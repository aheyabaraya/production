# IDOL Director Workbench · reference / board / asset routing audit

- Date: 2026-08-04 KST
- Status: dated implementation evidence; design recommendations are superseded
  by `wiki/founder-collaboration-reference-flow-improvement-plan.md` v0.3;
  2026-08-05 connector correction at the end is the current local verdict
- Authority: diagnostic architecture and local implementation evidence only
- Goal: make one visible Overall Director control room useful from discovery through the 02B image-review gate without collapsing stage ownership, reference provenance, or file placement.

> Supersession note: the final plan rejects a shared IDOL/CF MAIN/SUPPORT
> cardinality, authority, or creative-card contract. References to one shared
> visual language below describe the audited prototype state only. IDOL keeps
> its native projection; any CF integration requires a separate CF-owned
> adapter and CF-specific semantics.

## Executive decision

Do not remove Grok's subagent ceiling. Provider capacity is a safety ceiling, not a target:

- provider registration: six ordinary non-root sessions, eight only as a reviewed ceiling;
- interactive pre-02A Workbench: at most four live workers or the lower active-stage/provider limit;
- after exact 02A approval: four disjoint physical-section lineages ordinarily, six only after review;
- every lane requires disjoint byte ownership, a caught-up board/index writer, and no pending director-review backlog;
- workers remain flat. A creative worker does not open creative grandchildren.

This keeps useful parallelism while preventing context dilution, duplicate reference research, conflicting canonical writes, and an Overall Director review queue that grows faster than it can be judged.

## Workbench and Founder board boundary

The Director Workbench is now the visible control shell. It may show:

1. Discovery;
2. Direction Synthesis;
3. FP Final;
4. canonical 01 and 02A state;
5. 02B generation packets and generated-image review state;
6. later 03V/edit status through pointers and the stable board.

The shell does not make one editor the owner of every stage. The Front Planning editor remains a pre-02A writer. After exact 02A approval, a fresh hash-bound Luna/Max lineage owns exactly one physical section through 02B compile, generation, pixel review, and 03V handoff. The Workbench opens the stable `review/founder-workbench.html` projection; it does not silently approve or rewrite the section.

The current native host binds only `runs/ALBUM_KEY/TITLE_KEY/RUN_ID`. It must
not mount `cf/runs` as if CF were an IDOL run. CF requires an isolated adapter
that maps CF00-CF70, CF-owned schemas, and CF-specific review semantics. Ionia
remains a direct CF board example, not proof that the native Workbench can write
CF truth or that IDOL and CF should share creative card fields.

## Pre-generation scene and reference order

The IDOL review material should be read as a scene-build plan, not a gallery.
Every planned beat is displayed in the order the finished work will be made:

- MV: selected-audio/song-section order and whole-film message progression;
- short form: opening -> retention turn -> payoff -> loop/afterimage;
Each IDOL beat must expose, in this order:

1. `SCREEN EVENT`: the visible action/hold and its selected-song audio cue;
2. `MAIN REF`: the source that governs sequence/composition grammar;
3. `SUPPORT JOB`: the exact remaining gap a supporting source fills;
4. `KEY IMAGE MUST CARRY`: camera geometry, composition, body/object action, space/system response, wardrobe/material, light/color, and crop/proportion guard;
5. the selected crop/frame path and SHA-256.

The Scene Build Rail now renders the first four fields on each ordered card. The selected-crop intake exact-copies the fifth field plus direct-follow strength and key-image transfer locks. Main/support assignment remains a human/director decision; the intake converter does not invent it.

Before 02A, call presentation anchors `Major Screen` and `Key Screen`. Official
IDOL `Core Cut` and `Branch Cut` ids begin only when 02A authors them. CF keeps
its own CF-owned presentation and CF40/CF50 vocabulary. This prevents a preview
board from accidentally becoming canonical storyboard truth or a cross-lane
contract.

## Main, supporting, Core, and Branch reference collision check

There is no inherent collision if the system uses one canonical media owner and typed projections:

