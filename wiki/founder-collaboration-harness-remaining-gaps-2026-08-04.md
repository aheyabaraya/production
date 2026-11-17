# Founder Collaboration And Harness — Remaining Gaps Only

Status: locally implemented and dummy-qualified after 2026-08-05 connector correction; production creative evidence remains run-time gated
Date: 2026-08-04; corrective closeout 2026-08-05
Scope: IDOL full-song MV and master-derived short-form only
Boundary: CF remains isolated under `cf/` and is not part of this backlog

This supplement preserves the work that was missing or only partially
implemented at the time of the original audit. It does not replace active
policy, stage truth, or the broader improvement-plan history.

The original findings below are retained as the implementation backlog that
was audited. The 2026-08-05 corrective closeout at the end is the current
result and supersedes earlier local closeout claims where they described a
connection before its executable bridge existed.

## Finding

The current change is not Workbench-only, but it is still projection-heavy.
The visual review schema, renderer, reference-intake surface, fixed path layout,
and managed stable-board opening have been changed. The harness-wide intake and
return loop that should feed those surfaces is not complete yet.

The missing production chain is:

```text
stage owner / index / worklist / review receipt
-> deterministic review projection assembly
-> one stable manifest and HTML
-> Founder decision intake
-> smallest canonical owner patch
-> affected-only invalidation and current-next refresh
```

## Already Reflected And Excluded From This Backlog

- `AGENTS.md` already defines four ordinary disjoint post-02A production
  lineages and six as the reviewed ceiling, with lower runtime capacity and
  director-review backpressure taking precedence.
- The native Workbench can open the run-owned
  `review/founder-workbench.html` in a managed review window.
- Reference intake v2 already preserves selected crop identity, source-fragment
  hash, direct-follow strength, and key-image transfer facts.
- The review-board schema and renderer already contain the proposed adaptive
  Face / Style allocation, image-first card summary, collapsed detail blocks,
  role groups, state filters, revision fields, new-media fields, and deferred
  loading for closed cycles.
- The Workbench artifact-layout contract already fixes reference, member,
  generation, video, review, edit, and delivery locations and keeps media bytes
  at one owning path.
- The IDOL Workbench path contract already rejects `cf/runs/**`. No common
  IDOL/CF reference-authority contract is needed.

## G0. Repair The Current Review-Board Change Before Promotion

This is a release blocker, not a new feature.

Current evidence:

- `ruby scripts/tests/idol_html_review_board_test.rb` fails all 13 tests because
  the Ruby renderer requires `review_assets` for every v8 manifest even though
  the schema requires it only when the continuity profile is active.
- The current SU stable-board manifest fails validation with
  `manifest missing required keys: review_assets`.
- No active YAML/JSON manifest currently uses
  `founder-workbench-continuity-v1`; only the schema and renderer contain it.
- `ruby scripts/validate_harness_surface_version_registry.rb` reports stale
  hashes for both `scripts/idol_html_review_board.rb` and
  `schemas/html-review-board.schema.json`.

Required completion:

1. Keep legacy/current v8 manifests valid unless they explicitly activate the
   continuity profile.
2. Add one valid continuity fixture and negative fixtures for missing owner
   receipts, wrong target bindings, stale hashes, wrong FP/02A order, omitted
   assets, and incorrect `new_since_last_review` state.
3. Prove both the existing SU manifest and the continuity fixture can validate
   and render to the one stable path.
4. Update the owning surface revisions and SHA-256 rows in the same reviewed
   patch.

## G1. Build The Harness-Owned Review Projection Assembler

There is currently no producer for `review_assets`. Searching the repository
finds the field only in the review-board schema and renderer. Therefore the new
filters and groups have no active harness feed.

Do not create a second canonical asset register inside the board. Keep
`review_assets` as a derived, pointer-only projection assembled from the
existing owners:

