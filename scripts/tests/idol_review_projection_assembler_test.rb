# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_review_board_fixture"

class IdolReviewProjectionAssemblerTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_review_projection_assembler.rb")
  DIRECT_UPDATE = ROOT.join("scripts", "idol_founder_direct_update_commit.rb")
  BOARD = ROOT.join("scripts", "idol_html_review_board.rb")

  def setup
    @fixture = ActiveReviewBoardFixture.create
    @run = @fixture.mv.run_dir
    @manifest_path = @run.join("review", "manifests", "founder-workbench.yaml")
    @source_set_path = @run.join("work", "review-projection-source-set.yaml")
    @pending_path = @run.join("work", "review-projection-pending.yaml")
    @owners = {}
    prepare_base_manifest
    prepare_owner_feeds
    write_source_set
    write_owner_index
  end

  def teardown
    @fixture.cleanup
  end

  def test_dummy_owner_feeds_assemble_one_stable_pointer_only_board
    result = run_assembler

    assert result[:status].success?, result[:stderr]
    report = JSON.parse(result[:stdout])
    assert_equal "written", report.fetch("status")
    assert_equal 8, report.dig("summary", "source_count")
    assert_equal 1, report.dig("summary", "unresolved_count")

    manifest = load_yaml(@manifest_path)
    assert_equal 2, manifest.dig("board", "revision")
    assert_equal @source_set.fetch("source_set_digest"), manifest.dig("board", "source_set_digest")
    assert_equal %w[fp_close planning_02a], manifest.dig("board", "review_sequence").map { |row| row.fetch("phase") }
    assert_equal %w[active active], manifest.dig("sections", 0, "cards").last(2).map { |card| card.fetch("phase_state") }
    edit_asset = manifest.fetch("review_assets").find { |asset| asset.fetch("asset_id") == "MEDIA-EDIT-OUTPUT" }
    assert_equal "edit_output", edit_asset.fetch("role")
    assert_equal "edit_output", edit_asset.dig("bindings", 0, "lane_role")
    assert_equal "04", edit_asset.dig("bindings", 0, "source_stage")

    inbox = manifest.fetch("review_assets").find { |asset| asset.fetch("asset_id") == "MEDIA-NEW-REFERENCE" }
    assert_equal true, inbox.dig("bindings", 0, "new_since_last_review")
    assert_equal "unassigned", inbox.dig("bindings", 0, "assignment_state")
    pending = load_yaml(@pending_path)
    assert_equal "pending", pending.fetch("status")
    assert_equal "DISPATCH-CLASSIFY-NEW-REFERENCE", pending.dig("items", 0, "dispatch_id")
    assert_equal Digest::SHA256.file(@manifest_path).hexdigest, pending.dig("board_manifest", "sha256")

    board = run_command(RbConfig.ruby, BOARD, "validate", @manifest_path, "--json")
    assert board[:status].success?, board[:stderr]
    html = @run.join("review", "founder-workbench.html").read
    assert_includes html, "MEDIA-NEW-REFERENCE"
    assert_includes html, "MEDIA-EDIT-OUTPUT"
    assert_includes html, "NEW SINCE LAST REVIEW"
    freshness = run_command(RbConfig.ruby, SCRIPT, @source_set_path, "--check-current", "--json")
    assert freshness[:status].success?, freshness[:stderr]
    assert_equal "fresh", JSON.parse(freshness[:stdout]).fetch("status")
  end

  def test_every_active_binding_must_be_covered_by_an_owner_feed
    stage_02b = @owners.fetch("stage_02b")
    document = load_yaml(stage_02b)
    document["items"] = []
    write_yaml(stage_02b, document)
    refresh_source_binding!("stage_02b")
    rewrite_source_set

    result = run_assembler

    refute result[:status].success?
    assert_includes result[:stderr], "active board bindings were omitted"
    assert_equal 1, load_yaml(@manifest_path).dig("board", "revision")
  end

  def test_stale_owner_hash_aborts_without_replacing_the_board
    original = @manifest_path.binread
    @owners.fetch("generated_branch_review").open("ab") { |file| file.write("\nchanged after source lock\n") }

    result = run_assembler

    refute result[:status].success?
    assert_includes result[:stderr], "SHA-256 is stale"
    assert_equal original, @manifest_path.binread
    refute @pending_path.exist?
  end

  def test_open_board_freshness_check_holds_when_an_owner_changes
    assembled = run_assembler
    assert assembled[:status].success?, assembled[:stderr]
    @owners.fetch("stage_03v").open("ab") { |file| file.write("\nexternal owner drift\n") }

    checked = run_command(RbConfig.ruby, SCRIPT, @source_set_path, "--check-current", "--json")

    refute checked[:status].success?
    assert_includes checked[:stderr], "SHA-256 is stale"
  end

  def test_internal_fp_close_and_02a_final_planning_readiness_come_from_owner_bytes
    fp_path = @ordered_paths.fetch(:fp)
    fp = load_yaml(fp_path)
    fp["status"] = "hold"
    write_yaml(fp_path, fp)
    refresh_ordered_binding!(:fp)
    rewrite_source_set

    result = run_assembler

    assert result[:status].success?, result[:stderr]
    manifest = load_yaml(@manifest_path)
    assert_equal %w[provisional provisional], manifest.dig("sections", 0, "cards").last(2).map { |card| card.fetch("phase_state") }
  end

  def test_only_changed_owner_binding_receives_the_next_projection_revision
    first = run_assembler
    assert first[:status].success?, first[:stderr]
    before = load_yaml(@manifest_path)
    unchanged_before = binding_by_id(before, "BIND-MEDIA-WHOLE")
    generated_before = binding_by_id(before, "BIND-GENERATED-OUTPUT")

    generated_path = @owners.fetch("generated_branch_review")
    generated = load_yaml(generated_path)
    generated.dig("items", 0, "binding")["disposition"] = "passed_output"
    generated.dig("items", 0, "binding")["review_state"] = "reviewed_pass"
    write_yaml(generated_path, generated)
    refresh_source_binding!("generated_branch_review")
    @source_set["base_manifest"]["sha256"] = Digest::SHA256.file(@manifest_path).hexdigest
    @source_set["projection_revision"] = 3
    rewrite_source_set

    second = run_assembler

    assert second[:status].success?, second[:stderr]
    after = load_yaml(@manifest_path)
    assert_equal unchanged_before.fetch("latest_binding_revision"), binding_by_id(after, "BIND-MEDIA-WHOLE").fetch("latest_binding_revision")
    assert_equal generated_before.fetch("latest_binding_revision") + 1, binding_by_id(after, "BIND-GENERATED-OUTPUT").fetch("latest_binding_revision")
    assert_equal "passed_output", binding_by_id(after, "BIND-GENERATED-OUTPUT").fetch("disposition")
  end

  def test_stale_manifest_compare_and_swap_aborts
    @manifest_path.open("ab") { |file| file.write("\n# external change\n") }

    result = run_assembler

    refute result[:status].success?
    assert_includes result[:stderr], "base_manifest SHA-256 is stale"
    refute @pending_path.exist?
  end

  def test_projection_change_requires_a_new_board_revision
    reference_owner = @owners.fetch("reference_working_index")
    reference_document = load_yaml(reference_owner)
    reference_document["items"] = []
    write_yaml(reference_owner, reference_document)
    refresh_source_binding!("reference_working_index")
    @source_set["projection_revision"] = 1
    rewrite_source_set

    result = run_assembler

    refute result[:status].success?
    assert_includes result[:stderr], "projection bytes changed without advancing the board revision"
    assert_equal 1, load_yaml(@manifest_path).dig("board", "revision")
  end

  def test_idempotent_projection_may_keep_the_current_revision
    first = run_assembler
    assert first[:status].success?, first[:stderr]
    first_bytes = @manifest_path.binread
    @source_set["base_manifest"] = artifact_binding(@manifest_path, "stable_board_compare_and_swap_base")
    @source_set["projection_revision"] = 2
    rewrite_source_set

    second = run_assembler

    assert second[:status].success?, second[:stderr]
    assert_equal first_bytes, @manifest_path.binread
    assert_equal 2, load_yaml(@manifest_path).dig("board", "revision")
  end

  def test_pointer_plan_change_invalidates_the_open_board_even_when_owner_bytes_do_not_change
    first = run_assembler
    assert first[:status].success?, first[:stderr]
    @source_set.fetch("sources").first.fetch("asset_fields")["label"] = "/asset/alt"
    rewrite_source_set

    checked = run_command(RbConfig.ruby, SCRIPT, @source_set_path, "--check-current", "--json")

    refute checked[:status].success?
    assert_includes checked[:stderr], "stable board source-set digest differs"
  end

  def test_owner_index_prepares_missing_source_set_and_syncs_matching_current_next
    current_next_yaml = @run.join("work", "dummy-current-next.yaml")
    current_next_md = @run.join("work", "dummy-current-next.md")
    current_next = dummy_current_next
    selection_before = Marshal.load(Marshal.dump(current_next.dig("frontier_binding", "selection")))
    write_yaml(current_next_yaml, current_next)
    @source_set_path.delete

    result = run_command(
      RbConfig.ruby,
      SCRIPT,
      @source_set_path,
      "--prepare-from", @owner_index_path,
      "--current-next-yaml", current_next_yaml,
      "--current-next-md", current_next_md,
      "--write",
      "--json"
    )

    assert result[:status].success?, result[:stderr]
    report = JSON.parse(result[:stdout])
    assert_equal true, report.fetch("source_set_prepared")
    assert_equal "updated", report.dig("current_next", "status")
    assert @source_set_path.file?
    refreshed = load_yaml(current_next_yaml)
    assert_equal selection_before, refreshed.dig("frontier_binding", "selection")
    assert_equal @source_set.fetch("director_dispatch_index"), refreshed.dig("review_projection_pending", "director_dispatch_index")
    assert_equal false, refreshed.dig("review_projection_pending", "selection_overridden")
    assert_equal "pending", refreshed.dig("review_projection_pending", "status")
    assert_equal 1, refreshed.dig("review_projection_pending", "unresolved_count")
    assert_includes current_next_md.read, "Review Projection Pending"
  end

  def test_dummy_founder_direct_update_commits_receipt_owner_and_same_stable_board
    assembled = run_assembler
    assert assembled[:status].success?, assembled[:stderr]
    payload, paths = prepare_direct_update_payload

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      DIRECT_UPDATE.to_s,
      stdin_data: JSON.generate(payload),
      chdir: ROOT.to_s
    )

    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal "integrated", result.fetch("status")
    assert_equal relative(@run.join("review", "founder-workbench.html")), result.dig("board", "htmlPath")
    assert Pathname.new(ROOT.join(result.dig("receipt", "path"))).file?
    assert_equal result.dig("receipt", "sha256"), Digest::SHA256.file(ROOT.join(result.dig("receipt", "path"))).hexdigest

    plan = paths.fetch(:plan).read
    canvas = JSON.parse(paths.fetch(:canvas).read)
    assert_includes plan, "Put the consequence before the member reaction."
    assert_equal 1, canvas.fetch("founder_epoch")
    assert_equal %w[ASSET-DIRECT-B ASSET-DIRECT-A], canvas.fetch("sequence").map { |row| row.fetch("asset_id") }
    assert_equal false, canvas.dig("pending_reconciliation", "dirty")
    assert_equal "pending", load_yaml(paths.fetch(:current_next_yaml)).dig("review_projection_pending", "status")
    assert_includes paths.fetch(:current_next_md).read, "Review Projection Pending"

    fresh = run_command(
      RbConfig.ruby,
      SCRIPT,
      @source_set_path,
      "--prepare-from", @owner_index_path,
      "--check-current",
      "--json"
    )
    assert fresh[:status].success?, fresh[:stderr]
  end

  def test_dummy_founder_direct_update_rolls_back_every_write_when_owner_projection_is_stale
    assembled = run_assembler
    assert assembled[:status].success?, assembled[:stderr]
    payload, paths = prepare_direct_update_payload
    tracked = [
      paths.fetch(:plan), paths.fetch(:canvas), @manifest_path,
      @run.join("review", "founder-workbench.html"), @source_set_path, @pending_path,
      paths.fetch(:current_next_yaml), paths.fetch(:current_next_md)
    ]
    before = tracked.to_h { |path| [path, path.exist? ? path.binread : nil] }
    @owners.fetch("stage_03v").open("ab") { |file| file.write("\nstale owner after direct-update authorization\n") }

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      DIRECT_UPDATE.to_s,
      stdin_data: JSON.generate(payload),
      chdir: ROOT.to_s
    )

    refute status.success?, stdout
    assert_includes stderr, "stable board reprojection failed"
    before.each do |path, bytes|
      assert_equal bytes, path.exist? ? path.binread : nil, "expected rollback for #{relative(path)}"
    end
    refute @run.join("review", "founder-interventions").glob("FI_FPW_*.yaml").any?
  end

  private

  def prepare_base_manifest
    manifest = Marshal.load(Marshal.dump(@fixture.manifest))
    board = manifest.fetch("board")
    board["revision"] = 1
    board["projection_revision"] = 1
    board["last_reviewed_revision"] = 1
    board["review_sequence"] = [
      {"phase" => "fp_close", "order" => 1, "stage_id" => "front_planning_close", "gate" => "read_only_fp_close_lineage"},
      {"phase" => "planning_02a", "order" => 2, "stage_id" => "storyboard_02a", "gate" => "active_02a_final_planning"}
    ]
    cards = manifest.dig("sections", 0, "cards")
    cards.first(2).each { |card| card.merge!("review_phase" => "fp_close", "phase_state" => "read_only") }
    cards.last(2).each { |card| card.merge!("review_phase" => "planning_02a", "phase_state" => "provisional") }
    manifest.fetch("review_assets").each do |asset|
      asset.fetch("bindings").each do |binding|
        binding["latest_binding_revision"] = 1
        binding["new_since_last_review"] = false
      end
    end
    @manifest_path.dirname.mkpath
    write_yaml(@manifest_path, manifest)
    @base_manifest = manifest
  end

  def prepare_direct_update_payload
    plan_path = @run.join("research", "front-planning-v1.md")
    canvas_path = @run.join("work", "front_planning_integration", "canvas-state.json")
    current_next_yaml = @run.join("work", "dummy-current-next.yaml")
    current_next_md = @run.join("work", "dummy-current-next.md")
    asset_rows = %w[A B].map.with_index do |suffix, index|
      path = @run.join("research", "direct-update", "#{suffix.downcase}.png")
      path.dirname.mkpath
      path.write("dummy direct-update asset #{suffix}\n")
      {
        "id" => "ASSET-DIRECT-#{suffix}",
        "kind" => "reference_frame",
        "path" => relative(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "media_type" => "image/png",
        "status" => "selected",
        "section_ids" => ["S01"],
        "function_label" => "Dummy direct-update screen #{suffix}",
        "source" => {
          "title" => "Dummy official source #{suffix}",
          "uri_or_path" => relative(path),
          "followed_function" => "Exercise deterministic sequence routing.",
          "timestamp" => nil
        },
        "generation" => {"provider" => "none", "parent_asset_ids" => []},
        "intrinsic" => {"width" => 1920, "height" => 1080},
        "fixture_index" => index
      }
    end
    canvas_assets = asset_rows.map { |row| row.reject { |key, _value| key == "fixture_index" } }
    baseline_sequence = canvas_assets.map.with_index do |asset, index|
      {
        "id" => "SEQ-DIRECT-#{index + 1}",
        "asset_id" => asset.fetch("id"),
        "section_id" => "S01",
        "order" => index,
        "timeline" => "00:0#{index}",
        "purpose" => "Dummy baseline order"
      }
    end
    baseline_canvas = {
      "schema_version" => "front-planning-workbench.canvas-state.v5",
      "run" => {"run_root" => relative(@run), "content_id" => "ACTIVE_TITLE_TEST"},
      "founder_epoch" => 0,
      "revision" => {"number" => 1, "updated_at" => "2026-08-05T00:00:00Z", "content_digest" => ""},
      "sections" => [{
        "id" => "S01", "label" => "S01", "order" => 0, "status" => "draft",
        "time_range" => {"start" => "00:00", "end" => "00:10"}
      }],
      "assets" => canvas_assets,
      "nodes" => canvas_assets.map.with_index do |asset, index|
        {
          "id" => "NODE-DIRECT-#{index + 1}", "asset_id" => asset.fetch("id"),
          "section_id" => "S01", "x" => index * 400, "y" => 0,
          "display_class" => "landscape", "label" => asset.fetch("function_label"), "locked" => false
        }
      end,
      "edges" => [],
      "sequence" => baseline_sequence,
      "session_links" => [],
      "pending_reconciliation" => {"dirty" => true, "events" => [{
        "id" => "EVENT-DIRECT-BASE", "kind" => "sequence", "occurred_at" => "2026-08-05T00:00:00Z",
        "summary" => "Founder reordered the dummy rail.", "founder_authored" => true
      }]}
    }
    candidate_canvas = Marshal.load(Marshal.dump(baseline_canvas))
    candidate_canvas["founder_epoch"] = 1
    candidate_canvas["revision"] = {
      "number" => 2, "updated_at" => "2026-08-05T00:01:00Z", "content_digest" => ""
    }
    candidate_canvas["sequence"] = baseline_sequence.reverse.each_with_index.map do |row, index|
      row.merge("order" => index, "id" => "SEQ-DIRECT-#{index + 1}")
    end
    candidate_canvas["pending_reconciliation"] = {"dirty" => false, "events" => []}

    plan_path.dirname.mkpath
    plan_path.write("# Dummy Front Planning\n\n## Live planning decisions\n\n- Baseline dummy direction.\n")
    canvas_path.dirname.mkpath
    canvas_path.write(JSON.pretty_generate(baseline_canvas) + "\n")
    write_yaml(current_next_yaml, dummy_current_next)
    current_next_md.write("dummy pre-update readout\n")

    manifest = load_yaml(@manifest_path)
    instruction = "Put the consequence before the member reaction."
    plan_text = plan_path.read + "- **Founder decision draft (Founder direct update):** #{instruction}\n"
    ordered = candidate_canvas.fetch("sequence").map.with_index do |row, index|
      asset = canvas_assets.find { |candidate| candidate.fetch("id") == row.fetch("asset_id") }
      {
        "order" => index + 1,
        "nodeId" => "NODE-DIRECT-#{row.fetch('asset_id').end_with?('A') ? 1 : 2}",
        "assetId" => row.fetch("asset_id"),
        "sectionId" => row.fetch("section_id"),
        "path" => asset.fetch("path"),
        "sha256" => asset.fetch("sha256"),
        "label" => asset.fetch("function_label")
      }
    end
    payload = {
      "version" => 1,
      "runRoot" => relative(@run),
      "planText" => plan_text,
      "canvasValue" => candidate_canvas,
      "basePlanSha256" => Digest::SHA256.file(plan_path).hexdigest,
      "baseCanvasSha256" => Digest::SHA256.file(canvas_path).hexdigest,
      "request" => {
        "version" => 1,
        "runRoot" => relative(@run),
        "correctionKind" => "sequence_reorder_and_instruction",
        "owningTruthSurface" => "front_planning_sequence",
        "founderInstructionVerbatim" => instruction,
        "orderedSequence" => ordered,
        "affectedSectionIds" => ["S01"],
        "baseline" => {
          "plan" => {"path" => relative(plan_path), "sha256" => Digest::SHA256.file(plan_path).hexdigest},
          "canvas" => {"path" => relative(canvas_path), "sha256" => Digest::SHA256.file(canvas_path).hexdigest},
          "board" => {
            "htmlPath" => relative(@run.join("review", "founder-workbench.html")),
            "htmlSha256" => Digest::SHA256.file(@run.join("review", "founder-workbench.html")).hexdigest,
            "manifestPath" => relative(@manifest_path),
            "manifestSha256" => Digest::SHA256.file(@manifest_path).hexdigest,
            "revision" => manifest.dig("board", "revision"),
            "activeCycleId" => manifest.dig("board", "active_cycle_id")
          },
          "founderEpoch" => 0
        },
        "requiredRoute" => ["workbench_atomic_commit"],
        "forbidden" => ["paid_or_external_generation"]
      },
      "checks" => %w[
        schema_and_hash_integrity
        reference_and_identity_integrity
        safety_and_feasibility
        pixel_or_playback_qa_when_output_exists
        external_and_paid_approval_when_applicable
      ].map { |check_id| {"checkId" => check_id, "status" => "pass", "evidence" => "Dummy local check passed for #{check_id}."} },
      "currentNext" => {"yaml" => relative(current_next_yaml), "markdown" => relative(current_next_md)}
    }
    [payload, {plan: plan_path, canvas: canvas_path, current_next_yaml: current_next_yaml, current_next_md: current_next_md}]
  end

  def dummy_current_next
    action = @dispatch_document.fetch("next_actions").fetch(0)
    {
      "schema_version" => "harness-current-next.v2",
      "artifact_type" => "harness_current_next",
      "generated_at" => "2026-08-05T00:00:00Z",
      "run" => relative(@run),
      "album_key" => @run.parent.parent.basename.to_s,
      "title_key" => @run.parent.basename.to_s,
      "status" => "ready",
      "owner" => "creative_development_director",
      "frontier_binding" => {
        "director_dispatch_index" => artifact_binding(@dispatch_path, "director_dispatch_index_v4"),
        "source_set_sha256" => @dispatch_document.fetch("source_set_sha256"),
        "selection" => {
          "kind" => "next_action",
          "id" => action.fetch("next_action_id"),
          "dispatch_id" => "DISPATCH-CLASSIFY-NEW-REFERENCE",
          "json_pointer" => "/next_actions/0",
          "row_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(action))),
          "state" => action.fetch("state")
        },
        "canonical_heads" => {"resolution" => "not_yet_promoted", "items" => []}
      },
      "legacy_evidence" => {
        "selection_authority" => false,
        "source_next_unit" => nil,
        "source_founder_gate" => nil,
        "source_action_queue" => nil
      },
      "automation_boundaries" => ["Dummy local-only current-next projection."],
      "forbidden_actions" => ["paid_generation"],
      "refresh_commands" => []
    }
  end

  def prepare_owner_feeds
    dispatch_path = @run.join("work", "director-dispatch-index.yaml")
    source_set_sha = "1" * 64
    @dispatch_document = {
      "schema_version" => "idol-director-dispatch-index.v4",
      "run" => relative(@run),
      "source_set_sha256" => source_set_sha,
      "source_set_digest" => {"sha256" => source_set_sha},
      "dispatch_source_set" => {"entry_count" => 1},
      "dispatches" => [{
        "dispatch_id" => "DISPATCH-CLASSIFY-NEW-REFERENCE",
        "lifecycle" => {"current_state" => "launched"},
        "next_action_ids" => ["NEXT-CLASSIFY-NEW-REFERENCE"]
      }],
      "review_queue" => {
        "selection_order" => "dependency_rank_then_returned_at_then_dispatch_id",
        "items" => []
      },
      "current_heads" => [],
      "holds" => [],
      "next_actions" => [{
        "next_action_id" => "NEXT-CLASSIFY-NEW-REFERENCE",
        "owner" => "creative_development_director",
        "state" => "ready"
      }]
    }
    write_yaml(
      dispatch_path,
      @dispatch_document
    )
    @dispatch_path = dispatch_path

    base_asset = @base_manifest.fetch("review_assets").first
    base_bindings = base_asset.fetch("bindings")
    adapter_rows = {
      "current_title_member_visual" => row_from(base_asset, base_bindings.fetch(0)),
      "stage_01" => row_from(base_asset, base_bindings.fetch(1)),
      "stage_02a" => row_from(base_asset, base_bindings.fetch(2)),
      "stage_02b" => row_from(base_asset, base_bindings.fetch(3)),
      "reference_working_index" => new_reference_row,
      "generated_branch_review" => output_row(
        "MEDIA-GENERATED-OUTPUT", "BIND-GENERATED-OUTPUT", "generated.png",
        "generated_branch_cut", "generated_branch_cut", "generated_output", "TARGET-BC01", "branch_cut"
      ),
      "stage_03v" => output_row(
        "MEDIA-03V-PLAYBACK", "BIND-03V-PLAYBACK", "playback.mp4",
        "playback", "playback", "playback_output", "TARGET-S01", "03v", media_kind: "video"
      ),
      "stage_04" => output_row(
        "MEDIA-EDIT-OUTPUT", "BIND-EDIT-OUTPUT", "edit-review.mp4",
        "edit_output", "edit_output", "edit_output", "TARGET-WHOLE", "edit", media_kind: "video"
      )
    }
    adapter_rows.each do |adapter, row|
      path = @run.join("work", "review-owner-feeds", "#{adapter}.yaml")
      write_yaml(path, {"schema_version" => "dummy-#{adapter}.v1", "items" => [row]})
      @owners[adapter] = path
    end

    fp_path = @run.join("work", "review-owner-feeds", "fp-close-source.yaml")
    exact_path = @run.join("work", "review-owner-feeds", "planning-02a-source.yaml")
    write_yaml(fp_path, {"schema_version" => "dummy-fp-close.v1", "status" => "director_closed"})
    write_yaml(
      exact_path,
      {
        "schema_version" => "dummy-planning-02a.v1",
        "rows" => @base_manifest.dig("sections", 0, "cards").last(2).map do |card|
          {"target_id" => card.dig("review_target", "target_id"), "eligible" => true}
        end
      }
    )
    @ordered_paths = {fp: fp_path, exact: exact_path}
  end

  def write_source_set
    @source_set = {
      "schema_version" => "idol-review-projection-source-set.v2",
      "artifact_type" => "review_projection_source_set",
      "status" => "prepared",
      "run" => relative(@run),
      "base_manifest" => artifact_binding(@manifest_path, "stable_board_compare_and_swap_base"),
      "projection_revision" => 2,
      "source_set_digest" => {},
      "director_dispatch_index" => artifact_binding(@dispatch_path, "director_dispatch_index_v4"),
      "ordered_review" => {
        "fp_close_source" => {
          "owner_artifact" => artifact_binding(@ordered_paths.fetch(:fp), "fp_close_owner"),
          "status_pointer" => "/status",
          "closed_values" => ["director_closed"]
        },
        "planning_02a_source" => {
          "owner_artifact" => artifact_binding(@ordered_paths.fetch(:exact), "planning_02a_owner"),
          "rows_pointer" => "/rows",
          "target_id_pointer" => "/target_id",
          "status_pointer" => "/eligible",
          "ready_values" => [true]
        }
      },
      "sources" => @owners.map do |adapter, path|
        source_adapter(adapter, path)
      end,
      "outputs" => {
        "manifest_path" => relative(@manifest_path),
        "html_path" => relative(@run.join("review", "founder-workbench.html")),
        "pending_path" => relative(@pending_path)
      },
      "authority_boundary" => {
        "pointer_only" => true,
        "exact_copy_only" => true,
        "media_copy_allowed" => false,
        "creative_authority" => false,
        "stage_write_allowed" => false,
        "approval_inference_allowed" => false,
        "new_state_is_revision_derived" => true,
        "compare_and_swap_required" => true,
        "atomic_write_required" => true
      }
    }
    rewrite_source_set
  end

  def write_owner_index
    @owner_index_path = @run.join("work", "review-projection-owner-index.yaml")
    write_yaml(
      @owner_index_path,
      {
        "schema_version" => "idol-review-projection-owner-index.v1",
        "artifact_type" => "review_projection_owner_index",
        "status" => "prepared",
        "run" => relative(@run),
        "director_dispatch_index" => Marshal.load(Marshal.dump(@source_set.fetch("director_dispatch_index"))),
        "ordered_review" => Marshal.load(Marshal.dump(@source_set.fetch("ordered_review"))),
        "declared_adapter_kinds" => @source_set.fetch("sources").map { |source| source.fetch("adapter_kind") }.uniq,
        "sources" => Marshal.load(Marshal.dump(@source_set.fetch("sources"))),
        "authority_boundary" => {
          "owner_registration_only" => true,
          "exact_copy_only" => true,
          "creative_authority" => false,
          "stage_write_allowed" => false,
          "approval_inference_allowed" => false,
          "missing_declared_owner_behavior" => "hold"
        }
      }
    )
  end

  def source_adapter(adapter, path)
    stages = {
      "reference_working_index" => "front_planning",
      "current_title_member_visual" => "front_planning",
      "stage_01" => "01",
      "stage_02a" => "02A",
      "stage_02b" => "02B",
      "generated_branch_review" => "generated_branch_review",
      "stage_03v" => "03V",
      "stage_04" => "04"
    }
    reference = adapter == "reference_working_index"
    {
      "source_id" => "SOURCE-#{adapter.upcase.tr('_', '-')}",
      "adapter_kind" => adapter,
      "source_stage" => stages.fetch(adapter),
      "owner_artifact" => artifact_binding(path, "#{adapter}_owner"),
      "expected_schema_version" => "dummy-#{adapter}.v1",
      "inventory_pointer" => "/items",
      "projection_state_pointer" => "/projection_state",
      "project_values" => ["project"],
      "excluded_values" => ["excluded"],
      "exclusion_reason_pointer" => "/exclusion_reason",
      "asset_fields" => {
        "asset_id" => "/asset/asset_id",
        "surface_locator" => "/asset/surface_locator",
        "canonical_path" => "/asset/canonical_path",
        "sha256" => "/asset/sha256",
        "alt" => "/asset/alt",
        "label" => "/asset/label",
        "note" => nil,
        "media_kind" => "/asset/media_kind",
        "original_owner" => "/asset/original_owner",
        "role" => "/asset/role",
        "inspection_action" => "/asset/inspection_action",
        "display_lane" => "/asset/display_lane",
        "receipt" => reference ? "/asset/receipt" : nil,
        "supersedes_asset_id" => nil,
        "superseded_by_asset_id" => nil
      },
      "binding_fields" => {
        "binding_id" => "/binding/binding_id",
        "assignment_state" => "/binding/assignment_state",
        "target_id" => "/binding/target_id",
        "target_level" => "/binding/target_level",
        "section_id" => nil,
        "core_cut_id" => nil,
        "branch_cut_id" => nil,
        "declared_order" => "/binding/declared_order",
        "lane_role" => "/binding/lane_role",
        "disposition" => "/binding/disposition",
        "review_state" => "/binding/review_state",
        "state_receipt" => "/binding/state_receipt",
        "routing_dispatch_id" => reference ? "/binding/routing_dispatch_id" : nil
      }
    }
  end

  def row_from(asset, binding)
    asset_copy = Marshal.load(Marshal.dump(asset))
    binding_copy = Marshal.load(Marshal.dump(binding))
    asset_copy.delete("first_seen_board_revision")
    asset_copy.delete("bindings")
    binding_copy.delete("new_since_last_review")
    binding_copy.delete("latest_binding_revision")
    {"projection_state" => "project", "exclusion_reason" => "", "asset" => asset_copy, "binding" => binding_copy}
  end

  def new_reference_row
    path = @run.join("research", "reference-intake", "DUMMY-NEW", "selected.png")
    path.dirname.mkpath
    path.write("dummy new reference pixels\n")
    {
      "projection_state" => "project",
      "exclusion_reason" => "",
      "asset" => {
        "asset_id" => "MEDIA-NEW-REFERENCE",
        "surface_locator" => {
          "source_asset_id" => "DUMMY-OFFICIAL-SOURCE",
          "selected_cell_or_frame_id" => "DUMMY-SELECTED-FRAME",
          "surface_kind" => "video_frame"
        },
        "canonical_path" => relative(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "alt" => "Dummy selected reference frame for routing mechanics.",
        "label" => "Unassigned dummy reference",
        "media_kind" => "image",
        "original_owner" => "dummy_reference_owner",
        "role" => "context_reference",
        "inspection_action" => "consume_bound_interpretation",
        "display_lane" => "reference",
        "receipt" => {
          "receipt_id" => "RECEIPT-DUMMY-REFERENCE",
          "source_identity" => "DUMMY-OFFICIAL-SOURCE",
          "disposition" => "held",
          "function" => "Tests deterministic routing without creative use.",
          "follow_strength" => "bounded_surface_direct",
          "preserve" => "Exact dummy frame identity and hash.",
          "discard" => "No creative or production authority."
        }
      },
      "binding" => {
        "binding_id" => "BIND-NEW-REFERENCE",
        "assignment_state" => "unassigned",
        "target_id" => nil,
        "target_level" => "unassigned",
        "declared_order" => 99,
        "lane_role" => "unassigned",
        "disposition" => "new",
        "review_state" => "pending",
        "state_receipt" => artifact_binding(@fixture.mv.storyboard_path, "dummy_reference_state_receipt"),
        "routing_dispatch_id" => "DISPATCH-CLASSIFY-NEW-REFERENCE"
      }
    }
  end

  def output_row(asset_id, binding_id, filename, role, surface_kind, lane_role, target_id, target_level, media_kind: "image")
    path = @run.join("generations", "dummy-review-projection", filename)
    path.dirname.mkpath
    path.write("#{asset_id} dummy bytes\n")
    {
      "projection_state" => "project",
      "exclusion_reason" => "",
      "asset" => {
        "asset_id" => asset_id,
        "surface_locator" => {
          "source_asset_id" => asset_id,
          "selected_cell_or_frame_id" => asset_id,
          "surface_kind" => surface_kind
        },
        "canonical_path" => relative(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "alt" => "#{asset_id} dummy output.",
        "label" => asset_id,
        "media_kind" => media_kind,
        "original_owner" => "dummy_#{lane_role}_owner",
        "role" => role,
        "inspection_action" => media_kind == "video" ? "playback_review" : "pixel_review_generated_output",
        "display_lane" => "output"
      },
      "binding" => {
        "binding_id" => binding_id,
        "assignment_state" => "assigned",
        "target_id" => target_id,
        "target_level" => target_level,
        "declared_order" => 20,
        "lane_role" => lane_role,
        "disposition" => "candidate",
        "review_state" => "pending",
        "state_receipt" => artifact_binding(@fixture.mv.storyboard_path, "dummy_output_state_receipt")
      }
    }
  end

  def refresh_source_binding!(adapter)
    source = @source_set.fetch("sources").find { |row| row.fetch("adapter_kind") == adapter }
    source["owner_artifact"] = artifact_binding(@owners.fetch(adapter), "#{adapter}_owner")
  end

  def refresh_ordered_binding!(kind)
    key = kind == :fp ? "fp_close_source" : "planning_02a_source"
    @source_set.dig("ordered_review", key)["owner_artifact"] = artifact_binding(@ordered_paths.fetch(kind), "#{key}_owner")
  end

  def rewrite_source_set
    bindings = @source_set.fetch("sources").map { |source| source.fetch("owner_artifact") }
    bindings << @source_set.fetch("director_dispatch_index")
    bindings << @source_set.dig("ordered_review", "fp_close_source", "owner_artifact")
    bindings << @source_set.dig("ordered_review", "planning_02a_source", "owner_artifact")
    owner_pairs = bindings.map { |binding| [binding.fetch("path"), binding.fetch("sha256")] }.uniq.sort
    digest_payload = Marshal.load(Marshal.dump(@source_set))
    digest_payload.delete("source_set_digest")
    digest_payload.delete("projection_revision")
    digest_payload.fetch("base_manifest").delete("sha256")
    @source_set["source_set_digest"] = {
      "algorithm" => "sha256",
      "basis" => "canonical_projection_query_and_owner_bindings_v1",
      "sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(digest_payload))),
      "entry_count" => owner_pairs.length
    }
    write_yaml(@source_set_path, @source_set)
  end

  def canonical_json_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        result[key] = canonical_json_value(value.fetch(key))
      end
    when Array
      value.map { |item| canonical_json_value(item) }
    else
      value
    end
  end

  def binding_by_id(manifest, binding_id)
    manifest.fetch("review_assets").flat_map { |asset| asset.fetch("bindings") }.find do |binding|
      binding.fetch("binding_id") == binding_id
    end
  end

  def artifact_binding(path, role)
    {"path" => relative(path), "sha256" => Digest::SHA256.file(path).hexdigest, "role" => role}
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def write_yaml(path, value)
    path.dirname.mkpath
    path.write(YAML.dump(value))
  end

  def load_yaml(path)
    YAML.safe_load(path.read, aliases: true)
  end

  def run_assembler
    run_command(RbConfig.ruby, SCRIPT, @source_set_path, "--write", "--json")
  end

  def run_command(*command)
    stdout, stderr, status = Open3.capture3(*command.map(&:to_s), chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
