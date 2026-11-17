# IDOL Edit Desk Plan

## Decision

Build the first version as a lightweight local Python/Tk app, not as a web
server. This keeps idle resource use low and lets the app run through the
existing `scripts/idol-video-python` environment.

Longer term, the same recipe/data model can move into a Tauri app if the founder
wants a more polished desktop shell.

## 2026-07-07 Professional Shell Pass

The current UI direction is Premiere-first with light After Effects influence:

- left Project/Media column for recipes, sources, and clip lists
- center Source and Program monitors
- visible workspace strip: Edit, Review, FX, Export
- timeline tool strip: Select, Trim, Razor, Rate, Hand, Marker, Snap
- custom canvas timeline with track headers, work/render-area lane, marker
  lane, waveform guide, story/section lane, V1 clip lane, and A1 audio guide
- right Properties panel for clip, marker, section, review, and log surfaces

This pass intentionally keeps recipe persistence, safe draft behavior, source
probing, preview rendering, and existing keyboard shortcuts in place.

## 2026-07-08 Premiere / CapCut Feature Expansion

Additional product references are now folded into
`tools/idol-edit-desk/UI-REDESIGN.md`:

- Premiere patterns to keep:
  - workspaces and panel docking grammar
  - source/program monitor separation
  - marker colors/properties
  - proxy workflow
  - text-based editing / transcript-to-timeline thinking
  - ripple/roll/slip/slide/rate-stretch/speed-duration concepts
  - timecode, track locks, snapping, history, sequence navigation
- CapCut patterns to keep:
  - fast import-to-export flow
  - auto captions / transcript helpers
  - templates/effects/presets
  - aspect-ratio conversion for short-form outputs
  - keyframes and curves for simple motion
  - color wheel / auto adjust style quick controls
  - smart media search and quick social export presets

Implementation priority:

1. Make the current UI more readable: pinned track headers, clearer active
   states, consistent badge colors, collapsible Properties groups, and hover
   affordances.
2. Add media health/proxy/native/ffmpeg badges in Project/Media.
3. Add marker detail and QC status types.
4. Add background job shelf for probe/proxy/render.
5. Add Assistant/Console commands for deterministic edits.
6. Add short-form output pack presets and safe-area overlays.
7. Add keyframe-lite motion/speed graph features only after the base editing
   flow feels stable.

## 2026-07-09 Lightweight Applied Pass

Implemented without adding heavy render backends or external dependencies:

- `Console` tab for deterministic local commands:
  - save / snapshot / render
  - split / delete / marker / fit section
  - speed changes such as `speed 1.25x`
  - trim changes such as `trim in +0.20`, `trim out -0.12`
  - Korean aliases such as `선택 컷 앞 0.2초 줄여`, `여기서 자르기`,
    `선택 구간 렌더`
- Project/Media source tree now shows lightweight status/meta badges:
  - `missing`
  - `native`
  - `ffmpeg`
  - duration and file extension
- Compact job shelf shows background waveform, BPM, and selected preview render
  status.
- Console mirrors log messages so edit commands and resulting app actions stay
  visible in one place.

## 2026-07-09 Design Polish Pass

Applied immediate readability improvements:

- shortened toolbar labels to reduce crowding
- reduced button padding and title scale
- moved to a calmer dark palette with blue active state, amber playhead/work
  range, red error/fix, green pass, and purple/blue cue accents
- prevented low-height timeline lane headers from drawing overlapping sublabels
- shortened empty-state canvas helper text
- tightened Project/Media and Clips table column widths
- truncated long monitor overlay labels based on actual monitor width

## 2026-07-09 Human-Use Simplification Pass

Follow-up UX simplification after trying to inspect the live desktop state:

- default monitor layout now favors Program over Source
- Source monitor is treated as a smaller preparation panel
- Program monitor gets more height in responsive layout
- left and right sidebars are slightly narrower
- status/job text and source names are compacted with ellipsis
- Console intro text is shortened to one practical command line

The intent is to make the app feel like a working editor, not a control panel
that explains itself too much.

## 2026-07-07 Automation Console / Background Media Plan

The founder wants the editor to support chat-like adjustment while staying
connected to terminal/media tooling. This is feasible, but the implementation
must separate instant UI edits from heavier media work.

### macOS Native Media Layer

Use macOS-native media capabilities where they are lighter than ffmpeg and do
not require system-level mutation.

Local environment check:

- `/usr/bin/swift` exists.
- `/usr/bin/xcrun` exists.
- `/usr/bin/avconvert` exists.
- `/usr/bin/afconvert` exists.
- PyObjC modules (`AVFoundation`, `Quartz`, `Cocoa`, `objc`) are not currently
  available in either system Python or `scripts/idol-video-python`.

Preferred native path:

- Add a small Swift/AVFoundation helper for safe media operations that benefit
  from macOS frameworks:
  - source metadata probe
  - lightweight passthrough trim when container/codec supports it
  - thumbnail/frame extraction
  - optional proxy export through AVFoundation presets
- Use `avconvert` only as a conservative fallback for simple single-source
  start/duration trims or quick preset exports. It supports `--start`,
  `--duration`, and `PresetPassthrough` locally, but it is less controllable
  than a purpose-built Swift helper.
- Use `afconvert` only for audio-specific conversion/normalization tasks, not
  video edits.
- Keep ffmpeg as the compatibility/final-render backend for complex timelines,
  multi-source recipes, filters, exact crop/scale/audio stitching, and
  reproducible master renders.

OS-safety rules:

- Never install launch agents, background daemons, kernel/system extensions, or
  login items.
- Never change global macOS media settings.
- Run native helpers as short-lived child processes only.
- Limit background concurrency to one active media render/probe job by default.
- Write caches only inside `tools/idol-edit-desk/runtime/` or the run-owned
  preview/cache folder.
- Use low-priority execution for non-urgent preview/proxy jobs where practical.
- Keep full renders explicit and founder/operator-triggered.

### Chat / Terminal Control Surface

Add an `Assistant` or `Console` panel inside the app, plus keep the existing
`Terminal` launcher.

Target behavior:

- The founder can type short edit requests in natural language or command form:
  - `trim selected in +0.20`
  - `trim selected out -0.12`
  - `split here`
  - `speed selected 1.25x`
  - `render selected`
  - `mark cut "good hook"`
  - Korean equivalents such as `선택 컷 앞 0.2초 줄여`, `여기서 자르기`,
    `선택 구간 렌더`.
- The app parses safe deterministic edit commands itself first.
- For ambiguous chat requests, the app should create a structured pending
  command preview instead of mutating the recipe immediately.
- The terminal side should be a task log / command execution companion, not the
  source of truth. Recipe edits still happen through the app's in-memory recipe
  model and safe draft save path.
- Future Codex/Grok-style chat control should talk to the app through a small
  local command file or JSONL command inbox under
  `tools/idol-edit-desk/runtime/`, not by scraping terminal text.

Safety rule: no external model/API call, upload, Drive sync, platform action, or
paid generation is implied by the console.

### Automatic ffprobe / ffmpeg Behavior

Current app already does part of this:

- `ffprobe` is used through `probe_video_duration()` when a source duration is
  needed, with OpenCV fallback.
- single-frame source/program/trim previews use OpenCV and a frame cache.
- selected preview rendering already runs in a background thread through
  `scripts/idol_video_ffmpeg_revise_render.py` with ffmpeg.

Next target behavior:

- On source import:
  - run `ffprobe` once in the background
  - cache duration, fps, frame count, codec, resolution, rotation, audio-stream
    presence, and proxy-readiness
  - show source health badges in Project/Media and Properties
- On trim/split/move/speed edit:
  - update recipe/timeline UI instantly
  - mark the selected range dirty
  - refresh still-frame previews from OpenCV/cache
  - debounce background proxy render after the edit settles, for example
    500-900 ms after mouse-up or command completion
