import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';
import { getAIProvider } from '../providers/ai/AIProviderFactory';
import { AIMessage, AIToolCall, AIToolDefinition } from '../providers/ai/AIProvider';
import { Catalog } from './CatalogService';
import { YouTubeProvider } from '../providers/music/YouTubeProvider';
import { AudiusProvider } from '../providers/music/AudiusProvider';
import { JamendoProvider } from '../providers/music/JamendoProvider';
import { sharedSocialService } from './SocialService';
import { sharedSocialDb } from '../db/socialDb';
import { RozzaTrack } from '../types';

// ─────────────────────────────────────────────────────────────────────────────
// AIToolRunner — the ONLY bridge between what an LLM says and anything real
// happening. This is the Phase 2 "controlled application tools" system:
//
//   model proposes { name, arguments }
//     -> looked up in TOOL_REGISTRY by exact name (unknown name = dropped)
//     -> arguments parsed with that tool's Zod schema (invalid = dropped)
//     -> 'server' tools are executed here, against real data only
//        (CatalogService / YouTubeProvider / SocialService — never a
//        second, model-controlled query language, never raw SQL)
//     -> 'client' tools (playback control, which this backend has no way
//        to execute on a specific running app instance) are NOT executed
//        here at all — they pass through, validated, for the Flutter
//        client to run through PlaybackController exactly like a normal
//        button tap would. The model never gets any closer to playback
//        than that.
//
// There is no code path anywhere in this file that evaluates model-
// generated text as code, SQL, or a shell command.
// ─────────────────────────────────────────────────────────────────────────────

const youtube = new YouTubeProvider();
const audius = new AudiusProvider();
const jamendo = new JamendoProvider();

export type ToolKind = 'server' | 'client';

interface ToolSpec {
  name: string;
  description: string;
  kind: ToolKind;
  parameters: Record<string, any>; // JSON-Schema shown to the model
  schema: z.ZodTypeAny; // runtime validation of the model's arguments
  /** Only for kind:'server'. `ctx.userId` is null for guests. */
  execute?: (args: any, ctx: { userId: string | null }) => Promise<any>;
}

async function searchRealTracks(query: string, limit: number): Promise<RozzaTrack[]> {
  if (!query.trim()) return [];
  let tracks = Catalog.search(query, limit);
  if (tracks.length < 5) {
    const providers = [audius.search(query, limit)];
    if (jamendo.isConfigured()) providers.push(jamendo.search(query, limit));
    const results = await Promise.allSettled(providers);
    const seen = new Set(tracks.map((track) => track.id));
    for (const result of results) {
      if (result.status === 'rejected') {
        console.error('[AIToolRunner] native provider error:', result.reason?.message ?? result.reason);
        continue;
      }
      Catalog.upsertBatch(result.value);
      for (const track of result.value) {
        if (!seen.has(track.id)) {
          seen.add(track.id);
          tracks.push(track);
        }
      }
    }
  }
  if (tracks.length < 5 && youtube.isConfigured()) {
    try {
      const result = await youtube.search(query, limit);
      Catalog.upsertBatch(result.tracks);
      const seen = new Set(tracks.map((t) => t.id));
      for (const t of result.tracks) if (!seen.has(t.id)) { seen.add(t.id); tracks.push(t); }
    } catch (err: any) {
      console.error('[AIToolRunner] YouTube fallback error:', err.message);
    }
  }
  return tracks.slice(0, limit);
}

