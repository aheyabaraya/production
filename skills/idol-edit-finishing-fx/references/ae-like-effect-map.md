# AE-Like Effect Map

Use this reference when a 04 finishing pass needs After Effects-style motion
graphics or compositing without opening After Effects. Keep the AE term as a
source vocabulary label, then translate it into an IDOL-local visible job,
implementation family, and QC guard.

## Selection Rule

Start from the passed edit preview, not from an effect menu. Pick an AE-like
family only when the current cut has:

- a known output time range and source action marker
- an audio trigger such as onset, beat, lyric entrance, stop, or section handoff
- a visible basis such as body hit, gaze stop, object change, light sweep,
  camera stop, garment motion, screen flicker, reflection, or space transition
- a protection guard for face, hands, feet, body path, full space, tone, mobile
  readability, and flash/flicker safety

## Implementation Tiers

- `tier_0_current_renderer`: already expressible in the existing ffmpeg recipe
  effect list. Use first for short previews.
- `tier_1_ffmpeg_filter`: implement with ffmpeg filtergraph additions before
  final render. Good for grade, overlays, text, blur, glow-like blends, flashes,
  vignettes, noise, simple displacement, crop/zoom, and transitions.
- `tier_2_opencv_frame_pass`: implement with `scripts/idol-video-python` when
  the effect needs per-frame masks, optical-flow evidence, tracked points,
  custom particles, matte cleanup, or procedural geometry.
- `tier_3_asset_precomp`: pre-render a transparent overlay or image sequence
  with Python/PIL/MoviePy, then composite it with ffmpeg.
- `tier_4_analysis_only`: use local analysis to find or QC a moment, but do not
  render the AE feature locally.
- `tier_5_external_tool_required`: hold unless the founder explicitly approves
  After Effects, Blender, Resolve/Fusion, a paid model, or another external tool.

## Priority Families

| AE feature family | Local IDOL use | Implementation family | Use when | Hold/reject when |
| --- | --- | --- | --- | --- |
| Keyframes, easing, expressions | Beat-synced motion values: opacity pulse, zoom push, shake decay, glow rise/fall, text reveal | `tier_0_current_renderer`, `tier_1_ffmpeg_filter`, `tier_2_opencv_frame_pass` | The effect can be described as timed values around a real audio/source marker | The motion needs hand-drawn curves that cannot be previewed or QCed locally |
| Effects and presets | Exposure hit, color hit, blur, sharpen, noise/grain, glow-like layer blend, distortion, transition completion | `tier_0_current_renderer`, `tier_1_ffmpeg_filter` | A simple parameter curve makes the cut clearer | The effect stack would hide weak source or create one-effect drift |
| Adjustment layers | Section/chunk grade, bloom/glare, grain, vignette, shadow lift, source-family unification | `tier_1_ffmpeg_filter` | Multiple adjacent cuts need the same tone treatment | It changes member identity, wardrobe color truth, or world palette |
| Masks, mattes, alpha, track mattes | Reveal overlay inside a screen/object/door shape, isolate light pulse, confine grade to a region | `tier_1_ffmpeg_filter`, `tier_2_opencv_frame_pass`, `tier_3_asset_precomp` | Region is simple, stable, and visible enough to QC | Fine hair, fingers, fast body crossing, or face edges need true roto |
| Roto Brush/Object Matte | Foreground/background separation for selective effect, background replacement, object emphasis | `tier_2_opencv_frame_pass` for rough masks; `tier_4_analysis_only` or `tier_5_external_tool_required` for clean roto | A rough matte is only used for a soft light, shadow, or background pulse | Identity edges, hair, hands, or full-body separation must look production-clean |
| Keying | Green/solid-color removal, luminance screen extraction, light/fire/screen overlays | `tier_1_ffmpeg_filter`, `tier_2_opencv_frame_pass` | The source has a clean uniform color/luma basis or additive overlay | Uneven background, compression noise, or similar subject colors require roto |
| Motion tracking and stabilization | Attach glow/text/symbol to object path, screen insert, mild shake reduction, motion evidence for source hit | `tier_2_opencv_frame_pass`, `tier_4_analysis_only`; stabilization may be `tier_1_ffmpeg_filter` only when mild | Track point is high contrast and stays visible | Occlusion, motion blur, moving off-screen, or camera parallax needs Mocha/AE |
| 3D layers and cameras | 2.5D card push, parallax title/object, fake dolly, depth-of-field-like blur | `tier_1_ffmpeg_filter`, `tier_3_asset_precomp`; true camera solve is `tier_5_external_tool_required` | Flat layers or overlays can sell the move in a short window | Real 3D camera match, shadows, or geometry interaction is required |
| Text animation and MOGRT-like typography | Lyric/object word hit, title lower-third, warning/signal label, countdown, section marker | `tier_1_ffmpeg_filter`, `tier_3_asset_precomp` | Text is audible or visibly motivated and does not clutter mobile frame | Text decorates a frame without song/object trigger or covers face/body action |
| Shape layers and vector paths | Signal lines, circle targets, path strokes, object outline, UI trace, route map | `tier_1_ffmpeg_filter`, `tier_2_opencv_frame_pass`, `tier_3_asset_precomp` | Shape follows a visible object, screen, floor line, or music marker | Shape language becomes a generic UI overlay unrelated to the MV world |
| Particles, simulation, turbulence | Dust, sparks, light motes, rain streaks, data fragments, cloth/glass shimmer | `tier_3_asset_precomp`, limited `tier_1_ffmpeg_filter`; complex physics is `tier_5_external_tool_required` | Sparse overlay supports a world/object rule and leaves body readable | Dense particles hide choreography, face, hands, feet, or source quality |
| Time remap, freeze, speed ramp | Micro-freeze, rebound, impact hold, reverse/echo flash, short speed pulse | 04 edit recipe first; only then `tier_0_current_renderer` or `tier_1_ffmpeg_filter` | The edit timing is already passed and the effect reinforces a marker | It changes perceived cut timing; return to `idol-editing-qc` |
| Color correction/grading | Match mixed sources, remove flicker, hit chorus color accent, preserve palette | `tier_1_ffmpeg_filter` | It unifies sources or marks a real music transition | It invents a new palette outside 01A/track tone or crushes face/body detail |
| Content-aware fill/object removal | Remove small UI speck, logo-like artifact, or one-frame defect | `tier_2_opencv_frame_pass` for tiny static defects; otherwise `tier_5_external_tool_required` | The defect is small, static, and outside member/body action | Removal touches face, hair, hands, body, wardrobe edge, or moving background |

