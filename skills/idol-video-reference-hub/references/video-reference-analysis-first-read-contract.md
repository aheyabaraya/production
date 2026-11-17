# Video Reference Analysis First-read Contract

This contract keeps downloaded evidence and its reusable scene reading together
without turning source observation into title-specific creative meaning.

## Ownership

- `source-materials/video-sources/**` owns source identity, local media bytes,
  hashes, probe metadata, navigation sheets, and one canonical reusable Layer
  A/B analysis for the current source revision.
- The current run's Front Planning 01R/01R-C or other named MV research
  stage owns only current-project selection, disposition, transfer, section/job
  assignment, and binding. Historical CF20 consumption is frozen compatibility
  only and is not an active MV route.
- `source-materials/video-sources/READ-FIRST.md` is a generated pointer surface.
  It points to, but does not replace, the source-owned analysis.
- `catalog/references/reference-catalog.yaml` is the cross-media lookup and
  usage-history pointer layer. It may point to a complete analysis but never
  becomes that analysis or grants current-run application.

## Required read order

1. Open `source-materials/video-sources/READ-FIRST.md`.
2. Find the exact source identity.
3. If a complete whole-source analysis is registered, read it before opening
   video or sheets. `complete_scoped` is not whole-source complete.
4. Open source pixels only when bytes or meaning changed, the analysis is
   incomplete, a concrete conflict exists, or the Founder requests re-review.
5. If no complete analysis exists, inspect source video and exact range evidence
   before authoring the source-owned analysis.

## Complete analysis minimum

Use natural production language. A complete Markdown analysis has these exact
headings:

1. `## 분석에 실제로 사용한 자료`
2. `## 영상 전체의 큰 흐름`
3. `## 상세 장면 기록`
4. `## 공용 관찰에서 허용하는 전이 경계`
5. `## 공용 관찰에서 제외하는 전이 경계`

The first section names only files actually inspected and records their
repo-relative paths and SHA-256. `complete` requires the original video plus a
hash-bound one-second whole-source or selected-range analysis surface. Add
selected ranges, sub-second sheets, and selected frames only when used.

The whole-flow section explains how the source moves from opening through
turns, escalation, release, and ending. The detailed section uses timestamps
and states:

- who or what is visible and the relation among people;
- where the event happens;
- what each person or object does, in order;
- body direction, travel, posture, hand and foot action;
- expression, gaze, and visible reaction;
- object, environment, light, and material change;
- camera height, distance, direction/angle, movement/hold, and speed when
  observable;
- subject placement, crop, foreground/background depth, and negative space;
- edit entry, exit, match, interruption, and the before/after state.

When a multi-frame sheet is the navigation surface, or a selected still/frame/
cell will become a scene reference for Front Planning / 02B, close first-read
with the media-shaped observation contract in
`skills/idol-front-planning-director/references/director-operating-contract.md`
(top-level H2 `## 02B-Shaped Source Observation`): sheet flow plus nested stills
for selected
anchors, or one nested still tree for a single surface. Do not substitute a
whole-sheet mood note or invent motion a sampled sheet cannot prove. Mark
uncertainty and inspect playback or a denser range when the missing fact
matters.

The final two sections state reusable transfer and exclusion boundaries without
choosing a current project. Source faces, bodies, styling, brand, fictional
world, and art style never become current-title identity merely because action
or camera grammar may later be selected.

## Status rule

- `complete`: all required headings, exact inputs, whole flow, detailed
  timestamped observations, transfer boundaries, and exclusions exist.
- `complete_scoped`: a hash-bound supplement for declared time ranges only.
  It is not whole-source `complete`.
- `hold_incomplete`: one or more of those are missing. State exactly what still
  needs viewing or writing.
- `rejected`: the source evidence cannot support a reusable reading; preserve
  the exact source identity and reason.
- `superseded`: a newer hash-bound source analysis owns the same source revision.

Machine validation checks structure, paths, hashes, declared status, and for
`complete_scoped` parent identity, original video identity, and numeric covered
ranges only. Creative adequacy remains a human or assigned-model judgment.

## Scoped completion

Use `complete_scoped` for a supplement that covers named events without
claiming a new whole-source first-read. Keep the parent first-read bytes.

- `analysis_inputs` includes `parent_complete_analysis` whose path and SHA-256
  match same-source records whose only status is `complete`. The same bytes with
  mixed `complete`/`hold_incomplete`/`rejected` rows are contradictory and cannot
  bootstrap. A parent that is only `hold_incomplete` also cannot bootstrap.
- `original_video` must be this source manifest's actual primary video, not an
  unrelated hashed file.
- Declare `covered_ranges` as `{start_seconds, end_seconds}` pairs, finite and
  nonnegative, with `end_seconds >= start_seconds`. Do not add a second pointer
  schema. Sequence Unit five-frame timestamps are unit evidence; they do not
  replace extraction coverage.
- Extraction evidence is a hash-bound sheet manifest
  (`one_second_analysis_surface`, `selected_range_surface`, or
  `subsecond_turn_surface`) that names the same original video and contains
  every cadence point from start through end at its `interval_seconds`
  (at most one second). This is complete sampled coverage at the declared
  cadence, not continuous playback proof, and not a new creative criterion.
  Five scattered stamps are not complete sampled coverage.
- Scoped Markdown still needs the used-materials heading, transfer and exclusion
  headings, and timestamped observation locators, including canonical structured
  `cell_or_frame_locator` / `cell_locator` rows. It must not invent a whole-video
  flow to satisfy `complete`.
- If a source has only `complete_scoped` records, whole-source `analysis_state`
  stays `not_analyzed`. Scoped records must not make the source
  `detailed_analysis_available`. Existing `complete` whole-flow rules are
  unchanged.
- Unregistered or held scoped records are not lookup-ready.
