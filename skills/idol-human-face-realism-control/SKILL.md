---
name: idol-human-face-realism-control
description: Build original adult idol face systems that read like real people by translating 0-10 MetaHuman-style face scores into prompt-ready visible morphology, memory points, asymmetry locks, and review deltas. Use for independent face identity exploration, portrait prompting, and generated-face review. Use named people only as abstract source-function notes; generation targets remain original.
---

# IDOL Human Face Realism Control

Create an original adult idol face system that reads as a real photographed
person, not an averaged AI beauty template. This skill is independent from any
run-specific or Jellobus face work. It must not depend on previous founder
photos, old generated portraits, or isolated project artifacts unless the
founder explicitly supplies them for the current task.

## Boundaries

- Use this skill for original adult character face design, identity portrait
  prompts, face-lock score sheets, and generated-face reviews.
- Keep named public, private, or underage people out of identity targets; build
  an original fictional identity from current morphology controls. Public figure references may be analyzed only as abstract face-design
  functions and memory-point categories.
- Model-facing generation prompts use current character names and morphology labels instead of source-person names as identity targets.
- Treat minors and minor-risk public figure references as excluded from face morphology
  sourcing. If useful, carry only non-face abstract functions such as fresh
  styling energy, clean profile framing, or rookie brightness.
- Do not promote generated faces into `assets/members/**`, catalog registries,
  public-facing text, or release material without founder approval.

## Required Reads

Read this `SKILL.md` completely before using the skill.

For score translation and prompt compilation, read:

- `references/score-to-prompt-translation.md`

For face memory-point analysis, read:

- `references/face-memory-point-taxonomy.md`

## Output Ownership

Keep outputs in the current run or assignment owner:

- Run-specific exploration: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/*face-realism*.yaml`
- Run-specific review: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/*face-realism-review*.md`
- Durable identity work after founder approval: the relevant `assets/members/**`
  owner path

Do not write into `젤로버스/**` unless the founder explicitly returns to that
isolated assignment.

## Workflow

1. **Intake source functions**
   - Record source names, URLs, or local paths in `source_refs`.
   - Mark whether each source is `public_figure_function`, `founder_supplied`,
     `generated_candidate`, or `identity_lock`.
   - State the allowed use: function/category only, not likeness.
   - Exclude minor-risk sources from face morphology fields.

2. **Choose the identity strategy**
   - Pick one primary face architecture: outline, eye-orbit, nose-midface,
     mouth/philtrum, cheek-jaw, or hairline/face-frame.
   - Pick two secondary memory points.
   - Pick a `non_mirror_topology` map: eye length/crease/lower lid, nose axis
     and tip/base, nose-to-philtrum-to-lip distance, one mouth-corner behavior,
     chin/jaw endpoint, and hairline/face-frame imbalance.
   - Pick two realism points that must break AI smoothness.
   - Pick one adult-age guard.
   - Pick one anti-template guard.

3. **Write 0-10 controls**
   - Use the score sheet from `score-to-prompt-translation.md`.
   - Every numeric value must have a `prompt_translation`.
   - Never compile naked values such as `eye_horizontal_length_x: 7.5` into an
     image-generation prompt.

4. **Translate scores into model-facing language**
   - Keep only the controls that matter for this member.
   - Convert each score into visible facial construction, camera-readable
     shadows, and natural asymmetry.
   - Remove source names from the final model-facing prompt.

5. **Generate separately**
   - Generate one standalone identity portrait per member before any group sheet.
   - Keep camera, lens, lighting, clothing, and background comparable across
     candidates unless the task is a concept look test.
   - Use reference images only when the task explicitly requires image input;
     otherwise rely on text locks and score translations.

6. **Review and iterate**
   - Score the output with the review rubric in
     `score-to-prompt-translation.md`.
   - Record what matched, what drifted, and exact score deltas.
   - Change only a few controls per iteration unless the face collapsed into a
     generic template.

## Prompt Compile Order

Use this order when writing a model-facing prompt:

```text
Create one ultra-photorealistic identity portrait of a single original adult
female idol. She must not resemble any named celebrity reference, idol, influencer, or
minor.

Identity architecture:
[one sentence naming face outline, skull/cheek/jaw balance, and adult age read]

Memory points:
[3-5 prompt-translated features that make this person memorable]

Face construction:
[eyes/orbits, nose/midface, mouth/philtrum, cheeks/jaw/chin/neck, hairline]

Non-mirror topology:
[subtle left/right or z-plane differences in eyelids, lower lids, nose axis,
nose tip/base, philtrum-lip distance, mouth corner, chin point, and hairline]

Real-photo evidence:
[skin texture, under-eye variation, asymmetry, stray hair, lens compression,
z-plane shadows, natural catchlights]

Camera:
[lens, crop, angle, distance, light direction, background]

Avoid:
copied face, named-idol resemblance, underage look, wax skin, perfect symmetry,
generic K-pop template, anime eyes, glass eyes, flat nose, over-smoothed pores,
distorted anatomy, text, logo, watermark.
```

## Minimum Review Rubric

Use a 0-5 score after every generated candidate:

- `human_realism`
- `identity_distinctiveness`
- `memory_point_survival`
- `non_mirror_topology_survival`
- `non_template_face`
- `adult_age_read`
- `celebrity_non_likeness`
- `prompt_delta_clarity`

If `identity_distinctiveness`, `memory_point_survival`,
`non_mirror_topology_survival`, or `non_template_face` is below 3, do not polish
the same prompt. Rebuild the identity strategy first.
