# Browser QA

Run these checks against an already running local Web preview. They use headed
Chromium in fresh, isolated browser contexts and never attach to a user's browser.
Only `http://127.0.0.1` and `http://localhost` URLs are accepted. The default preview
is `http://127.0.0.1:8788/`.

## Prerequisites

Focused local HUD audit (no exported game or server required):

```sh
node scripts/qa/local-hud.cjs
```

This isolated Chromium fixture covers all five layouts at 1600x900, 1280x720,
844x390 and 390x844 with simultaneous effects, incoming warnings, reverse,
countdown, destruction, results and readiness. It checks camera-sector bounds,
non-overlap, loaded item art, own-seat commands and blur isolation. Screenshots
and report are written to `/tmp/gnom-hud-audit` (override with `GNOM_QA_OUT`).
These seeded UI states do not prove a completed Web race or physical pad support.

Track v11 checks use controlled short sections, not three-lap playthroughs:

```sh
godot --headless --path game --script res://tests/shortcut_probe.gd
godot --headless --path game --fixed-fps 120 --script res://tests/track_event_probe.gd
godot --headless --path game --fixed-fps 120 --script res://tests/track_event_session_probe.gd
godot --headless --path game --script res://tests/authored_track_probe.gd
godot --headless --path game --script res://tests/route_study_probe.gd
node scripts/test-track-map.cjs
node scripts/qa/track-event-hud.cjs
```

Shortcut checks drive its real collision joins and the main bend with four styles.
Event checks seed a final-lap leader, then use the production session for warning,
pause, reset and safe activation. Twelve isolated AI runners cover all difficulty
and style pairs through both solid obstacles. These are not a full-race balance
or multiplayer pile-up test. The Web HUD fixture checks phases, non-overlap and
minimap pixels in 1–4 layouts at desktop/portrait/landscape sizes; it does not
drive a browser player to the final lap. Artificial network-delay activation and
physical controller compatibility remain separate checks.

Short control/tutorial checks (no full laps):

```sh
godot --headless --path game --script res://tests/control_profile_probe.gd
godot --headless --path game --script res://tests/tutorial_probe.gd
node scripts/test-control-settings.cjs
```

Browser tutorial flow: change a seat's keyboard scheme/sensitivity, reload and
verify persistence, start `Обучение P1`, complete drive, stop, continuous brake
into reverse, actual level-I drift and release, then use Q/T (or LB/Y) in Arcade.
Wait for the actual drift level, not a nearly full lesson progress bar. Hold
test key presses across at least one physics tick. Verify retry and keyboard
input after changing settings on pause, reset to defaults, and HUD bounds at
1600x900/390x844. No API/WebSocket requests are expected in local training.
This does not validate physical controllers or a four-camera performance budget.

Short native checks for the v8/v9 driving/items milestones (no full laps):

```sh
godot --headless --path game --script res://tests/reverse_probe.gd
godot --headless --path game --script res://tests/reverse_gates_probe.gd
godot --headless --path game --script res://tests/bot_difficulty_probe.gd
godot --headless --path game --script res://tests/gifts_probe.gd
godot --headless --path game --script res://tests/local_app_probe.gd
godot --headless --path game --script res://tests/shards_probe.gd
godot --headless --path game --script res://tests/race_techniques_probe.gd
godot --headless --path game --script res://tests/racing_snapshot_boundary_probe.gd
godot --headless --path game --script res://tests/local_view_probe.gd
godot --headless --path game --script res://tests/combat_items_probe.gd
godot --headless --path game --script res://tests/combat_assets_probe.gd
```

Local browser flow: choose easy/normal/hard in local setup, start, hold brake
during countdown (no reverse), drive forward, brake to stop then reverse (R),
accelerate forward (R clears), pause/resume. Check an independently assigned
gamepad and a 390x844 HUD as well as desktop. Virtual controllers verify software
routing, not real hardware compatibility. Shared gift arbitration/2-second respawn
and full inventory refusal use deterministic native fixtures; do not drive three
laps to test these rules. Baseline values are in `docs/playtest-balance.md`.

For v9, press throttle during the final 0.65–0.15 seconds of countdown and hold it
to verify a real start boost; collect road crystals and check the owning HUD.
Native probes cover slipstream awards, all three drift tiers, stacking and loss/reset
rules. Separate HUD-only fixtures may supply rare combinations of these states to
check layout/icon loading at 1600x900 and 390x844; label them as presentation tests,
not evidence of gameplay awards. Four-camera checks share one pickup world and
verify pause freezes pickup timers. No full-lap or hardware performance claim.

Combat probes cover shield during burn, post-hit guard, inventory preservation,
target lifecycle, limited steering/evade, launch from a moving owner, wall blocking,
one-shot trap arbitration and slope placement. `local_app_probe` exercises real
item commands, shield visuals, owning-seat warning projection, pause and reset.
Browser fixtures exercise the three PNG icons, warning isolation/direction/clearing,
slot dispatch without speculative consumption, and shield plus burn layout. A
controlled native screenshot is evidence of rendering, not a normal Web playthrough.

