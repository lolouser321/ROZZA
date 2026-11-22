import axios from 'axios';
import { RozzaTrack } from '../../types';

const JAMENDO_BASE = 'https://api.jamendo.com/v3.0';

export class JamendoProvider {
  private readonly clientId = process.env.JAMENDO_CLIENT_ID ?? '';
  isConfigured(): boolean { return Boolean(this.clientId); }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    if (!this.clientId) return { healthy: false, error: 'JAMENDO_CLIENT_ID not configured' };
    const started = Date.now();
    try {
      await this.search('music', 1);
      return { healthy: true, latencyMs: Date.now() - started };
    } catch (error: any) {
      return { healthy: false, latencyMs: Date.now() - started, error: error?.message ?? 'Jamendo unavailable' };
    }
  }

  async search(query: string, limit = 15): Promise<RozzaTrack[]> {
    if (!this.clientId) return [];
    const response = await axios.get(`${JAMENDO_BASE}/tracks/`, {
      params: {
        client_id: this.clientId, format: 'json', limit, search: query,
        include: 'musicinfo licenses stats', audioformat: 'mp32', imagesize: 500,
        type: 'single albumtrack'
      }, timeout: 10000
    });
    const now = new Date().toISOString();
    return (response.data?.results ?? []).filter((item: any) => item.audio).map((item: any): RozzaTrack => ({
      id: `jamendo-${item.id}`,
      title: item.name || 'Untitled', artist: item.artist_name || 'Unknown Artist',
      album: item.album_name || undefined, artwork: item.image || item.album_image || '',
      durationSeconds: Number(item.duration) || undefined,
      language: item.musicinfo?.lang === 'ar' ? 'ar' : item.musicinfo?.vocalinstrumental === 'instrumental' ? 'instrumental' : 'other',
      region: 'GLOBAL', genre: item.musicinfo?.tags?.genres?.[0] || undefined,
      popularity: Math.min(100, Math.max(1, Math.round(Math.log10((item.stats?.listened_all || 0) + 1) * 18))),
      aliases: [item.name, item.artist_name, item.album_name].filter(Boolean),
      sources: [{
        provider: 'jamendo', providerId: String(item.id), url: item.audio,
        canPlay: true, canBackgroundPlay: true,
        canDownload: Boolean(item.audiodownload_allowed && item.audiodownload),
        canOfflinePlay: false, supportsLockScreen: true, supportsControlCenter: true
      }],
      discoveredAt: now, updatedAt: now
    }));
  }
}
