# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class LoomSnsCohortSnapshotTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join(
    "business-marketing",
    "skills",
    "loom-sns-cohort-analysis",
    "scripts",
    "build_snapshot.rb"
  )

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("loom-sns-cohort-snapshot-"))
    @posts = @tmp.join("platform-posts.jsonl")
    @metrics = @tmp.join("platform-metrics.jsonl")
    @observations = @tmp.join("cohort-observations.jsonl")
    @output = @tmp.join("snapshot.yaml")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def write_jsonl(path, rows)
    path.write(rows.map { |row| JSON.generate(row) }.join("\n") + "\n")
  end

  def post_row(post_id:, published_at:)
    {
      "post_id" => post_id,
      "content_id" => "COHORT_WINDOW_TEST",
      "platform" => "youtube",
      "template_type" => "youtube_full_master",
      "message" => "window test",
      "asset_or_clip" => "exports/test.mp4",
      "caption" => "Loom cohort window test",
      "hashtags" => %w[#AI #AIIdol #Kpop #VirtualIdol #Loom],
      "scheduled_at" => published_at,
      "published_at" => published_at,
      "platform_post_id" => post_id,
      "status" => "published",
      "analysis_scope" => "date_based"
    }
  end

  def metric_row(post_id:, captured_at:)
    {
      "captured_at" => captured_at,
      "observed_date" => captured_at[0, 10],
      "post_id" => post_id,
      "content_id" => "COHORT_WINDOW_TEST",
      "platform" => "youtube",
      "views" => 10,
      "engagement" => 1,
      "source" => "manual"
    }
  end

  def observation_row(window_start:, window_end:)
    {
      "cohort_id" => "LSC0",
      "platform" => "youtube",
      "window_start" => window_start,
      "window_end" => window_end,
      "numerator" => 2,
      "denominator" => 10,
      "source" => "privacy_safe_test_fixture",
      "eligibility_rule" => "aggregate only",
      "capture_method" => "manual aggregate"
    }
  end

  def build_snapshot
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      "--root", ROOT.to_s,
      "--posts", @posts.to_s,
      "--metrics", @metrics.to_s,
      "--observations", @observations.to_s,
      "--output", @output.to_s,
      "--as-of", "2026-07-30",
      "--write",
      chdir: ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    YAML.safe_load(@output.read, permitted_classes: [], permitted_symbols: [], aliases: true)
  end

  def test_rolling_window_excludes_old_posts_metrics_and_observations
    write_jsonl(@posts, [
      post_row(post_id: "OLD", published_at: "2026-06-17T12:00:00+09:00"),
      post_row(post_id: "CURRENT", published_at: "2026-07-03T12:00:00+09:00")
    ])
    write_jsonl(@metrics, [
      metric_row(post_id: "OLD", captured_at: "2026-07-30T09:00:00+09:00"),
      metric_row(post_id: "CURRENT", captured_at: "2026-07-30T09:00:00+09:00")
    ])
    write_jsonl(@observations, [
      observation_row(window_start: "2026-06-01", window_end: "2026-06-28"),
      observation_row(window_start: "2026-07-03", window_end: "2026-07-30")
    ])

    snapshot = build_snapshot
    assert_equal "2026-07-03", snapshot["window_start"]
    assert_equal "2026-07-30", snapshot["window_end"]
    assert_equal 1, snapshot.dig("publication_coverage", "published_post_count")
    assert_equal 1, snapshot.dig("publication_coverage", "measured_published_post_count")
    assert_equal 1, snapshot.dig("sources", "platform_metrics", "current_window_row_count")
    assert_equal 1, snapshot.dig("sources", "cohort_observations", "current_window_row_count")
    assert_equal ["LSC0"], snapshot["populated_cohort_ids"]
  end

  def test_historical_metrics_do_not_make_an_empty_current_window_look_populated
    write_jsonl(@posts, [
      post_row(post_id: "OLD", published_at: "2026-06-17T12:00:00+09:00")
    ])
    write_jsonl(@metrics, [
      metric_row(post_id: "OLD", captured_at: "2026-07-30T09:00:00+09:00")
    ])
    write_jsonl(@observations, [])

    snapshot = build_snapshot
    assert_equal "defined_not_populated", snapshot["status"]
    assert_equal 0, snapshot.dig("publication_coverage", "published_post_count")
    assert_nil snapshot.dig("publication_coverage", "metric_coverage_rate")
    assert_equal 1, snapshot.dig("historical_context", "excluded_metric_row_count")
    assert_includes snapshot["access_issues"], "No published post facts fall inside the current rolling 28-day window."
  end

  def test_snapshot_groups_expanded_lanes_into_cross_platform_content_families
    root = post_row(post_id: "ROOT", published_at: "2026-07-10T12:00:00+09:00").merge(
      "platform" => "x",
      "template_type" => "work_root",
      "content_lane" => "cf_film_drop",
      "content_pillar" => "cf_finish",
      "primary_channel_job" => "discovery",
      "analysis_scope" => "scheduler_whitelist"
    )
    derived = post_row(post_id: "DERIVED", published_at: "2026-07-11T12:00:00+09:00").merge(
      "platform" => "youtube_shorts",
      "template_type" => "derived_clip",
      "content_lane" => "derived_clip_3_8",
      "content_pillar" => "cf_finish",
      "primary_channel_job" => "discovery",
      "shared_media_source_post_id" => "ROOT"
    )
    write_jsonl(@posts, [root, derived])
    write_jsonl(@metrics, [
      metric_row(post_id: "DERIVED", captured_at: "2026-07-12T12:00:00+09:00").merge(
        "platform" => "youtube_shorts",
        "measurement_window" => "T+24h",
        "checkpoint_target_at" => "2026-07-12T12:00:00+09:00",
        "checkpoint_lag_seconds" => 0
      )
    ])
    write_jsonl(@observations, [])

    snapshot = build_snapshot
    assert_equal "loom_sns_cohort_snapshot.v2", snapshot["schema_version"]
    assert_equal({"derived_clip" => 1, "work_root" => 1}, snapshot.dig("analysis_dimensions", "content_family_post_counts"))
    assert_equal({"T+24h" => 1}, snapshot.dig("analysis_dimensions", "measurement_window_counts"))
    assert_equal 1, snapshot.dig("analysis_dimensions", "shared_media_post_count")
    assert_equal({"derived_clip" => 1, "work_root" => 1}, snapshot.dig("analysis_dimensions", "work_content_family_counts", "COHORT_WINDOW_TEST"))
  end
end
