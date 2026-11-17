# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_03v_fixture"

class IdolVideoPromptManifestTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_video_prompt_manifest.rb")
  SCHEMA = ROOT.join("schemas", "video-prompt-manifest.schema.json")

  def teardown
    @fixture&.cleanup
  end

  def test_default_i2v_uses_one_passed_official_core_frame
    @fixture = Active03VFixture.create(branch_count: 2, include_official_core: true)
    document = @fixture.video_manifest_document
    result = validate(document)
    assert result[:status].success?, errors(result)
    execution = document.dig("cues", 0, "grok_execution")
    assert_equal "official_core", execution["source_production_cut_type"]
    assert_equal 1, execution["source_image_frame_count"]
    assert_equal "image_to_video", execution["selected_tool"]
    assert_empty execution["additional_reference_image_ids"]
    assert_equal "C1", execution["section_cohort_id"]
    assert_equal "C1", document.dig("cues", 0, "section_cohort_id")
    assert_equal "CDD-P3-C1", document.dig("section_shards", 0, "planning_cdd_lane_id")
    assert_equal "CDD-V-C1", document.dig("section_shards", 0, "production_cdd_lane_id")
  end

  def test_cue_and_execution_cannot_drift_from_the_02b_to_03v_cohort
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document
    document.dig("cues", 0)["section_cohort_id"] = "C2"
    document.dig("cues", 0, "grok_execution")["section_cohort_id"] = "C2"

    result = validate(document)

    refute result[:status].success?
    assert_includes errors(result), "section_cohort_id must exact-carry the Production Cut review cohort"
  end

  def test_reference_to_video_requires_founder_exact_order
    @fixture = Active03VFixture.create(branch_count: 3, include_official_core: true)
    document = @fixture.video_manifest_document(tool: "reference_to_video")
    document.dig("cues", 0, "grok_execution", "founder_reference_selection")["selected_image_ids_in_order"].reverse!
    result = validate(document)
    refute result[:status].success?
    assert_includes errors(result), "reference_to_video requires exact Founder-selected image IDs and order"
  end

  def test_720_candidate_requires_same_job_passed_cdd_480p_review
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document(resolution_pass: "720p_candidate")
    assert validate(document)[:status].success?
    document.dig("cues", 0, "grok_execution", "source_480p_playback_review")["video_job_id"] = "OTHER_JOB"
    result = validate(document)
    refute result[:status].success?
    assert_includes errors(result), "720p candidate requires same-job passed CDD 480p playback review without resolution mismatch"
  end

  def test_requested_observed_mismatch_holds_720_promotion
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document(resolution_pass: "720p_candidate")
    document.dig("cues", 0, "grok_execution", "source_480p_playback_review")["observed_resolution"] = "720p"
    result = validate(document)
    refute result[:status].success?
    assert_match(/without resolution mismatch|expected.*480p/i, errors(result))
  end

  def test_prompt_hash_and_no_rewrite_are_exact
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document
    document.dig("cues", 0)["prompt_text"] = "#{document.dig('cues', 0, 'prompt_text')} rewritten"
    result = validate(document)
    refute result[:status].success?
    assert_includes errors(result), "prompt hash must match exact 03V prompt bytes"
  end

  def test_full_storyline_lineage_and_screen_progression_are_exact_04_carry
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document
    assert validate(document)[:status].success?

    document.dig("screen_progression_projection", "projected_value", "nodes", 0)["node_id"] = "SPN_DRIFT"
    result = validate(document)
    refute result[:status].success?
    assert_includes errors(result), "screen_progression_projection must exact-copy the complete 02A map"

    document = @fixture.video_manifest_document
    document.dig("storyline_lineage_projection", "source_value_sha256").replace("0" * 64)
    result = validate(document)
    refute result[:status].success?
    assert_includes errors(result), "storyline_lineage_projection source hash is stale"
  end

  def test_unsupported_duration_or_resolution_is_rejected
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document
    execution = document.dig("cues", 0, "grok_execution")
    execution["requested_duration_seconds"] = 8
    execution["requested_resolution"] = "1080p"
    result = validate(document)
    refute result[:status].success?
    assert_match(/6|10|480p|720p|enum/i, errors(result))
  end

  def test_old_branch_only_manifest_version_is_rejected
    @fixture = Active03VFixture.create(branch_count: 2)
    document = @fixture.video_manifest_document
    document["schema_version"] = "idol_video_prompt_manifest.v6"
    result = validate(document)
    refute result[:status].success?
    assert_includes errors(result), "only idol_video_prompt_manifest.v8 is active"
  end

  def test_schema_forbids_direct_and_fallback_paths
    text = SCHEMA.read
    assert_includes text, '"direct_image_to_video": {"const": "forbidden"}'
    assert_includes text, '"automatic_fallback": {"const": "none"}'
    refute_match(/1080p.*enum/i, text)
  end

  private

  def validate(document)
    path = @fixture.run_dir.join("03V-video-prompt-manifest.yaml")
    path.write(YAML.dump(document))
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, "--json", path.to_s, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def errors(result)
    ([result[:stderr]] + JSON.parse(result[:stdout]).fetch("errors")).reject(&:empty?).join("\n")
  rescue JSON::ParserError
    result[:stderr]
  end
end
