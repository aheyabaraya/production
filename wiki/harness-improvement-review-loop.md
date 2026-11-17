# IDOL Graph Engineering Improvement Review Loop

Use this optional loop only for material rework. It is a run-owned review
sidecar, not a production stage, creative artifact, readiness gate, release
gate, or permission to edit shared graph-engineering surfaces.

## Canonical Record

Keep one stable file:

```text
RUN/review/harness-improvement-review.yaml
```

Validate it against:

```text
schemas/harness-improvement-review.schema.json
```

```bash
scripts/idol-video-python scripts/validate_json_schema.py \
  schemas/harness-improvement-review.schema.json \
  RUN/review/harness-improvement-review.yaml
```

The record points to existing Founder interventions, review decisions,
artifacts, and playback evidence by path and SHA-256. It does not copy or
replace those canonical decisions.

This sidecar is `run_followup`, not a `standing_constraint`. A closed run does
not write skills or policies. Promotion into a standing owner requires Founder
approval and the overfit guard named in
[`harness-standing-constraint-index.md`](harness-standing-constraint-index.md).

## Material Trigger

Create or update the file when:

- work returns to an earlier owning stage;
- the same failure recurs after a correction;
- already accepted truth is invalidated;
- review or generation cycles repeat without resolving the same screen gap;
- the review material lacks the evidence needed for a decision;
- the run resets, is discarded, or enters a long hold;
- the Founder explicitly asks to preserve a learning.

Do not open it for ordinary exploration, materially different candidates, or
one provider-variance rerun without a reusable workflow question. File,
version, candidate, time, or cost counts may prompt review, but they do not
diagnose cause, block a stage, authorize cleanup, or promote a graph-engineering change.

## Issue Review

For each issue:

1. Record the detection stage and the earliest owner whose truth changed.
2. Fold repeated cycles under one stable `recurrence_key`.
3. Separate `current_run_resolution` from `harness_followup`.
4. Cite resolution and later verification evidence by path and SHA-256.
5. State an overfit guard before proposing a shared instruction, policy,
   schema, skill, review-surface, or script change.

Resolving the current run does not prove that a shared graph-engineering change works.

## Closeout And Follow-Up

At normal completion, 05 may point to the record through the existing optional
`supporting_records.harness_improvement_review` key. The pointer does not change
package readiness or release gates. A reset, discard, or long hold closes the
same record directly because the run may never reach 05.

Follow-up states are:

```text
none
-> observe
-> proposed
-> founder_approved
-> applied_awaiting_validation
-> verified
```

`rejected` may close a proposal at any point. `verified` requires evidence from
a later suitable run. Promotion into `decision-log.md`, style/performance
memory, or shared graph-engineering surfaces remains a separate reviewed maintenance
action.

Scripts may validate schema, hashes, counts, and states. A human or assigned
model authors root cause, proposal, overfit guard, and verification judgment.

Company Ops IDOL harness-maintenance work reuses this loop. Do not create a
competing loop. Routine proposals go to the reporting Director. Governing
instruction, policy, schema, skill, or provider changes require independent
review and Founder approval. Proposer-only approval, active-Goal hot swap,
automatic preference promotion, and machine-authored creative truth remain
forbidden. Maximum three submissions including the initial return; a remaining
defect routes upstream or HOLD.

## Provider Evidence And Execution Boundary

A provider-authored response and a provider lifecycle receipt prove different
facts and must remain separate. Persisted response bytes plus SHA-256 prove
what the assigned model returned; they do not prove that the provider Goal,
model, session, tool, or capability route was the admitted one. A raw provider
event plus its adapter attestation proves only the exact lifecycle facts it
binds, such as provider, runtime surface, native Goal identity, goal-text hash,
terminal state, and last event. It does not prove the response contents,
creative quality, output persistence, or Director acceptance. A provider's
self-report cannot replace the raw event, and an event or adapter attestation
cannot replace the returned response bytes.

Treat model execution as evidenced only when one correlated chain exact-binds
the Department Dispatch, provider-native Goal terminal event, its raw provider
event and adapter attestation,
registered provider/capability snapshot, prompt and input digest, exact-node
Role Context Pack/source-set digest, persisted response or media bytes, output
manifest/path/SHA-256, and recipient Director review. Media work additionally
requires inspection of the actual pixels or playback; paid, download,
external, destructive, and release actions additionally require their own
exact authority receipts. A script may validate this correlation. It may not
turn lifecycle evidence into a creative score, PASS, promotion, or Founder
decision.

