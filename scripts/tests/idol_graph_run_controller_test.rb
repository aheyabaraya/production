# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "yaml"
require_relative "../lib/idol_current_next_v2"
require_relative "../lib/idol_graph_run_controller"

class IdolGraphRunControllerTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCHEMA = ROOT.join("schemas", "graph-run-controller-state.schema.json")
  VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = ROOT.join("scripts", "idol-video-python")

  def setup
    parent = ROOT.join("runs", "controller-test", "fixture")
    parent.mkpath
    @run = parent.join("RUN_#{SecureRandom.hex(4).upcase}")
    @work = @run.join("work")
    @work.mkpath
    @run_rel = relative(@run)
    @output = @run.join("result.yaml")
    write_yaml(@output, "fixture" => "output")
    @validator_calls = []
    @contextual_judgment_validator = lambda do |root:, path:|
      @validator_calls << {"root" => root.to_s, "path" => path.to_s}
      {
        "status" => "pass",
        "validator" => "test_stub_contextual_judgment_validator",
        "boundary" => "test_stub"
      }
    end
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
  end

  def test_prepared_dispatch_plans_provider_neutral_dispatch_without_launch
    write_frontier(lifecycle: "prepared", stage_id: "song_direction_design")

    result = build

    assert_equal "dispatch_or_resume_model", result.dig("decision", "state")
    assert_equal false, result.dig("authority", "provider_launch_performed")
    assert_equal false, result.dig("authority", "execution_enabled")
    assert_equal "blocked_shadow_probe", result.dig("authority", "activation_status")
    assert_includes result.dig("authority", "activation_blockers"), "provider_launcher_not_connected"
    assert_equal false, result.dig("decision", "execution_authorized")
    assert_equal "legacy_action_code_untyped_shadow_hold", result.dig("decision", "authority_receipt_contract", "status")
    assert_equal false, result.dig("decision", "authority_receipt_contract", "typed_ddi_authority_requirements_present")
    assert_equal false, result.dig("decision", "authority_receipt_contract", "execution_authority")
    assert_equal false, result.dig("event_intent", "write_performed")
    assert_schema_valid(result)
  end

  def test_returned_creative_dispatch_with_bound_eligible_judgment_waits_for_director
    write_frontier(lifecycle: "returned", stage_id: "front_planning_integration")
    write_judgment

    result = build(judgment: relative(@judgment))

    assert_equal "await_director_review", result.dig("decision", "state")
    assert_equal "eligible_for_director_review", result.dig("evidence", "judgment_decision")
    assert_equal "test_stub", result.dig("validation", "contextual_judgment", "boundary")
    assert_equal "verified_shadow_bridge", result.dig("migration_bridge", "status")
    assert result.dig("migration_bridge", "checks").values.all? { |value| value == true }
    assert_equal relative(@graph_dispatch), result.dig("input_bindings", "graph_dispatch", "path")
    assert_equal 1, @validator_calls.length
    assert_nil result["correction_plan"]
    assert_schema_valid(result)
  end

  def test_contextual_judgment_requires_explicit_validator_pass_receipt
    write_frontier(lifecycle: "returned", stage_id: "front_planning_integration")
    write_judgment
    rejecting_validator = lambda do |root:, path:|
      assert_equal ROOT.to_s, root.to_s
      assert_equal @judgment.to_s, path.to_s
      {"status" => "fail", "validator" => "test_rejector", "boundary" => "test_stub"}
    end

    error = assert_raises(IdolGraphRunController::Error) do
      build(judgment: relative(@judgment), contextual_judgment_validator: rejecting_validator)
    end

    assert_includes error.message, "explicit pass receipt"
  end

  def test_injected_validator_cannot_bypass_formal_validation_outside_test_fixture_boundary
    error = assert_raises(IdolGraphRunController::Error) do
      IdolGraphRunController.invoke_contextual_judgment_validator!(
        root: ROOT,
        path: SCHEMA,
        validator: @contextual_judgment_validator
      )
    end

    assert_includes error.message, "restricted to the controller test fixture boundary"
  end

  def test_graph_and_legacy_dispatch_migration_bridge_fails_closed_on_owner_drift
    write_frontier(lifecycle: "returned", stage_id: "front_planning_integration")
    write_judgment(graph_owner: "another_worker")

    error = assert_raises(IdolGraphRunController::Error) { build(judgment: relative(@judgment)) }

    assert_includes error.message, "owner_exact_match"
  end

  def test_returned_creative_dispatch_without_bound_judgment_holds
    write_frontier(lifecycle: "returned", stage_id: "front_planning_integration")

    result = build

    assert_equal "hold", result.dig("decision", "state")
    assert_equal "bound_contextual_judgment_missing", result.dig("decision", "reason_code")
    assert_schema_valid(result)
  end

  def test_reviewed_accept_of_ineligible_judgment_remains_hold
    write_frontier(lifecycle: "reviewed", stage_id: "front_planning_integration", disposition: "accept")
    write_judgment(decision: "hold")

    result = build(judgment: relative(@judgment))

    assert_equal "hold", result.dig("decision", "state")
    assert_equal "judgment_not_eligible_without_director_correction", result.dig("decision", "reason_code")
    assert_schema_valid(result)
  end

  def test_director_patch_routes_only_same_owner_new_attempt_and_goal
    correction = correction_for("same_session_new_attempt")
    write_frontier(lifecycle: "reviewed", stage_id: "front_planning_integration", disposition: "patch", correction: correction)
    write_judgment

    result = build(judgment: relative(@judgment))
    plan = result.fetch("correction_plan")

    assert_equal "route_bounded_correction", result.dig("decision", "state")
    assert_equal 2, plan["next_submission_number"]
    assert_equal true, plan["new_immutable_attempt"]
    assert_equal true, plan["new_native_goal_required"]
    assert_equal "fixture_worker", plan["owner"]
    assert_equal [artifact], plan["invalidated_outputs"]
    assert_schema_valid(result)
  end

  def test_third_non_accept_submission_cannot_open_a_fourth_attempt
    correction = correction_for("same_session_new_attempt")
    write_frontier(lifecycle: "reviewed", stage_id: "front_planning_integration", disposition: "patch", correction: correction, submission_number: 3)
    write_judgment

    result = build(judgment: relative(@judgment))

    assert_equal "hold", result.dig("decision", "state")
    assert_equal "submission_limit_reached", result.dig("decision", "reason_code")
    assert_nil result["correction_plan"]
    assert_schema_valid(result)
  end

  def test_upstream_or_different_owner_correction_is_not_auto_routed
    correction = correction_for("upstream_owner").merge("affected_owner" => "another_owner")
    write_frontier(lifecycle: "reviewed", stage_id: "front_planning_integration", disposition: "hold", correction: correction)
    write_judgment

    result = build(judgment: relative(@judgment))

    assert_equal "hold", result.dig("decision", "state")
    assert_equal "director_correction_not_routable", result.dig("decision", "reason_code")
    assert_schema_valid(result)
  end

  def test_correction_invalidated_outputs_must_be_verified_subset_of_returned_outputs
    outside = @run.join("outside.yaml")
    write_yaml(outside, "fixture" => "not_returned")
    correction = correction_for("same_session_new_attempt").merge(
      "invalidated_outputs" => [{"path" => relative(outside), "sha256" => sha(outside), "role" => "fixture_output"}]
    )
    write_frontier(lifecycle: "reviewed", stage_id: "front_planning_integration", disposition: "patch", correction: correction)
    write_judgment

    result = build(judgment: relative(@judgment))

    assert_equal "hold", result.dig("decision", "state")
    assert_equal "director_correction_not_routable", result.dig("decision", "reason_code")
    assert_nil result["correction_plan"]
    assert_schema_valid(result)
  end

  def test_correction_invalidated_output_hash_must_match_exact_bytes
    correction = correction_for("same_session_new_attempt")
    correction["invalidated_outputs"][0]["sha256"] = "0" * 64
    write_frontier(lifecycle: "reviewed", stage_id: "front_planning_integration", disposition: "patch", correction: correction)
    write_judgment

    error = assert_raises(IdolGraphRunController::Error) { build(judgment: relative(@judgment)) }

    assert_includes error.message, "SHA-256 is stale"
  end

  def test_promoted_founder_gate_stops_only_for_bound_g0_to_g4_decision
    write_frontier(lifecycle: "promoted", stage_id: "front_planning_integration")

    result = build

    assert_equal "await_founder_decision", result.dig("decision", "state")
    assert_equal "G1", result.dig("decision", "founder_stop", "gate_id")
    assert_equal "creative_gate", result.dig("decision", "founder_stop", "authority_kind")
    assert_schema_valid(result)
  end

  def test_stage_registry_paid_authority_stops_even_for_generic_dispatch_action
    write_frontier(lifecycle: "prepared", stage_id: "image_generation_release_gate", action_code: "advance_dispatch")

    result = build

    assert_equal "await_founder_decision", result.dig("decision", "state")
    assert_equal "paid", result.dig("decision", "founder_stop", "authority_kind")
    assert_equal "graph_stage_registry_existing_paid_gate", result.dig("decision", "authority_requirements", 0, "source")
    assert_nil result.dig("decision", "authority_requirements", 0, "receipt_binding")
    assert_equal "missing_unconsumed_shadow", result.dig("decision", "authority_requirements", 0, "receipt_status")
    assert_equal false, result.dig("decision", "authority_receipt_contract", "all_required_receipts_verified")
    assert_schema_valid(result)
  end

  def test_release_authority_is_separate_from_master_package_authoring
    write_frontier(lifecycle: "prepared", stage_id: "master_package_release")

    result = build

    assert_equal "dispatch_or_resume_model", result.dig("decision", "state")
    assert_empty result.dig("decision", "authority_requirements")
    assert_equal false, result.dig("decision", "execution_authorized")
    assert_schema_valid(result)
  end

  def test_g4_closure_unions_creative_and_public_release_authorities
    write_frontier(lifecycle: "promoted", stage_id: "master_package_release")

    result = build
    requirements = result.dig("decision", "authority_requirements")

    assert_equal "await_founder_decision", result.dig("decision", "state")
    assert_equal "combined_founder_authorities_required", result.dig("decision", "reason_code")
    assert_equal "G4", result.dig("decision", "founder_stop", "gate_id")
    assert_equal %w[creative_gate release], requirements.map { |row| row["authority_kind"] }
    assert_equal %w[founder_authority_g4 founder_authority_release], requirements.map { |row| row["requirement_id"] }
    assert_equal 2, result.dig("decision", "authority_receipt_contract", "receipt_bindings").length
    assert_schema_valid(result)
  end

  def test_stage_and_action_material_authorities_are_unioned_without_execution_authority
    write_frontier(lifecycle: "prepared", stage_id: "image_generation_release_gate", action_code: "upload_approval")

    result = build
    requirements = result.dig("decision", "authority_requirements")

    assert_equal "await_founder_decision", result.dig("decision", "state")
    assert_equal "combined_founder_authorities_required", result.dig("decision", "reason_code")
    assert_equal %w[paid upload], requirements.map { |row| row["authority_kind"] }
    assert_equal false, result.dig("decision", "authority_receipt_contract", "typed_ddi_authority_requirements_present")
    assert_equal false, result.dig("decision", "execution_authorized")
    assert_schema_valid(result)
  end

  def test_compound_legacy_action_projects_separate_material_authority_requirements
    write_frontier(lifecycle: "prepared", stage_id: "song_direction_design", action_code: "download_capture_upload_external_mutation")

    result = build
    requirements = result.dig("decision", "authority_requirements")

    assert_equal %w[download capture upload external], requirements.map { |row| row["authority_kind"] }
    assert requirements.all? { |row| row["receipt_binding"].nil? && row["receipt_status"] == "missing_unconsumed_shadow" }
    assert_equal false, result.dig("decision", "authority_receipt_contract", "all_required_receipts_verified")
    assert_schema_valid(result)
  end

  def test_disjoint_parallel_cohort_actions_are_exposed_as_a_set_but_fail_closed
    write_frontier(
      lifecycle: "prepared",
      stage_id: "image_prompt_compilation",
      section_ids: ["S01"],
      extra_ready_sections: [["S02", "S03"]]
    )

    result = build

    assert_equal 2, result.dig("frontier_set", "ready_action_count")
    assert_equal "cohort_set_shadow_blocked", result.dig("frontier_set", "mode")
    assert_equal true, result.dig("frontier_set", "all_section_scopes_disjoint")
    assert_equal true, result.dig("frontier_set", "single_stage")
    assert_equal false, result.dig("frontier_set", "execution_allowed")
    assert_equal "hold", result.dig("decision", "state")
    assert_equal "parallel_cohort_frontier_shadow_blocked", result.dig("decision", "reason_code")
    assert_schema_valid(result)
  end

  def test_single_ready_action_with_same_stage_current_heads_holds_without_typed_join
    write_frontier(
      lifecycle: "prepared",
      stage_id: "image_prompt_compilation",
      current_head_stages: %w[image_prompt_compilation image_prompt_compilation]
    )

    result = build

    assert_equal 1, result.dig("frontier_set", "ready_action_count")
    assert_equal true, result.dig("frontier_set", "join_required")
    assert_equal "multi_head_same_stage_unresolved", result.dig("frontier_set", "join_status")
    assert_empty result.dig("frontier_set", "join_verified_head_ids")
    assert_equal "hold", result.dig("decision", "state")
    assert_equal "multi_head_join_unresolved", result.dig("decision", "reason_code")
    assert_schema_valid(result)
  end

  def test_single_ready_action_with_cross_stage_current_heads_holds_without_typed_join
    write_frontier(
      lifecycle: "prepared",
      stage_id: "image_prompt_compilation",
      current_head_stages: %w[front_planning_integration mv_storyboard_direction]
    )

    result = build

    assert_equal true, result.dig("frontier_set", "join_required")
    assert_equal "multi_stage_unresolved", result.dig("frontier_set", "join_status")
    assert_equal "hold", result.dig("decision", "state")
    assert_equal "multi_head_join_unresolved", result.dig("decision", "reason_code")
    assert_schema_valid(result)
  end

  def test_exact_typed_dependencies_close_same_stage_join_but_never_authorize_execution
    write_frontier(
      lifecycle: "prepared",
      stage_id: "image_prompt_compilation",
      current_head_stages: %w[image_prompt_compilation image_prompt_compilation],
      typed_join: true
    )

    result = build

    assert_equal "multi_head_same_stage_verified", result.dig("frontier_set", "join_status")
    assert_equal %w[HEAD_JOIN_1 HEAD_JOIN_2], result.dig("frontier_set", "join_verified_head_ids")
    assert_equal "dispatch_or_resume_model", result.dig("decision", "state")
    assert_equal false, result.dig("frontier_set", "execution_allowed")
    assert_equal false, result.dig("decision", "execution_authorized")
    assert_schema_valid(result)
  end

  def test_exact_typed_dependencies_close_cross_stage_join_but_never_authorize_execution
    write_frontier(
      lifecycle: "prepared",
      stage_id: "image_prompt_compilation",
      current_head_stages: %w[front_planning_integration mv_storyboard_direction],
      typed_join: true
    )

    result = build

    assert_equal "multi_stage_verified", result.dig("frontier_set", "join_status")
    assert_equal %w[HEAD_JOIN_1 HEAD_JOIN_2], result.dig("frontier_set", "join_verified_head_ids")
    assert_equal "dispatch_or_resume_model", result.dig("decision", "state")
    assert_equal false, result.dig("frontier_set", "execution_allowed")
    assert_equal false, result.dig("decision", "execution_authorized")
    assert_schema_valid(result)
  end

  def test_same_inputs_and_prior_hash_produce_same_idempotency_and_event_hash
    write_frontier(lifecycle: "prepared", stage_id: "song_direction_design")
    prior = "f" * 64

    first = build(previous_event_sha256: prior)
    second = build(previous_event_sha256: prior)

    assert_equal first.dig("event_intent", "idempotency_key"), second.dig("event_intent", "idempotency_key")
    assert_equal first.dig("event_intent", "event_sha256"), second.dig("event_intent", "event_sha256")
  end

  def test_stale_ddi_hash_fails_closed_before_reduction
    write_frontier(lifecycle: "prepared", stage_id: "song_direction_design")
    @ddi.open("a") { |file| file.puts("tampered: true") }

    error = assert_raises(IdolGraphRunController::Error) { build }
    assert_includes error.message, "SHA-256 is stale"
  end

  private

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def structured_sha(value)
    IdolGraphRunController.digest_value(value)
  end

  def write_yaml(path, document)
    path.dirname.mkpath
    path.write(YAML.dump(document), encoding: "utf-8")
  end

  def pointer(path, role = nil)
    row = {"path" => relative(path), "sha256" => sha(path)}
    row["role"] = role if role
    row
  end

  def artifact
    {"path" => relative(@output), "sha256" => sha(@output), "role" => "fixture_output"}
  end

  def correction_for(route)
    {
      "problem" => "The exact returned output remains below the Director requirement.",
      "evidence" => [{"kind" => "returned_output", "locator" => relative(@output), "source_sha256" => sha(@output), "observation" => "The named output requires one bounded correction."}],
      "screen_consequence" => "The output cannot advance unchanged.",
      "correction_action" => "Correct only the invalidated output while preserving all other returned bytes.",
      "remaining_risk" => "The corrected byte still requires a new judgment and Director review.",
      "affected_owner" => "fixture_worker",
      "invalidated_outputs" => [artifact],
      "complete_problem_set" => true,
      "acceptance_criteria" => ["The exact invalidated output closes the named problem and is re-reviewed."],
      "retry_route" => route
    }
  end

  def write_frontier(lifecycle:, stage_id:, disposition: nil, correction: nil, submission_number: 1, action_code: "advance_dispatch", section_ids: [], extra_ready_sections: [], current_head_stages: [], typed_join: false)
    @extra_dispatch_rows = []
    review = disposition ? {"disposition" => disposition, "correction" => correction} : nil
    dispatch = {
      "schema_version" => "idol-department-dispatch.v8",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => "DISPATCH_FIXTURE",
      "run" => @run_rel,
      "lineage" => {"attempt_id" => "DISPATCH_FIXTURE"},
      "review_submission" => {"review_cycle_id" => "CYCLE_FIXTURE", "submission_number" => submission_number, "maximum_submissions" => 3},
      "lifecycle" => {"current_state" => lifecycle},
      "launch" => {
        "task" => {
          "task_id" => "DISPATCH_FIXTURE",
          "exact_scope" => {
            "stage_id" => stage_id,
            "section_ids" => section_ids,
            "artifact_paths" => [relative(@output)]
          }
        },
        "authority" => {"assigned_owner" => "fixture_worker", "director_owner" => "fixture_director", "promotion_owner" => "fixture_overall"}
      },
      "runtime_return" => %w[returned reviewed promoted hold].include?(lifecycle) ? {"outputs" => [artifact]} : nil,
      "director_review" => review,
      "promotion" => lifecycle == "promoted" ? {"decision" => "promoted"} : nil
    }
    @dispatch = @work.join("DISPATCH_FIXTURE.yaml")
    write_yaml(@dispatch, dispatch)
    dispatch_pointer = pointer(@dispatch, "department_dispatch_v8")
    row = {
      "dispatch_id" => "DISPATCH_FIXTURE",
      "scope" => {"stage_id" => stage_id, "section_ids" => section_ids},
      "lifecycle" => {"current_state" => lifecycle},
      "dispatch_pointer" => dispatch_pointer,
      "review" => {"disposition" => disposition || "not_reviewed"},
      "next_action_ids" => []
    }
    holds = []
    queue_items = []
    actions = []
    if %w[prepared launched].include?(lifecycle)
      row["next_action_ids"] = ["NEXT_DISPATCH_FIXTURE"]
      actions << {
        "next_action_id" => "NEXT_DISPATCH_FIXTURE",
        "scope" => {"scope_kind" => "stage", "stage_id" => stage_id, "section_ids" => section_ids, "chunk_ids" => []},
        "action_code" => action_code,
        "owner" => "fixture_director",
        "state" => "ready",
        "dependency_pointers" => [dispatch_pointer]
      }
      extra_ready_sections.each_with_index do |extra_sections, index|
        extra_dispatch_id = "DISPATCH_COHORT_#{index + 2}"
        extra_action_id = "NEXT_#{extra_dispatch_id}"
        extra_dispatch_path = @work.join("#{extra_dispatch_id}.yaml")
        extra_dispatch = Marshal.load(Marshal.dump(dispatch))
        extra_dispatch["dispatch_id"] = extra_dispatch_id
        extra_dispatch["lineage"]["attempt_id"] = extra_dispatch_id
        extra_dispatch["launch"]["task"]["task_id"] = extra_dispatch_id
        extra_dispatch["launch"]["task"]["exact_scope"]["section_ids"] = extra_sections
        write_yaml(extra_dispatch_path, extra_dispatch)
        extra_pointer = pointer(extra_dispatch_path, "department_dispatch_v8")
        actions << {
          "next_action_id" => extra_action_id,
          "scope" => {"scope_kind" => "section_cohort", "stage_id" => stage_id, "section_ids" => extra_sections, "chunk_ids" => []},
          "action_code" => action_code,
          "owner" => "fixture_director",
          "state" => "ready",
          "dependency_pointers" => [extra_pointer]
        }
        extra_row = Marshal.load(Marshal.dump(row))
        extra_row["dispatch_id"] = extra_dispatch_id
        extra_row["scope"]["section_ids"] = extra_sections
        extra_row["dispatch_pointer"] = extra_pointer
        extra_row["next_action_ids"] = [extra_action_id]
        (@extra_dispatch_rows ||= []) << extra_row
      end
    elsif %w[returned reviewed].include?(lifecycle) && (disposition.nil? || disposition == "accept")
      queue_items << review_queue_item("queued")
    elsif lifecycle == "reviewed"
      holds << {
        "hold_id" => "HOLD_DISPATCH_FIXTURE",
        "scope" => {"scope_kind" => "hold_view", "stage_id" => stage_id, "section_ids" => [], "chunk_ids" => []},
        "dispatch_id" => "DISPATCH_FIXTURE",
        "owner" => "fixture_director",
        "evidence_pointers" => [dispatch_pointer],
        "state" => "open"
      }
    end

    current_heads = current_head_stages.each_with_index.map do |head_stage_id, index|
      head_artifact_path = @work.join("head-join-#{index + 1}.yaml")
      write_yaml(head_artifact_path, "fixture" => "head-#{index + 1}")
      {
        "head_id" => "HEAD_JOIN_#{index + 1}",
        "logical_artifact_id" => "ARTIFACT_JOIN_#{index + 1}",
        "stage_id" => head_stage_id,
        "artifact" => pointer(head_artifact_path, "canonical_artifact"),
        "source_dispatch_id" => "DISPATCH_HEAD_#{index + 1}",
        "state" => "current",
        "supersession_state" => "none"
      }
    end
    if current_heads.empty? && lifecycle == "promoted"
      current_heads << {
        "head_id" => "HEAD_FIXTURE",
        "logical_artifact_id" => "ARTIFACT_FIXTURE",
        "stage_id" => stage_id,
        "artifact" => pointer(@output, "canonical_artifact"),
        "source_dispatch_id" => "DISPATCH_FIXTURE",
        "state" => "current",
        "supersession_state" => "none"
      }
    end
    if typed_join && actions.length == 1
      actions.first["dependency_pointers"].concat(current_heads.map do |head|
        head.fetch("artifact").merge("role" => IdolGraphRunController::JOIN_DEPENDENCY_ROLE)
      end)
    end
    source_set_sha = "a" * 64
    ddi = {
      "schema_version" => "idol-director-dispatch-index.v4",
      "run" => @run_rel,
      "source_set_sha256" => source_set_sha,
      "source_set_digest" => {"sha256" => source_set_sha},
      "dispatch_source_set" => {"entry_count" => 1 + Array(@extra_dispatch_rows).length},
      "dispatches" => [row] + Array(@extra_dispatch_rows),
      "review_queue" => {"selection_order" => "dependency_rank_then_returned_at_then_dispatch_id", "items" => queue_items},
      "current_heads" => current_heads,
      "holds" => holds,
      "next_actions" => actions
    }
    @ddi = @work.join("director-dispatch-index.yaml")
    write_yaml(@ddi, ddi)
    selection = IdolCurrentNextV2.expected_selection(ddi)
    canonical_heads = if current_heads.empty?
                        {"resolution" => "not_yet_promoted", "items" => []}
                      else
                        {"resolution" => "bound", "items" => current_heads.each_with_index.map do |head, index|
                          {
                            "head_id" => head.fetch("head_id"),
                            "json_pointer" => "/current_heads/#{index}",
                            "row_sha256" => IdolCurrentNextV2.row_sha256(head),
                            "artifact" => head.fetch("artifact")
                          }
                        end}
                      end
    current_next = {
      "schema_version" => "harness-current-next.v2",
      "artifact_type" => "harness_current_next",
      "run" => @run_rel,
      "album_key" => "controller-test",
      "title_key" => "fixture",
      "status" => IdolCurrentNextV2.expected_status(selection),
      "owner" => IdolCurrentNextV2.expected_owner(ddi, selection),
      "frontier_binding" => {
        "director_dispatch_index" => pointer(@ddi, "director_dispatch_index_v4"),
        "source_set_sha256" => source_set_sha,
        "selection" => selection,
        "canonical_heads" => canonical_heads
      },
      "legacy_evidence" => {"selection_authority" => false, "source_next_unit" => nil, "source_founder_gate" => nil, "source_action_queue" => nil}
    }
    @current_next = @work.join("current-next.yaml")
    write_yaml(@current_next, current_next)
  end

  def review_queue_item(state)
    {
      "dispatch_id" => "DISPATCH_FIXTURE",
      "director_owner" => "fixture_director",
      "dependency_rank" => 0,
      "returned_at" => "2026-09-03T00:00:00Z",
      "queue_state" => state,
      "blocks_next" => true
    }
  end

  def write_judgment(graph_owner: "fixture_worker", decision: "eligible_for_director_review")
    registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
    release_binding = registry.fetch("current_profile_releases").fetch("front_planning_close")
    release_path = ROOT.join(release_binding.fetch("path"))
    release = YAML.safe_load(release_path.read, aliases: true)
    profile = release.fetch("profile")
    criteria = profile.fetch("criteria").map do |row|
      {
        "criterion_id" => row.fetch("criterion_id"),
        "result" => row["critical_four"] == true ? 4 : row.fetch("minimum"),
        "evidence_locator" => [pointer(@output).slice("path", "sha256")],
        "observable_claim" => "The assigned author recorded an observable claim.",
        "screen_consequence" => "The exact output has a named consequence.",
        "preserve" => "Preserve the bound evidence.",
        "change" => "Change only the named defect.",
        "do_not_infer" => "Do not infer creative PASS.",
        "correction_action" => "Return any defect to the same owner.",
        "acceptance_evidence" => "Recheck the exact changed bytes."
      }
    end
    @graph_output_manifest = @work.join("graph-output-manifest.yaml")
    write_yaml(@graph_output_manifest, {
      "dispatch_id" => "DISPATCH_FIXTURE",
      "assigned_owner" => graph_owner,
      "outputs" => [artifact]
    })
    @graph_dispatch = @work.join("graph-dispatch.yaml")
    write_yaml(@graph_dispatch, {
      "schema_version" => "idol-graph-department-dispatch.v1",
      "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => "DISPATCH_FIXTURE",
      "run" => @run_rel,
      "section_ids" => [],
      "assigned_owner" => graph_owner,
      "output_writer" => {"session_id" => "fixture_author_session"},
      "output_manifest" => pointer(@graph_output_manifest),
      "judgment_profile_id" => "front_planning_close",
      "lifecycle_state" => "returned"
    })
    @judgment = @work.join("judgment.yaml")
    write_yaml(@judgment, {
      "schema_version" => "idol_graph_contextual_judgment.v2",
      "artifact_type" => "graph_contextual_judgment",
      "profile_id" => "front_planning_close",
      "checkpoint_id" => "p3_section_kinetic_architecture",
      "stage_id" => "front_planning_integration",
      "criteria" => criteria,
      "execution_binding" => {
        "assignment_id" => "DISPATCH_FIXTURE",
        "dispatch" => pointer(@graph_dispatch),
        "author_session_id" => "fixture_author_session",
        "profile_release" => pointer(release_path),
        "output_manifest" => pointer(@graph_output_manifest),
        "profile_value_sha256" => structured_sha(profile)
      },
      "decision" => decision,
      "next_edge" => registry.dig("decision_edges", decision),
      "status" => registry.dig("decision_status", decision),
      "aggregate_score_present" => false,
      "automatic_creative_pass" => false
    })
  end

  def build(judgment: nil, previous_event_sha256: nil, contextual_judgment_validator: @contextual_judgment_validator)
    IdolGraphRunController.build(
      root: ROOT,
      run: @run_rel,
      current_next: relative(@current_next),
      judgment: judgment,
      previous_event_sha256: previous_event_sha256,
      contextual_judgment_validator: contextual_judgment_validator
    )
  end

  def assert_schema_valid(document)
    candidate = @work.join("controller-output.yaml")
    write_yaml(candidate, document)
    stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, SCHEMA.to_s, candidate.to_s, chdir: ROOT.to_s)
    assert status.success?, "#{stdout}\n#{stderr}"
  end
end
