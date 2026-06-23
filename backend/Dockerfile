# syntax=docker/dockerfile:1

# Single-stage build: install once, compile, then prune dev deps in place.
# This runs npm ci a single time (vs twice for multi-stage), which is the
# main build-time cost on the cloud builder.
FROM node:20-alpine
WORKDIR /app
ENV PORT=8080

# Install all deps (including dev) using the lockfile when present.
COPY package*.json ./
RUN npm ci

# Compile TypeScript to dist/, then drop dev deps to shrink the image.
COPY tsconfig.json ./
COPY src ./src
RUN npm run build \
    && npm prune --omit=dev \
    && npm cache clean --force

# Tesla requires the EC public key served at the well-known path. Ship only the
# public key; the private key is excluded via .dockerignore.
COPY keys/public-key.pem ./keys/public-key.pem

ENV NODE_ENV=production
EXPOSE 8080
CMD ["node", "dist/index.js"]
