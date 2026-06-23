import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { WebSocket } from 'ws';

import type { ServerMessage, VehicleState } from './types.js';

/**
 * Functional tests: boot the real backend as a child process in simulator mode
 * and exercise it the way the iPhone app does, over HTTP (/health) and the
 * /stream WebSocket. No mocks, no Tesla account.
 */

const here = dirname(fileURLToPath(import.meta.url));
const entry = resolve(here, 'index.ts');

function randomPort(): number {
  return 8100 + Math.floor(Math.random() * 800);
}

interface RunningServer {
  port: number;
  proc: ChildProcess;
  stop: () => Promise<void>;
}

async function startServer(env: Record<string, string>): Promise<RunningServer> {
  const port = randomPort();
  const proc = spawn(process.execPath, ['--import', 'tsx', entry], {
    env: { ...process.env, SOURCE: 'simulator', PORT: String(port), ...env },
    stdio: 'ignore',
  });

  const deadline = Date.now() + 20_000;
  for (;;) {
    if (Date.now() > deadline) {
      proc.kill('SIGKILL');
      throw new Error('server did not become healthy in time');
    }
    try {
      const res = await fetch(`http://localhost:${port}/health`);
      if (res.ok) break;
    } catch {
      // not up yet
    }
    await new Promise((r) => setTimeout(r, 200));
  }

  return {
    port,
    proc,
    stop: () =>
      new Promise<void>((resolveStop) => {
        proc.once('exit', () => resolveStop());
        proc.kill('SIGTERM');
        setTimeout(() => {
          proc.kill('SIGKILL');
          resolveStop();
        }, 3_000).unref();
      }),
  };
}

function firstStateFrom(url: string, headers?: Record<string, string>): Promise<VehicleState> {
  return new Promise((resolveState, reject) => {
    const ws = new WebSocket(url, { headers });
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error('no vehicle_state received in time'));
    }, 8_000);

    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString()) as ServerMessage;
      if (msg.type === 'vehicle_state') {
        clearTimeout(timer);
        ws.close();
        resolveState(msg);
      }
    });
    ws.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

// ── Open stream (local-dev default: no token) ────────────────────────────────

let open: RunningServer;

before(async () => {
  open = await startServer({ PRIMARY_UNIT: 'kph' });
});

after(async () => {
  await open?.stop();
});

test('GET /health reports ok and the active source', async () => {
  const res = await fetch(`http://localhost:${open.port}/health`);
  const body = (await res.json()) as { ok: boolean; source: string };
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.source, 'simulator');
});

test('the stream emits a well-formed vehicle_state in metric units', async () => {
  const state = await firstStateFrom(`ws://localhost:${open.port}/stream`);

  assert.equal(state.type, 'vehicle_state');
  assert.equal(state.source, 'simulator');
  assert.equal(state.online, true);
  assert.equal(state.primaryUnit, 'kph');
  assert.equal(typeof state.speedKph, 'number');
  assert.equal(typeof state.lat, 'number');
  assert.equal(typeof state.lng, 'number');
  assert.ok(state.heading !== null && state.heading >= 0 && state.heading < 360);
});

// ── Token-guarded stream ─────────────────────────────────────────────────────

test('a token-guarded stream rejects missing/wrong tokens and accepts the right one', async () => {
  const secret = 'test-secret-token';
  const guarded = await startServer({ STREAM_TOKEN: secret });
  try {
    await assert.rejects(
      firstStateFrom(`ws://localhost:${guarded.port}/stream`),
      'connection without a token should be rejected',
    );

    await assert.rejects(
      firstStateFrom(`ws://localhost:${guarded.port}/stream?token=wrong`),
      'connection with the wrong token should be rejected',
    );

    const state = await firstStateFrom(
      `ws://localhost:${guarded.port}/stream?token=${secret}`,
    );
    assert.equal(state.type, 'vehicle_state');
  } finally {
    await guarded.stop();
  }
});
