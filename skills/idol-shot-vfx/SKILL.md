---
name: idol-shot-vfx
description: "Use for optional IDOL 04VFX shot work after a 04 edit window already passes for source and timing: Blender hero objects, true 3D camera/object animation, world or space intervention, tracked inserts, shadows/reflections/occlusion, particles, and compositing that cannot be completed as 04FX finishing. Use when the Founder names an effect, reference, object, or situation and wants a local preview/contact-sheet loop. This is a manual specialist surface, not an active graph-engineering stage or schema-driven automation."
---

# IDOL Shot VFX

Use this skill to make one optional VFX candidate inside an already accepted 04
edit window. It does not own the cut. A passed result returns to
Edit Director first, which may route it to `idol-editing-qc` as a new
run-owned source; 04 then rechecks timing and locks the recipe before 04FX or
05.

## Execution Ownership And Return

04VFX is an optional manual specialist dispatched from the fresh,
Founder-visible Edit Director room after the exact 04 window passes. It is a
separate, bounded edit-window task, never a new stage, standalone edit room, or
continuation of the post-02A image-motion lineage. The Department Dispatch v8
attempt names one exact section/time range, output path(s), source and recipe
hashes, Founder epoch, last-passed CAS baseline, and stop conditions.

Edit Director is the return recipient and sole authority to decide whether a
passed VFX clip enters 04 source intake. A shard may supply the bounded window
and evidence in its own return, but it cannot open a creative grandchild,
rewrite the canonical map/recipe, or send VFX directly to Overall. Multi-file
VFX work returns one aggregate manifest with exact child paths and SHA-256
values. The Director Dispatch Index and Director Boot Pack remain pointer-only
and expose only lineage, scope, digests, manifests, review state, holds, and
next actions.

Founder revisions stay in the same relevant Edit Director or shard room as a
new immutable Department Dispatch v8 attempt under the same logical lineage;
the prior shot note, preview, and result are never overwritten. Edit Director
merges any accepted source into the 04 package and returns the reviewed 04/05
package to Overall, which alone may promote it. 04VFX itself has no promotion,
edit-map, recipe, or master-inclusion authority.

Do not register 04VFX in the stage registry, add a schema, create an empty no-VFX
artifact, or auto-dispatch it. Codex and Founder-selected Grok use this same
skill and the same run paths.

## Output Boundary

Allowed outputs are only the dispatch-scoped VFX source project, rendered shot
candidate, preview/contact sheet, QC evidence, and one aggregate return manifest
with exact child paths and SHA-256 values. Canonical `04-edit-map.yaml`, marker
plan, edit recipe, 04FX map, master, package, and release status are forbidden
outputs; only the Edit Director may ingest an accepted candidate and re-lock the
affected edit window.

## Required Reads

For delegated graph-engineering work, select only `edit_shard.shot_vfx_section` from
`automation/harness-skill-load-profiles.yaml`. The exact Edit Director route,
passed 04/04FX bytes, source handles, and CAS baseline are hash-bound inputs;
do not load the Edit Director or finishing worker skills as authority.

1. `AGENTS.md`
2. `wiki/production-system.md`
3. `policies/section-production.md`
4. `references/04vfx-manual-use-and-runtime.md` before planning or executing a
   shot
5. `references/shot-vfx-catalog.md` when choosing or explaining an effect
   family
6. `scripts/README.md` section `Python Runtime Isolation` before using Python,
   OpenCV, MoviePy, Pillow, ffmpeg, or ffprobe
7. The exact current 04 recipe, passed preview, Edit Segment, source handles,
   audio cue, and reference material for the target window

Read `skills/idol-edit-finishing-fx/references/ae-like-effect-map.md` only when
the requested behavior may still be a 2D/local finishing treatment rather than
true shot VFX.

## Ownership And Routing

Keep these decisions separate:

- Return to 04 when source choice, trim, speed, geometry, cutpoint, program
  frames, or audio alignment must change.
- Use 04FX when existing pixels only need a flash, zoom, grade, xfade, blur,
  glow-like blend, typography hit, simple overlay, or other registered local
  finishing treatment.
- Use 04VFX when the shot needs new geometry, a rendered object, 3D camera or
  material behavior, tracked spatial insertion, real depth/occlusion,
  reflection/shadow interaction, environment intervention, or simulation.
- For a hybrid, create the rendered shot element in 04VFX, return the passed
  clip to 04, then apply final 2D accents in 04FX.

04VFX may not edit `04-edit-map.yaml`, the marker plan, or the recipe. It may
not claim that a preview is in the master. Only 04 can ingest the passed result
and re-lock playback.

## Eligibility Gate

Start only when all of these are known:

- one passed 04 preview window and its exact output frame range;
- the owning Edit Segment and source SHA-256;
- required source head/tail handles;
- the visible action or intentional hold that must survive;
- the audio, object, story, or world reason for the VFX;
- the Founder reference/effect/situation, if supplied;
- the face, body, wardrobe, product/object, world, mobile-readability, and
  flash-safety protections;
- the fallback source to keep when the VFX is rejected.

If the edit is still a rough duration fit or candidate comparison, remain in
04. Do not use VFX to conceal weak footage.

