import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { readConfig } from '../src/config.js';
import { loadTrackManifest, raceCompatibility, trackIdentity, validateTrackManifest, WIRE_VERSION, VEHICLE_STATE_VERSION, TRACK_SCHEMA_VERSION } from '../src/race-compatibility.js';

const manifestPath = fileURLToPath(new URL('../../shared/track-manifest.json', import.meta.url));
const manifest = loadTrackManifest(manifestPath);

test('backend manifest and Godot bake share authoritative simulation identity', () => {
  const baked = JSON.parse(readFileSync(new URL('../../game/track/baked/castle_waterfalls.json', import.meta.url), 'utf8'));
  assert.deepEqual(trackIdentity(manifest), trackIdentity(baked));
  assert.equal(manifest.length, baked.length);
  assert.deepEqual(manifest.minimap, baked.minimap);
  assert.equal(raceCompatibility(manifest).protocol_version, WIRE_VERSION);
  assert.equal(raceCompatibility(manifest).vehicle_state_version, VEHICLE_STATE_VERSION);
  assert.notEqual(WIRE_VERSION as number, VEHICLE_STATE_VERSION as number);
  assert.equal(raceCompatibility(manifest).track.schema_version, TRACK_SCHEMA_VERSION);
  const protocolSource = readFileSync(new URL('../../game/net/prototype_protocol.gd', import.meta.url), 'utf8');
  const vehicleSource = readFileSync(new URL('../../game/vehicle/racing_vehicle.gd', import.meta.url), 'utf8');
  const loadout = raceCompatibility(manifest).loadout_hash;
  assert.ok(protocolSource.includes(`const LOADOUT_HASH: String = "${loadout}"`));
  assert.ok(vehicleSource.includes(`const BALANCE_VERSION: String = "vehicle-${loadout}"`));
});

test('manifest validation rejects malformed identity and runtime map', () => {
  for (const changes of [
    { track_id: '' }, { track_id: '../other' }, { schema_version: 999 }, { simulation_revision: 0 },
    { simulation_revision: 1.5 }, { art_revision: null }, { simulation_hash: '0'.repeat(63) },
    { simulation_hash: 'G'.repeat(64) }, { length: 0 }, { length: Infinity },
    { minimap: null }, { minimap: { ...manifest.minimap, polyline: [] } },
    { minimap: { ...manifest.minimap, polyline: [[NaN, 0], ...manifest.minimap.polyline] } },
    { minimap: { ...manifest.minimap, start: [1e9, 1e9] } },
    { minimap: { ...manifest.minimap, world_to_map: { ...manifest.minimap.world_to_map, scale_x: 0 } } },
  ]) assert.throws(() => validateTrackManifest({ ...manifest, ...changes }), /Invalid race track manifest/);
});

test('art revision is present for display but independent of simulation identity', () => {
  const changed = validateTrackManifest({ ...manifest, art_revision: manifest.art_revision + 1 });
  assert.equal(raceCompatibility(changed).track.simulation_hash, manifest.simulation_hash);
  assert.equal(raceCompatibility(changed).track.art_revision, manifest.art_revision + 1);
});

test('deployment chooses an explicit server manifest path, not request data', () => {
  const base = { DEPLOYMENT_ENV: 'test', SESSION_SECRET: 'test-configuration-secret-at-least-32-chars', DATABASE_URL: 'postgres://localhost/unused' };
  assert.equal(readConfig(base).trackManifestPath, manifestPath);
  assert.equal(readConfig({ ...base, RACE_TRACK_MANIFEST_PATH: '/tmp/versioned-race/track.json' }).trackManifestPath, '/tmp/versioned-race/track.json');
});
