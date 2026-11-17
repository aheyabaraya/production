# Graph Engineering Contract And Evidence Graph

Status: active local read-model
Canonical authority: `AGENTS.md` -> activated `policies/**` -> `schemas/**` ->
owning `skills/**/SKILL.md` -> run artifacts

This page is a local Markdown knowledge graph. It is intentionally compatible
with link-based tools such as Obsidian, but IDOL does not depend on Obsidian or
an external service. The wiki indexes truth; it does not duplicate or replace
the canonical bytes in a run, source hub, schema, skill, or automation file.

## Reference Evidence Graph

```text
source identity
-> canonical image/video bytes + SHA-256
-> selected cell/crop/frame/time-bounded sequence
-> observed pixel/playback facts
-> interpretation_receipt
-> applied/combined/held/rejected function + target + reason
-> Front Planning interpretation index
-> 01 interpretation binding and section direction
-> 01 Official Core creative truth and passed primary image
-> 02A immutable Core import + Branch-Cut creative truth
-> 02B exact-copy prompt projection
-> generated asset / 03V / 04 evidence and review receipt
```

Keep `observed truth` and `application truth` separate. An observed fact says
what the selected source pixels or playback actually show. Application truth
says how the creative owner uses, combines, holds, or rejects that fact for the
current song and section. A contact sheet is navigation evidence, not a source
interpretation and not a generation attachment. The owning run keeps exact
paths, hashes, selected cell/frame ids, and interpretation/application rows;
this wiki keeps only the route and links.

Primary links:

- [Reference source and routing policy](../policies/harness-routing-and-sources.md)
- [Creative production constitution](../policies/creative-production-constitution.md)
- [Section production contract](../policies/section-production.md)
- [Canonical video source hub](../source-materials/video-sources/README.md)
- [Artifact lifecycle](artifact-management-system.md)

## Department Dispatch And Director Review Graph

```text
semantic stage id
-> owning skill selected by stage registry
-> one bounded Department Dispatch v8 attempt at RUN/work/department-dispatches/TASK_ID.yaml
-> launch contract names exact role, scope, Founder epoch/locks, skills, linked reads,
   sources, permissions, output boundary, authority, hold conditions, and recipient
-> runtime enforces every required SKILL.md and linked read to EOF
-> runtime return records lineage/session/attempt ids, skill revisions,
   input/result digests, owner, output hashes, and an aggregate manifest when multi-file
-> exact recipient director reviews the actual returned bytes against the task rubric
-> director promotes the bound canonical output or records a hold
-> deterministic single writer projects pointer/hash state into Director Dispatch Index
-> stage schema + validator
-> canonical artifact or hold
```

Syntax, heading, and readable-path checks only prove that a skill is shaped and
addressable. They do not prove runtime loading, application, or output quality.
New or materially resumed work therefore uses one provider-neutral dispatch
governed by `schemas/department-dispatch.schema.json`. The lifecycle is the
exact prefix `prepared -> launched -> returned -> reviewed -> promoted|hold`.
One logical worker or Founder-visible room keeps a stable lineage; every launch,
return, and review submission is one immutable attempt with its own dispatch id.
The independent review-cycle counter allows the initial submission plus at most
two targeted corrections. Each correction exact-copies the prior Director's
complete problem set, invalidated output hashes, correction action, and
acceptance criteria; it narrows the Goal and artifact scope to those outputs and
hash-freezes everything else. Submission 3 may pass but cannot spawn a fourth
child submission. Replacement requires an explicit successor lineage from the
last valid checkpoint; session/provider/model changes do not reset the review
cycle or silently create a competing owner.
The same envelope accepts IDOL `runs/**` and isolated `cf/runs/CF_*` ownership;
each dispatch, output, manifest, correction source, and frozen output lives only
inside its declared album/title/run. There is no global `runs/workers` lane.
The attempt may load only the root or CF skill paths explicitly bound at launch.
The worker does not self-author a read/application receipt. Runtime records the
enforced revisions and digests; the named director reviews the actual output
bytes. A changed source, skill, or output hash stales the dispatch binding and
holds promotion.

`RUN/work/director-dispatch-index.yaml` is the pointer-only runtime read model.
It stores assignment, lineage, lifecycle, aggregate-manifest, review, board,
checkpoint, hold, and next-action pointers; it never stores raw media, full
worker outputs, or chat transcripts. Scoped views and the deterministic Director
Boot Pack are rebuilt from that index and canonical heads with compare-and-swap
and atomic-write protection. Reference departments return disjoint deltas to
`RUN/research/reference-working-index.yaml`; the CDD reviews the creative rows
and one mechanical writer merges them. A worker never edits either shared index.

