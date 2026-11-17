# Choreography Module

Use when a direct study or an active run needs point choreography, performer
movement language, body readability, or choreography direction.

## Inputs

- exact choreography, performance, or fancam source and selected segment/frames
- exact count, time window, or supplied audio cue
- target performer/member identity inputs when adaptation is requested
- passed Front Planning section, active 01 direction, current-title member
  visual package, and selected-song cue only when projecting into an active run

## Focus

- point phrase that can become the short derivative memory
- member-specific signature moves and performance roles
- hands, feet, gaze, pose landing, and formation readability
- choreography direction that can later be converted into generation prompts
- one `movement_feel_adjective` that names the physical quality of the body
  motion without replacing the actual route, keypoints, or camera-readable detail
- optional named dance vocabulary anchors, used only to name a movement family
  before translating it into visible idol-performance mechanics
- separation between dance phrase and non-dance action: if the song section is
  not dance-led, choreographic detail should support the exact gaze, hand, foot,
  object, wardrobe, space, or memory action instead of forcing a full point
  phrase
- choreography presence policy: whether choreography is the primary carrier,
  supporting motion, a minimal body/gaze/hold readability guard, or absent

## Detailed Movement State Cards

Read the phrase as a continuous physical route rather than a sequence of pose
labels. Author as many ordered states as the source phrase needs to preserve its
setup, pass-through, impact, suspension, rebound, release, arrival, or
intentional hold. A state should establish, in natural language:

- exact count or time window and its relation to the audible cue when one is
  supplied;
- floor mark, facing, foot placement, heel/ball contact, step path, and travel;
- left/right support ratio, transfer order, knee bend, body level, and pelvic
  direction;
- spine, ribcage, sternum, abdomen, hip, and shoulder route;
- upper-arm, elbow, forearm, wrist, hand, and finger route;
- neck, head angle, gaze target, and any deliberate timing delay;
- brows, eyelids, mouth, jaw, breath, and expression change when the face is
  visible;
- formation, spacing, occlusion, and member exchange when present;
- hair, garment, accessory, object, and floor response;
- continuity inherited from the previous state and the physical route into the
  next state;
- visibility limits or source uncertainty instead of invented unseen motion.

These are observation axes, not a closed schema or a keyword-based machine
gate. Use all axes that are visible or physically consequential for the phrase,
and state why a hidden area cannot be verified. Human/model review judges
whether the description is sufficiently detailed, physically plausible, and
performable.

Keep source observation and adaptation separate:

```text
observed source body truth
-> preserved phrase grammar
-> target-performer or current-song timing adaptation
-> ordered movement state
```

## Movement Phrase Contract

The choreography map should describe movement as performable idol choreography,
not as loose pose keywords.
Use the passed Front Planning choreography presence policy and 01
section direction as the decision boundary. 00A supplies timing and audible
triggers only; it never selects dance. Dance-led sections need a
start-impact-release phrase. Non-dance action-led sections need precise body
readability details and pose landing only as much as the camera must make the
action legible. Film-led object, environment, or camera-route sections may carry
no choreography at all; do not convert those sections into dance merely to fill
the choreography map.

- body path: where the torso, arms, hands, feet, and gaze travel
- weight shift: how the body changes support, level, or direction
- movement feel adjective: one compact adjective such as sharp, elastic,
  grounded, clipped, fluid, restrained, or weightless; it colors the physical
  quality of the phrase but does not become the action itself
- dance vocabulary anchor: optional names such as waacking, voguing, popping,
  locking, tutting, house footwork, heels choreography, dancehall, or
  twerking; write the exact name in `motion_keywords` or
  `choreography_direction_notes`, then the same note must spell out the foot
  route, weight shift, hip/torso/hand path, gaze, camera readability, and
  endpoint
- count feel: where the phrase starts, hits, and releases
- member spacing: how the featured member and group shape read in frame
- camera-readable silhouette: the outline should read in close, medium, and
  wide shots
- pose landing: the beat or frame where the movement arrives clearly enough for
  camera, edit, and review to recognize it
- three-keypoint phrase: start / impact / release or hold from one continuous
  dance phrase, not three unrelated poses
- key choreography accents: each keypoint should have a distinct body state,
  direction, level, or energy

For `primary` or `supporting` sections, complete an execution pass after the
creative phrase is approved. Use exact section/audio plus beat or cue references and add:

- count grid: pickup, start, impact, release/hold, and next-phrase entry
- floor route and facing: entry mark, weight-bearing foot, travel path, center
  or diagonal, and exit mark
- formation route: member/unit spacing, center relay, occlusion risk, and
  formation entry/exit
- performer feasibility: difficulty, stamina load, landing/joint risk, garment
  or footwear constraint, and member-specific accommodation
- rehearsal notation: mirror/front convention, count notation, reset mark, and
  endpoint cue
- transition feasibility: the actual counts and body/formation route available
  between adjacent sections, plus camera/edit compatibility

Do not repeat the MV story, camera route, or visible-action paragraph inside
this execution pass; cite their ids and solve only the performability gap.

## Hold Conditions

- The phrase repeats the same hand reach, arm extension, or body shape across
  all keypoints.
- The final keypoint becomes a default frozen ending without choreographic
  reason. A deliberate hold is allowed when it carries memory, emotion, gaze,
  or section arrival.
- The movement is written as a category label or checklist rather than natural
  choreography direction.
- A named dance style is left as the whole action without visible mechanics,
  camera readability, and endpoint.
- A sexualized or club-coded dance term is used bare without visible mechanics
  and a controlled idol-performance tone guard. Keep the exact dance name for
  model recognition, but constrain the body route and camera treatment.
- Formation context makes the main member too small to read when the keypoint
  should be center-focused.

## Output Fragment

```yaml
choreography_map:
  source_binding:
  point_phrase:
  member_blocking:
  motion_keywords:
  movement_feel_adjective:
  readability_priority:
  choreography_direction_notes:
  phrase_structure:
  movement_state_cards:
  keypoint_states:
  coverage_storyboard_binding:
  execution_plan:
  risks:
```

## Checks

- The point phrase fits member assets.
- The movement has a readable start, impact, and release or intentional hold.
- The `movement_feel_adjective` is a physical motion quality, not a vague mood
  tag or replacement for body path.
- Any named dance vocabulary anchor is paired with visible body route, count
  feel, camera-readable silhouette, and endpoint.
- Movement states preserve count-level feet, weight, level, torso, limb,
  head/gaze, expression when visible, material response, and continuity rather
  than collapsing into still-pose summaries.
- Source uncertainty and off-frame mechanics are identified rather than
  invented.
- Movement intensity matches the song section function.
- The choreography fits the selected performance reference and member assets.
