# Editing QC Detail

Use this reference after `skills/idol-editing-qc/SKILL.md` when actually
building, revising, rendering, section-sharding, source-intaking, auto-assist
indexing, or QCing a real edit.

## Contents

- Section-Sharded 04 Work
- Upstream Intent Context
- Runtime Cache And Render Contract
- Audio Marker First Contract
- Initial Analysis Alignment Pass
- Automatic Recognition Assist
- Source Intake And Generated Source Handoff
- Cut Decision Rules
- Contact Sheet And QC Granularity
- Frame-Canonical Recipe And Boundary Handles
- Color, Audio, Retime, And Delivery QC
- Tone And Source-Family QC
- Speed And Effect Rules
- Cache Storage And Closeout
- Fast Commands
- Memory Promotion

## 04 Editorial Namespace

Do not rename every use of `frame` or `cut` to Branch Cut:

- Core Cut and Branch Cut remain upstream 02A/02B/03V units.
- An Edit Slot is a planned position in `idol_edit_marker_plan.v6`.
- An Edit Segment is one selected source range in `idol_edit_recipe.v3`.
- An Edit Boundary or cutpoint joins two Edit Segments.
- A video frame is an actual timebase sample used for timing and QC.
- An animation keyframe is valid only for a real animated parameter; it never
  names an upstream Branch Cut.

The mapping is deliberately not one-to-one. Preserve exact upstream lineage in
each Edit Slot, then let actual playback and selected audio decide whether 04
splits one Branch Cut across multiple Edit Segments, combines several Branch
Cuts, or omits a passed branch without losing its continuity job.

## Section-Sharded 04 Work

After passed 03V handoffs, section-sharded 04 work runs inside the fresh,
Founder-visible physical Edit Director room. It is a separate execution unit
from the post-02A image-motion lineage. The Edit Director may direct disjoint
physical Edit `worker_high` shards through the run-resolved registered provider for long songs, large generated-source pools,
replacement-heavy edits, or high-candidate sections. Capacity and concurrency
come from the immutable run provider snapshot; this repository sets no
project-local numeric quota. Owner collision checks and Director-review
backpressure win.

Each shard owns one exact section or connected chunk, program/time range,
boundary scope, and declared output paths. It may author a marker-plan slice,
source candidate index, contact sheet, proxy preview, and recipe fragment, but
it is never final edit truth and returns only to Edit Director. A shard cannot
open a creative grandchild, merge another shard, or write the canonical map or
timeline. The Edit Director is the single writer of the canonical source-clean
recipe/timeline and `04-edit-map.yaml`, and performs the whole-video boundary and
continuity merge against the last-passed CAS baseline.

Every multi-file shard return exposes one aggregate manifest with exact child
paths and SHA-256 values. The Director Dispatch Index and Director Boot Pack
are pointer-only projections containing lineage, scope, digests, manifest
pointers, review/hold state, and next actions; they do not embed media, raw
pools, full transcripts, or creative bytes. A Founder correction remains in
the same relevant Edit Director or shard room as a new immutable Department Dispatch v8
attempt under the same logical lineage; it creates new attempt and
dispatch ids and never overwrites a prior attempt. The Edit Director returns
the reviewed merged 04/05 package to Overall, which alone may promote it.

The final truth remains the merged source-clean recipe plus `04-edit-map.yaml`;
shard previews are evidence and cannot by themselves authorize final render.

Each 04 shard must carry:

- selected-audio section ids, output time range, and nearby beat/onset markers
- upstream 01/02A/02B intent refs, including `edit_readiness_seed` when present
- upstream front-planning/01/02A/03V story-flow refs when present, especially
  section cause/effect, object or space state, space/visible-feeling progression,
  viewer-attention handoff, `source_production_cut_images`,
  `previous_next_continuity`, and `edit_handoff`
- the v6 marker-plan Production-Cut and screen-progression lineage: source 03V
  cue ids, Official-Core ids, exact Branch ids when present, or the current-run
  non-Production-Cut source plus the Branch Cut whose continuity job it replaces
