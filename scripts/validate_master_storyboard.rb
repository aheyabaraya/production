#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"
require_relative "lib/idol_storyboard_collected_angle_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "master-storyboard.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
FRONT_VALIDATOR = ROOT.join("scripts", "validate_front_planning_readiness.rb")
DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")
PLANNING_GRADE_VALIDATOR = ROOT.join("scripts", "validate_planning_contextual_grade_vector.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")
TEMPORAL_CAMERA_PATTERN = /\b(?:push[- ]?in|pull[- ]?out|pan(?:ning)?|tilt(?:ing)?|track(?:ing)?|orbit(?:ing)?|dolly|crane|zoom|camera speed|motion envelope)\b/i

options = {root: ROOT, json: false, max_errors: 50}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_master_storyboard.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!

artifact_arg = ARGV.shift
abort "02A storyboard path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "document must be an object" unless value.is_a?(Hash)
  value
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

def pointer_value(document, pointer)
  pointer.to_s.split("/").drop(1).reduce(document) do |value, raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    value.is_a?(Array) ? value.fetch(Integer(token, 10)) : value.fetch(token)
  end
end

def load_bound_source(ref, label, root, errors, enforce_artifact_sha: true)
  path = resolve_path(ref.to_h["path"], root)
  unless inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository"
    return [nil, nil, nil, false]
  end
  actual = Digest::SHA256.file(path).hexdigest
  matches = ref.to_h["sha256"].to_s == actual
  errors << "#{label} SHA-256 is stale" if enforce_artifact_sha && !matches
  [path, load_mapping(path), actual, matches]
end

