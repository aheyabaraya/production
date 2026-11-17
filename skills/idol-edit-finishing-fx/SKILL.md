---
name: idol-edit-finishing-fx
description: "Use for IDOL 04 edit finishing effects after a section or contiguous chunk edit preview has passed: transition bridges, beat accents, tone/grade fixes, world/object overlays, micro retime/pulse effects, local FFmpeg transition/accent catalog, professional edit-effect casebook examples (smash cut, dip to black, impact frame, whip sell, grade glue, chorus gate), After Effects-like motion graphics translation, post-edit transition opportunity audit, and QC before one final high-quality render. Use when the founder says the edit feels awkward/thin/unfinished, asks for transitions, effect examples, or wants AE-style effects without launching After Effects. Do not use for first-pass cut timing, source choice, video prompt authoring, true Blender/3D shot VFX, After Effects/MCP connection work, or hiding weak footage."
---

# IDOL Edit Finishing FX

Use this skill only after a 04 edit section preview or contiguous chunk preview
already works as an edit. The edit recipe owns Edit Segment source choice,
Edit Boundary timing, speed, geometry, and audio-marker alignment. Finishing FX
owns the additional visual treatment that makes a passed edit read more clearly
or feel more finished.

Do **not** change 04 cut flow from this skill. If timing, source, speed, or
geometry is wrong, return to `idol-editing-qc`.

Do not route through After Effects, AE MCP, Higgsfield, or any external tool
unless the founder explicitly asks for that separate integration. Prefer the
local FFmpeg catalog first. This skill can translate After Effects-like
concepts into local 04FX instructions, but the actual render must use the
repo's local render path.

## Execution Ownership And Return

04FX is a bounded specialist lane inside the fresh Founder-visible Edit
Director room. It starts only from an Edit Director- or Edit-shard-scoped
passed 04 section/chunk preview and an exact Department Dispatch v8 attempt;
it is never a standalone edit room and never extends the post-02A image-motion
lineage. The dispatch names the exact section/time range, source recipe, effect
outputs, Founder epoch, CAS baseline, and stop conditions.

The Edit Director remains the single writer of `04-edit-map.yaml`, the
canonical marker plan, recipe/timeline merge, and whole-video effect coverage.
An Edit shard may prepare a bounded effect preview or audit only inside its
declared scope and returns only to Edit Director; it cannot merge FX, update
canonical edit truth, or open a creative grandchild. Physical Edit shards use
the capacity and concurrency ceiling resolved in the immutable run provider
snapshot; this repository sets no project-local numeric quota. New launches
pause behind Director-review backpressure or a path collision. Multi-file FX
returns expose one aggregate manifest with exact
child paths and SHA-256 values.
The Director Dispatch Index and Director Boot Pack remain pointer-only and
expose lineage, scope, digests, manifest pointers, review/hold state, and next
actions without embedding media, raw pools, full transcripts, or creative
bytes.

Founder revisions continue in the same relevant Edit Director or shard room as
a new immutable Department Dispatch v8 attempt under the same logical lineage.
The new attempt binds fresh input/result digests and review state; no prior
attempt or passed preview is overwritten. FX dependency locks compare against
the last-passed canonical recipe/edit-map CAS baseline, so any source or
meaning drift returns to the smallest owner before compile. Edit Director
reviews and merges the final 04FX evidence, then returns the merged 04/05
package to Overall. Edit Director has no promotion authority.

## Required Reads

For delegated graph-engineering work, `automation/harness-skill-load-profiles.yaml` is
the sole static profile-body source. Use `finishing_fx_section` for ordinary
local finishing and `finishing_fx_ae_like_detail` only for a named AE-like
local compositing job. Exact passed Edit Director handoff bytes are run inputs;
do not preload neighboring owner skills.

1. `AGENTS.md`
2. `wiki/production-system.md` sections `Section-Gated Production Work`,
   `Production Boundaries`, `Cut Completeness`, and `Core Terms`
3. the exact passed Edit Director 04 handoff, target window, source handles,
   and CAS baseline
4. `schemas/edit-map.schema.json`
5. `schemas/edit-finishing-fx.schema.json`
   and `ruby scripts/validate_edit_finishing_fx.rb PATH` before an FX map can
   feed final render or 05
6. `schemas/edit-finishing-fx-compile-manifest.schema.json`,
   `schemas/edit-recipe.schema.json`, and
   `schemas/edit-render-manifest.schema.json` for strict final compilation and
   render-receipt handoff