- source candidates with first useful action, source-action marker, duration,
  geometry, and quality notes
- proxy preview or contact-sheet proof for the section when candidate choice is
  not obvious
- merge checks for audio-marker alignment, story-flow continuity,
  section-boundary transition, source-action marker alignment, source quality,
  geometry, preserve ranges, UI/blank-frame removal, and source-clean final
  inputs

Do not move to the next edit section or transition until the current shard
records in/out timing, cut trigger, source action marker, motion continuity,
story-flow continuity, space/visible-feeling progression, directorial transition
intent, audio-marker alignment, derivative impact when relevant, output paths,
open questions, and `pass` / `fail` / `blocked` / `needs_founder` status. Shard
previews are evidence, not approval to skip the marker plan.

When shards are merged, re-check boundary transitions, repeated-hook variation,
source-family tone, geometry, black frames, source-out overruns, and final audio
sync on the full master. Confirm that the actual intro boundary establishes the
chosen identity, completes the viewer promise or question and hook seed or
intentional hold, and the first full hook and middle return preserve one
recognizable music-and-screen carrier while developing it.
Do not approve a final render from shard previews alone.

## Upstream Intent Context

Use earlier graph-engineering outputs to avoid blind source hunting:

- 00A gives song structure, song feeling, and editability intent.
- front-planning readiness gives section story/object/space/camera drafts,
  space/visible-feeling progression, current-title album visual asset use, and upstream
  transfer boundaries when present.
- 01 gives choreography/performance/MV function, `director_chain` pressure,
  and `screen_cause_effect`.
- 02A/02B give expected screen action, source intent, generated-source
  assumptions, `pre_edit_marker_contract`, and any upstream
  `edit_readiness_seed`.
- Audio-Production-Cut Placement gives the reviewed order and selected-audio placement
  of passed Official Core/Branch image states without choosing camera motion or final cutpoints.
- 03V gives ordered Production Cut source anchors, visible motion bridge, temporal
  camera, `previous_next_continuity`, `edit_handoff`, playback evidence, and
  future edit-point basis.
- Review boards and cue sheets give slot timing, member focus, and visible
  action.

Read these as a map, not as a lock. 04 still has to prove:

- the actual source exists
- the first useful action is clean
- the motion peak or visible hit aligns with the music marker
- the planned source-action marker from `pre_edit_marker_contract` is actually
  present in the generated source, or the source is rejected/retimed/held
- the passed Production Cut anchors are actually present or defensibly substituted
  in source motion
- the source order and transition keep the section story, object/space state,
  space/visible-feeling progression, viewer attention, or deliberate contrast readable
- the candidate survives contact-sheet and preview QC
- the source quality and geometry match the final delivery policy

For efficiency, read only status/path fields and the relevant cue,
`director_chain`, `screen_cause_effect`, `source_production_cut_images`,
`previous_next_continuity`, `edit_handoff`,
`space_visible_feeling_progression`, `cuttable_motion_event`, `motion_density`,
`edit_handoff_intent`,
`edit_readiness_seed`, and Production Cut source/continuity fields first. Open larger prompt
packets or storyboard blocks only when the candidate choice is unclear.

## Runtime Cache And Render Contract

Use the cache ladder when many sources, candidate windows, or founder notes are
active:

- raw index
- proxy cache
- low-resolution full-flow preview
- targeted proxy previews
- locked recipe
- normalized final cache from selected original sources
- one full-quality final render
- final QC

Proxy files are iteration material only. They may drive review and candidate
selection, but final renders should read original sources or source-clean
normalized finals. Use `ffmpeg` as the default engine for trims, speed changes,
scaling, padding, concat, and simple transition effects. Use MoviePy only for an
experimental effect or fallback case that the ffmpeg recipe cannot express.

## Audio Marker First Contract

04 owns exact marker lock. Upstream artifacts may ask for rhythm-readable source
material through `cuttable_motion_event`, `motion_density`, and
`edit_handoff_intent` or a 01R/02A `edit_readiness_seed`, but they must not
decide exact `source_in`, `source_out`, `speed_factor`, final candidate,
geometry, or final cutpoint.

