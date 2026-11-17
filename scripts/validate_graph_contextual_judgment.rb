#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_graph_goal_evidence_contract"
require_relative "lib/idol_graph_output_manifest_contract"
require_relative "lib/idol_role_context_pack"
require_relative "lib/idol_graph_criterion_evidence_contract"

SCRIPT_ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = SCRIPT_ROOT.join("scripts", "idol-video-python")

STABLE_DISPATCH_IDENTITY_FIELDS = %w[
  dispatch_id
  input_digest_sha256
  run
  lane_id
  section_cohort_id
  section_ids
  logical_role
  assigned_owner
  output_writer
  reviewer
  return_recipient
].freeze

options = {root: SCRIPT_ROOT, mode: "active_promotion"}
OptionParser.new do |parser|
  parser.banner = "usage: validate_graph_contextual_judgment.rb [--root PATH] [--mode active_promotion|historical_audit|profile_evolution_evidence] PATH"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path.cleanpath }
  parser.on("--mode MODE", %w[active_promotion historical_audit profile_evolution_evidence]) { |value| options[:mode] = value }
end.parse!
path_arg = ARGV.shift
abort "usage: validate_graph_contextual_judgment.rb [--root PATH] [--mode active_promotion|historical_audit|profile_evolution_evidence] PATH" if path_arg.to_s.empty? || ARGV.any?

artifact_path = Pathname.new(path_arg)
artifact_path = options[:root].join(artifact_path) unless artifact_path.absolute?
abort "graph contextual judgment is missing" unless artifact_path.file?

registry_path = options[:root].join("automation", "graph-creative-judgment-registry.yaml")
registry_schema = options[:root].join("schemas", "graph-creative-judgment-registry.schema.json")
artifact_schema = options[:root].join("schemas", "graph-contextual-judgment.schema.json")
begin
  version_probe = artifact_path.extname.downcase == ".json" ? JSON.parse(artifact_path.read) : YAML.safe_load(artifact_path.read, aliases: true)
rescue JSON::ParserError, Psych::Exception => e
  abort "graph contextual judgment cannot parse: #{e.message}"
end
legacy_judgment = version_probe.is_a?(Hash) && version_probe["schema_version"] == "idol_graph_contextual_judgment.v1"
if legacy_judgment
  abort "contextual judgment v1 is historical only; new authoring requires v2 typed criterion evidence" unless options[:mode] == "historical_audit"
  artifact_schema = options[:root].join("schemas", "graph-contextual-judgment-v1-legacy.schema.json")
end
profile_release_schema = options[:root].join("schemas", "graph-creative-judgment-profile-release.schema.json")
dispatch_schema = options[:root].join("schemas", "graph-department-dispatch.schema.json")
role_context_pack_schema = options[:root].join("schemas", "role-context-pack.schema.json")
schema_validator = options[:root].join("scripts", "validate_json_schema.py")

schema_inputs = [[artifact_schema, artifact_path]]
schema_inputs.unshift([registry_schema, registry_path]) if options[:mode] == "active_promotion"
schema_inputs.each do |schema, instance|
  stdout, stderr, status = Open3.capture3(PYTHON.to_s, schema_validator.to_s, schema.to_s, instance.to_s, chdir: options[:root].to_s)
  abort [stderr, stdout].join("\n").strip unless status.success?
end

load_document = lambda do |path|
  path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, aliases: true)
end
canonical_value = lambda do |value|
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) { |key, memo| memo[key] = canonical_value.call(value[key]) }
  when Array
    value.map { |item| canonical_value.call(item) }
  else
    value
  end
end
structured_sha256 = ->(value) { Digest::SHA256.hexdigest(JSON.generate(canonical_value.call(value))) }
repo_file = lambda do |raw_path, label, errors|
  raw = Pathname.new(raw_path.to_s)
  if raw_path.to_s.empty? || raw.absolute?
    errors << "#{label} path must be repository-relative"
    next nil
  end
  candidate = options[:root].join(raw).expand_path.cleanpath
  unless candidate.file?
    errors << "#{label} path is missing: #{raw_path}"
    next nil
  end
  begin
    real_root = options[:root].realpath
    candidate = candidate.realpath
    relative = candidate.relative_path_from(real_root).to_s
    if relative == ".." || relative.start_with?("../")
      errors << "#{label} path escapes repository"
      next nil
    end
  rescue ArgumentError, Errno::ENOENT
    errors << "#{label} path escapes repository"
    next nil
  end
  candidate
