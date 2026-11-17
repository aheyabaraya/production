# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

class SelectedAudioAnalysisSchemaTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_selected_audio_analysis.rb")

  def test_active_audio_only_fixture_passes
    with_fixture do |artifact, _document|
      result = validate(artifact)

      assert result[:status].success?, result[:stderr]
      assert_includes result[:stdout], "1 selected-audio section"
    end
  end

  def test_scene_or_camera_authoring_is_rejected
    with_fixture do |artifact, document|
      document.fetch("section_map").first["camera"] = "front tracking shot"
      artifact.write(JSON.pretty_generate(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "camera"
    end
  end

  def test_unknown_version_is_rejected
    with_fixture do |artifact, document|
      document["schema_version"] = "idol_selected_audio_analysis.v0"
      artifact.write(JSON.pretty_generate(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "idol_selected_audio_analysis.v1"
    end
  end

  def test_stale_audio_hash_is_rejected
    with_fixture do |artifact, document|
      document.dig("source_audio", "source_ref")["sha256"] = "0" * 64
      artifact.write(JSON.pretty_generate(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "source_audio.source_ref.sha256 is stale"
    end
  end

  private

  def with_fixture
    Dir.mktmpdir("selected-audio-analysis") do |directory|
      root = Pathname.new(directory)
      audio = write(root, "audio/selected.wav", "selected audio bytes")
      lyrics = write(root, "lyrics/original.txt", "original lyric text")
      artifact = root.join("selected-audio-analysis.json")
      document = fixture_document(root, audio, lyrics)
      artifact.write(JSON.pretty_generate(document))
      yield artifact, document
    end
  end

  def fixture_document(root, audio, lyrics)
    {
      "schema_version" => "idol_selected_audio_analysis.v1",
      "content_id" => "AUDIO_ANALYSIS_TEST",
      "status" => "founder_selected",
      "title" => "Selected Take",
      "source_audio" => {
        "source_ref" => artifact_ref(root, audio),
        "take_id" => "TAKE-01",
        "source_kind" => "manual_production",
        "founder_selection_status" => "selected"
      },
      "lyrics_original" => {
        "source_ref" => artifact_ref(root, lyrics),
        "source_type" => "lyrics",
        "completeness" => "complete",
        "exact_text_or_pointer" => "Use the exact text in lyrics/original.txt.",
        "uncertain_lines" => []
      },
      "sonic_function_read" => {
        "sound_texture" => "Dry percussion under a widening vocal stack.",
        "hook_mechanics" => "A four-note return resolves the held verse phrase.",
        "tempo_speed_groove" => "Half-time weight with clipped double-time accents.",
        "feeling_temperature" => "Restrained and cool before a controlled release.",
        "vocal_rap_color" => "Close low register that opens into a brighter stack.",
        "production_dynamics" => "Sparse opening, denser pickup, then a clean stop.",
        "reference_fit_delta" => "Keeps the reference restraint but has a sharper hook release.",
        "screen_readability_questions" => [
          "Which visible state change should make the hook release legible?"
        ]
      },
      "song_craft_evaluation" => {
        "evaluation_mode" => "single_take",
        "candidate_ids" => ["TAKE-01"],
        "selected_candidate_id" => "TAKE-01",
        "dimensions" => ["hook", "section_contrast"],
        "audition_scorecard" => [
          {
            "candidate_id" => "TAKE-01",
            "dimension_scores" => {"hook" => 8.5, "section_contrast" => 8.0},
            "observed_strength" => "The hook arrives clearly without flattening the verse.",
            "observed_risk" => "The opening can feel too static if its silence is ignored."
          }
        ],
        "selection_reason" => "Founder selected the take after comparative listening.",
        "rejection_consequences" => []
      },
      "selected_cut" => {
        "source_duration_seconds" => 12.0,
        "active_start_seconds" => 0.0,
        "active_end_seconds" => 12.0,
        "selected_duration_seconds" => 12.0,
        "cut_policy" => "Use the complete selected take."
      },
      "lyrics_full_read" => {
        "whole_song_summary" => "Restraint becomes a deliberate release without full closure.",
        "song_meaning_arc" => ["private restraint", "chosen release", "unresolved afterimage"],
        "repeated_phrases_or_hooks" => ["four-note return"],
        "literal_misread_risks" => ["Do not reduce the lyric to a literal escape plot."],
        "front_planning_interpretation_questions" => [
          "Who should receive this shift from restraint to agency, and what promise should the film make?"
        ]
      },
      "section_map" => [
        {
          "section_id" => "S01",
          "label" => "Opening",
          "section_family" => "intro",
          "reserve_status" => "active",
          "start_seconds" => 0.0,
          "end_seconds" => 12.0,
          "energy_read" => "Held pressure with one clear release.",
          "sonic_read" => {
            "sound_texture" => "Dry low percussion and close vocal.",
            "hook_or_motif" => "The four-note return arrives at 8.0 seconds.",
            "speed_groove" => "Half-time weight with short accents.",
            "feeling_shift" => "Restraint opens into deliberate release.",
            "production_detail" => "A clean stop makes the return audible."
          },
          "lyric_source" => "literal_lyric",
          "lyric_function" => "A private declaration turns into chosen agency.",
          "music_function" => "Establish tension and deliver the first hook.",
          "audio_triggers" => [
            {
              "trigger_id" => "TR01",
              "trigger_type" => "vocal_entry",
              "time_seconds" => 1.0,
              "audible_fact" => "The first vocal enters after a short empty beat.",
              "evidence_refs" => []
            }
          ],
          "audio_motion_questions" => [
            "Which pulse and stop points require later state-change decisions?"
          ],
          "front_planning_questions" => [
            "What section role should embody restraint before the hook release?"
          ],
          "editability_evidence" => ["The stop at 7.8 seconds exposes a clean musical anchor."]
        }
      ],
      "audio_motion_handoff" => {
        "owner" => "idol-song-lock",
        "next_contract" => "idol_audio_motion_director_map.v1",
        "cues_to_map" => ["first vocal entry", "7.8-second stop", "four-note hook return"],
        "precision_marker_sources" => [],
        "timing_risks" => ["The opening silence must not be mistaken for missing audio."],
        "boundary" => "audio_evidence_and_questions_only"
      },
      "promotion_readiness" => {
        "selected_take_confirmed" => true,
        "craft_evaluation_complete" => true,
        "lyrics_or_instrumental_status_confirmed" => true,
        "section_map_complete" => true,
        "next_action" => "build_audio_motion_map",
        "notes" => "The take is ready for rhythm evidence mapping."
      },
      "open_questions" => [],
      "hold_reasons" => []
    }
  end

  def write(root, relative, content)
    path = root.join(relative)
    path.dirname.mkpath
    path.write(content)
    path
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
