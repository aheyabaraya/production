# IDOL Imagegen Validation Contract

Use this reference when turning validated `02B-prompt-packets.yaml` into image
generation manifests. This is a validation/export structure, not a creative
writing template.

## Active Contract

The active schema is `schemas/prompt-packets.schema.json` v2.6 only. Earlier
packet contracts are historical evidence and are not accepted as active
authoring or execution inputs.

```text
one approved Cut: Planning Hero Core | Official Core | Official Branch
-> one provider-neutral `idol_one_cut_one_image.v1` five-line packet
-> one provider-conditional v12 generation request and one image per packet
-> Codex local contact sheet assembly
-> generated Branch review when applicable, then typed Production Cut Review
```

The image model must not be asked to render storyboards, triptychs, contact
sheets, top-left label blocks, fixed coordinate regions, visible CUT labels,
right reference strips, support panels, local paths, schema text, or process
notes. Those are either retired diagnostics or local review materials.

Founder-approved scene/composition reference images are preserved through the
active Branch-Cut route as ordered `visual_reference_bindings`.
They control camera, space, light, texture, material, motif/object behavior,
and action center; they are not identity inputs, do not replace 02A or 01
creative truth, and do not automatically grant provider upload permission.
Legacy `scene_reference_input` and `api_reference_input_plan` remain readable
provider fields.
Every album/title builds and Founder-reviews a new visual package in Front
Planning. Front Planning album member visuals are the default appearance base;
scene-world truth comes from the Major/Key Screen and exact selected scene
references, not a separate background/world package. Attach the smallest
Cut-relevant set. A member visual never forces
a frontal face, readable gaze, pose, crop, or camera. There is no separate
face-reference lane and no prior-album fallback. A Cut-scoped
`scene_visual_package` is not a fifth reference group: it keeps
`world_look_binding` and still `composition_anchor` as separately reviewed
functions, then compiles them together only after their visual compatibility is
confirmed.

Legacy beat-source sheets and two-frame image jobs are archive-only. Active
generation produces one clean still per named Cut; multi-image sequencing
belongs to 03V Motion Storyboards after individual Production Cut images pass review.

## Approval Gates

- paid image generation requires founder approval for the current run
- paid image generation also requires each packet's founder pre-API review to
  pass against the final compiled prompt hash
- each request carries only the smallest Branch-Cut-relevant current-title
  member visuals plus explicitly bound scene references
- every input keeps its canonical path, SHA-256, declared function, order, and
  exact current-job attachment approval
- a member visual is attached only when a member is meaningfully visible and
  appearance continuity matters; it never forces a readable face or frontal
  composition
- selected scene cells/crops are attached individually; a whole sheet cannot
  substitute for a missing selected surface
- `gpt-image-2` is the only OpenAI image model. If a selected input is not
  supported by the chosen execution surface, hold instead of dropping or
  paraphrasing it
- character boards, moodboards, contact sheets, generated review sheets,
  unrelated assets, and legacy imports are not automatic inputs
- publishing, upload, scheduling, or platform sync is outside this contract

## Required Prompt Fields

The active blueprint/compile interface preserves these concise transport fields
or their exact IDOL equivalent:

```text
identity_reference_rule
scene_intent
visible_details
action_cue
avoid
```

`identity_reference_rule` is the fixed first render-facing label retained by the
active packet contract. It says which current-title member visuals are attached
and what appearance continuity they control, or explicitly says none are
attached. It must not imply a separate face-reference lane, force a frontal
face, or copy a reference pose/camera.
`scene_intent` combines emotion, who, exact place/background, and action.
`visible_details` contains directly authored `background_and_space`,
`still_camera_and_composition` (`camera_height`, `shot_scale_distance`,
`direction_angle`, `depth_design`, `subject_placement`,
`crop_negative_space`, `lens_feel`), `lighting_color_material`, and the fixed
quality literal.
`action_cue` contains directly authored `subject_state_or_pose`,
`visible_action_or_hold`, and an explicit `object_environment_response` or
`null`. It never authors temporal camera movement.

