#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"
require_relative "idol_department_transport_refresh"
require_relative "lib/idol_checkpoint_closure_catalog"
require_relative "lib/idol_department_context"
require_relative "lib/idol_helper_consumption_receipts"
require_relative "lib/idol_run_followup_sidecar"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "department-dispatch.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
HARNESS_ARTIFACT_VALIDATOR = ROOT.join("scripts", "validate_harness_artifact_contract.rb")
SECTION_SLICE_SCHEMA = "schemas/harness-section-slice.schema.json"
FOUNDER_BRIEFING_SCHEMA = ROOT.join("development", "front-planning-workbench", "founder-briefing", "founder-briefing.schema.json")
SKILL_PROFILE_REGISTRY = ROOT.join("automation", "harness-skill-load-profiles.yaml")
PROVIDER_NEUTRAL_STUDIO_KERNEL = "skills/idol-orchestrator/references/provider-neutral-studio-kernel.md"

LAUNCH_BLOCK_HEADINGS = [
  ["dispatch_identity", "## 01 Dispatch Identity"],
  ["role_and_authority", "## 02 Role And Authority"],
  ["current_creative_job", "## 03 Current Creative Job"],
  ["exact_scope_and_non_scope", "## 04 Exact Scope And Non-Scope"],
  ["input_pointers", "## 05 Input Pointers"],
  ["skill_route", "## 06 Skill Route"],
  ["required_work", "## 07 Required Work"],
  ["output_contract", "## 08 Output Contract"],
  ["quality_proof", "## 09 Quality Proof"],
  ["return_ready_conditions", "## 10 Return-Ready Conditions"],
  ["hold_stop_split_conditions", "## 11 HOLD Stop And Split Conditions"],
  ["return_and_wake", "## 12 Return And Wake"]
].freeze

CURRENT_ASSIGNMENT_BLOCKS = %w[current_creative_job required_work quality_proof].freeze
GOAL_DIRECTIVE = "First runtime action: open the native Goal from launch.goal_contract and record its id before required reads or creative work.".freeze
BASE_REVIEW_CRITERIA = %w[
  goal_opened_and_pursued
  founder_instruction_coverage
  owning_skill_application
  schema_and_contract_conformance
  current_assignment_resolution
  required_output_coverage
  observable_specificity
  source_and_pixel_grounding
  storyline_preservation
  locks_scope_and_unaffected_truth
  honest_completion_state
].freeze
REQUIREMENT_CATEGORIES = %w[founder skill policy contract schema output quality hold goal].freeze
REQUIREMENT_PROJECTION_PREFIX = "DDC_REQUIREMENT_PROJECTION_V1 ".freeze
ANTI_FLAT_PROJECTION_PREFIX = "DDC_ANTI_FLAT_PROJECTION_V1 ".freeze
REQUIREMENT_PROJECTION_FIELDS = %w[
  requirement_id
  source_locator
  affected_scope
  expected_output_target
  evidence_type
  director_semantic_review_required
].freeze

V19_OUTPUT_RULES = {
  "decision_set" => {
    roles: %w[song_room department_worker member_visual_identity_owner section_owner],
    binding_kinds: %w[selected_source_evidence],
    review_criteria: %w[actual_selected_media source_to_screen_delta nonoverlap]
  },
  "director_development_report" => {
    roles: %w[creative_development_director edit_director],
    binding_kinds: %w[decision_set],
    review_criteria: %w[one_work_synthesis raw_pool_removed material_risk]
  },
  "section_dispatch_map" => {
    roles: %w[creative_development_director section_owner edit_director edit_shard_worker],
    binding_kinds: %w[selected_audio_analysis audio_motion_map],
    review_criteria: %w[independent_visual_job connected_boundaries]
  },
  "section_reference_set" => {
    roles: %w[department_worker section_owner],
    binding_kinds: %w[section_dispatch_map reference_working_index selected_source_evidence],
    review_criteria: %w[comparison_floor source_function_diversity entry_exit]
  },
  "reference_working_index_delta" => {
    roles: %w[department_worker section_owner],
    binding_kinds: %w[reference_working_index selected_source_evidence],
    review_criteria: %w[level_a_b_c deduplication]
  },
  "pre_02a_section_working_shard" => {
    roles: %w[department_worker],
    binding_kinds: %w[section_dispatch_map section_reference_set section_slice_schema],
    review_criteria: %w[observable_nonredundant_events anti_flat_current_work_evidence section_boundary]
  },
  "founder_briefing_projection" => {
    roles: %w[department_worker],
    binding_kinds: %w[founder_briefing_source_set],
    review_criteria: %w[reviewed_milestone_only source_set_exactness projection_authority_boundary]
  }
}.freeze

LIFECYCLE_PREFIXES = {
  "prepared" => %w[prepared],
  "launched" => %w[prepared launched],
  "returned" => %w[prepared launched returned],
  "reviewed" => %w[prepared launched returned reviewed],
  "promoted" => %w[prepared launched returned reviewed promoted],
  "hold" => %w[prepared launched returned reviewed hold]
}.freeze

options = {json: false, require_promoted: false, transport_refresh: nil}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_department_dispatch.rb [--json] [--require-promoted] [--transport-refresh RECEIPT] DISPATCH"
  parser.on("--json") { options[:json] = true }
  parser.on("--require-promoted") { options[:require_promoted] = true }
  parser.on("--transport-refresh RECEIPT") { |value| options[:transport_refresh] = value }
end.parse!

argument = ARGV.shift
if argument.to_s.empty? || !ARGV.empty?
  warn "department dispatch path is required"
  exit 2
end

def repo_path(raw)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = path.relative_path_from(ROOT).to_s
  raise ArgumentError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")

  [path, relative]
rescue ArgumentError
  raise ArgumentError, "path escapes repository: #{raw}"
end

def load_document(path)
  text = path.read
  value = path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)
  value.is_a?(Hash) ? value : nil
rescue JSON::ParserError, Psych::Exception
  nil
end

def canonicalize(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonicalize(value[original_key])
    end
  when Array
    value.map { |item| canonicalize(item) }
  when Date, Time, DateTime
    value.iso8601
  else
    value
  end
end

def structured_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
end

def timestamp_value(errors, label, value)
  DateTime.iso8601(value.to_s)
rescue ArgumentError
  errors << "#{label} must be an ISO-8601 timestamp"
  nil
end

def file_binding(errors, label, row)
  unless row.is_a?(Hash)
    errors << "#{label} must be a path/hash binding"
    return [nil, ""]
  end

  path, relative = repo_path(row["path"])
  unless path.file?
    errors << "#{label} is missing: #{relative}"
    return [nil, relative]
  end

  begin
    real_relative = path.realpath.relative_path_from(ROOT.realpath).to_s
    if real_relative == ".." || real_relative.start_with?("../")
      errors << "#{label} resolves outside repository: #{relative}"
      return [nil, relative]
    end
  rescue ArgumentError, SystemCallError
    errors << "#{label} cannot be safely resolved: #{relative}"
    return [nil, relative]
  end

  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} SHA-256 is stale: #{relative}" unless actual == row["sha256"].to_s
  [path, relative]
rescue ArgumentError => e
  errors << e.message
  [nil, row.is_a?(Hash) ? row["path"].to_s : ""]
end

def binding_pairs(rows)
  Array(rows).each_with_object([]) do |row, result|
    next unless row.is_a?(Hash)

    result << [row["path"].to_s, row["sha256"].to_s]
  end
end

def hash_values(rows, key)
  Array(rows).each_with_object([]) do |row, result|
    result << row[key].to_s if row.is_a?(Hash)
  end
end

def duplicate_values(values)
  values.group_by(&:itself).select { |value, rows| value.empty? || rows.length > 1 }.keys
end

def exact_rows(rows)
  canonicalize(Array(rows))
end

def review_input_basis(document)
  launch = document["launch"].is_a?(Hash) ? document["launch"] : {}
  task = launch["task"].is_a?(Hash) ? launch["task"] : {}
  scope = task["exact_scope"].is_a?(Hash) ? task["exact_scope"] : {}
  {
    "review_submission" => document["review_submission"],
    "founder_context" => launch["founder_context"],
    "objective" => task["objective"],
    "scope" => scope.reject { |key, _value| key.to_s == "artifact_paths" },
    "requirement_manifest" => launch["requirement_manifest"],
    "required_skills" => launch["required_skills"],
    "sources" => launch["sources"],
    "external_permission" => launch["external_permission"],
    "bounded_output_kind" => launch.dig("bounded_output", "output_kind")
  }
end

def scope_without_artifact_paths(value)
  scope = value.is_a?(Hash) ? value : {}
  canonicalize(scope.reject { |key, _entry| key.to_s == "artifact_paths" })
end

def requirement_projection_line(row)
  payload = REQUIREMENT_PROJECTION_FIELDS.each_with_object({}) do |field, result|
    result[field] = row[field]
  end
  "#{REQUIREMENT_PROJECTION_PREFIX}#{JSON.generate(payload)}"
end

def anti_flat_projection_line(value)
  "#{ANTI_FLAT_PROJECTION_PREFIX}#{JSON.generate('anti_flat_evidence_requirement' => value)}"
end

def projected_requirement_block(category)
  case category.to_s
  when "founder" then "current_creative_job"
  when "quality" then "quality_proof"
  else "required_work"
  end
end

def validate_prompt_projection_lines(errors, lines, block_line_indexes, requirements, anti_flat_requirements)
  expected_requirements = Array(requirements).each_with_object([]) do |row, result|
    next unless row.is_a?(Hash)

    result << {
      line: requirement_projection_line(row),
      block_id: projected_requirement_block(row["category"]),
      requirement_id: row["requirement_id"].to_s
    }
  end
  expected_anti_flat = Array(anti_flat_requirements).map do |value|
    {
      line: anti_flat_projection_line(value),
      block_id: "quality_proof",
      requirement_id: value.to_s
    }
  end

  expected_requirement_lines = expected_requirements.map { |entry| entry.fetch(:line) }
  expected_anti_flat_lines = expected_anti_flat.map { |entry| entry.fetch(:line) }
  actual_requirement_rows = []
  actual_anti_flat_rows = []
  lines.each_with_index do |line, index|
    stripped = line.strip
    if line.include?(REQUIREMENT_PROJECTION_PREFIX)
      actual_requirement_rows << {line: stripped, index: index, canonical: line == stripped}
    elsif line.include?(ANTI_FLAT_PROJECTION_PREFIX)
      actual_anti_flat_rows << {line: stripped, index: index, canonical: line == stripped}
    end
  end

  actual_requirement_rows.each do |entry|
    errors << "compiled launch requirement projection lines must be unindented canonical single lines" unless entry.fetch(:canonical)
    unless expected_requirement_lines.include?(entry.fetch(:line))
      errors << "compiled launch contains an unexpected or non-exact requirement projection line"
    end
  end
  actual_anti_flat_rows.each do |entry|
    errors << "compiled launch Anti-Flat projection lines must be unindented canonical single lines" unless entry.fetch(:canonical)
    unless expected_anti_flat_lines.include?(entry.fetch(:line))
      errors << "compiled launch contains an unexpected or non-exact Anti-Flat projection line"
    end
  end

  expected_requirements.each do |entry|
    matches = actual_requirement_rows.select { |row| row.fetch(:line) == entry.fetch(:line) }
    unless matches.length == 1
      errors << "compiled launch must exact-project requirement #{entry.fetch(:requirement_id).inspect} exactly once"
      next
    end

    actual_block = block_line_indexes[matches.first.fetch(:index)]
    unless actual_block == entry.fetch(:block_id)
      errors << "compiled launch requirement #{entry.fetch(:requirement_id).inspect} must be in block #{entry.fetch(:block_id)}"
    end
  end
  expected_anti_flat.each do |entry|
    matches = actual_anti_flat_rows.select { |row| row.fetch(:line) == entry.fetch(:line) }
    unless matches.length == 1
      errors << "compiled launch must exact-project Anti-Flat evidence #{entry.fetch(:requirement_id).inspect} exactly once"
      next
    end

    actual_block = block_line_indexes[matches.first.fetch(:index)]
    unless actual_block == entry.fetch(:block_id)
      errors << "compiled launch Anti-Flat evidence must be in block quality_proof: #{entry.fetch(:requirement_id).inspect}"
    end
  end
end