def run_validator(validator, path, root, label, errors)
  stdout, stderr, status = Open3.capture3(
    "ruby",
    validator.to_s,
    "--root",
    root.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  errors << "#{label} failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
unless inside?(artifact, root) && artifact.file?
  errors << "02A storyboard is missing or outside the repository"
end

document = {}
reference_unit_reachability = []
if errors.empty?
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => e
    errors << "cannot parse 02A storyboard: #{e.message}"
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
  errors << "only 02A master storyboard 3.0 is active" unless document["schema_version"].to_s == "3.0"
  errors.concat(Idol02AStoryboardContract.section_exact_cover_errors(document, require_shards: true))
  front_path, front, _front_sha, _front_artifact_match = load_bound_source(
    document["source_front_planning"],
    "source_front_planning",
    root,
    errors,
    enforce_artifact_sha: false
  )
  direction_path, direction, _direction_sha, direction_artifact_match = load_bound_source(
    document["source_01_direction"],
    "source_01_direction",
    root,
    errors,
    enforce_artifact_sha: false
  )
  run_validator(FRONT_VALIDATOR, front_path, root, "source Front Planning", errors) if front_path
  run_validator(DIRECTION_VALIDATOR, direction_path, root, "source 01 direction", errors) if direction_path

  if front && direction
    selected_motion_by_major = {}
    Array(front["major_scene_catalog"]).each_with_index do |major, major_index|
      candidate_set = major["sequence_composition_candidate_set"].to_h
      selected_id = candidate_set["selected_sequence_composition_id"].to_s
      selected_index = Array(candidate_set["candidates"]).index { |row| row["sequence_composition_id"].to_s == selected_id }
      next if selected_index.nil?

      binding = Array(candidate_set["candidates"])[selected_index].to_h["sequence_motion_analysis_binding"].to_h
      next if binding.empty?

      analysis_path = resolve_path(binding["path"], root)
      if !inside?(analysis_path, root) || !analysis_path.file?
        errors << "#{major['major_scene_id']} selected Sequence Motion Analysis is missing for 02A carry"
        next
      end
      errors << "#{major['major_scene_id']} selected Sequence Motion Analysis SHA-256 is stale for 02A carry" unless Digest::SHA256.file(analysis_path).hexdigest == binding["sha256"].to_s
      begin
        analysis = load_mapping(analysis_path)
        analysis_row = pointer_value(analysis, binding["json_pointer"])
        errors << "#{major['major_scene_id']} selected Sequence Motion Analysis row hash is stale for 02A carry" unless binding["value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(analysis_row)
        selected_motion_by_major[major["major_scene_id"].to_s] = {
          "analysis_id" => analysis["analysis_id"].to_s,
          "section_id" => major["section_id"].to_s,
          "findings" => analysis_row.to_h["motion_support_finding"].to_h
        }
      rescue JSON::ParserError, Psych::Exception, TypeError, KeyError, IndexError, ArgumentError
        errors << "#{major['major_scene_id']} selected Sequence Motion Analysis row cannot be resolved for 02A carry"
      end
    end
    motion_adoptions_by_major = selected_motion_by_major.each_with_object({}) do |(major_id, motion), rows|
      section_direction = Array(direction["section_directions"]).find { |row| row["section_id"].to_s == motion["section_id"] }
      adoption = Array(section_direction.to_h["sequence_motion_adoptions"]).find do |row|
        row["major_scene_id"].to_s == major_id && row["analysis_id"].to_s == motion["analysis_id"]
      end
      if adoption
        next if adoption["overall_disposition"].to_s == "reject"

        rows[major_id] = {
          "overall_disposition" => adoption["overall_disposition"].to_s,
          "dispositions" => adoption["dimension_dispositions"].to_h,
          "applied_core_ids" => Array(adoption["applied_official_core_cut_ids"]).map(&:to_s),
          "applied_camera_ids" => Array(adoption["applied_still_camera_coverage_ids"]).map(&:to_s),
          "applied_branch_opportunity_ids" => Array(adoption["applied_branching_opportunity_ids"]).map(&:to_s)
        }
      else
        errors << "#{major_id} 02A cannot expand Sequence Motion findings without the exact typed 01 adoption decision"
      end
    end

    front_reference_units = Array(front.dig("reference_connection_research", "reference_units"))
    reference_unit_reachability = front_reference_units.each_with_index.map do |row, row_index|
      {
        "reference_unit_id" => row["reference_unit_id"].to_s,
        "source_json_pointer" => "/reference_connection_research/reference_units/#{row_index}",
        "source_value_sha256" => Idol02AStoryboardContract.value_sha256(row)
      }
    end
    errors << "02A content_id differs from Front Planning" unless document["content_id"].to_s == front["content_id"].to_s
    errors << "02A content_id differs from 01" unless document["content_id"].to_s == direction["content_id"].to_s
    errors << "02A requires Director-closed Front Planning and passed 01" unless front["status"] == "director_closed" && direction["status"] == "passed"
    errors << "01 and 02A must resolve the same Front Planning owner path" unless resolve_path(direction.dig("source_front_planning", "path"), root) == front_path
    errors << "02A derivative_route_id must exact-copy 01" unless document["derivative_route_id"].to_s == direction["derivative_route_id"].to_s
    errors << "02A production_scope_id must exact-copy 01" unless document["production_scope_id"].to_s == direction["production_scope_id"].to_s

    imported_head = document["imported_core_storyboard_head"].to_h
    source_cores = Array(direction["official_core_cuts"])
    errors << "imported Core Storyboard must bind the exact 01 path/SHA" unless imported_head["source_01_path"].to_s == document.dig("source_01_direction", "path").to_s && imported_head["source_01_sha256"].to_s == document.dig("source_01_direction", "sha256").to_s
    errors << "imported Core Storyboard pointer must remain /official_core_cuts" unless imported_head["source_json_pointer"].to_s == "/official_core_cuts"
    errors << "imported Core Storyboard hash is stale" unless imported_head["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_cores)
    unless Idol02AStoryboardContract.canonical_value(imported_head["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_cores)
      errors << "02A imported Core Storyboard must exact-copy all 01 Official Core bytes"
    end

    storyboard_cores = Array(document["master_storyboard"])
    errors << "02A Core parent roster must exact-cover 01 Official Cores in order" unless storyboard_cores.map { |row| row["core_cut_id"].to_s } == source_cores.map { |row| row["core_cut_id"].to_s }
    branch_ids = []
    storyboard_cores.each_with_index do |core, core_index|
      source_core = source_cores[core_index]
      next unless source_core

      core_id = core["core_cut_id"].to_s
      source_ref = core["source_01_core"].to_h
      errors << "#{core_id} source 01 Core pointer differs" unless source_ref["source_json_pointer"].to_s == "/official_core_cuts/#{core_index}"
      errors << "#{core_id} source 01 Core hash is stale" unless source_ref["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_core)
      unless Idol02AStoryboardContract.canonical_value(core["imported_core"]) == Idol02AStoryboardContract.canonical_value(source_core)
        errors << "#{core_id} imported Core bytes differ from 01"
      end
      errors << "#{core_id} Core authorship must remain 01_imported_immutable" unless core["authorship_owner"].to_s == "01_imported_immutable" && core["core_mutation_performed"] == false
      branches = Array(core.dig("compile_seed", "branch_cuts"))
      errors << "#{core_id} passed Official Core requires 1..N Branch Cuts" if branches.empty?
      branches.each_with_index do |branch, branch_index|
        branch_id = branch["branch_cut_id"].to_s
        branch_ids << branch_id
        errors << "#{branch_id} parent_core_cut_id differs" unless branch["parent_core_cut_id"].to_s == core_id
        errors << "#{branch_id} order_within_core must be contiguous from 1" unless branch["order_within_core"] == branch_index + 1 && branch["branch_sequence"] == branch_index + 1
        errors << "#{branch_id} section differs from imported Core" unless branch["section_id"].to_s == source_core["section_id"].to_s
        errors << "#{branch_id} parent Major differs from imported Core" unless branch["parent_major_scene_id"].to_s == source_core["parent_major_scene_id"].to_s
        errors << "#{branch_id} active storyline differs from imported Core" unless branch["active_storyline_version_id"].to_s == source_core["active_storyline_version_id"].to_s
        errors << "#{branch_id} screen progression node differs from imported Core" unless branch["screen_progression_node_id"].to_s == source_core["screen_progression_node_id"].to_s
        errors << "#{branch_id} must contain exactly one primary still job" unless branch["primary_still_job_count"] == 1 && branch.dig("expected_output", "count") == 1
      end
    end
    errors << "02A official_branch_cuts must exact-list every nested Branch once" unless Array(document["official_branch_cuts"]).map(&:to_s) == branch_ids
    errors << "reference_coverage_matrix must exact-cover every Branch" unless Array(document["reference_coverage_matrix"]).map { |row| row["branch_cut_id"].to_s }.sort == branch_ids.sort
    errors << "camera_diversity_review must exact-cover every Branch" unless Array(document.dig("camera_diversity_review", "reviewed_branch_cut_ids")).map(&:to_s).sort == branch_ids.sort
    core_ids = source_cores.map { |row| row["core_cut_id"].to_s }
    reviewed_core_ids = Array(document.dig("camera_diversity_review", "reviewed_core_cut_ids")).map(&:to_s)
    errors << "camera_diversity_review must exact-cover every Official Core" unless reviewed_core_ids.sort == core_ids.sort
    expected_images = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    errors.concat(
      IdolStoryboardCollectedAngleContract.validate_review(
        review: document.dig("camera_diversity_review", "collected_image_camera_angle_review"),
        expected_images: expected_images,
        document: document,
        root: root,
        parent_verdict: document.dig("camera_diversity_review", "verdict"),
        label: "camera_diversity_review"
      )
    )
    errors << "branch_generation_manifest must exact-cover every Branch" unless Array(document.dig("branch_generation_manifest", "planned_branch_cut_ids")).map(&:to_s) == branch_ids
    errors << "branch_generation_manifest production scope differs" unless document.dig("branch_generation_manifest", "production_scope_id").to_s == document["production_scope_id"].to_s
    g40 = document["g40_core_branch_authorization"].to_h
    errors << "G-40 derivative/scope differs from 02A" unless g40["derivative_route_id"].to_s == document["derivative_route_id"].to_s && g40["production_scope_id"].to_s == document["production_scope_id"].to_s
    errors << "G-40 reviewed Core roster differs" unless Array(g40["reviewed_core_cut_ids"]).map(&:to_s) == source_cores.map { |row| row["core_cut_id"].to_s }
    errors << "G-40 reviewed Branch roster differs" unless Array(g40["reviewed_branch_cut_ids"]).map(&:to_s) == branch_ids
    grade_ref = g40["draft_keyframe_grade_vector"].to_h
    grade_path, grade, _grade_sha, grade_hash_matches = load_bound_source(
      grade_ref,
      "G-40 Draft Keyframe contextual grade vector",
      root,
      errors
    )
    if grade_path && grade.is_a?(Hash) && grade_hash_matches
      errors << "G-40 grade binding stage must be draft_keyframe_proof" unless grade_ref["stage"].to_s == "draft_keyframe_proof"
      errors << "G-40 grade artifact must be planning_contextual_grade_vector" unless grade["artifact_type"].to_s == "planning_contextual_grade_vector"
      errors << "G-40 grade document stage must be draft_keyframe_proof" unless grade["stage"].to_s == "draft_keyframe_proof"
      errors << "G-40 grade scope differs from production scope" unless grade["scope_id"].to_s == document["production_scope_id"].to_s
      run_validator(PLANNING_GRADE_VALIDATOR, grade_path, root, "G-40 Draft Keyframe contextual grade vector", errors)
      if g40["decision"].to_s == "pass"
        errors << "G-40 PASS requires an eligible Draft Keyframe contextual grade vector" unless grade["decision"].to_s == "eligible_for_director_review"
        errors << "G-40 PASS requires reviewed Draft Keyframe contextual grades" unless grade["status"].to_s == "reviewed"
      end
    end

    source_storyline_projection = direction["storyline_lineage_projection"].to_h
    source_storyline_value = source_storyline_projection["projected_value"]
    storyline_projection = document["storyline_lineage_projection"].to_h
    errors << "02A storyline lineage source 01 pointer differs" unless storyline_projection["source_01_json_pointer"].to_s == "/storyline_lineage_projection/projected_value"
    errors << "02A storyline lineage Front Planning pointer differs" unless storyline_projection["source_front_planning_json_pointer"].to_s == "/storyline_lineage"
    errors << "02A storyline lineage hash is stale" unless storyline_projection["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_storyline_value)
    unless Idol02AStoryboardContract.canonical_value(storyline_projection["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_storyline_value)
      errors << "02A must exact-project the complete PRE-00-rooted full-storyline lineage from 01"
    end
    unless Idol02AStoryboardContract.canonical_value(source_storyline_value) == Idol02AStoryboardContract.canonical_value(front["storyline_lineage"])
      errors << "01 storyline lineage projection differs from Front Planning"
    end

    source_audience_target_projection = direction["pre00_audience_target_lineage_projection"].to_h
    source_audience_target_value = source_audience_target_projection["projected_value"]
    audience_target_projection = document["pre00_audience_target_lineage_projection"].to_h
    errors << "02A PRE-00 audience/target source 01 pointer differs" unless audience_target_projection["source_01_json_pointer"].to_s == "/pre00_audience_target_lineage_projection/projected_value"
    errors << "02A PRE-00 audience/target Front Planning pointer differs" unless audience_target_projection["source_front_planning_json_pointer"].to_s == "/pre00_audience_target_lineage"
    errors << "02A PRE-00 audience/target hash is stale" unless audience_target_projection["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_audience_target_value)
    unless Idol02AStoryboardContract.canonical_value(audience_target_projection["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_audience_target_value)
      errors << "02A must exact-copy 01 PRE-00 audience profiles, X envelope, and title target intersection"
    end
    unless Idol02AStoryboardContract.canonical_value(source_audience_target_value) == Idol02AStoryboardContract.canonical_value(front["pre00_audience_target_lineage"])
      errors << "01 PRE-00 audience/target projection differs from Front Planning"
    end

    target = front["target_message_lock"].to_h
    expected_target = {
      "primary_target" => target["primary_target"],
      "audience_promise" => target["audience_promise"],
      "core_message" => target["core_message"],
      "desired_response" => target["desired_response"],
      "do_not_serve" => target["do_not_serve"]
    }
    errors << "02A target_message_summary differs from Front Planning" unless document["target_message_summary"] == expected_target
    spine = front["whole_film_spine"].to_h
    expected_spine = {
      "opening_state" => spine["opening_state"],
      "progression" => spine["progression"],
      "turn" => spine["turn"],
      "resolution_or_afterimage" => spine["resolution_or_afterimage"],
      "recurrence_rule" => spine["recurrence_rule"]
    }
    errors << "02A whole_film_spine differs from Front Planning" unless document["whole_film_spine"] == expected_spine

    source_alignment_projection = direction["founder_visual_alignment_projection"].to_h
    source_alignment_value = source_alignment_projection["projected_value"]
    alignment_projection = document["founder_visual_alignment_projection"].to_h
    errors << "02A Founder visual alignment source 01 pointer differs" unless alignment_projection["source_01_json_pointer"].to_s == "/founder_visual_alignment_projection/projected_value"
    errors << "02A Founder visual alignment Front Planning pointer differs" unless alignment_projection["source_front_planning_json_pointer"].to_s == source_alignment_projection["source_json_pointer"].to_s
    errors << "02A Founder visual alignment hash is stale" unless alignment_projection["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_alignment_value)
    unless Idol02AStoryboardContract.canonical_value(alignment_projection["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_alignment_value)
      errors << "02A Founder visual alignment value differs from 01"
    end

    source_screen_projection = direction["screen_progression_map_projection"].to_h
    source_screen_value = source_screen_projection["projected_value"]
    screen_projection = document["screen_progression_map_projection"].to_h
    errors << "02A screen progression source 01 pointer differs" unless screen_projection["source_01_json_pointer"].to_s == "/screen_progression_map_projection/projected_value"
    errors << "02A screen progression Front Planning pointer differs" unless screen_projection["source_front_planning_json_pointer"].to_s == source_screen_projection["source_json_pointer"].to_s
    errors << "02A screen progression hash is stale" unless screen_projection["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_screen_value)
    unless Idol02AStoryboardContract.canonical_value(screen_projection["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_screen_value)
      errors << "02A screen progression map differs from 01"
    end

    visual = front["current_title_visual_identity"].to_h
    album_key = visual["album_key"].to_s
    title_key = visual["title_key"].to_s
    assets = Array(visual["assets"]).to_h { |row| [row["asset_id"].to_s, row] }
    direction_by_section = Array(direction["section_directions"]).to_h { |row| [row["section_id"].to_s, row] }
    applications_by_section = {}
    background_assets_by_section = {}
    shard_by_section = Array(document["section_shards"]).to_h { |row| [Array(row["section_ids"]).first.to_s, row] }
    direction_sections = Array(direction["section_directions"])
    storyboard_section_ids = Array(document["section_shards"]).map { |row| Array(row["section_ids"]).first.to_s }
    direction_section_ids = direction_sections.map { |row| row["section_id"].to_s }
    alignment_cut_ids_by_section = {}
    used_alignment_cut_ids_by_section = Hash.new { |hash, key| hash[key] = [] }
    errors << "02A section shards must exact-cover current 01 sections in order" unless storyboard_section_ids == direction_section_ids

    Array(document["section_shards"]).each_with_index do |shard, section_index|
      section_id = Array(shard["section_ids"]).first.to_s
      section_direction = direction_by_section[section_id]
      if section_direction.nil?
        errors << "#{section_id} has no passed 01 direction"
        next
      end
      source_01_section = shard["source_01_section"]
      if source_01_section.is_a?(Hash)
        errors << "#{section_id} source 01 section id differs" unless source_01_section["section_id"].to_s == section_id
        errors << "#{section_id} source 01 pointer differs" unless source_01_section["json_pointer"].to_s == "/section_directions/#{section_index}"
        unless source_01_section["value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(section_direction)
          errors << "#{section_id} source 01 section hash is stale"
        end
      elsif !direction_artifact_match
        errors << "#{section_id} source_01_section is required when the 01 whole-artifact baseline changed"
      end
      errors << "#{section_id} requires a passed current 01 section" unless section_direction["status"].to_s == "passed"
      source_section_alignment = section_direction["section_alignment_projection"].to_h
      section_alignment = shard["section_alignment_projection"].to_h
      expected_section_01_pointer = "/section_directions/#{section_index}/section_alignment_projection/projected_value"
      errors << "#{section_id} storyline section source 01 pointer differs" unless section_alignment["source_01_json_pointer"].to_s == expected_section_01_pointer
      errors << "#{section_id} storyline section Front Planning pointer differs" unless section_alignment["source_front_planning_json_pointer"].to_s == source_section_alignment["source_json_pointer"].to_s
      errors << "#{section_id} storyline section id differs" unless section_alignment["section_id"].to_s == section_id
      errors << "#{section_id} storyline section hash is stale" unless section_alignment["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_section_alignment["projected_value"])
      unless Idol02AStoryboardContract.canonical_value(section_alignment["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_section_alignment["projected_value"])
        errors << "#{section_id} storyline section value differs from 01"
      end

      source_cut_alignments = Array(section_direction["planning_cut_alignment_projections"])
      cut_alignments = Array(shard["planning_cut_alignment_projections"])
      source_cut_ids = source_cut_alignments.map { |row| row["planning_cut_id"].to_s }
      alignment_cut_ids_by_section[section_id] = source_cut_ids
      unless cut_alignments.map { |row| row["planning_cut_id"].to_s } == source_cut_ids
        errors << "#{section_id} storyline planning-cut projections must exact-cover 01 in order"
      end
      source_cut_alignments.each_with_index do |source_cut_alignment, cut_index|
        cut_alignment = cut_alignments[cut_index].to_h
        planning_cut_id = source_cut_alignment["planning_cut_id"].to_s
        expected_cut_01_pointer = "/section_directions/#{section_index}/planning_cut_alignment_projections/#{cut_index}/projected_value"
        errors << "#{section_id} #{planning_cut_id} storyline source 01 pointer differs" unless cut_alignment["source_01_json_pointer"].to_s == expected_cut_01_pointer
        errors << "#{section_id} #{planning_cut_id} storyline Front Planning pointer differs" unless cut_alignment["source_front_planning_json_pointer"].to_s == source_cut_alignment["source_json_pointer"].to_s
        errors << "#{section_id} #{planning_cut_id} storyline Key Screen differs" unless cut_alignment["source_key_screen_id"].to_s == source_cut_alignment["source_key_screen_id"].to_s
        errors << "#{section_id} #{planning_cut_id} storyline hash is stale" unless cut_alignment["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_cut_alignment["projected_value"])
        unless Idol02AStoryboardContract.canonical_value(cut_alignment["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_cut_alignment["projected_value"])
          errors << "#{section_id} #{planning_cut_id} storyline value differs from 01"
        end
      end
      projection = section_direction["source_front_planning_section"].to_h
      errors << "#{section_id} assigned members differ from 01" unless shard["assigned_member_ids"] == projection["assigned_member_ids"]
      allowed_member_assets = Array(section_direction.dig("visual_projection", "member_visual_asset_ids")).map(&:to_s)
      allowed_scene_assets = Array(section_direction.dig("visual_projection", "background_world_asset_ids")).map(&:to_s)
      background_assets_by_section[section_id] = allowed_scene_assets
      unless (Array(shard["authorized_member_visual_asset_ids"]).map(&:to_s) - allowed_member_assets).empty?
        errors << "#{section_id} authorizes member visuals outside the 01 pool"
      end
      applications = Array(section_direction["reference_applications"])
      application_ids = applications.map { |row| row["application_id"].to_s }
      application_id_counts = application_ids.each_with_object(Hash.new(0)) { |id, counts| counts[id] += 1 }
      duplicate_application_ids = application_id_counts.select { |id, count| id.empty? || count > 1 }.keys
      unless duplicate_application_ids.empty?
        errors << "#{section_id} has duplicate or blank 01 reference application ids: #{duplicate_application_ids.join(', ')}"
      end
      applications_by_section[section_id] = applications.to_h { |row| [row["application_id"].to_s, row] }
      unless (Array(shard["authorized_scene_reference_binding_ids"]).map(&:to_s) - application_ids).empty?
        errors << "#{section_id} authorizes scene bindings outside 01 reference applications"
      end
      unless Array(shard["authorized_member_visual_asset_ids"]).all? { |id| assets.key?(id.to_s) }
        errors << "#{section_id} authorizes unknown current-title member assets"
      end
      unless allowed_scene_assets.all? { |id| assets.key?(id.to_s) }
        errors << "#{section_id} 01 background/world projection names unknown current-title assets"
      end
    end

    Array(document["master_storyboard"]).each_with_index do |core_cut, core_cut_index|
      core_cut_id = core_cut["core_cut_id"].to_s
      section_id = core_cut.dig("imported_core", "section_id").to_s
      shard = shard_by_section[section_id]
      allowed_scene_assets = background_assets_by_section.fetch(section_id, [])
      errors << "#{core_cut_id} has no owning section shard" unless shard
      section_direction = direction_by_section[section_id]

      branch_cuts = Array(core_cut.dig("compile_seed", "branch_cuts"))
      branch_cut_ids = branch_cuts.map { |branch_cut| branch_cut["branch_cut_id"].to_s }
      authorized_scene_ids = Array(shard.to_h["authorized_scene_reference_binding_ids"]).map(&:to_s)
      used_scene_binding_ids = branch_cuts.flat_map do |branch_cut|
        Array(branch_cut["visual_reference_bindings"])
          .select do |binding|
            binding["reference_scope"].to_s == "scene_visual" &&
              binding["reference_class"].to_s != "current_title_world_or_background"
          end
          .map { |binding| binding["binding_id"].to_s }
      end.uniq
      unless (used_scene_binding_ids - authorized_scene_ids).empty?
        errors << "#{core_cut_id} Branch scene bindings exceed the section's 01-authorized pool"
      end
      sequences = branch_cuts.map { |branch_cut| branch_cut["branch_sequence"] }
      unless sequences == (1..branch_cuts.length).to_a
        errors << "#{core_cut_id} Branch-Cut sequence must be contiguous from 1"
      end
      branch_cuts.each_with_index do |branch_cut, branch_index|
        label = "#{core_cut_id}.compile_seed.branch_cuts[#{branch_index}]"
        errors.concat(Idol02AStoryboardContract.branch_cut_lock_errors(label, branch_cut))
        storyline_binding = branch_cut["storyline_alignment_binding"].to_h
        planning_cut_id = storyline_binding["planning_cut_id"].to_s
        source_cut_index = Array(alignment_cut_ids_by_section[section_id]).index(planning_cut_id)
        if source_cut_index.nil?
          errors << "#{label} storyline planning cut is outside the section's 01 projection"
        else
          source_cut_alignment = Array(section_direction["planning_cut_alignment_projections"])[source_cut_index].to_h
          expected_pointer = "/section_directions/#{direction_section_ids.index(section_id)}/planning_cut_alignment_projections/#{source_cut_index}/projected_value"
          errors << "#{label} storyline source 01 pointer differs" unless storyline_binding["source_01_json_pointer"].to_s == expected_pointer
          errors << "#{label} storyline Front Planning pointer differs" unless storyline_binding["source_front_planning_json_pointer"].to_s == source_cut_alignment["source_json_pointer"].to_s
          errors << "#{label} storyline Key Screen differs" unless storyline_binding["source_key_screen_id"].to_s == source_cut_alignment["source_key_screen_id"].to_s
          errors << "#{label} storyline hash is stale" unless storyline_binding["source_value_sha256"].to_s == Idol02AStoryboardContract.value_sha256(source_cut_alignment["projected_value"])
          unless Idol02AStoryboardContract.canonical_value(storyline_binding["projected_value"]) == Idol02AStoryboardContract.canonical_value(source_cut_alignment["projected_value"])
            errors << "#{label} storyline value differs from 01"
          end
          used_alignment_cut_ids_by_section[section_id] << planning_cut_id unless used_alignment_cut_ids_by_section[section_id].include?(planning_cut_id)
        end
        visible_members = Array(branch_cut["visible_member_focus"]).map(&:to_s)
        allowed_members = Array(shard.to_h["assigned_member_ids"]).map(&:to_s)
        errors << "#{label} shows a member not assigned to the section" unless (visible_members - allowed_members).empty?
        input = branch_cut["member_visual_compile_input"].to_h
        errors << "#{label} current-title package keys differ from Front Planning" unless input["package_album_key"].to_s == album_key && input["package_title_key"].to_s == title_key
        selected_ids = Array(input["selected_album_member_visual_asset_ids"]).map(&:to_s)
        unless (selected_ids - Array(shard.to_h["authorized_member_visual_asset_ids"]).map(&:to_s)).empty?
          errors << "#{label} selects a member visual outside the section pool"
        end

        still_text = [
          branch_cut["camera_treatment"],
          *branch_cut["still_camera_spec"].to_h.values
        ].map(&:to_s).join(" ")
        errors << "#{label} authors temporal camera motion reserved for 03V" if still_text.match?(TEMPORAL_CAMERA_PATTERN)
        Array(branch_cut["visual_reference_bindings"]).each do |binding|
          path = resolve_path(binding["actual_path"], root)
          if !inside?(path, root) || !path.file?
            errors << "#{label} visual binding is missing: #{binding['actual_path']}"
            next
          end
          errors << "#{label} visual binding SHA-256 is stale" unless Digest::SHA256.file(path).hexdigest == binding["sha256"].to_s
          errors << "#{label} uses a prohibited face-only binding" if binding["actual_path"].to_s.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
          if binding["reference_scope"] == "member_visual"
            asset = assets[binding["asset_id"].to_s]
            errors << "#{label} member visual is not a Front Planning asset" unless asset
            errors << "#{label} member visual path differs from Front Planning" if asset && binding["actual_path"].to_s != asset["path"].to_s
          elsif binding["reference_class"].to_s == "current_title_world_or_background"
            asset_id = binding["asset_id"].to_s
            asset = assets[asset_id]
            errors << "#{label} current-title world/background is not a Front Planning asset" unless asset
            unless allowed_scene_assets.include?(asset_id)
              errors << "#{label} current-title world/background is outside the section's 01 visual projection"
            end
            if asset
              errors << "#{label} current-title world/background path differs from Front Planning" unless binding["actual_path"].to_s == asset["path"].to_s
              errors << "#{label} current-title world/background SHA-256 differs from Front Planning" unless binding["sha256"].to_s == asset["sha256"].to_s
            end
            unless binding["source_owner"].to_s == "front_planning_album_visual_asset"
              errors << "#{label} current-title world/background owner must remain Front Planning"
            end
          else
            binding_id = binding["binding_id"].to_s
            unless authorized_scene_ids.include?(binding_id)
              errors << "#{label} scene reference binding is outside the section's 01-authorized pool"
              next
            end
            application = applications_by_section.fetch(section_id, {})[binding_id]
            unless application
              errors << "#{label} scene reference binding does not resolve to its 01 reference application"
              next
            end
            unless binding["actual_path"].to_s == application["source_path"].to_s
              errors << "#{label} scene reference path differs from its 01 reference application"
            end
            unless binding["sha256"].to_s == application["source_sha256"].to_s
              errors << "#{label} scene reference SHA-256 differs from its 01 reference application"
            end
            unless binding["asset_id"].to_s == application["reference_unit_id"].to_s
              errors << "#{label} scene reference unit differs from its 01 reference application"
            end
            reachability = reference_unit_reachability.find do |row|
              row["reference_unit_id"] == application["reference_unit_id"].to_s
            end
            if reachability.nil?
              errors << "#{label} cannot compute an exact Front Planning unit pointer/hash through its 01 reference application"
            else
              resolved_unit = front_reference_units.fetch(reachability.fetch("source_json_pointer").split("/").last.to_i)
              unless reachability["source_value_sha256"] == Idol02AStoryboardContract.value_sha256(resolved_unit) &&
                     resolved_unit["reference_unit_id"].to_s == application["reference_unit_id"].to_s
                errors << "#{label} Front Planning reference unit pointer/hash is stale through 01"
              end
            end
            unless application["source_kind"].to_s.empty?
              unless binding["source_kind"].to_s == application["source_kind"].to_s
                errors << "#{label} scene reference source_kind differs from its 01 reference application"
              end
              unless binding["role"].to_s == application["role"].to_s
                errors << "#{label} scene reference role differs from its 01 reference application"
              end
            end
          end
        end
      end
    end

    motion_adoptions_by_major.each do |major_id, adoption|
      dispositions = adoption["dispositions"].to_h
      applied_core_ids = adoption["applied_core_ids"]
      branches = Array(document["master_storyboard"]).select do |core|
        core.dig("imported_core", "parent_major_scene_id").to_s == major_id && applied_core_ids.include?(core["core_cut_id"].to_s)
      end.flat_map { |core| Array(core.dig("compile_seed", "branch_cuts")) }
      if branches.empty?
        errors << "#{major_id} adopted Sequence Motion findings require actual 02A Branch authoring"
        next
      end
      if %w[adopt partial].include?(dispositions["depth"])
        errors << "#{major_id} 02A Sequence Motion depth carry requires authored Branch depth truth" unless branches.all? { |branch| !branch.dig("still_camera_spec", "depth_design").to_s.empty? }
      end
      if %w[adopt partial].include?(dispositions["crop"])
        errors << "#{major_id} 02A Sequence Motion crop carry requires authored Branch crop/negative-space truth" unless branches.all? { |branch| !branch.dig("still_camera_spec", "crop_negative_space").to_s.empty? }
      end
      if %w[adopt partial].include?(dispositions["alternate_view"])
        views = branches.map do |branch|
          camera = branch["still_camera_spec"].to_h
          [camera["shot_scale_distance"], camera["camera_height"], camera["direction_angle"]]
        end.uniq
        errors << "#{major_id} 02A Sequence Motion alternate-view carry requires at least two independently authored Branch views" unless views.length >= 2
      end
      if %w[adopt partial].include?(dispositions["reveal_space"])
        errors << "#{major_id} 02A Sequence Motion reveal carry requires an observable Branch reveal job" unless branches.any? { |branch| Array(branch["required_visibility"]).length >= 2 && !branch["distinct_screen_contribution"].to_s.empty? }
      end
      if %w[adopt partial].include?(dispositions["rear_world_direction"])
        errors << "#{major_id} 02A Sequence Motion rear/world-direction carry requires authored Branch direction geometry" unless branches.all? { |branch| !branch.dig("still_camera_spec", "direction_angle").to_s.empty? }
      end
      visible_branches = branches.select { |branch| Array(branch["visible_member_focus"]).any? }
      unless visible_branches.all? do |branch|
        input = branch["member_visual_compile_input"].to_h
        input["member_visual_reference_policy"].to_s == "required" &&
          Array(input["selected_album_member_visual_asset_ids"]).any? &&
          !input["head_orientation"].to_s.empty? && !input["occlusion"].to_s.empty?
      end
        errors << "#{major_id} 02A Sequence Motion identity/occlusion risk carry requires current-title identity and occlusion truth on every visible Branch"
      end
      if %w[adopt partial].include?(dispositions["continuity"])
        errors << "#{major_id} 02A Sequence Motion continuity carry requires authored Branch continuity-in/out" unless branches.all? { |branch| !branch["continuity_in"].to_s.empty? && !branch["continuity_out"].to_s.empty? }
      end
      if %w[adopt partial].include?(dispositions["start_landing"])
        errors << "#{major_id} 02A Sequence Motion start/landing carry requires authored still-state timing and continuity" unless branches.all? { |branch| !branch["branch_time_relation"].to_s.empty? && !branch["continuity_in"].to_s.empty? && !branch["continuity_out"].to_s.empty? }
      end
    end

    direction_section_ids.each do |section_id|
      unless used_alignment_cut_ids_by_section[section_id] == Array(alignment_cut_ids_by_section[section_id])
        errors << "#{section_id} Branch Cuts must exact-cover every Founder-aligned planning cut in first-use order"
      end
    end
  end

  if document["status"] == "passed"
    errors << "passed 02A requires every section shard passed" unless Array(document["section_shards"]).all? { |row| row["status"] == "passed" }
    founder_gate = document["founder_planning_gate"].to_h
    errors << "passed 02A requires Founder 02A Final Planning PASS" unless founder_gate["decision"].to_s == "pass"
    errors << "passed 02A requires whole-video Founder review scope" unless founder_gate["reviewed_scope"].to_s == "whole_video"
    reviewed_section_ids = Array(founder_gate["reviewed_section_ids"]).map(&:to_s)
    expected_section_ids = Array(document["section_shards"]).flat_map { |row| Array(row["section_ids"]).map(&:to_s) }
    errors << "Founder 02A Final Planning review must exact-cover every section" unless reviewed_section_ids == expected_section_ids
    errors << "passed 02A requires camera diversity PASS" unless document.dig("camera_diversity_review", "verdict").to_s == "pass"
    errors << "passed 02A requires G-40 PASS" unless document.dig("g40_core_branch_authorization", "decision").to_s == "pass"
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
  puts "OK: 02A v3.0 exact-imports immutable one-image 01 Official Cores and authors only 1..N production-scope Branch Cuts with exact reference, camera, manifest, and G-40 coverage"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
