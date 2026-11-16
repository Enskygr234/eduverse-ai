import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AiRouter } from './ai-router';
import { GeminiProvider } from './providers/gemini.provider';
import { GroqProvider } from './providers/groq.provider';

/**
 * AI engine foundation. Phase 4 adds the tutor endpoints, per-user quotas (Redis),
 * cost tracking in ai_messages and the review queue for generated content.
 */
@Module({
  providers: [
    {
      provide: AiRouter,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        new AiRouter(
          [
            new GeminiProvider(config.get('GEMINI_API_KEY'), config.getOrThrow('GEMINI_MODEL')),
            new GroqProvider(config.get('GROQ_API_KEY'), config.getOrThrow('GROQ_MODEL')),
          ],
          config.getOrThrow('AI_DEFAULT_PROVIDER'),
        ),
    },
  ],
  exports: [AiRouter],
})
export class AiModule {}
