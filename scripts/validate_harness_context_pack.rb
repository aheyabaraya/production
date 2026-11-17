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
require_relative "lib/idol_run_layout"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "harness-context-pack.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {root: ROOT, json: false, max_errors: 30}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_harness_context_pack.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) do |value|
    raise OptionParser::InvalidArgument, "--max-errors must be zero or greater" if value.negative?
    options[:max_errors] = value
  end
end.parse!

pack_arg = ARGV.shift
abort "context pack path is required" if pack_arg.to_s.empty? || !ARGV.empty?

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

def expected_core_cut_ref(core_cut, index)
  return nil unless core_cut
  {
    "core_cut_id" => core_cut["core_cut_id"],
    "json_pointer" => "/master_storyboard/#{index}",
    "value_sha256" => value_sha256(core_cut)
  }
end

def expected_branch_cut_ref(branch_cut, core_index, branch_index)
  return nil unless branch_cut
  {
    "branch_cut_id" => branch_cut["branch_cut_id"],
    "json_pointer" => "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}",
    "value_sha256" => value_sha256(branch_cut)
  }
end

def schema_errors(path)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  status.success? ? [] : ["JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}"]
end

root = options[:root].expand_path.cleanpath
pack_path = resolve_path(pack_arg, root)
errors = []
unless inside?(pack_path, root) && pack_path.file?
  errors << "context pack is missing or outside the repository"
end

pack = {}
if errors.empty?
  begin
    pack = load_mapping(pack_path)
  rescue JSON::ParserError, Psych::Exception, TypeError => e
    errors << "cannot parse context pack: #{e.message}"
  end
end
errors.concat(schema_errors(pack_path)) if pack_path.file?

