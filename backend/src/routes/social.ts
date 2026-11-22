import { Router, Request, Response } from 'express';
import { requireAuth, optionalAuth } from '../middleware/auth';
import {
  sharedSocialService,
  UsernameTakenError,
  InvalidUsernameError,
  NotFoundError,
  ForbiddenError,
} from '../services/SocialService';

const router = Router();
const social = sharedSocialService();

function clampLimit(raw: unknown, fallback = 20, max = 50): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(Math.floor(n), max);
}

function handleServiceError(res: Response, err: unknown) {
  if (err instanceof UsernameTakenError || err instanceof InvalidUsernameError) {
    return res.status(400).json({ error: err.message });
  }
  if (err instanceof NotFoundError) return res.status(404).json({ error: err.message || 'Not found' });
  if (err instanceof ForbiddenError) return res.status(403).json({ error: err.message || 'Forbidden' });
  console.error('[social] error:', err);
  return res.status(500).json({ error: 'Internal error' });
}

// A YouTube video id is always exactly 11 URL-safe characters — validated
// here so a post can never reference something that plainly isn't a real
// YouTube video id.
const YOUTUBE_ID_RE = /^[A-Za-z0-9_-]{11}$/;

// ─── Profiles ───────────────────────────────────────────────────────────────

router.get('/profile/:username', optionalAuth, (req: Request, res: Response) => {
  const profile = social.getProfileByUsername(req.params.username);
  if (!profile) return res.status(404).json({ error: 'Profile not found' });
  const viewer = req.rozzaUserId;
  return res.json({
    profile,
    isFollowing: viewer ? social.isFollowing(viewer, profile.userId) : false,
    isBlocked: viewer ? social.isBlocked(viewer, profile.userId) : false,
    isOwnProfile: viewer === profile.userId,
  });
});

