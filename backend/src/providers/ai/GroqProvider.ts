import Groq from 'groq-sdk';
import { IAIProvider, AIMessage, AIProviderResponse, MusicIntent } from './AIProvider';

const SYSTEM_PROMPT = `You are ROZZA AI, the intelligent music intent engine for ROZZA — a premium Arabic and global music app.

Your ONLY job is to convert user messages into structured music intents as JSON.

You MUST return ONLY valid JSON. No markdown. No explanation. No text before or after the JSON.

JSON Schema:
{
  "intent": "PLAY_MUSIC" | "CREATE_PLAYLIST" | "GET_INFO" | "CONTROL" | "RECOMMEND" | "UNKNOWN",
  "filters": {
    "language": ["ar"] | ["en"] | ["ar","en"],
    "region": ["EG"] | ["GLOBAL"] | ["EG","GLOBAL"],
    "mood": ["party"] | ["romantic"] | ["relaxing"] | ["energetic"] | ["sad"] | ["happy"],
    "energy": "low" | "medium" | "medium_high" | "high",
    "genre": ["arabic_pop"] | ["mahraganat"] | ["shaabi"] | ["classic_arabic"] | ["electronic"] | ["pop"],
    "artistTarget": "Artist name in English",
    "trackTarget": "Track name",
    "era": "classic" | "2000s" | "2010s" | "new",
    "occasion": ["wedding"] | ["gym"] | ["driving"] | ["studying"] | ["sleeping"] | ["party"]
  },
  "exclude": ["extreme_mahraganat"] | ["explicit"] | [],
  "duration": 120,
  "action": "PLAY_TRACK" | "PLAY_ARTIST" | "CREATE_PLAYLIST" | "START_RADIO" | "ADD_TO_QUEUE" | "LIKE_TRACK" | "SEARCH",
  "searchQuery": "resolved English + Arabic search string",
  "explanation": "Brief human-readable summary of what you understood",
  "contextual": false
}

Key rules:
- Arabic text like "عمرو دياب" maps to artistTarget="Amr Diab" and language=["ar"]
- Franco-Arabic like "3amr diab" maps to artistTarget="Amr Diab"  
- "Mahraganat" is Egyptian street music — high energy, party genre
- "Not crazy" / "not too aggressive" = energy:"medium_high" + exclude:["extreme_mahraganat"]
- Wedding music in Egypt = arabic_pop + shaabi + classic_arabic, occasion:["wedding"]
- Contextual queries ("Who is this?", "More like this", "Save this") = contextual:true
- If user wants info only, use GET_INFO intent
- NEVER invent song IDs or claim specific tracks exist
- duration field = requested playlist length in minutes`;

export class GroqProvider implements IAIProvider {
  readonly providerName = 'groq';
  readonly modelName = 'llama-3.3-70b-versatile';

  private client: Groq | null = null;

  constructor() {
    const key = process.env.GROQ_API_KEY;
    if (key) {
      this.client = new Groq({ apiKey: key });
    }
  }

  isConfigured(): boolean {
    return !!this.client;
  }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    if (!this.client) return { healthy: false, error: 'GROQ_API_KEY not configured' };
    const started = Date.now();
    try {
      await this.client.models.list();
      return { healthy: true, latencyMs: Date.now() - started };
    } catch (error: any) {
      return { healthy: false, latencyMs: Date.now() - started, error: error?.message ?? 'Groq check failed' };
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
      throw new Error('Groq provider not configured — GROQ_API_KEY missing');
    }

    // Build context injection
    let contextNote = '';
    if (context.currentTrack) {
      contextNote = `\nCurrently playing: "${context.currentTrack.title}" by ${context.currentTrack.artist} (${context.currentTrack.genre}, ${context.currentTrack.language})`;
    }
    if (context.recentListening?.length) {
      contextNote += `\nRecently listened: ${context.recentListening.slice(0, 5).join(', ')}`;
    }

    const messages: Groq.Chat.ChatCompletionMessageParam[] = [
      { role: 'system', content: SYSTEM_PROMPT + contextNote },
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
      intent = { intent: 'UNKNOWN', explanation: 'Failed to parse AI response' };
    }

    return {
      intent,
      rawText,
      provider: this.providerName,
      model: this.modelName
    };
  }
}
