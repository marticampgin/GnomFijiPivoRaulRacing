const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { project } = require('../web/track-map.js');
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../shared/track-manifest.json')));

test('all authored route points fit the minimap with a uniform spatial scale', () => {
  const result = project(manifest);
  assert.ok(result);
  assert.equal(result.points.length, manifest.minimap.polyline.length);
  for (const [x, y] of result.points) assert.ok(x >= 13.99 && x <= 226.01 && y >= 13.99 && y <= 136.01);
  assert.deepEqual(result.start, result.worldToMap(...manifest.minimap.start));
  const a = result.worldToMap(0, 0), b = result.worldToMap(1, 1);
  assert.ok(Math.abs((b[0] - a[0]) - (b[1] - a[1])) < 1e-9);
  for (const index of [0, Math.floor(result.points.length / 4), Math.floor(result.points.length / 2), Math.floor(result.points.length * 3 / 4)]) {
    assert.deepEqual(result.points[index], result.worldToMap(...manifest.minimap.polyline[index]));
  }
});

test('descriptor, coordinates and viewport are validated without oval fallback', () => {
  for (const value of [null, {}, { ...manifest, schema_version: 99 }, { ...manifest, simulation_hash: 'bad' }]) assert.equal(project(value), null);
  for (const polyline of [[[0, 0]], [[0, 0], [1, 1], [2, 2], [NaN, 1]], Array(4097).fill([0, 0])]) assert.equal(project({ ...manifest, minimap: { ...manifest.minimap, polyline } }), null);
  assert.equal(project({ ...manifest, minimap: { ...manifest.minimap, bounds: { min_x: 0, max_x: 0, min_z: 0, max_z: 1 } } }), null);
  assert.equal(project(manifest, 20, 20, 14), null);
  assert.equal(project(manifest).worldToMap(Infinity, 0), null);
});

test('shortcut routes use the main map projection and remain optional', () => {
  const without = structuredClone(manifest); delete without.minimap.shortcuts;
  assert.deepEqual(project(without).shortcuts, []);
  const shortcuts = [[manifest.minimap.polyline[0], manifest.minimap.polyline[2], manifest.minimap.polyline[4]]];
  const descriptor = { ...manifest, minimap: { ...manifest.minimap, shortcuts } };
  const result = project(descriptor);
  assert.deepEqual(result.shortcuts, shortcuts.map(route => route.map(point => result.worldToMap(...point))));
  assert.deepEqual(result.points, project(without).points);
  assert.deepEqual(result.start, project(without).start);
});

test('shortcut routes reject malformed, unbounded and excessive geometry', () => {
  const p = manifest.minimap.polyline[0];
  const outside = [manifest.minimap.bounds.max_x + 1, p[1]];
  for (const shortcuts of [null, {}, [null], [[]], [[p]], [[p, [NaN, 0]]], [[p, [Infinity, 0]]], [[p, [0, '0']]], [[p, [0, 0, 0]]], [[p, outside]], Array(9).fill([p, p]), [Array(4097).fill(p)], [Array(3000).fill(p), Array(2000).fill(p)]]) {
    assert.equal(project({ ...manifest, minimap: { ...manifest.minimap, shortcuts } }), null);
  }
});
