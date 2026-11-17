# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class IdolVideoReferenceHubAuditTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_video_reference_hub_audit.rb")

  def test_short_source_and_selected_range_cadence_are_machine_auditable
    Dir.mktmpdir("idol-video-hub-audit-", "/private/tmp") do |directory|
      hub = Pathname.new(directory)
      source = hub.join("youtube", "by-source", "TEST123")
      sheets = source.join("contact-sheets", "segments-5s-1s")
      analysis = source.join("analysis")
      [sheets, analysis].each(&:mkpath)

      sheet_paths = [
        sheets.join("TEST123-00000000ms-00005000ms.png"),
        sheets.join("TEST123-00005000ms-00010000ms.png"),
        sheets.join("TEST123-00010000ms-00012000ms.png")
      ]
      sheet_paths.each { |path| path.write("fixture") }
      selected = source.join("contact-sheets", "TEST123-selected-sequence.png")
      selected.write("fixture")
      selected_manifest = analysis.join("TEST123-selected-one-second.json")
      selected_manifest.write(JSON.pretty_generate("interval_seconds" => 1))
      cadence_manifest = analysis.join("cadence.json")
      cadence_manifest.write(JSON.pretty_generate("interval_seconds" => 1, "segment_duration_seconds" => 5))
      frame_index = source.join("frame-index.yaml")
      frame_index.write(YAML.dump("contact_sheet_manifest" => {"path" => cadence_manifest.to_s}))
      source.join("source-manifest.yaml").write(YAML.dump(
        "identity" => {"source_key" => "youtube:TEST123", "platform" => "youtube", "platform_id" => "TEST123"},
        "discovery_metadata" => {"duration_seconds" => 12},
        "frame_index_path" => frame_index.to_s,
        "contact_sheets" => sheet_paths.map { |path| {"path" => path.to_s, "sampling_note" => "1-second sampling"} }
      ))

      stdout, stderr, status = Open3.capture3("ruby", SCRIPT.to_s, "--hub", hub.to_s, "--json", "--strict", chdir: ROOT.to_s)
      assert status.success?, [stdout, stderr].join("\n")
      report = JSON.parse(stdout)
      assert_equal "pass", report["overall_status"]
      row = report.fetch("sources").first
      assert_equal 1, row.dig("expected_cadence", "sampling_seconds")
      assert_equal 5, row.dig("expected_cadence", "part_seconds")
      assert_equal true, row.dig("selected_range_evidence", "cadence_proven")
    end
  end
end
