# GLB Export / Import Probe

This isolated fixture tests named nodes, metric scale, Blender-to-Godot axes,
UVs/normals, PBR material values and one embedded generated checker texture.
It is not hero geometry and is not added to the game. Primitives are intentional
here: the probe tests the pipeline, not the promised art quality.

Run from repository root with the pinned tools:

```sh
"$BLENDER_BIN" --background --factory-startup --offline-mode --python-exit-code 1 --python art-source/probes/create_export_probe.py -- --out-dir /private/tmp/gnom-glb-pipeline-probe
"$GODOT_BIN" --headless --path art-source/probes/godot --log-file /private/tmp/gnom-glb-pipeline-probe/import.log --script import_probe.gd -- /private/tmp/gnom-glb-pipeline-probe/export-probe.glb
```

`BLENDER_BIN` is the executable matching `tooling/blender.json`; `GODOT_BIN`
matches `tooling/godot.json`. The generator writes a source `.blend` and
self-contained `.glb` to the chosen output directory. Neither binary belongs in
the production hero folders. Do not run this generator on a production `.blend`.

The Godot phase uses `GLTFDocument` directly on the GLB in an isolated project,
without starting Blender or relying on an existing `.godot` import cache.
Editor import, animation export and real Web Compatibility material rendering
remain separate checks before the production pipeline is accepted.

Verified result on 2026-09-27: **43 checks, 0 failures** with Blender 4.5.13 LTS
and Godot 4.7.2. The tiny generated GLB was 12,216 bytes. Evidence is in
`design/reviews/presentation-slice/glb-pipeline-probe.json` and its linked log.
On this machine the restricted process environment crashed Blender during Metal
initialization before Python ran. An explicitly approved offline launch succeeded;
do not work around permissions by changing system security settings.
