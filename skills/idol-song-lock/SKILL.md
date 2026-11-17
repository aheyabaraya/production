---
name: idol-song-lock
description: "Use after an actual audio take exists and before Front Planning. One music-director owner analyzes the selected take, maps audio timing evidence, and authors the compact 00A song production lock without pre-authoring MV screen truth."
---

# IDOL Song Lock

Use this skill after an actual audio take exists. One music-director owner in
the separate physical Founder-visible Song Room under the durable Creative
Development Director (CDD) carries the take through three ordered artifacts:

```text
research/selected-audio-analysis-vN.md
research/selected-audio-analysis-vN.json
research/audio-motion-director-map-vN.yaml
00A-song-lock.yaml
```

The files are separate evidence surfaces, not separate creative roles or
Founder forms. The Founder selects the take and gives PASS, HOLD, or REJECT at
00A. Front Planning starts only after a selected take and valid 00A exist.

Reference-song fit is PRE-00 evidence for making or choosing a song. It is not
selected-audio analysis.

The selected PRE-00 v3 handoff is the Song Room's whole-film context. Read its
complete `storyline_lineage` before audio work: immutable
`pre00_storyline_original`, active full-text version, append-only revisions,
contextual density review, and every reference function/exclusion. Song work
may test or challenge how the selected audio supports that flow, but it never
overwrites the PRE-00 original, compresses it into a summary, or invents a
screen-level replacement. A needed change returns to the owning storyline
lineage as a new parent-linked full-text version.

The Song Room is an unconditional separate physical child task for lyric, arrangement,
candidate, selected-audio, audio-motion, and 00A work. A HOLD or later 00A
correction resumes that same task and returns only to CDD; Overall never
duplicates the Song Room conversation. CDD reviews the package and sends a
milestone upward, but only the Overall Director promotes canonical truth.

## Required Reads

Read this file completely. For the physical Song Room,
`automation/harness-skill-load-profiles.yaml` is the sole static profile-body
source and the same lineage advances through three exact checkpoints:

- `selected_audio_analysis` reads the selected-audio schema and analysis method;
- `audio_screen_motion_map` reads the accepted analysis plus audio-motion schema;
- `song_production_lock` reads both accepted upstream artifacts and the song-lock
  schema.

Each checkpoint also reads its registered AGENTS, constitution,
production/routing/song-system, Department Dispatch, and method sources. The
selected PRE-00 v3 handoff, exact audio, original lyric/transcript or
instrumental-status source, and latest owned artifacts are hash-bound
current-run inputs rather than a global read list. Validate the handoff against
`schemas/pre-00-selection-handoff.schema.json` before relying on it.

Read `scripts/README.md` when creating or citing beat, onset, pitch-contour
proxy, motif, or manual cue sidecars. The active MV route uses post-image
Audio Production-Cut Placement rather than the retired cue-BPM authoring route.

Every launch and return follows `idol-department-dispatch.v8` with Goal creation before reads or work. Stable
`lineage_id`/physical `session_id` are distinct from immutable
`attempt_id`/`attempt_number`; a correction is a new attempt under the same
Song Room lineage with prior output retained and affected dependents explicitly
invalidated. The runtime records EOF-read/application evidence, skill revisions,
owner, input/result digests, and output inventory. This skill returns only to
CDD. A multi-file return exposes one aggregate manifest with exact child paths
and SHA-256 values; Director Dispatch and Reference Working Index surfaces are
pointer-only projections, never duplicate artifact stores.

## Professional Role

Act as a music director and selected-track analyst:

- listen to the actual take rather than inferring from a generation prompt;
- judge song craft, hook behavior, arrangement, vocal/rap color, lyric truth,
  form, section contrast, and editability;
- preserve exact source identity and Founder selection state;
- turn audio timing into evidence and questions for the MV director;
- refuse to choose screen answers that belong to Front Planning, 01, 02A,
  02B, 03V, or 04.

Do not become the MV scene director inside this skill.

## Active Route

### 1. Selected-Audio Analysis

Author `idol_selected_audio_analysis.v1` from the actual take. It owns:

- source audio identity and hash;
- original lyric/transcript identity, completeness, and uncertainty;
- sonic texture, hook mechanics, groove, emotional temperature, vocal/rap
  color, production dynamics, and reference-fit delta;
- comparative or single-take craft evaluation;
- selected audio range and duration;
- whole-song meaning read and literal-misread risks;
- canonical section ids, timing, section family, lyric/music function, audible
  triggers, and editability evidence;
- audio-motion and Front Planning questions.

It does not own target, MV message, member allocation, current-title visual
identity, reference assignment, scenes, action, choreography, styling,
still-camera geometry, temporal camera motion, Core-Cut/Branch-Cut count, or prompt prose.

### 2. Audio Motion Evidence Map

The retained filename is `audio-motion-director-map-vN.yaml`, but active
`idol_audio_motion_director_map.v1` is an audio evidence map. It owns:

