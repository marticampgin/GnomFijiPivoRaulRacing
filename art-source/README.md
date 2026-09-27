# Editable Art Sources

This directory stores editable source assets and export settings for
`build-presentation-faithful-racing-slice`. It is not a Godot resource directory.

Current state: approved MVP model-sheet direction plus an editable Blender
hero/kart with a shared UV/PBR atlas pass. This is not an approved final model,
skeletal rig, LOD set or browser performance acceptance. Exact measured import
results, source hashes, provenance and reproduction commands are recorded in
[the hero notes](hero/README.md) and the runtime asset manifest.

## Review Gate

The hero sheet and dimensions live in
`design/reviews/presentation-slice/hero-kart-review-01.png` and
`design/reviews/presentation-slice/model-sheet-review.md`.
The user approved the sheet for MVP on 2026-09-27. Numeric dimensions are authoring
targets, not measurements from the raster; the rendered final model still needs
separate acceptance.

## Storage Contract

- Small review rasters and text manifests are kept in Git alongside provenance.
- Editable hero source belongs under `art-source/hero/`; its build script and
  runtime manifest record the export contract. Measure binary sizes before adding.
- Runtime exports belong in `game/art/characters/` and `game/art/vehicles/`, with
  provenance, source revision, SHA-256, bounds, material and attachment manifests.
- Explicit GLB exports must import without Blender installed on a clean checkout.
- No absolute workstation path may become a runtime resource dependency.
- Blender application, caches, rendered intermediates, and downloads are not
  committed. Git LFS or an external source store requires a separate decision;
  this folder does not silently establish either.

## Production Export Contract

The small pipeline probe and the UV/PBR work in progress have been exported/imported.
The following requirements still apply to a final production asset; the material
pass does not establish finished animation clips or a ten-visible-kart budget:

- Runtime space: meters, +Y up, -Z forward, +X right. Exported transform scale is
  one. A visual adapter preserves the vehicle's existing physics-origin contract.
- Keep steering pivots, rotating wheel meshes, steering wheel, hands, driver lean,
  head/hat secondary motion, crystal and paired exhaust attachment points named.
- Separate runtime geometry from authoring helpers. Supply UVs and material slots
  for enamel, brass, dark metal, rubber, leather, cloth, hair, and crystal.
- Export the explicit chosen collection to GLB. Validate bounds, transforms,
  animation tracks, textures and import errors with pinned Godot before any
  gameplay integration.
- No automatic physics/collider replacement follows from the proposed asset
  dimensions. Changed collision geometry must update simulation compatibility.

## Preflight

See `design/reviews/presentation-slice/preflight.md`. Local Blender setup was
authorized during the implementation turn. Blender 4.5.13 LTS was then installed
locally and its headless version check passed. Installation verification is
separate from concept approval. The basic pipeline probe passed 43 checks and
the original untextured blockout import passed 262; subsequent import and Web QA is recorded
separately in [delivery status](../docs/delivery.md).