For Front Planning, the context pack intentionally does not copy the complete
Markdown into a second editable cache. It carries the canonical plan path/hash
and the downstream-critical contract. The entry gate verifies the full original
bytes, the plan/readiness/pack bindings, and a promoted Front Planning dispatch.
The current or materially resumed stage through 02A must bind its exact output
through runtime return, director review, and promotion. Earlier dispatches and
legacy skill-application receipts remain provenance evidence. For an older run,
the newest single receipt inside the owning stage directory—whole or scoped—may
carry an exact unchanged canonical artifact path and SHA-256 as a frozen,
non-authoring compatibility baseline. Receipts are never aggregated to build
that proof. A stale `whole.yaml` remains rejected even when a newer scoped
receipt independently binds the current bytes. The selected receipt is not v18
application evidence, is never refreshed, and stops carrying the gate as soon
as the bytes change or a new same-stage dispatch launches. Any material
resumption requires the Department Dispatch lifecycle.

Dispatch lifecycle depth follows the work mode. Exploration may stop without
canonical output promotion. Promotion always requires input digest, returned
output hashes, and director review. Execution additionally preserves strict
permission, asset, pixel, or playback evidence owned by its downstream schema.

Primary links:

- [Stage registry](../automation/harness-stage-registry.yaml)
- [Execution prompt contract](../automation/harness-execution-contract.yaml)
- [Department dispatch schema](../schemas/department-dispatch.schema.json)
- [Department dispatch validator](../scripts/validate_department_dispatch.rb)
- [Director dispatch index schema](../schemas/director-dispatch-index.schema.json)
- [Reference working index schema](../schemas/reference-working-index.schema.json)
- [Director dispatch index and Boot Pack builder](../scripts/idol_director_dispatch_index.rb)
- [Skill-load profile registry](../automation/harness-skill-load-profiles.yaml)
- [Legacy skill application receipt schema](../schemas/skill-application-receipt.schema.json)
- [Orchestrator skill](../skills/idol-orchestrator/SKILL.md)

## Version Graph

`automation/harness-contract-version-registry.yaml` is the one current-version
router. Each row names the current authoring version, readable legacy versions,
producer, and consumers. New work authors the current version. Legacy versions
remain readable, but a materially resumed artifact migrates or holds before new
authoring; an unknown version always holds. Do not restate current versions in
another wiki table.

Primary links:

- [Contract version registry](../automation/harness-contract-version-registry.yaml)
- [Contract version registry schema](../schemas/harness-contract-version-registry.schema.json)
- [Graph Engineering maintenance rules](harness-maintenance-rules.md)

## Script Authority Graph

```text
human/model creative decision
-> canonical source path + JSON pointer + value SHA-256
-> promoted department dispatch + director-reviewed output binding
-> registered direct script validates or exact-copies
-> destination value and provenance check
```

A script owns mechanics, never creative authorship. It may not invent defaults,
paraphrase a thin source, fan one value across different cuts, fill placeholders,
or claim `model_authored` provenance. Missing creative truth returns to the
owning skill as a hold. Run-specific helpers write only diagnostic candidates
under `work/`; they never repair canonical creative artifacts. Schema failures
use `schemas/schema-repair-candidate.schema.json`: the candidate binds the
unchanged target/schema/source hashes and the source artifact's promoted
department dispatch. The validator confirms that runtime return, director
review, and promotion all bind those exact source bytes. The candidate itself
has no gate effect and returns to the existing creative owner.

Primary links:

- [Script policy and registry](../scripts/README.md)
- [Execution prompt contract](../automation/harness-execution-contract.yaml)
- [Graph Engineering maintenance rules](harness-maintenance-rules.md)

## Session Boundary Graph

One continuing Overall Director owns promotion and whole-video acceptance. It
opens one separate durable Founder-visible CDD at run start. The CDD owns the
Founder-visible development Workbench/session lineage and reviews all Song,
reference, Member Visual Identity, and FP/01/02A development returns before
sending only milestone packages upward; Overall remains the sole Founder-
conversation owner. The physical Song Room, only the adaptive named-gap
reference assignments still needed for decision readiness, the conditional
Member Visual Identity room, and two to four ordinary development blocks (a
fifth only by reviewed named exception) report only to the CDD. Revisions stay
in the same relevant physical room as new hash-bound attempts.

Only after one exact 02A section is approved does a checkpointed
provider-resolved `section_image_motion_worker / worker_high`
image-motion lineage open for that section. It carries 02A validation ->
section 02B compile/review -> image generation/review -> 03V handoff. A durable
checkpoint may resume in a new physical Luna session while the section,
sources, hashes, prompts, references, approvals, and output ownership remain
unchanged; a second creative lineage after 02B is forbidden. An upstream
creative hold routes only the affected scope to the continuing durable CDD.

04/05 starts in one fresh Founder-visible Edit Director room after required
03V handoffs pass. It owns the single canonical edit map and may open direct,
disjoint section or connected-chunk edit shards. Those shards return only to the
Edit Director; its reviewed merged package returns to Overall. Creative
delegation remains flat and every launch obeys director-review backpressure and
the lower registered provider cap.

Primary links:

- [Section production policy](../policies/section-production.md)
- [Execution prompt contract](../automation/harness-execution-contract.yaml)