## Current Local Capability Snapshot

Use `scripts/idol-video-python --check` before media work. The current repo
video runtime supports ffmpeg/ffprobe plus Python `cv2`, `moviepy`, `PIL`,
`numpy`, `scipy`, `librosa`, `soundfile`, and `jsonschema`.

Primary type names and when-to-use guidance live in
`references/local-ffmpeg-transition-effect-catalog.md`. The FFmpeg renderer
`scripts/idol_video_ffmpeg_revise_render.py` now supports the catalog's
timeline-safe accents and boundary `xfade` family; compile 04FX records with
`scripts/idol_04fx_compile_recipe_effects.py`.
The executable type/parameter/transition contract is
`automation/edit-effect-registry.yaml`; prose lists are navigation aids.

`tier_0_current_renderer` includes at least:

- `flash`, `dip_flash`, `punch_zoom`, `zoom_hold`, `micro_freeze`
- `blur_pulse`, `horizontal_blur_whip`, `tmix_smear`, `unsharp_pulse`
- `brightness_pulse`, `color_pulse`, `contrast_pulse`, `saturation_pulse`
- `hue_pulse`, `temperature_pulse`, `eq_grade_window`
- `vignette_pulse`, `grain_pulse`
- `rgb_split`, `chromatic_shift`, `shake`, `edge_flash`
- `drawtext_hit`
- `fade_to_black`, `fade_from_black`, `fade_to_white`, `fade_from_white`
- `negate_flash`, `pixelize_pulse`
- `xfade` with local FFmpeg transition names (`fade`, `fadeblack`, wipes,
  slides, circles, etc.)

Treat still-unimplemented specialty paths (clean roto, true 3D camera solve,
dense particles) as `tier_2`/`tier_5`. MoviePy workbench still offers
`source_overlay` for experimental overlay cases.

Do not use bare `python3` for media processing. Use `scripts/idol-video-python`
so OpenCV and the video/audio packages resolve from `.venv-video`.

## FX Record Additions

When using this map, add these optional keys under `effect_design`:

```yaml
ae_like_family: "text_animation"
local_implementation_family: "tier_1_ffmpeg_filter"
renderer_status: "supported_now | needs_script_extension | analysis_only | external_tool_required"
parameters:
  start_seconds:
  duration_frames:
  intensity:
  blend_or_opacity:
  easing_or_curve:
  mask_or_region:
```

Keep `visible_action` and `endpoint` concrete. Bad: `premium AE motion`.
Good: `white floor reflection swells under the boot for 4 frames on the snare,
then fades before the face close-up begins`.

## Practical Build Order

1. After a passed 04 edit preview, run the 04FX transition opportunity audit
   from `local-ffmpeg-transition-effect-catalog.md` before final master.
2. Use `tier_0` catalog accents first (`dip_flash` defaults at section gates,
   hit-only `punch_zoom`/`flash`, short blur/color/grain pulses, optional
   `xfade` when grammar justifies it).
3. Add `tier_1` specialty filters only when the cut asks: `drawtext` hits,
   shaped reveals, glow-like overlays, light sweeps.
4. Add `tier_3` overlay precomp support: transparent PNG/video overlays for
   particles, symbols, signal lines, and typography sequences.
5. Add `tier_2` OpenCV passes only after a real run needs tracking, matte, or
   per-frame procedural motion. Keep outputs as preview evidence and QC them
   before final inclusion.
6. Mark `tier_5` when the requested feature depends on AE/Mocha/Roto Brush,
   clean AI object matte, true 3D camera solve, production-grade object
   removal, or plugin simulation.

## Source Notes

The feature families in this map are grounded in Adobe's After Effects user
guide categories: text and motion graphics, masks/mattes, tracking and
stabilization, roto/object matte, keying, color correction, effects/presets,
expressions, time remapping, and 3D layers/cameras.
