import axios from 'axios';
import { RozzaTrack, TrackSource, ArtistResult } from '../../types';
import { v4 as uuidv4 } from 'uuid';
import { decodeHtmlEntities } from '../../utils/text';

// ─────────────────────────────────────────────────────────────────────────────
// YouTube Data API v3 Provider
// Uses official search.list endpoint — no stream extraction, no ToS violation.
// Results are video metadata only. Playback via YouTube's official iframe/player.
// ─────────────────────────────────────────────────────────────────────────────

const YT_BASE = 'https://www.googleapis.com/youtube/v3';

// Music-focused category IDs for ranking
const MUSIC_CATEGORY_ID = '10'; // YouTube Music category

// Words that indicate non-music content — deprioritised
const NON_MUSIC_KEYWORDS = ['trailer', 'podcast', 'news', 'lecture', 'gameplay', 'tutorial'];

export interface YouTubeSearchItem {
  videoId: string;
  title: string;
  channelName: string;
  thumbnail: string;
  publishedAt?: string;
  durationIso?: string;
  viewCount?: number;
}

export class YouTubeProvider {
  private readonly apiKey: string | null;
  private static quotaDay = new Date().toISOString().slice(0, 10);
  private static quotaUnitsUsed = 0;

  constructor() {
    this.apiKey = process.env.YOUTUBE_API_KEY ?? null;
  }

  isConfigured(): boolean {
    return !!this.apiKey;
  }

  private reserveQuota(units: number): void {
    const today = new Date().toISOString().slice(0, 10);
    if (YouTubeProvider.quotaDay !== today) {
      YouTubeProvider.quotaDay = today;
      YouTubeProvider.quotaUnitsUsed = 0;
    }
    const budget = Math.max(0, parseInt(process.env.YOUTUBE_DAILY_QUOTA_UNITS ?? '9000', 10));
    if (YouTubeProvider.quotaUnitsUsed + units > budget) {
      throw new Error('YouTube discovery budget exhausted; catalog-only mode is active');
    }
    YouTubeProvider.quotaUnitsUsed += units;
  }

