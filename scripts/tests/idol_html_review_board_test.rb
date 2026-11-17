# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require_relative "support/active_review_board_fixture"

class IdolHtmlReviewBoardTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_html_review_board.rb")

  def setup
    @fixture = ActiveReviewBoardFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_active_v12_g40_board_validates_and_renders_the_full_review_hierarchy
    validation = run_board("validate")
    assert validation[:status].success?, validation[:stderr]

    render = run_board("render")
    assert render[:status].success?, render[:stderr]
    payload = JSON.parse(render[:stdout])
    assert_equal 4, payload.fetch("card_count")
    assert_equal 1, payload.fetch("section_count")
    assert @fixture.output_path.file?

    html = @fixture.output_path.read
    assert_includes html, "Active Title Founder Review"
    assert_includes html, "TARGET"
    assert_includes html, "MESSAGE"
    assert_includes html, "WHOLE-VIDEO FLOW"
    assert_includes html, "SECTION FLOW"
    assert_includes html, "1.1.1.1"
    assert_includes html, "Branch Cut BC01"
    assert_includes html, "PASS"
    assert_includes html, "HOLD"
    assert_includes html, "REJECT"
    refute_includes html, ">REVISE<"
    assert_includes html, 'name="idol-generator" content="idol_html_review_board.v12"'
    assert_includes html, 'class="storyline-readout mismatch-aligned"'
    assert_includes html, "DIRECTOR STORYLINE · BRANCH CUT"
    assert_includes html, 'name="idol-review-mode" content="g40_core_branch_authorization"'
    assert_includes html, "Decision contract · g40_core_branch_authorization"
    assert_includes html, "overall_director"
    assert_includes html, "DISPATCH-CARD-BC01"
    assert_includes html, "WORKER EVIDENCE"
    assert_includes html, "ATTEMPT-CARD-BC01"
    assert_includes html, "founder_receipt"
    assert_includes html, 'name="idol-review-board-visual-profile" content="idol-dark-core-readable-v2"'
    assert_includes html, "Decision contract"
    assert_includes html, "FOUNDER-EPOCH-ACTIVE"
    assert_includes html, 'name="idol-review-board-font-profile" content="pretendard-inter-system-v1"'
    assert_includes html, 'name="idol-review-board-projection-profile" content="founder-workbench-continuity-v1"'
    assert_includes html, 'name="idol-review-board-active-cycle" content="CYCLE-ACTIVE-001"'
    assert_includes html, ".core-visual-layout{display:grid;grid-template-columns:var(--member-rail) minmax(0,1fr)"
    assert_includes html, "--member-rail:clamp(280px,28vw,420px)"
    assert_includes html, ".core-reference-grid{min-width:0;padding:0 14px 12px"
    assert_includes html, "grid-auto-flow:column"
    assert_includes html, "scroll-snap-type:x mandatory"
    assert_includes html, "refreshCarousels"
    assert_includes html, "t === img"
    assert_includes html, "--font-sans:Pretendard,Inter"
    assert_includes html, "--font-mono:ui-monospace"
    assert_includes html, "object-fit:contain!important"
    refute_includes html, "object-fit:cover"
    assert_includes html, 'class="read-stack"'
    assert_includes html, 'class="judge-band"'
    assert_includes html, 'class="media-meta"'
    assert_includes html, 'class="review-asset-register"'
    assert_includes html, 'data-media-filter="new"'
    assert_includes html, 'data-media-filter="new" aria-pressed="false"'
    assert_includes html, "button.setAttribute('aria-pressed', String(selected))"
    assert_includes html, 'id="showPending" aria-pressed="false"'
    assert_includes html, "event.currentTarget.setAttribute('aria-pressed', String(pendingOnly))"
    assert_includes html, 'class="decision tone-pass" aria-pressed="false"'
    assert_includes html, 'data-source-stage="front_planning"'
    assert_includes html, 'class="screen-summary"'
    assert_includes html, 'class="secondary-pack primary-detail-pack"'
    assert_includes html, 'class="media-state-badge state-active_used"'
    assert_includes html, 'input.value.split(/[\n,]+/)'
    refute_includes html, "input.value.split(/[\n,]+/)".sub("\\n", "\n")
  end

  def test_core_cut_keeps_member_rail_left_and_expands_references_on_the_right
    core_cut = @fixture.manifest.dig("sections", 0, "cards", 2)
    lead_ref = core_cut.fetch("media").first
    lead = @fixture.manifest.fetch("review_assets").find { |asset| asset.fetch("asset_id") == lead_ref.fetch("asset_id") }
    lead_binding = lead.fetch("bindings").find { |binding| binding.fetch("binding_id") == lead_ref.fetch("binding_id") }
    5.times do |index|
      asset = Marshal.load(Marshal.dump(lead))
      asset_id = "MEDIA-C01-SUPPORT-#{index + 1}"
      binding_id = "BIND-C01-SUPPORT-#{index + 1}"
      path = @fixture.mv.run_dir.join("generations", "branch-cuts", "S01", asset_id, "original.png")
      path.dirname.mkpath
      path.write("#{asset_id} pixels\n")
      asset["asset_id"] = asset_id
      asset["canonical_path"] = @fixture.relative(path)
      asset["sha256"] = Digest::SHA256.file(path).hexdigest
      asset["surface_locator"] = asset.fetch("surface_locator").merge(
        "source_asset_id" => asset_id,
        "selected_cell_or_frame_id" => asset_id
      )
      asset["role"] = "generated_branch_cut"
      asset["display_lane"] = "reference"
      asset["bindings"] = [Marshal.load(Marshal.dump(lead_binding)).merge(
        "binding_id" => binding_id,
        "lane_role" => "generated_output",
        "source_stage" => "generated_branch_review",
        "declared_order" => index + 4
      )]
      @fixture.manifest.fetch("review_assets") << asset
      core_cut["media"] << {"asset_id" => asset_id, "binding_id" => binding_id}
    end
    @fixture.write_manifest

    render = run_board("render")
    assert render[:status].success?, render[:stderr]

    html = @fixture.output_path.read
    core_article = html.match(/<article[^>]+id="CYCLE-ACTIVE-001--CARD-C01".*?<\/article>/m)&.to_s
    refute_nil core_article
    assert_includes core_article, "core-visual-layout"
    assert_includes core_article, "member-visual-rail"
    assert_includes core_article, "core-reference-grid"
    assert_includes core_article, "media-carousel"
    assert_includes core_article, "data-carousel"
    assert_includes core_article, "data-carousel-prev"
    assert_includes core_article, "data-carousel-next"
    assert_includes core_article, "display-lane-member_face"
    assert_equal 5, core_article.scan("display-lane-reference").length
    assert_equal 6, core_article.scan('class="media-panel').length
    assert_includes core_article, 'data-count="5" style="--visible-slots:4"'
    assert_includes core_article, 'aria-label="Image 1 of 5">01 / 05'
    assert_includes core_article, 'aria-label="Image 5 of 5">05 / 05'
    assert_includes html, "grid-auto-columns:calc((100% - ((var(--visible-slots) - 1) * 10px)) / var(--visible-slots))"
    assert_includes html, "@media(max-width:900px)"
    refute_includes html, ".core-reference-grid{grid-template-columns:repeat(auto-fit"
  end

  def test_board_output_is_forced_to_the_single_stable_workbench_path
    @fixture.manifest["board"]["output_path"] = @fixture.relative(
      @fixture.mv.run_dir.join("review", "storyboard-review.html")
    )
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "single stable review path"
    assert_includes result[:stderr], "review/founder-workbench.html"
  end

  def test_old_board_version_is_rejected_without_compatibility
    @fixture.manifest["schema_version"] = "idol-html-review-board.v4"
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "schema_version must be one of: idol-html-review-board.v12"
  end

  def test_decision_options_are_exactly_pass_hold_reject
    @fixture.manifest["decision_options"].insert(
      2,
      {"id" => "revise", "label" => "REVISE", "tone" => "revise"}
    )
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_match(/do not match g40_core_branch_authorization review mode|too long/i, result[:stderr])
  end

  def test_discovery_mode_is_sectionless_and_renders_non_gating_exploration_actions
    make_discovery_board

    result = run_board("render")

    assert result[:status].success?, result[:stderr]
    html = @fixture.output_path.read
    assert_includes html, 'name="idol-review-mode" content="g00_direction_draft"'
    assert_includes html, "ATTRACTED"
    assert_includes html, "CONNECT THESE"
    assert_includes html, "KEEP ONLY"
    assert_includes html, "SEARCH FURTHER"
    assert_includes html, "DIRECT COMMENT"
    assert_includes html, "No section lock"
    refute_includes html, ">PASS<"
  end

  def test_g30_groups_each_event_sheet_with_its_core_marks
    make_direction_board
    run_dir = @fixture.mv.run_dir
    sheet = run_dir.join("references", "SU-EVENT-A", "contact-sheet-5in1.png")
    frame = run_dir.join("references", "SU-EVENT-A", "frame-02.png")
    sheet.dirname.mkpath
    sheet.write("sequence parent sheet\n")
    frame.write("core mark still\n")
    card = @fixture.manifest.dig("sections", 0, "cards", 0)
    card["media"] = [
      {
        "asset_id" => "ASSET-SU-EVENT-A-SHEET",
        "path" => @fixture.relative(sheet),
        "sha256" => Digest::SHA256.file(sheet).hexdigest,
        "alt" => "event sequence sheet",
        "label" => "SU-EVENT-A sheet",
        "media_type" => "image",
        "role" => "primary_reference",
        "display_lane" => "reference",
        "surface_locator" => {
          "surface_kind" => "sequence_sheet",
          "source_asset_id" => "SU-EVENT-A",
          "selected_cell_or_frame_id" => "SU-EVENT-A-SHEET"
        },
        "inspection_action" => "consume_bound_interpretation",
        "receipt" => {
          "receipt_id" => "RCPT-SU-EVENT-A-SHEET",
          "source_identity" => "SU-EVENT-A",
          "disposition" => "applied",
          "function" => "event sequence parent sheet",
          "follow_strength" => "sequence_direct",
          "preserve" => "contiguous event flow",
          "discard" => "none"
        }
      },
      {
        "asset_id" => "ASSET-SU-EVENT-A-CORE",
        "path" => @fixture.relative(frame),
        "sha256" => Digest::SHA256.file(frame).hexdigest,
        "alt" => "event core mark",
        "label" => "SU-EVENT-A core",
        "media_type" => "image",
        "role" => "primary_reference",
        "display_lane" => "reference",
        "surface_locator" => {
          "surface_kind" => "sequence_sheet_cell",
          "source_asset_id" => "SU-EVENT-A",
          "selected_cell_or_frame_id" => "SU-EVENT-A-FRAME-02"
        },
        "inspection_action" => "consume_bound_interpretation",
        "receipt" => {
          "receipt_id" => "RCPT-SU-EVENT-A-CORE",
          "source_identity" => "SU-EVENT-A",
          "disposition" => "applied",
          "function" => "must-remain event core",
          "follow_strength" => "bounded_surface_direct",
          "preserve" => "peak still",
          "discard" => "none"
        }
      }
    ] + Array(card["media"])
    @fixture.write_manifest

    result = run_board("render")
    assert result[:status].success?, result[:stderr]
    html = @fixture.output_path.read
    assert_includes html, 'data-g30-layout="per_event_sequence_parent_core_marks"'
    assert_includes html, 'data-event-key="SU-EVENT-A"'
    assert_includes html, "g30-sequence-parent"
    assert_includes html, "g30-core-marks"

    scalar_source = run_dir.join("work", "g30-event-scalars.json")
    scalar_source.write(JSON.generate({
      "sheet_path" => @fixture.relative(sheet), "core_path" => @fixture.relative(frame),
      "event_id" => "SU-EVENT-A", "sheet_kind" => "sequence_sheet", "core_kind" => "sequence_sheet_cell"
    }))
    source_id = "G30-EVENT-SCALARS"
    @fixture.manifest.fetch("sources") << {
      "source_id" => source_id, "path" => @fixture.relative(scalar_source),
      "sha256" => Digest::SHA256.file(scalar_source).hexdigest, "role" => "Synthetic G30 resolved media bindings"
    }
    card.fetch("media").first(2).each_with_index do |media, index|
      media["path"] = {"source_id" => source_id, "pointer" => index.zero? ? "/sheet_path" : "/core_path"}
      media.fetch("surface_locator")["source_asset_id"] = {"source_id" => source_id, "pointer" => "/event_id"}
      media.fetch("surface_locator")["surface_kind"] = {"source_id" => source_id, "pointer" => index.zero? ? "/sheet_kind" : "/core_kind"}
    end
    @fixture.write_manifest
    pointed = run_board("render")
    assert pointed[:status].success?, pointed[:stderr]
    pointed_html = @fixture.output_path.read
    assert_includes pointed_html, 'data-event-key="SU-EVENT-A"'
    assert_includes pointed_html, "g30-sequence-parent"
    assert_includes pointed_html, "g30-core-marks"
    refute_includes pointed_html, 'data-event-key="."'
    card.fetch("media").first.fetch("surface_locator")["source_asset_id"]["pointer"] = "/missing_event_id"
    @fixture.write_manifest
    invalid = run_board("validate")
    refute invalid[:status].success?
    assert_includes invalid[:stderr], "pointer key is missing"
  end

  def test_g30_supports_exactly_three_complete_routes_and_rejects_a_fourth
    make_direction_board

    valid = run_board("render")
    assert valid[:status].success?, valid[:stderr]
    html = @fixture.output_path.read
    assert_includes html, "review-mode-g30_fp_final"
    assert_includes html, "SELECT COMPLETE ROUTE"
    assert_includes html, "FP-A · RECOMMENDED"
    assert_includes html, "FP-C · ALTERNATIVE"
    assert_includes html, "REFERENCE COMPLETE"
    assert_includes html, "HERO GENERATED"
    assert_includes html, "entryFor(key).action === 'select_candidate'"

    fourth = Marshal.load(Marshal.dump(@fixture.manifest.dig("sections", 0, "cards", 2)))
    fourth["card_id"] = "CARD-DIRECTION-FOURTH"
    fourth["review_target"] = fourth.fetch("review_target").merge("target_id" => "TARGET-DIRECTION-FOURTH", "display_number" => "R4")
    @fixture.manifest.dig("sections", 0, "cards") << fourth
    @fixture.write_manifest

    invalid = run_board("validate")
    refute invalid[:status].success?
    assert_includes invalid[:stderr], "exactly one recommendation and two complete alternatives"
  end

  def test_g30_consecutive_same_flow_hold_forbids_ranked_recommendation
    make_direction_board
    cycle = @fixture.manifest.fetch("sections").first
    cycle.fetch("cards").each { |card| card["variant"] = "candidate_alternative" }
    cycle["g30_readiness"]["hold_reasons"] = ["consecutive_same_flow"]
    cycle["g30_readiness"]["controls_enabled"] = false
    @fixture.write_manifest

    schema_cmd = [
      ROOT.join("scripts", "idol-video-python").to_s,
      "scripts/validate_json_schema.py",
      "schemas/html-review-board.schema.json",
      @fixture.manifest_path.to_s
    ]
    schema_stdout, schema_stderr, schema_status = Open3.capture3(*schema_cmd, chdir: ROOT.to_s)
    assert schema_status.success?, schema_stderr
    assert_includes schema_stdout, "schema ok"

    cycle["g30_readiness"]["hold_reasons"] = ["unknown_hold_reason"]
    @fixture.write_manifest
    unknown_stdout, unknown_stderr, unknown_status = Open3.capture3(*schema_cmd, chdir: ROOT.to_s)
    refute unknown_status.success?, unknown_stdout
    assert_includes unknown_stderr, "invalid"
    assert_includes unknown_stderr, "unknown_hold_reason"

    cycle["g30_readiness"]["hold_reasons"] = ["consecutive_same_flow"]
    @fixture.write_manifest

    valid = run_board("render")
    assert valid[:status].success?, valid[:stderr]
    html = @fixture.output_path.read
    assert_includes html, "SAME FLOW HOLD"
    assert_includes html, "G-30 FAIL-CLOSED"
    refute_includes html, "FP-A · RECOMMENDED"

    cycle.fetch("cards").first["variant"] = "recommendation"
    @fixture.write_manifest
    invalid = run_board("validate")
    refute invalid[:status].success?
    assert_includes invalid[:stderr], "consecutive_same_flow hold forbids a ranked recommendation"
  end

  def test_pre_g30_scopes_remain_schema_and_ruby_compatible
    [["g00_direction_draft", true], ["g10_song_lock", true], ["g10_song_lock", false],
     ["g20_visual_identity_lock", true], ["g20_visual_identity_lock", false]].each do |mode, sectionless|
      @fixture.cleanup
      @fixture = ActiveReviewBoardFixture.create
      if mode == "g00_direction_draft"
        make_discovery_board
      else
        disable_continuity_profile
        @fixture.manifest.fetch("board")["review_mode"] = mode
        cycle = @fixture.manifest.fetch("sections").first
        cycle["review_mode"] = mode
        if sectionless
          cycle["scope_mode"] = "sectionless"
          cycle.delete("section_id")
          cycle["covered_section_ids"] = []
          cycle["cards"] = cycle.fetch("cards").first(1)
          cycle.fetch("cards").first["affected_section_ids"] = []
        end
        @fixture.write_manifest
      end
      schema = run_schema
      assert schema[:status].success?, "#{mode} sectionless=#{sectionless}: #{schema[:stderr]}"
      ruby = run_board("validate")
      assert ruby[:status].success?, "#{mode} sectionless=#{sectionless}: #{ruby[:stderr]}"
    end
  end

  def test_g30_retains_nonempty_and_covered_section_guards
    make_direction_board
    cycle = @fixture.manifest.fetch("sections").first
    card = cycle.fetch("cards").first
    [[], ["S99"]].each do |sections|
      card["affected_section_ids"] = sections
      @fixture.write_manifest
      invalid = run_board("validate")
      refute invalid[:status].success?
      assert_match(/at least 1|outside.*review cycle|outside.*review/, invalid[:stderr])
    end
  end

  def test_discovery_schema_still_rejects_production_section_membership
    make_discovery_board
    @fixture.manifest.fetch("sections").first.fetch("cards").first["affected_section_ids"] = ["S01"]
    @fixture.write_manifest
    invalid = run_schema
    refute invalid[:status].success?
    assert_includes invalid[:stderr], "expected to be empty"
  end

  def test_revision_scope_must_equal_numbered_review_target_level
    @fixture.manifest.dig("sections", 0, "cards", 3)["revision_scope"] = "section"
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "revision_scope must equal its review target level"
  end

  def test_media_hash_drift_fails_closed
    reference = @fixture.manifest.dig("sections", 0, "cards", 3, "media", 0)
    asset = @fixture.manifest.fetch("review_assets").find do |candidate|
      candidate.fetch("asset_id") == reference.fetch("asset_id")
    end
    asset["sha256"] = "0" * 64
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "SHA-256 mismatch"
  end

  def test_unassigned_new_asset_stays_visible_in_the_new_inbox
    asset = append_unassigned_asset("MEDIA-INBOX-NEW")
    @fixture.write_manifest

    render = run_board("render")
    assert render[:status].success?, render[:stderr]

    html = @fixture.output_path.read
    assert_includes html, "NEW SINCE LAST REVIEW"
    assert_includes html, asset.fetch("asset_id")
    assert_includes html, 'data-disposition="new"'
    assert_includes html, 'data-new-since-last-review="true"'
    assert_includes html, 'data-lane-role="unassigned"'
  end

  def test_new_since_last_review_is_revision_derived
    @fixture.manifest.dig("review_assets", 0, "bindings", 0)["new_since_last_review"] = false
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "must be derived from declared board revisions"
  end

  def test_card_asset_binding_cannot_point_at_a_different_review_target
    binding = @fixture.manifest.dig("review_assets", 0, "bindings", 0)
    binding["target_id"] = "TARGET-S01"
    binding["target_level"] = "section"
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "binding target must equal card review target"
  end

  def test_generated_output_requires_a_post_02b_source_stage
    binding = @fixture.manifest.dig("review_assets", 0, "bindings", 0)
    binding["lane_role"] = "generated_output"
    binding["source_stage"] = "front_planning"
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "generated_output must project from 02B or generated Branch review"
  end

  def test_reused_path_and_hash_adds_a_binding_instead_of_a_duplicate_asset
    duplicate = Marshal.load(Marshal.dump(@fixture.manifest.fetch("review_assets").first))
    duplicate["asset_id"] = "MEDIA-DUPLICATE-BYTES"
    duplicate.fetch("bindings").first["binding_id"] = "BIND-DUPLICATE-BYTES"
    @fixture.manifest.fetch("review_assets") << duplicate
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_includes result[:stderr], "add a typed binding to the existing asset"
  end

  def test_read_only_fp_close_precedes_decision_bearing_02a_final_planning
    board = @fixture.manifest.fetch("board")
    board["review_sequence"] = [
      {"phase" => "fp_close", "order" => 1, "stage_id" => "front_planning_close", "gate" => "read_only_fp_close_lineage"},
      {"phase" => "planning_02a", "order" => 2, "stage_id" => "storyboard_02a", "gate" => "active_02a_final_planning"}
    ]
    cards = @fixture.manifest.dig("sections", 0, "cards")
    cards.first(2).each { |card| card.merge!("review_phase" => "fp_close", "phase_state" => "read_only") }
    cards.drop(2).each { |card| card.merge!("review_phase" => "planning_02a", "phase_state" => "active") }
    @fixture.write_manifest

    render = run_board("render")
    assert render[:status].success?, render[:stderr]
    html = @fixture.output_path.read
    assert_match(/<button[^>]+data-review-phase="planning_02a"/, html)
    refute_match(/<button[^>]+data-review-phase="fp_close"/, html)
    assert_includes html, "Internal FP Close · exact read-only lineage"

    cards.unshift(cards.delete_at(2))
    @fixture.write_manifest
    invalid = run_board("validate")
    refute invalid[:status].success?
    assert_includes invalid[:stderr], "must present every read-only FP Close storyline card before 02A Final Planning cards"
  end

  def test_collapsed_previous_cycle_defers_media_until_opened
    active = @fixture.manifest.fetch("sections").first
    previous = Marshal.load(Marshal.dump(active))
    previous.merge!(
      "cycle_id" => "CYCLE-PREVIOUS-001",
      "revision_id" => "REV-PREVIOUS-001",
      "status" => "superseded",
      "open_by_default" => false
    )
    active["supersedes_revision_id"] = previous.fetch("revision_id")
    @fixture.manifest.fetch("sections") << previous
    @fixture.write_manifest

    render = run_board("render")
    assert render[:status].success?, render[:stderr]
    html = @fixture.output_path.read
    previous_cycle = html.match(/<details id="CYCLE-PREVIOUS-001".*?<\/details>/m)&.to_s
    refute_nil previous_cycle
    assert_includes previous_cycle, "data-src="
    refute_includes previous_cycle, '<img class="zoomable" loading="lazy" src='
    assert_includes html, "viewState.openGroups"
  end

  def test_dispatch_bound_card_requires_lineage_attempt_session_and_dispatch_index_binding
    baseline = Marshal.load(Marshal.dump(@fixture.manifest))
    %w[lineage_id attempt_id director_dispatch_index].each do |missing_key|
      @fixture.manifest.replace(Marshal.load(Marshal.dump(baseline)))
      @fixture.manifest.dig("sections", 0, "cards", 3, "worker_evidence").delete(missing_key)
      @fixture.manifest_path.write(YAML.dump(@fixture.manifest))

      result = run_board("validate")

      refute result[:status].success?, "missing #{missing_key} unexpectedly validated"
      assert_includes result[:stderr], missing_key
    end
  end

  def test_mechanical_no_worker_card_explicitly_allows_null_session
    evidence = @fixture.manifest.dig("sections", 0, "cards", 3, "worker_evidence")
    evidence["applicability"] = "mechanical_no_worker"
    evidence["session_id"] = nil
    @fixture.manifest_path.write(YAML.dump(@fixture.manifest))

    result = run_board("validate")

    assert result[:status].success?, result[:stderr]
  end

  def test_missing_canonical_source_pointer_fails_closed
    @fixture.manifest.dig("sections", 0, "cards", 3, "source_field_refs", 0)["pointer"] =
      "/master_storyboard/99"
    @fixture.write_manifest

    result = run_board("validate")

    refute result[:status].success?
    assert_match(/pointer.*(?:missing|index)|array pointer index/i, result[:stderr])
  end

  def test_renderer_refuses_to_replace_handwritten_html
    @fixture.output_path.dirname.mkpath
    @fixture.output_path.write("<html><body>Founder handwritten notes</body></html>\n")

    result = run_board("render")

    refute result[:status].success?
    assert_includes result[:stderr], "refusing to replace non-generated HTML"
    assert_includes @fixture.output_path.read, "Founder handwritten notes"
  end

  private

  def append_unassigned_asset(asset_id)
    path = @fixture.mv.run_dir.join("research", "reference-intake", asset_id, "selected.png")
    path.dirname.mkpath
    path.write("#{asset_id} pixels\n")
    source = Marshal.load(Marshal.dump(@fixture.manifest.fetch("review_assets").first))
    source.merge!(
      "asset_id" => asset_id,
      "canonical_path" => @fixture.relative(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "label" => "Unassigned new intake",
      "first_seen_board_revision" => 1,
      "surface_locator" => source.fetch("surface_locator").merge(
        "source_asset_id" => asset_id,
        "selected_cell_or_frame_id" => "SELECTED-NEW"
      ),
      "bindings" => [
        source.fetch("bindings").first.merge(
          "binding_id" => "BIND-#{asset_id}",
          "assignment_state" => "unassigned",
          "target_id" => nil,
          "target_level" => "unassigned",
          "declared_order" => 99,
          "lane_role" => "unassigned",
          "disposition" => "new",
          "review_state" => "pending",
          "new_since_last_review" => true,
          "latest_binding_revision" => 1
        ).tap { |binding| %w[section_id core_cut_id branch_cut_id].each { |key| binding.delete(key) } }
      ]
    )
    @fixture.manifest.fetch("review_assets") << source
    source
  end

  def make_discovery_board
    disable_continuity_profile
    board = @fixture.manifest.fetch("board")
    board["review_mode"] = "g00_direction_draft"
    board["stage_id"] = "front_planning_discovery"
    @fixture.manifest["decision_options"] = [
      {"id" => "attracted", "label" => "ATTRACTED", "tone" => "pass"},
      {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
      {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
      {"id" => "connect_these", "label" => "CONNECT THESE", "tone" => "neutral"},
      {"id" => "keep_only", "label" => "KEEP ONLY", "tone" => "neutral"},
      {"id" => "search_further", "label" => "SEARCH FURTHER", "tone" => "revise"},
      {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
    ]
    cycle = @fixture.manifest.fetch("sections").first
    cycle["review_mode"] = "g00_direction_draft"
    cycle["scope_mode"] = "sectionless"
    cycle["covered_section_ids"] = []
    cycle.delete("section_id")
    cycle.fetch("cards").each_with_index do |card, index|
      card["revision_scope"] = "none"
      card["affected_section_ids"] = []
      card["review_target"] = {
        "target_id" => "TARGET-DISCOVERY-#{index + 1}",
        "level" => "discovery",
        "display_number" => "D#{index + 1}",
        "label" => "Discovery candidate #{index + 1}"
      }
    end
    @fixture.write_manifest
  end

  def make_direction_board
    disable_continuity_profile
    board = @fixture.manifest.fetch("board")
    board["review_mode"] = "g30_fp_final"
    board["stage_id"] = "front_planning_direction_synthesis"
    @fixture.manifest["decision_options"] = [
      {"id" => "select_candidate", "label" => "SELECT COMPLETE ROUTE", "tone" => "pass"},
      {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
      {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
      {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
    ]
    cycle = @fixture.manifest.fetch("sections").first
    cycle["review_mode"] = "g30_fp_final"
    cycle["cards"] = cycle.fetch("cards").first(3)
    cycle.fetch("cards").each_with_index do |card, index|
      card["variant"] = index.zero? ? "recommendation" : "candidate_alternative"
      card["card_type"] = "candidate_route"
      card["route_id"] = "FP-#{("A".ord + index).chr}"
      card["route_readiness"] = {
        "opening_to_ending_story_complete" => true,
        "section_major_stacks_complete" => true,
        "sequence_composition_sets_complete" => true,
        "core_visual_candidate_sets_complete" => true,
        "selected_exact_reference_or_waiver_complete" => true,
        "required_hero_proof_complete" => true,
        "actual_visual_present" => true,
        "materially_distinct" => true
      }
      card["revision_scope"] = "none"
      card["review_target"] = {
        "target_id" => "TARGET-DIRECTION-#{index + 1}",
        "level" => "direction",
        "display_number" => "R#{index + 1}",
        "label" => index.zero? ? "Recommended FP candidate" : "Alternative FP candidate"
      }
    end
    cycle["g30_readiness"] = {
      "route_ids" => %w[FP-A FP-B FP-C],
      "complete_route_count" => 3,
      "route_candidate_set_complete" => true,
      "routes_materially_distinct" => true,
      "actual_visuals_present" => true,
      "reference_complete" => true,
      "hero_generated" => true,
      "controls_enabled" => true,
      "hold_reasons" => []
    }
    @fixture.write_manifest
  end

  def disable_continuity_profile
    assets = @fixture.manifest.fetch("review_assets").to_h { |asset| [asset.fetch("asset_id"), asset] }
    @fixture.manifest.fetch("sections").each do |cycle|
      cycle.fetch("cards").each do |card|
        card["media"] = card.fetch("media").map do |reference|
          asset = assets.fetch(reference.fetch("asset_id"))
          {
            "asset_id" => asset.fetch("asset_id"),
            "surface_locator" => asset.fetch("surface_locator"),
            "path" => asset.fetch("canonical_path"),
            "sha256" => asset.fetch("sha256"),
            "alt" => asset.fetch("alt"),
            "label" => asset.fetch("label"),
            "media_type" => asset.fetch("media_kind"),
            "role" => asset.fetch("role"),
            "display_lane" => asset.fetch("display_lane"),
            "inspection_action" => asset.fetch("inspection_action")
          }
        end
        %w[screen_summary review_phase phase_state].each { |key| card.delete(key) }
      end
    end
    %w[projection_profile projection_revision last_reviewed_revision review_sequence rollback_pair].each do |key|
      @fixture.manifest.fetch("board").delete(key)
    end
    @fixture.manifest.delete("review_assets")
  end

  def run_schema
    stdout, stderr, status = Open3.capture3(
      ROOT.join("scripts", "idol-video-python").to_s,
      "scripts/validate_json_schema.py", "schemas/html-review-board.schema.json",
      @fixture.manifest_path.to_s, chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def run_board(command)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      command,
      @fixture.manifest_path.to_s,
      "--json",
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
