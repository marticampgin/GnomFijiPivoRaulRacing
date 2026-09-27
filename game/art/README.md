# Visual Sources

The user confirmed on 2026-09-27 that the accepted Figma concept is the target
for the first playable visual pass: red-hat gnome, teal kart with a cyan crystal
engine, paved stone track, castle, cliffs and waterfalls. Geometry remains real
3D and independent of the authoritative vehicle and track collision shapes.

Reference images are `design/assets/kart-concept.jpg` (model silhouette and
materials) and `design/assets/race-concept.jpg` (environment and chase camera).
These are concepts, not renders of the running game. Their views are not a
fully consistent production model sheet.

## Raster Materials

These materials were generated with the built-in image generation tool on
2026-09-27, then copied into this directory. Neither requires an external
asset service or runtime network request.

### stone-road.png

Prompt:

> Use case: stylized-concept. Asset type: square seamless albedo texture for a
> 3D fantasy kart racing game's broad cobblestone road, not a scene or concept
> art. Exact orthographic straight-down view of many small softly beveled and
> lightly worn grey limestone rectangular paving stones, staggered rows with
> narrow dark cool grey mortar gaps. Soft painterly realistic stylized game
> material, restrained stone surface grain, gentle variation in pale neutral
> silver grey and desaturated blue grey, tiny sparse moss flecks confined to a
> few joints. Stones fill the entire square edge to edge at uniform scale,
> roughly 9-12 stones across; seamless/tileable left-right and top-bottom. Flat
> even lighting, no cast shadows, no perspective, no large highlights, no
> objects, no border, no text, no watermark. This is actual repeating material
> for Godot geometry. 1024 x 1024 square texture.

### summer-sky.png

Prompt:

> Use case: stylized-concept. Asset type: equirectangular sky panorama texture
> for a stylized fantasy 3D racing game. Create a seamless 2:1 latitude-longitude
> environment texture (2048 wide x 1024 high): brilliant blue summer daytime
> sky, elegant soft white cumulus cloud banks concentrated around the horizon,
> rich blue high overhead. Flat lower half beneath the horizon should be pale
> blue haze, no land or water, no mountains, no castle, no sun disk, no objects.
> Horizon exactly at image vertical center. Upper quarter predominantly clear
> blue with just fine wisps, cloud banks between vertical 30% and 48%. Soft
> hand-painted game-quality clouds with convincing luminous volume, subtle
> warm-white highlights and cool muted undersides. Seamless left/right 360
> degree wrap, sky-only texture. Avoid text, watermark, borders, overly dramatic
> storm clouds or orange sunset.

### oak-leaves.png

Prompt:

> Use case: stylized-concept. Asset type: transparent foliage texture sprite,
> to be placed on many small intersecting cards inside a real 3D broadleaf tree
> canopy in a fantasy kart racing game. A single dense irregular spray of 35-50
> small individually readable fresh green oak and hornbeam leaves on thin
> branching twigs, viewed face-on, scattered natural layered arrangement,
> slightly asymmetrical broad oval silhouette with jagged leafy edges, tiny
> transparent gaps between leaves, no trunk. Stylized detailed hand-painted
> game albedo with olive mid greens, emerald shadow greens and yellow green
> fresh leaf highlights, subtle veins, subtle tonal variety, soft even ambient
> light with no strong cast shadow. Entire spray in frame with transparent
> margin, nothing cropped. Transparent background required, not white, not
> green background. No pot, no labels, no text, no border, no watermark. Square
> 1024x1024. This is a functional foliage card texture, not a whole tree, not a
> scene.

### limestone-cliff.png

Prompt:

> Use case: stylized-concept. Asset type: seamless square albedo material for
> large limestone cliffs in a 3D fantasy racing game. Flat orthographic view of
> a pale cool grey natural rock surface with long irregular vertical weathering
> fissures and gently varied strata; hand-painted detailed stylized realism.
> Dominantly medium light neutral grey, muted sage mineral accents, soft worn
> stone, very subtle moss deep inside sparse narrow cracks. Fine surface
> texture across the square, organic craggy forms, no individual rectangular
> bricks. Even diffuse lighting, no directional light or cast shadows, no
> strong black cracks. Tileable edge to edge. No landscape, no perspective,
> no objects, no plants growing out, no labels, no watermark. Square 1024 x
> 1024.

## Editable Hero and Route Study

`vehicles/hero-blockout.glb` is the current client hero, exported from the
editable [Blender source](../../art-source/hero/README.md). Its adjacent manifest
records provenance, hashes, dimensions and articulation contracts. It is not
a final accepted model: authored UVs, arm deformation and LODs remain open.

The current route uses a shared [authored bake](../track/AUTHORED_ROUTE.md).
`authored_track_study.gd` adds client-only scenery over those exact road faces;
the old oval remains a separate regression fixture. Standard/Low change only
rendering, not the authoritative route or vehicle simulation.

## Limits

This pass establishes the approved subject and material vocabulary, not parity
with the detailed concept render. Final environmental detailing, material and
animation refinement, ten-kart Web profiling and user visual acceptance remain
separate gates. Current Web evidence is recorded in [delivery](../../docs/delivery.md).