| Incoming material | Existing owning truth | Required board projection |
|---|---|---|
| Selected reference unit | Reference Working Index plus FP/01R disposition and section binding | Exact media identity, function, target, order, disposition, and receipt |
| Current-title member visual | Passed title-local member manifest | Member, appearance role, applicable target, path, and hash |
| 01/02A/02B material | Current stage artifact, approved section shard, prompt/request binding | Section/Core/Branch ownership and current eligibility |
| Generated Branch image | Image-generation section worklist, dispatch ledger, returned output, and Generated Branch-Cut Review | Original path/hash, pending or reviewed state, section/Core/Branch target |
| 03V material | Placement, storyboard, video prompt, and playback-review owners | Board/playback path, target, review state, and receipt |
| Edit and delivery media | 04/04FX/05 owner and edit-review evidence | Edit/output role, target, review state, and lineage |

The assembler must:

- exact-copy pointers, hashes, ids, declared order, and owner-authored states;
- never invent a reference role, disposition, creative use, or approval;
- compute `new since last review` from the last Founder-reviewed manifest and
  intake receipt against the current owner paths/hashes, rather than trusting a
  manually typed flag;
- bind an upstream source-set digest and prove that every eligible incoming
  asset is represented or explicitly held;
- store one media identity once and allow multiple typed bindings without
  duplicating the original bytes;
- fail closed when an eligible owner row is omitted, stale, multiply owned, or
  missing its state receipt;
- send unresolved new items to the Director Dispatch Index and `current-next`,
  so they cannot be hidden merely by a board filter.

The stable manifest remains a board-coordinator projection. The Reference
Working Index, generation worklist/ledger, stage artifacts, and review receipts
remain the actual owners.

## G2. Finish The Stage Handoffs That Feed The Projection

### G2.1 PRE-00 selection handoff

The agreed direct handoff from one Founder-selected PRE-00 target connection to
the Song Room and asynchronous visual preparation is not implemented. Current
search finds it only in the improvement-plan document.

Add one hash-bound handoff in the existing PRE-00 owner that carries the locked
target, audience promise, reviewed preview references, must/avoid, and Founder
response into both rooms without introducing a new stage or repeating the
brief.

### G2.2 Ordered FP Final and exact 02A review

This is only partially implemented. The schema and browser code contain
`fp_final -> exact_02a` display order and disable 02A buttons until local FP
PASS choices exist, but there is no active continuity manifest, canonical
projection producer, or end-to-end test.

The canonical stage owner—not browser JavaScript—must determine which exact
02A scope is eligible after the matching FP Final intake passes. The board then
projects that eligibility.

### G2.3 Post-02A section result projection

The Workbench currently opens the stable HTML, but neither the Workbench nor
the board renderer consumes the image-generation section worklist, dispatch
ledger, Generated Branch-Cut Review, 03V playback, or 04 review owners.

Add source adapters to the assembler so a returned 02B image can appear under
its exact section/Core/Branch without copying it. A result must first enter its
generation ledger/worklist, receive a byte hash and pixel review state, and
only then appear in the review projection.

The current asset vocabulary also needs one narrow correction before edit
projection: `lane_role` permits `edit_output`, but the review asset/media role
enum does not represent an edit output directly.

## G3. Complete The Founder Action And Refresh Round Trip

The current `reviewBoard.open` bridge opens a read-only file and returns its
path. It does not yet coordinate board regeneration, source drift, decision
intake, or affected-owner refresh.

Required loop:

```text
owner bytes change
-> owner index/worklist and current-next change
-> board assembler rebuilds the same manifest/HTML path
-> Workbench opens or refreshes the exact manifest revision
-> Founder decision export is ingested once
-> existing founder_direct_update or stage decision route patches the smallest owner
-> only affected dependents are invalidated and reprojected
```

Specific missing behavior:

- detect manifest/source hash drift while the managed board window is open and
  show a refresh hold rather than allowing review of stale pixels;
- ingest the exact board decision export through the existing Founder review
  intake instead of leaving it as browser-local state;
