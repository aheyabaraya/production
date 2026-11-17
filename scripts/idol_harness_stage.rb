#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
EXECUTION_CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")

options = {
  registry: DEFAULT_REGISTRY,
  json: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_harness_stage.rb [options] validate|list|graph|resolve|list-phases|resolve-phase [TOKEN]"
  opts.on("--registry PATH", String, "Active stage registry path") do |value|
    options[:registry] = Pathname.new(value).expand_path
  end
  opts.on("--json", "Emit JSON for list and resolve commands") do
    options[:json] = true
  end
end

parser.parse!
command = ARGV.shift
token = ARGV.shift

unless %w[validate list graph resolve list-phases resolve-phase].include?(command)
  warn parser
  exit 2
end

unless options[:registry].file?
  warn "stage registry not found: #{options[:registry]}"
  exit 1
end

document = YAML.safe_load(options[:registry].read, aliases: false)
unless document.is_a?(Hash)
  warn "stage registry root must be an object"
  exit 1
end

phases = Array(document["phases"]).select { |item| item.is_a?(Hash) }
stages = Array(document["stages"]).select { |item| item.is_a?(Hash) }

def normalized_token(value)
  value.to_s.strip.downcase.gsub(/[\s-]+/, "_")
end

def frequencies(values)
  values.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }
end

def stage_tokens(stage)
  [stage["stage_id"], stage["code"], stage["name"]]
    .compact
    .map(&:to_s)
    .reject(&:empty?)
end

def phase_tokens(phase)
  [phase["phase_id"], phase["name"]]
    .compact
    .map(&:to_s)
    .reject(&:empty?)
end

