# IDOL Harness Structure Audit - 2026-06-16

## Scope

This audit records the current skill, schema, and script structure after the
front-planning/PRE-00 discussion.

Founder intent:

- The purpose is not a generic repository neatness audit.
- The purpose is to find what blocks a LEFT IN THAT NIGHT style deep
  front-planning start: clear founder brief intake, preserved concrete ideas,
  early route clarity, source-preserving references, and a clean path into
  song/MV production without burying creative judgment in automation.

Current implementation boundary:

- PRE-00 skill scope, front-planning readiness, schema ID cleanup, checker
  cleanup, and script policy were handled in this maintenance pass.
- `idol-suno-prompt`, `idol-orchestrator`, `idol-editing-qc`, and
  `idol-nucleus` were slimmed into router-style skills with directly linked
  detail references. Further large skill slimming and existing one-off script
  relocation are still decision-queue items, not completed cleanup.
- Contact sheet interpretation, reference MV interpretation, music meaning
  analysis, melody judgment, instrument-function judgment, and creative route
  selection remain agent/founder work. Scripts may extract or validate evidence
  only.

## LEFT-Style Front-Planning Blocker Lens

The useful question is: can the founder give a detailed brief, image, message,
song feeling, reference family, or storyline seed and have the harness preserve
it cleanly until `00`, `00A`, `01`, and `02A`?

The main blockers found were:

1. PRE-00 was too easy to read as a deep research machine.
   - Risk: agents might browse, mine Bilibili, create contact sheets, run audio
     extraction, or write structured YAML before the founder has selected the
     route.
   - Fix in this pass: PRE-00 default is now only compact founder-facing
     inspiration cards.

2. Full radar detail could leak into default PRE-00.
   - Risk: a weaker agent may open the full authoring detail and assume every
     PRE-00 needs five routes, four reference families, Bilibili policy, and
     structured schema output.
   - Fix in this pass: the detail file now says it is full-radar only.

3. The real LEFT-style start needs a selected-route intake handoff, not a bigger
   PRE-00.
   - Risk: if PRE-00 tries to do all the deep work, it becomes noisy and loses
     founder intent before the run exists.
   - Direction: after founder selection, use a run-owned
     `research/harness-intake-brief-vN.md` to preserve situation, message,
     lyric seeds, reference intent, visual objects, story spine, risks, and
     what downstream must carry forward.

4. Run-specific scripts can accidentally become creative precedent.
   - Risk: PULSO/LOW scripts with hard-coded paths may teach agents to solve
     future songs by copying old mechanics.
   - Direction: treat them as one-off production tools unless separately
     generalized.
   - Fix in this pass: script policy now separates reusable extraction-only
     helpers, review-surface/worklist helpers, compatibility-default scripts,
     and one-off run helpers. Audio/reference helpers now emit measurement
     notes instead of creative decisions, and the WORLD_CUP_PULSO one-off
     instrument probe was downgraded from instrument inference to measurement
     flags.

5. Schema cleanup is not the creative blocker, but it can become a routing
   blocker after the selected route enters structured harness steps.
   - Risk: missing/off-pattern schema IDs can make validators and automation
     harder to trust.
   - Direction: clean schema IDs in a separate maintenance round.

6. 01 could preserve front planning only indirectly.
   - Risk: a run like LEFT could cite the readiness index at the top of 01, but
     leave individual sections with only `00A:Sxx` as the local source pointer.
     That is readable to Codex after a full pass, but too easy for a weaker
     executor to miss when moving section by section into 02A.
   - Fix in this pass: `schemas/song-choreography-performance-mv-map.schema.json`
     now allows optional
     `lyric_to_scene_thinking[].front_planning_transfer` with source refs,
     extracted function, current-song trigger, screen translation, and 02A
     cut/keyframe implication. This is a trace contract only; it does not
     automate source interpretation.
   - Follow-up fix in this pass: `scripts/idol_harness_state_check.rb` now
     reports a nonblocking `front_planning_transfer_gate_shape` check. It makes
     the indirect-transfer gap visible by counting 01 transfer records,
     section-level `screen_cause_effect` / `director_chain` cards, and 02A
     cut/keyframe source traces without judging the creative interpretation.

## Checks Run

- `ruby scripts/idol_skill_contract_check.rb skills/idol-research-radar`
  - Result: pass.
- `ruby scripts/idol_skill_contract_matrix.rb`
  - Result: pass.
  - 20 skills checked.
  - 10 `harness-core`, 6 `isolated-helper`, 3 `retired-stub`, 1
    `compat-alias`, 0 contract gaps.
  - The matrix now includes an informational skill size inventory so oversized
    skills are visible without making line count a readiness blocker.
