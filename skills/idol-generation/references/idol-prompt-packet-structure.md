# IDOL Prompt Packet Structure

Use this reference when creating or reviewing active
`02B-prompt-packets.yaml`.

For detailed prompt compile and Founder/reference-image intake rules, read
`prompt-packet-compile-detail.md`. Historical prompt-packet schemas are evidence
only and are not active authoring inputs.

## Active Flow

The active production order is:

```text
director-proposed Major -> passed or exception-selected album/title visual inputs
-> director-quality-passed Major and assigned-director Key Screen Anchors
-> Founder Direction Alignment
-> internal FP Close and role-routed 01 directorial expansion
-> 01 Official Cores with exactly one passed primary image each
-> 02A immutable Official Core imports with ordered Branch Cuts
-> Founder 02A Final Planning on the exact FP Close + 01 + 02A projection
-> one model-authored five-line packet per named Hero/Core/Branch Cut
-> delta v1.6 structured translation
-> prompt-packet v2.6
-> one generation request and one still per named Cut
-> typed Production Cut Review over 01 Official Core and generated Branch pixels
-> Audio Production-Cut Placement
-> 03V boards made from one to three passed official_core|branch images
```

Front Planning does not pre-author final Core-Cut or Branch-Cut counts. It gives
the section's major event, desired audience response, message/story function,
member/world identity, reference assignment, and whole-video progression. 01
authors the executable Official Core structure and one passed primary image per
Core. 02A imports those bytes unchanged and decides only the executable Branch
structure.

## Core Cut And Branch Cut

A Core Cut owns one governing event, action, effect, condition, or dramatic
beat. It may span several framed screens. It also states the intended
first-time target-viewer read and why the next governing event follows. That
job may be direct message or empathy evidence, or a necessary setup,
complication, reaction, result, intentional withholding, relation, world,
performance, or bridge that makes later evidence legible.

A Branch Cut is one independently framed and generatable realization derived
from its parent Core Cut. It must add distinct observable information or perform
a distinct directorial job while preserving the same event ownership.

Valid reasons to branch include:

- a materially different phase of the same event;
- a new viewpoint that changes what the viewer understands;
- a participant's action or reaction;
- an object, environment, or spatial consequence;
- a meaningful insert, aftermath, reprise, or transition;
- a different still composition needed to reveal the same event.

These are examples, not a fixed taxonomy. A start/end label, a shot-size-only
change, a lens/angle/beauty variation, or a repeated screen that adds no new
information is not sufficient.
When the governing event changes, return upstream for a new Major. When the
event stays the same and the screen reveals it differently, create a Branch Cut.

There is no global cap. One dense section may use many Core Cuts and few Branch
Cuts. Another may use one Core Cut whose spatial effect, participant response,
and aftermath require several Branch Cuts. The song and visible plan decide.

## Packet Ownership

Active 02B uses:

- `schemas/master-storyboard.schema.json` v3.0;
- `schemas/prompt-packet-delta.schema.json` v1.6;
- `schemas/prompt-packets.schema.json` v2.6.

Each active named Cut owns exactly one packet in mode `fp_hero_core`,
`official_core`, or `official_branch`. The Official Branch compile exact-covers
the ordered `compile_seed.branch_cuts[]` roster; Hero and Core modes bind their
owning FP or immutable 01 source pointer instead. Every packet preserves:

- `core_cut_id` and `branch_cut_id`;
- its complete `branch_cut_lock`;
- the parent Core Cut and section ownership;
- the immediately previous and next Branch Cut under the same Core Cut;
- the immediately previous and next Core Cut in the same section;
- current-title member-visual selection;
- ordered scene/reference bindings;
- still-camera geometry and composition;
- continuity into adjacent screen material;
- Founder locks and expected output path.

Another section's cuts, packets, or raw reference pool never enter the packet
context. A script may validate, exact-copy bindings, and serialize fixed labels
around directly authored components. It may not claim inspection or invent a
missing branch, action, angle, composition, or prompt value.

## Required Prompt Shape

Each packet contains exactly five required natural-language prompt items in
this order. Execution serializes them as five fixed labeled lines:

```text
Identity reference rule
Scene intent
Visible details
Action cue
Avoid
```

