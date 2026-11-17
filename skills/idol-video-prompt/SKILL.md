---
name: idol-video-prompt
description: "Use after passed Official Core/Branch Production Cut images to author active 03V Motion Storyboards, exact video prompts, one-frame or Founder-selected multi-reference execution, and 480p-to-720p CDD playback handoff."
---

# IDOL 03V Motion And Camera Director

This skill is the motion director, video cinematographer, and image-to-video
prompt writer. It begins after actual generated pixels pass. It does not rewrite
still-image appearance, Front Planning, 01, 02A, or 02B.

Audio placement and 03V remain separate artifacts but share this one
post-pixel motion-director owner. Placement decides which passed image states
belong to each audio interval; only the following 03V step authors temporal
camera movement.

## Required Reads

`automation/harness-skill-load-profiles.yaml` is the sole static profile-body
source. Keep one physical section lineage and select the exact checkpoint:

- `section_03v_audio_placement` reads the generated-image review and
  Audio Production-Cut Placement schema;
- `section_03v_motion_direction` additionally reads the storyboard-assist and
  video-prompt-manifest schemas plus
  `references/video-prompt-authoring-detail.md`,
  `references/storyboard-assisted-branch-cuts.md` and the registered common
  camera vocabulary;
- `section_03v_playback_review` reads the exact manifest, rendered clips, and
  review schema without reopening upstream authoring modules.

Each checkpoint reads the registered AGENTS, policy, and Department Dispatch
subset named for that checkpoint. Exact passed images, 02A/02B lineage,
placement, prompts, clips, and playback evidence are hash-bound current-section
inputs. Omitted neighboring phases are not inferred; a missing or stale
checkpoint/input is a HOLD.

## Active Contracts

- passed Production Cut review: `idol-production-cut-review.v2`
- Audio Production-Cut Placement: `idol_audio_production_cut_placement.v5`
- storyboard assist: `idol_video_prompt_storyboard_assist.v4`
- video prompt manifest: `idol_video_prompt_manifest.v8`
- common 03V authoring source pack: `idol_03v_authoring_source_pack.v5`
- optional Grok projection:
  `idol_grok_video_prompt_reference_pack.v7`

There is one active Motion Storyboard attachment grammar. Direct I2V before
passed 03V is forbidden. After passed 03V, default execution uses exactly one
passed Official Core or Branch still as frame 1.

## Start Gate

03V starts only when:

- 02A and canonical 02B validate;
- the 02A master storyboard exposes a valid complete PRE-00-rooted
  full-storyline lineage projection;
- every selected image has a passed pixel review and live hash;
- Audio Production-Cut Placement is `ready_for_03v` or `passed`;
- current section ownership is exact;
- any active choreography has an actual bound source.

Preparation does not authorize paid/external generation.

Before any subject or camera motion authorship, exact-project and read the
complete lineage: immutable PRE-00 original, active full text, every PRE-00/FP
revision, contextual density review, and reference-function receipts. Motion
expands that source. `whole_film_spine`, board summaries, and current cue prose
cannot replace it.

## Audio Production-Cut Placement

Placement maps actual passed `official_core|branch` Production Cut images to selected audio. It records timing,
observable state, subject/object transition need, continuity, choreography
policy, and future edit marker basis.

It does not author camera motion. Do not smuggle a camera route into placement.

## Storyboard Board Standard

One to three ordered passed `official_core|branch` Production Cut images form
one board under one active storyline passage and selected Sequence Composition
and flow. The 02A full-storyboard camera-angle review remains the collection unit:
every distinct Official Core primary and generated Branch still, including
non-adjacent and cross-packet pairs. A 1--3 image 03V packet is not a
sufficient scope. Camera angle is facing-and-pitch (`direction_angle` /
Core `camera_angle`), not `shot_scale_distance` and not height-only. The
same Cut id or pixel SHA-256 is not a second image. Keep 02A distinct-screen
job: angle diversity is additional, never a substitute. One-image boards
stay legal with `one_image_board_reason`. Do not promote Sequence frames
into extra cuts.
The selected Sequence binding exact-carries its reviewed Sequence Motion
Analysis binding through the board, 03V source pack, and v8 manifest. Validate
the analysis path/SHA, candidate row pointer/value SHA, and independent final
CDD DDC review bytes; never accept pre-copy-only evidence or a nonselected
candidate. Treat observed source events and inferred opportunities as planning
support only. Final subject/environment/camera route, speed, envelope, stop,
and landing remain 03V authorship after the bound Production Cut pixels PASS.
Same-parent Core is the default; a cross-Core transition must name both Core
IDs and a continuity reason. More than three necessary screens split
into linked boards. A one-image board is a normal route when that Production Cut is a sufficient
motion anchor; it must state why one anchor is enough and what temporal
subject/environment/camera route 03V will author from it.