- Node.js with `playwright` and `sharp` resolvable by `require()`.
- Playwright's Chromium already available and a graphical desktop session.
- A matching exported game/backend preview with guest login and the two local
  development profiles enabled. Use a fresh preview race for the art-stage check.

The scripts install no dependencies and do not start or restart servers. When
using an existing external dependency runtime, set `NODE_PATH` to its
`node_modules` directory and use that runtime's Node executable.

## Run Sequentially

### Native Contact Checks

Use the pinned Godot binary as `godot` below. These short probes cover impulse
response, actual worker ordering, snapshot replay and solid road/parapets:

```sh
godot --headless --path game --fixed-fps 60 --script res://tests/vehicle_contacts_probe.gd
godot --headless --path game --fixed-fps 60 --script res://tests/contact_worker_probe.gd
godot --headless --path game --script res://tests/contact_reconciliation_probe.gd
godot --headless --path game --script res://tests/contact_presentation_probe.gd
godot --headless --path game --script res://tests/contact_motion_probe.gd
godot --headless --path game --fixed-fps 60 --script res://tests/bot_contact_motion_probe.gd
godot --headless --path game --fixed-fps 60 --script res://tests/environment_contacts_probe.gd
```

`bot_race_probe.gd` adds ten-car, three-lap contact coverage on the authored road;
its contact counter counts solver passes, not distinct impacts. It requires zero
recoveries and exactly one finish per racer. This accelerated headless run does
not measure live server capacity or browser frame rate.

The contact presentation probe reproduces the former near-racer overlap from
100 ms delayed rendering, separately from the collision-envelope probe. Nearby
visual extrapolation is capped at 100 ms; it cannot predict an unseen future
impact or guarantee zero overlap under arbitrary latency.

The motion probe uses deterministic snapshot/acknowledgment jitter to check
frame displacement and turn continuity. The bot contact motion probe separates
server-side pack corrections from presentation jitter in a short simulation.

### Browser Scope

Four-style changes also use `driving_styles_probe.gd` for measured acceleration,
speed, turn and drift/boost differences. `race_lifecycle_probe.gd` verifies that
queued styles apply only on the next race and survive recovery. The mixed-style
bot race checks all four profiles without modifying the shared collision mass.

Items use `items_probe.gd`, `items_worker_probe.gd` and `item_visuals_probe.gd`
for catalog effects, command deduplication, destruction/recovery and asset events.
`items_race_probe.gd` runs the actual worker with ten bots and combat enabled;
destruction recovery is expected, while checkpoint bypass and missing finishes
remain failures. `GNOM_DRIVER_ITEMS=1 GNOM_DRIVER_LAPS=1` adds natural pickup and
keyboard Q/T use to the browser driver, requiring a server acknowledgment.
Health loss/destruction is excluded from the road-seam speed-loss heuristic,
not from the independent collision and item assertions.

Choose the scope to match the change. Hero-only geometry/material edits use the
short smoke below, not the full race. Route/physics/progress/network changes
still require their relevant integration checks and, when affected, a full finish.
Do not run three laps solely to validate a face, clothing or texture adjustment.

The shared local-session foundation has short `race_session_probe.gd` and
`local_input_probe.gd` checks. They exercise 1-4 humans with bots in one world and
device-isolated command snapshots; they do not prove physical gamepad compatibility
or completed split-screen UI. Existing worker/contact/item probes cover extraction
regressions. Browser recovery smoke observes the outgoing command and the next
server recovery epoch with the same race/lap, respecting the manual cooldown.
It does not require speed below 2 km/h one second later: another racer can legally
transfer momentum after recovery. Native probes cover the physical reset itself.

```sh
GNOM_QA_SCOPE=hero GNOM_QA_URL=http://127.0.0.1:8787/ GNOM_QA_OUT=/tmp/gnom-hero-qa node scripts/qa/art-stage.cjs
```

This mode checks one dev profile, nonblank/changing canvas, short keyboard
movement and turning, front/rear screenshots, Low rendering and mobile framing.
It records elapsed time and console errors, then exits the race. No laps,
two-client network regression, drift/boost or performance acceptance is claimed.
The default `GNOM_QA_SCOPE=full` keeps the existing art-stage coverage unchanged.

```sh
node scripts/qa/browser-driver.cjs
node scripts/qa/art-stage.cjs
```

`browser-driver.cjs` joins as a fresh guest and drives with real keyboard input.
Its default pass requires three laps, the authoritative `finished` flag, the
result dialog, four route-anchor screenshots and a healthy browser console.
It also rejects sudden unbraked speed losses near the road centre (more than
75% in at most 250 ms from above 8 m/s), excluding long pauses, position jumps
and samples within four metres of another racer where contact is expected.
This proximity exclusion is not proof of a collision; pair impulse behaviour is
covered separately by the native contact and worker probes.
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
`GNOM_DRIVER_REPEAT=1` additionally waits for the terminal ten-car result, checks
nine bots in a fresh single-human race, clicks the repeat button and verifies a
new generation/countdown with lap, elapsed time and result dialog reset. It
requires the default three-lap finish; use a fresh worker with no other humans.
`GNOM_DRIVER_TRACE=1` additionally records the test player's physical snapshots
and input commands to `physics-trace.json`, without handshake tickets or cookies.
This diagnostic capture adds overhead; do not use it as performance evidence.