const TOOL_REGISTRY: ToolSpec[] = [
  {
    name: 'searchMusic',
    description: 'Search the real ROZZA catalog (and YouTube as a fallback) for tracks matching a query.',
    kind: 'server',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search text — artist, title, mood, genre, or occasion' },
        limit: { type: 'integer', minimum: 1, maximum: 25, description: 'Max results, default 10' },
      },
      required: ['query'],
    },
    schema: z.object({ query: z.string().min(1).max(200), limit: z.number().int().min(1).max(25).optional() }),
    execute: async (args) => ({
      query: args.query,
      tracks: await searchRealTracks(args.query, args.limit ?? 10),
    }),
  },
  {
    name: 'exploreCountry',
    description:
      "Find real music from a specific country/region (ROZZA's Around the World / Surprise Me engine). Executed by the app's existing engine, not this backend.",
    kind: 'client',
    parameters: {
      type: 'object',
      properties: { countryCode: { type: 'string', description: 'ISO-3166 alpha-2 country code, e.g. EG, US, FR' } },
      required: ['countryCode'],
    },
    schema: z.object({ countryCode: z.string().length(2) }),
  },
  {
    name: 'searchUser',
    description: 'Search real ROZZA profiles by username or display name.',
    kind: 'server',
    parameters: {
      type: 'object',
      properties: { query: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 50 } },
      required: ['query'],
    },
    schema: z.object({ query: z.string().min(1).max(100), limit: z.number().int().min(1).max(50).optional() }),
    execute: async (args) => ({ profiles: sharedSocialService().searchProfiles(args.query, args.limit ?? 20) }),
  },
  {
    name: 'openUserProfile',
    description: "Look up a real ROZZA user's public profile by username, for the app to navigate to.",
    kind: 'server',
    parameters: { type: 'object', properties: { username: { type: 'string' } }, required: ['username'] },
    schema: z.object({ username: z.string().min(1).max(30) }),
    execute: async (args) => ({ profile: sharedSocialService().getProfileByUsername(args.username) }),
  },
  {
    name: 'createMusicPost',
    description: 'Post a currently-playing or found track to the ROZZA social feed. Requires a signed-in account.',
    kind: 'server',
    parameters: {
      type: 'object',
      properties: {
        youtubeVideoId: { type: 'string' },
        trackTitle: { type: 'string' },
        artist: { type: 'string' },
        thumbnailUrl: { type: 'string' },
        caption: { type: 'string' },
      },
      required: ['youtubeVideoId', 'trackTitle', 'artist'],
    },
    schema: z.object({
      youtubeVideoId: z.string().regex(/^[A-Za-z0-9_-]{11}$/),
      trackTitle: z.string().min(1).max(200),
      artist: z.string().min(1).max(200),
      thumbnailUrl: z.string().url().optional(),
      caption: z.string().max(500).optional(),
    }),
    execute: async (args, ctx) => {
      if (!ctx.userId) return { error: 'Sign in required to post' };
      return { post: sharedSocialService().createPost(ctx.userId, args) };
    },
  },
  // ─── Client-executed playback/library tools ─────────────────────────
  // These never touch this backend's data. They are validated here and
  // handed back so the Flutter client can run them through the exact same
  // PlaybackController methods a manual tap on Play/Next/Queue/etc. would
  // use — the "existing trusted ROZZA code" the mission requires.
  ...([
    ['getCurrentTrack', {}, 'Get the track currently playing, if any.'],
    ['playTrack', { trackId: z.string().min(1) }, 'Play a specific real track by its ROZZA track id.'],
    ['pausePlayback', {}, 'Pause playback.'],
    ['resumePlayback', {}, 'Resume playback.'],
    ['nextTrack', {}, 'Skip to the next track.'],
    ['previousTrack', {}, 'Go to the previous track.'],
    ['getQueue', {}, 'Get the current Up Next queue.'],
    ['addToQueue', { trackId: z.string().min(1) }, 'Add a real track to the queue.'],
    ['removeFromQueue', { trackId: z.string().min(1) }, 'Remove a track from the queue.'],
    ['clearQueue', {}, 'Clear the Up Next queue.'],
    [
      'createPlaylist',
      { title: z.string().min(1).max(100), trackIds: z.array(z.string()).max(200).optional() },
      'Create a new playlist, optionally seeded with real track ids.',
    ],
    [
      'addTrackToPlaylist',
      { playlistId: z.string().min(1), trackId: z.string().min(1) },
      'Add a real track to an existing playlist.',
    ],
    ['getLikedTracks', {}, "Get the user's liked songs."],
    ['getListeningHistory', {}, "Get the user's recent listening history."],
    ['getTasteDNA', {}, "Get the user's real Taste DNA summary."],
    [
      'getRecommendations',
      { seedMood: z.string().max(50).optional() },
      "Get real personalized recommendations from the app's own recommendation engine.",
    ],
    ['startRadio', { seedTrackId: z.string().min(1).optional() }, 'Start radio from a track (or the current one).'],
    [
      'setSleepTimer',
      { minutes: z.number().int().min(1).max(240) },
      'Arm the sleep timer for N minutes.',
    ],
    ['shareTrack', { trackId: z.string().min(1) }, "Open the native share sheet for a track."],
  ] as const).map(([name, shape, description]) => ({
    name,
    description,
    kind: 'client' as const,
    parameters: {
      type: 'object',
      properties: Object.fromEntries(Object.keys(shape).map((k) => [k, { type: 'string' }])),
      required: [],
    },
    schema: z.object(shape as any),
  })),
];