end
verify_pointer = lambda do |pointer, label, errors|
  unless pointer.is_a?(Hash)
    errors << "#{label} pointer is missing"
    next nil
  end
  path = repo_file.call(pointer["path"], label, errors)
  next nil unless path
  actual = Digest::SHA256.file(path).hexdigest
  errors << "#{label} SHA-256 is stale: #{pointer['path']}" unless actual == pointer["sha256"].to_s
  path
end
resolve_pointer = lambda do |value, pointer, label, errors|
  current = value
  pointer.to_s.split("/").drop(1).each do |token|
    token = token.gsub("~1", "/").gsub("~0", "~")
    if current.is_a?(Hash) && current.key?(token)
      current = current[token]
    elsif current.is_a?(Array) && token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < current.length
      current = current[token.to_i]
    else
      errors << "#{label} JSON pointer does not resolve: #{pointer}"
      next nil
    end
  end
  current
end
pointer_terminal_field = lambda do |pointer|
  pointer.to_s.split("/").last.to_s.gsub("~1", "/").gsub("~0", "~")
end
registry = load_document.call(registry_path)
document = load_document.call(artifact_path)
errors = []
execution = document["execution_binding"].to_h
if options[:mode] == "active_promotion"
  begin
    IdolRoleContextPack.validate_graph_judgment_registry!(root: options[:root], registry: registry)
  rescue IdolRoleContextPack::ContractError => e
    errors << "graph creative judgment registry failed semantic validation: #{e.message}"
  end
end

profiles = Array(registry["profiles"])
duplicate_profile_ids = profiles.group_by { |row| row.to_h["profile_id"].to_s }.select { |_id, rows| rows.length > 1 }.keys
errors << "judgment registry contains duplicate profile ids: #{duplicate_profile_ids.join(', ')}" unless duplicate_profile_ids.empty?
profile = nil
policy = nil
if execution["profile_release"].is_a?(Hash)
  begin
    release = IdolRoleContextPack.bound_graph_judgment_profile_release(
      root: options[:root],
      pointer: execution["profile_release"],
      expected_profile_id: document["profile_id"]
    )
    profile = release.fetch("profile")
    policy = release.fetch("policy")
    release_path = repo_file.call(execution.dig("profile_release", "path"), "execution profile release", errors)
    if release_path
      stdout, stderr, status = Open3.capture3(
        PYTHON.to_s,
        schema_validator.to_s,
        profile_release_schema.to_s,
        release_path.to_s,
        chdir: options[:root].to_s
      )
      errors << "execution profile release failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
    end
    if options[:mode] == "active_promotion"
      current_pointer = registry.to_h.dig("current_profile_releases", document["profile_id"].to_s).to_h.slice("path", "sha256")
      unless current_pointer == execution["profile_release"].to_h.slice("path", "sha256")
        errors << "historical profile release cannot open an active promotion edge"
      end
    end
  rescue IdolRoleContextPack::ContractError => e
    errors << "execution profile release is invalid: #{e.message}"
  end
else
  errors << "execution profile_release is required"
end

policy ||= {}
applicability_rules = policy.fetch("applicability_rules", {})
performance_mode_evidence_fields = Array(policy["performance_mode_evidence_fields"])