## Graph Judgment Profile Evolution

Use this same review loop to maintain checkpoint-specific 0--4 judgment
profiles. A profile update is justified by decision evidence, not by a desire to
raise or lower a generic quality score. Eligible signals are:

- the same Director correction reason recurring against hash-bound outputs;
- a Founder G0--G4 PATCH/REJECT or explicit correction that reveals a criterion
  missed a material decision;
- an upstream judgment marked eligible for Director review whose exact pixels
  or playback later exposes the same false positive;
- a hold or low criterion result later shown to be a false negative because the
  same creative bytes pass without a relevant creative change;
- the same reason recurring across suitable runs or section contexts after
  provider variance and transport faults are separated.

Provider latency, token use, file count, one unusual title, one model's
self-report, or a schema failure alone is not criterion evidence. Keep the
current-run correction separate from the shared-profile proposal.

Every proposal names the affected profile, checkpoint, criterion, observed
failure mode, exact evidence bindings, counterexample or negative-control
cases, and an overfit guard. Remove current-title nouns, members, scene actions,
camera solutions, and reference-specific taste from a reusable criterion. Test
whether the proposal would wrongly reject a materially different but valid
route and whether a narrower evidence hint, review question, or role-specific
profile would solve the problem. If the evidence does not generalize, keep it
as run-local Founder quality context.

Record that proposal in the optional typed
`issues[].harness_followup.judgment_profile_evolution` object rather than only
in free prose. The object has no current-pointer effect and cannot authorize
automatic tuning; floor, critical-4, and not-applicable changes require explicit
Founder approval.

Profile releases are immutable and content-addressed:

```text
observe -> proposed -> reviewed authority decision
-> new immutable profile release
-> representative shadow validation
-> Founder-selected real-song pilot
-> Founder-authored approval
-> current-profile pointer advancement for newly admitted work
```

The current bootstrap/current-pointer set is exactly seven checkpoint profiles:

| profile | maintained decision surface |
|---|---|
| `pre_fp_storyline` | pre-FP target, audience promise, message, and whole-film storyline lock |
| `reference_candidate` | actual still/motion unit function, transfer boundary, composition, and provenance |
| `front_planning_close` | full route, Major/Sequence/Core progression, motion, composition, and four-role synthesis |
| `draft_keyframe_proof` | existing `fp_hero_core` pixels and audio-animatic proof before final 02B |
| `pixel_02b` | actual generated Production Cut pixels |
| `playback_03v` | actual section playback, motion, camera, landing, and optional performance readability |
| `edit_04_playback` | section and whole-film edit playback |

Target empathy and message are authored and scored only in
`pre_fp_storyline`; later profiles inspect alignment or visible realization of
those locks rather than re-scoring them. Motion and still composition remain
critical `4` wherever the selected profile declares them, and performance
readability may be `not_applicable` only when the exact title has no
performance job. No result is aggregated.

Adding or removing a shared profile is itself a registry and authority change;
it does not happen as an implicit criterion edit and requires explicit Founder
approval plus the same immutable release and validation discipline.

The current registry pointer must exact-bind one
`idol-graph-creative-judgment-profile-promotion.v1` artifact. The seven initial
shadow releases are the only `bootstrap_shadow_seed` allowlist and grant neither
execution nor default-cutover authority. Every later pointer change binds the
exact old and new release pointers plus proposal, shadow, pilot, and
Founder-authored approval receipts in predecessor-hash order. Each phase must
bind one typed evolution-evidence artifact: a proposal names generalized gaps
and an overfit guard; shadow evidence binds one distinct old/new contextual-
judgment pair to each representative pass, correction, hard-gate, and outside-
scope case under the same scope, input digest, stage, applicability evidence,
performance mode, and evaluated source bytes; the outside-scope case also binds
its own exact evidence and observable scope reason, plus
a not-applicable case whenever the profile supports it and an independent
Director review; pilot evidence names the Founder-selected real song, a
decodable selected audio stream of at least 30 seconds, a structured song-
identity artifact that exact-binds those audio bytes, new-release judgments, a
hash-bound run-local Founder intervention selection receipt, and its Director review; and
Founder approval exact-binds the new profile-value hash plus the value hash of
the verbatim Founder intervention receipt. The judgment author session may not
be the Director review session. Each candidate judgment must pass the complete
contextual validator with a genuine prepared/launched Graph projection pack and
the exact registered provider snapshot. The Director review must use its own
exact-node Director Role Context Pack, generated from the Director's
Goal-admitted launched Dispatch and active frontier profile, rather than
reusing the judgment author's pack or broad worker context. Its hash-bound
review-input projection contains the exact old/new releases, typed phase
payload, and complete set of judgment hashes; the returned Graph Director
Dispatch must use that projection digest as its input digest and exact-bind its
full output manifest plus separate returned review bytes. For ordinary
production review, the same rule projects only the exact candidate output
bytes/path/SHA-256, output manifest, bound judgment and profile release/value
hash, active locks and source/evidence locators, neighbor/boundary handles,
prior correction requirements, and actual pixel/playback targets needed at
that node. Raw search pools, full URL lists, worker transcripts, unrelated
cohorts, and another provider's profile stay out. A launched-only Dispatch or
a compact projection without opening the actual governed bytes cannot close
review.