- Skill size inventory from `skills/*/SKILL.md`.
- Schema metadata scan for duplicate `$id`, missing `$id`, off-pattern `$id`,
  duplicate top-level titles, and duplicate enum values.
- Script inventory from top-level `scripts/*`.
- Script boundary follow-up checks:
  - `scripts/idol-video-python -m py_compile` on the audio/reference and edit
    helper scripts touched in this pass.
    - Result: pass.
  - `ruby scripts/idol_harness_state_check.rb runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE --json`
    - Result: `overall_status: validator_pass`; after the section-level 01
      retrofit, `front_planning_transfer_gate_shape` reports
      `01_front_planning_transfer_records: 11/11`.
  - `ruby scripts/idol_harness_state_check.rb runs/2026-06-11/0611_WORLD_CUP_PULSO --json`
    - Result: existing `video_prompt_section_qa_readiness` blocker only; new
      nonblocking `front_planning_transfer_gate_shape` reports
      `01_front_planning_transfer_records: 10/10`, while 02A has readiness
      source tokens in 22/22 cuts.
- 01 front-planning transfer follow-up checks:
  - `ruby -rjson -e 'JSON.parse(File.read("schemas/song-choreography-performance-mv-map.schema.json")); puts "schema json ok"'`
    - Result: pass.
  - `ruby scripts/idol_skill_contract_check.rb skills/idol-song-choreography-performance-mv skills/idol-generation`
    - Result: pass.
  - `ruby scripts/idol_skill_contract_matrix.rb --strict`
    - Result: pass, 0 contract gaps.
  - `ruby scripts/idol_harness_state_check.rb runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE --json`
    - Result: `overall_status: validator_pass`; the transfer-gate shape check
      passes with 11/11 01 transfer records, 11/11 readiness source tokens in
      01, and all 02A cuts carrying source sections, keyframe boundary
      contracts, and compile seed blocks.
  - `ruby scripts/idol_harness_state_check.rb runs/2026-06-11/0611_WORLD_CUP_PULSO --json`
    - Result: existing `video_prompt_section_qa_readiness` blocker only; 00,
      00A, 01, 02A, front-planning readiness, and downstream trace checks pass.
      The transfer-gate shape check passes with 10/10 01 transfer records,
      10/10 readiness source tokens in 01, and 22/22 02A cuts carrying source
      sections, keyframe boundary contracts, compile seed blocks, and readiness
      source tokens.

## PRE-00 Skill Status

`skills/idol-research-radar/SKILL.md` now treats PRE-00 as a light founder
inspiration surface by default.

Default PRE-00 behavior:

- Produce 3-5 compact route cards in chat or a short note.
- Do not create files by default.
- Do not browse, Bilibili-mine, download, create contact sheets, run extraction
  scripts, run reference-song metrics, or write structured YAML by default.
- Do not draft `00` from PRE-00 alone.
- Move into LEFT IN THAT NIGHT style only after the founder selects or expands a
  route, through a run-owned
  `runs/YYYY-MM-DD/CONTENT_ID/research/harness-intake-brief-vN.md`.

Full radar behavior remains available only when explicitly requested:

- Structured output:
  `automation/pre-00-research-radar-YYYY-MM-DD.yaml`.
- Conditional schema read:
  `schemas/pre-00-research-radar.schema.json`.
- Optional Bilibili/source mining only after explicit approval or selected-route
  source support.

## Skill Split Findings

The current skill split is structurally acceptable. The matrix found no missing
read contract, output boundary, schema pointer, or reference pointer gaps.

Largest skill files:

| lines | skill |
| ---: | --- |
| 314 | `skills/idol-research-radar/SKILL.md` |
| 281 | `skills/idol-song-choreography-performance-mv/SKILL.md` |
| 274 | `skills/kling/SKILL.md` |
| 267 | `skills/idol-song-lock/SKILL.md` |
| 261 | `skills/idol-generation/SKILL.md` |
| 231 | `skills/idol-suno-prompt/SKILL.md` |
| 213 | `skills/idol-video-prompt/SKILL.md` |
| 190 | `skills/idol-orchestrator/SKILL.md` |
| 185 | `skills/idol-editing-qc/SKILL.md` |
| 159 | `skills/idol-member-teaser-portrait/SKILL.md` |

Risk:

- No harness-core `SKILL.md` is currently above 314 lines after this pass, but
  several skills still carry dense procedural content.
