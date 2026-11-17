#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_SUITE = ROOT.join("automation", "harness-shadow-eval-suite.yaml")
PROFILE_DESCRIPTOR_FIELDS = %w[
  model_family
  model_id
  agent_name
  model_reasoning_effort
  effort_policy
  model_verbosity
  execution_surface
  harness_variant
  profile_role
].freeze
OPERATIONAL_DESCRIPTOR_FIELDS = %w[
  model_id
  agent_name
  model_reasoning_effort
  effort_policy
  model_verbosity
  execution_surface
  harness_variant
].freeze
ARTIFACT_REF_FIELDS = %w[path sha256].freeze
RESULT_FIELDS = %w[
  schema_version
  profile_label
  profile_descriptor
  harness_commit
  harness_snapshot
  source_snapshot
  task_set
  artifact_root
  profile_execution_manifest
  reviewer
  case_results
].freeze
CASE_RESULT_FIELDS = %w[
  case_id
  stage_id
  artifacts
  required_evidence
  hard_gates
  quality_scores
  evidence_counts
  efficiency
  agent_usage
  review_note
].freeze
AGENT_USAGE_FIELDS = %w[
  agent_path
  parent_agent_path
  agent_name
  model_id
  model_reasoning_effort
  model_verbosity
  route_id
  input_tokens
  output_tokens
  wall_seconds
  tool_calls
  retries
  status
].freeze
CANONICAL_DESCRIPTOR_PATTERN = /\A[a-z0-9]+(?:[._-][a-z0-9]+)*\z/
RUNTIME_AGENT_PATH_PATTERN = %r{\A/root(?:/[a-z0-9][a-z0-9_-]*)?\z}
MODEL_ID_PATTERN = /\Agpt-5\.6(?:[-._:\/][a-z0-9][a-z0-9._:\/-]*)?\z/
GIT_COMMIT_PATTERN = /\A[a-f0-9]{7,40}\z/
EXECUTION_MANIFEST_SCHEMA_VERSION = "idol-harness-shadow-profile-execution-manifest.v3"
EXECUTION_MANIFEST_FIELDS = %w[
  schema_version profile_label profile_descriptor harness_commit
  harness_snapshot_sha256 source_snapshot_sha256 task_set_sha256
  case_artifact_manifest_sha256 case_agent_usage_sha256
].freeze
ROUTING_POLICY_ID = "provider_registry_adaptive_runtime_v31"
SHADOW_CLOSEOUT_SCHEMA_VERSION = "idol_harness_maintenance_evidence.v1"
SHADOW_CLOSEOUT_SCOPE = "read_only_v31_shadow_closeout"
SHADOW_CLOSEOUT_CANONICAL_INPUTS = {
  "front_planning_readiness" => "research/front-planning-readiness-v12.yaml",
  "founder_review_board_manifest" => "review/manifests/front-planning-reauthor-v3.yaml",
  "run_manifest" => "run-manifest.yaml"
}.freeze
SHADOW_CLOSEOUT_DOWNSTREAM_ARTIFACTS = {
  "01" => "01-song-choreography-performance-mv-map.yaml",
  "02A" => "02A-master-storyboard.yaml"
}.freeze
ROUTING_POLICY_FIELDS = %w[
  policy_id
  automatic_lower_effort_allowed
  activation_contract
  effort_policy
  capability_check
  agent_governance
  routing_continuity_contract
  model_routes
  route_classes
].freeze
MODEL_ROUTE_FIELDS = %w[
  model_id
  role
  agent_profiles
].freeze
AGENT_PROFILE_FIELDS = %w[
  agent_name
  model_reasoning_effort
  model_verbosity
  tier_from_ceiling
].freeze
ROUTE_CLASS_FIELDS = %w[
  route_id
  purpose
  default_route
  explicit_alternatives
  default_selection_basis
  escalation_triggers
  output_authority
  owner_review_required_for_canonical_write
].freeze
ROUTE_DESCRIPTOR_FIELDS = %w[agent_name model_id model_reasoning_effort model_verbosity].freeze
AGENT_GOVERNANCE_FIELDS = %w[
  project_config_path
  agents_directory
  provider_native_helper_availability
  project_numeric_gate
  depth_gate
  physical_session_selection
  internal_and_physical_active_owner_overlap
  session_root_profile_source
  project_root_model_pin_allowed
  canonical_creative_authority_agent
  final_validation_agent
  root_canonical_write_executor
  session_root_model_authority
  canonical_write_exception_agent_names
  canonical_write_exception_paths
  read_only_agent_names
  no_nested_worker_delegation
  grok_worker_session_governance
].freeze
GROK_PROVIDER_BINDING = {
  "logical_profile_alias" => "worker_high",
  "provider_registry_path" => "automation/harness-provider-profile-registry.yaml",
  "provider_profile_source" => "automation/providers/grok-build-profiles.yaml",
  "fallback_policy" => "forbidden"
}.freeze
REGISTERED_MEDIA_GENERATION_HANDOFFS = [
  {
    "stage_id" => "branch_cut_generation",
    "action_scope" => "02b_image_generation_execution",
    "route" => "existing_registered_image_generation_lane",
    "nonmedia_provider_ownership" => false,
    "fallback_counted" => false
  },
  {
    "stage_id" => "video_motion_direction",
    "action_scope" => "03v_video_generation_execution_only",
    "route" => "existing_registered_video_generation_lane",
    "nonmedia_provider_ownership" => false,
    "fallback_counted" => false
  }
].freeze
SUPPORTED_MODEL_IDS = %w[gpt-5.6-sol gpt-5.6-luna gpt-5.6-terra].freeze
AGENT_PROFILES = {
  "idol_sol_creative_synthesis" => {
    "model_id" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high", "tier" => "general"
  },
  "idol_sol_creative_development_director" => {
    "model_id" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high", "tier" => "general"
  },
  "idol_sol_edit_director" => {
    "model_id" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high", "tier" => "general"
  },
  "idol_sol_primary_validation" => {
    "model_id" => "gpt-5.6-sol", "effort" => "max", "verbosity" => "high", "tier" => "whole_flow"
  },
  "idol_sol_bounded_synthesis" => {
    "model_id" => "gpt-5.6-sol", "effort" => "max", "verbosity" => "high", "tier" => "one_step_below_ceiling"
  },
  "idol_sol_complete_full_flow" => {
    "model_id" => "gpt-5.6-sol", "effort" => "ultra", "verbosity" => "high", "tier" => "ceiling"
  },
  "idol_terra_weekly_idol_research" => {
    "model_id" => "gpt-5.6-terra", "effort" => "xhigh", "verbosity" => "high", "tier" => "general"
  },
  "idol_terra_routine_judgment" => {
    "model_id" => "gpt-5.6-terra", "effort" => "xhigh", "verbosity" => "high", "tier" => "general"
  },
  "idol_luna_section_image_motion" => {
    "model_id" => "gpt-5.6-luna", "effort" => "max", "verbosity" => "high", "tier" => "general"
  },
  "idol_luna_studio_department" => {
    "model_id" => "gpt-5.6-luna", "effort" => "max", "verbosity" => "high", "tier" => "general"
  },
  "idol_terra_direction_scout" => {
    "model_id" => "gpt-5.6-terra", "effort" => "xhigh", "verbosity" => "high", "tier" => "general"
  }
}.freeze
ULTRA_ALLOWED_ESCALATION_TRIGGERS_BY_AGENT = {
  "idol_sol_complete_full_flow" => %w[founder_explicit_ultra_complete_full_flow_locked_front_planning]
}.freeze

def routing_policy(suite)
  suite.dig("operator_profile_policy", "routing_policy")
end

def route_class_for(suite, route_id)
  policy = routing_policy(suite)
  return nil unless policy.is_a?(Hash)

  Array(policy["route_classes"]).find { |row| row.is_a?(Hash) && row["route_id"].to_s == route_id.to_s }
end

def agent_profile_for(suite, agent_name)
  Array(routing_policy(suite)&.fetch("model_routes", nil)).each do |model_route|
    next unless model_route.is_a?(Hash)

    profile = Array(model_route["agent_profiles"]).find do |candidate|
      candidate.is_a?(Hash) && candidate["agent_name"].to_s == agent_name.to_s
    end
    next unless profile

    return profile.merge("model_id" => model_route["model_id"].to_s)
  end
  nil
end

def route_descriptor_tuple(route)
  source = route.is_a?(Hash) ? route : {}
  ROUTE_DESCRIPTOR_FIELDS.map { |field| source[field].to_s }
end

def route_descriptor_allowed?(suite, route)
  agent_name, model_id, effort, verbosity = route_descriptor_tuple(route)
  profile = agent_profile_for(suite, agent_name)
  profile.is_a?(Hash) &&
    SUPPORTED_MODEL_IDS.include?(model_id) &&
    profile["model_id"].to_s == model_id &&
    profile["model_reasoning_effort"].to_s == effort &&
    profile["model_verbosity"].to_s == verbosity
end

def route_descriptor_allowed_for_route?(suite, route_id, descriptor)
  route_class = route_class_for(suite, route_id)
  return false unless route_class

  [route_class["default_route"], *Array(route_class["explicit_alternatives"])].any? do |route|
    route_descriptor_allowed?(suite, route) && route_descriptor_tuple(route) == route_descriptor_tuple(descriptor)
  end
end

def load_doc(path)
  YAML.safe_load(Pathname.new(path).read, aliases: true) || {}
rescue Psych::SyntaxError => e
  raise "parse error in #{path}: #{e.message}"
end

def percent_change(before, after)
  return nil unless before.to_f.positive?

  ((after.to_f - before.to_f) / before.to_f) * 100.0
end

def weighted_quality(row, dimensions)
  scores = row["quality_scores"].is_a?(Hash) ? row["quality_scores"] : {}
  weight_sum = dimensions.values.map(&:to_f).sum
  return 0.0 unless weight_sum.positive?

  dimensions.sum { |id, weight| scores[id].to_f * weight.to_f } / weight_sum
end

def normalized_descriptor(descriptor, fields = PROFILE_DESCRIPTOR_FIELDS)
  source = descriptor.is_a?(Hash) ? descriptor : {}
  fields.to_h { |field| [field, source[field].to_s.strip] }
end

def normalized_operational_descriptor(descriptor)
  normalized_descriptor(descriptor, OPERATIONAL_DESCRIPTOR_FIELDS)
    .transform_values { |value| value.downcase }
end

def resolve_ledger_path(raw_path, ledger_path)
  path = Pathname.new(raw_path.to_s)
  path = Pathname.new(ledger_path).expand_path.dirname.join(path) unless path.absolute?
  path.expand_path
end

def canonical_existing_path(path)
  Pathname.new(path).realpath
rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
  Pathname.new(path).expand_path
end

def path_within_root?(path, root)
  path_value = canonical_existing_path(path).to_s
  root_value = canonical_existing_path(root).to_s
  path_value.start_with?("#{root_value}#{File::SEPARATOR}")
end

