# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

module IdolGraphGoalEvidenceContract
  SCHEMA_VERSION = "idol-graph-provider-goal-terminal-event.v1"
  ARTIFACT_TYPE = "graph_provider_goal_terminal_event"
  EVIDENCE_CLASSES = %w[provider_native_terminal_event synthetic_fixture].freeze
  VALIDATION_MODES = %w[active_promotion profile_evolution_evidence historical_audit test_boundary].freeze
  SYNTHETIC_NOTICE = "synthetic_test_evidence_not_runtime_attestation"
  REQUIRED_FIELDS = %w[
    schema_version
    artifact_type
    evidence_class
    provider
    native_goal_id
    goal_text
    goal_text_sha256
    goal_semantics
    terminal_state
    last_event
  ].freeze
  OPTIONAL_FIELDS = %w[fixture_notice adapter_attestation].freeze

  class ContractError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  module_function

  def verify!(root:, provider_binding:, goal_evidence:, validation_mode: nil, test_proof_root: nil)
    root_path = Pathname.new(root).expand_path
    binding = require_mapping!(provider_binding, "provider_binding")
    goal = require_mapping!(goal_evidence, "goal_evidence")
    pointer = require_mapping!(goal["terminal_event"], "goal_evidence.terminal_event")
    event_path = repository_file!(root_path, pointer["path"])
    effective_validation_mode = normalize_validation_mode(
      validation_mode,
      root: root_path,
      event_path: event_path,
      test_proof_root: test_proof_root
    )

    pointer_sha = require_sha!(pointer["sha256"], "goal_evidence.terminal_event.sha256")
    declared_event_sha = require_sha!(goal["goal_terminal_event_sha256"], "goal_terminal_event_sha256")
    unless pointer_sha == declared_event_sha
      raise ContractError.new("terminal_event_sha_mismatch", "terminal_event.sha256 must equal goal_terminal_event_sha256")
    end

    actual_sha = Digest::SHA256.file(event_path.to_s).hexdigest
    unless actual_sha == pointer_sha
      raise ContractError.new("stale_terminal_event_sha", "terminal Goal event SHA-256 is stale for #{pointer['path']}")
    end

    event = load_mapping!(event_path)
    validate_event_shape!(event)
    validate_event_class!(event, validation_mode: effective_validation_mode)

    expected = {
      "provider" => binding["registered_provider"],
      "native_goal_id" => goal["native_goal_id"],
      "goal_text_sha256" => goal["goal_text_sha256"],
      "goal_semantics" => goal["goal_semantics"],
      "terminal_state" => goal["goal_terminal_state"],
      "last_event" => goal["goal_last_event"]
    }
    expected.each do |field, value|
      next if event[field].to_s == value.to_s

      raise ContractError.new("terminal_event_field_mismatch", "terminal Goal event #{field} does not match Graph Goal evidence")
    end

    computed_goal_text_sha = Digest::SHA256.hexdigest(event.fetch("goal_text").encode(Encoding::UTF_8))
    unless computed_goal_text_sha == event["goal_text_sha256"].to_s
      raise ContractError.new("goal_text_digest_mismatch", "terminal Goal event goal_text_sha256 does not match exact goal_text bytes")
    end

    {
      "path" => pointer.fetch("path"),
      "sha256" => actual_sha,
      "native_goal_id" => event.fetch("native_goal_id"),
      "goal_text_sha256" => computed_goal_text_sha,
      "provider" => event.fetch("provider"),
      "evidence_class" => event.fetch("evidence_class"),
      "last_event" => event.fetch("last_event"),
      "terminal_state" => event.fetch("terminal_state")
    }
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
    raise ContractError.new("invalid_goal_text_encoding", "terminal Goal event goal_text must be valid UTF-8: #{e.message}")
  end

  def normalize_validation_mode(validation_mode, root:, event_path:, test_proof_root: nil)
    mode = validation_mode.to_s
    if mode.empty?
      relative = event_path.relative_path_from(root.realpath).to_s
      mode = relative.start_with?("scripts/tests/fixtures/") ? "test_boundary" : "active_promotion"
    end
    unless VALIDATION_MODES.include?(mode)
      raise ContractError.new("invalid_validation_mode", "Goal evidence validation_mode is not recognized")
    end
    if mode == "test_boundary"
      relative = event_path.relative_path_from(root.realpath).to_s
      fixture_boundary = relative.start_with?("scripts/tests/fixtures/")
      unless fixture_boundary || bounded_router_test_proof_root?(root, test_proof_root)
        raise ContractError.new(
          "invalid_test_boundary",
          "Goal evidence test_boundary is restricted to scripts/tests/fixtures or the explicit bounded router proof root"
        )
      end
    end
    mode

  rescue ArgumentError
    raise ContractError.new("invalid_validation_mode", "Goal evidence test boundary must remain inside the repository")
  end

  def bounded_router_test_proof_root?(root, test_proof_root)
    return false if test_proof_root.nil?

    declared = Pathname.new(test_proof_root).expand_path.cleanpath
    return false unless declared.directory?
    return false if declared.symlink?

    actual = root.realpath
    declared_real = declared.realpath
    private_tmp = Pathname.new("/private/tmp").realpath
    declared_real == actual &&
      declared_real.parent == private_tmp &&
      declared_real.basename.to_s.start_with?("idol-graph-director-router-")
  rescue ArgumentError, Errno::ENOENT
    false
  end

  def require_mapping!(value, label)
    return value if value.is_a?(Hash)

    raise ContractError.new("missing_goal_evidence", "#{label} must be an object")
  end

  def require_sha!(value, label)
    text = value.to_s
    return text if text.match?(/\A[a-f0-9]{64}\z/)

    raise ContractError.new("invalid_goal_evidence_sha", "#{label} must be a lowercase SHA-256")
  end

  def repository_file!(root, raw_path)
    relative = Pathname.new(raw_path.to_s)
    if relative.absolute? || raw_path.to_s.empty?
      raise ContractError.new("invalid_terminal_event_path", "terminal Goal event path must be repository-relative")
    end

    candidate = root.join(relative).cleanpath
    relative_to_root = candidate.relative_path_from(root).to_s
    if relative_to_root == ".." || relative_to_root.start_with?("../")
      raise ContractError.new("terminal_event_path_escape", "terminal Goal event path escapes repository")
    end
    unless candidate.file?
      raise ContractError.new("terminal_event_missing", "terminal Goal event file is missing: #{raw_path}")
    end

    real_root = root.realpath
    real_candidate = candidate.realpath
    real_relative = real_candidate.relative_path_from(real_root).to_s
    if real_relative == ".." || real_relative.start_with?("../")
      raise ContractError.new("terminal_event_path_escape", "terminal Goal event resolves outside repository")
    end

    real_candidate
  rescue Errno::ENOENT
    raise ContractError.new("terminal_event_missing", "terminal Goal event file is missing: #{raw_path}")
  end

  def load_mapping!(path)
    text = path.read
    value = path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, aliases: false)
    return value if value.is_a?(Hash)

    raise ContractError.new("invalid_terminal_event", "terminal Goal event must be a JSON or YAML object")
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError.new("invalid_terminal_event", "terminal Goal event cannot be parsed: #{e.message}")
  end

  def validate_event_shape!(event)
    missing = REQUIRED_FIELDS.reject { |field| event.key?(field) }
    unless missing.empty?
      raise ContractError.new("invalid_terminal_event", "terminal Goal event is missing: #{missing.join(', ')}")
    end

    unexpected = event.keys.map(&:to_s) - REQUIRED_FIELDS - OPTIONAL_FIELDS
    unless unexpected.empty?
      raise ContractError.new("invalid_terminal_event", "terminal Goal event has unexpected fields: #{unexpected.join(', ')}")
    end
    unless event["schema_version"].to_s == SCHEMA_VERSION && event["artifact_type"].to_s == ARTIFACT_TYPE
      raise ContractError.new("invalid_terminal_event", "terminal Goal event schema_version/artifact_type is not active")
    end
    require_sha!(event["goal_text_sha256"], "terminal Goal event goal_text_sha256")
    raise ContractError.new("invalid_terminal_event", "terminal Goal event goal_text must be non-empty") if event["goal_text"].to_s.empty?
  end

  def validate_event_class!(event, validation_mode:)
    evidence_class = event["evidence_class"].to_s
    unless EVIDENCE_CLASSES.include?(evidence_class)
      raise ContractError.new("invalid_evidence_class", "terminal Goal event evidence_class is not recognized")
    end

    if evidence_class == "synthetic_fixture"
      unless event["fixture_notice"].to_s == SYNTHETIC_NOTICE
        raise ContractError.new("synthetic_fixture_not_declared", "synthetic Goal evidence must declare that it is not runtime attestation")
      end
      unless %w[historical_audit test_boundary].include?(validation_mode.to_s)
        raise ContractError.new(
          "synthetic_fixture_forbidden_for_active_promotion",
          "active promotion requires provider_native_terminal_event Goal evidence; synthetic_fixture is historical/test evidence only"
        )
      end
    elsif event.key?("fixture_notice")
      raise ContractError.new("invalid_terminal_event", "provider-native Goal evidence may not carry a synthetic fixture notice")
    end
  end
end
