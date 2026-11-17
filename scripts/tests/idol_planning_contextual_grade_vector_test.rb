# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolPlanningContextualGradeVectorTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_planning_contextual_grade_vector.rb")

  def setup
    @dir = Pathname.new(Dir.mktmpdir("planning-grade-vector-", ROOT.join("runs").to_s))
    @source = @dir.join("front-planning.yaml")
    @source.write("front planning bytes\n")
    @path = @dir.join("review.yaml")
    write(document)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir&.directory?
  end

  def test_front_planning_reference_close_requires_motion_and_composition_four
    result = run_validator
    assert result[:status].success?, result[:stderr]

    payload = YAML.safe_load(@path.read, aliases: true)
    row = payload.fetch("criteria").find { |item| item["criterion_id"] == "still_camera_composition_depth_edit_value" }
    row["result"] = 3
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "still camera/composition requires grade 4"

    payload = document
    motion = payload.fetch("criteria").find { |item| item["criterion_id"] == "contiguous_motion_change_and_landing" }
    motion["result"] = 3
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "contiguous motion requires grade 4"
  end

  def test_pre_fp_storyline_uses_its_own_stage_criteria
    payload = document
    payload["stage"] = "pre_fp_storyline"
    payload["reviewer_role"] = "planning_cdd_p1"
    payload["criteria"] = %w[whole_film_opening_to_ending_causality target_audience_promise_lock message_progression_without_repetition storyline_reference_influence_accounting].map { |id| criterion(id, id == "whole_film_opening_to_ending_causality" ? 4 : 3) }
    write(payload)

    result = run_validator
    assert result[:status].success?, result[:stderr]

    payload.fetch("criteria").find { |row| row["criterion_id"] == "whole_film_opening_to_ending_causality" }["result"] = 3
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "opening-to-ending causality requires grade 4"
  end

  def test_draft_keyframe_proof_reuses_fp_hero_core_and_allows_exact_character_and_prop_na
    payload = draft_keyframe_document
    write(payload)
    result = run_validator
    assert result[:status].success?, result[:stderr]

    payload["preview_packet_mode"] = "official_core"
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_match(/fp_hero_core|const/i, result[:stderr])
  end

  def test_draft_keyframe_proof_requires_scene_and_action_motion_four
    {
      "scene_visual_package" => "scene_visual_package requires grade 4",
      "action_pose_motion_readiness" => "action/pose/motion readiness requires grade 4"
    }.each do |criterion_id, message|
      payload = draft_keyframe_document
      payload.fetch("criteria").find { |row| row["criterion_id"] == criterion_id }["result"] = 3
      write(payload)
      result = run_validator
      refute result[:status].success?
      assert_includes result[:stderr], message
    end
  end

  def test_draft_keyframe_proof_rejects_wrong_na_and_low_applicable_grade
    payload = draft_keyframe_document
    character = payload.fetch("criteria").find { |row| row["criterion_id"] == "character_visual" }
    character["result"] = "not_applicable_no_material_prop"
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "character_visual cannot use not_applicable_no_material_prop"

    payload = draft_keyframe_document
    payload.fetch("criteria").find { |row| row["criterion_id"] == "cut_screen_job_neighbor_delta" }["result"] = 2
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "every applicable planning criterion at grade 3 or higher"
  end

  def test_draft_keyframe_performance_is_omitted_for_none_and_numeric_when_present
    payload = draft_keyframe_document
    payload["criteria"] << criterion("performance_readability", 4)
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "performance_readability must be omitted"

    payload = draft_keyframe_document
    payload["performance_mode"] = "supporting"
    payload["criteria"] << criterion("performance_readability", "not_applicable").merge("not_applicable_reason" => "Missing evidence")
    write(payload)
    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "performance_readability cannot use not_applicable"

    payload.fetch("criteria").last.replace(criterion("performance_readability", 3))
    write(payload)
    result = run_validator
    assert result[:status].success?, result[:stderr]
  end

  def test_pixel_rubric_criterion_cannot_enter_planning_vector
    payload = YAML.safe_load(@path.read, aliases: true)
    payload.fetch("criteria").first["criterion_id"] = "artifact_anatomy_crop_provider_input_stability"
    write(payload)

    result = run_validator
    refute result[:status].success?
    assert_match(/criterion_id|schema/i, result[:stderr])
  end

  def test_rejects_stale_source_artifact_hash
    payload = YAML.safe_load(@path.read, aliases: true)
    payload.fetch("source_artifacts").first["sha256"] = "0" * 64
    write(payload)

    result = run_validator
    refute result[:status].success?
    assert_includes result[:stderr], "SHA-256 is stale"
  end

  private

  def document
    ids = %w[storyline_section_major_causality selected_audio_kinetic_edit_usefulness contiguous_motion_change_and_landing still_camera_composition_depth_edit_value four_role_coverage_and_synthesis major_core_whole_film_non_duplication transfer_provenance_feasibility]
    {
      "schema_version" => "idol_planning_contextual_grade_vector.v1",
      "artifact_type" => "planning_contextual_grade_vector",
      "stage" => "front_planning_reference_close",
      "scope_id" => "S01-MJ01",
      "authoring_owner" => "human_or_assigned_model",
      "reviewer_role" => "planning_cdd_p2",
      "performance_mode" => "none",
      "source_artifacts" => [{"path" => @source.relative_path_from(ROOT).to_s, "sha256" => Digest::SHA256.file(@source).hexdigest}],
      "criteria" => ids.map { |id| criterion(id, %w[contiguous_motion_change_and_landing still_camera_composition_depth_edit_value].include?(id) ? 4 : 3) },
      "decision" => "eligible_for_director_review",
      "target_message_treatment" => "pre_fp_locks_not_downstream_pixel_scores",
      "aggregate_score_present" => false,
      "automatic_creative_pass" => false,
      "downstream_pixel_rubric_reuse" => "forbidden",
      "status" => "reviewed"
    }
  end

  def criterion(id, result)
    {"criterion_id" => id, "result" => result, "evidence_locator" => "exact source pixels and authored screen row", "review_note" => "Assigned Director reviewed the exact named evidence."}
  end

  def draft_keyframe_document
    payload = document
    payload.merge!(
      "stage" => "draft_keyframe_proof",
      "scope_id" => "PSCOPE_DRAFT_PROOF",
      "reviewer_role" => "planning_cdd_p3_ci",
      "preview_packet_mode" => "fp_hero_core",
      "criteria" => %w[
        cut_screen_job_neighbor_delta
        character_visual
        scene_visual_package
        action_pose_motion_readiness
        angle_distance_depth_crop_transition_diversity
        reference_transfer_generation_feasibility
        prop_interaction_readability
      ].map do |id|
        case id
        when "scene_visual_package", "action_pose_motion_readiness"
          criterion(id, 4)
        when "character_visual"
          criterion(id, "not_applicable_member_absent").merge("not_applicable_reason" => "No member is visible in this Cut.")
        when "prop_interaction_readability"
          criterion(id, "not_applicable_no_material_prop").merge("not_applicable_reason" => "No material prop exists in this Cut.")
        else
          criterion(id, 3)
        end
      end
    )
    payload
  end

  def write(payload)
    @path.write(YAML.dump(payload))
  end

  def run_validator
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, @path.to_s, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
