# Local FFmpeg Transition & Finishing Effect Catalog

04FX-only catalog. This does **not** change 04 cut ownership
(`source_in` / `source_out` / speed / candidate / geometry / cut order).

Use this file when:

- a section or chunk edit preview has already passed
- founder says the edit feels awkward, thin, hard, cheap, or unfinished
- final pre-master quality check needs a transition/finishing opportunity pass
- an effect must be mapped to a local FFmpeg implementation

For rich professional examples, founder-phrase routing, and copyable sketches,
also read `professional-edit-effect-casebook.md`.
Renderer entry points:

- machine contract: `automation/edit-effect-registry.yaml`
- recipe `effects[]` consumed by `scripts/idol_video_ffmpeg_revise_render.py`
- optional compile from a 04FX map via `scripts/idol_04fx_compile_recipe_effects.py`

Local FFmpeg already includes these filters. Do not treat missing install as
the blocker; the blocker is only whether 04FX recorded and previewed the job.

## Hard Rules

1. Cut truth stays in the 04 recipe. 04FX may only add finishing realization.
2. If an effect makes timing feel early/late, return to `idol-editing-qc`.
3. Never use dissolve / wipe / flash as a default fill for a weak cut.
4. Prefer timeline-safe single-stream accents first.
5. Final `xfade` is legal only through a 04-owned duration-preserving boundary
   handle ref. Missing/insufficient handles, duplicate boundary transitions, or
   any program-frame change fail before final render. Legacy shortening is
   preview-only evidence.
6. Every applied effect needs a visible job, audio/source trigger, protection
   guard, and pass/hold/reject after preview.

## Founder Awkwardness → Transition Playbook

When founder feedback is roughly “어색하다 / 부족하다 / 딱딱하다 / 허전하다 /
전환이 없다 / 프로 느낌이 아니다”, do **not** reopen source hunting first.
Run this 04FX diagnosis in order:

| Founder signal | Likely cause | Prefer first | Avoid |
|---|---|---|---|
| 컷이 너무 딱딱하다 / hard | Boundary has no musical accent | `dip_flash`, short `blur_pulse`, tiny `punch_zoom` | long dissolve |
| 장면이 덜 넘어간다 | Section/world handoff weak | `fadeblack`/`fadewhite` 2–4f, soft `xfade=fade` only with handles or accepted shorten | wipe spam |
| 임팩트가 안 산다 | Hit frame not marked | `flash`, `punch_zoom`, `micro_freeze`, `shake` | full-screen flash every bar |
| 소스가 서로 다른 영상 같다 | Tone family jump | section `grade` / `color_pulse` unify, `grain_pulse`, light `vignette_pulse` | rainbow hue swings |
| 박자는 맞는데 허전하다 | Missing micro accent | `brightness_pulse`, `saturation_pulse`, `rgb_split` 1–2f | decorative text |
| 멤버/안무가 안 읽힌다 | Effect covering action | reduce opacity/duration or `reject`; reinforce with `micro_freeze` only on clean hit | blur/pixelize on face |
| 코러스 진입이 약하다 | Section gate under-sold | slightly stronger accent at gate only | effect demo through whole chorus |
| 전환이 싸 보인다 | Wrong family or too long | shorter duration, lower opacity, match direction to camera/body | CapCut preset tourism |

### Default response recipe (safe)

Unless the track tone forbids accents, after a passed edit preview:

1. Build a **transition opportunity audit** for every section boundary and every
   strong onset/lyric gate inside the passed window.
2. Auto-propose **safe defaults** only where the cut is already correct:
   - section entry/exit: `dip_flash` 3–4 frames @ opacity 0.18–0.28
   - hard body/camera hit on a real onset: optional `punch_zoom` 2–3 frames @ 1.03–1.05
   - true black/white musical stop: optional `fade_to_black` / `fade_to_white` 2–4 frames
3. Leave artistic wipes/slides/pixelize as **manual propose**, not auto-default.
4. Preview each changed window before final include.

Safe defaults are defaults for **proposal**, not automatic final pass.

## Effect Families And When To Use

### A. Timeline-safe single-stream accents (prefer)

These apply on the already-concatenated program timeline. They do not change
cut order and usually preserve duration.

