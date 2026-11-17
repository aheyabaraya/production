# IDOL Graph-Projected Role Context Pack Improvement Plan

## Document Status

- Authored: 2026-08-22 (Asia/Seoul)
- Status: `implemented_active_transport_contract_quality_pilot_pending`
- Authority: implementation record and noncanonical architecture rationale;
  active authority remains the registered policy, schema, execution contract,
  projection registry, and provider sources
- Gate effect: none
- Active-run effect: no run bytes mutated; new/materially resumed runtime nodes
  use the registered projection contract
- Registry or contract version effect: execution contract v35, startup
  admission v2, Role Context Pack v1, and projection registry v1
- External, paid-generation, upload, or release effect: none

This document began as the implementation proposal and now records the bounded
transport activation authorized on 2026-08-22. It does not alter a Founder lock
or make the graph an authority surface.

## Executive Decision

Keep the current OD -> CDD -> bounded Worker ownership and review structure.
The organizational split is not the primary problem. The current inefficiency
is that each role can still be required to load a broad instruction surface
before doing a narrow current-node job.

The recommended improvement is one read-only graph projection that emits the
minimum sufficient operational context for the exact current role,
assignment, checkpoint, and provider snapshot. The working name for that
derived artifact is:

`idol-role-context-pack.v1`

After validation and an atomic activation, this pack should become the normal
runtime context entry for OD, CDD, Edit Director, and bounded Workers. It must
replace repeated broad instruction loading for the current node; it must not
be added as another document that agents read on top of the same broad set.
Agents still read the exact creative sources and assets required for their
assignment.

The graph does not decide creative truth. It removes unrelated context while
preserving exact authority, provenance, dependencies, output contracts,
provider constraints, and HOLD conditions.

## Why This Is the Right Boundary

The current role hierarchy is already small in the dimension that matters:
one Overall Director, one Founder-visible CDD, bounded single-writer Workers,
and one Edit Director route. Further role merging would mix promotion,
development, production, and review authority without proving better creative
work.

The larger surface is the instruction and source-loading closure behind those
roles. The pre-activation baseline measurement of exact checkpoint
`required_read` bindings in `automation/harness-skill-load-profiles.yaml`
found:

| Measurement | Current value |
|---|---:|
| Load profiles | 18 |
| Checkpoints | 53 |
| Required-read bindings | 158 |
| Minimum checkpoint load | 2,264 lines |
| Median checkpoint load | 5,970 lines |
| Maximum checkpoint load | 13,512 lines |
| Overall Director startup | 7,104 lines across 11 bindings |
| CDD startup | 13,202 lines across 18 bindings |
| CDD direction alignment | 13,512 lines across 18 bindings |
| CDD sequence review | 12,223 lines |
| Post-02A 02B image checkpoint | 7,950 lines |

These are physical line counts, not token counts or quality scores. They cover
checkpoint instruction reads and do not include every current-run creative
source, media asset, or provider-native runtime context. They are sufficient
to show that a narrowly assigned logical role can still receive a broad
instruction payload.

The graph-engineering v1 baseline was useful evidence before activation:

- it is explicitly read-only, noncanonical, and advisory;
- it separates logical entities from path-and-locator evidence locations;
- its current unit suite passes with 15 runs and 83 assertions;
- its historical read-only parity suite passes with 5 runs and 32 assertions;
- it did not by itself provide active DDI parity or an active runtime
  projection.

The registered Role Context Pack v1 now extends that read-only graph proof into
the active transport boundary. It still does not make the graph a creative,
review, promotion, or Founder-decision authority.

## Current Provider and Grok Finding

Provider routing should be included in the projection, but it should not
become a second organizational graph.

The current assignment routing resolves provider-neutral logical aliases such
as `director_deep` and `worker_high` to exact provider snapshots. Grok is the
default new non-media execution route for the registered OD, CDD, Edit
Director, Song Room, ordinary Worker, and post-02A section-owner assignments.
Cursor routes remain Founder-explicit alternatives, with their own physical
chat and external Goal evidence. Media lanes remain separately registered.
There is no silent cross-provider fallback.

The assignment-routing and provider-profile validators currently pass. The
Grok source, provider registry, execution contract, and profile registry carry
matching current hashes, and the active projection preserves exact provider,
model, effort, capability, sandbox, and no-fallback resolution.

During implementation, a policy edit demonstrated that a coarse whole-file
dependency can invalidate a provider profile more broadly than the changed
semantic fragment warrants. The activation therefore keeps whole-file hashes
for inventory evidence while binding registered fragment hashes for localized
dependency and invalidation evidence. Ambiguous, missing, or changed fragments
still fail closed.

