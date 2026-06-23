import { test, mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import { SimulatorSource } from './SimulatorSource.js';
import { kphFromMph } from '../types.js';
import type { ServerMessage, VehicleState } from '../types.js';

afterEach(() => {
  mock.reset();
  mock.timers.reset();
});

function collectFirstState(unit: 'mph' | 'kph'): VehicleState {
  // Each call is self-contained: clear any prior mocks/timers first so the
  // helper can run several times within one test.
  mock.timers.reset();
  mock.restoreAll();
  // Deterministic: 0.5 keeps the random "new target speed" branch (< 0.02) off.
  mock.method(Math, 'random', () => 0.5);
  mock.timers.enable({ apis: ['setInterval'] });

  const source = new SimulatorSource(unit, 250);
  const messages: ServerMessage[] = [];
  source.start((m) => messages.push(m));

  mock.timers.tick(250);
  source.stop();

  assert.ok(messages.length >= 1, 'expected at least one emitted message');
  const state = messages[0];
  assert.equal(state.type, 'vehicle_state');
  return state as VehicleState;
}

test('emits a well-formed vehicle_state on each tick', () => {
  const state = collectFirstState('kph');

  assert.equal(state.source, 'simulator');
  assert.equal(state.online, true);
  assert.equal(typeof state.ts, 'number');
  assert.equal(typeof state.lat, 'number');
  assert.equal(typeof state.lng, 'number');
  assert.ok(state.heading !== null && state.heading >= 0 && state.heading < 360);
});

test('passes through the configured primary unit', () => {
  assert.equal(collectFirstState('mph').primaryUnit, 'mph');
  assert.equal(collectFirstState('kph').primaryUnit, 'kph');
});

test('derives speedKph from speedMph', () => {
  const state = collectFirstState('kph');
  assert.ok(state.speedMph !== null && state.speedKph !== null);
  const expected = Math.round(kphFromMph(state.speedMph) * 10) / 10;
  assert.ok(Math.abs((state.speedKph as number) - expected) < 0.2);
});

test('starts roughly stationary and within the Stockholm route bounds', () => {
  const state = collectFirstState('kph');
  assert.ok((state.speedMph as number) >= 0 && (state.speedMph as number) < 5);
  assert.ok((state.lat as number) > 59.32 && (state.lat as number) < 59.34);
  assert.ok((state.lng as number) > 18.02 && (state.lng as number) < 18.05);
});

test('stop halts further emissions', () => {
  mock.method(Math, 'random', () => 0.5);
  mock.timers.enable({ apis: ['setInterval'] });

  const source = new SimulatorSource('kph', 250);
  const messages: ServerMessage[] = [];
  source.start((m) => messages.push(m));

  mock.timers.tick(250);
  const afterFirst = messages.length;
  source.stop();
  mock.timers.tick(1000);

  assert.equal(messages.length, afterFirst);
});
