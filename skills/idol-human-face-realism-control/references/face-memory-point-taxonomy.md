# Face Memory-Point Taxonomy

This reference turns public idol-face observation into identity-separation categories
for original adult AI idol design. It is for original fictional identity design only.
Use source names only in research notes. Remove source names from model-facing
prompts.

## Source Scope

The examples below are public figure function notes, not likeness targets.

- Sullyoon / NMIXX: public visual discussion and official group profile context.
- Sana / TWICE: public profile and editorial portrait context.
- Tsuki / Billlie: official Japanese profile and public portrait context.
- Ahyeon / BABYMONSTER: public profile/interview context; young-adult source.
- Asa / BABYMONSTER: public profile/interview context; young-adult source.
- Ian / Hearts2Hearts: minor-risk source; exclude from face morphology sourcing.
  Use only broad non-face abstract functions such as clean rookie brightness if
  the founder explicitly needs that category.

## What Makes A Face Feel Real

Real faces are not just high-resolution skin. They have a readable internal
logic:

- Skull volume and face outline do not perfectly match a beauty-template oval.
- The two eyes are related but not identical.
- The eyelids, lower lids, and eye sockets cast small, different shadows.
- The nose has side planes, root depth, tip projection, base shape, and a small
  non-mirrored axis or light difference.
- The philtrum, lips, and mouth corners behave like movable tissue, not a stamp.
- The cheek-to-jaw-to-chin path has a personal imbalance.
- Hairline and face-framing strands hide and reveal structure unevenly.
- Skin has local variation: under-eye tone, pores, cheek sheen, lip texture.
- The lens and light reveal depth rather than flattening the face.

## Public Function Examples

### Clear Vertical Idol Face

Observed function from Sullyoon-like public visual discussion:

- strong front readability
- large clear eye area without losing idol softness
- slim nose and centered mouth
- clean vertical oval and narrow lower-face taper
- polished but still approachable expression

Use as category, not likeness:

```yaml
category: clear_vertical_idol_face
usable_memory_points:
  - "large clear eye area with natural lower-lid volume"
  - "clean vertical oval with a soft lower-face taper"
  - "small centered mouth under a slim nose bridge"
  - "bright direct gaze with real catchlights"
avoid:
  - "perfect doll symmetry"
  - "copied public visual face"
  - "over-small nose and over-large eyes together"
```

### Warm Soft-Charm Face

Observed function from Sana-like public profile/editorial portraits:

- soft eye contact that reads warm before the mouth fully smiles
- relaxed mouth shape with natural lip parting or soft lip volume
- cheek movement that carries charm
- hair and head angle often contribute to the facial read

Use as category, not likeness:

```yaml
category: warm_soft_charm_face
usable_memory_points:
  - "soft lower-lid expression before the smile opens"
  - "one mouth corner slightly more active than the other"
  - "relaxed lips with natural tissue texture, not glossy plastic"
  - "face-framing hair that softens one side of the cheek"
avoid:
  - "named-person resemblance"
  - "over-sultry mouth"
  - "flat cheek with only makeup doing the work"
```

### High-Expression Stage Face

Observed function from Tsuki-like public performance identity:

- eyes and brows can change the whole face quickly
- iris/catchlight and lid shape carry theatrical expression
- small mouth/cheek changes read clearly on camera
- styling can be extreme, but the memorable point is expression control

Use as category, not likeness:

```yaml
category: high_expression_stage_face
usable_memory_points:
  - "eyes carry a sharp expression shift through lid angle and catchlight"
  - "brows and lower lids visibly participate in the expression"
  - "small mouth shape contrasts with intense eye read"
  - "hair or bangs create a strong frame around the eyes"
avoid:
  - "anime eyes"
  - "costume-only identity"
  - "contact-lens color as the only memory point"
```

### Direct Center-Power Face

Observed function from Ahyeon-like public rookie-center material:

- direct camera-facing confidence
- strong eye-to-mouth triangle
- eye makeup and hairline can sharpen the face without changing bone structure
- lips and lower face keep softness under a focused gaze

Use as category, not likeness:

```yaml
category: direct_center_power_face
usable_memory_points:
  - "direct gaze with strong iris catchlights and visible upper-lid fold"
  - "eye-to-mouth triangle reads balanced and centered"
  - "soft lower face under a focused eye line"
  - "dark hair frame adds contrast without hiding the skull shape"
avoid:
  - "copying a YG promotional face"
  - "overdrawn eyeliner as the only identity"
  - "too mature glamour for a rookie adult read"
```

### Calm Rap-Line Chic Face

Observed function from Asa-like public material:

- calm, controlled face with less overt smile
- dark hair framing creates a strong silhouette
- eye shape can read long and quiet rather than wide-open
- mouth stays understated while the gaze carries confidence

Use as category, not likeness:

