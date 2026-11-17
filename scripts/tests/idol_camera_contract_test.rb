# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "pathname"
require_relative "../lib/idol_camera_direction_contract"

class IdolCameraContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  DIRECTION_SCHEMA = ROOT.join("schemas", "song-choreography-performance-mv-map.schema.json")
  STORYBOARD_SCHEMA = ROOT.join("schemas", "master-storyboard.schema.json")
  PACKET_DELTA_SCHEMA = ROOT.join("schemas", "prompt-packet-delta.schema.json")
  PACKET_SCHEMA = ROOT.join("schemas", "prompt-packets.schema.json")
  VIDEO_ASSIST_SCHEMA = ROOT.join("schemas", "video-prompt-storyboard-assist.schema.json")
  VIDEO_MANIFEST_SCHEMA = ROOT.join("schemas", "video-prompt-manifest.schema.json")
  MODULE = ROOT.join("skills", "idol-mv-director", "modules", "camera-coverage-vocabulary.md")

  def test_still_camera_and_temporal_camera_authority_are_stage_separated
    direction = JSON.parse(DIRECTION_SCHEMA.read)
    storyboard = JSON.parse(STORYBOARD_SCHEMA.read)
    packets = JSON.parse(PACKET_SCHEMA.read)
    video_assist = JSON.parse(VIDEO_ASSIST_SCHEMA.read)
    video_manifest = JSON.parse(VIDEO_MANIFEST_SCHEMA.read)

    %w[shot_scale_distance camera_height direction_angle depth_design subject_placement crop_negative_space temporal_camera_owner].each do |field|
      assert_includes direction.dig("$defs", "stillCameraCoverage", "required"), field
    end
    assert_equal "03V_after_passed_image_pixel_inspection",
                 direction.dig("$defs", "stillCameraCoverage", "properties", "temporal_camera_owner", "const")

    coverage = storyboard.dig("$defs", "cameraCoveragePlan")
    assert_equal true, coverage.dig("properties", "still_camera_only", "const")
    assert_equal "03V_after_passed_image_pixel_inspection",
                 coverage.dig("properties", "temporal_camera_owner", "const")

    %w[camera_height shot_scale_distance direction_angle depth_design subject_placement crop_negative_space lens_feel].each do |field|
      assert_includes packets.dig("$defs", "stillCamera", "required"), field
    end
    temporal_fields = %w[motion_camera_ownership movement_family movement_direction speed motion_envelope stop_trigger]
    assert_empty temporal_fields & packets.dig("$defs", "stillCamera", "properties").keys

    assist_motion = video_assist.dig("$defs", "cameraMotionRoute")
    manifest_motion = video_manifest.dig("$defs", "cameraMotionRoute")
    %w[start_view movement_family movement_direction speed motion_envelope depth_parallax_focus_change stop_trigger landing_state_or_reveal readability_reason].each do |field|
      assert_includes assist_motion.fetch("required"), field
    end
    %w[movement_family movement_direction speed motion_envelope depth_parallax_focus_change stop_trigger landing_state_or_reveal readability_reason].each do |field|
      assert_includes manifest_motion.fetch("required"), field
    end
    refute_includes manifest_motion.fetch("properties").keys, "start_view"
    motion_defs = [assist_motion, manifest_motion]
    assert_equal 1, motion_defs.map { |definition| definition.dig("properties", "movement_family", "enum") }.uniq.length
  end

  def test_02b_five_line_contract_and_still_camera_fields_are_unchanged
    delta = JSON.parse(PACKET_DELTA_SCHEMA.read)
    packets = JSON.parse(PACKET_SCHEMA.read)
    expected_blueprint = %w[
      authoring_owner identity_reference_rule scene_intent visible_details
      action_cue avoid
    ]
    expected_camera_fields = %w[
      camera_height shot_scale_distance direction_angle depth_design
      subject_placement crop_negative_space lens_feel
    ]
    temporal_fields = %w[
      movement_family movement_direction rig_character speed base_speed
      motion_envelope envelope exact_path reveal_timing stop_trigger
    ]

    assert_equal "1.6", delta.dig("properties", "schema_version", "const")
    assert_equal "2.6", packets.dig("properties", "schema_version", "const")
    [delta, packets].each do |schema|
      assert_equal expected_blueprint, schema.dig("$defs", "fiveLineComponents", "required")
      camera = schema.dig("$defs", "stillCamera")
      assert_equal expected_camera_fields, camera.fetch("required")
      assert_empty temporal_fields & camera.fetch("properties").keys
    end
    labels = packets.dig("$defs", "renderedFiveLines", "properties", "label_order", "prefixItems")
    assert_equal [
      "Identity reference rule", "Scene intent", "Visible details",
      "Action cue", "Avoid"
    ], labels.map { |row| row.fetch("const") }
  end

  def test_generic_camera_module_has_no_run_specific_template_leakage
    text = MODULE.read
    banned = {
      "One Move" => /one[ -]?move/i,
      "section ids" => /\bS0\d[A-Z]?\b/,
      "game-piece motif" => /\bstone\b/i,
      "board/grid motif" => /\b(?:board|grid)\b/i,
      "color-domain motif" => /\b(?:full[- ]red|red lane|domain)\b/i,
      "named transformation" => /\bbankai\b/i
    }
    banned.each do |label, pattern|
      refute_match pattern, text, "generic camera module leaked #{label}"
    end
  end

  def test_quick_selection_guide_precedes_dictionary_and_exposes_active_route
    text = MODULE.read
    quick_guide = text.index("## Quick Selection Guide")
    dictionary = text.index("## Detailed Vocabulary Dictionary")
    research = text.index("## Research Basis And Scope")

    refute_nil quick_guide
    refute_nil dictionary
    refute_nil research
    assert_operator quick_guide, :<, dictionary
    assert_operator dictionary, :<, research

    [
      "### Stage Gate And Return Route",
      "### Thirty-Second Selection Pass",
      "### Screen-Job Router",
      "### Minimum Decision Record",
      "### Fast Disambiguation Index"
    ].each { |heading| assert_includes text, heading }

    %w[
      reference_camera_composition_role section_01_core_direction
      section_02a_coverage section_02b_image section_generated_image_review
      section_03v_motion_direction
    ].each { |checkpoint| assert_includes text, checkpoint }

    assert_includes text, "camera/composition worker -> CDD"
    assert_includes text, "development worker -> CDD -> Overall -> exact Founder 02A approval"
    assert_includes text, "post-02A section worker -> CDD"
    assert_includes text, "CDD -> reviewed milestone to Overall"
    assert_match(/section_02b_image.*not loaded; use compact compile detail/, text)
    assert_match(/CDD remains active through image and 03V review/, text)
  end

  def test_movement_speed_and_envelope_names_are_orthogonal
    text = MODULE.read
    refute_match(/`M_(?:SLOW|FAST|BRISK|CREEP)/, text)
    refute_match(/`V_(?:RAMP_UP|RAMP_DOWN|PULSE)/, text)
    assert_match(/`M_PUSH \+ V_CREEP`/, text)
    assert_match(/`E_RAMP_UP`/, text)
    assert_match(/camera-decision vocabulary, not a shot template/i, text)
    assert_match(/custom current-run labels are allowed/i, text)
    assert_match(/height \+ distance\/scale \+ direction\/angle \+ depth/i, text)
    assert_match(/after pixel PASS only: 03V movement or hold \+ speed \+ envelope \+ stop/i, text)
  end

  def test_still_prompt_projection_cannot_leak_temporal_camera_codes
    spec = {
      "summary" => "H_KNEE SS_MLS using M_TRACK_LATERAL at V_BRISK",
      "camera_height" => "H_KNEE",
      "shot_scale_family" => "SS_MLS",
      "direction_angle" => "A_34",
      "depth_design" => "foreground shoulder, member midground, receding lights",
      "movement_family" => "M_TRACK_LATERAL",
      "base_speed" => "V_BRISK",
      "envelope" => "E_EASE_OUT",
      "composition_family" => "C_STACK_DEPTH",
      "lens_feel" => "L_NORMAL",
      "transition_family" => "T_MATCH_VECTOR",
      "audio_story_job" => "reveal the body route on the pickup"
    }
    prompt = IdolCameraDirectionContract.still_prompt_sentence(spec)
    %w[H_KNEE SS_MLS A_34 M_TRACK_LATERAL V_BRISK E_EASE_OUT C_STACK_DEPTH L_NORMAL T_MATCH_VECTOR].each do |token|
      refute_includes prompt, token
    end
    assert_includes prompt, "knee-height"
    assert_includes prompt, "medium-long shot"
    refute_includes prompt, "tracking move"
    refute_includes prompt, "brisk"
    refute_includes prompt, "ease-out"
  end

  def test_03v_motion_projection_translates_authored_route_without_selecting_it
    route = {
      "start_view" => "passed wide frame with three depth layers",
      "movement_family" => "track",
      "movement_direction" => "M_TRUCK_LATERAL camera-left while subject travels camera-right",
      "rig_character" => "R_GIMBAL",
      "speed" => "V_BRISK",
      "motion_envelope" => "E_EASE_OUT",
      "depth_change" => "foreground crosses faster than the subject plane",
      "reveal_target" => "the open threshold",
      "stop_trigger" => "subject reaches the right-third mark",
      "readability_reason" => "keep the hand-object contact unobscured",
      "edit_handoff" => "carry the camera-right vector"
    }
    prompt = IdolCameraDirectionContract.motion_prompt_sentence(route)
    %w[M_TRUCK_LATERAL R_GIMBAL V_BRISK E_EASE_OUT].each { |token| refute_includes prompt, token }
    assert_includes prompt, "lateral trucking move"
    assert_includes prompt, "gimbal-stabilized motion character"
    assert_includes prompt, "brisk speed"
    assert_includes prompt, "ease-out speed envelope"
    assert_includes prompt, "stop: subject reaches the right-third mark"
  end

  def test_structured_route_merges_instead_of_replacing_detailed_02a_camera_truth
    spec = {
      "camera_height" => "H_KNEE",
      "shot_scale_family" => "SS_MLS",
      "direction_angle" => "A_34",
      "depth_design" => "foreground shoulder, member midground, receding lights",
      "movement_family" => "M_TRACK_LATERAL",
      "base_speed" => "V_BRISK",
      "composition_family" => "C_STACK_DEPTH",
      "lens_feel" => "L_NORMAL",
      "audio_story_job" => "reveal the pickup"
    }
    cut = {
      "director_chain" => {"must_show" => {"camera" => ["keep the left boot on the lower-third line and land beside the doorway"]}},
      "visual_frame" => {"camera_treatment" => "preserve floor reflection and right-edge exit crop"}
    }
    local = IdolCameraDirectionContract.local_camera_realization(cut)
    merged = IdolCameraDirectionContract.merged_prompt_sentence(spec, local)

    assert_includes merged, "knee-height medium-long shot"
    assert_includes merged, "left boot on the lower-third line"
    assert_includes merged, "floor reflection and right-edge exit crop"
    assert_includes merged, "Passed still-camera basis"
    assert_includes merged, "without authoring temporal motion"
    refute_includes merged, "lateral tracking move"
  end

  def test_02a_cut_still_geometry_is_exact_copied_not_inferred
    branch = {
      "branch_cut_id" => "BC01_ACTION",
      "still_camera_spec" => {
        "camera_height" => "waist height",
        "direction_angle" => "lateral three-quarter rear view"
      }
    }
    core = {
      "core_cut_id" => "C01",
      "imported_core" => {
        "camera" => {
          "camera_height" => "marker height",
          "direction_angle" => "lateral side view"
        }
      }
    }
    assert_equal branch["still_camera_spec"], IdolCameraDirectionContract.still_camera_spec_from_02a_cut(branch)
    assert_equal core.dig("imported_core", "camera"), IdolCameraDirectionContract.still_camera_spec_from_02a_cut(core)
  end

  def test_coverage_plan_only_cut_does_not_infer_still_camera_spec
    coverage_only = {
      "branch_cut_id" => "BC01_COVERAGE",
      "camera_coverage_plan" => {
        "anchor_view" => {
          "camera_height" => "eye-level",
          "camera_angle" => "frontal angle",
          "direction_angle" => "frontal facing"
        }
      }
    }
    assert_nil IdolCameraDirectionContract.still_camera_spec_from_02a_cut(coverage_only)
    assert_nil IdolCameraDirectionContract.still_camera_spec_from_02a_cut({})
    assert_nil IdolCameraDirectionContract.still_camera_spec_from_02a_cut(nil)
  end
end