| `effect_type` | FFmpeg core | Use when | Default-safe? | Typical duration | Notes |
|---|---|---|---|---|---|
| `flash` | `drawbox` white fill | snare/hit, camera stop, lyric punch | no (too hot as default) | 2–4f | Keep opacity ≤0.55; flash-safety QC required |
| `dip_flash` | `drawbox` black fill | section handoff, soft gate, “hard cut feels naked” | **yes** at section boundaries | 3–5f | Best default bridge accent |
| `punch_zoom` | timed `scale`+`crop` | body hit, drop, hand stop | conditional yes on clear hits | 2–4f | factor 1.03–1.06; protect face center |
| `zoom_hold` | timed `scale`+`crop` hold look | slightly longer push than punch | conditional | 3–6f | Same face-center guard |
| `micro_freeze` | duration-preserving frame replacement | perfect hit frame needs one more read | conditional | 1–3f | Perceptual timing risk; return to 04 if the landing shifts |
| `blur_pulse` | `gblur` enable window | whip energy, hide micro judder at cut | conditional | 2–4f | Do not blur faces on hero close-ups |
| `horizontal_blur_whip` | stronger `gblur` | directional whip / speed bridge | no as default | 2–4f | Prefer when motion already streaks |
| `tmix_smear` | `tmix` | motion smear on impact | no as default | 2–4f | Easy to dirty choreography |
| `unsharp_pulse` | `unsharp` enable window | make a clean hit crisper | rare | 2–3f | Easy to look processed; low amounts only |
| `brightness_pulse` | `eq` brightness | light hit without full flash | **yes** low | 2–4f | brightness 0.04–0.10 |
| `color_pulse` | `eq` contrast/saturation | chorus color lift, source unify micro | conditional | 3–6f | Stay inside track palette |
| `contrast_pulse` | `eq` contrast | punch without color shift | conditional | 2–4f | |
| `saturation_pulse` | `eq` saturation | emotion spike, object color pop | conditional | 2–4f | Avoid skin oversat |
| `hue_pulse` | `hue` | world-color accent only | no as default | 2–4f | Avoid skin cast |
| `temperature_pulse` | `colortemperature` | warm/cool gate | conditional | 3–6f | Keep mild kelvin shifts |
| `eq_grade_window` | multi `eq` | short grade glue window | conditional | 4–12f | Prefer section `grade` for long glue |
| `vignette_pulse` | darken/gamma approx | focus inward, stage darkening | conditional | 4–8f | Good for ending holds |
| `grain_pulse` | `noise` | glue mixed sources, film texture | conditional | section-length ok if subtle | Prefer mild; not a dirt layer |
| `rgb_split` | `rgbashift` | glitch/digital world hit | no as default | 1–3f | Only if world grammar allows |
| `chromatic_shift` | `chromashift` | colder digital edge | no as default | 1–3f | Same guard as rgb_split |
| `shake` | `crop` jitter enable | impact shock | no as default | 2–4f | Keep small; motion-sickness risk |
| `edge_flash` | `edgedetect` | system/line-art hit | no as default | 1–3f | Not for beauty close-ups |
| `drawtext_hit` | `drawtext` | audible lyric/object word only | no as default | 4–12f | Never decorate over face action |
| `fade_to_black` | black `drawbox` ramp-ish window | musical stop, hard reset out | conditional | 2–6f | Not a substitute for missing next source |
| `fade_from_black` | black overlay ending | section enter from void | conditional | 2–6f | |
| `fade_to_white` | white overlay | blow-out hit, dream cut out | rare | 2–4f | Flash-safety |
| `fade_from_white` | white overlay | enter after blow-out | rare | 2–4f | |
| `negate_flash` | `negate` enable | experimental invert hit | no | 1–2f | Almost never for idol face hero |
| `pixelize_pulse` | `pixelize` | system corrupt / UI world only | no | 2–4f | Never on face identity |

### B. Boundary transitions (`xfade`) — use sparingly

These join two adjacent recipe segments with FFmpeg `xfade`.
Local FFmpeg exposes the full transition list below.

**Timeline contract:** new/final work references one 04-owned boundary handle.
The outgoing tail and incoming head are extended around one fixed program cut;
the overlap consumes exactly those added handle frames, so total program frames
remain unchanged.

