import { Router, Request, Response } from 'express';
import multer from 'multer';
import { AudDProvider } from '../providers/recognition/AudDProvider';

const router = Router();
const audd = new AudDProvider();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/recognition/identify
// Accepts multipart audio (from iPhone microphone) and returns track match
// ─────────────────────────────────────────────────────────────────────────────
router.post('/identify', upload.single('audio'), async (req: Request, res: Response) => {
  if (!audd.isConfigured()) {
    return res.status(503).json({
      error: 'Recognition provider not configured',
      hint: process.env.NODE_ENV === 'development' ? 'Set AUDD_API_KEY in backend/.env' : undefined
    });
  }

  try {
    let result;

    if (req.file) {
      // Audio buffer from iPhone microphone (m4a/wav/mp3)
      result = await audd.recognizeFromBuffer(req.file.buffer, req.file.mimetype);
    } else if (req.body.url) {
      result = await audd.recognizeFromUrl(req.body.url);
    } else {
      return res.status(400).json({ error: 'Provide either an audio file or url' });
    }

    if (!result.found) {
      return res.json({ found: false, message: 'No matching track found' });
    }

    return res.json({
      found: true,
      track: {
        title: result.title,
        artist: result.artist,
        album: result.album,
        artwork: result.appleMusic?.artworkUrl ?? null,
        releaseDate: result.releaseDate,
        youtubeLink: result.youtubeLink,
        youtubeVideoId: extractYouTubeId(result.youtubeLink),
        previewUrl: result.appleMusic?.previewUrl
      }
    });
  } catch (err: any) {
    console.error('[Recognition] Error:', err.message);
    return res.status(500).json({
      error: 'Recognition failed',
      details: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
  }
});

function extractYouTubeId(url?: string): string | undefined {
  if (!url) return undefined;
  try {
    const parsed = new URL(url);
    if (parsed.hostname === 'youtu.be') return parsed.pathname.slice(1) || undefined;
    return parsed.searchParams.get('v') ?? parsed.pathname.split('/').filter(Boolean).pop();
  } catch {
    return undefined;
  }
}

export default router;