- On repeated drag:
  - do not spawn ffmpeg for every pixel movement
  - cancel or supersede stale background render jobs
  - keep only the latest selected-range render active
- On selected preview:
  - render a low-resolution proxy first
  - optionally render a higher-quality review preview only on explicit request
- On full master:
  - stay explicit. Full renders remain founder/operator-triggered because they
    are heavier and may overwrite review assumptions if run blindly.

This is the closest practical ffmpeg-based equivalent to Adobe's feel: immediate
timeline feedback first, background conform/proxy/render second, explicit final
render last.

### Why It Can Feel Fast

Adobe does not run an external ffmpeg command for every trim drag. It uses an
internal media engine, cached decoded frames, proxies, conform files, GPU paths,
and background previews. IDOL Edit Desk can approximate the usable behavior:

- cache probe results
- cache decoded still frames
- prebuild low-res proxies for heavy sources
- render only dirty selected ranges
- debounce render jobs
- keep UI responsive with worker threads
- keep final ffmpeg render explicit and reproducible

Expected performance target:

- trim/split/move UI response: instant
- still-frame preview after scrub/trim: near-instant if cached, otherwise
  sub-second for normal local files
- selected proxy preview after edit: a few seconds depending on source codec,
  duration, resolution, and machine load
- full-song render: not instant; should remain an explicit render action

## MVP Scope

1. Load an IDOL recipe YAML, open one standalone video as a one-clip recipe, or
   append multiple video files to the current timeline, and infer the owning run
   root.
2. Show the timeline with one horizontal clip track, output timing, song-section bands,
   compact BPM text, lyric cue ticks, effect marks, and a waveform lane.
3. Show a large center preview frame tied to the current playhead, with basic
   play/pause and one-second step controls.
4. Let the founder directly edit common cut operations:
   - trim/extend left and right clip edges
   - see the current source-in/source-out frames while trimming
   - split selected clip
   - delete selected clip
   - duplicate selected clip
   - move the selected clip left or right in the timeline
   - apply speed from the inspector
   - edit source in/out and duration fields
   - use undo/redo history and shortcut-driven split, marker, snapping,
     frame-step, delete, duplicate, save, and ripple-trim actions
   - use a Source tab to set in/out and append source ranges
   - generate non-destructive cue markers from sections, lyric timestamps, and
     waveform peaks
5. Keep edits safe:
   - default save writes an `.edit-desk-draft.yaml`
   - snapshots write to `tools/idol-edit-desk/snapshots/`
   - original recipe overwrite is intentionally not in the first version
6. Use existing IDOL render scripts for selected-section preview renders.

## Toolbar Surfaces

- `Song`: load the active audio as a waveform on demand.
- `Sections`: load run-owned song section maps and show them as timeline bands.
- `← Section` / `→ Section`: move the playhead and horizontal timeline view by
  song section or auto video chunk.
- `Open Video`: import a plain video file into a temporary one-clip recipe.
- `Add Video`: append one or more source video files after the current last
  clip.
- `BPM`: show a compact tempo value from run notes, or calculate one value from
  the song only when no local BPM note exists.
- `Lyrics`: load lyrics/cue text and extract timestamped lane labels.
- `Contact Sheet`: open image contact sheets in the side panel.
- `Render Preview`: render the selected clip window through ffmpeg.
- `Open Preview`: open the latest rendered preview in the default macOS player.
- `Terminal`: open macOS Terminal at the current run folder for side-by-side use.
- `Markers`: manage manual and generated cue markers.
- `Source`: preview source media, set source in/out, append a source range, and
  fit selected clip duration to the active section.

## Not In MVP

- Paid generation calls.
- Publishing, upload, scheduling, Drive/GitHub sync, or external connectors.
- Full nonlinear multi-track compositing.
- Direct CapCut/Premiere project mutation.
- Always-on dev server.
- Clip-audio pitch preservation. Current rendering uses the master song audio,
  while clip speed is represented through video `output_duration`.