def validate_artifact_ref(ref, label:, ledger_path:, required_root: nil)
  errors = []
  unless ref.is_a?(Hash)
    return [errors << "#{label} must be an artifact ref object", nil]
  end

  unknown_fields = ref.keys.map(&:to_s) - ARTIFACT_REF_FIELDS
  errors << "#{label} has unknown fields: #{unknown_fields.join(',')}" unless unknown_fields.empty?
  path_value = ref["path"]
  sha_value = ref["sha256"]
  errors << "#{label}.path must be a non-empty string" unless path_value.is_a?(String) && !path_value.strip.empty?
  errors << "#{label}.sha256 must be a lowercase SHA-256 digest" unless sha_value.is_a?(String) && sha_value.match?(/\A[a-f0-9]{64}\z/)
  return [errors, nil] if path_value.to_s.strip.empty?

  resolved = resolve_ledger_path(path_value, ledger_path)
  unless resolved.file? && resolved.readable?
    errors << "#{label}.path is not a readable file: #{resolved}"
    return [errors, resolved]
  end
  if required_root && !path_within_root?(resolved, required_root)
    errors << "#{label}.path must stay under artifact_root: #{resolved}"
  end
  if sha_value.to_s.match?(/\A[a-f0-9]{64}\z/)
    actual_sha = Digest::SHA256.file(resolved).hexdigest
    errors << "#{label}.sha256 mismatch for #{resolved}" unless actual_sha == sha_value
  end
  [errors, resolved]
rescue ArgumentError, Errno::ENOENT, Errno::EACCES => e
  [errors << "#{label}.path is invalid: #{e.message}", nil]
end

def validate_artifact_root(raw_root, ledger_path)
  unless raw_root.is_a?(String) && !raw_root.strip.empty?
    return [["artifact_root must be a non-empty string"], nil]
  end

  root = resolve_ledger_path(raw_root, ledger_path)
  errors = []
  errors << "artifact_root is not a readable directory: #{root}" unless root.directory? && root.readable?
  [errors, root]
rescue ArgumentError => e
  [["artifact_root is invalid: #{e.message}"], nil]
end

def validate_execution_manifest(path, result)
  return [] unless path&.file?

  manifest = load_doc(path)
  return ["profile_execution_manifest must contain an object"] unless manifest.is_a?(Hash)

  errors = []
  unknown_fields = manifest.keys.map(&:to_s) - EXECUTION_MANIFEST_FIELDS
  errors << "profile_execution_manifest has unknown fields: #{unknown_fields.join(',')}" unless unknown_fields.empty?
  unless manifest["schema_version"].to_s == EXECUTION_MANIFEST_SCHEMA_VERSION
    errors << "profile_execution_manifest.schema_version must be #{EXECUTION_MANIFEST_SCHEMA_VERSION}"
  end
  errors << "profile_execution_manifest.profile_label does not match ledger" unless manifest["profile_label"] == result["profile_label"]
  errors << "profile_execution_manifest.harness_commit does not match ledger" unless manifest["harness_commit"] == result["harness_commit"]
  unless manifest["harness_snapshot_sha256"] == artifact_ref_sha(result["harness_snapshot"])
    errors << "profile_execution_manifest.harness_snapshot_sha256 does not match ledger"
  end
  unless manifest["profile_descriptor"] == result["profile_descriptor"]
    errors << "profile_execution_manifest.profile_descriptor does not match ledger"
  end
  unless manifest["source_snapshot_sha256"] == artifact_ref_sha(result["source_snapshot"])
    errors << "profile_execution_manifest.source_snapshot_sha256 does not match ledger"
  end
  unless manifest["task_set_sha256"] == artifact_ref_sha(result["task_set"])
    errors << "profile_execution_manifest.task_set_sha256 does not match ledger"
  end
  unless manifest["case_artifact_manifest_sha256"] == case_artifact_manifest_sha256(result)
    errors << "profile_execution_manifest.case_artifact_manifest_sha256 does not match ledger"
  end
  unless manifest["case_agent_usage_sha256"] == case_agent_usage_sha256(result)
    errors << "profile_execution_manifest.case_agent_usage_sha256 does not match ledger"
  end
  errors
rescue RuntimeError, Errno::ENOENT, Errno::EACCES => e
  ["profile_execution_manifest could not be read: #{e.message}"]
end

def descriptor_summary(descriptor)
  value = normalized_descriptor(descriptor)
  "#{value['agent_name']} / #{value['model_id']} / reasoning=#{value['model_reasoning_effort']} / verbosity=#{value['model_verbosity']} / surface=#{value['execution_surface']} / graph_engineering=#{value['harness_variant']}"
end

def resolved_case_artifact_paths(result, ledger_path)
  Array(result["case_results"]).flat_map do |row|
    next [] unless row.is_a?(Hash)

    Array(row["artifacts"]).each_with_object([]) do |ref, paths|
      next unless ref.is_a?(Hash) && ref["path"].is_a?(String)

      begin
        paths << canonical_existing_path(resolve_ledger_path(ref["path"], ledger_path)).to_s
      rescue ArgumentError
        next
      end
    end
  end
end

def artifact_ref_sha(ref)
  ref.is_a?(Hash) ? ref["sha256"].to_s : ""
end

def canonical_json_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.to_h do |key|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      [key, canonical_json_value(value[source_key])]
    end
  when Array
    value.map { |entry| canonical_json_value(entry) }
  else
    value
  end
end

def canonical_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(value)))
end

def case_artifact_manifest(result)
  Array(result["case_results"]).each_with_object([]) do |row, manifest|
    next unless row.is_a?(Hash)

    manifest << {
      "case_id" => row["case_id"].to_s,
      "artifacts" => Array(row["artifacts"]).map do |ref|
        ref.is_a?(Hash) ? {"path" => ref["path"].to_s, "sha256" => ref["sha256"].to_s} : ref
      end
    }
  end.sort_by { |row| row["case_id"] }
end

def case_artifact_manifest_sha256(result)
  canonical_sha256(case_artifact_manifest(result))
end

def case_agent_usage_manifest(result)
  Array(result["case_results"]).each_with_object([]) do |row, manifest|
    next unless row.is_a?(Hash)

    manifest << {"case_id" => row["case_id"].to_s, "agent_usage" => Array(row["agent_usage"])}
  end.sort_by { |row| row["case_id"] }
end

def case_agent_usage_sha256(result)
  canonical_sha256(case_agent_usage_manifest(result))
end

def validate_case_agent_usage(case_id, row, suite, expected_route_id)
  errors = []
  usage = row["agent_usage"]
  unless usage.is_a?(Array) && !usage.empty? && usage.length <= 5
    return ["#{case_id}: agent_usage must contain 1-5 direct-thread rows"]
  end
  paths = usage.each_with_object([]) do |entry, values|
    values << entry["agent_path"].to_s if entry.is_a?(Hash)
  end
  errors << "#{case_id}: agent_usage agent paths must be unique" unless paths.uniq.length == paths.length
  usage.each_with_index do |entry, index|
    unless entry.is_a?(Hash)
      errors << "#{case_id}: agent_usage[#{index}] must be an object"
      next
    end
    unknown_fields = entry.keys.map(&:to_s) - AGENT_USAGE_FIELDS
    errors << "#{case_id}: agent_usage[#{index}] has unknown fields: #{unknown_fields.join(',')}" unless unknown_fields.empty?
    path = entry["agent_path"].to_s
    errors << "#{case_id}: agent_usage[#{index}].agent_path must be /root or one direct child" unless path.match?(RUNTIME_AGENT_PATH_PATTERN)
    if path == "/root"
      errors << "#{case_id}: root usage parent_agent_path must be null" unless entry["parent_agent_path"].nil?
    else
      errors << "#{case_id}: direct child parent_agent_path must be /root" unless entry["parent_agent_path"] == "/root"
    end
    descriptor = {
      "agent_name" => entry["agent_name"],
      "model_id" => entry["model_id"],
      "model_reasoning_effort" => entry["model_reasoning_effort"],
      "model_verbosity" => entry["model_verbosity"]
    }
    route_id = entry["route_id"].to_s
    errors << "#{case_id}: agent_usage[#{index}].route_id must use canonical lowercase descriptor syntax" unless route_id.match?(CANONICAL_DESCRIPTOR_PATTERN)
    unless route_descriptor_allowed_for_route?(suite, route_id, descriptor)
      errors << "#{case_id}: agent_usage[#{index}] uses a model/agent/effort/verbosity tuple not allowed by route #{route_id.inspect}"
    end
    unless route_id == expected_route_id.to_s
      errors << "#{case_id}: agent_usage[#{index}].route_id must match suite case route #{expected_route_id.inspect}"
    end
    errors << "#{case_id}: agent_usage[#{index}].status must be completed" unless entry["status"] == "completed"
    %w[input_tokens output_tokens tool_calls retries].each do |field|
      value = entry[field]
      errors << "#{case_id}: agent_usage[#{index}].#{field} must be a non-negative integer" unless value.is_a?(Integer) && value >= 0
    end
    wall_seconds = entry["wall_seconds"]
    errors << "#{case_id}: agent_usage[#{index}].wall_seconds must be positive" unless wall_seconds.is_a?(Numeric) && wall_seconds.positive?
  end
  efficiency = row["efficiency"].is_a?(Hash) ? row["efficiency"] : {}
  %w[input_tokens output_tokens tool_calls retries].each do |field|
    sum = usage.sum { |entry| entry.is_a?(Hash) ? entry[field].to_i : 0 }
    errors << "#{case_id}: efficiency.#{field} must equal summed agent_usage" unless efficiency[field].to_i == sum
  end
  max_agent_wall = usage.each_with_object([]) do |entry, values|
    values << entry["wall_seconds"].to_f if entry.is_a?(Hash) && entry["wall_seconds"].is_a?(Numeric)
  end.max.to_f
  if efficiency["wall_seconds"].to_f < max_agent_wall
    errors << "#{case_id}: efficiency.wall_seconds cannot be shorter than every agent run"
  end
  errors
end

def local_git_commit?(commit)
  return false unless commit.is_a?(String) && commit.match?(GIT_COMMIT_PATTERN)

  _stdout, _stderr, status = Open3.capture3(
    "git",
    "-C",
    ROOT.to_s,
    "cat-file",
    "-e",
    "#{commit}^{commit}"
  )
  status.success?
rescue Errno::ENOENT
  false
end

