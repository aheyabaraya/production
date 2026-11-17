---
name: idol-editing-qc
description: Use for IDOL music-video editing, professional cutpoint and continuity decisions, master/cutdown assembly, frame-canonical recipe timing, raw/additional video source intake including passed manual 04VFX shot candidates, beat/lyric/onset sync, contact-sheet candidate selection, section preview rendering, edit finishing handoff, color/audio/retime/delivery QC, and promotion of edit lessons into run memory.
---

# IDOL Editing QC

Use this skill after founder review/video sources exist and the task is to build,
revise, or validate an IDOL MV edit.

## Execution Ownership

After all required 03V playback handoffs pass, 04 opens one fresh,
Founder-visible physical Edit Director room. It starts from an exact
Department Dispatch Contract v8 naming the edit scope, required skills,
hash-bound sources, output paths, Founder epoch, and stop conditions. This is a
separate lineage from the post-02A image-motion session: it never reuses that
room, carries its chat, or lets image-motion own edit truth. The Edit Director
owns the 04 review stage, canonical edit-map/timeline merge, and whole-video
boundary review, then returns one hash-bound 04/05 package to the Overall
Director. Edit Director has no promotion or final-acceptance authority.

When the recipe is long, source-heavy, or needs isolated timing work, the Edit
Director may direct disjoint physical `worker_high` Edit shards through the
run-resolved registered provider. Capacity and
concurrency resolve from the immutable run provider snapshot; this repository
sets no project-local numeric quota. Director-review backpressure and owner
collision always win. Each shard
owns an exact section or connected chunk, program/time range, boundary scope,
and declared output paths. It returns only to the Edit Director and never
writes the canonical edit map, canonical timeline, or final merge. A worker
does not open a creative grandchild; an oversized scope returns exact unowned
subscopes to the Edit Director for sibling dispatch.

The Edit Director is the single writer for the canonical v4 `04-edit-map.yaml`,
v6 marker plan, v3 recipe/timeline merge, and CAS baseline. Shard returns are
noncanonical working evidence until that review and merge. Every multi-file
return exposes one aggregate manifest with exact child paths and SHA-256
values. The Director Dispatch Index and Director Boot Pack remain pointer-only:
they expose lineage, scope, digests, manifest pointers, review state, holds,
and next actions, never raw media, full transcripts, or creative bytes.

Founder revisions stay in the same relevant Edit Director or Edit-shard room
as a new immutable Department Dispatch v8 attempt under the same logical
lineage. Attempt and dispatch ids, input/result digests, and review state are
new for every correction; prior attempts are never overwritten. 04FX and the
optional 04VFX specialist loop remain bounded Edit Director work and return to
that Director. Only the Overall Director may promote the merged 04/05 package.

## Founder Timing Rule

Beat, cue, prompt-slot, and selected-audio section seconds are approximate
references only unless a founder-approved final edit explicitly locks that exact
cutpoint. Do not obey upstream seconds mechanically. For 04 edit work, first
analyze the selected audio and watch the actual generated video motion, then
stretch, compress, trim, reorder within intent, or hold shots as needed so body
hits, face/gaze landings, foot contacts, hand cues, camera moves, lyric entries,
section handoffs, and audible beat/onset markers feel synchronized on playback.
Any roughcut built mainly by fitting clips to inherited seconds must be marked
as a timing test, not edit truth.

If any graph-engineering artifact, cue sheet, generated upload pack, or older recipe seems
to instruct mechanical timing in 04, treat that instruction as invalid for
editing. Patch the run record or handoff note to preserve the useful intent while
removing the mechanical timing requirement before continuing.

Beat ids from 02A/02B/03V are not edit cutpoints. If a B## range appears to have
been created by equal-second slicing, prompt-slot count, PACK_INDEX row count, or
an old sample shape rather than a lyric cue, onset/accent cluster, pulse-density
change, body phrase, camera attention, story/object state, or edit handoff, do
not build the recipe from that split. Mark the section as a timing-risk hold,
record the suspected forced-fit basis, and re-anchor the edit marker plan from
the selected audio plus actual source motion before cutting.

