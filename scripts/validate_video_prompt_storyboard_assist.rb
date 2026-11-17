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
require_relative "lib/idol_02a_storyboard_contract"
require_relative "lib/idol_storyboard_collected_angle_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "video-prompt-storyboard-assist.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")
ACTIVE_SCHEMA_VERSION = "idol_video_prompt_storyboard_assist.v4"
SEQUENCE_MOTION_ANALYSIS_VALIDATOR = ROOT.join("scripts", "validate_sequence_motion_analysis.rb")
SOURCE_VALIDATORS = {
  "source_front_planning" => ["validate_front_planning_readiness.rb", "--root"],
  "source_01_direction" => ["validate_01_section_direction.rb", "--root"],
  "source_master_storyboard" => ["validate_master_storyboard.rb", "--root"],
  "source_02a_context_review" => ["validate_02a_creative_context_review.rb", "--repo-root"],
  "source_prompt_packets" => ["validate_02b_imagegen_contract.rb", nil],
  "source_production_cut_review" => ["validate_production_cut_review.rb", "--root"],
  "source_audio_branch_cut_placement" => ["validate_audio_branch_cut_placement.rb", "--root"]
}.freeze

options = {root: ROOT, json: false, max_errors: 80}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_video_prompt_storyboard_assist.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!
artifact_arg = ARGV.shift
abort "storyboard-assist path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
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

def inside_real?(path, root)
  return false unless inside?(path, root) && path.exist?
  relative = path.realpath.relative_path_from(root.realpath).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
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

def run_source_validator(role, path, root, errors)
  script, root_option = SOURCE_VALIDATORS.fetch(role)
  command = [RbConfig.ruby, ROOT.join("scripts", script).to_s]
  command.concat([root_option, root.to_s]) if root_option
  command << "--require-ready" if role == "source_audio_branch_cut_placement"
  command << path.to_s
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  return if status.success?

  detail = [stderr, stdout].reject { |text| text.to_s.strip.empty? }.join(" ").strip
  errors << "#{role} failed active validation: #{detail}"
end

def resolve_pointer(document, pointer)
  raise KeyError, "JSON pointer must begin with /" unless pointer.to_s.start_with?("/")

  pointer.split("/").drop(1).reduce(document) do |value, token|
    key = token.gsub("~1", "/").gsub("~0", "~")
    value.is_a?(Array) ? value.fetch(Integer(key, 10)) : value.fetch(key)
  end
end

def value_sha(value)
  Idol02AStoryboardContract.value_sha256(value)
end

def validate_value_binding(binding, source, label, errors)
  unless binding.is_a?(Hash)
    errors << "#{label} must be an exact source value binding"
    return nil
  end
  value = resolve_pointer(source, binding["source_json_pointer"])
  errors << "#{label} source value SHA-256 is stale" unless binding["source_value_sha256"] == value_sha(value)
  value
rescue KeyError, IndexError, ArgumentError => error
  errors << "#{label} source pointer does not resolve: #{error.message}"
  nil
end

def same_artifact_ref?(left, right)
  left.to_h.slice("path", "sha256") == right.to_h.slice("path", "sha256")
end

def validate_sequence_motion_binding(binding, composition, board, root, errors, label)
  unless binding.is_a?(Hash)
    errors << "#{label} must carry the selected FP Sequence Motion Analysis binding"
    return
  end
  unless binding == composition.to_h["sequence_motion_analysis_binding"]
    errors << "#{label} must exact-copy the selected FP candidate Sequence Motion Analysis binding"
  end
  path = resolve_path(binding["path"], root)
  unless inside_real?(path, root) && path.file?
    errors << "#{label} analysis artifact is missing, outside the repository, or resolves through a symlink outside it"
    return
  end
  errors << "#{label} analysis file SHA-256 is stale" unless Digest::SHA256.file(path).hexdigest == binding["sha256"].to_s
  analysis = load_mapping(path)
  errors << "#{label} analysis must be independently reviewed ready_for_cdd_review v1" unless analysis["schema_version"] == "idol_sequence_motion_analysis.v1" && analysis["status"] == "ready_for_cdd_review"
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, SEQUENCE_MOTION_ANALYSIS_VALIDATOR.to_s, "--root", root.to_s, path.to_s, chdir: root.to_s)
  errors << "#{label} analysis failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  row = resolve_pointer(analysis, binding["json_pointer"])
  errors << "#{label} analysis row value SHA-256 is stale" unless binding["value_sha256"].to_s == value_sha(row)
  errors << "#{label} analysis row Sequence Composition differs" unless row.to_h["sequence_composition_id"].to_s == composition.to_h["sequence_composition_id"].to_s
  errors << "#{label} analysis row Sequence Units differ" unless Array(row.to_h["sequence_unit_bindings"]).map { |entry| entry["sequence_unit_id"].to_s } == Array(composition.to_h["typed_sequence_unit_ids"]).map(&:to_s)
  errors << "#{label} analysis section differs from board" unless analysis["section_id"].to_s == board["section_id"].to_s
  errors << "#{label} analysis Major differs from board" unless analysis["major_scene_id"].to_s == board["major_scene_id"].to_s