def validate_rendered_launch_prompt(errors, prompt, requirements, anti_flat_requirements)
  lines = prompt.to_s.lines.map { |line| line.chomp }
  first_nonempty = lines.find { |line| !line.strip.empty? }
  errors << "compiled launch rendered prompt must begin with the registered Goal-first runtime directive" unless first_nonempty == GOAL_DIRECTIVE
  heading_positions = {}

  LAUNCH_BLOCK_HEADINGS.each do |block_id, heading|
    positions = lines.each_index.select { |index| lines[index] == heading }
    if positions.length != 1
      errors << "compiled launch rendered prompt must contain #{heading.inspect} exactly once"
      next
    end
    heading_positions[block_id] = positions.first
  end

  return unless heading_positions.length == LAUNCH_BLOCK_HEADINGS.length

  ordered_positions = LAUNCH_BLOCK_HEADINGS.map { |block_id, _heading| heading_positions.fetch(block_id) }
  unless ordered_positions == ordered_positions.sort
    errors << "compiled launch rendered prompt must preserve the registered twelve-block order"
    return
  end

  block_line_indexes = {}
  LAUNCH_BLOCK_HEADINGS.each_with_index do |(block_id, _heading), index|
    start_index = heading_positions.fetch(block_id) + 1
    end_index = index == LAUNCH_BLOCK_HEADINGS.length - 1 ? lines.length : ordered_positions[index + 1]
    (start_index...end_index).each { |line_index| block_line_indexes[line_index] = block_id }
    body = lines[start_index...end_index].join("\n").strip
    errors << "compiled launch rendered prompt block #{block_id} must not be empty" if body.empty?
    next unless CURRENT_ASSIGNMENT_BLOCKS.include?(block_id)

    if body.match?(%r{<[^>\n]+>}) || body.match?(/\b(?:TBD|TODO)\b/i)
      errors << "compiled launch current-assignment block #{block_id} contains an unresolved placeholder"
    end
  end

  validate_prompt_projection_lines(
    errors,
    lines,
    block_line_indexes,
    requirements,
    anti_flat_requirements
  )
end

def validate_whole_skill_prose_not_duplicated(errors, prompt, required_skills)
  normalized_prompt = prompt.to_s.gsub(/\s+/, " ").strip
  Array(required_skills).each do |skill|
    next unless skill.is_a?(Hash)

    path, relative = repo_path(skill["path"])
    next unless path.file?

    skill_text = path.read.strip
    next if skill_text.empty?

    normalized_skill_text = skill_text.gsub(/\s+/, " ").strip
    next unless normalized_prompt.include?(normalized_skill_text)

    errors << "compiled launch rendered prompt must not duplicate the whole owning skill prose: #{relative}"
  rescue ArgumentError, SystemCallError
    next
  end
end

def validate_v18_output_binding(errors, label, binding, source_by_id)
  unless binding.is_a?(Hash)
    errors << "#{label} must be a source binding"
    return
  end

  file_binding(errors, label, binding)
  source = source_by_id[binding["source_id"].to_s]
  if source.nil?
    errors << "#{label} source_id is not declared by launch.sources: #{binding['source_id'].inspect}"
    return
  end

  unless binding["path"].to_s == source["path"].to_s && binding["sha256"].to_s == source["sha256"].to_s
    errors << "#{label} path and SHA-256 must exact-copy launch.sources source_id=#{binding['source_id']}"
  end
end

def validate_pre_02a_section_output(errors, label, path, relative, logical_owner, scope)
  return unless path&.file?

  contract = load_document(path)
  unless contract.is_a?(Hash) && contract["envelope"].is_a?(Hash) && contract["payload"].is_a?(Hash)
    errors << "#{label} must be a graph-engineering section-slice envelope: #{relative}"
    return
  end

  envelope = contract["envelope"]
  payload = contract["payload"]
  errors << "#{label} must use artifact_kind=harness_section_slice" unless envelope["artifact_kind"].to_s == "harness_section_slice"
  errors << "#{label} must bind payload_schema=#{SECTION_SLICE_SCHEMA}" unless envelope["payload_schema"].to_s == SECTION_SLICE_SCHEMA
  errors << "#{label} envelope owner must equal bounded_output.logical_owner.owner" unless envelope["owner"].to_s == logical_owner["owner"].to_s
  errors << "#{label} payload output_kind must be pre_02a_section_working_shard" unless payload["output_kind"].to_s == "pre_02a_section_working_shard"
  errors << "#{label} payload contract_kind must be section_slice" unless payload["contract_kind"].to_s == "section_slice"
  errors << "#{label} payload stage_id must equal dispatch exact_scope.stage_id" unless payload["stage_id"].to_s == scope["stage_id"].to_s

  visual_section_id = payload.dig("id_namespace", "visual_section_id").to_s
  unless Array(scope["section_ids"]).map(&:to_s).include?(visual_section_id)
    errors << "#{label} visual_section_id is outside dispatch exact_scope.section_ids: #{visual_section_id.inspect}"
  end

  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    HARNESS_ARTIFACT_VALIDATOR.to_s,
    "--json",
    relative,
    chdir: ROOT.to_s
  )
  return if status.success?

  details = begin
    result = JSON.parse(stdout)
    Array(result["errors"]).join("; ")
  rescue JSON::ParserError
    [stdout, stderr].join(" ").strip
  end
  errors << "#{label} failed the existing graph-engineering section-slice contract: #{details}"
end

def founder_briefing_source_set_digest(rows)
  lines = rows.map { |row| [row["path"].to_s, row["sha256"].to_s] }
              .sort
              .map { |path, sha256| "#{path}\t#{sha256}" }
  Digest::SHA256.hexdigest(lines.join("\n"))
end

def validate_founder_briefing_output(errors, label, path, relative, run, bindings)
  return unless path&.file?

  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    FOUNDER_BRIEFING_SCHEMA.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  unless status.success?
    errors << "#{label} Founder briefing schema validation failed: #{[stderr, stdout].join(' ').strip}"
    return
  end

  document = load_document(path)
  unless document.is_a?(Hash)
    errors << "#{label} Founder briefing output must be one JSON object: #{relative}"
    return
  end
  errors << "#{label} Founder briefing run_root must exact-copy dispatch.run" unless document["run_root"].to_s == run

  members = Array(document.dig("source_set", "members"))
  member_pairs = members.map { |row| row.is_a?(Hash) ? [row["path"].to_s, row["sha256"].to_s] : ["", ""] }.sort
  binding_pairs = Array(bindings).map do |row|
    next ["", ""] unless row.is_a?(Hash) && row["binding_kind"].to_s == "founder_briefing_source_set"

    [row["path"].to_s, row["sha256"].to_s]
  end.sort
  errors << "#{label} Founder briefing source_set.members must exact-copy its dispatch source-set bindings" unless member_pairs == binding_pairs

  digest = founder_briefing_source_set_digest(members)
  errors << "#{label} Founder briefing source_set_sha256 is stale" unless document["source_set_sha256"].to_s == digest

  milestone_pairs = Array(document["reviewed_milestones"]).flat_map do |row|
    next [] unless row.is_a?(Hash)

    [[row["source_path"].to_s, row["source_sha256"].to_s], [row["review_receipt_path"].to_s, row["review_receipt_sha256"].to_s]]
  end
  missing = milestone_pairs.uniq - member_pairs.uniq
  errors << "#{label} Founder briefing reviewed milestones are not fully present in the dispatch source set" unless missing.empty?
end

dispatch_path, dispatch_relative = repo_path(argument)
errors = []
raw_document = dispatch_path.file? ? load_document(dispatch_path) : nil
document = raw_document.is_a?(Hash) ? raw_document : {}
transport_refresh_receipt = nil

if !dispatch_path.file?
  errors << "department dispatch is missing: #{dispatch_relative}"
elsif options[:transport_refresh]
  begin
    validated_refresh = IdolDepartmentTransportRefresh.validate_receipt(options[:transport_refresh])
    refresh_source_path = validated_refresh.fetch("dispatch_path")
    unless refresh_source_path == dispatch_path
      errors << "transport refresh receipt belongs to another Department Dispatch: #{IdolDepartmentTransportRefresh.relative_path(refresh_source_path)}"
    end
    transport_refresh_receipt = validated_refresh.fetch("receipt")
    document = IdolDepartmentTransportRefresh.project_dispatch(raw_document, transport_refresh_receipt)
  rescue IdolDepartmentTransportRefresh::ValidationError => e
    errors.concat(e.errors.map { |error| "transport refresh invalid: #{error}" })
  end
end

if dispatch_path.file?
  schema_target = dispatch_path
  scratch = nil
  if transport_refresh_receipt
    scratch = Tempfile.new(["idol-department-dispatch-effective-", ".yaml"], "/private/tmp")
    scratch.write(YAML.dump(document))
    scratch.flush
    schema_target = Pathname.new(scratch.path)
  end
  projected_instruction_delivery = document.dig("launch", "instruction_delivery").to_s == "role_context_pack"
  if projected_instruction_delivery
    begin
      IdolDepartmentContext.validate_owning_dispatch_schema!(root: ROOT, instance_path: schema_target)
    rescue IdolDepartmentContext::ContractError => e
      errors << "schema validation failed: #{e.message}"
    end
  else
    stdout, stderr, status = Open3.capture3(
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      SCHEMA.to_s,
      schema_target.to_s,
      chdir: ROOT.to_s
    )
    unless status.success?
      errors << "schema validation failed: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}"
    end
  end
  scratch&.close!
end

run = document["run"].to_s
dispatch_id = document["dispatch_id"].to_s
raw_launch = raw_document.is_a?(Hash) && raw_document["launch"].is_a?(Hash) ? raw_document["launch"] : {}
raw_lineage = raw_document.is_a?(Hash) && raw_document["lineage"].is_a?(Hash) ? raw_document["lineage"] : {}
raw_review_submission = raw_document.is_a?(Hash) && raw_document["review_submission"].is_a?(Hash) ? raw_document["review_submission"] : {}
raw_runtime_return = raw_document.is_a?(Hash) && raw_document["runtime_return"].is_a?(Hash) ? raw_document["runtime_return"] : {}
raw_promotion = raw_document.is_a?(Hash) && raw_document["promotion"].is_a?(Hash) ? raw_document["promotion"] : {}

expected_directory = "#{run}/work/department-dispatches"
unless dispatch_path.dirname == ROOT.join(expected_directory).expand_path && dispatch_path.basename.to_s == "#{dispatch_id}.yaml"
  errors << "department dispatch must live at #{expected_directory}/#{dispatch_id}.yaml"
end
errors << "declared run is missing: #{run}" unless ROOT.join(run).directory?

launch = document["launch"].is_a?(Hash) ? document["launch"] : {}
lineage = document["lineage"].is_a?(Hash) ? document["lineage"] : {}
review_submission = document["review_submission"].is_a?(Hash) ? document["review_submission"] : {}
routing_identity = document["routing_identity"].is_a?(Hash) ? document["routing_identity"] : {}
logical_role = routing_identity["logical_role"].to_s
worker_specialty = routing_identity["worker_specialty"].to_s
recipient_role = routing_identity["return_recipient_role"].to_s
director_roles = %w[overall_director creative_development_director edit_director]
worker_roles = %w[worker mechanical_coordinator]
errors << "routing_identity.logical_role must be a logical Director, worker, or mechanical coordinator role" unless (director_roles + worker_roles).include?(logical_role)
expected_alias = director_roles.include?(logical_role) ? "director_deep" : "worker_high"
errors << "routing_identity logical profile alias mismatch: #{logical_role} must use #{expected_alias}" unless routing_identity["logical_profile_alias"].to_s == expected_alias
if director_roles.include?(logical_role)
  errors << "active Director routing must carry its exact active_role_binding_id" if routing_identity["active_role_binding_id"].to_s.empty?
end

cdd_specialties = %w[
  reference reference_story_sequence reference_camera_composition reference_world_object_material
  reference_performance front_planning stage_01 stage_02a image 02b 03v image_and_03v
]
edit_specialties = %w[stage_04 04 edit_shard finishing_fx shot_vfx]
overall_specialties = %w[cdd_reviewed_milestone edit_reviewed_milestone director_reviewed_milestone]
expected_recipient = if cdd_specialties.include?(worker_specialty)
                       "creative_development_director"
                     elsif edit_specialties.include?(worker_specialty)
                       "edit_director"
                     elsif overall_specialties.include?(worker_specialty) || director_roles.include?(logical_role)
                       logical_role == "overall_director" ? nil : "overall_director"
                     end
if expected_recipient && recipient_role != expected_recipient
  errors << "routing recipient mismatch for #{worker_specialty}: expected #{expected_recipient}, got #{recipient_role}"
