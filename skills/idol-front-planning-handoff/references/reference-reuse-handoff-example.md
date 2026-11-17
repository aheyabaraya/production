# Reference reuse handoff example

> NONCANONICAL TEACHING EXAMPLE. The paths, ids, hashes, sections, roles, and
> wording below are placeholders. They are forbidden as creative truth,
> production input, a prompt default, or a source for any active run.

## Input intent

A later section owner should reuse an already completed reference
interpretation without reopening a broad frame sheet.

## Current evidence

- Canonical plan: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/front-planning-vN.yaml`
- Pointer index: `catalog/albums/PROJECT_ID/TITLE_ID/reference-index.yaml`
- Selected-frame manifest:
  `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/REF_SET/manifest.yaml`
- Active section: `SXX`
- Selected reference: `REF_ACTION_ROUTE_A`

Every current path must be accompanied by the SHA-256 of its current bytes.

## Compared routes

1. Reopen the whole sheet and reinterpret it in the new session.
   Rejected because the interpretation is already complete and the sheet is
   navigation evidence.
2. Copy the prior analysis into a new handoff.
   Rejected because it creates a second semantic owner.
3. Point to the canonical analysis, active section, selected reference row, and
   individual selected frames.
   Selected because it preserves one owner and limits pixel reads to the exact
   direct inputs.

## Selected observable decision

The later owner reads the canonical plan, resolves `SXX` to
`REF_ACTION_ROUTE_A`, verifies the selected-frame manifest, and opens only
`REF_ACTION_ROUTE_A_PHASE_01` through `PHASE_03`. A physical session change
does not authorize a new interpretation.

## Owner fields

```yaml
canonical_owners:
  front_planning:
    path: runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/front-planning-vN.yaml
    sha256: <sha256-of-current-front-planning-bytes>
  reference_index:
    path: catalog/albums/PROJECT_ID/TITLE_ID/reference-index.yaml
    sha256: <sha256-of-current-index-bytes>
  selected_frame_manifest:
    path: runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/REF_SET/manifest.yaml
    sha256: <sha256-of-current-manifest-bytes>
minimum_read_order:
  - front_planning target and whole-video lock
  - active section SXX
  - reference row REF_ACTION_ROUTE_A
  - selected-frame manifest sequence REF_ACTION_ROUTE_A
selected_frames:
  - REF_ACTION_ROUTE_A_PHASE_01
  - REF_ACTION_ROUTE_A_PHASE_02
  - REF_ACTION_ROUTE_A_PHASE_03
re_review_only_if:
  - source bytes or meaning changed
  - interpretation or disposition is incomplete
  - identity, safety, or feasibility conflict appears
  - Founder explicitly requests re-review
current_gate:
  founder_review: <pending-or-passed-state>
  downstream_entry: <held-or-open-state>
```

The run-specific handoff may add section-to-reference pointers, but it must not
copy the detailed interpretation or turn this example into current creative
content.
