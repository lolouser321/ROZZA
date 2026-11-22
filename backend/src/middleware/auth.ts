import { Request, Response, NextFunction } from 'express';
import { verifySessionToken } from '../services/AuthService';
import { sharedSocialService } from '../services/SocialService';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      /** Set by requireAuth/optionalAuth once a bearer token verifies AND
       *  its tokenVersion still matches the live account (so a deleted or
       *  force-signed-out account's old tokens stop working immediately). */
      rozzaUserId?: string;
    }
  }
}

async function resolveBearerUser(req: Request): Promise<string | null> {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  const verified = await verifySessionToken(token);
  if (!verified) return null;
  const liveVersion = sharedSocialService().getTokenVersion(verified.userId);
  if (liveVersion === null || liveVersion !== verified.tokenVersion) return null;
  return verified.userId;
}

/** Social write actions (post, follow, like, comment, ...) require a real
 *  account — guests can browse and listen, never write social data. */
export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const userId = await resolveBearerUser(req);
  if (!userId) return res.status(401).json({ error: 'Sign in required' });
  req.rozzaUserId = userId;
  next();
}

/** Feed/browse endpoints: attach the user if present, but never block a
 *  guest — "Do not force login merely to listen to music" extends to
 *  browsing the feed. */
export async function optionalAuth(req: Request, _res: Response, next: NextFunction) {
  req.rozzaUserId = (await resolveBearerUser(req)) ?? undefined;
  next();
}
