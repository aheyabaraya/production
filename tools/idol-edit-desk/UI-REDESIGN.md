# IDOL Edit Desk UI Redesign

Date: 2026-07-07

## Goal

Make IDOL Edit Desk feel like a real editing desk instead of a helper panel.
The target is not to copy Adobe visual branding. The target is to adopt the
interaction model that professional editors already understand: source monitor,
program monitor, timeline tools, media/project bins, track headers, clip
properties, markers, and preview/render controls.

## References Checked

- Adobe Premiere workspace overview:
  https://helpx.adobe.com/premiere/desktop/get-started/tour-the-workspace/what-are-workspaces.html
- Adobe Premiere Source Monitor and Program Monitor:
  https://helpx.adobe.com/premiere/desktop/get-started/source-and-program-monitor-adjustments/about-source-monitor-and-program-monitor.html
- Adobe Premiere Tools panel:
  https://helpx.adobe.com/premiere/desktop/get-started/tour-the-workspace/tools-panel-and-options-panel.html
- Adobe Premiere timeline navigation controls:
  https://helpx.adobe.com/premiere/desktop/edit-projects/change-clip-sequence/navigation-controls-in-the-timeline.html
- Adobe Premiere trim behavior:
  https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/trim-a-clip.html
- Adobe After Effects composition and timeline model:
  https://helpx.adobe.com/after-effects/desktop/work-with-compositions/composition-settings/composition-basics.html
- Adobe After Effects layer switches and timeline columns:
  https://helpx.adobe.com/after-effects/desktop/work-with-layers/manage-layers/layers.html
- Adobe Premiere markers, proxy workflow, text-based editing, and speed/duration
  reference pages:
  https://helpx.adobe.com/premiere/desktop/organize-media/apply-labeling/overview-of-markers.html
  https://helpx.adobe.com/premiere/desktop/organize-media/ingest-proxy-workflow/create-proxies.html
  https://helpx.adobe.com/premiere/desktop/edit-projects/edit-video-using-text-based-editing/overview-of-text-based-editing.html
  https://helpx.adobe.com/premiere/desktop/edit-projects/change-clip-speed/different-ways-to-change-clip-speed-and-duration.html
- CapCut Desktop and online editor feature references:
  https://www.capcut.com/tools/desktop-video-editor
  https://www.capcut.com/tools/online-video-editor
  https://www.capcut.com/tools/ai-caption-generator

## Current UI Read

Current source: `idol_edit_desk.py`

- One top toolbar holds file actions, media helpers, render, undo/redo, and
  terminal actions.
- Main layout is three columns:
  - left sidebar: placeholder Runs/Recipes header, clip table, source tree
  - center: one Program-style viewer, playback controls, section nav, timeline
  - right sidebar: Inspector, Source, Markers, Sections, Lyrics, Contact, Log
- Timeline is custom-drawn on one canvas with these lanes:
  - Time
  - Song waveform
  - Sections
  - Markers
  - Clips
- Existing strengths:
  - safe draft save
  - source in/out fields
  - split/delete/duplicate/move/speed/fit-to-section
  - markers, sections, lyrics, contact sheets
  - frame preview and trim preview
- Main UI gap:
  - professional edit concepts exist, but they are hidden in tabs and text
    buttons instead of being exposed as an editing workspace.

## Target Shape