def validate_registry(document, phases, stages)
  errors = []
  warnings = []

  unless document["schema_version"] == "idol-harness-stage-registry.v8"
    errors << "schema_version must be idol-harness-stage-registry.v8"
  end
  errors << "registry status must be active" unless document["status"] == "active"

  studio_execution = document["studio_execution"].is_a?(Hash) ? document["studio_execution"] : {}
  expected_execution = {
    "execution_contract_path" => "automation/harness-execution-contract.yaml",
    "department_dispatch_schema" => "schemas/department-dispatch.schema.json",
    "director_dispatch_index_schema" => "schemas/director-dispatch-index.schema.json",
    "reference_working_index_schema" => "schemas/reference-working-index.schema.json",
    "skill_load_profiles_registry" => "automation/harness-skill-load-profiles.yaml",
    "provider_profile_registry" => "automation/harness-provider-profile-registry.yaml",
    "founder_workbench_path_template" => "RUN/review/founder-workbench.html",
    "startup_owner" => "overall_director",
    "startup_development_session" => "creative_development_director",
    "director_profile_alias" => "director_deep",
    "worker_profile_alias" => "worker_high",
    "active_director_binding_rule" => "exactly_one_per_open_logical_role",
    "ordinary_department_and_section_worker" => "provider_resolved_worker_high",
    "native_subagent_policy" => "provider_native_default_without_project_numeric_or_depth_override",
    "canonical_promotion_owner" => "overall_director",
    "founder_conversation_owner" => "overall_director",
    "cdd_review_extent" => "pre_00_through_image_pixels_motion_storyboard_and_03v_playback",
    "edit_director_review_extent" => "stage_04_through_05",
    "ordinary_terra_route" => "forbidden"
  }
  expected_execution.each do |key, expected|
    errors << "studio_execution.#{key} must be #{expected}" unless studio_execution[key] == expected
  end
  %w[execution_contract_path department_dispatch_schema director_dispatch_index_schema reference_working_index_schema skill_load_profiles_registry provider_profile_registry].each do |key|
    relative = studio_execution[key].to_s
    errors << "studio_execution.#{key} is not readable: #{relative}" unless !relative.empty? && ROOT.join(relative).file?
  end

  migration = document["migration_policy"].is_a?(Hash) ? document["migration_policy"] : {}
  errors << "active compatibility branch must be none" unless migration["compatibility_branch"] == "none"
  errors << "historical artifacts must be evidence_only" unless migration["historical_artifact_use"] == "evidence_only"
  errors << "historical contract fallback must be forbidden" unless migration["fallback_to_historical_contracts"] == "forbidden"
  unless Array(migration["retired_active_stage_labels"]) == %w[00 01A 02]
    errors << "retired active stage labels must be exactly 00, 01A, and 02"
  end

  phase_ids = phases.map { |phase| phase["phase_id"].to_s }
  stage_ids = stages.map { |stage| stage["stage_id"].to_s }
  frequencies(phase_ids).each do |value, count|
    errors << "duplicate or blank phase_id: #{value}" if value.empty? || count > 1
  end
  frequencies(stage_ids).each do |value, count|
    errors << "duplicate or blank stage_id: #{value}" if value.empty? || count > 1
  end
  frequencies(phases.map { |phase| phase["order"] }).each do |value, count|
    errors << "duplicate phase order: #{value}" if count > 1
  end
  frequencies(stages.map { |stage| stage["order"] }).each do |value, count|
    errors << "duplicate stage order: #{value}" if count > 1
  end

  ordered_stages = stages.sort_by { |stage| stage["order"].to_i }
  stage_by_id = stages.to_h { |stage| [stage["stage_id"].to_s, stage] }
  token_owners = Hash.new { |hash, key| hash[key] = [] }

  stages.each do |stage|
    stage_id = stage["stage_id"].to_s
    owner_skill = stage["owner_skill"].to_s
    errors << "#{stage_id}: stage must be active" unless stage["active"] == true
    errors << "#{stage_id}: owner_skill is missing" if owner_skill.empty?
    unless owner_skill.empty?
      owner_skill_path = ROOT.join("skills", owner_skill, "SKILL.md")
      errors << "#{stage_id}: owner_skill does not resolve to an active skill: #{owner_skill}" unless owner_skill_path.file?
    end
    errors << "#{stage_id}: professional_role is missing" if stage["professional_role"].to_s.empty?

    stage_tokens(stage).each do |candidate|
      token_owners[normalized_token(candidate)] << stage_id
    end

    Array(stage["inputs"]).each do |input_id|
      input_stage = stage_by_id[input_id.to_s]
      if input_stage.nil?
        errors << "#{stage_id}: unknown input stage #{input_id}"
        next
      end
      if input_stage["order"].to_i >= stage["order"].to_i
        errors << "#{stage_id}: input stage #{input_id} must be earlier"
      end
    end

    Array(stage["output_contracts"]).each do |schema_path|
      resolved = ROOT.join(schema_path.to_s).cleanpath
      errors << "#{stage_id}: output contract is not readable: #{schema_path}" unless resolved.file?
    end
  end

  token_owners.each do |candidate, owners|
    unique_owners = owners.uniq
    errors << "stage token collision #{candidate.inspect}: #{unique_owners.join(', ')}" if unique_owners.length > 1
  end

  ordered_stage_ids = ordered_stages.map { |stage| stage["stage_id"].to_s }
  flattened_phase_ids = []
  phases.sort_by { |phase| phase["order"].to_i }.each do |phase|
    member_ids = Array(phase["stage_ids"]).map(&:to_s)
    flattened_phase_ids.concat(member_ids)
    frequencies(member_ids).each do |value, count|
      errors << "#{phase['phase_id']}: duplicate member stage #{value}" if value.empty? || count > 1
    end
    member_ids.each do |stage_id|
      errors << "#{phase['phase_id']}: unknown member stage #{stage_id}" unless stage_by_id.key?(stage_id)
    end
    known = member_ids.select { |stage_id| stage_by_id.key?(stage_id) }
    expected = known.sort_by { |stage_id| stage_by_id.fetch(stage_id)["order"].to_i }
    unless known == expected
      errors << "#{phase['phase_id']}: member stages must follow authoritative order"
    end
  end

  unless flattened_phase_ids == ordered_stage_ids
    errors << "phase stage coverage must equal the authoritative ordered active stage list"
  end

  retired_codes = %w[00 01A 02]
  active_retired = stages.select { |stage| retired_codes.include?(stage["code"].to_s) }
  unless active_retired.empty?
    errors << "retired stage codes remain active: #{active_retired.map { |stage| stage['code'] }.join(', ')}"
  end

  front_planning = stage_by_id["front_planning_integration"]
  required_substages = %w[
    audience_message_lock
    current_title_visual_package
    reference_connection_01r
    reference_crop_lock_01r_c
    member_and_section_assignment
    whole_film_and_section_spine
    founder_front_planning_review
  ]
  if front_planning.nil?
    errors << "front_planning_integration stage is required"
  else
    missing = required_substages - Array(front_planning["substage_ids"]).map(&:to_s)
    errors << "front_planning_integration is missing substages: #{missing.join(', ')}" unless missing.empty?
  end

  storyboard = stage_by_id["mv_storyboard_direction"]
  unless storyboard && Array(storyboard["output_contracts"]).include?("schemas/master-storyboard.schema.json")
    errors << "mv_storyboard_direction must own the master storyboard contract"
  end

  stage_01 = stage_by_id["mv_performance_direction"]
  unless stage_01 && Array(stage_01["output_contracts"]).include?("schemas/song-choreography-performance-mv-map.schema.json")
    errors << "mv_performance_direction must own the one-image Official Core contract"
  end

  if stage_01 && stage_01["name"] != "Section Direction And Official Core Storyboard"
    errors << "mv_performance_direction must name the Official Core storyboard ownership"
  end

  if storyboard && storyboard["name"] != "Imported-Core Branch Planning"
    errors << "mv_storyboard_direction must preserve imported Core ownership and own Branch planning only"
  end

  expected_session_routes = {
    "song_direction_design" => "cdd_physical_song_room",
    "candidate_track_analysis" => "cdd_physical_song_room",
    "audio_screen_motion_map" => "cdd_physical_song_room",
    "song_production_lock" => "cdd_physical_song_room",
    "front_planning_integration" => "creative_development_director",
    "mv_performance_direction" => "pre_02a_luna_development_block",
    "mv_storyboard_direction" => "pre_02a_luna_development_block",
    "storyboard_review" => "cdd_review_then_overall_milestone",
    "image_prompt_compilation" => "post_02a_luna_image_motion_lineage",
    "image_generation_release_gate" => "post_02a_luna_image_motion_lineage",
    "branch_cut_generation" => "post_02a_luna_image_motion_lineage",
    "generated_branch_cut_review" => "post_02a_luna_image_motion_lineage",
    "audio_branch_cut_placement" => "post_02a_luna_image_motion_lineage",
    "video_motion_direction" => "post_02a_luna_image_motion_lineage",
    "video_playback_review" => "post_02a_luna_image_motion_lineage",
    "edit_assembly_playback_qc" => "edit_director_04_05",
    "edit_finishing_fx" => "edit_director_04_05",
    "master_package_release" => "edit_director_04_05"
  }
  expected_session_routes.each do |stage_id, expected|
    actual = stage_by_id.dig(stage_id, "session_route")
    errors << "#{stage_id}: session_route must be #{expected}" unless actual == expected
  end

  video_motion = stage_by_id["video_motion_direction"]
  required_video_contracts = %w[
    schemas/video-prompt-storyboard-assist.schema.json
    schemas/video-prompt-manifest.schema.json
  ]
  if video_motion.nil?
    errors << "video_motion_direction stage is required"
  else
    missing = required_video_contracts - Array(video_motion["output_contracts"]).map(&:to_s)
    errors << "video_motion_direction is missing contracts: #{missing.join(', ')}" unless missing.empty?
  end

  [errors.uniq, warnings.uniq]
