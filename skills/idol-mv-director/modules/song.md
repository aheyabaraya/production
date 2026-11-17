# Song Module

Use this module inside active 01 when a section needs a closer read of the
selected song. It interprets 00A constraints together with passed Front
Planning; it does not restore retired 00A screen-action fields.

## Inputs

- passed `00A-song-lock.yaml` using schema `1.5`;
- passed Front Planning creative spine;
- exact selected audio and original lyrics/transcript;
- current section's selected-audio and audio-map evidence;
- current-title member assets only when Front Planning assigned those members.

## Ownership Boundary

00A supplies:

- exact selected take and lyric truth;
- section ids, order, timing, and song/lyric function;
- energy/density and audible triggers;
- hook, meaning, and tonal guards;
- audio-pressure summaries and unanswered Front Planning questions.

Passed Front Planning supplies:

- target, message, and audience promise;
- member and current-title visual assignment;
- reference application and choreography presence policy;
- section role, major scene flow, and whole-video progression.

01 authors the observable answer: story action or hold, staging, space/object
behavior, member behavior, still-camera geometry, composition, and transition.
03V owns temporal camera motion after passed pixels.

## Method

For each section:

1. listen to the exact section and read its original lyric or instrumental
   status;
2. preserve 00A timing, audible triggers, hook, and meaning guard;
3. preserve the passed Front Planning section job and reference assignment;
4. choose the strongest observable scene realization;
5. explain how the selected action/hold and still view answer the song without
   literalizing every lyric;
6. activate choreography only when Front Planning marks it
   `primary`/`supporting` and an actual choreography, performance, or fancam
   source is bound;
7. leave temporal camera movement to 03V.

## Output Fragment

```yaml
song_application:
  source_song_lock:
  section_id:
  exact_audio_range:
  song_function:
  lyric_function:
  energy_and_density:
  audible_triggers:
  meaning_guard:
  front_planning_section_job:
  selected_scene_answer:
  still_frame_consequences:
  choreography_presence_policy:
  transition_consequence:
  risks:
```

## Checks

- The screen answer comes from 00A plus passed Front Planning, not BPM alone.
- The action is observable and specific to the selected song.
- A lyric line is literalized only when the words themselves are the audible
  turn and the choice serves the target/message progression.
- Member use follows Front Planning.
- Choreography is source-bound or absent.
- Still-camera geometry is concrete; temporal camera motion is absent.
- 02A can expand the result without inventing a new section direction.
