import { AiRouter } from './ai-router';
import { AiProviderError } from './providers/ai-provider';
import { GeminiProvider } from './providers/gemini.provider';
import { GroqProvider } from './providers/groq.provider';

const okJson = (body: unknown) => async () => ({ ok: true, status: 200, json: async () => body }) as any;
const fail = (status: number) => async () => ({ ok: false, status, json: async () => ({}) }) as any;
const req = { messages: [{ role: 'user' as const, content: 'Merhaba' }], maxOutputTokens: 5000 };

const geminiBody = {
  candidates: [{ content: { parts: [{ text: 'Gemini cevap' }] } }],
  usageMetadata: { promptTokenCount: 3, candidatesTokenCount: 4 },
};
const groqBody = { choices: [{ message: { content: 'Groq cevap' } }], usage: { prompt_tokens: 2, completion_tokens: 5 } };

describe('AI providers', () => {
  it('Gemini sends the key in a header and parses usage', async () => {
    let seenUrl = '';
    let seenHeaders: any;
    const fetchFn: any = async (url: string, init: any) => {
      seenUrl = url;
      seenHeaders = init.headers;
      return okJson(geminiBody)();
    };
    const out = await new GeminiProvider('secret-key', 'gemini-2.0-flash', fetchFn).complete(req);
    expect(out.text).toBe('Gemini cevap');
    expect(out.inputTokens).toBe(3);
    expect(seenUrl.includes('secret-key')).toBe(false);
    expect(seenHeaders['x-goog-api-key']).toBe('secret-key');
  });

  it('Groq parses OpenAI-style responses', async () => {
    const out = await new GroqProvider('k', 'llama', okJson(groqBody) as any).complete(req);
    expect(out).toEqual({ text: 'Groq cevap', inputTokens: 2, outputTokens: 5, provider: 'groq', model: 'llama' });
  });

  it('unconfigured providers refuse to run', async () => {
    await expect(new GroqProvider(undefined, 'llama').complete(req)).rejects.toBeInstanceOf(AiProviderError);
  });
});

describe('AiRouter', () => {
  it('uses the default provider first', async () => {
    const router = new AiRouter(
      [new GeminiProvider('a', 'g', okJson(geminiBody) as any), new GroqProvider('b', 'l', okJson(groqBody) as any)],
      'groq',
    );
    expect((await router.complete(req)).provider).toBe('groq');
  });

  it('falls back on upstream 5xx', async () => {
    const router = new AiRouter(
      [new GeminiProvider('a', 'g', fail(503) as any), new GroqProvider('b', 'l', okJson(groqBody) as any)],
      'gemini',
    );
    expect((await router.complete(req)).provider).toBe('groq');
  });

  it('does not fall back on a 400', async () => {
    const router = new AiRouter(
      [new GeminiProvider('a', 'g', fail(400) as any), new GroqProvider('b', 'l', okJson(groqBody) as any)],
      'gemini',
    );
    await expect(router.complete(req)).rejects.toBeInstanceOf(AiProviderError);
  });

  it('caps output tokens and rejects oversized input', async () => {
    let body: any;
    const fetchFn: any = async (_u: string, init: any) => {
      body = JSON.parse(init.body);
      return okJson(groqBody)();
    };
    const router = new AiRouter([new GroqProvider('b', 'l', fetchFn)], 'groq');
    await router.complete(req);
    expect(body.max_tokens).toBe(1024);
    await expect(
      router.complete({ messages: [{ role: 'user', content: 'x'.repeat(9000) }], maxOutputTokens: 10 }),
    ).rejects.toBeInstanceOf(AiProviderError);
  });

  it('reports no provider when no keys are set', async () => {
    const router = new AiRouter([new GeminiProvider(undefined, 'g'), new GroqProvider(undefined, 'l')], 'gemini');
    expect(router.available()).toEqual([]);
    await expect(router.complete(req)).rejects.toBeInstanceOf(AiProviderError);
  });
});
