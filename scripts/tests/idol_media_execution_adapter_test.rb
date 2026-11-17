# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_03v_fixture"

class IdolMediaExecutionAdapterTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_media_execution_adapter.rb")

  def teardown
    FileUtils.remove_entry(@package_root) if @package_root&.exist?
    @fixture&.cleanup
  end

  def test_video_dry_run_projects_exact_one_frame_i2v_without_external_call
    @fixture = Active03VFixture.create(branch_count: 2, include_official_core: true)
    path = write_manifest(@fixture.video_manifest_document)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, "video", path.to_s, "--cue-id", "03VCUE_C01_01", "--dry-run", chdir: ROOT.to_s)
    assert status.success?, stderr
    plan = JSON.parse(stdout)
    assert_equal false, plan["external_call_performed"]
    assert_equal "official_core", plan["source_cut_type"]
    assert_equal "image_to_video", plan["selected_tool"]
    assert_equal "forbidden", plan["prompt_rewrite_policy"]
  end

  def test_write_package_copies_validated_branch_placement_upscale
    @fixture = Active03VFixture.create(branch_count: 2)
    path = write_manifest(@fixture.video_manifest_document)
    @package_root = Pathname.new("/private/tmp").join(format("idol-g05-branch-pkg-%d-%x", Process.pid, object_id))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      "video",
      path.to_s,
      "--cue-id",
      "03VCUE_C01_01",
      "--dry-run",
      "--write-package",
      "--package-root",
      @package_root.to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, stderr
    plan = JSON.parse(stdout)
    selected = plan.fetch("ordered_inputs").fetch(0)
    unit = @fixture.source_fixture.placement.fetch("production_cut_units").find do |row|
      row.fetch("production_cut_id") == selected.fetch("production_cut_id")
    end
    assert_equal "branch", selected.fetch("production_cut_type")
    assert_equal unit.dig("placement_image", "sha256"), selected.fetch("source_sha256")
    assert_equal unit.dig("passed_source_image", "sha256"), selected.fetch("reviewed_original_sha256")
    refute_equal selected.fetch("source_sha256"), selected.fetch("reviewed_original_sha256")
    package = Pathname.new(plan.dig("materialized_package", "package_path"))
    copied = package.join("input-01.png")
    assert copied.file?
    assert_equal unit.dig("placement_image", "sha256"), Digest::SHA256.file(copied).hexdigest
    assert_equal @fixture.video_manifest_document.fetch("cues").first.fetch("prompt_text"), package.join("prompt.txt").read
  end

  def test_adapter_refuses_non_dry_run
    @fixture = Active03VFixture.create(branch_count: 1, include_official_core: true)
    path = write_manifest(@fixture.video_manifest_document)
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, "video", path.to_s, "--cue-id", "03VCUE_C01_01", chdir: ROOT.to_s)
    refute status.success?
    assert_includes stderr, "--dry-run is mandatory"
  end

  private

  def write_manifest(document)
    path = @fixture.run_dir.join("03V-video-prompt-manifest.yaml")
    path.write(YAML.dump(document))
    path
  end
end
