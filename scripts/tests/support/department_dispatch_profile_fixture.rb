# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "../../lib/idol_checkpoint_closure_catalog"

module DepartmentDispatchProfileFixture
  PROFILE_REGISTRY_PATH = "automation/harness-skill-load-profiles.yaml"
  STUDIO_KERNEL_PATH = "skills/idol-orchestrator/references/provider-neutral-studio-kernel.md"
  GOAL_DIRECTIVE = "First runtime action: open the native Goal from launch.goal_contract and record its id before required reads or creative work."
  LAUNCH_BLOCK_HEADINGS = [
    "## 01 Dispatch Identity",
    "## 02 Role And Authority",
    "## 03 Current Creative Job",
    "## 04 Exact Scope And Non-Scope",
    "## 05 Input Pointers",
    "## 06 Skill Route",
    "## 07 Required Work",
    "## 08 Output Contract",
    "## 09 Quality Proof",
    "## 10 Return-Ready Conditions",
    "## 11 HOLD Stop And Split Conditions",
    "## 12 Return And Wake"
  ].freeze
  REQUIREMENT_PROJECTION_PREFIX = "DDC_REQUIREMENT_PROJECTION_V1 ".freeze
  ANTI_FLAT_PROJECTION_PREFIX = "DDC_ANTI_FLAT_PROJECTION_V1 ".freeze
  REQUIREMENT_PROJECTION_FIELDS = %w[
    requirement_id
    source_locator
    affected_scope
    expected_output_target
    evidence_type
    director_semantic_review_required
  ].freeze

  def dispatch_fixture_profile_registry
    @dispatch_fixture_profile_registry ||= YAML.safe_load(
      dispatch_fixture_root.join(PROFILE_REGISTRY_PATH).read,
      aliases: true
    )
  end

  def dispatch_fixture_profile_contract(profile_id:, checkpoint_id:)
    registry = dispatch_fixture_profile_registry
    profile = Array(registry["profiles"]).find { |row| row["profile_id"].to_s == profile_id.to_s }
    raise "missing fixture profile: #{profile_id}" unless profile

    checkpoint = Array(profile.dig("phase_load", "checkpoints")).find do |row|
      row["checkpoint_id"].to_s == checkpoint_id.to_s
    end
    raise "missing fixture checkpoint: #{profile_id}.#{checkpoint_id}" unless checkpoint

    skills_by_id = Array(registry["skill_bindings"]).to_h { |row| [row["binding_id"].to_s, row] }
    reads_by_id = Array(registry["read_bindings"]).to_h { |row| [row["binding_id"].to_s, row] }
    linked_reads = Array(checkpoint["required_read_ids"]).map do |binding_id|
      row = reads_by_id.fetch(binding_id.to_s)
      {
        "path" => row.fetch("path"),
        "sha256" => row.fetch("sha256"),
        "eof_required" => true,
        "reason" => "Exact registered read for #{profile_id}.#{checkpoint_id}."
      }
    end

    skills = Array(checkpoint["required_skill_ids"]).each_with_index.map do |binding_id, index|
      row = skills_by_id.fetch(binding_id.to_s)
      {
        "path" => row.fetch("path"),
        "revision" => row.fetch("revision").to_s,
        "sha256" => row.fetch("sha256"),
        "eof_required" => true,
        "linked_reads" => index.zero? ? linked_reads : []
      }
    end

    {
      "profile" => profile,
      "checkpoint" => checkpoint,
      "required_skills" => skills
    }
  end

  def dispatch_fixture_compiled_launch_prompt(profile_id:, checkpoint_id:, source_ids:, model_or_role_profile: "fixture-provider-neutral")
    registry_path = dispatch_fixture_root.join(PROFILE_REGISTRY_PATH)
    kernel_path = dispatch_fixture_root.join(STUDIO_KERNEL_PATH)
    prompt = dispatch_fixture_rendered_prompt
    value = {
      "derivation" => "studio_kernel_plus_exact_selected_profile_checkpoint_plus_current_run_creative_delta",
      "studio_kernel" => {
        "path" => STUDIO_KERNEL_PATH,
        "sha256" => dispatch_fixture_file_sha(kernel_path),
        "role" => "Shared provider-neutral Studio Kernel"
      },
      "selected_profile" => {
        "profile_id" => profile_id,
        "checkpoint_id" => checkpoint_id,
        "registry_path" => PROFILE_REGISTRY_PATH,
        "registry_sha256" => dispatch_fixture_file_sha(registry_path),
        "model_or_role_profile" => model_or_role_profile
      },
      "current_run_creative_delta_source_ids" => Array(source_ids),
      "block_order" => %w[
        dispatch_identity
        role_and_authority
        current_creative_job
        exact_scope_and_non_scope
        input_pointers
        skill_route
        required_work
        output_contract
        quality_proof
        return_ready_conditions
        hold_stop_split_conditions
        return_and_wake
      ],
      "first_runtime_action" => "open_native_goal_from_goal_contract_and_record_goal_id_before_reads_or_work",
      "assembly_policy" => "fixed_labels_and_exact_copy_only",
      "current_value_authority" => "owning_director",
      "rendered_prompt" => prompt,
      "compiled_input_sha256" => "0" * 64,
      "rendered_prompt_sha256" => Digest::SHA256.hexdigest(prompt)
    }
    basis = value.reject do |key, _entry|
      %w[rendered_prompt compiled_input_sha256 rendered_prompt_sha256].include?(key)
    end
    value["compiled_input_sha256"] = dispatch_fixture_structured_sha(basis)
    value
  end

  def dispatch_fixture_project_launch_prompt!(launch)
    compiled = launch.fetch("compiled_launch_prompt")
    prompt = dispatch_fixture_rendered_prompt(
      requirement_manifest: launch.fetch("requirement_manifest"),
      anti_flat_evidence_requirements: launch.dig("bounded_output", "anti_flat_evidence_requirements")
    )
    compiled["rendered_prompt"] = prompt
    compiled["rendered_prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    basis = compiled.reject do |key, _entry|
      %w[rendered_prompt compiled_input_sha256 rendered_prompt_sha256].include?(key)
    end
    compiled["compiled_input_sha256"] = dispatch_fixture_structured_sha(basis)
    launch
  end

  def dispatch_fixture_runtime_skill_revisions(required_skills, read_completed_at: "2026-08-03T10:01:20+09:00")
    Array(required_skills).map do |skill|
      {
        "path" => skill.fetch("path"),
        "revision" => skill.fetch("revision"),
        "sha256" => skill.fetch("sha256"),
        "read_to_eof" => true,
        "read_completed_at" => read_completed_at,
        "linked_reads" => Array(skill["linked_reads"]).map do |row|
          {
            "path" => row.fetch("path"),
            "sha256" => row.fetch("sha256"),
            "read_to_eof" => true,
            "read_completed_at" => read_completed_at
          }
        end
      }
    end
  end

  def dispatch_fixture_promoted_document(
    run_path:,
    dispatch_id:,
    stage_id:,
    artifact_path:,
    owner_role:,
    profile_id:,
    checkpoint_id:,
    assigned_owner: "fixture-worker",
    director_owner: "fixture-director",
    promotion_owner: nil,
    recipient_role: "creative_development_director",
    output_role: "active stage artifact",
    objective: nil,
    requirement_overrides_by_category: {}
  )
    root = dispatch_fixture_root
    promotion_owner ||= director_owner
    run_relative = Pathname.new(run_path).relative_path_from(root).to_s
    artifact_relative = Pathname.new(artifact_path).relative_path_from(root).to_s
    objective ||= "Return the exact bounded #{stage_id} artifact for independent Director review."
    profile_contract = dispatch_fixture_profile_contract(
      profile_id: profile_id,
      checkpoint_id: checkpoint_id
    )
    required_skills = profile_contract.fetch("required_skills")
    output = {
      "path" => artifact_relative,
      "sha256" => dispatch_fixture_file_sha(artifact_path),
      "role" => output_role
    }
    source = output.merge("role" => "bounded source and returned output")
    skill_linked_reads = required_skills.flat_map { |skill| Array(skill["linked_reads"]) }
    required_reads = if required_skills.empty?
                       Array(profile_contract.dig("checkpoint", "required_read_ids")).map do |binding_id|
                         row = Array(dispatch_fixture_profile_registry["read_bindings"]).find { |candidate| candidate["binding_id"].to_s == binding_id.to_s }
                         raise "missing fixture read binding: #{binding_id}" unless row

                         {
                           "path" => row.fetch("path"),
                           "sha256" => row.fetch("sha256"),
                           "eof_required" => true,
                           "reason" => "Exact registered read for #{profile_id}.#{checkpoint_id}."
                         }
                       end
                     else
                       []
                     end
    policy_read = (skill_linked_reads + required_reads).find do |row|
      row["path"].to_s.start_with?("policies/")
    end
    policy_read ||= skill_linked_reads.first || required_reads.first
    execution_contract = root.join("automation", "harness-execution-contract.yaml")
    dispatch_schema = root.join("schemas", "department-dispatch.schema.json")
    requirement_sources = {
      "founder" => source,
      "skill" => if required_skills.empty?
        {
          "path" => policy_read.fetch("path"),
          "sha256" => policy_read.fetch("sha256"),
          "role" => "skill-less maintenance checkpoint read"
        }
      else
        {
          "path" => required_skills.first.fetch("path"),
          "sha256" => required_skills.first.fetch("sha256"),
          "role" => "owning skill"
        }
      end,
      "policy" => {
        "path" => policy_read.fetch("path"),
        "sha256" => policy_read.fetch("sha256"),
        "role" => "governing policy"
      },
      "contract" => {
        "path" => execution_contract.relative_path_from(root).to_s,
        "sha256" => dispatch_fixture_file_sha(execution_contract),
        "role" => "execution contract"
      },
      "schema" => {
        "path" => dispatch_schema.relative_path_from(root).to_s,
        "sha256" => dispatch_fixture_file_sha(dispatch_schema),
        "role" => "owning dispatch schema"
      }
    }
    categories = %w[founder skill policy contract schema output quality hold goal]
    requirements = categories.each_with_index.map do |category, index|
      {
        "requirement_id" => "#{category.upcase}-#{format('%02d', index + 1)}",
        "category" => category,
        "required" => true,
        "source_locator" => requirement_sources[category]&.fetch("path", nil) || "/launch/#{category}",
        "source_binding" => requirement_sources[category],
        "affected_scope" => "The exact bounded #{stage_id} fixture output and its dispatch lifecycle.",
        "expected_output_target" => category == "goal" ? "/runtime_return/runtime_goal" : artifact_relative,
        "evidence_type" => category == "goal" ? "runtime_goal" : (category == "hold" ? "hold" : "artifact"),
        "director_semantic_review_required" => %w[founder skill policy contract schema output quality].include?(category)
      }.merge(requirement_overrides_by_category.fetch(category, {}))
    end
    dispatch_fixture_append_recipe_rows!(
      requirements,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      output: output
    )
    launch = {
      "prepared_at" => "2026-08-03T12:00:00+09:00",
      "launched_at" => "2026-08-03T12:01:00+09:00",
      "launch_kind" => "worker_dispatch",
      "compiled_launch_prompt" => dispatch_fixture_compiled_launch_prompt(
        profile_id: profile_id,
        checkpoint_id: checkpoint_id,
        source_ids: ["source_artifact"]
      ),
      "task" => {
        "task_id" => dispatch_id,
        "role" => owner_role,
        "objective" => objective,
        "exact_scope" => {
          "mode" => "whole_run",
          "stage_id" => stage_id,
          "section_ids" => [],
          "artifact_paths" => [artifact_relative]
        }
      },
      "goal_contract" => {
        "required" => true,
        "goal_text" => objective,
        "goal_text_sha256" => Digest::SHA256.hexdigest(objective),
        "source_objective_pointer" => "/launch/task/objective",
        "source_scope_pointer" => "/launch/task/exact_scope",
        "creation_timing" => "before_required_reads_and_creative_work",
        "completion_timing" => "only_after_valid_runtime_return_and_worker_self_check",
        "unsupported_runtime_action" => "goal_surface_unavailable_hold_before_work"
      },
      "requirement_manifest" => requirements,
      "founder_context" => {"decision_epoch" => "FOUNDER-EPOCH-FIXTURE", "locks" => []},
      "required_skills" => required_skills,
      "required_reads" => required_reads,
      "sources" => [{
        "source_id" => "source_artifact",
        "path" => artifact_relative,
        "sha256" => output.fetch("sha256"),
        "purpose" => "Exact bounded source bytes for the fixture dispatch."
      }],
      "external_permission" => {"mode" => "closed_local", "allowed_surfaces" => [], "approval_reference" => nil},
      "bounded_output" => {
        "description" => "One exact hash-bound fixture artifact.",
        "output_kind" => "bounded_artifact",
        "expected_paths" => [artifact_relative],
        "maximum_artifact_count" => 1,
        "anti_flat_evidence_requirements" => ["Preserve the exact bounded source truth and current assignment resolution."]
      },
      "authority" => {
        "assigned_owner" => assigned_owner,
        "director_owner" => director_owner,
        "promotion_owner" => promotion_owner,
        "canonical_write" => "bounded_to_expected_paths",
        "external_actions" => "forbidden",
        "may_decide" => ["The exact bounded fixture artifact."],
        "must_not" => ["Change another stage or use an external surface."]
      },
      "hold_conditions" => ["Required Goal, skill, source, or contract bytes cannot be verified exactly."],
      "recipient" => {"owner" => director_owner, "role" => recipient_role, "return_route" => "director_output_review"}
    }
    launch.delete("required_reads") if required_reads.empty?
    dispatch_fixture_project_launch_prompt!(launch)
    lineage = {
      "lineage_id" => "LINEAGE_#{dispatch_id}",
      "attempt_id" => dispatch_id,
      "attempt_number" => 1,
      "provider" => "codex",
      "runtime_surface" => "test-runtime",
      "session_id" => "SESSION_#{dispatch_id}",
      "parent_session_id" => "SESSION_FIXTURE_DIRECTOR",
      "parent_lineage_id" => "LINEAGE_FIXTURE_DIRECTOR",
      "parent_dispatch_id" => "DISPATCH_FIXTURE_DIRECTOR",
      "previous_attempt_id" => nil,
      "delegation_depth" => 1,
      "lineage_state" => "active",
      "successor_attempt_id" => nil
    }
    review_submission = {
      "review_cycle_id" => dispatch_id,
      "submission_number" => 1,
      "maximum_submissions" => 3,
      "submission_kind" => "initial",
      "root_attempt_id" => dispatch_id,
      "previous_submission_attempt_id" => nil,
      "correction_source" => nil,
      "repair_targets" => [],
      "repair_acceptance_criteria" => [],
      "frozen_outputs" => []
    }
    checks = requirements.map do |requirement|
      {
        "check_id" => "MECH-#{requirement.fetch('requirement_id')}",
        "requirement_id" => requirement.fetch("requirement_id"),
        "check_kind" => requirement.fetch("category") == "goal" ? "goal_order" : "coverage",
        "target" => requirement.fetch("expected_output_target"),
        "result" => "pass",
        "evidence" => "Fixture structural evidence exists for #{requirement.fetch('requirement_id')}."
      }
    end
    receipt = {
      "contract_version" => "mechanical_compliance_receipt.v1",
      "validated_at" => "2026-08-03T12:01:50+09:00",
      "validator" => "fixture-department-dispatch-mechanical-validator",
      "checks" => checks,
      "all_required_checks_pass" => true,
      "receipt_sha256" => "0" * 64
    }
    receipt["receipt_sha256"] = dispatch_fixture_structured_sha(receipt.reject { |key, _value| key == "receipt_sha256" })
    claims = requirements.map do |requirement|
      {
        "requirement_id" => requirement.fetch("requirement_id"),
        "disposition" => "applied",
        "output_evidence" => %w[goal hold].include?(requirement.fetch("category")) ? [] : [output],
        "explanation" => "The worker applied #{requirement.fetch('requirement_id')} to the exact bounded fixture result."
      }
    end
    goal_completion_basis = {
      "mechanical_compliance_receipt_sha256" => receipt.fetch("receipt_sha256"),
      "worker_fulfillment_claims" => claims,
      "outputs" => [output],
      "hold_reasons" => []
    }
    runtime_return = {
      "returned_at" => "2026-08-03T12:02:00+09:00",
      "work_started_at" => "2026-08-03T12:01:30+09:00",
      "runtime_owner" => {"owner" => assigned_owner, "role" => owner_role, "runtime_surface" => "test-runtime"},
      "runtime_goal" => {
        "provider" => "codex",
        "native_goal_id" => "GOAL-#{dispatch_id}",
        "opened_at" => "2026-08-03T12:01:10+09:00",
        "goal_text_sha256" => launch.dig("goal_contract", "goal_text_sha256"),
        "state_at_return" => "achieved",
        "completion_evidence_sha256" => dispatch_fixture_structured_sha(goal_completion_basis)
      },
      "skill_revisions" => dispatch_fixture_runtime_skill_revisions(required_skills, read_completed_at: "2026-08-03T12:01:20+09:00"),
      "mechanical_compliance_receipt" => receipt,
      "worker_fulfillment_claims" => claims,
      "input_digest" => {
        "basis" => "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4",
        "sha256" => dispatch_fixture_structured_sha("lineage" => lineage, "review_submission" => review_submission, "launch" => launch)
      },
      "output_inventory" => {"mode" => "single_artifact", "artifact_count" => 1, "aggregate_manifest" => nil},
      "outputs" => [output],
      "result_digest" => {
        "basis" => "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4",
        "sha256" => "0" * 64
      },
      "transport_closure_summary" => {
        "status" => "clean",
        "creative_bytes_changed" => false,
        "error" => nil,
        "source_digest" => {"basis" => "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4", "sha256" => output.fetch("sha256")},
        "output_digest" => {"basis" => "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4", "sha256" => output.fetch("sha256")},
        "schema_version" => "idol-transport-closure-summary.v1",
        "refresh_receipt_pointer" => nil,
        "corroboration_pointers" => [],
        "repair_count" => 0,
        "exceptions" => [],
        "next_owner" => recipient_role
      },
      "hold_reasons" => [],
      "wake_event" => {
        "event_kind" => "final",
        "recipient_role" => recipient_role,
        "output_pointers" => [output],
        "aggregate_manifest" => nil,
        "hold_or_rejection_pointers" => [],
        "risk_or_unresolved_decision_pointers" => [],
        "raw_commentary_included" => false
      }
    }
    result_basis = %w[
      work_started_at runtime_owner runtime_goal skill_revisions
      mechanical_compliance_receipt worker_fulfillment_claims output_inventory
      outputs hold_reasons wake_event
    ].each_with_object({}) { |key, result| result[key] = runtime_return[key] }
    runtime_return.dig("result_digest")["sha256"] = dispatch_fixture_structured_sha(result_basis)
    reviewer_reads = required_skills.flat_map do |skill|
      [{
        "path" => skill.fetch("path"),
        "kind" => "skill",
        "revision" => skill.fetch("revision"),
        "sha256" => skill.fetch("sha256"),
        "read_to_eof" => true,
        "read_completed_at" => "2026-08-03T12:02:30+09:00"
      }] + Array(skill["linked_reads"]).map do |read|
        {
          "path" => read.fetch("path"),
          "kind" => "linked_module",
          "revision" => "hash-bound-launch-read",
          "sha256" => read.fetch("sha256"),
          "read_to_eof" => true,
          "read_completed_at" => "2026-08-03T12:02:30+09:00"
        }
      end
    end
    requirements.each do |requirement|
      next unless requirement["director_semantic_review_required"] == true
      next unless %w[skill policy contract schema].include?(requirement.fetch("category"))
      next unless requirement["source_binding"].is_a?(Hash)

      source_binding = requirement.fetch("source_binding")
      next if reviewer_reads.any? { |row| row["path"] == source_binding["path"] && row["sha256"] == source_binding["sha256"] }

      reviewer_reads << {
        "path" => source_binding.fetch("path"),
        "kind" => requirement.fetch("category"),
        "revision" => "hash-bound-requirement-source",
        "sha256" => source_binding.fetch("sha256"),
        "read_to_eof" => true,
        "read_completed_at" => "2026-08-03T12:02:30+09:00"
      }
    end
    requirement_results = requirements.map do |requirement|
      {
        "requirement_id" => requirement.fetch("requirement_id"),
        "result" => "pass",
        "evidence_locator" => artifact_relative,
        "evidence_sha256" => output.fetch("sha256"),
        "judgment" => "The Director read the exact returned bytes and judged #{requirement.fetch('requirement_id')} complete."
      }
    end
    review_lease_id = "REVIEW-#{dispatch_id}"
    promotion_lease_id = "PROMOTION-#{dispatch_id}"
    review = {
      "reviewed_at" => "2026-08-03T12:03:00+09:00",
      "director" => {"owner" => director_owner, "role" => recipient_role},
      "review_lease_id" => review_lease_id,
      "reviewer_read_closure" => reviewer_reads,
      "mechanical_receipt_sha256" => receipt.fetch("receipt_sha256"),
      "requirement_results" => requirement_results,
      "disposition" => "accept",
      "rubric_results" => %w[
        goal_opened_and_pursued founder_instruction_coverage owning_skill_application
        schema_and_contract_conformance current_assignment_resolution required_output_coverage
        observable_specificity source_and_pixel_grounding storyline_preservation
        locks_scope_and_unaffected_truth honest_completion_state
      ].map do |criterion|
        {"criterion" => criterion, "result" => "pass", "evidence" => "Fixture #{criterion} judgment on the exact returned bytes."}
      end,
      "reviewed_outputs" => [output],
      "summary" => "The Director independently reviewed and accepted the exact returned bytes.",
      "correction" => nil
    }
    promotion = {
      "decision" => "promoted",
      "mode" => "direct_canonical_promotion",
      "decided_at" => "2026-08-03T12:04:00+09:00",
      "promoter" => {"owner" => promotion_owner, "role" => "overall_director"},
      "promotion_lease_id" => promotion_lease_id,
      "approved_at" => "2026-08-03T12:04:00+09:00",
      "reason" => "The exact bounded bytes passed independent Director review.",
      "approved_working_outputs" => [output],
      "coordinator" => nil,
      "copy_completed_at" => nil,
      "canonical_artifacts" => [output],
      "queue_release_verified" => true,
      "baseline_refresh_evidence_sha256" => "0" * 64,
      "next_recipient" => {"owner" => "fixture-orchestrator", "role" => "next-stage-coordinator", "return_route" => "active_harness_stage"}
    }
    promotion_basis = {
      "dispatch_id" => dispatch_id,
      "review_lease_id" => review_lease_id,
      "promotion_lease_id" => promotion_lease_id,
      "decision" => promotion.fetch("decision"),
      "approved_working_outputs" => promotion.fetch("approved_working_outputs"),
      "canonical_artifacts" => promotion.fetch("canonical_artifacts"),
      "decided_at" => promotion.fetch("decided_at")
    }
    promotion["baseline_refresh_evidence_sha256"] = dispatch_fixture_structured_sha(promotion_basis)
    {
      "schema_version" => "idol-department-dispatch.v8",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => dispatch_id,
      "run" => run_relative,
      "lineage" => lineage,
      "review_submission" => review_submission,
      "lifecycle" => {
        "current_state" => "promoted",
        "events" => [
          {"state" => "prepared", "at" => launch.fetch("prepared_at"), "actor" => director_owner},
          {"state" => "launched", "at" => launch.fetch("launched_at"), "actor" => "test-runtime"},
          {"state" => "returned", "at" => runtime_return.fetch("returned_at"), "actor" => assigned_owner},
          {"state" => "reviewed", "at" => review.fetch("reviewed_at"), "actor" => director_owner},
          {"state" => "promoted", "at" => promotion.fetch("decided_at"), "actor" => promotion_owner}
        ]
      },
      "review_control" => {
        "queue_policy" => "single_flight_per_recipient_director_then_global_overall_promotion",
        "queue_state" => "released",
        "queued_at" => runtime_return.fetch("returned_at"),
        "queue_priority" => {"dependency_rank" => 0, "returned_at_then_dispatch_id" => true},
        "review_lease" => {
          "lease_id" => review_lease_id,
          "director_owner" => director_owner,
          "acquired_at" => "2026-08-03T12:02:10+09:00",
          "released_at" => "2026-08-03T12:03:10+09:00"
        },
        "promotion_lease" => {
          "lease_id" => promotion_lease_id,
          "overall_owner" => promotion_owner,
          "acquired_at" => "2026-08-03T12:03:20+09:00",
          "released_at" => "2026-08-03T12:04:10+09:00"
        }
      },
      "routing_identity" => {
        "logical_role" => "worker",
        "worker_specialty" => stage_id == "edit_assembly_playback_qc" ? "stage_04" : (stage_id == "song_production_lock" ? "front_planning" : "front_planning"),
        "provider" => "codex",
        "logical_profile_alias" => "worker_high",
        "execution_profile_id" => "codex_worker_high",
        "resolved_provider_model" => "provider_snapshot_fixture",
        "reasoning_effort" => "high",
        "provider_capability_snapshot_sha256" => "0" * 64,
        "resolved_profile_snapshot_ref" => "RUN/work/provider-profile-snapshot.yaml#/worker_high",
        "session_topology" => "physical_native_session",
        "active_role_binding_id" => "ACTIVE-CDD-FIXTURE",
        "internal_subagent_policy" => "provider_native_default_no_logical_role_or_authority",
        "exact_task_subagent_override" => "none",
        "founder_visible" => false,
        "return_recipient_role" => recipient_role,
        "physical_transfer" => nil
      },
      "internal_delegation_summary" => {
        "provider_native_helpers_used" => false,
        "helper_count" => 0,
        "logical_roles_created" => 0,
        "canonical_owner_changed" => false,
        "founder_conversation_authority_granted" => false
      },
      "launch" => launch,
      "runtime_return" => runtime_return,
      "director_review" => review,
      "promotion" => promotion
    }
  end

  def dispatch_fixture_requirement_projection_line(requirement)
    payload = REQUIREMENT_PROJECTION_FIELDS.each_with_object({}) do |field, result|
      result[field] = requirement[field]
    end
    "#{REQUIREMENT_PROJECTION_PREFIX}#{JSON.generate(payload)}"
  end

  def dispatch_fixture_anti_flat_projection_line(value)
    "#{ANTI_FLAT_PROJECTION_PREFIX}#{JSON.generate('anti_flat_evidence_requirement' => value)}"
  end

  def dispatch_fixture_rendered_prompt(requirement_manifest: [], anti_flat_evidence_requirements: [])
    bodies = [
      "Bind the fixture dispatch, attempt, lineage, and provider-neutral role.",
      "Keep the registered role authority and review boundary.",
      "Resolve the current fixture gap from the bound source without reopening settled truth.",
      "Work only inside the declared fixture scope and paths.",
      "Inspect the exact bound source pointers and current byte hashes.",
      "Read and apply the selected registered Recipe and linked reads to EOF.",
      "Follow the Recipe and complete only the current fixture assignment delta.",
      "Return the declared bounded output with exact ownership and hashes.",
      "Show current-work evidence that the named fixture gap is resolved.",
      "Return only after structural, evidence, and review-ready checks pass.",
      "HOLD on missing bytes, stale bindings, authority conflict, or illegal scope expansion.",
      "Wake only the declared recipient with compact output pointers and hashes."
    ]
    Array(requirement_manifest).each do |requirement|
      next unless requirement.is_a?(Hash)

      block_index = case requirement["category"].to_s
                    when "founder" then 2
                    when "quality" then 8
                    else 6
                    end
      bodies[block_index] = [bodies.fetch(block_index), dispatch_fixture_requirement_projection_line(requirement)].join("\n")
    end
    Array(anti_flat_evidence_requirements).each do |requirement|
      bodies[8] = [bodies.fetch(8), dispatch_fixture_anti_flat_projection_line(requirement)].join("\n")
    end
    [GOAL_DIRECTIVE, LAUNCH_BLOCK_HEADINGS.zip(bodies).map { |heading, body| "#{heading}\n#{body}" }.join("\n\n")].join("\n\n")
  end

  def dispatch_fixture_append_recipe_rows!(requirements, profile_id:, checkpoint_id:, output:)
    IdolCheckpointClosureCatalog.recipe_rows(
      dispatch_fixture_root,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id
    ).each do |recipe|
      next if requirements.any? { |row| row["requirement_id"].to_s == recipe["requirement_id"].to_s }

      requirements << {
        "requirement_id" => recipe.fetch("requirement_id"),
        "category" => recipe.fetch("category"),
        "required" => true,
        "source_locator" => recipe.fetch("source_locator"),
        "source_binding" => {
          "path" => output.fetch("path"),
          "sha256" => output.fetch("sha256"),
          "role" => "checkpoint closure recipe evidence"
        },
        "affected_scope" => "The exact Front Planning / CDD readiness artifact for this checkpoint.",
        "expected_output_target" => recipe.fetch("expected"),
        "evidence_type" => recipe.fetch("evidence_type"),
        "director_semantic_review_required" => recipe.fetch("check_kind") == "director_judgment"
      }
    end
    requirements
  end

  def dispatch_fixture_root
    self.class.const_get(:ROOT)
  end

  def dispatch_fixture_file_sha(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def dispatch_fixture_structured_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(dispatch_fixture_canonicalize(value)))
  end

  def dispatch_fixture_canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = dispatch_fixture_canonicalize(value[original_key])
      end
    when Array
      value.map { |item| dispatch_fixture_canonicalize(item) }
    else
      value
    end
  end
end
