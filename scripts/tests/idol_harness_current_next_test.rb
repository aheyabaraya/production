# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "yaml"

class IdolHarnessCurrentNextTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_harness_current_next.rb")
  ACTIVE_SCHEMA = ROOT.join("schemas", "harness-current-next.schema.json")
  LEGACY_SCHEMA = ROOT.join("schemas", "harness-current-next-v1-legacy.schema.json")
  VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = ROOT.join("scripts", "idol-video-python")
  DDI_SCRIPT = ROOT.join("scripts", "idol_director_dispatch_index.rb")

  def setup
    @run = ROOT.join("runs", "harness-test", "current-next", "RUN_#{SecureRandom.hex(4).upcase}")
    @run.join("work").mkpath
    @output_yaml = @run.join("work", "current-next.yaml")
    @output_md = @run.join("work", "current-next.md")
    @ddi_path = @run.join("work", "director-dispatch-index.yaml")
  end

  def teardown
    FileUtils.remove_entry(@run) if @run.directory?
    prune_empty(@run.parent, ROOT.join("runs"))
  end

  def test_deterministic_precedence_uses_stored_ddi_rows_and_exact_hashes
    dispatches = [dispatch_row("DISPATCH_HOLD"), dispatch_row("DISPATCH_REVIEW"), dispatch_row("DISPATCH_ACTION", next_action_ids: ["NEXT_ACTION"])]
    holds = [
      hold_row("HOLD_A_RESOLVED", "resolved", "DISPATCH_HOLD"),
      hold_row("HOLD_B_OPEN", "open", "DISPATCH_HOLD")
    ]
    reviews = [review_row("DISPATCH_REVIEW", blocks_next: true)]
    actions = [action_row("NEXT_ACTION", "ready")]
    write_ddi(dispatches: dispatches, holds: holds, reviews: reviews, actions: actions)

    payload = build
    assert_selection(payload, "open_hold", "HOLD_B_OPEN", "/holds/1", holds.fetch(1))

    write_ddi(dispatches: dispatches, holds: [holds.first], reviews: reviews, actions: actions)
    payload = build
    assert_selection(payload, "review_queue", "DISPATCH_REVIEW", "/review_queue/items/0", reviews.fetch(0))

    reviews.fetch(0)["blocks_next"] = false
    write_ddi(dispatches: dispatches, holds: [holds.first], reviews: reviews, actions: actions)
    payload = build
    assert_selection(payload, "next_action", "NEXT_ACTION", "/next_actions/0", actions.fetch(0))
    assert_equal "DISPATCH_ACTION", payload.dig("frontier_binding", "selection", "dispatch_id")

    actions.fetch(0)["state"] = "deferred"
    write_ddi(dispatches: dispatches, holds: [holds.first], reviews: reviews, actions: actions)
    payload = build
    assert_equal "no_actionable_unit", payload.dig("frontier_binding", "selection", "kind")
    assert_nil payload.dig("frontier_binding", "selection", "id")
    assert_equal "no_actionable_units", payload.fetch("status")

    write_ddi(dispatches: [], holds: [], reviews: [], actions: [], entry_count: 0)
    payload = build
    assert_equal "migration_hold", payload.dig("frontier_binding", "selection", "kind")
    assert_nil payload.dig("frontier_binding", "selection", "json_pointer")
    assert_equal "migration_hold", payload.fetch("status")
  end

  def test_canonical_heads_bind_exact_ddi_rows_and_artifact_bytes
    artifact = @run.join("research", "canonical.yaml")
    artifact.dirname.mkpath
    artifact.write("status: current\n")
    head = current_head("HEAD_CURRENT", "DISPATCH_PROMOTED", artifact)
    write_ddi(
      dispatches: [dispatch_row("DISPATCH_PROMOTED", lifecycle: "promoted")],
      heads: [head],
      entry_count: 1
    )

    payload = build
    heads = payload.dig("frontier_binding", "canonical_heads")
    assert_equal "bound", heads.fetch("resolution")
    item = heads.fetch("items").fetch(0)
    assert_equal "/current_heads/0", item.fetch("json_pointer")
    assert_equal canonical_sha(head), item.fetch("row_sha256")
    assert_equal Digest::SHA256.file(artifact).hexdigest, item.dig("artifact", "sha256")
    validate_active(@output_yaml)
  end

  def test_pending_projection_binds_same_ddi_without_overriding_selection
    dispatch = dispatch_row("DISPATCH_PENDING", next_action_ids: ["NEXT_PENDING"])
    action = action_row("NEXT_PENDING", "ready")
    write_ddi(dispatches: [dispatch], actions: [action], entry_count: 1)
    ddi_binding = binding(@ddi_path, "director_dispatch_index_v4")
    board = @run.join("review", "manifests", "founder-workbench.yaml")
    source_set = @run.join("work", "review-projection-source-set.yaml")
    pending = @run.join("work", "review-projection-pending.yaml")
    board.dirname.mkpath
    digest = {"algorithm" => "sha256", "basis" => "canonical_projection_query_and_owner_bindings_v1", "sha256" => "7" * 64, "entry_count" => 1}
    board.write(YAML.dump("run" => {"run_root" => relative(@run)}, "board" => {"revision" => 2, "active_cycle_id" => "CYCLE_2", "source_set_digest" => digest}))
    source_set.write(YAML.dump(
      "schema_version" => "idol-review-projection-source-set.v2",
      "run" => relative(@run),
      "director_dispatch_index" => ddi_binding,
      "source_set_digest" => digest,
      "outputs" => {"pending_path" => relative(pending), "manifest_path" => relative(board)}
    ))
    pending.write(YAML.dump(
      "schema_version" => "idol-review-projection-pending.v1",
      "run" => relative(@run),
      "status" => "pending",
      "source_set" => binding(source_set, "review_projection_source_set"),
      "board_manifest" => binding(board, "stable_founder_workbench_manifest"),
      "board_revision" => 2,
      "active_cycle_id" => "CYCLE_2",
      "summary" => {"unresolved_count" => 1},
      "items" => [{
        "asset_id" => "ASSET_PENDING",
        "binding_id" => "BINDING_PENDING",
        "source_stage" => "front_planning",
        "dispatch_id" => "DISPATCH_PENDING",
        "director_dispatch_index" => ddi_binding
      }],
      "next_action" => "route_unassigned_items_through_existing_director_dispatch_then_reassemble_same_stable_board",
      "automation_boundaries" => {"current_next_selection_overridden" => false}
    ))

    payload = build
    assert_equal "next_action", payload.dig("frontier_binding", "selection", "kind")
    assert_equal "NEXT_PENDING", payload.dig("frontier_binding", "selection", "id")
    assert_equal false, payload.dig("review_projection_pending", "selection_overridden")
    assert_equal ddi_binding, payload.dig("review_projection_pending", "director_dispatch_index")
    assert_includes @output_md.read, "Review Projection Pending"

    drifted = YAML.safe_load(pending.read, aliases: false)
    drifted.dig("items", 0, "director_dispatch_index")["sha256"] = "0" * 64
    pending.write(YAML.dump(drifted))
    result = run_script(relative(@run), "--output-yaml", relative(@output_yaml), "--output-md", relative(@output_md), "--write")
    refute result[:status].success?
    assert_includes result[:stderr], "pending item 1 DDI"
  end

  def test_render_mode_keeps_v1_as_frozen_evidence_and_detects_stale_readout
    source = @run.join("work", "legacy-current-next.yaml")
    source.write(ROOT.join("automation", "current-next.yaml").read)
    validate_document(LEGACY_SCHEMA, source)
    original = source.binread
    result = run_script("--render-from-yaml", relative(source), "--output-md", relative(@output_md), "--write")
    assert result[:status].success?, result[:stderr]
    assert_equal original, source.binread
    assert_includes @output_md.read, "Legacy v1 Evidence"

    checked = run_script("--render-from-yaml", relative(source), "--output-md", relative(@output_md), "--check-readout")
    assert checked[:status].success?, checked[:stderr]
    @output_md.open("ab") { |file| file.write("\nstale\n") }
    stale = run_script("--render-from-yaml", relative(source), "--output-md", relative(@output_md), "--check-readout")
    refute stale[:status].success?
    assert_includes stale[:stderr], "derived current-next Markdown is stale"
  end

  def test_real_ddi_v4_build_and_validate_feed_migration_hold_projection
    @ddi_path.delete if @ddi_path.exist?
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      DDI_SCRIPT.to_s,
      "build",
      relative(@run),
      "--json",
      "--skip-reference-validation",
      chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      DDI_SCRIPT.to_s,
      "validate",
      relative(@ddi_path),
      "--json",
      "--skip-reference-validation",
      chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")

    payload = build
    assert_equal "migration_hold", payload.dig("frontier_binding", "selection", "kind")
    assert_equal Digest::SHA256.file(@ddi_path).hexdigest, payload.dig("frontier_binding", "director_dispatch_index", "sha256")
  end

  private

  def build
    result = run_script(
      relative(@run),
      "--output-yaml", relative(@output_yaml),
      "--output-md", relative(@output_md),
      "--write"
    )
    assert result[:status].success?, result[:stderr]
    validate_active(@output_yaml)
    YAML.safe_load(@output_yaml.read, aliases: false)
  end

  def write_ddi(dispatches: [], holds: [], reviews: [], actions: [], heads: [], entry_count: nil)
    source_set_sha = "1" * 64
    document = {
      "schema_version" => "idol-director-dispatch-index.v4",
      "run" => relative(@run),
      "source_set_sha256" => source_set_sha,
      "source_set_digest" => {"sha256" => source_set_sha},
      "dispatch_source_set" => {"entry_count" => entry_count.nil? ? dispatches.length : entry_count},
      "dispatches" => dispatches,
      "review_queue" => {
        "selection_order" => "dependency_rank_then_returned_at_then_dispatch_id",
        "items" => reviews
      },
      "current_heads" => heads,
      "holds" => holds,
      "next_actions" => actions
    }
    @ddi_path.write(YAML.dump(document))
  end

  def dispatch_row(id, lifecycle: "launched", next_action_ids: [])
    {"dispatch_id" => id, "lifecycle" => {"current_state" => lifecycle}, "next_action_ids" => next_action_ids}
  end

  def hold_row(id, state, dispatch_id)
    {"hold_id" => id, "dispatch_id" => dispatch_id, "owner" => "overall_director", "state" => state}
  end

  def review_row(dispatch_id, blocks_next:)
    {
      "dispatch_id" => dispatch_id,
      "director_owner" => "creative_development_director",
      "dependency_rank" => 0,
      "returned_at" => "2026-08-14T00:00:00Z",
      "queue_state" => blocks_next ? "queued" : "released",
      "blocks_next" => blocks_next
    }
  end

  def action_row(id, state)
    {"next_action_id" => id, "owner" => "creative_development_director", "state" => state}
  end

  def current_head(head_id, dispatch_id, artifact)
    {
      "head_id" => head_id,
      "logical_artifact_id" => "ARTIFACT_#{head_id}",
      "stage_id" => "front_planning_integration",
      "artifact" => binding(artifact, "canonical_artifact"),
      "source_dispatch_id" => dispatch_id,
      "supersession_state" => "none",
      "state" => "current"
    }
  end

  def assert_selection(payload, kind, id, pointer, source_row)
    selection = payload.dig("frontier_binding", "selection")
    assert_equal kind, selection.fetch("kind")
    assert_equal id, selection.fetch("id")
    assert_equal pointer, selection.fetch("json_pointer")
    assert_equal canonical_sha(source_row), selection.fetch("row_sha256")
  end

  def canonical_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def canonical(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def binding(path, role)
    {"path" => relative(path), "sha256" => Digest::SHA256.file(path).hexdigest, "role" => role}
  end

  def validate_active(path)
    validate_document(ACTIVE_SCHEMA, path)
  end

  def validate_document(schema, path)
    _stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, schema.to_s, path.to_s, chdir: ROOT.to_s)
    assert status.success?, stderr
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def run_script(*arguments)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, *arguments, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def prune_empty(path, stop)
    current = path
    while current.to_s.start_with?(stop.to_s) && current != stop && current.directory? && current.children.empty?
      current.rmdir
      current = current.parent
    end
  end
end
