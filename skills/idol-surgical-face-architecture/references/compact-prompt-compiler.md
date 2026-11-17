# Compact Prompt Compiler

Use this reference to turn detailed surgical/aesthetic face analysis into short,
model-facing photoreal prompts. The prompt must preserve the intended structure
without reading like a medical report.

## Compiler Rule

Detailed analysis can use many axes. A generation prompt should carry only:

1. Beauty lane
2. Dominant structural axis
3. Two supporting axes
4. One depth ladder lock
5. One anti-repeat guard

If everything is important, the image model averages everything.

## Prompt Order

```text
Goal/use:
[Original fictional photoreal identity portrait, no original fictional identity.]

Beauty first:
[Immediate attractiveness lane: fresh, chic, warm, center-power, clear, etc.]

Face architecture:
[Dominant axis plus two supporting axes in visible language.]

Depth lock:
[Glabella/radix, eye socket, nose side plane, cheek plane, lip/chin z-plane.]

Style support:
[Hair, makeup, light, camera that support the face without becoming identity.]

Anti-repeat / avoid:
[What this candidate must not share with prior candidates.]
```

## Compression Pattern

### From Analysis

```yaml
dominant_axis: nose_midface
eye_orbit:
  type: long_low_lidded
lower_face:
  type: longer_lower_third_narrow_rounded_chin
nose_midface:
  radix: high
  side_planes: strong
  tip_projection: medium_high
depth_locks:
  - glabella_radix_shadow
  - cheek_to_nose_plane
  - lip_chin_plane
```

### To Prompt

```text
Face architecture:
Long low-lidded almond eyes with restrained vertical openness. Longer lower
third with a narrow rounded chin endpoint. Stronger nose-midface depth: higher
radix, visible glabella shadow, clean bridge side planes, and a neat projected
tip.

Depth lock:
The nose, cheek plane, lips, and chin must sit on distinct readable z-planes.

Avoid:
round-almond default eyes, compact rounded chin, tiny flat nose, flat front-lit
midface.
```

## Beauty First Without Averaging

Use these phrases to keep the image attractive:

- "strikingly pretty idol-casting portrait"
- "polished commercial beauty portrait"
- "satin skin with subtle natural texture"
- "refined lashes, clean catchlights, flattering eye-level portrait light"
- "soft rose or peach lip tint, not heavy glamour lipstick"
- "healthy glossy hair with controlled face-framing pieces"

Do not let beauty phrases become the whole identity. Pair them with one
structural pressure.

## Anti-Repeat Guards

Use explicit anti-repeat lines when iterating from same-looking outputs:

```text
Avoid reusing the previous set's round-almond eye shape, compact rounded chin,
slim tiny nose, flat midface, and identical soft V-oval lower face.
```

For eyes:

```text
This candidate must not have the same high-open round-almond eyes. Use
[long low-lidded / hooded-bright / compact almond / narrow crescent] eyes with
[specific upper-lid and lower-lid behavior].
```

For lower face:

```text
This candidate must not use the same compact rounded chin. Use
[longer lower third / wider soft-square jaw / forward chin projection / short
cheeky lower face] with visible jaw-to-neck shadow.
```

For nose/midface:

```text
This candidate must not use the same small neat flat nose. Use
[higher radix / lower soft bridge / stronger side planes / wider natural base /
more projected tip] with cheek and lip z-plane depth.
```

## Ten Differentiated Candidate Archetypes

Use as starting structures, not member canon.

