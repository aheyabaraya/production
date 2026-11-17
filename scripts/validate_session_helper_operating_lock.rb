# frozen_string_literal: true

# Mechanical floor checks for parent-scoped helpers and post-song reference
# workers. Does not judge creative adequacy.

require "json"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")
SCHEMA = ROOT.join("schemas", "harness-execution-contract.schema.json")

HELPER_MULTI_LEAF_MIN = 4
REFERENCE_WORKER_FLOOR = 6
EXACT_BYTE_REVIEW = "cdd_single_return_review"
LEGAL_EXCEPTIONS = %w[single_leaf_named exact_byte_director_judgment helper_surface_unavailable].freeze
REQUIRED_FLOOR_CHECKPOINTS = %w[
  reference_story_sequence_role
  reference_camera_composition_role
  reference_world_object_material_role
  reference_performance_role
  world_still_physical
  pinterest_physical
].freeze

def load_contract(path = CONTRACT)
  YAML.safe_load(Pathname(path).read, aliases: true)
end

def helper_floor_met?(count, work_class, exception = nil)
  return true if work_class.to_s == EXACT_BYTE_REVIEW
  return true if LEGAL_EXCEPTIONS.include?(exception.to_s) && exception.to_s != "exact_byte_director_judgment"
  return true if exception.to_s == "exact_byte_director_judgment" && work_class.to_s == EXACT_BYTE_REVIEW

  Integer(count) >= HELPER_MULTI_LEAF_MIN
end

def contract_floor_errors(contract)
  errors = []
  version = contract["schema_version"].to_s
  errors << "execution contract must be idol-harness-execution-contract.v36" unless version == "idol-harness-execution-contract.v36"

  helpers = contract.dig("session_route", "department_worker_execution_topology", "parent_scoped_helpers")
  unless helpers.is_a?(Hash)
    errors << "session_route.department_worker_execution_topology.parent_scoped_helpers is missing"
    return errors
  end
  min = helpers["cdd_fp_02a_multi_leaf_min"]
  errors << "cdd_fp_02a_multi_leaf_min must be #{HELPER_MULTI_LEAF_MIN}" unless min == HELPER_MULTI_LEAF_MIN
  errors << "exact_byte_return_review_min must be 0" unless helpers["exact_byte_return_review_min"] == 0
  errors << "parent_scoped grok_tool must be spawn_subagent" unless helpers["grok_tool"] == "spawn_subagent"
  errors << "parent_scoped helpers are not physical sessions" unless helpers["not_a_physical_session"] == true

  lock = contract.dig("session_route", "session_and_helper_operating_lock")
  unless lock.is_a?(Hash)
    errors << "session_route.session_and_helper_operating_lock is missing"
  else
    errors << "image section worker must stay a physical post-02A session" unless lock["image_section_worker"] == "physical_post_02a_session"
    errors << "CDD dispatch/review must use parent-scoped spawn_subagent min 4" unless lock["cdd_dispatch_and_review"] == "parent_scoped_spawn_subagent_min_4"
    errors << "Overall must assign checkpoints to the one CDD" unless lock["overall_assigns_checkpoint_not_a_new_cdd"] == true
    errors << "04 must open Edit Director, not a new CDD" unless lock["edit_opens_edit_director_not_cdd"] == true
  end

  wave = contract.dig("studio_session_routing", "post_song_reference_wave")
  unless wave.is_a?(Hash)
    errors << "post_song_reference_wave is missing"
    return errors
  end
  errors << "assignment_count_policy must be floor_six_disjoint_then_named_gap_adaptive" unless wave["assignment_count_policy"] == "floor_six_disjoint_then_named_gap_adaptive"
  errors << "assignment_count_floor must be #{REFERENCE_WORKER_FLOOR}" unless wave["assignment_count_floor"] == REFERENCE_WORKER_FLOOR
  errors << "launch_policy must stay never_fill_provider_capacity" unless wave["launch_policy"] == "never_fill_provider_capacity"
  rows = Array(wave["floor_assignments"])
  errors << "floor_assignments must contain #{REFERENCE_WORKER_FLOOR} rows" unless rows.length == REFERENCE_WORKER_FLOOR
  checkpoints = rows.map { |row| row.is_a?(Hash) ? row["checkpoint"].to_s : "" }
  missing = REQUIRED_FLOOR_CHECKPOINTS - checkpoints
  extra = checkpoints - REQUIRED_FLOOR_CHECKPOINTS
  errors << "floor_assignments missing #{missing.join(',')}" unless missing.empty?
  errors << "floor_assignments extra #{extra.join(',')}" unless extra.empty?
  physical = rows.select { |row| row.is_a?(Hash) && row["topology"] == "physical" }
  errors << "World/Still and Pinterest must be the physical floor rows" unless physical.map { |row| row["department"] }.sort == %w[pinterest_visual_composition_worker world_still_reference_department]
  errors
end

if $PROGRAM_NAME == __FILE__
  contract = load_contract
  errors = contract_floor_errors(contract)
  if errors.empty?
    puts "PASS session helper operating lock"
    exit 0
  end
  errors.each { |error| warn error }
  exit 1
end
