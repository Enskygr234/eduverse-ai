import { Global, Injectable, Logger, Module } from '@nestjs/common';

export interface MailMessage {
  to: string;
  subject: string;
  text: string;
}

/**
 * Mail transport abstraction. The "console" transport only logs messages and is
 * meant for development; production must plug in a real provider (SES, Postmark, ...)
 * before email verification and password reset can reach users.
 */
@Injectable()
export class MailService {
  private readonly logger = new Logger('Mail');
  /** Last messages, kept in memory so tests can read links. Not used in production. */
  readonly outbox: MailMessage[] = [];

  async send(message: MailMessage): Promise<void> {
    this.outbox.push(message);
    if (this.outbox.length > 50) this.outbox.shift();
    this.logger.log(`[console transport] to=${message.to} subject="${message.subject}"\n${message.text}`);
  }
}

@Global()
@Module({ providers: [MailService], exports: [MailService] })
export class MailModule {}
