# Grok CLI Local 03V Runbook

purpose: author or refine one passed Official Core/Branch image-locked video
  prompt at a time from the common hash-bound 03V source snapshot
status: active for the exact Grok 03V section owner selected by the current
  run and Department Dispatch, or when the
  Founder explicitly requests a cross-surface Grok app/TUI/CLI handoff
canonical_output: `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video-prompts/`

This runbook is the single Grok execution source for canonical 03V prompt work.
It does not create a Drive copy, approve generation, or activate the separate
live-testing exception.

## Required Start

From the IDOL repository root, follow this order exactly:

1. Read `AGENTS.md`.
2. Read `wiki/production-system.md`.
3. Read `wiki/INDEX.md`.
4. Read the task-activated policy modules named by `AGENTS.md`.
5. For a cross-surface handoff, read `handoff/grok/current.md` and the named
   handoff packet. For the run/Dispatch-selected Grok 03V section owner, resolve the exact run,
   section and checkpoint from that assignment and canonical local state; do not require a handoff packet.
6. Read `skills/idol-video-prompt/SKILL.md` from start to finish and only the
   operation-required linked references.
7. For a handoff, read the Founder-requested Grok reference pack and compact
   brief. For that exact Grok 03V section owner, read its canonical section sources
   required by `idol-video-prompt`.
8. Read this runbook.

For a handoff, stop if `handoff/grok/current.md` does not select the exact run
or request packet. Do not infer work from an archive, Drive mirror, or old
title. This stop does not apply to the run/Dispatch-selected Grok 03V section owner.

## Common Source Snapshot Rule

For a cross-surface handoff,
`scripts/idol_prepare_grok_video_prompt_handoff.rb` first runs the common
`scripts/idol_prepare_video_prompt_authoring.rb` preparation. Its Grok
reference pack therefore carries the same:

- complete PRE-00-rooted full-storyline lineage, including immutable original,
  active full text, revisions, density review, and reference functions/exclusions;
- `03v-source-snapshot` path and SHA-256;
- source-set SHA-256;
- typed Production Cut Review, Audio Production-Cut Placement, and detailed
  timeline gate;
- Founder-passed image byte hashes;
- 02A/02B lineage used by the shared route.

For that handoff, verify the reference pack against
`schemas/grok-video-prompt-reference-pack.schema.json`. If the snapshot or
source-set digest changed, regenerate the handoff before authoring. The
run/Dispatch-selected Grok 03V section owner uses its common preparation and
canonical section source snapshot directly; it validates the shared 03V sources and does not regenerate
or require a handoff package.

## One Compact Cue At A Time

For each active 03V v8 cue:

1. Follow `active storyline passage -> selected Sequence Composition and
   one-second flow reading -> selected Core reference -> passed Official
   Core/Branch Production Cut -> compact motion prompt`.
2. Open every ordered `source_production_cut_images[]` original and verify its
   SHA-256. Pixels are the
   complete appearance, styling, lighting, material, world, camera-anchor, and
   visible-start authority.
3. Read only that compact cue row: Section/Major/Core/Branch lineage, audio/no-lyric
   cue, audio cue/tension (`audio_pressure` compatibility field), frame-subject
   mode, choreography-presence policy,
   screen-motion route, camera route, endpoint, and adjacent continuity.
4. Read the common authoring source pack only when the cue row names a missing
   projection or the actual pixels contradict it.
5. Open full 02A, 02B, Front Planning, or research sources only for a named
   unresolved contradiction. Do not reopen them for every cue.
6. Inspect the previous/next compact row when continuity requires it; do not
   carry the entire song into a single prompt-writing turn.

Batch preparation is allowed within the assigned section; each worker/session
keeps that exact section and never merges canonical whole-video bytes. Write disjoint prompt records, then merge
and close QA by section. The central 03V manifest preserves whole-film order; the
Grok reference pack preserves the common source-set digest.

## Prompt Compile Rule

The 03V manifest retains internal truth. `prompt.txt` contains only observable control:

```text
one short visual-source lock
+ first visible trigger
+ member/object/environment/system movement or intentional hold
+ camera height, distance/scale, direction/angle, depth and motivated route
+ subject placement, crop and negative-space handling
+ pacing, endpoint and edit handoff
```

Use roughly 70-85% of generator-facing words for movement/hold, camera,
screen capture, timing, and endpoint. Do not inventory face, hair, makeup,
jewelry, wardrobe, lighting, color, or environment already visible in the
image. Add one minimal attribute only after a recorded drift failure names it.

Packet ids, cut ids, section ids, source ids, skill names, JSON pointers,
Founder status, and review notes stay in the canonical 03V manifest. They never
appear in generator-facing `prompt.txt`.

## Choreography Presence

