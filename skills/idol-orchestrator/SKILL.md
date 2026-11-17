---
name: idol-orchestrator
description: "Use when the Founder asks to start, inspect, continue, automate, or resume an IDOL production run. Keep one logical Overall Director. Select the writer from graph-default-routing: existing runs stay legacy-pinned; new runs may use Graph v2 only after a verified default-switch receipt. Graph v2 opens Planning P1/P2/P3-Ci and roster-derived V-C1..V-Cn CDD cohorts, never a fixed CDD count. Stop at Founder G0--G4 and paid/external gates."
---

# IDOL Studio Orchestrator

The orchestrator is the mechanical studio coordinator. It does not replace the
Overall Director, Creative Development Director, writer, visual designer,
cinematographer, choreographer, image director, motion director, or editor.

Exactly one logical Overall Director owns routing, canonical promotion,
Founder-facing recommendations, and final creative acceptance for the run.
Overall remains the only Founder-conversation owner. No standing Final Director
or ordinary Terra creative-production route exists.

## Default And Legacy Writer Boundary

Read `automation/graph-default-routing.yaml` before opening a Director or
worker session. That file is mechanical route selection only.

- Existing runs remain `legacy_pinned`. Do not rewrite their receipts, schema
  ids, or canonical writer to Graph v2.
- New runs default to `legacy_pinned`. They may select Graph v2 only after a
  verified default-switch receipt naming Founder authority, graph revision,
  switch boundary, and source-set SHA-256.
- Historical `harness-*` ids are parse-only Legacy Capsule inputs. Do not
  author them into a new artifact, prompt, pack, or session.
- One logical state may not have an old writer and a new writer at the same
  time. Dual active writers fail closed.

Until that receipt exists, use the current legacy-pinned CDD and
`automation/harness-skill-load-profiles.yaml` path. After the receipt, Graph v2
owns admission, node scheduling, skill load, Role Context Packs, succession,
backpressure, and Founder G0--G4 projection from
`automation/graph-skill-load-profiles.yaml` and
`automation/graph-role-context-projection.yaml`.

## Graph Admission And Node Scheduling

On Graph v2, Overall admits one graph node at a time. The coordinator:

- binds the Department Dispatch Contract and waits for native Goal admission;
- builds one exact-node Role Context Pack; the receiver applies that pack plus
  named current creative sources and does not reread the whole graph-engineering
  route;
- schedules only the next legal node; capacity is a ceiling, never a quota;
- returns worker output to the named Director; that Director reviews exact
  bytes before any promotion request reaches Overall;
- holds on missing hashes, overlapping writers, third sessions, unverified
  switch receipts, and unrecoverable source locators.

Scripts validate transport, provenance, and these structural gates. They never
author creative truth, grades, or PASS.

The shadow Graph run controller is
`scripts/idol_graph_run_controller.rb`. It reads the current-next projection,
Director Dispatch Index, shadow stage registry, selected dispatch, and optional
hash-bound contextual judgment, then emits one stdout-only decision plus a
verified frontier set:
`dispatch_or_resume_model`, `await_director_review`,
`route_bounded_correction`, `await_founder_decision`, or `hold`.
More than one frontier head is legal only when all heads are same-stage,
mutually disjoint section cohorts; it remains a blocked shadow plan until a
registered scheduler enforces those facts at execution time.
Its append-only event is an intent with an idempotency key, not a persisted
event. It does not launch or resume a provider, write a ledger, create a Goal,
author a score, review bytes, or promote work. Until a separately validated
provider executor, event writer, real-song pilot, and exact default-switch
receipt exist, use it only to shadow the intended
Goal -> judgment -> Director review/correction -> Founder-gate loop.

Use it only for an explicit production-direction, start, continue, inspect,
resume, or automation request. Casual discussion does not activate execution.
Before opening a Founder-visible CDD, Song, Member Visual Identity, post-02A
section, Edit Director, or edit-shard task, require explicit current-run route
authorization or the registered run-manifest flag from the execution contract.
Absent authorization holds creation. Task-route permission never implies web,
download, capture, upload, paid-generation, or release permission.

Use only the provider adapter's registered create/send/wait/resume/retire/
successor operations. Resume from the exact Director Boot Pack checkpoint. A
successor may exist only as a zero-turn read-only preflight while the prior
owner remains active; the registered session router must atomically retire the
prior writer before it authorizes successor work. Never replace a failed
operation with another provider silently.

## Required Reads

Always read:

1. `AGENTS.md`
2. `automation/graph-default-routing.yaml` to select the writer
3. `policies/harness-routing-and-sources.md`
4. `policies/section-production.md`
5. `wiki/production-system.md`
6. `references/provider-neutral-studio-kernel.md` before authoring, receiving,
   or validating a launch command
