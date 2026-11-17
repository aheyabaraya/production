#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "time"
require "yaml"
require_relative "lib/idol_storyline_density_locator_contract"

TOOL_ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = TOOL_ROOT.join("scripts", "idol-video-python")
VALIDATOR = TOOL_ROOT.join("scripts", "validate_json_schema.py")
RADAR_SCHEMA = TOOL_ROOT.join("schemas", "pre-00-research-radar.schema.json")
HANDOFF_SCHEMA = TOOL_ROOT.join("schemas", "pre-00-selection-handoff.schema.json")

options = {
  root: Pathname.new(__dir__).join("..").expand_path,
  created_at: nil,
  inspect: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_pre00_selection_handoff.rb (--radar PATH --run RUN --output PATH | --inspect PATH --run RUN) [--created-at ISO8601] [--root PATH]"
  parser.on("--radar PATH", "Selected PRE-00 radar path, relative to root.") { |value| options[:radar] = value }
  parser.on("--run RUN", "Canonical IDOL run root.") { |value| options[:run] = value }
  parser.on("--output PATH", "Handoff output path, relative to root.") { |value| options[:output] = value }
  parser.on("--inspect PATH", "Validate and read one stable PRE-00 handoff without mutation.") { |value| options[:inspect] = value }
  parser.on("--created-at ISO8601", "Explicit receipt timestamp.") { |value| options[:created_at] = value }
  parser.on("--root PATH", "Repository root for validation/testing.") { |value| options[:root] = Pathname.new(value).expand_path }
end.parse!

def abort_with(message)
  warn("PRE-00 selection handoff: HOLD: #{message}")
  exit(1)
end

def canonical_json(value)
  case value
  when Hash
    "{" + value.keys.map(&:to_s).sort.map do |key|
      source_key = value.key?(key) ? key : key.to_sym
      JSON.generate(key) + ":" + canonical_json(value[source_key])
    end.join(",") + "}"
  when Array
    "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
  else
    JSON.generate(value)
  end
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: TOOL_ROOT.to_s
  )
  abort_with("#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}") unless status.success?
end

def value_sha(value)
  Digest::SHA256.hexdigest(canonical_json(value))
end

def binding(pointer, value)
  copied_value = JSON.parse(JSON.generate(value))
  {
    "source_pointer" => pointer,
    "value" => copied_value,
    "value_sha256" => value_sha(value)
  }
end

def validate_reference_audience_lineage(primary_target)
  abort_with("primary_target is missing") unless primary_target.is_a?(Hash)
  lineage = primary_target["reference_audience_lineage"]
  abort_with("reference_audience_lineage is missing") unless lineage.is_a?(Hash)
  main = lineage["main_reference_song"]
  scenes = Array(lineage["scene_reference_audiences"])
  intersection = lineage["intersection_decision"]
  abort_with("main_reference_song is missing") unless main.is_a?(Hash)
  abort_with("intersection_decision is missing") unless intersection.is_a?(Hash)

  main_id = main["source_ref_id"].to_s
  unless intersection["base_source_ref_id"].to_s == main_id
    abort_with("reference-audience intersection base does not match the main song")
  end

  selected_scene_ids = scenes.select { |row| row.is_a?(Hash) && row["selected_for_intersection"] == true }
                             .map { |row| row["source_ref_id"].to_s }
  declared_scene_ids = Array(intersection["selected_scene_source_ref_ids"]).map(&:to_s)
  abort_with("reference-audience intersection has duplicate selected scene ids") unless declared_scene_ids.uniq == declared_scene_ids
  unless selected_scene_ids.sort == declared_scene_ids.sort
    abort_with("reference-audience intersection ids do not match selected scene profiles")
  end
end

