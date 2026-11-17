# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "yaml"

module IdolImageExecutionLaneContract
  class ContractError < StandardError; end

  NONSECRET_CHILD_ENV = {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil}.freeze
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze

  REQUESTS = %w[
    current_session_native
    openai_api_gpt_image_2
    grok_build_oauth_subscription
    xai_api_media
  ].freeze
  SESSION_PROVIDERS = %w[codex grok_build].freeze
  ORIGINS = %w[founder_omitted_current_session_default founder_explicit].freeze

  module_function

  def load_mapping(path, label)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
            end
    raise ContractError, "#{label} must contain an object" unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT => e
    raise ContractError, "cannot read #{label}: #{e.message}"
  end

  def exact_repo_file(root, raw, label)
    root = Pathname.new(root).expand_path
    path = Pathname.new(raw.to_s)
    path = root.join(path) unless path.absolute?
    path = path.expand_path.cleanpath
    raise ContractError, "#{label} is missing" unless path.file?

    real_root = root.realpath
    real_path = path.realpath
    relative = real_path.relative_path_from(real_root).to_s
    raise ContractError, "#{label} escapes the repository root" if relative == ".." || relative.start_with?("../")

    real_path
  rescue ArgumentError, Errno::ENOENT
    raise ContractError, "#{label} escapes or is missing from the repository root"
  end

  def resolve_selection!(selection)
    raise ContractError, "run execution selection must be an object" unless selection.is_a?(Hash)

    request = selection["image_execution_request"].to_s
    origin = selection["image_execution_request_origin"].to_s
    creative_provider = selection["creative_role_provider"].to_s
    session_provider = selection["image_execution_session_provider"].to_s
    lane = selection["image_execution_lane"].to_s
    raise ContractError, "image execution request is not registered" unless REQUESTS.include?(request)
    raise ContractError, "image execution request origin is invalid" unless ORIGINS.include?(origin)
    raise ContractError, "creative role provider is invalid" unless SESSION_PROVIDERS.include?(creative_provider)
    raise ContractError, "image execution session provider is invalid" unless SESSION_PROVIDERS.include?(session_provider)
    if origin == "founder_omitted_current_session_default" && request != "current_session_native"
      raise ContractError, "a provider-omitted request must resolve only to current_session_native"
    end
    if request == "current_session_native" && creative_provider != session_provider
      raise ContractError, "current-session native image execution must use the exact current creative assignment provider"
    end

    expected_lane = case request
                    when "current_session_native"
                      session_provider == "codex" ? "codex_session_native" : "grok_build_oauth_subscription"
                    else
                      request
                    end
    raise ContractError, "resolved image execution lane differs from the exact request/session provider" unless lane == expected_lane
    raise ContractError, "image execution fallback must be none" unless selection["automatic_fallback"].to_s == "none"

    {
      "request" => request,
      "origin" => origin,
      "creative_provider" => creative_provider,
      "session_provider" => session_provider,
      "lane" => lane,
      "adapter" => {
        "codex_session_native" => "codex_imagegen",
        "openai_api_gpt_image_2" => "openai_api_gpt_image_2",
        "grok_build_oauth_subscription" => "grok_image",
        "xai_api_media" => "xai_api_media"
      }.fetch(lane)
    }
  end

  def verify_execution_shape!(selection:, execution:, attachment_count:)
    resolved = resolve_selection!(selection)
    raise ContractError, "packet execution must be an object" unless execution.is_a?(Hash)
    raise ContractError, "packet adapter differs from resolved image lane" unless execution["execution_adapter_id"].to_s == resolved["adapter"]

    expected = case resolved["adapter"]
               when "codex_imagegen"
                 {
                   "provider" => "codex",
                   "provider_model_or_tool" => "codex_imagegen",
                   "selected_native_tool" => "imagegen",
                   "auth_lane" => "codex_session"
                 }
               when "openai_api_gpt_image_2"
                 {
                   "provider" => "openai",
                   "provider_model_or_tool" => "gpt-image-2",
                   "selected_native_tool" => nil,
                   "auth_lane" => "founder_approved_api"
                 }
               when "grok_image"
                 {
                   "provider" => "xai_grok_build",
                   "provider_model_or_tool" => "grok_image",
                   "selected_native_tool" => attachment_count.to_i.positive? ? "image_edit" : "image_gen",
                   "auth_lane" => "subscription_oauth"
                 }
               when "xai_api_media"
                 {
                   "provider" => "xai_api",
                   "selected_native_tool" => nil,
                   "auth_lane" => "founder_approved_api"
                 }
               end
    expected.each do |field, value|
      raise ContractError, "#{resolved['adapter']} execution #{field} differs from its provider-native contract" unless execution[field] == value
    end
    raise ContractError, "provider-specific image execution may not rewrite prompts" unless execution["prompt_rewrite_policy"].to_s == "forbidden"
    raise ContractError, "provider-specific image execution may not fall back" unless execution["automatic_fallback"].to_s == "none"
    resolved
  end

  def verify_registered_native_profile!(root:, selection:, execution:, attachment_count:, registry_path: nil)
    resolved = verify_execution_shape!(selection: selection, execution: execution, attachment_count: attachment_count)
    return resolved unless %w[codex_imagegen grok_image].include?(resolved["adapter"])

    root = Pathname.new(root).expand_path
    registry_path ||= root.join("automation/harness-provider-profile-registry.yaml")
    registry_path = exact_repo_file(root, registry_path, "provider registry")
    registry = load_mapping(registry_path, "provider registry")
    lane_key = resolved["lane"]
    lane = registry.dig("media_lanes", lane_key)
    raise ContractError, "#{lane_key} provider-native media lane is missing" unless lane.is_a?(Hash)

    required_lane = {
      "capability_status" => resolved["adapter"] == "codex_imagegen" ? "active" : "founder_verified",
      (resolved["adapter"] == "grok_image" ? "image_harness_status" : "harness_status") => "active",
      "image_adapter_id" => resolved["adapter"],
      "default_enabled" => true,
      "native_default_scope" => "exact_current_assignment_provider_only",
      "current_session_provider_match_required" => true,
      "cross_provider_tool_aliasing" => "forbidden",
      "automatic_fallback" => "none"
    }
    required_lane.each do |field, expected|
      raise ContractError, "#{lane_key} #{field} differs from the active provider-native binding" unless lane[field] == expected
    end

    profile_path = exact_repo_file(root, lane["provider_profile_source"], "#{lane_key} provider profile source")
    actual_profile_sha = Digest::SHA256.file(profile_path).hexdigest
    raise ContractError, "#{lane_key} provider profile source SHA-256 is stale" unless actual_profile_sha == lane["provider_profile_source_sha256"].to_s
    registry_sha = Digest::SHA256.file(registry_path).hexdigest
    expected_execution = {
      "provider_profile_id" => lane["provider_profile_id"],
      "provider_profile_sha256" => actual_profile_sha,
      "provider_capability_snapshot_sha256" => registry_sha
    }
    expected_execution.each do |field, expected|
      raise ContractError, "#{lane_key} execution #{field} differs from the exact provider registry snapshot" unless execution[field] == expected
    end

    if resolved["adapter"] == "codex_imagegen"
      source = load_mapping(profile_path, "Codex native media provider profile source")
      profile = source.dig("profiles", lane["provider_profile_id"])
      raise ContractError, "Codex native ImageGen profile does not resolve" unless profile.is_a?(Hash)
      %w[execution_adapter_id provider_model_or_tool selected_native_tool auth_lane].each do |field|
        raise ContractError, "Codex native ImageGen profile #{field} differs from execution" unless profile[field] == execution[field]
      end
      unless profile["current_session_binding_required"] == true && profile["exact_tool_inventory_required"] == true
        raise ContractError, "Codex native ImageGen profile must bind the current session and exact tool inventory"
      end
    else
      source = load_mapping(profile_path, "Grok provider profile source")
      profile = source.dig("media_capabilities", "image_subscription_cli")
      raise ContractError, "Grok native image capability does not resolve" unless profile.is_a?(Hash)
      unless profile["adapter_id"].to_s == "grok_image" &&
             profile["auth_lane"].to_s == "subscription_oauth" &&
             Array(profile["tools"]) == %w[image_edit image_gen] &&
             profile["automatic_fallback"].to_s == "none"
        raise ContractError, "Grok native image capability differs from the registered provider surface"
      end
    end

    resolved.merge(
      "profile_path" => profile_path.to_s,
      "profile_sha256" => actual_profile_sha,
      "registry_sha256" => registry_sha
    )
  end
end
