# Surgical Face Axis Taxonomy

Use this reference to diagnose and design differentiated original photoreal
idol faces. This is aesthetic morphology language for fictional face design, not
medical advice or identity procedure analysis.

## Contents

- Failure diagnosis
- Core surgical/aesthetic axes
- Eye-orbit controls
- Nose-midface controls
- Cheek-jaw-chin controls
- Mouth-philtrum controls
- Face outline and cranial frame controls
- Depth ladder
- Multi-face matrix
- Review rubric

## Failure Diagnosis

Generated idol faces become same-looking when prompts repeat the same hidden
defaults:

- Eyes: `round-almond`, high iris visibility, similar upper-lid fold, similar
  lash/makeup, and no real orbital-depth difference.
- Jaw/chin: soft V-oval, compact lower face, rounded chin, narrow bigonial
  width, and no difference in chin height or projection.
- Nose: slim small bridge, tidy tip, weak side-plane shadow, and no radix,
  supratip, alar base, or tip-projection variation.
- Midface: flat front-lit cheeks, no malar projection, no nasolabial/midface
  transition, and lips that sit on the same plane as the face.
- Styling: same long dark hair, same satin skin, same studio crop, same rose lip
  tint, same catchlight shape.

The fix is not "more asymmetry." The fix is to assign different structural axes
before beauty polish.

## Core Surgical/Aesthetic Axes

### 1. Face Width And Outline

Use when the silhouette must differ.

- `bizygomatic_width`: cheekbone-to-cheekbone width.
- `bigonial_width`: jaw-angle-to-jaw-angle width.
- `cranial_height`: skull height above the brow and hairline balance.
- `lower_face_taper`: how quickly the jaw narrows toward the chin.
- `face_length`: total vertical read from hairline to chin.

Prompt translations:

- "broad cheek-oval with visible cheekbone width and a softer natural jaw path"
- "long vertical oval with calm face length and a specific chin endpoint"
- "soft square-oval with a slightly wider jaw path than a template V-line"
- "short compact heart-oval with preserved jaw-to-neck structure"

Avoid overuse:

- Do not use "soft V-line" across a set. It makes every lower face identical.

### 2. Lower Third And Chin

Use when candidates have the same jaw or chin.

- `lower_third_ratio`: nose base to chin length relative to the whole face.
- `chin_height`: lower lip to chin endpoint distance.
- `chin_width`: horizontal chin endpoint width.
- `chin_projection`: forward projection of the chin plane.
- `mentolabial_fold`: shadow/curve between lower lip and chin.
- `mandibular_angle`: jaw corner visibility and angle.

Prompt translations:

- "shorter lower third with a compact rounded chin and clean jaw-to-neck shadow"
- "longer lower third with a narrow but rounded chin endpoint"
- "wider natural jaw path with a soft square chin width, not a sharp V"
- "chin projects slightly forward, creating a visible lower-lip-to-chin plane"
- "soft mentolabial fold under the lower lip so the chin is not flat"

Avoid overuse:

- Do not use "rounded chin" without specifying height, width, and projection.

### 3. Eye-Orbit Architecture

Use when every face has the same eyes.

- `palpebral_fissure_width`: horizontal eye opening.
- `palpebral_fissure_height`: vertical eye opening.
- `canthal_tilt`: outer-corner lift/drop.
- `upper_lid_fold`: visible fold height and depth.
- `lid_shelf`: hooded or low-lidded upper-lid shelf.
- `orbital_depth`: whether eyes sit forward or deeper under the brow.
- `lower_lid_volume`: under-eye cushion or flat lower-lid line.
- `brow_eye_distance`: vertical distance between brow and eye.

Prompt translations:

- "long low-lidded eyes with restrained vertical openness and a visible lid shelf"
- "wide round-almond eyes with high iris visibility and real socket depth"
- "smaller compact almond eyes with strong lower-lid identity"
- "hooded-bright eyes where the upper-lid shelf is the memory point"
- "narrow crescent eyes where width reads more than height"
- "deeper-set eyes under a soft brow, with real upper-lid shadow"

Avoid overuse:

- Do not pair high vertical openness, high lower-lid brightness, and large
  round-almond shape on every candidate.

### 4. Nose And Midface

Use when all faces look flat or share the same small nose.

- `radix_height`: where the nose begins between the eyes.
- `glabella_depth`: shadow between brows and nose root.
- `dorsum_height`: bridge height.
- `dorsum_width`: bridge width.
- `supratip_break`: transition before the tip.
- `tip_projection`: forward projection of the nose tip.
- `tip_rotation`: lifted, neutral, or slightly downturned tip.
- `alar_base_width`: nostril/alar base width.
- `columella_show`: visible column under the nose tip.
- `midface_projection`: cheek/nose/lip z-plane relationship.

Prompt translations:

- "higher radix and glabella depth so the nose starts with real shadow between the eyes"
- "low soft bridge with enough side-plane shadow to avoid a flat painted nose"
- "stronger nose z-plane with visible root, bridge, supratip, tip, and base depth"
- "compact neat nose with a round tip but real base shadow"
- "wider natural alar base that still fits the face"
- "nose, cheeks, and lips sit on distinct readable z-planes"

