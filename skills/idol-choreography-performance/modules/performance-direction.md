# Performance Direction Module

Use when a direct study or an active run needs performance readability:
blocking, formation, camera behavior, expression, lighting, performer presence,
and choreography capture. For film-led, object-led, environment-insert, or
camera-route sections, use this module only as an identity/readability guard
when a member or body evidence is actually visible.

## Inputs

- exact choreography/performance/fancam source and selected segment/frames
- detailed movement-state cards
- target performer/member identity inputs when adaptation is requested
- selected audio cue when timing is supplied
- active Front Planning/01 and current-title assets only for canonical handoff

## Focus

- camera-readable body, face, hands, spacing, weight shift, and pose landing
- brows, eyelids, gaze, mouth, jaw, breath, and expression transition
- formation center and transition logic
- performance blocking and performance cut opportunities
- state- and cut-specific lighting that preserves face, hand route, body line,
  floor contact, garment/material response, and performer identity
- whether choreography remains readable in close-up, medium, and wide shots

## Performance Craft Rules

- Performance direction exists to make choreography and member identity readable.
- It does not decide that every section needs choreography. When
  `frame_subject_mode` is world/object-led, environment-insert, or
  system-transition, performance direction should name only the member/identity
  guard that is visible, or stay out of the section carrier.
- Camera behavior should be designed from the movement phrase, not pasted on top
  afterward.
- Each choreography keypoint should get a fitting shot scale or camera note; do
  not repeat one camera note across the whole phrase by default.
- Use close-ups for face, gaze, and hand detail only after the body action is
  still understandable.
- Use wide or medium-wide frames when formation, spacing, feet, or full-body
  lock matters.
- Lighting should flatter the face while preserving hands, body line, outfit
  material, and floor contact.
- For every selected movement state with a visible face, describe the starting
  expression, the muscle-level change through the cue, the gaze target or
  delay, and the expression held or released at the end. Do not use a mood
  adjective as the entire facial direction.
- Treat breath as physical performance evidence when it changes the sternum,
  shoulders, mouth, or timing; do not invent visible breath merely to fill a
  field.
- Write lighting as a readability response, not only a palette or atmosphere:
  name the light direction or boundary that keeps the required face, hand,
  torso, foot, floor, hair, garment, or accessory behavior legible.
- Preserve light continuity across neighboring coverage cuts unless the source,
  stage cue, or authored lighting event justifies a visible change.
- If a camera move hides a key movement route, change the camera before
  changing the approved choreography.
- Keep supporting dancers or formation context behind, partial, soft, or
  secondary when the main member's keypoint is the visual anchor.
- Do not let key movement panels collapse into face-only, outfit-only, or empty
  light/performance panels.

## Output Fragment

```yaml
performance_direction_map:
  camera_behavior:
  formation_logic:
  lighting_behavior:
  state_expression_notes:
  state_lighting_notes:
  keypoint_camera_notes:
  coverage_cut_notes:
  performance_cut_opportunities:
  identity_readability_checks:
  movement_readability_checks:
  risks:
```

## Checks

- Performance direction serves the song hook and choreography point.
- Camera does not hide a choreography keypoint.
- Facial direction names observable gaze and facial change when the face is
  visible.
- Lighting and crop preserve performer identity, required body evidence, and
  material/floor readability.
- Neighboring coverage cuts preserve expression, body, and lighting continuity
  unless a named cue changes them.
- Full-body moments remain available for the master and derivatives.