end
if routing_identity["session_topology"].to_s == "internal_parent_work_package"
  errors << "internal helper routing must not carry physical_transfer" unless routing_identity["physical_transfer"].nil?
end
if routing_identity["session_topology"].to_s == "physical_native_session" && routing_identity["physical_transfer"].is_a?(Hash)
  errors << "physical transfer must forbid simultaneous owners" unless routing_identity.dig("physical_transfer", "simultaneous_owner_forbidden") == true
end
internal_delegation = document["internal_delegation_summary"].is_a?(Hash) ? document["internal_delegation_summary"] : {}
if internal_delegation["provider_native_helpers_used"] == false
  errors << "internal delegation helper_count must be zero when helpers were unused" unless internal_delegation["helper_count"] == 0
elsif !internal_delegation["helper_count"].is_a?(Integer) || internal_delegation["helper_count"] < 1
  errors << "internal delegation helper_count must be positive when provider-native helpers were used"
end
submission_kind = review_submission["submission_kind"].to_s
submission_number = review_submission["submission_number"].to_i
task = launch["task"].is_a?(Hash) ? launch["task"] : {}
scope = task["exact_scope"].is_a?(Hash) ? task["exact_scope"] : {}
founder_context = launch["founder_context"].is_a?(Hash) ? launch["founder_context"] : {}
authority = launch["authority"].is_a?(Hash) ? launch["authority"] : {}
bounded_output = launch["bounded_output"].is_a?(Hash) ? launch["bounded_output"] : {}
external_permission = launch["external_permission"].is_a?(Hash) ? launch["external_permission"] : {}
output_kind = bounded_output["output_kind"].to_s
output_rule = V19_OUTPUT_RULES[output_kind]

compiled_launch = launch["compiled_launch_prompt"].is_a?(Hash) ? launch["compiled_launch_prompt"] : {}
raw_compiled_launch = raw_launch["compiled_launch_prompt"].is_a?(Hash) ? raw_launch["compiled_launch_prompt"] : {}
selected_profile = compiled_launch["selected_profile"].is_a?(Hash) ? compiled_launch["selected_profile"] : {}
_studio_kernel_path, studio_kernel_relative = file_binding(errors, "launch.compiled_launch_prompt.studio_kernel", compiled_launch["studio_kernel"])
unless studio_kernel_relative == PROVIDER_NEUTRAL_STUDIO_KERNEL
  errors << "compiled launch Studio Kernel must use the shared provider-neutral kernel: #{PROVIDER_NEUTRAL_STUDIO_KERNEL}"
end
registry_binding = {
  "path" => selected_profile["registry_path"],
  "sha256" => selected_profile["registry_sha256"]
}
registry_path, = file_binding(errors, "launch.compiled_launch_prompt.selected_profile.registry", registry_binding)
profile_registry = registry_path&.file? ? load_document(registry_path) : nil
profile_rows = profile_registry.is_a?(Hash) ? Array(profile_registry["profiles"]) : []
profile_row = profile_rows.find { |row| row.is_a?(Hash) && row["profile_id"].to_s == selected_profile["profile_id"].to_s }
checkpoint_row = nil
if profile_row.nil?
  errors << "compiled launch selected profile is not registered: #{selected_profile['profile_id'].inspect}"
else
  checkpoints = Array(profile_row.dig("phase_load", "checkpoints"))
  checkpoint_row = checkpoints.find { |row| row.is_a?(Hash) && row["checkpoint_id"].to_s == selected_profile["checkpoint_id"].to_s }
  if checkpoint_row.nil?
    errors << "compiled launch selected checkpoint is not registered for profile #{selected_profile['profile_id']}: #{selected_profile['checkpoint_id'].inspect}"
  end
end
compiled_input_basis = raw_compiled_launch.reject do |key, _value|
  %w[rendered_prompt compiled_input_sha256 rendered_prompt_sha256].include?(key.to_s)
end
errors << "compiled launch input SHA-256 is stale" unless raw_compiled_launch["compiled_input_sha256"].to_s == structured_sha256(compiled_input_basis)
errors << "compiled launch rendered prompt SHA-256 is stale" unless raw_compiled_launch["rendered_prompt_sha256"].to_s == Digest::SHA256.hexdigest(raw_compiled_launch["rendered_prompt"].to_s)
unless compiled_launch["first_runtime_action"].to_s == "open_native_goal_from_goal_contract_and_record_goal_id_before_reads_or_work"
  errors << "compiled launch first_runtime_action must require Goal creation before reads or work"
end
validate_rendered_launch_prompt(
  errors,
  compiled_launch["rendered_prompt"],
  launch["requirement_manifest"],
  bounded_output["anti_flat_evidence_requirements"]
)
if %w[cdd_startup successor_resume].include?(launch["launch_kind"].to_s) && task["role"].to_s != "creative_development_director"
  errors << "#{launch['launch_kind']} launch_kind requires task role creative_development_director"
end

errors << "lineage attempt_id must equal dispatch_id" unless lineage["attempt_id"].to_s == dispatch_id
attempt_number = lineage["attempt_number"].to_i
previous_document = nil
if attempt_number == 1
  errors << "first lineage attempt cannot name previous_attempt_id" unless lineage["previous_attempt_id"].nil?
elsif attempt_number > 1
  errors << "later lineage attempt must name previous_attempt_id" if lineage["previous_attempt_id"].to_s.empty?
  previous_attempt_id = lineage["previous_attempt_id"].to_s
  previous_path = dispatch_path.dirname.join("#{previous_attempt_id}.yaml")
  if previous_attempt_id.empty? || !previous_path.file?
    errors << "later lineage attempt must resolve its canonical predecessor in the same run: #{previous_attempt_id.inspect}"
  else
    previous_document = load_document(previous_path)
    unless previous_document.is_a?(Hash)
      errors << "canonical predecessor must be a readable Department Dispatch: #{previous_attempt_id}"
      previous_document = nil
    end
  end

  if previous_document
    previous_lineage = previous_document["lineage"].is_a?(Hash) ? previous_document["lineage"] : {}
    previous_state = previous_document.dig("lifecycle", "current_state").to_s
    previous_correction = previous_document.dig("director_review", "correction")
    previous_retry_route = previous_correction.is_a?(Hash) ? previous_correction["retry_route"].to_s : ""
    errors << "canonical predecessor dispatch_id must equal previous_attempt_id" unless previous_document["dispatch_id"].to_s == previous_attempt_id
    errors << "canonical predecessor must belong to the same declared run" unless previous_document["run"].to_s == run
    errors << "canonical predecessor attempt_id must equal previous_attempt_id" unless previous_lineage["attempt_id"].to_s == previous_attempt_id
    errors << "same-lineage attempts must preserve lineage_id" unless previous_lineage["lineage_id"].to_s == lineage["lineage_id"].to_s
    errors << "same-lineage attempts must use consecutive attempt numbers" unless previous_lineage["attempt_number"].to_i == attempt_number - 1
    %w[parent_session_id parent_lineage_id parent_dispatch_id delegation_depth provider runtime_surface].each do |field|
      unless canonicalize(previous_lineage[field]) == canonicalize(lineage[field])
        errors << "same-lineage attempts must preserve lineage.#{field}"
      end
    end
    previous_scope = previous_document.dig("launch", "task", "exact_scope")
    if submission_kind == "targeted_correction"
      unless scope_without_artifact_paths(previous_scope) == scope_without_artifact_paths(scope)
        errors << "targeted correction must preserve the predecessor stage and section scope while narrowing only artifact paths"
      end
    elsif canonicalize(previous_scope) != canonicalize(scope)
      errors << "same-lineage successor must preserve the predecessor exact scope"
    end
    unless previous_document.dig("launch", "authority", "assigned_owner").to_s == authority["assigned_owner"].to_s &&
           previous_document.dig("launch", "authority", "director_owner").to_s == authority["director_owner"].to_s
      errors << "same-lineage successor must preserve assigned and recipient Director ownership"
    end
    unless %w[promoted hold].include?(previous_state) &&
           previous_document["runtime_return"].is_a?(Hash) &&
           previous_document["director_review"].is_a?(Hash) &&
           previous_document["promotion"].is_a?(Hash) &&
           previous_document.dig("promotion", "decision").to_s == previous_state
      errors << "canonical predecessor must close runtime return, Director review, and promoted-or-hold disposition before successor launch"
    end
    previous_wake_kind = previous_document.dig("runtime_return", "wake_event", "event_kind").to_s
    if %w[authority_request milestone].include?(previous_wake_kind)
      errors << "authority_request or milestone wake preserves the predecessor attempt and cannot authorize a successor"
    end
    if previous_state == "hold"
      case previous_retry_route
      when "same_session_new_attempt"
        unless !lineage["session_id"].to_s.empty? && lineage["session_id"].to_s == previous_lineage["session_id"].to_s
          errors << "same_session_new_attempt successor must preserve the exact non-empty predecessor session_id"
        end
      when "new_session_new_lineage"
        errors << "new_session_new_lineage must start a fresh lineage at attempt one, not a same-lineage successor"
      when "upstream_owner", "hold"
        errors << "#{previous_retry_route} predecessor disposition forbids a direct child successor"
      else
        errors << "held predecessor must declare a legal retry route before a successor"
      end
    end
  end
end

submission_predecessor_document = nil
if review_submission["maximum_submissions"].to_i != 3
  errors << "review_submission maximum_submissions must be exactly 3"
end
case submission_kind
when "initial"
  errors << "initial review submission number must be 1" unless submission_number == 1
  errors << "initial review cycle id must equal its root attempt id" unless review_submission["review_cycle_id"].to_s == review_submission["root_attempt_id"].to_s
  errors << "initial review root attempt id must equal dispatch_id" unless review_submission["root_attempt_id"].to_s == dispatch_id
  if previous_document&.dig("lifecycle", "current_state").to_s == "hold" &&
     %w[same_session_new_attempt new_session_new_lineage].include?(previous_document.dig("director_review", "correction", "retry_route").to_s)
    errors << "a held predecessor correction must continue the same review cycle as targeted_correction; it cannot reset to an initial submission"
  end
