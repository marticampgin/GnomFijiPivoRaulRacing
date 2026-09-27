# Godot Toolchain

## Pinned Inputs

- Godot editor: `4.7.2.stable.official.ed1daf0bf`, standard GDScript build, not .NET.
- Export templates: official `4.7.2-stable` archive. Archive size and SHA-256, extracted template hashes and editor download URLs are in `tooling/godot.json`.
- Web: Compatibility, WebGL 2.0, single thread, no native extensions. The current texture profile targets desktop. A mobile compressed-texture export must first enable the corresponding project imports and pass real-device tests.
- Local template cache: `.tools/godot/4.7.2/`. Templates and generated `build/` artifacts are not versioned.

## Install Templates

Prerequisites: Node.js 22 or newer, `unzip`, and the pinned Godot editor on `PATH` or in `GODOT_BIN`.

```sh
node scripts/setup-godot.mjs
```

The first installation downloads the official 1.28 GB archive, verifies its size and SHA-256 before extraction, and installs only single-thread Web and Linux ARM64 templates. Each extracted file is checked against its pinned hash. Global Godot export-template directories are not modified. The archive is cached for reuse.

An already downloaded official archive can be supplied without another download:

```sh
node scripts/setup-godot.mjs --archive /absolute/path/Godot_v4.7.2-stable_export_templates.tpz
node scripts/setup-godot.mjs --check
```

Download editor archives from the URLs in the manifest and verify their SHA-256 before unpacking. The scripts do not automatically install an editor. For an isolated editor installation, use Godot's self-contained mode by creating a `_sc_` marker beside the binary, or beside `Godot.app` on macOS. This also keeps editor settings outside the user's global Godot settings.

## Build Web

```sh
GODOT_BIN=/absolute/path/to/Godot node scripts/export-web.mjs
GODOT_BIN=/absolute/path/to/Godot node scripts/export-web.mjs --debug
```

The command rejects a different editor version or altered/missing templates, imports the project, then exports to `build/web/index.html`. Run it from any working directory. On macOS, `GODOT_BIN` points to `Godot.app/Contents/MacOS/Godot`, not the `.app` directory. `--debug` is for development diagnostics; release is the default.

After export, `scripts/web-present-compat.mjs` applies one version-guarded change
to the generated Emscripten `blitOffscreenFramebuffer`: the live boolean query
`getParameter(SCISSOR_TEST)` becomes `isEnabled(SCISSOR_TEST)`. Chromium profiling
identified synchronous stalls at the original query. The state is not cached,
and scissor disable/restore, framebuffer restore and rendering quality are unchanged.
Official template archives remain untouched. A different engine version or an
unexpected/ambiguous source fragment fails export rather than silently skipping
the workaround. Revalidate or remove it when upgrading Godot/Emscripten. A direct
editor export bypasses this step; use the script for team Web builds.

```sh
node scripts/test-web-present-compat.mjs
node scripts/test-web-present.mjs
```

The first test checks both pinned template variants and rejects source/version
drift. The second runs the actual exported presentation function with changing
scissor state and verifies the WebGL2 blit and restored framebuffer. Real browser
coverage uses `scripts/qa/local-web.cjs`; neither test certifies GPU timing.
API references: [isEnabled semantics](https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/isEnabled)
and [synchronous WebGL queries](https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices#avoid_blocking_api_calls_in_production).

The custom HTML shell lives in `game/web/shell.html`. Its companion application files are served by the backend from `web/`; changing those files does not require rebuilding the engine. Changes inside `game/` do require a new export. Serve the output over HTTP on localhost or HTTPS in a deployment, not through `file://`. The server must return `.wasm` as `application/wasm` and retain all exported filenames. An exported HTML file is not proof that the game rendered: browser console, screenshots, canvas pixels and interaction must also be checked.

## Local CPU Diagnostics

```sh
"${GODOT_BIN:-godot}" --headless --path game --fixed-fps 60 --script res://tests/local_cost_probe.gd
"${GODOT_BIN:-godot}" --headless --path game --script res://tests/local_standings_probe.gd
```

The cost probe warms up 60 ticks and samples 300 ticks with four local seats and
six bots. It separates simulation, visual updates and presentation; nested track,
vehicle and item totals are inclusive, so do not add them to the outer totals.
It deliberately requests presentation every sampled tick for diagnosis, whereas
the Web adapter publishes HUD at 10 Hz. Headless timings do not measure browser
rendering or predict FPS. The standings regression preserves the previous sort
semantics and bounds route projections per snapshot, including results with none.

## Prepare ARM64 Artifact

```sh
mkdir -p build/server
"${GODOT_BIN:-godot}" --headless --path game --import
"${GODOT_BIN:-godot}" --headless --path game --export-release "Linux ARM64 Server" ../build/server/gnom-racing.arm64
```

The preset sets `dedicated_server` and exports an ARM64 executable with its separate PCK. Copy both files to the Linux ARM64 host. Start it with `--headless -- --race-worker` and a private `RACE_TICKET_SECRET` of at least 32 characters; the shared main scene selects the authoritative worker by this flag. A successful cross-export on macOS does not prove Linux runtime compatibility, native WebRTC support or server capacity. Those remain separate smoke and load tests. The optional [ARM test stand](arm-test-stand.md) packages this worker, the metadata API and a separate test PostgreSQL instance without renting infrastructure.

## Verification Boundaries

- Verified archive and extracted templates against the pinned SHA-256 values.
- Verified a single-thread Web export using the pinned editor, and browser interaction with two isolated sessions against the real API and headless worker.
- Linux ARM64 execution and 4/8-core capacity require the target host; no concurrency promise follows from these build inputs.
- Pinning inputs makes the toolchain repeatable. Bit-for-bit equality of every generated artifact across operating systems is not claimed.

## Official References

- [Godot 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
- [Web export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)
- [Dedicated server export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html)
- [Self-contained editor paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html#self-contained-mode)
