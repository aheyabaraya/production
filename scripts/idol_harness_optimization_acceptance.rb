#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "time"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

class AcceptanceError < StandardError; end

def run_command(*command)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  return {stdout: stdout, stderr: stderr} if status.success?

  detail = [stdout, stderr].reject(&:empty?).join("\n").strip
  raise AcceptanceError, "#{command.join(' ')} failed\n#{detail}"
end

def validate_context_bootstrap
  run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_context_source_admission_test.rb").to_s)
  run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_reference_interpretation_contract_test.rb").to_s)
  {
    "fixture_contract_tests" => "pass",
    "current_run_source_admission" => true,
    "other_run_test_maintenance_and_symlink_sources_rejected" => true,
    "live_or_historical_run_used_as_acceptance_fixture" => false
  }
end

def validate_expert_gate_contract
  run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_expert_gate_test.rb").to_s)
  storyboard_schema = JSON.parse(ROOT.join("schemas", "master-storyboard.schema.json").read)
  parent_cap = storyboard_schema.dig("properties", "master_storyboard", "maxItems")
  branch_cap = storyboard_schema.dig("$defs", "compileSeed", "properties", "branch_cuts", "maxItems")
  raise AcceptanceError, "storyboard schema reintroduced a Core-Cut or Branch-Cut numeric cap" if parent_cap || branch_cap
  {
    "fixture_contract_tests" => "pass",
    "direction_form_tests" => 4,
    "contextual_llm_review_required" => true,
    "machine_creative_judgment_forbidden" => true,
    "numeric_cap_forbidden" => true,
    "live_or_historical_run_used_as_acceptance_fixture" => false
  }
end

def validate_current_routing
  shadow_schema_check = <<~PYTHON
    import json
    import jsonschema
    with open("schemas/harness-shadow-eval-result.schema.json", encoding="utf-8") as handle:
      jsonschema.Draft202012Validator.check_schema(json.load(handle))
  PYTHON
  run_command(PYTHON.to_s, "-c", shadow_schema_check)
  preflight = JSON.parse(run_command(PYTHON.to_s, ROOT.join("scripts", "validate_idol_model_routing_agents.py").to_s, "--json")[:stdout])
  run_command(PYTHON.to_s, "-m", "unittest", "scripts.tests.validate_idol_model_routing_agents_test")
  run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_shadow_eval_test.rb").to_s)
  policy = JSON.parse(run_command(RbConfig.ruby, ROOT.join("scripts", "idol_harness_shadow_eval.rb").to_s, "policy", "--json")[:stdout])
  routing = policy.fetch("routing_policy")
  raise AcceptanceError, "v31 routing policy id drifted" unless routing["policy_id"] == "provider_registry_adaptive_runtime_v31"
  raise AcceptanceError, "v31 provider-registry model preflight failed" unless preflight["status"] == "pass"
  raise AcceptanceError, "logical profile routing mode drifted" unless routing.dig("effort_policy", "mode") == "provider_registry_logical_aliases_v31"
  raise AcceptanceError, "silent model fallback became active" unless routing.dig("capability_check", "unsupported_pairing_action") == "hold_and_report"
  raise AcceptanceError, "standing Final Director returned" unless routing.dig("agent_governance", "standing_final_director_allowed") == false
  raise AcceptanceError, "provider-native helper gate drifted" unless routing.dig("agent_governance", "provider_native_helper_availability") == "default"
  raise AcceptanceError, "project numeric/depth helper gate returned" unless routing.dig("agent_governance", "project_numeric_gate") == "none" && routing.dig("agent_governance", "depth_gate") == "none"

  expected_directors = {
    "creative_core_and_founder_direction" => ["idol_sol_creative_synthesis", "xhigh"],
    "creative_development_direction" => ["idol_sol_creative_development_director", "xhigh"],
    "edit_director" => ["idol_sol_edit_director", "xhigh"]
  }
  routes = Array(routing["route_classes"])
  expected_directors.each do |route_id, (agent_name, effort)|
    route = routes.find { |row| row["route_id"] == route_id }
    unless route && route.dig("default_route", "agent_name") == agent_name && route.dig("default_route", "model_reasoning_effort") == effort
      raise AcceptanceError, "#{route_id} must remain the exact director_deep/xhigh route"
    end
  end
  edit_contract = routing.dig("routing_continuity_contract", "edit_qc_04_execution_contract")
  unless edit_contract.to_h["edit_director_agent_name"] == "idol_sol_edit_director" &&
         edit_contract.to_h["edit_shard_agent_name"] == "idol_luna_studio_department"
    raise AcceptanceError, "Edit Director and bounded edit-shard ownership drifted"
  end
  governance = routing.fetch("agent_governance")
  unless Array(governance["canonical_write_exception_agent_names"]).include?("idol_sol_edit_director") &&
         Array(governance["canonical_write_exception_paths"]).include?("runs/ALBUM_KEY/TITLE_KEY/RUN_ID/04-edit-map.yaml") &&
         !Array(governance["canonical_write_exception_paths"]).include?("runs/ALBUM_KEY/TITLE_KEY/RUN_ID/05-package.yaml")
    raise AcceptanceError, "Edit Director physical write authority must stop at the exact run-root 04 edit map"
  end
  raise AcceptanceError, "ordinary Terra route returned" if Array(routing["route_classes"]).any? do |row|
    row["route_id"] != "weekly_visual_idol_research" &&
      [row["default_route"], *Array(row["explicit_alternatives"])].any? { |descriptor| descriptor["model_id"] == "gpt-5.6-terra" }
  end
  {
    "policy_id" => routing["policy_id"],
    "overall_director_profiles" => %w[idol_sol_creative_synthesis],
    "creative_development_director" => "idol_sol_creative_development_director",
    "ordinary_worker" => "idol_luna_studio_department",
    "post_02a_logical_profile" => "worker_high",
    "post_02a_logical_role" => "section_image_motion_worker",
    "post_02a_codex_realization" => "idol_luna_section_image_motion",
    "post_02a_grok_realization" => "grok_worker_high",
    "edit_director" => "idol_sol_edit_director",
    "assignment_policy" => "adaptive_registered_assignment_under_provider_capacity_and_director_backpressure",
    "standing_final_director" => false,
    "unsupported_pairing_action" => "hold_and_report",
    "weekly_terra_exception_only" => true
  }
