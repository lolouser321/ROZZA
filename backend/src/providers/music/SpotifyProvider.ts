import axios from 'axios';
import { RozzaTrack } from '../../types';

const SPOTIFY_ACCOUNTS = 'https://accounts.spotify.com/api/token';
const SPOTIFY_API = 'https://api.spotify.com/v1';

// ─────────────────────────────────────────────────────────────────────────────
// SpotifyProvider — catalog *search* only.
//
// Client-credentials tokens can read the catalog but never stream audio. That
// is deliberate: playback happens on the device through the App Remote SDK,
// which asks the installed Spotify app to play the URI. No audio passes
// through this server, and the client secret never leaves it.
// ─────────────────────────────────────────────────────────────────────────────

export class SpotifyProvider {
  private readonly clientId = process.env.SPOTIFY_CLIENT_ID ?? '';
  private readonly clientSecret = process.env.SPOTIFY_CLIENT_SECRET ?? '';

  private token: string | null = null;
  private tokenExpiresAt = 0;

  isConfigured(): boolean {
    return Boolean(this.clientId && this.clientSecret);
  }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    if (!this.isConfigured()) {
      return { healthy: false, error: 'SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET not configured' };
    }
    const started = Date.now();
    try {
      await this.search('music', 1);
      return { healthy: true, latencyMs: Date.now() - started };
    } catch (error: any) {
      return { healthy: false, latencyMs: Date.now() - started, error: error?.message ?? 'Spotify unavailable' };
    }
  }

  private async accessToken(): Promise<string> {
    // Tokens last an hour; refresh a minute early to avoid a mid-request expiry.
    if (this.token && Date.now() < this.tokenExpiresAt - 60_000) return this.token;

    const basic = Buffer.from(`${this.clientId}:${this.clientSecret}`).toString('base64');
    const response = await axios.post(
      SPOTIFY_ACCOUNTS,
      new URLSearchParams({ grant_type: 'client_credentials' }).toString(),
      {
        headers: {
          Authorization: `Basic ${basic}`,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        timeout: 10000
      }
    );

    this.token = response.data.access_token;
    this.tokenExpiresAt = Date.now() + (response.data.expires_in ?? 3600) * 1000;
    return this.token!;
  }

  async search(query: string, limit = 15): Promise<RozzaTrack[]> {
    if (!this.isConfigured()) return [];

    const token = await this.accessToken();
    const response = await axios.get(`${SPOTIFY_API}/search`, {
      params: { q: query, type: 'track', limit: Math.min(limit, 50) },
      headers: { Authorization: `Bearer ${token}` },
      timeout: 10000
    });

    const now = new Date().toISOString();
    return (response.data?.tracks?.items ?? []).map((item: any): RozzaTrack => ({
      id: `spotify-${item.id}`,
      title: item.name || 'Untitled',
      artist: item.artists?.map((a: any) => a.name).join(', ') || 'Unknown Artist',
      album: item.album?.name || undefined,
      artwork: item.album?.images?.[0]?.url ?? '',
      durationSeconds: item.duration_ms ? Math.round(item.duration_ms / 1000) : undefined,
      language: 'other',
      region: item.album?.available_markets?.includes('EG') ? 'EG' : 'GLOBAL',
      popularity: typeof item.popularity === 'number' ? item.popularity : 50,
      aliases: [item.name, ...(item.artists?.map((a: any) => a.name) ?? []), item.album?.name].filter(Boolean),
      sources: [{
        provider: 'spotify',
        providerId: item.id,
        canPlay: true,
        // App Remote hands playback to the Spotify app, which keeps going when
        // the screen locks — but the Lock Screen then belongs to Spotify.
        canBackgroundPlay: true,
        canDownload: false,
        canOfflinePlay: false,
        supportsLockScreen: false,
        supportsControlCenter: false
      }],
      discoveredAt: now,
      updatedAt: now
    }));
  }
}
