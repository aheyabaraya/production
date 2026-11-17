#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "planning-contextual-grade-vector.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")

STAGE_CRITERIA = {
  "pre_fp_storyline" => %w[
    whole_film_opening_to_ending_causality
    target_audience_promise_lock
    message_progression_without_repetition
    storyline_reference_influence_accounting
  ],
  "front_planning_reference_close" => %w[
    storyline_section_major_causality
    selected_audio_kinetic_edit_usefulness
    contiguous_motion_change_and_landing
    still_camera_composition_depth_edit_value
    four_role_coverage_and_synthesis
    major_core_whole_film_non_duplication
    transfer_provenance_feasibility
  ],
  "front_planning_section_kinetic_close" => %w[
    section_major_causal_job
    two_to_three_second_kinetic_tendency
    contiguous_motion_change_and_landing
    still_camera_composition_depth_edit_value
    cohort_non_duplication
    boundary_continuity
  ],
  "draft_keyframe_proof" => %w[
    cut_screen_job_neighbor_delta
    character_visual
    scene_visual_package
    action_pose_motion_readiness
    angle_distance_depth_crop_transition_diversity
    reference_transfer_generation_feasibility
    prop_interaction_readability
  ]
}.freeze

options = {root: ROOT}
OptionParser.new do |parser|
  parser.banner = "usage: validate_planning_contextual_grade_vector.rb [--root PATH] PATH"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path.cleanpath }
end.parse!
path_arg = ARGV.shift
abort "usage: validate_planning_contextual_grade_vector.rb [--root PATH] PATH" if path_arg.to_s.empty? || ARGV.any?

path = Pathname.new(path_arg)
path = options[:root].join(path) unless path.absolute?
abort "planning grade vector is missing" unless path.file?

stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, path.to_s, chdir: ROOT.to_s)
abort [stderr, stdout].join("\n").strip unless status.success?

document = if path.extname.downcase == ".json"
             JSON.parse(path.read)
           else
             YAML.safe_load(path.read, aliases: true)
           end
errors = []
stage = document["stage"].to_s
required = STAGE_CRITERIA.fetch(stage, [])
performance_mode = document["performance_mode"].to_s
required += ["performance_readability"] if %w[supporting primary].include?(performance_mode)

Array(document["source_artifacts"]).each_with_index do |source, index|
  source = source.to_h
  raw_path = source["path"].to_s
  candidate = Pathname.new(raw_path)
  candidate = options[:root].join(candidate) unless candidate.absolute?
  candidate = candidate.expand_path.cleanpath
  begin
    relative = candidate.relative_path_from(options[:root]).to_s
    if relative == ".." || relative.start_with?("../")
      errors << "source_artifacts[#{index}] path escapes repository"
      next
    end
  rescue ArgumentError
    errors << "source_artifacts[#{index}] path escapes repository"
    next
  end
  unless candidate.file?
    errors << "source_artifacts[#{index}] path is missing: #{raw_path}"
    next
  end
  actual_sha256 = Digest::SHA256.file(candidate).hexdigest
  errors << "source_artifacts[#{index}] SHA-256 is stale: #{raw_path}" unless actual_sha256 == source["sha256"].to_s
end

rows = Array(document["criteria"])
ids = rows.map { |row| row.to_h["criterion_id"].to_s }
errors << "criteria must contain each stage-appropriate criterion exactly once" unless ids.sort == required.sort && ids.uniq.length == ids.length

rows.each do |row|
  criterion_id = row.to_h["criterion_id"].to_s
  result = row.to_h["result"]
  if criterion_id == "performance_readability" && performance_mode == "none"
    errors << "performance_readability must be omitted when performance_mode is none"
  end
  if result.is_a?(String) && result.start_with?("not_applicable")
    allowed =
      (stage == "draft_keyframe_proof" && criterion_id == "character_visual" && result == "not_applicable_member_absent") ||
      (stage == "draft_keyframe_proof" && criterion_id == "prop_interaction_readability" && result == "not_applicable_no_material_prop")
    errors << "#{criterion_id} cannot use #{result} at #{stage}" unless allowed
  end
end

by_id = rows.to_h { |row| [row.to_h["criterion_id"].to_s, row.to_h["result"]] }
if %w[front_planning_reference_close front_planning_section_kinetic_close].include?(stage)
  errors << "contiguous motion requires grade 4" unless by_id["contiguous_motion_change_and_landing"] == 4
  errors << "still camera/composition requires grade 4" unless by_id["still_camera_composition_depth_edit_value"] == 4
end
if stage == "pre_fp_storyline"
  errors << "whole-film opening-to-ending causality requires grade 4" unless by_id["whole_film_opening_to_ending_causality"] == 4
end
if stage == "draft_keyframe_proof"
  errors << "Draft Keyframe Proof must reuse fp_hero_core" unless document["preview_packet_mode"].to_s == "fp_hero_core"
  errors << "Draft Keyframe scene_visual_package requires grade 4" unless by_id["scene_visual_package"] == 4
  errors << "Draft Keyframe action/pose/motion readiness requires grade 4" unless by_id["action_pose_motion_readiness"] == 4
end

rows.each do |row|
  next unless row.is_a?(Hash)

  errors << "#{row['criterion_id']} evidence locator is missing" if row["evidence_locator"].to_s.strip.empty?
  errors << "script-authored grade is forbidden" if row["review_note"].to_s.match?(/\bscript(?:-authored)?\b/i)
end

if document["decision"].to_s == "eligible_for_director_review"
  numeric = rows.map { |row| row.to_h["result"] }.select { |value| value.is_a?(Integer) }
  inapplicable = rows.count { |row| row.to_h["result"].is_a?(String) && row.to_h["result"].start_with?("not_applicable") }
  errors << "promotion eligibility requires every applicable planning criterion at grade 3 or higher" unless numeric.length == required.length - inapplicable && numeric.all? { |value| value >= 3 }
  errors << "eligible_for_director_review still requires independent Director review and is not creative PASS" unless document["automatic_creative_pass"] == false
end

abort errors.join("\n") unless errors.empty?
display_path = path.relative_path_from(options[:root]) rescue path
puts "planning contextual grade vector valid: #{display_path}"
