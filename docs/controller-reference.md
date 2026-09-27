# Controller references: CrossWorlds and CTR

Research date: 2026-09-27. This is a reference and implementation checklist,
not a claim that physical Xbox Bluetooth testing has passed.

## Verified differences

| Topic | Sonic Racing: CrossWorlds | CTR Nitro-Fueled | Project decision or open choice |
| --- | --- | --- | --- |
| Drift activation | Hold drift while turning; charge supports progressively stronger boosts. | Hold a shoulder button entering a turn to hop and slide. | User requests either LB or RB to initiate. |
| Boost activation | Release the drift button. | While holding R1, press L1 in the red timing region; do not release the initiating button. | Adopt the requested CTR-like opposite-shoulder interaction, not CrossWorlds release-to-boost. |
| Boost chain | Charge strength is distinct from a repeated manual chain. | Up to three timed boosts during one slide. | User confirmed the full three-boost cycle; releasing ends the drift without automatic boost. |
| Failure feedback | Do not infer CTR backfire rules from Sonic's charge system. | Waiting too long produces backfire feedback and misses the boost. | Exact timing and failure tuning are our own parameters. |
| Items | One item-use action in the control table. | One power-up action; some items have repeated uses or secondary activation. | One button consumes our two carried items in order, as requested. |