For 04, the useful upstream object is the ordered Official Core/Branch Production Cut source and 03V
motion bridge, not the B## timestamp. First exact-project and read the complete
PRE-00-rooted full-storyline lineage and screen-progression map from one
declared passed 03V v8 manifest:
immutable original, active full text, every PRE-00/FP revision, contextual
density review, and reference-function receipts. Then read `source_production_cut_images`,
`subject_motion_route`, `camera_motion_route`,
`previous_next_continuity`, and `edit_handoff` from the passed 03V manifest.
Then verify them against the actual generated clip: the first useful source
frame, carried event phases, and final hold must agree with the passed
Production Cut anchors, and the cut must be justified by the body hit, camera stop,
lyric entry, object/space change, or intentional hold. If those do not match
playback, patch the marker plan or reject the source; do not force the clip into
the inherited audio window.

## 04 Unit Names

Keep upstream planning/generation units separate from editor-owned units:

- `Core Cut`: the 01-owned Official Core event, exact-carried unchanged through
  02A. It is never assumed to equal a final edit shot or boundary.
- `Production Cut`: one passed Official Core or Branch upstream framed screen
  realization and its 03V motion lineage. An Official Core-only cue has no
  fabricated Branch id.
- `Edit Slot`: one planned location in the v6 marker plan.
- `Edit Segment`: one selected source range on the v3 recipe timeline.
- `Edit Boundary` or `cutpoint`: the exact join between adjacent Edit Segments.
- `video frame`: one timebase sample used for frame-accurate editing and QC.
- `animation keyframe`: a parameter-animation term only when a real effect or
  motion control uses it; it is not a synonym for Branch Cut.

There is no one-to-one conversion rule. One Branch Cut may support multiple
Edit Segments, several Branch Cuts may combine into one Edit Segment, and a
passed Production Cut may be omitted when actual playback and selected-audio
logic justify the choice. The v6 marker plan exact-carries the full-storyline
and screen-progression projections plus 03V cue, Official Core, and Branch
lineage, or names the current-run non-Production-Cut source and the Branch Cut
whose continuity job it replaces.

Story flow is a 04 edit signal, not only an upstream planning note. When
front-planning readiness, 01 `screen_cause_effect`, 01/02A
`space_visible_feeling_progression`, 02A section transitions, or 03V
`source_production_cut_images` / `previous_next_continuity` / `edit_handoff` exists,
read the section story state, object/space consequence,
background/visible-feeling progression, viewer-attention change, and intended
transition before locking source order or cut density. A cut may be natural
because motion matches; it may also be natural because the story state, object
state, gaze route, camera direction, space change, screen-read feeling reset,
or deliberate contrast makes the next image feel directed. Record that as
`story_flow_continuity`, `space_visible_feeling_progression`, and
`directorial_transition_intent` in the 04 shard/edit map whenever section
shards are used. This still does not
let upstream artifacts set exact `source_in`, `source_out`, speed, candidate,
geometry, or final cutpoint.

## Required Reads

For delegated graph-engineering work, `automation/harness-skill-load-profiles.yaml` is
the sole static profile-body source. `edit_qc_section` loads the edit decision,
recipe, marker, casebook, and QC method set; `edit_master_closeout` loads only
the final render/delivery/package contracts after an assembled master candidate
exists. Run-owned audio, clips, maps, recipes, and receipts remain exact
hash-bound inputs.

1. `AGENTS.md`
2. `wiki/production-system.md` sections `Active Route`,
   `Stage And Session Ownership`, `01, 02A, And Post-02A`,
   `Dispatch, Context, Review, And Revision`, and
   `Founder Gates And Detail Sources`
3. Only at the `edit_social_release` checkpoint,
   `wiki/social-automation-system.md` sections `Run Artifact Layout`,
   `Git Artifact Policy`, and `Automation Boundary`
4. `wiki/generation-review-system.md` sections `Clip Budget Language` and
   `Core-Cut / Branch-Cut Imagegen Rules` when review boards or generated clips
   are being traced
5. `schemas/review.schema.json` when founder pass/hold/reject decisions are
   used
6. `schemas/edit-map.schema.json` when creating or updating `04-edit-map.yaml`
7. `schemas/edit-marker-plan.schema.json` when creating or validating a
   04-owned v6 edit marker plan before recipe lock
