import { Router, Request, Response } from 'express';
import { Catalog } from '../services/CatalogService';
import { RozzaTrack } from '../types';
import { v4 as uuidv4 } from 'uuid';

const router = Router();

router.post('/direct', (req: Request, res: Response) => {
  const adminToken = process.env.ADMIN_SEED_TOKEN;
  if (!adminToken || req.headers['x-admin-token'] !== adminToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const { title, artist, album, artwork, url, durationSeconds, genre, language } = req.body ?? {};
  if (!title || !artist || !url) return res.status(400).json({ error: 'title, artist and url are required' });

  let parsed: URL;
  try { parsed = new URL(url); } catch { return res.status(400).json({ error: 'Invalid audio URL' }); }
  const allowedHosts = (process.env.AUTHORIZED_AUDIO_HOSTS ?? '').split(',').map((v: string) => v.trim().toLowerCase()).filter(Boolean);
  if (parsed.protocol !== 'https:' || !allowedHosts.includes(parsed.hostname.toLowerCase())) {
    return res.status(400).json({ error: 'Audio host is not present in AUTHORIZED_AUDIO_HOSTS' });
  }

  const now = new Date().toISOString();
  const track: RozzaTrack = {
    id: `direct-${uuidv4()}`, title, artist, album, artwork: artwork ?? '',
    durationSeconds: Number(durationSeconds) || undefined,
    language: ['ar', 'en', 'instrumental', 'other'].includes(language) ? language : 'other',
    region: 'GLOBAL', genre, popularity: 50, aliases: [title, artist],
    sources: [{
      provider: 'direct', providerId: parsed.href, url: parsed.href,
      canPlay: true, canBackgroundPlay: true, canDownload: false,
      canOfflinePlay: false, supportsLockScreen: true, supportsControlCenter: true
    }],
    discoveredAt: now, updatedAt: now
  };
  Catalog.upsertTrack(track);
  return res.status(201).json({ track });
});

export default router;
