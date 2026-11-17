# Isolation Boundary

## Purpose

`idol-ops-tracker` is a management read-model and private operating ledger. It is not part of the IDOL production harness and has no authority to promote, repair, rewrite, or invalidate production truth.

## Write owner

The production server constructs `TrackerStore()` with its default root. That store rejects any data path outside this tool directory and writes atomically to:

```text
tools/idol-ops-tracker/data/tracker.json
```

No API action accepts an arbitrary output path. Supported actions are add/update operations for tracker projects, milestones, blockers, decisions, and AI execution records. Delete actions are intentionally absent.

## Source observer

Source paths must be relative to the IDOL repository. Resolution rejects absolute paths and `..` escapes. General source probes read filesystem metadata only. Git probes are read-only and omit untracked scanning.

The MV worker view has one narrow body-read exception, still read-only:

- `runs/*/*/*/run-manifest.yaml`: routing keys, status, run sequence, lineage pointer, and `created_at`;
- `RUN/work/director-dispatch-index.yaml` when present: pointer-only dispatch rows;
- otherwise `RUN/work/department-dispatches/*.yaml`: dispatch/lineage identity, lifecycle events, task role, stage/section/output-path scope, recipient, review, and promotion state;
- `cf/runs/CF_*`: directory birthtime/mtime only.

The projection does not copy objectives, compiled prompts, creative prose, media, transcripts, source pools, or output contents into tracker storage. It never writes a DDI or repair artifact back into the run.

The MV board excludes obvious CF, SNS operations, still-board, and retirement manifests from its open-MV summary. Within one album/title family, `MAIN`, `SUB`, and `BASE` are navigation-only roles derived from nonterminal state, shared `previous_run_root`, and `run_sequence`. They do not declare a canonical production owner, select creative truth, or create Founder approval.

## Authority separation

- Tracker baseline lock: Founder-approved measurement scope for this dashboard.
- Production gate: existing stage/section/creative approval owned by the active IDOL route.
- Evidence check: file-path existence, not semantic or creative adequacy.
- AI execution state: operational activity, never completion proof.
- Dispatch `launched`: a registered lifecycle state, not proof the task is still alive.
- Dispatch `returned`: a return awaiting independent Director review, not PASS.
- Dispatch `reviewed`: still separate from Overall promotion.

These axes remain separate in the data model and UI.

## Harness surfaces changed by installation

None. Installation consists only of files below `tools/idol-ops-tracker/`. The local `.app` is generated under its ignored `dist/` folder. No login item, `/Applications` install, launcher registry, schema, skill, policy, run artifact, wiki page, CF source, business source, or web source is modified.