if profile
  profile = profile.to_h
  errors << "stage_id is outside the judgment profile" unless Array(profile["stages"]).include?(document["stage_id"])
  errors << "checkpoint_id is outside the judgment profile" unless Array(profile["checkpoints"]).include?(document["checkpoint_id"])
  errors << "reviewer_role is outside the judgment profile" unless Array(profile["owner_roles"]).include?(document["reviewer_role"])
  errors << "target_message_treatment must exact-copy the profile" unless document["target_message_treatment"] == profile["target_message_treatment"]

  profile_criteria = Array(profile["criteria"])
  rows = Array(document["criteria"])
  ids = rows.map { |row| row.to_h["criterion_id"].to_s }
  expected_ids = profile_criteria.map { |row| row.to_h["criterion_id"].to_s }
  errors << "criteria must exact-cover the bound profile once" unless ids.sort == expected_ids.sort && ids.uniq.length == ids.length
  by_id = rows.to_h { |row| [row.to_h["criterion_id"].to_s, row.to_h] }
  tags = Array(document["applicability_tags"]).map(&:to_s)
  applicability_rows = Array(document["applicability_evidence"])
  applicability_tags = applicability_rows.map { |row| row.to_h["tag"].to_s }
  errors << "applicability_evidence must exact-cover applicability_tags once" unless applicability_tags.sort == tags.sort && applicability_tags.uniq.length == applicability_tags.length
  source_paths = Array(document["source_artifacts"]).map { |row| row.to_h["path"].to_s }
  applicability_rows.each_with_index do |row, index|
    row = row.to_h
    label = "applicability_evidence[#{index}]"
    unless source_paths.include?(row["source_path"].to_s)
      errors << "#{label} must bind a declared source_artifact"
      next
    end
    source_path = repo_file.call(row["source_path"], label, errors)
    next unless source_path
    begin
      source = load_document.call(source_path)
    rescue JSON::ParserError, Psych::Exception => e
      errors << "#{label} source is not structured evidence: #{e.message}"
      next
    end
    value = resolve_pointer.call(source, row["json_pointer"], label, errors)
    next if value.nil?
    errors << "#{label} value SHA-256 is stale" unless structured_sha256.call(value) == row["value_sha256"].to_s
    errors << "#{label} expected_value differs from the exact source value" unless value == row["expected_value"]
    rule = applicability_rules[row["tag"].to_s]
    if rule.nil?
      errors << "#{label} tag is not registered for typed applicability evidence"
      next
    end
    unless row["evidence_kind"].to_s == rule.fetch("evidence_kind").to_s
      errors << "#{label} evidence_kind differs from the registered tag kind"
    end
    unless Array(rule.fetch("fields")).include?(pointer_terminal_field.call(row["json_pointer"]))
      errors << "#{label} JSON pointer does not end at an allowed typed evidence field"
    end
    unless Array(rule.fetch("values")).include?(value)
      errors << "#{label} source value is not allowed for its applicability tag"
    end
  end

  performance_mode = document["performance_mode"].to_s
  performance_evidence = document["performance_mode_evidence"]
  performance_criterion = profile_criteria.any? { |criterion| criterion.to_h["criterion_id"].to_s == "performance_readability" }
  if performance_criterion && performance_mode == "none" && !tags.include?("no_performance_job")
    errors << "performance_mode none requires exact no_performance_job applicability evidence"
  end
  if tags.include?("no_performance_job") && performance_mode != "none"
    errors << "no_performance_job applicability evidence conflicts with performance_mode"
  end
  if %w[supporting primary].include?(performance_mode) && !performance_evidence.is_a?(Hash)
    errors << "supporting or primary performance_mode requires exact source evidence"
  end
  if performance_evidence.is_a?(Hash)
    label = "performance_mode_evidence"
    unless source_paths.include?(performance_evidence["source_path"].to_s)
      errors << "#{label} must bind a declared source_artifact"
    else
      source_path = repo_file.call(performance_evidence["source_path"], label, errors)
      if source_path
        begin
          source = load_document.call(source_path)
          value = resolve_pointer.call(source, performance_evidence["json_pointer"], label, errors)
          unless value.nil?
            errors << "#{label} value SHA-256 is stale" unless structured_sha256.call(value) == performance_evidence["value_sha256"].to_s
            errors << "#{label} expected_value differs from the exact source value" unless value == performance_evidence["expected_value"]
            errors << "#{label} must exact-bind performance_mode" unless value.to_s == performance_mode
          end
        rescue JSON::ParserError, Psych::Exception => e
          errors << "#{label} source is not structured evidence: #{e.message}"
        end
      end
    end
    unless performance_evidence["evidence_kind"].to_s == "performance_mode"
      errors << "#{label} evidence_kind must be performance_mode"
    end
    unless performance_mode_evidence_fields.include?(pointer_terminal_field.call(performance_evidence["json_pointer"]))
      errors << "#{label} JSON pointer does not end at an allowed typed performance field"
    end
  end

  profile_criteria.each do |criterion|
    criterion = criterion.to_h
    id = criterion["criterion_id"].to_s
    row = by_id[id].to_h
    result = row["result"]
    applies_when = criterion["applies_when"].to_s
    condition_applies = applies_when.empty? || tags.include?(applies_when)
    permitted_na = criterion["not_applicable"].to_s

    if result == "not_applicable"
      allowed = !condition_applies ||
        (!permitted_na.empty? && permitted_na == "no_performance_job" && document["performance_mode"] == "none") ||
        (!permitted_na.empty? && tags.include?(permitted_na))
      errors << "#{id} cannot be not_applicable in this scope" unless allowed
      next
    end
    if !condition_applies
      errors << "#{id} must be not_applicable when #{applies_when} is absent"
      next
    end
    if id == "performance_readability" && document["performance_mode"] == "none"
      errors << "performance_readability must be not_applicable when performance_mode is none"
    end
    next unless result.is_a?(Integer)

    if document["decision"] == "eligible_for_director_review" && condition_applies && result < criterion["minimum"].to_i
      errors << "#{id} must be at least grade #{criterion['minimum']} for Director review eligibility"
    end
    if document["decision"] == "eligible_for_director_review" && criterion["critical_four"] == true && condition_applies && result != 4
      errors << "#{id} is a critical grade-4 criterion"
    end
  end

  numeric_rows = profile_criteria.map do |criterion|
    row = by_id[criterion.to_h["criterion_id"].to_s].to_h
    result = row["result"]
    result.is_a?(Integer) ? [criterion.to_h, result] : nil
  end.compact
  hard_gates = Array(document["hard_gate_findings"])
  decision = document["decision"].to_s
  if hard_gates.any?
    errors << "hard-gate findings require hold" unless decision == policy.dig("grade_routing", "hard_gate")
  elsif numeric_rows.any? { |_criterion, result| result == 0 }
    errors << "grade 0 requires hold" unless decision == policy.dig("grade_routing", "grade_zero")
  elsif numeric_rows.any? { |_criterion, result| result == 1 }
    errors << "grade 1 requires reject" unless decision == policy.dig("grade_routing", "grade_one")
  else
    below_floor = numeric_rows.any? do |criterion, result|
      result < criterion["minimum"].to_i || (criterion["critical_four"] == true && result != 4)
    end
    if below_floor
      allowed = Array(policy.dig("grade_routing", "grade_two_or_below_profile_floor"))
      errors << "below-floor grade requires bounded correction or hold" unless allowed.include?(decision)
    elsif decision != policy.dig("grade_routing", "all_applicable_floors_and_critical_fours")
      errors << "all applicable floors require eligible_for_director_review"
    end
  end