when "targeted_correction"
  source = review_submission["correction_source"].is_a?(Hash) ? review_submission["correction_source"] : {}
  previous_submission_attempt_id = review_submission["previous_submission_attempt_id"].to_s
  source_path, source_relative = file_binding(errors, "review_submission.correction_source", source)
  expected_source_relative = "#{run}/work/department-dispatches/#{previous_submission_attempt_id}.yaml"
  errors << "targeted correction source must be its exact prior submission dispatch: #{expected_source_relative}" unless source_relative == expected_source_relative
  errors << "targeted correction source dispatch_id must equal previous_submission_attempt_id" unless source["dispatch_id"].to_s == previous_submission_attempt_id
  if source_path&.file?
    submission_predecessor_document = load_document(source_path)
    unless submission_predecessor_document.is_a?(Hash)
      errors << "targeted correction source must be a readable Department Dispatch"
      submission_predecessor_document = nil
    end
  end

  if submission_predecessor_document
    predecessor_submission = submission_predecessor_document["review_submission"].is_a?(Hash) ? submission_predecessor_document["review_submission"] : {}
    predecessor_correction = submission_predecessor_document.dig("director_review", "correction")
    predecessor_correction = {} unless predecessor_correction.is_a?(Hash)
    predecessor_outputs = Array(submission_predecessor_document.dig("runtime_return", "outputs"))
    repair_targets = Array(review_submission["repair_targets"])
    target_paths = repair_targets.map { |row| row.is_a?(Hash) ? row["path"].to_s : "" }
    expected_frozen_outputs = predecessor_outputs.reject do |row|
      row.is_a?(Hash) && target_paths.include?(row["path"].to_s)
    end
    retry_route = predecessor_correction["retry_route"].to_s

    predecessor_role = submission_predecessor_document.dig("launch", "task", "role").to_s
    errors << "targeted correction must keep launch.task.role on the same section-worker line" unless task["role"].to_s == predecessor_role && !predecessor_role.empty?
    errors << "targeted correction predecessor must belong to the same declared run" unless submission_predecessor_document["run"].to_s == run
    errors << "targeted correction predecessor must close on hold" unless submission_predecessor_document.dig("lifecycle", "current_state").to_s == "hold"
    errors << "targeted correction predecessor must authorize a child correction route" unless %w[same_session_new_attempt new_session_new_lineage].include?(retry_route)
    errors << "targeted correction must preserve review_cycle_id" unless review_submission["review_cycle_id"].to_s == predecessor_submission["review_cycle_id"].to_s
    errors << "targeted correction must preserve root_attempt_id" unless review_submission["root_attempt_id"].to_s == predecessor_submission["root_attempt_id"].to_s
    errors << "targeted correction submission numbers must be consecutive" unless submission_number == predecessor_submission["submission_number"].to_i + 1
    errors << "a review cycle may contain at most three total submissions including the initial return" if predecessor_submission["submission_number"].to_i >= 3
    unless exact_rows(repair_targets) == exact_rows(predecessor_correction["invalidated_outputs"])
      errors << "targeted correction repair_targets must exact-copy the predecessor invalidated_outputs"
    end
    unless canonicalize(review_submission["repair_acceptance_criteria"]) == canonicalize(predecessor_correction["acceptance_criteria"])
      errors << "targeted correction acceptance criteria must exact-copy the predecessor correction"
    end
    unless exact_rows(review_submission["frozen_outputs"]) == exact_rows(expected_frozen_outputs)
      errors << "targeted correction frozen_outputs must exact-copy every unaffected predecessor output"
    end
    unless task["objective"].to_s == predecessor_correction["correction_action"].to_s
      errors << "targeted correction Goal objective must exact-copy the predecessor correction_action"
    end
    unless Array(scope["artifact_paths"]).map(&:to_s) == target_paths
      errors << "targeted correction exact scope must contain only predecessor invalidated output paths"
    end

    case retry_route
    when "same_session_new_attempt"
      errors << "same-session targeted correction must use its submission predecessor as lineage.previous_attempt_id" unless lineage["previous_attempt_id"].to_s == previous_submission_attempt_id
      unless previous_document && canonicalize(previous_document) == canonicalize(submission_predecessor_document)
        errors << "same-session targeted correction must resolve the same canonical predecessor through lineage and review_submission"
      end
    when "new_session_new_lineage"
      errors << "new-session targeted correction must start at lineage attempt one" unless attempt_number == 1
      errors << "new-session targeted correction cannot use lineage.previous_attempt_id" unless lineage["previous_attempt_id"].nil?
      errors << "new-session targeted correction must use a fresh lineage_id" if lineage["lineage_id"].to_s == submission_predecessor_document.dig("lineage", "lineage_id").to_s
      errors << "new-session targeted correction must use a fresh non-empty session_id" if lineage["session_id"].to_s.empty? || lineage["session_id"].to_s == submission_predecessor_document.dig("lineage", "session_id").to_s
    end
  end

  repair_paths = Array(review_submission["repair_targets"]).map { |row| row.is_a?(Hash) ? row["path"].to_s : "" }
  duplicate_values(repair_paths).each { |value| errors << "duplicate or blank targeted correction repair path: #{value.inspect}" }
  frozen_paths = Array(review_submission["frozen_outputs"]).map { |row| row.is_a?(Hash) ? row["path"].to_s : "" }
  duplicate_values(frozen_paths).each { |value| errors << "duplicate or blank frozen output path: #{value.inspect}" }
  errors << "targeted correction repair_targets and frozen_outputs must be disjoint" unless (repair_paths & frozen_paths).empty?
  Array(review_submission["frozen_outputs"]).each_with_index do |row, index|
    _path, relative = file_binding(errors, "review_submission.frozen_outputs[#{index}]", row)
    errors << "frozen output must stay inside declared run" unless relative.start_with?("#{run}/")
  end
else
  errors << "review_submission must declare initial or targeted_correction"
end

if lineage["delegation_depth"].to_i == 1
  errors << "depth-one worker attempt must bind its parent session" if lineage["parent_session_id"].to_s.empty?
  errors << "depth-one worker attempt must bind its parent lineage" if lineage["parent_lineage_id"].to_s.empty?
  errors << "depth-one worker attempt must bind its parent dispatch" if lineage["parent_dispatch_id"].to_s.empty?
  errors << "worker session cannot equal its parent session" if lineage["session_id"].to_s == lineage["parent_session_id"].to_s
  errors << "worker lineage cannot equal its parent lineage" if lineage["lineage_id"].to_s == lineage["parent_lineage_id"].to_s
  errors << "worker attempt cannot equal its parent dispatch" if dispatch_id == lineage["parent_dispatch_id"].to_s
else
  %w[parent_session_id parent_lineage_id parent_dispatch_id].each do |field|
    errors << "depth-zero attempt cannot name #{field}" unless lineage[field].nil?
  end
end
if lineage["lineage_state"].to_s == "replaced"
  errors << "replaced lineage must name successor_attempt_id" if lineage["successor_attempt_id"].to_s.empty?
else
  errors << "only a replaced lineage may name successor_attempt_id" unless lineage["successor_attempt_id"].nil?
end

errors << "launch task_id must equal dispatch_id" unless task["task_id"].to_s == dispatch_id
errors << "launch recipient must be the declared director owner" unless launch.dig("recipient", "owner").to_s == authority["director_owner"].to_s

goal_contract = launch["goal_contract"].is_a?(Hash) ? launch["goal_contract"] : {}
errors << "goal_contract.goal_text must exact-copy launch.task.objective" unless goal_contract["goal_text"].to_s == task["objective"].to_s
errors << "goal_contract.goal_text_sha256 is stale" unless goal_contract["goal_text_sha256"].to_s == Digest::SHA256.hexdigest(goal_contract["goal_text"].to_s)

requirements = Array(launch["requirement_manifest"])
requirement_ids = hash_values(requirements, "requirement_id")
duplicate_values(requirement_ids).each { |value| errors << "duplicate or blank requirement id: #{value.inspect}" }
required_categories = requirements.select { |row| row.is_a?(Hash) && row["required"] == true }.map { |row| row["category"].to_s }.uniq
(REQUIREMENT_CATEGORIES - required_categories).each do |category|
  errors << "requirement_manifest requires at least one required #{category} row"
end
requirements.each_with_index do |row, index|
  next unless row.is_a?(Hash)

  prefix = row["requirement_id"].to_s.split("-", 2).first.to_s.downcase
  errors << "requirement_manifest[#{index}] category must match requirement_id prefix" unless prefix == row["category"].to_s
  next unless row["source_binding"].is_a?(Hash)

  file_binding(errors, "launch.requirement_manifest[#{index}].source_binding", row["source_binding"])
end

recipe_rows = IdolCheckpointClosureCatalog.recipe_rows(
  ROOT,
  profile_id: selected_profile["profile_id"],
  checkpoint_id: selected_profile["checkpoint_id"]
)
recipe_ids = recipe_rows.map { |row| row["requirement_id"].to_s }
if recipe_ids.any?
  missing_recipe_ids = recipe_ids - requirement_ids
  missing_recipe_ids.each do |requirement_id|
    errors << "requirement_manifest missing immutable recipe row #{requirement_id} for #{selected_profile['profile_id']}.#{selected_profile['checkpoint_id']}"
  end
  requirements.each_with_index do |row, index|
    next unless row.is_a?(Hash)
    next unless IdolCheckpointClosureCatalog.generic_follow_skill?(row)

    errors << "requirement_manifest[#{index}] must not PASS as a generic follow-skill row when recipe rows exist"
  end
end

scope_paths = Array(scope["artifact_paths"]).map(&:to_s)
expected_paths = Array(bounded_output["expected_paths"]).map(&:to_s)
errors << "exact scope artifact_paths must equal bounded output expected_paths" unless scope_paths == expected_paths
duplicate_values(scope_paths).each { |value| errors << "duplicate or blank exact-scope artifact path: #{value.inspect}" }
expected_paths.each do |path|
  errors << "bounded output path must stay inside declared run: #{path}" unless path.start_with?("#{run}/")
end
if bounded_output["maximum_artifact_count"].to_i < expected_paths.length
  errors << "maximum_artifact_count cannot be smaller than expected_paths"
end

if output_rule
  logical_owner = bounded_output["logical_owner"].is_a?(Hash) ? bounded_output["logical_owner"] : {}
  allowed_roles = output_rule.fetch(:roles)
  required_binding_kinds = output_rule.fetch(:binding_kinds)
  declared_binding_kinds = Array(bounded_output["required_binding_kinds"]).map(&:to_s)

  unless allowed_roles.include?(task["role"].to_s)
    errors << "bounded_output output_kind=#{output_kind} requires task role #{allowed_roles.join(' or ')}"
  end
  errors << "bounded_output logical owner must equal launch authority assigned_owner" unless logical_owner["owner"].to_s == authority["assigned_owner"].to_s
  errors << "bounded_output logical owner role must equal launch task role" unless logical_owner["role"].to_s == task["role"].to_s
  unless declared_binding_kinds.sort == required_binding_kinds.sort
    errors << "bounded_output output_kind=#{output_kind} requires exact required_binding_kinds #{required_binding_kinds.join(', ')}"
  end
end

section_ids = Array(scope["section_ids"])
case scope["mode"].to_s
when "whole_run", "artifact"
  errors << "#{scope['mode']} scope cannot declare section_ids" unless section_ids.empty?
when "section"
  errors << "section scope must declare exactly one section_id" unless section_ids.length == 1
when "section_set"
  errors << "section_set scope must declare at least two section_ids" unless section_ids.length >= 2
end

if output_kind == "pre_02a_section_working_shard"
  unless %w[section section_set].include?(scope["mode"].to_s)
    errors << "pre_02a_section_working_shard requires section or section_set exact scope"
  end
  unless section_ids.length.between?(1, 3)
    errors << "pre_02a_section_working_shard must own one to three exact section_ids"
  end
  unless expected_paths.length == section_ids.length
    errors << "pre_02a_section_working_shard expected_paths must provide exactly one path per section_id"
  end
  unless bounded_output["maximum_artifact_count"].to_i == section_ids.length
    errors << "pre_02a_section_working_shard maximum_artifact_count must equal its section count"
  end
end
if output_kind == "founder_briefing_projection"
  expected_working_path = "#{run}/work/department-dispatches/outputs/#{dispatch_id}.json"
  errors << "founder_briefing_projection requires artifact exact scope" unless scope["mode"].to_s == "artifact"
  errors << "founder_briefing_projection cannot declare section_ids" unless section_ids.empty?
  errors << "founder_briefing_projection must declare exactly one working output path" unless expected_paths == [expected_working_path]
  errors << "founder_briefing_projection maximum_artifact_count must equal one" unless bounded_output["maximum_artifact_count"].to_i == 1
  errors << "founder_briefing_projection worker cannot write canonical paths directly" unless authority["canonical_write"].to_s == "forbidden"
  errors << "founder_briefing_projection must use its noncreative projection scope" unless scope["stage_id"].to_s == "founder_briefing_projection"
  errors << "founder_briefing_projection must use the registered founder_briefing.briefing_refresh checkpoint" unless selected_profile["profile_id"].to_s == "founder_briefing" && selected_profile["checkpoint_id"].to_s == "briefing_refresh"
  errors << "founder_briefing_projection must return directly to Overall review" unless launch.dig("recipient", "role").to_s == "overall_director"
end

lock_ids = hash_values(founder_context["locks"], "lock_id")
duplicate_values(lock_ids).each { |value| errors << "duplicate or blank Founder lock id: #{value.inspect}" }

required_skills = Array(launch["required_skills"])
validate_whole_skill_prose_not_duplicated(errors, compiled_launch["rendered_prompt"], required_skills)
skill_paths = hash_values(required_skills, "path")
duplicate_values(skill_paths).each { |value| errors << "duplicate or blank required skill path: #{value.inspect}" }
required_skills.each_with_index do |skill, index|
  next unless skill.is_a?(Hash)

  file_binding(errors, "launch.required_skills[#{index}]", skill)
  errors << "launch.required_skills[#{index}] must name root, Grok, or CF SKILL.md" unless skill["path"].to_s.match?(%r{\A(?:skills|\.grok/skills|cf/skills)/.+/SKILL\.md\z})
  errors << "launch.required_skills[#{index}] must require EOF" unless skill["eof_required"] == true
  linked_paths = hash_values(skill["linked_reads"], "path")
  duplicate_values(linked_paths).each { |value| errors << "duplicate or blank linked read for #{skill['path']}: #{value.inspect}" }
  Array(skill["linked_reads"]).each_with_index do |row, linked_index|
    file_binding(errors, "launch.required_skills[#{index}].linked_reads[#{linked_index}]", row)
    errors << "launch.required_skills[#{index}].linked_reads[#{linked_index}] must require EOF" unless row.is_a?(Hash) && row["eof_required"] == true
  end
