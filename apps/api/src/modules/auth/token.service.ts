import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { randomToken, safeEqualHex, sha256 } from './crypto.util';

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresIn: number;
}

export interface ClientMeta {
  ip?: string;
  userAgent?: string;
}

/**
 * Access tokens: short-lived JWTs.
 * Refresh tokens: opaque "<id>.<secret>" strings, stored hashed, rotated on every use.
 * Re-using a rotated refresh token revokes the whole token family (theft detection).
 */
@Injectable()
export class TokenService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly audit: AuditService,
  ) {}

  async issueSession(userId: string, meta: ClientMeta, familyId: string = randomUUID()): Promise<SessionTokens> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { roles: { include: { role: true } } },
    });
    const ttl = this.config.getOrThrow<number>('JWT_ACCESS_TTL_SECONDS');
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, roles: user.roles.map((r) => r.role.key), typ: 'access' },
      { expiresIn: ttl },
    );

    const secret = randomToken();
    const row = await this.prisma.refreshToken.create({
      data: {
        userId,
        familyId,
        tokenHash: sha256(secret),
        expiresAt: this.refreshExpiry(),
        ip: meta.ip?.slice(0, 64),
        userAgent: meta.userAgent?.slice(0, 256),
      },
    });
    return { accessToken, refreshToken: `${row.id}.${secret}`, accessTokenExpiresIn: ttl };
  }

  async rotate(refreshToken: string, meta: ClientMeta): Promise<SessionTokens> {
    const [id, secret] = refreshToken.split('.');
    if (!id || !secret) throw new UnauthorizedException('Invalid refresh token');

    const row = await this.prisma.refreshToken.findUnique({ where: { id }, include: { user: true } });
    if (!row || !safeEqualHex(row.tokenHash, sha256(secret))) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (row.revokedAt) {
      await this.revokeFamily(row.familyId);
      await this.audit.log('auth.refresh_reuse_detected', { userId: row.userId, ip: meta.ip, metadata: { familyId: row.familyId } });
      throw new UnauthorizedException('Refresh token reuse detected; please sign in again');
    }
    if (row.expiresAt <= new Date()) throw new UnauthorizedException('Refresh token expired');
    if (row.user.status !== 'ACTIVE') throw new UnauthorizedException('Account is not active');

    // Conditional update: only one concurrent request can claim this token.
    const claimed = await this.prisma.refreshToken.updateMany({
      where: { id: row.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (claimed.count === 0) {
      await this.revokeFamily(row.familyId);
      throw new UnauthorizedException('Refresh token reuse detected; please sign in again');
    }

    const session = await this.issueSession(row.userId, meta, row.familyId);
    const newId = session.refreshToken.split('.')[0];
    await this.prisma.refreshToken.update({ where: { id: row.id }, data: { replacedById: newId } });
    return session;
  }

  /** Logout: revokes the family the presented token belongs to. Silent on unknown tokens. */
  async revoke(refreshToken: string): Promise<void> {
    const [id, secret] = refreshToken.split('.');
    if (!id || !secret) return;
    const row = await this.prisma.refreshToken.findUnique({ where: { id } });
    if (row && safeEqualHex(row.tokenHash, sha256(secret))) await this.revokeFamily(row.familyId);
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  private async revokeFamily(familyId: string): Promise<void> {
    await this.prisma.refreshToken.updateMany({ where: { familyId, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  private refreshExpiry(): Date {
    const days = this.config.getOrThrow<number>('REFRESH_TOKEN_TTL_DAYS');
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  }
}
