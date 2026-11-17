# IDOL Harness Step Commands (Grok TUI)

This document defines convenient slash commands for navigating the IDOL
production harness without repeating long instructions every time. These are
entry aliases, not permission to add extra top-level stages.

Clear operator names and stable semantic ids are canonical in
`automation/harness-stage-registry.yaml`. The Grok slash tokens below resolve
through that active registry and own no separate skill authority. Do not rename
run files or infer a new stage from the clearer label alone.

## Recommended Usage

Instead of typing long context every turn, use these short commands:

- `/idol-step pre00`
- `/idol-step pre00s`
- `/idol-step audio-analysis`
- `/idol-step audio-motion`
- `/idol-step 00a`
- `/idol-step front-planning`
- `/idol-step 01`
- `/idol-step 02a`
- `/idol-step 02a-review`
- `/idol-step 02b`
- `/idol-step 02b-release`
- `/idol-step 02b-gen`
- `/idol-step 02b-review`
- `/idol-step audio-branch`
- `/idol-step 03v`
- `/idol-step 03v-review`
- `/idol-step 04`
- `/idol-step 04fx`
- `/idol-step 05`

Additional helpers:
- `/idol-step current` — Show current frontier and recommended next slice
- `/idol-step next` — Validate the current gate and recommend the next safe slice; never advance across `hold`, `blocked`, `needs_founder`, or failed completion evidence

## Bounded Continuation

A Founder request to continue through several stages routes through
`skills/idol-orchestrator/` and the active execution contract. It is not encoded
as a slash-token preset. `fp-to-02a`, `fp-to-02b`, retired `00`, `01A`, and
separate `02` tokens must stop instead of opening a compatibility branch.
Nothing in this adapter authorizes image generation, paid or external action,
03V, or 04.

## Optional Surface Adapter

The commands above may be exposed in Grok through the local adapter:

`.grok/skills/idol-harness-step/`

The adapter delegates to `skills/idol-orchestrator/`,
`automation/harness-execution-contract.yaml`,
`automation/harness-stage-registry.yaml`, and the owning shared skill/schema.
It does not create a separate Grok instruction layer or stage authority. Invoke
the alias directly if needed:
`/idol-harness-step 02a`

## How These Commands Work

When you issue any of the above:

1. The system follows the shared root startup contract: `AGENTS.md`,
   `wiki/production-system.md`, `wiki/INDEX.md`, then only the activated
   policy/schema/shared skill/run sources. It resolves the Founder-named run
   and canonical local state, and reads
   `handoff/grok/current.md` only when the command explicitly resumes a
   cross-surface handoff. A Grok-owned harness run is not converted into a
   handoff and does not load `handoff/grok/archive/**` by default.
2. Runs the minimal orchestrator state diagnosis.
3. Jumps to the correct starting artifact for that stage (following the official harness order).
4. Continues from there through the owning shared skill. Multi-section
   authoring uses one physical section shard at a time, followed by validation,
   lossless merge, and whole-film continuity/repetition QA.
5. Maintains English for all internal work.

This eliminates the need to repeatedly say "start from the shared orchestrator,
resolve canonical state, and continue from X".

## Adding New Step Commands

If a new major stage is introduced, update the canonical registry, owning
schema/skill, and validators first; then add an alias here and in the optional
surface adapter. Do not add a command only because a section shard, review
sheet, helper script, or optional sub-artifact exists.

Current command map:

- `pre00`: Route Discovery.
- `pre00s`: Song Direction Design.
- `audio-analysis`: Candidate Track Analysis.
- `audio-motion`: Audio Rhythm Evidence Map.
- `00a`: Song Production Lock.
- `front-planning`: Front Planning, including internal 01R/01R-C work.
- `01`: Section Direction Expansion.
- `02a`: Core-Cut and Branch-Cut coverage; `02a-review` is its Founder gate.
- `02b`: one prompt per Branch Cut; `02b-release` is the generation approval gate.
- `02b-gen`: Branch-Cut Generation; `02b-review` is Generated Branch-Cut Review.
- `audio-branch`: Audio Production-Cut Placement (legacy alias retained).
- `03v`: Motion Direction; `03v-review` is playback review.
- `04`: Edit Assembly and Playback QC.
- `04fx`: Edit Finishing and Effects.
- `05`: Master Package.

Shared resolver example:

```text
ruby scripts/idol_harness_stage.rb resolve storyboard
ruby scripts/idol_harness_stage.rb resolve 02A
```

## Internal Language Rule Reminder

All reasoning and document writing performed while executing any of these step commands must be in English (per root AGENTS.md).

## Full Maintenance Standards

Detailed rules for keeping the entire harness (maintenance process, duplication avoidance, stage granularity, evolution hygiene) live in:
`wiki/harness-maintenance-rules.md`

Read this before making structural or documentary changes to the harness. Language precision rules are in AGENTS.md and wiki/production-system.md.
