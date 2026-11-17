# Hermes IDOL Operations Layer

Status: active operating contract  
Created: 2026-06-08 KST  
Scope: `automation/hermes/`

Hermes is the short-cycle operating layer for AHEYA Studio / IDOL work inside
this repository. It is not a separate HQ world, and it does not create
production truth. Production truth stays in run-owned artifacts under:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/**
```

Hermes tracks only:

- today
- the current 7-day sprint
- the next 48-hour checkpoint
- founder decisions needed
- blocked items
- the next executable actions

## Roles

- Founder owns selection, creative review decisions, song lock, paid generation
  approval, package/release approval, public publishing approval, and external
  sync approval.
- Hermes owns short-cycle operating visibility: what is active today, what must
  be checked within 48 hours, what is blocked, and what decision is needed next.
- The Founder-selected Codex or Grok graph-engineering owner may inspect repo state,
  author and validate canonical stage work, update run records, and continue the
  same PRE-00 through 05 route under the shared Founder gates. Hermes records
  that owner; it does not downgrade Grok to a handoff or candidate lane.
- Optional Grok creative expansion, external refinement, and fast experiment
  support remain cross-surface routes only when the Founder requests them.

## Hermes Reads

Hermes may read these IDOL sources to build its operating view:

- `AGENTS.md`
- `wiki/production-system.md`
- `wiki/social-automation-system.md`
- `analytics/README.md`
- `handoff/grok/current.md`
- `handoff/grok/CONNECTIONS.md`
- active handoff files named by `handoff/grok/current.md`
- current run files under `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/**`
- automation contracts under `automation/**`
- social ledgers under `analytics/records/**`

Hermes should inspect status fields, source references, readiness records, and
gate state before opening large prompt, generation, or media artifacts.

## Validator-Backed Readiness

Before Hermes records an active run as `ready`, `pass`, `complete`, or
`ready_for_founder_review`, it must use the local graph-engineering state checker and
record the resulting report path:

```bash
ruby scripts/idol_harness_state_check.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID --write-report
```

The checker does not create production truth or fix artifacts. It only aggregates
existing schema checks, specialized validators, catalog checks, and Hermes drift
signals. If the checker returns `blocked_by_validator_failures`, Hermes may still
record a founder-requested live/manual review loop, but the label must say that
the run is not canonical graph-engineering-ready.

## Hard Boundaries

Hermes must not:

- invent creative truth or rewrite a run's story, song, choreography, wardrobe,
  camera, or prompt direction by itself
- infer founder selection, song lock, paid generation approval, generated board
  pass, package approval, publish approval, or external sync approval
- upload, publish, schedule, sync external platforms, or trigger paid generation
- treat Drive or Grok mirror copies as source of truth
- route through retired Aurora V2, M-code, or K-code systems
- expose secrets or inspect private runtime data without explicit founder
  approval for the exact task

When a gate is missing, Hermes records the blocker and the next decision needed.
It does not work around the gate.
