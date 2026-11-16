import { AiCompletion, AiCompletionRequest, AiProvider, AiProviderError, FetchFn } from './ai-provider';

/** Google Gemini via the generateContent REST endpoint. The key is sent as a header, never in URLs or logs. */
export class GeminiProvider implements AiProvider {
  readonly name = 'gemini' as const;

  constructor(
    private readonly apiKey: string | undefined,
    private readonly model: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  isConfigured(): boolean {
    return Boolean(this.apiKey);
  }

  async complete(req: AiCompletionRequest): Promise<AiCompletion> {
    if (!this.apiKey) throw new AiProviderError('Gemini is not configured', this.name);
    const system = req.messages.filter((m) => m.role === 'system').map((m) => m.content).join('\n');
    const contents = req.messages
      .filter((m) => m.role !== 'system')
      .map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));

    const res = await this.fetchFn(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(this.model)}:generateContent`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': this.apiKey },
        body: JSON.stringify({
          ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
          contents,
          generationConfig: { maxOutputTokens: req.maxOutputTokens, temperature: req.temperature ?? 0.4 },
        }),
        signal: AbortSignal.timeout(30_000),
      },
    );
    if (!res.ok) throw new AiProviderError(`Gemini request failed (${res.status})`, this.name, res.status);
    const body: any = await res.json();
    const text: string = (body.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? '').join('');
    return {
      text,
      inputTokens: body.usageMetadata?.promptTokenCount ?? 0,
      outputTokens: body.usageMetadata?.candidatesTokenCount ?? 0,
      provider: this.name,
      model: this.model,
    };
  }
}
