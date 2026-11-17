#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"
require_relative "lib/idol_run_layout"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "harness-context-pack.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {
  run: nil,
  storyboard: nil,
  section_id: nil,
  core_cut_id: nil,
  branch_cut_id: nil,
  task: nil,
  owner: "grok",
  output: nil,
  write: false
}

OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_harness_context_pack.rb RUN_ROOT --section SXX --core-cut-id CXX_NAME --branch-cut-id BCXX_NAME --task TEXT [options]"
  opts.on("--run PATH") { |value| options[:run] = value }
  opts.on("--storyboard PATH", "Default: RUN_ROOT/02A-master-storyboard.yaml") { |value| options[:storyboard] = value }
  opts.on("--section ID") { |value| options[:section_id] = value }
  opts.on("--sections IDS", "Must contain exactly one section id") do |value|
    values = value.split(",").map(&:strip).reject(&:empty?)
    raise OptionParser::InvalidArgument, "--sections must contain exactly one id" unless values.length == 1
    options[:section_id] = values.first
  end
  opts.on("--core-cut-id ID") { |value| options[:core_cut_id] = value }
  opts.on("--branch-cut-id ID") { |value| options[:branch_cut_id] = value }
  opts.on("--task TEXT") { |value| options[:task] = value }
  opts.on("--owner OWNER", %w[grok cursor]) { |value| options[:owner] = value }
  opts.on("--output PATH") { |value| options[:output] = value }
  opts.on("--stage-id ID") do |value|
    raise OptionParser::InvalidArgument, "only image_prompt_compilation is active" unless value == "image_prompt_compilation"
  end
  opts.on("--context-profile PROFILE") do |value|
    raise OptionParser::InvalidArgument, "only image_prompt_section is active" unless value == "image_prompt_section"
  end
  opts.on("--write") { options[:write] = true }
end.parse!

class ContextError < StandardError; end

def resolve_repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(ROOT).to_s
  raise ContextError, "path escapes the IDOL repository: #{raw}" if relative == ".." || relative.start_with?("../")
  raise ContextError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise ContextError, "path escapes the IDOL repository: #{raw}"
end

def load_mapping(path, label)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise ContextError, "#{label} must be an object" unless value.is_a?(Hash)
  value
rescue JSON::ParserError, Psych::Exception => e
  raise ContextError, "cannot parse #{label}: #{e.message}"
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

def file_sha256(path)
  Digest::SHA256.file(path).hexdigest
end

def validate_schema(path)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?
  raise ContextError, "context pack failed schema validation: #{[stderr, stdout].join(' ').strip}"
end

def artifact_from_ref(ref, label)
  raise ContextError, "#{label} must be a path and SHA-256 object" unless ref.is_a?(Hash)
  path, relative = resolve_repo_path(ref["path"], must_exist: true)
  actual = file_sha256(path)
  document = load_mapping(path, label)
  [path, relative, actual, document]
end

def core_cut_ref(core_cut, index)
  return nil unless core_cut
  {
    "core_cut_id" => core_cut["core_cut_id"],
    "json_pointer" => "/master_storyboard/#{index}",
    "value_sha256" => value_sha256(core_cut)
  }
end

def branch_cut_ref(branch_cut, core_index, branch_index)
  return nil unless branch_cut
  {
    "branch_cut_id" => branch_cut["branch_cut_id"],
    "json_pointer" => "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}",
    "value_sha256" => value_sha256(branch_cut)
  }
end

