#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"

require_relative "lib/idol_graph_output_manifest_contract"
require_relative "lib/idol_graph_goal_evidence_contract"
require_relative "lib/idol_graph_provider_binding_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
LINEAGE_SCHEMA = ROOT.join("schemas", "graph-director-lineage.schema.json")
DISPATCH_SCHEMA = ROOT.join("schemas", "graph-department-dispatch.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
CONTEXTUAL_JUDGMENT_VALIDATOR = ROOT.join("scripts", "validate_graph_contextual_judgment.rb")
COHORT_MAP_VALIDATOR = ROOT.join("scripts", "validate_graph_section_cohort_map.rb")

DIRECTOR_LANE_ROLES = %w[overall_director planning_cdd section_cluster_cdd edit_director].freeze
ACTIVE_WRITER_STATES = %w[active_single_writer reactivated_single_writer].freeze
GOAL_BY_PROVIDER = {
  "grok" => %w[grok_goal_completed_admission complete goal_completed],
  "cursor" => %w[cursor_external_goal_runtime_receipt success cli_terminal_success]
}.freeze
DISPATCH_LEGAL_NEXT = {
  "prepared" => %w[launched hold],
  "launched" => %w[returned hold],
  "returned" => %w[reviewed hold],
  "reviewed" => %w[hold],
  "hold" => []
}.freeze
P3_LANE = /\Aplanning_p3_c([1-9][0-9]*)\z/
V_LANE = /\Asection_cluster_v_c([1-9][0-9]*)\z/

options = {json: false, root: ROOT, validation_mode: "active_promotion"}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_graph_director_lineage.rb [--json] [--root PATH] [--validation-mode active_promotion|historical_audit|test_boundary] DOCUMENT"
  parser.on("--json") { options[:json] = true }
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--validation-mode MODE", %w[active_promotion historical_audit test_boundary]) do |value|
    options[:validation_mode] = value
  end
end.parse!

argument = ARGV.shift
if argument.to_s.empty? || !ARGV.empty?
  warn "graph director lineage or graph department dispatch path is required"
  exit 2
end

def document_path(root, raw)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def repo_path(root, raw)
  path = document_path(root, raw)
  relative = path.relative_path_from(root).to_s
  raise ArgumentError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")

  [path, relative]
end

def load_document(path)
  text = path.read
  value = path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, aliases: true)
  value.is_a?(Hash) ? value : nil
rescue JSON::ParserError, Psych::Exception
  nil
end

def schema_errors(schema, path)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return [] if status.success?

  message = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
  message.empty? ? ["JSON Schema validation failed"] : [message]
end

def expected_goal(provider)
  GOAL_BY_PROVIDER[provider.to_s]
end

def validate_goal(root, errors, label, binding, goal, document = nil, validation_mode: "active_promotion")
  return unless binding.is_a?(Hash) && goal.is_a?(Hash)

  expected = expected_goal(binding["registered_provider"])
  actual = [goal["goal_semantics"], goal["goal_terminal_state"], goal["goal_last_event"]]
  unless expected && actual == expected
    errors << "#{label} Goal evidence does not match registered provider #{binding['registered_provider']}"
  end
  %w[goal_text_sha256 goal_terminal_event_sha256].each do |field|
    errors << "#{label} #{field} is missing" if goal[field].to_s.strip.empty?
  end
  errors << "#{label} native_goal_id is missing" if goal["native_goal_id"].to_s.strip.empty?
  begin
    IdolGraphGoalEvidenceContract.verify!(
      root: root,
      provider_binding: binding,
      goal_evidence: goal,
      validation_mode: validation_mode
    )
  rescue IdolGraphGoalEvidenceContract::ContractError => e
    errors << "#{label} Goal terminal event failed exact verification [#{e.code}]: #{e.message}"
  end
  if goal["goal_last_event"].to_s == "goal_completed" || goal["goal_semantics"].to_s == "grok_goal_completed_admission"
    unless goal["goal_completed_closes"].to_s.empty? || goal["goal_completed_closes"].to_s == "successor_admission_only"
      errors << "#{label} goal_completed closes successor admission only and does not imply IDOL assignment PASS"
    end
    if goal["idol_assignment_pass"] == true || (document.is_a?(Hash) && document["assignment_pass"] == true)
      errors << "#{label} goal_completed closes successor admission only and does not imply IDOL assignment PASS"
    end
  end
end

def validate_dispatch_lifecycle(errors, document)
  state = document["lifecycle_state"].to_s
  expected = DISPATCH_LEGAL_NEXT[state]
  unless expected
    errors << "dispatch lifecycle_state is not a legal Goal/assignment state"
    return
  end
  actual = Array(document["legal_next"]).map(&:to_s)
  errors << "dispatch legal_next does not match lifecycle_state #{state}" unless actual == expected
  from = document["lifecycle_from"]
  return if from.nil?

  allowed = DISPATCH_LEGAL_NEXT[from.to_s]
  unless allowed && (allowed.include?(state) || from.to_s == state)
    errors << "illegal lifecycle transition from #{from} to #{state}"
  end
