#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_REGISTRY = ROOT.join("automation", "harness-skill-load-profiles.yaml")
DEFAULT_SCHEMA = ROOT.join("schemas", "harness-skill-load-profiles.schema.json")
EXECUTION_CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")
PROVIDER_PROFILE_REGISTRY = ROOT.join("automation", "harness-provider-profile-registry.yaml")
STAGE_REGISTRY = ROOT.join("automation", "harness-stage-registry.yaml")
DEPARTMENT_DISPATCH_SCHEMA = ROOT.join("schemas", "department-dispatch.schema.json")

options = {json: false, registry: DEFAULT_REGISTRY, schema: DEFAULT_SCHEMA}
OptionParser.new do |parser|
  parser.on("--json") { options[:json] = true }
  parser.on("--registry PATH") { |value| options[:registry] = Pathname.new(value).expand_path }
  parser.on("--schema PATH") { |value| options[:schema] = Pathname.new(value).expand_path }
end.parse!

def load_yaml(path)
  value = YAML.safe_load(path.read, aliases: true)
  value.is_a?(Hash) ? value : {}
rescue Errno::ENOENT, Psych::Exception
  {}
end

errors = []
registry = options[:registry]
schema = options[:schema]

unless registry.file?
  errors << "skill-load profile registry is missing: #{registry}"
  document = {}
