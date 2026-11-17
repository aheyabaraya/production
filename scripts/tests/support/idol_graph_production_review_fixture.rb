# frozen_string_literal: true

require_relative "../../lib/idol_graph_production_review_contract"

# Synthetic execution records for structural tests only; never live model/media proof.
module IdolGraphProductionReviewFixture
  module_function

  def build(root:, judgment_path:, directory:, review_stage:, pack_overrides: {}, separate_launch_goal_pointer: false)
    root = Pathname.new(root)
    directory = Pathname.new(directory)
    directory.mkpath
    contract = IdolGraphProductionReviewContract
    ptr = ->(path) { contract.pointer(root, path) }
    write = lambda do |name, value|
      path = directory.join(name)
      path.write(JSON.pretty_generate(value) + "\n")
      path
    end
    input = contract.project_input(root: root, judgment_pointer: ptr.call(judgment_path))
    input_path = write.call("review-input.json", input)
    input_pointer = ptr.call(input_path)
    input_digest = contract.digest(input)
    worker_pack = contract.document(root, input["worker_role_context_pack"], "test worker pack")
    reviewer = input.fetch("reviewer")
    role = contract.review_profile_role(reviewer["role"])
    logical_role = {"planning_cdd_p1" => "planning_cdd", "section_cluster_cdd_ci" => "section_cluster_cdd"}.fetch(role, role)
    session = reviewer["session_id"] || "INDEPENDENT_DIRECTOR_FIXTURE"
    provider, holds = IdolRoleContextPack.resolve_provider(root: root, role: role, provider: "grok", runtime_surface: "grok_build_cli_acp", logical_profile_alias: "frontier_director")
    raise holds.join("; ") unless holds.empty?
    goal_text = "Synthetic test of an exact independently returned review; not a live execution."
    goal = {
      "schema_version" => "idol-graph-provider-goal-terminal-event.v1",
      "artifact_type" => "graph_provider_goal_terminal_event", "evidence_class" => "provider_native_terminal_event",
      "provider" => "grok", "native_goal_id" => "GOAL_DIRECTOR_REVIEW_FIXTURE",
      "goal_text" => goal_text, "goal_text_sha256" => Digest::SHA256.hexdigest(goal_text),
      "goal_semantics" => "grok_goal_completed_admission", "terminal_state" => "complete", "last_event" => "goal_completed"
    }
    goal_path = write.call("director-goal.json", goal)
    goal_pointer = ptr.call(goal_path)
    output_path = directory.join("review-output.json")
    parent = {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"}
    dispatch = {
      "schema_version" => "idol-graph-department-dispatch.v1", "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => "DIRECTOR_REVIEW_FIXTURE", "run" => input.dig("scope", "run"),
      "lane_id" => reviewer["lane_id"], "section_cohort_id" => input.dig("scope", "section_cohort_id"),
      "section_ids" => input.dig("scope", "section_ids"), "logical_role" => logical_role,
      "assigned_owner" => reviewer["owner"],
      "output_writer" => {"owner" => reviewer["owner"], "role" => logical_role, "session_id" => session},
      "reviewer" => parent,
      "return_recipient" => parent.slice("owner", "role").merge("return_route" => "overall_reviewed_milestone"),
      "provider_binding" => {
        "registered_provider" => "grok", "runtime_surface" => provider["runtime_surface"],
        "logical_profile_alias" => provider["logical_profile_alias"], "execution_profile_id" => provider["provider_profile_id"],
        "resolved_provider_model" => provider["exact_model"], "reasoning_effort" => provider["reasoning_effort"],
        "provider_capability_snapshot_sha256" => provider["registry_sha256"],
        "fallback_allowed" => false, "silent_substitution_allowed" => false
      },
      "goal_evidence" => {
        "native_goal_id" => goal["native_goal_id"], "goal_text_sha256" => goal["goal_text_sha256"],
        "goal_semantics" => goal["goal_semantics"], "goal_terminal_state" => "complete", "goal_last_event" => "goal_completed",
        "goal_terminal_event_sha256" => goal_pointer["sha256"], "terminal_event" => goal_pointer
      },
      "input_digest_sha256" => input_digest,
      "bounded_output" => {"output_kind" => "production_director_review", "expected_paths" => [output_path.relative_path_from(root).to_s], "maximum_artifact_count" => 1},
      "judgment_profile_id" => input["profile_id"], "output_manifest" => nil,
      "stop_conditions" => ["stale_bound_input"], "lifecycle_state" => "launched", "legal_next" => %w[returned hold], "assignment_pass" => false
    }
    launch_dispatch = Marshal.load(Marshal.dump(dispatch))
    if separate_launch_goal_pointer
      launch_event = write.call("director-launch-goal.json", goal)
      launch_dispatch["goal_evidence"]["terminal_event"] = ptr.call(launch_event)
    end
    launched_path = write.call("director-launched.json", launch_dispatch)
    pack_arguments = {
      root: root, run_root: dispatch["run"], assignment_id: dispatch["dispatch_id"], role: role, profile_id: role,
      checkpoint_id: "exact_returned_work_review", stage_id: review_stage, section_ids: dispatch["section_ids"],
      source_envelope: ptr.call(launched_path).merge("kind" => "department_dispatch"), current_state: "launched",
      scope: {"stage_id" => review_stage, "section_ids" => dispatch["section_ids"]},
      authority: {"assigned_owner" => dispatch["assigned_owner"], "promotion_owner" => "overall_director"},
      founder_epoch: input.dig("founder_context", "decision_epoch"), founder_locks: input.dig("founder_context", "locks"),
      creative_sources: [contract.creative_source(input_pointer, role)], output_contract: dispatch["bounded_output"],
      hold_conditions: dispatch["stop_conditions"], return_recipient: dispatch["return_recipient"],
      provider: "grok", runtime_surface: "grok_build_cli_acp", writer: "graph_v2", run_class: "new_run",
      switch_receipt: worker_pack.dig("activation_binding", "switch_receipt")
    }
    pack = IdolRoleContextPack.build(**pack_arguments.merge(pack_overrides))
    pack_path = write.call("director-pack.json", pack)
    output = {
      "schema_version" => contract::VERSION, "artifact_type" => "graph_production_director_review_output",
      "review_input_manifest" => input_pointer, "review_input_digest_sha256" => input_digest,
      "role_context_pack" => ptr.call(pack_path), "reviewer_role" => reviewer["role"], "reviewer_session_id" => session,
      "inspected_artifacts" => input["inspection_targets"].map { |p| p.merge("observation" => "Synthetic provenance fixture; no actual creative quality assertion.") },
      "decision" => "accept", "findings" => "Synthetic review result for structural validation only.",
      "correction_requirements" => [], "automatic_creative_pass" => false
    }
    write.call("review-output.json", output)
    manifest = {
      "schema_version" => "idol-graph-output-manifest.v1", "artifact_type" => "graph_dispatch_output_manifest",
      "dispatch_id" => dispatch["dispatch_id"], "assigned_owner" => dispatch["assigned_owner"],
      "input_digest_sha256" => input_digest, "output_kind" => dispatch.dig("bounded_output", "output_kind"),
      "outputs" => [ptr.call(output_path)]
    }
    manifest_path = write.call("director-output-manifest.json", manifest)
    dispatch.merge!("lifecycle_state" => "returned", "lifecycle_from" => "launched", "legal_next" => %w[reviewed hold], "output_manifest" => ptr.call(manifest_path))
    returned_path = write.call("director-returned.json", dispatch)
    envelope = {
      "schema_version" => contract::VERSION, "artifact_type" => "graph_production_director_review",
      "review_input_manifest" => input_pointer, "review_input_digest_sha256" => input_digest,
      "director_dispatch" => ptr.call(returned_path), "role_context_pack" => ptr.call(pack_path), "review_output" => ptr.call(output_path)
    }
    envelope_path = write.call("review-envelope.json", envelope)
    {"envelope_path" => envelope_path, "input_path" => input_path, "output_path" => output_path,
     "pack_path" => pack_path, "launched_path" => launched_path, "returned_path" => returned_path,
     "manifest_path" => manifest_path, "input" => input, "output" => output, "envelope" => envelope}
  end
end
