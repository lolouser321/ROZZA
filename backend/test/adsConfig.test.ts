import test from 'node:test';
import assert from 'node:assert/strict';
import { parseAdsConfig, currentAdsConfig, SAFE_DEFAULTS } from '../src/services/adsConfig';

test('unset env serves safe defaults with ads OFF', () => {
  const c = currentAdsConfig({} as NodeJS.ProcessEnv);
  assert.equal(c.adsEnabled, false);
  assert.deepEqual(c, SAFE_DEFAULTS);
});

test('invalid env JSON falls back to ads OFF, never throws', () => {
  for (const bad of ['{', '[]', '"x"', '{"adsEnabled":"yes"}', '{"schemaVersion":2}', '{"interstitialEveryNActions":2.5}']) {
    const c = currentAdsConfig({ ROZZA_ADS_CONFIG_JSON: bad } as unknown as NodeJS.ProcessEnv);
    assert.equal(c.adsEnabled, false, bad);
  }
});

test('a valid payload can turn ads on and is clamped', () => {
  const c = parseAdsConfig('{"adsEnabled":true,"interstitialEveryNActions":1,"interstitialMinimumSeconds":99999}');
  assert.ok(c);
  assert.equal(c!.adsEnabled, true);
  assert.equal(c!.interstitialEveryNActions, 2);
  assert.equal(c!.interstitialMinimumSeconds, 3600);
  assert.equal(c!.rewardedEnabled, false);
});
