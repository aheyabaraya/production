---
name: idol-choreography-board
description: "Use after source-bound choreography movement states exist to select three or four materially different camera coverage cuts, create an actual image-based choreography storyboard board, and prepare cut-specific image-to-video guidance. This IDOL choreography-board owner is separate from general storyboard skills."
---

# IDOL Choreography Board Director

This skill owns the compact visual coverage board for one choreography phrase.
It does not own choreography invention, MV story direction, canonical 02A
Branch-Cut cardinality, or the canonical 03V storyboard-board contract.

## Required Reads

Read completely:

1. `AGENTS.md`
2. `policies/creative-production-constitution.md`
3. the calling `idol-choreography-performance` result;
4. exact source path, SHA-256, selected segment/frames, and preservation rule;
5. ordered movement-state cards;
6. expression, gaze, lighting, hair, garment, object, and continuity notes;
7. target performer/member identity inputs when adaptation is requested.

Read `policies/section-production.md` and active 02A/03V contracts only when the
board is being used as supporting evidence for a named active MV section.

## Ownership Boundary

The choreography-performance skill owns physical body truth and performance
direction. This skill owns only:

- coverage-cut selection;
- panel-image requirements;
- the ordered three- or four-panel image board;
- cut-specific image-to-video guidance.

Keep two independent identifiers:

```text
movement_state_id = what the body physically does at a count/time
coverage_cut_id = how that state or transition is framed
```

A new camera angle must not change foot placement, weight, body level, torso
route, hand path, gaze, expression, garment response, or timing.

## Three-Or-Four-Cut Board

Select three or four ordered coverage cuts for one choreography phrase. The
board must use actual images, one image per cut. A text card, empty frame,
placeholder, or prompt-only panel is not an image storyboard.

Choose only views that reveal materially different choreography information.
Possible views include front full body, three-quarter or profile body,
hand/arm detail, face/gaze detail, overhead floor route, low-angle impact, rear
body route, or another source-led view. This list is a vocabulary, not a
checklist. Do not use every angle and do not add a cut only to vary shot size.

The board normally combines:

- one view that preserves the phrase's necessary body or formation context;
- one or more views that reveal an important route, impact, expression, or
  detail the wider view cannot show;
- one view that makes the phrase's release, arrival, or edit handoff readable.

The actual source phrase decides which three or four views satisfy those jobs.
Human/model review judges the selection; scripts must not rank camera choices.

## Coverage Cut Record

For every cut, author:

- `coverage_cut_id`;
- source `movement_state_id` or state transition;
- exact count or time window;
- actual panel-image path and SHA-256;
- camera height;
- distance or shot scale;
- direction and angle;
- foreground/background depth;
- subject placement, crop, and negative space;
- visible body, face/gaze, garment, object, floor, and lighting facts;
- the distinct choreography information made readable;
- continuity inherited from the prior cut and carried into the next.

A close crop may hide part of the body, but the underlying full-body continuity
must remain in the movement-state record.

## Panel Images And Board Assembly

An observation board may use approved source-bound frames or crops. A
target-performer adaptation board must use approved target-performer storyboard
images rather than presenting source-performer pixels as the adapted result.

Image prompting does not authorize image generation. When new panel pixels are
required, hold at `visual_storyboard_pending` until the Founder approves the
exact generation scope. Approved OpenAI image API work in IDOL uses
`gpt-image-2`.

Assemble the three or four panels in their intended order as one labeled image
board. Prefer PNG, preserve approved source quality, and keep labels outside the
panel image content when possible. Before completion, record each panel and
the assembled board's path, SHA-256, dimensions, and pixel-inspection result.

This board has no inherited grid style. Add a grid only when the Founder
explicitly requests one for this choreography board, then define that board's
grid locally without importing a general storyboard-skill default.

## Cut-Specific Image-To-Video Guidance

Treat each coverage cut as a separate visual setup. Prefer one camera setup per
generated clip and join clips at the authored count/audio transition. Do not
ask one clip to teleport from a full-body frame to a hand close-up or overhead
view.

For every cut-specific prompt, preserve:

- movement-state timing and physical route;
- target identity and appearance inputs;
- visible setup, pass-through, impact, rebound, release, or hold;
- off-frame body continuity;
- expression and gaze when visible;
- hair, garment, accessory, object, floor, lighting, and material response;
- one temporal camera route or intentional hold;
- exact landing state and edit handoff.

## Graph Engineering Boundary

The three-or-four-cut choreography board is review and authoring evidence. It
is not a cap or automatic roster for canonical 02A Branch Cuts.

When the phrase enters the active MV graph-engineering route:

- Front Planning and 01 must already authorize `primary` or `supporting`;
- 02A independently decides its evidence-led Branch-Cut roster;
- 03V continues to use one to three passed Production Cut images of type
  `official_core` or `branch` per canonical storyboard board and splits more
  into linked boards.

Without that active handoff authority, return only a noncanonical choreography
board and do not write or imply approval for 01, 02A, 02B, 03V, generation, or
release.

## Output Fragment

```yaml
choreography_board:
  source_binding:
  movement_state_ids: []
  coverage_cuts:
    - coverage_cut_id:
      movement_state_or_transition:
      count_or_time_window:
      panel_image:
      camera_geometry:
      visible_performance_truth:
      distinct_readability_job:
      continuity_in:
      continuity_out:
  assembled_board:
  image_to_video_prompt_bindings: []
  status:
  holds: []
```

## Quality Gate

PASS only when:

- the board contains exactly three or four ordered, actual image panels;
- every cut binds an exact movement state or transition;
- every cut adds materially different choreography information;
- body, expression, identity, light, and edit continuity survive across cuts;
- every panel and the assembled board have current paths, hashes, dimensions,
  and pixel inspection;
- no source-performer panel is mislabeled as a target-performer adaptation;
- any required generation has exact Founder approval;
- the board is not treated as an automatic 02A roster or a replacement for the
  03V board contract.
