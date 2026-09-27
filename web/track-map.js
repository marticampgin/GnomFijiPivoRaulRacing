(function (root) {
  'use strict';
  const finite = value => typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= 1e6;
  const point = value => Array.isArray(value) && value.length === 2 && value.every(finite);

  function project(descriptor, width = 240, height = 150, padding = 14) {
    const map = descriptor?.minimap;
    if (!descriptor || typeof descriptor.track_id !== 'string' || !/^[a-f0-9]{64}$/.test(descriptor.simulation_hash || '') || descriptor.schema_version !== 1) return null;
    if (!map || !Array.isArray(map.polyline) || map.polyline.length < 4 || map.polyline.length > 4096 || !map.polyline.every(point) || !point(map.start)) return null;
    const bounds = map.bounds;
    if (!bounds || !['min_x', 'min_z', 'max_x', 'max_z'].every(key => finite(bounds[key]))) return null;
    const dx = bounds.max_x - bounds.min_x, dz = bounds.max_z - bounds.min_z;
    if (dx <= 0 || dz <= 0 || !finite(width) || !finite(height) || !finite(padding) || padding < 0 || width <= padding * 2 || height <= padding * 2) return null;
    if (!map.polyline.every(([x, z]) => x >= bounds.min_x - .01 && x <= bounds.max_x + .01 && z >= bounds.min_z - .01 && z <= bounds.max_z + .01)) return null;
    const scale = Math.min((width - 2 * padding) / dx, (height - 2 * padding) / dz);
    const originX = (width - dx * scale) / 2, originZ = (height - dz * scale) / 2;
    const worldToMap = (x, z) => finite(x) && finite(z) ? [originX + (x - bounds.min_x) * scale, originZ + (z - bounds.min_z) * scale] : null;
    return { points: map.polyline.map(([x, z]) => worldToMap(x, z)), start: worldToMap(...map.start), worldToMap, hash: descriptor.simulation_hash };
  }

  const api = Object.freeze({ project });
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.GnomTrackMap = api;
})(globalThis);
