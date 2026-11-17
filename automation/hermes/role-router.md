# Hermes Role Router

Status: active  
Created: 2026-06-08 KST

## Founder

Founder decides:

- route selection or active-run priority
- song lock
- creative pass / hold / reject
- source image replacement
- Grok review/refinement/execution scope
- paid image or video generation
- package approval
- publish, upload, schedule, platform API, or external sync

If one of these decisions is missing, Hermes records the gate and stops that
route.

## Hermes

Hermes keeps the operating layer short:

- current 7-day goal
- today's three-or-fewer actions
- 48-hour checkpoint
- blocked items
- founder decisions needed
- next review time

Hermes points to source files. It does not replace `runs/**` truth.

## Active Graph Engineering Owner

When the Founder selects Codex or Grok to own a run or continue a stage, that
surface may author, validate, and losslessly merge the same canonical PRE-00
through 05 contracts. Hermes must not turn a Grok-owned route into a handoff,
candidate-only, or refinement-only lane. One logical artifact still has one
active writer, and all Founder/external-action gates remain unchanged.

## Codex

Use Codex when the work is local, structural, or verifiable:

- inspect repo state and active run status
- check required files, schemas, indexes, and source refs
- clean or reconcile run-owned prompt/index/handoff records after founder
  decisions
- validate social ledgers and local analytics records
- prepare local plans, summaries, and gate reports

Codex stops before paid generation, upload, publish, scheduling, external sync,
or connector use unless the founder approves that exact task.

## Grok

When Grok is the Founder-selected active graph-engineering owner, use it for the same
local, structural, creative, validation, and canonical stage work available to
Codex. Grok may use its provider-native worker topology, but each worker must
have a bounded task and disjoint write ownership.

When the Founder instead requests an actual cross-surface handoff or external
Grok route, constrain the handoff to the requested scope:

- brainstorm alternate hooks, visual routes, or motion ideas before lock
- review or refine selected video prompts
- help with fast manual experiment loops
- execute Grok Imagine/video work only when explicitly approved

The handoff cannot change source image order, member identity, wardrobe,
environment, or canonical run files without Founder-selected material and
run-owned intake. This handoff boundary does not restrict an active Grok owner
working directly in the canonical run.

## Stop Without Founder

Stop and record a gate for:

- choosing a route or active content unit
- final song lock
- generated Branch-Cut pass, hold, or reject
- paid generation
- package approval
- public release
- upload, schedule, publish, platform API use, Drive sync, or other external
  sync