end

errors, warnings = validate_registry(document, phases, stages)

if command == "validate"
  warnings.each { |warning| warn "warning: #{warning}" }
  if errors.empty?
    puts "OK: active stage registry valid (#{phases.length} phases, #{stages.length} stages)"
    exit 0
  end

  errors.each { |error| warn "error: #{error}" }
  exit 1
end

unless errors.empty?
  errors.each { |error| warn "error: #{error}" }
  warn "refusing #{command}: registry is invalid"
  exit 1
end

ordered_stages = stages.sort_by { |stage| stage["order"].to_i }
ordered_phases = phases.sort_by { |phase| phase["order"].to_i }

if command == "resolve"
  if token.to_s.empty?
    warn "resolve requires TOKEN"
    exit 2
  end

  normalized = normalized_token(token)
  matches = ordered_stages.select do |stage|
    stage_tokens(stage).any? { |candidate| normalized_token(candidate) == normalized }
  end
  if matches.empty?
    warn "unknown active stage token: #{token}"
    exit 1
  end
  if matches.length > 1
    warn "ambiguous active stage token #{token}: #{matches.map { |stage| stage['stage_id'] }.join(', ')}"
    exit 1
  end

  puts(options[:json] ? JSON.pretty_generate(matches.first) : YAML.dump(matches.first))
  exit 0
end

if command == "resolve-phase"
  if token.to_s.empty?
    warn "resolve-phase requires TOKEN"
    exit 2
  end

  normalized = normalized_token(token)
  matches = ordered_phases.select do |phase|
    phase_tokens(phase).any? { |candidate| normalized_token(candidate) == normalized }
  end
  if matches.empty?
    warn "unknown active phase token: #{token}"
    exit 1
  end
  if matches.length > 1
    warn "ambiguous active phase token #{token}: #{matches.map { |phase| phase['phase_id'] }.join(', ')}"
    exit 1
  end

  phase = matches.first
  output = phase.merge(
    "stages" => Array(phase["stage_ids"]).map { |stage_id| ordered_stages.find { |stage| stage["stage_id"] == stage_id } }
  )
  puts(options[:json] ? JSON.pretty_generate(output) : YAML.dump(output))
  exit 0
end