def verify_visual_bindings(branch_cut, album_key, title_key, run_path)
  bindings = []
  Array(branch_cut["visual_reference_bindings"]).each do |binding|
    path, relative = resolve_repo_path(binding["actual_path"], must_exist: true)
    actual = file_sha256(path)
    raise ContextError, "#{binding['binding_id']} visual SHA-256 is stale" unless binding["sha256"].to_s == actual
    admission_error = Idol02AStoryboardContract.visual_source_admission_error(
      path: path,
      root: ROOT,
      run_path: run_path,
      album_key: album_key,
      title_key: title_key,
      label: "#{binding['binding_id']} visual source"
    )
    raise ContextError, admission_error if admission_error
    if relative.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
      raise ContextError, "#{binding['binding_id']} uses the prohibited face-only lane"
    end
    if binding["reference_scope"].to_s == "member_visual"
      package_root = ROOT.join("assets", "members", "album-assets", album_key, title_key)
      unless Idol02AStoryboardContract.inside_real_root?(path, package_root)
        raise ContextError, "#{binding['binding_id']} is outside the current-title package"
      end
    end
    bindings << {
      "binding_id" => binding["binding_id"],
      "asset_id" => binding["asset_id"],
      "actual_path" => relative,
      "sha256" => actual,
      "reference_scope" => binding["reference_scope"],
      "reference_class" => binding["reference_class"],
      "order" => binding["order"],
      "target_branch_cut_ids" => [branch_cut["branch_cut_id"]],
      "preserve" => binding["preserve"],
      "discard" => binding["discard"]
    }
  end
  bindings
end