Active v2.6 validates the five canonical outer labels, the structured
human/model-authored components, and the authoring inspection receipt. The
compiler may add only fixed labels, separators, and punctuation. It does not
infer creative adequacy or fill a missing component. Keep long
reference-rendering warnings in `imagegen_guard`, while contextual review
decides whether the authored details make world, camera, action, and material
readable.
When a cut's `frame_subject_mode`, `visual_system_anchor`, 01/02A direction, or
founder review requires space, object state, pressure crowd, route physics, or
world reaction, those screen priorities must remain clear without requiring a
fixed clause order. Face readability must not collapse the packet into a beauty portrait. Preserve the
section's locked subject mix: wide/environment-led frames, object-led inserts,
non-member pressure figures, and member close frames should remain in the
run-approved policy. If no run-local policy exists for a cinematic narrative
section, use the diagnostic anti-face-dominance guard from
`wiki/generation-review-system.md`. Its numeric ranges are warning ranges, not
quotas or targets. For an individual 02B packet, the contextual reviewer checks
that the selected frame type survives and recommends a negative constraint only
when the actual prompt/reference combination has a close-up drift risk; no
keyword is universally required.

Face-only is the sole approved facial-identity source for a member-visual build
and registered identity-input route. Retired `no-mic`/`no_mic` variants must be
rejected before attachment. When an approved adapter attaches multiple images, the prompt may identify
their roles compactly: current-title member visual for appearance continuity,
current-title background/world for scene identity, and selected
scene/composition reference for its exact bounded function. Never call any
input a separate face identity reference. Do not use role wording as permission
to add face morphology, local paths, reference file names, or project asset
details to `full_prompt_text`.

The prompt must not include raw timecodes, internal packet/cut ids or legacy beat ids, source
paths, schema/validator labels, export/manifest labels, contact-sheet prose, or
layout/process text. A prompt may include an `Avoid:` line, but stale terms are
allowed there only as explicit negatives.

Every new or materially resumed prompt must also contain the literal terms
`4K`, `high quality`, and `high detail` inside the model-authored 02B blueprint
and therefore inside the exact compiled prompt hash. The execution request uses
`highest_available` quality and lets the approved adapter choose the maximum
supported dimensions for the locked aspect ratio. Do not add these terms after
02B, rewrite the prompt at dispatch, or lower quality for speed/cost.

## Imagegen Guard

The active v2.6 `imagegen_validation_contract` locks:

- provider-neutral prompt truth; only the OpenAI lane locks model `gpt-image-2`
- highest available quality and maximum supported dimensions for the locked
  aspect ratio
- literal prompt terms `4K`, `high quality`, and `high detail`
- hash-bound inputs selected for this Branch Cut in declared order
- a hold on cross-album pixels unless the Founder selected that exact direct
  scene reference for the current title
- explicit Founder approval before paid generation

The packet and request also preserve anatomy, lighting integration, crop safety,
and prompt-leakage risks through their authored `Visible details` and `Avoid`
truth. These guards may protect execution but cannot rewrite the Branch Cut's
action, still-camera geometry, composition, choreography phrase, world
response, empathy function, wardrobe, or memory value.

For cinematic-realistic lanes, contextual LLM or pixel review must hold or
revise any prompt, generated image, or review board that reads primarily as
concept art, illustration, fantasy-game render, anime, 3D render, or glossy AI
art when the founder asked for a filmed cinematic image. A validator confirms
the declared lane, source, exact-copy, and review coverage only; it does not
search style words to issue the verdict. The corrective action is to restore
live-action set, practical material, camera, lighting, and post-composite
evidence, not to remove the fantasy element.

## Execution Adapters

02B validates one prompt truth. `schemas/image-generation-request.schema.json`
and `scripts/idol_prepare_image_generation_request.rb` project that truth into
an execution request without changing prompt text or reference order:

- `openai_api_gpt_image_2` uses direct OpenAI API with exact `gpt-image-2`.
- `grok_image` uses the exact prompt and approved attachment order, choosing
  `image_edit` for one or more attachments and `image_gen` for zero attachments.
- `xai_api_media` opens only with explicit Founder API authority and an exact
  registered provider-owned profile. Missing/stale model, API version,
  endpoint, request/response contract, or image operation is a pre-credential
  registration HOLD; no literal is inferred and no fallback exists. The request
  preparer records that HOLD instead of `ready`, while the 02B validator and
  dry-run media adapter independently reject the same unregistered or stale
  binding.

The canonical merged `02B-prompt-packets.yaml` remains the only creative packet
truth. Export creates pointer-based `exports/02B/sections/Sxx/` packages for
inspection, while active execution begins from one validated
`idol_image_generation_request.v12` per named Cut. Every lane pins provider,
auth, profile/version snapshots, exact output, prompt rewrite forbidden, and no
fallback. The historical
`idol_02b_batch_api_runner.py` is historical and fails before preparation or
external access. A future Batch adapter must consume current v12 requests and
their section scope directly; it may not revive board/keyframe manifests, a
root export index, or an all-song prompt aggregate.

