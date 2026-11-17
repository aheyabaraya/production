#!/usr/bin/env ruby
# frozen_string_literal: true

# Classify and close hash-only Department Dispatch drift without opening a
# worker session, native Goal, semantic review, or additional review submission.
# The applied receipt is deliberately narrow: every projected hash must already
# be corroborated by at least three receipts across two independent lifecycle
# phases, including the latest binding phase. Otherwise the script routes one
# impact recheck to the recipient Director and performs no write.

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "securerandom"
require "tempfile"
require "time"
require "yaml"

module IdolDepartmentTransportRefresh
  ROOT = Pathname.new(__dir__).join("..").expand_path.freeze
  SCHEMA = ROOT.join("schemas", "department-transport-refresh.schema.json").freeze
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py").freeze
  PYTHON = ROOT.join("scripts", "idol-video-python").freeze
  PHASES = %w[launch lineage runtime review promotion].freeze
  PROOF_RULE = "current_hash_bound_by_at_least_three_receipts_across_two_independent_phases_including_latest_binding_phase".freeze
  MINIMUM_CORROBORATING_BINDINGS = 3

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors).map(&:to_s)
      super(@errors.join("; "))
    end
  end

  module_function

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).uniq.sort.each_with_object({}) do |key, result|
        original = value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[original])
      end
    when Array
      value.map { |item| canonicalize(item) }
    when Date, Time, DateTime
      value.iso8601
    else
      value
    end
  end

  def structured_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def load_document(path)
    target = Pathname.new(path)
    text = target.read
    value = target.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, permitted_classes: [Date, Time, DateTime], aliases: true)
    raise ValidationError, ["#{path} must contain an object"] unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT, Errno::EACCES => e
    raise ValidationError, ["cannot load #{path}: #{e.message}"]
  end

  def resolve_path(raw, allow_missing: false)
    value = Pathname.new(raw.to_s)
    value = ROOT.join(value) unless value.absolute?
    value = value.expand_path.cleanpath
    root = ROOT.expand_path
    unless value == root || value.to_s.start_with?("#{root}#{File::SEPARATOR}")
      raise ValidationError, ["path escapes repository: #{raw}"]
    end
    if value.exist?
      real = value.realpath
      unless real == root || real.to_s.start_with?("#{root}#{File::SEPARATOR}")
        raise ValidationError, ["path resolves outside repository: #{raw}"]
      end
    elsif !allow_missing
      raise ValidationError, ["path is missing: #{raw}"]
    end
    value
  rescue Errno::ENOENT, Errno::EACCES => e
    raise ValidationError, ["cannot resolve #{raw}: #{e.message}"]
  end

  def relative_path(path)
    Pathname.new(path).expand_path.cleanpath.relative_path_from(ROOT).to_s
  rescue ArgumentError
    path.to_s
  end

  def pointer_tokens(pointer)
    pointer.to_s.split("/").drop(1).map { |token| token.gsub("~1", "/").gsub("~0", "~") }
  end

  def pointer_value(document, pointer)
    pointer_tokens(pointer).reduce(document) do |value, token|
      case value
      when Hash then value.fetch(token)
      when Array then value.fetch(Integer(token, 10))
      else raise KeyError, pointer
      end
    end
  rescue KeyError, IndexError, ArgumentError
    nil
  end

  def set_pointer!(document, pointer, replacement)
    tokens = pointer_tokens(pointer)
    raise ValidationError, ["invalid empty JSON pointer"] if tokens.empty?

    parent = tokens[0...-1].reduce(document) do |value, token|
      case value
      when Hash then value.fetch(token)
      when Array then value.fetch(Integer(token, 10))
      else raise KeyError, pointer
      end
    end
    key = tokens.last
    case parent
    when Hash
      raise KeyError, pointer unless parent.key?(key)
      parent[key] = replacement
    when Array
      parent.fetch(Integer(key, 10))
      parent[Integer(key, 10)] = replacement
    else
      raise KeyError, pointer
    end
  rescue KeyError, IndexError, ArgumentError
    raise ValidationError, ["refresh target JSON pointer is missing: #{pointer}"]
  end

  def add_binding(rows, row, base_pointer, label, phase, family, path_key: "path", sha_key: "sha256")
    return unless row.is_a?(Hash)
    return if row[path_key].to_s.empty? || row[sha_key].to_s.empty?

    rows << {
      "binding_label" => label,
      "target_json_pointer" => "#{base_pointer}/#{sha_key}",
      "source_path" => row[path_key].to_s,
      "phase" => phase,
      "family" => family,
      "previous_sha256" => row[sha_key].to_s
    }
  end

  def add_artifact_with_bindings(rows, artifact, base_pointer, label, phase, family)
    add_binding(rows, artifact, base_pointer, label, phase, family)
    Array(artifact.is_a?(Hash) ? artifact["bindings"] : nil).each_with_index do |binding, index|
      add_binding(
        rows,
        binding,
        "#{base_pointer}/bindings/#{index}",
        "#{label}.bindings[#{index}]",
        phase,
        "governing_input_receipt"
      )
    end
  end

  def dispatch_bindings(document)
    rows = []
    launch = document["launch"].is_a?(Hash) ? document["launch"] : {}
    compiled = launch["compiled_launch_prompt"].is_a?(Hash) ? launch["compiled_launch_prompt"] : {}
    add_binding(rows, compiled["studio_kernel"], "/launch/compiled_launch_prompt/studio_kernel", "launch.compiled_launch_prompt.studio_kernel", "launch", "governing_input_receipt")
    selected = compiled["selected_profile"]
    add_binding(
      rows,
      selected,
      "/launch/compiled_launch_prompt/selected_profile",
      "launch.compiled_launch_prompt.selected_profile.registry",
      "launch",
      "governing_input_receipt",
      path_key: "registry_path",
      sha_key: "registry_sha256"
    )
    Array(launch["requirement_manifest"]).each_with_index do |requirement, index|
      add_binding(rows, requirement.is_a?(Hash) ? requirement["source_binding"] : nil, "/launch/requirement_manifest/#{index}/source_binding", "launch.requirement_manifest[#{index}].source_binding", "launch", "governing_input_receipt")
    end
    Array(launch["required_skills"]).each_with_index do |skill, index|
      base = "/launch/required_skills/#{index}"
      add_binding(rows, skill, base, "launch.required_skills[#{index}]", "launch", "governing_input_receipt")
      Array(skill.is_a?(Hash) ? skill["linked_reads"] : nil).each_with_index do |read, read_index|
        add_binding(rows, read, "#{base}/linked_reads/#{read_index}", "launch.required_skills[#{index}].linked_reads[#{read_index}]", "launch", "governing_input_receipt")
      end
    end
    Array(launch["sources"]).each_with_index do |source, index|
      add_binding(rows, source, "/launch/sources/#{index}", "launch.sources[#{index}]", "launch", "governing_input_receipt")
    end

    submission = document["review_submission"].is_a?(Hash) ? document["review_submission"] : {}
    %w[repair_targets frozen_outputs].each do |field|
      Array(submission[field]).each_with_index do |artifact, index|
        add_artifact_with_bindings(rows, artifact, "/review_submission/#{field}/#{index}", "review_submission.#{field}[#{index}]", "lineage", "working_output_receipt")
      end
    end

    runtime = document["runtime_return"].is_a?(Hash) ? document["runtime_return"] : {}
    Array(runtime["skill_revisions"]).each_with_index do |skill, index|
      base = "/runtime_return/skill_revisions/#{index}"
      add_binding(rows, skill, base, "runtime_return.skill_revisions[#{index}]", "runtime", "governing_input_receipt")
      Array(skill.is_a?(Hash) ? skill["linked_reads"] : nil).each_with_index do |read, read_index|
        add_binding(rows, read, "#{base}/linked_reads/#{read_index}", "runtime_return.skill_revisions[#{index}].linked_reads[#{read_index}]", "runtime", "governing_input_receipt")
      end
    end
    Array(runtime["worker_fulfillment_claims"]).each_with_index do |claim, claim_index|
      Array(claim.is_a?(Hash) ? claim["output_evidence"] : nil).each_with_index do |artifact, evidence_index|
        add_artifact_with_bindings(rows, artifact, "/runtime_return/worker_fulfillment_claims/#{claim_index}/output_evidence/#{evidence_index}", "runtime_return.worker_fulfillment_claims[#{claim_index}].output_evidence[#{evidence_index}]", "runtime", "working_output_receipt")
      end
    end
    inventory = runtime["output_inventory"].is_a?(Hash) ? runtime["output_inventory"] : {}
    add_binding(rows, inventory["aggregate_manifest"], "/runtime_return/output_inventory/aggregate_manifest", "runtime_return.output_inventory.aggregate_manifest", "runtime", "manifest_or_evidence_receipt")
    Array(runtime["outputs"]).each_with_index do |artifact, index|
      add_artifact_with_bindings(rows, artifact, "/runtime_return/outputs/#{index}", "runtime_return.outputs[#{index}]", "runtime", "working_output_receipt")
    end
    wake = runtime["wake_event"].is_a?(Hash) ? runtime["wake_event"] : {}
    Array(wake["output_pointers"]).each_with_index do |artifact, index|
      add_artifact_with_bindings(rows, artifact, "/runtime_return/wake_event/output_pointers/#{index}", "runtime_return.wake_event.output_pointers[#{index}]", "runtime", "working_output_receipt")
    end
    add_binding(rows, wake["aggregate_manifest"], "/runtime_return/wake_event/aggregate_manifest", "runtime_return.wake_event.aggregate_manifest", "runtime", "manifest_or_evidence_receipt")

    review = document["director_review"].is_a?(Hash) ? document["director_review"] : {}
    Array(review["reviewer_read_closure"]).each_with_index do |read, index|
      add_binding(rows, read, "/director_review/reviewer_read_closure/#{index}", "director_review.reviewer_read_closure[#{index}]", "review", "governing_input_receipt")
    end
    Array(review["requirement_results"]).each_with_index do |result, index|
      add_binding(rows, result, "/director_review/requirement_results/#{index}", "director_review.requirement_results[#{index}].evidence", "review", "manifest_or_evidence_receipt", path_key: "evidence_locator", sha_key: "evidence_sha256")
    end
    Array(review["reviewed_outputs"]).each_with_index do |artifact, index|
      add_artifact_with_bindings(rows, artifact, "/director_review/reviewed_outputs/#{index}", "director_review.reviewed_outputs[#{index}]", "review", "working_output_receipt")
    end
    correction = review["correction"].is_a?(Hash) ? review["correction"] : {}
    Array(correction["evidence"]).each_with_index do |evidence, index|
      add_binding(rows, evidence, "/director_review/correction/evidence/#{index}", "director_review.correction.evidence[#{index}]", "review", "manifest_or_evidence_receipt", path_key: "locator", sha_key: "source_sha256")
    end
    Array(correction["invalidated_outputs"]).each_with_index do |artifact, index|
      add_artifact_with_bindings(rows, artifact, "/director_review/correction/invalidated_outputs/#{index}", "director_review.correction.invalidated_outputs[#{index}]", "review", "working_output_receipt")
    end

    promotion = document["promotion"].is_a?(Hash) ? document["promotion"] : {}
    Array(promotion["approved_working_outputs"]).each_with_index do |artifact, index|
      add_artifact_with_bindings(rows, artifact, "/promotion/approved_working_outputs/#{index}", "promotion.approved_working_outputs[#{index}]", "promotion", "working_output_receipt")
    end
    Array(promotion["canonical_artifacts"]).each_with_index do |artifact, index|
      add_artifact_with_bindings(rows, artifact, "/promotion/canonical_artifacts/#{index}", "promotion.canonical_artifacts[#{index}]", "promotion", "canonical_output_receipt")
    end
    rows
  end

  def latest_completed_phase(document)
    return "promotion" if document["promotion"].is_a?(Hash)
    return "review" if document["director_review"].is_a?(Hash)
    return "runtime" if document["runtime_return"].is_a?(Hash)

    "launch"
  end

  def logical_phase(row)
    return "output" if row["family"].to_s == "working_output_receipt"
    return "canonical" if row["family"].to_s == "canonical_output_receipt"

    row["phase"].to_s
  end

  def output_snapshot(document)
    dispatch_bindings(document).select do |row|
      %w[working_output_receipt canonical_output_receipt].include?(row["family"])
    end.map do |row|
      path = resolve_path(row["source_path"])
      {
        "phase" => row["phase"],
        "path" => row["source_path"],
        "recorded_sha256" => row["previous_sha256"],
        "current_sha256" => Digest::SHA256.file(path.to_s).hexdigest
      }
    rescue ValidationError
      nil
    end.compact.sort_by { |row| [row["phase"], row["path"], row["recorded_sha256"]] }
  end

  def classify_document(document, dispatch_path: nil)
    bindings = dispatch_bindings(document)
    missing = []
    enriched = bindings.map do |row|
      begin
        path = resolve_path(row["source_path"])
        unless path.file?
          missing << row["source_path"]
          next row.merge("current_sha256" => nil)
        end
        row.merge("current_sha256" => Digest::SHA256.file(path.to_s).hexdigest)
      rescue ValidationError
        missing << row["source_path"]
        row.merge("current_sha256" => nil)
      end
    end
    mismatches = enriched.select { |row| row["current_sha256"].to_s != row["previous_sha256"].to_s }
    latest_phase = latest_completed_phase(document)
    targets = []
    blockers = []
    mismatches.group_by { |row| row["source_path"] }.each do |source_path, stale_rows|
      group = enriched.select { |row| row["source_path"] == source_path }
      current = stale_rows.first["current_sha256"].to_s
      consensus = group.select { |row| !current.empty? && row["previous_sha256"] == current }
      phases = consensus.map { |row| row["phase"] }.uniq.sort_by { |phase| PHASES.index(phase) || 99 }
      logical_phases = consensus.map { |row| logical_phase(row) }.uniq
      required_latest_phase = group.map { |row| row["phase"] }.max_by { |phase| PHASES.index(phase) || -1 }
      required_latest_logical_phase = logical_phase(group.max_by { |row| PHASES.index(row["phase"]) || -1 })
      eligible = current.match?(/\A[a-f0-9]{64}\z/) &&
                 consensus.length >= MINIMUM_CORROBORATING_BINDINGS &&
                 logical_phases.length >= 2 &&
                 logical_phases.include?(required_latest_logical_phase)
      if eligible
        pointers = consensus.map { |row| row["target_json_pointer"] }.uniq.sort
        stale_rows.each do |row|
          targets << row.merge(
            "consensus_phases" => phases,
            "consensus_json_pointers" => pointers
          )
        end
      else
        blockers << {
          "source_path" => source_path,
          "family" => stale_rows.map { |row| row["family"] }.uniq.sort,
          "stale_bindings" => stale_rows.map { |row| row["target_json_pointer"] }.sort,
          "current_consensus_phases" => phases,
          "required_latest_phase" => required_latest_phase
        }
      end
    end

    status = if !missing.empty?
               "missing_bound_bytes_hold"
             elsif mismatches.empty?
               "current"
             elsif blockers.empty?
               "mechanical_refresh_eligible"
             elsif blockers.any? { |row| (row["family"] & %w[working_output_receipt canonical_output_receipt]).any? }
               "director_output_receipt_recheck_required"
             else
               "director_input_impact_recheck_required"
             end
    {
      "status" => status,
      "dispatch_path" => dispatch_path ? relative_path(dispatch_path) : nil,
      "dispatch_id" => document["dispatch_id"].to_s,
      "run" => document["run"].to_s,
      "latest_completed_phase" => latest_phase,
      "mismatch_count" => mismatches.length,
      "refresh_target_count" => targets.length,
      "targets" => targets.sort_by { |row| row["target_json_pointer"] },
      "blockers" => blockers,
      "missing_paths" => missing.uniq.sort,
      "next_owner" => status == "mechanical_refresh_eligible" ? "mechanical_coordinator" : "original_recipient_director",
      "worker_session_opened" => false,
      "native_goal_opened" => false,
      "review_submission_incremented" => false,
      "quality_route" => status.start_with?("director_") ? "director_rechecks_impact_once_before_any_targeted_creative_correction" : "existing_creative_review_receipt_carried_forward"
    }
  end

  def receipt_without_digest(receipt)
    receipt.reject { |key, _value| key.to_s == "receipt_sha256" }
  end

  def build_receipt(document, dispatch_path, owner:, created_at: Time.now.utc.iso8601)
    classification = classify_document(document, dispatch_path: dispatch_path)
    unless classification["status"] == "mechanical_refresh_eligible"
      raise ValidationError, ["dispatch is not eligible for mechanical refresh: #{classification['status']}"]
    end
    submission = document["review_submission"].is_a?(Hash) ? document["review_submission"] : {}
    source_sha = Digest::SHA256.file(dispatch_path.to_s).hexdigest
    target_basis = classification["targets"].map { |row| [row["target_json_pointer"], row["current_sha256"]] }
    refresh_id = "REFRESH_#{document['dispatch_id']}_#{structured_sha256(target_basis)[0, 12]}"
    receipt = {
      "schema_version" => "idol-department-transport-refresh.v1",
      "artifact_type" => "department_transport_refresh",
      "refresh_id" => refresh_id,
      "run" => document["run"].to_s,
      "created_at" => created_at,
      "status" => "applied",
      "owner" => {"owner" => owner.to_s, "role" => "mechanical_coordinator"},
      "source_dispatch" => {
        "dispatch_id" => document["dispatch_id"].to_s,
        "path" => relative_path(dispatch_path),
        "sha256" => source_sha,
        "review_cycle_id" => submission["review_cycle_id"].to_s,
        "submission_number" => submission["submission_number"].to_i
      },
      "classification" => {
        "kind" => "corroborated_duplicate_binding_hash_reconciliation",
        "proof_rule" => PROOF_RULE,
        "hash_only" => true,
        "creative_bytes_written" => false,
        "governing_input_reinterpreted" => false,
        "worker_session_opened" => false,
        "native_goal_opened" => false,
        "semantic_review_reopened" => false,
        "review_submission_incremented" => false,
        "dispatch_bytes_rewritten" => false
      },
      "bindings" => classification["targets"].map do |row|
        row.slice(
          "binding_label",
          "target_json_pointer",
          "source_path",
          "phase",
          "family",
          "previous_sha256",
          "current_sha256",
          "consensus_phases",
          "consensus_json_pointers"
        )
      end,
      "output_snapshot" => output_snapshot(document),
      "effect" => {
        "active_for_validation" => true,
        "only_listed_hash_fields_projected" => true,
        "creative_goal_required" => false,
        "review_submission_number_before" => submission["submission_number"].to_i,
        "review_submission_number_after" => submission["submission_number"].to_i,
        "next_owner" => "original_recipient_director"
      },
      "receipt_sha256" => "0" * 64
    }
    receipt["receipt_sha256"] = structured_sha256(receipt_without_digest(receipt))
    receipt
  end

  def schema_errors(receipt)
    Tempfile.create(["idol-department-transport-refresh-", ".yaml"], "/private/tmp") do |file|
      file.write(YAML.dump(receipt))
      file.flush
      stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, file.path, chdir: ROOT.to_s)
      return [] if status.success?

      ["schema validation failed: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}"]
    end
  rescue Errno::ENOENT, Errno::EACCES => e
    ["cannot create schema validation scratch: #{e.message}"]
  end

  def validate_receipt(receipt_path)
    path = resolve_path(receipt_path)
    receipt = load_document(path)
    errors = schema_errors(receipt)
    run = receipt["run"].to_s
    refresh_id = receipt["refresh_id"].to_s
    expected_path = ROOT.join(run, "work", "department-transport-refreshes", "#{refresh_id}.yaml").expand_path
    errors << "transport refresh receipt must live at #{relative_path(expected_path)}" unless path == expected_path
    errors << "transport refresh receipt SHA-256 is stale" unless receipt["receipt_sha256"].to_s == structured_sha256(receipt_without_digest(receipt))

    source = receipt["source_dispatch"].is_a?(Hash) ? receipt["source_dispatch"] : {}
    begin
      dispatch_path = resolve_path(source["path"])
      errors << "source dispatch SHA-256 is stale" unless Digest::SHA256.file(dispatch_path.to_s).hexdigest == source["sha256"].to_s
      document = load_document(dispatch_path)
      errors << "source dispatch id does not match receipt" unless document["dispatch_id"].to_s == source["dispatch_id"].to_s
      errors << "source dispatch run does not match receipt" unless document["run"].to_s == run
      errors << "source dispatch review cycle does not match receipt" unless document.dig("review_submission", "review_cycle_id").to_s == source["review_cycle_id"].to_s
      before = receipt.dig("effect", "review_submission_number_before").to_i
      after = receipt.dig("effect", "review_submission_number_after").to_i
      actual_submission = document.dig("review_submission", "submission_number").to_i
      errors << "transport refresh may not change the review submission number" unless before == after && before == actual_submission && source["submission_number"].to_i == actual_submission

      classification = classify_document(document, dispatch_path: dispatch_path)
      errors << "source dispatch is no longer mechanically refreshable: #{classification['status']}" unless classification["status"] == "mechanical_refresh_eligible"
      expected_bindings = classification["targets"].map do |row|
        row.slice(
          "binding_label",
          "target_json_pointer",
          "source_path",
          "phase",
          "family",
          "previous_sha256",
          "current_sha256",
          "consensus_phases",
          "consensus_json_pointers"
        )
      end
      unless canonicalize(receipt["bindings"]) == canonicalize(expected_bindings)
        errors << "transport refresh bindings must exact-cover the currently eligible hash-only mismatches"
      end
      unless canonicalize(receipt["output_snapshot"]) == canonicalize(output_snapshot(document))
        errors << "transport refresh output snapshot is stale"
      end
    rescue ValidationError => e
      errors.concat(e.errors)
      document = nil
    end
    raise ValidationError, errors unless errors.empty?

    {"receipt" => receipt, "dispatch" => document, "dispatch_path" => dispatch_path}
  end

  def project_dispatch(document, receipt)
    projected = deep_copy(document)
    Array(receipt["bindings"]).each do |binding|
      pointer = binding["target_json_pointer"].to_s
      previous = pointer_value(document, pointer).to_s
      unless previous == binding["previous_sha256"].to_s
        raise ValidationError, ["refresh target previous hash no longer matches source dispatch: #{pointer}"]
      end
      set_pointer!(projected, pointer, binding["current_sha256"].to_s)
    end
    projected
  end

  def write_receipt(dispatch_path, owner:, created_at: Time.now.utc.iso8601)
    raise ValidationError, ["mechanical coordinator owner is required"] if owner.to_s.strip.empty?

    source_path = resolve_path(dispatch_path)
    document = load_document(source_path)
    receipt = build_receipt(document, source_path, owner: owner, created_at: created_at)
    destination = ROOT.join(receipt["run"], "work", "department-transport-refreshes", "#{receipt['refresh_id']}.yaml")
    destination.dirname.mkpath
    if destination.file?
      existing = load_document(destination)
      unless canonicalize(existing) == canonicalize(receipt)
        # created_at is evidence metadata, so an already-valid deterministic
        # receipt is returned idempotently even when this invocation is later.
        existing_without_time = deep_copy(existing)
        receipt_without_time = deep_copy(receipt)
        existing_without_time["created_at"] = receipt_without_time["created_at"]
        existing_without_time["receipt_sha256"] = structured_sha256(receipt_without_digest(existing_without_time))
        unless canonicalize(existing_without_time) == canonicalize(receipt_without_time)
          raise ValidationError, ["deterministic transport refresh receipt already exists with different content: #{relative_path(destination)}"]
        end
      end
      validate_receipt(destination)
      return destination
    end

    Tempfile.create([".#{receipt['refresh_id']}-", ".yaml"], destination.dirname.to_s) do |file|
      file.write(YAML.dump(receipt))
      file.flush
      file.fsync
      File.rename(file.path, destination.to_s)
    end
    validate_receipt(destination)
    destination
  end

  def applicable_receipts(dispatch_path)
    source = resolve_path(dispatch_path)
    document = load_document(source)
    directory = ROOT.join(document["run"].to_s, "work", "department-transport-refreshes")
    return [] unless directory.directory?

    directory.children.select(&:file?).select { |path| %w[.yaml .yml].include?(path.extname.downcase) }.select do |path|
      begin
        receipt = load_document(path)
        receipt.dig("source_dispatch", "path").to_s == relative_path(source) &&
          receipt.dig("source_dispatch", "sha256").to_s == Digest::SHA256.file(source.to_s).hexdigest
      rescue ValidationError
        false
      end
    end.sort
  end
