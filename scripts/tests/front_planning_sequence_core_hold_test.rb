# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class FrontPlanningSequenceCoreHoldTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_front_planning_sequence_core_hold.rb")

  def test_new_v17_same_sequence_unit_frames_hold_by_default
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "core_visual_candidate_sets" => [same_unit_set]
    )
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    refute status.success?
    assert_includes stderr, "same_event_anchor_counted_as_hypothesis_floor"
    assert_includes stderr, "CS01"
  end

  def test_isolated_frozen_relative_path_is_skipped_without_admission_graph
    with_isolated_hold_tree do |_tree, validator, frozen|
      FileUtils.mkdir_p(File.dirname(frozen))
      File.write(frozen, YAML.dump("schema_version" => "front-planning-readiness.v17"))
      [frozen, File.realpath(frozen)].uniq.each do |path|
        stdout, stderr, status = Open3.capture3("ruby", validator, path)
        assert status.success?, "#{path}: #{stderr}"
        assert_includes stdout, "skip frozen COLOR STAY v17"
      end
    end
  end

  def test_isolated_frozen_relative_path_holds_under_admission_graph
    with_isolated_hold_tree do |_tree, validator, frozen|
      FileUtils.mkdir_p(File.dirname(frozen))
      File.write(
        frozen,
        YAML.dump(
          "schema_version" => "front-planning-readiness.v17",
          "core_visual_candidate_sets" => [same_unit_set]
        )
      )
      _stdout, stderr, status = Open3.capture3("ruby", validator, "--admission-graph", frozen)
      refute status.success?
      assert_includes stderr, "same_event_anchor_counted_as_hypothesis_floor"
    end
  end

  def test_isolated_missing_frozen_relative_path_is_not_skipped
    with_isolated_hold_tree do |_tree, validator, frozen|
      refute File.exist?(frozen)
      stdout, stderr, status = Open3.capture3("ruby", validator, frozen)
      refute status.success?, stdout
      assert_includes stderr, "Front Planning path is missing"
      refute_includes stdout, "skip frozen COLOR STAY v17"
    end
  end

  def test_isolated_same_basename_outside_frozen_relative_path_is_not_skipped
    with_isolated_hold_tree do |tree, validator, _frozen|
      other = File.join(tree, "work", "front-planning.yaml")
      FileUtils.mkdir_p(File.dirname(other))
      File.write(other, YAML.dump("schema_version" => "front-planning-readiness.v17"))
      stdout, stderr, status = Open3.capture3("ruby", validator, other)
      assert status.success?, stderr
      assert_includes stdout, "sequence-core-hold: pass"
      refute_includes stdout, "skip frozen COLOR STAY v17"
    end
  end

  def test_same_sequence_unit_frames_hold_under_admission_graph
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "core_visual_candidate_sets" => [same_unit_set]
    )
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, "--admission-graph", path)
    refute status.success?
    assert_includes stderr, "same_event_anchor_counted_as_hypothesis_floor"
    assert_includes stderr, "CS01"
  end

  def test_same_sequence_unit_split_across_three_core_slots_holds
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "core_visual_candidate_sets" => split_unit_sets
    )
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    refute status.success?
    assert_includes stderr, "same_event_sequence_counted_as_three_cores"
    assert_includes stderr, "SU-OP-CLAIM"
  end

  def test_frame_dump_without_su_token_holds
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "core_visual_candidate_sets" => [{
        "core_slot_id" => "CS01",
        "candidates" => [
          {"source_identity" => "EVENT-KICK frame 1", "actual_path" => "runs/x/EVENT-KICK/frame-01.png"},
          {"source_identity" => "EVENT-KICK frame 3", "actual_path" => "runs/x/EVENT-KICK/frame-03.png"},
          {"source_identity" => "EVENT-KICK frame 5", "actual_path" => "runs/x/EVENT-KICK/frame-05.png"}
        ]
      }]
    )
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    refute status.success?
    assert_includes stderr, "same_event_anchor_counted_as_hypothesis_floor"
    assert_includes stderr, "EVENT-KICK"
  end

  def test_three_core_slots_on_one_major_hold_without_counting_seconds
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "core_visual_candidate_sets" => [
        {"core_slot_id" => "CS01", "major_scene_id" => "MJ01", "candidates" => [{"source_identity" => "door peak still", "actual_path" => "runs/x/stills/door.png"}]},
        {"core_slot_id" => "CS02", "major_scene_id" => "MJ01", "candidates" => [{"source_identity" => "alley still", "actual_path" => "runs/x/stills/alley.png"}]},
        {"core_slot_id" => "CS03", "major_scene_id" => "MJ01", "candidates" => [{"source_identity" => "wall still", "actual_path" => "runs/x/stills/wall.png"}]}
      ]
    )
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    refute status.success?
    assert_includes stderr, "third_core_without_new_major"
    assert_includes stderr, "MJ01"
  end

  def test_two_core_slots_from_one_sequence_unit_do_not_trip_three_core_hold
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "core_visual_candidate_sets" => split_unit_sets.first(2)
    )
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    assert status.success?, stderr
    assert_includes stdout, "sequence-core-hold: pass"
  end

  def test_distinct_sequence_units_pass_under_admission_graph
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v18",
      "core_visual_candidate_sets" => [distinct_unit_set]
    )
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, "--admission-graph", path)
    assert status.success?, stderr
    assert_includes stdout, "sequence-core-hold: pass"
  end

  def same_unit_set
    {
      "core_slot_id" => "CS01",
      "candidates" => [
        {"source_identity" => "SU-OP-CLAIM frame 1", "actual_path" => "runs/x/SU-OP-CLAIM/frame-01.png"},
        {"source_identity" => "SU-OP-CLAIM frame 3", "actual_path" => "runs/x/SU-OP-CLAIM/frame-03.png"},
        {"source_identity" => "SU-OP-CLAIM frame 5", "actual_path" => "runs/x/SU-OP-CLAIM/frame-05.png"}
      ]
    }
  end

  def split_unit_sets
    [
      {
        "core_slot_id" => "CS01",
        "candidates" => [
          {"source_identity" => "SU-OP-CLAIM frame 1", "actual_path" => "runs/x/SU-OP-CLAIM/frame-01.png"},
          {"source_identity" => "door peak still", "actual_path" => "runs/x/stills/door.png"}
        ]
      },
      {
        "core_slot_id" => "CS02",
        "candidates" => [
          {"source_identity" => "SU-OP-CLAIM frame 3", "actual_path" => "runs/x/SU-OP-CLAIM/frame-03.png"},
          {"source_identity" => "alley still", "actual_path" => "runs/x/stills/alley.png"}
        ]
      },
      {
        "core_slot_id" => "CS03",
        "candidates" => [
          {"source_identity" => "SU-OP-CLAIM frame 5", "actual_path" => "runs/x/SU-OP-CLAIM/frame-05.png"},
          {"source_identity" => "wall still", "actual_path" => "runs/x/stills/wall.png"}
        ]
      }
    ]
  end

  def distinct_unit_set
    {
      "core_slot_id" => "CS01",
      "candidates" => [
        {"source_identity" => "SU-OP-CLAIM frame 2", "actual_path" => "runs/x/SU-OP-CLAIM/frame-02.png"},
        {"source_identity" => "SU-GDL-ALLEY frame 1", "actual_path" => "runs/x/SU-GDL-ALLEY/frame-01.png"},
        {"source_identity" => "door peak still", "actual_path" => "runs/x/stills/door-peak.png"}
      ]
    }
  end

  def with_isolated_hold_tree
    Dir.mktmpdir("sequence-core-hold-tree-") do |tree|
      scripts = File.join(tree, "scripts")
      lib = File.join(scripts, "lib")
      FileUtils.mkdir_p(lib)
      FileUtils.cp(
        ROOT.join("scripts", "lib", "idol_front_planning_sequence_core_hold.rb").to_s,
        File.join(lib, "idol_front_planning_sequence_core_hold.rb")
      )
      validator = File.join(scripts, "validate_front_planning_sequence_core_hold.rb")
      FileUtils.cp(VALIDATOR.to_s, validator)
      frozen = File.join(tree, "runs/aurora-m/color-stay/20260811_COLOR_STAY_PRE00/front-planning.yaml")
      yield tree, validator, frozen
    end
  end

  def write_yaml(document)
    path = File.join(Dir.mktmpdir("sequence-core-hold"), "front-planning.yaml")
    File.write(path, YAML.dump(document))
    path
  end
end
