# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_reference_role_plan_contract"

class IdolReferenceRolePlanContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path

  def setup
    @directory = Pathname.new(Dir.mktmpdir("idol-reference-role-plan-", ROOT.join("runs").to_s))
    @front_path = @directory.join("front-planning.yaml")
    @source_paths = %w[world-a.png motion-a.mp4 prop-a.png prop-b.png].map { |name| @directory.join(name) }
    @source_paths.each_with_index { |path, index| path.write("physical reference bytes #{index}\n") }
    @frame_paths = (1..5).map { |index| @directory.join("motion-frame-#{index}.png") }
    @frame_paths.each_with_index { |path, index| path.write("motion frame bytes #{index}\n") }
    @manifest_path = @directory.join("motion-sequence-manifest.yaml")
    @manifest_path.write("sequence: SEQU_ROLE_01\n")
    @units = [
      unit("REF-ROLE-WORLD", @source_paths[0], [function("RFN_WORLD", "background_and_space"), function("RFN_CAMERA", "still_camera_and_composition")]),
      unit("REF-ROLE-MOTION", @source_paths[1], [function("RFN_MOTION", "visible_action_or_hold")], sequence_unit: sequence_unit),
      unit("REF-ROLE-PROP-A", @source_paths[2], [function("RFN_PROP_A", "object_environment_response")]),
      unit("REF-ROLE-PROP-B", @source_paths[3], [function("RFN_PROP_B", "subject_state_or_pose")])
    ]
    @front_path.write(YAML.dump(
      "schema_version" => "front-planning-readiness.v17",
      "reference_connection_research" => {"reference_units" => @units}
    ))
    @attachments = [
      attachment(1, "WORLD", @source_paths[0]),
      attachment(2, "MOTION", @source_paths[1]),
      attachment(3, "PROP_A", @source_paths[2]),
      attachment(4, "PROP_B", @source_paths[3])
    ]
    @plan = valid_plan
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory&.directory?
  end

  def test_valid_four_role_plan_exact_covers_two_prop_attachments
    result = verify
    assert_same @plan, result
  end

  def test_material_prop_rejects_attachment_without_function_lineage
    prop.fetch("prop_function_lineage").pop

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }

    assert_includes error.message, "attachments must each carry exact function lineage"
  end

  def test_material_prop_rejects_duplicate_function_lineage_row
    prop.fetch("prop_function_lineage") << Marshal.load(Marshal.dump(prop.fetch("prop_function_lineage").first))

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }

    assert_includes error.message, "function lineage rows must be unique"
  end

  def test_rejects_front_planning_unit_bound_to_unrelated_attachment_bytes
    @units.first["source_path"] = @source_paths[1].relative_path_from(ROOT).to_s
    @units.first["source_sha256"] = Digest::SHA256.file(@source_paths[1]).hexdigest
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "does not exact-bind the physical attachment"
  end

  def test_rejects_reference_unit_outside_current_section
    @units.first["target_section_ids"] = ["S02"]
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "outside the current section"
  end

  def test_motion_lineage_must_cover_every_motion_attachment
    motion["attachment_binding_ids"] << "PROP_A"

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "motion_reference attachments must each carry exact function lineage"
  end

  def test_rejects_identical_attachment_bytes_even_when_paths_differ
    duplicate_path = @directory.join("duplicate-prop-copy.png")
    duplicate_path.write(@source_paths[2].read)
    @attachments << attachment(5, "PROP_A_COPY", duplicate_path)

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "identical attachment bytes must be registered once even when paths differ"
  end

  def test_motion_requires_exactly_five_samples
    motion["sample_count"] = 6

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "exactly five contiguous one-second samples"
  end

  def test_motion_source_must_be_video_or_selected_range
    motion_lineage["source_media_type"] = "image"

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "source_media_type must be video or video_selected_range"
  end

  def test_motion_requires_exact_sequence_unit_pointer
    motion_lineage["sequence_unit_json_pointer"] = "/reference_connection_research/reference_units/0/sequence_unit"

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "must name the Sequence Unit inside its referenced Front Planning unit"
  end

  def test_motion_rejects_stale_sequence_unit_value_hash
    motion_lineage["sequence_unit_value_sha256"] = "0" * 64

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "sequence_unit_value_sha256 is stale"
  end

  def test_motion_rejects_nonconsecutive_one_second_timestamps
    @units[1].fetch("sequence_unit").fetch("ordered_frames")[3]["timestamp_seconds"] = 13.5
    @units[1].fetch("sequence_unit").fetch("frame_observations")[3]["timestamp_seconds"] = 13.5
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "timestamps must advance at exact one-second cadence"
  end

  def test_motion_rejects_missing_fifth_frame
    @units[1].fetch("sequence_unit").fetch("ordered_frames").pop
    @units[1].fetch("sequence_unit").fetch("frame_observations").pop
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "must contain exactly five frames"
  end

  def test_motion_rejects_stale_frame_sha
    @units[1].fetch("sequence_unit").fetch("ordered_frames")[2].fetch("artifact")["sha256"] = "0" * 64
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "frame 3 SHA-256 is stale"
  end

  def test_motion_rejects_missing_frame_file
    @units[1].fetch("sequence_unit").fetch("ordered_frames")[2].fetch("artifact")["path"] = @directory.join("missing-frame.png").relative_path_from(ROOT).to_s
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "frame 3 path is missing"
  end

  def test_motion_rejects_duplicate_source_frame_id
    frames = @units[1].fetch("sequence_unit").fetch("ordered_frames")
    frames[3]["source_frame_or_cell_id"] = frames[2].fetch("source_frame_or_cell_id")
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "source frame ids must be unique"
  end

  def test_motion_rejects_observations_not_aligned_to_frames
    @units[1].fetch("sequence_unit").fetch("frame_observations")[2]["timestamp_seconds"] = 12.25
    refresh_front_and_lineage_hashes

    error = assert_raises(IdolReferenceRolePlanContract::ContractError) { verify }
    assert_includes error.message, "observations must align to the five ordered frames"
  end

  def test_reference_role_schema_definitions_remain_in_parity
    schemas = %w[
      schemas/prompt-packets.schema.json
      schemas/prompt-packet-delta.schema.json
      schemas/image-generation-request.schema.json
    ].map { |path| JSON.parse(ROOT.join(path).read).fetch("$defs") }

    assert schemas.drop(1).all? { |defs| defs.fetch("referenceFunctionLineage") == schemas.first.fetch("referenceFunctionLineage") }
    assert schemas.drop(1).all? { |defs| defs.fetch("referenceRoleGroup") == schemas.first.fetch("referenceRoleGroup") }
  end

  private

  def verify
    IdolReferenceRolePlanContract.verify!(
      plan: @plan,
      attachments: @attachments,
      member_visual_applicability: "not_visible",
      current_section_id: "S01",
      root: ROOT,
      label: "fixture.reference_role_plan"
    )
  end

  def function(id, purpose)
    {"function_id" => id, "purpose" => purpose, "screen_consequence" => "fixture #{purpose}"}
  end

  def unit(id, path, functions, sequence_unit: nil)
    row = {
      "reference_unit_id" => id,
      "source_path" => path.relative_path_from(ROOT).to_s,
      "source_sha256" => Digest::SHA256.file(path).hexdigest,
      "target_section_ids" => ["S01"],
      "disposition" => "combined",
      "function_analysis" => functions
    }
    row["sequence_unit"] = sequence_unit if sequence_unit
    row
  end

  def sequence_unit
    timestamps = (10..14).to_a
    {
      "sequence_unit_id" => "SEQU_ROLE_01",
      "sequence_run_id" => "SRUN_ROLE_01",
      "event_identity" => "One contiguous fixture event.",
      "frame_selection_mode" => "fixed_cadence",
      "declared_cadence_seconds" => 1,
      "ordered_frames" => @frame_paths.each_with_index.map do |path, index|
        {
          "order_index" => index + 1,
          "timestamp_seconds" => timestamps.fetch(index),
          "source_frame_or_cell_id" => "FRAME_#{index + 1}",
          "artifact" => {
            "path" => path.relative_path_from(ROOT).to_s,
            "sha256" => Digest::SHA256.file(path).hexdigest
          }
        }
      end,
      "flow_reading" => {
        "entry_state" => "entry",
        "trigger" => "trigger",
        "visible_transformation" => "change",
        "peak_or_reveal" => "peak",
        "exit_state" => "exit",
        "camera_composition_depth_progression" => "camera progression",
        "continuity_to_next" => "continuity",
        "direct_observation_vs_inference" => "direct observation",
        "storyline_transfer_and_exclusion" => "bounded transfer",
        "authorship_owner" => "assigned_model"
      },
      "frame_observations" => timestamps.each_with_index.map do |timestamp, index|
        {
          "order_index" => index + 1,
          "timestamp_seconds" => timestamp,
          "subject_body_object_space" => "state #{index + 1}",
          "delta_from_previous" => "delta #{index + 1}",
          "camera_composition_depth" => "camera #{index + 1}",
          "storyline_function" => "story #{index + 1}",
          "uncertainty" => "none"
        }
      end,
      "manifest" => {
        "path" => @manifest_path.relative_path_from(ROOT).to_s,
        "sha256" => Digest::SHA256.file(@manifest_path).hexdigest
      },
      "major_reference_eligible" => true,
      "downstream_cut_count_rule" => "five_source_frames_never_imply_five_core_or_branch_cuts"
    }
  end

  def attachment(order, binding_id, path)
    {
      "order" => order,
      "role" => "supporting_component_reference",
      "binding_id" => binding_id,
      "actual_path" => path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def valid_plan
    {
      "authoring_owner" => "human_or_assigned_model",
      "scene_character_compile_mode" => "separate",
      "performance_mode" => "none",
      "attachment_order_binding_ids" => %w[WORLD MOTION PROP_A PROP_B],
      "logical_role_groups" => [
        {"logical_role" => "character_visual", "applicability" => "not_applicable_member_absent", "attachment_binding_ids" => []},
        {
          "logical_role" => "scene_visual_package",
          "applicability" => "required",
          "attachment_binding_ids" => ["WORLD"],
          "world_look_binding_ids" => ["WORLD"],
          "composition_anchor_binding_id" => "WORLD",
          "world_look_function_lineage" => [lineage("WORLD", 0, 0, "image")],
          "composition_anchor_function_lineage" => lineage("WORLD", 0, 1, "image")
        },
        {
          "logical_role" => "motion_reference",
          "applicability" => "required",
          "attachment_binding_ids" => ["MOTION"],
          "sequence_unit_id" => "SEQU_ROLE_01",
          "source_locator" => "fixture frames 01-05",
          "sampling_interval_seconds" => 1,
          "sample_count" => 5,
          "contiguous_event" => "One contiguous fixture event.",
          "motion_function_lineage" => [lineage("MOTION", 1, 0, "video_selected_range", sequence_unit: true)]
        },
        {
          "logical_role" => "prop_reference",
          "applicability" => "required",
          "attachment_binding_ids" => %w[PROP_A PROP_B],
          "prop_function_lineage" => [
            lineage("PROP_A", 2, 0, "image_selected_crop"),
            lineage("PROP_B", 3, 0, "image_selected_crop")
          ]
        }
      ]
    }
  end

  def prop
    @plan.fetch("logical_role_groups").find { |row| row["logical_role"] == "prop_reference" }
  end


  def motion
    @plan.fetch("logical_role_groups").find { |row| row["logical_role"] == "motion_reference" }
  end

  def motion_lineage
    motion.fetch("motion_function_lineage").first
  end

  def lineage(binding_id, unit_index, function_index, media_type, sequence_unit: false)
    unit_row = @units.fetch(unit_index)
    function_row = unit_row.fetch("function_analysis").fetch(function_index)
    unit_pointer = "/reference_connection_research/reference_units/#{unit_index}"
    row = {
      "attachment_binding_id" => binding_id,
      "reference_unit_id" => unit_row.fetch("reference_unit_id"),
      "function_id" => function_row.fetch("function_id"),
      "purpose" => function_row.fetch("purpose"),
      "disposition" => unit_row.fetch("disposition"),
      "source_media_type" => media_type,
      "source_artifact" => {
        "path" => @front_path.relative_path_from(ROOT).to_s,
        "sha256" => Digest::SHA256.file(@front_path).hexdigest,
        "schema_version" => "front-planning-readiness.v17"
      },
      "reference_unit_json_pointer" => unit_pointer,
      "reference_unit_value_sha256" => IdolReferenceRolePlanContract.value_sha256(unit_row),
      "function_json_pointer" => "#{unit_pointer}/function_analysis/#{function_index}",
      "function_value_sha256" => IdolReferenceRolePlanContract.value_sha256(function_row)
    }
    if sequence_unit
      row["sequence_unit_json_pointer"] = "#{unit_pointer}/sequence_unit"
      row["sequence_unit_value_sha256"] = IdolReferenceRolePlanContract.value_sha256(unit_row.fetch("sequence_unit"))
    end
    row
  end


  def refresh_front_and_lineage_hashes
    @front_path.write(YAML.dump("schema_version" => "front-planning-readiness.v17", "reference_connection_research" => {"reference_units" => @units}))
    @plan.fetch("logical_role_groups").each do |group|
      rows = Array(group["world_look_function_lineage"]) + Array(group["motion_function_lineage"]) + Array(group["prop_function_lineage"])
      rows << group["composition_anchor_function_lineage"] if group["composition_anchor_function_lineage"].is_a?(Hash)
      rows.each do |row|
        next unless row.is_a?(Hash)
        unit_index = row.fetch("reference_unit_json_pointer").split("/").last.to_i
        function_index = row.fetch("function_json_pointer").split("/").last.to_i
        unit_row = @units.fetch(unit_index)
        row.fetch("source_artifact")["sha256"] = Digest::SHA256.file(@front_path).hexdigest
        row["reference_unit_value_sha256"] = IdolReferenceRolePlanContract.value_sha256(unit_row)
        row["function_value_sha256"] = IdolReferenceRolePlanContract.value_sha256(unit_row.fetch("function_analysis").fetch(function_index))
        if row.key?("sequence_unit_value_sha256")
          row["sequence_unit_value_sha256"] = IdolReferenceRolePlanContract.value_sha256(unit_row.fetch("sequence_unit"))
        end
      end
    end
  end
end
