# GPT Handoff Packet - TITLE 02A Storyboard Review

Status: ready_for_founder_manual_transfer
Created: YYYY-MM-DD KST
Target: GPT / ChatGPT
Owner: Codex prepares, founder reviews/selects
Content ID: `CONTENT_ID`
Title: `TITLE`

## Task

Review the current `TITLE` 02A storyboard before 02B prompt-packet regeneration.
You are providing creative draft/reference input inside the IDOL harness. You
are not the source of truth, not the track's creative owner, and cannot approve
02A, 02B, paid generation, or identity changes.

Focus on:

1. Flag or rewrite beats whose review sentence is too abstract or not drawable.
2. Check the exact lyric cue or no-lyric cue together with the lyric function;
   do not review from section labels alone.
3. Check whether space/background, wardrobe, member action, rhythm cue, gaze, and
   camera still match the locked song message and the actual words being sung.
4. When revising camera, write it at 02A-patchable detail: shot scale, camera height,
   front/side/three-quarter/low-angle view, tracking/push/hold or still-image
   equivalent, member-to-space balance, and why the framing makes the lyric/action
   readable.
5. If a supplied reference image should influence the storyboard, state which
   beat(s) and scene role it targets, what to preserve, and what to discard.
6. Suggest concrete `pass`, `hold`, or `revise` changes.

## Locked Context

- Core message:
- Track length / cut:
- Active unit:
- Founder visual lock, if any:
- Founder-provided reference images, if any:
- Current stage: 02A founder review, before 02B, before paid generation.
- GPT output is advisory until founder selection and Codex intake.
- Reference images in this pack are temporary review inputs. Selected images
  will be copied into a run-owned `review/02a-reference-intake-vN/` artifact
  before Codex can patch 02A.

## Source Pack

Use the attached source pack. For album/title song work, the preferred Drive
lane is:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/source-pack-vN/
```

Returned notes, images, manifests, or alternates should go to:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/incoming/
```

Codex-normalized summaries back to GPT/Grok/Drive go to:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/outgoing/
```

Required files:

```text
01-current-02a-founder-review.md
02-current-02a-master-storyboard.yaml
04-audio-analysis-vN.md
05-audio-motion-director-map-vN.yaml
09-01r-mv-direction-reference-mining-vN.yaml
11-wardrobe-style-review-vN.md
18-founder-visual-reference-vN.md
founder-image-refs/*
wardrobe-image-refs/*
storyboard-preview-vN/*
member-refs/*
```

Use 00/00A/01/02, registries, and voice/style references for lock checking.
If a founder-provided visual lock conflicts with older source files, keep the
timing, member roles, and action logic from the older files. Apply the founder
visual lock only to compatible 02A-level space, camera, blocking, wardrobe
readability, mood, and avoid-list decisions. If the reference would change song
meaning, member owner, core action/action type, MV world, wardrobe lane, or
section `director_chain`, mark it as a route-back item for 01 or 01A instead of
writing it as a 02A-only patch.

## Concrete Language Rule

Use observable screen language first.

Every revised screen-proof sentence should answer:

```text
who is visible / where they are / what body or object action happens /
which rhythm or lyric cue triggers it / what the face or gaze does /
how the camera sees it
```

Do not leave abstract or undefined terms as the only screen direction. An
explanatory `issue` may describe the directorial purpose naturally, but
`revised_sentence` and affected patch fields must translate it into visible
behavior.
If camera changes are suggested, do not write only "dynamic", "cinematic", or
"camera-readable"; name shot scale, camera height, angle, movement/hold,
member-to-space balance, and framing reason so Codex can patch 02A first.
For reference-image analysis, use existing IDOL field names where possible:
`camera_height`, `camera_angle_or_direction`, `shot_scale`,
`camera_treatment`, `framing_reason`, `member_blocking`,
`required_body_evidence`, `required_camera_evidence`, `space_or_object`,
`crop_safe_center_rule`, `visible_action`, and `action_carry_guard`.

## Output Format

```yaml
overall_read:
  pass_hold_or_revise:
  main_reason:

beat_reviews:
  - beat_id:
    time_range:
    status: pass | hold | revise
    issue:
    revised_sentence:
    space_change:
    wardrobe_or_identity_check:
    rhythm_check:
    camera_specificity_check:

reference_image_intake:
  - reference_id:
    source_filename:
    target_beats:
    target_scene_role:
    identity_priority: identity_first
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
      -
    patch_target:
      - 02A.visual_frame.camera_treatment
      - 02A.director_scene_lock.required_body_evidence
      - 02A.director_scene_lock.required_camera_evidence
      - 02A.director_chain.visible_action
      - 02A.director_chain.must_show.camera

space_recommendations:
  - target_beats:
    current_space:
    proposed_space:
    why_it_fits:
    concrete_visual_actions:
    risks_to_avoid:

must_keep:
  -

must_fix_before_02B:
  -
```

## Do Not Do

- Do not rewrite the song message.
- Do not invent new members, ages, third-party identity comparisons, or identity traits.
- Do not approve paid generation, publishing, upload, or scheduling.
- Keep reference artists' source identity, outfits, choreography, lyrics, set, logo, or branding as source provenance.
- Do not leave abstract phrasing as the only screen direction. In
  `revised_sentence` and affected patch fields, name the visible action and
  camera detail needed for a 02A patch.

## Cleanup

This source pack is temporary. After founder-selected changes are patched into
02A and 02B regeneration starts, delete the temporary drive-sync source pack
only. Keep all run-owned source files. Do not overwrite returned files in
`incoming/`; Codex copies only founder-selected reference material into the
run-owned review intake folder before patching 02A.
