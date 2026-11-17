# IDOL Script Index

This is the full findability surface. The machine registry is authoritative for declared roots, documentation surfaces, guide mappings, status, and authority profiles.

- Start Here: [`README.md`](README.md)
- Machine registry: [`../automation/idol-script-registry.yaml`](../automation/idol-script-registry.yaml)
- Registry schema: [`../schemas/idol-script-registry.schema.json`](../schemas/idol-script-registry.schema.json)

## Role guides

- [Graph Engineering state, startup admission, queues, dispatch, and contract routing](registry/state-and-contracts.md) — `state_contracts`
- [Schema, semantic, readiness, and release validators](registry/validators.md) — `validators`
- [Audio, reference, source, and measurable evidence routes](registry/research-and-evidence.md) — `research_evidence`
- [Front Planning, review boards, contact sheets, and decision projections](registry/review-and-planning.md) — `review_planning`
- [02B prompt, image-generation preparation, title assets, and output registry](registry/image-and-title.md) — `image_title`
- [03V prompt authoring, playback intake, and motion handoff](registry/video-and-playback.md) — `video_playback`
- [04 edit source, marker, recipe, FX, QC, and worklists](registry/edit-and-qc.md) — `edit_qc`
- [05 package, platform, Drive, workspace, and social evidence](registry/release-and-platform.md) — `release_platform`
- [Runtime launchers and shared deterministic libraries](registry/runtime-and-libraries.md) — `runtime_libraries`
- [Historical, inactive, compatibility, and one-off evidence surfaces](registry/legacy-and-one-off.md) — `legacy_one_off`

## Complete machine roster