rescue JSON::ParserError, Psych::Exception, TypeError, KeyError, IndexError, ArgumentError => error
  errors << "#{label} analysis binding is stale: #{error.message}"
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
document = {}
unless inside?(artifact, root) && artifact.file?
  errors << "storyboard-assist artifact is missing or outside the repository: #{artifact_arg}"
else
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot parse storyboard-assist artifact: #{error.message}"
  end
  stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, artifact.to_s, chdir: ROOT.to_s)
  errors << "JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

if document.any?
  errors << "only #{ACTIVE_SCHEMA_VERSION} is active" unless document["schema_version"] == ACTIVE_SCHEMA_VERSION
  source_paths = {}
  sources = {}
  SOURCE_VALIDATORS.each_key do |role|
    path = validate_ref(document[role], role, root, errors)
    source_paths[role] = path
    next unless path

    run_source_validator(role, path, root, errors)
    begin
      sources[role] = load_mapping(path)
    rescue JSON::ParserError, Psych::Exception, TypeError => error
      errors << "#{role} cannot be read: #{error.message}"
    end
  end

  front = sources.fetch("source_front_planning", {})
  direction = sources.fetch("source_01_direction", {})
  master = sources.fetch("source_master_storyboard", {})
  context_review = sources.fetch("source_02a_context_review", {})
  prompt_packets = sources.fetch("source_prompt_packets", {})
  review = sources.fetch("source_production_cut_review", {})
  placement = sources.fetch("source_audio_branch_cut_placement", {})
  generated_review = nil
  generated_ref = review["source_generated_branch_cut_review"]
  if generated_ref.is_a?(Hash)
    generated_path = validate_ref(generated_ref, "source_production_cut_review.source_generated_branch_cut_review", root, errors)
    if generated_path
      begin
        generated_review = load_mapping(generated_path)
      rescue JSON::ParserError, Psych::Exception, TypeError => error
        errors << "source generated Branch-Cut review cannot be read: #{error.message}"
      end
    end
  end

  errors << "source Front Planning must be active director-closed v17" unless front["schema_version"] == "front-planning-readiness.v17" && front["status"] == "director_closed"
  errors << "source 01 direction must be active passed 3.0" unless direction["schema_version"] == "3.0" && direction["status"] == "passed"
  errors << "source 02A master storyboard must be active passed 3.0" unless master["schema_version"] == "3.0" && master["status"] == "passed"
  errors << "source 02A contextual review must be active passed v7" unless context_review["schema_version"] == "idol-02a-creative-context-review.v7" && context_review["status"] == "passed"
  errors << "source prompt packets must be active approved 2.6" unless prompt_packets["schema_version"] == "2.6" && prompt_packets["status"] == "approved"
  errors << "source Production Cut review must be active passed v2" unless review["schema_version"] == "idol-production-cut-review.v2" && review["status"] == "passed"
  errors << "source audio placement must be active v5 ready_for_03v or passed" unless placement["schema_version"] == "idol_audio_production_cut_placement.v5" && %w[ready_for_03v passed].include?(placement["status"].to_s)

  errors << "01 source Front Planning differs from storyboard-assist" unless same_artifact_ref?(direction["source_front_planning"], document["source_front_planning"])
  errors << "02A source Front Planning differs from storyboard-assist" unless same_artifact_ref?(master["source_front_planning"], document["source_front_planning"])
  errors << "02A source 01 direction differs from storyboard-assist" unless same_artifact_ref?(master["source_01_direction"], document["source_01_direction"])
  errors << "02A contextual review source differs from storyboard-assist" unless same_artifact_ref?(context_review["source_02a"], document["source_master_storyboard"])
  errors << "Production Cut review source 01 differs from storyboard-assist" unless same_artifact_ref?(review["source_01_direction"], document["source_01_direction"])
  errors << "Production Cut review source 02A differs from storyboard-assist" unless same_artifact_ref?(review["source_02a"], document["source_master_storyboard"])
  errors << "Production Cut review source 02B differs from storyboard-assist" unless same_artifact_ref?(review["source_02b"], document["source_prompt_packets"])
  errors << "audio placement source Production Cut review differs from storyboard-assist" unless same_artifact_ref?(placement["source_production_cut_review"], document["source_production_cut_review"])
  errors << "audio placement source 01 differs from storyboard-assist" unless same_artifact_ref?(placement["source_01_direction"], document["source_01_direction"])
  errors << "audio placement source 02A differs from storyboard-assist" unless same_artifact_ref?(placement["source_02a"], document["source_master_storyboard"])
  errors << "audio placement source 02B differs from storyboard-assist" unless same_artifact_ref?(placement["source_02b"], document["source_prompt_packets"])

  errors << "declared_board_count must equal boards length" unless document["declared_board_count"].to_i == Array(document["boards"]).length
  errors << "return recipient must be CDD" unless document["return_recipient_role"] == "creative_development_director"
  output_root = resolve_path(document["output_root"], root)
  errors << "output_root must remain inside the repository" unless inside?(output_root, root)

  review_rows = Array(review["production_cut_reviews"])
  cohort_by_section = {}
  Array(review["section_cohort_successions"]).each do |successor|
    cohort_id = successor.to_h["section_cohort_id"].to_s
    Array(successor.to_h["section_ids"]).each { |section_id| cohort_by_section[section_id.to_s] = cohort_id }
  end
  placement_by_id = Array(placement["production_cut_units"]).to_h { |row| [row["production_cut_id"], row] }
  board_ids = []
  boards = Array(document["boards"])
  boards.each_with_index do |board, index|
    label = "boards[#{index}]"
    board_id = board["storyboard_id"].to_s
    errors << "#{label}.storyboard_id must be unique" if board_ids.include?(board_id)
    board_ids << board_id
    errors << "#{label}.board_order must equal #{index + 1}" unless board["board_order"].to_i == index + 1

    active = validate_value_binding(board["active_storyline_binding"], master, "#{label}.active_storyline_binding", errors)
    if active.is_a?(Hash)
      errors << "#{label} active storyline version differs from 02A" unless board.dig("active_storyline_binding", "active_version_id") == active["version_id"]
      errors << "#{label} active storyline full-text hash differs from 02A" unless board.dig("active_storyline_binding", "active_full_text_sha256") == active["full_storyline_text_sha256"]
      passage = resolve_pointer(master, board["active_storyline_passage_pointer"])
      errors << "#{label} storyline passage must be the exact active full text" unless passage.is_a?(String) && Digest::SHA256.hexdigest(passage) == active["full_storyline_text_sha256"]
    end

    major = validate_value_binding(board["major_scene_binding"], front, "#{label}.major_scene_binding", errors)
    if major.is_a?(Hash)
      errors << "#{label}.major_scene_id differs from exact FP Major" unless board["major_scene_id"] == major["major_scene_id"] && board.dig("major_scene_binding", "major_scene_id") == major["major_scene_id"]
      errors << "#{label}.section_id differs from exact FP Major" unless board["section_id"] == major["section_id"]
    end

    sequence_binding = board["selected_sequence_binding"].to_h
    composition = validate_value_binding(sequence_binding, front, "#{label}.selected_sequence_binding", errors)
    unit_sources = Array(sequence_binding["sequence_unit_sources"])
    if composition.is_a?(Hash)
      expected_id = composition["sequence_composition_id"]
      expected_units = Array(composition["typed_sequence_unit_ids"])
      errors << "#{label} selected Sequence Composition id differs from exact FP candidate" unless board["selected_sequence_composition_id"] == expected_id && sequence_binding["selected_sequence_composition_id"] == expected_id
      errors << "#{label} Sequence Composition flow hash differs from FP" unless board["sequence_flow_reading_sha256"] == value_sha(composition["flow_reading"]) && sequence_binding["sequence_flow_reading_sha256"] == value_sha(composition["flow_reading"])
      errors << "#{label} selected Sequence Unit roster differs from FP Composition" unless board["selected_sequence_unit_ids"] == expected_units && unit_sources.map { |row| row["sequence_unit_id"] } == expected_units
      validate_sequence_motion_binding(sequence_binding["sequence_motion_analysis_binding"], composition, board, root, errors, "#{label}.selected_sequence_binding.sequence_motion_analysis_binding")
    end
    unit_sources.each_with_index do |binding, unit_index|
      unit = validate_value_binding(binding, front, "#{label}.selected_sequence_binding.sequence_unit_sources[#{unit_index}]", errors)
      next unless unit.is_a?(Hash)

      errors << "#{label} Sequence Unit id differs from exact FP unit" unless binding["sequence_unit_id"] == unit["sequence_unit_id"]
      errors << "#{label} Sequence Unit flow-reading hash differs from FP" unless binding["flow_reading_sha256"] == value_sha(unit["flow_reading"])
    end

    screen_binding = board["screen_progression_binding"].to_h
    screen_map = validate_value_binding(screen_binding, master, "#{label}.screen_progression_binding", errors)
    if screen_map.is_a?(Hash)
      errors << "#{label} screen progression map id differs from 02A" unless screen_binding["screen_progression_map_id"] == screen_map["screen_progression_map_id"]
    end
    node_sources = Array(screen_binding["node_sources"])
    node_sources.each_with_index do |binding, node_index|
      node = validate_value_binding(binding, master, "#{label}.screen_progression_binding.node_sources[#{node_index}]", errors)
      errors << "#{label} screen node id differs from exact 02A node" if node.is_a?(Hash) && binding["screen_progression_node_id"] != node["node_id"]
    end

    images = Array(board["source_production_cut_images"])
    expected_slots = %w[@image2 @image3 @image4].first(images.length)
    errors << "#{label} Production Cut board_order values must be contiguous from 1" unless images.map { |image| image["board_order"] } == (1..images.length).to_a
    errors << "#{label} original attachment slots must be #{expected_slots.join(', ')}" unless images.map { |image| image["attachment_slot"] } == expected_slots
    errors << "#{label}.board_image.panel_count must equal source Production Cut image count" unless board.dig("board_image", "panel_count").to_i == images.length
    validate_ref(board["board_image"], "#{label}.board_image", root, errors)

    images.each_with_index do |image, image_index|
      image_label = "#{label}.source_production_cut_images[#{image_index}]"
      validate_ref(image, image_label, root, errors)
      errors << "#{image_label} must be passed_production_cut" unless image["pixel_review_status"] == "passed_production_cut"
      review_row = validate_value_binding(image["source_production_cut_review"], review, "#{image_label}.source_production_cut_review", errors)
      source_cut = validate_value_binding(image["source_02a_cut"], master, "#{image_label}.source_02a_cut", errors)
      screen_job = validate_value_binding(image["screen_job_binding"], master, "#{image_label}.screen_job_binding", errors)
      expected_review = review_rows.find { |row| row["production_cut_id"] == image["production_cut_id"] }
      errors << "#{image_label} review pointer does not resolve the named Production Cut" unless review_row == expected_review
      if review_row.is_a?(Hash)
        %w[production_cut_id production_cut_type parent_core_cut_id packet_id pixel_review_status section_id major_scene_id active_storyline_version_id screen_progression_node_id scene_phase_context primary_audio_cue sequence_phase_binding_ids core_reference_binding_id].each do |key|
          errors << "#{image_label}.#{key} differs from typed Production Cut review" unless image[key] == review_row[key]
        end
        errors << "#{image_label} has no exact 02B to 03V section cohort" unless review_row["section_cohort_id"].to_s == cohort_by_section[image["section_id"].to_s].to_s && !review_row["section_cohort_id"].to_s.empty?
      end
      errors << "#{image_label}.screen_job_binding value differs from exact 02A screen job" unless image.dig("screen_job_binding", "value") == screen_job
      placement_row = placement_by_id[image["production_cut_id"]]
      transport_ref = image.slice("path", "sha256")
      reviewed_original = review_row.is_a?(Hash) ? review_row.slice("path", "sha256") : nil
      unless placement_row && placement_row["production_cut_type"] == image["production_cut_type"] && placement_row["parent_core_cut_id"] == image["parent_core_cut_id"]
        errors << "#{image_label} differs from exact audio-placement Production Cut unit"
      end
      if placement_row
        errors << "#{image_label} reviewed original must exact-match Production Cut review and audio-placement passed_source_image" unless reviewed_original && placement_row["passed_source_image"] == reviewed_original
        errors << "#{image_label} board/execution image must exact-match the audio-placement placement_image" unless placement_row["placement_image"] == transport_ref
        if image["production_cut_type"] == "official_core"
          errors << "#{image_label} Official Core board/execution image must remain the reviewed original" unless transport_ref == reviewed_original
        elsif image["production_cut_type"] == "branch"
          errors << "#{image_label} Branch board/execution image must be the receipt-bound placement upscale" unless placement_row["placement_image_role"] == "validated_local_upscale" && placement_row["local_upscale_receipt"].is_a?(Hash)
        end
      end
      errors << "#{image_label} source 02A cut id differs from named Production Cut" unless source_cut.is_a?(Hash) && (source_cut["core_cut_id"] || source_cut["branch_cut_id"]) == image["production_cut_id"]
    end

    cut_ids = images.map { |image| image["production_cut_id"].to_s }
    pixel_hashes = images.map { |image| image["sha256"].to_s }
    errors << "#{label} Production Cut ids on one board must be unique; same image exact-carry is not a new image" unless cut_ids.uniq.length == cut_ids.length
    errors << "#{label} pixel SHA-256 values on one board must be unique; same image exact-carry is not a new image" unless pixel_hashes.uniq.length == pixel_hashes.length
    planning_review = master.dig("camera_diversity_review", "collected_image_camera_angle_review").to_h
    errors << "#{label} 02A planning camera-angle review cannot be treated as generated-pixel closure" if planning_review["generated_pixel_closure"] == true
    if generated_review.is_a?(Hash)
      section_row = Array(generated_review["section_reviews"]).find { |row| row.to_h["section_id"].to_s == board["section_id"].to_s }
      pixel = section_row.to_h["collected_image_camera_angle_pixel_review"].to_h
      errors << "#{label} 03V cannot treat a partial generated-pixel camera-angle review as full-generated closure" if pixel["generated_pixel_closure"] != true
      errors << "#{label} generated-pixel camera-angle review is incomplete" unless Array(pixel["incomplete_pixel_bindings"]).empty?
    end
    reviewed_ids = Array(planning_review["distinct_images"]).map { |row| row.to_h["cut_id"].to_s }
    images.each do |image|
      next if reviewed_ids.include?(image["production_cut_id"].to_s)

      errors << "#{label} #{image['production_cut_id']} is absent from the 02A full-storyboard collected camera-angle review"
    end

    errors << "#{label}.section_id must exact-match every source Production Cut" unless images.all? { |image| image["section_id"] == board["section_id"] }
    board_cohorts = images.map { |image| review_rows.find { |row| row["production_cut_id"] == image["production_cut_id"] }.to_h["section_cohort_id"].to_s }.uniq
    errors << "#{label} must stay inside one exact 02B to 03V section cohort" unless board_cohorts == [cohort_by_section[board["section_id"].to_s]] && !board_cohorts.first.to_s.empty?
    errors << "#{label}.major_scene_id must exact-match every source Production Cut" unless images.all? { |image| image["major_scene_id"] == board["major_scene_id"] }
    errors << "#{label} active storyline version must exact-match every source Production Cut" unless images.all? { |image| image["active_storyline_version_id"] == board.dig("active_storyline_binding", "active_version_id") }
    errors << "#{label} selected Sequence Units must exact-match every source Production Cut" unless images.all? { |image| image["sequence_phase_binding_ids"] == board["selected_sequence_unit_ids"] }
    expected_nodes = images.map { |image| image["screen_progression_node_id"] }.uniq
    errors << "#{label}.screen_progression_node_ids differ from source Production Cuts" unless board["screen_progression_node_ids"] == expected_nodes && node_sources.map { |row| row["screen_progression_node_id"] } == expected_nodes
    expected_core_refs = images.map { |image| image["core_reference_binding_id"] }.uniq
    errors << "#{label}.selected_core_reference_binding_ids differ from source Production Cuts" unless board["selected_core_reference_binding_ids"] == expected_core_refs
    errors << "#{label}.audio_cue differs from source Production Cut" unless board["audio_cue"] == images.first.to_h["primary_audio_cue"]

    parents = images.map { |image| image["parent_core_cut_id"] }.uniq
    transition = board["cross_core_transition"]
    errors << "#{label}.core_cut_id must equal the first source parent Core" unless board["core_cut_id"] == parents.first
    if board["relationship_mode"] == "same_parent_core"
      errors << "#{label} same-parent board must have exactly one parent Core" unless parents.length == 1
      errors << "#{label} same-parent board must not declare cross-Core transition" unless transition.nil?
    else
      errors << "#{label} cross-Core board must bind at least two parent Cores" unless parents.length >= 2
      unless transition.is_a?(Hash) && transition["from_core_cut_id"] == parents.first && transition["to_core_cut_id"] == parents.last && transition["from_core_cut_id"] != transition["to_core_cut_id"] && !transition["continuity_reason"].to_s.strip.empty?
        errors << "#{label} cross-Core transition requires both distinct ordered Core IDs and continuity reason"
      end
      edge_present = Array(screen_map.to_h["ordered_edges"]).any? do |edge|
        edge["from_node_id"] == expected_nodes.first && edge["to_node_id"] == expected_nodes.last
      end
      errors << "#{label} cross-Core transition lacks the exact FP/02A screen-progression edge" unless edge_present
    end

    reason = board["one_image_board_reason"]
    if images.length == 1
      errors << "#{label} one-image board requires a motion-anchor reason and temporal-route sufficiency" unless reason.is_a?(Hash) && !reason["reason"].to_s.strip.empty? && !reason["temporal_route_sufficiency"].to_s.strip.empty?
    elsif !reason.nil?
      errors << "#{label} multi-image board must not declare a one-image reason"
    end
    handoff = board.fetch("prompt_handoff", {})
    expected = ["@image1"] + expected_slots
    errors << "#{label}.prompt_handoff.attachment_order must exactly equal #{expected.join(', ')}" unless handoff["attachment_order"] == expected
    prompt = handoff["prompt_text"].to_s
    expected.each { |slot| errors << "#{label}.prompt_text must explicitly bind #{slot}" unless prompt.include?(slot) }
    (%w[@image1 @image2 @image3 @image4] - expected).each { |slot| errors << "#{label}.prompt_text names unused attachment #{slot}" if prompt.include?(slot) }
    errors << "#{label} prompt rewrite policy must be forbidden" unless handoff["prompt_rewrite_policy"] == "forbidden"
  end

  boards.each_with_index do |board, index|
    expected_previous = index.zero? ? nil : boards[index - 1]["storyboard_id"]
    expected_next = index == boards.length - 1 ? nil : boards[index + 1]["storyboard_id"]
    errors << "boards[#{index}].previous_board_id is not the preceding board" unless board["previous_board_id"] == expected_previous
    errors << "boards[#{index}].next_board_id is not the following board" unless board["next_board_id"] == expected_next
  end
end

result = {"ok" => errors.empty?, "schema_version" => document["schema_version"], "board_count" => Array(document["boards"]).length, "errors" => errors.uniq.first(options[:max_errors])}
puts(options[:json] ? JSON.pretty_generate(result) : (errors.empty? ? "OK: active 03V Production Cut Motion Storyboard is valid" : errors.map { |error| "ERROR: #{error}" }.join("\n")))
exit(errors.empty? ? 0 : 1)
