# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "pathname"

class IdolVideoReferenceSequenceContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path

  def test_active_front_planning_requires_one_exact_five_one_second_sequence_unit_per_section
    schema = JSON.parse(ROOT.join("schemas/front-planning-readiness.schema.json").read)
    assert_equal(
      "front-planning-readiness.v17",
      schema.dig("properties", "schema_version", "const")
    )

    unit = schema.dig("$defs", "sequenceUnit")
    assert_equal 1, unit.dig("properties", "declared_cadence_seconds", "const")
    assert_equal 5, unit.dig("properties", "ordered_frames", "minItems")
    assert_equal 5, unit.dig("properties", "ordered_frames", "maxItems")
    assert_equal 5, unit.dig("properties", "frame_observations", "minItems")
    assert_equal true, unit.dig("properties", "major_reference_eligible", "const")
    assert_equal "five_source_frames_never_imply_five_core_or_branch_cuts", unit.dig("properties", "downstream_cut_count_rule", "const")

    section = schema.dig("$defs", "sectionPlan")
    assert_equal 1, section.dig("properties", "sequence_unit_ids", "minItems")
    research = schema.dig("$defs", "referenceConnectionResearch")
    assert_includes research.fetch("required"), "section_sequence_unit_floor"
  end

  def test_sequence_direct_requires_active_unit_but_does_not_force_five_downstream_cuts
    schema = JSON.parse(ROOT.join("schemas/front-planning-readiness.schema.json").read)
    unit = schema.dig("$defs", "referenceUnit")
    assert_includes unit.fetch("required"), "sequence_unit"
    gate = unit.fetch("allOf").find do |row|
      row.dig("if", "anyOf")&.any? do |condition|
        condition.dig("properties", "direct_use_mode", "const") == "sequence_direct"
      end
    end
    refute_nil gate
    assert_equal "#/$defs/sequenceUnit", gate.dig("then", "properties", "sequence_unit", "$ref")

    hub_skill = ROOT.join("skills/idol-video-reference-hub/SKILL.md").read
    assert_includes hub_skill, "exactly five"
    assert_includes hub_skill, "not five required downstream cuts"
    assert_includes hub_skill, "Major Scene"
  end

  def test_selected_derivatives_reuse_existing_crop_and_02a_binding_surfaces
    hub_skill = ROOT.join("skills/idol-video-reference-hub/SKILL.md").read
    director_detail = ROOT.join("skills/idol-mv-director/references/01-bundle-authoring-detail.md").read
    storyboard = JSON.parse(ROOT.join("schemas/master-storyboard.schema.json").read)

    assert_includes hub_skill, "scripts/idol_video_qc_sheet.py"
    assert_includes hub_skill, "--cell-crops-dir"
    assert_includes hub_skill, "Do not create a new crop helper"
    assert_includes director_detail, "1..N ordered Branch Cuts per Core"
    assert storyboard.dig("$defs", "branchCut", "properties").key?("visual_reference_bindings")
  end

  def test_restricted_edits_need_exact_founder_permission_before_active_use
    schema = JSON.parse(ROOT.join("schemas/mv-direction-reference-mining.schema.json").read)
    capture = schema.dig("properties", "reference_captures", "items", "properties")
    permission = capture.fetch("restricted_source_permission")

    assert_equal "exact_current_task_founder_approval",
                 permission.dig("properties", "approval_scope", "const")
    assert_equal false, permission.dig("properties", "provided_link_or_file_is_approval", "const")
    assert_equal false, permission.dig("properties", "rhythm_permission_implies_scene_binding", "const")
    direct_gate = permission.fetch("allOf").first
    assert_includes direct_gate.dig("then", "required"), "direct_scene_binding_lock_pointer"

    active_gate = schema.fetch("allOf").first.dig(
      "then", "properties", "reference_captures", "items", "allOf"
    ).last
    assert_equal %w[amv_or_mad_edit short_form_response_edit],
                 active_gate.dig("if", "properties", "source_type", "enum")
    assert_includes active_gate.dig("then", "anyOf").last.fetch("required"),
                    "restricted_source_permission"
  end
end