The binding is fixed:

```text
@image1 = storyboard board
@image2 = first original passed Production Cut image
@image3 = second original passed Production Cut image
@image4 = third original passed Production Cut image
```

Only slots with actual frames are named.

The storyboard board controls:

- ordered timing;
- blocking;
- subject/body/object route;
- temporal camera movement.

The original Production Cut images control:

- pixels and member appearance;
- wardrobe and materials;
- light and color;
- still composition and crop;
- visible start/intermediate/end states.

Board labels, arrows, borders, padding, or panel layout never appear in the
generated video.

## Board Authoring Method

For each board:

1. inspect every original Official Core/Branch image at pixel level;
2. read its audio placement plus the generated review's `observable_pixel_truth`,
   `still_camera_result`, section `continuity_observation`, and upstream
   motion-readiness need;
3. decide whether the states form one coherent video cue;
3a. confirm each packet image is already in the 02A
    `collected_image_camera_angle_review` distinct-image roster; inspect the
    actual pixels against that full-storyboard review;
3b. if the full collection is missing a pair, missing pixel/geometry
    bindings, or a Founder exception that does not exact-bind a real lock,
    HOLD and return to the smallest still owner;
4. author the observable subject/object/environment transition;
5. compare the passed pixels against the reserved axis, room, layers, path,
   crop safety, and edit carrier, then author temporal camera motion from the
   actual start view;
6. verify reference-bound choreography where active;
7. write the board image with one clean ordered panel per source frame;
8. bind `@image1` and originals in exact order;
9. link previous/next boards;
10. record a hold when the pixels cannot support the desired bridge.

Do not add an invented intermediate action merely because a board has space or
because only one branch-cut anchor was supplied.

## Subject Motion

Describe:

- visible start trigger;
- body, object, environment, or intentional-hold route;
- timing against the audio cue;
- pass-through state when present;
- target visible state;
- contact, collision, cloth/hair/object reaction when relevant;
- continuity into the next board.

Use concrete verbs and geometry. Do not write only “energy rises” or “the space
reacts.”

## Temporal Camera Motion

03V owns camera movement because actual pixels now exist. State:

- start view inherited from 02A/02B pixels;
- movement family or positive locked-camera hold;
- direction;
- rig/motion character when it changes the result;
- speed;
- acceleration/deceleration or motion envelope;
- motivation;
- depth change and parallax;
- reveal target and stop trigger;
- readability reason;
- edit handoff.

Upstream motion readiness is a feasibility boundary, not a command. Preserve
the passed action axis, screen direction, lead/reveal room, layer order,
path/occlusion, crop safety, and continuity carrier when they remain supported
by the actual pixels. If a proposed route would invent an unseen rear world,
cross the axis accidentally, crop protected identity/action, or require a
missing depth layer, select another evidence-supported route or return to the
smallest upstream owner.

Treat the Generated Branch-Cut Review as pixel evidence, not a motion command.
03V may choose among the broad families the pixels support, but it may not
overwrite an observed broken carrier, unsafe crop, missing layer, or unseen
space with optimistic prompt language. A review-marked unsupported family
requires another route or the exact upstream HOLD.

Keep one coherent camera cue. `pan`, `truck`, `dolly`, `zoom`, `arc`, `orbit`,
`tilt`, `pedestal`, `rack focus`, and rig terms are not interchangeable; use
the common vocabulary's physical definitions and state the observable result.

Vary movement only when the song and scene justify it. A locked hold is a valid
route. Do not mechanically push in on every face or orbit every performance
frame.

## Non-Prescriptive Teaching Example

This example teaches how to choose a 03V motion carrier. It is not canonical
scene or prompt text.

For a Founder note such as `make this beat more dynamic`, first compare the
current audio cue, passed pixels, selected reference grammar, and adjacent-board
continuity. Then test materially different carrier families:

- subject-led change, with the camera protecting action readability;
- camera-led change, only when the inherited composition and depth can support
  it without losing the subject;
- environment-, object-, material-, or light-led change, while subject and
  camera may stay restrained;
- an intentional hold, when withholding motion gives the next beat more force;
- another carrier indicated by the current evidence.

Select one route or a reasoned combination from that evidence. Only then author
the exact movement family, direction, speed, motion envelope, depth behavior,
stop trigger, and edit handoff for the active board.

Use this output skeleton to check the translation:

```text
[current trigger] -> [selected motion carrier] -> [observable route] ->
[camera response] -> [stop/readability condition] -> [edit handoff]
```

The bracketed terms are roles to fill from the active section. They are not a
prompt, preset, required move list, or quota.

## Choreography

Choreography appears only for `primary` or `supporting` cues with a bound actual
choreography, performance, or fancam source. Preserve the inspected body phrase
and timing readability. Do not invent generic dance.

