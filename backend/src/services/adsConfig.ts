/**
 * Remote ads configuration served to the ROZZA app.
 *
 * The app fetches this on launch (never blocking launch), validates it again
 * itself (lib/src/ads/ads_config.dart) and caches the last good copy. This
 * file is the SERVER side of the same contract: it can only ever emit a valid,
 * bounded payload, and defaults to ads OFF.
 *
 * Turn ads on/off WITHOUT an app update by changing the ROZZA_ADS_CONFIG_JSON
 * environment variable (e.g. `fly secrets set ROZZA_ADS_CONFIG_JSON='{"adsEnabled":true}'`).
 */
export const SCHEMA_VERSION = 1;

export interface AdsConfigPayload {
  schemaVersion: number;
  adsEnabled: boolean;
  bannerEnabled: boolean;
  interstitialEnabled: boolean;
  rewardedEnabled: boolean;
  appOpenEnabled: boolean;
  interstitialEveryNActions: number;
  interstitialMinimumSeconds: number;
}

export const SAFE_DEFAULTS: AdsConfigPayload = {
  schemaVersion: SCHEMA_VERSION,
  adsEnabled: false,
  bannerEnabled: true,
  interstitialEnabled: true,
  rewardedEnabled: false,
  appOpenEnabled: false,
  interstitialEveryNActions: 4,
  interstitialMinimumSeconds: 180,
};

const BOOLS = ['adsEnabled', 'bannerEnabled', 'interstitialEnabled', 'rewardedEnabled', 'appOpenEnabled'] as const;

function clampInt(v: unknown, min: number, max: number): number | null {
  if (typeof v !== 'number' || !Number.isFinite(v) || !Number.isInteger(v)) return null;
  return Math.min(max, Math.max(min, v));
}

/** Returns a valid payload, or null if `raw` is malformed. Never throws. */
export function parseAdsConfig(raw: string | undefined): AdsConfigPayload | null {
  if (!raw || !raw.trim()) return null;
  let obj: unknown;
  try {
    obj = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof obj !== 'object' || obj === null || Array.isArray(obj)) return null;
  const o = obj as Record<string, unknown>;
  const out: AdsConfigPayload = { ...SAFE_DEFAULTS };
  if ('schemaVersion' in o && o.schemaVersion !== SCHEMA_VERSION) return null;
  for (const k of BOOLS) {
    if (k in o) {
      if (typeof o[k] !== 'boolean') return null;
      out[k] = o[k] as boolean;
    }
  }
  if ('interstitialEveryNActions' in o) {
    const n = clampInt(o.interstitialEveryNActions, 2, 50);
    if (n === null) return null;
    out.interstitialEveryNActions = n;
  }
  if ('interstitialMinimumSeconds' in o) {
    const n = clampInt(o.interstitialMinimumSeconds, 60, 3600);
    if (n === null) return null;
    out.interstitialMinimumSeconds = n;
  }
  return out;
}

/** What GET /api/app-config/ads returns: the configured payload, or safe defaults (ads OFF). */
export function currentAdsConfig(env: NodeJS.ProcessEnv = process.env): AdsConfigPayload {
  return parseAdsConfig(env.ROZZA_ADS_CONFIG_JSON) ?? { ...SAFE_DEFAULTS };
}