end

def validate_provider(root, errors, label, binding, studio_role:)
  return errors << "#{label} provider_binding is missing" unless binding.is_a?(Hash)

  if DIRECTOR_LANE_ROLES.include?(studio_role.to_s) && binding["logical_profile_alias"].to_s != "frontier_director"
    errors << "#{label} director lane must resolve frontier_director with no fallback"
  end

  IdolGraphProviderBindingContract.resolve!(
    root: root,
    binding: binding,
    studio_role: studio_role
  )
rescue IdolGraphProviderBindingContract::ContractError => e
  errors << "#{label} provider binding failed exact resolution [#{e.code}]: #{e.message}"
end

def validate_output_manifest(root, errors, document)
  pointer = document["output_manifest"]
  required = %w[returned reviewed].include?(document["lifecycle_state"].to_s)
  if pointer.nil?
    errors << "returned/reviewed dispatch requires a non-null output_manifest" if required
    return
  end

  IdolGraphOutputManifestContract.verify!(root: root, pointer: pointer, dispatch: document)
rescue IdolGraphOutputManifestContract::ContractError => e
  errors << "dispatch output_manifest failed exact verification [#{e.code}]: #{e.message}"
end

def validate_recipient(errors, label, recipient)
  return errors << "#{label} return recipient is missing" unless recipient.is_a?(Hash)

  errors << "#{label} return recipient owner is missing" if recipient["owner"].to_s.strip.empty?
  errors << "#{label} return recipient role is missing" if recipient["role"].to_s.strip.empty?
  errors << "#{label} return recipient return_route is missing" if recipient["return_route"].to_s.strip.empty?
end

def active_writer_sessions(sessions)
  Array(sessions).select { |session| session.is_a?(Hash) && ACTIVE_WRITER_STATES.include?(session["state"].to_s) }
end

def validate_succession_state(errors, label, sessions, succession, lane_active_writer_id)
  return errors << "#{label} succession is missing" unless succession.is_a?(Hash)

  primary = sessions.find { |session| session["generation"].to_s == "primary" }
  successor = sessions.find { |session| session["generation"].to_s == "successor" }
  source_id = succession["source_session_id"].to_s
  successor_id = succession["successor_session_id"]
  active_id = lane_active_writer_id.to_s
  authority = succession["authority_state"].to_s

  errors << "#{label} succession source_session_id must identify the primary" unless primary && source_id == primary["session_id"].to_s
  if successor
    unless successor_id.to_s == successor["session_id"].to_s
      errors << "#{label} successor_session_id must identify the only successor"
    end
  elsif !successor_id.nil?
    errors << "#{label} successor_session_id must be null when no successor exists"
  end

  case authority
  when "primary_active"
    errors << "#{label} primary_active may not include a successor" if successor
    errors << "#{label} primary must be the only active writer" unless primary && ACTIVE_WRITER_STATES.include?(primary["state"].to_s) && active_id == primary["session_id"].to_s
  when "successor_preflight"
    errors << "#{label} successor_preflight requires a successor" unless successor
    errors << "#{label} successor must stay zero-turn read-only before CAS" unless successor && successor["state"].to_s == "zero_turn_read_only_preflight"
    errors << "#{label} primary must remain the only active writer before CAS" unless primary && ACTIVE_WRITER_STATES.include?(primary["state"].to_s) && active_id == primary["session_id"].to_s
  when "successor_admitted"
    errors << "#{label} successor_admitted requires a successor" unless successor
    errors << "#{label} admitted successor must stay read-only before CAS" unless successor && successor["state"].to_s == "admitted_read_only"
    errors << "#{label} primary must remain the only active writer before CAS" unless primary && ACTIVE_WRITER_STATES.include?(primary["state"].to_s) && active_id == primary["session_id"].to_s
  when "successor_active"
    errors << "#{label} successor_active requires a successor" unless successor
    errors << "#{label} successor must be the only active writer after CAS" unless successor && ACTIVE_WRITER_STATES.include?(successor["state"].to_s) && active_id == successor["session_id"].to_s
    errors << "#{label} primary must be read-only after successor CAS" if primary && ACTIVE_WRITER_STATES.include?(primary["state"].to_s)
  when "rolled_back"
    errors << "#{label} rollback requires the primary as the only active writer" unless primary && primary["state"].to_s == "reactivated_single_writer" && active_id == primary["session_id"].to_s
    errors << "#{label} rolled-back successor must be read-only" if successor && ACTIVE_WRITER_STATES.include?(successor["state"].to_s)
  when "read_only_retired"
    errors << "#{label} read_only_retired lane cannot have an active writer" unless active_writer_sessions(sessions).empty?
  end
