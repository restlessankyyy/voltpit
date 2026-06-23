import express from 'express';
import { createServer, type IncomingMessage } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { WebSocketServer } from 'ws';

import { config, assertTeslaConfig } from './config.js';
import { WsHub } from './wsHub.js';
import { authRoutes } from './routes/auth.js';
import { wellKnownRoutes } from './routes/wellKnown.js';
import { TeslaOAuth } from './tesla/oauth.js';
import { FleetApi } from './tesla/fleetApi.js';
import { TokenStore } from './tesla/tokenStore.js';
import { SimulatorSource } from './sources/SimulatorSource.js';
import { TeslaSource } from './sources/TeslaSource.js';
import type { VehicleSource } from './sources/VehicleSource.js';

const app = express();
const server = createServer(app);
const hub = new WsHub();

// ── HTTP routes ─────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ ok: true, source: config.source, clients: hub.clientCount });
});

app.use('/.well-known', wellKnownRoutes());

// ── WebSocket: the app connects here for the realtime stream ────────────────
// When STREAM_TOKEN is set, clients must present it as `Authorization: Bearer
// <token>` or `?token=<token>`. Empty token (local dev) leaves the stream open.
function tokensMatch(provided: string, expected: string): boolean {
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

function isAuthorized(req: IncomingMessage): boolean {
  if (!config.streamToken) return true;
  const header = req.headers.authorization;
  const fromHeader = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
  const fromQuery = new URL(req.url ?? '', 'http://localhost').searchParams.get(
    'token',
  );
  const provided = fromHeader ?? fromQuery ?? '';
  return tokensMatch(provided, config.streamToken);
}

const wss = new WebSocketServer({
  server,
  path: '/stream',
  verifyClient: ({ req }, done) => {
    if (isAuthorized(req)) return done(true);
    done(false, 401, 'Unauthorized');
  },
});
wss.on('connection', (socket) => {
  hub.add(socket);
});

// ── Build the data source ────────────────────────────────────────────────────
function buildSource(): VehicleSource {
  if (config.source === 'tesla') {
    assertTeslaConfig();
    const store = new TokenStore(config.tesla.tokenStorePath);
    const oauth = new TeslaOAuth(store);
    const api = new FleetApi(oauth);
    app.use('/auth', authRoutes(oauth));
    return new TeslaSource(api, config.primaryUnit, config.pollIntervalMs);
  }
  return new SimulatorSource(config.primaryUnit);
}

const source = buildSource();

server.listen(config.port, () => {
  console.log(`Tesla Dash backend listening on :${config.port}`);
  console.log(`  source:    ${config.source}`);
  console.log(`  stream:    ws://localhost:${config.port}/stream`);
  if (config.source === 'tesla') {
    console.log(`  authorize: http://localhost:${config.port}/auth/login`);
  }
  void source.start((msg) => hub.broadcast(msg));
});

// ── Graceful shutdown ────────────────────────────────────────────────────────
for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, () => {
    console.log(`\n${sig} received, shutting down…`);
    void source.stop();
    wss.close();
    server.close(() => process.exit(0));
  });
}
