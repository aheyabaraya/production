# Selected Audio, Audio Evidence, And 00A Authoring Detail

This reference expands `idol-song-lock/SKILL.md`. The three active artifacts
share one music-director owner and one actual selected take, but each has one
clear job:

| Artifact | Owns | Must not own |
| --- | --- | --- |
| selected-audio analysis | music/lyric/craft/section evidence and questions | MV target or screen answers |
| audio motion evidence map | pulse, trigger, density, reset, timing evidence | action, camera, prompt, styling, edit lock |
| 00A | compact selected-song and section lock | Front Planning, 01, 02A, 02B, 03V, or 04 decisions |

## Selected-Audio Ingest

Start with the actual file, not a Suno prompt or candidate description.
Preserve:

- audio path and SHA-256;
- take id and source kind;
- Founder selection status;
- original lyric/transcript path and SHA-256, or explicit
  instrumental/vocalise status;
- uncertainty instead of guessed lyric text.

Listen at least once for the whole-song arc and again by section. The structured
analysis must answer:

1. What is the song doing musically?
2. What makes the selected take stronger or weaker than alternatives?
3. Where do the actual section boundaries and returns occur?
4. Which lyric, vocal, rhythm, bass, transient, silence, or texture events
   justify those boundaries?
5. What remains an open question for Front Planning?

### Craft Evaluation

Use the same declared dimensions for every candidate in one evaluation. Useful
dimensions include hook prosody, melodic memorability, section contrast,
arrangement development, vocal-stack behavior, lyric delivery, sonic identity
developed across the opening arc, completion through the actual intro boundary,
recognizable middle/later hook returns, and derivative editability. Scores
support a written judgment; they do not replace it.

For `founder_selected`:

- `selected_candidate_id` matches the selected take;
- every candidate has one scorecard row;
- every row covers the declared dimensions;
- the selection reason names concrete audible consequences;
- promotion readiness is complete.

### Section Analysis

Each active section records:

- canonical `section_id`, label, family, start, and end;
- energy and sonic read;
- lyric source and lyric/music function;
- concrete audible triggers with timestamps;
- editability evidence;
- questions for audio mapping and Front Planning.

A good question preserves the problem without pre-authoring the answer:

```text
At 00:42.180 the vocal stack opens after a dry stop. Which visible state
change should Front Planning assign to this release so the selected audience
can read the message turn?
```

A bad entry authors another stage:

```text
At 00:42.180 use a low-angle dolly-in on Member A as she turns beside the red
car.
```

The latter belongs to Front Planning/01/02A and, for temporal camera motion, to
03V after images pass.

## Precision Audio Evidence

When local audio is available, optional sidecars may include:

```text
*-beat-grid.tsv
*-onset-candidates.tsv
*-pitch-contour.tsv
*-motif-candidates.tsv
*-motif-candidates.json
```

Record each path and SHA-256. These files are measurement evidence only.
Automated boundaries, tempo candidates, or contour changes never become
creative truth without listening judgment.

Pitch contour is a register/entry-shape proxy unless a valid isolated-vocal
source exists. A motif candidate is evidence of recurrence; Front Planning
decides whether that recurrence should later become character, object,
performance, world, or negative-space content.

## Audio Motion Evidence Map

The active schema keeps the historical contract name
`idol_audio_motion_director_map.v1`, but its content is deliberately audio-only.

### Stable Extracts

Record:

- duration;
- main tempo grid and perceived pulse;
- alternate grid or uncertainty;
- meter when defensible;
- source-hashed signals and optional precision marker sources;
- the evidence-only rule.

### Section Rhythm Map

Preserve selected-audio section ids, order, start, and end exactly. For each
section, record:

- main pulse;
- energy density;
- accent grid;
- onset, stop, and reset behavior;
- vocal or lyric trigger;
- motif return;
- audible state-change pressure: `sustain`, `accent`, `reset`, `release`,
  `contrast`, or `none`;
- screen-readability questions;
- editability evidence;
- `temporal_camera_deferred_to_03v: true`.

Do not write `body_behavior`, `camera_rhythm`, `prompt_overlay`,
`director_planning_use`, Core-Cut or Branch-Cut count, scene grammar, or reference
application. Those fields recreate downstream decisions and are forbidden.

### Trigger Map

Each trigger has one section, time, type, audible fact, and downstream question.
The question may ask what later state change should answer the cue. It must not
name the chosen member, action, space, camera, composition, styling, or prompt.

## Promotion To 00A

Promote only when:

- the selected take is confirmed;
- original lyrics or instrumental status are source-backed;
- craft evaluation is complete;
- selected-audio and audio-map section ids, order, and timing agree;
- the map is `ready_for_00a`;
- no hold reason remains.

Active 00A schema `1.5` carries:

- exact selected-audio, analysis, audio-map, and lyric sources;
- tempo/form and selected-take craft consequences;
- hook behavior; sonic identity and opening-arc completion through the actual
  intro boundary; and the recognizable carrier shared by the first full hook
  and middle/later returns;
- song meaning and misread guards;
- canonical section timing, lyric/music function, energy/density, audible
  triggers, and meaning guard;
- audio-pressure summaries and Front Planning questions;
- song editability evidence and 04 ownership of exact cut timing;
- Founder PASS/HOLD/REJECT.

It intentionally has no action directive, visual readability target, output lane, member,
wardrobe, visual, reference, scene, camera, Core-Cut, Branch-Cut, prompt, or
exact edit field.

## Front Planning Handoff

Front Planning reads 00A and then decides:

- primary audience and content promise;
- target-facing MV message;
- current-title member and background visual identity;
- reference connection research and section assignment;
- member placement by section;
- whole-video message/content progression;
- major scene flow and key scene purpose in each section.

01 expands section staging and reference application. 02A turns that into
Core Cuts and ordered Branch Cuts with still-frame camera geometry. 02B
translates passed 02A into the fixed prompt structure. 03V begins temporal
camera and motion direction only after passed pixels.

## Local Revision

Use the smallest owning truth:

- new or changed take -> selected-audio analysis, then affected audio map and
  00A;
- corrected lyric or section timing -> selected-audio analysis, affected map
  rows, and affected 00A section rows;
- corrected pulse or trigger evidence -> audio map and affected 00A rows;
- target, message, visual, member, reference, or scene change -> Front Planning;
- still-frame action/composition change -> 01 or 02A;
- image prompt wording change -> 02B;
- temporal camera change -> 03V;
- exact cutpoint change -> 04.

Do not reopen unaffected sections or refill earlier documents solely to satisfy
the graph-engineering route.