end

def lane_index(lane_id)
  text = lane_id.to_s
  if (match = text.match(P3_LANE))
    return ["p3", match[1].to_i]
  end
  if (match = text.match(V_LANE))
    return ["v", match[1].to_i]
  end

  [text, nil]
end

def write_scope_keys(lane)
  Array(lane["write_scopes"]).each_with_object([]) do |scope, keys|
    next unless scope.is_a?(Hash)

    field = scope["field_id"].to_s
    if scope["scope_kind"].to_s == "whole_film"
      keys << [field, "WHOLE_FILM"]
    else
      Array(scope["section_ids"]).each { |section_id| keys << [field, section_id.to_s] }
    end
  end
end

def validate_pointer(root, errors, label, pointer)
  return unless pointer.is_a?(Hash)

  path, _relative = repo_path(root, pointer["path"])
  unless path.file?
    errors << "#{label} path is missing: #{pointer['path']}"
    return
  end
  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} SHA-256 is stale: #{pointer['path']}" unless actual == pointer["sha256"].to_s
rescue ArgumentError => e
  errors << "#{label} #{e.message}"
end

def validate_graph_contextual_judgment_binding(root, errors, document, validation_mode: "active_promotion")
  binding = document["contextual_judgment"]
  required = document["lifecycle_state"].to_s == "reviewed"
  if !binding.is_a?(Hash)
    errors << "reviewed Graph dispatch requires a contextual_judgment binding" if required
    return
  end

  validate_pointer(root, errors, "Graph contextual judgment", binding)
  profile_id = document["judgment_profile_id"].to_s
  if profile_id.empty? || binding["profile_id"].to_s != profile_id
    errors << "Graph contextual judgment profile must exact-bind judgment_profile_id"
  end
  path, _relative = repo_path(root, binding["path"])
  return unless path.file?

  judgment = load_document(path)
  unless judgment.is_a?(Hash) && judgment["artifact_type"].to_s == "graph_contextual_judgment"
    errors << "contextual_judgment binding does not name graph_contextual_judgment"
    return
  end
  errors << "Graph contextual judgment document profile differs from dispatch" unless judgment["profile_id"].to_s == profile_id
  unless judgment.dig("execution_binding", "assignment_id").to_s == document["dispatch_id"].to_s
    errors << "Graph contextual judgment assignment differs from dispatch"
  end
  unless judgment.dig("execution_binding", "output_manifest").to_h.slice("path", "sha256") == document["output_manifest"].to_h.slice("path", "sha256")
    errors << "Graph contextual judgment output manifest differs from dispatch"
  end
  writer_session = document.dig("output_writer", "session_id").to_s
  unless writer_session.empty? || judgment.dig("execution_binding", "author_session_id").to_s == writer_session
    errors << "Graph contextual judgment author session differs from dispatch output writer"
  end
  if required
    errors << "reviewed Graph dispatch requires eligible_for_director_review" unless judgment["decision"].to_s == "eligible_for_director_review"
    errors << "reviewed Graph dispatch requires director_review next edge" unless judgment["next_edge"].to_s == "director_review"
    unless judgment["status"].to_s == "ready_for_director_review"
      errors << "reviewed Graph dispatch requires ready_for_director_review judgment status"
    end
  end

  contextual_mode = validation_mode == "active_promotion" ? "active_promotion" : "historical_audit"
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    CONTEXTUAL_JUDGMENT_VALIDATOR.to_s,
    "--root", root.to_s,
    "--mode", contextual_mode,
    path.to_s,
    chdir: ROOT.to_s
  )
  unless status.success?
    errors << "Graph contextual judgment failed active validation: #{[stderr, stdout].join(' ').strip}"
  end
rescue ArgumentError => e
  errors << "Graph contextual judgment #{e.message}"
end

