#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "set"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "front-planning-readiness.schema.json")
REFERENCE_INDEX_SCHEMA = ROOT.join("schemas", "reference-working-index.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")
FOUNDER_SEQUENCE_VALIDATOR = ROOT.join("scripts", "validate_founder_sequence_control.rb")
SEQUENCE_MOTION_ANALYSIS_VALIDATOR = ROOT.join("scripts", "validate_sequence_motion_analysis.rb")
DEPARTMENT_DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb")
require_relative "lib/idol_front_planning_sequence_core_hold"
require_relative "lib/idol_front_planning_local_pairwise_global"
require_relative "lib/idol_storyline_density_locator_contract"
require_relative "lib/idol_kinetic_slot_sheet_contract"
VIDEO_ANALYSIS_REGISTRY = Pathname.new("source-materials/video-sources/reference-analysis-registry.yaml")
VIDEO_READ_FIRST = Pathname.new("source-materials/video-sources/READ-FIRST.md")
VIDEO_SOURCE_KINDS = %w[performance_video fancam].freeze
ACTIVE_FRONT_PLANNING_VERSION = "front-planning-readiness.v17"
SEQUENCE_UNIT_FRAME_COUNT = 5
SEQUENCE_UNIT_CADENCE = 1.0
SEQUENCE_CADENCE_TOLERANCE = 0.001

options = {root: ROOT, json: false, max_errors: 40, admission_graph: false}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_front_planning_readiness.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
  opts.on("--admission-graph") { options[:admission_graph] = true }
end.parse!

artifact_arg = ARGV.shift
abort "Front Planning path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

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
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonical_value(value[source_key])
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def pointer_value(document, pointer)
  current = document
  pointer.to_s.split("/")[1..].to_a.each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    current = if current.is_a?(Array) && token.match?(/\A(?:0|[1-9]\d*)\z/)
                current.fetch(token.to_i)
              elsif current.is_a?(Hash)
                current.fetch(token)
              else
                raise KeyError, "pointer traverses a scalar"
              end
  end
  current
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

def inside_real?(path, root)
  return false unless inside?(path, root) && path.exist?
  real_root = root.realpath
  relative = path.realpath.relative_path_from(real_root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
end

def pinterest_index_row?(row)
  row.to_h.dig("source_eligibility", "classification").to_s == "public_pinterest_pin"
end

def validate_file(path, sha, label, root, errors)
  unless inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository"
    return
  end
  errors << "#{label} SHA-256 is stale" unless Digest::SHA256.file(path).hexdigest == sha.to_s
end

def validate_sequence_unit(unit, root, errors)
  unit_id = unit["reference_unit_id"].to_s
  sequence = unit["sequence_unit"]
  sequence_required = unit["source_kind"].to_s == "sequence_sheet" ||
    unit["direct_use_mode"].to_s == "sequence_direct"
  if sequence_required && !sequence.is_a?(Hash)
    errors << "#{unit_id} sequence reference requires one active exact-five sequence_unit"
    return
  end
  return unless sequence.is_a?(Hash)

  sequence_id = sequence["sequence_unit_id"].to_s
  unless unit["selected_locator"].to_s.include?(sequence_id)
    errors << "#{unit_id} selected_locator must name active Sequence Unit #{sequence_id}"
  end

  manifest = sequence["manifest"].to_h
  validate_file(
    resolve_path(manifest["path"], root),
    manifest["sha256"],
    "#{unit_id} Sequence Unit manifest",
    root,
    errors
  )

  frames = Array(sequence["ordered_frames"])
  if frames.length != SEQUENCE_UNIT_FRAME_COUNT
    errors << "#{unit_id} Sequence Unit must contain exactly five ordered frames"
  end
  orders = frames.map { |frame| frame["order_index"].to_i }
  unless orders == (1..SEQUENCE_UNIT_FRAME_COUNT).to_a
    errors << "#{unit_id} Sequence Unit frame order must be exactly 1 through 5"
  end

  timestamps = frames.map { |frame| frame["timestamp_seconds"].to_f }
  frame_ids = frames.map { |frame| frame["source_frame_or_cell_id"].to_s }
  frame_paths = frames.map { |frame| frame.to_h.dig("artifact", "path").to_s }
  errors << "#{unit_id} Sequence Unit frame ids must be unique" unless frame_ids.uniq.length == frame_ids.length
  errors << "#{unit_id} Sequence Unit frame paths must be unique" unless frame_paths.uniq.length == frame_paths.length

  frames.each_with_index do |frame, frame_index|
    artifact = frame["artifact"].to_h
    validate_file(
      resolve_path(artifact["path"], root),
      artifact["sha256"],
      "#{unit_id} Sequence Unit frame #{frame_index + 1}",
      root,
      errors
    )
  end

  cadence = sequence["declared_cadence_seconds"].to_f
  unless (cadence - SEQUENCE_UNIT_CADENCE).abs <= SEQUENCE_CADENCE_TOLERANCE
    errors << "#{unit_id} active Sequence Unit cadence must be exactly one second"
  end
  timestamps.each_cons(2).with_index do |(current, following), pair_index|
    difference = following - current
    unless (difference - cadence).abs <= SEQUENCE_CADENCE_TOLERANCE
      errors << "#{unit_id} Sequence Unit frames #{pair_index + 1}-#{pair_index + 2} are not exact t+1 consecutive samples"
    end
  end
  observations = Array(sequence["frame_observations"])
  errors << "#{unit_id} Sequence Unit requires exactly five contextual frame observations" unless observations.length == SEQUENCE_UNIT_FRAME_COUNT
  observation_orders = observations.map { |row| row["order_index"].to_i }
  observation_times = observations.map { |row| row["timestamp_seconds"].to_f }
  errors << "#{unit_id} frame observations must map exactly 1 through 5" unless observation_orders == orders
  errors << "#{unit_id} frame observation timestamps must exact-copy ordered frames" unless observation_times == timestamps
  flow = sequence["flow_reading"].to_h
  errors << "#{unit_id} flow reading must be authored by a human or assigned model" unless %w[human assigned_model].include?(flow["authorship_owner"].to_s)
end

def validate_selected_route_storyline_binding(document, routes, selected_route, errors)
  experiment = document["creative_experiment"].to_h
  binding = experiment["selected_route_storyline_binding"].to_h
  selected_route_id = experiment["candidate_route_id"].to_s
  if binding.empty?
    errors << "creative_experiment requires a hash-bound selected route storyline binding"
    return
  end

  unless binding["candidate_route_id"].to_s == selected_route_id
    errors << "selected route storyline binding candidate_route_id differs from creative_experiment"
  end

  selected_index = routes.index(selected_route)
  expected_pointer = "/candidate_routes/#{selected_index}/complete_storyline_version"
  source_pointer = binding["candidate_route_storyline_json_pointer"].to_s
  unless source_pointer == expected_pointer
    errors << "selected route storyline binding must point to #{expected_pointer}"
  end

  selected_version = selected_route["complete_storyline_version"].to_h
  begin
    resolved_version = pointer_value(document, source_pointer)
    unless canonical_value(resolved_version) == canonical_value(selected_version)
      errors << "selected route storyline binding does not resolve to the selected route complete storyline"
    end
    unless binding["candidate_route_storyline_value_sha256"].to_s == value_sha256(resolved_version)
      errors << "selected route storyline binding source value hash is stale"
    end
  rescue KeyError, IndexError
    errors << "selected route storyline binding source pointer is stale"
  end

  active_storyline = document.dig("storyline_lineage", "active_version").to_h
  unless binding["active_storyline_version_id"].to_s == active_storyline["version_id"].to_s &&
         binding["active_storyline_full_storyline_text_sha256"].to_s == active_storyline["full_storyline_text_sha256"].to_s
    errors << "selected route storyline binding must exact-copy the active storyline id and full-text hash"
  end

  promotion_pointer = binding["promoted_storyline_revision_json_pointer"]
  promotion_value_sha = binding["promoted_storyline_revision_value_sha256"]
  case binding["active_storyline_relation"].to_s
  when "exact_selected_route_text"
    unless active_storyline["full_storyline_text_sha256"].to_s == selected_version["full_storyline_text_sha256"].to_s
      errors << "exact-selected route relation requires the active full storyline text to match the selected route"
    end
    unless promotion_pointer.nil? && promotion_value_sha.nil?
      errors << "exact-selected route relation must not invent a promoted storyline revision"
    end
  when "reviewed_full_text_descendant"
    if promotion_pointer.to_s.empty? || promotion_value_sha.to_s.empty?
      errors << "reviewed descendant relation requires one hash-bound promoted selected-route revision"
      return
    end

    begin
      promoted_revision = pointer_value(document, promotion_pointer)
      unless promotion_value_sha.to_s == value_sha256(promoted_revision)
        errors << "promoted selected-route storyline revision value hash is stale"
      end
      unless promoted_revision.to_h["full_storyline_text"].to_s == selected_version["full_storyline_text"].to_s &&
             promoted_revision.to_h["full_storyline_text_sha256"].to_s == selected_version["full_storyline_text_sha256"].to_s
        errors << "promoted storyline revision must exact-copy the selected route full text and hash"
      end
      unless promoted_revision.to_h["parent_version_id"].to_s == selected_version["parent_version_id"].to_s &&
             promoted_revision.to_h["parent_full_storyline_text_sha256"].to_s == selected_version["parent_full_storyline_text_sha256"].to_s
        errors << "promoted storyline revision must preserve the selected route parent id and full-text hash"
      end

      revisions = Array(document.dig("storyline_lineage", "front_planning_revisions"))
      promoted_index = revisions.index { |revision| revision.equal?(promoted_revision) || canonical_value(revision) == canonical_value(promoted_revision) }
      active_index = revisions.index { |revision| revision["version_id"].to_s == active_storyline["version_id"].to_s }
      unless active_storyline["lineage_scope"].to_s == "front_planning" && promoted_index && active_index && active_index >= promoted_index
        errors << "active storyline must be the promoted selected-route revision or its later reviewed full-text descendant"
      end
    rescue KeyError, IndexError
      errors << "promoted selected-route storyline revision pointer is stale"
    end
  end
end

def validate_sequence_motion_analysis_binding(binding, candidate, major, document, root, errors)
  label = "#{major['major_scene_id']} #{candidate['sequence_composition_id']} Sequence Motion Analysis"
  path = resolve_path(binding["path"], root)
  unless inside_real?(path, root) && path.file?
    errors << "#{label} is missing, outside the repository, or resolves through a symlink outside it"
    return
  end
  errors << "#{label} file SHA-256 is stale" unless Digest::SHA256.file(path).hexdigest == binding["sha256"].to_s

  analysis = begin
    load_mapping(path)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "#{label} cannot be read: #{error.message}"
    return
  end
  unless binding["schema_version"].to_s == "idol_sequence_motion_analysis.v1" && analysis["schema_version"].to_s == "idol_sequence_motion_analysis.v1"
    errors << "#{label} must bind idol_sequence_motion_analysis.v1"
  end
  errors << "#{label} must be worker-authored ready_for_cdd_review evidence" unless analysis["status"].to_s == "ready_for_cdd_review"
  errors << "#{label} content differs from Front Planning" unless analysis["content_id"].to_s == document["content_id"].to_s
  errors << "#{label} section differs from its Major" unless analysis["section_id"].to_s == major["section_id"].to_s
  errors << "#{label} Major differs" unless analysis["major_scene_id"].to_s == major["major_scene_id"].to_s

  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    SEQUENCE_MOTION_ANALYSIS_VALIDATOR.to_s,
    "--root",
    root.to_s,
    path.to_s,
    chdir: root.to_s
  )
  errors << "#{label} failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?

  review_binding = binding["independent_cdd_review_binding"].to_h
  review_path = resolve_path(review_binding["path"], root)
  unless inside_real?(review_path, root) && review_path.file?
    errors << "#{label} independent CDD review dispatch is missing or outside the repository"
  else
    review_sha = Digest::SHA256.file(review_path).hexdigest
    errors << "#{label} independent CDD review dispatch SHA-256 is stale" unless review_binding["sha256"].to_s == review_sha
    review_dispatch = load_mapping(review_path)
    errors << "#{label} independent review must use idol-department-dispatch.v8" unless review_binding["schema_version"].to_s == "idol-department-dispatch.v8" && review_dispatch["schema_version"].to_s == "idol-department-dispatch.v8"
    stdout, stderr, review_status = Open3.capture3(
      RbConfig.ruby,
      DEPARTMENT_DISPATCH_VALIDATOR.to_s,
      "--require-promoted",
      review_path.to_s,
      chdir: root.to_s
    )
    errors << "#{label} independent CDD review dispatch failed active validation: #{[stderr, stdout].join(' ').strip}" unless review_status.success?
    errors << "#{label} independent review must bind the analysis Department Dispatch" unless review_path == resolve_path(analysis.dig("dispatch_and_authorship", "dispatch_contract", "path"), root)
    errors << "#{label} independent review pointer must remain /director_review" unless review_binding["json_pointer"].to_s == "/director_review"
    review_value = pointer_value(review_dispatch, review_binding["json_pointer"])
    errors << "#{label} independent review value SHA-256 is stale" unless review_binding["value_sha256"].to_s == value_sha256(review_value)
    expected_analysis_ref = [binding["path"].to_s, binding["sha256"].to_s]
    reviewed_pairs = Array(review_dispatch.dig("director_review", "reviewed_outputs")).map { |row| [row["path"].to_s, row["sha256"].to_s] }
    returned_pairs = Array(review_dispatch.dig("runtime_return", "outputs")).map { |row| [row["path"].to_s, row["sha256"].to_s] }
    unless review_dispatch.dig("director_review", "director", "role").to_s == "creative_development_director" &&
           review_dispatch.dig("director_review", "disposition").to_s == "accept" &&
           review_dispatch.dig("promotion", "decision").to_s == "promoted" &&
           reviewed_pairs.include?(expected_analysis_ref) && returned_pairs.include?(expected_analysis_ref)
      errors << "#{label} requires independent CDD accept/promotion of the exact analysis path/SHA"
    end
    attempt_key = analysis.dig("dispatch_and_authorship", "attempt_key").to_s
    expected_dispatch_id = "sequence-motion-analysis-#{major['major_scene_id']}--#{attempt_key}"
    unless review_dispatch["dispatch_id"].to_s == expected_dispatch_id && review_dispatch.dig("lineage", "attempt_id").to_s == expected_dispatch_id
      errors << "#{label} independent review dispatch/attempt differs from the exact Major assignment"
    end
  end

  pointer = binding["json_pointer"].to_s
  begin
    analysis_row = pointer_value(analysis, pointer)
    errors << "#{label} row value SHA-256 is stale" unless binding["value_sha256"].to_s == value_sha256(analysis_row)
    errors << "#{label} row names a different Sequence Composition" unless analysis_row.to_h["sequence_composition_id"].to_s == candidate["sequence_composition_id"].to_s
    errors << "#{label} row Sequence Units differ from the selected candidate" unless Array(analysis_row.to_h["sequence_unit_bindings"]).map { |row| row["sequence_unit_id"].to_s } == Array(candidate["typed_sequence_unit_ids"]).map(&:to_s)
    flow_binding = analysis_row.to_h.dig("candidate_source_binding", "flow_reading_binding").to_h
    errors << "#{label} row Flow Reading hash differs from the selected candidate" unless flow_binding["source_value_sha256"].to_s == value_sha256(candidate["flow_reading"])
  rescue KeyError, IndexError, TypeError
    errors << "#{label} candidate row pointer is stale"
  end