def validate_suite_v31(suite)
  errors = []
  unless suite.is_a?(Hash) && suite["schema_version"].to_s == "idol-harness-shadow-eval-suite.v15"
    return ["suite schema_version must be idol-harness-shadow-eval-suite.v15"]
  end

  descriptor_policy = suite["profile_policy"]
  unless descriptor_policy.is_a?(Hash)
    errors << "profile_policy must be an object"
  else
    %w[
      profile_labels_are_operator_supplied model_descriptors_are_operator_supplied
      model_descriptors_are_local_execution_metadata same_source_snapshot_required
      same_task_and_active_sections_required same_harness_commit_required
      same_harness_snapshot_required harness_commit_resolves_to_local_git_commit_required
      hash_bound_artifact_refs_required profile_specific_artifact_root_required
      distinct_profile_artifact_roots_required no_shared_case_artifact_paths_required
      execution_manifest_descriptor_commit_match_required
      execution_manifest_harness_snapshot_match_required task_fit_route_required
      adaptive_upper_two_effort_required per_agent_usage_required
      per_agent_usage_must_reconcile
    ].each do |field|
      errors << "profile_policy.#{field} must be true" unless descriptor_policy[field] == true
    end
  end

  policy = suite["operator_profile_policy"]
  return errors << "operator_profile_policy must be an object" unless policy.is_a?(Hash)
  errors << "operator_profile_policy.active_model_family must be gpt-5.6" unless policy["active_model_family"] == "gpt-5.6"
  errors << "operator_profile_policy.comparison_scope must be gpt_5_6_family_internal_only" unless policy["comparison_scope"] == "gpt_5_6_family_internal_only"
  errors << "operator_profile_policy.candidate_descriptor_source must be operator_supplied_at_execution" unless policy["candidate_descriptor_source"] == "operator_supplied_at_execution"

  routing = policy["routing_policy"]
  return errors << "operator_profile_policy.routing_policy must be an object" unless routing.is_a?(Hash)
  errors << "routing_policy.policy_id must be #{ROUTING_POLICY_ID}" unless routing["policy_id"] == ROUTING_POLICY_ID
  errors << "routing_policy.automatic_lower_effort_allowed must be false" unless routing["automatic_lower_effort_allowed"] == false
  effort = routing["effort_policy"] || {}
  errors << "routing_policy effort mode drifted" unless effort["mode"] == "provider_registry_logical_aliases_v31"
  expected_efforts = {
    "gpt-5.6-sol" => %w[xhigh max ultra],
    "gpt-5.6-luna" => %w[max],
    "gpt-5.6-terra" => %w[xhigh]
  }
  errors << "routing_policy allowed efforts drifted" unless effort["allowed_efforts_by_model"] == expected_efforts
  errors << "unsupported pairing must hold_and_report" unless routing.dig("capability_check", "unsupported_pairing_action") == "hold_and_report"

  governance = routing["agent_governance"] || {}
  {
    "provider_native_helper_availability" => "default",
    "project_numeric_gate" => "none",
    "depth_gate" => "none",
    "physical_session_selection" => "adaptive_registered_assignment",
    "internal_and_physical_active_owner_overlap" => "forbidden",
    "canonical_creative_authority_role" => "overall_director",
    "standing_final_director_allowed" => false,
    "provider_contract_rewrite_allowed" => false
  }.each do |field, expected|
    errors << "routing_policy.agent_governance.#{field} must be #{expected.inspect}" unless governance[field] == expected
  end
  unless Array(governance["canonical_write_exception_agent_names"]).include?("idol_sol_edit_director") &&
         Array(governance["canonical_write_exception_paths"]).include?("runs/ALBUM_KEY/TITLE_KEY/RUN_ID/04-edit-map.yaml") &&
         !Array(governance["canonical_write_exception_paths"]).include?("runs/ALBUM_KEY/TITLE_KEY/RUN_ID/05-package.yaml")
    errors << "Edit Director physical canonical-write authority must include the run-root 04-edit-map.yaml and exclude 05-package.yaml"
  end
  unless Array(governance["inactive_legacy_exception_agent_names"]).sort == %w[idol_terra_direction_scout idol_terra_routine_judgment idol_terra_weekly_idol_research]
    errors << "Terra profiles must remain inactive legacy exceptions"
  end
  codex_roles = governance["codex_role_adapters"] || {}
  grok_roles = governance["grok_role_adapters"] || {}
  required_roles = %w[overall_director creative_development_director song_room department_worker member_visual_identity_owner section_owner edit_director edit_shard_worker mechanical_coordinator]
  errors << "Codex role adapter is incomplete" unless (required_roles - codex_roles.keys).empty?
  errors << "Grok role adapter is incomplete" unless (required_roles - grok_roles.keys).empty?
  unless grok_roles["same_dispatch_contract_as_codex"] == true && grok_roles["creative_contract_rewrite_allowed"] == false
    errors << "Grok must consume the same dispatch contract without a creative rewrite"
  end

  model_routes = Array(routing["model_routes"])
  model_ids = model_routes.each_with_object([]) { |row, values| values << row["model_id"] if row.is_a?(Hash) }
  errors << "model routes must name exactly Sol, Luna, and Terra" unless model_ids.sort == SUPPORTED_MODEL_IDS.sort
  policy_agents = []
  model_routes.each do |model_route|
    next unless model_route.is_a?(Hash)
    model_id = model_route["model_id"].to_s
    errors << "model route #{model_id} role must be non-empty" if model_route["role"].to_s.strip.empty?
    Array(model_route["agent_profiles"]).each do |profile|
      next errors << "model route #{model_id} contains a non-object profile" unless profile.is_a?(Hash)
      name = profile["agent_name"].to_s
      policy_agents << name
      expected = AGENT_PROFILES[name]
      unless expected && expected["model_id"] == model_id
        errors << "model route #{model_id} references unregistered profile #{name.inspect}"
        next
      end
      tuple = [profile["model_reasoning_effort"], profile["model_verbosity"], profile["tier_from_ceiling"]].map(&:to_s)
      expected_tuple = [expected["effort"], expected["verbosity"], expected["tier"]]
      errors << "model route profile #{name} tuple drifted" unless tuple == expected_tuple
    end
  end
  errors << "model routes must register each active profile exactly once" unless policy_agents.uniq.sort == AGENT_PROFILES.keys.sort && policy_agents.uniq.length == policy_agents.length

  expected_routes = %w[
    initial_direction_discovery weekly_visual_idol_research
    creative_core_and_founder_direction creative_development_direction
    physical_song_room media_research_department member_visual_identity
    high_stakes_repair_and_final_qc development_block physical_section_shard
    edit_director edit_shard full_flow_integration complete_full_flow
  ]
  routes = Array(routing["route_classes"])
  route_ids = routes.each_with_object([]) { |row, values| values << row["route_id"].to_s if row.is_a?(Hash) }
  errors << "routing_policy route class order drifted" unless route_ids == expected_routes
  routes.each do |route|
    next unless route.is_a?(Hash)
    route_id = route["route_id"].to_s
    descriptors = [route["default_route"], *Array(route["explicit_alternatives"])]
    descriptors.each do |descriptor|
      unless descriptor.is_a?(Hash) && route_descriptor_allowed?(suite, descriptor)
        errors << "route class #{route_id} has an unregistered descriptor"
        next
      end
      if route_id != "weekly_visual_idol_research" && (descriptor["model_id"] == "gpt-5.6-terra" || descriptor["agent_name"].to_s.start_with?("idol_terra_"))
        errors << "ordinary route #{route_id} must not use Terra"
      end
    end
    errors << "route class #{route_id} purpose must be non-empty" if route["purpose"].to_s.strip.empty?
    errors << "route class #{route_id} selection basis must be non-empty" if route["default_selection_basis"].to_s.strip.empty?
    errors << "route class #{route_id} escalation triggers must be non-empty" if Array(route["escalation_triggers"]).empty?
  end
  weekly = routes.find { |row| row["route_id"] == "weekly_visual_idol_research" }
  unless route_descriptor_tuple(weekly && weekly["default_route"]) == %w[idol_luna_studio_department gpt-5.6-luna max high]
    errors << "weekly visual research automation must use Luna/Max"
  end
  section_route = routes.find { |row| row["route_id"] == "physical_section_shard" }
  expected_section_resolution = {
    "logical_profile_alias" => "worker_high",
    "logical_role" => "section_image_motion_worker",
    "provider_registry_path" => "automation/harness-provider-profile-registry.yaml",
    "provider_resolution" => "exact_run_snapshot_no_fallback",
    "codex_physical_realization" => "idol_luna_section_image_motion",
    "grok_physical_realization" => "grok_worker_high",
    "provider_native_media_tools_must_remain_distinct" => true
  }
  expected_section_resolution.each do |field, expected|
    errors << "physical_section_shard #{field} must be #{expected.inspect}" unless section_route && section_route[field] == expected
  end
  max_review = routes.find { |row| row["route_id"] == "high_stakes_repair_and_final_qc" }
  errors << "Sol/Max review must be advisory to Overall" unless max_review && max_review["output_authority"] == "advisory_to_overall_director" && max_review["owner_review_required_for_canonical_write"] == true
  errors << "standing final_validation authority is forbidden" if routes.any? { |row| row["output_authority"] == "final_validation" }

  registered_route_ids = route_ids.to_set
  Array(suite["cases"]).each do |case_def|
    next unless case_def.is_a?(Hash)
    errors << "suite case #{case_def['case_id']} route_id must name a registered route" unless registered_route_ids.include?(case_def["route_id"].to_s)
  end

  expected_surface = {
    "active_execution_surface" => "legacy_codex_comparison_only",
    "codex_effort_field" => "model_reasoning_effort",
    "codex_effort_policy" => "provider_registry_logical_aliases_v31",
    "codex_verbosity_field" => "model_verbosity",
    "responses_api_effort_field" => "reasoning.effort",
    "responses_api_highest_documented_effort" => "max",
    "cross_surface_effort_translation_allowed" => false,
    "responses_api_harness_route_active" => false
  }
  errors << "operator_profile_policy.surface_contract drifted" unless policy["surface_contract"] == expected_surface
  tool_policy = policy["tool_calling_policy"] || {}
  errors << "tool calling must retain Overall final acceptance" unless tool_policy["overall_director_final_acceptance_required"] == true
  errors << "delegation must require root reconciliation" unless policy.dig("delegation_policy", "root_reconciliation_required") == true
  grok_governance = policy.dig("routing_policy", "agent_governance", "grok_worker_session_governance") || {}
  expected_goal_admission = {
    "admissible_surfaces" => %w[interactive_tui_slash_goal acp_matching_native_goal_event],
    "objective_match_required" => true,
    "headless_without_matching_native_goal_event" => "forbidden",
    "goal_surface_unavailable_action" => "hold_zero_work_zero_output"
  }
  unless grok_governance["goal_admission"] == expected_goal_admission
    errors << "Grok shadow routes must require TUI /goal or matching ACP native Goal and HOLD with zero work/output otherwise"
  end
  peer_headless = grok_governance["peer_headless_sessions"] || {}
  unless peer_headless["admission_requires"] == "matching_acp_native_goal_event" &&
         peer_headless["goal_surface_unavailable_action"] == "hold_zero_work_zero_output"
    errors << "peer headless shadow session must prove a matching ACP native Goal before work"
  end
  baseline = policy["current_baseline"] || {}
  errors << "current baseline effort policy drifted" unless baseline["effort_policy"] == "provider_registry_logical_aliases_v31"

  thresholds = suite["thresholds"]
  unless thresholds.is_a?(Hash)
    errors << "thresholds must be an object"
  else
    %w[maximum_output_token_increase_percent maximum_retry_increase].each do |field|
      value = thresholds[field]
      errors << "thresholds.#{field} must be a non-negative number" unless value.is_a?(Numeric) && value >= 0
    end
  end
  errors
