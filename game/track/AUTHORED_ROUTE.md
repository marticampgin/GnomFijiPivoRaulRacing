# Authored Route Draft

This is a reviewable greybox, not finished presentation art. The legacy
`prototype_track.gd` remains available as an independent regression fixture.

## Source and Bake

`castle_waterfalls.tres` is the editable `TrackDefinition` with a closed
`Curve3D`. `tools/bake_track.gd` generates:

- `track/baked/castle_waterfalls.json`: shared numerical simulation package.
- `../shared/track-manifest.json`: backend/browser identity and minimap.
- `track/baked/route-overview.svg`: route review plan, generated from samples.

Run from the repository root:

```sh
"$GODOT_BIN" --headless --path game --script res://tools/bake_track.gd
"$GODOT_BIN" --headless --path game --script res://tests/authored_track_probe.gd
"$GODOT_BIN" --headless --path game --fixed-fps 60 --script res://tests/authored_drive_probe.gd
"$GODOT_BIN" --headless --path game --fixed-fps 60 --script res://tests/slope_contact_probe.gd
```

The bake sorts dictionary keys and canonicalizes simulation numbers at
one-micrometre precision before SHA256. This avoids depending on JSON parser
rounding of insignificant binary floating-point digits. Simulation data includes
collision winding/backface policy, route, gates, starts/recovery, surfaces,
corridor tolerances and kill volumes. Art revision, minimap, guide and camera
metadata are excluded. Generated JSON files are replaced atomically.

The draft loop is 798.46 m long with a 14 m road, 16 directed gates and ten
two-column start positions. It rises from approximately 0 to 16 m and contains
opposite turns. Four camera anchors denote the proposed start, forest, water
reveal and bridge/castle sections. Their labels are working descriptions, not
new story names. Full scenery must follow approval of this plan.

## Runtime Contract

`AuthoredTrack.build(false)` creates only simulation colliders. It does not
preload meshes, textures, materials or scenery scripts. `build(true)` dynamically
loads the separately owned greybox renderer with the same collision bake.
`load_errors` reports malformed/incompatible packages; an invalid package
does not build colliders and has an empty identity/descriptor.

- `identity()` returns track/schema/simulation revision/hash and art revision.
- `descriptor()` adds route length and minimap polyline/bounds/world-to-map.
- `spawn_transform(slot)` returns one of ten supported, world-up yaw poses.
- `initial_progress()` creates the authoritative per-racer progress dictionary.
- `advance_progress(state, before, after, discontinuity)` mutates that dictionary
  and returns checkpoint/lap/finish events. It does not mutate vehicle physics.
- `standings_distance(state, location)` projects only into the confirmed interval.
- `recovery_transform(state)` selects the last confirmed safe anchor.
- `mark_recovered(state)` clears the violated interval and marks discontinuity.
- `needs_recovery(location)` tests spatial bounds, volumes and road-relative fall.

Progress fields: `started`, `confirmed_gate` (-1 before the start),
`expected_gate`, `lap` (completed laps), `finished`, `interval_valid`, and
`discontinuity`. The initial start-line crossing arms a lap; it does not finish
one. Gate 15 followed by gate 0 increments completed laps. The third completed
lap emits exactly one finish. Re-crossing another gate cannot advance order.

Every swept movement is clipped against the exact union of local corridor
prisms. Any uncovered portion poisons the interval until recovery; re-entering
the road does not erase a shortcut. This is not a movement-rate/cheat detector:
the authoritative vehicle simulation still owns valid input and motion.

The caller must reset speed/drift/boost, input epoch and command queues when
performing recovery. The route helper preserves completed laps and expected
checkpoint and suppresses the discontinuous movement's gate crossings.

## Verified Scope

On the pinned Godot 4.7.2 local runtime, 27 September 2026:

- Authored route probe: 88 assertions, zero failures. Includes deterministic
  hash, visual-only stability, malformed resources, 0.5/1/3 m sample spacing,
  three ordered laps, multiple swept gates, wrong-way/height/shortcut/recovery,
  all ten grounded starts, minimap/guide and client/server collision parity.
- Drive fixture: one actual controller lap, 37.7 simulated seconds, zero
  recoveries. Configured top speed is 26 m/s. This is deterministic steering QA,
  not implemented gameplay AI, Web performance, or a default-speed player test.
- Vehicle regression: 33 assertions, zero failures, including airborne drift,
  local gravity, boost lifecycle and powered escape from a head-on wall.

Driving exposed the engine's idle `floor_stop_on_slope` correction pinning a
powered box collider to road triangle seams. Vehicle balance v2 limits this
correction to nearly stationary, unpowered input; the vehicle-state schema stays
at version 1. No unsynchronized floor-normal state is introduced.

Visual acceptance, normal desktop steering at all speeds, Web two-player
route migration, camera collision and performance budgets remain separate gates.
