export interface AiChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface AiCompletionRequest {
  messages: AiChatMessage[];
  maxOutputTokens: number;
  temperature?: number;
}

export interface AiCompletion {
  text: string;
  inputTokens: number;
  outputTokens: number;
  provider: string;
  model: string;
}

export class AiProviderError extends Error {
  constructor(
    message: string,
    readonly provider: string,
    readonly status?: number,
  ) {
    super(message);
  }
}

/** Every AI vendor sits behind this interface; the rest of the app never calls a vendor SDK directly. */
export interface AiProvider {
  readonly name: 'gemini' | 'groq';
  isConfigured(): boolean;
  complete(request: AiCompletionRequest): Promise<AiCompletion>;
}

export type FetchFn = typeof fetch;
