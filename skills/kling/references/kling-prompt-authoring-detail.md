# Kling Prompt Authoring Detail

Use this detail file when drafting, rewriting, or QAing an actual Kling prompt.
This is a repo-local heuristic snapshot. Verify official Kling documentation
first if the founder approves a current-source check.

## Source Basis

This guidance was distilled from public Kling documentation and prompting guides
available when the skill was written, especially:

- `https://kling.ai/quickstart/text-to-video-prompt-guide`
- `https://kling.ai/quickstart/image-to-video-guide`
- `https://kling.ai/quickstart/klingai-video-o1-user-guide`
- `https://kling.ai/quickstart/klingai-video-26-audio-user-guide`
- `https://kling.ai/quickstart/klingai-video-3-model-user-guide`
- `https://kling.ai/quickstart/ai-video-start-end-frames`
- `https://kling.ai/quickstart/how-to-animate-image-parts`
- `https://kling.ai/quickstart/how-to-choose-video-mode`
- `https://www.veed.io/learn/kling-ai-prompting-guide`
- `https://leonardo.ai/news/kling-ai-prompts`

Use official Kling pages as the stronger source when sources disagree.

## Core Prompt Shapes

### Text-To-Video

```text
[Shot scale] of [specific subject] [one primary action], in [scene with 3-5 concrete elements],
[one main camera move with direction, speed, and endpoint], [lighting], [visual style or mood].
```

Kling's public text-to-video formula at the time of writing was:

```text
Subject + subject movement + scene + camera language + lighting + atmosphere
```

Keep the action suitable for a 5-10 second clip. Do not pack a full music video,
ad script, or multi-scene story into one generation unless the user specifically
uses a workflow that supports multi-shot output.

### Image-To-Video

```text
Preserve the provided image exactly. [Visible subject] [specific movement],
[optional background/object movement], [camera move or static camera],
ending with [clear final pose or settled state].
```

The source image supplies identity, wardrobe, scene, composition, and lighting.
Spend prompt space on what moves, how it moves, and where motion lands.

### Start And End Frames

```text
Take @image1 as the start frame and @image2 as the end frame. From [start pose/composition],
[subject action route] while [camera route], ending exactly on @image2 with [final pose/composition].
```

Start and end images should be visually similar. Large changes can cause a shot
switch or transition rather than a smooth motion bridge.

### Elements

```text
[Element A identity/function] and [Element B identity/function] [interaction],
in [environment/background], with [visual direction: camera, lighting, style].
```

Name the interaction directly. Avoid generic verbs such as `interact` without
saying who moves, who reacts, and what changes on screen.

### Motion Control Or Motion Brush

```text
[Controlled element] [motion that matches the brush/reference path], while
[static areas or background behavior], [camera behavior].
```

For Motion Brush, keep one brushed region to one connected element when
possible. The text prompt must match the drawn motion. If the background should
not move, state that it remains static and use a static brush when available.

### Native Audio

```text
[Scene] + [subject/character] + [movement] + [audio] + [style/emotion/camera]
```

For dialogue:

```text
[Character A, tone/speed/emotion]: "line." [Character B, tone/speed/emotion]: "line."
[ambient sound or BGM]. [camera behavior].
```

Use clear character labels for each speaker. For singing or dialogue-heavy
generations, prefer 10 seconds when the setting allows it. For visual control,
English prompt text is usually the safest default; keep spoken lines in the
target language only when the active Kling model supports that language.

## Writing Rules

- Put one main subject and one main action at the center of each prompt.
- Use one main camera movement per shot: push in, pull back, pan left, pan
  right, tilt up, tilt down, track forward, track sideways, slow orbit, or
  static camera.
- Tie the camera move to the subject action: `camera slowly pushes in as her
  hand reaches the microphone`.
- Include shot scale and camera height when they matter: close-up, medium shot,
  full-body shot, low frontal, high three-quarter, side tracking.
- Give a clear endpoint: `then settles into a still final pose`, `camera stops
  on the product label`, or `hair falls back into place`.
- Keep scene details concrete and limited. Three to five environment details
  are usually enough.
- Use physical, visible motion: `turns her head left`, `steps forward once`,
  `coat hem lifts in the wind`, or `camera tracks beside her`.
- Keep movement plausible from the source image.
- Avoid exact large counts. Use small groups, position labels, or composition
  language.
- Avoid complex physics in one prompt. High throws, bouncing paths, gymnastics,
  and multi-part object collisions need simplified motion or multiple passes.
- Avoid vague standalone style words. `cinematic` is useful only after shot,
  subject, action, camera, and lighting are clear.
- Avoid contradictions such as `static camera` and `dynamic orbit` in one shot.
- If a negative prompt field exists, keep it short and concrete.

## Prompt QA Checklist

1. Mode is clear: text-to-video, image-to-video, start/end frames, elements,
   motion control, or native audio.
2. First sentence names the visible subject and action.
3. Image-to-video prompts do not waste space re-describing the image.
4. Camera movement has direction, speed, and endpoint.
5. The prompt fits 5-10 seconds unless a longer workflow was requested.
6. There are no more than three sequential subject actions in one clip.
7. The prompt avoids exact high counts, impossible physics, and overloaded
   detail.
8. Native-audio prompts label every speaker and avoid unsupported language
   assumptions.

## Common Fixes

- Static or weak motion: add subject action, camera action, and final landing.
- Random camera movement: specify `static camera` or one clear move with a stop.
- Identity/style drift in image-to-video: say `Preserve the provided image
  exactly` and remove extra restyling.
- Awkward cuts in image-to-video: make the requested action closer to what the
  image can physically support.
- Unfinished motion: add a clear endpoint or settled final state.
- Overloaded output: remove secondary subjects, extra props, multi-step actions,
  and compound camera moves.
- Dialogue confusion: label speakers with names or roles before each line.
- Dance/performance blur: use full-body or medium-wide framing, a simple weight
  shift, one readable pose landing, and a camera move that does not hide feet or
  hands.