- a source hub owns the reusable original and first pixel/sequence analysis;
- a run owns only its selected derivative, locator, disposition, transfer, and section/beat binding;
- the same source may be referenced at Major/Key and later Core/Branch levels by path/hash pointers;
- bytes are not copied again merely because the source has another role;
- a governing main reference keeps its scene/sequence/composition grammar;
- supporting references fill named gaps and cannot average, reorder, or dilute the main grammar;
- a whole sheet is navigation evidence only; selected cells/crops are the usable units.

Collision occurs only when two owners rewrite the same canonical bytes, when a support reference is allowed to override a governing main reference, when a whole sheet substitutes for selected crops, or when pre-02A labels masquerade as official 02A cut ids. The updated contracts explicitly block those cases.

## Ionia board result

`CF_LOL_IONIA_PERFUME_001/review/founder-workbench.html` is a useful layout model because its active cycle places member inputs and C01-C07 references alongside the intended CF order. During this audit:

- the manifest's non-schema runtime stamp was removed because the same evidence already exists in `work/cf40-cf50-lock-reproject-receipt-v1.yaml`;
- stale CF40, cast/TX lock, and Founder-intervention hashes were refreshed from current bytes;
- the active revision now supersedes the last revision actually retained in the manifest;
- the board revalidated and re-rendered from its v8 manifest;
- a renderer escape bug that broke all decision JavaScript was fixed and regression-tested;
- fresh-browser console: zero errors; a PASS click updated the visible count from `0 / 17` to `1 / 17`.

One semantic gap remains in the Ionia example: the active cycle contains 71
media rows labelled `diagnostic` and 21 `member_visual` rows, but it does not
expose the CF-native governing-main versus phase-support responsibility.
Therefore it is a good CF layout example, not an IDOL reference-authority
template. Those CF roles require actual commercial-director judgment; this
audit did not invent or bulk-relabel them.

## Fixed file placement

| Asset class | Canonical placement |
| --- | --- |
| unselected local reference cache | `RUN/research/_local_reference_cache/` |
| selected crop/frame unit | `RUN/research/reference-intake/REFERENCE_UNIT_ID/` |
| reference working index | `RUN/research/reference-working-index.yaml` |
| title member visuals by member | `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/` |
| reusable video source and analysis | `source-materials/video-sources/PLATFORM/by-source/SOURCE_ID/` |
| reusable still source and analysis | `source-materials/image-sources/by-source/SOURCE_ID/` |
| single Founder board source/render | `RUN/review/manifests/founder-workbench.yaml` and `RUN/review/founder-workbench.html` |
| temporary planning/Grok roughs | `RUN/generations/front-planning/grok-roughs/JOB_ID/` |
| 02B section export | `RUN/exports/02B/sections/Sxx/` |
| image generation request | `RUN/work/image_generation_requests/sections/Sxx/` |
| generated Branch Cut original | `RUN/generations/branch-cuts/Sxx/BRANCH_CUT_ID/original.png` |
| storyboard boards | `RUN/generations/boards/` |
| video prompt, raw, extra, QC, master, cutdown, shorts | `RUN/generations/video-prompts/` and `RUN/generations/video/{raw,raw/additional,qc,master,cutdown,shorts}/` |
| edit working files | `RUN/work/edit/SECTION_OR_CHUNK/` |
| delivery truth | `RUN/package/final-delivery/manifest.yaml` |

Review boards, contact sheets, and QC views point to the canonical asset. They are not second owners of the same original.

## Review continuity and scanability addendum

The existing version lineage is real and should be preserved. The Ionia board
manifest is at board revision 13 with one active cycle and three superseded,
collapsed, read-only cycles. The stable HTML path, active-cycle id, revision,
supersession chain, and revision-bound decision export already prevent a new
HTML file from being created for every review.

The remaining gap is accumulated-asset legibility rather than board-file
versioning. The current manifest carries 95 media rows: 73 are labelled
`diagnostic` and 22 `member_visual`; none carries a visible reference
disposition receipt. The schema can express primary/supporting/context roles
and applied/combined/held/rejected dispositions, but the current Ionia
projection does not use them, and the renderer does not group or filter media
by those fields.

The source also confirms the Founder's layout observations:

- the member rail is fixed at `220px`, with face and styling stacked vertically;
- facts, provenance, and contracts collapse, but Direction, Screen Proof, and
  the review question all remain expanded by default;