Every adapter stops on prompt-hash drift, stale source/reference bytes,
unsupported locked inputs, missing current-job approval, or an output that
cannot be intaken at the declared path. An adapter may not omit an image,
replace it with a text description, or ask the worker to reinterpret 02A.
Every adapter continues inside the hash-bound post-02A image-motion section
lineage scoped to one `execution_section_id`. A durable checkpoint may resume
that lineage only through the registered provider-resolved physical successor;
Luna XHigh is an optional exact route, never an implied fallback. 04 is not part
of this request.
It consumes the exact `image_prompt_section` Context Pack v7 and one run-owned
planning source, and verifies their SHA-256 values. The pack's hash-bound
section projection is the worker's run-source boundary: lossless active 02A,
causal-only whole-video spine, exact adjacent boundaries, explicit remote
anchors, and unique physical visuals with all bindings. Do not
load other-section cuts/prompts/references, whole contact sheets, raw research
history, prior chat, the full asset registry, or the full 01/02A/02B monolith.
The Overall Director and CDD are forbidden as image-execution controllers.
Adapter-native execution or assigned post-02A section owners may run different
sections asynchronously only when
packet ownership and output paths are disjoint. Within each section, the
selected runtime's current capacity bounds parallel calls; unsupported runtimes
serialize only their own calls without rewriting packets. Direct scripts retain
hash and contract checks, the assigned section owner performs complete pixel
review, and—after the verified Graph v2 switch—the owning V-Ci Section-Cluster
CDD retains bounded-evidence review, continuity, and repetition authority for
its exact two- or three-section cohort before sending a reviewed milestone to
Overall. Until that switch, the pinned legacy CDD retains this review boundary.

## Core-Cut And Branch-Cut Cardinality

Generation count follows the approved screen plan, never a fixed image quota.
A Core Cut owns one major event, action, effect, condition, or dramatic beat.
It states the intended first-time target-viewer read and why the next governing
event follows. Its ordered Branch Cuts are independently framed screen
realizations that reveal distinct observable information about that same event.

- every 01 Official Core owns exactly one passed primary image and may own one
  or more 02A `compile_seed.branch_cuts[]`
- every Branch Cut owns exactly one 02B packet, one generation request, and one
  generated still
- valid branching may reveal a different event phase, viewpoint, participant
  response, object/space consequence, insert, aftermath, reprise, or transition
- a start/end label, shot-size-only change, or repeated screen with no new
  visible job is not sufficient branching
- a lens, angle, or beauty variation alone is not sufficient branching; the
  screen must add viewer knowledge, response, consequence, emotional landing,
  or a necessary edit/continuity job
- if the screen introduces a new governing event, return upstream for a new
  Major; if it reveals the same event differently, keep it as a Branch Cut
- ordered phases such as setup, release, expansion, impact, reaction, and
  aftereffect are allowed when each frame carries distinct screen truth; phase
  labels are not a mandatory taxonomy
- one dense section may use many Core Cuts and few Branch Cuts, while another
  may use one Core Cut with several strong Branch Cuts
- local contact sheets may group generated Branch-Cut images for review, but
  grouping never changes generation count or ownership
- identical compiled prompt hashes are an output-ownership/reuse question, not
  a machine-authored creative verdict

## Validation

Before any imagegen request:

1. The canonical 02A schema is `3.0`, the delta is `1.6`, and the merged
   prompt-packet schema is `2.6`.
2. `packet_policy.unit` is one named Cut per packet in explicit Hero/Core/Branch
   mode; Official Branch packets exact-cover every active
   `compile_seed.branch_cuts[]` row.
3. Each packet preserves `core_cut_id`, `branch_cut_id`, its complete
   `branch_cut_lock`, the exact parent Core Cut, adjacent Branch Cuts under that
   Core Cut, and immediate same-section neighboring Core Cuts.
4. The creative components are human/model-authored after exact Branch-Cut and
   visual-input inspection. Scripts validate the receipt and serialize them
   into the fixed order `Identity reference rule`, `Scene intent`, `Visible
   details`, `Action cue`, `Avoid`; they do not write prose.
