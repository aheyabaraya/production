# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class Idol03vContextualGradeVectorTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_03v_contextual_grade_vector.rb")

  def setup
    @dir = Pathname.new(Dir.mktmpdir("03v-grade-vector-", ROOT.join("runs").to_s))
    @clip = @dir.join("playback.mp4")
    @clip.write("actual playback bytes\n")
    @path = @dir.join("review.yaml")
    write(document)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir&.directory?
  end

  def test_passes_stage_specific_playback_vector
    result = validate
    assert result[:status].success?, result[:stderr]
  end

  def test_requires_subject_camera_and_audio_grade_four
    {
      "subject_body_action_pose_transition" => "subject motion",
      "temporal_camera_route_or_locked_hold" => "temporal camera",
      "audio_trigger_landing_edit_handoff" => "audio/edit landing"
    }.each do |criterion_id, message|
      payload = document
      payload.fetch("criteria").find { |row| row["criterion_id"] == criterion_id }["result"] = 3
      write(payload)
      result = validate
      refute result[:status].success?
      assert_includes result[:stderr], message
      write(document)
    end
  end

  def test_performance_is_omitted_when_absent_and_required_when_present
    result = validate
    assert result[:status].success?, result[:stderr]

    payload = document
    payload["performance_mode"] = "primary"
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "each 03V stage criterion exactly once"
  end

  def test_rejects_stale_playback_hash
    payload = document
    payload.fetch("source_playbacks").first["sha256"] = "0" * 64
    write(payload)
    result = validate
    refute result[:status].success?
    assert_includes result[:stderr], "SHA-256 is stale"
  end

  private

  def document
    criteria = %w[
      subject_body_action_pose_transition
      temporal_camera_route_or_locked_hold
      audio_trigger_landing_edit_handoff
      depth_parallax_occlusion_reveal_stop
      neighbor_whole_section_motion_diversity
      identity_light_state_geometry_stability
    ]
    {
      "schema_version" => "idol_03v_contextual_grade_vector.v1",
      "artifact_type" => "03v_contextual_grade_vector",
      "stage" => "03v_playback",
      "scope_id" => "S01-VIDEO-01",
      "section_cohort_id" => "C1",
      "section_ids" => ["S01"],
      "authoring_owner" => "human_or_assigned_model",
      "reviewer_role" => "section_cluster_cdd_ci",
      "performance_mode" => "none",
      "source_playbacks" => [{"path" => @clip.relative_path_from(ROOT).to_s, "sha256" => Digest::SHA256.file(@clip).hexdigest, "playback_locator" => "00:00-00:03"}],
      "criteria" => criteria.map { |id| criterion(id, %w[subject_body_action_pose_transition temporal_camera_route_or_locked_hold audio_trigger_landing_edit_handoff].include?(id) ? 4 : 3) },
      "decision" => "eligible_for_director_review",
      "actual_playback_reviewed" => true,
      "aggregate_score_present" => false,
      "automatic_creative_pass" => false,
      "planning_or_pixel_rubric_reuse" => "forbidden",
      "status" => "reviewed"
    }
  end

  def criterion(id, result)
    {"criterion_id" => id, "result" => result, "evidence_locator" => "actual playback #{id}", "review_note" => "Section-Cluster CDD reviewed the exact clip."}
  end

  def write(payload)
    @path.write(YAML.dump(payload))
  end

  def validate
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @path.to_s, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
