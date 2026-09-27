# Browser QA

Run these checks against an already running local Web preview. They use headed
Chromium in fresh, isolated browser contexts and never attach to a user's browser.
Only `http://127.0.0.1` and `http://localhost` URLs are accepted. The default preview
is `http://127.0.0.1:8788/`.

## Prerequisites

- Node.js with `playwright` and `sharp` resolvable by `require()`.
- Playwright's Chromium already available and a graphical desktop session.
- A matching exported game/backend preview with guest login and the two local
  development profiles enabled. Use a fresh preview race for the art-stage check.

The scripts install no dependencies and do not start or restart servers. When
using an existing external dependency runtime, set `NODE_PATH` to its
`node_modules` directory and use that runtime's Node executable.

## Run Sequentially

```sh
node scripts/qa/browser-driver.cjs
node scripts/qa/art-stage.cjs
```

`browser-driver.cjs` joins as a fresh guest and drives with real keyboard input.
Its default pass requires three laps, the authoritative `finished` flag, the
result dialog, four route-anchor screenshots and a healthy browser console.
Route geometry comes from the HUD descriptor; local camera anchors are used only
when the baked simulation hash matches. No movement packets or teleport commands
are injected.

```sh
GNOM_DRIVER_URL=http://127.0.0.1:8788/ GNOM_DRIVER_OUT=/tmp/gnom-driver-qa node scripts/qa/browser-driver.cjs
GNOM_DRIVER_LAPS=1 GNOM_DRIVER_SECONDS=90 node scripts/qa/browser-driver.cjs
```

The second command is a bounded one-lap smoke check, not a full race finish.
Optional `GNOM_DRIVER_SPEED` sets the upper target speed in metres per second
(default `24`); `GNOM_DRIVER_SECONDS` defaults to `240`.

`art-stage.cjs` checks two development profiles, movement, keyboard drift/boost,
recovery, look-back, a seven-second CDP freeze/resume during acceleration,
graphics toggles, preference persistence after reload, unchanged racing identity,
responsive HUD/menu bounds, accessible controls and an isolated incompatible
launch response. Freeze cleanup always restores the page lifecycle; stale
acceleration after resume is a failure. It renders at 1600x900, 390x844 and 844x390.

```sh
GNOM_QA_URL=http://127.0.0.1:8788/ GNOM_QA_OUT=/tmp/gnom-art-qa node scripts/qa/art-stage.cjs
```

`GNOM_QA_PROFILE_FIRST=0` reverses the default development-profile join order
from `[1, 0]` to `[0, 1]`; the report records the order actually used.

Each script exits nonzero on failure and writes `result.json` plus PNG evidence.
Default output folders are `/tmp/gnom-browser-driver-qa` and
`/tmp/gnom-art-stage-qa`. Run sequentially so foreground focus remains predictable.

These are functional and visual study/blockout checks, not final-art approval,
touch-control support, production bot AI, a performance budget pass or an ARM
server capacity measurement.