- They should not be split just because they are long. Split only when a clear
  stage boundary, schema boundary, or repeated sub-procedure exists.
- Best next pattern is to keep each `SKILL.md` as a short router and move
  procedural detail into local `references/` only when that skill is next edited
  for a real harness reason.

Follow-up skill slimming performed in this pass:

- `skills/idol-generation/SKILL.md` was reduced from 320 lines to 261 lines.
  The stage router, required reads, front-planning transfer gate,
  cut/keyframe/pre-edit/contact-sheet invariants, founder gates, output
  placement, and registry rules stayed in `SKILL.md`.
- The long top-level output-shape and validation checklist was replaced by a
  compact `Output Shape And Checks` router. Detailed 02/02A/02B authoring,
  prompt packet structure, prompt compilation, and API/imagegen validation
  remain in the directly linked generation reference files.
- `skills/idol-suno-prompt/SKILL.md` was reduced from 473 lines to 231 lines.
  The trigger, live drafting boundary, required reads, output path, compact
  prompt standard, output shape, and core checks stayed in `SKILL.md`.
- Detailed reference-song fit, source lineage, whole-song composition,
  copy-box rules, arrangement/instrumentation, melody/topline, and full
  checklist moved into
  `skills/idol-suno-prompt/references/suno-prompt-authoring-detail.md`.
- This keeps the front-planning/Suno bridge maintainable without weakening the
  rule that saved prompt packets must still read the detailed reference before
  being marked ready.
- `skills/idol-orchestrator/SKILL.md` was reduced from 407 lines to 190 lines.
  The trigger, required reads, state order, front-planning carry rules, output
  verification summary, founder gates, and compact output shape stayed in
  `SKILL.md`.
- Detailed next-step routing, section-shard checks, post-review handoff,
  package/social/memory routing, and run-output verification moved into
  `skills/idol-orchestrator/references/orchestration-routing-detail.md`.
- The strict skill matrix now detects that orchestrator reference and still
  reports 0 contract gaps.
- `skills/idol-editing-qc/SKILL.md` was reduced from 487 lines to 185 lines.
  Founder timing, required reads, input boundaries, source of truth, output
  boundary, and the high-level edit workflow stayed in `SKILL.md`.
- Detailed 04 section-sharding, upstream intent context, runtime/cache ladder,
  audio-marker-first contract, initial analysis alignment pass, automatic
  recognition assist limits, source intake, cut/QC/effect rules, command
  templates, and memory promotion moved into
  `skills/idol-editing-qc/references/editing-qc-detail.md`.
- This keeps edit automation bounded to evidence gathering and validation; it
  does not automate final source choice, identity judgment, exact edit timing,
  geometry, or founder pass/fail.
- `skills/idol-nucleus/SKILL.md` was reduced from 308 lines to 140 lines.
  The song-backed `00` gate, founder-input-first rule, target-empathy priority,
  thin-promotion source lineage rule, output boundary, and compact authoring
  decision checklist stayed in `SKILL.md`.
- External brainstorm handoff, PRE-00 route handoff, full draft rules, minimum
  output shape, and founder-review checklist moved into
  `skills/idol-nucleus/references/nucleus-authoring-detail.md`.
- This directly supports LEFT/PULSO-style front planning by keeping `00` from
  becoming a lossy rewrite of the intake, readiness index, selected-audio
  analysis, lyrics bridge, audio-motion map, POV timeline, or section/cut/frame
  map.
- `skills/idol-song-choreography-performance-mv/SKILL.md` now points agents to
  optional `lyric_to_scene_thinking[].front_planning_transfer` when deep
  planning needs a durable section-level bridge into 02A, while still requiring
  the same decision to be visible through `screen_cause_effect` and
  `director_chain`.
- `skills/idol-generation/SKILL.md` now treats that 01 field as the preferred
  bridge when present, then requires 02A to convert it into source sections,
  director chain, compile seed refs, keyframe boundary contract, or reference
  contact-sheet contract instead of copying raw planning prose.

Retired/compat status:

- Retired mv/stage/mix skill names have been removed from the repository.
- `idol-track-key-visual` is a compatibility alias.
- The contract matrix sees these as closed/contained, not active harness entry
  points.

## Schema Findings

Schema count: 43.

No immediate duplicate-contract risk found:

- Duplicate `$id`: none.
- Duplicate top-level schema titles: none.
- Duplicate enum values: none found by scan.

Cleanup candidates:

| issue | paths |
| --- | --- |
| Definitions-only schema | `schemas/social-analytics.schema.json` intentionally has `$defs` but no top-level `type` or `required`; runtime validation is currently owned by `scripts/validate_social_analytics.rb` |

Recommended schema cleanup round:

1. Normalize missing/off-pattern `$id` values to the active local schema URL
   pattern.
2. Confirm validators do not depend on the old IDs.
3. Decide whether `social-analytics.schema.json` is intentionally a `$defs`
   library or should expose a top-level validation object.
4. Run existing schema and harness validators after the cleanup.

Follow-up cleanup performed in this pass:

- `song-choreography-performance-mv-map.schema.json` now accepts optional
  `front_planning_transfer` on each 01 lyric/section card. This closes a
  schema expressiveness gap without adding a new stage or requiring existing
  artifacts to change.
- `scripts/idol_harness_state_check.rb` now checks front-planning source-token
  trace separately across existing `00`, `00A`, `01`, and `02A` carry gates.
  The check remains non-interpretive: it reports missing source lineage, not
  whether the creative transfer is good.
- PULSO and LEFT 01 run artifacts were retrofitted with section-level
  `front_planning_transfer` records so each section names source refs, extracted
  function, current-song trigger, screen translation, and 02A cut/keyframe
  implication without replacing the deep-planning files.
- Missing/off-pattern `$id` values were normalized for
  `single-cut-beat-source-generation-manifest`, `two-cut-beat-source-generation-manifest`,
  `video-prompt-section-qa`, `package`, `prompt-packets`, `publishing-plan`, and
  `social-analytics`.
- `schemas/song-lock.schema.json` now accepts optional
  `audio_source.audio_mp3_mirror` as a review/playback mirror pointer while
  keeping `audio_file_or_url` as the selected source truth.
- `schemas/prompt-packets.schema.json` now accepts optional
  `compiled_prompt_block.compiled_prompt_hash` for preflight/export drift
  checking.
- `schemas/audio-motion-director-map.schema.json` now accepts current `C##`
  cut/cut-range slots and optional `stable_audio_extracts.vocal_delivery_summary`
  as timing evidence, without making it a choreography decision.
- `schemas/video-prompt-section-qa.schema.json` now accepts transition and
  alternate review keys such as `S00_S01` and `S09_ALT`.
- PULSO run artifacts were normalized where the artifact was using alias-like
  values instead of canonical schema values: `route_action` layout family became
  `body_route_action`, `mv_world` layout family became `world_response`, and
  00A compatibility field name `proof_target` visual readability target one-off object labels were reduced to existing target
  categories while the detailed prose was preserved.
- PULSO `selected-audio-analysis-v3.json` was promoted from an evidence sidecar
  shape to a schema-valid selected-audio analysis by preserving v2's validated
  analysis structure and applying the founder final audio timing/evidence from
  the original v3 data.

Remaining schema cleanup candidates:

- Add a separate top-level `social-analytics` document schema only if the ledger
  moves away from JSONL row validation.

## Script Findings

Top-level script count: 71.

Largest scripts:

| lines | script |
| ---: | --- |
| 2712 | `scripts/validate_02b_imagegen_contract.rb` |
| 1615 | `scripts/idol_02b_batch_api_runner.py` |
| 1371 | `scripts/idol_pulso_next_section_preview.py` |
| 1190 | `scripts/idol_harness_state_check.rb` |
| 1140 | `scripts/idol_pulso_s00_s01_codex_preview.py` |
| 1091 | `scripts/idol_grok_imagine_drive_sync.py` |
| 1073 | `scripts/validate_03v_front_playback_gate.rb` |
| 1016 | `scripts/validate_video_prompt_index.rb` |
| 845 | `scripts/idol_03v_import_generated_clips.rb` |
| 842 | `scripts/idol_build_two_cut_source_manifest.py` |

Run-specific script risk:

- `scripts/idol_low_source_first_rebuild_plan.py` has hard-coded
  `0526_SONG_SELECTION` / LOW paths.
- `scripts/idol_pulso_next_section_preview.py` has hard-coded
  `0611_WORLD_CUP_PULSO` paths.
- `scripts/idol_pulso_s00_s01_codex_preview.py` has hard-coded
  `0611_WORLD_CUP_PULSO` paths.
- `scripts/idol_worldcup_reference_audio_instrument_probe.py` is also treated
  as a known one-off production helper.

Compatibility-default script risk:

- `scripts/idol_platform_draft_upload.py`
- `scripts/idol_social_release_sync.py`
- `scripts/idol_video_ffmpeg_revise_render.py`
- `scripts/idol_video_source_intake.py`
- `scripts/idol_video_sync_workbench.py`
- `scripts/validate_02b_imagegen_contract.rb`

