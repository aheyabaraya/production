#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "digest"

path = ARGV.fetch(0) do
  warn "usage: scripts/validate_wardrobe_style_review.rb PATH_TO_wardrobe-style-review-vN.json"
  exit 2
end

root = Pathname.new(Dir.pwd)
errors = []
warnings = []

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_path(path, root)
  return nil if blank?(path)

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : (root + raw).cleanpath
end

def readable_file?(path)
  path && File.file?(path.to_s)
end

def check_hash(path, declared_hash, errors, label)
  unless readable_file?(path)
    errors << "#{label} is not readable: #{path}"
    return
  end

  actual_hash = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} SHA-256 is stale" unless actual_hash == declared_hash.to_s
end

def required_text?(value)
  !blank?(value)
end

resolved_path = resolve_path(path, root)
unless readable_file?(resolved_path)
  warn "ERROR: wardrobe style review is not readable: #{path}"
  exit 1
end

begin
  doc = JSON.parse(File.read(resolved_path))
rescue JSON::ParserError => e
  warn "ERROR: JSON syntax error: #{e.message}"
  exit 1
end

required_top_fields = %w[
  content_id
  status
  date
  song_title
  source_audio_analysis
  flow_position
  canonical_terms
  automation_loop
  preview_use_rule
  wardrobe_system
  wardrobe_lanes
  member_application
  section_rotation
  reject_terms
  carry_forward
]

required_top_fields.each do |field|
  errors << "missing top-level field: #{field}" if blank?(doc[field])
end

source_audio_analysis = resolve_path(doc["source_audio_analysis"], root)
errors << "source_audio_analysis is not readable: #{doc['source_audio_analysis']}" unless readable_file?(source_audio_analysis)

canonical_terms = doc["canonical_terms"]
if canonical_terms.is_a?(Hash)
  %w[
    wardrobe_style_review
    wardrobe_lane
    garment_inventory
    member_application
    section_rotation
    reject_terms
  ].each do |term|
    errors << "canonical_terms.#{term} is required" if blank?(canonical_terms[term])
  end
else
  errors << "canonical_terms must be a mapping"
end

automation_loop = doc["automation_loop"]
errors << "automation_loop must be a non-empty array" unless automation_loop.is_a?(Array) && !automation_loop.empty?

lanes = doc["wardrobe_lanes"]
lane_ids = []
if lanes.is_a?(Array) && !lanes.empty?
  seen = {}
  lanes.each_with_index do |lane, idx|
    unless lane.is_a?(Hash)
      errors << "wardrobe_lanes[#{idx}] must be a mapping"
      next
    end

    %w[id function image_ref garment_inventory use].each do |field|
      errors << "wardrobe_lanes[#{idx}].#{field} is required" if blank?(lane[field])
    end

    lane_id = lane["id"].to_s
    if seen[lane_id]
      errors << "duplicate wardrobe lane id: #{lane_id}"
    else
      seen[lane_id] = true unless lane_id.empty?
      lane_ids << lane_id unless lane_id.empty?
    end

    image_path = resolve_path(lane["image_ref"], root)
    errors << "wardrobe_lanes.#{lane_id}.image_ref is not readable: #{lane['image_ref']}" unless readable_file?(image_path)

    inventory = lane["garment_inventory"]
    errors << "wardrobe_lanes.#{lane_id}.garment_inventory must be a non-empty array" unless inventory.is_a?(Array) && !inventory.empty?
  end
else
  errors << "wardrobe_lanes must be a non-empty array"
end

member_application = doc["member_application"]
if member_application.is_a?(Hash) && !member_application.empty?
  # The legacy lane used this as a migration hint for the original five-member
  # roster. A bounded Founder-requested evidence review declares its active
  # cast explicitly below, so fixed IDs are neither useful nor truthful there.
  unless doc["member_style_evidence_mode"]
    %w[M03 M04 M05 M08 M11].each do |member|
      warnings << "member_application missing #{member}" unless member_application.key?(member)
    end
  end
else
  errors << "member_application must be a non-empty mapping"
end