Likewise, upstream `pre_edit_marker_contract` is a planned alignment contract:
it carries the known music marker, cue-function marker, and intended
source-action marker before generation. 04 uses it as a target to verify against
actual source motion, then locks or rejects the real source timing from
playback evidence.

For 04, use the selected audio timeline and actual 03V playback as the
authority:

- read selected-audio analysis and the audio motion director map; if selected
  audio exists for video/MV-bound edit work and the map is missing or stale,
  hold and create or refresh it before the edit marker plan
- read the passed Audio-Production-Cut Placement and verify it against actual 03V
  playback; it is a planning placement, not a final cutpoint
- read local beat/onset evidence when exact marker work needs it
- create or update an edit marker plan when the edit needs more than prose notes
- record cue role, output range, nearby beat/onset/feature boundary, source
  candidate, source action marker, cut density, alignment basis, and pass/fail
  note before recipe lock
- consider a cut strong only when the audio marker, source action marker, and
  cue function overlap enough to make the move visible

## Initial Analysis Alignment Pass

Before building or revising the recipe, do the analysis pass that worked in the
early v1-v3 edit:

1. Read the upstream intent context enough to know the intended cue function and
   expected motion, without accepting it as edit truth.
2. Read the selected audio duration, section changes, BPM grid, strong onsets,
   lyric/phrase entrances, and cue sheet timing.
3. Read the current roughcut or current recipe as a flow object, not as truth.
   Mark what already works on the selected audio and what is only duration-fit
   but not marker-locked.
4. Scan candidate sources for first useful action, motion peak, face read, hand
   hit, foot hit, body landing, gaze lock, and camera move.
   Use automatic recognition only as a candidate-finding assist: motion peaks,
   scene cuts, coarse object/space tags, transcript hints, or pose/hand/body
   landmarks may point to review windows, but they do not lock member identity,
   source choice, source in/out, speed, geometry, or final cutpoints.
5. Read the section story flow before final source order: what just happened,
   what visible object/space/body/camera state must carry forward, whether the
   next cut should feel continuous, intentionally contrasting, or a motivated
   reset, how the background/space and screen-read feeling should progress, and
   what would make the edit look accidental.
6. For each slot, align three markers:
   - music marker: beat, onset, feature boundary, lyric entrance, section handoff
   - source action marker: visible body/action/camera event inside the source
   - cue function marker: why this slot exists in the song and MV structure
7. Only then write the structured `idol_edit_marker_plan.v6` artifact and move
   into recipe timing.

This pass is mandatory for new 04 runs because it is what made the early rough
edits feel musically placed before later founder-specific replacement work.
Skipping it tends to produce duration-matched cuts that technically fit but do
not land on the song.

## Automatic Recognition Assist

Use automated recognition in 04 only to reduce search space and create evidence
for human review. It can propose candidate windows, not approve them.

Allowed local assists with the current runtime:

- audio markers: BPM, beat grid, onset clusters, RMS/energy changes, and feature
  boundary candidates from `librosa`, `soundfile`, `numpy`, and `scipy`
- source health and metadata: duration, fps, resolution, codec, stream state,
  and black/silence checks from `ffprobe`/`ffmpeg`
- motion evidence: optical-flow motion peaks, first-useful-action windows, and
  frame/contact-sheet proof from `cv2`, `moviepy`, and `PIL`
- scene/cut support: scene-change candidates from `scenedetect` when useful

Optional ML assists may be added later, but they remain evidence-only:

- transcription (`whisper`/`torch`) can draft lyric or vocal timing candidates;
  generated vocals must still be checked against founder/Codex lyric truth
- pose, hand, or body tracking (`mediapipe`, OpenPose/MMPose-style tooling) can
  flag body route, hand lift, foot plant, or landing candidates; it must not
  replace visual QC
- object or space tagging can suggest props, space, or UI contamination; it must
  not replace contact-sheet inspection

Never let automatic recognition decide:

- final member identity or face quality
- final candidate selection
- exact `source_in`, `source_out`, `speed_factor`, final cutpoint, or geometry
- whether a feeling- or narratively important cut passes founder review
- whether broken hands, body proportions, facial drift, or source-family
  mismatch are acceptable

Record automatic recognition outputs as `automatic_recognition_assist` in
`04-edit-map.yaml` when used, and as `automatic_recognition_evidence` on the
relevant edit-marker candidates when it directly influenced a slot. A candidate
still passes only when audio marker, source action marker, cue function, contact
sheet, and preview QC agree.

## Source Intake And Generated Source Handoff

For every new raw, additional, replacement, or section-directed source pack:

- use only `generations/video/raw/additional/` for added active sources; if the
  retired misspelled `raw/addiontal/` folder contains files, stop intake and
  preserve it as evidence until selected bytes have a hash-bound migration plan
- record duration, fps, resolution, codec, and path before recipe use
- verify every recipe source exists and no `source_out` exceeds source duration
- inspect the first usable seconds before choosing `source_in`
- trim or reject UI/storyboard frames, visible reference panels, support strips,
  blank frames, static poster holds, and stale setup frames
- treat generated clips as source material, not as final timeline truth
- require internal edit events for high-energy sections: hand hit, body pass,
  foot plant, gaze lock, lane drive, camera rush, light shutter, hook landing,
  pair alignment, or final seal
- ask which frame contains the first useful action, which visible hit aligns
  with the onset cluster, whether the clip has enough internal motion for the
  assigned audio intensity, and whether a shorter extraction is cleaner than
  the whole clip

For new Production-Cut-to-video source packs, keep source chunks edit-sized. A
short `0-4s` source can use one strong Official Core or Branch anchor when its temporal route
is sufficient; longer or more complex sources may need multiple passed
Production Cut anchors on linked 03V boards. Do not cram several screen jobs into
one generated still when separate Branch Cuts would give the editor cleaner
actions. In 04, map those anchors to Edit Slots first; do not assume their count
must equal the final Edit Segment count.

## Cut Decision Rules

Use the selected audio timeline as the authority. A cut point is strong when at
least two of these align:

- beat, onset, or music-feature boundary
- lyric syllable, phrase ending, or section handoff
- visible body landing, hand hit, foot hit, gaze lock, or camera move
- R-slot function from the cue sheet

For professional timing and continuity cases, read
`professional-edit-decision-casebook.md`. Record the incoming cut method,
anticipation/exact-hit/afterbeat/offbeat relation, pre/cut/post-frame evidence,
story/attention handoff, no-effect pass, and route. Do not send an unresolved
timing or source problem to 04FX.

Do not cut every beat. Treat the following as section-sensitive heuristics, not
fixed genre templates or shot quotas; keep or reject each one from the current
selected audio, source motion, story flow, and playback evidence:

- opener: hold identity and micro motion
- rap: clipped hand, foot, body, and camera hits
- verse: controlled travel and readable shape change
- pre-chorus: lift, preload, axis alignment, and breath
- chorus: wide body read, hit-stop, point choreography, and punch effects
- bridge/tail: source-limited coverage is acceptable only if labeled
- finale: deceleration and final seal

## Contact Sheet And QC Granularity

- Use full-master 1-second sheets for whole-flow review.
- For changed cut boundaries, inspect targeted windows around the cut, including
  `-3,-2,-1,0,+1,+2,+3,+6` program frames. Frame `0` is the incoming first
  frame. Store plan/video hashes, rational FPS, requested/actual frame ids, and
  any incomplete edge window in the cutpoint-sheet manifest.
- For suspect generated or revised sources, inspect the first usable seconds at
  sub-second intervals before choosing `source_in`; first frames often carry UI,
  board, or stale setup material.
- For founder-disputed ranges, generate short preview candidates before full
  render. Keep selected and rejected candidates in a decision ledger.
- Check for 0.x-second alien inserts, source-family jumps, quality mismatches,
  black frames, final silence mismatch, and motion/body mechanics breakage.
- When an older accepted range is preserved, compare it against the final
  source-clean version so quality does not visibly drop at the preserve seam.

## Frame-Canonical Recipe And Boundary Handles

