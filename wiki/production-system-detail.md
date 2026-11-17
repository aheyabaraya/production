# IDOL Production System Detail

This page is an operator supplement to `production-system.md`. Active creative
method lives in the owning skill and policy; this page lists artifact and
validation flow.

## Active Artifact Chain

| Stage | Canonical contract | Typical artifact |
|---|---|---|
| 00A | `1.4` | `00A-song-lock.yaml` |
| PRE-00 selection handoff | `idol-pre00-selection-handoff.v4` | `research/pre00-selection-handoff-v1.yaml` |
| Front Planning | `front-planning-readiness.v17` | `front-planning.yaml` |
| 01 | `idol_song_choreography_performance_mv_map.v3.0` | `01-song-choreography-performance-mv-map.yaml` |
| 02A | `idol_master_storyboard.v3.0` | `02A-master-storyboard.yaml` |
| 02B section delta | `idol_prompt_packet_delta.v1.6` | section-scoped delta |
| 02B canonical | `2.6` | `02B-prompt-packets.yaml` |
| image request | `idol_image_generation_request.v12` | packet request |
| image execution receipt | `idol_image_generation_execution_receipt.v4` | redacted exact execution receipt |
| image render correction | `idol_image_render_correction.v8` | bounded correction request |
| generated Branch review | `idol_generated_branch_cut_review.v4` | `review/generated-branch-cut-review.yaml` |
| typed Production Cut review | `idol-production-cut-review.v2` | `03-production-cut-review.yaml` |
| audio placement | `idol_audio_production_cut_placement.v5` | `03V-audio-branch-cut-placement.yaml` |
| 03V board | `idol_video_prompt_storyboard_assist.v4` | `03V-storyboard-assist.yaml` |
| 03V prompt | `idol_video_prompt_manifest.v8` | `03V-video-prompt-manifest.yaml` |
| Founder HTML | `idol-html-review-board.v12` | `review/founder-workbench.html` |
| decision intake | `idol_founder_review_decision_intake.v7` | `review/decision-intake/*.yaml` |

There is no active 00, 01A, or 02 creative artifact.

## Studio Dispatch Baseline

Exactly one Founder-selected frontier Overall Director owns routing, canonical
promotion, Founder-facing recommendation, and final creative acceptance. Graph
v2 remains shadow-only until an exact verified default-switch receipt exists;
the legacy route keeps one durable CDD until then. After the switch, Overall
routes one physical P1 Story/Audience CDD, one physical P2 Visual/Reference CDD,
and a roster-derived set of P3-Ci Section-Cluster CDDs, each owning one
contiguous two- or three-section cohort. P1 is the only planning integration
writer. Matching V-Ci CDDs exact-carry those cohorts through 02B pixel and 03V
playback review. Each CDD lane/stage admits one primary plus at most one CAS
successor; a third claimant holds. Overall remains the only Founder-conversation
owner and promotion authority.

- Pre-song abstract/first-proposal work opens only the smallest disjoint logical
  `worker_high` assignments justified by named evidence gaps. The immutable run
  snapshot resolves and pins the registered provider, with Grok preferred when
  ready; it never silently falls back. No worker count is
  preallocated; a director-ready start may open one named gap or none.
- The Song route uses one physical Founder-visible Song Room under CDD for
  lyric, arrangement, candidate, selected-audio, audio-motion, and 00A work and
  returns only to CDD.
- Post-song reference work adaptively opens the smallest disjoint mix of
  video-capable generalist, image-only World/Still, and image-only Pinterest
  assignments needed for named gaps. Source and worker counts are capacity
  ceilings, never creative quotas. World/Still performs no video work and
  performs every multi-image comparison from bounded-worker pruning through CDD and
  Founder review on a hash-bound uncropped contact sheet. After each reviewed
  return, CDD either closes the named gap or opens another disjoint assignment;
  provider capacity supplies backpressure without defining quality completion.
- Run-specific groups load `idol-reference-research-department` only. A
  selected unregistered or stale source opens a separate
  `idol-video-reference-hub` source-owner dispatch; it returns reusable
  source-level evidence from `source-materials/video-sources` and never writes
  current-run disposition or section binding. Query
  `catalog/references/reference-catalog.yaml` through
  `scripts/idol_reference_catalog_lookup.py` instead of loading the full catalog.
- A missing or full-restyle current-title member card may open one conditional
  physical Member Visual Identity task under the selected provider. Luna XHigh
  is optional and never an implicit fallback. Passed cards bind
  without reopening and no separate Styling Room is created.
- Pre-02A development uses two to four ordinary blocks, one section by default
  or two to three connected sections, with a fifth only for a reviewed named
  exception. Launch only disjoint named-gap assignments under the lower
  registered provider capacity; capacity is never a completion quota.