| `transition` value | Use when | Avoid when |
|---|---|---|
| `fade` / `fadefast` / `fadeslow` / `dissolve` | soft world continuity, memory dissolve, rare lyric drift | fast dance cuts, identity close-ups that must stay sharp |
| `fadeblack` | night/system off, motivated black gate | every section (becomes music-video screensaver) |
| `fadewhite` | flash-cut, camera bulb, heaven/overexpose grammar | dark moody tracks without white permission |
| `fadegrays` | desaturated memory bridge | skin-critical romantic close cut |
| `wipeleft`/`wiperight`/`wipeup`/`wipedown` | direction matches camera/body exit | random wipe with no direction motive |
| `wipetl`/`wipetr`/`wipebl`/`wipebr` | diagonal stage wipe matching formation | decoration |
| `slideleft`/`slideright`/`slideup`/`slidedown` | parallax card / UI panel MV grammar | natural performance realism |
| `smoothleft`/`smoothright`/`smoothup`/`smoothdown` | softer slide, lyric card energy | same as slide |
| `coverleft`/`coverright`/`coverup`/`coverdown` | next shot covers previous like a panel | subtle emotional verse |
| `revealleft`/`revealright`/`revealup`/`revealdown` | pull-away reveal | crowded face framing |
| `circleopen`/`circleclose`/`circlecrop`/`rectcrop`/`radial` | portal/system/eye motif only | generic idol chorus |
| `vertopen`/`vertclose`/`horzopen`/`horzclose` | shutter / gate / mirror split worlds | no spatial motive |
| `diagtl`/`diagtr`/`diagbl`/`diagbr` | slash energy, graphic MV | soft vocal close-up |
| `hlslice`/`hrslice`/`vuslice`/`vdslice` | slice/stagger graphic | identity integrity risk |
| `hlwind`/`hrwind`/`vuwind`/`vdwind` | wind/speed streak transition | quiet emotional hold |
| `hblur` | speed blur bridge when motion already streaks | static face talk |
| `pixelize` | digital breakup | beauty close-up |
| `distance` | dreamy depth blend | precise choreography read |
| `squeezeh`/`squeezev` | graphic compress | body mechanics focus |
| `zoomin` | push into next world | already punch-zoomed cut |
`custom` is not in the active machine registry. Use only named, smoke-tested
transitions until a separately validated expression contract exists.

Recipe/04FX shape for boundary xfade:

```yaml
type: xfade
start_frame: 300       # canonical fixed program cut frame
duration_frames: 4
start: 12.500          # seconds projection at the recipe FPS
duration: 0.167        # seconds projection
transition: fadeblack
from_slot: R12
to_slot: R13
transition_handle_ref: HANDLE_R12_R13
timeline_impact: program_frames_unchanged
```

04FX never authors `HANDLE_R12_R13`; 04 creates it after source-handle and
cutpoint review. Do not silently retime audio.

### C. Grade / tone unification (segment or window)

Prefer recipe `grade` / `grade_profiles` for section-length tone glue.
Window pulses above are for short musical accents only.

Useful FFmpeg building blocks already available locally and allowed inside
`grade_profiles.*.filter` when previewed:

- `eq`, `curves`, `colorbalance`, `colortemperature`
- `hue`, `huesaturation`, `vibrance`, `colorchannelmixer`, `colorize`
- `lut3d` when a run-owned LUT path exists
- `vignette`, `noise`, `unsharp`, `gblur`, `deflicker`

### D. Overlay / text / mask (local available, selective)

| Tool | Use when | 04FX status |
|---|---|---|
| `overlay` | logo hold, symbol, signal line precomp | supported as `source_overlay` (MoviePy path / compile target) |
| `drawtext` | audible lyric/object word only | optional `drawtext_hit`; never default spam |
| `colorkey`/`chromakey` | clean plate inserts | analysis-first; rare |
| `maskedmerge`/`alphamerge` | shaped reveals | needs matte source |
| `subtitles`/`ass` | package captions / review burn-ins | usually 05/derivative, not master FX |

### E. Explicitly non-default / external

Keep as hold unless Founder approves external path:

- production roto, hair-clean mattes
- true 3D camera solve
- dense particle sims
- AI morph transitions

These remain `external_tool_required` in the AE-like map.

## Post-Edit Final Quality Check: Transition Opportunity Pass

After 04 edit preview is pass/local-accepted and **before** one high-quality
final master, run this checklist and write it into the 04FX map as
`transition_opportunity_audit`:

1. List every section boundary in the passed window.
2. List every strong onset / drop / lyric gate that is a story or performance turn.
3. For each point mark one of:
   - `none_needed` — hard cut already sells the turn
   - `safe_default_proposed` — dip_flash / tiny punch / brightness
   - `manual_fx_proposed` — specific bridge/accent from this catalog
   - `return_to_04` — cut/source/speed is the real problem