end

def validate_suite(suite)
  errors = validate_suite_v31(suite)
  runtime = suite["runtime_route_shadow"]
  return errors << "runtime_route_shadow must be an object" unless runtime.is_a?(Hash)
  execution = load_doc(ROOT.join(runtime["execution_contract_path"].to_s))
  provider_registry = load_doc(ROOT.join(runtime["provider_registry_path"].to_s))
  errors << "runtime route shadow must be offline_deterministic_dry_run" unless runtime["mode"] == "offline_deterministic_dry_run"
  %w[live_model_calls external_actions generative_actions].each do |field|
    errors << "runtime_route_shadow.#{field} must be forbidden" unless runtime[field] == "forbidden"
  end
  errors << "runtime route shadow fallback must be forbidden" unless runtime["fallback_policy"] == "forbidden"
  unless runtime["stage_reachability_semantics"] == "route_order_only_never_provider_ownership_or_generation_authority"
    errors << "runtime route shadow stage reachability must not imply provider ownership or generation authority"
  end
  expected_media_lane = {
    "lane_id" => "grok_build_oauth_subscription",
    "required_harness_status" => "active",
    "nonmedia_activation_may_promote_lane" => false,
    "registered_lane_is_not_generation_or_playback_pass" => true
  }
  unless runtime["registered_media_lane_expectation"] == expected_media_lane
    errors << "runtime route shadow must keep Grok media registration separate from generation/playback PASS"
  end
  unless provider_registry.dig("media_lanes", "grok_build_oauth_subscription", "video_harness_status") == "active"
    errors << "runtime route shadow requires the registered Grok video lane to be active"
  end
  selection = provider_registry["selection_policy"].is_a?(Hash) ? provider_registry["selection_policy"] : {}
  unless selection["preferred_nonmedia_provider"] == "grok" &&
         selection["founder_default_switch_required"] == true &&
         selection["preferred_provider_unavailable_action"] == "hold_without_cross_provider_fallback"
    errors << "runtime route shadow requires Founder-gated Grok preference with unsupported-route HOLD and no fallback"
  end
  media_handoffs = Array(runtime["registered_media_generation_handoffs"])
  unless media_handoffs == REGISTERED_MEDIA_GENERATION_HANDOFFS
    errors << "runtime route shadow must exact-bind the existing 02B image and 03V video generation handoffs"
  end
  errors << "runtime route shadow must bind execution v36" unless execution["schema_version"] == "idol-harness-execution-contract.v36"
  errors << "runtime route shadow must bind provider registry v1" unless provider_registry["schema_version"] == "idol-harness-provider-profile-registry.v1"
  execution_route = Array(execution["active_route"])
  expected_returns = runtime["required_return_checkpoints"] || {}
  expected_returns.each do |field, expected|
    actual = execution.dig("return_routing", field)
    errors << "runtime return reachability mismatch for #{field}: expected #{expected}, got #{actual}" unless actual == expected
  end
  fixtures = Array(runtime["offline_fixtures"])
  errors << "runtime route shadow must contain Grok-only and Cursor-reference fixtures" unless fixtures.map { |row| row["fixture_id"] } == %w[grok_only_pre00_to_05 cursor_reference_pre00_to_05]
  fixtures.each do |fixture|
    fixture_id = fixture["fixture_id"].to_s
    errors << "#{fixture_id} stage reachability must equal execution active_route" unless Array(fixture["stages"]) == execution_route
    expected_provider_scope = fixture["provider_lane"].to_s == "grok" ?
      "nonmedia_only_with_registered_media_generation_handoffs" :
      "nonmedia_reference_control_with_registered_media_generation_handoffs"
    errors << "#{fixture_id} provider scope must remain nonmedia-only" unless fixture["provider_scope"] == expected_provider_scope
    nonmedia_stages = execution_route.reject { |stage_id| stage_id == "branch_cut_generation" }
    unless Array(fixture["nonmedia_provider_stages"]) == nonmedia_stages
      errors << "#{fixture_id} nonmedia provider stages must exclude 02B image generation while preserving route order"
    end
    unless Array(fixture["media_generation_handoffs"]) == media_handoffs
      errors << "#{fixture_id} media generation handoffs must exact-copy the registered runtime handoffs"
    end
    unless fixture["registered_media_handoff_count_expected"] == media_handoffs.length
      errors << "#{fixture_id}.registered_media_handoff_count_expected must equal the exact registered handoff count"
    end
    errors << "#{fixture_id} must resolve director_deep and worker_high" unless Array(fixture["resolved_logical_aliases"]) == %w[director_deep worker_high]
    errors << "#{fixture_id} must have zero fallback providers" unless Array(fixture["fallback_providers"]).empty?
    %w[codex_fallback_count_expected live_model_call_count_expected external_action_count_expected generative_action_count_expected unauthorized_media_generation_count_expected].each do |field|
      errors << "#{fixture_id}.#{field} must be zero" unless fixture[field] == 0
    end
    provider = fixture["provider_lane"].to_s
    ready_aliases = []
    held_aliases = []
    %w[director_deep worker_high].each do |logical_alias|
      source = provider_registry.dig("logical_profiles", logical_alias, "providers", provider)
      errors << "#{fixture_id} cannot resolve #{logical_alias} on #{provider}" unless source.is_a?(Hash)
      if source.is_a?(Hash) && %w[active active_text_only].include?(source["harness_status"]) && source["full_owner_ready"] == true
        ready_aliases << logical_alias
      else
        held_aliases << logical_alias
      end
    end
    unless Array(fixture["ready_logical_aliases_expected"]) == ready_aliases
      errors << "#{fixture_id} ready logical aliases differ from exact provider readiness"
    end
    unless Array(fixture["held_logical_aliases_expected"]) == held_aliases
      errors << "#{fixture_id} held logical aliases differ from exact provider readiness"
    end
    switch_allowed = held_aliases.empty?
    unless fixture["founder_default_switch_review_allowed_expected"] == switch_allowed
      errors << "#{fixture_id} Founder default-switch review expectation bypasses a held profile"
    end
  end
  errors
end