- the toolbar can expand/collapse whole cycles and show undecided cards, but it
  has no media-level used/candidate/held/rejected/superseded filter;
- media role appears as a small caption string rather than a role-grouped
  review lane;
- the native Workbench has a bounded candidate inbox and local
  candidate/selected/hold/rejected statuses, but it opens the stable Founder
  board read-only and does not yet share the board's revisioned asset view.

The final v0.3 proposal therefore preserves the current palette, typography,
card language, image containment, and overall layout character. It changes only
member-space allocation, default text disclosure, visible status/role grouping,
asset-level revision intake, and identical Workbench/HTML projection.

## Verification

- Workbench full check: 71 Python tests passed; policy, JavaScript, DOM, native compile, and native runtime checks passed.
- review-board renderer tests: 13 tests / 169 assertions passed.
- Ionia v8 manifest validation: passed after exact hash/lineage repair.
- managed-shell and generated-v8 structural profiles: both passed after removing the stale `240px`/legacy-anchor assumption.
- Ionia rendered projection: 20 total cards, 17 active decision-bearing cards.
- real-browser Ionia decision interaction: passed, zero console errors.
- real-browser Director Workbench demo: six ordered beats; every card exposed SCREEN, MAIN, SUPPORT, and KEY IMAGE fields; zero console errors.

## Remaining implementation boundary

The IDOL native bridge is ready to open its own stable board and show the
control plane through 02B review. A separate CF-native adapter is required
before the app may bind or write `cf/runs`. Existing CF boards such as Ionia
still need CF-director-authored governing-main and phase-support dispositions
before they become role-complete CF templates; layout alone must not fabricate
those decisions or define IDOL semantics.

## Final v0.3 implementation and integration audit

Date: 2026-08-04 (Asia/Seoul)

### Verdict

- Local R1-R5 implementation and contract integration: **PASS**
- Local deterministic portions of R6: **PASS**
- Production-complete Overall Director room acceptance: **HOLD**
- Commit: **not performed**

The implementation is internally coherent enough to continue local IDOL MV and
short-form development, and the IDOL/CF ownership boundary remains explicit.
It is not yet correct to call the Workbench production-complete or to commit
this final acceptance patch, because the real-run R6 evidence and one active
instruction-surface audit are still incomplete.

### R1-R6 result

| Requirement | Result | Integrated behavior |
|---|---|---|
| R1 automatic PRE-00 selection handoff | PASS | A strict selected-radar schema and atomic, non-overwriting exact-copy builder produce one run-owned hash-bound handoff. The stage registry, execution contract, PRE-00 automation contract, and routing policy all point to the same zero-turn bridge. It adds neither a stage nor generation authority. |
| R2 one-session FP Final and 02A review | PASS | The shared projection permits provisional preparation but fixes the decision order to FP Final then eligible 02A. A failed FP scope cannot appear as approved 02A truth. |
| R3 drag plus instruction canonical patch | PASS locally | Plan and canvas use one conflict-checked transaction and rollback pair. The minimum Founder input is the visible reorder plus one exact instruction. Same-field conflict, stale digest, incomplete receipt, invalidation, board binding, or rollback evidence holds without retry. Completion now requires the returned canonical canvas to be reconciled before board verification; the app no longer re-saves it after validating the rendered board. |
| R4 IDOL post-02A projection | PASS | IDOL 01, 02A, 02B, generated review, 03V, and 04 are read-only pointer/status projections. Generated results remain under the owning section by canonical path and SHA-256. The IDOL board contract no longer uses a CF stage example; CF still requires a separate CF-owned adapter. |
| R5 board continuity and scanability | PASS | The v8 projection now carries a pointer-only asset register, revision/cycle identity, new-since-last-review intake, target/role/state/supersession/receipt bindings, lane-owned filters and groups, collapsed old cycles, image-first disclosures, and adaptive Face/Style comparison space. Workbench and HTML mismatch is a visible stale hold. |
| R6 production acceptance | PARTIAL PASS / HOLD | Transaction, conflict, and deterministic capacity checks pass. The optimized arm64 native host was measured on the actual 8 GB Apple M1: 150 cards used about 109.1 MiB with 17/18 ms frame-interval p50/p95; 500 cards used about 289.7 MiB with 21/33 ms p50/p95. Render p95 was 1/2 ms and both settled at 96 proxies with empty decode queues, passing the 450/750 MiB and large-board 30 fps budgets. A real Founder-selected song comparison, approved real Grok I2I job, and real Sequence Rail contact-sheet pixel review remain open. |

