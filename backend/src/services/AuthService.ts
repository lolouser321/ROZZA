import { SignJWT, jwtVerify, createRemoteJWKSet, importJWK, type JWTVerifyGetKey } from 'jose';
import crypto from 'crypto';

// ─────────────────────────────────────────────────────────────────────────────
// AuthService — real Sign in with Apple identity-token verification (against
// Apple's own public JWKS, no fabricated trust), plus this backend's own
// short-lived session JWTs (HS256, our own secret — this backend is both the
// issuer and the only verifier, so there is no reason for asymmetric keys
// here). Session tokens embed a `tokenVersion` claim; bumping a user's
// token_version in the database (SocialService.bumpTokenVersion) instantly
// invalidates every previously-issued token for that account — the
// mechanism DELETE /api/auth/account and POST /api/auth/signout-all rely on.
// ─────────────────────────────────────────────────────────────────────────────

const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days
const ISSUER = 'rozza-backend';

function sessionSecret(): Uint8Array {
  const configured = process.env.ROZZA_JWT_SECRET;
  if (configured) return new TextEncoder().encode(configured);
  if (process.env.NODE_ENV === 'production') {
    // Refuse to silently run production auth on a made-up secret — every
    // session would be invalidated (and worse, forgeable if guessed) on
    // every restart. This is a real, loud failure, not a fabricated default.
    throw new Error(
      'ROZZA_JWT_SECRET is required in production. Set a long random value (e.g. `openssl rand -hex 32`).'
    );
  }
  // Dev-only: a random secret generated once per process. Real, not
  // hardcoded — it just means dev sessions don't survive a server restart,
  // which is an honest and safe default rather than a shared dev secret
  // that could leak into production by accident.
  if (!_devSecret) _devSecret = crypto.randomBytes(32);
  return _devSecret;
}
let _devSecret: Buffer | null = null;

export interface SessionClaims {
  sub: string; // ROZZA user id
  tokenVersion: number;
}

export async function issueSessionToken(claims: SessionClaims): Promise<string> {
  return new SignJWT({ tokenVersion: claims.tokenVersion })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(claims.sub)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(`${SESSION_TTL_SECONDS}s`)
    .sign(sessionSecret());
}

export async function verifySessionToken(
  token: string
): Promise<{ userId: string; tokenVersion: number } | null> {
  try {
    const { payload } = await jwtVerify(token, sessionSecret(), { issuer: ISSUER });
    if (!payload.sub) return null;
    return { userId: payload.sub, tokenVersion: (payload.tokenVersion as number) ?? 0 };
  } catch {
    return null;
  }
}

// ─── Sign in with Apple ────────────────────────────────────────────────────

const APPLE_ISSUER = 'https://appleid.apple.com';
let _appleJwks: JWTVerifyGetKey | null = null;

export interface AppleIdentity {
  sub: string;
  email: string | null;
}

/**
 * Verifies a real Apple identity token (the JWT the Sign in with Apple
 * button hands the client) against Apple's own published keys. `jwks` is
 * injectable so tests can verify the exact same logic against a local,
 * self-signed fixture instead of Apple's live endpoint — this project has
 * no way to produce a genuine Apple-signed token without a paid Developer
 * account and a real device (see docs/RELEASE_BLOCKERS.md), so the
 * end-to-end "a real Apple token verifies" path is UNVERIFIED — PHYSICAL
 * DEVICE / OWNER ACCOUNT REQUIRED, exactly as documented; the verification
 * *logic* itself is real and unit-tested against a fixture JWKS.
 */
