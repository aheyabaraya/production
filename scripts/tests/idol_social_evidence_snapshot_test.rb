# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolSocialEvidenceSnapshotTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_social_evidence_snapshot.rb")
  CONTENT_ID = "SOCIAL_EVIDENCE_TEST"

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-social-evidence-"))
    @run = @tmp.join("runs", "aurora-m", "social-evidence-test", CONTENT_ID)
    @run.mkpath
    write_run_manifest(@run, CONTENT_ID)
    @posts = @tmp.join("analytics", "records", "platform-posts.jsonl")
    @metrics = @tmp.join("analytics", "records", "platform-metrics.jsonl")
    @posts.dirname.mkpath
    @posts.write("")
    @metrics.write("")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def write_run_manifest(run, content_id)
    run_id = run.basename.to_s
    run.join("run-manifest.yaml").write(
      YAML.dump(
        {
          "schema_version" => "idol-run-manifest.v1",
          "status" => "active",
          "album_key" => "aurora-m",
          "title_key" => "social-evidence-test",
          "run_id" => run_id,
          "content_id" => content_id,
          "canonical_run_root" => "runs/aurora-m/social-evidence-test/#{run_id}",
          "artifact_revision_owner" => "git",
          "compatibility_authoring" => "forbidden"
        }
      )
    )
  end

  def post_row(status: "planned", post_id: "POST-1")
    {
      "post_id" => post_id,
      "content_id" => CONTENT_ID,
      "platform" => "youtube",
      "template_type" => "youtube_full_master",
      "message" => "full master",
      "asset_or_clip" => "exports/master.mp4",
      "caption" => "Loom",
      "hashtags" => ["#Loom"],
      "scheduled_at" => "2026-07-10T12:00:00+09:00",
      "status" => status,
      "analysis_scope" => "date_based",
      "published_at" => status == "published" ? "2026-07-10T12:05:00+09:00" : "",
      "platform_post_id" => status == "published" ? "YT-1" : "",
      "published_url" => status == "published" ? "https://example.invalid/YT-1" : ""
    }
  end

  def metric_row(captured_at:, views:, post_id: "POST-1")
    {
      "captured_at" => captured_at,
      "observed_date" => "2026-07-10",
      "post_id" => post_id,
      "content_id" => CONTENT_ID,
      "platform" => "youtube",
      "views" => views,
      "engagement" => 3,
      "watch_retention" => nil,
      "completion_rate" => nil,
      "source" => "manual"
    }
  end

  def write_jsonl(path, rows)
    path.write(rows.map { |row| JSON.generate(row) }.join("\n") + (rows.empty? ? "" : "\n"))
  end

  def build_snapshot
    output = @run.join("analytics", "social-evidence-snapshot-v3.yaml")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      @run.to_s,
      "--content-id", CONTENT_ID,
      "--root", @tmp.to_s,
      "--posts", @posts.to_s,
      "--metrics", @metrics.to_s,
      "--output", output.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    YAML.safe_load(output.read, permitted_classes: [], permitted_symbols: [], aliases: true)
  end

  def run_snapshot(*extra_args, run: @run, content_id: CONTENT_ID, posts: @posts, metrics: @metrics)
    output = run.join("analytics", "social-evidence-snapshot-v3.yaml")
    Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      run.to_s,
      "--content-id", content_id,
      "--root", @tmp.to_s,
      "--posts", posts.to_s,
      "--metrics", metrics.to_s,
      "--output", output.to_s,
      "--write",
      *extra_args,
      chdir: ROOT.to_s
    )
  end

  def test_no_rows_are_an_explicit_non_inferential_state
    snapshot = build_snapshot
    assert_equal "no_evidence_yet", snapshot["status"]
    assert_equal "no_post_records", snapshot["evidence_status"]
    assert_equal "canonical", snapshot.dig("ledger_scope", "mode")
    assert_equal 0, snapshot.dig("summary", "metric_count")
    assert_equal "no_release_trace", snapshot.dig("production_graph_evidence", "status")
  end

  def test_v3_carries_release_output_to_edit_graph_without_mutating_source_truth
    traced = post_row(status: "published").merge(
      "release_provenance_version" => "idol_release_provenance.v2",
      "release_package_contract" => "runs/aurora-m/social-evidence-test/#{CONTENT_ID}/05-package.yaml",
      "release_package_contract_sha256" => "1" * 64,
      "release_package_deliverable_manifest_sha256" => "2" * 64,
      "release_package_output_id" => "OUT_SOCIAL_MASTER",
      "release_package_output_role" => "final_public_master",
      "release_package_linkage" => "exact_deliverable",
      "release_production_graph_trace_sha256" => "3" * 64,
      "release_edit_segment_ids" => ["SEG_RELEASE_R01"],
      "release_screen_progression_node_ids" => ["SPN_RELEASE_R01"],
      "release_section_ids" => ["S01"],
      "release_asset_sha256" => "4" * 64
    )
    write_jsonl(@posts, [traced])
    write_jsonl(@metrics, [metric_row(captured_at: "2026-07-10T13:00:00+09:00", views: 10)])

    snapshot = build_snapshot
    fact = snapshot.fetch("post_facts").first
    assert_equal "complete", snapshot.dig("production_graph_evidence", "status")
    assert_equal ["POST-1"], snapshot.dig("production_graph_evidence", "traceable_post_ids")
    assert_equal ["SEG_RELEASE_R01"], fact["release_edit_segment_ids"]
    assert_equal ["SPN_RELEASE_R01"], fact["release_screen_progression_node_ids"]
    assert_includes snapshot.fetch("automation_boundaries").last, "never patches"
  end

  def test_legacy_release_package_fields_do_not_impersonate_v2_provenance
    legacy = post_row(status: "published").merge(
      "release_package_contract" => "runs/aurora-m/social-evidence-test/#{CONTENT_ID}/05-package.yaml",
      "release_package_contract_sha256" => "1" * 64,
      "release_package_output_id" => "OUT_LEGACY"
    )
    write_jsonl(@posts, [legacy])
    snapshot = build_snapshot
    assert_equal "no_release_trace", snapshot.dig("production_graph_evidence", "status")
    assert_equal ["POST-1"], snapshot.dig("production_graph_evidence", "missing_trace_post_ids")
  end

  def test_run_identity_content_id_must_match_requested_content_id
    wrong_run = @tmp.join("runs", "aurora-m", "social-evidence-test", "WRONG_CONTENT")
    wrong_run.mkpath
    write_run_manifest(wrong_run, "WRONG_CONTENT")
    _stdout, stderr, status = run_snapshot(run: wrong_run)
    refute status.success?
    assert_includes stderr, "run identity content_id must match --content-id #{CONTENT_ID}"
  end

  def test_custom_ledgers_require_audited_override_reason
    custom_posts = @tmp.join("fixtures", "posts.jsonl")
    custom_metrics = @tmp.join("fixtures", "metrics.jsonl")
    custom_posts.dirname.mkpath
    custom_posts.write("")
    custom_metrics.write("")

    _stdout, stderr, status = run_snapshot(posts: custom_posts, metrics: custom_metrics)
    refute status.success?
    assert_includes stderr, "noncanonical ledger paths require --ledger-override-reason"

    stdout, stderr, status = run_snapshot(
      "--ledger-override-reason", "Isolated fixture ledgers for audited contract testing.",
      posts: custom_posts,
      metrics: custom_metrics
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    snapshot = YAML.safe_load(@run.join("analytics/social-evidence-snapshot-v3.yaml").read, permitted_classes: [], permitted_symbols: [], aliases: true)
    assert_equal "audited_override", snapshot.dig("ledger_scope", "mode")
  end

  def test_planned_post_is_not_treated_as_published
    write_jsonl(@posts, [post_row])
    snapshot = build_snapshot
    assert_equal "posts_without_published_facts", snapshot["evidence_status"]
    assert_equal 0, snapshot.dig("summary", "published_count")
  end

  def test_published_without_metrics_stays_explicit
    write_jsonl(@posts, [post_row(status: "published")])
    snapshot = build_snapshot
    assert_equal "published_without_metrics", snapshot["evidence_status"]
  end

  def test_published_fact_requires_timestamp_and_platform_identity_or_https_url
    invalid = post_row(status: "published")
    invalid["platform_post_id"] = ""
    invalid["published_url"] = ""
    write_jsonl(@posts, [invalid])

    _stdout, stderr, status = run_snapshot
    refute status.success?
    assert_includes stderr, "requires platform_post_id or HTTPS published_url evidence"
  end

  def test_partial_metric_coverage_stays_non_conclusive_and_lists_missing_posts
    second = post_row(status: "published", post_id: "POST-2").merge(
      "platform_post_id" => "YT-2",
      "published_url" => "https://example.invalid/YT-2"
    )
    write_jsonl(@posts, [post_row(status: "published"), second])
    write_jsonl(@metrics, [metric_row(captured_at: "2026-07-10T13:00:00+09:00", views: 10)])

    snapshot = build_snapshot
    assert_equal "published_partial_metrics", snapshot["evidence_status"]
    assert_equal ["POST-2"], snapshot.dig("summary", "missing_metric_post_ids")
  end

  def test_invalid_source_ledger_does_not_replace_existing_snapshot
    output = @run.join("analytics", "social-evidence-snapshot-v3.yaml")
    output.dirname.mkpath
    output.write("existing-valid-snapshot\n")
    invalid = post_row
    invalid.delete("caption")
    write_jsonl(@posts, [invalid])

    _stdout, stderr, status = run_snapshot
    refute status.success?
    assert_includes stderr, "source social ledger validation failed"
    assert_equal "existing-valid-snapshot\n", output.read
  end

  def test_measured_snapshot_keeps_latest_same_day_metric_and_stable_subset_digest
    write_jsonl(@posts, [post_row(status: "published")])
    write_jsonl(@metrics, [
      metric_row(captured_at: "2026-07-10T13:00:00+09:00", views: 10),
      metric_row(captured_at: "2026-07-10T14:00:00+09:00", views: 20)
    ])
    first = build_snapshot
    assert_equal "measured", first["evidence_status"]
    assert_equal 2, first.dig("summary", "metric_count")
    assert_equal 1, first.dig("summary", "latest_metric_count")
    assert_equal 20, first.fetch("metric_facts").first["views"]
    assert_empty first.dig("summary", "missing_metric_post_ids")

    unrelated = post_row(post_id: "OTHER-1").merge("content_id" => "OTHER_CONTENT")
    File.open(@posts, "a") { |file| file.puts(JSON.generate(unrelated)) }
    second = build_snapshot
    assert_equal first["source_set_sha256"], second["source_set_sha256"]
    refute_equal first.dig("source_ledgers", 0, "sha256"), second.dig("source_ledgers", 0, "sha256")
  end

  def test_v2_preserves_multi_lane_lineage_and_distinct_fixed_checkpoints
    root = post_row(status: "published", post_id: "POST-X-ROOT").merge(
      "platform" => "x",
      "template_type" => "work_root",
      "content_lane" => "mv_cutdown",
      "format_family" => "video",
      "content_pillar" => "loom_idol_member",
      "primary_channel_job" => "discovery",
      "member" => ["M02"],
      "member_intro_line" => "Seorin is holding the last frame.",
      "analysis_scope" => "scheduler_whitelist",
      "platform_post_id" => "X-ROOT",
      "published_url" => "https://example.invalid/X-ROOT"
    )
    derived = post_row(status: "published", post_id: "POST-YS-DERIVED").merge(
      "platform" => "youtube_shorts",
      "template_type" => "derived_clip",
      "content_lane" => "derived_clip_3_8",
      "format_family" => "video",
      "content_pillar" => "loom_idol_member",
      "primary_channel_job" => "discovery",
      "shared_media_source_post_id" => "POST-X-ROOT",
      "platform_post_id" => "YS-DERIVED",
      "published_url" => "https://example.invalid/YS-DERIVED"
    )
    write_jsonl(@posts, [root, derived])
    checkpoint_24 = metric_row(
      captured_at: "2026-07-10T13:00:00+09:00",
      views: 10,
      post_id: "POST-YS-DERIVED"
    ).merge(
      "platform" => "youtube_shorts",
      "measurement_window" => "T+24h",
      "checkpoint_target_at" => "2026-07-10T12:00:00+09:00",
      "checkpoint_lag_seconds" => 3600
    )
    checkpoint_72 = checkpoint_24.merge(
      "captured_at" => "2026-07-10T14:00:00+09:00",
      "views" => 20,
      "measurement_window" => "T+72h",
      "checkpoint_target_at" => "2026-07-10T13:00:00+09:00"
    )
    write_jsonl(@metrics, [checkpoint_24, checkpoint_72])

    snapshot = build_snapshot
    assert_equal "idol_social_evidence_snapshot.v3", snapshot["schema_version"]
    assert_equal 2, snapshot.dig("summary", "selected_metric_count")
    assert_equal({"T+24h" => 1, "T+72h" => 1}, snapshot.dig("summary", "measurement_window_counts"))
    assert_equal({"derived_clip" => 1, "work_root" => 1}, snapshot.dig("summary", "content_family_post_counts"))
    assert_equal 1, snapshot.dig("summary", "shared_media_post_count")
    assert_equal %w[T+24h T+72h], snapshot.fetch("metric_facts").map { |fact| fact["measurement_window"] }.sort
    derived_fact = snapshot.fetch("post_facts").find { |fact| fact["post_id"] == "POST-YS-DERIVED" }
    assert_equal "derived_clip", derived_fact["content_family"]
    assert_equal "POST-X-ROOT", derived_fact["shared_media_source_post_id"]
  end
end
