#!/usr/bin/env ruby
# frozen_string_literal: true

# Graph-v2-only physical Director session shadow-readiness router.
#
# This script mutates only its run-local operational authority state. It never
# opens a provider session, authors creative truth, changes a Founder gate, or
# writes a Graph lineage/production artifact. Its route-authorize action is a
# readiness observation, never execution permission. Historical CDD router
# bytes use scripts/idol_director_dispatch_index.rb and remain a separate
# legacy route.

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "time"
require "yaml"
require_relative "lib/idol_graph_goal_evidence_contract"
require_relative "lib/idol_graph_provider_binding_contract"
require_relative "lib/idol_role_context_pack"

module IdolGraphDirectorSessionRouter
  ROOT = Pathname.new(__dir__).join("..").expand_path.freeze
  STATE_SCHEMA = ROOT.join("schemas", "graph-director-session-router-state.schema.json").freeze
  LINEAGE_SCHEMA = ROOT.join("schemas", "graph-director-lineage.schema.json").freeze
  ROLE_CONTEXT_PACK_SCHEMA = ROOT.join("schemas", "role-context-pack.schema.json").freeze
  LINEAGE_VALIDATOR = ROOT.join("scripts", "validate_graph_director_lineage.rb").freeze
  PYTHON = ROOT.join("scripts", "idol-video-python").freeze
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py").freeze
  SCHEMA_VERSION = "idol-graph-director-session-router-state.v1"
  ROUTING_MODE = "graph_v2"
  LANE_ID = /\A(?:overall|planning_p1|planning_p2|planning_p3_c[1-9][0-9]*|section_cluster_v_c[1-9][0-9]*|edit_director)\z/
  TOKEN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{1,180}\z/
  SHA256 = /\A[a-f0-9]{64}\z/
  OPERATIONS = %w[goal_and_preflight prompt resume dispatch review canonical_write founder_conversation promotion].freeze
  MUTATING_OPERATIONS = %w[prompt resume dispatch review canonical_write founder_conversation promotion].freeze
  PHASE_EVENTS = {
    "successor_preflight" => %w[initialized],
    "successor_admitted" => %w[initialized admitted],
    "successor_active" => %w[initialized admitted committed],
    "rolled_back" => %w[initialized admitted committed rolled_back]
  }.freeze
  EVENT_EVIDENCE = {
    "initialized" => "shadow_same_lane_succession_observation",
    "admitted" => "shadow_provider_goal_admission_observation",
    "committed" => "shadow_cas_readiness_observation",
    "rolled_back" => "shadow_failure_rollback_observation"
  }.freeze
  LANE_ROLE = {
    "overall" => "overall_director",
    "planning_p1" => "planning_cdd_p1",
    "planning_p2" => "planning_cdd_p2",
    "edit_director" => "edit_director"
  }.freeze
  OVERALL_MACRO_STAGES = %w[planning_cell section_cluster_production edit_and_package].freeze
  SHADOW_BLOCKERS = %w[
    graph_director_router_is_shadow_readiness_only
    no_execution_authorization_consumer_registered
    typed_commit_authority_receipt_not_registered
    typed_rollback_failure_and_primary_liveness_receipt_not_registered
  ].freeze
  PROVIDER_BINDING_KEYS = %w[
    registered_provider
    runtime_surface
    logical_profile_alias
    execution_profile_id
    resolved_provider_model
    reasoning_effort
    provider_capability_snapshot_sha256
    fallback_allowed
    silent_substitution_allowed
  ].freeze
  GOAL_EVIDENCE_KEYS = %w[
    native_goal_id
    goal_text_sha256
    goal_semantics
    goal_terminal_state
    goal_last_event
    goal_terminal_event_sha256
    terminal_event
    goal_completed_closes
    idol_assignment_pass
  ].freeze
  NONSECRET_CHILD_ENV = {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil}.freeze

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors).map(&:to_s)
      super(@errors.join("; "))
    end
  end

  module_function

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original = value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[original])
      end
    when Array
      value.map { |item| canonicalize(item) }
    when Date, Time, DateTime
      value.iso8601
    else
      value
    end
  end

  def digest_value(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def sha256(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def sha256!(value, label)
    text = value.to_s
    raise ValidationError, ["#{label} must be a lowercase SHA-256"] unless text.match?(SHA256)

    text
  end

  def timestamp!(value, label)
    text = value.to_s
    Time.iso8601(text)
    text
  rescue ArgumentError
    raise ValidationError, ["#{label} must be an ISO-8601 timestamp"]
  end

  def exact_keys!(value, expected, label)
    raise ValidationError, ["#{label} must be an object"] unless value.is_a?(Hash)

    actual = value.keys.map(&:to_s).sort
    wanted = expected.sort
    return value if actual == wanted

    raise ValidationError, ["#{label} keys must be exactly #{wanted.join(', ')}; got #{actual.join(', ')}"]
  end

  def path_within?(path, root)
    clean_path = Pathname.new(path).expand_path.cleanpath
    clean_root = Pathname.new(root).expand_path.cleanpath
    clean_path == clean_root || clean_path.to_s.start_with?("#{clean_root}#{File::SEPARATOR}")
  end

  def ensure_no_symlink_ancestors!(path, allowed_root, label)
    candidate = Pathname.new(path).expand_path.cleanpath
    root = Pathname.new(allowed_root).expand_path.cleanpath
    raise ValidationError, ["#{label} escapes its allowed root"] unless path_within?(candidate, root)
    raise ValidationError, ["#{label} allowed root is missing"] unless root.directory?
    raise ValidationError, ["#{label} allowed root must not be a symlink"] if root.symlink?

    current = root
    candidate.relative_path_from(root).each_filename do |component|
      current = current.join(component)
      break unless current.exist? || current.symlink?
      raise ValidationError, ["#{label} contains a symlink ancestor: #{current}"] if current.symlink?
    end

    existing = candidate
    existing = existing.parent until existing.exist? || existing.symlink? || existing == root
    raise ValidationError, ["#{label} contains a symlink ancestor: #{existing}"] if existing.symlink?
    root_real = root.realpath
    existing_real = existing.realpath
    raise ValidationError, ["#{label} escapes its allowed root"] unless path_within?(existing_real, root_real)

    candidate
  rescue ArgumentError, Errno::ENOENT => e
    raise ValidationError, ["#{label} cannot be resolved safely: #{e.message}"]
  end

  def test_root
    raw = ENV["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT"].to_s
    return nil if raw.empty?

    root = Pathname.new(raw).expand_path.cleanpath
    private_tmp = Pathname.new("/private/tmp").expand_path.cleanpath
    unless root != private_tmp && path_within?(root, private_tmp)
      raise ValidationError, ["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT must name one bounded child of /private/tmp"]
    end
    unless root.parent == private_tmp && root.basename.to_s.start_with?("idol-graph-director-router-")
      raise ValidationError, ["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT must use the dedicated idol-graph-director-router-* proof-root pattern"]
    end
    raise ValidationError, ["IDOL_GRAPH_DIRECTOR_ROUTER_TEST_ROOT must not be a symlink"] if root.symlink?
    root
  end

  def resolve_state_path(raw)
    text = raw.to_s
    raise ValidationError, ["Graph Director router state_path is empty"] if text.empty?

    path = Pathname.new(text)
    if path.absolute?
      root = test_root
      unless root && path_within?(path, root)
        raise ValidationError, ["absolute Graph Director router state_path requires the exact bounded /private/tmp proof root"]
      end
      return [ensure_no_symlink_ancestors!(path, root, "Graph Director router state_path"), true]
    end
    raise ValidationError, ["Graph Director router state_path must be clean repository-relative"] if text.start_with?("./") || text.include?("\\")

    path = ROOT.join(path).expand_path.cleanpath
    raise ValidationError, ["Graph Director router state_path escapes repository"] unless path_within?(path, ROOT)

    [ensure_no_symlink_ancestors!(path, ROOT, "Graph Director router state_path"), false]
  end

  def canonical_state_relative(run_root, lane_id, macro_stage_id)
    "#{run_root}/work/graph-director-session-router/#{lane_id}/#{macro_stage_id}/active-session.json"
  end

  def validate_state_location!(state_path, noncanonical, state)
    return if noncanonical

    relative = state_path.relative_path_from(ROOT).to_s
    expected = canonical_state_relative(state["run_root"], state["lane_id"], state["macro_stage_id"])
    raise ValidationError, ["Graph Director router state_path must be #{expected}"] unless relative == expected
  end

  def resolve_pointer(value, label, noncanonical)
    pointer = exact_keys!(value, %w[path sha256], label)
    digest = sha256!(pointer["sha256"], "#{label} sha256")
    path_text = pointer["path"].to_s
    candidate = Pathname.new(path_text)
    if candidate.absolute?
      root = test_root
      unless noncanonical && root && path_within?(candidate, root)
        raise ValidationError, ["#{label} absolute path is outside the bounded proof root"]
      end
      path = ensure_no_symlink_ancestors!(candidate, root, label)
    else
      path = ROOT.join(candidate).expand_path.cleanpath
      raise ValidationError, ["#{label} path escapes repository"] unless path_within?(path, ROOT)
      path = ensure_no_symlink_ancestors!(path, ROOT, label)
    end
    raise ValidationError, ["#{label} path is missing"] unless path.file?
    raise ValidationError, ["#{label} path must not be a symlink"] if path.symlink?
    raise ValidationError, ["#{label} SHA-256 is stale"] unless sha256(path) == digest

    {"path" => path_text, "sha256" => digest}
  end

  def load_mapping(path, label)
    value = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, aliases: true)
    raise ValidationError, ["#{label} must contain a structured object"] unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception => e
    raise ValidationError, ["#{label} is not valid structured evidence: #{e.message}"]
  end

  def validate_schema_file(path, schema, label)
    stdout, stderr, status = Open3.capture3(
      NONSECRET_CHILD_ENV,
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      schema.to_s,
      path.to_s,
      chdir: ROOT.to_s
    )
    return if status.success?

    message = [stderr, stdout].reject { |item| item.to_s.strip.empty? }.join(" ").strip
    raise ValidationError, ["#{label} failed JSON Schema validation: #{message}"]
  end

  def lane_role(lane_id)
    return "planning_cdd_p3_ci" if lane_id.to_s.match?(/\Aplanning_p3_c/)
    return "section_cluster_cdd_ci" if lane_id.to_s.match?(/\Asection_cluster_v_c/)

    LANE_ROLE[lane_id.to_s]
  end

  def provider_contract_role(lane_id)
    lane = lane_id.to_s
    return "overall_director" if lane == "overall"
    return "planning_cdd" if lane.start_with?("planning_")
    return "section_cluster_cdd" if lane.start_with?("section_cluster_v_c")
    return "edit_director" if lane == "edit_director"

    nil
  end

  def macro_stage_allowed?(lane_id, macro_stage_id)
    lane = lane_id.to_s
    stage = macro_stage_id.to_s
    return OVERALL_MACRO_STAGES.include?(stage) if lane == "overall"
    return stage == "planning_cell" if lane.start_with?("planning_")
    return stage == "section_cluster_production" if lane.start_with?("section_cluster_v_c")
    return stage == "edit_and_package" if lane == "edit_director"

    false
  end

  def correlated_lineage!(document, params)
    errors = []
    errors << "Director lineage run differs from router run_root" unless document["run"].to_s == params["run_root"].to_s
    lane = Array(document["lanes"]).find { |row| row.to_h["lane_id"].to_s == params["lane_id"].to_s }
    unless lane
      errors << "Director lineage does not contain router lane #{params['lane_id']}"
      raise ValidationError, errors
    end
    errors << "Director lineage logical_lineage_id differs" unless lane["logical_lineage_id"].to_s == params["logical_lineage_id"].to_s
    errors << "router macro_stage_id is not registered for its lane" unless macro_stage_allowed?(params["lane_id"], params["macro_stage_id"])
    if params["lane_id"].to_s == "overall"
      errors << "Director lineage Overall macro-stage differs" unless document.dig("overall", "macro_stage_id").to_s == params["macro_stage_id"].to_s
    end
    errors << "Director lineage primary is not the active writer" unless lane["active_writer_session_id"].to_s == params["primary_session_id"].to_s
    sessions = Array(lane["physical_sessions"])
    primary = sessions.find { |row| row.to_h["generation"].to_s == "primary" }
    errors << "Director lineage primary session differs" unless primary && primary["session_id"].to_s == params["primary_session_id"].to_s
    successor = sessions.find { |row| row.to_h["generation"].to_s == "successor" }
    if successor && successor["session_id"].to_s != params["successor_session_id"].to_s
      errors << "Director lineage already binds another successor"
    end
    binding = lane["provider_binding"].to_h
    errors << "Director lineage provider differs" unless binding["registered_provider"].to_s == params["provider"].to_s
    errors << "Director lineage runtime surface differs" unless binding["runtime_surface"].to_s == params["runtime_surface"].to_s
    errors << "Director lineage lane is not frontier_director" unless binding["logical_profile_alias"].to_s == "frontier_director"
    raise ValidationError, errors unless errors.empty?

    true
  end

  def correlated_role_context_pack!(pack, params)
    errors = IdolRoleContextPack.validate_pack(root: ROOT, pack: pack)
    errors << "Role Context Pack is not an admitted Graph-v2 pack" unless pack.dig("activation_binding", "writer").to_s == ROUTING_MODE
    errors << "Role Context Pack run differs from router run_root" unless pack.dig("identity", "run_root").to_s == params["run_root"].to_s
    errors << "Role Context Pack role differs from router lane" unless pack.dig("identity", "role").to_s == lane_role(params["lane_id"])
    provider = pack["provider_binding"].to_h
    errors << "Role Context Pack provider differs" unless provider["provider"].to_s == params["provider"].to_s
    errors << "Role Context Pack runtime surface differs" unless provider["runtime_surface"].to_s == params["runtime_surface"].to_s
    errors << "Role Context Pack Director profile is not frontier_director" unless provider["logical_profile_alias"].to_s == "frontier_director"
    raise ValidationError, errors unless errors.empty?

    true
  end

  def assess_route_bindings(paths, params, noncanonical)
    checks = %w[verified_switch_receipt director_lineage role_context_pack successor_pack provider_source safe_checkpoint].to_h do |key|
      [key, "hash_only_shadow_hold"]
    end
    checks["successor_goal_admission"] = "not_yet_admitted_shadow_hold"
    errors = []

    begin
      receipt = load_mapping(paths.fetch("verified_switch_receipt"), "verified switch receipt")
      IdolRoleContextPack.validate_graph_switch_receipt!(ROOT, receipt)
      checks["verified_switch_receipt"] = "typed_current_valid"
    rescue IdolRoleContextPack::ContractError, ValidationError => e
      checks["verified_switch_receipt"] = "invalid_shadow_hold"
      errors.concat(e.respond_to?(:errors) ? e.errors : [e.message])
    end

    begin
      lineage_path = paths.fetch("director_lineage")
      validate_schema_file(lineage_path, LINEAGE_SCHEMA, "Director lineage")
      lineage = load_mapping(lineage_path, "Director lineage")
      correlated_lineage!(lineage, params)
      unless noncanonical
        stdout, stderr, status = Open3.capture3(
          NONSECRET_CHILD_ENV,
          RbConfig.ruby,
          LINEAGE_VALIDATOR.to_s,
          lineage_path.to_s,
          chdir: ROOT.to_s
        )
        unless status.success?
          raise ValidationError, ["Director lineage failed active validation: #{[stderr, stdout].join(' ').strip}"]
        end
      end
      checks["director_lineage"] = "typed_correlated_valid"
    rescue ValidationError => e
      checks["director_lineage"] = "invalid_shadow_hold"
      errors.concat(e.errors)
    end

    begin
      pack_path = paths.fetch("role_context_pack")
      validate_schema_file(pack_path, ROLE_CONTEXT_PACK_SCHEMA, "Role Context Pack")
      correlated_role_context_pack!(load_mapping(pack_path, "Role Context Pack"), params)
      checks["role_context_pack"] = "typed_correlated_valid"
    rescue ValidationError => e
      checks["role_context_pack"] = "invalid_shadow_hold"
      errors.concat(e.errors)
    end

    raise ValidationError, errors.uniq if !noncanonical && errors.any?

    blockers = SHADOW_BLOCKERS.dup
    blockers.concat(%w[
      successor_pack_has_no_graph_typed_contract
      provider_source_and_safe_checkpoint_are_hash_only
      successor_goal_admission_not_yet_verified
    ])
    blockers << "noncanonical_proof_evidence_is_not_activation_evidence" if noncanonical
    blockers << "typed_core_evidence_invalid" if errors.any?
    {
      "status" => errors.empty? ? "typed_core_correlated_shadow_hold" : "hold_unverified_or_incomplete",
      "checks" => checks,
      "blockers" => blockers.uniq
    }
  end

  def verify_goal_admission!(state, provider_binding, goal_evidence, noncanonical)
    binding = exact_keys!(provider_binding, PROVIDER_BINDING_KEYS, "Graph Director provider_binding")
    goal = exact_keys!(goal_evidence, GOAL_EVIDENCE_KEYS, "Graph Director goal_evidence")
    unless goal["goal_completed_closes"] == "successor_admission_only" && goal["idol_assignment_pass"] == false
      raise ValidationError, ["Graph Director successor Goal evidence may close admission only and must not imply IDOL assignment PASS"]
    end

    begin
      IdolGraphProviderBindingContract.resolve!(
        root: ROOT,
        binding: binding,
        studio_role: provider_contract_role(state["lane_id"])
      )
    rescue IdolGraphProviderBindingContract::ContractError => e
      raise ValidationError, ["Graph Director provider binding failed exact resolution [#{e.code}]: #{e.message}"]
    end

    errors = []
    errors << "Graph Director provider binding differs from router provider" unless binding["registered_provider"] == state["provider"]
    errors << "Graph Director provider binding differs from router runtime surface" unless binding["runtime_surface"] == state["runtime_surface"]
    errors << "Graph Director successor must resolve frontier_director" unless binding["logical_profile_alias"] == "frontier_director"
    raise ValidationError, errors unless errors.empty?

    evidence_root = noncanonical ? test_root : ROOT
    validation_mode = noncanonical ? "test_boundary" : "active_promotion"
    begin
      verified_event = IdolGraphGoalEvidenceContract.verify!(
        root: evidence_root,
        provider_binding: binding,
        goal_evidence: goal,
        validation_mode: validation_mode,
        test_proof_root: noncanonical ? evidence_root : nil
      )
    rescue IdolGraphGoalEvidenceContract::ContractError => e
      raise ValidationError, ["Graph Director Goal terminal event failed exact verification [#{e.code}]: #{e.message}"]
    end

    expected_goal = state["provider"] == "grok" ? %w[grok_goal_completed_admission complete goal_completed] : %w[cursor_external_goal_runtime_receipt success cli_terminal_success]
    actual_goal = [goal["goal_semantics"], goal["goal_terminal_state"], goal["goal_last_event"]]
    unless actual_goal == expected_goal
      raise ValidationError, ["Graph Director provider-native Goal semantics are invalid"]
    end

    admission_digest = digest_value("provider_binding" => binding, "goal_evidence" => goal)
    {
      "admission_digest" => admission_digest,
      "verification_status" => "typed_goal_terminal_event_and_provider_binding_verified",
      "validation_mode" => validation_mode,
      "provider_binding" => binding,
      "goal_evidence" => goal,
      "verified_terminal_event" => verified_event
    }
  end

  def verify_persisted_admission!(state, noncanonical)
    admission = state["admission"]
    return state if admission.nil?

    verified = verify_goal_admission!(state, admission["provider_binding"], admission["goal_evidence"], noncanonical)
    errors = []
    errors << "Graph Director persisted admission digest is stale" unless admission["admission_digest"] == verified["admission_digest"]
    errors << "Graph Director persisted admission verification status is invalid" unless admission["verification_status"] == verified["verification_status"]
    errors << "Graph Director persisted admission validation mode is invalid" unless admission["validation_mode"] == verified["validation_mode"]
    errors << "Graph Director persisted terminal-event verification differs" unless admission["verified_terminal_event"] == verified["verified_terminal_event"]
    raise ValidationError, errors unless errors.empty?

    state
  end

  def schema_errors(state)
    Tempfile.create(["graph-director-router-state-", ".json"], "/private/tmp") do |file|
      file.write(JSON.pretty_generate(state))
      file.flush
      stdout, stderr, status = Open3.capture3(
        NONSECRET_CHILD_ENV,
        PYTHON.to_s,
        SCHEMA_VALIDATOR.to_s,
        STATE_SCHEMA.to_s,
        file.path,
        chdir: ROOT.to_s
      )
      return [] if status.success?

      message = [stderr, stdout].reject { |item| item.to_s.strip.empty? }.join(" ").strip
      [message.empty? ? "Graph Director router state failed JSON Schema validation" : message]
    end
  end

  def validate_semantics!(state)
    errors = []
    errors << "Graph Director router state must remain HOLD" unless state["status"] == "hold"
    unless state["authority"] == "shadow_readiness_only_no_execution_or_canonical_authority"
      errors << "Graph Director router must remain shadow readiness only"
    end
    errors << "Graph Director router must never grant execution authority" unless state["execution_authority"] == false
    unless state["activation_status"] == "hold_shadow_not_execution_ready"
      errors << "Graph Director router activation must remain HOLD"
    end
    unless state["authorization_semantics"] == "readiness_observation_only_never_execution_permission"
      errors << "Graph Director router authorization semantics are invalid"
    end
    errors << "routing_mode must be graph_v2" unless state["routing_mode"] == ROUTING_MODE
    errors << "lane_id is not a registered Graph Director lane" unless state["lane_id"].to_s.match?(LANE_ID)
    errors << "macro_stage_id is invalid" unless state["macro_stage_id"].to_s.match?(TOKEN)
    errors << "physical_session_limit must be exactly two" unless state["physical_session_limit"] == 2
    primary = state["primary_session"] || {}
    successor = state["successor_session"] || {}
    errors << "primary and successor session ids must be distinct" if primary["session_id"].to_s == successor["session_id"].to_s
    errors << "primary_session generation must be primary" unless primary["generation"] == "primary"
    errors << "successor_session generation must be successor" unless successor["generation"] == "successor"

    expected = case state["phase"]
               when "successor_preflight"
                 [0, primary["session_id"], "active_single_writer", "zero_turn_read_only_preflight", nil]
               when "successor_admitted"
                 [1, primary["session_id"], "active_single_writer", "admitted_read_only", Hash]
               when "successor_active"
                 [2, successor["session_id"], "graph_logically_retired", "active_single_writer", Hash]
               when "rolled_back"
                 [3, primary["session_id"], "reactivated_single_writer", "graph_logically_retired", Hash]
               end
    if expected
      errors << "generation does not match phase" unless state["generation"] == expected[0]
      errors << "active_writer_session_id does not match phase" unless state["active_writer_session_id"] == expected[1]
      errors << "primary session state does not match phase" unless primary["state"] == expected[2]
      errors << "successor session state does not match phase" unless successor["state"] == expected[3]
      admission_ok = expected[4].nil? ? state["admission"].nil? : state["admission"].is_a?(expected[4])
      errors << "admission presence does not match phase" unless admission_ok
    else
      errors << "phase is invalid"
    end

    gate = state["founder_gate_contract"] || {}
    errors << "Graph succession must not add a Founder confirmation" unless gate["same_lane_succession_confirmation_required"] == false
    errors << "Graph succession must not add a Founder gate" unless gate["succession_adds_founder_gate"] == false
    errors << "normal Founder cycle must remain G0--G4" unless gate["normal_cycle"] == %w[G0 G1 G2 G3 G4]

    history = Array(state["history"])
    expected_events = PHASE_EVENTS[state["phase"]]
    errors << "history event sequence does not match phase" unless expected_events && history.map { |row| row["event"] } == expected_events
    history.each_with_index do |transition, index|
      event = transition["event"].to_s
      errors << "#{event} evidence_kind is invalid" unless transition["evidence_kind"] == EVENT_EVIDENCE[event]
      errors << "#{event} transition basis SHA-256 is invalid" unless transition["basis_sha256"] == digest_value(transition.reject { |key, _| key == "basis_sha256" })
      previous = index.zero? ? nil : history[index - 1]["basis_sha256"]
      errors << "#{event} transition chain is broken" unless transition["previous_transition_basis_sha256"] == previous
      errors << "#{event} source session differs from primary" unless transition["source_session_id"] == primary["session_id"]
      errors << "#{event} successor session differs from successor" unless transition["successor_session_id"] == successor["session_id"]
    end
    errors << "last_transition must equal the final history row" unless state["last_transition"] == history.last
    validation = state["evidence_validation"].to_h
    errors << "Graph Director router evidence blockers are required" if Array(validation["blockers"]).empty?
    admission_check = validation.dig("checks", "successor_goal_admission")
    if state["phase"] == "successor_preflight"
      errors << "Graph Director preflight must mark successor Goal admission as not yet verified" unless admission_check == "not_yet_admitted_shadow_hold"
      unless Array(validation["blockers"]).include?("successor_goal_admission_not_yet_verified")
        errors << "Graph Director preflight must expose the unverified successor Goal blocker"
      end
    else
      expected_admission_check = state["noncanonical_proof_root"] ? "typed_test_boundary_valid" : "typed_correlated_valid"
      errors << "Graph Director admitted successor must have typed Goal and provider verification" unless admission_check == expected_admission_check
      if Array(validation["blockers"]).include?("successor_goal_admission_not_yet_verified")
        errors << "Graph Director admitted successor retains a stale Goal admission blocker"
      end
    end
    receipt_contract = state["transition_receipt_contract"].to_h
    unless receipt_contract["typed_receipt_required_before_activation"] == true &&
           receipt_contract["hash_claim_opens_execution_authority"] == false
      errors << "Graph Director router hash claims must not open execution authority"
    end

    errors.concat(schema_errors(state))
    raise ValidationError, errors unless errors.empty?

    state
  end

  def verify_route_bindings!(state, noncanonical)
    state.fetch("route_binding").each do |key, pointer|
      resolve_pointer(pointer, "route_binding #{key}", noncanonical)
    end
    state
  rescue KeyError => e
    raise ValidationError, ["Graph Director router route binding is incomplete: #{e.message}"]
  end

  def read_state(path, noncanonical)
    raise ValidationError, ["Graph Director router state is missing"] unless path.file?
    raise ValidationError, ["Graph Director router state must not be a symlink"] if path.symlink?
    state = JSON.parse(path.read)
    raise ValidationError, ["Graph Director router state must contain an object"] unless state.is_a?(Hash)
    validate_semantics!(state)
    validate_state_location!(path, noncanonical, state)
    verify_route_bindings!(state, noncanonical)
    verify_persisted_admission!(state, noncanonical)
    [state, sha256(path)]
  rescue JSON::ParserError => e
    raise ValidationError, ["Graph Director router state JSON is invalid: #{e.message}"]
  end

  def atomic_write(path, state)
    validate_semantics!(state)
    payload = JSON.pretty_generate(state) + "\n"
    Tempfile.create([".graph-director-session-", ".json"], path.dirname.to_s) do |file|
      file.chmod(0o600)
      file.write(payload)
      file.flush
      file.fsync
      File.rename(file.path, path.to_s)
    end
    File.open(path.dirname.to_s, File::RDONLY) { |directory| directory.fsync }
    sha256(path)
  rescue Errno::ENOENT, Errno::EACCES, SystemCallError => e
    raise ValidationError, ["cannot atomically write Graph Director router state: #{e.message}"]
  end

  def with_lock(raw)
    path, noncanonical = resolve_state_path(raw)
    allowed_root = noncanonical ? test_root : ROOT
    ensure_no_symlink_ancestors!(path.dirname, allowed_root, "Graph Director router parent")
    FileUtils.mkdir_p(path.dirname)
    ensure_no_symlink_ancestors!(path.dirname, allowed_root, "Graph Director router parent")
    raise ValidationError, ["Graph Director router state must not be a symlink"] if path.symlink?
    lock_path = path.dirname.join(".active-session.lock")
    raise ValidationError, ["Graph Director router lock must not be a symlink"] if lock_path.symlink?
    File.open(lock_path.to_s, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      yield path, noncanonical
    ensure
      lock.flock(File::LOCK_UN) rescue nil
    end
  rescue Errno::ENOENT, Errno::EACCES, SystemCallError => e
    raise ValidationError, ["cannot lock Graph Director router state: #{e.message}"]
  end

  def transition(event:, at:, before_generation:, after_generation:, source:, successor:, active_before:, active_after:, previous_state_sha256:, previous_transition_sha256:, evidence_sha256:)
    value = {
      "event" => event,
      "evidence_kind" => EVENT_EVIDENCE.fetch(event),
      "recorded_at" => at,
      "generation_before" => before_generation,
      "generation_after" => after_generation,
      "source_session_id" => source,
      "successor_session_id" => successor,
      "active_writer_before" => active_before,
      "active_writer_after" => active_after,
      "previous_state_sha256" => previous_state_sha256,
      "previous_transition_basis_sha256" => previous_transition_sha256,
      "evidence_sha256" => evidence_sha256
    }
    value.merge("basis_sha256" => digest_value(value))
  end

  def result(path, state, state_sha)
    {
      "status" => "hold",
      "activation_status" => state["activation_status"],
      "authority" => state["authority"],
      "execution_authority" => false,
      "routing_mode" => ROUTING_MODE,
      "state_path" => path.to_s,
      "state_sha256" => state_sha,
      "lane_id" => state["lane_id"],
      "macro_stage_id" => state["macro_stage_id"],
      "generation" => state["generation"],
      "phase" => state["phase"],
      "active_writer_session_id" => state["active_writer_session_id"],
      "transition_receipt_sha256" => state.dig("last_transition", "basis_sha256"),
      "admission_digest" => state.dig("admission", "admission_digest"),
      "founder_confirmation_required" => false,
      "blockers" => state.dig("evidence_validation", "blockers"),
      "noncanonical_proof_root" => state["noncanonical_proof_root"]
    }
  end

  def initialize_route(params)
    exact_keys!(params, %w[action state_path routing_mode run_root lane_id macro_stage_id logical_lineage_id provider runtime_surface primary_session_id successor_session_id verified_switch_receipt director_lineage role_context_pack successor_pack provider_source safe_checkpoint recorded_at], "Graph Director initialize request")
    raise ValidationError, ["Graph Director router is Graph-v2-only"] unless params["routing_mode"] == ROUTING_MODE
    lane_id = params["lane_id"].to_s
    macro_stage_id = params["macro_stage_id"].to_s
    raise ValidationError, ["lane_id is not a registered Graph Director lane"] unless lane_id.match?(LANE_ID)
    raise ValidationError, ["macro_stage_id is invalid"] unless macro_stage_id.match?(TOKEN)
    unless macro_stage_allowed?(lane_id, macro_stage_id)
      raise ValidationError, ["macro_stage_id is not registered for lane #{lane_id}"]
    end
    provider = params["provider"].to_s
    raise ValidationError, ["Graph Director provider must be cursor or grok"] unless %w[cursor grok].include?(provider)
    primary = params["primary_session_id"].to_s
    successor = params["successor_session_id"].to_s
    unless primary.match?(TOKEN) && successor.match?(TOKEN) && primary != successor
      raise ValidationError, ["Graph Director router requires distinct primary and successor session ids"]
    end
    at = timestamp!(params["recorded_at"], "Graph Director recorded_at")

    with_lock(params["state_path"]) do |path, noncanonical|
      raise ValidationError, ["Graph Director router state already exists; a third physical session is forbidden"] if path.exist?
      unless noncanonical
        expected = canonical_state_relative(params["run_root"], lane_id, macro_stage_id)
        actual = path.relative_path_from(ROOT).to_s
        raise ValidationError, ["Graph Director router state_path must be #{expected}"] unless actual == expected
      end
      resolved_paths = {}
      bindings = %w[verified_switch_receipt director_lineage role_context_pack successor_pack provider_source safe_checkpoint].each_with_object({}) do |key, memo|
        memo[key] = resolve_pointer(params[key], key, noncanonical)
        raw_path = Pathname.new(memo[key]["path"])
        resolved_paths[key] = raw_path.absolute? ? raw_path.expand_path.cleanpath : ROOT.join(raw_path).expand_path.cleanpath
      end
      bindings["router_implementation"] = {"path" => "scripts/idol_graph_director_session_router.rb", "sha256" => sha256(Pathname.new(__FILE__).expand_path)}
      bindings["state_schema"] = {"path" => "schemas/graph-director-session-router-state.schema.json", "sha256" => sha256(STATE_SCHEMA)}
      evidence = digest_value(bindings)
      evidence_validation = assess_route_bindings(resolved_paths, params, noncanonical)
      initial = transition(
        event: "initialized", at: at, before_generation: 0, after_generation: 0,
        source: primary, successor: successor, active_before: nil, active_after: primary,
        previous_state_sha256: nil, previous_transition_sha256: nil, evidence_sha256: evidence
      )
      state = {
        "schema_version" => SCHEMA_VERSION,
        "artifact_type" => "graph_director_session_router_state",
        "status" => "hold",
        "authority" => "shadow_readiness_only_no_execution_or_canonical_authority",
        "routing_mode" => ROUTING_MODE,
        "router_id" => "GRAPH_DIRECTOR_ROUTER_#{digest_value([params['run_root'], lane_id, macro_stage_id, primary, successor])[0, 24].upcase}",
        "run_root" => params["run_root"].to_s,
        "lane_id" => lane_id,
        "macro_stage_id" => macro_stage_id,
        "logical_lineage_id" => params["logical_lineage_id"].to_s,
        "provider" => provider,
        "runtime_surface" => params["runtime_surface"].to_s,
        "generation" => 0,
        "phase" => "successor_preflight",
        "physical_session_limit" => 2,
        "active_writer_session_id" => primary,
        "primary_session" => {"generation" => "primary", "session_id" => primary, "state" => "active_single_writer"},
        "successor_session" => {"generation" => "successor", "session_id" => successor, "state" => "zero_turn_read_only_preflight"},
        "route_binding" => bindings,
        "admission" => nil,
        "founder_gate_contract" => {
          "normal_cycle" => %w[G0 G1 G2 G3 G4],
          "same_lane_succession_confirmation_required" => false,
          "succession_adds_founder_gate" => false,
          "legacy_dual_confirmation_router" => "schemas/cdd-session-router-state.schema.json"
        },
        "last_transition" => initial,
        "history" => [initial],
        "activation_status" => "hold_shadow_not_execution_ready",
        "execution_authority" => false,
        "authorization_semantics" => "readiness_observation_only_never_execution_permission",
        "evidence_validation" => evidence_validation,
        "transition_receipt_contract" => {
          "commit_input" => "sha256_claim_only_not_typed_authority_receipt",
          "rollback_input" => "sha256_claim_only_not_typed_failure_or_liveness_receipt",
          "typed_receipt_required_before_activation" => true,
          "hash_claim_opens_execution_authority" => false
        },
        "noncanonical_proof_root" => noncanonical
      }
      raise ValidationError, ["logical_lineage_id is invalid"] unless state["logical_lineage_id"].match?(TOKEN)
      raise ValidationError, ["runtime_surface is missing"] if state["runtime_surface"].strip.empty?
      state_sha = atomic_write(path, state)
      result(path, state, state_sha)
    end
  end

  def assert_expected!(state, current_sha, params)
    expected_sha = sha256!(params["expected_state_sha256"], "expected_state_sha256")
    raise ValidationError, ["Graph Director compare-and-swap failed: state SHA changed"] unless expected_sha == current_sha
    raise ValidationError, ["Graph Director compare-and-swap failed: generation changed"] unless params["expected_generation"].is_a?(Integer) && params["expected_generation"] == state["generation"]
    raise ValidationError, ["Graph Director primary session is stale"] unless params["primary_session_id"].to_s == state.dig("primary_session", "session_id")
    raise ValidationError, ["Graph Director successor session is stale"] unless params["successor_session_id"].to_s == state.dig("successor_session", "session_id")
  end

  def admit(params)
    exact_keys!(params, %w[action state_path expected_state_sha256 expected_generation primary_session_id successor_session_id provider_binding goal_evidence recorded_at], "Graph Director admit request")
    at = timestamp!(params["recorded_at"], "Graph Director recorded_at")

    with_lock(params["state_path"]) do |path, noncanonical|
      state, state_sha = read_state(path, noncanonical)
      assert_expected!(state, state_sha, params)
      raise ValidationError, ["Graph Director successor may be admitted only from read-only preflight"] unless state["phase"] == "successor_preflight"
      admission = verify_goal_admission!(state, params["provider_binding"], params["goal_evidence"], noncanonical)
      transition_value = transition(
        event: "admitted", at: at, before_generation: 0, after_generation: 1,
        source: params["primary_session_id"], successor: params["successor_session_id"],
        active_before: state["active_writer_session_id"], active_after: state["active_writer_session_id"],
        previous_state_sha256: state_sha, previous_transition_sha256: state.dig("last_transition", "basis_sha256"), evidence_sha256: admission["admission_digest"]
      )
      state["generation"] = 1
      state["phase"] = "successor_admitted"
      state["successor_session"]["state"] = "admitted_read_only"
      state["admission"] = admission
      state["evidence_validation"]["checks"]["successor_goal_admission"] = noncanonical ? "typed_test_boundary_valid" : "typed_correlated_valid"
      state["evidence_validation"]["blockers"].delete("successor_goal_admission_not_yet_verified")
      state["last_transition"] = transition_value
      state["history"] << transition_value
      next_sha = atomic_write(path, state)
      result(path, state, next_sha)
    end
  end

  def commit(params)
    exact_keys!(params, %w[action state_path expected_state_sha256 expected_generation primary_session_id successor_session_id admission_digest director_succession_authority_sha256 recorded_at], "Graph Director commit request")
    at = timestamp!(params["recorded_at"], "Graph Director recorded_at")
    admission_digest = sha256!(params["admission_digest"], "admission_digest")
    authority_sha = sha256!(params["director_succession_authority_sha256"], "director_succession_authority_sha256")
    with_lock(params["state_path"]) do |path, noncanonical|
      state, state_sha = read_state(path, noncanonical)
      assert_expected!(state, state_sha, params)
      raise ValidationError, ["Graph Director can commit only an admitted read-only successor"] unless state["phase"] == "successor_admitted"
      raise ValidationError, ["Graph Director admission digest is stale"] unless state.dig("admission", "admission_digest") == admission_digest
      primary = params["primary_session_id"]
      successor = params["successor_session_id"]
      raise ValidationError, ["Graph Director primary is not the active writer"] unless state["active_writer_session_id"] == primary
      transition_value = transition(
        event: "committed", at: at, before_generation: 1, after_generation: 2,
        source: primary, successor: successor, active_before: primary, active_after: successor,
        previous_state_sha256: state_sha, previous_transition_sha256: state.dig("last_transition", "basis_sha256"), evidence_sha256: authority_sha
      )
      state["generation"] = 2
      state["phase"] = "successor_active"
      state["active_writer_session_id"] = successor
      state["primary_session"]["state"] = "graph_logically_retired"
      state["successor_session"]["state"] = "active_single_writer"
      state["last_transition"] = transition_value
      state["history"] << transition_value
      next_sha = atomic_write(path, state)
      result(path, state, next_sha)
    end
  end

  def rollback(params)
    exact_keys!(params, %w[action state_path expected_state_sha256 expected_generation primary_session_id successor_session_id commit_receipt_sha256 failure_receipt_sha256 recorded_at], "Graph Director rollback request")
    at = timestamp!(params["recorded_at"], "Graph Director recorded_at")
    commit_sha = sha256!(params["commit_receipt_sha256"], "commit_receipt_sha256")
    failure_sha = sha256!(params["failure_receipt_sha256"], "failure_receipt_sha256")
    with_lock(params["state_path"]) do |path, noncanonical|
      state, state_sha = read_state(path, noncanonical)
      assert_expected!(state, state_sha, params)
      raise ValidationError, ["Graph Director can roll back only an active successor"] unless state["phase"] == "successor_active"
      unless state.dig("last_transition", "event") == "committed" && state.dig("last_transition", "basis_sha256") == commit_sha
        raise ValidationError, ["Graph Director commit receipt does not match the active transition"]
      end
      primary = params["primary_session_id"]
      successor = params["successor_session_id"]
      transition_value = transition(
        event: "rolled_back", at: at, before_generation: 2, after_generation: 3,
        source: primary, successor: successor, active_before: successor, active_after: primary,
        previous_state_sha256: state_sha, previous_transition_sha256: commit_sha, evidence_sha256: failure_sha
      )
      state["generation"] = 3
      state["phase"] = "rolled_back"
      state["active_writer_session_id"] = primary
      state["primary_session"]["state"] = "reactivated_single_writer"
      state["successor_session"]["state"] = "graph_logically_retired"
      state["last_transition"] = transition_value
      state["history"] << transition_value
      next_sha = atomic_write(path, state)
      result(path, state, next_sha)
    end
  end

  def authorize(params)
    exact_keys!(params, %w[action state_path expected_state_sha256 expected_generation session_id operation], "Graph Director authorize request")
    operation = params["operation"].to_s
    raise ValidationError, ["Graph Director operation is unsupported"] unless OPERATIONS.include?(operation)
    path, noncanonical = resolve_state_path(params["state_path"])
    state, state_sha = read_state(path, noncanonical)
    expected_sha = sha256!(params["expected_state_sha256"], "expected_state_sha256")
    raise ValidationError, ["Graph Director authorization state SHA is stale"] unless expected_sha == state_sha
    raise ValidationError, ["Graph Director authorization generation is stale"] unless params["expected_generation"] == state["generation"]
    session_id = params["session_id"].to_s
    observable = if operation == "goal_and_preflight"
                   %w[successor_preflight successor_admitted].include?(state["phase"]) && session_id == state.dig("successor_session", "session_id")
                 else
                   session_id == state["active_writer_session_id"]
                 end
    observable = false if %w[founder_conversation promotion].include?(operation) && state["lane_id"] != "overall"
    raise ValidationError, ["Graph Director router denied readiness observation for #{operation} on inactive, read-only, or role-ineligible session #{session_id}"] unless observable
    basis = {
      "routing_mode" => ROUTING_MODE,
      "state_sha256" => state_sha,
      "generation" => state["generation"],
      "lane_id" => state["lane_id"],
      "macro_stage_id" => state["macro_stage_id"],
      "session_id" => session_id,
      "operation" => operation,
      "active_writer_session_id" => state["active_writer_session_id"],
      "phase" => state["phase"]
    }
    {
      "status" => "hold",
      "authorization" => "shadow_observation_only",
      "execution_authority" => false,
      "operation_must_remain_blocked" => true,
      "readiness_observation_sha256" => digest_value(basis),
      "blockers" => state.dig("evidence_validation", "blockers"),
      "basis" => basis
    }
  end

  def snapshot(params)
    exact_keys!(params, %w[action state_path], "Graph Director snapshot request")
    path, noncanonical = resolve_state_path(params["state_path"])
    state, state_sha = read_state(path, noncanonical)
    result(path, state, state_sha).merge("state" => state)
  end

  def command(params)
    action = params.is_a?(Hash) ? params["action"].to_s : ""
    case action
    when "route-initialize" then initialize_route(params)
    when "route-admit" then admit(params)
    when "route-commit" then commit(params)
    when "route-authorize" then authorize(params)
    when "route-rollback" then rollback(params)
    when "route-snapshot" then snapshot(params)
    else
      raise ValidationError, ["Graph Director router action must be one registered route-* action"]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  unless ARGV.empty?
    warn "usage: ruby scripts/idol_graph_director_session_router.rb < request.json"
    exit 2
  end
  begin
    request = JSON.parse($stdin.read)
    puts JSON.generate(IdolGraphDirectorSessionRouter.command(request))
  rescue JSON::ParserError => e
    warn "ERROR: Graph Director router request JSON is invalid: #{e.message}"
    exit 1
  rescue IdolGraphDirectorSessionRouter::ValidationError => e
    warn e.errors.map { |error| "ERROR: #{error}" }.join("\n")
    exit 1
  end
end