7. `references/orchestration-routing-detail.md` for a real dispatch or resume

If the run is `legacy_pinned`, also read
`automation/harness-stage-registry.yaml` and
`automation/harness-execution-contract.yaml`, then load the exact checkpoint
set in `automation/harness-skill-load-profiles.yaml`.

If a verified default-switch receipt selected Graph v2, also read
`automation/graph-skill-load-profiles.yaml` and
`automation/graph-role-context-projection.yaml`. Resolve the checkpoint's
current immutable judgment-profile release through
`automation/graph-creative-judgment-registry.yaml`; bind that release path,
release SHA-256, and profile-value SHA-256 into the Role Context Pack and
judgment. Do not load both graph and harness profile registries as active
writers.

Then read the complete owning skill, active schema, required linked references,
and current run sources for the discovered stage.
For every real creative worker dispatch or resume, also read
`schemas/department-dispatch.schema.json` and validate the complete prepared ->
launched -> returned -> reviewed -> promoted/hold lifecycle.
The coordinator performs that complete-source read and validation. After the
receiver's native Goal admission, build and validate one exact-node
`idol-role-context-pack.v1`. On Graph v2 the pack is projected from
`automation/graph-role-context-projection.yaml`; on a legacy-pinned run keep
`scripts/idol_role_context_pack.rb`. The receiver applies its exact projected
fragments plus named current creative sources. Do not send the broad
dependency inventory as a second runtime read list.

## Active Stage Route

Follow `wiki/production-system.md` heading `## Active Route` to EOF. This
coordinator does not keep a second stage map.

The Skill Routing table names owner skills. These coordinator-owned literals
stay here because the compact route does not carry them: Front Planning +
01R/01R-C; adaptive named-gap video-capable integrated generalist reference
assignments; physical image-only World/Still department; physical Pinterest
Visual/Composition worker; hash-bound contact sheets; two to four ordinary
pre-02A worker_high development blocks; fresh exact-one-section
02B/image-generation Grok CLI session. After song lock the execution-contract
reference fetch floor is six disjoint workers; CDD/FP/02A multi-leaf work uses
parent-scoped Grok `spawn_subagent` at floor four.

On Graph v2 the same production spine remains. What changes is CDD topology:
Planning uses P1 Story/Audience, P2 Visual/Reference, and roster-derived
P3-C1..Cn; after G-40 the same cohort ids become V-C1..V-Cn. Do not open a
third Planning function CDD or a function-only post-G-40 CDD.

Do not create separate active 00, 01A, or 02 artifacts. Existing run bytes with
those names do not create a compatibility branch.

No short-form extraction, hook quota, or derivative field is required by the MV
planning route.

04VFX is not an active registered stage and has no schema or automatic
dispatch. Call `idol-shot-vfx` only when a passed 04 window needs true shot VFX;
its passed clip returns to 04 and becomes eligible for 04FX only after 04
re-ingest and playback validation. Before that manual loop, read
`skills/idol-shot-vfx/references/04vfx-manual-use-and-runtime.md` for the
runtime, package, cache, and review rules.

## Skill Routing