end
Array(launch["required_reads"]).each_with_index do |row, index|
  next unless row.is_a?(Hash)

  file_binding(errors, "launch.required_reads[#{index}]", row)
  errors << "launch.required_reads[#{index}] must require EOF" unless row["eof_required"] == true
end

# CF-code is an isolated lane whose task profiles are owned under cf/. The
# common launch-command and byte/hash checks still apply there; exact IDOL
# profile-role/read closure is enforced only for the active IDOL route.
unless run.start_with?("cf/")
  if profile_row.is_a?(Hash) && checkpoint_row.is_a?(Hash) && profile_registry.is_a?(Hash)
    unless task["role"].to_s == profile_row["role"].to_s
      errors << "compiled launch task role must match selected provider-neutral profile role: expected #{profile_row['role']}, got #{task['role']}"
    end
    projection_only_briefing = output_kind == "founder_briefing_projection" &&
                               selected_profile["profile_id"].to_s == "founder_briefing" &&
                               profile_row["projection_only"] == true &&
                               scope["stage_id"].to_s == "founder_briefing_projection"
    maintenance_only_dispatch = output_kind == "bounded_artifact" &&
                                selected_profile["profile_id"].to_s == "harness_maintenance" &&
                                profile_row["maintenance_only"] == true &&
                                Array(profile_row["maintenance_surface_ids"]).map(&:to_s).include?(selected_profile["checkpoint_id"].to_s) &&
                                scope["stage_id"].to_s == selected_profile["checkpoint_id"].to_s
    unless projection_only_briefing || maintenance_only_dispatch || Array(profile_row["stage_ids"]).map(&:to_s).include?(scope["stage_id"].to_s)
      errors << "compiled launch stage is outside selected profile: #{selected_profile['profile_id']} does not own #{scope['stage_id']}"
    end

    skill_bindings_by_id = Array(profile_registry["skill_bindings"]).each_with_object({}) do |row, result|
      result[row["binding_id"].to_s] = row if row.is_a?(Hash)
    end
    read_bindings_by_id = Array(profile_registry["read_bindings"]).each_with_object({}) do |row, result|
      result[row["binding_id"].to_s] = row if row.is_a?(Hash)
    end

    expected_skills = Array(checkpoint_row["required_skill_ids"]).each_with_object([]) do |binding_id, result|
      row = skill_bindings_by_id[binding_id.to_s]
      if row.nil?
        errors << "selected checkpoint references missing skill binding: #{binding_id}"
        next
      end
      result << {
        "path" => row["path"].to_s,
        "revision" => row["revision"].to_s,
        "sha256" => row["sha256"].to_s,
        "eof_required" => true
      }
    end
    actual_skills = required_skills.each_with_object([]) do |row, result|
      next unless row.is_a?(Hash)
      result << {
        "path" => row["path"].to_s,
        "revision" => row["revision"].to_s,
        "sha256" => row["sha256"].to_s,
        "eof_required" => row["eof_required"]
      }
    end
    unless canonicalize(actual_skills) == canonicalize(expected_skills)
      errors << "launch.required_skills must exact-copy the selected checkpoint skill bindings"
    end

    expected_reads = Array(checkpoint_row["required_read_ids"]).each_with_object([]) do |binding_id, result|
      row = read_bindings_by_id[binding_id.to_s]
      if row.nil?
        errors << "selected checkpoint references missing read binding: #{binding_id}"
        next
      end
      result << {
        "path" => row["path"].to_s,
        "sha256" => row["sha256"].to_s,
        "eof_required" => true
      }
    end
    launch_required_reads = Array(launch["required_reads"])
    skill_linked_reads = required_skills.flat_map do |skill|
      Array(skill.is_a?(Hash) ? skill["linked_reads"] : nil)
    end
    if required_skills.empty?
      actual_reads = launch_required_reads.each_with_object([]) do |row, result|
        next unless row.is_a?(Hash)
        result << {
          "path" => row["path"].to_s,
          "sha256" => row["sha256"].to_s,
          "eof_required" => row["eof_required"]
        }
      end
    else
      errors << "launch.required_reads is only for skill-less maintenance checkpoints" unless launch_required_reads.empty?
      actual_reads = skill_linked_reads.each_with_object([]) do |row, result|
        next unless row.is_a?(Hash)
        result << {
          "path" => row["path"].to_s,
          "sha256" => row["sha256"].to_s,
          "eof_required" => row["eof_required"]
        }
      end
    end
    duplicate_values(actual_reads.map { |row| row["path"] }).each do |value|
      errors << "duplicate or blank checkpoint linked read across required skills: #{value.inspect}"
    end
    unless canonicalize(actual_reads) == canonicalize(expected_reads)
      errors << "launch linked reads must exact-copy the selected checkpoint read bindings"
    end
  end
end

sources = Array(launch["sources"])
source_ids = hash_values(sources, "source_id")
duplicate_values(source_ids).each { |value| errors << "duplicate or blank source_id: #{value.inspect}" }
sources.each_with_index { |row, index| file_binding(errors, "launch.sources[#{index}]", row) }
source_by_id = sources.each_with_object({}) do |row, result|
  result[row["source_id"].to_s] = row if row.is_a?(Hash)
end
delta_source_ids = Array(compiled_launch["current_run_creative_delta_source_ids"]).map(&:to_s)
(delta_source_ids - source_ids).each do |source_id|
  errors << "compiled launch Creative Delta source_id is not declared by launch.sources: #{source_id.inspect}"
end

case external_permission["mode"].to_s
when "closed_local"
  errors << "closed_local dispatch cannot name allowed external surfaces" unless Array(external_permission["allowed_surfaces"]).empty?
  errors << "closed_local dispatch cannot carry an approval reference" unless external_permission["approval_reference"].nil?
  errors << "closed_local dispatch authority must forbid external actions" unless authority["external_actions"].to_s == "forbidden"
when "founder_approved"
  errors << "founder_approved dispatch must name at least one allowed surface" if Array(external_permission["allowed_surfaces"]).empty?
  errors << "founder_approved dispatch must bind its approval reference" if external_permission["approval_reference"].to_s.empty?
  errors << "founder_approved dispatch authority must be founder_approved_only" unless authority["external_actions"].to_s == "founder_approved_only"
end

lifecycle = document["lifecycle"].is_a?(Hash) ? document["lifecycle"] : {}
current_state = lifecycle["current_state"].to_s
events = Array(lifecycle["events"])
event_states = hash_values(events, "state")
expected_states = LIFECYCLE_PREFIXES[current_state]
errors << "lifecycle events must be the exact prefix for #{current_state}: #{Array(expected_states).join(' -> ')}" unless event_states == expected_states
event_by_state = events.each_with_object({}) do |row, result|
  result[row["state"].to_s] = row if row.is_a?(Hash)
end
errors << "prepared event timestamp must equal launch.prepared_at" unless event_by_state.dig("prepared", "at").to_s == launch["prepared_at"].to_s
if current_state != "prepared"
  errors << "launched event timestamp must equal launch.launched_at" unless event_by_state.dig("launched", "at").to_s == launch["launched_at"].to_s
end

review_control = document["review_control"].is_a?(Hash) ? document["review_control"] : {}
unless review_control["queue_policy"].to_s == "single_flight_per_recipient_director_then_global_overall_promotion"
  errors << "review_control must use the registered Director single-flight queue policy"
end
expected_queue_states = case current_state
                        when "prepared", "launched" then %w[not_eligible]
                        when "returned" then %w[queued in_review]
                        when "reviewed" then %w[disposition_recorded promotion_in_progress]
                        when "promoted", "hold" then %w[released]
                        else []
                        end
unless expected_queue_states.include?(review_control["queue_state"].to_s)
  errors << "review_control queue_state is incompatible with lifecycle current_state=#{current_state}"
end
queue_priority = review_control["queue_priority"].is_a?(Hash) ? review_control["queue_priority"] : {}
errors << "review queue dependency_rank must be a nonnegative integer" unless queue_priority["dependency_rank"].is_a?(Integer) && queue_priority["dependency_rank"] >= 0
if runtime_return_placeholder = document["runtime_return"]
  if runtime_return_placeholder.is_a?(Hash) && review_control["queue_state"].to_s != "not_eligible"
    errors << "review queued_at must equal runtime_return.returned_at" unless review_control["queued_at"].to_s == runtime_return_placeholder["returned_at"].to_s
  end
end