```yaml
candidate_01_clear_front_visual:
  beauty_lane: clear bright front readability
  eye_orbit: large clear eyes, medium-high vertical openness, real socket depth
  lower_face: clean vertical oval, soft narrow taper, small centered mouth
  nose_midface: slim bridge with visible side planes
  anti_repeat: do not become doll-symmetric or flat-nosed

candidate_02_low_lidded_editorial:
  beauty_lane: chic polished profile
  eye_orbit: long low-lidded eyes, restrained vertical openness, deeper upper-lid shadow
  lower_face: longer lower third, narrow rounded chin endpoint
  nose_midface: higher radix and stronger side planes
  anti_repeat: avoid open round-almond eyes and compact cute chin

candidate_03_short_cheek_warmth:
  beauty_lane: warm fresh idol charm
  eye_orbit: round-almond eyes with lower-lid cushion
  lower_face: short compact lower third, soft full front cheeks, low chin projection
  nose_midface: low soft bridge with rounded tip and real base shadow
  anti_repeat: avoid long oval face and high sharp nose

candidate_04_soft_square_chic:
  beauty_lane: sleek chic beauty
  eye_orbit: compact almond eyes, moderate vertical openness
  lower_face: soft square-oval, wider natural jaw path, wider chin width
  nose_midface: medium bridge, wider natural alar base
  anti_repeat: avoid V-line taper and tiny centered mouth

candidate_05_hooded_bright:
  beauty_lane: memorable bright stage face
  eye_orbit: hooded-bright eyes where upper-lid shelf is the memory point
  lower_face: compact heart-oval with preserved jaw-to-neck shadow
  nose_midface: compact nose with visible side planes
  anti_repeat: avoid same visible high double-eyelid fold

candidate_06_strong_nose_restrained_eye:
  beauty_lane: expensive elegant portrait
  eye_orbit: restrained almond eyes, lower vertical openness
  lower_face: calm oval, medium chin height and projection
  nose_midface: strong nose z-plane, radix, bridge, supratip, projected tip
  anti_repeat: avoid tiny nose and oversized eyes

candidate_07_wide_cheek_real_person:
  beauty_lane: approachable but striking
  eye_orbit: medium eyes with soft lower-lid identity
  lower_face: broad cheek-oval, slightly wider bigonial width, rounded chin
  nose_midface: natural alar base and visible cheek-to-nose transition
  anti_repeat: avoid narrow V-oval

candidate_08_narrow_crescent:
  beauty_lane: quiet magnetic chic
  eye_orbit: narrow crescent eyes, width reads more than height
  lower_face: long soft oval, defined mentolabial fold
  nose_midface: slim bridge with side-plane shadow
  anti_repeat: avoid large iris-open eyes

candidate_09_mouth_charm:
  beauty_lane: warm expressive profile
  eye_orbit: balanced eyes, not dominant
  lower_face: short-to-medium lower third
  nose_midface: compact nose with real philtrum shadow
  mouth_philtrum: wider relaxed mouth, one corner warmer, fuller lower lip
  anti_repeat: avoid stamped small centered mouth

candidate_10_depth_first:
  beauty_lane: photoreal cinematic beauty
  eye_orbit: deeper-set eyes under soft brow
  lower_face: medium lower third, forward chin plane
  nose_midface: visible glabella, nose side planes, malar projection, lip/chin z-plane
  anti_repeat: avoid flat front-lit face
```

## Prompt Skeleton

```text
Goal/use:
Create one photorealistic real-camera identity portrait of a single original
fictional performer candidate. She must not resemble any named celebrity reference, idol,
influencer, private person, or minor.

Beauty first:
[Strikingly pretty idol-casting portrait + age phrase if applicable + gaze and
expression.]

Face architecture:
[Dominant axis in one sentence.]
[Two supporting axes in one or two sentences.]

Depth lock:
[At least three visible z-plane cues.]

Style support:
[Hair, makeup, lighting, camera.]

Avoid:
copied face, named-person resemblance, ordinary plain portrait, harsh
asymmetry, same round-almond eyes, same compact rounded chin, same tiny flat
nose, flat midface, anime eyes, glass eyes, wax skin, distorted anatomy, text,
logo, watermark.
```

## Iteration Delta Template

```yaml
matched:
  -
drifted:
  - repeated_eye_shape:
  - repeated_lower_face:
  - flat_nose_midface:
  - beauty_drop:
next_prompt_delta:
  preserve:
    - beauty_lane
    - hair_light_makeup
  change:
    eye_orbit:
    lower_face:
    nose_midface:
    depth_ladder:
  avoid_new:
    -
```