8. `schemas/edit-recipe.schema.json` and
   `scripts/validate_edit_recipe.py` for every new frame-canonical recipe and
   before final render. Legacy recipes remain compatibility inputs, not the
   preferred contract for new locks.
9. `references/professional-edit-decision-casebook.md` when choosing or
   disputing a cut, diagnosing Founder "awkward / not professional" feedback, deciding
   anticipation/exact-hit/afterbeat timing, or routing between 04, 04FX, and
   upstream regeneration
10. Do not preload worker skills to decide a route. Use the edit casebook and
    exact passed preview to dispatch `edit_shard.finishing_fx_section` for
    transition, beat-accent, tone, world/object, or local finishing work.
11. Dispatch `edit_shard.shot_vfx_section` only when the Edit Director has
    identified a hero object, true 3D camera/object job, tracked spatial insert,
    physical shadow/reflection/occlusion, particles, or Blender compositing.
    That worker reads the VFX manual/catalog; the Edit Director does not load
    the shot-worker skill into ordinary edit QC.
12. The active run's selected audio, passed Audio-Production-Cut Placement, passed 03V
   playback/review, video source, recipe, and edit-map files needed for the
   current edit task
13. `schemas/edit-render-manifest.schema.json`,
   `schemas/edit-cutpoint-sheet-manifest.schema.json`,
   `schemas/edit-delivery-qc.schema.json`,
   `scripts/idol_edit_delivery_qc.py`, and
   `schemas/edit-qc-closeout.schema.json` before a new master is claimed as
   final or a v3 closeout is authored
14. `references/editing-qc-detail.md` when building, revising, rendering,
   section-sharding, source-intaking, auto-assist-indexing, or QCing a real edit
15. `scripts/README.md` before choosing, adding, or rerouting automation scripts
   for source intake, sync workbench, edit contact sheets, video QC sheets,
   render helpers, or edit-readiness worklists
16. `schemas/department-dispatch.schema.json` and the exact current 04
    Department Dispatch v8 attempt, including its Edit Director/Edit-shard
    scope, CAS baseline, aggregate-manifest path, and pointer-only index/Boot
    Pack entries, before delegated edit/QC work

## Inputs

Read only the files needed for the active edit:

- `04-edit-map.yaml`: edit state index and current recipe pointer.
- active `idol_edit_marker_plan.v6`: complete PRE-00-rooted storyline and
  screen-progression projections plus Edit Slot/Boundary intent and Production
  Cut lineage.
- 00A/01/02A/02B/review-board context when present, read only as intent,
  source expectation, and candidate narrowing.
- Cue sheet or review-board table: R-slot timing, member, action, prompt summary.
- Selected audio and analysis: `audio/selected/*`, selected-audio analysis,
  and `research/audio-motion-director-map-*` provide song evidence. The passed
  legacy-named `03V-audio-branch-cut-placement.yaml`, 03V prompt manifest, and playback review
  provide Production Cut post-image timing and motion evidence. Also read local beat/onset
  evidence when exact marker work needs it.
- Raw video sources under `generations/video/raw/`. New or added active sources
  use only `generations/video/raw/additional/`. A populated historical
  `generations/video/raw/addiontal/` folder is evidence-only and holds active
  intake until selected bytes are migrated through a hash-bound plan.
- Generated or section-directed video sources under run-owned image/video output
  roots when the edit uses replacement source packs.
- Current recipe YAML in `generations/video/qc/sync-workbench-v1/`.

## Source Of Truth

- Recipe YAML is the Edit Segment, Edit Boundary, and exact-timing source of
  truth.
- `04-edit-map.yaml` is the state/index record.
- Rendered MP4 files are outputs, not editable truth.
- Founder-created variants such as `r3-1`, `r5-2`, `r9-2(additional)`, or
  `remake` are combinable edit material, not a one-winner-only candidate set.
  Files preserved in the retired misspelled folder remain historical evidence;
  when the Founder selects one for reuse, migrate its exact bytes into the
  canonical `additional/` lane before active intake.