- Post-02A execution may open a provider-resolved
  `section_image_motion_worker / worker_high` session for exactly one physical
  section. It receives only the compact approved checkpoint and owns execution,
  not CDD judgment. After Graph v2 switch, its returns go to the exact V-Ci
  cohort owner for 02B pixel and 03V playback review; before the switch they go
  to the pinned legacy CDD.
  04 starts separately under
  a fresh Founder-visible Edit Director, with disjoint Edit `worker_high` shards returning
  only to that director and the final merge returning to Overall.

No short-form output, per-Major hook quota, or derivative field is a Front
Planning, 01, or 02A readiness requirement.

Active visual roles remain `character_visual`, `scene_visual_package`,
`motion_reference`, and optional `prop_reference`. Recover a bound unit by
`source_id` → locator → function/role → disposition → section/Major/Core
binding → 02A / 02B / 03V. Wiki is not a second media library; default packs
and wiki summaries exclude raw URL lists.

Use the smallest validation mode that matches the decision boundary:

| Mode | Use | Required proof |
|---|---|---|
| Explore | discovery, candidate search, noncanonical worker draft | scope, source availability, readable evidence, basic shape |
| Promote | worker return, director review, canonical section/artifact promotion | owner and epoch, input/result digests, source bindings, applicable schema, creative review |
| Execute | paid/external generation, merge, playback, delivery, release | strict hashes, explicit permissions, exact outputs, pixel/playback evidence |

Do not run downstream-final validation during ordinary exploration. Raw search
pools, temporary extraction, generated context packs, and runtime dependencies
stay in excluded work/cache space and never masquerade as active run truth.

## Dispatch Index, Aggregate Manifests, And Boot Pack

The run-owned Director Dispatch Index is a pointer-only projection over
Department Dispatch attempts. It records lineage/session identity, bounded
scope, state, input/result digests, review disposition, output-manifest
pointers, board links, holds, canonical heads, and next actions; it never
embeds images, long prose, raw pools, or creative truth. Every multi-file worker
return exposes one aggregate manifest with exact child paths and SHA-256 values;
the index stores that manifest pointer and counts rather than copying its rows.

A deterministic Director Boot Pack projects only the active stage, decision
epoch, explicit locks, open/held tasks, canonical heads, active board cycle, and
next actions. It excludes full transcripts, rejected dumps, raw candidate pools,
and unrelated section artifacts. Index and board-manifest writes are
single-writer operations with a source-set digest recheck before replacement.
Creative delegation stops one level below a director. A worker that needs to
split returns exact unowned subscopes, sibling count, disjoint paths, shared
boundaries, and risk; the recipient director decides. New launches pause only
when the next assignment consumes pending returned bytes (especially image
hashes), a shared writer is behind, or an owner/path collision exists. Canonical
wait rule: `automation/harness-execution-contract.yaml`
`live_worker_capacity.provider_capacity.queue_launch_when`. Capacity never
overrides review backpressure or Founder locks.

## 00A Closeout

Required:

- actual Founder-selected audio;
- original lyric/transcript source when applicable;
- selected-audio analysis path/hash;
- audio rhythm evidence map path/hash;
- section order, hook, pulse, meaning guard, trigger cues, and editability;
- no target, MV-message, member, visual, scene, still-camera, or temporal-camera
  lock.

Validate against `schemas/song-lock.schema.json`. Front Planning starts only
from a passed 00A and authors the target/message/visual/section truth.

## Front Planning Closeout

Required:

- selected-song lock path/hash; its internal audio evidence remains canonical
  upstream rather than being copied into Front Planning;
- audience evidence and target connection;
- message and screen promise;
- current-title package manifest;
- passed current-title member visual binding, with exception selection only for
  a new or fully restyled candidate;
- whole-video spine;
- complete section plan;
- unified current-title member visual, governing scene/sequence reference, and
  supporting-component assignment;
- integrated 01R/01R-C interpretation contract;
- one Creative Development Director-owned Reference Working Index preserving
  `Discovery Pool -> selected Evidence Card -> exact section binding`;
- adaptive named-gap video-generalist, image-only World/Still, and image-only
  Pinterest returns with complete actual-unit evidence for each comparative
  judgment, followed by CDD checkpoints and only the additional disjoint
  assignments still required for a decision-ready FP route;
- reference comparison floor;
- purpose-class function analyses;
- two to four development-block checkpoints and separate section rows when a
  block groups two or three connected sections;
- curated Decision Sets with exact media and Anti-Flat evidence: source-to-
  screen delta, current-song/member dependencies, observable
  before/trigger/after state, distinct contribution, whole-video consequence,
  execution strength, and concrete risk;
