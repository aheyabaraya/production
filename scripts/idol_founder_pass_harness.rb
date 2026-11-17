#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "yaml"
require_relative "lib/idol_handoff_keys"

options = {
  run: nil,
  pass_date: Date.today.iso8601,
  album_key: "aurora-m",
  title_key: nil,
  write: false,
  sync_grok_imagine: false,
  founder_requested: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: scripts/idol_founder_pass_harness.rb RUN_ROOT [--album-key ALBUM_KEY] [--title-key TITLE_KEY] [--pass-date YYYY-MM-DD] [--write]"
  opts.on("--run PATH", "Run root. Alternative to positional RUN_ROOT.") { |value| options[:run] = value }
  opts.on("--pass-date DATE", "Founder pass date. Defaults to today.") { |value| options[:pass_date] = value }
  opts.on("--album-key KEY", "Stable album key for catalog/albums. Defaults to aurora-m.") { |value| options[:album_key] = IdolHandoffKeys.slug(value) }
  opts.on("--title-key KEY", "Stable title-song key for pass-harness report. Defaults to CONTENT_ID slug.") { |value| options[:title_key] = value }
  opts.on("--write", "Write handoff outputs. Without this, run a dry check.") { options[:write] = true }
  opts.on("--sync-grok-imagine", "Stage the 02-03 Grok Imagine Drive handoff. Use only on explicit founder request.") { options[:sync_grok_imagine] = true }
  opts.on("--no-sync-grok-imagine", "Skip 02-03 Grok Imagine Drive staging.") { options[:sync_grok_imagine] = false }
  opts.on("--founder-requested", "Confirm the founder explicitly requested Grok/Drive handoff staging for this run.") { options[:founder_requested] = true }
end

parser.parse!

run = options[:run] || ARGV.shift
abort parser.to_s unless run

unless options[:pass_date].match?(/\A\d{4}-\d{2}-\d{2}\z/)
  abort "pass date must be YYYY-MM-DD"
end

run_path = File.expand_path(run)
content_id = File.basename(run_path)
album_key = IdolHandoffKeys.slug(options[:album_key])
abort "album key cannot be empty" if album_key.empty?
title_key = IdolHandoffKeys.title_key(options[:title_key], fallback: content_id)
title_output_registry_path = File.join("catalog/albums", album_key, title_key, "output-registry.yaml")
review_path = File.join(run_path, "03-review.yaml")
abort "missing review file: #{review_path}" unless File.exist?(review_path)
python_bin = File.exist?(".venv-video/bin/python") ? ".venv-video/bin/python" : "python3"

if options[:write] && options[:sync_grok_imagine] && !options[:founder_requested]
  abort "refusing to write Grok/Drive handoff without --founder-requested"
end

review = YAML.safe_load(File.read(review_path), permitted_classes: [Time, Date], aliases: true)
board_reviews = review.fetch("board_reviews", [])
abort "03-review.board_reviews must contain review records" unless board_reviews.is_a?(Array) && !board_reviews.empty?

status_counts = board_reviews.each_with_object(Hash.new(0)) do |record, counts|
  counts[record["founder_review_status"].to_s] += 1
end

pass_count = status_counts.fetch("pass", 0)
abort "no founder_review_status: pass records found in 03-review.yaml" if pass_count.zero?

unknown_statuses = status_counts.keys - %w[pass hold reject]
abort "unknown founder_review_status values: #{unknown_statuses.join(", ")}" unless unknown_statuses.empty?

drive_sync_result = nil
if options[:sync_grok_imagine]
  command = [
    python_bin,
    "scripts/idol_grok_imagine_drive_sync.py",
    "--run",
    run,
    "--pass-date",
    options[:pass_date],
    "--album-key",
    album_key,
    "--title-key",
    title_key
  ]
  command << "--write" if options[:write]
  command << "--founder-requested" if options[:founder_requested]
  stdout, stderr, status = Open3.capture3(*command)
  abort stderr unless status.success?
  drive_sync_result = JSON.parse(stdout)
end

result = {
  "write" => options[:write],
  "harness" => "founder_pass",
  "run" => run,
  "content_id" => content_id,
  "album_key" => album_key,
  "title_key" => title_key,
  "title_output_registry_path" => title_output_registry_path,
  "pass_date" => options[:pass_date],
  "founder_requested" => options[:founder_requested],
  "review_file" => review_path,
  "review_status_counts" => status_counts.sort.to_h,
  "pass_count" => pass_count,
  "steps" => {
    "review_pass_check" => "passed",
    "grok_imagine_drive_sync" => options[:sync_grok_imagine] ? "included" : "skipped"
  },
  "drive_sync" => drive_sync_result
}

if options[:write]
  report_dir = File.join(run_path, "handoff")
  FileUtils.mkdir_p(report_dir)
  report_path = File.join(report_dir, "03-review-founder-pass-harness-#{title_key}.json")
  File.write(report_path, JSON.pretty_generate(result) + "\n")
  result["report_path"] = report_path
end

puts JSON.pretty_generate(result)
