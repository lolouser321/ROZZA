// ─────────────────────────────────────────────────────────────────────────────
// ROZZA Shared Types — used by both backend and (via API contract) the iPhone
// ─────────────────────────────────────────────────────────────────────────────

export interface RozzaTrack {
  id: string;              // rozza-generated stable ID
  title: string;
  artist: string;
  album?: string;
  artwork: string;
  durationSeconds?: number;
  language: 'ar' | 'en' | 'instrumental' | 'other';
  region?: string;
  genre?: string;
  popularity: number;      // 0-100
  aliases: string[];
  sources: TrackSource[];
  discoveredAt: string;    // ISO timestamp
  updatedAt: string;
}

export interface TrackSource {
  provider: 'youtube' | 'audius' | 'jamendo' | 'direct' | 'spotify' | 'apple_music' | 'local';
  providerId: string;      // e.g. YouTube videoId
  url?: string;            // only for non-YouTube/non-protected sources
  channelName?: string;
  viewCount?: number;
  publishedAt?: string;
  canBackgroundPlay: boolean;
  canDownload: boolean;
  canPlay: boolean;
  canOfflinePlay: boolean;
  supportsLockScreen: boolean;
  supportsControlCenter: boolean;
}

export interface SearchResult {
  tracks: RozzaTrack[];
  topResult?: RozzaTrack;
  artists?: ArtistResult[];
  playlists?: PlaylistResult[];
  totalResults: number;
  source: 'catalog' | 'audius' | 'jamendo' | 'spotify' | 'youtube' | 'mixed';
  cached: boolean;
  query: string;
}

export interface ArtistResult {
  name: string;
  channelId?: string;
  thumbnail?: string;
  trackCount?: number;
  aliases: string[];
}

export interface PlaylistResult {
  id: string;
  title: string;
  artwork: string;
  tracks: RozzaTrack[];
  isAiGenerated: boolean;
  createdAt: string;
}

export interface ProviderHealth {
  name: string;
  configured: boolean;
  healthy: boolean;
  latencyMs?: number;
  error?: string;
}

export interface HealthReport {
  status: 'ok' | 'degraded' | 'down';
  providers: Record<string, ProviderHealth>;
  catalog: { healthy: boolean; trackCount: number; cacheEntries: number };
  timestamp: string;
}