- New locks use `idol_edit_recipe.v3`; validate with
  `scripts/idol-video-python scripts/validate_edit_recipe.py RECIPE --require-v3`.
- Treat integer program frames as canonical and seconds as readability
  projections within half a frame. Use start-inclusive/end-exclusive ranges so
  adjacent segments share one boundary without a gap or duplicate frame.
- Read rational FPS and render geometry from the recipe. Do not make proxy or
  final profiles choose the aspect ratio.
- Bind source bytes and the exact run-owned probe report by separate SHA-256
  before final source in/out. A readable filename or mutable probe pointer is
  not sufficient lineage.
- 04 owns duration-preserving xfade handles because they extend source in/out.
  Record one handle id, exact adjacent slots, fixed program cut frame,
  transition frames, and pre/post allocation; then re-preview the 04 recipe.
  04FX may reference that handle but may not invent or expand it.
- Keep constant retime and cadence method explicit. Variable/optical-flow work
  remains an external 04 operation until the local renderer and cadence QC can
  prove it; it cannot silently fall back to frame sampling.

## Color, Audio, Retime, And Delivery QC

- Probe source range/space/transfer/primaries, pixel format/bit depth, SAR/DAR,
  rotation, field order, frame rate/time base, and VFR risk. Preserve `unknown`
  metadata until the recipe records an explicit interpretation; do not label an
  untransformed source Rec.709 merely by writing metadata tags.
- Lock the working and delivery color spaces plus the actual transform. Bind
  any LUT by path/hash and pass it on the exact preview before final inclusion.
- Separate a mezzanine master from platform derivatives. A derivative records
  the master hash, crop/pad/background policy, and reframe safe area instead of
  becoming a second edit truth.
- Lock mezzanine container, video codec, audio codec, and chroma/pixel-format
  policy together. Use H.264/AAC only when that is the declared master policy;
  a ProRes/PCM master must be a compatible MOV with an explicit 10-bit pixel
  format and must not be silently downgraded during `final` render.
- Measure selected-audio hash, sample rate, channel layout, program duration,
  integrated LUFS, LRA, true peak, clipping/sample peak, and lead/trail silence.
  Report against recipe targets; never auto-normalize during QC.
- For every retimed range, inspect duplicate/freeze/cadence candidates and then
  visually review body mechanics, face/gaze speed, hands, feet, garment motion,
  and camera judder. Automatic measurements cannot pass these surfaces.

## Tone And Source-Family QC

Mixed-source edits need a visual-quality pass in addition to timing:

- compare brightness, white/blue glare, saturation, contrast, and face/body
  readability across old raw, new generated source, preserved ranges, and final
  source-clean segments
- treat a tone/quality jump as an edit issue when it distracts more than the
  cut itself
- prefer grade or source-clean lineage fixes before covering a mismatch with an
  effect
- if a source-family jump is founder-accepted or musically justified, record
  why it stays and confirm it recovers within the next visible beat or action

## Speed And Effect Rules

- Speed up clips when the motion lags behind the song, but review for unnatural
  body mechanics above roughly `1.6x`.
- If a speed-up creates an output gap or weak landing, fill it with a compatible
  adjacent or backup hit instead of stretching dead air.
- Use the current selected audio's measured and listening-verified beat grid or
  double-time subdivision for small hand, shoulder, hair, foot, and camera
  accents only when playback supports it. Never carry a BPM number from another
  run into the active edit, and never treat a subdivision as the default cut
  grid.
- Use finishing effects only after the underlying section or contiguous chunk
  edit preview has passed. If cut timing, source choice, speed, or geometry is
  still unresolved, fix the 04 recipe first. Do not perform transition-effect
  authoring inside the cut-edit loop; push it to 04FX.
- Before one high-quality final master, require a 04FX **transition opportunity
  audit** for the passed window: every section boundary and strong
  onset/drop/lyric gate is marked `none_needed`, `safe_default_proposed`,
  `manual_fx_proposed`, or `return_to_04`. Safe defaults may propose short
  `dip_flash` / hit `punch_zoom` / rare fade accents; they still need FX
  preview pass. See
  `skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md`
  and example routing in
  `skills/idol-edit-finishing-fx/references/professional-edit-effect-casebook.md`.
