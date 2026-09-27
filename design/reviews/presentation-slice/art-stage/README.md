# Editable Art Checkpoint

Recorded 2026-09-27. This is a working Blender/GLB blockout and environment study,
not final production art or user visual acceptance. The accepted Figma concepts
and presentation have not been changed.

## Evidence

- `hero-blender.png`: actual render of the editable source mesh, not a game frame.
- `stone-start.png`, `forest.png`, `lake-waterfall.png`, `bridge-castle.png`:
  actual Chromium Web frames captured during keyboard-driven racing.
- `joined-02-first.png`: the same teal hero on two clients, with Driver 02 joining
  first. Captured before the translation-follow camera correction; model unchanged.
- `laps-result.json`: final three-lap run with authoritative finish, result dialog,
  raw input-controller observations and zero browser console errors.
- `joined-01-first.png`: final two-profile run with the opposite join order.
- `ui-result.json`: passing gameplay/graphics/preferences/rejoin/version and
  responsive menu/HUD checks, including real drift/boost and seven-second freeze.
- `390x844.png`, `844x390.png`, `menu-844x390.png`, `graphics-low.png`: actual
  responsive and Low-profile evidence. Landscape menu intentionally scrolls.

Runtime: Godot 4.7.2 Compatibility, Chromium 151.0.7922.34, 1600x900 desktop.
Simulation hash: `88a534de126218c02524009a2d9b38394111f70a0cbbd9e1d0b3dea858669b38`.
Art revision 2. Reproduction scripts and prerequisites: [browser QA](../../../../scripts/qa/README.md).
Exact source/export hashes: [hero manifest](../../../../game/art/vehicles/hero-blockout.manifest.json).

## Reference Comparison

| Feature | Verified improvement | Remaining difference |
| --- | --- | --- |
| Hero silhouette | Red bent hat, coherent white beard/hair, blue clothing and visible seated driver | Face and cloth are still simple; final topology, UVs and deformation are not approved |
| Kart | Rounded teal body, brass detail, four animated tires, steering wheel and attached gloves | Polished material response lacks authored wear; arms use limited rigid articulation |
| Rear engine | Low cyan crystal below shoulders and exactly two rear outlets | Energy detail and final VFX are simpler than the concept |
| Road and route | Continuous stone road, height changes, forest turns and directed full-race progress | Repeated paving/parapets need art variation; driving feel on uphill sections needs investigation |
| World | Lake is exposed; two waterfalls, forest, bridge and castle are visible from the route | Faceted mountains, slab-like banks, repeated foliage and simple castle architecture are not reference-level |
| Camera | Translation is followed without accumulating speed-dependent boom lag; stable chase and look-back | Final cinematic framing and camera collision against visual-only scenery remain open |
| Web materials | Hero, foliage, stone and animated water render in Compatibility without console errors | Lighting remains brighter/flatter than the concept; final texture/LOD/overdraw budgets are unmeasured |

The current world is deliberately an editable study. These frames must not be
presented as a 10/10 match, accepted final assets, an ARM capacity result or a
mobile release. Three functional laps are not the required percentile/memory
benchmark, and no ten-visible-kart benchmark has been completed.

The browser fixtures were corrected during verification: the drift fixture now
keeps sufficient entry speed and observes the actual 0.25 boost threshold; the
native dialog check distinguishes browser-chrome focus from a game-background
escape and waits for the asynchronous close handler. The final scripts and
reports include these checks, not a skipped test or an application focus hack.

## Follow-up Gates

Explicit model-sheet/blockout and route-direction approval precedes final UVs,
rigging and detailed scenery. Then refine silhouette/materials, LODs, foliage,
castle/shore geometry, camera-scene collision and the remaining drift VFX.

The keyboard fixture recorded intermittent low speeds on uphill sections while
requesting throttle. Positions stayed continuous and correction was small;
contact/traction is a hypothesis, not an established diagnosis. Keep this as a
separate instrumented driving investigation; do not silently change simulation
compatibility during an art-only pass.
