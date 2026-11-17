# Video Prompt Authoring Detail

Read this reference after `skills/idol-video-prompt/SKILL.md` when writing,
revising, validating, or handing off production prompt text. Keep the top-level
skill as the route and gate; use this file for the longer authoring grammar.

## Source Order

Use the current run structure before writing motion language:

1. Actual attached/generated images. Pixels decide visible identity, styling,
   wardrobe, lighting, camera anchor, source order, and endpoint.
2. Active `idol_video_prompt_manifest.v8`. Read
   `active_storyline_binding`, `selected_sequence_binding`,
   `major_scene_binding`, `screen_progression_binding`, ordered
   `source_production_cut_images`, `motion_derivation_note`,
   `subject_motion_route`, `camera_motion_route`, and
   `previous_next_continuity`.
3. Exact FP v17, 01 v3.0, and 02A v3.0 sources named by those bindings. Resolve
   Major/Sequence/storyline/screen truth from the bound pointers and value
   hashes, not from broad-search rediscovery or a neighboring summary. A
   contact sheet contributes its selected cell/crop, never the whole sheet.
4. `idol-production-cut-review.v2`, the active v4 Motion Storyboard assist, and
   `idol_audio_production_cut_placement.v5`. Use the typed Official Core/Branch
   ids, ordered passed-image roles, pixel truth, audio cue, transition need,
   and continuity evidence.
5. The active Audio Production-Cut Placement, audio-motion director map, and
   selected-audio analysis. Translate timing into visible body/camera pacing;
   do not ask the video model to hear audio unless the target tool actually
   receives audio.
6. Choreography and performance-direction modules only when the body/camera
   bridge is missing or weak.
7. 02B review board/export only for intent recovery. Never copy render-wrapper,
   contact-sheet, support-panel, or schema text into prompt prose.

If an expected cue map or audio-motion map is missing or stale, HOLD. Do not
recover its timing authority from 02A or author a conservative image-only draft;
restore the current owning audio evidence first.

## Upstream Boundary

This skill is the final image-to-video translation layer, not a second 01/02B
planning pass. Do not re-run the full song, MV direction, or integration modules
when their decisions already arrive through 03V, cue sheets, section manifests,
02B exports, or founder pass notes.

Treat upstream artifacts as compressed truth for song cue, optional literal
original lyric text, MV world, camera/composition intent, integration decisions,
video-prompt readiness seeds, and edit-readiness hints. Only open full upstream
modules when a required bridge is missing or contradictory.
Likewise, use `consume_bound_interpretation` for valid reference receipts. A
different 03V model or session does not authorize reinterpretation.

## Planning Carry Into 03V

The active v8 manifest and v4 board already exact-carry planning truth through
typed bindings. Before final prompt writing, read those bindings as one compact
planning carry. It should answer:

- which source refs were used
- what section story function this clip carries
- what front-planning transfer survives into the motion bridge
- which current-title album visual asset is being preserved or used, if any
- what reference function or contact-sheet surface is followed
- how object/space state remains continuous across the cue
- what 04 can later use as an edit-intent seed, without setting exact cutpoints

Verify the exact active storyline, Major, selected Sequence Composition and
Units, screen-progression map/nodes, 02A Cut, screen job, Production Cut review,
and audio-placement pointers and value hashes.
Within `selected_sequence_binding`, exact-carry the complete
`sequence_motion_analysis_binding` from FP to storyboard assist, 03V source
pack, and manifest cue. Dereference and verify the analysis artifact, selected
candidate row, Major/section/Sequence identities, and immutable CDD review DDC;
never flatten it into prompt prose, add a sixth source-pack role, or admit an
unselected/pre-copy-only row. Machine validation checks those exact joins;
contextual review judges the resulting motion meaning. Historical
manifest-v5 `planning_projection_sources`, `upstream_frame_lineage`, and
`source_field_projections` remain legacy evidence and are not active v8 fields.

Use the semantic owner, not a convenient neighboring sentence:

- bind whole/section passage from `active_storyline_binding`;
- bind Major and Sequence truth from `major_scene_binding` and
  `selected_sequence_binding`;