end

def validate_v17_creative_graph(document, root, section_ids, sequence_units_by_id, errors)
  routes = Array(document["candidate_routes"])
  route_ids = routes.map { |row| row["candidate_id"].to_s }
  errors << "Front Planning v17 requires exactly ordered FP-A, FP-B, and FP-C complete routes" unless route_ids == %w[FP-A FP-B FP-C]
  ranks = routes.map { |row| row["recommendation_rank"] }
  errors << "FP-A/B/C recommendation ranks must be unique 1 through 3" unless ranks.sort == [1, 2, 3]
  storyline = document["storyline_lineage"].to_h
  pre00_lineage = storyline["pre00_lineage"].to_h
  preserved_storyline_versions = [pre00_lineage["pre00_storyline_original"]] +
    Array(pre00_lineage["pre00_storyline_revisions"]) +
    Array(storyline["front_planning_revisions"])
  preserved_storyline_versions = preserved_storyline_versions.compact
  preserved_storyline_versions_by_id = preserved_storyline_versions.to_h { |version| [version["version_id"].to_s, version] }
  routes.each do |route|
    version = route["complete_storyline_version"].to_h
    expected_sha = Digest::SHA256.hexdigest(version["full_storyline_text"].to_s)
    errors << "#{route['candidate_id']} complete storyline hash is stale" unless version["full_storyline_text_sha256"].to_s == expected_sha
    parent = preserved_storyline_versions_by_id[version["parent_version_id"].to_s]
    if parent.nil?
      errors << "#{route['candidate_id']} complete storyline parent version does not resolve"
    elsif version["parent_full_storyline_text_sha256"].to_s != parent["full_storyline_text_sha256"].to_s
      errors << "#{route['candidate_id']} complete storyline parent hash is stale"
    end
    route_sections = Array(route["sections"])
    unless route_sections.map { |row| row["section_id"].to_s } == section_ids
      errors << "#{route['candidate_id']} must exact-cover every section in order"
    end
    route_sections.each do |section|
      stack = section["major_scene_stack"].to_h
      placements = Array(stack["ordered_major_placements"])
      orders = placements.map { |row| row["order_within_section"] }
      errors << "#{route['candidate_id']} #{section['section_id']} Major placement order must be contiguous" unless orders == (1..placements.length).to_a
      if placements.length == 1 && stack["single_major_hold_bridge_rationale"].to_s.strip.empty?
        errors << "#{route['candidate_id']} #{section['section_id']} single-Major section requires deliberate hold/bridge rationale"
      end
      expansion_ids = Array(section["route_major_expansions"]).map { |row| row["major_scene_id"].to_s }
      placement_ids = placements.map { |row| row["major_scene_id"].to_s }
      errors << "#{route['candidate_id']} #{section['section_id']} Major expansions must exact-cover its stack" unless expansion_ids == placement_ids
    end
  end

  catalog = Array(document["major_scene_catalog"])
  catalog_ids = catalog.map { |row| row["major_scene_id"].to_s }
  errors << "major_scene_catalog MJxx ids must be unique" unless catalog_ids.uniq.length == catalog_ids.length
  candidate_set_ids = []
  selected_composition_ids = []
  catalog.each do |major|
    candidate_set = major["sequence_composition_candidate_set"].to_h
    candidate_set_ids << candidate_set["candidate_set_id"].to_s
    candidates = Array(candidate_set["candidates"])
    ids = candidates.map { |row| row["sequence_composition_id"].to_s }
    errors << "#{major['major_scene_id']} Sequence Composition ids must be unique" unless ids.uniq.length == ids.length
    unit_set_signatures = candidates.map { |row| Array(row["typed_sequence_unit_ids"]).map(&:to_s).sort }
    unless unit_set_signatures.uniq.length == unit_set_signatures.length
      errors << "#{major['major_scene_id']} Sequence Composition candidates must not repeat an exact Sequence Unit set"
    end
    selected_id = candidate_set["selected_sequence_composition_id"].to_s
    selected_composition_ids << selected_id
    errors << "#{major['major_scene_id']} selected Sequence Composition does not resolve" unless ids.include?(selected_id)
    errors << "#{major['major_scene_id']} requires exactly one selected Sequence Composition disposition" unless candidates.count { |row| row["disposition"].to_s == "selected" } == 1
    candidates.each do |candidate|
      unknown = Array(candidate["typed_sequence_unit_ids"]).map(&:to_s) - sequence_units_by_id.keys
      errors << "#{candidate['sequence_composition_id']} names unknown Sequence Units: #{unknown.join(', ')}" unless unknown.empty?
      binding = candidate["sequence_motion_analysis_binding"]
      selected_candidate = candidate["sequence_composition_id"].to_s == selected_id
      if selected_candidate
        if document["status"].to_s == "director_closed" && !binding.is_a?(Hash)
          errors << "#{major['major_scene_id']} Director-closed selected Sequence Composition requires one independently CDD-reviewed Sequence Motion Analysis binding"
        elsif binding.is_a?(Hash)
          validate_sequence_motion_analysis_binding(binding, candidate, major, document, root, errors)
        end
      elsif binding
        errors << "#{candidate['sequence_composition_id']} is non-selected and cannot carry Sequence Motion Analysis into 01 or 03V"
      end
    end
  end
  errors << "Major Sequence Candidate Set ids must be unique" unless candidate_set_ids.uniq.length == candidate_set_ids.length

  selected_route_id = document.dig("creative_experiment", "candidate_route_id").to_s
  selected_route = routes.find { |row| row["candidate_id"].to_s == selected_route_id }
  if selected_route.nil?
    errors << "creative_experiment candidate_route_id does not resolve"
    selected_core_slot_ids = []
  else
    validate_selected_route_storyline_binding(document, routes, selected_route, errors)
    selected_core_slot_ids = Array(selected_route["sections"]).flat_map do |section|
      Array(section["route_major_expansions"]).flat_map do |major|
        Array(major["core_cut_slots"]).map { |slot| slot["core_slot_id"].to_s }
      end
    end
    errors << "selected route Core Slot ids must be unique" unless selected_core_slot_ids.uniq.length == selected_core_slot_ids.length
  end

  candidate_sets = Array(document["core_visual_candidate_sets"])
  set_slot_ids = candidate_sets.map { |row| row["core_slot_id"].to_s }
  errors << "Core Visual Candidate Sets must exact-cover every selected material Core Slot" unless set_slot_ids.sort == selected_core_slot_ids.sort
  candidates_by_slot = {}
  candidate_set_ids_by_slot = {}
  candidate_sets.each do |set|
    slot_id = set["core_slot_id"].to_s
    candidate_set_ids_by_slot[slot_id] = set["candidate_set_id"].to_s
    candidates = Array(set["candidates"])
    ids = candidates.map { |row| row["candidate_id"].to_s }
    errors << "#{slot_id} Core visual candidate ids must be unique" unless ids.uniq.length == ids.length
    file_signatures = candidates.map { |row| [row["actual_path"].to_s, row["sha256"].to_s] }
    unless file_signatures.uniq.length == file_signatures.length
      errors << "#{slot_id} Core visual candidates must not repeat an identical path/SHA-256"
    end
    selected_id = set["selected_candidate_id"].to_s
    errors << "#{slot_id} selected Core visual candidate does not resolve" unless ids.include?(selected_id)
    errors << "#{slot_id} requires exactly one selected Core visual candidate disposition" unless candidates.count { |row| row["disposition"].to_s == "selected" } == 1
    candidates.each do |candidate|
      validate_file(resolve_path(candidate["actual_path"], root), candidate["sha256"], "#{slot_id} #{candidate['candidate_id']} actual still", root, errors)
    end
    candidates_by_slot[slot_id] = candidates.to_h { |row| [row["candidate_id"].to_s, row] }
  end

  binding_slots = []
  Array(document["core_reference_bindings"]).each do |binding|
    slot_id = binding["core_slot_id"].to_s
    binding_slots << slot_id
    decision = binding["decision"].to_h
    if decision["kind"].to_s == "selected_exact_reference"
      selected = candidates_by_slot.fetch(slot_id, {})[decision["selected_reference_candidate_id"].to_s]
      if selected.nil?
        errors << "#{slot_id} exact Core reference does not resolve to its candidate set"
      elsif selected["actual_path"].to_s != decision["actual_path"].to_s || selected["sha256"].to_s != decision["sha256"].to_s
        errors << "#{slot_id} exact Core reference must exact-copy selected candidate path and SHA-256"
      end
      validate_file(resolve_path(decision["actual_path"], root), decision["sha256"], "#{slot_id} selected exact Core reference", root, errors)
    else
      waiver = decision["founder_reference_waiver"].to_h
      errors << "#{slot_id} Founder waiver must name the exact Core Slot" unless waiver["core_slot_id"].to_s == slot_id
      receipt = waiver["receipt"].to_h
      validate_file(resolve_path(receipt["path"], root), receipt["sha256"], "#{slot_id} Founder reference waiver", root, errors)
    end
  end
  errors << "Core reference bindings must exact-cover every selected material Core Slot" unless binding_slots.sort == selected_core_slot_ids.sort
  if document["reference_coverage_complete"] == true && binding_slots.sort != selected_core_slot_ids.sort
    errors << "reference_coverage_complete cannot be true with incomplete Core reference coverage"
  end

  heroes = Array(document["hero_core_cut_candidates"])
  hero_ids = heroes.map { |row| row["hero_core_id"].to_s }
  errors << "Hero Core candidate ids must be unique" unless hero_ids.uniq.length == hero_ids.length
  heroes.each do |hero|
    output = hero["actual_output"].to_h
    validate_file(resolve_path(output["path"], root), output["sha256"], "#{hero['hero_core_id']} actual Hero output", root, errors)
  end
  coverage = document["hero_generation_coverage"].to_h
  actual_covered_roles = heroes.select { |row| row["pixel_review_status"].to_s == "pass" }.map { |row| row["coverage_role"].to_s }.uniq
  declared_covered_roles = Array(coverage["covered_roles"]).map(&:to_s)
  errors << "Hero generation covered_roles must be backed by passed actual outputs" unless (declared_covered_roles - actual_covered_roles).empty?
  required_roles = Array(coverage["required_roles"]).map(&:to_s)
  if coverage["complete"] == true && !(required_roles - declared_covered_roles).empty?
    errors << "Hero generation coverage cannot be complete while required roles are missing"
  end

  screen_map = document["screen_progression_map"].to_h
  nodes = Array(screen_map["nodes"])
  node_ids = nodes.map { |row| row["node_id"].to_s }
  errors << "screen_progression_map node ids must be unique" unless node_ids.uniq.length == node_ids.length
  Array(screen_map["ordered_edges"]).each do |edge|
    errors << "screen_progression_map edge names an unknown node" unless node_ids.include?(edge["from_node_id"].to_s) && node_ids.include?(edge["to_node_id"].to_s)
  end
  active_storyline = document.dig("storyline_lineage", "active_version").to_h
  errors << "screen_progression_map active storyline id/hash must exact-copy storyline_lineage" unless screen_map["active_storyline_version_id"].to_s == active_storyline["version_id"].to_s && screen_map["active_storyline_sha256"].to_s == active_storyline["full_storyline_text_sha256"].to_s

  scopes = Array(document["production_scopes"])
  scope_ids = scopes.map { |row| row["production_scope_id"].to_s }
  errors << "production_scope ids must be unique" unless scope_ids.uniq.length == scope_ids.length
  errors << "production_scopes must preserve at least one full-MV scope" unless scopes.any? { |row| row["route_type"].to_s == "full_mv" }
  scopes.each do |scope|
    unknown = (Array(scope["selected_node_ids"]) + Array(scope["unopened_full_mv_node_ids"])).map(&:to_s) - node_ids
    errors << "#{scope['production_scope_id']} names unknown screen progression nodes: #{unknown.join(', ')}" unless unknown.empty?
    overlap = Array(scope["selected_node_ids"]).map(&:to_s) & Array(scope["unopened_full_mv_node_ids"]).map(&:to_s)
    errors << "#{scope['production_scope_id']} selected and unopened nodes must be disjoint" unless overlap.empty?
  end
  experiment = document["creative_experiment"].to_h
  errors << "creative_experiment Sequence Candidate Sets differ from catalog" unless Array(experiment["sequence_candidate_set_ids"]).map(&:to_s).sort == candidate_set_ids.sort
  errors << "creative_experiment selected Sequence Compositions differ from catalog" unless Array(experiment["selected_sequence_composition_ids"]).map(&:to_s).sort == selected_composition_ids.sort
  errors << "creative_experiment Core Visual Candidate Sets differ from selected route" unless Array(experiment["core_visual_candidate_set_ids"]).map(&:to_s).sort == candidate_set_ids_by_slot.values.sort
  errors << "creative_experiment generated Hero ids do not resolve" unless (Array(experiment["generated_hero_core_ids"]).map(&:to_s) - hero_ids).empty?
  founder_disposition = experiment.dig("founder_decision", "disposition").to_s
  allowed_founder_dispositions = case document["status"].to_s
                                 when "draft", "founder_review"
                                   %w[pending]
                                 when "direction_aligned", "director_closed"
                                   %w[teaser_only teaser_first_full_mv_hold full_mv_development full_mv_approved]
                                 when "hold"
                                   %w[pending revise_experiment teaser_first_full_mv_hold]
                                 when "rejected"
                                   %w[reject_archive]
                                 else
                                   []
                                 end
  unless allowed_founder_dispositions.include?(founder_disposition)
    errors << "creative_experiment Founder decision #{founder_disposition.inspect} is inconsistent with Front Planning status #{document['status'].inspect}"
  end
  Array(experiment["derivative_routes"]).each do |route|
    errors << "#{route['derivative_route_id']} names unknown production_scope_id" unless scope_ids.include?(route["production_scope_id"].to_s)
  end