- refresh only affected sections after a section owner returns;
- preserve the last passed manifest/HTML rollback pair until the affected route
  closes;
- handle external-file changes with compare-and-swap or an explicit merge hold.

Workbench drag/reorder is also still only a canvas-pending action. Connect a
move plus the Founder's ordinary-language instruction to the existing
`founder_direct_update` receipt, smallest-owner patch, and affected-only
invalidation. Drag position alone must not silently author creative meaning.

## G4. Remove The Remaining IDOL/CF Wording Leak

The path boundary is correct, but the current IDOL Scene Build Rail empty-state
copy still explains a CF `subject -> need -> proof -> objection -> action`
order beside MV and short-form order.

Remove that CF production instruction from the IDOL Workbench. Keep only:

- selected-audio order for the full-song MV;
- opening/retention/payoff/loop when arranging a master-derived short-form cut;
- a short notice that CF uses its separate `cf/` adapter and contracts, if a
  boundary notice is necessary.

CF review mechanics may be improved later inside `cf/`, but this IDOL patch
must not author or normalize CF card semantics.

## G5. Complete Production Acceptance

After G0–G4, run only the still-missing acceptance work:

1. one real Founder-selected song from PRE-00 selection through FP/02A review;
2. one real generated Branch result entering the ledger, pixel review,
   section projection, Founder intake, and affected-only refresh;
3. one real Grok image-to-image job from a selected canonical parent;
4. one real Sequence/Scene Build contact sheet with visual inspection;
5. external-file reload/merge and transactional plan-plus-canvas creation;
6. 150-card and 500-card board tests for load, filter, expand/collapse,
   pan/zoom, proxy behavior, and M1 memory pressure.

Do not raise Grok/Luna ceilings or redesign the current visual style to pass
these checks.

## Implementation Order

1. Fix the renderer compatibility regression, tests, and stale surface hashes.
2. Implement the harness-owned projection assembler and completeness check.
3. Connect pending projection items to Director Dispatch Index and
   `current-next`.
4. Add PRE-00, ordered FP/02A, generated-result, 03V, and edit source adapters.
5. Add decision intake, smallest-owner patching, scoped refresh, and stale-file
   handling to the managed Workbench loop.
6. Remove the remaining CF instruction from the IDOL UI.
7. Run the real-flow and large-board acceptance checks.

## Completion Criteria

The remaining work is complete only when:

- the current SU board and a continuity-profile fixture both validate and
  render;
- every eligible reference or generated result is accounted for from its
  harness owner, even if it is held, rejected, or superseded;
- an unreviewed incoming item is visible in both `current-next` and the board;
- a returned 02B image appears under its exact section by pointer/hash without
  a second media copy;
- Founder decisions and moves reach the existing canonical owner and invalidate
  only affected downstream scopes;
- Workbench and standalone HTML show the same manifest revision and hold on
  drift;
- IDOL UI and fixtures contain no CF production-order semantics;
- the review-board, Workbench, registry, real-flow, and large-board checks pass.

## 2026-08-04 Implementation Closeout

The Founder subsequently authorized safe instruction-size remediation,
required dummy testing, and explicitly prohibited touching SU. Under that
current instruction, G0–G4 are implemented and G5 is locally qualified without
relabeling dummy evidence as production creative proof.