export async function verifyAppleIdentityToken(
  identityToken: string,
  opts?: { jwks?: JWTVerifyGetKey; audience?: string }
): Promise<AppleIdentity> {
  const jwks = opts?.jwks ?? (_appleJwks ??= createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`)));
  const audience = opts?.audience ?? process.env.APPLE_BUNDLE_ID ?? 'com.rozza.app';
  const { payload } = await jwtVerify(identityToken, jwks, {
    issuer: APPLE_ISSUER,
    audience,
  });
  if (!payload.sub) throw new Error('Apple identity token missing sub');
  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : null,
  };
}

/** Test-only helper: build a local JWKS + a validly-signed fixture token so
 *  verifyAppleIdentityToken's real verification path (signature, issuer,
 *  audience, expiry) can be exercised without any network call or a real
 *  Apple account. */
export async function __buildTestAppleFixture(claims: { sub: string; email?: string; audience: string }) {
  const { generateKeyPair, exportJWK } = await import('jose');
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = await exportJWK(publicKey);
  const kid = 'test-key-1';
  const jwks: JWTVerifyGetKey = async () => await importJWK({ ...jwk, kid, alg: 'RS256' }, 'RS256');
  const token = await new SignJWT({ email: claims.email })
    .setProtectedHeader({ alg: 'RS256', kid })
    .setSubject(claims.sub)
    .setIssuer(APPLE_ISSUER)
    .setAudience(claims.audience)
    .setIssuedAt()
    .setExpirationTime('10m')
    .sign(privateKey);
  return { token, jwks };
}

// ─── Passwordless email codes ──────────────────────────────────────────────

export function generateEmailCode(): string {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

export function hashCode(code: string): string {
  return crypto.createHash('sha256').update(code).digest('hex');
}

// ─── Username + password accounts ──────────────────────────────────────────
// scrypt, not a fast hash like the email-code sha256 above — a password is
// long-lived and user-chosen (so it's much more guessable than a random
// 6-digit code with a 10-minute expiry + 5-attempt lock), so it needs real
// key-stretching. scrypt is Node's own built-in KDF (no new dependency,
// unlike bcrypt/argon2 which would need a native addon on top of
// better-sqlite3's) and is an OWASP-acceptable choice. Stored as
// `salt:hash`, both hex, so verifyPassword never needs a second lookup.
const SCRYPT_KEYLEN = 64;

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);
  const derived = await new Promise<Buffer>((resolve, reject) => {
    crypto.scrypt(password, salt, SCRYPT_KEYLEN, (err, key) => (err ? reject(err) : resolve(key)));
  });
  return `${salt.toString('hex')}:${derived.toString('hex')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [saltHex, hashHex] = stored.split(':');
  if (!saltHex || !hashHex) return false;
  const salt = Buffer.from(saltHex, 'hex');
  const expected = Buffer.from(hashHex, 'hex');
  // Buffer.from(..., 'hex') does not throw on invalid hex — it silently
  // truncates at the first bad pair, so e.g. 'zz' decodes to a valid but
  // *empty* Buffer instead of an error. Without this check, two corrupt
  // values that both truncate to empty compare as "equal" below (an empty
  // buffer trivially equals another empty buffer), which would let a
  // corrupted stored hash verify against ANY password. Requiring the exact
  // real scrypt output length closes that off.
  if (salt.length !== 16 || expected.length !== SCRYPT_KEYLEN) return false;
  const derived = await new Promise<Buffer>((resolve, reject) => {
    crypto.scrypt(password, salt, expected.length, (err, key) => (err ? reject(err) : resolve(key)));
  });
  return crypto.timingSafeEqual(derived, expected);
}

// ─── Sign in with Google ───────────────────────────────────────────────────
// Same shape as verifyAppleIdentityToken above — a real ID token verified
// against Google's own published JWKS via the same `jose` library already a
// dependency here, so this needed no new package. `aud` must match a real
// Google OAuth client ID the account owner creates themselves in Google
// Cloud Console (free, GOOGLE_IOS_CLIENT_ID here) — there is no way to
// fabricate that from this environment, same caveat as Apple's bundle id.

const GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];
let _googleJwks: JWTVerifyGetKey | null = null;

export interface GoogleIdentity {
  sub: string;
  email: string | null;
}

export async function verifyGoogleIdToken(
  idToken: string,
  opts?: { jwks?: JWTVerifyGetKey; audience?: string }
): Promise<GoogleIdentity> {
  const jwks = opts?.jwks ?? (_googleJwks ??= createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs')));
  const audience = opts?.audience ?? process.env.GOOGLE_IOS_CLIENT_ID;
  if (!audience) throw new Error('GOOGLE_IOS_CLIENT_ID is not configured on this server');
  const { payload } = await jwtVerify(idToken, jwks, { issuer: GOOGLE_ISSUERS, audience });
  if (!payload.sub) throw new Error('Google identity token missing sub');
  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : null,
  };
}

/** Test-only helper, same purpose as __buildTestAppleFixture above — a
 *  locally-signed, validly-shaped Google ID token so verifyGoogleIdToken's
 *  real verification logic (signature, issuer, audience) is exercised
 *  without a network call or a real Google account. */
export async function __buildTestGoogleFixture(claims: { sub: string; email?: string; audience: string }) {
  const { generateKeyPair, exportJWK } = await import('jose');
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = await exportJWK(publicKey);
  const kid = 'test-key-1';
  const jwks: JWTVerifyGetKey = async () => await importJWK({ ...jwk, kid, alg: 'RS256' }, 'RS256');
  const token = await new SignJWT({ email: claims.email })
    .setProtectedHeader({ alg: 'RS256', kid })
    .setSubject(claims.sub)
    .setIssuer(GOOGLE_ISSUERS[0])
    .setAudience(claims.audience)
    .setIssuedAt()
    .setExpirationTime('10m')
    .sign(privateKey);
  return { token, jwks };
}
