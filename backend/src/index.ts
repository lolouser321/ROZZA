import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';

import searchRoutes from './routes/search';
import aiRoutes from './routes/ai';
import recognitionRoutes from './routes/recognition';
import healthRoutes from './routes/health';
import catalogRoutes from './routes/catalog';
import v2Routes from './routes/v2';
import { getAIProvider } from './providers/ai/AIProviderFactory';

const app = express();
const PORT = parseInt(process.env.PORT ?? '3001', 10);
const HOST = process.env.HOST ?? '0.0.0.0';

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use(cors({
  // The iPhone client is native, so CORS only matters for the web build; set
  // ALLOWED_ORIGINS to a comma-separated list to restrict it in production.
  origin: process.env.ALLOWED_ORIGINS?.split(',').map((o: string) => o.trim()).filter(Boolean) ?? '*',
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'x-admin-token', 'x-rozza-token']
}));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

// Rate limiter — generous for dev, can tighten for production
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 120,
  message: { error: 'Too many requests, please slow down' }
});
app.use('/api/', limiter);

// Shared-secret gate. Unset in local dev, so nothing changes there; once the
// backend has a public hostname it stops strangers spending the YouTube quota
// and AI credits this server pays for.
const APP_TOKEN = process.env.ROZZA_APP_TOKEN;
if (APP_TOKEN) {
  app.use('/api/', (req, res, next) => {
    // Health stays open so the platform's own probe can reach it.
    if (req.path === '/' || req.path.startsWith('/health')) return next();
    if (req.headers['x-rozza-token'] !== APP_TOKEN) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    return next();
  });
}

// ─── Routes ───────────────────────────────────────────────────────────────────
app.use('/api/search', searchRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/recognition', recognitionRoutes);
app.use('/api/health', healthRoutes);
app.use('/api/catalog', catalogRoutes);
// Client-shaped search for the SwiftUI app; v1 above still serves React Native.
app.use('/api/v2', v2Routes);

// ─── Root ─────────────────────────────────────────────────────────────────────
app.get('/', (_req, res) => {
  res.json({ name: 'ROZZA Music Backend', version: '1.0.0', status: 'running' });
});

// ─── Error handler ────────────────────────────────────────────────────────────
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('[ROZZA] Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// ─── Start ───────────────────────────────────────────────────────────────────
app.listen(PORT, HOST, () => {
  const configuredAI = getAIProvider();
  const ai = configuredAI.providerName;
  const ytKey = process.env.YOUTUBE_API_KEY ? '✅' : '❌ MISSING';
  const aiKey = configuredAI.isConfigured() ? '✅' : '❌ MISSING';
  const auddKey = process.env.AUDD_API_KEY || process.env.AUDD_API_TOKEN ? '✅' : '❌ MISSING';

  console.log(`
╔══════════════════════════════════════════════╗
║           ROZZA Backend  v1.0.0              ║
╠══════════════════════════════════════════════╣
║  Port     : ${PORT}                              ║
║  Host     : ${HOST}                         ║
║  Node ENV : ${process.env.NODE_ENV ?? 'development'}                   ║
║  AI Prov  : ${ai}                           ║
╠══════════════════════════════════════════════╣
║  YouTube  : ${ytKey}                         ║
║  AI Key   : ${aiKey}                         ║
║  AudD     : ${auddKey}                         ║
╚══════════════════════════════════════════════╝
  `);
});

export default app;