The labels are fixed transport structure; every creative component is
human/model-authored after inspection of the exact Branch Cut, current-title
assets, and reference bindings. The authoring receipt exact-copies those hashes
and ordered ids.

### Identity reference rule

State which current-title member visuals are attached and what appearance
continuity they control, or explicitly state that none are attached. Member
visuals control appearance, hair, makeup, wardrobe, material, silhouette, and
body continuity only. They never force:

- a readable or frontal face;
- frontal gaze;
- the reference pose;
- camera angle or distance;
- crop, subject placement, or proportions.

Face-only is the sole upstream facial-identity source for member-visual
construction. After the current-title card passes, this packet does not create
a second raw face-reference lane.

### Scene intent

Name who or what is visible, the physical place/object system, the Branch Cut's
dramatic purpose, and its exact visible action or intentional hold. Preserve the
parent Core Cut's event rather than summarizing the whole section.

### Visible details

Author separate `background_and_space`, `lighting_color_material`, and
`still_camera_and_composition` components. The camera object requires:

- camera height;
- camera-to-subject distance or scale;
- camera direction and angle;
- foreground/background depth;
- subject/object placement;
- crop and negative space;
- body, gaze, hands, garment, material, object, and environment facts that
  make the Branch Cut readable;
- lighting and color state when they affect the event.

The camera fields are `camera_height`, `shot_scale_distance`,
`direction_angle`, `depth_design`, `subject_placement`,
`crop_negative_space`, and `lens_feel`. These are required screen truths. The
author must return upstream when one is undecided rather than let a script fill
it from a default. The author also supplies the fixed
`4K, high quality, high detail` component.

### Action cue

Author separate `subject_state_or_pose`, `visible_action_or_hold`, and
`object_environment_response` components. The last may be `null` only when no
response exists. Translate the primary audio or section cue into the exact
visible trigger, change, reaction, or hold. A still may capture setup, release,
expansion, impact, reaction, aftereffect, or another event phase when that phase
is the Branch Cut's distinct screen contribution. Do not paste BPM math,
timecodes, lyrics as explanation, or process labels.

## Action Cue Teaching Pattern

This is a decision pattern, not reusable scene truth. First name the audible or
section trigger, then name the exact body, object, relation, or environment
change visible in this Branch Cut. Different projects may use contact,
expansion, recoil, reaction, suspension, aftermath, or another phase; the
chosen phase must be justified by the parent Core Cut and this branch's distinct
screen contribution.

### Avoid

Carry Branch-Cut-specific drift risks, rejected reference traits, identity or
wardrobe errors, anatomy/render defects, unwanted layout/text, and anything
that would collapse this Branch Cut back into another branch.

Every new or materially resumed prompt contains `4K`, `high quality`, and
`high detail` inside the five authored items. Do not append them at
dispatch.

## Current-Title Member Visuals

Every album/title builds and Founder-reviews new current-title member visuals in
Front Planning. No earlier album package is inherited. A passed member visual
is the appearance base only when the member is meaningfully visible; the
governing scene/sequence and any supporting component remain the scene-world
inputs in the same combined attachment order. There is no independently
promoted downstream background-only package. A Cut-scoped
`scene_visual_package` may carry a `world_look_binding` and a still
`composition_anchor`: reviewers judge those functions separately, then 02B
compiles the compatible pair together with the character input. Attach only
the smallest useful subset for the exact Cut.

- Attach a member visual only when the member is meaningfully visible and it
  controls appearance continuity.
- A hand/body crop may retain its visible member owner without forcing a face.
- A pure object or environment Branch Cut carries no member visual.
- Cross-album member pixels hold unless the Founder selected that exact image
  as a direct scene reference for the current title.
- The member visual cannot erase the Branch Cut's selected action, composition,
  still camera, crop, gaze, or spatial grammar.

## Scene And Sequence References

Every selected scene reference remains bound to its actual path, SHA-256,
selected cell/frame/crop identity, function, preserve/discard rules, inspection
receipt, attachment permission, and order.

`bounded_surface_direct`, `full_scene_direct`, and `sequence_direct` retain the
selected screen grammar appropriate to their strength. In particular, a
Founder-selected full scene or sequence preserves its action/collision,
prop/world effect, body route, expression/gaze, camera geometry, subject
placement, crop/negative space, composition, and ordered scene grammar unless
an explicit lock discards a field.

