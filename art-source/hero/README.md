# Hero/Kart MVP Character Pass

This is an editable, geometry-authored **MVP work in progress**, not a final
character or skeletal rig. The model sheet was approved as the MVP direction on
2026-09-27 ("Для MVP ок"); final rendered-model approval remains pending.
The accepted Figma concepts remain the visual authority.

## Files

- `build_blockout.py`: reproducible local Blender construction/export/render script.
- `hero_materials.py`: authored surface recipes, global UV packing and PBR baking.
- `hero_uv.py`: analytic overlap checks and bounded repair of folded UV polygons.
- `textures/`: generated albedo, ORM and emission atlases, also embedded in GLB/source.
- `material-bake.json`: measured UV, texture and geometry-invariance evidence.
- `hero-blockout.blend`: compressed, editable source, with a separate studio setup.
- `../../game/art/vehicles/hero-blockout.glb`: runtime hierarchy only, no studio.
- `../../game/art/vehicles/hero-blockout.manifest.json`: provenance and runtime contract.
- `godot/import_probe.gd`: standalone GLTFDocument import and articulation checks.
- `import-check.json`: measured geometry from the exported GLB in Godot.

Geometry is authored from rings, lofts, curved sections and supporting mesh forms.
Logical parts are joined into 13 editable meshes for export. The source builder
retains the individual design decisions. One shared 2048-square atlas set carries
color, roughness/metallic and emission across all 13 meshes. Source-authored grain,
cloth weave and restrained enamel/brass wear are baked offline, not evaluated by
Godot. ORM is non-color (R=1, G=roughness, B=metallic); albedo/emission use sRGB.
There is no baked lighting/AO or normal map. Armature, clips and LODs remain open.
Godot imports this GLB with embedded lossless textures (image handling 3), avoiding
another generated PNG copy beside the runtime asset. This setting preserves the
self-contained scene; see [Godot's image-handling modes](https://docs.godotengine.org/en/stable/classes/class_gltfstate.html).

The UV pass checks positive-area triangle intersections across and within all
meshes, isolates only faulty polygons, repacks, and refuses an unresolved bake
after five repair passes. It does not modify vertex positions or topology.
Zero-area geometry is counted separately; the Godot import probe rejects it.
The character pass fixes the 96 former Body degenerates at their source: grille
and louvre bevels now remain below half the thin box depth. The UV audit does
not replace artistic seam/texel-density review or browser mip-filtering checks.

## Provenance

Primary rear reference: `design/assets/race-concept.jpg` from the accepted race
art. Secondary front/material reference: `design/assets/kart-concept.jpg`.
The accepted `design/reviews/presentation-slice/hero-kart-review-01.png` informs
the combined proportions; it is a raster direction, not an exact geometric blueprint.

Figma authorities: original presentation `JK4YNN8zKqhuZonVbDZ8YB` node `2:291`;
accepted race HUD `OejURNEY5ZRhWWOBicFNYP` node `3:101`; accepted garage node
`3:22`. No Figma source was modified and no third-party model was downloaded.

## Reproduce

Run from the repository root with the locally verified Blender 4.5.13 LTS binary.
No additional environment variables or Python packages are required. The current
macOS restricted sandbox cannot initialize Blender's Metal detection; this
command was run with explicit approved local-process permission, offline.

```sh
.tools/blender/4.5.13/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --offline-mode --python-exit-code 1 \
  --python art-source/hero/build_blockout.py -- \
  --source-dir art-source/hero \
  --runtime game/art/vehicles/hero-blockout.glb \
  --renders /private/tmp/gnom-hero-blockout-renders
```

The command replaces the owned source/GLB outputs, produces no `.blend1` backup,
and renders the same geometry with four cameras into `/private/tmp`. The source
contains studio lights/cameras/floor for review; export selection excludes them.
Source plus runtime GLB have a 32 MiB repository accident guard, increased from
the untextured prototype's 10 MiB guard for packed 2048 atlases. This is not an
approved Web transfer/frame/memory budget; those remain deferred by the user.
Blender binary build hash:
`daeeeca98fb0`. Installation/archive verification is in `tooling/blender.json`.

```sh
.tools/godot/4.7.2/editor/Godot.app/Contents/MacOS/Godot \
  --headless --path art-source/hero/godot --script import_probe.gd -- \
  "$PWD/game/art/vehicles/hero-blockout.glb" \
  "$PWD/art-source/hero/import-check.json"
```

The import probe does not open the runtime project or change its importer. It
measures transformed vertices, UV coverage, embedded textures, exact attachment names,
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

The next character pass adds recessed eyes, heavier lids, cheek/nose/ear details,
unequal overlapping beard and nape locks, a leather waistcoat, turned collar,
shaped sleeves and a cloth hat band. Flattened swept cross-sections replace the
old identical round hair tubes. The outer silhouette, wheel/hand pivots and
gameplay collider are retained; this is not a finished sculpt or deforming rig.

Remaining art work includes further facial/hair refinement, final topology and material tuning,
finished deformations, optimized LODs and user approval. The stylized blockout
is simpler than the accepted illustrative art. Material surfaces and triangles
must be profiled in a ten-visible-kart browser fixture; a successful import is
not evidence of meeting that performance budget.

For changes limited to this asset, use the standalone import probe, the game's
`tests/authored_kart_probe.gd` after editor import, and
`GNOM_QA_SCOPE=hero node scripts/qa/art-stage.cjs` against the rebuilt Web preview.
This short browser check does not replace full-lap/network acceptance when
route, physics or network behavior changes.
