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
}
