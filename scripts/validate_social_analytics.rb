#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "time"
require_relative "lib/idol_social_taxonomy"

ROOT = Pathname.new(Dir.pwd)
POSTS_PATH = ARGV[0] || "analytics/records/platform-posts.jsonl"
METRICS_PATH = ARGV[1] || "analytics/records/platform-metrics.jsonl"

ALLOWED_PLATFORMS = IdolSocialTaxonomy::PLATFORMS
ALLOWED_TEMPLATE_TYPES = IdolSocialTaxonomy::TEMPLATE_TYPES

ALLOWED_POST_STATUSES = %w[
  planned
  scheduled
  published
  skipped
  failed
].freeze

ALLOWED_DECISIONS = %w[
  repeat
  transform
  watch
  pause
].freeze

PUBLIC_PLATFORM_HASHTAG_PLATFORMS = %w[
  tiktok
  youtube
  youtube_shorts
  instagram_reels
].freeze

REQUIRED_PUBLIC_PLATFORM_HASHTAGS = %w[
  #AI
  #AIIdol
  #Kpop
  #VirtualIdol
  #Loom
].freeze

POST_REQUIRED_FIELDS = %w[
  post_id
  content_id
  platform
  template_type
  message
  asset_or_clip
  caption
  hashtags
  scheduled_at
  status
  analysis_scope
].freeze

METRIC_REQUIRED_FIELDS = %w[
  captured_at
  observed_date
  post_id
  content_id
  platform
  views
  engagement
  source
].freeze

RELEASE_PRODUCTION_TRACE_FIELDS = %w[
  release_provenance_version
  release_package_contract
  release_package_contract_sha256
  release_package_deliverable_manifest_sha256
  release_package_output_id
  release_package_output_role
  release_package_linkage
  release_production_graph_trace_sha256
  release_edit_segment_ids
  release_screen_progression_node_ids
  release_section_ids
  release_asset_sha256
].freeze
RELEASE_PRODUCTION_TRACE_TRIGGER_FIELDS = %w[
  release_provenance_version
  release_production_graph_trace_sha256
  release_edit_segment_ids
  release_screen_progression_node_ids
  release_section_ids
].freeze

errors = []
warnings = []

def repo_path(path)
  raw = Pathname.new(path)
  raw.absolute? ? raw.cleanpath : (ROOT + raw).cleanpath
end

def load_jsonl(path, label, errors)
  resolved = repo_path(path)
  unless File.file?(resolved)
    errors << "#{label} file is missing: #{path}"
    return []
  end

  records = []
  File.foreach(resolved).with_index(1) do |line, line_no|
    text = line.strip
    next if text.empty?

    begin
      value = JSON.parse(text)
    rescue JSON::ParserError => e
      errors << "#{label}:#{line_no}: invalid JSON: #{e.message}"
      next
    end

    unless value.is_a?(Hash)
      errors << "#{label}:#{line_no}: row must be a JSON object"
      next
    end

    records << [line_no, value]
  end
  records
end

def blank?(value)
  value.nil? || (value.respond_to?(:empty?) && value.empty?)
end

def require_fields!(record, fields, label, errors)
  fields.each do |field|
    value = record[field]
    errors << "#{label}: #{field} is required" if blank?(value)
  end
end

def parse_time(value)
  Time.iso8601(value.to_s)
rescue ArgumentError
  nil
end

def non_negative_number?(value)
  value.is_a?(Numeric) && value >= 0
end

YOUTUBE_BREAKDOWN_NUMERIC_FIELDS = %w[
  views
  shares
  average_view_duration_sec
  average_view_percentage
  estimated_minutes_watched
].freeze

YOUTUBE_BREAKDOWN_DIMENSION_FIELDS = %w[
  country
  age_group
  gender
  device_type
  operating_system
  traffic_source_type
  playback_location_type
  subscribed_status
  youtube_product
  sharing_service
].freeze

YOUTUBE_DETAIL_STATUSES = %w[
  populated
  no_rows
  unsupported_or_unavailable
  request_failed
  not_requested_public_statistics_fallback
].freeze

TIKTOK_STUDIO_DETAIL_DIMENSIONS = %w[
  country
  age_gender
  traffic_source
  average_watch_time
  completion_rate
  retention_curve
].freeze

TIKTOK_STUDIO_DETAIL_STATUSES = %w[
  populated
  not_in_export
  manual_ui_required
  request_failed
].freeze