def validate_result(result, suite, ledger_path:)
  return ["result root must be an object"] unless result.is_a?(Hash)

  errors = []
  unknown_result_fields = result.keys.map(&:to_s) - RESULT_FIELDS
  errors << "result has unknown fields: #{unknown_result_fields.join(',')}" unless unknown_result_fields.empty?
  errors << "schema_version must be idol-harness-shadow-eval-result.v10" unless result["schema_version"].to_s == "idol-harness-shadow-eval-result.v10"
  unless result["profile_label"].is_a?(String) && !result["profile_label"].strip.empty?
    errors << "profile_label must be a non-empty string"
  end
  descriptor = result["profile_descriptor"]
  if descriptor.is_a?(Hash)
    unknown_fields = descriptor.keys.map(&:to_s) - PROFILE_DESCRIPTOR_FIELDS
    errors << "profile_descriptor has unknown fields: #{unknown_fields.join(',')}" unless unknown_fields.empty?
    PROFILE_DESCRIPTOR_FIELDS.each do |field|
      value = descriptor[field]
      errors << "profile_descriptor.#{field} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
    end
    active_family = suite.dig("operator_profile_policy", "active_model_family").to_s
    unless descriptor["model_family"].to_s == active_family
      errors << "profile_descriptor.model_family must be #{active_family}"
    end
    unless descriptor["model_id"].to_s.match?(MODEL_ID_PATTERN) && SUPPORTED_MODEL_IDS.include?(descriptor["model_id"].to_s)
      errors << "profile_descriptor.model_id must be one of the active gpt-5.6 Sol, Luna, or Terra ids"
    end
    registered_profile = agent_profile_for(suite, descriptor["agent_name"])
    unless registered_profile
      errors << "profile_descriptor.agent_name #{descriptor['agent_name'].inspect} is not a registered adaptive agent profile"
    else
      expected_tuple = [registered_profile["model_id"], registered_profile["model_reasoning_effort"], registered_profile["model_verbosity"]]
      actual_tuple = [descriptor["model_id"], descriptor["model_reasoning_effort"], descriptor["model_verbosity"]].map(&:to_s)
      unless actual_tuple == expected_tuple.map(&:to_s)
        errors << "profile_descriptor must match registered agent profile #{descriptor['agent_name']}: #{expected_tuple.join(' / ')}"
      end
    end
    unless descriptor["effort_policy"].to_s == "provider_registry_logical_aliases_v31"
      errors << "profile_descriptor.effort_policy must be provider_registry_logical_aliases_v31"
    end
    %w[agent_name model_reasoning_effort effort_policy model_verbosity execution_surface harness_variant].each do |field|
      unless descriptor[field].to_s.match?(CANONICAL_DESCRIPTOR_PATTERN)
        errors << "profile_descriptor.#{field} must use canonical lowercase descriptor syntax"
      end
    end
    unless %w[current_baseline candidate].include?(descriptor["profile_role"].to_s)
      errors << "profile_descriptor.profile_role must be current_baseline or candidate"
    end
    errors << "profile_descriptor.execution_surface must be codex" unless descriptor["execution_surface"].to_s == "codex"
    if descriptor["profile_role"].to_s == "current_baseline"
      expected_baseline = suite.dig("operator_profile_policy", "current_baseline") || {}
      unless result["profile_label"].to_s == expected_baseline["profile_label"].to_s
        errors << "current_baseline profile_label must be #{expected_baseline['profile_label']}"
      end
      PROFILE_DESCRIPTOR_FIELDS.each do |field|
        expected = expected_baseline[field].to_s
        actual = descriptor[field].to_s
        errors << "current_baseline profile_descriptor.#{field} must be #{expected}" unless actual == expected
      end
    end
  else
    errors << "profile_descriptor must be an object"
  end
  unless result["harness_commit"].is_a?(String) && result["harness_commit"].match?(GIT_COMMIT_PATTERN)
    errors << "harness_commit must be lowercase hexadecimal with 7-40 characters"
  else
    errors << "harness_commit does not resolve to a local git commit" unless local_git_commit?(result["harness_commit"])
  end

  root_errors, artifact_root = validate_artifact_root(result["artifact_root"], ledger_path)
  errors.concat(root_errors)
  %w[harness_snapshot source_snapshot task_set].each do |field|
    ref_errors, = validate_artifact_ref(result[field], label: field, ledger_path: ledger_path)
    errors.concat(ref_errors)
  end
  manifest_errors, manifest_path = validate_artifact_ref(
    result["profile_execution_manifest"],
    label: "profile_execution_manifest",
    ledger_path: ledger_path,
    required_root: artifact_root
  )
  errors.concat(manifest_errors)
  errors.concat(validate_execution_manifest(manifest_path, result)) if manifest_errors.empty?

  cases = Array(result["case_results"])
  rows = cases.each_with_object({}) { |row, memo| memo[row["case_id"].to_s] = row if row.is_a?(Hash) }
  case_defs = Array(suite["cases"]).each_with_object({}) { |row, memo| memo[row["case_id"].to_s] = row if row.is_a?(Hash) }
  required_cases = case_defs.keys
  missing_cases = required_cases - rows.keys
  unknown_cases = rows.keys - required_cases
  errors << "missing eval cases: #{missing_cases.join(',')}" unless missing_cases.empty?
  errors << "unknown eval cases: #{unknown_cases.join(',')}" unless unknown_cases.empty?
  errors << "duplicate case ids" unless cases.map { |row| row.is_a?(Hash) ? row["case_id"].to_s : "" }.uniq.length == cases.length

  dimensions = suite["quality_dimensions"].is_a?(Hash) ? suite["quality_dimensions"] : {}
  hard_gates = Array(suite["hard_gates"]).map(&:to_s)
  evidence_keys = Array(suite["evidence_counts"]).map(&:to_s)
  seen_case_artifacts = {}
  rows.each do |case_id, row|
    unknown_case_fields = row.keys.map(&:to_s) - CASE_RESULT_FIELDS
    errors << "#{case_id}: result has unknown fields: #{unknown_case_fields.join(',')}" unless unknown_case_fields.empty?
    case_def = case_defs[case_id] || {}
    quality_scores = row["quality_scores"].is_a?(Hash) ? row["quality_scores"] : {}
    hard_gate_values = row["hard_gates"].is_a?(Hash) ? row["hard_gates"] : {}
    evidence_counts = row["evidence_counts"].is_a?(Hash) ? row["evidence_counts"] : {}
    required_evidence_values = row["required_evidence"].is_a?(Hash) ? row["required_evidence"] : {}
    efficiency = row["efficiency"].is_a?(Hash) ? row["efficiency"] : {}
    missing_dimensions = dimensions.keys - quality_scores.keys
    missing_hard = hard_gates - hard_gate_values.keys
    missing_evidence = evidence_keys - evidence_counts.keys
    missing_required_evidence = Array(case_def["required_evidence"]).map(&:to_s) - required_evidence_values.keys
    errors << "#{case_id}: missing quality dimensions #{missing_dimensions.join(',')}" unless missing_dimensions.empty?
    errors << "#{case_id}: missing hard gates #{missing_hard.join(',')}" unless missing_hard.empty?
    errors << "#{case_id}: missing evidence counts #{missing_evidence.join(',')}" unless missing_evidence.empty?
    errors << "#{case_id}: missing required evidence #{missing_required_evidence.join(',')}" unless missing_required_evidence.empty?
    errors << "#{case_id}: stage_id mismatch" unless row["stage_id"].to_s == case_def["stage_id"].to_s

    artifacts = row["artifacts"]
    unless artifacts.is_a?(Array) && !artifacts.empty?
      errors << "#{case_id}: artifacts must be a non-empty array"
      artifacts = []
    end
    case_paths = []
    artifacts.each_with_index do |artifact_ref, index|
      artifact_errors, resolved_path = validate_artifact_ref(
        artifact_ref,
        label: "#{case_id}.artifacts[#{index}]",
        ledger_path: ledger_path,
        required_root: artifact_root
      )
      errors.concat(artifact_errors)
      next unless resolved_path

      canonical_path = canonical_existing_path(resolved_path).to_s
      case_paths << canonical_path
      previous_case = seen_case_artifacts[canonical_path]
      if previous_case
        errors << "#{case_id}: case artifact path is already used by #{previous_case}: #{canonical_path}"
      else
        seen_case_artifacts[canonical_path] = case_id
      end
    end
    errors << "#{case_id}: artifact paths must be unique" unless case_paths.uniq.length == case_paths.length
    quality_scores.each do |dimension, score|
      errors << "#{case_id}: #{dimension} quality score must be between 0 and 5" unless score.is_a?(Numeric) && score.between?(0, 5)
    end
    hard_gate_values.each do |gate_id, value|
      errors << "#{case_id}: #{gate_id} hard gate must be boolean" unless [true, false].include?(value)
    end
    required_evidence_values.each do |evidence_id, value|
      errors << "#{case_id}: #{evidence_id} required evidence must be boolean" unless [true, false].include?(value)
    end
    evidence_counts.each do |evidence_id, value|
      errors << "#{case_id}: #{evidence_id} evidence count must be a non-negative integer" unless value.is_a?(Integer) && value >= 0
    end
    %w[input_tokens output_tokens tool_calls retries].each do |field|
      value = efficiency[field]
      errors << "#{case_id}: efficiency.#{field} must be a non-negative integer" unless value.is_a?(Integer) && value >= 0
    end
    errors << "#{case_id}: efficiency.input_tokens must be positive for comparison" unless efficiency["input_tokens"].to_i.positive?
    wall_seconds = efficiency["wall_seconds"]
    errors << "#{case_id}: efficiency.wall_seconds must be positive" unless wall_seconds.is_a?(Numeric) && wall_seconds.positive?
    errors.concat(validate_case_agent_usage(case_id, row, suite, case_def["route_id"]))
  end
  if descriptor.is_a?(Hash)
    profile_execution_seen = cases.any? do |row|
      next false unless row.is_a?(Hash)

      Array(row["agent_usage"]).any? do |entry|
        entry.is_a?(Hash) &&
          entry["agent_name"].to_s == descriptor["agent_name"].to_s &&
          entry["model_id"].to_s == descriptor["model_id"].to_s &&
          entry["model_reasoning_effort"].to_s == descriptor["model_reasoning_effort"].to_s &&
          entry["model_verbosity"].to_s == descriptor["model_verbosity"].to_s
      end
    end
    errors << "agent_usage must include the profile descriptor tuple in at least one case" unless profile_execution_seen
  end
  errors
end

def repo_relative_path(path)
  expanded = Pathname.new(path).expand_path
  relative = expanded.relative_path_from(ROOT).to_s
  if relative == ".." || relative.start_with?("../")
    raise ArgumentError, "path must stay inside repository: #{expanded}"
  end

  relative
end

def sha256_file(path)
  Digest::SHA256.file(Pathname.new(path)).hexdigest
end

def shadow_closeout_paths(run_root, output: nil)
  root = Pathname.new(run_root).expand_path
  raise ArgumentError, "run root does not exist: #{root}" unless root.directory?

  root = root.realpath
  repo_relative_path(root)
  maintenance_root = root.join("work", "harness-maintenance")
  raise ArgumentError, "maintenance evidence directory does not exist: #{maintenance_root}" unless maintenance_root.directory?

  paths = SHADOW_CLOSEOUT_CANONICAL_INPUTS.transform_values do |relative|
    path = root.join(relative)
    raise ArgumentError, "required SU canonical input is missing: #{path}" unless path.file?

    path.realpath
  end
  downstream = SHADOW_CLOSEOUT_DOWNSTREAM_ARTIFACTS.transform_values { |relative| root.join(relative) }
  output_path = output && Pathname.new(output).expand_path
  if output_path
    unless output_path.dirname.directory? && output_path.dirname.realpath == maintenance_root.realpath
      raise ArgumentError, "closeout output must be a direct child of #{maintenance_root}"
    end
    raise ArgumentError, "closeout output must not be a symlink" if output_path.symlink?
    raise ArgumentError, "closeout output must be a YAML file" unless %w[.yaml .yml].include?(output_path.extname.downcase)
  end

  {
    run_root: root,
    maintenance_root: maintenance_root.realpath,
    canonical: paths,
    downstream: downstream,
    output: output_path
  }
end

def shadow_closeout_snapshot(paths)
  readiness = load_doc(paths.fetch(:canonical).fetch("front_planning_readiness"))
  board = load_doc(paths.fetch(:canonical).fetch("founder_review_board_manifest"))
  run_manifest = load_doc(paths.fetch(:canonical).fetch("run_manifest"))
  section_statuses = Array(board["sections"]).each_with_object([]) do |section, statuses|
    statuses << section["status"].to_s if section.is_a?(Hash)
  end
  errors = []
  errors << "Front Planning readiness must remain founder_review" unless readiness["status"].to_s == "founder_review"
  errors << "Founder review board must remain founder_review" unless board.dig("board", "status").to_s == "founder_review"
  if section_statuses.empty? || section_statuses.any? { |status| status != "founder_review" }
    errors << "every Founder review board section must remain founder_review"
  end
  unless run_manifest["canonical_run_root"].to_s == repo_relative_path(paths.fetch(:run_root))
    errors << "run manifest canonical_run_root does not match the selected run root"
  end
  paths.fetch(:downstream).each do |stage, path|
    errors << "downstream #{stage} is already open: #{path}" if path.exist?
  end

  {
    errors: errors,
    front_planning_status: readiness["status"].to_s,
    board_status: board.dig("board", "status").to_s,
    board_section_statuses: section_statuses,
    run_status: run_manifest["status"].to_s,
    run_id: run_manifest["run_id"].to_s,
    canonical_hashes: paths.fetch(:canonical).transform_values { |path| sha256_file(path) },
    downstream_exists: paths.fetch(:downstream).transform_values(&:exist?)
  }
end

def build_shadow_closeout_evidence(suite, suite_path, paths, before_snapshot, after_snapshot = before_snapshot)
  run_root = paths.fetch(:run_root)
  canonical_artifacts = SHADOW_CLOSEOUT_CANONICAL_INPUTS.map do |role, relative|
    {
      "role" => role,
      "path" => repo_relative_path(run_root.join(relative)),
      "before_sha256" => before_snapshot.fetch(:canonical_hashes).fetch(role),
      "after_sha256" => after_snapshot.fetch(:canonical_hashes).fetch(role),
      "unchanged" => before_snapshot.fetch(:canonical_hashes).fetch(role) == after_snapshot.fetch(:canonical_hashes).fetch(role)
    }
  end
  downstream_absence = SHADOW_CLOSEOUT_DOWNSTREAM_ARTIFACTS.map do |stage, relative|
    {
      "stage" => stage,
      "path" => repo_relative_path(run_root.join(relative)),
      "exists" => after_snapshot.fetch(:downstream_exists).fetch(stage)
    }
  end
  hashes_unchanged = canonical_artifacts.all? { |row| row["unchanged"] == true }
  downstream_absent = downstream_absence.all? { |row| row["exists"] == false }
  founder_review_preserved = after_snapshot.fetch(:front_planning_status) == "founder_review" &&
    after_snapshot.fetch(:board_status) == "founder_review" &&
    !after_snapshot.fetch(:board_section_statuses).empty? &&
    after_snapshot.fetch(:board_section_statuses).all? { |status| status == "founder_review" }

  {
    "schema_version" => SHADOW_CLOSEOUT_SCHEMA_VERSION,
    "task_id" => "#{before_snapshot.fetch(:run_id)}_V18_SHADOW_CLOSEOUT",
    "status" => hashes_unchanged && downstream_absent && founder_review_preserved ? "complete" : "hold",
    "scope" => SHADOW_CLOSEOUT_SCOPE,
    "run" => {
      "run_root" => repo_relative_path(run_root),
      "run_id" => before_snapshot.fetch(:run_id),
      "run_status" => after_snapshot.fetch(:run_status)
    },
    "routing_contract" => {
      "policy_id" => routing_policy(suite).fetch("policy_id"),
      "suite_path" => repo_relative_path(suite_path),
      "suite_sha256" => sha256_file(suite_path),
      "runner_path" => repo_relative_path(Pathname.new(__FILE__).expand_path),
      "runner_sha256" => sha256_file(Pathname.new(__FILE__).expand_path),
      "suite_validation" => "pass",
      "comparison_performed" => false,
      "model_execution_performed" => false
    },
    "canonical_state" => {
      "front_planning_status" => after_snapshot.fetch(:front_planning_status),
      "founder_review_board_status" => after_snapshot.fetch(:board_status),
      "founder_review_section_statuses" => after_snapshot.fetch(:board_section_statuses).uniq,
      "downstream_01_opened" => after_snapshot.fetch(:downstream_exists).fetch("01"),
      "downstream_02a_opened" => after_snapshot.fetch(:downstream_exists).fetch("02A"),
      "promotion_or_authorization_performed" => false
    },
    "canonical_artifacts" => canonical_artifacts,
    "downstream_absence" => downstream_absence,
    "boundary" => {
      "evidence_only" => true,
      "may_promote_front_planning" => false,
      "may_open_01_or_02a" => false,
      "may_author_creative_truth" => false
    },
    "verification" => {
      "routing_suite_validation" => "pass",
      "canonical_hashes_unchanged" => hashes_unchanged,
      "founder_review_preserved" => founder_review_preserved,
      "downstream_absence_preserved" => downstream_absent
    }
  }
