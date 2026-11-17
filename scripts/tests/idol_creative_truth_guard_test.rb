# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"

class IdolCreativeTruthGuardTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  GUARD = ROOT.join("scripts", "idol_creative_truth_guard.rb")

  def setup
    @day_root = ROOT.join("runs", "2099-12-31")
    @run = @day_root.join("CREATIVE_GUARD_#{SecureRandom.hex(4).upcase}")
    @work = @run.join("work", "guard-fixtures")
    @work.mkpath
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    @day_root.rmdir if @day_root&.directory? && @day_root.children.empty?
  end

  def test_direct_canonical_write_is_blocked
    write_script("direct.py", <<~PYTHON)
      from pathlib import Path
      RUN = Path("#{run_relative}")
      TARGET = RUN / "02A-master-storyboard.yaml"
      TARGET.write_text("invented camera: same")
    PYTHON

    result, status = guard
    refute status.success?
    assert_equal "fail", result.fetch("status")
    assert_reason result, "run_owned_canonical_write_target"
  end

  def test_custom_dump_helper_to_canonical_target_is_blocked
    write_script("helper.py", <<~PYTHON)
      from pathlib import Path
      RUN = Path("#{run_relative}")
      out = RUN / "01-song-choreography-performance-mv-map.yaml"
      def dump_yaml(path, value):
          path.write_text(value)
      dump_yaml(out, "camera: default")
    PYTHON

    result, status = guard
    refute status.success?
    assert_reason result, "run_owned_canonical_write_target"
  end

  def test_reading_canonical_and_writing_only_scratch_is_allowed
    write_script("scanner.py", <<~PYTHON)
      from pathlib import Path
      RUN = Path("#{run_relative}")
      SOURCE = RUN / "02A-master-storyboard.yaml"
      SCRATCH = RUN / "work/guard-fixtures/scan.json"
      value = SOURCE.read_text() if SOURCE.exists() else "missing"
      SCRATCH.write_text(value)
    PYTHON

    result, status = guard
    assert status.success?, result.inspect
    assert_equal "pass", result.fetch("status")
  end

  def test_script_authored_creative_review_verdict_is_blocked
    write_script("review.py", <<~PYTHON)
      from pathlib import Path
      RUN = Path("#{run_relative}")
      REVIEW = RUN / "review/02a-context-v3/02a-creative-context-review-v3.yaml"
      review = {"verdict": "pass", "script_substitution_detected": False}
      REVIEW.write_text(str(review))
    PYTHON

    result, status = guard
    refute status.success?
    assert_reason result, "script_authored_creative_review_verdict"
  end

  def test_script_claimed_model_authorship_is_reported_with_canonical_write
    write_script("claimed.py", <<~PYTHON)
      from pathlib import Path
      RUN = Path("#{run_relative}")
      TARGET = RUN / "00-creative-nucleus.yaml"
      document = {"authoring_owner": "model_authored_02a"}
      TARGET.write_text(str(document))
    PYTHON

    result, status = guard
    refute status.success?
    assert_reason result, "script_claimed_model_authorship"
  end

  def test_run_owned_helper_cannot_select_or_hold_front_planning_canvas_truth
    write_script("canvas_patch.py", <<~PYTHON)
      from pathlib import Path
      RUN = Path("#{run_relative}")
      CANVAS = RUN / "work/front_planning_integration/canvas-state.json"
      CANVAS.write_text('{"status":"selected","held":false}')
    PYTHON

    result, status = guard
    refute status.success?
    assert_reason result, "run_owned_creative_state_write"
  end

  private

  def run_relative
    @run.relative_path_from(ROOT).to_s
  end

  def write_script(name, body)
    @work.join(name).write(body)
  end

  def guard
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      GUARD.to_s,
      run_relative,
      "--json",
      chdir: ROOT.to_s
    )
    [JSON.parse(stdout.empty? ? stderr : stdout), status]
  end

  def assert_reason(result, expected)
    reasons = result.fetch("offenders").flat_map do |row|
      row.fetch("reasons").map { |reason| reason.fetch("reason") }
    end
    assert_includes reasons, expected
  end
end
