Archive note: LOW was discarded by founder on 2026-06-14; LOW-specific observations in this dated file are historical only. Canonical closeout: `runs/2026-05-26/0526_SONG_SELECTION/review/low-discard-closeout-v1.md`.

# IDOL Harness Contract Audit - 2026-06-10

Purpose: audit whether the current IDOL harness supports the main operating
goal: higher efficiency, higher output quality, and lower founder intervention
through local-first automation that still respects founder gates.

Scope:

- skill Required Reads and referenced documents
- schema-backed output contracts
- run/catalog artifact placement rules
- automation/Hermes gate visibility
- current LOW run evidence where it proves or contradicts readiness

## Current Strengths

- The top-level rule stack is clear:
  `AGENTS.md` -> `schemas/**` -> `skills/**/SKILL.md` -> `wiki/**` -> run
  artifacts.
- Core production skills now use concise `SKILL.md` files and directly linked
  `references/**` or `modules/**` files.
- The main song-led contract files have schemas:
  `00`, `00A`, `01`, `01A`, `02`, `02A`, `02B`, `03-review`, `03V`, `04`,
  title output registry, selected-audio analysis, lyrics bridge, cue BPM,
  audio-motion, wardrobe review, and PRE-00 radar.
- Current LOW evidence shows the early/mid core contracts are schema-valid:
  `00`, `00A`, `01`, and `01A` all validate against their schemas.
- The title registry is present and validates:
  `catalog/albums/aurora-m/low/output-registry.yaml`.
- Legacy video-prompt skill names have been reduced to hard stubs and are not
  valid new `selected_skill` values.
- Non-core isolated, social, external-helper, retired, and alias skills now
  expose a standard `## Read / Write Contract` block.
- Purpose-level skill read/write coverage is now machine-auditable:
  `automation/skill-purpose-contract-matrix-2026-06-10.md` reports 10
  harness-core skills, 6 isolated helpers, 3 retired stubs, and 1 compatibility
  alias with zero contract gaps under the current checker. The matrix now has a
  strict mode that exits nonzero when gaps are present.
- Hermes/handoff readiness now points at a validator-backed state report before
  calling LOW canonical-ready.

## Changes Implemented In This Pass

- Added `scripts/idol_harness_state_check.rb`, a local checker that aggregates
  schema validation, specialized validators, catalog validation, and Hermes drift
  detection.
- Generated the current LOW state report:
  `automation/state-reports/2026-06-10-0526_SONG_SELECTION-harness-state.md`.
- Updated `automation/hermes/current-sprint.yaml` and
  `handoff/grok/video-prompts.md` so LOW is labeled as live/manual review only,
  not canonical harness-ready.
- Added `## Read / Write Contract` to:
  `idol-grid-overlay`, `idol-member-teaser-portrait`, `idol-track-poster`,
  `idol-track-key-visual`, `kling`, `reels-tiktok-template`, and `x-posting-template` (retired mv/stage labels fully removed).
- Added `scripts/idol_skill_contract_check.rb`; current result:
  `OK: 20 skill contract(s) checked`.
- Added `scripts/idol_skill_contract_matrix.rb` and generated
  `automation/skill-purpose-contract-matrix-2026-06-10.md` so purpose-specific
  Required Reads, read/write contracts, schema refs, reference/module refs, and
  write boundaries can be checked as a single matrix.
- Added an explicit `## Output Boundary` to `skills/idol-editing-qc/SKILL.md`
  so 04 editing cannot silently write prompt truth or promote previews as final
  edit artifacts.
- Added `scripts/idol_video_prompt_section_qa_worklist.rb` and generated
  `runs/2026-05-26/0526_SONG_SELECTION/review/03v-section-video-prompt-qa-worklist-v1.md`
  plus the schema-backed `.yaml` sidecar.
  The worklist expands blocked 03V section QA into per-section review actions,
  prompt paths, upload-pack paths, source image paths, audio-motion slots, and
  start/end/edit-basis text without marking any QA item as pass.