Use a Premiere-first layout with AE-inspired property detail.

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Workspace bar: Edit | Review | FX | Export          Open Save Render QC    │
├───────────────┬──────────────────────────────────────────────┬─────────────┤
│ Project/Media │ Source Monitor        Program Monitor        │ Properties  │
│ - Recipes     │ in/out, source time    sequence time          │ Clip        │
│ - Sources     │ append/insert          playback/render range  │ Speed       │
│ - Clips       ├──────────────────────────────────────────────┤ Markers     │
│ - Sections    │ Tool strip | Time ruler / work area / markers │ Sections    │
│               │            | Song waveform                    │ Notes       │
│               │            | Section/story lane               │ Log         │
│               │            | V1 clip track                    │             │
│               │            | A1 future/audio guide track      │             │
│               ├──────────────────────────────────────────────┤ Console     │
│               │ Assistant command line + background job queue │             │
└───────────────┴──────────────────────────────────────────────┴─────────────┘
```

## Reference Patterns To Adopt

1. Premiere workspaces

Premiere treats panels as task-specific workspaces. IDOL should add a visible
workspace strip, but keep the first release focused:

- `Edit`: default cutting workspace
- `Review`: playback, QC notes, markers, contact sheet
- `FX`: future finishing effects and speed/time controls
- `Export`: render preview, latest preview, package status

For the first pass these can switch visible panel emphasis without changing the
data model.

2. Source Monitor / Program Monitor

Premiere separates source preparation from sequence playback. IDOL already has
both concepts, but Source is buried in a right-side tab. Promote it:

- left center: `Source` monitor
  - source filename
  - source timecode
  - Set In, Set Out
  - Append Selection
  - Fit To Section
- right center: `Program` monitor
  - sequence timecode
  - previous frame, play, next frame
  - render range badge
  - frame unavailable state

On narrow windows, stack them as tabs: Source | Program.

3. Premiere Tools panel

Turn common commands into a vertical tool strip next to the timeline:

- Select: default select/move playhead behavior
- Trim: edge trim and ripple trim
- Razor: click a clip to split
- Rate: speed/rate stretch
- Hand: pan timeline
- Marker: add marker at playhead/clicked time
- Snap: toggle snapping

The current shortcuts can remain. Tool mode makes the visible app easier to
trust because the cursor action is explicit.

4. Timeline navigation

Premiere exposes time ruler, work area bar, playhead, playhead position, and
zoom scroll bar. IDOL should keep the canvas but redraw it closer to this:

- top time ruler with current time display
- draggable playhead head plus vertical line
- work area / render preview range lane above clips
- zoom bar at bottom, separate from horizontal scroll
- stronger track headers on the left
- label and color lanes consistently

5. Trim behavior

Premiere makes trimming edge-based: hover clip edge, see trim affordance, drag.
IDOL already supports edge dragging. The UI needs clearer feedback:

- wider edge handles at high zoom
- trim cursor/status text: `Trim In`, `Trim Out`, `Ripple Trim`
- two-up trim preview promoted near Program monitor during active drag
- live delta display: `+0.32s`, `-12 frames`

6. After Effects layer/timeline columns

AE's useful contribution is not its full compositing model. The useful part for
IDOL is per-layer/clip switches and property columns:

- visible/on toggle
- audio/use toggle for future audio guide tracks
- solo/review-only toggle
- lock toggle
- quality/proxy indicator
- label color
- source name vs clip name toggle

Add these first as clip metadata fields in UI only where the recipe supports or
can safely ignore them.

7. CapCut fast-creator conveniences

CapCut's useful pattern for IDOL is not deep timeline precision. It is fast
completion:

- fast import -> timeline -> trim/split/crop/effects/export path
- auto captions / transcript features
- templates and preset effects
- aspect-ratio conversion for social outputs
- smart search over media by object/dialogue/person where available
- keyframes/graphs for simple motion
- color wheel and auto adjust
- direct short-form export presets

IDOL should adopt these as optional speed layers over the Premiere-like base.
The base editor remains source/program/timeline/properties; CapCut-like helpers
become one-click assistants, presets, and output packs.

## Additional Feature Backlog

### A. Project / Media Bin

- Media health badges: missing, proxy ready, native trim possible, needs ffmpeg,
  has audio, resolution, fps, duration, codec.
- Smart filters: selected run only, missing media, generated clips, passed
  clips, rejected clips, source family, section id, member id.
- Relink/reveal/open-in-Finder actions.
- Thumbnail strip and contact-sheet preview.
- Local source metadata cache.

### B. Timeline Editing

- Ripple, roll, slip, slide, rate-stretch modes.
- J/L cut support for audio/video offset, even if the default IDOL path keeps
  master audio locked.
- Multi-track readiness: V1 main, V2 overlays/text/effects, A1 master audio,
  A2 source/audio guide.
- Track lock, solo/review-only, enable/disable switches.
- Timeline minimap / zoom bar / scroll grip.
- Edit history panel with human-readable commands.
- Scene-edit detection or cut-point suggestion on imported rendered videos.

### C. Review And QC

- Marker colors and marker types: pass, hold, fix, beat, lyric, face issue,
  continuity issue, source gold.
- Marker detail panel with status, owner, note, linked frame, linked section.
- Compare source vs program frame.
- Before/after preview for trims and replacements.
- QC checklist per selected range:
  - audio sync
  - face readability
  - section continuity
  - source quality
  - framing/crop safety
  - final hold

### D. Captions / Lyrics / Transcript

- Lyrics/cue lane becomes editable.
- Import transcript/caption file as timecoded markers.
- Optional local speech-to-text backend later, but not required for the first
  usable cut desk.
- Text-based editing style command surface: selecting text/cue can select or
  trim timeline ranges.
- Social caption preview overlay with safe margins.

### E. Effects / Motion / Color

- Keyframe-lite panel for scale, position, opacity, crop, blur, and speed.
- Graph-lite editor for speed ramps and simple scale/position curves.
- Color wheel / auto-adjust placeholder for fast look checks.
- LUT/preset slot, even if actual render implementation stays ffmpeg/native
  backend dependent.
- CapCut-like effect presets as named recipe effects, not hidden destructive
  filters.

### F. Short-Form Output Packs

- Output presets: full master, 90s, 45s, 30s, 15s, 9:16, 1:1, 16:9, 3:2.
- Safe-area overlays for TikTok/Reels/Shorts.
- Thumbnail/cover frame picker.
- Batch render queue with explicit final approval.
- Package checklist: file path, duration, resolution, aspect ratio, audio,
  caption, cover, marker notes.

### G. Assistant / Command Workflows

- Natural-language command preview before applying changes.
- Local deterministic command parser first; external model integration is not a
  default requirement.
- Command examples:
  - `make selected 0.2s shorter`
  - `split here and mark as hook`
  - `render S03 proxy`
  - `make 9:16 preview from selected range`
- Command log writes an edit history that can be saved with the draft.

## Readability And UIUX Improvements

The app can follow real Premiere/CapCut layouts closely because this is a local
personal tool. Still, do not embed Adobe/CapCut proprietary icons, logos,
screenshots, or code. Copy the interaction grammar and visual hierarchy:

- Dense dark professional surface, but with clearer contrast than the first
  pass.
- Fixed-height toolbar rows and fixed-width tool strip so the layout does not
  jump.
- Icon-like short labels in the tool strip, plus tooltips/status text.
- Stronger selected states: selected clip, selected track, active monitor,
  active tool, dirty render range.
- Consistent color semantics:
  - teal = active/current media
  - yellow = playhead/work range
  - red = missing/error/fix
  - green = pass/good take
  - purple = effect/motion
- Larger hit targets for trim handles at high zoom.
- Hover feedback for clip body, trim handles, marker, playhead, and source
  in/out handles.
- Collapsible right inspector sections instead of long vertical forms.
- Timecode always visible in Source, Program, and Timeline.
- Track headers stay readable and pinned while horizontally scrolling.
- Timeline lanes should have labels and secondary sublabels, but avoid full
  sentence instructions inside the canvas once controls are discoverable.
- Use badges instead of paragraphs: proxy, native, ffmpeg, dirty, rendered,
  missing, locked, muted, hidden.
- Add a small status/job shelf for background probe/proxy/render operations.

## Implementation Plan

### Phase 1: Professional Shell

Files:

- `idol_edit_desk.py`
- `README.md`
- `PLAN.md`

Changes:

- Replace the current single toolbar with:
  - compact app bar
  - workspace strip
  - grouped command buttons
- Rename panels to professional edit terms:
  - `Project`
  - `Source`
  - `Program`
  - `Timeline`
  - `Properties`
- Split the current center viewer into Source and Program monitors.
- Move Source tab controls into the Source monitor area.
- Keep the right tabs, but make `Properties` the default and reduce tab count
  by grouping:
  - Clip
  - Markers
  - Sections
  - Review
  - Log

Acceptance:

- Existing open recipe/video/add/save/snapshot/render behavior still works.
- Existing keyboard shortcuts still work.
- No original recipe overwrite.
- Window remains usable at 980x620.

### Phase 2: Timeline Rebuild On Same Canvas

Files:

- `idol_edit_desk.py`

Changes:

- Add track-header column with fixed width.
- Add tool mode state.
- Add vertical tool strip.
- Draw lanes as:
  - ruler
  - work/render area
  - markers
  - waveform
  - sections/story
  - V1 clips
  - future A1/audio guide placeholder
- Improve clip rendering:
  - stronger selected state
  - source filename badge
  - speed badge
  - missing media warning badge
  - trim handles with hover/active states
- Add playhead head and current time box.
- Add zoom control that feels like Premiere's zoom scroll bar.

Acceptance:

- Split, trim, ripple trim, move, duplicate, delete, speed, snapping, markers,
  and section nav still work.
- Hover/click targets remain stable and do not shift when labels change.
- Long recipes remain scrollable.

### Phase 3: Review / QC Desk

Files:

- `idol_edit_desk.py`
- `README.md`

Changes:

- Build Review workspace:
  - Program monitor emphasized
  - marker list and QC note visible
  - contact sheet visible without hiding inspector
  - render preview and open latest preview grouped together
- Add render range display and quick set range from selected section.
- Add a compact history/log drawer instead of always occupying a full tab.

Acceptance:

- Founder can watch, mark, note, render a section, and reopen the preview
  without moving across many tabs.

### Phase 4: FX / AE-Inspired Clip Properties

Files:

- `idol_edit_desk.py`
- maybe a future recipe schema patch if persistent fields are needed

Changes:

- Add per-clip switches:
  - visible/use
  - lock
  - solo/review-only
  - proxy/quality indicator
- Add effect/time badges from recipe `effects`.
- Add speed curve/time-remap placeholder UI only after recipe semantics are
  clear.

Acceptance:

- UI can display finishing intent without pretending to be full After Effects.
- Unsupported switches are either local-only or disabled with clear status text.

### Phase 5: Assistant Console And Terminal Bridge

Files:

- `idol_edit_desk.py`
- `README.md`
- maybe `runtime/` ignored local command/log files

Changes:

- Add an `Assistant` or `Console` panel with:
  - command input
  - parsed-command preview
  - apply/cancel controls
  - background job list
  - last terminal command/status log
- Keep the existing `Terminal` button, but make it a companion surface for
  inspection and manual override rather than the primary state owner.
- Support deterministic app-native commands first:
  - `trim selected in +0.20`
  - `trim selected out -0.12`
  - `split here`
  - `speed selected 1.25x`
  - `render selected`
  - `mark cut "good hook"`
  - Korean command aliases such as `선택 컷 앞 0.2초 줄여`, `여기서 자르기`,
    and `선택 구간 렌더`
- For ambiguous natural-language requests, show a structured proposed command
  before mutating the recipe.
- Future Codex/Grok control should use a local JSONL command inbox under the
  tool runtime folder, not terminal text scraping.

Acceptance:

- A command can adjust the selected clip without leaving the app.
- The command log records what changed and whether a draft save/render is still
  pending.
- No external API/model/upload action is triggered by the console.

### Phase 6: Background Probe / Proxy / Preview Queue

Files:

- `idol_edit_desk.py`
- maybe a small runtime cache manifest

Changes:

- Probe imported sources in the background with `ffprobe` once per source:
  - duration
  - fps
  - frame count
  - codec
  - resolution
  - rotation
  - audio stream presence
- Cache probe results and show source health badges in Project/Media and
  Properties.
- On trim/split/move/speed:
  - update the recipe and timeline immediately
  - mark selected range dirty
  - refresh still-frame previews from OpenCV/frame cache
  - debounce a selected-range proxy render after mouse-up or command completion
- Do not spawn ffmpeg during every drag event. Supersede stale jobs and keep
  only the latest selected-range preview active.
- Keep full master render explicit.

Acceptance:

- UI edits stay instant even when background preview rendering is busy.
- Selected-range proxy preview updates automatically after settled edits.
- Stale preview jobs cannot overwrite the latest preview status.
- Source metadata survives app restarts through a local ignored cache.

### Phase 7: macOS Native Lightweight Media Helper

Files:

- a small Swift helper under `tools/idol-edit-desk/` or `scripts/`
- `idol_edit_desk.py`
- runtime cache manifest

Changes:

- Add a short-lived macOS-native helper for operations that are lighter through
  AVFoundation than through full ffmpeg:
  - metadata probe
  - simple single-source start/duration trim
  - frame/thumbnail extraction
  - low-res proxy export when supported
- Prefer a Swift/AVFoundation helper because PyObjC is not currently available
  in the app Python environments.
- Use `/usr/bin/avconvert` only as a conservative fallback for simple
  start/duration exports. Local help confirms it supports `--start`,
  `--duration`, and `PresetPassthrough`, but a Swift helper gives better
  control over status, errors, and future composition behavior.
- Keep ffmpeg for complex multi-source recipe renders, filters, final master
  output, and exact reproducibility.

Acceptance:

- Single-source cutdown/proxy operations can run without a heavy ffmpeg path
  when macOS can do a safe passthrough/export.
- The app falls back to ffmpeg when the native helper cannot support the source
  or timeline.
- Native helpers never alter global OS settings and run only as short-lived
  child processes.

## Non-Goals

- Do not clone Adobe branding, icons, exact screenshots, or proprietary visual
  assets.
- Do not add paid generation, upload, Drive sync, platform sync, or external
  connector actions.
- Do not replace the recipe model before the current editor is easier to use.
- Do not move to Tauri/Electron until the Tk workflow proves the layout and
  interaction model.

## First Code Pass Recommendation

Start with Phase 1 and Phase 2 together in one focused change:

1. Add workspace strip and panel renames.
2. Promote Source monitor next to Program monitor.
3. Add timeline tool mode state and vertical tool strip.
4. Redraw timeline with track headers and a work-area lane.
5. Keep all persistence and recipe behavior unchanged.

This gives the founder a materially better editing desk without risking the
render pipeline or recipe safety rules.

## Adobe-Speed Boundary

An ffmpeg-backed editor can feel clean and fast for IDOL's workflow if it uses
cached frames, source probes, low-res proxies, dirty-range renders, debounce,
and background workers. It should not try to run a full ffmpeg render on every
trim drag. Adobe's apparent immediacy comes from its internal media engine,
cached decode/conform/proxy files, GPU paths, and background previews. IDOL Edit
Desk should follow that architecture at the workflow level, not the exact
implementation.

macOS-native AVFoundation/VideoToolbox paths can help with lightweight probe,
thumbnail, passthrough trim, and proxy export. They do not replace ffmpeg for
the full IDOL recipe renderer; they reduce unnecessary heavy work around the
interactive editing loop.