- Final-master quality locks should render from original source clips whenever
  possible. Do not preserve a section by cutting from an older rendered master
  unless that rendered master is intentionally accepted as the source; expand
  preserved ranges back to the older recipe's raw segments for source-clean
  finals.
- Founder-accepted preserve ranges stay locked unless the founder changes the
  lock or QC finds a blocking defect. A quality pass may still expand those
  ranges back to original raw/source-clean recipe lineage without changing the
  visible timing.
- Upstream 00A/01/02A/02B and review-board artifacts are intent context. They
  can narrow candidates and explain why a moment exists, but they are not edit
  truth for exact `source_in`, `source_out`, speed, final candidate, geometry, or
  cutpoint.
- `PACK_INDEX.csv`, prompt-slot order, and selected-audio section windows are
  routing aids only. They must never force a clip to keep its generated duration
  or inherited output second when playback, source motion, or musical feel says
  the edit needs a different trim or hold.
- Match final delivery geometry to the founder-specified or founder-approved
  source/generation intent for the current run. Do not hard-code a default ratio
  in Graph Engineering. Create platform derivatives from the source-clean master or
  source-clean recipe only with an explicit crop, pad, or background policy.

## Output Boundary

Write or update only run-owned edit artifacts for the active content run:

The Edit Director is the only canonical writer. A physical Edit shard writes
only its declared run-owned working paths and returns a manifest to the Edit
Director; it must not update `04-edit-map.yaml`, the canonical marker plan, the
canonical recipe/timeline, `05-package.yaml`, or an output registry. The
Director performs the ordered merge against the last-passed CAS baseline and
returns the merged package to Overall for promotion.

- `04-edit-map.yaml` for edit state, selected candidate status, shard status,
  current/final recipe pointers, source indexes, QC pointers, and founder
  decisions.
- `generations/video/qc/edit-marker-plan-vN.yaml` or a shard-owned
  `generations/video/qc/sync-workbench-v*/edit-marker-plan-vN.yaml` for the
  04-owned marker plan that maps selected-audio/cue timing to candidate source
  action markers before recipe lock. The plan must validate against
  `schemas/edit-marker-plan.schema.json` when it exists and be referenced from
  `04-edit-map.yaml` through `edit_marker_plan_ref` or the active shard.
- Recipe YAML under `generations/video/qc/sync-workbench-v*/` for editable cut
  truth. New locks use `idol_edit_recipe.v3`, integer start-inclusive/
  end-exclusive program frames, rational FPS, explicit render geometry, source
  hashes, retime cadence, color pipeline, delivery policy, and 04-owned boundary
  handles. Each source also binds the run-owned probe bytes used for its color,
  geometry, rate, and duration interpretation. Seconds remain readable projections.
- Preview MP4s and contact sheets under `generations/video/qc/` for review
  evidence.
- Hash-bound final delivery measurement reports under `generations/video/qc/`;
  these measure but never normalize audio or infer a creative/Founder pass.
- 04 finishing FX maps, short FX previews, and FX contact sheets under
  `generations/video/qc/finishing-fx-v*/` only after the underlying section or
  contiguous chunk edit preview passes.
- Final source-clean master outputs under `generations/video/master/` only
  after the recipe is locked, included finishing FX have passed, and QC passes.
- `05-package.yaml` and `catalog/albums/ALBUM_KEY/TITLE_KEY/output-registry.yaml`
  only after founder-approved final edit promotion.

New 05 authoring uses `idol_package.v2`. Its `production_graph_trace` binds the
exact run-root `04-edit-map.yaml` and the canonical compiled
`idol_edit_recipe.v3` bytes, then maps every declared output to its ordered Edit
Segment ids and the exact projected screen-progression node and Section ids.
Changing either 04 source byte invalidates the trace; downstream release or
analytics evidence never patches those sources and grants no release authority.
Preserved v1 bytes are read only through
`schemas/package-v1-legacy.schema.json`; that schema is never selected by an
active producer or new run.

Do not write 02/02A/02B/03V prompt truth from this skill. Patch upstream intent
only when an edit finding proves the existing run record is stale or
mechanically misleading, and keep the patch in the owning run artifact.
Do not refresh legacy skill-application receipts; delegated work closes through
the current Department Dispatch return and director review.

