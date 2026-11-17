# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "yaml"
require_relative "support/active_mv_fixture"
require_relative "../lib/idol_kinetic_slot_sheet_contract"

class IdolKineticSlotSheetProducerConsumerTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  FP_VALIDATOR = ROOT.join("scripts", "validate_front_planning_readiness.rb")
  DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_fp_and_01_clis_accept_selected_major_identity_bindings
    assert_fp_cli_success
    assert_01_cli_success
  end

  def test_isolated_producer_sibling_reaches_fp_and_01_clis
    planted = IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01")
    planted.delete
    refute planted.file?

    missing_stdout, missing_stderr, missing_status = run_cli(FP_VALIDATOR, @fixture.front_path)
    refute missing_status.success?, [missing_stderr, missing_stdout].join("\n")
    assert_includes [missing_stderr, missing_stdout].join("\n"), "kinetic slot sheet missing for MJ01"

    front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    route_id = front.dig("creative_experiment", "candidate_route_id").to_s
    route = front.fetch("candidate_routes").find { |row| row["candidate_id"].to_s == route_id }
    section = route.fetch("sections").first
    section_id = section.fetch("section_id")
    placement = section.fetch("major_scene_stack").fetch("ordered_major_placements").first
    major_id = placement.fetch("major_scene_id")
    selected_composition_id = placement.fetch("selected_sequence_composition_id")
    catalog = front.fetch("major_scene_catalog").find { |row| row["major_scene_id"].to_s == major_id }
    candidate = catalog.fetch("sequence_composition_candidate_set").fetch("candidates").find do |row|
      row["sequence_composition_id"].to_s == selected_composition_id
    end
    sequence_unit_ids = candidate.fetch("typed_sequence_unit_ids")
    plan_section = front.fetch("section_plan").find { |row| row["section_id"].to_s == section_id }
    plan_major = plan_section.fetch("major_scene_flow").find { |row| row["major_scene_id"].to_s == major_id }
    key_screens = plan_major.fetch("key_screen_anchors")
    contact = key_screens[0]
    overhead = key_screens[1]
    contact_camera = four_axis_camera(contact.fetch("still_camera_and_composition"))
    overhead_camera = four_axis_camera(overhead.fetch("still_camera_and_composition"))

    authored = {
      "schema_version" => "kinetic_change_point_slot_sheet.v1",
      "major_scene_id" => major_id,
      "section_id" => section_id,
      "automatic_creative_pass" => false,
      "sequence_evidence" => {
        "sequence_unit_ids" => sequence_unit_ids,
        "not_cut_plan" => true
      },
      "slots" => [
        {
          "slot_id" => "KSL_#{major_id}_01",
          "ordinal" => 1,
          "change_axis" => "action",
          "previous_slot_id" => nil,
          "production_binding" => "core",
          "screen_job" => "Keep M01's measured hand contact on the marker readable as the governing alignment action.",
          "visible_action_or_hold" => "M01 presses the marker from the offset sample point into registration on the guide.",
          "still_camera" => contact_camera
        },
        {
          "slot_id" => "KSL_#{major_id}_02",
          "ordinal" => 2,
          "change_axis" => "angle",
          "previous_slot_id" => "KSL_#{major_id}_01",
          "production_binding" => "core",
          "screen_job" => "Show the guide's registration geometry without another member portrait.",
          "visible_action_or_hold" => "Concentric guide lines illuminate around the registered marker on the plane.",
          "still_camera" => overhead_camera
        },
        {
          "slot_id" => "KSL_#{major_id}_03",
          "ordinal" => 3,
          "change_axis" => "authored_hold",
          "previous_slot_id" => "KSL_#{major_id}_02",
          "production_binding" => "branch",
          "screen_job" => "Hold the registered marker long enough for the luminous response to remain the afterimage.",
          "visible_action_or_hold" => "The marker stays seated while the response ring continues to read.",
          "hold_reason" => "The overhead proof needs a locked hold so the registration does not collapse back into a portrait.",
          "continuity_in" => "Enter from the overhead registration still.",
          "continuity_out" => "Leave the registered marker as the afterimage for the next Major."
        }
      ],
      "core_nail_slot_ids" => ["KSL_#{major_id}_01", "KSL_#{major_id}_02"],
      "key_screen_inheritances" => [
        {
          "key_screen_id" => contact.fetch("key_screen_id"),
          "inherits_from_slot_id" => "KSL_#{major_id}_01",
          "inherits" => "still_camera_and_action",
          "camera_reauthored" => false
        },
        {
          "key_screen_id" => overhead.fetch("key_screen_id"),
          "inherits_from_slot_id" => "KSL_#{major_id}_02",
          "inherits" => "still_camera_and_action",
          "camera_reauthored" => false
        }
      ],
      "collected_production_start_pairs" => [
        {
          "left_slot_id" => "KSL_#{major_id}_01",
          "right_slot_id" => "KSL_#{major_id}_02",
          "declared_change_axis_or_hold" => "angle",
          "same_image_exact_carry" => false
        }
      ]
    }
    planted.dirname.mkpath
    planted.write(YAML.dump(authored))
    written = planted.read
    refute_includes written, "readable event beat"
    refute_includes written, "SRUN_EVENT_A"
    refute_includes written, "KS_MJ01_A"

    fp_stdout, fp_stderr, fp_status = run_cli(FP_VALIDATOR, @fixture.front_path)
    assert fp_status.success?, [fp_stderr, fp_stdout].join("\n")
    assert_includes fp_stdout, "Front Planning v17"
    direction_stdout, direction_stderr, direction_status = run_cli(DIRECTION_VALIDATOR, @fixture.direction_path)
    assert direction_status.success?, [direction_stderr, direction_stdout].join("\n")
    refute_includes [fp_stdout, direction_stdout].join("\n"), "creative PASS"
  end

  def test_fp_close_holds_held_composition_unit_even_when_section_and_run_list_it
    path = IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01")
    sheet = YAML.safe_load(path.read, aliases: true)
    sheet["sequence_evidence"]["sequence_unit_ids"] = ["SEQU_REF_04"]
    path.write(YAML.dump(sheet))
    assert_cli_failure(FP_VALIDATOR, @fixture.front_path, "not bound to selected Sequence Composition")
    assert_cli_failure(DIRECTION_VALIDATOR, @fixture.direction_path, "not bound to selected Sequence Composition")
  end

  def test_fp_close_holds_sequence_run_id_used_as_a_sequence_unit
    path = IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01")
    sheet = YAML.safe_load(path.read, aliases: true)
    sheet["sequence_evidence"]["sequence_unit_ids"] = ["SRUN_MJ01"]
    path.write(YAML.dump(sheet))
    assert_cli_failure(FP_VALIDATOR, @fixture.front_path, "SRUN_MJ01")
    assert_cli_failure(DIRECTION_VALIDATOR, @fixture.direction_path, "SRUN_MJ01")
  end

  def test_fp_and_01_hold_unbound_key_screen_id
    path = IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01")
    sheet = YAML.safe_load(path.read, aliases: true)
    sheet["key_screen_inheritances"][0]["key_screen_id"] = "KS_MJ01_A"
    path.write(YAML.dump(sheet))
    assert_cli_failure(FP_VALIDATOR, @fixture.front_path, "Key Screen KS_MJ01_A does not resolve on that Major")
    assert_cli_failure(DIRECTION_VALIDATOR, @fixture.direction_path, "Key Screen KS_MJ01_A does not resolve on that Major")
  end

  def test_fp_close_holds_missing_selected_major_sheet
    IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01").delete
    assert_cli_failure(FP_VALIDATOR, @fixture.front_path, "kinetic slot sheet missing for MJ01")
  end

  private

  def four_axis_camera(camera)
    {
      "camera_height" => camera.fetch("camera_height"),
      "shot_scale_distance" => camera.fetch("shot_scale_distance"),
      "direction_angle" => camera.fetch("direction_angle"),
      "depth" => camera.fetch("depth")
    }
  end

  def run_cli(validator, path)
    Open3.capture3("ruby", validator.to_s, "--root", ROOT.to_s, path.to_s, chdir: ROOT.to_s)
  end

  def assert_fp_cli_success
    stdout, stderr, status = run_cli(FP_VALIDATOR, @fixture.front_path)
    assert status.success?, [stderr, stdout].join("\n")
    assert_includes stdout, "Front Planning v17"
  end

  def assert_01_cli_success
    stdout, stderr, status = run_cli(DIRECTION_VALIDATOR, @fixture.direction_path)
    assert status.success?, [stderr, stdout].join("\n")
  end

  def assert_cli_failure(validator, path, fragment)
    stdout, stderr, status = run_cli(validator, path)
    refute status.success?, [stderr, stdout].join("\n")
    assert_includes [stderr, stdout].join("\n"), fragment
  end
end
