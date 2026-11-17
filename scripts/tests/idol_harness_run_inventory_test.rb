# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

class IdolHarnessRunInventoryTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_harness_run_inventory.rb")
  LAYOUT_SCRIPT = ROOT.join("scripts", "idol_run_layout.py")

  def test_active_routing_attaches_only_run_owned_current_contracts
    run_id = "TEST_RUN_#{Process.pid}_#{rand(100_000)}"
    run_rel = "runs/harness-test/inventory/#{run_id}"
    run = ROOT.join(run_rel)
    begin
      _stdout, stderr, status = Open3.capture3(
        "python3",
        LAYOUT_SCRIPT.to_s,
        "init",
        "--album-key", "harness-test",
        "--title-key", "inventory",
        "--run-id", run_id,
        "--content-id", "INVENTORY_TEST",
        chdir: ROOT.to_s
      )
      assert status.success?, stderr
      run.join("00A-song-lock.yaml").write("schema_version: '1.5'\n")

      stdout, _stderr, _status = Open3.capture3("ruby", SCRIPT.to_s, run_rel, "--json", chdir: ROOT.to_s)
      report = JSON.parse(stdout)
      artifacts = report.fetch("stage_connections").flat_map { |stage| stage.fetch("artifacts") }
      refute artifacts.any? { |artifact| artifact.fetch("path").start_with?("automation/") }
      song_lock = artifacts.find { |artifact| artifact.fetch("path").end_with?("00A-song-lock.yaml") }
      refute_nil song_lock
      assert_equal "song_lock", song_lock["contract_id"]
      assert_equal "current", song_lock["version_status"]
      assert_equal "harness-test", report["album_key"]
      assert_equal "inventory", report["title_key"]
      assert_equal run_id, report["run_id"]
      assert_equal "album_layout", report["layout_status"]
      assert_equal "runs/harness-test/inventory/#{run_id}/run-manifest.yaml", report.dig("run_identity", "path")
    ensure
      FileUtils.rm_rf(run) if run.exist?
    end
  end
end
