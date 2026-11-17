# Photoreal Human Face Control Taxonomy

Use this reference to turn old MetaHuman-style thinking into temporary
photoreal human face locks. The useful carryover is structural analysis: x/y/z
face planes, control grouping, and exact iteration deltas. The output must read
like a real photograph, not a render, and each face should have a memorable
human structure rather than an averaged idol template.

## Carry From Legacy MetaHuman Work

- Keep x/y/z thinking:
  - `x`: horizontal width, spacing, left/right difference, stretch.
  - `y`: vertical height, length, position, lid or feature level.
  - `z`: forward projection, recession, socket depth, plane shadows.
- Keep grouped face analysis: skull, forehead/brow, eyes/orbits, nose,
  midface/cheeks, mouth/philtrum, jaw/chin/neck, hairline, skin/lens/light.
- Keep 0-10 internal scoring for comparison and deltas.
- Keep standalone-first generation before group sheets.
- Keep review language: matched, drifted, exact next control deltas.

## Drop From Legacy MetaHuman Work

- Do not use `Unreal`, `MetaHuman`, `3D render`, `CG`, or `game engine` in
  model-facing prompts.
- Do not send naked numeric controls to image models.
- Do not reuse fixed Jellobus run IDs, source file paths, Photo 1-7 labels,
  old generated outputs, or member-specific V7 values as reusable law.
- Do not use source names as prompt targets.
- Do not treat contact sheets as the first identity step.

## Internal Scale

- `0-2`: very low, recessed, narrow, short, soft, absent, or minimal.
- `3-4`: slightly low or restrained.
- `5`: balanced realistic human baseline.
- `6-7`: clearly present but still natural.
- `8-10`: strong identity feature; use only for chosen memory points.

Every active numeric value must use:

```yaml
control_name:
  score:
  prompt_translation:
  realism_guard:
  overuse_risk:
```

Only `prompt_translation` can enter the final prompt.

## Core Control Groups

### Face Outline And Skull

- `skull_height_y`
- `skull_width_x`
- `cranial_roundness_xyz`
- `face_length_y`
- `face_width_x`
- `face_depth_z`
- `lower_face_taper_x`

Prompt carriers:

- compact heart-oval with natural jaw and visible neck
- long vertical oval with a calm face length
- soft square-oval with relaxed lower face
- broad cheek-oval with a wider human jaw path
- short compact oval with jaw and neck preserved
- longer lower-face oval with a specific chin endpoint
- lower face narrows softly without a severe V-line
- chin endpoint sits a fraction off-center under a rounded chin

### Forehead, Brow, And Hairline

- `forehead_height_y`
- `forehead_convexity_z`
- `brow_ridge_projection_z`
- `glabella_depth_z`
- `interbrow_distance_x`
- `brow_arch_y`
- `brow_tail_lift_y`
- `hairline_softness`
- `face_framing_strands`

Prompt carriers:

- soft uneven hairline with small temple baby hairs
- subtle glabella shadow so the nose root does not look flat
- one side of the hairline more open than the other
- varied bang density, not helmet hair

### Eyes And Orbits

- `orbital_depth_z`
- `eye_size_xyz`
- `eye_horizontal_length_x`
- `eye_vertical_openness_y`
- `eye_spacing_x`
- `eye_tilt_y`
- `inner_corner_sharpness_xz`
- `upper_eyelid_fold_depth_z`
- `lower_lid_volume_z`
- `left_right_eye_length_delta_x`
- `left_right_eyelid_crease_delta_yz`
- `left_right_lower_lid_delta_z`
- `iris_height_difference_y`

Prompt carriers:

- eyes sit slightly deeper under the brow with real upper-lid shadow
- wide rounded eyes with high iris visibility and real socket depth
- long low-lidded eyes with restrained vertical openness
- narrow crescent eyes where width reads more than height
- smaller compact eyes with strong lower-lid identity
- hooded eyes where the lid shelf is the memory point
- asymmetrical eye pair where one side is flatter and the other is rounder
- one eye reads slightly longer at the outer corner while the other stays a
  touch rounder
