import { Router, Request, Response } from 'express';
import { YouTubeProvider } from '../providers/music/YouTubeProvider';
import { AudDProvider } from '../providers/recognition/AudDProvider';
import { getAIProvider } from '../providers/ai/AIProviderFactory';
import { AudiusProvider } from '../providers/music/AudiusProvider';
import { JamendoProvider } from '../providers/music/JamendoProvider';
import { SpotifyProvider } from '../providers/music/SpotifyProvider';
import { Catalog } from '../services/CatalogService';
import { HealthReport, ProviderHealth } from '../types';

const router = Router();
const youtube = new YouTubeProvider();
const audd = new AudDProvider();
const audius = new AudiusProvider();
const jamendo = new JamendoProvider();
const spotify = new SpotifyProvider();

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/health/providers — DEV/ADMIN ONLY
// Protected by ADMIN_SEED_TOKEN header
// ─────────────────────────────────────────────────────────────────────────────
router.get('/providers', async (req: Request, res: Response) => {
  const adminToken = process.env.ADMIN_SEED_TOKEN;
  const providedToken = req.headers['x-admin-token'] as string;

  if (!adminToken && process.env.NODE_ENV === 'production') {
    return res.status(404).json({ error: 'Not found' });
  }
  if (adminToken && providedToken !== adminToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const ai = getAIProvider();

  // Run provider health checks concurrently
  const [ytHealth, aiHealth, auddHealth, audiusHealth, jamendoHealth, spotifyHealth] = await Promise.allSettled([
    youtube.healthCheck(),
    ai.healthCheck(),
    audd.healthCheck(),
    audius.healthCheck(),
    jamendo.healthCheck(),
    spotify.healthCheck()
  ]);

  const providers: Record<string, ProviderHealth> = {
    youtube: {
      name: 'YouTube Data API v3',
      configured: youtube.isConfigured(),
      healthy: ytHealth.status === 'fulfilled' ? ytHealth.value.healthy : false,
      latencyMs: ytHealth.status === 'fulfilled' ? ytHealth.value.latencyMs : undefined,
      error: ytHealth.status === 'fulfilled' ? ytHealth.value.error : String((ytHealth as any).reason)
    },
    [ai.providerName]: {
      name: `AI (${ai.providerName} / ${ai.modelName})`,
      configured: ai.isConfigured(),
      healthy: aiHealth.status === 'fulfilled' ? aiHealth.value.healthy : false,
      latencyMs: aiHealth.status === 'fulfilled' ? aiHealth.value.latencyMs : undefined,
      error: aiHealth.status === 'fulfilled' ? aiHealth.value.error : String((aiHealth as any).reason)
    },
    recognition: {
      name: 'AudD Music Recognition',
      configured: audd.isConfigured(),
      healthy: auddHealth.status === 'fulfilled' ? auddHealth.value.healthy : false,
      error: auddHealth.status === 'fulfilled' ? auddHealth.value.error : String((auddHealth as any).reason)
    },
    audius: {
      name: 'Audius Open Audio API', configured: audius.isConfigured(),
      healthy: audiusHealth.status === 'fulfilled' ? audiusHealth.value.healthy : false,
      latencyMs: audiusHealth.status === 'fulfilled' ? audiusHealth.value.latencyMs : undefined,
      error: audiusHealth.status === 'fulfilled' ? audiusHealth.value.error : String((audiusHealth as any).reason)
    },
    jamendo: {
      name: 'Jamendo API', configured: jamendo.isConfigured(),
      healthy: jamendoHealth.status === 'fulfilled' ? jamendoHealth.value.healthy : false,
      latencyMs: jamendoHealth.status === 'fulfilled' ? jamendoHealth.value.latencyMs : undefined,
      error: jamendoHealth.status === 'fulfilled' ? jamendoHealth.value.error : String((jamendoHealth as any).reason)
    },
    spotify: {
      name: 'Spotify Web API (catalog search)', configured: spotify.isConfigured(),
      healthy: spotifyHealth.status === 'fulfilled' ? spotifyHealth.value.healthy : false,
      latencyMs: spotifyHealth.status === 'fulfilled' ? spotifyHealth.value.latencyMs : undefined,
      error: spotifyHealth.status === 'fulfilled' ? spotifyHealth.value.error : String((spotifyHealth as any).reason)
    },
    catalog: {
      name: 'ROZZA Catalog',
      configured: true,
      healthy: true
    }
  };

  const catalogStats = Catalog.stats();
  const allHealthy = Object.values(providers).every(p => !p.configured || p.healthy);

  const report: HealthReport = {
    status: allHealthy ? 'ok' : 'degraded',
    providers,
    catalog: {
      healthy: true,
      trackCount: catalogStats.trackCount,
      cacheEntries: catalogStats.cacheEntries
    },
    timestamp: new Date().toISOString()
  };

  // Never expose actual API key values — only configuration status
  return res.json(report);
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/health — public minimal ping
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', (_req: Request, res: Response) => {
  const catalogStats = Catalog.stats();
  res.json({
    status: 'ok',
    server: 'ROZZA Backend',
    version: '1.0.0',
    catalog: { trackCount: catalogStats.trackCount },
    timestamp: new Date().toISOString()
  });
});

export default router;