def validate_storyline_lineage(storyline, radar, selected_route_ids)
  abort_with("storyline_lineage is missing") unless storyline.is_a?(Hash)
  original = storyline["pre00_storyline_original"]
  revisions = Array(storyline["pre00_storyline_revisions"])
  abort_with("pre00_storyline_original is missing") unless original.is_a?(Hash)
  abort_with("PRE-00 storyline original must remain V001") unless original["version_id"].to_s == "PRE00_STORYLINE_V001"
  abort_with("PRE-00 storyline original cannot have a parent") unless original["parent_version_id"].nil? && original["parent_full_storyline_text_sha256"].nil?

  versions = [original] + revisions
  versions.each_with_index do |version, index|
    label = version["version_id"].to_s
    expected_id = format("PRE00_STORYLINE_V%03d", index + 1)
    abort_with("storyline versions must be append-only and sequential: expected #{expected_id}") unless label == expected_id
    text = version["full_storyline_text"].to_s
    text_sha = Digest::SHA256.hexdigest(text)
    abort_with("#{label} full storyline text SHA-256 is stale") unless version["full_storyline_text_sha256"].to_s == text_sha

    if index.positive?
      parent = versions.fetch(index - 1)
      abort_with("#{label} parent version is not the immediately preceding preserved version") unless version["parent_version_id"].to_s == parent["version_id"].to_s
      unless version["parent_full_storyline_text_sha256"].to_s == parent["full_storyline_text_sha256"].to_s
        abort_with("#{label} parent storyline hash is stale")
      end
    end

    binding_ids = Array(version["reference_bindings"]).map.with_index do |row, binding_index|
      binding_label = "#{label} reference_bindings[#{binding_index}]"
      abort_with("#{binding_label} must be an object") unless row.is_a?(Hash)
      source_ref_id = row["source_ref_id"].to_s
      pointer = row["source_json_pointer"].to_s
      abort_with("#{binding_label} pointer does not identify its source_ref_id") unless pointer == "/research_inputs/#{source_ref_id}"
      source_value = pointer_value(radar, pointer, binding_label)
      unless canonical_json(row["source_snapshot"]) == canonical_json(source_value)
        abort_with("#{binding_label} source snapshot differs from the current radar")
      end
      abort_with("#{binding_label} source value SHA-256 is stale") unless row["source_value_sha256"].to_s == value_sha(source_value)
      source_ref_id
    end
    abort_with("#{label} has duplicate storyline reference bindings") unless binding_ids.uniq == binding_ids
  end

  active = storyline["active_version"]
  abort_with("storyline active_version is missing") unless active.is_a?(Hash)
  active_index = versions.index { |version| version["version_id"].to_s == active["version_id"].to_s }
  abort_with("storyline active_version does not resolve to a preserved full-text version") unless active_index
  active_version = versions.fetch(active_index)
  expected_pointer = active_index.zero? ? "/storyline_lineage/pre00_storyline_original" : "/storyline_lineage/pre00_storyline_revisions/#{active_index - 1}"
  abort_with("storyline active_version pointer is stale") unless active["version_json_pointer"].to_s == expected_pointer
  unless active["full_storyline_text_sha256"].to_s == active_version["full_storyline_text_sha256"].to_s
    abort_with("storyline active_version text hash is stale")
  end
  unless Array(active_version["selected_route_ids"]).map(&:to_s).sort == Array(selected_route_ids).map(&:to_s).sort
    abort_with("active storyline selected_route_ids differ from Founder selection")
  end

  density = storyline["contextual_density_review"]
  abort_with("storyline contextual_density_review is missing") unless density.is_a?(Hash)
  abort_with("selected storyline requires contextual density PASS") unless density["decision"].to_s == "pass"
  abort_with("density review version is stale") unless density["reviewed_version_id"].to_s == active_version["version_id"].to_s
  unless density["reviewed_full_storyline_text_sha256"].to_s == active_version["full_storyline_text_sha256"].to_s
    abort_with("density review storyline hash is stale")
  end
  unless %w[selected revised_by_founder].include?(active_version.dig("authorship_receipt", "founder_status").to_s)
    abort_with("active storyline full-text version is not Founder selected")
  end
  JSON.parse(JSON.generate(storyline))