- one lower lid catches a brighter ridge while the other falls into softer
  shadow

### Nose And Midface

- `nose_root_projection_z`
- `nose_bridge_height_z`
- `nose_bridge_length_y`
- `nose_bridge_width_x`
- `nose_side_plane_definition_z`
- `nose_tip_projection_z`
- `nose_tip_roundness_xyz`
- `nose_base_width_x`
- `nose_base_projection_z`
- `nostril_visibility`
- `nose_axis_subtle_offset_x`
- `nose_tip_left_right_delta_xz`
- `nose_base_asymmetry_x`
- `alar_width_difference_x`
- `midface_depth_z`
- `midface_forward_projection_z`

Prompt carriers:

- visible soft nose side planes under portrait light
- nose tip projects enough to cast a small natural shadow
- stronger nose z-plane with visible root, bridge length, and tip/base depth
- wider natural nose base that still fits the face
- low soft nose bridge with enough side-plane shadow to avoid flatness
- nose bridge mostly straight but not ruler-perfect
- tip and base sit a fraction off the exact centerline
- one nostril wing or nose-base side is slightly more shadowed
- nose, cheeks, and lips sit on readable z-planes

### Mouth, Philtrum, And Expression Tissue

- `mouth_width_x`
- `mouth_height_y`
- `upper_lip_volume_z`
- `lower_lip_volume_z`
- `lip_forward_projection_z`
- `cupid_bow_definition_xy`
- `philtrum_length_y`
- `philtrum_depth_z`
- `nose_to_upper_lip_distance_y`
- `left_right_mouth_corner_delta_y`
- `upper_lower_lip_ratio_z`

Prompt carriers:

- smaller centered mouth under the nose
- readable philtrum groove and soft upper-lip shadow
- fuller lower lip with natural uneven highlight
- one mouth corner rests slightly higher without becoming a smile
- lips project from the face plane and are not stamped glossy shapes

### Cheek, Jaw, Chin, And Neck

- `cheekbone_height_y`
- `cheekbone_projection_z`
- `cheek_fullness_z`
- `buccal_hollow_recession_z`
- `nasolabial_depth_z`
- `cheek_plane_shadows`
- `jaw_width_x`
- `jaw_angle_definition_xyz`
- `chin_length_y`
- `chin_projection_z`
- `chin_roundness_xyz`
- `neck_length_y`
- `neck_thickness_x`
- `neck_forward_set_z`

Prompt carriers:

- front cheek volume remains visible at neutral expression
- one cheek plane catches a different light break
- jaw corner exists but stays natural, not template-sharp
- natural mandible under early-20s softness
- clean visible neck height under the jaw, not a floating head

## Distinctiveness Pressure

Every candidate must carry one structural pressure that prevents the face from
collapsing into a generic idol average. Choose one primary pressure and protect
it through generation and review:

- `outline_pressure`: broad cheek-oval, soft square-oval, long lower face,
  compact short face, asymmetric chin endpoint, or non-V jaw path.
- `eye_pressure`: wide-round, long low-lidded, narrow crescent, hooded shelf,
  smaller compact eyes, uneven crease height, or one-eye-longer topology.
- `nose_pressure`: stronger bridge/root, lower softer bridge with real side
  planes, wider natural base, visible tip projection, or off-center base.
- `mouth_pressure`: smaller centered mouth, wider relaxed mouth, fuller lower
  lip, short philtrum, longer philtrum, one corner higher, or non-stamped lip
  texture.
- `cheek_jaw_pressure`: fuller cheek planes, wider natural jaw, softer jaw
  corner, sharper cheek plane, or uneven cheek light break.
- `hairline_pressure`: uneven hairline, one side more open, denser curtain on
  one cheek, irregular bangs, or flyaway/baby-hair pattern that changes the
  face frame.

Do not use hair color, makeup, outfit, or idol role as the primary
distinctiveness pressure. Styling can support identity, but the face must remain
recognizable when styling changes.

### Skin, Lens, And Light

