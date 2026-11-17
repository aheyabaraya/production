# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class ValidateEditFinishingFxTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_edit_finishing_fx.rb")
  STATE_CHECK = ROOT.join("scripts", "idol_harness_state_check.rb")
  RUN_ROOT = "runs/aurora-m/fx-test/FX_TEST_001"
  EDIT_MAP_PATH = "#{RUN_ROOT}/04-edit-map.yaml"
  RECIPE_PATH = "#{RUN_ROOT}/generations/video/qc/sync-workbench-v1/final-recipe-v1.yaml"
  MARKER_PATH = "#{RUN_ROOT}/generations/video/qc/edit-marker-plan-v3.yaml"
  AUDIO_PATH = "#{RUN_ROOT}/audio/selected/master.wav"
  AUDIO_MOTION_PATH = "#{RUN_ROOT}/research/audio-motion-director-map-v1.yaml"
  PREVIEW_PATH = "#{RUN_ROOT}/generations/video/qc/previews/S00-S01-preview-v1.mp4"
  ARTIFACT_PATH = "#{RUN_ROOT}/generations/video/qc/finishing-fx-v1/04FX-finishing-map-v1.yaml"
  FX_PREVIEW_PATH = "#{RUN_ROOT}/generations/video/qc/finishing-fx-v1/FX_S00_LIGHT_CARRY-preview-v1.mp4"
  FX_CONTACT_SHEET_PATH = "#{RUN_ROOT}/generations/video/qc/finishing-fx-v1/FX_S00_LIGHT_CARRY-contact-sheet-v1.png"
  OTHER_RUN_ROOT = "runs/aurora-m/fx-test/FX_OTHER_001"
  OTHER_RECIPE_PATH = "#{OTHER_RUN_ROOT}/generations/video/qc/sync-workbench-v1/final-recipe-v1.yaml"
  OTHER_PREVIEW_PATH = "#{OTHER_RUN_ROOT}/generations/video/qc/previews/S00-S01-preview-v1.mp4"

  def screen_progression_node(slot, section_id)
    {
      "screen_progression_map_id" => "SPM_FX_TEST_001",
      "screen_progression_node_id" => "SPN_#{slot}",
      "section_id" => section_id,
      "major_scene_id" => section_id == "S00" ? "MJ00" : "MJ01",
      "core_cut_id" => section_id == "S00" ? "C00" : "C01",
      "branch_cut_ids" => ["BC#{section_id}_#{slot}"],
      "source_03v_cue_ids" => ["03VCUE_#{section_id}_#{slot}"],
      "storyline_role" => section_id == "S00" ? "seed" : "resolve",
      "observable_screen_proof" => "The fixture preserves the reviewed #{section_id} screen state."
    }
  end

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-edit-finishing-fx-", "/private/tmp"))
    write_file(
      "#{RUN_ROOT}/run-manifest.yaml",
      YAML.dump(
        "schema_version" => "idol-run-manifest.v1",
        "status" => "active",
        "album_key" => "aurora-m",
        "title_key" => "fx-test",
        "run_id" => "FX_TEST_001",
        "content_id" => "FX_TEST_001",
        "canonical_run_root" => RUN_ROOT,
        "artifact_revision_owner" => "git",
        "compatibility_authoring" => "forbidden"
      )
    )
    write_file(AUDIO_PATH, "selected audio bytes\n")
    write_file(
      AUDIO_MOTION_PATH,
      YAML.dump("schema_version" => "idol_audio_motion_director_map.v1", "content_id" => "FX_TEST_001")
    )
    write_file(
      RECIPE_PATH,
      YAML.dump(
        "schema_version" => "idol_edit_recipe.v3",
        "content_id" => "FX_TEST_001",
        "audio_path" => AUDIO_PATH,
        "render_spec" => {"fps" => {"numerator" => 24, "denominator" => 1}},
        "timeline" => [
          {
            "segment_id" => "SEG_R03",
            "slot" => "R03",
            "marker_slot_ref" => "R03",
            "screen_progression_node" => screen_progression_node("R03", "S00"),
            "section_ids" => ["S00"],
            "output_in_frame" => 0,
            "output_out_frame" => 302
          },
          {
            "segment_id" => "SEG_R04",
            "slot" => "R04",
            "marker_slot_ref" => "R04",
            "screen_progression_node" => screen_progression_node("R04", "S01"),
            "section_ids" => ["S01"],
            "output_in_frame" => 302,
            "output_out_frame" => 600
          }
        ],
        "cuts" => [{"cut_id" => "R03"}, {"cut_id" => "R04"}]
      )
    )
    write_file(
      MARKER_PATH,
      YAML.dump(
        "schema_version" => "idol_edit_marker_plan.v6",
        "content_id" => "FX_TEST_001",
        "source_recipe" => RECIPE_PATH,
        "source_audio" => AUDIO_PATH,
        "source_audio_motion_director_map" => {
          "path" => AUDIO_MOTION_PATH,
          "sha256" => sha256(AUDIO_MOTION_PATH)
        },
        "timeline_slots" => [
          {
            "slot" => "R03",
            "section_id" => "S00",
            "source_lineage" => {
              "screen_progression_node" => screen_progression_node("R03", "S00")
            }
          },
          {
            "slot" => "R04",
            "section_id" => "S01",
            "source_lineage" => {
              "screen_progression_node" => screen_progression_node("R04", "S01")
            }
          }
        ]
      )
    )
    write_file(
      EDIT_MAP_PATH,
      YAML.dump(
        "schema_version" => "idol_edit_map.v4",
        "content_id" => "FX_TEST_001",
        "recipe_qc_contract" => {"current_final_recipe" => RECIPE_PATH},
        "manual_adjustment_workflow" => {"current_final_recipe" => RECIPE_PATH},
        "edit_marker_plan_ref" => {
          "schema" => "idol_edit_marker_plan.v6",
          "path" => MARKER_PATH,
          "sha256" => sha256(MARKER_PATH),
          "status" => "recipe_ready",
          "source_recipe" => RECIPE_PATH
        },
        "audio_marker_handoff" => {
          "source_audio" => AUDIO_PATH,
          "audio_motion_director_map" => {
            "path" => AUDIO_MOTION_PATH,
            "sha256" => sha256(AUDIO_MOTION_PATH)
          },
          "main_grid_bpm" => 120,
          "strong_onsets_seconds" => []
        },
        "screen_progression_projection" => {
          "source_path" => MARKER_PATH,
          "source_json_pointer" => "/screen_progression_projection/projected_value",
          "source_value_sha256" => "2" * 64,
          "projected_value" => {"screen_progression_map_id" => "SPM_FX_TEST_001"},
          "projection_rule" => "exact_copy_no_paraphrase_or_default"
        },
        "edit_unit_screen_progression_nodes" => [
          screen_progression_node("R03", "S00").merge("edit_unit_id" => "SEG_R03"),
          screen_progression_node("R04", "S01").merge("edit_unit_id" => "SEG_R04")
        ]
      )
    )
    write_file(PREVIEW_PATH, "passed preview bytes\n")
    write_file(FX_PREVIEW_PATH, "passed FX preview bytes\n")
    write_file(FX_CONTACT_SHEET_PATH, "passed FX contact sheet bytes\n")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def test_v3_recipe_and_passed_preview_digest_lock_passes
    result = validate(valid_document)
    assert result[:status].success?, result[:stderr]
    assert_includes result[:stdout], "recipe/preview dependency lock valid"
    assert_includes result[:stdout], "no pass inferred"
  end

  def test_recipe_tamper_is_reported_as_stale
    document = valid_document
    write_file(RECIPE_PATH, "recipe: changed after FX review\n")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_recipe_sha256 mismatch"
    assert_includes result[:stderr], "stale or was modified"
  end

  def test_passed_preview_tamper_is_reported_as_stale
    document = valid_document
    write_file(PREVIEW_PATH, "different preview bytes\n")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "passed_preview_sha256 mismatch"
    assert_includes result[:stderr], "stale or was modified"
  end

  def test_v3_binds_edit_map_marker_and_audio_or_cue_sources
    original_marker = @tmp.join(MARKER_PATH).read
    document = valid_document
    write_file(MARKER_PATH, "changed marker plan\n")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_edit_marker_plan sha256 mismatch"

    write_file(MARKER_PATH, original_marker)
    document = valid_document
    write_file(AUDIO_MOTION_PATH, "changed audio timing bytes\n")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_audio_or_cue_map sha256 mismatch"
  end

  def test_immutable_receipt_skips_only_post_render_edit_map_digest_change
    document = valid_document
    document["status"] = "passed_for_final_render"
    edit_map = YAML.safe_load(@tmp.join(EDIT_MAP_PATH).read)
    edit_map["final_closeout_inventory"] = {"status" => "ready_for_05"}
    write_file(EDIT_MAP_PATH, YAML.dump(edit_map))

    live_mode = validate(document)
    refute live_mode[:status].success?
    assert_includes live_mode[:stderr], "source_edit_map sha256 mismatch"

    receipt_mode = validate(document, immutable_receipt: true)
    assert receipt_mode[:status].success?, receipt_mode[:stderr]

    write_file(MARKER_PATH, "changed marker after render\n")
    stale_marker = validate(document, immutable_receipt: true)
    refute stale_marker[:status].success?
    assert_includes stale_marker[:stderr], "source_edit_marker_plan sha256 mismatch"
  end

  def test_passed_fx_preview_and_contact_sheet_are_same_run_hash_bound
    document = valid_document
    write_file(FX_PREVIEW_PATH, "changed FX preview bytes\n")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "preview_qc.preview sha256 mismatch"

    document = valid_document
    write_file(FX_CONTACT_SHEET_PATH, "changed FX sheet bytes\n")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "preview_qc.contact_sheet sha256 mismatch"
  end

  def test_final_render_status_requires_all_fx_records_to_pass
    document = valid_document
    document["status"] = "passed_for_final_render"
    document["fx_records"].first["status"] = "hold"
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "complete_fx_passed requires every linked FX to pass"
    assert_includes result[:stderr], "FX_S00_LIGHT_CARRY"
  end

  def test_passed_for_final_render_with_all_fx_records_passes
    document = valid_document
    document["status"] = "passed_for_final_render"

    result = validate(document)
    assert result[:status].success?, result[:stderr]
    assert_includes result[:stdout], "dependency lock valid"
  end

  def test_passed_for_final_render_requires_completed_transition_audit
    document = valid_document
    document["status"] = "passed_for_final_render"
    document.delete("transition_opportunity_audit")

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "transition_opportunity_audit"
  end

  def test_passed_for_final_render_rejects_a_chunk_preview_even_when_hash_bound
    document = valid_document
    document["status"] = "passed_for_final_render"
    document["preview_gate"]["gate_type"] = "contiguous_chunk"

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "full_master"
  end

  def test_passed_for_final_render_rejects_missing_recipe_coverage_event
    document = valid_document
    document["status"] = "passed_for_final_render"
    point = document["transition_opportunity_audit"]["points"].first
    point["coverage_event_ids"].delete("recipe_cut:R03:R04:f302")
    point["coverage_kinds"] = ["section_boundary"]
    ids = point["coverage_event_ids"]
    document["transition_opportunity_audit"]["coverage_contract"] = coverage_contract(ids, ids)

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "full_master exact coverage is missing events"
    assert_includes result[:stderr], "recipe_cut:R03:R04:f302"
  end

  def test_full_master_gate_sections_must_equal_recipe_timeline_sections
    document = valid_document
    document["status"] = "passed_for_final_render"
    document["preview_gate"]["section_ids"] = ["S00"]

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "must exactly match source_recipe timeline sections"
  end

  def test_complete_no_fx_needed_allows_empty_fx_records
    document = valid_document
    document["status"] = "passed_for_final_render"
    document["fx_records"] = []
    document["transition_opportunity_audit"] = {
      "audit_status" => "complete_no_fx_needed",
      "catalog_ref" => "skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md",
      "coverage_contract" => coverage_contract(full_master_event_ids),
      "points" => [
        {
          "point_id" => "TP_S00_S01",
          "program_time" => 12.6,
          "program_frame" => 302,
          "kind" => "section_boundary",
          "section_ids" => %w[S00 S01],
          "coverage_event_ids" => full_master_event_ids,
          "coverage_kinds" => %w[section_boundary story_handoff],
          "disposition" => "none_needed",
          "rationale" => "The body landing and hard reset already read without an effect."
        }
      ]
    }

    result = validate(document)
    assert result[:status].success?, result[:stderr]
  end


  def test_hash_bound_marker_and_audio_standalone_gates_require_exact_coverage
    write_file(
      AUDIO_MOTION_PATH,
      YAML.dump(
        "schema_version" => "idol_audio_motion_director_map.v1",
        "content_id" => "FX_TEST_001",
        "stable_audio_extracts" => {
          "signals" => [
            {"signal_type" => "onset", "time_seconds" => 1.0},
            {"signal_type" => "texture_change", "time_seconds" => 13.25},
            {"signal_type" => "vocal_entry", "time_seconds" => 20.0}
          ]
        }
      )
    )
    marker = YAML.safe_load(@tmp.join(MARKER_PATH).read)
    marker["source_audio_motion_director_map"]["sha256"] = sha256(AUDIO_MOTION_PATH)
    marker["timeline_slots"] = [
      {
        "slot" => "R04",
        "section_id" => "S01",
        "output_range" => {"start_frame" => 302},
        "nearby_markers" => {
          "strong_onsets_seconds" => [14.0],
          "feature_boundaries_seconds" => [15.0],
          "lyric_or_section_handoff" => "vocal handoff"
        }
      }
    ]
    write_file(MARKER_PATH, YAML.dump(marker))
    edit_map = YAML.safe_load(@tmp.join(EDIT_MAP_PATH).read)
    edit_map["edit_marker_plan_ref"]["sha256"] = sha256(MARKER_PATH)
    edit_map["audio_marker_handoff"]["audio_motion_director_map"]["sha256"] = sha256(AUDIO_MOTION_PATH)
    write_file(EDIT_MAP_PATH, YAML.dump(edit_map))

    document = valid_document
    document["status"] = "passed_for_final_render"
    document["source_audio_or_cue_map"] = AUDIO_MOTION_PATH
    document["dependency_lock"]["source_audio_or_cue_map_sha256"] = sha256(AUDIO_MOTION_PATH)
    document["fx_records"] = []
    groups = {
      24 => [["audio_onset:f24"], ["onset_gate"], ["S00"]],
      302 => [
        [
          "marker_lyric:R04:f302",
          "recipe_cut:R03:R04:f302",
          "recipe_section:S00>S01:f302"
        ],
        %w[section_boundary lyric_gate story_handoff],
        %w[S00 S01]
      ],
      318 => [["audio_drop:f318"], ["drop_or_release"], ["S01"]],
      336 => [["marker_onset:R04:f336"], ["onset_gate"], ["S01"]],
      360 => [["marker_drop:R04:f360"], ["drop_or_release"], ["S01"]],
      480 => [["audio_lyric:f480"], ["lyric_gate"], ["S01"]]
    }
    all_ids = groups.values.flat_map(&:first)
    document["transition_opportunity_audit"] = {
      "audit_status" => "complete_no_fx_needed",
      "catalog_ref" => "skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md",
      "coverage_contract" => coverage_contract(all_ids),
      "points" => groups.map do |frame, (event_ids, kinds, sections)|
        {
          "point_id" => format("TP_F%06d", frame),
          "program_time" => frame / 24.0,
          "program_frame" => frame,
          "kind" => kinds.first,
          "section_ids" => sections,
          "coverage_event_ids" => event_ids,
          "coverage_kinds" => kinds,
          "disposition" => "none_needed",
          "rationale" => "Full-master playback confirms no additional effect is needed at this typed event."
        }
      end
    }

    passing = validate(document)
    assert passing[:status].success?, passing[:stderr]

    document["transition_opportunity_audit"]["points"].reject! do |point|
      point["coverage_event_ids"].include?("audio_lyric:f480")
    end
    covered_ids = document["transition_opportunity_audit"]["points"].flat_map do |point|
      point["coverage_event_ids"]
    end
    document["transition_opportunity_audit"]["coverage_contract"] = coverage_contract(all_ids, covered_ids)
    failing = validate(document)
    refute failing[:status].success?
    assert_includes failing[:stderr], "full_master exact coverage is missing events: audio_lyric:f480"
  end

  def test_v2_audit_program_time_must_project_from_program_frame
    document = valid_document
    document["transition_opportunity_audit"]["points"].first["program_frame"] = 24

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "program_time is more than half a frame"
  end

  def test_audit_proposal_must_link_matching_fx_record
    document = valid_document
    document["transition_opportunity_audit"]["points"].first["fx_id_ref"] = "FX_MISSING"
    document["transition_opportunity_audit"]["points"].first["proposed_effect_type"] = "punch_zoom"

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "does not link to fx_records"
  end

  def test_final_xfade_requires_duration_preserving_handle_contract
    document = valid_document
    document["status"] = "passed_for_final_render"
    design = document["fx_records"].first["effect_design"]
    design["effect_type"] = "xfade"
    design["xfade_transition"] = "fade"
    design["from_slot"] = "R03"
    design["to_slot"] = "R04"
    document["transition_opportunity_audit"]["points"].first["proposed_effect_type"] = "xfade"

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "transition_handle_ref"
  end

  def test_registry_parameter_sources_may_not_conflict
    document = valid_document
    design = document["fx_records"].first["effect_design"]
    design["parameters"] = {"opacity" => 0.18}

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "opacity has conflicting duplicate values"
  end

  def test_metadata_only_hard_cut_note_cannot_masquerade_as_passed_fx
    document = valid_document
    design = document["fx_records"].first["effect_design"]
    design["effect_type"] = "hard_cut_note"
    document["transition_opportunity_audit"]["points"].first["proposed_effect_type"] = "hard_cut_note"

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "metadata-only records cannot pass"
  end

  def test_v2_rejects_edit_map_current_recipe_mismatch_after_rehash
    alternate_recipe = "#{RUN_ROOT}/generations/video/qc/sync-workbench-v1/final-recipe-v2.yaml"
    write_file(
      alternate_recipe,
      YAML.dump(
        "schema_version" => "fixture",
        "content_id" => "FX_TEST_001",
        "audio_path" => AUDIO_PATH,
        "cuts" => [{"cut_id" => "R03"}, {"cut_id" => "R04"}]
      )
    )
    edit_map = YAML.safe_load(@tmp.join(EDIT_MAP_PATH).read)
    edit_map["recipe_qc_contract"]["current_final_recipe"] = alternate_recipe
    write_file(EDIT_MAP_PATH, YAML.dump(edit_map))
    document = valid_document

    result = validate(document)
    refute result[:status].success?
    assert_includes(
      result[:stderr],
      "source_edit_map.recipe_qc_contract.current_final_recipe must match"
    )
  end

  def test_v2_rejects_edit_map_marker_mismatch_after_rehash
    alternate_marker = "#{RUN_ROOT}/generations/video/qc/edit-marker-plan-v4.yaml"
    write_file(
      alternate_marker,
      YAML.dump(
        "schema_version" => "fixture",
        "content_id" => "FX_TEST_001",
        "source_recipe" => RECIPE_PATH,
        "source_audio" => AUDIO_PATH,
        "source_audio_motion_director_map" => {
          "path" => AUDIO_MOTION_PATH,
          "sha256" => sha256(AUDIO_MOTION_PATH)
        }
      )
    )
    edit_map = YAML.safe_load(@tmp.join(EDIT_MAP_PATH).read)
    edit_map["edit_marker_plan_ref"]["path"] = alternate_marker
    write_file(EDIT_MAP_PATH, YAML.dump(edit_map))
    document = valid_document

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_edit_map.edit_marker_plan_ref.path must match"
  end

  def test_v2_rejects_marker_recipe_mismatch_after_rehash
    alternate_recipe = "#{RUN_ROOT}/generations/video/qc/sync-workbench-v1/final-recipe-v2.yaml"
    write_file(
      alternate_recipe,
      YAML.dump(
        "schema_version" => "fixture",
        "content_id" => "FX_TEST_001",
        "audio_path" => AUDIO_PATH,
        "cuts" => [{"cut_id" => "R03"}, {"cut_id" => "R04"}]
      )
    )
    marker = YAML.safe_load(@tmp.join(MARKER_PATH).read)
    marker["source_recipe"] = alternate_recipe
    write_file(MARKER_PATH, YAML.dump(marker))
    document = valid_document

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_edit_marker_plan.source_recipe must match"
  end

  def test_v2_rejects_recipe_audio_mismatch_after_rehash
    alternate_audio = "#{RUN_ROOT}/audio/selected/alternate-master.wav"
    write_file(alternate_audio, "alternate selected audio bytes\n")
    recipe = YAML.safe_load(@tmp.join(RECIPE_PATH).read)
    recipe["audio_path"] = alternate_audio
    write_file(RECIPE_PATH, YAML.dump(recipe))
    document = valid_document

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_edit_marker_plan.source_audio must match"
    assert_includes result[:stderr], "source_edit_map.audio_marker_handoff.source_audio must match"
  end

  def test_fx_sections_and_source_edit_segment_refs_must_match_passed_preview_and_recipe
    document = valid_document
    document["fx_records"].first["section_ids"] = ["S09"]
    document["fx_records"].first["source_edit_segment_refs"] = ["SEG_R99"]
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "outside preview_gate.section_ids"
    assert_includes result[:stderr], "source_edit_segment_ref \"SEG_R99\" is not present in source_recipe"
  end

  def test_v2_requires_an_explicit_passed_or_local_accepted_preview_status
    document = valid_document
    document["preview_gate"]["edit_preview_status"] = "timing_test"
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "must record an explicit passed/local-accepted state"
  end

  def test_v2_schema_requires_dependency_lock
    document = valid_document
    document.delete("dependency_lock")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "dependency_lock"
    assert_includes result[:stderr], "required property"
  end

  def test_v1_is_historical_evidence_only_and_cannot_validate
    document = valid_document
    document["schema_version"] = "idol_edit_finishing_fx.v1"
    document.delete("dependency_lock")
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "idol_edit_finishing_fx.v2"
  end

  def test_dependency_paths_reject_traversal
    document = valid_document
    document["source_recipe"] = "../outside-recipe.yaml"
    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "must not use . or .. traversal"
  end

  def test_recipe_from_another_run_is_rejected_even_when_readable_and_hash_matched
    write_file(OTHER_RECIPE_PATH, "other run recipe\n")
    document = valid_document
    document["source_recipe"] = OTHER_RECIPE_PATH
    document["dependency_lock"]["source_recipe_sha256"] = sha256(OTHER_RECIPE_PATH)

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_recipe points to a different run"
  end

  def test_preview_from_another_run_is_rejected_even_when_readable_and_hash_matched
    write_file(OTHER_PREVIEW_PATH, "other run preview\n")
    document = valid_document
    document["preview_gate"]["preview_path"] = OTHER_PREVIEW_PATH
    document["dependency_lock"]["passed_preview_sha256"] = sha256(OTHER_PREVIEW_PATH)

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "preview_gate.preview_path points to a different run"
  end

  def test_repo_root_file_cannot_substitute_for_a_run_owned_recipe
    document = valid_document
    document["source_recipe"] = ROOT.join("AGENTS.md").to_s
    document["dependency_lock"]["source_recipe_sha256"] = Digest::SHA256.file(
      ROOT.join("AGENTS.md").to_s
    ).hexdigest

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_recipe escapes owning run"
  end

  def test_same_run_dependencies_still_need_canonical_recipe_and_pre_fx_preview_locations
    wrong_recipe = "#{RUN_ROOT}/generations/video/qc/previews/not-a-workbench-recipe.yaml"
    write_file(wrong_recipe, "recipe in wrong folder\n")
    document = valid_document
    document["source_recipe"] = wrong_recipe
    document["dependency_lock"]["source_recipe_sha256"] = sha256(wrong_recipe)

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "source_recipe is not in an allowed run-owned location"

    fx_preview = "#{RUN_ROOT}/generations/video/qc/finishing-fx-v1/already-treated-preview.mp4"
    write_file(fx_preview, "circular FX preview\n")
    document = valid_document
    document["preview_gate"]["preview_path"] = fx_preview
    document["dependency_lock"]["passed_preview_sha256"] = sha256(fx_preview)

    result = validate(document)
    refute result[:status].success?
    assert_includes result[:stderr], "preview_gate.preview_path is not in an allowed run-owned location"
  end

  def test_harness_state_check_uses_semantic_validator_and_blocks_stale_v2
    document = valid_document

    fresh_check = state_check(document)
    assert_equal "pass", fresh_check["status"], fresh_check["details"]
    assert_equal false, fresh_check["blocking"]
    assert_includes fresh_check["command"], "scripts/validate_edit_finishing_fx.rb"

    document["dependency_lock"]["source_recipe_sha256"] = "0" * 64
    stale_check = state_check(document)
    assert_equal "fail", stale_check["status"]
    assert_equal true, stale_check["blocking"]
    assert_includes stale_check["details"], "source_recipe_sha256 mismatch"
  end

  private

  def write_file(relative_path, content)
    path = @tmp.join(relative_path)
    path.dirname.mkpath
    path.write(content)
  end

  def sha256(relative_path)
    Digest::SHA256.file(@tmp.join(relative_path).to_s).hexdigest
  end

  def valid_document
    {
      "schema_version" => "idol_edit_finishing_fx.v2",
      "content_id" => "FX_TEST_001",
      "status" => "partial_pass",
      "source_edit_map" => EDIT_MAP_PATH,
      "source_recipe" => RECIPE_PATH,
      "source_edit_marker_plan" => MARKER_PATH,
      "source_audio_or_cue_map" => AUDIO_MOTION_PATH,
      "effect_registry_ref" => "automation/edit-effect-registry.yaml",
      "dependency_lock" => {
        "digest_algorithm" => "sha256",
        "source_edit_map_sha256" => sha256(EDIT_MAP_PATH),
        "source_recipe_sha256" => sha256(RECIPE_PATH),
        "source_edit_marker_plan_sha256" => sha256(MARKER_PATH),
        "source_audio_or_cue_map_sha256" => sha256(AUDIO_MOTION_PATH),
        "passed_preview_sha256" => sha256(PREVIEW_PATH)
      },
      "preview_gate" => {
        "gate_type" => "full_master",
        "section_ids" => %w[S00 S01],
        "preview_path" => PREVIEW_PATH,
        "edit_preview_status" => "passed",
        "fx_allowed" => true,
        "gate_note" => "The recorded 04 review passed this exact preview for FX eligibility."
      },
      "track_tone_world_guard" => {
        "tone_and_manner" => "Keep the restrained blue-black track tone.",
        "world_space_preserve" => "Keep the full corridor depth and the practical light route visible.",
        "identity_body_preserve" => "Keep face, hands, feet, weight transfer, and coat motion readable.",
        "color_light_limits" => "No clipped whites, heavy bloom, or exposure pumping.",
        "repeated_effect_drift_guard" => "Use this light carry once for the section handoff."
      },
      "transition_opportunity_audit" => {
        "audit_status" => "complete_fx_passed",
        "catalog_ref" => "skills/idol-edit-finishing-fx/references/local-ffmpeg-transition-effect-catalog.md",
        "coverage_contract" => coverage_contract(full_master_event_ids),
        "points" => [
          {
            "point_id" => "TP_S00_S01",
            "program_time" => 12.6,
            "program_frame" => 302,
            "kind" => "section_boundary",
            "section_ids" => %w[S00 S01],
            "coverage_event_ids" => full_master_event_ids,
            "coverage_kinds" => %w[section_boundary story_handoff],
            "disposition" => "manual_fx_proposed",
            "proposed_effect_type" => "dip_flash",
            "fx_id_ref" => "FX_S00_LIGHT_CARRY",
            "rationale" => "The passed hard cut benefits from one restrained light dip."
          }
        ]
      },
      "fx_records" => [
        {
          "fx_id" => "FX_S00_LIGHT_CARRY",
          "section_ids" => %w[S00 S01],
          "time_range" => "12.400-12.800",
          "source_edit_segment_refs" => %w[SEG_R03 SEG_R04],
          "eligibility" => {
            "edit_preview_passed" => true,
            "edit_boundary_timing_locked" => true,
            "source_action_marker_known" => true,
            "effect_job" => "transition_bridge"
          },
          "trigger" => {
            "audio_or_section_cue" => "The snare stop at 12.600 seconds.",
            "source_action_marker" => "The coat edge clears the lens as the incoming foot plants."
          },
          "visible_basis" => "The outgoing coat edge crosses the lens from left to right.",
          "effect_design" => {
            "effect_type" => "dip_flash",
            "duration_frames" => 5,
            "program_start_seconds" => 12.4,
            "program_start_frame" => 298,
            "opacity" => 0.22,
            "direction" => "left to right",
            "intensity" => "low",
            "renderer_status" => "supported_now",
            "visible_action" => "A narrow light edge follows the coat across the cut.",
            "endpoint" => "The light disappears before the incoming face clears."
          },
          "reason_it_helps" => "It makes the coat-direction match readable without hiding the foot plant.",
          "protection_guards" => {
            "face_hand_foot_body" => "Do not cover the incoming face, hands, or planted foot.",
            "full_space_world" => "Keep corridor depth and floor reflections visible.",
            "tone_and_manner" => "Keep the restrained practical-light treatment.",
            "timing_feel" => "The light must end before the next snare pickup.",
            "mobile_readability" => "The edge remains visible but narrower than the face."
          },
          "fail_conditions" => ["Reject if it obscures the face or makes the cut feel late."],
          "preview_qc" => {
            "preview_path" => FX_PREVIEW_PATH,
            "preview_sha256" => sha256(FX_PREVIEW_PATH),
            "contact_sheet_path" => FX_CONTACT_SHEET_PATH,
            "contact_sheet_sha256" => sha256(FX_CONTACT_SHEET_PATH),
            "checks" => %w[
              timing_feel
              identity_body_preserved
              full_space_world_preserved
              tone_manner_preserved
              mobile_readable
              flicker_flash_safe
              source_quality_not_hidden
              repeated_effect_drift_checked
            ],
            "qc_note" => "The recorded preview keeps the body and corridor readable."
          },
          "status" => "pass"
        }
      ],
      "final_render_policy" => {
        "include_only_passed_fx" => true,
        "single_high_quality_render_after_fx_pass" => true,
        "timing_change_returns_to_04_edit" => true,
        "post_edit_transition_audit_required_before_final_master" => true,
        "final_qc_no_new_creative_fx_by_default" => true
      },
      "automation_boundaries" => [
        "Automation validates structure, paths, and hashes only; it does not choose effects or infer pass."
      ]
    }
  end

  def validate(document, immutable_receipt: false)
    artifact = @tmp.join(ARTIFACT_PATH)
    artifact.dirname.mkpath
    artifact.write(YAML.dump(document))
    command = [
      RbConfig.ruby,
      VALIDATOR.to_s,
      "--run-root",
      @tmp.join(RUN_ROOT).to_s
    ]
    command << "--immutable-receipt" if immutable_receipt
    command << artifact.to_s
    stdout, stderr, status = Open3.capture3(
      *command,
      chdir: ROOT.to_s
    )
    { stdout: stdout, stderr: stderr, status: status }
  end

  def full_master_event_ids
    [
      "recipe_cut:R03:R04:f302",
      "recipe_section:S00>S01:f302"
    ]
  end

  def coverage_contract(expected_ids, covered_ids = expected_ids)
    {
      "coverage_version" => "recipe_marker_audio_exact_v1",
      "coverage_scope" => "full_master",
      "digest_algorithm" => "sha256_sorted_utf8_lines_v1",
      "expected_event_count" => expected_ids.uniq.length,
      "covered_event_count" => covered_ids.uniq.length,
      "expected_event_ids_sha256" => coverage_digest(expected_ids),
      "covered_event_ids_sha256" => coverage_digest(covered_ids)
    }
  end

  def coverage_digest(event_ids)
    Digest::SHA256.hexdigest(event_ids.map(&:to_s).uniq.sort.map { |event_id| "#{event_id}\n" }.join)
  end

  def state_check(document)
    artifact = @tmp.join(ARTIFACT_PATH)
    artifact.dirname.mkpath
    artifact.write(YAML.dump(document))
    stdout, _stderr, _status = Open3.capture3(
      RbConfig.ruby,
      STATE_CHECK.to_s,
      @tmp.join(RUN_ROOT).to_s,
      "--json",
      chdir: ROOT.to_s
    )
    payload = JSON.parse(stdout)
    payload.fetch("checks").find { |check| check["id"] == "edit_finishing_fx" } ||
      flunk("edit_finishing_fx state check is missing")
  end
end
