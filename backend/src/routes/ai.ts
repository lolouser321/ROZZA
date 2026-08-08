import { Router, Request, Response } from 'express';
import { getAIProvider } from '../providers/ai/AIProviderFactory';
import { Catalog } from '../services/CatalogService';
import { YouTubeProvider } from '../providers/music/YouTubeProvider';
import { AudiusProvider } from '../providers/music/AudiusProvider';
import { JamendoProvider } from '../providers/music/JamendoProvider';
import { AIMessage } from '../providers/ai/AIProvider';
import { RozzaTrack, PlaylistResult } from '../types';
import { v4 as uuidv4 } from 'uuid';

const router = Router();
const youtube = new YouTubeProvider();
const audius = new AudiusProvider();
const jamendo = new JamendoProvider();

// In-memory conversation histories per session (production: use Redis/DB)
const conversationStore = new Map<string, AIMessage[]>();

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/ai/chat
// Main AI endpoint — converts natural language to structured intent + resolves tracks
// ─────────────────────────────────────────────────────────────────────────────
router.post('/chat', async (req: Request, res: Response) => {
  const { message, sessionId, currentTrack, recentListening, userPreferences } = req.body as {
    message: string;
    sessionId?: string;
    currentTrack?: { title: string; artist: string; genre: string; language: string } | null;
    recentListening?: string[];
    userPreferences?: { likedGenres: string[]; preferredLanguages: string[] };
  };

  if (!message?.trim()) {
    return res.status(400).json({ error: 'Message required' });
  }

  const ai = getAIProvider();
  if (!ai.isConfigured()) {
    return res.status(503).json({
      error: 'AI provider not configured',
      provider: ai.providerName,
      hint: process.env.NODE_ENV === 'development' ? `Set the credential for ACTIVE_AI_PROVIDER=${ai.providerName} in backend/.env` : undefined
    });
  }

  // Retrieve or create conversation history
  const sid = sessionId ?? uuidv4();
  let history = conversationStore.get(sid) ?? [];

  try {
    // Step 1: Parse user intent via AI
    const aiResponse = await ai.parseIntent(message, history, {
      currentTrack: currentTrack ?? null,
      recentListening,
      userPreferences
    });

    const intent = aiResponse.intent;

    // Step 2: Update conversation history
    history.push({ role: 'user', content: message });
    history.push({ role: 'assistant', content: aiResponse.rawText });
    if (history.length > 20) history = history.slice(-20); // Keep last 10 turns
    conversationStore.set(sid, history);

    // Step 3: Resolve REAL tracks based on intent (AI never invents track IDs)
    let resolvedTracks: RozzaTrack[] = [];
    let playlist: PlaylistResult | null = null;

    if (intent.intent !== 'GET_INFO' && intent.intent !== 'UNKNOWN') {
      resolvedTracks = await resolveTracks(intent);

      // Build playlist if requested
      if (intent.intent === 'CREATE_PLAYLIST' && resolvedTracks.length > 0) {
        const targetDurationSec = (intent.duration ?? 60) * 60;
        const playlistTracks = buildPlaylist(resolvedTracks, targetDurationSec);
        playlist = {
          id: `ai-pl-${uuidv4()}`,
          title: intent.explanation ?? 'ROZZA AI Mix',
          artwork: playlistTracks[0]?.artwork ?? '',
          tracks: playlistTracks,
          isAiGenerated: true,
          createdAt: new Date().toISOString()
        };
      }
    }

    return res.json({
      sessionId: sid,
      intent,
      tracks: resolvedTracks.slice(0, 20),
      playlist,
      explanation: intent.explanation,
      provider: aiResponse.provider,
      model: aiResponse.model
    });
  } catch (err: any) {
    console.error('[AI] Error:', err.message);
    return res.status(500).json({
      error: 'AI request failed',
      details: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Resolve real tracks from intent — catalog first, then YouTube
// AI NEVER invents song IDs. All tracks come from real providers.
// ─────────────────────────────────────────────────────────────────────────────
async function resolveTracks(intent: any): Promise<RozzaTrack[]> {
  const searchQuery = buildSearchQuery(intent);
  if (!searchQuery) return [];

  // 1. Catalog search
  let tracks = Catalog.search(searchQuery, 25);

  // 2. Apply intent filters to catalog results
  tracks = applyFilters(tracks, intent);

  // 3. Resolve legal native-audio providers before foreground-only YouTube.
  if (tracks.length < 5) {
    try {
      const limit = intent.intent === 'CREATE_PLAYLIST' ? 50 : 15;
      const resolved = await Promise.allSettled([
        audius.search(searchQuery, limit),
        jamendo.search(searchQuery, limit)
      ]);
      const nativeTracks = resolved.flatMap(r => r.status === 'fulfilled' ? r.value : []);
      if (nativeTracks.length > 0) {
        Catalog.upsertBatch(nativeTracks);
        const filtered = applyFilters(nativeTracks, intent);
        // Deduplicate
        const seen = new Set(tracks.map(t => t.id));
        for (const t of filtered) {
          if (!seen.has(t.id)) {
            seen.add(t.id);
            tracks.push(t);
          }
        }
      }
    } catch (err: any) { console.error('[AI resolve] Native provider error:', err.message); }
  }

  if (tracks.length < 5 && youtube.isConfigured()) {
    try {
      const ytResult = await youtube.search(searchQuery, intent.intent === 'CREATE_PLAYLIST' ? 50 : 15);
      Catalog.upsertBatch(ytResult.tracks);
      const seen = new Set(tracks.map(t => t.id));
      for (const t of applyFilters(ytResult.tracks, intent)) if (!seen.has(t.id)) { seen.add(t.id); tracks.push(t); }
    } catch (err: any) { console.error('[AI resolve] YouTube fallback error:', err.message); }
  }

  return tracks.sort((a, b) => Number(b.sources.some(s => s.canBackgroundPlay)) - Number(a.sources.some(s => s.canBackgroundPlay)) || b.popularity - a.popularity);
}

function buildSearchQuery(intent: any): string {
  const parts: string[] = [];

  if (intent.filters?.artistTarget) parts.push(intent.filters.artistTarget);
  if (intent.filters?.trackTarget) parts.push(intent.filters.trackTarget);

  if (!parts.length) {
    // Build from genre/language
    if (intent.filters?.language?.includes('ar')) {
      if (intent.filters?.region?.includes('EG')) parts.push('Egyptian Arabic music');
      else parts.push('Arabic music');
    }
    if (intent.filters?.genre?.length) parts.push(intent.filters.genre[0].replace('_', ' '));
    if (intent.filters?.mood?.length) parts.push(intent.filters.mood[0]);
    if (intent.filters?.occasion?.length) parts.push(intent.filters.occasion[0]);
  }

  return parts.join(' ').trim() || intent.searchQuery || '';
}

function applyFilters(tracks: RozzaTrack[], intent: any): RozzaTrack[] {
  let filtered = [...tracks];

  if (intent.filters?.language?.length) {
    filtered = filtered.filter(t => intent.filters.language.includes(t.language) || t.language === 'other');
  }

  if (intent.exclude?.length) {
    filtered = filtered.filter(t => {
      const genre = (t.genre ?? '').toLowerCase();
      return !intent.exclude.some((ex: string) => genre.includes(ex.replace('_', '').toLowerCase()));
    });
  }

  if (intent.filters?.energy === 'high') {
    filtered.sort((a, b) => b.popularity - a.popularity);
  } else if (intent.filters?.energy === 'low') {
    filtered.sort((a, b) => a.popularity - b.popularity);
  }

  return filtered;
}

function buildPlaylist(tracks: RozzaTrack[], targetDurationSec: number): RozzaTrack[] {
  const result: RozzaTrack[] = [];
  let total = 0;

  // Deduplicate by artist to avoid repeats
  const artistCount = new Map<string, number>();

  for (const track of tracks) {
    if (total >= targetDurationSec) break;
    const count = artistCount.get(track.artist) ?? 0;
    if (count >= 3) continue; // max 3 tracks per artist

    result.push(track);
    total += track.durationSeconds ?? 210;
    artistCount.set(track.artist, count + 1);
  }

  return result;
}

export default router;
