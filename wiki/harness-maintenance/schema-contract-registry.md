# Schema, Contract, And Registry Maintenance

## Activation

Load this module for a schema, contract, producer/consumer route, active
schema inventory, contract-version registry, surface-version registry, or
hash-bound compatibility change. Read the exact schema, producer, consumer,
and registry paths named by the current assignment to EOF.

## Safe Evolution Order

Use one smallest-owner transaction:

1. Identify the current canonical schema/contract and its active authoring
   version. Confirm no later artifact is being mistaken for readiness.
2. Patch the authoritative schema first when the byte contract changes.
3. Patch the owning skill or producer/consumer guidance required to author or
   consume the new shape.
4. Patch `wiki/production-system.md` only when the overall flow, owner, or
   gate actually changes.
5. Update deterministic validators and tests for the changed structural
   invariant.
6. Refresh the owning contract-version and surface-version records in the
   same patch. Root owns the registry bytes and cross-file navigation when a
   dispatch assigns that responsibility.

For an atomic migration, classify every inventoried producer, consumer,
validator, Workbench/native reader, and legacy path before changing the active
pointer. `must_change` closes on new bytes and tests; `verified_compatible`
closes on an explicit reachability test; `legacy_pinned` remains non-authoring
and byte-preserved. If any active consumer still writes the old semantic field,
or a new producer is unreachable from its gate, keep the migration HOLD rather
than enable a partial default.

Do not migrate by silently accepting a legacy shape. A materially resumed run
must migrate or HOLD before authoring. Historical bytes remain evidence only.

## Version And Hash Closure

`automation/harness-contract-version-registry.yaml` is the active schema
inventory: each active stage or shared authoring script has one schema route,
one readable current version, and one producer. Retired or definitions-only
schemas do not become active by appearing in a profile. Reject duplicate paths,
`$id` values, or content; field similarity is diagnostic and never merges
owners or state transitions.

`automation/harness-surface-version-registry.yaml` records the current
revision and SHA-256 for tracked instruction, policy, wiki-router, skill, and
creative-adjacent script surfaces. A changed path with a stale or missing
record is a HOLD. Git remains the ordinary revision archive; do not create a
physical changelog for every byte change.

For every changed binding, record:

- exact repository path and current revision;
- SHA-256 of the bytes actually read and returned;
- producer, consumer, and owning logical role;
- affected checkpoint or artifact paths;
- invalidated dependents and preserved unaffected truth;
- validator/test evidence and any unresolved hold.

## Mechanical Boundary

Schemas and validators may measure, validate, scaffold empty structure, or
exact-copy a human/model-authored value with source path, JSON pointer,
source-value SHA-256, and authorship receipt. They may not infer creative
defaults, paraphrase fields, fan out a value by label, set `model_authored`,
select references, or convert schema validity into creative PASS.

The active Department Dispatch schema remains the transport contract for
maintenance returns. A maintenance result must preserve owner, scope, goal
order, required EOF reads, input/result digests, output hashes, reviewer
closure, and wake payload. Structural validation never promotes canonical
creative truth.

An admitted Company Ops `grok-build` packet maps through
`schemas/company-ops-idol-bridge.schema.json` and
`automation/company-ops-idol-bridge.yaml`. The packet may request work and
cannot bypass IDOL Department Dispatch v8, native Goal, Role Context Pack,
Director review, promotion, paid/media, external, publication, or release
gates.

## Validation Set

For a schema/profile change, run the owning JSON Schema validator, the profile
validator, and the directly affected consumer tests. Run broader state or
release-closeout audits only when the maintenance assignment explicitly names
that surface. If a required consumer is unavailable, return a HOLD with the
exact missing command/path; do not repair by weakening the contract.
