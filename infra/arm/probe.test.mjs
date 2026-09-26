import assert from 'node:assert/strict';
import test from 'node:test';
import { loopbackOrigin, percentile, steeringFor } from './probe.mjs';

test('percentiles are numeric, sorted, and explicitly absent for no samples', () => {
  assert.equal(percentile([], 0.99), null);
  assert.equal(percentile([9, 1, 5], 0.5), 5);
  assert.equal(percentile([9, 1, 5], 0.99), 9);
});

test('load probe rejects public targets and unexpected origins', () => {
  assert.equal(loopbackOrigin('http://127.0.0.1:8787'), 'http://127.0.0.1:8787');
  for (const origin of ['https://example.com', 'http://0.0.0.0:8787', 'http://127.0.0.1:8787/path', 'http://name:password@127.0.0.1:8787']) assert.throws(() => loopbackOrigin(origin));
});

test('scripted steering remains bounded and turns into the oval', () => {
  assert.equal(steeringFor(null), 0);
  const steer = steeringFor({ position: [62, 0.5, 0], basis: [[-1, 0, 0], [0, 1, 0], [0, 0, -1]] });
  assert.ok(steer > 0 && steer <= 1);
});
