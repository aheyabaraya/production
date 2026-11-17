---
name: idol-grid-overlay
description: |
  Use only when the founder explicitly asks to use/call the IDOL grid overlay skill, says "idol-grid-overlay", "그리드 스킬", or asks for this saved grid workflow by name. Do not use automatically for ordinary image editing, storyboard grids, layout grids, or generation work.
---

# IDOL Grid Overlay

Use this isolated utility skill only when the founder explicitly calls for the saved
grid overlay workflow. It is not part of the production graph-engineering route and must not be
auto-wired into 02A, 02B, review, generation, or CF-code flows.

## Read / Write Contract

- Status: active isolated utility.
- Required reads: this `SKILL.md` and the provided local input image path(s).
- Allowed outputs: `INPUT_STEM-grid-6x6.png` next to the source image, or the
  explicit founder-provided output path.
- Forbidden outputs: modified originals, generated images, external uploads,
  run, catalog, or package registry updates, or graph-engineering stage artifacts.
- Registry behavior: none by default.
- Founder gates: explicit founder call is required; separate approval is needed
  for any registry, external sync, or non-overlay image work.

## Job

Create a visible white grid overlay on one or more local image files while leaving
the original image untouched.

Default output:

```text
INPUT_STEM-grid-6x6.png
```

Default grid:

```text
columns: 6
rows: 6
line color: white
line width: 14 px
line opacity: 245/255
outer border: included
```

## Workflow

1. Confirm the input file path exists.
2. Use the bundled script in this skill instead of rewriting ad hoc image code.
3. Save the output next to the source image unless the founder gives an explicit
   output path.
4. Show the generated image back to the founder.
5. If the founder asks for thicker or thinner lines, rerun only with a changed
   `--line-width`; keep the grid count unchanged unless requested.

## Script

Run from the IDOL repository root or pass absolute paths:

```bash
scripts/idol-video-python skills/idol-grid-overlay/scripts/apply_grid_overlay.py \
  path/to/image.png \
  --cols 6 \
  --rows 6 \
  --line-width 14
```

Multiple files are allowed:

```bash
scripts/idol-video-python skills/idol-grid-overlay/scripts/apply_grid_overlay.py \
  image-a.png image-b.png \
  --line-width 14
```

Use `scripts/idol-video-python --check` if the launcher reports a missing image
dependency. Do not fall back to bare `python3` or install packages into a random
system Python during IDOL repo work.

## Boundaries

- Do not call image generation APIs.
- Do not alter the original image.
- Do not attach or upload the image externally.
- Do not promote the output into active run, asset, catalog, or package registries
  unless the founder separately asks for that registry work.
- Do not use this skill as a substitute for 02A storyboard layout, 02B prompt
  packets, imagegen validation, or post-review video prompt work.
