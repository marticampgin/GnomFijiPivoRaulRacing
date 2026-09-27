# Baseline vs Target

Evidence in `baseline/` is preserved from the prior actual Web QA on 2026-09-27,
not newly generated in this planning step. Its source QA result is included.
The baseline remains a technical visual pass, not accepted final art.

| Area | Observed baseline | Required next evidence |
| --- | --- | --- |
| Driver | Angular face, broad simple beard pieces, stiff arms and hat | Sculpted readable face, coherent hair/cloth, wheel/hand rig, front and rear Web inspection |
| Kart | Narrow lightweight silhouette; same player's color changes by join slot | Broad low body, materially distinct surfaces, consistent teal preset across clients |
| Rear engine | Tall cyan prism/cage masks most of the driver's back | Compact low crystal and two low outlets, visible driver shoulders/hat |
| Route | Flat oval, repeated radius, flat ground around road | Full authored loop with slope, descent, bridge, water reveal and opposing turns |
| World | Simplified castle and repeated trees; flat lake and distant steep polygon peaks | Coherent architecture, nearer vegetation/terrain transitions, visible water/foam and layered mountains |
| Light/materials | Bright flat patches, sharp white road fixtures, less depth than concept | Controlled sunlight/shadows and coherent enamel/stone/cloth/rubber response in actual Web |
| Motion | Wheel/driver procedural motion, simple crystal boost; steering wheel/hand contact not rigged | Synchronized wheel/steering/hand/body motion and visible timed drift/boost |
| Performance | Prior QA contains one 39 FPS observation, no accepted percentile budget | Declared device/browser, cold load, p50/p95/p99 over three laps, memory availability and explicit limits |

The two baseline desktop frames show a red local kart because another session
occupied the first teal slot. This is an identified preset bug, not a proposed
change to the accepted teal hero. New concept art must not be substituted for
runtime screenshots when reporting progress.

## Character Pass, Art Revision 5

Actual evidence: four Blender renders in `/private/tmp/gnom-hero-sculpt-art5-final/`
and release-Web captures in `/private/tmp/gnom-hero-art5-smoke/` (2026-09-27).
The original baseline and approved reference images above are unchanged.

| Area | Current evidence | Remaining mismatch |
| --- | --- | --- |
| Face/hair | Layered unequal beard/nape locks, heavier lids, cheek/nose/ear forms; front/rear Web views inspected | Still simplified face planes and broad hair clumps; less sculptural detail than the accepted sheet |
| Clothing | Leather waistcoat, collar, shaped sleeves and cloth hat band; shirt poke-through and floating hem stitches corrected after render review | Folds remain shallow; no deforming arm/cloth rig |
| Materials/light | One baked PBR set retained in Standard/Low; no missing textures or browser errors observed | Bright Web lighting flattens white hair and surfaces; moderate wear, no normal map |
| Runtime | 278 import and 112 adapter checks; 15.21-second focused browser smoke with motion/turning and three viewport sizes | Not final model/user acceptance, full-race/network regression or performance evidence |

The environment remains the previous route study. This hero-only pass does not
approve route composition or close the detailed-world work.
