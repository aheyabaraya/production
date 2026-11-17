# IDOL Edit Desk

IDOL Edit Desk is a lightweight local editor for IDOL recipe-based video cuts.
It is intentionally not a web server. It runs through the repository video
launcher and only calls heavier media work when the founder requests a waveform,
BPM calculation, or preview render.

## Folder

This tool is isolated under:

```text
tools/idol-edit-desk/
```

Core source and docs live in this folder. Runtime imports, snapshots, preview
outputs, and Python caches are ignored by this folder's `.gitignore`. The repo
entrypoint remains `scripts/idol-edit-desk` so the command is short and stable.

## Run

```bash
scripts/idol-edit-desk
```

Open a recipe from the app, or start with a known recipe:

```bash
scripts/idol-edit-desk \
  --recipe runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL/generations/video/qc/sync-workbench-v1/final-master-recipe-v11-source-clean-3x2-hq.yaml
```

## Current MVP

- Load an IDOL edit recipe YAML.
- Open a standalone video file and turn it into a one-clip edit recipe.
- Add one or more source videos to the current timeline in one file picker pass.
- Use a Premiere-style editing shell with Project/Media on the left,
  Source/Program monitors in the center, timeline tools beside the timeline,
  and Properties on the right.
- Show a Source monitor for source in/out selection and a Program monitor for
  the current sequence playhead.
- Display clips as one horizontal edit track, so multiple clips sit end-to-end.
- Show timeline track headers, a work/render-area lane, marker lane, waveform
  guide lane, story/section lane, V1 clip lane, and A1 audio guide lane.
- Select visible timeline tools for select, trim, razor, rate, hand/pan,
  marker, and snapping workflows.
- Use a lightweight Console tab for deterministic local edit commands such as
  split, marker, render, save, speed, and trim adjustments.
- Show source status/meta badges in the Project/Media source tree and a compact
  job shelf for waveform, BPM, and preview render tasks.
- Drag clip edges to trim or extend inside the real source video duration.
- Split, delete, duplicate, move clips left/right, undo, redo, and apply speed.
- Accept speed values as `1`, `1x`, `100%`, `0.5x`, or `2x`.
- Use keyboard shortcuts for fast cutting and recovery: `Cmd/Ctrl+Z`,
  `Cmd/Ctrl+Shift+Z`, `Cmd/Ctrl+S`, `Space`, `B`, `S`, `M`, `I`, `O`, `Q`,
  `W`, `=`, `-`, `Delete`, `Esc`, and arrow keys.
- Snap cuts and trim handles to clips, sections, lyrics, and markers.
- Add timeline markers and generate non-destructive cue markers from sections,
  lyric marks, and waveform peaks.
- Use a separate Source tab to preview source media, set source in/out, append
  a selected source range, and fit the selected clip to the active section.
- Resize the window with responsive preview/timeline sizing and mouse-wheel
  timeline scrolling/zooming.
- Save to a draft recipe without overwriting the source recipe by default.
- Load a song waveform on demand.
- Show song sections on the timeline from run-owned section maps.
- Show BPM as a compact text value. It does not draw dense beat or onset markers.
- Load lyrics or cue text into the side panel.
- Load contact sheet images into the side panel.
- Show a trim preview monitor for the selected clip's current source-in and
  source-out frames while edge handles are dragged.
- Render a selected-section proxy preview using the existing ffmpeg recipe
  renderer.
- Open a macOS Terminal window at the current run folder for side-by-side use.
- Move left/right by song section or auto video chunk with `← Section` and
  `→ Section`.
- Use lightweight preview controls to play/pause and step the playhead by one
  second.

## Opening Video

Use `Open Video` for a plain `.mp4`, `.mov`, `.m4v`, `.mkv`, or `.webm`.

The editor creates a temporary recipe under:

```text
tools/idol-edit-desk/imports/
```

The whole video appears as one clip. From there, drag the clip edges, split it,
delete parts, or save a draft recipe. If the video does not have a song-section
map, the editor creates 10-second navigation chunks so `← Section` and
`→ Section` work immediately.

Use `Add Video` or the `+` button in Sources when you want CapCut-style source
assembly. The file picker accepts multiple videos and appends each one after the
current last clip. Existing IDOL recipe sections are preserved; plain imported
video sessions get automatic navigation chunks across the full edited timeline.

## Timeline Editing

