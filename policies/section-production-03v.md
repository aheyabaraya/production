# IDOL Section Production: 03V Storyboard And Motion

Status: active
Authority: `AGENTS.md` first, then `policies/section-production.md`, then this
chapter, the active owning schema, and the complete owning skill
Activation: load only when the current skill-load checkpoint binds this file.
Read it to EOF. Do not load it from an unrelated stage.

## 03V Storyboard And Motion

03V begins only after passed Production Cut pixels, validated Branch local
upscales where applicable, and ready Audio Production-Cut Placement. It first
exact-projects and reads the complete
PRE-00-rooted full-storyline lineage from 02A; subject and camera motion expand
the active full text and cannot replace it with the whole-film spine. One to
three ordered placement images from passed Production Cuts of type
`official_core` or `branch` form one Motion Storyboard board when they belong to
one coherent motion cue. An Official Core uses its unchanged passed original;
a Branch uses its receipt-bound local upscale. More than three necessary
screens split into linked boards. A one-image board is a normal route when that
Production Cut is a sufficient motion anchor; it records why one anchor is enough
and the subject/environment/camera route 03V must author from it. It is not
restricted to a static hold or insert.

Every distinct generated production image collected on the planning/production
storyboard — Official Core primaries and generated Branch stills, not only
the 1--3 images on one 03V packet — must have a meaningfully different
camera angle from every other distinct image in that full collection.
Compare the complete unordered set of distinct images, including
non-adjacent and cross-packet pairs. Camera angle is the facing-and-pitch
relation (`direction_angle` / Core `camera_angle`); it is not shot size, not
height-only, not a label, not a random rotation, and not a numerical
similarity score. Height and pitch stay distinct. The same exact-carried
image is not a new image: a repeated `production_cut_id` or repeated pixel
SHA-256 cannot count as a second image. A one-image 03V packet does not
narrow the full-storyboard duty. Preserve the protected action axis, screen
direction, identity, and feasible movement. 03V does not invent a new still
angle. If the full collection shares an angle, HOLD and return to 01, 02A,
or 02B. An explicit Founder lock that requires a conflicting repeat is an
exact-bound HOLD naming the lock source, pointer, value SHA, and exact
images; a fabricated lock id is unbound. Linked 03V boards of one coherent
cue must not hide a repeated angle by splitting. Sequence Units remain
exact-five one-second evidence; they are not extra Production Cuts. Actual
pixels require model-authored contextual visual review of the full
collection. Scripts validate exact image/source/review bindings, pair
completeness, and declared outcomes only; they never infer sameness or
uniqueness from labels, families, text inequality, hashes, or numeric
angles. 03V and G3 cannot treat the 02A planning
`collected_image_camera_angle_review` as generated-pixel closure.
Generated-pixel closure is the section
`collected_image_camera_angle_pixel_review` after actual passed 02B
image hashes exist for that section. A section worker does not author
other sections. Incomplete bindings remain HOLD until those hashes are
present.

The attachment grammar is fixed:

```text
@image1 = storyboard board
@image2 = first original passed Production Cut image
@image3 = second original passed Production Cut image
@image4 = third original passed Production Cut image
```

Only existing slots are named. The board controls timing, blocking, subject
route, and temporal camera motion. Original Production Cut images control
pixels, appearance, wardrobe, light, composition, and visible states.
Same-parent boards are default; a cross-Core transition names the reason and
continuity edge. The authoring board may contain one to three passed images,
but default I2V execution uses one passed Production Cut. Multiple-reference
execution uses `reference_to_video` only after an exact Founder selection.
Registered Grok media accepts only 6 or 10 seconds and 480p or 720p; 1080p
requests and observed-resolution mismatch hold. CDD reviews a 480p test before
the same job may proceed to a 720p candidate.

03V authors temporal camera movement only after inspecting actual pixels and
the upstream motion-readiness/continuity conditions: movement or locked hold,
direction, rig character when useful, speed, envelope, motivation, depth or
parallax change, reveal/stop trigger, readability protection, and edit handoff.
An upstream motion hypothesis is not a lock. If the passed pixels cannot support
it without inventing unseen space, breaking the protected axis, unsafe cropping,
or changing a passed state, 03V chooses another evidence-supported route or
returns to the smallest owning stage. A one-image board uses the same attachment
grammar and an authored single-anchor reason.

Choreography is present only where Front Planning/01 marks `primary` or
`supporting`, with a bound actual choreography, performance, or fancam source.
Never invent generic dance.

The same one-section `section_image_motion_worker / worker_high` remains the
only 03V board, prompt, and clip writer. After G-40, that section returns to
the same Section-Cluster CDD cohort that closed its 02B pixel review. The
cohort CDD is the integrated motion/playback reviewer, never a second writer.
Overall alone promotes the reviewed cohort milestone to Edit Director.

### Same-Cohort CDD Succession

Keep the logical `CDD-V-Ci` / `section_cluster_cdd_c1..cn` owner from 02B pixel
review through 03V playback. Continue through the registered successor CAS
when a new physical session is required:

```text
CDD-V-Ci image review -> same CDD-V-Ci motion/playback successor
```

One logical cohort lane permits one physical primary and one physical
successor per stage. A successor requires an immutable checkpoint, compact
successor pack, zero-turn preflight, native Goal admission, exact
`frontier_director` profile and read validation, and lane-local single-writer
CAS. The source becomes read-only only after CAS. Compatibility alias
`director_deep` remains a machine id only; it is not a downgrade or fallback.
If the successor cannot close playback, do not create a third CDD session.
Split unowned worker scope further or return the cohort HOLD to Overall.

