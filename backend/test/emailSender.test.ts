import test from 'node:test';
import assert from 'node:assert/strict';
import { ResendEmailSender } from '../src/services/EmailSender';

// ─────────────────────────────────────────────────────────────────────────────
// Real request shaping + real success/failure reporting, tested against a
// mocked fetch (no live network call, no real API key needed) — matching
// how OllamaProvider.ts is tested. A live send to a real Resend account is
// covered separately by manual verification once a real RESEND_API_KEY is
// configured (see docs/AUTH_ARCHITECTURE.md), which this test suite cannot
// do without fabricating a credential.
// ─────────────────────────────────────────────────────────────────────────────

test('a successful Resend response reports delivered:true and sends the right payload', async () => {
  let capturedUrl: string | RequestInfo | URL | undefined;
  let capturedInit: RequestInit | undefined;
  const fakeFetch = (async (url: any, init?: any) => {
    capturedUrl = url;
    capturedInit = init;
    return new Response(JSON.stringify({ id: 'fake-id' }), { status: 200 });
  }) as typeof fetch;

  const sender = new ResendEmailSender('fake-key', 'onboarding@resend.dev', fakeFetch);
  const ok = await sender.send('someone@example.com', 'Your ROZZA sign-in code', 'Your code is 123456.');

  assert.equal(ok, true);
  assert.equal(capturedUrl, 'https://api.resend.com/emails');
  const body = JSON.parse((capturedInit!.body as string) ?? '{}');
  assert.equal(body.to, 'someone@example.com');
  assert.equal(body.from, 'onboarding@resend.dev');
  assert.match(body.text, /123456/);
  const headers = capturedInit!.headers as Record<string, string>;
  assert.equal(headers.Authorization, 'Bearer fake-key');
});

test('a non-2xx Resend response reports delivered:false, never a fabricated success', async () => {
  const fakeFetch = (async () => new Response('rejected', { status: 422 })) as typeof fetch;
  const sender = new ResendEmailSender('fake-key', 'onboarding@resend.dev', fakeFetch);
  const ok = await sender.send('someone@example.com', 'subject', 'body');
  assert.equal(ok, false);
});

test('a network failure reports delivered:false rather than throwing to the caller', async () => {
  const fakeFetch = (async () => {
    throw new Error('network unreachable');
  }) as typeof fetch;
  const sender = new ResendEmailSender('fake-key', 'onboarding@resend.dev', fakeFetch);
  const ok = await sender.send('someone@example.com', 'subject', 'body');
  assert.equal(ok, false);
});
