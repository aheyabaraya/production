# frozen_string_literal: true

require "pathname"
require "yaml"

module ActiveSequenceMotionFixture
  module_function

  def value_binding(fixture, pointer, value)
    {
      "source_json_pointer" => pointer,
      "source_value_sha256" => fixture.value_sha(value)
    }
  end

  def candidate_binding(fixture, front, major_index, candidate_index)
    candidate = front.dig("major_scene_catalog", major_index, "sequence_composition_candidate_set", "candidates", candidate_index)
    base = "/major_scene_catalog/#{major_index}/sequence_composition_candidate_set/candidates/#{candidate_index}"
    {
      "sequence_composition_id" => candidate.fetch("sequence_composition_id"),
      "sequence_composition_id_binding" => value_binding(fixture, "#{base}/sequence_composition_id", candidate.fetch("sequence_composition_id")),
      "typed_sequence_unit_ids_binding" => value_binding(fixture, "#{base}/typed_sequence_unit_ids", candidate.fetch("typed_sequence_unit_ids")),
      "flow_reading_binding" => value_binding(fixture, "#{base}/flow_reading", candidate.fetch("flow_reading")),
      "mismatch_and_risk_binding" => value_binding(fixture, "#{base}/mismatch_and_risk", candidate.fetch("mismatch_and_risk"))
    }
  end

  def document(fixture, front, dispatch_path:, audio_motion_map_path:, attempt_key:)
    major_index = 0
    major = front.fetch("major_scene_catalog").fetch(major_index)
    candidate_set = major.fetch("sequence_composition_candidate_set")
    candidates = candidate_set.fetch("candidates")
    major_base = "/major_scene_catalog/#{major_index}"
    candidate_bindings = candidates.each_index.map do |candidate_index|
      candidate_binding(fixture, front, major_index, candidate_index)
    end
    stable_snapshot = {
      "major_scene_id" => major.fetch("major_scene_id"),
      "section_id" => major.fetch("section_id"),
      "semantic_event_or_relation_job" => major.fetch("semantic_event_or_relation_job"),
      "candidate_set_id" => candidate_set.fetch("candidate_set_id"),
      "candidates" => candidates.map do |candidate|
        candidate.slice("sequence_composition_id", "typed_sequence_unit_ids", "flow_reading", "mismatch_and_risk")
      end
    }
    source_front_planning = {
      "path" => fixture.relative(fixture.front_path),
      "schema_version" => "front-planning-readiness.v17",
      "whole_file_sha256_absent_reason" => "final_front_planning_candidate_binds_this_analysis_so_a_whole_file_hash_here_would_create_a_self_reference_cycle",
      "candidate_snapshot_algorithm" => "sha256_of_canonical_json_with_recursively_sorted_object_keys",
      "candidate_snapshot_scope" => "major_identity_section_identity_semantic_job_candidate_set_id_and_each_candidates_composition_id_typed_sequence_unit_ids_flow_reading_mismatch_and_risk",
      "candidate_snapshot_sha256" => fixture.value_sha(stable_snapshot),
      "major_scene_id_binding" => value_binding(fixture, "#{major_base}/major_scene_id", major.fetch("major_scene_id")),
      "section_id_binding" => value_binding(fixture, "#{major_base}/section_id", major.fetch("section_id")),
      "semantic_event_or_relation_job_binding" => value_binding(fixture, "#{major_base}/semantic_event_or_relation_job", major.fetch("semantic_event_or_relation_job")),
      "candidate_set_id_binding" => value_binding(fixture, "#{major_base}/sequence_composition_candidate_set/candidate_set_id", candidate_set.fetch("candidate_set_id")),
      "candidate_bindings" => candidate_bindings
    }
    audio_map = YAML.safe_load(Pathname.new(audio_motion_map_path).read, aliases: true)
    audio_cue = audio_map.fetch("section_rhythm_map").first
    audio_binding = {
      "cue_id" => audio_cue.fetch("section_id"),
      "source_json_pointer" => "/section_rhythm_map/0",
      "source_value_sha256" => fixture.value_sha(audio_cue)
    }
    front_units = front.dig("reference_connection_research", "reference_units")
    analysis_scope = {
      "scope_kind" => "one_material_major_complete_sequence_composition_candidate_group",
      "candidate_group_policy" => "one_worker_reviews_all_candidates_for_the_same_major",
      "candidate_set_id" => candidate_set.fetch("candidate_set_id"),
      "candidate_ids" => candidates.map { |candidate| candidate.fetch("sequence_composition_id") },
      "active_storyline_passage_binding" => value_binding(
        fixture,
        "/storyline_lineage/active_version/full_storyline_text",
        front.dig("storyline_lineage", "active_version", "full_storyline_text")
      ),
      "cohesion_basis" => "Every candidate performs the same MJ01 action-to-registered-state screen job and must be compared by one worker."
    }
    candidate_analyses = candidates.each_with_index.map do |candidate, candidate_index|
      unit_bindings = candidate.fetch("typed_sequence_unit_ids").map do |unit_id|
        reference_index = front_units.index { |row| row.dig("sequence_unit", "sequence_unit_id") == unit_id }
        unit = front_units.fetch(reference_index).fetch("sequence_unit")
        unit_pointer = "/reference_connection_research/reference_units/#{reference_index}/sequence_unit"
        {
          "sequence_unit_id" => unit_id,
          "source_json_pointer" => unit_pointer,
          "source_value_sha256" => fixture.value_sha(unit),
          "flow_reading_json_pointer" => "#{unit_pointer}/flow_reading",
          "flow_reading_value_sha256" => fixture.value_sha(unit.fetch("flow_reading"))
        }
      end
      selected = candidate_index.zero?
      {
        "sequence_composition_id" => candidate.fetch("sequence_composition_id"),
        "candidate_source_binding" => candidate_bindings.fetch(candidate_index),
        "sequence_unit_bindings" => unit_bindings,
        "audio_motion_cue_bindings" => [audio_binding],
        "continuous_motion_source_review" => {
          "inspection_status" => "source_video_unavailable",
          "source_video" => nil,
          "unavailable_reason" => "The active fixture binds exact one-second source frames but no continuous source-video bytes.",
          "observed_interframe_events" => []
        },
        "inferred_camera_opportunities" => [{
          "opportunity_id" => "INF_MJ01_0#{candidate_index + 1}",
          "evidence_status" => "inferred",
          "inference_basis" => ["sequence_frame_observations", "contextual_flow_reading", "major_screen_job", "audio_motion_cue"],
          "observed_event_ids" => [],
          "perceptual_functions" => selected ? ["directionality", "continuity", "reveal"] : ["parallax", "scale", "continuity"],
          "geometry_support" => selected ? "The rear-facing contact axis supports restrained lateral energy while the scene intentionally withholds facial readability." : "The alternate spatial proof supports a bounded reframe around the registered guide.",
          "joint_motion_reading" => {
            "body_action_energy" => selected ? "The hand contact and body settle create directional energy without requiring a face turn." : "The body remains anchored while the guide change supplies the active energy.",
            "camera_translation" => selected ? "A restrained lateral track is supportable as an inference, not final camera truth." : "A short lateral or forward relation may clarify scale if later pixels support it.",
            "camera_rotation" => "No exact rotational family is claimed without admitted continuous-video evidence.",
            "lens_change" => "A lens pulse is not evidenced by the exact-five still sequence and remains unclaimed.",
            "subject_gaze_and_head_direction" => selected ? "The head stays rear-facing and gaze remains intentionally unreadable; no frontal turn is required." : "A partial side relation may be tested without requiring frontal gaze.",
            "angle_and_composition_reframing" => selected ? "Keep the rear-world axis and reframe around the open guide-side negative space." : "Preserve the guide and subject planes while testing a functionally distinct composition.",
            "depth_occlusion_reveal" => "The hand-to-guide crossing can create occlusion and reveal across the foreground, subject, and guide planes.",
            "start_and_landing" => "The first offset and fifth registered state are advisory boundaries; 03V owns temporal intensity and landing.",
            "continuous_camera_energy_review" => selected ? "continuous_camera_energy_supported_contextually" : "intentional_locked_or_hold_is_stronger"
          },
          "literal_transfer" => {
            "supported" => false,
            "source_motion_family" => nil,
            "observed_event_ids" => [],
            "perceptual_functions" => [],
            "camera_translation_fact" => nil,
            "camera_rotation_fact" => nil,
            "rotation_degrees" => nil,
            "full_orbit_completed" => nil,
            "lens_change_fact" => nil,
            "hold_reason" => "No continuous source-video bytes were admitted, so no exact source motion family can be claimed."
          },
          "function_equivalent_transfer" => {
            "supported" => true,
            "alternative_motion_families" => selected ? ["locked_hold", "lateral_track"] : ["partial_arc", "environment_or_light_led_route"],
            "equivalence_reason" => selected ? "A hold or restrained lateral relation preserves direction and reveal while respecting the intentionally unreadable scene function." : "A partial arc or environment-led response preserves scale and spatial consequence without becoming a default orbit."
          },
          "confidence" => selected ? "high" : "medium",
          "uncertainty" => "Final temporal geometry, speed, envelope, stop, and landing remain unowned until passed pixels are reviewed in 03V."
        }],
        "motion_support_finding" => {
          "authority" => "advisory_until_independently_adopted_partial_or_rejected_by_01_cdd_review",
          "candidate_readout" => selected ? "Best preserves the action axis while flagging identity and crop risk for 01 still coverage." : "Useful spatial alternative but weaker on member causality.",
          "depth" => support_finding("partial", "The five frames expose foreground mark, subject plane, and guide plane.", "adopt", "01 must author an actual still depth design that keeps all three planes readable.", "02A should add a deeper or shallower alternate only if it contributes new state proof."),
          "alternate_view" => support_finding("partial", "The candidate group contains a second Sequence Unit view for comparison.", "partial", "01 must choose the Official Core anchor view independently.", "02A should author at least one functionally distinct alternate view where it adds information."),
          "reveal_space" => support_finding("partial", "The right-side guide provides bounded reveal space.", "adopt", "01 must reserve visible reveal space in the Official Core crop.", "02A should expand the reveal only through an authored Branch state."),
          "rear_world_direction" => support_finding("partial", "The lateral contact axis preserves rear-world direction without requiring a face turn.", "partial", "01 must independently decide the still direction and rear-world relation.", "02A should test an alternate world-facing relation without reversing continuity."),
          "identity_visibility" => {
            "intent" => selected ? "intentionally_unreadable" : "optional_partial",
            "visible_identity_cues" => selected ? ["styling", "clothing", "body_silhouette", "member_specific_detail"] : ["hair", "styling", "clothing", "body_silhouette"],
            "fidelity_when_visible" => "exact_current_title_identity_nonfrontal_allowed",
            "visible_cue_fidelity" => "all_listed_visible_cues_preserve_exact_current_title_fidelity",
            "scene_function_reason" => selected ? "The rear-facing action withholds facial readability as part of the screen job; silhouette, body action, and styling still carry the member." : "The alternate may reveal part of the member without requiring a frontal face or gaze."
          },
          "identity" => support_finding("supported", "Current-title identity is preserved through silhouette, body action, and styling; facial readability is not required for this scene.", "adopt", "01 must preserve exact current-title identity wherever visible while honoring the selected visibility intent.", "02A may author rear, silhouette, occluded, wide, rotated, or nonfrontal views when they serve the scene and keep visible identity exact."),
          "crop" => support_finding("partial", "The marker route needs open right-side negative space.", "adopt", "01 must author crop and negative space around the route.", "02A should add a crop alternative only when it preserves the required route."),
          "occlusion" => support_finding("partial", "The hand can cross the guide and hide the registered state.", "partial", "01 must author an Official Core state with the registered result visible.", "02A should separate contact and revealed-result views if one frame cannot show both."),
          "continuity" => support_finding("supported", "The final registered state has a clean carry into the next Core.", "adopt", "01 must record the actual still continuity state.", "02A Branches must preserve that state unless they explicitly advance it."),
          "start_landing" => support_finding("partial", "The first offset and fifth registered frames provide advisory start/landing potential only.", "partial", "01 may use either state as still truth but must not script temporal camera.", "02A may expand start or landed states as still Branches; 03V owns final temporal landing.")
        },
        "mismatch_and_risk" => candidate.fetch("mismatch_and_risk")
      }
    end
    comparative = {
      "recommended_sequence_composition_id" => candidates.first.fetch("sequence_composition_id"),
      "compared_candidate_ids" => candidates.map { |candidate| candidate.fetch("sequence_composition_id") },
      "recommendation_reason" => "The first candidate preserves member causality and the retained system consequence while leaving exact temporal intensity to 03V.",
      "adoption_state" => "advisory_only_until_recorded_in_01_cdd_review"
    }
    dispatch_document = YAML.safe_load(Pathname.new(dispatch_path).read, aliases: true)
    dispatch_binding = {
      "path" => fixture.relative(dispatch_path),
      "schema_version" => "idol-department-dispatch.v8",
      "dispatch_id" => dispatch_document.fetch("dispatch_id"),
      "attempt_id" => dispatch_document.dig("lineage", "attempt_id"),
      "whole_file_sha256_absent_reason" => "the_final_dispatch_review_binds_this_analysis_sha256_so_only_stable_prework_launch_and_goal_fields_are_value_bound_here_to_avoid_a_hash_cycle",
      "task_binding" => value_binding(fixture, "/launch/task", dispatch_document.dig("launch", "task")),
      "exact_scope_binding" => value_binding(fixture, "/launch/task/exact_scope", dispatch_document.dig("launch", "task", "exact_scope")),
      "goal_contract_binding" => value_binding(fixture, "/launch/goal_contract", dispatch_document.dig("launch", "goal_contract")),
      "source_set_binding" => value_binding(fixture, "/launch/sources", dispatch_document.dig("launch", "sources")),
      "bounded_output_binding" => value_binding(fixture, "/launch/bounded_output", dispatch_document.dig("launch", "bounded_output")),
      "recipient_binding" => value_binding(fixture, "/launch/recipient", dispatch_document.dig("launch", "recipient")),
      "selected_profile_binding" => value_binding(fixture, "/launch/compiled_launch_prompt/selected_profile", dispatch_document.dig("launch", "compiled_launch_prompt", "selected_profile")),
      "rendered_prompt_binding" => value_binding(fixture, "/launch/compiled_launch_prompt/rendered_prompt", dispatch_document.dig("launch", "compiled_launch_prompt", "rendered_prompt")),
      "routing_identity_binding" => value_binding(fixture, "/routing_identity", dispatch_document.fetch("routing_identity"))
    }
    goal_binding = {
      "path" => fixture.relative(dispatch_path),
      "provider_binding" => value_binding(fixture, "/runtime_return/runtime_goal/provider", dispatch_document.dig("runtime_return", "runtime_goal", "provider")),
      "native_goal_id_binding" => value_binding(fixture, "/runtime_return/runtime_goal/native_goal_id", dispatch_document.dig("runtime_return", "runtime_goal", "native_goal_id")),
      "opened_at_binding" => value_binding(fixture, "/runtime_return/runtime_goal/opened_at", dispatch_document.dig("runtime_return", "runtime_goal", "opened_at")),
      "goal_text_sha256_binding" => value_binding(fixture, "/runtime_return/runtime_goal/goal_text_sha256", dispatch_document.dig("runtime_return", "runtime_goal", "goal_text_sha256"))
    }
    source_audio_motion_map = {
      "path" => fixture.relative(audio_motion_map_path),
      "sha256" => fixture.file_sha(audio_motion_map_path),
      "schema_version" => "idol_audio_motion_director_map.v1"
    }
    dispatch = {
      "dispatch_contract" => dispatch_binding,
      "native_goal" => goal_binding,
      "studio_role" => "department_worker",
      "profile_id" => "reference_research_generalist",
      "logical_profile_alias" => "worker_high",
      "return_recipient_role" => "creative_development_director",
      "scope_key" => "sequence_motion:ACTIVE_TITLE_TEST:S01:MJ01",
      "attempt_key" => attempt_key,
      "attempt_number" => dispatch_document.dig("lineage", "attempt_number"),
      "previous_attempt_id" => dispatch_document.dig("lineage", "previous_attempt_id"),
      "single_writer_scope" => "one_material_major_complete_candidate_group",
      "overlap_policy" => "hold_when_an_active_peer_has_the_same_scope_key",
      "review_backpressure" => "capacity_available",
      "next_launch_rule" => "launch_only_for_a_named_unowned_gap_when_cdd_review_capacity_is_available",
      "authorship_owner" => "assigned_model",
      "input_digest_sha256" => "0" * 64,
      "result_digest_scope" => "candidate_analyses_and_comparative_recommendation",
      "result_sha256" => fixture.value_sha({"candidate_analyses" => candidate_analyses, "comparative_recommendation" => comparative})
    }
    dispatch["input_digest_sha256"] = fixture.value_sha(
      {
        "candidate_snapshot_sha256" => source_front_planning.fetch("candidate_snapshot_sha256"),
        "source_audio_motion_map_sha256" => source_audio_motion_map.fetch("sha256"),
        "analysis_scope" => analysis_scope,
        "dispatch_contract_stable_binding_sha256" => fixture.value_sha(dispatch_binding),
        "native_goal_stable_binding_sha256" => fixture.value_sha(goal_binding)
      }
    )
    {
      "schema_version" => "idol_sequence_motion_analysis.v1",
      "analysis_id" => "SMA_ACTIVE_TITLE_TEST_S01_MJ01",
      "content_id" => "ACTIVE_TITLE_TEST",
      "run_root" => fixture.relative(fixture.run_dir),
      "status" => "ready_for_cdd_review",
      "section_id" => "S01",
      "major_scene_id" => "MJ01",
      "source_front_planning" => source_front_planning,
      "source_audio_motion_map" => source_audio_motion_map,
      "analysis_scope" => analysis_scope,
      "candidate_analyses" => candidate_analyses,
      "comparative_recommendation" => comparative,
      "dispatch_and_authorship" => dispatch,
      "authority_boundary" => authority_boundary,
      "source_sequence_policy" => source_sequence_policy
    }
  end

  def support_finding(state, evidence, disposition, core_requirement, branch_requirement)
    {
      "support_state" => state,
      "evidence" => evidence,
      "recommended_01_disposition" => disposition,
      "official_core_still_requirement" => core_requirement,
      "branch_expansion_requirement" => branch_requirement
    }
  end

  def authority_boundary
    {
      "artifact_role" => "front_planning_reference_connection_analysis_not_a_canonical_stage",
      "stage_creation" => "forbidden",
      "recommendation_authority" => "advisory_until_independently_adopted_by_01_cdd_review",
      "front_planning_authority" => "only_selected_candidate_may_bind_one_independently_cdd_reviewed_analysis_row",
      "official_still_truth_owner" => "01_authors_actual_still_screen_truth_without_scripted_temporal_camera",
      "branch_still_truth_owner" => "02A_authors_still_branch_coverage_only",
      "final_temporal_camera_owner" => "03V_after_passed_production_cut_pixel_review",
      "script_role" => "validate_and_exact_copy_never_author_creative_truth"
    }
  end

  def source_sequence_policy
    {
      "active_unit_shape" => "exactly_five_ordered_consecutive_samples",
      "active_cadence_seconds" => 1,
      "legacy_three_second_units" => "pinned_read_only_evidence_only",
      "legacy_promotion" => "forbidden_for_new_authoring_or_automatic_upgrade"
    }
  end
end