## Existing Boot Pack Compatibility

The repository already owns `idol-director-boot-pack.v3`. It is a pointer-only
restore package for a specific read-only CDD successor preflight. It must not
be silently renamed or repurposed as a general role context.

The proposed `idol-role-context-pack.v1` has a different scope:

- it is emitted for one exact current execution node;
- it supports OD, CDD, Edit Director, and bounded Worker views;
- it projects only the context needed for that node;
- it is derived from existing canonical owners;
- it never carries independent creative or promotion authority.

If the proposal is later approved, the existing CDD successor Boot Pack may
reference one role-context-pack pointer. It should not duplicate the same
state blocks or become a second current-state owner.

## Non-Negotiable Boundaries

The improvement must preserve:

- one active Overall Director and one Founder-visible CDD;
- one writer per logical artifact, section shard, decision, and merge;
- Founder ownership of locks, paid or external authorization, final decisions,
  protected-output disposal, and release;
- CDD review of exact Worker returns and OD ownership of promotion;
- exact PRE-00 full-storyline lineage and downstream carry;
- actual pixel and playback review, distinct from transport or schema PASS;
- provider-specific models, effort, authentication, tools, capabilities,
  events, sandboxes, and runtime receipts;
- Grok native Goal ordering and Cursor external Goal evidence;
- no silent fallback, provider aliasing, or media-lane substitution;
- contextual creative judgment by assigned humans or models;
- scripts limited to projection, validation, measurement, and exact-copy
  transport.

The proposal does not optimize for fewer files, shorter policies, or smaller
schemas as goals by themselves. It optimizes for minimum sufficient context at
runtime without reducing creative evidence or review quality.

## Target Architecture

```text
Canonical truth, policies, schemas, run sources, and provider registries
                              |
                              v
                Read-only graph projection
                              |
                              v
             idol-role-context-pack.v1
                 for one current node
                              |
                              v
              Provider-neutral Dispatch
                              |
                    +---------+---------+
                    |                   |
                    v                   v
             Grok adapter          Cursor adapter
                    |                   |
                    +---------+---------+
                              |
                              v
             exact output and runtime receipts
                              |
                              v
                CDD review -> OD promotion
```

The graph is a projection layer. Existing canonical files and run artifacts
remain the byte owners. The pack contains pointers, locators, exact copied
values where permitted, and hashes. It does not paraphrase or regenerate
creative truth.

## Proposed Role Context Pack Contract

The pack should contain the following bounded blocks.

### 1. Pack Identity

- schema and projection version;
- run, assignment, and logical role identifiers;
- exact stage and checkpoint;
- section, Major, Core, Cut, or edit-shard scope when applicable;
- pack creation time as evidence metadata, never current-state authority;
- deterministic source-set digest.

### 2. Authority and Return Route

- active owner and single writer;
- return recipient;
- review owner and promotion owner;
- active Founder locks and exact source pointers;
- permissions granted for this assignment;
- permissions explicitly absent;
- authority-request recipient.

### 3. Current Node

- current state and legal successor states;
- exact scope and non-scope;
- Assignment Delta;
- stop and HOLD conditions;
- required completion event;
- current decision epoch and relevant lineage checkpoint.

### 4. Creative Source Pointers

- exact current song, selected-audio, target, storyline, Front Planning,
  section, identity, reference, Cut, and neighbor pointers required by the
  assignment;
- exact paths, structured locators, and SHA-256 values;
- attachment order when the execution surface requires it;
- preserved and invalidated descendant sets when a scoped revision is active.

The pack must not summarize away a creative source. The assigned role reads
the exact creative bytes and actual assets named by these pointers.

### 5. Dependency Edges

- required predecessors;
- legal next owner or state;
- semantic, provenance, execution, review, and provider dependencies;
- affected invalidation edges;
- explicitly preserved unaffected edges.

### 6. Policy and Skill Slices

Each required instruction slice should carry:

- canonical path and owning contract identifier;
- stable Markdown heading, JSON Pointer, YAML locator, or other registered
  fragment locator;
- canonical whole-file SHA-256 for inventory evidence;
- fragment SHA-256 for localized dependency evidence;
- selection reason and applicable rule identifier;
- whether full-file EOF reading is mandatory;
- fail-closed fallback behavior.

Creative methods must remain verbatim or exact-source reads. The projector may
select an instruction fragment; it may not author a new creative method by
summarizing one.