end

assignment_id = execution["assignment_id"].to_s
errors << "scope_id must exact-bind execution assignment_id" unless document["scope_id"].to_s == assignment_id
errors << "execution author_role must exact-bind reviewer_role" unless execution["author_role"].to_s == document["reviewer_role"].to_s
if profile
  profile_hash = structured_sha256.call(profile)
  errors << "execution profile_value_sha256 differs from the registered profile" unless execution["profile_value_sha256"].to_s == profile_hash
end

dispatch_path = verify_pointer.call(execution["dispatch"], "execution dispatch", errors)
pack_path = verify_pointer.call(execution["role_context_pack"], "execution Role Context Pack", errors)
manifest_path = verify_pointer.call(execution["output_manifest"], "evaluated output manifest", errors)

dispatch = nil
verified_manifest = nil
if dispatch_path
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    schema_validator.to_s,
    dispatch_schema.to_s,
    dispatch_path.to_s,
    chdir: options[:root].to_s
  )
  errors << "execution dispatch failed Graph Department Dispatch schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  begin
    dispatch = load_document.call(dispatch_path)
    errors << "execution dispatch schema_version is not current" unless dispatch["schema_version"].to_s == "idol-graph-department-dispatch.v1"
    errors << "execution dispatch artifact_type is not graph_department_dispatch" unless dispatch["artifact_type"].to_s == "graph_department_dispatch"
    errors << "execution dispatch must be an immutable returned snapshot before judgment" unless dispatch["lifecycle_state"].to_s == "returned"
    errors << "execution dispatch_id differs from assignment_id" unless dispatch["dispatch_id"].to_s == assignment_id
    errors << "execution judgment profile differs from dispatch" unless dispatch["judgment_profile_id"].to_s == document["profile_id"].to_s
    errors << "execution goal_id differs from dispatch Goal" unless dispatch.dig("goal_evidence", "native_goal_id").to_s == execution["goal_id"].to_s
    unless dispatch.dig("goal_evidence", "goal_terminal_event_sha256").to_s == execution["goal_terminal_event_sha256"].to_s
      errors << "execution Goal terminal event differs from dispatch"
    end
    begin
      IdolGraphGoalEvidenceContract.verify!(
        root: options[:root],
        provider_binding: dispatch["provider_binding"],
        goal_evidence: dispatch["goal_evidence"],
        validation_mode: options[:mode]
      )
    rescue IdolGraphGoalEvidenceContract::ContractError => e
      errors << "execution Dispatch Goal terminal event failed exact verification (#{e.code}): #{e.message}"
    end
    errors << "execution input digest differs from dispatch" unless dispatch["input_digest_sha256"].to_s == execution["input_digest_sha256"].to_s
    unless dispatch["output_manifest"].to_h.slice("path", "sha256") == execution["output_manifest"].to_h.slice("path", "sha256")
      errors << "execution output manifest differs from dispatch"
    end
    writer_session_id = dispatch.dig("output_writer", "session_id").to_s
    errors << "execution dispatch output_writer.session_id is missing" if writer_session_id.empty?
    unless writer_session_id == execution["author_session_id"].to_s
      errors << "execution author_session_id differs from dispatch output_writer.session_id"
    end

    begin
      verified_manifest = IdolGraphOutputManifestContract.verify!(
        root: options[:root],
        pointer: execution["output_manifest"],
        dispatch: dispatch
      )
    rescue IdolGraphOutputManifestContract::ContractError => e
      errors << "evaluated output manifest failed full verification (#{e.code}): #{e.message}"
    end
  rescue JSON::ParserError, Psych::Exception => e
    errors << "execution dispatch is not structured: #{e.message}"
  end
