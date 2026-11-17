# frozen_string_literal: true

module IdolSocialTaxonomy
  PLATFORMS = %w[
    x
    tiktok
    youtube
    youtube_shorts
    instagram_reels
  ].freeze

  TEMPLATE_TYPES = %w[
    track
    clip
    question_poll
    youtube_full_master
    work_root
    derived_clip
    hook_loop
    member_still
    member_carousel
    member_clip
    craft_gift
    harness_proof
    process_thread
  ].freeze

  CONTENT_LANES = %w[
    work_root
    derived_clip
    derived_clip_3_8
    hook_loop_3_8
    member_key_visual
    member_still
    member_carousel
    member_clip
    lip_sync_reel
    mv_highlight
    cf_key_visual
    section_clip
    member_focus_3_8
    cf_hook_3_8
    before_after
    craft_gift
    harness_proof
    process_thread
    question_poll
    full_master
    cf_film_drop
    mv_film_drop
    mv_cutdown
    x_derived_clip
    x_craft_gift
    x_harness_proof
    x_process_film_drop
    x_reply_boards_image_prompt
    x_reply_video_prompt
    x_reply_stack
  ].freeze

  CONTENT_FAMILIES = %w[
    legacy_track
    legacy_clip
    question_poll
    full_master
    work_root
    derived_clip
    hook_loop
    member_still
    member_carousel
    member_clip
    craft_gift
    harness_proof
    process_thread
    reply_support
    key_visual
    before_after
  ].freeze

  FORMAT_FAMILIES = %w[
    video
    still
    carousel
    thread
    poll
    full_master
    unknown
  ].freeze

  CONTENT_PILLARS = %w[
    loom_idol_member
    cf_finish
    production_harness
    unclassified
  ].freeze

  PRIMARY_CHANNEL_JOBS = %w[
    discovery
    proof
    relationship
    return
    unclassified
  ].freeze

  LANE_TO_FAMILY = {
    "work_root" => "work_root",
    "cf_film_drop" => "work_root",
    "mv_film_drop" => "work_root",
    "mv_cutdown" => "work_root",
    "derived_clip" => "derived_clip",
    "derived_clip_3_8" => "derived_clip",
    "x_derived_clip" => "derived_clip",
    "cf_hook_3_8" => "derived_clip",
    "mv_highlight" => "derived_clip",
    "section_clip" => "derived_clip",
    "hook_loop_3_8" => "hook_loop",
    "member_key_visual" => "member_still",
    "member_still" => "member_still",
    "member_carousel" => "member_carousel",
    "member_clip" => "member_clip",
    "member_focus_3_8" => "member_clip",
    "lip_sync_reel" => "member_clip",
    "craft_gift" => "craft_gift",
    "x_craft_gift" => "craft_gift",
    "harness_proof" => "harness_proof",
    "x_harness_proof" => "harness_proof",
    "process_thread" => "process_thread",
    "x_process_film_drop" => "process_thread",
    "x_reply_boards_image_prompt" => "reply_support",
    "x_reply_video_prompt" => "reply_support",
    "x_reply_stack" => "reply_support",
    "cf_key_visual" => "key_visual",
    "before_after" => "before_after",
    "question_poll" => "question_poll",
    "full_master" => "full_master"
  }.freeze

  TEMPLATE_TO_FAMILY = {
    "track" => "legacy_track",
    "clip" => "legacy_clip",
    "question_poll" => "question_poll",
    "youtube_full_master" => "full_master",
    "work_root" => "work_root",
    "derived_clip" => "derived_clip",
    "hook_loop" => "hook_loop",
    "member_still" => "member_still",
    "member_carousel" => "member_carousel",
    "member_clip" => "member_clip",
    "craft_gift" => "craft_gift",
    "harness_proof" => "harness_proof",
    "process_thread" => "process_thread"
  }.freeze

  module_function

  def content_family(row)
    explicit = row["content_family"].to_s.strip
    return explicit unless explicit.empty?

    lane = row["content_lane"].to_s.strip
    return LANE_TO_FAMILY.fetch(lane) if LANE_TO_FAMILY.key?(lane)

    TEMPLATE_TO_FAMILY.fetch(row["template_type"].to_s, "legacy_clip")
  end

  def format_family(row)
    explicit = row["format_family"].to_s.strip
    return explicit unless explicit.empty?

    media_kind = row["media_kind"].to_s
    return "carousel" if media_kind.include?("carousel")
    return "still" if media_kind == "still" || media_kind.start_with?("still_")
    return "video" if media_kind.start_with?("video_")

    case content_family(row)
    when "full_master" then "full_master"
    when "member_still", "key_visual" then "still"
    when "member_carousel" then "carousel"
    when "process_thread", "reply_support" then "thread"
    when "question_poll" then "poll"
    when "legacy_track", "legacy_clip", "work_root", "derived_clip", "hook_loop", "member_clip", "before_after"
      "video"
    else
      "unknown"
    end
  end

  def member_codes(row)
    value = row["member_codes"] || row["member"] || []
    Array(value).map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def count_by(rows)
    rows.each_with_object(Hash.new(0)) { |value, counts| counts[yield(value)] += 1 }.sort.to_h
  end
end