- When Founder feedback is "awkward / insufficient / stiff / no transition", keep 04 cut ownership
  and run the 04FX awkwardness playbook + casebook first unless playback proves
  the cut itself is wrong.
- Route passed-preview transition, beat-accent, tone, world/object overlay, and
  source-reinforcement work through `skills/idol-edit-finishing-fx/SKILL.md`
  and `schemas/edit-finishing-fx.schema.json`.
- Local FFmpeg capability is intentionally broad now; do not under-use the
  catalog out of habit. The guard is not effect scarcity; the guard is that
  every effect must have a visible job and pass preview QC.
- Use effects when they make a real edit job clearer: a cut transition, a music
  accent, world/object continuity, tone/source-family unification, readable
  source reinforcement, or compact lyric/message emphasis.
- Place lyric-trigger effects on exact words or endings only when the word is
  audible at that moment or the founder names it. Raw lyric text is a cue; the
  effect still needs a visible body, object, camera, light, or space behavior.
- Preserve more than identity fragments. Effects must protect member face,
  hands, feet, core body path, garment motion, full space, world atmosphere,
  visual system rules, color/light limits, and the track's tone-and-manner.
- Reject effects that hide a weak cut, damage body mechanics, flatten the MV
  world, create tone drift, make the cut feel late or early, add mobile clutter,
  create flicker/flash risk, or turn the master into a repeated effect demo.
- If an effect changes perceived timing, return to the 04 recipe, patch the cut
  or speed, and re-preview before final render. Boundary `xfade` shortens video
  unless handles are planned; always re-check selected-audio sync.
- High-quality render should happen once from the locked/passed edit recipe,
  passed finishing FX map (including transition opportunity audit), compiled
  passed effects, and source-clean inputs. After master lock, defect-only final
  QC should not invent new creative effects by default.

## Cache Storage And Closeout

- Keep cleanup track-scoped. Do not delete source material simply because it was
  not in an early preview; delete only after the final recipe source keeper
  index shows it is unused or after the founder explicitly rejects it.
- Preserve the final master, final recipe, source keeper index, final QC sheets,
  package, title registry pointer, member/album assets, and any explicitly
  marked exception artifacts.
- Preview proxies, superseded masters, old contact-sheet caches, batch JSONL
  caches, full-size handoff duplicates, and raw-derived social drafts may be
  deleted or compacted only after their selected output or lightweight pointer is
  registered.
- Public social clips should come from the final source-clean master or the
  final source-clean recipe unless the founder explicitly approves raw-source
  posting.

## Fast Commands

Source intake:

```bash
scripts/idol-video-python scripts/idol_video_source_intake.py --run-root runs/ALBUM_KEY/TITLE_KEY/RUN_ID
```

Preview render:

```bash
scripts/idol-video-python scripts/idol_video_sync_workbench.py \
  --run-root runs/ALBUM_KEY/TITLE_KEY/RUN_ID \
  --recipe runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video/qc/sync-workbench-v1/final-master-recipe-vN.yaml \
  --preview-start 40 \
  --preview-duration 18 \
  --preset ultrafast
```

Full render:

```bash
scripts/idol-video-python scripts/idol_video_sync_workbench.py \
  --run-root runs/ALBUM_KEY/TITLE_KEY/RUN_ID \
  --recipe runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video/qc/sync-workbench-v1/final-master-recipe-vN.yaml \
  --output runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video/master/final-master-vN.mp4 \
  --qc-sheet runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video/qc/contact-sheets/final-master-vN-1sec-qc-contact-sheet.png \
  --preset veryfast
```

## Memory Promotion

Promote only review-backed lessons:

- a founder correction that improved the edit
- a repeated candidate-selection pattern
- a speed/effect threshold that changed QC outcome
- a source limitation future automation must not hide

Keep run-specific timestamps in the run memory. Put only reusable behavior in
`wiki/performance-memory.md`.
