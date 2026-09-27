# MVP Item Assets

Six original low-poly props share the fantasy kart's teal, gold and crystal vocabulary. They are generated from native Godot meshes, with no downloads, external textures or licensed brand artwork. Product names are gameplay placeholders approved for this prototype; this does not grant trademark or production distribution rights. Packaging, silhouettes and symbols are original approximations, not reproductions of commercial packaging.

| ID | Prop | Visual cue |
| --- | --- | --- |
| `fanta` | Orange bottle | Green cap, orange fruit and leaf |
| `mermaid_rum` | Teal bottle | Gold cap, paired tail motif |
| `ice_rum` | Frost-blue bottle | Dark label, ice crystal |
| `stroh80` | Amber bottle | Red diamond, dark fuse |
| `lays_crab` | Red packet | Gold seals, crab motif |
| `bfg10k` | Original green energy weapon | Twin luminous emitters, top crystal |

## Source And Reproduction

- Geometry/material source: `game/items/item_art.gd`.
- Pickup crate: teal cube, gold bands, floating crystal. No collision or authority is encoded in the asset.
- Stroh projectiles reuse the bottle; BFG fires a separate green energy bolt, not the weapon model. Short explosion spheres use orange or green, scaled to authoritative event radius. Reduced effects decreases their size and motion.
- Snapshot presentation/lifecycle: `game/items/item_visuals.gd`. Pickup/projectile IDs reconcile each snapshot; recent event IDs deduplicate effects. `clear()` resets race-local IDs. No damage is applied by presentation.
- HUD images: `web/assets/items/*.png`, transparent 256 x 256 native Godot renders of those exact meshes.
- Regenerate: `GODOT_BIN --path game --script res://items/render_icons.gd` with a graphical renderer. Replace `GODOT_BIN` with the installed Godot executable. No Python or image editing step.
- Verify lifecycle: `GODOT_BIN --headless --path game --script res://tests/item_visuals_probe.gd`.

## HUD Contract

`items` has two item IDs or empty strings. Slot buttons send `{type: 'use_item', slot: 0|1}` and never consume locally. Server state owns inventory, health and timers. `effects` maps item IDs (plus `burn`) to `{remaining}`; `invulnerableRemaining` adds the shield indicator. `blurIntensity` is clamped to 0..1. Blur affects the canvas only, up to 3 px normally or 0.6 px with reduced effects. HUD, menus and input stay sharp. Destroyed countdown is read from `destroyedRemaining`.

Desktop, mobile portrait and compact landscape HUD fixture checks cover icon loading, slot dispatch, no local consumption, empty/disabled state, health, countdown and reduced blur. They are presentation checks, not a substitute for the authoritative gameplay probes or live network testing.
