# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "support/active_mv_fixture"

class FounderSequenceControlTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_founder_sequence_control.rb")

  def test_current_template_starts_as_a_valid_draft_without_fabricating_ready_authority
    document = YAML.safe_load(ROOT.join("templates", "founder-sequence-control.template.yaml").read)
    assert_valid(document)
    document["status"] = "director_ready"
    assert_invalid(document, "start_authorized")
  end

  def test_current_idol_ready_control_retains_typed_reference_and_section_checks
    fixture = ActiveMvFixture.new
    document = fixture.send(:founder_sequence_control_document)
    fixture.send(:upgrade_founder_sequence_control!, document)
    assert_valid(document)
    document.dig("reference_plan", "references", 0)["target_section_ids"] = ["S99"]
    assert_invalid(document, "target_section_ids must exact-cover")
    document.dig("reference_plan", "references", 0)["target_section_ids"] = ["S01"]
    document.dig("reference_plan", "references").pop
    assert_invalid(document, "exactly one typed Z reference")
  end

  def test_retired_cf_control_requires_explicit_historical_audit_and_never_migrates_bytes
    document = legacy_cf_document
    original = JSON.generate(document)
    assert_invalid(document, "v1 is historical only")
    result = assert_valid(document, "--mode", "historical_audit")
    assert_equal true, result.fetch("evidence_only")
    assert_equal original, JSON.generate(document)
    document["schema_version"] = "idol_founder_sequence_control.v99"
    assert_invalid(document, "unknown or inactive", "--mode", "historical_audit")
  end

  def test_historical_mode_still_checks_legacy_evidence_and_malformed_input_returns_json
    document = legacy_cf_document
    document.dig("founder_gate", "reviewed_reference_ids").pop
    assert_invalid(document, "Founder PASS must review every reference", "--mode", "historical_audit")
    document["reference_plan"] = {"references" => ["not a reference object"]}
    assert_invalid(document, "JSON Schema validation failed", "--mode", "historical_audit")
  end

  def test_empty_document_cannot_report_validation_success_in_either_mode
    assert_invalid({}, "unknown or inactive")
    assert_invalid({}, "unknown or inactive", "--mode", "historical_audit")
  end

  def test_plain_text_success_identifies_a_draft_without_claiming_complete_reference_coverage
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, ROOT.join("templates", "founder-sequence-control.template.yaml").to_s)
    assert status.success?, stderr
    assert_includes stdout, "status: draft"
    assert_includes stdout, "structural validation only"
    refute_includes stdout, "carries typed A/B/C and X/Y/Z"
  end

  private

  def validate(document, *options)
    Dir.mktmpdir("idol-sequence-control-test-") do |directory|
      file = Pathname.new(directory).join("control.json")
      bytes = JSON.pretty_generate(document) + "\n"
      file.write(bytes)
      stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, "--root", directory, "--json", *options, file.to_s)
      assert_equal bytes, file.read, "a read-only validator must preserve input bytes"
      [JSON.parse(stdout), stderr, status]
    end
  end

  def assert_valid(document, *options)
    result, stderr, status = validate(document, *options)
    assert status.success?, [stderr, result].inspect
    assert_equal true, result.fetch("valid")
    result
  end

  def assert_invalid(document, message, *options)
    result, stderr, status = validate(document, *options)
    refute status.success?, [stderr, result].inspect
    assert_equal false, result.fetch("valid")
    assert_includes result.fetch("errors").join("\n"), message
  end

  def legacy_cf_document
    document = ActiveMvFixture.new.send(:founder_sequence_control_document)
    document["schema_version"] = "idol_founder_sequence_control.v1"
    document["lane"] = "cf_code"
    document["status"] = "passed"
    document["source_capture"].delete("start_authorization_mode")
    document["source_capture"]["capture_mode"] = "founder_conversation_transcribed_by_director"
    document.dig("story_flow", "ordered_major_scenes").each do |major|
      major["founder_direction"] = major.delete("direction")
      major.delete("direction_owner")
    end
    document.dig("reference_plan", "references").each { |reference| reference.delete("assignment_owner") }
    translation = document.fetch("director_translation")
    %w[explicit_founder_locks_preserved director_fills_unspecified_story_order reference_roles_are_proposals_unless_founder_locked].each { |key| translation.delete(key) }
    translation["translation_preserves_founder_order"] = true
    translation["reference_roles_preserved"] = true
    document.delete("minimal_intervention_contract")
    document.delete("startup_gate")
    document["lane_contract"] = {
      "founder_controls_whole_story_flow" => true, "director_translates_to_execution_truth" => true,
      "planning_may_not_close_before_founder_pass" => true, "founder_authors_idol_major_scenes" => false,
      "idol_major_and_member_visual_same_review_unit" => false, "idol_key_screens_require_founder_review" => false,
      "idol_separate_background_asset_generation" => false
    }
    document["founder_gate"] = {
      "decision" => "pass", "reviewed_control_major_ids" => ["FSC_MAJOR_01"],
      "reviewed_reference_ids" => document.dig("reference_plan", "references").map { |row| row.fetch("reference_id") },
      "unresolved_material_choices" => [], "projection_authorized" => true, "note" => "Historical test evidence only."
    }
    document
  end
end
