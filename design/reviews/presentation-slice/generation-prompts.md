# Review Sheet Generation

Mode: built-in `image_gen`, reference-derived generation followed by one targeted edit.
Date: 2026-09-27. Only the selected corrected result is copied into this project.
Original references are unchanged. This is a review concept, not an authored 3D asset.

## Initial Prompt

```text
Use case: stylized-concept.
Asset type: ONE professional game production turnaround review sheet, landscape, four clearly separated views of the SAME exact gnome seated in the SAME exact teal and brass crystal kart, intended for user design approval before 3D modeling. This is not a game screenshot.
Input image 1: race-concept.jpg is the PRIMARY authority for broad low rear silhouette, compact rear crystal BELOW the driver's shoulders, low twin exhaust nozzles, readable red hat and white hair from rear.
Input image 2: kart-concept.jpg is secondary authority for the expressive face, red cloth hat, white beard, blue coat, leather gloves, teal enamel front panels, brass lamps, grille, suspension, and material detail. Resolve its conflicting engine and exhaust by replacing the huge high crystal and upward side exhausts with the compact low rear arrangement from image 1.
Composition: a precise two-by-two grid on a flat very light cool-gray studio background. Upper left FRONT orthographic, upper right LEFT SIDE orthographic facing left, lower left REAR orthographic, lower right FRONT LEFT THREE QUARTER perspective. Each view shows the entire kart and seated gnome without cropping or overlap. Same consistent scale for orthographic views, tires share ground line. A small plain heading "HERO / KART - REVIEW 01". Small neutral view labels "FRONT", "SIDE", "REAR", "3/4". No other text, no dimensions, no arrows. No decorative frame.
Same model in ALL four views: compact approximately 2.7m long, 2.1m wide, 2.05m total height including hat, wheelbase 1.75m. Four black rubber tires, rear tires slightly wider, diameter about 0.68m, rounded diagonal treads. Brass rims. Low broad teal enamel body, curved wheel arches but large exposed tires. Small worn brass trims/fasteners and dark tube chassis. Paired warm circular headlamps to either side of a simple dark vertical-slat grille, a modest brass central badge and low protective bumper. NO weapons. Dark brown padded leather seat; small steering wheel, both gloved hands gripping it in a natural seated driving pose, identical pose in every view.
Gnome: stocky proportion, expressive determined friendly aged face, prominent pink nose and pointed ears, thick white swept eyebrows, full white beard and hair. Red bent cloth cap leaning slightly backward with a simple folded tip. Blue wool coat, leather gloves, small dark boots. Driver's face and head must read clearly, detailed sculpted forms, not a toy, not low poly.
Rear: ONE faceted cyan crystal in a low dark-metal/brass cradle, roughly 0.5m tall, centered behind seat between exposed rear tires; top of crystal below shoulders, NOT above hat. Two symmetric circular brass-and-dark-steel exhaust nozzles, horizontally rear-facing below crystal at rear axle height. No exhaust protruding upward beside driver. No flames in this stationary sheet, just a subtle cyan glow deep within each nozzle. Show rear suspension, curved fenders and readable white hair beneath red hat. Only the same low crystal should appear in side/3/4/front as physically visible.
Style/medium: polished high-end stylized 3D game character/vehicle concept render, detailed but clean coherent surface construction. Strong geometry readability. Moderate enamel edge wear, distinguish brushed brass, teal painted metal, rough rubber, leather, woven cloth and white hair. Soft neutral studio illumination with contact shadow, balanced exposure; no dramatic darkness. Teal/brass/red/blue palette as references. Do not redesign between views: enforce identical wheel diameters, bumper, headlamp placement, driver silhouette, seat, compact engine, twin nozzles and tread construction.
Avoid: giant crystal above driver, upward pipes or guns, extra wheels, different vehicle variants, environment backgrounds, logos, extra characters, explosion, motion blur, painterly sketch, overly cute plastic toy, low-poly primitives.
```

## Targeted Correction

The first output was inspected and rejected for stacked side exhausts and a high
side crystal. The corrected output was inspected and selected for user review.

```text
Precise object edit. Correct ONLY the mismatched REAR ENGINE ASSEMBLY in the SIDE and 3/4 panels of this model sheet. Keep layout, all labels, gnome, face, red hat, wheels, all other bodywork, front view, rear view, colors, styling and lighting unchanged.
The lower-left REAR view is the mechanical authority: exactly TWO exhaust nozzles side by side at the SAME LOW HEIGHT centered around rear wheel axle height, pointing horizontally straight back; compact cyan crystal low BETWEEN the rear tires, its top below the back of driver's shoulders. There are no elevated/stacked nozzles. In upper-right SIDE view remove BOTH wrongly elevated/stacked exhaust pipes behind the rear wheel; replace with ONE visible low rear-facing nozzle around axle height, the other nozzle hidden behind it by orthographic projection. Lower the whole crystal cradle from over the rear fenders down BETWEEN the rear tires so its tip is level with or lower than the driver's shoulder, matching the rear view exactly. Show only the visible top part of the low compact crystal above the rear body; upper seat stays clearly above crystal. Apply the same lower crystal correction to the bottom-right 3/4 view. Preserve the two low side-by-side nozzles in the REAR view, not stacked. This is ONE same vehicle rotated, not variations. No new details.
```