end

def load_video_analysis_bindings(root, errors)
  hub_root = root.join("source-materials", "video-sources").expand_path.cleanpath
  registry_path = root.join(VIDEO_ANALYSIS_REGISTRY).expand_path.cleanpath
  read_first_path = root.join(VIDEO_READ_FIRST).expand_path.cleanpath
  issues = []
  unless registry_path.file?
    return {all: {}, by_source: {}, by_path: {}, evidence: {}, issues: ["video source analysis registry is missing"]}
  end
  unless read_first_path.file?
    issues << "video source READ-FIRST.md is missing"
  end

  registry = load_mapping(registry_path)
  unless registry["schema_version"].to_s == "idol_video_reference_analysis_registry.v2"
    issues << "video source analysis registry must use idol_video_reference_analysis_registry.v2"
  end

  all = {}
  by_source = Hash.new { |hash, key| hash[key] = {} }
  by_path = {}
  Array(registry["sources"]).each do |source|
    source_key = source["source_key"].to_s
    [source["source_manifest"], source["primary_media"]].compact.each do |ref|
      by_path[resolve_path(ref.to_h["path"], root).to_s] = source_key
    end
    Array(source["analysis_records"]).each do |record|
      Array(record["analysis_inputs"]).each do |input|
        by_path[resolve_path(input.to_h["path"], root).to_s] = source_key
      end
      next unless record["status"].to_s == "complete"

      analysis = record["analysis"].to_h
      analysis_path = resolve_path(analysis["path"], root)
      unless inside?(analysis_path, hub_root)
        issues << "#{source_key} complete analysis is outside source-materials/video-sources"
        next
      end
      binding_key = [analysis_path.to_s, analysis["sha256"].to_s]
      all[binding_key] = source_key
      by_source[source_key][binding_key] = true
    end
  end

  evidence = {}
  catalog_path = root.join("catalog", "references", "reference-catalog.yaml")
  if catalog_path.file?
    catalog = load_mapping(catalog_path)
    Array(catalog["reference_units"]).each do |row|
      next unless row["media_type"].to_s.start_with?("video")

      analysis = row["analysis_ref"].to_h
      analysis_key = [resolve_path(analysis["path"], root).to_s, analysis["sha256"].to_s]
      Array(row["selected_evidence"]).each do |item|
        evidence[resolve_path(item.to_h["path"], root).to_s] = analysis_key
      end
    end
  end
  {all: all, by_source: by_source, by_path: by_path, evidence: evidence, issues: issues}
