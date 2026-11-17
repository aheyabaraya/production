# Score To Prompt Translation

Use this reference to turn 0-10 MetaHuman-style controls into prompt-ready
visible face language. Numeric scores are an internal control layer, not
reliable image-model parameters. The generated prompt must contain the translated
visible morphology, not naked numbers.

## Scale

- `0-2`: very low, recessed, narrow, short, soft, or absent.
- `3-4`: slightly low or restrained.
- `5`: balanced realistic idol baseline.
- `6-7`: clearly present but still natural.
- `8-10`: strong identity feature; use only when it is one of the chosen memory
  points.

Use `.5` only inside score sheets. Do not send `.5` precision to the image
model.

## Translation Rule

Every active control must use this shape:

```yaml
eye_horizontal_length_x:
  score: 7
  prompt_translation: "long horizontal almond eyes with a visible outer-corner stretch, not oversized round anime eyes"
  realism_guard: "keep natural eyelid thickness and a slight left/right difference"
  overuse_risk: "can become generic doll eyes if paired with high vertical openness"
```

The `prompt_translation` is the only part that goes into the generation prompt.

## Non-Mirror Topology Rule

A realistic face needs small non-mirrored differences that still look natural.
Do not write only "slight asymmetry." Name the location and the visible result.

Minimum topology map:

```yaml
non_mirror_topology:
  eye_length_difference:
    score:
    prompt_translation: "one eye reads a touch longer horizontally; the other eye holds a slightly rounder inner corner"
  eyelid_crease_difference:
    score:
    prompt_translation: "left eyelid crease sits slightly higher and deeper than the right"
  lower_lid_difference:
    score:
    prompt_translation: "right lower lid catches a softer light ridge than the left"
  nose_axis_and_planes:
    score:
    prompt_translation: "nose bridge stays mostly straight but the tip and base turn a fraction toward camera-left, with different side-plane shadows"
  nose_to_philtrum_to_lip_distance:
    score:
    prompt_translation: "short natural nose-to-upper-lip distance with a visible philtrum groove and a small shadow above the upper lip"
  mouth_corner_behavior:
    score:
    prompt_translation: "right mouth corner lifts first while the left corner stays quieter"
  chin_and_jaw_endpoint:
    score:
    prompt_translation: "chin point is subtly off-center under an idol-soft jaw, not a mirrored V-line"
  hairline_face_frame:
    score:
    prompt_translation: "temple baby hairs and face-framing strands are denser on one side"
```

Only use two to five of these in a final prompt. Too many topology locks can
make the face look damaged or overdescribed.

## Core Controls

### Face Outline And Skull

- `skull_height_y`
- `skull_width_x`
- `cranial_roundness_xyz`
- `face_length_y`
- `face_width_x`
- `face_depth_z`
- `lower_face_taper_x`

Prompt translation examples:

- Low `face_length_y`: "compact face length, with adult jaw and neck structure
  preserved"
- High `face_length_y`: "longer elegant face length, with a calm vertical oval
  read"
- High `lower_face_taper_x`: "lower face narrows cleanly toward a small chin,
  without a severe V-line"

### Forehead, Brow, And Hairline

- `forehead_height_y`
- `forehead_convexity_z`
- `brow_ridge_projection_z`
- `glabella_depth_z`
- `interbrow_distance_x`
- `brow_arch_y`
- `brow_tail_lift_y`
- `hairline_softness`

Prompt translation examples:

- High `hairline_softness`: "soft uneven hairline with small baby hairs at the
  temples"
- Low `brow_ridge_projection_z`: "soft brow bone, no harsh brow ridge"
- Medium-high `glabella_depth_z`: "subtle shadow between the brows so the nose
  root does not look flat"

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

Prompt translation examples:

- High `orbital_depth_z`: "eyes sit slightly deeper under the brow, with real
  upper-lid shadow"
- High `eye_horizontal_length_x`: "long almond eyes with a stretched outer
  corner"
- High `eye_vertical_openness_y`: "open round-almond eyes, still adult and not
  childlike"
- High `lower_lid_volume_z`: "soft lower-lid volume that catches light under
  the iris"
- Medium `left_right_eye_length_delta_x`: "one eye reads slightly longer at the
  outer corner while the other stays a touch rounder"
- Medium `left_right_eyelid_crease_delta_yz`: "one eyelid crease sits slightly
  higher and casts a deeper fold shadow"
- Medium `left_right_lower_lid_delta_z`: "lower lids are related but not
  identical; one catches a brighter ridge under the iris"

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
- `midface_recession_z`
- `midface_forward_projection_z`

Prompt translation examples:

- Medium-high `nose_side_plane_definition_z`: "visible soft nose side planes
  under studio light, not a flat painted nose"
