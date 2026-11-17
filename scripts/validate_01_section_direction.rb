#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_front_planning_sequence_core_hold"
require_relative "lib/idol_storyline_density_locator_contract"
require_relative "lib/idol_kinetic_slot_sheet_contract"
require_relative "lib/idol_source_connection_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "song-choreography-performance-mv-map.schema.json")
FRONT_VALIDATOR = ROOT.join("scripts", "validate_front_planning_readiness.rb")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {root: ROOT, json: false, max_errors: 40, admission_graph: false}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_01_section_direction.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
  opts.on("--admission-graph") { options[:admission_graph] = true }
end.parse!

artifact_arg = ARGV.shift
abort "01 direction path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "document must be an object" unless value.is_a?(Hash)
  value
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical_value(value[key]) }
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def inside?(path, root)
  relative = path.relative_path_from(root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

def pinterest_unit?(unit)
  [unit["source_identity"], unit["selected_locator"]].compact.join(" ").match?(%r{(?:pinterest\.[a-z.]+/pin/|pin\.it/|pinterest[-_: ]?pin)}i)
end

def bound_creative_source_rows(document)
  rows = []
  Array(document["official_core_cuts"]).each do |core|
    core_id = core.to_h["core_cut_id"].to_s
    image = core.to_h["primary_image"].to_h
    unless image["actual_path"].to_s.empty?
      rows << { "source_id" => "#{core_id}.primary_image", "path" => image["actual_path"].to_s, "sha256" => image["sha256"].to_s }
    end
    binding = core.to_h["core_reference_binding"].to_h
    if binding["required"] == true && !binding["actual_path"].to_s.empty?
      rows << { "source_id" => "#{core_id}.core_reference", "path" => binding["actual_path"].to_s, "sha256" => binding["sha256"].to_s }
    end
  end
  Array(document["hero_core_adoptions"]).each do |adoption|
    next if adoption.to_h["output_path"].to_s.empty?

    rows << {
      "source_id" => adoption["hero_core_candidate_id"].to_s,
      "path" => adoption["output_path"].to_s,
      "sha256" => adoption["output_sha256"].to_s
    }
  end
  Array(document["section_directions"]).each do |direction|
    Array(direction["reference_applications"]).each do |application|
      next if application.to_h["source_path"].to_s.empty?

      rows << {
        "source_id" => application["reference_unit_id"].to_s,
        "path" => application["source_path"].to_s,
        "sha256" => application["source_sha256"].to_s
      }
    end
  end
  rows.uniq { |row| [row["source_id"], row["path"], row["sha256"]] }
end

SEQUENCE_MOTION_DIMENSIONS = %w[
  depth alternate_view reveal_space rear_world_direction identity crop
  occlusion continuity start_landing
].freeze

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
unless inside?(artifact, root) && artifact.file?
  errors << "01 direction artifact is missing or outside the repository"
end

document = {}
reference_unit_reachability = []
if errors.empty?
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => e
    errors << "cannot parse 01 direction: #{e.message}"
  end
end

if artifact.file?
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    artifact.to_s,
    chdir: ROOT.to_s
  )
  errors << "JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

