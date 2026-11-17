# 02A GPT Review Flow

Use this flow when the founder wants to continue a 02A storyboard review in GPT
or another general LLM through `drive-sync`.

## Position In Harness

This flow belongs here:

```text
02A -> 02A_preview_review -> optional GPT LLM review -> Codex intake
-> patched 02A -> 02B
```

The GPT review does not replace the IDOL harness. It is a creative
draft/reference input surface for the founder and Codex, not the track's
creative owner and not a source of truth. GPT output is advisory until the
founder selects changes and Codex patches the run-owned source files.

This pass may patch 02A only when the selected change refines beat-level camera,
framing, body level, blocking, crop safety, space/object detail, wardrobe
readability, or action carry guard inside the existing 01-owned direction. If a
GPT/reference suggestion changes song meaning, member ownership, core
action/action type, MV world, wardrobe lane, or section `director_chain`, route
back to 01 or 01A before continuing downstream.

## Album-Scoped Source Pack Location

Create one temporary pack under the album/title handoff lane when `album_key`
and `title_key` are known:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/source-pack-vN/
```

Use the album/title key, not the date, as the active identity. Example:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/source-pack-v1/
```

Returned GPT/Grok/founder material for the same title should land beside it:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/incoming/
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/outgoing/
```

`incoming/` is for returned notes, images, manifests, and alternatives that
Codex has not canonicalized. `outgoing/` is for Codex-normalized response
packets, revised compact source packs, or founder-facing handoff summaries that
need to go back to GPT/Grok/Drive.

The older flat location remains compatibility-only for existing packs and
scripts:

```text
drive-sync/02_GPT_GROK_HANDOFF/TITLE-02a-review-source-pack-vN/
```

If a flat pack is used, record its album/title mapping in
`drive-sync/ACTIVE.md` before starting a two-way review.

## Required Files

Each 02A GPT review pack should include:

- `00-gpt-review-request.md`
- current founder-readable 02A review
- current `02A-master-storyboard.yaml`
- current audio analysis
- current audio motion director map, when present
- current `00`, `00A`, `01`, and `02` source files
- current 01R research, when present
- 01R contact-sheet index or grouped source observation notes, when present
- wardrobe/style review `.md` and `.json`, when present
- wardrobe image references, when present
- founder-provided moodboards, visual boards, outfit boards, image references,
  or concrete visual-lock notes created during review
- current 02A preview contact sheets, when present
- active member registry, unit registry, and voice-style index
- active unit face references and character boards when the founder wants GPT to
  review identity or says to include all review materials

Do not include stale 02B prompt packets unless the task is explicitly to compare
old 02B against the new 02A. In normal 02A review, 02B is a downstream artifact
and should be regenerated after the selected 02A changes.

## Request Rules

The GPT request must say:

- review stage is 02A, before 02B, before paid generation
- core song message and title
- active unit
- current founder-selected revisions
- exact lyric cue or no-lyric cue must be reviewed together with lyric function;
  GPT must not review from section function labels alone
- any founder-provided visual lock or reference image that overrides older
  space, wardrobe, or mood assumptions
- any reference-image change that touches song meaning, member owner, core
  action/action type, MV world, wardrobe lane, or section `director_chain` must
  be routed back to 01 or 01A, not patched only in 02A
- concrete language rule: who, where, visible action, rhythm or lyric cue, gaze,
  and camera
- camera checks should be concrete enough to patch 02A before 02B: shot scale,
  camera height, front/side/three-quarter/low-angle view, tracking/push/hold or
  still-image equivalent, member-to-space balance, and framing reason when a
  beat is revised
- no abstract placeholders or undefined music/film jargon
- space/background issue to inspect
- exact return format for `pass`, `hold`, and `revise`
- GPT output is advisory until founder selection and Codex intake
- GPT/reference images are draft/reference inputs; selected images must be
  copied into a run-owned intake artifact before they can patch 02A

## Cleanup Rule

The drive-sync source pack is temporary. When the founder passes the 02A review
and Codex starts 02B prompt-packet regeneration, delete only the matching
`source-pack-vN/` folder from the album/title lane. If a legacy flat
`TITLE-02a-review-source-pack-vN/` folder or matching `.zip` upload copy was
used, delete only that temporary copy too.

Only delete the drive-sync copy. Never delete the run-owned source files under
`runs/`, active assets under `assets/`, source materials, schemas, or harness
docs as part of this cleanup. Returned material under `incoming/` remains draft
handoff material until it is either copied into a run-owned intake artifact or
explicitly archived.

## Returned Reference Image Intake

GPT-returned images, image manifests, and founder-selected reference boards may
arrive in drive-sync first, but drive-sync remains temporary. Before using a
reference image as a canonical 02A patch source, copy the selected file into:

```text
runs/YYYY-MM-DD/CONTENT_ID/review/02a-reference-intake-vN/
```

Create an intake manifest beside the copied files:

```yaml
source_surface: gpt_reference_input
source_drive_sync_path:
run_owned_copied_path:
image_sha256:
target_beats: []
target_scene_role:
identity_priority: identity_first
patch_target:
  - 02A.visual_frame.camera_treatment
  - 02A.director_scene_lock.required_body_evidence
  - 02A.director_scene_lock.required_camera_evidence
  - 02A.director_chain.visible_action
  - 02A.director_chain.must_show.camera
preserve_exact:
  camera_height:
  camera_angle_or_direction:
  shot_scale:
  camera_treatment:
  framing_reason:
  member_blocking:
  required_body_evidence:
  required_camera_evidence:
  space_or_object:
  crop_safe_center_rule:
preserve_action:
  visible_action:
  action_carry_guard:
discard:
  - visible text
  - storyboard layout
  - GPT face identity
  - wrong member count
  - exact outfit copy unless founder explicitly locks it
founder_target_selection:
  status: selected | candidate_only
  note:
```

If `founder_target_selection.status` is `candidate_only`, Codex may list
candidate beats and scene roles, but must not patch 02A. Once the founder
selects the target beat/scene role, translate the selected reference into the
existing 02A fields, preserving timing/member/action logic from current run
files and applying the reference only to compatible space, camera, blocking,
body-level, reflection/depth, crop-safe, and avoid-list decisions.
If the selected reference changes 01-owned direction instead of refining 02A
beat-level execution, patch 01 or 01A first and regenerate the affected
downstream artifacts before rebuilding 02B.

## Codex Intake

When GPT returns a review:

1. Save or summarize the GPT output under the run's `review/` folder or
   `handoff/llm/current.md`.
2. For returned images, register founder-selected references under
   `review/02a-reference-intake-vN/`, record hashes and source paths, and keep
   unselected drive-sync images out of canonical 02A patch sources.
3. Compare every suggested change against `AGENTS.md`, schemas, active assets,
   `00`, `00A`, `01`, `02`, and `02A`.
4. Ask the founder to select changes when the GPT output contains alternatives
   or reference images have no target beat.
5. Patch `02A-master-storyboard.yaml` and the founder-readable 02A review first.
6. Validate schemas before 02B.
7. Regenerate 02B only from the selected and patched 02A.
8. When a revised summary needs to go back to GPT/Grok/Drive, write a compact
   Codex-normalized packet under the album/title `outgoing/` folder. Do not
   overwrite the original returned files in `incoming/`.