### Minimal intervention and command surface

The minimum interaction contract is now present and bounded:

1. A selected PRE-00 radar creates the handoff without asking the Founder to
   repeat the target, promise, reference previews, must/avoid, or response.
2. A valid start control can warm the Overall and Creative Development rooms
   without sending a model turn.
3. Ordinary work proceeds through compact, hash-bound owner assignments and
   milestone returns rather than repeated status polling or raw transcript
   transfer.
4. A Founder sequence correction needs only the visible drag result and one
   exact natural-language instruction.
5. The correction revises the smallest owner and invalidates only affected
   downstream scope. Missing or stale evidence produces one visible HOLD; it
   does not trigger an automatic retry, wider rewrite, or paid generation.

This is sufficient for minimum-intervention local orchestration. External
generation still requires the exact current-task Founder approval and cannot be
inferred from an ordinary creative request.

### Connection and graph audit

The active semantic graph remains 19 stages and the artifact routing exact-
covers all 19. This audit found and corrected one real connection defect:
`mv_storyboard_direction` was owned by
`idol-front-planning-development-block` in the stage registry but still named
`idol-generation` in artifact routing. Both surfaces now name the same owner.

The resulting layers are cleanly separated:

- semantic graph: fixed stage order, owner, input, gate, and output contract;
- provenance graph: canonical pointer, SHA-256, revision, source disposition,
  dispatch input/result digest, and decision receipt;
- execution graph: prepared, launched, returned, reviewed, then promoted or
  held, with one writer and disjoint-section parallelism;
- invalidation graph: smallest changed owner to affected downstream nodes only;
- review projection: read-only asset/status view with no second media owner.

Scripts continue to validate, exact-copy, transact, or project authored truth;
they do not create creative decisions or convert a structural PASS into a
creative PASS. Rhai is not active infrastructure, and this patch does not
activate it.

There is still no unified typed dynamic run-graph engine that materializes
every live node, edge, lease, digest, state, and invalidation in one runtime.
The current contracts behave graph-cleanly at their boundaries, but claiming a
fully implemented graph engine would be inaccurate. That remains a separate
architecture proposal rather than an R1-R6 acceptance item.

### Skill, instruction, and version management

- Contract-version registry: 97 routes match their current schemas.
- Surface-version registry: 381 tracked surfaces and 36 skills match current
  bytes, revisions, and SHA-256 values.
- Department dispatch requires exact skill/source reads, runtime input/result
  digests, returned output hashes, director review, and promotion or hold.
- IDOL and CF remain separate truth lanes; the IDOL patch does not bind or write
  `cf/runs/**`.
- One repository-wide instruction audit remains on HOLD: root `AGENTS.md` has
  6,019 words against the reviewed ceiling of 6,000. Repository policy forbids
  automatic splitting, compression, or deletion without an explicit current
  Founder instruction, so this audit did not modify it.

### Verification evidence from this pass

- Workbench `make check`: 73 Python tests passed; policy, JavaScript syntax,
  DOM, browser-fallback, capacity, canonical-state, native-agent, raw-terminal,
  department-dispatch, Grok-job, Objective-C compile, and native runtime checks
  passed.
- Review board: 20 tests / 226 assertions passed; managed shell passed.
- PRE-00 radar and handoff: 9 tests / 36 assertions passed.
- Stage graph: 12 tests / 195 assertions passed.
- Artifact routing: 19/19 exact coverage passed after owner-parity repair.
- Department dispatch: 29 tests / 107 assertions passed.
- Director dispatch index: 3 tests / 37 assertions passed.
- Image dispatch: 2 tests / 16 assertions passed.
- 03V section lineage: 7 tests / 35 assertions passed.
- Front Planning state gate: 11 tests / 82 assertions passed.
- Section harness: 10 tests / 66 assertions passed.
- Expert gate, context admission, frontier, current-next, run inventory, shadow
  evaluation, skill-load profiles, execution preset, intervention receipt, and
  active-instruction bias tests passed.