`minimal_body_gaze_hold_guard` may animate only the necessary acting/body
evidence. `absent` does not introduce choreography meaning. Contextual review
judges whether the prompt invents choreography; a token or negative phrase
alone is not a pass/fail signal.

## Generator-Facing Prompt

Authoring/review `prompt_handoff` uses `@image1` plus every original slot present on that board. The final generator-facing execution prompt is a separate immutable artifact. Name only slots the selected tool will receive: default `image_to_video` attaches one still, addressed as `@image1`; Founder-selected `reference_to_video` attaches two or three stills as `@image1` plus `@image2`/`@image3`. Do not name unattached slots. Do not rewrite a passed execution prompt to drop slots; HOLD.

The authoring/review prompt records:

- board authority;
- original-frame authority;
- subject motion;
- temporal camera route;
- pacing and stop;
- continuity and edit handoff;
- necessary negatives.

One useful motion-sentence flow is shown below. It is optional; the assigned
author chooses the wording and order that make this cue executable:

```text
[inherited start view] + [start trigger] + [subject/object/environment motion
or intentional hold] + [one camera movement/hold family and direction] +
[speed/envelope] + [depth/parallax or focus behavior] + [reveal/stop] +
[readability protection] + [continuity/edit handoff]
```

Start with the essential motion and add only what removes ambiguity. Prefer
positive physical wording such as `the camera remains locked` over a
negative-only instruction. For a large change, describe what becomes visible
through the phases instead of stacking several technique names.

Keep ids, paths, hashes, schemas, approvals, process text, and internal
checklists outside the prompt.

Do not inventory appearance already locked by the original pixels unless an
observed drift requires a minimal correction.

## Section Ownership

This skill is the second half of the fresh post-02A provider-resolved
`section_image_motion_worker / worker_high` lineage opened for exactly one
physical section. The session validates the
exact approved 02A checkpoint, completes 02B/generation/pixel review under
`idol-generation`, returns exact pixels to CDD review, and then resumes the same
checkpoint here. It never inherits a pre-02A development chat,
loads another section, or opens a replacement session merely to rewrite a
prompt.

One physical section owner may author several boards in its section. It never
merges canonical whole-video bytes. The coordinator reviews whole-video camera
progression and repetition after section shards pass. A Department Dispatch
return records the exact section result and 03V handoff or hold; it does not
grant canonical promotion or Founder approval.

Past-run prompts, test fixtures, and graph-engineering examples are not motion sources.
The section's passed pixels, placement, board, selected audio, and bound
references must author the subject route and camera movement. Shared guidance
defines the questions and attachment grammar, not a reusable move, framing, or
shot sentence.

## Common Source Pack

Prepare the exact active source pack with:

```text
ruby scripts/idol_prepare_video_prompt_authoring.rb RUN_ROOT --write
```

The script validates and projects sources only. It does not author camera or
prompt prose. Its active manifest must carry the exact full-storyline value and
hash from the 02A master storyboard.

Optional Grok handoff requires an existing active source pack and explicit
Founder request:

```text
ruby scripts/idol_prepare_grok_video_prompt_handoff.rb RUN_ROOT \
  --source-pack PATH_TO_WRITTEN_SOURCE_PACK \
  --founder-requested --write
```

The handoff remains local and does not approve external execution.

## Video Execution Contract

Passed 03V prompt bytes are immutable execution input. The adapter must use
`prompt_rewrite_policy: forbidden`, exact prompt SHA-256, pinned provider/auth/
profile/version, and `automatic_fallback: none`. A final execution prompt that
names an unattached `@image` slot is HOLD; do not rewrite the passed bytes.

- Default `image_to_video`: exactly one passed `official_core|branch` still,
  `source_image_frame_count: 1`.
- Conditional `reference_to_video`: only the board's ordered actual originals
  named by a Founder-authored exact image-ID/order selection receipt. Missing
  receipt is HOLD, never silent downgrade to one-frame I2V.
- Duration is exactly 6 or 10 seconds. Resolution is exactly 480p or 720p;
  1080p is rejected.
- Direct execution without passed 03V is forbidden.
- `scripts/idol_media_execution_adapter.rb` remains the mandatory local dry-run
  projection/package surface and performs no external or generative call.
  For a Founder/operator handoff it may, only with explicit
  `--write-package --package-root`, materialize unchanged `prompt.txt`, one
  passed Production Cut for `image_to_video` or the exact Founder-ordered two
  to three passed cuts for `reference_to_video`, and a hash-bound
  `package-plan.json`. The package retains provider/readiness HOLDs and is not
  generation approval. When the exact physical section owner resolves to the
  active Grok lane, that same Grok session may invoke only its registered
  `image_to_video` or `reference_to_video` provider-native tool after current
  session inventory/adapter preflight and cue-specific Founder external
  generation authority. A missing tool, mismatched provider, or missing
  authority holds that cue without borrowing Codex/xAI tools or auth. Returned
  clips re-enter only through the registered 03V importer, intake, and CDD
  playback-review route.

