# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolMvGitWorktreeTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("../..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_mv_git_worktree.rb")

  def setup
    @holder = Dir.mktmpdir("idol-mv-git-worktree-test-")
    @repo = Pathname.new(@holder).join("repo")
    @repo.mkpath
    git("init", "-b", "main")
    git("config", "user.name", "IDOL Test")
    git("config", "user.email", "idol-test@example.invalid")
    @repo.join("README.md").write("fixture\n")
    git("add", "README.md")
    git("commit", "-m", "fixture")
    @main_sha = git("rev-parse", "HEAD").strip
  end

  def teardown
    FileUtils.remove_entry(@holder) if @holder && File.exist?(@holder)
  end

  def git(*arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", @repo.to_s, *arguments)
    raise stderr unless status.success?
    stdout
  end

  def run_script(*arguments)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      *arguments,
      "--repo",
      @repo.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def test_init_run_dry_run_projects_only_main_integration_edges
    worktree = Pathname.new(@holder).join("dry-run-worktree")
    result = run_script(
      "init-run",
      "--run-root", "runs/aurora-m/color-stay/20260830_COLOR_STAY_MV",
      "--base-sha", @main_sha,
      "--worktree", worktree.to_s
    )

    assert result[:status].success?, result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "dry_run", payload.fetch("status")
    assert_equal "mv/aurora-m/color-stay/20260830_color_stay_mv/integration", payload.fetch("branch")
    assert_equal %w[branched_from reviewed_merge_candidate_for], payload.dig("execution_graph", "edges").map { |row| row.fetch("edge_type") }
    refute worktree.exist?
  end

  def test_init_run_apply_creates_exact_branch_and_worktree_at_main_sha
    worktree = Pathname.new(@holder).join("run-integration")
    result = run_script(
      "init-run",
      "--run-root", "runs/aurora-m/color-stay/20260830_COLOR_STAY_MV",
      "--base-sha", @main_sha,
      "--worktree", worktree.to_s,
      "--apply"
    )

    assert result[:status].success?, result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "created", payload.fetch("status")
    assert worktree.directory?
    assert_equal payload.fetch("branch"), Open3.capture3("git", "-C", worktree.to_s, "branch", "--show-current").first.strip
    assert_equal @main_sha, Open3.capture3("git", "-C", worktree.to_s, "rev-parse", "HEAD").first.strip
  end

  def test_stale_main_sha_fails_without_creating_branch
    worktree = Pathname.new(@holder).join("stale")
    result = run_script(
      "init-run",
      "--run-root", "runs/aurora-m/color-stay/20260830_COLOR_STAY_MV",
      "--base-sha", "0" * 40,
      "--worktree", worktree.to_s,
      "--apply"
    )

    refute result[:status].success?
    assert_includes result[:stderr], "main SHA is stale"
    refute worktree.exist?
  end

  def test_open_lane_dry_run_derives_dispatch_bound_branch_and_write_scope
    integration = "mv/aurora-m/color-stay/20260830_color_stay_mv/integration"
    git("branch", integration, @main_sha)
    dispatch_path = @repo.join("runs/aurora-m/color-stay/20260830_COLOR_STAY_MV/work/dispatch.yaml")
    dispatch_path.dirname.mkpath
    dispatch_path.write(YAML.dump({
      "schema_version" => "idol-department-dispatch.v8",
      "dispatch_id" => "COLOR-STAY-S01-02B",
      "run" => "runs/aurora-m/color-stay/20260830_COLOR_STAY_MV",
      "lifecycle" => {"current_state" => "prepared"},
      "launch" => {
        "task" => {
          "task_id" => "COLOR-STAY-S01-02B",
          "exact_scope" => {
            "stage_id" => "image_prompt_compilation",
            "section_ids" => ["S01"],
            "artifact_paths" => ["runs/aurora-m/color-stay/20260830_COLOR_STAY_MV/02b/S01.yaml"]
          }
        },
        "authority" => {
          "assigned_owner" => "section_image_motion_worker",
          "canonical_write" => "bounded_to_expected_paths"
        },
        "bounded_output" => {
          "expected_paths" => ["runs/aurora-m/color-stay/20260830_COLOR_STAY_MV/02b/S01.yaml"]
        }
      },
      "routing_identity" => {"return_recipient_role" => "creative_development_director"}
    }))
    worktree = Pathname.new(@holder).join("lane")
    result = run_script(
      "open-lane",
      "--dispatch", dispatch_path.relative_path_from(@repo).to_s,
      "--base-sha", @main_sha,
      "--worktree", worktree.to_s
    )

    assert result[:status].success?, result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "deferred_until_apply", payload.fetch("dispatch_validation")
    assert_equal "mv/aurora-m/color-stay/20260830_color_stay_mv/lane/image_prompt_compilation/color-stay-s01-02b", payload.fetch("branch")
    assert_equal ["runs/aurora-m/color-stay/20260830_COLOR_STAY_MV/02b/S01.yaml"], payload.dig("dispatch", "write_paths")
    refute worktree.exist?
  end

  def test_rejects_non_mv_run_and_nested_worktree_path
    nested = @repo.join("nested")
    result = run_script(
      "init-run",
      "--run-root", "runs/2026-08-30/HARNESS",
      "--base-sha", @main_sha,
      "--worktree", nested.to_s
    )

    refute result[:status].success?
    assert_includes result[:stderr], "runs/ALBUM_KEY/TITLE_KEY/RUN_ID"

    nested_result = run_script(
      "init-run",
      "--run-root", "runs/aurora-m/color-stay/20260830_COLOR_STAY_MV",
      "--base-sha", @main_sha,
      "--worktree", nested.to_s
    )
    refute nested_result[:status].success?
    assert_includes nested_result[:stderr], "outside the current repository worktree"
  end
end
