#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic, pointer-only projections for the Department Dispatch v8 lane.
#
# This command intentionally has no creative defaults and no canonical-stage
# write authority.  It reads immutable Department Dispatch attempts, validates
# their exact path/hash bindings, and (when explicitly asked) rebuilds the
# run-owned derived index, the typed CDD successor Boot Pack v3, or the
# provider-neutral CDD physical-session router control state.  Router state is
# operational authority metadata only; it never contains or authors creative
# truth.

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "securerandom"
require "rbconfig"
require "tempfile"
require "time"
require "tmpdir"
require "yaml"
require_relative "idol_department_transport_refresh"

module IdolDirectorDispatchIndex
  ROOT = Pathname.new(__dir__).join("..").expand_path.freeze
  INDEX_SCHEMA = ROOT.join("schemas", "director-dispatch-index.schema.json").freeze
  BOOT_SCHEMA = ROOT.join("schemas", "director-boot-pack.schema.json").freeze
  CDD_ROUTER_STATE_SCHEMA = ROOT.join("schemas", "cdd-session-router-state.schema.json").freeze
  REFERENCE_SCHEMA = ROOT.join("schemas", "reference-working-index.schema.json").freeze
  DISPATCH_SCHEMA = ROOT.join("schemas", "department-dispatch.schema.json").freeze
  DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb").freeze
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py").freeze
  PYTHON = ROOT.join("scripts", "idol-video-python").freeze
  DISPATCH_DIR_NAME = "department-dispatches"
  SOURCE_DIGEST_BASIS = "sorted_pointer_path_hash_pairs_v1"
  INDEX_SOURCE_DIGEST_BASIS = "sorted_pointer_path_hash_pairs_and_dispatch_admission_v2"
  DISPATCH_SOURCE_SET_BASIS = "sorted_dispatch_path_hash_classification_v1"
  INDEX_SCHEMA_VERSION = "idol-director-dispatch-index.v4"
  LEGACY_INDEX_SCHEMA_VERSION = "idol-director-dispatch-index.v3"
  CURRENT_DISPATCH_SCHEMA_VERSION = "idol-department-dispatch.v8"
  PINNED_LEGACY_DISPATCH_SCHEMA_VERSIONS = ["idol-department-dispatch.v4"].freeze
  CDD_SUCCESSOR_BOOT_SCHEMA_VERSION = "idol-director-boot-pack.v3"
  CDD_ROUTER_STATE_SCHEMA_VERSION = "idol-cdd-session-router-state.v1"
  CDD_SESSION_KEY = "creative_development_director:development-through-03v"
  CDD_ROUTER_ASSIGNMENT_ID = "creative_development_director:development-through-03v"
  CDD_ROUTER_OPERATIONS = %w[goal_and_preflight prompt resume dispatch review canonical_write].freeze
  NONSECRET_CHILD_ENV = {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil}.freeze
  CDD_SUCCESSOR_QUESTIONS = %w[
    scope_and_authority
    founder_locks_and_proposals
    current_recommendation_and_reason
    do_not_revive
    unresolved_decisions
    heads_evidence_and_pending_owner
    next_stop_and_wake
  ].freeze

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
      keys = value.keys.map(&:to_s).uniq.sort
      keys.each_with_object({}) do |key, result|
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

  def canonical_json(value)
    JSON.generate(canonicalize(value))
  end

  def digest_value(value)
    Digest::SHA256.hexdigest(canonical_json(value))
  end

  def sha256(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def load_document(path)
    text = Pathname.new(path).read
    value = if Pathname.new(path).extname.downcase == ".json"
              JSON.parse(text)
            else
              YAML.safe_load(text, permitted_classes: [Date, Time, DateTime], aliases: true)
            end
    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT, Errno::EACCES => e
    raise ValidationError, ["cannot load #{path}: #{e.message}"]
  end

  def hash_document(path)
    value = load_document(path)
    raise ValidationError, ["#{path} must contain an object"] unless value.is_a?(Hash)

    value
  end

  def relative_path(path)
    Pathname.new(path).expand_path.cleanpath.relative_path_from(ROOT.expand_path).to_s
  rescue ArgumentError
    path.to_s
  end

  def resolve_path(raw, allow_missing: false)
    text = raw.to_s
    raise ValidationError, ["path is empty"] if text.empty?

    candidate = Pathname.new(text)
    candidate = ROOT.join(candidate) unless candidate.absolute?
    candidate = candidate.expand_path.cleanpath
    root = ROOT.expand_path
    unless candidate == root || candidate.to_s.start_with?("#{root}#{File::SEPARATOR}")
      raise ValidationError, ["path escapes repository: #{text}"]
    end
    if candidate.exist?
      real = candidate.realpath
      unless real == root || real.to_s.start_with?("#{root}#{File::SEPARATOR}")
        raise ValidationError, ["path resolves outside repository: #{text}"]
      end
    elsif !allow_missing
      raise ValidationError, ["path is missing: #{text}"]
    end
    candidate
  rescue Errno::ENOENT, Errno::EACCES => e
    raise ValidationError, ["cannot resolve #{text}: #{e.message}"]
  end

  def repo_relative?(text)
    value = text.to_s
    return false if value.empty? || value.start_with?("/") || value.include?("\\")

    path = Pathname.new(value)
    return false if value == "." || value.start_with?("./")

    path.cleanpath.to_s == value && !path.each_filename.any? { |part| part == ".." }
  rescue ArgumentError
    false
  end

  def pointer(path, role = nil)
    row = {"path" => relative_path(path), "sha256" => sha256(path)}
    row["role"] = role.to_s unless role.to_s.empty?
    row
  end

  def pointer_hash?(value)
    value.is_a?(Hash) && value.key?("path") && value.key?("sha256")
  end

  # Return every pointer-shaped hash in stable path/hash order.  The index and
  # reference schemas are pointer-only, so this is also a useful guard against
  # accidentally embedding a byte payload.
  def pointer_pairs(value, rows = [])
    case value
    when Hash
      rows << [value["path"].to_s, value["sha256"].to_s] if pointer_hash?(value)
      value.each_value { |child| pointer_pairs(child, rows) }
    when Array
      value.each { |child| pointer_pairs(child, rows) }
    end
    rows
  end

  def unique_sorted_pairs(pairs)
    Array(pairs).map { |path, digest| [path.to_s, digest.to_s] }.uniq.sort
  end

  def source_set_digest(pairs)
    rows = unique_sorted_pairs(pairs)
    Digest::SHA256.hexdigest(JSON.generate(rows))
  end

  def director_index_source_set_digest(pairs, dispatch_admission_sha256)
    digest_value(
      "pointer_pairs" => unique_sorted_pairs(pairs),
      "dispatch_admission_sha256" => dispatch_admission_sha256.to_s
    )
  end

  def timestamp_for(paths, fallback: nil)
    mtimes = Array(paths).map do |path|
      begin
        Pathname.new(path).mtime
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
    end.compact
    value = mtimes.max || fallback || Time.now
    value.utc.iso8601
  end

  def schema_errors(schema, document_path)
    stdout, stderr, status = Open3.capture3(
      NONSECRET_CHILD_ENV,
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      schema.to_s,
      document_path.to_s,
      chdir: ROOT.to_s
    )
    return [] if status.success?

    text = [stderr, stdout].reject { |item| item.to_s.strip.empty? }.join(" ").strip
    ["schema validation failed for #{relative_path(document_path)}: #{text}"]
  end

  def require_schema!(schema, path, errors)
    errors.concat(schema_errors(schema, path))
  end

  def dispatch_contract_errors(path, transport_refresh_path = nil)
    arguments = [
      RbConfig.ruby,
      DISPATCH_VALIDATOR.to_s,
      "--json"
    ]
    if transport_refresh_path
      arguments.concat(["--transport-refresh", relative_path(transport_refresh_path)])
    end
    arguments << relative_path(path)
    stdout, stderr, status = Open3.capture3(
      *arguments,
      chdir: ROOT.to_s
    )
    return [] if status.success?

    parsed = JSON.parse(stdout)
    Array(parsed["errors"]).map { |error| "#{relative_path(path)}: #{error}" }
  rescue JSON::ParserError
    ["department dispatch validator failed for #{relative_path(path)}: #{[stderr, stdout].join(' ').strip}"]
  end

  def effective_dispatch(path, errors)
    raw = hash_document(path)
    candidates = IdolDepartmentTransportRefresh.applicable_receipts(path)
    if candidates.length > 1
      errors << "#{relative_path(path)} has multiple applicable transport refresh receipts; keep one unambiguous current receipt"
      return [raw, raw, nil]
    end
    if candidates.empty?
      classification = IdolDepartmentTransportRefresh.classify_document(raw, dispatch_path: path)
      if classification["status"] == "mechanical_refresh_eligible"
        errors << "#{relative_path(path)} has corroborated hash-only drift; one mechanical coordinator must write the run-local transport refresh receipt without opening a worker Goal or review submission"
      elsif classification["status"].to_s.start_with?("director_")
        errors << "#{relative_path(path)} requires one recipient-Director impact recheck before any worker correction: #{classification['status']}"
      end
      return [raw, raw, nil]
    end

    refresh_path = candidates.first
    validated = IdolDepartmentTransportRefresh.validate_receipt(refresh_path)
    projected = IdolDepartmentTransportRefresh.project_dispatch(raw, validated.fetch("receipt"))
    [projected, raw, refresh_path]
  rescue IdolDepartmentTransportRefresh::ValidationError => e
    errors.concat(e.errors.map { |message| "#{relative_path(path)} transport refresh: #{message}" })
    [raw || {}, raw || {}, nil]
  end

  def schema_errors_for_document(schema, document, label)
    Tempfile.create(["idol-dispatch-index-", ".yaml"], "/private/tmp") do |file|
      file.write(YAML.dump(document))
      file.flush
      schema_errors(schema, Pathname.new(file.path)).map do |error|
        error.sub(Pathname.new(file.path).to_s, label.to_s)
      end
    end
  rescue Errno::ENOENT, Errno::EACCES => e
    ["cannot create schema-validation scratch for #{label}: #{e.message}"]
  end

  def ensure_hash!(value, label, errors)
    return value if value.is_a?(Hash)

    errors << "#{label} must be an object"
    {}
  end

  def ensure_array(value, label, errors)
    return value if value.is_a?(Array)

    errors << "#{label} must be an array"
    []
  end

  def pointer_binding_errors(value, label, errors, require_file: true)
    unless pointer_hash?(value)
      errors << "#{label} must be a path/hash pointer"
      return nil
    end
    path_text = value["path"].to_s
    errors << "#{label}.path must be repository-relative" unless repo_relative?(path_text)
    begin
      path = resolve_path(path_text, allow_missing: !require_file)
      if require_file && !path.file?
        errors << "#{label} target is missing: #{path_text}"
      elsif require_file && value["sha256"].to_s != sha256(path)
        errors << "#{label} SHA-256 is stale: #{path_text}"
      end
      path
    rescue ValidationError => e
      errors.concat(e.errors.map { |message| "#{label}: #{message}" })
      nil
    end
  end

  def no_embedded_bytes_errors(value, label = "$", errors = [])
    case value
    when Hash
      value.each do |key, child|
        key_text = key.to_s
        if %w[bytes media_bytes binary_data base64_data embedded_bytes].include?(key_text)
          errors << "#{label}.#{key_text} is forbidden in a pointer-only read model"
        end
        no_embedded_bytes_errors(child, "#{label}.#{key_text}", errors)
      end
    when Array
      value.each_with_index { |child, index| no_embedded_bytes_errors(child, "#{label}[#{index}]", errors) }
    end
    errors
  end

  def lifecycle_timestamp(document, state)
    Array(document.dig("lifecycle", "events")).find { |event| event.is_a?(Hash) && event["state"].to_s == state.to_s }&.fetch("at", nil)
  end

  def expected_input_digest(document)
    digest_value(
      {
        "lineage" => document["lineage"],
        "review_submission" => document["review_submission"],
        "launch" => document["launch"]
      }
    )
  end

  def expected_result_digest(runtime_return)
    digest_value(
      {
        "work_started_at" => runtime_return["work_started_at"],
        "runtime_owner" => runtime_return["runtime_owner"],
        "runtime_goal" => runtime_return["runtime_goal"],
        "skill_revisions" => runtime_return["skill_revisions"],
        "mechanical_compliance_receipt" => runtime_return["mechanical_compliance_receipt"],
        "worker_fulfillment_claims" => runtime_return["worker_fulfillment_claims"],
        "output_inventory" => runtime_return["output_inventory"],
        "outputs" => runtime_return["outputs"],
        "hold_reasons" => runtime_return["hold_reasons"],
        "wake_event" => runtime_return["wake_event"]
      }
    )
  end

  def validate_dispatch_bindings(document, dispatch_path, run_rel, errors)
    dispatch_id = document["dispatch_id"].to_s
    launch = ensure_hash!(document["launch"], "#{dispatch_id}.launch", errors)
    lineage = ensure_hash!(document["lineage"], "#{dispatch_id}.lineage", errors)
    scope = ensure_hash!(launch["task"].is_a?(Hash) ? launch["task"]["exact_scope"] : nil, "#{dispatch_id}.launch.task.exact_scope", errors)
    expected_paths = Array(scope["artifact_paths"]).map(&:to_s)
    source_ids = {}
    Array(launch["sources"]).each_with_index do |source, index_number|
      label = "#{dispatch_id}.launch.sources[#{index_number}]"
      pointer_binding_errors(source, label, errors)
      source_ids[source["source_id"].to_s] = source if source.is_a?(Hash)
    end
    Array(launch["required_skills"]).each_with_index do |skill, index_number|
      label = "#{dispatch_id}.launch.required_skills[#{index_number}]"
      pointer_binding_errors(skill, label, errors)
      Array(skill.is_a?(Hash) ? skill["linked_reads"] : []).each_with_index do |read, read_index|
        pointer_binding_errors(read, "#{label}.linked_reads[#{read_index}]", errors)
      end
    end
    runtime = document["runtime_return"]
    if runtime.is_a?(Hash)
      outputs = Array(runtime["outputs"])
      inventory = runtime["output_inventory"].is_a?(Hash) ? runtime["output_inventory"] : {}
      errors << "#{dispatch_id} output_inventory artifact_count is stale" unless inventory["artifact_count"].to_i == outputs.length
      if outputs.length > 1
        pointer_binding_errors(inventory["aggregate_manifest"], "#{dispatch_id}.runtime_return.output_inventory.aggregate_manifest", errors)
        errors << "#{dispatch_id} multiple outputs require an aggregate manifest" if inventory["aggregate_manifest"].nil?
      end
      outputs.each_with_index do |output, index_number|
        label = "#{dispatch_id}.runtime_return.outputs[#{index_number}]"
        pointer_binding_errors(output, label, errors)
        errors << "#{label} is outside exact scope" unless expected_paths.include?(output["path"].to_s)
      end
    end
    Array(document.dig("director_review", "reviewed_outputs")).each_with_index do |output, index_number|
      pointer_binding_errors(output, "#{dispatch_id}.director_review.reviewed_outputs[#{index_number}]", errors)
    end
    promotion = document["promotion"]
    if promotion.is_a?(Hash)
      Array(promotion["approved_working_outputs"]).each_with_index do |output, index_number|
        pointer_binding_errors(output, "#{dispatch_id}.promotion.approved_working_outputs[#{index_number}]", errors)
      end
      Array(promotion["canonical_artifacts"]).each_with_index do |output, index_number|
        pointer_binding_errors(output, "#{dispatch_id}.promotion.canonical_artifacts[#{index_number}]", errors)
      end
    end
    errors << "#{dispatch_id} lineage attempt_id must equal dispatch_id" unless lineage["attempt_id"].to_s == dispatch_id
    errors << "#{dispatch_id} run must equal #{run_rel}" unless document["run"].to_s == run_rel
    errors
  end

  def underlying_dispatch_pairs(index, errors)
    Array(index["dispatches"]).flat_map do |row|
      next [] unless row.is_a?(Hash) && pointer_hash?(row["dispatch_pointer"])

      begin
        dispatch_path = resolve_path(row["dispatch_pointer"]["path"])
        raw = hash_document(dispatch_path)
        refresh_pointer = row["transport_refresh_receipt"]
        document = if pointer_hash?(refresh_pointer)
                     validated = IdolDepartmentTransportRefresh.validate_receipt(resolve_path(refresh_pointer["path"]))
                     IdolDepartmentTransportRefresh.project_dispatch(raw, validated.fetch("receipt"))
                   else
                     raw
                   end
        pointer_pairs(document)
      rescue ValidationError => e
        errors.concat(e.errors)
        []
      rescue IdolDepartmentTransportRefresh::ValidationError => e
        errors.concat(e.errors)
        []
      end
    end
  end

  def stage_registry_document
    path = ROOT.join("automation", "harness-stage-registry.yaml")
    [path, hash_document(path)]
  end

  def active_stage_order(stage_registry)
    rows = Array(stage_registry["phases"]).flat_map { |phase| Array(phase.is_a?(Hash) ? phase["stage_ids"] : []) }
    order = {}
    rows.each_with_index { |stage_id, index| order[stage_id.to_s] = index }
    Array(stage_registry["stages"]).each_with_index do |stage, index|
      next unless stage.is_a?(Hash)

      order[stage["stage_id"].to_s] ||= stage["order"].to_i + index
    end
    order
  end

  def active_stage_ids(stage_registry)
    Array(stage_registry["stages"]).map do |stage|
      next unless stage.is_a?(Hash) && stage.fetch("active", true)

      stage["stage_id"].to_s
    end.compact
  end

  def dispatch_paths(run_path)
    root = run_path.join("work", DISPATCH_DIR_NAME)
    return [] unless root.directory?

    Dir.glob(root.join("*.yaml").to_s).sort.map do |path|
      candidate = Pathname.new(path).cleanpath
      resolve_path(relative_path(candidate))
    end
  end

  def repository_path_contract?(value)
    text = value.to_s
    return true if text == "AGENTS.md"

    %w[
      .codex/ .grok/ automation/ assets/ catalog/ cf/ development/ handoff/
      policies/ reference-library/ references/ runs/ schemas/ scripts/ skills/
      source-materials/ wiki/
    ].any? { |prefix| text.start_with?(prefix) && text.length > prefix.length } && repo_relative?(text)
  end

  def dispatch_id_contract?(value)
    value.to_s.match?(/\A[A-Za-z0-9][-_A-Za-z0-9.:]{2,140}\z/)
  end

  def admission_dispatch_id(document, path)
    authored = document.is_a?(Hash) ? document["dispatch_id"].to_s : ""
    return authored if dispatch_id_contract?(authored)

    fallback = token(path.basename(path.extname).to_s, "DISPATCH_UNREADABLE")
    return fallback if dispatch_id_contract?(fallback)

    "DISPATCH_UNREADABLE_#{Digest::SHA256.hexdigest(path.to_s)[0, 16].upcase}"
  end

  def admission_scope(document)
    scope = document.is_a?(Hash) ? document.dig("launch", "task", "exact_scope") : nil
    scope = {} unless scope.is_a?(Hash)
    stage = scope["stage_id"].to_s
    stage = nil if stage.empty?
    stage = token(stage, "stage_unknown") if stage
    stage = nil unless stage.nil? || stage.match?(/\A[A-Za-z0-9][-_A-Za-z0-9.:]{1,120}\z/)
    {
      "stage_id" => stage,
      "section_ids" => Array(scope["section_ids"]).map(&:to_s).select { |value| value.match?(/\AS[0-9]{2,}[A-Z]?\z/) }.uniq.sort,
      "artifact_paths" => Array(scope["artifact_paths"]).map(&:to_s).select { |value| repository_path_contract?(value) }.uniq.sort
    }
  end

  def admission_owner_receipt(document)
    authority = document.is_a?(Hash) ? document.dig("launch", "authority") : nil
    authority = {} unless authority.is_a?(Hash)
    value_or_nil = lambda do |value|
      text = value.to_s.strip
      text.empty? ? nil : text[0, 240]
    end
    {
      "assigned_owner" => value_or_nil.call(authority["assigned_owner"]),
      "director_owner" => value_or_nil.call(authority["director_owner"]),
      "promotion_owner" => value_or_nil.call(authority["promotion_owner"]),
      "source" => "dispatch_launch_authority"
    }
  end

  def dispatch_admission_entry(path, run_rel)
    document = hash_document(path)
    version = document["schema_version"].to_s
    classification, reason = if version == CURRENT_DISPATCH_SCHEMA_VERSION
                               ["active_v8", "current_v8_contract"]
                             elsif PINNED_LEGACY_DISPATCH_SCHEMA_VERSIONS.include?(version)
                               ["legacy_pinned", "legacy_v4_hash_pinned_evidence_only"]
                             else
                               ["held_incompatible", "unsupported_dispatch_schema_version"]
                             end
    if document["run"].to_s != run_rel
      classification = "held_incompatible"
      reason = "dispatch_run_mismatch"
    end
    if path.basename.to_s != "#{admission_dispatch_id(document, path)}.yaml"
      classification = "held_incompatible"
      reason = "dispatch_filename_identity_mismatch"
    end
    entry = {
      "dispatch_id" => admission_dispatch_id(document, path),
      "schema_version" => version.empty? ? "unversioned" : version[0, 240],
      "classification" => classification,
      "reason_code" => reason,
      "dispatch_pointer" => pointer(path, "dispatch_admission_source"),
      "scope" => admission_scope(document),
      "owner_receipt" => admission_owner_receipt(document),
      "lifecycle_state" => begin
        state = document.dig("lifecycle", "current_state").to_s
        normalized = state.empty? ? nil : token(state, "unknown")
        normalized&.match?(/\A[A-Za-z0-9][-_A-Za-z0-9.:]{1,120}\z/) ? normalized : nil
      end,
      "active_projection" => classification == "active_v8"
    }
    [entry, document]
  rescue ValidationError
    entry = {
      "dispatch_id" => admission_dispatch_id(nil, path),
      "schema_version" => "unreadable",
      "classification" => "held_incompatible",
      "reason_code" => "unreadable_dispatch_document",
      "dispatch_pointer" => pointer(path, "dispatch_admission_source"),
      "scope" => {"stage_id" => nil, "section_ids" => [], "artifact_paths" => []},
      "owner_receipt" => {
        "assigned_owner" => nil,
        "director_owner" => nil,
        "promotion_owner" => nil,
        "source" => "dispatch_launch_authority"
      },
      "lifecycle_state" => nil,
      "active_projection" => false
    }
    [entry, nil]
  end

  def dispatch_source_set(run_path)
    run_rel = relative_path(run_path)
    documents = {}
    entries = dispatch_paths(run_path).map do |path|
      entry, document = dispatch_admission_entry(path, run_rel)
      documents[relative_path(path)] = document if document
      entry
    end.sort_by { |entry| [entry.dig("dispatch_pointer", "path").to_s, entry["classification"].to_s] }
    entries.group_by { |entry| entry["dispatch_id"].to_s }.each_value do |same_id|
      next unless same_id.length > 1

      same_id.each do |entry|
        entry["classification"] = "held_incompatible"
        entry["reason_code"] = "duplicate_dispatch_id_admission"
        entry["active_projection"] = false
      end
    end
    entries.select { |entry| entry["classification"].to_s == "active_v8" }.combination(2) do |left, right|
      next unless admission_scope_overlap?(left, right)

      owner_ambiguous = %w[assigned_owner director_owner promotion_owner].any? do |owner_key|
        left_owner = left.dig("owner_receipt", owner_key).to_s
        right_owner = right.dig("owner_receipt", owner_key).to_s
        !left_owner.empty? && !right_owner.empty? && left_owner != right_owner
      end
      next unless owner_ambiguous

      [left, right].each do |entry|
        entry["classification"] = "held_incompatible"
        entry["reason_code"] = "dispatch_owner_scope_overlap"
        entry["active_projection"] = false
      end
    end
    digest = digest_value(entries)
    source_set = {
      "status" => admission_holds(entries).empty? ? "current" : "hold",
      "basis" => DISPATCH_SOURCE_SET_BASIS,
      "sha256" => digest,
      "entry_count" => entries.length,
      "entries" => entries
    }
    [source_set, documents]
  end

  def board_manifest_path(run_path)
    path = run_path.join("review", "manifests", "founder-workbench.yaml")
    path.file? ? path : nil
  end

  def reference_index_path(run_path)
    path = run_path.join("research", "reference-working-index.yaml")
    path.file? ? path : nil
  end

  def run_inventory_path(run_path)
    path = run_path.join("work", "harness-run-inventory.yaml")
    path.file? ? path : nil
  end

  def stage_id_for(document)
    document.dig("launch", "task", "exact_scope", "stage_id").to_s
  end

  def section_ids_for(document)
    Array(document.dig("launch", "task", "exact_scope", "section_ids")).map(&:to_s)
  end

  def chunk_ids_for(document)
    []
  end

  def dispatch_state(document)
    document.dig("lifecycle", "current_state").to_s
  end

  def terminal_dispatch_state?(state)
    %w[promoted hold retired replaced].include?(state.to_s)
  end

  def session_state_for(state)
    {
      "prepared" => "prepared",
      "launched" => "active",
      "returned" => "returned",
      "reviewed" => "returned",
      "promoted" => "complete",
      "hold" => "held"
    }.fetch(state.to_s, "prepared")
  end

  def retirement_for(document)
    lineage = ensure_hash!(document["lineage"], "lineage", [])
    state = lineage["lineage_state"].to_s
    case state
    when "replaced"
      {"state" => "replaced", "at" => lifecycle_timestamp(document, "hold") || lifecycle_timestamp(document, "promoted"), "reason_code" => "successor_attempt"}
    when "retired", "completed"
      {"state" => "retired", "at" => lifecycle_timestamp(document, dispatch_state(document)), "reason_code" => "lineage_closed"}
    else
      {"state" => "not_retired", "at" => nil, "reason_code" => nil}
    end
  end

  def attempt_for(document)
    lineage = document["lineage"].is_a?(Hash) ? document["lineage"] : {}
    state = dispatch_state(document)
    {
      "lineage_id" => lineage["lineage_id"].to_s,
      "attempt_id" => lineage["attempt_id"].to_s,
      "attempt_no" => lineage["attempt_number"].to_i,
      "session_id" => lineage["session_id"].to_s,
      "provider" => lineage["provider"].to_s,
      "runtime_surface" => lineage["runtime_surface"].to_s,
      "parent_lineage_id" => lineage["parent_lineage_id"],
      "parent_dispatch_id" => lineage["parent_dispatch_id"],
      "previous_attempt_id" => lineage["previous_attempt_id"],
      "successor_dispatch_id" => lineage["successor_attempt_id"],
      "session_state" => session_state_for(state),
      "retirement" => retirement_for(document)
    }
  end

  def scope_for(document, interaction_surface = nil)
    scope = ensure_hash!(document.dig("launch", "task", "exact_scope"), "launch.task.exact_scope", [])
    mode = scope["mode"].to_s
    {
      "stage_id" => scope["stage_id"].to_s,
      "section_ids" => Array(scope["section_ids"]).map(&:to_s).sort,
      "chunk_ids" => [],
      "artifact_paths" => Array(scope["artifact_paths"]).map(&:to_s).sort,
      "interaction_surface" => interaction_surface || (document.dig("launch", "authority", "director_owner").to_s == "overall_director" ? "founder_visible" : "internal")
    }.tap do |value|
      value["section_ids"] = [] if %w[whole_run artifact].include?(mode)
    end
  end

  def index_scope(stage_id: nil, section_ids: [], scope_kind: "run", chunk_ids: [])
    {
      "scope_kind" => scope_kind,
      "stage_id" => stage_id,
      "section_ids" => Array(section_ids).map(&:to_s).uniq.sort,
      "chunk_ids" => Array(chunk_ids).map(&:to_s).uniq.sort
    }
  end

  def admission_scope_overlap?(left, right)
    left_scope = left.is_a?(Hash) && left["scope"].is_a?(Hash) ? left["scope"] : left
    right_scope = right.is_a?(Hash) && right["scope"].is_a?(Hash) ? right["scope"] : right
    left_scope = {} unless left_scope.is_a?(Hash)
    right_scope = {} unless right_scope.is_a?(Hash)
    left_paths = Array(left_scope["artifact_paths"]).map(&:to_s)
    right_paths = Array(right_scope["artifact_paths"]).map(&:to_s)
    return !(left_paths & right_paths).empty? unless left_paths.empty? || right_paths.empty?

    left_stage = left_scope["stage_id"].to_s
    right_stage = right_scope["stage_id"].to_s
    return true if left_stage.empty? || right_stage.empty?
    return false unless left_stage == right_stage

    left_sections = Array(left_scope["section_ids"]).map(&:to_s)
    right_sections = Array(right_scope["section_ids"]).map(&:to_s)
    left_sections.empty? || right_sections.empty? || !(left_sections & right_sections).empty?
  end

  def admission_hold(entries, reason_code, evidence_entries, scope_entry: nil, dispatch_id: nil)
    evidence = Array(evidence_entries).map { |entry| entry["dispatch_pointer"] }.select { |row| pointer_hash?(row) }
    identity = {
      "reason_code" => reason_code,
      "paths" => evidence.map { |row| row["path"].to_s }.sort
    }
    source = scope_entry || Array(evidence_entries).first || {}
    scope = source["scope"].is_a?(Hash) ? source["scope"] : {}
    owner_receipt = source["owner_receipt"].is_a?(Hash) ? source["owner_receipt"] : {}
    {
      "hold_id" => token("HOLD_ADMISSION_#{Digest::SHA256.hexdigest(canonical_json(identity))[0, 20].upcase}", "HOLD_ADMISSION"),
      "scope" => index_scope(
        stage_id: scope["stage_id"],
        section_ids: scope["section_ids"],
        scope_kind: scope["stage_id"] ? "hold_view" : "run"
      ),
      "dispatch_id" => dispatch_id,
      "reason_code" => reason_code,
      "owner" => owner_receipt["promotion_owner"] || owner_receipt["director_owner"] || "overall_director",
      "evidence_pointers" => evidence.sort_by { |row| row["path"].to_s },
      "next_action_id" => nil,
      "state" => "open"
    }
  end

  def broad_admission_scope_entry(left = nil, right = nil)
    stages = [left, right].compact.map { |entry| entry.dig("scope", "stage_id").to_s }.reject(&:empty?).uniq
    stage_id = stages.length == 1 ? stages.first : nil
    {
      "scope" => {"stage_id" => stage_id, "section_ids" => [], "artifact_paths" => []},
      "owner_receipt" => {}
    }
  end

  def admission_holds(entries)
    rows = Array(entries).select { |entry| entry.is_a?(Hash) }
    holds = rows.select { |entry| entry["classification"].to_s == "held_incompatible" }.map do |entry|
      admission_hold([entry], entry["reason_code"].to_s, [entry], scope_entry: entry, dispatch_id: entry["dispatch_id"])
    end

    legacy = rows.select { |entry| entry["classification"].to_s == "legacy_pinned" }
    active = rows.select { |entry| entry["classification"].to_s == "active_v8" }
    if active.empty? && !legacy.empty?
      holds << admission_hold(
        legacy,
        "legacy_dispatches_have_no_current_v8_projection",
        legacy,
        scope_entry: broad_admission_scope_entry,
        dispatch_id: nil
      )
    end

    rows.group_by { |entry| entry["dispatch_id"].to_s }.each_value do |same_id|
      next unless same_id.length > 1

      holds << admission_hold(same_id, "duplicate_dispatch_id_admission", same_id, scope_entry: broad_admission_scope_entry, dispatch_id: nil)
    end

    rows.combination(2) do |left, right|
      next unless admission_scope_overlap?(left, right)

      classifications_differ = left["classification"].to_s != right["classification"].to_s
      owner_ambiguous = %w[assigned_owner director_owner promotion_owner].any? do |owner_key|
        left_owner = left.dig("owner_receipt", owner_key).to_s
        right_owner = right.dig("owner_receipt", owner_key).to_s
        !left_owner.empty? && !right_owner.empty? && left_owner != right_owner
      end
      next unless classifications_differ || owner_ambiguous

      holds << admission_hold(
        [left, right],
        classifications_differ ? "dispatch_admission_scope_overlap" : "dispatch_owner_scope_overlap",
        [left, right],
        scope_entry: broad_admission_scope_entry(left, right),
        dispatch_id: nil
      )
    end
    holds.uniq { |hold| hold["hold_id"] }.sort_by { |hold| hold["hold_id"] }
  end

  def token(value, fallback)
    text = value.to_s.gsub(/[^A-Za-z0-9_.:-]+/, "_")
    text = fallback if text.empty? || text !~ /\A[A-Za-z0-9]/
    text[0, 120]
  end

  def owner_lock_for(document)
    launch = ensure_hash!(document["launch"], "launch", [])
    {
      "owner" => launch.dig("authority", "assigned_owner").to_s,
      "lock_id" => token("LOCK_#{document["dispatch_id"]}", "LOCK_DISPATCH"),
      "active" => !terminal_dispatch_state?(dispatch_state(document)),
      "exclusive_paths" => Array(launch.dig("task", "exact_scope", "artifact_paths")).map(&:to_s).sort,
      "acquired_at" => launch["prepared_at"].to_s,
      "released_at" => terminal_dispatch_state?(dispatch_state(document)) ? lifecycle_timestamp(document, dispatch_state(document)) : nil
    }
  end

  def pointer_or_nil(value)
    pointer_hash?(value) ? value : nil
  end

  # The Department Dispatch schema allows descriptive `role` prose on a
  # hashed artifact.  The Director Dispatch and Reference Working Index
  # pointer schemas intentionally allow only a compact token, so projection
  # keeps the exact path/hash identity and mechanically normalizes only that
  # transport label.
  def pointer_projection(value, fallback = "pointer")
    return nil unless pointer_hash?(value)

    row = {"path" => value["path"].to_s, "sha256" => value["sha256"].to_s}
    role = token(value["role"], fallback)
    row["role"] = role unless role.to_s.empty?
    row
  end

  def logical_artifact_id(scope, artifact)
    basis = {
      "stage_id" => scope["stage_id"].to_s,
      "section_ids" => Array(scope["section_ids"]).map(&:to_s).uniq.sort,
      "chunk_ids" => Array(scope["chunk_ids"]).map(&:to_s).uniq.sort,
      "canonical_path" => artifact["path"].to_s
    }
    "ARTIFACT_#{Digest::SHA256.hexdigest(canonical_json(basis)).upcase}"
  end

  def canonical_owner_receipt(artifact, promotion, dispatch_pointer)
    logical_owner = artifact.is_a?(Hash) ? artifact["logical_owner"] : nil
    promoter = promotion.is_a?(Hash) ? promotion["promoter"] : nil
    source = logical_owner.is_a?(Hash) ? logical_owner : promoter
    source = {} unless source.is_a?(Hash)
    {
      "owner" => source["owner"].to_s,
      "role" => source["role"].to_s,
      "source" => logical_owner.is_a?(Hash) ? "canonical_artifact.logical_owner" : "promotion.promoter",
      "dispatch_pointer" => dispatch_pointer
    }
  end

  def canonical_head_records_for(document, scope, dispatch_pointer)
    promotion = document["promotion"].is_a?(Hash) ? document["promotion"] : nil
    return [] unless promotion && promotion["decision"].to_s == "promoted"

    Array(promotion["canonical_artifacts"]).each_with_object([]) do |artifact, records|
      pointer_row = pointer_projection(artifact, "canonical_artifact")
      next unless pointer_row

      records << {
        "logical_artifact_id" => logical_artifact_id(scope, pointer_row),
        "logical_identity_basis" => "stage_scope_canonical_path_sha256_v1",
        "artifact" => pointer_row,
        "promotion_epoch" => artifact["decision_epoch"].to_s.empty? ? promotion["decided_at"].to_s : artifact["decision_epoch"].to_s,
        "promotion_epoch_source" => artifact["decision_epoch"].to_s.empty? ? "promotion.decided_at" : "canonical_artifact.decision_epoch",
        "promoted_at" => promotion["decided_at"].to_s,
        "owner_receipt" => canonical_owner_receipt(artifact, promotion, dispatch_pointer)
      }
    end
  end

  def manifest_set_for(document, dispatch_path)
    runtime = document["runtime_return"].is_a?(Hash) ? document["runtime_return"] : {}
    inventory = runtime["output_inventory"].is_a?(Hash) ? runtime["output_inventory"] : {}
    outputs = Array(runtime["outputs"])
    aggregate = inventory["aggregate_manifest"].is_a?(Hash) ? inventory["aggregate_manifest"] : nil
    {
      "input_manifest" => nil,
      "input_count" => Array(document.dig("launch", "sources")).length,
      "result_manifest" => pointer_projection(aggregate, "aggregate_manifest"),
      "result_count" => outputs.length,
      "review_manifest" => nil,
      "review_count" => Array(document.dig("director_review", "reviewed_outputs")).length
    }
  end

  def board_link_candidates(board, board_pointer, dispatch_ids)
    return [] unless board.is_a?(Hash)

    links = []
    walk = lambda do |value, cycle_id = board.dig("board", "active_cycle_id"), card_id = nil|
      case value
      when Hash
        current_cycle = value["cycle_id"].to_s.empty? ? cycle_id : value["cycle_id"].to_s
        current_card = value["card_id"].to_s.empty? ? card_id : value["card_id"].to_s
        if value["dispatch_id"] && dispatch_ids.include?(value["dispatch_id"].to_s)
          links << {
            "dispatch_id" => value["dispatch_id"].to_s,
            "cycle_id" => token(current_cycle, "CYCLE_UNKNOWN"),
            "card_id" => token(current_card, "CARD_#{value["dispatch_id"]}"),
            "decision_receipt" => pointer_projection(value["decision_receipt"], "decision_receipt")
          }
        end
        value.each { |key, child| walk.call(child, current_cycle, key.to_s == "card_id" ? value["card_id"] : current_card) }
      when Array
        value.each { |child| walk.call(child, cycle_id, card_id) }
      end
    end
    walk.call(board)
    links.group_by { |link| [link["dispatch_id"], link["cycle_id"], link["card_id"]] }.values.map(&:first).sort_by { |link| [link["dispatch_id"], link["cycle_id"], link["card_id"]] }.map do |link|
      {
        "board_link_id" => token("BL_#{link["dispatch_id"]}_#{link["card_id"]}", "BLINK"),
        "dispatch_id" => link["dispatch_id"],
        "cycle_id" => link["cycle_id"],
        "card_id" => link["card_id"],
        "board_pointer" => board_pointer,
        "decision_receipt" => link["decision_receipt"],
        "required" => true,
        "state" => "linked"
      }
    end
  end

  def build_dispatch_row(document, dispatch_path, board_links_by_dispatch, stage_order, errors, transport_refresh_path: nil, raw_document: nil)
    dispatch_id = document["dispatch_id"].to_s
    state = dispatch_state(document)
    launch = ensure_hash!(document["launch"], "#{dispatch_id}.launch", errors)
    ensure_hash!(document["lineage"], "#{dispatch_id}.lineage", errors)
    runtime = document["runtime_return"].is_a?(Hash) ? document["runtime_return"] : nil
    review = document["director_review"].is_a?(Hash) ? document["director_review"] : nil
    promotion = document["promotion"].is_a?(Hash) ? document["promotion"] : nil
    digest_document = raw_document || document
    input_digest = digest_document.dig("runtime_return", "input_digest", "sha256") || expected_input_digest(digest_document)
    result_digest = runtime&.dig("result_digest", "sha256")
    scope = scope_for(document)
    pointer = pointer(dispatch_path)
    canonical_rows = promotion ? Array(promotion["canonical_artifacts"]) : []
    canonical_head_records = canonical_head_records_for(document, scope, pointer)
    review_disposition = review ? review["disposition"].to_s : "not_reviewed"
    promotion_state = promotion ? promotion["decision"].to_s : "not_started"
    board_ids = Array(board_links_by_dispatch[dispatch_id]).map { |link| link["board_link_id"] }.sort
    hold_ids = state == "hold" || %w[patch reject hold].include?(review_disposition) ? [token("HOLD_#{dispatch_id}", "HOLD_DISPATCH")] : []
    next_action_ids = []
    unless terminal_dispatch_state?(state)
      next_action_ids << token("NEXT_#{dispatch_id}", "NEXT_DISPATCH")
    end
    next_action_ids << token("NEXT_#{dispatch_id}", "NEXT_DISPATCH") if state == "hold"
    next_action_ids.uniq!

    stage_id = scope["stage_id"]
    errors << "#{dispatch_id} stage_id is not active in the stage registry: #{stage_id}" unless active_stage_id = stage_order.key?(stage_id)
    _ = active_stage_id
    {
      "dispatch_id" => dispatch_id,
      "attempt" => attempt_for(document),
      "task" => {
        "task_id" => launch.dig("task", "task_id").to_s,
        "logical_role" => token(launch.dig("task", "role"), "worker"),
        "dispatcher" => launch.dig("authority", "director_owner").to_s,
        "return_recipient" => launch.dig("recipient", "owner").to_s
      },
      "scope" => scope,
      "owner_lock" => owner_lock_for(document),
      "lifecycle" => {
        "current_state" => state,
        "prepared_at" => lifecycle_timestamp(document, "prepared").to_s,
        "launched_at" => lifecycle_timestamp(document, "launched"),
        "returned_at" => lifecycle_timestamp(document, "returned"),
        "reviewed_at" => lifecycle_timestamp(document, "reviewed"),
        "closed_at" => terminal_dispatch_state?(state) ? lifecycle_timestamp(document, state) : nil
      },
      "dispatch_pointer" => pointer,
      "transport_refresh_receipt" => transport_refresh_path ? pointer(transport_refresh_path, "department_transport_refresh") : nil,
      "input_digest" => input_digest.to_s,
      "result_digest" => result_digest,
      "manifests" => manifest_set_for(document, dispatch_path),
      "review" => {
        "disposition" => review_disposition,
        "reviewer" => review ? review.dig("director", "owner").to_s : launch.dig("authority", "director_owner").to_s,
        "review_pointer" => review ? pointer : nil,
        "board_required" => !board_ids.empty?
      },
      "promotion" => {
        "state" => promotion_state == "promoted" ? "promoted" : (state == "hold" ? "hold" : "not_started"),
        "canonical_head_pointers" => canonical_rows.map { |artifact| pointer_projection(artifact, "canonical_artifact") }.compact,
        "canonical_head_records" => canonical_head_records,
        "promoter" => promotion ? promotion.dig("promoter", "owner") : nil
      },
      "board_link_ids" => board_ids,
      "hold_ids" => hold_ids,
      "next_action_ids" => next_action_ids
    }
  end

  def board_link_map(board_links)
    board_links.group_by { |link| link["dispatch_id"].to_s }
  end

  def derive_matrix(rows, stage_registry_pointer)
    rows.sort_by { |row| [row.dig("scope", "stage_id").to_s, row["dispatch_id"].to_s] }.map do |row|
      state = row.dig("lifecycle", "current_state").to_s
      requirement_id = token("REQ_#{row["dispatch_id"]}", "REQ_DISPATCH")
      {
        "requirement_id" => requirement_id,
        "stage_id" => row.dig("scope", "stage_id").to_s,
        "scope" => row["scope"],
        "required" => true,
        "applicability" => "required",
        "state" => state,
        "dispatch_id" => row["dispatch_id"],
        "dispatch_pointer" => row["dispatch_pointer"],
        "not_applicable_reason" => nil,
        "stale" => false,
        "board_required" => row.dig("review", "board_required") == true,
        "board_link_ids" => row["board_link_ids"]
      }
    end
  end

  def hold_rows(rows, stage_registry_pointer)
    rows.map do |row|
      next if Array(row["hold_ids"]).empty?

      hold_id = row["hold_ids"].first
      {
        "hold_id" => hold_id,
        "scope" => index_scope(stage_id: row.dig("scope", "stage_id"), section_ids: row.dig("scope", "section_ids"), scope_kind: "hold_view"),
        "dispatch_id" => row["dispatch_id"],
        "reason_code" => "dispatch_hold",
        "owner" => row.dig("review", "reviewer").to_s,
        "evidence_pointers" => [row["dispatch_pointer"]],
        "next_action_id" => row["next_action_ids"].first,
        "state" => "open"
      }
    end.compact
  end

  def next_action_rows(rows, holds)
    rows.map do |row|
      next if Array(row["next_action_ids"]).empty?

      action_id = row["next_action_ids"].first
      state = row.dig("lifecycle", "current_state").to_s
      action_scope = index_scope(stage_id: row.dig("scope", "stage_id"), section_ids: row.dig("scope", "section_ids"))
      applicable_holds = Array(holds).select do |hold|
        hold["dispatch_id"].to_s == row["dispatch_id"].to_s || admission_scope_overlap?(action_scope, hold["scope"])
      end
      {
        "next_action_id" => action_id,
        "scope" => action_scope,
        "action_code" => token(state == "hold" ? "resolve_hold" : (state == "returned" ? "director_review" : "advance_dispatch"), "advance_dispatch"),
        "owner" => row.dig("task", "dispatcher").to_s,
        "state" => state == "hold" ? "open" : (applicable_holds.empty? ? "ready" : "deferred"),
        "blocked_by_hold_ids" => applicable_holds.map { |hold| hold["hold_id"] }.uniq.sort,
        "dependency_pointers" => [row["dispatch_pointer"]],
        "successor_dispatch_id" => nil
      }
    end.compact
  end

  def head_candidate(row, record, index)
    receipt = record["owner_receipt"].is_a?(Hash) ? record["owner_receipt"] : {}
    head_identity = {
      "dispatch_id" => row["dispatch_id"].to_s,
      "logical_artifact_id" => record["logical_artifact_id"].to_s,
      "artifact_path" => record.dig("artifact", "path").to_s,
      "ordinal" => index + 1
    }
    head_digest = Digest::SHA256.hexdigest(canonical_json(head_identity)).upcase
    {
      "head_id" => "HEAD_#{head_digest}",
      "logical_artifact_id" => record["logical_artifact_id"].to_s,
      "logical_identity_basis" => record["logical_identity_basis"].to_s,
      "scope" => index_scope(stage_id: row.dig("scope", "stage_id"), section_ids: row.dig("scope", "section_ids")),
      "stage_id" => row.dig("scope", "stage_id").to_s,
      "artifact" => record["artifact"],
      "owner" => receipt["owner"].to_s,
      "owner_kind" => "canonical_stage",
      "owner_receipt" => receipt,
      "promotion_epoch" => record["promotion_epoch"].to_s,
      "promotion_epoch_source" => record["promotion_epoch_source"].to_s,
      "promoted_at" => record["promoted_at"].to_s,
      "source_dispatch_id" => row["dispatch_id"],
      "lineage_id" => row.dig("attempt", "lineage_id"),
      "attempt_id" => row.dig("attempt", "attempt_id"),
      "supersedes_head_id" => nil,
      "superseded_by_head_id" => nil,
      "supersession_state" => "none",
      "state" => "current",
      "revision" => "REV_#{head_digest}",
      "_attempt" => row["attempt"],
      "_dispatch_pointer" => row["dispatch_pointer"]
    }
  end

  def head_scope_signature(head)
    canonical_json(
      "stage_id" => head["stage_id"].to_s,
      "section_ids" => Array(head.dig("scope", "section_ids")).map(&:to_s).uniq.sort,
      "chunk_ids" => Array(head.dig("scope", "chunk_ids")).map(&:to_s).uniq.sort
    )
  end

  def verified_head_successor?(predecessor, successor)
    previous_attempt = predecessor["_attempt"].is_a?(Hash) ? predecessor["_attempt"] : {}
    next_attempt = successor["_attempt"].is_a?(Hash) ? successor["_attempt"] : {}
    return false unless previous_attempt["successor_dispatch_id"].to_s == successor["source_dispatch_id"].to_s
    return false unless next_attempt["previous_attempt_id"].to_s == predecessor["attempt_id"].to_s
    return false unless predecessor["lineage_id"].to_s == successor["lineage_id"].to_s
    return false unless next_attempt["attempt_no"].to_i == previous_attempt["attempt_no"].to_i + 1
    return false unless previous_attempt.dig("retirement", "state").to_s == "replaced"
    return false unless predecessor.dig("owner_receipt", "owner").to_s == successor.dig("owner_receipt", "owner").to_s
    return false unless predecessor.dig("owner_receipt", "role").to_s == successor.dig("owner_receipt", "role").to_s

    true
  end

  def verified_head_chain(group)
    return nil unless group.map { |head| head["source_dispatch_id"].to_s }.uniq.length == group.length

    outgoing = Hash.new { |hash, key| hash[key] = [] }
    incoming = Hash.new { |hash, key| hash[key] = [] }
    group.permutation(2) do |predecessor, successor|
      next unless verified_head_successor?(predecessor, successor)

      outgoing[predecessor["head_id"]] << successor
      incoming[successor["head_id"]] << predecessor
    end
    roots = group.select { |head| incoming[head["head_id"]].empty? }
    terminals = group.select { |head| outgoing[head["head_id"]].empty? }
    return nil unless roots.length == 1 && terminals.length == 1
    return nil unless group.all? { |head| incoming[head["head_id"]].length <= 1 && outgoing[head["head_id"]].length <= 1 }
    return nil unless outgoing.values.sum(&:length) == group.length - 1

    visited = []
    current = roots.first
    while current && !visited.include?(current["head_id"])
      visited << current["head_id"]
      current = outgoing[current["head_id"]].first
    end
    return nil unless visited.length == group.length && terminals.first["head_id"] == visited.last

    {"incoming" => incoming, "outgoing" => outgoing, "terminal" => terminals.first}
  end

  def head_ambiguity_hold(group)
    first = group.first || {}
    identity = {
      "logical_artifact_id" => first["logical_artifact_id"],
      "scope" => first["scope"],
      "dispatch_ids" => group.map { |head| head["source_dispatch_id"].to_s }.sort
    }
    owners = group.map { |head| head["owner"].to_s }.reject(&:empty?).uniq
    {
      "hold_id" => token("HOLD_HEAD_#{Digest::SHA256.hexdigest(canonical_json(identity))[0, 20].upcase}", "HOLD_HEAD"),
      "scope" => first["scope"] || index_scope,
      "dispatch_id" => nil,
      "reason_code" => "canonical_head_ambiguity",
      "owner" => owners.length == 1 ? owners.first : "overall_director",
      "evidence_pointers" => group.map { |head| head["_dispatch_pointer"] }.select { |row| pointer_hash?(row) }.uniq.sort_by { |row| row["path"].to_s },
      "next_action_id" => nil,
      "state" => "open"
    }
  end

  def head_projection(rows)
    candidates = Array(rows).flat_map do |row|
      next [] unless row.dig("promotion", "state").to_s == "promoted"

      Array(row.dig("promotion", "canonical_head_records")).each_with_index.map do |record, index|
        head_candidate(row, record, index)
      end
    end
    holds = []
    candidates.group_by { |head| [head["logical_artifact_id"].to_s, head_scope_signature(head)] }.each_value do |group|
      next if group.length == 1

      chain = verified_head_chain(group)
      if chain
        group.each do |head|
          predecessor = chain["incoming"][head["head_id"]].first
          successor = chain["outgoing"][head["head_id"]].first
          head["supersedes_head_id"] = predecessor && predecessor["head_id"]
          head["superseded_by_head_id"] = successor && successor["head_id"]
          if head["head_id"] == chain["terminal"]["head_id"]
            head["state"] = "current"
            head["supersession_state"] = "verified_successor"
          else
            head["state"] = "stale"
            head["supersession_state"] = "superseded"
          end
        end
      else
        group.each do |head|
          head["state"] = "held"
          head["supersession_state"] = "ambiguous_hold"
        end
        holds << head_ambiguity_hold(group)
      end
    end
    public_heads = candidates.map { |head| head.reject { |key, _value| key.start_with?("_") } }
    [public_heads.sort_by { |head| [head["stage_id"], head["logical_artifact_id"], head["head_id"]] }, holds.sort_by { |hold| hold["hold_id"] }]
  end

  def apply_admission_holds_to_heads(heads, admission_holds)
    Array(heads).map do |head|
      blocked = Array(admission_holds).any? { |hold| admission_scope_overlap?(head["scope"], hold["scope"]) }
      next head unless blocked && head["state"].to_s == "current"

      head.merge("state" => "held", "supersession_state" => "ambiguous_hold")
    end
  end

  def load_optional_requirements(run_path, explicit_path = nil)
    candidates = []
    candidates << resolve_path(explicit_path) if explicit_path
    candidates.concat([
      run_path.join("work", "director-dispatch-requirements.yaml"),
      run_path.join("work", "required-task-matrix.yaml")
    ])
    path = candidates.find(&:file?)
    path ? [path, hash_document(path)] : [nil, nil]
  rescue ValidationError
    raise
  end

  def matrix_from_source(document, fallback_rows, stage_registry_pointer, errors)
    source_rows = document.is_a?(Hash) ? document["rows"] : nil
    return derive_matrix(fallback_rows, stage_registry_pointer) unless source_rows.is_a?(Array)

    source_rows.each_with_index do |row, index|
      next unless row.is_a?(Hash)

      applicability = row["applicability"].to_s
      if applicability == "not_applicable" && row["not_applicable_reason"].to_s.empty?
        errors << "required_task_matrix.rows[#{index}] not_applicable requires an authored reason; builder will not invent one"
      end
    end
    source_rows
  end

  def normalize_board_links(board_links)
    Array(board_links).map do |link|
      link.merge("decision_receipt" => pointer_projection(link["decision_receipt"], "decision_receipt"))
    end
  end

  def parsed_timestamp(value, label, errors)
    return nil if value.nil?

    Time.iso8601(value.to_s)
  rescue ArgumentError
    errors << "#{label} must be an ISO-8601 timestamp"
    nil
  end

  def review_queue_projection(dispatches, errors)
    items = Array(dispatches).map do |_path, document|
      control = document["review_control"].is_a?(Hash) ? document["review_control"] : {}
      review_lease = control["review_lease"].is_a?(Hash) ? control["review_lease"] : {}
      promotion_lease = control["promotion_lease"].is_a?(Hash) ? control["promotion_lease"] : {}
      returned_at = document.dig("runtime_return", "returned_at")
      queue_state = control["queue_state"].to_s
      {
        "dispatch_id" => document["dispatch_id"].to_s,
        "director_owner" => document.dig("launch", "authority", "director_owner").to_s,
        "overall_owner" => document.dig("launch", "authority", "promotion_owner").to_s,
        "dependency_rank" => control.dig("queue_priority", "dependency_rank").to_i,
        "returned_at" => returned_at,
        "queue_state" => queue_state,
        "review_lease_id" => review_lease["lease_id"],
        "review_acquired_at" => review_lease["acquired_at"],
        "review_released_at" => review_lease["released_at"],
        "disposition_recorded_at" => document.dig("director_review", "reviewed_at"),
        "promotion_lease_id" => promotion_lease["lease_id"],
        "promotion_acquired_at" => promotion_lease["acquired_at"],
        "promotion_released_at" => promotion_lease["released_at"],
        "promotion_closed_at" => document.dig("promotion", "decided_at"),
        "blocks_next" => !returned_at.nil? && queue_state != "released"
      }
    end
    items.sort_by! do |item|
      [item["dependency_rank"], item["returned_at"].to_s.empty? ? "9999" : item["returned_at"].to_s, item["dispatch_id"]]
    end

    active_review_items = items.select do |item|
      item["queue_state"] == "in_review" && item["review_acquired_at"] && item["review_released_at"].nil?
    end
    active_review_items.group_by { |item| item["director_owner"] }.each do |director_owner, rows|
      if rows.length > 1
        errors << "recipient Director #{director_owner} has more than one active review lease: #{rows.map { |row| row['dispatch_id'] }.join(', ')}"
      end
    end

    items.group_by { |item| item["director_owner"] }.each do |director_owner, rows|
      eligible = rows.select { |item| !item["returned_at"].nil? }
      eligible.each_with_index do |item, index|
        acquired = parsed_timestamp(item["review_acquired_at"], "review_queue #{item['dispatch_id']} review_acquired_at", errors)
        next unless acquired

        eligible[0...index].each do |prior|
          unless prior["queue_state"] == "released" && prior["promotion_closed_at"]
            errors << "recipient Director #{director_owner} started #{item['dispatch_id']} before earlier return #{prior['dispatch_id']} closed disposition, promotion or hold, and baseline refresh"
            next
          end
          prior_closed = parsed_timestamp(prior["promotion_closed_at"], "review_queue #{prior['dispatch_id']} promotion_closed_at", errors)
          if prior_closed && prior_closed > acquired
            errors << "recipient Director #{director_owner} review order overlaps: #{item['dispatch_id']} starts before #{prior['dispatch_id']} closes"
          end
        end
      end

      intervals = eligible.each_with_object([]) do |item, rows_with_lease|
        acquired = parsed_timestamp(item["review_acquired_at"], "review_queue #{item['dispatch_id']} review_acquired_at", errors)
        next unless acquired

        released = parsed_timestamp(item["review_released_at"], "review_queue #{item['dispatch_id']} review_released_at", errors)
        rows_with_lease << [acquired, released, item]
      end.sort_by(&:first)
      intervals.each_cons(2) do |prior, current|
        if prior[1].nil? || prior[1] > current[0]
          errors << "recipient Director #{director_owner} review leases overlap: #{prior[2]['dispatch_id']} and #{current[2]['dispatch_id']}"
        end
      end
    end

    active_promotion_items = items.select do |item|
      item["queue_state"] == "promotion_in_progress" && item["promotion_acquired_at"] && item["promotion_released_at"].nil?
    end
    if active_promotion_items.length > 1
      errors << "Overall promotion has more than one active global lease: #{active_promotion_items.map { |row| row['dispatch_id'] }.join(', ')}"
    end
    promotion_intervals = items.each_with_object([]) do |item, rows_with_lease|
      acquired = parsed_timestamp(item["promotion_acquired_at"], "review_queue #{item['dispatch_id']} promotion_acquired_at", errors)
      next unless acquired

      released = parsed_timestamp(item["promotion_released_at"], "review_queue #{item['dispatch_id']} promotion_released_at", errors)
      rows_with_lease << [acquired, released, item]
    end.sort_by(&:first)
    promotion_intervals.each_cons(2) do |prior, current|
      if prior[1].nil? || prior[1] > current[0]
        errors << "Overall promotion leases overlap: #{prior[2]['dispatch_id']} and #{current[2]['dispatch_id']}"
      end
    end

    {
      "policy" => "single_flight_per_recipient_director_then_global_overall_promotion",
      "selection_order" => "dependency_rank_then_returned_at_then_dispatch_id",
      "active_review_lease_count" => active_review_items.length,
      "per_director_active_review_limit" => 1,
      "active_promotion_lease_count" => active_promotion_items.length,
      "items" => items
    }
  end

  def build_index(run_path, options = {})
    run_rel = relative_path(run_path)
    errors = []
    stage_path, stage_registry = stage_registry_document
    stage_order = active_stage_order(stage_registry)
    active_ids = active_stage_ids(stage_registry)
    run_inventory = run_inventory_path(run_path)
    board_path = board_manifest_path(run_path)
    reference_path = reference_index_path(run_path)
    admission_source_set, _admission_documents = dispatch_source_set(run_path)
    admission_entries = Array(admission_source_set["entries"])
    admission_hold_rows = admission_holds(admission_entries)
    dispatches = []
    admission_entries.select { |entry| entry["classification"].to_s == "active_v8" }.each do |entry|
      dispatch_path = resolve_path(entry.dig("dispatch_pointer", "path"))
      begin
        effective, raw, refresh_path = effective_dispatch(dispatch_path, errors)
        if refresh_path
          errors.concat(schema_errors_for_document(DISPATCH_SCHEMA, effective, relative_path(dispatch_path)))
        else
          require_schema!(DISPATCH_SCHEMA, dispatch_path, errors)
        end
        errors.concat(dispatch_contract_errors(dispatch_path, refresh_path))
        dispatches << [dispatch_path, effective, raw, refresh_path]
      rescue ValidationError => e
        errors.concat(e.errors)
      end
    end
    errors << "run is not a repository-relative run root: #{run_rel}" unless run_rel.start_with?("runs/", "cf/runs/")
    errors << "run root is missing: #{run_rel}" unless run_path.directory?
    dispatches.each do |dispatch_path, document, raw_document, _refresh_path|
      errors << "#{relative_path(dispatch_path)} run must equal index run #{run_rel}" unless document["run"].to_s == run_rel
      errors << "#{relative_path(dispatch_path)} filename must equal dispatch_id.yaml" unless dispatch_path.basename.to_s == "#{document["dispatch_id"]}.yaml"
      errors << "#{document["dispatch_id"]} lineage attempt_id must equal dispatch_id" unless document.dig("lineage", "attempt_id").to_s == document["dispatch_id"].to_s
      validate_dispatch_bindings(document, dispatch_path, run_rel, errors)
      stage = stage_id_for(document)
      errors << "#{document["dispatch_id"]} stage_id is not active in stage registry: #{stage}" unless active_ids.include?(stage)
      runtime = document["runtime_return"]
      if runtime.is_a?(Hash)
        expected_in = expected_input_digest(raw_document)
        errors << "#{document["dispatch_id"]} input_digest is stale" unless raw_document.dig("runtime_return", "input_digest", "sha256").to_s == expected_in
        expected_out = expected_result_digest(raw_document["runtime_return"])
        errors << "#{document["dispatch_id"]} result_digest is stale" unless raw_document.dig("runtime_return", "result_digest", "sha256").to_s == expected_out
      end
    end
    dispatch_ids = dispatches.map { |_path, document, _raw, _refresh| document["dispatch_id"].to_s }
    if dispatch_ids.uniq.length != dispatch_ids.length
      errors << "department dispatch ids must be unique"
    end

    board = board_path ? hash_document(board_path) : nil
    board_pointer = board_path ? pointer(board_path, "founder_workbench") : nil
    links = normalize_board_links(board_link_candidates(board, board_pointer, dispatch_ids))
    by_dispatch = board_link_map(links)
    rows = dispatches.sort_by { |_path, document, _raw, _refresh| [stage_order.fetch(stage_id_for(document), 1_000_000), document["dispatch_id"].to_s] }.map do |dispatch_path, document, raw_document, refresh_path|
      build_dispatch_row(document, dispatch_path, by_dispatch, stage_order, errors, transport_refresh_path: refresh_path, raw_document: raw_document)
    end
    review_queue = review_queue_projection(dispatches.map { |path, document, _raw, _refresh| [path, document] }, errors)
    requirements_path, requirements = load_optional_requirements(run_path, options[:requirements])
    matrix = matrix_from_source(requirements, rows, stage_pointer(stage_path), errors)
    dispatch_hold_rows = hold_rows(rows, stage_pointer(stage_path))
    heads, head_hold_rows = head_projection(rows)
    heads = apply_admission_holds_to_heads(heads, admission_hold_rows)
    holds = (dispatch_hold_rows + admission_hold_rows + head_hold_rows).uniq { |hold| hold["hold_id"] }.sort_by { |hold| hold["hold_id"] }
    actions = next_action_rows(rows, holds)
    status = rows.any? { |row| row.dig("lifecycle", "current_state").to_s == "hold" } || holds.any? ? "hold" : "current"

    pointers = []
    pointers << pointer(stage_path, "stage_registry")
    pointers << pointer(run_inventory, "run_inventory") if run_inventory
    pointers.concat(admission_entries.map { |entry| entry["dispatch_pointer"] })
    # A board pointer is consumed only when a dispatch row is actually linked
    # to that board.  The reference working index is validated separately; it
    # is deliberately not smuggled into this schema's source set as an
    # unrepresented pointer.
    pointers << pointer(board_path, "founder_workbench") if board_path && !links.empty?
    pointers.concat(rows.flat_map { |row| pointer_pairs(row).map { |path, digest| {"path" => path, "sha256" => digest} } })
    pointers.concat(dispatches.flat_map { |_path, document, _raw, _refresh| pointer_pairs(document).map { |path, digest| {"path" => path, "sha256" => digest} } })
    pointers.concat(matrix.flat_map { |row| pointer_pairs(row).map { |path, digest| {"path" => path, "sha256" => digest} } })
    pointers.concat(links.flat_map { |link| pointer_pairs(link).map { |path, digest| {"path" => path, "sha256" => digest} } })
    source_pairs = unique_sorted_pairs(pointers.map { |row| [row["path"], row["sha256"]] })
    generated_at = options[:generated_at].to_s
    generated_at = timestamp_for(source_pairs.map(&:first).map { |path| resolve_path(path, allow_missing: false) }, fallback: Time.now) if generated_at.empty?
    digest = director_index_source_set_digest(source_pairs, admission_source_set["sha256"])
    stage_pointer_row = pointer(stage_path, "stage_registry")
    index_name = token("DDI_#{run_path.basename.to_s.upcase}", "DDI_RUN_INDEX")
    index = {
      "schema_version" => INDEX_SCHEMA_VERSION,
      "artifact_type" => "director_dispatch_index",
      "index_id" => index_name,
      "run" => run_rel,
      "generated_at" => generated_at,
      "status" => status,
      "scope" => index_scope,
      "stage_registry" => stage_pointer_row,
      "run_inventory" => run_inventory ? pointer(run_inventory, "run_inventory") : nil,
      "dispatch_source_set" => admission_source_set,
      "source_set_digest" => {
        "algorithm" => "sha256",
        "basis" => INDEX_SOURCE_DIGEST_BASIS,
        "sha256" => digest,
        "entry_count" => source_pairs.length,
        "computed_at" => generated_at,
        "verified_before_write" => true
      },
      "source_set_sha256" => digest,
      "authority_boundary" => {
        "derived_read_model" => true,
        "pointer_only" => true,
        "no_creative_authority" => true,
        "canonical_write" => false,
        "founder_approval_inferred" => false,
        "media_bytes_embedded" => false,
        "mechanical_rebuild_only" => true
      },
      "required_task_matrix" => {
        "stage_id" => token(options[:stage_id] || (rows.first && rows.first.dig("scope", "stage_id")), "run"),
        "stage_registry_pointer" => stage_pointer_row,
        "rows" => matrix
      },
      "dispatches" => rows,
      "review_queue" => review_queue,
      "current_heads" => heads,
      "board_links" => links,
      "holds" => holds,
      "next_actions" => actions
    }
    errors.concat(schema_errors_for_document(INDEX_SCHEMA, index, "built director dispatch index"))
    errors.concat(validate_index_document(index, nil, run_path, expected_source_pairs: source_pairs, validate_reference: false))
    errors.concat(validate_reference_index(reference_path)[:errors]) if reference_path && options.fetch(:validate_reference, true)
    raise ValidationError, errors.uniq unless errors.empty?

    [index, source_pairs, {
      "stage_path" => stage_path,
      "run_inventory_path" => run_inventory,
      "board_path" => board_path,
      "reference_path" => reference_path,
      "requirements_path" => requirements_path,
      "dispatch_paths" => dispatches.map(&:first),
      "dispatch_admission_paths" => admission_entries.map { |entry| resolve_path(entry.dig("dispatch_pointer", "path")) },
      "transport_refresh_paths" => dispatches.map { |_path, _document, _raw, refresh| refresh }.compact
    }]
  end

  def stage_pointer(path)
    pointer(path, "stage_registry")
  end

  def validate_index_document(index, index_path = nil, run_path = nil, expected_source_pairs: nil, validate_reference: true)
    errors = []
    if index_path
      require_schema!(INDEX_SCHEMA, index_path, errors)
    end
    unless index.is_a?(Hash)
      errors << "director dispatch index must be an object"
      return errors
    end
    run_rel = index["run"].to_s
    run_path ||= resolve_path(run_rel)
    errors << "index run root is missing: #{run_rel}" unless run_path.directory?
    errors << "legacy #{LEGACY_INDEX_SCHEMA_VERSION} is builder-readable evidence only; current validation requires #{INDEX_SCHEMA_VERSION}" unless index["schema_version"].to_s == INDEX_SCHEMA_VERSION
    expected_dispatch_source_set, _admission_documents = dispatch_source_set(run_path)
    actual_dispatch_source_set = ensure_hash!(index["dispatch_source_set"], "dispatch_source_set", errors)
    unless canonicalize(actual_dispatch_source_set) == canonicalize(expected_dispatch_source_set)
      errors << "dispatch_source_set must classify every run-owned Dispatch path/hash exactly once; silent omission, stale hashes, or classification drift is forbidden"
    end
    expected_admission_holds = admission_holds(Array(expected_dispatch_source_set["entries"]))
    active_admission_paths = Array(expected_dispatch_source_set["entries"]).select do |entry|
      entry["classification"].to_s == "active_v8"
    end.map { |entry| entry.dig("dispatch_pointer", "path").to_s }.sort
    no_embedded_bytes_errors(index, "$", errors)
    source_digest = index["source_set_digest"].is_a?(Hash) ? index["source_set_digest"] : {}
    errors << "source_set_digest alias does not equal source_set_sha256" unless source_digest["sha256"].to_s == index["source_set_sha256"].to_s
    errors << "source_set_digest basis must be #{INDEX_SOURCE_DIGEST_BASIS}" unless source_digest["basis"].to_s == INDEX_SOURCE_DIGEST_BASIS
    source_pairs = unique_sorted_pairs(pointer_pairs(index) + underlying_dispatch_pairs(index, errors))
    recomputed = director_index_source_set_digest(source_pairs, expected_dispatch_source_set["sha256"])
    errors << "source_set_digest SHA-256 is stale" unless source_digest["sha256"].to_s == recomputed
    errors << "source_set_digest entry_count is stale" unless source_digest["entry_count"].to_i == source_pairs.length
    stage_ptr = index["stage_registry"]
    pointer_binding_errors(stage_ptr, "stage_registry", errors)
    stage_registry = begin
      stage_ptr.is_a?(Hash) ? hash_document(resolve_path(stage_ptr["path"])) : {}
    rescue ValidationError
      {}
    end
    active_ids = active_stage_ids(stage_registry)
    dispatch_rows = ensure_array(index["dispatches"], "dispatches", errors)
    projected_dispatch_paths = dispatch_rows.each_with_object([]) do |row, paths|
      paths << row.dig("dispatch_pointer", "path").to_s if row.is_a?(Hash)
    end.sort
    unless (projected_dispatch_paths - active_admission_paths).empty?
      errors << "dispatches contains a path not admitted as active_v8"
    end
    if index.dig("scope", "scope_kind").to_s == "run" && projected_dispatch_paths != active_admission_paths
      errors << "run-scoped index must project every and only active_v8 Dispatch admission"
    end
    dispatch_by_id = {}
    dispatch_documents = []
    source_head_rows = []
    dispatch_rows.each_with_index do |row, index_number|
      label = "dispatches[#{index_number}]"
      unless row.is_a?(Hash)
        errors << "#{label} must be an object"
        next
      end
      id = row["dispatch_id"].to_s
      errors << "#{label} dispatch_id is duplicated" if dispatch_by_id.key?(id)
      dispatch_by_id[id] = row
      path = pointer_binding_errors(row["dispatch_pointer"], "#{label}.dispatch_pointer", errors)
      next unless path&.file?

      begin
        refresh_pointer = row["transport_refresh_receipt"]
        refresh_path = pointer_hash?(refresh_pointer) ? pointer_binding_errors(refresh_pointer, "#{label}.transport_refresh_receipt", errors) : nil
        raw_dispatch = hash_document(path)
        if refresh_path&.file?
          validated = IdolDepartmentTransportRefresh.validate_receipt(refresh_path)
          dispatch = IdolDepartmentTransportRefresh.project_dispatch(raw_dispatch, validated.fetch("receipt"))
          errors.concat(schema_errors_for_document(DISPATCH_SCHEMA, dispatch, relative_path(path)))
        else
          dispatch = raw_dispatch
          require_schema!(DISPATCH_SCHEMA, path, errors)
        end
        errors.concat(dispatch_contract_errors(path, refresh_path))
        dispatch_documents << [path, dispatch]
        validate_dispatch_bindings(dispatch, path, run_rel, errors)
        errors << "#{label} dispatch_id does not exact-copy source" unless dispatch["dispatch_id"].to_s == id
        errors << "#{label} run does not exact-copy index run" unless dispatch["run"].to_s == run_rel
        errors << "#{label} lineage attempt_id does not exact-copy dispatch_id" unless row.dig("attempt", "attempt_id").to_s == dispatch.dig("lineage", "attempt_id").to_s
        errors << "#{label} lineage_id is stale" unless row.dig("attempt", "lineage_id").to_s == dispatch.dig("lineage", "lineage_id").to_s
        errors << "#{label} attempt_no is stale" unless row.dig("attempt", "attempt_no").to_i == dispatch.dig("lineage", "attempt_number").to_i
        errors << "#{label} parent_lineage_id is stale" unless row.dig("attempt", "parent_lineage_id") == dispatch.dig("lineage", "parent_lineage_id")
        errors << "#{label} parent_dispatch_id is stale" unless row.dig("attempt", "parent_dispatch_id") == dispatch.dig("lineage", "parent_dispatch_id")
        errors << "#{label} previous_attempt_id is stale" unless row.dig("attempt", "previous_attempt_id") == dispatch.dig("lineage", "previous_attempt_id")
        errors << "#{label} successor_dispatch_id is stale" unless row.dig("attempt", "successor_dispatch_id") == dispatch.dig("lineage", "successor_attempt_id")
        errors << "#{label} attempt projection is stale" unless canonicalize(row["attempt"]) == canonicalize(attempt_for(dispatch))
        errors << "#{label} lifecycle state is stale" unless row.dig("lifecycle", "current_state").to_s == dispatch_state(dispatch)
        expected_scope = scope_for(dispatch)
        errors << "#{label} scope projection is stale" unless canonicalize(row["scope"]) == canonicalize(expected_scope)
        expected_head_records = canonical_head_records_for(dispatch, expected_scope, pointer(path))
        errors << "#{label} canonical head records are stale" unless canonicalize(row.dig("promotion", "canonical_head_records")) == canonicalize(expected_head_records)
        expected_head_pointers = expected_head_records.map { |record| record["artifact"] }
        errors << "#{label} canonical head pointers are stale" unless canonicalize(row.dig("promotion", "canonical_head_pointers")) == canonicalize(expected_head_pointers)
        expected_promotion_state = if dispatch.dig("promotion", "decision").to_s == "promoted"
                                     "promoted"
                                   elsif dispatch_state(dispatch) == "hold"
                                     "hold"
                                   else
                                     "not_started"
                                   end
        errors << "#{label} promotion state is stale" unless row.dig("promotion", "state").to_s == expected_promotion_state
        errors << "#{label} promoter is stale" unless row.dig("promotion", "promoter") == dispatch.dig("promotion", "promoter", "owner")
        source_head_rows << {
          "dispatch_id" => dispatch["dispatch_id"].to_s,
          "attempt" => attempt_for(dispatch),
          "scope" => expected_scope,
          "dispatch_pointer" => pointer(path),
          "promotion" => {
            "state" => expected_promotion_state,
            "canonical_head_records" => expected_head_records
          }
        }
        runtime = dispatch["runtime_return"]
        expected_in = expected_input_digest(raw_dispatch)
        errors << "#{label} input_digest is stale" unless row["input_digest"].to_s == expected_in
        if runtime.is_a?(Hash)
          raw_runtime = raw_dispatch["runtime_return"]
          errors << "#{label} result_digest is stale" unless row["result_digest"].to_s == raw_runtime.dig("result_digest", "sha256").to_s
          errors << "#{label} result digest source is stale" unless raw_runtime.dig("result_digest", "sha256").to_s == expected_result_digest(raw_runtime)
          aggregate = runtime.dig("output_inventory", "aggregate_manifest")
          row_manifest = row.dig("manifests", "result_manifest")
          if aggregate.nil?
            errors << "#{label} result_manifest must be null when dispatch has no aggregate manifest" unless row_manifest.nil?
          elsif row_manifest != pointer_projection(aggregate, "aggregate_manifest")
            errors << "#{label} result_manifest must exact-copy dispatch aggregate manifest"
          end
        end
        stage = row.dig("scope", "stage_id").to_s
        errors << "#{label} stage_id is not active in stage registry: #{stage}" unless active_ids.include?(stage)
      rescue ValidationError => e
        errors.concat(e.errors)
      rescue IdolDepartmentTransportRefresh::ValidationError => e
        errors.concat(e.errors)
      end
    end
    expected_review_queue = review_queue_projection(dispatch_documents, errors)
    unless canonicalize(index["review_queue"]) == canonicalize(expected_review_queue)
      errors << "review_queue must exact-project each dispatch queue, review lease, disposition, promotion lease, and closure state"
    end
    expected_heads, expected_head_holds = head_projection(source_head_rows)
    expected_heads = apply_admission_holds_to_heads(expected_heads, expected_admission_holds)
    unless canonicalize(index["current_heads"]) == canonicalize(expected_heads)
      errors << "current_heads must exact-project one current canonical head per logical artifact/scope and only verified supersession chains"
    end
    Array(index["current_heads"]).select { |head| head.is_a?(Hash) && head["state"].to_s == "current" }.group_by do |head|
      [head["logical_artifact_id"].to_s, head_scope_signature(head)]
    end.each_value do |heads|
      errors << "logical artifact/scope has more than one current canonical head" if heads.length > 1
    end
    ids = dispatch_rows.map { |row| row.is_a?(Hash) ? row["dispatch_id"].to_s : nil }.compact
    board_ids = ensure_array(index["board_links"], "board_links", errors).map { |link| link.is_a?(Hash) ? link["board_link_id"].to_s : nil }.compact
    hold_ids = ensure_array(index["holds"], "holds", errors).map { |hold| hold.is_a?(Hash) ? hold["hold_id"].to_s : nil }.compact
    expected_special_holds = (expected_admission_holds + expected_head_holds).sort_by { |hold| hold["hold_id"] }
    actual_special_holds = Array(index["holds"]).select do |hold|
      hold.is_a?(Hash) && (hold["hold_id"].to_s.start_with?("HOLD_ADMISSION_") || hold["hold_id"].to_s.start_with?("HOLD_HEAD_"))
    end.sort_by { |hold| hold["hold_id"] }
    unless canonicalize(actual_special_holds) == canonicalize(expected_special_holds)
      errors << "admission and canonical-head ambiguity holds must exact-project their bound evidence"
    end
    has_open_hold = Array(index["holds"]).any? { |hold| hold.is_a?(Hash) && hold["state"].to_s == "open" } ||
                    dispatch_rows.any? { |row| row.is_a?(Hash) && row.dig("lifecycle", "current_state").to_s == "hold" }
    expected_index_status = has_open_hold ? "hold" : "current"
    errors << "index status must fail closed over every open HOLD" unless index["status"].to_s == expected_index_status
    next_actions = ensure_array(index["next_actions"], "next_actions", errors)
    next_actions.each_with_index do |action, index_number|
      next unless action.is_a?(Hash)

      required_blockers = expected_special_holds.select do |hold|
        admission_scope_overlap?(action["scope"], hold["scope"])
      end.map { |hold| hold["hold_id"] }.uniq.sort
      next if required_blockers.empty?

      actual_blockers = Array(action["blocked_by_hold_ids"]).map(&:to_s).uniq.sort
      errors << "next_actions[#{index_number}] omits admission or canonical-head HOLD blockers" unless (required_blockers - actual_blockers).empty?
      if action["action_code"].to_s != "resolve_hold" && action["state"].to_s != "deferred"
        errors << "next_actions[#{index_number}] cannot advance while admission or canonical-head HOLD is open"
      end
    end
    action_ids = next_actions.map { |action| action.is_a?(Hash) ? action["next_action_id"].to_s : nil }.compact
    dispatch_rows.each_with_index do |row, index_number|
      next unless row.is_a?(Hash)

      Array(row["board_link_ids"]).each { |id| errors << "dispatches[#{index_number}] references missing board link #{id}" unless board_ids.include?(id.to_s) }
      Array(row["hold_ids"]).each { |id| errors << "dispatches[#{index_number}] references missing hold #{id}" unless hold_ids.include?(id.to_s) }
      Array(row["next_action_ids"]).each { |id| errors << "dispatches[#{index_number}] references missing next action #{id}" unless action_ids.include?(id.to_s) }
    end
    matrix = ensure_hash!(index["required_task_matrix"], "required_task_matrix", errors)
    pointer_binding_errors(matrix["stage_registry_pointer"], "required_task_matrix.stage_registry_pointer", errors)
    ensure_array(matrix["rows"], "required_task_matrix.rows", errors).each_with_index do |row, index_number|
      next unless row.is_a?(Hash)

      stage = row["stage_id"].to_s
      errors << "required_task_matrix.rows[#{index_number}] stage_id is not active" unless active_ids.include?(stage)
      dispatch_id = row["dispatch_id"].to_s
      if row["state"].to_s == "not_applicable" && row["not_applicable_reason"].to_s.empty?
        errors << "required_task_matrix.rows[#{index_number}] not_applicable reason is missing; validator will not author one"
      end
      if dispatch_id.empty? && !%w[missing not_applicable].include?(row["state"].to_s)
        errors << "required_task_matrix.rows[#{index_number}] non-missing state must bind dispatch_id"
      elsif !dispatch_id.empty?
        errors << "required_task_matrix.rows[#{index_number}] references unknown dispatch #{dispatch_id}" unless ids.include?(dispatch_id)
      end
    end
    expected_source_pairs ||= source_pairs
    errors << "source set does not match expected sorted pointers" unless unique_sorted_pairs(expected_source_pairs) == source_pairs
    if validate_reference && run_path
      reference_path = reference_index_path(run_path)
      errors.concat(validate_reference_index(reference_path)[:errors]) if reference_path
    end
    errors
  end

  def validate_reference_index(path)
    errors = []
    return {errors: []} if path.nil?

    path = resolve_path(path)
    require_schema!(REFERENCE_SCHEMA, path, errors)
    begin
      document = hash_document(path)
    rescue ValidationError => e
      return {errors: errors + e.errors}
    end
    no_embedded_bytes_errors(document, "$", errors)
    source_digest = document["source_set_digest"].is_a?(Hash) ? document["source_set_digest"] : {}
    errors << "reference source_set_digest alias does not equal source_set_sha256" unless source_digest["sha256"].to_s == document["source_set_sha256"].to_s
    pairs = unique_sorted_pairs(pointer_pairs(document))
    errors << "reference source_set_digest SHA-256 is stale" unless source_digest["sha256"].to_s == source_set_digest(pairs)
    errors << "reference source_set_digest entry_count is stale" unless source_digest["entry_count"].to_i == pairs.length
    dispatch_by_attempt = {}
    Array(document["worker_deltas"]).each_with_index do |delta, index_number|
      next unless delta.is_a?(Hash)

      delta_path = pointer_binding_errors(delta, "worker_deltas[#{index_number}]", errors)
      next unless delta_path&.file?

      next unless delta["state"].to_s == "accepted"

      begin
        delta_document = load_document(delta_path)
        if delta_document.is_a?(Hash)
          errors << "worker_deltas[#{index_number}] dispatch_id does not exact-copy delta" if delta_document.key?("dispatch_id") && delta_document["dispatch_id"].to_s != delta["dispatch_id"].to_s
          errors << "worker_deltas[#{index_number}] attempt_id does not exact-copy delta" if delta_document.key?("attempt_id") && delta_document["attempt_id"].to_s != delta["attempt_id"].to_s
        end
      rescue ValidationError => e
        errors.concat(e.errors)
      end
      dispatch_by_attempt[[delta["dispatch_id"].to_s, delta["attempt_id"].to_s]] = delta
    end
    Array(document["rows"]).each_with_index do |row, index_number|
      next unless row.is_a?(Hash)

      worker = row["worker_attempt"].is_a?(Hash) ? row["worker_attempt"] : {}
      dispatch_key = [worker["dispatch_id"].to_s, worker["attempt_id"].to_s]
      if row.dig("cdd_review", "disposition").to_s == "accepted"
        delta = dispatch_by_attempt[dispatch_key]
        errors << "rows[#{index_number}] accepted CDD review must bind an accepted worker delta" if delta.nil?
      end
      dispatch_pointer_errors = []
      dispatch_pointer_errors.concat(pointer_binding_errors(worker["dispatch_pointer"], "rows[#{index_number}].worker_attempt.dispatch_pointer", dispatch_pointer_errors) ? [] : [])
      errors.concat(dispatch_pointer_errors)
      if pointer_hash?(worker["dispatch_pointer"])
        begin
          dispatch = hash_document(resolve_path(worker["dispatch_pointer"]["path"]))
          errors << "rows[#{index_number}] worker dispatch id is stale" unless dispatch["dispatch_id"].to_s == worker["dispatch_id"].to_s
          errors << "rows[#{index_number}] worker attempt id is stale" unless dispatch.dig("lineage", "attempt_id").to_s == worker["attempt_id"].to_s
        rescue ValidationError => e
          errors.concat(e.errors)
        end
      end
    end
    {errors: errors.uniq}
  end

  def atomic_write(path, text, expected_existing_sha: nil)
    path = resolve_path(path, allow_missing: true)
    path.dirname.mkpath
    if expected_existing_sha && path.file?
      actual = sha256(path)
      raise ValidationError, ["compare-and-swap failed: destination changed before write"] unless actual == expected_existing_sha
    elsif expected_existing_sha && !path.exist?
      raise ValidationError, ["compare-and-swap failed: destination disappeared before write"]
    end
    temp = path.dirname.join(".#{path.basename}.tmp-#{Process.pid}-#{SecureRandom.hex(5)}")
    begin
      File.open(temp.to_s, "wb") do |file|
        file.write(text)
        file.flush
        file.fsync
      end
      File.rename(temp.to_s, path.to_s)
    ensure
      temp.delete if temp.exist?
    end
    path
  end

  def source_snapshot(pairs)
    Array(pairs).map do |path, _digest|
      resolved = resolve_path(path)
      stat = resolved.stat
      {"path" => path, "size" => stat.size, "mtime_nsec" => stat.mtime.nsec, "sha256" => sha256(resolved)}
    end.sort_by { |row| row["path"] }
  end

  def source_snapshot_changed?(before, after)
    before != after
  end

  def yaml_text(document)
    YAML.dump(document)
  end

  def write_index(run_path, options = {})
    attempts = 0
    begin
      existing_path = options[:output] ? resolve_path(options[:output], allow_missing: true) : run_path.join("work", "director-dispatch-index.yaml")
      existing_sha = existing_path.file? ? sha256(existing_path) : nil
      existing = existing_path.file? ? hash_document(existing_path) : nil
      expected_source = options[:if_source_set].to_s
      if !expected_source.empty? && existing && existing["source_set_sha256"].to_s != expected_source
        raise ValidationError, ["compare-and-swap failed: existing source_set_sha256 does not match --if-source-set"]
      end
      index, source_pairs, metadata = build_index(run_path, options)
      before = source_snapshot(source_pairs)
      # Build may be instrumented in tests or run concurrently with a worker;
      # re-read every pointer/hash pair immediately before replacement.
      after = source_snapshot(source_pairs)
      if source_snapshot_changed?(before, after)
        raise ValidationError, ["source set changed during build; retrying"]
      end
      current_digest = director_index_source_set_digest(
        after.map { |row| [row["path"], row["sha256"]] },
        index.dig("dispatch_source_set", "sha256")
      )
      raise ValidationError, ["source-set recheck failed before write"] unless current_digest == index["source_set_sha256"].to_s
      text = yaml_text(index)
      output = atomic_write(existing_path, text, expected_existing_sha: existing_sha)
      views = []
      view_specs = Array(options[:views])
      view_specs.each do |spec|
        view = scoped_view(index, spec)
        view_path = run_path.join("work", "director-dispatch-views", "#{view_slug(spec)}.yaml")
        view_existing_sha = view_path.file? ? sha256(view_path) : nil
        view_source_pairs = unique_sorted_pairs(pointer_pairs(view) + underlying_dispatch_pairs(view, []))
        view["source_set_digest"]["sha256"] = director_index_source_set_digest(
          view_source_pairs,
          view.dig("dispatch_source_set", "sha256")
        )
        view["source_set_digest"]["entry_count"] = view_source_pairs.length
        view["source_set_sha256"] = view["source_set_digest"]["sha256"]
        view_text = yaml_text(view)
        atomic_write(view_path, view_text, expected_existing_sha: view_existing_sha)
        views << relative_path(view_path)
      end
      [output, views, index]
    rescue ValidationError => e
      attempts += 1
      if e.errors.any? { |message| message.include?("source set changed during build") } && attempts <= options.fetch(:retries, 2).to_i
        retry
      end
      raise
    end
  end

  def view_slug(spec)
    token("#{spec.to_s.gsub(/[^A-Za-z0-9_-]+/, "_")}", "run")
  end

  def scoped_view(index, spec)
    text = spec.to_s
    kind, value = text.split(":", 2)
    kind = "run" if kind.to_s.empty?
    value = nil if value.to_s.empty?
    view = Marshal.load(Marshal.dump(index))
    dispatches = Array(index["dispatches"])
    selected_ids = case kind
                   when "stage"
                     dispatches.select { |row| row.dig("scope", "stage_id").to_s == value.to_s }.map { |row| row["dispatch_id"] }
                   when "section"
                     dispatches.select { |row| Array(row.dig("scope", "section_ids")).include?(value.to_s) }.map { |row| row["dispatch_id"] }
                   when "hold", "hold_view"
                     dispatches.select { |row| !Array(row["hold_ids"]).empty? }.map { |row| row["dispatch_id"] }
                   when "founder_cycle"
                     links = Array(index["board_links"]).select { |link| link["cycle_id"].to_s == value.to_s }
                     links.map { |link| link["dispatch_id"] }
                   else
                     dispatches.map { |row| row["dispatch_id"] }
                   end
    selected = selected_ids.map(&:to_s)
    unless kind == "run"
      view["dispatches"] = dispatches.select { |row| selected.include?(row["dispatch_id"].to_s) }
      queue_items = Array(index.dig("review_queue", "items")).select { |item| selected.include?(item["dispatch_id"].to_s) }
      view["review_queue"]["items"] = queue_items
      view["review_queue"]["active_review_lease_count"] = queue_items.count do |item|
        item["queue_state"].to_s == "in_review" && !item["review_acquired_at"].nil? && item["review_released_at"].nil?
      end
      view["review_queue"]["active_promotion_lease_count"] = queue_items.count do |item|
        item["queue_state"].to_s == "promotion_in_progress" && !item["promotion_acquired_at"].nil? && item["promotion_released_at"].nil?
      end
      view["required_task_matrix"]["rows"] = Array(index.dig("required_task_matrix", "rows")).select { |row| selected.include?(row["dispatch_id"].to_s) }
      view["board_links"] = Array(index["board_links"]).select { |link| selected.include?(link["dispatch_id"].to_s) }
      admission_hold_rows = admission_holds(Array(view.dig("dispatch_source_set", "entries")))
      heads, head_hold_rows = head_projection(view["dispatches"])
      view["current_heads"] = apply_admission_holds_to_heads(heads, admission_hold_rows)
      dispatch_hold_rows = hold_rows(view["dispatches"], view.dig("required_task_matrix", "stage_registry_pointer"))
      view["holds"] = (dispatch_hold_rows + admission_hold_rows + head_hold_rows).uniq { |hold| hold["hold_id"] }.sort_by { |hold| hold["hold_id"] }
      view["next_actions"] = next_action_rows(view["dispatches"], view["holds"])
      view["status"] = view["holds"].empty? ? "current" : "hold"
    end
    stage_id = kind == "stage" ? value : nil
    section_ids = kind == "section" ? [value] : []
    view["scope"] = index_scope(stage_id: stage_id, section_ids: section_ids, scope_kind: %w[section stage hold_view founder_cycle].include?(kind) ? kind : "run", chunk_ids: [])
    view["index_id"] = token("#{index["index_id"]}_#{view_slug(spec).upcase}", "DDI_VIEW")
    view
  end

  # Internal pointer summary used only while assembling the typed CDD successor
  # Boot Pack v3. It is deliberately not a public artifact contract.
  def boot_pack_projection(index, index_path = nil, options = {})
    run_path = resolve_path(index["run"])
    stage_path = resolve_path(index.dig("stage_registry", "path"))
    stage_registry = hash_document(stage_path)
    order = active_stage_order(stage_registry)
    dispatch_rows = Array(index["dispatches"])
    open_rows = dispatch_rows.select { |row| !%w[promoted hold retired replaced].include?(row.dig("lifecycle", "current_state").to_s) || row.dig("lifecycle", "current_state").to_s == "hold" }
    if options[:stage]
      open_rows = open_rows.select { |row| row.dig("scope", "stage_id").to_s == options[:stage].to_s }
    end
    if options[:section]
      open_rows = open_rows.select { |row| Array(row.dig("scope", "section_ids")).include?(options[:section].to_s) }
    end
    current_stage = options[:stage].to_s
    if current_stage.empty?
      current_stage = open_rows.map { |row| row.dig("scope", "stage_id").to_s }.max_by { |stage| order.fetch(stage, -1) }.to_s
      current_stage = nil if current_stage.empty?
    end
    launch_contexts = open_rows.map do |row|
      pointer = row["dispatch_pointer"]
      next unless pointer_hash?(pointer)

      begin
        hash_document(resolve_path(pointer["path"]))
      rescue ValidationError
        nil
      end
    end.compact
    epoch = launch_contexts.map { |doc| doc.dig("launch", "founder_context", "decision_epoch").to_s }.reject(&:empty?).sort.last
    locks = launch_contexts.flat_map { |doc| Array(doc.dig("launch", "founder_context", "locks")) }.uniq { |lock| canonical_json(lock) }.sort_by { |lock| lock["lock_id"].to_s }
    tasks = open_rows.sort_by { |row| [row.dig("scope", "stage_id").to_s, row["dispatch_id"].to_s] }.map do |row|
      {
        "dispatch_id" => row["dispatch_id"],
        "task_id" => row.dig("task", "task_id"),
        "stage_id" => row.dig("scope", "stage_id"),
        "section_ids" => row.dig("scope", "section_ids"),
        "state" => row.dig("lifecycle", "current_state"),
        "owner" => row.dig("owner_lock", "owner"),
        "lineage_id" => row.dig("attempt", "lineage_id"),
        "attempt_id" => row.dig("attempt", "attempt_id"),
        "dispatch_pointer" => row["dispatch_pointer"]
      }
    end
    board_links = Array(index["board_links"])
    cycle_ids = board_links.map { |link| link["cycle_id"].to_s }.reject(&:empty?).uniq.sort
    active_cycle = if cycle_ids.empty?
                     nil
                   else
                     cycle_id = cycle_ids.last
                     {
                       "cycle_id" => cycle_id,
                       "board_pointers" => board_links.select { |link| link["cycle_id"].to_s == cycle_id }.map { |link| link["board_pointer"] }.uniq,
                       "dispatch_ids" => board_links.select { |link| link["cycle_id"].to_s == cycle_id }.map { |link| link["dispatch_id"] }.uniq.sort
                     }
                   end
    next_actions = Array(index["next_actions"]).select do |action|
      options[:stage].nil? || action.dig("scope", "stage_id").to_s == options[:stage].to_s
    end
    checkpoints = tasks.map do |task|
      row = dispatch_rows.find { |candidate| candidate["dispatch_id"].to_s == task["dispatch_id"].to_s }
      {
        "dispatch_id" => task["dispatch_id"],
        "lineage_id" => task["lineage_id"],
        "attempt_id" => task["attempt_id"],
        "session_id" => row.dig("attempt", "session_id"),
        "input_digest" => row["input_digest"],
        "result_digest" => row["result_digest"],
        "dispatch_pointer" => row["dispatch_pointer"]
      }
    end
    {
      "projection_version" => "idol-director-boot-pack-pointer-summary.v1",
      "projection_type" => "director_boot_pack_pointer_summary",
      "run" => relative_path(run_path),
      "scope" => index["scope"],
      "current_stage" => current_stage,
      "decision_epoch" => epoch.to_s.empty? ? nil : epoch,
      "active_founder_locks" => locks,
      "open_or_held_tasks" => tasks,
      "review_queue" => index["review_queue"],
      "current_canonical_heads" => Array(index["current_heads"]).select { |head| head["state"].to_s == "current" },
      "active_board_cycle" => active_cycle,
      "next_actions" => next_actions,
      "exact_lineage_checkpoint" => checkpoints
    }
  end

  def exact_request_keys!(value, required, label)
    unless value.is_a?(Hash)
      raise ValidationError, ["#{label} must be an object"]
    end

    expected = Array(required).map(&:to_s).sort
    actual = value.keys.map(&:to_s).sort
    missing = expected - actual
    unknown = actual - expected
    errors = []
    errors << "#{label} is missing fields: #{missing.join(', ')}" unless missing.empty?
    errors << "#{label} contains unsupported fields: #{unknown.join(', ')}" unless unknown.empty?
    raise ValidationError, errors unless errors.empty?

    value
  end

  def cdd_successor_profile_reads(errors)
    registry_path = ROOT.join("automation", "harness-skill-load-profiles.yaml")
    registry = hash_document(registry_path)
    profile = Array(registry["profiles"]).find do |row|
      row.is_a?(Hash) && row["profile_id"].to_s == "creative_development_director"
    end
    unless profile
      errors << "creative_development_director profile is missing"
      return [pointer(registry_path, "skill_load_profile_registry"), []]
    end
    checkpoint = Array(profile.dig("phase_load", "checkpoints")).find do |row|
      row.is_a?(Hash) && row["checkpoint_id"].to_s == "cdd_startup"
    end
    unless checkpoint
      errors << "creative_development_director cdd_startup checkpoint is missing"
      return [pointer(registry_path, "skill_load_profile_registry"), []]
    end

    skill_by_id = Array(registry["skill_bindings"]).each_with_object({}) do |row, result|
      result[row["binding_id"].to_s] = row if row.is_a?(Hash)
    end
    read_by_id = Array(registry["read_bindings"]).each_with_object({}) do |row, result|
      result[row["binding_id"].to_s] = row if row.is_a?(Hash)
    end
    rows = []
    [["skill", checkpoint["required_skill_ids"], skill_by_id], ["linked_read", checkpoint["required_read_ids"], read_by_id]].each do |kind, ids, registry_rows|
      Array(ids).each do |binding_id|
        row = registry_rows[binding_id.to_s]
        if row.nil?
          errors << "cdd_startup references missing #{kind} binding #{binding_id}"
          next
        end
        path_text = row["path"].to_s
        begin
          path = resolve_path(path_text)
          current_sha = sha256(path)
          errors << "cdd_startup #{kind} binding is stale: #{path_text}" unless current_sha == row["sha256"].to_s
        rescue ValidationError => e
          errors.concat(e.errors)
        end
        errors << "cdd_startup #{kind} binding must require EOF: #{path_text}" unless row["eof_required"] == true
        rows << {
          "binding_id" => binding_id.to_s,
          "kind" => kind,
          "path" => path_text,
          "revision" => row["revision"].to_s.empty? ? "content-addressed" : row["revision"].to_s,
          "sha256" => row["sha256"].to_s,
          "eof_required" => true
        }
      end
    end
    [pointer(registry_path, "skill_load_profile_registry"), rows]
  end

  def cdd_successor_report_pointers(index, errors)
    rows_by_id = Array(index["dispatches"]).each_with_object({}) do |row, result|
      result[row["dispatch_id"].to_s] = row if row.is_a?(Hash)
    end
    reports = Array(index["current_heads"]).each_with_object([]) do |head, result|
      next unless head["state"].to_s == "current"

      row = rows_by_id[head["source_dispatch_id"].to_s]
      next unless row

      begin
        dispatch = hash_document(resolve_path(row.dig("dispatch_pointer", "path")))
        next unless dispatch.dig("launch", "bounded_output", "output_kind").to_s == "director_development_report"

        artifact = head["artifact"]
        pointer_binding_errors(artifact, "director development report", errors)
        result << artifact
      rescue ValidationError => e
        errors.concat(e.errors)
      end
    end
    reports.uniq { |row| [row["path"].to_s, row["sha256"].to_s] }.sort_by { |row| [row["path"].to_s, row["sha256"].to_s] }
  end

  def cdd_successor_prepare(params)
    exact_request_keys!(
      params,
      %w[action run_root shared_checkpoint_path shared_checkpoint_sha256 source_session_id successor_session_id runtime_state],
      "CDD successor prepare request"
    )
    errors = []
    run_text = params["run_root"].to_s
    unless run_text.match?(%r{\Aruns/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9\uac00-\ud7a3][a-z0-9\uac00-\ud7a3-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}\z})
      errors << "run_root is not a canonical IDOL Workbench run"
    end
    run_path = resolve_path(run_text)
    checkpoint_path = resolve_path(params["shared_checkpoint_path"])
    expected_checkpoint_path = run_path.join("work", "front_planning_integration", "shared-context", "current.json")
    errors << "shared checkpoint must use the current Workbench checkpoint path" unless checkpoint_path == expected_checkpoint_path
    checkpoint_sha = params["shared_checkpoint_sha256"].to_s
    errors << "shared checkpoint SHA-256 is invalid" unless checkpoint_sha.match?(/\A[a-f0-9]{64}\z/)
    errors << "shared checkpoint SHA-256 is stale" unless checkpoint_path.file? && sha256(checkpoint_path) == checkpoint_sha
    checkpoint = hash_document(checkpoint_path)
    errors.concat(schema_errors(ROOT.join("development", "front-planning-workbench", "contracts", "shared-context-checkpoint.schema.json"), checkpoint_path))
    errors << "shared checkpoint run does not match run_root" unless checkpoint["run_root"].to_s == run_text
    errors << "shared checkpoint still has pending reconciliation" if checkpoint.dig("planning_state", "pending_reconciliation_dirty") == true
    immutable_checkpoint_path = run_path.join(
      "work",
      "front_planning_integration",
      "shared-context",
      "checkpoints",
      "checkpoint-#{checkpoint["checkpoint_id"]}.json"
    )
    errors << "immutable source checkpoint is missing" unless immutable_checkpoint_path.file?
    if immutable_checkpoint_path.file?
      errors << "immutable source checkpoint does not match current checkpoint bytes" unless sha256(immutable_checkpoint_path) == checkpoint_sha
      errors.concat(schema_errors(ROOT.join("development", "front-planning-workbench", "contracts", "shared-context-checkpoint.schema.json"), immutable_checkpoint_path))
    end

    plan_pointer = checkpoint["plan"]
    canvas_pointer = {
      "path" => checkpoint.dig("canvas", "path"),
      "sha256" => checkpoint.dig("canvas", "file_sha256")
    }
    plan_path = pointer_binding_errors(plan_pointer, "shared checkpoint plan", errors)
    plan = plan_path&.file? ? hash_document(plan_path) : {}
    errors << "CDD successor v3 source plan must carry storyline_lineage" unless plan["storyline_lineage"].is_a?(Hash)
    errors << "CDD successor v3 source plan must carry screen_progression_map" unless plan["screen_progression_map"].is_a?(Hash)
    canvas_path = pointer_binding_errors(canvas_pointer, "shared checkpoint canvas", errors)
    canvas = canvas_path&.file? ? hash_document(canvas_path) : {}
    if canvas_path&.file?
      errors.concat(schema_errors(ROOT.join("development", "front-planning-workbench", "contracts", "canvas-state.schema.json"), canvas_path))
    end

    source_session_id = params["source_session_id"].to_s
    successor_session_id = params["successor_session_id"].to_s
    errors << "source and successor CDD session IDs must differ" if source_session_id.empty? || source_session_id == successor_session_id
    errors << "successor CDD session ID is missing" if successor_session_id.empty?
    cdd_links = Array(canvas["session_links"]).select do |row|
      row.is_a?(Hash) && row["session_key"].to_s == CDD_SESSION_KEY
    end
    errors << "canonical canvas must contain exactly one active CDD session link" unless cdd_links.length == 1
    cdd_link = cdd_links.first || {}
    errors << "source CDD session does not match the hash-bound canonical canvas" unless cdd_link["native_session_id"].to_s == source_session_id
    errors << "source CDD session is not at an idle attached checkpoint" unless cdd_link["status"].to_s == "attached_structured"
    logical_lineage_id = cdd_link["lineage_id"].to_s
    source_attempt_id = cdd_link["attempt_id"].to_s
    errors << "source CDD logical lineage is missing" if logical_lineage_id.empty?
    errors << "source CDD attempt checkpoint is missing" if source_attempt_id.empty?

    runtime_state = params["runtime_state"]
    exact_request_keys!(
      runtime_state,
      %w[active_turn_count canonical_writer_idle founder_gate_open save_conflict startup_phase explicit_founder_confirmation],
      "CDD successor runtime_state"
    )
    errors << "CDD successor requires zero active model turns" unless runtime_state["active_turn_count"] == 0
    errors << "canonical Workbench writer must be idle" unless runtime_state["canonical_writer_idle"] == true
    errors << "open Founder gate or unrecorded intervention blocks CDD rollover" unless runtime_state["founder_gate_open"] == false
    errors << "Workbench save conflict blocks CDD rollover" unless runtime_state["save_conflict"] == false
    errors << "Startup Admission must be ready before CDD rollover" unless runtime_state["startup_phase"].to_s == "ready"
    errors << "CDD rollover requires explicit current-action Founder confirmation" unless runtime_state["explicit_founder_confirmation"] == true

    index_path = run_path.join("work", "director-dispatch-index.yaml")
    unless index_path.file?
      errors << "Director Dispatch Index is missing; rebuild #{INDEX_SCHEMA_VERSION} before CDD rollover"
    end
    index = index_path.file? ? hash_document(index_path) : {}
    if index_path.file?
      errors.concat(validate_index_document(index, index_path))
      errors << "Director Dispatch Index must be #{INDEX_SCHEMA_VERSION}" unless index["schema_version"].to_s == INDEX_SCHEMA_VERSION
      errors << "Director Dispatch Index run does not match CDD run" unless index["run"].to_s == run_text
      open_index_holds = Array(index["holds"]).select { |hold| hold["state"].to_s == "open" }
      errors << "Director Dispatch Index admission, ownership, or canonical-head HOLD blocks CDD rollover" unless index["status"].to_s == "current" && open_index_holds.empty?
    end
    base_pack = index_path.file? ? boot_pack_projection(index, index_path) : {
      "decision_epoch" => nil,
      "active_founder_locks" => [],
      "open_or_held_tasks" => [],
      "review_queue" => {},
      "current_canonical_heads" => [],
      "next_actions" => []
    }
    unsafe_dispatch_states = %w[prepared launched returned reviewed]
    unsafe_dispatches = Array(index["dispatches"]).select do |row|
      unsafe_dispatch_states.include?(row.dig("lifecycle", "current_state").to_s)
    end
    errors << "active prepared, launched, returned, or reviewed dispatch blocks CDD rollover" unless unsafe_dispatches.empty?
    active_review_count = index.dig("review_queue", "active_review_lease_count").to_i
    active_promotion_count = index.dig("review_queue", "active_promotion_lease_count").to_i
    queued_review = Array(index.dig("review_queue", "items")).any? do |row|
      %w[queued in_review disposition_recorded promotion_in_progress].include?(row["queue_state"].to_s)
    end
    errors << "active or queued Director review/promotion blocks CDD rollover" unless active_review_count.zero? && active_promotion_count.zero? && !queued_review
    owner_collision = unsafe_dispatches.any? { |row| row.dig("owner_lock", "active") == true }
    errors << "active owner or output-path lease blocks CDD rollover" if owner_collision

    reference_path = run_path.join("research", "reference-working-index.yaml")
    reference_pointer = nil
    reference_absence_reason = nil
    if reference_path.file?
      reference_errors = validate_reference_index(reference_path)[:errors]
      errors.concat(reference_errors)
      reference_pointer = pointer(reference_path, "current_reference_working_index") if reference_errors.empty?
    else
      reference_absence_reason = "not_present_at_hash_bound_checkpoint"
    end
    profile_pointer, required_reads = cdd_successor_profile_reads(errors)
    reports = cdd_successor_report_pointers(index, errors)

    canonical_heads = Array(index["current_heads"]).select { |head| head["state"].to_s == "current" }.map do |head|
      {
        "head_id" => head["head_id"],
        "stage_id" => head["stage_id"],
        "source_dispatch_id" => head["source_dispatch_id"],
        "lineage_id" => head["lineage_id"],
        "attempt_id" => head["attempt_id"],
        "artifact" => head["artifact"]
      }
    end
    raise ValidationError, errors unless errors.empty?

    objective = "Restore the exact hash-bound CDD decision state in read-only mode, open the native Goal before required reads, answer every admission question from the bound pointers, and claim no creative or canonical authority until the prior CDD is retired and the Founder confirms the switch."
    checkpoint_token = checkpoint["checkpoint_id"].to_s.tr("-", "_")
    pack_path = run_path.join("work", "front_planning_integration", "cdd-successor", "boot-pack-#{checkpoint["checkpoint_id"]}.json")
    blocks = {
      "identity" => {
        "run" => run_text,
        "logical_role" => "creative_development_director",
        "session_key" => CDD_SESSION_KEY,
        "source_session_id" => source_session_id,
        "successor_session_id" => successor_session_id
      },
      "role_and_authority" => {
        "reports_to" => "overall_director",
        "founder_lock_owner" => "founder",
        "canonical_promotion_owner" => "overall_director",
        "preflight_may_read" => true,
        "preflight_may_author_creative_truth" => false,
        "preflight_may_write_canonical_truth" => false,
        "preflight_may_dispatch_workers" => false,
        "preflight_may_use_external_or_paid_surfaces" => false
      },
      "founder_truth" => {
        "decision_epoch" => base_pack["decision_epoch"],
        "active_founder_locks" => base_pack["active_founder_locks"]
      },
      "creative_spine" => {
        "current_plan" => plan_pointer,
        "director_development_reports" => reports
      },
      "director_decision_checkpoint" => {
        "shared_checkpoint" => {"path" => relative_path(immutable_checkpoint_path), "sha256" => checkpoint_sha, "role" => "founder_workbench_checkpoint"},
        "checkpoint_id" => checkpoint["checkpoint_id"],
        "founder_epoch" => checkpoint["founder_epoch"],
        "active_section_id" => checkpoint["active_section_id"],
        "planning_status" => checkpoint.dig("planning_state", "status")
      },
      "evidence_view" => {
        "reference_working_index" => reference_pointer,
        "reference_index_absence_reason" => reference_absence_reason,
        "required_read_set" => required_reads
      },
      "canonical_heads" => canonical_heads,
      "execution_state" => {
        "director_dispatch_index" => pointer(index_path, "director_dispatch_index_v4"),
        "source_set_sha256" => index["source_set_sha256"],
        "open_or_held_tasks" => base_pack["open_or_held_tasks"],
        "review_queue" => base_pack["review_queue"]
      },
      "review_and_next_route" => {
        "next_actions" => base_pack["next_actions"],
        "no_rollover_zones_verified" => {
          "safe_checkpoint" => true,
          "no_open_founder_gate" => true,
          "no_active_worker_return_or_director_review" => true,
          "canonical_writer_idle" => true,
          "no_owner_or_output_collision" => true,
          "hashes_fresh" => true,
          "explicit_founder_confirmation" => true
        }
      }
    }
    blocks["transfer_integrity"] = {
      "profile_registry" => profile_pointer,
      "required_read_set_sha256" => digest_value(required_reads),
      "state_blocks_sha256" => digest_value(blocks)
    }
    pack = {
      "schema_version" => CDD_SUCCESSOR_BOOT_SCHEMA_VERSION,
      "artifact_type" => "director_boot_pack",
      "profile" => "cdd_successor",
      "boot_pack_id" => "CDD_BOOT_#{checkpoint_token}",
      "run" => run_text,
      "generated_at" => checkpoint["created_at"],
      "authority_boundary" => {
        "pointer_only" => true,
        "transcript_included" => false,
        "creative_summary_authored_by_script" => false,
        "preflight_read_only" => true,
        "creative_authority" => false,
        "canonical_write" => false,
        "founder_lock_inferred" => false,
        "prior_session_retired" => false
      },
      "transfer" => {
        "logical_role" => "creative_development_director",
        "session_key" => CDD_SESSION_KEY,
        "source_session_id" => source_session_id,
        "successor_session_id" => successor_session_id,
        "logical_lineage_id" => logical_lineage_id,
        "source_attempt_id" => source_attempt_id,
        "source_checkpoint" => {"path" => relative_path(immutable_checkpoint_path), "sha256" => checkpoint_sha, "role" => "source_cdd_checkpoint"},
        "successor_authority_state" => "read_only_preflight",
        "prior_owner_release_required_before_authority" => true,
        "explicit_founder_confirmation_required_after_preflight" => true
      },
      "lineage_carry" => {
        "source_artifact" => plan_pointer.merge("role" => "front_planning_storyline_and_screen_graph"),
        "pre00_storyline_original_json_pointer" => "/storyline_lineage/pre00_lineage/pre00_storyline_original",
        "active_storyline_json_pointer" => "/storyline_lineage/active_version",
        "screen_progression_map_json_pointer" => "/screen_progression_map",
        "valid_through_stage" => "video_playback_review",
        "review_scope" => "song_reference_fp_01_02a_image_and_03v_internal_review",
        "exact_copy_only" => true
      },
      "state_blocks" => blocks,
      "admission" => {
        "response_envelope" => "idol_cdd_successor_preflight.v1",
        "objective" => objective,
        "objective_sha256" => Digest::SHA256.hexdigest(objective),
        "required_questions" => CDD_SUCCESSOR_QUESTIONS
      }
    }
    schema_validation = schema_errors_for_document(BOOT_SCHEMA, pack, "CDD successor boot pack")
    raise ValidationError, schema_validation unless schema_validation.empty?

    prompt = <<~PROMPT.strip
      First runtime action: create the native Goal with exactly this objective and record its goal id before any required read or task work:
      #{objective}

      You are the read-only successor preflight for the existing logical Creative Development Director lineage. Open and read #{relative_path(pack_path)} and every path in state_blocks.evidence_view.required_read_set to EOF. Verify the boot-pack file SHA-256 is {{BOOT_PACK_SHA256}}. Then open the exact plan, every listed Director Development Report, the shared Founder Workbench checkpoint, current Director Dispatch Index, every canonical head needed for the seven answers, and the current Reference Working Index when present. Do not write files, dispatch workers, create or revise creative truth, infer a Founder lock, or claim authority. The prior CDD remains active during this turn.

      Answer all seven required_questions with current concrete state and cite only exact path/SHA-256 pointers already present in the boot pack. If any answer or read is incomplete, return status hold. End with exactly one final envelope and no bytes after it:
      <idol_cdd_successor_preflight>{"version":1,"status":"ready|hold","boot_pack_path":"#{relative_path(pack_path)}","boot_pack_sha256":"{{BOOT_PACK_SHA256}}","source_session_id":"#{source_session_id}","successor_session_id":"#{successor_session_id}","runtime_goal":{"native_goal_id":"GOAL ID","state":"achieved|runtime_blocked","objective_sha256":"#{Digest::SHA256.hexdigest(objective)}"},"answers":{"scope_and_authority":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]},"founder_locks_and_proposals":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]},"current_recommendation_and_reason":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]},"do_not_revive":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]},"unresolved_decisions":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]},"heads_evidence_and_pending_owner":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]},"next_stop_and_wake":{"answer":"...","evidence_pointers":[{"path":"...","sha256":"..."}]}},"authority_acknowledgement":{"preflight_was_read_only":true,"creative_authority_claimed":false,"canonical_write_claimed":false,"prior_session_retirement_observed":false,"founder_confirmation_still_required":true}}</idol_cdd_successor_preflight>
    PROMPT
    {
      "status" => "pass",
      "boot_pack_path" => relative_path(pack_path),
      "boot_pack" => pack,
      "preflight_prompt_template" => prompt
    }
  end

  def cdd_successor_validate(params)
    exact_request_keys!(
      params,
      %w[action boot_pack_path boot_pack_sha256 source_session_id successor_session_id response_text],
      "CDD successor validation request"
    )
    errors = []
    pack_path = resolve_path(params["boot_pack_path"])
    pack_sha = params["boot_pack_sha256"].to_s
    errors << "CDD successor boot pack SHA-256 is invalid" unless pack_sha.match?(/\A[a-f0-9]{64}\z/)
    errors << "CDD successor boot pack SHA-256 is stale" unless pack_path.file? && sha256(pack_path) == pack_sha
    pack = hash_document(pack_path)
    errors.concat(schema_errors(BOOT_SCHEMA, pack_path))
    errors << "CDD successor boot pack profile is invalid" unless pack["profile"].to_s == "cdd_successor"
    errors << "source CDD session does not match the boot pack" unless pack.dig("transfer", "source_session_id").to_s == params["source_session_id"].to_s
    errors << "successor CDD session does not match the boot pack" unless pack.dig("transfer", "successor_session_id").to_s == params["successor_session_id"].to_s

    response_text = params["response_text"].to_s
    matches = response_text.scan(%r{<idol_cdd_successor_preflight>([\s\S]*?)</idol_cdd_successor_preflight>})
    errors << "CDD successor response must contain exactly one preflight envelope" unless matches.length == 1
    match = response_text.match(%r{<idol_cdd_successor_preflight>([\s\S]*?)</idol_cdd_successor_preflight>\s*\z})
    errors << "CDD successor preflight envelope must be the final bytes" unless match
    response = {}
    if match
      begin
        response = JSON.parse(match[1])
      rescue JSON::ParserError => e
        errors << "CDD successor preflight JSON is invalid: #{e.message}"
      end
    end
    unless response.empty?
      begin
        exact_request_keys!(
          response,
          %w[version status boot_pack_path boot_pack_sha256 source_session_id successor_session_id runtime_goal answers authority_acknowledgement],
          "CDD successor preflight response"
        )
        errors << "CDD successor preflight version must be 1" unless response["version"] == 1
        errors << "CDD successor preflight returned HOLD" unless response["status"].to_s == "ready"
        errors << "CDD successor response boot-pack path is stale" unless response["boot_pack_path"].to_s == relative_path(pack_path)
        errors << "CDD successor response boot-pack SHA-256 is stale" unless response["boot_pack_sha256"].to_s == pack_sha
        errors << "CDD successor response source session is stale" unless response["source_session_id"].to_s == params["source_session_id"].to_s
        errors << "CDD successor response target session is stale" unless response["successor_session_id"].to_s == params["successor_session_id"].to_s
        goal = exact_request_keys!(response["runtime_goal"], %w[native_goal_id state objective_sha256], "CDD successor runtime_goal")
        errors << "CDD successor Goal id is missing" if goal["native_goal_id"].to_s.strip.empty?
        errors << "CDD successor Goal must be achieved before READY" unless goal["state"].to_s == "achieved"
        errors << "CDD successor Goal objective hash is stale" unless goal["objective_sha256"].to_s == pack.dig("admission", "objective_sha256").to_s
        answers = exact_request_keys!(response["answers"], CDD_SUCCESSOR_QUESTIONS, "CDD successor answers")
        allowed_pairs = unique_sorted_pairs(pointer_pairs(pack))
        CDD_SUCCESSOR_QUESTIONS.each do |question|
          answer = exact_request_keys!(answers[question], %w[answer evidence_pointers], "CDD successor answer #{question}")
          errors << "CDD successor answer #{question} is empty" if answer["answer"].to_s.strip.empty?
          evidence = Array(answer["evidence_pointers"])
          errors << "CDD successor answer #{question} needs at least one bound evidence pointer" if evidence.empty?
          evidence.each_with_index do |row, index|
            exact_request_keys!(row, %w[path sha256], "CDD successor answer #{question} evidence #{index + 1}")
            pair = [row["path"].to_s, row["sha256"].to_s]
            errors << "CDD successor answer #{question} cites an unbound pointer #{pair.first}" unless allowed_pairs.include?(pair)
            pointer_binding_errors(row, "CDD successor answer #{question} evidence #{index + 1}", errors)
          end
        end
        acknowledgement = exact_request_keys!(
          response["authority_acknowledgement"],
          %w[preflight_was_read_only creative_authority_claimed canonical_write_claimed prior_session_retirement_observed founder_confirmation_still_required],
          "CDD successor authority acknowledgement"
        )
        expected_acknowledgement = {
          "preflight_was_read_only" => true,
          "creative_authority_claimed" => false,
          "canonical_write_claimed" => false,
          "prior_session_retirement_observed" => false,
          "founder_confirmation_still_required" => true
        }
        errors << "CDD successor authority acknowledgement is invalid" unless acknowledgement == expected_acknowledgement
      rescue ValidationError => e
        errors.concat(e.errors)
      end
    end
    raise ValidationError, errors unless errors.empty?

    admission_basis = {
      "boot_pack_path" => relative_path(pack_path),
      "boot_pack_sha256" => pack_sha,
      "source_session_id" => params["source_session_id"].to_s,
      "successor_session_id" => params["successor_session_id"].to_s,
      "response" => response
    }
    {
      "status" => "pass",
      "admission_digest" => digest_value(admission_basis),
      "boot_pack_path" => relative_path(pack_path),
      "boot_pack_sha256" => pack_sha,
      "source_session_id" => params["source_session_id"].to_s,
      "successor_session_id" => params["successor_session_id"].to_s,
      "response" => response
    }
  end

  def cdd_router_sha256?(value)
    value.to_s.match?(/\A[a-f0-9]{64}\z/)
  end

  def cdd_router_timestamp!(value, label)
    text = value.to_s
    Time.iso8601(text)
    text
  rescue ArgumentError
    raise ValidationError, ["#{label} must be an ISO-8601 timestamp"]
  end

  def cdd_router_path_within?(path, root)
    clean_path = Pathname.new(path).expand_path.cleanpath
    clean_root = Pathname.new(root).expand_path.cleanpath
    clean_path == clean_root || clean_path.to_s.start_with?("#{clean_root}#{File::SEPARATOR}")
  end

  def cdd_router_test_root
    raw = ENV["IDOL_CDD_ROUTER_TEST_ROOT"].to_s
    return nil if raw.empty?

    root = Pathname.new(raw).expand_path.cleanpath
    private_tmp = Pathname.new("/private/tmp").expand_path.cleanpath
    unless cdd_router_path_within?(root, private_tmp) && root != private_tmp
      raise ValidationError, ["IDOL_CDD_ROUTER_TEST_ROOT must name one bounded child of /private/tmp"]
    end
    root
  end

  def resolve_cdd_router_state_path(raw)
    text = raw.to_s
    raise ValidationError, ["CDD router state_path is empty"] if text.empty?

    path = Pathname.new(text)
    if path.absolute?
      test_root = cdd_router_test_root
      unless test_root && cdd_router_path_within?(path, test_root)
        raise ValidationError, ["absolute CDD router state_path requires the exact bounded /private/tmp proof root"]
      end
      return [path.expand_path.cleanpath, true]
    end

    unless text.match?(%r{\Aruns/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9\uac00-\ud7a3][a-z0-9\uac00-\ud7a3-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}/work/director-session-router/cdd-active-session\.json\z})
      raise ValidationError, ["CDD router state_path must be the canonical run work/director-session-router/cdd-active-session.json path"]
    end
    [resolve_path(text, allow_missing: true), false]
  end

  def resolve_cdd_router_bound_pointer(value, label, noncanonical_proof_root)
    pointer_value = exact_request_keys!(value, %w[path sha256], label)
    path_text = pointer_value["path"].to_s
    digest = pointer_value["sha256"].to_s
    raise ValidationError, ["#{label} SHA-256 is invalid"] unless cdd_router_sha256?(digest)

    candidate = Pathname.new(path_text)
    if candidate.absolute?
      test_root = cdd_router_test_root
      unless noncanonical_proof_root && test_root && cdd_router_path_within?(candidate, test_root)
        raise ValidationError, ["#{label} absolute path is outside the bounded proof root"]
      end
      path = candidate.expand_path.cleanpath
    else
      path = resolve_path(path_text)
    end
    raise ValidationError, ["#{label} path is missing"] unless path.file?
    raise ValidationError, ["#{label} SHA-256 is stale"] unless sha256(path) == digest
    {"path" => path_text, "sha256" => digest}
  end

  def cdd_router_validate_state!(state)
    errors = schema_errors_for_document(CDD_ROUTER_STATE_SCHEMA, state, "CDD session router state")
    raise ValidationError, errors unless errors.empty?
    state
  end

  def cdd_router_read_state(path)
    raise ValidationError, ["CDD session router state is missing"] unless path.file?
    raise ValidationError, ["CDD session router state must not be a symlink"] if path.symlink?
    state = JSON.parse(path.read)
    raise ValidationError, ["CDD session router state must contain an object"] unless state.is_a?(Hash)
    cdd_router_validate_state!(state)
    [state, sha256(path)]
  rescue JSON::ParserError => e
    raise ValidationError, ["CDD session router state JSON is invalid: #{e.message}"]
  end

  def cdd_router_atomic_write(path, state)
    cdd_router_validate_state!(state)
    payload = JSON.pretty_generate(state) + "\n"
    Tempfile.create([".cdd-session-router-", ".json"], path.dirname.to_s) do |file|
      file.chmod(0o600)
      file.write(payload)
      file.flush
      file.fsync
      File.rename(file.path, path.to_s)
    end
    File.open(path.dirname.to_s, File::RDONLY) { |directory| directory.fsync }
    sha256(path)
  rescue Errno::ENOENT, Errno::EACCES, SystemCallError => e
    raise ValidationError, ["cannot atomically write CDD session router state: #{e.message}"]
  end

  def with_cdd_router_lock(state_path_raw)
    state_path, noncanonical = resolve_cdd_router_state_path(state_path_raw)
    FileUtils.mkdir_p(state_path.dirname)
    allowed_root = noncanonical ? cdd_router_test_root : ROOT
    real_parent = state_path.dirname.realpath
    unless allowed_root && cdd_router_path_within?(real_parent, allowed_root)
      raise ValidationError, ["CDD session router state parent resolves outside its allowed root"]
    end
    raise ValidationError, ["CDD session router state must not be a symlink"] if state_path.symlink?
    lock_path = state_path.dirname.join(".cdd-active-session.lock")
    raise ValidationError, ["CDD session router lock must not be a symlink"] if lock_path.symlink?
    File.open(lock_path.to_s, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      yield state_path, noncanonical
    ensure
      lock.flock(File::LOCK_UN) rescue nil
    end
  rescue Errno::ENOENT, Errno::EACCES, SystemCallError => e
    raise ValidationError, ["cannot lock CDD session router state: #{e.message}"]
  end

  def cdd_router_transition(event:, recorded_at:, generation_before:, generation_after:, source_session_id:, successor_session_id:, active_writer_before:, active_writer_after:, previous_state_sha256:, extra_basis: {})
    transition = {
      "event" => event,
      "recorded_at" => recorded_at,
      "generation_before" => generation_before,
      "generation_after" => generation_after,
      "source_session_id" => source_session_id,
      "successor_session_id" => successor_session_id,
      "active_writer_before" => active_writer_before,
      "active_writer_after" => active_writer_after,
      "previous_state_sha256" => previous_state_sha256
    }
    receipt_basis = transition.merge("extra_basis" => extra_basis)
    transition.merge("basis_sha256" => digest_value(receipt_basis))
  end

  def cdd_router_result(state_path, state, state_sha256)
    {
      "status" => "pass",
      "state_path" => state_path.to_s,
      "state_sha256" => state_sha256,
      "generation" => state["generation"],
      "phase" => state["phase"],
      "active_writer_session_id" => state["active_writer_session_id"],
      "transition_receipt_sha256" => state.dig("last_transition", "basis_sha256"),
      "noncanonical_proof_root" => state["noncanonical_proof_root"]
    }
  end

  def cdd_router_initialize(params)
    exact_request_keys!(
      params,
      %w[action state_path assignment_id provider runtime_surface run_root logical_lineage_id source_session_id successor_session_id route_manifest provider_source boot_pack recorded_at],
      "CDD session router initialize request"
    )
    provider = params["provider"].to_s
    raise ValidationError, ["CDD session router provider must be codex, cursor, or grok"] unless %w[codex cursor grok].include?(provider)
    raise ValidationError, ["CDD session router assignment_id is invalid"] unless params["assignment_id"].to_s == CDD_ROUTER_ASSIGNMENT_ID
    source_session_id = params["source_session_id"].to_s
    successor_session_id = params["successor_session_id"].to_s
    if source_session_id.empty? || successor_session_id.empty? || source_session_id == successor_session_id
      raise ValidationError, ["CDD session router requires distinct nonempty source and successor session IDs"]
    end
    recorded_at = cdd_router_timestamp!(params["recorded_at"], "CDD session router recorded_at")

    with_cdd_router_lock(params["state_path"]) do |state_path, noncanonical|
      raise ValidationError, ["CDD session router state already exists"] if state_path.exist?
      route_manifest = resolve_cdd_router_bound_pointer(params["route_manifest"], "CDD router route_manifest", noncanonical)
      provider_source = resolve_cdd_router_bound_pointer(params["provider_source"], "CDD router provider_source", noncanonical)
      boot_pack = resolve_cdd_router_bound_pointer(params["boot_pack"], "CDD router boot_pack", noncanonical)
      transition = cdd_router_transition(
        event: "initialized",
        recorded_at: recorded_at,
        generation_before: 0,
        generation_after: 0,
        source_session_id: source_session_id,
        successor_session_id: successor_session_id,
        active_writer_before: nil,
        active_writer_after: source_session_id,
        previous_state_sha256: nil,
        extra_basis: {
          "assignment_id" => CDD_ROUTER_ASSIGNMENT_ID,
          "provider" => provider,
          "route_manifest_sha256" => route_manifest["sha256"],
          "provider_source_sha256" => provider_source["sha256"],
          "boot_pack_sha256" => boot_pack["sha256"]
        }
      )
      state = {
        "schema_version" => CDD_ROUTER_STATE_SCHEMA_VERSION,
        "router_id" => "CDD_ROUTER_#{digest_value([CDD_ROUTER_ASSIGNMENT_ID, params['logical_lineage_id'], source_session_id, successor_session_id])[0, 24].upcase}",
        "assignment_id" => CDD_ROUTER_ASSIGNMENT_ID,
        "provider" => provider,
        "runtime_surface" => params["runtime_surface"].to_s,
        "logical_lineage_id" => params["logical_lineage_id"].to_s,
        "generation" => 0,
        "phase" => "successor_preflight",
        "active_writer_session_id" => source_session_id,
        "source_session" => {"session_id" => source_session_id, "state" => "active_single_writer"},
        "successor_session" => {"session_id" => successor_session_id, "state" => "zero_turn_read_only_preflight"},
        "route_binding" => {
          "run_root" => params["run_root"].to_s,
          "route_manifest" => route_manifest,
          "provider_source" => provider_source,
          "boot_pack" => boot_pack,
          "router_implementation" => pointer(Pathname.new(__FILE__).expand_path),
          "state_schema" => pointer(CDD_ROUTER_STATE_SCHEMA)
        },
        "admission" => nil,
        "last_transition" => transition,
        "history" => [transition],
        "noncanonical_proof_root" => noncanonical
      }
      raise ValidationError, ["CDD session router runtime_surface is missing"] if state["runtime_surface"].strip.empty?
      raise ValidationError, ["CDD session router logical_lineage_id is missing"] if state["logical_lineage_id"].strip.empty?
      state_sha = cdd_router_atomic_write(state_path, state)
      cdd_router_result(state_path, state, state_sha)
    end
  end

  def cdd_router_assert_expected!(state, state_sha, params)
    expected_sha = params["expected_state_sha256"].to_s
    expected_generation = params["expected_generation"]
    raise ValidationError, ["CDD session router expected_state_sha256 is invalid"] unless cdd_router_sha256?(expected_sha)
    raise ValidationError, ["CDD session router compare-and-swap failed: state SHA changed"] unless state_sha == expected_sha
    raise ValidationError, ["CDD session router compare-and-swap failed: generation changed"] unless expected_generation.is_a?(Integer) && state["generation"] == expected_generation
    source = params["source_session_id"].to_s
    successor = params["successor_session_id"].to_s
    raise ValidationError, ["CDD session router source session is stale"] unless state.dig("source_session", "session_id").to_s == source
    raise ValidationError, ["CDD session router successor session is stale"] unless state.dig("successor_session", "session_id").to_s == successor
  end

  def cdd_router_admit(params)
    exact_request_keys!(
      params,
      %w[action state_path expected_state_sha256 expected_generation source_session_id successor_session_id admission_digest goal_receipt recorded_at],
      "CDD session router admit request"
    )
    recorded_at = cdd_router_timestamp!(params["recorded_at"], "CDD session router recorded_at")
    admission_digest = params["admission_digest"].to_s
    raise ValidationError, ["CDD successor admission_digest is invalid"] unless cdd_router_sha256?(admission_digest)
    goal = exact_request_keys!(
      params["goal_receipt"],
      %w[goal_id goal_semantics objective_sha256 terminal_state last_event terminal_event_sha256],
      "CDD session router goal_receipt"
    )
    %w[objective_sha256 terminal_event_sha256].each do |field|
      raise ValidationError, ["CDD session router goal_receipt #{field} is invalid"] unless cdd_router_sha256?(goal[field])
    end
    raise ValidationError, ["CDD session router goal id is missing"] if goal["goal_id"].to_s.strip.empty?

    with_cdd_router_lock(params["state_path"]) do |state_path, _noncanonical|
      state, state_sha = cdd_router_read_state(state_path)
      cdd_router_assert_expected!(state, state_sha, params)
      raise ValidationError, ["CDD session router can admit only from successor_preflight"] unless state["phase"] == "successor_preflight"
      expected_goal = case state["provider"]
                      when "grok"
                        ["grok_goal_completed_admission", "complete", "goal_completed"]
                      when "cursor"
                        ["cursor_external_goal_runtime_receipt", "success", "cli_terminal_success"]
                      else
                        ["codex_thread_goal_active", "active", "goal_active"]
                      end
      actual_goal = [goal["goal_semantics"], goal["terminal_state"], goal["last_event"]]
      unless actual_goal == expected_goal
        raise ValidationError, ["CDD session router provider-native Goal semantics are invalid for #{state['provider']}"]
      end
      generation = state["generation"]
      transition = cdd_router_transition(
        event: "admitted",
        recorded_at: recorded_at,
        generation_before: generation,
        generation_after: generation + 1,
        source_session_id: params["source_session_id"],
        successor_session_id: params["successor_session_id"],
        active_writer_before: state["active_writer_session_id"],
        active_writer_after: state["active_writer_session_id"],
        previous_state_sha256: state_sha,
        extra_basis: {
          "admission_digest" => admission_digest,
          "goal_id" => goal["goal_id"],
          "goal_semantics" => goal["goal_semantics"],
          "goal_terminal_event_sha256" => goal["terminal_event_sha256"]
        }
      )
      state["generation"] = generation + 1
      state["phase"] = "successor_admitted"
      state["successor_session"]["state"] = "admitted_read_only"
      state["admission"] = {
        "admission_digest" => admission_digest,
        "goal_id" => goal["goal_id"],
        "goal_semantics" => goal["goal_semantics"],
        "goal_objective_sha256" => goal["objective_sha256"],
        "goal_terminal_state" => goal["terminal_state"],
        "goal_last_event" => goal["last_event"],
        "goal_terminal_event_sha256" => goal["terminal_event_sha256"]
      }
      state["last_transition"] = transition
      state["history"] << transition
      next_sha = cdd_router_atomic_write(state_path, state)
      cdd_router_result(state_path, state, next_sha)
    end
  end

  def cdd_router_commit(params)
    exact_request_keys!(
      params,
      %w[action state_path expected_state_sha256 expected_generation source_session_id successor_session_id admission_digest founder_confirmation_sha256 recorded_at],
      "CDD session router commit request"
    )
    recorded_at = cdd_router_timestamp!(params["recorded_at"], "CDD session router recorded_at")
    admission_digest = params["admission_digest"].to_s
    founder_sha = params["founder_confirmation_sha256"].to_s
    raise ValidationError, ["CDD session router admission_digest is invalid"] unless cdd_router_sha256?(admission_digest)
    raise ValidationError, ["CDD session router Founder confirmation SHA-256 is invalid"] unless cdd_router_sha256?(founder_sha)
    with_cdd_router_lock(params["state_path"]) do |state_path, _noncanonical|
      state, state_sha = cdd_router_read_state(state_path)
      cdd_router_assert_expected!(state, state_sha, params)
      raise ValidationError, ["CDD session router can commit only an admitted successor"] unless state["phase"] == "successor_admitted"
      raise ValidationError, ["CDD session router admission digest is stale"] unless state.dig("admission", "admission_digest").to_s == admission_digest
      source_session_id = params["source_session_id"].to_s
      successor_session_id = params["successor_session_id"].to_s
      raise ValidationError, ["CDD session router source is not the active writer"] unless state["active_writer_session_id"] == source_session_id
      generation = state["generation"]
      transition = cdd_router_transition(
        event: "committed",
        recorded_at: recorded_at,
        generation_before: generation,
        generation_after: generation + 1,
        source_session_id: source_session_id,
        successor_session_id: successor_session_id,
        active_writer_before: source_session_id,
        active_writer_after: successor_session_id,
        previous_state_sha256: state_sha,
        extra_basis: {"admission_digest" => admission_digest, "founder_confirmation_sha256" => founder_sha}
      )
      state["generation"] = generation + 1
      state["phase"] = "successor_active"
      state["active_writer_session_id"] = successor_session_id
      state["source_session"]["state"] = "harness_logically_retired"
      state["successor_session"]["state"] = "active_single_writer"
      state["last_transition"] = transition
      state["history"] << transition
      next_sha = cdd_router_atomic_write(state_path, state)
      cdd_router_result(state_path, state, next_sha)
    end
  end

  def cdd_router_authorize(params)
    exact_request_keys!(
      params,
      %w[action state_path expected_state_sha256 expected_generation session_id operation],
      "CDD session router authorize request"
    )
    operation = params["operation"].to_s
    raise ValidationError, ["CDD session router operation is unsupported"] unless CDD_ROUTER_OPERATIONS.include?(operation)
    state_path, _noncanonical = resolve_cdd_router_state_path(params["state_path"])
    state, state_sha = cdd_router_read_state(state_path)
    expected_sha = params["expected_state_sha256"].to_s
    expected_generation = params["expected_generation"]
    raise ValidationError, ["CDD session router authorization state SHA is stale"] unless cdd_router_sha256?(expected_sha) && expected_sha == state_sha
    raise ValidationError, ["CDD session router authorization generation is stale"] unless expected_generation.is_a?(Integer) && expected_generation == state["generation"]
    session_id = params["session_id"].to_s
    allowed = if operation == "goal_and_preflight"
                %w[successor_preflight successor_admitted].include?(state["phase"]) && session_id == state.dig("successor_session", "session_id")
              else
                session_id == state["active_writer_session_id"] &&
                  ["active_single_writer", "reactivated_single_writer"].include?(
                    session_id == state.dig("source_session", "session_id") ? state.dig("source_session", "state") : state.dig("successor_session", "state")
                  )
              end
    raise ValidationError, ["CDD session router denied #{operation} for inactive or read-only session #{session_id}"] unless allowed
    basis = {
      "state_sha256" => state_sha,
      "generation" => state["generation"],
      "session_id" => session_id,
      "operation" => operation,
      "active_writer_session_id" => state["active_writer_session_id"],
      "phase" => state["phase"]
    }
    {
      "status" => "pass",
      "authorization" => "allowed",
      "authorization_receipt_sha256" => digest_value(basis),
      "basis" => basis
    }
  end

  def cdd_router_rollback(params)
    exact_request_keys!(
      params,
      %w[action state_path expected_state_sha256 expected_generation source_session_id successor_session_id commit_receipt_sha256 failure_receipt_sha256 recorded_at],
      "CDD session router rollback request"
    )
    recorded_at = cdd_router_timestamp!(params["recorded_at"], "CDD session router recorded_at")
    commit_sha = params["commit_receipt_sha256"].to_s
    failure_sha = params["failure_receipt_sha256"].to_s
    raise ValidationError, ["CDD session router commit receipt SHA-256 is invalid"] unless cdd_router_sha256?(commit_sha)
    raise ValidationError, ["CDD session router failure receipt SHA-256 is invalid"] unless cdd_router_sha256?(failure_sha)
    with_cdd_router_lock(params["state_path"]) do |state_path, _noncanonical|
      state, state_sha = cdd_router_read_state(state_path)
      cdd_router_assert_expected!(state, state_sha, params)
      raise ValidationError, ["CDD session router can rollback only an active successor"] unless state["phase"] == "successor_active"
      raise ValidationError, ["CDD session router commit receipt does not match the active transition"] unless state.dig("last_transition", "event") == "committed" && state.dig("last_transition", "basis_sha256") == commit_sha
      source_session_id = params["source_session_id"].to_s
      successor_session_id = params["successor_session_id"].to_s
      raise ValidationError, ["CDD session router successor is not the active writer"] unless state["active_writer_session_id"] == successor_session_id
      generation = state["generation"]
      transition = cdd_router_transition(
        event: "rolled_back",
        recorded_at: recorded_at,
        generation_before: generation,
        generation_after: generation + 1,
        source_session_id: source_session_id,
        successor_session_id: successor_session_id,
        active_writer_before: successor_session_id,
        active_writer_after: source_session_id,
        previous_state_sha256: state_sha,
        extra_basis: {"commit_receipt_sha256" => commit_sha, "failure_receipt_sha256" => failure_sha}
      )
      state["generation"] = generation + 1
      state["phase"] = "rolled_back"
      state["active_writer_session_id"] = source_session_id
      state["source_session"]["state"] = "reactivated_single_writer"
      state["successor_session"]["state"] = "harness_logically_retired"
      state["last_transition"] = transition
      state["history"] << transition
      next_sha = cdd_router_atomic_write(state_path, state)
      cdd_router_result(state_path, state, next_sha)
    end
  end

  def cdd_router_snapshot(params)
    exact_request_keys!(params, %w[action state_path], "CDD session router snapshot request")
    state_path, _noncanonical = resolve_cdd_router_state_path(params["state_path"])
    state, state_sha = cdd_router_read_state(state_path)
    cdd_router_result(state_path, state, state_sha).merge("state" => state)
  end

  def cdd_successor_command(params)
    action = params.is_a?(Hash) ? params["action"].to_s : ""
    case action
    when "prepare"
      cdd_successor_prepare(params)
    when "validate"
      cdd_successor_validate(params)
    when "route-initialize"
      cdd_router_initialize(params)
    when "route-admit"
      cdd_router_admit(params)
    when "route-commit"
      cdd_router_commit(params)
    when "route-authorize"
      cdd_router_authorize(params)
    when "route-rollback"
      cdd_router_rollback(params)
    when "route-snapshot"
      cdd_router_snapshot(params)
    else
      raise ValidationError, ["CDD successor action must be prepare, validate, or one registered route-* action"]
    end
  end
end

def print_result(value, json)
  if json
    puts JSON.pretty_generate(value)
  else
    puts value.is_a?(Hash) ? value.map { |key, item| "#{key}: #{item}" }.join("\n") : value
  end
end

if $PROGRAM_NAME == __FILE__
  command = ARGV.shift.to_s
  if command.empty?
    warn "usage: ruby scripts/idol_director_dispatch_index.rb build|validate|validate-reference|cdd-successor ..."
    exit 2
  end

  begin
  case command
  when "build"
    options = {json: false, output: nil, views: [], requirements: nil, retries: 2, generated_at: nil, if_source_set: nil, validate_reference: true}
    OptionParser.new do |parser|
      parser.banner = "usage: ... build RUN_ROOT [options]"
      parser.on("--json") { options[:json] = true }
      parser.on("--output PATH") { |value| options[:output] = value }
      parser.on("--view SPEC") { |value| options[:views] << value }
      parser.on("--requirements PATH") { |value| options[:requirements] = value }
      parser.on("--retries N", Integer) { |value| options[:retries] = value }
      parser.on("--generated-at VALUE") { |value| options[:generated_at] = value }
      parser.on("--if-source-set SHA256") { |value| options[:if_source_set] = value }
      parser.on("--skip-reference-validation") { options[:validate_reference] = false }
    end.parse!(ARGV)
    run_arg = ARGV.shift
    raise IdolDirectorDispatchIndex::ValidationError, ["RUN_ROOT is required"] if run_arg.to_s.empty? || !ARGV.empty?
    run_path = IdolDirectorDispatchIndex.resolve_path(run_arg)
    output, views, index = IdolDirectorDispatchIndex.write_index(run_path, options)
    admission_entries = Array(index.dig("dispatch_source_set", "entries"))
    result = {
      "status" => "pass",
      "index" => IdolDirectorDispatchIndex.relative_path(output),
      "views" => views,
      "source_set_sha256" => index["source_set_sha256"],
      "dispatch_count" => Array(index["dispatches"]).length,
      "dispatch_admission_count" => admission_entries.length,
      "legacy_pinned_count" => admission_entries.count { |entry| entry["classification"].to_s == "legacy_pinned" },
      "held_incompatible_count" => admission_entries.count { |entry| entry["classification"].to_s == "held_incompatible" }
    }
    print_result(result, options[:json])
  when "validate"
    options = {json: false, skip_reference: false}
    OptionParser.new do |parser|
      parser.banner = "usage: ... validate INDEX_PATH [options]"
      parser.on("--json") { options[:json] = true }
      parser.on("--skip-reference-validation") { options[:skip_reference] = true }
    end.parse!(ARGV)
    path = ARGV.shift
    raise IdolDirectorDispatchIndex::ValidationError, ["INDEX_PATH is required"] if path.to_s.empty? || !ARGV.empty?
    index_path = IdolDirectorDispatchIndex.resolve_path(path)
    index = IdolDirectorDispatchIndex.hash_document(index_path)
    errors = IdolDirectorDispatchIndex.validate_index_document(index, index_path, nil, validate_reference: !options[:skip_reference])
    result = {"status" => errors.empty? ? "pass" : "fail", "index" => IdolDirectorDispatchIndex.relative_path(index_path), "errors" => errors}
    print_result(result, options[:json])
    exit(errors.empty? ? 0 : 1)
  when "validate-reference"
    options = {json: false}
    OptionParser.new { |parser| parser.on("--json") { options[:json] = true } }.parse!(ARGV)
    path = ARGV.shift
    raise IdolDirectorDispatchIndex::ValidationError, ["REFERENCE_INDEX_PATH is required"] if path.to_s.empty? || !ARGV.empty?
    reference_path = IdolDirectorDispatchIndex.resolve_path(path)
    errors = IdolDirectorDispatchIndex.validate_reference_index(reference_path)[:errors]
    result = {"status" => errors.empty? ? "pass" : "fail", "reference_index" => IdolDirectorDispatchIndex.relative_path(reference_path), "errors" => errors}
    print_result(result, options[:json])
    exit(errors.empty? ? 0 : 1)
  when "boot-pack"
    raise IdolDirectorDispatchIndex::ValidationError, [
      "generic boot-pack is retired because it emitted an untyped v1 artifact; use cdd-successor prepare for the schema-valid Director Boot Pack v3 route"
    ]
  when "cdd-successor"
    raise IdolDirectorDispatchIndex::ValidationError, ["cdd-successor accepts one JSON request on stdin and no arguments"] unless ARGV.empty?
    begin
      request = JSON.parse($stdin.read)
    rescue JSON::ParserError => e
      raise IdolDirectorDispatchIndex::ValidationError, ["CDD successor request JSON is invalid: #{e.message}"]
    end
    result = IdolDirectorDispatchIndex.cdd_successor_command(request)
    puts JSON.generate(result)
  else
    raise IdolDirectorDispatchIndex::ValidationError, ["unknown command: #{command}"]
  end
  rescue IdolDirectorDispatchIndex::ValidationError => e
    warn e.errors.map { |error| "ERROR: #{error}" }.join("\n")
    exit 1
  end
end
