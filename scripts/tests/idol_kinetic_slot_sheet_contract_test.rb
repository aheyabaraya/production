# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_kinetic_slot_sheet_contract"

class IdolKineticSlotSheetContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCHEMA = ROOT.join("schemas", "kinetic-change-point-slot-sheet.schema.json")
  CLI = ROOT.join("scripts", "idol_validate_kinetic_slot_sheet.rb")
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = ROOT.join("scripts", "idol-video-python")

  def sheet(overrides = {})
    {
      "schema_version" => "kinetic_change_point_slot_sheet.v1",
      "major_scene_id" => "MJ01",
      "section_id" => "S01",
      "automatic_creative_pass" => false,
      "sequence_evidence" => {
        "sequence_unit_ids" => ["SRUN_EVENT_A"],
        "not_cut_plan" => true
      },
      "slots" => [
        slot("KSL_MJ01_01", 1, "action", nil, "core"),
        slot("KSL_MJ01_02", 2, "angle", "KSL_MJ01_01", "core"),
        slot("KSL_MJ01_03", 3, "authored_hold", "KSL_MJ01_02", "branch", hold: true)
      ],
      "core_nail_slot_ids" => %w[KSL_MJ01_01 KSL_MJ01_02],
      "key_screen_inheritances" => [
        inheritance("KS_S01_A", "KSL_MJ01_01"),
        inheritance("KS_S01_B", "KSL_MJ01_02")
      ],
      "collected_production_start_pairs" => [
        pair("KSL_MJ01_01", "KSL_MJ01_02", "angle")
      ]
    }.merge(overrides)
  end

  def slot(id, ordinal, axis, previous, binding, hold: false)
    row = {
      "slot_id" => id,
      "ordinal" => ordinal,
      "change_axis" => axis,
      "previous_slot_id" => previous,
      "production_binding" => binding,
      "screen_job" => "readable event beat",
      "visible_action_or_hold" => "the subject continues the same event"
    }
    if binding == "core"
      row["still_camera"] = {
        "camera_height" => ordinal == 1 ? "eye" : "high",
        "shot_scale_distance" => "MS",
        "direction_angle" => ordinal == 1 ? "front" : "profile",
        "depth" => "subject in middle ground"
      }
    end
    if hold
      row["hold_reason"] = "locked-angle continuation of the same event"
      row["continuity_in"] = "enters from the prior angle change"
      row["continuity_out"] = "hands the same body line to the next Major"
    end
    row
  end

  def inheritance(key_screen_id, slot_id)
    {
      "key_screen_id" => key_screen_id,
      "inherits_from_slot_id" => slot_id,
      "inherits" => "still_camera_and_action",
      "camera_reauthored" => false
    }
  end

  def pair(left, right, axis)
    {
      "left_slot_id" => left,
      "right_slot_id" => right,
      "declared_change_axis_or_hold" => axis,
      "same_image_exact_carry" => false
    }
  end

  def test_complete_sheet_closes
    assert_empty IdolKineticSlotSheetContract.validate(sheet)
    assert IdolKineticSlotSheetContract.closeable?(sheet)
  end

  def test_schema_accepts_complete_sheet
    Dir.mktmpdir("kinetic-slot-") do |directory|
      path = Pathname.new(directory).join("sheet.json")
      path.write(JSON.pretty_generate(sheet))
      _stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, path.to_s)
      assert status.success?, stderr
    end
  end

  def test_coverage_errors_require_a_sheet_per_selected_major
    Dir.mktmpdir("kinetic-coverage-") do |directory|
      front = Pathname.new(directory).join("front-planning.yaml")
      front.write("status: director_closed\n")
      mj01 = IdolKineticSlotSheetContract.sheet_path_for(front, "MJ01")
      mj01.dirname.mkpath
      mj01.write(YAML.dump(sheet))
      errors = IdolKineticSlotSheetContract.coverage_errors(front, %w[MJ01 MJ02])
      assert_includes errors, "kinetic slot sheet missing for MJ02"
      refute_includes errors, "kinetic slot sheet missing for MJ01"
    end
  end

  def test_empty_slots_is_not_a_close
    errors = IdolKineticSlotSheetContract.validate(sheet("slots" => []))
    assert_includes errors, "kinetic slot sheet slots is empty"
  end

  def test_neighbor_same_axis_without_hold_is_not_a_close
    broken = sheet
    broken["slots"][1]["change_axis"] = "action"
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert errors.any? { |error| error.include?("different change_axis") }
  end

  def test_authored_hold_without_continuity_is_not_a_close
    broken = sheet
    broken["slots"][2].delete("continuity_out")
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert_includes errors, "kinetic slot sheet KSL_MJ01_03 continuity_out is empty"
  end

  def test_three_cores_is_not_a_close
    broken = sheet
    broken["slots"][2]["production_binding"] = "core"
    broken["slots"][2]["still_camera"] = {
      "camera_height" => "hip",
      "shot_scale_distance" => "CU",
      "direction_angle" => "back",
      "depth" => "foreground"
    }
    broken["core_nail_slot_ids"] = %w[KSL_MJ01_01 KSL_MJ01_02 KSL_MJ01_03]
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert_includes errors, "kinetic slot sheet core_nail_slot_ids must contain 1 or 2 ids"
  end

  def test_core_without_four_axis_camera_is_not_a_close
    broken = sheet
    broken["slots"][0].delete("still_camera")
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert_includes errors, "kinetic slot sheet KSL_MJ01_01 still_camera is missing"
  end

  def test_missing_key_screen_inheritance_is_not_a_close
    broken = sheet
    broken["key_screen_inheritances"] = [inheritance("KS_S01_A", "KSL_MJ01_01")]
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert_includes errors, "kinetic slot sheet Core-bound slot missing Key Screen inheritance: KSL_MJ01_02"
  end

  def test_key_screen_camera_reauthor_is_not_a_close
    broken = sheet
    broken["key_screen_inheritances"][0]["camera_reauthored"] = true
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert_includes errors, "kinetic slot sheet Key Screen camera_reauthored must be false"
  end

  def test_missing_collected_pair_is_not_a_close
    broken = sheet("collected_production_start_pairs" => [])
    errors = IdolKineticSlotSheetContract.validate(broken)
    assert errors.any? { |error| error.include?("collected production-start pair is missing") }
  end

  def test_one_core_needs_no_collected_pair
    one = sheet
    one["slots"] = [
      slot("KSL_MJ01_01", 1, "action", nil, "core"),
      slot("KSL_MJ01_02", 2, "authored_hold", "KSL_MJ01_01", "branch", hold: true)
    ]
    one["core_nail_slot_ids"] = %w[KSL_MJ01_01]
    one["key_screen_inheritances"] = [inheritance("KS_S01_A", "KSL_MJ01_01")]
    one["collected_production_start_pairs"] = []
    assert_empty IdolKineticSlotSheetContract.validate(one)
  end

  def test_sheet_does_not_require_key_screen_or_scene_phase_fields
    payload = sheet
    refute payload.key?("key_screen_anchors")
    refute payload.key?("scene_phases")
    refute payload.dig("slots", 0)&.key?("still_camera_and_composition")
    assert_empty IdolKineticSlotSheetContract.validate(payload)
  end

  def test_cli_passes_complete_sheet
    Dir.mktmpdir("kinetic-slot-cli-") do |directory|
      path = Pathname.new(directory).join("sheet.yaml")
      path.write(YAML.dump(sheet))
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, CLI.to_s, path.to_s)
      assert status.success?, stderr
      assert_includes stdout, "kinetic-slot-sheet: pass"
    end
  end

  def test_graph_p3_and_fp_close_load_camera_vocabulary
    graph = YAML.safe_load(ROOT.join("automation", "graph-skill-load-profiles.yaml").read, aliases: true)
    harness = YAML.safe_load(ROOT.join("automation", "harness-skill-load-profiles.yaml").read, aliases: true)
    p3 = graph.fetch("profiles").find { |row| row["profile_id"] == "planning_cdd_p3_ci" }
    p3_close = p3.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "p3_section_kinetic_architecture" }
    p1 = graph.fetch("profiles").find { |row| row["profile_id"] == "planning_cdd_p1" }
    p1_close = p1.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "p1_g40_integration_handoff" }
    overall = graph.fetch("profiles").find { |row| row["profile_id"] == "overall_director" }
    g40 = overall.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "g40_planning_cell_handoff" }
    assert_includes p3.fetch("required_read_ids"), "mv_camera_module"
    assert_includes p3_close.fetch("required_read_ids"), "mv_camera_module"
    refute_includes Array(p1_close["required_read_ids"]), "mv_camera_module"
    refute_includes Array(g40["required_read_ids"]), "mv_camera_module"

    fp = harness.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
    close = fp.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "fp_close_shard" }
    cdd = harness.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
    alignment = cdd.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "cdd_direction_alignment" }
    assert_includes close.fetch("required_read_ids"), "mv_camera_module"
    assert_includes close.fetch("required_read_ids"), "fp_operating_contract"
    refute_includes Array(alignment["required_read_ids"]), "mv_camera_module"
    projection = YAML.safe_load(ROOT.join("automation", "harness-role-context-projection.yaml").read, aliases: true)
    fp_op = Array(projection["rules"]).find { |row| row["binding_id"] == "fp_operating_contract" }
    assert_includes Array(fp_op["headings"]), "Studio Roles And Evidence Lifecycle"
    contract = ROOT.join("skills", "idol-front-planning-director", "references", "director-operating-contract.md").read
    start = contract.index("## Studio Roles And Evidence Lifecycle")
    stop = contract.index("## Department Dispatch v8 And Return Lifecycle")
    refute_nil start
    refute_nil stop
    lifecycle = contract[start...stop]
    assert_includes lifecycle, "### FP Close Sibling Outputs"
    assert_includes lifecycle, "storyline_density_locator.v1"
    assert_includes lifecycle, "kinetic_change_point_slot_sheet.v1"
    assert_includes lifecycle, "ruby scripts/idol_validate_kinetic_slot_sheet.rb <fp-stem>.kinetic-slots/<MJxx>.yaml"
  end

  def test_selected_route_join_accepts_selected_composition_units_and_major_key_screens
    Dir.mktmpdir("kinetic-join-pass-") do |directory|
      front = Pathname.new(directory).join("front-planning.yaml")
      document = selected_major_identity_document
      front.write(YAML.dump(document))
      bound = sheet(
        "sequence_evidence" => {
          "sequence_unit_ids" => ["SEQU_REF_01"],
          "not_cut_plan" => true
        },
        "key_screen_inheritances" => [
          inheritance("KS_S01_CONTACT", "KSL_MJ01_01"),
          inheritance("KS_S01_OVERHEAD", "KSL_MJ01_02")
        ]
      )
      path = IdolKineticSlotSheetContract.sheet_path_for(front, "MJ01")
      path.dirname.mkpath
      path.write(YAML.dump(bound))
      errors = IdolKineticSlotSheetContract.coverage_errors(
        front,
        %w[MJ01],
        document: document,
        selected_route: document.fetch("candidate_routes").first
      )
      assert_empty errors
    end
  end

  def test_selected_route_join_rejects_held_composition_or_section_floor_or_run_ids
    Dir.mktmpdir("kinetic-join-hold-") do |directory|
      front = Pathname.new(directory).join("front-planning.yaml")
      document = selected_major_identity_document
      front.write(YAML.dump(document))
      path = IdolKineticSlotSheetContract.sheet_path_for(front, "MJ01")
      path.dirname.mkpath
      route = document.fetch("candidate_routes").first

      {
        ["SEQU_REF_04"] => "SEQU_REF_04",
        ["SRUN_MJ01"] => "SRUN_MJ01",
        ["SEQU_REF_01", "SEQU_REF_04"] => "SEQU_REF_04"
      }.each do |unit_ids, fragment|
        bound = sheet(
          "sequence_evidence" => {
            "sequence_unit_ids" => unit_ids,
            "not_cut_plan" => true
          },
          "key_screen_inheritances" => [
            inheritance("KS_S01_CONTACT", "KSL_MJ01_01"),
            inheritance("KS_S01_OVERHEAD", "KSL_MJ01_02")
          ]
        )
        path.write(YAML.dump(bound))
        errors = IdolKineticSlotSheetContract.coverage_errors(
          front,
          %w[MJ01],
          document: document,
          selected_route: route
        )
        assert errors.any? { |error| error.include?(fragment) }, errors.join("\n")
        assert errors.any? { |error| error.include?("selected Sequence Composition") }, errors.join("\n")
      end
    end
  end

  def test_selected_route_join_rejects_unbound_key_screen_and_section_ids
    Dir.mktmpdir("kinetic-join-ks-") do |directory|
      front = Pathname.new(directory).join("front-planning.yaml")
      document = selected_major_identity_document
      front.write(YAML.dump(document))
      path = IdolKineticSlotSheetContract.sheet_path_for(front, "MJ01")
      path.dirname.mkpath
      route = document.fetch("candidate_routes").first
      unbound_key = sheet(
        "sequence_evidence" => {
          "sequence_unit_ids" => ["SEQU_REF_01"],
          "not_cut_plan" => true
        },
        "key_screen_inheritances" => [
          inheritance("KS_MJ01_A", "KSL_MJ01_01"),
          inheritance("KS_S01_OVERHEAD", "KSL_MJ01_02")
        ]
      )
      path.write(YAML.dump(unbound_key))
      errors = IdolKineticSlotSheetContract.coverage_errors(
        front,
        %w[MJ01],
        document: document,
        selected_route: route
      )
      assert_includes errors, "kinetic slot sheet MJ01 Key Screen KS_MJ01_A does not resolve on that Major"

      wrong_section = sheet(
        "section_id" => "S02",
        "sequence_evidence" => {
          "sequence_unit_ids" => ["SEQU_REF_01"],
          "not_cut_plan" => true
        },
        "key_screen_inheritances" => [
          inheritance("KS_S01_CONTACT", "KSL_MJ01_01"),
          inheritance("KS_S01_OVERHEAD", "KSL_MJ01_02")
        ]
      )
      path.write(YAML.dump(wrong_section))
      errors = IdolKineticSlotSheetContract.coverage_errors(
        front,
        %w[MJ01],
        document: document,
        selected_route: route
      )
      assert_includes errors, "kinetic slot sheet MJ01 section_id differs from selected route S01"
    end
  end

  def selected_major_identity_document
    {
      "major_scene_catalog" => [{
        "major_scene_id" => "MJ01",
        "section_id" => "S01",
        "sequence_composition_candidate_set" => {
          "candidate_set_id" => "SCSET_MJ01",
          "selected_sequence_composition_id" => "SCOMP_MJ01_01",
          "candidates" => [
            {
              "sequence_composition_id" => "SCOMP_MJ01_01",
              "typed_sequence_unit_ids" => ["SEQU_REF_01"],
              "disposition" => "selected"
            },
            {
              "sequence_composition_id" => "SCOMP_MJ01_02",
              "typed_sequence_unit_ids" => ["SEQU_REF_04"],
              "disposition" => "held"
            }
          ]
        }
      }],
      "section_plan" => [{
        "section_id" => "S01",
        "sequence_unit_ids" => %w[SEQU_REF_01 SEQU_REF_04],
        "major_scene_flow" => [{
          "major_scene_id" => "MJ01",
          "key_screen_anchors" => [
            {"key_screen_id" => "KS_S01_CONTACT"},
            {"key_screen_id" => "KS_S01_OVERHEAD"}
          ]
        }]
      }],
      "candidate_routes" => [{
        "candidate_id" => "FP-A",
        "sections" => [{
          "section_id" => "S01",
          "major_scene_stack" => {
            "ordered_major_placements" => [{
              "major_scene_id" => "MJ01",
              "sequence_composition_candidate_set_id" => "SCSET_MJ01",
              "selected_sequence_composition_id" => "SCOMP_MJ01_01"
            }]
          },
          "route_major_expansions" => [{
            "major_scene_id" => "MJ01",
            "section_id" => "S01",
            "sequence_run_ids" => ["SRUN_MJ01"]
          }]
        }]
      }]
    }
  end
end
