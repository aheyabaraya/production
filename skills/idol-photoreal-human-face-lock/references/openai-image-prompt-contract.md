# OpenAI Image Prompt Contract For Photoreal Face Locks

Use this reference before writing OpenAI image generation or image edit prompts
for temporary original photoreal human face locks.

Official sources consulted:

- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/api/reference/resources/images/methods/generate
- https://developers.openai.com/api/reference/resources/images/methods/edit
- https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide
- https://openai.com/policies/usage-policies/

## Prompt Order

OpenAI's image prompting guidance favors a consistent, skimmable order. For
temporary face-lock work, use:

1. Goal/use
2. Scene/background
3. Subject
4. Face identity
5. Non-mirror topology
6. Photoreal evidence
7. Framing/camera
8. Preserve/change constraints
9. Exclusions

Do not write one giant paragraph when the prompt has many constraints. Use
short labeled segments.

## Generation Prompt Pattern

Use for a new original fictional face from text:

```text
Goal/use:
Create one photorealistic real-camera identity portrait of a single original
fictional person for face-lock review. Make the face highly distinctive as a
real person before any performer or idol styling is added.

Scene/background:
[Controlled background, lighting direction, color limits, background depth.]

Subject:
[Model-facing age phrase, head angle, gaze, expression, neck/shoulder read. Do
not use "idol" as the default face category.]

Face identity:
[Face architecture, eye-orbit memory, nose/midface planes,
mouth/philtrum behavior, cheek/jaw/chin path, hairline and face frame.]

Distinctiveness pressure:
[The one structural feature that must prevent a generic idol average: unusual
face outline, wider jaw path, stronger nose plane, narrower eyes, heavier lids,
off-center mouth behavior, asymmetrical cheek plane, or another real human
memory point.]

Non-mirror topology:
[Two to five exact differences: eyelid crease, lower lid, nose axis/base,
mouth corner, philtrum, chin endpoint, hairline or strands.]

Photoreal evidence:
[Real pores, under-eye tone, skin texture by face plane, natural catchlights,
flyaway hairs, lip texture, nose shadow, lower-lip shadow.]

Framing/camera:
[Portrait crop, angle, camera height, distance, high-level lens look, depth.]

Avoid:
[Identity separation, anatomy, AI-template, text/logo/watermark limits.]
```

## Early-20s Beautiful Girl Mode

Use this mode when the founder wants the face to read less mature than the first
adult-pass outputs.

Observed YNG test lesson: the stronger results came from removing model-facing
`adult`, `woman`, and negative youth phrasing. Those terms made the generator
overcorrect toward a 30s face read. The improved prompt used the positive phrase
`beautiful girl in her early 20s`, then controlled the face with structure and
depth instead of more age policing.

For this mode, the model-facing prompt must use:

```text
beautiful girl in her early 20s
```

Do not add `adult`, `woman`, or negative youth wording anywhere in the
model-facing prompt for this mode. Keep those concerns in internal notes only.

Use structural youth controls:

- shorter lower face and compact chin
- soft full cheek volume without beauty-filter smoothing
- lower softer brows, not severe glamour brows
- large eyes with real sockets, upper-lid shadow, and lower-lid shadow
- compact nose and mouth scale with visible z-depth
- natural jaw-to-neck shadow, not a floating head
- light natural styling, minimal heavy contour, no mature red-carpet glamour

Keep photoreal depth controls mandatory:

- eye sockets and eyelid shadows
- nose root, bridge, tip, base, and side-plane shadows
- cheekbone-to-cheek plane break
- philtrum groove and lower-lip cast shadow
- chin front plane and jaw/neck cast shadow

## Edit Prompt Pattern

Use image edits when preserving an existing authorized identity, generated
candidate, pose, wardrobe, or layout matters.

Always state what changes and what stays:

```text
Image 1: identity reference / current candidate.
Image 2: wardrobe reference.
Image 3: lighting reference.

Change only:
[The exact face, hair, wardrobe, lighting, or background delta.]

Preserve:
[Identity, face proportions, eye spacing, nose/midface, mouth/philtrum,
age read, expression, hairstyle, body shape, pose, crop, camera angle,
lighting direction, background layout, and any founder-locked details.]

Return:
[Photorealistic real-camera portrait, no text, no watermark.]
```

Repeat the preserve list on each edit iteration. Do not rely on "same as
before" for identity-critical details.

## Multi-Image Input Rules

- Label each input by index and role: `Image 1: identity`, `Image 2: wardrobe`,
  `Image 3: lighting`, `Image 4: background`.
- Describe how the inputs interact. Example: preserve Image 1's face identity,
  use Image 2 only for jacket material, and use Image 3 only for soft window
  light.
- Never attach reference images by default if text locks can control the face
  more cheaply and safely.
- For source-function research, keep named-artist references and source paths in
  research notes only. Remove them from the model-facing prompt.

## API Settings Belong Outside The Prompt

Keep request settings in the export/request manifest, not in the model-facing
prompt prose:

```yaml
model:
size:
quality:
background:
output_format:
output_compression:
moderation:
n:
```

For close-up face-lock work, prefer a high-quality setting when budget allows,
because identity, skin, hair, and small face-plane details are the point of the
test. Use lower quality only for fast drafts.

For portrait review, use a portrait aspect ratio such as `1024x1536` when
supported by the selected model. Confirm current model support from official
docs before paid generation because image model and size support can change.

## Photoreal Prompt Rules

- Use `photorealistic`, `real-camera portrait`, or `real photographed portrait`
  directly.
- Do not default to `idol`, `K-pop visual`, `perfect idol face`, or similar
  category language in first-pass face-lock prompts. Those phrases pull the
  result toward a narrow averaged beauty type. Use `portrait subject`,
  `performer candidate`, or the founder-locked age phrase until the face
  structure is selected.
- For early-20s beautiful-girl tests, do not compensate with negative age terms.
  If the face reads too mature, change lower-face length, cheek fullness, brow
  intensity, styling, and camera first.
- Treat exact camera specs as high-level look guidance, not physical simulation.
  `70-85mm portrait-lens feel` is useful; a long list of camera metadata is
  usually not.
- Name face-plane evidence: nose side planes, glabella shadow, cheek light
  break, philtrum groove, lower-lip shadow, lower-lid ridge, and hairline
  flyaways.
- Name gaze and expression mechanics. Do not write only "beautiful", "chic", or
  "realistic".
- Avoid `flawless`, `perfect symmetry`, `beauty filter`, and `porcelain skin`
  unless the same prompt also demands local texture and non-mirror details.

## Safety And Likeness

- Do not prompt for a source person's likeness or a confusingly authentic image
  of a real person.
- Public figure references may be analyzed only in research notes as abstract function
  categories, never as model-facing likeness targets.
- Private-person references require explicit founder permission for the current
  task and still must be translated into original identity-separation controls.
- Keep all generated identities within the founder-locked age lane. For
  early-20s mode, use the positive age phrase and internal safety notes rather
  than negative model-facing age wording. If age read drifts too mature, fix
  lower-face length, jaw/cheek softness, styling, and camera before enlarging
  eyes or adding beauty polish.
- If a candidate becomes a generic idol average, change face architecture
  before changing makeup, hair color, outfit, or lighting.
- Avoid deceptive authenticity framing. The work is an original fictional human
  identity, not evidence of a source person's existence.