### 7. Output Contract

- exact schema and output manifest pointers;
- required filenames or JSON pointers;
- authorship and source-value receipt requirements;
- validation commands or validator identifiers;
- expected return event and recipient;
- review criteria that require contextual Director judgment.

### 8. Provider Resolution

- one provider-neutral logical profile;
- one resolved provider snapshot pointer;
- exact provider, model, effort, capability, authentication, sandbox, and
  inventory digests from the registered snapshot;
- provider-native Goal or external Goal evidence pointer;
- allowed native tools and prohibited substitutions;
- provider mismatch and capability-drift HOLD conditions.

Provider details should be referenced once. Copying the same provider literals
into the graph, pack, dispatch, and prompt would create four drift surfaces.

### 9. Open Holds and Review Queue

- unresolved inputs;
- stale or mismatched hashes;
- pending returns and required reviewers;
- exact next admissible action;
- explicit reason that promotion is not yet legal.

## Fragment Binding and Invalidation Rules

Localized projection is safe only when fragment identity is stable and
fail-closed.

1. Prefer registered H2/H3 headings, JSON Pointers, or schema-defined YAML
   locators over physical line numbers.
2. Store both the whole-file hash and the selected fragment hash.
3. Treat a duplicate, missing, or ambiguous locator as a HOLD. Never choose the
   closest text or guess a replacement.
4. Require full-file reading when a rule depends on global definitions,
   cross-section exceptions, or an authority kernel that cannot be safely
   sliced.
5. Changes to Always-On authority or protected invariants may correctly cause
   broad invalidation.
6. A path hash change with an unchanged bound fragment may become inventory
   refresh only after historical and shadow parity prove that the fragment
   boundary is complete.
7. A fragment hash is dependency evidence, not independent policy authority.

Recommended invalidation behavior:

| Change | Packs invalidated |
|---|---|
| Founder lock or intervention | Exact affected semantic descendants and active assignment packs |
| Bound policy or skill fragment | Packs that bind that fragment |
| Unrelated section content | No other section pack |
| Provider source or capability snapshot | Packs resolved to that provider snapshot |
| Creative output byte change | Exact downstream, review, and promotion packs |
| Always-On authority or protected invariant | All packs governed by the changed rule |
| Whole-file hash changes but bound fragment is identical | Inventory refresh only after approved parity proof |

## Role-Specific Views

### Overall Director

Receives whole-film canonical heads, stage legality, active Founder decisions,
CDD or Edit Director milestones, promotion requirements, open review gates,
and exact next actions. It does not need raw Worker procedure for inactive
departments.

### Creative Development Director

Receives the complete current whole-film creative spine, current development
checkpoint, selected evidence, current section dependencies, bounded
department assignments, pending returns, and review requirements. It does not
need unrelated inactive-stage execution procedure.

### Bounded Worker

Receives the exact complete job: Assignment Delta, task sources, relevant
creative context, owning policy and skill slices, output contract, return
recipient, provider snapshot, and stop conditions. It does not load the whole
harness route.

### Post-02A Section Owner

Receives the exact section, Official Core and ordered Branch Cut context,
neighbor continuity, passed identity and reference assets, image and motion
provider constraints, pixel or playback gates, and return route.

### Edit Director and Edit Shard

The Edit Director receives accepted production inputs, whole-video edit
progression, shard boundaries, review queue, and merge authority. A shard
receives only its disjoint edit inputs, shared boundaries, output contract, and
return route.

## Grok and Multi-Provider Graph Engineering

The provider is an execution attribute of a logical assignment, not a new
creative owner or a duplicate stage branch.

The graph should model:

- shared logical role, stage, scope, and review edges;
- provider-specific capability and runtime-receipt nodes;
- a single `resolved_provider_snapshot` edge per assignment;
- exact native lifecycle evidence without forcing providers to use one literal
  event vocabulary;
- provider drift as an assignment-level invalidation unless it changes a
  canonical creative source;
- separate registered media routes for 02B image and 03V video generation.

For Grok, the pack must preserve exact registered profile, model, effort,
sandbox, tool inventory, and native Goal ordering. For Cursor, it must preserve
the separate physical-chat provider, external Goal record, and runtime receipt.
Neither provider borrows the other's capabilities or becomes an implicit
fallback.

## Deterministic Projection Procedure

1. Resolve the current canonical frontier from the DDI, stage registry,
   Founder state, and canonical run heads.
