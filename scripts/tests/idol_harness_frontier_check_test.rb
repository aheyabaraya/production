# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "yaml"

class IdolHarnessFrontierCheckTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_harness_frontier_check.rb")
  CURRENT_NEXT = ROOT.join("scripts", "idol_harness_current_next.rb")
  OUTPUT_SCHEMA = ROOT.join("schemas", "harness-frontier-check.schema.json")
  VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = ROOT.join("scripts", "idol-video-python")

  def setup
    @run = ROOT.join("runs", "harness-test", "frontier-check", "RUN_#{SecureRandom.hex(5).upcase}")
    @run.join("work").mkpath
    @ddi = @run.join("work", "director-dispatch-index.yaml")
    @pointer = @run.join("work", "current-next.yaml")
    @readout = @run.join("work", "current-next.md")
    write_ddi(
      dispatches: [{"dispatch_id" => "DISPATCH_FRONTIER", "lifecycle" => {"current_state" => "launched"}, "next_action_ids" => ["NEXT_FRONTIER"]}],
      actions: [{"next_action_id" => "NEXT_FRONTIER", "owner" => "creative_development_director", "state" => "ready"}],
      entry_count: 1
    )
    build_pointer
  end

  def teardown
    FileUtils.remove_entry(@run) if @run.directory?
    prune_empty(@run.parent, ROOT.join("runs"))
  end

  def test_valid_v2_frontier_passes_and_matches_output_schema
    report, status, stderr = run_frontier

    assert status.success?, stderr
    assert_equal "pass", report.fetch("status")
    assert_equal "active_frontier", report.dig("scope", "mode")
    assert_equal "NEXT_FRONTIER", report.dig("scope", "selected_unit_id")
    assert_equal "next_action", report.dig("scope", "selected_unit_type")
    assert_equal 0, report.dig("scope", "unrelated_files_scanned")
    assert_empty report.fetch("blockers")

    output_path = @run.join("work", "frontier-report.json")
    output_path.write(JSON.pretty_generate(report))
    _stdout, schema_stderr, schema_status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, OUTPUT_SCHEMA.to_s, output_path.to_s, chdir: ROOT.to_s)
    assert schema_status.success?, schema_stderr
  end

  def test_unrelated_invalid_files_are_not_scanned
    unrelated = @run.join("work", "unrelated", "invalid.yaml")
    unrelated.dirname.mkpath
    unrelated.write("[not: valid: yaml")

    report, status, stderr = run_frontier

    assert status.success?, stderr
    assert_equal 0, report.dig("scope", "unrelated_files_scanned")
    refute report.fetch("checked").any? { |row| row.fetch("path") == relative(unrelated) }
  end

  def test_ddi_byte_drift_blocks_exact_binding
    @ddi.open("ab") { |file| file.write("\n# drift\n") }

    report, status, = run_frontier

    refute status.success?
    codes = report.fetch("blockers").map { |row| row.fetch("code") }
    assert_includes codes, "ddi_binding_sha256_mismatch"
    assert_includes codes, "sha256_mismatch"
  end

  def test_tampered_selection_row_hash_is_rejected
    pointer = load_yaml(@pointer)
    pointer.dig("frontier_binding", "selection")["row_sha256"] = "0" * 64
    @pointer.write(YAML.dump(pointer))

    report, status, = run_frontier

    refute status.success?
    assert_includes report.fetch("blockers").map { |row| row.fetch("code") }, "frontier_selection_stale"
  end

  def test_canonical_artifact_from_another_run_is_blocked
    other_run = ROOT.join("runs", "harness-test", "frontier-check", "OTHER_#{SecureRandom.hex(5).upcase}")
    artifact = other_run.join("research", "canonical.yaml")
    artifact.dirname.mkpath
    artifact.write("status: foreign\n")
    head = {
      "head_id" => "HEAD_FOREIGN",
      "logical_artifact_id" => "ARTIFACT_HEAD_FOREIGN",
      "stage_id" => "front_planning_integration",
      "artifact" => binding(artifact, "canonical_artifact"),
      "source_dispatch_id" => "DISPATCH_PROMOTED",
      "supersession_state" => "none",
      "state" => "current"
    }
    write_ddi(
      dispatches: [{"dispatch_id" => "DISPATCH_PROMOTED", "lifecycle" => {"current_state" => "promoted"}, "next_action_ids" => []}],
      heads: [head],
      entry_count: 1
    )
    build_pointer

    report, status, = run_frontier

    refute status.success?
    assert_includes report.fetch("blockers").map { |row| row.fetch("code") }, "selected_path_outside_run"
  ensure
    FileUtils.remove_entry(other_run) if other_run&.directory?
  end

  def test_positional_run_must_match_current_next
    report, status, = run_frontier("runs/harness-test/frontier-check/NOT_SELECTED")

    refute status.success?
    assert_includes report.fetch("blockers").map { |row| row.fetch("code") }, "run_argument_mismatch"
  end

  def test_active_frontier_rejects_legacy_v1
    @pointer.write(ROOT.join("automation", "current-next.yaml").read)

    report, status, = run_frontier

    refute status.success?
    assert_includes report.fetch("blockers").map { |row| row.fetch("code") }, "active_pointer_version_invalid"
  end

  def test_active_frontier_rejects_null_selected_migration_hold
    write_ddi(dispatches: [], heads: [], actions: [], entry_count: 0)
    build_pointer

    report, status, = run_frontier

    refute status.success?
    assert_equal "migration_hold", load_yaml(@pointer).dig("frontier_binding", "selection", "kind")
    assert_includes report.fetch("blockers").map { |row| row.fetch("code") }, "frontier_selection_missing"
  end

  def test_full_audit_delegates_to_existing_checker
    report, _status, = run_frontier("--full-audit")

    assert_equal "full_audit", report.dig("scope", "mode")
    assert report.fetch("checked").any? { |row| row.fetch("id") == "full_audit" }
  end

  private

  def write_ddi(dispatches:, actions: [], heads: [], holds: [], reviews: [], entry_count: nil)
    source_set_sha = "1" * 64
    @ddi.write(YAML.dump(
      "schema_version" => "idol-director-dispatch-index.v4",
      "run" => relative(@run),
      "source_set_sha256" => source_set_sha,
      "source_set_digest" => {"sha256" => source_set_sha},
      "dispatch_source_set" => {"entry_count" => entry_count.nil? ? dispatches.length : entry_count},
      "dispatches" => dispatches,
      "review_queue" => {"selection_order" => "dependency_rank_then_returned_at_then_dispatch_id", "items" => reviews},
      "current_heads" => heads,
      "holds" => holds,
      "next_actions" => actions
    ))
  end

  def build_pointer
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      CURRENT_NEXT.to_s,
      relative(@run),
      "--output-yaml", relative(@pointer),
      "--output-md", relative(@readout),
      "--write",
      chdir: ROOT.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
  end

  def run_frontier(*extra_args)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      "--current-next", @pointer.to_s,
      "--json",
      *extra_args,
      chdir: ROOT.to_s
    )
    [JSON.parse(stdout), status, stderr]
  rescue JSON::ParserError => error
    flunk("frontier checker did not emit JSON: #{error.message}\nstdout=#{stdout}\nstderr=#{stderr}")
  end

  def load_yaml(path)
    YAML.safe_load(path.read, aliases: false)
  end

  def binding(path, role)
    {"path" => relative(path), "sha256" => Digest::SHA256.file(path).hexdigest, "role" => role}
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def prune_empty(path, stop)
    current = path
    while current.to_s.start_with?(stop.to_s) && current != stop && current.directory? && current.children.empty?
      current.rmdir
      current = current.parent
    end
  end
end