The profile-evolution validator enforces its specialized Director Role Context
Pack and review-input manifest. Ordinary Graph production review uses
`scripts/idol_graph_production_review.rb` and the role-local
`exact_returned_work_review` checkpoint. Its input is derived from the exact
worker return, judgment, profile and selected context; its separate Director
return binds the input digest, independent session, launched context pack,
inspection observations and full output manifest. The Graph projector requires
this returned review before projecting a promotion. Existing exact stage
review contracts and Founder gates remain canonical. Structural coverage of
this consumer does not prove actual media inspection, creative quality or
production/default-cutover readiness at every checkpoint.

A generic file pointer, container-only media duration, extension-only audio
file, or author-role self-claim is insufficient. The validator checks those
bytes but never advances the pointer itself.

Never edit or replace an old release. Its path, file SHA-256, and profile-value
SHA-256 remain bound to historical Role Context Packs and judgments. Advancing
the current pointer does not rewrite, regrade, invalidate, or reopen them.
Shadow validation covers the profile's applicable planning/reference/image/
playback checkpoints, an expected pass, a correction case, a not-applicable
case when supported, a hard-gate case, and a counterexample outside the
criterion's intended scope. Under the current promotion contract every
non-bootstrap shared current-pointer change, not only a change heuristically
called material, requires a suitable Founder-selected real-song pilot and
Founder-authored approval. If a proposal does not justify that validation, it
remains run-local and the current pointer does not move. This profile-release
pilot is separate from the system-level real-song A/B and exact default-switch
receipt required to activate Graph v2.

An assigned Director may propose and review changes to evidence wording,
observable claims, correction questions, or acceptance-evidence guidance.
Explicit Founder approval is required before changing any minimum floor,
critical-4 designation, not-applicable rule, Founder G0--G4 stop, paid/external/
destructive/release gate, or role/authority boundary. No profile or maintenance
report may total, average, weight, rank by aggregate, or percentage-convert the
0--4 vector. Scripts may validate and compare declared release bytes; they
never author a criterion value, tune a profile, or declare creative PASS.

## Automated Graph Range And Founder Stops

The current `idol_graph_run_controller.rb` is a shadow, read-only dry run. It
calculates only one of five next states: `dispatch_or_resume_model`,
`await_director_review`, `route_bounded_correction`,
`await_founder_decision`, or `hold`. It does not launch or resume a provider,
create a Goal, send a prompt, write an event/ledger, author a score or review,
advance a profile pointer, promote an artifact, or perform paid/external work.
Raw provider events therefore cannot turn its intent into execution.

After a separately verified cutover, automation may schedule admitted nodes
inside an existing authority envelope, collect fully evidenced returns, route
them to the exact recipient Director, retry bounded same-owner corrections,
apply Director-session CAS succession, preserve backpressure, and invalidate
only affected descendants. It still stops for G0 target/message/story
direction and source/provider/spend envelope; G1 route selection; G2 draft
keyframe plus audio-animatic and final execution envelope; G3 reviewed cohort
playback/material exceptions; and G4 final master, protected-output
disposition, and release. It also stops for any expansion of paid, download,
external, destructive, output-count, or publication authority. Shared profile
pointer advancement is a separate Founder-approved maintenance action, not an
ordinary MV gate. Until the event writer, provider executor, provider-native
lifecycle proof, representative real-song pilot, and exact default-switch
receipt are closed, Graph remains `shadow_not_default` and all such execution
claims remain HOLD.

## Founder Creative-Feedback Shadow Closure

