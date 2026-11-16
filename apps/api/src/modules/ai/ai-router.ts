import { AiCompletion, AiCompletionRequest, AiProvider, AiProviderError } from './providers/ai-provider';

export const AI_LIMITS = {
  maxInputChars: 8_000,
  maxOutputTokens: 1_024,
};

/**
 * Picks the configured default provider and falls back to the other one on
 * upstream failures (5xx / 429). Input size and output tokens are capped here so
 * no caller can run up costs by accident.
 */
export class AiRouter {
  constructor(
    private readonly providers: AiProvider[],
    private readonly defaultProvider: 'gemini' | 'groq',
  ) {}

  available(): string[] {
    return this.providers.filter((p) => p.isConfigured()).map((p) => p.name);
  }

  async complete(req: AiCompletionRequest): Promise<AiCompletion> {
    const inputChars = req.messages.reduce((n, m) => n + m.content.length, 0);
    if (inputChars > AI_LIMITS.maxInputChars) throw new AiProviderError('Input too long', 'router', 413);
    const capped = { ...req, maxOutputTokens: Math.min(req.maxOutputTokens, AI_LIMITS.maxOutputTokens) };

    const ordered = [...this.providers]
      .filter((p) => p.isConfigured())
      .sort((a, b) => Number(b.name === this.defaultProvider) - Number(a.name === this.defaultProvider));
    if (ordered.length === 0) throw new AiProviderError('No AI provider is configured', 'router', 503);

    let lastError: unknown;
    for (const provider of ordered) {
      try {
        return await provider.complete(capped);
      } catch (err) {
        lastError = err;
        const status = err instanceof AiProviderError ? err.status : undefined;
        const retryable = status === undefined || status === 429 || status >= 500;
        if (!retryable) throw err;
      }
    }
    throw lastError;
  }
}
