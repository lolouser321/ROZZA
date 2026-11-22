# Deploying the ROZZA backend

Today the backend runs on the development PC at `http://192.168.4.24:3001`. That
means the computer has to stay on, the process has to stay up, the iPhone has to
be on the same Wi-Fi, and a DHCP lease change silently breaks the IPA. Putting it
on a public HTTPS host removes all four failure modes at once.

## 1. Fill in the keys

```bash
cp .env.example .env
```

The one that is currently missing and costs nothing:

- **`JAMENDO_CLIENT_ID`** — register an app at <https://devportal.jamendo.com/>
  and copy the *Client ID*. The Jamendo integration is already written; without
  this value every Jamendo search returns an empty list, which is why the
  catalog looks thinner than it should. Jamendo is independent and
  Creative-Commons licensed music, so it will not carry major commercial
  releases — it widens the background-capable pool, it does not replace
  Apple Music for exact recordings.

Also set, before going public:

- **`ROZZA_APP_TOKEN`** — any long random string. Once set, the API rejects
  requests without a matching `x-rozza-token` header. Put the same value in the
  app's `EXPO_PUBLIC_ROZZA_APP_TOKEN`. Without it, a public URL means strangers
  spending your YouTube quota and AI credits.
- **`ROZZA_DATA_DIR=/data`** — so the SQLite catalog lands on the mounted volume
  rather than inside the container filesystem.

## 2. Deploy

### Fly.io (recommended — persistent volume, cheap always-on machine)

```bash
fly launch --no-deploy --copy-config --name rozza-backend
```

```bash
fly volumes create rozza_data --size 1 --region cdg
```

```bash
fly secrets set YOUTUBE_API_KEY=... OPENAI_API_KEY=... AUDD_API_KEY=... JAMENDO_CLIENT_ID=... ROZZA_APP_TOKEN=... SPOTIFY_CLIENT_ID=... SPOTIFY_CLIENT_SECRET=...
```

```bash
fly deploy
```

`fly.toml` already pins `min_machines_running = 1`, because a cold start on the
first search reads to a listener as the app being broken.

### Render / Railway / any Docker host

Point the service at `backend/Dockerfile`. Attach a persistent disk mounted at
`/data` and set `ROZZA_DATA_DIR=/data`. Health check path is `/api/health`.

Without a persistent disk everything still works, but the discovered-track
catalog and search cache are rebuilt from scratch on each redeploy — which
means more YouTube API calls and a slower first search.

## 3. Point the app at it

In the project root `.env`:

```
EXPO_PUBLIC_API_URL=https://rozza-backend.fly.dev
EXPO_PUBLIC_ROZZA_APP_TOKEN=<same value as ROZZA_APP_TOKEN>
```

Then rebuild the IPA. `EXPO_PUBLIC_*` values are inlined at build time, so
changing them requires a new build, not just a restart.

## 4. Verify

```bash
curl https://rozza-backend.fly.dev/api/health
```

Provider-by-provider status, including whether Jamendo is now configured:

```bash
curl -H "x-admin-token: $ADMIN_SEED_TOKEN" https://rozza-backend.fly.dev/api/health/providers
```

## Afterwards: drop the arbitrary-loads exception

`app.json` sets `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` so the
app can reach a plain-HTTP LAN address during development. Once the backend is
HTTPS-only, remove that key. App Review asks for a justification for it, and
there is no longer a reason to carry one.
