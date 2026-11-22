import test from 'node:test';
import assert from 'node:assert/strict';
import {
  issueSessionToken,
  verifySessionToken,
  verifyAppleIdentityToken,
  __buildTestAppleFixture,
  generateEmailCode,
  hashCode,
  hashPassword,
  verifyPassword,
  verifyGoogleIdToken,
  __buildTestGoogleFixture,
} from '../src/services/AuthService';

test('a session token round-trips and carries the right claims', async () => {
  const token = await issueSessionToken({ sub: 'u_123', tokenVersion: 2 });
  const verified = await verifySessionToken(token);
  assert.ok(verified);
  assert.equal(verified!.userId, 'u_123');
  assert.equal(verified!.tokenVersion, 2);
});

test('a garbage token never verifies', async () => {
  assert.equal(await verifySessionToken('not-a-real-token'), null);
  assert.equal(await verifySessionToken(''), null);
});

test('a real Sign in with Apple identity token verifies against its JWKS, with the right sub/email/audience', async () => {
  const { token, jwks } = await __buildTestAppleFixture({
    sub: 'apple-sub-abc',
    email: 'private-relay@example.com',
    audience: 'com.rozza.app',
  });
  const identity = await verifyAppleIdentityToken(token, { jwks, audience: 'com.rozza.app' });
  assert.equal(identity.sub, 'apple-sub-abc');
  assert.equal(identity.email, 'private-relay@example.com');
});

test('an Apple token for a different app (wrong audience) is rejected', async () => {
  const { token, jwks } = await __buildTestAppleFixture({
    sub: 'apple-sub-abc',
    audience: 'com.someone.else',
  });
  await assert.rejects(() => verifyAppleIdentityToken(token, { jwks, audience: 'com.rozza.app' }));
});

test('email codes are 6 digits and hashed at rest (hash never equals the plaintext code)', () => {
  const code = generateEmailCode();
  assert.match(code, /^\d{6}$/);
  const hash = hashCode(code);
  assert.notEqual(hash, code);
  assert.equal(hashCode(code), hash, 'hashing must be deterministic so verification can compare it');
});

test('a real Sign in with Google identity token verifies against its JWKS, with the right sub/email/audience', async () => {
  const { token, jwks } = await __buildTestGoogleFixture({
    sub: 'google-sub-xyz',
    email: 'listener@gmail.com',
    audience: 'test-client-id.apps.googleusercontent.com',
  });
  const identity = await verifyGoogleIdToken(token, { jwks, audience: 'test-client-id.apps.googleusercontent.com' });
  assert.equal(identity.sub, 'google-sub-xyz');
  assert.equal(identity.email, 'listener@gmail.com');
});

test('a Google token for a different app (wrong audience) is rejected', async () => {
  const { token, jwks } = await __buildTestGoogleFixture({
    sub: 'google-sub-xyz',
    audience: 'someone-elses-client-id.apps.googleusercontent.com',
  });
  await assert.rejects(() =>
    verifyGoogleIdToken(token, { jwks, audience: 'test-client-id.apps.googleusercontent.com' })
  );
});

test('verifyGoogleIdToken refuses to run with no GOOGLE_IOS_CLIENT_ID configured and no explicit audience', async () => {
  const before = process.env.GOOGLE_IOS_CLIENT_ID;
  delete process.env.GOOGLE_IOS_CLIENT_ID;
  try {
    const { token, jwks } = await __buildTestGoogleFixture({ sub: 'x', audience: 'whatever' });
    await assert.rejects(() => verifyGoogleIdToken(token, { jwks }));
  } finally {
    if (before !== undefined) process.env.GOOGLE_IOS_CLIENT_ID = before;
  }
});

test('a password hashes to something that is not the plaintext, and verifies correctly', async () => {
  const hash = await hashPassword('correct horse battery staple');
  assert.notEqual(hash, 'correct horse battery staple');
  assert.match(hash, /^[0-9a-f]+:[0-9a-f]+$/, 'stored as salt:hash hex');
  assert.equal(await verifyPassword('correct horse battery staple', hash), true);
});

test('a wrong password is rejected, and two hashes of the same password differ (real random salt)', async () => {
  const hash = await hashPassword('correct horse battery staple');
  assert.equal(await verifyPassword('wrong password', hash), false);
  const hash2 = await hashPassword('correct horse battery staple');
  assert.notEqual(hash, hash2, 'each hash must use a fresh random salt');
  assert.equal(await verifyPassword('correct horse battery staple', hash2), true);
});

test('verifyPassword never throws on a garbage/corrupt stored value — it just returns false', async () => {
  assert.equal(await verifyPassword('anything', ''), false);
  assert.equal(await verifyPassword('anything', 'not-the-right-shape'), false);
  assert.equal(await verifyPassword('anything', 'zz:zz'), false);
});