runtime_return = document["runtime_return"]
if runtime_return.is_a?(Hash)
  errors.concat(
    IdolHelperConsumptionReceipts.validate(
      root: ROOT,
      document: document,
      bind_file: method(:file_binding)
    )
  )
  loaded_receipts = IdolHelperConsumptionReceipts.load_receipts(root: ROOT, document: document)
  errors.concat(
    IdolRunFollowupSidecar.validate(
      root: ROOT,
      document: document,
      receipts: loaded_receipts,
      require_on_material: true
    )
  )
  errors << "returned event timestamp must equal runtime_return.returned_at" unless event_by_state.dig("returned", "at").to_s == runtime_return["returned_at"].to_s
  errors << "runtime owner must equal launch authority assigned_owner" unless runtime_return.dig("runtime_owner", "owner").to_s == authority["assigned_owner"].to_s
  errors << "runtime owner role must equal launch task role" unless runtime_return.dig("runtime_owner", "role").to_s == task["role"].to_s
  closure = runtime_return["transport_closure_summary"].is_a?(Hash) ? runtime_return["transport_closure_summary"] : {}
  if closure["creative_bytes_changed"] == true && !%w[director_impact_required blocked].include?(closure["status"].to_s)
    errors << "creative-byte transport change must require Director impact or remain blocked"
  end
  errors << "transport closure next_owner must equal routing return recipient" unless closure["next_owner"].to_s == recipient_role

  runtime_goal = runtime_return["runtime_goal"].is_a?(Hash) ? runtime_return["runtime_goal"] : {}
  expected_goal_provider = %w[codex grok].include?(lineage["provider"].to_s) ? lineage["provider"].to_s : "other_registered_provider"
  errors << "runtime Goal provider must match the dispatch lineage provider" unless runtime_goal["provider"].to_s == expected_goal_provider
  errors << "runtime Goal must exact-copy the launch Goal text hash" unless runtime_goal["goal_text_sha256"].to_s == goal_contract["goal_text_sha256"].to_s

  goal_opened_at = timestamp_value(errors, "runtime_return.runtime_goal.opened_at", runtime_goal["opened_at"])
  work_started_at = timestamp_value(errors, "runtime_return.work_started_at", runtime_return["work_started_at"])
  returned_at = timestamp_value(errors, "runtime_return.returned_at", runtime_return["returned_at"])

  projected_instruction = launch["instruction_delivery"].to_s == "role_context_pack"
  if projected_instruction
    unless Array(runtime_return["skill_revisions"]).empty?
      errors << "projected role_context_pack return must use empty skill_revisions"
    end
    receipt = runtime_return["role_context_receipt"]
    unless receipt.is_a?(Hash)
      errors << "projected role_context_pack return requires runtime_return.role_context_receipt"
    else
      begin
        recorded_goal = {
          "provider" => runtime_goal["provider"],
          "native_goal_id" => runtime_goal["native_goal_id"],
          "native_session_id" => lineage["session_id"].to_s,
          "assignment_key" => IdolDepartmentContext.assignment_key_from_owner(authority["assigned_owner"]),
          "dispatch_id" => dispatch_id,
          "attempt_id" => lineage["attempt_id"].to_s,
          "runtime_surface" => lineage["runtime_surface"].to_s,
          "goal_text_sha256" => goal_contract["goal_text_sha256"].to_s,
          "raw_event_sha256" => receipt["native_goal_raw_event_sha256"],
          "observed_at" => runtime_goal["opened_at"].to_s,
          "evidence_source" => IdolDepartmentContext::REQUIRED_EVIDENCE_SOURCE,
          "objective" => task["objective"].to_s,
          "request_id" => runtime_goal["request_id"]
        }
        IdolDepartmentContext.validate_application!(
          root: ROOT,
          dispatch: raw_document.is_a?(Hash) ? raw_document : document,
          runtime_goal: recorded_goal,
          application: receipt,
          work_started_at: runtime_return["work_started_at"],
          returned_at: runtime_return["returned_at"]
        )
      rescue IdolDepartmentContext::ContractError, JSON::ParserError, KeyError, Errno::ENOENT => e
        errors << "role context application invalid: #{e.message}"
      end
    end
  else
    if runtime_return.key?("role_context_receipt")
      errors << "legacy EOF return cannot carry runtime_return.role_context_receipt"
    end
    expected_skill_revisions = required_skills.map do |skill|
      next {} unless skill.is_a?(Hash)

      {
        "path" => skill["path"],
        "revision" => skill["revision"],
        "sha256" => skill["sha256"],
        "read_to_eof" => true,
        "linked_reads" => Array(skill["linked_reads"]).map do |row|
          {
            "path" => row["path"],
            "sha256" => row["sha256"],
            "read_to_eof" => true
          }
        end
      }
    end
    actual_skill_revisions = Array(runtime_return["skill_revisions"])
    comparable_skill_revisions = actual_skill_revisions.map do |skill|
      next {} unless skill.is_a?(Hash)

      {
        "path" => skill["path"],
        "revision" => skill["revision"],
        "sha256" => skill["sha256"],
        "read_to_eof" => skill["read_to_eof"],
        "linked_reads" => Array(skill["linked_reads"]).map do |row|
          {
            "path" => row["path"],
            "sha256" => row["sha256"],
            "read_to_eof" => row["read_to_eof"]
          }
        end
      }
    end
    unless canonicalize(comparable_skill_revisions) == canonicalize(expected_skill_revisions)
      errors << "runtime skill revisions must exact-copy launch skill/read revisions and record EOF"
    end

    read_times = []
    actual_skill_revisions.each_with_index do |skill, skill_index|
      next unless skill.is_a?(Hash)

      read_times << timestamp_value(
        errors,
        "runtime_return.skill_revisions[#{skill_index}].read_completed_at",
        skill["read_completed_at"]
      )
      Array(skill["linked_reads"]).each_with_index do |row, read_index|
        next unless row.is_a?(Hash)

        read_times << timestamp_value(
          errors,
          "runtime_return.skill_revisions[#{skill_index}].linked_reads[#{read_index}].read_completed_at",
          row["read_completed_at"]
        )
      end
    end
    read_times.compact!
    if goal_opened_at && read_times.any? { |time| time < goal_opened_at }
      errors << "runtime Goal must open before every required skill or linked-module read completes"
    end
    if work_started_at && read_times.any? { |time| time > work_started_at }
      errors << "every required skill and linked module must be read to EOF before creative work starts"
    end
  end
  if goal_opened_at && work_started_at && work_started_at < goal_opened_at
    errors << "runtime Goal must open before creative work starts"
  end
  if work_started_at && returned_at && returned_at < work_started_at
    errors << "runtime return cannot precede creative work start"
  end

  input_basis = {"lineage" => raw_lineage, "review_submission" => raw_review_submission, "launch" => raw_launch}
  expected_input_sha = structured_sha256(input_basis)
  expected_input_basis = "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4"
  errors << "input_digest basis must be #{expected_input_basis}" unless runtime_return.dig("input_digest", "basis").to_s == expected_input_basis
  errors << "input_digest SHA-256 is stale" unless runtime_return.dig("input_digest", "sha256").to_s == expected_input_sha

  mechanical_receipt = runtime_return["mechanical_compliance_receipt"].is_a?(Hash) ? runtime_return["mechanical_compliance_receipt"] : {}
  receipt_basis = mechanical_receipt.reject { |key, _value| key.to_s == "receipt_sha256" }
  errors << "mechanical compliance receipt SHA-256 is stale" unless mechanical_receipt["receipt_sha256"].to_s == structured_sha256(receipt_basis)
  mechanical_validated_at = timestamp_value(errors, "runtime_return.mechanical_compliance_receipt.validated_at", mechanical_receipt["validated_at"])
  if work_started_at && mechanical_validated_at && mechanical_validated_at < work_started_at
    errors << "mechanical compliance validation cannot precede creative work start"
  end
  if returned_at && mechanical_validated_at && mechanical_validated_at > returned_at
    errors << "mechanical compliance validation must finish before runtime return"
  end
  mechanical_checks = Array(mechanical_receipt["checks"])
  check_ids = hash_values(mechanical_checks, "check_id")
  duplicate_values(check_ids).each { |value| errors << "duplicate or blank mechanical check id: #{value.inspect}" }
  check_requirement_ids = hash_values(mechanical_checks, "requirement_id")
  (check_requirement_ids - requirement_ids).each do |requirement_id|
    errors << "mechanical check references undeclared requirement_id: #{requirement_id.inspect}"
  end
  required_requirement_ids = requirements.select { |row| row.is_a?(Hash) && row["required"] == true }.map { |row| row["requirement_id"].to_s }
  (required_requirement_ids - check_requirement_ids).each do |requirement_id|
    errors << "every required requirement needs at least one mechanical structural check: #{requirement_id}"
  end
  expected_all_required_checks_pass = mechanical_checks.all? { |row| row.is_a?(Hash) && row["result"].to_s == "pass" } &&
                                      (required_requirement_ids - check_requirement_ids).empty?
  unless mechanical_receipt["all_required_checks_pass"] == expected_all_required_checks_pass
    errors << "mechanical receipt all_required_checks_pass does not match its required check results"
  end

  fulfillment_claims = Array(runtime_return["worker_fulfillment_claims"])
  claim_requirement_ids = hash_values(fulfillment_claims, "requirement_id")
  duplicate_values(claim_requirement_ids).each { |value| errors << "duplicate or blank worker fulfillment requirement_id: #{value.inspect}" }
  unless claim_requirement_ids.sort == requirement_ids.sort
    errors << "worker fulfillment claims must exact-cover launch.requirement_manifest requirement ids"
  end
  fulfillment_claims.each_with_index do |claim, claim_index|
    next unless claim.is_a?(Hash)

    requirement = requirements.find { |row| row.is_a?(Hash) && row["requirement_id"].to_s == claim["requirement_id"].to_s }
    if requirement && requirement["required"] == true && claim["disposition"].to_s == "not_applicable"
      errors << "required worker fulfillment claim cannot be not_applicable: #{claim['requirement_id']}"
    end
    evidence_rows = Array(claim["output_evidence"])
    evidence_rows.each_with_index do |row, evidence_index|
      file_binding(errors, "runtime_return.worker_fulfillment_claims[#{claim_index}].output_evidence[#{evidence_index}]", row)
    end
    if requirement && requirement["required"] == true && claim["disposition"].to_s == "applied" &&
       !%w[goal hold].include?(requirement["category"].to_s) && evidence_rows.empty?
      errors << "applied required worker claim needs hash-bound output evidence: #{claim['requirement_id']}"
    end
  end

  completion_basis = {
    "mechanical_compliance_receipt_sha256" => raw_runtime_return.dig("mechanical_compliance_receipt", "receipt_sha256"),
    "worker_fulfillment_claims" => raw_runtime_return["worker_fulfillment_claims"],
    "outputs" => raw_runtime_return["outputs"],
    "hold_reasons" => raw_runtime_return["hold_reasons"]
  }
  unless runtime_goal["completion_evidence_sha256"].to_s == structured_sha256(completion_basis)
    errors << "runtime Goal completion evidence SHA-256 is stale"
  end
  if runtime_goal["state_at_return"].to_s == "runtime_blocked"
    errors << "goal_surface_unavailable runtime HOLD cannot return output bytes" unless Array(runtime_return["outputs"]).empty?
    unless Array(runtime_return["hold_reasons"]).any? { |reason| reason.to_s.include?("goal_surface_unavailable") }
      errors << "runtime_blocked Goal state requires a goal_surface_unavailable hold reason"
    end
  end

  result_basis = {
    "work_started_at" => raw_runtime_return["work_started_at"],
    "runtime_owner" => raw_runtime_return["runtime_owner"],
    "runtime_goal" => raw_runtime_return["runtime_goal"],
    "skill_revisions" => raw_runtime_return["skill_revisions"],
    "mechanical_compliance_receipt" => raw_runtime_return["mechanical_compliance_receipt"],
    "worker_fulfillment_claims" => raw_runtime_return["worker_fulfillment_claims"],
    "output_inventory" => raw_runtime_return["output_inventory"],
    "outputs" => raw_runtime_return["outputs"],
    "hold_reasons" => raw_runtime_return["hold_reasons"],
    "wake_event" => raw_runtime_return["wake_event"]
  }
  if projected_instruction
    result_basis["role_context_receipt"] = raw_runtime_return["role_context_receipt"]
  end
  expected_result_sha = structured_sha256(result_basis)
  expected_result_basis = "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4"
  errors << "result_digest basis must be #{expected_result_basis}" unless runtime_return.dig("result_digest", "basis").to_s == expected_result_basis
  errors << "result_digest SHA-256 is stale" unless runtime_return.dig("result_digest", "sha256").to_s == expected_result_sha

  outputs = Array(runtime_return["outputs"])
  output_inventory = runtime_return["output_inventory"].is_a?(Hash) ? runtime_return["output_inventory"] : {}
  errors << "output_inventory artifact_count must equal returned output count" unless output_inventory["artifact_count"].to_i == outputs.length
  if outputs.length <= 1
    errors << "zero or one returned output requires single_artifact inventory mode" unless output_inventory["mode"].to_s == "single_artifact"
    errors << "single_artifact inventory cannot bind an aggregate manifest" unless output_inventory["aggregate_manifest"].nil?
  else
    errors << "multiple returned outputs require aggregate_manifest inventory mode" unless output_inventory["mode"].to_s == "aggregate_manifest"
    manifest = output_inventory["aggregate_manifest"]
    if manifest.is_a?(Hash)
      _manifest_path, manifest_relative = file_binding(errors, "runtime_return.output_inventory.aggregate_manifest", manifest)
      errors << "aggregate manifest must stay inside declared run" unless manifest_relative.start_with?("#{run}/")
    else
      errors << "multiple returned outputs require a hash-bound aggregate manifest"
    end
  end
  output_paths = hash_values(outputs, "path")
  duplicate_values(output_paths).each { |value| errors << "duplicate or blank runtime output path: #{value.inspect}" }
  errors << "runtime returned more outputs than maximum_artifact_count" if outputs.length > bounded_output["maximum_artifact_count"].to_i
  returned_section_ids = []
  outputs.each_with_index do |row, index|
    label = "runtime_return.outputs[#{index}]"
    path, relative = file_binding(errors, label, row)
    errors << "runtime output was not declared by bounded_output.expected_paths: #{relative}" unless expected_paths.include?(relative)

    next unless output_rule && row.is_a?(Hash)

    errors << "#{label} output_kind must exact-copy launch bounded_output.output_kind" unless row["output_kind"].to_s == output_kind
    errors << "#{label} logical_owner must exact-copy launch bounded_output.logical_owner" unless canonicalize(row["logical_owner"]) == canonicalize(bounded_output["logical_owner"])
    errors << "#{label} decision_epoch must exact-copy launch founder_context.decision_epoch" unless row["decision_epoch"].to_s == founder_context["decision_epoch"].to_s

    bindings = Array(row["bindings"])
    binding_keys = bindings.map do |binding|
      binding.is_a?(Hash) ? [binding["binding_kind"], binding["source_id"]].map(&:to_s).join("|") : ""
    end
    duplicate_values(binding_keys).each { |value| errors << "#{label} repeats or blanks a binding kind/source pair: #{value.inspect}" }
    actual_binding_kinds = hash_values(bindings, "binding_kind")
    missing_binding_kinds = output_rule.fetch(:binding_kinds) - actual_binding_kinds
    unless missing_binding_kinds.empty?
      errors << "#{label} misses required binding kinds for #{output_kind}: #{missing_binding_kinds.join(', ')}"
    end
    bindings.each_with_index do |binding, binding_index|
      validate_v18_output_binding(errors, "#{label}.bindings[#{binding_index}]", binding, source_by_id)
    end

    if output_kind == "founder_briefing_projection"
      validate_founder_briefing_output(errors, label, path, relative, run, bindings)
    end

    next unless output_kind == "pre_02a_section_working_shard"

    validate_pre_02a_section_output(errors, label, path, relative, bounded_output["logical_owner"], scope)
    contract = path&.file? ? load_document(path) : nil
    returned_section_ids << contract.dig("payload", "id_namespace", "visual_section_id").to_s if contract.is_a?(Hash)
  end
  if output_kind == "pre_02a_section_working_shard" && !outputs.empty? && returned_section_ids.sort != section_ids.map(&:to_s).sort
    errors << "pre_02a_section_working_shard outputs must exact-cover dispatch exact_scope.section_ids"
  end
  if submission_kind == "targeted_correction"
    repair_targets_by_path = Array(review_submission["repair_targets"]).each_with_object({}) do |row, result|
      result[row["path"].to_s] = row if row.is_a?(Hash)
    end
    unless output_paths == repair_targets_by_path.keys
      errors << "targeted correction runtime outputs must exact-cover repair_targets in declared order"
    end
    outputs.each_with_index do |row, index|
      next unless row.is_a?(Hash)

      target = repair_targets_by_path[row["path"].to_s]
      next unless target.is_a?(Hash)

      label = "runtime_return.outputs[#{index}]"
      errors << "#{label} must contain changed bytes for its invalidated repair target" if row["sha256"].to_s == target["sha256"].to_s
      errors << "#{label}.source_output_path must bind the invalidated predecessor output path" unless row["source_output_path"].to_s == target["path"].to_s
      errors << "#{label}.source_output_sha256 must bind the invalidated predecessor output SHA-256" unless row["source_output_sha256"].to_s == target["sha256"].to_s
      %w[role output_kind logical_owner decision_epoch bindings].each do |field|
        next unless target.key?(field) || row.key?(field)

        errors << "#{label}.#{field} must preserve its repair target metadata" unless canonicalize(row[field]) == canonicalize(target[field])
      end
    end
  end
  if outputs.empty? && Array(runtime_return["hold_reasons"]).empty?
    errors << "runtime return must contain output bytes or an explicit hold reason"
  end

  wake_event = runtime_return["wake_event"].is_a?(Hash) ? runtime_return["wake_event"] : {}
  errors << "wake event recipient role must exact-copy launch recipient role" unless wake_event["recipient_role"].to_s == launch.dig("recipient", "role").to_s
  errors << "wake event output pointers must exact-copy runtime outputs" unless exact_rows(wake_event["output_pointers"]) == exact_rows(outputs)
  errors << "wake event aggregate manifest must exact-copy output inventory" unless canonicalize(wake_event["aggregate_manifest"]) == canonicalize(output_inventory["aggregate_manifest"])
  Array(wake_event["hold_or_rejection_pointers"]).each_with_index do |row, index|
    file_binding(errors, "runtime_return.wake_event.hold_or_rejection_pointers[#{index}]", row)
  end
  Array(wake_event["risk_or_unresolved_decision_pointers"]).each_with_index do |row, index|
    file_binding(errors, "runtime_return.wake_event.risk_or_unresolved_decision_pointers[#{index}]", row)
  end
  if wake_event["event_kind"].to_s == "final" && outputs.empty?
    errors << "final wake event requires at least one returned output pointer"
  end
  if wake_event["event_kind"].to_s == "hold" && Array(runtime_return["hold_reasons"]).empty?
    errors << "hold wake event requires an explicit runtime hold reason"
  end

  if previous_document&.dig("runtime_return").is_a?(Hash)
    previous_outputs = binding_pairs(previous_document.dig("runtime_return", "outputs")).sort
    current_outputs = binding_pairs(runtime_return["outputs"]).sort
    same_epoch = previous_document.dig("launch", "founder_context", "decision_epoch").to_s == founder_context["decision_epoch"].to_s
    same_governing_input = canonicalize(review_input_basis(previous_document)) == canonicalize(review_input_basis(raw_document))
    if same_epoch && same_governing_input && !current_outputs.empty? && current_outputs == previous_outputs
      errors << "unchanged input, result bytes, and Founder epoch must reuse the predecessor review receipt instead of opening duplicate semantic review"
    end
  end
