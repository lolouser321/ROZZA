# ROZZA backend

The backend owns all provider credentials and exposes catalog, search, AI, recognition, and health APIs to the iPhone app. The mobile bundle contains no provider keys.

## Setup

1. Copy `.env.example` to `.env`.
2. Add rotated provider credentials.
3. Run `npm install` and `npm run dev`.
4. Set the mobile build variable `EXPO_PUBLIC_API_URL` to the HTTPS URL of this server.

The active AI provider defaults to OpenAI. Provider selection is isolated behind `IAIProvider`; change `ACTIVE_AI_PROVIDER` to switch implementations without changing routes or mobile code.

## Endpoints

- `POST /api/search/autocomplete` — catalog/cache only; never calls YouTube.
- `POST /api/search/full` — catalog first, then Audius/Jamendo native audio, with YouTube as a foreground-only fallback.
- `POST /api/catalog/direct` — admin-only registration of authorized HTTPS MP3/AAC sources from `AUTHORIZED_AUDIO_HOSTS`.
- `GET /api/search/trending?region=EG` — persisted catalog charts with provider refresh.
- `POST /api/ai/chat` — structured music intent followed by real catalog/provider resolution.
- `POST /api/recognition/identify` — multipart audio recognition through AudD.
- `GET /api/health` — public minimal status.
- `GET /api/health/providers` — development/admin diagnostics; requires `x-admin-token` when `ADMIN_SEED_TOKEN` is configured and is hidden in production when it is not.

## Security

- Never commit `.env`.
- Never use `EXPO_PUBLIC_` for provider credentials.
- Rotate any credential exposed in chat, screenshots, logs, or source history.
- In production, configure `ADMIN_SEED_TOKEN`, an HTTPS backend URL, and a restricted CORS policy appropriate to the deployment.

## YouTube playback

The Data API supplies metadata only. The iPhone app uses YouTube's visible embedded player for foreground playback. It does not extract audio, proxy streams, download videos, remove ads, or enable unauthorized background playback.

## Native audio sources

Audius streams, Jamendo streams, authorized direct audio, and files imported by the user are played by the native iOS audio session. They support background playback and system media controls. Audius public access works without an app credential; Jamendo requires `JAMENDO_CLIENT_ID`. Imported files stay on the device and never pass through this backend.