| Need | Owner skill | Professional role |
|---|---|---|
| Graph v2 Planning CDD Cell: P1 Story/Audience, P2 Visual/Reference, or one P3-Ci section/kinetic cohort | `idol-planning-cdd` with exact `planning_cdd_mode` | frontier Planning CDD lane returning to P1 or Overall; proposal skill until atomic promotion |
| Graph v2 post-G-40 Section-Cluster CDD for one roster-derived 2--3-section cohort through 02B pixel and 03V playback | `idol-section-cluster-cdd` bound to one `section_cohort_id` | frontier Section-Cluster CDD; one section media worker remains the 02B/03V writer |
| Audience, message, title identity, section spine, worker review, Founder workbench | `idol-front-planning-director` | legacy-pinned one CDD room, or Graph v2 Planning Cell G-40 integrator, with Overall Director promotion |
| Run-specific reference search, inspection, disposition proposal, and Reference Working Index delta | `idol-reference-research-department` | bounded integrated `worker_high` reference generalist on the run-resolved registered provider, returning to CDD |
| Broad non-Pinterest still research for space/world/object/material/light/composition | `idol-world-still-reference-department` | image-only World/Still worker returning to CDD |
| Per-section public-pin visual/composition comparison | `idol-pinterest-reference-worker` | dedicated image-only Pinterest worker returning to CDD |
| Original registration and reusable source-level Layer A/B analysis | `idol-video-reference-hub` in a separate source-hub dispatch | source owner returning exact evidence to CDD; no run disposition |
| Current-title member appearance card: approved face plus full hair/makeup/wardrobe restyle in face/upper/full format | `idol-member-visual-identity` inside Front Planning | member visual identity and styling director |
| FP section shard and its bounded checkpoint lifecycle | `idol-front-planning-development-block` | noncanonical `worker_high` section developer on the run-resolved registered provider, returning only to CDD |
| 01 section story, action, staging, still camera, transitions | `idol-front-planning-development-block` plus phase-loaded `idol-mv-director` | writer, scene director, still cinematographer |
| Actual choreography/performance/body phrase | `idol-choreography-performance` | choreographer and performance director |
| Pre-02A 01 Official Core / 02A Branch coverage | `idol-front-planning-development-block` plus its `02a-coverage-authoring-detail` | noncanonical section/Core/Branch planning worker returning to CDD; 01 owns Core bytes and 02A exact-imports them |
| Post-02A 02B image prompt, visual inputs, generation, pixel review | `idol-generation` in a fresh exact-one-section lineage | production designer, still-image and image-prompt director |
| 03V storyboard boards, subject/camera motion, video prompt | `idol-video-prompt` | motion director and video cinematographer |
| 04 assembly/QC | active edit skill/contract | editor |
| Optional hero-object, spatial, 3D, tracked, or composited shot VFX inside a passed 04 window | `idol-shot-vfx` | shot VFX supervisor and compositor |
| 04FX transition/accent/grade finishing after passed 04 playback | `idol-edit-finishing-fx` | finishing editor |

Load choreography only when the current section actually needs it. A worker
never loads `idol-front-planning-director`; a run-specific reference worker
never loads `idol-video-reference-hub`; and a pre-02A checkpoint never loads
`idol-generation`, prompt compilation, render correction, 03V, or edit skills.
Use the exact checkpoint set in the selected writer registry:
`automation/graph-skill-load-profiles.yaml` after a verified Graph v2 switch,
otherwise `automation/harness-skill-load-profiles.yaml`.

## Teaching Example Use

Examples inside policies and owner skills are method aids. They may supply
decision questions, contrasting route families, and an output skeleton; they
never supply the current run's action, camera, composition, motion, or prompt
value. Route the operator to the owner skill's non-prescriptive example, then
require the current song, reference, title assets, or passed pixels to choose
and author the actual result.

Do not strip every example while removing historical bias. Do not copy an
example into a context pack or canonical artifact either.

## Frontier Discovery

Inspect only the named run and relevant canonical files. Determine:

- last valid active artifact and SHA-256;
- current PASS/HOLD/REJECT state;
- exact affected sections/core cuts/branch cuts;
- active owner and checkpoint;
- missing Department Dispatch Contract, required-skill application evidence, or
  source;
- next legal stage;
- external/paid approval state.

Do not infer readiness from filename order. A later artifact cannot bypass an
invalid owner.

## Dynamic CDD Cohorts

Legacy-pinned runs keep one durable Founder-visible CDD room from startup
through 03V playback review.

Graph v2 replaces that one-room assumption with roster-derived lanes:

- `CDD-P1 Story/Audience Lead` is the only planning integration writer from
  PRE-00 through G-40.
- `CDD-P2 Visual/Reference Development` owns the visual/reference Decision Set.
- `CDD-P3-C1..Cn Section/Kinetic Architecture` opens only after selected audio
  and a provisional section map exist. Every P3 owns one contiguous 2--3-section
  cohort. Capacity never creates a cohort. A singleton is allowed only when the
  whole title has one section. Examples: 4=2+2, 5=2+3, 7=2+2+3, 8=2+3+3,
  9=3+3+3.
- At G-40 the Planning Cell becomes a read-only rollback point. Each P3 cohort
  id exact-carries into `CDD-V-C1..V-Cn`. P3-C1 may not succeed into V-C2.
- Each Section-Cluster CDD reviews integrated 02B pixels then continues as the
  same-cohort 03V playback successor. One `section_image_motion_worker` remains
  the only 02B/03V output writer for that section.
- Overall alone promotes whole-film truth. Cohort CDDs do not promote across
  cohorts or talk to the Founder.

Every Director lane/stage allows one physical primary and one successor,
maximum two. A third session is HOLD; narrow worker scope or return HOLD. P1,
P2, and P3-Ci never jointly write the same field.

## Founder G0 Through G4 Gates

Normal Founder interaction on Graph v2 is five gates. Existing paid, download,
external, destructive, and release gates remain unchanged.

