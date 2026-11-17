# Active 03V Core/Branch Motion Storyboard Detail

This is the standard 03V authoring route. It is provider-neutral and begins
only after exact Production Cut pixels pass review.

## Source Set

- Each board binds one to three ordered passed Production Cut originals.
- Allowed types are `official_core` and `branch`.
- Every source keeps Cut ID/type, parent Core ID, exact path/SHA-256, passed
  pixel-review receipt, observable state, unique state role, and membership
  in the 02A full-storyboard `collected_image_camera_angle_review`.
- Distinct collected images on one board must have unique Cut IDs and unique
  pixel SHA-256 values. The same exact-carried image is not a new image.
- Camera-angle diversity is judged on the full planning/production
  storyboard collection, not only this 1--3 packet and not only neighbors.
  Scripts check review completeness and exact bindings; they do not infer
  uniqueness from labels or families. 03V cannot treat 02A planning
  `generated_pixel_closure` as generated-pixel closure; the section
  generated review must rebind actual passed hashes.
- Include an Official Core when it owns a unique start, transition, or arrival
  state. Do not duplicate it when a Branch already owns the same state or the
  same camera angle.
- More than three necessary states split into ordered linked boards. Linked
  boards of one coherent cue must not hide a repeated camera angle.
- One image is normal when it is a sufficient motion anchor and the author
  records the reason and temporal-route sufficiency. Angle diversity is
  not_applicable on a one-image board.
- Five Sequence Unit frames remain evidence. They are not five board images.

## Storyline And Sequence Binding

Every board exact-binds one active storyline passage, selected Major Sequence
Composition, selected one-second Sequence Unit IDs, and detailed flow-reading
hash. The author then reads the selected Core reference and each Core/Branch
screen job before writing the motion derivation. An image alone is not the
creative source of a generic move.

Same-parent Core is the default. Cross-Core is allowed only when the board
names distinct `from_core_cut_id` and `to_core_cut_id` plus an observable
continuity reason.

## Attachment Grammar And Pixel Authority

```text
@image1 Motion Storyboard composite
@image2 first ordered Production Cut original
@image3 second ordered Production Cut original, when present
@image4 third ordered Production Cut original, when present
```

The composite controls order, timing, blocking, subject route, and temporal
camera map for authoring/review. Originals control exact pixels, identity,
style, light, still composition, crop, and visible states. Board labels,
arrows, borders, padding, or grid guides never appear in generated video. If a
grid guide exists, it is non-visual alignment evidence only.

## Motion Authoring

Author from the exact first pixel state:

- observable subject/object/environment motion or intentional hold;
- one motivated camera route, direction, speed, and envelope;
- depth/parallax/focus change;
- stop trigger and landing/reveal;
- previous/next continuity and edit handoff.

Do not repeat an appearance catalogue already owned by passed pixels. Recover
only a named observed drift attribute. Do not invent an intermediate state or
choreography to fill a panel.

## Execution Boundary

The board is authoring/review evidence. Default `image_to_video` uses one
selected passed Production Cut still as frame 1. Multiple actual originals are
passed to `reference_to_video` only with a Founder-authored exact image-ID/order
selection. The exact passed 03V prompt is forwarded without rewrite. That execution
prompt may name only attached execution slots; a prompt that names an
unattached `@image` slot is HOLD, not a silent rewrite. Duration
is 6 or 10 seconds; resolution is 480p or 720p only; fallback is none.

Run the 480p test first. Only a CDD-passed playback for the same `video_job_id`
opens a 720p candidate. Requested/observed resolution mismatch is HOLD. A 720p
candidate is reviewed again and never inherits creative PASS from 480p.

Return every board, playback result, or HOLD to the owning V-Ci Section-Cluster
CDD after the verified Graph v2 switch, or the pinned legacy CDD before it. 04
opens separately only after passed 03V playback.