end

if $PROGRAM_NAME == __FILE__
  command = ARGV.shift.to_s
  options = {json: false, owner: nil, created_at: nil}
  OptionParser.new do |parser|
    parser.on("--json") { options[:json] = true }
    parser.on("--owner OWNER") { |value| options[:owner] = value }
    parser.on("--created-at TIMESTAMP") { |value| options[:created_at] = value }
  end.parse!(ARGV)
  argument = ARGV.shift
  if argument.to_s.empty? || !ARGV.empty? || !%w[classify write validate].include?(command)
    warn "usage: ruby scripts/idol_department_transport_refresh.rb classify|write|validate [--json] [--owner OWNER] [--created-at ISO8601] PATH"
    exit 2
  end

  begin
    case command
    when "classify"
      path = IdolDepartmentTransportRefresh.resolve_path(argument)
      document = IdolDepartmentTransportRefresh.load_document(path)
      result = IdolDepartmentTransportRefresh.classify_document(document, dispatch_path: path)
    when "write"
      path = IdolDepartmentTransportRefresh.write_receipt(
        argument,
        owner: options[:owner],
        created_at: options[:created_at] || Time.now.utc.iso8601
      )
      validated = IdolDepartmentTransportRefresh.validate_receipt(path)
      result = {
        "status" => "pass",
        "receipt_path" => IdolDepartmentTransportRefresh.relative_path(path),
        "receipt_sha256" => Digest::SHA256.file(path.to_s).hexdigest,
        "dispatch_id" => validated.dig("receipt", "source_dispatch", "dispatch_id"),
        "review_submission_incremented" => false,
        "native_goal_opened" => false
      }
    when "validate"
      validated = IdolDepartmentTransportRefresh.validate_receipt(argument)
      result = {
        "status" => "pass",
        "receipt_path" => IdolDepartmentTransportRefresh.relative_path(argument),
        "dispatch_id" => validated.dig("receipt", "source_dispatch", "dispatch_id"),
        "binding_count" => Array(validated.dig("receipt", "bindings")).length,
        "review_submission_incremented" => false,
        "native_goal_opened" => false
      }
    end
    puts(options[:json] ? JSON.pretty_generate(result) : result.map { |key, value| "#{key}=#{value}" }.join(" "))
  rescue IdolDepartmentTransportRefresh::ValidationError => e
    if options[:json]
      puts JSON.pretty_generate("status" => "fail", "errors" => e.errors)
    else
      e.errors.each { |error| warn error }
    end
    exit 1
  end
end
