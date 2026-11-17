# Grok / Handoff Connection Map

Status: active orientation note
Updated: 2026-07-12 KST

This file lists where IDOL can connect to Grok, Grok Imagine, and manual
handoff surfaces. These routes are dormant by default. Codex should write or
refresh Grok/Drive handoff material only when the founder explicitly asks for
Grok, Grok Imagine, Grok TUI/CLI, or Drive handoff. Canonical source remains in
run folders, schemas, and skills. Drive copies are transport only.

Write guard: Grok/Drive handoff scripts require `--founder-requested` with
`--write`. Dry checks may run without it.

## Active Song-Led Connections

- `handoff/grok/current.md`
  - current Grok handoff pointer for the active manual transfer.
- `handoff/grok/archive/`
  - preserved historical current-handoff snapshots. Do not load by default;
    open only for archive recovery, audit, or debugging.
- `handoff/grok/flows/02B/image-prompts/GROK-IMAGE-LOCAL-SOURCE.md`
  - provider-neutral 02B still-image execution route for Founder-requested
    Grok `/image` image-to-image work. It consumes the run-owned
    `idol_image_generation_request.v10` projection, attaches the exact
    hash-bound references in order, and pastes the approved model-authored
    prompt without rewriting it.
- `handoff/grok/flows/03-review/video-prompts/`
  - post-review video prompt route. Codex authors by default with
    `idol-video-prompt`; Grok is optional only when the founder asks.
- `handoff/grok/flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md`
  - single execution runbook for Grok CLI/app/TUI when it must open the repo
    and write one `idol-video-prompt` cue at a time. Older video-prompt request
    packets and paste triggers should point here instead of repeating the
    workflow.
- `handoff/grok/README-video-prompts.md`
  - current video prompt rules and optional Grok execution order.
- `handoff/grok/references/video-prompt-source-rules.md`
  - source priority for video prompt work.
- `drive-sync/02_GPT_GROK_HANDOFF/`
  - manual transfer route for Grok/GPT. Do not treat it as source of truth, and
    do not refresh it unless the founder asks for a handoff.
- `drive-sync/02_GPT_GROK_HANDOFF/00_ASSET_CONTEXT/`
  - controlled asset context mirror refreshed for LLM/Grok handoffs.

## Active Scripts

- `scripts/idol_founder_pass_harness.rb`
  - validates founder review pass. It skips Grok/Drive staging by default.
    Use `--sync-grok-imagine --founder-requested` only on founder request.
- `scripts/idol_prepare_video_prompt_authoring.rb`
  - prepares the common hash-bound 03V source snapshot and source pack used by
    both Codex authoring and optional Grok handoff.
- `scripts/idol_prepare_grok_video_prompt_handoff.rb`
  - creates optional Grok request and paste-trigger files only after reusing
    the common 03V source snapshot/source-set digest and validating the Grok
    reference pack schema.
- `scripts/idol_prepare_image_generation_request.rb`
  - builds a read-only provider-adapter request from one approved 02B packet.
    The Grok adapter preserves prompt bytes, attaches visible-face identity
    inputs first, and then follows exact visual-reference order; the script
    never executes generation or authors creative prompt text.
- `scripts/idol_video_prompt_drive_sync.rb`
  - historical evidence-only v3-index mirror. It is not an active v8 prompt
    transport and must not be run for new work.
- `scripts/idol_asset_drive_sync.py`
  - refreshes `00_ASSET_CONTEXT` for LLM/Grok handoffs.

## Active Schemas / Fields

- `schemas/review.schema.json`
  - keeps legacy `grok_video_prompt_*` field names for compatibility. New
    meaning is post-review video prompt authoring, with Grok optional.
- `schemas/grok-video-prompt-reference-pack.schema.json`
  - optional Grok video prompt projection of the common 03V source snapshot,
    including compact per-cue motion/camera controls and the absent-dance
    omission policy.
- `schemas/image-generation-request.schema.json`
  - provider-neutral derived still-image execution request used by Grok
    `/image` and the existing OpenAI preflight adapter without changing 02B
    creative truth.
- `schemas/generation-map.schema.json`
  - allows `grok_imagine` as a generation engine target.
- `schemas/creative-nucleus.schema.json`
  - allows Grok as an input/source or generation route when explicitly selected.

## Active Run-Specific Connections

- `runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL/handoff/02-03-grok-imagine-v12-webp/`
  - canonical run-owned Grok Imagine handoff source package. External handoff
    packets should extract the key cue board, cue sheet, prompt, identity, and
    action summary from here instead of dumping unrelated source material.
- `runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL/handoff/review-to-grok-handoff-aurora-m-full-code-root-signal.json`
  - optional Grok video prompt wrapper report.
- `runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL/handoff/grok-video-prompt-reference-pack-aurora-m-full-code-root-signal.yaml`
  - optional Grok/Codex video prompt source-pack manifest.
- `runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL/handoff/04S-section-v4-grok-video-prompt-request.md`
  - section-specific Grok video prompt request; treat as run-owned request
    context, not a Drive sync source.
- `handoff/grok/video-prompts.md`
  - copy-paste bridge only. Canonical prompt files stay under the run folder.

## Handoff Content Rule

When a founder-requested Grok handoff is prepared, pass only a compact brief:

- task and exact requested output
- run-owned canonical source paths
- cue board / cue sheet / index pointers
- selected prompt or cue rows
- required identity references
- explicit do-not-do rules

For still-image `/image` work, pass the run-owned
`idol_image_generation_request.v10` artifact rather than the entire 02A/02B
files. For 03V video-prompt work, pass the Grok reference pack that reuses the
common `03v-source-snapshot` source-set digest and one compact cue row at a
time. Actual reference or passed Official Core/Branch Production Cut originals
stay hash-bound and must be inspected; compact handoff does not mean
function-only reference reduction.

Keep broad research folders, raw ledgers, old prompt drafts, unrelated
run notes, and full source prose out of the request packet unless the founder asks
for an archive-recovery/debug task.

For post-review video prompt handoff, the compact brief and paste trigger must
defer detailed execution to
`handoff/grok/flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md`.
Do not keep parallel Grok CLI source-order instructions in Drive packets,
templates, README files, or generated request prose.

## Frozen CF Boundary

CF-code remains frozen under `AGENTS.md`. Its archived instructions and
compatibility paths do not open a current Grok route. Do not route CF work
through song/MV handoff surfaces.

## Retired Label Notes

- `scripts/idol_review_to_grok_handoff.rb` is a fail-closed historical entry;
  current optional 03V transport uses the written source pack with
  `scripts/idol_prepare_grok_video_prompt_handoff.rb`.
- `scripts/idol_grok_imagine_drive_sync.py` is historical pre-Branch-Cut
  staging, not an active preparation route.

- Old retired skill names (mv/stage labels) are no longer used
  historical labels only. Do not look for active skills at those names, and do
  not record them as new `selected_skill` values.
- Retired Drive handoff copies live under `drive-sync/99_ARCHIVE/`.
- Social/SNS packages no longer use `drive-sync`; the SNS automation should
  point to run-owned package/export paths and check upload state through Social
  Pulse / analytics ledgers.