4. Apply only proposed FX that still have a visible job after watching playback.
5. Preview windows → pass/hold/reject.
6. Include only `pass` records in final render compile.

Do not skip this pass because the roughcut “already looks fine.” Many
founder “어색/부족” notes are missing boundary accents, not wrong sources.

## Intensity Defaults (frame counts use the active recipe FPS)

| Class | frames | opacity/intensity |
|---|---|---|
| Safe boundary dip | 3–4 | 0.18–0.28 black |
| Hit flash | 2–3 | 0.35–0.55 white |
| Punch zoom | 2–3 | factor 1.03–1.05 |
| Blur pulse | 2–4 | sigma 0.6–1.4 |
| RGB split | 1–2 | shift 1–3 px |
| Soft xfade | 3–6 | duration 0.12–0.25s |
| Hard graphic xfade | 2–4 | only with motive |

## Compile Mapping

04FX `effect_design.effect_type` should use the names in this file, but
`automation/edit-effect-registry.yaml` is the executable truth for canonical
types, aliases, parameters, and supported transitions. Compiler and renderer
must fail—not silently drop—an unsupported passed record.

Friendly aliases accepted by compile/render:

`gblur`/`blur` → `blur_pulse`, `unsharp` → `unsharp_pulse`, `noise`/`grain` →
`grain_pulse`, `vignette` → `vignette_pulse`, `rgbashift` → `rgb_split`,
`chromashift` → `chromatic_shift`, `hblur`/`smear` → whip/smear types,
`edgedetect` → `edge_flash`, `drawtext`/`text_hit` → `drawtext_hit`,
`colortemperature` → `temperature_pulse`, `hue` → `hue_pulse`.

## Implementation Completeness (local 04FX)

### Implemented now (timeline-safe stream accents)

`flash`, `dip_flash`, `punch_zoom`, `micro_freeze`, `blur_pulse`,
`unsharp_pulse`, `brightness_pulse`, `color_pulse`, `contrast_pulse`,
`saturation_pulse`, `hue_pulse`, `temperature_pulse`, `eq_grade_window`,
`vignette_pulse`, `grain_pulse`, `rgb_split`, `chromatic_shift`, `shake`,
`tmix_smear`, `horizontal_blur_whip`, `edge_flash`, `zoom_hold`,
`drawtext_hit`, fade black/white family, `negate_flash`, `pixelize_pulse`,
`hard_cut_note`. `hard_cut_note` is metadata-only: keep it as a 04/base-recipe
annotation when useful, but never pass it as an applied 04FX record. A clean
boundary closes the audit point as `none_needed`.

### Implemented now (boundary)

`xfade` + the named FFmpeg transition list in the machine registry, with
duration-preserving 04 handle contracts for final render.

### Available locally but intentionally not default 04FX master tools

| Capability | Why not auto-wired as default |
|---|---|
| `source_overlay` multi-input FFmpeg graph | Needs second input wiring; MoviePy path remains experimental |
| clean `colorkey`/`chromakey` master inserts | Source-dependent; easy to break identity |
| `lut3d` full grade | Requires run-owned LUT + preview contract |
| time-lengthening freeze or speed redesign | 04 retime ownership; the local micro-freeze only replaces frames without changing duration |
| production roto / true 3D / dense particles | external_tool_required |

### Analysis assist that feeds 04FX (does not replace judgment)

- `scripts/idol_video_sync_workbench.py` → `audio-beat-onset-summary.json` v2
  (phase candidates/locks, ranked onsets, percussive onsets, energy jumps, low-energy holds)
- `scripts/idol_audio_precision_markers.py` → higher-precision sidecars
- `scripts/idol_04fx_transition_opportunity_seed.py` → draft
  `review_candidate` audit points from recipe boundaries + audio evidence; add
  the v2 04 marker plan so the evidence index can expose cut method, route,
  visible-action basis, and return-to-04 risk

These are measurement seeds only. They cannot lock cuts, choose an effect type,
or auto-pass FX. Resolve every `review_candidate` after watched playback.

## QC Guards (every included effect)

- face / hands / feet / body path readable
- full space and world atmosphere preserved
- track tone-and-manner preserved
- no cheap repeated-effect demo drift
- flash/flicker safety
- mobile readability
- source quality not hidden
- audio sync still true after any xfade