if document.any?
  errors << "only 01 schema 3.0 is active" unless document["schema_version"].to_s == "3.0"
  front_ref = document["source_front_planning"].to_h
  front_path = resolve_path(front_ref["path"], root)
  if !inside?(front_path, root) || !front_path.file?
    errors << "source_front_planning is missing or outside the repository"
  else
    # The whole-artifact SHA is the authored baseline. Current validity is
    # established below from the exact global and per-section value
    # projections, so an unrelated Front Planning byte change does not stale
    # every 01 section.
    front = load_mapping(front_path)
    stdout, stderr, status = Open3.capture3(
      "ruby",
      FRONT_VALIDATOR.to_s,
      "--root",
      root.to_s,
      *(options[:admission_graph] ? ["--admission-graph"] : []),
      front_path.to_s,
      chdir: ROOT.to_s
    )
    errors << "source Front Planning failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
    errors << "source Front Planning must be Director-closed after Founder Direction Alignment PASS" unless front["status"] == "director_closed" && front.dig("founder_gate", "decision") == "pass"
    frozen_fp = IdolFrontPlanningSequenceCoreHold.skip_frozen_legacy?(front_path, admission_graph: options[:admission_graph])
    unless frozen_fp
      IdolStorylineDensityLocatorContract.close_artifact(root, front_path, document: front).each do |error|
        errors << "01 entrance density locator: #{error}"
      end
    end
    errors << "content_id differs from Front Planning" unless document["content_id"].to_s == front["content_id"].to_s

    imported_head = document["imported_fp_head"].to_h
    errors << "imported_fp_head must bind source_front_planning path and SHA-256" unless imported_head["path"].to_s == front_ref["path"].to_s && imported_head["sha256"].to_s == front_ref["sha256"].to_s
    errors << "imported_fp_head must identify active FP v17" unless imported_head["schema_version"].to_s == "front-planning-readiness.v17"
    selected_route_id = imported_head["selected_candidate_route_id"].to_s
    selected_route = Array(front["candidate_routes"]).find { |row| row["candidate_id"].to_s == selected_route_id }
    errors << "imported_fp_head selected candidate route does not resolve" if selected_route.nil?
    unless frozen_fp
      major_ids = IdolKineticSlotSheetContract.selected_major_ids(selected_route)
      IdolKineticSlotSheetContract.coverage_errors(
        front_path,
        major_ids,
        document: front,
        selected_route: selected_route
      ).each do |error|
        errors << "01 entrance kinetic slot sheet: #{error}"
      end
      bound_creative_source_rows(document).each do |row|
        connection = IdolSourceConnectionContract.connection_of(root, row)
        next if connection["status"] == "connected"

        errors << "01 entrance source #{row["source_id"]} not_connected: #{connection["reason"]}"
      end
    end
    active_storyline = front.dig("storyline_lineage", "active_version").to_h
    unless imported_head["active_storyline_version_id"].to_s == active_storyline["version_id"].to_s && imported_head["active_storyline_sha256"].to_s == active_storyline["full_storyline_text_sha256"].to_s
      errors << "imported_fp_head active storyline id/hash differs from Front Planning"
    end
    screen_map = front["screen_progression_map"].to_h
    unless imported_head["screen_progression_map_id"].to_s == screen_map["screen_progression_map_id"].to_s && imported_head["screen_progression_map_sha256"].to_s == value_sha256(screen_map)
      errors << "imported_fp_head screen progression map id/hash differs from Front Planning"
    end
    screen_projection = document["screen_progression_map_projection"].to_h
    errors << "screen_progression_map_projection pointer is not canonical" unless screen_projection["source_json_pointer"].to_s == "/screen_progression_map"
    errors << "screen_progression_map_projection hash is stale" unless screen_projection["source_value_sha256"].to_s == value_sha256(screen_map)
    errors << "screen_progression_map_projection value differs" unless canonical_value(screen_projection["projected_value"]) == canonical_value(screen_map)

    derivative_route_id = document["derivative_route_id"].to_s
    production_scope_id = document["production_scope_id"].to_s
    derivative = Array(front.dig("creative_experiment", "derivative_routes")).find { |row| row["derivative_route_id"].to_s == derivative_route_id }
    errors << "01 derivative_route_id does not resolve in FP creative_experiment" if derivative.nil?
    errors << "01 derivative route production_scope_id differs" if derivative && derivative["production_scope_id"].to_s != production_scope_id
    scope = Array(front["production_scopes"]).find { |row| row["production_scope_id"].to_s == production_scope_id }
    errors << "01 production_scope_id does not resolve in Front Planning" if scope.nil?
    errors << "01 production scope must be approved_for_01" if scope && scope["state"].to_s != "approved_for_01"

    selected_slots = if selected_route
                       Array(selected_route["sections"]).flat_map do |section|
                         Array(section["route_major_expansions"]).flat_map { |major| Array(major["core_cut_slots"]) }
                       end
                     else
                       []
                     end
    selected_motion_by_major = Array(front["major_scene_catalog"]).each_with_object({}) do |major, rows|
      candidate_set = major["sequence_composition_candidate_set"].to_h
      selected_id = candidate_set["selected_sequence_composition_id"].to_s
      candidate = Array(candidate_set["candidates"]).find { |row| row["sequence_composition_id"].to_s == selected_id }
      binding = candidate.to_h["sequence_motion_analysis_binding"].to_h
      next if binding.empty?
      analysis_path = resolve_path(binding["path"], root)
      next unless inside?(analysis_path, root) && analysis_path.file?
      begin
        analysis = load_mapping(analysis_path)
        analysis_row = binding["json_pointer"].to_s.split("/").drop(1).reduce(analysis) do |value, token|
          value.is_a?(Array) ? value.fetch(Integer(token, 10)) : value.fetch(token)
        end
        rows[major["major_scene_id"].to_s] = {
          "analysis_id" => analysis["analysis_id"].to_s,
          "selected_sequence_composition_id" => selected_id,
          "selected_unit_ids" => Array(analysis_row.to_h["sequence_unit_bindings"]).map { |row| row["sequence_unit_id"].to_s },
          "findings" => analysis_row.to_h["motion_support_finding"].to_h
        }
      rescue JSON::ParserError, Psych::Exception, TypeError, KeyError, IndexError, ArgumentError
        errors << "#{major['major_scene_id']} selected Sequence Motion Analysis row cannot be resolved for 01 adoption"
      end
    end
    scope_node_ids = Array(scope.to_h["selected_node_ids"]).map(&:to_s)
    nodes_by_id = Array(screen_map["nodes"]).to_h { |row| [row["node_id"].to_s, row] }
    selected_slots = selected_slots.select do |slot|
      scope_node_ids.any? { |node_id| nodes_by_id.dig(node_id, "source_id").to_s == slot["core_slot_id"].to_s }
    end
    expected_slot_ids = selected_slots.map { |row| row["core_slot_id"].to_s }
    fp_core_reference_decisions = Array(front["core_reference_bindings"]).to_h do |row|
      [row["core_slot_id"].to_s, row["decision"].to_h]
    end
    official_cores = Array(document["official_core_cuts"])
    core_ids = official_cores.map { |row| row["core_cut_id"].to_s }
    errors << "Official Core ids must be unique" unless core_ids.uniq.length == core_ids.length
    errors << "Official Core Storyboard must exact-cover selected production-scope Core Slots" unless official_cores.map { |row| row["source_core_slot_id"].to_s }.sort == expected_slot_ids.sort
    official_cores.each_with_index do |core, index|
      core_id = core["core_cut_id"].to_s
      slot = selected_slots.find { |row| row["core_slot_id"].to_s == core["source_core_slot_id"].to_s }
      errors << "#{core_id} source Core Slot does not resolve" if slot.nil?
      if slot
        errors << "#{core_id} parent Major differs from FP Core Slot" unless core["parent_major_scene_id"].to_s == slot["major_scene_id"].to_s
        errors << "#{core_id} section differs from FP Core Slot" unless core["section_id"].to_s == slot["section_id"].to_s
      end
      motion = selected_motion_by_major[core["parent_major_scene_id"].to_s]
      if motion
        phase_ids = Array(core["sequence_phase_bindings"]).map(&:to_s)
        unless phase_ids.any? && (phase_ids - motion.fetch("selected_unit_ids")).empty?
          errors << "#{core_id} sequence_phase_bindings must be a nonempty subset of the selected Sequence Motion candidate units"
        end
      end
      errors << "#{core_id} active storyline differs from FP" unless core["active_storyline_version_id"].to_s == active_storyline["version_id"].to_s
      node = nodes_by_id[core["screen_progression_node_id"].to_s]
      errors << "#{core_id} screen progression node does not resolve" unless node && node["source_id"].to_s == core["source_core_slot_id"].to_s
      image = core["primary_image"].to_h
      image_path = resolve_path(image["actual_path"], root)
      if !inside?(image_path, root) || !image_path.file?
        errors << "#{core_id} must own exactly one actual primary image"
      elsif Digest::SHA256.file(image_path).hexdigest != image["sha256"].to_s
        errors << "#{core_id} primary image SHA-256 is stale"
      end
      binding = core["core_reference_binding"].to_h
      fp_reference_decision = fp_core_reference_decisions[core["source_core_slot_id"].to_s].to_h
      if binding["required"] == true
        errors << "#{core_id} actual Core reference requires an FP selected_exact_reference decision" unless fp_reference_decision["kind"].to_s == "selected_exact_reference"
        unless binding["selected_reference_candidate_id"].to_s == fp_reference_decision["selected_reference_candidate_id"].to_s && binding["actual_path"].to_s == fp_reference_decision["actual_path"].to_s && binding["sha256"].to_s == fp_reference_decision["sha256"].to_s
          errors << "#{core_id} actual Core reference must exact-copy the FP Core Slot decision"
        end
        reference_path = resolve_path(binding["actual_path"], root)
        if !inside?(reference_path, root) || !reference_path.file?
          errors << "#{core_id} selected exact Core reference is missing"
        elsif Digest::SHA256.file(reference_path).hexdigest != binding["sha256"].to_s
          errors << "#{core_id} selected exact Core reference SHA-256 is stale"
        end
        errors << "#{core_id} selected exact Core reference cannot also carry a waiver" unless binding["founder_reference_waiver"].nil?
      else
        waiver = binding["founder_reference_waiver"].to_h
        fp_waiver = fp_reference_decision["founder_reference_waiver"].to_h
        errors << "#{core_id} Core reference waiver requires an FP founder_waiver decision" unless fp_reference_decision["kind"].to_s == "founder_waiver"
        errors << "#{core_id} Core reference waiver must name this exact Core" unless waiver["exact_core_cut_id"].to_s == core_id
        errors << "#{core_id} Core reference waiver must be Founder-authored" unless waiver["authored_by"].to_s == "founder"
        errors << "#{core_id} Core reference waiver requires an exact reason" if waiver["reason"].to_s.strip.empty?
        errors << "#{core_id} Core reference waiver reason must exact-copy the FP Founder reason" unless waiver["reason"].to_s == fp_waiver["founder_verbatim_reason"].to_s
      end
      expected_order = index + 1
      errors << "#{core_id} Official Core order must be contiguous" unless core["order_within_section"] == expected_order
    end
    errors << "core_storyboard must list every Official Core exactly once in order" unless Array(document["core_storyboard"]).map(&:to_s) == core_ids
    errors << "branch_expansion_needs must exact-cover every Official Core" unless Array(document["branch_expansion_needs"]).map { |row| row["core_cut_id"].to_s }.sort == core_ids.sort
    errors << "core_motion_readiness_map must exact-cover every Official Core" unless Array(document["core_motion_readiness_map"]).map { |row| row["core_cut_id"].to_s }.sort == core_ids.sort
    hero_ids = Array(front["hero_core_cut_candidates"]).map { |row| row["hero_core_id"].to_s }
    Array(document["hero_core_adoptions"]).each do |adoption|
      errors << "#{adoption['hero_core_candidate_id']} Hero adoption does not resolve in FP" unless hero_ids.include?(adoption["hero_core_candidate_id"].to_s)
      errors << "#{adoption['adopted_as_core_cut_id']} Hero adoption names unknown Official Core" unless core_ids.include?(adoption["adopted_as_core_cut_id"].to_s)
      output_path = resolve_path(adoption["output_path"], root)
      errors << "#{adoption['hero_core_candidate_id']} adopted Hero output is missing or stale" unless inside?(output_path, root) && output_path.file? && Digest::SHA256.file(output_path).hexdigest == adoption["output_sha256"].to_s
    end
    review = document["whole_film_core_review"].to_h
    errors << "whole-film Core review must exact-cover every Official Core" unless Array(review["reviewed_core_cut_ids"]).map(&:to_s) == core_ids

    storyline_projection = document["storyline_lineage_projection"].to_h
    errors << "storyline_lineage_projection pointer is not canonical" unless storyline_projection["source_json_pointer"] == "/storyline_lineage"
    errors << "storyline_lineage_projection hash is stale" unless storyline_projection["source_value_sha256"].to_s == value_sha256(front["storyline_lineage"])
    unless canonical_value(storyline_projection["projected_value"]) == canonical_value(front["storyline_lineage"])
      errors << "storyline_lineage_projection must exact-copy the complete PRE-00-rooted full-text lineage"
    end
    audience_target_projection = document["pre00_audience_target_lineage_projection"].to_h
    errors << "pre00_audience_target_lineage_projection pointer is not canonical" unless audience_target_projection["source_json_pointer"] == "/pre00_audience_target_lineage"
    errors << "pre00_audience_target_lineage_projection hash is stale" unless audience_target_projection["source_value_sha256"].to_s == value_sha256(front["pre00_audience_target_lineage"])
    unless canonical_value(audience_target_projection["projected_value"]) == canonical_value(front["pre00_audience_target_lineage"])
      errors << "pre00_audience_target_lineage_projection must exact-copy PRE-00 audience profiles, X envelope, and title target intersection"
    end
    target_projection = document["target_message_projection"].to_h
    errors << "target_message_projection pointer is not canonical" unless target_projection["source_json_pointer"] == "/target_message_lock"
    errors << "target_message_projection hash is stale" unless target_projection["source_value_sha256"].to_s == value_sha256(front["target_message_lock"])
    errors << "target_message_projection value differs" unless canonical_value(target_projection["projected_value"]) == canonical_value(front["target_message_lock"])
    spine_projection = document["whole_film_spine_projection"].to_h
    errors << "whole_film_spine_projection pointer is not canonical" unless spine_projection["source_json_pointer"] == "/whole_film_spine"
    errors << "whole_film_spine_projection hash is stale" unless spine_projection["source_value_sha256"].to_s == value_sha256(front["whole_film_spine"])
    errors << "whole_film_spine_projection value differs" unless canonical_value(spine_projection["projected_value"]) == canonical_value(front["whole_film_spine"])

    alignment = front["founder_visual_alignment"].to_h
    alignment_projection = document["founder_visual_alignment_projection"].to_h
    unless alignment_projection["source_json_pointer"] == "/founder_visual_alignment"
      errors << "founder_visual_alignment_projection pointer is not canonical"
    end
    unless alignment_projection["source_value_sha256"].to_s == value_sha256(alignment)
      errors << "founder_visual_alignment_projection hash is stale"
    end
    unless canonical_value(alignment_projection["projected_value"]) == canonical_value(alignment)
      errors << "founder_visual_alignment_projection value differs"
    end
    alignment_sections = Array(alignment["section_readouts"])
    alignment_cuts = Array(alignment["planning_cut_readouts"])

    front_sections = Array(front["section_plan"])
    directions = Array(document["section_directions"])
    errors << "01 section order and ids must exact-copy Front Planning" unless directions.map { |row| row["section_id"].to_s } == front_sections.map { |row| row["section_id"].to_s }
    front_reference_units = Array(front.dig("reference_connection_research", "reference_units"))
    reference_unit_reachability = front_reference_units.each_with_index.map do |row, row_index|
      {
        "reference_unit_id" => row["reference_unit_id"].to_s,
        "source_json_pointer" => "/reference_connection_research/reference_units/#{row_index}",
        "source_value_sha256" => value_sha256(row)
      }
    end
    reference_units = front_reference_units.to_h do |row|
      [row["reference_unit_id"].to_s, row]
    end
    visual = front["current_title_visual_identity"].to_h

    directions.each_with_index do |direction, index|
      source_section = front_sections[index]
      next unless source_section
      section_id = direction["section_id"].to_s
      source_major_scenes = Array(source_section["major_scene_flow"])
      source_major_scene_ids = source_major_scenes.map { |scene| scene["major_scene_id"].to_s }
      motion_major_ids = source_major_scene_ids.select { |major_id| selected_motion_by_major.key?(major_id) }
      adoption_rows = Array(direction["sequence_motion_adoptions"])
      adoption_major_ids = adoption_rows.map { |row| row["major_scene_id"].to_s }
      unless adoption_major_ids == motion_major_ids && adoption_major_ids.uniq.length == adoption_major_ids.length
        errors << "#{section_id} typed Sequence Motion adoptions must exact-cover selected analyzed Majors once in Front Planning order"
      end
      source_major_scene_ids.each do |major_id|
        motion = selected_motion_by_major[major_id]
        next unless motion

        adoption = adoption_rows.find { |row| row["major_scene_id"].to_s == major_id }
        analysis_id = motion.fetch("analysis_id")
        unless adoption.is_a?(Hash)
          errors << "#{section_id} must record one typed 01 adoption for selected #{analysis_id}"
          next
        end
        errors << "#{section_id} Sequence Motion adoption analysis_id differs from the FP-selected binding" unless adoption["analysis_id"].to_s == analysis_id
        errors << "#{section_id} Sequence Motion adoption selected candidate differs from Front Planning" unless adoption["selected_sequence_composition_id"].to_s == motion["selected_sequence_composition_id"].to_s
        dispositions = adoption["dimension_dispositions"].to_h
        errors << "#{section_id} Sequence Motion adoption must disposition all nine dimensions exactly once" unless dispositions.keys.map(&:to_s).sort == SEQUENCE_MOTION_DIMENSIONS.sort
        errors << "#{section_id} Sequence Motion adoption requires an independently authored reason" if adoption["authored_reason"].to_s.strip.empty?
        camera_rows = Array(direction["still_camera_coverage"])
        branch_rows = Array(direction["scene_expansions"]).flat_map { |row| Array(row["branching_opportunities"]) }
        major_cores = official_cores.select { |core| core["parent_major_scene_id"].to_s == major_id }
        applied_core_ids = Array(adoption["applied_official_core_cut_ids"]).map(&:to_s)
        applied_camera_ids = Array(adoption["applied_still_camera_coverage_ids"]).map(&:to_s)
        applied_branch_ids = Array(adoption["applied_branching_opportunity_ids"]).map(&:to_s)
        disposition_values = SEQUENCE_MOTION_DIMENSIONS.map { |dimension| dispositions[dimension].to_s }
        applied_id_count = applied_core_ids.length + applied_camera_ids.length + applied_branch_ids.length
        case adoption["overall_disposition"].to_s
        when "reject"
          errors << "#{section_id} overall Sequence Motion reject requires all nine dimensions rejected" unless disposition_values.all? { |value| value == "reject" }
          errors << "#{section_id} overall Sequence Motion reject requires every applied truth id list empty" unless applied_id_count.zero?
        when "adopt"
          errors << "#{section_id} overall Sequence Motion adopt requires all nine dimensions adopted" unless disposition_values.all? { |value| value == "adopt" }
          errors << "#{section_id} overall Sequence Motion adopt requires at least one exact applied truth id" unless applied_id_count.positive?
        when "partial"
          aggregate_partial = disposition_values.any? { |value| value != "reject" } && !disposition_values.all? { |value| value == "adopt" }
          errors << "#{section_id} overall Sequence Motion partial requires a genuinely partial adopt/reject dimension aggregate" unless aggregate_partial
          errors << "#{section_id} overall Sequence Motion partial requires at least one exact applied truth id" unless applied_id_count.positive?
        end
        errors << "#{section_id} Sequence Motion adoption names an unrelated Official Core" unless (applied_core_ids - major_cores.map { |row| row["core_cut_id"].to_s }).empty?
        errors << "#{section_id} Sequence Motion adoption names an unknown still camera coverage row" unless (applied_camera_ids - camera_rows.map { |row| row["coverage_id"].to_s }).empty?
        errors << "#{section_id} Sequence Motion adoption names an unknown branching opportunity" unless (applied_branch_ids - branch_rows.map { |row| row["opportunity_id"].to_s }).empty?
        applied_cameras = camera_rows.select { |row| applied_camera_ids.include?(row["coverage_id"].to_s) }
        applied_branches = branch_rows.select { |row| applied_branch_ids.include?(row["opportunity_id"].to_s) }
        if %w[adopt partial].include?(dispositions["depth"]) || %w[adopt partial].include?(dispositions["crop"])
          errors << "#{section_id} Sequence Motion depth/crop carry requires exact applied camera ids and authored still truth" unless applied_cameras.any? && applied_cameras.all? { |row| !row["depth_design"].to_s.empty? && !row["crop_negative_space"].to_s.empty? }
        end
        distinct_views = applied_cameras.map { |row| [row["shot_scale_distance"], row["camera_height"], row["direction_angle"]] }.uniq
        if %w[adopt partial].include?(dispositions["alternate_view"])
          errors << "#{section_id} Sequence Motion alternate-view carry requires at least two distinct authored still views" unless distinct_views.length >= 2
        end
        if %w[adopt partial].include?(dispositions["reveal_space"]) || %w[adopt partial].include?(dispositions["occlusion"])
          errors << "#{section_id} Sequence Motion reveal/occlusion carry requires exact applied Branch-opportunity ids" unless applied_branches.any? { |row| !row["observable_action_or_hold"].to_s.empty? && !row["space_object_or_relation_change"].to_s.empty? }
        end
        if %w[adopt partial].include?(dispositions["continuity"]) || %w[adopt partial].include?(dispositions["start_landing"])
          applied_cores = major_cores.select { |core| applied_core_ids.include?(core["core_cut_id"].to_s) }
          unless applied_cores.any? && applied_cores.all? { |core| Array(core["continuity_in"]).any? && Array(core["continuity_out"]).any? }
            errors << "#{section_id} Sequence Motion continuity/start-landing carry requires authored Official Core continuity truth"
          end
        end
      end
      source_key_screen_ids = source_major_scenes.flat_map do |scene|
        Array(scene["key_screen_anchors"]).map { |anchor| anchor["key_screen_id"].to_s }
      end
      key_screen_ids_by_scene = source_major_scenes.to_h do |scene|
        [
          scene["major_scene_id"].to_s,
          Array(scene["key_screen_anchors"]).map { |anchor| anchor["key_screen_id"].to_s }
        ]
      end
      projection = direction["source_front_planning_section"].to_h
      errors << "#{section_id} source pointer differs" unless projection["source_json_pointer"] == "/section_plan/#{index}"
      errors << "#{section_id} source section hash is stale" unless projection["source_value_sha256"].to_s == value_sha256(source_section)
      {
        "assigned_member_ids" => source_section["assigned_member_ids"],
        "screen_carrier" => source_section["screen_carrier"],
        "member_visual_asset_ids" => source_section["member_visual_asset_ids"],
        "background_world_asset_ids" => [],
        "sequence_unit_ids" => source_section["sequence_unit_ids"],
        "scene_reference_unit_ids" => source_section["scene_reference_unit_ids"],
        "major_scene_ids" => source_major_scene_ids,
        "key_screen_anchor_ids" => source_key_screen_ids
      }.each do |field, expected|
        errors << "#{section_id} #{field} differs from Front Planning" unless canonical_value(projection[field]) == canonical_value(expected)
      end

      source_alignment_index = alignment_sections.index { |row| row["section_id"].to_s == section_id }
      section_alignment = source_alignment_index.nil? ? nil : alignment_sections[source_alignment_index]
      section_alignment_projection = direction["section_alignment_projection"].to_h
      if section_alignment.nil?
        errors << "#{section_id} has no Founder visual alignment section readout"
      else
        expected_pointer = "/founder_visual_alignment/section_readouts/#{source_alignment_index}"
        errors << "#{section_id} alignment section pointer differs" unless section_alignment_projection["source_json_pointer"].to_s == expected_pointer
        errors << "#{section_id} alignment section id differs" unless section_alignment_projection["section_id"].to_s == section_id
        errors << "#{section_id} alignment section hash is stale" unless section_alignment_projection["source_value_sha256"].to_s == value_sha256(section_alignment)
        unless canonical_value(section_alignment_projection["projected_value"]) == canonical_value(section_alignment)
          errors << "#{section_id} alignment section value differs"
        end
      end

      source_alignment_cuts = alignment_cuts.each_with_index.select { |row, _cut_index| row["section_id"].to_s == section_id }
      cut_projections = Array(direction["planning_cut_alignment_projections"])
      unless cut_projections.map { |row| row["planning_cut_id"].to_s } == source_alignment_cuts.map { |row, _index| row["planning_cut_id"].to_s }
        errors << "#{section_id} planning-cut alignment projections must exact-cover Front Planning in order"
      end
      cut_projections.each_with_index do |cut_projection, cut_position|
        source_cut, source_cut_index = source_alignment_cuts[cut_position]
        next unless source_cut

        expected_pointer = "/founder_visual_alignment/planning_cut_readouts/#{source_cut_index}"
        errors << "#{section_id} #{source_cut['planning_cut_id']} alignment pointer differs" unless cut_projection["source_json_pointer"].to_s == expected_pointer
        errors << "#{section_id} #{source_cut['planning_cut_id']} source Key Screen differs" unless cut_projection["source_key_screen_id"].to_s == source_cut["source_key_screen_id"].to_s
        errors << "#{section_id} #{source_cut['planning_cut_id']} alignment hash is stale" unless cut_projection["source_value_sha256"].to_s == value_sha256(source_cut)
        unless canonical_value(cut_projection["projected_value"]) == canonical_value(source_cut)
          errors << "#{section_id} #{source_cut['planning_cut_id']} alignment value differs"
        end
      end

      visual_projection = direction["visual_projection"].to_h
      errors << "#{section_id} visual album key differs" unless visual_projection["current_title_album_key"].to_s == visual["album_key"].to_s
      errors << "#{section_id} visual title key differs" unless visual_projection["current_title_key"].to_s == visual["title_key"].to_s
      errors << "#{section_id} member visual pool differs" unless canonical_value(visual_projection["member_visual_asset_ids"]) == canonical_value(source_section["member_visual_asset_ids"])
      errors << "#{section_id} separate background/world asset pool must remain empty" unless Array(visual_projection["background_world_asset_ids"]).empty?

      assigned_sequence_unit_ids = Array(source_section["sequence_unit_ids"]).map(&:to_s)
      sequence_reference_ids = reference_units.map do |reference_id, unit|
        reference_id if assigned_sequence_unit_ids.include?(unit.dig("sequence_unit", "sequence_unit_id").to_s)
      end.compact
      allowed_ref_ids = (sequence_reference_ids + Array(source_section["scene_reference_unit_ids"])).map(&:to_s)
      Array(direction["reference_applications"]).each do |application|
        ref_id = application["reference_unit_id"].to_s
        unit = reference_units[ref_id]
        if unit.nil?
          errors << "#{section_id} reference application names unknown unit #{ref_id}"
          next
        end
        errors << "#{section_id} applies an unassigned reference #{ref_id}" unless allowed_ref_ids.include?(ref_id)
        errors << "#{section_id} reference source path differs" unless application["source_path"].to_s == unit["source_path"].to_s
        errors << "#{section_id} reference source SHA-256 differs" unless application["source_sha256"].to_s == unit["source_sha256"].to_s
        errors << "#{section_id} reference direct-use mode differs" unless application["direct_use_mode"].to_s == unit["direct_use_mode"].to_s
        reachability = reference_unit_reachability.find { |row| row["reference_unit_id"] == ref_id }
        if reachability.nil?
          errors << "#{section_id} reference application cannot compute an exact Front Planning unit pointer/hash for #{ref_id}"
        else
          resolved_unit = front_reference_units.fetch(reachability.fetch("source_json_pointer").split("/").last.to_i)
          unless reachability["source_value_sha256"] == value_sha256(resolved_unit) && resolved_unit["reference_unit_id"].to_s == ref_id
            errors << "#{section_id} reference application Front Planning unit pointer/hash is stale for #{ref_id}"
          end
        end
        if pinterest_unit?(unit)
          unless %w[main_reference supporting_visual_reference].include?(unit["source_kind"].to_s)
            errors << "#{section_id} Pinterest unit #{ref_id} must be classified as main_reference or supporting_visual_reference"
          end
          errors << "#{section_id} Pinterest application #{ref_id} source_kind differs from Front Planning" unless application["source_kind"].to_s == unit["source_kind"].to_s
          errors << "#{section_id} Pinterest application #{ref_id} role differs from Front Planning reason" unless application["role"].to_s == unit["reason"].to_s
        end
      end

      expansions = Array(direction["scene_expansions"])
      expansion_scene_ids = expansions.map { |row| row["scene_id"].to_s }
      errors << "#{section_id} scene expansions must exact-cover Front Planning Major Scenes" unless expansion_scene_ids == source_major_scene_ids
      expansions.each do |expansion|
        scene_id = expansion["scene_id"].to_s
        allowed_key_ids = key_screen_ids_by_scene.fetch(scene_id, [])
        expanded_key_ids = Array(expansion["source_key_screen_anchor_ids"]).map(&:to_s)
        unless expanded_key_ids == allowed_key_ids
          errors << "#{section_id} #{scene_id} must exact-copy its director-quality-passed Key Screen ids"
        end
        Array(expansion["branching_opportunities"]).each do |opportunity|
          opportunity_key_ids = Array(opportunity["source_key_screen_anchor_ids"]).map(&:to_s)
          unknown_opportunity_keys = opportunity_key_ids - allowed_key_ids
          errors << "#{section_id} #{opportunity['opportunity_id']} names unknown Key Screens: #{unknown_opportunity_keys.join(', ')}" unless unknown_opportunity_keys.empty?
        end
      end

      Array(direction["still_camera_coverage"]).each do |coverage|
        scene_id = coverage["scene_id"].to_s
        allowed_key_ids = key_screen_ids_by_scene.fetch(scene_id, [])
        coverage_key_ids = Array(coverage["source_key_screen_anchor_ids"]).map(&:to_s)
        unknown_coverage_keys = coverage_key_ids - allowed_key_ids
        errors << "#{section_id} #{coverage['coverage_id']} names unknown Key Screens: #{unknown_coverage_keys.join(', ')}" unless unknown_coverage_keys.empty?
      end

      policy = direction["choreography_presence_policy"].to_s
      errors << "#{section_id} choreography policy differs from Front Planning" unless policy == source_section["choreography_presence_policy"].to_s
      choreography = direction["choreography_reference_binding"]
      if %w[primary supporting].include?(policy)
        unless choreography.is_a?(Hash)
          errors << "#{section_id} requires an actual choreography reference"
          next
        end
        ref_id = choreography["reference_unit_id"].to_s
        unit = reference_units[ref_id]
        errors << "#{section_id} choreography reference was not assigned in Front Planning" unless Array(source_section["choreography_reference_unit_ids"]).map(&:to_s).include?(ref_id)
        if unit
          errors << "#{section_id} choreography source path differs" unless choreography["source_path"].to_s == unit["source_path"].to_s
          errors << "#{section_id} choreography source SHA-256 differs" unless choreography["source_sha256"].to_s == unit["source_sha256"].to_s
          unless %w[choreography_reference performance_video fancam].include?(unit["source_kind"].to_s)
            errors << "#{section_id} choreography unit is not an actual choreography/performance/fancam source"
          end
        end
      end
    end
  end

  song_ref = document["source_song_lock"].to_h
  song_path = resolve_path(song_ref["path"], root)
  if !inside?(song_path, root) || !song_path.file?
    errors << "source_song_lock is missing or outside the repository"
  elsif Digest::SHA256.file(song_path).hexdigest != song_ref["sha256"].to_s
    errors << "source_song_lock SHA-256 is stale"
  end

  if document["status"] == "passed"
    errors << "passed 01 requires every section passed" unless Array(document["section_directions"]).all? { |row| row["status"] == "passed" }
    errors << "passed 01 requires whole-film Official Core review PASS" unless document.dig("whole_film_core_review", "verdict").to_s == "pass"
    errors << "passed 01 requires every Official Core primary image pixel PASS" unless Array(document["official_core_cuts"]).all? { |row| row.dig("primary_image", "status").to_s == "pass" && row.dig("primary_image", "pixel_review", "verdict").to_s == "pass" }
  end
end

errors = errors.uniq
errors = errors.first(options[:max_errors]) if options[:max_errors].to_i.positive?
result = {
  "valid" => errors.empty?,
  "schema_version" => document["schema_version"],
  "front_planning_reference_unit_reachability" => reference_unit_reachability,
  "errors" => errors
}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: 01 v3.0 exact-projects FP v17 and owns every production-scope Official Core with one actual primary image, exact Core reference, Core Storyboard, and motion/Branch need handoff"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
