import { SocialDb, newId, sharedSocialDb } from '../db/socialDb';

// ─────────────────────────────────────────────────────────────────────────────
// SocialService — every real read/write for accounts, follows, posts, likes,
// comments, reposts, saves, blocks, reports and notifications. Routes call
// only these typed methods; nothing in routes/ai.ts touches raw SQL. This is
// also exactly the trusted layer the AI tool system (AIToolRunner.ts) is
// allowed to call — the model never gets closer to the database than this.
//
// Counters (followers_count, posts_count, likes_count, ...) are maintained
// by hand in the same transaction as each mutation, not by SQL triggers —
// this keeps every count-changing rule in one auditable place, and lets
// deleteAccount() reuse the exact same unfollow/unlike/uncomment/unrepost
// paths (rather than a second, easy-to-drift bookkeeping routine) to unwind
// a user's footprint before the final cascade delete.
// ─────────────────────────────────────────────────────────────────────────────

export interface PublicProfile {
  userId: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string;
  country: string | null;
  preferredLanguage: string | null;
  isCreator: boolean;
  followersCount: number;
  followingCount: number;
  postsCount: number;
  createdAt: string;
}

/** The minimum a feed/post card needs to render an author — deliberately
 *  lighter than the full PublicProfile (no follower counts etc.), and
 *  always joined in the same query as the post itself so rendering a feed
 *  never needs a second round-trip per post (no N+1 queries). */
export interface PostAuthorSummary {
  userId: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
}

export interface MusicPost {
  id: string;
  authorId: string;
  youtubeVideoId: string;
  trackTitle: string;
  artist: string;
  thumbnailUrl: string | null;
  caption: string;
  hashtags: string[];
  likesCount: number;
  commentsCount: number;
  repostsCount: number;
  sharesCount: number;
  createdAt: string;
  author: PostAuthorSummary | null;
  repostOf?: { postId: string; byUsername: string } | null;
}

export interface CommentRow {
  id: string;
  postId: string;
  authorId: string;
  parentCommentId: string | null;
  text: string;
  createdAt: string;
}

export interface NotificationRow {
  id: string;
  type: 'follow' | 'like' | 'comment' | 'repost' | 'mention';
  actorId: string;
  postId: string | null;
  commentId: string | null;
  createdAt: string;
  readAt: string | null;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

function nowIso() {
  return new Date().toISOString();
}

function encodeCursor(createdAt: string, id: string): string {
  return Buffer.from(`${createdAt}|${id}`, 'utf8').toString('base64url');
}

function decodeCursor(cursor?: string | null): { createdAt: string; id: string } | null {
  if (!cursor) return null;
  try {
    const raw = Buffer.from(cursor, 'base64url').toString('utf8');
    const [createdAt, id] = raw.split('|');
    if (!createdAt || !id) return null;
    return { createdAt, id };
  } catch {
    return null;
  }
}

const USERNAME_RE = /^[a-z0-9_][a-z0-9_.]{2,29}$/;

export class UsernameTakenError extends Error {
  constructor() {
    super('Username already taken');
  }
}
export class InvalidUsernameError extends Error {
  constructor() {
    super('Username must be 3-30 chars: letters, numbers, underscore, dot');
  }
}
export class NotFoundError extends Error {}
export class ForbiddenError extends Error {}

export class SocialService {
  constructor(private readonly social: SocialDb) {}

  // ─── Accounts / profiles ──────────────────────────────────────────────

  private generateUsername(seed: string): string {
    const base = seed.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 16) || 'listener';
    for (let i = 0; i < 25; i++) {
      const candidate = i === 0 ? base : `${base}${Math.floor(Math.random() * 9000 + 1000)}`;
      const exists = this.social.db
        .prepare('SELECT 1 FROM profiles WHERE username = ? COLLATE NOCASE')
        .get(candidate);
      if (!exists) return candidate;
    }
    return `listener${Date.now()}`;
  }

  findOrCreateUserByAppleSub(appleSub: string, email: string | null): { userId: string; isNewUser: boolean } {
    const existing = this.social.db.prepare('SELECT id FROM users WHERE apple_sub = ?').get(appleSub) as
      | { id: string }
      | undefined;
    const ts = nowIso();
    if (existing) {
      this.social.db.prepare('UPDATE users SET last_login_at = ? WHERE id = ?').run(ts, existing.id);
      return { userId: existing.id, isNewUser: false };
    }
    return this.social.db.transaction(() => {
      const userId = newId('u');
      this.social.db
        .prepare('INSERT INTO users (id, apple_sub, email, created_at, last_login_at) VALUES (?, ?, ?, ?, ?)')
        .run(userId, appleSub, email, ts, ts);
      this.createDefaultProfile(userId, email ?? appleSub);
      return { userId, isNewUser: true };
    })();
  }