def validate_dispatch_semantics(root, errors, document, validation_mode: "active_promotion")
  validate_provider(root, errors, "dispatch", document["provider_binding"], studio_role: document["logical_role"])
  validate_goal(root, errors, "dispatch", document["provider_binding"], document["goal_evidence"], document, validation_mode: validation_mode)
  validate_dispatch_lifecycle(errors, document)
  validate_output_manifest(root, errors, document)
  validate_graph_contextual_judgment_binding(root, errors, document, validation_mode: validation_mode)
  validate_recipient(errors, "dispatch", document["return_recipient"])

  writer = document["output_writer"]
  errors << "dispatch must have exactly one output writer" unless writer.is_a?(Hash) && writer["owner"].to_s.strip != "" && writer["role"].to_s.strip != ""
  reviewer = document["reviewer"]
  errors << "dispatch must have exactly one reviewer" unless reviewer.is_a?(Hash) && reviewer["owner"].to_s.strip != "" && reviewer["role"].to_s.strip != ""

  role = document["logical_role"].to_s
  case role
  when "section_image_motion_worker"
    errors << "section output writer role must be section_image_motion_worker" unless writer.is_a?(Hash) && writer["role"].to_s == "section_image_motion_worker"
    errors << "section worker reviewer must be the cohort CDD" unless reviewer.is_a?(Hash) && reviewer["role"].to_s == "creative_development_director"
    errors << "section worker return recipient must be the cohort CDD" unless document.dig("return_recipient", "role").to_s == "creative_development_director"
    errors << "section worker dispatch requires a section_cohort_id" if document["section_cohort_id"].nil?
    errors << "section worker reviewer lane must equal the dispatch lane" unless reviewer.is_a?(Hash) && reviewer["lane_id"].to_s == document["lane_id"].to_s
    unless reviewer.is_a?(Hash) && reviewer["owner"].to_s == document.dig("return_recipient", "owner").to_s
      errors << "section worker reviewer owner must equal the return recipient owner"
    end
    unless document.dig("return_recipient", "return_route").to_s == "cohort_cdd_exact_byte_review"
      errors << "section worker return route must be cohort_cdd_exact_byte_review"
    end
    lane_match = document["lane_id"].to_s.match(V_LANE)
    unless lane_match && document["section_cohort_id"].to_s == "C#{lane_match[1]}"
      errors << "section worker V-Ci lane suffix must match section_cohort_id C{N}"
    end
    checkpoint = document["review_checkpoint"].to_s
    errors << "section worker review checkpoint must be 02b_pixel or 03v_playback" unless %w[02b_pixel 03v_playback].include?(checkpoint)
  when "department_worker"
    errors << "department worker reviewer must be a Director" unless reviewer.is_a?(Hash) && %w[overall_director planning_cdd_p1 creative_development_director edit_director].include?(reviewer["role"].to_s)
    errors << "department worker return recipient is missing" if document.dig("return_recipient", "role").to_s.strip.empty?
  when "planning_cdd"
    lane_id = document["lane_id"].to_s
    if lane_id == "planning_p1"
      errors << "Planning P1 dispatch return recipient must be overall_director" unless document.dig("return_recipient", "role").to_s == "overall_director"
      errors << "Planning P1 dispatch reviewer must be overall_director" unless reviewer.is_a?(Hash) && reviewer["role"].to_s == "overall_director"
    elsif lane_id == "planning_p2" || lane_id.match?(P3_LANE)
      errors << "Planning P2/P3 dispatch return recipient must be planning_cdd_p1" unless document.dig("return_recipient", "role").to_s == "planning_cdd_p1"
      errors << "Planning P2/P3 dispatch reviewer must be planning_cdd_p1" unless reviewer.is_a?(Hash) && reviewer["role"].to_s == "planning_cdd_p1"
      errors << "Planning P2/P3 dispatch reviewer lane must be planning_p1" unless reviewer.is_a?(Hash) && reviewer["lane_id"].to_s == "planning_p1"
      errors << "Planning P2/P3 dispatch must use planning_cdd_p1_exact_link" unless document.dig("return_recipient", "return_route").to_s == "planning_cdd_p1_exact_link"
    end
  when "section_cluster_cdd"
    errors << "CDD dispatch return recipient must be overall_director" unless document.dig("return_recipient", "role").to_s == "overall_director"
    errors << "CDD dispatch reviewer must be overall_director" unless reviewer.is_a?(Hash) && reviewer["role"].to_s == "overall_director"
  when "edit_director"
    errors << "Edit Director return recipient must be overall_director" unless document.dig("return_recipient", "role").to_s == "overall_director"
  end
end

