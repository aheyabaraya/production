# 03V prompt authoring, playback intake, and motion handoff

Machine source: `automation/idol-script-registry.yaml`.

Carry passed Official Core/Branch Production Cut pixels, selected Sequence flow, Motion Storyboards, and playback evidence through the active 03V route for one exact section.

Authority boundary: Clip existence never proves playback PASS; temporal motion and camera direction remain authored and reviewed, not inferred by scripts.

Route: active storyline + selected Sequence → passed Official Core/Branch pixels → Motion Storyboard → one-frame I2V or Founder-selected multi-reference execution → 480p/720p CDD playback evidence → edit handoff.

## Registered scripts

- `scripts/idol_03v_apply_playback_decision.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_apply_playback_review_record.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_generated_playback_intake.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_import_generated_clips.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_playback_decision_sheet.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_playback_review_worklist.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_record_playback_review.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_refresh_playback_surfaces.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_source_snapshot.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_grok_imagine_drive_sync.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_media_execution_adapter.rb` — status: `active`; authority: `mechanical_default`. Dry-run validates the exact active image or Grok video lane; for video, an explicit local write may package unchanged prompt bytes plus only the tool-authorized ordered Production Cut inputs under `execution-ready/` or `/private/tmp`. It never invokes a provider.
- `scripts/idol_prepare_grok_video_prompt_handoff.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_production_cut_review.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_video_prompt_authoring.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_review_to_grok_handoff.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_storyboard_probe_contract.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_video_prompt_drive_sync.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_video_prompt_section_qa_worklist.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_03v_front_playback_gate.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_audio_branch_cut_placement.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_production_cut_review.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_video_prompt_index.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_video_prompt_manifest.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_video_prompt_section_qa_readiness.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_video_prompt_storyboard_assist.rb` — status: `active`; authority: `mechanical_default`.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
