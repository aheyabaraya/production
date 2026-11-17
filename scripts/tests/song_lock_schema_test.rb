# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class SongLockSchemaTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  SCHEMA = ROOT.join("schemas", "song-lock.schema.json")

  def test_active_v1_5_fixture_passes
    with_fixture do |artifact, _document|
      result = validate(artifact)

      assert result[:status].success?, result[:stderr]
    end
  end

  def test_old_song_lock_version_is_not_readable
    with_fixture do |artifact, document|
      document["schema_version"] = "1.4"
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_match(/1\.5/, result[:stderr])
    end
  end

  def test_selected_audio_and_audio_motion_sources_are_mandatory
    with_fixture do |artifact, document|
      document.delete("source_audio_motion_director_map")
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "source_audio_motion_director_map"
    end
  end

  def test_song_lock_cannot_author_scene_or_camera_truth
    with_fixture do |artifact, document|
      document.fetch("section_lock").first["action_directive"] = "front tracking shot"
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "action_directive"
    end
  end

  private

  def with_fixture
    Dir.mktmpdir("song-lock-v1-4") do |directory|
      root = Pathname.new(directory)
      analysis = write(root, "research/selected-audio-analysis-v1.yaml", "selected audio analysis\n")
      motion = write(root, "research/audio-motion-director-map-v1.yaml", "audio motion map\n")
      audio = write(root, "audio/selected.wav", "selected audio\n")
      lyrics = write(root, "research/lyrics-original.txt", "original lyric\n")
      document = fixture_document(root, analysis, motion, audio, lyrics)
      artifact = root.join("00A-song-lock.yaml")
      artifact.write(YAML.dump(document))
      yield artifact, document
    end
  end

  def fixture_document(root, analysis, motion, audio, lyrics)
    {
      "schema_version" => "1.5",
      "content_id" => "SONG_LOCK_TEST",
      "status" => "locked",
      "source_selected_audio_analysis" => artifact_ref(root, analysis),
      "source_audio_motion_director_map" => artifact_ref(root, motion),
      "selected_audio" => {
        "source_ref" => artifact_ref(root, audio),
        "take_id" => "TAKE-01",
        "engine_or_source" => "manual production",
        "founder_selection_status" => "locked",
        "lyrics_status" => "lyrics_present",
        "source_lyrics_original" => artifact_ref(root, lyrics)
      },
      "song_first_policy" => {
        "decision" => "lock_selected_song_before_front_planning",
        "reason" => "Section timing and hook behavior must come from the actual take.",
        "downstream_rule" => "front_planning_owns_target_message_visual_identity_members_references_and_section_scene_flow"
      },
      "tempo_form_lock" => {
        "main_grid_bpm" => 120,
        "perceived_pulse" => "half-time body pressure with double-time accents",
        "meter" => "4/4",
        "duration_seconds" => 12.0,
        "energy_curve" => "restrained opening, pressure rise, hook release",
        "selected_take_craft_consequences" => [
          "Preserve the clear stop before the hook return."
        ]
      },
      "hook_lock" => {
        "hook_phrase_or_sound" => "four-note vocal return",
        "hook_function" => "releases the held opening pressure",
        "first_15s_impact" => "The 12-second intro arc establishes a clipped sonic identity and completes its held setup.",
        "return_or_variation_rule" => "The first full hook and middle return preserve the four-note phrase while the middle return increases vocal density."
      },
      "song_meaning_guard" => {
        "lyric_or_sonic_thesis" => "Agency becomes audible as restraint turns into chosen release.",
        "emotional_progression" => "private restraint to deliberate release to unresolved afterimage",
        "literal_misread_guards" => ["Do not reduce the lyric to a literal escape plot."],
        "tonal_boundaries" => "Keep tension precise rather than uniformly tragic or triumphant.",
        "front_planning_questions" => [
          "Who should receive this shift, and what content promise makes it meaningful?"
        ]
      },
      "section_lock" => [
        {
          "section_id" => "S01",
          "label" => "Opening",
          "section_family" => "intro",
          "start_seconds" => 0.0,
          "end_seconds" => 12.0,
          "song_function" => "withhold pressure and deliver the first hook",
          "lyric_function" => "private declaration becomes chosen agency",
          "energy_and_density" => "sparse opening with one controlled release",
          "audible_triggers" => ["1.0-second vocal entry", "7.8-second stop", "8.0-second hook return"],
          "meaning_guard" => "The release is deliberate, not an automatic victory.",
          "front_planning_questions" => [
            "Which section scene role should embody the shift without literalizing the lyric?"
          ]
        }
      ],
      "audio_pressure_handoff" => {
        "opening_exception" => "Preserve the initial silence as tension.",
        "high_pressure_sections" => ["S01 reaches its pressure peak immediately before the hook."],
        "break_or_reset_read" => "The 7.8-second stop is the primary reset.",
        "audible_state_change_rule" => "Later screen planning must answer the stop and release with a legible change.",
        "scope" => "audio_pressure_and_questions_not_screen_answers",
        "front_planning_questions" => [
          "What visible state change best serves the target and message at the hook?"
        ]
      },
      "song_editability_guard" => {
        "section_boundary_readability" => "The hook return exposes a clear audible turn.",
        "musical_anchor_events" => ["7.8-second stop", "8.0-second hook return"],
        "cutdown_viability" => "The hook can anchor shorter derivatives without changing the song order.",
        "timing_risks" => ["Do not erase the pre-hook silence."],
        "exact_edit_lock_owner" => "04_edit",
        "exclusions" => [
          "visual_source_in",
          "visual_source_out",
          "speed_factor",
          "generated_video_candidate",
          "final_cutpoint"
        ]
      },
      "founder_gate" => {
        "decision" => "pass",
        "selected_take_confirmed" => true,
        "founder_decisions" => ["Founder locked TAKE-01 for Front Planning."],
        "integrity_checks" => ["source hashes present", "section ids and timing agree"]
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
      ROOT.join("scripts", "idol-video-python").to_s,
      VALIDATOR.to_s,
      SCHEMA.to_s,
      artifact.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