v3 may record an optional `founder_creative_closures[]` array on the same
sidecar. This is still `run_followup`. It is not a production stage, G-cycle,
review board, numeric score, machine judge, or raw-feedback memory store. Missing, unbound,
or unsolved rows hold only the sidecar record. They do not hold PRE-00 through
05, package readiness, or release.

A v3 sidecar may contain ordinary improvement `issues`, Founder creative
closures, or both; at least one of the two arrays is non-empty. Feedback-only
capture must not invent a helper recurrence or graph-engineering defect merely to satisfy
the older v1 issue shape.

Historical v1 and v2 documents remain readable through the frozen
`schemas/harness-improvement-review-v1-legacy.schema.json` and
`schemas/harness-improvement-review-v2-legacy.schema.json` readers. New
authoring uses `idol_harness_improvement_review.v3`. The Ruby sidecar validator
selects the schema from `schema_version`; use
`scripts/validate_run_followup_sidecar.rb` for every version. The direct
JSON-schema command above is the current v3 authoring check only.

When a Founder creative response is captured, the Director authors the
structured closure. Founder comments stay natural language. The Director marks
interpretation as hypothesis, preference, correction, explicit lock, direct
replacement, or unresolved ambiguity, and shows ambiguity instead of forcing a
form. An explicit lock copies an already-explicit Founder lock; scripts do not
classify Founder text.

The exact Founder wording remains once at its canonical task event or Founder
intervention/review artifact. A v3 sidecar stores only the durable locator,
optional artifact plus JSON pointer, content SHA-256, capture time, and the
fixed `canonical_source_only_no_sidecar_or_runtime_copy` retention marker. The
Founder decision and any studio-preference confirmation use the same
pointer/digest rule. Raw `verbatim`, `verbatim_or_marker`, transcript, or
commentary copies are rejected from new v3 sidecars and from Role Context Pack
runtime projection.

Each closure can preserve:

- one pointer/digest-bound Founder input source and authorship;
- named track/run/stage/section/Major/Core/Cut or artifact path plus baseline
  SHA-256;
- intended screen job versus the result the Founder perceived;
- why it is weak for this song/member/world/section, paired with observable
  screen or playback evidence;
- positive preservation, required changes, and `do_not_infer` boundaries;
- optional pairwise preferred alternative;
- local scope versus same-track candidate versus studio-preference candidate;
- a pointer bind to an existing Department Dispatch correction unit at
  `/director_review/correction`, plus requirement ids, acceptance criteria,
  frozen unaffected outputs, and the Director command translation;
- corrected-result path/SHA, Director verification of whether the stated reason
  was solved, and a separate Founder PASS/PATCH/REJECT/HOLD record whose
  production-gate effect remains `none`;
- one concise `reason_summary`, stable recurrence key, total recurrence count,
  first/last seen timestamps, an evidence-rollup digest, and at most eight
  representative/latest evidence bindings;
- one Director-authored compact context projection: positive core, avoid
  signals, Director actions, review questions, priority, and exact
  role/profile/stage/section applicability;
- optional Git commit pointers for baseline delivery, feedback
  capture/dispatch, corrected return, and acceptance.

The same contextual reason updates the existing recurrence row; it never adds a
second row with the same key. A materially different reason adds a new row.
Grok or the responsible Director decides contextual sameness and authors the
stable key; scripts enforce uniqueness and bounds but never similarity-score
Founder taste. `eligible` compact rows are projected into the actual
`founder_quality_context` field of matching Overall/CDD/Edit/worker Role
Context Packs. Directors may see a current-run section-specific row for
whole-run review; bounded workers receive only exact matching section rows.
The runtime pack carries at most twelve author-prioritized patterns, adds a
semantic graph edge to the source sidecar digest, and never carries the raw
Founder source text. These rows are advisory review context, not locks or PASS.

Promotion fails closed:

- one response stays local to its named scope;
- repeated same-reason evidence may become a same-track candidate and never an
  automatic lock;
- studio or cross-track promotion requires explicit Founder confirmation and
  exact evidence, then a separate maintenance action with an overfit guard;
- numeric scoring, similarity, or scripts cannot approve creative truth;
- a worker self-claim never closes the correction;
- Git evidence is optional corroboration and never Founder PASS.

Do not bump Department Dispatch or Workbench versions to add this record. Bind
the selected correction through existing paths, hashes, and ids. Keep examples
abstract and free of prior-run creative nouns.
