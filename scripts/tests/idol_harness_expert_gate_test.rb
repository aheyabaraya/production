# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolHarnessExpertGateTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  GATE = ROOT.join("scripts", "idol_harness_expert_gate.rb")

  def test_active_01_direction_expansion_passes
    report, status = run_gate(direction: active_direction)
    gate = find_gate(report, "front_planning_to_01_direction_expansion")

    assert status.success?, JSON.pretty_generate(report)
    assert_equal "pass", gate.fetch("status")
    assert_includes gate.fetch("evidence"), "still_camera_owner=01_and_02a"
    assert_includes gate.fetch("evidence"), "temporal_camera_owner=03v_after_passed_pixels"
  end

  def test_retired_01_contract_is_rejected
    direction = active_direction.merge("schema_version" => "1.7")
    report, status = run_gate(direction: direction)
    gate = find_gate(report, "front_planning_to_01_direction_expansion")

    refute status.success?
    assert_equal "fail", gate.fetch("status")
    assert_includes gate.fetch("missing"), "schema_version=2.0"
  end

  def test_missing_01_is_not_applicable
    report, status = run_gate(direction: nil)
    gate = find_gate(report, "front_planning_to_01_direction_expansion")

    assert status.success?, JSON.pretty_generate(report)
    assert_equal false, gate.fetch("applies")
    assert_equal "not_applicable", gate.fetch("status")
  end

  def test_temporal_camera_cannot_move_upstream_of_03v
    direction = active_direction
    direction.fetch("section_directions").first.fetch("still_camera_coverage").first[
      "temporal_camera_owner"
    ] = "01"
    report, status = run_gate(direction: direction)
    gate = find_gate(report, "front_planning_to_01_direction_expansion")

    refute status.success?
    assert_includes gate.fetch("missing"), "S00.temporal_camera_owner"
  end

  def test_primary_choreography_requires_actual_reference_binding
    direction = active_direction
    section = direction.fetch("section_directions").first
    section["choreography_presence_policy"] = "primary"
    report, status = run_gate(direction: direction)
    gate = find_gate(report, "choreography_execution_feasibility")

    refute status.success?
    assert_equal "fail", gate.fetch("status")
    assert_includes gate.fetch("missing"), "S00"
  end

  def test_primary_choreography_with_reference_binding_passes
    direction = active_direction
    section = direction.fetch("section_directions").first
    section["choreography_presence_policy"] = "primary"
    section["choreography_reference_binding"] = {
      "reference_unit_id" => "REF_CHOREO_S00"
    }
    report, status = run_gate(direction: direction)
    gate = find_gate(report, "choreography_execution_feasibility")

    assert status.success?, JSON.pretty_generate(report)
    assert_equal "pass", gate.fetch("status")
  end

  def test_active_storyboard_gate_rejects_old_context_review
    report, status = run_gate(
      direction: active_direction,
      storyboard_review_schema: "idol-02a-creative-context-review.v3"
    )
    gate = find_gate(report, "storyboard_llm_creative_context_review")

    refute status.success?
    assert_equal "fail", gate.fetch("status")
    assert_includes gate.fetch("missing").join(" "),
                    "active 02B readiness requires idol-02a-creative-context-review.v7"
  end

  private

  def active_direction
    {
      "schema_version" => "2.0",
      "content_id" => "EXPERT_GATE_TEST",
      "status" => "passed",
      "source_front_planning" => {"path" => "research/front-planning-readiness-v7.yaml", "sha256" => "a" * 64},
      "source_song_lock" => {"path" => "00A-song-lock.yaml", "sha256" => "b" * 64},
      "front_planning_consumption_contract" => {"mode" => "exact_projection"},
      "target_message_projection" => {"projected_value" => "target and message"},
      "whole_film_spine_projection" => {"projected_value" => "whole-film spine"},
      "founder_visual_alignment_projection" => {"projected_value" => {"whole_film_readout" => "whole-film Founder alignment"}},
      "section_directions" => [
        {
          "section_id" => "S00",
          "section_alignment_projection" => {"projected_value" => {"section_id" => "S00"}},
          "planning_cut_alignment_projections" => [{"planning_cut_id" => "PC_S00_01", "projected_value" => {"action" => "fixture"}}],
          "scene_expansions" => [
            {
              "scene_id" => "SCENE_S00_01",
              "source_key_screen_anchor_ids" => ["KS_S00_01"],
              "branching_opportunities" => [
                {
                  "opportunity_id" => "BRANCH_OP_S00_01",
                  "source_key_screen_anchor_ids" => ["KS_S00_01"]
                }
              ]
            }
          ],
          "still_camera_coverage" => [
            {
              "coverage_id" => "CAM_S00_01",
              "source_key_screen_anchor_ids" => ["KS_S00_01"],
              "temporal_camera_owner" => "03V_after_passed_image_pixel_inspection"
            }
          ],
          "choreography_presence_policy" => "absent",
          "choreography_reference_binding" => nil
        }
      ]
    }
  end

  def find_gate(report, id)
    report.fetch("gates").find { |row| row["id"] == id }
  end

  def run_gate(direction:, storyboard_review_schema: nil)
    Dir.mktmpdir("idol-expert-gate-") do |directory|
      run_root = Pathname.new(directory)
      if direction
        run_root.join("01-song-choreography-performance-mv-map.yaml").write(
          YAML.dump(direction)
        )
      end
      if storyboard_review_schema
        run_root.join("02A-master-storyboard.yaml").write(
          YAML.dump(
            "schema_version" => "2.5",
            "content_id" => "EXPERT_GATE_TEST",
            "status" => "generation_ready",
            "master_storyboard" => [
              {
                "core_cut_id" => "CC_S00_01",
                "section_id" => "S00",
                "branch_cuts" => [{"branch_cut_id" => "BC_S00_01"}]
              }
            ]
          )
        )
        review_path = run_root.join("review", "02a-creative-context-review-v6.yaml")
        review_path.dirname.mkpath
        review_path.write(YAML.dump("schema_version" => storyboard_review_schema))
      end

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        GATE.to_s,
        run_root.to_s,
        "--json",
        chdir: ROOT.to_s
      )
      raise stderr if stdout.strip.empty?

      [JSON.parse(stdout), status]
    end
  end
end