- Added `scripts/idol_edit_readiness_worklist.rb` and generated
  `runs/2026-05-26/0526_SONG_SELECTION/review/04-edit-readiness-worklist-v1.md`
  plus the schema-backed `.yaml` sidecar.
  The worklist expands the blocked 04 edit state into final-recipe, active
  candidate, section-shard, rough-output, and promotion-guard actions without
  changing edit status or approving any preview as final truth.
- Added `schemas/package.schema.json`, `schemas/publishing-plan.schema.json`,
  and `scripts/validate_publishing_plan.py`; existing Root Signal package and
  publishing plan validate.
- Connected package/publishing-plan checks to
  `scripts/idol_harness_state_check.rb` as optional checks that become blocking
  if the corresponding file exists and fails.
- Reconciled stale review/audio/edit validation conflicts:
  `review/03-generated-keyframe-review-v1.yaml`,
  `research/audio-motion-director-map-v7.yaml`, and `04-edit-map.yaml` now pass
  their schema or dedicated structural validators. `04` readiness is checked
  separately so a structurally valid edit map with no locked final recipe still
  blocks automation.
- Reconciled the active LOW 03V/video-prompt contract split:
  `03V-video-prompt-manifest-v1.yaml` now has schema-valid
  `keyframe_boundary_contract` records derived from existing cue fields,
  `video-prompt-index.yaml` links each Bxx prompt to the appropriate
  audio-motion R-slot, and section QA is structurally valid while remaining
  readiness-blocked for checks that have not actually run.
- Adjusted `scripts/validate_video_prompt_index.rb` so generator-facing prompt
  text is checked for semantic carry-through of concrete terms instead of
  requiring exact YAML field-string inclusion. This keeps natural prompt prose
  compatible with strict harness validation.
- Split readiness checks out of broad validators:
  `scripts/validate_video_prompt_section_qa_readiness.rb` now owns section-QA
  pass/not-run status, and `scripts/validate_edit_map_readiness.rb` now owns
  final-recipe/shard/candidate readiness. The harness state report can now say
  that the 03V index itself passes while section QA and 04 edit readiness remain
  blocked.
- Added blocker-specific `Next Actions` to
  `scripts/idol_harness_state_check.rb` reports so Hermes/orchestration can see
  the next local action without reinterpreting long validator output.
- Added blocker-worklist freshness checks to
  `scripts/idol_harness_state_check.rb`. Current reports now verify that the
  run-owned 03V section-QA worklist and 04 edit-readiness worklist exist and
  are not older than their source artifacts before treating blocker handoff as
  locally actionable.
- Added `schemas/harness-action-queue.schema.json` and
  `scripts/idol_harness_action_queue.rb`, then generated
  `automation/action-queues/2026-06-10-0526_SONG_SELECTION-harness-action-queue.yaml`
  and `.md`. The queue compresses the current state report, blocker worklists,
  and Hermes founder gates into ordered local actions while keeping forbidden
  actions explicit.
- Added `scripts/idol_harness_refresh.rb` as the single local refresh path for
  harness diagnostics. It regenerates the state report, refreshes blocker
  worklists, regenerates the action queue, and validates the worklist/action
  queue schemas without changing any production approval state. A valid refresh
  may still report `archived_blocked_reference` when readiness validators are correctly
  blocking the run.
- Added `schemas/harness-blocker-worklist.schema.json` and wired both blocker
  worklist scripts to write Markdown for operators plus YAML for automation.
  The state checker now validates these structured worklists; current LOW
  harness state is `pass=25`, `fail=2`, `missing=5`, `blocking=2`.
- Expanded `schemas/harness-action-queue.schema.json` and
  `scripts/idol_harness_action_queue.rb` so each blocker queue item now carries
  structured `worklist_summary` and `next_units`. The action queue no longer
  only links to a worklist; it exposes the next 03V section QA units and 04
  recipe/shard/rough-output units directly while preserving founder gates.