- Actual M1 capacity: optimized arm64 host plus new WebKit process set measured
  about 109.1 MiB at 150 cards and 289.7 MiB at 500 cards; frame-interval
  p50/p95 was 17/18 ms and 21/33 ms, render p95 was 1/2 ms, proxy cache settled
  at 96, and decode queue/active loads settled at zero.
- `git diff --check`: passed.

### Unresolved acceptance blockers

1. No exact Founder-selected real-song pilot and old-window comparison result.
2. No exact current-task external approval and completed real Grok I2I result.
3. No real Sequence Rail contact sheet with recorded pixel inspection.
4. Root `AGENTS.md` remains 19 words above its reviewed ceiling and requires an
   explicit Founder size-remediation instruction.
5. The `main` worktree contains extensive pre-existing unrelated modifications,
   deletions, and untracked run/media files. Nothing from this audit was staged.

The active pointer does not provide a lawful substitute for items 1–3. It names
`runs/aurora-m/su/0801_SU` as an in-progress Front Planning reauthor after a
Founder HOLD, keeps downstream work held before 01/02A, and explicitly sets
image generation, paid generation, and external execution authorization to
false. The only discovered Workbench canvas in historical run storage has an
empty Sequence Rail. Neither may be relabelled as real-song, real-I2I, or real
Sequence Rail acceptance evidence.

Because the Founder requested a commit only when the final audit has no
anomaly, these blockers require a **HOLD / no-commit** result.

## Final dummy-qualified closeout after Founder follow-up

Date: 2026-08-04 (Asia/Seoul)
Supersedes: the preceding pre-authorization HOLD snapshot
Founder boundary: use dummy acceptance, safely remediate the instruction-size
finding, and do not touch SU

### Verdict

- Local implementation and graph-boundary integrity: **PASS**
- Minimum-intervention command surface: **PASS**
- Workbench and stable-board visual/interaction audit: **PASS after one
  accessibility correction**
- Contract, instruction, skill, and version management: **PASS**
- Scoped commit gate: **PASS; no push authorized**
- Real production-output quality evidence: **not claimed by this dummy run**

The earlier HOLD was valid before the follow-up instruction because it required
real external/creative acceptance and root instruction-size authority. The
Founder then supplied that missing size-remediation authority and explicitly
selected dummy testing for this implementation closeout. The real-song, real
I2I, and real contact-sheet items therefore remain later production-run
evidence; they are not relabelled as passed and do not block the scoped harness
implementation commit.

### G0-G5 closeout

| Gap | Result | Closeout evidence |
|---|---|---|
| G0 board compatibility and continuity | PASS outside SU | Active v8 and continuity dummy fixtures validate and render; stale hashes, omitted owner rows, wrong target/order, revision drift, and invalid `new_since_last_review` derivation fail closed. SU was excluded by current Founder instruction. |
| G1 projection assembler | PASS | One deterministic query plan covers reference, member visual, 01, 02A, 02B, generated review, 03V, and 04 owners. The result is pointer-only, exact-copy, receipt-bound, completeness-checked, compare-and-swap written, and rollback-protected. |
| G2 stage feeds | PASS | The PRE-00 handoff carries the selected connection once with zero model turns. FP Final and exact 02A eligibility come from their canonical owner bytes. Post-02A image/playback/edit rows retain exact path, hash, order, target, and state. |
| G3 Founder action round trip | PASS locally | Managed open/refresh/check holds on drift. Exact v8 decision exports ingest once, preserve a run-owned capture, and send only the intake pointer to the existing Overall Director route. Direct sequence changes require the visible reorder plus one exact sentence and preserve smallest-owner and affected-only invalidation boundaries. |
| G4 IDOL/CF boundary | PASS | The IDOL Scene Build Rail contains only full-song audio order and master-derived short-form order. CF remains isolated behind its own adapter and contracts. |
| G5 acceptance | LOCAL DUMMY PASS | Dummy owner feeds, pending current-next, stale-file checks, decision intake, plan/canvas transactions, browser interaction, native compile/runtime, and 150/500-card capacity smoke pass. No external, paid, or production generation was attempted. |

