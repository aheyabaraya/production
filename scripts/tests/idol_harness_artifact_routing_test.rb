# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"

class IdolHarnessArtifactRoutingTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "validate_harness_artifact_routing.rb")

  def test_active_routing_exact_covers_registry
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      "--json",
      chdir: ROOT.to_s
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "pass", result["status"]
    assert_equal 19, result["active_stage_count"]
    assert_equal result["active_stage_count"], result["routing_stage_count"]
    assert_empty result["errors"]
  end
end
