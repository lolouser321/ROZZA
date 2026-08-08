import crypto from 'crypto';

// ─────────────────────────────────────────────────────────────────────────────
// SearchCache — in-memory L1 cache in front of SQLite.
// Prevents repeated DB reads for hot queries during the same server session.
// ─────────────────────────────────────────────────────────────────────────────

interface CacheEntry {
  data: any;
  expiresAt: number;
}

class SearchCache {
  private cache = new Map<string, CacheEntry>();
  private readonly defaultTtlMs: number;

  constructor() {
    const ttlMin = parseInt(process.env.SEARCH_CACHE_TTL_MINUTES ?? '60', 10);
    this.defaultTtlMs = ttlMin * 60 * 1000;

    // Periodic cleanup every 10 minutes
    setInterval(() => this.evictExpired(), 10 * 60 * 1000);
  }

  hashQuery(query: string): string {
    return crypto.createHash('sha256').update(query.toLowerCase().trim()).digest('hex').slice(0, 16);
  }

  get(key: string): any | null {
    const entry = this.cache.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expiresAt) {
      this.cache.delete(key);
      return null;
    }
    return entry.data;
  }

  set(key: string, data: any, ttlMs?: number): void {
    this.cache.set(key, {
      data,
      expiresAt: Date.now() + (ttlMs ?? this.defaultTtlMs)
    });
  }

  has(key: string): boolean {
    return this.get(key) !== null;
  }

  delete(key: string): void {
    this.cache.delete(key);
  }

  evictExpired(): number {
    let count = 0;
    const now = Date.now();
    for (const [key, entry] of this.cache.entries()) {
      if (now > entry.expiresAt) {
        this.cache.delete(key);
        count++;
      }
    }
    return count;
  }

  size(): number {
    return this.cache.size;
  }
}

export const MemoryCache = new SearchCache();
