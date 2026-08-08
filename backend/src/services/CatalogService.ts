import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import { RozzaTrack } from '../types';
import { decodeHtmlEntities } from '../utils/text';

// ─────────────────────────────────────────────────────────────────────────────
// CatalogService — SQLite-backed music catalog
// Stores real discovered tracks, aliases, and search cache.
// Every YouTube search result is persisted here to reduce future API calls.
// ─────────────────────────────────────────────────────────────────────────────

// ROZZA_DATA_DIR points at the mounted volume in production; without a
// persistent mount the catalog is rebuilt from scratch on every redeploy.
const DB_DIR = process.env.ROZZA_DATA_DIR
  ? path.resolve(process.env.ROZZA_DATA_DIR)
  : path.join(__dirname, '../../data');
const DB_PATH = path.join(DB_DIR, 'rozza_catalog.db');

function ensureDbDir() {
  if (!fs.existsSync(DB_DIR)) fs.mkdirSync(DB_DIR, { recursive: true });
}

class CatalogService {
  private db: Database.Database;

  constructor() {
    ensureDbDir();
    this.db = new Database(DB_PATH);
    this.db.pragma('journal_mode = WAL');
    this.db.pragma('foreign_keys = ON');
    this.migrate();
    this.decodeStoredEntities();
  }

