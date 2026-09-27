# Art Pipeline Preflight

Date: 2026-09-27. Initial inspection plus verified local setup follow-up.

| Check | Observed result |
| --- | --- |
| Blender executable | Not on PATH; absent at `/Applications/Blender.app`, `/opt/homebrew/bin/blender`, `/usr/local/bin/blender` |
| Other DCC | No other DCC was selected or verified; not a claim that every application was exhaustively inspected |
| Free disk | `df -h . /private/tmp` reported 4.7 GiB available, 98% capacity used, same APFS data volume |
| Godot executable | `/private/tmp/gnom-racing-godot-4.7.2/Godot.app/Contents/MacOS/Godot --version` returned `4.7.2.stable.official.ed1daf0bf` |
| Version pin | Matches `tooling/godot.json` |
| Export templates | `node scripts/setup-godot.mjs --check` succeeded: `Godot 4.7.2 templates verified.` |
| Verified template set | Web no-threads debug/release, Linux ARM64 debug/release, version file; every SHA-256 compared by the existing checker to `tooling/godot.json` |
| Native modeling/export | Initial inspection only; later isolated GLB round trip is recorded below. No final hero source/GLB exists |
| Tool authorization | User authorized local Blender setup during the current implementation turn; root handles download/setup without duplicate installation |
| Paid services | None contacted or authorized |

## Local Setup Follow-Up

Root installed the authorized portable Blender and recorded its official source,
archive SHA-256 and version in `tooling/blender.json`. An independent invocation
of `/private/tmp/gnom-blender-4.5.13/Blender.app/Contents/MacOS/Blender --background
--factory-startup --version` succeeded with `4.5.13 LTS`, build `daeeeca98fb0`.
It emitted a USD `ARCH_CACHE_LINE_SIZE` warning but exited successfully. Roughly
3.8 GiB remained after installation according to the root's disk check. No paid
service, global application replacement, or large source binary was introduced.

Verified official archive SHA-256:
`663ce944257c61ff1d6aa09e15c8f57bbd8d59023adb2fa7edde33a9ed960b53`.
The installed executable is
`/private/tmp/gnom-blender-4.5.13/Blender.app/Contents/MacOS/Blender`.
The source/checksum URLs and tool pin are in `tooling/blender.json`; this archive
hash is not a hash of the expanded application bundle.

## Minimal GLB Round Trip

The isolated scripts in `art-source/probes/` produced a 12,216-byte GLB and a
574,283-byte editable test `.blend`. Pinned Godot parsed the standalone GLB and
passed **43/43** assertions for geometry scale, UVs/normals, named attachment axes,
PBR properties, emission and an embedded texture. The final run had no errors.
See `glb-pipeline-probe.json` and `glb-import-probe.log` for the exact scope.

Actual Blender initialization required an explicitly permissioned offline launch:
the restricted environment crashed in Metal detection before executing Python.
Godot also needed permission for its standard data folder/system certificates to
avoid environment errors. No OS security settings were changed. This proves a
small structural export/import path, not Web material quality, animation or final
hero production. Task 2.4 is therefore not complete from this probe alone.

Reproduce from the repository root with the installed pinned tools:

```sh
/private/tmp/gnom-blender-4.5.13/Blender.app/Contents/MacOS/Blender --background --factory-startup --offline-mode --python-exit-code 1 --python art-source/probes/create_export_probe.py -- --out-dir /private/tmp/gnom-glb-pipeline-probe
/private/tmp/gnom-racing-godot-4.7.2/Godot.app/Contents/MacOS/Godot --headless --path art-source/probes/godot --log-file /private/tmp/gnom-glb-pipeline-probe/import.log --script import_probe.gd -- /private/tmp/gnom-glb-pipeline-probe/export-probe.glb
```

No extra environment variable was required for these verified commands. The
processes did require the explicitly approved system access described above;
`--background --version` alone was not sufficient to prove Blender could export.
GLB SHA-256: `04abe3e754ac0f5f319849c10538954093feba1e1e314ea6ef2ffe1bcfc882d9`.

The template check reads the existing files; no archive was downloaded. It proves
the pinned templates are intact, not that this new art package imports or renders.
ARM64 template verification is not an ARM server capacity test.

Source storage follows `art-source/README.md`. Only the selected review sheet and
existing small Web evidence are being preserved here. Large source files, Git LFS,
and final texture/mesh budgets remain decisions before production asset delivery.

## Memory Measurement Candidate

A fresh temporary Chromium 151.0.7922.34 page at `http://127.0.0.1:8787/` reached
the Godot ready state at 1600x900 without runtime errors. Ten loaded-idle samples
observed one WebAssembly instance and one memory with **58,064,896 bytes
(55.375 MiB)** of allocated linear-buffer capacity throughout. The separate CDP
`Performance.getMetrics` value `JSHeapUsedSize` was **12,347,100 bytes**.

The helper `/private/tmp/gnom-wasm-memory-probe.cjs` observes only the tested
page's public WebAssembly instantiate results and imported/exported Memory
references, then reads `Memory.buffer.byteLength`. It does not inspect memory
contents, persistent browser profiles, or other tabs. The temporary browser was
closed after sampling. Evidence:
`/private/tmp/gnom-wasm-memory-probe/result.json` and `loaded-idle.png` alongside it.

This measures allocated WASM buffer capacity, not live allocator bytes, process
RSS or GPU memory. Those latter metrics remain unavailable. `performance.memory`
reported materially different numbers and is not interchangeable with the declared
CDP JS-heap metric. The helper's instrumented startup is not a replacement for the
uninstrumented cold-load timing baseline.

`tooling/quality-budgets.json` proposes separate maxima of **256 MiB WASM allocated
linear buffer** and **64 MiB CDP JS heap**. Its status remains
`proposed-pending-user-approval`. Full-lap and ten-visible-kart peak memory are
**unmeasured**, not passed by this startup sample. The model sheet also remains
awaiting explicit user approval; no final modeling, UV or rig is authorized by
these measurements.

## Follow-Up Conditions

1. Keep the verified Blender application/download outside version control.
2. Recheck free space before source baking/export; do not clear unrelated files.
3. Approve the proposed model sheet before final hero geometry, UV and rig.
4. Prove GLB import, required nodes/materials and Web Compatibility rendering with
   a small sample before calling the production pipeline ready.