7. `automation/edit-effect-registry.yaml` as the single executable effect
   type, alias, parameter, transition, timeline-safety, compiler, and renderer
   support contract. Catalog prose does not override this registry.
8. The active run's `04-edit-map.yaml`, current recipe YAML, section preview
   output, cut sheet or edit marker plan, selected audio or cue/BPM/onset map,
   and any QC contact sheets needed for the target section or chunk
9. Relevant upstream 01/02A/02B/03V fields only when the effect must preserve a
   specific world object, visual system anchor, Official Core/Branch Production
   Cut source state,
   Edit Boundary, motion route, or transition handoff
10. `references/local-ffmpeg-transition-effect-catalog.md` for local effect
   types, when-to-use, safe defaults, xfade list, and founder-awkwardness
   playbook. **Required** for any transition/accent work or post-edit final
   quality pass.
11. `references/professional-edit-effect-casebook.md` for rich professional
   examples, founder-phrase routing, pro-term cross-index, copyable effect
   sketches, and song-form placement. **Required** when choosing concrete
   finishing examples, answering “what effect here?”, or founder complains
   about hard/empty/no-impact/no-transition feel.
12. `references/ae-like-effect-map.md` when the founder asks for After
   Effects-style, motion-graphics, compositing, tracking, typography, glow,
   particle, matte, roto/key, 3D camera, expression-like, or advanced local FX
   behavior without actually using After Effects
13. When the result needs new rendered geometry, a hero object, true 3D
   camera/material behavior, tracked spatial insertion, physical
   shadow/reflection/occlusion, particles, or Blender compositing, return HOLD
   to the Edit Director for `edit_shard.shot_vfx_section`. Do not load or
   impersonate the shot-VFX worker from an ordinary finishing checkpoint.
14. `scripts/README.md` before adding or rerouting any reusable render,
    contact-sheet, or QC helper

## Output Boundary

Write only run-owned 04 finishing artifacts:

- `generations/video/qc/finishing-fx-vN/04FX-finishing-map-vN.yaml`
- short FX preview renders and contact sheets under
  `generations/video/qc/finishing-fx-vN/`
- compiled recipe effects helper output when used
  (`generations/video/qc/finishing-fx-vN/compiled-recipe-effects-vN.yaml`)
- a hash-bound compile manifest beside the compiled output; strict final mode
  must prove every passed FX id compiled with no skipped pass record
- an `effect_audit_summary` pointer/status update inside `04-edit-map.yaml`
- final render inclusion notes only after every included FX record passes

Do not write 02, 02A, 02B, or 03V prompt truth from this skill. If an effect
reveals that the cut timing, source choice, speed, or geometry is wrong, return
to `idol-editing-qc` and patch the edit recipe first.

Do not absorb true shot VFX into the 04FX registry. Route it to the optional
manual `idol-shot-vfx` skill. A passed 04VFX candidate must return to 04 source
intake and playback lock before 04FX can treat it as part of the passed edit.

## Eligibility Gate

A finishing effect may be proposed only when all of these are true:

- the underlying section or chunk edit preview is already marked pass or
  locally accepted for timing review
- the exact `source_edit_segment_refs`, output time range, Edit Boundary or
  in-segment trigger, and visible source action marker are known
- the effect performs at least one real job: transition bridge, music accent,
  world/object continuity, tone/source-family unification, readable source
  reinforcement, or compact lyric/message emphasis
- the effect can preserve member face, hands, feet, core body action, camera
  route, full space, world atmosphere, and track tone-and-manner

If the preview is still a rough duration fit, blocked shard, timing test, or
candidate comparison, do not add finishing FX yet.

## Post-Edit Transition Opportunity Pass (Mandatory Before Final Master)

After 04 edit preview passes and before one high-quality final master, run a
**transition opportunity audit**. This is 04FX work, not a cut re-edit.

Purpose: catch the common founder note that the edit is musically cut but
feels awkward, hard, thin, or missing transitions.

1. Read `references/local-ffmpeg-transition-effect-catalog.md`.
2. Walk every section boundary and every strong onset/drop/lyric gate in the
   passed window.
3. A measurement seed starts as `review_candidate`; after watching playback,
   resolve every point to exactly one final disposition:
   - `none_needed`
   - `safe_default_proposed`
   - `manual_fx_proposed`
   - `return_to_04`