end

director_review = document["director_review"]
if director_review.is_a?(Hash)
  errors << "reviewed event timestamp must equal director_review.reviewed_at" unless event_by_state.dig("reviewed", "at").to_s == director_review["reviewed_at"].to_s
  errors << "director review owner must equal launch authority director_owner" unless director_review.dig("director", "owner").to_s == authority["director_owner"].to_s

  review_lease = review_control["review_lease"].is_a?(Hash) ? review_control["review_lease"] : {}
  errors << "director review must bind the active review lease id" unless director_review["review_lease_id"].to_s == review_lease["lease_id"].to_s
  errors << "review lease director_owner must equal the launch director owner" unless review_lease["director_owner"].to_s == authority["director_owner"].to_s
  review_acquired_at = timestamp_value(errors, "review_control.review_lease.acquired_at", review_lease["acquired_at"])
  reviewed_at = timestamp_value(errors, "director_review.reviewed_at", director_review["reviewed_at"])
  review_released_at = timestamp_value(errors, "review_control.review_lease.released_at", review_lease["released_at"])
  if review_acquired_at && reviewed_at && reviewed_at < review_acquired_at
    errors << "director review cannot finish before its review lease is acquired"
  end
  if reviewed_at && review_released_at && review_released_at < reviewed_at
    errors << "director review lease cannot release before disposition is recorded"
  end

  reviewer_reads = Array(director_review["reviewer_read_closure"])
  reviewer_read_pairs = binding_pairs(reviewer_reads)
  duplicate_values(reviewer_read_pairs.map { |pair| pair.join("|") }).each do |value|
    errors << "duplicate or blank Director reviewer read binding: #{value.inspect}"
  end
  reviewer_reads.each_with_index do |row, index|
    next unless row.is_a?(Hash)

    file_binding(errors, "director_review.reviewer_read_closure[#{index}]", row)
    read_at = timestamp_value(errors, "director_review.reviewer_read_closure[#{index}].read_completed_at", row["read_completed_at"])
    if review_acquired_at && read_at && read_at < review_acquired_at
      errors << "Director reviewer read must occur after its single-flight review lease is acquired"
    end
    if reviewed_at && read_at && read_at > reviewed_at
      errors << "Director reviewer read must finish before disposition is recorded"
    end
  end

  expected_reviewer_reads = []
  required_skills.each do |skill|
    next unless skill.is_a?(Hash)

    expected_reviewer_reads << [skill["path"].to_s, skill["sha256"].to_s]
    actual_skill_read = reviewer_reads.find do |row|
      row.is_a?(Hash) && row["path"].to_s == skill["path"].to_s && row["sha256"].to_s == skill["sha256"].to_s
    end
    if actual_skill_read && actual_skill_read["kind"].to_s != "skill"
      errors << "Director reviewer read must classify launch required skill as kind=skill: #{skill['path']}"
    end
    if actual_skill_read && actual_skill_read["revision"].to_s != skill["revision"].to_s
      errors << "Director reviewer read must bind the exact launch skill revision: #{skill['path']}"
    end
    Array(skill["linked_reads"]).each do |row|
      next unless row.is_a?(Hash)

      expected_reviewer_reads << [row["path"].to_s, row["sha256"].to_s]
    end
  end
  requirements.each do |requirement|
    next unless requirement.is_a?(Hash)
    next unless requirement["director_semantic_review_required"] == true
    next unless %w[skill policy contract schema].include?(requirement["category"].to_s)
    next unless requirement["source_binding"].is_a?(Hash)

    expected_reviewer_reads << [
      requirement.dig("source_binding", "path").to_s,
      requirement.dig("source_binding", "sha256").to_s
    ]
  end
  expected_reviewer_reads.uniq!
  unless reviewer_read_pairs.sort == expected_reviewer_reads.sort
    errors << "Director reviewer read closure must exact-cover required skills, linked modules, and semantically reviewed skill/policy/contract/schema sources"
  end

  mechanical_receipt_sha = runtime_return.is_a?(Hash) ? runtime_return.dig("mechanical_compliance_receipt", "receipt_sha256").to_s : ""
  unless director_review["mechanical_receipt_sha256"].to_s == mechanical_receipt_sha
    errors << "Director review must bind the exact worker mechanical compliance receipt"
  end

  requirement_results = Array(director_review["requirement_results"])
  reviewed_requirement_ids = hash_values(requirement_results, "requirement_id")
  duplicate_values(reviewed_requirement_ids).each { |value| errors << "duplicate or blank Director requirement result id: #{value.inspect}" }
  unless reviewed_requirement_ids.sort == requirement_ids.sort
    errors << "Director requirement results must exact-cover launch.requirement_manifest requirement ids"
  end
  requirement_results.each_with_index do |row, index|
    next unless row.is_a?(Hash)

    requirement = requirements.find { |candidate| candidate.is_a?(Hash) && candidate["requirement_id"].to_s == row["requirement_id"].to_s }
    if requirement && requirement["required"] == true && row["result"].to_s == "not_applicable"
      errors << "required Director requirement result cannot be not_applicable: #{row['requirement_id']}"
    end
    if %w[pass hold fail].include?(row["result"].to_s) && row["evidence_sha256"].to_s.empty?
      errors << "closed director_review.requirement_results[#{index}].evidence_sha256 must not be null"
      next
    end
    next if row["evidence_sha256"].nil?

    file_binding(
      errors,
      "director_review.requirement_results[#{index}].evidence",
      {"path" => row["evidence_locator"], "sha256" => row["evidence_sha256"]}
    )
  end

  reviewed_pairs = binding_pairs(director_review["reviewed_outputs"])
  returned_pairs = runtime_return.is_a?(Hash) ? binding_pairs(runtime_return["outputs"]) : []
  if output_rule
    returned_rows = runtime_return.is_a?(Hash) ? exact_rows(runtime_return["outputs"]) : []
    errors << "director review must exact-copy every returned v18 output and its ownership/bindings" unless exact_rows(director_review["reviewed_outputs"]) == returned_rows
  else
    errors << "director review must bind every returned output path and SHA-256" unless reviewed_pairs == returned_pairs
  end
  Array(director_review["reviewed_outputs"]).each_with_index do |row, index|
    file_binding(errors, "director_review.reviewed_outputs[#{index}]", row)
  end
  rubric_results = Array(director_review["rubric_results"])
  criterion_ids = hash_values(rubric_results, "criterion")
  duplicate_values(criterion_ids).each { |value| errors << "duplicate or blank director review criterion: #{value.inspect}" }
  required_criteria = (BASE_REVIEW_CRITERIA + (output_rule ? output_rule.fetch(:review_criteria) : [])).uniq
  unless criterion_ids.sort == required_criteria.sort
    errors << "director review for output_kind=#{output_kind} requires exact rubric criteria #{required_criteria.join(', ')}"
  end
  if director_review["disposition"].to_s == "accept"
    if rubric_results.any? { |row| row.is_a?(Hash) && row["result"].to_s != "pass" }
      errors << "director disposition accept requires every rubric result to pass"
    end
    if requirement_results.any? { |row| row.is_a?(Hash) && row["result"].to_s != "pass" }
      errors << "director disposition accept requires every requirement result to pass"
    end
    if runtime_return.is_a?(Hash) && runtime_return.dig("mechanical_compliance_receipt", "all_required_checks_pass") != true
      errors << "director disposition accept requires the mechanical compliance receipt to pass"
    end
    required_claims = runtime_return.is_a?(Hash) ? Array(runtime_return["worker_fulfillment_claims"]) : []
    unfulfilled_required_claims = required_claims.select do |claim|
      next false unless claim.is_a?(Hash)

      requirement = requirements.find { |row| row.is_a?(Hash) && row["requirement_id"].to_s == claim["requirement_id"].to_s }
      requirement && requirement["required"] == true && claim["disposition"].to_s != "applied"
    end
    errors << "director disposition accept requires every required worker claim to be applied" unless unfulfilled_required_claims.empty?
  end
  correction = director_review["correction"]
  if director_review["disposition"].to_s == "accept"
    errors << "accepted review cannot carry a correction unit" unless correction.nil?
  elsif correction.is_a?(Hash)
    Array(correction["evidence"]).each_with_index do |row, index|
      next unless row.is_a?(Hash) && !row["source_sha256"].nil?

      label = "director_review.correction.evidence[#{index}]"
      _path, relative = file_binding(errors, label, {"path" => row["locator"], "sha256" => row["source_sha256"]})
      case row["kind"].to_s
      when "returned_output"
        errors << "#{label} must point to one returned output" unless binding_pairs(runtime_return["outputs"]).include?([relative, row["source_sha256"].to_s])
      when "bound_source"
        errors << "#{label} must point to one launch source" unless binding_pairs(launch["sources"]).include?([relative, row["source_sha256"].to_s])
      end
    end
    Array(correction["invalidated_outputs"]).each_with_index do |row, index|
      file_binding(errors, "director_review.correction.invalidated_outputs[#{index}]", row)
    end
    invalidated_rows = exact_rows(correction["invalidated_outputs"])
    returned_rows = runtime_return.is_a?(Hash) ? exact_rows(runtime_return["outputs"]) : []
    unless invalidated_rows.all? { |row| returned_rows.include?(row) }
      errors << "director correction invalidated_outputs must exact-copy only outputs from the current return"
    end
    if %w[same_session_new_attempt new_session_new_lineage].include?(correction["retry_route"].to_s) && invalidated_rows.empty?
      errors << "a direct correction retry requires at least one exact invalidated output"
    end
    if correction["retry_route"].to_s == "same_session_new_attempt" && lineage["session_id"].to_s.empty?
      errors << "same-session retry requires a bound lineage session_id"
    end
    if submission_number >= 3 && %w[same_session_new_attempt new_session_new_lineage].include?(correction["retry_route"].to_s)
      errors << "review submission 3 is the final allowed submission; another child retry is forbidden and the route must be upstream_owner or hold"
    end
  else
    errors << "patch, reject, or hold review requires a correction unit"
  end
