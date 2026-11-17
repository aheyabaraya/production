# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "support/active_mv_fixture"

class FrontPlanningFrozenSkipAdmissionGraphTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")
  REQUIRED_LIBS = %w[
    idol_front_planning_sequence_core_hold.rb
    idol_storyline_density_locator_contract.rb
    idol_kinetic_slot_sheet_contract.rb
    idol_source_connection_contract.rb
  ].freeze

  def test_01_nested_front_planning_subprocess_receives_admission_graph
    Dir.mktmpdir("fp-01-nested-argv-") do |tree|
      direction = install_isolated_01_tree(tree)
      capture_with = File.join(tree, "argv-with.json")
      capture_without = File.join(tree, "argv-without.json")

      run_isolated_01(tree, direction, capture_with, admission_graph: true)
      run_isolated_01(tree, direction, capture_without, admission_graph: false)

      assert File.file?(capture_with), "nested Front Planning validator was not invoked with --admission-graph"
      assert File.file?(capture_without), "nested Front Planning validator was not invoked without --admission-graph"
      with_args = JSON.parse(File.read(capture_with))
      without_args = JSON.parse(File.read(capture_without))
      assert_includes with_args, "--admission-graph"
      refute_includes without_args, "--admission-graph"
      assert_includes with_args, "--root"
      assert_includes without_args, "--root"
    end
  end

  def test_01_live_nonfrozen_entrypoint_accepts_admission_graph
    fixture = ActiveMvFixture.create
    stdout, stderr, status = Open3.capture3(
      "ruby",
      DIRECTION_VALIDATOR.to_s,
      "--root",
      ROOT.to_s,
      "--admission-graph",
      "--json",
      fixture.direction_path.to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
    assert_equal true, JSON.parse(stdout).fetch("valid")
  ensure
    fixture.cleanup if fixture
  end

  private

  def install_isolated_01_tree(tree)
    scripts = File.join(tree, "scripts")
    lib = File.join(scripts, "lib")
    work = File.join(tree, "work")
    FileUtils.mkdir_p(lib)
    FileUtils.mkdir_p(work)
    FileUtils.cp(DIRECTION_VALIDATOR.to_s, File.join(scripts, "validate_01_section_direction.rb"))
    REQUIRED_LIBS.each do |name|
      FileUtils.cp(ROOT.join("scripts", "lib", name).to_s, File.join(lib, name))
    end
    File.write(
      File.join(scripts, "validate_front_planning_readiness.rb"),
      "# frozen_string_literal: true\nrequire \"json\"\nFile.binwrite(ENV.fetch(\"IDOL_FRONT_VALIDATOR_ARGV_CAPTURE\"), JSON.generate(ARGV))\nexit 7\n"
    )
    python = File.join(scripts, "idol-video-python")
    File.write(python, "#!/usr/bin/env ruby\nexit 1\n")
    File.chmod(0o755, python)
    front = File.join(work, "front-planning.yaml")
    File.write(front, YAML.dump("schema_version" => "front-planning-readiness.v17"))
    direction = File.join(work, "01-section-direction.yaml")
    File.write(
      direction,
      YAML.dump(
        "schema_version" => "3.0",
        "source_front_planning" => {
          "path" => "work/front-planning.yaml",
          "sha256" => Digest::SHA256.file(front).hexdigest
        }
      )
    )
    direction
  end

  def run_isolated_01(tree, direction, capture, admission_graph:)
    command = [
      "ruby",
      File.join(tree, "scripts", "validate_01_section_direction.rb"),
      "--root",
      tree,
      direction
    ]
    command.insert(-2, "--admission-graph") if admission_graph
    Open3.capture3({"IDOL_FRONT_VALIDATOR_ARGV_CAPTURE" => capture}, *command, chdir: tree)
  end
end