4. Write the audit into the 04FX map as `transition_opportunity_audit`.
5. Materialize proposals as `fx_records` (safe defaults may be proposed without
   founder micro-approval; they still need preview pass before final include).
6. Preview → pass/hold/reject → compile only passed FX into the render effects
   list → final render.

Section/chunk passes remain the efficient working loop, but
`passed_for_final_render` is a **full-master** gate. Its v2 audit must carry the
exact coverage receipt recomputed from the hash-bound recipe, marker plan, and
structured audio/cue map. Every deterministic recipe boundary and typed
marker/audio gate appears exactly once in `coverage_event_ids` at its canonical
program frame; grouped points carry the matching `coverage_kinds`. Count or
digest mismatch, missing/duplicate event, wrong frame/section attribution, or a
non-full-master preview gate fails closed. This proves review coverage only; it
does not select an effect or infer a pass.

Safe defaults (proposal-level, still require preview pass):

- section boundary: `dip_flash` ~3–4 frames, opacity ~0.18–0.28
- clear body/camera hit on a real onset: optional `punch_zoom` ~2–3 frames,
  factor ~1.03–1.05
- musical stop with void grammar: optional short `fade_to_black` / `fade_to_white`

Do **not** auto-default dissolve, wipe, slide, pixelize, rgb split, or long
xfade chains.

The seed script does not choose even a safe default. It ranks frame/evidence
review surfaces only. Effect selection begins after 04 cut evidence and actual
playback are visible; a final map cannot retain `review_candidate`.

## Founder “어색/부족” Response

When founder says the edit feels awkward, insufficient, hard, empty, or
missing transitions:

1. Confirm 04 cut preview is still pass for source/timing. If not, leave 04FX.
2. Open the Founder Awkwardness playbook in
   `references/local-ffmpeg-transition-effect-catalog.md` and the matching
   cases in `references/professional-edit-effect-casebook.md` section H.
3. Prefer timeline-safe accents first (`dip_flash`, `brightness_pulse`,
   `punch_zoom`, `blur_pulse`, `micro_freeze`).
4. Use true `xfade` only when direction/world grammar justifies it and sync is
   re-checked.
5. Reject any effect whose only job is hiding a bad cut.

## Judgment Standard

Choose effects from the actual video, cut sheet, song cue, and MV world. Do not
start from a trend library. The local catalog is broad so capability is not the
bottleneck; every applied effect must still pass a concrete acceptance test.

For each candidate, record:

- `fx_id`, section id(s), output time range, and exact v3 recipe
  `source_edit_segment_refs`
- audio trigger: beat, onset, lyric entrance, section handoff, stop, release, or
  texture change
- visible basis: the body, object, camera, light, garment, space, or world
  behavior that the effect uses
- effect design: registry-backed effect type, canonical program start frame,
  duration in frames, direction, intensity, blend or opacity, endpoint, and
  renderer mapping. Seconds are a readability projection from recipe FPS.
- reason it helps: what becomes clearer, more continuous, or more musical
- protection guard: face/hand/foot/body, full space, world rule, tone, color,
  exposure, and mobile readability constraints
- fail conditions: exactly what would make the effect rejected
- preview output path, QC note, and status

Reject any effect whose strongest defense is only "cool", "premium",
"cinematic", "energy", or "more dynamic".

## Allowed Effect Jobs

Use any effect family that the current cut genuinely asks for, including:

- transition bridge: object, garment, hand, light, reflection, camera-direction,
  angle match, or a short local FFmpeg accent/xfade that carries the handoff
- beat accent: exposure pulse, dip flash, punch zoom, micro freeze, impact
  shake, blur pulse, rgb split, color/saturation/brightness hit
- tone/grade unification: exposure, contrast, saturation, grain, vignette,
  shadow, or short grade pulse that makes mixed sources feel like one MV
- world/object overlay: signal line, glass/reflection behavior, code trace,
  dust/light particle, screen flicker, or other current-run visual system rule
- readable source reinforcement: a small pulse or hold that makes a good body
  hit, gaze lock, foot plant, camera stop, or object state readable
- compact typography or symbol hit only when the word/object is an audible or
  visible cue, not decoration