end

if pack_path
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    schema_validator.to_s,
    role_context_pack_schema.to_s,
    pack_path.to_s,
    chdir: options[:root].to_s
  )
  errors << "execution Role Context Pack failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  begin
    pack = load_document.call(pack_path)
    pack_errors = IdolRoleContextPack.validate_pack(
      root: options[:root],
      pack: pack,
      validation_mode: options[:mode]
    )
    unless pack_errors.empty?
      errors << "execution Role Context Pack failed full projection validation: #{pack_errors.join('; ')}"
    end
    errors << "Role Context Pack schema_version is not current" unless pack["schema_version"].to_s == "idol-role-context-pack.v1"
    errors << "Role Context Pack must be pass before judgment" unless pack["status"].to_s == "pass"
    errors << "Role Context Pack must be an admitted Graph v2 pack" unless pack.dig("activation_binding", "writer").to_s == "graph_v2"
    unless pack.dig("projection", "registry_path").to_s == IdolRoleContextPack::GRAPH_PROJECTION_REGISTRY_RELATIVE &&
           pack.dig("projection", "profile_registry_path").to_s == IdolRoleContextPack::GRAPH_PROFILE_REGISTRY_RELATIVE
      errors << "Role Context Pack must use the current Graph projection and profile registries"
    end
    errors << "Role Context Pack assignment differs from judgment" unless pack.dig("identity", "assignment_id").to_s == assignment_id
    errors << "Role Context Pack checkpoint differs from judgment" unless pack.dig("identity", "checkpoint_id").to_s == document["checkpoint_id"].to_s
    errors << "Role Context Pack stage differs from judgment" unless pack.dig("identity", "stage_id").to_s == document["stage_id"].to_s
    errors << "Role Context Pack role differs from judgment" unless pack.dig("identity", "role").to_s == document["reviewer_role"].to_s
    errors << "Role Context Pack judgment profile differs" unless pack.dig("creative_judgment_contract", "profile_id").to_s == document["profile_id"].to_s
    unless pack.dig("creative_judgment_contract", "profile_value_sha256").to_s == execution["profile_value_sha256"].to_s
      errors << "Role Context Pack judgment profile hash differs"
    end
    if pack.dig("creative_judgment_contract", "profile_release").is_a?(Hash) && !execution["profile_release"].is_a?(Hash)
      errors << "released Role Context Pack requires execution profile_release"
    end
    if execution["profile_release"].is_a?(Hash) &&
       pack.dig("creative_judgment_contract", "profile_release").to_h.slice("path", "sha256") != execution["profile_release"].to_h.slice("path", "sha256")
      errors << "Role Context Pack judgment profile release differs"
    end
    if dispatch
      expected_stable_dispatch_identity = {
        "dispatch_id" => dispatch["dispatch_id"],
        "input_digest_sha256" => dispatch["input_digest_sha256"],
        "run" => dispatch["run"],
        "lane_id" => dispatch["lane_id"],
        "section_cohort_id" => dispatch["section_cohort_id"],
        "section_ids" => dispatch["section_ids"],
        "logical_role" => dispatch["logical_role"],
        "assigned_owner" => dispatch["assigned_owner"],
        "output_writer" => dispatch["output_writer"],
        "reviewer" => dispatch["reviewer"],
        "return_recipient" => dispatch["return_recipient"]
      }
      projected_dispatch_identity = pack["graph_dispatch_identity"]
      unless projected_dispatch_identity.is_a?(Hash)
        errors << "Role Context Pack graph_dispatch_identity is required for judgment validation"
      else
        projected_lifecycle = projected_dispatch_identity["dispatch_lifecycle_state_at_projection"].to_s
        unless %w[prepared launched].include?(projected_lifecycle)
          errors << "Role Context Pack judgment identity must come from a prepared or launched Dispatch snapshot"
        end
        projected_stable_identity = projected_dispatch_identity.slice(*STABLE_DISPATCH_IDENTITY_FIELDS)
        unless canonical_value.call(projected_stable_identity) == canonical_value.call(expected_stable_dispatch_identity)
          errors << "Role Context Pack stable dispatch identity differs from the returned execution Dispatch"
        end
      end
      errors << "Role Context Pack run differs from dispatch" unless pack.dig("identity", "run_root").to_s == dispatch["run"].to_s
      unless Array(pack.dig("identity", "section_ids")).map(&:to_s) == Array(dispatch["section_ids"]).map(&:to_s)
        errors << "Role Context Pack section scope differs from dispatch"
      end
      provider = pack["provider_binding"].to_h
      dispatch_provider = dispatch["provider_binding"].to_h
      provider_pairs = {
        "provider" => "registered_provider",
        "runtime_surface" => "runtime_surface",
        "logical_profile_alias" => "logical_profile_alias",
        "provider_profile_id" => "execution_profile_id",
        "exact_model" => "resolved_provider_model",
        "reasoning_effort" => "reasoning_effort"
      }
      provider_pairs.each do |pack_field, dispatch_field|
        unless provider[pack_field].to_s == dispatch_provider[dispatch_field].to_s
          errors << "Role Context Pack provider #{pack_field} differs from dispatch #{dispatch_field}"
        end
      end
      unless provider["registry_sha256"].to_s == dispatch_provider["provider_capability_snapshot_sha256"].to_s
        errors << "Role Context Pack provider registry snapshot differs from dispatch provider capability snapshot"
      end
      unless provider["fallback_policy"].to_s == "forbidden" &&
             dispatch_provider["fallback_allowed"] == false &&
             dispatch_provider["silent_substitution_allowed"] == false
        errors << "Role Context Pack and dispatch provider fallback boundaries differ"
      end
    end
  rescue JSON::ParserError, Psych::Exception => e
    errors << "Role Context Pack is not structured: #{e.message}"
  end
