import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { loopbackOrigin, percentile, routeFor, steeringFor } from './probe.mjs';

test('percentiles are numeric, sorted, and explicitly absent for no samples', () => {
  assert.equal(percentile([], 0.99), null);
  assert.equal(percentile([9, 1, 5], 0.5), 5);
  assert.equal(percentile([9, 1, 5], 0.99), 9);
});

test('load probe rejects public targets and unexpected origins', () => {
  assert.equal(loopbackOrigin('http://127.0.0.1:8787'), 'http://127.0.0.1:8787');
  for (const origin of ['https://example.com', 'http://0.0.0.0:8787', 'http://127.0.0.1:8787/path', 'http://name:password@127.0.0.1:8787']) assert.throws(() => loopbackOrigin(origin));
});

test('scripted steering follows authored descriptor direction and remains bounded', () => {
  assert.equal(steeringFor(null, []), 0);
  const route = routeFor(JSON.parse(readFileSync(new URL('../../shared/track-manifest.json', import.meta.url), 'utf8')));
  const forward = { position: [0, 0.5, -110], basis: [[0, 0, 1], [0, 1, 0], [-1, 0, 0]] };
  const steer = steeringFor(forward, route);
  assert.ok(Number.isFinite(steer) && Math.abs(steer) < 0.2, 'start follows baked +X tangent rather than old ellipse');
  for (let index = 0; index < route.length - 1; index += 10) {
    const point = route[index], next = route[index + 1];
    const length = Math.hypot(next[0] - point[0], next[1] - point[1]);
    const state = { position: [point[0], 0, point[1]], basis: [[1, 0, 0], [0, 1, 0], [-(next[0] - point[0]) / length, 0, -(next[1] - point[1]) / length]] };
    assert.ok(Math.abs(steeringFor(state, route)) <= 1);
  }
});

test('load probe rejects missing, open, malformed and degenerate routes', () => {
  for (const polyline of [undefined, [], [[0, 0], [1, 0], [1, 1], [2, 2]], [[0, 0], [1, 0], [NaN, 1], [0, 0]], [[0, 0], [1, 0], [1, 0], [0, 0]]]) {
    assert.throws(() => routeFor({ minimap: { polyline } }), /track descriptor|zero-length/);
  }
  assert.throws(() => steeringFor({ position: [0, 0, 0] }), /no route/);
});