2. Select the exact logical role, load profile, and checkpoint.
3. Traverse only required authority, semantic, provenance, execution, review,
   and provider predecessors for that node.
4. Resolve one exact provider snapshot from the immutable assignment binding.
5. Bind registered instruction fragments and exact creative source pointers.
6. Emit the deterministic role context pack and source-set digest.
7. Validate source existence, locators, hashes, authority, provider readiness,
   output contract, and legal successor state.
8. At runtime, load the pack and then the exact creative bytes and assets it
   names.
9. Return outputs and receipts to the named Director for independent exact-byte
   review.

The projector must not select a creative direction, fill missing content,
repair a stale truth value, or promote an output.

## Migration Plan

### Phase 0: Baseline and Ownership Inventory — completed

- verify and synchronize the exact Grok CDD successor source and provider
  registry hashes;
- freeze representative OD, CDD, Worker, section-owner, and Edit Director
  checkpoint fixtures;
- record current instruction lines, tokens, latency, cost, HOLD rate, and
  outputs without changing active behavior;
- map each proposed field to one existing canonical byte owner.

Deliverable: evidence-only baseline and field ownership table.

### Phase 1: Noncanonical Projection Prototype — completed

- add a proposed `idol-role-context-pack.v1` schema under a noncanonical graph
  work area;
- extend the read-only graph with role, checkpoint, fragment, provider,
  authority, and review edges;
- emit packs only from fixtures and historical snapshots;
- make no active DDI, skill, profile, run, or provider-registry write.

Deliverable: deterministic prototype, fixture packs, and source-set hashes.

### Phase 2: Historical and Structural Parity — completed for activation

- compare every projected dependency with the current checkpoint read closure;
- prove that each omitted source is unrelated to the exact assignment;
- test ambiguous locators, renamed headings, stale fragments, provider drift,
  Founder interventions, and invalidated descendants;
- require fail-closed outcomes for every uncertainty.

Deliverable: parity report with no unexplained omissions.

### Phase 3: Current Shadow Projection — completed for activation

- project packs beside exact current OD, CDD, and Worker assignments;
- do not deliver the packs to production models yet;
- compare pack decisions, legal next actions, provider resolution, and HOLDs
  with the active route;
- confirm that the pack has no independent queue or Current Next state.

Deliverable: shadow comparison and activation HOLD list.

### Phase 4: Isolated Dummy A/B Pilot — quality follow-up pending

Use the same frozen source bytes, assignment, provider model, effort, and output
contract for each comparison:

- current full checkpoint context;
- graph-projected role context pack.

Run both Grok and the explicitly selected comparison provider when authorized.
Treat provider choice and harness thickness as separate variables. Codex-native
or another provider may be used as an evaluation surface only; it does not
silently become the registered production route.

Use at least three trials per cell and blind the Founder review to the context
variant where practical.

Deliverable: quality, compliance, intervention, latency, and cost comparison.

### Phase 5: Atomic Active Switch — completed

The 2026-08-22 Founder instruction authorized the active switch. The reviewed
change set:

- register the active context-pack schema and projection version;
- update the producer, consumers, checkpoint profiles, execution contract,
  validators, and contract-version registry together;
- update every changed surface revision and SHA-256;
- remove the replaced broad runtime read path from active profiles;
- retain a versioned rollback pointer;
- run repository, provider, graph, route, and isolated dummy validations.

The old broad route and new pack route must not both be mandatory in production.
That would add cost without proving simplification.

### Phase 6: Rollback and Observation — observation pending material use

Rollback changes only the active context-loading route to the previous
versioned checkpoint profile. It must not rewrite creative outputs, Founder
locks, or run lineage. Observe the first approved runs for missing-context
HOLDs, false invalidations, intervention rate, and review quality.

## Implemented Change Surface

The activated surface is:

- one registered role-context-pack schema and projection registry;
- a deterministic projector and validator with profile/checkpoint and
  Department Dispatch entry points;
- deterministic, source-drift, unrelated-change, authority-change,
  invalidation, and ambiguity tests;
- startup-admission and provider-neutral Studio Kernel consumers;
- Grok-owner and orchestrator routing rules that apply the same pack contract;
- execution-contract, schema, contract-version, script, and surface-hash
  registry updates in the same activation change set.

No creative artifact should be rewritten merely to implement this projection.
Provider data should remain in provider-specific sources and be referenced,
not copied into every consumer.

## Evaluation and Acceptance Criteria

### Hard Correctness Requirements

