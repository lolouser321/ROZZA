# ─────────────────────────────────────────────────────────────────────────────
# ROZZA backend — deployable image.
#
# Replaces "the PC at 192.168.4.24 must stay on, on the same Wi-Fi": once this
# runs on a host with a public HTTPS name, the iPhone reaches ROZZA anywhere.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:22-bookworm-slim AS build

WORKDIR /app

# better-sqlite3 compiles a native addon, so the toolchain is needed at build
# time only — the runtime stage below drops it again.
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev


FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production \
    PORT=3001 \
    HOST=0.0.0.0 \
    ROZZA_DATA_DIR=/data

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json

# Catalog and search cache live on a mounted volume so a redeploy does not
# throw away everything ROZZA has discovered.
RUN mkdir -p /data && chown -R node:node /data /app
USER node

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3001)+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/index.js"]