<!-- idol-script-registry: complete-roster -->
- `scripts/lib/idol_graph_production_review_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_graph_criterion_evidence_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_graph_production_review.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol-edit-desk` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/idol-video-python` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_01r_reference_gap_worklist.rb` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_02b_batch_api_runner.py` — guide: `image_title`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_03v_apply_playback_decision.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_apply_playback_review_record.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_generated_playback_intake.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_import_generated_clips.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_playback_decision_sheet.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_playback_review_worklist.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_record_playback_review.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_refresh_playback_surfaces.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_03v_source_snapshot.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_04fx_compile_recipe_effects.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_04fx_transition_opportunity_seed.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_artifact_integrity.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_asset_drive_sync.py` — guide: `release_platform`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_audio_precision_markers.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_bilibili_reference_fetch.py` — guide: `research_evidence`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_build_two_cut_source_manifest.py` — guide: `image_title`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_candidate_audio_probe.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_collect_platform_metrics.py` — guide: `release_platform`; status: `active`; authority: `founder_approved_read_only_external`.
- `scripts/idol_compile_brief_cards.rb` — guide: `research_evidence`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_creative_truth_guard.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_cue_bpm_map.rb` — guide: `research_evidence`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_cut_keyframe_batch_api_runner.py` — guide: `image_title`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_cursor_assignment_adapter.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_cursor_model_guard.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_concurrency_migration.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_director_dispatch_index.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_department_transport_refresh.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_delivery_qc.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_marker_contact_sheets.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_readiness_worklist.rb` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_recipe_alignment_evidence.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_employer_boundary_guard.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_execute_image_generation_request.py` — guide: `image_title`; status: `active`; authority: `founder_approved_external_write`.
- `scripts/idol_export_02b_prompt_manifests.py` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_founder_direct_update_commit.rb` — guide: `state_contracts`; status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_founder_pass_harness.rb` — guide: `state_contracts`; status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_g2_delegated_pixel_close_intake.rb` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_grok_imagine_drive_sync.py` — guide: `video_playback`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_graph_director_session_router.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_graph_projector.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_graph_run_controller.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_action_queue.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_apply_founder_decision.rb` — guide: `state_contracts`; status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_harness_context_pack.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_department_context.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_role_context_pack.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_current_next.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_expert_gate.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_founder_gate_packet.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_frontier_check.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_next_unit.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_optimization_acceptance.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_record_founder_decision.rb` — guide: `state_contracts`; status: `active`; authority: `founder_decision_transport`.
- `scripts/idol_harness_refresh.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_run_inventory.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_mv_git_worktree.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_sections.rb` — guide: `state_contracts`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_harness_shadow_eval.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_stage.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_harness_state_check.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_html_review_board.rb` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_dispatch.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_request_selection.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_section_worklist.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_section_worklist_v7_legacy.rb` — guide: `image_title`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_import_tiktok_studio_exports.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_tiktok_oauth_reauth.py` — guide: `release_platform`; status: `active`; authority: `founder_approved_credential_write`.
- `scripts/idol_instruction_surface_audit.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_local_image_upscale.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_luna_to_grok_section_transfer.py` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_low_source_first_rebuild_plan.py` — guide: `state_contracts`; status: `one_off`; authority: `one_off_measurement_only`.
- `scripts/idol_measure_sequence_motion_timeline.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_media_execution_adapter.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_openai_image_model_policy.py` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_pinterest_public_capture.py` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_planning_image_contact_sheet.py` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_platform_auth_status.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_platform_draft_upload.py` — guide: `release_platform`; status: `active`; authority: `founder_approved_external_write`.
- `scripts/idol_pre00_selection_handoff.rb` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_api_upload_video.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_grok_video_prompt_handoff.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_image_generation_request.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_image_generation_request_v8_legacy.rb` — guide: `image_title`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_prepare_image_render_correction.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_production_cut_review.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_sequence_motion_analysis.rb` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_video_prompt_authoring.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prompt_packet_compile.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_prompt_packet_section_merge.rb` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_audio_metrics.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_catalog_lookup.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_comparison_packet.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_evaluation.rb` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_hub.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_intro_audio_metrics.py` — guide: `research_evidence`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_reference_music_feature_extract.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_section_segments.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_review_decision_intake.rb` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_review_projection_assembler.rb` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_review_to_grok_handoff.rb` — guide: `video_playback`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_run_layout.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_safe_workspace_cleanup.py` — guide: `release_platform`; status: `active`; authority: `founder_scoped_cleanup`.
- `scripts/idol_script_registry_check.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_skill_contract_check.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_skill_contract_matrix.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_evidence_snapshot.rb` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_public_closeout.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_release_session.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_release_sync.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_split_beat_source_manifest_by_section.py` — guide: `image_title`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_stamp_source_connections.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_startup_admission.rb` — guide: `state_contracts`; status: `active`; authority: `startup_admission_transport_only`.
- `scripts/idol_storyboard_probe_contract.rb` — guide: `video_playback`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_title_output_registry.py` — guide: `image_title`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_two_cut_sheet_crop.py` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_validate_kinetic_slot_sheet.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_validate_storyline_density_locators.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_vercel_analytics_setup.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_ffmpeg_revise_render.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_prompt_drive_sync.rb` — guide: `video_playback`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_video_prompt_section_qa_worklist.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_qc_sheet.py` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_analysis_registry.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_sequence_unit_registry.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_hub_audit.rb` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_segments.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_source_intake.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_sync_workbench.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_weekly_report_reference_extract.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/idol_worldcup_reference_audio_instrument_probe.py` — guide: `research_evidence`; status: `one_off`; authority: `one_off_measurement_only`.
- `scripts/idol_youtube_oauth_reauth.py` — guide: `release_platform`; status: `active`; authority: `founder_approved_credential_write`.
- `scripts/idol_x_scheduled_thread.py` — guide: `release_platform`; status: `active`; authority: `founder_approved_external_write`.
- `scripts/idol_x_oauth_reauth.py` — guide: `release_platform`; status: `active`; authority: `founder_approved_credential_write`.
- `scripts/lib/idol_02a_storyboard_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_03v_language_contract.rb` — guide: `runtime_libraries`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/lib/idol_03v_source_discovery.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_api_video_quality.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_artifact_integrity.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_artifact_integrity.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_camera_direction_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_checkpoint_closure_catalog.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_front_planning_local_pairwise_global.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_front_planning_sequence_core_hold.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_generated_review_post_pass.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_current_next_v2.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_direction_projection_contract.rb` — guide: `runtime_libraries`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/lib/idol_edit_effect_registry.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_handoff_keys.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_helper_consumption_receipts.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_image_execution_lane_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_grok_video_execution_package.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_platform_credentials.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_prompt_presence_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_production_cut_review_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_reference_interpretation_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_reference_evaluation_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_graph_goal_evidence_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_graph_judgment_profile_promotion_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_graph_output_manifest_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_graph_provider_binding_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_graph_run_controller.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_reference_role_plan_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_department_context.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_role_context_pack.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_run_followup_sidecar.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_run_layout.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_run_layout.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_post05_trace.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_skill_contract_paths.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_source_connection_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_social_release_contracts.py` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_social_taxonomy.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_storyboard_collected_angle_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_kinetic_slot_sheet_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_storyline_density_locator_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/lib/idol_video_prompt_section_qa_contract.rb` — guide: `runtime_libraries`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/lib/idol_xai_api_media_profile_contract.rb` — guide: `runtime_libraries`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_01_section_direction.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_02a_creative_context_review.rb` — guide: `review_planning`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_02b_imagegen_contract.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_03v_front_playback_gate.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_audio_branch_cut_placement.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_audio_motion_director_map.rb` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_cue_bpm_map.rb` — guide: `validators`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_department_dispatch.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_company_ops_idol_bridge.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_finishing_fx.rb` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_finishing_fx_compile.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_map_readiness.rb` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_marker_plan.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_recipe.py` — guide: `edit_qc`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_final_delivery_manifest.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_founder_intervention_receipt.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_founder_sequence_control.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_checkpoint_closure_catalog.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_standing_constraint_catalog.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_helper_consumption_receipt.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_front_planning_sequence_core_hold.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_front_planning_local_pairwise_global.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_run_followup_sidecar.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_front_planning_readiness.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_sequence_motion_analysis.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_generated_branch_cut_review.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_director_lineage.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_runtime_projection.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_section_cohort_map.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_contextual_judgment.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_graph_judgment_profile_promotion.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_planning_contextual_grade_vector.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_03v_contextual_grade_vector.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_artifact_contract.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_artifact_routing.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_context_pack.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_contract_version_registry.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_skill_load_profiles.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_surface_version_registry.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_idol_model_routing_agents.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_provider_profiles.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_harness_assignment_model_routing.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_json_schema.py` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_local_image_upscale_receipt.py` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_luna_section_lifecycle_receipt.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_master_storyboard.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_package_readiness.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_production_cut_review.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_publishing_plan.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_reference_interpretation_contract.rb` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_reference_management_catalog.py` — guide: `research_evidence`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_schema_repair_candidate.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_selected_audio_analysis.rb` — guide: `validators`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_session_helper_operating_lock.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_signal_deck_traffic.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_skill_application_receipt.rb` — guide: `validators`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_social_analytics.rb` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_terminology_guard.rb` — guide: `state_contracts`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_terra_section_lifecycle_receipt.rb` — guide: `validators`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_tiktok_studio_exports.py` — guide: `release_platform`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_video_prompt_index.rb` — guide: `video_playback`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/validate_video_prompt_manifest.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_video_prompt_section_qa_readiness.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_video_prompt_storyboard_assist.rb` — guide: `video_playback`; status: `active`; authority: `mechanical_default`.
- `scripts/validate_wardrobe_style_review.rb` — guide: `validators`; status: `historical`; authority: `historical_evidence_only`.
- `scripts/yt-dlp-bilibili.sh` — guide: `research_evidence`; status: `active`; authority: `founder_permission_external_capture`.
- `scripts/yt-dlp-instagram-reference.sh` — guide: `research_evidence`; status: `active`; authority: `founder_permission_external_capture`.
- `scripts/yt-dlp-youtube-reference.sh` — guide: `research_evidence`; status: `active`; authority: `founder_permission_external_capture`.

## Detailed script authority notes

The following detailed notes preserve the prior script descriptions and authority caveats. They are findability support; the machine registry and checker remain authoritative.

## Detailed Script Authority Notes
Scripts in this directory are execution aids. They may validate contracts,
extract measurable evidence, assemble local review surfaces, or update
machine-readable handoff files. They must not replace founder/Codex creative
interpretation.

## How to choose a script

1. Check `automation/idol-script-registry.yaml` before adding or rewriting a script.
2. Prefer a reusable validator, extractor, worklist, contact-sheet builder, or
   export helper when the task is mechanical.
3. Use `scripts/idol-video-python` for media scripts that touch video/audio
   frames, OpenCV, ffmpeg/ffprobe, or the video venv. Do not use bare
   `python3` for those scripts. Rebuild the local runtime from
   `requirements-video.txt` when `.venv-video` is missing.
   System `python3` may be newer than the supported media runtime; treat
   `scripts/idol-video-python --check`, not `python3 --version`, as the IDOL
   audio/video Python readiness check.
4. Pass explicit run paths, manifest paths, output paths, and section ids when a
   script supports them. Inactive or historical defaults are never creative
   precedent and are not part of the active MV route.
5. If the requested automation would choose story meaning, reference function,
   contact-sheet interpretation, melody/instrument function, edit pass/fail, or
   founder approval, stop and report it as a creative/manual decision instead
   of implementing automation.

## Allowed reusable script roles

- Schema and deterministic consistency validators. They may check structure,
  hashes, and schema consistency; they may not judge semantic adequacy or
  generic/thin creative content. Model/Director remain responsible for those
  judgments.
- Evidence extraction that reports measurable values only.
- Contact-sheet or review-surface assembly without interpretation.
- Worklist, queue, gate, registry, and state-report generation.
- Export, manifest, and preflight packaging from already-locked artifacts.
- Deterministic serialization of already-locked creative fields when every
  creative input carries its exact source path, JSON pointer, source-value
  SHA-256, and human/model authorship receipt, the mapping is fixed and
  inspectable, and the script rejects any missing or stale upstream decision
  instead of filling or paraphrasing it. Generic or thin creative content is
  a model/Director judgment, not a script verdict. This is compilation,
  not creative authorship.

There is no registered IDOL Responses Programmatic Tool Calling runner. Direct
tool calls and the helpers in this registry remain the default. A future PTC
helper would need separate measured adoption and may only reduce a read-only,
predictable direct-script validation check with an explicit tool
allowlist, exact output/evidence schema, concurrency/retry/stop limits, and one
root handoff. It must reject creative or adaptive judgment, approvals, final
validation, writes or external actions, citation/native-artifact work, and
duplicate replay of work already completed by a direct tool or agent.

## Python Runtime Isolation

- `scripts/idol-video-python` is the canonical Python entrypoint for IDOL
  audio/video/media and schema-validation helpers that depend on the video
  runtime.
- Bare `python3` may point to a newly upgraded system interpreter. Do not use it
  for media work and do not install packages into it to fix IDOL script errors.
- After a system Python upgrade or `.venv-video` rebuild, run
  `scripts/idol-video-python --check` before media, contact-sheet, audio,
  schema, prompt-export, or output-registry work that depends on Python
  packages. The check reports interpreter isolation, required module presence,
  and direct `requirements-video.txt` pin mismatches.
- `idol_harness_state_check.rb` reports `python_video_runtime_isolation` so
  operators can see whether the launcher still resolves `.venv-video/bin/python`
  and required pinned packages.
- Optional 04VFX work uses the same media Python launcher for ffmpeg/ffprobe,
  OpenCV, MoviePy, Pillow, and review sheets, while Blender remains a separately
  versioned application. Do not install the media requirements into Blender's
  embedded Python or merge the CF image-generation venv into `.venv-video`.
  Read
  `skills/idol-shot-vfx/references/04vfx-manual-use-and-runtime.md` for the
  current package-distribution audit, Blender preflight, known holds, and M1
  8GB preview defaults.

## Not allowed in reusable scripts

- Contact-sheet interpretation.
- Reference MV creative-function selection.
- Song meaning, lyric meaning, melody, arrangement, or instrument-function
  judgment.
- Promotion of a run-specific motif, cut pattern, route, wardrobe, or visual
  grammar into a future default.
- Founder review pass/hold/reject decisions.
- New camera, action, choreography, wardrobe, world, song meaning, or prompt
  intent hidden inside a compiler template. A deterministic compiler may format
  approved upstream prose, but it must return upstream when that prose is thin
  or incomplete.
- Filling missing creative fields with section labels, band/count-derived text,
  placeholders, or other templates and then presenting the result as a complete
  02A/02B artifact.
- Fanning one creative value across distinct sections/cuts, even when that makes
  the schema pass.
- Marking script-created prose as `model_authored_02a`, treating schema validity
  as proof of creative authorship, or using a repair/migration helper to bypass
  contextual LLM review or the registered 02B compiler.

## Run-Specific Helpers

Run-specific helpers may exist when they are clearly production aids for one
run, but they are not reusable graph-engineering commands until refactored. If they
reshape a stage artifact or fill a structural gap, their output must remain a
clearly marked diagnostic candidate under the run's `work/` layer. They may not
write canonical 02A/02B creative truth, supply creative defaults, claim
model-authored provenance, or advance a stage gate.
`idol_creative_truth_guard.rb` performs target-aware inspection: reading a
canonical file while writing scratch evidence is allowed, but writing canonical
stage/research truth, changing run-owned selected/held planning state, writing a
human/model creative-review verdict, or claiming model authorship is blocked.
If a mechanical diagnosis is useful, keep the
candidate and `receipt.yaml` together under
`RUN/work/schema-repair-candidates/ID/`; validate the receipt against
`schemas/schema-repair-candidate.schema.json`. It proves the canonical target
hash stayed unchanged and always has `none_hold_only` gate effect.

`validate_founder_intervention_receipt.rb` validates the exact Founder input,
run-local receipt placement, affected/invalidation artifact hashes, and
integration evidence. V2 additionally validates a Founder-direct correction
against the last passed review/source baseline, every authoritative field
pointer/value hash, the revised canonical artifact, and the nonwaivable
integrity checks. The direct receipt replaces only an additional LLM
creative-opinion review for its named scope; it never removes pixel/playback,
safety, identity/reference, hash, or external-approval checks. The validator
never classifies the request or writes a creative change.
`idol_harness_state_check.rb` holds the current pointer's unresolved
receipt and any later unresolved receipt for the same active stage/section.
Older or other-section receipts remain visible diagnostics without blocking an
unrelated active scope.
`validate_harness_surface_version_registry.rb` verifies the separate current
instruction/skill/script-surface revision registry, byte hashes, full skill
coverage, size and overlap reviews, and the shared-script canonical-write
classification guard; Git remains the history owner.
`validate_harness_skill_load_profiles.rb` validates the provider-neutral,
phase-loaded skill/read registry against its schema, current file hashes,
active stages and roles, execution-contract profile set, and mandatory CDD /
Overall / Edit Director return routes.
`idol_director_dispatch_index.rb` mechanically builds or validates the
pointer-only Director Dispatch Index and Reference Working Index, creates
scoped views, and compiles the schema-valid CDD successor Boot Pack v3 through
the fail-closed `cdd-successor` route. The same command owns the provider-neutral
CDD physical-session router state: initialize, provider-native Goal admission,
exact state-SHA/generation A->B CAS, per-operation authorization, and B->A
rollback. That state is authority metadata only and never rewrites HTML,
review-board, canvas, storyline, Section, or canonical creative bytes. The old
generic `boot-pack` command is retired because it emitted an untyped artifact.
The script aborts compare-and-swap writes when dispatch, manifest, or router
state bytes change. It never embeds worker output, media, or transcripts and
never creates creative truth.

`idol_graph_director_session_router.rb` is the separate Graph-v2 shadow
readiness model for Overall, Planning P1/P2/P3-Ci, Section V-Ci, and Edit
lanes. It keys state by `lane_id + macro_stage_id`, keeps one primary plus one
read-only successor, validates the typed core of provider-native Goal
admission, and models state-SHA/generation A->B CAS plus B->A rollback. The
current command always returns `HOLD`: its hash claims and route observations
grant no prompt, review, canonical-write, Founder-conversation, promotion, or
execution authority. Same-lane Graph succession adds no Founder confirmation
or G-gate. Legacy-pinned CDD state remains on
`idol_director_dispatch_index.rb` and cannot be mixed with it. Activation
requires registered typed transition receipts and a freshness-enforcing
execution consumer outside this shadow model.

`idol_graph_run_controller.rb` reads the hash-bound current-next v2 projection,
Director Dispatch Index, shadow Graph stage registry, selected Department
Dispatch, and optional contextual judgment. It emits one stdout-only dry-run
decision plus a verified frontier set: dispatch/resume, wait for Director
review, route one same-owner bounded correction with a fresh immutable attempt
and Goal, wait for a Founder gate, or hold. Multiple heads are only represented
for a same-stage, mutually disjoint section-cohort set and remain blocked from
execution until a registered scheduler exists. Its append-only event is an
unpersisted intent with a chain hash and idempotency key. It performs no
provider action, Goal creation, state write, creative judgment, review, PASS,
or promotion.

## Active Front Planning-Centered MV Route

The active MV graph-engineering route has no compatibility branch. Existing run artifacts may
remain as historical evidence, but no active script may use them as a fallback
or infer missing current truth from them.

```text
PRE-00 -> PRE-00S -> selected-audio analysis -> audio-motion map
-> 00A song production lock -> Front Planning v17 (including the complete
PRE-00-rooted full-storyline lineage, exactly three viable routes, ordered
MJxx Major Stacks, selected exact-five one-second Sequence Units, Core references,
Hero proof, and screen progression)
-> 01 v3.0 Official Cores -> 02A v3.0 Branch plans -> 02B delta v1.6 / packets v2.6
-> Generated Production-Cut Review -> Audio Production-Cut Placement
-> storyboard assist v4 -> 03V manifest v8 -> 04 marker plan v6 -> 05
```

Active ownership is deliberately narrow:

- Front Planning owns target, message, whole-video and section flow, member
  placement, the unified current-title member-visual plus governing
  scene/sequence plus supporting-component attachment order, and reference
  dispositions. There is no separate downstream background package.
- 01 expands the approved Front Planning section and owns each one-image
  Official Core. 02A exact-imports those immutable Cores and owns only each
  Core's ordered `1..N` Branch Cuts. A Core Cut owns the major event; a Branch Cut is an independently
  framed realization that adds distinct observable screen information.
- A human or assigned model authors each 02B set of five required render-prompt
  items from the
  exact 02A Branch Cut, parent Core Cut, immediate Branch-Cut siblings, and
  immediate same-section neighboring Core Cuts. The compiler validates and
  exact-copies it.
- Still-camera geometry is resolved through 02B. Temporal camera movement is
  first authored in 03V after selected generated pixels pass review.
- Every active 03V prompt uses a storyboard board made from one to three passed
  `official_core|branch` Production Cut images. A one-image board is valid when it is a sufficient motion
  anchor and carries an authored temporal-route reason. `@image1` is the board and
  `@image2`–`@image4` are its ordered original frames.

## Common Task Quick Map

Use this map before adding a new script or copying commands into a skill:

- Active run address: `idol_run_layout.py init|validate|plan-migration` owns
  `runs/ALBUM_KEY/TITLE_KEY/RUN_ID` and `run-manifest.yaml`. New authoring never
  falls back to a date-first root. Only the exact hash-bound in-flight entry in
  `automation/run-layout-transition.yaml` may finish in place; this is not a
  generic compatibility branch. Migration planning is read-only unless an
  explicit output path is given and never moves bytes.
- Artifact identity cost: `idol_artifact_integrity.py` applies
  `canonical_gate`, `promotion_or_external_transfer`,
  `repeat_local_validation`, `working_derived_media`, or `ephemeral`.
  Promotion/gates force SHA-256; unchanged local checks may reuse the
  metadata-keyed cache, which has no approval authority.
- Shared run/integrity libraries: `idol_run_layout.rb`,
  `idol_artifact_integrity.rb`, and their Python counterparts under
  `scripts/lib/` keep Ruby and Python consumers on the same album-run and hash
  policy. They validate routing and integrity only; they do not author stage
  truth.
- API-video quality library: `lib/idol_api_video_quality.py` probes exact local
  upload bytes and validates the run-owned 2K/30fps preparation receipt. It
  performs no network I/O and grants no upload or release authority.
- Social taxonomy library: `lib/idol_social_taxonomy.rb` centralizes the
  platform, content-lane, family, format, and pillar vocabularies shared by
  social validators. It classifies transport fields only and does not select
  content or publication timing.
- Reference comparison coverage: `idol_01r_reference_gap_worklist.rb` reads a
  validated active Front Planning v17 artifact and writes only a derived
  per-section comparison-floor worklist. It never selects, applies, combines,
  rejects, or invents a reference.
- Active-run connectivity and versions: `idol_harness_run_inventory.rb` reads
  the run identity (manifest or exact registered transition), unchanged
  semantic stage registry, artifact routing,
  contract-version registry, current-next YAML/MD, title output registry, and
  actual run files. It reports paths, cached-or-forced SHA-256, active-only
  artifact schema versions, pointer drift, and missing title registration; its
  optional `--write` file under `RUN/work/` is derived evidence only.
- Artifact placement: `validate_harness_artifact_routing.rb` requires
  `automation/harness-artifact-routing.yaml` to exact-cover the 19 active stage
  ids in registry order, use the same owning skill, remain run-relative, and
  exclude retired 00/01A/02 and standalone 01R/01R-C patterns. Routing changes
  where bytes live; it has no authority to change stage order, scope, inputs,
  or Founder gates.
- Active schema inventory: `validate_harness_contract_version_registry.rb`
  requires every active stage output contract and every authoring schema named
  by an active shared script to have one current-only registry route. It rejects
  duplicate schema paths, duplicate `$id` values, exact-content duplicates, and
  retired stage schemas in the active registry. Its high-overlap report is
  diagnostic only: similarity never authorizes a merge, split, rewrite, or
  deletion.
- Downloaded-reference cadence: `idol_video_reference_hub_audit.rb` reports
  each registered source's duration lane, broad contact-sheet sampling and
  part seconds, selected-range one-second proof, retained legacy cadence, and
  unregistered source roots. Unregistered roots also report metadata duration,
  available cadence directories, selected-range proof, and a 270-second-limit
  hold. It reads manifests/files only and makes no source or creative judgment.

- Selected/candidate audio evidence: `idol_candidate_audio_probe.py` for broad
  local audio reports; `idol_audio_precision_markers.py` for sub-second beat,
  onset, pitch-proxy, energy-jump/low-energy, percussive-onset, and motif
  sidecars; `idol_video_sync_workbench.py` audio summary v2 for 04/04FX assist;
  `idol_04fx_transition_opportunity_seed.py` for draft 04FX opportunity points;
  `validate_selected_audio_analysis.rb` and `validate_audio_motion_director_map.rb`
  for downstream contract checks. All of these are measurement/seed evidence only.
- Reference-song audio evidence: `idol_reference_music_feature_extract.py`,
  `idol_reference_audio_metrics.py`, `idol_reference_intro_audio_metrics.py`,
  and `idol_reference_section_segments.py`. These outputs are measurement-only
  and must not decide current-run section functions or edit timing.
- Generated Branch-Cut review: use the v12 Founder HTML workbench and
  `validate_generated_branch_cut_review.rb`. Legacy beat-source contact-sheet
  tooling is archive-only.
- Founder Sequence Control: `validate_founder_sequence_control.rb` checks the
  IDOL/CF lane schema, ordered major ids, reference targets, and pointer/hash
  integrity. It never authors the sequence or infers a Founder lock.
- Source-bound Founder HTML review boards:
  `idol_html_review_board.rb`. Keep the active v12 workbench manifest at
  `RUN/review/manifests/founder-workbench.yaml`; one active cycle may review a
  single section, a named multi-section set, or the whole video. The script
  orders target/message and whole-video/section-flow summaries before sections,
  Core Cuts, and Branch Cuts. It resolves hash-bound canonical field pointers and
  media receipts into a reusable local layout without copying creative truth
  into HTML source, and every card declares its smallest revision scope.
- Weekly visual-report reference extraction:
  `idol_weekly_report_reference_extract.py`. It reads one completed
  self-contained weekly HTML figure plus its paired reference-image ledger and
  writes only the selected embedded derivative and report/ledger/image-hash
  manifest under `RUN/research/weekly-report-reference-extracts/`. After an
  album run selects the figure, that surface can enter Front Planning reference
  research/disposition and current-title album-asset development. The
  script never interprets the image, creates a creative lock, or authorizes a
  generation attachment. It preserves only an embedded weekly HTML figure's
  appearance-reference use; it is not a general direction source.
- Video/source QC sheets: `idol_video_qc_sheet.py`; fixed two-cut crops:
  `idol_two_cut_sheet_crop.py`; edit-marker source-window sheets:
  `idol_edit_marker_contact_sheets.py`.
- 02B export, preflight, and paid-generation preparation:
  `idol_prompt_packet_compile.rb`, `validate_02b_imagegen_contract.rb`,
  `idol_export_02b_prompt_manifests.py`,
  `idol_openai_image_model_policy.py`,
  `idol_execute_image_generation_request.py`, and
  `idol_02b_batch_api_runner.py`.
- Revisioned section authoring and exact merge:
  `idol_harness_sections.rb` plus `validate_harness_artifact_contract.rb`.
  Extraction requires an explicit audio-to-visual section map; equal-looking
  section ids are never joined by inference.
- 03V authoring, upload queue, playback review, and handoff:
  `validate_generated_branch_cut_review.rb`,
  `idol_prepare_production_cut_review.rb`,
  `validate_production_cut_review.rb`,
  `validate_audio_branch_cut_placement.rb`,
  `validate_video_prompt_storyboard_assist.rb`,
  `idol_prepare_video_prompt_authoring.rb`,
  `validate_video_prompt_manifest.rb`,
  `idol_video_prompt_section_qa_worklist.rb`,
  `validate_video_prompt_section_qa_readiness.rb`,
  `idol_03v_generated_playback_intake.rb`,
  `idol_03v_playback_review_worklist.rb`,
  `idol_03v_playback_decision_sheet.rb`,
  `idol_03v_refresh_playback_surfaces.rb`,
  `idol_03v_record_playback_review.rb`, and the two apply helpers.
- 04 edit source intake, marker evidence, recipe work, QC, and worklists:
  `idol_video_source_intake.py`, `idol_edit_recipe_alignment_evidence.py`,
  `idol_edit_marker_contact_sheets.py`, `idol_video_sync_workbench.py`,
  `idol_video_ffmpeg_revise_render.py`, `idol_04fx_compile_recipe_effects.py`,
  `idol_04fx_transition_opportunity_seed.py`, `idol_edit_delivery_qc.py`,
  `validate_edit_map_readiness.rb`, `validate_edit_finishing_fx.rb`, and
  `idol_edit_readiness_worklist.rb`.
- 05 package, publication, and measured social evidence:
  `validate_package_readiness.py`, `validate_final_delivery_manifest.py`,
  `validate_publishing_plan.py`,
  `idol_social_release_sync.py`,
  `idol_platform_draft_upload.py`, `idol_social_evidence_snapshot.rb`,
  `validate_social_analytics.rb`, and `idol_title_output_registry.py`.

Do not promote `idol_low_source_first_rebuild_plan.py` into this quick map as a
general 04 marker-plan builder without refactoring. It is a LOW/0526-derived
source-first draft helper with embedded run assumptions. For new runs, use the
generic schema, evidence, contact-sheet, and workbench helpers above, or refactor
the one-off first.

## Current Script Registry

### State, Queue, And Skill Contracts

- `idol_startup_admission.rb`: prepare and compile the hash-bound Overall/CDD
  startup admission in the existing session. It verifies the exact run
  binding, selected profile/checkpoint, graph-projected Role Context Pack
  receipt, Current Assignment Delta envelope, and twelve-block launch shape,
  and holds on stale bytes,
  owner/scope conflicts, illegal stage jumps, or unauthorized paid/external/
  public actions. It only assembles and validates transport; it never authors
  creative truth, opens workers, writes canonical files, grants Founder locks
  or approval, or performs external action.
- `idol_harness_stage.rb`: validate, list, and resolve the canonical semantic
  stage registry at `automation/harness-stage-registry.yaml`. `list-phases` and
  `resolve-phase TOKEN` expose five semantic operator phases while retaining
  every stage, owner, session, and Founder gate. New operator-facing names and
  commands resolve through the registry's stable semantic stage ids or its
  current public codes only. Retired stage labels and filenames are rejected.
- `idol_harness_context_pack.rb`: compile a read-only, source-hashed active
  stage/section context pack plus whole-song continuity signature from existing
  run artifacts and state-check output. The pack is always
  `derived_context_only`; it cannot create creative locks, Founder approvals, or
  production readiness by implication. `--write` without an explicit output
  uses the run-owned `work/context-packs/STAGE/SECTION.yaml` derived-work path;
  a cached `--state-json` input must also remain inside the repository so its
  source hash is portable and auditable. It projects only active, hash-matched
  `interpretation_receipt` rows and their selected cells/crops. A later worker
  consumes those rows without reopening the source. Only the active
  `image_prompt_section` profile at `image_prompt_compilation` is accepted, with
  exactly one section id, Core Cut id, and Branch Cut id. The script rejects
  every retired profile or mismatched scope. It emits
  the Context Pack v7 hash-bound section projection: lossless active 02A cuts,
  causal-only whole-video spine, exact adjacent boundaries, and one row per
  unique physical visual file with all bindings. It explicitly excludes
  other-section cuts/prompts/references and broad history; the validator proves
  the projection against the canonical storyboard hash and cut-value digest.
  Every visual path is resolved through the shared realpath-aware source
  admission gate: only the exact current run, the exact current-title package,
  or `source-materials/` is admitted. Another run, `scripts/tests/`,
  maintenance surfaces, and symlink escapes fail before becoming worker
  context.
  The Front Planning entry additionally requires a reviewed, promoted
  Department Dispatch, or the one exact frozen legacy receipt baseline for
  unchanged historical bytes. `optional_stage_resume` remains available elsewhere only
  for a real resume, cross-session handoff, or physical-shard audit.
- `idol_role_context_pack.rb` plus `lib/idol_role_context_pack.rb`: verify the
  complete registered profile/Dispatch source closure, project only the exact
  current-node instruction fragments, bind the resolved Grok or Cursor snapshot,
  and emit/validate `idol-role-context-pack.v1`. The pack replaces broad runtime
  instruction rereads, preserves named creative source pointers, and may project
  only exact-scope compact v3 Founder quality patterns into matching Director or
  worker sessions. Raw Founder wording/transcripts are excluded; one pack carries
  at most twelve author-prioritized patterns and one semantic source-digest edge.
  It fails closed on stale or ambiguous bytes and owns no creative, lock, review,
  or promotion authority.
- `idol_mv_git_worktree.rb`: project the existing single-writer Department
  Dispatch into an optional physical Git lane. `init-run` creates one
  run-integration branch from an exact `main` SHA; `open-lane` creates one lane
  from an exact integration SHA only after current Dispatch validation when
  `--apply` is used. `merge-ready` checks accepted Director review, clean
  committed bytes from the run-integration worktree, exact Dispatch artifact
  paths, ancestry, and same-path integration drift but never performs the
  merge. Dry-run is the default;
  worker-to-main merge, creative authority, promotion, automatic branch
  deletion, and destructive cleanup are forbidden.
- `validate_department_dispatch.rb`: validate one provider-neutral studio
  dispatch from prepared launch through runtime skill/linked-read digests,
  bounded worker return, director review, and exact-hash promotion. It enforces
  the shared Studio Kernel, exact selected profile/checkpoint role, stage,
  skill and linked-read closure, the registered twelve-block launch shape,
  bounded task id, Founder epoch, source/write boundaries, Anti-Flat evidence,
  the CF/MV run boundary, canonical predecessor closure, unchanged-review
  receipt reuse, run-local correction sources, exact failed-output scope,
  frozen unaffected hashes, legal retry routing, and the initial-plus-two
  maximum of three review submissions. Submission 3 cannot open a fourth child
  retry. It checks structure and bytes only; it never
  authors or judges the Current Assignment Delta or any other creative truth.
  Founder Workbench studio-role dispatch separately enforces the stable
  `session_key = studio_role + assignment_key` identity used to resume a
  durable studio session.
- `validate_terra_section_lifecycle_receipt.rb`: compatibility-only validator
  for frozen historical Terra section lifecycle receipts. New or materially
  resumed production uses the active Context Pack v7 section projection and
  assigned logical section owner; this validator cannot authorize a new Terra
  route, creative PASS, or canonical promotion.
- `validate_skill_application_receipt.rb`: legacy-only validator for historical
  human/model-authored skill receipts. New or materially resumed work must not
  create or refresh one; the state checker may consume only the one newest
  stage-local receipt whose exact path and SHA still bind unchanged canonical
  bytes as a frozen baseline.
- `idol_creative_truth_guard.rb`: scan one run's `work/` scripts and fail on an
  actual canonical creative write target, run-owned creative planning-state
  write, script-authored creative-review verdict, or script-claimed model
  authorship while allowing read-only scanners that write only scratch evidence.
- `validate_schema_repair_candidate.rb`: validate one diagnostic schema-repair
  candidate, candidate/source/schema bytes, unchanged canonical target, current
  contract version, exact-copy JSON pointers/value hashes, and the reviewed
  Department Dispatch that returned those bytes. It cannot promote or repair
  the target.
- `validate_harness_contract_version_registry.rb`: verify every current and
  current-only readable version declared by the central router is present in its
  owning schema, with unique ids and existing path-based producer files. It also
  requires active-stage and shared-script authoring schemas to be registered,
  rejects exact duplicate active schemas, and reports high-overlap pairs for
  review without authorizing a merge. It never migrates an artifact or selects
  creative content.
- `idol_harness_expert_gate.rb`: evaluate conditional song-craft, story/camera
  directing, choreography execution/feasibility, the structural presence and
  hash/coverage validity of the mandatory 02A LLM creative-context review, and
  edit-grid hygiene gates. It does not count camera tuples, repeated words,
  prompt hashes, spaces, actions, or semantic similarity to judge creativity.
  Historical versions remain evidence-only; active 01 v3.0, 02A v3.0, and
  contextual review v7 are required for the current gate. A ready claim or
  `--strict` turns an applicable missing contract into failure.
  Use `--output PATH` to persist the hash-bound JSON report required by actual
  deterministic 02B materialization.
- `idol_harness_shadow_eval.rb`: validate and compare baseline/candidate graph-engineering
  result ledgers against `automation/harness-shadow-eval-suite.yaml`. Quality,
  evidence, and hard-gate non-regression decide first; input/output token,
  wall-time, tool-call, and retry targets can only upgrade a quality-safe result
  from conditional to full pass.
  It re-hashes the graph-engineering/source/task manifests, execution manifests, and case
  outputs; requires one resolvable git commit; and rejects shared profile
  artifact roots or paths before scoring.
  `policy` reports the executable v31 Overall/CDD/Edit Director/worker routing policy and
  operator-supplied candidate requirements. `route ROUTE_ID` requires
  `--execution-scope direction_discovery|stage_execution|multi_stage_execution|run_resume|full_flow`;
  it fails when the scope is missing, invalid, or incompatible with the route.
  `--select-agent AGENT_NAME` selects only a declared alternative or escalation;
  every Ultra alternative additionally requires an
  `--escalation-trigger` valid for both route and agent.
  The evaluation baseline remains
  `idol_sol_creative_synthesis/gpt-5.6-sol/xhigh/high`; it is not the interactive
  default. The project config leaves that default to the Founder session.
  active profiles record custom-agent id, model, scope-bound effort
  policy, verbosity, Codex surface, and reconciled per-agent route usage. One
  Overall Director owns the Founder-facing whole-video recommendation and opens
  one distinct durable Creative Development Director. Logical `worker_high`,
  resolved and pinned from the immutable provider snapshot with Grok preferred
  when ready, owns ordinary non-media named-gap departments and bounded pre-02A
  development blocks; a fresh provider-resolved `section_image_motion_worker /
  worker_high` owns each post-02A section lineage, and Terra
  remains only for the isolated weekly route.
  After the Overall Director approves 02A for one section, a fresh
  provider-resolved `section_image_motion_worker / worker_high` session, using
  the exact selected provider source and immutable snapshot, owns exactly that
  physical section's image-motion lineage: it validates 02A, compiles and
  reviews that section's 02B, then carries the same section through image
  generation/review and 03V handoff. A hash-bound checkpoint may resume in a
  new physical section session without rereading unchanged owner material or
  changing section, prompt, attachment order, or creative state. Codex-specific
  `idol_luna_section_image_motion` on `gpt-5.6-luna` at `max` remains a Codex
  validation description for `validate_idol_model_routing_agents.py`; it is not
  the active MV route default. Disjoint
  section sessions may run in bounded parallel; 04 is a separate section
  edit/QC execution unit. Direct scripts alone check schema, hash, path,
  exact-copy, and output presence. Production OD, CDD, and Edit Director remain
  `director_deep/xhigh`; Sol/Max is one bounded advisory review only and never
  creates a standing Final Director. Sol/Ultra exists only for the locked complete-
  full-flow route. Effort never changes for availability. Active
  comparisons reject 5.5 and cross-family ledgers. Codex effort labels are not
  Responses API effort labels.
- `idol_storyboard_probe_contract.rb`: retired NONCANONICAL capability-test
  validator retained for historical probe evidence only. Its child-keyframe
  vocabulary and compact attestations are not readable or writable active 02A
  truth and must not be used as a Core-Cut/Branch-Cut compatibility route.
- `validate_idol_model_routing_agents.py`: cross-check the active
  `.codex/config.toml`, the exact v19 active `.codex/agents/*.toml` set,
  `automation/harness-shadow-eval-suite.yaml`, and the refreshed model catalog.
  It rejects project-level root model/effort/verbosity pins; requires the
  Overall Director, distinct Founder-visible CDD, physical Song Room,
  integrated reference generalists, conditional Member Visual Identity owner,
  pre-02A development blocks, fresh one-section Luna production owner, fresh
  Edit Director/shards, bounded Sol/Max advisor, explicit Ultra, and weekly-only
  Terra profiles; validates Codex/Grok provider-neutral role parity, reviewed
  stage capacity plus lower-provider backpressure, flat delegation, direct-
  script boundaries, and no standing Final Director. It rejects effort
  below those pairs, an unregistered route profile, an invalid scope, and an
  availability-driven silent downgrade. The active effort vocabulary is only
  XHigh/Max/Ultra, and routine or bounded work must use the minimum sufficient
  profile; every Ultra selection requires `--escalation-trigger` registered for
  both that route and the selected agent. The
  catalog is a current dispatch capability check only; saved shadow ledgers are
  not tied to current catalog bytes, CLI version, or config hashes. Use `--json`
  for a machine-readable result. Fixture-only `--catalog-json` keeps tests
  deterministic.
- `idol_harness_optimization_acceptance.rb`: noncanonical active local-lineage
  acceptance suite. It uses temporary synthetic fixtures only—never live run
  creative truth—and runs prompt compilation, image-request/source admission,
  multi-section local revision/expansion, active-instruction bias, section
  export, provider-resolved post-02A worker routing, image-correction, 03V, and contract-integrity
  regressions.
- `idol_harness_sections.rb`: inactive historical shard helper. It is not
  admitted by the active Front Planning-centered MV route.
- `idol_prompt_packet_compile.rb`: validate one physical 02A v3.0 section shard
  and one human/model-authored 02B delta v1.6, then validate its exact Hero Core,
  Official Core, or Official Branch current-title/reference inspection receipt and
  deterministically serialize its authored components into a noncanonical 02B v2.6
  section artifact. Each Production-Cut prompt retains five required items with fixed
  five-line serialization (`Identity reference rule`, `Scene intent`,
  `Visible details`, `Action cue`, `Avoid`) and the required `4K`,
  `high quality`, and `high detail` terms. The compiler never authors,
  infers, paraphrases, repairs, pads, or fills creative prose. It validates
  structured background/space, still-camera/composition,
  light/color/material, pose/state, action/hold, and object/environment
  response components plus current-title member visual, governing scene or
  sequence reference, and supporting-component bindings in one combined order,
  face-visibility policy, expected output
  paths, and exact section/Branch-Cut coverage. New output records local
  section/Core-Cut/Branch-Cut/neighborhood lineage. With
  `carry_forward_source_02b`, a revision may supply only changed packets; the
  compiler exact-copies omitted approved packets only when every applicable
  local hash remains current. No face-only lane or historical packet version
  is admitted.
- `idol_prompt_packet_section_merge.rb`: verify noncanonical section artifacts
  compiled from active delta v1.6 and their exact current `fp_final` Workbench
  decision intakes, then
  losslessly order and merge already-authored packets into canonical 02B v2.6.
  Whole 02A SHA drift is accepted only for sections with current local lineage.
  It does not author,
  summarize, or repair prompt text.
- `lib/idol_prompt_presence_contract.rb`: shared validation for render-facing
  02A choreography-presence policy. It writes no sentence and rejects every
  dance/choreography token in absent/minimal generator prose.
- `lib/idol_xai_api_media_profile_contract.rb`: shared fail-closed resolver for
  xAI media registration and request snapshots. The current
  `registration_required` branch and legacy selection-only evidence HOLD before
  credentials or transport; only one exact active provider-source path, SHA-256,
  profile id, model, API version, endpoint operation, request/response contract,
  and no-fallback binding can resolve. It grants no readiness, paid, generation,
  review, or promotion authority.
- `lib/idol_image_execution_lane_contract.rb`: shared fail-closed resolver for
  provider-omitted current-session native image execution. It binds Codex to
  `imagegen`, Grok to `image_gen`/`image_edit`, keeps API selection explicit,
  and forbids cross-provider tool/auth aliasing or fallback.
- `lib/idol_generated_review_post_pass.rb`: shared mechanical transition for
  an already-authored all-pass generated review. The Founder intake admits
  only `founder_review`; the delegated G2 CDD intake admits only `cdd_review`.
  After that caller-specific eligibility proof it applies status, local
  non-generative upscale, active review validation, and typed 03V readiness
  without creating a pixel verdict or widening authority.
- `lib/idol_grok_video_execution_package.rb`: shared fail-closed Grok video
  package resolver. It exact-binds the current provider registry and Grok
  source hash, validates the selected tool/duration/resolution and first passed
  Production Cut, preserves an exact Founder-selected two-to-three-image order
  for reference-to-video, and can copy only those inputs plus unchanged prompt
  bytes into a non-overwriting local operator package. It performs no provider
  call itself. The active Grok physical section session may execute only the
  exact registered native video tool after current-session inventory/adapter
  match and cue-specific Founder external-generation authority; no other
  provider tool/auth fallback is legal. The package resolver grants no
  generation, playback, edit, or promotion authority.
- `idol_prepare_image_generation_request.rb`: derive one provider-conditional,
  hash-bound v12 request from one validated canonical 02B v2.6 Hero Core,
  Official Core, or Official Branch packet
  and the exact focused v7 context pack. It preserves prompt bytes and one ordered
  attachment list containing only the applicable current-title member visual,
  governing scene or sequence reference, and supporting component reference. A
  face-only lane is prohibited. The member visual controls appearance
  continuity only and never forces a visible face, frontal gaze, pose, camera,
  crop, or body proportion. OpenAI is locked to `gpt-image-2`; Grok selects
  `image_edit` when attachments exist and `image_gen` when none exist; xAI API
  stays explicit-authority-only. All lanes pin auth/profile snapshots, exact
  output, forbidden prompt rewriting, and no fallback. The
  helper checks the selected section's local 02A lineage instead of invalidating
  every packet on unrelated whole-file SHA drift. The same realpath-aware
  source admission gate rejects another run, tests, maintenance content, and
  symlink escapes before any attachment reaches the request. It prepares only;
  it never uploads, generates, or approves pixels.
- `idol_prepare_image_render_correction.rb`: derive one non-overwriting
  render-local correction request from an active v12 image request, one
  held/rejected generated image, its exact review row, a human/model-authored
  five-item correction with fixed five-line serialization, and bounded Founder
  authorization. It exact-preserves
  current-title member visuals, scene references, and the combined attachment
  order; only `Visible details` and `Avoid` may repair the named pixel defect.
  It emits active `idol_image_render_correction.v8`, never reads historical
  image-request versions, never rewrites 02A/02B, and keeps the attempt inside
  the same provider-resolved section image-motion lineage.
- `idol_image_generation_request_selection.rb`: bind the exact selected request
  paths and SHA-256 values for one section. Duplicate packet ids, request paths,
  or output paths fail before dispatch. xAI requests are re-resolved against the
  current central registry and exact provider source; registration-required,
  legacy, stale, or mismatched snapshots fail before a selection is written.
- `idol_image_generation_section_worklist.rb`: consume the explicit request
  selection, exclude archive/history/superseded/rejected files and requests not
  bound to the current canonical 02B bytes, verify one exact context pack and
  planning source per current section plus disjoint output paths, and emit a
  v8 checkpointed-image-motion-lineage index. Only explicit active selection is
  accepted; directory fallback cannot dispatch. It runs the context-pack
  validator instead of trusting the pack file's outer hash alone. Each ready
  section lists all of its ready requests as bounded-parallel members while
  preserving one exact packet and one disjoint output path per generation call;
  any pack, source, request, input, approval, or prompt hold disables dispatch
  for that section. If every discovered request
  is stale, it emits a schema-valid zero-request `hold` worklist instead of
  crashing or accidentally launching legacy packets. It creates no Codex task,
  calls no model, uploads nothing, grants no approval, and performs no paid
  generation. A non-executable xAI registration is recorded as a section HOLD
  before any request can become ready. Dispatch starts only after a real section
  lineage and current executable provider snapshot are registered.
  Unsupported runtimes serialize only their own calls; returned
  outputs remain behind hash, pixel-inspection, and section-review barriers.
- `idol_image_generation_dispatch.rb`: initialize the persistent section
  dispatch ledger, claim disjoint ready requests up to bounded capacity, record
  exact output hashes, require pixel inspection before completion, and manage
  bounded retries. It rechecks worklist and request hashes on every transition.
  For xAI it also re-resolves the current registry/profile snapshot at init,
  before claim, record, and inspect, and validates receipt bindings; a late
  registration, source, model, status, or fallback mismatch HOLDs the ledger.
  The selected API, built-in ImageGen, Grok, or section LLM still performs the
  actual one-packet model call.
- `validate_luna_section_lifecycle_receipt.rb`: validate the active v2 run-owned
  exactly-one-section image-motion lifecycle receipt and its provider-neutral
  registered-runner execution record. It verifies the immutable `worker_high`
  provider-capability snapshot, Overall-promoted 02A boundary, source/output
  hashes, inspected-asset coverage, 02A Official Core/Branch mappings, typed CDD
  Production Cut review, direct-scene/sequence evidence, and required 03V
  playback. The worker returns to CDD; Founder final selection and Overall
  promotion stay separate and are never inferred. The lifecycle ends at the
  hash-bound 03V handoff; 04 uses a separate edit/QC receipt.
- `idol_harness_state_check.rb`: broad historical run-state reporter. Until its
  stage table is registered against the active route, use the stage-specific
  active validators and registries as advancement authority.
- `idol_harness_frontier_check.rb`: default low-latency active-run preflight.
  It validates `automation/current-next.yaml`, selected-run containment and
  existence, and only the selected unit's explicit path/SHA-256 pairs. It emits
  measured elapsed time, checked rows, and blockers without scanning unrelated
  files. `--full-audit` delegates to the broad state checker and reports its
  result separately for explicit, harness-closeout, or release-closeout use.
- `idol_harness_refresh.rb`: local refresh wrapper for state report, blocker
  worklists, action queue, next unit, and validation.
- `idol_harness_action_queue.rb`, `idol_harness_next_unit.rb`, and
  `idol_harness_current_next.rb`: compact the current blocker state into
  operator-facing next-action surfaces. `automation/current-next.yaml` is the
  canonical pointer; use `idol_harness_current_next.rb --render-from-yaml ...`
  to write or check the derived Markdown readout without reopening upstream
  next-unit/founder-gate state.
- `idol_harness_founder_gate_packet.rb`,
  `idol_harness_record_founder_decision.rb`,
  `idol_harness_apply_founder_decision.rb`, and
  `idol_founder_pass_harness.rb`: record/apply explicit founder decisions and
  refresh related automation surfaces. They do not create approval by
  implication.
- `idol_skill_contract_check.rb` and `idol_skill_contract_matrix.rb`: verify
  skill read/write/schema/reference routing contracts.
- `idol_instruction_surface_audit.py`: validate the quality-first instruction
  surface policy, static startup word budgets, conditional detail
  index/activation routes, every policy-declared protected creative/authority/
  lifecycle/model invariant, and the frozen maintenance-history boundary. Length targets warn;
  reviewed static ceilings, missing quality terms, orphaned detail, and history
  regrowth fail. Long indexed conditional detail has no global length cap.
- `idol_script_registry_check.rb`: verify that this registry mentions every
  current reusable script and does not list removed script files.
- `scripts/lib/idol_handoff_keys.rb`: shared internal helper for title and
  handoff key normalization. It is not a standalone command.
- `scripts/lib/idol_02a_storyboard_contract.rb`: shared internal 02A contract
  helper for complete Core-Cut/Branch-Cut lock shape and exact section-shard
  Core-Cut coverage, local invariant/boundary/Core-Cut/Branch-Cut/neighborhood lineage, and
  realpath-aware visual-source admission. Section `cut_ids` remains an exact
  coverage roster but is excluded from packet-local creative hashes, so adding
  a cut invalidates only its affected same-section neighborhood instead of
  every packet in that section. The compiler fails fast on its errors; the 02B
  validator accumulates the same errors without maintaining a second semantic
  implementation.
- `scripts/lib/idol_03v_source_discovery.rb`: shared one-pass, hash-bound 03V
  source discovery used by the source snapshot and authoring-prep commands. It
  owns the shared Founder-pass/authoring disposition and cut-id normalization
  contract so placement, preparation, and the active manifest do not diverge.
- `idol_03v_source_snapshot.rb`: materialize the read-only source snapshot
  returned by that discovery contract; it cannot author subject or camera
  motion.
- `scripts/lib/idol_03v_language_contract.rb` and
  `scripts/lib/idol_video_prompt_section_qa_contract.rb`: historical
  video-prompt-index support libraries. They are evidence-only and are not
  loaded by the active v8 manifest/QA route.
- `scripts/lib/idol_skill_contract_paths.rb`: shared read-only path-token
  extraction and normalization used by the skill contract checker and purpose
  matrix; it does not validate path existence or write output.
- `scripts/lib/idol_social_release_contracts.py`: shared run/content/path,
  canonical queue-digest, and Founder-approval validation for local release
  projection and platform draft upload. It performs no external action.
- `scripts/lib/idol_post05_trace.py`: pure provider-neutral 05-to-04 release
  provenance canonicalizer. It performs no I/O or creative judgment; package,
  delivery, closeout, and analytics callers use it to recompute identical Edit
  Segment, screen-node, package-graph, and asset digests.

### Schema And Semantic Validators

- `validate_checkpoint_closure_catalog.rb`: validate the recipe-owned
  checkpoint closure catalog schema, prefix, and unique requirement ids.
- `validate_standing_constraint_catalog.rb`: validate the standing-constraint
  index schema, unique ids, and owner-path presence. The catalog is an index,
  not a second rulebook.
- `validate_company_ops_idol_bridge.rb`: fail-closed Company Ops grok-build
  ingress. A packet cannot execute before IDOL Department Dispatch, native
  Goal, and Role Context Pack admission.
- `validate_helper_consumption_receipt.rb`: validate a helper-consumption
  receipt when a parent presents a helper return as a graph edge.
- `validate_front_planning_sequence_core_hold.rb`: HOLD when one Sequence Unit's
  frames are counted as multiple Core creative-hypothesis candidates. New Front
  Planning is checked by default. Frozen COLOR STAY v17 skips unless
  `--admission-graph`.
- `validate_front_planning_local_pairwise_global.rb`: HOLD when new Front
  Planning omits Local/Pairwise/Global presence or assigns the wrong owner.
  Frozen COLOR STAY v17 skips unless `--admission-graph`. This is not v18
  admission.
- `validate_run_followup_sidecar.rb`: validate the run-owned improvement-review
  sidecar. v1 remains readable; v2 may record a shadow Founder
  creative-feedback closure. Require it on material helper recurrence. Never
  auto-write skills or treat validator pass as a production gate.
- `validate_front_planning_readiness.rb`: validate the active Front Planning v17
  complete PRE-00-rooted full-storyline lineage, evidence,
  reference-disposition, current-title visual, section, and whole-video
  closeout contract.
- `validate_01_section_direction.rb`: validate active 01 v3.0 Official Core section
  projection and exact complete Front Planning/storyline/reference lineage.
- `validate_master_storyboard.rb`: validate active 02A v3.0 immutable imported Official Core and Branch-plan
  coverage and exact 01/Front Planning/full-storyline lineage.
- `validate_json_schema.py`: generic local JSON/YAML schema validation helper;
  duplicate YAML keys fail before schema evaluation instead of silently
  replacing the earlier professional contract value. Error output is capped at
  20 per document by default; `--max-errors 0` is the explicit unlimited audit.
- `validate_harness_context_pack.rb`: verify that a derived context pack uses a
  registered stage id, readable source paths with matching SHA-256 hashes,
  unique active sections with adjacent boundary context, independent readiness
  axes, exact active interpretation-receipt projections and inspection actions,
  the Context Pack v7 section projection, lossless active 02A cut digest, unique
  physical visual count versus retained binding count, and explicit
  no-approval/no-external-action guards. It reruns the same visual-source
  admission check used by context and request builders. Error output uses the
  same `--max-errors` convention.
- `validate_reference_interpretation_contract.rb` plus
  `lib/idol_reference_interpretation_contract.rb`: verify that Front Planning's
  01R and 01R-C owner rows bind observation, selected evidence locator,
  selected function, inspected source bytes, and revision evidence; verify that
  01 consumes the exact receipt through `interpretation_bindings`. A model or
  session change is never accepted as a reopen trigger, and selected
  contact-sheet/frame work cannot fall back to the whole source: selected
  sheet/board cells require cell-id-matched derivative path/SHA rows. New or
  resumed 01 work declares `reference_interpretation_receipt.v1`; integrated
  Front Planning 01R and optional 01R-C owners declare the same value in
  `interpretation_contract_version`. Historical artifacts are evidence only
  and cannot resume or author active work.
- `validate_harness_artifact_contract.rb`: validate an additive
  `envelope + payload` revision contract, canonical payload digest, parent and
  typed reference lineage, invalidations, section namespace/transitions, and
  the five independent readiness axes. Legacy canonical artifacts remain valid
  until wrapped or physically sharded.
- `validate_selected_audio_analysis.rb`: active selected-audio source/hash,
  lyric, craft, selected range, section order/timing, and audio-only ownership
  validation.
- `validate_audio_motion_director_map.rb`: active audio rhythm evidence,
  source/hash, section order/timing, trigger, and downstream-boundary
  validation. It rejects scene, choreography, camera, and prompt authoring.
- `validate_audio_branch_cut_placement.rb`: validate the hash-bound selected
  audio, passed Production Cut review evidence, detailed timeline,
  animatic/timing table, and concrete Official Core/Branch Production Cut units
  required before new song-led 03V authoring. The legacy script filename does
  not narrow active semantics to Branch-only input. `--require-ready`
  rejects draft, hold, stale, gapped, or overlapping placement truth.
- `validate_cue_bpm_map.rb`: inactive historical cue/BPM-map validator. Active
  MV timing uses post-image Audio-Production-Cut Placement and 03V playback.
- `validate_wardrobe_style_review.rb`: inactive historical wardrobe-review
  validator. Active visual identity uses the unified current-title member
  visual, governing scene/sequence, and supporting-component attachment order
  owned by Front Planning and the title-asset production route.
- `validate_02b_imagegen_contract.rb`: active 02B v2.6 authoring and preflight
  validation, including the ordered current-title member visual, governing
  scene/sequence reference, and supporting-component reference plan. `--run-root PATH` lets a temporary compiled file
  be checked against its real owning run without writing the audit artifact
  into that run; normal run-owned 02B validation still infers the root from the
  file path. It rejects face-only inputs and historical packet versions. It
  validates ids, hashes, current local section/boundary/Core-Cut/Branch-Cut lineage,
  active section-delta exact-copy transfer, types, enums, manifests, outputs,
  and approval state. Missing active local lineage is a hold; no historical
  whole-02A fallback is accepted. It does not fail creative work for
  action/camera/space/reference/prompt similarity. It emits at most 20 distinct
  errors by default; use `--max-errors 0` only for an out-of-context exhaustive
  audit.
- `validate_generated_branch_cut_review.rb`: validate active v4 generated
  Branch-Cut image reviews against current 02A/02B truth and exact image bytes.
  New review rows
  may bind a current packet value hash or carry an unchanged passed row through
  an exact prior review path/SHA and prior row-value SHA. A section review
  carries only when its complete ordered 02B packet-set hash is unchanged, so
  one revised image does not invalidate unrelated passed pixels. Every passed
  source image must also own a valid 3840-long-edge local upscale sidecar before
  the review can close for downstream use.
- `validate_local_image_upscale_receipt.py`: validate exact source/output
  hashes, decoded dimensions, aspect preservation, PNG format, no-downscale
  behavior, fixed non-generative/no-sharpening policy, and black-pixel damage
  diagnostics for `idol_local_image_upscale_receipt.v1`.
- `validate_video_prompt_index.rb`: inactive historical 03V index validator.
  The active route uses `idol_video_prompt_manifest.v8` and its validator
  directly.
- `validate_video_prompt_manifest.rb`: validate the active 03V v8 manifest,
  storyline→selected Sequence→Core reference→passed Official Core/Branch
  derivation, exact prompt hash, one-frame default `image_to_video`,
  Founder-selected ordered multi-reference `reference_to_video`, 6/10-second
  and 480p/720p bounds, no fallback, and same-job CDD 480p review before a 720p
  candidate.
- `validate_video_prompt_storyboard_assist.rb`: validate the mandatory active
  v4 Motion Storyboard artifact, ordered `official_core|branch` Production Cut
  authority, same-parent default or explicit cross-Core transition, board and
  original image hashes, `@image1` board plus ordered source-image references,
  and the one-image reason. Each board contains one to three passed Production Cut
  images; a longer sequence is split into linked boards.
- `validate_video_prompt_section_qa_readiness.rb`: 03V section QA readiness
  validation. Active section QA binds the exact 03V v8 manifest and exact ordered cue
  coverage per physical section. Contextual mode validates the section plus
  whole-timeline route; Founder-direct mode validates an exact manifest delta
  against a hash-bound passed v6 CDD baseline and integrated Founder receipt,
  carries unaffected scope forward, and requires affected-cue rerun plus
  playback QA.
- `validate_03v_front_playback_gate.rb`: focused 03V front playback/generation
  gate validation.
- `validate_edit_map_readiness.rb`: active v4 04 edit-map readiness validation.
  Every mode schema-validates the edit map and its hash-bound v6 marker plan;
  `--mode final-render` additionally binds the v3
  editable recipe, completed 04FX audit, strict compile manifest, and derived
  final recipe before FFmpeg; `--mode closeout` binds the immutable compile and
  render receipts, exact master bytes, delivery/cutpoint evidence, and required
  manual playback QC through active `idol_edit_qc_closeout.v3`, whose embedded
  final recipe is exact `idol_edit_recipe.v3`, before 05.
- `validate_edit_marker_plan.py`: validate active v6 Official Core/Branch
  Production-Cut/03V lineage, exact screen-progression node carry (including
  Official Core-only cues), planned Edit Slots, frame-aligned Edit Boundaries,
  source bindings, and transition classifications before recipe lock.
- `validate_edit_recipe.py`: validate the frame-canonical v3 edit recipe,
  source hashes/probes, retime, geometry, color/audio truth, and duration-
  preserving transition handles. Final mode requires `final_render_ready`.
- `validate_edit_finishing_fx.rb`: validate 04FX schema and, for v2, re-hash
  the exact v4 edit map, v3 Edit-Segment recipe, v6 marker plan, and passed
  preview so stale FX cannot reach 05. V1 is historical evidence only and
  fails active validation.
- `validate_edit_finishing_fx_compile.py`: revalidate the hash-bound 04FX
  compile manifest, source FX semantics, and compiled final recipe. Final mode
  deterministically rebuilds the canonical merged recipe from the bound FX
  map, base recipe, and effect registry, so refreshed output hashes cannot hide
  a changed projection. A valid zero-effect compile is the audit-complete no-FX
  route and permits only registry metadata-only base-recipe annotations plus an
  explicitly passed, duration-preserving `origin: 04_edit` xfade already owned
  and playback-reviewed by 04. `--immutable-receipt` retains that deterministic
  rebuild at 05 while leaving the historical pre-render edit-map digest frozen;
  it is valid only after the separate live 04 closeout gate passes.
- `validate_package_readiness.py`: fail closed unless the run-owned 05 package
  revalidates the exact 04 closeout, typed 04FX map and compile receipt, complete
  final-render receipt, and byte-identical hash-bound `final_master`. The social
  release helpers call the same semantic contract before projecting a package.
- `validate_publishing_plan.py`: auto-detect and validate either an active
  publishing plan or an immutable closed publishing record; `--mode` may make
  that choice explicit.
- `validate_social_analytics.rb`: validate global post and metric ledger rows,
  expanded content lanes, shared-media/thread relations, and fixed checkpoint
  identity while preserving legacy rows.
- `validate_tiktok_studio_exports.py`: validate hash-bound local TikTok Studio
  import receipts, account-day rows, cumulative video snapshots, exact
  published-post mappings, and explicit unavailable-detail states without
  touching raw ZIPs or calling TikTok.
- `validate_signal_deck_traffic.py`: validate the separate Signal Deck aggregate
  traffic ledger. It rejects any visitor, session, cookie, IP, or raw-event
  field.
- `idol_collect_platform_metrics.py`: Founder-approved, read-only raw-metric
  collector for published X, TikTok, YouTube/Shorts rows and aggregate Loom
  Signal Deck production traffic. It consumes local OAuth credentials internally,
  records no payloads or secret values, validates staged ledgers before writing,
  and cannot publish, upload, schedule, edit copy, or retrieve personal data.
  Run without `--apply` for an eligibility-only dry run; Instagram remains
  manual-attachment-only.
- `idol_import_tiktok_studio_exports.py`: local-only Sunday ZIP importer for
  Founder-provided TikTok Studio `Overview.csv`, `Viewers.csv`, and
  `Content.csv` exports. It hashes the ZIP/member bytes, rejects conflicting
  overlap, keeps unmatched videos out of the post ledger, and writes a
  normalized platform metric only for an exact published TikTok video ID.
- `idol_vercel_analytics_setup.py`: localhost-only one-time setup form for the
  Vercel token and project identifiers consumed by the metric collector. It
  writes `.runtime/secrets/vercel.env` at mode `0600` and emits value-free
  readiness only; tokens never belong in chat, command arguments, logs, or Git.
- `validate_terminology_guard.rb`: terminology/retired-label guard. Use
  `--tracked-only` for reproducible graph-engineering acceptance that excludes ignored
  local transfer copies; omit it when deliberately auditing every local note.

### Evidence Extraction Only

- `idol_candidate_audio_probe.py`: local selected/candidate audio measurements,
  lyric metadata extraction, novelty-aligned section candidates, plots, and
  reports. Section candidates are evidence only; Codex/human listening must
  decide the production section map.
- `idol_audio_precision_markers.py`: sub-second audio evidence extractor for
  selected-audio and reference-audio files. Run with `scripts/idol-video-python`.
  It writes beat-grid, onset-candidate, pitch-contour-proxy, and repeated-motif
  candidate sidecars plus a JSON marker map. In `selected-audio` mode, outputs
  may feed selected-audio analysis, the audio rhythm evidence map, 00A
  editability guards and Front Planning questions, and later 04 edit-marker
  planning after human review. In
  `reference-audio` mode, outputs may feed reference-song fit, Suno prompt
  planning, hook/motif analysis, and vocal/pitch evidence only; do not generate
  cut-pressure scores or current-run MV section video functions from reference
  audio alone.
- `idol_reference_music_feature_extract.py`: reference-song tempo, onset,
  energy-band, percussive/harmonic, chroma, and pitch-proxy measurements.
  It must not identify instruments, write melody/topline analysis, decide song
  fit, or produce Suno prompt wording.
- `idol_reference_audio_metrics.py` and
  `idol_reference_intro_audio_metrics.py`: legacy reference-audio measurement
  helpers. Treat outputs as evidence rows only.
- `idol_reference_section_segments.py`: reference-audio novelty segmentation
  candidates. Measurement buckets are not section-function decisions.
- `idol_edit_recipe_alignment_evidence.py`: edit alignment evidence from source
  motion peaks and selected-audio onset/beat grids. It must not mark a final
  edit pass; contact-sheet/playback review remains required.
- `idol_cue_bpm_map.rb`: inactive historical cue/BPM-map construction helper.
  Do not route active MV work through it.

### Contact Sheets And Review Surfaces

- `idol_pre00_selection_handoff.rb`: atomically create the one stable
  `RUN/research/pre00-selection-handoff-v1.yaml` exact-copy bridge from a
  Founder-selected PRE-00 `1.8` radar using the active handoff v4 payload,
  including the nested reference-audience lineage, or inspect that bridge
  read-only before Workbench context binding. The stable compatibility filename
  does not name the payload schema. Inspect mode rechecks the current radar
  path/hash/status, every exact-copy binding, and the payload hash; it starts no
  model turn and authors no later-stage truth.
- `idol_review_projection_assembler.rb`: compile the derived review source set
  from one stable run-owned projection-owner index, exact-copy eligible owner
  pointers into the single stable manifest/HTML projection, and synchronize
  only that run's automation-owned pending entry in `current-next`. It uses
  compare-and-swap plus rollback, creates no task or approval, and never owns
  media or creative state.
- `idol_founder_direct_update_commit.rb`: native-Workbench-only deterministic
  writer for one visible sequence reorder plus one exact Founder sentence after
  the read-only director returns all five required checks. It transactionally
  commits plan/canvas, the intervention receipt, affected invalidations,
  projection revision, and same-run current-next state, or restores the entire
  prior set. It cannot infer a creative change, retry, widen scope, or authorize
  external/paid work.
- `validate_02a_creative_context_review.rb`: validate the hash-bound
  active-only `idol-02a-creative-context-review.v7` artifact. It exact-covers
  every 02A section, Core Cut, and Branch Cut, verifies the source
  SHA/schema/content id, checks
  finding ids and continuing Codex/Grok CDD provenance, and
  confirms the whole-video review covers the same sections. V6 requires
  LLM-owned 01-to-02A and Founder-alignment-storyline realization evidence for every cut, permits patch routing
  only to active smallest owners, and prevents a passing section when that review detects
  script substitution. V7 also exact-binds imported Official Core ownership and
  screen progression. It validates evidence shape and verdict coherence only;
  it never evaluates creative prose or decides whether recurrence is good or
  bad.
- `idol_html_review_board.rb`: validate or render deterministic local HTML
  review material from `schemas/html-review-board.schema.json`. Active v12 keeps
  the stable `review/manifests/founder-workbench.yaml` and
  `review/founder-workbench.html`, folds prior review cycles, preserves local
  PASS/HOLD/REJECT decisions across rerenders, and exports the exact review
  target and smallest revision scope. It presents target/message, whole-video and
  section-flow summaries, then section, Core-Cut, and Branch-Cut cards. The
  manifest declares canonical YAML/JSON sources by path and SHA-256 and exact
  path/SHA-bound media rows. Output is a rebuildable projection under the same
  run's `review/` directory. It refuses stale source/media bytes, missing
  pointers, URL media, repository escape, symlink traversal, duplicate ids, and
  replacement of a handwritten HTML file. Browser controls save local draft
  decisions and export JSON only.
- `idol_review_decision_intake.rb`: preserve one exact active board-v12 Workbench
  export and write a v12 routing intake under the owning run. It rechecks the
  manifest hash, board revision, target hierarchy, decision annotations, and
  revision scope; it neither adds a verdict nor writes canonical creative truth.
  Only a complete explicit all-PASS intake for the active
  `generated_branch_cut` cycle exact-promotes the bound v4 returned review from
  `founder_review` to `passed` and invokes the local passed-review upscaler. It
  changes no row-level pixel judgment, validates the exact review and
  derivatives, reuses only already valid receipts, and reports 03V readiness
  only through the typed passed Production Cut Review plus ready Audio
  Production Cut Placement v5. HOLD, REJECT,
  partial, stale, and other-cycle intakes do not promote status, process pixels,
  or route 03V. For every other active cycle, the same complete intake processes
  only exact PASS-card media that is a run-owned generated image marked for
  generated-output pixel review. It excludes references, planning evidence,
  promoted assets, video, HOLD, and REJECT; a member-visual result routes to
  current-title promotion and no non-Branch visual reports 03V readiness.
- `idol_g2_delegated_pixel_close_intake.rb`: close only a generated-pixel scope
  already authorized by an exact Founder G2 `draft_keyframe` envelope. It
  revalidates the envelope pointer/value hash, section/Cut set, provider,
  attachment order and bytes, output and budget, P3-Ci-to-V-Ci cohort carry,
  section writer dispatches, execution receipts, and per-packet review hashes.
  Every applicable contextual criterion must be at least 3, the motion anchor
  must be 4, and target/message violations and material drift must be false.
  Failure is an `authority_request` or mechanical `HOLD`, never fallback; the
  existing Founder all-PASS intake remains a separate route.
- `idol_planning_image_contact_sheet.py`: deterministic Front Planning
  planning-image contact-sheet helper. Its transient v2 manifest uses
  `planning_images`; these inputs are review candidates, not Core Cuts,
  Branch Cuts, or a generation-resume surface.
- `skills/idol-world-still-reference-department/scripts/build_contact_sheet.py`:
  deterministic image-only World/Still comparison-sheet builder. It verifies
  every local candidate path and SHA-256, displays the proposed main/support
  class and authored screen role, preserves model-authored order, uses
  uncropped contain-fit cells, and writes a mechanical sheet receipt. It never
  searches or opens video, interprets image meaning, selects a reference, or
  replaces individual image/crop bindings with the sheet.
- `idol_pinterest_public_capture.py`: common Codex/Grok CLI helper for one exact
  current-task-approved public Pinterest still. It prefers the public image
  asset, accepts a public image-element capture as a declared fallback, writes
  only run reference-intake or reusable image-source paths, verifies a minimum
  720-pixel short edge, and records a mechanical path/hash/dimension receipt.
  It does not search, bulk-scrape, select, disposition, or approve attachment.
- `idol_edit_marker_contact_sheets.py`: contact-sheet assembly from an active
  v6 edit marker plan. It creates review surfaces only. Common presets:
  `dense-qc` for
  sub-second source-window inspection, `founder-review` for readable 4-column
  review, `source-preview` for PULSO-style 320x180 two-column source windows,
  `detail` for larger candidate inspection, and `one-second` for broad
  source-window scans.
- `idol_video_qc_sheet.py`: timestamp or interval-based video QC contact sheets;
  its optional manifest hash-binds source and sheet bytes and assigns ordered
  source/label-time cell ids. `--cell-crops-dir` additionally emits one
  hash-bound, timestamp-labelled crop per sheet cell for direct inspection and
  requires `--manifest`. Reuse the same output/manifest paths for an unchanged
  recipe: source bytes, settings, renderer revision and all listed output hashes
  must match before any render is skipped. Unknown or changed existing outputs
  HOLD for version reconciliation; the helper never removes stale siblings.
  For reusable `yt-dlp` evidence, use `one-second` with
  `--segment-duration 5` at or below 60 seconds, otherwise `three-second` with
  `--segment-duration 15`, always with a manifest. Do not make automatic cell
  crops the active hub surface. Use denser presets only for selected ranges.
  Run with `scripts/idol-video-python`. Common presets: `half-second` for the
  legacy default, `dense-qc` for tighter timing review, `one-second` for
  full-flow scans, `two-second` and `three-second` for 01R public-reference
  range scrubs, `source-preview` for PULSO-style 320x180 two-column source
  previews, `founder-review` for readable review sheets, and `detail` for close
  inspection. Split durable reusable sheets with `--segment-duration 15` plus
  `--manifest` rather than making one oversized full-source sheet.
- `idol_two_cut_sheet_crop.py`: deterministic crop/sheet utility for fixed
  two-cut manifest regions. It extracts declared regions; it does not decide
  whether the crop is creatively good.

### 02B Export, Imagegen, And Title Registry

- `idol_openai_image_model_policy.py`: shared OpenAI image model guard. IDOL
  OpenAI image API routes must use `gpt-image-2`; `gpt-image-1` and other image
  model overrides fail before upload or export.
- `idol_export_02b_prompt_manifests.py`: export approved/selected 02B packets
  into packet manifests, pointer-based `exports/02B/sections/Sxx/` API prompt
  packages, and title output registry rows. The root has no all-song API prompt
  aggregate; a boundary packet is assigned once to its execution-owning section.
- `idol_execute_image_generation_request.py`: active v12 Founder-gated image
  executor. Preflight records only usable credential presence and performs no
  provider call. OpenAI execution accepts only the exact `gpt-image-2` profile,
  exact request/approval/count/spend/output bindings, and an explicit matching
  Founder authority id; attachment edits use multipart `image[]` transport.
  The xAI lane executes only from an exact hash-matching provider-owned profile
  that registers model, API version, endpoint, request/response transport, and
  the required image operation; missing or mismatched registration HOLDs before
  credential access. Neither lane falls back, and secrets are never written to receipts.
- `idol_02b_batch_api_runner.py`: historical pre-Branch-Cut Batch runner,
  retained only to identify old records. Every command now fails before local
  preparation or external access. Active execution starts from one validated
  `idol_image_generation_request.v12` per named FP Hero Core, Official Core, or Official Branch Cut; no legacy board/keyframe
  manifest is accepted as a compatibility fallback.
- `idol_cut_keyframe_batch_api_runner.py`,
  `idol_build_two_cut_source_manifest.py`, and
  `idol_split_beat_source_manifest_by_section.py`: legacy beat-source tools
  retained for historical artifact recovery only. New manifest construction,
  sharding, prepare, and paid submit fail closed. Existing submitted-state
  status/download/import recovery remains available in the runner; it cannot
  become a compatibility fallback for new 02B work.
- `idol_title_output_registry.py`: update and validate stable
  `catalog/albums/ALBUM_KEY/TITLE_KEY/output-registry.yaml` pointers. It keeps
  declared future outputs in `outputs[]` but only promotes readable current
  artifacts into `latest_pointers`. Observed HTTPS publication URLs use the
  dedicated `remote_publication` output type and `published` status; they are
  never mistaken for local files. Active v1.1 rows use `branch_cut_image`,
  `core_cut_id`, `branch_cut_id`, and `output_roots.branch_cut_images`; legacy
  keyframe registries remain evidence-only and are not auto-migrated.
- `idol_social_evidence_snapshot.rb`: filter the global social ledgers into one
  compact, run-owned, source-hashed v3 view that retains detailed/normalized
  lanes, member and shared-media lineage, learning dimensions, and distinct
  T+24h/T+72h/T+7d checkpoints instead of reducing them to a same-day
  latest-only row. It also preserves append-only 05-to-04 release-provenance
  fields when present and records
  `no_post_records`, `posts_without_published_facts`,
  `published_without_metrics`, `published_partial_metrics`, or `measured`
  without inventing performance. `measured` requires metric coverage for every
  published fact; each publication fact requires `published_at` plus a platform
  id or HTTPS URL. Source ledgers validate before a staged snapshot atomically
  replaces the prior file. The canonical ledgers are default; a noncanonical
  source requires a recorded `--ledger-override-reason`.

### 03V Video Prompt, Playback, And Drive Handoff

- `idol_prepare_production_cut_review.rb` and
  `validate_production_cut_review.rb`: build and validate the typed
  `idol-production-cut-review.v2` bridge. It exact-covers the authorized G-40
  scope in Core/child order, binds each immutable 01 Official Core pixel PASS
  or generated Branch pixel PASS by pointer/value hash, and preserves the exact
  storyline, Sequence, Major, Core, screen, and section lineage required by
  03V. `scripts/lib/idol_production_cut_review_contract.rb` owns the shared
  deterministic join checks; no script grants creative PASS.
- `idol_prepare_video_prompt_authoring.rb`: prepare 03V authoring inputs from
  one exact section's active 02A, 02B, passed Official Core/Branch Production
  Cut Review, Audio Production-Cut
  Placement, and storyboard-assist artifacts. It validates and hashes those
  sources, exact-copies the complete PRE-00-rooted storyline lineage into the
  v5 source pack, then writes only that derived source pack and authoring
  request. The
  assigned director/model must author temporal subject and camera motion; this
  helper never writes creative direction or invokes generation.
- `idol_media_execution_adapter.rb`: validate one active v12 image request or
  active v8 03V cue and emit a deterministic execution projection only under
  mandatory `--dry-run`. It performs no API/tool call, preserves exact prompt
  bytes and ordered inputs, and rejects model/tool/auth/resolution fallback. An
  xAI projection additionally re-resolves the central registered-exact branch,
  registry/profile source hashes, model, API version, endpoint operation, and
  active default-disabled status; the current registration-required branch
  HOLDs before a projection is emitted. For a Grok video cue, the optional
  `--write-package --package-root` route creates a non-overwriting exact-copy
  `prompt.txt`, selected `input-XX` files, and hash-bound `package-plan.json`
  under the cue's `execution-ready/` root or `/private/tmp`; it may preserve
  explicit execution HOLDs and never invokes Grok. Execution, when selected,
  happens only inside the exact registered Grok physical session and remains
  separately Founder-authorized for that cue.
- `idol_video_prompt_section_qa_worklist.rb`: build section-level 03V QA
  worklists directly from the active v8 manifest and current v6 section QA. The
  logical reviewer is CDD; the exact provider is only an immutable
  `director_deep` capability snapshot with no fallback. Cue order,
  source-image endpoints, prompt paths, audio cue, continuity, and edit handoff
  come from that manifest; a flat `upload-ready/` pointer is included only when
  it exists under the canonical prompt-output root.
- `idol_prepare_grok_video_prompt_handoff.rb`: prepare an optional v7 external
  video-generator handoff from an already validated active v5 03V source pack
  and authored manifest. It exact-copies the full storyline lineage, requires
  an explicit Founder request, and makes no external call.
- `idol_video_prompt_drive_sync.rb`: inactive historical index/upload-pack
  mirror helper. It cannot hand off or resume the active v8 route.
- `idol_03v_generated_playback_intake.rb`: index generated playback clips for
  a focused review gate and bind present clip bytes by SHA-256.
- `idol_03v_playback_review_worklist.rb`: turn playback intake into packet
  review checks.
- `idol_03v_playback_decision_sheet.rb`: build the compact pass/hold/fix
  decision surface.
- `idol_03v_record_playback_review.rb`,
  `idol_03v_apply_playback_decision.rb`, and
  `idol_03v_apply_playback_review_record.rb`: record and apply explicit
  playback review decisions. They must not infer pass from clip existence.
- `idol_03v_import_generated_clips.rb`: import loose generated clips into the
  run-owned 03V playback review material and optionally refresh focused
  worklists.
- `idol_03v_refresh_playback_surfaces.rb`: hash the focused QA worklist and
  generated clips, then rebuild intake, playback worklist, and decision sheet
  only when inputs or derived-output digests changed. A no-op never records
  playback pass or Founder approval.
- `idol_review_to_grok_handoff.rb`: fail-closed historical wrapper; no input
  read, child process, or write occurs. Current optional Grok transport uses
  `idol_prepare_grok_video_prompt_handoff.rb` with an existing source pack.
- `idol_grok_imagine_drive_sync.py`: inactive historical pre-Branch-Cut
  Grok Imagine package mirror. It depends on retired face-reference,
  cue/BPM-map, and package-index shapes and cannot hand off or resume an active
  run. Active optional Grok transport starts from
  `idol_prepare_grok_video_prompt_handoff.rb`.

### Drive, Workspace, And Platform Utilities

- `idol_local_image_upscale.py`: deterministic local image upscaler. `images`
  processes explicit `SOURCE=OUTPUT` pairs and writes one aggregate receipt;
  `passed-review` keeps reviewed 02B source bytes unchanged, creates one
  3840-long-edge PNG per passed Branch Cut under `generations/upscaled/`, and
  writes the mandatory `SOURCE_IMAGE.upscale.json` sidecar. `passed-visuals`
  applies that same idempotent pass-bound treatment to explicit generated
  visual `SOURCE=OUTPUT` pairs selected by the Workbench intake, including
  passed current-title member clean cards, without claiming 03V readiness. It uses Pillow
  LANCZOS only—no API, generative enhancement, crop, or sharpening—and must run
  through `scripts/idol-video-python`. The active pipeline calls this mode from
  the explicit generated-review Founder all-PASS intake; repeat intake reuses
  only an exact valid derivative/receipt pair and fails closed on partial or
  stale existing output.
- `idol_asset_drive_sync.py`: historical. Local `drive-sync/` is retired
  (2026-08-22). The helper fails closed and must not write asset mirrors.
  Grok Bot PRE-00 uses `skills/idol-grok-bot-pre00-intake`. Member assets
  stay in `assets/`.
- `idol_safe_workspace_cleanup.py`: dry-run-first workspace and artifact-
  lifecycle audit helper. It reads
  `automation/artifact-lifecycle-policy.yaml`, reports supporting-version
  pileups, malformed or unindexed run-owned physical archives, forbidden
  legacy root output lanes, and optional exact-byte duplicate groups. Use
  `--json` for machine-readable evidence, `--hash-duplicates` only when a
  deeper scan is worth the I/O, and `--strict-lifecycle` for a closeout audit.
  None of those report modes selects files for deletion. `--apply` remains
  limited to low-risk caches and temporary files; production artifacts,
  candidates, archives, mirrors, generated media, and duplicate groups are
  always report-only and require a separate Founder-approved cleanup plan. Git
  object files are never cleanup targets, and archive symlinks fail the
  lifecycle audit instead of being followed or ignored. Canonical relations
  cannot cross symlink components, and forbidden root artifact lanes cannot be
  hidden behind symlinks. Misplaced or symlink-owned archive lanes are still
  discovered and reported, and rollback checkpoints must identify their live
  canonical artifact. Permission or I/O failures are surfaced as incomplete
  scans instead of silently skipping archive evidence or crashing the audit.

### 04 Edit And QC

- `idol_video_source_intake.py`: index local raw/additional video sources for a
  run through active `idol_video_source_intake.v2`. Run with
  `scripts/idol-video-python`. Added active sources use only
  `generations/video/raw/additional/`; a populated retired misspelled folder
  holds instead of entering the index. It records source SHA-256 plus
  independent probe, motion, and contact-sheet fingerprints. Unchanged routine
  scans may reuse the shared stat-keyed SHA-256 cache, while forced refresh,
  promotion, and external transfer require a fresh SHA-256. Probe cache v4
  preserves rational frame rates/time base, geometry/SAR/DAR/rotation,
  codec/pixel format/declared bit depth/field order, and color/HDR metadata;
  absent tags stay `unknown` and never imply a color transform. Identical
  component inputs reuse cached evidence, while `--force` explicitly rebuilds.
- `idol_video_sync_workbench.py`: build or revise sync-workbench recipe
  material from explicit run/edit inputs. Treat legacy defaults as examples.
- `idol_video_ffmpeg_revise_render.py`: revise/render video outputs from an
  explicit recipe or source plan. Supports the 04FX local finishing catalog
  (timeline-safe accents plus boundary `xfade`). Treat legacy defaults as
  examples. Prefer `--render-mode filter` when boundary xfade is present.
  V2 `final` renders require the declared container/codec policy and support
  H.264/AAC or ProRes/PCM MOV without silently substituting proxy settings.
- `idol_04fx_compile_recipe_effects.py`: compile a 04FX finishing map into
  recipe-compatible `effects[]` (optional full recipe merge). Does not change
  cut timeline truth. Catalog:
  `skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md`.
- `idol_04fx_transition_opportunity_seed.py`: draft
  `transition_opportunity_audit` points from recipe boundaries + marker-plan +
  structured audio/cue evidence. It groups deterministic events by canonical
  program frame and emits a hashable full-master coverage receipt. Seed only;
  never auto-pass FX.
- `lib/idol_edit_effect_registry.py`: shared registry loader, aliases, parameter
  normalization, and final xfade handle enforcement used by 04FX compilation,
  recipe validation, and local FFmpeg rendering.
- `lib/idol_camera_direction_contract.rb`: shared deterministic translation of
  structured camera codes into concrete generator-facing camera language; the
  02B compiler and validator use the same phrases.
- `lib/idol_source_connection_contract.rb`: exact-copy disk SHA onto
  model-authored source_id/path/locator rows. Emits `connected` /
  `not_connected` and a model-facing pointer without hex. Never fills
  function, disposition, locator, or observations.
- `lib/idol_storyboard_collected_angle_contract.rb`: structural completeness
  and exact-binding checks for model-authored full-storyboard camera-angle
  review. Scripts never infer sameness or uniqueness from labels, families,
  hashes, or numeric angles. Founder exceptions must exact-bind a real lock
  and remain HOLD. Generated-pixel closure is section-scoped and cannot
  treat 02A planning review or blank out-of-scope hashes as complete.
- `lib/idol_storyline_density_locator_contract.rb`: close check for a locator
  sheet into one full-text storyline. Presence, lineage, and not-empty /
  not-PRE-00-restatement only. Markdown PRE-00 uses a sibling sheet bound to
  `source_path`. Empty passage locators cannot close. Scripts never judge
  cinematic recoverability.
- `lib/idol_kinetic_slot_sheet_contract.rb`: presence of a change-point slot
  sheet for one Major. Sequence stays evidence; Core marks 1--2 nails; Key
  Screen inherits Core-bound slot camera. Neighbor axis/hold declarations
  and collected production-start pairs only; no uniqueness scorer.
- `idol_validate_kinetic_slot_sheet.rb`: fail-closed presence check for the
  kinetic slot sheet.
- `idol_stamp_source_connections.rb`: stdin/file pointer rows in, stamped
  envelope or `--model-facing` rows out. Does not write canonical creative
  filenames.
- `idol_validate_storyline_density_locators.rb`: fail-closed locator-sheet
  close check for a sheet or a markdown/YAML artifact with a sibling sheet.
- `lib/idol_direction_projection_contract.rb`: retired pre-01-v1.8/pre-02A-v2
  projection diagnostic retained for historical evidence and its generic
  structured-value hash helper. It cannot validate or reopen the active
  Core-Cut/Branch-Cut route.
- `idol_edit_delivery_qc.py`: hash-bind an exact 04 master, optional edit
  recipe, and selected audio, then measure program FPS/frame count/geometry and
  color tags; LUFS/LRA/true peak/sample-threshold/silence; and
  black/freeze/exact-duplicate-frame candidates. It never normalizes audio or
  issues a creative/Founder pass; playback review remains required.
- `idol_edit_readiness_worklist.rb`: edit-map readiness worklist generation.
- `idol-edit-desk`: local edit desk wrapper/entrypoint when a concrete 04 edit
  workflow needs the established desk surface.

### 05 Release, Publishing Record, And Social Evidence

Social posting entry point:

- Current X/TikTok/YouTube readiness, OAuth recovery, latest verified results,
  and exact apply playbook:
  `wiki/platform-credential-and-draft-upload-ops.md`.
- Common queue, Founder approval, execution routing, and closeout owner:
  `skills/idol-social-metadata-upload/SKILL.md`.
- Value-free first check: `python3 scripts/idol_platform_auth_status.py`.

- `idol_social_release_sync.py`: project one explicit run/content/package/
  publishing-plan/registry scope locally. The owning `05-package.yaml` is a
  required input. Approved states require a matching run-owned approval
  artifact bound to the canonical queue and exact approved asset bytes. The
  command performs no network action; it validates a staged projection before
  atomic replacement and records a recovery journal.
- `idol_social_public_closeout.py`: validate one run-owned Founder-supplied
  public URL closeout, derive the platform ID and embed URL, and atomically
  upsert the exact publication into the global post ledger, canonical Signal
  Deck member/track-or-CF visual registry, and existing title output registry.
  The input must bind an existing queue row, actual `published_at`, exact
  visible members, one MV track or CF, and final-used source/web visual paths
  and hashes. Dry-run is read-only. Apply writes a run-owned result and fixed
  T+24h/T+72h/T+7d due times; it never uploads, publishes, schedules, calls a
  metric API, syncs externally, chooses creative mappings, or deploys the site.
- `idol_social_release_session.py`: register one finished-content social batch
  once, then refresh it from stored run-owned pointers. It binds the exact
  queue action digest, package deliverables, plan, registry, assets, valid
  approvals, public facts, Signal Deck projection, and fixed T+24h/T+72h/T+7d
  windows into one schema-backed session plus one Founder decision packet.
  Unchanged state performs no rewrite or Founder wake. It authors no copy or
  approval and performs no upload, publish, provider request, or deploy.
- `idol_platform_draft_upload.py`: dry-run or execute one explicit run-owned
  platform draft batch. Dry-run requires the exact run-root `05-package.yaml`
  and emits its deliverable plus queue-asset linkage manifest without network.
  `--apply` requires an approval bound to that package path/SHA/deliverable
  digest, the canonical queue, approved actions/platforms/post ids/asset hashes,
  and distinct run-owned social-lane tracker/log paths. It copies approved bytes
  into content-addressed run-owned staging, atomically fsyncs a started intent,
  records `upload_in_progress`, verifies each request chunk against a preflight
  byte manifest, uploads only that snapshot, and blocks automatic
  retry while a started/unknown intent remains unresolved. Queue, tracker, and
  log retain approval/queue/package/output/linkage/snapshot/attempt provenance.
  Apply cannot skip the exact active title registry. The automatic draft path
  selects TikTok, YouTube, and YouTube Shorts from a mixed social queue;
  Instagram Reels stays manual and regular X public API publishing remains on
  the dedicated hash-bound X adapter. Explicit X/Instagram filters fail with
  that route. Apply performs a value-free credential preflight before creating
  an attempt, persists rotated TikTok/YouTube tokens atomically, finalizes
  deterministic pre-request failures as retryable `failed`, and reserves
  `unknown` for ambiguous request outcomes.
- `idol_prepare_api_upload_video.py`: local pre-approval API delivery step. It
  writes an `idol_api_upload_video.v1` receipt and performs no external action.
  Already-compliant 2K-or-higher CFR30 H.264/AAC bytes are copied without
  recompression; other sources receive a no-downscale Lanczos,
  CRF14/preset-slow, AAC320k local derivative. The draft and X upload adapters
  re-probe exact bytes before network access and refuse missing/stale receipts,
  sub-2K geometry, non-CFR30 video, or a hidden uploader transcode route.
- `idol_platform_auth_status.py`: value-free local status report for the X,
  TikTok, and YouTube credential stores. It reports only source paths, field
  names, and boolean readiness; it performs no network request and never
  prints a credential value. Ops layout, reauth commands, recent success
  evidence, and draft-upload playbook: `wiki/platform-credential-and-draft-upload-ops.md`.
- `idol_tiktok_oauth_reauth.py`: restore or rotate the TikTok user upload token
  through Desktop Login Kit PKCE. If the local client configuration is missing,
  it opens a localhost-only setup form, saves `tiktok.env` and
  `tiktok-token.json` with mode `0600`, requires `video.upload`, and never
  prints secret/token values. `--refresh-only` rotates an existing token
  without opening a browser; `--configure-client` reopens the localhost setup
  form when an existing app client binding must be replaced.
  Pre-review integrations must use the active Sandbox Credentials and a
  registered Sandbox target user, not App ID or Production Draft credentials.
  The Sandbox Desktop redirect must exactly match
  `http://127.0.0.1:8766/oauth2callback`; the callback server can restart
  immediately after an interrupted local authorization attempt.
- `idol_x_scheduled_thread.py`: execute one already approved, hash-bound CF X
  reply chain at its local due time through the regular X API. It verifies the
  exact queue, approval, post ids, attachments, claim guard, and 2K/CFR30
  `tweet_video` quality floor, consumes
  credentials internally without printing them, and never authors copy or
  infers approval.
- `scripts/lib/idol_platform_credentials.py`: shared value-free credential
  presence/readiness helper for X, TikTok, and YouTube runners. Public status
  contains paths, field names, and booleans only; secret values are never
  printed, logged, hashed, or returned.

### Public Reference Intake And Brief Cards

- `validate_reference_management_catalog.py`: network-free read-only validation
  for `catalog/references/reference-catalog.yaml` and the reusable still-image
  source catalog/manifests. It checks schemas, exact file pointers, SHA-256,
  source/usage ids, and local originals. It never classifies a reference,
  authors analysis, infers application or Founder PASS, downloads media, or
  grants generation attachment. The cross-run catalog points to the existing
  video hub, still-image hub, run-owned analyses, title indexes, and
  `reference-library/`; it is not another byte owner.
- `idol_reference_hub.py`: network-free, run-external reference lookup,
  preflight, local registration, deterministic catalog build, and hash/size
  verification. It normalizes platform ids/URLs, groups matching SHA-256 bytes,
  returns `reuse_existing` or a fail-closed hold before capture, and keeps new
  canonical owners under `source-materials/video-sources/{platform}/by-source/`.
  `ingest-local --replace-contact-sheets` can replace an already registered
  source's canonical sheet cadence only with a supplied hash-bound QC manifest;
  prior bytes remain untouched until a separately approved cleanup.
  It never downloads, byte-copies, moves, deletes, uploads, or grants approval;
  historical in-hub evidence may be hardlinked into its canonical source lane
  so one inode can back both provenance and active-owner paths.
- `idol_video_reference_segments.py`: network-free refresh helper for one
  already registered source. It is dry-run by default; `--apply` regenerates
  only the canonical duration-aware source sheets (one-second/5-second for
  short sources; three-second/15-second for longer ones) and replaces the active
  frame-index/contact-sheet set through the hub registry. It never downloads,
  copies raw video, makes per-cell crops, or selects creative references.
- `idol_video_reference_analysis_registry.py`: network-free first-read registry
  for source-owned reusable Layer A/B video analyses. `sync` scans canonical
  source manifests and updates `source-materials/video-sources/READ-FIRST.md`;
  a newly captured source remains `미분석`. `register` binds one human- or
  assigned-model-authored analysis to its canonical source, original video,
  one-second evidence, optional selected/sub-second inputs, declared coverage,
  and status. `complete` requires the exact analysis-input, whole-flow,
  timestamped scene-detail, source-transfer, and exclusion headings. `verify`
  checks paths, hashes, headings, declared status, and deterministic read-first
  output only; it never authors or judges creative analysis prose.
  `idol_harness_state_check.rb` runs this verification as a blocking
  local-source preflight for current MV. Historical CF-ALL preset and CF
  reference-bridge entrypoints are frozen compatibility only and must not open
  CF operations.
- `yt-dlp-bilibili.sh`: current-task-approved public/no-account Bilibili
  reference capture wrapper for one explicit URL. It accepts no arbitrary
  target path: hub preflight resolves the canonical source-id folder, reused
  evidence exits before network access, and a new capture requires
  `IDOL_REFERENCE_CAPTURE_APPROVED=1`, a non-empty task approval basis, and an
  exact matching approved URL before even metadata network access.
  Unknown-duration and over-270-second sources are prohibited with no override.
  Metadata persists a hash-bound info JSON, verified duration, raw view count
  when available, and the at-or-below-60-second shorts lane versus
  above-60-through-270-second music-reference lane in the canonical source
  manifest and catalog; candidate search
  still belongs to the owning research stage and ranks view count only after
  target/message relevance and diversity. Other heavy sources hold, separate
  audio is opt-in, and a successful capture receives duration-aware canonical
  contact sheets: one-second/5-second parts at or below 60 seconds, otherwise
  three-second/15-second parts, plus hub registration. The common engine used
  by all registered platform wrappers requires at least a 720-pixel short edge,
  defaults to a 1920-pixel long-edge ceiling, and verifies both dimensions from
  the captured bytes before registration.
- `yt-dlp-instagram-reference.sh`: registered public/no-account Instagram entry
  for one exact public post, Reel, or IGTV URL. Instagram is an allowed
  reference-capture route. It requires `IDOL_REFERENCE_CAPTURE_APPROVED=1`, a
  non-empty `IDOL_REFERENCE_CAPTURE_BASIS`, and an exact matching
  `IDOL_REFERENCE_APPROVED_URL` before metadata network access. It delegates to
  the same hub engine as Bilibili, rejects non-Instagram identity before
  network, uses no cookies or account state, enforces the same 270-second
  ceiling, writes the canonical `instagram/by-source/{shortcode}` owner,
  generates the same duration-aware sheets, registers the hash-bound evidence,
  and refreshes the read-first analysis index. Weekly short-form trend
  observation remains a separate no-bulk-download lane; this entry is for named
  single-URL reference capture.
- `yt-dlp-youtube-reference.sh`: registered public/no-account YouTube and
  YouTube Shorts entry for one exact URL. It is dormant by default and requires
  `IDOL_YOUTUBE_EXPLICIT_FOUNDER_INSTRUCTION=1` plus a non-empty
  `IDOL_YOUTUBE_FOUNDER_INSTRUCTION_BASIS` proving the Founder's separate
  current-task YouTube instruction before preflight. Use it only after the title,
  original-work/artist, scene/segment context, verification sources, and
  wrong-download rejection test are recorded in the owning Front Planning/01R
  contract and that direct instruction permits the route. It delegates to the
  same hub engine as Bilibili, rejects non-YouTube identity before network,
  uses no cookies or account state, enforces the same 270-second ceiling,
  writes the canonical `youtube/by-source/{video_id}` owner, generates the same
  duration-aware sheets, registers the hash-bound evidence, and refreshes the
  read-first analysis index.
  Do not use a bare `yt-dlp` command or add a wrapper that writes elsewhere:
  every future permitted platform wrapper must preflight, write only to the
  source-id hub owner, render this cadence, register hash-bound evidence, and
  preserve a single video byte copy. It can download a fresh `yt-dlp`
  binary into `/tmp` when missing, so do not run it without current task
  permission for that exact public source.
- `idol_bilibili_reference_fetch.py`: public/no-account Bilibili reference
  fetch helper only when the current task has approval under the repo's
  Bilibili policy. It is a legacy API fallback, not the canonical intake route
  or a default PRE-00 action; preflight and register any retained result through
  `idol_reference_hub.py` instead of creating another source truth.
- `idol_compile_brief_cards.rb`: inactive historical noncanonical brief-card
  projection. It reads retired prompt-index/cue-map shapes and cannot feed the
  active Front Planning→01→02A→02B route.

Known one-off helpers:

- `idol_low_source_first_rebuild_plan.py`
- `idol_worldcup_reference_audio_instrument_probe.py`:
  WORLD_CUP_PULSO-only reference-audio measurement probe. It reports
  measurement flags only; it must not be generalized as automatic
  instrument-function, arrangement, or prompt guidance.

Scripts that require explicit current-run paths:

- `idol_video_ffmpeg_revise_render.py`
- `idol_video_source_intake.py`
- `idol_video_sync_workbench.py`

Sequence Motion Analysis transport and validation:

- `validate_sequence_motion_analysis.rb`: strict by default; validates the
  provider-neutral `idol_sequence_motion_analysis.v1` evidence graph and
  requires the immutable promoted DDC v8 CDD review of the exact deterministic
  run-local bytes. `--pre-cdd-copy` is transport admission only for a returned
  DDC and grants no FP/01/03V authority.
- `idol_prepare_sequence_motion_analysis.rb`: atomic exact-copy-only producer
  for `RUN/research/sequence-motion-analysis/Sxx--MJxx/ATTEMPT.yaml`. It never
  authors creative truth, overwrites different bytes, follows output symlinks,
  or reports creative PASS; success is `copied_pending_cdd_review`.
- `idol_measure_sequence_motion_timeline.py`: optional diagnostic producer for
  `idol_sequence_motion_machine_measurement.v1` before model-authored SMA.
  Procedure and exact CLI flags live in `registry/research-and-evidence.md`.
  Same prepare/validate/CDD pipeline afterward. No new stage, no automatic SMA,
  no automatic invented production run path, and no creative PASS.

Do not use a built-in historical sample/default as an active source. Pass an
explicit current album/title/run path; if a script cannot do that, treat it as
inactive until its default is removed. `validate_video_prompt_index.rb` and
`idol_video_prompt_drive_sync.rb` are already classified as historical
evidence-only surfaces.

Before adding another run-specific script, first check whether an existing
validator or extractor can be extended safely. If a new one-off is still needed,
prefer storing it under the owning run folder unless it is intentionally being
designed as a reusable script.
