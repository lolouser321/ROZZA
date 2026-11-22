import {
  IAIProvider,
  AIMessage,
  AIProviderResponse,
  MusicIntent,
  AIToolDefinition,
  AIToolCall,
  AIConverseResult,
} from './AIProvider';

// ─────────────────────────────────────────────────────────────────────────────
// OllamaProvider — self-hosted, open-weight model option for local
// development (Phase 2's explicit requirement: "Architecture must NOT
// depend permanently on one model" / "Ollama development environment").
// Talks to a local or self-hosted Ollama server's OpenAI-shaped `/api/chat`
// endpoint. Multilingual open models that work well here for Arabic +
// English include the Qwen2.5 family (e.g. `qwen2.5:7b-instruct`) — set
// OLLAMA_MODEL to whichever one is actually pulled on the target machine;
// this class does not assume or fabricate one being present.
//
// Not the shipping default (ACTIVE_AI_PROVIDER defaults to openai/groq,
// hosted providers this backend already had working, real API keys for).
// This provider only activates when someone explicitly sets
// ACTIVE_AI_PROVIDER=ollama AND OLLAMA_BASE_URL — see AIProviderFactory.ts.
// No Ollama server is running in this environment, so this class's
// behavior against a live server is UNVERIFIED — DEV ENVIRONMENT REQUIRED;
// its request/response shaping is unit-tested against a mocked fetch.
// ─────────────────────────────────────────────────────────────────────────────

export class OllamaProvider implements IAIProvider {
  readonly providerName = 'ollama';
  readonly modelName: string;
  private readonly baseUrl: string | null;
  private _fetch: typeof fetch;

  constructor(fetchImpl: typeof fetch = fetch) {
    this.baseUrl = process.env.OLLAMA_BASE_URL ?? null;
    this.modelName = process.env.OLLAMA_MODEL ?? 'qwen2.5:7b-instruct';
    this._fetch = fetchImpl;
  }

  isConfigured(): boolean {
    return !!this.baseUrl;
  }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    if (!this.baseUrl) return { healthy: false, error: 'OLLAMA_BASE_URL not configured' };
    const started = Date.now();
    try {
      const res = await this._fetch(`${this.baseUrl}/api/tags`, { method: 'GET' });
      if (!res.ok) return { healthy: false, latencyMs: Date.now() - started, error: `HTTP ${res.status}` };
      return { healthy: true, latencyMs: Date.now() - started };
    } catch (error: any) {
      return { healthy: false, latencyMs: Date.now() - started, error: error?.message ?? 'Ollama unreachable' };
    }
  }

  async parseIntent(
    userMessage: string,
    conversationHistory: AIMessage[],
    context: {
      currentTrack?: { title: string; artist: string; genre: string; language: string } | null;
      recentListening?: string[];
      userPreferences?: { likedGenres: string[]; preferredLanguages: string[] };
    }
  ): Promise<AIProviderResponse> {
    if (!this.baseUrl) throw new Error('Ollama provider not configured — OLLAMA_BASE_URL missing');

    let contextNote = '';
    if (context.currentTrack) {
      contextNote = `\nCurrently playing: "${context.currentTrack.title}" by ${context.currentTrack.artist}`;
    }
    const systemContent = `You are ROZZA AI music intent engine. Return ONLY valid JSON matching this schema, nothing else:
{ "intent": "PLAY_MUSIC"|"CREATE_PLAYLIST"|"GET_INFO"|"CONTROL"|"RECOMMEND"|"UNKNOWN", "filters": {...}, "exclude": [], "duration": 0, "action": "SEARCH", "searchQuery": "", "explanation": "", "contextual": false }${contextNote}`;

    const body = {
      model: this.modelName,
      messages: [
        { role: 'system', content: systemContent },
        ...conversationHistory.map((m) => ({ role: m.role, content: m.content })),
        { role: 'user', content: userMessage },
      ],
      format: 'json',
      stream: false,
      options: { temperature: 0.1 },
    };
    const res = await this._fetch(`${this.baseUrl}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Ollama request failed: HTTP ${res.status}`);
    const json = (await res.json()) as { message?: { content?: string } };
    const rawText = json.message?.content ?? '{}';
    let intent: MusicIntent;
    try {
      intent = JSON.parse(rawText) as MusicIntent;
    } catch {
      intent = { intent: 'UNKNOWN', explanation: 'Failed to parse AI response' };
    }
    return { intent, rawText, provider: this.providerName, model: this.modelName };
  }

  async converse(messages: AIMessage[], tools: AIToolDefinition[], systemPrompt: string): Promise<AIConverseResult> {
    if (!this.baseUrl) throw new Error('Ollama provider not configured — OLLAMA_BASE_URL missing');

    const body = {
      model: this.modelName,
      messages: [{ role: 'system', content: systemPrompt }, ...messages.map((m) => ({ role: m.role, content: m.content }))],
      tools: tools.length
        ? tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }))
        : undefined,
      stream: false,
      options: { temperature: 0.4 },
    };
    const res = await this._fetch(`${this.baseUrl}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Ollama request failed: HTTP ${res.status}`);
    const json = (await res.json()) as {
      message?: { content?: string; tool_calls?: { function?: { name?: string; arguments?: any } }[] };
    };
    const rawText = json.message?.content ?? '';
    const toolCalls: AIToolCall[] = (json.message?.tool_calls ?? []).map((call, i) => ({
      id: `ollama-${i}`,
      name: call.function?.name ?? '',
      arguments:
        typeof call.function?.arguments === 'string'
          ? JSON.parse(call.function.arguments || '{}')
          : (call.function?.arguments ?? {}),
    }));
    return { reply: rawText, toolCalls, rawText: rawText || JSON.stringify(toolCalls), provider: this.providerName, model: this.modelName };
  }
}