The current [SEGA retail manual](https://manual.sega.jp/sonicracingcrossworlds/ru/index.html)
describes charge strength and direction changes. Its control table has no
opposite-shoulder boost action. Release-to-boost is stated explicitly in SEGA's
[closed-network-test tutorial](https://manual.sega.jp/sonicracingcrossworlds/cnt/asia_en/index.html?pid=3).
That tutorial is an older official reference, not a source for current numerical
balance. The retail manual does not explicitly specify FIFO ordering; our FIFO
rule comes from the user's request.

The explicit R1-hold/L1-press interaction and three-boost limit are documented in
[PlayStation's official CTR guide](https://www.playstation.com/en-ae/editorial/everything-you-need-to-know-about-crash-team-racing-nitro-fueled/).
[Activision's gameplay tips](https://support.activision.com/uk/en/crash-team-racing/articles/crash-team-racing-nitro-fueled-gameplay-tips)
confirm black exhaust smoke as a timing cue, backfire on waiting too long, the
three-boost chain, a turbo gauge, and optional glowing Nitro Wheels. The exact
early/late timing thresholds and reserve equations are not specified there.
Do not present locally chosen constants as original CTR values.

## Verified CrossWorlds control reference

The A-accelerate variant in the
[retail control table](https://manual.sega.jp/sonicracingcrossworlds/ru/index.html)
uses the following. CrossWorlds offers additional controller variants; this is
not a universal kart-racing standard.

| Action | Xbox | Keyboard |
| --- | --- | --- |
| Accelerate | A | Space |
| Brake / reverse | B | C |
| Steer | Left stick | A / D |
| Drift | RB / RT | E / Shift |
| Item | LB / LT | Q |
| Rear view | X | F |
| Pause | Menu | Tab |
| Gadget ability | Y | T |

Our required LB/RB drift pair occupies CrossWorlds' item binding. The user
confirmed Y as the single item key, X rear view, A accelerate and B brake/reverse.
This is a deliberate adaptation, not a copy of either entire layout.
CTR Nitro-Fueled's official
[platform listing](https://www.activision.com/games/crash/crash-team-racing)
lists consoles, not a PC keyboard scheme; do not invent an official CTR keyboard
layout.

## UI and UX recommendations

These are project recommendations, not undocumented claims about either game's
menu implementation:

- Treat controller navigation as a complete screen flow: main menu, race setup,
  per-player choices, pause, settings, confirmation, results, and replay.
- Give every screen a deliberate initial focus. Preserve focus when returning
  from a child screen. Keep D-pad and stick navigation stable with held-repeat
  delay and stick hysteresis; one held confirm must never activate two screens.
- Use A to confirm and B to return in menus, regardless of racing bindings. Keep
  a compact context-sensitive action strip and an obvious selected row. Do not
  require hover, mouse scrolling, or a native select popup for a core flow.
- Prefer a short pause list; move detailed controls and device reassignment to
  a settings subview. Keep diagnostics and connection details outside the normal
  racing HUD.
- Show one prominent current-item icon and a smaller next-item icon, one use
  prompt, and no selectable-slot presentation. Animate advancement only after a
  successful authoritative consumption. Preserve the queue on a rejected use.
- Display the drift timing window and remaining chain capacity near the kart
  or primary gauge. Show which opposite button is actionable. Color alone must
  not carry ready, success, and failure states.
- Detect and prefer an available gamepad for a new solo seat; do not require
  the player to choose it manually. Preserve explicit multiplayer ownership and
  never steal another player's controller after a hot-plug.

Web detection has a platform limitation: a controller connected before page load
may only be exposed after a button/axis interaction on the focused page.
Disconnect/reconnect may also reuse an index. Poll current state rather than a
cached event object, and avoid promising silent pre-interaction detection on all
browsers. See [MDN's Gamepad API guide](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API/Using_the_Gamepad_API).

## Implementation pitfalls to test

- The existing single `drift` Boolean cannot distinguish the initiating shoulder
  from a new press on the opposite shoulder. Simply OR-ing LB/RB loses required
  information and enables accidental repeated boosts.
- Define simultaneous initial presses, early taps, late taps, held opposite
  input, initiator release, direction reversal, falling, weapon interruption,
  pause/resume, and device loss. A canceled drift must not award release boost.
- Local play, prediction, authoritative simulation, bots, replay, and snapshots
  need the same drift state contract. Client-only button remapping is insufficient.
- FIFO is an inventory rule, not merely both buttons pointing at slot zero.
  Confirm behavior for `[empty, item]`, new pickups, multi-use items, use failure,
  two quick presses, and delayed server acknowledgement.
- Remove slot selection consistently from input, visible prompts, mouse actions,
  tutorial, settings, and tests. Keeping an old second-slot bypass contradicts
  the requested sequential inventory.
- Test an entire race-entry-to-replay flow using only a virtual controller, then
  separately record the user's physical Xbox Bluetooth playtest. Synthetic input
  cannot establish Bluetooth reconnect behavior, latency, or physical ergonomics.

## Audit of the previous implementation

This section records the pre-v13 behavior, not the current lobby. Input fixes
in 3.26 did not establish visual acceptance: the user subsequently rejected the
large dark setup form. Task 3.29 separately replaces that screen with the
[full-screen lobby](../design/lobby-v1/README.md). The official CrossWorlds
customization images support a large vehicle preview, visible selection groups,
and a persistent action strip; the CTR online guide supports separating lobby
concerns, not any exact local join/focus implementation. Our four styles and
explicit Add seats remain project-specific decisions.

- P1 is initialized to keyboard in `web/local-race.js`; detecting a pad only
  refreshes options. The previous live test manually selected a controller, so
  its pass did not establish automatic assignment.
- `web/menu-navigation.js` maps left/right to previous/next DOM element, not
  geometric neighbors. A two-column screen therefore behaves like a Tab list.
- Hot-plug rebuilds player rows, losing focus and expanded controls. Context
  prompts mix keyboard and controller bindings regardless of active device.
- The hub's style selection affects online play, while local setup independently
  defaults to drift. The main route must not show settings for a different mode.
- Inventory clears a used slot and fills the first empty slot. Without queue
  compaction, `[A,B] -> [empty,B] -> [C,B]` allows C to jump ahead of B.
- Authoritative input is repeated when no new packet arrives. A boost edge must
  be deduplicated in captured/replayed vehicle state; it must also survive the
  client's full in-flight input window without granting repeated boosts.

The previous 3.26 acceptance covered basic menu input, manual assignment and
pause, not controller-first UX or these revised mechanics. Do not use that
earlier acceptance as evidence that this redesign is implemented.

### Reproduced UI failures

On commit `c082fdd`, a 0.60-second headless Chromium fixture exercised the real
LocalUI and menu navigator. All three expected behaviors failed without page
errors: a detected Xbox at index 3 left P1 on keyboard (-1); Right from the
top-right cell moved to bottom-left; Down from top-left moved to top-right.
The fixture did not select a device manually. Local research artifacts:
`/tmp/gnom-controller-ux-red.cjs` and `/tmp/gnom-controller-ux-red.json`.
These are reproduction results, not fixes or physical-controller acceptance.
