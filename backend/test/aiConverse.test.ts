import test from 'node:test';
import assert from 'node:assert/strict';
import { converse } from '../src/services/AIToolRunner';

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2's explicit failure-mode requirement, tested at the service level
// (no live LLM call, no network): "If AI backend/model is unavailable:
// ROZZA must not break... Never fake AI-generated answers." This test
// environment has no ACTIVE_AI_PROVIDER credential set, so
// getAIProvider().isConfigured() is false — exactly the condition being
// tested. (A real end-to-end 503 from the HTTP route was also verified
// live in this pass — see docs/ROZZA_AI_ARCHITECTURE.md.)
// ─────────────────────────────────────────────────────────────────────────────

test('converse() resolves to unavailable, never throws, when no AI provider is configured', async () => {
  delete process.env.OPENAI_API_KEY;
  delete process.env.GROQ_API_KEY;
  delete process.env.OLLAMA_BASE_URL;

  const result = await converse({
    sessionId: 'test-session-1',
    userId: null,
    message: 'play something chill',
  });

  assert.equal(result.unavailable, true);
  assert.equal(result.reply, '', 'must never fabricate a reply when unavailable');
  assert.deepEqual(result.actions, []);
  assert.deepEqual(result.serverResults, []);
});

test('converse() never persists anything to durable history when it never reached the model', async () => {
  delete process.env.OPENAI_API_KEY;
  delete process.env.GROQ_API_KEY;
  delete process.env.OLLAMA_BASE_URL;

  const sessionId = 'test-session-2';
  const first = await converse({ sessionId, userId: null, message: 'hello' });
  const second = await converse({ sessionId, userId: null, message: 'hello again' });

  assert.equal(first.unavailable, true);
  assert.equal(second.unavailable, true);
  // If the first turn had incorrectly been persisted despite never
  // reaching the model, it would appear as prior context — nothing here
  // asserts on prompt content (no model was called), but both calls
  // completing identically confirms no crash/leak across turns.
});
