import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';

// ─────────────────────────────────────────────────────────────────────────────
// SocialDb — SQLite-backed accounts + social graph + feed store.
//
// Same storage pattern as CatalogService.ts (better-sqlite3, WAL mode,
// ROZZA_DATA_DIR-aware, `CREATE TABLE IF NOT EXISTS` migrations run at boot) —
// this is a second database file (`rozza_social.db`) rather than new tables
// bolted onto the catalog DB, so the catalog (which existed before any of
// this and must keep working unmodified) and the new account/social data
// never share a schema or a lock.
//
// Why SQLite and not Supabase/Postgres: there was no existing auth/database
// layer in this backend at all before this pass, and this session has no
// ability to create a Supabase project on the account owner's behalf (that
// needs their own account + credentials). `better-sqlite3` was already a
// declared backend dependency and the exact ROZZA_DATA_DIR + persistent Fly
// volume convention this needs already exists (see CatalogService.ts and
// fly.toml). This keeps everything real, testable, and running today,
// without inventing infrastructure or fabricating credentials. See
// docs/AUTH_ARCHITECTURE.md for the documented Postgres/Supabase migration
// path if/when the account owner wants managed infra at real scale.
//
// Every foreign key that should cascade does (ON DELETE CASCADE), so a real
// account deletion (Phase 9) is a small number of top-level deletes, not a
// hand-maintained list of every table.
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_DB_DIR = process.env.ROZZA_DATA_DIR
  ? path.resolve(process.env.ROZZA_DATA_DIR)
  : path.join(__dirname, '../../data');

