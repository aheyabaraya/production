# File contract

The canonical shared state is already run-owned:

```text
research/front-planning-v1.md
work/front_planning_integration/canvas-state.json
work/front_planning_integration/shared-context/current.json   # only after an explicit checkpoint
```

Do not mirror those files into every terminal/session. A handoff names the
current files plus SHA-256 values, selected asset IDs, target role, reason, and
one bounded instruction:

```text
work/front_planning_integration/handoff/tasks/FPHT-YYYYMMDDTHHMMSSZ-XXXX.json
work/front_planning_integration/handoff/returns/              # optional human/operator summary only
```

The Raw-TUI payload is one line, not a copied context:

```text
Read RUN/work/front_planning_integration/handoff/tasks/FPHT-....json. Do only its bounded task and return at most N characters. Do not sync sessions, replay transcripts, or write canonical Front Planning files.
```

## Reusable reference-analysis bridge

When the task is to let a later session reuse completed reference
interpretation, keep a pointer-only bridge under the active run:

```text
handoff/front-planning-reference-reuse-vN.md
```

The bridge contains only:

- current canonical owner paths and SHA-256 values;
- the ordered minimum reads;
- active section pointers and stable reference ids;
- exact sequence and frame ids already selected;
- the conditions that permit re-review;
- the current Founder and downstream gate.

The detailed interpretation, preserve/discard rationale, and section direction
stay in their canonical owners. The bridge must not become a second creative
report.

For a sequence that will govern exact future pixels, the owning selected-frame
manifest uses this generic shape:

```yaml
sequence_id: REF_SEQUENCE_A
source_asset_id: SOURCE_ASSET_A
direct_use_mode: sequence_direct
target_section_ids: [SXX]
review_strip:
  path: runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/selected/review-strip.png
  sha256: <sha256-of-current-review-strip-bytes>
ordered_frames:
  - frame_id: REF_SEQUENCE_A_PHASE_01
    order: 1
    path: runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/selected/phase-01.png
    sha256: <sha256-of-current-frame-bytes>
    function: <bounded observable phase>
preserve: <existing selected grammar>
discard: <existing rejected elements>
```

The review strip proves order for a human reviewer. Each `ordered_frames` row
is the direct pixel input. Do not replace it with the whole sheet or strip.
See `reference-reuse-handoff-example.md` for a noncanonical teaching example.

## Selected local reference intake

The existing capture/crop route stays the owner of acquisition. After a human or
creative selection is written as an `idol_reference_fragment_crop_lock.v3`, use:

```bash
scripts/idol-video-python development/front-planning-workbench/tools/reference_intake_from_crop_lock.py \
  --run-root runs/ALBUM_KEY/TITLE_KEY/RUN_ID \
  --crop-lock runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-fragment-crop-lock-vN.yaml

python3 development/front-planning-workbench/tools/workbench.py validate-reference-intake \
  --intake runs/ALBUM_KEY/TITLE_KEY/RUN_ID/work/front_planning_integration/reference-intake/current.json \
  --check-files
```

Then use **Sync intake** in the native Workbench. When the app is closed, an
operator may apply the already-validated packet atomically:

```bash
python3 development/front-planning-workbench/tools/workbench.py apply-reference-intake \
  --canvas runs/ALBUM_KEY/TITLE_KEY/RUN_ID/work/front_planning_integration/canvas-state.json \
  --intake runs/ALBUM_KEY/TITLE_KEY/RUN_ID/work/front_planning_integration/reference-intake/current.json
```

This is local filesystem work only. It does not invoke yt-dlp, crop images,
create a contact sheet, call a model, or add candidates to Sequence Rail.
