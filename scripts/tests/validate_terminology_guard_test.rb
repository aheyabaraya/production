# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

class ValidateTerminologyGuardTest < Minitest::Test
  SCRIPT = Pathname.new(__dir__).join("..", "validate_terminology_guard.rb").expand_path

  def check(text, extension = ".md")
    Dir.mktmpdir("idol-terminology-") do |directory|
      path = Pathname.new(directory).join("sample#{extension}")
      path.write(text)
      Open3.capture3(RbConfig.ruby, SCRIPT.to_s, path.to_s)
    end
  end

  def test_ordinary_evidence_and_review_prose_is_allowed
    text = <<~TEXT
      Keep decision-ready actual visual evidence for each selected screen job.
      An OTS needs visual evidence of whose view the camera represents.
      `upload-ready/` remains the authoring/review surface for the current job.
      Audio pressure and lyric pressure can describe an interpretation.
    TEXT
    stdout, stderr, status = check(text)
    assert status.success?, stderr
    assert_includes stdout, "terminology guard passed"
  end

  def test_retired_labels_still_fail_in_plain_and_formatted_fields
    ["Visual evidence: an authored detail", "- **Visual evidence:** an authored detail",
     "### Review surface", "| Audio pressure | cue |", "Proof target: object",
     "Lyric pressure: cue"].each do |label|
      _stdout, stderr, status = check(label + "\n")
      refute status.success?, label
      refute_empty stderr, label
    end
  end

  def test_serialized_prompt_labels_fail_without_banning_captured_prose
    _stdout, stderr, status = check('{"full_prompt_text": "Visual evidence: a detail"}', ".json")
    refute status.success?, stderr
    _stdout, stderr, status = check('{"content": "Require actual visual evidence for the selected unit."}', ".json")
    assert status.success?, stderr
  end

  def test_retired_screen_beat_instruction_is_rejected_but_musical_beat_is_allowed
    _stdout, stderr, status = check("02A storyboard beats\n")
    refute status.success?, stderr
    _stdout, stderr, status = check("Keep the musical beat and current Core/Branch ownership distinct.\n")
    assert status.success?, stderr
  end

  def test_explicit_legacy_label_and_compatibility_field_remain_readable
    _stdout, stderr, status = check("Legacy Visual evidence label is read-only compatibility.\nproof_target: an existing schema value\n", ".yaml")
    assert status.success?, stderr
  end
end