- bind camera/staging continuity from `screen_progression_binding` and each
  Production Cut's exact `screen_job_binding`.

Do not substitute a semantically adjacent summary for any exact active pointer,
source value, or hash. Missing or stale joins are HOLD.

If a passed Official Core or generated Branch image contradicts the planning carry, the pixels still lock
identity/style/camera anchor for this 03V prompt, but mark the cue `hold` or
route the contradiction back to 02A/02B instead of hiding it in motion prose.
Use the typed Production Cut review and, for a Branch, its current generated review; this does
not reopen the upstream reference. Reopen reference meaning only for changed
source/cell bytes, an incomplete lock, changed selected-audio meaning,
identity/safety/feasibility conflict, or explicit Founder re-review, then
invalidate affected downstream projections.

If upstream 02A/02B/imagegen review locked cinematic realism for fantasy,
mythic, surreal, or impossible-world material, inherit that lock into video
prompt prose. Preserve the passed image as a live-action filmed set with
practical effects and post-production composite. Do not re-describe the world as
illustration, animation, anime, fantasy-game art, 3D render, glossy AI art, or a
creature/mascot lane unless founder review explicitly changed the lane.

## Motion Bridge

For every 03V board prompt, compile this bridge:

```text
image anchor
+ 03V / section manifest
+ planning carry from front-planning / 01 / 02A / album assets when present
+ song audio cue/tension
+ idol-choreography-performance when needed
= video motion bridge
```

## Motion/Camera-First Compile

Keep authoring truth and generator control separate. The active 03V manifest retains audio,
optional literal original lyric text, planning carry, previous/next continuity, and edit-basis
evidence. Compile those records into visible action; do not paste every field
into `prompt.txt`.

One useful generator-facing flow is:

```text
short image-source lock
 start trigger
 member/object/environment/system/intentional-hold route
 camera geometry and motivated camera route
 screen placement/crop/depth capture
 pacing, hit/hold, endpoint, edit handoff
```

This flow is optional, not a fixed sentence order or word allocation. Give
movement, camera, timing, and screen capture the detail this cue needs. A clean
attached image normally needs only a compact source lock; do not repeat a
catalogue of face, hair, makeup, jewelry, outfit, lighting, color, and
environment. Use `drift_recovery_minimal` only after a recorded failure
identifies the exact attribute that must be restated.

The active `camera_motion_route` and the visible start view must collectively
preserve:

- camera height
- camera-to-subject distance / shot scale
- camera direction / angle
- foreground-background depth and framing
- subject placement and crop pressure inside the screen

`camera_motion_route` says how and why the camera moves or holds after the
passed still geometry. Do not add a second compatibility camera tuple or let
field count decide creative readiness.

For every active storyboard-assisted cue, `@image1` is the storyboard board and
`@image2` through `@image4` are the ordered original images that actually exist.
The prompt must make the visible cause and landing across that board order and
those original states executable. Draw on the cue, start state, applicable
member/object/environment/system route or intentional hold, camera, pacing,
endpoint, and continuity only as they clarify that bridge; do not recite every
source field.

When `choreography_presence_policy` is `primary` or `supporting`, translate a
style label into the few visible mechanics that define this cue, such as one
foot/weight decision, hand path, gaze, garment reaction, camera response, or
endpoint. Do not paste module prose or force every example into one sentence.
For `minimal_body_gaze_hold_guard`, preserve only the stated guard. For
`absent`, do not introduce choreography meaning; the object, environment,
system, camera, or intentional hold remains the screen carrier. Token presence
or a negative phrase such as “no dance” is not itself a pass/fail signal—the
contextual review judges whether the prompt actually invents choreography.

## Choreography Activation And Recovery

Use choreography activation only when the upstream policy is `primary` or
`supporting` and the generator needs explicit dance-language permission to
move. The activation phrase is not the action; it
needs nearby visible mechanics that make the actual motion executable.

Optional shape, not required wording:

```prompt
Perform a clear K-pop idol choreography phrase: [foot/weight/hand/torso/gaze
route], while the camera [camera route] and the motion ends [endpoint].
```

