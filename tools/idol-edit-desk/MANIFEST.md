# IDOL Edit Desk Manifest

## Purpose

`tools/idol-edit-desk/` is the isolated local editing tool folder for the
founder-facing IDOL cut-edit desk. It is a lightweight desktop UI, not a web
server and not a publishing or generation surface.

The public launcher remains:

```bash
scripts/idol-edit-desk
```

That wrapper runs this tool through `scripts/idol-video-python` so the same
media Python, ffmpeg, ffprobe, and OpenCV environment is used as the rest of the
repo video workflow.

## Core Files

- `idol_edit_desk.py`: Tk desktop UI and edit recipe logic.
- `README.md`: operator-facing usage notes.
- `PLAN.md`: implementation scope, current MVP boundary, and next-step shape.
- `MANIFEST.md`: this folder map.
- `.gitignore`: keeps runtime drafts, caches, and snapshots out of source
  control by default.

## Runtime Folders

These folders may be created while using the editor and are intentionally
ignored:

- `imports/`: temporary recipes made from standalone video imports.
- `snapshots/`: timestamped recipe snapshots.
- `previews/` or `renders/`: local preview/render outputs if a future workflow
  writes them inside the tool folder.
- `__pycache__/`: Python bytecode cache.

## Current Capabilities

- Open an existing IDOL edit recipe.
- Open one standalone video as a new one-clip recipe.
- Add multiple source videos to one horizontal clip track.
- Trim or extend clip edges inside actual source duration.
- Split, delete, duplicate, move clips left/right, and set speed.
- Use bounded undo/redo history plus shortcut-driven split, marker, snapping,
  ripple trim, delete, duplicate, save, frame step, and edit point navigation.
- Manage `edit_desk_markers` and generate advisory cue markers.
- Use a separate Source tab for source scrub, in/out, append, and fit-to-section
  workflows.
- Load song waveform, section map, BPM note, lyrics/cue text, and contact sheet.
- Save safe drafts without overwriting the source recipe by default.
- Render selected preview windows through the existing ffmpeg recipe renderer.

## Boundaries

This folder does not own paid generation, upload, publishing, Drive sync,
platform scheduling, or external connector work. Those remain founder-approved
harness or automation steps outside the edit desk.