end

promotion = document["promotion"]
if promotion.is_a?(Hash)
  errors << "final lifecycle event timestamp must equal promotion.decided_at" unless event_by_state.dig(current_state, "at").to_s == promotion["decided_at"].to_s
  errors << "promotion decision must equal lifecycle current_state" unless promotion["decision"].to_s == current_state
  errors << "promotion requires the Director review queue to be released" unless review_control["queue_state"].to_s == "released" && promotion["queue_release_verified"] == true
  review_released_at = timestamp_value(errors, "review_control.review_lease.released_at", review_control.dig("review_lease", "released_at"))
  promotion_decided_at = timestamp_value(errors, "promotion.decided_at", promotion["decided_at"])
  promotion_lease = review_control["promotion_lease"].is_a?(Hash) ? review_control["promotion_lease"] : {}
  errors << "promotion must bind the active Overall promotion lease id" unless promotion["promotion_lease_id"].to_s == promotion_lease["lease_id"].to_s
  errors << "Overall promotion lease owner must equal launch promotion_owner" unless promotion_lease["overall_owner"].to_s == authority["promotion_owner"].to_s
  promotion_acquired_at = timestamp_value(errors, "review_control.promotion_lease.acquired_at", promotion_lease["acquired_at"])
  promotion_released_at = timestamp_value(errors, "review_control.promotion_lease.released_at", promotion_lease["released_at"])
  if review_released_at && promotion_acquired_at && promotion_acquired_at < review_released_at
    errors << "Overall promotion lease cannot be acquired before Director disposition and review lease release"
  end
  if promotion_acquired_at && promotion_decided_at && promotion_decided_at < promotion_acquired_at
    errors << "Overall promotion cannot be decided before its global single-flight lease is acquired"
  end
  if promotion_decided_at && promotion_released_at && promotion_released_at < promotion_decided_at
    errors << "Overall promotion lease cannot release before the promotion or hold decision is recorded"
  end
  baseline_refresh_basis = {
    "dispatch_id" => dispatch_id,
    "review_lease_id" => raw_document.is_a?(Hash) ? raw_document.dig("director_review", "review_lease_id") : nil,
    "promotion_lease_id" => raw_promotion["promotion_lease_id"],
    "decision" => raw_promotion["decision"],
    "approved_working_outputs" => raw_promotion["approved_working_outputs"],
    "canonical_artifacts" => raw_promotion["canonical_artifacts"],
    "decided_at" => raw_promotion["decided_at"]
  }
  unless raw_promotion["baseline_refresh_evidence_sha256"].to_s == structured_sha256(baseline_refresh_basis)
    errors << "promotion baseline refresh evidence SHA-256 is stale"
  end
  promoter = promotion["promoter"].is_a?(Hash) ? promotion["promoter"] : {}
  errors << "promotion promoter must equal launch authority promotion_owner" unless promoter["owner"].to_s == authority["promotion_owner"].to_s
  errors << "promotion promoter role must be overall_director" unless promoter["role"].to_s == "overall_director"

  approved_working_outputs = Array(promotion["approved_working_outputs"])
  approved_working_outputs.each_with_index do |row, index|
    file_binding(errors, "promotion.approved_working_outputs[#{index}]", row)
  end
  canonical_artifacts = Array(promotion["canonical_artifacts"])
  canonical_paths = hash_values(canonical_artifacts, "path")
  duplicate_values(canonical_paths).each { |value| errors << "duplicate or blank canonical artifact path: #{value.inspect}" }
  canonical_artifacts.each_with_index { |row, index| file_binding(errors, "promotion.canonical_artifacts[#{index}]", row) }
  if current_state == "promoted"
    errors << "promoted dispatch requires director disposition accept" unless director_review.is_a?(Hash) && director_review["disposition"].to_s == "accept"
    errors << "promoted dispatch must bind at least one canonical artifact" if canonical_artifacts.empty?
    if output_rule
      errors << "v18 promotion mode must be coordinator_exact_copy" unless promotion["mode"].to_s == "coordinator_exact_copy"
      errors << "v18 assigned worker canonical_write authority must remain forbidden" unless authority["canonical_write"].to_s == "forbidden"
      errors << "v18 promotion must preserve a separate Overall approved_at timestamp" if promotion["approved_at"].to_s.empty?
      begin
        reviewed_time = DateTime.iso8601(director_review["reviewed_at"].to_s)
        approved_time = DateTime.iso8601(promotion["approved_at"].to_s)
        copied_time = DateTime.iso8601(promotion["copy_completed_at"].to_s)
        unless reviewed_time <= approved_time && approved_time <= copied_time
          errors << "v18 promotion timestamps must order director review <= Overall approval <= coordinator copy completion"
        end
      rescue ArgumentError
        errors << "v18 promotion reviewed_at, approved_at, and copy_completed_at must be ISO-8601 timestamps"
      end
      reviewed_rows = director_review.is_a?(Hash) ? exact_rows(director_review["reviewed_outputs"]) : []
      unless exact_rows(approved_working_outputs) == reviewed_rows
        errors << "v18 promotion approved_working_outputs must exact-copy every reviewed output and its ownership/bindings"
      end

      coordinator = promotion["coordinator"].is_a?(Hash) ? promotion["coordinator"] : {}
      errors << "v18 promotion coordinator role must be mechanical_coordinator" unless coordinator["role"].to_s == "mechanical_coordinator"
      errors << "v18 promotion requires a named mechanical coordinator" if coordinator["owner"].to_s.empty?
      errors << "v18 promotion copy_completed_at must equal promotion.decided_at" unless promotion["copy_completed_at"].to_s == promotion["decided_at"].to_s
      errors << "promoted lifecycle event actor must be the mechanical coordinator" unless event_by_state.dig("promoted", "actor").to_s == coordinator["owner"].to_s

      approved_by_source = approved_working_outputs.each_with_object({}) do |row, result|
        next unless row.is_a?(Hash)

        result[[row["path"].to_s, row["sha256"].to_s]] = row
      end
      consumed_sources = []
      canonical_artifacts.each_with_index do |row, index|
        next unless row.is_a?(Hash)

        label = "promotion.canonical_artifacts[#{index}]"
        source_key = [row["source_output_path"].to_s, row["source_output_sha256"].to_s]
        source = approved_by_source[source_key]
        if source.nil?
          errors << "#{label} must bind one exact approved working output through source_output_path/source_output_sha256"
          next
        end
        consumed_sources << source_key
        errors << "#{label} must preserve exact approved output bytes" unless row["sha256"].to_s == source["sha256"].to_s
        %w[output_kind logical_owner decision_epoch bindings].each do |field|
          unless canonicalize(row[field]) == canonicalize(source[field])
            errors << "#{label}.#{field} must exact-copy its approved working output"
          end
        end
        errors << "#{label} must use a canonical path distinct from its working output" if row["path"].to_s == source["path"].to_s
        errors << "#{label} canonical path must stay inside the declared run" unless row["path"].to_s.start_with?("#{run}/")
        errors << "#{label} canonical path cannot be a worker expected_path" if expected_paths.include?(row["path"].to_s)
      end
      duplicate_values(consumed_sources.map { |pair| pair.join("|") }).each do |value|
        errors << "v18 promotion repeats or blanks an approved working output lineage: #{value.inspect}"
      end
      unless consumed_sources.sort == approved_by_source.keys.sort
        errors << "v18 canonical_artifacts must exact-cover approved_working_outputs one-to-one"
      end
      if output_kind == "founder_briefing_projection"
        errors << "founder_briefing_projection promotion must contain exactly one immutable history artifact" unless canonical_artifacts.length == 1
        source = approved_working_outputs.first
        source_document = source.is_a?(Hash) && ROOT.join(source["path"].to_s).file? ? load_document(ROOT.join(source["path"].to_s)) : nil
        source_set_sha256 = source_document.is_a?(Hash) ? source_document["source_set_sha256"].to_s : ""
        expected_history_path = "#{run}/work/founder-briefing/history/#{source_set_sha256}.json"
        history = canonical_artifacts.first
        unless history.is_a?(Hash) && history["path"].to_s == expected_history_path
          errors << "founder_briefing_projection promotion must exact-copy to immutable history/<source_set_sha256>.json"
        end
        if canonical_artifacts.any? { |row| row.is_a?(Hash) && row["path"].to_s.end_with?("/work/founder-briefing/current.json") }
          errors << "founder_briefing_projection current.json is a transport read model, not a promotion artifact"
        end
      end
    else
      errors << "bounded_artifact promotion mode must be direct_canonical_promotion" unless promotion["mode"].to_s == "direct_canonical_promotion"
      errors << "promoted dispatch requires bounded canonical-write authority" unless authority["canonical_write"].to_s == "bounded_to_expected_paths"
      errors << "direct promotion approved_at must equal promotion.decided_at" unless promotion["approved_at"].to_s == promotion["decided_at"].to_s
      errors << "direct promotion must not declare a mechanical coordinator" unless promotion["coordinator"].nil?
      errors << "direct promotion must not declare copy_completed_at" unless promotion["copy_completed_at"].nil?
      errors << "promoted lifecycle event actor must be the Overall promoter" unless event_by_state.dig("promoted", "actor").to_s == promoter["owner"].to_s
      reviewed_pairs = director_review.is_a?(Hash) ? binding_pairs(director_review["reviewed_outputs"]) : []
      errors << "direct promotion approved_working_outputs must exact-copy reviewed outputs" unless binding_pairs(approved_working_outputs) == reviewed_pairs
      unreviewed = binding_pairs(canonical_artifacts) - reviewed_pairs
      errors << "promotion contains artifacts not bound by director review: #{unreviewed.map(&:first).join(', ')}" unless unreviewed.empty?
    end
  elsif current_state == "hold"
    errors << "hold promotion mode must be held_without_promotion" unless promotion["mode"].to_s == "held_without_promotion"
    errors << "hold promotion cannot declare approved_at" unless promotion["approved_at"].nil?
    errors << "hold dispatch cannot approve working outputs" unless approved_working_outputs.empty?
    errors << "hold dispatch cannot declare a mechanical coordinator" unless promotion["coordinator"].nil?
    errors << "hold dispatch cannot declare copy_completed_at" unless promotion["copy_completed_at"].nil?
    errors << "hold dispatch cannot promote canonical artifacts" unless canonical_artifacts.empty?
    errors << "hold lifecycle event actor must be the Overall promoter" unless event_by_state.dig("hold", "actor").to_s == promoter["owner"].to_s
  end
end

if options[:require_promoted] && current_state != "promoted"
  errors << "department dispatch must be promoted for this active gate (current_state=#{current_state.empty? ? 'unknown' : current_state})"
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "dispatch" => dispatch_relative,
  "dispatch_id" => dispatch_id,
  "run" => run,
  "review_cycle_id" => review_submission["review_cycle_id"].to_s,
  "review_submission_number" => submission_number,
  "review_submission_maximum" => review_submission["maximum_submissions"].to_i,
  "transport_refresh_receipt" => transport_refresh_receipt ? IdolDepartmentTransportRefresh.relative_path(options[:transport_refresh]) : nil,
  "transport_refresh_consumed_goal" => false,
  "transport_refresh_consumed_review_submission" => false,
  "lifecycle_state" => current_state,
  "stage_id" => scope["stage_id"].to_s,
  "output_kind" => output_kind,
  "promotion_mode" => promotion.is_a?(Hash) ? promotion["mode"].to_s : nil,
  "outputs" => runtime_return.is_a?(Hash) ? binding_pairs(runtime_return["outputs"]).map(&:first) : [],
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: #{dispatch_relative} is a valid #{current_state} department dispatch"
else
  errors.each { |error| warn "ERROR: #{error}" }
end

exit(errors.empty? ? 0 : 1)
