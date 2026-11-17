# 04VFX Manual Use And Runtime Management

This is the operating note for the optional `idol-shot-vfx` specialist loop.
It is not a schema, stage contract, effect registry, or automation surface.

## Manual Shot Note

Create `04vfx-shot-note.md` beside the shot project and keep these headings in
plain language:

```markdown
# 04VFX Shot Note — SHOT_ID

## Locked 04 window
- run and section:
- Edit Segment:
- recipe path and SHA-256:
- passed preview path and SHA-256:
- source path and SHA-256:
- output start/end frames, FPS, geometry, duration:
- available source handles:

## Founder input and reference
- verbatim effect/reference/situation:
- exact reference path/locator and SHA-256:
- governing action, camera, composition, material, and sequence grammar:
- elements replaced for the current title:

## Shot design
- visible object/subject state at entry:
- observable VFX action:
- camera/object spatial relation:
- light, material, shadow, reflection, and occlusion behavior:
- environment response:
- exact endpoint and handoff back to the edit:
- 04FX finishing, if any, to defer until after 04 reinsertion:

## Runtime and cache identity
- media-runtime check date/result:
- Blender executable/version or missing hold:
- Add Camera Rigs version/module/source commit/package SHA-256 or missing hold:
- project/script/source hashes:
- preview engine, resolution, samples, FPS, color/alpha settings:
- cache fingerprint and reused/rebuilt reason:

## Review
- reference-versus-shot strip:
- short preview:
- identity/body/world/track/flash/technical QC:
- decision: PASS | HOLD | REJECT
- concrete reason:
- passed export path and SHA-256:
- 04 re-intake status: not_started | returned_to_04 | accepted_by_04
```

The note is authored by the assigned model or human. Utilities may calculate
hashes and measurements but may not fill the design or review decision.

## Working And Review Loop

1. Copy or link only the exact source/reference bytes needed for the shot.
2. Make a still or sparse contact sheet before a moving render.
3. Render a short proxy around the effect window.
4. Compare reference and output at the same temporal cadence when possible.
5. Change one observable variable at a time: timing, position, scale, material,
   camera relation, light, or environment response.
6. Render a longer or higher-quality version only after the proxy passes.
7. Export a passed clip with exact 04 FPS, geometry, duration, frame count, and
   color/alpha interpretation.
8. Return it to 04 source intake; never splice it directly into the master.

## M1 8GB Preview Defaults

- Work one shot at a time and close unrelated memory-heavy applications.
- Begin with Workbench or EEVEE-class previews; do not default to Cycles.
- Use low resolution, short windows, low samples, simple geometry, bounded
  texture sizes, and disabled nonessential modifiers/simulations.
- Prefer baked or cached bounded motion over live dense simulation.
- Increase resolution, samples, texture size, or render length one dimension at
  a time after approval.
- Treat full characters, dense cities, long fluid/cloth/destruction simulation,
  and high-sample Cycles as `external_or_heavy_hold` unless a local test proves
  feasibility.

These are working defaults, not a promise that every shot will fit in memory.

## Runtime Sources Of Truth

| Concern | Active owner | Rule |
| --- | --- | --- |
| IDOL media Python interpreter | `.venv-video/bin/python` through `scripts/idol-video-python` | Never substitute bare system `python3` for media work |
| Python package pins | `requirements-video.txt` | Rebuild `.venv-video` from this file; do not hand-install an unrecorded fix |
| ffmpeg/ffprobe | executable paths reported by `scripts/idol-video-python --check` | Missing executable is a local-runtime hold |
| Blender | separately installed macOS application | Record executable path and version in the shot note; do not merge its embedded Python with `.venv-video` |
| Camera explanation rig | Blender extension `add_camera_rigs` | Project already-authored 01/02A/03V camera truth only; never infer or replace it |
| 04VFX creative truth | `04vfx-shot-note.md` written by the assigned human/model | No schema or script authors the design or PASS decision |

Use these checks before actual shot work:

```text
scripts/idol-video-python --check
command -v ffmpeg
command -v ffprobe
command -v blender
/Applications/Blender.app/Contents/MacOS/Blender --version
/opt/homebrew/bin/blender --background --python-expr 'import bpy; keys=[k for k in bpy.context.preferences.addons.keys() if "camera_rig" in k]; built=bpy.ops.object.build_camera_rig(mode="DOLLY"); cam=bpy.context.scene.camera; cam.data.show_composition_thirds=True; print("IDOL_CAMERA_RIG_INSTALLED", keys, built, cam.name, cam.data.show_composition_thirds)'
```

