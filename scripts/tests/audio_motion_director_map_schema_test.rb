# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

class AudioMotionDirectorMapSchemaTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_audio_motion_director_map.rb")

  def test_audio_evidence_only_fixture_passes
    with_fixture do |artifact, _document|
      result = validate(artifact)

      assert result[:status].success?, result[:stderr]
      assert_includes result[:stdout], "1 section rhythm record"
    end
  end

  def test_camera_or_prompt_authoring_is_rejected
    with_fixture do |artifact, document|
      document.fetch("section_rhythm_map").first["camera_rhythm"] = "fast push in"
      artifact.write(JSON.pretty_generate(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "camera_rhythm"
    end
  end

  def test_source_analysis_hash_is_enforced
    with_fixture do |artifact, document|
      document.fetch("source_selected_audio_analysis")["sha256"] = "f" * 64
      artifact.write(JSON.pretty_generate(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "source_selected_audio_analysis.sha256 is stale"
    end
  end

  def test_section_timing_cannot_drift_from_selected_audio
    with_fixture do |artifact, document|
      document.fetch("section_rhythm_map").first["end_seconds"] = 11.5
      artifact.write(JSON.pretty_generate(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "end_seconds drifted"
    end
  end

  private

  def with_fixture
    Dir.mktmpdir("audio-motion-map") do |directory|
      root = Pathname.new(directory)
      analysis = root.join("selected-audio-analysis.json")
      analysis.write(
        JSON.pretty_generate(
          {
            "schema_version" => "idol_selected_audio_analysis.v1",
            "section_map" => [
              {
                "section_id" => "S01",
                "reserve_status" => "active",
                "start_seconds" => 0.0,
                "end_seconds" => 12.0
              }
            ]
          }
        )
      )
      artifact = root.join("audio-motion-map.json")
      document = fixture_document(root, analysis)
      artifact.write(JSON.pretty_generate(document))
      yield artifact, document
    end
  end

  def fixture_document(root, analysis)
    {
      "schema_version" => "idol_audio_motion_director_map.v1",
      "content_id" => "AUDIO_MOTION_TEST",
      "status" => "ready_for_00a",
      "source_selected_audio_analysis" => artifact_ref(root, analysis),
      "purpose" => {
        "summary" => "Preserve audible timing pressure and leave screen answers to later stages.",
        "use_rule" => "map_audible_timing_pressure_and_leave_screen_answers_downstream"
      },
      "stable_audio_extracts" => {
        "duration_seconds" => 12.0,
        "tempo" => {
          "main_grid_bpm" => 120,
          "perceived_pulse" => "half-time weight with double-time accents",
          "alternate_grid_or_uncertainty" => "The double-time grid is an accent layer, not a tempo change."
        },
        "meter" => "4/4",
        "signals" => [
          {
            "signal_id" => "SIG01",
            "signal_type" => "vocal_entry",
            "time_seconds" => 1.0,
            "observed_audio_fact" => "The first vocal enters after a short empty beat.",
            "confidence" => "high",
            "evidence_refs" => []
          }
        ],
        "precision_marker_sources" => [],
        "evidence_only_rule" => "measurements_support_listening_and_never_author_creative_truth"
      },
      "section_rhythm_map" => [
        {
          "section_id" => "S01",
          "start_seconds" => 0.0,
          "end_seconds" => 12.0,
          "main_pulse" => "Half-time weight under short upper accents.",
          "energy_density" => "Sparse until the hook return.",
          "accent_grid" => "One clear stop before the four-note return.",
          "onset_stop_reset" => "The 7.8-second stop resets the phrase.",
          "vocal_or_lyric_trigger" => "The first vocal at 1.0 seconds and hook return at 8.0 seconds.",
          "motif_return" => "The four-note hook returns once with a wider vocal stack.",
          "audible_state_change_pressure" => "release",
          "screen_readability_questions" => [
            "What visible state change should make the 8.0-second release readable?"
          ],
          "editability_evidence" => ["The 7.8-second stop is an audible marker candidate."],
          "temporal_camera_deferred_to_03v" => true
        }
      ],
      "trigger_map" => [
        {
          "trigger_id" => "TR01",
          "section_id" => "S01",
          "time_seconds" => 8.0,
          "trigger_type" => "motif_return",
          "audio_fact" => "The four-note vocal hook returns after the stop.",
          "candidate_state_change_question" => "Which later screen decision should answer this release without repeating the verse?",
          "precision_source_ids" => []
        }
      ],
      "downstream_boundary" => {
        "provides_audio_pressure_only" => true,
        "front_planning_owns_target_message_visual_members_references_and_section_scene_flow" => true,
        "front_planning_01_02a_own_still_frame_truth" => true,
        "video_prompt_03v_owns_temporal_camera_after_passed_pixels" => true,
        "image_prompt_02b_translates_passed_02a" => true,
        "prompt_prose_forbidden_here" => true
      },
      "song_lock_handoff" => {
        "section_ids" => ["S01"],
        "audible_pressure_summary" => ["S01 holds pressure before a single hook release."],
        "timing_risks" => ["Do not treat the opening silence as a missing cue."],
        "front_planning_questions" => [
          "Which target-facing section role should receive the hook release?"
        ]
      },
      "open_questions" => [],
      "hold_reasons" => []
    }
  end

  def artifact_ref(root, path)
    {
      "path" => path.relative_path_from(root).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def validate(artifact)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      artifact.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