end

source_bindings = []
Array(document["source_artifacts"]).each_with_index do |source, index|
  raw_path = source.to_h["path"].to_s
  candidate = repo_file.call(raw_path, "source_artifacts[#{index}]", errors)
  next unless candidate
  actual = Digest::SHA256.file(candidate).hexdigest
  errors << "source_artifacts[#{index}] SHA-256 is stale: #{raw_path}" unless actual == source.to_h["sha256"].to_s
  relative = candidate.relative_path_from(options[:root].realpath).to_s
  source_bindings << [relative, source.to_h["sha256"].to_s]
end
if source_bindings.uniq.length != source_bindings.length
  errors << "source_artifacts must not repeat the same verified output"
end
if verified_manifest
  output_bindings = verified_manifest.fetch("outputs").map { |row| [row.fetch("path"), row.fetch("sha256")] }
  outside_manifest = source_bindings.reject { |binding| output_bindings.include?(binding) }
  unless outside_manifest.empty?
    errors << "source_artifacts must be an exact subset of the fully verified output manifest"
  end
end

expected_edge = policy.dig("decision_edges", document["decision"].to_s)
errors << "next_edge must exact-copy the registered decision edge" unless document["next_edge"] == expected_edge
expected_status = policy.dig("decision_status", document["decision"].to_s)
errors << "status must exact-copy the registered decision status" unless document["status"] == expected_status