- no missing Founder lock, authority boundary, source, stage gate, required
  policy, skill method, provider restriction, output contract, or review gate;
- no second canonical queue, Current Next, promotion state, or creative truth;
- deterministic output for identical source bytes and projection version;
- exact source locators and hashes with ambiguity causing HOLD;
- provider/model/effort/tool/auth mismatch causing HOLD;
- unrelated changes do not invalidate unrelated packs;
- affected Founder intervention descendants do invalidate and revalidate;
- scripts author no creative truth;
- the Director still reviews exact output bytes contextually.

### Quality Comparison

Compare the full current context against the projected context on:

- whole-film coherence and progression;
- song, title, member, and world specificity;
- observable screen action, camera, composition, identity, and continuity;
- preservation of Founder locks and reference functions;
- useful branch and section differentiation;
- number of Founder interventions required;
- Director revision and rejection rate;
- false PASS, false HOLD, and missing-context rate;
- latency, input tokens, and execution cost;
- provider route stability and receipt completeness.

A mechanical schema PASS is not a creative PASS.

### Activation Decision Threshold

The initial decision target is at least a 50 percent reduction in median
instruction-only loaded lines for the representative OD, CDD, and Worker
checkpoints, with:

- zero hard correctness regressions;
- no material blind-review creative quality regression;
- no increase in missing-context or unauthorized-action failures;
- no increase in Founder keystrokes needed to recover omitted context.

The line-reduction number is a decision threshold, not permission to compress
or delete canonical policy. If the pack cannot meet it safely, the active route
does not switch.

## Stop Conditions

Stop the migration and return HOLD if:

- the graph or pack becomes a creative or promotion authority;
- a script paraphrases, defaults, repairs, or invents creative truth;
- the pack and an existing surface both claim current-state ownership;
- a required rule cannot be bounded without losing cross-section meaning;
- locator ambiguity is resolved by guesswork;
- provider-specific constraints are flattened into a false common contract;
- a provider substitution or fallback is introduced;
- active run bytes must be changed merely to prove the projection;
- validators are weakened to make parity pass;
- broad reads remain mandatory after the pack is activated;
- the change overlaps unrelated dirty work without a safe single-owner patch.

## Recommendation

Keep the active transport switch and preserve the OD/CDD/Worker structure.
Treat the first authorized material use as the quality pilot: compare creative
quality, missing-context rate, Director revision rate, Founder keystrokes,
latency, and cost against the frozen broad-load baseline. Roll back the context
loading route if a hard correctness or material quality regression appears;
do not rewrite creative outputs, Founder locks, or lineage during rollback.

The practical boundary remains one minimum-sufficient current-node pack from a
read-only graph projection. It replaces unused stage procedure while retaining
IDOL's lineage, approval, exact provider, no-fallback, contextual review, and
Founder-control shell.

## Implementation Receipt — 2026-08-22

The bounded transport implementation is active. No current-run creative bytes,
Founder locks, paid generation, provider call, upload, or release were changed.

Implemented surfaces:

- `automation/harness-role-context-projection.yaml` and its v1 schema register
  deterministic full-file, exact-heading, and structured pointer-only rules;
- `scripts/lib/idol_role_context_pack.rb` and
  `scripts/idol_role_context_pack.rb` build and validate from either a selected
  profile/checkpoint or Department Dispatch;
- `schemas/role-context-pack.schema.json` keeps the pack derived/read-only and
  binds owner, scope, dependencies, Founder context, named creative pointers,
  output/HOLD/return contract, and exact Grok or Cursor provider snapshot;
- startup admission v2 makes Overall and CDD apply a single pack receipt in
  place of the former broad EOF receipt list;
- the provider-neutral Studio Kernel, Grok owner route, orchestrator, authority
  kernel, production map, and routing policy now define the same replacement
  and invalidation rule;
- execution contract v35 and the contract/script/surface registries classify
  the producer, consumers, provider separation, no-fallback rule, and absence
  of creative or promotion authority.

Representative live instruction-only measurements against the current source
closure are:

| Node | Original words | Projected words | Reduction |
|---|---:|---:|---:|
| Overall `director_startup` | 34,169 | 16,768 | 50.93% |
| CDD `cdd_startup` | 65,537 | 32,114 | 51.00% |
| Worker `pre00_scan` | 29,596 | 14,402 | 51.34% |

These are transport measurements, not creative PASS. The first material
production use should still compare creative quality, missing-context rate,
Director revision rate, and Founder keystrokes against the former broad-load
baseline before treating token reduction as a quality result.