  findOrCreateUserByEmail(email: string): { userId: string; isNewUser: boolean } {
    const existing = this.social.db
      .prepare('SELECT id FROM users WHERE email = ? COLLATE NOCASE')
      .get(email) as { id: string } | undefined;
    const ts = nowIso();
    if (existing) {
      this.social.db.prepare('UPDATE users SET last_login_at = ? WHERE id = ?').run(ts, existing.id);
      return { userId: existing.id, isNewUser: false };
    }
    return this.social.db.transaction(() => {
      const userId = newId('u');
      this.social.db
        .prepare('INSERT INTO users (id, email, created_at, last_login_at) VALUES (?, ?, ?, ?)')
        .run(userId, email, ts, ts);
      this.createDefaultProfile(userId, email);
      return { userId, isNewUser: true };
    })();
  }

  /** Real username/password account creation — no email required at all.
   *  `passwordHash` is the already-hashed value (AuthService.hashPassword);
   *  this method never sees or logs the plaintext password. Throws
   *  InvalidUsernameError / UsernameTakenError so the route can turn those
   *  into clean 400s, same pattern as updateProfile's username change. */
  registerWithUsernamePassword(username: string, passwordHash: string): { userId: string; isNewUser: true } {
    const clean = username.trim().toLowerCase();
    if (!USERNAME_RE.test(clean)) throw new InvalidUsernameError();
    const taken = this.social.db
      .prepare('SELECT 1 FROM profiles WHERE username = ? COLLATE NOCASE')
      .get(clean);
    if (taken) throw new UsernameTakenError();
    const ts = nowIso();
    return this.social.db.transaction(() => {
      const userId = newId('u');
      this.social.db
        .prepare('INSERT INTO users (id, password_hash, created_at, last_login_at) VALUES (?, ?, ?, ?)')
        .run(userId, passwordHash, ts, ts);
      this.social.db
        .prepare(
          `INSERT INTO profiles (user_id, username, display_name, bio, created_at, updated_at)
           VALUES (?, ?, ?, '', ?, ?)`
        )
        .run(userId, clean, 'ROZZA listener', ts, ts);
      return { userId, isNewUser: true as const };
    })();
  }

  /** Looks up the stored password hash for a login attempt — returns null
   *  for "no such username" AND "this account has no password set" (e.g. an
   *  Apple/Google/email-only account) alike, so callers can't distinguish
   *  the two and enumerate valid usernames from response shape alone. */
  getPasswordHashByUsername(username: string): { userId: string; passwordHash: string } | null {
    const row = this.social.db
      .prepare(
        `SELECT u.id as user_id, u.password_hash as password_hash
         FROM users u JOIN profiles p ON p.user_id = u.id
         WHERE p.username = ? COLLATE NOCASE`
      )
      .get(username.trim().toLowerCase()) as { user_id: string; password_hash: string | null } | undefined;
    if (!row || !row.password_hash) return null;
    return { userId: row.user_id, passwordHash: row.password_hash };
  }

  touchLastLogin(userId: string) {
    this.social.db.prepare('UPDATE users SET last_login_at = ? WHERE id = ?').run(nowIso(), userId);
  }

  findOrCreateUserByGoogleSub(googleSub: string, email: string | null): { userId: string; isNewUser: boolean } {
    const existing = this.social.db.prepare('SELECT id FROM users WHERE google_sub = ?').get(googleSub) as
      | { id: string }
      | undefined;
    const ts = nowIso();
    if (existing) {
      this.social.db.prepare('UPDATE users SET last_login_at = ? WHERE id = ?').run(ts, existing.id);
      return { userId: existing.id, isNewUser: false };
    }
    return this.social.db.transaction(() => {
      const userId = newId('u');
      this.social.db
        .prepare('INSERT INTO users (id, google_sub, email, created_at, last_login_at) VALUES (?, ?, ?, ?, ?)')
        .run(userId, googleSub, email, ts, ts);
      this.createDefaultProfile(userId, email ?? googleSub);
      return { userId, isNewUser: true };
    })();
  }

  private createDefaultProfile(userId: string, seed: string) {
    const username = this.generateUsername(seed.split('@')[0]);
    const ts = nowIso();
    this.social.db
      .prepare(
        `INSERT INTO profiles (user_id, username, display_name, bio, created_at, updated_at)
         VALUES (?, ?, ?, '', ?, ?)`
      )
      .run(userId, username, 'ROZZA listener', ts, ts);
  }