A whole contact sheet is navigation evidence. Each selected cell or frame is
passed as its own bound path and hash. Missing selection is a hold, never a
whole-sheet fallback.

Selected stills bind only after the media-shaped first-read in
`skills/idol-front-planning-director/references/director-operating-contract.md`
(top-level H2 `## 02B-Shaped Source Observation`) is complete. 02B rewrites each
selected still observation for the current Branch
Cut and current-title member-visual attachment; it does not prompt from a whole
sheet, purpose class, mood sentence, or incomplete observation.

Planning use and execution attachment are separate. A reference can govern the
prompt while remaining `planning_and_prompt_only`. External attachment requires
exact current-job approval and a surface that supports every locked input.

## Direct Prompt Revision

Delta v1.6 may carry one human/model-authored direct prompt revision when render
wording—not creative ownership—is the smallest correct fix.

It must preserve:

- Core-Cut and Branch-Cut ids;
- the complete Branch-Cut lock;
- member-visual set and order;
- scene-reference set and order;
- still-camera geometry and composition;
- Founder locks;
- output path.
- exact authoring-inspection receipt and structured component order.

Changing event ownership, Branch-Cut meaning, member/reference selection,
camera, composition, timing, or output family returns to 02A. The compiler
validates hashes, exact-copies bindings, and serializes only fixed labels and
separators; it never writes or repairs a creative component.

## Generation Request

`scripts/idol_prepare_image_generation_request.rb` derives one
`idol_image_generation_request.v12` from one passed Production Cut packet. The
request preserves:

- exact five-item prompt, fixed five-line serialization, and prompt hash;
- Core/Branch identity;
- current-title member-visual inputs and digest;
- scene-reference inputs and digest;
- combined attachment order and digest;
- the exact provider/auth/profile snapshot from the packet;
- `gpt-image-2` for OpenAI, exact Grok tool selection, or one exact registered
  xAI model/profile binding, always with one output and no fallback;
- one unique run-owned expected output.

The adapter may be `openai_api_gpt_image_2`, `grok_image`, or
`xai_api_media`. If the selected surface cannot accept a locked
input or parameter, hold. Never drop the input, describe it in text, merge
packets, or rewrite the prompt.

Preparing a request performs no upload, paid generation, or approval.

## Review

After generation:

1. move the output into the declared run path;
2. record byte SHA-256;
3. inspect actual pixels;
4. enter the result into Generated Branch-Cut Review;
5. compare all passed branches against the parent Core Cut, section, and whole
   film.

The review must judge:

- whether every branch still expresses its parent event;
- whether each branch adds distinct observable screen information;
- whether phase, viewpoint, participant, object, space, reaction, or aftermath
  choices form purposeful direction rather than random variety;
- whether action, camera, composition, identity, world, and continuity survive;
- whether branches or Core Cuts repeat without a dramatic reason.

These are LLM/director judgments. Scripts validate ids, paths, hashes, order,
exact cover, and output ownership only. They do not score semantic similarity,
variation, or creative adequacy.

## 03V Handoff

Passed `official_core|branch` images enter typed Production Cut Review, Audio
Production-Cut Placement, then 03V. A standard 03V board groups one to three
passed Production Cut images. The board
limit applies per board, never to the section or film.

One-image boards are valid when that image gives a sufficient motion anchor and
the author records the temporal route and reason. Two or three images are
ordinary when the motion bridge needs multiple passed screen states.

## Integrity Checks

Before release to generation, confirm:

- Core/Branch roster exact-cover and ordering;
- structured five-item authorship receipt, fixed five-line serialization, and
  prompt hash;
- observable event, action/hold, still camera, composition, and continuity;
- current-title member visual, governing scene/sequence reference, and
  supporting-component subset in combined order, per-album identity, and no
  separate face or background lane;
- exact scene-reference paths, hashes, selected surfaces, functions, and order;
- one packet, one request, one expected output;
- Founder approval state is not inferred;
- no internal ids, paths, schema labels, approvals, or process prose in the
  render text;
- section and whole-video contextual review cover event fidelity, directorial
  diversity, continuity, and repetition.

Historical prompt-packet and storyboard-board schemas remain archive evidence
only. Active work does not route through them for compatibility.