The Blender commands are checks only. Do not install or update Blender as a
side effect of preflight.

## Verified Local Snapshot — 2026-08-01

- `scripts/idol-video-python` resolves `.venv-video/bin/python` at Python
  `3.12.13`.
- All 12 exact pins in `requirements-video.txt` match the installed media
  environment.
- ffmpeg and ffprobe resolve from `/opt/homebrew/bin`.
- MoviePy, OpenCV, Pillow, NumPy, SciPy, librosa, soundfile, imageio,
  imageio-ffmpeg, matplotlib, PyYAML, and jsonschema are available through the
  wrapper.
- The wrapper keeps XDG, matplotlib, and pip caches under the ignored
  `.runtime/cache` tree so restricted sessions do not fall back to unwritable
  user cache directories.
- Blender `5.2.0` is installed at `/Applications/Blender.app` and resolves as
  `/opt/homebrew/bin/blender`. The background factory-startup smoke test passes.
- `Add Camera Rigs` `1.8.2` is installed and enabled as
  `bl_ext.user_default.add_camera_rigs`. A default-user Blender `5.2.0` smoke
  test creates `Dolly_Camera` and enables the thirds composition guide.

This snapshot is evidence for the stated date, not a permanent capability
claim. Re-run the checks before each new VFX session.

## Add Camera Rigs Install Lock

- Extension id: `add_camera_rigs`
- Installed version: `1.8.2`
- Minimum declared Blender version: `4.2.0`
- License: `GPL-3.0-or-later`
- Source: `https://github.com/waylow/add_camera_rigs`
- Audited source commit: `2fb7b36d52dddc79185de05eb4f87f6aa9e28f7d`
- Locally built install-package SHA-256:
  `7c85d8cd724c58fd7f40220c906864707d3e28b0ff1e80707960b6723af849ca`
- Installed manifest SHA-256:
  `2a6d354349829b5f65e68aeb10a06433bd9094e55ebeb7ee78cbc1d4fa56a85d`
- Installed path:
  `/Users/yuminseog/Library/Application Support/Blender/5.2/extensions/user_default/add_camera_rigs`

The 2026-08-01 source audit found only Blender API, `mathutils`, and standard
math imports. It found no network client, subprocess/external-command call,
file-removal routine, updater, or upload path in the audited Python/TOML files.
The package was built with Blender's extension builder, validated, installed
into the `user_default` extension repository, and enabled without turning on
Blender's global online-access preference.

This lock approves only the installed camera-explanation helper. It grants no
automatic update, remote sync, asset download, creative camera authorship,
render PASS, or master inclusion. A version, source-commit, package, permission,
or Blender-major change requires a fresh audit, smoke test, and current-task
Founder approval before the lock is revised.

## Package Distribution Audit

The top-level IDOL media environment is centralized: one `.venv-video`, one
`requirements-video.txt`, and one launcher.

1. `matplotlib==3.10.9` is now an exact top-level media pin and a required
   `scripts/idol-video-python --check` module. The previously failing
   `idol_candidate_audio_probe.py` process-start import is restored without
   using bare system Python.
2. `cf/.venv-imagegen` remains intentionally separate from song/MV media work,
   but its complete installed package set is now reproducible from the exact
   pins in `cf/requirements-imagegen.txt`. Do not merge it into `.venv-video`.

The historical OpenAI batch scripts also import the OpenAI SDK, but they are
declared inactive/legacy in `scripts/README.md`; their SDK is not an active
04VFX media-runtime requirement.

## Linkage Audit

This management note must remain directly linked from:

- `skills/idol-shot-vfx/SKILL.md` as a required read;
- `skills/idol-editing-qc/SKILL.md` for 04 source return and re-lock;
- `skills/idol-edit-finishing-fx/SKILL.md` for 04FX-versus-04VFX routing;
- `skills/idol-orchestrator/SKILL.md` as the optional manual specialist loop;
- `scripts/README.md` from the Python runtime management section.

If any link disappears, 04VFX is not ready for use even though this file still
exists.