- `skin_texture`
- `under_eye_variation`
- `cheek_sheen_plane_change`
- `lip_texture`
- `hair_flyaways`
- `catchlight_realism`
- `lens_compression`
- `ai_smoothness_risk`

Prompt carriers:

- visible pores on nose and inner cheeks
- slight under-eye tone variation
- cheek sheen changes by face plane
- natural catchlights, not glass beads
- realistic portrait lens compression
- fine flyaway hairs and uneven temple baby hairs

## Identity Strategy Formula

For each original person, choose:

- one primary face architecture
- one dominant structural memory point
- two secondary memory points
- two to five non-mirror topology locks
- two real-photo evidence locks
- one age-read strategy
- one anti-template guard

Example:

```yaml
identity_strategy:
  primary_architecture: "compact heart-oval with natural jaw and visible neck"
  dominant_structural_memory_point: "wide rounded eyes with soft lower-lid cushion"
  secondary_memory_points:
    - "small rounded nose with visible side-plane shadow"
    - "quiet closed mouth with one corner less active"
  distinctiveness_pressure: "wide-round eye orbit plus compact cheek-oval, not small-nose-large-eye idol average"
  non_mirror_topology:
    - "one upper eyelid crease sits slightly lower under the bangs"
    - "one lower lid catches a brighter ridge"
    - "nose tip and base sit a fraction off-center"
    - "chin endpoint is subtly off-center"
    - "hair curtain is denser on one cheek"
  real_photo_evidence:
    - "visible pores on nose and inner cheeks"
    - "fine baby hairs and flyaway strands catch light"
  age_read_strategy:
    model_facing_age_phrase: "beautiful girl in her early 20s"
    internal_safety_guard: "fictional early-20s identity; no minor sourcing or likeness"
    prompt_terms_to_avoid: ["adult", "woman", "negative youth phrasing"]
    youthful_structure_controls:
      - "short lower face with compact rounded chin"
      - "soft full cheek volume"
      - "large eyes with real socket depth and eyelid shadows"
      - "compact nose and mouth scale with visible z-depth"
  anti_template_guard: "avoid perfect symmetry and generic K-pop average face"
```

## Early-20s Youthful Read Controls

Use these controls when the founder wants the face to read like the successful
YNG test set: fresh and early-20s, not a 30s glamour portrait.

- `lower_face_length_y`: keep low to medium-low; shorten the visual distance
  from lower lip to chin.
- `cheek_fullness_z`: keep medium-high; soft cheek volume carries youth better
  than heavy contour.
- `jaw_angle_definition_xyz`: keep readable but gentle; avoid a hard mature
  jaw unless that is the chosen memory point.
- `brow_arch_y`: keep low or softly arched; severe high arches push maturity.
- `eye_vertical_openness_y`: allow larger eyes only with real socket depth,
  upper-lid shadow, lower-lid shadow, and non-glass catchlights.
- `nose_bridge_height_z` and `nose_tip_projection_z`: keep compact scale but
  preserve root, bridge, tip, base, and side-plane shadows.
- `mouth_width_x`: usually small to medium; avoid heavy lipstick shape unless
  explicitly selected.
- `chin_length_y`: short to medium-short with a real front plane and jaw-to-neck
  shadow.
- `skin_texture`: keep pores, under-eye tone, and cheek-plane sheen; do not
  smooth into a doll face.

If the output reads too old, adjust lower-face length, cheek fullness, brow
intensity, makeup/styling weight, and camera distance before changing eye size.

## Useful Face Archetypes

Use these as generic construction choices, not fixed member canon:

- wide-round open gaze
- long low-lidded calm gaze
- narrow crescent side-veiled gaze
- compact small-round quiet pout
- hooded-bright symmetry-break gaze
- heavy-lidded sleepy gaze with explicit age-read strategy
- lifted side-angle cinematic gaze
- broad-cheek human-face center with wider jaw path
- strong-nose editorial face with restrained eyes
- asymmetric mouth-and-chin face with soft plain styling

Each archetype still needs its own skull/outline, nose z-plane, mouth behavior,
hair frame, and real-photo evidence. Eye shape, hair color, or idol label alone
is not a face lock.
