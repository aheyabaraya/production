# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "yaml"

module IdolGraphOutputManifestContract
  class ContractError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  SCHEMA_VERSION = "idol-graph-output-manifest.v1"
  ARTIFACT_TYPE = "graph_dispatch_output_manifest"
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze

  module_function

  # This verifies only a non-null manifest. The caller owns lifecycle policy and
  # decides whether a nil output_manifest is legal before invoking this method.
  def verify!(root:, pointer:, dispatch:)
    root = Pathname.new(root).expand_path
    raise_contract("null_manifest", "a non-null output manifest pointer is required") unless pointer.is_a?(Hash)
    raise_contract("invalid_dispatch", "dispatch must be an object") unless dispatch.is_a?(Hash)

    manifest_path = relative_repo_file(root, pointer["path"], "output manifest")
    verify_sha!(pointer["sha256"], "output manifest pointer")
    actual_manifest_sha = Digest::SHA256.file(manifest_path).hexdigest
    unless actual_manifest_sha == pointer["sha256"].to_s
      raise_contract("stale_manifest_sha", "output manifest SHA-256 is stale")
    end

    manifest = load_mapping(manifest_path, "output manifest")
    validate_identity!(manifest, dispatch)
    bounded_output = dispatch["bounded_output"]
    unless bounded_output.is_a?(Hash)
      raise_contract("bounded_output_missing", "dispatch bounded_output must be an object")
    end
    expected_paths = Array(bounded_output["expected_paths"]).map(&:to_s)
    if expected_paths.empty? || expected_paths.uniq.length != expected_paths.length
      raise_contract("bounded_output_invalid", "dispatch bounded_output expected_paths must be a non-empty unique list")
    end
    unless bounded_output["maximum_artifact_count"].to_i == expected_paths.length
      raise_contract("bounded_output_invalid", "dispatch bounded_output maximum_artifact_count must equal expected path count")
    end
    unless manifest["output_kind"].to_s == bounded_output["output_kind"].to_s
      raise_contract("output_kind_mismatch", "output manifest output_kind does not exact-bind dispatch bounded_output")
    end
    outputs = manifest["outputs"]
    unless outputs.is_a?(Array) && !outputs.empty?
      raise_contract("outputs_missing", "output manifest must declare at least one output")
    end

    seen_paths = {}
    resolved_outputs = outputs.each_with_index.map do |output, index|
      raise_contract("invalid_output", "output #{index + 1} must be an object") unless output.is_a?(Hash)

      output_path = relative_repo_file(root, output["path"], "output #{index + 1}")
      relative_path = output_path.relative_path_from(root.realpath).to_s
      if seen_paths[relative_path]
        raise_contract("duplicate_output", "output manifest repeats output path: #{relative_path}")
      end
      seen_paths[relative_path] = true

      verify_sha!(output["sha256"], "output #{index + 1}")
      actual_output_sha = Digest::SHA256.file(output_path).hexdigest
      unless actual_output_sha == output["sha256"].to_s
        raise_contract("stale_output_sha", "output #{index + 1} SHA-256 is stale: #{relative_path}")
      end

      {
        "path" => relative_path,
        "sha256" => actual_output_sha
      }
    end
    actual_paths = resolved_outputs.map { |row| row.fetch("path") }
    unless actual_paths == expected_paths
      raise_contract("output_scope_mismatch", "output manifest must exact-cover bounded_output expected_paths in order")
    end

    {
      "manifest_path" => manifest_path.relative_path_from(root.realpath).to_s,
      "manifest_sha256" => actual_manifest_sha,
      "schema_version" => SCHEMA_VERSION,
      "artifact_type" => ARTIFACT_TYPE,
      "dispatch_id" => dispatch["dispatch_id"],
      "assigned_owner" => dispatch["assigned_owner"],
      "input_digest_sha256" => dispatch["input_digest_sha256"],
      "output_kind" => bounded_output["output_kind"],
      "outputs" => resolved_outputs
    }
  end

  def validate_identity!(manifest, dispatch)
    expected = {
      "schema_version" => SCHEMA_VERSION,
      "artifact_type" => ARTIFACT_TYPE,
      "dispatch_id" => dispatch["dispatch_id"],
      "assigned_owner" => dispatch["assigned_owner"],
      "input_digest_sha256" => dispatch["input_digest_sha256"]
    }
    verify_sha!(expected["input_digest_sha256"], "dispatch input digest")
    expected.each do |field, value|
      if value.to_s.empty?
        raise_contract("invalid_dispatch", "dispatch #{field} is missing")
      end
      next if manifest[field] == value

      raise_contract("manifest_identity_mismatch", "output manifest #{field} does not exact-bind the dispatch")
    end
  end

  def relative_repo_file(root, raw, label)
    relative = Pathname.new(raw.to_s)
    if raw.to_s.empty? || relative.absolute?
      raise_contract("path_not_repository_relative", "#{label} path must be repository-relative")
    end

    path = root.join(relative).expand_path.cleanpath
    raise_contract("missing_file", "#{label} file is missing") unless path.file?

    real_root = root.realpath
    real_path = path.realpath
    repo_relative = real_path.relative_path_from(real_root).to_s
    if repo_relative == ".." || repo_relative.start_with?("../")
      raise_contract("path_escapes_repository", "#{label} path escapes the repository root")
    end

    real_path
  rescue ArgumentError, Errno::ENOENT
    raise_contract("path_escapes_repository", "#{label} path escapes or is missing from the repository root")
  end

  def load_mapping(path, label)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
            end
    raise_contract("invalid_manifest", "#{label} must contain an object") unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT => e
    raise_contract("invalid_manifest", "cannot read #{label}: #{e.message}")
  end

  def verify_sha!(raw, label)
    return if raw.to_s.match?(SHA256_PATTERN)

    raise_contract("invalid_sha256", "#{label} SHA-256 is invalid")
  end

  def raise_contract(code, message)
    raise ContractError.new(code, message)
  end
end
