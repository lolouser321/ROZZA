import OpenAI from 'openai';
import { IAIProvider, AIMessage, AIProviderResponse, MusicIntent } from './AIProvider';

// OpenAI provider — set ACTIVE_AI_PROVIDER=openai in .env and provide OPENAI_API_KEY
// Uses gpt-4o-mini for cost efficiency; swap model in OPENAI_MODEL env var
export class OpenAIProvider implements IAIProvider {
  readonly providerName = 'openai';
  readonly modelName: string;

  private client: OpenAI | null = null;

  constructor() {
    const key = process.env.OPENAI_API_KEY;
    this.modelName = process.env.OPENAI_MODEL ?? 'gpt-4o-mini';
    if (key) {
      this.client = new OpenAI({ apiKey: key });
    }
  }

  isConfigured(): boolean {
    return !!this.client;
  }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    if (!this.client) return { healthy: false, error: 'OPENAI_API_KEY not configured' };
    const started = Date.now();
    try {
      await this.client.models.retrieve(this.modelName);
      return { healthy: true, latencyMs: Date.now() - started };
    } catch (error: any) {
      return { healthy: false, latencyMs: Date.now() - started, error: error?.message ?? 'OpenAI check failed' };
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
    if (!this.client) {
      throw new Error('OpenAI provider not configured — OPENAI_API_KEY missing');
    }

    let contextNote = '';
    if (context.currentTrack) {
      contextNote = `\nCurrently playing: "${context.currentTrack.title}" by ${context.currentTrack.artist}`;
    }

    const systemContent = `You are ROZZA AI music intent engine. Return ONLY valid JSON matching the MusicIntent schema. No markdown, no explanation.
Schema: { intent, filters: { language, region, mood, energy, genre, artistTarget, trackTarget, era, occasion }, exclude, duration, action, searchQuery, explanation, contextual }${contextNote}`;

    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: 'system', content: systemContent },
      ...conversationHistory.map(m => ({
        role: m.role as 'user' | 'assistant',
        content: m.content
      })),
      { role: 'user', content: userMessage }
    ];

    const response = await this.client.chat.completions.create({
      model: this.modelName,
      messages,
      temperature: 0.1,
      max_tokens: 600,
      response_format: { type: 'json_object' }
    });

    const rawText = response.choices[0]?.message?.content ?? '{}';
    let intent: MusicIntent;
    try {
      intent = JSON.parse(rawText) as MusicIntent;
    } catch {
      intent = { intent: 'UNKNOWN', explanation: 'Parse error' };
    }

    return { intent, rawText, provider: this.providerName, model: this.modelName };
  }
}