section_rotation = doc["section_rotation"]
errors << "section_rotation must be a non-empty mapping" unless section_rotation.is_a?(Hash) && !section_rotation.empty?

reject_terms = doc["reject_terms"]
errors << "reject_terms must be a non-empty array" unless reject_terms.is_a?(Array) && !reject_terms.empty?

carry_forward = doc["carry_forward"]
if carry_forward.is_a?(Hash) && !carry_forward.empty?
  %w[00 00A 01].each do |stage|
    warnings << "carry_forward missing #{stage}" unless carry_forward.key?(stage)
  end
else
  errors << "carry_forward must be a non-empty mapping"
end

style_evidence = doc["member_style_evidence_mode"]
if style_evidence
  unless doc["schema_version"] == "idol-wardrobe-style-review.v2"
    errors << "member_style_evidence_mode requires schema_version idol-wardrobe-style-review.v2"
  end

  unless style_evidence.is_a?(Hash)
    errors << "member_style_evidence_mode must be a mapping"
    style_evidence = {}
  end

  errors << "member_style_evidence_mode.activation must be Founder-requested idol source evidence" unless style_evidence["activation"] == "founder_requested_idol_source_style_evidence"
  errors << "member_style_evidence_mode.review_status must remain founder_review_pending" unless style_evidence["review_status"] == "founder_review_pending"

  scope = style_evidence["source_scope"]
  if scope.is_a?(Hash)
    errors << "member_style_evidence_mode.source_scope.source_class must be idol_editorial_or_performance" unless scope["source_class"] == "idol_editorial_or_performance"
    weekly_status = scope["weekly_idol_evidence_status"]
    unless %w[completed_weekly_bundle weekly_radar_unavailable_official_editorial_fallback].include?(weekly_status)
      errors << "member_style_evidence_mode.source_scope.weekly_idol_evidence_status is invalid"
    end
    if weekly_status == "weekly_radar_unavailable_official_editorial_fallback" && blank?(scope["weekly_radar_unavailable_reason"])
      errors << "member_style_evidence_mode.source_scope.weekly_radar_unavailable_reason is required for fallback"
    end
    errors << "member_style_evidence_mode.source_scope must preserve style_reference_not_member_identity_reference" unless scope["source_identity_guard"] == "style_reference_not_member_identity_reference"
  else
    errors << "member_style_evidence_mode.source_scope must be a mapping"
  end

  requirements = style_evidence["candidate_requirements"]
  if requirements.is_a?(Hash)
    errors << "member_style_evidence_mode requires three outfit candidates per member" unless requirements["outfit_candidates_per_member"] == 3
    errors << "member_style_evidence_mode requires three hair candidates per member" unless requirements["hair_candidates_per_member"] == 3
    errors << "member_style_evidence_mode makeup selection must remain deferred to displayed images" unless requirements["makeup_selection"] == "defer_to_displayed_outfit_and_hair_images"
  else
    errors << "member_style_evidence_mode.candidate_requirements must be a mapping"
  end

  makeup = style_evidence["makeup_strategy"]
  if makeup.is_a?(Hash)
    allowed_makeup_modes = %w[defer_to_displayed_outfit_and_hair_images primary_screen_problem_exception]
    errors << "member_style_evidence_mode.makeup_strategy.mode is invalid" unless allowed_makeup_modes.include?(makeup["mode"])
    if makeup["mode"] == "primary_screen_problem_exception" && blank?(makeup["exception_reason"])
      errors << "member_style_evidence_mode.makeup_strategy.exception_reason is required for exception"
    end
  else
    errors << "member_style_evidence_mode.makeup_strategy must be a mapping"
  end

  trend_basis = style_evidence["trend_basis"]
  if trend_basis.is_a?(Hash)
    %w[source_path sha256 observed_signal current_run_translation].each do |field|
      errors << "member_style_evidence_mode.trend_basis.#{field} is required" unless required_text?(trend_basis[field])
    end
    trend_path = resolve_path(trend_basis["source_path"], root)
    check_hash(trend_path, trend_basis["sha256"], errors, "member_style_evidence_mode.trend_basis.source_path") if trend_path
  else
    errors << "member_style_evidence_mode.trend_basis must be a mapping"
  end

  candidates = style_evidence["candidates"]
  candidate_by_id = {}
  candidate_groups = Hash.new { |hash, key| hash[key] = [] }
  if candidates.is_a?(Array) && !candidates.empty?
    candidates.each_with_index do |candidate, idx|
      label = "member_style_evidence_mode.candidates[#{idx}]"
      unless candidate.is_a?(Hash)
        errors << "#{label} must be a mapping"
        next
      end

      %w[candidate_id member_id category comparison_role source_class source_identity source_page_url original_image_url source_record_path observed_facts take discard lock_fit section_fit risk trend_translation director_recommendation founder_decision].each do |field|
        errors << "#{label}.#{field} is required" unless required_text?(candidate[field])
      end

      candidate_id = candidate["candidate_id"].to_s
      errors << "duplicate member-style candidate id: #{candidate_id}" if !candidate_id.empty? && candidate_by_id.key?(candidate_id)
      candidate_by_id[candidate_id] = candidate unless candidate_id.empty?

      category = candidate["category"].to_s
      role = candidate["comparison_role"].to_s
      member_id = candidate["member_id"].to_s
      errors << "#{label}.category must be outfit or hair" unless %w[outfit hair].include?(category)
      errors << "#{label}.comparison_role must be lead, alternative, or boundary_test" unless %w[lead alternative boundary_test].include?(role)
      errors << "#{label}.source_class must be idol_editorial_or_performance" unless candidate["source_class"] == "idol_editorial_or_performance"
      errors << "#{label}.founder_decision must remain pending" unless candidate["founder_decision"] == "pending"
      errors << "#{label}.director_recommendation is invalid" unless %w[pass hold revise].include?(candidate["director_recommendation"])
      errors << "#{label}.source_page_url must be an http(s) source page" unless candidate["source_page_url"].to_s.match?(%r{\Ahttps?://})
      errors << "#{label}.original_image_url must be an http(s) image URL" unless candidate["original_image_url"].to_s.match?(%r{\Ahttps?://})

      source_record_path = resolve_path(candidate["source_record_path"], root)
      errors << "#{label}.source_record_path is not readable: #{candidate['source_record_path']}" unless readable_file?(source_record_path)

      asset = candidate["local_asset"]
      if asset.is_a?(Hash)
        %w[path sha256 pixel_inspection].each do |field|
          errors << "#{label}.local_asset.#{field} is required" unless required_text?(asset[field])
        end
        asset_path = resolve_path(asset["path"], root)
        check_hash(asset_path, asset["sha256"], errors, "#{label}.local_asset.path") if asset_path
      else
        errors << "#{label}.local_asset must be a mapping"
      end

      hard_conflicts = candidate["hard_conflict_axes"]
      unless hard_conflicts.is_a?(Array)
        errors << "#{label}.hard_conflict_axes must be an array"
        hard_conflicts = []
      end
      if hard_conflicts.length > 1
        errors << "#{label} has multiple hard lock conflicts and may appear only as boundary_test" unless role == "boundary_test"
        errors << "#{label} has multiple hard lock conflicts and cannot carry a pass recommendation" if candidate["director_recommendation"] == "pass"
      end

      candidate_groups[[member_id, category]] << candidate
    end
  else
    errors << "member_style_evidence_mode.candidates must be a non-empty array"
  end

  member_sets = style_evidence["member_evidence_sets"]
  member_ids = []
  if member_sets.is_a?(Array) && !member_sets.empty?
    member_sets.each_with_index do |member_set, idx|
      label = "member_style_evidence_mode.member_evidence_sets[#{idx}]"
      unless member_set.is_a?(Hash)
        errors << "#{label} must be a mapping"
        next
      end

      member_id = member_set["member_id"].to_s
      errors << "#{label}.member_id is required" if member_id.empty?
      errors << "duplicate member-style evidence member_id: #{member_id}" if !member_id.empty? && member_ids.include?(member_id)
      member_ids << member_id unless member_id.empty?

      face_only = member_set["face_only_identity_check"]
      if face_only.is_a?(Hash)
        %w[asset_path sha256 pixel_inspection fit_observation].each do |field|
          errors << "#{label}.face_only_identity_check.#{field} is required" unless required_text?(face_only[field])
        end
        face_only_path = resolve_path(face_only["asset_path"], root)
        check_hash(face_only_path, face_only["sha256"], errors, "#{label}.face_only_identity_check.asset_path") if face_only_path
      else
        errors << "#{label}.face_only_identity_check must be a mapping"
      end

      {"outfit" => member_set["outfit_candidate_ids"], "hair" => member_set["hair_candidate_ids"]}.each do |category, ids|
        unless ids.is_a?(Array) && ids.length == 3 && ids.uniq.length == 3
          errors << "#{label}.#{category}_candidate_ids must contain exactly three unique candidate ids"
          next
        end
        group = candidate_groups[[member_id, category]]
        errors << "#{label} must have exactly three #{category} candidates" unless group.length == 3
        roles = group.map { |candidate| candidate["comparison_role"].to_s }
        errors << "#{label} #{category} candidates must cover lead, alternative, and boundary_test once" unless roles.sort == %w[alternative boundary_test lead]
        ids.each do |candidate_id|
          candidate = candidate_by_id[candidate_id]
          if candidate.nil?
            errors << "#{label}.#{category}_candidate_ids references missing candidate #{candidate_id}"
          elsif candidate["member_id"].to_s != member_id || candidate["category"].to_s != category
            errors << "#{label}.#{category}_candidate_ids references a different member/category candidate #{candidate_id}"
          end
        end
      end
    end
  else
    errors << "member_style_evidence_mode.member_evidence_sets must be a non-empty array"
  end

  presentation = style_evidence["review_presentation"]
  if presentation.is_a?(Hash)
    %w[html source_index].each do |kind|
      binding = presentation[kind]
      if binding.is_a?(Hash)
        binding_path = resolve_path(binding["path"], root)
        check_hash(binding_path, binding["sha256"], errors, "member_style_evidence_mode.review_presentation.#{kind}.path") if binding_path
      else
        errors << "member_style_evidence_mode.review_presentation.#{kind} must be a mapping"
      end
    end

    sheets = presentation["static_contact_sheets"]
    sheets = [] unless sheets.is_a?(Array)
    sheet_member_ids = []
    sheets.each_with_index do |sheet, idx|
      label = "member_style_evidence_mode.review_presentation.static_contact_sheets[#{idx}]"
      unless sheet.is_a?(Hash)
        errors << "#{label} must be a mapping"
        next
      end
      sheet_member_ids << sheet["member_id"].to_s
      sheet_path = resolve_path(sheet["path"], root)
      check_hash(sheet_path, sheet["sha256"], errors, "#{label}.path") if sheet_path
    end
    if presentation["remote_delivery_requested"] == true
      missing_sheets = member_ids - sheet_member_ids
      errors << "member_style_evidence_mode remote delivery is missing static contact sheets for #{missing_sheets.join(', ')}" unless missing_sheets.empty?
    end
  else
    errors << "member_style_evidence_mode.review_presentation must be a mapping"
  end

  promotion_guard = style_evidence["promotion_guard"]
  if promotion_guard.is_a?(Hash)
    errors << "member_style_evidence_mode.promotion_guard.candidate_state must remain founder_review_pending" unless promotion_guard["candidate_state"] == "founder_review_pending"
    errors << "member_style_evidence_mode.promotion_guard.selection_scope must limit promotion to elements" unless promotion_guard["selection_scope"] == "elements_not_full_celebrity_look"
    errors << "member_style_evidence_mode.promotion_guard.automatic_promotion must be false" unless promotion_guard["automatic_promotion"] == false
  else
    errors << "member_style_evidence_mode.promotion_guard must be a mapping"
  end
end

if errors.empty?
  suffix = style_evidence ? " with Founder-requested member style evidence" : ""
  puts "OK: #{lane_ids.length} wardrobe lane(s) validated#{suffix}"
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