The 03V successor pack carries only passed Production Cut pixels, selected
motion evidence, Motion Storyboard boards, audio cues, immediate neighbors,
frozen visual guardrails, open holds, and exact hashes. It does not reload raw
reference pools, 02B generation history, URL lists, worker transcripts, or
another cohort.

### Mandatory Motion Evidence And Temporal Ownership

Every material Major requires selected contiguous motion evidence: one
exact-five one-second Sequence Unit, or linked Units of the same event. A
broad contact sheet counts as zero. Locked-camera stills remain legal only
when the CDD inspected that contiguous range and recorded why a hold is
stronger than a move. Missing motion evidence is HOLD, not a still-only
shortcut.

03V owns temporal subject, environment, and camera motion after passed pixels
exist. From actual pixels, Sequence evidence, and the audio cue it authors:

- subject motion route;
- pose transition and landing;
- environment/object response;
- camera start view;
- movement family and direction, or an evidence-based locked hold;
- speed and envelope;
- depth, parallax, or focus change;
- reveal/stop trigger;
- edit handoff;
- readability protection.

02B stills are appearance, composition, and motion-ready geometry. 03V must
not overwrite those passed pixels, invent an unseen rear world, or treat an
upstream motion hypothesis as a lock. Bind the selected motion evidence by
source id, locator or Sequence id, and derivative path/hash. Do not put raw
URLs or the source pool into the 03V pack, prompt, or Director context.

Performance readability is evaluated only when `performance_mode` is
`supporting` or `primary` with a bound actual source. `performance_mode: none`
excludes that criterion entirely. Do not invent generic dance to fill it.

Anti-flat motion is contextual, not a mechanical quota:

- repeating the same temporal camera family (push, orbit, hold) is not an
  automatic fail of playback motion;
- that temporal-family rule does not waive the still-image camera-angle
  duty on distinct Production Cut images collected into one Motion
  Storyboard;
- unmotivated repetition of the same frontal medium, centered symmetry, slow
  push, or default orbit is HOLD;
- each section must change at least one of subject energy, camera energy,
  depth change, or landing form relative to the previous section;
- a long hold needs audio/story evidence for its length;
- do not require a cut every 2--3 seconds.

### 03V Motion 0-4 Review

The assigned model authors a 0--4 grade per applicable criterion against
actual playback and the bound Motion Storyboard. Scripts validate presence,
locator, and range only. They never author a grade or creative PASS. Averages
and totals are forbidden. Grade 4 is not automatic PASS.
The co-loaded Graph prose judgment additionally records observable playback
claim, screen consequence, preserve/change/do-not-infer boundary, correction
action, and acceptance evidence, then selects the next legal graph edge.
Graph v2 records this once with the `playback_03v` profile of
`idol_graph_contextual_judgment.v2`; do not reuse PRE-FP/FP planning or 02B
pixel criteria. `idol_03v_contextual_grade_vector.v1` remains compatibility
evidence for the still-active legacy writer and its historical reader; it is
not co-authored for a Graph review.

Criteria:

1. subject body/action/pose transition;
2. temporal camera route or evidence-based locked hold;
3. audio cue, trigger, landing, and edit handoff;
4. depth, parallax, occlusion, and reveal/stop;
5. neighbor and whole-section motion diversity;
6. identity, light, state, and geometry stability;
7. performance readability, only when `performance_mode != none`.

Entry to CDD promotion eligibility requires every applicable item `>= 3`,
subject motion or intentional-hold close `= 4`, temporal-camera route or
evidence-based locked hold `= 4`, and audio/edit landing `= 4`.
Static pose with no authored hold reason, camera-only motion that leaves the
subject dead, repeated orbit or default push, or an ungrounded hold cannot
PASS. Actual playback review is mandatory; a board or prompt without playback
cannot go to Edit Director.

Target empathy and message are PRE-FP locks. 03V does not rescore them. A
lock violation or a lock that never becomes visible motion, hold, or landing
is HOLD regardless of grade.

### Playback Correction And Section Handoff

Review 480p first. Only a CDD-passed 480p playback may open the same
`video_job_id` as a 720p candidate. Resolution increase is not creative PASS.
Observed-resolution mismatch is `resolution_fallback_hold`.

The cohort CDD reviews subject motion, pose transition, environment response,
temporal camera, speed/envelope, depth/parallax/focus, reveal/stop, landing,
edit handoff, identity stability, world stability, and actual playback rhythm
as one section result. It does not accept a motion-axis pass that makes the
section flat, unstable, or collaged with the passed stills.

The CDD returns one complete correction unit for every observed defect. The
section worker authors the corrected board, prompt, or clip in a new immutable
attempt for only those invalidated paths. Pixel defects return to the exact
02B image; still composition or visible-state defects return to 01 or 02A;
temporal subject/camera defects stay at 03V. A review cycle has at most three
total submissions; a third failure routes upstream or HOLD.

Passed 03V section packages return to Overall, then to Edit Director. Founder
G3 `section_playback` sees only internally reviewed section preview: actual
selected-audio playback, incoming/outgoing handles, reference- and audio-led
kinetic tendency or intentional hold as edited, and remaining material risk. Founder
does not inspect the raw reference loop or each I2V clip. A Founder HOLD
returns to the smallest owner.

The cohort return excludes raw pools, full URL lists, worker transcripts,
superseded prose, and other-cohort media. A structural PASS or worker claim is
never creative PASS.