else
  stdout, stderr, status = Open3.capture3(
    ROOT.join("scripts", "idol-video-python").to_s,
    ROOT.join("scripts", "validate_json_schema.py").to_s,
    schema.to_s,
    registry.to_s,
    chdir: ROOT.to_s
  )
  errors << [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip unless status.success?
  document = load_yaml(registry)
end

skill_rows = Array(document["skill_bindings"]).select { |row| row.is_a?(Hash) }
read_rows = Array(document["read_bindings"]).select { |row| row.is_a?(Hash) }
binding_rows = skill_rows + read_rows
binding_ids = binding_rows.map { |row| row["binding_id"].to_s }
binding_paths = binding_rows.map { |row| row["path"].to_s }
binding_ids.group_by(&:itself).each { |id, rows| errors << "duplicate binding_id: #{id}" if id.empty? || rows.length > 1 }
binding_paths.group_by(&:itself).each { |path, rows| errors << "duplicate binding path: #{path}" if path.empty? || rows.length > 1 }

binding_rows.each do |row|
  relative = row["path"].to_s
  path = ROOT.join(relative).cleanpath
  begin
    repo_relative = path.relative_path_from(ROOT).to_s
    raise ArgumentError if repo_relative == ".." || repo_relative.start_with?("../")
  rescue ArgumentError
    errors << "binding path escapes repository: #{relative}"
    next
  end
  unless path.file?
    errors << "binding path is missing: #{relative}"
    next
  end
  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "binding SHA-256 is stale: #{relative}" unless actual == row["sha256"].to_s
end

# Report the actual registered checkpoint load, not a profile union or a
# static-startup estimate. Counts are whitespace-delimited words in the bytes
# resolved from each checkpoint's exact binding ids.
binding_word_counts = binding_rows.each_with_object({}) do |row, counts|
  path = ROOT.join(row["path"].to_s)
  counts[row["binding_id"].to_s] = path.file? ? path.read.split.length : 0
end

skill_ids = skill_rows.map { |row| row["binding_id"].to_s }.to_set
read_ids = read_rows.map { |row| row["binding_id"].to_s }.to_set
profiles = Array(document["profiles"]).select { |row| row.is_a?(Hash) }
profile_ids = profiles.map { |row| row["profile_id"].to_s }
profile_ids.group_by(&:itself).each { |id, rows| errors << "duplicate profile_id: #{id}" if id.empty? || rows.length > 1 }

execution = load_yaml(EXECUTION_CONTRACT)
expected_profiles = execution.dig("skill_load_profiles", "profiles")
expected_profile_ids = expected_profiles.is_a?(Hash) ? expected_profiles.keys.map(&:to_s) : []
profile_rows_by_id = profiles.each_with_object({}) { |row, memo| memo[row["profile_id"].to_s] = row }
missing_profile_ids = expected_profile_ids.to_set - profile_ids.to_set
extra_profile_ids = profile_ids.to_set - expected_profile_ids.to_set
# Execution v30 resolves provider profiles and active logical-role bindings. The
# checkpoint registry remains the canonical owner of skill-load profile ids, so
# compare aliases only when a compatibility contract explicitly publishes them.
missing_profile_ids.each do |profile_id|
  errors << "execution contract profile is missing from registry: #{profile_id}"
end
if expected_profiles.is_a?(Hash)
  extra_profile_ids.each do |profile_id|
    profile = profile_rows_by_id[profile_id] || {}
    errors << "unexpected non-maintenance profile outside execution contract: #{profile_id}" unless profile["maintenance_only"] == true
  end
end
if expected_profiles.is_a?(Hash)
  expected_profiles.each do |profile_id, alias_body|
    expected_alias = {"profile_id" => profile_id.to_s}
    errors << "execution contract profile entry must be an alias only: #{profile_id}" unless alias_body == expected_alias
  end
end

dispatch_schema = JSON.parse(DEPARTMENT_DISPATCH_SCHEMA.read)
dispatch_output_kinds = Array(dispatch_schema.dig("$defs", "outputKind", "enum")).map(&:to_s).to_set

stage_document = load_yaml(STAGE_REGISTRY)
known_stage_ids = Array(stage_document["stages"]).each_with_object([]) do |row, ids|
  ids << row["stage_id"].to_s if row.is_a?(Hash)
end.to_set
known_roles = execution.fetch("authority", {}).keys.map(&:to_s).to_set
known_roles.merge(%w[founder board_coordinator overall_director creative_development_director edit_director])
maintenance_read_ids = Set.new(%w[
  maintenance_rules
  maintenance_instruction_policy_wiki
  maintenance_schema_contract_registry
  maintenance_skill_profile_routing
  maintenance_script_validator_registry
  maintenance_workbench_runtime_ui
])
nonruntime_script_registry_ids = Set.new(%w[
  scripts_full_index
  idol_script_registry
  idol_script_registry_schema
  idol_script_registry_check
])
script_guide_ids = Set.new(%w[
  scripts_guide_state_contracts
  scripts_guide_validators
  scripts_guide_research_evidence
  scripts_guide_review_planning
  scripts_guide_image_title
  scripts_guide_video_playback
  scripts_guide_edit_qc
  scripts_guide_release_platform
  scripts_guide_runtime_libraries
  scripts_guide_legacy_one_off
])

profiles.each do |profile|
  profile_id = profile["profile_id"].to_s
  maintenance_only = profile["maintenance_only"] == true
  projection_only = profile["projection_only"] == true
  errors << "unknown profile role: #{profile_id}=#{profile['role']}" unless known_roles.include?(profile["role"].to_s)
  maintenance_only = profile["maintenance_only"] == true
  Array(profile["stage_ids"]).each do |stage_id|
    errors << "unknown stage id in #{profile_id}: #{stage_id}" unless maintenance_only || projection_only || known_stage_ids.include?(stage_id.to_s)
  end
  if maintenance_only && !Array(profile["stage_ids"]).empty?
    errors << "maintenance-only profile must not invent a creative stage: #{profile_id}"
  elsif projection_only && !Array(profile["stage_ids"]).empty?
    errors << "projection-only profile must not invent a creative stage: #{profile_id}"
  elsif !maintenance_only && !projection_only && Array(profile["stage_ids"]).empty?
    errors << "creative profile must declare at least one stage: #{profile_id}"
  end
  Array(profile["required_skill_ids"]).each do |binding_id|
    errors << "unknown skill binding in #{profile_id}: #{binding_id}" unless skill_ids.include?(binding_id.to_s)
  end
  Array(profile["required_read_ids"]).each do |binding_id|
    errors << "unknown read binding in #{profile_id}: #{binding_id}" unless read_ids.include?(binding_id.to_s)
  end
  phase_load = profile["phase_load"].is_a?(Hash) ? profile["phase_load"] : {}
  [phase_load].concat(Array(phase_load["checkpoints"])).each do |phase|
    next unless phase.is_a?(Hash)
    Array(phase["preload_skill_ids"] || phase["required_skill_ids"]).each do |binding_id|
      errors << "unknown phase skill binding in #{profile_id}: #{binding_id}" unless skill_ids.include?(binding_id.to_s)
    end
    Array(phase["preload_read_ids"] || phase["required_read_ids"]).each do |binding_id|
      errors << "unknown phase read binding in #{profile_id}: #{binding_id}" unless read_ids.include?(binding_id.to_s)
    end
  end
  recipient = profile.dig("return_route", "recipient_role").to_s
  errors << "unknown return recipient in #{profile_id}: #{recipient}" unless known_roles.include?(recipient)
  Array(profile.dig("output_contract", "kinds")).each do |output_kind|
    errors << "profile output kind is outside Department Dispatch v8: #{profile_id}=#{output_kind}" unless dispatch_output_kinds.include?(output_kind.to_s)
  end

  allowed_skills = Array(profile["required_skill_ids"]).map(&:to_s).to_set
  allowed_reads = Array(profile["required_read_ids"]).map(&:to_s).to_set
  used_skills = Array(phase_load["preload_skill_ids"]).map(&:to_s).to_set
  used_reads = Array(phase_load["preload_read_ids"]).map(&:to_s).to_set
  Array(phase_load["checkpoints"]).each do |checkpoint|
    next unless checkpoint.is_a?(Hash)
    checkpoint_id = checkpoint["checkpoint_id"].to_s
    checkpoint_skills = Array(checkpoint["required_skill_ids"]).map(&:to_s).to_set
    checkpoint_reads = Array(checkpoint["required_read_ids"]).map(&:to_s).to_set
    if maintenance_only
      errors << "maintenance checkpoint must not load a creative skill: #{profile_id}.#{checkpoint_id}" unless checkpoint_skills.empty?
    elsif checkpoint_skills.empty?
      errors << "creative checkpoint must declare at least one skill: #{profile_id}.#{checkpoint_id}"
    end
    (checkpoint_skills - allowed_skills).each do |binding_id|
      errors << "checkpoint skill is outside profile allowed union: #{profile_id}.#{checkpoint_id}=#{binding_id}"
    end
    (checkpoint_reads - allowed_reads).each do |binding_id|
      errors << "checkpoint read is outside profile allowed union: #{profile_id}.#{checkpoint_id}=#{binding_id}"
    end
    used_skills.merge(checkpoint_skills)
    used_reads.merge(checkpoint_reads)
  end
  (allowed_skills - used_skills).each { |binding_id| errors << "unused profile skill binding: #{profile_id}=#{binding_id}" }
  (allowed_reads - used_reads).each { |binding_id| errors << "unused profile read binding: #{profile_id}=#{binding_id}" }
  if maintenance_only
    errors << "maintenance-only profile must not load a creative skill: #{profile_id}" unless allowed_skills.empty?
  else
    errors << "creative profile must declare at least one skill: #{profile_id}" if allowed_skills.empty?
    (used_reads & maintenance_read_ids).each do |binding_id|
      errors << "creative profile must not load maintenance context: #{profile_id}=#{binding_id}"
    end
    (used_reads & nonruntime_script_registry_ids).each do |binding_id|
      errors << "creative profile must not load full script discovery/maintenance surface: #{profile_id}=#{binding_id}"
    end
    Array(phase_load["checkpoints"]).each do |checkpoint|
      next unless checkpoint.is_a?(Hash)

      checkpoint_id = checkpoint["checkpoint_id"].to_s
      checkpoint_reads = Array(checkpoint["required_read_ids"]).map(&:to_s).to_set
      selected_guides = checkpoint_reads & script_guide_ids
      if checkpoint_reads.include?("scripts_start_here") && selected_guides.empty?
        errors << "profiled script checkpoint must load one exact role guide: #{profile_id}.#{checkpoint_id}"
      elsif !selected_guides.empty? && !checkpoint_reads.include?("scripts_start_here")
        errors << "script role guide requires Start Here: #{profile_id}.#{checkpoint_id}"
      end
    end
  end
end

recipient_contract = {
  "pre_song_research" => "creative_development_director",
  "song_room_prompt" => "creative_development_director",
  "song_room_00a" => "creative_development_director",
  "reference_research_generalist" => "creative_development_director",
  "world_still_reference_department" => "creative_development_director",
  "pinterest_visual_composition_worker" => "creative_development_director",
  "source_hub_registration" => "creative_development_director",
  "member_visual_identity" => "creative_development_director",
  "pre_02a_development_block_fp" => "creative_development_director",
  "post_02a_02b_image" => "creative_development_director",
  "post_02a_03v" => "creative_development_director",
  "edit_director" => "overall_director",
  "edit_shard" => "edit_director",
  "founder_briefing" => "overall_director"
}
profiles_by_id = profiles.each_with_object({}) { |row, memo| memo[row["profile_id"].to_s] = row }
maintenance_profile = profiles_by_id["harness_maintenance"] || {}
maintenance_surface_ids = %w[
  instruction_policy_wiki
  schema_contract_registry
  skill_profile_routing
  script_validator_registry
  workbench_runtime_ui
]
if maintenance_profile.empty?
  errors << "maintenance-only profile is missing: harness_maintenance"
else
  errors << "harness_maintenance must declare maintenance_only=true" unless maintenance_profile["maintenance_only"] == true
  errors << "harness_maintenance must use mechanical_coordinator" unless maintenance_profile["role"].to_s == "mechanical_coordinator"
  errors << "harness_maintenance must not declare a creative stage" unless Array(maintenance_profile["stage_ids"]).empty?
  errors << "harness_maintenance must not load a creative skill" unless Array(maintenance_profile["required_skill_ids"]).empty?
  actual_surfaces = Array(maintenance_profile["maintenance_surface_ids"]).map(&:to_s)
  errors << "harness_maintenance surface ids must match registered change surfaces" unless actual_surfaces.to_set == maintenance_surface_ids.to_set
  expected_maintenance_reads = Set.new(%w[
    agents production_system maintenance_rules department_dispatch_schema
    maintenance_instruction_policy_wiki maintenance_schema_contract_registry
    maintenance_skill_profile_routing maintenance_script_validator_registry
    maintenance_workbench_runtime_ui
    scripts_start_here scripts_full_index idol_script_registry
    idol_script_registry_schema idol_script_registry_check
    scripts_guide_state_contracts scripts_guide_validators
    scripts_guide_research_evidence scripts_guide_review_planning
    scripts_guide_image_title scripts_guide_video_playback
    scripts_guide_edit_qc scripts_guide_release_platform
    scripts_guide_runtime_libraries scripts_guide_legacy_one_off
  ])
  actual_maintenance_reads = Array(maintenance_profile["required_read_ids"]).map(&:to_s).to_set
  errors << "harness_maintenance allowed read union must contain the compact core and all modules" unless actual_maintenance_reads == expected_maintenance_reads
  expected_maintenance_checkpoints = maintenance_surface_ids
  actual_maintenance_checkpoints = Array(maintenance_profile.dig("phase_load", "checkpoints")).each_with_object([]) do |row, ids|
    ids << row["checkpoint_id"].to_s if row.is_a?(Hash)
  end
  errors << "harness_maintenance checkpoints must match registered change surfaces" unless actual_maintenance_checkpoints.to_set == expected_maintenance_checkpoints.to_set
  core_reads = Set.new(%w[agents production_system maintenance_rules department_dispatch_schema])
  module_by_checkpoint = {
    "instruction_policy_wiki" => "maintenance_instruction_policy_wiki",
    "schema_contract_registry" => "maintenance_schema_contract_registry",
    "skill_profile_routing" => "maintenance_skill_profile_routing",
    "script_validator_registry" => "maintenance_script_validator_registry",
    "workbench_runtime_ui" => "maintenance_workbench_runtime_ui"
  }
  script_registry_reads = Set.new(%w[
    scripts_start_here scripts_full_index idol_script_registry
    idol_script_registry_schema idol_script_registry_check
    scripts_guide_state_contracts scripts_guide_validators
    scripts_guide_research_evidence scripts_guide_review_planning
    scripts_guide_image_title scripts_guide_video_playback
    scripts_guide_edit_qc scripts_guide_release_platform
    scripts_guide_runtime_libraries scripts_guide_legacy_one_off
  ])
  Array(maintenance_profile.dig("phase_load", "checkpoints")).each do |checkpoint|
    next unless checkpoint.is_a?(Hash)
    checkpoint_id = checkpoint["checkpoint_id"].to_s
    actual_skills = Array(checkpoint["required_skill_ids"]).map(&:to_s)
    actual_reads = Array(checkpoint["required_read_ids"]).map(&:to_s).to_set
    expected_reads = core_reads | Set[module_by_checkpoint[checkpoint_id].to_s]
    expected_reads |= script_registry_reads if checkpoint_id == "script_validator_registry"
    errors << "maintenance checkpoint must not load a creative skill: #{checkpoint_id}" unless actual_skills.empty?
    errors << "maintenance checkpoint must load compact core plus one selected module: #{checkpoint_id}" unless actual_reads == expected_reads
    errors << "maintenance checkpoint must preserve same-lineage unload boundary: #{checkpoint_id}" unless checkpoint["same_lineage"] == true && checkpoint["unload_after"].to_s == "maintenance_review_return"
  end
end

founder_briefing_profile = profiles_by_id["founder_briefing"] || {}
if founder_briefing_profile.empty?
  errors << "projection-only profile is missing: founder_briefing"
else
  expected_briefing_reads = Set.new(%w[
    agents routing_policy production_system artifact_management
    harness_execution_contract director_dispatch_index_schema
    harness_current_next_schema workbench_run_route_manifest_schema
    founder_briefing_schema
  ])
  errors << "founder_briefing must declare projection_only=true" unless founder_briefing_profile["projection_only"] == true
  errors << "founder_briefing must use department_worker" unless founder_briefing_profile["role"].to_s == "department_worker"
  errors << "founder_briefing must not declare a creative stage" unless Array(founder_briefing_profile["stage_ids"]).empty?
  errors << "founder_briefing must load only its bounded briefing skill" unless Array(founder_briefing_profile["required_skill_ids"]).map(&:to_s) == ["founder_briefing_assistant"]
  errors << "founder_briefing read union must remain bounded" unless Array(founder_briefing_profile["required_read_ids"]).map(&:to_s).to_set == expected_briefing_reads
  briefing_checkpoints = Array(founder_briefing_profile.dig("phase_load", "checkpoints"))
  errors << "founder_briefing must expose one briefing_refresh checkpoint" unless briefing_checkpoints.length == 1 && briefing_checkpoints.first["checkpoint_id"].to_s == "briefing_refresh"
  if briefing_checkpoints.length == 1
    checkpoint = briefing_checkpoints.first
    errors << "founder_briefing checkpoint must load its bounded skill" unless Array(checkpoint["required_skill_ids"]).map(&:to_s) == ["founder_briefing_assistant"]
    errors << "founder_briefing checkpoint read set must remain bounded" unless Array(checkpoint["required_read_ids"]).map(&:to_s).to_set == expected_briefing_reads
    errors << "founder_briefing checkpoint must return to Overall review" unless checkpoint["same_lineage"] == true && checkpoint["unload_after"].to_s == "overall_director_review_return"
    expected_activation = "reviewed_milestone_source_set_digest_changed_or_founder_explicit_refresh_never_ui_open_alone"
    errors << "founder_briefing checkpoint must not launch a model turn from UI open alone" unless checkpoint["activation"].to_s == expected_activation
  end
  errors << "founder_briefing must return only the bounded Founder briefing projection kind" unless Array(founder_briefing_profile.dig("output_contract", "kinds")).map(&:to_s) == ["founder_briefing_projection"]
  errors << "founder_briefing must remain noncanonical" unless founder_briefing_profile.dig("output_contract", "canonical_write").to_s == "forbidden"
  expected_projection_route = "overall_review_then_mechanical_projection_publication_no_creative_promotion"
  errors << "founder_briefing must publish only reviewed projection bytes without creative promotion" unless founder_briefing_profile.dig("return_route", "promotion_route").to_s == expected_projection_route
end

recipient_contract.each do |profile_id, expected|
  actual = profiles_by_id.dig(profile_id, "return_route", "recipient_role").to_s
  errors << "return recipient mismatch for #{profile_id}: expected #{expected}, got #{actual}" unless actual == expected
end

declared_profile_checkpoints = profiles_by_id.transform_values do |profile|
  Array(profile.dig("phase_load", "checkpoints")).map { |checkpoint| checkpoint["checkpoint_id"].to_s }.to_set
end
skill_rows.each do |row|
  skill_path = ROOT.join(row["path"].to_s)
  next unless skill_path.file?

  skill_path.read.scan(/`([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)`/).each do |profile_id, checkpoint_id|
    next unless profiles_by_id.key?(profile_id)

    unless declared_profile_checkpoints.fetch(profile_id).include?(checkpoint_id)
      errors << "skill names an unregistered profile checkpoint: #{row['path']}=#{profile_id}.#{checkpoint_id}"
    end
  end
end

storyboard_stage = Array(stage_document["stages"]).find { |row| row.is_a?(Hash) && row["stage_id"].to_s == "mv_storyboard_direction" } || {}
unless storyboard_stage["owner_skill"].to_s == "idol-front-planning-development-block"
  errors << "mv_storyboard_direction must stay owned by the pre-02A development block"
end
storyboard_review_stage = Array(stage_document["stages"]).find { |row| row.is_a?(Hash) && row["stage_id"].to_s == "storyboard_review" } || {}
unless storyboard_review_stage["owner_skill"].to_s == "idol-front-planning-director"
  errors << "storyboard_review must stay owned by the CDD planning reviewer"
end
front_planning_stage = Array(stage_document["stages"]).find { |row| row.is_a?(Hash) && row["stage_id"].to_s == "front_planning_integration" } || {}
unless front_planning_stage["session_route"].to_s == "creative_development_director"
  errors << "Front Planning must stay in the CDD session route"
end
if front_planning_stage["professional_role"].to_s.match?(/\boverall\b/i)
  errors << "Front Planning professional role must not imply Overall promotion authority"
end

if profiles_by_id.key?("grok_worker_adapter")
  errors << "Grok transport adapter must not be a task skill-load profile"
end
provider_registry = load_yaml(PROVIDER_PROFILE_REGISTRY)
unless execution.dig("provider_profile_resolution", "registry_path").to_s == "automation/harness-provider-profile-registry.yaml"
  errors << "execution v33 must resolve provider profiles through the active provider registry"
end
%w[director_deep worker_high].each do |logical_alias|
  grok_source = provider_registry.dig("logical_profiles", logical_alias, "providers", "grok")
  errors << "provider registry missing Grok #{logical_alias} source outside task profiles" unless grok_source.is_a?(Hash)
end

def profile_binding_set(profile, kind)
  phase_load = profile["phase_load"].is_a?(Hash) ? profile["phase_load"] : {}
  values = Array(profile["required_#{kind}_ids"]) + Array(phase_load["preload_#{kind}_ids"])
  Array(phase_load["checkpoints"]).each do |checkpoint|
    values.concat(Array(checkpoint["required_#{kind}_ids"])) if checkpoint.is_a?(Hash)
  end
  values.map(&:to_s).to_set
end

def checkpoint_by_id(profile, checkpoint_id)
  Array(profile.dig("phase_load", "checkpoints")).find do |checkpoint|
    checkpoint.is_a?(Hash) && checkpoint["checkpoint_id"].to_s == checkpoint_id
  end || {}
end

def require_checkpoint_bindings(errors, profile, checkpoint_id, kind, expected)
  checkpoint = checkpoint_by_id(profile, checkpoint_id)
  actual = Array(checkpoint["required_#{kind}_ids"]).map(&:to_s).to_set
  Set.new(expected).each do |binding_id|
    errors << "#{profile['profile_id']}.#{checkpoint_id} missing #{kind} binding: #{binding_id}" unless actual.include?(binding_id)
  end
  actual
end

def require_checkpoint_set(errors, profile, expected)
  actual = Array(profile.dig("phase_load", "checkpoints")).each_with_object([]) do |checkpoint, ids|
    ids << checkpoint["checkpoint_id"].to_s if checkpoint.is_a?(Hash)
  end.to_set
  expected = Set.new(expected)
  (expected - actual).each { |checkpoint_id| errors << "#{profile['profile_id']} missing checkpoint: #{checkpoint_id}" }
  (actual - expected).each { |checkpoint_id| errors << "#{profile['profile_id']} has unregistered checkpoint: #{checkpoint_id}" }
  actual
end

# Authority and phase-minimality contracts. The schema proves shape; these
# checks prove that a worker profile cannot silently inherit a director or a
# neighboring production phase.
profiles.each do |profile|
  profile_id = profile["profile_id"].to_s
  skills = profile_binding_set(profile, "skill")
  reads = profile_binding_set(profile, "read")
  if skills.include?("front_planning_director") && profile_id != "creative_development_director"
    errors << "CDD skill may load only in creative_development_director: #{profile_id}"
  end

  next unless profile_id.start_with?("pre_02a_development_block_")

  forbidden_skills = %w[front_planning_director generation video_prompt editing_qc edit_finishing_fx shot_vfx]
  forbidden_reads = %w[generation_02a_handoff generation_prompt_compile generation_render_correction prompt_packet_delta_schema prompt_packets_schema image_generation_request_schema generated_review_schema html_review_board_schema fp_founder_visual_contract]
  (skills & forbidden_skills.to_set).each { |binding_id| errors << "pre-02A profile loads forbidden phase/authority skill: #{profile_id}=#{binding_id}" }
  (reads & forbidden_reads.to_set).each { |binding_id| errors << "pre-02A profile loads forbidden phase/board read: #{profile_id}=#{binding_id}" }
  errors << "pre-02A profile must retain development-block authority shell: #{profile_id}" unless skills.include?("front_planning_development_block")
end

reference_profile = profiles_by_id["reference_research_generalist"] || {}
reference_skills = profile_binding_set(reference_profile, "skill")
reference_reads = profile_binding_set(reference_profile, "read")
reference_holds = Array(reference_profile["hold_conditions"]).map(&:to_s).to_set
errors << "reference research worker must not load source-hub owner skill" if reference_skills.include?("video_reference_hub")
errors << "reference research worker must use only its bounded owner skill" unless reference_skills == Set["reference_research_department"]
errors << "reference research worker must load Reference Working Index schema" unless reference_reads.include?("reference_working_index_schema")
%w[sequence_motion_analysis_schema sequence_motion_analysis_validator].each do |binding_id|
  errors << "reference research worker missing Sequence Motion contract read: #{binding_id}" unless reference_reads.include?(binding_id)
end
required_reference_role_checkpoints = Set[
  "reference_story_sequence_role",
  "reference_camera_composition_role",
  "reference_world_object_material_role",
  "reference_performance_role",
  "reference_named_gap"
]
actual_reference_role_checkpoints = declared_profile_checkpoints.fetch("reference_research_generalist", Set.new)
(required_reference_role_checkpoints - actual_reference_role_checkpoints).each do |checkpoint_id|
  errors << "reference research profile missing role checkpoint: #{checkpoint_id}"
end
reference_story_reads = Array(checkpoint_by_id(reference_profile, "reference_story_sequence_role")["required_read_ids"]).map(&:to_s).to_set
%w[sequence_motion_analysis_schema sequence_motion_analysis_validator].each do |binding_id|
  errors << "reference_story_sequence_role missing Sequence Motion read: #{binding_id}" unless reference_story_reads.include?(binding_id)
end
reference_camera_reads = Array(checkpoint_by_id(reference_profile, "reference_camera_composition_role")["required_read_ids"]).map(&:to_s).to_set
reference_world_reads = Array(checkpoint_by_id(reference_profile, "reference_world_object_material_role")["required_read_ids"]).map(&:to_s).to_set
reference_performance_reads = Array(checkpoint_by_id(reference_profile, "reference_performance_role")["required_read_ids"]).map(&:to_s).to_set
reference_named_gap_reads = Array(checkpoint_by_id(reference_profile, "reference_named_gap")["required_read_ids"]).map(&:to_s).to_set
video_protocol_reads = Set[
  "source_video_readme",
  "source_video_read_first",
  "video_first_read_contract",
  "scripts_start_here",
  "scripts_guide_research_evidence"
]
still_protocol_reads = Set["source_image_readme", "world_still_contact_sheet_contract"]
{
  "reference_story_sequence_role" => reference_story_reads,
  "reference_camera_composition_role" => reference_camera_reads,
  "reference_performance_role" => reference_performance_reads
}.each do |checkpoint_id, reads|
  (video_protocol_reads - reads).each { |binding_id| errors << "#{checkpoint_id} missing role video read: #{binding_id}" }
  (reads & still_protocol_reads).each { |binding_id| errors << "#{checkpoint_id} loads unrelated still read: #{binding_id}" }
end
(still_protocol_reads - reference_world_reads).each { |binding_id| errors << "reference_world_object_material_role missing role still read: #{binding_id}" }
(reference_world_reads & video_protocol_reads).each { |binding_id| errors << "reference_world_object_material_role loads unrelated video read: #{binding_id}" }
((reference_named_gap_reads & video_protocol_reads) | (reference_named_gap_reads & still_protocol_reads)).each do |binding_id|
  errors << "reference_named_gap must not preselect a source-medium protocol: #{binding_id}"
end
errors << "reference_camera_composition_role missing camera vocabulary read: mv_camera_module" unless reference_camera_reads.include?("mv_camera_module")
{
  "reference_story_sequence_role" => reference_story_reads,
  "reference_world_object_material_role" => reference_world_reads,
  "reference_performance_role" => reference_performance_reads,
  "reference_named_gap" => reference_named_gap_reads
}.each do |checkpoint_id, reads|
  errors << "#{checkpoint_id} must not preload camera vocabulary" if reads.include?("mv_camera_module")
end

pre_song_profile = profiles_by_id["pre_song_research"] || {}
require_checkpoint_bindings(errors, pre_song_profile, "pre00_scan", "read", %w[
  agents production_system routing_policy media_security_policy
  radar_authoring_detail pre00_radar_schema
])

song_prompt_profile = profiles_by_id["song_room_prompt"] || {}
song_prompt_base_reads = %w[
  agents production_system routing_policy pre00_song_system
  production_bible trend_pulse_latest
  voice_style_index department_dispatch_schema suno_prompt_authoring_detail
]
require_checkpoint_bindings(errors, song_prompt_profile, "song_prompt_authoring", "read", song_prompt_base_reads)
require_checkpoint_bindings(errors, song_prompt_profile, "song_prompt_reference_fit", "read", song_prompt_base_reads + ["reference_song_fit_schema"])
%w[song_prompt_authoring song_prompt_reference_fit].each do |checkpoint_id|
  reads = Array(checkpoint_by_id(song_prompt_profile, checkpoint_id)["required_read_ids"]).map(&:to_s)
  errors << "#{checkpoint_id} must not preload post-05 social automation" if reads.include?("social_automation_system")
end

song_00a_profile = profiles_by_id["song_room_00a"] || {}
song_00a_base_reads = %w[
  agents production_system routing_policy creative_constitution
  pre00_song_system department_dispatch_schema song_lock_detail
]
require_checkpoint_bindings(errors, song_00a_profile, "selected_audio_analysis", "read", song_00a_base_reads + %w[selected_audio_schema scripts_start_here scripts_guide_research_evidence])
require_checkpoint_bindings(errors, song_00a_profile, "audio_screen_motion_map", "read", song_00a_base_reads + %w[selected_audio_schema audio_motion_schema scripts_start_here scripts_guide_research_evidence])
require_checkpoint_bindings(errors, song_00a_profile, "song_production_lock", "read", song_00a_base_reads + %w[selected_audio_schema audio_motion_schema song_lock_schema])

cdd_profile = profiles_by_id["creative_development_director"] || {}
cdd_reads = profile_binding_set(cdd_profile, "read")
require_checkpoint_set(errors, cdd_profile, %w[cdd_startup cdd_direction_alignment cdd_sequence_motion_review cdd_02a_final_planning_review])
required_cdd_reads = Set[
  "media_security_policy",
  "harness_execution_contract",
  "provider_neutral_studio_kernel",
  "orchestration_routing_detail",
  "department_dispatch_schema",
  "front_planning_schema",
  "sequence_motion_analysis_schema",
  "sequence_motion_analysis_validator",
  "director_dispatch_index_schema",
  "reference_working_index_schema"
]
(required_cdd_reads - cdd_reads).each { |binding_id| errors << "CDD profile missing canonical contract read: #{binding_id}" }
errors << "CDD canonical_write must be forbidden" unless cdd_profile.dig("output_contract", "canonical_write") == "forbidden"
errors << "CDD profile must own storyboard_review after the continuous FP-to-02A epoch" unless Array(cdd_profile["stage_ids"]).include?("storyboard_review")
errors << "CDD assigned owner must remain creative_development_director" unless cdd_profile.dig("authority", "assigned_owner") == "creative_development_director"
errors << "CDD review owner must remain Overall" unless cdd_profile.dig("authority", "review_owner") == "overall_director"
errors << "CDD promotion owner must remain Overall" unless cdd_profile.dig("authority", "promotion_owner") == "overall_director"
errors << "CDD return route must remain Overall" unless cdd_profile.dig("return_route", "recipient_role") == "overall_director"
require_checkpoint_bindings(errors, cdd_profile, "cdd_02a_final_planning_review", "read", %w[
  section_slice_schema creative_context_review_schema llm_review_execution_record_schema
  founder_review_decision_intake_schema html_review_board_schema
  fp_operating_contract fp_reference_management fp_harness_wiki
  fp_founder_visual_contract
])
cdd_startup_reads = Array(checkpoint_by_id(cdd_profile, "cdd_startup")["required_read_ids"]).map(&:to_s).to_set
%w[director_room_discovery fp_harness_wiki fp_founder_visual_contract].each do |binding_id|
  errors << "CDD startup must defer checkpoint-specific read to JIT review: #{binding_id}" if cdd_startup_reads.include?(binding_id)
end
cdd_direction_reads = require_checkpoint_bindings(errors, cdd_profile, "cdd_direction_alignment", "read", %w[
  director_room_discovery fp_founder_visual_contract
])
errors << "CDD direction alignment must load its own Founder visual contract" unless cdd_direction_reads.include?("fp_founder_visual_contract")
errors << "CDD direction alignment must load sequence-discovery detail" unless cdd_direction_reads.include?("director_room_discovery")
errors << "CDD direction alignment must load Front Planning film procedure" unless cdd_direction_reads.include?("section_production_front_planning")
errors << "cdd_direction_alignment must not preload camera vocabulary" if cdd_direction_reads.include?("mv_camera_module")
errors << "CDD direction alignment must not load 02B packet-compile procedure" if cdd_direction_reads.include?("section_production_02b_pixel")
errors << "CDD direction alignment must not load 04 edit-unit procedure" if cdd_direction_reads.include?("section_production_04")
errors << "CDD skill may load only in creative_development_director" unless profile_binding_set(cdd_profile, "skill") == Set["front_planning_director"]
cdd_sequence_reads = require_checkpoint_bindings(errors, cdd_profile, "cdd_sequence_motion_review", "read", %w[
  front_planning_schema reference_working_index_schema
  sequence_motion_analysis_schema sequence_motion_analysis_validator
  fp_operating_contract fp_reference_management
])
errors << "CDD Sequence Motion review must not preload unrelated Founder board detail" if cdd_sequence_reads.include?("fp_founder_visual_contract")
errors << "CDD final planning must defer sequence-discovery detail after Direction Alignment" if Array(checkpoint_by_id(cdd_profile, "cdd_02a_final_planning_review")["required_read_ids"]).map(&:to_s).include?("director_room_discovery")

overall_profile = profiles_by_id["overall_director"] || {}
overall_reads = profile_binding_set(overall_profile, "read")
required_overall_reads = Set[
  "harness_stage_registry",
  "harness_execution_contract",
  "provider_neutral_studio_kernel",
  "orchestration_routing_detail",
  "department_dispatch_schema"
]
(required_overall_reads - overall_reads).each { |binding_id| errors << "Overall profile missing orchestration contract read: #{binding_id}" }
errors << "Overall assigned owner must remain overall_director" unless overall_profile.dig("authority", "assigned_owner") == "overall_director"
errors << "Overall review owner must remain overall_director" unless overall_profile.dig("authority", "review_owner") == "overall_director"
errors << "Overall promotion owner must remain overall_director" unless overall_profile.dig("authority", "promotion_owner") == "overall_director"
errors << "Overall return route must remain Founder" unless overall_profile.dig("return_route", "recipient_role") == "founder"
overall_startup_reads = Array(checkpoint_by_id(overall_profile, "director_startup")["required_read_ids"]).map(&:to_s).to_set
errors << "Overall startup must load the compact stage map" unless overall_startup_reads.include?("production_system")
errors << "Overall startup must load the section owner/smallest-owner index" unless overall_startup_reads.include?("section_production_policy")
errors << "Overall startup must not load 02B compile procedure" if overall_startup_reads.include?("section_production_02b_pixel")
errors << "Overall startup must not load 04 edit-unit procedure" if overall_startup_reads.include?("section_production_04")

helper_policy = execution.dig("execution_topology", "provider_native_helper_policy") || {}
errors << "provider-native helpers must be available by default" unless helper_policy["availability"] == "default"
errors << "provider-native helpers must not use a project numeric gate" unless helper_policy["project_numeric_gate"] == "none"
errors << "provider-native helpers must not use a depth gate" unless helper_policy["depth_gate"] == "none"
errors << "provider-native helpers must not gain a logical role" unless helper_policy["logical_role_granted"] == false
unless execution.dig("execution_topology", "physical_transfer_policy", "same_work_package_simultaneous_internal_and_physical_owner") == "forbidden"
  errors << "one Work Package must not have simultaneous internal and physical owners"
end
selection_policy = provider_registry.fetch("selection_policy", {})
errors << "provider registry must keep adaptive physical-session selection" unless selection_policy["physical_session_selection"] == "adaptive_registered_assignment"
errors << "provider registry must forbid internal/physical active-owner overlap" unless selection_policy["internal_and_physical_active_owner_overlap"] == "forbidden"

binding_contract = {
  "overall_director" => ["founder", "exclusive_owner"],
  "creative_development_director" => ["overall_director", "none"],
  "edit_director" => ["overall_director", "none"]
}
binding_contract.each do |role, (recipient, founder_authority)|
  binding = execution.dig("active_role_bindings", role) || {}
  errors << "#{role} must require exactly one run-owned active binding" unless binding["required_active_binding_count"] == 1
  errors << "#{role} active binding logical_role mismatch" unless binding["logical_role"] == role
  errors << "#{role} active binding return recipient mismatch" unless binding["return_recipient_role"] == recipient
  errors << "#{role} Founder-conversation authority mismatch" unless binding["founder_conversation_authority"] == founder_authority
end
errors << "active role bindings must be run-owned" unless execution.dig("active_role_bindings", "ownership") == "run_owned_resolved_profile_snapshot"
errors << "provider registry must remain candidate inventory only" unless execution.dig("active_role_bindings", "provider_registry_role") == "candidate_inventory_only"
errors << "shared execution contract must not materialize active binding ids or profiles" unless execution.dig("active_role_bindings", "static_binding_materialization") == "forbidden_in_shared_contract"
expected_return_routing = {
  "image_and_03v_recipient_role" => "creative_development_director",
  "stage_04_shards_recipient_role" => "edit_director",
  "reviewed_director_milestones_recipient_role" => "overall_director",
  "founder_conversation_owner_role" => "overall_director"
}
expected_return_routing.each do |field, expected|
  actual = execution.dig("return_routing", field)
  errors << "execution v33 return routing mismatch for #{field}: expected #{expected}, got #{actual}" unless actual == expected
end

edit_director_profile = profiles_by_id["edit_director"] || {}
edit_director_reads = profile_binding_set(edit_director_profile, "read")
required_edit_director_reads = Set[
  "harness_execution_contract",
  "provider_neutral_studio_kernel",
  "department_dispatch_schema"
]
(required_edit_director_reads - edit_director_reads).each { |binding_id| errors << "Edit Director profile missing launch contract read: #{binding_id}" }

profiles.each do |profile|
  errors << "full reference catalog must not be a profile EOF binding: #{profile['profile_id']}" if profile_binding_set(profile, "read").include?("reference_catalog")
end

world_still_profile = profiles_by_id["world_still_reference_department"] || {}
world_still_skills = profile_binding_set(world_still_profile, "skill")
world_still_reads = profile_binding_set(world_still_profile, "read")
world_still_must_not = Array(world_still_profile.dig("authority", "must_not")).map(&:to_s).to_set
world_still_outputs = Array(world_still_profile.dig("output_contract", "kinds")).map(&:to_s).to_set
world_still_holds = Array(world_still_profile["hold_conditions"]).map(&:to_s).to_set
forbidden_world_still_reads = Set[
  "source_video_readme",
  "source_video_read_first",
  "video_first_read_contract",
  "video_analysis_example",
  "scripts_start_here",
  "scripts_guide_research_evidence"
]
required_world_still_bans = Set[
  "video_search",
  "video_open",
  "video_download",
  "video_playback",
  "video_sampling",
  "frame_extraction",
  "video_hub_load",
  "pinterest_search",
  "pinterest_open",
  "pinterest_capture",
  "pinterest_quota_ownership"
]
errors << "world/still worker must use only its image-only owner skill" unless world_still_skills == Set["world_still_reference_department"]
(world_still_reads & forbidden_world_still_reads).each { |binding_id| errors << "world/still worker loads forbidden video read: #{binding_id}" }
(required_world_still_bans - world_still_must_not).each { |token| errors << "world/still worker missing video ban: #{token}" }
required_world_still_outputs = Set["decision_set", "reference_working_index_delta"]
errors << "world/still worker must use existing Department Dispatch output kinds" unless world_still_outputs == required_world_still_outputs
errors << "world/still worker must hold unsheeted multi-image comparison" unless world_still_holds.include?("multi_image_comparison_without_contact_sheet")
errors << "world/still worker canonical_write must be forbidden" unless world_still_profile.dig("output_contract", "canonical_write") == "forbidden"
errors << "world/still review owner must be CDD" unless world_still_profile.dig("authority", "review_owner") == "creative_development_director"

pinterest_profile = profiles_by_id["pinterest_visual_composition_worker"] || {}
pinterest_skills = profile_binding_set(pinterest_profile, "skill")
pinterest_reads = profile_binding_set(pinterest_profile, "read")
pinterest_outputs = Array(pinterest_profile.dig("output_contract", "kinds")).map(&:to_s).to_set
pinterest_must_not = Array(pinterest_profile.dig("authority", "must_not")).map(&:to_s).to_set
errors << "Pinterest worker must use only its dedicated owner skill" unless pinterest_skills == Set["pinterest_reference_worker"]
%w[pinterest_section_comparison_detail world_still_contact_sheet_contract reference_working_index_schema].each do |binding_id|
  errors << "Pinterest worker missing registered comparison read: #{binding_id}" unless pinterest_reads.include?(binding_id)
end
%w[video_search video_open private_or_logged_in_pinterest bulk_scrape face_identity_inference canonical_index_write generation].each do |token|
  errors << "Pinterest worker missing authority ban: #{token}" unless pinterest_must_not.include?(token)
end
errors << "Pinterest worker must use existing Department Dispatch output kinds" unless pinterest_outputs == Set["decision_set", "reference_working_index_delta"]
errors << "Pinterest worker canonical_write must be forbidden" unless pinterest_profile.dig("output_contract", "canonical_write") == "forbidden"
errors << "Pinterest worker review owner must be CDD" unless pinterest_profile.dig("authority", "review_owner") == "creative_development_director"

pre02a_profile = profiles_by_id["pre_02a_development_block_fp"] || {}
required_pre02a_checkpoints = %w[
  fp_close_shard
  section_01_core_direction
  section_01_song_story_detail
  section_01_world_wardrobe_detail
  section_01_choreography_detail
  section_01_choreography_board
  section_01_performance_detail
  section_01_integration
  section_02a_coverage
]
require_checkpoint_set(errors, pre02a_profile, required_pre02a_checkpoints)

pre02a_read_contract = {
  "fp_close_shard" => %w[agents routing_policy section_production_policy section_production_front_planning creative_constitution production_system department_dispatch_schema section_slice_schema fp_operating_contract fp_reference_management mv_camera_module kinetic_slot_sheet_schema],
  "section_01_core_direction" => %w[agents routing_policy section_production_policy creative_constitution production_system department_dispatch_schema section_slice_schema fp_operating_contract mv_direction_module mv_camera_module mv_bundle_detail song_choreography_performance_schema],
  "section_01_song_story_detail" => %w[agents section_production_policy section_slice_schema fp_operating_contract mv_song_module song_choreography_performance_schema],
  "section_01_world_wardrobe_detail" => %w[agents section_production_policy section_slice_schema fp_operating_contract mv_screen_flow_wardrobe_module song_choreography_performance_schema],
  "section_01_choreography_detail" => %w[agents routing_policy section_production_policy creative_constitution production_system department_dispatch_schema section_slice_schema fp_operating_contract mv_choreography_module choreography_body_module choreography_capture_module song_choreography_performance_schema],
  "section_01_choreography_board" => %w[agents creative_constitution section_production_policy section_slice_schema song_choreography_performance_schema master_storyboard_schema],
  "section_01_performance_detail" => %w[agents section_production_policy section_slice_schema fp_operating_contract mv_performance_module song_choreography_performance_schema],
  "section_01_integration" => %w[agents section_production_policy section_slice_schema fp_operating_contract mv_integration_module mv_bundle_detail song_choreography_performance_schema],
  "section_02a_coverage" => %w[agents routing_policy media_security_policy section_production_policy section_production_01_02a creative_constitution production_system department_dispatch_schema section_slice_schema fp_operating_contract mv_camera_module fp_02a_coverage_detail master_storyboard_schema]
}
pre02a_read_contract.each do |checkpoint_id, expected_reads|
  require_checkpoint_bindings(errors, pre02a_profile, checkpoint_id, "read", expected_reads)
end

pre02a_skill_contract = {
  "fp_close_shard" => Set["front_planning_development_block"],
  "section_01_core_direction" => Set["mv_director"],
  "section_01_song_story_detail" => Set["mv_director"],
  "section_01_world_wardrobe_detail" => Set["mv_director"],
  "section_01_choreography_detail" => Set["mv_director", "choreography_performance"],
  "section_01_choreography_board" => Set["choreography_board"],
  "section_01_performance_detail" => Set["mv_director"],
  "section_01_integration" => Set["mv_director"],
  "section_02a_coverage" => Set["front_planning_development_block"]
}
pre02a_skill_contract.each do |checkpoint_id, expected_skills|
  actual_skills = require_checkpoint_bindings(errors, pre02a_profile, checkpoint_id, "skill", expected_skills)
  errors << "#{checkpoint_id} loads unrelated authority skill" unless actual_skills == expected_skills
end

choreography_reads = Array(checkpoint_by_id(pre02a_profile, "section_01_choreography_detail")["required_read_ids"]).map(&:to_s).to_set
performance_reads = Array(checkpoint_by_id(pre02a_profile, "section_01_performance_detail")["required_read_ids"]).map(&:to_s).to_set
errors << "choreography detail must not preload performance module" if choreography_reads.include?("mv_performance_module")
errors << "performance detail must not preload choreography module" if performance_reads.include?("mv_choreography_module")

board_profile = profiles_by_id["board_coordinator"] || {}
board_skills = profile_binding_set(board_profile, "skill")
board_must_not = Array(board_profile.dig("authority", "must_not")).map(&:to_s).to_set
errors << "board coordinator must use only mechanical review-board skill" unless board_skills == Set["review_board_coordinator"]
errors << "board coordinator must not load full orchestrator" if board_skills.include?("orchestrator")
errors << "board coordinator must use section-set review scope" unless board_profile.dig("output_contract", "expected_scope") == "section_set"
%w[creative_promotion founder_lock canonical_truth_authoring].each do |token|
  errors << "board coordinator missing mechanical authority ban: #{token}" unless board_must_not.include?(token)
end
require_checkpoint_set(errors, board_profile, %w[
  board_direction_alignment
  board_02a_final_planning
  board_generated_branch_cut_review
  board_video_playback_review
])
board_read_contract = {
  "board_direction_alignment" => %w[agents production_system section_production_policy section_production_workbench section_slice_schema fp_founder_visual_contract html_review_board_schema],
  "board_02a_final_planning" => %w[agents production_system section_production_policy section_slice_schema fp_founder_visual_contract creative_context_review_schema founder_review_decision_intake_schema html_review_board_schema generation_02a_handoff],
  "board_generated_branch_cut_review" => %w[agents production_system section_production_policy section_slice_schema image_generation_request_schema generated_review_schema html_review_board_schema],
  "board_video_playback_review" => %w[agents production_system section_production_policy section_slice_schema generated_review_schema production_cut_review_schema html_review_board_schema video_prompt_manifest_schema video_prompt_section_qa_schema llm_review_execution_record_schema]
}
board_read_contract.each do |checkpoint_id, expected_reads|
  require_checkpoint_bindings(errors, board_profile, checkpoint_id, "read", expected_reads)
  actual_skills = require_checkpoint_bindings(errors, board_profile, checkpoint_id, "skill", ["review_board_coordinator"])
  errors << "#{checkpoint_id} must use only the mechanical board skill" unless actual_skills == Set["review_board_coordinator"]
end

hub_profile = profiles_by_id["source_hub_registration"] || {}
hub_skills = profile_binding_set(hub_profile, "skill")
errors << "source-hub profile must use only video_reference_hub" unless hub_skills == Set["video_reference_hub"]

%w[reference_research_generalist world_still_reference_department source_hub_registration pre_song_research].each do |profile_id|
  holds = Array(profiles_by_id.dig(profile_id, "hold_conditions")).map(&:to_s).to_set
  errors << "restricted-source profile missing founder_permission_missing hold: #{profile_id}" unless holds.include?("founder_permission_missing")
  errors << "restricted-source profile missing unresolved_origin hold: #{profile_id}" unless holds.include?("unresolved_origin")
end

post_profile = profiles_by_id["post_02a_02b_image"] || {}
require_checkpoint_set(errors, post_profile, %w[
  section_02b_image
  section_image_generation_release
  section_generated_image_review
  section_image_render_correction
])
post_image_read_contract = {
  "section_02b_image" => %w[agents media_security_policy section_production_policy section_production_02b_pixel creative_constitution department_dispatch_schema master_storyboard_schema prompt_packet_delta_schema prompt_packets_schema harness_context_pack_schema generation_prompt_compile],
  "section_image_generation_release" => %w[agents media_security_policy section_production_policy section_production_02b_pixel department_dispatch_schema prompt_packets_schema harness_context_pack_schema image_generation_section_approval_schema image_generation_request_schema],
  "section_generated_image_review" => %w[agents media_security_policy section_production_policy section_production_02b_pixel department_dispatch_schema image_generation_request_schema image_generation_execution_receipt_schema generated_review_schema production_cut_review_schema],
  "section_image_render_correction" => %w[agents media_security_policy section_production_policy section_production_02b_pixel department_dispatch_schema prompt_packets_schema image_generation_request_schema generated_review_schema generation_render_correction]
}
post_image_read_contract.each do |checkpoint_id, expected_reads|
  require_checkpoint_bindings(errors, post_profile, checkpoint_id, "read", expected_reads)
  actual_skills = require_checkpoint_bindings(errors, post_profile, checkpoint_id, "skill", ["generation"])
  errors << "#{checkpoint_id} must use only the post-02A generation skill" unless actual_skills == Set["generation"]
end
main_image_checkpoint = checkpoint_by_id(post_profile, "section_02b_image")
correction_checkpoint = checkpoint_by_id(post_profile, "section_image_render_correction")
main_reads = Array(main_image_checkpoint["required_read_ids"]).map(&:to_s).to_set
correction_reads = Array(correction_checkpoint["required_read_ids"]).map(&:to_s).to_set
errors << "main post-02A image checkpoint must not preload render correction" if main_reads.include?("generation_render_correction")
errors << "02B translation checkpoint must not reopen the full camera vocabulary" if main_reads.include?("mv_camera_module")
errors << "02B translation checkpoint must not load Front Planning spine procedure" if main_reads.include?("section_production_front_planning")
errors << "02B translation checkpoint must not load 04 edit-unit procedure" if main_reads.include?("section_production_04")
errors << "02B translation checkpoint must load 02B/pixel procedure" unless main_reads.include?("section_production_02b_pixel")
errors << "02B translation checkpoint must load media-security input and allowlist policy" unless main_reads.include?("media_security_policy")
errors << "render-correction checkpoint must load its exact module" unless correction_reads.include?("generation_render_correction")
errors << "render-correction checkpoint must stay in the same lineage" unless correction_checkpoint["same_lineage"] == true

video_profile = profiles_by_id["post_02a_03v"] || {}
require_checkpoint_set(errors, video_profile, %w[
  section_03v_audio_placement
  section_03v_motion_direction
  section_03v_playback_review
])
video_read_contract = {
  "section_03v_audio_placement" => %w[agents media_security_policy section_production_policy section_production_02b_pixel department_dispatch_schema generated_review_schema production_cut_review_schema audio_branch_cut_placement_schema],
  "section_03v_motion_direction" => %w[agents media_security_policy section_production_policy section_production_03v creative_constitution department_dispatch_schema mv_camera_module generated_review_schema production_cut_review_schema audio_branch_cut_placement_schema video_prompt_storyboard_assist_schema authoring_source_pack_03v_schema video_prompt_manifest_schema video_prompt_section_qa_schema llm_review_execution_record_schema video_prompt_authoring_detail video_storyboard_assist_detail],
  "section_03v_playback_review" => %w[agents media_security_policy section_production_policy section_production_03v department_dispatch_schema generated_review_schema production_cut_review_schema video_prompt_manifest_schema video_prompt_section_qa_schema llm_review_execution_record_schema]
}
video_read_contract.each do |checkpoint_id, expected_reads|
  require_checkpoint_bindings(errors, video_profile, checkpoint_id, "read", expected_reads)
  actual_skills = require_checkpoint_bindings(errors, video_profile, checkpoint_id, "skill", ["video_prompt"])
  errors << "#{checkpoint_id} must use only the 03V owner skill" unless actual_skills == Set["video_prompt"]
end
video_audio_reads = Array(checkpoint_by_id(video_profile, "section_03v_audio_placement")["required_read_ids"]).map(&:to_s).to_set
video_playback_reads = Array(checkpoint_by_id(video_profile, "section_03v_playback_review")["required_read_ids"]).map(&:to_s).to_set
errors << "03V audio placement must not preload camera vocabulary" if video_audio_reads.include?("mv_camera_module")
errors << "03V playback review must not reopen camera vocabulary" if video_playback_reads.include?("mv_camera_module")
errors << "03V audio placement must not preload video prompt authoring detail" if video_audio_reads.include?("video_prompt_authoring_detail")
errors << "03V playback review must not reopen video prompt authoring detail" if video_playback_reads.include?("video_prompt_authoring_detail")

mvi_profile = profiles_by_id["member_visual_identity"] || {}
errors << "member visual worker canonical_write must be forbidden" unless mvi_profile.dig("output_contract", "canonical_write") == "forbidden"
errors << "member visual review owner must be CDD" unless mvi_profile.dig("authority", "review_owner") == "creative_development_director"
errors << "member visual promotion owner must be Overall" unless mvi_profile.dig("authority", "promotion_owner") == "overall_director"
required_mvi_reads = Set["member_visual_character_card_contract", "member_visual_prompt_field_guide"]
missing_mvi_reads = required_mvi_reads - profile_binding_set(mvi_profile, "read")
missing_mvi_reads.each { |binding_id| errors << "member visual profile missing registered method read: #{binding_id}" }

edit_shard_profile = profiles_by_id["edit_shard"] || {}
errors << "edit shard canonical_write must be forbidden" unless edit_shard_profile.dig("output_contract", "canonical_write") == "forbidden"
require_checkpoint_set(errors, edit_director_profile, %w[edit_qc_section edit_master_closeout edit_social_release])
edit_director_read_contract = {
  "edit_qc_section" => %w[agents section_production_policy section_production_04 production_system generation_review_system generated_review_schema edit_map_schema edit_marker_plan_schema edit_recipe_schema editing_qc_detail editing_casebook scripts_start_here scripts_guide_edit_qc harness_execution_contract provider_neutral_studio_kernel department_dispatch_schema],
  "edit_master_closeout" => %w[agents section_production_policy production_system edit_map_schema edit_recipe_schema edit_render_manifest_schema edit_cutpoint_sheet_schema edit_delivery_qc_schema edit_qc_closeout_schema package_schema editing_qc_detail scripts_start_here scripts_guide_edit_qc department_dispatch_schema],
  "edit_social_release" => %w[agents section_production_policy production_system social_automation_system edit_render_manifest_schema edit_delivery_qc_schema edit_qc_closeout_schema package_schema editing_qc_detail scripts_start_here scripts_guide_edit_qc scripts_guide_release_platform department_dispatch_schema]
}
edit_director_read_contract.each do |checkpoint_id, expected_reads|
  actual_reads = require_checkpoint_bindings(errors, edit_director_profile, checkpoint_id, "read", expected_reads)
  actual_skills = require_checkpoint_bindings(errors, edit_director_profile, checkpoint_id, "skill", ["editing_qc"])
  errors << "#{checkpoint_id} must use only the Edit Director skill" unless actual_skills == Set["editing_qc"]
  if %w[edit_qc_section edit_master_closeout].include?(checkpoint_id) && actual_reads.include?("social_automation_system")
    errors << "#{checkpoint_id} must defer social automation to edit_social_release"
  end
end

require_checkpoint_set(errors, edit_shard_profile, %w[finishing_fx_section finishing_fx_ae_like_detail shot_vfx_section])
edit_shard_read_contract = {
  "finishing_fx_section" => %w[agents section_production_policy production_system edit_map_schema edit_recipe_schema edit_finishing_fx_schema edit_finishing_compile_schema edit_render_manifest_schema edit_effect_registry local_ffmpeg_effect_catalog professional_effect_casebook scripts_start_here scripts_guide_edit_qc],
  "finishing_fx_ae_like_detail" => %w[agents section_production_policy production_system edit_map_schema edit_recipe_schema edit_finishing_fx_schema edit_finishing_compile_schema edit_render_manifest_schema edit_effect_registry local_ffmpeg_effect_catalog professional_effect_casebook ae_like_effect_map scripts_start_here scripts_guide_edit_qc],
  "shot_vfx_section" => %w[agents section_production_policy production_system edit_map_schema edit_recipe_schema shot_vfx_manual shot_vfx_catalog scripts_start_here scripts_guide_edit_qc]
}
edit_shard_skill_contract = {
  "finishing_fx_section" => Set["edit_finishing_fx"],
  "finishing_fx_ae_like_detail" => Set["edit_finishing_fx"],
  "shot_vfx_section" => Set["shot_vfx"]
}
edit_shard_read_contract.each do |checkpoint_id, expected_reads|
  actual_reads = require_checkpoint_bindings(errors, edit_shard_profile, checkpoint_id, "read", expected_reads)
  actual_skills = require_checkpoint_bindings(errors, edit_shard_profile, checkpoint_id, "skill", edit_shard_skill_contract.fetch(checkpoint_id))
  errors << "#{checkpoint_id} loads unrelated edit authority skill" unless actual_skills == edit_shard_skill_contract.fetch(checkpoint_id)
  if checkpoint_id.start_with?("finishing_fx")
    (actual_reads & Set["shot_vfx_manual", "shot_vfx_catalog"]).each do |binding_id|
      errors << "#{checkpoint_id} preloads shot-VFX read: #{binding_id}"
    end
  else
    (actual_reads & Set["edit_finishing_fx_schema", "edit_finishing_compile_schema", "local_ffmpeg_effect_catalog", "professional_effect_casebook", "ae_like_effect_map"]).each do |binding_id|
      errors << "shot_vfx_section preloads finishing read: #{binding_id}"
    end
  end
end

checkpoint_loads = profiles.each_with_object([]) do |profile, rows|
  Array(profile.dig("phase_load", "checkpoints")).each do |checkpoint|
    next unless checkpoint.is_a?(Hash)
    skill_ids_for_checkpoint = Array(checkpoint["required_skill_ids"]).map(&:to_s)
    read_ids_for_checkpoint = Array(checkpoint["required_read_ids"]).map(&:to_s)
    rows << {
      "profile_id" => profile["profile_id"].to_s,
      "checkpoint_id" => checkpoint["checkpoint_id"].to_s,
      "skill_binding_count" => skill_ids_for_checkpoint.length,
      "read_binding_count" => read_ids_for_checkpoint.length,
      "binding_count" => (skill_ids_for_checkpoint + read_ids_for_checkpoint).length,
      "word_count" => (skill_ids_for_checkpoint + read_ids_for_checkpoint).sum { |binding_id| binding_word_counts.fetch(binding_id, 0) },
      "unload_after" => checkpoint["unload_after"].to_s
    }
  end
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "profile_count" => profiles.length,
  "skill_binding_count" => skill_rows.length,
  "read_binding_count" => read_rows.length,
  "checkpoint_load_measurement_basis" => "registered_checkpoint_required_skill_ids_and_required_read_ids_whitespace_words_v1",
  "checkpoint_loads" => checkpoint_loads,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
else
  puts "Graph Engineering skill-load profiles: #{result['status'].upcase}"
  puts "Profiles: #{profiles.length}; skill bindings: #{skill_rows.length}; read bindings: #{read_rows.length}"
  checkpoint_loads.each do |row|
    puts "- load #{row['profile_id']}.#{row['checkpoint_id']}: #{row['word_count']} words/#{row['binding_count']} bindings; unload_after=#{row['unload_after']}"
  end
  errors.each { |error| puts "- #{error}" }
end

exit(errors.empty? ? 0 : 1)