def validate_lane(root, errors, lane, phase, validation_mode: "active_promotion")
  lane_id = lane["lane_id"].to_s
  label = "lane #{lane_id}"
  sessions = Array(lane["physical_sessions"])
  errors << "#{label} exceeds primary+successor maximum two physical sessions" if sessions.length > 2
  generations = sessions.map { |session| session["generation"].to_s }
  errors << "#{label} primary session is required" unless generations.include?("primary")
  errors << "#{label} duplicate physical generation" unless generations.uniq.length == generations.length
  errors << "third Director session is forbidden on #{label}" if sessions.length > 2

  writers = active_writer_sessions(sessions)
  if lane["succession"].is_a?(Hash) && lane.dig("succession", "authority_state").to_s == "read_only_retired"
    errors << "#{label} read_only_retired lane cannot have an active writer" unless writers.empty?
  else
    errors << "#{label} must have exactly one active writer" unless writers.length == 1
  end
  if writers.length == 1 && writers[0]["session_id"].to_s != lane["active_writer_session_id"].to_s
    errors << "#{label} active_writer_session_id does not match the active session"
  end
  if lane["succession"].is_a?(Hash) && lane.dig("succession", "active_writer_session_id").to_s != lane["active_writer_session_id"].to_s
    errors << "#{label} succession active writer does not match the lane active writer"
  end
  validate_succession_state(errors, label, sessions, lane["succession"], lane["active_writer_session_id"])

  kind, index = lane_index(lane_id)
  case kind
  when "planning_p1"
    errors << "#{label} must use story_audience_lead" unless lane["planning_cdd_mode"].to_s == "story_audience_lead"
    errors << "#{label} must not bind a section_cohort_id" unless lane["section_cohort_id"].nil?
    errors << "#{label} must be the planning integration writer" unless lane["integration_writer"] == true
    errors << "#{label} logical_role must be planning_cdd" unless lane["logical_role"].to_s == "planning_cdd"
  when "planning_p2"
    errors << "#{label} must use visual_reference_development" unless lane["planning_cdd_mode"].to_s == "visual_reference_development"
    errors << "#{label} must not bind a section_cohort_id" unless lane["section_cohort_id"].nil?
    errors << "#{label} must not be the planning integration writer" unless lane["integration_writer"] == false
    errors << "#{label} logical_role must be planning_cdd" unless lane["logical_role"].to_s == "planning_cdd"
  when "p3"
    errors << "#{label} must use section_kinetic_architecture" unless lane["planning_cdd_mode"].to_s == "section_kinetic_architecture"
    errors << "#{label} requires section_cohort_id C#{index}" unless lane["section_cohort_id"].to_s == "C#{index}"
    errors << "#{label} must not be the planning integration writer" unless lane["integration_writer"] == false
    errors << "#{label} logical_role must be planning_cdd" unless lane["logical_role"].to_s == "planning_cdd"
  when "v"
    errors << "#{label} planning_cdd_mode must be null" unless lane["planning_cdd_mode"].nil?
    errors << "#{label} requires section_cohort_id C#{index}" unless lane["section_cohort_id"].to_s == "C#{index}"
    errors << "#{label} must not be the planning integration writer" unless lane["integration_writer"] == false
    errors << "#{label} logical_role must be section_cluster_cdd" unless lane["logical_role"].to_s == "section_cluster_cdd"
  when "overall"
    errors << "#{label} logical_role must be overall_director" unless lane["logical_role"].to_s == "overall_director"
    errors << "#{label} must not be the planning integration writer" unless lane["integration_writer"] == false
  when "edit_director"
    errors << "#{label} logical_role must be edit_director" unless lane["logical_role"].to_s == "edit_director"
    errors << "#{label} must not be the planning integration writer" unless lane["integration_writer"] == false
  end

  if %w[g40_handoff production_active].include?(phase) && (kind.start_with?("planning") || kind == "p3")
    unless lane.dig("succession", "authority_state").to_s == "read_only_retired"
      errors << "#{label} must be read_only_retired after G-40"
    end
  end

  validate_provider(root, errors, label, lane["provider_binding"], studio_role: lane["logical_role"])
  validate_goal(root, errors, label, lane["provider_binding"], lane["goal_evidence"], lane, validation_mode: validation_mode)
  validate_recipient(errors, label, lane["return_recipient"])
  if kind == "overall"
    unless lane.dig("return_recipient", "role").to_s == "overall_director"
      errors << "#{label} Overall has no upstream Director recipient besides itself for Founder conversation closure"
    end
  elsif kind == "planning_p2" || kind == "p3"
    unless lane.dig("return_recipient", "role").to_s == "planning_cdd_p1"
      errors << "#{label} return recipient must be planning_cdd_p1"
    end
    unless lane.dig("return_recipient", "return_route").to_s == "planning_cdd_p1_exact_link"
      errors << "#{label} return route must be planning_cdd_p1_exact_link"
    end
  else
    unless lane.dig("return_recipient", "role").to_s == "overall_director"
      errors << "#{label} return recipient must be overall_director"
    end
  end
end

def validate_lane_carry_pointer(root, errors, lane)
  carry = lane["planning_to_production_carry"]
  return unless carry.is_a?(Hash)

  validate_pointer(root, errors, "lane #{lane['lane_id']} planning_handoff", carry["planning_handoff"])
end