end

def inside_root(root, relative, label)
  abort_with("#{label} must be repository-relative") if relative.to_s.empty? || Pathname.new(relative).absolute?
  path = root.join(relative).cleanpath
  begin
    resolved_relative = path.relative_path_from(root.cleanpath).to_s
    abort_with("#{label} escapes repository root") if resolved_relative == ".." || resolved_relative.start_with?("../")
  rescue ArgumentError
    abort_with("#{label} escapes repository root")
  end
  path
end

def ensure_real_containment(path, root, label)
  real_root = root.realpath
  real_path = path.realpath
  relative = real_path.relative_path_from(real_root).to_s
  abort_with("#{label} crosses a symlink outside repository root") if relative == ".." || relative.start_with?("../")
rescue Errno::ENOENT, ArgumentError
  abort_with("#{label} cannot be resolved inside repository root")
end

def pointer_value(document, pointer, label)
  current = document
  pointer.to_s.split("/")[1..].to_a.each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    current = if current.is_a?(Array) && token.match?(/\A(?:0|[1-9]\d*)\z/)
                current.fetch(token.to_i) { abort_with("#{label} pointer is stale at #{token}") }
              elsif current.is_a?(Hash)
                current.fetch(token) { abort_with("#{label} pointer is stale at #{token}") }
              else
                abort_with("#{label} pointer traverses a scalar")
              end
  end
  current
end

def verified_binding_value(binding_value, radar, label, expected_pointer)
  abort_with("#{label} must be an exact-copy binding") unless binding_value.is_a?(Hash)
  pointer = binding_value["source_pointer"].to_s
  unless pointer == expected_pointer
    abort_with("#{label} does not identify its Founder-selected source: expected #{expected_pointer}")
  end
  value = pointer_value(radar, pointer, label)
  abort_with("#{label} copied value differs from the current radar") unless canonical_json(binding_value["value"]) == canonical_json(value)
  expected_sha = value_sha(value)
  abort_with("#{label} value SHA-256 is stale") unless binding_value["value_sha256"].to_s == expected_sha
  JSON.parse(JSON.generate(value))
end

root = options[:root]
run_rel = options[:run].to_s
unless run_rel.match?(%r{\Aruns/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9가-힣][a-z0-9가-힣-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}\z})
  abort_with("--run is not a canonical IDOL run root")
end