Named dance vocabulary may be used when it improves model recognition:
`waacking`, `voguing`, `popping`, `locking`, `tutting`, `house footwork`,
`heels choreography`, `dancehall`, or `twerking`. Keep the exact name only if
the surrounding prompt also makes the specific body mechanics, camera response,
endpoint, and idol-performance tone needed for that shot observable; it need
not enumerate every possible body axis.

Use choreography recovery only after ordinary prompts produce static poses,
camera-only movement, weak body motion, unreadable hands/feet, or repeated
failure to express a policy-authorized 03V body route. Recovery may rewrite
`subject_motion_route`, `camera_motion_route`, `choreography_bridge`, and
`prompt_text`. It must not change member
ownership, song meaning, wardrobe, source image order, endpoint, or 01 direction.
If it would require those changes, route back to 01/03V.

## Camera Grammar

Keep camera angle/framing and camera technique separate, then write them as one
connected action.

- Geometry baseline: the review unit collectively makes camera height,
  camera-to-subject distance/shot scale, direction/angle, depth, placement/crop,
  movement or hold, and dramatic reason recoverable where they matter. Do not
  split them into a tuple or invent an axis the source image does not establish.
- Angle/framing: low frontal, front three-quarter, side track, rear
  three-quarter, overhead, close-medium, medium-wide, full formation, foreground
  hand, boot near lens.
- Technique: locked hold, gimbal follow, lateral track, dolly backward,
  push-in, punch-in on hit, tilt, rack focus, foreground parallax,
  widen-then-push, recoil, locked stop, anchored orbit around a visible body or
  object route, slight diagonal/Dutch tilt.

Do not use techniques as decorative tags. A motivated orbit is allowed only when
anchored to a visible body route, handrail, bag, garment edge, foreground object,
or formation line. If the basis is weak, use a locked hold, subtle push, short
punch-in, or small lateral drift tied to a visible floor, rail, belt, tray,
corridor, or formation line.

When analyzing reference stills, record the observed geometry that actually
determines the shot and distinguish it from inferred video technique. Name
uncertainty rather than completing a camera checklist from imagination; infer
movement only when the body route, floor line, foreground object, reflection,
garment edge, or formation direction visibly motivates it. If the still is a bound scene reference whose first-read is incomplete, recover
or reopen the media-shaped observation contract in
`skills/idol-front-planning-director/references/director-operating-contract.md`
(top-level H2 `## 02B-Shaped Source Observation`) rather than inventing motion
from a mood, function label, or incomplete summary. Whole contact sheets remain
navigation only.

## Section And Image Bridge

For Production Cut image work, compare section function and pixels:

```text
section function + start image -> missing body/camera transition -> end image
```

For each bridge, decide start state, target state, gap motion, transition-match
continuity, camera bridge, section cue, the applicable movement/performance
continuity, and endpoint. `@image1` is the Motion Storyboard; original passed
pixels begin at `@image2`. If two original states are too different to connect
cleanly, say so and write a transition-safe bridge instead of forcing an
unsupported body transition.

Use acceleration and deceleration as timing, not decoration. When crossing a
cut, name what carries through it: direction, speed, step phase, foot/floor
contact, hand path, garment swing, or body momentum.

## Contextual Prompt QA

Before finalizing `prompt.txt`, read the prompt with its actual source images,
section cue, active manifest record, and adjacent boundaries. Use the following as
review lenses, not independent checkbox gates or keyword tests:

- source image order is explicit and correct
- identity/style/environment lock is present but not bloated
- first trigger, impact/hit-stop, release/hold, and endpoint are concrete
- the applicable member/object/environment/system route or intentional hold is
  connected to the camera route
- source audio/cue map linkage is present or readiness is `hold`
- one-image boards carry `one_image_board_reason` with a sufficient
  temporal route
- no internal graph-engineering labels or retired skill labels leak into generator text
- relevant abstract intent is preserved and accompanied by visible proof rather
  than left as an unexecutable placeholder
- cinematic-realistic fantasy material stays framed as filmed set plus
  post-production composite, not concept art, anime, game art, 3D render, or
  glossy AI-art drift
- the manifest prompt and any upload-ready copy preserve the same semantic bridge
- generator prose is not an inventory of appearance attributes already proven
  by the source image