| Gate | Founder judges | Already closed internally |
|---|---|---|
| G0 | target, audience promise, message/story direction, source/provider/spend envelope | research method, Director/session topology |
| G1 | one complete planning route, section progression, material visual regime | raw references, rejected routes, CDD lane conflict |
| G2 | 02A draft keyframes plus audio animatic, final 02B/03V execution envelope | render-local correction, role coverage, motion readiness |
| G3 | reviewed section-cohort playback and material exception | individual reference loops, every I2V clip, CDD rollover |
| G4 | final master, protected-output disposition, release | shard merge mechanics, non-semantic QC |

Bypassing a gate is HOLD. Non-material operational state is Director-owned
`hold_and_route`. Material escalation still names identity, restricted source,
spend envelope, unresolvable cross-cohort conflict, disposal, upload, or
release.

## Succession, Backpressure, And Same-Session Correction

Succession is a session-router CAS: compact successor pack, zero-turn
successor, native Goal admission, exact pack/schema/frontier validation,
lane-local single-writer CAS, then the source becomes a read-only rollback
point. The successor pack excludes raw pools, URL lists, worker transcripts,
superseded prose, and other-cohort media.

Returns to one Director enter one single-flight queue. Pause new launches when
review backpressure, writer backlog, owner/path collision, provider limits, or
Founder locks exist. A lane with two unreviewed aggregate manifests must not
launch more work. Capacity never overrides that stop.

A correction is a new immutable attempt in the same physical session. Preserve
prior evidence. One review cycle is the initial return plus two targeted
corrections. After submission 3, route upstream or HOLD. Do not open a fourth
child submission, a new physical session, or a parallel writer for the same
work package.

## Model Routing

- Overall Director: exactly one frontier Director route. The logical tier is
  `frontier_director` (`director_deep/xhigh` remains the legacy-pinned alias).
  The target is Grok CLI `grok_director_deep`; Cursor Sol/XHigh is the explicit
  registered alternative for new work. Existing Codex bindings remain historical
  run snapshot evidence only. No provider or model may silently fall back.
- Creative Development Director: legacy-pinned runs keep exactly one separate
  durable, Founder-visible frontier room from startup through actual image,
  Motion Storyboard, and 03V playback review. Graph v2 opens the Planning Cell
  and later the roster-derived Section-Cluster CDDs described above. Overall
  alone owns Founder conversation. Each CDD inspects returns in its write
  scope and sends reviewed milestone packages to Overall.
- `worker_high`: the logical ordinary non-media MV/CF department profile for
  shared reference research, pre-02A development blocks, and Edit shards. New
  assignments prefer the readiness-valid run-resolved Grok CLI provider; the
  immutable run snapshot pins the actual registered provider with no fallback.
- Pre-song: an abstract or first-proposal start opens only the smallest
  disjoint assignments justified by unresolved axes; a director-ready start
  opens only its named gap or none.
- Song: one physical Founder-visible Song Room under CDD for song, lyric,
  selected-audio, audio-motion, or 00A work; it returns only to CDD.
- Post-song research: CDD opens the execution-contract fetch floor of six
  disjoint role-routed integrated
  generalist, World/Still, or Pinterest assignments, then extras only for named screen
  gaps. `idol-world-still-reference-department` owns image-only world/still
  research and `idol-pinterest-reference-worker` owns public-pin visual/
  composition comparison. CDD assigns the registered story/sequence,
  camera/composition, world/object/material-challenge, conditional performance,
  and named-gap checkpoint that matches the actual unresolved screen role.
  World/Still owns broad space/world/object/material
  still research, loads no video instructions, and must perform every
  multi-image comparison from bounded-worker pruning through CDD and Founder review on a
  hash-bound uncropped contact sheet while preserving individual
  image/crop paths and hashes. After CDD reviews the active Pass-B returns, it
  may reopen only the exact owner of a named unresolved gap. Provider-native
  capacity is a ceiling, never an assignment quota, and every return still
  goes only to CDD. A conditional physical
  current-title Member Visual Identity task opens
  only for missing/new/full-restyle cards and returns only to CDD.
  At Direction Alignment a selected Pinterest worker processes only its named
  section cohorts and adds enough readable public-pin candidates to compare the
  unresolved composition functions without a fixed candidate quota. Each
  candidate shows proposed main/support status and an exact Major/Key-Screen/
  likely Core-Cut role; internal FP Close keeps only the individually
  applied/combined pins required by the selected route. It adds one registered physical worker but
  no creative stage, schema family, canonical owner, identity lane, or Founder
  gate. World/Still may hand off only a stable pin pointer. A missing/new/
  full-restyle member receives a comparison set sized to the exact unresolved
  styling/look decision inside the existing identity task; passed cards do not
  reopen.