  private migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS tracks (
        id          TEXT PRIMARY KEY,
        title       TEXT NOT NULL,
        artist      TEXT NOT NULL,
        album       TEXT,
        artwork     TEXT,
        duration_s  INTEGER,
        language    TEXT,
        region      TEXT,
        genre       TEXT,
        popularity  INTEGER DEFAULT 50,
        youtube_id  TEXT UNIQUE,
        sources_json TEXT NOT NULL DEFAULT '[]',
        discovered_at TEXT NOT NULL,
        updated_at  TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_tracks_youtube ON tracks(youtube_id);
      CREATE INDEX IF NOT EXISTS idx_tracks_artist  ON tracks(artist COLLATE NOCASE);
      CREATE INDEX IF NOT EXISTS idx_tracks_title   ON tracks(title COLLATE NOCASE);
      CREATE INDEX IF NOT EXISTS idx_tracks_lang    ON tracks(language);
      CREATE INDEX IF NOT EXISTS idx_tracks_pop     ON tracks(popularity DESC);

      CREATE TABLE IF NOT EXISTS aliases (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        alias    TEXT NOT NULL COLLATE NOCASE
      );

      CREATE INDEX IF NOT EXISTS idx_aliases_alias ON aliases(alias);

      CREATE TABLE IF NOT EXISTS search_cache (
        query_hash  TEXT PRIMARY KEY,
        query_text  TEXT NOT NULL,
        results_json TEXT NOT NULL,
        cached_at   TEXT NOT NULL,
        expires_at  TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS trending (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id    TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        region      TEXT NOT NULL DEFAULT 'GLOBAL',
        score       INTEGER DEFAULT 0,
        updated_at  TEXT NOT NULL
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_trending_track_region ON trending(track_id, region);
    `);
  }

  /**
   * Titles discovered before the YouTube provider started decoding HTML
   * entities are still stored with `&amp;` and `&quot;` in them. They are shown
   * verbatim in the UI and fed into alias matching, so clean them once at boot
   * rather than leaving the catalog permanently wrong.
   */
  private decodeStoredEntities(): void {
    const rows = this.db.prepare(
      `SELECT id, title, artist, album FROM tracks
       WHERE title LIKE '%&%' OR artist LIKE '%&%' OR album LIKE '%&%'`
    ).all() as { id: string; title: string; artist: string; album: string | null }[];
    if (rows.length === 0) return;

    const update = this.db.prepare('UPDATE tracks SET title = ?, artist = ?, album = ? WHERE id = ?');
    const updateAlias = this.db.prepare('UPDATE aliases SET alias = ? WHERE alias = ?');
    let changed = 0;
    const run = this.db.transaction(() => {
      for (const row of rows) {
        const title = decodeHtmlEntities(row.title);
        const artist = decodeHtmlEntities(row.artist);
        const album = row.album ? decodeHtmlEntities(row.album) : null;
        if (title === row.title && artist === row.artist && album === row.album) continue;
        update.run(title, artist, album, row.id);
        if (title !== row.title) updateAlias.run(title, row.title);
        if (artist !== row.artist) updateAlias.run(artist, row.artist);
        changed += 1;
      }
      // Cached search responses embed copies of these titles, so they would
      // keep serving the old text until they expired.
      if (changed > 0) this.db.prepare('DELETE FROM search_cache').run();
    });

    try {
      run();
      if (changed > 0) console.log(`[Catalog] Decoded HTML entities in ${changed} stored track(s); search cache cleared`);
    } catch (error: any) {
      // A pre-existing alias row can collide; the catalog is still usable.
      console.warn('[Catalog] Entity cleanup skipped:', error?.message);
    }
  }

  // ── Upsert discovered tracks ──────────────────────────────────────────────
  upsertTrack(track: RozzaTrack): void {
    const now = new Date().toISOString();
    const youtubeSource = track.sources.find(s => s.provider === 'youtube');

    const stmt = this.db.prepare(`
      INSERT INTO tracks (id, title, artist, album, artwork, duration_s, language, region, genre, popularity, youtube_id, sources_json, discovered_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title       = excluded.title,
        artwork     = excluded.artwork,
        popularity  = MAX(tracks.popularity, excluded.popularity),
        sources_json = excluded.sources_json,
        updated_at  = excluded.updated_at
    `);

    stmt.run(
      track.id, track.title, track.artist, track.album ?? null,
      track.artwork, track.durationSeconds ?? null,
      track.language, track.region ?? null, track.genre ?? null,
      track.popularity, youtubeSource?.providerId ?? null,
      JSON.stringify(track.sources), track.discoveredAt ?? now, now
    );

    // Upsert aliases
    const aliasCheck = this.db.prepare('SELECT id FROM aliases WHERE track_id = ? AND alias = ?');
    const aliasInsert = this.db.prepare('INSERT OR IGNORE INTO aliases (track_id, alias) VALUES (?, ?)');
    for (const alias of track.aliases) {
      if (!aliasCheck.get(track.id, alias.toLowerCase())) {
        aliasInsert.run(track.id, alias.toLowerCase());
      }
    }
  }

  upsertBatch(tracks: RozzaTrack[]): void {
    const upsert = this.db.transaction(() => {
      for (const t of tracks) this.upsertTrack(t);
    });
    upsert();
  }

  // ── Search in catalog ─────────────────────────────────────────────────────
  search(query: string, limit = 20): RozzaTrack[] {
    const q = `%${query.toLowerCase()}%`;

    const rows = this.db.prepare(`
      SELECT DISTINCT t.* FROM tracks t
      LEFT JOIN aliases a ON a.track_id = t.id
      WHERE lower(t.title) LIKE ?
        OR lower(t.artist) LIKE ?
        OR lower(t.album) LIKE ?
        OR lower(a.alias) LIKE ?
      ORDER BY t.popularity DESC
      LIMIT ?
    `).all(q, q, q, q, limit) as any[];

    return rows.map(this.rowToTrack);
  }

  findByYoutubeId(videoId: string): RozzaTrack | null {
    const row = this.db.prepare('SELECT * FROM tracks WHERE youtube_id = ?').get(videoId) as any;
    return row ? this.rowToTrack(row) : null;
  }

  // ── Trending ──────────────────────────────────────────────────────────────
  upsertTrending(trackId: string, region: string, score: number): void {
    this.db.prepare(`
      INSERT INTO trending (track_id, region, score, updated_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(track_id, region) DO UPDATE SET score = excluded.score, updated_at = excluded.updated_at
    `).run(trackId, region, score, new Date().toISOString());
  }

  getTrending(region = 'GLOBAL', limit = 20): RozzaTrack[] {
    const rows = this.db.prepare(`
      SELECT t.* FROM tracks t
      JOIN trending tr ON tr.track_id = t.id
      WHERE tr.region = ?
      ORDER BY tr.score DESC, t.popularity DESC
      LIMIT ?
    `).all(region, limit) as any[];
    return rows.map(this.rowToTrack);
  }

  // ── Search Cache ──────────────────────────────────────────────────────────
  getCachedSearch(queryHash: string): { results: any; query: string } | null {
    const row = this.db.prepare(`
      SELECT * FROM search_cache WHERE query_hash = ? AND expires_at > ?
    `).get(queryHash, new Date().toISOString()) as any;
    if (!row) return null;
    return { results: JSON.parse(row.results_json), query: row.query_text };
  }

  setCachedSearch(queryHash: string, queryText: string, results: any, ttlMinutes = 60): void {
    const now = new Date();
    const expires = new Date(now.getTime() + ttlMinutes * 60 * 1000);
    this.db.prepare(`
      INSERT OR REPLACE INTO search_cache (query_hash, query_text, results_json, cached_at, expires_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(queryHash, queryText, JSON.stringify(results), now.toISOString(), expires.toISOString());
  }

  cleanExpiredCache(): number {
    const result = this.db.prepare('DELETE FROM search_cache WHERE expires_at <= ?').run(new Date().toISOString());
    return result.changes;
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  stats(): { trackCount: number; aliasCount: number; cacheEntries: number } {
    const trackCount = (this.db.prepare('SELECT COUNT(*) as c FROM tracks').get() as any).c;
    const aliasCount = (this.db.prepare('SELECT COUNT(*) as c FROM aliases').get() as any).c;
    const cacheEntries = (this.db.prepare('SELECT COUNT(*) as c FROM search_cache WHERE expires_at > ?').get(new Date().toISOString()) as any).c;
    return { trackCount, aliasCount, cacheEntries };
  }

  private rowToTrack(row: any): RozzaTrack {
    return {
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: row.album ?? undefined,
      artwork: row.artwork ?? '',
      durationSeconds: row.duration_s ?? undefined,
      language: row.language ?? 'other',
      region: row.region ?? undefined,
      genre: row.genre ?? undefined,
      popularity: row.popularity ?? 50,
      aliases: [],
      sources: (JSON.parse(row.sources_json ?? '[]') as any[]).map(source => {
        const nativeAudio = source.provider !== 'youtube' && Boolean(source.url);
        return {
          ...source,
          canPlay: source.canPlay ?? (source.provider === 'youtube' || nativeAudio),
          canBackgroundPlay: source.canBackgroundPlay ?? nativeAudio,
          canDownload: source.canDownload ?? false,
          canOfflinePlay: source.canOfflinePlay ?? source.provider === 'local',
          supportsLockScreen: source.supportsLockScreen ?? nativeAudio,
          supportsControlCenter: source.supportsControlCenter ?? nativeAudio
        };
      }),
      discoveredAt: row.discovered_at,
      updatedAt: row.updated_at
    };
  }
}

export const Catalog = new CatalogService();