- generator prose carries the canonical subject-motion route, camera-motion
  route, start view, start trigger, pacing, endpoint, and edit handoff

Record one integrated section judgment and concrete findings only where a
cue needs revision. After all sections, a separate whole-timeline review
judges recurrence, continuity, pacing, camera progression, and ending carry.
Validators confirm that those reviews cover the current manifest hash; they do not
recreate the judgment with word length, keyword, token, or similarity rules.

When the Founder directly rewrites or locks exact 03V prompt fields after this
v6 contextual baseline has passed, do not run the section and whole-timeline
creative review again merely to obtain another opinion. Preserve the baseline
QA and baseline manifest bytes, then write
`idol_video_prompt_section_qa.v6` with a provider-neutral
`creative_development_director` review owner and immutable `director_deep`
provider-capability snapshot with `automatic_fallback: none`:

- `review_mode: founder_direct_delta`;
- the exact current manifest path/hash and affected section/cue ids;
- the hash-bound passed v6 contextual QA and its baseline manifest;
- the integrated `idol-founder-intervention-receipt.v2`, including each changed
  YAML/JSON pointer and value hash;
- explicit carry-forward of unaffected baseline scope; and
- the required affected-cue rerun followed by hash-bound playback QA.

The Founder may make that decision from a single-section, multi-section, or
whole-video workbench cycle. The v6 delta may therefore list one, several, or
all affected sections, but materialization and reruns remain section-owned and
only disjoint section jobs may execute in bounded parallel.

This is not permission to edit arbitrary downstream text in place. The receipt
must name `video_prompt_revision` / `video_prompt_03v`, preserve source-image
order, identity/reference locks, unchanged prompts and boundaries, and pass
schema/hash, safety, feasibility, and applicable approval checks. A detected
objective conflict holds the affected scope; an LLM aesthetic preference does
not override the named Founder-authored change.

## Active Storyboard-Assisted Route

Read `storyboard-assisted-branch-cuts.md` for the active 03V board grammar. One
to three passed `official_core|branch` Production Cut images form a board and become the original screen
anchors after the derived storyboard board. Never treat the three-image board
limit as a section, Core-Cut, Branch-Cut, or film cap. Same-parent Core is the
default; cross-Core requires both Core IDs and a continuity reason. Default
execution uses one passed Production Cut frame with `image_to_video`.
`reference_to_video` requires Founder-selected exact image IDs/order. Only
6/10 seconds and 480p/720p are allowed; same-job CDD-passed 480p playback is
required before a 720p candidate, and requested/observed mismatch is HOLD.

## Manual Upload Queue

When a prompt set is intended for founder/operator upload to Grok, Runway,
Kling, Sora, or another external video generator, create or refresh one flat
`upload-ready/` queue under the package root.

Required shape:

```text
upload-ready/
  README.md
  UPLOAD_READY_INDEX.csv
  001_S00_PACKET_ID/
    prompt.txt
    image1.png   # storyboard board
    image2.png   # first original
    image3.png   # second original, when present
    image4.png   # third original, when present
```

`upload-ready/` remains the authoring/review surface and may include the
storyboard board followed by all actual originals. It is not automatically the
provider execution input set. For Grok execution, derive one cue-scoped
`execution-ready/` package with `scripts/idol_media_execution_adapter.rb`:

```text
ruby scripts/idol_media_execution_adapter.rb video \
  RUN/03V-video-prompt-manifest-v8.yaml --cue-id CUE_ID --dry-run \
  --write-package \
  --package-root RUN/generations/video-prompts/execution-ready
```

That package contains unchanged `prompt.txt`, `package-plan.json`, and only
the selected tool's exact inputs: one passed Production Cut for
`image_to_video`, or the Founder-selected ordered two-to-three passed cuts for
`reference_to_video`. Never pass the storyboard board merely because it exists
in `upload-ready/`. A package marked `prepared_with_holds` is organization
only; it cannot be submitted until every listed provider/manifest/section/
Founder-authority HOLD is closed. Name the downloaded clip `CUE_ID.mp4` (or an
allowed video extension with the same stem), then use the registered 03V clip
importer, intake, and CDD playback review. File presence is never playback PASS.