if options[:inspect]
  inspect_rel = options[:inspect].to_s
  expected_rel = "#{run_rel}/research/pre00-selection-handoff-v1.yaml"
  abort_with("--inspect must name #{expected_rel}") unless inspect_rel == expected_rel
  handoff_path = inside_root(root, inspect_rel, "handoff path")
  abort_with("handoff does not exist: #{inspect_rel}") unless handoff_path.file?
  ensure_real_containment(handoff_path, root, "handoff path")
  validate_schema(HANDOFF_SCHEMA, handoff_path, "PRE-00 selection handoff")
  handoff_text = handoff_path.binread
  handoff = YAML.safe_load(handoff_text, aliases: true)
  abort_with("handoff root must be an object") unless handoff.is_a?(Hash)
  abort_with("handoff belongs to another run") unless handoff["run"].to_s == run_rel

  radar_binding = handoff["source_radar"]
  abort_with("source_radar is missing") unless radar_binding.is_a?(Hash)
  radar_rel = radar_binding["path"].to_s
  radar_path = inside_root(root, radar_rel, "source radar path")
  abort_with("source radar does not exist: #{radar_rel}") unless radar_path.file?
  ensure_real_containment(radar_path, root, "source radar path")
  radar_text = radar_path.binread
  abort_with("source radar SHA-256 is stale") unless Digest::SHA256.hexdigest(radar_text) == radar_binding["sha256"].to_s
  validate_schema(RADAR_SCHEMA, radar_path, "selected PRE-00 radar")
  radar = YAML.safe_load(radar_text, aliases: true)
  abort_with("source radar root must be an object") unless radar.is_a?(Hash)
  abort_with("source radar is no longer selected") unless radar["status"].to_s == "selected"

  storyline_lineage = verified_binding_value(handoff["storyline_lineage"], radar, "storyline_lineage", "/storyline_lineage")
  migrated_context = %w[
    visual_reference_hierarchy
    audio_reference_hierarchy
    reference_transfer_exclusion_map
    audience_profiles
    x_reference_audience_envelope
    title_target_intersection
    message_progression
    emotional_progression
    sequence_runs
    fp_autonomy_envelope
    source_acquisition_authority
    planning_image_authority
    operating_observation
    fp_launch_lock
  ].to_h do |field|
    [field, verified_binding_value(handoff[field], radar, field, "/#{field}")]
  end
  selected_target = verified_binding_value(handoff["selected_target"], radar, "selected_target", "/target_trend_foundation/primary_target")
  founder_response = verified_binding_value(handoff["founder_response"], radar, "founder_response", "/founder_selection")
  connection_id = selected_target["selected_connection_id"].to_s
  connection_index = Array(radar.dig("target_trend_foundation", "connection_candidates")).index do |row|
    row.is_a?(Hash) && row["connection_id"].to_s == connection_id
  end
  abort_with("selected target connection does not resolve") unless connection_index
  connection_pointer = "/target_trend_foundation/connection_candidates/#{connection_index}"
  selected_connection = verified_binding_value(handoff["selected_connection"], radar, "selected_connection", connection_pointer)
  route_ids = Array(founder_response["route_ids"]).map(&:to_s)
  unless Array(handoff["selected_routes"]).length == route_ids.length
    abort_with("selected_routes count differs from the Founder-selected source")
  end
  selected_routes = Array(handoff["selected_routes"]).map.with_index do |row, index|
    route_index = Array(radar["candidate_routes"]).index do |candidate|
      candidate.is_a?(Hash) && candidate["route_id"].to_s == route_ids.fetch(index)
    end
    abort_with("selected route does not resolve: #{route_ids.fetch(index)}") unless route_index
    verified_binding_value(row, radar, "selected_routes[#{index}]", "/candidate_routes/#{route_index}")
  end
  reference_preview = verified_binding_value(handoff["reference_preview"], radar, "reference_preview", "#{connection_pointer}/reference_preview")
  must_and_avoid_pointers = {
    "content_contract" => "/target_trend_foundation/content_contract",
    "attraction_triggers" => "/target_trend_foundation/primary_target/attraction_triggers",
    "rejection_triggers" => "/target_trend_foundation/primary_target/rejection_triggers",
    "do_not_serve" => "/target_trend_foundation/primary_target/do_not_serve",
    "trend_do_not_copy" => "/target_trend_foundation/trend_synthesis/do_not_copy"
  }
  must_and_avoid = handoff.fetch("must_and_avoid").each_with_object({}) do |(key, row), result|
    result[key] = verified_binding_value(row, radar, "must_and_avoid.#{key}", must_and_avoid_pointers.fetch(key))
  end
  validate_storyline_lineage(storyline_lineage, radar, route_ids)
  payload_without_hash = Marshal.load(Marshal.dump(handoff))
  payload_without_hash.fetch("integrity").delete("handoff_payload_sha256")
  unless handoff.dig("integrity", "handoff_payload_sha256").to_s == value_sha(payload_without_hash)
    abort_with("handoff payload SHA-256 is stale")
  end

  puts(JSON.generate({
    "available" => true,
    "path" => inspect_rel,
    "sha256" => Digest::SHA256.hexdigest(handoff_text),
    "handoffId" => handoff["handoff_id"],
    "context" => {
      "storylineLineage" => storyline_lineage,
      "selectedTarget" => selected_target,
      "visualReferenceHierarchy" => migrated_context.fetch("visual_reference_hierarchy"),
      "audioReferenceHierarchy" => migrated_context.fetch("audio_reference_hierarchy"),
      "referenceTransferExclusionMap" => migrated_context.fetch("reference_transfer_exclusion_map"),
      "audienceProfiles" => migrated_context.fetch("audience_profiles"),
      "xReferenceAudienceEnvelope" => migrated_context.fetch("x_reference_audience_envelope"),
      "titleTargetIntersection" => migrated_context.fetch("title_target_intersection"),
      "messageProgression" => migrated_context.fetch("message_progression"),
      "emotionalProgression" => migrated_context.fetch("emotional_progression"),
      "sequenceRuns" => migrated_context.fetch("sequence_runs"),
      "fpAutonomyEnvelope" => migrated_context.fetch("fp_autonomy_envelope"),
      "sourceAcquisitionAuthority" => migrated_context.fetch("source_acquisition_authority"),
      "planningImageAuthority" => migrated_context.fetch("planning_image_authority"),
      "operatingObservation" => migrated_context.fetch("operating_observation"),
      "fpLaunchLock" => migrated_context.fetch("fp_launch_lock"),
      "selectedConnection" => selected_connection,
      "selectedRoutes" => selected_routes,
      "referencePreview" => reference_preview,
      "founderResponse" => founder_response,
      "mustAndAvoid" => must_and_avoid,
      "startup" => handoff["startup"],
      "authorityBoundary" => handoff["authority_boundary"]
    }
  }))
  exit(0)
