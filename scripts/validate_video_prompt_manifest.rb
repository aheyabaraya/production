#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "lib/idol_grok_video_execution_package"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "video-prompt-manifest.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_video_prompt_storyboard_assist.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")
ACTIVE_SCHEMA_VERSION = "idol_video_prompt_manifest.v8"
NONSECRET_CHILD_ENV = {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil}.freeze

options = {root: ROOT, json: false, max_errors: 60}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_video_prompt_manifest.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!
artifact_arg = ARGV.shift
abort "video-prompt manifest path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
  raise TypeError, "document must be an object" unless value.is_a?(Hash)
  value
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  (path.absolute? ? path : root.join(path)).expand_path.cleanpath
end

def inside?(path, root)
  relative = path.relative_path_from(root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
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

def validate_ref(row, label, root, errors)
  unless row.is_a?(Hash)
    errors << "#{label} must be a path and SHA-256 object"
    return nil
  end
  path = resolve_path(row["path"], root)
  unless inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository: #{row['path']}"
    return nil
  end
  errors << "#{label} SHA-256 is stale" unless row["sha256"] == Digest::SHA256.file(path).hexdigest
  path
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
document = {}
unless inside?(artifact, root) && artifact.file?
  errors << "video-prompt manifest is missing or outside the repository: #{artifact_arg}"
else
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot parse video-prompt manifest: #{error.message}"
  end
  stdout, stderr, status = Open3.capture3(NONSECRET_CHILD_ENV, PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, artifact.to_s, chdir: ROOT.to_s)
  errors << "JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

if document.any?
  errors << "only #{ACTIVE_SCHEMA_VERSION} is active" unless document["schema_version"] == ACTIVE_SCHEMA_VERSION
  refs = %w[source_front_planning source_01_direction source_master_storyboard source_02a_context_review source_prompt_packets source_production_cut_review source_audio_branch_cut_placement source_storyboard_assist].to_h do |key|
    [key, validate_ref(document[key], key, root, errors)]
  end
  assist = refs["source_storyboard_assist"] ? load_mapping(refs["source_storyboard_assist"]) : {}
  if refs["source_storyboard_assist"]
    stdout, stderr, status = Open3.capture3(NONSECRET_CHILD_ENV, RbConfig.ruby, STORYBOARD_VALIDATOR.to_s, "--root", root.to_s, refs["source_storyboard_assist"].to_s, chdir: ROOT.to_s)
    unless status.success?
      detail = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
      errors << "source storyboard assist failed active validation: #{detail}"
    end
  end
  errors << "source storyboard assist must be passed active v4" unless assist["schema_version"] == "idol_video_prompt_storyboard_assist.v4" && assist["status"] == "passed"
  %w[source_front_planning source_01_direction source_master_storyboard source_02a_context_review source_prompt_packets source_production_cut_review source_audio_branch_cut_placement].each do |key|
    errors << "#{key} differs from the passed storyboard assist" unless document[key].to_h.slice("path", "sha256") == assist[key].to_h.slice("path", "sha256")
  end
  errors << "return recipient must be CDD" unless document["return_recipient_role"] == "creative_development_director"
  policy = document["prompt_authoring_policy"].to_h
  unless policy["temporal_camera_owner"] == "03V_after_passed_production_cut_review_and_audio_production_cut_placement"
    errors << "temporal camera ownership must begin only after passed Production Cut review and Audio Production Cut Placement"
  end
  errors << "edit ownership must remain in 04 after passed 03V playback" unless policy["edit_owner"] == "04_after_passed_03V_playback"
  output_root = resolve_path(document["canonical_video_prompt_output_root"], root)
  errors << "canonical_video_prompt_output_root must remain inside the repository" unless inside?(output_root, root)
  boards = Array(assist["boards"]).to_h { |board| [board["storyboard_id"], board] }
  first_board = boards.values.first.to_h
  master_storyboard = refs["source_master_storyboard"] ? load_mapping(refs["source_master_storyboard"]) : {}
  production_review = refs["source_production_cut_review"] ? load_mapping(refs["source_production_cut_review"]) : {}
  placement = refs["source_audio_branch_cut_placement"] ? load_mapping(refs["source_audio_branch_cut_placement"]) : {}
  errors << "source Production Cut review must be active passed v2" unless production_review["schema_version"] == "idol-production-cut-review.v2" && production_review["status"] == "passed"
  expected_successions = Array(production_review["section_cohort_successions"])
  errors << "section_cohort_successions must exact-copy the Production Cut review" unless document["section_cohort_successions"] == expected_successions
  successor_by_cohort = expected_successions.to_h { |row| [row.to_h["section_cohort_id"].to_s, row.to_h] }
  cohort_by_section = {}
  expected_successions.each do |row|
    cohort_id = row.to_h["section_cohort_id"].to_s
    Array(row.to_h["section_ids"]).each do |section_id|
      errors << "Production Cut review section #{section_id} maps to multiple cohorts" if cohort_by_section.key?(section_id.to_s) && cohort_by_section[section_id.to_s] != cohort_id
      cohort_by_section[section_id.to_s] = cohort_id
    end
  end
  production_row_by_id = Array(production_review["production_cut_reviews"]).to_h do |row|
    [row.to_h["production_cut_id"].to_s, row.to_h]
  end
  storyline_lineage = document["storyline_lineage_projection"].to_h
  expected_storyline_lineage = master_storyboard.dig("storyline_lineage_projection", "projected_value")
  errors << "storyline_lineage_projection source pointer is not canonical" unless storyline_lineage["source_json_pointer"] == "/storyline_lineage_projection/projected_value"
  errors << "storyline_lineage_projection source hash is stale" unless storyline_lineage["source_value_sha256"] == Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(expected_storyline_lineage)))
  errors << "storyline_lineage_projection must exact-copy the complete 02A lineage" unless storyline_lineage["projected_value"] == expected_storyline_lineage
  screen_progression = document["screen_progression_projection"].to_h
  expected_screen_progression = master_storyboard.dig("screen_progression_map_projection", "projected_value")
  errors << "screen_progression_projection source pointer is not canonical" unless screen_progression["source_json_pointer"] == "/screen_progression_map_projection/projected_value"
  errors << "screen_progression_projection source hash is stale" unless screen_progression["source_value_sha256"] == Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(expected_screen_progression)))
  errors << "screen_progression_projection must exact-copy the complete 02A map" unless screen_progression["projected_value"] == expected_screen_progression
  storyline = document["storyline_projection"].to_h
  errors << "storyline_projection.active_storyline_version_id differs from passed storyboard" unless storyline["active_storyline_version_id"] == first_board.dig("active_storyline_binding", "active_version_id")
  errors << "storyline_projection.active_storyline_full_text_sha256 differs from passed storyboard" unless storyline["active_storyline_full_text_sha256"] == first_board.dig("active_storyline_binding", "active_full_text_sha256")
  errors << "storyline_projection.screen_progression_map_id differs from passed storyboard" unless storyline["screen_progression_map_id"] == first_board.dig("screen_progression_binding", "screen_progression_map_id")
  cue_ids = []
  job_modes = {}
  Array(document["cues"]).each_with_index do |cue, index|
    label = "cues[#{index}]"
    cue_id = cue["cue_id"].to_s
    errors << "#{label}.cue_id must be unique" if cue_ids.include?(cue_id)
    cue_ids << cue_id
    board = boards[cue["storyboard_id"]]
    if board.nil?
      errors << "#{label}.storyboard_id is not present in passed assist"
      next
    end
    %w[section_id major_scene_id core_cut_id active_storyline_passage_pointer active_storyline_binding selected_sequence_composition_id sequence_flow_reading_sha256 selected_sequence_binding major_scene_binding screen_progression_node_ids screen_progression_binding selected_core_reference_binding_ids].each do |key|
      errors << "#{label}.#{key} differs from storyboard" unless cue[key] == board[key]
    end
    errors << "#{label}.active_storyline_version_id differs from storyboard" unless cue["active_storyline_version_id"] == board.dig("active_storyline_binding", "active_version_id")
    errors << "#{label}.screen_progression_map_id differs from storyboard" unless cue["screen_progression_map_id"] == board.dig("screen_progression_binding", "screen_progression_map_id")
    errors << "#{label}.screen_progression_node_id must be the first exact storyboard node" unless cue["screen_progression_node_id"] == Array(board["screen_progression_node_ids"]).first
    errors << "#{label}.selected_core_reference_binding_id must be the first exact storyboard Core reference" unless cue["selected_core_reference_binding_id"] == Array(board["selected_core_reference_binding_ids"]).first
    errors << "#{label}.selected_sequence_unit_ids differs from storyboard" unless cue["selected_sequence_unit_ids"] == board["selected_sequence_unit_ids"]
    expected_cohort_id = cohort_by_section[board["section_id"].to_s]
    errors << "#{label}.section_cohort_id must exact-carry the Production Cut review cohort" unless !expected_cohort_id.to_s.empty? && cue["section_cohort_id"].to_s == expected_cohort_id
    board_sources = Array(board["source_production_cut_images"])
    sources = Array(cue["source_production_cut_images"])
    projection_fields = %w[production_cut_id production_cut_type parent_core_cut_id packet_id path sha256 pixel_review_status source_production_cut_review source_02a_cut section_id major_scene_id active_storyline_version_id screen_progression_node_id scene_phase_context primary_audio_cue sequence_phase_binding_ids core_reference_binding_id screen_job_binding]
    board_projection = board_sources.map do |source|
      projected = source.slice(*projection_fields)
      review_row = production_row_by_id[source["production_cut_id"].to_s]
      errors << "#{label} names a Production Cut missing from the active review" if review_row.nil?
      projected["section_cohort_id"] = review_row.to_h["section_cohort_id"]
      errors << "#{label} source Production Cut crosses its section cohort" unless projected["section_cohort_id"].to_s == expected_cohort_id.to_s
      projected
    end
    errors << "#{label} source Production Cut images differ from passed storyboard order" unless sources == board_projection
    expected_screen_job = sources.map { |source| source.dig("screen_job_binding", "value") }.join(" -> ")
    errors << "#{label}.core_branch_screen_job differs from exact 02A screen jobs" unless cue["core_branch_screen_job"] == expected_screen_job
    errors << "#{label}.source_image_ids must exact-project source order" unless cue["source_image_ids"] == sources.map { |source| source["production_cut_id"] }
    errors << "#{label}.source_pixel_hashes must exact-project source order" unless cue["source_pixel_hashes"] == sources.map { |source| source["sha256"] }
    prompt = cue["prompt_text"].to_s
    errors << "#{label}.prompt_rewrite_policy must be forbidden" unless cue["prompt_rewrite_policy"] == "forbidden"
    execution = cue.fetch("grok_execution", {})
    errors << "#{label} execution cohort must equal the cue cohort" unless execution["section_cohort_id"].to_s == expected_cohort_id.to_s
    source = sources.find { |row| row["production_cut_id"] == execution["source_production_cut_id"] }
    unless source && execution["source_production_cut_type"] == source["production_cut_type"] && execution["source_image_path"] == source["path"] && execution["source_image_sha256"] == source["sha256"]
      errors << "#{label} execution source must be one exact passed Production Cut from the board"
    end
    errors << "#{label} execution must use exactly one source frame" unless execution["source_image_frame_count"] == 1
    errors << "#{label} prompt hash must match exact 03V prompt bytes" unless execution["prompt_sha256"] == Digest::SHA256.hexdigest(prompt)
    errors << "#{label} direct image-to-video remains forbidden before passed 03V" unless execution["direct_image_to_video"] == "forbidden" && execution["source_stage"] == "passed_03v"
    errors << "#{label} automatic fallback must be none" unless execution["automatic_fallback"] == "none"
    begin
      IdolGrokVideoExecutionPackage.registered_video_lane!(root: root, execution: execution)
      IdolGrokVideoExecutionPackage.ordered_inputs!(root: root, cue: cue, execution: execution, placement: placement, production_review: production_review)
    rescue IdolGrokVideoExecutionPackage::ContractError => error
      errors << "#{label} #{error.message}"
    end
    tool = execution["selected_tool"]
    additional = Array(execution["additional_reference_image_ids"])
    selection = execution["founder_reference_selection"]
    if tool == "image_to_video"
      errors << "#{label} image_to_video must not carry additional references or Founder multi-ref selection" unless additional.empty? && selection.nil?
    elsif tool == "reference_to_video"
      expected_ids = [execution["source_production_cut_id"]] + additional
      available_ids = sources.map { |row| row["production_cut_id"] }
      errors << "#{label} reference_to_video references must be ordered board Production Cuts" unless expected_ids.length.between?(2, 3) && (expected_ids - available_ids).empty? && expected_ids.uniq == expected_ids
      unless selection.is_a?(Hash) && selection["founder_authored"] == true && selection["selected_image_ids_in_order"] == expected_ids
        errors << "#{label} reference_to_video requires exact Founder-selected image IDs and order"
      end
    end
    attached_count = if tool == "image_to_video"
                       1
                     elsif tool == "reference_to_video"
                       ([execution["source_production_cut_id"]] + additional).length
                     else
                       0
                     end
    IdolGrokVideoExecutionPackage.unattached_execution_image_slots(prompt, attached_count).each do |slot|
      errors << "#{label} execution prompt names unattached #{slot}; do not rewrite, HOLD"
    end
    job_id = execution["video_job_id"].to_s
    pass = execution["resolution_pass"]
    if pass == "480p_test"
      errors << "#{label} 480p test must request 480p and have no upstream playback review" unless execution["requested_resolution"] == "480p" && execution["source_480p_playback_review"].nil?
    elsif pass == "720p_candidate"
      review = execution["source_480p_playback_review"]
      unless execution["requested_resolution"] == "720p" && review.is_a?(Hash) && review["video_job_id"] == job_id && review["decision"] == "pass" && review["reviewer_role"] == "creative_development_director" && review["requested_resolution"] == review["observed_resolution"]
        errors << "#{label} 720p candidate requires same-job passed CDD 480p playback review without resolution mismatch"
      end
      validate_ref({"path" => review["playback_review_record_path"], "sha256" => review["playback_review_record_sha256"]}, "#{label}.source_480p_playback_review", root, errors) if review.is_a?(Hash)
    end
    job_modes[job_id] ||= []
    job_modes[job_id] << pass
  end
  Array(document["section_shards"]).each_with_index do |shard, index|
    expected_cohort_id = cohort_by_section[shard["section_id"].to_s]
    successor = successor_by_cohort[expected_cohort_id].to_h
    unless !expected_cohort_id.to_s.empty? &&
           shard["section_cohort_id"].to_s == expected_cohort_id &&
           shard["planning_cdd_lane_id"].to_s == successor["planning_cdd_lane_id"].to_s &&
           shard["production_cdd_lane_id"].to_s == successor["production_cdd_lane_id"].to_s &&
           shard["cohort_carry_policy"].to_s == successor["carry_policy"].to_s
      errors << "section_shards[#{index}] must exact-carry its CDD-P3-Ci to CDD-V-Ci cohort successor"
    end
    unknown = Array(shard["cue_ids"]) - cue_ids
    errors << "section_shards[#{index}] names unknown cue IDs: #{unknown.join(', ')}" unless unknown.empty?
    Array(shard["output_prompt_paths"]).each do |path|
      resolved = resolve_path(path, root)
      errors << "section_shards[#{index}] output prompt path must remain under canonical output root" unless inside?(resolved, output_root)
    end
    shard_cues = Array(document["cues"]).select { |cue| Array(shard["cue_ids"]).include?(cue["cue_id"]) }
    errors << "section_shards[#{index}] mixes cue section or cohort ownership" unless shard_cues.all? { |cue| cue["section_id"] == shard["section_id"] && cue["section_cohort_id"] == shard["section_cohort_id"] }
  end
  shard_cue_ids = Array(document["section_shards"]).flat_map { |shard| Array(shard["cue_ids"]) }
  errors << "section shards must exact-cover all cues once" unless shard_cue_ids == cue_ids && shard_cue_ids.uniq == shard_cue_ids
end

result = {"ok" => errors.empty?, "schema_version" => document["schema_version"], "cue_count" => Array(document["cues"]).length, "errors" => errors.first(options[:max_errors])}
puts(options[:json] ? JSON.pretty_generate(result) : (errors.empty? ? "OK: active 03V Core/Branch video prompt manifest is valid" : errors.map { |error| "ERROR: #{error}" }.join("\n")))
exit(errors.empty? ? 0 : 1)