  async healthCheck(): Promise<{ healthy: boolean; latencyMs?: number; error?: string }> {
    if (!this.apiKey) return { healthy: false, error: 'YOUTUBE_API_KEY not configured' };
    const start = Date.now();
    try {
      this.reserveQuota(1);
      await axios.get(`${YT_BASE}/videos`, {
        params: { part: 'id', chart: 'mostPopular', videoCategoryId: MUSIC_CATEGORY_ID, maxResults: 1, key: this.apiKey },
        timeout: 5000
      });
      return { healthy: true, latencyMs: Date.now() - start };
    } catch (err: any) {
      return { healthy: false, latencyMs: Date.now() - start, error: err?.message };
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Full music search — filters heavily toward music content
  // ──────────────────────────────────────────────────────────────────
  async search(query: string, maxResults = 15): Promise<{ tracks: RozzaTrack[]; artists: ArtistResult[] }> {
    if (!this.apiKey) throw new Error('YOUTUBE_API_KEY not configured');
    this.reserveQuota(101); // search.list (100) + videos.list (1)

    // Append "music" to bias toward music results for generic queries
    const musicQuery = this.isMusicBiasNeeded(query) ? `${query} music` : query;

    const searchResp = await axios.get(`${YT_BASE}/search`, {
      params: {
        part: 'snippet',
        q: musicQuery,
        type: 'video',
        videoEmbeddable: 'true',
        videoSyndicated: 'true',
        videoCategoryId: MUSIC_CATEGORY_ID,
        maxResults,
        order: 'relevance',
        key: this.apiKey,
        safeSearch: 'none',
        relevanceLanguage: 'ar' // bias toward Arabic where relevant
      },
      timeout: 8000
    });

    const items: any[] = searchResp.data.items ?? [];

    if (items.length === 0) return { tracks: [], artists: [] };

    // Fetch durations + view counts in one batch call
    const videoIds = items.map((i: any) => i.id.videoId).join(',');
    const detailResp = await axios.get(`${YT_BASE}/videos`, {
      params: {
        part: 'contentDetails,statistics,snippet,status',
        id: videoIds,
        key: this.apiKey
      },
      timeout: 8000
    });

    const detailMap = new Map<string, any>();
    for (const d of detailResp.data.items ?? []) {
      detailMap.set(d.id, d);
    }

    const tracks: RozzaTrack[] = [];
    const artistSet = new Map<string, ArtistResult>();

    for (const item of items) {
      const videoId = item.id.videoId;
      const snippet = item.snippet;
      const detail = detailMap.get(videoId);

      // Search results are metadata, not a playback guarantee. Only advertise
      // a video as playable after videos.list confirms that the owner permits
      // embedding and the upload is publicly available.
      if (!detail || detail.status?.embeddable !== true || detail.status?.privacyStatus !== 'public') continue;

      const title: string = decodeHtmlEntities(snippet.title ?? '');
      const channelName: string = decodeHtmlEntities(snippet.channelName ?? snippet.channelTitle ?? '');

      // Skip non-music content
      if (this.isNonMusic(title, channelName)) continue;

      const thumbnail = snippet.thumbnails?.high?.url ?? snippet.thumbnails?.default?.url ?? '';
      const publishedAt: string = snippet.publishedAt ?? '';
      const durationSec = detail ? this.parseISODuration(detail.contentDetails?.duration) : undefined;
      const viewCount = detail ? parseInt(detail.statistics?.viewCount ?? '0', 10) : 0;

      // Parse title into track/artist
      const { trackTitle, artistName } = this.parseMusicTitle(title, channelName);

      const source: TrackSource = {
        provider: 'youtube',
        providerId: videoId,
        channelName,
        viewCount,
        publishedAt,
        canBackgroundPlay: false, // YouTube ToS: no background without YouTube Premium
        canDownload: false,
        canPlay: true,
        canOfflinePlay: false,
        supportsLockScreen: false,
        supportsControlCenter: false
      };

      const track: RozzaTrack = {
        id: `yt-${videoId}`,
        title: trackTitle,
        artist: artistName,
        artwork: thumbnail,
        durationSeconds: durationSec,
        language: this.detectLanguage(title),
        region: this.detectRegion(title, channelName),
        genre: this.detectGenre(title),
        popularity: Math.min(100, Math.floor((viewCount / 1_000_000) * 5)), // views → 0-100
        aliases: this.buildAliases(trackTitle, artistName),
        sources: [source],
        discoveredAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      tracks.push(track);

      // Collect artist data
      if (!artistSet.has(artistName)) {
        artistSet.set(artistName, {
          name: artistName,
          channelId: snippet.channelId,
          thumbnail,
          trackCount: 1,
          aliases: this.buildAliases(artistName, '')
        });
      } else {
        const existing = artistSet.get(artistName)!;
        existing.trackCount = (existing.trackCount ?? 0) + 1;
      }
    }

    return { tracks, artists: Array.from(artistSet.values()) };
  }

  // ──────────────────────────────────────────────────────────────────
  // Trending music — uses YouTube's mostPopular music chart
  // ──────────────────────────────────────────────────────────────────
  async getTrending(regionCode = 'EG', maxResults = 20): Promise<RozzaTrack[]> {
    if (!this.apiKey) throw new Error('YOUTUBE_API_KEY not configured');
    this.reserveQuota(1);

    const resp = await axios.get(`${YT_BASE}/videos`, {
      params: {
        part: 'snippet,contentDetails,statistics,status',
        chart: 'mostPopular',
        videoCategoryId: MUSIC_CATEGORY_ID,
        regionCode,
        maxResults,
        key: this.apiKey
      },
      timeout: 8000
    });

    return (resp.data.items ?? [])
      .filter((item: any) => item.status?.embeddable === true && item.status?.privacyStatus === 'public')
      .map((item: any) => {
      const { trackTitle, artistName } = this.parseMusicTitle(
        decodeHtmlEntities(item.snippet.title ?? ''),
        decodeHtmlEntities(item.snippet.channelTitle ?? '')
      );
      const viewCount = parseInt(item.statistics?.viewCount ?? '0', 10);
      const videoId = item.id;

      return {
        id: `yt-${videoId}`,
        title: trackTitle,
        artist: artistName,
        artwork: item.snippet.thumbnails?.high?.url ?? '',
        durationSeconds: this.parseISODuration(item.contentDetails?.duration),
        language: this.detectLanguage(item.snippet.title ?? ''),
        region: regionCode,
        genre: this.detectGenre(item.snippet.title ?? ''),
        popularity: Math.min(100, Math.floor((viewCount / 1_000_000) * 5)),
        aliases: this.buildAliases(trackTitle, artistName),
        sources: [{
          provider: 'youtube' as const,
          providerId: videoId,
          channelName: item.snippet.channelTitle,
          viewCount,
          publishedAt: item.snippet.publishedAt,
          canBackgroundPlay: false,
          canDownload: false,
          canPlay: true,
          canOfflinePlay: false,
          supportsLockScreen: false,
          supportsControlCenter: false
        }],
        discoveredAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      } as RozzaTrack;
      });
  }

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────

  private isMusicBiasNeeded(query: string): boolean {
    // Don't append "music" if query already contains music-related terms
    const musicTerms = ['song', 'music', 'official', 'audio', 'lyrics', 'موسيقى', 'أغنية', 'كليب'];
    const lower = query.toLowerCase();
    return !musicTerms.some(t => lower.includes(t));
  }

  private isNonMusic(title: string, channel: string): boolean {
    const combined = `${title} ${channel}`.toLowerCase();
    return NON_MUSIC_KEYWORDS.some(kw => combined.includes(kw));
  }

  private parseMusicTitle(title: string, channelName: string): { trackTitle: string; artistName: string } {
    // Try "Artist - Title" pattern (most common on YouTube)
    const dashMatch = title.match(/^(.+?)\s*[-–—|]\s*(.+)$/);
    if (dashMatch) {
      return { artistName: dashMatch[1].trim(), trackTitle: dashMatch[2].replace(/\(.*?\)/g, '').trim() };
    }
    // Fallback: use channel as artist, clean title
    return {
      artistName: channelName.replace(/ (VEVO|Official|Music|Channel|Records)/gi, '').trim(),
      trackTitle: title.replace(/\(Official.*?\)/gi, '').replace(/\[.*?\]/g, '').trim()
    };
  }

  private parseISODuration(iso?: string): number | undefined {
    if (!iso) return undefined;
    const match = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
    if (!match) return undefined;
    return (parseInt(match[1] ?? '0') * 3600) + (parseInt(match[2] ?? '0') * 60) + parseInt(match[3] ?? '0');
  }

  private detectLanguage(text: string): 'ar' | 'en' | 'other' {
    // Simple Arabic script detection
    if (/[\u0600-\u06FF]/.test(text)) return 'ar';
    return 'en';
  }

  private detectRegion(title: string, channel: string): string {
    const text = `${title} ${channel}`.toLowerCase();
    const egyptKeywords = ['مصر', 'egypt', 'cairo', 'القاهرة', 'محمد', 'عمرو', 'احمد', 'هاني', 'مهرجان'];
    if (egyptKeywords.some(k => text.includes(k))) return 'EG';
    return 'GLOBAL';
  }

  private detectGenre(title: string): string {
    const t = title.toLowerCase();
    if (t.includes('مهرجان') || t.includes('mahraganat') || t.includes('مهرجانات')) return 'mahraganat';
    if (t.includes('شعبي') || t.includes('sha3bi') || t.includes('shaabi')) return 'shaabi';
    if (t.includes('كلاسيك') || t.includes('classic') || t.includes('زمان')) return 'classic_arabic';
    return 'arabic_pop';
  }

  private buildAliases(title: string, artist: string): string[] {
    const aliases = new Set<string>();
    const addVariants = (text: string) => {
      if (!text) return;
      aliases.add(text.toLowerCase());
      // Transliteration hints
      aliases.add(text.toLowerCase().replace(/a/g, 'e').replace(/3/g, 'a'));
    };
    addVariants(title);
    addVariants(artist);
    return Array.from(aliases).filter(Boolean);
  }
}