end

radar_rel = options[:radar].to_s
output_rel = options[:output].to_s
abort_with("--radar is required") if radar_rel.empty?
abort_with("--run is required") if run_rel.empty?
abort_with("--output is required") if output_rel.empty?
unless output_rel == "#{run_rel}/research/pre00-selection-handoff-v1.yaml"
  abort_with("--output must use RUN/research/pre00-selection-handoff-v1.yaml")
end

radar_path = inside_root(root, radar_rel, "radar path")
output_path = inside_root(root, output_rel, "output path")
abort_with("radar does not exist: #{radar_rel}") unless radar_path.file?
abort_with("output already exists: #{output_rel}") if output_path.exist?
ensure_real_containment(radar_path, root, "radar path")
validate_schema(RADAR_SCHEMA, radar_path, "selected PRE-00 radar")

radar_text = radar_path.binread
radar = YAML.safe_load(radar_text, aliases: true)
abort_with("radar root must be an object") unless radar.is_a?(Hash)
abort_with("radar schema_version must be 1.8") unless radar["schema_version"].to_s == "1.8"
abort_with("radar status must be selected") unless radar["status"].to_s == "selected"
foundation = radar["target_trend_foundation"]
selection = radar["founder_selection"]
abort_with("target_trend_foundation is missing") unless foundation.is_a?(Hash)
abort_with("target must be Founder-locked") unless foundation["lock_status"].to_s == "founder_locked"
abort_with("founder_selection is missing") unless selection.is_a?(Hash)
unless %w[select_one combine_routes].include?(selection["action"].to_s)
  abort_with("founder_selection action must select or combine routes")
end

primary_target = foundation["primary_target"]
validate_reference_audience_lineage(primary_target)
launch_lock = radar["fp_launch_lock"].to_h
abort_with("FP Launch Lock must be locked") unless launch_lock["status"].to_s == "locked"
abort_with("FP Launch Lock requires verified current-run target evidence") unless launch_lock["target_evidence_status"].to_s == "verified_current_run"
abort_with("FP Launch Lock cannot use timing as a gate") unless launch_lock["timing_used_as_gate"] == false
abort_with("operating timing is diagnostic only") unless radar.dig("operating_observation", "timing_is_gate") == false
active_storyline = radar.dig("storyline_lineage", "active_version").to_h
unless launch_lock["active_storyline_version_id"].to_s == active_storyline["version_id"].to_s &&
       launch_lock["active_storyline_sha256"].to_s == active_storyline["full_storyline_text_sha256"].to_s
  abort_with("FP Launch Lock active storyline binding is stale")