5. The prompt preserves observable action or hold, still-camera height,
   distance, direction/angle, depth, placement, crop, composition, continuity,
   selected reference grammar, and the Branch Cut's distinct screen
   contribution.
6. `member_visual_lock` uses only the smallest relevant newly built album/title
   subset and never creates a downstream face-only lane. It is followed by the
   governing scene/sequence reference and supporting-component reference in one
   combined order; no separate background/world lane is admitted. Cross-album
   pixels hold unless the Founder selected that exact direct scene reference.
7. `visual_reference_bindings` retain actual path, SHA-256, function, preserve
   and discard locks, attachment permission, and declared order. A selected
   cell/crop is a separate input; a whole sheet does not count.
8. `compiled_prompt_block.full_prompt_text` and its hash exact-match the five
   canonical lines. Internal ids, paths, schemas, approvals, and process text
   do not leak into render prose.
9. `export_contract.expected_output_path` is run-owned and unique to the
   Branch-Cut packet. One packet becomes one request and one still.
10. The derived `idol_image_generation_request.v12` preserves the exact prompt,
    Cut pointer/type, current-title member-visual order, scene-reference order,
    combined attachment digest, provider/auth/profile snapshot, exact approval,
    and expected output.
11. The request verifies `4K`, `high quality`, and `high detail`, uses
    `gpt-image-2`, highest available quality, and maximum supported dimensions
    for the locked aspect ratio.
12. The chosen adapter accepts every locked input and parameter. Unsupported
    inputs hold the job instead of being omitted or described in text.
13. Generation output is copied into the declared run path, hashed, pixel
    inspected, and entered into Generated Branch-Cut Review. A PASS remains
    bound to those unchanged source bytes.
14. LLM/director review judges event fidelity, directorial diversity,
    continuity, and repetition. Exact ids, paths, hashes, order, and output
    ownership are machine checks; semantic similarity is not.
15. Every passed source image receives a deterministic local LANCZOS upscale
    before 03V, but only when the shared post-pass library receives either one
    complete explicit Founder all-PASS intake through
    `idol_review_decision_intake.rb --write`, or one exact G2 delegated close
    through `idol_g2_delegated_pixel_close_intake.rb --write`. The G2 route
    requires the exact authority envelope and Section-Cluster CDD review: all
    seven applicable 0--4 grades are at least 3, the named motion-anchor grade
    is 4, and target/message violation plus material drift are false. Neither
    script authors grades or a verdict. The validated intake exact-applies the
    decision only to the returned review's `founder_review` status and
    post-pass placement boundary; it does not invent or revise a section or
    Branch-Cut judgment.
    HOLD, REJECT, partial, stale, and other-cycle intakes perform no status
    promotion, no upscale, and open no 03V route. The idempotent
    `SOURCE_IMAGE.upscale.json` must validate the exact source and output
    hashes, preserve aspect ratio, disable crop, sharpening, and generative
    enhancement, and bind a PNG whose long edge is at least 3840 pixels.
    Audio Production-Cut Placement and 03V consume that output; the reviewed source
    remains the creative pixel authority. A ready placement must separately
    validate before the intake may report that 03V can start.
16. Each provider-resolved post-02A execution worker stays scoped to one section
    through 03V. After the verified Graph v2 switch, one V-Ci CDD owns the
    matching contiguous two- or three-section cohort across pixel and playback
    review; disjoint sections may execute only with disjoint packet/output
    ownership. 04 begins from a separate passed 03V handoff.
17. A completed Core Cut receives no invented parent image. Its coverage is the
    ordered set of actual generated Branch-Cut stills beneath it, and every one
    of those stills enters the same pass-bound local upscale gate. The shared
    gate may also process an exact generated image on a non-Branch Workbench
    card, such as a current-title member clean card, only on explicit Founder
    PASS for that card. It excludes face-only/style inputs, reference or
    planning evidence, previously promoted title assets, video, HOLD, and
    REJECT. Such a non-Branch visual returns to its owning promotion boundary
    and never establishes 03V readiness.

## Local Contact Sheets

Generated Branch-Cut review sheets are local assemblies made after generation
returns individual images. They may group a useful number of images for Founder
review and add compact local labels, but those labels are never part of the API
prompt or generated image.

## Legacy Diagnostic Mode

`schemas/prompt-packets-v1.3-legacy.schema.json` remains archive evidence only.
It is not an accepted input to active generation or a compatibility route.
