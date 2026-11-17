# IDOL Graph Engineering Maintenance Rules

**Purpose**: Keep IDOL Graph Engineering (instructions, policies, schemas, skills,
validators, runtime surfaces, and related artifacts) clear, auditable, and
safe to evolve.

`harness` remains only in compatibility-bound paths, schema versions, registry
ids, scripts, and historical evidence. Do not mass-rename those identifiers:
that would sever producer/consumer and historical graph edges. New AI/model-
facing prose and labels use `IDOL Graph Engineering` or `graph-engineering`.

**Audience**: Codex, Grok, and a Founder-authorized maintenance owner doing
structural or documentary work. This is not a creative-production brief.

The page is the compact common transaction and router. Change-surface detail
lives in the linked modules under `wiki/harness-maintenance/`; a module is read
only when the current change surface activates it. The old
`handoff/grok/HARNESS-MAINTENANCE-RULES.md` location is retired.

## Authority And Boundaries

Use this order when surfaces disagree: `AGENTS.md`, the activated policy under
`policies/`, active schemas, owning skills, `wiki/production-system.md`,
specialist wiki modules, then source and run artifacts. Git is the normal text
history. Physical copies, mirrors, previews, and rejected candidates are not
new canonical versions.

This page governs maintenance process only. Creative language, Founder locks,
prompt quality, source eligibility, media security, and stage decisions stay
with their named owners; cite them rather than restating them. A maintenance
worker must not author creative truth, infer a Founder lock, create a creative
stage, widen a dispatch, expose secrets, capture/download/upload media, or
promote canonical production truth outside the declared write scope.

## Common Maintenance Transaction

Every change follows the same auditable transaction:

1. **Authorize and scope.** Bind the current Founder instruction, owner,
   decision epoch, exact files, output paths, and stop conditions. A size
   reduction or split is valid only when the current request explicitly
   authorizes size remediation.
2. **Route by surface.** Select exactly one or more disjoint change-surface
   modules from the table below. Do not load maintenance context into an
   ordinary creative checkpoint; use the `harness_maintenance` profile only
   for a maintenance dispatch.
3. **Read the recipe.** Create the native Goal first, then read this core,
   every selected module, and every required schema/policy/skill to EOF. Record
   the launch hashes and unload each module at its declared checkpoint return.
4. **Inspect current bytes.** Resolve the canonical owner, producer and
   consumers, current revision/hash, active registry entry, and any dirty
   worktree changes. Preserve unrelated work. Never infer truth from a
   filename, a static startup bundle, or a prior report.
5. **Patch the smallest owner.** Keep one canonical owner per logical artifact.
   Split by change surface, not provider, worker, musical subdivision, or
   subjective difficulty. Preserve unique quality, safety, schema, review, and
   Founder-gate obligations; move only detail whose activation is explicit.
6. **Validate and measure.** Run the owning schema, profile, instruction, and
   relevant consumer checks. Measure the exact registered checkpoint load
   (binding paths read at that checkpoint), not a profile's union or a static
   startup estimate. A structural pass does not mean creative PASS.
7. **Return an auditable delta.** Return changed paths, baseline and result
   SHA-256 values, measured checkpoint loads, tests, unresolved risk, and any
   hold. The recipient Director independently opens the exact bytes and
   governing sources before promotion.

For a breaking cross-stage migration, the maintenance owner also keeps one
machine-readable path classification with every inventoried path closed as
`must_change`, `verified_compatible`, or `legacy_pinned`; records the producer,
consumers, validators, and target registry revision for each changed canonical
field; and keeps old/new authoring defaults from becoming active simultaneously.
Provider/model literal migration follows one order: provider-specific exact
profile source -> literal-free alias index/source hash -> immutable run snapshot
-> offline shadows -> explicit Founder default switch. A lifecycle-retired
schema or script never reactivates merely because a proposal names its path.

## Change-Surface Router