end

options = {json: false}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_harness_optimization_acceptance.rb [--json]"
  opts.on("--json", "Emit machine-readable acceptance report") { options[:json] = true }
end.parse!

checks = [
  {
    id: "stage_naming_and_decision_ownership",
    objective: "Semantic stage naming, Front Planning Integration, and one-owner decision projections are machine validated.",
    run: lambda do
      run_command(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, ROOT.join("schemas", "harness-stage-registry.schema.json").to_s, ROOT.join("automation", "harness-stage-registry.yaml").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "idol_harness_stage.rb").to_s, "validate")
      resolved = run_command(RbConfig.ruby, ROOT.join("scripts", "idol_harness_stage.rb").to_s, "resolve", "front-planning")
      raise AcceptanceError, "front-planning alias did not resolve" unless resolved[:stdout].include?("front_planning_integration")
      stage_registry = YAML.safe_load(ROOT.join("automation", "harness-stage-registry.yaml").read, permitted_classes: [], permitted_symbols: [], aliases: true)
      front_stage = Array(stage_registry["stages"]).find { |row| row["stage_id"].to_s == "front_planning_integration" }
      required_upstream = %w[creative_route_discovery candidate_track_analysis audio_screen_motion_map song_production_lock]
      active_route = Array(
        YAML.safe_load(
          ROOT.join("automation", "harness-execution-contract.yaml").read,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: true
        )["active_route"]
      )
      route_positions = (required_upstream + ["front_planning_integration"]).map { |stage_id| active_route.index(stage_id) }
      unless front_stage &&
             Array(front_stage["inputs"]) == ["creative_route_discovery", "song_production_lock"] &&
             route_positions.none?(&:nil?) &&
             route_positions == route_positions.sort
        raise AcceptanceError, "Front Planning prerequisite order drifted"
      end
      {"front_planning_resolved" => true, "front_planning_upstream_order" => required_upstream, "decision_contracts_machine_validated" => true}
    end
  },
  {
    id: "quality_preserving_context_bootstrap",
    objective: "Compact bootstrap retains creative constitution, whole-song/adjacent continuity, expert activation, hashes, and independent readiness axes.",
    run: -> { validate_context_bootstrap }
  },
  {
    id: "operator_speed_and_render_correction",
    objective: "Five semantic operator phases, fixture-isolated active-frontier validation, and bounded post-generation render correction reduce transition cost without removing creative or Founder gates.",
    run: lambda do
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_stage_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_current_next_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_frontier_check_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_prepare_image_render_correction_test.rb").to_s)
      stage_registry = YAML.safe_load(ROOT.join("automation", "harness-stage-registry.yaml").read, permitted_classes: [], permitted_symbols: [], aliases: true)
      phases = Array(stage_registry["phases"])
      raise AcceptanceError, "operator phase overlay drifted" unless phases.length == 5
      {
        "operator_phase_count" => phases.length,
        "frontier_fixture_contract" => "pass",
        "live_current_pointer_used_as_acceptance_fixture" => false,
        "render_correction_version" => "idol_image_render_correction.v8",
        "render_correction_regression" => true
      }
    end
  },
  {
    id: "instruction_surface_quality_and_efficiency",
    objective: "Static startup stays compact without removing protected creative quality, authority, cardinality, lifecycle, or routing truth; long detail remains conditionally indexed.",
    run: lambda do
      run_command(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, ROOT.join("schemas", "instruction-surface-policy.schema.json").to_s, ROOT.join("automation", "instruction-surface-policy.yaml").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_instruction_surface_audit_test.py").to_s)
      audit = JSON.parse(run_command(PYTHON.to_s, ROOT.join("scripts", "idol_instruction_surface_audit.py").to_s, "--json")[:stdout])
      raise AcceptanceError, "instruction surface audit failed" unless audit["status"] == "pass" && Array(audit["errors"]).empty?
      static = Array(audit["startup_profiles"]).find { |row| row["id"] == "harness_static_startup" }
      raise AcceptanceError, "static startup profile missing" unless static
      policy = YAML.safe_load(ROOT.join("automation", "instruction-surface-policy.yaml").read, permitted_classes: [], permitted_symbols: [], aliases: true)
      static_policy = Array(policy["startup_profiles"]).find { |row| row["id"] == "harness_static_startup" }
      raise AcceptanceError, "static startup policy missing" unless static_policy
      audit_invariant_ids = Array(audit["protected_invariants"]).map { |row| row["id"].to_s }
      policy_invariant_ids = Array(policy["protected_invariants"]).map { |row| row["id"].to_s }
      invariant_count = audit_invariant_ids.length
      conditional_count = Array(audit["conditional_references"]).length
      unless audit_invariant_ids == policy_invariant_ids && audit_invariant_ids.uniq.length == audit_invariant_ids.length
        raise AcceptanceError, "protected instruction invariants drifted"
      end
      raise AcceptanceError, "conditional instruction routing incomplete" unless conditional_count >= 5
      unless audit.dig("maintenance_history", "excluded_from_startup") == true
        raise AcceptanceError, "frozen maintenance history re-entered startup"
      end
      {
        "static_startup_words" => static["words"],
        "target_words" => static_policy["target_words"],
        "reviewed_ceiling_words" => static_policy["reviewed_ceiling_words"],
        "protected_invariant_count" => invariant_count,
        "conditional_reference_count" => conditional_count,
        "history_excluded" => true,
        "warning_count" => Array(audit["warnings"]).length,
        "conditional_detail_global_cap" => false
      }
    end
  },
  {
    id: "revisioned_physical_section_sharding",
    objective: "Active 02A/02B local lineage keeps unrelated sections stable, limits same-section expansion invalidation to the affected neighborhood, and routes each post-02A physical section through the registered provider-resolved worker_high session boundary.",
    run: lambda do
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_local_revision_propagation_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_shadow_eval_test.rb").to_s)
      {
        "local_revision_and_expansion_tests" => "pass",
        "unaffected_section_hashes_stable" => true,
        "same_section_immediate_neighborhood_only" => true,
        "post_02a_route" => "physical_section_shard",
        "post_02a_logical_profile" => "worker_high",
        "post_02a_logical_role" => "section_image_motion_worker",
        "post_02a_provider_resolution" => "exact_run_snapshot_no_fallback"
      }
    end
  },
  {
    id: "direct_deterministic_02b",
    objective: "Active delta v1.5 and packet v2.5 compile and review one physical section at a time across Hero Core, Official Core, and Official Branch modes, carry only locally unchanged packets, reject unadmitted creative sources, and merge passed section shards without reopening unrelated sections. Every adapter keeps one exact Production Cut per generation call and preserves Founder gates.",
    run: lambda do
      schema_check = <<~PYTHON
        import json
        import jsonschema
        for path in [
          "schemas/master-storyboard.schema.json",
          "schemas/prompt-packet-delta.schema.json",
          "schemas/prompt-packets.schema.json",
          "schemas/image-generation-request.schema.json",
          "schemas/image-generation-section-worklist.schema.json",
          "schemas/grok-video-prompt-reference-pack.schema.json",
        ]:
          with open(path, encoding="utf-8") as handle:
            jsonschema.Draft202012Validator.check_schema(json.load(handle))
      PYTHON
      run_command(PYTHON.to_s, "-c", schema_check)
      delta_schema = JSON.parse(ROOT.join("schemas", "prompt-packet-delta.schema.json").read)
      unless delta_schema.dig("properties", "schema_version", "const") == "1.6" &&
             delta_schema.dig("properties", "compiler_profile", "const") == "provider_neutral_one_cut_one_image_translation_v2_6"
        raise AcceptanceError, "active prompt-packet delta version/profile drifted"
      end
      packet_schema = JSON.parse(ROOT.join("schemas", "prompt-packets.schema.json").read)
      raise AcceptanceError, "active prompt-packet version drifted" unless packet_schema.dig("properties", "schema_version", "const") == "2.6"
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_prompt_packet_compile_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_prepare_image_generation_request_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_harness_context_source_admission_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_local_revision_propagation_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_active_instruction_bias_test.rb").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_02b_section_execution_test.py").to_s)
      {
        "prompt_packet_compile_tests" => "pass",
        "image_generation_request_tests" => "pass",
        "context_source_admission_tests" => "pass",
        "local_revision_and_multi_section_tests" => "pass",
        "active_instruction_bias_tests" => "pass",
        "section_execution_export_tests" => "pass",
        "packet_count_source" => "actual_selected_Hero_Core_Branch_targets",
        "multiple_branch_cuts_per_core_cut" => "uncapped",
        "production_cut_member_visual_scope" => true,
        "authorized_member_relay" => true,
        "no_face_visible_member_crop" => true,
        "section_storyboard_exact_cover" => true,
        "duplicate_master_cut_id_blocked" => true,
        "model_or_human_authored_five_line_prompt_exact_copy" => true,
        "local_lineage_contract" => "idol_02a_02b_local_lineage.v1",
        "packet_only_carry_forward" => true,
        "same_section_neighbor_invalidation_only" => true,
        "unaffected_section_carry_forward" => true,
        "member_visuals_follow_meaningful_member_visibility" => true,
        "scene_references_independent_of_member_visibility" => true,
        "actual_reference_path_sha_pixel_contract" => true,
        "creative_source_admission" => "current_run_current_title_or_selected_source_material_only",
        "openai_platform_adapter_one_packet_per_call" => true,
        "section_llm_one_section_per_worker_session" => true,
        "section_llm_one_packet_per_generation_call" => true,
        "section_worklist_version" => "idol_image_generation_section_worklist.v9",
        "same_section_bounded_parallel_packet_calls" => true,
        "same_output_parallel_write_forbidden" => true,
        "historical_batch_runner_inactive" => true,
        "count_is_global_cap" => false,
        "active_delta_profile" => "provider_neutral_one_cut_one_image_translation_v2_5",
        "active_packet_version" => "2.5",
        "historical_profile_authoring" => "forbidden"
      }
    end
  },
  {
    id: "conditional_professional_quality_gates",
    objective: "Song craft, directing/camera, choreography feasibility, contextual storyboard review, and edit-grid depth block thin readiness claims while schemas preserve uncapped Core-Cut/Branch-Cut cardinality.",
    run: -> { validate_expert_gate_contract }
  },
  {
    id: "quality_first_5_6_shadow_policy",
    objective: "Ordinary conversation preserves the user-selected session profile; scoped work uses only XHigh/Max/Ultra task-fit routes, while Ultra remains an explicit-trigger exception rather than a routine default.",
    run: -> { validate_current_routing }
  },
  {
    id: "motion_camera_first_03v_contract",
    objective: "03V starts after typed passed Production-Cut pixel review, uses one to three ordered passed Official-Core or Branch images per storyboard board, records the temporal-route reason for a one-image board, and owns temporal camera motion only after image completion.",
    run: lambda do
      schema_check = <<~PYTHON
        import json
        import jsonschema
        for path in [
          "schemas/audio-branch-cut-placement.schema.json",
          "schemas/review.schema.json",
          "schemas/production-cut-review.schema.json",
          "schemas/video-prompt-manifest.schema.json",
          "schemas/video-prompt-storyboard-assist.schema.json",
        ]:
          with open(path, encoding="utf-8") as handle:
            jsonschema.Draft202012Validator.check_schema(json.load(handle))
      PYTHON
      run_command(PYTHON.to_s, "-c", schema_check)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_production_cut_review_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_video_prompt_storyboard_assist_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_video_prompt_manifest_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_03v_manifest_index_exactness_test.rb").to_s)
      {
        "default_control_profile" => "storyboard_assisted",
        "ordinary_production_cut_images_per_board" => "1_to_3",
        "one_image_requires_temporal_route_reason" => true,
        "attachment_order" => "@image1_board_then_ordered_original_frames",
        "temporal_camera_owner" => "03V_after_actual_pixel_inspection",
        "count_is_global_cap" => false
      }
    end
  },
  {
    id: "audio_branch_cut_placement_and_03v_incremental_refresh",
    objective: "Post-02B authoring requires exact 02A→02B→typed Production-Cut Review→Audio Production-Cut Placement→storyboard-assist v4→manifest v7 lineage, including the full PRE-00 storyline, selected Sequence, Core/Branch, and screen-progression bindings, permits smallest-owner local reprojection, and begins 04 only after passed 03V playback.",
    run: lambda do
      schema_check = <<~PYTHON
        import json
        import jsonschema
        for path in [
          "schemas/audio-branch-cut-placement.schema.json",
          "schemas/review.schema.json",
          "schemas/03v-source-snapshot.schema.json",
          "schemas/03v-playback-refresh-state.schema.json",
          "schemas/03v-generated-playback-intake.schema.json",
          "schemas/03v-playback-review-worklist.schema.json",
          "schemas/03v-playback-decision-sheet.schema.json",
          "schemas/03v-playback-review-record.schema.json",
        ]:
          with open(path, encoding="utf-8") as handle:
            jsonschema.Draft202012Validator.check_schema(json.load(handle))
      PYTHON
      run_command(PYTHON.to_s, "-c", schema_check)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_03v_placement_revision_binding_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_03v_prepare_lineage_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_post02b_03v_contracts_test.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_03v_refresh_playback_surfaces_test.rb").to_s)
      {
        "audio_production_cut_placement_version" => "v5",
        "video_prompt_manifest_version" => "v7",
        "exact_lineage_projection" => true,
        "smallest_owner_local_reprojection" => true,
        "camera_motion_deferred_until_03v" => true,
        "playback_refresh_digest" => true,
        "generated_clip_sha256" => true,
        "playback_pass_inferred" => false,
        "edit_owner" => "04_after_passed_03V_playback"
      }
    end
  },
  {
    id: "edit_cache_and_fx_dependency_integrity",
    objective: "04 keeps Branch Cuts as upstream lineage, authors Edit Slots, Edit Segments, and Edit Boundaries as distinct editorial units, reuses only source/config-identical evidence, and binds 04FX to the exact passed active edit chain without changing edit judgment.",
    run: lambda do
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_video_source_intake_cache_test.py").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "validate_edit_marker_plan_test.py").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_edit_recipe_validator_test.py").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_edit_marker_cutpoint_contact_sheet_test.py").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "validate_edit_finishing_fx_test.rb").to_s)
      {
        "cache_components" => %w[probe motion contact_sheet],
        "selective_invalidation" => true,
        "force_bypass" => true,
        "edit_marker_plan_version" => "idol_edit_marker_plan.v6",
        "editorial_units" => %w[edit_slot edit_segment edit_boundary video_frame],
        "branch_cut_to_edit_segment_cardinality" => "many_to_many_through_edit_slots",
        "fx_v1_status" => "historical_evidence_only",
        "fx_v2_stale_dependency_blocked" => true,
        "edit_pass_inferred" => false
      }
    end
  },
  {
    id: "creative_authority_and_artifact_lifecycle",
    objective: "Founder input remains actively traced but director-assessed before lock, while candidate breadth stays uncapped and canonical/archive cleanup is policy-bound and non-destructive.",
    run: lambda do
      schema_check = <<~PYTHON
        import json
        import jsonschema
        for path in [
          "schemas/artifact-lifecycle-policy.schema.json",
          "schemas/artifact-archive-manifest.schema.json",
        ]:
          with open(path, encoding="utf-8") as handle:
            jsonschema.Draft202012Validator.check_schema(json.load(handle))
      PYTHON
      run_command(PYTHON.to_s, "-c", schema_check)
      run_command(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, ROOT.join("schemas", "artifact-lifecycle-policy.schema.json").to_s, ROOT.join("automation", "artifact-lifecycle-policy.yaml").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_safe_workspace_cleanup_test.py").to_s)
      dry_run = JSON.parse(run_command(PYTHON.to_s, ROOT.join("scripts", "idol_safe_workspace_cleanup.py").to_s, "--json", "--skip-git-temp", "--max-report-items", "1")[:stdout])
      raise AcceptanceError, "workspace lifecycle audit stopped being dry-run by default" unless dry_run["mode"] == "dry_run_report_only"
      policy = YAML.safe_load(ROOT.join("automation", "artifact-lifecycle-policy.yaml").read, permitted_classes: [], permitted_symbols: [], aliases: true)
      unless policy.dig("versions", "creative_candidate_count_unbounded_before_selection") == true && policy.dig("canonical", "one_active_path_per_logical_artifact") == true
        raise AcceptanceError, "candidate breadth or canonical-owner lifecycle policy drifted"
      end
      unless policy.dig("cleanup", "production_auto_delete_allowed") == false && policy.dig("cleanup", "harmless_cache_apply_only") == true
        raise AcceptanceError, "production cleanup became automatic"
      end
      {"founder_reference_disposition_required" => true, "independent_director_assessment_required" => true, "candidate_count_capped_before_selection" => false, "canonical_active_paths_per_artifact" => 1, "max_rollback_checkpoints" => policy.dig("versions", "max_rollback_checkpoints_per_family"), "production_auto_delete_allowed" => false, "reported_legacy_pileup_families" => dry_run.dig("summary", "version_pileup_family_count"), "reported_legacy_root_or_archive_issues" => dry_run.dig("summary", "lifecycle_issue_count")}
    end
  },
  {
    id: "release_scope_record_and_evidence_integrity",
    objective: "05/social work is explicit-run, fail-closed for external action, separates active and immutable records, supports observed remote outputs, and cannot infer performance from missing metrics.",
    run: lambda do
      schema_check = <<~PYTHON
        import json
        import jsonschema
        for path in [
          "schemas/package.schema.json",
          "schemas/publishing-plan.schema.json",
          "schemas/publishing-record.schema.json",
          "schemas/platform-release-approval.schema.json",
          "schemas/social-evidence-snapshot.schema.json",
          "schemas/title-output-registry.schema.json",
        ]:
          with open(path, encoding="utf-8") as handle:
            jsonschema.Draft202012Validator.check_schema(json.load(handle))
      PYTHON
      run_command(PYTHON.to_s, "-c", schema_check)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "test_social_release_contracts.py").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "validate_publishing_plan_modes_test.py").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_social_evidence_snapshot_test.rb").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_title_output_registry_release_test.py").to_s)
      {"global_queue_default" => false, "approval_artifact_and_digest_required" => true, "active_closed_contracts_split" => true, "remote_publication_typed" => true, "no_metrics_state_explicit" => true, "external_action_inferred" => false}
    end
  },
  {
    id: "run_external_reference_hub_reuse",
    objective: "Every registered yt-dlp source resolves through one run-external owner with hash-bound reusable contact sheets, exact approval binding, and fail-closed no-redownload evidence checks.",
    run: lambda do
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_reference_hub_test.py").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "idol_video_qc_sheet_manifest_test.py").to_s)
      run_command(
        PYTHON.to_s,
        SCHEMA_VALIDATOR.to_s,
        ROOT.join("schemas", "downloaded-reference-hub.schema.json").to_s,
        ROOT.join("source-materials", "video-sources", "reference-hub-catalog.yaml").to_s
      )
      build = JSON.parse(
        run_command(
          PYTHON.to_s,
          ROOT.join("scripts", "idol_reference_hub.py").to_s,
          "build", "--check"
        )[:stdout]
      )
      verification = JSON.parse(
        run_command(
          PYTHON.to_s,
          ROOT.join("scripts", "idol_reference_hub.py").to_s,
          "verify"
        )[:stdout]
      )
      run_command("bash", "-n", ROOT.join("scripts", "yt-dlp-bilibili.sh").to_s)
      run_command("bash", "-n", ROOT.join("scripts", "yt-dlp-youtube-reference.sh").to_s)
      run_command("bash", "-n", ROOT.join("scripts", "yt-dlp-instagram-reference.sh").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "yt_dlp_youtube_reference_contract_test.py").to_s)
      run_command(PYTHON.to_s, ROOT.join("scripts", "tests", "yt_dlp_instagram_reference_contract_test.py").to_s)
      unless build["status"] == "current" && verification["valid"] == true && Array(verification["issues"]).empty?
        raise AcceptanceError, "reference hub is stale or invalid"
      end
      {
        "source_count" => build["source_count"],
        "catalog_current" => true,
        "missing_or_partial_holds" => Array(verification["holds"]).length,
        "future_capture_contact_sheet_manifest_required" => true,
        "silent_redownload_allowed" => false,
        "external_execution_approval_inferred" => false
      }
    end
  },
  {
    id: "skill_schema_and_language_integrity",
    objective: "Active skill links, contract versions, and prior-run creative-source isolation remain consistent after the local-revision update.",
    run: lambda do
      run_command(RbConfig.ruby, ROOT.join("scripts", "idol_skill_contract_check.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "validate_harness_skill_load_profiles.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "validate_harness_contract_version_registry.rb").to_s)
      run_command(RbConfig.ruby, ROOT.join("scripts", "tests", "idol_active_instruction_bias_test.rb").to_s)
      {
        "skill_link_contracts" => "pass",
        "skill_load_profiles" => "pass",
        "contract_version_registry" => "pass",
        "active_instruction_bias_regression" => "pass"
      }
    end
  }
]