## Workflow

1. Inspect the complete v6 full-storyline and screen-progression projections first, then the current
   recipe, selected audio markers, passed Audio-Production-Cut Placement, 03V
   playback, and only the needed upstream intent fields.
2. Index new sources with `scripts/idol-video-python scripts/idol_video_source_intake.py`
   when raw files changed. Reuse probe, motion, and contact-sheet evidence only
   when the source SHA-256 and that component's settings fingerprint still
   match; routine unchanged-source checks may reuse the shared stat-keyed
   SHA-256 cache, while `--force`, promotion, and external transfer require a
   fresh SHA-256. Use `--force` only for an intentional rebuild, not routine
   refresh.
3. Use upstream context to narrow the candidate search, including story/object/
   space flow and 03V planning carry when present, then prove the choice from
   actual source motion, audio alignment, story-flow continuity, and QC.
4. For new 04 edits, create the structured 04-owned edit marker plan before
   recipe lock. New work uses marker-plan v6: exact-project the full storyline
   and screen-progression map,
   then bind passed
   Audio-Production-Cut Placement, 03V manifests, and playback-review bytes; map
   every Edit Slot to its 03V cue/Official-Core/Branch Production-Cut lineage
   or a reasoned current-run non-Production-Cut source; lock rational FPS; keep unverified beat phase
   candidate-only; and record the incoming Edit Boundary method plus
   pre/cut/post-frame evidence. Older marker plans and CSV/prose marker notes
   are historical evidence, not active authoring inputs. The active order is
   selected-audio analysis -> audio rhythm evidence map -> passed pixel
   Audio-Production-Cut Placement -> passed 03V playback -> initial alignment with
   story-flow read -> edit marker plan -> recipe.
5. For every new recipe, use `idol_edit_recipe.v3` and run
   `scripts/idol-video-python scripts/validate_edit_recipe.py RECIPE --require-v3`.
   Keep output frames canonical, bind source bytes, declare actual FPS/geometry,
   record retime cadence/color/audio/delivery policy, and let 04—not 04FX—own
   any duration-preserving boundary source handles.
6. Follow the cache ladder for high-candidate edits: raw index -> proxy cache ->
   low-res full-flow preview -> targeted proxy previews -> locked recipe ->
   normalized final cache -> one full-quality final render -> final QC.
7. Generate or read contact sheets before choosing candidates. For changed
   program boundaries, build the frame-step surface at
   `-3,-2,-1,0,+1,+2,+3,+6` frames and use frame `0` as the incoming first
   frame. The sheet is evidence; Codex/Founder still pass the cut.

```bash
scripts/idol-video-python scripts/idol_edit_marker_contact_sheets.py \
  --run-root RUN_ROOT --plan MARKER_PLAN.yaml --mode cutpoint \
  --rendered-video PREVIEW_OR_MASTER.mp4 --out-dir CUTPOINT_QC_DIR
```
8. Select cuts by song function first, source action marker second, source
   duration third.
9. Trim, stretch, compress, hold, or shorten source clips freely inside the
   current song intent; avoid mechanical one-slot-one-duration assembly.
10. For uncertain changes, render a short preview window before rendering the full master.
11. After a section or contiguous chunk edit preview works, hand finishing to
    `idol-edit-finishing-fx` for the mandatory post-edit transition opportunity
    audit before final master. 04FX owns transition/accent realization; do not
    invent cut changes inside FX. Use FX when a transition bridge, beat accent,
    tone/source-family unification, world/object continuity, or readable source
    reinforcement would materially improve the passed edit—or when founder says
    the edit feels awkward, thin, hard, or missing transitions. Do not add
    effects to rescue weak timing or source choice; return those to this skill.
    Before final compile, section/chunk passes merge into one full-master 04FX
    audit whose coverage receipt accounts for every recipe boundary and typed
    marker/audio gate; the receipt adds no effect by itself.
    When the passed window instead needs new rendered geometry, a hero object,
    true 3D camera/material behavior, tracked spatial insertion, physical
    shadow/reflection/occlusion, or simulation, call the optional manual
    `idol-shot-vfx` specialist loop first. 04VFX may not edit this recipe or the
    edit map. After Founder PASS, ingest its exact passed clip as a normal
    run-owned additional source, rebuild the affected 04 window, and recheck
    frame count, timing, continuity, source quality, and playback. Only that
    04-accepted source may continue to 04FX; a VFX preview never splices itself
    into the master.
