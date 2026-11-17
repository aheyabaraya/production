# Common Contract Contamination Audit - 2026-07-04

Purpose: verify that the July 4 harness additions do not accidentally force one
album, title, run, reference hub, or INK asset path onto unrelated album work.

## Audit Result

Pass with follow-up corrections.

The new album reference/contact-sheet index, front-planning readiness asset
plan, and INK guard language are scoped correctly when they use placeholders:
`ALBUM_KEY/TITLE_KEY`, current run source refs, current title registry, and
current-title album asset manifests.

## Corrected

- Removed the concrete Jellobus downloaded-reference hub path from shared
  `wiki/artifact-management-system.md`. A project-specific hub should be cited
  only from the run, readiness, source cache, or reference index that owns it,
  not named as a common default.
- Kept INK asset paths only in INK-owned files or as explicit example language.
  Shared contracts now say INK-style means pattern only.
- Extended current-title album asset priority to track-poster and beat-source
  identity paths. Album identity-source copies under
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` are preferred before base
  member profile fallback when declared.

## Safe Shared Patterns

- `catalog/albums/ALBUM_KEY/TITLE_KEY/reference-index.yaml` and
  `contact-sheet-index.yaml` are pointer indexes only; they do not create a new
  common media dump.
- `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` is for founder-locked
  current-title visual assets only.
- 03V `planning_carry` carries the current run's planning, album assets, and
  reference functions into video prompts without promoting those choices as
  future defaults.
- 04 `story_flow_continuity` and `directorial_transition_intent` let the edit
  follow the current section story flow while preserving 04 ownership of exact
  source timing, speed, candidate selection, geometry, and cutpoints.
- 04 section-sharded readiness now requires story-flow, space/visible-feeling,
  and directorial-transition fields together rather than treating them as
  optional alternatives.

## Remaining Watch Items

- `scripts/idol_title_output_registry.py` still defaults `album_key` to
  `aurora-m`, which is acceptable for the internal AURORA-M production root but
  should be overridden explicitly when a future album/title uses a different
  album key.
- Existing untracked or legacy INK/catalog asset paths remain valid only as
  records for their own title. Keep them out of new title manifests.