- `primary` or `supporting`: use a dance/choreography term only when it improves
  model control, and immediately translate it into exact foot, weight, level,
  torso, hand, gaze, garment, camera, and endpoint mechanics.
- `minimal_body_gaze_hold_guard`: preserve only the bound body/gaze/hold route.
  Do not add a dance phrase.
- `absent`: omit every dance, choreography, formation-dance, dance-pose, or
  related dance-activation token from generator-facing text. Do not write “no
  dance” or another negative dance sentence. Acting, gaze, body holds, object
  behavior, environment, system, and camera motion remain available when the
  upstream plan calls for them.

When the actual frame is non-member-led, do not force a body route merely
because this is an idol MV.

## Output

Write or update:

```text
RUN/generations/video-prompts/<canonical prompt record>
RUN/03V-video-prompt-manifest-vN.yaml
RUN/review/03v-section-video-prompt-qa-vN.yaml
```

When a manual upload package is requested, prepare one flat timeline-order
`upload-ready/` queue. Each folder contains `prompt.txt` and exactly the indexed
source images. Typed upload packs remain validation mirrors.

Use `schema_version: idol_video_prompt_manifest.v8`. Each Motion Storyboard
binds one to three ordered passed `official_core|branch` originals under one
active storyline passage and selected Sequence flow. Same-parent Core is the
default. A cross-Core board must name both Core IDs and its continuity reason.
The composite board is authoring/review evidence; the ordered originals remain
pixel truth.

Default execution is `image_to_video` with exactly one passed Production Cut
still as frame 1. `reference_to_video` opens only when the Founder selected the
exact multi-reference image IDs and order. Pass the approved `prompt_text`
bytes unchanged (`prompt_rewrite_policy: forbidden`). Only 6 or 10 seconds and
480p or 720p are valid. Run 480p test first; only a CDD-passed playback of the
same `video_job_id` can open its 720p candidate. A requested/observed resolution
mismatch is `resolution_fallback_hold`. No automatic provider, auth, tool, or
resolution fallback is allowed.

Validate the finished manifest and section QA before any external execution or
Drive mirror. File presence is not a playback or Founder pass.

## Exact Local Execution Package And Return

After the active manifest and section have passed, use the exact current
manifest path bound by that run (not a highest-numbered filename), project one
cue and, when a local operator folder is required, materialize it without
contacting Grok. `RUN` below denotes that owning album/title/run root:

```text
ruby scripts/idol_media_execution_adapter.rb video \
  CURRENT_BOUND_03V_MANIFEST_PATH --cue-id CUE_ID --dry-run \
  --write-package \
  --package-root RUN/generations/video-prompts/execution-ready
```

The resulting folder is authoritative only for transport bytes. Confirm that
`package-plan.json` reports `external_execution_ready: true` before any
separately approved provider action. `image_to_video` contains exactly one
passed Production Cut; `reference_to_video` contains only the exact
Founder-selected ordered two-to-three cuts. Do not upload the Motion Storyboard
board as an extra execution image. The provider profile/source SHA, prompt SHA,
ordered input-set SHA, individual copied-file hashes, duration, resolution, and
no-fallback rule must remain exact.

Download the returned clip into a separate local source directory using the
expected `CUE_ID.mp4` stem. Then route it through the existing importer rather
than copying it directly into review state:

```text
ruby scripts/idol_03v_import_generated_clips.rb RUN \
  --source-dir LOCAL_RETURN_DIRECTORY --mode copy \
  --refresh-worklists --write
```

The importer matches the cue stem, copies and hashes the clip into the run-owned
03V clips root, refreshes generated-playback intake/worklists when requested,
and leaves playback status pending. CDD must inspect the actual playback and
record a separate decision before 04; a package, download, hash, or playable
probe is never creative PASS.

## Stop Conditions

Stop instead of guessing when:

- the reference pack or source snapshot does not validate;
- source-set or image SHA-256 changed;
- the actual image is unreadable;
- the review record is not Founder-passed;
- any source is not a passed `official_core|branch` Production Cut;
- a cross-Core board lacks both Core IDs or its continuity reason;
- `reference_to_video` lacks the Founder exact image-order selection;
- a 720p candidate lacks the same-job passed CDD 480p playback review;
- requested and observed resolution differ;
- the typed Production Cut Review is not passed, or Audio Production-Cut
  Placement is missing or not ready;
- the cue row lacks an observable screen-motion/hold route, camera route, or
  endpoint;
- pixels contradict the compact planning projection;
- a dance-heavy cue lacks the upstream mechanics needed to author it;
- a Drive mirror disagrees with the run-owned source.

Do not modify 02A, 02B, 03V locks, review images, selected audio, or external
state from this runbook.
