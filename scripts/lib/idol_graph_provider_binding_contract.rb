# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "yaml"

module IdolGraphProviderBindingContract
  class ContractError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  REGISTRY_RELATIVE_PATH = "automation/harness-provider-profile-registry.yaml"
  PROVIDER_SOURCES = {
    "grok" => {
      "path" => "automation/providers/grok-build-profiles.yaml",
      "schema_version" => "idol-grok-build-provider-profiles.v1",
      "document_statuses" => %w[active],
      "runtime_surface" => "grok_build_cli_acp"
    },
    "cursor" => {
      "path" => "automation/providers/cursor-agent-profiles.yaml",
      "schema_version" => "idol-cursor-agent-provider-profiles.v2",
      "document_statuses" => %w[active active_with_assignment_holds],
      "runtime_surface" => "cursor_cli_local_physical_chat"
    }
  }.freeze
  DIRECTOR_ROLES = %w[
    overall_director
    creative_development_director
    planning_cdd
    planning_cdd_p1
    planning_cdd_p2
    planning_cdd_p3
    section_cluster_cdd
    edit_director
  ].freeze
  ROLE_NORMALIZATION = {
    "planning_cdd" => "creative_development_director",
    "planning_cdd_p1" => "creative_development_director",
    "planning_cdd_p2" => "creative_development_director",
    "planning_cdd_p3" => "creative_development_director",
    "section_cluster_cdd" => "creative_development_director"
  }.freeze
  ACTIVE_TEXT_ONLY_ROLES = %w[worker mechanical_coordinator].freeze

  module_function

  def resolve!(root:, binding:, studio_role:, registry_path: nil)
    root = Pathname.new(root).expand_path
    raise_contract("invalid_binding", "provider binding must be an object") unless binding.is_a?(Hash)

    provider = binding["registered_provider"].to_s
    raise_contract("direct_codex_forbidden", "direct Codex provider bindings are forbidden in Graph Engineering") if provider == "codex"

    provider_contract = PROVIDER_SOURCES[provider]
    raise_contract("unknown_provider", "Graph provider is not registered for exact resolution: #{provider}") unless provider_contract

    registry_path ||= root.join(REGISTRY_RELATIVE_PATH)
    registry_path = exact_repo_file(root, registry_path, "provider registry")
    registry = load_mapping(registry_path, "provider registry")
    registry_sha = Digest::SHA256.file(registry_path).hexdigest

    logical_alias = binding["logical_profile_alias"].to_s
    logical_profile = registry.dig("logical_profiles", logical_alias)
    unless logical_profile.is_a?(Hash)
      raise_contract("unknown_logical_profile_alias", "logical profile alias is not registered: #{logical_alias}")
    end

    provider_registration = logical_profile.dig("providers", provider)
    unless provider_registration.is_a?(Hash)
      raise_contract("provider_not_registered_for_alias", "#{provider} is not registered for logical profile #{logical_alias}")
    end

    validate_registration!(provider, provider_contract, provider_registration)
    source_path = exact_repo_file(root, provider_registration["source_path"], "#{provider} provider profile source")
    actual_source_sha = Digest::SHA256.file(source_path).hexdigest
    unless actual_source_sha == provider_registration["source_sha256"].to_s
      raise_contract("stale_provider_source_sha", "#{provider} provider profile source SHA-256 is stale")
    end

    source = load_mapping(source_path, "#{provider} provider profile source")
    validate_source_header!(provider, provider_contract, source)
    registered_profile_id = provider_registration["provider_profile_id"].to_s
    profile = source.dig("profiles", registered_profile_id)
    unless profile.is_a?(Hash)
      raise_contract("unknown_provider_profile", "registered provider profile does not resolve: #{registered_profile_id}")
    end

    validate_profile_registration_parity!(provider_registration, profile, registered_profile_id)
    normalized_role = normalize_role(studio_role, logical_alias)
    validate_role_eligibility!(logical_profile, profile, normalized_role, studio_role)
    validate_readiness!(profile, normalized_role, studio_role)

    expected = {
      "registered_provider" => provider,
      "runtime_surface" => source["runtime_surface"],
      "logical_profile_alias" => logical_alias,
      "execution_profile_id" => registered_profile_id,
      "resolved_provider_model" => profile["exact_model"],
      "reasoning_effort" => profile["reasoning_effort"],
      "provider_capability_snapshot_sha256" => registry_sha,
      "fallback_allowed" => false,
      "silent_substitution_allowed" => false
    }
    expected.each do |field, value|
      next if binding[field] == value

      raise_contract("binding_mismatch", "provider binding #{field} differs from the exact registered profile")
    end

    expected.merge(
      "provider_profile_source" => provider_registration["source_path"],
      "provider_profile_source_sha256" => actual_source_sha,
      "provider_profile_snapshot_ref" => "#{REGISTRY_RELATIVE_PATH}#/logical_profiles/#{logical_alias}/providers/#{provider}",
      "capability_status" => profile["capability_status"],
      "harness_status" => profile["harness_status"],
      "full_owner_ready" => profile["full_owner_ready"],
      "normalized_logical_role" => normalized_role
    )
  end

  def load_mapping(path, label)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
            end
    raise_contract("invalid_source", "#{label} must contain an object") unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT => e
    raise_contract("invalid_source", "cannot read #{label}: #{e.message}")
  end

  def exact_repo_file(root, raw, label)
    path = Pathname.new(raw.to_s)
    path = root.join(path) unless path.absolute?
    path = path.expand_path.cleanpath
    raise_contract("missing_source", "#{label} is missing") unless path.file?

    real_root = root.realpath
    real_path = path.realpath
    relative = real_path.relative_path_from(real_root).to_s
    if relative == ".." || relative.start_with?("../")
      raise_contract("source_escape", "#{label} escapes the repository root")
    end

    real_path
  rescue ArgumentError, Errno::ENOENT
    raise_contract("source_escape", "#{label} escapes or is missing from the repository root")
  end

  def validate_registration!(provider, provider_contract, registration)
    unless registration["source_kind"].to_s == "provider_yaml" &&
           registration["source_path"].to_s == provider_contract["path"]
      raise_contract("provider_source_mismatch", "#{provider} registry row does not point to its exact provider YAML")
    end
    unless registration["source_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
      raise_contract("invalid_provider_source_sha", "#{provider} provider profile source SHA-256 is invalid")
    end
    if registration["provider_profile_id"].to_s.empty?
      raise_contract("unknown_provider_profile", "#{provider} provider profile id is missing")
    end
  end

  def validate_source_header!(provider, provider_contract, source)
    valid = source["schema_version"].to_s == provider_contract["schema_version"] &&
            provider_contract["document_statuses"].include?(source["status"].to_s) &&
            source["provider"].to_s == provider &&
            source["runtime_surface"].to_s == provider_contract["runtime_surface"]
    raise_contract("inactive_provider_source", "#{provider} provider profile source header is not exact and active") unless valid
  end

  def validate_profile_registration_parity!(registration, profile, profile_id)
    %w[capability_status harness_status full_owner_ready].each do |field|
      next if registration[field] == profile[field]

      raise_contract("profile_registration_mismatch", "registered #{profile_id} #{field} differs from its provider source")
    end
    if profile["exact_model"].to_s.empty? || profile["reasoning_effort"].to_s.empty?
      raise_contract("incomplete_provider_profile", "registered #{profile_id} lacks exact model or reasoning effort")
    end
    unless profile["unavailable_or_mismatch_action"].to_s == "hold_and_report"
      raise_contract("unsafe_mismatch_action", "registered #{profile_id} must hold and report on mismatch")
    end
  end

  def normalize_role(studio_role, logical_alias)
    role = studio_role.to_s
    raise_contract("missing_studio_role", "studio role is required for provider resolution") if role.empty?

    return "worker" if role == "department_worker" && logical_alias == "worker_high"

    ROLE_NORMALIZATION.fetch(role, role)
  end

  def validate_role_eligibility!(logical_profile, profile, normalized_role, original_role)
    registry_roles = Array(logical_profile["eligible_logical_roles"]).map(&:to_s)
    profile_roles = Array(profile["eligible_logical_roles"]).map(&:to_s)
    return if registry_roles.include?(normalized_role) && profile_roles.include?(normalized_role)

    raise_contract("role_not_eligible", "studio role #{original_role} is not eligible for the resolved logical/provider profile")
  end

  def validate_readiness!(profile, normalized_role, original_role)
    unless profile["capability_status"].to_s == "founder_verified"
      raise_contract("profile_not_founder_verified", "resolved provider profile is not Founder-verified")
    end

    harness_status = profile["harness_status"].to_s
    active_for_role = harness_status == "active" ||
                      (harness_status == "active_text_only" && ACTIVE_TEXT_ONLY_ROLES.include?(normalized_role))
    unless active_for_role
      raise_contract("profile_not_active_for_role", "resolved provider profile is not active for studio role #{original_role}")
    end

    if DIRECTOR_ROLES.include?(original_role.to_s) && profile["full_owner_ready"] != true
      raise_contract("director_full_owner_not_ready", "Director role #{original_role} requires full_owner_ready=true")
    end
  end

  def raise_contract(code, message)
    raise ContractError.new(code, message)
  end
end