begin
  run_arg = options[:run] || ARGV.shift
  raise ContextError, "run root is required" if run_arg.to_s.empty?
  raise ContextError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  raise ContextError, "--section is required" if options[:section_id].to_s.empty?
  raise ContextError, "--core-cut-id is required" if options[:core_cut_id].to_s.empty?
  raise ContextError, "--branch-cut-id is required" if options[:branch_cut_id].to_s.empty?
  raise ContextError, "--task is required" if options[:task].to_s.strip.empty?

  run_path, run_rel = resolve_repo_path(run_arg)
  layout_errors = IdolRunLayout.validate(run_path, repo_root: ROOT)
  raise ContextError, layout_errors.join("; ") unless layout_errors.empty?
  run_identity = IdolRunLayout.identity(run_path, repo_root: ROOT)
  storyboard_path = options[:storyboard] ? resolve_repo_path(options[:storyboard], must_exist: true).first : run_path.join("02A-master-storyboard.yaml")
  raise ContextError, "storyboard must stay inside the owning run" unless storyboard_path.dirname == run_path
  raise ContextError, "storyboard is missing" unless storyboard_path.file?
  storyboard_rel = storyboard_path.relative_path_from(ROOT).to_s
  storyboard = load_mapping(storyboard_path, "02A storyboard")
  raise ContextError, "only active 02A schema 3.0 is supported" unless storyboard["schema_version"].to_s == "3.0"
  unless storyboard["content_id"].to_s == run_identity["content_id"].to_s
    raise ContextError, "storyboard content_id differs from the run identity"
  end
  stdout, stderr, status = Open3.capture3(
    "ruby",
    STORYBOARD_VALIDATOR.to_s,
    "--root",
    ROOT.to_s,
    storyboard_path.to_s,
    chdir: ROOT.to_s
  )
  raise ContextError, "02A storyboard failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  storyboard_sha = file_sha256(storyboard_path)

  front_path, front_rel, front_sha, front = artifact_from_ref(storyboard["source_front_planning"], "source_front_planning")
  direction_path, direction_rel, direction_sha, direction = artifact_from_ref(storyboard["source_01_direction"], "source_01_direction")
  raise ContextError, "Front Planning source must stay inside the owning run or current title package" unless front_path.to_s.start_with?("#{run_path}/") || front_rel.start_with?("assets/members/album-assets/")
  raise ContextError, "01 source must stay inside the owning run" unless direction_path.to_s.start_with?("#{run_path}/")

  section_id = options[:section_id].to_s
  core_cut_id = options[:core_cut_id].to_s
  branch_cut_id = options[:branch_cut_id].to_s
  shard = Array(storyboard["section_shards"]).find do |row|
    row.is_a?(Hash) && Array(row["section_ids"]).map(&:to_s) == [section_id]
  end
  raise ContextError, "section #{section_id} has no 02A shard" unless shard

  all_core_cuts = Array(storyboard["master_storyboard"])
  section_core_cuts = Array(shard["core_cut_ids"]).map do |owned_core_cut_id|
    all_core_cuts.find { |core_cut| core_cut["core_cut_id"].to_s == owned_core_cut_id.to_s } ||
      raise(ContextError, "section shard names unknown Core Cut #{owned_core_cut_id}")
  end
  core_position = section_core_cuts.index { |core_cut| core_cut["core_cut_id"].to_s == core_cut_id }
  raise ContextError, "Core Cut #{core_cut_id} is not owned by section #{section_id}" unless core_position
  current_core_cut = section_core_cuts.fetch(core_position)
  unless current_core_cut.dig("imported_core", "section_id").to_s == section_id
    raise ContextError, "Core Cut #{core_cut_id} imported_core.section_id differs from #{section_id}"
  end
  previous_core_cut = core_position.zero? ? nil : section_core_cuts.fetch(core_position - 1)
  next_core_cut = core_position == section_core_cuts.length - 1 ? nil : section_core_cuts.fetch(core_position + 1)
  current_core_index = all_core_cuts.index(current_core_cut)
  previous_core_index = previous_core_cut && all_core_cuts.index(previous_core_cut)
  next_core_index = next_core_cut && all_core_cuts.index(next_core_cut)

  branch_cuts = Array(current_core_cut.dig("compile_seed", "branch_cuts"))
  branch_position = branch_cuts.index { |branch_cut| branch_cut["branch_cut_id"].to_s == branch_cut_id }
  raise ContextError, "Branch Cut #{branch_cut_id} is not owned by Core Cut #{core_cut_id}" unless branch_position
  current_branch_cut = branch_cuts.fetch(branch_position)
  previous_branch_cut = branch_position.zero? ? nil : branch_cuts.fetch(branch_position - 1)
  next_branch_cut = branch_position == branch_cuts.length - 1 ? nil : branch_cuts.fetch(branch_position + 1)

  member_input = current_branch_cut["member_visual_compile_input"].to_h
  packages = [[member_input["package_album_key"].to_s, member_input["package_title_key"].to_s]]
  raise ContextError, "current Branch Cut must bind one current-title package" if packages.flatten.any?(&:empty?)
  album_key, title_key = packages.first
  visual_bindings = verify_visual_bindings(current_branch_cut, album_key, title_key, run_path)
  member_asset_ids = visual_bindings.map { |row| row["asset_id"] if row["reference_scope"] == "member_visual" }.compact.uniq

  context_payload = Idol02AStoryboardContract.same_section_context_payload(
    storyboard,
    shard,
    section_core_cuts,
    core_position,
    current_branch_cut,
    branch_position
  )
  context_sha = value_sha256(context_payload)
  planning_projection = {
    "target_message_summary" => storyboard["target_message_summary"],
    "whole_film_spine" => storyboard["whole_film_spine"],
    "output_intent" => storyboard["output_intent"],
    "branch_subject_mix_policy" => storyboard["branch_subject_mix_policy"],
    "summary_boundary" => "compact_index_only_never_a_substitute_for_storyline_lineage_projection"
  }
  storyline_value = storyboard.dig("storyline_lineage_projection", "projected_value")
  storyline_projection = {
    "source_json_pointer" => "/storyline_lineage_projection/projected_value",
    "source_value_sha256" => value_sha256(storyline_value),
    "projected_value" => storyline_value,
    "projection_rule" => "read_complete_pre00_original_active_full_text_revision_history_density_review_and_reference_receipts_before_compact_planning_or_branch_detail"
  }
  screen_progression_value = front.fetch("screen_progression_map")
  provider_registry_path = ROOT.join("automation", "harness-provider-profile-registry.yaml")
  provider_registry_sha = file_sha256(provider_registry_path)
  provider_registry = load_mapping(provider_registry_path, "provider profile registry")
  worker_providers = provider_registry.dig("logical_profiles", "worker_high", "providers").to_h
  resolved_provider = worker_providers[options[:owner]].to_h
  execution_profile_id = resolved_provider["provider_profile_id"].to_s
  profile_source = resolved_provider["source_path"].to_s
  profile_source_sha = resolved_provider["source_sha256"].to_s
  resolved_profile_snapshot_ref = "#{profile_source}#profiles/#{execution_profile_id}#sha256=#{profile_source_sha}"
  raise ContextError, "selected worker provider profile is incomplete" if [execution_profile_id, profile_source, profile_source_sha].any?(&:empty?)
  selected_profile_path, = resolve_repo_path(profile_source, must_exist: true)
  raise ContextError, "selected worker provider profile registry hash is stale" unless file_sha256(selected_profile_path) == profile_source_sha

  pack = {
    "schema_version" => "idol-harness-context-pack.v7",
    "content_id" => storyboard["content_id"],
    "run" => run_rel,
    "task" => {
      "stage_id" => "image_prompt_compilation",
      "context_profile" => "image_prompt_section",
      "owner" => options[:owner],
      "description" => options[:task],
      "active_section_ids" => [section_id],
      "active_core_cut_id" => core_cut_id,
      "active_branch_cut_id" => branch_cut_id,
      "scope_rule" => "one_section_one_current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_same_section_core_neighbors"
    },
    "source_snapshot" => [
      {
        "role" => "front_planning",
        "path" => front_rel,
        "sha256" => front_sha,
        "schema_version" => front["schema_version"].to_s,
        "selected_use" => "target_message_visual_package_section_member_and_reference_assignment_owner"
      },
      {
        "role" => "section_direction_01",
        "path" => direction_rel,
        "sha256" => direction_sha,
        "schema_version" => direction["schema_version"].to_s,
        "selected_use" => "section_staging_action_choreography_need_still_camera_and_transition_owner"
      },
      {
        "role" => "storyboard_02a",
        "path" => storyboard_rel,
        "sha256" => storyboard_sha,
        "schema_version" => storyboard["schema_version"].to_s,
        "selected_use" => "exact_parent_core_cut_current_branch_cut_and_visual_binding_owner"
      }
    ],
    "storyline_lineage_projection" => storyline_projection,
    "screen_progression_projection" => {
      "source_path" => front_rel,
      "source_json_pointer" => "/screen_progression_map",
      "source_value_sha256" => value_sha256(screen_progression_value),
      "projected_value" => screen_progression_value,
      "projection_rule" => "exact_copy_no_paraphrase_or_default"
    },
    "provider_profile_snapshot" => {
      "registry_path" => "automation/harness-provider-profile-registry.yaml",
      "registry_sha256" => provider_registry_sha,
      "logical_profile_alias" => "worker_high",
      "execution_profile_id" => execution_profile_id,
      "resolved_profile_snapshot_ref" => resolved_profile_snapshot_ref,
      "provider_capability_snapshot_sha256" => profile_source_sha,
      "fallback_policy" => "forbidden"
    },
    "planning_spine" => planning_projection.merge("projection_sha256" => value_sha256(planning_projection)),
    "active_unit" => {
      "section_id" => section_id,
      "section_assignment" => shard,
      "branch_neighborhood" => {
        "policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only",
        "section_id" => section_id,
        "parent_core_cut" => core_cut_ref(current_core_cut, current_core_index),
        "current_branch_cut" => branch_cut_ref(current_branch_cut, current_core_index, branch_position),
        "previous_branch_cut" => branch_cut_ref(previous_branch_cut, current_core_index, branch_position - 1),
        "next_branch_cut" => branch_cut_ref(next_branch_cut, current_core_index, branch_position + 1),
        "previous_core_cut" => core_cut_ref(previous_core_cut, previous_core_index),
        "next_core_cut" => core_cut_ref(next_core_cut, next_core_index),
        "section_entry_continuity" => previous_core_cut.nil? ? shard["transition_in"] : nil,
        "section_exit_continuity" => next_core_cut.nil? ? shard["transition_out"] : nil,
        "context_value_sha256" => context_sha
      },
      "parent_core_cut" => Idol02AStoryboardContract.core_cut_context_projection(current_core_cut),
      "current_branch_cut" => current_branch_cut,
      "previous_branch_cut" => previous_branch_cut,
      "next_branch_cut" => next_branch_cut,
      "previous_core_cut" => previous_core_cut && Idol02AStoryboardContract.core_cut_context_projection(previous_core_cut),
      "next_core_cut" => next_core_cut && Idol02AStoryboardContract.core_cut_context_projection(next_core_cut),
      "current_branch_visual_bindings" => visual_bindings,
      "current_title_package" => {
        "album_key" => album_key,
        "title_key" => title_key,
        "member_visual_asset_ids" => member_asset_ids,
        "rule" => "current_title_only_and_smallest_branch_cut_relevant_subset"
      },
      "cross_section_boundary_detail" => nil
    },
    "read_order" => [
      "storyline_lineage_projection",
      "screen_progression_projection",
      "provider_profile_snapshot",
      "planning_spine",
      "active_unit.section_assignment",
      "active_unit.parent_core_cut",
      "active_unit.current_branch_cut",
      "active_unit.previous_branch_cut",
      "active_unit.next_branch_cut",
      "active_unit.previous_core_cut",
      "active_unit.next_core_cut",
      "active_unit.current_branch_visual_bindings"
    ],
    "excluded_surfaces" => [
      "adjacent_section_core_or_branch_detail",
      "other_section_storyboard_cuts",
      "other_section_prompt_packets",
      "other_section_visual_references",
      "full_run_raw_research_history",
      "rejected_candidate_detail",
      "full_contact_sheets",
      "prior_chat_transcript"
    ],
    "automation_boundaries" => {
      "derived_context_only" => true,
      "creative_truth_authored" => false,
      "founder_pass_inferred" => false,
      "paid_generation_approved" => false,
      "external_execution_approved" => false
    }
  }
  pack["handoff_digest"] = value_sha256(pack)

  output_path = if options[:output]
                  resolve_repo_path(options[:output]).first
                else
                  run_path.join("work", "context-packs", "image_prompt_section", section_id, core_cut_id, "#{branch_cut_id}.yaml")
                end
  raise ContextError, "context-pack output must stay inside the owning run" unless output_path.to_s.start_with?("#{run_path}/")
  serialized = YAML.dump(pack)
  Tempfile.create(["idol-context-pack", ".yaml"]) do |file|
    file.write(serialized)
    file.flush
    validate_schema(Pathname.new(file.path))
  end
  if options[:write]
    output_path.dirname.mkpath
    output_path.write(serialized)
  end

  puts JSON.pretty_generate(
    "valid" => true,
    "written" => options[:write],
    "output" => output_path.relative_path_from(ROOT).to_s,
    "section_id" => section_id,
    "core_cut_id" => core_cut_id,
    "branch_cut_id" => branch_cut_id,
    "previous_branch_cut_id" => previous_branch_cut&.dig("branch_cut_id"),
    "next_branch_cut_id" => next_branch_cut&.dig("branch_cut_id"),
    "previous_core_cut_id" => previous_core_cut&.dig("core_cut_id"),
    "next_core_cut_id" => next_core_cut&.dig("core_cut_id"),
    "visual_binding_count" => visual_bindings.length,
    "handoff_digest" => pack["handoff_digest"]
  )
rescue ContextError, KeyError => e
  warn "context pack failed: #{e.message}"
  exit 1
end
