import { readFileSync } from 'node:fs';

export const WIRE_VERSION = 5;
export const TICKET_VERSION = 3;
export const VEHICLE_STATE_VERSION = 1;
export const TRACK_SCHEMA_VERSION = 1;
export const LOADOUT_HASH = 'prototype-v7';
export const STYLE_IDS = ['handling', 'acceleration', 'speed', 'drift'] as const;
export type StyleId = typeof STYLE_IDS[number];

export interface TrackIdentity {
  track_id: string;
  schema_version: number;
  simulation_revision: number;
  simulation_hash: string;
  art_revision: number;
}

export interface TrackManifest extends TrackIdentity {
  length: number;
  minimap: {
    polyline: [number, number][];
    bounds: { min_x: number; max_x: number; min_z: number; max_z: number };
    world_to_map: { scale_x: number; scale_z: number; offset_x: number; offset_z: number };
    start: [number, number];
  };
}

const record = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
const finite = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
const revision = (value: unknown): value is number => finite(value) && Number.isInteger(value) && value >= 1 && value <= 2147483647;
const point = (value: unknown): value is [number, number] => Array.isArray(value) && value.length === 2 && value.every(finite);

export function validateTrackManifest(value: unknown): TrackManifest {
  const invalid = () => { throw new Error('Invalid race track manifest'); };
  if (!record(value)) return invalid();
  if (typeof value.track_id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(value.track_id)
    || value.schema_version !== TRACK_SCHEMA_VERSION || !revision(value.simulation_revision) || !revision(value.art_revision)
    || typeof value.simulation_hash !== 'string' || !/^[a-f0-9]{64}$/.test(value.simulation_hash)
    || !finite(value.length) || value.length <= 0) return invalid();
  const map = value.minimap;
  if (!record(map) || !record(map.bounds) || !record(map.world_to_map) || !point(map.start)
    || !Array.isArray(map.polyline) || map.polyline.length < 4 || map.polyline.length > 4096 || !map.polyline.every(point)) return invalid();
  const bounds = map.bounds;
  if (!finite(bounds.min_x) || !finite(bounds.max_x) || !finite(bounds.min_z) || !finite(bounds.max_z)
    || bounds.min_x >= bounds.max_x || bounds.min_z >= bounds.max_z) return invalid();
  for (const key of ['scale_x', 'scale_z', 'offset_x', 'offset_z']) if (!finite(map.world_to_map[key])) return invalid();
  if ((map.world_to_map.scale_x as number) <= 0 || (map.world_to_map.scale_z as number) <= 0) return invalid();
  for (const [x, z] of [map.start, ...map.polyline]) {
    if (x < bounds.min_x - 0.001 || x > bounds.max_x + 0.001 || z < bounds.min_z - 0.001 || z > bounds.max_z + 0.001) return invalid();
  }
  return value as unknown as TrackManifest;
}

export function loadTrackManifest(path: string): TrackManifest {
  const source = readFileSync(path);
  if (source.byteLength > 1024 * 1024) throw new Error('Race track manifest exceeds size limit');
  return validateTrackManifest(JSON.parse(source.toString('utf8')));
}

export function trackIdentity(manifest: TrackManifest): TrackIdentity {
  const { track_id, schema_version, simulation_revision, simulation_hash, art_revision } = manifest;
  return { track_id, schema_version, simulation_revision, simulation_hash, art_revision };
}

export function raceCompatibility(manifest: TrackManifest) {
  return { protocol_version: WIRE_VERSION, vehicle_state_version: VEHICLE_STATE_VERSION, loadout_hash: LOADOUT_HASH, track: trackIdentity(manifest) };
}