- High `nose_tip_projection_z`: "nose tip projects forward enough to cast a
  small natural shadow below it"
- Low `nose_bridge_width_x`: "slim bridge with natural cartilage width at the
  base"
- Medium `midface_depth_z`: "nose, cheeks, and lips sit on readable z-planes"
- Medium `nose_axis_subtle_offset_x`: "nose bridge is mostly straight but not
  ruler-perfect; the tip falls a fraction off the exact centerline"
- Medium `nose_tip_left_right_delta_xz`: "one side of the nose tip catches more
  light while the opposite side casts a softer shadow"
- Medium `nose_base_asymmetry_x`: "nostril/base width is natural and slightly
  uneven, not mirrored"

### Cheeks, Jaw, Chin, And Neck

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

Prompt translation examples:

- High `cheek_fullness_z`: "front cheek volume remains visible when the mouth is
  neutral"
- Medium `jaw_angle_definition_xyz`: "jaw corner exists but stays idol-soft"
- Low `buccal_hollow_recession_z`: "no hollowed model cheek; keep natural
  rookie softness"
- Medium-high `neck_length_y`: "clean visible neck height under the jaw, not a
  floating head"

### Mouth And Expression

- `mouth_width_x`
- `mouth_height_y`
- `upper_lip_volume_z`
- `lower_lip_volume_z`
- `lip_forward_projection_z`
- `cupid_bow_definition_xy`
- `philtrum_length_y`
- `philtrum_depth_z`
- `lip_corner_lift_y`
- `nose_to_upper_lip_distance_y`
- `left_right_mouth_corner_delta_y`
- `upper_lower_lip_ratio_z`

Prompt translation examples:

- Low `mouth_width_x`: "smaller mouth width, with lips centered under the nose"
- High `lower_lip_volume_z`: "fuller lower lip with natural uneven highlight"
- Low `philtrum_length_y`: "shorter nose-to-lip distance without childlike face
  proportions"
- Asymmetric `lip_corner_lift_y`: "one mouth corner lifts a little earlier than
  the other"
- Medium `nose_to_upper_lip_distance_y`: "nose-to-upper-lip distance is
  readable with a real philtrum groove and soft shadow above the upper lip"
- Medium `left_right_mouth_corner_delta_y`: "one mouth corner sits a millimeter
  higher, giving the neutral mouth a real human bias"
- Medium `upper_lower_lip_ratio_z`: "lower lip is fuller than the upper lip with
  uneven natural highlight, not a stamped glossy shape"

## Memory-Point Controls

Use these controls only for identity shaping.

```yaml
signature_eye_read:
  score:
  prompt_translation:
asymmetry_locks:
  left_eye:
  right_eye:
  nose_axis:
  nose_tip_or_base:
  philtrum_lip_distance:
  mouth_corner:
  jaw_or_chin:
  hairline:
signature_mouth_behavior:
  score:
  prompt_translation:
skin_and_lens_realism:
  skin_texture:
  under_eye_variation:
  catchlight_realism:
  lens_compression:
  ai_smoothness_risk:
anti_template_guards:
  -
```

## Prompt Compiler Checklist

Before sending an image-generation prompt, confirm:

- No real person name is used as a likeness target.
- No naked numeric score appears in the model-facing prompt.
- The prompt has 3-5 memory points, not 15 competing features.
- At least one memory point is structural, not styling.
- The prompt names at least three non-mirror topology zones across eyes, nose,
  mouth/philtrum, chin/jaw, and hairline.
- At least one non-mirror topology zone is about z-plane or light behavior, not
  only left/right outline.
- At least two real-photo evidence cues are present.
- The adult-age guard is explicit.
- The avoid list blocks generic beauty averaging.

## Review Rubric

Score each generated candidate from 0 to 5:

```yaml
review_scores:
  human_realism:
  identity_distinctiveness:
  memory_point_survival:
  non_mirror_topology_survival:
  non_template_face:
  adult_age_read:
  celebrity_non_likeness:
  prompt_delta_clarity:
matched:
  -
drifted:
  -
next_control_deltas:
  - control:
    from:
    to:
    prompt_translation_change:
```

Failure rules:

- If `celebrity_non_likeness` is below 4, move away from the source family before
  improving beauty.
- If `adult_age_read` is below 4, fix adult skull, jaw, neck, and styling before
  changing eyes.
- If `non_template_face` is below 3, add asymmetry and z-plane shadows before
  adding more makeup or polish.
- If `non_mirror_topology_survival` is below 3, rewrite the prompt with named
  eye, nose, mouth, chin, and hairline differences instead of generic
  "asymmetry."
- If `memory_point_survival` is below 3, reduce the number of active traits and
  make one structural feature dominant.