- Pre-02A development: two to four ordinary blocks, one section by default or
  two to three connected sections, a reviewed maximum of five, and twelve or fewer
  `worker_high` sessions active (or lower provider capacity).
- Provider capacity: probe the current native/headless runtime before launch
  and use its observed registered ceiling together with Director backpressure;
  the repository does not add a provider-specific assignment quota. Hold on
  ambiguous state and never launch merely to fill capacity.
- Provider preference: new non-media assignments prefer the exact run-resolved
  Grok CLI profile selected by the Founder. Do not treat that preference as an
  owner, a static binding, or a fallback. 02B image generation defaults to the
  current Grok native image tools and 03V video remains Grok CLI only. The
  Founder briefing secretary uses Grok CLI `worker_high` and cannot author or
  promote creative truth. Cursor Opus, Fable, Sol, Luna, and Gemini stay unused
  unless the Founder explicitly says to use that route instead of Grok CLI.
- Post-02A: a fresh Founder-visible provider-resolved
  `section_image_motion_worker / worker_high` session owns exactly one physical
  section through 02B, generation, placement, 03V, and playback handoff
  to the continuing CDD. Pixel and playback review open a fresh window on
  returned artifacts only. The selected registered Cursor or Grok physical session uses only
  its own registered media tools and auth. An upstream HOLD returns the exact
  affected scope to that CDD; only its reviewed milestone goes to Overall.
- Separate 04 owner: a fresh Founder-visible Edit Director owns edit/QC and
  merge; disjoint Edit `worker_high` shards on the run-resolved registered
  provider return only to it, and it returns final truth to Overall after
  passed playback.
- Optional manual 04VFX specialist: one locked 04 shot window; no stage
  advancement, schema, automatic dispatch, or master inclusion authority.

The interactive audit/integration model may be Founder-selected, but production
OD, CDD, and Edit Director remain `director_deep/xhigh`. There is no standing
Final Director. Overall may request one bounded adversarial adviser review at a
named boundary; that result is advisory and never becomes the Overall route.
Terra remains outside ordinary production except isolated weekly reporting or a
named forensic exception. Scripts are not creative authors.

Registered Cursor and Founder-selected Grok map the same Overall Director, Creative
Development Director, department-worker, section-owner, dispatch, promotion,
and Founder-gate contracts. A Grok-owned run is not automatically a handoff and
its adapter may not creatively rewrite the common contract.

The Creative Development Director escalates one Director Development Report,
not its transcript or raw pool. It contains the current-work thesis, exact open
Founder decision, curated Decision Set, exact surviving source anchors,
whole-work consequence, rejected reasons, recommended synthesis, material risk,
and smallest next action. CDD owns a separate Founder-visible workbench lineage
through image and 03V review, while Overall remains the only Founder-conversation
owner; the Overall Director inspects the surviving media and alone decides
what is promoted or accepted. Overall does not replay the worker's complete
requirement review unless the milestone evidence is stale, incomplete, or
conflicting.

The unified `idol-html-review-board.v12` accumulates the canonical G-cycle
views in one stable board. `discovery`, `direction_synthesis`, and `fp_final`
remain read-only aliases for historical projections; new decisions use the
G-cycle ids. CDD owns development plus image/03V internal review without
promotion or Founder-conversation authority. The fresh Founder-visible
Edit Director owns the 04 review stage
and shard decisions without promotion authority, then returns one merged package
to Overall. Raw worker pools never enter the board and a signal never infers a
Founder lock.

## Section Dispatch

Before 02A, one development block has one owner and contains one section by
default or two to three connected sections. Grouped blocks must return separate
section rows, reference floors, dispositions, and entry/exit boundaries. Two to
four blocks are ordinary, a fifth is reviewed maximum with a named
  unmergeable-section reason, and twelve or fewer `worker_high` sessions are live (or the
lower provider cap). After 02A, one fresh Founder-visible production session
owns exactly one physical section through 03V and returns only to CDD.
Disjoint owners may run in bounded parallel only when paths and outputs are
disjoint and the lower runtime/provider capacity permits.

The coordinator:

- preserves Front Planning order;
- issues exact source hashes and scope;
- prevents cross-section loading;
- collects section validation and Founder state;
- performs ordered canonical merge;
- reviews whole-video continuity/repetition;
- never uses a whole-video physical worker as a shortcut.

After required 03V handoffs pass, the coordinator opens one fresh
Founder-visible Edit Director task. It owns 04 review and merge; disjoint Edit
`worker_high` section/chunk shards return only to it, and it returns final 04/05 truth to
Overall. A post-02A upstream HOLD returns the exact affected scope to the
continuing CDD checkpoint before the section lineage resumes.

