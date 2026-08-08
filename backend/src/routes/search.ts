import { Router, Request, Response } from 'express';
import { YouTubeProvider } from '../providers/music/YouTubeProvider';
import { AudiusProvider } from '../providers/music/AudiusProvider';
import { JamendoProvider } from '../providers/music/JamendoProvider';
import { SpotifyProvider } from '../providers/music/SpotifyProvider';
import { Catalog } from '../services/CatalogService';
import { MemoryCache } from '../services/SearchCache';
import { SearchResult, RozzaTrack } from '../types';

const router = Router();
const youtube = new YouTubeProvider();
const audius = new AudiusProvider();
const jamendo = new JamendoProvider();
const spotify = new SpotifyProvider();

// ─────────────────────────────────────────────────────────────────────────────
// Multilingual text normalizer — handles Arabic, Franco-Arabic, English
// ─────────────────────────────────────────────────────────────────────────────
function normalizeQuery(q: string): string {
  return q
    .toLowerCase()
    .trim()
    // Franco-Arabic number substitutions
    .replace(/3/g, 'a')
    .replace(/7/g, 'h')
    .replace(/2/g, "'")
    .replace(/5/g, 'kh')
    // Arabic vowel normalization
    .replace(/[أإآ]/g, 'ا')
    .replace(/[ىئ]/g, 'ي')
    .replace(/ة/g, 'ه');
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/search/autocomplete
// Fast — catalog/cache only. NO YouTube call.
// ─────────────────────────────────────────────────────────────────────────────
router.post('/autocomplete', (req: Request, res: Response) => {
  const { query } = req.body as { query: string };
  if (!query || query.trim().length < 1) {
    return res.json({ suggestions: [] });
  }

  const norm = normalizeQuery(query);
  const cacheKey = `autocomplete:${norm}`;

  const cached = MemoryCache.get(cacheKey);
  if (cached) return res.json({ suggestions: cached, cached: true });

  // Catalog-only autocomplete
  const results = dedupeTracks([
    ...Catalog.search(query.trim(), 8),
    ...Catalog.search(norm, 8)
  ]).slice(0, 8);
  const suggestions = Array.from(new Set([
    ...results.map(t => t.title),
    ...results.map(t => t.artist)
  ])).slice(0, 6);

  MemoryCache.set(cacheKey, suggestions, 5 * 60 * 1000); // 5 min TTL for autocomplete
  return res.json({ suggestions, cached: false });
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/search/full
// Full search: catalog → Audius/Jamendo → YouTube fallback → persist
// ─────────────────────────────────────────────────────────────────────────────
router.post('/full', async (req: Request, res: Response) => {
  const { query } = req.body as { query: string };
  if (!query || query.trim().length < 2) {
    return res.status(400).json({ error: 'Query too short' });
  }

  const norm = normalizeQuery(query);
  // Version the key whenever provider semantics change so legacy YouTube-only
  // responses cannot shadow native-audio results after an app update.
  const cacheKey = `search:v5:${norm}`;

  // L1: memory cache
  const memoryCached = MemoryCache.get(cacheKey);
  if (memoryCached) return res.json({ ...memoryCached, cached: true });

  // L2: SQLite cache
  const dbCached = Catalog.getCachedSearch(cacheKey);
  if (dbCached) {
    MemoryCache.set(cacheKey, dbCached.results);
    return res.json({ ...dbCached.results, cached: true });
  }

  try {
    // Step 1: Search local catalog
    const catalogTracks = dedupeTracks([
      ...Catalog.search(query.trim(), 10),
      ...Catalog.search(norm, 10)
    ]).slice(0, 10);

    let discoveredTracks: RozzaTrack[] = [];
    let artists: any[] = [];
    let source: SearchResult['source'] = 'catalog';

    // Step 2: Query the background-capable catalogs first. Spotify is included
    // here because App Remote keeps playing when the screen locks, even though
    // the audio comes out of the Spotify app rather than ROZZA.
    const providerResults = await Promise.allSettled([
      audius.search(query, 15),
      jamendo.search(query, 15),
      spotify.search(query, 15)
    ]);
    const settled = (index: number): RozzaTrack[] =>
      providerResults[index].status === 'fulfilled' ? (providerResults[index] as PromiseFulfilledResult<RozzaTrack[]>).value : [];
    discoveredTracks.push(...settled(0), ...settled(1), ...settled(2));

    // Step 3: YouTube is metadata + visible foreground playback fallback only.
    if (catalogTracks.length + discoveredTracks.length < 12 && youtube.isConfigured()) {
      try {
        const ytResult = await youtube.search(query, 15);
        discoveredTracks.push(...ytResult.tracks);
        artists = ytResult.artists;
      } catch (ytErr: any) {
        console.error('[YouTube] Search fallback failed:', ytErr.message);
      }
    }

    if (discoveredTracks.length > 0) {
      Catalog.upsertBatch(discoveredTracks);
      const providerNames = new Set(discoveredTracks.map(t => t.sources[0]?.provider));
      source = catalogTracks.length || providerNames.size > 1 ? 'mixed' :
        providerNames.has('audius') ? 'audius'
          : providerNames.has('jamendo') ? 'jamendo'
            : providerNames.has('spotify') ? 'spotify' : 'youtube';
    }

    // Native-playable sources rank first; equivalent metadata merges into one track.
    const mergedTracks = mergeTracks([...catalogTracks, ...discoveredTracks], query);

    const topResult = mergedTracks[0] ?? null;

    const result: SearchResult = {
      tracks: mergedTracks,
      topResult: topResult ?? undefined,
      artists,
      totalResults: mergedTracks.length,
      source,
      cached: false,
      query
    };

    // Cache the result
    const ttl = parseInt(process.env.SEARCH_CACHE_TTL_MINUTES ?? '60', 10);
    MemoryCache.set(cacheKey, result, ttl * 60 * 1000);
    Catalog.setCachedSearch(cacheKey, query, result, ttl);

    return res.json(result);
  } catch (err: any) {
    console.error('[Search] Error:', err.message);
    return res.status(500).json({
      error: 'Search temporarily unavailable',
      details: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
  }
});

function dedupeTracks(tracks: RozzaTrack[]): RozzaTrack[] {
  const seenIds = new Set<string>();
  const seenMetadata = new Set<string>();
  return tracks.filter(track => {
    const metadataKey = `${track.title}|${track.artist}`.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
    if (seenIds.has(track.id) || seenMetadata.has(metadataKey)) return false;
    seenIds.add(track.id);
    seenMetadata.add(metadataKey);
    return true;
  });
}

/** Query tokens, normalized the same way the search text is. */
function tokenize(value: string): string[] {
  return normalizeQuery(value)
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .split(' ')
    .filter(token => token.length > 1);
}

/**
 * Coarse 0-4 relevance so background-capability can only break ties between
 * comparably relevant results. Without this, one loosely-matching Audius track
 * outranks the song the listener actually searched for, purely because it
 * survives the screen locking.
 */
function relevanceBucket(track: RozzaTrack, queryTokens: string[]): number {
  if (queryTokens.length === 0) return 0;
  const haystack = normalizeQuery(
    `${track.title} ${track.artist} ${track.album ?? ''} ${track.aliases.join(' ')}`
  );
  const matched = queryTokens.filter(token => haystack.includes(token)).length;
  return Math.round((matched / queryTokens.length) * 4);
}

function mergeTracks(tracks: RozzaTrack[], query: string): RozzaTrack[] {
  const merged = new Map<string, RozzaTrack>();
  for (const track of tracks) {
    const key = `${track.title}|${track.artist}`.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
    const existing = merged.get(key);
    if (!existing) {
      merged.set(key, { ...track, sources: [...track.sources] });
      continue;
    }
    const sourceIds = new Set(existing.sources.map(s => `${s.provider}:${s.providerId}`));
    for (const source of track.sources) {
      if (!sourceIds.has(`${source.provider}:${source.providerId}`)) existing.sources.push(source);
    }
    existing.popularity = Math.max(existing.popularity, track.popularity);
    if (!existing.artwork && track.artwork) existing.artwork = track.artwork;
  }
  const queryTokens = tokenize(query);
  return [...merged.values()].sort((a, b) => {
    // Relevance first, then whether it survives the screen locking, then reach.
    const relevance = relevanceBucket(b, queryTokens) - relevanceBucket(a, queryTokens);
    if (relevance !== 0) return relevance;
    const aNative = a.sources.some(s => s.canBackgroundPlay) ? 1 : 0;
    const bNative = b.sources.some(s => s.canBackgroundPlay) ? 1 : 0;
    return bNative - aNative || b.popularity - a.popularity;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/search/trending?region=EG
// ─────────────────────────────────────────────────────────────────────────────
router.get('/trending', async (req: Request, res: Response) => {
  const region = (req.query.region as string) ?? 'EG';
  const cacheKey = `trending:v2:${region}`;

  const cached = MemoryCache.get(cacheKey);
  if (cached) return res.json({ tracks: cached, cached: true });

  // Fetch the actual regional chart first. Search discoveries must never turn
  // into trending entries merely because somebody searched for them.
  if (youtube.isConfigured()) {
    try {
      const ytRegion = region === 'EG' ? 'EG' : region === 'Arabic' ? 'SA' : 'US';
      const ytTracks = await youtube.getTrending(ytRegion, 20);

      if (ytTracks.length > 0) {
        Catalog.upsertBatch(ytTracks);
        ytTracks.forEach((t, i) => {
          Catalog.upsertTrending(t.id, region, Math.max(0, 100 - i * 4));
        });

        const ttl = parseInt(process.env.TRENDING_CACHE_TTL_MINUTES ?? '30', 10);
        MemoryCache.set(cacheKey, ytTracks, ttl * 60 * 1000);
        return res.json({ tracks: ytTracks, region, cached: false, source: 'youtube' });
      }
    } catch (err: any) {
      console.error('[Trending] YouTube error:', err.message);
    }
  }

  // Provider unavailable: use only previously stored entries for this exact
  // region. Never blend GLOBAL rows into Egypt/Arabic charts.
  const catalogTrending = Catalog.getTrending(region, 20);
  if (catalogTrending.length > 0) {
    MemoryCache.set(cacheKey, catalogTrending, 5 * 60 * 1000);
    return res.json({ tracks: catalogTrending, region, cached: false, source: 'catalog-fallback' });
  }

  // Nothing available — return empty (no fake data)
  return res.json({ tracks: [], region, cached: false, source: 'none', message: 'No trending data available yet' });
});

export default router;
