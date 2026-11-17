# CDD-P3-Ci Section/Kinetic Architecture

Activate one instance of this mode per hash-bound 2--3-section cohort only after
selected audio and provisional section boundaries exist. It owns planning-time
section and kinetic structure for that cohort, not temporal 03V authoring.

## Deterministic Cohort Construction

For two or more ordered sections, partition into contiguous cohorts of two or
three. Do not create extra cohorts to fill provider capacity. A one-section
title may use one explicit singleton. If an already approved story/audio
boundary makes a contiguous 2--3 split impossible, escalate to Founder; do not
invent a creative partition.

Use this remainder-first rule, which matches the required examples:

- `n % 3 == 0` -> all threes: 3, 6=3+3, 9=3+3+3;
- `n % 3 == 1` -> two twos, then threes: 4=2+2, 7=2+2+3, 10=2+2+3+3;
- `n % 3 == 2` -> one two, then threes: 2, 5=2+3, 8=2+3+3, 11=2+3+3+3.

Every section belongs to exactly one cohort. Read adjacent cohort boundary
handles; never write them.

## Own

- section screen jobs and whole-video progression for this cohort;
- Major event, exact-five one-second Sequence Unit, one-or-two Core marks, and
  later Branch coverage requirements;
- the change-point kinetic slot sheet for each Major (`angle` / `action` /
  `person` / `background` / authored hold), written as
  `<fp-stem>.kinetic-slots/<MJxx>.yaml` (`kinetic_change_point_slot_sheet.v1`),
  with Sequence as evidence, Core as 1--2 nails, remaining slots as Branch, and
  Key Screen inheriting Core-bound slot camera rather than re-authoring
  composition. Bind `section_id` to the selected-route section that owns the
  Major in `ordered_major_placements`. Bind `sequence_evidence.sequence_unit_ids`
  to that Major's selected Sequence Composition `typed_sequence_unit_ids` as an
  identifier exact-cover. Bind `key_screen_inheritances` to that Major's existing
  `key_screen_id` values. Those binds are identifier checks only. Do not invent
  ids. Return the sheets with the Decision Set to P1 exact-link; P1/Close lands
  them next to the v17 artifact. This is not a Founder form;
- still camera height, distance, direction, angle, depth, crop, and composition
  on Core-bound slots, using the camera coverage vocabulary loaded at this
  checkpoint;
- action/pose variation, motion readiness, transitions, and continuity handles;
- evidence-based 2--3 second kinetic change tendency and intentional long holds;
- Draft Keyframe Proof requirements before final 02B, reusing existing
  `fp_hero_core` as the noncanonical packet mode.

Do not create one event per section, one Core per time interval, or start/middle/
end Core dumps. A third Core requires a new governing event and therefore a new
Major. Sequence is the parent evidence; Core marks only the stills that must
remain.

## Major Motion Evidence

Every material Major requires real contiguous motion evidence: one exact-five
one-second Sequence Unit or linked Units of the same event. A broad contact
sheet counts as zero. If the Founder chooses a locked hold, still inspect the
contiguous interval and state why the hold is stronger than movement. Promotion
eligibility requires motion grade 4 and still-camera/composition grade 4, each
with an actual evidence locator. The 2--3 second tendency is a creative pacing
target, not a machine counter.

## Review

Check that story and audio produce observable state changes, distinct Major/Core
jobs, a change-point slot sheet whose neighbor slots declare a different axis
or an authored hold, useful motion landing, and non-flat transitions. Do not
treat “varied still geometry” as a substitute for that sheet. Longer holds need
song/story evidence; repeated frontal medium, default push, or orbit needs a
clear function.

Use P2's selected reference Decision Set as evidence. Do not reopen source
eligibility or author a replacement visual regime. Grade applicable
storyline/audio/kinetic/camera/coverage/non-duplication/feasibility criteria on
the 0--4 scale. All applicable items must be at least 3, and both motion and
still-camera/composition must be 4, before the Decision Set is eligible for P1
integration and Overall review.

Return section topology, Major/Sequence/Core pointers, boundary handles, motion-
readiness holds, Draft Keyframe Proof requirements, and the visible consequence
of every material choice only to P1 through `planning_cdd_p1_exact_link`. P1
exact-links the reviewed P3-Ci Decision Set and alone returns the integrated
Planning Cell milestone to Overall. At G-40, bind the exact
`section_cohort_id` so the matching production CDD can carry it through 02B
pixel and 03V playback review without silently repartitioning sections.