Map concrete types through
`references/local-ffmpeg-transition-effect-catalog.md` first. When a request
names an After Effects feature family, also translate through
`references/ae-like-effect-map.md`. Record the local implementation family in
`effect_design`, such as `ffmpeg_filter`, `opencv_frame_pass`,
`moviepy_or_pil_overlay`, `asset_precomp`, `analysis_only`, or
`external_tool_required`. Do not promise a feature as local-renderable unless a
repo-local renderer or script can actually produce the preview.

The executable type/parameter truth is
`automation/edit-effect-registry.yaml`. Unknown types, unknown parameters,
unsupported passed effects, and compiler/renderer count mismatch fail closed.
Do not maintain another hand-written allowlist in the compiler or renderer.

Avoid one-effect drift by checking whether repeated effects still serve
different visible jobs.

## Local Render Path

1. Optionally seed a draft transition opportunity audit from recipe + marker +
   structured audio/cue evidence (never auto-pass). The seed groups exact
   full-program events by canonical frame and emits the coverage receipt that
   final semantic validation later recomputes:

```bash
scripts/idol-video-python scripts/idol_04fx_transition_opportunity_seed.py \
  --recipe generations/video/qc/sync-workbench-v1/RECIPE.yaml \
  --marker-plan generations/video/qc/edit-marker-plan-v6.yaml \
  --audio-summary generations/video/qc/sync-workbench-v1/audio-beat-onset-summary.json \
  --output generations/video/qc/finishing-fx-v1/transition-opportunity-seed-v1.yaml
```

2. Author/update `04FX-finishing-map-vN.yaml` (merge/review the seed first).
3. Compile passed (or draft-for-preview) FX into recipe-compatible effects:

```bash
scripts/idol-video-python scripts/idol_04fx_compile_recipe_effects.py \
  --fx-map generations/video/qc/finishing-fx-v1/04FX-finishing-map-v1.yaml \
  --recipe generations/video/qc/sync-workbench-v1/RECIPE.yaml \
  --output generations/video/qc/finishing-fx-v1/preview-recipe-with-fx-v1.yaml \
  --merge-into-recipe
```

For the final recipe, use strict mode. This preserves 04-owned base effects,
replaces prior `origin: 04fx` projections, and emits a compile manifest:

```bash
scripts/idol-video-python scripts/idol_04fx_compile_recipe_effects.py \
  --fx-map generations/video/qc/finishing-fx-v1/04FX-finishing-map-v1.yaml \
  --recipe generations/video/qc/sync-workbench-v1/RECIPE.yaml \
  --output generations/video/qc/finishing-fx-v1/final-recipe-with-passed-fx.yaml \
  --pass-only --merge-into-recipe
```

The final compile receipt is not trusted from its own hashes. Its validator
rebuilds the exact canonical merged recipe from the bound FX map, base recipe,
and effect registry, then requires the rebuilt document to equal the declared
compiled output. For `complete_no_fx_needed`, the base recipe `effects[]` lane
may retain registry `metadata_only` annotations such as `hard_cut_note` and an
explicitly passed, duration-preserving `origin: 04_edit` xfade already owned and
playback-reviewed by 04. Other renderable treatment must be audited and passed
through 04FX.

4. Preview with the FFmpeg renderer using the base recipe plus compiled effects
   overlay, or a temporary recipe copy that includes `effects[]`:

```bash
scripts/idol-video-python scripts/idol_video_ffmpeg_revise_render.py \
  --run-root RUN_ROOT \
  --recipe RECIPE_WITH_EFFECTS.yaml \
  --output generations/video/qc/finishing-fx-v1/preview-window.mp4 \
  --profile proxy \
  --preview-start START --preview-end END
```

5. For final master after all included FX are `pass`, render once at `final`
   profile from the merged recipe and supply its `--fx-compile-manifest`. The
   renderer re-hashes the FX map, base recipe, effect registry, merged recipe,
   effect ids, and counts before FFmpeg starts.

```bash
scripts/idol-video-python scripts/idol_video_ffmpeg_revise_render.py \
  --run-root RUN_ROOT \
  --recipe generations/video/qc/finishing-fx-v1/final-recipe-with-passed-fx.yaml \
  --fx-compile-manifest generations/video/qc/finishing-fx-v1/FINAL_COMPILE_MANIFEST.yaml \
  --output generations/video/master/MASTER.mp4 --profile final
```