- stable duration, tempo grid, perceived pulse, meter, and uncertainty;
- source-hashed precision markers when available;
- section pulse, density, accents, stops, resets, vocal/lyric triggers, motif
  returns, and audible state-change pressure;
- exact trigger times and evidence;
- questions that later screen planning must answer.

It must preserve selected-audio section ids, order, and timing exactly. It must
not contain body blocking, scene action, choreography, camera rhythm, prompt
overlay, styling, spatial design, Core-Cut/Branch-Cut count, or final edit timing.

### 3. 00A Song Production Lock

Author active schema `1.5`. 00A is a compact, Founder-reviewable lock for:

- selected audio, lyrics, and source hashes;
- tempo, pulse, meter, duration, energy curve, and selected-take craft
  consequences;
- hook function; opening-arc behavior that establishes sonic identity through
  the actual intro boundary, ordinarily around 8-12 seconds when supported by
  the take; and the recognizable carrier shared by the first full hook and its
  middle/later returns;
- song-derived thesis, emotional progression, tonal boundary, and literal
  misread guards;
- canonical section timing, song/lyric function, energy/density, audible
  triggers, and meaning guard;
- audio cue/tension, editability evidence, and open Front Planning questions.

00A does not choose any visible action or screen grammar. Front Planning owns
target, message, member and current-title visual assignment, reference
connection and section allocation, whole-video progression, and major section
scene flow. 01 and 02A expand observable still-frame truth. 02B translates
passed 02A into five required prompt items, serialized as five fixed labeled
lines. 03V authors
temporal camera motion only after passed images exist. 04 locks exact edit
timing.

## Source Lineage

```text
actual audio + original lyrics or instrumental status
-> selected-audio analysis
-> audio timing evidence map
-> 00A song production lock
-> Front Planning creative spine
```

Every transition preserves source path and SHA-256. A new take invalidates the
selected-audio analysis and its affected audio-map and 00A dependents. A
corrected timing or lyric interpretation reprojects only affected audio-map and
00A fields. It does not reopen unrelated Front Planning sections after a local
Founder correction.

## Output Boundary

Write only the active run's selected-audio analysis Markdown/JSON pair,
audio-motion evidence map, and `00A-song-lock.yaml`, plus the exact run-owned
review or dispatch return named by the current task. Do not write target,
message, member, visual, reference, scene, 01, 02A, 02B, 03V, or 04 truth. Do
not alter the selected audio bytes or promote a take without explicit Founder
selection. Return all artifacts only to CDD, with one aggregate manifest for
the three-file package and a retained immutable attempt for every correction.

## Authoring Rules

- Use original lyric text only when the words themselves are the audible turn.
  Do not invent or normalize uncertain lyrics.
- Separate measured signals from listening judgment. Scripts may provide
  markers; the music director authors their meaning.
- Treat pitch contour as a proxy unless a valid isolated-vocal source exists.
- A repeated motif may justify a downstream question; it does not automatically
  become repeated movement, camera, object, or edit grammar.
- Preserve silence, breath, pickups, stops, resets, bass landings, percussion,
  transient grids, vocal entries/holds, texture shifts, and motif returns when
  they materially divide the song.
- Do not manufacture screen requirements merely to populate a schema.
- Do not copy a previous run's section pattern.

## Validation

Run:

```text
ruby scripts/validate_selected_audio_analysis.rb PATH
ruby scripts/validate_audio_motion_director_map.rb PATH
scripts/idol-video-python scripts/validate_json_schema.py schemas/song-lock.schema.json PATH
```

Before passing 00A, confirm:

- the exact selected audio exists and Founder selection is explicit;
- lyrics or instrumental/vocalise status is source-backed;
- song craft evaluation is complete;
- section ids, order, and timing agree across all three artifacts;
- audio triggers come from the actual take;
- the audio map contains questions, not screen answers;
- 00A schema version is `1.5`;
- 00A contains no target, message, member, visual, reference, action,
  choreography, styling, camera, Core-Cut/Branch-Cut, prompt, or exact edit decision;
- the Department Dispatch v8 return names the CDD recipient, lineage/session and
  attempt, current input/result digests, and aggregate manifest (when the
  package has multiple files), while pointer indexes remain pointer-only;
- the Founder gate is PASS and all hashes validate.

## Stop Conditions

HOLD when:

- only chat prompt text or an unreturned generation prompt exists;
- no actual Founder-selected take exists for a locked 00A;
- lyrics are claimed but no original lyric/transcript source exists;
- craft evaluation is missing for a selected take;
- section order, timing, hook, or trigger evidence disagrees across artifacts;
- a required source or hash is missing or stale;
- a correction would overwrite an earlier Song Room attempt, bypass CDD review,
  or reopen unaffected Front Planning sections;
- the work would require paid generation, upload, network access, or another
  external action without current approval.
