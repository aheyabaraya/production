# IDOL Storyboard Layout Profiles

Legacy diagnostic reference for retired triptych/review-board layouts. Active
v1.6 image generation does not use storyboard boards, triptychs, top-left label
blocks, visible CUT labels, or model-rendered contact sheets.

The active exception is founder-approved beat-as-clip source generation. Solo
beats use the two-cut source sheet mode below. Paired, group-dance, or formation
beats use a separate single-cut 16:9 source image and do not use the two-cut crop
coordinates. Neither route may render labels, captions, support panels,
reference strips, or contact-sheet UI.

Use this reference only when the founder explicitly requests a legacy
storyboard-board diagnostic or when validating archived v1.4 packets. It defines
layout shape only. It does not choose the song, members, wardrobe, choreography,
camera route, or MV world.

## Source Precedent

This profile adapts a useful older storyboard test-flow correction, with the
visible reference strip now retired:

```text
CUT01 / CUT02 / CUT03 are the only visible image panels.
ACTION / CAMERA stays in metadata, not as a rendered support panel.
Face-only reference images are attached API identity inputs only. Do not render
them as a right reference strip, visible thumbnails, wardrobe swatches,
background swatches, identity checklists, or support panels. When using cropped
face assets, preserve identity while matching the generated scene lighting
direction, exposure, color temperature, shadow softness, skin tone continuity,
neck/shoulder connection, perspective, and scale. Do not paste a head/cutout
onto the generated body.
```

Do not import old source names, candidate banks, or legacy readability fields.

## Active Beat-As-Clip Two-Cut Sheet

Use this mode only when the founder approves one solo beat image as a video clip
source. It remains one API request per 02A beat; the model returns a single clean
source sheet, and Codex crops the two frames locally.

```yaml
layout_profile_id: idol_two_cut_16x9_stack
aspect_ratio: "8:9"
size: "1280x1440"
fixed_canvas:
  width: 1280
  height: 1440
cut_regions:
  CUT01_START:
    x: 0
    y: 0
    width: 1280
    height: 720
    aspect_ratio: "16:9"
  CUT02_END:
    x: 0
    y: 720
    width: 1280
    height: 720
    aspect_ratio: "16:9"
```

Visible rules:

- top frame is the beat start pose; bottom frame is the beat end pose
- no visible frame labels, numbers, captions, UI, logos, reference panels, or
  readable text
- a thin plain divider is acceptable only when both halves remain clean crops
- each half must work as a standalone `1280x720` MV still
- prompts should use start pose, end pose, final hold, hit, or stop language;
  avoid `land` / `landing` wording unless the literal subject is an aircraft or
  place

Framing rules:

- solo beats default to medium, close-medium, or three-quarter
  performance framing unless a wide body route is explicitly required
- paired, group-dance, and formation beats route to separate single-cut 16:9
  source images; use wide or medium-wide only for spacing, floor marks, foot
  route, and synchronized body-level proof
- after the formation is readable, keep some group beats closer through medium
  group frames, center-led three-quarter frames, or detail inserts
- low camera angles must guard against below-boot-height distortion, stretched
  legs, crouch, kneel, and lunge unless the beat explicitly asks for that body
  level
- wardrobe locks should block accidental office suiting, collared white office
  shirts, bare-leg skirts, generic runway fashion, and unrelated glamour styling

## Active Multi-Member Single-Cut Image

Use this mode for any beat with two or more declared members. It remains one API
request per 02A beat; the model returns one clean 16:9 source image.

```yaml
layout_profile_id: idol_single_cut_multi_16x9
aspect_ratio: "16:9"
size: "1280x720"
fixed_canvas:
  width: 1280
  height: 720
```

Visible rules:

- one clean MV still only; no start/end split
- no visible frame labels, numbers, captions, UI, logos, reference panels, or
  readable text
- no local crop step
- camera is only as wide as needed to read spacing, foot route, floor marks,
  synchronized body levels, and center energy

## Post-Review Cut-Coordinate Board Exception

This exception applies only when passed Branch-Cut images are assembled into a
post-review storyboard board for 03V or edit use. It does not authorize a second
image truth, a replacement 02B prompt, or legacy board generation.

