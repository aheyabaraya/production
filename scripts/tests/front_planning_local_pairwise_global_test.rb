# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class FrontPlanningLocalPairwiseGlobalTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_front_planning_local_pairwise_global.rb")

  def test_new_authoring_without_graph_holds
    path = write_yaml("schema_version" => "front-planning-readiness.v17")
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    refute status.success?
    assert_includes stderr, "local_pairwise_global_presence_missing"
  end

  def test_new_authoring_with_cdd_local_pairwise_and_overall_global_passes
    path = write_yaml(
      "schema_version" => "front-planning-readiness.v17",
      "creative_review_graph" => valid_graph
    )
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    assert status.success?, stderr
    assert_includes stdout, "local-pairwise-global: pass"
  end

  def test_global_owned_by_cdd_holds
    graph = valid_graph
    graph["global"]["owner_role"] = "creative_development_director"
    path = write_yaml("schema_version" => "front-planning-readiness.v17", "creative_review_graph" => graph)
    _stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, path)
    refute status.success?
    assert_includes stderr, "local_pairwise_global_owner_mismatch"
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
      File.write(frozen, YAML.dump("schema_version" => "front-planning-readiness.v17"))
      _stdout, stderr, status = Open3.capture3("ruby", validator, "--admission-graph", frozen)
      refute status.success?
      assert_includes stderr, "local_pairwise_global_presence_missing"
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
      refute status.success?, stdout
      assert_includes stderr, "local_pairwise_global_presence_missing"
      refute_includes stdout, "skip frozen COLOR STAY v17"
    end
  end

  def valid_graph
    {
      "local" => {
        "present" => true,
        "owner_role" => "creative_development_director",
        "scope" => "single-major local review"
      },
      "pairwise" => {
        "present" => true,
        "owner_role" => "creative_development_director",
        "scope" => "adjacent-major pairwise review"
      },
      "global" => {
        "present" => true,
        "owner_role" => "overall_director",
        "scope" => "whole-film global review"
      }
    }
  end

  def with_isolated_hold_tree
    Dir.mktmpdir("local-pairwise-global-tree-") do |tree|
      scripts = File.join(tree, "scripts")
      lib = File.join(scripts, "lib")
      FileUtils.mkdir_p(lib)
      FileUtils.cp(
        ROOT.join("scripts", "lib", "idol_front_planning_sequence_core_hold.rb").to_s,
        File.join(lib, "idol_front_planning_sequence_core_hold.rb")
      )
      FileUtils.cp(
        ROOT.join("scripts", "lib", "idol_front_planning_local_pairwise_global.rb").to_s,
        File.join(lib, "idol_front_planning_local_pairwise_global.rb")
      )
      validator = File.join(scripts, "validate_front_planning_local_pairwise_global.rb")
      FileUtils.cp(VALIDATOR.to_s, validator)
      frozen = File.join(tree, "runs/aurora-m/color-stay/20260811_COLOR_STAY_PRE00/front-planning.yaml")
      yield tree, validator, frozen
    end
  end

  def write_yaml(document)
    path = File.join(Dir.mktmpdir("local-pairwise-global"), "front-planning.yaml")
    File.write(path, YAML.dump(document))
    path
  end
end