def validate_p3_v_carry(errors, lanes, phase)
  p3 = lanes.select { |lane| lane["lane_id"].to_s.match?(P3_LANE) }
  v_lanes = lanes.select { |lane| lane["lane_id"].to_s.match?(V_LANE) }
  if phase == "planning_provisional"
    v_lanes.each do |lane|
      errors << "planning_provisional must not open production lane #{lane['lane_id']}"
    end
    return
  end

  p3_by_index = p3.each_with_object({}) do |lane, map|
    _kind, index = lane_index(lane["lane_id"])
    map[index] = lane
  end
  v_by_index = v_lanes.each_with_object({}) do |lane, map|
    _kind, index = lane_index(lane["lane_id"])
    map[index] = lane
  end
  (p3_by_index.keys | v_by_index.keys).each do |index|
    p3_lane = p3_by_index[index]
    v_lane = v_by_index[index]
    unless p3_lane && v_lane
      errors << "P3-Ci to V-Ci cohort carry is missing or inexact for C#{index}"
      next
    end
    carry = v_lane["planning_to_production_carry"]
    unless carry.is_a?(Hash) && carry["exact_carry"] == true
      errors << "P3-Ci to V-Ci cohort carry is missing or inexact for C#{index}"
      next
    end
    expected_p3 = "planning_p3_c#{index}"
    expected_v = "section_cluster_v_c#{index}"
    expected_cohort = "C#{index}"
    unless carry["planning_lane_id"].to_s == expected_p3 &&
           carry["production_lane_id"].to_s == expected_v &&
           carry["section_cohort_id"].to_s == expected_cohort &&
           p3_lane["section_cohort_id"].to_s == expected_cohort &&
           v_lane["section_cohort_id"].to_s == expected_cohort
      errors << "P3-Ci to V-Ci cohort carry is missing or inexact for C#{index}"
    end
  end
end

def validate_cohort_map_lineage_binding(root, errors, document)
  pointer = document["section_cohort_map"]
  return nil unless pointer.is_a?(Hash)

  path, _relative = repo_path(root, pointer["path"])
  return nil unless path.file?

  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    COHORT_MAP_VALIDATOR.to_s,
    "--root", root.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  unless status.success?
    message = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
    errors << "section cohort map failed active validation: #{message}"
  end

  map = load_document(path)
  return nil unless map.is_a?(Hash) && map["artifact_type"].to_s == "graph_section_cohort_map"

  errors << "section cohort map run does not match lineage run" unless map["run"].to_s == document["run"].to_s
  errors << "section cohort map phase does not match lineage phase" unless map["phase"].to_s == document["phase"].to_s
  lanes_by_id = Array(document["lanes"]).select { |lane| lane.is_a?(Hash) }.to_h { |lane| [lane["lane_id"].to_s, lane] }
  cohorts_by_id = Array(map["cohorts"]).select { |cohort| cohort.is_a?(Hash) }.to_h do |cohort|
    [cohort["section_cohort_id"].to_s, cohort]
  end
  cohorts_by_id.each_value do |cohort|
    lane_id = document["phase"].to_s == "planning_provisional" ? cohort["planning_lane_id"] : cohort["production_lane_id"]
    lane = lanes_by_id[lane_id.to_s]
    next unless lane.is_a?(Hash)

    reviewer = cohort["cdd_reviewer"]
    next unless reviewer.is_a?(Hash)

    unless reviewer["session_id"].to_s == lane["active_writer_session_id"].to_s
      errors << "cohort #{cohort['section_cohort_id']} CDD reviewer session does not match lineage active writer"
    end
    unless reviewer["logical_lineage_id"].to_s == lane["logical_lineage_id"].to_s
      errors << "cohort #{cohort['section_cohort_id']} CDD reviewer logical lineage does not match lineage"
    end
  end

  {"map" => map, "cohorts_by_id" => cohorts_by_id, "lanes_by_id" => lanes_by_id}
rescue ArgumentError => e
  errors << "section cohort map #{e.message}"
  nil
end

def validate_section_dispatch_reviewer_binding(errors, dispatch, cohort_contract)
  return unless dispatch["logical_role"].to_s == "section_image_motion_worker"
  return unless cohort_contract.is_a?(Hash)

  cohort = cohort_contract.fetch("cohorts_by_id")[dispatch["section_cohort_id"].to_s]
  unless cohort.is_a?(Hash)
    errors << "section worker dispatch cohort is absent from the bound section cohort map"
    return
  end
  lane = cohort_contract.fetch("lanes_by_id")[cohort["production_lane_id"].to_s]
  unless lane.is_a?(Hash)
    errors << "section worker dispatch cohort has no bound V-Ci lineage lane"
    return
  end
  reviewer = dispatch["reviewer"]
  cohort_reviewer = cohort["cdd_reviewer"]
  return unless reviewer.is_a?(Hash) && cohort_reviewer.is_a?(Hash)

  errors << "section worker dispatch run must exact-bind the lineage run" unless dispatch["run"].to_s == cohort_contract.fetch("map")["run"].to_s
  errors << "section worker dispatch V-Ci lane must exact-bind the cohort map" unless dispatch["lane_id"].to_s == cohort["production_lane_id"].to_s
  unless reviewer["owner"].to_s == cohort_reviewer["owner"].to_s
    errors << "section worker dispatch reviewer owner must exact-bind the cohort CDD owner"
  end
  unless reviewer["session_id"].to_s == cohort_reviewer["session_id"].to_s &&
         reviewer["session_id"].to_s == lane["active_writer_session_id"].to_s
    errors << "section worker dispatch reviewer session must exact-bind the cohort V-Ci active writer"
  end
  unless reviewer["logical_lineage_id"].to_s == cohort_reviewer["logical_lineage_id"].to_s &&
         reviewer["logical_lineage_id"].to_s == lane["logical_lineage_id"].to_s
    errors << "section worker dispatch reviewer logical lineage must exact-bind the cohort V-Ci lineage"
  end
