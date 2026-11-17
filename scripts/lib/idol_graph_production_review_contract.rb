# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "idol_graph_criterion_evidence_contract"
require_relative "idol_graph_output_manifest_contract"
require_relative "idol_graph_provider_binding_contract"
require_relative "idol_graph_goal_evidence_contract"
require_relative "idol_role_context_pack"

# Copies exact review inputs and verifies an independently returned review.
# The assigned Director writes every observation, decision and correction.
module IdolGraphProductionReviewContract
  class ContractError < StandardError; end

  VERSION = "idol-graph-production-review.v1"
  IMPLEMENTATION_ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SOURCE_ID = "graph_production_review_input"
  SOURCE_FUNCTION = "exact_director_review_input"
  SOURCE_PURPOSE = "Exact production Director review input bytes."
  STABLE_DISPATCH_FIELDS = %w[
    dispatch_id run lane_id section_cohort_id section_ids logical_role assigned_owner
    output_writer reviewer return_recipient provider_binding
    input_digest_sha256 bounded_output judgment_profile_id stop_conditions
  ].freeze
  STABLE_GOAL_FIELDS = %w[native_goal_id goal_text_sha256 goal_semantics].freeze

  module_function

  def check!(condition, message)
    raise ContractError, message unless condition
  end

  def digest(value)
    IdolGraphCriterionEvidenceContract.value_sha256(value)
  end

  # Dispatch, context profile and graph topology use different historical names
  # for the same cohort Director. These are role aliases, never owner IDs.
  def review_profile_role(role)
    %w[creative_development_director section_cluster_cdd].include?(role) ? "section_cluster_cdd_ci" : role
  end

  def review_graph_role(role)
    review_profile_role(role) == "section_cluster_cdd_ci" ? "section_cluster_cdd" : role
  end

  def pointer(root, path)
    root = Pathname.new(root).expand_path
    path = Pathname.new(path)
    path = root.join(path) unless path.absolute?
    relative = path.relative_path_from(root).to_s
    exact = IdolGraphCriterionEvidenceContract.exact_file(root, relative)
    {"path" => relative, "sha256" => Digest::SHA256.file(exact).hexdigest}
  rescue IdolGraphCriterionEvidenceContract::ContractError => e
    raise ContractError, e.message
  end

  def exact_file(root, ref, label)
    check!(ref.is_a?(Hash), "#{label} pointer is missing")
    path = IdolGraphCriterionEvidenceContract.exact_file(root, ref["path"])
    check!(Digest::SHA256.file(path).hexdigest == ref["sha256"], "#{label} SHA-256 is stale")
    path
  rescue IdolGraphCriterionEvidenceContract::ContractError => e
    raise ContractError, "#{label}: #{e.message}"
  end

  def document(root, ref, label)
    path = exact_file(root, ref, label)
    value = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, aliases: true)
    check!(value.is_a?(Hash), "#{label} must be an object")
    value
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError, "#{label} cannot parse: #{e.message}"
  end

  def run_validator!(root, script, path, *arguments)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, IMPLEMENTATION_ROOT.join("scripts", script).to_s,
      "--root", root.to_s, *arguments, path.to_s, chdir: root.to_s
    )
    check!(status.success?, "#{script}: #{[stderr, stdout].join(' ').strip}")
  end

  def schema!(root, path)
    stdout, stderr, status = Open3.capture3(
      IMPLEMENTATION_ROOT.join("scripts", "idol-video-python").to_s,
      IMPLEMENTATION_ROOT.join("scripts", "validate_json_schema.py").to_s,
      IMPLEMENTATION_ROOT.join("schemas", "graph-production-review.schema.json").to_s,
      path.to_s, chdir: root.to_s
    )
    check!(status.success?, "production review schema: #{[stderr, stdout].join(' ').strip}")
  end

  def project_input(root:, judgment_pointer:)
    root = Pathname.new(root).expand_path
    judgment_path = exact_file(root, judgment_pointer, "contextual judgment")
    run_validator!(root, "validate_graph_contextual_judgment.rb", judgment_path)
    judgment = document(root, judgment_pointer, "contextual judgment")
    binding = judgment.fetch("execution_binding")
    dispatch = document(root, binding["dispatch"], "worker returned Dispatch")
    check!(dispatch["lifecycle_state"] == "returned", "review input requires an immutable returned worker Dispatch")
    pack = document(root, binding["role_context_pack"], "worker Role Context Pack")
    manifest = IdolGraphOutputManifestContract.verify!(root: root, pointer: binding["output_manifest"], dispatch: dispatch)
    sources = Array(judgment["source_artifacts"]).map { |ref| ref.slice("path", "sha256") }
    selected_context = Array(pack["creative_source_pointers"])
    selected_context.each { |ref| exact_file(root, ref, "selected context") }
    cut_pixels = []
    if judgment["profile_id"].to_s == "pixel_02b"
      raw_manifest = document(root, binding["output_manifest"], "output manifest")
      cut_pixels = IdolGraphCriterionEvidenceContract.expected_cut_images_from_authentic_manifest(
        root: root,
        manifest: raw_manifest,
        section_ids: dispatch["section_ids"]
      )
    end
    # The source pack already excludes raw pools/transcripts. Keep its selected handles,
    # exact locks, scope and correction/neighbor references; do not copy broad instructions.
    {
      "schema_version" => VERSION,
      "artifact_type" => "graph_production_review_input",
      "contextual_judgment" => judgment_pointer.slice("path", "sha256"),
      "worker_dispatch" => binding.fetch("dispatch").slice("path", "sha256"),
      "worker_role_context_pack" => binding.fetch("role_context_pack").slice("path", "sha256"),
      "profile_id" => judgment.fetch("profile_id"),
      "profile_release" => binding.fetch("profile_release").slice("path", "sha256"),
      "profile_value_sha256" => binding.fetch("profile_value_sha256"),
      "output_manifest" => binding.fetch("output_manifest").slice("path", "sha256"),
      "candidate_outputs" => manifest.fetch("outputs"),
      "inspection_targets" => (manifest.fetch("outputs") + sources + cut_pixels).uniq,
      "criterion_evidence" => Array(judgment["criteria"]).map { |row| row.slice("criterion_id", "evidence_locator") },
      "hard_gate_evidence" => Array(judgment["hard_gate_findings"]).map { |row| row.slice("finding_id", "evidence_locator") },
      "scope" => {
        "run" => dispatch.fetch("run"), "section_ids" => dispatch.fetch("section_ids"),
        "section_cohort_id" => dispatch["section_cohort_id"],
        "stage_id" => judgment.fetch("stage_id"), "checkpoint_id" => judgment.fetch("checkpoint_id"),
        "scope_id" => judgment.fetch("scope_id")
      },
      "reviewer" => dispatch.fetch("reviewer"),
      "author_session_id" => binding.fetch("author_session_id"),
      "founder_context" => pack.fetch("founder_context"),
      "authority_binding" => pack.fetch("authority_binding"),
      "node_context" => pack.fetch("current_node").slice("scope", "non_scope", "stop_conditions"),
      "selected_context_sources" => selected_context,
      "authority" => "derived_review_input_no_creative_or_promotion_authority"
    }
  rescue KeyError, IdolGraphOutputManifestContract::ContractError, IdolGraphCriterionEvidenceContract::ContractError => e
    raise ContractError, "production review input: #{e.message}"
  end

  def creative_source(input_pointer, role)
    {
      "source_id" => SOURCE_ID, "path" => input_pointer.fetch("path"), "sha256" => input_pointer.fetch("sha256"),
      "purpose" => SOURCE_PURPOSE, "locator" => "/", "function" => SOURCE_FUNCTION,
      "role_groups" => [role], "disposition" => "applied"
    }
  end

  def verify!(root:, review_pointer:, expected_judgment: nil, expected_output: nil)
    root = Pathname.new(root).expand_path
    review_path = exact_file(root, review_pointer, "Director review envelope")
    schema!(root, review_path)
    review = document(root, review_pointer, "Director review envelope")
    check!(review["artifact_type"] == "graph_production_director_review", "Director review envelope type differs")
    input = document(root, review["review_input_manifest"], "Director review input")
    expected = project_input(root: root, judgment_pointer: input["contextual_judgment"])
    check!(input == expected, "Director review input differs from the exact projected worker sources")
    check!(review["review_input_digest_sha256"] == digest(input), "Director review input digest is stale")
    if expected_judgment
      check!(input["contextual_judgment"] == expected_judgment.slice("path", "sha256"), "Director review covers a different contextual judgment")
    end
    if expected_output
      check!(input["candidate_outputs"].include?(expected_output.slice("path", "sha256")), "Director review does not cover the promoted output")
    end

    dispatch_path = exact_file(root, review["director_dispatch"], "Director returned Dispatch")
    run_validator!(root, "validate_graph_director_lineage.rb", dispatch_path)
    dispatch = document(root, review["director_dispatch"], "Director returned Dispatch")
    check!(dispatch["lifecycle_state"] == "returned", "Director review requires a returned Dispatch, not a launched claim")
    assigned = input.fetch("reviewer")
    check!(dispatch["assigned_owner"] == assigned["owner"], "Director review writer is not the assigned reviewer")
    check!(dispatch["lane_id"] == assigned["lane_id"], "Director review lane differs from assigned reviewer")
    check!(dispatch["section_ids"] == input.dig("scope", "section_ids"), "Director review section scope differs")
    check!(dispatch["run"] == input.dig("scope", "run"), "Director review run differs")
    check!(dispatch["section_cohort_id"] == input.dig("scope", "section_cohort_id"), "Director review cohort differs")
    check!(dispatch["judgment_profile_id"] == input["profile_id"], "Director review judgment profile differs")
    check!(dispatch["input_digest_sha256"] == digest(input), "Director Dispatch does not bind its exact review input")
    expected_role = review_profile_role(assigned["role"])
    expected_logical_role = {"planning_cdd_p1" => "planning_cdd", "section_cluster_cdd_ci" => "section_cluster_cdd"}.fetch(expected_role, expected_role)
    check!(dispatch["logical_role"] == expected_logical_role, "Director Dispatch role differs from the assigned reviewer")
    check!(dispatch.dig("output_writer", "role") == expected_logical_role &&
           dispatch.dig("output_writer", "owner") == assigned["owner"], "Director output writer differs from the assigned reviewer")
    session = dispatch.dig("output_writer", "session_id")
    check!(!session.to_s.empty? && session != input["author_session_id"], "Director review must use an independent session")
    if assigned["session_id"]
      check!(session == assigned["session_id"], "Director review session differs from the assigned reviewer")
    end

    pack = document(root, review["role_context_pack"], "Director Role Context Pack")
    check!(pack["status"] == "pass" && Array(pack["hold_reasons"]).empty?, "Director Role Context Pack has unresolved holds")
    pack_errors = IdolRoleContextPack.validate_pack(root: root, pack: pack)
    check!(pack_errors.empty?, "Director Role Context Pack: #{pack_errors.join('; ')}")
    check!(pack.dig("identity", "assignment_id") == dispatch["dispatch_id"], "Director pack belongs to a different assignment")
    check!(pack.dig("identity", "run_root") == dispatch["run"], "Director pack belongs to a different run")
    check!(pack.dig("identity", "section_ids") == dispatch["section_ids"], "Director pack section scope differs from its Dispatch")
    check!(pack.dig("identity", "checkpoint_id") == "exact_returned_work_review", "Director pack must use the exact returned-work review checkpoint")
    check!(pack.dig("current_node", "state") == "launched", "Director pack must be projected before its return")
    check!(pack.dig("identity", "role") == expected_role, "Director pack role differs from the assigned review role")
    check!(pack.dig("authority_binding", "assigned_owner") == assigned["owner"], "Director pack authority differs from the assigned reviewer")
    check!(pack["output_contract"] == dispatch["bounded_output"], "Director pack output contract differs from its Dispatch")
    check!(pack.dig("current_node", "return_recipient") == dispatch["return_recipient"], "Director pack return recipient differs from its Dispatch")
    check!(pack.dig("current_node", "stop_conditions") == dispatch["stop_conditions"], "Director pack stop conditions differ from its Dispatch")
    check!(pack["creative_source_pointers"] == [creative_source(review["review_input_manifest"], expected_role)], "Director pack must contain only its exact review input projection")
    check!(pack["founder_context"] == input["founder_context"], "Director pack must preserve the exact Founder epoch and locks")
    check!(pack.dig("source_envelope", "kind") == "department_dispatch", "Director pack source must be a Department Dispatch")
    launched = document(root, pack["source_envelope"], "Director launch Dispatch")
    check!(launched["lifecycle_state"] == "launched", "Director pack source is not a launched Dispatch")
    check!(launched.slice(*STABLE_DISPATCH_FIELDS) == dispatch.slice(*STABLE_DISPATCH_FIELDS), "Director launch/return identity differs")
    # The return's terminal receipt is verified above by the lineage validator.
    # Its locator can change while the assigned Goal identity stays fixed.
    check!(launched.fetch("goal_evidence").slice(*STABLE_GOAL_FIELDS) ==
           dispatch.fetch("goal_evidence").slice(*STABLE_GOAL_FIELDS), "Director launch/return Goal identity differs")
    check!(pack.dig("provider_binding", "logical_profile_alias") == "frontier_director", "Director review requires the registered frontier profile")
    resolved = IdolGraphProviderBindingContract.resolve!(root: root, binding: dispatch["provider_binding"], studio_role: dispatch["logical_role"])
    %w[reasoning_effort runtime_surface].each do |field|
      check!(pack.dig("provider_binding", field) == resolved[field], "Director pack provider #{field} differs")
    end
    check!(pack.dig("provider_binding", "exact_model") == resolved["resolved_provider_model"], "Director pack model differs")
    check!(pack.dig("provider_binding", "registry_sha256") == resolved["provider_capability_snapshot_sha256"], "Director pack provider snapshot differs")

    manifest = IdolGraphOutputManifestContract.verify!(root: root, pointer: dispatch["output_manifest"], dispatch: dispatch)
    output_path = exact_file(root, review["review_output"], "Director review output")
    schema!(root, output_path)
    output = document(root, review["review_output"], "Director review output")
    check!(manifest.fetch("outputs").include?(review["review_output"].slice("path", "sha256")), "Director output manifest does not bind the actual review bytes")
    expected_fields = {
      "artifact_type" => "graph_production_director_review_output",
      "review_input_manifest" => review["review_input_manifest"],
      "review_input_digest_sha256" => digest(input), "role_context_pack" => review["role_context_pack"],
      "reviewer_role" => assigned["role"], "reviewer_session_id" => session
    }
    check!(output.slice(*expected_fields.keys) == expected_fields, "Director output does not bind the assigned execution and review input")
    inspected = output.fetch("inspected_artifacts").map { |row| row.slice("path", "sha256") }
    check!(inspected.uniq.length == inspected.length && (input["inspection_targets"] - inspected).empty?, "Director output omits exact inspection targets")
    check!((inspected - input["inspection_targets"]).empty?, "Director output contains unrelated inspection targets")
    inspected.each { |ref| exact_file(root, ref, "Director inspected artifact") }
    {"input" => input, "output" => output, "review_input_digest_sha256" => digest(input), "result_digest_sha256" => digest(output)}
  rescue KeyError, IdolRoleContextPack::ContractError, IdolGraphOutputManifestContract::ContractError,
         IdolGraphProviderBindingContract::ContractError => e
    raise ContractError, "production Director review: #{e.message}"
  end
end