## Manual Workflow

1. Freeze the target 04 preview and record its recipe, source, frame range,
   duration, FPS, geometry, and hashes in the plain-language shot note from
   `references/04vfx-manual-use-and-runtime.md`.
2. Inspect the exact reference pixels or sequence. Translate the requested
   effect into observable object state, camera relation, light/material,
   environment response, and endpoint.
3. Decide 04FX versus 04VFX with the routing rule above. Prefer 04FX when it can
   deliver the same screen result without building a new spatial object or
   interaction.
4. Run the media-runtime preflight. Blender is optional and separate from the
   Python environment; missing Blender is a hold for Blender-dependent work,
   not permission to install or invoke another external service.
5. Build one low-cost proof: still frame or 0.5/1-second contact sheet first,
   then a short proxy window. M1 8GB defaults to simple geometry, bounded
   textures, EEVEE/Workbench-class preview, low samples, and one shot at a time.
6. Compare the reference strip and our shot side by side. Judge the transferred
   directing grammar, not literal object identity. Check framing, scale,
   approach, material reveal, spatial consequence, timing, and endpoint.
7. Record `PASS`, `HOLD`, or `REJECT` in the shot note with the concrete reason.
   A script or render completion never supplies this judgment.
8. On PASS, preserve the project/source hashes and export one source-clean clip
   with the same FPS, geometry, duration, and program-frame count as the locked
   window.
9. Return the clip and its aggregate manifest to Edit Director. Only Edit
   Director may route it into `idol-editing-qc` for normal source intake;
   04 ingests it through the normal source path, re-renders the window, and
   verifies timing before it can reach 04FX or the master.

Rejected experiments remain review evidence only. They do not enter the 04
source index or final recipe.

## Run-Owned Working Area

Keep one shot together under:

```text
RUN/generations/video/qc/shot-vfx-vN/SHOT_ID/
  04vfx-shot-note.md
  reference/
  project/
  previews/
  contact-sheets/
  passed/
```

The folder is a review workspace, not a canonical stage. Do not create a
cross-run asset library from a run-specific Blender scene or effect setup.

## Runtime Rule

- Use `scripts/idol-video-python` for ffmpeg/ffprobe, OpenCV, MoviePy, Pillow,
  contact sheets, and video inspection. Never repair a missing media package by
  installing into bare system `python3`.
- Keep Blender as a separately versioned application. Do not install the IDOL
  media requirements into Blender's embedded Python or treat Blender Python as
  the media-runtime source of truth.
- Do not install Blender, Python packages, plugins, assets, or external render
  services without the current-task Founder approval that the action requires.
- Cache reuse requires unchanged source bytes, shot note, project/script bytes,
  render preset, Blender version, and output settings.

The current package and Blender management baseline, known exceptions, and
preflight commands are in `references/04vfx-manual-use-and-runtime.md`.

## Camera Explanation Rig

The locally installed `Add Camera Rigs` extension is the approved Blender aid
for explaining an already-authored camera decision. It does not author or
select camera truth.

- Use the 2D rig to demonstrate framing boundaries, lens-versus-shift behavior,
  crop, placement, and negative space.
- Use the Dolly rig to demonstrate camera height, distance, direction, aim,
  lens choice, and a straight spatial approach or retreat.
- Use the Crane rig only when the authored route includes a real elevation,
  boom-length, or arcing camera relation.
- Turn on Blender's composition guides when they clarify thirds, center,
  diagonal, golden-ratio, or safe-area placement.
- Preserve the owning 01/02A still-camera values or the owning 03V temporal
  camera route exactly. A rig preview may illustrate those values but may not
  replace them, make a thin direction look complete, or become a new stage
  contract.
- Keep any screenshot, `.blend`, or proxy created for a real shot inside that
  shot's run-owned `project/`, `previews/`, or `contact-sheets/` folder. Never
  turn a run-specific rig scene into a cross-run creative default.

The exact installed version, source commit, package hash, local module id, and
smoke-test command are locked in
`references/04vfx-manual-use-and-runtime.md`.

## Review Standard

Pass only when the VFX:

- performs the named story, object, world, or music job;
- preserves the locked cut and exact frame count;
- reads at mobile size without turning the shot into a software demo;
- preserves member identity, face, hands, feet, body route, wardrobe, object
  truth, and surrounding world;
- maintains credible light, shadow, reflection, occlusion, scale, material, and
  camera relation for the requested effect;
- has no black frames, alpha fringe, texture pop, temporal flicker, broken
  track, simulation jump, or source-quality collapse;
- remains feasible on the local machine or is explicitly held for a heavier
  approved route.

Reject any result whose strongest defense is only “cool”, “cinematic”,
“premium”, “more dynamic”, or similarity to the reference object.

## Founder Gates

Founder approval remains separate for:

- installing or materially updating Blender;
- installing plugins or additional Python packages;
- paid generation, external render, cloud assets, or third-party services;
- creative PASS of the shot;
- 04 reinsertion and final master inclusion;
- public release.

An intended future installation is not an executed install receipt, and a
passed VFX preview is not a master inclusion decision.
