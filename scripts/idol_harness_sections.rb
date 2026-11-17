#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "time"
require "yaml"

module IdolHarnessSections
  ROOT = Pathname.new(__dir__).join("..").expand_path
  ENVELOPE_SCHEMA_VERSION = "idol-harness-artifact-envelope.v1"
  PAYLOAD_SCHEMA_VERSION = "idol-harness-section-slice.v1"
  MANIFEST_SCHEMA_VERSION = "idol-harness-section-slice-set.v1"
  PAYLOAD_SCHEMA_PATH = "schemas/harness-section-slice.schema.json"
  CONTRACT_VALIDATOR = ROOT.join("scripts", "validate_harness_artifact_contract.rb")

  STAGE_ALIASES = {
    "front" => "front_planning_integration",
    "front_planning_integration" => "front_planning_integration",
    "front planning integration" => "front_planning_integration",
    "front_planning_readiness" => "front_planning_integration",
    "01" => "mv_performance_direction",
    "mv_performance_direction" => "mv_performance_direction",
    "mv & performance direction" => "mv_performance_direction",
    "02a" => "mv_storyboard_direction",
    "mv_storyboard_direction" => "mv_storyboard_direction",
    "core cut & branch cut storyboard" => "mv_storyboard_direction",
    "02b" => "image_prompt_compilation",
    "image_prompt_compilation" => "image_prompt_compilation",
    "image prompt compile" => "image_prompt_compilation"
  }.freeze

  STAGE_KINDS = {
    "front_planning_integration" => "front_planning_readiness",
    "mv_performance_direction" => "01_direction_map",
    "mv_storyboard_direction" => "02a_master_storyboard",
    "image_prompt_compilation" => "02b_prompt_packets"
  }.freeze

  MERGE_CHECK_MAP = {
    "section_boundary_timing" => "section_boundary_continuity",
    "section_boundary_continuity" => "section_boundary_continuity",
    "repeated_hook_variation" => "repeated_hook_variation",
    "member_balance" => "member_balance",
    "frame_subject_variety" => "frame_subject_variety",
    "world_object_system_continuity" => "world_object_system_continuity",
    "space_variety" => "space_variety",
    "wardrobe_rotation" => "wardrobe_rotation",
    "source_trace_consistency" => "source_traceability",
    "source_traceability" => "source_traceability",
    "rhythm_preservation" => "rhythm_preservation",
    "packet_count_alignment" => "packet_export_count_alignment",
    "packet_expansion_alignment" => "packet_export_count_alignment",
    "02a_source_ref_alignment" => "source_traceability",
    "03_motion_continuity" => "motion_continuity",
    "motion_continuity" => "motion_continuity",
    "04_audio_marker_alignment" => "audio_marker_alignment",
    "audio_marker_alignment" => "audio_marker_alignment",
    "founder_gate_preserved" => "founder_gate_preserved"
  }.freeze

  class Error < StandardError; end
  class ValidationError < Error; end

  module_function

  def load_structured(path)
    path = Pathname.new(path).expand_path
    raise Error, "file not found: #{path}" unless path.file?

    if path.extname.downcase == ".json"
      JSON.parse(path.read)
    else
      YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true) || {}
    end
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise Error, "failed to parse #{path}: #{e.message}"
  end

  def dump_structured(document, path)
    alias_free = JSON.parse(JSON.generate(canonicalize(document)))
    if Pathname.new(path).extname.downcase == ".json"
      JSON.pretty_generate(alias_free) + "\n"
    else
      YAML.dump(alias_free)
    end
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def canonicalize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, child), result|
        result[key.to_s] = canonicalize(child)
      end.sort.to_h
    when Array
      value.map { |child| canonicalize(child) }
    when Time
      value.iso8601
    else
      value
    end
  end

  def canonical_digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def file_digest(path)
    Digest::SHA256.file(Pathname.new(path).expand_path.to_s).hexdigest
  end

  def repo_relative(path)
    path = Pathname.new(path).expand_path
    root_prefix = "#{ROOT}#{File::SEPARATOR}"
    return path.relative_path_from(ROOT).to_s if path.to_s.start_with?(root_prefix)
    return "." if path == ROOT

    path.to_s
  end

  def resolve_path(raw)
    path = Pathname.new(raw.to_s)
    path = ROOT.join(path) unless path.absolute?
    path.expand_path
  end

  def atomic_write(path, content, force: false)
    path = Pathname.new(path).expand_path
    raise Error, "output exists; pass --force to replace: #{path}" if path.exist? && !force

    FileUtils.mkdir_p(path.dirname.to_s)
    temporary = path.dirname.join(".#{path.basename}.tmp-#{Process.pid}")
    temporary.write(content)
    File.rename(temporary.to_s, path.to_s)
  ensure
    temporary.delete if defined?(temporary) && temporary && temporary.exist?
  end

  def write_validated_contract(path, document, force: false)
    path = Pathname.new(path).expand_path
    raise Error, "output exists; pass --force to replace: #{path}" if path.exist? && !force

    FileUtils.mkdir_p(path.dirname.to_s)
    suffix = path.extname.downcase == ".json" ? ".json" : ".yaml"
    temporary = path.dirname.join(".#{path.basename}.validate-#{Process.pid}#{suffix}")
    temporary.write(dump_structured(document, temporary))
    report = run_contract_validator(temporary)
    unless report["status"] == "pass"
      raise ValidationError, "canonical graph-engineering artifact validation failed for #{path}: #{Array(report['errors']).join('; ')}"
    end
    File.rename(temporary.to_s, path.to_s)
    report
  ensure
    temporary.delete if defined?(temporary) && temporary && temporary.exist?
  end

  def run_contract_validator(path)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      CONTRACT_VALIDATOR.to_s,
      "--json",
      Pathname.new(path).expand_path.to_s,
      chdir: ROOT.to_s
    )
    report = JSON.parse(stdout)
    report["process_stderr"] = stderr unless stderr.to_s.strip.empty?
    report["process_success"] = status.success?
    report
  rescue JSON::ParserError => e
    {
      "status" => "fail",
      "errors" => ["validator returned non-JSON output: #{e.message}", stdout.to_s, stderr.to_s].reject(&:empty?)
    }
  rescue Errno::ENOENT => e
    { "status" => "fail", "errors" => ["validator could not run: #{e.message}"] }
  end

  def compact_strings(value)
    Array(value).flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def first_text(*values)
    values.flatten.each do |value|
      case value
      when String
        return value.strip unless value.strip.empty?
      when Numeric, TrueClass, FalseClass
        return value.to_s
      when Array
        text = compact_strings(value).join(" | ")
        return text unless text.empty?
      when Hash
        text = value["summary"] || value["description"] || value["note"]
        return text.to_s unless text.to_s.strip.empty?
      end
    end
    nil
  end

  def value_at(document, path)
    path.reduce(document) do |memo, key|
      break nil unless memo.is_a?(Hash)

      memo[key]
    end
  end

  def deep_values_for_key(value, wanted_key, result = [])
    case value
    when Hash
      value.each do |key, child|
        result << child if key.to_s == wanted_key.to_s
        deep_values_for_key(child, wanted_key, result)
      end
    when Array
      value.each { |child| deep_values_for_key(child, wanted_key, result) }
    end
    result
  end

  def normalize_stage(token)
    return nil if token.nil?

    stage = STAGE_ALIASES[token.to_s.strip.downcase]
    raise Error, "unsupported stage token: #{token}" unless stage

    stage
  end

  def infer_stage(document)
    return "image_prompt_compilation" if document["prompt_packets"].is_a?(Array)
    return "mv_storyboard_direction" if document["master_storyboard"].is_a?(Array)
    return "mv_performance_direction" if document.dig("section_gate", "slices").is_a?(Array)
    return "front_planning_integration" if document.dig("section_work_plan", "sections").is_a?(Array)

    raise Error, "could not infer a supported Front Planning/01/02A/02B stage from the artifact"
  end

  def descriptors_for(document, stage_id)
    case stage_id
    when "front_planning_integration"
      path = ["section_work_plan", "sections"]
      rows = value_at(document, path)
      raise Error, "front-planning artifact has no section_work_plan.sections" unless rows.is_a?(Array)
      rows.each_with_index.map do |row, index|
        descriptor(path, row, index, compact_strings([row["section_id"]]), [], [], [], [])
      end
    when "mv_performance_direction"
      path = ["section_gate", "slices"]
      rows = value_at(document, path)
      raise Error, "01 artifact has no section_gate.slices" unless rows.is_a?(Array)
      rows.each_with_index.map do |row, index|
        descriptor(path, row, index, compact_strings([row["section_id"]]), row["beat_ids"], row["cue_ids"], [], [])
      end
    when "mv_storyboard_direction"
      path = ["section_shards"]
      rows = value_at(document, path)
      raise Error, "#{stage_id} artifact has no section_shards" unless rows.is_a?(Array)
      rows.each_with_index.map do |row, index|
        descriptor(
          path,
          row,
          index,
          compact_strings(row["section_ids"]),
          row["beat_ids"] || row["source_storyboard_beat_ids"],
          [],
          row["cut_ids"] || row["source_storyboard_cut_ids"],
          row["packet_ids"]
        )
      end
    when "image_prompt_compilation"
      path = ["section_shards"]
      rows = value_at(document, path)
      if rows.is_a?(Array)
        rows.each_with_index.map do |row, index|
          descriptor(
            path,
            row,
            index,
            compact_strings(row["section_ids"]),
            row["beat_ids"] || row["source_storyboard_beat_ids"],
            [],
            row["cut_ids"] || row["source_storyboard_cut_ids"],
            row["packet_ids"]
          )
        end
      else
        packets = document["prompt_packets"]
        raise Error, "#{stage_id} artifact has neither section_shards nor prompt_packets" unless packets.is_a?(Array)

        grouped = {}
        packets.each_with_index do |packet, index|
          next unless packet.is_a?(Hash)

          local_trace = packet["local_trace"].is_a?(Hash) ? packet["local_trace"] : {}
          section_id = local_trace["section_id"].to_s
          section_id = local_trace["execution_section_id"].to_s if section_id.empty?
          declared_section_ids = compact_strings(local_trace["section_ids"])
          section_id = declared_section_ids.first if section_id.empty? && declared_section_ids.length == 1
          raise Error, "image_prompt_compilation packet #{packet['packet_id']} has no explicit local_trace.section_id, execution_section_id, or single section_ids value" if section_id.empty?
          grouped[section_id] ||= []
          grouped[section_id] << [packet, index]
        end
        raise Error, "image_prompt_compilation has no section-addressable prompt packets" if grouped.empty?

        grouped.map do |section_id, entries|
          first_packet, first_index = entries.first
          descriptor(
            ["prompt_packets"],
            first_packet,
            first_index,
            [section_id],
            [],
            [],
            entries.map { |packet, _index| packet["cut_id"] },
            entries.map { |packet, _index| packet["packet_id"] }
          ).merge("descriptor_source" => "prompt_packet_explicit_section_trace")
        end
      end
    else
      raise Error, "unsupported stage: #{stage_id}"
    end
  end

  def descriptor(path, row, index, visual_ids, beat_ids, cue_ids, cut_ids, packet_ids)
    raise Error, "section descriptor at #{path.join('.')}[#{index}] must be an object" unless row.is_a?(Hash)
    raise Error, "physical v1 requires exactly one visual section per slice; found #{visual_ids.inspect}" unless visual_ids.length == 1

    {
      "container_path" => path,
      "source_index" => index,
      "record" => row,
      "visual_section_id" => visual_ids.first,
      "beat_ids" => compact_strings(beat_ids),
      "cue_ids" => compact_strings(cue_ids),
      "cut_ids" => compact_strings(cut_ids),
      "packet_ids" => compact_strings(packet_ids)
    }
  end

  def joined_record(path, container_kind, index, key, data, match_field, match_values)
    {
      "container_path" => path,
      "container_kind" => container_kind,
      "source_index" => index,
      "source_key" => key,
      "data" => deep_copy(data),
      "match_field" => match_field,
      "match_values" => compact_strings(match_values)
    }
  end

  def array_matches(document, path, field, expected, array_field: false)
    rows = value_at(document, path)
    return [] unless rows.is_a?(Array)

    rows.each_with_index.each_with_object([]) do |(row, index), result|
      next unless row.is_a?(Hash)

      values = array_field ? compact_strings(row[field]) : compact_strings([row[field]])
      next if (values & expected).empty?

      result << joined_record(path, "array", index, nil, row, field, expected)
    end
  end

  def hash_matches(document, path, expected_keys)
    rows = value_at(document, path)
    return [] unless rows.is_a?(Hash)

    expected_keys.each_with_object([]) do |key, result|
      next unless rows.key?(key)

      result << joined_record(path, "object", nil, key, rows[key], "object_key", expected_keys)
    end
  end

  def joined_records_for(document, stage_id, descriptor)
    visual_id = descriptor["visual_section_id"]
    expected = [visual_id]
    case stage_id
    when "front_planning_integration"
      array_matches(
        document,
        ["section_work_plan", "unit_or_beat_work_units"],
        "parent_section_id",
        expected
      )
    when "mv_performance_direction"
      records = []
      records.concat(array_matches(document, ["lyric_to_scene_thinking"], "section_or_beat_id", expected))
      records.concat(array_matches(document, ["story_distribution", "section_mapping"], "section_name", expected))
      records.concat(hash_matches(document, ["choreography_map", "section_motion_plan"], expected))
      deduplicate_records(records)
    when "mv_storyboard_direction"
      array_matches(document, ["master_storyboard"], "source_sections", expected, array_field: true)
    when "image_prompt_compilation"
      packets = document["prompt_packets"]
      return [] unless packets.is_a?(Array)

      packet_ids = descriptor["packet_ids"]
      packets.each_with_index.each_with_object([]) do |(packet, index), result|
        next unless packet.is_a?(Hash)

        exact_packet = !packet_ids.empty? && packet_ids.include?(packet["packet_id"].to_s)
        exact_section = packet_ids.empty? && packet.dig("local_trace", "section_id").to_s == visual_id
        next unless exact_packet || exact_section

        field = exact_packet ? "packet_id" : "local_trace.section_id"
        values = exact_packet ? packet_ids : expected
        result << joined_record(["prompt_packets"], "array", index, nil, packet, field, values)
      end
    else
      []
    end
  end

  def deduplicate_records(records)
    seen = {}
    records.each_with_object([]) do |record, result|
      locator = raw_record_locator(record)
      next if seen[locator]

      seen[locator] = true
      result << record
    end
  end

  def raw_record_locator(record)
    [Array(record["container_path"]).join("."), record["container_kind"], record["source_index"], record["source_key"]].join("|")
  end

  def primary_record(descriptor)
    joined_record(
      descriptor["container_path"],
      "array",
      descriptor["source_index"],
      nil,
      descriptor["record"],
      "visual_section_id",
      [descriptor["visual_section_id"]]
    )
  end

  def record_identifier(data, fallback)
    if data.is_a?(Hash)
      %w[section_id shard_id cut_id beat_id packet_id section_or_beat_id section_name id].each do |key|
        value = data[key].to_s
        return value unless value.empty?
      end
    end
    fallback.to_s
  end

  def mechanical_record_groups(descriptor, joined)
    records = deduplicate_records([primary_record(descriptor)] + joined)
    grouped = records.group_by { |record| [record["container_path"], record["container_kind"]] }
    grouped.keys.sort_by { |path, kind| [path.join("."), kind] }.each_with_index.map do |(path, kind), group_index|
      items = grouped[[path, kind]].sort_by do |record|
        kind == "array" ? record["source_index"].to_i : record["source_key"].to_s
      end
      ids = []
      items.each_with_index do |record, item_index|
        fallback = kind == "array" ? "record_#{record['source_index']}" : record["source_key"]
        candidate = record_identifier(record["data"], fallback)
        candidate = "#{candidate}__#{item_index}" if ids.include?(candidate)
        ids << candidate
      end
      {
        "group_id" => format("record_group_%02d", group_index + 1),
        "source_container_path" => path,
        "source_container_kind" => kind,
        "source_record_indexes" => kind == "array" ? items.map { |record| record["source_index"] } : [],
        "source_record_keys" => kind == "object" ? items.map { |record| record["source_key"] } : [],
        "source_record_ids" => ids,
        "embedded_records" => items.map { |record| deep_copy(record["data"]) }
      }
    end
  end

  def path_like_values(value, path = [], result = [])
    case value
    when Hash
      value.each { |key, child| path_like_values(child, path + [key.to_s], result) }
    when Array
      value.each_with_index { |child, index| path_like_values(child, path + [index], result) }
    when String
      file_part = value.split("#", 2).first
      if file_part.match?(/\.(?:ya?ml|json)\z/i)
        result << { "field_path" => path.join("."), "value" => value, "file" => file_part }
      end
    end
    result
  end

  def pointer_findings(source_path, descriptors)
    source_path = Pathname.new(source_path).expand_path
    entries = descriptors.map do |descriptor|
      {
        "visual_section_id" => descriptor["visual_section_id"],
        "pointers" => path_like_values(descriptor["record"])
      }
    end
    counts = Hash.new { |hash, key| hash[key] = [] }
    entries.each_with_index do |entry, index|
      entry["pointers"].each do |pointer|
        file = resolve_path(pointer["file"]).to_s
        counts[file] << index unless counts[file].include?(index)
      end
    end

    entries.each_with_object([]) do |entry, result|
      issues = entry["pointers"].each_with_object([]) do |pointer, found|
        file = resolve_path(pointer["file"])
        reasons = []
        reasons << "self_referential_canonical_pointer" if file == source_path
        reasons << "shared_monolith_pointer" if counts[file.to_s].length > 1
        found << pointer.merge("reasons" => reasons) unless reasons.empty?
      end
      result << { "visual_section_id" => entry["visual_section_id"], "issues" => issues } unless issues.empty?
    end
  end

  def inspect_artifact(source_path, stage_token: nil)
    source_path = Pathname.new(source_path).expand_path
    document = load_structured(source_path)
    stage_id = normalize_stage(stage_token) || infer_stage(document)
    descriptors = descriptors_for(document, stage_id)
    findings = pointer_findings(source_path, descriptors)
    by_id = {}
    findings.each { |finding| by_id[finding["visual_section_id"]] = finding["issues"] }

    physically_distinct = descriptors.all? do |descriptor|
      files = path_like_values(descriptor["record"]).map { |pointer| resolve_path(pointer["file"]) }.uniq
      unique_readable = files.select do |file|
        file.file? && file != source_path && descriptors.count do |other|
          path_like_values(other["record"]).any? { |pointer| resolve_path(pointer["file"]) == file }
        end == 1
      end
      !unique_readable.empty?
    end

    {
      "source_artifact" => repo_relative(source_path),
      "stage_id" => stage_id,
      "artifact_kind" => STAGE_KINDS[stage_id],
      "content_id" => document["content_id"],
      "legacy_schema_version" => document["schema_version"],
      "source_sha256" => file_digest(source_path),
      "section_count" => descriptors.length,
      "legacy_monolith_pointer_section_count" => findings.length,
      "physical_section_files_present" => physically_distinct,
      "sections" => descriptors.map do |descriptor|
        {
          "visual_section_id" => descriptor["visual_section_id"],
          "beat_ids" => descriptor["beat_ids"],
          "cue_ids" => descriptor["cue_ids"],
          "cut_ids" => descriptor["cut_ids"],
          "packet_ids" => descriptor["packet_ids"],
          "status" => descriptor.dig("record", "status"),
          "embedded_payload_record_count" => joined_records_for(document, stage_id, descriptor).length + 1,
          "legacy_monolith_pointers" => by_id[descriptor["visual_section_id"]] || []
        }
      end,
      "warnings" => findings.empty? ? [] : ["section metadata points to shared or self-referential canonical YAML/JSON files; those pointers are not physical shards"]
    }
  end

  def mapping_entries(mapping_path)
    return [] unless mapping_path

    document = load_structured(mapping_path)
    rows = document.is_a?(Array) ? document : document["mappings"] || document["sections"]
    raise Error, "section mapping must contain a mappings or sections array" unless rows.is_a?(Array)

    seen = {}
    rows.map do |row|
      raise Error, "each section mapping must be an object" unless row.is_a?(Hash)

      visual_id = first_text(row["visual_section_id"])
      audio_id = first_text(row["audio_section_id"])
      raise Error, "section mapping is missing visual_section_id" unless visual_id
      raise Error, "section mapping #{visual_id} is missing explicit audio_section_id" unless audio_id
      raise Error, "section mapping repeats visual_section_id #{visual_id}" if seen[visual_id]

      seen[visual_id] = true
      source_audio_ids = compact_strings(row["source_audio_section_ids"])
      source_audio_ids = [audio_id] if source_audio_ids.empty?
      unless source_audio_ids.include?(audio_id)
        raise Error, "section mapping #{visual_id} source_audio_section_ids must include primary audio_section_id #{audio_id}"
      end
      {
        "visual_section_id" => visual_id,
        "audio_section_id" => audio_id,
        "source_audio_section_ids" => source_audio_ids,
        "beat_ids" => compact_strings(row["beat_ids"]),
        "cue_ids" => compact_strings(row["cue_ids"]),
        "timing" => row["timing"].is_a?(Hash) ? deep_copy(row["timing"]) : {}
      }
    end
  end

  def mapping_index(entries)
    entries.each_with_object({}) { |entry, result| result[entry["visual_section_id"]] = entry }
  end

  def require_explicit_mappings!(descriptors, mapping_by_visual)
    missing = descriptors.map { |descriptor| descriptor["visual_section_id"] }.reject do |visual_id|
      mapping_by_visual[visual_id] && !mapping_by_visual[visual_id]["audio_section_id"].to_s.empty?
    end
    return if missing.empty?

    raise Error, "explicit audio↔visual section mapping is required; missing: #{missing.join(', ')}. Pass --section-map and do not infer from matching S-codes."
  end

  def parse_clock(token)
    negative = token.start_with?("-")
    clean = negative ? token[1..-1] : token
    parts = clean.split(":").map(&:to_f)
    seconds = if parts.length == 1
                parts[0]
              elsif parts.length == 2
                parts[0] * 60.0 + parts[1]
              else
                parts[-3] * 3600.0 + parts[-2] * 60.0 + parts[-1]
              end
    negative ? -seconds : seconds
  end

  def parse_time_range(value)
    text = value.to_s
    token = "-?(?:\\d{1,2}:){0,2}\\d+(?:\\.\\d+)?"
    match = text.match(/(#{token})\s*-\s*(#{token})/)
    return nil unless match

    [parse_clock(match[1]), parse_clock(match[2])]
  end

  def timing_for(mapping, descriptor, joined)
    mapped = mapping["timing"] || {}
    start_seconds = mapped["start_seconds"]
    end_seconds = mapped["end_seconds"]
    unless start_seconds.is_a?(Numeric) && end_seconds.is_a?(Numeric)
      ranges = []
      ranges << parse_time_range(descriptor.dig("record", "time_range"))
      joined.each do |record|
        deep_values_for_key(record["data"], "time_range").each { |value| ranges << parse_time_range(value) }
      end
      ranges.compact!
      unless ranges.empty?
        start_seconds = ranges.map(&:first).min
        end_seconds = ranges.map(&:last).max
      end
    end
    unless start_seconds.is_a?(Numeric) && end_seconds.is_a?(Numeric) && end_seconds > start_seconds
      raise Error, "#{descriptor['visual_section_id']} needs explicit timing.start_seconds/end_seconds in --section-map"
    end

    primary_cue = first_text(
      mapped["primary_audio_section_cue"],
      descriptor.dig("record", "rhythm_or_lyric_trigger"),
      descriptor.dig("record", "audio_lock", "primary_audio_or_section_cue"),
      joined.map { |record| deep_values_for_key(record["data"], "primary_audio_or_section_cue") },
      joined.map { |record| deep_values_for_key(record["data"], "start_audio_cue") },
      joined.map { |record| deep_values_for_key(record["data"], "music_marker") }
    )
    lyric_original_text = first_text(
      mapped["lyric_original_text"],
      descriptor.dig("record", "audio_lock", "lyric_original_text"),
      joined.map { |record| deep_values_for_key(record["data"], "lyric_original_text") }
    )
    backing_trigger = first_text(
      mapped["backing_rhythm_trigger"],
      descriptor.dig("record", "audio_motion_basis"),
      descriptor.dig("record", "audio_lock", "supporting_rhythm_trigger"),
      joined.map { |record| deep_values_for_key(record["data"], "backing_rhythm_trigger") },
      joined.map { |record| deep_values_for_key(record["data"], "tempo_pulse") },
      "not_applicable_no_separate_backing_rhythm_trigger"
    )
    raise Error, "#{descriptor['visual_section_id']} has no primary audio/section cue" unless primary_cue

    timing = {
      "start_seconds" => start_seconds,
      "end_seconds" => end_seconds,
      "primary_audio_section_cue" => primary_cue,
      "backing_rhythm_trigger" => backing_trigger
    }
    timing["lyric_original_text"] = lyric_original_text if lyric_original_text
    timing
  end

  def first_deep_text(joined, *keys)
    keys.each do |key|
      joined.each do |record|
        text = first_text(deep_values_for_key(record["data"], key))
        return text if text
      end
    end
    nil
  end

  def normalize_slice_status(source_status)
    text = source_status.to_s.downcase
    return "done" if %w[done ready_for_merge merged exported].include?(text)
    return "needs_founder" if text.include?("needs_founder") || text.include?("founder_review")
    return "blocked" if text.include?("blocked") || text.include?("hold") || text.include?("reject")

    "draft"
  end

  def output_paths_for(descriptor, source_path)
    row = descriptor["record"]
    values = []
    values.concat(Array(row["output_paths"]))
    values << row["output_path"] if row["output_path"].is_a?(String)
    values.concat(row["outputs"].values) if row["outputs"].is_a?(Hash)
    values.concat(row["paths"].values) if row["paths"].is_a?(Hash)
    values << row["path"] if row["path"].is_a?(String)
    paths = compact_strings(values)
    paths = [repo_relative(source_path)] if paths.empty?
    paths
  end

  def blockers_for(status, descriptor)
    return [] if status == "done" || status == "draft"

    questions = compact_strings(descriptor.dig("record", "open_questions"))
    return questions unless questions.empty?

    [status == "needs_founder" ? "Legacy slice status requires an explicit founder decision before readiness." : "Legacy slice status is blocked and requires an explicit repair record."]
  end

  def readiness_for(status)
    founder_gate = status == "needs_founder" ? "pending" : "unknown"
    {
      "schema_valid" => true,
      "revision_coherent" => true,
      "stage_ready" => false,
      "founder_gate" => founder_gate,
      "next_unit_resumable" => false,
      "basis" => {
        "schema_valid" => ["Canonical envelope and section-slice payload schemas must validate before the file is emitted."],
        "revision_coherent" => ["The canonical legacy source and explicit namespace map are content-digest locked."],
        "stage_ready" => ["Physical extraction preserves source truth but does not promote stage readiness."],
        "founder_gate" => [founder_gate == "pending" ? "The source slice explicitly requires founder review." : "No founder decision is inferred from physical extraction."],
        "next_unit_resumable" => ["A physical slice does not make the next graph-engineering unit resumable by implication."]
      }
    }
  end

  def run_root_for(source_path)
    relative = repo_relative(source_path)
    parts = Pathname.new(relative).each_filename.to_a
    if parts[0] == "runs" && parts.length >= 3
      parts[0, 3].join("/")
    else
      repo_relative(Pathname.new(source_path).expand_path.dirname)
    end
  end

  def legacy_reference(ref_id, artifact_id, path, role)
    path = Pathname.new(path).expand_path
    {
      "ref_id" => ref_id,
      "ref_type" => "legacy_snapshot",
      "artifact_id" => artifact_id,
      "path" => repo_relative(path),
      "stage_id" => nil,
      "revision" => nil,
      "content_digest" => file_digest(path),
      "role" => role
    }
  end

  def transition_payload(direction, descriptor, index, descriptors, mapping_by_visual, timing, status, blockers)
    visual_id = descriptor["visual_section_id"]
    audio_id = mapping_by_visual.fetch(visual_id).fetch("audio_section_id")
    current = { "audio_section_id" => audio_id, "visual_section_id" => visual_id }
    previous = index.zero? ? nil : descriptors[index - 1]
    following = index == descriptors.length - 1 ? nil : descriptors[index + 1]
    legacy = descriptor.dig("record", "transition_#{direction}")
    legacy = {} unless legacy.is_a?(Hash)

    if direction == "in"
      boundary_kind = previous ? "internal" : "entry"
      from = previous ? endpoint_for(previous, mapping_by_visual) : null_endpoint
      to = current
    else
      boundary_kind = following ? "internal" : "exit"
      from = current
      to = following ? endpoint_for(following, mapping_by_visual) : null_endpoint
    end

    transition_status = status == "done" ? "ready" : status
    transition_status = "draft" unless %w[ready draft blocked needs_founder].include?(transition_status)
    transition_blockers = %w[blocked needs_founder].include?(transition_status) ? blockers : []
    continuity = first_text(legacy["continuity_lock"], "legacy_gap_boundary_continuity_lock")
    boundary_values = {
      "body_or_formation_bridge" => first_text(legacy["body_or_formation_bridge"], "not_applicable_or_legacy_gap_body_bridge"),
      "composition_handoff" => first_text(descriptor.dig("record", "composition_lock"), legacy["continuity_lock"], "legacy_gap_boundary_composition_handoff"),
      "camera_or_edit_bridge" => first_text(legacy["camera_or_edit_bridge"], "legacy_gap_boundary_camera_or_edit_bridge"),
      "space_or_object_change" => first_text(legacy["space_or_object_change"], "not_applicable_or_legacy_gap_space_object_change")
    }
    if boundary_values.values.any? { |value| value.start_with?("legacy_gap", "not_applicable_or_legacy_gap") } || continuity.start_with?("legacy_gap")
      transition_status = "draft"
    end
    trigger = {
      "primary_audio_section_cue" => first_text(legacy["audio_or_lyric_trigger"], legacy["audio_or_section_trigger"], timing["primary_audio_section_cue"]),
      "backing_rhythm_trigger" => timing["backing_rhythm_trigger"]
    }
    trigger["lyric_original_text"] = timing["lyric_original_text"] if timing["lyric_original_text"]
    {
      "handoff_id" => "#{descriptor['visual_section_id'].downcase}_#{direction}_#{descriptor['source_index']}",
      "boundary_kind" => boundary_kind,
      "from" => from,
      "to" => to,
      "trigger" => trigger,
      "body_or_formation_bridge" => boundary_values["body_or_formation_bridge"],
      "composition_handoff" => boundary_values["composition_handoff"],
      "camera_or_edit_bridge" => boundary_values["camera_or_edit_bridge"],
      "space_or_object_change" => boundary_values["space_or_object_change"],
      "continuity_locks" => [continuity],
      "feedback_ref_ids" => [],
      "status" => transition_status,
      "blockers" => transition_blockers
    }
  end

  def endpoint_for(descriptor, mapping_by_visual)
    visual_id = descriptor["visual_section_id"]
    {
      "audio_section_id" => mapping_by_visual.fetch(visual_id).fetch("audio_section_id"),
      "visual_section_id" => visual_id
    }
  end

  def null_endpoint
    { "audio_section_id" => nil, "visual_section_id" => nil }
  end

  def normalized_merge_checks(descriptor)
    checks = Array(descriptor.dig("record", "merge_checks") || descriptor.dig("record", "merge_audit")).map do |check|
      MERGE_CHECK_MAP[check.to_s]
    end.compact.uniq
    checks << "source_traceability" unless checks.include?("source_traceability")
    checks << "founder_gate_preserved" unless checks.include?("founder_gate_preserved")
    checks
  end

  def build_payload(source_path, stage_id, descriptor, index, descriptors, mapping_by_visual, joined, source_ref_id)
    mapping = mapping_by_visual.fetch(descriptor["visual_section_id"])
    timing = timing_for(mapping, descriptor, joined)
    row = descriptor["record"]
    status = normalize_slice_status(row["status"])
    blockers = blockers_for(status, descriptor)
    frame_mode = first_text(row["frame_subject_mode"], first_deep_text(joined, "frame_subject_mode"))
    unless %w[member_led unit_or_group_led world_object_led environment_insert system_transition mixed_member_world].include?(frame_mode)
      raise Error, "#{descriptor['visual_section_id']} has no valid explicit frame_subject_mode"
    end
    participant_refs = compact_strings(row["participant_or_identity_refs"])
    member_owner = first_text(
      row["member_owner"],
      participant_refs.find { |value| value.match?(/\AM(?:0[1-9]|1[0-3])\z/) },
      first_deep_text(joined, "member_owner"),
      first_deep_text(joined, "member_focus")
    )
    unit_owner = first_text(row["unit_owner"], participant_refs.find { |value| !value.match?(/\AM(?:0[1-9]|1[0-3])\z/) })
    if %w[member_led mixed_member_world].include?(frame_mode) && !member_owner
      raise Error, "#{descriptor['visual_section_id']} requires an explicit member_owner for #{frame_mode}"
    end

    visual_anchor = first_text(row["visual_system_anchor"], row["object_or_space_refs"], first_deep_text(joined, "visual_system_anchor"), first_deep_text(joined, "space_or_object"))
    visible_action = first_text(row["visible_action"], row["visible_body_action"], row["non_member_screen_event"], row["visible_response"], first_deep_text(joined, "visible_action"), first_deep_text(joined, "motion_goal"))
    composition = first_text(row["composition_lock"], row["camera_composition_lock"], first_deep_text(joined, "composition"), first_deep_text(joined, "camera_treatment"))
    camera = first_text(row["camera_coverage_intent"], row["camera_space_wardrobe_decisions"], row["camera_composition_lock"], first_deep_text(joined, "camera_treatment"), first_deep_text(joined, "camera_composition_goal"), first_deep_text(joined, "required_camera_evidence"))
    camera_route_spec = row["camera_route_spec"]
    unless camera_route_spec.is_a?(Hash)
      camera_route_spec = joined.flat_map { |record| deep_values_for_key(record["data"], "camera_route_spec") }
                                .find { |value| value.is_a?(Hash) }
    end
    research_application_ids = compact_strings([
      row["research_application_ids"],
      row["reference_application_ids"],
      joined.flat_map { |record| deep_values_for_key(record["data"], "research_application_ids") },
      joined.flat_map { |record| deep_values_for_key(record["data"], "source_01_application_ids") }
    ]).select { |value| value.match?(/\AAPP_[A-Z0-9_]{2,80}\z/) }
    location = first_text(row["object_or_space_refs"], first_deep_text(joined, "space_or_object"), visual_anchor)
    visible_subject = first_text(member_owner, row["subject_focus"], first_deep_text(joined, "subject_focus"), frame_mode.tr("_", " "))
    face_or_gaze = first_text(first_deep_text(joined, "face_or_gaze"), first_deep_text(joined, "gaze"), first_deep_text(joined, "body_state"))
    face_or_gaze ||= member_owner ? "legacy_gap_face_or_gaze_lock" : "not_applicable_no_member_visible"
    wardrobe = first_text(row["wardrobe_or_material_read"], first_deep_text(joined, "wardrobe_read"), row["camera_space_wardrobe_decisions"], first_deep_text(joined, "material_read"))
    wardrobe ||= member_owner ? "legacy_gap_wardrobe_read" : "legacy_gap_material_surface_read"
    performance = first_text(
      row["performance_or_body_decision"],
      row["choreography_presence_policy"],
      member_owner ? "legacy_gap_performance_or_body_decision" : "not_applicable_non_member_screen_carrier"
    )
    section_goal = first_text(
      row["section_goal"],
      row.dig("downstream_01_transfer", "02a_core_cut_implication"),
      first_deep_text(joined, "02a_core_cut_implication"),
      row.dig("meaning_lock", "section_function"),
      first_deep_text(joined, "message_function")
    )
    section_function = first_text(row["storyline_director_function"], row.dig("meaning_lock", "section_function"), section_goal)
    visual_arc = row["space_visible_feeling_arc"].is_a?(Hash) ? row["space_visible_feeling_arc"] : {}
    visual_quality = first_text(
      row["section_visual_quality_note"],
      compact_strings([
        visual_arc["space_background_role"],
        visual_arc["visible_feeling_state"],
        visual_arc["progression_function"],
        visual_arc["adjacent_variation_note"]
      ]).join(" | "),
      "legacy_gap_section_visual_quality_note"
    )

    legacy_gap_fields = {
      "face_or_gaze" => face_or_gaze,
      "wardrobe_or_material_decision" => wardrobe,
      "performance_or_body_decision" => performance,
      "section_visual_quality_note" => visual_quality
    }.select { |_field, value| value.to_s.start_with?("legacy_gap") }.keys
    unless legacy_gap_fields.empty?
      status = "draft"
      blockers = (blockers + ["Legacy extraction has unresolved typed gaps: #{legacy_gap_fields.join(', ')}"]).uniq
    end

    required = {
      "section_goal" => section_goal,
      "section_function" => section_function,
      "visual_system_anchor" => visual_anchor,
      "visible_action" => visible_action,
      "composition_lock" => composition,
      "camera_view" => camera,
      "location" => location,
      "visible_subject" => visible_subject,
      "wardrobe_or_material_decision" => wardrobe
    }
    missing = required.select { |_key, value| value.to_s.strip.empty? }.keys
    raise Error, "#{descriptor['visual_section_id']} lacks required explicit section fields: #{missing.join(', ')}" unless missing.empty?

    direction_decisions = {
      "camera_decision" => camera,
      "space_or_object_decision" => visual_anchor,
      "wardrobe_or_material_decision" => wardrobe,
      "performance_or_body_decision" => performance
    }
    direction_decisions["camera_route_spec"] = camera_route_spec if camera_route_spec.is_a?(Hash)

    {
      "schema_version" => PAYLOAD_SCHEMA_VERSION,
      "contract_kind" => "section_slice",
      "slice_id" => "#{stage_id}:#{descriptor['visual_section_id']}",
      "stage_id" => stage_id,
      "id_namespace" => {
        "audio_section_id" => mapping["audio_section_id"],
        "source_audio_section_ids" => mapping["source_audio_section_ids"],
        "visual_section_id" => descriptor["visual_section_id"],
        "beat_ids" => (descriptor["beat_ids"] + mapping["beat_ids"]).uniq,
        "cue_ids" => (descriptor["cue_ids"] + mapping["cue_ids"]).uniq,
        "cut_ids" => descriptor["cut_ids"],
        "packet_ids" => descriptor["packet_ids"]
      },
      "source_bindings" => {
        "upstream_ref_ids" => [],
        "feedback_ref_ids" => []
      },
      "section_goal" => section_goal,
      "section_function" => section_function,
      "reference_function_transfers" => [],
      "selected_reference_fragments" => [],
      "selected_reference_application_ids" => research_application_ids,
      "timing" => timing,
      "identity_and_subject" => {
        "member_owner" => member_owner,
        "unit_owner" => unit_owner,
        "frame_subject_mode" => frame_mode,
        "visual_system_anchor" => visual_anchor
      },
      "screen_event" => {
        "visible_subject" => visible_subject,
        "location" => location,
        "visible_action" => visible_action,
        "face_or_gaze" => face_or_gaze,
        "composition_lock" => composition,
        "camera_view" => camera
      },
      "direction_decisions" => direction_decisions,
      "section_visual_quality_note" => visual_quality,
      "transition_in" => transition_payload("in", descriptor, index, descriptors, mapping_by_visual, timing, status, blockers),
      "transition_out" => transition_payload("out", descriptor, index, descriptors, mapping_by_visual, timing, status, blockers),
      "mechanical_merge" => {
        "source_ref_id" => source_ref_id,
        "source_content_digest" => file_digest(source_path),
        "record_groups" => mechanical_record_groups(descriptor, joined),
        "round_trip_policy" => "lossless_replace_at_source_locators"
      },
      "merge_contract" => {
        "canonical_artifact" => repo_relative(source_path),
        "merge_key" => descriptor["visual_section_id"],
        "sequence_index" => descriptor["source_index"],
        "required_merge_checks" => normalized_merge_checks(descriptor)
      },
      "output_paths" => output_paths_for(descriptor, source_path),
      "open_questions" => compact_strings(row["open_questions"]),
      "blockers" => blockers,
      "status" => status
    }
  end

  def build_contract(source_path, mapping_path, stage_id, descriptor, index, descriptors, mapping_by_visual, joined, owner:)
    source_path = Pathname.new(source_path).expand_path
    source_ref = legacy_reference(
      "canonical_source",
      "#{descriptor['record']['content_id'] || 'legacy'}:#{stage_id}:canonical_source",
      source_path,
      "Canonical legacy artifact snapshot used for lossless physical section extraction."
    )
    refs = [source_ref]
    if mapping_path
      refs << legacy_reference(
        "section_id_map",
        "#{descriptor['visual_section_id']}:section_id_map",
        mapping_path,
        "Explicit audio-to-visual section namespace and timing mapping; no S-code equality is inferred."
      )
    end
    payload = build_payload(source_path, stage_id, descriptor, index, descriptors, mapping_by_visual, joined, source_ref["ref_id"])
    payload["source_bindings"]["upstream_ref_ids"] = refs.map { |ref| ref["ref_id"] }
    content_id = load_structured(source_path)["content_id"].to_s
    artifact_id = [content_id, stage_id, descriptor["visual_section_id"]].reject(&:empty?).join(":")
    {
      "schema_version" => ENVELOPE_SCHEMA_VERSION,
      "envelope" => {
        "artifact_id" => artifact_id,
        "artifact_kind" => "harness_section_slice",
        "run" => run_root_for(source_path),
        "stage_id" => stage_id,
        "owner" => owner,
        "authored_at" => source_path.mtime.utc.iso8601(6),
        "revision" => 1,
        "content_digest" => canonical_digest(payload),
        "parent" => {
          "path" => nil,
          "revision" => nil,
          "content_digest" => nil
        },
        "payload_schema" => PAYLOAD_SCHEMA_PATH,
        "upstream_refs" => refs,
        "feedback_refs" => [],
        "invalidates" => [],
        "readiness" => readiness_for(payload["status"])
      },
      "payload" => payload
    }
  end

  def extract(source_path, output_dir:, mapping_path:, stage_token: nil, section_ids: [], owner: "codex")
    source_path = Pathname.new(source_path).expand_path
    output_dir = Pathname.new(output_dir).expand_path
    mapping_path = Pathname.new(mapping_path).expand_path if mapping_path
    raise Error, "--section-map is required for legacy artifacts without explicit audio_section_id" unless mapping_path
    if output_dir.exist? && output_dir.children.any?
      raise Error, "output directory must not exist or must be empty: #{output_dir}"
    end

    document = load_structured(source_path)
    stage_id = normalize_stage(stage_token) || infer_stage(document)
    all_descriptors = descriptors_for(document, stage_id)
    mappings = mapping_entries(mapping_path)
    mapping_by_visual = mapping_index(mappings)
    require_explicit_mappings!(all_descriptors, mapping_by_visual)
    selected_ids = compact_strings(section_ids)
    descriptors = if selected_ids.empty?
                    all_descriptors
                  else
                    all_descriptors.select { |descriptor| selected_ids.include?(descriptor["visual_section_id"]) }
                  end
    found_ids = descriptors.map { |descriptor| descriptor["visual_section_id"] }
    missing_ids = selected_ids - found_ids
    raise Error, "requested visual sections were not found: #{missing_ids.join(', ')}" unless missing_ids.empty?
    raise Error, "no section descriptors selected" if descriptors.empty?

    FileUtils.mkdir_p(output_dir.to_s)
    shard_rows = []
    descriptors.each do |descriptor|
      timeline_index = all_descriptors.index(descriptor)
      joined = joined_records_for(document, stage_id, descriptor)
      contract = build_contract(source_path, mapping_path, stage_id, descriptor, timeline_index, all_descriptors, mapping_by_visual, joined, owner: owner)
      shard_path = output_dir.join("#{descriptor['visual_section_id'].gsub(/[^A-Za-z0-9_-]/, '_')}.yaml")
      validator_report = write_validated_contract(shard_path, contract)
      shard_rows << {
        "path" => shard_path.basename.to_s,
        "audio_section_id" => contract.dig("payload", "id_namespace", "audio_section_id"),
        "visual_section_id" => descriptor["visual_section_id"],
        "beat_ids" => contract.dig("payload", "id_namespace", "beat_ids"),
        "cut_ids" => contract.dig("payload", "id_namespace", "cut_ids"),
        "packet_ids" => contract.dig("payload", "id_namespace", "packet_ids"),
        "revision" => contract.dig("envelope", "revision"),
        "content_digest" => contract.dig("envelope", "content_digest"),
        "status" => contract.dig("payload", "status"),
        "validator_status" => validator_report["status"]
      }
    end

    manifest = {
      "schema_version" => MANIFEST_SCHEMA_VERSION,
      "stage_id" => stage_id,
      "source_artifact" => {
        "path" => repo_relative(source_path),
        "content_digest" => file_digest(source_path)
      },
      "section_map" => {
        "path" => repo_relative(mapping_path),
        "content_digest" => file_digest(mapping_path),
        "mapping_policy" => "explicit_only_no_same_code_inference"
      },
      "section_count" => shard_rows.length,
      "shards" => shard_rows,
      "merge_policy" => {
        "source_digest_must_match" => true,
        "lossless_source_locator_replacement" => true,
        "canonical_source_mutation_allowed" => false
      }
    }
    manifest_path = output_dir.join("manifest.yaml")
    atomic_write(manifest_path, dump_structured(manifest, manifest_path))
    {
      "ok" => true,
      "stage_id" => stage_id,
      "source_artifact" => repo_relative(source_path),
      "output_dir" => output_dir.to_s,
      "manifest" => manifest_path.to_s,
      "section_count" => shard_rows.length,
      "shards" => shard_rows
    }
  end

  def shard_paths(target)
    target = Pathname.new(target).expand_path
    raise Error, "shard target not found: #{target}" unless target.exist?
    return [target] if target.file?

    target.children.select do |path|
      path.file? && %w[.yaml .yml .json].include?(path.extname.downcase) && path.basename.to_s != "manifest.yaml"
    end.sort_by(&:to_s)
  end

  def source_ref_for(contract)
    source_ref_id = contract.dig("payload", "mechanical_merge", "source_ref_id").to_s
    Array(contract.dig("envelope", "upstream_refs")).find do |ref|
      ref.is_a?(Hash) && ref["ref_id"].to_s == source_ref_id
    end
  end

  def group_records_from_source(source_document, group)
    container = value_at(source_document, group["source_container_path"])
    case group["source_container_kind"]
    when "array"
      raise ValidationError, "mechanical container is not an array: #{group['source_container_path'].join('.')}" unless container.is_a?(Array)
      Array(group["source_record_indexes"]).map do |index|
        raise ValidationError, "source record index is out of range: #{index}" unless index.is_a?(Integer) && index >= 0 && index < container.length
        container[index]
      end
    when "object"
      raise ValidationError, "mechanical container is not an object: #{group['source_container_path'].join('.')}" unless container.is_a?(Hash)
      Array(group["source_record_keys"]).map do |key|
        raise ValidationError, "source record key is missing: #{key}" unless container.key?(key)
        container[key]
      end
    when "root"
      [source_document]
    else
      raise ValidationError, "unsupported source_container_kind: #{group['source_container_kind']}"
    end
  end

  def expected_record_ids(records, group)
    ids = []
    records.each_with_index do |record, index|
      fallback = if group["source_container_kind"] == "array"
                   "record_#{Array(group['source_record_indexes'])[index]}"
                 else
                   Array(group["source_record_keys"])[index]
                 end
      candidate = record_identifier(record, fallback)
      candidate = "#{candidate}__#{index}" if ids.include?(candidate)
      ids << candidate
    end
    ids
  end

  def validate_mechanical_contract(contract)
    errors = []
    source_ref = source_ref_for(contract)
    if source_ref.nil?
      errors << "mechanical source_ref_id does not resolve to an upstream ref"
      return errors
    end
    source_path = resolve_path(source_ref["path"])
    if !source_path.file?
      errors << "mechanical source path is not readable: #{source_path}"
      return errors
    end
    actual_digest = file_digest(source_path)
    expected_digest = contract.dig("payload", "mechanical_merge", "source_content_digest").to_s
    errors << "mechanical source digest drifted" unless actual_digest == expected_digest && expected_digest == source_ref["content_digest"].to_s
    source_document = load_structured(source_path)
    Array(contract.dig("payload", "mechanical_merge", "record_groups")).each do |group|
      begin
        source_records = group_records_from_source(source_document, group)
        embedded = Array(group["embedded_records"])
        errors << "#{group['group_id']} source locator count does not match embedded records" unless source_records.length == embedded.length
        ids = expected_record_ids(source_records, group)
        errors << "#{group['group_id']} source_record_ids do not match source locators" unless ids == Array(group["source_record_ids"])
      rescue ValidationError => e
        errors << "#{group['group_id']}: #{e.message}"
      end
    end
    errors
  end

  def locator_keys(contract)
    Array(contract.dig("payload", "mechanical_merge", "record_groups")).each_with_object([]) do |group, result|
      path = Array(group["source_container_path"]).join(".")
      if group["source_container_kind"] == "array"
        Array(group["source_record_indexes"]).each { |index| result << "#{path}|array|#{index}" }
      elsif group["source_container_kind"] == "object"
        Array(group["source_record_keys"]).each { |key| result << "#{path}|object|#{key}" }
      else
        result << "#{path}|root"
      end
    end
  end

  def validate_set(target)
    paths = shard_paths(target)
    reports = []
    documents = []
    paths.each do |path|
      contract = load_structured(path)
      canonical = run_contract_validator(path)
      mechanical_errors = validate_mechanical_contract(contract)
      reports << {
        "path" => path.to_s,
        "artifact_id" => contract.dig("envelope", "artifact_id"),
        "stage_id" => contract.dig("envelope", "stage_id"),
        "audio_section_id" => contract.dig("payload", "id_namespace", "audio_section_id"),
        "visual_section_id" => contract.dig("payload", "id_namespace", "visual_section_id"),
        "ok" => canonical["status"] == "pass" && mechanical_errors.empty?,
        "canonical_errors" => Array(canonical["errors"]),
        "mechanical_errors" => mechanical_errors,
        "warnings" => Array(canonical["warnings"])
      }
      documents << [path, contract]
    end

    cross_errors = []
    source_keys = documents.map do |_path, contract|
      ref = source_ref_for(contract) || {}
      [ref["path"], ref["content_digest"], contract.dig("envelope", "stage_id")]
    end.uniq
    cross_errors << "all shards in one set must share canonical source path, digest, and stage" if source_keys.length > 1

    seen_sections = {}
    seen_locators = {}
    documents.each do |path, contract|
      visual_id = contract.dig("payload", "id_namespace", "visual_section_id").to_s
      cross_errors << "visual section #{visual_id} repeats in #{seen_sections[visual_id]} and #{path}" if seen_sections[visual_id]
      seen_sections[visual_id] = path
      locator_keys(contract).each do |locator|
        cross_errors << "mechanical locator #{locator} repeats in #{seen_locators[locator]} and #{path}" if seen_locators[locator]
        seen_locators[locator] = path
      end
    end

    {
      "ok" => reports.all? { |report| report["ok"] } && cross_errors.empty?,
      "shard_count" => reports.length,
      "reports" => reports,
      "cross_slice_errors" => cross_errors
    }
  end

  def apply_group!(document, group)
    container = value_at(document, group["source_container_path"])
    embedded = Array(group["embedded_records"])
    case group["source_container_kind"]
    when "array"
      indexes = Array(group["source_record_indexes"])
      raise ValidationError, "array merge count mismatch" unless indexes.length == embedded.length && container.is_a?(Array)
      indexes.each_with_index { |index, item_index| container[index] = deep_copy(embedded[item_index]) }
    when "object"
      keys = Array(group["source_record_keys"])
      raise ValidationError, "object merge count mismatch" unless keys.length == embedded.length && container.is_a?(Hash)
      keys.each_with_index { |key, item_index| container[key] = deep_copy(embedded[item_index]) }
    when "root"
      raise ValidationError, "root merge requires one embedded record" unless embedded.length == 1 && embedded.first.is_a?(Hash)
      document.replace(deep_copy(embedded.first))
    else
      raise ValidationError, "unsupported source_container_kind: #{group['source_container_kind']}"
    end
  end

  def ensure_output_is_not_source!(source_path, output_path)
    source = Pathname.new(source_path).expand_path
    output = Pathname.new(output_path).expand_path
    raise Error, "refusing to overwrite the canonical source artifact: #{source}" if source == output
  end

  def merge(source_path, shards_target:, output_path:, force: false)
    source_path = Pathname.new(source_path).expand_path
    output_path = Pathname.new(output_path).expand_path
    ensure_output_is_not_source!(source_path, output_path)
    validation = validate_set(shards_target)
    unless validation["ok"]
      raise ValidationError, "section slice validation failed: #{validation.to_json}"
    end

    documents = shard_paths(shards_target).map { |path| [path, load_structured(path)] }
    source_ref = source_ref_for(documents.first[1])
    raise ValidationError, "source argument does not match mechanical source ref" unless resolve_path(source_ref["path"]) == source_path
    raise ValidationError, "source digest does not match mechanical source ref" unless file_digest(source_path) == source_ref["content_digest"]

    source_document = load_structured(source_path)
    merged = deep_copy(source_document)
    ordered = documents.sort_by { |_path, contract| contract.dig("payload", "merge_contract", "sequence_index").to_i }
    ordered.each do |_path, contract|
      Array(contract.dig("payload", "mechanical_merge", "record_groups")).each do |group|
        apply_group!(merged, group)
      end
    end
    output_text = dump_structured(merged, output_path)
    atomic_write(output_path, output_text, force: force)
    {
      "ok" => true,
      "stage_id" => documents.first[1].dig("envelope", "stage_id"),
      "source_artifact" => repo_relative(source_path),
      "output" => output_path.to_s,
      "merged_visual_section_ids" => ordered.map { |_path, contract| contract.dig("payload", "id_namespace", "visual_section_id") },
      "shard_count" => ordered.length,
      "semantic_round_trip" => merged == source_document,
      "merge_source" => "payload.mechanical_merge.record_groups",
      "source_sha256" => file_digest(source_path),
      "output_sha256" => file_digest(output_path),
      "output_canonical_digest" => canonical_digest(merged)
    }
  end

  def seal_revision(draft_path, parent_path:, output_path:, authored_at: nil, force: false)
    draft_path = Pathname.new(draft_path).expand_path
    parent_path = Pathname.new(parent_path).expand_path
    output_path = Pathname.new(output_path).expand_path
    raise Error, "draft and parent must be distinct files so revision lineage remains readable" if draft_path == parent_path
    raise Error, "output must be distinct from draft and parent" if output_path == draft_path || output_path == parent_path

    parent_report = run_contract_validator(parent_path)
    raise ValidationError, "parent contract is invalid: #{Array(parent_report['errors']).join('; ')}" unless parent_report["status"] == "pass"
    draft = load_structured(draft_path)
    parent = load_structured(parent_path)
    raise ValidationError, "draft artifact_id must match parent artifact_id" unless draft.dig("envelope", "artifact_id") == parent.dig("envelope", "artifact_id")
    raise ValidationError, "draft stage_id must match parent stage_id" unless draft.dig("envelope", "stage_id") == parent.dig("envelope", "stage_id")

    draft["schema_version"] = ENVELOPE_SCHEMA_VERSION
    draft["envelope"]["revision"] = parent.dig("envelope", "revision").to_i + 1
    draft["envelope"]["parent"] = {
      "path" => repo_relative(parent_path),
      "revision" => parent.dig("envelope", "revision"),
      "content_digest" => parent.dig("envelope", "content_digest")
    }
    draft["envelope"]["authored_at"] = authored_at || Time.now.utc.iso8601(6)
    draft["envelope"]["content_digest"] = canonical_digest(draft["payload"])
    draft["envelope"]["readiness"]["schema_valid"] = true
    draft["envelope"]["readiness"]["revision_coherent"] = true
    report = write_validated_contract(output_path, draft, force: force)
    {
      "ok" => true,
      "output" => output_path.to_s,
      "artifact_id" => draft.dig("envelope", "artifact_id"),
      "revision" => draft.dig("envelope", "revision"),
      "content_digest" => draft.dig("envelope", "content_digest"),
      "validator_status" => report["status"]
    }
  end

  def print_result(result, json: false)
    puts(json ? JSON.pretty_generate(result) : YAML.dump(result))
  end

  def usage
    <<~USAGE
      usage:
        ruby scripts/idol_harness_sections.rb inspect SOURCE [--stage TOKEN] [--json]
        ruby scripts/idol_harness_sections.rb extract SOURCE --section-map PATH --output-dir DIR [--sections S00,S01] [--stage TOKEN] [--owner codex|grok] [--json]
        ruby scripts/idol_harness_sections.rb validate SHARD_OR_DIR [--json]
        ruby scripts/idol_harness_sections.rb seal DRAFT --parent PREVIOUS --output NEW [--authored-at ISO8601] [--force] [--json]
        ruby scripts/idol_harness_sections.rb merge SOURCE --shards SHARD_OR_DIR --output PATH [--force] [--json]

      Safety and identity rules:
        inspect and validate are read-only. extract requires an explicit audio↔visual
        namespace map and an explicit empty output directory. Equal-looking S-codes are
        never treated as the same namespace by inference. Every physical file uses the
        canonical envelope + section-slice payload contracts. merge always refuses
        output==SOURCE and applies only mechanical_merge source locators. seal creates a
        new revision file and never overwrites its parent. No command infers founder,
        paid-generation, external-action, or publication approval.
    USAGE
  end

  def run(argv)
    command = argv.shift
    raise Error, usage unless %w[inspect extract validate seal merge].include?(command)

    options = { json: false, stage: nil, sections: [], force: false, owner: "codex" }
    parser = OptionParser.new do |opts|
      opts.on("--stage TOKEN", String) { |value| options[:stage] = value }
      opts.on("--section-map PATH", String) { |value| options[:section_map] = value }
      opts.on("--output-dir DIR", String) { |value| options[:output_dir] = value }
      opts.on("--sections IDS", String) { |value| options[:sections] = value.split(",") }
      opts.on("--shards PATH", String) { |value| options[:shards] = value }
      opts.on("--parent PATH", String) { |value| options[:parent] = value }
      opts.on("--output PATH", String) { |value| options[:output] = value }
      opts.on("--authored-at ISO8601", String) { |value| options[:authored_at] = value }
      opts.on("--owner OWNER", String) { |value| options[:owner] = value.to_s.strip }
      opts.on("--force") { options[:force] = true }
      opts.on("--json") { options[:json] = true }
      opts.on("-h", "--help") { puts usage; return 0 }
    end
    parser.parse!(argv)
    target = argv.shift
    raise Error, usage if target.to_s.empty? || !argv.empty?

    result = case command
             when "inspect"
               inspect_artifact(target, stage_token: options[:stage])
             when "extract"
               raise Error, "--output-dir is required" if options[:output_dir].to_s.empty?
               raise Error, "--section-map is required" if options[:section_map].to_s.empty?
               raise Error, "--owner must be codex or grok for graph-engineering section extraction" unless %w[codex grok].include?(options[:owner])
               extract(target, output_dir: options[:output_dir], mapping_path: options[:section_map], stage_token: options[:stage], section_ids: options[:sections], owner: options[:owner])
             when "validate"
               validate_set(target)
             when "seal"
               raise Error, "--parent is required" if options[:parent].to_s.empty?
               raise Error, "--output is required" if options[:output].to_s.empty?
               seal_revision(target, parent_path: options[:parent], output_path: options[:output], authored_at: options[:authored_at], force: options[:force])
             when "merge"
               raise Error, "--shards is required" if options[:shards].to_s.empty?
               raise Error, "--output is required" if options[:output].to_s.empty?
               merge(target, shards_target: options[:shards], output_path: options[:output], force: options[:force])
             end
    print_result(result, json: options[:json])
    result.is_a?(Hash) && result["ok"] == false ? 1 : 0
  rescue OptionParser::ParseError, Error => e
    warn e.message
    2
  end
end

if $PROGRAM_NAME == __FILE__
  exit IdolHarnessSections.run(ARGV)
end