## Department Dispatch Contract

Every creative worker launch states:

- task id, studio role, objective, and recipient director;
- one-section default or justified connected two-to-three-section pre-02A scope;
- interaction surface, logical dispatcher, return recipient, parent lineage,
  session/reuse policy, and active-owner lock;
- Founder epoch, explicit locks, and canonical write authority;
- exact required skills and linked modules as the projector's hash-bound
  dependency inventory, plus the validated Role Context Pack digest and an
  instruction to apply its projected fragments and named creative sources;
- one run-local `review_submission` identity: initial submission 1 or a
  hash-bound targeted correction at submission 2 or 3, with no fourth child
  submission;
- exact song, references, member/product assets, and source hashes;
- separate external-discovery and source-registration permissions plus the
  reference mode; download, capture, or upload needs its own exact permission;
- candidate bound or other decision-ready output;
- required Anti-Flat evidence;
- output location/shape and stop/hold conditions.

The runtime records task id, skill revisions, input digest, result digest, and
owner at launch and return. Every multi-file return exposes one aggregate
manifest with exact child paths and SHA-256 values; the Director Dispatch Index
stores only that pointer, lifecycle state, review disposition, and next action.
The worker does not create a separate self-authored skill-application verdict.
The kernel's [Department Instruction Delivery](references/provider-neutral-studio-kernel.md#department-instruction-delivery)
defines the explicit Workbench Pack mode, its transport acknowledgement and
legacy EOF boundary. A missing or mismatched dispatch record is a hold.

### Reusable Department Recipe And Current Assignment Delta

Every dispatch uses
`references/provider-neutral-studio-kernel.md`. The selected profile/checkpoint,
complete owning skill, and linked reads are the reusable **Department Recipe**
source closure. They pre-author the repeated professional method: for example source
eligibility and comparison for reference research, or prompt translation,
generation, inspection, and return rules for image work. Do not make the
assigning director rewrite that method in every message, and do not copy the
whole skill into the launch prompt. The deterministic projector verifies that
source closure to EOF and emits the exact node's Role Context Pack. That pack
replaces broad receiver rereads; it is not added on top of them.

The assigning director reads the current frontier and authors only the
**Current Assignment Delta**: the exact present gap, current locks and evidence,
task-specific work beyond the recipe, and the current-work proof required for
review. The final launch command has the kernel's exact twelve H2 blocks. A
mechanical layer may bind ids, roles, paths, hashes, permissions, profile/read
sets, output and wake fields, add the fixed headings, and hash the bytes. It may
not select the recipe, write or summarize the Current Assignment Delta, or
claim that the worker applied it.

Canonical command and role text is provider-neutral. Cursor or Grok adapters
transport the same bytes; provider/model names remain runtime metadata. This
does not alias provider-native capabilities: Cursor text agents, Grok
`image_gen`/`image_edit`, explicit APIs, their auth, lifecycle events, and runtime inventory
remain exact to the selected physical session. Provider omission means that
current session's native image surface; API use is explicit, and an unavailable
capability HOLDs without cross-provider fallback.

### Same-Session Checkpoint Progression

The same physical Song, CDD, department, identity, section, or edit session may
advance to its next registered checkpoint only after the current attempt
returns, the declared recipient completes review, any required Founder receipt
is bound, the owner/scope remain unchanged, and the next checkpoint's exact
reads, hashes, activation condition, and fresh input digest are prepared in a
new immutable attempt. This continuation may avoid asking the Founder to repeat
settled input. It may not skip a Founder/stage/paid/external/pixel/playback gate,
infer PASS, widen scope, or silently change owner.

Do not confuse checkpoint attempts with review submissions. `attempt_number`
may continue across legal checkpoints, while one review cycle is limited to the
initial return plus two targeted corrections. After a non-accept review, copy
the Director's complete problem set, invalidated output hashes, correction
action, and acceptance criteria into the next Dispatch. Open a fresh Goal for
only those failed paths and hash-freeze every unaffected output. If submission
3 still fails, route upstream or HOLD; a session, provider, model, or Founder
epoch change cannot create submission 4 for the same work package.

Corroborated hash-only drift is outside that creative submission counter. The
mechanical coordinator alone may write the run-local transport-refresh receipt
when independent current-hash receipts prove the same bytes; this creates no
worker session or Goal and changes no creative bytes. A real governing-input
change returns once to the recipient Director for impact review, while changed
output bytes stay on the ordinary quality/correction route. Never turn a plain
receipt mismatch into parallel worker retries.

