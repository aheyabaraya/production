# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "idol_graph_judgment_profile_promotion_contract"
require_relative "idol_run_followup_sidecar"
require_relative "idol_source_connection_contract"

module IdolRoleContextPack
  class ContractError < StandardError; end

  IMPLEMENTATION_ROOT = Pathname.new(__dir__).join("..", "..").expand_path.cleanpath
  SCHEMA_VERSION = "idol-role-context-pack.v1"
  PROJECTION_REGISTRY_RELATIVE = "automation/harness-role-context-projection.yaml"
  PROFILE_REGISTRY_RELATIVE = "automation/harness-skill-load-profiles.yaml"
  GRAPH_PROJECTION_REGISTRY_RELATIVE = "automation/graph-role-context-projection.yaml"
  GRAPH_PROFILE_REGISTRY_RELATIVE = "automation/graph-skill-load-profiles.yaml"
  GRAPH_ROUTING_REGISTRY_RELATIVE = "automation/graph-default-routing.yaml"
  GRAPH_JUDGMENT_REGISTRY_RELATIVE = "automation/graph-creative-judgment-registry.yaml"
  GRAPH_JUDGMENT_PROFILE_RELEASE_SCHEMA_RELATIVE = "schemas/graph-creative-judgment-profile-release.schema.json"
  GRAPH_JUDGMENT_PROFILE_RELEASE_ROOT = "automation/graph-creative-judgment-profile-releases"
  GRAPH_JUDGMENT_PROFILE_RELEASE_VERSION = "idol-graph-creative-judgment-profile-release.v1"
  GRAPH_JUDGMENT_PROFILE_RELEASE_AUTHORITY = "profile_snapshot_no_creative_or_promotion_authority"
  GRAPH_JUDGMENT_APPLICABILITY_TAGS = %w[
    motion_reference composition_function_present member_absent no_material_prop no_performance_job
  ].freeze
  PROVIDER_REGISTRY_RELATIVE = "automation/harness-provider-profile-registry.yaml"
  DIRECTOR_ROLES = %w[overall_director creative_development_director edit_director].freeze
  GRAPH_DIRECTOR_ROLES = %w[
    planning_cdd_p1 planning_cdd_p2 planning_cdd_p3_ci section_cluster_cdd_ci
  ].freeze
  GRAPH_SWITCH_RECEIPT_FIELDS = %w[
    receipt_id founder_authority graph_revision switch_boundary source_set_sha256 verified_at
  ].freeze
  GRAPH_DISPATCH_OUTPUT_WRITER_FIELDS = %w[owner role session_id].freeze
  GRAPH_DISPATCH_REVIEWER_FIELDS = %w[owner role lane_id session_id logical_lineage_id].freeze
  GRAPH_DISPATCH_RETURN_RECIPIENT_FIELDS = %w[owner role return_route].freeze
  GRAPH_PROFILE_DISPATCH_ROLES = {
    "overall_director" => "overall_director",
    "planning_cdd_p1" => "planning_cdd",
    "planning_cdd_p2" => "planning_cdd",
    "planning_cdd_p3_ci" => "planning_cdd",
    "section_cluster_cdd_ci" => "section_cluster_cdd",
    "section_image_motion_worker" => "section_image_motion_worker",
    "edit_director" => "edit_director"
  }.freeze
  GRAPH_WRITER = "graph_v2"
  LEGACY_WRITER = "legacy_pinned"
  LEGAL_NEXT = {
    "startup_admission" => %w[prepared compiled hold],
    "prepared" => %w[launched hold],
    "launched" => %w[returned hold],
    "returned" => %w[reviewed hold],
    "reviewed" => %w[promoted hold],
    "promoted" => [],
    "hold" => []
  }.freeze
  STRUCTURED_EXTENSIONS = %w[.json .yaml .yml .rb .py .js .ts .toml].freeze
  FOUNDER_QUALITY_PATTERN_LIMIT = 12
  RESOLVED_PROVIDER_BINDING_FIELDS = %w[
    status logical_profile_alias provider runtime_surface registry_path registry_sha256
    provider_profile_id provider_source_path provider_source_sha256 exact_model reasoning_effort fallback_policy
  ].freeze
  REQUESTED_PROVIDER_ATTESTATION_FIELDS = %w[
    logical_profile_alias provider_profile_id exact_model reasoning_effort provider_source_sha256
  ].freeze
  REQUESTED_PROVIDER_ATTESTATION_INCOMPLETE = "role_context_requested_provider_attestation_incomplete"
  SELECTED_PROVIDER_ROLE_UNSUPPORTED_PREFIX = "role_context_selected_provider_role_unsupported:"
  SELECTED_PROVIDER_MISMATCH_PREFIX = "role_context_selected_provider_mismatch:"

  module_function

  def profile_owns_stage?(profile, checkpoint:, stage_id:, writer:)
    stage = stage_id.to_s
    return true if writer.to_s == LEGACY_WRITER && stage == "startup_admission"
    return true if Array(profile["stage_ids"]).map(&:to_s).include?(stage)
    return true if writer.to_s == LEGACY_WRITER &&
                   profile["profile_id"].to_s == "harness_maintenance" &&
                   profile["maintenance_only"] == true &&
                   Array(profile["maintenance_surface_ids"]).map(&:to_s).include?(checkpoint["checkpoint_id"].to_s) &&
                   stage == checkpoint["checkpoint_id"].to_s

    false
  end

  def build(root:, run_root:, assignment_id:, role:, profile_id:, checkpoint_id:, stage_id:,
            section_ids: [], source_envelope: nil, current_state: "prepared", scope: {},
            non_scope: [], authority: {}, founder_epoch: "unbound", founder_locks: [],
            creative_sources: [], output_contract: {}, hold_conditions: [], return_recipient: {},
            provider: "grok", runtime_surface: "registered_provider_surface", live_run_state: nil,
            founder_quality_context: nil, writer: LEGACY_WRITER, run_class: nil,
            switch_receipt: nil, active_writers: nil,
            requested_logical_profile_alias: nil, requested_provider_profile_id: nil,
            requested_exact_model: nil, requested_reasoning_effort: nil,
            requested_provider_source_sha256: nil)
    root = Pathname.new(root).expand_path.cleanpath
    selection = select_registry_pair(
      root: root,
      writer: writer,
      run_class: run_class,
      switch_receipt: switch_receipt,
      active_writers: active_writers
    )
    projection_path = contained_file(root, selection.fetch("projection_registry_path"))
    profile_path = contained_file(root, selection.fetch("profile_registry_path"))
    projection_registry = load_mapping(projection_path)
    profile_registry = load_mapping(profile_path)
    validate_projection_registry!(projection_registry, profile_registry, writer: selection.fetch("writer"))

    profile = Array(profile_registry["profiles"]).find do |row|
      row.is_a?(Hash) && row["profile_id"].to_s == profile_id.to_s
    end
    raise ContractError, "unknown role-context profile: #{profile_id}" unless profile
    raise ContractError, "role-context role differs from selected profile" unless profile["role"].to_s == role.to_s

    checkpoint = Array(profile.dig("phase_load", "checkpoints")).find do |row|
      row.is_a?(Hash) && row["checkpoint_id"].to_s == checkpoint_id.to_s
    end
    raise ContractError, "unknown role-context checkpoint: #{profile_id}.#{checkpoint_id}" unless checkpoint
    unless profile_owns_stage?(
      profile,
      checkpoint: checkpoint,
      stage_id: stage_id,
      writer: selection.fetch("writer")
    )
      raise ContractError, "role-context stage is outside selected profile"
    end
    if selection.fetch("writer") == GRAPH_WRITER && checkpoint.key?("judgment_profile_id") &&
       !Array(checkpoint["stage_ids"]).map(&:to_s).include?(stage_id.to_s)
      raise ContractError, "role-context stage is outside selected checkpoint"
    end

    skill_map = binding_map(profile_registry, "skill_bindings")
    read_map = binding_map(profile_registry, "read_bindings")
    slices = []
    Array(checkpoint["required_skill_ids"]).each do |binding_id|
      row = skill_map[binding_id.to_s]
      raise ContractError, "missing role-context skill binding: #{binding_id}" unless row
      slices.concat(project_binding(root, projection_registry, profile_id, row, "skill"))
    end
    Array(checkpoint["required_read_ids"]).each do |binding_id|
      row = read_map[binding_id.to_s]
      raise ContractError, "missing role-context read binding: #{binding_id}" unless row
      slices.concat(project_binding(root, projection_registry, profile_id, row, "linked_read"))
    end
    raise ContractError, "role-context pack has no instruction slices" if slices.empty?

    provider_binding, provider_holds = resolve_provider(
      root: root,
      role: role,
      provider: provider,
      runtime_surface: runtime_surface,
      logical_profile_alias: provider_alias(
        profile,
        role,
        graph_native: selection.fetch("writer") == GRAPH_WRITER
      )
    )
    attestation_holds = apply_selected_provider_profile!(
      root: root,
      role: role,
      provider: provider,
      runtime_surface: runtime_surface,
      provider_binding: provider_binding,
      requested_logical_profile_alias: requested_logical_profile_alias,
      requested_provider_profile_id: requested_provider_profile_id,
      requested_exact_model: requested_exact_model,
      requested_reasoning_effort: requested_reasoning_effort,
      requested_provider_source_sha256: requested_provider_source_sha256
    )
    creative_pointers = normalize_creative_sources(
      root,
      creative_sources,
      graph_native: selection.fetch("writer") == GRAPH_WRITER
    )
    quality_context = normalize_founder_quality_context(root, founder_quality_context)
    creative_judgment_contract = if selection.fetch("writer") == GRAPH_WRITER
                                   build_graph_judgment_contract(
                                     root: root,
                                     checkpoint: checkpoint,
                                     stage_id: stage_id,
                                     role: role
                                   )
                                 end
    state = current_state.to_s
    source_envelope ||= {"kind" => "profile_checkpoint", "path" => nil, "sha256" => nil}
    source_envelope = normalize_source_envelope(root, source_envelope)
    graph_dispatch_identity = if selection.fetch("writer") == GRAPH_WRITER && !creative_judgment_contract.nil?
                                case source_envelope["kind"]
                                when "department_dispatch"
                                  normalize_graph_dispatch_identity(
                                    root,
                                    source_envelope,
                                    assignment_id: assignment_id,
                                    run_root: run_root,
                                    profile_id: profile_id,
                                    section_ids: section_ids,
                                    authority: authority,
                                    return_recipient: return_recipient,
                                    current_state: state
                                  )
                                when "startup_admission"
                                  unless state == "prepared"
                                    raise ContractError, "Graph startup judgment projection must remain prepared"
                                  end
                                  nil
                                else
                                  raise ContractError, "Graph judgment checkpoint requires a startup projection or hash-bound Department Dispatch"
                                end
                              end
    original_words = slices.sum { |row| row.delete("_original_word_count").to_i }
    projected_words = slices.sum { |row| row["content"].to_s.scan(/\S+/).length }
    ratio = original_words.zero? ? 0.0 : ((original_words - projected_words).to_f / original_words).round(4)
    source_set = {
      "projection_registry" => file_pointer(root, projection_path),
      "profile_registry" => file_pointer(root, profile_path),
      "activation_binding" => selection.fetch("activation_binding"),
      "source_envelope" => source_envelope,
      "instructions" => slices.map { |row| row.slice("binding_id", "path", "whole_file_sha256", "locator", "fragment_sha256") },
      "creative_sources" => creative_pointers,
      "founder_quality_context" => quality_context,
      "provider" => provider_binding.slice("provider", "provider_profile_id", "provider_source_sha256")
    }
    source_set["creative_judgment_contract"] = creative_judgment_contract unless creative_judgment_contract.nil?
    source_set["graph_dispatch_identity"] = graph_dispatch_identity unless graph_dispatch_identity.nil?
    instruction_content = slices.each_with_object([]) do |row, values|
      values << row["content"] unless row["content"].nil?
    end.join("\n")
    holds = provider_holds + attestation_holds

    pack = {
      "schema_version" => SCHEMA_VERSION,
      "status" => holds.empty? ? "pass" : "hold",
      "authority" => "derived_read_only_no_creative_or_promotion_authority",
      "pack_id" => pack_id(assignment_id, profile_id, checkpoint_id),
      "activation_binding" => selection.fetch("activation_binding"),
      "source_envelope" => source_envelope,
      "identity" => {
        "run_root" => run_root.to_s,
        "assignment_id" => assignment_id.to_s,
        "role" => role.to_s,
        "profile_id" => profile_id.to_s,
        "checkpoint_id" => checkpoint_id.to_s,
        "stage_id" => stage_id.to_s,
        "section_ids" => Array(section_ids).map(&:to_s).uniq
      },
      "unload_after" => checkpoint.fetch("unload_after").to_s,
      "current_node" => {
        "state" => state,
        "legal_next" => LEGAL_NEXT.fetch(state, %w[hold]),
        "scope" => scope.is_a?(Hash) ? scope : {"description" => scope.to_s},
        "non_scope" => Array(non_scope).map(&:to_s).reject(&:empty?).uniq,
        "stop_conditions" => Array(hold_conditions).map(&:to_s).reject(&:empty?).uniq,
        "return_recipient" => return_recipient.is_a?(Hash) ? return_recipient : {"owner" => return_recipient.to_s}
      },
      "authority_binding" => authority.is_a?(Hash) ? authority : {"owner" => authority.to_s},
      "founder_context" => {
        "decision_epoch" => founder_epoch,
        "locks" => Array(founder_locks)
      },
      "creative_source_pointers" => creative_pointers,
      "dependency_edges" => dependency_edges(role, assignment_id, return_recipient, provider_binding, quality_context),
      "instruction_slices" => slices,
      "output_contract" => output_contract.is_a?(Hash) ? output_contract : {"description" => output_contract.to_s},
      "provider_binding" => provider_binding,
      "hold_reasons" => holds,
      "projection" => {
        "registry_path" => selection.fetch("projection_registry_path"),
        "registry_sha256" => Digest::SHA256.file(projection_path).hexdigest,
        "profile_registry_path" => selection.fetch("profile_registry_path"),
        "profile_registry_sha256" => Digest::SHA256.file(profile_path).hexdigest,
        "source_set_sha256" => structured_sha256(source_set),
        "instruction_content_sha256" => Digest::SHA256.hexdigest(instruction_content),
        "original_word_count" => original_words,
        "projected_word_count" => projected_words,
        "reduction_ratio" => ratio,
        "pack_digest" => "0" * 64,
        "replacement_rule" => "runtime_pack_replaces_broad_instruction_reads_and_is_not_an_additional_required_layer",
        "invalidation_policy" => "bound_fragment_or_exact_dependency_change_only_except_always_on_authority",
        "model_facing_creative_sources" => IdolSourceConnectionContract.project_rows(root, creative_pointers)
      }
    }
    normalized_live = normalize_live_run_state(live_run_state)
    pack["live_run_state"] = normalized_live if live_run_state_present?(normalized_live)
    pack["founder_quality_context"] = quality_context unless quality_context.nil?
    pack["creative_judgment_contract"] = creative_judgment_contract unless creative_judgment_contract.nil?
    pack["graph_dispatch_identity"] = graph_dispatch_identity unless graph_dispatch_identity.nil?
    pack["projection"]["pack_digest"] = structured_sha256(pack.reject { |key, _| key == "projection" }.merge(
      "projection" => pack["projection"].reject { |key, _| key == "pack_digest" }
    ))
    pack
  end

  def build_from_dispatch(root:, dispatch_path:)
    root = Pathname.new(root).expand_path.cleanpath
    path = contained_file(root, dispatch_path)
    document = load_mapping(path)
    launch = document.fetch("launch")
    compiled = launch.fetch("compiled_launch_prompt")
    selected = compiled.fetch("selected_profile")
    task = launch.fetch("task")
    exact_scope = task.fetch("exact_scope")
    lineage = document.fetch("lineage")
    founder = launch.fetch("founder_context")
    relative = path.relative_path_from(root).to_s
    build(
      root: root,
      run_root: document.fetch("run"),
      assignment_id: document.fetch("dispatch_id"),
      role: task.fetch("role"),
      profile_id: selected.fetch("profile_id"),
      checkpoint_id: selected.fetch("checkpoint_id"),
      stage_id: exact_scope.fetch("stage_id"),
      section_ids: exact_scope.fetch("section_ids"),
      source_envelope: {"kind" => "department_dispatch", "path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest},
      current_state: document.dig("lifecycle", "current_state") || "prepared",
      scope: exact_scope,
      non_scope: launch.dig("authority", "must_not") || [],
      authority: launch.fetch("authority"),
      founder_epoch: founder.fetch("decision_epoch"),
      founder_locks: founder.fetch("locks"),
      creative_sources: launch.fetch("sources"),
      output_contract: launch.fetch("bounded_output"),
      hold_conditions: launch.fetch("hold_conditions"),
      return_recipient: launch.fetch("recipient"),
      provider: lineage.fetch("provider"),
      runtime_surface: lineage.fetch("runtime_surface"),
      live_run_state: extract_live_run_state(root, document),
      founder_quality_context: extract_founder_quality_context(
        root,
        document,
        role: task.fetch("role"),
        profile_id: selected.fetch("profile_id"),
        stage_id: exact_scope.fetch("stage_id"),
        section_ids: exact_scope.fetch("section_ids")
      )
    )
  end

  def render_runtime_json(pack)
    runtime = {
      "schema_version" => pack.fetch("schema_version"),
      "status" => pack.fetch("status"),
      "authority" => pack.fetch("authority"),
      "pack_id" => pack.fetch("pack_id"),
      "source_envelope" => pack.fetch("source_envelope"),
      "identity" => pack.fetch("identity"),
      "unload_after" => pack.fetch("unload_after"),
      "current_node" => pack.fetch("current_node"),
      "authority_binding" => pack.fetch("authority_binding"),
      "founder_context" => pack.fetch("founder_context"),
      "creative_source_pointers" => model_facing_creative_sources(pack),
      "dependency_edges" => pack.fetch("dependency_edges"),
      "instruction_slices" => pack.fetch("instruction_slices"),
      "output_contract" => pack.fetch("output_contract"),
      "provider_binding" => pack.fetch("provider_binding"),
      "hold_reasons" => pack.fetch("hold_reasons"),
      "projection" => pack.fetch("projection")
    }
    runtime["activation_binding"] = pack["activation_binding"] if pack.key?("activation_binding")
    runtime["live_run_state"] = pack["live_run_state"] if pack.key?("live_run_state")
    runtime["founder_quality_context"] = pack["founder_quality_context"] if pack.key?("founder_quality_context")
    runtime["creative_judgment_contract"] = pack["creative_judgment_contract"] if pack.key?("creative_judgment_contract")
    runtime["graph_dispatch_identity"] = pack["graph_dispatch_identity"] if pack.key?("graph_dispatch_identity")
    "ROLE_CONTEXT_PACK_V1 #{JSON.generate(canonical_value(runtime))}"
  end

  def model_facing_creative_sources(pack)
    facing = pack.dig("projection", "model_facing_creative_sources")
    return facing if facing.is_a?(Array)

    pack.fetch("creative_source_pointers")
  end

  def validate_pack(root:, pack:, validation_mode: "active_promotion")
    root = Pathname.new(root).expand_path.cleanpath
    errors = []
    unless %w[active_promotion historical_audit profile_evolution_evidence].include?(validation_mode.to_s)
      return ["role context pack validation_mode must be active_promotion, historical_audit, or profile_evolution_evidence"]
    end
    historical_audit = validation_mode.to_s == "historical_audit"
    profile_evolution_evidence = validation_mode.to_s == "profile_evolution_evidence"
    errors << "role context pack schema_version is not active" unless pack["schema_version"] == SCHEMA_VERSION
    errors << "role context pack authority is invalid" unless pack["authority"] == "derived_read_only_no_creative_or_promotion_authority"
    errors << "role context pack replacement rule is invalid" unless pack.dig("projection", "replacement_rule") == "runtime_pack_replaces_broad_instruction_reads_and_is_not_an_additional_required_layer"
    projection = pack["projection"].to_h
    judgment_contract = pack["creative_judgment_contract"].to_h
    released_judgment_history = (historical_audit || profile_evolution_evidence) &&
                                judgment_contract["profile_release"].is_a?(Hash) &&
                                judgment_contract.dig("registry", "path").to_s == GRAPH_JUDGMENT_REGISTRY_RELATIVE
    if historical_audit && !released_judgment_history
      errors << "historical_audit requires an immutable Graph judgment profile release"
    end
    activation_present = pack["activation_binding"].is_a?(Hash)
    activation = activation_present ? pack.fetch("activation_binding") : {
      "writer" => LEGACY_WRITER,
      "run_class" => "legacy_or_unspecified",
      "switch_receipt" => nil
    }
    begin
      selection = if (historical_audit || profile_evolution_evidence) && activation["writer"] == GRAPH_WRITER
                    receipt = validate_historical_graph_switch_receipt!(activation["switch_receipt"])
                    {
                      "writer" => GRAPH_WRITER,
                      "projection_registry_path" => GRAPH_PROJECTION_REGISTRY_RELATIVE,
                      "profile_registry_path" => GRAPH_PROFILE_REGISTRY_RELATIVE,
                      "activation_binding" => {"writer" => GRAPH_WRITER, "run_class" => "new_run", "switch_receipt" => receipt}
                    }
                  else
                    select_registry_pair(
                      root: root,
                      writer: activation.fetch("writer"),
                      run_class: activation["run_class"],
                      switch_receipt: activation["switch_receipt"]
                    )
                  end
      errors << "role context projection registry differs from selected writer" unless selection["projection_registry_path"] == projection["registry_path"]
      errors << "role context profile registry differs from selected writer" unless selection["profile_registry_path"] == projection["profile_registry_path"]
      if activation_present
        errors << "role context activation binding is stale" unless canonical_value(selection["activation_binding"]) == canonical_value(activation)
      end
    rescue ContractError, KeyError => e
      errors << "role context activation binding is invalid: #{e.message}"
    end
    validate_current_file_pointer(
      root: root,
      relative: projection["registry_path"],
      expected_sha256: projection["registry_sha256"],
      label: "role context projection registry",
      errors: errors
    )
    unless released_judgment_history && !profile_evolution_evidence
      validate_current_file_pointer(
        root: root,
        relative: projection["profile_registry_path"],
        expected_sha256: projection["profile_registry_sha256"],
        label: "role context profile registry",
        errors: errors
      )
    end
    source_envelope = pack["source_envelope"].to_h
    if source_envelope["path"].nil?
      errors << "role context source envelope has a SHA-256 without a path" unless source_envelope["sha256"].nil?
    else
      validate_current_file_pointer(
        root: root,
        relative: source_envelope["path"],
        expected_sha256: source_envelope["sha256"],
        label: "role context source envelope",
        errors: errors
      )
    end
    Array(pack["creative_source_pointers"]).each_with_index do |row, index|
      validate_current_file_pointer(
        root: root,
        relative: row["path"],
        expected_sha256: row["sha256"],
        label: "creative_source_pointers[#{index}]",
        errors: errors
      )
      if activation["writer"] == GRAPH_WRITER
        errors << "creative_source_pointers[#{index}] graph locator is missing" if row["locator"].to_s.empty?
        errors << "creative_source_pointers[#{index}] graph function is missing" if row["function"].to_s.empty?
      end
    end
    facing = pack.dig("projection", "model_facing_creative_sources")
    if facing
      expected_facing = IdolSourceConnectionContract.project_rows(root, pack["creative_source_pointers"])
      unless facing == expected_facing
        errors << "projection.model_facing_creative_sources drifted from envelope creative_source_pointers"
      end
      Array(facing).each_with_index do |row, index|
        next unless row.is_a?(Hash)

        sha_keys = row.keys.map(&:to_s).select { |key| key.include?("sha256") }
        errors << "projection.model_facing_creative_sources[#{index}] leaked #{sha_keys.join(', ')}" unless sha_keys.empty?
      end
    end
    if activation["writer"] == GRAPH_WRITER
      forbidden = %w[url urls raw_pool raw_search_pool full_url_list worker_transcript completed_worker_transcript superseded_prose]
      forbidden.each do |key|
        errors << "graph role context pack contains forbidden field: #{key}" if contains_key?(pack, key)
      end
      begin
        projection_registry = load_mapping(contained_file(root, projection["registry_path"]))
        profile_registry = load_mapping(contained_file(root, projection["profile_registry_path"]))
        identity = pack["identity"].to_h
        role_profile = Array(profile_registry["profiles"]).find { |row| row.to_h["profile_id"].to_s == identity["profile_id"].to_s }
        raise ContractError, "unknown role-context profile: #{identity['profile_id']}" unless role_profile
        unless role_profile["role"].to_s == identity["role"].to_s
          raise ContractError, "role-context role differs from selected profile"
        end
        unless Array(role_profile["stage_ids"]).map(&:to_s).include?(identity["stage_id"].to_s)
          raise ContractError, "role-context stage is outside selected profile"
        end
        checkpoint = Array(role_profile.to_h.dig("phase_load", "checkpoints")).find { |row| row.to_h["checkpoint_id"].to_s == identity["checkpoint_id"].to_s }
        raise ContractError, "unknown role-context checkpoint: #{identity['profile_id']}.#{identity['checkpoint_id']}" unless checkpoint
        if checkpoint.key?("judgment_profile_id") && !Array(checkpoint["stage_ids"]).map(&:to_s).include?(identity["stage_id"].to_s)
          raise ContractError, "role-context stage is outside selected checkpoint"
        end
        if checkpoint["judgment_profile_id"].to_s.empty?
          errors << "non-judgment Graph checkpoint must not carry graph_dispatch_identity" if pack.key?("graph_dispatch_identity")
        else
          case source_envelope["kind"]
          when "startup_admission"
            errors << "Graph startup judgment projection must remain prepared" unless pack.dig("current_node", "state") == "prepared"
            errors << "Graph startup judgment projection must not carry graph_dispatch_identity" if pack.key?("graph_dispatch_identity")
          when "department_dispatch"
            expected_dispatch_identity = normalize_graph_dispatch_identity(
              root,
              source_envelope,
              assignment_id: identity["assignment_id"],
              run_root: identity["run_root"],
              profile_id: identity["profile_id"],
              section_ids: identity["section_ids"],
              authority: pack["authority_binding"],
              return_recipient: pack.dig("current_node", "return_recipient"),
              current_state: pack.dig("current_node", "state")
            )
            unless canonical_value(pack["graph_dispatch_identity"]) == canonical_value(expected_dispatch_identity)
              errors << "graph_dispatch_identity differs from the exact Graph Dispatch snapshot"
            end
          else
            raise ContractError, "Graph judgment checkpoint requires a startup projection or hash-bound Department Dispatch"
          end
        end

        skill_map = binding_map(profile_registry, "skill_bindings")
        read_map = binding_map(profile_registry, "read_bindings")
        expected_slices = []
        Array(checkpoint["required_skill_ids"]).each do |binding_id|
          row = skill_map[binding_id.to_s]
          raise ContractError, "missing role-context skill binding: #{binding_id}" unless row
          expected_slices.concat(project_binding(root, projection_registry, identity["profile_id"], row, "skill"))
        end
        Array(checkpoint["required_read_ids"]).each do |binding_id|
          row = read_map[binding_id.to_s]
          raise ContractError, "missing role-context read binding: #{binding_id}" unless row
          # Historical judgment audit uses the immutable registry slice and
          # policy/profile release captured by the original pack. Resolving
          # this one binding through today's row would turn an expected
          # release update into a false stale-source failure. All other
          # bindings remain current and fully validated.
          next if historical_audit && released_judgment_history && binding_id.to_s == "graph_creative_judgment_registry"

          expected_slices.concat(project_binding(root, projection_registry, identity["profile_id"], row, "linked_read"))
        end
        expected_original_words = expected_slices.sum { |row| row.delete("_original_word_count").to_i }
        expected_projected_words = expected_slices.sum { |row| row["content"].to_s.scan(/\S+/).length }
        actual_slices = Array(pack["instruction_slices"])
        if historical_audit && released_judgment_history
          actual_slices = actual_slices.reject { |row| row["binding_id"].to_s == "graph_creative_judgment_registry" }
        end
        unless canonical_value(actual_slices) == canonical_value(expected_slices)
          errors << "graph instruction_slices differ from the exact profile checkpoint projection"
        end
        unless historical_audit || projection["original_word_count"].to_i == expected_original_words
          errors << "graph original_word_count differs from the exact profile checkpoint projection"
        end
        actual_projected_words = Array(pack["instruction_slices"]).sum { |row| row["content"].to_s.scan(/\S+/).length }
        unless projection["projected_word_count"].to_i == (historical_audit && released_judgment_history ? actual_projected_words : expected_projected_words)
          errors << "graph projected_word_count differs from the exact profile checkpoint projection"
        end
        expected_ratio = expected_original_words.zero? ? 0.0 : ((expected_original_words - expected_projected_words).to_f / expected_original_words).round(4)
        unless historical_audit || projection["reduction_ratio"].to_f == expected_ratio
          errors << "graph reduction_ratio differs from the exact profile checkpoint projection"
        end
        unless pack["unload_after"].to_s == checkpoint["unload_after"].to_s && !pack["unload_after"].to_s.empty?
          errors << "graph unload_after differs from the exact profile checkpoint"
        end
        scope = pack.dig("current_node", "scope").to_h
        if scope.key?("stage_id") && scope["stage_id"].to_s != identity["stage_id"].to_s
          errors << "graph current-node scope stage differs from identity"
        end
        if scope.key?("section_ids") && Array(scope["section_ids"]).map(&:to_s) != Array(identity["section_ids"]).map(&:to_s)
          errors << "graph current-node scope sections differ from identity"
        end
        if checkpoint["judgment_profile_id"].to_s.empty?
          errors << "non-judgment Graph checkpoint must not carry a creative judgment contract" if pack.key?("creative_judgment_contract")
        else
          errors.concat(validate_graph_judgment_contract(
            root: root,
            contract: pack["creative_judgment_contract"],
            checkpoint: checkpoint.to_h,
            stage_id: identity["stage_id"],
            role: identity["role"],
            validation_mode: validation_mode
          ))
        end
      rescue ContractError, KeyError => e
        errors << "graph creative judgment contract is invalid: #{e.message}"
      end
    else
      begin
        projection_registry = load_mapping(contained_file(root, projection["registry_path"]))
        profile_registry = load_mapping(contained_file(root, projection["profile_registry_path"]))
        identity = pack["identity"].to_h
        role_profile = Array(profile_registry["profiles"]).find { |row| row.to_h["profile_id"].to_s == identity["profile_id"].to_s }
        raise ContractError, "unknown role-context profile: #{identity['profile_id']}" unless role_profile
        unless role_profile["role"].to_s == identity["role"].to_s
          raise ContractError, "role-context role differs from selected profile"
        end
        checkpoint = Array(role_profile.to_h.dig("phase_load", "checkpoints")).find { |row| row.to_h["checkpoint_id"].to_s == identity["checkpoint_id"].to_s }
        raise ContractError, "unknown role-context checkpoint: #{identity['profile_id']}.#{identity['checkpoint_id']}" unless checkpoint
        unless profile_owns_stage?(
          role_profile,
          checkpoint: checkpoint,
          stage_id: identity["stage_id"],
          writer: LEGACY_WRITER
        )
          raise ContractError, "role-context stage is outside selected profile"
        end
        skill_map = binding_map(profile_registry, "skill_bindings")
        read_map = binding_map(profile_registry, "read_bindings")
        expected_slices = []
        Array(checkpoint["required_skill_ids"]).each do |binding_id|
          row = skill_map[binding_id.to_s]
          raise ContractError, "missing role-context skill binding: #{binding_id}" unless row
          expected_slices.concat(project_binding(root, projection_registry, identity["profile_id"], row, "skill"))
        end
        Array(checkpoint["required_read_ids"]).each do |binding_id|
          row = read_map[binding_id.to_s]
          raise ContractError, "missing role-context read binding: #{binding_id}" unless row
          expected_slices.concat(project_binding(root, projection_registry, identity["profile_id"], row, "linked_read"))
        end
        expected_slices.each { |row| row.delete("_original_word_count") }
        unless canonical_value(Array(pack["instruction_slices"])) == canonical_value(expected_slices)
          errors << "legacy instruction_slices differ from the exact profile checkpoint projection"
        end
      rescue ContractError, KeyError => e
        errors << "legacy checkpoint slice projection is invalid: #{e.message}"
      end
    end
    quality_context = pack["founder_quality_context"]
    if quality_context.is_a?(Hash)
      source = quality_context["source_sidecar"].to_h
      validate_current_file_pointer(
        root: root,
        relative: source["path"],
        expected_sha256: source["sha256"],
        label: "founder quality context source sidecar",
        errors: errors
      )
      errors << "founder quality context must come from active v3 sidecar bytes" unless source["schema_version"] == IdolRunFollowupSidecar::V3_VERSION
      context_basis = quality_context.reject { |key, _| key == "context_digest" }
      errors << "founder quality context digest is stale" unless structured_sha256(context_basis) == quality_context["context_digest"]
      IdolRunFollowupSidecar::RAW_FEEDBACK_KEYS.each do |key|
        errors << "founder quality context must not carry raw feedback key #{key}" if contains_key?(quality_context, key)
      end
    end
    Array(pack["instruction_slices"]).each_with_index do |row, index|
      if historical_audit && released_judgment_history && row["binding_id"].to_s == "graph_creative_judgment_registry"
        errors << "historical judgment-registry slice path is invalid" unless row["path"].to_s == GRAPH_JUDGMENT_REGISTRY_RELATIVE
        errors << "historical judgment-registry slice whole-file SHA differs from its contract provenance" unless row["whole_file_sha256"].to_s == judgment_contract.dig("registry", "sha256").to_s
        if row["content"]
          errors << "historical judgment-registry slice fragment SHA-256 is stale" unless Digest::SHA256.hexdigest(row["content"].to_s) == row["fragment_sha256"].to_s
        end
        next
      end
      begin
        path = contained_file(root, row.fetch("path"))
        actual = Digest::SHA256.file(path).hexdigest
        errors << "instruction_slices[#{index}] whole-file SHA-256 is stale" unless actual == row["whole_file_sha256"]
        case row.dig("locator", "type")
        when "whole_file"
          content = path.read
          errors << "instruction_slices[#{index}] full-file content changed" unless content == row["content"]
        when "markdown_heading"
          content = markdown_heading(path.read, row.dig("locator", "heading"), row["path"])
          errors << "instruction_slices[#{index}] fragment content changed" unless content == row["content"]
        when "pointer_only"
          errors << "instruction_slices[#{index}] pointer-only row carries content" unless row["content"].nil?
        else
          errors << "instruction_slices[#{index}] locator is invalid"
        end
        if row["content"]
          errors << "instruction_slices[#{index}] fragment SHA-256 is stale" unless Digest::SHA256.hexdigest(row["content"]) == row["fragment_sha256"]
        end
      rescue ContractError, KeyError, Errno::ENOENT, Encoding::InvalidByteSequenceError => e
        errors << "instruction_slices[#{index}] #{e.message}"
      end
    end
    provider = pack["provider_binding"].to_h
    attestation = provider["requested_provider_attestation"]
    if attestation.is_a?(Hash)
      missing = REQUESTED_PROVIDER_ATTESTATION_FIELDS.any? { |field| attestation[field].to_s.empty? }
      if missing
        unless pack["status"].to_s == "hold" && Array(pack["hold_reasons"]).include?(REQUESTED_PROVIDER_ATTESTATION_INCOMPLETE)
          errors << "role context requested provider attestation is incomplete"
        end
      else
        evaluation = selected_provider_profile_evaluation(
          root: root,
          role: pack.dig("identity", "role"),
          provider: provider["provider"],
          requested: attestation
        )
        expected_holds = evaluation.fetch("holds")
        if expected_holds.empty?
          unless provider["logical_profile_alias"].to_s == attestation["logical_profile_alias"].to_s
            errors << "role context selected provider alias was not applied"
          end
          unless provider["provider_profile_id"].to_s == attestation["provider_profile_id"].to_s
            errors << "role context selected provider profile was not applied"
          end
        else
          unless pack["status"].to_s == "hold" && expected_holds.all? { |row| Array(pack["hold_reasons"]).include?(row) }
            errors << "role context selected provider attestation holds are missing"
          end
        end
      end
    end
    errors << "role context provider is held" unless provider["status"] == "resolved"
    if provider["status"] == "resolved"
      current_provider, provider_holds = resolve_provider(
        root: root,
        role: pack.dig("identity", "role"),
        provider: provider["provider"],
        runtime_surface: provider["runtime_surface"],
        logical_profile_alias: provider["logical_profile_alias"]
      )
      errors << "role context provider binding is stale: #{provider_holds.join(',')}" unless provider_holds.empty?
      resolved_binding = provider.slice(*RESOLVED_PROVIDER_BINDING_FIELDS)
      errors << "role context provider binding differs from the current registered snapshot" unless canonical_value(current_provider) == canonical_value(resolved_binding)
    end
    identity = pack["identity"].to_h
    current_node = pack["current_node"].to_h
    expected_pack_id = pack_id(identity["assignment_id"], identity["profile_id"], identity["checkpoint_id"])
    errors << "role context pack id differs from its identity" unless pack["pack_id"] == expected_pack_id
    expected_legal_next = LEGAL_NEXT.fetch(current_node["state"].to_s, %w[hold])
    errors << "role context current-node legal_next is stale" unless Array(current_node["legal_next"]) == expected_legal_next
    expected_edges = dependency_edges(
      identity["role"],
      identity["assignment_id"],
      current_node["return_recipient"],
      provider,
      quality_context
    )
    errors << "role context dependency edges differ from the exact operational graph" unless canonical_value(pack["dependency_edges"]) == canonical_value(expected_edges)
    instruction_content = Array(pack["instruction_slices"]).map { |row| row["content"] }.compact.join("\n")
    errors << "role context instruction content SHA-256 is stale" unless Digest::SHA256.hexdigest(instruction_content) == projection["instruction_content_sha256"]
    source_set = {
      "projection_registry" => {"path" => projection["registry_path"], "sha256" => projection["registry_sha256"]},
      "profile_registry" => {"path" => projection["profile_registry_path"], "sha256" => projection["profile_registry_sha256"]},
      "source_envelope" => pack["source_envelope"],
      "instructions" => Array(pack["instruction_slices"]).map { |row| row.slice("binding_id", "path", "whole_file_sha256", "locator", "fragment_sha256") },
      "creative_sources" => pack["creative_source_pointers"],
      "founder_quality_context" => quality_context,
      "provider" => provider.slice("provider", "provider_profile_id", "provider_source_sha256")
    }
    source_set["creative_judgment_contract"] = pack["creative_judgment_contract"] if pack.key?("creative_judgment_contract")
    source_set["graph_dispatch_identity"] = pack["graph_dispatch_identity"] if pack.key?("graph_dispatch_identity")
    source_set["activation_binding"] = pack["activation_binding"] if activation_present
    errors << "role context source-set SHA-256 is stale" unless structured_sha256(source_set) == projection["source_set_sha256"]
    expected_digest = structured_sha256(pack.reject { |key, _| key == "projection" }.merge(
      "projection" => pack.fetch("projection").reject { |key, _| key == "pack_digest" }
    ))
    errors << "role context pack digest is stale" unless expected_digest == pack.dig("projection", "pack_digest")
    errors
  end

  def select_registry_pair(root:, writer:, run_class:, switch_receipt:, active_writers: nil)
    writer_id = writer.to_s.empty? ? LEGACY_WRITER : writer.to_s
    writers = Array(active_writers).map(&:to_s).reject(&:empty?)
    writers = [writer_id] if writers.empty?
    if writers.uniq.length > 1
      raise ContractError, "dual active writer"
    end
    unless writers.uniq == [writer_id]
      raise ContractError, "requested writer must equal the unique active writer"
    end
    case writer_id
    when LEGACY_WRITER
      raise ContractError, "legacy role-context route must not carry a graph switch receipt" unless switch_receipt.nil?

      {
        "writer" => LEGACY_WRITER,
        "projection_registry_path" => PROJECTION_REGISTRY_RELATIVE,
        "profile_registry_path" => PROFILE_REGISTRY_RELATIVE,
        "activation_binding" => {
          "writer" => LEGACY_WRITER,
          "run_class" => run_class.to_s.empty? ? "legacy_or_unspecified" : run_class.to_s,
          "switch_receipt" => nil
        }
      }
    when GRAPH_WRITER
      raise ContractError, "graph role-context route is limited to an explicitly classified new run" unless run_class.to_s == "new_run"

      receipt = validate_graph_switch_receipt!(root, switch_receipt)
      {
        "writer" => GRAPH_WRITER,
        "projection_registry_path" => GRAPH_PROJECTION_REGISTRY_RELATIVE,
        "profile_registry_path" => GRAPH_PROFILE_REGISTRY_RELATIVE,
        "activation_binding" => {
          "writer" => GRAPH_WRITER,
          "run_class" => "new_run",
          "switch_receipt" => receipt
        }
      }
    else
      raise ContractError, "unknown role-context writer: #{writer_id}"
    end
  end

  def validate_graph_switch_receipt!(root, value)
    raise ContractError, "graph role-context route requires a verified default-switch receipt" unless value.is_a?(Hash)
    receipt = canonical_value(value)
    actual_keys = receipt.keys.sort
    expected_keys = GRAPH_SWITCH_RECEIPT_FIELDS.sort
    raise ContractError, "graph switch receipt keys must be exactly #{expected_keys.join(', ')}" unless actual_keys == expected_keys
    GRAPH_SWITCH_RECEIPT_FIELDS.each do |field|
      raise ContractError, "graph switch receipt #{field} is missing" if receipt[field].to_s.strip.empty?
    end
    raise ContractError, "graph switch receipt Founder authority is invalid" unless receipt["founder_authority"] == "founder"
    unless receipt["switch_boundary"] == "new_runs_only_after_verified_receipt"
      raise ContractError, "graph switch receipt boundary is invalid"
    end

    profile_path = contained_file(root, GRAPH_PROFILE_REGISTRY_RELATIVE)
    profile_registry = load_mapping(profile_path)
    unless receipt["graph_revision"] == profile_registry["schema_version"]
      raise ContractError, "graph switch receipt revision differs from the current Graph registry"
    end
    expected_source_set = graph_source_set_sha256(root)
    unless receipt["source_set_sha256"].to_s == expected_source_set
      raise ContractError, "graph switch receipt source set differs from current Graph bytes"
    end
    begin
      parsed = DateTime.iso8601(receipt["verified_at"].to_s)
      raise ArgumentError if parsed.zone.nil?
    rescue ArgumentError
      raise ContractError, "graph switch receipt verified_at must be ISO8601 with an offset"
    end
    receipt
  end

  def validate_historical_graph_switch_receipt!(value)
    raise ContractError, "historical Graph role-context route requires its original switch receipt" unless value.is_a?(Hash)
    receipt = canonical_value(value)
    unless receipt.keys.sort == GRAPH_SWITCH_RECEIPT_FIELDS.sort
      raise ContractError, "historical Graph switch receipt field set is invalid"
    end
    raise ContractError, "historical Graph switch receipt Founder authority is invalid" unless receipt["founder_authority"] == "founder"
    raise ContractError, "historical Graph switch receipt boundary is invalid" unless receipt["switch_boundary"] == "new_runs_only_after_verified_receipt"
    raise ContractError, "historical Graph switch receipt source-set SHA-256 is invalid" unless receipt["source_set_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
    raise ContractError, "historical Graph switch receipt revision is missing" if receipt["graph_revision"].to_s.empty?
    raise ContractError, "historical Graph switch receipt id is missing" if receipt["receipt_id"].to_s.empty?
    begin
      parsed = DateTime.iso8601(receipt["verified_at"].to_s)
      raise ArgumentError if parsed.zone.nil?
    rescue ArgumentError
      raise ContractError, "historical Graph switch receipt verified_at must be ISO8601 with an offset"
    end
    receipt
  end

  def graph_source_set_sha256(root)
    routing_path = contained_file(root, GRAPH_ROUTING_REGISTRY_RELATIVE)
    routing = load_mapping(routing_path)
    sources = Array(routing.dig("writer_boundary", "active_graph_surfaces")).map(&:to_s)
    raise ContractError, "active Graph source set is empty" if sources.empty?
    raise ContractError, "active Graph source set contains duplicate paths" unless sources.uniq.length == sources.length

    rows = sources.sort.map do |relative|
      path = contained_file(root, relative)
      "#{relative}:#{Digest::SHA256.file(path).hexdigest}"
    end
    Digest::SHA256.hexdigest(rows.join("\n") + "\n")
  end

  def build_graph_judgment_contract(root:, checkpoint:, stage_id:, role:)
    profile_id = checkpoint.to_h["judgment_profile_id"].to_s
    return nil if profile_id.empty?

    registry_path = contained_file(root, GRAPH_JUDGMENT_REGISTRY_RELATIVE)
    registry = load_mapping(registry_path)
    unless registry["schema_version"] == "idol-graph-creative-judgment-registry.v1" &&
           registry["status"] == "shadow_not_default"
      raise ContractError, "graph creative judgment registry is not an admitted shadow surface"
    end
    validate_graph_judgment_registry!(root: root, registry: registry)
    release = current_graph_judgment_profile_release(root: root, registry: registry, profile_id: profile_id)
    profile = release.fetch("profile")
    unless Array(profile["checkpoints"]).include?(checkpoint.to_h["checkpoint_id"].to_s)
      raise ContractError, "graph creative judgment checkpoint differs from its profile"
    end
    unless Array(profile["stages"]).include?(stage_id.to_s)
      raise ContractError, "graph creative judgment stage differs from its profile"
    end
    unless Array(profile["owner_roles"]).include?(role.to_s)
      raise ContractError, "graph creative judgment role differs from its profile"
    end
    {
      "authority" => "criteria_projection_no_creative_or_promotion_authority",
      "registry" => file_pointer(root, registry_path),
      "registry_schema" => file_pointer(root, contained_file(root, "schemas/graph-creative-judgment-registry.schema.json")),
      "profile_release" => release.fetch("pointer"),
      "profile_release_schema" => file_pointer(root, contained_file(root, GRAPH_JUDGMENT_PROFILE_RELEASE_SCHEMA_RELATIVE)),
      "profile_promotion" => release.fetch("promotion_binding"),
      "profile_promotion_schema" => file_pointer(root, contained_file(root, IdolGraphJudgmentProfilePromotionContract::SCHEMA_RELATIVE)),
      "profile_promotion_validator" => file_pointer(root, contained_file(root, IdolGraphJudgmentProfilePromotionContract::VALIDATOR_RELATIVE)),
      "artifact_schema" => file_pointer(root, contained_file(root, "schemas/graph-contextual-judgment.schema.json")),
      "validator" => file_pointer(root, contained_file(root, "scripts/validate_graph_contextual_judgment.rb")),
      "profile_id" => profile_id,
      "profile_value_sha256" => structured_sha256(profile),
      "profile" => profile
    }
  end

  def current_graph_judgment_profile_release(root:, registry:, profile_id:)
    current_profile = Array(registry["profiles"]).find { |row| row.to_h["profile_id"].to_s == profile_id.to_s }
    raise ContractError, "unknown graph creative judgment profile: #{profile_id}" unless current_profile
    pointer = registry.to_h.dig("current_profile_releases", profile_id.to_s)
    raise ContractError, "current graph creative judgment profile release is missing: #{profile_id}" unless pointer.is_a?(Hash)

    release = bound_graph_judgment_profile_release(root: root, pointer: pointer, expected_profile_id: profile_id)
    promotion_errors = IdolGraphJudgmentProfilePromotionContract.validate_binding(
      root: root,
      binding: pointer["promotion_binding"],
      current_release: pointer,
      profile_id: profile_id,
      registry_status: registry["status"],
      validation_mode: "active_promotion"
    )
    unless promotion_errors.empty?
      raise ContractError, "current graph creative judgment profile promotion is invalid: #{promotion_errors.join('; ')}"
    end
    unless canonical_value(current_profile) == canonical_value(release.fetch("profile"))
      raise ContractError, "current graph creative judgment profile differs from its immutable release: #{profile_id}"
    end
    unless pointer["profile_value_sha256"].to_s == release.fetch("profile_value_sha256")
      raise ContractError, "current graph creative judgment profile release value hash is stale: #{profile_id}"
    end
    unless pointer["release_value_sha256"].to_s == release.fetch("release_value_sha256")
      raise ContractError, "current graph creative judgment release policy hash is stale: #{profile_id}"
    end
    release["promotion_binding"] = pointer.fetch("promotion_binding").slice("path", "sha256")
    release
  end

  def bound_graph_judgment_profile_release(root:, pointer:, expected_profile_id: nil)
    raise ContractError, "graph creative judgment profile release pointer is missing" unless pointer.is_a?(Hash)
    path = contained_file(root, pointer["path"])
    actual_sha = Digest::SHA256.file(path).hexdigest
    unless actual_sha == pointer["sha256"].to_s
      raise ContractError, "graph creative judgment profile release SHA-256 is stale"
    end
    validate_json_schema_file!(
      root: root,
      schema_relative: GRAPH_JUDGMENT_PROFILE_RELEASE_SCHEMA_RELATIVE,
      instance_path: path,
      label: "graph creative judgment profile release"
    )
    release = load_mapping(path)
    unless release["schema_version"] == GRAPH_JUDGMENT_PROFILE_RELEASE_VERSION &&
           release["status"] == "immutable_release" &&
           release["authority"] == GRAPH_JUDGMENT_PROFILE_RELEASE_AUTHORITY
      raise ContractError, "graph creative judgment profile release is not immutable"
    end
    profile = canonical_value(release["profile"])
    policy = canonical_value(release["policy"])
    profile_id = profile.to_h["profile_id"].to_s
    if !expected_profile_id.to_s.empty? && profile_id != expected_profile_id.to_s
      raise ContractError, "graph creative judgment profile release identity differs"
    end
    profile_hash = structured_sha256(profile)
    unless release["profile_value_sha256"].to_s == profile_hash
      raise ContractError, "graph creative judgment profile release value hash is stale"
    end
    criterion_ids = Array(profile["criteria"]).map { |row| row.to_h["criterion_id"].to_s }
    if criterion_ids.any?(&:empty?) || criterion_ids.uniq.length != criterion_ids.length
      raise ContractError, "graph creative judgment profile release criterion ids are missing or duplicated"
    end
    rule_ids = policy.to_h.fetch("applicability_rules", {}).keys.map(&:to_s)
    unless rule_ids.sort == GRAPH_JUDGMENT_APPLICABILITY_TAGS.sort
      raise ContractError, "graph creative judgment profile release applicability rule set is invalid"
    end
    referenced_rules = Array(profile["criteria"]).flat_map do |row|
      [row.to_h["applies_when"], row.to_h["not_applicable"]]
    end.compact.map(&:to_s)
    unless (referenced_rules - rule_ids).empty?
      raise ContractError, "graph creative judgment profile release references an unknown applicability rule"
    end
    release_hash = structured_sha256("policy" => policy, "profile" => profile)
    unless release["release_value_sha256"].to_s == release_hash
      raise ContractError, "graph creative judgment release policy hash is stale"
    end
    expected_path = "#{GRAPH_JUDGMENT_PROFILE_RELEASE_ROOT}/#{profile_id}/#{release_hash}.yaml"
    unless pointer["path"].to_s == expected_path
      raise ContractError, "graph creative judgment profile release path is not content-addressed"
    end
    {
      "pointer" => {"path" => pointer["path"].to_s, "sha256" => actual_sha},
      "release_value_sha256" => release_hash,
      "profile_value_sha256" => profile_hash,
      "policy" => policy,
      "profile" => profile
    }
  end

  def validate_graph_judgment_registry!(root:, registry:)
    root = Pathname.new(root).expand_path.cleanpath
    registry_path = contained_file(root, GRAPH_JUDGMENT_REGISTRY_RELATIVE)
    validate_json_schema_file!(
      root: root,
      schema_relative: "schemas/graph-creative-judgment-registry.schema.json",
      instance_path: registry_path,
      label: "graph creative judgment registry"
    )
    profiles = Array(registry["profiles"])
    profile_ids = profiles.map { |row| row.to_h["profile_id"].to_s }
    if profile_ids.any?(&:empty?) || profile_ids.uniq.length != profile_ids.length
      raise ContractError, "graph creative judgment registry profile ids are missing or duplicated"
    end
    releases = registry["current_profile_releases"].to_h
    unless releases.keys.map(&:to_s).sort == profile_ids.sort
      raise ContractError, "graph creative judgment registry release keys differ from profile ids"
    end
    profiles.each do |profile|
      criterion_ids = Array(profile.to_h["criteria"]).map { |row| row.to_h["criterion_id"].to_s }
      if criterion_ids.any?(&:empty?) || criterion_ids.uniq.length != criterion_ids.length
        raise ContractError, "graph creative judgment registry criterion ids are missing or duplicated: #{profile.to_h['profile_id']}"
      end
      current_graph_judgment_profile_release(root: root, registry: registry, profile_id: profile.to_h["profile_id"])
    end
    true
  end

  def validate_graph_judgment_contract(root:, contract:, checkpoint:, stage_id:, role:, validation_mode: "active_promotion")
    errors = []
    unless contract.is_a?(Hash)
      return ["graph creative judgment contract is missing"]
    end
    profile_id = checkpoint.to_h["judgment_profile_id"].to_s
    begin
      release = bound_graph_judgment_profile_release(
        root: root,
        pointer: contract["profile_release"],
        expected_profile_id: profile_id
      )
      profile = release.fetch("profile")
      errors << "graph creative judgment checkpoint differs from its released profile" unless Array(profile["checkpoints"]).include?(checkpoint.to_h["checkpoint_id"].to_s)
      errors << "graph creative judgment stage differs from its released profile" unless Array(profile["stages"]).include?(stage_id.to_s)
      errors << "graph creative judgment role differs from its released profile" unless Array(profile["owner_roles"]).include?(role.to_s)
      errors << "graph creative judgment contract profile differs from its immutable release" unless canonical_value(contract["profile"]) == canonical_value(profile)
      errors << "graph creative judgment contract profile hash differs from its immutable release" unless contract["profile_value_sha256"].to_s == release.fetch("profile_value_sha256")
      errors << "graph creative judgment contract release pointer differs from its immutable release" unless canonical_value(contract["profile_release"]) == canonical_value(release.fetch("pointer"))
      promotion_release = release.fetch("pointer").merge(
        "release_value_sha256" => release.fetch("release_value_sha256"),
        "profile_value_sha256" => release.fetch("profile_value_sha256")
      )
      promotion_registry_status = if validation_mode.to_s == "active_promotion"
                                    load_mapping(contained_file(root, GRAPH_JUDGMENT_REGISTRY_RELATIVE))["status"]
                                  end
      if validation_mode.to_s == "profile_evolution_evidence"
        # A candidate-release pack is evidence inside the promotion artifact,
        # so binding that same promotion here would create a hash cycle. Keep
        # the last admitted promotion pointer hash-checked and schema-valid;
        # the outer lifecycle contract independently binds the candidate.
        promotion_binding = contract["profile_promotion"].to_h
        promotion_path = contained_file(root, promotion_binding["path"])
        errors << "graph creative judgment profile promotion pointer is stale" unless Digest::SHA256.file(promotion_path).hexdigest == promotion_binding["sha256"].to_s
        validate_json_schema_file!(
          root: root,
          schema_relative: IdolGraphJudgmentProfilePromotionContract::SCHEMA_RELATIVE,
          instance_path: promotion_path,
          label: "graph creative judgment profile evolution prior promotion"
        )
      else
        promotion_errors = IdolGraphJudgmentProfilePromotionContract.validate_binding(
          root: root,
          binding: contract["profile_promotion"],
          current_release: promotion_release,
          profile_id: profile_id,
          registry_status: promotion_registry_status,
          validation_mode: validation_mode
        )
        errors.concat(promotion_errors.map { |message| "graph creative judgment profile promotion #{message}" })
      end
      if validation_mode.to_s == "active_promotion"
        registry = load_mapping(contained_file(root, GRAPH_JUDGMENT_REGISTRY_RELATIVE))
        validate_graph_judgment_registry!(root: root, registry: registry)
        current = current_graph_judgment_profile_release(root: root, registry: registry, profile_id: profile_id)
        errors << "graph creative judgment contract release is not the current active-promotion release" unless canonical_value(current.fetch("pointer")) == canonical_value(release.fetch("pointer"))
        errors << "graph creative judgment contract promotion binding is not the current active-promotion binding" unless canonical_value(current.fetch("promotion_binding")) == canonical_value(contract["profile_promotion"])
        errors << "graph creative judgment contract registry provenance is stale for active promotion" unless contract.dig("registry", "sha256").to_s == Digest::SHA256.file(contained_file(root, GRAPH_JUDGMENT_REGISTRY_RELATIVE)).hexdigest
      elsif validation_mode.to_s == "profile_evolution_evidence"
        registry_path = contained_file(root, GRAPH_JUDGMENT_REGISTRY_RELATIVE)
        registry = load_mapping(registry_path)
        current_binding = registry.to_h.dig("current_profile_releases", profile_id, "promotion_binding").to_h.slice("path", "sha256")
        errors << "graph creative judgment evolution registry provenance is stale" unless contract.dig("registry", "sha256").to_s == Digest::SHA256.file(registry_path).hexdigest
        errors << "graph creative judgment evolution prior promotion is not the current admitted binding" unless canonical_value(contract["profile_promotion"]) == canonical_value(current_binding)
      end
    rescue ContractError => e
      errors << e.message
    end
    errors << "graph creative judgment contract authority is invalid" unless contract["authority"] == "criteria_projection_no_creative_or_promotion_authority"
    errors << "graph creative judgment contract profile id differs from checkpoint" unless contract["profile_id"].to_s == profile_id
    errors << "graph creative judgment contract registry provenance path is invalid" unless contract.dig("registry", "path").to_s == GRAPH_JUDGMENT_REGISTRY_RELATIVE
    registry_sha = contract.dig("registry", "sha256").to_s
    errors << "graph creative judgment contract registry provenance SHA-256 is invalid" unless registry_sha.match?(/\A[a-f0-9]{64}\z/) && registry_sha != "0" * 64
    {
      "registry_schema" => "schemas/graph-creative-judgment-registry.schema.json",
      "profile_release_schema" => GRAPH_JUDGMENT_PROFILE_RELEASE_SCHEMA_RELATIVE,
      "profile_promotion_schema" => IdolGraphJudgmentProfilePromotionContract::SCHEMA_RELATIVE,
      "profile_promotion_validator" => IdolGraphJudgmentProfilePromotionContract::VALIDATOR_RELATIVE,
      "artifact_schema" => "schemas/graph-contextual-judgment.schema.json",
      "validator" => "scripts/validate_graph_contextual_judgment.rb"
    }.each do |field, relative|
      expected = file_pointer(root, contained_file(root, relative))
      errors << "graph creative judgment contract #{field} pointer is stale" unless canonical_value(contract[field]) == canonical_value(expected)
    end
    errors
  end

  def apply_selected_provider_profile!(root:, role:, provider:, runtime_surface:, provider_binding:,
                                      requested_logical_profile_alias:, requested_provider_profile_id:,
                                      requested_exact_model:, requested_reasoning_effort:,
                                      requested_provider_source_sha256:)
    supplied = {
      "logical_profile_alias" => requested_logical_profile_alias.to_s,
      "provider_profile_id" => requested_provider_profile_id.to_s,
      "exact_model" => requested_exact_model.to_s,
      "reasoning_effort" => requested_reasoning_effort.to_s,
      "provider_source_sha256" => requested_provider_source_sha256.to_s
    }
    return [] if supplied.values.all?(&:empty?)

    attestation = {}
    supplied.each do |key, value|
      attestation[key] = value unless value.empty?
    end
    provider_binding["requested_provider_attestation"] = attestation
    return [REQUESTED_PROVIDER_ATTESTATION_INCOMPLETE] if supplied.values.any?(&:empty?)

    evaluation = selected_provider_profile_evaluation(
      root: root,
      role: role,
      provider: provider,
      requested: supplied
    )
    holds = evaluation.fetch("holds")
    if evaluation.fetch("eligible")
      selected_binding, selected_holds = resolve_provider(
        root: root,
        role: role,
        provider: provider,
        runtime_surface: runtime_surface,
        logical_profile_alias: supplied.fetch("logical_profile_alias")
      )
      holds.concat(selected_holds)
      if selected_holds.empty?
        RESOLVED_PROVIDER_BINDING_FIELDS.each do |field|
          provider_binding[field] = selected_binding[field]
        end
      end
    end
    holds
  end

  def selected_provider_profile_evaluation(root:, role:, provider:, requested:)
    holds = []
    alias_id = requested.fetch("logical_profile_alias").to_s
    profile_id = requested.fetch("provider_profile_id").to_s
    requested_model = requested.fetch("exact_model").to_s
    requested_effort = requested.fetch("reasoning_effort").to_s
    requested_sha = requested.fetch("provider_source_sha256").to_s
    registry_path = contained_file(root, PROVIDER_REGISTRY_RELATIVE)
    registry = load_mapping(registry_path)
    logical_profile = registry.dig("logical_profiles", alias_id)
    row = logical_profile.is_a?(Hash) ? logical_profile.dig("providers", provider.to_s) : nil
    unless row.is_a?(Hash)
      holds << "role_context_selected_provider_profile_not_registered:#{alias_id}/#{provider}"
      return {"holds" => holds, "eligible" => false}
    end
    unless row.fetch("provider_profile_id").to_s == profile_id
      holds << "#{SELECTED_PROVIDER_MISMATCH_PREFIX}profile=#{profile_id};registry=#{row['provider_profile_id']}"
    end
    source_relative = row.fetch("source_path").to_s
    source_path = contained_file(root, source_relative)
    actual_sha = Digest::SHA256.file(source_path).hexdigest
    registry_sha = row.fetch("source_sha256").to_s
    if requested_sha != actual_sha || requested_sha != registry_sha
      holds << "#{SELECTED_PROVIDER_MISMATCH_PREFIX}source_sha256"
    end
    source = load_mapping(source_path)
    source_profile = source.dig("profiles", profile_id)
    unless source_profile.is_a?(Hash)
      holds << "role_context_selected_provider_profile_missing:#{profile_id}"
      return {"holds" => holds, "eligible" => false}
    end
    source_model = source_profile.fetch("exact_model").to_s
    source_effort = source_profile.fetch("reasoning_effort").to_s
    if requested_model != source_model || requested_effort != source_effort
      holds << "#{SELECTED_PROVIDER_MISMATCH_PREFIX}requested=#{requested_model}/#{requested_effort};source=#{source_model}/#{source_effort}"
    end
    registry_roles = Array(logical_profile["eligible_logical_roles"]).map(&:to_s)
    source_roles = Array(source_profile["eligible_logical_roles"]).map(&:to_s)
    unless registry_roles.include?(role.to_s) && source_roles.include?(role.to_s)
      holds << "#{SELECTED_PROVIDER_ROLE_UNSUPPORTED_PREFIX}#{role}:#{alias_id}:#{profile_id}"
    end
    {"holds" => holds, "eligible" => holds.empty?}
  rescue ContractError, KeyError => e
    {"holds" => ["role_context_selected_provider_resolution_error:#{e.message}"], "eligible" => false}
  end

  def provider_alias(profile, role, graph_native:)
    tier = profile["logical_tier"].to_s
    return tier if graph_native && %w[frontier_director worker_high research_medium].include?(tier)
    return "director_deep" if director_role?(role)

    role.to_s == "department_worker" ? "research_medium" : "worker_high"
  end

  def director_role?(role)
    DIRECTOR_ROLES.include?(role.to_s) || GRAPH_DIRECTOR_ROLES.include?(role.to_s)
  end

  def project_binding(root, registry, profile_id, row, kind)
    binding_id = row.fetch("binding_id").to_s
    relative = row.fetch("path").to_s
    path = contained_file(root, relative)
    actual_sha = Digest::SHA256.file(path).hexdigest
    raise ContractError, "role-context source SHA-256 is stale: #{relative}" unless actual_sha == row.fetch("sha256").to_s
    text = path.read
    original_words = text.scan(/\S+/).length
    rule = select_rule(registry, binding_id, profile_id)
    mode = rule&.fetch("mode") || default_mode(registry, kind, path)
    reason = rule&.fetch("reason") || default_reason(mode, kind)

    case mode
    when "full_file"
      [slice_row(row, kind, actual_sha, {"type" => "whole_file"}, text, "inline_exact_full_file", reason, original_words)]
    when "pointer_only"
      [slice_row(row, kind, actual_sha, {"type" => "pointer_only"}, nil, "pointer_with_structural_preflight", reason, original_words)]
    when "markdown_headings"
      raise ContractError, "markdown heading projection requires a Markdown source: #{relative}" unless path.extname.downcase == ".md"
      Array(rule.fetch("headings")).map do |heading|
        content = markdown_heading(text, heading, relative)
        slice_row(row, kind, actual_sha, {"type" => "markdown_heading", "heading" => heading}, content, "inline_exact_fragment", reason, original_words)
      end.tap do |rows|
        rows.each_with_index { |item, index| item["_original_word_count"] = index.zero? ? original_words : 0 }
      end
    else
      raise ContractError, "unsupported role-context projection mode: #{mode}"
    end
  end

  def slice_row(binding, kind, whole_sha, locator, content, runtime_mode, reason, original_words)
    {
      "binding_id" => binding.fetch("binding_id").to_s,
      "binding_kind" => kind,
      "path" => binding.fetch("path").to_s,
      "revision" => binding.fetch("revision").to_s,
      "whole_file_sha256" => whole_sha,
      "locator" => locator,
      "fragment_sha256" => content.nil? ? nil : Digest::SHA256.hexdigest(content),
      "runtime_read_mode" => runtime_mode,
      "source_read_verified_to_eof" => true,
      "content" => content,
      "selection_reason" => reason.to_s,
      "_original_word_count" => original_words
    }
  end

  def markdown_heading(text, heading, label)
    lines = text.lines
    matches = []
    fenced = false
    lines.each_with_index do |line, index|
      if line.match?(/\A[ \t]*(?:```|~~~)/)
        fenced = !fenced
        next
      end
      next if fenced
      match = line.match(/\A(\#{1,6})[ \t]+(.+?)[ \t]*\r?\n?\z/)
      next unless match && match[2] == heading
      matches << [index, match[1].length]
    end
    raise ContractError, "markdown heading is missing: #{label}##{heading}" if matches.empty?
    raise ContractError, "markdown heading is ambiguous: #{label}##{heading}" unless matches.length == 1
    start_index, level = matches.first
    finish_index = lines.length
    fenced = false
    ((start_index + 1)...lines.length).each do |index|
      if lines[index].match?(/\A[ \t]*(?:```|~~~)/)
        fenced = !fenced
        next
      end
      next if fenced
      match = lines[index].match(/\A(\#{1,6})[ \t]+/)
      if match && match[1].length <= level
        finish_index = index
        break
      end
    end
    lines[start_index...finish_index].join
  end

  def resolve_provider(root:, role:, provider:, runtime_surface:, logical_profile_alias: nil)
    registry_path = contained_file(root, PROVIDER_REGISTRY_RELATIVE)
    registry = load_mapping(registry_path)
    alias_id = logical_profile_alias.to_s
    alias_id = director_role?(role) ? "director_deep" : "worker_high" if alias_id.empty?
    provider_id = provider.to_s
    row = registry.dig("logical_profiles", alias_id, "providers", provider_id)
    base = {
      "status" => "hold",
      "logical_profile_alias" => alias_id,
      "provider" => %w[grok cursor].include?(provider_id) ? provider_id : "unresolved",
      "runtime_surface" => runtime_surface.to_s.empty? ? "unresolved_provider_surface" : runtime_surface.to_s,
      "registry_path" => PROVIDER_REGISTRY_RELATIVE,
      "registry_sha256" => Digest::SHA256.file(registry_path).hexdigest,
      "provider_profile_id" => nil,
      "provider_source_path" => nil,
      "provider_source_sha256" => nil,
      "exact_model" => nil,
      "reasoning_effort" => nil,
      "fallback_policy" => "forbidden"
    }
    return [base, ["role_context_provider_not_registered:#{provider_id}"]] unless row.is_a?(Hash)

    source_path = contained_file(root, row.fetch("source_path"))
    actual = Digest::SHA256.file(source_path).hexdigest
    return [base, ["role_context_provider_source_hash_mismatch:#{row['source_path']}"]] unless actual == row.fetch("source_sha256").to_s
    source = load_mapping(source_path)
    profile_id = row.fetch("provider_profile_id").to_s
    profile = source.dig("profiles", profile_id)
    return [base, ["role_context_provider_profile_missing:#{profile_id}"]] unless profile.is_a?(Hash)

    base.merge!(
      "status" => "resolved",
      "provider_profile_id" => profile_id,
      "provider_source_path" => row.fetch("source_path").to_s,
      "provider_source_sha256" => actual,
      "exact_model" => profile.fetch("exact_model").to_s,
      "reasoning_effort" => profile.fetch("reasoning_effort").to_s
    )
    [base, []]
  rescue ContractError, KeyError => e
    [base || {
      "status" => "hold",
      "logical_profile_alias" => logical_profile_alias.to_s.empty? ? (director_role?(role) ? "director_deep" : "worker_high") : logical_profile_alias.to_s,
      "provider" => "unresolved",
      "runtime_surface" => "unresolved_provider_surface",
      "registry_path" => PROVIDER_REGISTRY_RELATIVE,
      "registry_sha256" => "0" * 64,
      "provider_profile_id" => nil,
      "provider_source_path" => nil,
      "provider_source_sha256" => nil,
      "exact_model" => nil,
      "reasoning_effort" => nil,
      "fallback_policy" => "forbidden"
    }, ["role_context_provider_resolution_error:#{e.message}"]]
  end

  def normalize_creative_sources(root, sources, graph_native: false)
    Array(sources).map do |row|
      raise ContractError, "creative source pointer must be an object" unless row.is_a?(Hash)
      if graph_native
        forbidden = %w[url urls raw_pool raw_search_pool full_url_list worker_transcript completed_worker_transcript superseded_prose]
        found = forbidden.find { |key| row.key?(key) || row.key?(key.to_sym) }
        raise ContractError, "graph role-context creative source contains forbidden field: #{found}" if found
      end
      relative = row.fetch("path").to_s
      path = contained_file(root, relative)
      actual = Digest::SHA256.file(path).hexdigest
      expected = row.fetch("sha256").to_s
      raise ContractError, "role-context creative source SHA-256 is stale: #{relative}" unless actual == expected
      normalized = {
        "source_id" => (row["source_id"] || row["role"] || Digest::SHA256.hexdigest(relative)[0, 12]).to_s,
        "path" => relative,
        "sha256" => actual,
        "purpose" => (row["purpose"] || row["role"] || "Exact current assignment source bytes.").to_s
      }
      locator = row["locator"].to_s
      function = row["function"].to_s
      normalized["locator"] = locator unless locator.empty?
      normalized["function"] = function unless function.empty?
      groups = Array(row["role_groups"]).map(&:to_s).reject(&:empty?).uniq
      normalized["role_groups"] = groups unless groups.empty?
      disposition = row["disposition"].to_s
      normalized["disposition"] = disposition unless disposition.empty?
      if graph_native
        source_id = row["source_id"].to_s
        locator = row["locator"].to_s
        function = row["function"].to_s
        raise ContractError, "graph role-context creative source source_id is required: #{relative}" if source_id.empty?
        raise ContractError, "graph role-context creative source locator is required: #{relative}" if locator.empty?
        raise ContractError, "graph role-context creative source function is required: #{relative}" if function.empty?
        normalized["source_id"] = source_id
        normalized.merge!(
          "locator" => locator,
          "function" => function,
          "role_groups" => Array(row["role_groups"]).map(&:to_s).reject(&:empty?).uniq,
          "disposition" => row.fetch("disposition", "applied").to_s
        )
      end
      normalized
    end
  end

  def normalize_source_envelope(root, envelope)
    raise ContractError, "role-context source envelope must be an object" unless envelope.is_a?(Hash)

    normalized = {
      "kind" => envelope.fetch("kind").to_s,
      "path" => envelope["path"],
      "sha256" => envelope["sha256"]
    }
    if normalized["path"].nil?
      raise ContractError, "role-context source envelope has a SHA-256 without a path" unless normalized["sha256"].nil?
      return normalized
    end

    relative = normalized.fetch("path").to_s
    path = contained_file(root, relative)
    actual = Digest::SHA256.file(path).hexdigest
    raise ContractError, "role-context source envelope SHA-256 is stale: #{relative}" unless actual == normalized.fetch("sha256").to_s
    normalized.merge("path" => relative, "sha256" => actual)
  end

  def normalize_graph_dispatch_identity(root, source_envelope, assignment_id:, run_root:, profile_id:, section_ids:, authority:, return_recipient:, current_state:)
    unless source_envelope.is_a?(Hash) && source_envelope["kind"] == "department_dispatch" && !source_envelope["path"].to_s.empty?
      raise ContractError, "Graph judgment checkpoint requires a hash-bound Department Dispatch source envelope"
    end

    path = contained_file(root, source_envelope.fetch("path"))
    actual_sha = Digest::SHA256.file(path).hexdigest
    unless actual_sha == source_envelope["sha256"].to_s
      raise ContractError, "Graph judgment Department Dispatch source envelope is stale"
    end
    dispatch = load_mapping(path)
    unless dispatch["schema_version"] == "idol-graph-department-dispatch.v1" && dispatch["artifact_type"] == "graph_department_dispatch"
      raise ContractError, "Graph judgment source envelope must name graph_department_dispatch"
    end
    unless dispatch["dispatch_id"].to_s == assignment_id.to_s
      raise ContractError, "Graph judgment Department Dispatch differs from assignment_id"
    end
    unless dispatch["run"].to_s == run_root.to_s
      raise ContractError, "Graph judgment Department Dispatch differs from run_root"
    end
    expected_role = GRAPH_PROFILE_DISPATCH_ROLES[profile_id.to_s]
    if expected_role.to_s.empty? || dispatch["logical_role"].to_s != expected_role
      raise ContractError, "Graph judgment Department Dispatch logical_role differs from profile"
    end
    unless Array(dispatch["section_ids"]).map(&:to_s) == Array(section_ids).map(&:to_s)
      raise ContractError, "Graph judgment Department Dispatch sections differ from Role Context Pack"
    end
    validate_graph_profile_dispatch_lane!(
      profile_id: profile_id,
      lane_id: dispatch["lane_id"],
      section_cohort_id: dispatch["section_cohort_id"]
    )
    dispatch_state = dispatch["lifecycle_state"].to_s
    unless %w[prepared launched returned].include?(dispatch_state)
      raise ContractError, "Graph judgment Department Dispatch lifecycle is not projectable"
    end
    unless current_state.to_s == dispatch_state
      raise ContractError, "Graph judgment Role Context Pack state differs from Department Dispatch at projection"
    end
    unless dispatch["input_digest_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
      raise ContractError, "Graph judgment Department Dispatch input_digest_sha256 is invalid"
    end

    output_writer = dispatch["output_writer"]
    reviewer = dispatch["reviewer"]
    recipient = dispatch["return_recipient"]
    raise ContractError, "Graph judgment Department Dispatch output_writer is missing" unless output_writer.is_a?(Hash)
    raise ContractError, "Graph judgment Department Dispatch reviewer is missing" unless reviewer.is_a?(Hash)
    raise ContractError, "Graph judgment Department Dispatch return_recipient is missing" unless recipient.is_a?(Hash)
    GRAPH_DISPATCH_OUTPUT_WRITER_FIELDS.each do |field|
      raise ContractError, "Graph judgment Department Dispatch output_writer.#{field} is missing" if output_writer[field].to_s.empty?
    end
    %w[owner role lane_id].each do |field|
      raise ContractError, "Graph judgment Department Dispatch reviewer.#{field} is missing" if reviewer[field].to_s.empty?
    end
    GRAPH_DISPATCH_RETURN_RECIPIENT_FIELDS.each do |field|
      raise ContractError, "Graph judgment Department Dispatch return_recipient.#{field} is missing" if recipient[field].to_s.empty?
    end
    raise ContractError, "Graph judgment Department Dispatch assigned_owner is missing" if dispatch["assigned_owner"].to_s.empty?
    unless authority.is_a?(Hash) && authority["assigned_owner"].to_s == dispatch["assigned_owner"].to_s
      raise ContractError, "Graph judgment Role Context Pack assigned owner differs from Department Dispatch"
    end
    unless canonical_value(return_recipient) == canonical_value(recipient.slice(*GRAPH_DISPATCH_RETURN_RECIPIENT_FIELDS))
      raise ContractError, "Graph judgment Role Context Pack return recipient differs from Department Dispatch"
    end

    {
      "authority" => "exact_copy_from_hash_bound_graph_dispatch_at_pack_creation",
      "dispatch" => {"path" => source_envelope.fetch("path"), "sha256" => actual_sha},
      "dispatch_id" => dispatch.fetch("dispatch_id").to_s,
      "input_digest_sha256" => dispatch.fetch("input_digest_sha256").to_s,
      "dispatch_lifecycle_state_at_projection" => dispatch_state,
      "run" => dispatch.fetch("run").to_s,
      "lane_id" => dispatch.fetch("lane_id").to_s,
      "section_cohort_id" => dispatch["section_cohort_id"],
      "section_ids" => Array(dispatch["section_ids"]).map(&:to_s),
      "logical_role" => dispatch.fetch("logical_role").to_s,
      "assigned_owner" => dispatch.fetch("assigned_owner").to_s,
      "output_writer" => output_writer.slice(*GRAPH_DISPATCH_OUTPUT_WRITER_FIELDS),
      "reviewer" => reviewer.slice(*GRAPH_DISPATCH_REVIEWER_FIELDS),
      "return_recipient" => recipient.slice(*GRAPH_DISPATCH_RETURN_RECIPIENT_FIELDS)
    }
  rescue KeyError => e
    raise ContractError, "Graph judgment Department Dispatch is incomplete: #{e.message}"
  end

  def validate_graph_profile_dispatch_lane!(profile_id:, lane_id:, section_cohort_id:)
    lane = lane_id.to_s
    cohort = section_cohort_id
    case profile_id.to_s
    when "overall_director"
      valid = lane == "overall" && cohort.nil?
    when "planning_cdd_p1"
      valid = lane == "planning_p1" && cohort.nil?
    when "planning_cdd_p2"
      valid = lane == "planning_p2" && cohort.nil?
    when "planning_cdd_p3_ci"
      match = /\Aplanning_p3_c([1-9][0-9]*)\z/.match(lane)
      valid = !match.nil? && cohort.to_s == "C#{match[1]}"
    when "section_cluster_cdd_ci", "section_image_motion_worker"
      match = /\Asection_cluster_v_c([1-9][0-9]*)\z/.match(lane)
      valid = !match.nil? && cohort.to_s == "C#{match[1]}"
    when "edit_director"
      valid = lane == "edit_director" && cohort.nil?
    else
      valid = false
    end
    return if valid

    raise ContractError, "Graph judgment Department Dispatch lane/cohort differs from profile"
  end

  def validate_current_file_pointer(root:, relative:, expected_sha256:, label:, errors:)
    path = contained_file(root, relative)
    actual = Digest::SHA256.file(path).hexdigest
    errors << "#{label} SHA-256 is stale" unless actual == expected_sha256
  rescue ContractError, Errno::ENOENT => e
    errors << "#{label} #{e.message}"
  end

  def dependency_edges(role, assignment_id, recipient, provider_binding, founder_quality_context = nil)
    recipient_owner = recipient.is_a?(Hash) ? (recipient["owner"] || recipient["role"]) : recipient
    recipient_owner = "declared_recipient" if recipient_owner.to_s.empty?
    edges = [
      {"edge_type" => "authority", "from" => role.to_s, "to" => assignment_id.to_s, "invalidation_scope" => "exact_assignment_only"},
      {"edge_type" => "review", "from" => assignment_id.to_s, "to" => recipient_owner.to_s, "invalidation_scope" => "exact_return_bytes_and_governing_inputs"},
      {"edge_type" => "provider", "from" => provider_binding["provider_profile_id"] || "unresolved_provider", "to" => assignment_id.to_s, "invalidation_scope" => "assignments_resolved_to_this_provider_snapshot_only"}
    ]
    if founder_quality_context.is_a?(Hash)
      edges << {
        "edge_type" => "semantic",
        "from" => "founder_quality_context:#{founder_quality_context['context_digest']}",
        "to" => assignment_id.to_s,
        "invalidation_scope" => "exact_role_context_pack_advisory_projection_only"
      }
    end
    edges
  end

  def extract_founder_quality_context(root, document, role:, profile_id:, stage_id:, section_ids:)
    root = Pathname.new(root).expand_path.cleanpath
    run = document["run"].to_s
    return nil if run.empty?

    path = root.join(run, IdolRunFollowupSidecar::RELATIVE_SIDECAR).expand_path.cleanpath
    return nil unless path.file?

    sidecar = IdolRunFollowupSidecar.load_sidecar(path)
    return nil unless sidecar.is_a?(Hash) && sidecar["schema_version"] == IdolRunFollowupSidecar::V3_VERSION
    semantic_errors = IdolRunFollowupSidecar.validate_founder_creative_closures(
      sidecar,
      version: IdolRunFollowupSidecar::V3_VERSION
    )
    return nil unless semantic_errors.empty?

    matching = Array(sidecar["founder_creative_closures"]).each_with_index.each_with_object([]) do |(closure, index), rows|
      next unless closure.is_a?(Hash)
      projection = closure["context_projection"]
      next unless projection.is_a?(Hash) && projection["status"] == "eligible"
      next unless founder_quality_applicable?(
        projection["applicability"],
        role: role,
        profile_id: profile_id,
        stage_id: stage_id,
        section_ids: section_ids
      )

      rows << {
        "closure_id" => closure["closure_id"],
        "recurrence_key" => closure["recurrence_key"],
        "recurrence_count" => closure["recurrence_count"],
        "reason_summary" => closure["reason_summary"],
        "pattern_type" => projection["pattern_type"],
        "priority" => projection["priority"],
        "first_seen_at" => closure["first_seen_at"],
        "last_seen_at" => closure["last_seen_at"],
        "evidence_rollup_sha256" => closure["evidence_rollup_sha256"],
        "positive_core" => Array(projection["positive_core"]),
        "avoid_signals" => Array(projection["avoid_signals"]),
        "director_actions" => Array(projection["director_actions"]),
        "review_questions" => Array(projection["review_questions"]),
        "applicability" => projection["applicability"],
        "source_json_pointer" => "/founder_creative_closures/#{index}"
      }
    end
    return nil if matching.empty?

    matching.sort! do |left, right|
      comparison = left["priority"].to_i <=> right["priority"].to_i
      comparison = right["recurrence_count"].to_i <=> left["recurrence_count"].to_i if comparison.zero?
      comparison = right["last_seen_at"].to_s <=> left["last_seen_at"].to_s if comparison.zero?
      comparison.zero? ? left["closure_id"].to_s <=> right["closure_id"].to_s : comparison
    end
    selected = matching.first(FOUNDER_QUALITY_PATTERN_LIMIT)
    relative = path.relative_path_from(root).to_s
    context = {
      "authority" => "compact_advisory_context_no_lock_review_or_promotion_authority",
      "source_sidecar" => {
        "path" => relative,
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "schema_version" => IdolRunFollowupSidecar::V3_VERSION
      },
      "selection_mode" => "author_scoped_priority_then_recency_no_machine_similarity",
      "pattern_limit" => FOUNDER_QUALITY_PATTERN_LIMIT,
      "omitted_pattern_count" => matching.length - selected.length,
      "patterns" => selected,
      "context_digest" => "0" * 64
    }
    context["context_digest"] = structured_sha256(context.reject { |key, _| key == "context_digest" })
    context
  rescue ArgumentError
    nil
  end

  def founder_quality_applicable?(applicability, role:, profile_id:, stage_id:, section_ids:)
    return false unless applicability.is_a?(Hash)

    return false unless token_applies?(applicability["roles"], role)
    return false unless token_applies?(applicability["profile_ids"], profile_id)
    return false unless token_applies?(applicability["stage_ids"], stage_id)

    bound_sections = Array(applicability["section_ids"]).map(&:to_s)
    return true if bound_sections.empty? || bound_sections.include?("*")
    return true if DIRECTOR_ROLES.include?(role.to_s)

    !(bound_sections & Array(section_ids).map(&:to_s)).empty?
  end

  def token_applies?(values, token)
    candidates = Array(values).map(&:to_s)
    candidates.include?("*") || candidates.include?(token.to_s)
  end

  def normalize_founder_quality_context(root, value)
    return nil if value.nil?
    raise ContractError, "founder quality context must be an object" unless value.is_a?(Hash)

    context = canonical_value(value)
    patterns = Array(context["patterns"])
    return nil if patterns.empty?
    raise ContractError, "founder quality context exceeds bounded pattern limit" if patterns.length > FOUNDER_QUALITY_PATTERN_LIMIT

    source = context["source_sidecar"].to_h
    validate_path = contained_file(root, source.fetch("path"))
    actual = Digest::SHA256.file(validate_path).hexdigest
    raise ContractError, "founder quality context source SHA-256 is stale" unless actual == source.fetch("sha256").to_s
    raise ContractError, "founder quality context must use active v3 sidecar" unless source["schema_version"] == IdolRunFollowupSidecar::V3_VERSION
    IdolRunFollowupSidecar::RAW_FEEDBACK_KEYS.each do |key|
      raise ContractError, "founder quality context must not carry raw feedback key #{key}" if contains_key?(context, key)
    end
    context["pattern_limit"] = FOUNDER_QUALITY_PATTERN_LIMIT
    context["context_digest"] = structured_sha256(context.reject { |key, _| key == "context_digest" })
    context
  rescue KeyError => e
    raise ContractError, "founder quality context is incomplete: #{e.message}"
  end

  def contains_key?(value, key)
    case value
    when Hash
      return true if value.key?(key) || value.key?(key.to_sym)

      value.values.any? { |item| contains_key?(item, key) }
    when Array
      value.any? { |item| contains_key?(item, key) }
    else
      false
    end
  end

  def validate_projection_registry!(projection, profiles, writer:)
    if writer == GRAPH_WRITER
      valid = projection["schema_version"] == "idol-graph-role-context-projection.v1" &&
        projection["status"] == "shadow_not_default" &&
        projection.dig("activation", "graph_v2_requires") == "verified_default_switch_receipt"
      raise ContractError, "graph role-context projection registry is not an admitted shadow route" unless valid
      unless profiles["schema_version"] == "idol-graph-skill-load-profiles.v1" &&
             profiles["status"] == "shadow_not_default" &&
             profiles.dig("activation", "default_writer") == LEGACY_WRITER
        raise ContractError, "graph role-context profile registry is not an admitted shadow route"
      end
    else
      valid = projection["schema_version"] == "idol-harness-role-context-projection.v1" && projection["status"] == "active"
      raise ContractError, "role-context projection registry is not active" unless valid
      raise ContractError, "role-context profile registry is not active" unless profiles["status"] == "active"
    end
    expected = projection.dig("source_registry", "schema_version")
    raise ContractError, "role-context source registry version mismatch" unless profiles["schema_version"] == expected
    rules = Array(projection["rules"])
    duplicate_exact = rules.group_by { |row| [row["binding_id"], Array(row["profile_ids"]).sort] }.select { |_key, rows| rows.length > 1 }
    raise ContractError, "role-context projection registry has duplicate rules" unless duplicate_exact.empty?
  end

  def select_rule(registry, binding_id, profile_id)
    rules = Array(registry["rules"]).select do |row|
      row.is_a?(Hash) && row["binding_id"].to_s == binding_id.to_s && Array(row["profile_ids"]).map(&:to_s).include?(profile_id.to_s)
    end
    raise ContractError, "role-context projection has multiple exact profile rules: #{binding_id}.#{profile_id}" if rules.length > 1
    return rules.first if rules.length == 1
    wildcard = Array(registry["rules"]).select do |row|
      row.is_a?(Hash) && row["binding_id"].to_s == binding_id.to_s && Array(row["profile_ids"]).map(&:to_s).include?("*")
    end
    raise ContractError, "role-context projection has multiple wildcard rules: #{binding_id}" if wildcard.length > 1
    wildcard.first
  end

  def default_mode(registry, kind, path)
    defaults = registry.fetch("defaults")
    return defaults.fetch("skill_mode") if kind == "skill"
    STRUCTURED_EXTENSIONS.include?(path.extname.downcase) ? defaults.fetch("structured_read_mode") : defaults.fetch("markdown_read_mode")
  end

  def default_reason(mode, kind)
    return "The complete owning skill remains the reusable Department Recipe." if kind == "skill"
    return "The structured contract is hash-bound and structurally preflighted; runtime prose duplication is excluded." if mode == "pointer_only"
    "The complete bound Markdown instruction is required because no safe narrower rule is registered."
  end

  def binding_map(registry, key)
    Array(registry[key]).each_with_object({}) do |row, result|
      next unless row.is_a?(Hash)
      id = row.fetch("binding_id").to_s
      raise ContractError, "duplicate #{key} binding: #{id}" if result.key?(id)
      result[id] = row
    end
  end

  def normalize_live_run_state(value)
    state = value.is_a?(Hash) ? value : {}
    {
      "open_hold_ids" => Array(state["open_hold_ids"]).map(&:to_s).reject(&:empty?).uniq,
      "consumed_helper_ids" => Array(state["consumed_helper_ids"]).map(&:to_s).reject(&:empty?).uniq,
      "run_followup_path" => state["run_followup_path"].to_s.empty? ? nil : state["run_followup_path"].to_s
    }
  end

  def live_run_state_present?(state)
    return false unless state.is_a?(Hash)

    Array(state["open_hold_ids"]).any? ||
      Array(state["consumed_helper_ids"]).any? ||
      !state["run_followup_path"].to_s.empty?
  end

  def extract_live_run_state(root, document)
    runtime_return = document["runtime_return"].is_a?(Hash) ? document["runtime_return"] : {}
    open_holds = Array(runtime_return["hold_reasons"]).map(&:to_s).reject(&:empty?).uniq
    consumed = []
    Array(runtime_return["helper_consumption_receipts"]).each do |row|
      next unless row.is_a?(Hash)

      path = Pathname.new(root).join(row["path"].to_s)
      next unless path.file?

      receipt = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
      next unless receipt.is_a?(Hash) && receipt["director_disposition"].to_s == "consume"

      consumed << receipt["helper_id"].to_s
    end
    sidecar = Pathname.new(root).join(document["run"].to_s, "review/harness-improvement-review.yaml")
    {
      "open_hold_ids" => open_holds,
      "consumed_helper_ids" => consumed.reject(&:empty?).uniq,
      "run_followup_path" => sidecar.file? ? sidecar.relative_path_from(Pathname.new(root).expand_path.cleanpath).to_s : nil
    }
  end

  def load_mapping(path)
    value = case path.extname.downcase
            when ".json" then JSON.parse(path.read)
            else YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
            end
    raise ContractError, "document must be an object: #{path}" unless value.is_a?(Hash)
    value
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError, "cannot parse #{path}: #{e.message}"
  end

  def validate_json_schema_file!(root:, schema_relative:, instance_path:, label:)
    root = Pathname.new(root).expand_path.cleanpath
    schema_path = contained_file(root, schema_relative)
    # Execute the validator through the runtime colocated with this library.
    # `root` may intentionally be an isolated contract fixture and should not
    # need to clone the repository's virtual environment.
    python = contained_file(IMPLEMENTATION_ROOT, "scripts/idol-video-python")
    validator = contained_file(IMPLEMENTATION_ROOT, "scripts/validate_json_schema.py")
    stdout, stderr, status = Open3.capture3(
      python.to_s,
      validator.to_s,
      schema_path.to_s,
      Pathname.new(instance_path).to_s,
      chdir: root.to_s
    )
    return true if status.success?

    message = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
    raise ContractError, "#{label} failed JSON Schema validation: #{message}"
  end

  def contained_file(root, raw)
    path = Pathname.new(raw.to_s)
    path = root.join(path) unless path.absolute?
    path = path.expand_path.cleanpath
    relative = path.relative_path_from(root).to_s
    raise ContractError, "path escapes repository: #{raw}" if relative == ".." || relative.start_with?("../")
    raise ContractError, "file is missing: #{raw}" unless path.file?
    path
  rescue ArgumentError
    raise ContractError, "path escapes repository: #{raw}"
  end

  def file_pointer(root, path)
    {"path" => path.relative_path_from(root).to_s, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def pack_id(assignment_id, profile_id, checkpoint_id)
    token = [assignment_id, profile_id, checkpoint_id].join("_").upcase.gsub(/[^A-Z0-9_]+/, "_").gsub(/_+/, "_").sub(/\A_/, "").sub(/_\z/, "")
    token = "PACK_#{Digest::SHA256.hexdigest([assignment_id, profile_id, checkpoint_id].join("|"))[0, 16].upcase}" if token.length < 3
    "ROLE_CONTEXT_#{token[0, 160]}"
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical_value(value[key]) }
    when Array
      value.map { |item| canonical_value(item) }
    else value
    end
  end

  def structured_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end
end