end

def validate_required_phase_lanes(root, errors, document)
  phase = document["phase"].to_s
  lane_ids = Array(document["lanes"]).each_with_object([]) { |lane, ids| ids << lane["lane_id"].to_s if lane.is_a?(Hash) }
  errors << "#{phase} requires planning_p1" unless lane_ids.include?("planning_p1")
  errors << "#{phase} requires planning_p2" unless lane_ids.include?("planning_p2")

  expected_cohorts = []
  pointer = document["section_cohort_map"]
  if pointer.is_a?(Hash)
    begin
      map_path, _relative = repo_path(root, pointer["path"])
      map = load_document(map_path) if map_path.file?
      expected_cohorts = Array(map && map["cohorts"]).each_with_object([]) do |cohort, ids|
        ids << cohort["section_cohort_id"].to_s if cohort.is_a?(Hash) && cohort["section_cohort_id"].to_s.match?(/\AC[1-9][0-9]*\z/)
      end
    rescue ArgumentError
      expected_cohorts = []
    end
  end

  p3_cohorts = lane_ids.each_with_object([]) { |lane_id, ids| ids << "C#{lane_id.match(P3_LANE)[1]}" if lane_id.match?(P3_LANE) }
  v_cohorts = lane_ids.each_with_object([]) { |lane_id, ids| ids << "C#{lane_id.match(V_LANE)[1]}" if lane_id.match?(V_LANE) }
  if phase == "planning_provisional"
    unless expected_cohorts.empty? || p3_cohorts.sort == expected_cohorts.sort
      errors << "planning_provisional cohort readiness requires one exact P3-Ci lane per section cohort"
    end
    return
  end

  if %w[g40_handoff production_active].include?(phase)
    errors << "#{phase} requires the retired P3-Ci cohort lanes" if p3_cohorts.empty?
    errors << "#{phase} requires one V-Ci production lane per P3-Ci cohort" if v_cohorts.empty?
    unless expected_cohorts.empty?
      errors << "#{phase} P3-Ci lanes do not exact-cover the section cohort map" unless p3_cohorts.sort == expected_cohorts.sort
      errors << "#{phase} V-Ci lanes do not exact-cover the section cohort map" unless v_cohorts.sort == expected_cohorts.sort
    end
  end
end