This does not relax Director successor control. Legal checkpoint progression
may continue inside the one active physical Director session. On Graph v2,
physical Overall, Planning CDD, Section-Cluster CDD, and Edit Director
replacement is modeled by `scripts/idol_graph_director_session_router.rb`,
keyed by `lane_id + macro_stage_id`. The successor starts as zero-turn
read-only preflight, binds typed-core provider-native Goal evidence, and the
shadow state can model a state-SHA/generation compare-and-swap plus rollback.
The current router always returns `HOLD`; neither a hash claim nor a route
observation grants a prompt, review, canonical-write, Founder-conversation,
promotion, or execution permission. Activation requires typed transition
receipts and an execution consumer that enforces freshness independently.
Graph same-lane succession adds no Founder confirmation or extra Founder gate.

The Graph router mutates only its run-local shadow-readiness proof state. It
does not open a provider session, create a Goal, authorize an operation, author
or promote creative truth, change G0--G4, or alter production artifacts. A provider-native Goal
terminal closes successor admission only and never closes the IDOL assignment.
Legacy-pinned runs keep their byte-stable Boot Pack v3 and legacy CDD router,
including its historical Founder-confirmation sequence; never mix that route
with the Graph router. Any surface that cannot prove its route-specific Goal
admission and single-writer transition remains `HOLD`.

Every dispatched creative worker call, including a provider-resolved post-02A media
lineage, names one reference mode:

- `local_plus_external_discovery` for approved broad local and external search;
- `bound_then_gap_search` for selected evidence first and only named gap or
  challenge search afterward; or
- `bound_only` for an explicit governing lock with no gap search.

Every candidate must carry inspected exact media or a bounded sequence. A
text-only concept is not an ordinary creative return.

Validate at the active boundary: `Explore` checks bounded draft scope and
source/evidence shape; `Promote` adds owner/epoch, input/result digests, source
bindings, applicable schema, and director review; `Execute` adds strict hashes,
permissions, exact output state, and pixel/playback evidence. Do not run
downstream-final validation to gate ordinary discovery.

## Output Boundary

The orchestrator writes only the active pointer, validated Department Dispatch
lifecycle, declared disjoint working shard, deterministic review projection, or
named canonical stage artifact that the current owner contract authorizes. It
does not write creative defaults, replace a worker's evidence, promote an
unreviewed return, or mutate an unaffected run, section, or stage. Every
canonical promotion binds the exact reviewed output path and SHA-256; a held or
discovery-only return remains noncanonical.

The Director Dispatch Index, scoped views, aggregate lane manifests, Director
Boot Pack, and Role Context Pack are pointer-only or derived read models. The index exposes
lineage/session state, scope, hashes, review, board links, holds, canonical
heads, and next actions; the Boot Pack exposes only the active stage, decision
epoch, locks, open/held tasks, active board cycle, and next actions. It excludes
raw pools, full transcripts, and unrelated section artifacts. One mechanical
writer owns each shared index/board manifest and rechecks its source-set digest
before replacement.

Delegation is flat: a worker may use deterministic tools or provider jobs but
cannot create creative grandchildren. An oversized worker returns `split_required`
with exact unowned subscopes, sibling count, disjoint output paths, shared
boundaries, and risk; the recipient director decides whether to dispatch
siblings. New launches pause only when the next assignment consumes pending
returned bytes (especially image hashes), a shared writer is behind, or an
owner/path collision exists. Canonical wait rule:
`automation/harness-execution-contract.yaml`
`live_worker_capacity.provider_capacity.queue_launch_when`. Capacity never
overrides review backpressure or Founder locks.

## Context

Front Planning is the canonical detailed planning report. Do not create a
parallel Front Planning context form.

For every Overall, CDD, Edit, Song, department, or section-owner runtime node,
use one derived exact-node `idol-role-context-pack.v1`. It carries the current
owner, Founder epoch/locks, exact scope/non-scope, dependency edges, selected
instruction fragments, named creative pointers, output contract, HOLD
conditions, return route, and exact provider snapshot.

On Graph v2 the pack is compact: shared kernel plus node-local delta. Project
source id, locator, local path, SHA-256, and function. Exclude URLs, raw
search pools, completed worker transcripts, superseded prose, unrelated
section or cohort media, graph-engineering policy explanations, and other
provider tool detail. If source id, locator, or SHA-256 cannot be recovered,
HOLD; do not infer a URL back into the pack.

A full source hash or a selected fragment hash change invalidates only packs
that bind it; authority, Founder-lock, stage, owner, and provider-binding
changes always invalidate the affected node. This pack has no creative,
review, promotion, generation, or external authority.