function ensureDir(dir: string) {
  if (dir !== ':memory:' && !fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

export function newId(prefix: string): string {
  return `${prefix}_${crypto.randomBytes(12).toString('hex')}`;
}

export class SocialDb {
  db: Database.Database;

  /** @param dbPath Pass ':memory:' or a temp file path in tests. */
  constructor(dbPath?: string) {
    const resolved = dbPath ?? path.join(DEFAULT_DB_DIR, 'rozza_social.db');
    if (resolved !== ':memory:') ensureDir(path.dirname(resolved));
    this.db = new Database(resolved);
    // See the matching comment in CatalogService.ts — a real busy_timeout
    // instead of the driver's near-zero default.
    this.db.pragma('busy_timeout = 5000');
    this.db.pragma('journal_mode = WAL');
    this.db.pragma('foreign_keys = ON');
    this.migrate();
  }

  close() {
    this.db.close();
  }

  private migrate() {
    this.db.exec(`
      -- ─── Accounts ────────────────────────────────────────────────────────
      CREATE TABLE IF NOT EXISTS users (
        id            TEXT PRIMARY KEY,
        apple_sub     TEXT UNIQUE,
        email         TEXT UNIQUE COLLATE NOCASE,
        token_version INTEGER NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL,
        last_login_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS profiles (
        user_id           TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        username          TEXT NOT NULL UNIQUE COLLATE NOCASE,
        display_name      TEXT NOT NULL,
        avatar_url        TEXT,
        bio               TEXT NOT NULL DEFAULT '',
        country           TEXT,
        preferred_language TEXT,
        is_creator        INTEGER NOT NULL DEFAULT 0,
        followers_count   INTEGER NOT NULL DEFAULT 0,
        following_count   INTEGER NOT NULL DEFAULT 0,
        posts_count       INTEGER NOT NULL DEFAULT 0,
        created_at        TEXT NOT NULL,
        updated_at        TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_profiles_username ON profiles(username COLLATE NOCASE);

      -- Passwordless email sign-in codes. Hashed at rest; never store a
      -- code in the clear even though it is short-lived.
      CREATE TABLE IF NOT EXISTS auth_email_codes (
        email      TEXT PRIMARY KEY COLLATE NOCASE,
        code_hash  TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        attempts   INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );

      -- ─── Social graph ────────────────────────────────────────────────────
      CREATE TABLE IF NOT EXISTS follows (
        follower_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        followee_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at  TEXT NOT NULL,
        PRIMARY KEY (follower_id, followee_id)
      );
      CREATE INDEX IF NOT EXISTS idx_follows_followee ON follows(followee_id, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS blocks (
        blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        PRIMARY KEY (blocker_id, blocked_id)
      );
      CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);

      -- ─── Posts (a ROZZA post; the media itself stays on YouTube) ────────
      CREATE TABLE IF NOT EXISTS music_posts (
        id                TEXT PRIMARY KEY,
        author_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        youtube_video_id  TEXT NOT NULL,
        track_title       TEXT NOT NULL,
        artist            TEXT NOT NULL,
        thumbnail_url     TEXT,
        caption           TEXT NOT NULL DEFAULT '',
        hashtags_json     TEXT NOT NULL DEFAULT '[]',
        likes_count       INTEGER NOT NULL DEFAULT 0,
        comments_count    INTEGER NOT NULL DEFAULT 0,
        reposts_count     INTEGER NOT NULL DEFAULT 0,
        shares_count      INTEGER NOT NULL DEFAULT 0,
        created_at        TEXT NOT NULL,
        deleted_at        TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_posts_author ON music_posts(author_id, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_posts_feed   ON music_posts(deleted_at, created_at DESC);

      CREATE TABLE IF NOT EXISTS post_likes (
        post_id    TEXT NOT NULL REFERENCES music_posts(id) ON DELETE CASCADE,
        user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        PRIMARY KEY (post_id, user_id)
      );
      CREATE INDEX IF NOT EXISTS idx_likes_user ON post_likes(user_id, created_at DESC);

      -- parent_comment_id exists now (nullable, unused) so threaded replies
      -- can be added later without another migration, per the mission spec.
      CREATE TABLE IF NOT EXISTS comments (
        id                TEXT PRIMARY KEY,
        post_id           TEXT NOT NULL REFERENCES music_posts(id) ON DELETE CASCADE,
        author_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        parent_comment_id TEXT REFERENCES comments(id) ON DELETE CASCADE,
        text              TEXT NOT NULL,
        created_at        TEXT NOT NULL,
        deleted_at        TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_id, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_comments_author ON comments(author_id);

      -- A repost points at the original; it never copies the YouTube
      -- reference or media into a second row.
      CREATE TABLE IF NOT EXISTS reposts (
        id               TEXT PRIMARY KEY,
        user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        original_post_id TEXT NOT NULL REFERENCES music_posts(id) ON DELETE CASCADE,
        caption          TEXT,
        created_at       TEXT NOT NULL,
        UNIQUE (user_id, original_post_id)
      );
      CREATE INDEX IF NOT EXISTS idx_reposts_original ON reposts(original_post_id);
      CREATE INDEX IF NOT EXISTS idx_reposts_user ON reposts(user_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS saved_posts (
        user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        post_id    TEXT NOT NULL REFERENCES music_posts(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        PRIMARY KEY (user_id, post_id)
      );

      -- ─── Safety ──────────────────────────────────────────────────────────
      CREATE TABLE IF NOT EXISTS reports (
        id          TEXT PRIMARY KEY,
        reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        target_type TEXT NOT NULL CHECK (target_type IN ('post','comment','user')),
        target_id   TEXT NOT NULL,
        reason      TEXT NOT NULL,
        details     TEXT,
        status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewed','dismissed')),
        created_at  TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at DESC);

      -- ─── Notifications ───────────────────────────────────────────────────
      CREATE TABLE IF NOT EXISTS notifications (
        id         TEXT PRIMARY KEY,
        user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        type       TEXT NOT NULL CHECK (type IN ('follow','like','comment','repost','mention')),
        actor_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        post_id    TEXT REFERENCES music_posts(id) ON DELETE CASCADE,
        comment_id TEXT REFERENCES comments(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        read_at    TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC);

      -- ─── AI ──────────────────────────────────────────────────────────────
      -- Durable replacement for ai.ts's in-memory conversationStore Map
      -- (lost on every restart). user_id is nullable — guests get real AI
      -- too, keyed only by session_id.
      CREATE TABLE IF NOT EXISTS ai_messages (
        id         TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        user_id    TEXT REFERENCES users(id) ON DELETE CASCADE,
        role       TEXT NOT NULL CHECK (role IN ('user','assistant','tool')),
        content    TEXT NOT NULL,
        tool_calls_json TEXT,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_ai_messages_session ON ai_messages(session_id, created_at);

      CREATE TABLE IF NOT EXISTS user_preferences (
        user_id                     TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        private_session             INTEGER NOT NULL DEFAULT 0,
        ai_personalization_enabled  INTEGER NOT NULL DEFAULT 1,
        updated_at                  TEXT NOT NULL
      );
    `);

    // ─── Username/password + Google sign-in (added after the users table
    // already had real rows on the deployed Fly volume) ───────────────────
    // SQLite can't ALTER TABLE ... ADD COLUMN IF NOT EXISTS, and can't add a
    // UNIQUE column constraint via ALTER TABLE at all — so this checks
    // pragma_table_info first (safe to run on every boot) and enforces
    // uniqueness with a separate partial index instead.
    this.addColumnIfMissing('users', 'password_hash', 'TEXT');
    this.addColumnIfMissing('users', 'google_sub', 'TEXT');
    this.db.exec(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub
        ON users(google_sub) WHERE google_sub IS NOT NULL;
    `);
  }

  private addColumnIfMissing(table: string, column: string, type: string) {
    const cols = this.db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
    if (!cols.some((c) => c.name === column)) {
      this.db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
    }
  }
}

let _shared: SocialDb | null = null;
/** Process-wide singleton, same lifecycle pattern as Catalog in CatalogService.ts. */
export function sharedSocialDb(): SocialDb {
  if (!_shared) _shared = new SocialDb();
  return _shared;
}