end
connection_id = primary_target.is_a?(Hash) ? primary_target["selected_connection_id"].to_s : ""
connections = Array(foundation["connection_candidates"])
connection_index = connections.index { |row| row.is_a?(Hash) && row["connection_id"].to_s == connection_id }
abort_with("selected target connection does not resolve") unless connection_index
selected_connection = connections.fetch(connection_index)

routes = Array(radar["candidate_routes"])
route_ids = Array(selection["route_ids"]).map(&:to_s)
abort_with("founder_selection route_ids are empty") if route_ids.empty?
selected_routes = route_ids.map do |route_id|
  index = routes.index { |row| row.is_a?(Hash) && row["route_id"].to_s == route_id }
  abort_with("selected route does not resolve: #{route_id}") unless index
  [index, routes.fetch(index)]
end
storyline_lineage = validate_storyline_lineage(radar["storyline_lineage"], radar, route_ids)
locator_errors = IdolStorylineDensityLocatorContract.close_artifact(
  root,
  radar_path,
  document: radar,
  stage: "pre00"
)
abort_with(locator_errors.first) unless locator_errors.empty?

created_at = options[:created_at] || Time.now.utc.iso8601
begin
  Time.iso8601(created_at)
rescue ArgumentError
  abort_with("--created-at must be ISO8601")
end