Supported local effect types are owned by the catalog and implemented in
`scripts/idol_video_ffmpeg_revise_render.py`. If a catalog type is not yet
renderable, mark `renderer_status: needs_script_extension` and hold it.

## Rejection Rules

Reject or hold the effect when it:

- hides a weak cut, bad source choice, or wrong edit timing
- damages member identity, face readability, hand/foot/body mechanics, garment
  motion, or choreography endpoint
- breaks the full space, world atmosphere, visual system rule, color palette, or
  tone-and-manner of the track
- makes the cut feel late, early, cheaper, noisier, or less readable
- creates a source-family jump, flicker, black frame, compression artifact,
  flash-safety risk, or mobile clutter
- repeats the same visual trick so often that the MV turns into an effect demo
- changes song meaning, member ownership, MV world, wardrobe lane, or core
  action logic instead of finishing the existing edit
- uses boundary `xfade` that breaks selected-audio sync without an accepted
  handle/timeline plan

Boundary xfade may not author source handles in 04FX. Select only a
`transition_handle_ref` already locked in the v3 04 recipe. The compiler copies
that contract into the render projection. A missing handle, duplicate boundary
transition, insufficient source head/tail, or any final program-frame change
fails and returns to 04.

## Workflow

1. Confirm the active Edit Director (or its exact shard scope) and Department
   Dispatch v8 attempt, then start from the passed 04 section/chunk preview,
   current v3 Edit-Segment recipe, v6 Edit-Slot/Boundary marker plan, selected
   audio cues, QC sheets, and the last-passed CAS baseline.
2. Run the mandatory transition opportunity audit for the passed window.
3. Watch the actual cut flow and mark only moments where a finishing effect has
   a visible job. Use the awkwardness playbook when founder feedback is thin or
   hard.
4. Write or update `04FX-finishing-map-vN.yaml` against
   `schemas/edit-finishing-fx.schema.json`. New maps use v2 and bind the exact
   source-recipe SHA-256 plus the passed-preview SHA-256 in `dependency_lock`.
   Before taking that dependency digest, make the edit map predeclare its final
   recipe, compile manifest, render manifest, and closeout paths. Freeze the
   edit-map bytes until strict compile and final render finish; even a status-only
   mutation correctly invalidates the v2 FX dependency lock.
5. Compile effects and render a short low-resolution FX preview around each
   changed window or contiguous chunk.
6. QC the preview for timing feel, identity/body preservation, full-space and
   world preservation, tone-and-manner, mobile readability, flicker/flash risk,
   source quality, repeated-effect drift, and xfade audio-sync if used.
7. Mark each effect `pass`, `hold`, or `reject`. Rejected effects remain in the
   map with a reason when they explain a decision.
8. Include only passed FX in the final high-quality render. If the effect
   changes perceived timing, patch the 04 edit recipe and re-preview before
   final render.
9. Run `ruby scripts/validate_edit_finishing_fx.rb PATH`. A v2 final map needs
   a completed audit: `complete_no_fx_needed` with no FX records, or
   `complete_fx_passed` with every selected proposal linked to a passed record.
   It also needs `preview_gate.gate_type: full_master` and exact full-program
   coverage of the bound recipe/marker/audio event set.
   A `complete_no_fx_needed` strict compile also rejects renderable effects
   hidden in the 04 base recipe; only registry metadata-only annotations and an
   explicit passed duration-preserving `origin: 04_edit` xfade may survive that
   route.
   Any recipe or preview digest change makes the map stale: return to 04FX, or
   first to 04 when timing, source, speed, or geometry changed. V1 is historical
   evidence only and cannot pass active validation, compile, final render, or 05.
10. Strict-compile with `--pass-only --merge-into-recipe`. A passed FX that is
    unsupported, invalid, or omitted is a hard failure. Validate the emitted
    compile manifest and run
    `ruby scripts/validate_edit_map_readiness.rb --mode final-render 04_EDIT_MAP`
    before final render.
11. Update `04-edit-map.yaml` `effect_audit_summary` with the finishing map
    path, audit status, allowed/rejected families, and final-include note.

## Final Render Rule

High-quality render should happen once from:

```text
locked/passed 04 edit recipe
+ passed 04FX finishing map
+ compiled passed effects
+ final source-clean inputs
```

After the master is locked, do not add new creative effects by default during
defect-only final QC. The mandatory transition opportunity pass happens
**before** that lock, as part of finishing—not as a silent post-lock surprise.