Avoid overuse:

- "slim tidy nose" alone erases nose identity. Always specify height, width,
  tip projection, base, and side-plane evidence.

### 5. Cheek And Midface Soft Tissue

Use when faces have the same flat front-lit beauty.

- `malar_projection`: cheekbone projection.
- `submalar_fullness`: area below cheekbone.
- `front_cheek_fullness`: youthful cheek volume.
- `buccal_hollow`: hollowing under cheekbone.
- `nasolabial_depth`: fold/transition from nose side to mouth area.
- `cheek_plane_shadow`: visible plane break under light.

Prompt translations:

- "front cheek volume remains visible at neutral expression"
- "higher cheekbone with a soft edge, no hollow model cheek"
- "one cheek plane catches a different light break"
- "subtle cheek-to-nose transition so the midface is not flat"
- "luminous cheek plane without erasing real facial depth"

Avoid overuse:

- Too much hollowing ages the face. Too much smooth cheek fullness makes every
  candidate cute and same-looking.

### 6. Mouth, Philtrum, And Perioral Tissue

Use when faces differ only by eye and hair.

- `mouth_width`: horizontal lip width.
- `lip_height`: vertical lip fullness.
- `upper_lower_lip_ratio`: lower lip vs upper lip volume.
- `philtrum_length`: nose base to upper lip length.
- `philtrum_depth`: groove and shadow.
- `cupid_bow_definition`: upper-lip shape.
- `lip_projection`: lips projecting from the face plane.
- `corner_bias`: one mouth corner more active or higher.

Prompt translations:

- "small centered mouth with a defined philtrum groove and fuller lower lip"
- "wider relaxed mouth with soft natural lip tissue, not stamped gloss"
- "short nose-to-upper-lip distance with adult face proportions preserved"
- "one mouth corner rests slightly higher without becoming a smirk"
- "lips project from the midface and cast a soft lower-lip shadow"

Avoid overuse:

- Glossy symmetric lips erase expression tissue.

### 7. Hairline And Cranial Frame

Use when the same face appears under different hair.

- `forehead_height`: hairline-to-brow distance.
- `temple_openness`: how much temple area shows.
- `hairline_shape`: round, widow's peak, irregular, soft baby hairs.
- `part_geometry`: center, side, open temple, curtain frame.
- `face_frame_density`: how much hair hides or reveals cheek/jaw.

Prompt translations:

- "one temple more open, with soft baby hairs changing the face outline"
- "curtain bangs with varied density, not helmet hair"
- "sleek side part that exposes one cheekbone and narrows the opposite cheek"
- "short bob frame that rounds the cheek and jaw silhouette"

Avoid overuse:

- Hair cannot be the dominant identity point unless it changes the visible face
  frame.

## Depth Ladder

Use this ladder to stop flat faces.

1. `glabella/radix`: shadow between brows and nose root.
2. `orbital_depth`: upper-lid shelf and socket shadow.
3. `nose_side_planes`: bridge and tip side shadows.
4. `malar_projection`: cheek plane catches light separately from nose.
5. `perioral_projection`: philtrum, lips, and lower lip project from face.
6. `chin_plane`: mentolabial fold, chin front plane, jaw-to-neck shadow.

A face is truly 3D only when at least three of these six are visible.

## Multi-Face Matrix

Before generating 5 or more candidates, fill this matrix:

```yaml
candidate:
  beauty_lane:
  dominant_axis:
  eye_orbit:
    width:
    height:
    upper_lid:
    lower_lid:
    orbital_depth:
  lower_face:
    bigonial_width:
    chin_height:
    chin_width:
    chin_projection:
    lower_third_ratio:
  nose_midface:
    radix:
    dorsum:
    tip_projection:
    alar_base:
    midface_depth:
  mouth:
    width:
    philtrum:
    lower_lip:
    corner_bias:
  depth_locks:
    -
  anti_repeat_guard:
```

No two candidates in a set should share all of:

- same eye width/height family
- same upper-lid family
- same chin height/width/projection family
- same nose radix/tip/base family

## Review Rubric

Score 0-5:

- `beauty_first_read`: immediately attractive, not only realistic.
- `eye_orbit_distinction`: eyes differ from the rest of the set.
- `lower_face_distinction`: jaw/chin/lower third differs from the rest.
- `nose_midface_depth`: radix, bridge, tip, base, and side planes survive.
- `face_depth_ladder`: at least three depth ladder points are visible.
- `non_likeness`: no public-figure or private-person resemblance target.
- `prompt_compactness`: prompt carried the essential controls without overload.

Failure rules:

- If `beauty_first_read` is below 4, restore flattering light, hair polish,
  lashes, lip tint, and camera before adding more anatomy.
- If `eye_orbit_distinction` is below 3, change eye height, upper-lid fold, and
  orbital depth. Do not merely change eyeliner.
- If `lower_face_distinction` is below 3, change chin height, width, projection,
  or bigonial width. Do not merely change hair length.
- If `nose_midface_depth` is below 3, add radix/glabella, side-plane, tip, base,
  cheek, and lip z-plane evidence.
