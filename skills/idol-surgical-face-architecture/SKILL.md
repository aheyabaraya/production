---
name: idol-surgical-face-architecture
description: Design, critique, and prompt original photoreal idol character faces with plastic-surgery-style facial morphology axes. Use when Codex needs to prevent same-looking generated faces, diagnose repeated eyes, jawlines, noses, or flat midface depth, build differentiated face-control sheets, or compile concise identity-separation image prompts from detailed surgical/aesthetic analysis.
---

# IDOL Surgical Face Architecture

Create original photoreal character faces by separating beauty from sameness.
This skill is an analysis and prompt-architecture layer: use surgical/aesthetic
face axes internally, then compile only the strongest visible controls into a
short image-generation prompt.

## Boundaries

- This is not medical advice, diagnosis, treatment planning, or a claim about
  any source person's procedures. Use the language as aesthetic morphology for
  fictional face design only.
- Keep named public, private, or underage people out of identity targets; build
  an original fictional identity from current morphology controls.
- Model-facing prompts use current character names and morphology labels instead of source-person names.
- Exclude minors and minor-risk sources from face morphology sourcing. If a
  minor-risk source is mentioned by the founder, carry only broad non-face
  functions such as rookie brightness, clean styling, or fresh screen tone.
- Keep the target face original. Public figure references may be discussed only as
  abstract function references in internal notes.
- This skill does not replace `idol-photoreal-human-face-lock` or
  `idol-human-face-realism-control`. Use it before those skills when the face
  architecture needs stronger differentiation.

## Required Reads

Read this `SKILL.md` completely before using the skill.

Read `references/surgical-face-axis-taxonomy.md` when doing detailed analysis,
building a face-control sheet, or diagnosing why generated faces look the same.

Read `references/compact-prompt-compiler.md` when turning analysis into a
model-facing prompt or iteration delta.

If the task is actual OpenAI image generation or image editing, also read
`skills/idol-photoreal-human-face-lock/references/openai-image-prompt-contract.md`.

## Workflow

1. **Separate beauty from identity**
   - First state the beauty lane: fresh, chic, warm, clear, center-power,
     editorial, or other founder-selected direction.
   - Then state the identity lane: which anatomical axis makes this face
     different from the others.
   - Do not let "pretty" collapse into the same large-eye, small-nose, rounded
     chin recipe.

2. **Pick one dominant surgical axis**
   - Choose exactly one dominant axis: eye-orbit, nose-midface, cheek-jaw-chin,
     mouth-philtrum, face outline, or cranial/hairline frame.
   - Choose two supporting axes.
   - For a multi-face set, make a matrix before prompting. Two candidates may
     share "pretty" or "idol profile" styling, but they must not share the same
     dominant axis and lower-face recipe.

3. **Lock the face in three depths**
   - `front_read`: what the face reads like at a glance from a front portrait.
   - `three_quarter_read`: what changes when depth, nose side plane, cheek
     projection, and jaw angle become visible.
   - `close_detail_read`: eyelid fold, lower lid, philtrum, lip projection,
     chin plane, skin/lens/light cues.

4. **Write internal controls**
   - Use exact morphology words: palpebral fissure width/height, canthal tilt,
     upper-lid fold, orbital depth, radix, dorsum, supratip, tip projection,
     alar base, malar projection, bigonial width, chin height, chin width,
     chin projection, mentolabial fold, and lower-third ratio.
   - Translate clinical terms into visible prompt language before generation.
   - Never send numeric scores or dense surgical jargon directly to an image
     model unless the prompt also explains the visible result.

5. **Compile a compact prompt**
   - Keep 3-5 memory points total.
   - Name one eye difference, one lower-face difference, and one depth cue.
   - Put beauty polish before micro-realism when the founder wants idol-level
     attractiveness.
   - Put anti-average guards in the avoid list: do not reuse the same
     round-almond eyes, compact rounded chin, slim tiny nose, or flat midface.

6. **Review generated outputs**
   - Compare the image against the planned axes, not just whether it is pretty.
   - If eyes repeat, change eye-orbit geometry before styling.
   - If jawlines repeat, change bigonial width, chin width, chin height, or
     chin projection before changing hair.
   - If faces look flat, change glabella/radix depth, nose side planes, malar
     projection, lip projection, and chin plane before adding makeup.
   - If beauty drops, reduce harsh asymmetry and restore lighting, hair, skin,
     lashes, lip color, and flattering camera distance.

## Minimum Face Architecture Packet

```yaml
status: draft
stage: surgical_face_architecture
allowed_use:
  source_policy: function_only_not_likeness
  model_prompt_real_names: forbidden
beauty_lane:
identity_lane:
dominant_axis:
supporting_axes:
front_read:
three_quarter_read:
close_detail_read:
controls:
  eye_orbit:
  nose_midface:
  cheek_jaw_chin:
  mouth_philtrum:
  face_outline_hairline:
depth_locks:
  glabella_radix:
  malar_midface:
  lip_chin_plane:
anti_average_guards:
  -
prompt_ready_memory_points:
  -
compact_prompt:
reject_if:
  -
```

## Output Ownership

Keep outputs under the current run or assignment owner:

- Analysis: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/*surgical-face-architecture*.md`
- Control sheets: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/*surgical-face-architecture*.yaml`
- Generated reviews: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/*face-architecture-review*.md`

Do not promote generated faces into `assets/members/**`, catalog registries, or
public-facing text without founder approval.