- Creative-Development-proposed Major direction, current-title visual/reference
  evidence, Creative Development QA, and Overall promotion state;
- coverage-complete Creative-Development-QA'd and Overall-promoted Key Screen
  Anchors, each binding one governing or primary named reference function and
  only optional support for another named screen job, with detailed camera/
  composition;
- explicit `discovery`, `direction_synthesis`, or `fp_final` review mode, with
  only `fp_final` carrying the consolidated PASS/HOLD/REJECT state, plus any
  named exception choices;
- Department Dispatch Contract, skill revisions, matching input/result digests,
  and required-skill application evidence. No manual worker-authored skill
  receipt is required.

Validate:

```text
ruby scripts/validate_front_planning_readiness.rb PATH
```

## 01 Closeout

Required:

- exact Front Planning projection;
- resumed development-block checkpoint and exact section dispatch scope;
- one section expansion per active section;
- observable scene/action/hold;
- staging and still-camera geometry;
- title visual projection;
- exact reference application;
- choreography source where active;
- section transitions;
- every Official Core and exactly one passed primary image per Core;
- per-section Anti-Flat evidence;
- Creative Development Director shard review and Overall Director promotion;
- matching dispatch/skill/application input-result evidence; and
- section and whole-video creative review.

Validate:

```text
ruby scripts/validate_01_section_direction.rb PATH
```

## 02A Closeout

Required:

- exact Front Planning and 01 sources;
- promoted 01 working-shard lineage and dispatch evidence;
- immutable exact imports of every 01 Official Core and its passed primary
  image;
- internal Branch coverage plan;
- ordered section shards;
- 1..N ordered Branch Cuts per imported Core, each adding distinct screen
  information;
- still-camera and composition;
- current-title and scene-reference binding pools;
- expected outputs;
- Creative Development Director working-shard review, Overall Director
  promotion, and Founder storyboard review.
- `idol-front-planning-development-block` plus its exact pre-02A 02A coverage
  module; no `idol-generation`, prompt-compile, render-correction, 03V, or edit
  load before exact 02A approval.

Validate:

```text
ruby scripts/validate_master_storyboard.rb PATH
```

## 02B Closeout

Open a fresh just-in-time provider-resolved `section_image_motion_worker /
worker_high` production session from the exact
Overall-approved compact checkpoint for one physical section. It must not carry
the pre-02A multi-section planning chat or rejected reference pool. One
model-authored v1.5 section delta is compiled without creative rewriting.
The author inspects the exact Branch Cut, current-title assets, and selected
reference derivatives, records their hash/order in the inspection receipt, and
authors all structured Visible details and Action cue components. The compiler
adds only fixed labels, separators, and punctuation. Review one section, then
merge passed sections into v2.5.

This is the first checkpoint that loads `idol-generation`. Its ordinary 02B/
image checkpoint does not preload the render-correction module. A named held or
rejected pixel defect activates that module later in the same section lineage;
03V and 04 remain separate phase profiles.

New compiler output carries
`idol_02a_02b_local_lineage.v2`: section-invariant, entry/exit-boundary,
core-cut context, exact-branch-cut, immediate branch-sibling,
same-section-core-neighborhood, and packet-value
hashes. For a packet-only revision, add `carry_forward_source_02b` and include
only changed packet rows in the delta. The compiler exact-copies omitted
packets after local validation. The merge updates the current whole 02A
baseline but does not reject an unchanged section merely because that
whole-file SHA changed.

Validate:

```text
ruby scripts/validate_02b_imagegen_contract.rb PATH
```

Export and prepare:

```text
scripts/idol_export_02b_prompt_manifests.py ...
ruby scripts/idol_prepare_image_generation_request.rb ...
```

No command implies paid approval.

## Context Pack

Build one section/core-cut pack:

```text
ruby scripts/idol_harness_context_pack.rb RUN_ROOT \
  --section S01 \
  --cut-id C01 \
  --task "author active 02B prompts"
```

Validate:

```text
ruby scripts/validate_harness_context_pack.rb PATH
```

## Generated Review

Review every output against its exact 02A branch cut and 02B packet:

```text
ruby scripts/validate_generated_branch_cut_review.rb PATH
```

New rows bind the exact 02B packet value hash. For a current review assembled
after a local packet change, unchanged passed rows may cite an exact prior
review path/SHA and prior row-value SHA. A section review carries only when its
ordered packet-set hash is unchanged.

The typed Production Cut review's passed status is required for Audio
Production-Cut Placement. The legacy filename
`03V-audio-branch-cut-placement.yaml` does not narrow the active semantics to
Branch rows.

## 03V Closeout

Validate timing:

```text
ruby scripts/validate_audio_branch_cut_placement.rb PATH --require-ready
```

Validate storyboard boards:

```text
ruby scripts/validate_video_prompt_storyboard_assist.rb PATH
```

Prepare exact source pack:

```text
ruby scripts/idol_prepare_video_prompt_authoring.rb RUN_ROOT --write
```

Validate prompt manifest:

```text
ruby scripts/validate_video_prompt_manifest.rb PATH
```

Optional Grok local handoff:

```text
ruby scripts/idol_prepare_grok_video_prompt_handoff.rb RUN_ROOT \
  --source-pack RUN_ROOT/handoff/03V-authoring-source-pack.yaml \
  --founder-requested --write
```

The Grok command creates local handoff files only.
Grok and Codex adapters consume the same approved source pack, prompt truth,
attachment order, and decision semantics; the handoff is not permission for a
provider-specific creative rewrite.

## Unified Review

Front Planning uses the stable workbench in one declared mode:

- `discovery`: four to eight curated ingredients with `attracted`, `reject`,
  `hold`, `connect_these`, `keep_only`, `search_further`, or `direct_comment`
  signals;
- `direction_synthesis`: one recommended complete FP candidate and up to two
  complete alternatives, with `select_candidate`, `lock_fields`, `hold`,
  `reject`, or `direct_comment`; selection routes one base without FP PASS and
  only exact Founder-named fields become locks; or
- `fp_final`: a legacy internal board mode token whose active pre-02B use is
  Founder 02A Final Planning; internal FP Close appears as exact read-only
  lineage and is not another Founder gate.

Discovery signals are nonbinding. Direction Alignment selects one coherent
direction and only `lock_fields` binds exact Founder-named fields. PASS returns
the same Director epoch to internal FP Close, role-routed 01, and 02A. A
requested cross-candidate delta is reauthored as one coherent candidate.
Target/message/audio tension stays visible as reading,
evidence, counterreading, and screen consequence rather than an automatic
filter. The Creative
Development Director curates and presents the pre-02A cycles in its
Founder-visible task, preserves verbatim decisions, and returns a reviewed
milestone package; it has no promotion authority. Overall alone promotes and
accepts canonical truth. Raw pools stay off the board. The fresh
Founder-visible Edit Director owns the 04 review stage and disjoint Edit
`worker_high` shard decisions, merges them, and returns one final package to Overall without
becoming a second promoter. Later stage cycles preserve their registered
decision semantics on the same board lineage.

Validate/render:

```text
ruby scripts/idol_html_review_board.rb validate MANIFEST
ruby scripts/idol_html_review_board.rb render MANIFEST
```

Intake:

```text
ruby scripts/idol_review_decision_intake.rb EXPORT.json --write
```

HOLD/REJECT needs a note. Intake records scope but never patches creative truth.

## Stage Resume

Resume pre-02A work only from live source hashes, valid active schema, exact
development-block checkpoint, Department Dispatch Contract, recorded skill
revisions, matching input/result digests, required-skill application evidence,
current scope ownership, and exact Founder state. A new physical session does
not reopen unchanged planning. A manual worker-authored skill-application
receipt is not an active gate.

“Live source hashes” means the smallest owning value hashes where local
lineage exists. Whole-artifact SHA remains the authored baseline and provenance
record. Unchanged section reviews carry through their exact prior review
path/SHA, prior row hash, and current section-truth hash. Focused context packs
may be mechanically refreshed when source transport bytes change without
reopening creative review.

For post-02A work, resolve `physical_section_shard` through the immutable
provider snapshot and open a fresh Founder-visible exact-one-section
`section_image_motion_worker / worker_high`
session from the exact approved checkpoint. One physical session owns exactly
one section lineage through placement and 03V, then returns the passed package
to the continuing CDD. A post-02A upstream HOLD returns only the affected scope
to that durable CDD checkpoint; CDD returns a replacement shard before the same lineage
resumes. A replacement physical session may resume only the same exact durable
checkpoint. After section 03V handoffs pass, 04 starts as a fresh
Founder-visible Edit Director execution unit; disjoint Edit `worker_high` shards return
only to Edit Director, which owns the merge and returns final 04/05 truth to
Overall. Terra is not an ordinary production owner.

Runtime source admission is limited to the current run, current-title package,
and selected hash-bound source material. Test fixtures, maintenance examples,
historical prompt prose, and un-intaken files from another run are a hold.

## Failure Handling

Return to:

- Front Planning for central locks;
- 01 for section direction, Official Core event/reference/primary-image truth,
  or a changed Branch need;
- 02A for immutable Core import and Branch action, composition, binding, order,
  or roster truth;
- 02B for render wording only;
- exact output for pixel defect;
- 03V for subject/camera motion;
- 04 for edit-only changes.

Do not widen context or regenerate unrelated sections to repair a local hold.
