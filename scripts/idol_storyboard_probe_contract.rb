#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "tempfile"
require "tmpdir"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"

# Deterministic validation and merge support for the retired read-only storyboard
# capability probe. This contract deliberately does not create, approve, or
# replace production 02A/02B truth. It only checks NONCANONICAL evaluation
# evidence against a frozen source allowlist and the existing 02A child-shot
# semantics.
module IdolStoryboardProbeContract
  REPOSITORY_ROOT = Pathname.new(__dir__).join("..").expand_path.cleanpath
  SHARD_SCHEMA_VERSION = "idol_storyboard_probe_section.v1"
  RESULT_SCHEMA_VERSION = "idol_storyboard_probe_result.v1"
  CHILD_KEYFRAME_MODE = "child_keyframe_elaboration"
  SECTION_AUTHORING_MODE = "section_02a_authoring"
  PROBE_MODES = [CHILD_KEYFRAME_MODE, SECTION_AUTHORING_MODE].freeze
  CHILD_CONTEXT_SCHEMA_VERSION = "idol_storyboard_probe_section_input.v1"
  AUTHORING_CONTEXT_SCHEMA_VERSION = "idol_storyboard_probe_section_input.v2"
  NONCANONICAL_STATUS = "noncanonical_evaluation_only"
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  CUT_ID_PATTERN = /\AC\d{3,}_[A-Z0-9][A-Z0-9_]*\z/
  MEMBER_ID_PATTERN = /\AM(?:0[1-9]|1[0-3])\z/
  CAMERA_FIELDS = %w[
    height
    shot_scale_distance
    direction_angle
    depth_framing
    movement_or_hold
    screen_placement_crop
    readability_reason
  ].freeze
  CUT_REQUIRED_TEXT_FIELDS = %w[
    time_range
    audio_cue
    visible_action_or_hold
    composition
    continuity_in
    continuity_out
    image_prompt_blueprint
  ].freeze
  MODEL_ROUTE = {
    "model" => "gpt-5.6-sol",
    "effort" => "xhigh",
    "verbosity" => "high"
  }.freeze
  IDENTITY_FIELDS = %w[
    face_visible
    face_visibility_reason
    identity_focus_members
    identity_reference_source
    scene_reference_mode
  ].freeze
  ALLOWLIST_SOURCE_FIELDS = %w[
    path
    sha256
    disposition
    function
    target_sections
    reason
  ].freeze
  ALLOWLIST_SOURCE_OPTIONAL_FIELDS = %w[evidence_scope required_evidence_sections].freeze
  EVIDENCE_SCOPES = %w[
    per_declared_target
    at_least_one_declared_target
    context_only_per_target
  ].freeze
  CLOSED_DISPOSITIONS = %w[applied combined held rejected].freeze
  RECEIPT_FIELDS = %w[
    probe_mode
    section_id
    section_order
    harness_commit
    context_path
    context_file_sha256
    section_context_sha256
    path
    sha256
  ].freeze
  NORMALIZATION_RECEIPT_FIELDS = %w[
    receipt_version
    probe_mode
    raw_path
    raw_sha256
    context_path
    context_file_sha256
    section_context_sha256
    harness_commit
    raw_keyframe_shots_sha256
    keyframe_shots_sha256
    collapsed_exact_duplicate_cuts
    repaired_locked_field_paths
    repaired_locked_field_count
  ].freeze
  AUTHORING_NORMALIZATION_RECEIPT_FIELDS = (
    NORMALIZATION_RECEIPT_FIELDS + %w[
      raw_creative_section_semantic_sha256
      normalized_creative_section_semantic_sha256
    ]
  ).freeze
  EXECUTION_RECEIPT_FIELDS = %w[
    receipt_version
    probe_mode
    evidence_mode
    execution_log_path
    execution_log_sha256
    turn_id
    actual_model
    actual_effort
    context_path
    section_context_sha256
    raw_output_semantic_sha256
    task_complete
  ].freeze
  COMPACT_EXECUTION_ATTESTATION_SCHEMA_VERSION = "idol_storyboard_probe_execution_attestation.v1"
  COMPACT_EXECUTION_ATTESTATION_FIELDS = %w[
    schema_version
    status
    receipt_mode
    probe_mode
    context_path
    raw_path
    raw_sha256
    raw_output_semantic_sha256
    keyframe_shots_sha256
    creative_section_semantic_sha256
    section_id
    actual_core_cut_count
    actual_keyframe_count
  ].freeze
  RESULT_FIELDS = %w[
    schema_version
    status
    probe_mode
    harness_commit
    repo_root_binding
    model_route
    source_set_sha256
    shard_receipts
    sections
    source_use_audit
    coverage_audit
  ].freeze
  SOURCE_AUDIT_FIELDS = %w[
    sources
    referenced_source_paths
    unreferenced_source_paths
    unknown_source_paths
    direct_reference_paths
    supporting_context_paths
    unevidenced_direct_paths
    unevidenced_supporting_paths
    direct_reference_closure_complete
    supporting_context_closure_complete
    reference_closure_complete
  ].freeze
  COVERAGE_FIELDS = %w[
    required_section_ids
    completed_section_ids
    missing_section_ids
    extra_section_ids
    section_cut_counts
    section_keyframe_counts
    section_cut_ids
    keyframe_shot_ids
    packet_ids
    actual_core_cut_count
    actual_keyframe_count
    numeric_cap_used
    section_by_section_pass_used
  ].freeze
  CONTEXT_COMMON_FIELDS = %w[
    schema_version
    status
    probe_mode
    harness_commit
    section_id
    section_order
    time_range
    model_route
    source_set_sha256
    section_context_sha256
    previous_boundary
    next_boundary
  ].freeze
  CHILD_CONTEXT_FIELDS = (
    CONTEXT_COMMON_FIELDS + %w[section_plan required_parent_cuts allowed_sources]
  ).freeze
  AUTHORING_CONTEXT_FIELDS = (
    CONTEXT_COMMON_FIELDS + %w[
      root_locked_envelope
      section_plan
      whole_film_locks
      boundary_locks
      source_locks
      split_obligations
    ]
  ).freeze
  AUTHORING_RAW_SHARD_FIELDS = %w[
    schema_version
    status
    probe_mode
    harness_commit
    section_id
    section_order
    time_range
    model_route
    source_set_sha256
    section_context_sha256
    previous_boundary
    next_boundary
    section
  ].freeze

  class ContractError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors).map(&:to_s).reject(&:empty?)
      super(@errors.join("; "))
    end
  end

  module_function

  def load_structured(path)
    pathname = Pathname.new(path.to_s).expand_path.cleanpath
    raise ContractError, ["file is not readable: #{pathname}"] unless pathname.file?

    content = pathname.binread.force_encoding(Encoding::UTF_8)
    raise ContractError, ["file is not valid UTF-8: #{pathname}"] unless content.valid_encoding?

    document = if pathname.extname.downcase == ".json"
                 JSON.parse(content)
               else
                 YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
               end
    raise ContractError, ["document must be an object: #{pathname}"] unless document.is_a?(Hash)

    [pathname, stringify_keys(document)]
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError, ["cannot parse #{pathname || path}: #{e.message}"]
  end

  def stringify_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
    when Array
      value.map { |item| stringify_keys(item) }
    else
      value
    end
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def canonical_json_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        result[key] = canonical_json_value(value[key])
      end
    when Array
      value.map { |item| canonical_json_value(item) }
    else
      value
    end
  end

  def semantic_digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(value)))
  end

  # Canonical digest used by the probe packets: sort the exact path/hash pairs,
  # serialize them as compact UTF-8 JSON two-element arrays, then hash those
  # bytes. Extra descriptive allowlist fields never affect source identity.
  def source_set_digest(sources)
    pairs = sources.map { |source| [source.fetch("path"), source.fetch("sha256")] }.sort
    Digest::SHA256.hexdigest(JSON.generate(pairs))
  end

  def duplicate_values(values)
    values.group_by { |value| value }.select { |_value, rows| rows.length > 1 }.keys
  end

  def repo_relative_path?(value)
    text = value.to_s
    return false if text.empty? || text.include?("\0") || text.include?("\\")

    path = Pathname.new(text)
    return false if path.absolute? || text == "." || text.start_with?("./")

    path.cleanpath.to_s == text && !path.each_filename.any? { |part| part == ".." }
  end

  def resolve_repo_root(path)
    root = Pathname.new(path.to_s).expand_path.cleanpath
    raise ContractError, ["repo root is not a directory: #{root}"] unless root.directory?

    root.realpath
  rescue Errno::ENOENT, Errno::EACCES => e
    raise ContractError, ["cannot resolve repo root #{root || path}: #{e.message}"]
  end

  def path_inside_root?(path, root)
    path.to_s.start_with?("#{root}#{File::SEPARATOR}")
  end

  def closed_source_row?(row)
    CLOSED_DISPOSITIONS.include?(row["disposition"].to_s) &&
      nonempty_string?(row["function"]) &&
      row["target_sections"].is_a?(Array) &&
      row["target_sections"].any? &&
      row["target_sections"].all? { |section| nonempty_string?(section) } &&
      nonempty_string?(row["reason"])
  end

  def validate_allowlist(path, repo_root: REPOSITORY_ROOT)
    pathname, document = load_structured(path)
    root = resolve_repo_root(repo_root)
    errors = []
    harness_commit = document["harness_commit"]
    errors << "allowlist.harness_commit is required" unless nonempty_string?(harness_commit)
    section_universe = document["section_universe"]
    unless section_universe.is_a?(Array) && section_universe.any? && section_universe.all? { |section| nonempty_string?(section) && section.match?(/\AS[A-Z0-9_]+\z/) }
      errors << "allowlist.section_universe must be a non-empty ordered list of S-prefixed section ids"
      section_universe = []
    end
    duplicate_universe_sections = duplicate_values(section_universe)
    errors << "allowlist.section_universe must contain unique ids: #{duplicate_universe_sections.join(', ')}" unless duplicate_universe_sections.empty?

    rows = document["sources"]
    unless rows.is_a?(Array) && rows.any?
      errors << "allowlist.sources must be a non-empty array"
      rows = []
    end

    normalized = []
    rows.each_with_index do |row, index|
      label = "allowlist.sources[#{index}]"
      unless row.is_a?(Hash)
        errors << "#{label} must be an object"
        next
      end
      row_keys = row.keys.map(&:to_s)
      missing_source_fields = ALLOWLIST_SOURCE_FIELDS - row_keys
      unexpected_source_fields = row_keys - (ALLOWLIST_SOURCE_FIELDS + ALLOWLIST_SOURCE_OPTIONAL_FIELDS)
      errors << "#{label} is missing keys: #{missing_source_fields.join(', ')}" unless missing_source_fields.empty?
      errors << "#{label} contains unexpected keys: #{unexpected_source_fields.join(', ')}" unless unexpected_source_fields.empty?
      source_path = row["path"]
      sha256 = row["sha256"]
      errors << "#{label}.path must be a normalized repo-relative path" unless repo_relative_path?(source_path)
      errors << "#{label}.sha256 must be exactly 64 lowercase hexadecimal characters" unless sha256.to_s.match?(SHA256_PATTERN)
      errors << "#{label}.disposition must be applied, combined, held, or rejected" unless CLOSED_DISPOSITIONS.include?(row["disposition"].to_s)
      errors << "#{label}.function is required" unless nonempty_string?(row["function"])
      target_sections = row["target_sections"]
      unless target_sections.is_a?(Array) && target_sections.any? && target_sections.all? { |section| nonempty_string?(section) }
        errors << "#{label}.target_sections must be a non-empty list of non-empty section ids"
        target_sections = []
      end
      errors << "#{label}.target_sections must be unique" unless target_sections.uniq.length == target_sections.length
      unknown_target_sections = target_sections - section_universe
      errors << "#{label}.target_sections contains sections outside allowlist.section_universe: #{unknown_target_sections.join(', ')}" unless unknown_target_sections.empty?
      errors << "#{label}.reason is required" unless nonempty_string?(row["reason"])

      evidence_scope = row["evidence_scope"]
      if row.key?("evidence_scope") && !EVIDENCE_SCOPES.include?(evidence_scope.to_s)
        errors << "#{label}.evidence_scope must be one of #{EVIDENCE_SCOPES.join(', ')}"
      end
      required_evidence_sections = row["required_evidence_sections"]
      if row.key?("required_evidence_sections")
        unless required_evidence_sections.is_a?(Array) && required_evidence_sections.all? { |section| nonempty_string?(section) }
          errors << "#{label}.required_evidence_sections must be a list of non-empty section ids"
          required_evidence_sections = []
        end
        errors << "#{label}.required_evidence_sections must be unique" unless required_evidence_sections.uniq.length == required_evidence_sections.length
        outside_targets = required_evidence_sections - target_sections
        errors << "#{label}.required_evidence_sections must be a subset of target_sections: #{outside_targets.join(', ')}" unless outside_targets.empty?
      end

      normalized_row = {
        "path" => source_path.to_s,
        "sha256" => sha256.to_s,
        "disposition" => row["disposition"].to_s,
        "function" => row["function"].to_s,
        "target_sections" => deep_copy(target_sections),
        "reason" => row["reason"].to_s
      }
      normalized_row["evidence_scope"] = evidence_scope.to_s if row.key?("evidence_scope")
      normalized_row["required_evidence_sections"] = deep_copy(required_evidence_sections) if row.key?("required_evidence_sections")
      normalized << normalized_row

      next unless repo_relative_path?(source_path)

      candidate = root.join(source_path).cleanpath
      unless path_inside_root?(candidate, root)
        errors << "#{label}.path escapes the repo root: #{source_path}"
        next
      end
      begin
        stat = File.lstat(candidate.to_s)
        if stat.symlink?
          errors << "#{label}.path must not be a symlink: #{source_path}"
          next
        end
        unless stat.file?
          errors << "#{label}.path must be a regular file: #{source_path}"
          next
        end
        real_source = candidate.realpath
        unless path_inside_root?(real_source, root)
          errors << "#{label}.path resolves outside the repo root: #{source_path}"
          next
        end
        actual_sha256 = Digest::SHA256.file(real_source.to_s).hexdigest
        unless actual_sha256 == sha256.to_s
          errors << "#{label}.sha256 does not match source bytes: #{source_path}"
        end
      rescue Errno::ENOENT, Errno::EACCES => e
        errors << "#{label}.path is not a readable regular file: #{source_path} (#{e.class})"
      end
    end

    duplicates = duplicate_values(normalized.map { |row| row["path"] })
    errors << "allowlist contains duplicate source paths: #{duplicates.join(', ')}" unless duplicates.empty?

    supporting_context_source_paths = document["supporting_context_source_paths"]
    unless supporting_context_source_paths.is_a?(Array) && supporting_context_source_paths.all? { |source_path| repo_relative_path?(source_path) }
      errors << "allowlist.supporting_context_source_paths must be an ordered list of normalized repo-relative paths"
      supporting_context_source_paths = []
    end
    duplicate_supporting_paths = duplicate_values(supporting_context_source_paths)
    errors << "allowlist.supporting_context_source_paths must be unique: #{duplicate_supporting_paths.join(', ')}" unless duplicate_supporting_paths.empty?
    unknown_supporting_paths = supporting_context_source_paths - normalized.map { |row| row["path"] }
    errors << "allowlist.supporting_context_source_paths contains paths outside sources: #{unknown_supporting_paths.join(', ')}" unless unknown_supporting_paths.empty?
    invalid_context_only_paths = normalized.select do |row|
      row["evidence_scope"] == "context_only_per_target" && !supporting_context_source_paths.include?(row["path"])
    end.map { |row| row["path"] }
    errors << "context_only_per_target sources must be listed in supporting_context_source_paths: #{invalid_context_only_paths.join(', ')}" unless invalid_context_only_paths.empty?

    digest = source_set_digest(normalized)
    supplied_digest = document["source_set_sha256"]
    if supplied_digest
      errors << "allowlist.source_set_sha256 must be exactly 64 lowercase hexadecimal characters" unless supplied_digest.to_s.match?(SHA256_PATTERN)
      errors << "allowlist.source_set_sha256 does not match the derived path/hash digest" unless supplied_digest.to_s == digest
    end
    raise ContractError, errors unless errors.empty?

    root_binding_material = {
      "realpath" => root.to_s,
      "source_set_sha256" => digest,
      "section_universe" => deep_copy(section_universe),
      "supporting_context_source_paths" => deep_copy(supporting_context_source_paths)
    }

    {
      "path" => pathname.to_s,
      "repo_root" => root.to_s,
      "repo_root_binding" => root_binding_material.merge(
        "binding_sha256" => Digest::SHA256.hexdigest(JSON.generate(root_binding_material))
      ),
      "harness_commit" => harness_commit.to_s,
      "section_universe" => deep_copy(section_universe),
      "supporting_context_source_paths" => deep_copy(supporting_context_source_paths),
      "sources" => normalized,
      "source_set_sha256" => digest,
      "source_paths" => normalized.map { |row| row["path"] }
    }
  end

  def parse_sections(value)
    sections = value.to_s.split(",", -1).map(&:strip)
    errors = []
    errors << "--sections must contain at least one section id" if sections.empty? || sections.any?(&:empty?)
    duplicates = duplicate_values(sections)
    errors << "--sections contains duplicate ids: #{duplicates.join(', ')}" unless duplicates.empty?
    errors << "--sections ids must use the S-prefixed section namespace" unless sections.all? { |section| section.match?(/\AS[A-Z0-9_]+\z/) }
    raise ContractError, errors unless errors.empty?

    sections
  end

  def validate_requested_sections(allowlist, expected_sections)
    unknown = expected_sections - allowlist["section_universe"]
    errors = []
    errors << "--sections contains ids outside allowlist.section_universe: #{unknown.join(', ')}" unless unknown.empty?
    raise ContractError, errors unless errors.empty?

    true
  end

  def absolute_section_order(allowlist, section_id)
    index = allowlist["section_universe"].index(section_id)
    raise ContractError, ["section is outside allowlist.section_universe: #{section_id}"] unless index

    index + 1
  end

  def temporary_output_path?(path, repo_root)
    pathname = Pathname.new(path.to_s).expand_path.cleanpath
    missing_parts = [pathname.basename.to_s]
    existing_parent = pathname.dirname
    until existing_parent.exist?
      missing_parts.unshift(existing_parent.basename.to_s)
      existing_parent = existing_parent.dirname
    end
    pathname = missing_parts.reduce(existing_parent.realpath) { |base, part| base.join(part) }.cleanpath
    root = Pathname.new(repo_root.to_s).expand_path.cleanpath.realpath
    return false if pathname.to_s == root.to_s || path_inside_root?(pathname, root)

    temp_roots = [Dir.tmpdir, "/private/tmp", "/tmp"].map do |candidate|
      candidate_path = Pathname.new(candidate).expand_path.cleanpath
      candidate_path.exist? ? candidate_path.realpath : candidate_path
    end.uniq
    temp_roots.any? { |temp_root| pathname.to_s.start_with?("#{temp_root}#{File::SEPARATOR}") }
  end

  def section_context_digest(document)
    digest_input = deep_copy(document)
    digest_input.delete("section_context_sha256")
    Digest::SHA256.hexdigest(JSON.generate(digest_input))
  end

  def recursive_forbidden_keys(value, forbidden, label, errors)
    case value
    when Hash
      parent_truth_signature = %w[audio_cue visible_action_or_hold composition camera image_prompt_blueprint]
      if (value.keys.map(&:to_s) & parent_truth_signature).length >= 4
        errors << "#{label} contains a forbidden full parent-cut creative truth payload"
      end
      value.each do |key, item|
        errors << "#{label}.#{key} is forbidden in a section_02a_authoring input" if forbidden.include?(key.to_s)
        recursive_forbidden_keys(item, forbidden, "#{label}.#{key}", errors)
      end
    when Array
      value.each_with_index { |item, index| recursive_forbidden_keys(item, forbidden, "#{label}[#{index}]", errors) }
    end
  end

  def authoring_lock_ids(rows, label, errors, required_fields: %w[lock_id requirement])
    unless rows.is_a?(Array) && rows.any?
      errors << "#{label} must be a non-empty array"
      return []
    end

    ids = []
    rows.each_with_index do |row, index|
      row_label = "#{label}[#{index}]"
      errors.concat(exact_keys_errors(row, required_fields, row_label))
      next unless row.is_a?(Hash)

      lock_id = row["lock_id"].to_s
      errors << "#{row_label}.lock_id is required" unless nonempty_string?(row["lock_id"])
      required_fields.reject { |field| field == "lock_id" }.each do |field|
        errors << "#{row_label}.#{field} is required" unless nonempty_string?(row[field])
      end
      ids << lock_id unless lock_id.empty?
    end
    duplicates = duplicate_values(ids)
    errors << "#{label} contains duplicate lock_id values: #{duplicates.join(', ')}" unless duplicates.empty?
    ids
  end

  def validate_context_file(path, allowlist, expected_section_id:, expected_order:)
    pathname = Pathname.new(path.to_s).expand_path.cleanpath
    errors = []
    begin
      stat = File.lstat(pathname.to_s)
      errors << "context must not be a symlink: #{pathname}" if stat.symlink?
      errors << "context must be a regular file: #{pathname}" unless stat.file?
    rescue Errno::ENOENT, Errno::EACCES => e
      raise ContractError, ["context is not a readable regular file: #{pathname} (#{e.class})"]
    end

    loaded_path, document = load_structured(pathname)
    probe_mode = document["probe_mode"].to_s
    errors << "#{pathname}.probe_mode must be one of #{PROBE_MODES.join(', ')}" unless PROBE_MODES.include?(probe_mode)
    expected_context_fields = probe_mode == SECTION_AUTHORING_MODE ? AUTHORING_CONTEXT_FIELDS : CHILD_CONTEXT_FIELDS
    expected_schema = probe_mode == SECTION_AUTHORING_MODE ? AUTHORING_CONTEXT_SCHEMA_VERSION : CHILD_CONTEXT_SCHEMA_VERSION
    errors.concat(exact_keys_errors(document, expected_context_fields, pathname.to_s))
    errors << "#{pathname}.schema_version must be #{expected_schema}" unless document["schema_version"] == expected_schema
    errors << "#{pathname}.status must be #{NONCANONICAL_STATUS}" unless document["status"] == NONCANONICAL_STATUS
    errors << "#{pathname}.harness_commit does not match the allowlist" unless document["harness_commit"].to_s == allowlist["harness_commit"]
    errors << "#{pathname}.section_id must be #{expected_section_id}" unless document["section_id"].to_s == expected_section_id
    errors << "#{pathname}.section_order must be #{expected_order}" unless document["section_order"] == expected_order
    errors << "#{pathname}.time_range is required" unless nonempty_string?(document["time_range"])
    errors << "#{pathname}.previous_boundary is required" unless nonempty_string?(document["previous_boundary"])
    errors << "#{pathname}.next_boundary is required" unless nonempty_string?(document["next_boundary"])
    errors << "#{pathname}.model_route must be gpt-5.6-sol/xhigh/high" unless document["model_route"] == MODEL_ROUTE
    errors << "#{pathname}.source_set_sha256 does not match the allowlist" unless document["source_set_sha256"].to_s == allowlist["source_set_sha256"]

    supplied_context_digest = document["section_context_sha256"].to_s
    errors << "#{pathname}.section_context_sha256 must be exactly 64 lowercase hexadecimal characters" unless supplied_context_digest.match?(SHA256_PATTERN)
    computed_context_digest = section_context_digest(document)
    unless supplied_context_digest == computed_context_digest
      errors << "#{pathname}.section_context_sha256 does not match compact JSON content"
    end

    section_plan = document["section_plan"]
    unless section_plan.is_a?(Hash)
      errors << "#{pathname}.section_plan must be an object"
      section_plan = {}
    end
    errors << "#{pathname}.section_plan.section_id must match the context section" unless section_plan["section_id"].to_s == expected_section_id
    errors << "#{pathname}.section_plan.time_range must match the context time_range" unless section_plan["time_range"].to_s == document["time_range"].to_s

    global_sources_by_path = allowlist["sources"].to_h { |source| [source["path"], source] }
    required_parent_cuts = []
    allowed_sources = []
    context_source_paths = []
    upstream_lock_ids = []
    split_obligation_ids = []

    if probe_mode == CHILD_KEYFRAME_MODE
      required_parent_cuts = document["required_parent_cuts"]
      unless required_parent_cuts.is_a?(Array) && required_parent_cuts.any?
        errors << "#{pathname}.required_parent_cuts must be a non-empty array"
        required_parent_cuts = []
      end
      required_ids = []
      required_parent_cuts.each_with_index do |row, index|
        label = "#{pathname}.required_parent_cuts[#{index}]"
        unless row.is_a?(Hash)
          errors << "#{label} must be an object"
          next
        end
        required_id = row["required_cut_id"].to_s
        errors << "#{label}.required_cut_id must match C<3+ digits>_<UPPERCASE_SUFFIX>" unless required_id.match?(CUT_ID_PATTERN)
        errors << "#{label}.source_parent_cut must be an object" unless row["source_parent_cut"].is_a?(Hash)
        required_ids << required_id unless required_id.empty?
      end
      duplicate_required_ids = duplicate_values(required_ids)
      errors << "#{pathname}.required_parent_cuts contains duplicate ids: #{duplicate_required_ids.join(', ')}" unless duplicate_required_ids.empty?

      allowed_sources = document["allowed_sources"]
      unless allowed_sources.is_a?(Array) && allowed_sources.any?
        errors << "#{pathname}.allowed_sources must be a non-empty array"
        allowed_sources = []
      end
      allowed_sources.each_with_index do |source, index|
        label = "#{pathname}.allowed_sources[#{index}]"
        unless source.is_a?(Hash)
          errors << "#{label} must be an object"
          next
        end
        source_path = source["path"].to_s
        global_source = global_sources_by_path[source_path]
        errors << "#{label} is outside the global allowlist: #{source_path}" unless global_source
        errors << "#{label} must exactly equal its global allowlist row" if global_source && source != global_source
        context_source_paths << source_path unless source_path.empty?
      end
    else
      forbidden = %w[required_parent_cuts required_cut_id source_parent_cut storyboard_core_cuts keyframe_shots cut_id]
      recursive_forbidden_keys(document, forbidden, pathname.to_s, errors)

      envelope = document["root_locked_envelope"]
      envelope_fields = %w[lock_id harness_commit section_id section_order time_range model_route source_set_sha256]
      errors.concat(exact_keys_errors(envelope, envelope_fields, "#{pathname}.root_locked_envelope"))
      if envelope.is_a?(Hash)
        errors << "#{pathname}.root_locked_envelope.lock_id is required" unless nonempty_string?(envelope["lock_id"])
        errors << "#{pathname}.root_locked_envelope does not match the root context envelope" unless envelope.reject { |key, _value| key == "lock_id" } == {
          "harness_commit" => document["harness_commit"],
          "section_id" => document["section_id"],
          "section_order" => document["section_order"],
          "time_range" => document["time_range"],
          "model_route" => document["model_route"],
          "source_set_sha256" => document["source_set_sha256"]
        }
        upstream_lock_ids << envelope["lock_id"].to_s if nonempty_string?(envelope["lock_id"])
      end
      errors << "#{pathname}.section_plan.lock_id is required" unless nonempty_string?(section_plan["lock_id"])
      upstream_lock_ids << section_plan["lock_id"].to_s if nonempty_string?(section_plan["lock_id"])
      upstream_lock_ids.concat(authoring_lock_ids(document["whole_film_locks"], "#{pathname}.whole_film_locks", errors))

      boundary_ids = authoring_lock_ids(
        document["boundary_locks"], "#{pathname}.boundary_locks", errors,
        required_fields: %w[lock_id boundary text]
      )
      boundary_rows = Array(document["boundary_locks"])
      errors << "#{pathname}.boundary_locks must contain previous and next exactly once" unless boundary_rows.map { |row| row["boundary"].to_s if row.is_a?(Hash) } == %w[previous next]
      if boundary_rows[0].is_a?(Hash)
        errors << "#{pathname}.boundary_locks previous text mismatch" unless boundary_rows[0]["text"].to_s == document["previous_boundary"].to_s
      end
      if boundary_rows[1].is_a?(Hash)
        errors << "#{pathname}.boundary_locks next text mismatch" unless boundary_rows[1]["text"].to_s == document["next_boundary"].to_s
      end
      upstream_lock_ids.concat(boundary_ids)

      source_locks = document["source_locks"]
      unless source_locks.is_a?(Array) && source_locks.any?
        errors << "#{pathname}.source_locks must be a non-empty array"
        source_locks = []
      end
      source_locks.each_with_index do |source_lock, index|
        label = "#{pathname}.source_locks[#{index}]"
        unless source_lock.is_a?(Hash)
          errors << "#{label} must be an object"
          next
        end

        source_path = source_lock["source_path"].to_s
        global_source = global_sources_by_path[source_path]
        source_lock_fields = ["lock_id", "source_path"] + (global_source ? global_source.keys.reject { |key| key == "path" } : (ALLOWLIST_SOURCE_FIELDS - ["path"]))
        errors.concat(exact_keys_errors(source_lock, source_lock_fields, label))
        errors << "#{label}.lock_id is required" unless nonempty_string?(source_lock["lock_id"])
        errors << "#{label}.source_path is outside the global allowlist: #{source_path}" unless global_source
        expected_lock = global_source && global_source.merge("lock_id" => source_lock["lock_id"], "source_path" => source_path).reject { |key, _value| key == "path" }
        errors << "#{label} must exactly preserve its global allowlist row" if expected_lock && source_lock != expected_lock
        upstream_lock_ids << source_lock["lock_id"].to_s if nonempty_string?(source_lock["lock_id"])
        context_source_paths << source_path unless source_path.empty?
        allowed_sources << deep_copy(global_source) if global_source
      end

      obligations = document["split_obligations"]
      unless obligations.is_a?(Array) && obligations.any?
        errors << "#{pathname}.split_obligations must be a non-empty array"
        obligations = []
      end
      obligations.each_with_index do |row, index|
        label = "#{pathname}.split_obligations[#{index}]"
        errors.concat(exact_keys_errors(row, %w[obligation_id requirement], label))
        next unless row.is_a?(Hash)

        errors << "#{label}.obligation_id is required" unless nonempty_string?(row["obligation_id"])
        errors << "#{label}.requirement is required" unless nonempty_string?(row["requirement"])
        split_obligation_ids << row["obligation_id"].to_s if nonempty_string?(row["obligation_id"])
      end
      duplicate_upstream_ids = duplicate_values(upstream_lock_ids)
      duplicate_obligation_ids = duplicate_values(split_obligation_ids)
      errors << "#{pathname} contains duplicate upstream lock ids: #{duplicate_upstream_ids.join(', ')}" unless duplicate_upstream_ids.empty?
      errors << "#{pathname}.split_obligations contains duplicate obligation_id values: #{duplicate_obligation_ids.join(', ')}" unless duplicate_obligation_ids.empty?
    end
    duplicate_context_sources = duplicate_values(context_source_paths)
    errors << "#{pathname} contains duplicate source locks/admissions: #{duplicate_context_sources.join(', ')}" unless duplicate_context_sources.empty?
    raise ContractError, errors unless errors.empty?

    {
      "path" => loaded_path.to_s,
      "file_sha256" => Digest::SHA256.file(loaded_path.to_s).hexdigest,
      "probe_mode" => probe_mode,
      "section_context_sha256" => computed_context_digest,
      "harness_commit" => document["harness_commit"].to_s,
      "section_id" => expected_section_id,
      "section_order" => expected_order,
      "time_range" => document["time_range"],
      "previous_boundary" => document["previous_boundary"],
      "next_boundary" => document["next_boundary"],
      "section_plan" => deep_copy(section_plan),
      "required_parent_cuts" => deep_copy(required_parent_cuts),
      "allowed_sources" => deep_copy(allowed_sources),
      "allowed_source_paths" => context_source_paths,
      "upstream_lock_ids" => upstream_lock_ids,
      "split_obligation_ids" => split_obligation_ids,
      "document" => document
    }
  end

  def validate_contexts(paths, allowlist, expected_sections)
    errors = []
    loaded = []
    Array(paths).each do |path|
      begin
        _pathname, document = load_structured(path)
        loaded << [path, document["section_id"].to_s, document["probe_mode"].to_s]
      rescue ContractError => e
        errors.concat(e.errors)
      end
    end
    by_section = loaded.group_by { |_path, section_id, _probe_mode| section_id }
    missing = expected_sections.reject { |section_id| by_section.fetch(section_id, []).length == 1 }
    duplicate = expected_sections.select { |section_id| by_section.fetch(section_id, []).length > 1 }
    extra = by_section.keys - expected_sections
    errors << "missing expected section contexts: #{missing.join(', ')}" unless missing.empty?
    errors << "duplicate section contexts: #{duplicate.join(', ')}" unless duplicate.empty?
    errors << "unexpected section contexts: #{extra.join(', ')}" unless extra.empty?
    errors << "exactly #{expected_sections.length} --context paths are required" unless loaded.length == expected_sections.length
    modes = loaded.map { |_path, _section_id, probe_mode| probe_mode }.uniq
    errors << "mixed probe_mode contexts are forbidden: #{modes.join(', ')}" if modes.length > 1
    raise ContractError, errors unless errors.empty?

    expected_sections.map do |section_id|
      path = by_section.fetch(section_id).first.first
      validate_context_file(
        path,
        allowlist,
        expected_section_id: section_id,
        expected_order: absolute_section_order(allowlist, section_id)
      )
    end
  end

  def nonempty_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end

  def exact_keys_errors(value, expected, label)
    return ["#{label} must be an object"] unless value.is_a?(Hash)

    keys = value.keys.map(&:to_s)
    missing = expected - keys
    extra = keys - expected
    errors = []
    errors << "#{label} is missing fields: #{missing.join(', ')}" unless missing.empty?
    errors << "#{label} contains unsupported fields: #{extra.join(', ')}" unless extra.empty?
    errors
  end

  def recursive_source_paths(value, label, errors, result = [])
    case value
    when Hash
      value.each do |key, item|
        child_label = "#{label}.#{key}"
        if key.to_s == "source_path"
          if nonempty_string?(item)
            result << item
          else
            errors << "#{child_label} must be a non-empty string"
          end
        else
          recursive_source_paths(item, child_label, errors, result)
        end
      end
    when Array
      value.each_with_index { |item, index| recursive_source_paths(item, "#{label}[#{index}]", errors, result) }
    end
    result
  end

  def validate_identity_compile_input(value, label, visible_member_focus = nil)
    errors = exact_keys_errors(value, IDENTITY_FIELDS, label)
    return errors unless value.is_a?(Hash)

    face_visible = value["face_visible"]
    errors << "#{label}.face_visible must be boolean" unless [true, false].include?(face_visible)
    errors << "#{label}.face_visibility_reason is required" unless nonempty_string?(value["face_visibility_reason"])

    members = value["identity_focus_members"]
    unless members.is_a?(Array)
      errors << "#{label}.identity_focus_members must be an array"
      members = []
    end
    errors << "#{label}.identity_focus_members may contain at most two members" if members.length > 2
    errors << "#{label}.identity_focus_members must be unique" unless members.uniq.length == members.length
    invalid_members = members.reject { |member| member.is_a?(String) && member.match?(MEMBER_ID_PATTERN) }
    errors << "#{label}.identity_focus_members contains invalid member ids: #{invalid_members.map(&:to_s).join(', ')}" unless invalid_members.empty?

    source = value["identity_reference_source"].to_s
    errors << "#{label}.identity_reference_source is invalid" unless %w[member_registry_face_only none].include?(source)
    errors << "#{label}.scene_reference_mode must be text_locks_only for direct 02B inheritance" unless value["scene_reference_mode"].to_s == "text_locks_only"

    if face_visible == true
      errors << "#{label} visible face requires one or two identity_focus_members" unless members.length.between?(1, 2)
      errors << "#{label} visible face requires identity_reference_source member_registry_face_only" unless source == "member_registry_face_only"
    elsif face_visible == false
      errors << "#{label} no-face shot must not list identity_focus_members" unless members.empty?
      errors << "#{label} no-face shot requires identity_reference_source none" unless source == "none"
    end

    if visible_member_focus.is_a?(Array)
      disallowed = members - visible_member_focus
      errors << "#{label} identity members are outside visible_member_focus: #{disallowed.join(', ')}" unless disallowed.empty?
    end
    errors
  end

  def validate_visible_member_focus(value, label)
    return [] if value.nil?
    return ["#{label} must be an array"] unless value.is_a?(Array)

    errors = []
    errors << "#{label} must be unique" unless value.uniq.length == value.length
    invalid = value.reject { |member| member.is_a?(String) && member.match?(MEMBER_ID_PATTERN) }
    errors << "#{label} contains invalid member ids: #{invalid.map(&:to_s).join(', ')}" unless invalid.empty?
    errors
  end

  def validate_cut(cut, label, allowed_source_paths, probe_mode: CHILD_KEYFRAME_MODE)
    errors = []
    unless cut.is_a?(Hash)
      return {errors: ["#{label} must be an object"], cut_id: "", shots: [], source_paths: []}
    end

    cut_id = cut["cut_id"].to_s
    errors << "#{label}.cut_id must match C<3+ digits>_<UPPERCASE_SUFFIX>" unless cut_id.match?(CUT_ID_PATTERN)
    CUT_REQUIRED_TEXT_FIELDS.each do |field|
      errors << "#{label}.#{field} is required" unless nonempty_string?(cut[field])
    end

    camera = cut["camera"]
    errors.concat(exact_keys_errors(camera, CAMERA_FIELDS, "#{label}.camera"))
    if camera.is_a?(Hash)
      CAMERA_FIELDS.each do |field|
        errors << "#{label}.camera.#{field} is required" unless nonempty_string?(camera[field])
      end
    end

    reference_uses = cut["reference_uses"]
    unless reference_uses.is_a?(Array)
      errors << "#{label}.reference_uses must be an array"
      reference_uses = []
    end
    reference_uses.each_with_index do |reference, index|
      reference_label = "#{label}.reference_uses[#{index}]"
      unless reference.is_a?(Hash)
        errors << "#{reference_label} must be an object"
        next
      end
      source_path = reference["source_path"]
      errors << "#{reference_label}.source_path is required" unless nonempty_string?(source_path)
      if nonempty_string?(source_path) && !allowed_source_paths.include?(source_path)
        errors << "#{reference_label}.source_path is outside the allowlist: #{source_path}"
      end
    end

    if probe_mode == SECTION_AUTHORING_MODE
      %w[upstream_lock_refs split_obligation_refs].each do |field|
        refs = cut[field]
        unless refs.is_a?(Array)
          errors << "#{label}.#{field} must be an array"
          next
        end
        errors << "#{label}.#{field} must contain only non-empty strings" unless refs.all? { |ref| nonempty_string?(ref) }
        duplicates = duplicate_values(refs)
        errors << "#{label}.#{field} contains duplicate refs: #{duplicates.join(', ')}" unless duplicates.empty?
      end
    end

    shots = cut["keyframe_shots"]
    unless shots.is_a?(Array) && shots.any?
      errors << "#{label}.keyframe_shots must be a non-empty array"
      shots = []
    end

    sequences = []
    shots.each_with_index do |shot, index|
      shot_label = "#{label}.keyframe_shots[#{index}]"
      errors.concat(Idol02AStoryboardContract.keyframe_shot_lock_errors(shot_label, shot))
      next unless shot.is_a?(Hash)

      sequences << shot["shot_sequence"] if shot["shot_sequence"].is_a?(Integer)
      errors << "#{shot_label}.visible_member_focus is required for direct 02B member authorization proof" unless shot.key?("visible_member_focus")
      errors.concat(validate_visible_member_focus(shot["visible_member_focus"], "#{shot_label}.visible_member_focus"))
      unless shot.key?("identity_compile_input")
        errors << "#{shot_label}.identity_compile_input is required for direct 02B identity inheritance proof"
        next
      end
      errors.concat(
        validate_identity_compile_input(
          shot["identity_compile_input"],
          "#{shot_label}.identity_compile_input",
          shot["visible_member_focus"]
        )
      )
    end

    duplicate_sequences = duplicate_values(sequences)
    errors << "#{label}.keyframe_shots contains duplicate shot_sequence values: #{duplicate_sequences.join(', ')}" unless duplicate_sequences.empty?
    unless sequences.each_cons(2).all? { |left, right| left < right }
      errors << "#{label}.keyframe_shots shot_sequence values must be strictly ascending in array order"
    end

    keyframe_ids = shots.map { |shot| shot["keyframe_shot_id"].to_s if shot.is_a?(Hash) }.compact
    packet_ids = shots.map { |shot| shot["packet_id"].to_s if shot.is_a?(Hash) }.compact
    duplicate_keyframes = duplicate_values(keyframe_ids.reject(&:empty?))
    duplicate_packets = duplicate_values(packet_ids.reject(&:empty?))
    errors << "#{label}.keyframe_shots contains duplicate keyframe_shot_id values: #{duplicate_keyframes.join(', ')}" unless duplicate_keyframes.empty?
    errors << "#{label}.keyframe_shots contains duplicate packet_id values: #{duplicate_packets.join(', ')}" unless duplicate_packets.empty?

    source_errors = []
    all_source_paths = recursive_source_paths(cut, label, source_errors)
    errors.concat(source_errors)
    unknown = all_source_paths.uniq - allowed_source_paths
    errors << "#{label} contains source paths outside the allowlist: #{unknown.join(', ')}" unless unknown.empty?

    {
      errors: errors,
      cut_id: cut_id,
      shots: shots,
      keyframe_ids: keyframe_ids,
      packet_ids: packet_ids,
      source_paths: all_source_paths
    }
  end

  def numeric_time_range(value)
    match = value.to_s.match(/\A\s*(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)\s*\z/)
    return nil unless match

    range_start = Float(match[1])
    range_end = Float(match[2])
    return nil unless range_start < range_end

    [range_start, range_end]
  end

  def exact_cover_errors(cuts, field, expected_ids, label)
    refs = cuts.flat_map { |cut| cut.is_a?(Hash) && cut[field].is_a?(Array) ? cut[field] : [] }
    missing = expected_ids - refs
    unknown = refs - expected_ids
    duplicates = duplicate_values(refs)
    errors = []
    errors << "#{label}.#{field} is missing required refs: #{missing.join(', ')}" unless missing.empty?
    errors << "#{label}.#{field} contains unknown refs: #{unknown.join(', ')}" unless unknown.empty?
    errors << "#{label}.#{field} must cover every id exactly once; duplicate refs: #{duplicates.join(', ')}" unless duplicates.empty?
    errors
  end

  def validate_authoring_section(section, context, label, require_known_continuity: false)
    errors = []
    unless section.is_a?(Hash)
      return {errors: ["#{label}.section must be an object"], cuts: [], cut_ids: [], keyframe_ids: [], packet_ids: [], shots: [], source_paths: []}
    end

    errors << "#{label}.section.section_id conflicts with the context" unless section["section_id"].to_s == context["section_id"]
    errors << "#{label}.section.time_range conflicts with the context" unless section["time_range"].to_s == context["time_range"].to_s
    cuts = section["storyboard_core_cuts"]
    unless cuts.is_a?(Array) && cuts.any?
      errors << "#{label}.section.storyboard_core_cuts must be a non-empty array"
      cuts = []
    end
    cut_results = cuts.each_with_index.map do |cut, index|
      validate_cut(
        cut,
        "#{label}.section.storyboard_core_cuts[#{index}]",
        context["allowed_source_paths"],
        probe_mode: SECTION_AUTHORING_MODE
      )
    end
    cut_results.each { |result| errors.concat(result[:errors]) }
    cut_ids = cut_results.map { |result| result[:cut_id] }.reject(&:empty?)
    duplicate_cuts = duplicate_values(cut_ids)
    errors << "#{label} contains duplicate cut ids: #{duplicate_cuts.join(', ')}" unless duplicate_cuts.empty?

    section_range = numeric_time_range(context["time_range"])
    errors << "#{label} context section time_range is not a valid increasing numeric range" unless section_range
    cuts.each_with_index do |cut, index|
      next unless cut.is_a?(Hash)

      cut_range = numeric_time_range(cut["time_range"])
      if cut_range.nil?
        errors << "#{label}.section.storyboard_core_cuts[#{index}].time_range must be a valid increasing numeric range"
      elsif section_range && (cut_range[0] < section_range[0] || cut_range[1] > section_range[1])
        errors << "#{label}.section.storyboard_core_cuts[#{index}].time_range falls outside the section time bounds"
      end
    end

    actual_cut_count = cuts.length
    actual_keyframe_count = cut_results.sum { |result| result[:shots].length }
    quality_check = section["section_quality_check"]
    if quality_check.is_a?(Hash)
      errors << "#{label}.section.section_quality_check.actual_core_cut_count contradicts the storyboard array" if quality_check.key?("actual_core_cut_count") && quality_check["actual_core_cut_count"] != actual_cut_count
      errors << "#{label}.section.section_quality_check.actual_keyframe_count contradicts the keyframe arrays" if quality_check.key?("actual_keyframe_count") && quality_check["actual_keyframe_count"] != actual_keyframe_count
    end
    expected_plan = deep_copy(context["section_plan"])
    if expected_plan["section_quality_check"].is_a?(Hash)
      expected_plan["section_quality_check"]["actual_core_cut_count"] = actual_cut_count
      expected_plan["section_quality_check"]["actual_keyframe_count"] = actual_keyframe_count
    end
    actual_plan = section.reject { |key, _value| key == "storyboard_core_cuts" }
    errors << "#{label}.section must preserve the root-locked section_plan outside derived counts" unless actual_plan == expected_plan

    errors.concat(exact_cover_errors(cuts, "upstream_lock_refs", context["upstream_lock_ids"], "#{label}.section.storyboard_core_cuts"))
    errors.concat(exact_cover_errors(cuts, "split_obligation_refs", context["split_obligation_ids"], "#{label}.section.storyboard_core_cuts"))

    source_errors = []
    source_paths = recursive_source_paths(section, "#{label}.section", source_errors)
    errors.concat(source_errors)
    unknown_sources = source_paths.uniq - context["allowed_source_paths"]
    errors << "#{label}.section contains source paths outside the bounded context source locks: #{unknown_sources.join(', ')}" unless unknown_sources.empty?

    collective = [{
      cut_ids: cut_ids,
      keyframe_ids: cut_results.flat_map { |result| result[:keyframe_ids] }.reject(&:empty?),
      packet_ids: cut_results.flat_map { |result| result[:packet_ids] }.reject(&:empty?),
      shots: cut_results.flat_map { |result| result[:shots] }
    }]
    errors.concat(validate_collective(collective, require_known_continuity: require_known_continuity))
    {
      errors: errors,
      cuts: cuts,
      cut_ids: cut_ids,
      keyframe_ids: collective.first[:keyframe_ids],
      packet_ids: collective.first[:packet_ids],
      shots: collective.first[:shots],
      source_paths: source_paths
    }
  end

  def validate_authoring_raw_shard_for_normalization(document, allowlist, context:, label:)
    errors = exact_keys_errors(document, AUTHORING_RAW_SHARD_FIELDS, label)
    return {errors: errors, cuts: [], keyframe_ids: [], packet_ids: [], shots: []} unless document.is_a?(Hash)

    errors << "#{label}.schema_version must be #{SHARD_SCHEMA_VERSION}" unless document["schema_version"] == SHARD_SCHEMA_VERSION
    errors << "#{label}.status must be #{NONCANONICAL_STATUS}" unless document["status"] == NONCANONICAL_STATUS
    errors << "#{label}.probe_mode must match the bounded section context" unless document["probe_mode"].to_s == context["probe_mode"]
    errors << "#{label}.probe_mode must be #{SECTION_AUTHORING_MODE}" unless document["probe_mode"] == SECTION_AUTHORING_MODE
    errors << "#{label}.harness_commit does not match the allowlist/context" unless document["harness_commit"].to_s == allowlist["harness_commit"] && document["harness_commit"].to_s == context["harness_commit"]
    errors << "#{label}.section_id does not match context" unless document["section_id"].to_s == context["section_id"]
    errors << "#{label}.section_order does not match context" unless document["section_order"] == context["section_order"]
    errors << "#{label}.time_range does not match context" unless document["time_range"].to_s == context["time_range"].to_s
    errors << "#{label}.model_route must be gpt-5.6-sol/xhigh/high" unless document["model_route"] == MODEL_ROUTE
    errors << "#{label}.source_set_sha256 does not match allowlist/context" unless document["source_set_sha256"].to_s == allowlist["source_set_sha256"]
    errors << "#{label}.section_context_sha256 does not match context" unless document["section_context_sha256"].to_s == context["section_context_sha256"]
    errors << "#{label}.previous_boundary does not match context" unless document["previous_boundary"].to_s == context["previous_boundary"].to_s
    errors << "#{label}.next_boundary does not match context" unless document["next_boundary"].to_s == context["next_boundary"].to_s

    section_result = validate_authoring_section(document["section"], context, label, require_known_continuity: false)
    errors.concat(section_result[:errors])
    section_result.merge(errors: errors)
  end

  def validate_raw_shard_for_normalization(document, allowlist, context:, label:)
    if context["probe_mode"] == SECTION_AUTHORING_MODE
      return validate_authoring_raw_shard_for_normalization(document, allowlist, context: context, label: label)
    end

    errors = []
    unless document.is_a?(Hash)
      return {errors: ["#{label} must be an object"], cuts: [], keyframe_ids: [], packet_ids: []}
    end

    errors << "#{label}.schema_version must be #{SHARD_SCHEMA_VERSION}" unless document["schema_version"] == SHARD_SCHEMA_VERSION
    errors << "#{label}.status must be #{NONCANONICAL_STATUS}" unless document["status"] == NONCANONICAL_STATUS
    errors << "#{label}.probe_mode must be #{CHILD_KEYFRAME_MODE}" unless document["probe_mode"] == CHILD_KEYFRAME_MODE
    if document.key?("harness_commit")
      errors << "#{label}.harness_commit does not match the allowlist/context" unless document["harness_commit"].to_s == allowlist["harness_commit"] && document["harness_commit"].to_s == context["harness_commit"]
    end
    errors << "#{label}.section_id does not match context" unless document["section_id"].to_s == context["section_id"]
    errors << "#{label}.section_order does not match context" unless document["section_order"] == context["section_order"]
    errors << "#{label}.time_range does not match context" unless document["time_range"].to_s == context["time_range"].to_s
    errors << "#{label}.model_route must be gpt-5.6-sol/xhigh/high" unless document["model_route"] == MODEL_ROUTE
    errors << "#{label}.source_set_sha256 does not match allowlist/context" unless document["source_set_sha256"].to_s == allowlist["source_set_sha256"]
    errors << "#{label}.section_context_sha256 does not match context" unless document["section_context_sha256"].to_s == context["section_context_sha256"]
    errors << "#{label}.previous_boundary does not match context" unless document["previous_boundary"].to_s == context["previous_boundary"].to_s
    errors << "#{label}.next_boundary does not match context" unless document["next_boundary"].to_s == context["next_boundary"].to_s

    section = document["section"]
    unless section.is_a?(Hash)
      errors << "#{label}.section must be an object"
      section = {}
    end
    cuts = section["storyboard_core_cuts"]
    unless cuts.is_a?(Array) && cuts.any?
      errors << "#{label}.section.storyboard_core_cuts must be a non-empty array"
      cuts = []
    end
    required_rows = context["required_parent_cuts"]
    required_ids = required_rows.map { |row| row["required_cut_id"].to_s }
    actual_ids = cuts.map { |cut| cut.is_a?(Hash) ? cut["cut_id"].to_s : "" }
    unless actual_ids == required_ids
      errors << "#{label}.section.storyboard_core_cuts must exactly cover context required_cut_id values in order; expected #{required_ids.join(', ')}, got #{actual_ids.join(', ')}"
    end

    synthetic_results = cuts.each_with_index.map do |raw_cut, index|
      unless raw_cut.is_a?(Hash) && required_rows[index].is_a?(Hash)
        next({errors: ["#{label}.section.storyboard_core_cuts[#{index}] must be an object"], cut_id: "", keyframe_ids: [], packet_ids: [], shots: []})
      end
      shots = raw_cut["keyframe_shots"]
      expected_parent = deep_copy(required_rows[index]["source_parent_cut"])
      unless expected_parent.is_a?(Hash)
        next({errors: ["#{label}: context parent cut #{index} must be an object"], cut_id: "", keyframe_ids: [], packet_ids: [], shots: []})
      end
      expected_parent["cut_id"] = required_rows[index]["required_cut_id"]
      expected_parent["keyframe_shots"] = deep_copy(shots)
      validate_cut(
        expected_parent,
        "#{label}.section.storyboard_core_cuts[#{index}]",
        context["allowed_source_paths"]
      )
    end
    synthetic_results.each { |result| errors.concat(result[:errors]) }
    collective = [{
      cut_ids: actual_ids.reject(&:empty?),
      keyframe_ids: synthetic_results.flat_map { |result| result[:keyframe_ids] }.reject(&:empty?),
      packet_ids: synthetic_results.flat_map { |result| result[:packet_ids] }.reject(&:empty?),
      shots: synthetic_results.flat_map { |result| result[:shots] }
    }]
    # A section worker may name an exact adjacent-section KS_* id supplied by
    # the bounded boundary contract. Its existence can only be proven after all
    # normalized shards are assembled, so normalization rejects malformed id
    # families and local duplicates but defers unknown-id resolution to merge.
    errors.concat(validate_collective(collective, require_known_continuity: false))
    {
      errors: errors,
      cuts: cuts,
      cut_ids: actual_ids,
      keyframe_ids: collective.first[:keyframe_ids],
      packet_ids: collective.first[:packet_ids],
      shots: collective.first[:shots]
    }
  end

  def keyframe_arrays_digest(document)
    cuts = Array(document.dig("section", "storyboard_core_cuts"))
    material = cuts.map do |cut|
      [cut.is_a?(Hash) ? cut["cut_id"].to_s : "", cut.is_a?(Hash) ? deep_copy(cut["keyframe_shots"]) : nil]
    end
    Digest::SHA256.hexdigest(JSON.generate(material))
  end

  def collapse_exact_duplicate_cuts(document)
    collapsed = deep_copy(document)
    cuts = Array(collapsed.dig("section", "storyboard_core_cuts"))
    seen = {}
    kept = []
    removals = []
    cuts.each_with_index do |cut, index|
      cut_id = cut.is_a?(Hash) ? cut["cut_id"].to_s : ""
      prior = seen[cut_id]
      if !cut_id.empty? && prior && cut == prior[:cut]
        removals << {
          "cut_id" => cut_id,
          "removed_raw_index" => index,
          "removed_raw_path" => "section.storyboard_core_cuts[#{index}]",
          "exact_duplicate_of" => "section.storyboard_core_cuts[#{prior[:index]}]"
        }
        next
      end
      seen[cut_id] ||= {cut: deep_copy(cut), index: index} unless cut_id.empty?
      kept << cut
    end
    collapsed["section"]["storyboard_core_cuts"] = kept if collapsed["section"].is_a?(Hash)
    [collapsed, removals]
  end

  def load_execution_turns(execution_log_path)
    pathname = Pathname.new(execution_log_path.to_s).expand_path.cleanpath
    begin
      stat = File.lstat(pathname.to_s)
      raise ContractError, ["execution log must be a regular non-symlink file: #{pathname}"] if stat.symlink? || !stat.file?
    rescue Errno::ENOENT, Errno::EACCES => e
      raise ContractError, ["execution log is not a readable regular file: #{pathname} (#{e.class})"]
    end

    turns = []
    current = nil
    File.foreach(pathname, encoding: Encoding::UTF_8).with_index(1) do |line, line_number|
      next if line.strip.empty?

      begin
        row = stringify_keys(JSON.parse(line))
      rescue JSON::ParserError => e
        raise ContractError, ["execution log line #{line_number} is not valid JSON: #{pathname} (#{e.message})"]
      end
      unless row.is_a?(Hash)
        raise ContractError, ["execution log line #{line_number} must be a JSON object: #{pathname}"]
      end

      if row["type"] == "turn_context"
        payload = row["payload"]
        unless payload.is_a?(Hash)
          raise ContractError, ["execution log turn_context line #{line_number} has no object payload: #{pathname}"]
        end
        current = {
          turn_context: payload,
          user_messages: [],
          agent_messages: [],
          task_complete: false
        }
        turns << current
        next
      end
      next unless current && row["type"] == "event_msg" && row["payload"].is_a?(Hash)

      payload = row["payload"]
      case payload["type"]
      when "user_message"
        current[:user_messages] << payload["message"].to_s
      when "agent_message"
        current[:agent_messages] << payload
      when "task_complete"
        current[:task_complete] = payload["turn_id"].to_s == current.dig(:turn_context, "turn_id").to_s
      end
    end
    [pathname, turns]
  rescue ArgumentError => e
    raise ContractError, ["execution log is not valid UTF-8: #{pathname} (#{e.message})"]
  end

  def compact_execution_attestation(raw_path, raw_document, context)
    raw_pathname = Pathname.new(raw_path.to_s).expand_path.cleanpath
    cuts = Array(raw_document.dig("section", "storyboard_core_cuts"))
    {
      "schema_version" => COMPACT_EXECUTION_ATTESTATION_SCHEMA_VERSION,
      "status" => NONCANONICAL_STATUS,
      "receipt_mode" => "compact_hash_attestation",
      "probe_mode" => context["probe_mode"],
      "context_path" => context["path"],
      "raw_path" => raw_pathname.to_s,
      "raw_sha256" => Digest::SHA256.file(raw_pathname.to_s).hexdigest,
      "raw_output_semantic_sha256" => semantic_digest(raw_document),
      "keyframe_shots_sha256" => keyframe_arrays_digest(raw_document),
      "creative_section_semantic_sha256" => semantic_digest(raw_document["section"]),
      "section_id" => context["section_id"],
      "actual_core_cut_count" => cuts.length,
      "actual_keyframe_count" => cuts.sum { |cut| Array(cut["keyframe_shots"]).length }
    }
  end

  def matching_completed_execution_turn(turns, raw_path, raw_document, context)
    raw_pathname = Pathname.new(raw_path.to_s).expand_path.cleanpath.to_s
    expected_compact = context["probe_mode"] == SECTION_AUTHORING_MODE ? compact_execution_attestation(raw_pathname, raw_document, context) : nil
    matches = turns.each_with_object([]) do |turn, result|
      next unless turn[:task_complete]
      next unless turn[:user_messages].any? { |message| message.include?(context["path"].to_s) }

      final_message = turn[:agent_messages].last
      next unless final_message.is_a?(Hash) && final_message["phase"] == "final_answer"

      begin
        parsed = stringify_keys(JSON.parse(final_message["message"].to_s))
        if parsed == raw_document
          result << [turn, "full_final_json"]
        elsif expected_compact &&
              turn[:user_messages].any? { |message| message.include?(raw_pathname) } &&
              parsed.is_a?(Hash) &&
              exact_keys_errors(parsed, COMPACT_EXECUTION_ATTESTATION_FIELDS, "compact execution attestation").empty? &&
              parsed == expected_compact
          result << [turn, "compact_hash_attestation"]
        end
      rescue JSON::ParserError
        next
      end
    end
    matches.last
  end

  def build_execution_receipt(execution_log_path, raw_path, raw_document, context)
    pathname, turns = load_execution_turns(execution_log_path)
    match = matching_completed_execution_turn(turns, raw_path, raw_document, context)
    unless match
      raise ContractError, [
        "execution log has no completed turn whose user message names the exact context path and whose final evidence is either the full raw JSON or an exact compact hash attestation bound to the raw path: #{pathname}"
      ]
    end
    turn, evidence_mode = match

    actual_model = turn.dig(:turn_context, "model").to_s
    actual_effort = turn.dig(:turn_context, "effort").to_s
    expected_route = context.dig("document", "model_route")
    errors = []
    errors << "execution turn actual model #{actual_model.inspect} does not match context model #{expected_route['model'].inspect}" unless actual_model == expected_route["model"]
    errors << "execution turn actual effort #{actual_effort.inspect} does not match context effort #{expected_route['effort'].inspect}" unless actual_effort == expected_route["effort"]
    errors << "execution turn must use gpt-5.6-sol/xhigh" unless actual_model == MODEL_ROUTE["model"] && actual_effort == MODEL_ROUTE["effort"]
    raise ContractError, errors unless errors.empty?

    {
      "receipt_version" => "idol_storyboard_probe_execution.v2",
      "probe_mode" => context["probe_mode"],
      "evidence_mode" => evidence_mode,
      "execution_log_path" => pathname.to_s,
      "execution_log_sha256" => Digest::SHA256.file(pathname.to_s).hexdigest,
      "turn_id" => turn.dig(:turn_context, "turn_id").to_s,
      "actual_model" => actual_model,
      "actual_effort" => actual_effort,
      "context_path" => context["path"],
      "section_context_sha256" => context["section_context_sha256"],
      "raw_output_semantic_sha256" => semantic_digest(raw_document),
      "task_complete" => true
    }
  end

  def validate_execution_receipt(receipt, raw_path, raw_document, context, label)
    errors = exact_keys_errors(receipt, EXECUTION_RECEIPT_FIELDS, "#{label}.execution_receipt")
    return errors unless receipt.is_a?(Hash)

    begin
      expected = build_execution_receipt(receipt["execution_log_path"], raw_path, raw_document, context)
      errors << "#{label}.execution_receipt does not match current execution-log/raw/context evidence" unless receipt == expected
    rescue ContractError => e
      errors.concat(e.errors.map { |message| "#{label}.execution_receipt: #{message}" })
    end
    errors
  end

  def locked_projection(document)
    projection = deep_copy(document)
    projection.delete("deterministic_normalization_receipt")
    projection.delete("execution_receipt")
    Array(projection.dig("section", "storyboard_core_cuts")).each do |cut|
      cut.delete("keyframe_shots") if cut.is_a?(Hash)
    end
    projection
  end

  def authoring_envelope_projection(document)
    projection = deep_copy(document)
    projection.delete("deterministic_normalization_receipt")
    projection.delete("execution_receipt")
    projection.delete("section")
    projection
  end

  def changed_paths(left, right, path = "")
    return [] if left == right

    if left.is_a?(Hash) && right.is_a?(Hash)
      return (left.keys | right.keys).sort.flat_map do |key|
        child_path = path.empty? ? key.to_s : "#{path}.#{key}"
        changed_paths(left[key], right[key], child_path)
      end
    end
    if left.is_a?(Array) && right.is_a?(Array)
      paths = []
      paths << "#{path}.length" unless left.length == right.length
      [left.length, right.length].min.times do |index|
        paths.concat(changed_paths(left[index], right[index], "#{path}[#{index}]"))
      end
      return paths
    end
    [path]
  end

  def normalized_shard_base(raw_document, context)
    if context["probe_mode"] == SECTION_AUTHORING_MODE
      return {
        "schema_version" => SHARD_SCHEMA_VERSION,
        "status" => NONCANONICAL_STATUS,
        "probe_mode" => SECTION_AUTHORING_MODE,
        "harness_commit" => context["harness_commit"],
        "section_id" => context["section_id"],
        "section_order" => context["section_order"],
        "time_range" => context["time_range"],
        "model_route" => deep_copy(MODEL_ROUTE),
        "source_set_sha256" => context["document"]["source_set_sha256"],
        "section_context_sha256" => context["section_context_sha256"],
        "previous_boundary" => context["previous_boundary"],
        "next_boundary" => context["next_boundary"],
        "section" => deep_copy(raw_document["section"])
      }
    end

    normalized_cuts = context["required_parent_cuts"].each_with_index.map do |row, index|
      parent = deep_copy(row["source_parent_cut"])
      parent["cut_id"] = row["required_cut_id"]
      parent["keyframe_shots"] = deep_copy(raw_document.dig("section", "storyboard_core_cuts", index, "keyframe_shots"))
      parent
    end
    section = deep_copy(context["section_plan"])
    if section["section_quality_check"].is_a?(Hash)
      section["section_quality_check"]["actual_core_cut_count"] = normalized_cuts.length
      section["section_quality_check"]["actual_keyframe_count"] = normalized_cuts.sum { |cut| Array(cut["keyframe_shots"]).length }
    end
    section["storyboard_core_cuts"] = normalized_cuts
    {
      "schema_version" => SHARD_SCHEMA_VERSION,
      "status" => NONCANONICAL_STATUS,
      "probe_mode" => CHILD_KEYFRAME_MODE,
      "harness_commit" => context["harness_commit"],
      "section_id" => context["section_id"],
      "section_order" => context["section_order"],
      "time_range" => context["time_range"],
      "model_route" => deep_copy(MODEL_ROUTE),
      "source_set_sha256" => context["document"]["source_set_sha256"],
      "section_context_sha256" => context["section_context_sha256"],
      "previous_boundary" => context["previous_boundary"],
      "next_boundary" => context["next_boundary"],
      "section" => section
    }
  end

  def normalization_receipt(raw_path, raw_document, collapsed_document, context, normalized_base, removals)
    raw_pathname = Pathname.new(raw_path.to_s).expand_path.cleanpath
    left_projection = context["probe_mode"] == SECTION_AUTHORING_MODE ? authoring_envelope_projection(raw_document) : locked_projection(raw_document)
    right_projection = context["probe_mode"] == SECTION_AUTHORING_MODE ? authoring_envelope_projection(normalized_base) : locked_projection(normalized_base)
    repair_paths = changed_paths(left_projection, right_projection)
    repair_paths.concat(removals.map { |row| row["removed_raw_path"] })
    repair_paths = repair_paths.uniq.sort
    receipt = {
      "receipt_version" => "idol_storyboard_probe_deterministic_normalization.v1",
      "probe_mode" => context["probe_mode"],
      "raw_path" => raw_pathname.to_s,
      "raw_sha256" => Digest::SHA256.file(raw_pathname.to_s).hexdigest,
      "context_path" => context["path"],
      "context_file_sha256" => context["file_sha256"],
      "section_context_sha256" => context["section_context_sha256"],
      "harness_commit" => context["harness_commit"],
      "raw_keyframe_shots_sha256" => keyframe_arrays_digest(raw_document),
      "keyframe_shots_sha256" => keyframe_arrays_digest(collapsed_document),
      "collapsed_exact_duplicate_cuts" => deep_copy(removals),
      "repaired_locked_field_paths" => repair_paths,
      "repaired_locked_field_count" => repair_paths.length
    }
    if context["probe_mode"] == SECTION_AUTHORING_MODE
      receipt["raw_creative_section_semantic_sha256"] = semantic_digest(raw_document["section"])
      receipt["normalized_creative_section_semantic_sha256"] = semantic_digest(normalized_base["section"])
    end
    receipt
  end

  def build_normalized_shard(raw_path, allowlist, context, execution_log_path)
    pathname, raw_document = load_structured(raw_path)
    collapsed_document, removals = if context["probe_mode"] == SECTION_AUTHORING_MODE
                                     [deep_copy(raw_document), []]
                                   else
                                     collapse_exact_duplicate_cuts(raw_document)
                                   end
    raw_validation = validate_raw_shard_for_normalization(collapsed_document, allowlist, context: context, label: pathname.to_s)
    raise ContractError, raw_validation[:errors] unless raw_validation[:errors].empty?

    normalized = normalized_shard_base(collapsed_document, context)
    normalized["execution_receipt"] = build_execution_receipt(execution_log_path, pathname, raw_document, context)
    normalized["deterministic_normalization_receipt"] = normalization_receipt(
      pathname,
      raw_document,
      collapsed_document,
      context,
      normalized,
      removals
    )
    normalized
  end

  def validate_normalization_receipt(document, allowlist, context, label)
    receipt = document["deterministic_normalization_receipt"]
    execution_receipt = document["execution_receipt"]
    missing = []
    unless receipt.is_a?(Hash)
      missing << "#{label}.deterministic_normalization_receipt is required; run normalize-shard before merge"
    end
    unless execution_receipt.is_a?(Hash)
      missing << "#{label}.execution_receipt is required; raw self-reported model_route is not execution evidence"
    end
    return missing unless missing.empty?

    receipt_fields = context["probe_mode"] == SECTION_AUTHORING_MODE ? AUTHORING_NORMALIZATION_RECEIPT_FIELDS : NORMALIZATION_RECEIPT_FIELDS
    errors = exact_keys_errors(receipt, receipt_fields, "#{label}.deterministic_normalization_receipt")
    return errors unless receipt.is_a?(Hash)

    raw_path = Pathname.new(receipt["raw_path"].to_s).expand_path.cleanpath
    errors << "#{label}.deterministic_normalization_receipt.raw_path must be normalized absolute" unless raw_path.to_s == receipt["raw_path"].to_s
    begin
      stat = File.lstat(raw_path.to_s)
      errors << "#{label}.deterministic_normalization_receipt.raw_path must be a regular non-symlink file" if stat.symlink? || !stat.file?
    rescue Errno::ENOENT, Errno::EACCES
      errors << "#{label}.deterministic_normalization_receipt.raw_path is not readable"
      return errors
    end
    actual_raw_sha = Digest::SHA256.file(raw_path.to_s).hexdigest
    errors << "#{label}.deterministic_normalization_receipt.raw_sha256 is stale" unless receipt["raw_sha256"].to_s == actual_raw_sha
    errors << "#{label}.deterministic_normalization_receipt.context_path mismatch" unless receipt["context_path"].to_s == context["path"]
    errors << "#{label}.deterministic_normalization_receipt.context_file_sha256 mismatch" unless receipt["context_file_sha256"].to_s == context["file_sha256"]
    errors << "#{label}.deterministic_normalization_receipt.section_context_sha256 mismatch" unless receipt["section_context_sha256"].to_s == context["section_context_sha256"]
    errors << "#{label}.deterministic_normalization_receipt.harness_commit mismatch" unless receipt["harness_commit"].to_s == allowlist["harness_commit"]
    errors << "#{label}.deterministic_normalization_receipt.probe_mode mismatch" unless receipt["probe_mode"].to_s == context["probe_mode"]
    return errors unless errors.empty?

    _path, raw_document = load_structured(raw_path)
    execution_errors = validate_execution_receipt(document["execution_receipt"], raw_path, raw_document, context, label)
    errors.concat(execution_errors)
    return errors unless errors.empty?

    collapsed_document, removals = if context["probe_mode"] == SECTION_AUTHORING_MODE
                                     [deep_copy(raw_document), []]
                                   else
                                     collapse_exact_duplicate_cuts(raw_document)
                                   end
    raw_validation = validate_raw_shard_for_normalization(collapsed_document, allowlist, context: context, label: raw_path.to_s)
    errors.concat(raw_validation[:errors])
    return errors unless errors.empty?

    expected_base = normalized_shard_base(collapsed_document, context)
    expected_base["execution_receipt"] = build_execution_receipt(
      document.dig("execution_receipt", "execution_log_path"),
      raw_path,
      raw_document,
      context
    )
    expected_receipt = normalization_receipt(raw_path, raw_document, collapsed_document, context, expected_base, removals)
    errors << "#{label}.deterministic_normalization_receipt does not match raw/context evidence" unless receipt == expected_receipt
    expected_document = expected_base.merge("deterministic_normalization_receipt" => expected_receipt)
    errors << "#{label} is not the deterministic locked-source normalization of its raw shard" unless document == expected_document
    errors << "#{label}.deterministic_normalization_receipt keyframe digest changed" unless receipt["keyframe_shots_sha256"].to_s == keyframe_arrays_digest(document)
    if context["probe_mode"] == SECTION_AUTHORING_MODE
      raw_creative_digest = semantic_digest(raw_document["section"])
      normalized_creative_digest = semantic_digest(document["section"])
      errors << "#{label}.deterministic_normalization_receipt raw creative section digest mismatch" unless receipt["raw_creative_section_semantic_sha256"] == raw_creative_digest
      errors << "#{label}.deterministic_normalization_receipt normalized creative section digest mismatch" unless receipt["normalized_creative_section_semantic_sha256"] == normalized_creative_digest
      errors << "#{label} section_02a_authoring normalization mutated the Terra creative section payload" unless raw_creative_digest == normalized_creative_digest
    end
    errors
  rescue ContractError => e
    errors + e.errors
  end

  def validate_shard(document, allowlist, context:, expected_section_id:, expected_order:, label:)
    errors = []
    unless document.is_a?(Hash)
      return {errors: ["#{label} must be an object"], projection: {}, cuts: [], source_paths: []}
    end

    errors << "#{label}.schema_version must be #{SHARD_SCHEMA_VERSION}" unless document["schema_version"] == SHARD_SCHEMA_VERSION
    errors << "#{label}.status must be #{NONCANONICAL_STATUS}" unless document["status"] == NONCANONICAL_STATUS
    errors << "#{label}.probe_mode must match the bounded section context" unless document["probe_mode"].to_s == context["probe_mode"]
    if document.key?("harness_commit")
      errors << "#{label}.harness_commit does not match the allowlist" unless document["harness_commit"].to_s == allowlist["harness_commit"]
      errors << "#{label}.harness_commit does not match the bounded section context" unless document["harness_commit"].to_s == context["harness_commit"]
    end
    errors << "#{label}.section_id must be #{expected_section_id}" unless document["section_id"].to_s == expected_section_id
    errors << "#{label}.section_order must be #{expected_order}" unless document["section_order"] == expected_order
    errors << "#{label}.time_range is required" unless nonempty_string?(document["time_range"])
    errors << "#{label}.time_range does not match the bounded section context" unless document["time_range"].to_s == context["time_range"].to_s
    errors.concat(exact_keys_errors(document["model_route"], MODEL_ROUTE.keys, "#{label}.model_route"))
    errors << "#{label}.model_route must be gpt-5.6-sol/xhigh/high" unless document["model_route"] == MODEL_ROUTE
    errors << "#{label}.source_set_sha256 does not match the allowlist" unless document["source_set_sha256"].to_s == allowlist["source_set_sha256"]
    errors << "#{label}.section_context_sha256 must be exactly 64 lowercase hexadecimal characters" unless document["section_context_sha256"].to_s.match?(SHA256_PATTERN)
    errors << "#{label}.section_context_sha256 does not match the bounded section context" unless document["section_context_sha256"].to_s == context["section_context_sha256"].to_s
    errors << "#{label}.previous_boundary is required" unless nonempty_string?(document["previous_boundary"])
    errors << "#{label}.next_boundary is required" unless nonempty_string?(document["next_boundary"])
    errors << "#{label}.previous_boundary does not match the bounded section context" unless document["previous_boundary"].to_s == context["previous_boundary"].to_s
    errors << "#{label}.next_boundary does not match the bounded section context" unless document["next_boundary"].to_s == context["next_boundary"].to_s

    if context["probe_mode"] == SECTION_AUTHORING_MODE
      authoring_result = validate_authoring_section(document["section"], context, label, require_known_continuity: false)
      errors.concat(authoring_result[:errors])
      errors.concat(validate_normalization_receipt(document, allowlist, context, label))
      projection = {
        "probe_mode" => SECTION_AUTHORING_MODE,
        "section_id" => expected_section_id,
        "section_order" => expected_order,
        "time_range" => document["time_range"],
        "section_context_sha256" => document["section_context_sha256"],
        "previous_boundary" => document["previous_boundary"],
        "next_boundary" => document["next_boundary"]
      }
      document["section"].each do |key, value|
        next if %w[section_id section_order time_range section_context_sha256 previous_boundary next_boundary].include?(key)

        projection[key] = deep_copy(value)
      end if document["section"].is_a?(Hash)
      return authoring_result.merge(errors: errors, projection: projection)
    end

    section = document["section"]
    unless section.is_a?(Hash)
      errors << "#{label}.section must be an object"
      section = {}
    end
    if section.key?("section_id") && section["section_id"].to_s != expected_section_id
      errors << "#{label}.section.section_id conflicts with the shard section_id"
    end
    if section.key?("section_order") && section["section_order"] != expected_order
      errors << "#{label}.section.section_order conflicts with the shard section_order"
    end
    if section.key?("time_range") && section["time_range"].to_s != document["time_range"].to_s
      errors << "#{label}.section.time_range conflicts with the shard time_range"
    end

    cuts = section["storyboard_core_cuts"]
    unless cuts.is_a?(Array) && cuts.any?
      errors << "#{label}.section.storyboard_core_cuts must be a non-empty array"
      cuts = []
    end

    cut_results = cuts.each_with_index.map do |cut, index|
      validate_cut(cut, "#{label}.section.storyboard_core_cuts[#{index}]", context["allowed_source_paths"])
    end
    cut_results.each { |result| errors.concat(result[:errors]) }

    cut_ids = cut_results.map { |result| result[:cut_id] }.reject(&:empty?)
    duplicate_cuts = duplicate_values(cut_ids)
    errors << "#{label} contains duplicate cut ids: #{duplicate_cuts.join(', ')}" unless duplicate_cuts.empty?

    required_parent_cuts = context["required_parent_cuts"]
    required_cut_ids = required_parent_cuts.map { |row| row["required_cut_id"].to_s }
    unless cut_ids == required_cut_ids
      errors << "#{label}.section.storyboard_core_cuts must exactly cover required_parent_cuts in order; expected #{required_cut_ids.join(', ')}, got #{cut_ids.join(', ')}"
    end
    cuts.each_with_index do |cut, index|
      next unless cut.is_a?(Hash) && required_parent_cuts[index].is_a?(Hash)

      expected_parent = deep_copy(required_parent_cuts[index]["source_parent_cut"])
      next unless expected_parent.is_a?(Hash)

      expected_parent["cut_id"] = required_parent_cuts[index]["required_cut_id"]
      actual_parent = cut.reject { |key, _value| key == "keyframe_shots" }
      unless actual_parent == expected_parent
        errors << "#{label}.section.storyboard_core_cuts[#{index}] rewrites, drops, or adds parent-cut content outside cut_id rename plus keyframe_shots"
      end
    end

    section_source_errors = []
    section_source_paths = recursive_source_paths(section, "#{label}.section", section_source_errors)
    errors.concat(section_source_errors)
    unknown = section_source_paths.uniq - context["allowed_source_paths"]
    errors << "#{label}.section contains source paths outside the bounded context allowlist: #{unknown.join(', ')}" unless unknown.empty?

    actual_cut_count = cuts.length
    actual_keyframe_count = cut_results.sum { |result| result[:shots].length }
    quality_check = section["section_quality_check"]
    if quality_check.is_a?(Hash)
      if quality_check.key?("actual_core_cut_count") && quality_check["actual_core_cut_count"] != actual_cut_count
        errors << "#{label}.section.section_quality_check.actual_core_cut_count contradicts the storyboard array"
      end
      if quality_check.key?("actual_keyframe_count") && quality_check["actual_keyframe_count"] != actual_keyframe_count
        errors << "#{label}.section.section_quality_check.actual_keyframe_count contradicts the keyframe arrays"
      end
    end

    expected_section_plan = deep_copy(context["section_plan"])
    if expected_section_plan["section_quality_check"].is_a?(Hash)
      expected_section_plan["section_quality_check"]["actual_core_cut_count"] = actual_cut_count
      expected_section_plan["section_quality_check"]["actual_keyframe_count"] = actual_keyframe_count
    end
    actual_section_plan = section.reject { |key, _value| key == "storyboard_core_cuts" }
    unless actual_section_plan == expected_section_plan
      errors << "#{label}.section rewrites, drops, or adds section_plan content outside recomputed actual counts"
    end
    errors.concat(validate_normalization_receipt(document, allowlist, context, label))

    projection = {
      "probe_mode" => CHILD_KEYFRAME_MODE,
      "section_id" => expected_section_id,
      "section_order" => expected_order,
      "time_range" => document["time_range"],
      "section_context_sha256" => document["section_context_sha256"],
      "previous_boundary" => document["previous_boundary"],
      "next_boundary" => document["next_boundary"]
    }
    section.each do |key, value|
      next if %w[section_id section_order time_range section_context_sha256 previous_boundary next_boundary].include?(key)

      projection[key] = deep_copy(value)
    end

    {
      errors: errors,
      projection: projection,
      cuts: cuts,
      cut_ids: cut_ids,
      keyframe_ids: cut_results.flat_map { |result| result[:keyframe_ids] }.reject(&:empty?),
      packet_ids: cut_results.flat_map { |result| result[:packet_ids] }.reject(&:empty?),
      shots: cut_results.flat_map { |result| result[:shots] },
      source_paths: section_source_paths
    }
  end

  def validate_collective(shard_results, require_known_continuity: true)
    errors = []
    all_keyframe_ids = shard_results.flat_map { |result| result[:keyframe_ids] }
    {
      "cut_id" => shard_results.flat_map { |result| result[:cut_ids] },
      "keyframe_shot_id" => all_keyframe_ids,
      "packet_id" => shard_results.flat_map { |result| result[:packet_ids] }
    }.each do |field, values|
      duplicates = duplicate_values(values)
      errors << "probe contains duplicate #{field} values across sections: #{duplicates.join(', ')}" unless duplicates.empty?
    end

    known_keyframe_ids = all_keyframe_ids.to_h { |keyframe_id| [keyframe_id, true] }
    shard_results.flat_map { |result| Array(result[:shots]) }.each do |shot|
      next unless shot.is_a?(Hash)

      shot_id = shot["keyframe_shot_id"].to_s
      %w[continuity_in continuity_out].each do |field|
        text = shot[field]
        next unless text.is_a?(String)

        invalid_tokens = text.scan(/\b(?:KF|KSB)_[A-Z0-9_]+\b/)
        invalid_tokens.concat(text.scan(/\b(?:KSS|KSC)[A-Z0-9_]*\b/))
        invalid_tokens.uniq.each do |token|
          errors << "probe child shot #{shot_id} #{field} contains invalid continuity id token #{token}; only an exact existing KS_* id is valid"
        end
        text.scan(/\bKS_[A-Z0-9_]+\b/).uniq.each do |token|
          next if known_keyframe_ids[token]

          local_expansions = known_keyframe_ids.keys.select { |keyframe_id| keyframe_id.start_with?("#{token}_") }
          unless local_expansions.empty?
            errors << "probe child shot #{shot_id} #{field} uses truncated local keyframe id #{token}; use exact #{local_expansions.join(' or ')}"
            next
          end
          next unless require_known_continuity

          errors << "probe child shot #{shot_id} #{field} references unknown keyframe id #{token}"
        end
      end
    end
    errors
  end

  def derive_coverage(sections, expected_sections)
    cuts_by_section = sections.to_h do |section|
      [section["section_id"], Array(section["storyboard_core_cuts"])]
    end
    section_cut_ids = cuts_by_section.transform_values { |cuts| cuts.map { |cut| cut["cut_id"].to_s } }
    section_keyframe_counts = cuts_by_section.transform_values do |cuts|
      cuts.sum { |cut| Array(cut["keyframe_shots"]).length }
    end
    keyframes = cuts_by_section.values.flatten.flat_map { |cut| Array(cut["keyframe_shots"]) }
    actual_ids = sections.map { |section| section["section_id"].to_s }
    {
      "required_section_ids" => expected_sections,
      "completed_section_ids" => actual_ids,
      "missing_section_ids" => expected_sections - actual_ids,
      "extra_section_ids" => actual_ids - expected_sections,
      "section_cut_counts" => section_cut_ids.transform_values(&:length),
      "section_keyframe_counts" => section_keyframe_counts,
      "section_cut_ids" => section_cut_ids,
      "keyframe_shot_ids" => keyframes.map { |shot| shot["keyframe_shot_id"].to_s },
      "packet_ids" => keyframes.map { |shot| shot["packet_id"].to_s },
      "actual_core_cut_count" => section_cut_ids.values.sum(&:length),
      "actual_keyframe_count" => keyframes.length,
      "numeric_cap_used" => false,
      "section_by_section_pass_used" => true
    }
  end

  def source_evidence_incomplete?(source, evidence_sections, expected_sections)
    declared_targets = Array(source["target_sections"]) & expected_sections
    return false if declared_targets.empty?

    if source.key?("required_evidence_sections")
      required = Array(source["required_evidence_sections"]) & expected_sections
      return (required - evidence_sections).any?
    end

    case source["evidence_scope"].to_s
    when "per_declared_target", "context_only_per_target"
      (declared_targets - evidence_sections).any?
    else
      (evidence_sections & declared_targets).empty?
    end
  end

  def derive_source_audit(sections, allowlist, expected_sections, contexts)
    errors = []
    referenced = recursive_source_paths(sections, "sections", errors).uniq
    raise ContractError, errors unless errors.empty?

    unknown = referenced - allowlist["source_paths"]
    direct_evidence_sections_by_path = Hash.new { |hash, key| hash[key] = [] }
    sections.each do |section|
      section_id = section["section_id"].to_s
      Array(section["reference_dispositions"]).each do |row|
        direct_evidence_sections_by_path[row["source_path"].to_s] << section_id if row.is_a?(Hash) && nonempty_string?(row["source_path"])
      end
      Array(section["storyboard_core_cuts"]).each do |cut|
        next unless cut.is_a?(Hash)

        Array(cut["reference_uses"]).each do |row|
          direct_evidence_sections_by_path[row["source_path"].to_s] << section_id if row.is_a?(Hash) && nonempty_string?(row["source_path"])
        end
      end
    end
    supporting_evidence_sections_by_path = Hash.new { |hash, key| hash[key] = [] }
    contexts.each do |context|
      Array(context["allowed_source_paths"]).each do |source_path|
        supporting_evidence_sections_by_path[source_path] << context["section_id"].to_s
      end
    end
    direct_evidence_sections_by_path.each_value(&:uniq!)
    supporting_evidence_sections_by_path.each_value(&:uniq!)

    supporting_paths = allowlist["supporting_context_source_paths"]
    direct_paths = allowlist["source_paths"] - supporting_paths
    sources_by_path = allowlist["sources"].to_h { |source| [source["path"], source] }
    unevidenced_direct = direct_paths.select do |source_path|
      source_evidence_incomplete?(sources_by_path.fetch(source_path), direct_evidence_sections_by_path[source_path], expected_sections)
    end
    unevidenced_supporting = supporting_paths.select do |source_path|
      source_evidence_incomplete?(sources_by_path.fetch(source_path), supporting_evidence_sections_by_path[source_path], expected_sections)
    end

    closure_errors = []
    closure_errors << "direct reference sources lack output reference evidence in any declared in-probe target section: #{unevidenced_direct.join(', ')}" unless unevidenced_direct.empty?
    closure_errors << "supporting context sources lack exact context admission in any declared in-probe target section: #{unevidenced_supporting.join(', ')}" unless unevidenced_supporting.empty?
    raise ContractError, closure_errors unless closure_errors.empty?
    ordered_referenced = allowlist["source_paths"].select { |path| referenced.include?(path) }
    unreferenced = allowlist["source_paths"] - ordered_referenced
    direct_closed = unevidenced_direct.empty?
    supporting_closed = unevidenced_supporting.empty?
    {
      "sources" => deep_copy(allowlist["sources"]),
      "referenced_source_paths" => ordered_referenced,
      "unreferenced_source_paths" => unreferenced,
      "unknown_source_paths" => unknown,
      "direct_reference_paths" => direct_paths,
      "supporting_context_paths" => supporting_paths,
      "unevidenced_direct_paths" => unevidenced_direct,
      "unevidenced_supporting_paths" => unevidenced_supporting,
      "direct_reference_closure_complete" => direct_closed,
      "supporting_context_closure_complete" => supporting_closed,
      "reference_closure_complete" => unknown.empty? && direct_closed && supporting_closed && allowlist["sources"].all? { |source| closed_source_row?(source) }
    }
  end

  def build_receipt(path, section_id, section_order, context)
    pathname = Pathname.new(path.to_s).expand_path.cleanpath
    {
      "probe_mode" => context["probe_mode"],
      "section_id" => section_id,
      "section_order" => section_order,
      "harness_commit" => context["harness_commit"],
      "context_path" => context["path"],
      "context_file_sha256" => context["file_sha256"],
      "section_context_sha256" => context["section_context_sha256"],
      "path" => pathname.to_s,
      "sha256" => Digest::SHA256.file(pathname.to_s).hexdigest
    }
  end

  def build_result(allowlist:, expected_sections:, shard_paths:, contexts:)
    errors = []
    probe_modes = contexts.map { |context| context["probe_mode"] }.uniq
    errors << "mixed probe_mode merge is forbidden: #{probe_modes.join(', ')}" unless probe_modes.length == 1
    documents = []
    shard_paths.each do |path|
      begin
        pathname, document = load_structured(path)
        documents << [pathname, document]
      rescue ContractError => e
        errors.concat(e.errors)
      end
    end
    raise ContractError, errors unless errors.empty?

    by_section = documents.group_by { |_path, document| document["section_id"].to_s }
    missing = expected_sections.reject { |section| by_section.fetch(section, []).length == 1 }
    duplicate = expected_sections.select { |section| by_section.fetch(section, []).length > 1 }
    extra = by_section.keys - expected_sections
    errors << "missing expected section shards: #{missing.join(', ')}" unless missing.empty?
    errors << "duplicate section shards: #{duplicate.join(', ')}" unless duplicate.empty?
    errors << "unexpected section shards: #{extra.join(', ')}" unless extra.empty?
    errors << "merge requires exactly #{expected_sections.length} shard files" unless documents.length == expected_sections.length
    raise ContractError, errors unless errors.empty?

    ordered = expected_sections.each_with_index.map do |section_id, index|
      pathname, document = by_section.fetch(section_id).first
      result = validate_shard(
        document,
        allowlist,
        context: contexts[index],
        expected_section_id: section_id,
        expected_order: contexts[index]["section_order"],
        label: pathname.to_s
      )
      errors.concat(result[:errors])
      [pathname, result]
    end
    errors.concat(validate_collective(ordered.map(&:last)))
    raise ContractError, errors unless errors.empty?

    sections = ordered.map { |_path, result| result[:projection] }
    {
      "schema_version" => RESULT_SCHEMA_VERSION,
      "status" => NONCANONICAL_STATUS,
      "probe_mode" => probe_modes.first,
      "harness_commit" => allowlist["harness_commit"],
      "repo_root_binding" => deep_copy(allowlist["repo_root_binding"]),
      "model_route" => deep_copy(MODEL_ROUTE),
      "source_set_sha256" => allowlist["source_set_sha256"],
      "shard_receipts" => ordered.each_with_index.map do |(pathname, _result), index|
        build_receipt(
          pathname,
          expected_sections[index],
          contexts[index]["section_order"],
          contexts[index]
        )
      end,
      "sections" => sections,
      "source_use_audit" => derive_source_audit(sections, allowlist, expected_sections, contexts),
      "coverage_audit" => derive_coverage(sections, expected_sections)
    }
  end

  def resolve_receipt_path(value, merged_path)
    raw = Pathname.new(value.to_s)
    candidate = raw.absolute? ? raw : merged_path.dirname.join(raw)
    candidate.expand_path.cleanpath
  end

  def validate_result(merged_path, allowlist:, expected_sections:, contexts:)
    pathname, document = load_structured(merged_path)
    errors = exact_keys_errors(document, RESULT_FIELDS, "result")
    errors << "result.schema_version must be #{RESULT_SCHEMA_VERSION}" unless document["schema_version"] == RESULT_SCHEMA_VERSION
    errors << "result.status must be #{NONCANONICAL_STATUS}" unless document["status"] == NONCANONICAL_STATUS
    context_modes = contexts.map { |context| context["probe_mode"] }.uniq
    errors << "mixed probe_mode validation is forbidden: #{context_modes.join(', ')}" unless context_modes.length == 1
    errors << "result.probe_mode does not match the supplied contexts" unless document["probe_mode"].to_s == context_modes.first.to_s
    errors << "result.harness_commit does not match the allowlist" unless document["harness_commit"].to_s == allowlist["harness_commit"]
    errors << "result.repo_root_binding does not match the validated repository/source-set identity" unless document["repo_root_binding"] == allowlist["repo_root_binding"]
    errors << "result.model_route must be gpt-5.6-sol/xhigh/high" unless document["model_route"] == MODEL_ROUTE
    errors << "result.source_set_sha256 does not match the allowlist" unless document["source_set_sha256"].to_s == allowlist["source_set_sha256"]

    receipts = document["shard_receipts"]
    sections = document["sections"]
    unless receipts.is_a?(Array)
      errors << "result.shard_receipts must be an array"
      receipts = []
    end
    unless sections.is_a?(Array)
      errors << "result.sections must be an array"
      sections = []
    end
    errors << "result must contain exactly #{expected_sections.length} shard receipts" unless receipts.length == expected_sections.length
    errors << "result must contain exactly #{expected_sections.length} sections" unless sections.length == expected_sections.length

    receipt_results = []
    receipt_paths = []
    expected_sections.each_with_index do |section_id, index|
      receipt = receipts[index]
      section = sections[index]
      receipt_label = "result.shard_receipts[#{index}]"
      errors.concat(exact_keys_errors(receipt, RECEIPT_FIELDS, receipt_label))
      unless receipt.is_a?(Hash)
        next
      end
      errors << "#{receipt_label}.section_id must be #{section_id}" unless receipt["section_id"].to_s == section_id
      errors << "#{receipt_label}.probe_mode does not match result/context" unless receipt["probe_mode"].to_s == document["probe_mode"].to_s && receipt["probe_mode"].to_s == contexts[index]["probe_mode"].to_s
      errors << "#{receipt_label}.section_order must match the absolute allowlist.section_universe order" unless receipt["section_order"] == contexts[index]["section_order"]
      errors << "#{receipt_label}.harness_commit does not match the allowlist" unless receipt["harness_commit"].to_s == allowlist["harness_commit"]
      errors << "#{receipt_label}.harness_commit does not match the supplied context" unless receipt["harness_commit"].to_s == contexts[index]["harness_commit"]
      errors << "#{receipt_label}.section_context_sha256 must be exactly 64 lowercase hexadecimal characters" unless receipt["section_context_sha256"].to_s.match?(SHA256_PATTERN)
      errors << "#{receipt_label}.section_context_sha256 does not match the supplied bounded context" unless receipt["section_context_sha256"].to_s == contexts[index]["section_context_sha256"].to_s
      if section.is_a?(Hash) && receipt["section_context_sha256"].to_s != section["section_context_sha256"].to_s
        errors << "#{receipt_label}.section_context_sha256 does not match the merged section projection"
      end
      context_path = resolve_receipt_path(receipt["context_path"], pathname)
      errors << "#{receipt_label}.context_path must be a normalized absolute path" unless receipt["context_path"].to_s == context_path.to_s
      errors << "#{receipt_label}.context_path does not match the supplied --context" unless context_path.to_s == contexts[index]["path"].to_s
      errors << "#{receipt_label}.context_file_sha256 must be exactly 64 lowercase hexadecimal characters" unless receipt["context_file_sha256"].to_s.match?(SHA256_PATTERN)
      if context_path.file?
        actual_context_file_sha = Digest::SHA256.file(context_path.to_s).hexdigest
        errors << "#{receipt_label}.context_file_sha256 is stale for #{context_path}" unless actual_context_file_sha == receipt["context_file_sha256"].to_s
      else
        errors << "#{receipt_label}.context_path is not readable: #{context_path}"
      end
      errors << "#{receipt_label}.context_file_sha256 does not match the supplied --context" unless receipt["context_file_sha256"].to_s == contexts[index]["file_sha256"].to_s
      errors << "#{receipt_label}.sha256 must be exactly 64 lowercase hexadecimal characters" unless receipt["sha256"].to_s.match?(SHA256_PATTERN)

      receipt_path = resolve_receipt_path(receipt["path"], pathname)
      if receipt["path"].to_s != receipt_path.to_s
        errors << "#{receipt_label}.path must be a normalized absolute path"
      end
      receipt_paths << receipt_path.to_s
      unless receipt_path.file?
        errors << "#{receipt_label}.path is not readable: #{receipt_path}"
        next
      end
      actual_sha = Digest::SHA256.file(receipt_path.to_s).hexdigest
      unless actual_sha == receipt["sha256"].to_s
        errors << "#{receipt_label}.sha256 is stale for #{receipt_path}"
        next
      end

      begin
        _loaded_path, shard_document = load_structured(receipt_path)
        shard_result = validate_shard(
          shard_document,
          allowlist,
          context: contexts[index],
          expected_section_id: section_id,
          expected_order: contexts[index]["section_order"],
          label: receipt_path.to_s
        )
        errors.concat(shard_result[:errors])
        errors << "result.sections[#{index}] does not exactly match its hash-bound shard" unless section == shard_result[:projection]
        receipt_results << shard_result
      rescue ContractError => e
        errors.concat(e.errors)
      end
    end
    duplicate_receipt_paths = duplicate_values(receipt_paths)
    errors << "result.shard_receipts contains duplicate paths: #{duplicate_receipt_paths.join(', ')}" unless duplicate_receipt_paths.empty?
    errors.concat(validate_collective(receipt_results))

    section_ids = sections.map { |section| section["section_id"].to_s if section.is_a?(Hash) }.compact
    errors << "result sections must exactly cover --sections in order" unless section_ids == expected_sections

    source_audit = document["source_use_audit"]
    errors.concat(exact_keys_errors(source_audit, SOURCE_AUDIT_FIELDS, "result.source_use_audit"))
    coverage = document["coverage_audit"]
    errors.concat(exact_keys_errors(coverage, COVERAGE_FIELDS, "result.coverage_audit"))

    if sections.all? { |section| section.is_a?(Hash) }
      expected_source_audit = derive_source_audit(sections, allowlist, expected_sections, contexts)
      errors << "result.source_use_audit does not match allowlisted paths/hashes and derived source use" unless source_audit == expected_source_audit
      expected_coverage = derive_coverage(sections, expected_sections)
      errors << "result.coverage_audit does not match counts and ids derived from the section arrays" unless coverage == expected_coverage
    end

    if source_audit.is_a?(Hash)
      unknown = Array(source_audit["unknown_source_paths"])
      errors << "result contains source paths outside the allowlist: #{unknown.join(', ')}" unless unknown.empty?
    end
    raise ContractError, errors unless errors.empty?

    document
  end

  def write_structured(path, document)
    pathname = Pathname.new(path.to_s).expand_path.cleanpath
    FileUtils.mkdir_p(pathname.dirname)
    content = if %w[.yaml .yml].include?(pathname.extname.downcase)
                YAML.dump(document)
              else
                "#{JSON.pretty_generate(document)}\n"
              end
    temporary = Tempfile.new([".idol-storyboard-probe-", ".tmp"], pathname.dirname.to_s)
    begin
      temporary.binmode
      temporary.write(content)
      temporary.flush
      temporary.fsync
      temporary.close
      File.rename(temporary.path, pathname.to_s)
    ensure
      temporary.close! if temporary
    end
    pathname
  end

  def report(document, path)
    coverage = document.fetch("coverage_audit")
    {
      "ok" => true,
      "status" => document["status"],
      "result_path" => Pathname.new(path.to_s).expand_path.cleanpath.to_s,
      "source_set_sha256" => document["source_set_sha256"],
      "section_count" => Array(document["sections"]).length,
      "actual_core_cut_count" => coverage["actual_core_cut_count"],
      "actual_keyframe_count" => coverage["actual_keyframe_count"],
      "reference_closure_complete" => document.dig("source_use_audit", "reference_closure_complete"),
      "numeric_cap_used" => coverage["numeric_cap_used"],
      "section_by_section_pass_used" => coverage["section_by_section_pass_used"]
    }
  end
