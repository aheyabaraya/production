---
name: idol-photoreal-human-face-lock
description: Temporary standalone skill for building highly distinctive original photoreal human face locks, including early-20s "beautiful girl" portrait tests, that read as real photographed people rather than Unreal/MetaHuman renders, AI beauty templates, or homogenized idol faces. Use when Codex needs to analyze face references as identity-separation source functions, write photoreal human face control sheets, compile OpenAI image-generation or image-edit prompts for identity portraits, review generated face candidates, or plan exact deltas for the next face-lock iteration.
---

# IDOL Photoreal Human Face Lock

Create original human face locks that can survive close-up photoreal image
generation. This is a temporary standalone exploration skill. The target is a
real-camera human portrait feel with highly individual face shape: facial
structure, skull/outline, eye-orbit type, nose and mouth tissue, skin, hair,
lens, light, asymmetry, expression tissue, and age read must all work together.

## Boundaries

- Use this skill for face identity exploration, portrait prompts, reference
  function intake, face-lock control sheets, generated candidate review, and
  iteration deltas.
- Do not route this skill into the main IDOL Graph Engineering route or orchestrator unless the
  founder separately asks for that integration.
- Treat `idol` as a later styling/context layer, not the default face category.
  If the prompt says only "idol face", models tend to average toward one narrow
  K-pop beauty template. Build a distinctive human face first; add group,
  performer, wardrobe, or idol context only after the face structure is locked.
- When the founder asks for a less mature early-20s result, use the model-facing
  phrase `beautiful girl in her early 20s`. In that mode, do not put `adult`,
  `woman`, or negative age phrases into the model-facing prompt; carry safety in
  internal notes and use positive structure controls instead.
- Keep named public, private, or underage people out of identity targets; build
  an original fictional identity from current morphology controls. Source images are function references only.
- Model-facing prompts use current character names, morphology labels, and selected style functions instead of source-person names, source filenames, or third-party identity labels.
- Exclude minors and minor-risk sources from face morphology sourcing. If a
  minor-risk source is useful, carry only non-face abstract functions such as
  clean rookie brightness or soft styling energy.
- Do not promote generated faces into `assets/members/**`, catalog registries,
  public-facing text, or release material without founder approval.
- Do not use `Unreal`, `MetaHuman`, `3D render`, `CG`, or similar terms in the
  model-facing prompt unless the founder explicitly asks for a non-photographic
  render test.

## Required Reads

Read this `SKILL.md` completely before using the skill.

Read `references/openai-image-prompt-contract.md` before compiling an OpenAI
image generation or image edit prompt.

Read `references/photoreal-human-face-control-taxonomy.md` before writing a
numeric control sheet, translating old MetaHuman-style controls, or deciding
which face details to carry from legacy Jellobus material.

Read `references/founder-face-source-function-bank-v1.md` before building a
multi-person face set from the founder-supplied 23-image morphology analysis.
This reference converts those sources into reusable identity-separation face
architectures and generation guards.

If the task touches repository placement or durable member assets, also read
`AGENTS.md` and `wiki/artifact-management-system.md`.

## Output Boundary

Keep outputs under the current run or explicit assignment owner:

- Face research: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/*face-lock*.md`
- Control sheets: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/*face-lock*.yaml`
- Generated reviews: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/*face-lock-review*.md`
- Generated images: the run-owned `generations/` or explicit assignment output
  folder
- Durable identity assets: the relevant `assets/members/**` path only after
  founder approval

Do not write into `젤로버스/**` unless the founder explicitly returns to that
isolated assignment.

## Workflow

1. **Intake sources as functions**
   - Record source paths, URLs, or founder-supplied labels in research notes.
   - Mark each source as `founder_supplied`, `public_function_reference`,
     `generated_candidate`, or `identity_lock`.
   - Write allowed use as function/category only, not likeness.
   - Extract observable face functions: outline, eye-orbit behavior, nose and
     midface planes, mouth and philtrum behavior, cheek/jaw/chin path, hairline
     frame, skin/lens/light evidence, and expression tissue.

2. **Choose a human identity strategy**
   - Pick one primary face architecture.
   - Pick one dominant structural memory point.
   - Pick two secondary memory points.
   - Pick one intentional deviation from generic idol averaging: face length,
     cheek/jaw path, nose z-plane, mouth/philtrum behavior, eye-orbit type,
     hairline frame, or asymmetry must be clearly different from the others.
   - Pick two to five non-mirror topology locks across eyes, nose, mouth or
     philtrum, cheek/jaw/chin, and hairline.
   - Pick two real-photo evidence locks.
   - Pick one age-read strategy and one anti-template guard.
   - Do not choose the same "small nose + large almond eyes + soft V-line" face
     recipe twice in one candidate set.

3. **Build multi-person face sets**
   - For 5 or more candidates, spread the set across face outline families,
     eye-orbit families, nose/midface z-planes, mouth/philtrum behavior, and
     hairline/frame topology.
   - Each candidate must have a different dominant memory point. Styling,
     hair color, makeup, or outfit cannot be the dominant memory point.
   - If two candidates both use large eyes, separate them by eye openness,
     lid height, lower-lid volume, face length, mouth size, nose z-plane, or
     cheek/jaw path.
   - If two candidates both use a V-oval or compact face, separate them by
     midface length, chin endpoint, jaw width, mouth pressure, hairline
     asymmetry, or nose/base projection.
   - Keep every prompt source-name-free and identity-separation. Do not ask the model
     to copy a supplied source image or public figure.

4. **Write internal controls**
   - Use 0-10 controls only as an internal planning layer.
   - Every active numeric control must include `prompt_translation`,
     `realism_guard`, and `overuse_risk`.
   - Translate numbers into visible face language before prompt compilation.
   - Never send naked numeric controls to the image model.

5. **Compile the OpenAI image prompt**
   - Follow `references/openai-image-prompt-contract.md`.
   - Use a skimmable prompt order: goal/use, scene/background, subject, face
     identity, non-mirror topology, photoreal evidence, framing/camera,
     preserve/change constraints, exclusions.
   - Include `photorealistic` or `real photographed portrait` directly.
   - For early-20s tests, write `beautiful girl in her early 20s` in the subject
     line and make the youthful read through structure: shorter lower face,
     soft full cheeks, lower softer brows, large but anatomically socketed eyes,
     compact nose and mouth scale, and real nose/lip/chin/jaw shadows.
   - For early-20s tests, avoid age-negating prompt language. The YNG test set
     improved because `adult`, `woman`, and explicit negative youth phrasing
     were removed; those words had been pulling the output toward a 30s read.
   - Keep API settings such as model, size, quality, background, and
     output format outside the model-facing prompt.

6. **Generate standalone first**
   - Generate one standalone identity portrait per person before group sheets.
   - Keep camera, crop, lighting, clothing, and background comparable across
     candidates unless the task is testing a specific camera angle.
   - Use group/contact sheets only for comparison after standalone candidates
     exist or when the founder explicitly wants a quick board.

7. **Review and iterate**
   - Review the actual image, not the prompt intent.
   - Record what matched, what drifted, exact next deltas, and reject-if gates.
   - Change only a few controls per iteration unless the face collapses into a
     generic template.
   - If the face resembles a real source, move away from that source family
     before polishing beauty.

## Prompt Compile Order

Use this model-facing structure after controls have been translated:

```text
Goal/use:
Create one photorealistic real-camera identity portrait of a single original
fictional person for face-lock review. Build the face as a distinctive real
person first; do not default to an idol beauty template.

Scene/background:
[Plain studio, neutral editorial wall, outdoor street, or other controlled
background. Include lighting direction and color limits.]

Subject:
[Age phrase, face orientation, gaze, expression, and head/neck/shoulder read.
For early-20s tests, use "beautiful girl in her early 20s". Add idol context
only if explicitly required for this iteration.]

Face identity:
[Face architecture, dominant memory point, secondary memory points, eyes,
nose/midface, mouth/philtrum, cheek/jaw/chin, hairline/face frame.]

Non-mirror topology:
[Two to five named differences across eyelids/lower lids, nose axis/base,
mouth corner/philtrum, chin/jaw endpoint, and hairline/strands.]

Photoreal evidence:
[Skin texture, under-eye tone, pores, cheek sheen by plane, natural catchlights,
flyaway hairs, real lens compression, nose and lower-lip shadows.]

Framing/camera:
[Portrait crop, eye-level or angle, 70-85mm portrait-lens feel or equivalent
high-level camera look, distance, background depth.]

Preserve/change constraints:
[For edits, say "change only X" and list identity, face, expression, hairstyle,
pose, camera, lighting, and background details to preserve.]

Avoid:
copied face, named-idol resemblance, private-person likeness, anime eyes, glass
eyes, wax skin, perfect symmetry, generic K-pop average face, small-nose-large-
eye idol average, flat nose, stamped glossy lips, distorted anatomy, text, logo,
watermark.
```

For early-20s "beautiful girl" prompts, keep the `Avoid` line age-neutral. Do
not use negative age wording there; make the intended age read through the
positive subject phrase and facial structure controls.

## Minimum Control Packet

```yaml
status: draft
run:
stage: photoreal_human_face_lock
source_refs:
allowed_use:
  source_policy: function_only_not_likeness
  model_prompt_source_names: forbidden
identity_strategy:
  primary_architecture:
  dominant_structural_memory_point:
  secondary_memory_points:
  distinctiveness_pressure:
  age_read_strategy:
    model_facing_age_phrase:
    internal_safety_guard:
    prompt_terms_to_avoid:
    youthful_structure_controls:
  anti_template_guard:
controls:
  face_outline:
    face_length_y:
      score:
      prompt_translation:
      realism_guard:
      overuse_risk:
  eye_orbits:
  nose_midface:
  mouth_philtrum:
  cheek_jaw_chin:
  hairline_frame:
  skin_lens_light:
non_mirror_topology:
  - zone:
    prompt_translation:
real_photo_evidence:
  -
prompt_ready_summary:
reject_if:
  -
```

## Review Rubric

Score each generated candidate from 0 to 5:

- `human_photorealism`
- `identity_distinctiveness`
- `face_shape_distinctiveness`
- `structural_memory_survival`
- `non_mirror_topology_survival`
- `skin_lens_light_realism`
- `age_read_fit`
- `early_20s_youthful_read` when the founder asks for "beautiful girl" mode
- `idol_homogenization_resistance`
- `non_likeness_to_sources`
- `prompt_delta_clarity`

Failure rules:

- If `non_likeness_to_sources` is below 4, move away from the source family
  before improving beauty.
- If `age_read_fit` is below 4, fix face proportion, jaw/neck read, styling,
  and camera before changing eyes.
- If `early_20s_youthful_read` is below 4, reduce 30s drift by shortening the
  lower face, softening cheek/jaw planes, lowering brow intensity, reducing
  heavy glamour styling, and keeping real z-depth in eyes, nose, lips, and chin.
- If `skin_lens_light_realism` is below 3, add local skin variation, lens
  compression, and face-plane shadows before adding makeup or polish.
- If `non_mirror_topology_survival` is below 3, name exact eye, nose, mouth,
  chin, and hairline differences instead of generic asymmetry.
- If `identity_distinctiveness` is below 3, reduce active traits and make one
  structural feature dominant.
- If `face_shape_distinctiveness` or `idol_homogenization_resistance` is below
  3, stop polishing and rebuild the face architecture away from the idol
  average before generating again.

## Review Template

````markdown
status: draft
run:
stage: photoreal_face_lock_review
source_refs:
generated_outputs:

# Photoreal Face Lock Review

## Candidate

Path:

Status:

## Matched

-

## Drifted

-

## Pass / Fail Gate

```yaml
human_photorealism:
face_shape_distinctiveness:
structural_memory_survival:
non_mirror_topology_survival:
age_read_fit:
early_20s_youthful_read:
idol_homogenization_resistance:
non_likeness_to_sources:
```

## Next Deltas

- control:
  from:
  to:
  prompt_translation_change:
````
