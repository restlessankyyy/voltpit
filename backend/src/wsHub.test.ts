import { test } from 'node:test';
import assert from 'node:assert/strict';

import { WsHub } from './wsHub.js';
import type { ServerMessage, VehicleState } from './types.js';

/**
 * Minimal stand-in for a `ws` WebSocket: records everything sent and lets the
 * test fire 'close' / 'error' to exercise client cleanup.
 */
class FakeSocket {
  static readonly OPEN = 1;
  readonly OPEN = FakeSocket.OPEN;
  readyState = FakeSocket.OPEN;
  sent: string[] = [];
  private handlers = new Map<string, () => void>();

  send(payload: string): void {
    this.sent.push(payload);
  }

  on(event: string, cb: () => void): this {
    this.handlers.set(event, cb);
    return this;
  }

  fire(event: string): void {
    this.handlers.get(event)?.();
  }
}

function vehicleState(speedMph: number): VehicleState {
  return {
    type: 'vehicle_state',
    ts: 1,
    speedMph,
    speedKph: speedMph,
    primaryUnit: 'kph',
    lat: 0,
    lng: 0,
    heading: 0,
    shiftState: 'D',
    power: 0,
    batteryLevel: 80,
    source: 'simulator',
    online: true,
  };
}

test('broadcast sends the message to every open client', () => {
  const hub = new WsHub();
  const a = new FakeSocket();
  const b = new FakeSocket();
  hub.add(a as never);
  hub.add(b as never);

  hub.broadcast(vehicleState(30));

  assert.equal(a.sent.length, 1);
  assert.equal(b.sent.length, 1);
  assert.deepEqual(JSON.parse(a.sent[0]), vehicleState(30));
});

test('a new client immediately receives the last vehicle_state', () => {
  const hub = new WsHub();
  hub.broadcast(vehicleState(42));

  const late = new FakeSocket();
  hub.add(late as never);

  assert.equal(late.sent.length, 1);
  assert.deepEqual(JSON.parse(late.sent[0]), vehicleState(42));
});

test('status messages are not replayed to new clients', () => {
  const hub = new WsHub();
  const status: ServerMessage = {
    type: 'status',
    ts: 1,
    level: 'info',
    message: 'hello',
  };
  hub.broadcast(status);

  const late = new FakeSocket();
  hub.add(late as never);

  assert.equal(late.sent.length, 0);
});

test('clientCount tracks adds and removals on close', () => {
  const hub = new WsHub();
  const a = new FakeSocket();
  const b = new FakeSocket();
  hub.add(a as never);
  hub.add(b as never);
  assert.equal(hub.clientCount, 2);

  a.fire('close');
  assert.equal(hub.clientCount, 1);

  b.fire('error');
  assert.equal(hub.clientCount, 0);
});

test('broadcast skips clients that are not open', () => {
  const hub = new WsHub();
  const closed = new FakeSocket();
  closed.readyState = 3; // CLOSED
  hub.add(closed as never);

  hub.broadcast(vehicleState(10));

  assert.equal(closed.sent.length, 0);
});
