# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "uri"
require "yaml"

module IdolXaiApiMediaProfileContract
  class ContractError < StandardError; end

  PROFILE_BINDING_FIELDS = %w[
    provider_profile_id
    provider_profile_source
    provider_profile_source_sha256
  ].freeze
  NONSECRET_CHILD_ENV = {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil}.freeze
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze
  ENDPOINT_PATTERN = %r{\A/[A-Za-z0-9][A-Za-z0-9._~!$&'()*+,;=:@%/\-]{0,240}\z}.freeze

  module_function

  def load_mapping(path)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
            end
    raise ContractError, "xAI API contract source must be an object: #{path}" unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT => e
    raise ContractError, "cannot read xAI API contract source: #{path}: #{e.message}"
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
    if relative == ".." || relative.start_with?("../")
      raise ContractError, "#{label} escapes the repository root"
    end
    real_path
  rescue ArgumentError, Errno::ENOENT
    raise ContractError, "#{label} escapes or is missing from the repository root"
  end

  def exact_https_origin?(raw)
    uri = URI.parse(raw.to_s)
    uri.is_a?(URI::HTTPS) &&
      !uri.host.to_s.empty? &&
      uri.userinfo.nil? &&
      uri.port == 443 &&
      ["", "/"].include?(uri.path.to_s) &&
      uri.query.nil? &&
      uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end

  def validate_operation!(operation, operation_id)
    raise ContractError, "registered xAI API profile lacks #{operation_id}" unless operation.is_a?(Hash)

    endpoint = operation["endpoint_path"].to_s
    raise ContractError, "registered xAI API #{operation_id} endpoint is unsafe" unless endpoint.match?(ENDPOINT_PATTERN) && !endpoint.split("/").include?("..")

    request = operation["request_contract"]
    response = operation["response_contract"]
    raise ContractError, "registered xAI API #{operation_id} request contract is missing" unless request.is_a?(Hash)
    raise ContractError, "registered xAI API #{operation_id} response contract is missing" unless response.is_a?(Hash)

    fields = %w[model_field prompt_field output_count_field].map { |key| request[key].to_s }
    attachment_field = request["attachment_field"]
    fields << attachment_field.to_s unless attachment_field.nil?
    if fields.any?(&:empty?) || fields.uniq.length != fields.length
      raise ContractError, "registered xAI API #{operation_id} request fields are empty or overlap"
    end
    fixed_fields = request["fixed_fields"]
    raise ContractError, "registered xAI API #{operation_id} fixed fields must be an object" unless fixed_fields.is_a?(Hash)
    if fields.any? { |field| fixed_fields.key?(field) }
      raise ContractError, "registered xAI API #{operation_id} fixed fields override exact request bindings"
    end
    unless response["exact_output_count"] == 1 && %w[base64_json https_url raw_body].include?(response["image_encoding"].to_s)
      raise ContractError, "registered xAI API #{operation_id} response contract is not exact-one-image"
    end

    transport = operation["transport"].to_s
    if operation_id == "image_gen"
      unless transport == "json" && operation["attachment_policy"].to_s == "forbidden" && attachment_field.nil?
        raise ContractError, "registered xAI API image_gen must use JSON and forbid attachments"
      end
    else
      allowed = %w[json_data_url_array json_base64_array multipart_form_data_image_array]
      unless allowed.include?(transport) && operation["attachment_policy"].to_s == "required_all_ordered" && !attachment_field.to_s.empty?
        raise ContractError, "registered xAI API image_edit must carry every ordered attachment"
      end
    end
    operation
  end

  def verify!(root:, execution:, attachment_count:, registry_path: nil)
    root = Pathname.new(root).expand_path
    registry_path ||= root.join("automation/harness-provider-profile-registry.yaml")
    registry_path = exact_repo_file(root, registry_path, "provider registry")
    registry = load_mapping(registry_path)
    lane = registry.dig("media_lanes", "xai_api_media")
    raise ContractError, "xAI API media registration is missing; activation HOLD and no fallback" unless lane.is_a?(Hash)

    if lane["selection_only"] == true
      raise ContractError, "xAI API media is legacy selection-only; activation HOLD and no fallback"
    end
    if lane["registration_status"].to_s == "registration_required"
      unless lane["capability_status"].to_s == "registration_required" &&
             lane["harness_status"].to_s == "hold" &&
             lane["default_enabled"] == false &&
             lane["selection_only"] == false &&
             lane["automatic_fallback"].to_s == "none" &&
             PROFILE_BINDING_FIELDS.none? { |field| lane.key?(field) }
        raise ContractError, "xAI API media registration_required row is malformed; activation HOLD and no fallback"
      end
      raise ContractError, "xAI API media registration_required HOLD: exact profile source, model, and endpoint are absent; no fallback"
    end

    required_lane = {
      "provider" => "xai",
      "auth_lane" => "founder_approved_api",
      "capability_status" => "active",
      "harness_status" => "active",
      "registration_status" => "registered_exact",
      "image_adapter_id" => "xai_api_media",
      "image_output_contract" => "exact_expected_output_path_sha256_pixel_review",
      "default_enabled" => false,
      "selection_only" => false,
      "automatic_fallback" => "none"
    }
    required_lane.each do |field, expected|
      raise ContractError, "registered xAI API lane #{field} differs from exact active binding" unless lane[field] == expected
    end

    profile_id = lane["provider_profile_id"].to_s
    source_sha = lane["provider_profile_source_sha256"].to_s
    raise ContractError, "registered xAI API profile id is missing" if profile_id.empty?
    raise ContractError, "registered xAI API profile source SHA-256 is invalid" unless source_sha.match?(SHA256_PATTERN)

    profile_path = exact_repo_file(root, lane["provider_profile_source"], "xAI API provider profile source")
    actual_source_sha = Digest::SHA256.file(profile_path).hexdigest
    raise ContractError, "registered xAI API provider profile source SHA-256 is stale" unless actual_source_sha == source_sha

    source = load_mapping(profile_path)
    unless source["schema_version"].to_s == "idol-xai-api-media-provider-profiles.v1" &&
           source["status"].to_s == "active" &&
           source["provider"].to_s == "xai_api" &&
           source["runtime_surface"].to_s == "xai_media_api"
      raise ContractError, "registered xAI API provider profile source has an inactive contract header"
    end
    profile = source.dig("profiles", profile_id)
    raise ContractError, "registered xAI API provider profile id does not resolve" unless profile.is_a?(Hash)
    required_profile = {
      "image_adapter_id" => "xai_api_media",
      "auth_lane" => "founder_approved_api",
      "authorization_scheme" => "bearer",
      "capability_status" => "active",
      "harness_status" => "active",
      "default_enabled" => false,
      "automatic_fallback" => "none",
      "unavailable_or_mismatch_action" => "hold_and_report"
    }
    required_profile.each do |field, expected|
      raise ContractError, "registered xAI API profile #{field} differs from exact active binding" unless profile[field] == expected
    end
    if profile["exact_model"].to_s.empty? || profile["exact_model"].to_s == "unregistered_selection_only"
      raise ContractError, "registered xAI API profile exact model is missing"
    end
    raise ContractError, "registered xAI API profile API version is missing" if profile["api_version"].to_s.empty?
    raise ContractError, "registered xAI API profile base URL is not an exact HTTPS origin" unless exact_https_origin?(profile["api_base_url"])

    operations = profile["operations"]
    raise ContractError, "registered xAI API profile operations are missing" unless operations.is_a?(Hash)
    validate_operation!(operations["image_gen"], "image_gen")
    validate_operation!(operations["image_edit"], "image_edit")
    operation_id = attachment_count.to_i.positive? ? "image_edit" : "image_gen"

    expected_execution = {
      "execution_adapter_id" => "xai_api_media",
      "provider" => "xai_api",
      "provider_model_or_tool" => profile["exact_model"],
      "selected_native_tool" => nil,
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => profile_id,
      "provider_profile_sha256" => actual_source_sha,
      "provider_capability_snapshot_sha256" => Digest::SHA256.file(registry_path).hexdigest,
      "cli_or_api_version" => profile["api_version"],
      "automatic_fallback" => "none"
    }
    expected_execution.each do |field, expected|
      raise ContractError, "xAI API execution #{field} differs from exact registered profile" unless execution[field] == expected
    end

    {
      "lane" => lane,
      "profile" => profile,
      "profile_path" => profile_path.to_s,
      "profile_sha256" => actual_source_sha,
      "registry_sha256" => Digest::SHA256.file(registry_path).hexdigest,
      "operation_id" => operation_id,
      "endpoint_path" => operations.fetch(operation_id).fetch("endpoint_path")
    }
  end

  def verify_request!(root:, request:, registry_path: nil)
    execution = request["execution"]
    return nil unless execution.is_a?(Hash) && execution["execution_adapter_id"].to_s == "xai_api_media"

    unless request["status"].to_s == "ready" && Array(request["hold_reasons"]).empty?
      raise ContractError, "xAI API request is not exact ready or still carries HOLD reasons"
    end

    verify!(
      root: root,
      registry_path: registry_path,
      execution: execution,
      attachment_count: Array(request["attachments"]).length
    )
  end
end
