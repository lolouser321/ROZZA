import axios from 'axios';
import FormData from 'form-data';

// ─────────────────────────────────────────────────────────────────────────────
// AudD Music Recognition Provider
// https://audd.io/ — identify songs from audio samples
// ─────────────────────────────────────────────────────────────────────────────

export interface RecognitionResult {
  found: boolean;
  title?: string;
  artist?: string;
  album?: string;
  releaseDate?: string;
  label?: string;
  timecode?: string;
  youtubeLink?: string;
  appleMusic?: {
    previewUrl?: string;
    artworkUrl?: string;
  };
}

export class AudDProvider {
  private readonly token: string | null;
  private readonly endpoint = 'https://api.audd.io/';

  constructor() {
    this.token = process.env.AUDD_API_KEY ?? process.env.AUDD_API_TOKEN ?? null;
  }

  isConfigured(): boolean {
    return !!this.token;
  }

  async healthCheck(): Promise<{ healthy: boolean; error?: string }> {
    if (!this.token) return { healthy: false, error: 'AUDD_API_KEY not configured' };
    // AudD doesn't have a dedicated health endpoint — we just verify the token is set
    return { healthy: true };
  }

  // Recognize from an external URL (e.g. a stream URL or publicly accessible audio)
  async recognizeFromUrl(url: string): Promise<RecognitionResult> {
    if (!this.token) throw new Error('AudD not configured');

    const resp = await axios.post(this.endpoint, null, {
      params: {
        url,
        return: 'apple_music,spotify',
        api_token: this.token
      },
      timeout: 15000
    });

    return this.parseAudDResponse(resp.data);
  }

  // Recognize from raw audio buffer (uploaded by iPhone microphone)
  async recognizeFromBuffer(audioBuffer: Buffer, mimeType = 'audio/mp4'): Promise<RecognitionResult> {
    if (!this.token) throw new Error('AudD not configured');

    const form = new FormData();
    form.append('api_token', this.token);
    form.append('return', 'apple_music,spotify,youtube');
    form.append('file', audioBuffer, { filename: 'sample.m4a', contentType: mimeType });

    const resp = await axios.post(this.endpoint, form, {
      headers: form.getHeaders(),
      timeout: 15000
    });

    return this.parseAudDResponse(resp.data);
  }

  private parseAudDResponse(data: any): RecognitionResult {
    if (data.status !== 'success' || !data.result) {
      return { found: false };
    }

    const r = data.result;
    return {
      found: true,
      title: r.title,
      artist: r.artist,
      album: r.album,
      releaseDate: r.release_date,
      label: r.label,
      timecode: r.timecode,
      youtubeLink: r.youtube_link ?? undefined,
      appleMusic: r.apple_music ? {
        previewUrl: r.apple_music.previews?.[0]?.url,
        artworkUrl: r.apple_music.artwork?.url?.replace('{w}', '400').replace('{h}', '400')
      } : undefined
    };
  }
}
