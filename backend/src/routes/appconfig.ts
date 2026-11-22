import { Router, Request, Response } from 'express';
import { currentAdsConfig } from '../services/adsConfig';

const router = Router();

// GET /api/app-config/ads — public, non-secret, tiny. Deliberately exempt from
// the ROZZA_APP_TOKEN gate (see index.ts): a 401 would only make the app keep
// ads off, which is the safe direction, but there is nothing here to protect.
router.get('/ads', (_req: Request, res: Response) => {
  res.set('Cache-Control', 'public, max-age=300');
  res.json(currentAdsConfig());
});

export default router;
