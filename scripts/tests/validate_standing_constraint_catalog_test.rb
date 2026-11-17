# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class ValidateStandingConstraintCatalogTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_standing_constraint_catalog.rb")
  CATALOG = ROOT.join("automation", "harness-standing-constraint-catalog.yaml")

  def test_catalog_passes
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, chdir: ROOT.to_s)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "standing-constraint-catalog: pass"
  end

  def test_locked_terms_and_four_graph_gaps
    catalog = YAML.safe_load(CATALOG.read)
    ids = catalog.fetch("constraints").map { |row| row.fetch("constraint_id") }
    assert_includes ids, "SC-HELPER-CONSUMPTION-RECEIPT"
    assert_includes ids, "SC-RUN-FOLLOWUP-SIDECAR"
    assert_includes ids, "SC-ROLE-CONTEXT-PACK"
    assert_includes ids, "SC-LOCAL-PAIRWISE-GLOBAL"
    assert_includes ids, "SC-NO-CONSTRAINTS-MD"
    assert_includes ids, "SC-NO-AUTO-SKILL-SAVE"
    assert_includes ids, "SC-NO-WEEKLY-HARNESS-SWARM"
    assert_includes ids, "SC-COLOR-STAY-V17-PIN"
    assert_equal false, catalog.dig("promotion_policy", "catalog_may_copy_owner_prose")
    assert_includes catalog.fetch("forbidden_imports"), "CONSTRAINTS.md"
  end
end