### Minimum Founder interaction now required

```text
select one PRE-00 connection
-> continue the Overall Director conversation
-> optionally move one sequence item + write one exact sentence
-> review one stable board
-> export one PASS/HOLD/REJECT decision set
-> refresh only when a visible stale HOLD appears
```

The Founder does not need to repeat the target brief, maintain a separate media
ledger, reconcile a second board model, poll worker status, or manually route
unchanged sections. Missing evidence produces one bounded HOLD rather than a
retry, wider rewrite, model fallback, or paid action.

### Connection and graph result

The current implementation is graph-clean without claiming a new dynamic graph
engine:

- the semantic graph retains the active 19-stage order and stage-owner gates;
- the provenance graph binds path, SHA-256, revision, dispatch input/result,
  state receipt, and Founder decision lineage;
- the execution graph keeps prepared, launched, returned, reviewed, and
  promoted/held distinct with one writer per artifact;
- the invalidation graph starts at the smallest changed owner and touches only
  declared affected dependents;
- the review projection is a read-only query result, never a second owner;
- Rhai remains inactive and no new runtime layer was introduced.

Scripts author no creative truth. They validate, exact-copy, assemble pointers,
transact already-authored values, or render a derived surface. Structural PASS,
dummy PASS, and browser PASS do not substitute for Founder creative judgment or
pixel/playback acceptance on real outputs.

### Skill and instruction management result

- Root `AGENTS.md` was compacted only under the explicit Founder instruction:
  6,019 words became 5,979, below the reviewed 6,000-word ceiling.
- All protected invariant markers and routing terms remain present.
- The instruction-surface audit passes. Its remaining over-target notices are
  diagnostics, not authorization to split or rewrite another file.
- Department dispatch still requires exact skill/source reads to EOF, bound
  input/result digests, fresh output hashes, director review, and explicit
  promotion or hold.
- Contract registry now routes 99 active contracts. Surface registry tracks
  388 current surfaces and 36 skills with current revisions and SHA-256 values.

### Dummy UI audit

1. **Workbench entry — healthy.** The Founder sees one Overall Director control
   plane, the active stage route, one run binding, one Scene Build Rail, the
   exact-update sentence field, one stable-board action, and one decision-import
   action. The IDOL view contains no CF production-order instruction.
2. **Stable board intake — healthy.** The dummy projection shows accountable
   NEW, ACTIVE/USED, HELD, and OUTPUT counts; canonical media renders from owner
   paths; the member rail and governing/support/output groups preserve the
   current dark visual system and full-frame containment.
3. **Core/Branch judgment — healthy.** Image-first cards keep the compact screen
   consequence, exact question, PASS/HOLD/REJECT, and note field visible while
   full direction, proof, contracts, and provenance remain available in labelled
   disclosure controls.
4. **Interaction and accessibility — corrected and passed.** Filter toggles and
   decision toggles worked, but their selected state was initially visual-only.
   The renderer now synchronizes `aria-pressed` for media filters, pending-only,
   and Founder decision buttons; browser verification confirmed the state change
   and one recorded Branch decision.

The UI audit used non-SU dummy owner records and real local visual assets. It did
not inspect or modify the SU run, call an external provider, or create paid
generation.

### Verification evidence

- Workbench `make check`: 73 Python tests passed; JSON/policy validation,
  JavaScript syntax, DOM, canonical-state, native agents, raw terminal,
  department dispatch, Grok job, Objective-C compile, and native runtime passed.
- Workbench capacity smoke: 150/500-card visibility, pan/zoom round trip, proxy
  priority, and LRU bounds passed.
- Review board: 20 tests / 236 assertions passed.
- Projection assembler: 10 tests / 61 assertions passed.
- PRE-00 radar and exact-copy handoff: 10 tests / 39 assertions passed.
- Founder decision intake: 9 tests / 58 assertions passed.
- Current-next pending projection: 3 tests / 27 assertions passed.
- Execution contract preset: 5 tests / 93 assertions passed.
- Stage graph: 12 tests / 195 assertions passed.
- Artifact routing: 1 test / 6 assertions passed.
- Commit-scoped contract-version registry: 98 active routes passed.
- Commit-scoped surface-version registry: 383 surfaces / 36 skills passed.
- Instruction-surface audit: PASS at 5,979 root-instruction words.

