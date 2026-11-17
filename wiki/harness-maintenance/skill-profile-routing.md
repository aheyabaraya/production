# Skill And Checkpoint Profile Routing

## Activation

Load this module for a skill-load registry, role profile, checkpoint read set,
runtime profile switch, unload boundary, or context-load measurement. It is
maintenance guidance, not a creative skill and not a provider prompt.

## Exact Runtime Sets

`automation/harness-skill-load-profiles.yaml` is the only profile-body source.
The profile-level arrays are allowed unions for validation; the checkpoint's
`required_skill_ids` and `required_read_ids` are the exact runtime set. There
is no implicit inheritance from a neighboring checkpoint, a startup bundle,
or a previously used role. The selected profile/checkpoint, all revisions and
hashes, the current assignment delta, and the unload boundary are recorded in
the Department Dispatch.

Ordinary creative profiles must not read `maintenance_rules` or any module
under `wiki/harness-maintenance/`. In particular, Overall startup, source-hub
registration, FP close, reference, member-visual, post-02A, edit, and board
checkpoints stay on their own professional reads. Maintenance context is
available only through the explicit `harness_maintenance` profile and a
selected change-surface checkpoint.

## Maintenance-Only Profile

The registry's non-creative `harness_maintenance` profile has no stage id and
loads no creative skill. Its common read core is:

```text
AGENTS.md
wiki/production-system.md
wiki/harness-maintenance-rules.md
schemas/department-dispatch.schema.json
```

Each checkpoint adds exactly one selected module:

| Checkpoint | Selected module | Unload boundary |
|---|---|---|
| `instruction_policy_wiki` | `wiki/harness-maintenance/instruction-policy-wiki.md` | `maintenance_review_return` |
| `schema_contract_registry` | `wiki/harness-maintenance/schema-contract-registry.md` | `maintenance_review_return` |
| `skill_profile_routing` | `wiki/harness-maintenance/skill-profile-routing.md` | `maintenance_review_return` |
| `script_validator_registry` | `wiki/harness-maintenance/script-validator-registry.md` | `maintenance_review_return` |
| `workbench_runtime_ui` | `wiki/harness-maintenance/workbench-runtime-ui.md` | `maintenance_review_return` |

The profile is a structural route, not a new creative stage. It cannot be
selected by ordinary creative dispatch, cannot create a stage, and cannot
promote a production artifact. A maintenance task still needs a native Goal,
exact scope, bounded outputs, independent Director review, and the same hold,
split, and Founder gates as any other Department Dispatch.

Company Ops role `kurisu.idol_graph_cdd` is pointer-only on this profile and
the registered Grok `worker_high` / `grok_worker_high` route. It may coordinate
bounded harness maintenance and return reviewed milestones. It is not a second
Overall Director, creative promotion authority, public release authority,
universal worker, or Founder-conversation owner. The pointer contract is
`automation/company-ops-idol-bridge.yaml`. Do not copy Company Ops organization
policy or IDOL creative truth across repositories.

## Profile Changes

When adding or removing a binding, first verify the change surface and then
update the allowed profile union and every affected checkpoint together. Keep
role-specific modules conditional: a song/story checkpoint does not inherit
world/object or choreography detail, and an image-only World/Still checkpoint
never inherits video instructions. Keep source-hub, reference, pre-02A,
post-02A, and edit ownership disjoint.

A logical profile alias resolves through the literal-free provider registry to
one provider-specific exact source and immutable run snapshot. Directors use
`director_deep`; bounded workers use `worker_high`. The alias, provider source
hash, resolved model/effort/auth/capabilities, active role binding, and no-
fallback state travel together. Model literals in policy, skill, central index,
or stage config are a HOLD; provider-specific profile sources and immutable
resolved fixtures are the allowed owners.

A profile switch is legal only at a hash-bound artifact or section-shard
boundary with complete or held state. Never switch in the middle of a source
interpretation, core cut, branch prompt, or motion cue. A correction is a new
immutable attempt in the same lineage; it never overwrites prior evidence.

Provider-native internal helpers require no project numeric/depth gate. They
remain inside the parent Work Package and cannot gain another logical role,
canonical owner/writer, Founder dialogue, promotion, paid, or external
authority. When physical media/context/output ownership is more effective,
select it at launch or perform one atomic transfer; simultaneous internal and
physical owners for the same Work Package fail closed.

## Measuring Actual Checkpoint Loads

Measure each registered checkpoint from its exact binding ids, resolving each
path in the current registry and counting whitespace-delimited words in the
bytes actually read. Report both binding count and word total, for example:

```text
profile.checkpoint | skill bindings | read bindings | total words | unload_after
```

Do not report `required_read_ids` union totals as a checkpoint load, and do not
use `harness_static_startup` or `maintenance_static_startup` as a proxy. A
changed binding hash invalidates the old measurement. The result is an audit
measurement only; it never authorizes a thinner professional read set.

## Required Checks

Run the profile JSON Schema validator and
`ruby scripts/validate_harness_skill_load_profiles.rb`. The validator must
fail closed when a creative profile includes maintenance context, when a
maintenance checkpoint selects more than one module, when a profile uses an
unknown change-surface id, or when a required read/skill is outside its
declared union. Confirm all selected paths exist, match their hashes, and are
read to EOF before return.