12. Render short FX previews and keep only passed effects for the final render.
    If an effect changes perceived timing, patch the edit recipe and re-preview.
13. Before the final 04FX dependency lock, predeclare the final recipe, compile
    manifest, render manifest, and closeout paths in `04-edit-map.yaml`. Then
    freeze the edit-map bytes through strict compile and final render: v2 04FX
    hashes the edit map, so a mid-chain status-only edit is still a stale input.
    Run the strict final-render gate after compile and before FFmpeg. Render the
    full recipe only after the local section preview, the 04FX transition
    opportunity audit, and any included finishing FX preview all pass.

```bash
ruby scripts/validate_edit_map_readiness.rb --mode final-render \
  RUN_ROOT/04-edit-map.yaml
```
14. QC with `ffprobe`, source existence and source-out overrun checks, full
   1-second contact sheet, cut/window contact sheet, source-family mismatch
   review, tone/quality consistency review, `blackdetect`, and final-silence
   comparison with the source audio.
15. Run delivery QC without automatic normalization: verify exact program
    frames/duration, rational FPS, geometry/SAR, pixel/color tags, selected-audio
    hash, sample rate/channel layout, LUFS/LRA/true peak/clipping, lead/trail
    silence, retime duplicate/judder candidates, and black frames. Body,
    identity, hands/feet, and cadence still require playback/contact-sheet review.
    The v2 delivery policy also locks the final container and supported local
    codec pair. `final` rendering may use H.264/AAC or a source-clean
    ProRes/PCM MOV mezzanine; output extension, pixel format, and codec policy
    must agree instead of being silently replaced by a proxy encode.

```bash
scripts/idol-video-python scripts/idol_edit_delivery_qc.py \
  --video generations/video/master/MASTER.mp4 \
  --recipe generations/video/qc/sync-workbench-vN/FINAL_RECIPE.yaml \
  --output generations/video/qc/final-delivery-qc-vN.yaml
```
16. After the Edit Director's merged package passes its review, return the
   hash-bound 04/05 package to Overall. Only Overall promotion followed by the
   required Founder approval may turn the candidate into final 05 truth and
   authorize updates to `05-package.yaml` and the title `output-registry.yaml`.
   The Edit Director may update its canonical 04 map with the reviewed merge
   and closeout pointers before that promotion, but it never promotes the
   package itself.
17. After the immutable compile and render receipts exist, update
   `04-edit-map.yaml` once with render/QC/closeout status. Write or update a v3
   04 closeout inventory with the exact final-master/recipe/receipt hashes,
   source keeper index, missing source count, cache cleanup manifest, cutpoint
   frame-step manifest, delivery measurements, required manual playback
   verdicts, and social derivative policy. Run the strict closeout gate before
   routing to 05; this gate follows the immutable compile/render receipt chain
   and therefore does not reopen the frozen pre-render edit-map digest.

```bash
ruby scripts/validate_edit_map_readiness.rb --mode closeout \
  RUN_ROOT/04-edit-map.yaml
```
18. Update `04-edit-map.yaml` and promote reusable edit decisions to the run
    memory; promote to `wiki/performance-memory.md` only when the lesson should
    survive future runs.

## Detailed 04 References

For real edit execution, read `references/editing-qc-detail.md`. It owns:

- section-sharded 04 work and merge checks
- upstream intent context and the audio-marker-first contract
- the initial analysis alignment pass
- automatic recognition assist boundaries
- source intake and generated-source handoff checks
- cut decision, contact-sheet, tone/source-family, speed/effect, cache, and
  closeout rules
- fast command templates
- memory promotion boundaries

Automatic recognition remains evidence-only. It may narrow candidate windows
and seed QC, but it must not choose final sources, identity, exact cutpoints,
geometry, speed, or founder pass/fail decisions.