For post-review replacement sources, use a run-owned cut-coordinate storyboard
board instead:

- Assemble a storyboard-style Branch-Cut panel board. Each panel uses one
  already passed Branch-Cut image and should preserve a clean `16:9` master
  crop.
- If one Core Cut needs several views, phases, responses, inserts, or spatial
  consequences to read, author distinct Branch Cuts in 02A. If the governing
  event changes, return upstream for a new Major; do not invent a third Core on
  the same event. Do not manufacture start/end frames or
  generate extra board-only images. Contact sheets are review assemblies only
  and are not video-generation source images.
- Do not include `FACE PHOTO`, `WARDROBE`, `BACKGROUND`, right reference strip,
  or any support panels in the visible board.
- Name only the intended member or center.
- Lock each Branch Cut with time target, main action coordinates, crop-safe center
  corridor, camera movement, and edit endpoint.
- Keep critical gesture/action inside the crop-safe center so the edit can use
  wide, square, or vertical crops.
- Face-only is the sole approved facial-identity source during member-visual
  construction. After the current-title card passes, there is no separate raw
  face-only input route; any member visual already bound to the passed Branch
  Cut remains an appearance-continuity input only and must
  not appear as a visible inset or support panel.
- Add high-quality/proportion guards to prompts in this mode: high quality,
  detail high, clean anatomy, natural elegant idol proportions, readable hands
  and feet, and no broken hands, extra fingers, warped feet, twisted limbs,
  melted faces, distorted proportions, or awkward idle poses.

## Legacy Profile

`idol_3_2_cutmain_support_band` is the legacy review-board profile.

```yaml
layout_profile_id: idol_3_2_cutmain_support_band
aspect_ratio: "3:2"
size: "1536x1024"
main_panels:
  - CUT01
  - CUT02
  - CUT03
support_panels: []
```

Fixed coordinate wrappers:

`mv_wide_triptych` is for MV, world, object, gaze, close signal, and memory
beats where cinematic width matters more than full-body readability. It should feel
dense and image-led; do not waste the board on large blank gutters.

```text
Canvas: 3:2 horizontal, 1536x1024.
Header band: x=0 y=0 w=100 h=8.
Variant: mv_wide_triptych.
Main CUT region: x=1 y=10 w=98 h=84.
CUT01 image: x=1 y=10 w=32 h=84.
CUT02 image: x=34 y=10 w=32 h=84.
CUT03 image: x=67 y=10 w=32 h=84.
No right reference strip. No FACE/WARDROBE/BACKGROUND support panels.
```

`identity_motion_triptych` is a review-board layout for beats where member
recognizability, gaze, expression, and upper-body action are the main review
problem. Use it for MV identity/motion moments that need larger faces or
upper-body framing. Do not use it to validate full-body choreography, footwork,
spacing, formation, weight transfer, or pose endpoint; those beats should use
`performance_portrait_triptych`.

```text
Canvas: 3:2 horizontal, 1536x1024.
Header band: x=0 y=0 w=100 h=8.
Variant: identity_motion_triptych.
Main CUT region: x=1 y=10 w=98 h=84.
CUT01 image: x=1 y=10 w=32 h=84.
CUT02 image: x=34 y=10 w=32 h=84.
CUT03 image: x=67 y=10 w=32 h=84.
CUT labels: visible inside the top-left of each CUT only.
No right reference strip. No FACE/WARDROBE/BACKGROUND support panels.
```

`performance_portrait_triptych` is for route, choreography, stage-motion,
paired hook, full-body, and formation beats where the body line, hands, feet,
spacing, and pose endpoint must stay readable. This is the default for idol MV
beats that prove dance inside an MV world.
The word `portrait` in this legacy variant name means portrait-oriented panel
geometry inside the 3:2 board. It does not mean face portrait framing. Shot scale
still follows the beat's must-show body/camera readability details.

```text
Canvas: 3:2 horizontal, 1536x1024.
Header band: x=0 y=0 w=100 h=8.
Variant: performance_portrait_triptych.
Main CUT region: x=1 y=10 w=98 h=84.
CUT01 image: x=1 y=10 w=32 h=84.
CUT02 image: x=34 y=10 w=32 h=84.
CUT03 image: x=67 y=10 w=32 h=84.
CUT labels: visible inside the top-left of each CUT only.
No right reference strip. No FACE/WARDROBE/BACKGROUND support panels.
```

