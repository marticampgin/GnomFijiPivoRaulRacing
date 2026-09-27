# Unified Racing UI v1

27 September 2026. Implementation reference for OpenSpec task 3.30.
This extends the fullscreen lobby to the existing Web interface, not the track,
vehicle model, gameplay rules or production content. User artistic acceptance
and physical Bluetooth Xbox testing remain separate gates.

## Concepts and Assets

- [Main menu](concept-main.png): full-bleed paddock, current kart, four commands,
  guest/profile entry and a bottom input-hint rail.
- [Settings family](concept-settings.png): light modal surface, ink heading,
  cyan divider, value rows, bindings and shared action treatment.
- [HUD treatment](concept-hud.png): light compact plates, active/next item,
  cyan meters, yellow timing/actions and red danger semantics.

The three concepts were generated with ImageGen from the existing lobby screen.
Brief: extend the same light cyan/yellow racing language; retain the red-hat
gnome and current turquoise kart; render real UI as native text/controls; use
only existing menu commands and state; avoid marketing cards, new features or
currencies. Separate concepts cover the main menu, settings family and HUD.
The HUD image is a component reference: its generated world, opponents, road,
item illustrations and minimap are **not** new runtime assets or a promised scene.

Runtime art is reused from `web/assets/lobby-paddock.jpg` and
`web/assets/lobby-kart.png`. The former is an illustration, the latter a render
of the current Blender model; see [lobby provenance](../lobby-v1/README.md).
Two additional icons, `graduation-cap` and `wifi`, come from the same pinned
official Lucide 0.468.0 release and license as the lobby icons. No model edits.

## System and Ownership

`web/ui-theme.css` owns shared shell/dialog tokens and responsive composition.
`web/race-overlays.css` applies those tokens to existing HUD elements without
changing camera-sector grids or state ownership. They load after legacy geometry
styles in the real shell, static server and isolated fixtures.

| Role | Value |
| --- | --- |
| Ink | `#071723` |
| Muted text | `#52687b` |
| Surface | `#f7fbfe` |
| Secondary surface | `#e6edf3` |
| Divider | `#bed0df` |
| Value/selection accent | `#04ced8` |
| Primary action/timing | `#ffe436` |
| Danger | `#b63137` |
| Display typography | Arial Black, bold italic, zero tracking |
| Body/control typography | Arial, explicit UI sizes, zero tracking |

Existing styles retain seat colors and compact/stacked layout breakpoints.
Global focus is an ink outline with a white separation ring. Gamepad A and B
use semantic key attributes; an isolated A hint is never mistaken for Back.
Loading disables start commands; failures replace the stale progress indicator
and appear before menu commands. Online/reconnect errors appear on the active
surface and clear after recovery or an incompatible-version state.

## Fidelity Ledger

The concepts and latest Chromium renders were inspected with `view_image`.
This is a coherent implementation of the lobby's visual language, not a claim
of pixel-identical generated artwork or CTR/CrossWorlds production quality.

| Comparison | Render decision / correction |
| --- | --- |
| Main copy and order | GNOM FIJI, P.I.V.O RAUL RACING; Local Race, Training, Settings, Network Test; profile and local status retained. No invented features or marketing copy. |
| First-screen composition | Same unframed paddock/current kart, left command rail, profile upper right, white bottom rail; portrait stacks kart above commands. |
| Palette and typography | Shared ink/cyan/yellow tokens and italic display headings across menus and HUD; muted labels recolored to remain readable on light surfaces. |
| Icons | Native Lucide line icons; missing training/network SVGs fixed. Existing item raster icons are preserved, not replaced by generated concept items. |
| Settings | Retains all seven actual bindings including turn and pause. Native selects remain in detailed settings with existing controller cycling; decorative fake arrow controls were not added. |
| Input hints | Green A, red B, dark directional hints; no Back hint at root. Preserves keyboard hints and per-seat readiness ownership. |
| Dialogs | Light shared header, divider and action families; long account names wrap; mobile reset no longer overlaps the gamepad select. |
| HUD | Same existing geometry and FIFO behavior, new surface/typography treatment; the network map keeps an ink field for its existing light line. No replacement game world. |
| Compact layout | Fixed crystal/next-item overflow and separated network effects, speed and drift indicators. Camera boundaries remain unchanged. |
| Error states | Loading failure no longer looks like stalled progress; request errors stay visible inside online/reconnect UI, without stale errors after recovery. |

The main concept includes a B/Back prompt even at root; implementation intentionally
omits a command that has no destination. Loading, errors and actual account names
are necessary state-dependent additions. The generated settings image omits some
real bindings; implementation retains them. These differences preserve the app's
existing contracts rather than adding or removing gameplay.

## Verification

Only menu interaction and synthetic state captures are permitted for this stage.
The real exported Godot Web shell is checked with `GNOM_QA_MENU_ONLY=1`; that
branch exits before any local start. It covers virtual Xbox navigation through
hub, lobby, style/device selection, player controls, settings and Back, plus
visible assets and console errors. Physical Xbox is not claimed tested.

`web/tests/ui-system-browser.cjs` reads the real shell, strips Godot boot, stubs
API/host boundaries and rejects external requests and WebSockets. Screens cover
loading/ready/error hub, settings, profile/merge, network setup/errors, HUD,
pause, reconnect, incompatible version, results, local controls/disconnect,
1–4 player HUD/results and tutorial active/complete. All race states in this
fixture are synthetic. No socket, actual race or progression operation occurs.

Viewports: 1600x900, 1280x800, 844x390 and 390x844, plus the lobby's existing
1600x1000, 1024x760 and 320x740 checks. The real main menu is also captured at the
concept's native 1586x992 dimensions. Temporary captures/reports live in
`/tmp/gnom-ui-*` and `/tmp/gnom-controller-live-*`, not production assets.

Browser/IAB automation via the frontend plugin is unavailable in this environment;
the existing repository Playwright Chromium harness is the verification fallback.
Reproducible commands and final results are in [delivery](../../docs/delivery.md).