end

def validate_shadow_closeout_evidence(evidence, evidence_path, suite, suite_path)
  errors = []
  unless evidence.is_a?(Hash)
    return ["closeout evidence must be an object"]
  end
  errors << "schema_version must be #{SHADOW_CLOSEOUT_SCHEMA_VERSION}" unless evidence["schema_version"] == SHADOW_CLOSEOUT_SCHEMA_VERSION
  errors << "scope must be #{SHADOW_CLOSEOUT_SCOPE}" unless evidence["scope"] == SHADOW_CLOSEOUT_SCOPE
  errors << "status must be complete" unless evidence["status"] == "complete"
  run_root_raw = evidence.dig("run", "run_root").to_s
  if run_root_raw.empty?
    return errors << "run.run_root is required"
  end

  begin
    paths = shadow_closeout_paths(ROOT.join(run_root_raw), output: evidence_path)
    snapshot = shadow_closeout_snapshot(paths)
    errors.concat(snapshot.fetch(:errors))
    routing = evidence["routing_contract"].is_a?(Hash) ? evidence["routing_contract"] : {}
    expected_suite_path = repo_relative_path(suite_path)
    expected_runner_path = repo_relative_path(Pathname.new(__FILE__).expand_path)
    errors << "routing_contract.policy_id drifted" unless routing["policy_id"] == routing_policy(suite)["policy_id"]
    errors << "routing_contract.suite_path drifted" unless routing["suite_path"] == expected_suite_path
    errors << "routing_contract.suite_sha256 is stale" unless routing["suite_sha256"] == sha256_file(suite_path)
    errors << "routing_contract.runner_path drifted" unless routing["runner_path"] == expected_runner_path
    errors << "routing_contract.runner_sha256 is stale" unless routing["runner_sha256"] == sha256_file(Pathname.new(__FILE__).expand_path)
    errors << "routing_contract.suite_validation must be pass" unless routing["suite_validation"] == "pass"
    errors << "routing_contract.comparison_performed must be false" unless routing["comparison_performed"] == false
    errors << "routing_contract.model_execution_performed must be false" unless routing["model_execution_performed"] == false

    errors << "task_id drifted" unless evidence["task_id"] == "#{snapshot.fetch(:run_id)}_V18_SHADOW_CLOSEOUT"
    errors << "run.run_id drifted" unless evidence.dig("run", "run_id") == snapshot.fetch(:run_id)
    errors << "run.run_status drifted" unless evidence.dig("run", "run_status") == snapshot.fetch(:run_status)

    canonical_rows = Array(evidence["canonical_artifacts"])
    SHADOW_CLOSEOUT_CANONICAL_INPUTS.each do |role, relative|
      row = canonical_rows.find { |candidate| candidate.is_a?(Hash) && candidate["role"] == role }
      unless row
        errors << "canonical_artifacts is missing #{role}"
        next
      end
      expected_path = repo_relative_path(paths.fetch(:run_root).join(relative))
      current_sha = snapshot.fetch(:canonical_hashes).fetch(role)
      errors << "#{role} path drifted" unless row["path"] == expected_path
      errors << "#{role} before_sha256 and after_sha256 must match" unless row["before_sha256"] == row["after_sha256"]
      errors << "#{role} hash is stale" unless row["after_sha256"] == current_sha
      errors << "#{role} unchanged must be true" unless row["unchanged"] == true
    end
    errors << "canonical_artifacts contains unexpected rows" unless canonical_rows.length == SHADOW_CLOSEOUT_CANONICAL_INPUTS.length

    downstream_rows = Array(evidence["downstream_absence"])
    SHADOW_CLOSEOUT_DOWNSTREAM_ARTIFACTS.each do |stage, relative|
      row = downstream_rows.find { |candidate| candidate.is_a?(Hash) && candidate["stage"] == stage }
      unless row
        errors << "downstream_absence is missing #{stage}"
        next
      end
      errors << "downstream #{stage} path drifted" unless row["path"] == repo_relative_path(paths.fetch(:run_root).join(relative))
      errors << "downstream #{stage} must remain absent" unless row["exists"] == false && snapshot.fetch(:downstream_exists).fetch(stage) == false
    end
    errors << "downstream_absence contains unexpected rows" unless downstream_rows.length == SHADOW_CLOSEOUT_DOWNSTREAM_ARTIFACTS.length

    state = evidence["canonical_state"].is_a?(Hash) ? evidence["canonical_state"] : {}
    errors << "canonical_state.front_planning_status must remain founder_review" unless state["front_planning_status"] == "founder_review"
    errors << "canonical_state.founder_review_board_status must remain founder_review" unless state["founder_review_board_status"] == "founder_review"
    errors << "canonical_state section statuses must remain founder_review" unless Array(state["founder_review_section_statuses"]) == ["founder_review"]
    errors << "canonical_state.downstream_01_opened must be false" unless state["downstream_01_opened"] == false
    errors << "canonical_state.downstream_02a_opened must be false" unless state["downstream_02a_opened"] == false
    errors << "canonical_state.promotion_or_authorization_performed must be false" unless state["promotion_or_authorization_performed"] == false

    boundary = evidence["boundary"].is_a?(Hash) ? evidence["boundary"] : {}
    errors << "boundary.evidence_only must be true" unless boundary["evidence_only"] == true
    %w[may_promote_front_planning may_open_01_or_02a may_author_creative_truth].each do |field|
      errors << "boundary.#{field} must be false" unless boundary[field] == false
    end
    verification = evidence["verification"].is_a?(Hash) ? evidence["verification"] : {}
    errors << "verification.routing_suite_validation must be pass" unless verification["routing_suite_validation"] == "pass"
    %w[canonical_hashes_unchanged founder_review_preserved downstream_absence_preserved].each do |field|
      errors << "verification.#{field} must be true" unless verification[field] == true
    end
  rescue ArgumentError, RuntimeError, Errno::ENOENT => e
    errors << e.message
  end
  errors
end

