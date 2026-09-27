# Hero/Kart Review Blockout

This is an editable, geometry-authored **review blockout**, not a final character,
approved model sheet, completed UV asset, or skeletal rig. The user authorized
continued local implementation; explicit model-sheet and final-art approval
remain pending. The accepted Figma concepts remain the visual authority.

## Files

- `build_blockout.py`: reproducible local Blender construction/export/render script.
- `hero-blockout.blend`: compressed, editable source, with a separate studio setup.
- `../../game/art/vehicles/hero-blockout.glb`: runtime hierarchy only, no studio.
- `../../game/art/vehicles/hero-blockout.manifest.json`: provenance and runtime contract.
- `godot/import_probe.gd`: standalone GLTFDocument import and articulation checks.
- `import-check.json`: measured geometry from the exported GLB in Godot.

Geometry is authored from rings, lofts, curved sections and supporting mesh forms.
Logical parts are joined into 13 editable meshes for export. The source builder
retains the individual design decisions. Materials use PBR base colors,
metallic/roughness and emission; no external textures, downloads, UV unwrap,
armature, animation clips, or LODs are represented as finished work.

## Provenance

Primary rear reference: `design/assets/race-concept.jpg` from the accepted race
art. Secondary front/material reference: `design/assets/kart-concept.jpg`.
The proposed `design/reviews/presentation-slice/hero-kart-review-01.png` informed
the combined proportions but remains an unapproved raster proposal, not a
geometrically authoritative turnaround.

Figma authorities: original presentation `JK4YNN8zKqhuZonVbDZ8YB` node `2:291`;
accepted race HUD `OejURNEY5ZRhWWOBicFNYP` node `3:101`; accepted garage node
`3:22`. No Figma source was modified and no third-party model was downloaded.

## Reproduce

Run from the repository root with the locally verified Blender 4.5.13 LTS binary.
No additional environment variables or Python packages are required. The current
macOS restricted sandbox cannot initialize Blender's Metal detection; this
command was run with explicit approved local-process permission, offline.

```sh
/private/tmp/gnom-blender-4.5.13/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --offline-mode --python-exit-code 1 \
  --python art-source/hero/build_blockout.py -- \
  --source-dir art-source/hero \
  --runtime game/art/vehicles/hero-blockout.glb \
  --renders /private/tmp/gnom-hero-blockout-renders
```

The command replaces the owned source/GLB outputs, produces no `.blend1` backup,
and renders the same geometry with four cameras into `/private/tmp`. The source
contains studio lights/cameras/floor for review; export selection excludes them.
Source plus runtime GLB are guarded below 10 MiB. Blender binary build hash:
`daeeeca98fb0`. Installation/archive verification is in `tooling/blender.json`.

```sh
/private/tmp/gnom-racing-godot-4.7.2/Godot.app/Contents/MacOS/Godot \
  --headless --path art-source/hero/godot --script import_probe.gd -- \
  "$PWD/game/art/vehicles/hero-blockout.glb" \
  "$PWD/art-source/hero/import-check.json"
```

The import probe does not open the runtime project or change its importer. It
measures transformed vertices, material availability, exact attachment names,
ground contact, local-X rolling, steering/hand parenting, crystal height and
rear exhaust orientation. It is not a browser-render or performance acceptance
test. On this macOS host an approved launch also avoids sandbox user-data and
system-certificate warnings.

## Runtime Contract

Meters, unit scale, +Y up, -Z forward. The exported root is `HeroBlockout`;
Godot may add a file-name wrapper. Resolve the following unique names without
assuming the wrapper. Ground contact is y=0. For the existing collider whose
origin is 0.35m above the road, the runtime adapter offsets the asset by
`Vector3(0, -0.35, 0)`; the asset contains no collider or physics changes.

- `FrontLeftSteer` / `FrontRightSteer`: local-Y steering, identity rest basis.
- `FrontLeftRoll`, `FrontRightRoll`, `RearLeftRoll`, `RearRightRoll`: local-X roll,
  identity rest basis, origin at axle center. Rear parents are `RearLeftPivot`
  and `RearRightPivot`.
- `DriverLean` contains `DriverBody` and `HeadMotion`; `HeadMotion` contains
  `Head` and `Hat`. Use restrained leaning only. There is no arm deformation.
- `SteeringPivot` is a root-level sibling of `DriverLean`, identity rest basis.
  Rotate about normalized local `(0, 0.48, -0.877)`; the wheel tilt is baked into
  mesh positions. `SteeringWheel`, `LeftHand`, and `RightHand` are its children,
  preserving grip during a small steering motion. Hands are not skinned arms.
- `CrystalPivot` contains `Crystal`. Retain all imported child transforms;
  mesh local origins must not be guessed from their names.
- `ExhaustLeft` / `ExhaustRight`: symmetric rear emission attachments; local +Z
  points backwards. Their visible barrels belong to `EngineCradle`.

## Review Limits

The four actual Blender renders were inspected from front, rear, side and
three-quarter views. The body is broad teal enamel with brass detail, bent red
hat and sculpted beard silhouette, four correctly oriented tires, a compact
crystal below the shoulders, and two low rear nozzles. These are actual shared
mesh views, not separately generated concept images.

Remaining art work includes facial/hair refinement, final topology/UVs/textures,
finished deformations, optimized LODs and user approval. The stylized blockout
is simpler than the accepted illustrative art. Material surfaces and triangles
must be profiled in a ten-visible-kart browser fixture; a successful import is
not evidence of meeting that performance budget.