- Added `schemas/harness-next-unit.schema.json` and
  `scripts/idol_harness_next_unit.rb`, then wired the refresh wrapper to emit
  `automation/next-units/2026-06-10-0526_SONG_SELECTION-harness-next-unit.yaml`
  and `.md`. The artifact selects the first non-founder-gated unit from the
  highest-priority blocker queue; it initially selected
  `close_03v_section_qa:S00`. After local S00-S03 source/prompt QA closure, the
  selector now stops at `front_03v_playback_gate:S00-S03` instead of forcing broad
  S04+ QA immediately. Automation can resume at one concrete unit or front-chunk
  gate instead of rereading the whole queue.
- Closed the local source/prompt QA portion of 03V `S00`. `S00` is now
  `partial`: start/end keyframe audio alignment, previous/next continuity,
  two-image exception review, clip-duration fit, motion/camera fit,
  space/object reaction, story progression, and person-only risk all pass from
  run-owned image/prompt/audio sources. `generation_playback_probe` remains
  `archived_low_discarded`, so the selector now skips that founder-gated unit and moves
  the next local resume target to `close_03v_section_qa:S01`.
- Closed the local source/prompt QA portion of 03V `S01` for B02-B04. `S01` is
  now `partial`: all local image/prompt/audio checks pass from the actual
  two-image upload packs, `PACK_INDEX`, selected-audio S01 analysis, R02
  audio-motion slot, 03V manifest, root prompts, and upload `prompt.txt` files.
  `generation_playback_probe` remains `archived_low_discarded`, so the next non-founder
  resume target is now `close_03v_section_qa:S02`.
- Closed the local source/prompt QA portion of 03V `S02` for B05-B08. `S02` is
  now `partial`: all local image/prompt/audio checks pass from the actual
  two-image upload packs, `PACK_INDEX`, selected-audio S02 analysis, R03
  audio-motion slot, 03V manifest, root prompts, upload `prompt.txt` files,
  contact sheet, and actual image1/image2 pixels. `generation_playback_probe`
  remains `archived_low_discarded`, so the next non-founder resume target is now
  `close_03v_section_qa:S03`.
- Closed the local source/prompt QA portion of 03V `S03` for B09-B12. `S03` is
  now `partial`: all local image/prompt/audio checks pass from the actual
  two-image upload packs, `PACK_INDEX`, selected-audio S03 analysis, R04
  audio-motion slot, 03V manifest, root prompts, upload `prompt.txt` files,
  contact sheet, and actual image1/image2 pixels. `generation_playback_probe`
  remains `archived_low_discarded`.
- Adjusted `scripts/idol_harness_next_unit.rb` so a contiguous front 03V chunk
  with local source/prompt QA closed stops at a founder playback/generation gate
  instead of automatically selecting the next unfinished section. Current LOW
  next unit is `front_03v_playback_gate:S00-S03`; `S04` remains the next local
  section only if the founder chooses to continue broad section QA before front
  chunk playback/generation review.
- Promoted that front-chunk stop into structured automation state:
  `scripts/idol_video_prompt_section_qa_worklist.rb` now records
  `front_playback_gate_ready`, section range, minimum section threshold, packet
  count, and next local section in the 03V worklist summary;
  `scripts/idol_harness_action_queue.rb` can emit a 03V-only queue with
  `--only-check video_prompt_section_qa_readiness` and prepends
  `front_03v_playback_gate:S00-S03` before any broad S04+ QA unit.
  The current 03V-focused queue is
  `automation/action-queues/2026-06-10-0526_SONG_SELECTION-03v-action-queue.yaml`,
  and the next-unit artifact uses that queue so edit worklists are not refreshed
  by the 03V continuation path.
- Tightened the 03V-focused action queue so
  `--only-check video_prompt_section_qa_readiness` no longer invokes the full
  harness state checker first. The focused queue now reads the structured 03V
  section-QA worklist plus Hermes active context, records
  `source_state_report: focused_03v_queue_no_state_report`, and keeps the
  selected next unit at `front_03v_playback_gate:S00-S03`. The focused action
  queue also has a safe default output path:
  `automation/action-queues/YYYY-MM-DD-CONTENT_ID-03v-action-queue.yaml`, and
  `idol_harness_next_unit.rb` can discover the newest 03V-focused queue without
  requiring a long `--action-queue` argument.