command = ARGV.shift
options = {suite: DEFAULT_SUITE, json: false}
OptionParser.new do |opts|
  opts.on("--suite PATH") { |value| options[:suite] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--run-root PATH") { |value| options[:run_root] = Pathname.new(value).expand_path }
  opts.on("--output PATH") { |value| options[:output] = Pathname.new(value).expand_path }
  opts.on("--select-agent AGENT_NAME") { |value| options[:select_agent] = value }
  opts.on("--escalation-trigger TRIGGER") { |value| options[:escalation_trigger] = value }
  opts.on("--founder-selected-ultra") { options[:founder_selected_ultra] = true }
  opts.on("--execution-scope SCOPE") { |value| options[:execution_scope] = value }
end.parse!

unless %w[policy route-shadow route closeout validate-closeout validate compare].include?(command)
  warn "usage: ruby scripts/idol_harness_shadow_eval.rb policy [--suite PATH] [--json] | route-shadow FIXTURE_ID [--suite PATH] [--json] | route ROUTE_ID --execution-scope SCOPE [--select-agent AGENT_NAME] [--founder-selected-ultra] [--escalation-trigger TRIGGER] [--suite PATH] [--json] | closeout --run-root RUN_ROOT --output OUTPUT [--suite PATH] [--json] | validate-closeout EVIDENCE [--suite PATH] [--json] | validate RESULT [--suite PATH] | compare BASELINE CANDIDATE [--suite PATH] [--json]"
  exit 2
end

suite = load_doc(options[:suite])
suite_errors = validate_suite(suite)
unless suite_errors.empty?
  suite_errors.each { |error| warn "ERROR: #{error}" }
  exit 1
end

if command == "route-shadow"
  fixture_id = ARGV.shift.to_s
  runtime = suite.fetch("runtime_route_shadow")
  fixture = Array(runtime["offline_fixtures"]).find { |row| row["fixture_id"].to_s == fixture_id }
  unless fixture
    warn "ERROR: unknown route-shadow fixture #{fixture_id.inspect}"
    exit 2
  end

  provider_registry_path = ROOT.join(runtime.fetch("provider_registry_path"))
  execution_contract_path = ROOT.join(runtime.fetch("execution_contract_path"))
  provider_registry = load_doc(provider_registry_path)
  provider = fixture.fetch("provider_lane")
  resolved_profiles = Array(fixture["resolved_logical_aliases"]).each_with_object({}) do |logical_alias, memo|
    source = provider_registry.dig("logical_profiles", logical_alias, "providers", provider)
    memo[logical_alias] = {
      "source_kind" => source.fetch("source_kind"),
      "source_path" => source.fetch("source_path"),
      "source_sha256" => source["source_sha256"] || source["source_set_sha256"],
      "capability_status" => source.fetch("capability_status"),
      "harness_status" => source.fetch("harness_status"),
      "full_owner_ready" => source.fetch("full_owner_ready")
    }
  end
  ready_logical_aliases = resolved_profiles.each_with_object([]) do |(logical_alias, row), memo|
    memo << logical_alias if %w[active active_text_only].include?(row["harness_status"]) && row["full_owner_ready"] == true
  end
  held_logical_aliases = resolved_profiles.keys - ready_logical_aliases
  activation_ready = held_logical_aliases.empty?
  media_lane_id = runtime.fetch("registered_media_lane_expectation").fetch("lane_id")
  media_lane_status = provider_registry.dig("media_lanes", media_lane_id, "harness_status")
  result = {
    "schema_version" => "idol-harness-runtime-route-shadow-result.v1",
    "fixture_id" => fixture_id,
    "mode" => runtime.fetch("mode"),
    "status" => "pass",
    "activation_status" => activation_ready ? "eligible_for_founder_default_switch_review" : "migration_hold",
    "founder_default_switch_review_allowed" => activation_ready,
    "provider_lane" => provider,
    "suite_path" => options[:suite].relative_path_from(ROOT).to_s,
    "suite_sha256" => Digest::SHA256.file(options[:suite]).hexdigest,
    "execution_contract_path" => runtime.fetch("execution_contract_path"),
    "execution_contract_sha256" => Digest::SHA256.file(execution_contract_path).hexdigest,
    "provider_registry_path" => runtime.fetch("provider_registry_path"),
    "provider_registry_sha256" => Digest::SHA256.file(provider_registry_path).hexdigest,
    "resolved_profiles" => resolved_profiles,
    "ready_logical_aliases" => ready_logical_aliases,
    "held_logical_aliases" => held_logical_aliases,
    "registered_media_lane" => {
      "lane_id" => media_lane_id,
      "harness_status" => media_lane_status,
      "promoted_by_nonmedia_activation" => false
    },
    "stages" => fixture.fetch("stages"),
    "nonmedia_provider_stages" => fixture.fetch("nonmedia_provider_stages"),
    "registered_media_generation_handoffs" => fixture.fetch("media_generation_handoffs"),
    "return_checkpoints" => runtime.fetch("required_return_checkpoints"),
    "codex_fallback_count" => fixture.fetch("codex_fallback_count_expected"),
    "live_model_call_count" => fixture.fetch("live_model_call_count_expected"),
    "external_action_count" => fixture.fetch("external_action_count_expected"),
    "generative_action_count" => fixture.fetch("generative_action_count_expected"),
    "unauthorized_media_generation_count" => fixture.fetch("unauthorized_media_generation_count_expected"),
    "registered_media_handoff_count" => fixture.fetch("registered_media_handoff_count_expected")
  }
  if options[:json]
    puts JSON.pretty_generate(result)
  else
    puts "IDOL runtime route shadow: #{result['status']} / #{fixture_id}"
    puts "mode: #{result['mode']} / provider=#{provider} / activation=#{result['activation_status']}"
    puts "stages: #{result['stages'].length} / fallback=#{result['codex_fallback_count']} / live=#{result['live_model_call_count']} / external=#{result['external_action_count']} / generative=#{result['generative_action_count']}"
  end
  exit 0
end

if command == "closeout"
  unless options[:run_root] && options[:output]
    warn "--run-root and --output are required"
    exit 2
  end
  begin
    paths = shadow_closeout_paths(options[:run_root], output: options[:output])
    before_snapshot = shadow_closeout_snapshot(paths)
    unless before_snapshot.fetch(:errors).empty?
      before_snapshot.fetch(:errors).each { |error| warn "ERROR: #{error}" }
      exit 1
    end
    evidence = build_shadow_closeout_evidence(suite, options[:suite], paths, before_snapshot)
    options[:output].write(YAML.dump(evidence))
    after_snapshot = shadow_closeout_snapshot(paths)
    evidence = build_shadow_closeout_evidence(suite, options[:suite], paths, before_snapshot, after_snapshot)
    options[:output].write(YAML.dump(evidence))
    closeout_errors = after_snapshot.fetch(:errors) + validate_shadow_closeout_evidence(evidence, options[:output], suite, options[:suite])
    unless closeout_errors.empty?
      closeout_errors.each { |error| warn "ERROR: #{error}" }
      exit 1
    end
    payload = {
      "status" => evidence["status"],
      "output" => repo_relative_path(options[:output]),
      "policy_id" => evidence.dig("routing_contract", "policy_id"),
      "front_planning_status" => evidence.dig("canonical_state", "front_planning_status"),
      "founder_review_board_status" => evidence.dig("canonical_state", "founder_review_board_status"),
      "canonical_hashes_unchanged" => evidence.dig("verification", "canonical_hashes_unchanged"),
      "downstream_01_opened" => evidence.dig("canonical_state", "downstream_01_opened"),
      "downstream_02a_opened" => evidence.dig("canonical_state", "downstream_02a_opened")
    }
    if options[:json]
      puts JSON.pretty_generate(payload)
    else
      puts "OK: v31 read-only shadow closeout written to #{payload['output']}"
      puts "Front Planning: #{payload['front_planning_status']} / board: #{payload['founder_review_board_status']}"
      puts "canonical hashes unchanged: #{payload['canonical_hashes_unchanged']}"
      puts "01 opened: #{payload['downstream_01_opened']} / 02A opened: #{payload['downstream_02a_opened']}"
    end
    exit 0
  rescue ArgumentError, RuntimeError, Errno::ENOENT => e
    warn "ERROR: #{e.message}"
    exit 1
  end
end

if command == "validate-closeout"
  evidence_path = ARGV.shift
  unless evidence_path
    warn "EVIDENCE is required"
    exit 2
  end
  evidence_path = Pathname.new(evidence_path).expand_path
  evidence = load_doc(evidence_path)
  closeout_errors = validate_shadow_closeout_evidence(evidence, evidence_path, suite, options[:suite])
  unless closeout_errors.empty?
    closeout_errors.each { |error| warn "ERROR: #{error}" }
    exit 1
  end
  payload = {
    "status" => "pass",
    "evidence" => repo_relative_path(evidence_path),
    "policy_id" => evidence.dig("routing_contract", "policy_id"),
    "front_planning_status" => evidence.dig("canonical_state", "front_planning_status"),
    "canonical_hashes_unchanged" => evidence.dig("verification", "canonical_hashes_unchanged"),
    "downstream_absence_preserved" => evidence.dig("verification", "downstream_absence_preserved")
  }
  if options[:json]
    puts JSON.pretty_generate(payload)
  else
    puts "OK: v31 read-only shadow closeout is current and boundary-safe"
  end
  exit 0
end

if command == "policy"
  policy = suite.fetch("operator_profile_policy")
  if options[:json]
    puts JSON.pretty_generate(policy)
  else
    baseline = policy.fetch("current_baseline")
    puts "IDOL active model family: #{policy['active_model_family']}"
    puts "current baseline profile: #{baseline['profile_label']}"
    puts "current baseline descriptor: #{descriptor_summary(baseline)}"
    puts "candidate descriptor: #{policy['candidate_descriptor_source']}"
    puts "status: #{policy['selection_status']}"
    puts "routing policy: #{policy.dig('routing_policy', 'policy_id')}"
    puts "task-shape route classes: #{Array(policy.dig('routing_policy', 'route_classes')).map { |row| row['route_id'] }.join(', ')}"
    puts "evidence boundary: #{policy['current_evidence_boundary']}"
  end
  exit 0
end

if command == "route"
  route_id = ARGV.shift.to_s
  if route_id.empty?
    warn "ROUTE_ID is required"
    exit 2
  end
  routing = routing_policy(suite)
  route = Array(routing["route_classes"]).find { |row| row.is_a?(Hash) && row["route_id"].to_s == route_id }
  unless route
    warn "unknown route id: #{route_id}"
    exit 2
  end
  activation = routing["activation_contract"]
  execution_scope = options[:execution_scope].to_s
  if execution_scope.empty?
    warn "--execution-scope is required for route resolution"
    exit 2
  end
  allowed_scopes = Array(activation["allowed_execution_scopes"]).map(&:to_s)
  unless allowed_scopes.include?(execution_scope)
    warn "invalid execution scope #{execution_scope.inspect}; allowed: #{allowed_scopes.join(', ')}"
    exit 2
  end
  allowed_routes = Array(activation.dig("scope_route_allowlist", execution_scope)).map(&:to_s)
  unless allowed_routes.include?(route_id)
    warn "route #{route_id} is not allowed for execution scope #{execution_scope}; allowed: #{allowed_routes.join(', ')}"
    exit 2
  end
  candidates = [route["default_route"], *Array(route["explicit_alternatives"])]
  selected_route = if options[:select_agent]
                     candidates.find do |candidate|
                       candidate.is_a?(Hash) && candidate["agent_name"].to_s == options[:select_agent].to_s
                     end
                   else
                     route["default_route"]
                   end
  unless selected_route
    allowed_agents = candidates.each_with_object([]) do |candidate, names|
      names << candidate["agent_name"].to_s if candidate.is_a?(Hash)
    end
    warn "agent #{options[:select_agent].inspect} is not registered for route #{route_id}; allowed: #{allowed_agents.join(', ')}"
    exit 2
  end
  selection_kind = selected_route.equal?(route["default_route"]) ? "default" : "explicit_alternative"
  effort = selected_route["model_reasoning_effort"].to_s
  ultra_activation = nil
  if effort == "ultra"
    unless routing.dig("effort_policy", "automatic_ultra_selection_allowed") == false &&
           routing.dig("effort_policy", "ultra_founder_selection_required") == true &&
           routing.dig("effort_policy", "ultra_founder_selection_evidence").to_s == "founder_explicit_current_request"
      warn "Ultra Founder-selection contract is missing or invalid"
      exit 2
    end
    unless options[:founder_selected_ultra]
      warn "Ultra requires --founder-selected-ultra, attesting that the Founder explicitly selected Ultra in the current request"
      exit 2
    end
    allowed_ultra_scopes = Array(routing.dig("effort_policy", "ultra_allowed_execution_scopes")).map(&:to_s)
    allowed_ultra_routes = Array(routing.dig("effort_policy", "ultra_allowed_route_ids")).map(&:to_s)
    unless allowed_ultra_scopes.include?(execution_scope) && allowed_ultra_routes.include?(route_id)
      warn "Ultra is allowed only for registered complete full flow routes; scope=#{execution_scope} route=#{route_id}"
      exit 2
    end
    escalation_trigger = options[:escalation_trigger].to_s
    if escalation_trigger.empty?
      warn "Ultra route #{selected_route['agent_name']} requires --escalation-trigger matching both route #{route_id} and agent"
      exit 2
    end
    route_triggers = Array(route["escalation_triggers"]).map(&:to_s)
    agent_triggers = Array(routing.dig("effort_policy", "ultra_allowed_escalation_triggers_by_agent", selected_route["agent_name"].to_s)).map(&:to_s)
    allowed_triggers = route_triggers & agent_triggers
    unless allowed_triggers.include?(escalation_trigger)
      warn "invalid Ultra escalation trigger #{escalation_trigger.inspect} for route #{route_id} and agent #{selected_route['agent_name']}; allowed: #{allowed_triggers.join(', ')}"
      exit 2
    end
    ultra_activation = {
      "basis" => "founder_explicit_current_request_and_locked_front_planning",
      "trigger" => escalation_trigger
    }
  elsif options[:escalation_trigger] || options[:founder_selected_ultra]
    warn "--founder-selected-ultra and --escalation-trigger are accepted only when selecting an Ultra route"
    exit 2
  end
  if options[:json]
    puts JSON.pretty_generate(
      {
        "policy_id" => routing["policy_id"],
        "routing_active" => true,
        "execution_scope" => execution_scope,
        "route_class" => route,
        "selected_route" => selected_route,
        "selection_kind" => selection_kind,
        "ultra_activation" => ultra_activation
      }
    )
  else
    puts "IDOL model route: #{route_id}"
    puts "routing active: true"
    puts "execution scope: #{execution_scope}"
    puts "purpose: #{route['purpose']}"
    puts "default: #{route_descriptor_tuple(route['default_route']).join(' / ')}"
    Array(route["explicit_alternatives"]).each do |alternative|
      puts "explicit alternative: #{route_descriptor_tuple(alternative).join(' / ')}"
    end
    puts "selected: #{route_descriptor_tuple(selected_route).join(' / ')} (#{selection_kind})"
    puts "Ultra activation: #{ultra_activation['basis']} / #{ultra_activation['trigger']}" if ultra_activation
    puts "output authority: #{route['output_authority']}"
    puts "owner review required for canonical write: #{route['owner_review_required_for_canonical_write']}"
  end
  exit 0
end

if command == "validate"
  result_path = ARGV.shift
  unless result_path
    warn "RESULT is required"
    exit 2
  end
  result_path = Pathname.new(result_path).expand_path
  result = load_doc(result_path)
  errors = validate_result(result, suite, ledger_path: result_path)
  if errors.empty?
    puts "OK: shadow eval result covers #{Array(result['case_results']).length} case(s)"
    exit 0
  end
  errors.each { |error| warn "ERROR: #{error}" }
  exit 1
end

baseline_path = ARGV.shift
candidate_path = ARGV.shift
unless baseline_path && candidate_path
  warn "BASELINE and CANDIDATE are required"
  exit 2
end

baseline_path = Pathname.new(baseline_path).expand_path
candidate_path = Pathname.new(candidate_path).expand_path
baseline = load_doc(baseline_path)
candidate = load_doc(candidate_path)
errors = validate_result(baseline, suite, ledger_path: baseline_path).map { |value| "baseline: #{value}" }
errors.concat(validate_result(candidate, suite, ledger_path: candidate_path).map { |value| "candidate: #{value}" })
errors << "harness_commit differs" unless baseline["harness_commit"] == candidate["harness_commit"]
errors << "harness_snapshot.sha256 differs" unless artifact_ref_sha(baseline["harness_snapshot"]) == artifact_ref_sha(candidate["harness_snapshot"])
errors << "source_snapshot.sha256 differs" unless artifact_ref_sha(baseline["source_snapshot"]) == artifact_ref_sha(candidate["source_snapshot"])
errors << "task_set.sha256 differs" unless artifact_ref_sha(baseline["task_set"]) == artifact_ref_sha(candidate["task_set"])
begin
  baseline_root = canonical_existing_path(resolve_ledger_path(baseline["artifact_root"], baseline_path))
  candidate_root = canonical_existing_path(resolve_ledger_path(candidate["artifact_root"], candidate_path))
  errors << "baseline and candidate artifact_root must differ" if baseline_root == candidate_root
rescue ArgumentError
  # Individual ledger validation already reports the malformed root.
end
shared_case_artifacts = resolved_case_artifact_paths(baseline, baseline_path) & resolved_case_artifact_paths(candidate, candidate_path)
unless shared_case_artifacts.empty?
  errors << "baseline and candidate must not share case artifact paths: #{shared_case_artifacts.join(',')}"
end
profile_policy = suite.fetch("operator_profile_policy")
expected_baseline = profile_policy.fetch("current_baseline")
if profile_policy["enforce_profile_roles_on_compare"] == true
  errors << "baseline profile_label must be #{expected_baseline['profile_label']}" unless baseline["profile_label"].to_s == expected_baseline["profile_label"].to_s
  baseline_profile_descriptor = normalized_descriptor(baseline["profile_descriptor"])
  candidate_profile_descriptor = normalized_descriptor(candidate["profile_descriptor"])
  PROFILE_DESCRIPTOR_FIELDS.each do |field|
    expected = expected_baseline[field].to_s
    actual = baseline_profile_descriptor[field]
    errors << "baseline profile_descriptor.#{field} must be #{expected}" unless actual == expected
  end
  unless candidate_profile_descriptor["profile_role"] == "candidate"
    errors << "candidate profile_descriptor.profile_role must be candidate"
  end
end
if baseline["profile_label"].to_s == candidate["profile_label"].to_s
  errors << "baseline and candidate profile_label must differ"
end
if profile_policy["distinct_operational_descriptors_required"] == true
  baseline_descriptor = normalized_operational_descriptor(baseline["profile_descriptor"])
  candidate_descriptor = normalized_operational_descriptor(candidate["profile_descriptor"])
  if baseline_descriptor == candidate_descriptor
    errors << "baseline and candidate operational descriptors must differ in model_id, agent_name, model_reasoning_effort, execution_surface, or harness_variant"
  end
end
unless errors.empty?
  errors.each { |error| warn "ERROR: #{error}" }
  exit 1
end

dimensions = suite.fetch("quality_dimensions")
hard_gate_ids = Array(suite["hard_gates"])
evidence_ids = Array(suite["evidence_counts"])
thresholds = suite.fetch("thresholds")
baseline_rows = baseline["case_results"].each_with_object({}) { |row, memo| memo[row["case_id"]] = row }
candidate_rows = candidate["case_results"].each_with_object({}) { |row, memo| memo[row["case_id"]] = row }

case_reports = []
quality_failures = []
hard_failures = []
evidence_failures = []
efficiency_misses = []

Array(suite["cases"]).each do |case_def|
  case_id = case_def["case_id"]
  before = baseline_rows.fetch(case_id)
  after = candidate_rows.fetch(case_id)
  before_weighted = weighted_quality(before, dimensions)
  after_weighted = weighted_quality(after, dimensions)

  hard_gate_ids.each do |gate_id|
    hard_failures << "#{case_id}:#{gate_id}" unless after.fetch("hard_gates")[gate_id] == true
  end
  Array(case_def["required_evidence"]).each do |evidence_id|
    evidence_failures << "#{case_id}:required:#{evidence_id}" unless after.fetch("required_evidence")[evidence_id] == true
  end
  dimensions.each_key do |dimension|
    regression = before.fetch("quality_scores")[dimension].to_f - after.fetch("quality_scores")[dimension].to_f
    if regression > thresholds["maximum_dimension_regression"].to_f
      quality_failures << "#{case_id}:#{dimension}:#{regression.round(3)}"
    end
  end
  weighted_regression = before_weighted - after_weighted
  if weighted_regression > thresholds["maximum_case_weighted_regression"].to_f
    quality_failures << "#{case_id}:weighted:#{weighted_regression.round(3)}"
  end
  if after_weighted < thresholds["minimum_candidate_quality"].to_f
    quality_failures << "#{case_id}:minimum_quality:#{after_weighted.round(3)}"
  end
  evidence_ids.each do |evidence_id|
    regression = before.fetch("evidence_counts")[evidence_id].to_i - after.fetch("evidence_counts")[evidence_id].to_i
    if regression > thresholds["maximum_evidence_count_regression"].to_i
      evidence_failures << "#{case_id}:#{evidence_id}:#{regression}"
    end
  end

  before_eff = before.fetch("efficiency")
  after_eff = after.fetch("efficiency")
  input_change = percent_change(before_eff["input_tokens"], after_eff["input_tokens"])
  output_change = percent_change(before_eff["output_tokens"], after_eff["output_tokens"])
  wall_change = percent_change(before_eff["wall_seconds"], after_eff["wall_seconds"])
  tool_change = after_eff["tool_calls"].to_i - before_eff["tool_calls"].to_i
  retry_change = after_eff["retries"].to_i - before_eff["retries"].to_i
  target_input = -thresholds["target_input_token_reduction_percent"].to_f
  target_wall = -thresholds["target_wall_time_reduction_percent"].to_f
  efficiency_misses << "#{case_id}:input_tokens" if input_change && input_change > target_input
  output_increase_exceeds_threshold = if output_change
                                        output_change > thresholds["maximum_output_token_increase_percent"].to_f
                                      else
                                        after_eff["output_tokens"].to_i > before_eff["output_tokens"].to_i
                                      end
  efficiency_misses << "#{case_id}:output_tokens" if output_increase_exceeds_threshold
  efficiency_misses << "#{case_id}:wall_seconds" if wall_change && wall_change > target_wall
  efficiency_misses << "#{case_id}:tool_calls" if tool_change > thresholds["maximum_tool_call_increase"].to_i
  efficiency_misses << "#{case_id}:retries" if retry_change > thresholds["maximum_retry_increase"].to_i

  case_reports << {
    "case_id" => case_id,
    "baseline_quality" => before_weighted.round(3),
    "candidate_quality" => after_weighted.round(3),
    "input_token_change_percent" => input_change&.round(2),
    "output_token_change_percent" => output_change&.round(2),
    "wall_time_change_percent" => wall_change&.round(2),
    "tool_call_change" => tool_change,
    "retry_change" => retry_change
  }
end

decision = if hard_failures.any? || quality_failures.any? || evidence_failures.any?
             "fail"
           elsif efficiency_misses.any?
             "conditional_pass"
           else
             "pass"
           end

report = {
  "decision" => decision,
  "harness_commit" => baseline["harness_commit"],
  "harness_snapshot_sha256" => artifact_ref_sha(baseline["harness_snapshot"]),
  "source_snapshot_sha256" => artifact_ref_sha(baseline["source_snapshot"]),
  "task_set_sha256" => artifact_ref_sha(baseline["task_set"]),
  "baseline_profile" => baseline["profile_label"],
  "candidate_profile" => candidate["profile_label"],
  "baseline_descriptor" => normalized_descriptor(baseline["profile_descriptor"]),
  "candidate_descriptor" => normalized_descriptor(candidate["profile_descriptor"]),
  "quality_failures" => quality_failures,
  "hard_gate_failures" => hard_failures,
  "evidence_failures" => evidence_failures,
  "efficiency_target_misses" => efficiency_misses,
  "cases" => case_reports
}

if options[:json]
  puts JSON.pretty_generate(report)
else
  puts "IDOL Graph Engineering shadow eval: #{decision}"
  puts "graph engineering: #{report['harness_commit']} / snapshot=#{report['harness_snapshot_sha256']}"
  puts "profiles: #{report['baseline_profile']} -> #{report['candidate_profile']}"
  puts "baseline: #{descriptor_summary(report['baseline_descriptor'])}"
  puts "candidate: #{descriptor_summary(report['candidate_descriptor'])}"
  case_reports.each do |row|
    puts "- #{row['case_id']}: quality #{row['baseline_quality']} -> #{row['candidate_quality']}; input #{row['input_token_change_percent']}%; output #{row['output_token_change_percent']}%; wall #{row['wall_time_change_percent']}%; tools #{row['tool_call_change'] >= 0 ? '+' : ''}#{row['tool_call_change']}; retries #{row['retry_change'] >= 0 ? '+' : ''}#{row['retry_change']}"
  end
  (hard_failures + quality_failures + evidence_failures).each { |failure| puts "  failure: #{failure}" }
  efficiency_misses.each { |miss| puts "  efficiency target miss: #{miss}" }
end

exit(decision == "fail" ? 1 : 0)
