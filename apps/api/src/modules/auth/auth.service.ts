import { BadRequestException, ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, TokenPurpose } from '@prisma/client';
import * as argon2 from 'argon2';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { MailService } from '../mail/mail.service';
import { ClientMeta, SessionTokens, TokenService } from './token.service';
import { RegisterDto, LoginDto } from './dto/auth.dto';
import { randomToken, sha256 } from './crypto.util';

const ARGON_OPTIONS: argon2.Options = { type: argon2.argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 };
const VERIFICATION_TTL_MS = 24 * 60 * 60 * 1000;
const RESET_TTL_MS = 30 * 60 * 1000;

// Hash used to equalise timing when the email does not exist.
let dummyHashPromise: Promise<string> | undefined;
const dummyHash = () => (dummyHashPromise ??= argon2.hash('dummy-password-for-timing', ARGON_OPTIONS));

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TokenService,
    private readonly audit: AuditService,
    private readonly mail: MailService,
    private readonly config: ConfigService,
  ) {}

  async register(dto: RegisterDto, meta: ClientMeta): Promise<SessionTokens> {
    const passwordHash = await argon2.hash(dto.password, ARGON_OPTIONS);
    let userId: string;
    try {
      const user = await this.prisma.$transaction(async (tx) => {
        const created = await tx.user.create({
          data: {
            email: dto.email,
            passwordHash,
            profile: { create: { displayName: dto.displayName } },
            streak: { create: {} },
          },
        });
        const learner = await tx.role.findUnique({ where: { key: 'learner' } });
        if (learner) await tx.userRole.create({ data: { userId: created.id, roleId: learner.id } });
        await this.audit.log('auth.register', { userId: created.id, ip: meta.ip, tx });
        return created;
      });
      userId = user.id;
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new ConflictException('An account with this email already exists');
      }
      throw err;
    }

    await this.sendVerificationEmail(userId, dto.email);
    return this.tokens.issueSession(userId, meta);
  }

  async login(dto: LoginDto, meta: ClientMeta): Promise<SessionTokens> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    const valid = user
      ? await argon2.verify(user.passwordHash, dto.password)
      : (await argon2.verify(await dummyHash(), dto.password), false);

    if (!user || !valid) {
      await this.audit.log('auth.login_failed', { userId: user?.id, ip: meta.ip });
      throw new UnauthorizedException('Email or password is incorrect');
    }
    if (user.status !== 'ACTIVE') throw new UnauthorizedException('Account is not active');

    await this.prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    await this.audit.log('auth.login', { userId: user.id, ip: meta.ip });
    return this.tokens.issueSession(user.id, meta);
  }

  refresh(refreshToken: string, meta: ClientMeta): Promise<SessionTokens> {
    return this.tokens.rotate(refreshToken, meta);
  }

  logout(refreshToken: string): Promise<void> {
    return this.tokens.revoke(refreshToken);
  }

  async verifyEmail(token: string): Promise<void> {
    const row = await this.consumeOneTimeToken(token, TokenPurpose.EMAIL_VERIFICATION);
    await this.prisma.user.update({ where: { id: row.userId }, data: { emailVerifiedAt: new Date() } });
    await this.audit.log('auth.email_verified', { userId: row.userId });
  }

  async resendVerification(userId: string): Promise<void> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (user.emailVerifiedAt) return;
    await this.sendVerificationEmail(user.id, user.email);
  }

  /** Always succeeds from the caller's view so the endpoint cannot be used to probe emails. */
  async forgotPassword(email: string): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || user.status !== 'ACTIVE') return;
    const token = await this.createOneTimeToken(user.id, TokenPurpose.PASSWORD_RESET, RESET_TTL_MS);
    await this.mail.send({
      to: user.email,
      subject: 'EduVerse AI şifre sıfırlama',
      text: `Şifreni sıfırlamak için kod: ${token}\nBu kod 30 dakika geçerlidir.`,
    });
    await this.audit.log('auth.password_reset_requested', { userId: user.id });
  }

  async resetPassword(token: string, newPassword: string): Promise<void> {
    const row = await this.consumeOneTimeToken(token, TokenPurpose.PASSWORD_RESET);
    const passwordHash = await argon2.hash(newPassword, ARGON_OPTIONS);
    await this.prisma.user.update({ where: { id: row.userId }, data: { passwordHash } });
    await this.tokens.revokeAllForUser(row.userId);
    await this.audit.log('auth.password_reset', { userId: row.userId });
  }

  private async sendVerificationEmail(userId: string, email: string): Promise<void> {
    const token = await this.createOneTimeToken(userId, TokenPurpose.EMAIL_VERIFICATION, VERIFICATION_TTL_MS);
    const base = this.config.get<string>('APP_PUBLIC_URL');
    await this.mail.send({
      to: email,
      subject: 'EduVerse AI e-posta doğrulama',
      text: `E-postanı doğrulamak için kod: ${token}\nveya ${base}/auth/verify-email?token=${token}`,
    });
  }

  private async createOneTimeToken(userId: string, purpose: TokenPurpose, ttlMs: number): Promise<string> {
    const token = randomToken(24);
    await this.prisma.$transaction([
      this.prisma.oneTimeToken.updateMany({
        where: { userId, purpose, consumedAt: null },
        data: { consumedAt: new Date() },
      }),
      this.prisma.oneTimeToken.create({
        data: { userId, purpose, tokenHash: sha256(token), expiresAt: new Date(Date.now() + ttlMs) },
      }),
    ]);
    return token;
  }

  private async consumeOneTimeToken(token: string, purpose: TokenPurpose) {
    const row = await this.prisma.oneTimeToken.findUnique({ where: { tokenHash: sha256(token) } });
    if (!row || row.purpose !== purpose || row.consumedAt || row.expiresAt <= new Date()) {
      throw new BadRequestException('Token is invalid or expired');
    }
    const claimed = await this.prisma.oneTimeToken.updateMany({
      where: { id: row.id, consumedAt: null },
      data: { consumedAt: new Date() },
    });
    if (claimed.count === 0) throw new BadRequestException('Token is invalid or expired');
    return row;
  }
}