- Added `schemas/harness-founder-gate.schema.json` and
  `scripts/idol_harness_founder_gate_packet.rb` so a founder-required next unit
  becomes a compact decision packet instead of a file-hunting task. Current LOW
  emits
  `automation/founder-gates/2026-06-10-0526_SONG_SELECTION-03v-front-gate-s00-s03.yaml`
  and `.md`, listing the allowed routes: approve S00-S03 generation/playback
  scope, review/refine prompts only, continue local S04 QA, or hold the gate.
  The packet remains explicit that no QA pass, paid generation, external
  execution, publishing, Drive mutation, or wider-scope approval is inferred.
- Added `scripts/validate_03v_front_playback_gate.rb` as a read-only regression
  check for that focused path. It verifies the worklist front-gate summary, the
  first 03V action-queue unit, the next-unit selection, founder-gate ownership,
  the founder gate packet source links, the allowed decision ids and flags, the
  no-state-report marker, and the absence of full-state/edit/full-refresh
  commands from focused 03V refresh commands. This makes the founder-facing
  decision packet a checked contract, not only a Markdown convenience surface.
- Connected the skill contract checks to `scripts/idol_harness_state_check.rb`.
  Current state reports now include `skill_path_contracts` and
  `skill_purpose_contract_matrix` as blocking harness checks before run-level
  readiness is considered. In the current LOW report both pass, the blocker
  worklists are current, and the action queue is schema-valid while 03V section
  QA and 04 edit readiness remain blocked. The current structured blocker
  worklists are also schema-valid.
- Hardened `scripts/validate_edit_map_readiness.rb` and the matching state
  checker status logic so underscore-separated values such as
  `front_overhaul_v8_rendered_archived_low_discarded_playback_review` and
  `founder_rejected_unrecoverable_music_video_mismatch` are caught as
  non-ready/rejected states.

## Main Problems

### 1. Some output families are not schema-backed

The skill-level read/write-contract gap is closed for the audited skill set.
The remaining contract issue is output families that are intentionally or
temporarily described in prose but do not yet have first-class schemas.

These outputs are still prose-governed:

- `research/suno-prompt-packet-vN.md`
- track poster/key visual outputs
- member teaser portrait outputs

This is manageable while they remain manual or isolated, but it limits
minimum-intervention automation. Automation can verify "file exists" or "text
mentions the right things", but it cannot reliably decide readiness.

Recommended fix order:

1. Add a lightweight `schemas/suno-prompt-packet.schema.json` only if Suno
   prompt packets are repeatedly being reused by automation.
2. Keep poster/teaser isolated unless founder explicitly wants them wired into
   album release automation.

### 2. Active LOW downstream readiness is blocked by current validators

Current state-check evidence:

- Pass:
  - `skill_path_contracts`
  - `skill_purpose_contract_matrix`
  - `review/03v-section-video-prompt-qa-worklist-v1.md` freshness
  - `review/03v-section-video-prompt-qa-worklist-v1.yaml` schema
  - `review/04-edit-readiness-worklist-v1.md` freshness
  - `review/04-edit-readiness-worklist-v1.yaml` schema
  - `automation/action-queues/2026-06-10-0526_SONG_SELECTION-harness-action-queue.yaml`
  - `00-creative-nucleus.yaml`
  - `00A-song-lock.yaml`
  - `01-song-choreography-performance-mv-map.yaml`
  - `01A-track-visual-board.yaml`
  - `selected-audio-analysis-v1.yaml`
  - `lyrics-direction-bridge-v1.yaml`
  - `research/audio-motion-director-map-v7.yaml`
  - `03V-video-prompt-manifest-v1.yaml`
  - `review/03-generated-keyframe-review-v1.yaml`
  - `04-edit-map.yaml` schema only
  - `generations/video-prompts/video-prompt-index.yaml`
  - `review/03v-section-video-prompt-qa-v2.yaml` schema only
  - `wardrobe-style-review-v2.json`
  - `catalog/albums/aurora-m/low/output-registry.yaml`
