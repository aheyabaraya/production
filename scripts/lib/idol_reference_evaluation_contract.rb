#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "idol_graph_criterion_evidence_contract"

# Completeness and exact evidence binding for reference-evaluation cases.
# JSON Schema is the structural validator. This overlay adds containment,
# Sequence cadence, provenance, path identity, and drift only.
# Humans or assigned models author observations. Pixel meaning is not machine PASS.
module IdolReferenceEvaluationContract
  class ContractError < StandardError; end

  SCHEMA_VERSION = "idol-reference-evaluation.v1"
  MECHANICAL_RESULT_VERSION = "idol-reference-evaluation-mechanical-result.v1"
  SYNTHETIC_NOTICE = "synthetic_test_evidence_not_pixel_inspection_or_production_pass"
  CAMERA_SUBJECT_AMBIGUITY = "unresolved_2d_projection_cannot_separate_camera_from_subject"
  SEQUENCE_FRAME_COUNT = 5
  SEQUENCE_CADENCE_SECONDS = 1.0
  CADENCE_TOLERANCE = 0.001
  CADENCE_OVERLAY = "JSON Schema cannot express consecutive exact one-second Sequence cadence; sequence_samples overlay requires five finite nonnegative timestamps at 1.0s ± 0.001"
  MECHANICAL_REF_KEYS = %w[path sha256 json_pointer value_sha256].freeze
  IMPLEMENTATION_ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCHEMA = IMPLEMENTATION_ROOT.join("schemas", "reference-evaluation.schema.json")
  PYTHON = IMPLEMENTATION_ROOT.join("scripts", "idol-video-python")
  SCHEMA_VALIDATOR = IMPLEMENTATION_ROOT.join("scripts", "validate_json_schema.py")

  module_function

  def value_sha256(value)
    IdolGraphCriterionEvidenceContract.value_sha256(value)
  end

  def empty_case_extras
    {
      "time_span_alignment" => "not_applicable",
      "time_claim_kind" => "absent",
      "bound_sequence_samples" => false
    }
  end

  def empty_independence
    {
      "session_id_declaration" => "missing",
      "session_id_declaration_is_runtime_proof" => false,
      "runtime_artifact_binding" => "none",
      "independence_proof" => "insufficient"
    }
  end

  def mapping?(value)
    value.is_a?(Hash)
  end

  def finite_nonnegative_time?(value)
    value.is_a?(Numeric) && value.to_f.finite? && value.to_f >= 0.0
  end

  def sequence_sample_timestamps?(value)
    return false unless value.is_a?(Array) && value.length == SEQUENCE_FRAME_COUNT
    return false unless value.all? { |item| finite_nonnegative_time?(item) }

    value.each_cons(2).all? do |first, second|
      (second.to_f - first.to_f - SEQUENCE_CADENCE_SECONDS).abs <= CADENCE_TOLERANCE
    end
  end

  def relabel_resolver_error(message, label)
    message.to_s
      .sub("criterion evidence path", "#{label} path")
      .sub("criterion evidence file", "#{label} file")
      .sub("criterion evidence SHA-256", "#{label} SHA-256")
      .sub("criterion evidence JSON pointer", "#{label} JSON pointer")
      .sub("criterion evidence value SHA-256", "#{label} value SHA-256")
      .sub("criterion evidence must bind a declared source_artifact", "#{label} must bind a declared source_artifact")
      .sub("criterion evidence must be a typed source reference", "#{label} must be a typed source reference")
  end

  def contained_file(root, raw, label)
    IdolGraphCriterionEvidenceContract.exact_file(root, raw)
  rescue IdolGraphCriterionEvidenceContract::ContractError => e
    raise ContractError, relabel_resolver_error(e.message, label)
  end

  def contained_relative(root, raw, label)
    file = contained_file(root, raw, label)
    file.relative_path_from(Pathname.new(root).realpath).to_s
  end

  def parse_bytes(bytes, extname)
    text = bytes.to_s
    if %w[.json].include?(extname.to_s.downcase)
      JSON.parse(text)
    else
      YAML.safe_load(text, aliases: true)
    end
  rescue JSON::ParserError, Psych::Exception
    :unparsed
  end

  def schema_errors_for_bytes(bytes, extname, label)
    return ["#{label} schema snapshot missing"] if bytes.nil?

    ext = %w[.json .yaml .yml].include?(extname.to_s.downcase) ? extname.to_s.downcase : ".json"
    Dir.mktmpdir("idol-ref-eval-schema-") do |directory|
      path = Pathname.new(directory).join("document#{ext}")
      path.binwrite(bytes)
      stdout, stderr, status = Open3.capture3(
        PYTHON.to_s,
        SCHEMA_VALIDATOR.to_s,
        SCHEMA.to_s,
        path.to_s,
        chdir: IMPLEMENTATION_ROOT.to_s
      )
      return [] if status.success?

      message = [stderr, stdout].map { |part| part.to_s.strip }.reject(&:empty?).join("\n")
      ["#{label} schema: #{message.empty? ? 'validation failed' : message}"]
    end
  rescue StandardError => e
    ["#{label} schema failed closed: #{e.message}"]
  end

  def schema_errors_for_document(document, label)
    schema_errors_for_bytes(JSON.generate(document), ".json", label)
  rescue JSON::GeneratorError => e
    ["#{label} cannot serialize for schema validation: #{e.message}"]
  end

  def load_contained(root, raw, label)
    snapshot = {
      "errors" => [],
      "file" => nil,
      "bytes" => nil,
      "sha256" => nil,
      "document" => nil,
      "relative" => nil,
      "requested" => raw.to_s,
      "extname" => nil
    }
    begin
      file = contained_file(root, raw, label)
      relative = file.relative_path_from(Pathname.new(root).realpath).to_s
    rescue ContractError => e
      snapshot["errors"] = [e.message]
      return snapshot
    end

    bytes = file.binread
    snapshot["file"] = file
    snapshot["bytes"] = bytes
    snapshot["sha256"] = Digest::SHA256.hexdigest(bytes)
    snapshot["relative"] = relative
    snapshot["extname"] = file.extname
    parsed = parse_bytes(bytes, file.extname)
    if parsed == :unparsed
      snapshot["errors"] = ["#{label} cannot parse"]
    else
      snapshot["document"] = parsed
    end
    snapshot
  end

  def input_drift_errors(snapshot, label)
    file = mapping?(snapshot) ? snapshot["file"] : nil
    expected = mapping?(snapshot) ? snapshot["sha256"] : nil
    return [] unless file && expected

    current = Digest::SHA256.file(file).hexdigest
    return [] if current == expected

    ["#{label} input drifted after parse; refusing to publish mixed parse/hash"]
  end

  def verify_source_artifacts(root, document)
    errors = []
    verified = []
    rows = mapping?(document) ? document["source_artifacts"] : nil
    return [["source_artifacts must be an array"], verified] unless rows.is_a?(Array)

    rows.each_with_index do |row, index|
      label = "source_artifacts[#{index}]"
      unless mapping?(row)
        errors << "#{label} must be an object"
        next
      end
      begin
        file = contained_file(root, row["path"], label)
        actual = Digest::SHA256.file(file).hexdigest
        errors << "#{label} SHA-256 is stale" unless actual == row["sha256"].to_s
        next unless actual == row["sha256"].to_s

        verified << {
          "path" => row["path"].to_s,
          "normalized" => file.relative_path_from(Pathname.new(root).realpath).to_s,
          "sha256" => actual
        }
      rescue ContractError => e
        errors << e.message
      end
    end
    [errors, verified]
  end

  def source_pairs(verified)
    verified.flat_map do |row|
      [[row["path"], row["sha256"]], [row["normalized"], row["sha256"]]]
    end.uniq
  end

  def verify_runtime_artifacts(root, rows, label)
    errors = []
    refs = []
    return [errors, refs] unless rows.is_a?(Array)

    rows.each_with_index do |row, index|
      row_label = "#{label}[#{index}]"
      unless mapping?(row)
        errors << "#{row_label} must be a path/sha256 artifact pointer"
        next
      end
      begin
        file = contained_file(root, row["path"], row_label)
        actual = Digest::SHA256.file(file).hexdigest
        errors << "#{row_label} SHA-256 is stale" unless actual == row["sha256"].to_s
        refs << [row["path"].to_s, row["sha256"].to_s]
      rescue ContractError => e
        errors << e.message
      end
    end
    [errors, refs]
  end

  def recheck_verified_sources(root, verified)
    verified.flat_map do |row|
      next ["source_artifacts recheck missing"] unless mapping?(row)

      begin
        file = contained_file(root, row["path"], "source_artifacts")
        actual = Digest::SHA256.file(file).hexdigest
        actual == row["sha256"] ? [] : ["source_artifacts #{row['path']} drifted before result publication"]
      rescue ContractError => e
        [e.message]
      end
    end
  end

  def final_freshness_errors(root, extras, case_document: nil, review_document: nil)
    errors = []
    verified = mapping?(extras) ? extras["verified_sources"] : nil
    verified = [] unless verified.is_a?(Array)
    errors.concat(recheck_verified_sources(root, verified))
    if mapping?(case_document) && mapping?(case_document["authorship"])
      runtime_errors, = verify_runtime_artifacts(
        root,
        case_document["authorship"]["runtime_artifacts"],
        "authorship.runtime_artifacts"
      )
      errors.concat(runtime_errors)
    end
    if mapping?(review_document) && mapping?(review_document["reviewer"])
      runtime_errors, = verify_runtime_artifacts(
        root,
        review_document["reviewer"]["runtime_artifacts"],
        "reviewer.runtime_artifacts"
      )
      errors.concat(runtime_errors)
    end
    errors
  end

  def validate_timestamps(stamps, label, kind:)
    errors = []
    unless stamps.is_a?(Array)
      return ["#{label} timestamps_seconds must be an array"]
    end

    stamps.each_with_index do |value, index|
      next if finite_nonnegative_time?(value)

      errors << "#{label} timestamps_seconds[#{index}] must be a finite nonnegative number"
    end
    case kind
    when "sequence_samples"
      unless stamps.length == SEQUENCE_FRAME_COUNT
        errors << "#{label} sequence_samples must be exactly five timestamps"
      end
      if stamps.length == SEQUENCE_FRAME_COUNT && stamps.all? { |item| finite_nonnegative_time?(item) }
        unless sequence_sample_timestamps?(stamps)
          errors << "#{label} Sequence samples must use exact one-second cadence (#{CADENCE_OVERLAY})"
        end
      end
    when "review_interval"
      if stamps.length < 2
        errors << "#{label} review_interval must contain at least two timestamps and is not a Sequence sample assertion"
      end
    end
    errors
  end

  def time_span_alignment(claim, bound_values)
    extras = empty_case_extras
    bound_sequences = bound_values.select { |value| sequence_sample_timestamps?(value) }
    extras["bound_sequence_samples"] = !bound_sequences.empty?
    return [[], extras] unless mapping?(claim)

    kind = claim["kind"].to_s
    extras["time_claim_kind"] = kind.empty? ? "absent" : kind
    errors = validate_timestamps(claim["timestamps_seconds"], "time_claim", kind: kind)
    claimed = claim["timestamps_seconds"]
    if kind == "sequence_samples" && bound_sequences.empty?
      errors << "sequence_samples claim has no bound Sequence sample timestamps"
    end
    if claimed.is_a?(Array) && !bound_sequences.empty?
      extras["time_span_alignment"] =
        bound_sequences.any? { |span| span == claimed } ? "equal" : "claimed_and_bound_differ"
    elsif kind == "review_interval" && claimed.is_a?(Array) && bound_values.any? { |value| value.is_a?(Array) }
      extras["time_span_alignment"] =
        bound_values.any? { |value| value == claimed } ? "equal" : "claimed_and_bound_differ"
    end
    [errors, extras]
  end

  def overlay_case(root, document)
    extras = empty_case_extras.merge("bound_values" => [], "verified_sources" => [])
    return [[], extras] unless mapping?(document)

    errors, verified = verify_source_artifacts(root, document)
    extras["verified_sources"] = verified
    pairs = source_pairs(verified)
    bindings = document["evidence_bindings"]
    if bindings.is_a?(Array)
      bindings.each_with_index do |row, index|
        next unless mapping?(row)

        begin
          resolved = IdolGraphCriterionEvidenceContract.resolve_ref(
            root: root,
            ref: row.slice(*MECHANICAL_REF_KEYS),
            sources: pairs
          )
          extras["bound_values"] << resolved["value"]
        rescue IdolGraphCriterionEvidenceContract::ContractError => e
          errors << relabel_resolver_error(e.message, "evidence_bindings[#{index}]")
        end
      end
    end

    claims = document["scene_function_claims"]
    if claims.is_a?(Array)
      allowed = verified.flat_map { |row| [row["path"], row["normalized"]] }.uniq
      claims.each_with_index do |row, index|
        next unless mapping?(row)
        next if allowed.include?(row["source_path"].to_s)

        errors << "scene_function_claims[#{index}] source_path is not a verified source_artifact"
      end
    end

    span_errors, span_extras = time_span_alignment(document["time_claim"], extras["bound_values"])
    errors.concat(span_errors)
    extras = extras.merge(span_extras)
    extras["verified_sources"] = verified
    extras["bound_values"] ||= []

    authorship = document["authorship"]
    if mapping?(authorship)
      artifact_errors, = verify_runtime_artifacts(
        root,
        authorship["runtime_artifacts"],
        "authorship.runtime_artifacts"
      )
      errors.concat(artifact_errors)
    end
    [errors, extras]
  end

  def independence_assessment(case_document, review_document, case_refs, review_refs)
    assessment = empty_independence
    case_session = mapping?(case_document) && mapping?(case_document["authorship"]) ? case_document["authorship"]["author_session_id"].to_s : ""
    review_session = mapping?(review_document) && mapping?(review_document["reviewer"]) ? review_document["reviewer"]["session_id"].to_s : ""
    assessment["session_id_declaration"] =
      if case_session.empty? || review_session.empty?
        "missing"
      elsif case_session == review_session
        "same"
      else
        "distinct"
      end
    assessment["session_id_declaration_is_runtime_proof"] = false
    if case_refs.empty? && review_refs.empty?
      assessment["runtime_artifact_binding"] = "none"
    elsif !case_refs.empty? && !review_refs.empty? && case_refs.sort == review_refs.sort
      assessment["runtime_artifact_binding"] = "same_bound_artifacts"
    elsif !case_refs.empty? && !review_refs.empty? && (case_refs & review_refs).empty?
      assessment["runtime_artifact_binding"] = "distinct_bound_artifacts"
    else
      assessment["runtime_artifact_binding"] = "partial"
    end
    assessment["independence_proof"] =
      if assessment["runtime_artifact_binding"] == "distinct_bound_artifacts"
        "distinct_bound_runtime_artifacts_not_native_session_authority"
      elsif assessment["session_id_declaration"] == "distinct"
        "author_assertion_only"
      else
        "insufficient"
      end
    assessment
  end

  def overlay_review(root, document, case_document, case_relative, case_sha256, verified)
    errors = []
    return errors unless mapping?(document)

    pointer = document["case"]
    if mapping?(pointer)
      begin
        review_relative = contained_relative(root, pointer["path"], "review case")
        errors << "review case path does not bind the supplied case" unless review_relative == case_relative.to_s
      rescue ContractError => e
        errors << e.message
      end
      errors << "review case SHA-256 is stale" unless pointer["sha256"].to_s == case_sha256.to_s
    end

    reviewer = document["reviewer"]
    case_session = mapping?(case_document) && mapping?(case_document["authorship"]) ? case_document["authorship"]["author_session_id"].to_s : ""
    review_session = mapping?(reviewer) ? reviewer["session_id"].to_s : ""
    if case_session.empty? || review_session.empty? || case_session == review_session
      errors << "independent review session_id declaration must differ from case author_session_id (declaration only, not runtime proof)"
    end

    case_refs = []
    review_refs = []
    if mapping?(case_document) && mapping?(case_document["authorship"])
      case_errors, case_refs = verify_runtime_artifacts(
        root,
        case_document["authorship"]["runtime_artifacts"],
        "authorship.runtime_artifacts"
      )
      errors.concat(case_errors)
    end
    if mapping?(reviewer)
      review_errors, review_refs = verify_runtime_artifacts(
        root,
        reviewer["runtime_artifacts"],
        "reviewer.runtime_artifacts"
      )
      errors.concat(review_errors)
    end
    if !case_refs.empty? && !review_refs.empty? && case_refs.sort == review_refs.sort
      errors << "review runtime_artifacts match case runtime_artifacts; independence remains unproven and this declaration is inconsistent"
    end

    pairs = source_pairs(verified)
    observations = document["observations"]
    if observations.is_a?(Array)
      observations.each_with_index do |row, index|
        next unless mapping?(row) && mapping?(row["evidence"])

        begin
          IdolGraphCriterionEvidenceContract.resolve_ref(
            root: root,
            ref: row["evidence"].slice(*MECHANICAL_REF_KEYS),
            sources: pairs
          )
        rescue IdolGraphCriterionEvidenceContract::ContractError => e
          errors << relabel_resolver_error(e.message, "observations[#{index}] evidence")
        end
      end
    end
    [errors, independence_assessment(case_document, document, case_refs, review_refs)]
  end

  def public_extras(extras)
    base = empty_case_extras
    return base unless mapping?(extras)

    base.merge(extras.slice("time_span_alignment", "time_claim_kind", "bound_sequence_samples"))
  end

  def snapshot_document(snapshot)
    mapping?(snapshot) && mapping?(snapshot["document"]) ? snapshot["document"] : nil
  end

  def mechanical_result(errors:, case_snapshot: nil, review_snapshot: nil, extras: nil, independence: nil)
    extras = public_extras(extras)
    case_doc = snapshot_document(case_snapshot)
    {
      "schema_version" => MECHANICAL_RESULT_VERSION,
      "artifact_type" => "reference_evaluation_mechanical_result",
      "authority" => "structure_and_binding_only_never_semantic_quality_or_production_pass",
      "mechanical_closure" => errors.empty? ? "complete" : "incomplete",
      "production_pass" => false,
      "semantic_quality_determined" => false,
      "automatic_winner" => false,
      "category" => case_doc && case_doc["category"],
      "evidence_class" => case_doc && case_doc["evidence_class"],
      "time_claim_kind" => extras["time_claim_kind"],
      "bound_sequence_samples" => extras["bound_sequence_samples"],
      "time_span_alignment" => extras["time_span_alignment"],
      "independence" => independence || empty_independence,
      "case" => mapping?(case_snapshot) && case_snapshot["sha256"] && {
        "path" => case_snapshot["relative"],
        "sha256" => case_snapshot["sha256"]
      },
      "review" => mapping?(review_snapshot) && review_snapshot["sha256"] && {
        "path" => review_snapshot["relative"],
        "sha256" => review_snapshot["sha256"]
      },
      "findings" => errors
    }
  end

  def fail_closed(message, extras: nil, independence: nil)
    errors = ["reference evaluation failed closed: #{message}"]
    [errors, mechanical_result(errors: errors, extras: extras, independence: independence)]
  end

  def validate_case(root:, document:)
    extras = empty_case_extras
    errors = schema_errors_for_document(document, "case")
    if errors.empty? && mapping?(document)
      overlay_errors, extras = overlay_case(root, document)
      errors.concat(overlay_errors)
      errors.concat(final_freshness_errors(root, extras, case_document: document))
    end
    [errors, public_extras(extras)]
  rescue StandardError => e
    [["reference evaluation case failed closed: #{e.message}"], empty_case_extras]
  end

  def evaluate_case(root:, path:)
    snapshot = load_contained(root, path, "case")
    errors = snapshot["errors"].dup
    extras = empty_case_extras
    errors.concat(schema_errors_for_bytes(snapshot["bytes"], snapshot["extname"], "case")) if snapshot["bytes"]
    if errors.empty? && mapping?(snapshot["document"])
      overlay_errors, extras = overlay_case(root, snapshot["document"])
      errors.concat(overlay_errors)
      errors.concat(final_freshness_errors(root, extras, case_document: snapshot["document"]))
    end
    errors.concat(input_drift_errors(snapshot, "case"))
    result = mechanical_result(errors: errors, case_snapshot: snapshot, extras: extras)
    result["independent_review"] = "not_supplied"
    [errors, result]
  rescue StandardError => e
    errors, result = fail_closed(e.message)
    result["independent_review"] = "not_supplied"
    [errors, result]
  end

  def evaluate_pair(root:, case_path:, review_path:)
    extras = empty_case_extras
    independence = empty_independence
    case_loaded = load_contained(root, case_path, "case")
    review_loaded = load_contained(root, review_path, "review")
    errors = []
    errors.concat(case_loaded["errors"])
    errors.concat(review_loaded["errors"])
    case_schema = []
    review_schema = []
    if case_loaded["bytes"]
      case_schema = schema_errors_for_bytes(case_loaded["bytes"], case_loaded["extname"], "case")
      errors.concat(case_schema)
    end
    if review_loaded["bytes"]
      review_schema = schema_errors_for_bytes(review_loaded["bytes"], review_loaded["extname"], "review")
      errors.concat(review_schema)
    end

    verified = []
    if case_schema.empty? && mapping?(case_loaded["document"])
      overlay_errors, extras = overlay_case(root, case_loaded["document"])
      errors.concat(overlay_errors)
      verified = extras["verified_sources"] || []
    end
    if review_schema.empty? && mapping?(review_loaded["document"]) && mapping?(case_loaded["document"])
      review_errors, independence = overlay_review(
        root,
        review_loaded["document"],
        case_loaded["document"],
        case_loaded["relative"],
        case_loaded["sha256"],
        verified
      )
      errors.concat(review_errors)
    end
    errors.concat(
      final_freshness_errors(
        root,
        extras,
        case_document: case_loaded["document"],
        review_document: review_loaded["document"]
      )
    )
    errors.concat(input_drift_errors(case_loaded, "case"))
    errors.concat(input_drift_errors(review_loaded, "review"))
    [
      errors,
      mechanical_result(
        errors: errors,
        case_snapshot: case_loaded,
        review_snapshot: review_loaded,
        extras: extras,
        independence: independence
      )
    ]
  rescue StandardError => e
    fail_closed(e.message)
  end
end
