#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "03v-contextual-grade-vector.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")

BASE_CRITERIA = %w[
  subject_body_action_pose_transition
  temporal_camera_route_or_locked_hold
  audio_trigger_landing_edit_handoff
  depth_parallax_occlusion_reveal_stop
  neighbor_whole_section_motion_diversity
  identity_light_state_geometry_stability
].freeze

options = {root: ROOT}
OptionParser.new do |parser|
  parser.banner = "usage: validate_03v_contextual_grade_vector.rb [--root PATH] PATH"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path.cleanpath }
end.parse!
path_arg = ARGV.shift
abort "usage: validate_03v_contextual_grade_vector.rb [--root PATH] PATH" if path_arg.to_s.empty? || ARGV.any?

path = Pathname.new(path_arg)
path = options[:root].join(path) unless path.absolute?
abort "03V grade vector is missing" unless path.file?

stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, path.to_s, chdir: ROOT.to_s)
abort [stderr, stdout].join("\n").strip unless status.success?

document = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, aliases: true)
errors = []

Array(document["source_playbacks"]).each_with_index do |source, index|
  source = source.to_h
  raw_path = source["path"].to_s
  candidate = Pathname.new(raw_path)
  candidate = options[:root].join(candidate) unless candidate.absolute?
  candidate = candidate.expand_path.cleanpath
  begin
    relative = candidate.relative_path_from(options[:root]).to_s
    if relative == ".." || relative.start_with?("../")
      errors << "source_playbacks[#{index}] path escapes repository"
      next
    end
  rescue ArgumentError
    errors << "source_playbacks[#{index}] path escapes repository"
    next
  end
  unless candidate.file?
    errors << "source_playbacks[#{index}] path is missing: #{raw_path}"
    next
  end
  actual_sha256 = Digest::SHA256.file(candidate).hexdigest
  errors << "source_playbacks[#{index}] SHA-256 is stale: #{raw_path}" unless actual_sha256 == source["sha256"].to_s
end

required = BASE_CRITERIA.dup
required << "performance_readability" if %w[supporting primary].include?(document["performance_mode"].to_s)
rows = Array(document["criteria"])
ids = rows.map { |row| row.to_h["criterion_id"].to_s }
errors << "criteria must contain each 03V stage criterion exactly once" unless ids.sort == required.sort && ids.uniq.length == ids.length

rows.each do |row|
  row = row.to_h
  criterion_id = row["criterion_id"].to_s
  result = row["result"]
  errors << "#{criterion_id} cannot be not_applicable at 03V" if result == "not_applicable" && criterion_id != "performance_readability"
  errors << "performance_readability must be omitted when performance_mode is none" if criterion_id == "performance_readability" && document["performance_mode"].to_s == "none"
end

by_id = rows.to_h { |row| [row.to_h["criterion_id"].to_s, row.to_h["result"]] }
if document["decision"].to_s == "eligible_for_director_review"
  numeric = rows.map { |row| row.to_h["result"] }.select { |value| value.is_a?(Integer) }
  errors << "03V promotion eligibility requires every applicable criterion at grade 3 or higher" unless numeric.length == required.length && numeric.all? { |value| value >= 3 }
  errors << "03V subject motion or intentional hold requires grade 4" unless by_id["subject_body_action_pose_transition"] == 4
  errors << "03V temporal camera or evidence-based locked hold requires grade 4" unless by_id["temporal_camera_route_or_locked_hold"] == 4
  errors << "03V audio/edit landing requires grade 4" unless by_id["audio_trigger_landing_edit_handoff"] == 4
end

abort errors.join("\n") unless errors.empty?
display_path = path.relative_path_from(options[:root]) rescue path
puts "03V contextual grade vector valid: #{display_path}"
