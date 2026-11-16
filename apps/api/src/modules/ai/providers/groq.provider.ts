import { AiCompletion, AiCompletionRequest, AiProvider, AiProviderError, FetchFn } from './ai-provider';

/** Groq via its OpenAI-compatible chat completions endpoint. */
export class GroqProvider implements AiProvider {
  readonly name = 'groq' as const;

  constructor(
    private readonly apiKey: string | undefined,
    private readonly model: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  isConfigured(): boolean {
    return Boolean(this.apiKey);
  }

  async complete(req: AiCompletionRequest): Promise<AiCompletion> {
    if (!this.apiKey) throw new AiProviderError('Groq is not configured', this.name);
    const res = await this.fetchFn('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${this.apiKey}` },
      body: JSON.stringify({
        model: this.model,
        messages: req.messages,
        max_tokens: req.maxOutputTokens,
        temperature: req.temperature ?? 0.4,
      }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) throw new AiProviderError(`Groq request failed (${res.status})`, this.name, res.status);
    const body: any = await res.json();
    return {
      text: body.choices?.[0]?.message?.content ?? '',
      inputTokens: body.usage?.prompt_tokens ?? 0,
      outputTokens: body.usage?.completion_tokens ?? 0,
      provider: this.name,
      model: this.model,
    };
  }
}
