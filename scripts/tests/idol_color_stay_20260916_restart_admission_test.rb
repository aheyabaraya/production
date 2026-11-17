# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "yaml"

class IdolColorStay20260916RestartAdmissionTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  RUN = ROOT.join("runs", "aurora-m", "color-stay", "20260811_COLOR_STAY_PRE00")
  DISPATCH = RUN.join("work", "department-dispatches", "DISP-CS-OD-STARTUP-20260916-001.yaml")
  PACK = RUN.join("work", "overall", "20260916-restart", "role-context-pack.json")
  GRAPH_ROUTING = ROOT.join("automation", "graph-default-routing.yaml")

  def test_live_restart_dispatch_validates_through_shipped_validator
    stdout, stderr, status = Open3.capture3(
      "ruby",
      ROOT.join("scripts", "validate_department_dispatch.rb").to_s,
      DISPATCH.to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, [stdout, stderr].join("\n")
    assert_includes stdout, "valid launched department dispatch"
  end

  def test_live_restart_role_context_pack_validates_through_shipped_validator
    stdout, stderr, status = Open3.capture3(
      "ruby",
      ROOT.join("scripts", "idol_role_context_pack.rb").to_s,
      "validate",
      PACK.to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal "pass", result.fetch("status")
    assert_equal [], result.fetch("errors")
  end

  def test_live_restart_artifacts_bind_native_goal_and_legacy_pinned_route
    dispatch = YAML.safe_load(DISPATCH.read, aliases: true)
    pack = JSON.parse(PACK.read)
    routing = YAML.safe_load(GRAPH_ROUTING.read, aliases: true)
    assert_equal "DISP-CS-OD-STARTUP-20260916-001", dispatch.fetch("dispatch_id")
    assert_equal "grok", dispatch.dig("lineage", "provider")
    assert_equal "01a0ab1f-6a8f-7481-8300-e204b59a648b", dispatch.dig("lineage", "session_id")
    assert_equal "overall_director", dispatch.dig("launch", "compiled_launch_prompt", "selected_profile", "profile_id")
    assert_equal "director_startup", dispatch.dig("launch", "compiled_launch_prompt", "selected_profile", "checkpoint_id")
    assert_includes dispatch.dig("launch", "task", "objective"), "GOAL-CS-FULL-MV-RESTART-20260916"
    assert_equal "pass", pack.fetch("status")
    assert_equal "legacy_pinned", pack.dig("activation_binding", "writer")
    assert_equal "shadow_not_default", routing.fetch("status")
    assert_equal "legacy_pinned", routing.dig("writer_boundary", "existing_runs")
  end

  def test_od_compiled_prompt_is_production_not_fixture
    prompt = YAML.safe_load(DISPATCH.read, aliases: true).dig("launch", "compiled_launch_prompt", "rendered_prompt")
    refute_match(/fixture dispatch|fixture gap|fixture assignment delta/i, prompt)
    assert_includes prompt, "e14911a0b8a5"
    assert_includes prompt, "GOAL-CS-FULL-MV-RESTART-20260916"
    assert_equal 4, YAML.safe_load(DISPATCH.read, aliases: true).dig("internal_delegation_summary", "helper_count")
  end

  def test_cdd_edit_and_reviewer_dispatches_and_packs_validate
    %w[
      DISP-CS-CDD-20260916-001
      DISP-CS-01-WORKER-20260916-001
      DISP-CS-EDIT-20260916-001
      DISP-CS-REV-FP-20260916-001
      DISP-CS-REV-02A-20260916-001
      DISP-CS-REV-02B-20260916-001
      DISP-CS-REV-03V-20260916-001
    ].each do |dispatch_id|
      dispatch = RUN.join("work", "department-dispatches", "#{dispatch_id}.yaml")
      stdout, stderr, status = Open3.capture3(
        "ruby",
        ROOT.join("scripts", "validate_department_dispatch.rb").to_s,
        dispatch.to_s,
        chdir: ROOT.to_s
      )
      assert status.success?, "#{dispatch_id}\n#{stdout}\n#{stderr}"
      pack = if dispatch_id == "DISP-CS-OD-STARTUP-20260916-001"
        PACK
      else
        RUN.join("work", "overall", "20260916-restart", "packs", "#{dispatch_id}.role-context-pack.json")
      end
      stdout, stderr, status = Open3.capture3(
        "ruby",
        ROOT.join("scripts", "idol_role_context_pack.rb").to_s,
        "validate",
        pack.to_s,
        chdir: ROOT.to_s
      )
      assert status.success?, "#{pack}\n#{stdout}\n#{stderr}"
      assert_equal "pass", JSON.parse(stdout).fetch("status")
    end
  end

  def test_sequence_units_and_02b_review_bind_real_hashes
    index = YAML.safe_load(RUN.join("work", "cdd", "20260916-restart", "sequence-units", "INDEX.yaml").read, aliases: true)
    assert_equal 10, index.fetch("unit_count")
    index.fetch("units").each do |unit|
      assert_equal 5, unit.fetch("frame_sha256s").length
      unit.fetch("frame_sha256s").each { |digest| assert_match(/\A[a-f0-9]{64}\z/, digest) }
      record = RUN.join("work", "cdd", "20260916-restart", "sequence-units", unit.fetch("sequence_unit_id"), "sequence-unit.yaml")
      assert record.file?, record.to_s
    end
    review = RUN.join("work", "overall", "20260916-restart", "reviews", "02B-pixel-review.md").read
    assert_includes review, "e90bddc8564fbdda28a84ea83e28e247d2836f89ff5b574c8836b2b0e26fc512"
    assert_includes review, "DISP-CS-REV-02B-20260916-001"
    assert_match(/implemented-and-executed|implemented and executed/i, review)
  end

  REVIEWER_LANES = {
    "DISP-CS-REV-FP-20260916-001" => {
      "profile_id" => "pre_02a_development_block_fp",
      "checkpoint_id" => "fp_close_shard",
      "receipt" => "FP-independent-review.md"
    },
    "DISP-CS-REV-01-20260916-001" => {
      "profile_id" => "pre_02a_development_block_fp",
      "checkpoint_id" => "section_01_core_direction",
      "receipt" => "01-independent-review.md"
    },
    "DISP-CS-REV-02A-20260916-001" => {
      "profile_id" => "pre_02a_development_block_fp",
      "checkpoint_id" => "section_02a_coverage",
      "receipt" => "02A-independent-review.md"
    },
    "DISP-CS-REV-02B-20260916-001" => {
      "profile_id" => "post_02a_02b_image",
      "checkpoint_id" => "section_generated_image_review",
      "receipt" => "02B-pixel-review.md"
    },
    "DISP-CS-REV-03V-20260916-001" => {
      "profile_id" => "post_02a_03v",
      "checkpoint_id" => "section_03v_playback_review",
      "receipt" => "03V-playback-review.md"
    },
    "DISP-CS-REV-04-20260916-001" => {
      "profile_id" => "edit_director",
      "checkpoint_id" => "edit_qc_section",
      "receipt" => "04-independent-review.md"
    },
    "DISP-CS-REV-05-20260916-001" => {
      "profile_id" => "edit_director",
      "checkpoint_id" => "edit_master_closeout",
      "receipt" => "05-independent-review.md"
    }
  }.freeze

  def test_reviewer_lanes_use_creative_checkpoints_and_real_receipts
    stale_cores = "c377c6d4248727e3c36314751b02e448d4ed09d26d412de8c0ae81e08e55f957"
    live_cores = "10c2889045ece2d6734bdaec3537384cfb10d03668a62d9f2a4a3f0dec6cb1c6"
    REVIEWER_LANES.each do |dispatch_id, expected|
      dispatch_path = RUN.join("work", "department-dispatches", "#{dispatch_id}.yaml")
      dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
      profile = dispatch.dig("launch", "compiled_launch_prompt", "selected_profile")
      refute_equal "harness_maintenance", profile.fetch("profile_id"), dispatch_id
      refute_equal "script_validator_registry", profile.fetch("checkpoint_id"), dispatch_id
      refute_equal "mechanical_coordinator", dispatch.dig("routing_identity", "logical_role"), dispatch_id
      assert_equal expected.fetch("profile_id"), profile.fetch("profile_id"), dispatch_id
      assert_equal expected.fetch("checkpoint_id"), profile.fetch("checkpoint_id"), dispatch_id
      assert_equal "worker", dispatch.dig("routing_identity", "logical_role"), dispatch_id
      paths = dispatch.dig("launch", "bounded_output", "expected_paths")
      assert_equal 1, paths.length, dispatch_id
      receipt = ROOT.join(paths.first)
      assert_equal expected.fetch("receipt"), receipt.basename.to_s, dispatch_id
      assert receipt.file?, receipt.to_s
      assert_operator receipt.size, :>, 100, "#{dispatch_id} expected_paths is a stub: #{receipt} (#{receipt.size} bytes)"
      refute_match(/\A# Independent \S+ review\n\z/, receipt.read)

      pack = JSON.parse(RUN.join("work", "overall", "20260916-restart", "packs", "#{dispatch_id}.role-context-pack.json").read)
      refute_equal "harness_maintenance", pack.dig("identity", "profile_id"), dispatch_id
      assert_equal expected.fetch("profile_id"), pack.dig("identity", "profile_id"), dispatch_id
      assert_equal expected.fetch("checkpoint_id"), pack.dig("identity", "checkpoint_id"), dispatch_id
      assert_equal "pass", pack.fetch("status")
    end

    fp = RUN.join("work", "overall", "20260916-restart", "reviews", "FP-independent-review.md").read
    two_a = RUN.join("work", "overall", "20260916-restart", "reviews", "02A-independent-review.md").read
    assert_includes fp, live_cores
    refute_includes fp, stale_cores
    assert_includes two_a, live_cores
    refute_includes two_a, stale_cores
  end
end