| Gap | Result | Current evidence and boundary |
|---|---|---|
| G0 review-board repair | PASS outside SU | Active v8 and continuity fixtures validate and render to one stable path; asset omission, stale hash, wrong target/order, revision drift, and new-state derivation fail closed. SU is neither read nor modified in this closeout; its status signature is checked only as an opaque path-level invariant. |
| G1 owner-backed projection | PASS | `idol_review_projection_assembler.rb` exact-copies eight registered owner classes into one pointer-only asset register, verifies owner/state-receipt hashes and coverage, writes a derived pending index, and detects owner or query drift with compare-and-swap rollback. |
| G2 stage handoffs | PASS | PRE-00 selection has one zero-turn hash-bound handoff; FP Final and exact 02A order comes from owner bytes; generated review, 03V, and 04 outputs project by canonical pointer/hash without media copies. |
| G3 Founder round trip | PASS locally | Managed open/refresh/check uses the same stable board; exact v8 decisions ingest idempotently and only the intake pointer enters the active Overall Director route. Direct reorder plus one exact instruction uses the existing Founder intervention, smallest owner, affected-only invalidation, and transactional rollback contracts. |
| G4 IDOL/CF wording boundary | PASS | The IDOL Scene Build Rail describes full-song audio order and master-derived short-form order only. CF remains a separate `cf/` adapter and truth lane. |
| G5 acceptance | LOCAL DUMMY PASS / REAL OUTPUT NOT CLAIMED | Dummy owner feeds, current-next, decision round trip, stale-file holds, plan/canvas transactions, 150/500-card capacity, native compile/runtime, and browser interaction pass. No external generation or paid action was authorized. Real-song comparison, real I2I output, and real contact-sheet pixel judgment remain production-run evidence, not a structural blocker for this scoped implementation commit. |

### Closed chain

```text
canonical owner/index/worklist/receipt
-> hash-bound projection source set
-> deterministic completeness + drift check
-> one stable manifest and HTML
-> Founder decision export
-> idempotent run-owned intake
-> existing Overall Director / smallest-owner route
-> affected-only invalidation
-> refreshed board revision or visible HOLD
```

This chain preserves the graph boundary: semantic stage order, provenance,
execution state, invalidation, and review projection remain separate. The
projection creates no creative truth, stage approval, media copy, task, retry,
external call, or paid-generation authority.

### Minimum Founder command shape now available

1. Select one PRE-00 connection once; the Song Room and CDD visual preparation
   receive the same exact handoff without a duplicate brief or model turn.
2. Give ordinary direction in the Overall Director room; departments receive
   bounded hash-bound dispatches only when a named gap exists.
3. For a sequence correction, move the visible item and write one exact natural
   sentence describing the reason and screen consequence.
4. Review the same stable board and export one PASS/HOLD/REJECT decision set.
5. Reopen the board only when a visible stale HOLD requires reprojection.

No extra Founder form, manual asset ledger, second board, or status-polling loop
is required for the tested local path.

## 2026-08-05 Corrective Final Closeout

The final steering audit found that the prior dummy-qualified closeout still
described five connections more strongly than the executable path justified.
Those connections are now implemented and covered by success plus fail-closed
tests:

| Corrected connection | Current executable behavior |
|---|---|
| Direct Founder update writer | The Overall session remains read-only and returns exactly five required checks. The native Workbench is the sole deterministic writer for the exact Founder sentence, visible sequence order, plan/canvas pair, intervention receipt, affected-only invalidations, board revision, and rollback. |
| Projection source registration | One stable run-owned owner index validates canonical owner paths/hashes and compiles the derived source set. Missing, stale, omitted, or multiply owned feed evidence holds before projection. |
| PRE-00 to Workbench context | The stable selection handoff is inspected against the current selected radar, including exact-copy bindings and payload hash, then injected into the first bounded director context without a duplicate Founder brief or model turn. |
| Pending projection to current-next | The assembler synchronizes only the same run's automation-owned pending entry in `automation/current-next.yaml` and `.md`; it creates no task, approval, retry, or creative truth. |
| Stable-board monitoring after update | Direct-update completion returns through managed `refresh`, so the existing window remains checked against owner/query digest, revision, and active cycle instead of reopening an unmonitored board. |

The non-SU dummy flow proves the success path from registered owners through a
stable board revision and direct update, and the rollback path proves that
stale owner drift leaves the previous plan/canvas/board/current-next set intact.
The skill and policy surfaces now name these exact ownership boundaries. Real
song, image, motion, edit, and pixel/playback quality remain the responsibility
of their production runs and Founder gates; this closeout does not relabel
dummy evidence as creative acceptance.
