#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path

SOURCE_SPECS = {
  "master_storyboard" => {
    default: "02A-master-storyboard.yaml",
    validator: "scripts/validate_master_storyboard.rb",
    root_option: true
  },
  "prompt_packets" => {
    default: "02B-prompt-packets.yaml",
    validator: "scripts/validate_02b_imagegen_contract.rb",
    root_option: false
  },
  "production_cut_review" => {
    default: "03-production-cut-review.yaml",
    validator: "scripts/validate_production_cut_review.rb",
    root_option: true
  },
  "audio_branch_cut_placement" => {
    default: "03V-audio-branch-cut-placement.yaml",
    validator: "scripts/validate_audio_branch_cut_placement.rb",
    root_option: true,
    extra_args: ["--require-ready"]
  },
  "storyboard_assist" => {
    default: "03V-storyboard-assist.yaml",
    validator: "scripts/validate_video_prompt_storyboard_assist.rb",
    root_option: true
  }
}.freeze

options = {
  root: ROOT,
  run: nil,
  output: nil,
  request_output: nil,
  write: false,
  json: true,
  sources: {}
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prepare_video_prompt_authoring.rb RUN_ROOT [options]"
  opts.on("--run PATH", "Run root. Alternative to positional RUN_ROOT.") { |value| options[:run] = value }
  opts.on("--root PATH", "Repository root used to resolve and hash sources.") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--master-storyboard PATH", "Explicit active 02A source.") { |value| options[:sources]["master_storyboard"] = value }
  opts.on("--prompt-packets PATH", "Explicit active 02B source.") { |value| options[:sources]["prompt_packets"] = value }
  opts.on("--production-cut-review PATH", "Explicit passed Official Core/Branch Production Cut review.") { |value| options[:sources]["production_cut_review"] = value }
  opts.on("--generated-branch-cut-review PATH", "Legacy alias for --production-cut-review.") { |value| options[:sources]["production_cut_review"] = value }
  opts.on("--audio-branch-cut-placement PATH", "Explicit ready Audio Production-Cut Placement (legacy option name retained).") { |value| options[:sources]["audio_branch_cut_placement"] = value }
  opts.on("--storyboard-assist PATH", "Explicit passed 03V storyboard-assist artifact.") { |value| options[:sources]["storyboard_assist"] = value }
  opts.on("--output PATH", "Source-pack output. Defaults to RUN_ROOT/handoff/03V-authoring-source-pack.yaml.") { |value| options[:output] = value }
  opts.on("--request-output PATH", "Authoring request output. Defaults to RUN_ROOT/handoff/03V-authoring-request.md.") { |value| options[:request_output] = value }
  opts.on("--write", "Write the validated source pack and request. No video generation is performed.") { options[:write] = true }
  opts.on("--no-json", "Print a short text result instead of JSON.") { options[:json] = false }
end

begin
  parser.parse!
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

run_arg = options[:run] || ARGV.shift
if run_arg.to_s.strip.empty? || !ARGV.empty?
  warn parser
  exit 2
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def inside?(path, root)
  relative = path.relative_path_from(root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

def inside_real?(path, root)
  return false unless inside?(path, root) && path.exist?
  relative = path.realpath.relative_path_from(root.realpath).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
end

def relative_path(path, root)
  path.relative_path_from(root).to_s
end

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "#{path} must contain an object" unless value.is_a?(Hash)
  value
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonical_value(value[source_key])
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def pointer_value(document, pointer)
  pointer.to_s.split("/")[1..].to_a.reduce(document) do |current, raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    current.is_a?(Array) ? current.fetch(Integer(token, 10)) : current.fetch(token)
  end
end

def validate_sequence_motion_bindings(storyboard, root, errors)
  front_ref = storyboard["source_front_planning"].to_h
  front_path = resolve_path(front_ref["path"], root)
  unless inside_real?(front_path, root) && front_path.file? && Digest::SHA256.file(front_path).hexdigest == front_ref["sha256"].to_s
    errors << "storyboard-assist source Front Planning is missing, stale, or outside the repository"
    return
  end
  front = load_mapping(front_path)
  Array(storyboard["boards"]).each_with_index do |board, index|
    label = "storyboard-assist boards[#{index}] Sequence Motion Analysis"
    sequence_binding = board["selected_sequence_binding"].to_h
    composition = pointer_value(front, sequence_binding["source_json_pointer"])
    binding = sequence_binding["sequence_motion_analysis_binding"].to_h
    errors << "#{label} must exact-copy the selected FP candidate binding" unless binding == composition.to_h["sequence_motion_analysis_binding"].to_h
    analysis_path = resolve_path(binding["path"], root)
    unless inside_real?(analysis_path, root) && analysis_path.file?
      errors << "#{label} artifact is missing or outside the repository"
      next
    end
    errors << "#{label} file SHA-256 is stale" unless Digest::SHA256.file(analysis_path).hexdigest == binding["sha256"].to_s
    analysis = load_mapping(analysis_path)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      root.join("scripts", "validate_sequence_motion_analysis.rb").to_s,
      "--root",
      root.to_s,
      analysis_path.to_s,
      chdir: root.to_s
    )
    errors << "#{label} failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
    row = pointer_value(analysis, binding["json_pointer"])
    errors << "#{label} row value SHA-256 is stale" unless binding["value_sha256"].to_s == value_sha256(row)
    errors << "#{label} row composition differs" unless row.to_h["sequence_composition_id"].to_s == composition.to_h["sequence_composition_id"].to_s
    errors << "#{label} row Sequence Units differ" unless Array(row.to_h["sequence_unit_bindings"]).map { |entry| entry["sequence_unit_id"].to_s } == Array(composition.to_h["typed_sequence_unit_ids"]).map(&:to_s)
    errors << "#{label} section differs" unless analysis["section_id"].to_s == board["section_id"].to_s
    errors << "#{label} Major differs" unless analysis["major_scene_id"].to_s == board["major_scene_id"].to_s
  rescue JSON::ParserError, Psych::Exception, TypeError, KeyError, IndexError, ArgumentError => error
    errors << "#{label} binding is stale: #{error.message}"
  end
end

def run_validator(spec, path, root)
  return nil unless spec[:validator]

  command = [RbConfig.ruby, root.join(spec.fetch(:validator)).to_s]
  command.concat(["--root", root.to_s]) if spec[:root_option]
  command.concat(Array(spec[:extra_args]))
  command << path.to_s
  stdout, stderr, status = Open3.capture3(*command, chdir: root.to_s)
  return nil if status.success?

  [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n").strip
end

def validate_source_pack(document, root)
  Tempfile.create(["idol-03v-authoring-source-pack", ".yaml"]) do |file|
    file.write(YAML.dump(document))
    file.flush
    stdout, stderr, status = Open3.capture3(
      root.join("scripts", "idol-video-python").to_s,
      root.join("scripts", "validate_json_schema.py").to_s,
      root.join("schemas", "03v-authoring-source-pack.schema.json").to_s,
      file.path,
      chdir: root.to_s
    )
    return nil if status.success?
    return [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n").strip
  end
end

root = options[:root].expand_path.cleanpath
run_path = resolve_path(run_arg, root)
errors = []
unless inside?(run_path, root) && run_path.directory?
  errors << "run root is missing or outside the repository: #{run_arg}"
end

source_paths = {}
source_documents = {}
source_rows = []

if errors.empty?
  SOURCE_SPECS.each do |role, spec|
    requested = options[:sources][role]
    path = if requested
             resolve_path(requested, root)
           else
             run_path.join(spec.fetch(:default)).expand_path.cleanpath
           end
    source_paths[role] = path
    unless inside?(path, root) && path.file?
      errors << "#{role} is missing: #{relative_path(path, root)}"
      next
    end

    validation_error = run_validator(spec, path, root)
    errors << "#{role} failed active validation: #{validation_error}" if validation_error
    begin
      source_documents[role] = load_mapping(path)
    rescue JSON::ParserError, Psych::Exception, TypeError => error
      errors << "#{role} cannot be read: #{error.message}"
    end
    source_rows << {
      "role" => role,
      "path" => relative_path(path, root),
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end
end

if errors.empty?
  master_storyboard = source_documents.fetch("master_storyboard")
  storyline_lineage_projection = master_storyboard["storyline_lineage_projection"]
  errors << "02A master storyboard must carry the complete PRE-00-rooted storyline lineage" unless storyline_lineage_projection.is_a?(Hash) &&
                                                                                                         storyline_lineage_projection["projected_value"].is_a?(Hash)
  storyboard = source_documents.fetch("storyboard_assist")
  errors << "03V storyboard assist must be passed before prompt authoring preparation" unless storyboard["status"] == "passed"
  prompt_packets = source_documents.fetch("prompt_packets")
  errors << "02B must be the approved active 2.6 packet set" unless prompt_packets["schema_version"] == "2.6" && prompt_packets["status"] == "approved"
  review = source_documents.fetch("production_cut_review")
  errors << "Official Core/Branch Production Cut review must be active passed v2" unless review["schema_version"] == "idol-production-cut-review.v2" && review["status"].to_s == "passed"
  placement = source_documents.fetch("audio_branch_cut_placement")
  errors << "Audio Production-Cut Placement must be ready_for_03v or passed" unless %w[ready_for_03v passed].include?(placement["status"].to_s)
  validate_sequence_motion_bindings(storyboard, root, errors)
end

storyline_lineage_projection = source_documents.fetch("master_storyboard", {})["storyline_lineage_projection"] || {}

source_set_sha256 = Digest::SHA256.hexdigest(
  source_rows
    .sort_by { |row| row.fetch("role") }
    .map { |row| "#{row.fetch('role')}\0#{row.fetch('path')}\0#{row.fetch('sha256')}" }
    .join("\n")
)

content_id = run_path.basename.to_s
output_path = options[:output] ? resolve_path(options[:output], root) : run_path.join("handoff", "03V-authoring-source-pack.yaml")
request_path = options[:request_output] ? resolve_path(options[:request_output], root) : run_path.join("handoff", "03V-authoring-request.md")
[output_path, request_path].each do |path|
  errors << "output path must remain inside the owning run: #{path}" unless inside?(path, run_path)
end

boards = errors.empty? ? Array(source_documents.fetch("storyboard_assist")["boards"]) : []
review = source_documents.fetch("production_cut_review", {})
cohort_successions = Array(review["section_cohort_successions"])
cohort_by_section = {}
successor_by_cohort = {}
cohort_successions.each do |successor|
  cohort_id = successor.to_h["section_cohort_id"].to_s
  if successor_by_cohort.key?(cohort_id)
    errors << "Production Cut review repeats section cohort #{cohort_id}"
  end
  successor_by_cohort[cohort_id] = successor
  Array(successor.to_h["section_ids"]).each do |section_id|
    if cohort_by_section.key?(section_id.to_s) && cohort_by_section[section_id.to_s] != cohort_id
      errors << "Production Cut review section #{section_id} maps to multiple cohorts"
    end
    cohort_by_section[section_id.to_s] = cohort_id
  end
end
review_rows_by_id = Array(review["production_cut_reviews"]).to_h do |row|
  [row.to_h["production_cut_id"].to_s, row.to_h]
end

section_shards = boards.group_by { |board| board["section_id"].to_s }.map do |section_id, section_boards|
  cohort_id = cohort_by_section[section_id]
  successor = successor_by_cohort[cohort_id].to_h
  errors << "03V section #{section_id} has no exact Production Cut cohort successor" if cohort_id.to_s.empty? || successor.empty?
  {
    "section_id" => section_id,
    "section_cohort_id" => cohort_id,
    "planning_cdd_lane_id" => successor["planning_cdd_lane_id"],
    "production_cdd_lane_id" => successor["production_cdd_lane_id"],
    "cohort_carry_policy" => successor["carry_policy"],
    "storyboard_ids" => section_boards.map { |board| board["storyboard_id"] },
    "board_count" => section_boards.length,
    "authoring_scope" => "one_section_only"
  }
end

pack = {
  "schema_version" => "idol_03v_authoring_source_pack.v5",
  "content_id" => content_id,
  "status" => errors.empty? ? "ready_for_model_authoring" : "hold",
  "run_root" => inside?(run_path, root) ? relative_path(run_path, root) : run_arg.to_s,
  "source_set_sha256" => source_set_sha256,
  "sources" => source_rows.sort_by { |row| row.fetch("role") },
  "storyline_lineage_projection" => storyline_lineage_projection,
  "read_order" => [
    "storyline_lineage_projection.projected_value.pre00_storyline_original",
    "storyline_lineage_projection.projected_value.pre00_storyline_revisions",
    "storyline_lineage_projection.projected_value.active_storyline_version",
    "storyline_lineage_projection.projected_value.contextual_density_review",
    "storyline_lineage_projection.projected_value.reference_bindings",
    "section_shards_and_boards"
  ],
  "authoring_policy" => {
    "source_gate" => "passed_hash_bound_pixels_and_passed_storyboard_boards_only",
    "standard_attachment_order" => "@image1_storyboard_then_@image2_@image3_optional_@image4_ordered_production_cut_originals",
    "board_authority" => "authoring_and_review_evidence_for_order_timing_blocking_subject_route_and_camera_motion",
    "production_cut_original_authority" => "pixels_identity_style_light_still_composition_and_visible_states",
    "source_union" => "official_core_or_branch",
    "same_parent_default" => true,
    "cross_core_rule" => "both_core_ids_and_continuity_reason_required",
    "sequence_motion_analysis_role" => "selected_exact_advisory_input_only_never_final_temporal_camera_truth",
    "camera_motion_owner" => "03V_after_passed_production_cut_review_and_audio_production_cut_placement",
    "one_image_rule" => "allowed_when_one_passed_production_cut_is_a_sufficient_motion_anchor_with_authored_reason_and_temporal_route",
    "more_than_three_rule" => "split_into_ordered_linked_boards",
    "choreography_rule" => "primary_or_supporting_only_from_bound_actual_choreography_performance_or_fancam_reference",
    "creative_authorship" => "assigned_model_or_human_only",
    "script_role" => "validate_hash_and_project_exact_source_values_only"
  },
  "section_cohort_successions" => cohort_successions,
  "section_shards" => section_shards,
  "boards" => boards.map do |board|
    cohort_id = cohort_by_section[board["section_id"].to_s]
    projected_sources = Array(board["source_production_cut_images"]).map do |source|
      review_row = review_rows_by_id[source.to_h["production_cut_id"].to_s]
      if review_row.nil?
        errors << "#{board['storyboard_id']} names an unknown Production Cut #{source.to_h['production_cut_id']}"
        deep = source.dup
      else
        errors << "#{board['storyboard_id']} mixes Production Cuts from another section cohort" unless review_row["section_cohort_id"].to_s == cohort_id.to_s
        deep = Marshal.load(Marshal.dump(source))
        deep["section_cohort_id"] = review_row["section_cohort_id"]
      end
      deep
    end
    {
      "storyboard_id" => board["storyboard_id"],
      "section_id" => board["section_id"],
      "section_cohort_id" => cohort_id,
      "major_scene_id" => board["major_scene_id"],
      "core_cut_id" => board["core_cut_id"],
      "board_order" => board["board_order"],
      "active_storyline_passage_pointer" => board["active_storyline_passage_pointer"],
      "active_storyline_binding" => board["active_storyline_binding"],
      "selected_sequence_composition_id" => board["selected_sequence_composition_id"],
      "selected_sequence_unit_ids" => board["selected_sequence_unit_ids"],
      "sequence_flow_reading_sha256" => board["sequence_flow_reading_sha256"],
      "selected_sequence_binding" => board["selected_sequence_binding"],
      "major_scene_binding" => board["major_scene_binding"],
      "screen_progression_binding" => board["screen_progression_binding"],
      "screen_progression_node_ids" => board["screen_progression_node_ids"],
      "selected_core_reference_binding_ids" => board["selected_core_reference_binding_ids"],
      "relationship_mode" => board["relationship_mode"],
      "cross_core_transition" => board["cross_core_transition"],
      "board_image" => board["board_image"],
      "source_production_cut_images" => projected_sources,
      "one_image_board_reason" => board["one_image_board_reason"],
      "previous_board_id" => board["previous_board_id"],
      "next_board_id" => board["next_board_id"],
      "audio_cue" => board["audio_cue"],
      "motion_derivation_note" => board["motion_derivation_note"],
      "prompt_handoff" => board["prompt_handoff"]
    }
  end,
  "canonical_manifest_path" => relative_path(run_path.join("03V-video-prompt-manifest.yaml"), root),
  "validation_command" => "ruby scripts/validate_video_prompt_manifest.rb #{relative_path(run_path.join('03V-video-prompt-manifest.yaml'), root)}",
  "automation_boundaries" => {
    "creative_prompt_authored" => false,
    "camera_motion_authored_by_script" => false,
    "paid_video_generation_approved" => false,
    "external_video_execution_approved" => false,
    "playback_pass_implied" => false,
    "edit_readiness_implied" => false
  },
  "errors" => errors
}

source_pack_schema_error = validate_source_pack(pack, root)
if source_pack_schema_error
  errors << "03V authoring source pack failed active v5 schema validation: #{source_pack_schema_error}"
  pack["status"] = "hold"
  pack["errors"] = errors
end

request = <<~MARKDOWN
  # 03V Video Prompt Authoring Request

  Status: #{pack["status"]}
  Run: `#{pack["run_root"]}`
  Source pack: `#{relative_path(output_path, root)}`
  Source-set SHA-256: `#{source_set_sha256}`

  Read the complete PRE-00-rooted storyline lineage first: immutable original,
  ordered full-text revisions, active full text, contextual density review, and
  every reference function/exclusion. Do not replace it with a whole-film or
  section summary.

  Author the active `idol_video_prompt_manifest.v8` one physical section at a
  time. Inspect the exact passed board and original Official Core/Branch pixels. Preserve
  `@image1` as the storyboard authority for ordered timing, blocking, subject
  route, and temporal camera motion. Preserve `@image2`, `@image3`, and optional
  `@image4` as the pixel authority for identity, style, light,
  composition, and visible states.

  Exact-carry each `section_cohort_id` and its `CDD-P3-Ci` to `CDD-V-Ci`
  successor binding from the source pack. Do not mix Production Cuts, cues, or
  playback review across section cohorts.

  Write observable subject motion and a motivated temporal camera route only
  here, after pixel inspection. A one-image clip still uses its declared
  one-image board, motion-anchor reason, and temporal route. Split more than
  three necessary states into linked boards. Default to one parent Core; a
  cross-Core transition requires both Core IDs and a continuity reason. The
  default execution source is one passed Production Cut frame. Use
  `reference_to_video` only for Founder-selected exact multi-reference IDs and
  order. Use only 6/10 seconds and 480p/720p; a 720p candidate requires a passed
  CDD review of the same job's 480p test. Use choreography only when the board carries a bound actual
  choreography, performance, or fancam source. Do not generate video, infer
  paid or external approval, or start 04 edit/QC from this preparation.
MARKDOWN

if options[:write]
  if errors.any?
    warn errors.join("\n")
    exit 1
  end
  FileUtils.mkdir_p(output_path.dirname)
  FileUtils.mkdir_p(request_path.dirname)
  output_path.write(YAML.dump(pack))
  request_path.write(request)
end

result = {
  "write" => options[:write],
  "authoring_ready" => errors.empty?,
  "authoring_status" => pack["status"],
  "run" => pack["run_root"],
  "content_id" => content_id,
  "source_pack" => relative_path(output_path, root),
  "source_pack_sha256" => options[:write] ? Digest::SHA256.file(output_path).hexdigest : Digest::SHA256.hexdigest(YAML.dump(pack)),
  "request" => relative_path(request_path, root),
  "source_set_sha256" => source_set_sha256,
  "board_count" => boards.length,
  "section_count" => section_shards.length,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: active 03V authoring source pack is ready"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
