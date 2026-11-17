# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "idol_current_next_v2"

module IdolGraphRunController
  SCHEMA_VERSION = "idol-graph-run-controller-state.v1"
  STAGE_REGISTRY_VERSION = "idol-graph-stage-registry.v1"
  JUDGMENT_VERSION = "idol_graph_contextual_judgment.v2"
  DISPATCH_VERSION = "idol-department-dispatch.v8"
  GRAPH_DISPATCH_VERSION = "idol-graph-department-dispatch.v1"
  GRAPH_PROFILE_RELEASE_VERSION = "idol-graph-creative-judgment-profile-release.v1"
  STAGE_REGISTRY_PATH = "automation/graph-stage-registry.yaml"
  JUDGMENT_REGISTRY_PATH = "automation/graph-creative-judgment-registry.yaml"
  JUDGMENT_REGISTRY_VERSION = "idol-graph-creative-judgment-registry.v1"
  CONTEXTUAL_JUDGMENT_VALIDATOR_PATH = "scripts/validate_graph_contextual_judgment.rb"
  TEST_JUDGMENT_FIXTURE_PREFIX = "runs/controller-test/fixture/"
  CORRECTION_ROUTES = %w[same_session_new_attempt new_session_new_lineage].freeze
  AUTHORITY_ACTIONS = {
    "paid_generation_approval" => %w[paid],
    "await_paid_generation_approval" => %w[paid],
    "external_mutation_approval" => %w[external],
    "await_external_mutation_approval" => %w[external],
    "external_action_approval" => %w[external],
    "download_approval" => %w[download],
    "capture_approval" => %w[capture],
    "upload_approval" => %w[upload],
    "download_capture_upload_external_mutation" => %w[download capture upload external],
    "destructive_action_approval" => %w[destructive],
    "protected_output_disposal_approval" => %w[destructive],
    "release_approval" => %w[release],
    "public_release_approval" => %w[release]
  }.freeze
  AUTHORITY_KIND_ORDER = %w[creative_gate paid download capture upload external destructive release].freeze
  JOIN_DEPENDENCY_ROLE = "canonical_head_join_dependency"
  ACTIVATION_BLOCKERS = %w[
    graph_v2_default_switch_receipt_not_consumed
    provider_launcher_not_connected
    event_writer_not_connected
    founder_decision_receipt_reducer_not_connected
    root_goal_progression_not_bound
    graph_batch_scheduler_not_connected
    typed_ddi_material_authority_requirements_not_registered
    legacy_dispatch_v8_full_schema_and_policy_validation_not_embedded
  ].freeze
  INTENT_TYPES = {
    "dispatch_or_resume_model" => "dispatch_or_resume_planned",
    "await_director_review" => "director_review_wait_planned",
    "route_bounded_correction" => "bounded_correction_planned",
    "await_founder_decision" => "founder_decision_wait_planned",
    "hold" => "hold_planned"
  }.freeze

  class Error < StandardError; end

  module_function

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original = value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical_value(value.fetch(original))
      end
    when Array
      value.map { |item| canonical_value(item) }
    when Date, Time, DateTime
      value.iso8601
    else
      value
    end
  end

  def digest_value(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end

  def root_path(root)
    Pathname.new(root).expand_path.cleanpath
  end

  def resolve_path(root, value, label)
    raise Error, "#{label} path is missing" if value.nil? || value.to_s.strip.empty?

    base = root_path(root)
    raw = Pathname.new(value.to_s)
    path = raw.absolute? ? raw.expand_path.cleanpath : base.join(raw).expand_path.cleanpath
    boundary = base.to_s
    unless path.to_s == boundary || path.to_s.start_with?("#{boundary}#{File::SEPARATOR}")
      raise Error, "#{label} escapes repository root"
    end
    raise Error, "#{label} is not a readable file: #{value}" unless path.file?

    real_base = base.realpath.to_s
    real_path = path.realpath.to_s
    unless real_path == real_base || real_path.start_with?("#{real_base}#{File::SEPARATOR}")
      raise Error, "#{label} resolves outside repository root"
    end
    path
  rescue Errno::ENOENT, Errno::EACCES => error
    raise Error, "#{label} is not readable: #{error.message}"
  end

  def relative_path(root, path)
    Pathname.new(path).expand_path.cleanpath.relative_path_from(root_path(root)).to_s
  end

  def load_document(path, label)
    text = Pathname.new(path).read(encoding: "utf-8")
    value = if Pathname.new(path).extname.downcase == ".json"
              JSON.parse(text)
            else
              YAML.safe_load(text, permitted_classes: [Date, Time, DateTime], aliases: true)
            end
    raise Error, "#{label} must contain a mapping" unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception => error
    raise Error, "cannot parse #{label}: #{error.message}"
  end

  def pointer_for(root, path, role)
    resolved = resolve_path(root, path, role)
    {
      "path" => relative_path(root, resolved),
      "sha256" => Digest::SHA256.file(resolved).hexdigest,
      "role" => role
    }
  end

  def verify_pointer(root, binding, label, role: nil)
    raise Error, "#{label} must be a path/SHA-256 binding" unless binding.is_a?(Hash)

    resolved = resolve_path(root, binding["path"], label)
    expected = binding["sha256"].to_s
    raise Error, "#{label} SHA-256 is malformed" unless expected.match?(/\A[a-f0-9]{64}\z/)
    actual = Digest::SHA256.file(resolved).hexdigest
    raise Error, "#{label} SHA-256 is stale" unless actual == expected
    resolved_role = role || binding["role"].to_s
    resolved_role = "bound_artifact" if resolved_role.empty?
    {
      "path" => relative_path(root, resolved),
      "sha256" => actual,
      "role" => resolved_role
    }
  end

  def contextual_judgment_validator(root:, path:)
    validator = resolve_path(root, CONTEXTUAL_JUDGMENT_VALIDATOR_PATH, "contextual judgment validator")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      validator.to_s,
      "--root", root_path(root).to_s,
      path.to_s,
      chdir: root_path(root).to_s
    )
    unless status.success?
      detail = [stderr, stdout].join(" ").strip
      raise Error, "contextual judgment failed the formal validator: #{detail}"
    end

    {
      "status" => "pass",
      "validator" => CONTEXTUAL_JUDGMENT_VALIDATOR_PATH,
      "boundary" => "formal_contextual_judgment_validator"
    }
  end

  def invoke_contextual_judgment_validator!(root:, path:, validator:)
    callable = validator || method(:contextual_judgment_validator)
    receipt = callable.call(root: root_path(root), path: path)
    unless receipt.is_a?(Hash) && receipt["status"].to_s == "pass"
      raise Error, "contextual judgment validator did not return an explicit pass receipt"
    end
    boundary = receipt["boundary"].to_s
    if validator
      unless boundary == "test_stub" && relative_path(root, path).start_with?(TEST_JUDGMENT_FIXTURE_PREFIX)
        raise Error, "injected contextual judgment validators are restricted to the controller test fixture boundary"
      end
    elsif boundary != "formal_contextual_judgment_validator"
      raise Error, "the production contextual judgment validator boundary is not formal"
    end

    {
      "required" => true,
      "status" => "pass",
      "validator" => receipt["validator"].to_s.empty? ? "injected_validator" : receipt["validator"].to_s,
      "boundary" => boundary
    }
  rescue Error
    raise
  rescue StandardError => error
    raise Error, "contextual judgment validator failed: #{error.message}"
  end

  def verified_artifact_pair(root, row, label)
    raise Error, "#{label} must be a path/SHA-256 artifact" unless row.is_a?(Hash)

    pointer = verify_pointer(root, row, label)
    [pointer.fetch("path"), pointer.fetch("sha256")]
  end

  def verified_output_pairs(root, rows, label)
    raise Error, "#{label} must be an array" unless rows.is_a?(Array)

    pairs = rows.each_with_index.map do |row, index|
      verified_artifact_pair(root, row, "#{label}[#{index}]")
    end
    raise Error, "#{label} repeats an output" unless pairs.uniq.length == pairs.length

    pairs
  end

  def stage_rows(registry)
    Array(registry["stages"]).select { |row| row.is_a?(Hash) && row["active"] == true }.sort_by { |row| row["order"].to_i }
  end

  def stage_for(registry, stage_id)
    stage_rows(registry).find { |row| row["stage_id"].to_s == stage_id.to_s }
  end

  def next_stage(registry, stage_id)
    rows = stage_rows(registry)
    index = rows.index { |row| row["stage_id"].to_s == stage_id.to_s }
    index ? rows[index + 1] : rows.first
  end

  def selected_dispatch_row(context)
    dispatch_id = context.dig("selection", "dispatch_id").to_s
    return nil if dispatch_id.empty?

    matches = Array(context.dig("director_dispatch_index", "dispatches")).select do |row|
      row.is_a?(Hash) && row["dispatch_id"].to_s == dispatch_id
    end
    raise Error, "selected DDI dispatch must resolve exactly once" unless matches.length == 1

    matches.first
  end

  def load_selected_dispatch(root, context, row)
    return [nil, nil] unless row

    pointer = verify_pointer(root, row["dispatch_pointer"], "selected department dispatch", role: "department_dispatch_v8")
    document = load_document(resolve_path(root, pointer["path"], "selected department dispatch"), "selected department dispatch")
    raise Error, "selected dispatch schema must be #{DISPATCH_VERSION}" unless document["schema_version"].to_s == DISPATCH_VERSION
    raise Error, "selected dispatch artifact_type must be department_dispatch" unless document["artifact_type"].to_s == "department_dispatch"
    raise Error, "selected dispatch id differs from DDI" unless document["dispatch_id"].to_s == row["dispatch_id"].to_s
    raise Error, "selected dispatch belongs to another run" unless document["run"].to_s == context.dig("document", "run").to_s
    raise Error, "DDI dispatch lifecycle is stale" unless row.dig("lifecycle", "current_state").to_s == document.dig("lifecycle", "current_state").to_s
    expected_disposition = document["director_review"].is_a?(Hash) ? document.dig("director_review", "disposition").to_s : "not_reviewed"
    projected_disposition = row.dig("review", "disposition").to_s
    unless projected_disposition.empty? || projected_disposition == expected_disposition
      raise Error, "DDI Director disposition is stale"
    end
    [document, pointer]
  end

  def load_stage_registry(root, path)
    pointer = pointer_for(root, path, "graph_stage_registry")
    unless pointer["path"] == STAGE_REGISTRY_PATH
      raise Error, "shadow controller requires the canonical Graph stage registry"
    end
    document = load_document(resolve_path(root, pointer["path"], "graph stage registry"), "graph stage registry")
    raise Error, "graph stage registry schema must be #{STAGE_REGISTRY_VERSION}" unless document["schema_version"].to_s == STAGE_REGISTRY_VERSION
    unless document["status"].to_s == "shadow_read_only" && document["default_writer"].to_s == "forbidden" && document["authority"].to_s == "read_only_projection"
      raise Error, "graph stage registry is not a read-only shadow"
    end
    rows = stage_rows(document)
    ids = rows.map { |row| row["stage_id"].to_s }
    orders = rows.map { |row| row["order"] }
    raise Error, "graph stage registry has no active stages" if rows.empty?
    raise Error, "graph stage registry active stage ids must be unique and non-empty" unless ids.all? { |id| !id.empty? } && ids.uniq.length == ids.length
    raise Error, "graph stage registry active stage orders must be unique integers" unless orders.all? { |order| order.is_a?(Integer) } && orders.uniq.length == orders.length
    gates = Array(document["founder_gates"]).map { |row| row.is_a?(Hash) ? row["gate_id"].to_s : "" }
    raise Error, "graph stage registry must exact-cover Founder gates G0-G4" unless gates.sort == %w[G0 G1 G2 G3 G4]
    [document, pointer]
  end

  def load_judgment_registry(root)
    path = resolve_path(root, JUDGMENT_REGISTRY_PATH, "judgment registry")
    pointer = pointer_for(root, path, "graph_creative_judgment_registry")
    document = load_document(path, "judgment registry")
    unless document["schema_version"].to_s == JUDGMENT_REGISTRY_VERSION &&
           document["authority"].to_s == "criteria_registry_no_creative_or_promotion_authority"
      raise Error, "contextual judgment registry is not the active no-authority registry"
    end
    [document, pointer]
  end

  def profiles_for_stage(judgment_registry, stage_id)
    Array(judgment_registry["profiles"]).select do |profile|
      profile.is_a?(Hash) && Array(profile["stages"]).map(&:to_s).include?(stage_id.to_s)
    end
  end

  def no_judgment_validation
    {
      "required" => false,
      "status" => "not_supplied",
      "validator" => nil,
      "boundary" => "not_run_no_judgment"
    }
  end

  def empty_migration_bridge(dispatch_pointer)
    {
      "status" => "not_applicable_before_judgment",
      "legacy_dispatch" => dispatch_pointer,
      "graph_dispatch" => nil,
      "checks" => {
        "dispatch_id_exact_match" => nil,
        "run_exact_match" => nil,
        "owner_exact_match" => nil,
        "stage_exact_match" => nil,
        "section_scope_exact_match" => nil,
        "output_set_exact_match" => nil
      },
      "activation_authority" => false
    }
  end

  def verified_migration_bridge(root:, legacy_dispatch:, legacy_pointer:, graph_dispatch:, graph_pointer:, judgment:, selected_row:)
    checks = {
      "dispatch_id_exact_match" => graph_dispatch["dispatch_id"].to_s == legacy_dispatch["dispatch_id"].to_s,
      "run_exact_match" => graph_dispatch["run"].to_s == legacy_dispatch["run"].to_s,
      "owner_exact_match" => graph_dispatch["assigned_owner"].to_s == legacy_dispatch.dig("launch", "authority", "assigned_owner").to_s,
      "stage_exact_match" => judgment["stage_id"].to_s == legacy_dispatch.dig("launch", "task", "exact_scope", "stage_id").to_s &&
        judgment["stage_id"].to_s == selected_row.dig("scope", "stage_id").to_s,
      "section_scope_exact_match" => Array(graph_dispatch["section_ids"]).map(&:to_s).sort ==
        Array(legacy_dispatch.dig("launch", "task", "exact_scope", "section_ids")).map(&:to_s).sort &&
        Array(graph_dispatch["section_ids"]).map(&:to_s).sort == Array(selected_row.dig("scope", "section_ids")).map(&:to_s).sort,
      "output_set_exact_match" => false
    }

    graph_manifest_pointer = verify_pointer(
      root,
      graph_dispatch["output_manifest"],
      "Graph dispatch output manifest",
      role: "graph_dispatch_output_manifest"
    )
    judgment_manifest = judgment.dig("execution_binding", "output_manifest")
    unless judgment_manifest.to_h.slice("path", "sha256") == graph_dispatch["output_manifest"].to_h.slice("path", "sha256")
      raise Error, "Graph/legacy migration bridge judgment output manifest differs from Graph dispatch"
    end
    manifest = load_document(resolve_path(root, graph_manifest_pointer["path"], "Graph dispatch output manifest"), "Graph dispatch output manifest")
    raise Error, "Graph dispatch output manifest identity differs" unless manifest["dispatch_id"].to_s == graph_dispatch["dispatch_id"].to_s
    raise Error, "Graph dispatch output manifest owner differs" unless manifest["assigned_owner"].to_s == graph_dispatch["assigned_owner"].to_s
    graph_pairs = verified_output_pairs(root, Array(manifest["outputs"]), "Graph dispatch outputs")
    legacy_pairs = verified_output_pairs(root, Array(legacy_dispatch.dig("runtime_return", "outputs")), "legacy dispatch returned outputs")
    checks["output_set_exact_match"] = graph_pairs.sort == legacy_pairs.sort

    failed = checks.select { |_key, value| value != true }.keys
    unless failed.empty?
      raise Error, "Graph/legacy migration bridge failed: #{failed.join(', ')}"
    end

    {
      "status" => "verified_shadow_bridge",
      "legacy_dispatch" => legacy_pointer,
      "graph_dispatch" => graph_pointer,
      "checks" => checks,
      "activation_authority" => false
    }
  end

  def load_and_validate_judgment(root, path, selected_row, dispatch, dispatch_pointer, stage_id, registry, validator: nil)
    return [nil, nil, nil, nil, no_judgment_validation, empty_migration_bridge(dispatch_pointer), nil] if path.nil? || path.to_s.strip.empty?
    raise Error, "a contextual judgment cannot bind without a selected dispatch" unless selected_row && dispatch

    pointer = pointer_for(root, path, "graph_contextual_judgment")
    judgment_path = resolve_path(root, pointer["path"], "contextual judgment")
    validation = invoke_contextual_judgment_validator!(root: root, path: judgment_path, validator: validator)
    document = load_document(judgment_path, "contextual judgment")
    raise Error, "contextual judgment schema must be #{JUDGMENT_VERSION}" unless document["schema_version"].to_s == JUDGMENT_VERSION
    raise Error, "contextual judgment artifact_type is invalid" unless document["artifact_type"].to_s == "graph_contextual_judgment"
    raise Error, "contextual judgment cannot contain an aggregate score" unless document["aggregate_score_present"] == false
    raise Error, "contextual judgment cannot grant automatic creative PASS" unless document["automatic_creative_pass"] == false
    raise Error, "contextual judgment stage differs from the DDI frontier" unless document["stage_id"].to_s == stage_id.to_s
    assignment_id = document.dig("execution_binding", "assignment_id").to_s
    raise Error, "contextual judgment assignment differs from the selected dispatch" unless assignment_id == selected_row["dispatch_id"].to_s

    bound_dispatch_pointer = verify_pointer(root, document.dig("execution_binding", "dispatch"), "judgment execution Graph dispatch", role: "graph_department_dispatch_v1")
    bound_dispatch = load_document(resolve_path(root, bound_dispatch_pointer["path"], "judgment execution dispatch"), "judgment execution dispatch")
    raise Error, "judgment execution dispatch schema must be #{GRAPH_DISPATCH_VERSION}" unless bound_dispatch["schema_version"].to_s == GRAPH_DISPATCH_VERSION
    raise Error, "judgment execution dispatch artifact_type must be graph_department_dispatch" unless bound_dispatch["artifact_type"].to_s == "graph_department_dispatch"
    raise Error, "judgment execution Graph dispatch must be a returned snapshot" unless bound_dispatch["lifecycle_state"].to_s == "returned"
    raise Error, "judgment execution dispatch id differs from the selected dispatch" unless bound_dispatch["dispatch_id"].to_s == selected_row["dispatch_id"].to_s
    raise Error, "judgment execution dispatch belongs to another run" unless bound_dispatch["run"].to_s == dispatch["run"].to_s
    raise Error, "judgment profile differs from the Graph dispatch" unless bound_dispatch["judgment_profile_id"].to_s == document["profile_id"].to_s
    raise Error, "judgment author session differs from the Graph output writer" unless bound_dispatch.dig("output_writer", "session_id").to_s == document.dig("execution_binding", "author_session_id").to_s

    release_pointer = verify_pointer(root, document.dig("execution_binding", "profile_release"), "judgment immutable profile release", role: "graph_judgment_profile_release")
    release = load_document(resolve_path(root, release_pointer["path"], "judgment immutable profile release"), "judgment immutable profile release")
    unless release["schema_version"].to_s == GRAPH_PROFILE_RELEASE_VERSION && release["status"].to_s == "immutable_release"
      raise Error, "contextual judgment profile release is not an immutable release"
    end
    profile = release["profile"]
    raise Error, "contextual judgment profile release has no profile" unless profile.is_a?(Hash)
    raise Error, "contextual judgment profile release identity differs" unless profile["profile_id"].to_s == document["profile_id"].to_s
    raise Error, "contextual judgment profile is outside the frontier stage" unless Array(profile["stages"]).map(&:to_s).include?(stage_id.to_s)
    unless Array(profile["checkpoints"]).map(&:to_s).include?(document["checkpoint_id"].to_s)
      raise Error, "contextual judgment checkpoint is outside the registered profile"
    end
    expected_profile_sha = digest_value(profile)
    unless document.dig("execution_binding", "profile_value_sha256").to_s == expected_profile_sha
      raise Error, "contextual judgment profile value SHA-256 is stale"
    end
    decision = document["decision"].to_s
    expected_edge = registry.dig("decision_edges", decision).to_s
    expected_status = registry.dig("decision_status", decision).to_s
    raise Error, "contextual judgment decision is not registered" if expected_edge.empty? || expected_status.empty?
    raise Error, "contextual judgment next edge differs from the registry" unless document["next_edge"].to_s == expected_edge
    raise Error, "contextual judgment status differs from the registry" unless document["status"].to_s == expected_status

    criteria = Array(document["criteria"])
    raise Error, "contextual judgment criteria are missing" if criteria.empty?
    criteria.each do |criterion|
      result = criterion.is_a?(Hash) ? criterion["result"] : nil
      valid_result = result == "not_applicable" || (result.is_a?(Integer) && result.between?(0, 4))
      raise Error, "contextual judgment contains a result outside 0-4/not_applicable" unless valid_result
    end
    bridge = verified_migration_bridge(
      root: root,
      legacy_dispatch: dispatch,
      legacy_pointer: dispatch_pointer,
      graph_dispatch: bound_dispatch,
      graph_pointer: bound_dispatch_pointer,
      judgment: document,
      selected_row: selected_row
    )
    [document, pointer, bound_dispatch, bound_dispatch_pointer, validation, bridge, release_pointer]
  end

  def authority_requirement(kind:, gate_id:, source:, must_precede_action:)
    suffix = gate_id.to_s.empty? ? kind : gate_id.to_s.downcase
    {
      "requirement_id" => "founder_authority_#{suffix}",
      "authority_kind" => kind,
      "gate_id" => gate_id,
      "source" => source,
      "must_precede_action" => must_precede_action,
      "receipt_binding" => nil,
      "receipt_status" => "missing_unconsumed_shadow"
    }
  end

  def action_authority_requirements(action_code)
    Array(AUTHORITY_ACTIONS[action_code.to_s]).map do |kind|
      authority_requirement(
        kind: kind,
        gate_id: nil,
        source: "ddi_action_code_conservative_guard",
        must_precede_action: true
      )
    end
  end

  def stage_authority_requirements(stage, closure:)
    return [] unless stage

    requirements = []
    gate = stage["founder_gate"].to_s
    if closure && gate.match?(/\AG[0-4]\z/)
      requirements << authority_requirement(
        kind: "creative_gate",
        gate_id: gate,
        source: "graph_stage_registry_founder_gate",
        must_precede_action: false
      )
    end
    if stage["existing_paid_gate"]
      requirements << authority_requirement(
        kind: "paid",
        gate_id: nil,
        source: "graph_stage_registry_existing_paid_gate",
        must_precede_action: true
      )
    end
    if closure && stage["existing_release_gate"]
      requirements << authority_requirement(
        kind: "release",
        gate_id: nil,
        source: "graph_stage_registry_existing_release_gate",
        must_precede_action: true
      )
    end
    requirements
  end

  def combined_authority_requirements(stage:, closure:, action_code:)
    combined = stage_authority_requirements(stage, closure: closure) + action_authority_requirements(action_code)
    combined.each_with_object([]) do |requirement, union|
      key = [requirement["authority_kind"], requirement["gate_id"]]
      union << requirement unless union.any? { |row| [row["authority_kind"], row["gate_id"]] == key }
    end.sort_by do |row|
      [AUTHORITY_KIND_ORDER.index(row["authority_kind"]) || AUTHORITY_KIND_ORDER.length, row["gate_id"].to_s]
    end
  end

  def authority_stop(requirements)
    primary = Array(requirements).first
    return nil unless primary

    {
      "required" => true,
      "authority_kind" => primary.fetch("authority_kind"),
      "gate_id" => primary["gate_id"]
    }
  end

  def no_founder_stop
    {"required" => false, "authority_kind" => "none", "gate_id" => nil}
  end

  def authority_receipt_contract(action_code, requirements)
    code = action_code.to_s
    status = if !code.empty?
               "legacy_action_code_untyped_shadow_hold"
             elsif requirements.any?
               "stage_registry_requirements_unconsumed_shadow"
             else
               "no_material_action_projection_shadow"
             end
    {
      "status" => status,
      "producer_contract" => "typed_ddi_authority_requirements_and_receipt_bindings_not_registered",
      "legacy_action_code" => code.empty? ? nil : code,
      "legacy_action_code_is_execution_authority" => false,
      "typed_ddi_authority_requirements_present" => false,
      "receipt_bindings" => requirements.map do |requirement|
        {
          "requirement_id" => requirement.fetch("requirement_id"),
          "receipt" => nil,
          "verification_status" => "missing_unconsumed_shadow"
        }
      end,
      "all_required_receipts_verified" => false,
      "execution_authority" => false
    }
  end

  def ready_action_set(root, context)
    ddi = context.fetch("director_dispatch_index")
    dispatches = Array(ddi["dispatches"])
    Array(ddi["next_actions"]).select do |row|
      row.is_a?(Hash) && %w[open ready in_progress].include?(row["state"].to_s)
    end.map do |row|
      action_id = row["next_action_id"].to_s
      matches = dispatches.select { |dispatch| Array(dispatch["next_action_ids"]).map(&:to_s).include?(action_id) }
      raise Error, "ready action #{action_id} must resolve to exactly one DDI dispatch" unless matches.length == 1

      dispatch_row = matches.first
      scope = row["scope"].is_a?(Hash) ? row["scope"] : {}
      dispatch_scope = dispatch_row["scope"].is_a?(Hash) ? dispatch_row["scope"] : {}
      unless scope["stage_id"].to_s == dispatch_scope["stage_id"].to_s &&
             Array(scope["section_ids"]).map(&:to_s).sort == Array(dispatch_scope["section_ids"]).map(&:to_s).sort
        raise Error, "ready action #{action_id} scope differs from its DDI dispatch"
      end
      dispatch_pointer = verify_pointer(root, dispatch_row["dispatch_pointer"], "ready action #{action_id} department dispatch", role: "department_dispatch_v8")
      dependency_pairs = Array(row["dependency_pointers"]).each_with_object([]) do |binding, pairs|
        pairs << [binding["path"].to_s, binding["sha256"].to_s] if binding.is_a?(Hash)
      end
      unless dependency_pairs.include?([dispatch_pointer["path"], dispatch_pointer["sha256"]])
        raise Error, "ready action #{action_id} is not bound to its exact department dispatch pointer"
      end
      dispatch_document = load_document(
        resolve_path(root, dispatch_pointer["path"], "ready action #{action_id} department dispatch"),
        "ready action #{action_id} department dispatch"
      )
      unless dispatch_document["schema_version"].to_s == DISPATCH_VERSION && dispatch_document["artifact_type"].to_s == "department_dispatch"
        raise Error, "ready action #{action_id} department dispatch is not #{DISPATCH_VERSION}"
      end
      unless dispatch_document["dispatch_id"].to_s == dispatch_row["dispatch_id"].to_s &&
             dispatch_document["run"].to_s == context.dig("document", "run").to_s &&
             dispatch_document.dig("lifecycle", "current_state").to_s == dispatch_row.dig("lifecycle", "current_state").to_s
        raise Error, "ready action #{action_id} department dispatch identity or lifecycle is stale"
      end
      task_scope = dispatch_document.dig("launch", "task", "exact_scope")
      unless task_scope.is_a?(Hash) && task_scope["stage_id"].to_s == scope["stage_id"].to_s &&
             Array(task_scope["section_ids"]).map(&:to_s).sort == Array(scope["section_ids"]).map(&:to_s).sort
        raise Error, "ready action #{action_id} differs from the legacy dispatch exact scope"
      end
      {
        "action_id" => action_id,
        "dispatch_id" => dispatch_row["dispatch_id"].to_s,
        "dispatch_pointer" => dispatch_pointer,
        "stage_id" => scope["stage_id"].to_s.empty? ? nil : scope["stage_id"].to_s,
        "section_ids" => Array(scope["section_ids"]).map(&:to_s).sort,
        "owner" => row["owner"].to_s,
        "state" => row["state"].to_s,
        "evidence_status" => "verified_legacy_shadow_input"
      }
    end.sort_by { |row| [row["stage_id"].to_s, row["section_ids"].join(","), row["action_id"]] }
  end

  def frontier_set(root, context)
    actions = ready_action_set(root, context)
    section_sets = actions.map { |row| row["section_ids"] }
    all_scoped = section_sets.all? { |sections| !sections.empty? }
    flat_sections = section_sets.flatten
    action_stage_ids = actions.map { |row| row["stage_id"].to_s }.reject(&:empty?).uniq
    single_stage = actions.length <= 1 || action_stage_ids.length == 1
    disjoint = actions.length <= 1 ? true : all_scoped && single_stage && flat_sections.uniq.length == flat_sections.length
    mode = if actions.empty?
             "none"
           elsif actions.length == 1
             "single"
           elsif disjoint
             "cohort_set_shadow_blocked"
           else
             "conflicting_set_hold"
           end

    heads = Array(context.dig("director_dispatch_index", "current_heads")).select do |row|
      row.is_a?(Hash) && row["state"].to_s == "current"
    end
    head_stage_ids = heads.map { |row| row["stage_id"].to_s }.reject(&:empty?).uniq.sort
    join_required = heads.length > 1
    join_action_id = nil
    verified_head_ids = []
    head_artifact_pairs = []
    if join_required && actions.length == 1
      join_action_id = actions.first.fetch("action_id")
      action_row = Array(context.dig("director_dispatch_index", "next_actions")).find do |row|
        row.is_a?(Hash) && row["next_action_id"].to_s == join_action_id
      end
      typed_dependencies = Array(action_row&.fetch("dependency_pointers", nil)).select do |pointer|
        pointer.is_a?(Hash) && pointer["role"].to_s == JOIN_DEPENDENCY_ROLE
      end.map.with_index do |pointer, index|
        verified = verify_pointer(root, pointer, "join dependency #{join_action_id}[#{index}]", role: JOIN_DEPENDENCY_ROLE)
        [verified["path"], verified["sha256"]]
      end
      heads.each_with_index do |head, index|
        artifact = verify_pointer(root, head["artifact"], "current head join artifact[#{index}]", role: "canonical_head")
        head_artifact_pairs << [artifact["path"], artifact["sha256"]]
        if typed_dependencies.include?([artifact["path"], artifact["sha256"]])
          verified_head_ids << head["head_id"].to_s
        end
      end
    end
    join_verified = join_required &&
      head_artifact_pairs.uniq.length == heads.length &&
      verified_head_ids.length == heads.length &&
      verified_head_ids.uniq.length == heads.length
    join_status = if heads.empty?
                    actions.any? ? "actionable_frontier_present" : "no_heads"
                  elsif heads.length == 1
                    actions.any? ? "actionable_frontier_present" : "single_head"
                  elsif join_verified && head_stage_ids.length == 1
                    "multi_head_same_stage_verified"
                  elsif join_verified
                    "multi_stage_verified"
                  elsif head_stage_ids.length == 1
                    "multi_head_same_stage_unresolved"
                  else
                    "multi_stage_unresolved"
                  end
    {
      "ready_actions" => actions,
      "ready_action_count" => actions.length,
      "mode" => mode,
      "all_section_scopes_disjoint" => actions.empty? ? nil : disjoint,
      "single_stage" => actions.empty? ? nil : single_stage,
      "current_head_count" => heads.length,
      "current_head_stage_ids" => head_stage_ids,
      "join_required" => join_required,
      "join_dependency_role" => JOIN_DEPENDENCY_ROLE,
      "join_action_id" => join_action_id,
      "join_verified_head_ids" => verified_head_ids.sort,
      "join_status" => join_status,
      "execution_allowed" => false
    }
  end

  def correction_plan(root, dispatch)
    review = dispatch["director_review"]
    submission = dispatch["review_submission"]
    correction = review.is_a?(Hash) ? review["correction"] : nil
    return nil unless correction.is_a?(Hash) && submission.is_a?(Hash)
    return nil unless correction["complete_problem_set"] == true
    return nil unless CORRECTION_ROUTES.include?(correction["retry_route"].to_s)

    current_number = submission["submission_number"].to_i
    maximum = submission["maximum_submissions"].to_i
    return nil unless maximum == 3 && current_number.between?(1, 2)

    assigned_owner = dispatch.dig("launch", "authority", "assigned_owner").to_s
    affected_owner = correction["affected_owner"].to_s
    return nil if assigned_owner.empty? || affected_owner != assigned_owner
    invalidated = Array(correction["invalidated_outputs"])
    criteria = Array(correction["acceptance_criteria"])
    return nil if invalidated.empty? || criteria.empty? || criteria.any? { |criterion| criterion.to_s.strip.empty? }
    return nil if correction["correction_action"].to_s.strip.empty?
    return nil if submission["review_cycle_id"].to_s.strip.empty? || dispatch.dig("lineage", "attempt_id").to_s.strip.empty?

    returned = Array(dispatch.dig("runtime_return", "outputs"))
    returned_pairs = verified_output_pairs(root, returned, "legacy correction returned outputs")
    invalidated_pairs = verified_output_pairs(root, invalidated, "legacy correction invalidated outputs")
    return nil unless (invalidated_pairs - returned_pairs).empty?

    returned_by_pair = returned.each_with_object({}) do |row, index|
      index[[row["path"].to_s, row["sha256"].to_s]] = row
    end
    invalidated = invalidated_pairs.map { |pair| returned_by_pair.fetch(pair) }
    frozen = returned.reject do |row|
      invalidated_pairs.include?([row["path"].to_s, row["sha256"].to_s])
    end
    frozen.each_with_index do |row, index|
      verified_artifact_pair(root, row, "legacy correction frozen outputs[#{index}]")
    end
    expected_partition = (invalidated.map { |row| [row["path"].to_s, row["sha256"].to_s] } + frozen.map { |row| [row["path"].to_s, row["sha256"].to_s] }).sort
    return nil unless expected_partition == returned_pairs.sort

    {
      "plan_kind" => "bounded_correction",
      "same_owner" => true,
      "owner" => affected_owner,
      "new_immutable_attempt" => true,
      "new_native_goal_required" => true,
      "review_cycle_id" => submission["review_cycle_id"].to_s,
      "previous_attempt_id" => dispatch.dig("lineage", "attempt_id").to_s,
      "next_submission_number" => current_number + 1,
      "maximum_submissions" => 3,
      "retry_route" => correction["retry_route"].to_s,
      "correction_action" => correction["correction_action"].to_s,
      "invalidated_outputs" => invalidated,
      "frozen_outputs" => frozen,
      "acceptance_criteria" => criteria,
      "fourth_submission_forbidden" => true
    }
  end

  def judgment_ready?(judgment)
    judgment.nil? || (judgment["decision"].to_s == "eligible_for_director_review" && judgment["next_edge"].to_s == "director_review")
  end

  def decision_for(root:, context:, registry:, judgment_registry:, selected_row:, dispatch:, judgment:, frontier_set:)
    selection = context.fetch("selection")
    stage_id = selected_row&.dig("scope", "stage_id").to_s
    if stage_id.empty?
      heads = Array(context.dig("director_dispatch_index", "current_heads")).select { |row| row.is_a?(Hash) && row["state"].to_s == "current" }
      stage_id = heads.first&.fetch("stage_id", nil).to_s if heads.length == 1
    end
    stage = stage_for(registry, stage_id)
    raise Error, "DDI frontier stage is not active in the Graph registry: #{stage_id}" if !stage_id.empty? && stage.nil?

    if frontier_set["ready_action_count"].to_i > 1
      reason = frontier_set["all_section_scopes_disjoint"] == true ? "parallel_cohort_frontier_shadow_blocked" : "overlapping_ready_action_scopes"
      return ["hold", reason, "hold_for_graph_batch_scheduler", registry.dig("studio_execution", "startup_owner"), no_founder_stop, nil, stage_id]
    end
    if %w[multi_head_same_stage_unresolved multi_stage_unresolved].include?(frontier_set["join_status"].to_s)
      return ["hold", "multi_head_join_unresolved", "hold_for_explicit_cohort_join", registry.dig("studio_execution", "startup_owner"), no_founder_stop, nil, stage_id]
    end

    lifecycle = dispatch&.dig("lifecycle", "current_state").to_s
    director_disposition = dispatch&.dig("director_review", "disposition").to_s
    closure_candidate = lifecycle == "promoted" || (selection["kind"].to_s == "no_actionable_unit" && !stage_id.empty?)
    action_code = selection["kind"].to_s == "next_action" ? context.dig("selection_row", "action_code").to_s : ""
    authority_requirements = combined_authority_requirements(stage: stage, closure: closure_candidate, action_code: action_code)
    material_stop = authority_stop(authority_requirements)
    if material_stop
      reason = if authority_requirements.length > 1
                 "combined_founder_authorities_required"
               elsif material_stop["authority_kind"] == "creative_gate"
                 "founder_gate_required"
               elsif authority_requirements.first["source"].start_with?("graph_stage_registry_")
                 "stage_material_authority_required"
               else
                 "explicit_founder_authority_required"
               end
      return ["await_founder_decision", reason, "await_all_founder_authority_receipts", "founder", material_stop, nil, stage_id]
    end

    if selection["kind"].to_s == "migration_hold"
      return ["hold", "graph_frontier_migration_hold", "hold_and_report", nil, no_founder_stop, nil, stage_id]
    end

    if %w[patch reject hold].include?(director_disposition)
      plan = correction_plan(root, dispatch)
      if plan
        return ["route_bounded_correction", "director_bounded_correction", "plan_new_immutable_attempt_and_goal", plan["owner"], no_founder_stop, plan, stage_id]
      end
      reason = dispatch.dig("review_submission", "submission_number").to_i >= 3 ? "submission_limit_reached" : "director_correction_not_routable"
      return ["hold", reason, "hold_and_route_upstream", dispatch.dig("launch", "authority", "director_owner"), no_founder_stop, nil, stage_id]
    end

    if selection["kind"].to_s == "open_hold" || lifecycle == "hold"
      return ["hold", "open_ddi_hold", "hold_and_report", context.dig("document", "owner"), no_founder_stop, nil, stage_id]
    end

    judgment_required = !profiles_for_stage(judgment_registry, stage_id).empty? && %w[returned reviewed].include?(lifecycle)
    if judgment_required && judgment.nil?
      return ["hold", "bound_contextual_judgment_missing", "hold_for_bound_judgment", dispatch.dig("launch", "authority", "assigned_owner"), no_founder_stop, nil, stage_id]
    end
    if judgment && !judgment_ready?(judgment)
      return ["hold", "judgment_not_eligible_without_director_correction", "hold_for_director_routing", dispatch.dig("launch", "authority", "director_owner"), no_founder_stop, nil, stage_id]
    end

    case lifecycle
    when "prepared", "launched"
      return ["dispatch_or_resume_model", "dispatch_ready_or_active", "plan_dispatch_or_resume", dispatch.dig("launch", "authority", "assigned_owner"), no_founder_stop, nil, stage_id]
    when "returned"
      return ["await_director_review", "returned_bytes_require_director_review", "await_exact_byte_director_review", dispatch.dig("launch", "authority", "director_owner"), no_founder_stop, nil, stage_id]
    when "reviewed"
      return ["await_director_review", "director_accept_requires_promotion_closure", "await_overall_promotion_closure", dispatch.dig("launch", "authority", "promotion_owner"), no_founder_stop, nil, stage_id]
    end

    if selection["kind"].to_s == "review_queue"
      return ["await_director_review", "ddi_review_queue_blocks_next", "await_exact_byte_director_review", context.dig("document", "owner"), no_founder_stop, nil, stage_id]
    end

    next_row = next_stage(registry, stage_id)
    if selection["kind"].to_s == "no_actionable_unit" && next_row && next_row["stage_id"].to_s != stage_id
      return ["dispatch_or_resume_model", "next_graph_stage_unassigned", "plan_next_stage_dispatch", registry.dig("studio_execution", "startup_owner"), no_founder_stop, nil, next_row["stage_id"].to_s]
    end
    if selection["kind"].to_s == "no_actionable_unit" && stage_id.empty? && next_row
      return ["dispatch_or_resume_model", "initial_graph_stage_unassigned", "plan_initial_stage_dispatch", registry.dig("studio_execution", "startup_owner"), no_founder_stop, nil, next_row["stage_id"].to_s]
    end
    ["hold", "frontier_exhausted_completion_unproven", "hold_for_root_goal_and_join_evidence", nil, no_founder_stop, nil, stage_id]
  end

  def build(root:, run:, current_next:, stage_registry: STAGE_REGISTRY_PATH, judgment: nil, previous_event_sha256: nil, contextual_judgment_validator: nil)
    if previous_event_sha256 && !previous_event_sha256.to_s.match?(/\A[a-f0-9]{64}\z/)
      raise Error, "previous event SHA-256 is malformed"
    end
    context = IdolCurrentNextV2.load_active(path: current_next, run: run, root: root, require_actionable: false)
    registry, registry_pointer = load_stage_registry(root, stage_registry)
    judgment_registry, judgment_registry_pointer = load_judgment_registry(root)
    selected_row = selected_dispatch_row(context)
    dispatch, dispatch_pointer = load_selected_dispatch(root, context, selected_row)
    stage_id = selected_row&.dig("scope", "stage_id").to_s
    judgment_document, judgment_pointer, _graph_dispatch, graph_dispatch_pointer, judgment_validation, migration_bridge, profile_release_pointer = load_and_validate_judgment(
      root,
      judgment,
      selected_row,
      dispatch,
      dispatch_pointer,
      stage_id,
      judgment_registry,
      validator: contextual_judgment_validator
    )
    frontier = frontier_set(root, context)
    state, reason, action, owner, founder_stop, correction, resolved_stage_id = decision_for(
      root: root,
      context: context,
      registry: registry,
      judgment_registry: judgment_registry,
      selected_row: selected_row,
      dispatch: dispatch,
      judgment: judgment_document,
      frontier_set: frontier
    )

    current_next_pointer = pointer_for(root, context.fetch("path"), "current_next_v2")
    inputs = {
      "current_next" => current_next_pointer,
      "director_dispatch_index" => context.fetch("director_dispatch_index_binding").merge("role" => "director_dispatch_index_v4"),
      "graph_stage_registry" => registry_pointer,
      "judgment_registry" => judgment_registry_pointer,
      "selected_dispatch" => dispatch_pointer,
      "contextual_judgment" => judgment_pointer,
      "graph_dispatch" => graph_dispatch_pointer,
      "judgment_profile_release" => profile_release_pointer
    }
    lifecycle = dispatch&.dig("lifecycle", "current_state").to_s
    closure = lifecycle == "promoted" || (context.dig("selection", "kind").to_s == "no_actionable_unit" && !resolved_stage_id.to_s.empty?)
    selected_action_code = context.dig("selection", "kind").to_s == "next_action" ? context.dig("selection_row", "action_code").to_s : ""
    projected_authority_requirements = combined_authority_requirements(
      stage: stage_for(registry, resolved_stage_id),
      closure: closure,
      action_code: selected_action_code
    )
    authority_requirements = state == "await_founder_decision" ? projected_authority_requirements : []
    receipt_contract = authority_receipt_contract(selected_action_code, authority_requirements)
    result = {
      "schema_version" => SCHEMA_VERSION,
      "artifact_type" => "graph_run_controller_state",
      "authority" => {
        "mode" => "read_only_dry_run",
        "graph_shadow_only" => true,
        "provider_launch_performed" => false,
        "write_performed" => false,
        "creative_judgment_authored" => false,
        "creative_pass_inferred" => false,
        "execution_enabled" => false,
        "activation_status" => "blocked_shadow_probe",
        "activation_blockers" => ACTIVATION_BLOCKERS
      },
      "run" => context.dig("document", "run").to_s,
      "frontier" => {
        "selection_kind" => context.dig("selection", "kind").to_s,
        "selection_id" => context.dig("selection", "id"),
        "dispatch_id" => context.dig("selection", "dispatch_id"),
        "stage_id" => resolved_stage_id.to_s.empty? ? nil : resolved_stage_id,
        "owner" => context.dig("document", "owner")
      },
      "frontier_set" => frontier,
      "input_bindings" => inputs,
      "decision" => {
        "state" => state,
        "reason_code" => reason,
        "action_code" => action,
        "owner" => owner.to_s.empty? ? nil : owner,
        "founder_stop" => founder_stop,
        "authority_requirements" => authority_requirements,
        "authority_receipt_contract" => receipt_contract,
        "execution_authorized" => false,
        "state_semantics" => "advisory_shadow_plan_only",
        "provider_action" => "not_performed_plan_only",
        "write_action" => "not_performed_stdout_only"
      },
      "correction_plan" => correction,
      "validation" => {
        "contextual_judgment" => judgment_validation,
        "legacy_current_next_ddi_boundary" => "structural_subset_only_activation_blocked"
      },
      "migration_bridge" => migration_bridge,
      "evidence" => {
        "dispatch_lifecycle" => dispatch&.dig("lifecycle", "current_state"),
        "judgment_decision" => judgment_document&.fetch("decision", nil),
        "judgment_next_edge" => judgment_document&.fetch("next_edge", nil),
        "director_disposition" => dispatch&.dig("director_review", "disposition"),
        "submission_number" => dispatch&.dig("review_submission", "submission_number"),
        "stage_founder_gate" => (stage_for(registry, resolved_stage_id) || {})["founder_gate"].to_s.match?(/\AG[0-4]\z/) ? stage_for(registry, resolved_stage_id)["founder_gate"] : nil
      }
    }
    event_payload = {
      "run" => result["run"],
      "frontier" => result["frontier"],
      "frontier_set" => frontier,
      "input_bindings" => inputs,
      "decision" => result["decision"],
      "correction_plan" => correction,
      "validation" => result["validation"],
      "migration_bridge" => migration_bridge
    }
    payload_sha = digest_value(event_payload)
    result["event_intent"] = {
      "append_only" => true,
      "write_performed" => false,
      "intent_type" => INTENT_TYPES.fetch(state),
      "previous_event_sha256" => previous_event_sha256,
      "payload_sha256" => payload_sha,
      "event_sha256" => digest_value("previous_event_sha256" => previous_event_sha256, "payload_sha256" => payload_sha),
      "idempotency_key" => digest_value("run" => result["run"], "frontier" => result["frontier"], "inputs" => inputs, "decision" => result["decision"], "correction_plan" => correction)
    }
    result
  rescue IdolCurrentNextV2::Error => error
    raise Error, error.message
  end
end
