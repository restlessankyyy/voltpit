import { test } from 'node:test';
import assert from 'node:assert/strict';

import { kphFromMph, mphFromKph } from './types.js';

test('kphFromMph converts known values', () => {
  assert.equal(Math.round(kphFromMph(60)), 97);
  assert.equal(kphFromMph(0), 0);
});

test('mphFromKph converts known values', () => {
  assert.equal(Math.round(mphFromKph(100)), 62);
  assert.equal(mphFromKph(0), 0);
});

test('mph and kph conversions round-trip', () => {
  for (const mph of [0, 15, 37.5, 80]) {
    assert.ok(Math.abs(mphFromKph(kphFromMph(mph)) - mph) < 1e-9);
  }
});

test('kph is always greater than the equivalent mph for positive speeds', () => {
  for (const mph of [1, 25, 70]) {
    assert.ok(kphFromMph(mph) > mph);
  }
});