Layout contract:

- The top-left label block names only the short packet number, section label,
  source timecode, and visible AURORA-M member codes/names.
- The horizontal coordinate wrapper and declared variant are mandatory. Do not
  improvise panel positions, add extra support areas, add bottom-right technical panels,
  or switch to a vertical board.
- `mv_wide_triptych` should use a dark or neutral production-board background and
  tight gutters so blank background does not compete with the CUT panels.
- CUT01, CUT02, and CUT03 sit as the large visual triptych.
- CUT01, CUT02, and CUT03 are the only main visual panels.
- CUT01, CUT02, and CUT03 carry the beat action, camera route, body route,
  gaze/object response, or memory transition.
- CUT01, CUT02, and CUT03 must vary camera angle, shot scale, or composition
  enough to give the edit usable options while preserving one
  continuous action chain. Do not repeat the same flat angle three times unless
  the beat intentionally requires a hold.
- Do not render ACTION / CAMERA sentences on the board. Action and camera stay
  in YAML/export metadata and guide the CUT image content only.
- `identity_motion_triptych` renders no ACTION / CAMERA sentence on the board.
  Its CUTs must show one wide/context action and two larger face, gaze, or
  upper-body action moments.
- `performance_portrait_triptych` renders no ACTION / CAMERA sentence on the
  board. Action and camera stay in YAML/export metadata and guide the image
  content only.
- Do not split action/camera direction into separate visible fields, bullet
  notes, fragments, or paragraphs.
- No right reference strip, visible face reference panel, wardrobe swatch,
  background swatch, support panel, identity note, status label, checklist, or
  long text is rendered.
- Attach the local face-only asset(s) from `identity_lock.member_references` as
  image inputs for identity invariants.
- Face-only crops are input references only. Do not redraw, stylize, relight, or
  paste the crop as a panel. The generated face must match the scene lighting
  direction, exposure, color temperature, highlight level, and shadow softness.
- One-member boards attach one face reference. Two-member boards attach two
  unique face references. Do not duplicate a face reference to fill space.
- Face references are identity anchors only. They are not extra generated
  members, visible review photos, or large portrait panels.
- Visible text is minimal. Boards may show top-left short packet number, section
  label, source timecode, and member codes/names only. Each CUT label appears in
  the top-left corner inside its own panel. Put
  action, camera, wardrobe notes, sound/SFX notes, checklists, and long descriptions in
  YAML/export metadata, not inside the rendered board.
- The common render guard must travel in the canonical prompt with literal
  `4K`, `high quality`, and `high detail`; API quality is always `high`:
  cinematic idol MV rendering, clean
  anatomy, natural elegant idol proportions, readable hands/fingers/feet,
  grounded weight, coherent lighting direction, controlled exposure, consistent
  color temperature, soft realistic shadows, and negative guards against warped
  limbs, extra fingers, broken hands, pasted-face lighting, and distorted
  proportions.
- Do not create a separate key frame, key art, poster frame, or dominant main
  panel.
- Do not show more than two visible generated performers in one board.

## Motion Emphasis

The active profile stays `3:2`. `render_prompt_mode` uses the validator enum
names from `idol-imagegen-validation-contract.md`; the names below are
`layout_variant` families only:

- `mv_wide_triptych`: close signal, MV world, object, gaze, memory, and
  cinematic route beats that need width without losing member readability
- `identity_motion_triptych`: face, gaze, upper-body hook, and identity-motion
  beats where recognizability matters more than full-body route readability
- `performance_portrait_triptych`: route, choreography, stage-motion, paired
  hook, full-body, and formation beats that need body-line readability; this is
  also the default when an idol MV beat is mainly dance inside an MV world
- still moments are allowed only after arrival, settling, or memory cause is
  visible in CUT01, CUT02, and CUT03

## Inactive Layouts

Do not use 9:16 or vertical-motion layouts in the current graph-engineering pass. Keep
`3:2` / `1536x1024` until the founder explicitly unlocks another review-board
profile.