def validate_lineage_semantics(root, errors, document, validation_mode: "active_promotion")
  overall_lanes = Array(document["lanes"]).select { |lane| lane.is_a?(Hash) && lane["logical_role"].to_s == "overall_director" }
  errors << "exactly one logical Overall Director is required" unless overall_lanes.length == 1
  if overall_lanes.length == 1
    overall_lane = overall_lanes[0]
    overall = document["overall"]
    if overall.is_a?(Hash)
      errors << "Overall logical_lineage_id is missing" if overall["logical_lineage_id"].to_s.strip.empty?
      unless overall["active_writer_session_id"].to_s == overall_lane["active_writer_session_id"].to_s
        errors << "Overall active writer does not match the overall lane"
      end
    end
    errors << "overall lane_id must be overall" unless overall_lane["lane_id"].to_s == "overall"
  end

  lane_ids = []
  Array(document["lanes"]).each do |lane|
    next unless lane.is_a?(Hash)

    lane_id = lane["lane_id"].to_s
    errors << "duplicate lane_id #{lane_id}" if lane_ids.include?(lane_id)
    lane_ids << lane_id
    validate_lane(root, errors, lane, document["phase"].to_s, validation_mode: validation_mode)
    validate_lane_carry_pointer(root, errors, lane)
  end

  integration_ids = Array(document["lanes"]).select { |lane| lane.is_a?(Hash) && lane["integration_writer"] == true }.map { |lane| lane["lane_id"].to_s }
  if lane_ids.include?("planning_p1")
    errors << "only planning_p1 may be the planning integration writer" unless integration_ids == ["planning_p1"]
  elsif !integration_ids.empty?
    errors << "only planning_p1 may be the planning integration writer"
  end

  owned = {}
  Array(document["lanes"]).each do |lane|
    next unless lane.is_a?(Hash)
    next if lane.dig("succession", "authority_state").to_s == "read_only_retired"

    write_scope_keys(lane).each do |key|
      owner = owned[key]
      if owner && owner != lane["lane_id"].to_s
        errors << "P1/P2/P3-Ci write scopes overlap: #{key[0]} @ #{key[1]} owned by #{owner} and #{lane['lane_id']}"
      else
        owned[key] = lane["lane_id"].to_s
      end
    end
  end

  policy = document["provider_policy"]
  if policy.is_a?(Hash)
    errors << "provider fallback is forbidden" unless policy["fallback_allowed"] == false
    errors << "silent provider substitution is forbidden" unless policy["silent_substitution_allowed"] == false
    unless policy["director_minimum_alias"].to_s == "frontier_director"
      errors << "director lane must resolve frontier_director with no fallback"
    end

    caps = policy["physical_session_caps"] || {}
    live_by_provider = Hash.new(0)
    Array(document["lanes"]).each do |lane|
      next unless lane.is_a?(Hash)
      next if lane["lane_id"].to_s == "overall"

      provider = lane.dig("provider_binding", "registered_provider").to_s
      Array(lane["physical_sessions"]).each do |session|
        next unless session.is_a?(Hash)
        next if session["state"].to_s == "graph_logically_retired"

        live_by_provider[provider] += 1
      end
    end
    grok_live = live_by_provider["grok"]
    cursor_live = live_by_provider["cursor"]
    combined_live = grok_live + cursor_live
    errors << "Grok live physical session ceiling exceeded: #{grok_live}>#{caps['grok_build_nonroot']}" if grok_live > Integer(caps["grok_build_nonroot"] || 0)
    errors << "Cursor live physical session ceiling exceeded: #{cursor_live}>#{caps['cursor_agent_nonroot']}" if cursor_live > Integer(caps["cursor_agent_nonroot"] || 0)
    errors << "combined live physical session ceiling exceeded: #{combined_live}>#{caps['combined']}" if combined_live > Integer(caps["combined"] || 0)
  end

  validate_p3_v_carry(errors, Array(document["lanes"]), document["phase"].to_s)
  validate_required_phase_lanes(root, errors, document)
  validate_pointer(root, errors, "section_cohort_map", document["section_cohort_map"])
  cohort_contract = validate_cohort_map_lineage_binding(root, errors, document)
  Array(document["department_dispatch_pointers"]).each_with_index do |pointer, index|
    validate_pointer(root, errors, "department_dispatch_pointers[#{index}]", pointer)
    next unless pointer.is_a?(Hash)

    begin
      path, _relative = repo_path(root, pointer["path"])
    rescue ArgumentError
      next
    end
    next unless path.file?

    dispatch = load_document(path)
    unless dispatch.is_a?(Hash) && dispatch["artifact_type"].to_s == "graph_department_dispatch"
      errors << "department_dispatch_pointers[#{index}] is not a graph_department_dispatch"
      next
    end
    schema_errors(DISPATCH_SCHEMA, path).each { |message| errors << "department_dispatch_pointers[#{index}] #{message}" }
    validate_dispatch_semantics(root, errors, dispatch, validation_mode: validation_mode)
    validate_section_dispatch_reviewer_binding(errors, dispatch, cohort_contract)
  end
end

path = document_path(options[:root], argument)
unless path.file?
  warn "document is missing: #{argument}"
  exit 2
end

errors = []
if options[:validation_mode] == "test_boundary"
  begin
    relative_document_path = path.realpath.relative_path_from(options[:root].realpath).to_s
    unless relative_document_path.start_with?("scripts/tests/fixtures/")
      errors << "test_boundary is restricted to documents under scripts/tests/fixtures"
    end
  rescue ArgumentError, Errno::ENOENT
    errors << "test_boundary is restricted to documents under scripts/tests/fixtures"
  end
end
document = load_document(path)
if document.nil?
  errors << "document must be a JSON or YAML object"
else
  artifact = document["artifact_type"].to_s
  case artifact
  when "graph_director_lineage"
    errors.concat(schema_errors(LINEAGE_SCHEMA, path))
    validate_lineage_semantics(options[:root], errors, document, validation_mode: options[:validation_mode])
  when "graph_department_dispatch"
    errors.concat(schema_errors(DISPATCH_SCHEMA, path))
    validate_dispatch_semantics(options[:root], errors, document, validation_mode: options[:validation_mode])
  else
    errors << "artifact_type must be graph_director_lineage or graph_department_dispatch"
  end
end

status = errors.empty? ? "pass" : "fail"
payload = {
  "status" => status,
  "validation_mode" => options[:validation_mode],
  "promotion_authority" => false,
  "schema_version" => document.is_a?(Hash) ? document["schema_version"] : nil,
  "artifact_type" => document.is_a?(Hash) ? document["artifact_type"] : nil,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(payload)
else
  if errors.empty?
    puts "graph-director-lineage: pass (validation_mode=#{options[:validation_mode]}; promotion_authority=false)"
  else
    warn errors.join("\n")
  end
end

exit(errors.empty? ? 0 : 1)
