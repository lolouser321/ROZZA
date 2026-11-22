// ─────────────────────────────────────────────────────────────────────────────
// ROZZA AI Provider Interface
// All LLM providers must implement this contract.
// Swap providers by changing ACTIVE_AI_PROVIDER in .env — no app code changes.
// ─────────────────────────────────────────────────────────────────────────────

export interface MusicIntent {
  intent: 'PLAY_MUSIC' | 'CREATE_PLAYLIST' | 'GET_INFO' | 'CONTROL' | 'RECOMMEND' | 'UNKNOWN';
  filters?: {
    language?: string[];       // ['ar', 'en']
    region?: string[];         // ['EG', 'GLOBAL']
    mood?: string[];           // ['party', 'romantic', 'relaxing']
    energy?: 'low' | 'medium' | 'medium_high' | 'high';
    genre?: string[];          // ['arabic_pop', 'mahraganat']
    artistTarget?: string;     // 'Amr Diab'
    trackTarget?: string;      // exact track name
    era?: string;              // 'classic', '2000s', 'new'
    occasion?: string[];       // ['wedding', 'gym', 'driving']
  };
  exclude?: string[];          // ['extreme_mahraganat', 'explicit']
  duration?: number;           // target playlist duration in minutes
  action?: 'PLAY_TRACK' | 'PLAY_ARTIST' | 'CREATE_PLAYLIST' | 'START_RADIO' |
           'ADD_TO_QUEUE' | 'PLAY_NEXT' | 'LIKE_TRACK' | 'OPEN_ARTIST' | 'SEARCH';
  searchQuery?: string;        // resolved search string if applicable
  explanation?: string;        // human-readable explanation of intent
  contextual?: boolean;        // true if referring to current track/queue
}

export interface AIMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface AIProviderResponse {
  intent: MusicIntent;
  rawText: string;
  provider: string;
  model: string;
}

export interface AIProviderConfig {
  name: string;
  model: string;
  isConfigured: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// Real conversational tool-calling (Phase 2 — "Real ROZZA AI"). A tool
// definition is a plain JSON-Schema function description; every provider
// that supports it maps `tools`/`toolCalls` onto its own native tool-calling
// API (OpenAI/Groq's `tools`, Ollama's `/api/chat` tools). The model only
// ever *proposes* a tool call by name + arguments — AIToolRunner.ts is the
// only code that actually executes one, after validating both the name
// (against a fixed allowlist) and the arguments (against a Zod schema).
// ─────────────────────────────────────────────────────────────────────────────

export interface AIToolDefinition {
  name: string;
  description: string;
  /** JSON-Schema for the tool's arguments object. */
  parameters: Record<string, any>;
}

export interface AIToolCall {
  id: string;
  name: string;
  arguments: Record<string, any>;
}

export interface AIConverseResult {
  /** Natural-language reply in the user's own language (Arabic, Egyptian
   *  Arabic, or English) — never omitted, even when tool calls are present,
   *  so the UI always has something to show while actions resolve. */
  reply: string;
  toolCalls: AIToolCall[];
  rawText: string;
  provider: string;
  model: string;
}

export interface IAIProvider {
  readonly providerName: string;
  readonly modelName: string;
  isConfigured(): boolean;
  healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }>;
  parseIntent(
    userMessage: string,
    conversationHistory: AIMessage[],
    context: {
      currentTrack?: { title: string; artist: string; genre: string; language: string } | null;
      recentListening?: string[];
      userPreferences?: { likedGenres: string[]; preferredLanguages: string[] };
    }
  ): Promise<AIProviderResponse>;
  /** Real multi-turn, tool-calling conversation — the engine behind
   *  Phase 2's ROZZA AI screen. `systemPrompt` already has the
   *  personalization context folded in (AIToolRunner.ts builds it). */
  converse(
    messages: AIMessage[],
    tools: AIToolDefinition[],
    systemPrompt: string
  ): Promise<AIConverseResult>;
}