### Residual boundary

No structural or local execution blocker remains for the scoped IDOL harness
implementation. Real-song clarity/speed comparison, real external I2I output,
and real Sequence Rail contact-sheet pixel judgment must still be collected in
their actual production runs before anyone calls those creative outputs
accepted or provider quality proven. That boundary is deliberate and does not
weaken the current commit gate.

## 2026-08-05 Connector Correction And Final Local Audit

### Corrective finding

The final steering review found five executable connections that the preceding
2026-08-04 closeout described as complete before their end-to-end bridges were
actually present. The prior report remains dated evidence; this section is the
current local verdict.

1. The direct-update model route was read-only but was still asked to write
   canonical files. It now returns exactly the five mandatory checks, while the
   native Workbench alone performs the rollback-protected write.
2. The projection assembler depended on a manually present source set. A stable
   run-owned owner index now validates registered canonical feeds and compiles
   that derived source set automatically.
3. The PRE-00 selection handoff could be built but was not consumed by the
   Workbench. Its stable path, source radar, exact-copy bindings, and payload
   hash are now inspected before its bounded payload enters the first director
   context.
4. Projection pending state was not automatically represented in
   `current-next`. The assembler now synchronizes only the same run's
   automation-owned pending entry, with no task, approval, retry, or creative
   authorship.
5. Direct-update completion reopened the stable board outside continuous
   monitoring. It now returns through managed refresh, retaining digest,
   revision, active-cycle, and stale-HOLD checks.

### Final local verdict

- Minimum-Founder-intervention route: **PASS**. The minimum shape is one PRE-00
  selection, ordinary Overall Director conversation, optional visible move plus
  one exact sentence, and one stable-board decision export.
- Semantic, provenance, execution, invalidation, and review-projection graphs:
  **PASS at their declared boundaries**. No dynamic graph engine is claimed,
  and Rhai remains inactive.
- Skill and instruction route: **PASS**. The active policy and handoff skill
  name the stable owner index, derived source set, read-only director checks,
  sole native writer, affected-only invalidation, and same-run pending
  projection. The scoped commit registry contains 99 routes and 385 current
  surfaces / 36 skills. The full dirty worktree also validates at 100 routes
  and 390 surfaces, but its unrelated routes and surface changes are excluded
  from this commit.
- Dummy end-to-end and rollback: **PASS in local tests**. Success reaches a new
  stable board revision and current-next projection; stale-owner failure
  restores the prior plan, canvas, board, source-set, pending, current-next, and
  receipt state.
- SU boundary: excluded from content inspection and modification. Only the
  pre-recorded opaque path-level status signature may be compared at closeout.
- Real production quality: **not claimed**. Real song, image, motion, edit, and
  pixel/playback acceptance remain gated by their owning run and Founder
  review.

### Verification evidence for the correction

- Workbench `make check`: 74 Python tests passed, including exact parity among
  the JavaScript allowlist, native capabilities, bridge schema, and method
  contract; all JavaScript smoke checks, Objective-C `-Werror` compile, and
  native runtime checks passed.
- Projection assembler and direct-update transaction: 13 tests / 97 assertions
  passed, including missing-source-set owner compilation, same-run
  current-next synchronization, successful integration, stale-owner HOLD, and
  full rollback.
- PRE-00 radar and stable handoff creation/inspection: 10 tests / 47 assertions
  passed.
- Current-next pending projection: 3 tests / 27 assertions passed.
- Founder intervention receipt: 2 tests / 8 assertions passed.
- Instruction-surface audit: 11 tests passed; active-instruction bias: 6 tests /
  39 assertions passed; artifact routing: 1 test / 6 assertions passed.
- Scoped contract-version registry: 99 active routes passed. Scoped
  surface-version registry: 385 surfaces / 36 skills passed. The separate full
  dirty-worktree result is 100 / 390 / 36 and is not staged by this audit.
