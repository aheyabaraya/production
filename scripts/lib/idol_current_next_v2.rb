# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "time"
require "yaml"

module IdolCurrentNextV2
  SCHEMA_VERSION = "harness-current-next.v2"
  DDI_SCHEMA_VERSION = "idol-director-dispatch-index.v4"
  DEPARTMENT_DISPATCH_SCHEMA_VERSION = "idol-department-dispatch.v8"
  DDI_ROLE = "director_dispatch_index_v4"
  LEGACY_ROLES = {
    "source_next_unit" => "legacy_harness_next_unit_v1",
    "source_founder_gate" => "legacy_harness_founder_gate_v1",
    "source_action_queue" => "legacy_harness_action_queue_v1"
  }.freeze
  LEGACY_SCHEMAS = {
    "source_next_unit" => "harness-next-unit.v1",
    "source_founder_gate" => "harness-founder-gate.v1",
    "source_action_queue" => "harness-action-queue.v1"
  }.freeze

  class Error < StandardError; end

  module_function

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  def canonical_json_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original = value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical_json_value(value.fetch(original))
      end
    when Array
      value.map { |item| canonical_json_value(item) }
    when Date, Time
      value.iso8601
    else
      value
    end
  end

  def row_sha256(row)
    Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(row)))
  end

  def normalized_root(root)
    Pathname.new(root).expand_path.cleanpath
  end

  def resolve_path(root, value, label)
    raise Error, "#{label} path is missing" if blank?(value)

    base = normalized_root(root)
    raw = Pathname.new(value.to_s)
    resolved = raw.absolute? ? raw.expand_path.cleanpath : base.join(raw).expand_path.cleanpath
    boundary = base.to_s
    unless resolved.to_s == boundary || resolved.to_s.start_with?("#{boundary}#{File::SEPARATOR}")
      raise Error, "#{label} escapes repository root"
    end
    resolved
  end

  def relative_path(root, value, label = "artifact")
    resolve_path(root, value, label).relative_path_from(normalized_root(root)).to_s
  end

  def contained_file?(root, path)
    base = normalized_root(root).realpath.to_s
    target = path.realpath.to_s
    target == base || target.start_with?("#{base}#{File::SEPARATOR}")
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  def load_yaml_hash(root, path, label)
    resolved = resolve_path(root, path, label)
    raise Error, "#{label} is not readable: #{path}" unless resolved.file?
    raise Error, "#{label} resolves outside repository root" unless contained_file?(root, resolved)

    document = YAML.safe_load(
      resolved.read(encoding: "utf-8"),
      permitted_classes: [Date, Time],
      aliases: true
    )
    raise Error, "#{label} must be a mapping" unless document.is_a?(Hash)

    [document, resolved]
  rescue Psych::Exception => error
    raise Error, "cannot parse #{label}: #{error.message}"
  end

  def verified_binding(root, binding, label, expected_role:, required_path: nil)
    raise Error, "#{label} must be an artifact binding" unless binding.is_a?(Hash)

    resolved = resolve_path(root, binding["path"], label)
    raise Error, "#{label} is not readable: #{binding['path']}" unless resolved.file?
    raise Error, "#{label} resolves outside repository root" unless contained_file?(root, resolved)
    expected_sha = binding["sha256"].to_s
    raise Error, "#{label} SHA-256 is malformed" unless expected_sha.match?(/\A[a-f0-9]{64}\z/)
    actual_sha = Digest::SHA256.file(resolved).hexdigest
    raise Error, "#{label} SHA-256 is stale" unless actual_sha == expected_sha
    raise Error, "#{label} role must be #{expected_role}" unless binding["role"].to_s == expected_role

    if required_path
      required = resolve_path(root, required_path, "required #{label}")
      raise Error, "#{label} must bind #{relative_path(root, required)}" unless resolved == required
    end

    {
      "path" => relative_path(root, resolved, label),
      "sha256" => expected_sha,
      "role" => expected_role
    }
  end

  def validate_ddi_order!(ddi)
    holds = Array(ddi["holds"])
    hold_ids = holds.map { |row| row.is_a?(Hash) ? row["hold_id"].to_s : "" }
    raise Error, "DDI holds are not in canonical hold_id order" unless hold_ids == hold_ids.sort
    unless hold_ids.all? { |id| !id.empty? } && hold_ids.uniq.length == hold_ids.length
      raise Error, "DDI hold ids must be unique and non-empty"
    end

    review_queue = ddi["review_queue"]
    raise Error, "DDI review_queue must be a mapping" unless review_queue.is_a?(Hash)
    unless review_queue["selection_order"].to_s == "dependency_rank_then_returned_at_then_dispatch_id"
      raise Error, "DDI review queue selection order is unsupported"
    end
    items = Array(review_queue["items"])
    expected_items = items.sort_by do |row|
      [row["dependency_rank"].to_i, blank?(row["returned_at"]) ? "9999" : row["returned_at"].to_s, row["dispatch_id"].to_s]
    end
    raise Error, "DDI review queue is not in its declared canonical order" unless items == expected_items

    action_ids = Array(ddi["next_actions"]).map { |row| row.is_a?(Hash) ? row["next_action_id"].to_s : "" }
    unless action_ids.all? { |id| !id.empty? } && action_ids.uniq.length == action_ids.length
      raise Error, "DDI next-action ids must be unique and non-empty"
    end

    heads = Array(ddi["current_heads"])
    expected_heads = heads.sort_by { |row| [row["stage_id"].to_s, row["logical_artifact_id"].to_s, row["head_id"].to_s] }
    raise Error, "DDI canonical heads are not in canonical stage/artifact/head order" unless heads == expected_heads
  end

  def dispatch_rows_by_id(ddi)
    rows = Array(ddi["dispatches"])
    ids = rows.map { |row| row.is_a?(Hash) ? row["dispatch_id"].to_s : "" }
    unless ids.all? { |id| !id.empty? } && ids.uniq.length == ids.length
      raise Error, "DDI dispatch ids must be unique and non-empty"
    end
    rows.each_with_object({}) { |row, result| result[row["dispatch_id"].to_s] = row }
  end

  def action_dispatch_id(ddi, action_id)
    matches = Array(ddi["dispatches"]).select do |row|
      Array(row["next_action_ids"]).map(&:to_s).include?(action_id.to_s)
    end
    unless matches.length == 1
      raise Error, "DDI next action #{action_id} does not resolve to exactly one dispatch"
    end
    matches.first["dispatch_id"].to_s
  end

  def expected_selection(ddi)
    holds = Array(ddi["holds"])
    index = holds.index { |row| row.is_a?(Hash) && row["state"].to_s == "open" }
    if index
      row = holds.fetch(index)
      return {
        "kind" => "open_hold",
        "id" => row["hold_id"].to_s,
        "dispatch_id" => blank?(row["dispatch_id"]) ? nil : row["dispatch_id"].to_s,
        "json_pointer" => "/holds/#{index}",
        "row_sha256" => row_sha256(row),
        "state" => row["state"].to_s
      }
    end

    items = Array(ddi.dig("review_queue", "items"))
    index = items.index { |row| row.is_a?(Hash) && row["blocks_next"] == true }
    if index
      row = items.fetch(index)
      return {
        "kind" => "review_queue",
        "id" => row["dispatch_id"].to_s,
        "dispatch_id" => row["dispatch_id"].to_s,
        "json_pointer" => "/review_queue/items/#{index}",
        "row_sha256" => row_sha256(row),
        "state" => row["queue_state"].to_s
      }
    end

    actions = Array(ddi["next_actions"])
    index = actions.index { |row| row.is_a?(Hash) && %w[open ready in_progress].include?(row["state"].to_s) }
    if index
      row = actions.fetch(index)
      action_id = row["next_action_id"].to_s
      return {
        "kind" => "next_action",
        "id" => action_id,
        "dispatch_id" => action_dispatch_id(ddi, action_id),
        "json_pointer" => "/next_actions/#{index}",
        "row_sha256" => row_sha256(row),
        "state" => row["state"].to_s
      }
    end

    indexed = !Array(ddi["dispatches"]).empty? || !Array(ddi["current_heads"]).empty? ||
              !holds.empty? || !items.empty? || !actions.empty? ||
              ddi.dig("dispatch_source_set", "entry_count").to_i.positive?
    {
      "kind" => indexed ? "no_actionable_unit" : "migration_hold",
      "id" => nil,
      "dispatch_id" => nil,
      "json_pointer" => nil,
      "row_sha256" => nil,
      "state" => indexed ? "none" : "ddi_has_no_indexed_dispatch_evidence"
    }
  end

  def expected_status(selection)
    {
      "open_hold" => "hold",
      "review_queue" => "review_required",
      "next_action" => "ready",
      "no_actionable_unit" => "no_actionable_units",
      "migration_hold" => "migration_hold"
    }.fetch(selection["kind"])
  end

  def expected_owner(ddi, selection)
    return nil if selection["json_pointer"].nil?

    value = case selection["kind"]
            when "open_hold"
              Array(ddi["holds"])[selection["json_pointer"].split("/").last.to_i]["owner"]
            when "review_queue"
              Array(ddi.dig("review_queue", "items"))[selection["json_pointer"].split("/").last.to_i]["director_owner"]
            when "next_action"
              Array(ddi["next_actions"])[selection["json_pointer"].split("/").last.to_i]["owner"]
            end
    blank?(value) ? nil : value.to_s
  end

  def resolve_selection_row(ddi, selection)
    pointer = selection["json_pointer"]
    return nil if pointer.nil?

    case selection["kind"]
    when "open_hold"
      Array(ddi["holds"])[pointer.split("/").last.to_i]
    when "review_queue"
      Array(ddi.dig("review_queue", "items"))[pointer.split("/").last.to_i]
    when "next_action"
      Array(ddi["next_actions"])[pointer.split("/").last.to_i]
    end
  end

  def validate_canonical_heads!(root, current_next, ddi, selection)
    projection = current_next.dig("frontier_binding", "canonical_heads")
    raise Error, "current-next canonical_heads must be a mapping" unless projection.is_a?(Hash)

    heads = Array(ddi["current_heads"])
    current = []
    held_or_ambiguous = false
    heads.each_with_index do |row, index|
      raise Error, "DDI current_heads[#{index}] must be a mapping" unless row.is_a?(Hash)
      ambiguous = row["supersession_state"].to_s == "ambiguous_hold"
      held_or_ambiguous ||= row["state"].to_s == "held" || ambiguous
      next unless row["state"].to_s == "current"

      artifact = verified_binding(root, row["artifact"], "DDI current_heads[#{index}].artifact", expected_role: row.dig("artifact", "role").to_s)
      current << {
        "head_id" => row["head_id"].to_s,
        "json_pointer" => "/current_heads/#{index}",
        "row_sha256" => row_sha256(row),
        "artifact" => artifact
      }
    end
    if held_or_ambiguous && selection["kind"] != "open_hold"
      raise Error, "DDI held or ambiguous canonical head lacks the required open HOLD frontier"
    end

    selected_dispatch = dispatch_rows_by_id(ddi)[selection["dispatch_id"].to_s]
    if selected_dispatch
      matching = heads.select { |row| row["source_dispatch_id"].to_s == selection["dispatch_id"].to_s }
      invalid = matching.any? do |row|
        row["state"].to_s != "current" || row["supersession_state"].to_s == "ambiguous_hold"
      end
      if invalid && selection["kind"] != "open_hold"
        raise Error, "selected dispatch resolves only to a held, stale, or ambiguous canonical head"
      end
      if selected_dispatch.dig("lifecycle", "current_state").to_s == "promoted" &&
         matching.none? { |row| row["state"].to_s == "current" }
        raise Error, "promoted selected dispatch lacks its corresponding current canonical head"
      end
    end

    resolution = if held_or_ambiguous
                   "held_or_ambiguous"
                 elsif current.any?
                   "bound"
                 elsif selected_dispatch
                   "not_yet_promoted"
                 else
                   "none_declared"
                 end
    expected = {"resolution" => resolution, "items" => current}
    raise Error, "current-next canonical_heads differs from the hash-bound DDI" unless projection == expected
  end

  def verify_legacy_evidence(root, current_next, run, required_keys, expected_paths)
    evidence = current_next["legacy_evidence"]
    raise Error, "current-next legacy_evidence must be a mapping" unless evidence.is_a?(Hash)
    unless evidence["selection_authority"] == false
      raise Error, "current-next legacy_evidence selection_authority must be false"
    end

    bindings = {}
    documents = {}
    LEGACY_ROLES.each do |key, role|
      binding = evidence[key]
      if binding.nil?
        raise Error, "current-next legacy_evidence #{key} is required" if required_keys.include?(key)
        next
      end
      verified = verified_binding(
        root,
        binding,
        "current-next legacy_evidence #{key}",
        expected_role: role,
        required_path: expected_paths[key]
      )
      document, = load_yaml_hash(root, verified["path"], "current-next legacy_evidence #{key}")
      expected_schema = LEGACY_SCHEMAS.fetch(key)
      unless document["schema_version"].to_s == expected_schema
        raise Error, "current-next legacy_evidence #{key} schema must be #{expected_schema}"
      end
      unless document["run"].to_s == run.to_s
        raise Error, "current-next legacy_evidence #{key} belongs to another run"
      end
      bindings[key] = verified
      documents[key] = document
    end
    [bindings, documents]
  end

  def load_active(path:, run:, root:, require_actionable: false, require_legacy: [], expected_legacy_paths: {})
    current_next, current_next_path = load_yaml_hash(root, path, "current-next")
    unless current_next["schema_version"].to_s == SCHEMA_VERSION
      raise Error, "active current-next schema must be #{SCHEMA_VERSION}; v1 is legacy evidence only"
    end
    raise Error, "current-next artifact_type must be harness_current_next" unless current_next["artifact_type"].to_s == "harness_current_next"
    raise Error, "current-next belongs to another run" unless current_next["run"].to_s == run.to_s

    frontier = current_next["frontier_binding"]
    raise Error, "current-next frontier_binding must be a mapping" unless frontier.is_a?(Hash)
    ddi_path = File.join(run.to_s, "work", "director-dispatch-index.yaml")
    ddi_binding = verified_binding(
      root,
      frontier["director_dispatch_index"],
      "current-next director dispatch index",
      expected_role: DDI_ROLE,
      required_path: ddi_path
    )
    ddi, = load_yaml_hash(root, ddi_binding["path"], "director dispatch index")
    unless ddi["schema_version"].to_s == DDI_SCHEMA_VERSION
      raise Error, "director dispatch index schema must be #{DDI_SCHEMA_VERSION}"
    end
    raise Error, "director dispatch index belongs to another run" unless ddi["run"].to_s == run.to_s
    source_set_sha = ddi["source_set_sha256"].to_s
    raise Error, "director dispatch index source_set_sha256 is malformed" unless source_set_sha.match?(/\A[a-f0-9]{64}\z/)
    unless ddi.dig("source_set_digest", "sha256").to_s == source_set_sha &&
           frontier["source_set_sha256"].to_s == source_set_sha
      raise Error, "current-next and DDI source-set hashes disagree"
    end

    validate_ddi_order!(ddi)
    expected = expected_selection(ddi)
    selection = frontier["selection"]
    raise Error, "current-next selection must be a mapping" unless selection.is_a?(Hash)
    raise Error, "current-next selection differs from deterministic DDI precedence" unless selection == expected
    unless current_next["status"].to_s == expected_status(selection)
      raise Error, "current-next status does not match its DDI selection"
    end
    unless current_next["owner"] == expected_owner(ddi, selection)
      raise Error, "current-next owner does not match its DDI selection"
    end
    if require_actionable && %w[no_actionable_unit migration_hold].include?(selection["kind"].to_s)
      raise Error, "current-next has no actionable DDI row"
    end
    selection_row = resolve_selection_row(ddi, selection)
    if require_actionable && !selection_row.is_a?(Hash)
      raise Error, "current-next actionable selection does not resolve to a DDI row"
    end

    validate_canonical_heads!(root, current_next, ddi, selection)
    required_keys = Array(require_legacy).map(&:to_s)
    unknown = required_keys - LEGACY_ROLES.keys
    raise Error, "unknown required legacy evidence key(s): #{unknown.join(', ')}" unless unknown.empty?
    expected_paths = expected_legacy_paths.each_with_object({}) do |(key, value), result|
      result[key.to_s] = value
    end
    bindings, documents = verify_legacy_evidence(root, current_next, run, required_keys, expected_paths)

    {
      "root" => normalized_root(root),
      "document" => current_next,
      "path" => relative_path(root, current_next_path, "current-next"),
      "director_dispatch_index" => ddi,
      "director_dispatch_index_binding" => ddi_binding,
      "selection" => selection,
      "selection_row" => selection_row,
      "legacy_bindings" => bindings,
      "legacy_documents" => documents
    }
  end

  def authority_scope(context)
    selection = context.fetch("selection")
    row = context["selection_row"]
    return {} unless row.is_a?(Hash)
    return row["scope"].is_a?(Hash) ? row["scope"] : {} unless selection["kind"].to_s == "review_queue"

    dispatch_id = selection["dispatch_id"].to_s
    dispatch = Array(context.dig("director_dispatch_index", "dispatches")).find do |candidate|
      candidate.is_a?(Hash) && candidate["dispatch_id"].to_s == dispatch_id
    end
    dispatch.is_a?(Hash) && dispatch["scope"].is_a?(Hash) ? dispatch["scope"] : {}
  end

  def require_03v_authority!(context)
    selection = context.fetch("selection")
    unless selection["kind"].to_s == "next_action"
      raise Error, "03V continuation requires a selected DDI next_action; HOLD and review_queue rows cannot authorize continuation"
    end
    action_code = context.dig("selection_row", "action_code").to_s
    unless action_code == "advance_dispatch"
      raise Error, "selected DDI next_action action_code #{action_code.inspect} does not authorize 03V continuation"
    end
    scope = authority_scope(context)
    stage = scope["stage_id"].to_s
    unless %w[video_motion_direction video_playback_review].include?(stage)
      raise Error, "active DDI frontier stage #{stage.inspect} does not authorize a 03V operation"
    end
    scope
  end

  def require_03v_legacy_gate!(context)
    next_unit = context.dig("legacy_documents", "source_next_unit")
    founder_gate = context.dig("legacy_documents", "source_founder_gate")
    action_queue = context.dig("legacy_documents", "source_action_queue")
    unless next_unit.is_a?(Hash) && founder_gate.is_a?(Hash) && action_queue.is_a?(Hash)
      raise Error, "03V operation requires the exact legacy next-unit, founder-gate, and action-queue evidence"
    end
    unless founder_gate["gate_type"].to_s == "03v_front_playback_generation"
      raise Error, "legacy founder-gate evidence is not a 03V front playback gate"
    end

    scope = require_03v_authority!(context)
    require_legacy_join!(context, %w[source_next_unit source_founder_gate source_action_queue])
    authoritative_sections = Array(scope["section_ids"]).map(&:to_s).sort
    gate_sections = Array(founder_gate["section_ids"]).map(&:to_s).sort
    if authoritative_sections.any? && authoritative_sections != gate_sections
      raise Error, "legacy 03V gate sections differ from the active DDI frontier scope"
    end
    {"next_unit" => next_unit, "founder_gate" => founder_gate, "action_queue" => action_queue}
  end

  def pointer_pairs(value, result = [])
    case value
    when Hash
      path = value["path"].to_s
      sha256 = value["sha256"].to_s
      result << [path, sha256] if !path.empty? && sha256.match?(/\A[a-f0-9]{64}\z/)
      value.each_value { |child| pointer_pairs(child, result) }
    when Array
      value.each { |child| pointer_pairs(child, result) }
    end
    result
  end

  def selected_dispatch(context)
    dispatch_id = context.dig("selection", "dispatch_id").to_s
    return nil if dispatch_id.empty?

    Array(context.dig("director_dispatch_index", "dispatches")).find do |row|
      row.is_a?(Hash) && row["dispatch_id"].to_s == dispatch_id
    end
  end

  def selected_department_dispatch!(context)
    root = context.fetch("root")
    selection = context.fetch("selection")
    selection_row = context.fetch("selection_row")
    dispatch = selected_dispatch(context)
    raise Error, "selected DDI frontier row lacks its dispatch record" unless dispatch.is_a?(Hash)

    pointer = dispatch["dispatch_pointer"]
    verified = verified_binding(
      root,
      pointer,
      "selected DDI department dispatch",
      expected_role: pointer.is_a?(Hash) ? pointer["role"].to_s : ""
    )
    pointer_pair = [verified["path"], verified["sha256"]]
    dependencies = pointer_pairs(selection_row["dependency_pointers"]).map do |path, sha256|
      [relative_path(root, path, "selected DDI dependency"), sha256]
    end
    unless dependencies.include?(pointer_pair)
      raise Error, "selected DDI next action is not bound to its exact department dispatch pointer"
    end

    document, = load_yaml_hash(root, verified["path"], "selected DDI department dispatch")
    unless document["schema_version"].to_s == DEPARTMENT_DISPATCH_SCHEMA_VERSION
      raise Error, "selected department dispatch schema must be #{DEPARTMENT_DISPATCH_SCHEMA_VERSION}"
    end
    raise Error, "selected department dispatch artifact_type must be department_dispatch" unless document["artifact_type"].to_s == "department_dispatch"
    unless document["run"].to_s == context.dig("document", "run").to_s
      raise Error, "selected department dispatch belongs to another run"
    end
    unless document["dispatch_id"].to_s == selection["dispatch_id"].to_s
      raise Error, "selected department dispatch id differs from the DDI frontier"
    end
    [dispatch, document, verified]
  end

  def require_legacy_join!(context, keys)
    _dispatch, department_dispatch, = selected_department_dispatch!(context)
    sources = Array(department_dispatch.dig("launch", "sources"))
    Array(keys).each do |key|
      binding = context.dig("legacy_bindings", key.to_s)
      raise Error, "required legacy evidence #{key} is missing" unless binding.is_a?(Hash)

      source_id = LEGACY_ROLES.fetch(key.to_s)
      matches = sources.select { |source| source.is_a?(Hash) && source["source_id"].to_s == source_id }
      unless matches.length == 1
        raise Error, "selected department dispatch launch.sources must contain exactly one #{source_id} binding"
      end
      source = matches.first
      source_path = relative_path(context.fetch("root"), source["path"], "selected department dispatch #{source_id}")
      unless source_path == binding["path"].to_s && source["sha256"].to_s == binding["sha256"].to_s
        raise Error, "selected department dispatch #{source_id} does not exactly bind current-next legacy_evidence #{key}"
      end
    end
    true
  end

  def selected_pointer_paths(context)
    values = []
    collect_paths = lambda do |value|
      case value
      when Hash
        path = value["path"].to_s
        values << path unless path.empty?
        value.each_value { |child| collect_paths.call(child) }
      when Array
        value.each { |child| collect_paths.call(child) }
      end
    end
    collect_paths.call(context["selection_row"])
    values.uniq
  end
end