  getTokenVersion(userId: string): number | null {
    const row = this.social.db.prepare('SELECT token_version FROM users WHERE id = ?').get(userId) as
      | { token_version: number }
      | undefined;
    return row?.token_version ?? null;
  }

  bumpTokenVersion(userId: string) {
    this.social.db.prepare('UPDATE users SET token_version = token_version + 1 WHERE id = ?').run(userId);
  }

  private rowToProfile(row: any): PublicProfile {
    return {
      userId: row.user_id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      bio: row.bio,
      country: row.country,
      preferredLanguage: row.preferred_language,
      isCreator: !!row.is_creator,
      followersCount: row.followers_count,
      followingCount: row.following_count,
      postsCount: row.posts_count,
      createdAt: row.created_at,
    };
  }

  getProfileByUserId(userId: string): PublicProfile | null {
    const row = this.social.db.prepare('SELECT * FROM profiles WHERE user_id = ?').get(userId);
    return row ? this.rowToProfile(row) : null;
  }

  getProfileByUsername(username: string): PublicProfile | null {
    const row = this.social.db
      .prepare('SELECT * FROM profiles WHERE username = ? COLLATE NOCASE')
      .get(username);
    return row ? this.rowToProfile(row) : null;
  }

  /** Prefix/substring search over username + display name — backs both the
   *  in-app user search and the AI's `searchUser` tool. Real data only,
   *  capped, never a fuzzy relevance model that could look like it "knows"
   *  something it doesn't. */
  searchProfiles(query: string, limit = 20): PublicProfile[] {
    const q = `%${query.trim()}%`;
    const rows = this.social.db
      .prepare(
        `SELECT * FROM profiles
         WHERE username LIKE ? COLLATE NOCASE OR display_name LIKE ? COLLATE NOCASE
         ORDER BY followers_count DESC
         LIMIT ?`
      )
      .all(q, q, Math.min(Math.max(limit, 1), 50)) as any[];
    return rows.map((r) => this.rowToProfile(r));
  }

  updateProfile(
    userId: string,
    patch: Partial<Pick<PublicProfile, 'username' | 'displayName' | 'avatarUrl' | 'bio' | 'country' | 'preferredLanguage'>>
  ): PublicProfile {
    if (patch.username !== undefined) {
      const clean = patch.username.trim().toLowerCase();
      if (!USERNAME_RE.test(clean)) throw new InvalidUsernameError();
      const taken = this.social.db
        .prepare('SELECT user_id FROM profiles WHERE username = ? COLLATE NOCASE AND user_id != ?')
        .get(clean, userId);
      if (taken) throw new UsernameTakenError();
      this.social.db.prepare('UPDATE profiles SET username = ? WHERE user_id = ?').run(clean, userId);
    }
    const fieldMap: Record<string, string> = {
      displayName: 'display_name',
      avatarUrl: 'avatar_url',
      bio: 'bio',
      country: 'country',
      preferredLanguage: 'preferred_language',
    };
    for (const [key, column] of Object.entries(fieldMap)) {
      const value = (patch as any)[key];
      if (value !== undefined) {
        this.social.db.prepare(`UPDATE profiles SET ${column} = ? WHERE user_id = ?`).run(value, userId);
      }
    }
    this.social.db.prepare('UPDATE profiles SET updated_at = ? WHERE user_id = ?').run(nowIso(), userId);
    const updated = this.getProfileByUserId(userId);
    if (!updated) throw new NotFoundError('Profile vanished mid-update');
    return updated;
  }

  // ─── Follows ───────────────────────────────────────────────────────────

  isFollowing(followerId: string, followeeId: string): boolean {
    return !!this.social.db
      .prepare('SELECT 1 FROM follows WHERE follower_id = ? AND followee_id = ?')
      .get(followerId, followeeId);
  }

  isBlocked(a: string, b: string): boolean {
    return !!this.social.db
      .prepare(
        'SELECT 1 FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)'
      )
      .get(a, b, b, a);
  }

  follow(followerId: string, followeeId: string): void {
    if (followerId === followeeId) throw new ForbiddenError('Cannot follow yourself');
    if (this.isBlocked(followerId, followeeId)) throw new ForbiddenError('Blocked');
    if (this.isFollowing(followerId, followeeId)) return;
    this.social.db.transaction(() => {
      this.social.db
        .prepare('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)')
        .run(followerId, followeeId, nowIso());
      this.social.db
        .prepare('UPDATE profiles SET following_count = following_count + 1 WHERE user_id = ?')
        .run(followerId);
      this.social.db
        .prepare('UPDATE profiles SET followers_count = followers_count + 1 WHERE user_id = ?')
        .run(followeeId);
      this.insertNotification(followeeId, 'follow', followerId, null, null);
    })();
  }