| Current surface | Read this module | Use it for | Do not use it for |
|---|---|---|---|
| instruction, policy, or wiki prose | [instruction-policy-wiki.md](harness-maintenance/instruction-policy-wiki.md) | canonical placement, conditional routing, bias-safe examples, size and history boundaries | schema ownership, runtime profile design |
| schema, contract, or versioned registry | [schema-contract-registry.md](harness-maintenance/schema-contract-registry.md) | schema-first evolution, producer/consumer inventory, version/hash closure, stale-route holds | creative field authoring or broad prose cleanup |
| skill and checkpoint load routing | [skill-profile-routing.md](harness-maintenance/skill-profile-routing.md) | exact profile/checkpoint sets, maintenance-only loading, unload boundaries, registered-load measurement | creative stage creation, provider-specific prompts |
| reusable script or validator | [script-validator-registry.md](harness-maintenance/script-validator-registry.md) | validator/extractor scope, deterministic exact-copy guards, test and registry coverage | semantic reference selection, Founder review |
| Workbench, runtime UI, queue, or handoff | [workbench-runtime-ui.md](harness-maintenance/workbench-runtime-ui.md) | pointer-only views, lifecycle/lease/wake behavior, owner and single-flight review boundaries | canonical creative merge or release approval |

If one patch spans surfaces, keep one aggregate manifest but record one row per
module and one owning path per file. The profile/checkpoint IDs are stable:
`harness_maintenance` with `instruction_policy_wiki`,
`schema_contract_registry`, `skill_profile_routing`,
`script_validator_registry`, and `workbench_runtime_ui`. Company Ops role
`kurisu.idol_graph_cdd` remains pointer-only on that profile; see
`automation/company-ops-idol-bridge.yaml`.

The aggregate return reuses Department Dispatch transport closure. Do not create
a second receipt contract merely to prove hashes or schema status. One closure
summary records clean/auto-refreshed/Director-impact/blocked state; unchanged
creative bytes may receive at most one mechanical refresh and do not reopen a
creative review counter.

## Instruction Surface And History Discipline

This section is the active maintenance boundary for instruction surfaces. Keep
`AGENTS.md` as the always-on kernel, `wiki/production-system.md` as the compact
router, and conditional modules as exact routed detail. Historical prose stays
out of normal bootstrap paths. Shared stop-doing rows are indexed in
[`harness-standing-constraint-index.md`](harness-standing-constraint-index.md)
and `automation/harness-standing-constraint-catalog.yaml`; do not add a second
always-on rulebook.

## Duplication, Examples, And History

### Teaching Example Preservation And Bias Control

Search `AGENTS.md`, `policies/`, and `wiki/` before adding guidance. Link to a
stronger owner instead of copying it. Teaching examples may show a decision
method and materially different routes, but must remain noncanonical,
non-prescriptive, current-evidence dependent, and outside generation/context
packs. Do not carry prior-run names, distinctive scene nouns, full prompts, or
copy-ready action/camera/motion into current execution.

Do not append a dated narrative to this active page. Routine history belongs in
the Git commit. The frozen compatibility snapshot remains at
[wiki/harness-maintenance-history.md](harness-maintenance-history.md) and is
excluded from startup and creative checkpoint loads.

## Size And Evolution Guardrails

File length is a review signal, not a creative quota. A compact core plus
directly linked conditional detail is appropriate when one always-on surface
mixes authority, procedure, examples, and history. Do not split a cohesive
conditional reference merely to hit a line count, auto-summarize unique
quality instructions, or create dated/per-change archive piles. Any long
conditional module needs stable headings and an explicit activation rule.

For a new stage, artifact, skill, command boundary, or schema, use the
schema/contract/registry order in the [schema module](harness-maintenance/schema-contract-registry.md),
then update its owner and consumers in one patch. A stale or omitted registry
revision is a HOLD. An authoring change updates the contract-version registry,
surface revision, and SHA-256 in the same patch. Size findings are diagnostic
or hold only; size remediation requires an explicit Founder instruction in the
current request. Automatic size remediation is false: preserve the file unless
that authority is present. A maintenance change never silently changes a
Founder lock, stage owner, source disposition, or production artifact.

## Closeout

The maintenance owner performs mechanical self-checks and returns the exact
manifest. The recipient Director performs the independent byte/read closure,
requirement judgment, and promotion or HOLD. Keep the result under the
declared maintenance output path; do not publish, submit, delete protected
outputs, or mutate external systems without the separate Founder gate.

Run `python3 scripts/idol_instruction_surface_audit.py` after structural
instruction changes. Size findings are warnings unless a protected invariant,
activation link, history boundary, or reviewed exception is missing. Run the
registered profile/schema/consumer validators after routing changes. The
machine-readable thresholds and frozen-history baseline live in
`automation/instruction-surface-policy.yaml`; it is read-only input to this
transaction and is not duplicated here.
