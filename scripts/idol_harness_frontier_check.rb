# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "set"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
RUNS_ROOT = ROOT.join("runs")
DEFAULT_POINTER = ROOT.join("automation", "current-next.yaml")
POINTER_SCHEMA = ROOT.join("schemas", "harness-current-next.schema.json")
OUTPUT_SCHEMA_VERSION = "idol-harness-frontier-check.v1"

class FrontierCheck
  ACTIVE_POINTER_VERSION = "harness-current-next.v2"
  DDI_VERSION = "idol-director-dispatch-index.v4"

  def initialize(pointer_path:, requested_run:, full_audit:)
    @pointer_path = pointer_path.expand_path
    @requested_run = requested_run
    @full_audit_requested = full_audit
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @checked = []
    @blockers = []
    @blocker_keys = Set.new
    @checked_path_values = Set.new
    @path_probe_cache = {}
    @digest_cache = {}
    @pointer = nil
    @run_rel = nil
    @run_path = nil
    @full_audit = nil
    @ddi = nil
  end

  def call
    pointer_schema_status = validate_pointer_schema
    load_pointer if @pointer_path.file?
    active_version = validate_active_pointer_version if @pointer
    resolve_run if @pointer && active_version
    validate_frontier_binding if @pointer && @run_path
    validate_artifact_bindings if @pointer && @run_path
    run_full_audit if @full_audit_requested

    {
      "schema_version" => OUTPUT_SCHEMA_VERSION,
      "generated_at" => pointer_generated_at,
      "status" => @blockers.empty? ? "pass" : "blocked",
      "elapsed_ms" => elapsed_ms,
      "run" => @run_rel,
      "pointer" => {
        "path" => display_path(@pointer_path),
        "schema" => display_path(POINTER_SCHEMA),
        "schema_status" => pointer_schema_status
      },
      "scope" => scope,
      "checked" => @checked,
      "blockers" => @blockers,
      "full_audit" => @full_audit
    }
  end

  private

  def validate_active_pointer_version
    version = @pointer["schema_version"].to_s
    return true if version == ACTIVE_POINTER_VERSION

    add_check(
      id: "active_pointer_version",
      kind: "active_pointer_version",
      status: "blocked",
      path: display_path(@pointer_path),
      detail: "active frontier requires #{ACTIVE_POINTER_VERSION}; #{version.empty? ? 'no version' : version} is legacy or unsupported"
    )
    add_blocker(
      "active_pointer_version_invalid",
      display_path(@pointer_path),
      "active frontier rejects v1 and unsupported current-next pointers"
    )
    false
  end

  def validate_pointer_schema
    unless @pointer_path.file?
      add_check(
        id: "pointer_schema",
        kind: "pointer_schema",
        status: "blocked",
        path: display_path(@pointer_path),
        detail: "current-next pointer is missing"
      )
      add_blocker("pointer_missing", display_path(@pointer_path), "current-next pointer does not exist")
      return "blocked"
    end

    launcher = ROOT.join("scripts", "idol-video-python")
    validator = ROOT.join("scripts", "validate_json_schema.py")
    stdout, stderr, status = Open3.capture3(
      launcher.to_s,
      validator.to_s,
      POINTER_SCHEMA.to_s,
      @pointer_path.to_s,
      chdir: ROOT.to_s
    )
    detail = command_detail(stdout, stderr)
    if status.success?
      add_check(
        id: "pointer_schema",
        kind: "pointer_schema",
        status: "pass",
        path: display_path(@pointer_path),
        detail: detail.empty? ? "current-next pointer matches its schema" : detail
      )
      "pass"
    else
      add_check(
        id: "pointer_schema",
        kind: "pointer_schema",
        status: "blocked",
        path: display_path(@pointer_path),
        detail: detail.empty? ? "current-next schema validation failed" : detail
      )
      add_blocker(
        "pointer_schema_invalid",
        display_path(@pointer_path),
        detail.empty? ? "current-next schema validation failed" : detail
      )
      "blocked"
    end
  rescue Errno::ENOENT, Errno::EACCES => error
    add_check(
      id: "pointer_schema",
      kind: "pointer_schema",
      status: "blocked",
      path: display_path(@pointer_path),
      detail: "schema validator could not run: #{error.message}"
    )
    add_blocker(
      "pointer_schema_validator_unavailable",
      display_path(@pointer_path),
      "schema validator could not run: #{error.message}"
    )
    "blocked"
  end

  def load_pointer
    loaded = YAML.safe_load(
      @pointer_path.read(encoding: "utf-8"),
      permitted_classes: [Date, Time],
      aliases: false
    )
    unless loaded.is_a?(Hash)
      add_blocker("pointer_load_failed", display_path(@pointer_path), "current-next pointer is not an object")
      return
    end

    @pointer = stringify_keys(loaded)
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES => error
    add_blocker(
      "pointer_load_failed",
      display_path(@pointer_path),
      "current-next pointer could not be loaded: #{error.message}"
    )
  end

  def resolve_run
    declared = @pointer["run"]
    unless declared.is_a?(String) && !declared.strip.empty?
      add_check(
        id: "selected_run",
        kind: "selected_run",
        status: "blocked",
        path: declared.to_s,
        detail: "current-next does not select a run"
      )
      add_blocker("selected_run_missing", declared.to_s, "current-next does not select a run")
      return
    end

    normalized, error = normalize_repo_relative(declared)
    if error
      add_check(
        id: "selected_run",
        kind: "selected_run",
        status: "blocked",
        path: declared,
        detail: error
      )
      add_blocker("selected_run_invalid", declared, error)
      return
    end

    @run_rel = normalized
    target = ROOT.join(normalized).expand_path
    unless contained_path?(target, RUNS_ROOT)
      add_check(
        id: "selected_run",
        kind: "selected_run",
        status: "blocked",
        path: normalized,
        detail: "selected run is outside runs/"
      )
      add_blocker("selected_run_outside_runs", normalized, "selected run must be contained by runs/")
      return
    end

    requested_run_matches(normalized)

    unless target.directory?
      add_check(
        id: "selected_run",
        kind: "selected_run",
        status: "blocked",
        path: normalized,
        detail: "selected run directory is missing"
      )
      add_blocker("selected_run_missing", normalized, "selected run directory does not exist")
      return
    end

    unless real_contained_path?(target, RUNS_ROOT)
      add_check(
        id: "selected_run",
        kind: "selected_run",
        status: "blocked",
        path: normalized,
        detail: "selected run resolves outside runs/"
      )
      add_blocker("selected_run_symlink_escape", normalized, "selected run resolves outside runs/")
      return
    end

    @run_path = target
    add_check(
      id: "selected_run",
      kind: "selected_run",
      status: "pass",
      path: normalized,
      detail: "selected run exists and is contained by runs/"
    )
  end

  def requested_run_matches(declared_run)
    return if @requested_run.nil?

    normalized, error = normalize_repo_relative(@requested_run)
    if error
      add_blocker("run_argument_invalid", @requested_run.to_s, error)
    elsif normalized != declared_run
      add_blocker(
        "run_argument_mismatch",
        normalized,
        "requested run does not match current-next run #{declared_run}"
      )
    end
  end

  def validate_frontier_binding
    blocker_count = @blockers.length
    binding = @pointer["frontier_binding"]
    unless binding.is_a?(Hash)
      frontier_error("frontier_binding_missing", "frontier_binding must be an object")
      return
    end
    ddi_binding = binding["director_dispatch_index"]
    unless ddi_binding.is_a?(Hash)
      frontier_error("ddi_binding_missing", "frontier_binding.director_dispatch_index must be an artifact binding")
      return
    end
    expected_path = @run_path.join("work", "director-dispatch-index.yaml").relative_path_from(ROOT).to_s
    unless ddi_binding["path"].to_s == expected_path && ddi_binding["role"].to_s == "director_dispatch_index_v4"
      frontier_error("ddi_binding_not_canonical", "DDI binding must use #{expected_path} with role director_dispatch_index_v4")
      return
    end
    probe = probe_file(ddi_binding["path"], require_run_owned: true)
    unless probe[:status] == "pass"
      frontier_error(probe[:code], "DDI binding: #{probe[:message]}")
      return
    end
    expected_sha = ddi_binding["sha256"].to_s
    actual_sha = digest_for(probe[:absolute])
    unless expected_sha.match?(/\A[a-f0-9]{64}\z/) && expected_sha == actual_sha
      frontier_error("ddi_binding_sha256_mismatch", "DDI binding does not match the exact current bytes")
      return
    end
    @ddi = stringify_keys(YAML.safe_load(probe[:absolute].read, permitted_classes: [Date, Time], aliases: true))
    unless @ddi.is_a?(Hash) && @ddi["schema_version"].to_s == DDI_VERSION
      frontier_error("ddi_schema_version_invalid", "DDI binding must resolve to #{DDI_VERSION}")
      return
    end
    frontier_error("ddi_run_mismatch", "DDI belongs to another run") unless @ddi["run"].to_s == @run_rel
    source_set_sha = @ddi["source_set_sha256"].to_s
    unless source_set_sha.match?(/\A[a-f0-9]{64}\z/) &&
           source_set_sha == @ddi.dig("source_set_digest", "sha256").to_s &&
           source_set_sha == binding["source_set_sha256"].to_s
      frontier_error("ddi_source_set_mismatch", "frontier source_set_sha256 must exactly equal both DDI source-set hashes")
    end
    validate_ddi_canonical_order
    expected_selection = ddi_expected_selection
    actual_selection = binding["selection"]
    unless canonical_json_value(actual_selection) == canonical_json_value(expected_selection)
      frontier_error("frontier_selection_stale", "frontier selection does not equal the deterministic first DDI row at the declared precedence")
    end
    if actual_selection.is_a?(Hash) && actual_selection["id"].nil?
      frontier_error("frontier_selection_missing", "active frontier rejects a null-selected no-action or migration projection")
    end
    expected_heads = ddi_expected_canonical_heads(expected_selection)
    unless canonical_json_value(binding["canonical_heads"]) == canonical_json_value(expected_heads)
      frontier_error("canonical_heads_stale", "canonical head pointers or recursively sorted row hashes differ from DDI current_heads")
    end
    validate_selected_dispatch_head(expected_selection)
    validate_pending_ddi_binding(ddi_binding)

    status = @blockers.length == blocker_count ? "pass" : "blocked"
    add_check(
      id: "ddi_frontier_binding",
      kind: "sha256",
      status: status,
      path: expected_path,
      declared_sha256: expected_sha,
      actual_sha256: actual_sha,
      detail: status == "pass" ? "DDI v4 selection, canonical heads, and pending projection are exact" : "DDI frontier binding is not exact"
    )
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES, TypeError, ArgumentError => error
    frontier_error("ddi_frontier_validation_failed", "cannot validate DDI frontier binding: #{error.message}")
  end

  def validate_ddi_canonical_order
    holds = Array(@ddi["holds"])
    hold_ids = holds.map { |row| row.is_a?(Hash) ? row["hold_id"].to_s : "" }
    frontier_error("ddi_hold_order_invalid", "DDI holds are not in canonical hold_id order") unless hold_ids == hold_ids.sort && hold_ids.uniq.length == hold_ids.length

    queue = @ddi["review_queue"]
    unless queue.is_a?(Hash) && queue["selection_order"].to_s == "dependency_rank_then_returned_at_then_dispatch_id"
      frontier_error("ddi_review_order_invalid", "DDI review queue lacks its canonical selection order")
      return
    end
    items = Array(queue["items"])
    expected = items.sort_by do |row|
      [row["dependency_rank"].to_i, row["returned_at"].to_s.empty? ? "9999" : row["returned_at"].to_s, row["dispatch_id"].to_s]
    end
    frontier_error("ddi_review_order_invalid", "DDI review queue rows are not in declared canonical order") unless items == expected
  end

  def ddi_expected_selection
    holds = Array(@ddi["holds"])
    index = holds.index { |row| row.is_a?(Hash) && row["state"].to_s == "open" }
    if index
      row = holds.fetch(index)
      return selection_row("open_hold", row["hold_id"], row["dispatch_id"], "/holds/#{index}", row, row["state"])
    end

    reviews = Array(@ddi.dig("review_queue", "items"))
    index = reviews.index { |row| row.is_a?(Hash) && row["blocks_next"] == true }
    if index
      row = reviews.fetch(index)
      return selection_row("review_queue", row["dispatch_id"], row["dispatch_id"], "/review_queue/items/#{index}", row, row["queue_state"])
    end

    actions = Array(@ddi["next_actions"])
    index = actions.index { |row| row.is_a?(Hash) && %w[open ready in_progress].include?(row["state"].to_s) }
    if index
      row = actions.fetch(index)
      action_id = row["next_action_id"].to_s
      matching = Array(@ddi["dispatches"]).select { |dispatch| Array(dispatch["next_action_ids"]).map(&:to_s).include?(action_id) }
      frontier_error("next_action_dispatch_ambiguous", "selected DDI next action must resolve to exactly one dispatch") unless matching.length == 1
      dispatch_id = matching.length == 1 ? matching.first["dispatch_id"].to_s : nil
      return selection_row("next_action", action_id, dispatch_id, "/next_actions/#{index}", row, row["state"])
    end

    has_evidence = !Array(@ddi["dispatches"]).empty? || !Array(@ddi["current_heads"]).empty? ||
      !holds.empty? || !reviews.empty? || !actions.empty? || @ddi.dig("dispatch_source_set", "entry_count").to_i.positive?
    {
      "kind" => has_evidence ? "no_actionable_unit" : "migration_hold",
      "id" => nil,
      "dispatch_id" => nil,
      "json_pointer" => nil,
      "row_sha256" => nil,
      "state" => has_evidence ? "none" : "ddi_has_no_indexed_dispatch_evidence"
    }
  end

  def selection_row(kind, id, dispatch_id, pointer, row, state)
    {
      "kind" => kind,
      "id" => id.to_s,
      "dispatch_id" => dispatch_id.to_s.empty? ? nil : dispatch_id.to_s,
      "json_pointer" => pointer,
      "row_sha256" => row_digest(row),
      "state" => state.to_s
    }
  end

  def ddi_expected_canonical_heads(selection)
    heads = Array(@ddi["current_heads"])
    items = []
    held_or_ambiguous = false
    heads.each_with_index do |row, index|
      next unless row.is_a?(Hash)
      held_or_ambiguous ||= row["state"].to_s == "held" || row["supersession_state"].to_s == "ambiguous_hold"
      next unless row["state"].to_s == "current"
      items << {
        "head_id" => row["head_id"].to_s,
        "json_pointer" => "/current_heads/#{index}",
        "row_sha256" => row_digest(row),
        "artifact" => row["artifact"]
      }
    end
    selected_dispatch = Array(@ddi["dispatches"]).find { |row| row["dispatch_id"].to_s == selection["dispatch_id"].to_s }
    resolution = if held_or_ambiguous
                   "held_or_ambiguous"
                 elsif items.any?
                   "bound"
                 elsif selected_dispatch
                   "not_yet_promoted"
                 else
                   "none_declared"
                 end
    {"resolution" => resolution, "items" => items}
  end

  def validate_selected_dispatch_head(selection)
    dispatch_id = selection["dispatch_id"].to_s
    return if dispatch_id.empty?
    dispatch = Array(@ddi["dispatches"]).find { |row| row["dispatch_id"].to_s == dispatch_id }
    return unless dispatch
    matching = Array(@ddi["current_heads"]).select { |row| row["source_dispatch_id"].to_s == dispatch_id }
    invalid = matching.any? { |row| row["state"].to_s != "current" || row["supersession_state"].to_s == "ambiguous_hold" }
    if invalid && selection["kind"].to_s != "open_hold"
      frontier_error("selected_dispatch_head_invalid", "selected dispatch has only held, stale, or ambiguous canonical-head lineage")
    end
    if dispatch.dig("lifecycle", "current_state").to_s == "promoted" && matching.none? { |row| row["state"].to_s == "current" }
      frontier_error("promoted_dispatch_head_missing", "promoted selected dispatch lacks a corresponding current canonical head")
    end
  end

  def validate_pending_ddi_binding(ddi_binding)
    summary = @pointer["review_projection_pending"]
    pending_path = @run_path.join("work", "review-projection-pending.yaml")
    if summary.nil?
      frontier_error("review_projection_pending_omitted", "run-owned review projection pending index exists but current-next omits it") if pending_path.file?
      return
    end
    unless summary.is_a?(Hash) && binding_equal?(summary["director_dispatch_index"], ddi_binding)
      frontier_error("review_projection_ddi_mismatch", "review projection summary must bind the exact current-next DDI pointer")
      return
    end
    source = summary["source"]
    unless source.is_a?(Hash) && source["path"].to_s == pending_path.relative_path_from(ROOT).to_s
      frontier_error("review_projection_source_mismatch", "review projection summary does not bind the exact run-owned pending path")
      return
    end
    return unless pending_path.file?
    pending = stringify_keys(YAML.safe_load(pending_path.read, permitted_classes: [Date, Time], aliases: true))
    source_set_binding = pending["source_set"]
    source_set_probe = probe_file(source_set_binding["path"].to_s, require_run_owned: true)
    unless source_set_probe[:status] == "pass" && digest_for(source_set_probe[:absolute]) == source_set_binding["sha256"].to_s
      frontier_error("review_projection_source_set_stale", "pending source-set pointer is stale")
      return
    end
    source_set = stringify_keys(YAML.safe_load(source_set_probe[:absolute].read, permitted_classes: [Date, Time], aliases: true))
    unless binding_equal?(source_set["director_dispatch_index"], ddi_binding)
      frontier_error("review_projection_source_set_ddi_mismatch", "pending source-set DDI pointer differs from current-next")
    end
    known_ids = Array(@ddi["dispatches"]).map { |row| row["dispatch_id"].to_s } +
      Array(@ddi.dig("review_queue", "items")).map { |row| row["dispatch_id"].to_s }
    Array(pending["items"]).each_with_index do |item, index|
      frontier_error("review_projection_item_ddi_mismatch", "pending item #{index + 1} DDI pointer differs from current-next") unless binding_equal?(item["director_dispatch_index"], ddi_binding)
      frontier_error("review_projection_item_dispatch_missing", "pending item #{index + 1} references a dispatch absent from DDI") unless known_ids.include?(item["dispatch_id"].to_s)
    end
    frontier_error("review_projection_selection_override", "review projection pending may not override current-next selection") unless summary["selection_overridden"] == false && pending.dig("automation_boundaries", "current_next_selection_overridden") == false
  rescue Psych::Exception, Errno::ENOENT, Errno::EACCES, TypeError => error
    frontier_error("review_projection_validation_failed", "cannot validate pending projection DDI binding: #{error.message}")
  end

  def validate_artifact_bindings
    each_artifact_binding(@pointer) do |logical_path, binding|
      declared_path = binding["path"].to_s
      declared_sha = binding["sha256"].to_s
      @checked_path_values << declared_path unless declared_path.empty?
      probe = probe_file(declared_path, require_run_owned: path_under_runs_prefix?(declared_path))
      if probe[:status] != "pass"
        add_check(id: "sha256:#{logical_path}", kind: "sha256", status: "blocked", path: declared_path, declared_sha256: declared_sha, detail: probe[:message])
        add_blocker(probe[:code], declared_path, "#{logical_path}: #{probe[:message]}")
        next
      end
      actual = digest_for(probe[:absolute])
      status = declared_sha.match?(/\A[a-f0-9]{64}\z/) && actual == declared_sha ? "pass" : "blocked"
      add_check(id: "sha256:#{logical_path}", kind: "sha256", status: status, path: probe[:normalized], declared_sha256: declared_sha, actual_sha256: actual, detail: status == "pass" ? "artifact binding matches exact bytes" : "artifact binding SHA-256 differs")
      add_blocker("sha256_mismatch", probe[:normalized], "#{logical_path} does not match its declared SHA-256") if status == "blocked"
    end
  end

  def each_artifact_binding(value, segments = [], &block)
    case value
    when Hash
      if value.key?("path") && value.key?("sha256")
        block.call(segments.join("."), value)
      end
      value.each { |key, child| each_artifact_binding(child, segments + [key.to_s], &block) }
    when Array
      value.each_with_index { |child, index| each_artifact_binding(child, segments + [index.to_s], &block) }
    end
  end

  def canonical_json_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original = value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical_json_value(value[original])
      end
    when Array
      value.map { |item| canonical_json_value(item) }
    when Date, Time
      value.iso8601
    else
      value
    end
  end

  def row_digest(row)
    Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(row)))
  end

  def binding_equal?(left, right)
    %w[path sha256 role].all? { |key| left.is_a?(Hash) && right.is_a?(Hash) && left[key].to_s == right[key].to_s }
  end

  def frontier_error(code, message)
    add_blocker(code, @run_rel || display_path(@pointer_path), message)
  end

  def validate_selected_paths
    DIRECT_PATH_FIELDS.each do |keys, require_run_owned|
      value = dig_value(@pointer, keys)
      next unless value.is_a?(String) && !value.strip.empty?

      logical_path = keys.join(".")
      validate_selected_path(logical_path, value, require_run_owned: require_run_owned)
    end
  end

  def validate_selected_path(logical_path, declared_path, require_run_owned:)
    @checked_path_values << declared_path
    probe = probe_file(declared_path, require_run_owned: require_run_owned)
    if probe[:status] == "pass"
      add_check(
        id: "selected_path:#{logical_path}",
        kind: "selected_path",
        status: "pass",
        path: probe[:normalized],
        detail: "selected path exists within its allowed scope"
      )
    else
      add_check(
        id: "selected_path:#{logical_path}",
        kind: "selected_path",
        status: "blocked",
        path: declared_path,
        detail: probe[:message]
      )
      add_blocker(probe[:code], declared_path, "#{logical_path}: #{probe[:message]}")
    end
  end

  def validate_explicit_sha_pairs
    each_sha_pair(@pointer) do |logical_path, declared_path, declared_sha|
      @checked_path_values << declared_path.to_s unless declared_path.to_s.empty?
      unless declared_path.is_a?(String) && !declared_path.strip.empty?
        add_check(
          id: "sha256:#{logical_path}",
          kind: "sha256",
          status: "blocked",
          path: declared_path.to_s,
          declared_sha256: declared_sha.is_a?(String) ? declared_sha : nil,
          detail: "SHA-256 sibling does not name a non-empty path"
        )
        add_blocker(
          "sha256_path_invalid",
          logical_path,
          "SHA-256 sibling does not name a non-empty path"
        )
        next
      end

      unless declared_sha.is_a?(String) && declared_sha.match?(/\A[0-9a-f]{64}\z/)
        add_check(
          id: "sha256:#{logical_path}",
          kind: "sha256",
          status: "blocked",
          path: declared_path,
          declared_sha256: declared_sha.is_a?(String) ? declared_sha : nil,
          detail: "declared SHA-256 must be 64 lowercase hexadecimal characters"
        )
        add_blocker(
          "sha256_declaration_invalid",
          declared_path,
          "#{logical_path} must be 64 lowercase hexadecimal characters"
        )
        next
      end

      require_run_owned = path_under_runs_prefix?(declared_path)
      probe = probe_file(declared_path, require_run_owned: require_run_owned)
      if probe[:status] != "pass"
        add_check(
          id: "sha256:#{logical_path}",
          kind: "sha256",
          status: "blocked",
          path: declared_path,
          declared_sha256: declared_sha,
          detail: probe[:message]
        )
        add_blocker(probe[:code], declared_path, "#{logical_path}: #{probe[:message]}")
        next
      end

      actual_sha = digest_for(probe[:absolute])
      if actual_sha == declared_sha
        add_check(
          id: "sha256:#{logical_path}",
          kind: "sha256",
          status: "pass",
          path: probe[:normalized],
          declared_sha256: declared_sha,
          actual_sha256: actual_sha,
          detail: "selected artifact bytes match the declared SHA-256"
        )
      else
        add_check(
          id: "sha256:#{logical_path}",
          kind: "sha256",
          status: "blocked",
          path: probe[:normalized],
          declared_sha256: declared_sha,
          actual_sha256: actual_sha,
          detail: "selected artifact bytes do not match the declared SHA-256"
        )
        add_blocker(
          "sha256_mismatch",
          probe[:normalized],
          "#{logical_path} does not match its declared SHA-256"
        )
      end
    end
  end

  def run_full_audit
    unless @run_path
      add_check(
        id: "full_audit",
        kind: "full_audit",
        status: "skipped",
        path: display_path(ROOT.join("scripts", "idol_harness_state_check.rb")),
        detail: "full audit was not run because the selected run is invalid"
      )
      return
    end

    script = ROOT.join("scripts", "idol_harness_state_check.rb")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      script.to_s,
      @run_rel,
      "--json",
      chdir: ROOT.to_s
    )
    parsed = JSON.parse(stdout)
    @full_audit = {
      "exit_status" => status.exitstatus,
      "overall_status" => parsed["overall_status"],
      "counts" => parsed["counts"].is_a?(Hash) ? parsed["counts"] : {},
      "blocking_checks" => parsed["blocking_checks"].is_a?(Array) ? parsed["blocking_checks"] : [],
      "state_pointer_drift" => parsed["state_pointer_drift"].is_a?(Array) ? parsed["state_pointer_drift"] : []
    }

    if status.success? && parsed["overall_status"] == "validator_pass"
      add_check(
        id: "full_audit",
        kind: "full_audit",
        status: "pass",
        path: display_path(script),
        detail: "existing broad graph-engineering audit passed"
      )
    else
      detail = "existing broad graph-engineering audit returned #{parsed["overall_status"] || "unknown"}"
      add_check(
        id: "full_audit",
        kind: "full_audit",
        status: "blocked",
        path: display_path(script),
        detail: detail
      )
      add_blocker("full_audit_blocked", @run_rel, detail)
    end
  rescue JSON::ParserError => error
    detail = "full audit did not emit valid JSON: #{error.message}"
    detail = "#{detail}; #{command_detail("", stderr)}" unless command_detail("", stderr).empty?
    add_check(
      id: "full_audit",
      kind: "full_audit",
      status: "blocked",
      path: display_path(ROOT.join("scripts", "idol_harness_state_check.rb")),
      detail: detail
    )
    add_blocker("full_audit_invalid_output", @run_rel.to_s, detail)
  rescue Errno::ENOENT, Errno::EACCES => error
    detail = "full audit could not run: #{error.message}"
    add_check(
      id: "full_audit",
      kind: "full_audit",
      status: "blocked",
      path: display_path(ROOT.join("scripts", "idol_harness_state_check.rb")),
      detail: detail
    )
    add_blocker("full_audit_unavailable", @run_rel.to_s, detail)
  end

  def each_sha_pair(value, segments = [], &block)
    case value
    when Hash
      value.each do |key, declared_sha|
        key_string = key.to_s
        next unless key_string.end_with?("_sha256")

        base_key = key_string.delete_suffix("_sha256")
        next unless value.key?(base_key)

        logical_path = (segments + [key_string]).join(".")
        block.call(logical_path, value[base_key], declared_sha)
      end
      value.each { |key, child| each_sha_pair(child, segments + [key.to_s], &block) }
    when Array
      value.each_with_index { |child, index| each_sha_pair(child, segments + [index.to_s], &block) }
    end
  end

  def probe_file(declared_path, require_run_owned:)
    cache_key = [declared_path, require_run_owned]
    return @path_probe_cache[cache_key] if @path_probe_cache.key?(cache_key)

    normalized, error = normalize_repo_relative(declared_path)
    if error
      return @path_probe_cache[cache_key] = {
        status: "blocked", code: "selected_path_invalid", message: error
      }
    end

    absolute = ROOT.join(normalized).expand_path
    unless contained_path?(absolute, ROOT)
      return @path_probe_cache[cache_key] = {
        status: "blocked",
        code: "selected_path_outside_repo",
        message: "selected path is outside the repository"
      }
    end

    if require_run_owned && !contained_path?(absolute, @run_path)
      return @path_probe_cache[cache_key] = {
        status: "blocked",
        code: "selected_path_outside_run",
        message: "selected path is outside the selected run"
      }
    end

    if path_under_runs_prefix?(normalized) && !contained_path?(absolute, @run_path)
      return @path_probe_cache[cache_key] = {
        status: "blocked",
        code: "selected_path_other_run",
        message: "selected path points to a different run"
      }
    end

    unless absolute.file?
      return @path_probe_cache[cache_key] = {
        status: "blocked",
        code: "selected_path_missing",
        message: "selected file does not exist"
      }
    end

    allowed_real_root = require_run_owned || path_under_runs_prefix?(normalized) ? @run_path : ROOT
    unless real_contained_path?(absolute, allowed_real_root)
      return @path_probe_cache[cache_key] = {
        status: "blocked",
        code: "selected_path_symlink_escape",
        message: "selected file resolves outside its allowed scope"
      }
    end

    @path_probe_cache[cache_key] = {
      status: "pass",
      normalized: normalized,
      absolute: absolute
    }
  end

  def digest_for(path)
    real = path.realpath.to_s
    @digest_cache[real] ||= Digest::SHA256.file(real).hexdigest
  end

  def normalize_repo_relative(value)
    return [nil, "path must be a string"] unless value.is_a?(String)
    return [nil, "path must not be empty"] if value.strip.empty?

    candidate = Pathname.new(value)
    return [nil, "absolute paths are not allowed"] if candidate.absolute?

    normalized = candidate.cleanpath.to_s
    absolute = ROOT.join(normalized).expand_path
    return [nil, "path escapes the repository"] unless contained_path?(absolute, ROOT)

    [normalized, nil]
  rescue ArgumentError => error
    [nil, "path is invalid: #{error.message}"]
  end

  def contained_path?(path, base)
    path_string = path.expand_path.to_s
    base_string = base.expand_path.to_s
    path_string == base_string || path_string.start_with?("#{base_string}#{File::SEPARATOR}")
  end

  def real_contained_path?(path, base)
    contained_path?(path.realpath, base.realpath)
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  def path_under_runs_prefix?(value)
    normalized, error = normalize_repo_relative(value)
    return false if error

    normalized == "runs" || normalized.start_with?("runs/")
  end

  def dig_value(value, keys)
    keys.reduce(value) do |cursor, key|
      break nil unless cursor.is_a?(Hash)

      cursor[key]
    end
  end

  def stringify_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, child), out| out[key.to_s] = stringify_keys(child) }
    when Array
      value.map { |child| stringify_keys(child) }
    when Date, Time
      value.iso8601
    else
      value
    end
  end

  def pointer_generated_at
    value = @pointer && @pointer["generated_at"]
    value.is_a?(String) ? value : nil
  end

  def scope
    selection = @pointer && @pointer.dig("frontier_binding", "selection")
    selection = {} unless selection.is_a?(Hash)
    {
      "mode" => @full_audit_requested ? "full_audit" : "active_frontier",
      "selected_unit_id" => string_value(selection["id"]),
      "selected_unit_type" => string_value(selection["kind"]),
      "selected_unit_status" => string_value(selection["state"]),
      "section_ids" => section_ids,
      "checked_path_count" => @checked_path_values.length,
      "unrelated_files_scanned" => 0
    }
  end

  def section_ids
    return [] unless @pointer && @ddi

    pointer = @pointer.dig("frontier_binding", "selection", "json_pointer").to_s
    row = resolve_json_pointer(@ddi, pointer)
    values = row.is_a?(Hash) ? Array(row.dig("scope", "section_ids")) : []
    values.select { |value| value.is_a?(String) && value.match?(/\AS\d{2,}[A-Z]?\z/) }.uniq.sort
  end

  def resolve_json_pointer(document, pointer)
    return nil if pointer.to_s.empty?
    pointer.to_s.split("/")[1..].to_a.reduce(document) do |cursor, raw|
      token = raw.gsub("~1", "/").gsub("~0", "~")
      if cursor.is_a?(Array) && token.match?(/\A(?:0|[1-9]\d*)\z/)
        cursor[token.to_i]
      elsif cursor.is_a?(Hash)
        cursor[token]
      end
    end
  end

  def string_value(value)
    value.is_a?(String) ? value : ""
  end

  def display_path(path)
    expanded = Pathname.new(path).expand_path
    return expanded.relative_path_from(ROOT).to_s if contained_path?(expanded, ROOT)

    expanded.to_s
  rescue ArgumentError
    path.to_s
  end

  def command_detail(stdout, stderr)
    [stdout, stderr]
      .flat_map { |text| text.to_s.lines }
      .map(&:strip)
      .reject(&:empty?)
      .join(" | ")
      .slice(0, 800)
      .to_s
  end

  def add_check(id:, kind:, status:, path:, detail:, declared_sha256: nil, actual_sha256: nil)
    @checked << {
      "id" => id,
      "kind" => kind,
      "status" => status,
      "path" => path.to_s,
      "declared_sha256" => declared_sha256,
      "actual_sha256" => actual_sha256,
      "detail" => detail.to_s
    }
  end

  def add_blocker(code, path, message)
    key = [code, path.to_s, message.to_s]
    return if @blocker_keys.include?(key)

    @blocker_keys << key
    @blockers << {
      "id" => format("B%03d", @blockers.length + 1),
      "code" => code,
      "path" => path.to_s,
      "message" => message.to_s
    }
  end

  def elapsed_ms
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round
  end
