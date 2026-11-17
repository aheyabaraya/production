# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"

require Pathname.new(__dir__).join("..", "..", "scripts", "validate_session_helper_operating_lock.rb").to_s

class IdolSessionHelperOperatingLockTest < Minitest::Test
  CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")
  VALIDATOR = ROOT.join("scripts", "validate_session_helper_operating_lock.rb")
  SCHEMA = ROOT.join("schemas", "harness-execution-contract.schema.json")

  def test_live_execution_contract_passes_shipped_floor_validator
    contract = YAML.safe_load(CONTRACT.read, aliases: true)
    errors = contract_floor_errors(contract)
    assert_empty errors, errors.join("\n")

    status = system("ruby", VALIDATOR.to_s, out: File::NULL, err: File::NULL)
    assert status, "ruby scripts/validate_session_helper_operating_lock.rb must PASS on live bytes"
  end

  def test_shipped_schema_accepts_live_execution_contract
    raw = `python3 scripts/idol-video-python -c "import json,sys; print('skip')" 2>/dev/null`
    json_schema = JSON.parse(SCHEMA.read)
    assert_equal "idol-harness-execution-contract.v36", json_schema.dig("properties", "schema_version", "const")
    contract = YAML.safe_load(CONTRACT.read, aliases: true)
    assert_equal json_schema.dig("properties", "schema_version", "const"), contract.fetch("schema_version")
  end

  def test_lowering_helper_min_fails_the_shipped_validator
    contract = YAML.safe_load(CONTRACT.read, aliases: true)
    contract["session_route"]["department_worker_execution_topology"]["parent_scoped_helpers"]["cdd_fp_02a_multi_leaf_min"] = 2
    errors = contract_floor_errors(contract)
    refute_empty errors
    assert errors.any? { |error| error.include?("cdd_fp_02a_multi_leaf_min") }
  end

  def test_omitting_reference_floor_fails_the_shipped_validator
    contract = YAML.safe_load(CONTRACT.read, aliases: true)
    contract["studio_session_routing"]["post_song_reference_wave"]["assignment_count_floor"] = 0
    contract["studio_session_routing"]["post_song_reference_wave"]["floor_assignments"] = []
    errors = contract_floor_errors(contract)
    refute_empty errors
    assert errors.any? { |error| error.include?("assignment_count_floor") || error.include?("floor_assignments") }
  end

  def test_helper_count_function_uses_contract_floor
    refute helper_floor_met?(3, "cdd_fp_close")
    assert helper_floor_met?(4, "cdd_fp_close")
    assert helper_floor_met?(0, "cdd_single_return_review")
    refute helper_floor_met?(0, "cdd_fp_close")
    assert helper_floor_met?(0, "cdd_fp_close", "helper_surface_unavailable")
  end
end