def validate_youtube_breakdown_rows!(rows, label, expected_dimension, errors)
  unless rows.is_a?(Array)
    errors << "#{label} must be an array"
    return
  end

  rows.each_with_index do |row, index|
    row_label = "#{label}[#{index}]"
    unless row.is_a?(Hash)
      errors << "#{row_label} must be an object"
      next
    end
    if row[expected_dimension].to_s.strip.empty?
      errors << "#{row_label}: #{expected_dimension} is required"
    end
    YOUTUBE_BREAKDOWN_NUMERIC_FIELDS.each do |field|
      next unless row.key?(field)

      errors << "#{row_label}: #{field} must be a non-negative number" unless non_negative_number?(row[field])
    end
  end
end

def validate_youtube_detail_statuses!(statuses, label, errors)
  unless statuses.is_a?(Hash)
    errors << "#{label} must be an object"
    return
  end

  statuses.each do |key, status|
    status_label = "#{label}.#{key}"
    unless status.is_a?(Hash)
      errors << "#{status_label} must be an object"
      next
    end
    errors << "#{status_label}: source_dimension is required" if status["source_dimension"].to_s.strip.empty?
    unless YOUTUBE_DETAIL_STATUSES.include?(status["status"].to_s)
      errors << "#{status_label}: unsupported status #{status['status']}"
    end
    row_count = status["row_count"]
    errors << "#{status_label}: row_count must be a non-negative integer" unless row_count.is_a?(Integer) && row_count >= 0
    if status.key?("reason_code") && status["reason_code"].to_s.strip.empty?
      errors << "#{status_label}: reason_code cannot be blank"
    end
  end
end

def validate_tiktok_studio_detail_statuses!(statuses, label, errors)
  unless statuses.is_a?(Hash)
    errors << "#{label} must be an object"
    return
  end

  missing = TIKTOK_STUDIO_DETAIL_DIMENSIONS - statuses.keys.map(&:to_s)
  unexpected = statuses.keys.map(&:to_s) - TIKTOK_STUDIO_DETAIL_DIMENSIONS
  missing.each { |dimension| errors << "#{label}: missing #{dimension}" }
  unexpected.each { |dimension| errors << "#{label}: unsupported TikTok Studio detail #{dimension}" }
  statuses.each do |key, status|
    status_label = "#{label}.#{key}"
    unless status.is_a?(Hash)
      errors << "#{status_label} must be an object"
      next
    end
    errors << "#{status_label}: source_dimension is required" if status["source_dimension"].to_s.strip.empty?
    unless TIKTOK_STUDIO_DETAIL_STATUSES.include?(status["status"].to_s)
      errors << "#{status_label}: unsupported status #{status['status']}"
    end
    row_count = status["row_count"]
    errors << "#{status_label}: row_count must be a non-negative integer" unless row_count.is_a?(Integer) && row_count >= 0
    if status.key?("reason_code") && status["reason_code"].to_s.strip.empty?
      errors << "#{status_label}: reason_code cannot be blank"
    end
  end
end

def validate_youtube_retention_curve!(rows, label, errors)
  unless rows.is_a?(Array)
    errors << "#{label} must be an array"
    return
  end

  rows.each_with_index do |row, index|
    row_label = "#{label}[#{index}]"
    unless row.is_a?(Hash)
      errors << "#{row_label} must be an object"
      next
    end
    unless non_negative_number?(row["elapsed_video_time_ratio"])
      errors << "#{row_label}: elapsed_video_time_ratio must be a non-negative number"
    end
    %w[audience_watch_ratio relative_retention_performance].each do |field|
      next unless row.key?(field)

      errors << "#{row_label}: #{field} must be a non-negative number" unless non_negative_number?(row[field])
    end
  end
end

posts = load_jsonl(POSTS_PATH, "platform-posts", errors)
metrics = load_jsonl(METRICS_PATH, "platform-metrics", errors)

posts_by_id = {}
published_platform_ids = {}