## Playback And 04 Boundary

Generate/review 480p first. After the verified Graph v2 switch, the owning V-Ci
Section-Cluster CDD reviews actual playback for its exact two- or three-section
cohort. Until that switch, the pinned legacy CDD owns the same review boundary.
It judges:

- pixel/identity stability;
- subject motion;
- camera route;
- choreography fidelity when active;
- temporal artifacts;
- section continuity;
- endpoint and edit handoff.

Only a CDD-passed 480p playback may open the same `video_job_id` as a 720p
candidate. The 720p candidate receives a separate playback review; resolution
increase is not creative PASS. Every receipt records requested and observed
resolution. Any mismatch is `resolution_fallback_hold` and cannot be promoted.

04 begins separately only after passed playback. 03V completion does not imply
edit readiness.

## Local Revision

- Board panel or binding defect: patch the board/assist artifact.
- Subject or camera motion defect: patch exact 03V cue.
- Pixel defect: return to the exact generated Official Core/Branch image.
- Still composition or visible state defect: return to the exact 01 Official
  Core or 02A Branch
  or 02B packet as appropriate.
- Section direction/reference change: return to 01.
- Target/message/title identity change: return to Front Planning.

Every 03V package or HOLD returns only to the owning Creative Development
Director: V-Ci after the verified Graph v2 switch, or the pinned legacy CDD
before it. That CDD reviews exact Motion Storyboard bytes and actual playback,
routes the smallest affected scope to its P3-Ci predecessor or 01/02A when
required, and sends only a reviewed cohort milestone to Overall. This section
owner never bypasses CDD.

## Output Boundary

Write only the current dispatch's exact one-section run-owned outputs:

- Audio Production-Cut Placement;
- storyboard-assist boards and their bound original-frame order;
- 03V prompt manifest and source pack;
- generated video outputs and playback review when execution is authorized;
- the same lineage's checkpoint and Department Dispatch runtime return.

Do not write Front Planning, 01, 02A, 02B, another section, a whole-video merge,
legacy skill-application receipts, or 04 edit truth. A new physical session may
resume only an exact durable checkpoint with unchanged owner, section, prompt,
reference order, and creative state.

## Quality Gate

PASS only when:

- the Department Dispatch, exact section checkpoint, required skills, sources,
  Founder epoch, and output paths all match;
- the lineage is the fresh provider-resolved post-02A one-section owner and does not contain a
  pre-02A chat or another section;
- the v8 manifest exact-projects the complete PRE-00-rooted full-storyline,
  FP17 Major/Sequence bindings, and 01/02A screen-progression lineage, and the
  active full-text raw hash remains valid;
- every board uses 1–3 passed `official_core|branch` Production Cut images, and every one-image board
  states why one anchor is sufficient;
- every packet image appears in the 02A full-storyboard collected
  camera-angle review; 02A planning `generated_pixel_closure` cannot
  satisfy generated-pixel closure; 03V requires the section generated
  pixel review with actual passed hashes; distinct Cut ids and pixel hashes on one packet are
  unique; shot-size-only, height-only, label-only, adjacent-only, random
  rotation, numeric similarity, and machine family-matching cannot PASS;
  same Cut id or pixel SHA-256 is not a new image; unbound Founder-lock ids
  HOLD;
- every source frame is passed and hash-bound;
- the stage-specific 03V playback vector has every applicable grade at least
  3, with subject motion/intentional hold, temporal camera/evidence-based hold,
  and audio/edit landing each at 4; no planning or pixel rubric is reused and
  no averaging can hide a weak item;
- attachment order is exact;
- board and original-frame authority are not confused;
- subject motion is observable;
- camera motion is motivated, specific, and authored after pixel inspection;
- the route consumes the exact Generated Review pixel-support/continuity
  evidence without rewriting a held pixel fact as a prompt assumption;
- the temporal route is physically consistent with the inherited axis, room,
  layers, path/crop safety, and continuity carrier or records the smallest-owner
  return;
- choreography is source-bound or absent;
- section and whole-video camera patterns do not collapse into one direction;
- generator text contains no internal metadata;
- playback, external execution, and 04 remain separately gated.

Validate with:

```text
ruby scripts/validate_audio_branch_cut_placement.rb PATH --require-ready
ruby scripts/validate_production_cut_review.rb PATH
ruby scripts/validate_video_prompt_storyboard_assist.rb PATH
ruby scripts/validate_video_prompt_manifest.rb PATH
```
