# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

class ValidateHelperConsumptionReceiptTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_helper_consumption_receipt.rb")
  FIXTURE = ROOT.join("scripts", "tests", "fixtures", "helper-consumption-receipt-valid.yaml")

  def test_valid_fixture_passes
    stdout, stderr, status = Open3.capture3(
      "ruby",
      VALIDATOR.to_s,
      "--receipt",
      FIXTURE.to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "helper-consumption-receipt: pass"
  end

  def test_missing_disposition_fails
    Dir.mktmpdir do |dir|
      bad = Pathname.new(dir).join("bad.yaml")
      bad.write(<<~YAML)
        schema_version: idol-helper-consumption-receipt.v1
        receipt_id: HCR_BAD
        parent_dispatch_id: DISPATCH_X
        helper_id: helper_x
        inspected_inputs:
          - a.yaml
        finding: missing disposition
      YAML
      _stdout, _stderr, status = Open3.capture3(
        "ruby",
        VALIDATOR.to_s,
        "--receipt",
        bad.to_s,
        chdir: ROOT.to_s
      )
      refute status.success?
    end
  end
end