const TOOL_BY_NAME = new Map(TOOL_REGISTRY.map((t) => [t.name, t]));

/** Read-only export for tests that assert the full mission-required tool
 *  set is actually registered. */
export const REGISTERED_TOOL_NAMES: readonly string[] = TOOL_REGISTRY.map((t) => t.name);

export function toolDefinitionsForModel(): AIToolDefinition[] {
  return TOOL_REGISTRY.map((t) => ({ name: t.name, description: t.description, parameters: t.parameters }));
}

export interface ValidatedAction {
  callId: string;
  name: string;
  arguments: Record<string, any>;
}

export interface RejectedAction {
  callId: string;
  name: string;
  reason: string;
}

/** Exported for tests — this is the security-critical boundary (unknown
 *  tool names / invalid arguments never reach real execution), so it's
 *  tested directly against fabricated model output, without needing a
 *  live LLM call. */
export async function validateAndRun(
  calls: AIToolCall[],
  userId: string | null
): Promise<{ clientActions: ValidatedAction[]; serverResults: { name: string; result: any }[]; rejected: RejectedAction[] }> {
  const clientActions: ValidatedAction[] = [];
  const serverResults: { name: string; result: any }[] = [];
  const rejected: RejectedAction[] = [];

  for (const call of calls) {
    const spec = TOOL_BY_NAME.get(call.name);
    if (!spec) {
      rejected.push({ callId: call.id, name: call.name, reason: 'Unknown tool — not in the allowlist' });
      continue;
    }
    const parsed = spec.schema.safeParse(call.arguments ?? {});
    if (!parsed.success) {
      rejected.push({ callId: call.id, name: call.name, reason: 'Arguments failed validation' });
      continue;
    }
    if (spec.kind === 'client') {
      clientActions.push({ callId: call.id, name: spec.name, arguments: parsed.data as Record<string, any> });
    } else {
      try {
        const result = await spec.execute!(parsed.data, { userId });
        serverResults.push({ name: spec.name, result });
      } catch (err: any) {
        rejected.push({ callId: call.id, name: call.name, reason: err?.message ?? 'Tool execution failed' });
      }
    }
  }
  return { clientActions, serverResults, rejected };
}

// ─── Personalization context (Phase 2's "structured context / retrieval
// layer" — never a raw history dump into the prompt) ──────────────────────

export interface PersonalizationContext {
  currentTrack?: { title: string; artist: string; genre?: string; language?: string } | null;
  topArtists?: string[];
  recentMoods?: string[];
  arabicPct?: number;
  preferredRegions?: string[];
  privateSession?: boolean;
}