posts.each do |line_no, post|
  label = "platform-posts:#{line_no}:#{post['post_id'] || 'unknown'}"
  require_fields!(post, POST_REQUIRED_FIELDS, label, errors)

  post_id = post["post_id"].to_s
  platform = post["platform"].to_s
  template_type = post["template_type"].to_s
  content_lane = post["content_lane"].to_s
  status = post["status"].to_s
  scope = post["analysis_scope"].to_s

  if posts_by_id.key?(post_id)
    errors << "#{label}: duplicate post_id also appears at platform-posts:#{posts_by_id[post_id][:line_no]}"
  elsif !post_id.empty?
    posts_by_id[post_id] = { line_no: line_no, row: post }
  end

  errors << "#{label}: unsupported platform #{platform}" unless ALLOWED_PLATFORMS.include?(platform)
  errors << "#{label}: unsupported template_type #{template_type}" unless ALLOWED_TEMPLATE_TYPES.include?(template_type)
  errors << "#{label}: unsupported status #{status}" unless ALLOWED_POST_STATUSES.include?(status)

  unless content_lane.empty? || IdolSocialTaxonomy::CONTENT_LANES.include?(content_lane)
    errors << "#{label}: unsupported content_lane #{content_lane}"
  end
  if !%w[track clip question_poll youtube_full_master].include?(template_type) && content_lane.empty?
    errors << "#{label}: expanded template_type #{template_type} requires content_lane"
  end

  content_family = post["content_family"].to_s
  unless content_family.empty? || IdolSocialTaxonomy::CONTENT_FAMILIES.include?(content_family)
    errors << "#{label}: unsupported content_family #{content_family}"
  end
  unless content_family.empty?
    derived_row = post.dup
    derived_row.delete("content_family")
    derived_family = IdolSocialTaxonomy.content_family(derived_row)
    errors << "#{label}: content_family #{content_family} does not match derived #{derived_family}" unless content_family == derived_family
  end

  format_family = post["format_family"].to_s
  unless format_family.empty? || IdolSocialTaxonomy::FORMAT_FAMILIES.include?(format_family)
    errors << "#{label}: unsupported format_family #{format_family}"
  end
  %w[member member_codes].each do |field|
    next unless post.key?(field)

    values = post[field]
    if !values.is_a?(Array) || values.any? { |value| value.to_s.strip.empty? } || values.map(&:to_s).uniq.length != values.length
      errors << "#{label}: #{field} must be a unique array of non-empty member labels"
    end
  end
  member_codes = IdolSocialTaxonomy.member_codes(post)
  if platform == "x" && member_codes.any? && post["member_intro_line"].to_s.strip.empty?
    errors << "#{label}: member-led X rows require member_intro_line"
  end
  unless content_lane.empty?
    warnings << "#{label}: content_pillar is missing; analysis will mark it unclassified" if post["content_pillar"].to_s.empty?
    warnings << "#{label}: primary_channel_job is missing; analysis will mark it unclassified" if post["primary_channel_job"].to_s.empty?
  end

  if platform == "x"
    errors << "#{label}: X rows must use analysis_scope scheduler_whitelist" unless scope == "scheduler_whitelist"
  elsif ALLOWED_PLATFORMS.include?(platform)
    errors << "#{label}: #{platform} rows must use analysis_scope date_based" unless scope == "date_based"
  end

  unless post["hashtags"].is_a?(Array)
    errors << "#{label}: hashtags must be an array"
  else
    normalized_tags = post["hashtags"].map { |tag| tag.to_s.downcase.delete("-_") }
    if normalized_tags.any? { |tag| tag == "#auroram" }
      errors << "#{label}: public hashtags must use Loom/Harne, not #AURORAM"
    end
    unless normalized_tags.any? { |tag| tag == "#loom" || tag == "#harne" }
      warnings << "#{label}: consider adding a Loom or Harne public tag when brand-safe"
    end
    if PUBLIC_PLATFORM_HASHTAG_PLATFORMS.include?(platform)
      compact_tags = post["hashtags"].map { |tag| tag.to_s.downcase.delete(" ") }
      missing = REQUIRED_PUBLIC_PLATFORM_HASHTAGS.reject do |tag|
        compact_tags.include?(tag.downcase.delete(" "))
      end
      unless missing.empty?
        warnings << "#{label}: platform public draft tags should include #{missing.join(', ')}"
      end
    end
  end

  scheduled_at = post["scheduled_at"].to_s
  errors << "#{label}: scheduled_at must be ISO-8601" if !scheduled_at.empty? && parse_time(scheduled_at).nil?

  if status == "published"
    published_at = post["published_at"].to_s
    platform_post_id = post["platform_post_id"].to_s
    published_url = post["published_url"].to_s
    errors << "#{label}: published_at is required for published rows" if published_at.empty?
    errors << "#{label}: published_at must be ISO-8601" if !published_at.empty? && parse_time(published_at).nil?
    warnings << "#{label}: published_url or platform_post_id should be recorded" if published_url.empty? && platform_post_id.empty?

    unless platform_post_id.empty?
      key = "#{platform}:#{platform_post_id}"
      if published_platform_ids.key?(key)
        errors << "#{label}: duplicate platform_post_id also appears at platform-posts:#{published_platform_ids[key]}"
      else
        published_platform_ids[key] = line_no
      end
    end
  end

  if template_type == "youtube_full_master" && platform != "youtube"
    errors << "#{label}: youtube_full_master template_type must use platform youtube"
  end

  trace_fields_present = RELEASE_PRODUCTION_TRACE_TRIGGER_FIELDS.any? { |field| post.key?(field) }
  if trace_fields_present
    RELEASE_PRODUCTION_TRACE_FIELDS.each do |field|
      errors << "#{label}: #{field} is required for a release production trace" if blank?(post[field])
    end
    if post["release_provenance_version"] != "idol_release_provenance.v2"
      errors << "#{label}: release_provenance_version must be idol_release_provenance.v2"
    end
    %w[
      release_package_contract_sha256
      release_package_deliverable_manifest_sha256
      release_production_graph_trace_sha256
      release_asset_sha256
    ].each do |field|
      next if post[field].to_s.match?(/\A[a-f0-9]{64}\z/)

      errors << "#{label}: #{field} must be lowercase SHA-256"
    end
    package_contract = post["release_package_contract"].to_s
    if package_contract.start_with?("/") || package_contract.split("/").include?("..")
      errors << "#{label}: release_package_contract must be repository-relative without .."
    end
    unless %w[exact_deliverable child_of_upload_package].include?(post["release_package_linkage"].to_s)
      errors << "#{label}: release_package_linkage is unsupported"
    end
    {
      "release_edit_segment_ids" => /\ASEG_[A-Z0-9_]{2,80}\z/,
      "release_screen_progression_node_ids" => /\A.+\z/,
      "release_section_ids" => /\AS[0-9]{2,}[A-Z]?\z/
    }.each do |field, pattern|
      values = post[field]
      if !values.is_a?(Array) || values.empty? || values.map(&:to_s).uniq.length != values.length
        errors << "#{label}: #{field} must be a non-empty unique array"
        next
      end
      errors << "#{label}: #{field} contains an invalid id" unless values.all? { |value| value.to_s.match?(pattern) }
    end
  end
