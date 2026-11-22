import { Router, Request, Response } from 'express';
import rateLimit from 'express-rate-limit';
import {
  issueSessionToken,
  verifyAppleIdentityToken,
  generateEmailCode,
  hashCode,
  hashPassword,
  verifyPassword,
  verifyGoogleIdToken,
} from '../services/AuthService';
import { getEmailSender } from '../services/EmailSender';
import { sharedSocialService, UsernameTakenError, InvalidUsernameError } from '../services/SocialService';
import { sharedSocialDb } from '../db/socialDb';
import { requireAuth } from '../middleware/auth';

const router = Router();
const social = sharedSocialService();

// Tighter than the global 120/min API limiter — this gates password guesses
// specifically, so it stays strict regardless of what the general limit is.
const loginLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { error: 'Too many login attempts — wait a minute and try again' },
});

const EMAIL_CODE_TTL_MS = 10 * 60 * 1000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isEmail(value: unknown): value is string {
  return typeof value === 'string' && EMAIL_RE.test(value);
}

async function respondWithSession(res: Response, userId: string, isNewUser: boolean) {
  const tokenVersion = social.getTokenVersion(userId) ?? 0;
  const token = await issueSessionToken({ sub: userId, tokenVersion });
  const profile = social.getProfileByUserId(userId);
  return res.json({ token, isNewUser, profile });
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/auth/apple — real Sign in with Apple. The client sends the
// identityToken it received from ASAuthorizationAppleIDCredential; this
// verifies it against Apple's own live JWKS (or, in the injected-fixture
// test path, a local one — see AuthService.ts's doc comment on why an
// end-to-end real Apple token can't be produced from this environment).
// ─────────────────────────────────────────────────────────────────────────────
router.post('/apple', async (req: Request, res: Response) => {
  const { identityToken, email } = req.body as { identityToken?: string; email?: string | null };
  if (!identityToken) return res.status(400).json({ error: 'identityToken required' });
  try {
    const identity = await verifyAppleIdentityToken(identityToken);
    // Apple only includes email on the FIRST authorization for a given app;
    // trust the token's own email claim first, then whatever the client
    // passed from that first-authorization response.
    const resolvedEmail = identity.email ?? (isEmail(email) ? email : null);
    const { userId, isNewUser } = social.findOrCreateUserByAppleSub(identity.sub, resolvedEmail);
    return await respondWithSession(res, userId, isNewUser);
  } catch (err: any) {
    return res.status(401).json({ error: 'Invalid Apple identity token', details: err?.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/auth/google — real Sign in with Google. The client sends the
// idToken Google's Sign-In SDK hands it after the user picks an account;
// this verifies it against Google's own live JWKS, the same pattern as
// Apple above. GOOGLE_IOS_CLIENT_ID must be set to a real client id the
// account owner creates in Google Cloud Console — see .env.example.
// ─────────────────────────────────────────────────────────────────────────────
router.post('/google', async (req: Request, res: Response) => {
  const { idToken } = req.body as { idToken?: string };
  if (!idToken) return res.status(400).json({ error: 'idToken required' });
  try {
    const identity = await verifyGoogleIdToken(idToken);
    const { userId, isNewUser } = social.findOrCreateUserByGoogleSub(identity.sub, identity.email);
    return await respondWithSession(res, userId, isNewUser);
  } catch (err: any) {
    return res.status(401).json({ error: 'Invalid Google identity token', details: err?.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Username + password accounts — no email required at all. Registration and
// login are both behind loginLimiter (10/min/IP) since both let an attacker
// try passwords; registration also burns a username per attempt, which is
// its own natural brake.
// ─────────────────────────────────────────────────────────────────────────────
const USERNAME_LOGIN_RE = /^[a-z0-9_][a-z0-9_.]{2,29}$/i;

router.post('/username/register', loginLimiter, async (req: Request, res: Response) => {
  const { username, password } = req.body as { username?: string; password?: string };
  if (typeof username !== 'string' || !USERNAME_LOGIN_RE.test(username)) {
    return res.status(400).json({ error: 'Username must be 3-30 chars: letters, numbers, underscore, dot' });
  }
  if (typeof password !== 'string' || password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }
  try {
    const passwordHash = await hashPassword(password);
    const { userId, isNewUser } = social.registerWithUsernamePassword(username, passwordHash);
    return await respondWithSession(res, userId, isNewUser);
  } catch (err: any) {
    if (err instanceof UsernameTakenError) return res.status(409).json({ error: err.message });
    if (err instanceof InvalidUsernameError) return res.status(400).json({ error: err.message });
    console.error('[auth:username/register]', err?.message ?? err);
    return res.status(500).json({ error: 'Could not create account' });
  }
});

router.post('/username/login', loginLimiter, async (req: Request, res: Response) => {
  const { username, password } = req.body as { username?: string; password?: string };
  if (typeof username !== 'string' || typeof password !== 'string') {
    return res.status(400).json({ error: 'username and password required' });
  }
  const found = social.getPasswordHashByUsername(username);
  // Same generic error whether the username doesn't exist or the password
  // is wrong — never reveal which, so a login form can't be used to
  // enumerate real usernames.
  if (!found || !(await verifyPassword(password, found.passwordHash))) {
    return res.status(401).json({ error: 'Incorrect username or password' });
  }
  social.touchLastLogin(found.userId);
  return await respondWithSession(res, found.userId, false);
});

// ─── Passwordless email sign-in ────────────────────────────────────────────

router.post('/email/start', async (req: Request, res: Response) => {
  const { email } = req.body as { email?: string };
  if (!isEmail(email)) return res.status(400).json({ error: 'Valid email required' });

  const code = generateEmailCode();
  const codeHash = hashCode(code);
  const expiresAt = new Date(Date.now() + EMAIL_CODE_TTL_MS).toISOString();
  sharedSocialDb().db
    .prepare(
      `INSERT INTO auth_email_codes (email, code_hash, expires_at, attempts, created_at)
       VALUES (?, ?, ?, 0, ?)
       ON CONFLICT(email) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at,
         attempts = 0, created_at = excluded.created_at`
    )
    .run(email.toLowerCase(), codeHash, expiresAt, new Date().toISOString());

  const sender = getEmailSender();
  const usingRealProvider = Boolean(process.env.RESEND_API_KEY);
  const delivered = await sender.send(
    email,
    'Your ROZZA sign-in code',
    `Your ROZZA sign-in code is ${code}. It expires in 10 minutes.`
  );
  // Never claim a real email was sent when only the dev console sender is
  // configured — see EmailSender.ts. `delivered` reflects what the active
  // sender actually reported, not an assumption.
  return res.json({
    delivered,
    hint: usingRealProvider
      ? delivered
        ? undefined
        : 'The email provider rejected or failed to send this — check the backend log.'
      : 'No production email provider is configured; the code was printed to the backend console.',
  });
});

router.post('/email/verify', async (req: Request, res: Response) => {
  const { email, code } = req.body as { email?: string; code?: string };
  if (!isEmail(email) || !code) return res.status(400).json({ error: 'email and code required' });

  const row = sharedSocialDb().db
    .prepare('SELECT * FROM auth_email_codes WHERE email = ? COLLATE NOCASE')
    .get(email) as { code_hash: string; expires_at: string; attempts: number } | undefined;
  if (!row) return res.status(400).json({ error: 'No code requested for this email' });
  if (new Date(row.expires_at).getTime() < Date.now()) {
    return res.status(400).json({ error: 'Code expired — request a new one' });
  }
  if (row.attempts >= 5) return res.status(429).json({ error: 'Too many attempts — request a new code' });

  if (hashCode(code) !== row.code_hash) {
    sharedSocialDb().db
      .prepare('UPDATE auth_email_codes SET attempts = attempts + 1 WHERE email = ? COLLATE NOCASE')
      .run(email);
    return res.status(401).json({ error: 'Incorrect code' });
  }

  sharedSocialDb().db.prepare('DELETE FROM auth_email_codes WHERE email = ? COLLATE NOCASE').run(email);
  const { userId, isNewUser } = social.findOrCreateUserByEmail(email);
  return await respondWithSession(res, userId, isNewUser);
});

// ─── Session ────────────────────────────────────────────────────────────────

router.get('/me', requireAuth, (req: Request, res: Response) => {
  const profile = social.getProfileByUserId(req.rozzaUserId!);
  if (!profile) return res.status(404).json({ error: 'Profile not found' });
  return res.json({ profile, preferences: social.getPreferences(req.rozzaUserId!) });
});

/** Invalidates every session token this account has ever been issued
 *  (bumps token_version). The current request's own token also stops
 *  working immediately after this — the client should sign in again. */
router.post('/signout-all', requireAuth, (req: Request, res: Response) => {
  social.bumpTokenVersion(req.rozzaUserId!);
  return res.json({ ok: true });
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/auth/account — real erasure (Phase 9), not a hidden flag.
// See SocialService.deleteAccount for exactly what is removed.
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/account', requireAuth, (req: Request, res: Response) => {
  social.deleteAccount(req.rozzaUserId!);
  return res.json({ ok: true, deleted: true });
});

export default router;