function buildSystemPrompt(personalization: PersonalizationContext | undefined, locale: string): string {
  const lines = [
    'You are ROZZA AI, the conversational assistant inside the ROZZA music app.',
    'Always reply in the language the user is writing in — Arabic (including Egyptian Arabic/Franco-Arabic) or English. Be warm, brief, natural — never robotic.',
    'You have real tools to search music, control playback, manage the queue/playlists, explore countries, and interact with the ROZZA social feed. Use a tool whenever the user is asking for an action, not just information.',
    'NEVER invent song titles, artists, track ids, user profiles, or claim an action succeeded that you did not call a tool for. Every real track or profile must come from a tool result.',
    'If nothing matches, say so honestly and suggest a normal search instead of making something up.',
  ];
  if (personalization?.currentTrack) {
    lines.push(`Currently playing: "${personalization.currentTrack.title}" by ${personalization.currentTrack.artist}.`);
  }
  if (personalization?.topArtists?.length) {
    lines.push(`Listener's top artists recently: ${personalization.topArtists.slice(0, 5).join(', ')}.`);
  }
  if (personalization?.arabicPct !== undefined) {
    lines.push(`About ${personalization.arabicPct}% of this listener's recent plays are Arabic.`);
  }
  if (personalization?.preferredRegions?.length) {
    lines.push(`Preferred regions: ${personalization.preferredRegions.join(', ')}.`);
  }
  if (personalization?.privateSession) {
    lines.push('Private Session is ON: do not reference or imply learning from this conversation for future recommendations.');
  }
  if (locale) lines.push(`The user's device locale is ${locale}.`);
  return lines.join('\n');
}

export interface ConverseRequest {
  sessionId: string;
  userId: string | null;
  message: string;
  locale?: string;
  personalization?: PersonalizationContext;
}

export interface ConverseResult {
  sessionId: string;
  reply: string;
  actions: ValidatedAction[];
  serverResults: { name: string; result: any }[];
  rejected: RejectedAction[];
  provider: string;
  model: string;
  unavailable?: boolean;
}

const HISTORY_WINDOW = 16; // messages kept for prompt context

/** Real, durable conversation history — replaces ai.ts's in-memory Map.
 *  Skipped entirely (never written) while Private Session is on. */
function loadHistory(sessionId: string): AIMessage[] {
  const rows = sharedSocialDb()
    .db.prepare('SELECT role, content FROM ai_messages WHERE session_id = ? ORDER BY created_at ASC LIMIT ?')
    .all(sessionId, HISTORY_WINDOW) as { role: string; content: string }[];
  return rows
    .filter((r) => r.role === 'user' || r.role === 'assistant')
    .map((r) => ({ role: r.role as 'user' | 'assistant', content: r.content }));
}

function saveMessage(sessionId: string, userId: string | null, role: 'user' | 'assistant', content: string) {
  sharedSocialDb()
    .db.prepare(
      'INSERT INTO ai_messages (id, session_id, user_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?)'
    )
    .run(uuidv4(), sessionId, userId, role, content, new Date().toISOString());
}

/**
 * The Phase 2 entry point. Never throws to the caller — any failure
 * (unconfigured provider, network error, malformed model output) resolves
 * to `{ unavailable: true }` so the route can show the honest
 * "ROZZA AI is temporarily unavailable" fallback instead of a stack trace
 * or, worse, a fabricated-looking empty success.
 */
export async function converse(req: ConverseRequest): Promise<ConverseResult> {
  const provider = getAIProvider();
  const fallback = (): ConverseResult => ({
    sessionId: req.sessionId,
    reply: '',
    actions: [],
    serverResults: [],
    rejected: [],
    provider: provider.providerName,
    model: provider.modelName,
    unavailable: true,
  });

  if (!provider.isConfigured()) return fallback();

  try {
    const persist = !req.personalization?.privateSession;
    const history = loadHistory(req.sessionId);
    const systemPrompt = buildSystemPrompt(req.personalization, req.locale ?? 'en');

    const result = await provider.converse(
      [...history, { role: 'user', content: req.message }],
      toolDefinitionsForModel(),
      systemPrompt
    );

    const { clientActions, serverResults, rejected } = await validateAndRun(result.toolCalls, req.userId);

    if (persist) {
      saveMessage(req.sessionId, req.userId, 'user', req.message);
      saveMessage(req.sessionId, req.userId, 'assistant', result.reply || '[tool call]');
    }

    return {
      sessionId: req.sessionId,
      reply: result.reply,
      actions: clientActions,
      serverResults,
      rejected,
      provider: result.provider,
      model: result.model,
    };
  } catch (err: any) {
    console.error('[AIToolRunner] converse failed:', err?.message ?? err);
    return fallback();
  }
}