The pack binds one immutable content-addressed judgment-profile release, not
only the mutable registry head. Historical outputs keep validating against
their exact release even after a later profile is selected for new work. A
release mismatch, stale profile-value hash, or in-place mutation is `HOLD`.
Profile evolution follows
`wiki/harness-improvement-review-loop.md`: evidence-backed proposal, explicit
overfit guard, representative shadow/pilot validation, then current-pointer
advancement. Never total, average, weight, or percentage-convert the 0--4
vector. Changes to a floor, critical-4 rule, not-applicable rule, Founder gate,
or authority boundary require explicit Founder approval.

When the current run has a valid v3 graph-engineering improvement sidecar, the same pack
may carry its exact role/profile/stage/section-matching compact Founder quality
patterns. Give Directors the current-run whole-work review view and workers
only exact matching section rows. Carry only the authored reason summary,
recurrence count, bounded positive/avoid/action/review signals, applicability,
evidence-rollup digest, and source sidecar pointer. Never carry the raw Founder
quote, decision wording, transcript, full closure, or unrelated patterns. The
semantic edge invalidates only packs bound to the changed compact context and
creates no lock, gate, PASS, or promotion authority.

At 02B, build one active `image_prompt_section` context pack for one section and
one core cut. It contains that core cut's ordered branch roster, the current
branch and its immediate branch siblings, immediate same-section previous/next
core cuts, compact whole-video invariants, title package, selected bindings, and
hashes. It excludes other sections and raw pools.

At 03V, use the active common source pack produced from passed images,
placement, and storyboard boards. Do not perform broad source discovery.

Past-run artifacts, test fixtures, maintenance examples, and another run's
prompt or scene prose are never creative context for the active run. A prior
run may contribute only a named failure mode or invariant after its scene
nouns, actions, camera route, and composition have been removed. Admit actual
creative inputs only from the hash-bound current run, current-title package, or
selected source material.

## Founder Intervention

Preserve the verbatim intervention once at its canonical Founder task event or
intervention/review artifact and route it to the smallest owner. Secondary
sidecars, Role Context Packs, Dispatches, and wake payloads carry only its
pointer/digest and the bounded Director-authored quality context needed for the
exact assignment:

- Founder intervention: Overall preserves the one Founder conversation, then
  routes affected reference, member identity, development, image, or 03V work
  to CDD and its exact existing worker/task;
- Front Planning: target/message/title identity/member allocation/section spine/
  governing reference;
- 01: Official Core event ownership, boundary, exact reference or Founder
  waiver, passed primary image, section direction/staging, and Core still
  camera;
- 02A: immutable 01 Core import plus Branch-only realization/count/still-camera
  composition/input binding;
- 02B: render wording only;
- exact image: pixel defect;
- 03V: subject/camera motion;
- 04: edit-only assembly/timing.
- 04 shard: exact section/chunk edit timing or source range -> Edit `worker_high` shard;
  whole-video edit rhythm, merge, or boundary -> Edit Director.
- 04VFX: rendered shot behavior inside the locked 04 window; any timing,
  source, speed, crop, or geometry change returns to 04.

Invalidate only affected dependents. A Founder direct replacement is the
creative judgment for that scope and receives no second advisory veto.

## Stop Gates

Stop on:

- missing or stale hashes;
- Graph v2 selected without a verified default-switch receipt;
- existing-run Graph v2 write;
- dual active writer;
- historical `harness-*` id used as active authoring;
- P3-Ci succeeding into a different V-Cj cohort;
- third physical Director session on one lane/stage;
- URL or raw pool inside a Role Context Pack, or source id/locator/hash that
  cannot be recovered;
- stale, mutated, or unbound contextual-judgment profile release;
- overlapping P1/P2/P3-Ci or V-Ci write scope;
- G0--G4 bypass;
- review backpressure or two unreviewed aggregate manifests on the same lane;
- same-package correction opened in a new physical session;
- wrong current-title package;
- cross-run or cross-section source leakage;
- test, maintenance-example, or historical-scene source admission;
- unclosed supplied reference;
- missing or mismatched Department Dispatch Contract or required-skill
  application evidence;
- schema or exact-projection failure;
- held/rejected Founder state;
- required input unsupported by the selected surface;
- missing current-job paid/external approval;
- missing pixel or playback pass;
- owner collision.

Report the concrete hold and next smallest action.

## Completion

A stage is complete only when:

- the creative owner authored the truth;
- CDD reviewed every pre-02A worker return and sent the required milestone
  package, the Edit Director reviewed/merged any 04 shards, and the Overall
  Director performed the required promotion or acceptance;
- active schema and hashes validate;
- required reference and asset files were inspected and applied;
- section and complete-video creative review passed where required;
- Founder PASS exists at the correct gate;
- downstream scope and owner are explicit;
- no paid/external/public action was inferred.