if command == "graph"
  nodes = ordered_stages.map do |stage|
    {
      "stage_id" => stage["stage_id"],
      "code" => stage["code"],
      "order" => stage["order"],
      "owner_skill" => stage["owner_skill"],
      "output_contracts" => Array(stage["output_contracts"]),
      "declared_inputs" => Array(stage["inputs"])
    }
  end
  data_edges = []
  ordered_stages.each do |stage|
    Array(stage["inputs"]).each do |input_id|
      data_edges << {
        "from" => input_id.to_s,
        "to" => stage["stage_id"].to_s,
        "kind" => "declared_input"
      }
    end
  end
  order_adjacencies_without_declared_input = []
  ordered_stages.each_cons(2) do |left, right|
    inputs = Array(right["inputs"]).map(&:to_s)
    next if inputs.include?(left["stage_id"].to_s)

    order_adjacencies_without_declared_input << {
      "from" => left["stage_id"].to_s,
      "to" => right["stage_id"].to_s,
      "kind" => "order_adjacent_without_declared_input"
    }
  end
  execution = YAML.safe_load(EXECUTION_CONTRACT.read, aliases: false)
  provider_capacity = execution.is_a?(Hash) ? execution.dig("live_worker_capacity", "provider_capacity") : nil
  post_02a = execution.is_a?(Hash) ? execution["post_02a_session_routing"] : nil
  operational_wait_policy = {
    "source" => "automation/harness-execution-contract.yaml",
    "authority" => "read_only_projection",
    "launch_to_fill_capacity" => provider_capacity && provider_capacity["launch_to_fill_capacity"],
    "queue_when_director_review_pending" => provider_capacity && provider_capacity["queue_when_director_review_pending"],
    "queue_launch_when" => provider_capacity && provider_capacity["queue_launch_when"],
    "pixel_and_playback_review_window" => post_02a && post_02a["pixel_and_playback_review_window"],
    "does_not_change_stage_spine" => true
  }
  atlas = {
    "schema_version" => "idol-harness-stage-graph-atlas.v1",
    "authority" => "read_only_projection",
    "source" => "automation/harness-stage-registry.yaml",
    "nodes" => nodes,
    "data_edges" => data_edges,
    "order_adjacencies_without_declared_input" => order_adjacencies_without_declared_input,
    "operational_wait_policy" => operational_wait_policy
  }
  if options[:json]
    puts JSON.pretty_generate(atlas)
  else
    puts "schema_version\t#{atlas['schema_version']}"
    puts "authority\t#{atlas['authority']}"
    puts "nodes\t#{nodes.length}"
    puts "data_edges\t#{data_edges.length}"
    puts "order_adjacencies_without_declared_input\t#{order_adjacencies_without_declared_input.length}"
    puts "queue_launch_when\t#{operational_wait_policy['queue_launch_when']}"
    puts "from\tto\tkind"
    data_edges.each do |edge|
      puts [edge["from"], edge["to"], edge["kind"]].join("\t")
    end
    order_adjacencies_without_declared_input.each do |edge|
      puts [edge["from"], edge["to"], edge["kind"]].join("\t")
    end
  end
  exit 0
end

if command == "list-phases"
  rows = ordered_phases.map do |phase|
    {
      "order" => phase["order"],
      "phase_id" => phase["phase_id"],
      "name" => phase["name"],
      "stage_count" => Array(phase["stage_ids"]).length,
      "first_stage_id" => Array(phase["stage_ids"]).first,
      "last_stage_id" => Array(phase["stage_ids"]).last
    }
  end
  if options[:json]
    puts JSON.pretty_generate(rows)
  else
    puts "order\tphase_id\tname\tstage_count\tfirst_stage\tlast_stage"
    rows.each do |row|
      puts [
        row["order"],
        row["phase_id"],
        row["name"],
        row["stage_count"],
        row["first_stage_id"],
        row["last_stage_id"]
      ].join("\t")
    end
  end
  exit 0
end

rows = ordered_stages.map do |stage|
  {
    "order" => stage["order"],
    "stage_id" => stage["stage_id"],
    "code" => stage["code"],
    "name" => stage["name"],
    "owner_skill" => stage["owner_skill"],
    "professional_role" => stage["professional_role"],
    "scope" => stage["scope"],
    "founder_gate" => stage["founder_gate"]
  }
end

if options[:json]
  puts JSON.pretty_generate(rows)
else
  puts "order\tstage_id\tcode\tname\towner_skill\tprofessional_role\tscope\tfounder_gate"
  rows.each do |row|
    puts [
      row["order"],
      row["stage_id"],
      row["code"],
      row["name"],
      row["owner_skill"],
      row["professional_role"],
      row["scope"],
      row["founder_gate"]
    ].join("\t")
  end
end