The Clips lane is one horizontal video track. Click a clip body to select it and
move the playhead. Drag the left or right white handle to shorten or extend the
clip. Extending stops at the actual beginning or end of the source file, so the
draft recipe cannot accidentally point past available frames.

Inspector fields can also be edited directly. `Source In`, `Source Out`, and
`Duration` accept seconds or timecode-style values such as `1:23.5`. `Speed`
accepts numeric factors, `x` suffixes, or percentages. `Move ←` and `Move →`
swap the selected clip with its neighbor and then recalculate the output
timeline.

Useful shortcuts:

```text
Space        play / pause
B            split selected clip at the playhead
S            toggle snapping
M            add a cut marker at the playhead
I / O        set Source tab in/out at the source playhead
Q / W        ripple trim selected clip start/end to the timeline playhead
= / -        zoom timeline
Left/Right   step one frame
Up/Down      jump to previous/next edit point
Cmd/Ctrl+Z   undo last edit
Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y
             redo last undone edit
Cmd/Ctrl+S   save draft
Cmd/Ctrl+O   open recipe
Cmd/Ctrl+D   duplicate selected clip
Delete       delete selected clip
Esc          stop playback / cancel active drag
```

Mouse wheel scrolls the timeline horizontally. `Cmd`/`Ctrl` + wheel zooms around
the cursor. `Shift` + wheel scrolls faster. Holding `Option`/`Alt` while
dragging bypasses snapping on Tk builds that expose that modifier bit.

## Markers And Source Preview

Markers are stored under `edit_desk_markers` in the draft recipe. `M` adds a
manual cut marker. The Markers tab can jump, delete, or generate cue markers
from loaded song sections, lyric timestamps, and waveform peaks. Cue markers are
advisory only; they do not split clips until you use split/trim commands.

The Source tab is separate from the main Program viewer. Double-click a file in
Sources or select a clip to load the source media, scrub it, set in/out points,
and append that source range as a new clip.

## Song Sections And BPM

The editor automatically looks for section maps in the opened recipe and then in
the run folder, including `00A-song-lock.yaml`,
`research/selected-audio-analysis-v*.yaml`, and `00-creative-nucleus.yaml`.

`BPM` first reads existing run notes such as `tempo_and_form.bpm` or
`tempo_read`. Only if no local BPM note exists does it calculate a single tempo
number from the audio.

## Trim Preview

When a clip is selected, the Inspector tab shows the current `IN` and `OUT`
source frames. While dragging the left or right clip handle, the active trim
side is highlighted so the founder can see the frame being added or removed.

The preview reads single frames from the recipe source file and caches them at
0.1-second precision. If the source video is not present in the local workspace,
the panel shows a missing/unavailable source message instead of blocking edits.

## Edit Safety

`Save Draft` writes next to the opened recipe as:

```text
<recipe-name>.edit-desk-draft.yaml
```

`Snapshot` writes timestamped copies under:

```text
tools/idol-edit-desk/snapshots/
```

The app does not perform paid generation, publishing, upload, platform sync, or
external connector work.

## Automation Direction

The editor is planned to support an in-app Assistant/Console surface for
chat-like deterministic edit commands such as trimming the selected clip,
splitting at the playhead, changing speed, adding markers, and rendering the
selected range. This should mutate the app's recipe model directly and keep the
terminal as a companion log/manual-override surface.

Current media automation already includes source duration probing with
`ffprobe`, OpenCV frame preview/cache, and background selected-range ffmpeg
preview rendering. The next step is to add a background job queue with cached
source metadata, dirty-range tracking, debounce, and stale-job cancellation so
quick edits feel immediate while heavier preview renders happen behind the UI.

macOS-native media helpers are also planned for lightweight operations that do
not need a full ffmpeg render. The local Mac has `swift`, `xcrun`, `avconvert`,
and `afconvert`; PyObjC is not currently available in the app Python
environment. The preferred path is therefore a small Swift/AVFoundation helper
for safe metadata probing, passthrough start/duration trim when supported,
thumbnail extraction, and proxy export. `avconvert` can be a fallback for simple
single-source trims, while ffmpeg remains the compatibility path for complex
multi-source recipe renders and final masters.

The next UI pass should copy the practical editing patterns from Premiere and
CapCut closely: readable dark panels, pinned track headers, clear active states,
color-coded markers, project/media health badges, collapsible Properties
groups, hover affordances, short-form safe-area overlays, auto-caption/transcript
helpers, templates/presets, and a visible background job shelf for probe, proxy,
and render tasks.
