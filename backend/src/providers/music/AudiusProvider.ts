import axios from 'axios';
import { RozzaTrack } from '../../types';

const AUDIUS_BASE = 'https://api.audius.co/v1';

export class AudiusProvider {
  private readonly apiKey = process.env.AUDIUS_API_KEY ?? '';

  isConfigured(): boolean { return true; }

  private headers() {
    return this.apiKey ? { 'x-api-key': this.apiKey } : undefined;
  }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    const started = Date.now();
    try {
      await axios.get(`${AUDIUS_BASE}/tracks/search`, {
        params: { query: 'music', limit: 1, app_name: 'ROZZA' }, headers: this.headers(), timeout: 7000
      });
      return { healthy: true, latencyMs: Date.now() - started };
    } catch (error: any) {
      return { healthy: false, latencyMs: Date.now() - started, error: error?.message ?? 'Audius unavailable' };
    }
  }

  async search(query: string, limit = 15): Promise<RozzaTrack[]> {
    const response = await axios.get(`${AUDIUS_BASE}/tracks/search`, {
      params: { query, limit, app_name: 'ROZZA' }, headers: this.headers(), timeout: 10000
    });
    const now = new Date().toISOString();
    return (response.data?.data ?? [])
      .filter((item: any) => item.is_streamable !== false && item.stream?.url)
      .map((item: any): RozzaTrack => ({
        id: `audius-${item.id}`,
        title: item.title || 'Untitled',
        artist: item.user?.name || item.user?.handle || 'Unknown Artist',
        album: item.album_backlink?.title || undefined,
        artwork: item.artwork?.['480x480'] || item.artwork?.['150x150'] || '',
        durationSeconds: Number(item.duration) || undefined,
        language: /[\u0600-\u06FF]/.test(item.title || '') ? 'ar' : 'other',
        region: 'GLOBAL',
        genre: item.genre || undefined,
        popularity: Math.min(100, Math.max(1, Math.round(Math.log10((item.play_count || 0) + 1) * 18))),
        aliases: [item.title, item.user?.name, item.user?.handle].filter(Boolean),
        sources: [{
          provider: 'audius', providerId: item.id, url: item.stream.url,
          canPlay: true, canBackgroundPlay: true,
          canDownload: Boolean(item.is_downloadable && item.download?.url),
          canOfflinePlay: false, supportsLockScreen: true, supportsControlCenter: true
        }],
        discoveredAt: now, updatedAt: now
      }));
  }
}