These contain legacy or sample/default run paths. They may remain as tools, but
new workflow use should pass explicit run paths or refactor the default path out
before treating them as reusable harness commands.

Interpretation:

- These look like useful one-off production tools, not reusable harness
  commands.
- Keeping them at top-level `scripts/` increases the chance that agents treat
  run-specific logic as general automation.
- Do not delete or move them in this pass. A separate cleanup round should
  decide whether to mark them as one-off, move them under the owning run, or
  generalize the reusable parts.

Script policy recommendation:

- Extraction and validation scripts are allowed when they preserve evidence or
  check contracts.
- Creative interpretation must stay out of scripts.
- New run-specific scripts should require a short justification and should
  default to the owning run folder unless they are designed as reusable harness
  tools.
- Before adding a new script, check whether an existing validator/extractor can
  be extended safely.

Policy implementation in this pass:

- Added `scripts/README.md` to define reusable script roles, prohibited
  creative-interpretation automation, and known one-off helpers.
- Added `Script Promotion Policy` to `wiki/harness-maintenance-rules.md`.
- Added a nonblocking `script_policy_run_path_registry` check to
  `scripts/idol_harness_state_check.rb`. It scans top-level scripts for
  hard-coded run paths or known run tokens and verifies they are registered in
  `scripts/README.md`; it does not evaluate creative interpretation.
- No run-specific scripts were moved or deleted; moving them can break existing
  run evidence and should happen only in a dedicated cleanup round.
- `scripts/README.md` now names the current extraction-only helpers and
  review/worklist helpers. `idol_candidate_audio_probe.py`,
  `idol_reference_audio_metrics.py`, `idol_reference_intro_audio_metrics.py`,
  `idol_reference_music_feature_extract.py`, and
  `idol_reference_section_segments.py` are measurement/candidate helpers only.
  Their outputs must not become song fit, section function, arrangement,
  instrument-use, melody, or prompt decisions without Codex/founder analysis.
- `idol_worldcup_reference_audio_instrument_probe.py` remains a one-off
  WORLD_CUP_PULSO helper, but it now reports `measurement_flags` instead of
  `instrument_inference`.

## Current Decision Queue

Founder/Codex decisions still needed:

1. Decide whether to move, archive, or generalize the existing LOW/PULSO
   run-specific scripts.
2. Decide whether remaining dense skills such as `idol-generation` or
   `idol-song-lock` should be slimmed during their next real edit using
   references/modules rather than broad rewrites.
3. Decide whether PULSO's `video_prompt_section_qa_readiness` should remain the
   active blocker until real 03V section review is complete.

## Status

- PRE-00 skill correction: done.
- PRE-00 skill contract validation: pass.
- Global skill contract matrix: pass.
- Front-planning 00/00A/01/02A source-trace check: implemented and validated;
  LEFT and PULSO now pass this trace check.
- 01 section-level front-planning transfer slot: implemented as optional
  `lyric_to_scene_thinking[].front_planning_transfer`; schema JSON, skill
  contracts, strict skill matrix, LEFT state check, and PULSO expected-blocker
  state check pass.
- 01 section-level front-planning transfer retrofit: LEFT now has 11/11 section
  records and PULSO now has 10/10 section records carrying front-planning
  transfer into 02A-facing screen contracts.
- PULSO schema/contract drift cleanup: implemented; state checker now leaves
  only real 03V section QA readiness as the blocking issue.
- Schema ID cleanup: implemented for the known missing/off-pattern IDs.
- Script policy: documented in `scripts/README.md` and
  `wiki/harness-maintenance-rules.md`; state checker registry check added; no
  one-off scripts were moved or generalized.
- Script boundary tightening: reference/candidate audio scripts now state
  measurement-only method notes in their outputs; reference-section helper
  `function_guess` was renamed to neutral `measurement_bucket`; the
  WORLD_CUP_PULSO one-off instrument probe no longer emits arrangement or
  instrument-function guidance.
- Skill slimming: `idol-suno-prompt` now uses a short router plus directly linked
  authoring detail reference; `idol-orchestrator` now uses a short router plus
  directly linked routing detail reference; `idol-editing-qc` now uses a short
  router plus directly linked editing/QC detail reference; `idol-nucleus` now
  uses a short router plus directly linked nucleus authoring detail reference.
- Skill-size automation: `scripts/idol_skill_contract_matrix.rb` now reports a
  line-count inventory for all skills.