if pack.any?
  errors << "only idol-harness-context-pack.v7 is active" unless pack["schema_version"].to_s == "idol-harness-context-pack.v7"
  run_path = resolve_path(pack["run"], root)
  layout_errors = IdolRunLayout.validate(run_path, repo_root: root)
  unless inside?(run_path, root) && run_path.directory? && layout_errors.empty?
    errors << "context pack run is missing or outside the active runs root"
    errors.concat(layout_errors)
  end
  snapshots = Array(pack["source_snapshot"])
  errors << "source snapshot roles/order are not active" unless snapshots.map { |row| row["role"].to_s } == %w[front_planning section_direction_01 storyboard_02a]
  source_docs = {}
  snapshots.each_with_index do |row, index|
    path = resolve_path(row["path"], root)
    if !inside?(path, root) || !path.file?
      errors << "source_snapshot[#{index}] is missing or outside the repository"
      next
    end
    actual = Digest::SHA256.file(path).hexdigest
    errors << "source_snapshot[#{index}] SHA-256 is stale" unless row["sha256"].to_s == actual
    source_docs[row["role"].to_s] = load_mapping(path)
    errors << "source_snapshot[#{index}] schema_version is stale" unless row["schema_version"].to_s == source_docs[row["role"].to_s]["schema_version"].to_s
  end

  storyboard = source_docs["storyboard_02a"]
  if storyboard
    errors << "storyboard source must use schema 3.0" unless storyboard["schema_version"].to_s == "3.0"
    errors << "content_id differs from source 02A" unless pack["content_id"].to_s == storyboard["content_id"].to_s
    front_snapshot = snapshots.find { |row| row["role"] == "front_planning" }.to_h
    direction_snapshot = snapshots.find { |row| row["role"] == "section_direction_01" }.to_h
    errors << "Front Planning source path differs from 02A owner" unless storyboard.dig("source_front_planning", "path").to_s == front_snapshot["path"].to_s
    errors << "01 source path differs from 02A owner" unless storyboard.dig("source_01_direction", "path").to_s == direction_snapshot["path"].to_s

    source_storyline_value = storyboard.dig("storyline_lineage_projection", "projected_value")
    storyline_projection = pack["storyline_lineage_projection"].to_h
    errors << "context storyline lineage pointer is not canonical" unless storyline_projection["source_json_pointer"].to_s == "/storyline_lineage_projection/projected_value"
    errors << "context storyline lineage hash is stale" unless storyline_projection["source_value_sha256"].to_s == value_sha256(source_storyline_value)
    unless canonical_value(storyline_projection["projected_value"]) == canonical_value(source_storyline_value)
      errors << "context pack must exact-copy the complete PRE-00-rooted full-storyline lineage"
    end
    source_progression = source_docs["front_planning"].to_h["screen_progression_map"]
    progression = pack["screen_progression_projection"].to_h
    errors << "context screen progression pointer is not canonical" unless progression["source_json_pointer"] == "/screen_progression_map"
    errors << "context screen progression hash is stale" unless progression["source_value_sha256"] == value_sha256(source_progression)
    errors << "context pack must exact-copy screen_progression_map" unless canonical_value(progression["projected_value"]) == canonical_value(source_progression)
    provider = pack["provider_profile_snapshot"].to_h
    registry = resolve_path(provider["registry_path"], root)
    errors << "provider registry snapshot is stale" unless registry.file? && provider["registry_sha256"] == Digest::SHA256.file(registry).hexdigest
    errors << "context provider fallback must be forbidden" unless provider["fallback_policy"] == "forbidden"
    if registry.file?
      registry_document = load_mapping(registry)
      worker_providers = registry_document.dig("logical_profiles", "worker_high", "providers").to_h
      task_owner = pack.dig("task", "owner").to_s
      if %w[grok cursor].include?(task_owner)
        expected_provider = worker_providers[task_owner].to_h
        expected_profile_id = expected_provider["provider_profile_id"].to_s
        expected_source = expected_provider["source_path"].to_s
        expected_sha = expected_provider["source_sha256"].to_s
        expected_ref = "#{expected_source}#profiles/#{expected_profile_id}#sha256=#{expected_sha}"
      else
        errors << "context task owner is not a registered provider lane"
      end
      if %w[grok cursor].include?(task_owner)
        errors << "context logical profile must resolve worker_high" unless provider["logical_profile_alias"] == "worker_high"
        errors << "context execution profile differs from selected provider registry" unless provider["execution_profile_id"].to_s == expected_profile_id
        errors << "context resolved profile reference differs from selected provider registry" unless provider["resolved_profile_snapshot_ref"].to_s == expected_ref
        errors << "context provider capability snapshot differs from selected provider registry" unless provider["provider_capability_snapshot_sha256"].to_s == expected_sha
        source_path = resolve_path(expected_source, root)
        errors << "selected context provider source hash is stale" unless source_path.file? && Digest::SHA256.file(source_path).hexdigest == expected_sha
      end
    end
    active_storyline = storyline_projection.dig("projected_value", "active_version").to_h
    errors << "context active full storyline text hash is stale" unless active_storyline["full_storyline_text_sha256"].to_s == Digest::SHA256.hexdigest(active_storyline["full_storyline_text"].to_s)

    task = pack["task"].to_h
    section_id = Array(task["active_section_ids"]).first.to_s
    active_core_cut_id = task["active_core_cut_id"].to_s
    active_branch_cut_id = task["active_branch_cut_id"].to_s
    shard = Array(storyboard["section_shards"]).find { |row| Array(row["section_ids"]).map(&:to_s) == [section_id] }
    if shard.nil?
      errors << "active section has no source 02A shard"
    else
      all_core_cuts = Array(storyboard["master_storyboard"])
      section_core_cuts = Array(shard["core_cut_ids"]).map do |id|
        all_core_cuts.find { |core_cut| core_cut["core_cut_id"].to_s == id.to_s }
      end.compact
      core_position = section_core_cuts.index { |core_cut| core_cut["core_cut_id"].to_s == active_core_cut_id }
      if core_position.nil?
        errors << "active Core Cut does not belong to active section"
      else
        current_core_cut = section_core_cuts.fetch(core_position)
        errors << "active Core Cut imported_core.section_id differs from active section" unless current_core_cut.dig("imported_core", "section_id").to_s == section_id
        previous_core_cut = core_position.zero? ? nil : section_core_cuts.fetch(core_position - 1)
        next_core_cut = core_position == section_core_cuts.length - 1 ? nil : section_core_cuts.fetch(core_position + 1)
        current_core_index = all_core_cuts.index(current_core_cut)
        previous_core_index = previous_core_cut && all_core_cuts.index(previous_core_cut)
        next_core_index = next_core_cut && all_core_cuts.index(next_core_cut)
        branch_cuts = Array(current_core_cut.dig("compile_seed", "branch_cuts"))
        branch_position = branch_cuts.index { |branch_cut| branch_cut["branch_cut_id"].to_s == active_branch_cut_id }
        if branch_position.nil?
          errors << "active Branch Cut does not belong to active Core Cut"
        else
        current_branch_cut = branch_cuts.fetch(branch_position)
        previous_branch_cut = branch_position.zero? ? nil : branch_cuts.fetch(branch_position - 1)
        next_branch_cut = branch_position == branch_cuts.length - 1 ? nil : branch_cuts.fetch(branch_position + 1)
        active = pack["active_unit"].to_h
        errors << "active section assignment differs from 02A" unless canonical_value(active["section_assignment"]) == canonical_value(shard)
        expected_parent = Idol02AStoryboardContract.core_cut_context_projection(current_core_cut)
        expected_previous_core = previous_core_cut && Idol02AStoryboardContract.core_cut_context_projection(previous_core_cut)
        expected_next_core = next_core_cut && Idol02AStoryboardContract.core_cut_context_projection(next_core_cut)
        errors << "active parent Core Cut differs from 02A" unless canonical_value(active["parent_core_cut"]) == canonical_value(expected_parent)
        errors << "active current Branch Cut differs from 02A" unless canonical_value(active["current_branch_cut"]) == canonical_value(current_branch_cut)
        errors << "active previous Branch Cut is not the immediate sibling" unless canonical_value(active["previous_branch_cut"]) == canonical_value(previous_branch_cut)
        errors << "active next Branch Cut is not the immediate sibling" unless canonical_value(active["next_branch_cut"]) == canonical_value(next_branch_cut)
        errors << "active previous Core Cut is not the immediate same-section Core Cut" unless canonical_value(active["previous_core_cut"]) == canonical_value(expected_previous_core)
        errors << "active next Core Cut is not the immediate same-section Core Cut" unless canonical_value(active["next_core_cut"]) == canonical_value(expected_next_core)
        errors << "cross-section boundary detail must be absent" unless active["cross_section_boundary_detail"].nil?

        context_payload = Idol02AStoryboardContract.same_section_context_payload(
          storyboard,
          shard,
          section_core_cuts,
          core_position,
          current_branch_cut,
          branch_position
        )
        neighborhood = active["branch_neighborhood"].to_h
        expected_neighborhood = {
          "policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only",
          "section_id" => section_id,
          "parent_core_cut" => expected_core_cut_ref(current_core_cut, current_core_index),
          "current_branch_cut" => expected_branch_cut_ref(current_branch_cut, current_core_index, branch_position),
          "previous_branch_cut" => expected_branch_cut_ref(previous_branch_cut, current_core_index, branch_position - 1),
          "next_branch_cut" => expected_branch_cut_ref(next_branch_cut, current_core_index, branch_position + 1),
          "previous_core_cut" => expected_core_cut_ref(previous_core_cut, previous_core_index),
          "next_core_cut" => expected_core_cut_ref(next_core_cut, next_core_index),
          "section_entry_continuity" => previous_core_cut.nil? ? shard["transition_in"] : nil,
          "section_exit_continuity" => next_core_cut.nil? ? shard["transition_out"] : nil,
          "context_value_sha256" => value_sha256(context_payload)
        }
        errors << "Branch Cut neighborhood hash or ownership drifted" unless canonical_value(neighborhood) == canonical_value(expected_neighborhood)

        expected_visuals = []
        input = current_branch_cut["member_visual_compile_input"].to_h
        package_pairs = [[input["package_album_key"].to_s, input["package_title_key"].to_s]]
        Array(current_branch_cut["visual_reference_bindings"]).each do |binding|
          path = resolve_path(binding["actual_path"], root)
          actual = path.file? ? Digest::SHA256.file(path).hexdigest : nil
          errors << "#{binding['binding_id']} visual file is missing or stale" unless actual == binding["sha256"].to_s
          expected_visuals << {
            "binding_id" => binding["binding_id"],
            "asset_id" => binding["asset_id"],
            "actual_path" => path.relative_path_from(root).to_s,
            "sha256" => binding["sha256"],
            "reference_scope" => binding["reference_scope"],
            "reference_class" => binding["reference_class"],
            "order" => binding["order"],
            "target_branch_cut_ids" => [current_branch_cut["branch_cut_id"]],
            "preserve" => binding["preserve"],
            "discard" => binding["discard"]
          }
        end
        errors << "current Branch Cut visual bindings differ from 02A" unless canonical_value(active["current_branch_visual_bindings"]) == canonical_value(expected_visuals)
        package_pairs.uniq!
        errors << "current Branch Cut uses more than one title package" unless package_pairs.length == 1
        if package_pairs.length == 1
          album_key, title_key = package_pairs.first
          package = active["current_title_package"].to_h
          errors << "current title package keys drifted" unless package["album_key"].to_s == album_key && package["title_key"].to_s == title_key
          expected_member_ids = expected_visuals.map { |row| row["asset_id"] if row["reference_scope"] == "member_visual" }.compact.uniq
          errors << "current title member visual ids drifted" unless Array(package["member_visual_asset_ids"]).map(&:to_s) == expected_member_ids
          expected_visuals.each do |row|
            visual_path = resolve_path(row["actual_path"], root)
            admission_error = Idol02AStoryboardContract.visual_source_admission_error(
              path: visual_path,
              root: root,
              run_path: run_path,
              album_key: album_key,
              title_key: title_key,
              label: "#{row['binding_id']} visual source"
            )
            errors << admission_error if admission_error
            next unless row["reference_scope"] == "member_visual"
            prefix = root.join("assets", "members", "album-assets", album_key, title_key).to_s
            unless Idol02AStoryboardContract.inside_real_root?(visual_path, prefix)
              errors << "#{row['binding_id']} member visual is outside current-title package"
            end
          end
        end
        end
      end
    end

    projection = {
      "target_message_summary" => storyboard["target_message_summary"],
      "whole_film_spine" => storyboard["whole_film_spine"],
      "output_intent" => storyboard["output_intent"],
      "branch_subject_mix_policy" => storyboard["branch_subject_mix_policy"],
      "summary_boundary" => "compact_index_only_never_a_substitute_for_storyline_lineage_projection"
    }
    planning = pack["planning_spine"].to_h
    errors << "planning spine differs from 02A" unless canonical_value(planning.reject { |key, _| key == "projection_sha256" }) == canonical_value(projection)
    errors << "planning spine digest is stale" unless planning["projection_sha256"].to_s == value_sha256(projection)
  end

  digest_payload = pack.reject { |key, _| key == "handoff_digest" }
  errors << "handoff_digest is stale" unless pack["handoff_digest"].to_s == value_sha256(digest_payload)
end

errors = errors.uniq.first(options[:max_errors]) if options[:max_errors].positive?
result = {
  "valid" => errors.empty?,
  "schema_version" => pack["schema_version"],
  "section_id" => pack.dig("active_unit", "section_id"),
  "core_cut_id" => pack.dig("task", "active_core_cut_id"),
  "branch_cut_id" => pack.dig("task", "active_branch_cut_id"),
  "errors" => errors
}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: bounded image-prompt context reads the complete PRE-00-rooted full-storyline lineage first, then only the current Branch Cut, its parent and siblings, and immediate same-section Core Cut neighbors"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