end

posts_by_id.each do |post_id, entry|
  post = entry.fetch(:row)
  label = "platform-posts:#{entry.fetch(:line_no)}:#{post_id}"
  %w[shared_media_source_post_id reply_to_post_id].each do |field|
    source_id = post[field].to_s.strip
    next if source_id.empty?

    if source_id == post_id
      errors << "#{label}: #{field} cannot reference the same post_id"
      next
    end
    source = posts_by_id.dig(source_id, :row)
    if source.nil?
      errors << "#{label}: #{field} #{source_id} is not present in platform-posts"
    elsif source["content_id"].to_s != post["content_id"].to_s
      errors << "#{label}: #{field} must stay inside the same content_id"
    end
  end
end

metric_keys = {}

metrics.each do |line_no, metric|
  label = "platform-metrics:#{line_no}:#{metric['post_id'] || 'unknown'}"
  require_fields!(metric, METRIC_REQUIRED_FIELDS, label, errors)

  post_id = metric["post_id"].to_s
  platform = metric["platform"].to_s
  captured_at = metric["captured_at"].to_s
  observed_date = metric["observed_date"].to_s

  post = posts_by_id.dig(post_id, :row)
  if post.nil?
    errors << "#{label}: post_id is not present in platform-posts"
  elsif post["platform"].to_s != platform
    errors << "#{label}: platform does not match platform-posts row"
  elsif post["content_id"].to_s != metric["content_id"].to_s
    errors << "#{label}: content_id does not match platform-posts row"
  end

  errors << "#{label}: unsupported platform #{platform}" unless ALLOWED_PLATFORMS.include?(platform)
  errors << "#{label}: captured_at must be ISO-8601" if !captured_at.empty? && parse_time(captured_at).nil?
  errors << "#{label}: observed_date must be YYYY-MM-DD" unless observed_date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

  %w[
    views engagement likes comments shares saves quotes
    average_view_duration_sec average_view_percentage estimated_minutes_watched
    subscribers_gained subscribers_lost engaged_views
  ].each do |field|
    next unless metric.key?(field)

    errors << "#{label}: #{field} must be a non-negative number" unless non_negative_number?(metric[field])
  end

  %w[watch_retention completion_rate].each do |field|
    next unless metric.key?(field) && !metric[field].nil?

    errors << "#{label}: #{field} must be a non-negative number or null" unless non_negative_number?(metric[field])
  end

  if metric.key?("platform_video_id") && metric["platform_video_id"].to_s.strip.empty?
    errors << "#{label}: platform_video_id cannot be blank"
  end
  if metric.key?("tiktok_studio_import_id") && metric["tiktok_studio_import_id"].to_s.strip.empty?
    errors << "#{label}: tiktok_studio_import_id cannot be blank"
  end
  if metric.key?("tiktok_studio_detail_status")
    validate_tiktok_studio_detail_statuses!(
      metric["tiktok_studio_detail_status"],
      "#{label}: tiktok_studio_detail_status",
      errors
    )
  end

  if metric.key?("completion_rate_status") && !%w[
    reported_by_provider
    not_exposed_by_youtube_analytics_api_v2
    unavailable_data_api_fallback
  ].include?(metric["completion_rate_status"].to_s)
    errors << "#{label}: unsupported completion_rate_status #{metric['completion_rate_status']}"
  end

  if metric.key?("top_countries") && !metric["top_countries"].nil?
    validate_youtube_breakdown_rows!(metric["top_countries"], "#{label}: top_countries", "country", errors)
  end

  if metric.key?("youtube_analytics_breakdowns")
    breakdowns = metric["youtube_analytics_breakdowns"]
    unless breakdowns.is_a?(Hash)
      errors << "#{label}: youtube_analytics_breakdowns must be an object"
    else
      breakdowns.each do |dimension, rows|
        expected_dimension = dimension.to_s
        unless YOUTUBE_BREAKDOWN_DIMENSION_FIELDS.include?(expected_dimension)
          errors << "#{label}: unsupported YouTube breakdown #{dimension}"
          next
        end
        validate_youtube_breakdown_rows!(rows, "#{label}: youtube_analytics_breakdowns.#{dimension}", expected_dimension, errors)
      end
    end
  end

  if metric.key?("youtube_analytics_breakdown_status")
    validate_youtube_detail_statuses!(
      metric["youtube_analytics_breakdown_status"],
      "#{label}: youtube_analytics_breakdown_status",
      errors
    )
  end

  if metric.key?("youtube_analytics_retention_curve")
    validate_youtube_retention_curve!(
      metric["youtube_analytics_retention_curve"],
      "#{label}: youtube_analytics_retention_curve",
      errors
    )
  end

  if metric.key?("youtube_analytics_retention_status")
    validate_youtube_detail_statuses!(
      { "retention" => metric["youtube_analytics_retention_status"] },
      "#{label}: youtube_analytics_retention_status",
      errors
    )
  end

  decision = metric["decision"].to_s
  if !decision.empty? && !ALLOWED_DECISIONS.include?(decision)
    errors << "#{label}: decision must be one of #{ALLOWED_DECISIONS.join(', ')}"
  end

  measurement_window = metric["measurement_window"].to_s
  unless measurement_window.empty?
    errors << "#{label}: measurement_window must be T+24h, T+72h, or T+7d" unless %w[T+24h T+72h T+7d].include?(measurement_window)
    checkpoint_target_at = metric["checkpoint_target_at"].to_s
    checkpoint_lag_seconds = metric["checkpoint_lag_seconds"]
    errors << "#{label}: checkpoint_target_at is required with measurement_window" if checkpoint_target_at.empty?
    errors << "#{label}: checkpoint_target_at must be ISO-8601" if !checkpoint_target_at.empty? && parse_time(checkpoint_target_at).nil?
    errors << "#{label}: checkpoint_lag_seconds must be a non-negative integer" unless checkpoint_lag_seconds.is_a?(Integer) && checkpoint_lag_seconds >= 0
  end

  measurement_identity = if !measurement_window.empty?
                           "checkpoint:#{measurement_window}"
                         elsif !metric["snapshot_id"].to_s.empty?
                           "snapshot:#{metric['snapshot_id']}"
                         else
                           "date:#{observed_date}"
                         end
  key = "#{platform}:#{post_id}:#{measurement_identity}"
  if metric_keys.key?(key)
    previous = metric_keys[key]
    if previous[:captured_at] == captured_at
      errors << "#{label}: duplicate metric key and captured_at also appears at platform-metrics:#{previous[:line_no]}"
    else
      warnings << "#{label}: duplicate metric key; latest snapshot is selected by captured_at"
    end
  end
  metric_keys[key] = { line_no: line_no, captured_at: captured_at }
end

if errors.empty?
  puts "OK: #{posts.length} post row(s), #{metrics.length} metric row(s) validated"
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
