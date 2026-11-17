# IDOL Video Prompt Record Template

This is an operator/index record. Only the fenced block under
`Generator-Facing Prompt` is emitted as `prompt.txt` and pasted into a video
generator.

## Source And Lineage

- Run:
- Source snapshot path:
- Source snapshot SHA-256:
- Source-set SHA-256:
- Section id:
- Cut id:
- Packet id:
- Placement frame id:
- Founder review status: `pass`
- Source image path:
- Source image SHA-256:
- Selected skill: `idol-video-prompt`
- Choreography presence policy:
- Frame subject mode:

Keep every id and source path in this metadata section. Do not copy them into
the generator-facing block.

## Canonical V3 Controls

- Lyric or no-lyric cue:
- Audio cue/tension (`audio_pressure` compatibility field):
- Visible start pose: inspect and write from the actual source pixels
- Start trigger:
- Screen motion route or intentional hold:
- Camera route:
- Camera capture:
  - camera height:
  - shot scale / distance:
  - direction / angle:
  - depth / framing:
  - screen placement / crop:
- Pacing / timing:
- Endpoint:
- Edit handoff:
- Previous / next continuity:
- Planning carry source-field projections:

## Generator-Facing Prompt

```prompt
Use the provided image(s) as the complete visual source; keep the visible
appearance, styling, lighting, materials, and environment unchanged.

Camera + action:
[Start from the visible pixels. State the first trigger, exact
member/object/environment/system motion or intentional hold, and the motivated
camera route as one connected paragraph. Do not include internal ids or source
names.]

Camera capture:
[State camera height, shot scale/distance, direction/angle, depth/framing, and
subject placement/crop/negative space that keeps the event readable.]

Pacing / timing:
[State the trigger, acceleration or hold, impact/release, exact endpoint, and
edit handoff.]
```

### Presence Compile Guard

- For `primary` or `supporting`, include a dance/choreography anchor only when
  it improves control and immediately translate it into visible mechanics.
- For `minimal_body_gaze_hold_guard`, include only the bound body/gaze/hold.
- For `absent`, remove every dance, choreography, formation-dance, dance-pose,
  and related dance-activation token from the fenced prompt. Do not add a
  negative dance sentence; acting, gaze, body holds, and object/environment
  motion remain available when bound upstream.
- For a non-member-led cue, the motion paragraph may contain only the object,
  environment, system, camera, or intentional hold.

## QA

- Actual image inspected, not inferred from filename:
- Prompt carries the exact screen-motion/hold route:
- Prompt carries all five camera-capture axes:
- Internal ids absent from generator text:
- Appearance inventory absent unless a drift-recovery record requires one term:
- `absent` cue contains zero dance/choreography tokens:
- Endpoint and edit handoff are observable:
- Section QA status:
- Open decisions:
