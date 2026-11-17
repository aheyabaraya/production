# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolHarnessSectionsTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  CLI = ROOT.join("scripts", "idol_harness_sections.rb")
  RUN = ROOT.join("runs", "2026-07-05", "0705_GIRL_BADUK_WORLD_SIGNAL")
  SOURCES = {
    "01" => RUN.join("01-song-choreography-performance-mv-map.yaml"),
    "02A" => RUN.join("02A-master-storyboard.yaml"),
    "02B" => RUN.join("02B-prompt-packets.yaml")
  }.freeze

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-harness-sections-", "/private/tmp"))
    @map = @tmp.join("explicit-section-map.yaml")
    mappings = ["S00P", "S00", "S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"].map do |visual_id|
      audio_id = visual_id == "S00P" ? "AUDIO_PRE" : "AUDIO_#{visual_id.delete_prefix('S')}"
      row = {
        "visual_section_id" => visual_id,
        "audio_section_id" => audio_id,
        "source_audio_section_ids" => [audio_id],
        "timing" => {}
      }
      if visual_id == "S00P"
        row["timing"] = {
          "start_seconds" => -8.0,
          "end_seconds" => 0.0,
          "primary_audio_section_cue" => "pre-song visual intro before selected audio starts",
          "backing_rhythm_trigger" => "no selected-audio backing rhythm before 0.0 seconds"
        }
      end
      row
    end
    @map.write(YAML.dump("mappings" => mappings))

    @front_source = @tmp.join("front-planning-readiness.yaml")
    @front_map = @tmp.join("front-section-map.yaml")
    front_sections = [
      front_section("V00", "0.000-4.000", "M01", "A00", "door-light line opens behind M01"),
      front_section("V01", "4.000-8.000", "M02", "A01", "M02 steps across the door-light line")
    ]
    @front_source.write(YAML.dump(
      "schema_version" => "front-planning-readiness.v1",
      "content_id" => "HARNESS_FRONT_FIXTURE",
      "section_work_plan" => {
        "sections" => front_sections,
        "unit_or_beat_work_units" => [
          {
            "unit_id" => "U00",
            "parent_section_id" => "V00",
            "time_range" => "0.000-2.000",
            "source_ref_ids" => ["SRC_FRONT"],
            "active_screen_job" => "M01 raises one hand before the door-light line opens.",
            "must_show" => ["hand and door-light line in the same frame"],
            "must_not_show" => ["generic beauty portrait"],
            "handoff_to_next" => "The opened light line becomes V01's floor route.",
            "status" => "done"
          }
        ]
      }
    ))
    @front_map.write(YAML.dump(
      "mappings" => [
        {"visual_section_id" => "V00", "audio_section_id" => "A00", "source_audio_section_ids" => ["A00"]},
        {"visual_section_id" => "V01", "audio_section_id" => "A01", "source_audio_section_ids" => ["A01"]}
      ]
    ))
  end

  def front_section(section_id, time_range, member, audio_id, action)
    {
      "section_id" => section_id,
      "planning_maturity" => "ready_for_01_transfer",
      "time_range" => time_range,
      "source_ref_ids" => ["SRC_FRONT"],
      "participant_or_identity_refs" => [member],
      "object_or_space_refs" => ["door-light corridor"],
      "audio_lock" => {
        "primary_audio_or_section_cue" => "#{audio_id} first bass accent",
        "lyric_original_text" => "I make one move",
        "supporting_rhythm_trigger" => "snare stop after the bass accent",
        "source_audio_refs" => [audio_id]
      },
      "meaning_lock" => {
        "section_function" => "Turn private choice into a visible route.",
        "viewer_read" => "The member chooses the route before the room reacts.",
        "banned_misread" => "No passive waiting or fantasy teleportation."
      },
      "space_visible_feeling_arc" => {
        "space_background_role" => "A narrow practical corridor makes the choice line readable.",
        "visible_feeling_state" => "The member holds still until the hand or step commits.",
        "progression_function" => "The closed route becomes an open floor direction.",
        "adjacent_variation_note" => "V00 opens the line; V01 crosses it from a lower camera."
      },
      "frame_subject_mode" => "member_led",
      "visual_system_anchor" => "door-light line on the corridor floor",
      "visible_action" => action,
      "camera_composition_lock" => "Waist-height medium-wide camera, member on the left third, door-light line receding through foreground and background, feet and hand visible.",
      "screen_cause_effect" => {
        "visible_cause" => action,
        "visible_effect" => "the door-light line changes from closed to open",
        "viewer_or_camera_change" => "camera shifts from frontal hold to a low diagonal route",
        "next_section_bridge" => "the open line continues under the next member's first step"
      },
      "wardrobe_or_material_read" => "Contemporary black performance jacket; sleeve edge stops with the hand and does not cover it.",
      "transition_in" => {
        "audio_or_section_trigger" => "#{audio_id} entry",
        "body_or_formation_bridge" => "preserve the previous hand or step endpoint",
        "camera_or_edit_bridge" => "hold the corridor axis before changing height",
        "space_or_object_change" => "door-light line changes one state only",
        "continuity_lock" => "same practical corridor and light-line material"
      },
      "transition_out" => {
        "audio_or_section_trigger" => "#{audio_id} snare stop",
        "body_or_formation_bridge" => "hand endpoint becomes the next step direction",
        "camera_or_edit_bridge" => "match the light-line direction across the cut",
        "space_or_object_change" => "open line extends into the next section",
        "continuity_lock" => "same line width, color, and floor reflection"
      },
      "downstream_01_transfer" => {
        "function_extracted" => "choice becomes a floor route",
        "current_song_trigger" => "#{audio_id} bass accent and snare stop",
        "screen_translation" => action,
        "01_fields_to_seed" => ["front_planning_transfer", "director_chain.composition_lock", "director_chain.visible_action", "screen_cause_effect"],
        "02a_core_cut_implication" => "Keep the lyric turn and committed body action inside one governing event.",
        "safe_to_auto_seed" => false
      },
      "status" => "done",
      "output_path" => "work/front_planning_integration/sections/#{section_id}.yaml"
    }
  end

  def teardown
    FileUtils.remove_entry(@tmp.to_s) if @tmp&.directory?
  end

  def run_cli(*args, success: true)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, CLI.to_s, *args.map(&:to_s), chdir: ROOT.to_s)
    if success
      assert status.success?, "command failed: #{args.join(' ')}\nstdout=#{stdout}\nstderr=#{stderr}"
    else
      refute status.success?, "command unexpectedly passed: #{args.join(' ')}"
    end
    [stdout, stderr, status]
  end

  def load_yaml(path)
    YAML.safe_load(Pathname.new(path).read, permitted_classes: [], aliases: true)
  end

  def test_inspect_detects_metadata_that_points_to_one_monolith
    stdout, = run_cli("inspect", SOURCES["02A"], "--json")
    report = JSON.parse(stdout)
    assert_equal 10, report["legacy_monolith_pointer_section_count"]
    assert_equal false, report["physical_section_files_present"]
  end

  def test_active_01_02a_02b_stages_extract_validate_and_round_trip_in_private_tmp
    SOURCES.each do |stage, source|
      shard_dir = @tmp.join("#{stage}-shards")
      merged = @tmp.join("#{stage}-merged.yaml")
      run_cli("extract", source, "--section-map", @map, "--output-dir", shard_dir, "--json")
      validate_stdout, = run_cli("validate", shard_dir, "--json")
      assert_equal true, JSON.parse(validate_stdout)["ok"]
      merge_stdout, = run_cli("merge", source, "--shards", shard_dir, "--output", merged, "--json")
      assert_equal true, JSON.parse(merge_stdout)["semantic_round_trip"]
      assert_equal load_yaml(source), load_yaml(merged)
    end
  end

  def test_01_shard_preserves_selected_application_ids_and_structured_camera_route
    source = @tmp.join("01-structured-camera.yaml")
    document = load_yaml(SOURCES["01"])
    route = {
      "contract_version" => "camera_direction.v2",
      "route_id" => "CAM_SECTION_ROUND_TRIP",
      "summary" => "Knee-height medium-long lateral travel with a clean stop.",
      "shot_scale_family" => "SS_MLS",
      "camera_height" => "H_KNEE",
      "direction_angle" => "A_34",
      "depth_design" => "foreground edge, member midground, open background route",
      "movement_family" => "M_TRACK_LATERAL",
      "base_speed" => "V_BRISK",
      "envelope" => "E_EASE_OUT",
      "composition_family" => "C_STACK_DEPTH",
      "lens_feel" => "L_NORMAL",
      "audio_story_job" => "make the pickup and body travel readable",
      "refuse_defaults" => ["front eye-level beauty close"]
    }
    slice = document.dig("section_gate", "slices").find { |row| row["section_id"] == "S00" }
    slice["camera_route_spec"] = route
    slice["research_application_ids"] = ["APP_SECTION_CAMERA_REFERENCE"]
    source.write(YAML.dump(document))

    shard_dir = @tmp.join("01-structured-shards")
    merged = @tmp.join("01-structured-merged.yaml")
    run_cli("extract", source, "--stage", "01", "--section-map", @map, "--output-dir", shard_dir, "--sections", "S00")
    shard = load_yaml(shard_dir.join("S00.yaml"))
    assert_equal ["APP_SECTION_CAMERA_REFERENCE"], shard.dig("payload", "selected_reference_application_ids")
    assert_equal route, shard.dig("payload", "direction_decisions", "camera_route_spec")
    run_cli("merge", source, "--shards", shard_dir, "--output", merged)
    assert_equal document, load_yaml(merged)
  end

  def test_front_planning_section_work_plan_extracts_and_round_trips_without_becoming_a_new_top_level_stage
    shard_dir = @tmp.join("front-shards")
    merged = @tmp.join("front-merged.yaml")
    inspect_stdout, = run_cli("inspect", @front_source, "--json")
    inspect_report = JSON.parse(inspect_stdout)
    assert_equal "front_planning_integration", inspect_report["stage_id"]
    assert_equal 2, inspect_report["section_count"]

    run_cli("extract", @front_source, "--section-map", @front_map, "--output-dir", shard_dir, "--json")
    shard = load_yaml(shard_dir.join("V00.yaml"))
    assert_equal "I make one move", shard.dig("payload", "timing", "lyric_original_text")
    validate_stdout, = run_cli("validate", shard_dir, "--json")
    assert_equal true, JSON.parse(validate_stdout)["ok"]
    run_cli("merge", @front_source, "--shards", shard_dir, "--output", merged, "--json")
    assert_equal load_yaml(@front_source), load_yaml(merged)
  end

  def test_namespaces_are_explicit_and_cut_ids_are_not_recast_as_beats
    shard_dir = @tmp.join("02a-shards")
    run_cli("extract", SOURCES["02A"], "--section-map", @map, "--output-dir", shard_dir, "--sections", "S00")
    contract = load_yaml(shard_dir.join("S00.yaml"))
    ids = contract.dig("payload", "id_namespace")
    assert_equal "AUDIO_00", ids["audio_section_id"]
    assert_equal ["AUDIO_00"], ids["source_audio_section_ids"]
    assert_equal "S00", ids["visual_section_id"]
    assert_empty ids["beat_ids"]
    refute_empty ids["cut_ids"]
    assert_empty ids["packet_ids"]
  end

  def test_grok_can_own_the_same_canonical_section_slice_contract_as_codex
    shard_dir = @tmp.join("01-grok-owned-shard")
    run_cli(
      "extract",
      SOURCES["01"],
      "--section-map",
      @map,
      "--output-dir",
      shard_dir,
      "--sections",
      "S00",
      "--owner",
      "grok"
    )
    contract = load_yaml(shard_dir.join("S00.yaml"))
    assert_equal "grok", contract.dig("envelope", "owner")
    validate_stdout, = run_cli("validate", shard_dir, "--json")
    assert_equal true, JSON.parse(validate_stdout)["ok"]
  end

  def test_section_slice_omits_lyric_original_text_when_no_lyric_text_is_declared
    no_lyric_map = @tmp.join("no-lyric-section-map.yaml")
    mappings = ["S00P", "S00", "S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"].map do |visual_id|
      audio_id = visual_id == "S00P" ? "AUDIO_PRE" : "AUDIO_#{visual_id.delete_prefix('S')}"
      {"visual_section_id" => visual_id, "audio_section_id" => audio_id, "source_audio_section_ids" => [audio_id]}
    end
    no_lyric_map.write(YAML.dump("mappings" => mappings))
    shard_dir = @tmp.join("01-no-lyric-cue-shard")
    run_cli("extract", SOURCES["01"], "--section-map", no_lyric_map, "--output-dir", shard_dir, "--sections", "S00")
    shard = load_yaml(shard_dir.join("S00.yaml"))
    refute shard.dig("payload", "timing").key?("lyric_original_text")
    validate_stdout, = run_cli("validate", shard_dir, "--json")
    assert_equal true, JSON.parse(validate_stdout)["ok"]
  end

  def test_extraction_refuses_to_guess_audio_namespace
    run_cli(
      "extract",
      SOURCES["01"],
      "--output-dir",
      @tmp.join("missing-map"),
      success: false
    )
  end

  def test_merge_is_deterministic_and_refuses_canonical_overwrite
    shard_dir = @tmp.join("02a-shards")
    run_cli("extract", SOURCES["02A"], "--section-map", @map, "--output-dir", shard_dir)
    first = @tmp.join("first.yaml")
    second = @tmp.join("second.yaml")
    run_cli("merge", SOURCES["02A"], "--shards", shard_dir, "--output", first)
    run_cli("merge", SOURCES["02A"], "--shards", shard_dir, "--output", second)
    assert_equal first.read, second.read
    original_digest = Digest::SHA256.file(SOURCES["02A"].to_s).hexdigest
    run_cli("merge", SOURCES["02A"], "--shards", shard_dir, "--output", SOURCES["02A"], success: false)
    assert_equal original_digest, Digest::SHA256.file(SOURCES["02A"].to_s).hexdigest
  end

  def test_new_revision_requires_a_distinct_parent_and_validates
    shard_dir = @tmp.join("01-shards")
    run_cli("extract", SOURCES["01"], "--section-map", @map, "--output-dir", shard_dir, "--sections", "S00")
    parent = shard_dir.join("S00.yaml")
    draft = @tmp.join("S00-draft.yaml")
    document = load_yaml(parent)
    document["payload"]["section_goal"] = document["payload"]["section_goal"] + " Revision test."
    draft.write(YAML.dump(document))
    revision = @tmp.join("S00-v2.yaml")
    run_cli("seal", draft, "--parent", parent, "--output", revision, "--authored-at", "2026-07-10T00:00:00Z")
    sealed = load_yaml(revision)
    assert_equal 2, sealed.dig("envelope", "revision")
    assert_equal parent.to_s, sealed.dig("envelope", "parent", "path")
    validate_stdout, = run_cli("validate", revision, "--json")
    assert_equal true, JSON.parse(validate_stdout)["ok"]
  end
end