run_id = run_rel.split("/").last.upcase.gsub(/[^A-Z0-9_-]/, "_")
radar_id = radar["radar_id"].to_s
document = {
  "schema_version" => "idol-pre00-selection-handoff.v4",
  "artifact_type" => "pre00_founder_selection_handoff",
  "handoff_id" => "PRE00_HANDOFF_#{radar_id}_#{run_id}",
  "run" => run_rel,
  "created_at" => created_at,
  "source_radar" => {
    "path" => radar_rel,
    "sha256" => Digest::SHA256.hexdigest(radar_text),
    "schema_version" => radar["schema_version"].to_s,
    "radar_id" => radar_id,
    "status" => radar["status"].to_s
  },
  "storyline_lineage" => binding("/storyline_lineage", storyline_lineage),
  "visual_reference_hierarchy" => binding("/visual_reference_hierarchy", radar["visual_reference_hierarchy"]),
  "audio_reference_hierarchy" => binding("/audio_reference_hierarchy", radar["audio_reference_hierarchy"]),
  "reference_transfer_exclusion_map" => binding("/reference_transfer_exclusion_map", radar["reference_transfer_exclusion_map"]),
  "audience_profiles" => binding("/audience_profiles", radar["audience_profiles"]),
  "x_reference_audience_envelope" => binding("/x_reference_audience_envelope", radar["x_reference_audience_envelope"]),
  "title_target_intersection" => binding("/title_target_intersection", radar["title_target_intersection"]),
  "message_progression" => binding("/message_progression", radar["message_progression"]),
  "emotional_progression" => binding("/emotional_progression", radar["emotional_progression"]),
  "sequence_runs" => binding("/sequence_runs", radar["sequence_runs"]),
  "fp_autonomy_envelope" => binding("/fp_autonomy_envelope", radar["fp_autonomy_envelope"]),
  "source_acquisition_authority" => binding("/source_acquisition_authority", radar["source_acquisition_authority"]),
  "planning_image_authority" => binding("/planning_image_authority", radar["planning_image_authority"]),
  "operating_observation" => binding("/operating_observation", radar["operating_observation"]),
  "fp_launch_lock" => binding("/fp_launch_lock", radar["fp_launch_lock"]),
  "selected_target" => binding("/target_trend_foundation/primary_target", primary_target),
  "selected_connection" => binding("/target_trend_foundation/connection_candidates/#{connection_index}", selected_connection),
  "selected_routes" => selected_routes.map { |index, route| binding("/candidate_routes/#{index}", route) },
  "reference_preview" => binding("/target_trend_foundation/connection_candidates/#{connection_index}/reference_preview", selected_connection["reference_preview"]),
  "founder_response" => binding("/founder_selection", selection),
  "must_and_avoid" => {
    "content_contract" => binding("/target_trend_foundation/content_contract", foundation["content_contract"]),
    "attraction_triggers" => binding("/target_trend_foundation/primary_target/attraction_triggers", primary_target["attraction_triggers"]),
    "rejection_triggers" => binding("/target_trend_foundation/primary_target/rejection_triggers", primary_target["rejection_triggers"]),
    "do_not_serve" => binding("/target_trend_foundation/primary_target/do_not_serve", primary_target["do_not_serve"]),
    "trend_do_not_copy" => binding("/target_trend_foundation/trend_synthesis/do_not_copy", foundation.dig("trend_synthesis", "do_not_copy"))
  },
  "startup" => {
    "song_room" => {
      "action" => "open_existing_song_room_context",
      "session_route" => "cdd_physical_song_room",
      "created_by" => "creative_development_director",
      "reports_to" => "creative_development_director",
      "context_source" => "this_hash_bound_handoff",
      "duplicate_founder_brief_forbidden" => true,
      "model_turn_at_handoff" => false
    },
    "visual_preparation" => {
      "action" => "start_asynchronous_cdd_preparation_context",
      "owner" => "creative_development_director",
      "allowed_scope" => ["reference_preview_preparation", "identity_gap_check", "visual_research_question_preparation"],
      "returns_to" => "creative_development_director",
      "context_source" => "this_hash_bound_handoff",
      "parallel_with_song_conversation" => true,
      "external_or_paid_generation_allowed" => false
    }
  },
  "authority_boundary" => {
    "new_stage_created" => false,
    "stage_order_changed" => false,
    "creative_lock_scope" => "selected_pre00_target_storyline_reference_hierarchies_and_fp_launch_values_only",
    "paid_generation_authorized" => false,
    "external_action_authorized" => false,
    "downstream_truth_authorized" => false
  },
  "integrity" => {
    "copy_policy" => "exact_copy_from_source_json_pointer_no_creative_defaults",
    "consumer_start_order" => ["song_room_context", "visual_preparation_context"],
    "storyline_consumer_chain" => ["song_room_context", "front_planning", "section_01", "section_02a", "section_02b", "section_03v", "section_04"],
    "storyline_preservation_rule" => "exact_copy_original_active_full_text_revision_history_density_review_and_reference_bindings_no_summary_substitution",
    "handoff_payload_sha256" => ""
  }
}
payload_without_hash = Marshal.load(Marshal.dump(document))
payload_without_hash["integrity"].delete("handoff_payload_sha256")
document["integrity"]["handoff_payload_sha256"] = value_sha(payload_without_hash)

output_path.dirname.mkpath
ensure_real_containment(output_path.dirname, root, "output directory")
Tempfile.create(["pre00-selection-handoff-", ".yaml"], output_path.dirname.to_s) do |temporary|
  temporary.binmode
  temporary.write(YAML.dump(document))
  temporary.flush
  temporary.fsync
  validate_schema(HANDOFF_SCHEMA, Pathname.new(temporary.path), "PRE-00 selection handoff")
  begin
    File.link(temporary.path, output_path.to_s)
  rescue Errno::EEXIST
    abort_with("output already exists: #{output_rel}")
  end
end
puts(JSON.generate({
  "status" => "pass",
  "handoff" => output_rel,
  "sha256" => Digest::SHA256.file(output_path).hexdigest,
  "song_room_context" => "prepared",
  "visual_preparation_context" => "prepared",
  "model_turns_started" => 0,
  "external_or_paid_generation_authorized" => false
}))