```yaml
category: calm_rap_line_chic_face
usable_memory_points:
  - "controlled neutral mouth with subtle lower-lip volume"
  - "longer quiet eye shape with restrained vertical openness"
  - "dark hair strands crossing or framing one cheek"
  - "nose and midface planes stay visible under clean light"
avoid:
  - "blank expression"
  - "over-smoothed black-hair idol template"
  - "cold face with no under-eye or mouth tissue detail"
```

## Big Memory-Point Categories

### 1. Face Outline Memory

Use when the person should be remembered from silhouette.

Good prompt carriers:

- compact heart-oval
- long vertical oval
- soft square-oval
- narrow lower-face taper
- small rounded chin
- visible adult neck length

Risk:

- If every member gets the same V-line oval, they become interchangeable.

### 2. Eye-Orbit Memory

Use when the person should be remembered from gaze.

Good prompt carriers:

- long almond eyes
- round-almond eyes
- restrained vertical openness
- visible upper-lid fold
- lower-lid volume
- asymmetric lid height
- one eye slightly longer or rounder than the other
- one lower lid catching more light
- iris/catchlight height not perfectly matched
- real socket shadow

Risk:

- Large eyes plus high smoothness creates an AI doll read.

### 3. Nose-Midface Z-Plane Memory

Use when the face needs real skull depth.

Good prompt carriers:

- visible nose side planes
- small shadow under the nose tip
- nose tip and base not perfectly centered on a mirror axis
- one nostril/base wing slightly wider or more shadowed
- readable glabella depth
- cheek-to-nose plane transition
- mouth and lips projecting from the face plane

Risk:

- If the nose is only "small and pretty", the face becomes flat.

### 4. Mouth-Philtrum Memory

Use when charm or attitude should come from expression.

Good prompt carriers:

- shorter or longer philtrum
- readable nose-to-upper-lip distance
- visible philtrum groove and upper-lip shadow
- small centered mouth
- one mouth corner lifts first
- fuller lower lip than upper lip
- slight natural lip asymmetry
- relaxed closed mouth, not beauty-ad smile

Risk:

- Glossy symmetrical lips create a generated-beauty stamp.

### 5. Cheek-Jaw-Chin Memory

Use when age, softness, or chicness needs control.

Good prompt carriers:

- front cheek volume
- high cheekbone with soft edge
- idol-soft jaw corner
- adult mandible under rookie cheeks
- rounded chin endpoint
- chin point subtly off-center
- one jaw edge or cheek plane catching a different light break

Risk:

- Too much cheek hollow or sharp jaw ages the character; too little adult jaw
  makes the face read underage.

### 6. Asymmetry And Micro-Expression Memory

Use this in every realistic face.

Good prompt carriers:

- one eye is a touch longer while the other is a touch rounder
- one eyelid crease sits slightly higher
- one lower lid catches more light
- nose tip/base sits a fraction off the face centerline
- philtrum groove falls naturally under the nose instead of as a perfect line
- one mouth corner lifts earlier
- chin point is subtly off-center
- hairline is not perfectly mirrored

Risk:

- Overstating asymmetry makes the face look distorted. Keep it subtle.

### 7. Hairline And Face-Frame Memory

Use when the face needs a real photographed frame.

Good prompt carriers:

- baby hairs at temple
- uneven side part
- one strand crossing the cheek
- bangs with varied density
- hair shadow touching one side of the face

Risk:

- Perfect helmet hair makes the face feel synthetic even when skin is detailed.

### 8. Skin, Lens, And Light Memory

Use this to kill AI smoothness.

Good prompt carriers:

- visible pores on nose and cheek
- under-eye tone variation
- natural catchlights, not glass beads
- cheek sheen that changes by plane
- realistic lens compression
- soft shadow under nose and lower lip

Risk:

- "Flawless skin" fights realism unless balanced by local texture.

## Assembly Formula

For one original member, choose:

- 1 face architecture category
- 1 dominant structural memory point
- 2 secondary memory points
- 3-5 non-mirror topology locks across eyes, nose, mouth/philtrum, chin/jaw, and
  hairline
- 2 real-photo evidence locks
- 1 adult-age guard
- 1 anti-template guard

Example structure:

```yaml
identity_strategy:
  face_architecture: "compact heart-oval with adult jaw and visible neck"
  dominant_memory_point: "round-almond eyes with lower-lid volume"
  secondary_memory_points:
    - "small centered mouth with fuller lower lip"
    - "soft cheek volume that remains visible at neutral expression"
  non_mirror_topology:
    - "left eyelid crease sits slightly higher"
    - "right lower lid catches a brighter ridge under the iris"
    - "nose tip falls a fraction off the exact centerline with different side-plane shadows"
    - "right mouth corner lifts first"
    - "chin point is subtly off-center under an idol-soft jaw"
  real_photo_evidence:
    - "fine baby hairs at both temples, uneven density"
    - "small nose-tip shadow and lower-lip shadow"
  adult_age_guard: "adult skull, jaw, and neck; not teenage proportions"
  anti_template_guard: "avoid perfect symmetry and generic K-pop average face"
```

The result should not be "make her look like X." It should be "make a new person
whose face has a few unavoidable, camera-readable reasons to be remembered."
