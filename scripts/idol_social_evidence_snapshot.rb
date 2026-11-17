#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "time"
require "yaml"
require_relative "lib/idol_run_layout"
require_relative "lib/idol_social_taxonomy"

TOOL_ROOT = Pathname.new(__dir__).join("..").expand_path

def fail_usage(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_social_evidence_snapshot.rb RUN_ROOT --content-id ID [--root PATH] [--posts PATH] [--metrics PATH] [--ledger-override-reason REASON] [--output PATH] [--write]"
  exit 2
end

def canonicalize_path(path)
  expanded = path.expand_path
  return expanded.realpath if expanded.exist?

  suffix = []
  ancestor = expanded
  until ancestor.exist? || ancestor.root?
    suffix.unshift(ancestor.basename.to_s)
    ancestor = ancestor.parent
  end
  base = ancestor.exist? ? ancestor.realpath : ancestor
  suffix.reduce(base) { |current, part| current.join(part) }
rescue Errno::ENOENT, Errno::EACCES
  expanded
end

def resolve_path(value, root)
  raw = Pathname.new(value.to_s)
  canonicalize_path(raw.absolute? ? raw : (root + raw))
end

def display_path(path, root)
  path.relative_path_from(root).to_s
rescue ArgumentError
  path.to_s
end

def within?(path, owner)
  candidate = path.expand_path.to_s
  boundary = owner.expand_path.to_s
  candidate == boundary || candidate.start_with?("#{boundary}/")
end

def output_parent_within_run?(path, run_path)
  return false unless within?(path, run_path)

  ancestor = path.dirname
  ancestor = ancestor.parent until ancestor.exist? || ancestor.root?
  ancestor.exist? && within?(ancestor.realpath, run_path.realpath)
rescue Errno::ENOENT, Errno::EACCES
  false
end

def sha256_file(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def verify_ledger_unchanged!(path, expected_sha256, label)
  actual_sha256 = sha256_file(path)
  return if actual_sha256 == expected_sha256

  fail_usage("#{label} ledger changed while the snapshot was being built; retry from a stable source")
end

def load_jsonl(path, label, root)
  fail_usage("#{label} ledger is not readable: #{display_path(path, root)}") unless File.file?(path)

  records = []
  File.foreach(path).with_index(1) do |line, line_no|
    raw = line.strip
    next if raw.empty?

    begin
      row = JSON.parse(raw)
    rescue JSON::ParserError => e
      fail_usage("#{label}:#{line_no}: invalid JSON: #{e.message}")
    end
    fail_usage("#{label}:#{line_no}: row must be an object") unless row.is_a?(Hash)
    records << {"line_no" => line_no, "row" => row, "row_sha256" => Digest::SHA256.hexdigest(raw)}
  end
  records
end

def validate_source_ledgers(posts_path, metrics_path, root)
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    (TOOL_ROOT + "scripts/validate_social_analytics.rb").to_s,
    posts_path.to_s,
    metrics_path.to_s,
    chdir: root.to_s
  )
  return if status.success?

  fail_usage("source social ledger validation failed: #{[stdout, stderr].join(' ').strip}")
end

def https_url?(value)
  value.to_s.match?(%r{\Ahttps://\S+\z})
end

def validate_published_fact!(item)
  row = item.fetch("row")
  return unless row["status"].to_s == "published"

  post_id = row["post_id"].to_s
  published_at = row["published_at"].to_s
  platform_post_id = row["platform_post_id"].to_s.strip
  published_url = row["published_url"].to_s.strip
  fail_usage("published post #{post_id} requires published_at") if published_at.empty?
  begin
    Time.iso8601(published_at)
  rescue ArgumentError
    fail_usage("published post #{post_id} has invalid published_at")
  end
  if !published_url.empty? && !https_url?(published_url)
    fail_usage("published post #{post_id} published_url must be HTTPS")
  end
  if platform_post_id.empty? && !https_url?(published_url)
    fail_usage("published post #{post_id} requires platform_post_id or HTTPS published_url evidence")
  end
end

def normalized_time(value)
  Time.iso8601(value.to_s)
rescue ArgumentError
  Time.at(0)
end

def post_fact(item)
  row = item.fetch("row")
  fact = {
    "post_id" => row["post_id"].to_s,
    "platform" => row["platform"].to_s,
    "template_type" => row["template_type"].to_s,
    "content_family" => IdolSocialTaxonomy.content_family(row),
    "format_family" => IdolSocialTaxonomy.format_family(row),
    "member_codes" => IdolSocialTaxonomy.member_codes(row),
    "content_pillar" => row["content_pillar"].to_s.empty? ? "unclassified" : row["content_pillar"].to_s,
    "primary_channel_job" => row["primary_channel_job"].to_s.empty? ? "unclassified" : row["primary_channel_job"].to_s,
    "message" => row["message"].to_s,
    "asset_or_clip" => row["asset_or_clip"].to_s,
    "status" => row["status"].to_s,
    "scheduled_at" => row["scheduled_at"].to_s,
    "published_at" => row["published_at"].to_s,
    "platform_post_id" => row["platform_post_id"].to_s,
    "published_url" => row["published_url"].to_s,
    "row_sha256" => item.fetch("row_sha256")
  }
  %w[
    content_lane media_kind shared_media_source_post_id reply_to_post_id
    thread_role member_intro_line duration_band hook_type first_frame_type
    payoff_timestamp edit_density data_completeness release_provenance_version
    release_package_contract
    release_package_contract_sha256 release_package_deliverable_manifest_sha256
    release_package_output_id release_package_output_role release_package_linkage
    release_production_graph_trace_sha256 release_edit_segment_ids
    release_screen_progression_node_ids release_section_ids release_asset_sha256
  ].each do |field|
    fact[field] = row[field] if row.key?(field) && !row[field].to_s.empty?
  end
  fact["harness_intensity"] = row["harness_intensity"] if row.key?("harness_intensity")
  fact["known_gaps"] = row["known_gaps"] if row.key?("known_gaps")
  fact
end

def metric_fact(item)
  row = item.fetch("row")
  fact = {
    "post_id" => row["post_id"].to_s,
    "platform" => row["platform"].to_s,
    "observed_date" => row["observed_date"].to_s,
    "captured_at" => row["captured_at"].to_s,
    "views" => row["views"],
    "engagement" => row["engagement"],
    "source" => row["source"].to_s,
    "decision" => row["decision"].to_s,
    "row_sha256" => item.fetch("row_sha256")
  }
  %w[
    likes comments shares saves quotes watch_retention completion_rate
    measurement_window checkpoint_target_at checkpoint_lag_seconds
    source_locator metric_scope views_semantics known_gaps data_completeness
    snapshot_id snapshot_kind
  ].each do |field|
    fact[field] = row[field] if row.key?(field)
  end
  fact
end

options = {
  content_id: nil,
  root: TOOL_ROOT.to_s,
  posts: "analytics/records/platform-posts.jsonl",
  metrics: "analytics/records/platform-metrics.jsonl",
  ledger_override_reason: nil,
  output: nil,
  write: false
}

OptionParser.new do |parser|
  parser.on("--content-id ID") { |value| options[:content_id] = value }
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--posts PATH") { |value| options[:posts] = value }
  parser.on("--metrics PATH") { |value| options[:metrics] = value }
  parser.on("--ledger-override-reason REASON") { |value| options[:ledger_override_reason] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--write") { options[:write] = true }
end.parse!

run_arg = ARGV.shift
fail_usage("RUN_ROOT is required") if run_arg.to_s.strip.empty?
fail_usage("unexpected arguments: #{ARGV.join(' ')}") unless ARGV.empty?
content_id = options[:content_id].to_s.strip
fail_usage("--content-id ID is required") if content_id.empty?
fail_usage("invalid content id: #{content_id}") unless content_id.match?(/\A[A-Z0-9][A-Z0-9_-]{2,120}\z/)

root_path = resolve_path(options[:root], TOOL_ROOT)
fail_usage("repository root is not a directory: #{options[:root]}") unless root_path.directory?
root_path = root_path.realpath
run_path = resolve_path(run_arg, root_path)
fail_usage("RUN_ROOT is not a directory: #{run_arg}") unless Dir.exist?(run_path)
run_path = run_path.realpath
fail_usage("RUN_ROOT must stay inside repository root: #{display_path(run_path, root_path)}") unless within?(run_path, root_path)
run_rel = display_path(run_path, root_path)
layout_errors = IdolRunLayout.validate(run_path, repo_root: root_path)
fail_usage(layout_errors.join("; ")) unless layout_errors.empty?
run_identity = IdolRunLayout.identity(run_path, repo_root: root_path)
unless run_identity["content_id"].to_s == content_id
  fail_usage("run identity content_id must match --content-id #{content_id}")
end

posts_path = resolve_path(options[:posts], root_path)
metrics_path = resolve_path(options[:metrics], root_path)
output_path = resolve_path(options[:output] || (run_path + "analytics/social-evidence-snapshot-v3.yaml").to_s, root_path)

canonical_posts = canonicalize_path(root_path.join("analytics/records/platform-posts.jsonl"))
canonical_metrics = canonicalize_path(root_path.join("analytics/records/platform-metrics.jsonl"))
ledger_override_reason = options[:ledger_override_reason].to_s.strip
custom_ledgers = posts_path != canonical_posts || metrics_path != canonical_metrics
if custom_ledgers && ledger_override_reason.length < 12
  fail_usage("noncanonical ledger paths require --ledger-override-reason with at least 12 characters")
end
unless custom_ledgers
  begin
    unless within?(posts_path.realpath, root_path) && within?(metrics_path.realpath, root_path)
      fail_usage("canonical ledgers must not escape repository root through symlinks")
    end
  rescue Errno::ENOENT, Errno::EACCES
    # The readable-ledger check below reports the exact missing or inaccessible path.
  end
end

unless output_parent_within_run?(output_path, run_path)
  fail_usage("output must stay inside RUN_ROOT without a symlink escape: #{display_path(output_path, root_path)}")
end

fail_usage("platform-posts ledger is not readable: #{display_path(posts_path, root_path)}") unless File.file?(posts_path)
fail_usage("platform-metrics ledger is not readable: #{display_path(metrics_path, root_path)}") unless File.file?(metrics_path)
posts_source_sha256 = sha256_file(posts_path)
metrics_source_sha256 = sha256_file(metrics_path)
posts_source_bytes = File.size(posts_path)
metrics_source_bytes = File.size(metrics_path)
validate_source_ledgers(posts_path, metrics_path, root_path)
verify_ledger_unchanged!(posts_path, posts_source_sha256, "platform-posts")
verify_ledger_unchanged!(metrics_path, metrics_source_sha256, "platform-metrics")
post_rows = load_jsonl(posts_path, "platform-posts", root_path)
metric_rows = load_jsonl(metrics_path, "platform-metrics", root_path)
verify_ledger_unchanged!(posts_path, posts_source_sha256, "platform-posts")
verify_ledger_unchanged!(metrics_path, metrics_source_sha256, "platform-metrics")
matching_posts = post_rows.select { |item| item.dig("row", "content_id").to_s == content_id }
matching_metrics = metric_rows.select { |item| item.dig("row", "content_id").to_s == content_id }
matching_posts.each { |item| validate_published_fact!(item) }

posts_by_id = {}
matching_posts.each do |item|
  post_id = item.dig("row", "post_id").to_s
  fail_usage("matching platform-post row has no post_id") if post_id.empty?
  fail_usage("duplicate matching post_id: #{post_id}") if posts_by_id.key?(post_id)
  posts_by_id[post_id] = item.fetch("row")
end
matching_metrics.each do |item|
  metric = item.fetch("row")
  post_id = metric["post_id"].to_s
  post = posts_by_id[post_id]
  fail_usage("metric #{post_id} has no matching platform-post row for #{content_id}") unless post
  fail_usage("metric #{post_id} cannot be used before the post row is explicitly published") unless post["status"].to_s == "published"
  unless metric["platform"].to_s == post["platform"].to_s
    fail_usage("metric #{post_id} platform does not match the platform-post row")
  end
end

selected_metric_rows = matching_metrics.group_by do |item|
  row = item.fetch("row")
  identity = if !row["measurement_window"].to_s.empty?
               "checkpoint:#{row['measurement_window']}"
             elsif !row["snapshot_id"].to_s.empty?
               "snapshot:#{row['snapshot_id']}"
             else
               "date:#{row['observed_date']}"
             end
  [row["post_id"].to_s, identity]
end.values.map do |group|
  group.max_by { |item| [normalized_time(item.dig("row", "captured_at")), item["line_no"]] }
end

published_post_ids = matching_posts.each_with_object([]) do |item, ids|
  ids << item.dig("row", "post_id").to_s if item.dig("row", "status").to_s == "published"
end.uniq.sort
metric_post_ids = matching_metrics.map { |item| item.dig("row", "post_id").to_s }.uniq
missing_metric_post_ids = published_post_ids - metric_post_ids
published_count = published_post_ids.length
evidence_status = if matching_posts.empty?
                    "no_post_records"
                  elsif published_count.zero?
                    "posts_without_published_facts"
                  elsif missing_metric_post_ids.length == published_count
                    "published_without_metrics"
                  elsif missing_metric_post_ids.any?
                    "published_partial_metrics"
                  else
                    "measured"
                  end

source_set_material = [content_id]
matching_posts.each { |item| source_set_material << "post:#{item['row_sha256']}" }
matching_metrics.each { |item| source_set_material << "metric:#{item['row_sha256']}" }

post_facts = matching_posts.sort_by do |item|
  [item.dig("row", "scheduled_at").to_s, item.dig("row", "post_id").to_s]
end.map { |item| post_fact(item) }
metric_facts = selected_metric_rows.sort_by do |item|
  [item.dig("row", "post_id").to_s, item.dig("row", "measurement_window").to_s, item.dig("row", "captured_at").to_s]
end.map { |item| metric_fact(item) }
published_post_facts = post_facts.select { |fact| fact["status"] == "published" }
production_trace_fields = %w[
  release_provenance_version
  release_package_contract release_package_contract_sha256
  release_package_deliverable_manifest_sha256 release_package_output_id
  release_package_output_role release_package_linkage
  release_production_graph_trace_sha256 release_edit_segment_ids
  release_screen_progression_node_ids release_section_ids release_asset_sha256
]
traceable_post_facts = published_post_facts.select do |fact|
  production_trace_fields.all? { |field| fact.key?(field) && !fact[field].to_s.empty? }
end
traceable_post_ids = traceable_post_facts.map { |fact| fact.fetch("post_id") }.sort
missing_production_trace_post_ids = (
  published_post_facts.map { |fact| fact.fetch("post_id") } - traceable_post_ids
).sort
production_trace_status = if traceable_post_ids.empty?
                            "no_release_trace"
                          elsif missing_production_trace_post_ids.empty?
                            "complete"
                          else
                            "partial"
                          end
package_contracts = traceable_post_facts.map do |fact|
  {
    "path" => fact.fetch("release_package_contract"),
    "sha256" => fact.fetch("release_package_contract_sha256")
  }
end.uniq.sort_by { |binding| [binding.fetch("path"), binding.fetch("sha256")] }

document = {
  "schema_version" => "idol_social_evidence_snapshot.v3",
  "generated_at" => Time.now.iso8601,
  "run" => run_rel,
  "content_id" => content_id,
  "status" => matching_posts.empty? ? "no_evidence_yet" : "observed",
  "evidence_status" => evidence_status,
  "ledger_scope" => {
    "mode" => custom_ledgers ? "audited_override" : "canonical",
    "override_reason" => custom_ledgers ? ledger_override_reason : nil
  },
  "source_ledgers" => [
    {
      "role" => "platform_posts",
      "path" => display_path(posts_path, root_path),
      "sha256" => posts_source_sha256,
      "byte_count" => posts_source_bytes,
      "row_count" => post_rows.length,
      "matching_row_count" => matching_posts.length
    },
    {
      "role" => "platform_metrics",
      "path" => display_path(metrics_path, root_path),
      "sha256" => metrics_source_sha256,
      "byte_count" => metrics_source_bytes,
      "row_count" => metric_rows.length,
      "matching_row_count" => matching_metrics.length
    }
  ],
  "source_set_sha256" => Digest::SHA256.hexdigest(source_set_material.sort.join("\n")),
  "summary" => {
    "post_count" => matching_posts.length,
    "published_count" => published_count,
    "metric_count" => matching_metrics.length,
    "latest_metric_count" => selected_metric_rows.length,
    "selected_metric_count" => selected_metric_rows.length,
    "missing_metric_post_ids" => missing_metric_post_ids,
    "content_family_post_counts" => IdolSocialTaxonomy.count_by(post_facts) { |fact| fact.fetch("content_family") },
    "published_content_family_counts" => IdolSocialTaxonomy.count_by(published_post_facts) { |fact| fact.fetch("content_family") },
    "content_lane_post_counts" => IdolSocialTaxonomy.count_by(post_facts) { |fact| fact.fetch("content_lane", "unclassified") },
    "format_family_post_counts" => IdolSocialTaxonomy.count_by(post_facts) { |fact| fact.fetch("format_family") },
    "measurement_window_counts" => IdolSocialTaxonomy.count_by(metric_facts) { |fact| fact.fetch("measurement_window", "non_checkpoint_snapshot") },
    "shared_media_post_count" => post_facts.count { |fact| fact.key?("shared_media_source_post_id") },
    "production_trace_post_count" => traceable_post_ids.length,
    "missing_production_trace_post_ids" => missing_production_trace_post_ids,
    "unclassified_learning_post_ids" => post_facts.select do |fact|
      fact["content_pillar"] == "unclassified" || fact["primary_channel_job"] == "unclassified"
    end.map { |fact| fact.fetch("post_id") }
  },
  "post_facts" => post_facts,
  "metric_facts" => metric_facts,
  "production_graph_evidence" => {
    "status" => production_trace_status,
    "traceable_post_ids" => traceable_post_ids,
    "missing_trace_post_ids" => missing_production_trace_post_ids,
    "package_contracts" => package_contracts,
    "mutation_boundary" => "analytics_is_append_only_evidence_and_never_mutates_05_or_04_truth"
  },
  "automation_boundaries" => [
    "This snapshot filters observed ledger rows for one run/content scope; it does not upload, schedule, publish, or mutate either source ledger.",
    "Only rows explicitly marked published count as publication facts; planned or draft-upload rows remain non-published.",
    "no_post_records, posts_without_published_facts, published_without_metrics, and published_partial_metrics are evidence states, not permission to infer complete performance.",
    "Performance decisions remain Founder-review candidates and cannot promote themselves into creative memory.",
    "Release production traces are copied as append-only evidence; analytics never patches 05-package.yaml, the 04 recipe, or the 04 edit map."
  ]
}

verify_ledger_unchanged!(posts_path, posts_source_sha256, "platform-posts")
verify_ledger_unchanged!(metrics_path, metrics_source_sha256, "platform-metrics")
if options[:write]
  FileUtils.mkdir_p(output_path.dirname)
  stage = Tempfile.new([".#{output_path.basename}.stage-", ".yaml"], output_path.dirname.to_s, encoding: "utf-8")
  begin
    stage.write(YAML.dump(document))
    stage.flush
    stage.fsync
    stage.close
    stdout, stderr, status = Open3.capture3(
      (TOOL_ROOT + "scripts/idol-video-python").to_s,
      (TOOL_ROOT + "scripts/validate_json_schema.py").to_s,
      (TOOL_ROOT + "schemas/social-evidence-snapshot.schema.json").to_s,
      stage.path,
      chdir: TOOL_ROOT.to_s
    )
    fail_usage("snapshot schema validation failed: #{[stdout, stderr].join(' ').strip}") unless status.success?
    File.rename(stage.path, output_path.to_s)
  ensure
    stage.close! if File.exist?(stage.path)
  end
  puts "wrote #{display_path(output_path, root_path)}"
  puts "evidence_status #{evidence_status}"
else
  puts YAML.dump(document)
end
