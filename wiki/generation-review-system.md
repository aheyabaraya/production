# IDOL Generation And Review System

This page summarizes the active 02A -> 02B -> image -> review -> 03V route.
Creative authoring detail lives in `skills/idol-generation/SKILL.md` and
`skills/idol-video-prompt/SKILL.md`.

## Design Goal

The system lets the Founder lock a strong Front Planning spine and then delegate
professional expansion. It optimizes quality first, then local revision speed
and context efficiency.

Graph Engineering never creates images to complete a form.

## Active Contracts

| Artifact | Version |
|---|---|
| 02A master storyboard | `idol_master_storyboard.v3.0` |
| 02B section delta | `idol_prompt_packet_delta.v1.6` |
| 02B canonical packets | `2.6` |
| image request | `idol_image_generation_request.v12` |
| image execution receipt | `idol_image_generation_execution_receipt.v4` |
| image render correction | `idol_image_render_correction.v8` |
| 02B context pack | `idol_harness_context_pack.v7` |
| generated Branch review | `idol_generated_branch_cut_review.v4` |
| typed Production Cut review | `idol-production-cut-review.v2` |
| Audio Production-Cut Placement | `idol_audio_production_cut_placement.v5` |
| 03V storyboard assist | `idol_video_prompt_storyboard_assist.v4` |
| 03V prompt manifest | `idol_video_prompt_manifest.v8` |
| HTML review | `idol-html-review-board.v12` |

No active compatibility branch is created. Graph v2 CDD routing is
shadow-only until the verified default-switch receipt. After that boundary,
each P3-Ci/V-Ci pair owns one roster-derived contiguous two- or three-section
cohort, while section workers remain bounded execution owners below the CDD.

## 02A Storyboard

01 owns the Official Core Storyboard and exactly one passed primary image per
Core. 02A imports those Core bytes unchanged, then adds as many ordered Branch
Cuts as the song and screen plan require.

A core cut is the parent major event, action, effect, condition, or dramatic
beat and may span several framed screens. Each core cut owns `1..N` branch cuts.
It also records the governing camera position/axis and full anchor view, then
maps one distinct camera role to every ordered Branch Cut.

The anchor is not a repeated default shot. The review checks that broad
variation remains possible and that any height, distance, direction, angle,
axis, depth, placement, crop, lens, or viewpoint departure adds information
while preserving or explicitly resetting continuity.

Each branch cut binds:

- derivation from its parent core event;
- a distinct observable screen contribution;
- exact visible state and action/hold;
- still-camera height, distance, direction/angle, and depth;
- placement, crop, negative space, light, and material;
- current-title member visual first only when meaningful;
- governing scene or sequence reference;
- supporting component reference when the screen job needs it;
- continuity and expected output.

Temporal camera motion does not belong in 02A.

## Visual Package And Reference Roles

Current-title assets live under:

```text
assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**
```

Every album/title builds and Founder-reviews its current-title member visuals in
Front Planning; passed member visuals are appearance inputs only when the member
is meaningfully visible. The scene/world comes from the governing scene or
sequence reference and optional supporting component reference in one combined
attachment order, never a separate downstream background package. INK and prior
albums are not reusable looks or silent fallbacks.

Face-only is the sole approved facial-identity source for member-visual builds
and registered identity-input requests. After the current-title card passes,
there is no separate downstream face-only input lane. Retired `no-mic`/`no_mic`
variants are invalid. A member visual controls appearance continuity and never forces face visibility/readability, frontal view/gaze,
pose, crop, still camera, or proportion.

Sequence sheets establish ordered flow. A selected cell/crop becomes its own
scene-reference file and SHA-256. Direct scene/sequence use preserves action,
staging, still-camera geometry, placement, crop, and ordered grammar.

## 02A Review

The Founder reviews:

1. target/message;
2. whole-video/section flow;
3. section;
4. core cuts, including governing camera anchor and Branch Cut camera roles;
5. branch cuts.

The board shows exact input references and title assets. PASS/HOLD/REJECT routes
to the matching smallest owner.

## 02B Translation

One assigned human or model translates one passed Cut in the exact declared
`fp_hero_core|official_core|official_branch` mode into:

```text
Identity reference rule:
Scene intent:
Visible details:
Action cue:
Avoid:
```

This structure is fixed. The content is natural render prose, not copied schema
fields.

Before authoring, the assigned human/model inspects the exact named
Hero/Core/Branch Cut, every bound current-title asset, and every selected
reference derivative. The v1.5
delta receipt exact-copies that hash and input order. `Visible details` internally
separates background/space, detailed still camera/composition, and
light/color/material. `Action cue` separates subject state/pose, visible
action/hold, and object/environment response.

The prompt must:

- preserve the owning Front Planning Hero, 01 Official Core, or 02A Branch
  action, still camera, composition, title identity, reference grammar, and
  combined attachment order;
- include `4K`, `high quality`, and `high detail`;
- omit ids, paths, hashes, schema/process terms, approval text, and temporal
  camera motion;
- avoid ambiguous production phase words;
- avoid accidental frontal-face and portrait bias.

## Section Compilation

One physical 02A section becomes one noncanonical 02B section artifact. That
section is reviewed before the next. Only passed sections merge into canonical
2.5.

The compiler validates receipts/components, exact-copies bindings, and
serializes fixed labels/separators around already-authored values. It never
claims inspection or fills, repairs, pads, or paraphrases creative truth.

## Bounded Context

One prompt author receives:

- compact whole-video invariants;
- full current branch cut and parent core cut;
- immediate previous/next branch cut inside the same core cut;
- immediate previous/next core cut in the same section;
- current-section title assets;
- selected bindings and hashes.

Another section's detailed cuts, prompts, and raw reference pool are excluded.

## Image Execution

One request owns one packet. The request preserves:

- exact five-item prompt hash and fixed five-line serialization;
- expected output path;
- combined visual attachment order;
- current-title and scene input hashes;
- section ownership;
- current-job approval state.

OpenAI uses `gpt-image-2`. No local export, manifest, or request implies paid
approval.

## Production Cut Review

Each result records:

- exact 02A/02B lineage;
- run-owned path and SHA-256;
- dimensions;
- observable pixel truth;
- member-visual result;
- scene-reference result;
- still-camera result;
- body/object integrity;
- section continuity/repetition;
- Founder decision.

The typed `idol-production-cut-review.v2` exact-covers G-40 order by joining
01's passed Official Core primary images with the current generated Branch
review. Only its passed `official_core|branch` rows enter Audio Production-Cut
Placement.

## Audio Production-Cut Placement

Placement maps actual passed pixels to song timing. It states subject/object
transition need and continuity while leaving camera motion unassigned.

## 03V Boards

One to three passed `official_core|branch` Production Cut images form a board.
One image is valid when it is a sufficient motion anchor with an authored
reason and temporal route; it is not restricted to a static hold or insert.
More than three split into linked boards.

```text
@image1 board
@image2 original 1
@image3 original 2
@image4 original 3
```

Board = timing, blocking, subject route, temporal camera.
Originals = pixels, appearance, wardrobe, light, composition, states.

03V authors camera motion after pixel inspection and validates playback before
04.

## Choreography

Only `primary`/`supporting` sections use choreography, with an actual
choreography/performance/fancam source. 02A derives ordered body states; 03V
preserves the phrase between passed frames.

## Local Patch Table

| Problem | Patch |
|---|---|
| anatomy/material/pixel defect | exact image |
| wording without screen-truth change | exact 02B packet |
| branch-cut action/still composition/input selection | exact 02A branch cut |
| Official Core event/image | exact 01 Official Core |
| Branch roster | exact 02A imported Core compile seed |
| section scene/reference/still-camera grammar | 01 section |
| target/message/title/member/section spine | Front Planning |
| subject/camera motion | 03V board/cue |
| assembly/timing only | 04 |

## Validators

```text
ruby scripts/validate_master_storyboard.rb PATH
ruby scripts/validate_02b_imagegen_contract.rb PATH
ruby scripts/validate_generated_branch_cut_review.rb PATH
ruby scripts/validate_audio_branch_cut_placement.rb PATH --require-ready
ruby scripts/validate_video_prompt_storyboard_assist.rb PATH
ruby scripts/validate_video_prompt_manifest.rb PATH
```

Machines validate transport; the director and Founder judge creative quality.
