# HUD v2: Local Racing

Status: **accepted by the user**, 2026-09-27. This revision does not change the game.
The previous accepted Figma page is untouched. Artwork is the accepted concept
background, not a screenshot of implemented split-screen or a promise of final graphics.

## Figma Review

- [Revision overview](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=16-3)
- [One player](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=18-4)
- [Two players, side by side](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=18-73)
- [Two players, stacked](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=18-206)
- [Three players and shared overview](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=18-335)
- [Four players](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=18-543)
- [Incoming attack, burn, reverse and recovery](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=18-800)
- [Reusable HUD elements](https://www.figma.com/design/OejURNEY5ZRhWWOBicFNYP?node-id=17-2)

Six editable 1600x900 screen frames use native text, vectors and instances.
There are 27 local components, 17 scoped variables and six Arimo text styles.
Both item slots have equal prominence and independent input labels. Status effects
are separate from inventory. Each local player has a number as well as a color.
The minimap uses the existing baked route, with its direction derived from point order.
Counts, timers, speed and health in screenshots are illustrative, not approved tuning.

## Reference Boundary

Read all 17 sections of the [official Sonic Racing: CrossWorlds manual](https://manual.sega.jp/sonicracingcrossworlds/ru/index.html).
The [official item screenshot](https://manual.sega.jp/sonicracingcrossworlds/efigs/img/screens/Elements06.webp)
shows circular inventory wells at upper left. We adapt that visual hierarchy using
our own item renders, colors and typography. The manual images reviewed suppress
most other HUD elements; our rank, crystal, durability, minimap and split layouts
are our accepted design, not a verified reproduction of Sonic's complete interface.
No SEGA artwork is embedded in the mockups.

## Decisions Confirmed In The Interview

- Next playable milestone: 1-4 local players versus bots, up to 10 total racers;
  four styles, configurable bot difficulty, single race, results and repeat.
- No ranking or mandatory Google sign-in in this local mode. Public online parties
  are deferred. Championship, permanent rewards and story come after testing it.
- At most one keyboard player; each other player has a separate gamepad, or all use
  gamepads. For three players use a 2x2 grid with shared overview in the fourth area.
- Two players default to side-by-side views, with a stacked option. One player uses
  the full screen; four players use four gameplay sectors.
- After the initial Web download the local race runs without a game server. True
  offline reload/caching is deferred; this is not a promise of offline installation.
- Any local player can pause the shared race. A disconnected controller pauses it
  until reconnected or reassigned. A finished player keeps their sector for results
  or spectating; repeat requires every local human to be ready.
- Three bot difficulties adjust driving and item-use skill, not hidden speed,
  teleportation or privileged loot.
- Brake slows to a stop, then holding it drives backward at a limited speed with R
  displayed. The present game has braking only, not commanded reverse.
- Weapons remain in slots. Received damage and negative effects apply immediately,
  without occupying a slot. Repair drinks retain their voluntary blur tradeoff.
- Full inventory does not consume a gift. A collected gift disappears globally for
  two seconds; after respawn anyone, including its last recipient, can collect it.
- Loot softly accounts for rank and leader gap, with the same rules for bots.
- Add shield, dodgeable homing projectile with warning, and a single-trigger rear
  trap. Ordinary hits preserve inventory; a future distinct special attack may
  remove one item. Mass inventory deletion is not approved.
- Shield blocks new weapon attacks and incoming negative effects, not physical
  contact, walls, falls or voluntary drink side effects. It does not cleanse an
  existing burn; cleansing is a separate future ability. Brief post-hit protection
  prevents repeated direct hits, but does not suppress existing burn ticks.
- Turquoise engine-crystal shards exist only in the race, reset next race, and are
  not shop currency. Their capped cumulative bonus affects top speed only.
- Weapons and strong impacts remove some shards; light contact does not. Some lost
  shards scatter for anyone to collect; destruction empties the reserve. Zero shards
  does not itself cause additional stun. Numerical tuning is delegated for playtest.
- Timed start boost, slipstream and three visible drift levels enter MVP; tricks
  are later. All four styles can use the mechanics and retain steering during boosts.
- Shortcuts are open from the first lap. Final-lap obstacles change on the main
  route without closing the shortcut. The leader entering the final lap triggers
  a global warning before the shared change. Obstacles must not spawn inside a
  vehicle. Flight, boats and world transfers are later.
- Future online parts/devices use a shared competitive budget; characters are
  cosmetic for MVP and purchases do not increase that budget.
- Future online: novice protection, code invites, blocking and repeated-quit sanctions
  after a reconnect window. Public rated parties remain deferred.
- Tutorial/input settings precede challenges and cosmetic titles; character
  relationships await the approved story. Time trials/ghosts are not next priority.

## Implementation Handoff

The interview and HUD acceptance are complete. The user authorizes a first numerical
baseline in versioned configuration with a published parameter table, then tuning
through playtests: shards, protection, boosts, projectiles and obstacles. These are
not finalized competitive balance values; screenshot numbers are not requirements.
Specific obstacle assets and shortcut geometry remain implementation work within
the approved rules, not a reason to reopen the entire interview.

Next order: shared local simulation, per-device input and cameras, pause/results/
repeat; then the new race mechanics and track changes. OpenSpec reconciliation is
pending confirmation of the artifact scope. Existing gameplay still uses the prior
single-player HUD and has not gained split-screen from this design acceptance.

## Verification And Handoff

All six screen layouts and the foundation/component boards were visually reviewed.
Initial screen audit found zero viewport-bound violations across 16 player panes.
Screenshot review caught instance health geometry not reflecting numeric overrides;
six explicit health components now provide correct 0/24/34/76/88/100 states.
The horizontal artwork crop was corrected and recovery no longer shows charged drift.
Affected screens were reviewed again. This is design verification, not a measured
four-camera Godot benchmark or mobile support claim.

`*.figma.js` preserve the construction recipes. They run inside Figma MCP, not Node.
`*-state.json` files retain returned IDs; inspect these and the canvas before any
retry. The final state requires components, screens and the refinement pass.
INPUT assets are base64 of the six existing `web/assets/items/*.png` files.
INPUT route is the baked minimap normalized to its bounds and sampled every eighth
point. Background image hash is reused from accepted node `3:103`.
Existing screen creation is deliberately guarded; do not replay scripts blindly.