router.patch('/profile', requireAuth, (req: Request, res: Response) => {
  try {
    const { username, displayName, avatarUrl, bio, country, preferredLanguage } = req.body ?? {};
    const updated = social.updateProfile(req.rozzaUserId!, {
      username,
      displayName,
      avatarUrl,
      bio,
      country,
      preferredLanguage,
    });
    return res.json({ profile: updated });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

// ─── Follow ─────────────────────────────────────────────────────────────────

router.post('/follow/:userId', requireAuth, (req: Request, res: Response) => {
  try {
    social.follow(req.rozzaUserId!, req.params.userId);
    return res.json({ ok: true });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

router.delete('/follow/:userId', requireAuth, (req: Request, res: Response) => {
  social.unfollow(req.rozzaUserId!, req.params.userId);
  return res.json({ ok: true });
});

router.get('/followers/:userId', optionalAuth, (req: Request, res: Response) => {
  const page = social.listFollowers(req.params.userId, (req.query.cursor as string) ?? null, clampLimit(req.query.limit));
  return res.json(page);
});

router.get('/following/:userId', optionalAuth, (req: Request, res: Response) => {
  const page = social.listFollowing(req.params.userId, (req.query.cursor as string) ?? null, clampLimit(req.query.limit));
  return res.json(page);
});

// ─── Posts / feed ───────────────────────────────────────────────────────────

router.post('/posts', requireAuth, (req: Request, res: Response) => {
  const { youtubeVideoId, trackTitle, artist, thumbnailUrl, caption, hashtags } = req.body ?? {};
  if (typeof youtubeVideoId !== 'string' || !YOUTUBE_ID_RE.test(youtubeVideoId)) {
    return res.status(400).json({ error: 'youtubeVideoId must be a real 11-character YouTube video id' });
  }
  if (typeof trackTitle !== 'string' || !trackTitle.trim() || typeof artist !== 'string') {
    return res.status(400).json({ error: 'trackTitle and artist are required' });
  }
  if (typeof caption === 'string' && caption.length > 500) {
    return res.status(400).json({ error: 'caption is limited to 500 characters' });
  }
  const post = social.createPost(req.rozzaUserId!, {
    youtubeVideoId,
    trackTitle,
    artist,
    thumbnailUrl: typeof thumbnailUrl === 'string' ? thumbnailUrl : null,
    caption: typeof caption === 'string' ? caption : '',
    hashtags: Array.isArray(hashtags) ? hashtags.filter((h) => typeof h === 'string').slice(0, 10) : [],
  });
  return res.status(201).json({ post });
});

router.get('/posts/:id', optionalAuth, (req: Request, res: Response) => {
  const post = social.getPost(req.params.id);
  if (!post) return res.status(404).json({ error: 'Post not found' });
  const viewer = req.rozzaUserId;
  return res.json({ post, isLiked: viewer ? social.hasLiked(post.id, viewer) : false });
});

router.delete('/posts/:id', requireAuth, (req: Request, res: Response) => {
  try {
    social.deletePost(req.params.id, req.rozzaUserId!);
    return res.json({ ok: true });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

router.get('/feed', optionalAuth, (req: Request, res: Response) => {
  const page = social.getFeed(req.rozzaUserId ?? null, (req.query.cursor as string) ?? null, clampLimit(req.query.limit, 20, 50));
  return res.json(page);
});

router.get('/users/:userId/posts', optionalAuth, (req: Request, res: Response) => {
  const page = social.getPostsByAuthor(req.params.userId, (req.query.cursor as string) ?? null, clampLimit(req.query.limit));
  return res.json(page);
});

// ─── Likes ──────────────────────────────────────────────────────────────────

router.post('/posts/:id/like', requireAuth, (req: Request, res: Response) => {
  try {
    social.likePost(req.params.id, req.rozzaUserId!);
    return res.json({ ok: true });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

router.delete('/posts/:id/like', requireAuth, (req: Request, res: Response) => {
  social.unlikePost(req.params.id, req.rozzaUserId!);
  return res.json({ ok: true });
});

// ─── Comments ───────────────────────────────────────────────────────────────

router.get('/posts/:id/comments', optionalAuth, (req: Request, res: Response) => {
  const page = social.listComments(req.params.id, (req.query.cursor as string) ?? null, clampLimit(req.query.limit));
  return res.json(page);
});

router.post('/posts/:id/comments', requireAuth, (req: Request, res: Response) => {
  const { text, parentCommentId } = req.body ?? {};
  if (typeof text !== 'string' || !text.trim() || text.length > 1000) {
    return res.status(400).json({ error: 'text is required (max 1000 characters)' });
  }
  try {
    const comment = social.addComment(req.params.id, req.rozzaUserId!, text.trim(), parentCommentId ?? null);
    return res.status(201).json({ comment });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

router.delete('/comments/:id', requireAuth, (req: Request, res: Response) => {
  try {
    social.deleteComment(req.params.id, req.rozzaUserId!);
    return res.json({ ok: true });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

// ─── Reposts ────────────────────────────────────────────────────────────────

router.post('/posts/:id/repost', requireAuth, (req: Request, res: Response) => {
  const { caption } = req.body ?? {};
  try {
    const result = social.repost(req.rozzaUserId!, req.params.id, typeof caption === 'string' ? caption : null);
    return res.status(201).json(result);
  } catch (err) {
    return handleServiceError(res, err);
  }
});

router.delete('/posts/:id/repost', requireAuth, (req: Request, res: Response) => {
  social.unrepost(req.rozzaUserId!, req.params.id);
  return res.json({ ok: true });
});

// ─── Saves ──────────────────────────────────────────────────────────────────

router.post('/posts/:id/save', requireAuth, (req: Request, res: Response) => {
  social.savePost(req.rozzaUserId!, req.params.id);
  return res.json({ ok: true });
});

router.delete('/posts/:id/save', requireAuth, (req: Request, res: Response) => {
  social.unsavePost(req.rozzaUserId!, req.params.id);
  return res.json({ ok: true });
});

router.get('/saved', requireAuth, (req: Request, res: Response) => {
  const page = social.listSaved(req.rozzaUserId!, (req.query.cursor as string) ?? null, clampLimit(req.query.limit));
  return res.json(page);
});

// ─── Blocks / reports ───────────────────────────────────────────────────────

router.post('/block/:userId', requireAuth, (req: Request, res: Response) => {
  try {
    social.blockUser(req.rozzaUserId!, req.params.userId);
    return res.json({ ok: true });
  } catch (err) {
    return handleServiceError(res, err);
  }
});

router.delete('/block/:userId', requireAuth, (req: Request, res: Response) => {
  social.unblockUser(req.rozzaUserId!, req.params.userId);
  return res.json({ ok: true });
});

router.get('/blocked', requireAuth, (req: Request, res: Response) => {
  return res.json({ items: social.listBlocked(req.rozzaUserId!) });
});

const REPORT_REASONS = new Set(['spam', 'harassment', 'copyright', 'explicit', 'hate_speech', 'other']);

router.post('/report', requireAuth, (req: Request, res: Response) => {
  const { targetType, targetId, reason, details } = req.body ?? {};
  if (!['post', 'comment', 'user'].includes(targetType)) {
    return res.status(400).json({ error: 'targetType must be post, comment, or user' });
  }
  if (typeof targetId !== 'string' || !targetId) return res.status(400).json({ error: 'targetId required' });
  if (typeof reason !== 'string' || !REPORT_REASONS.has(reason)) {
    return res.status(400).json({ error: `reason must be one of: ${[...REPORT_REASONS].join(', ')}` });
  }
  const result = social.report(req.rozzaUserId!, targetType, targetId, reason, typeof details === 'string' ? details : undefined);
  return res.status(201).json(result);
});

// ─── Notifications ──────────────────────────────────────────────────────────

router.get('/notifications', requireAuth, (req: Request, res: Response) => {
  const page = social.listNotifications(req.rozzaUserId!, (req.query.cursor as string) ?? null, clampLimit(req.query.limit));
  return res.json({ ...page, unreadCount: social.unreadNotificationCount(req.rozzaUserId!) });
});

router.post('/notifications/read', requireAuth, (req: Request, res: Response) => {
  const { ids } = req.body ?? {};
  social.markNotificationsRead(req.rozzaUserId!, ids === 'all' ? 'all' : Array.isArray(ids) ? ids : []);
  return res.json({ ok: true });
});

// ─── Preferences (Private Session, AI personalization) ─────────────────────

router.get('/preferences', requireAuth, (req: Request, res: Response) => {
  return res.json(social.getPreferences(req.rozzaUserId!));
});

router.patch('/preferences', requireAuth, (req: Request, res: Response) => {
  const { privateSession, aiPersonalizationEnabled } = req.body ?? {};
  social.setPreferences(req.rozzaUserId!, {
    privateSession: typeof privateSession === 'boolean' ? privateSession : undefined,
    aiPersonalizationEnabled: typeof aiPersonalizationEnabled === 'boolean' ? aiPersonalizationEnabled : undefined,
  });
  return res.json(social.getPreferences(req.rozzaUserId!));
});

export default router;