rescue JSON::ParserError, Psych::Exception, TypeError => e
  {all: {}, by_source: {}, by_path: {}, evidence: {}, issues: ["cannot parse video source analysis registry or reference catalog: #{e.message}"]}
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
unless inside?(artifact, root) && artifact.file?
  errors << "Front Planning artifact is missing or outside the repository"
end

document = {}
if errors.empty?
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => e
    errors << "cannot parse Front Planning artifact: #{e.message}"
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
  unless IdolFrontPlanningSequenceCoreHold.skip_frozen_legacy?(artifact, admission_graph: options[:admission_graph])
    IdolFrontPlanningSequenceCoreHold.holds(document).each do |row|
      errors << "#{row.fetch('code')} core_slot=#{row.fetch('core_slot_id')} sequence_unit=#{row.fetch('sequence_unit')} candidate_count=#{row.fetch('candidate_count')}"
    end
    IdolFrontPlanningLocalPairwiseGlobal.holds(document).each do |row|
      errors << "#{row.fetch('code')} scope=#{row.fetch('scope')} #{row.fetch('detail')}"
    end
  end
  errors << "only #{ACTIVE_FRONT_PLANNING_VERSION} is active" unless document["schema_version"].to_s == ACTIVE_FRONT_PLANNING_VERSION
  pre00_handoff_ref = document["source_pre00_handoff"].to_h
  pre00_handoff_path = resolve_path(pre00_handoff_ref["path"], root)
  validate_file(pre00_handoff_path, pre00_handoff_ref["sha256"], "source_pre00_handoff", root, errors)
  pre00_handoff = {}
  if inside?(pre00_handoff_path, root) && pre00_handoff_path.file?
    begin
      pre00_handoff = load_mapping(pre00_handoff_path)
    rescue JSON::ParserError, Psych::Exception, TypeError => e
      errors << "cannot parse source_pre00_handoff: #{e.message}"
    end
  end

  storyline = document["storyline_lineage"].to_h
  source_storyline_binding = pre00_handoff["storyline_lineage"].to_h
  errors << "source PRE-00 handoff must use idol-pre00-selection-handoff.v4" unless pre00_handoff["schema_version"].to_s == "idol-pre00-selection-handoff.v4"
  errors << "source PRE-00 handoff storyline pointer must remain /storyline_lineage" unless source_storyline_binding["source_pointer"].to_s == "/storyline_lineage"
  source_pre00_lineage = source_storyline_binding["value"]
  source_pre00_lineage_sha = value_sha256(source_pre00_lineage)
  unless source_storyline_binding["value_sha256"].to_s == source_pre00_lineage_sha
    errors << "source PRE-00 handoff storyline lineage hash is stale"
  end
  unless storyline["source_pre00_lineage_value_sha256"].to_s == source_pre00_lineage_sha
    errors << "Front Planning PRE-00 storyline lineage source hash is stale"
  end
  unless canonical_value(storyline["pre00_lineage"]) == canonical_value(source_pre00_lineage)
    errors << "Front Planning must exact-project the complete PRE-00 storyline lineage without paraphrase or omission"
  end

  audience_target_lineage = document["pre00_audience_target_lineage"].to_h
  {
    "audience_profiles" => "/audience_profiles",
    "x_reference_audience_envelope" => "/x_reference_audience_envelope",
    "title_target_intersection" => "/title_target_intersection"
  }.each do |field, expected_pointer|
    source_binding = pre00_handoff[field].to_h
    projected_binding = audience_target_lineage[field].to_h
    source_value_sha = value_sha256(source_binding["value"])
    errors << "source PRE-00 #{field} pointer must remain #{expected_pointer}" unless source_binding["source_pointer"].to_s == expected_pointer
    errors << "source PRE-00 #{field} value hash is stale" unless source_binding["value_sha256"].to_s == source_value_sha
    errors << "Front Planning #{field} must exact-copy PRE-00 binding path/hash/value" unless canonical_value(projected_binding) == canonical_value(source_binding)
  end

  pre00_versions = [source_pre00_lineage.to_h["pre00_storyline_original"]] + Array(source_pre00_lineage.to_h["pre00_storyline_revisions"])
  pre00_versions.compact.each do |version|
    expected_text_sha = Digest::SHA256.hexdigest(version["full_storyline_text"].to_s)
    unless version["full_storyline_text_sha256"].to_s == expected_text_sha
      errors << "#{version['version_id']} PRE-00 full storyline text hash is stale"
    end
  end
  source_pre00_active_id = source_pre00_lineage.to_h.dig("active_version", "version_id").to_s
  previous_version = pre00_versions.find { |version| version.to_h["version_id"].to_s == source_pre00_active_id }.to_h
  if previous_version.empty?
    errors << "Front Planning source PRE-00 active storyline version does not resolve"
  end

  fp_revisions = Array(storyline["front_planning_revisions"])
  unless IdolFrontPlanningSequenceCoreHold.skip_frozen_legacy?(artifact, admission_graph: options[:admission_graph])
    errors.concat(
      IdolStorylineDensityLocatorContract.close_artifact(
        root,
        artifact,
        document: document,
        stage: "front_planning"
      )
    )
    selected_route_id = document.dig("creative_experiment", "candidate_route_id").to_s
    selected_route = Array(document["candidate_routes"]).find { |row| row["candidate_id"].to_s == selected_route_id }
    unless selected_route.nil?
      major_ids = IdolKineticSlotSheetContract.selected_major_ids(selected_route)
      errors.concat(
        IdolKineticSlotSheetContract.coverage_errors(
          artifact,
          major_ids,
          document: document,
          selected_route: selected_route
        )
      )
    end
  end
  fp_revisions.each_with_index do |revision, index|
    expected_id = format("FP_STORYLINE_V%03d", index + 1)
    errors << "Front Planning storyline revisions must be append-only and sequential: expected #{expected_id}" unless revision["version_id"].to_s == expected_id
    errors << "#{revision['version_id']} parent version differs from the preceding preserved version" unless revision["parent_version_id"].to_s == previous_version["version_id"].to_s
    unless revision["parent_full_storyline_text_sha256"].to_s == previous_version["full_storyline_text_sha256"].to_s
      errors << "#{revision['version_id']} parent storyline hash is stale"
    end
    expected_text_sha = Digest::SHA256.hexdigest(revision["full_storyline_text"].to_s)
    errors << "#{revision['version_id']} full storyline text hash is stale" unless revision["full_storyline_text_sha256"].to_s == expected_text_sha
    Array(revision["applied_reference_receipts"]).each_with_index do |receipt, receipt_index|
      label = "#{revision['version_id']} applied_reference_receipts[#{receipt_index}]"
      begin
        source_value = pointer_value(document, receipt["source_json_pointer"])
        errors << "#{label} source value hash is stale" unless receipt["source_value_sha256"].to_s == value_sha256(source_value)
        errors << "#{label} reference_unit_id differs from source" unless receipt["reference_unit_id"].to_s == source_value.to_h["reference_unit_id"].to_s
      rescue KeyError, IndexError
        errors << "#{label} source pointer is stale"
      end
    end
    previous_version = revision
  end

  active_storyline = storyline["active_version"].to_h
  begin
    resolved_active = pointer_value(document, active_storyline["version_json_pointer"])
    errors << "Front Planning active storyline version id differs from its preserved full-text version" unless active_storyline["version_id"].to_s == resolved_active.to_h["version_id"].to_s
    errors << "Front Planning active full storyline text differs from its preserved version" unless active_storyline["full_storyline_text"].to_s == resolved_active.to_h["full_storyline_text"].to_s
    active_text_sha = Digest::SHA256.hexdigest(active_storyline["full_storyline_text"].to_s)
    errors << "Front Planning active full storyline text hash is stale" unless active_storyline["full_storyline_text_sha256"].to_s == active_text_sha
    errors << "Front Planning active storyline hash differs from its preserved version" unless active_storyline["full_storyline_text_sha256"].to_s == resolved_active.to_h["full_storyline_text_sha256"].to_s
  rescue KeyError, IndexError
    errors << "Front Planning active storyline pointer is stale"
  end
  density_review = storyline["contextual_density_review"].to_h
  errors << "Front Planning density review version is stale" unless density_review["reviewed_version_id"].to_s == active_storyline["version_id"].to_s
  errors << "Front Planning density review hash is stale" unless density_review["reviewed_full_storyline_text_sha256"].to_s == active_storyline["full_storyline_text_sha256"].to_s
  if %w[direction_aligned director_closed].include?(document["status"].to_s)
    errors << "aligned or Director-closed Front Planning requires full-storyline contextual density PASS" unless density_review["decision"].to_s == "pass"
  end

  song_lock = document["selected_song_lock"].to_h
  validate_file(resolve_path(song_lock["path"], root), song_lock["sha256"], "selected_song_lock", root, errors)

  sequence_ref = document["founder_sequence_control"].to_h
  sequence_path = resolve_path(sequence_ref["path"], root)
  validate_file(sequence_path, sequence_ref["sha256"], "founder_sequence_control", root, errors)
  sequence_control = {}
  sequence_control_valid = false
  if inside?(sequence_path, root) && sequence_path.file?
    begin
      sequence_control = load_mapping(sequence_path)
    rescue JSON::ParserError, Psych::Exception, TypeError => e
      errors << "cannot parse founder_sequence_control: #{e.message}"
    end
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      FOUNDER_SEQUENCE_VALIDATOR.to_s,
      "--root",
      root.to_s,
      sequence_path.to_s,
      chdir: ROOT.to_s
    )
    sequence_control_valid = status.success? && !sequence_control.empty?
    unless status.success?
      errors << "Founder Sequence Control validation failed: #{[stderr, stdout].join(' ').strip}"
      sequence_control = {}
    end
  end
  if sequence_control_valid
    errors << "Founder Sequence Control content_id differs from Front Planning" unless sequence_control["content_id"].to_s == document["content_id"].to_s
    errors << "Founder Sequence Control lane must be idol_mv" unless sequence_control["lane"].to_s == "idol_mv"
    errors << "IDOL Founder start control must be director-ready before Front Planning" unless sequence_control["status"].to_s == "director_ready"
    errors << "IDOL Founder start control requires explicit start authorization" unless sequence_control.dig("startup_gate", "decision").to_s == "start_authorized"
    errors << "IDOL Founder start control must authorize projection" unless sequence_control.dig("startup_gate", "projection_authorized") == true
  end
  control_majors = Array(sequence_control.dig("story_flow", "ordered_major_scenes"))
  control_major_ids = control_majors.map { |row| row["control_major_id"].to_s }
  control_majors_by_id = control_majors.to_h { |row| [row["control_major_id"].to_s, row] }
  control_references = Array(sequence_control.dig("reference_plan", "references"))
  applied_control_reference_ids = control_references.select { |row| %w[applied combined].include?(row["disposition"].to_s) }.map { |row| row["reference_id"].to_s }
  governing_control_reference_ids = Array(sequence_control.dig("reference_plan", "governing_reference_ids")).map(&:to_s)
  supporting_control_reference_ids = applied_control_reference_ids - governing_control_reference_ids
  # Cross-source comparisons need a valid control; its root failure is already recorded.
  founder_brief = document["founder_brief"].to_h
  if sequence_control_valid
    unless Array(founder_brief["selected_main_reference_ids"]).map(&:to_s).sort == governing_control_reference_ids.sort
      errors << "founder_brief main references must exact-copy Founder Sequence Control governing references"
    end
    unless Array(founder_brief["selected_supporting_reference_ids"]).map(&:to_s).sort == supporting_control_reference_ids.sort
      errors << "founder_brief supporting references must exact-copy applied Founder Sequence Control supporting references"
    end
  end

  visual = document["current_title_visual_identity"].to_h
  album_key = visual["album_key"].to_s
  title_key = visual["title_key"].to_s
  expected_root = "assets/members/album-assets/#{album_key}/#{title_key}"
  errors << "current-title asset_root must equal #{expected_root}" unless visual["asset_root"].to_s == expected_root
  manifest = visual["asset_manifest"].to_h
  validate_file(resolve_path(manifest["path"], root), manifest["sha256"], "current-title asset manifest", root, errors)
  errors << "asset manifest must stay inside the current-title package" unless manifest["path"].to_s.start_with?("#{expected_root}/")

  assets = Array(visual["assets"])
  asset_ids = assets.map { |row| row["asset_id"].to_s }
  errors << "visual asset ids must be unique" unless asset_ids.uniq.length == asset_ids.length
  assets.each_with_index do |asset, index|
    label = "current_title_visual_identity.assets[#{index}]"
    errors << "#{label} must stay inside #{expected_root}" unless asset["path"].to_s.start_with?("#{expected_root}/")
    errors << "#{label} uses a prohibited face-only path" if asset["path"].to_s.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
    validate_file(resolve_path(asset["path"], root), asset["sha256"], label, root, errors)
    if asset["asset_type"] == "member_visual_anchor" && Array(asset["member_ids"]).empty?
      errors << "#{label} member visual must name at least one member"
    end
    if asset["asset_type"].to_s.include?("background") || asset["asset_type"].to_s.include?("world")
      errors << "#{label} separate background/world assets are not active in Front Planning v17"
    end
  end
  assets_by_id = assets.to_h { |row| [row["asset_id"].to_s, row] }

  research = document["reference_connection_research"].to_h
  reference_index_ref = research["reference_working_index"].to_h
  reference_index_path = resolve_path(reference_index_ref["path"], root)
  validate_file(
    reference_index_path,
    reference_index_ref["sha256"],
    "reference_connection_research.reference_working_index",
    root,
    errors
  )
  reference_index = {}
  if inside?(reference_index_path, root) && reference_index_path.file?
    begin
      reference_index = load_mapping(reference_index_path)
    rescue JSON::ParserError, Psych::Exception, TypeError => e
      errors << "cannot parse Reference Working Index: #{e.message}"
    end
    stdout, stderr, status = Open3.capture3(
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      REFERENCE_INDEX_SCHEMA.to_s,
      reference_index_path.to_s,
      chdir: ROOT.to_s
    )
    errors << "Reference Working Index schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
  end
  index_rows = Array(reference_index["rows"])
  index_row_ids = index_rows.map { |row| row["row_id"].to_s }
  errors << "Reference Working Index row ids must be unique" unless index_row_ids.uniq.length == index_row_ids.length
  index_rows_by_id = index_rows.to_h { |row| [row["row_id"].to_s, row] }
  pinterest_index_row_ids = index_rows.select { |row| pinterest_index_row?(row) }.map { |row| row["row_id"].to_s }.to_set

  main_reference_ids = Array(founder_brief["selected_main_reference_ids"]).map(&:to_s)
  source_lineages = Array(research["source_lineages"])
  lineage_main_ids = source_lineages.map { |row| row["main_reference_id"] }.compact.map(&:to_s)
  if main_reference_ids.empty?
    errors << "no-main Front Planning must use no_main_function_first discovery" unless research["discovery_mode"].to_s == "no_main_function_first"
    errors << "no-main function-first lineage must keep main_reference_id null" unless lineage_main_ids.empty?
  else
    errors << "Founder-main Front Planning must use founder_main_origin_first discovery" unless research["discovery_mode"].to_s == "founder_main_origin_first"
    unless lineage_main_ids.sort == main_reference_ids.sort
      errors << "origin-first lineages must cover every selected Founder main reference exactly once"
    end
  end

  units = Array(research["reference_units"])
  video_analysis_bindings = load_video_analysis_bindings(root, errors)
  unit_ids = units.map { |row| row["reference_unit_id"].to_s }
  errors << "reference unit ids must be unique" unless unit_ids.uniq.length == unit_ids.length
  functions_by_id = {}
  units.each_with_index do |unit, index|
    row_id = unit["reference_working_index_row_id"].to_s
    index_row = index_rows_by_id[row_id]
    if index_row.nil?
      errors << "#{unit['reference_unit_id']} must resolve to one Reference Working Index row"
    else
      errors << "#{unit['reference_unit_id']} Index row reference_unit_id is stale" unless index_row["reference_unit_id"].to_s == unit["reference_unit_id"].to_s
      errors << "#{unit['reference_unit_id']} Index row source_id differs from source_identity" unless index_row["source_id"].to_s == unit["source_identity"].to_s
      errors << "#{unit['reference_unit_id']} disposition differs from its Index row" unless index_row["disposition"].to_s == unit["disposition"].to_s
      source_manifest = index_row["source_manifest"].to_h
      validate_file(
        resolve_path(source_manifest["path"], root),
        source_manifest["sha256"],
        "#{unit['reference_unit_id']} Index source_manifest",
        root,
        errors
      )
      review_pointer = index_row.dig("cdd_review", "review_pointer").to_h
      validate_file(
        resolve_path(review_pointer["path"], root),
        review_pointer["sha256"],
        "#{unit['reference_unit_id']} Index CDD review",
        root,
        errors
      )
      if %w[applied combined].include?(unit["disposition"].to_s)
        eligibility = index_row["source_eligibility"].to_h
        unless eligibility["origin_identity_verified"] == true &&
               eligibility["active_reuse_eligible"] == true &&
               eligibility["historical_row_reused_without_review"] == false
          errors << "#{unit['reference_unit_id']} lacks active origin-verified Index eligibility"
        end
        errors << "#{unit['reference_unit_id']} requires an accepted CDD Index review" unless index_row.dig("cdd_review", "disposition").to_s == "accepted"
        bound_sections = Array(index_row["section_bindings"]).map { |binding| binding["section_id"].to_s }
        missing_section_bindings = Array(unit["target_section_ids"]).map(&:to_s) - bound_sections
        unless missing_section_bindings.empty?
          errors << "#{unit['reference_unit_id']} Index row omits target section bindings: #{missing_section_bindings.join(', ')}"
        end
        selected_evidence = index_row["selected_evidence"].to_h
        unless selected_evidence["path"].to_s == unit["source_path"].to_s && selected_evidence["sha256"].to_s == unit["source_sha256"].to_s
          errors << "#{unit['reference_unit_id']} must exact-copy its Index selected evidence path and SHA-256"
        end
        permission = eligibility["restricted_source_permission"].to_h
        unless permission.empty?
          founder_pointer = permission["founder_approval_pointer"].to_h
          validate_file(
            resolve_path(founder_pointer["path"], root),
            founder_pointer["sha256"],
            "#{unit['reference_unit_id']} restricted-source Founder permission",
            root,
            errors
          )
          scene_lock = permission["direct_scene_binding_lock_pointer"].to_h
          validate_file(
            resolve_path(scene_lock["path"], root),
            scene_lock["sha256"],
            "#{unit['reference_unit_id']} restricted-source direct-scene lock",
            root,
            errors
          ) unless scene_lock.empty?
        end
      elsif Array(index_row["section_bindings"]).any? || Array(index_row["downstream_consumers"]).any?
        errors << "#{unit['reference_unit_id']} held/rejected Index row cannot bind or feed downstream consumers"
      end
    end
    connection_proof = unit["connection_quality_proof"].to_h
    begin
      resolved_index_row = pointer_value(
        reference_index,
        connection_proof["reference_working_index_json_pointer"]
      )
      unless resolved_index_row.is_a?(Hash) && resolved_index_row["row_id"].to_s == row_id
        errors << "#{unit['reference_unit_id']} connection_quality_proof pointer resolves a different Reference Working Index row"
      end
      unless connection_proof["reference_working_index_row_value_sha256"].to_s == value_sha256(resolved_index_row)
        errors << "#{unit['reference_unit_id']} connection_quality_proof Reference Working Index row hash is stale"
      end
    rescue KeyError, IndexError
      errors << "#{unit['reference_unit_id']} connection_quality_proof Reference Working Index pointer is stale"
    end
    source_path = resolve_path(unit["source_path"], root)
    validate_file(
      source_path,
      unit["source_sha256"],
      "reference_connection_research.reference_units[#{index}]",
      root,
      errors
    )
    validate_sequence_unit(unit, root, errors)
    if unit["source_kind"] == "sequence_sheet" && Array(unit["ordered_sequence_grammar"]).length < 2
      errors << "#{unit['reference_unit_id']} sequence sheet must record an ordered multi-frame grammar"
    end
    source_key = unit["source_identity"].to_s
    expected_analysis = video_analysis_bindings[:evidence][source_path.to_s]
    expected_source = if video_analysis_bindings[:by_source].key?(source_key)
                        source_key
                      else
                        video_analysis_bindings[:by_path][source_path.to_s] || video_analysis_bindings[:all][expected_analysis]
                      end
    registered_video = VIDEO_SOURCE_KINDS.include?(unit["source_kind"].to_s) ||
      !expected_source.nil? ||
      inside?(source_path, root.join("source-materials", "video-sources")) ||
      !expected_analysis.nil?
    if registered_video
      video_analysis_bindings[:issues].each do |issue|
        errors << "#{unit['reference_unit_id']} registered-video source preflight failed: #{issue}"
      end
      if expected_source.nil?
        errors << "#{unit['reference_unit_id']} must resolve to one registered video source identity or hash-bound source path"
      elsif source_key != expected_source
        errors << "#{unit['reference_unit_id']} source_identity must equal registered source_key #{expected_source}"
      end
    end
    Array(unit["function_analysis"]).each_with_index do |function, function_index|
      function_id = function["function_id"].to_s
      if function_id.empty?
        errors << "#{unit['reference_unit_id']} function_analysis[#{function_index}] has a blank function_id"
      elsif functions_by_id.key?(function_id)
        errors << "reference function ids must be globally unique: #{function_id}"
      else
        functions_by_id[function_id] = {"unit" => unit, "function" => function}
      end
      analysis_record = function["analysis_record"].to_h
      analysis_path = resolve_path(analysis_record["path"], root)
      validate_file(
        analysis_path,
        analysis_record["sha256"],
        "#{unit['reference_unit_id']} #{function_id} analysis_record",
        root,
        errors
      )
      next unless registered_video

      analysis_key = [analysis_path.to_s, analysis_record["sha256"].to_s]
      allowed = expected_source ? video_analysis_bindings[:by_source][expected_source] : {}
      unless allowed.key?(analysis_key)
        errors << "#{unit['reference_unit_id']} #{function_id} must bind the exact complete source-owned video analysis; run-owned or stale analysis is not allowed"
      end
    end
  end
  units_by_id = units.to_h { |row| [row["reference_unit_id"].to_s, row] }
  sequence_units = units.map { |row| row["sequence_unit"] if row["sequence_unit"].is_a?(Hash) }.compact
  sequence_units_by_id = sequence_units.to_h { |row| [row["sequence_unit_id"].to_s, row] }
  sequence_unit_ids = sequence_units_by_id.keys
  errors << "active Sequence Unit ids must be unique" unless sequence_unit_ids.length == sequence_units.length
  sequence_runs = Array(research["sequence_runs"])
  sequence_run_ids = sequence_runs.map { |row| row["sequence_run_id"].to_s }
  errors << "Sequence Run ids must be unique" unless sequence_run_ids.uniq.length == sequence_run_ids.length
  sequence_runs.each do |run|
    run_id = run["sequence_run_id"].to_s
    ordered_ids = Array(run["ordered_sequence_unit_ids"]).map(&:to_s)
    unknown_ids = ordered_ids - sequence_unit_ids
    errors << "#{run_id} names unknown active Sequence Units: #{unknown_ids.join(', ')}" unless unknown_ids.empty?
    bound_units = ordered_ids.map { |id| sequence_units_by_id[id] }.compact
    mismatched_run_ids = bound_units.reject { |row| row["sequence_run_id"].to_s == run_id }.map { |row| row["sequence_unit_id"].to_s }
    errors << "#{run_id} contains Sequence Units bound to another run: #{mismatched_run_ids.join(', ')}" unless mismatched_run_ids.empty?
    bound_units.each_cons(2) do |left, right|
      left_last = Array(left["ordered_frames"]).last.to_h
      right_first = Array(right["ordered_frames"]).first.to_h
      if left_last.dig("artifact", "sha256").to_s == right_first.dig("artifact", "sha256").to_s ||
         left_last["source_frame_or_cell_id"].to_s == right_first["source_frame_or_cell_id"].to_s
        errors << "#{run_id} linked Sequence Units duplicate a boundary frame"
      end
    end
  end

  sections = Array(document["section_plan"])
  section_ids = sections.map { |row| row["section_id"].to_s }
  errors << "section ids must be unique" unless section_ids.uniq.length == section_ids.length
  all_key_screen_ids = []
  key_screen_section_by_id = {}
  projected_control_major_ids = []
  sections.each do |section|
    section_id = section["section_id"].to_s
    member_ids = Array(section["assigned_member_ids"]).map(&:to_s)
    member_asset_ids = Array(section["member_visual_asset_ids"]).map(&:to_s)
    unknown_assets = member_asset_ids.uniq - asset_ids
    errors << "#{section_id} names unknown visual assets: #{unknown_assets.join(', ')}" unless unknown_assets.empty?
    member_asset_ids.each do |asset_id|
      asset = assets_by_id[asset_id]
      next unless asset
      unless %w[member_visual_anchor unit_or_group_visual_anchor].include?(asset["asset_type"].to_s)
        errors << "#{section_id} member_visual_asset_ids contains a non-member visual asset"
      end
    end
    uncovered_members = member_ids.reject do |member_id|
      member_asset_ids.any? { |asset_id| Array(assets_by_id.dig(asset_id, "member_ids")).map(&:to_s).include?(member_id) }
    end
    errors << "#{section_id} lacks current-title member visual coverage for #{uncovered_members.join(', ')}" unless uncovered_members.empty?

    major_scenes = Array(section["major_scene_flow"])
    section_sequence_unit_ids = Array(section["sequence_unit_ids"]).map(&:to_s)
    reference_ids = (
      Array(section["scene_reference_unit_ids"]) +
      Array(section["choreography_reference_unit_ids"]) +
      major_scenes.flat_map { |scene| Array(scene["reference_unit_ids"]) }
    ).map(&:to_s)
    unknown_units = reference_ids - unit_ids
    errors << "#{section_id} names unknown reference units: #{unknown_units.join(', ')}" unless unknown_units.empty?
    inactive_units = reference_ids.map do |reference_id|
      unit = units_by_id[reference_id]
      reference_id unless unit.nil? || %w[applied combined].include?(unit["disposition"].to_s)
    end.compact.uniq
    errors << "#{section_id} may bind only applied or combined reference units: #{inactive_units.join(', ')}" unless inactive_units.empty?
    if section_sequence_unit_ids.empty?
      errors << "#{section_id} requires at least one applied or combined exact-five one-second Sequence Unit"
    end
    section_sequence_unit_ids.each do |sequence_unit_id|
      sequence_unit = sequence_units_by_id[sequence_unit_id]
      if sequence_unit.nil?
        errors << "#{section_id} names unknown active Sequence Unit #{sequence_unit_id}"
        next
      end
      source_unit = units.find { |unit| unit["sequence_unit"].equal?(sequence_unit) || unit["sequence_unit"] == sequence_unit }
      unless source_unit && Array(source_unit["target_section_ids"]).map(&:to_s).include?(section_id) && %w[applied combined].include?(source_unit["disposition"].to_s)
        errors << "#{section_id} Sequence Unit #{sequence_unit_id} is not an applied/combined section-targeted unit"
      end
    end
    if %w[primary supporting].include?(section["choreography_presence_policy"].to_s)
      choreography_units = Array(section["choreography_reference_unit_ids"]).map { |id| units_by_id[id.to_s] }.compact
      unless choreography_units.any? { |unit| %w[choreography_reference performance_video].include?(unit["source_kind"].to_s) && %w[applied combined].include?(unit["disposition"].to_s) }
        errors << "#{section_id} choreography requires an active official/original choreography or performance reference"
      end
    end

    major_scenes.each do |scene|
      scene_id = scene["major_scene_id"].to_s
      major_reference_ids = Array(scene["reference_unit_ids"]).map(&:to_s)
      major_reference_ids.each do |reference_id|
        unit = units_by_id[reference_id]
        next if unit.nil?

        unless Array(unit["target_section_ids"]).map(&:to_s).include?(section_id)
          errors << "#{scene_id} uses #{reference_id} outside its targeted section"
        end
        if unit["sequence_unit"].is_a?(Hash) && unit.dig("sequence_unit", "major_reference_eligible") != true
          errors << "#{scene_id} Sequence Unit #{reference_id} is not eligible for Major reference binding"
        end
      end
      major_direction = scene["major_direction"].to_h
      source_control_major_id = major_direction["source_control_major_id"].to_s
      projected_control_major_ids << source_control_major_id
      if sequence_control_valid
        control_major = control_majors_by_id[source_control_major_id]
        if control_major.nil?
          errors << "#{scene_id} names unknown Founder Sequence Control Major #{source_control_major_id}"
        else
          errors << "#{scene_id} Major direction differs from its director-ready control" unless major_direction["direction"].to_s == control_major["direction"].to_s
          unless Array(major_direction["major_scene_boundaries"]).map(&:to_s) == Array(control_major["major_scene_boundaries"]).map(&:to_s)
            errors << "#{scene_id} Major boundaries differ from their director-ready control"
          end
          missing_control_refs = Array(control_major["reference_ids"]).map(&:to_s) - major_reference_ids
          unless missing_control_refs.empty?
            errors << "#{scene_id} omits control-bound references: #{missing_control_refs.join(', ')}"
          end
        end
      end
      evidence = Array(scene["major_visual_evidence"])
      evidence_ids = evidence.map { |row| row["evidence_id"].to_s }
      errors << "#{scene_id} major visual input ids must be unique" unless evidence_ids.uniq.length == evidence_ids.length
      evidence.each_with_index do |row, evidence_index|
        artifact_ref = row["artifact"].to_h
        validate_file(
          resolve_path(artifact_ref["path"], root),
          artifact_ref["sha256"],
          "#{scene_id} major_visual_evidence[#{evidence_index}]",
          root,
          errors
        )
        named_refs = Array(row["reference_unit_ids"]).map(&:to_s)
        named_assets = Array(row["current_title_asset_ids"]).map(&:to_s)
        if named_refs.empty? && named_assets.empty?
          errors << "#{scene_id} #{row['evidence_id']} must bind a reference unit or current-title asset"
        end
        unknown_evidence_refs = named_refs - unit_ids
        errors << "#{scene_id} #{row['evidence_id']} names unknown reference units: #{unknown_evidence_refs.join(', ')}" unless unknown_evidence_refs.empty?
        unknown_evidence_assets = named_assets - asset_ids
        errors << "#{scene_id} #{row['evidence_id']} names unknown current-title assets: #{unknown_evidence_assets.join(', ')}" unless unknown_evidence_assets.empty?
      end

      major_quality = scene["director_major_quality_review"].to_h
      reviewed_evidence_ids = Array(major_quality["reviewed_ids"]).map(&:to_s)
      unknown_reviewed_evidence = reviewed_evidence_ids - evidence_ids
      errors << "#{scene_id} director Major review names unknown visual inputs: #{unknown_reviewed_evidence.join(', ')}" unless unknown_reviewed_evidence.empty?

      exception_gate = scene["founder_exception_gate"].to_h
      new_member_visual_ids = evidence.select { |row| row["evidence_kind"].to_s == "major_scene_member_visual_test" }.map { |row| row["evidence_id"].to_s }
      if new_member_visual_ids.any?
        errors << "#{scene_id} new or restyled member visual requires the Founder exception gate" unless exception_gate["required"] == true
        errors << "#{scene_id} new or restyled member visual requires Founder PASS" unless exception_gate["decision"].to_s == "pass"
        missing_exception_reviews = new_member_visual_ids - Array(exception_gate["reviewed_ids"]).map(&:to_s)
        errors << "#{scene_id} Founder exception gate omits new member visual candidates: #{missing_exception_reviews.join(', ')}" unless missing_exception_reviews.empty?
      elsif exception_gate["required"] == false && exception_gate["decision"].to_s != "not_required"
        errors << "#{scene_id} non-required Founder exception gate must remain not_required"
      end

      key_screens = Array(scene["key_screen_anchors"])
      key_screen_ids = key_screens.map { |row| row["key_screen_id"].to_s }
      all_key_screen_ids.concat(key_screen_ids)
      errors << "#{scene_id} key screen ids must be unique" unless key_screen_ids.uniq.length == key_screen_ids.length

      key_screens.each do |key_screen|
        key_screen_id = key_screen["key_screen_id"].to_s
        key_screen_section_by_id[key_screen_id] = section_id
        bindings = Array(key_screen["reference_function_bindings"])
        bound_unit_ids = bindings.map { |row| row["reference_unit_id"].to_s }
        if bound_unit_ids.empty?
          errors << "#{key_screen_id} requires at least one named decision-ready reference-function binding"
        end
        bindings.each do |binding|
          ref_id = binding["reference_unit_id"].to_s
          function_id = binding["function_id"].to_s
          unit = units_by_id[ref_id]
          function_row = functions_by_id[function_id]
          if unit.nil?
            errors << "#{key_screen_id} names unknown reference unit #{ref_id}"
            next
          end
          unless Array(unit["target_section_ids"]).map(&:to_s).include?(section_id)
            errors << "#{key_screen_id} uses #{ref_id} outside its targeted section"
          end
          unless %w[applied combined].include?(unit["disposition"].to_s)
            errors << "#{key_screen_id} may use only applied or combined reference units: #{ref_id}"
          end
          if function_row.nil?
            errors << "#{key_screen_id} names unknown reference function #{function_id}"
            next
          end
          unless function_row["unit"]["reference_unit_id"].to_s == ref_id
            errors << "#{key_screen_id} function #{function_id} does not belong to #{ref_id}"
          end
          function = function_row["function"]
          unless function["purpose"].to_s == binding["purpose"].to_s
            errors << "#{key_screen_id} function #{function_id} purpose differs from its analysis"
          end
          unless Array(function["downstream_targets"]).map(&:to_s).include?("front_planning_key_screen")
            errors << "#{key_screen_id} function #{function_id} is not cleared for Front Planning Key Screens"
          end
        end

        visual_application = key_screen["visual_identity_application"].to_h
        visible_key_members = Array(visual_application["visible_member_ids"]).map(&:to_s)
        key_member_assets = Array(visual_application["member_visual_asset_ids"]).map(&:to_s)
        unknown_key_assets = key_member_assets.uniq - asset_ids
        errors << "#{key_screen_id} names unknown current-title assets: #{unknown_key_assets.join(', ')}" unless unknown_key_assets.empty?
        key_member_assets.each do |asset_id|
          asset = assets_by_id[asset_id]
          next unless asset
          errors << "#{key_screen_id} uses a non-authorized member visual asset" unless asset["status"].to_s == "authorized"
          unless %w[member_visual_anchor unit_or_group_visual_anchor].include?(asset["asset_type"].to_s)
            errors << "#{key_screen_id} member_visual_asset_ids contains a non-member visual asset"
          end
        end
        uncovered_key_members = visible_key_members.reject do |member_id|
          key_member_assets.any? do |asset_id|
            Array(assets_by_id.dig(asset_id, "member_ids")).map(&:to_s).include?(member_id)
          end
        end
        errors << "#{key_screen_id} lacks current-title member visual coverage for #{uncovered_key_members.join(', ')}" unless uncovered_key_members.empty?
      end

      key_review = scene["director_key_screen_quality_review"].to_h
      reviewed_key_screen_ids = Array(key_review["reviewed_ids"]).map(&:to_s)
      unknown_reviewed_keys = reviewed_key_screen_ids - key_screen_ids
      errors << "#{scene_id} director Key Screen review names unknown anchors: #{unknown_reviewed_keys.join(', ')}" unless unknown_reviewed_keys.empty?

      if section["status"] == "passed" || document["status"] == "passed"
        errors << "#{scene_id} requires director Major quality PASS before section PASS" unless major_quality["decision"].to_s == "pass"
        errors << "#{scene_id} requires at least one passed Major visual input row" unless evidence.any? { |row| row["status"].to_s == "passed" }
        unless reviewed_evidence_ids.sort == evidence_ids.sort
          errors << "#{scene_id} director Major PASS must review the complete Major Scene and every visual input in that review unit"
        end
        if member_ids.any? && !evidence.any? { |row| %w[current_title_member_key_visual major_scene_member_visual_test].include?(row["evidence_kind"].to_s) }
          errors << "#{scene_id} requires member identity and appearance evidence in the same Major review unit"
        end
        errors << "#{scene_id} requires director Key Screen quality PASS before section PASS" unless key_review["decision"].to_s == "pass"
        unless reviewed_key_screen_ids.sort == key_screen_ids.sort
          errors << "#{scene_id} director Key Screen PASS must review every current anchor"
        end
        errors << "#{scene_id} has unresolved Key Screen coverage jobs" unless Array(scene["uncovered_key_screen_jobs"]).empty?
        errors << "#{scene_id} requires every Key Screen anchor director-passed" unless key_screens.all? { |row| row["status"].to_s == "director_passed" }
      end
    end
  end
  errors << "key screen ids must be globally unique" unless all_key_screen_ids.uniq.length == all_key_screen_ids.length
  validate_v17_creative_graph(document, root, section_ids, sequence_units_by_id, errors)

  alignment = document["founder_visual_alignment"].to_h
  alignment_phase = alignment["review_phase"].to_s
  alignment_source_ids = Array(alignment["source_reference_unit_ids"]).map(&:to_s)
  errors << "Founder visual alignment source_reference_unit_ids must be unique" unless alignment_source_ids.uniq.length == alignment_source_ids.length
  unknown_alignment_sources = alignment_source_ids - unit_ids
  unless unknown_alignment_sources.empty?
    errors << "Founder visual alignment names unknown reference units: #{unknown_alignment_sources.join(', ')}"
  end
  inactive_alignment_sources = alignment_source_ids.select do |reference_id|
    unit = units_by_id[reference_id]
    unit && !%w[applied combined].include?(unit["disposition"].to_s)
  end
  unless inactive_alignment_sources.empty?
    errors << "Founder visual alignment may use only applied or combined reference units: #{inactive_alignment_sources.join(', ')}"
  end

  section_readouts = Array(alignment["section_readouts"])
  section_readout_ids = section_readouts.map { |row| row["section_id"].to_s }
  errors << "Founder visual alignment section readout ids must be unique" unless section_readout_ids.uniq.length == section_readout_ids.length
  if %w[direction_alignment fp_close].include?(alignment_phase) && section_readout_ids.sort != section_ids.sort
    errors << "#{alignment_phase} Founder visual alignment must exact-cover every Front Planning section"
  end
  section_by_id = sections.to_h { |row| [row["section_id"].to_s, row] }
  section_readouts.each do |readout|
    section_id = readout["section_id"].to_s
    section = section_by_id[section_id]
    errors << "Founder visual alignment section readout names unknown section #{section_id}" if section.nil?
    if section && readout["primary_audio_cue"].to_s != section["primary_audio_cue"].to_s
      errors << "Founder visual alignment #{section_id} primary_audio_cue must exact-copy section_plan"
    end
  end

  reference_contributions = Array(alignment.dig("whole_film_readout", "reference_combination_logic")) +
    section_readouts.flat_map { |row| Array(row["reference_contributions"]) } +
    Array(alignment["planning_cut_readouts"]).flat_map { |row| Array(row["reference_contributions"]) }
  reference_contributions.each do |contribution|
    reference_id = contribution["reference_unit_id"].to_s
    unless alignment_source_ids.include?(reference_id)
      errors << "Founder visual alignment contribution #{reference_id} is outside source_reference_unit_ids"
      next
    end
    unit = units_by_id[reference_id]
    if unit && contribution["selected_locator"].to_s != unit["selected_locator"].to_s
      errors << "Founder visual alignment contribution #{reference_id} must exact-copy the selected reference locator"
    end
  end

  planning_cut_readouts = Array(alignment["planning_cut_readouts"])
  planning_cut_ids = planning_cut_readouts.map { |row| row["planning_cut_id"].to_s }
  source_key_screen_ids = planning_cut_readouts.map { |row| row["source_key_screen_id"].to_s }
  errors << "Founder visual alignment planning_cut_id values must be unique" unless planning_cut_ids.uniq.length == planning_cut_ids.length
  errors << "Founder visual alignment source_key_screen_id values must be unique" unless source_key_screen_ids.uniq.length == source_key_screen_ids.length
  if alignment_phase == "fp_close" && source_key_screen_ids.sort != all_key_screen_ids.sort
    errors << "FP Close Founder visual alignment must exact-cover every current Key Screen as one planning-cut readout"
  end
  planning_cut_readouts.group_by { |row| row["section_id"].to_s }.each do |section_id, rows|
    orders = rows.map { |row| row["sequence_order"].to_i }
    errors << "Founder visual alignment #{section_id} planning-cut sequence_order values must be unique" unless orders.uniq.length == orders.length
  end
  planning_cut_readouts.each do |readout|
    key_screen_id = readout["source_key_screen_id"].to_s
    expected_section_id = key_screen_section_by_id[key_screen_id]
    if expected_section_id.nil?
      errors << "Founder visual alignment planning cut names unknown Key Screen #{key_screen_id}"
    elsif readout["section_id"].to_s != expected_section_id
      errors << "Founder visual alignment #{readout['planning_cut_id']} section_id differs from its source Key Screen"
    end
  end
  if document["status"] == "direction_aligned" && alignment_phase != "direction_alignment"
    errors << "direction-aligned Front Planning requires Direction Alignment storyline detail"
  end
  if document["status"] == "director_closed" && alignment_phase != "fp_close"
    errors << "Director-closed Front Planning requires FP Close storyline detail"
  end
  if sequence_control_valid && projected_control_major_ids != control_major_ids
    errors << "Front Planning Major Scenes must project every director-ready control Major exactly once and in proposed order"
  end

  if %w[direction_aligned director_closed].include?(document["status"].to_s)
    errors << "aligned or Director-closed Front Planning requires Founder Direction Alignment PASS" unless document.dig("founder_gate", "decision") == "pass"
  end
  if document["status"] == "direction_aligned"
    errors << "Direction Alignment requires every section direction-aligned" unless sections.all? { |section| section["status"] == "direction_aligned" }
  end
  if document["status"] == "director_closed"
    errors << "Director-closed Front Planning requires every section Director-passed" unless sections.all? { |section| section["status"] == "director_passed" }
  end
end

errors = errors.uniq
errors = errors.first(options[:max_errors]) if options[:max_errors].to_i.positive?
result = {"valid" => errors.empty?, "schema_version" => document["schema_version"], "errors" => errors}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: Front Planning v17 exact-preserves PRE-00 while closing FP-A/B/C, selected-route storyline binding, one-second Sequence Runs, MJxx/Core Slot references, Hero proof, screen progression, and production scope for 01/02A"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