- Fail:
  - `review/03v-section-video-prompt-qa-v2.yaml` readiness
  - `04-edit-map.yaml` readiness

The failures are not cosmetic. They directly affect automation:

- `video-prompt-index.yaml` is structurally linked and prompt carry-through now
  validates. Canonical readiness remains blocked by
  `video_prompt_section_qa_readiness` because section QA has `not_run` checks
  for start/end keyframe audio alignment, clip-duration music fit, motion
  speed/expression/camera fit, space/object reaction, story-spine progression,
  person-only risk, and generation playback probe.
- `04-edit-map.yaml` is structurally valid, but readiness fails because no
  `manual_adjustment_workflow.current_final_recipe` is locked, the top-level
  edit status records rejected/unrecoverable source mismatch, the active
  candidate still needs founder/playback review, seven section shards are not
  ready for merge, and current rough outputs remain review, timing-test, or
  rejected evidence rather than final edit truth.

Recommended fix: canonical readiness should stay blocked until these validators
pass or the artifacts are marked `legacy/live_unreconciled` under a controlled
status.

### 3. Live Grok/Drive hot-copy mode is useful but must stay clearly scoped

The active handoff correctly says Drive mirror files are hot working copies and
canonical promotion is batched. That supports founder-speed iteration.

This distinction matters because the founder can still test prompts manually,
but automation must not promote, package, or treat them as validated source.

## Recommended Next Work

Highest impact for efficiency and quality:

1. Keep using the local harness refresh wrapper before Hermes or handoff records
   `ready`, `pass`, `complete`, or `archived_low_discarded_reference`:
   `ruby scripts/idol_harness_refresh.rb runs/YYYY-MM-DD/CONTENT_ID --write`.
2. Use the schema-backed local action queue as the compact automation handoff
   after refresh. It now includes blocker summaries and per-unit next actions:
   `automation/action-queues/2026-06-10-0526_SONG_SELECTION-harness-action-queue.yaml`.
3. For active LOW 03V, treat S00-S03 as the current front chunk. Its local
   source/prompt QA is closed and only playback/generation review remains, so
   the current next unit is the founder gate
   `front_03v_playback_gate:S00-S03`, not broad S04+ local QA by default. Use
   the run-owned worklist:
   `runs/2026-05-26/0526_SONG_SELECTION/review/03v-section-video-prompt-qa-worklist-v1.md`
   or the automation-facing `.yaml` sidecar. The short local refresh sequence is:
   `ruby scripts/idol_video_prompt_section_qa_worklist.rb runs/2026-05-26/0526_SONG_SELECTION --write`,
   `ruby scripts/idol_harness_action_queue.rb runs/2026-05-26/0526_SONG_SELECTION --only-check video_prompt_section_qa_readiness --write`,
   `ruby scripts/idol_harness_next_unit.rb runs/2026-05-26/0526_SONG_SELECTION --write`,
   `ruby scripts/idol_harness_founder_gate_packet.rb runs/2026-05-26/0526_SONG_SELECTION --write`,
   then `ruby scripts/validate_03v_front_playback_gate.rb runs/2026-05-26/0526_SONG_SELECTION`.
4. Keep `04` blocked until a final recipe is locked, or keep it explicitly in
   candidate/founder-playback-review state. Use the run-owned worklist:
   `runs/2026-05-26/0526_SONG_SELECTION/review/04-edit-readiness-worklist-v1.md`
   or the automation-facing `.yaml` sidecar.
5. Add schemas only where automation needs machine-readiness, not for isolated
   manual helper outputs that should remain founder-directed.

## Bottom Line

The harness rules are now much better organized than before, but management is
not yet fully automatic. The next real bottleneck is closing the two remaining
readiness queues, not more prose cleanup. If Hermes and orchestrator routing
depend on validator output plus the schema-backed action queue, founder
intervention can focus on real creative decisions instead of discovering
contract drift by hand.
