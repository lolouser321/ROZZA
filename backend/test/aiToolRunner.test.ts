import test from 'node:test';
import assert from 'node:assert/strict';
import { validateAndRun, REGISTERED_TOOL_NAMES, toolDefinitionsForModel } from '../src/services/AIToolRunner';
import { AIToolCall } from '../src/providers/ai/AIProvider';

// ─────────────────────────────────────────────────────────────────────────────
// These tests exercise the security-critical boundary directly: they hand
// validateAndRun() fabricated "model output" (exactly what a compromised or
// hallucinating LLM might propose) and assert nothing unsafe ever executes.
// No live LLM call is involved — that's the point.
// ─────────────────────────────────────────────────────────────────────────────

test('every tool the mission requires is actually registered', () => {
  const required = [
    'searchMusic',
    'getCurrentTrack',
    'playTrack',
    'pausePlayback',
    'resumePlayback',
    'nextTrack',
    'previousTrack',
    'getQueue',
    'addToQueue',
    'removeFromQueue',
    'clearQueue',
    'createPlaylist',
    'addTrackToPlaylist',
    'getLikedTracks',
    'getListeningHistory',
    'getTasteDNA',
    'getRecommendations',
    'startRadio',
    'exploreCountry',
    'setSleepTimer',
    'searchUser',
    'openUserProfile',
    'shareTrack',
    'createMusicPost',
  ];
  for (const name of required) {
    assert.ok(REGISTERED_TOOL_NAMES.includes(name), `missing required tool: ${name}`);
  }
});

test('every registered tool has a non-empty description shown to the model', () => {
  for (const def of toolDefinitionsForModel()) {
    assert.ok(def.description && def.description.length > 5, `${def.name} needs a real description`);
  }
});

test('an unknown tool name proposed by the model is dropped, never executed', async () => {
  const calls: AIToolCall[] = [{ id: '1', name: 'dropAllTables', arguments: {} }];
  const { clientActions, serverResults, rejected } = await validateAndRun(calls, null);
  assert.equal(clientActions.length, 0);
  assert.equal(serverResults.length, 0);
  assert.equal(rejected.length, 1);
  assert.match(rejected[0].reason, /allowlist/i);
});

test('a known tool with invalid arguments is dropped, never executed', async () => {
  // playTrack requires a non-empty trackId string; the model sent nothing.
  const calls: AIToolCall[] = [{ id: '1', name: 'playTrack', arguments: {} }];
  const { clientActions, rejected } = await validateAndRun(calls, null);
  assert.equal(clientActions.length, 0);
  assert.equal(rejected.length, 1);
});

test('a valid client-kind tool call (e.g. playTrack) passes through untouched for the app to execute', async () => {
  const calls: AIToolCall[] = [{ id: '1', name: 'playTrack', arguments: { trackId: 'track_abc' } }];
  const { clientActions, serverResults, rejected } = await validateAndRun(calls, null);
  assert.equal(rejected.length, 0);
  assert.equal(serverResults.length, 0, 'playback control must never be executed server-side');
  assert.equal(clientActions.length, 1);
  assert.equal(clientActions[0].name, 'playTrack');
  assert.equal(clientActions[0].arguments.trackId, 'track_abc');
});

test('a valid server-kind tool call (e.g. searchMusic) actually executes and returns real data shape', async () => {
  const calls: AIToolCall[] = [{ id: '1', name: 'searchMusic', arguments: { query: 'test', limit: 3 } }];
  const { serverResults, clientActions, rejected } = await validateAndRun(calls, null);
  assert.equal(rejected.length, 0);
  assert.equal(clientActions.length, 0);
  assert.equal(serverResults.length, 1);
  assert.equal(serverResults[0].name, 'searchMusic');
  assert.ok(Array.isArray(serverResults[0].result.tracks));
});

test('createMusicPost is refused server-side for a guest (no userId), never silently posted', async () => {
  const calls: AIToolCall[] = [
    {
      id: '1',
      name: 'createMusicPost',
      arguments: { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' },
    },
  ];
  const { serverResults } = await validateAndRun(calls, null);
  assert.equal(serverResults[0].result.error, 'Sign in required to post');
});

test('a batch of calls is validated independently — one bad call does not block the good ones', async () => {
  const calls: AIToolCall[] = [
    { id: '1', name: 'notARealTool', arguments: {} },
    { id: '2', name: 'pausePlayback', arguments: {} },
    { id: '3', name: 'searchMusic', arguments: { query: 'chill' } },
  ];
  const { clientActions, serverResults, rejected } = await validateAndRun(calls, null);
  assert.equal(rejected.length, 1);
  assert.equal(clientActions.length, 1);
  assert.equal(serverResults.length, 1);
});