`art-stage.cjs` preloads two development profiles and joins both during the
countdown, then checks two humans plus eight bots, movement, keyboard drift/boost,
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
# Local Split-Screen

Reproducible browser lifecycle check after starting the static preview:

```sh
node scripts/qa/local-web.cjs
GNOM_LOCAL_SAMPLE_SECONDS=10 node scripts/qa/local-web.cjs
GNOM_LOCAL_QUALITY=low GNOM_LOCAL_SAMPLE_SECONDS=10 GNOM_LOCAL_OUT=/tmp/gnom-local-low node scripts/qa/local-web.cjs
```

The first command exercises all five layouts with virtual controllers, camera
geometry, canvas pixels, keyboard movement, pause/resume, controller loss/return
and exit. It does not play three laps. `GNOM_LOCAL_URL` accepts only localhost;
`GNOM_LOCAL_OUT` selects the external artifact directory. The second command
also samples four-player browser animation callbacks. Keep its window visible
and focused; do not run another browser test at the same time.

Callback interval percentiles are preliminary browser pacing observations, not
GPU render times, engine FPS, a worst-case track benchmark or a performance pass.
The report records its sample window and simulation tick progress. No performance
threshold is accepted yet. A passing virtual-pad test is not hardware validation.
`GNOM_LOCAL_QUALITY` selects `standard` (default) or `low`; every layout verifies
the applied Godot profile. `GNOM_LOCAL_HEADLESS=1` is available for CI smoke checks,
but its measurements must not be compared to a headed run as equivalent hardware evidence.

Remaining physical-controller and user checks (task 3.25 stays open):

1. Record OS/browser, controller models, wired/Bluetooth connection and player count.
2. Assign one keyboard plus distinct pads, then an all-pad setup; verify each
   participant's steering, pedals, drift, look-back and two item buttons independently.
3. Unplug an assigned pad while accelerating. Verify every car/timer stops, the
   player remains present and Resume is blocked. Reconnect or explicitly reassign;
   verify neutral input before new presses and that the other players keep their seats.
4. Finish a local race; each person confirms readiness once. Verify one new
   countdown, cleared effects/crystals, preserved device/style selections and no rewards.
5. Record handling feedback for all four styles and any unreadable HUD or collisions.
   User playtest approval (3.10) is separate from automated correctness.

Build with `node scripts/export-web.mjs`, then start
`node scripts/local-web.mjs --detach`. The reported localhost URL serves static
assets only, with no account API, PostgreSQL or race worker. The network prototype
continues to use `scripts/dev.mjs`.

Focused native checks (use the pinned Godot executable):

```sh
godot --headless --path game --script res://tests/local_race_probe.gd --log-file /tmp/local-race.log
godot --headless --path game --script res://tests/local_view_probe.gd --log-file /tmp/local-view.log
godot --headless --path game --script res://tests/local_app_probe.gd --log-file /tmp/local-app.log
```

These cover local commands, one shared world/tick, pause/disconnect/reassignment,
item projection, recovery, result readiness and reset using short fixtures. They do
not claim a full browser race or physical gamepad verification. Browser smoke:
local setup -> each 1/2-side/2-stacked/3/4 layout -> drive -> pause -> resume -> exit.
Check each canvas sector is nonblank and moves, no API/WebSocket is opened, and
assigned device disconnect blocks resume without removing its player. Test one
keyboard plus distinct controllers, or all controllers; virtual gamepads are only
an automated boundary test, never evidence about real hardware.
## Controller menus and Arcade controls

`node web/tests/menu-navigation.cjs` verifies per-device menu edges, held buttons,
repeat timing and reconnect rearming. `node web/tests/menu-navigation-browser.cjs`
checks DOM focus, settings, controller ownership and keyboard navigation in an
isolated Chromium fixture. `node web/tests/menu-race-browser.cjs` uses the real
Web export on 8788: virtual Xbox menu navigation, device selection, Arcade A
throttle only after release, pause and return. Physical Bluetooth remains a
manual acceptance test. Existing saved profiles keep their previous mappings;
select Arcade or reset controls to test the new default on an existing profile.

## Network input backpressure

`node scripts/qa/network-input.cjs` uses the local dev server on 8787 (override
`GNOM_NETWORK_URL`, output `GNOM_NETWORK_OUT`). It holds one ordered outbound
input batch for 650 ms, then checks the 24-command acknowledgement window,
continued acknowledgements, countdown completion and actual keyboard movement.
It records counts and close reasons, never tickets or raw protocol frames.
Run browser and native network checks serially to avoid distorting timeouts.
This is not a physical controller or sustained latency acceptance test.