Array(document["criteria"]).each do |row|
  row = row.to_h
  %w[observable_claim screen_consequence preserve change do_not_infer correction_action acceptance_evidence].each do |field|
    errors << "#{row['criterion_id']} #{field} is missing" if row[field].to_s.strip.empty?
  end
end

unless legacy_judgment
  expected_cut_images = nil
  if document["profile_id"].to_s == "pixel_02b" && verified_manifest && manifest_path
    begin
      derived_cut_images = IdolGraphCriterionEvidenceContract.expected_cut_images_from_authentic_manifest(
        root: options[:root],
        manifest: load_document.call(manifest_path),
        section_ids: dispatch && dispatch["section_ids"]
      )
      if options[:mode] == "active_promotion" && derived_cut_images.empty?
        errors << "pixel_02b requires Cut image targets from hash-bound generated image outputs or idol_generated_branch_cut_review.v4 branch_cut_reviews image_path/image_sha256"
      elsif !derived_cut_images.empty?
        expected_cut_images = derived_cut_images
      end
    rescue IdolGraphCriterionEvidenceContract::ContractError => e
      errors << e.message
    end
  end
  begin
    IdolGraphCriterionEvidenceContract.verify!(
      root: options[:root],
      document: document,
      expected_cut_images: expected_cut_images
    )
  rescue IdolGraphCriterionEvidenceContract::ContractError => e
    errors << e.message
  end
end

abort errors.join("\n") unless errors.empty?
display_path = artifact_path.relative_path_from(options[:root]) rescue artifact_path
if options[:mode] == "historical_audit"
  puts "graph contextual judgment historical audit valid; promotion forbidden: #{display_path}"
elsif options[:mode] == "profile_evolution_evidence"
  puts "graph contextual judgment candidate-profile evolution evidence valid; promotion remains external: #{display_path}"
else
  puts "graph contextual judgment active-promotion validation valid: #{display_path}"
end