  unfollow(followerId: string, followeeId: string): void {
    if (!this.isFollowing(followerId, followeeId)) return;
    this.social.db.transaction(() => {
      this.social.db
        .prepare('DELETE FROM follows WHERE follower_id = ? AND followee_id = ?')
        .run(followerId, followeeId);
      this.social.db
        .prepare('UPDATE profiles SET following_count = MAX(0, following_count - 1) WHERE user_id = ?')
        .run(followerId);
      this.social.db
        .prepare('UPDATE profiles SET followers_count = MAX(0, followers_count - 1) WHERE user_id = ?')
        .run(followeeId);
    })();
  }

  listFollowers(userId: string, cursor: string | null, limit: number): Page<PublicProfile> {
    return this.listEdge('followee_id', 'follower_id', userId, cursor, limit);
  }

  listFollowing(userId: string, cursor: string | null, limit: number): Page<PublicProfile> {
    return this.listEdge('follower_id', 'followee_id', userId, cursor, limit);
  }

  private listEdge(
    matchColumn: 'follower_id' | 'followee_id',
    otherColumn: 'follower_id' | 'followee_id',
    userId: string,
    cursor: string | null,
    limit: number
  ): Page<PublicProfile> {
    const c = decodeCursor(cursor);
    const rows = this.social.db
      .prepare(
        `SELECT f.created_at as edge_created_at, p.* FROM follows f
         JOIN profiles p ON p.user_id = f.${otherColumn}
         WHERE f.${matchColumn} = ?
           AND (? IS NULL OR f.created_at < ? OR (f.created_at = ? AND f.${otherColumn} < ?))
         ORDER BY f.created_at DESC, f.${otherColumn} DESC
         LIMIT ?`
      )
      .all(
        userId,
        c?.createdAt ?? null,
        c?.createdAt ?? null,
        c?.createdAt ?? null,
        c?.id ?? null,
        limit + 1
      ) as any[];
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      items: page.map((r) => this.rowToProfile(r)),
      nextCursor: hasMore ? encodeCursor(page[page.length - 1].edge_created_at, page[page.length - 1].user_id) : null,
    };
  }

  // ─── Posts ─────────────────────────────────────────────────────────────

  createPost(authorId: string, data: {
    youtubeVideoId: string;
    trackTitle: string;
    artist: string;
    thumbnailUrl?: string | null;
    caption?: string;
    hashtags?: string[];
  }): MusicPost {
    const id = newId('post');
    const ts = nowIso();
    this.social.db.transaction(() => {
      this.social.db
        .prepare(
          `INSERT INTO music_posts
           (id, author_id, youtube_video_id, track_title, artist, thumbnail_url, caption, hashtags_json, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        )
        .run(
          id,
          authorId,
          data.youtubeVideoId,
          data.trackTitle,
          data.artist,
          data.thumbnailUrl ?? null,
          data.caption ?? '',
          JSON.stringify(data.hashtags ?? []),
          ts
        );
      this.social.db.prepare('UPDATE profiles SET posts_count = posts_count + 1 WHERE user_id = ?').run(authorId);
    })();
    return this.getPost(id)!;
  }

  /** `row` must come from a query that joined `profiles` and aliased its
   *  columns `author_username` / `author_display_name` / `author_avatar_url`
   *  (every post-listing query below does) — this is what lets a feed
   *  render `@username` per card without a second query per post. */
  private rowToPost(row: any): MusicPost {
    return {
      id: row.id,
      authorId: row.author_id,
      youtubeVideoId: row.youtube_video_id,
      trackTitle: row.track_title,
      artist: row.artist,
      thumbnailUrl: row.thumbnail_url,
      caption: row.caption,
      hashtags: JSON.parse(row.hashtags_json ?? '[]'),
      likesCount: row.likes_count,
      commentsCount: row.comments_count,
      repostsCount: row.reposts_count,
      sharesCount: row.shares_count,
      createdAt: row.created_at,
      author: row.author_username
        ? {
            userId: row.author_id,
            username: row.author_username,
            displayName: row.author_display_name,
            avatarUrl: row.author_avatar_url ?? null,
          }
        : null,
    };
  }

  private static readonly POST_SELECT_WITH_AUTHOR = `
    SELECT mp.*, p.username as author_username, p.display_name as author_display_name, p.avatar_url as author_avatar_url
    FROM music_posts mp
    JOIN profiles p ON p.user_id = mp.author_id
  `;

  getPost(id: string): MusicPost | null {
    const row = this.social.db
      .prepare(`${SocialService.POST_SELECT_WITH_AUTHOR} WHERE mp.id = ? AND mp.deleted_at IS NULL`)
      .get(id);
    return row ? this.rowToPost(row) : null;
  }

  /** Soft delete — a single post the author removes. Full data erasure only
   *  happens via deleteAccount(), which cascades for real. */
  deletePost(postId: string, requesterId: string): void {
    const row = this.social.db.prepare('SELECT author_id FROM music_posts WHERE id = ?').get(postId) as
      | { author_id: string }
      | undefined;
    if (!row) throw new NotFoundError('Post not found');
    if (row.author_id !== requesterId) throw new ForbiddenError('Not your post');
    this.social.db.transaction(() => {
      this.social.db.prepare('UPDATE music_posts SET deleted_at = ? WHERE id = ?').run(nowIso(), postId);
      this.social.db
        .prepare('UPDATE profiles SET posts_count = MAX(0, posts_count - 1) WHERE user_id = ?')
        .run(row.author_id);
    })();
  }

  /** Cursor-paginated feed. Personalized (followed authors + self) when
   *  viewerUserId is set and that set is non-empty; otherwise a public
   *  chronological feed — real posts either way, never synthetic ranking. */
  getFeed(viewerUserId: string | null, cursor: string | null, limit: number): Page<MusicPost> {
    const c = decodeCursor(cursor);
    const blockedClause = viewerUserId
      ? `AND mp.author_id NOT IN (
           SELECT blocked_id FROM blocks WHERE blocker_id = @viewer
           UNION SELECT blocker_id FROM blocks WHERE blocked_id = @viewer
         )`
      : '';
    const params: Record<string, any> = {
      viewer: viewerUserId,
      createdAt: c?.createdAt ?? null,
      id: c?.id ?? null,
      limit: limit + 1,
    };

    let rows: any[] = [];
    if (viewerUserId) {
      rows = this.social.db
        .prepare(
          `${SocialService.POST_SELECT_WITH_AUTHOR}
           WHERE mp.deleted_at IS NULL
             AND (mp.author_id = @viewer OR mp.author_id IN (SELECT followee_id FROM follows WHERE follower_id = @viewer))
             ${blockedClause}
             AND (@createdAt IS NULL OR mp.created_at < @createdAt OR (mp.created_at = @createdAt AND mp.id < @id))
           ORDER BY mp.created_at DESC, mp.id DESC
           LIMIT @limit`
        )
        .all(params) as any[];
    }
    // Fall back to (or, for guests, always use) the public feed.
    if (rows.length === 0) {
      rows = this.social.db
        .prepare(
          `${SocialService.POST_SELECT_WITH_AUTHOR}
           WHERE mp.deleted_at IS NULL
             ${blockedClause}
             AND (@createdAt IS NULL OR mp.created_at < @createdAt OR (mp.created_at = @createdAt AND mp.id < @id))
           ORDER BY mp.created_at DESC, mp.id DESC
           LIMIT @limit`
        )
        .all(params) as any[];
    }
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      items: page.map((r) => this.rowToPost(r)),
      nextCursor: hasMore ? encodeCursor(page[page.length - 1].created_at, page[page.length - 1].id) : null,
    };
  }

  getPostsByAuthor(authorId: string, cursor: string | null, limit: number): Page<MusicPost> {
    const c = decodeCursor(cursor);
    const rows = this.social.db
      .prepare(
        `${SocialService.POST_SELECT_WITH_AUTHOR}
         WHERE mp.author_id = ? AND mp.deleted_at IS NULL
           AND (? IS NULL OR mp.created_at < ? OR (mp.created_at = ? AND mp.id < ?))
         ORDER BY mp.created_at DESC, mp.id DESC
         LIMIT ?`
      )
      .all(authorId, c?.createdAt ?? null, c?.createdAt ?? null, c?.createdAt ?? null, c?.id ?? null, limit + 1) as any[];
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      items: page.map((r) => this.rowToPost(r)),
      nextCursor: hasMore ? encodeCursor(page[page.length - 1].created_at, page[page.length - 1].id) : null,
    };
  }

  // ─── Likes ─────────────────────────────────────────────────────────────

  hasLiked(postId: string, userId: string): boolean {
    return !!this.social.db.prepare('SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?').get(postId, userId);
  }

  likePost(postId: string, userId: string): void {
    if (this.hasLiked(postId, userId)) return;
    const post = this.social.db.prepare('SELECT author_id FROM music_posts WHERE id = ?').get(postId) as
      | { author_id: string }
      | undefined;
    if (!post) throw new NotFoundError('Post not found');
    this.social.db.transaction(() => {
      this.social.db
        .prepare('INSERT INTO post_likes (post_id, user_id, created_at) VALUES (?, ?, ?)')
        .run(postId, userId, nowIso());
      this.social.db.prepare('UPDATE music_posts SET likes_count = likes_count + 1 WHERE id = ?').run(postId);
      this.insertNotification(post.author_id, 'like', userId, postId, null);
    })();
  }

  unlikePost(postId: string, userId: string): void {
    if (!this.hasLiked(postId, userId)) return;
    this.social.db.transaction(() => {
      this.social.db.prepare('DELETE FROM post_likes WHERE post_id = ? AND user_id = ?').run(postId, userId);
      this.social.db
        .prepare('UPDATE music_posts SET likes_count = MAX(0, likes_count - 1) WHERE id = ?')
        .run(postId);
    })();
  }

  // ─── Comments ──────────────────────────────────────────────────────────

  addComment(postId: string, authorId: string, text: string, parentCommentId: string | null): CommentRow {
    const post = this.social.db.prepare('SELECT author_id FROM music_posts WHERE id = ?').get(postId) as
      | { author_id: string }
      | undefined;
    if (!post) throw new NotFoundError('Post not found');
    const id = newId('cmt');
    const ts = nowIso();
    this.social.db.transaction(() => {
      this.social.db
        .prepare(
          'INSERT INTO comments (id, post_id, author_id, parent_comment_id, text, created_at) VALUES (?, ?, ?, ?, ?, ?)'
        )
        .run(id, postId, authorId, parentCommentId, text, ts);
      this.social.db.prepare('UPDATE music_posts SET comments_count = comments_count + 1 WHERE id = ?').run(postId);
      this.insertNotification(post.author_id, 'comment', authorId, postId, id);
    })();
    return { id, postId, authorId, parentCommentId, text, createdAt: ts };
  }

  listComments(postId: string, cursor: string | null, limit: number): Page<CommentRow> {
    const c = decodeCursor(cursor);
    const rows = this.social.db
      .prepare(
        `SELECT * FROM comments
         WHERE post_id = ? AND deleted_at IS NULL
           AND (? IS NULL OR created_at < ? OR (created_at = ? AND id < ?))
         ORDER BY created_at DESC, id DESC
         LIMIT ?`
      )
      .all(postId, c?.createdAt ?? null, c?.createdAt ?? null, c?.createdAt ?? null, c?.id ?? null, limit + 1) as any[];
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      items: page.map((r) => ({
        id: r.id,
        postId: r.post_id,
        authorId: r.author_id,
        parentCommentId: r.parent_comment_id,
        text: r.text,
        createdAt: r.created_at,
      })),
      nextCursor: hasMore ? encodeCursor(page[page.length - 1].created_at, page[page.length - 1].id) : null,
    };
  }

  deleteComment(commentId: string, requesterId: string): void {
    const row = this.social.db
      .prepare('SELECT post_id, author_id FROM comments WHERE id = ? AND deleted_at IS NULL')
      .get(commentId) as { post_id: string; author_id: string } | undefined;
    if (!row) throw new NotFoundError('Comment not found');
    if (row.author_id !== requesterId) throw new ForbiddenError('Not your comment');
    this.social.db.transaction(() => {
      this.social.db.prepare('UPDATE comments SET deleted_at = ? WHERE id = ?').run(nowIso(), commentId);
      this.social.db
        .prepare('UPDATE music_posts SET comments_count = MAX(0, comments_count - 1) WHERE id = ?')
        .run(row.post_id);
    })();
  }

  // ─── Reposts ───────────────────────────────────────────────────────────

  repost(userId: string, originalPostId: string, caption: string | null): { id: string } {
    const original = this.social.db
      .prepare('SELECT author_id FROM music_posts WHERE id = ? AND deleted_at IS NULL')
      .get(originalPostId) as { author_id: string } | undefined;
    if (!original) throw new NotFoundError('Post not found');
    const existing = this.social.db
      .prepare('SELECT id FROM reposts WHERE user_id = ? AND original_post_id = ?')
      .get(userId, originalPostId) as { id: string } | undefined;
    if (existing) return existing;
    const id = newId('rp');
    this.social.db.transaction(() => {
      this.social.db
        .prepare('INSERT INTO reposts (id, user_id, original_post_id, caption, created_at) VALUES (?, ?, ?, ?, ?)')
        .run(id, userId, originalPostId, caption, nowIso());
      this.social.db.prepare('UPDATE music_posts SET reposts_count = reposts_count + 1 WHERE id = ?').run(originalPostId);
      this.insertNotification(original.author_id, 'repost', userId, originalPostId, null);
    })();
    return { id };
  }

  unrepost(userId: string, originalPostId: string): void {
    const existing = this.social.db
      .prepare('SELECT id FROM reposts WHERE user_id = ? AND original_post_id = ?')
      .get(userId, originalPostId) as { id: string } | undefined;
    if (!existing) return;
    this.social.db.transaction(() => {
      this.social.db.prepare('DELETE FROM reposts WHERE id = ?').run(existing.id);
      this.social.db
        .prepare('UPDATE music_posts SET reposts_count = MAX(0, reposts_count - 1) WHERE id = ?')
        .run(originalPostId);
    })();
  }

  // ─── Saves ─────────────────────────────────────────────────────────────

  savePost(userId: string, postId: string): void {
    this.social.db
      .prepare('INSERT OR IGNORE INTO saved_posts (user_id, post_id, created_at) VALUES (?, ?, ?)')
      .run(userId, postId, nowIso());
  }

  unsavePost(userId: string, postId: string): void {
    this.social.db.prepare('DELETE FROM saved_posts WHERE user_id = ? AND post_id = ?').run(userId, postId);
  }

  listSaved(userId: string, cursor: string | null, limit: number): Page<MusicPost> {
    const c = decodeCursor(cursor);
    const rows = this.social.db
      .prepare(
        `SELECT mp.*, p.username as author_username, p.display_name as author_display_name, p.avatar_url as author_avatar_url
         FROM saved_posts sp
         JOIN music_posts mp ON mp.id = sp.post_id AND mp.deleted_at IS NULL
         JOIN profiles p ON p.user_id = mp.author_id
         WHERE sp.user_id = ?
           AND (? IS NULL OR sp.created_at < ? OR (sp.created_at = ? AND sp.post_id < ?))
         ORDER BY sp.created_at DESC, sp.post_id DESC
         LIMIT ?`
      )
      .all(userId, c?.createdAt ?? null, c?.createdAt ?? null, c?.createdAt ?? null, c?.id ?? null, limit + 1) as any[];
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      items: page.map((r) => this.rowToPost(r)),
      nextCursor: hasMore ? encodeCursor(page[page.length - 1].created_at, page[page.length - 1].id) : null,
    };
  }

  // ─── Blocks / reports ──────────────────────────────────────────────────

  blockUser(blockerId: string, blockedId: string): void {
    if (blockerId === blockedId) throw new ForbiddenError('Cannot block yourself');
    this.social.db.transaction(() => {
      this.social.db
        .prepare('INSERT OR IGNORE INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)')
        .run(blockerId, blockedId, nowIso());
      // A block also severs any existing follow in either direction.
      this.unfollow(blockerId, blockedId);
      this.unfollow(blockedId, blockerId);
    })();
  }

  unblockUser(blockerId: string, blockedId: string): void {
    this.social.db.prepare('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?').run(blockerId, blockedId);
  }

  listBlocked(blockerId: string): PublicProfile[] {
    const rows = this.social.db
      .prepare(
        `SELECT p.* FROM blocks b JOIN profiles p ON p.user_id = b.blocked_id
         WHERE b.blocker_id = ? ORDER BY b.created_at DESC`
      )
      .all(blockerId) as any[];
    return rows.map((r) => this.rowToProfile(r));
  }

  report(reporterId: string, targetType: 'post' | 'comment' | 'user', targetId: string, reason: string, details?: string) {
    const id = newId('rep');
    this.social.db
      .prepare(
        'INSERT INTO reports (id, reporter_id, target_type, target_id, reason, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
      )
      .run(id, reporterId, targetType, targetId, reason, details ?? null, nowIso());
    return { id };
  }

  // ─── Notifications ─────────────────────────────────────────────────────

  private insertNotification(
    recipientId: string,
    type: 'follow' | 'like' | 'comment' | 'repost' | 'mention',
    actorId: string,
    postId: string | null,
    commentId: string | null
  ) {
    if (recipientId === actorId) return; // never notify yourself
    this.social.db
      .prepare(
        'INSERT INTO notifications (id, user_id, type, actor_id, post_id, comment_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
      )
      .run(newId('ntf'), recipientId, type, actorId, postId, commentId, nowIso());
  }

  listNotifications(userId: string, cursor: string | null, limit: number): Page<NotificationRow> {
    const c = decodeCursor(cursor);
    const rows = this.social.db
      .prepare(
        `SELECT * FROM notifications
         WHERE user_id = ?
           AND (? IS NULL OR created_at < ? OR (created_at = ? AND id < ?))
         ORDER BY created_at DESC, id DESC
         LIMIT ?`
      )
      .all(userId, c?.createdAt ?? null, c?.createdAt ?? null, c?.createdAt ?? null, c?.id ?? null, limit + 1) as any[];
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    return {
      items: page.map((r) => ({
        id: r.id,
        type: r.type,
        actorId: r.actor_id,
        postId: r.post_id,
        commentId: r.comment_id,
        createdAt: r.created_at,
        readAt: r.read_at,
      })),
      nextCursor: hasMore ? encodeCursor(page[page.length - 1].created_at, page[page.length - 1].id) : null,
    };
  }

  markNotificationsRead(userId: string, ids: string[] | 'all'): void {
    if (ids === 'all') {
      this.social.db
        .prepare('UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL')
        .run(nowIso(), userId);
      return;
    }
    const stmt = this.social.db.prepare(
      'UPDATE notifications SET read_at = ? WHERE user_id = ? AND id = ? AND read_at IS NULL'
    );
    const ts = nowIso();
    const tx = this.social.db.transaction((idList: string[]) => {
      for (const id of idList) stmt.run(ts, userId, id);
    });
    tx(ids);
  }

  unreadNotificationCount(userId: string): number {
    const row = this.social.db
      .prepare('SELECT COUNT(*) as c FROM notifications WHERE user_id = ? AND read_at IS NULL')
      .get(userId) as { c: number };
    return row.c;
  }

  // ─── AI preferences / Private Session ─────────────────────────────────

  getPreferences(userId: string): { privateSession: boolean; aiPersonalizationEnabled: boolean } {
    const row = this.social.db.prepare('SELECT * FROM user_preferences WHERE user_id = ?').get(userId) as any;
    if (!row) return { privateSession: false, aiPersonalizationEnabled: true };
    return {
      privateSession: !!row.private_session,
      aiPersonalizationEnabled: !!row.ai_personalization_enabled,
    };
  }

  setPreferences(userId: string, patch: { privateSession?: boolean; aiPersonalizationEnabled?: boolean }): void {
    const current = this.getPreferences(userId);
    const next = { ...current, ...patch };
    this.social.db
      .prepare(
        `INSERT INTO user_preferences (user_id, private_session, ai_personalization_enabled, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           private_session = excluded.private_session,
           ai_personalization_enabled = excluded.ai_personalization_enabled,
           updated_at = excluded.updated_at`
      )
      .run(userId, next.privateSession ? 1 : 0, next.aiPersonalizationEnabled ? 1 : 0, nowIso());
  }

  // ─── Account deletion (Phase 9 — real erasure, not hiding) ────────────

  deleteAccount(userId: string): void {
    this.social.db.transaction(() => {
      // Unwind this user's footprint on OTHER users' data first, reusing
      // the exact same counter-adjusting methods used everywhere else —
      // this is what keeps other people's follower/like/comment counts
      // correct after the cascade below removes the raw rows.
      const following = this.social.db
        .prepare('SELECT followee_id FROM follows WHERE follower_id = ?')
        .all(userId) as { followee_id: string }[];
      for (const { followee_id } of following) this.unfollow(userId, followee_id);

      const followers = this.social.db
        .prepare('SELECT follower_id FROM follows WHERE followee_id = ?')
        .all(userId) as { follower_id: string }[];
      for (const { follower_id } of followers) this.unfollow(follower_id, userId);

      const likedElsewhere = this.social.db
        .prepare(
          `SELECT pl.post_id FROM post_likes pl JOIN music_posts mp ON mp.id = pl.post_id
           WHERE pl.user_id = ? AND mp.author_id != ?`
        )
        .all(userId, userId) as { post_id: string }[];
      for (const { post_id } of likedElsewhere) this.unlikePost(post_id, userId);

      const repostedElsewhere = this.social.db
        .prepare('SELECT original_post_id FROM reposts WHERE user_id = ?')
        .all(userId) as { original_post_id: string }[];
      for (const { original_post_id } of repostedElsewhere) this.unrepost(userId, original_post_id);

      const commentedElsewhere = this.social.db
        .prepare(
          `SELECT c.id FROM comments c JOIN music_posts mp ON mp.id = c.post_id
           WHERE c.author_id = ? AND c.deleted_at IS NULL AND mp.author_id != ?`
        )
        .all(userId, userId) as { id: string }[];
      for (const { id } of commentedElsewhere) this.deleteComment(id, userId);

      // Finally, the user row itself — ON DELETE CASCADE removes:
      // profile, own posts (and, transitively, those posts' own likes/
      // comments/reposts/saves/notifications), own remaining comments,
      // blocks either direction, ai_messages, user_preferences.
      this.social.db.prepare('DELETE FROM users WHERE id = ?').run(userId);
    })();
  }
}

let _shared: SocialService | null = null;
export function sharedSocialService(): SocialService {
  if (!_shared) _shared = new SocialService(sharedSocialDb());
  return _shared;
}
