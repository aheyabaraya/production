# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

# Resolves evidence selected by a human/model. It never selects evidence or grades it.
module IdolGraphCriterionEvidenceContract
  class ContractError < StandardError; end

  module_function

  def canonical(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, out| out[key] = canonical(value[key]) }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def value_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def exact_file(root, raw)
    text = raw.to_s
    path = Pathname.new(text)
    if text.empty? || path.absolute? || text.split("/").include?("..")
      raise ContractError, "criterion evidence path must be repository-relative without traversal"
    end
    real_root = Pathname.new(root).realpath
    candidate = real_root.join(path)
    raise ContractError, "criterion evidence file is missing: #{text}" unless candidate.file?
    candidate = candidate.realpath
    relative = candidate.relative_path_from(real_root).to_s
    if relative == ".." || relative.start_with?("../")
      raise ContractError, "criterion evidence path escapes repository"
    end
    candidate
  rescue ArgumentError, Errno::ENOENT => e
    raise ContractError, "criterion evidence path cannot resolve: #{e.message}"
  end

  def resolve_value(document, pointer)
    text = pointer.to_s
    unless text.start_with?("/") && !text.match?(/~(?![01])/)
      raise ContractError, "criterion evidence JSON pointer is invalid"
    end
    value = document
    text.split("/", -1).drop(1).each do |raw|
      token = raw.gsub("~1", "/").gsub("~0", "~")
      if value.is_a?(Hash) && value.key?(token)
        value = value.fetch(token)
      elsif value.is_a?(Array) && token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < value.length
        value = value.fetch(token.to_i)
      else
        raise ContractError, "criterion evidence JSON pointer does not resolve: #{text}"
      end
    end
    value
  end

  def resolve_ref(root:, ref:, sources:)
    unless ref.is_a?(Hash) && (ref.keys - %w[path sha256 json_pointer value_sha256]).empty?
      raise ContractError, "criterion evidence must be a typed source reference"
    end
    pair = [ref["path"].to_s, ref["sha256"].to_s]
    unless sources.include?(pair)
      raise ContractError, "criterion evidence must bind a declared source_artifact"
    end
    file = exact_file(root, ref["path"])
    unless Digest::SHA256.file(file).hexdigest == ref["sha256"].to_s
      raise ContractError, "criterion evidence SHA-256 is stale: #{ref['path']}"
    end
    has_pointer = ref.key?("json_pointer")
    unless has_pointer == ref.key?("value_sha256")
      raise ContractError, "criterion evidence JSON pointer and value hash must be paired"
    end
    value = nil
    if has_pointer
      unless %w[.json .yaml .yml].include?(file.extname.downcase)
        raise ContractError, "criterion row evidence requires a structured source"
      end
      source = file.extname.downcase == ".json" ? JSON.parse(file.read) : YAML.safe_load(file.read, aliases: true)
      value = resolve_value(source, ref["json_pointer"])
      unless value_sha256(value) == ref["value_sha256"].to_s
        raise ContractError, "criterion evidence value SHA-256 is stale"
      end
    end
    {"path" => pair[0], "sha256" => pair[1], "value" => value}
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError, "criterion evidence structured source cannot parse: #{e.message}"
  end

  GENERATED_BRANCH_CUT_REVIEW_SCHEMA = "idol_generated_branch_cut_review.v4"
  GENERATED_BRANCH_CUT_PACKET_ID = /\APKT_BC[0-9]{2,}_[A-Z0-9_]+\z/
  GENERATED_BRANCH_CUT_ID = /\ABC[0-9A-Z_]{2,80}\z/
  GENERATED_BRANCH_CUT_SECTION_ID = /\AS[0-9]{2,}[A-Z]?\z/
  GENERATED_BRANCH_CUT_CORE_ID = /\AC[0-9]{2,}[A-Z0-9_]*\z/
  GENERATED_BRANCH_CUT_IMAGE_SHA256 = /\A[0-9a-f]{64}\z/
  GENERATED_IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .webp .heic .gif .avif].freeze

  def nested_image_pair(value)
    return unless value.is_a?(Hash) && value["image_path"].is_a?(String) && value["image_sha256"].is_a?(String)

    [value["image_path"], value["image_sha256"]]
  end

  def verify_nested_image!(root, value, label)
    pair = nested_image_pair(value)
    return unless pair

    image = exact_file(root, pair[0])
    return if Digest::SHA256.file(image).hexdigest == pair[1]

    raise ContractError, "#{label} row image SHA-256 is stale"
  end

  def generated_branch_cut_review_target_row!(row, index)
    unless row.is_a?(Hash)
      raise ContractError, "branch_cut_reviews[#{index}] must be an object"
    end
    path = row["image_path"]
    sha = row["image_sha256"]
    unless path.is_a?(String) && !path.empty? && sha.to_s.match?(GENERATED_BRANCH_CUT_IMAGE_SHA256)
      raise ContractError, "branch_cut_reviews[#{index}] is missing image_path/image_sha256"
    end
    unless row["packet_id"].to_s.match?(GENERATED_BRANCH_CUT_PACKET_ID) &&
           row["branch_cut_id"].to_s.match?(GENERATED_BRANCH_CUT_ID) &&
           row["section_id"].to_s.match?(GENERATED_BRANCH_CUT_SECTION_ID) &&
           row["core_cut_id"].to_s.match?(GENERATED_BRANCH_CUT_CORE_ID)
      raise ContractError, "branch_cut_reviews[#{index}] packet_id/branch_cut_id/section_id/core_cut_id is invalid"
    end
    {"path" => path, "sha256" => sha}
  end

  def generated_branch_cut_image_targets(review, section_ids = nil)
    return [] unless review.is_a?(Hash)
    return [] unless review["schema_version"].to_s == GENERATED_BRANCH_CUT_REVIEW_SCHEMA
    unless review["branch_cut_reviews"].is_a?(Array)
      raise ContractError, "idol_generated_branch_cut_review.v4 output must contain a branch_cut_reviews array"
    end

    allowed = Array(section_ids).map(&:to_s).reject(&:empty?)
    expected = []
    review["branch_cut_reviews"].each_with_index do |row, index|
      target = generated_branch_cut_review_target_row!(row, index)
      next if !allowed.empty? && !allowed.include?(row["section_id"].to_s)

      expected << target
    end
    expected
  end

  def generated_image_output_target!(root, output, index)
    raise ContractError, "output #{index} must be an object" unless output.is_a?(Hash)
    path = output["path"].to_s
    return nil unless GENERATED_IMAGE_EXTENSIONS.include?(Pathname.new(path).extname.downcase)
    sha = output["sha256"].to_s
    unless !path.empty? && sha.match?(GENERATED_BRANCH_CUT_IMAGE_SHA256)
      raise ContractError, "output #{index} is missing path/sha256"
    end
    file = exact_file(root, path)
    unless Digest::SHA256.file(file).hexdigest == sha
      raise ContractError, "output #{index} SHA-256 is stale: #{path}"
    end
    {"path" => path, "sha256" => sha}
  end

  def expected_cut_images_from_authentic_manifest(root:, manifest:, section_ids: nil)
    raise ContractError, "authentic output manifest must be an object" unless manifest.is_a?(Hash)

    expected = []
    Array(manifest["outputs"]).each_with_index do |output, index|
      if (direct = generated_image_output_target!(root, output, index))
        expected << direct
        next
      end
      path = output["path"].to_s
      next unless %w[.json .yaml .yml].include?(Pathname.new(path).extname.downcase)

      file = exact_file(root, path)
      parsed = file.extname.downcase == ".json" ? JSON.parse(file.read) : YAML.safe_load(file.read, aliases: true)
      next unless parsed.is_a?(Hash) && parsed["schema_version"].to_s == GENERATED_BRANCH_CUT_REVIEW_SCHEMA

      expected.concat(generated_branch_cut_image_targets(parsed, section_ids))
    end
    expected.each_with_object([]) do |row, uniq|
      pair = [row["path"], row["sha256"]]
      uniq << row unless uniq.any? { |item| [item["path"], item["sha256"]] == pair }
    end
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError, "authentic generated Branch-Cut review output cannot parse: #{e.message}"
  end

  def verify!(root:, document:, expected_cut_images: nil)
    unless document["schema_version"] == "idol_graph_contextual_judgment.v2"
      raise ContractError, "active criterion evidence requires contextual judgment v2; v1 is historical only"
    end
    sources = Array(document["source_artifacts"]).map { |row| [row.to_h["path"].to_s, row.to_h["sha256"].to_s] }
    expected = expected_cut_images && expected_cut_images.map { |row| [row.fetch("path").to_s, row.fetch("sha256").to_s] }.uniq
    collections = {"criteria" => Array(document["criteria"]), "hard_gate_findings" => Array(document["hard_gate_findings"])}
    collections.each do |collection, rows|
      rows.each do |row|
        label = row.to_h["criterion_id"] || row.to_h["finding_id"] || collection
        refs = row.to_h["evidence_locator"]
        unless refs.is_a?(Array) && !refs.empty? && refs.uniq.length == refs.length
          raise ContractError, "#{label} evidence_locator requires unique typed references"
        end
        resolved = refs.map { |ref| resolve_ref(root: root, ref: ref, sources: sources) }
        resolved.each { |ref| verify_nested_image!(root, ref["value"], label) }
        next unless expected && collection == "criteria"

        covered = resolved.flat_map do |ref|
          pairs = [[ref["path"], ref["sha256"]]]
          pair = nested_image_pair(ref["value"])
          pairs << pair if pair
          pairs
        end
        unless (expected - covered).empty?
          raise ContractError, "#{label} evidence does not cover every exact target Cut image"
        end
      end
    end
    true
  end
end
