import { Router, Request, Response } from 'express';
import { YouTubeProvider } from '../providers/music/YouTubeProvider';
import { AudiusProvider } from '../providers/music/AudiusProvider';
import { JamendoProvider } from '../providers/music/JamendoProvider';
import { Catalog } from '../services/CatalogService';
import { MemoryCache } from '../services/SearchCache';
import { RozzaTrack } from '../types';

// ─────────────────────────────────────────────────────────────────────────────
// v2 — the shape the SwiftUI client consumes.
//
// Separate from /api/search/* so the React Native app keeps working unchanged.
// Differences that matter to the iOS app:
//   • `contentType` on every result, so the filter chips have something to bind
//   • typed sources carrying an honest `canPlayInBackground`
//   • real pagination (`page`, `hasMore`) instead of one fixed batch
//   • a `source` selector distinguishing YouTube Music from YouTube at large
// ─────────────────────────────────────────────────────────────────────────────

const router = Router();
const youtube = new YouTubeProvider();
const audius = new AudiusProvider();
const jamendo = new JamendoProvider();

type SearchSource = 'youtubeMusic' | 'youtube';
type SearchFilter = 'all' | 'songs' | 'videos' | 'artists' | 'playlists';
type ContentType = 'song' | 'video' | 'artist' | 'playlist';

interface ClientSource {
  provider: 'youtube' | 'local' | 'licensed';
  providerID: string;
  url?: string;
  canPlayInBackground: boolean;
  supportsSeeking: boolean;
  isDownloadable: boolean;
}

interface ClientTrack {
  id: string;
  title: string;
  artist: string;
  album?: string;
  artworkURL?: string;
  duration?: number;
  contentType: ContentType;
  sources: ClientSource[];
}

const PAGE_SIZE_MAX = 50;

function normalizeQuery(q: string): string {
  return q.toLowerCase().trim()
    .replace(/[أإآ]/g, 'ا')
    .replace(/[ىئ]/g, 'ي')
    .replace(/ة/g, 'ه');
}

/**
 * A "- Topic" channel or an official artist upload is a song; a long clip, a
 * live set or a reaction is a video. This is heuristic — YouTube exposes no
 * authoritative song/video flag through the Data API — but it is what makes
 * the Songs and Videos tabs meaningfully different.
 */
function classify(track: RozzaTrack): ContentType {
  const channel = (track.sources[0]?.channelName ?? '').toLowerCase();
  const title = track.title.toLowerCase();

  // Audio-only providers have no video to speak of, so anything that isn't
  // backed by YouTube is a song by definition — the title heuristics below only
  // make sense for YouTube uploads.
  if (!track.sources.some(source => source.provider === 'youtube')) return 'song';

  if (channel.endsWith('- topic') || channel.endsWith('- موضوع')) return 'song';
  if (/\b(live|concert|حفلة|حفل|reaction|cover|remix|mix|compilation|full album|البوم كامل)\b/.test(title)) {
    return 'video';
  }
  // Anything over ~12 minutes is not a single track.
  if ((track.durationSeconds ?? 0) > 12 * 60) return 'video';
  if (/(official (music )?video|lyrics|audio|كليب|اغنية)/.test(title)) return 'song';
  return 'video';
}

function toClientTrack(track: RozzaTrack): ClientTrack {
  const sources: ClientSource[] = track.sources
    .map((source): ClientSource | null => {
      switch (source.provider) {
        case 'youtube':
          return {
            provider: 'youtube',
            providerID: source.providerId,
            // The embedded player is suspended at lock and YouTube's terms
            // don't permit background audio. Never claim otherwise.
            canPlayInBackground: false,
            supportsSeeking: true,
            isDownloadable: false
          };
        case 'audius':
        case 'jamendo':
        case 'direct':
          // Real audio URLs the app may stream itself.
          return source.url ? {
            provider: 'licensed',
            providerID: source.providerId,
            url: source.url,
            canPlayInBackground: true,
            supportsSeeking: true,
            isDownloadable: source.canDownload
          } : null;
        default:
          return null;
      }
    })
    .filter((source): source is ClientSource => source !== null);

  return {
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    artworkURL: track.artwork || undefined,
    duration: track.durationSeconds,
    contentType: classify(track),
    sources
  };
}

