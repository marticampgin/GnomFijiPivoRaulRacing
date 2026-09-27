# Local race lobby v1

Date: 2026-09-27.

## Purpose and scope

Replace the local-race setup form with a dedicated, full-screen game UI. The
previous modal made device dropdowns the dominant content. This version makes
the existing driver and kart, four driving styles, player seats, and race setup
the main hierarchy.

This is an implemented design direction, not an approved final visual result or
a claim of matching the production polish of CTR or CrossWorlds. Browser visual
tests and physical-controller acceptance remain separate; no test counts or
acceptance results are asserted here.

## Implemented screen

- Full-screen HTML UI with a paddock background, rather than a blurred hub behind
  a small setup dialog. Its controls remain real UI, not text baked into artwork.
- A prominent render of the existing MVP driver and kart. No additional
  characters, vehicles, or tracks are implied by the selection screen.
- All four established styles are visible: handling, acceleration, speed, and
  drift. Selection changes the existing style choice, not the gameplay balance.
- Four seat positions show the local party. Empty positions have an explicit
  Add action. The concept's press-to-join suggestion is not implemented and must
  not be advertised as working behavior.
- Race options use directional steppers instead of native select popups.
  Device assignment remains available, with detailed controls in a separate
  view rather than expanded into the main setup screen.
- Back and Start retain a stable action area. Controller and keyboard navigation
  use the existing menu-input contract; this redesign does not change the
  approved racing bindings or add independent per-seat ready/join mechanics.

The screen is implemented in `web/race-lobby.js` and `web/race-lobby.css`, with
local-race integration in `web/local-race.js`.

## Asset provenance

| Asset | Origin and role |
| --- | --- |
| `design/lobby-v1/concept.png` | ImageGen concept for composition and visual direction. Not a screenshot of running UI and not a source of implemented interaction guarantees. |
| `web/assets/lobby-paddock.jpg` | ImageGen-edited concept background. This and the track tile are concept art, not screenshots of the current gameplay environment. |
| `web/assets/lobby-kart.png` | Transparent Blender render of the project's existing `art-source/hero/hero-blockout.blend`. Uses the actual authored MVP model, not the stylized kart illustration in the generated concept. |
| `scripts/art/render-lobby-kart.py` | Reproducible render-only preparation of the kart PNG. Opens the existing scene, adjusts presentation in memory, and does not save changes to the source `.blend`. Checks its source hash and transparent image margins. |

The model-image substitution is deliberate: the lobby should represent the
vehicle that the project actually has. The generated environment communicates
the intended setting, but must not be presented as evidence that the race scene
already has the same detail.

To regenerate the kart render with the project's Blender executable:

```sh
Blender --background --offline-mode --python-exit-code 1 \
  --python scripts/art/render-lobby-kart.py -- \
  --output web/assets/lobby-kart.png
```

## Official references

The following observations were checked against primary sources. They inform
the information hierarchy, not an exact copy of either game's graphics or an
assumption about undocumented input behavior.

- [CrossWorlds character selection](https://manual.sega.jp/sonicracingcrossworlds/efigs/img/screens/Customize01.webp)
  shows a large driver-and-vehicle preview, a visible choice grid, name/type
  identification, and a persistent bottom action strip.
- [CrossWorlds vehicle selection](https://manual.sega.jp/sonicracingcrossworlds/efigs/img/screens/Customize02.webp)
  shows vehicle thumbnails grouped by labeled types. Detailed stats are a
  separate action rather than always-expanded text.
- [CrossWorlds customization](https://manual.sega.jp/sonicracingcrossworlds/efigs/img/screens/Customize05.webp)
  pairs visible choices with a large preview and differentiates selection from
  the installed option. These images are part of the
  [official retail manual](https://manual.sega.jp/sonicracingcrossworlds/ru/index.html).
- [Activision's CTR online guide](https://support.activision.com/crash-team-racing/articles/crash-team-racing-nitro-fueled-online)
  separates customization, game settings, and friends in its lobby description.
  That is an online-flow reference, not proof of local split-screen join or
  focus behavior.
- [Activision's CTR customization article](https://blog.activision.com/ja/crash-bandicoot/2019-05/Announcement-Crash-Bandicoot-Customization-Revealed-Part-1)
  describes inspecting the kart from different angles before a race. Our PNG
  preview is static and does not implement that rotation feature.

Adapting these principles to one approved MVP hero and four styles is a project
decision. No competitor artwork is used as a game asset. See
`docs/controller-reference.md` for the separately verified driving mechanics and
approved control adaptations.

## Verification and reproduction

The approved scope was menu screenshots, not browser race tests. The local
coordinator must be serving assets at `http://127.0.0.1:8787/` for the visual
fixture. With Node and Playwright available:

```sh
node web/tests/race-lobby-browser.cjs
node web/tests/controller-first-browser.cjs
node web/tests/menu-navigation-browser.cjs
node scripts/qa/menu-choice-unit.cjs
node web/tests/menu-navigation.cjs
node scripts/test-control-settings.cjs
GNOM_QA_MENU_ONLY=1 node web/tests/menu-race-browser.cjs
```

The isolated fixtures capture real DOM controls without starting Godot races.
Current results and limits are recorded in `docs/delivery.md`. The responsive
layout keeps fixed actions; short landscape scrolls the body, portrait scrolls
the page, with focus scroll padding to keep controls above the footer.
`browser-desktop.png` and `browser-portrait.png` are captured from that isolated
DOM fixture with the production lobby code and assets, not generated mockups.
The full Web application was separately exercised in a menu-only smoke test.
`browser-live.png` records that full application at 1280x800 after controller-only
style selection, opening/closing controls and the direct Controls/Start focus
link. No race was started.

The display uses ink `#071723`, cyan `#04ced8`, yellow `#ffe436`, cool light
surfaces and four seat accents. Text uses local Arial Black/Arial fallbacks, fixed
breakpoint sizes and zero letter spacing. The model render remains static.