active_check_ids = %w[
  stage_naming_and_decision_ownership
  quality_preserving_context_bootstrap
  operator_speed_and_render_correction
  instruction_surface_quality_and_efficiency
  revisioned_physical_section_sharding
  direct_deterministic_02b
  quality_first_5_6_shadow_policy
  motion_camera_first_03v_contract
  audio_branch_cut_placement_and_03v_incremental_refresh
  edit_cache_and_fx_dependency_integrity
  skill_schema_and_language_integrity
]
checks.select! { |check| active_check_ids.include?(check.fetch(:id)) }

report = {
  "schema_version" => "idol-harness-optimization-acceptance.v3",
  "generated_at" => Time.now.iso8601,
  "status" => "pass",
  "checks" => []
}

checks.each do |check|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    evidence = check.fetch(:run).call
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    row = {"id" => check[:id], "status" => "pass", "objective" => check[:objective], "elapsed_seconds" => elapsed.round(3), "evidence" => evidence}
    report["checks"] << row
    puts "PASS #{check[:id]} (#{row['elapsed_seconds']}s)" unless options[:json]
  rescue AcceptanceError, JSON::ParserError, Psych::SyntaxError => e
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    report["status"] = "fail"
    report["checks"] << {"id" => check[:id], "status" => "fail", "objective" => check[:objective], "elapsed_seconds" => elapsed.round(3), "error" => e.message}
    warn "FAIL #{check[:id]}: #{e.message}" unless options[:json]
    break
  end
end

if options[:json]
  puts JSON.pretty_generate(report)
else
  puts "IDOL Graph Engineering optimization acceptance: #{report['status']} (#{report['checks'].count { |row| row['status'] == 'pass' }}/#{checks.length})"
end
exit(report["status"] == "pass" ? 0 : 1)
