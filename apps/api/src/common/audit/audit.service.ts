import { Global, Injectable, Logger, Module } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

type Tx = Prisma.TransactionClient;

@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Records a security-relevant event. Pass `tx` to write inside a running transaction.
   * Never put secrets (passwords, tokens) in metadata.
   */
  async log(
    action: string,
    opts: { userId?: string | null; ip?: string | null; metadata?: Prisma.InputJsonValue; tx?: Tx } = {},
  ): Promise<void> {
    const client = opts.tx ?? this.prisma;
    try {
      await client.auditLog.create({
        data: { action, userId: opts.userId ?? null, ip: opts.ip ?? null, metadata: opts.metadata },
      });
    } catch (err) {
      if (opts.tx) throw err;
      this.logger.error(`Failed to write audit log for ${action}`, err as Error);
    }
  }
}

@Global()
@Module({ providers: [AuditService], exports: [AuditService] })
export class AuditModule {}