end

def probe_usage_error(message, parser = nil)
  warn "ERROR: #{message}"
  warn parser if parser
  exit 2
end

def print_probe_failure(error, json: false)
  if json
    puts JSON.pretty_generate("ok" => false, "errors" => error.errors)
  else
    error.errors.each { |message| warn "ERROR: #{message}" }
  end
end

if __FILE__ == $PROGRAM_NAME
  command = ARGV.shift
  probe_usage_error("expected validate, merge, normalize-shard, or attest") unless %w[validate merge normalize-shard attest].include?(command)

  options = {
    allowlist: nil,
    sections: nil,
    output: nil,
    contexts: [],
    execution_log: nil,
    repo_root: IdolStoryboardProbeContract::REPOSITORY_ROOT,
    json: false
  }
  parser = OptionParser.new do |opts|
    opts.banner = if command == "validate"
                    "usage: ruby scripts/idol_storyboard_probe_contract.rb validate MERGED --allowlist PATH --sections CSV --context PATH... [--json]"
                  elsif command == "normalize-shard"
                    "usage: ruby scripts/idol_storyboard_probe_contract.rb normalize-shard RAW_SHARD --allowlist PATH --context PATH --execution-log PATH --output TEMP_PATH [--json]"
                  elsif command == "attest"
                    "usage: ruby scripts/idol_storyboard_probe_contract.rb attest RAW_SHARD --allowlist PATH --context PATH [--json]"
                  else
                    "usage: ruby scripts/idol_storyboard_probe_contract.rb merge --allowlist PATH --sections CSV --context PATH... --output PATH SHARD... [--json]"
                  end
    opts.on("--allowlist PATH", String, "Hash-bound source allowlist") { |value| options[:allowlist] = value }
    opts.on("--sections CSV", String, "Expected section ids in merge order") { |value| options[:sections] = value }
    opts.on("--output PATH", String, "Merged evaluation result path") { |value| options[:output] = value }
    opts.on("--context PATH", String, "Bounded section input packet; repeat once per expected section") { |value| options[:contexts] << value }
    opts.on("--execution-log PATH", String, "Codex JSONL execution log for normalize-shard provenance") { |value| options[:execution_log] = value }
    opts.on("--repo-root PATH", String, "Repository root used to resolve and hash allowlisted sources") { |value| options[:repo_root] = value }
    opts.on("--json", "Print a machine-readable report") { options[:json] = true }
  end

  begin
    parser.parse!(ARGV)
  rescue OptionParser::ParseError => e
    probe_usage_error(e.message, parser)
  end
  probe_usage_error("--allowlist is required", parser) unless options[:allowlist]
  probe_usage_error("--sections is required", parser) if %w[validate merge].include?(command) && !options[:sections]

  begin
    allowlist = IdolStoryboardProbeContract.validate_allowlist(options[:allowlist], repo_root: options[:repo_root])
    if command == "normalize-shard"
      probe_usage_error("normalize-shard requires exactly one RAW_SHARD path", parser) unless ARGV.length == 1
      probe_usage_error("normalize-shard requires exactly one --context PATH", parser) unless options[:contexts].length == 1
      probe_usage_error("normalize-shard requires --execution-log PATH", parser) unless options[:execution_log]
      probe_usage_error("normalize-shard requires --output TEMP_PATH", parser) unless options[:output]
      _context_path, context_document = IdolStoryboardProbeContract.load_structured(options[:contexts].first)
      section_id = context_document["section_id"].to_s
      IdolStoryboardProbeContract.validate_requested_sections(allowlist, [section_id])
      context = IdolStoryboardProbeContract.validate_contexts(options[:contexts], allowlist, [section_id]).first
      output_path = Pathname.new(options[:output]).expand_path.cleanpath
      unless IdolStoryboardProbeContract.temporary_output_path?(output_path, allowlist["repo_root"])
        probe_usage_error("--output must stay in an OS temporary directory outside the repository", parser)
      end
      protected_paths = [options[:allowlist], options[:contexts].first, options[:execution_log], ARGV.first].map { |path| Pathname.new(path).expand_path.cleanpath.to_s }
      probe_usage_error("--output must not overwrite the allowlist, context, execution log, or raw shard", parser) if protected_paths.include?(output_path.to_s)

      document = IdolStoryboardProbeContract.build_normalized_shard(ARGV.first, allowlist, context, options[:execution_log])
      written = IdolStoryboardProbeContract.write_structured(output_path, document)
      validation = IdolStoryboardProbeContract.validate_shard(
        document,
        allowlist,
        context: context,
        expected_section_id: section_id,
        expected_order: context["section_order"],
        label: written.to_s
      )
      raise IdolStoryboardProbeContract::ContractError, validation[:errors] unless validation[:errors].empty?
      receipt = document["deterministic_normalization_receipt"]
      report = {
        "ok" => true,
        "status" => document["status"],
        "normalized_shard_path" => written.to_s,
        "section_id" => section_id,
        "execution_turn_id" => document.dig("execution_receipt", "turn_id"),
        "actual_model" => document.dig("execution_receipt", "actual_model"),
        "actual_effort" => document.dig("execution_receipt", "actual_effort"),
        "raw_sha256" => receipt["raw_sha256"],
        "raw_keyframe_shots_sha256" => receipt["raw_keyframe_shots_sha256"],
        "keyframe_shots_sha256" => receipt["keyframe_shots_sha256"],
        "collapsed_exact_duplicate_cuts" => receipt["collapsed_exact_duplicate_cuts"],
        "repaired_locked_field_count" => receipt["repaired_locked_field_count"],
        "repaired_locked_field_paths" => receipt["repaired_locked_field_paths"]
      }
      puts(options[:json] ? JSON.pretty_generate(report) : "wrote #{written}")
    elsif command == "attest"
      probe_usage_error("attest requires exactly one RAW_SHARD path", parser) unless ARGV.length == 1
      probe_usage_error("attest requires exactly one --context PATH", parser) unless options[:contexts].length == 1
      _context_path, context_document = IdolStoryboardProbeContract.load_structured(options[:contexts].first)
      section_id = context_document["section_id"].to_s
      IdolStoryboardProbeContract.validate_requested_sections(allowlist, [section_id])
      context = IdolStoryboardProbeContract.validate_contexts(options[:contexts], allowlist, [section_id]).first
      unless context["probe_mode"] == IdolStoryboardProbeContract::SECTION_AUTHORING_MODE
        probe_usage_error("compact attestations are restricted to section_02a_authoring", parser)
      end
      raw_path, raw_document = IdolStoryboardProbeContract.load_structured(ARGV.first)
      validation = IdolStoryboardProbeContract.validate_raw_shard_for_normalization(
        raw_document,
        allowlist,
        context: context,
        label: raw_path.to_s
      )
      raise IdolStoryboardProbeContract::ContractError, validation[:errors] unless validation[:errors].empty?
      attestation = IdolStoryboardProbeContract.compact_execution_attestation(raw_path, raw_document, context)
      puts(options[:json] ? JSON.pretty_generate(attestation) : JSON.generate(attestation))
    else
      expected_sections = IdolStoryboardProbeContract.parse_sections(options[:sections])
      IdolStoryboardProbeContract.validate_requested_sections(allowlist, expected_sections)
      contexts = IdolStoryboardProbeContract.validate_contexts(options[:contexts], allowlist, expected_sections)

      if command == "validate"
        probe_usage_error("validate requires exactly one MERGED path", parser) unless ARGV.length == 1
        merged_path = ARGV.first
        document = IdolStoryboardProbeContract.validate_result(
          merged_path,
          allowlist: allowlist,
          expected_sections: expected_sections,
          contexts: contexts
        )
        report = IdolStoryboardProbeContract.report(document, merged_path)
        puts(options[:json] ? JSON.pretty_generate(report) : "OK: NONCANONICAL storyboard probe result is internally valid")
      else
        probe_usage_error("merge requires --output PATH", parser) unless options[:output]
        probe_usage_error("merge requires at least one SHARD path", parser) if ARGV.empty?
        output_path = Pathname.new(options[:output]).expand_path.cleanpath
        unless IdolStoryboardProbeContract.temporary_output_path?(output_path, allowlist["repo_root"])
          probe_usage_error("--output must stay in an OS temporary directory outside the repository", parser)
        end
        protected_paths = [options[:allowlist], *options[:contexts], *ARGV].map { |path| Pathname.new(path).expand_path.cleanpath.to_s }
        probe_usage_error("--output must not overwrite the allowlist or a shard", parser) if protected_paths.include?(output_path.to_s)

        document = IdolStoryboardProbeContract.build_result(
          allowlist: allowlist,
          expected_sections: expected_sections,
          shard_paths: ARGV,
          contexts: contexts
        )
        written = IdolStoryboardProbeContract.write_structured(output_path, document)
        IdolStoryboardProbeContract.validate_result(
          written,
          allowlist: allowlist,
          expected_sections: expected_sections,
          contexts: contexts
        )
        report = IdolStoryboardProbeContract.report(document, written)
        puts(options[:json] ? JSON.pretty_generate(report) : "wrote #{written}")
      end
    end
  rescue IdolStoryboardProbeContract::ContractError => e
    print_probe_failure(e, json: options[:json])
    exit 1
  end
end