function admits(filter: SearchFilter, type: ContentType): boolean {
  switch (filter) {
    case 'all': return true;
    case 'songs': return type === 'song';
    case 'videos': return type === 'video';
    case 'artists': return type === 'artist';
    case 'playlists': return type === 'playlist';
    default: return true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v2/search
// ─────────────────────────────────────────────────────────────────────────────
router.post('/search', async (req: Request, res: Response) => {
  const {
    query,
    source = 'youtubeMusic',
    filter = 'all',
    page = 0,
    pageSize = 20
  } = req.body as {
    query: string; source?: SearchSource; filter?: SearchFilter; page?: number; pageSize?: number;
  };

  if (!query || query.trim().length < 2) {
    return res.status(400).json({ error: 'Query too short' });
  }

  const limit = Math.min(Math.max(1, Number(pageSize) || 20), PAGE_SIZE_MAX);
  const pageIndex = Math.max(0, Number(page) || 0);
  const norm = normalizeQuery(query);

  // The upstream providers have no cursor, so a generous first fetch is cached
  // and paged locally. That keeps page 2 free rather than costing a second
  // YouTube search (100 quota units each).
  const cacheKey = `v2:${source}:${norm}`;

  try {
    let pool: ClientTrack[] | undefined = MemoryCache.get(cacheKey);

    if (!pool) {
      const results = await Promise.allSettled([
        audius.search(query, 20),
        jamendo.search(query, 20),
        youtube.isConfigured()
          ? youtube.search(source === 'youtubeMusic' ? `${query} official audio` : query, 25)
              .then(r => r.tracks)
          : Promise.resolve([] as RozzaTrack[])
      ]);

      const discovered = results.flatMap(r => r.status === 'fulfilled' ? r.value : []);
      if (discovered.length > 0) Catalog.upsertBatch(discovered);

      const merged = new Map<string, ClientTrack>();
      for (const track of [...Catalog.search(query.trim(), 15), ...discovered]) {
        const client = toClientTrack(track);
        if (client.sources.length === 0) continue;   // nothing playable, drop it
        const key = `${client.title}|${client.artist}`.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
        if (!merged.has(key)) merged.set(key, client);
      }

      pool = [...merged.values()].sort((a, b) => {
        // Background-capable first, then the provider's own ordering.
        const rank = (t: ClientTrack) => (t.sources.some(s => s.canPlayInBackground) ? 0 : 1);
        return rank(a) - rank(b);
      });

      const ttl = parseInt(process.env.SEARCH_CACHE_TTL_MINUTES ?? '60', 10);
      MemoryCache.set(cacheKey, pool, ttl * 60 * 1000);
    }

    // YouTube Music mode prefers real songs over clips.
    const scoped = source === 'youtubeMusic'
      ? pool.filter(track => track.contentType === 'song' || track.sources.some(s => s.canPlayInBackground))
      : pool;

    const filtered = scoped.filter(track => admits(filter as SearchFilter, track.contentType));
    const start = pageIndex * limit;
    const slice = filtered.slice(start, start + limit);

    return res.json({
      tracks: slice,
      hasMore: start + limit < filtered.length,
      totalResults: filtered.length
    });
  } catch (err: any) {
    console.error('[v2/search] Error:', err.message);
    return res.status(500).json({ error: 'Search temporarily unavailable' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v2/autocomplete — catalog only, never spends YouTube quota
// ─────────────────────────────────────────────────────────────────────────────
router.post('/autocomplete', (req: Request, res: Response) => {
  const { query } = req.body as { query: string };
  if (!query || !query.trim()) return res.json({ suggestions: [] });

  const norm = normalizeQuery(query);
  const cacheKey = `v2:auto:${norm}`;
  const cached = MemoryCache.get(cacheKey);
  if (cached) return res.json({ suggestions: cached });

  const tracks = [...Catalog.search(query.trim(), 8), ...Catalog.search(norm, 8)];
  const suggestions = Array.from(new Set([
    ...tracks.map(t => t.title),
    ...tracks.map(t => t.artist)
  ])).filter(Boolean).slice(0, 8);

  MemoryCache.set(cacheKey, suggestions, 5 * 60 * 1000);
  return res.json({ suggestions });
});

export default router;