end

options = {
  pointer: DEFAULT_POINTER,
  full_audit: false,
  json: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/idol_harness_frontier_check.rb [RUN_ROOT] [options]"
  opts.on("--current-next PATH", "Validate a specific current-next pointer") do |value|
    path = Pathname.new(value)
    options[:pointer] = path.absolute? ? path : ROOT.join(path)
  end
  opts.on("--full-audit", "Delegate to the existing broad graph-engineering state audit") do
    options[:full_audit] = true
  end
  opts.on("--json", "Emit the structured frontier report as JSON") do
    options[:json] = true
  end
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

if ARGV.length > 1
  warn "expected at most one RUN_ROOT"
  warn parser
  exit 2
end

report = FrontierCheck.new(
  pointer_path: options[:pointer],
  requested_run: ARGV.first,
  full_audit: options[:full_audit]
).call

if options[:json]
  puts JSON.pretty_generate(report)
else
  puts "IDOL Graph Engineering frontier: #{report["status"]}"
  puts "run: #{report["run"] || "none"}"
  puts "scope: #{report.dig("scope", "mode")}"
  puts "checked: #{report["checked"].length} rows, #{report.dig("scope", "checked_path_count")} selected paths"
  puts "elapsed_ms: #{report["elapsed_ms"]}"
  if report["blockers"].any?
    puts "blockers:"
    report["blockers"].each do |blocker|
      puts "- #{blocker["code"]}: #{blocker["message"]}"
    end
  end
end

exit(report["status"] == "pass" ? 0 : 1)
