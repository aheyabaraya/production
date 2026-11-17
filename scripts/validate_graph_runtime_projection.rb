#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "ripper"
require "set"
require "time"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_SKILL_LOAD = ROOT.join("automation", "graph-skill-load-profiles.yaml")
DEFAULT_PROJECTION = ROOT.join("automation", "graph-role-context-projection.yaml")
DEFAULT_ROUTING = ROOT.join("automation", "graph-default-routing.yaml")
JUDGMENT_REGISTRY = ROOT.join("automation", "graph-creative-judgment-registry.yaml")
SKILL_LOAD_SCHEMA = ROOT.join("schemas", "graph-skill-load-profiles.schema.json")
PROJECTION_SCHEMA = ROOT.join("schemas", "graph-role-context-projection.schema.json")
ROUTING_SCHEMA = ROOT.join("schemas", "graph-default-routing.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

FORBIDDEN_PACK_KEYS = %w[
  url urls raw_pool raw_search_pool full_url_list worker_transcript
  completed_worker_transcript superseded_prose
].freeze
SWITCH_RECEIPT_FIELDS = %w[
  receipt_id founder_authority graph_revision switch_boundary source_set_sha256 verified_at
].freeze
PARSE_ONLY_PREFIXES = %w[harness- idol-harness- idol_harness_].freeze
CANONICAL_DIRECTOR_LANE_ID_PATTERNS = {
  "overall" => "^overall$",
  "planning_p1" => "^planning_p1$",
  "planning_p2" => "^planning_p2$",
  "planning_p3_ci" => "^planning_p3_c[1-9][0-9]*$",
  "section_cluster_v_ci" => "^section_cluster_v_c[1-9][0-9]*$",
  "edit_director" => "^edit_director$"
}.freeze
P3_LANE_ID_PATTERN = CANONICAL_DIRECTOR_LANE_ID_PATTERNS.fetch("planning_p3_ci")
V_LANE_ID_PATTERN = CANONICAL_DIRECTOR_LANE_ID_PATTERNS.fetch("section_cluster_v_ci")
DIRECTOR_LANE_PATTERN_LABELS = {
  "overall" => ["overall", "overall"],
  "planning_p1" => ["P1", "planning_p1"],
  "planning_p2" => ["P2", "planning_p2"],
  "planning_p3_ci" => ["P3", "planning_p3_cN"],
  "section_cluster_v_ci" => ["V-Ci", "section_cluster_v_cN"],
  "edit_director" => ["edit_director", "edit_director"]
}.freeze
P3_DIRECTOR_LANE = /\Aplanning_p3_c([1-9][0-9]*)\z/
V_DIRECTOR_LANE = /\Asection_cluster_v_c([1-9][0-9]*)\z/
CANONICAL_DIRECTOR_LANE = /\A(?:overall|planning_p1|planning_p2|planning_p3_c[1-9][0-9]*|section_cluster_v_c[1-9][0-9]*|edit_director)\z/
DIRECTOR_LANE_ROLES = {
  "overall" => "overall_director",
  "planning_p1" => "planning_cdd_p1",
  "planning_p2" => "planning_cdd_p2",
  "edit_director" => "edit_director"
}.freeze
COMPACT_EXCLUSIONS = %w[
  raw_search_pools full_url_lists completed_worker_transcripts superseded_prose
  unrelated_section_or_cohort_media graph_engineering_policy_explanations
  other_provider_tool_detail
].freeze
EXPLICIT_NON_RUBY_RUNTIME_DEPENDENCIES = %w[
  scripts/idol-video-python
  scripts/validate_json_schema.py
].freeze
COHORT_WRITER_REQUIRED_STATES = %w[active reviewing].freeze
COHORT_NONWRITER_STATES = %w[queued backpressure_blocked retired].freeze
COHORT_RUNTIME_STAGES = %w[planning_cell section_cluster_production].freeze

options = {
  json: false,
  skill_load: DEFAULT_SKILL_LOAD,
  projection: DEFAULT_PROJECTION,
  routing: DEFAULT_ROUTING,
  case: nil
}
OptionParser.new do |parser|
  parser.on("--json") { options[:json] = true }
  parser.on("--skill-load PATH") { |value| options[:skill_load] = Pathname.new(value).expand_path }
  parser.on("--projection PATH") { |value| options[:projection] = Pathname.new(value).expand_path }
  parser.on("--routing PATH") { |value| options[:routing] = Pathname.new(value).expand_path }
  parser.on("--case PATH") { |value| options[:case] = Pathname.new(value).expand_path }
end.parse!

def load_yaml(path)
  value = YAML.safe_load(path.read, aliases: true)
  value.is_a?(Hash) ? value : {}
rescue Errno::ENOENT, Psych::Exception => e
  raise e if e.is_a?(Errno::ENOENT)

  {}
end

def schema_validate(schema, document)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    document.to_s,
    chdir: ROOT.to_s
  )
  return [] if status.success?

  [[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip]
end

def repo_file?(relative)
  path = ROOT.join(relative).cleanpath
  repo_relative = path.relative_path_from(ROOT).to_s
  return false if repo_relative == ".." || repo_relative.start_with?("../")

  path.file?
rescue ArgumentError
  false
end

def file_sha256(relative)
  Digest::SHA256.file(ROOT.join(relative).to_s).hexdigest
end

def graph_source_set_digest(routing, errors)
  surfaces = Array(routing.dig("writer_boundary", "active_graph_surfaces")).map(&:to_s)
  if surfaces.empty?
    errors << "active graph source set is empty"
    return nil
  end
  errors << "active graph source set contains duplicate paths" unless surfaces.uniq.length == surfaces.length

  rows = surfaces.sort.map do |relative|
    unless repo_file?(relative)
      errors << "active graph source is missing: #{relative}"
      next
    end
    "#{relative}:#{file_sha256(relative)}"
  end.compact
  return nil unless rows.length == surfaces.length

  Digest::SHA256.hexdigest(rows.join("\n") + "\n")
end

def static_string_argument(arguments)
  node = arguments
  node = node[1] if node.is_a?(Array) && node[0] == :arg_paren
  return nil unless node.is_a?(Array) && node[0] == :args_add_block

  values = node[1]
  return nil unless values.is_a?(Array) && values.length == 1

  literal = values.first
  return nil unless literal.is_a?(Array) && literal[0] == :string_literal

  content = literal[1]
  return "" if content == [:string_content]
  return nil unless content.is_a?(Array) && content[0] == :string_content

  fragments = content.drop(1)
  return nil unless fragments.all? { |fragment| fragment.is_a?(Array) && fragment[0] == :@tstring_content }

  fragments.map { |fragment| fragment[1].to_s }.join
end

def require_relative_calls(node, calls)
  return unless node.is_a?(Array)

  if node[0] == :command && node.dig(1, 0) == :@ident && node.dig(1, 1) == "require_relative"
    calls << [static_string_argument(node[2]), node.dig(1, 2, 0)]
  elsif node[0] == :method_add_arg &&
        node.dig(1, 0) == :fcall && node.dig(1, 1, 0) == :@ident && node.dig(1, 1, 1) == "require_relative"
    calls << [static_string_argument(node[2]), node.dig(1, 1, 2, 0)]
  end
  node.each { |child| require_relative_calls(child, calls) if child.is_a?(Array) }
end

def validate_active_ruby_dependency_closure(active_surfaces, errors)
  roots = active_surfaces.select do |relative|
    relative.end_with?(".rb") && relative.start_with?("scripts/") && !relative.start_with?("scripts/lib/")
  end.sort
  errors << "active graph Ruby entrypoint set is empty" if roots.empty?

  repo_root = ROOT.realpath
  queue = roots.dup
  visited = Set.new
  until queue.empty?
    relative = queue.shift
    next if visited.include?(relative)

    visited << relative
    source_path = ROOT.join(relative)
    next unless source_path.file?

    syntax = Ripper.sexp(source_path.read)
    unless syntax
      errors << "active graph Ruby source cannot be parsed for dependency closure: #{relative}"
      next
    end
    calls = []
    require_relative_calls(syntax, calls)
    calls.each do |literal, line|
      if literal.nil? || literal.empty?
        errors << "dynamic require_relative is forbidden in active graph Ruby closure: #{relative}:#{line}"
        next
      end

      unresolved = source_path.dirname.join(literal).cleanpath
      candidates = [unresolved]
      candidates << Pathname.new("#{unresolved}.rb") if unresolved.extname.empty?
      target = candidates.find(&:file?)
      unless target
        errors << "require_relative target is missing from disk: #{relative}:#{line} -> #{literal}"
        next
      end
      begin
        real_target = target.realpath
        target_relative = real_target.relative_path_from(repo_root).to_s
        if target_relative == ".." || target_relative.start_with?("../") || real_target.extname != ".rb"
          errors << "require_relative target escapes the active Ruby repository closure: #{relative}:#{line} -> #{literal}"
          next
        end
      rescue ArgumentError
        errors << "require_relative target escapes the active Ruby repository closure: #{relative}:#{line} -> #{literal}"
        next
      end

      unless active_surfaces.include?(target_relative)
        errors << "required Ruby dependency is outside active graph source closure: #{relative}:#{line} -> #{target_relative}"
      end
      queue << target_relative unless visited.include?(target_relative)
    end
  end
end

def markdown_headings(relative)
  text = ROOT.join(relative).read
  text.scan(/^\#{2,3}\s+(.+?)\s*$/).flatten
end

def partition_cohort_sizes(section_count)
  count = Integer(section_count)
  return :invalid if count < 1
  return [1] if count == 1
  return [2] if count == 2
  return [3] if count == 3

  threes, remainder = count.divmod(3)
  sizes =
    case remainder
    when 0
      Array.new(threes, 3)
    when 1
      return :invalid if threes < 1

      [2, 2] + Array.new(threes - 1, 3)
    when 2
      [2] + Array.new(threes, 3)
    end
  return :invalid unless sizes.sum == count && sizes.all? { |size| size == 2 || size == 3 }

  sizes
end

def parse_only_id?(value)
  text = File.basename(value.to_s)
  PARSE_ONLY_PREFIXES.any? { |prefix| text.start_with?(prefix) }
end

def director_lane_role(lane_id)
  lane = lane_id.to_s
  return "planning_cdd_p3_ci" if lane.match?(P3_DIRECTOR_LANE)
  return "section_cluster_cdd_ci" if lane.match?(V_DIRECTOR_LANE)

  DIRECTOR_LANE_ROLES[lane]
end

def director_lane_macro_stage(lane_id)
  lane = lane_id.to_s
  return %w[planning_cell section_cluster_production edit_and_package] if lane == "overall"
  return ["planning_cell"] if lane.start_with?("planning_")
  return ["section_cluster_production"] if lane.match?(V_DIRECTOR_LANE)
  return ["edit_and_package"] if lane == "edit_director"

  []
end

def director_lane_cohort_id(lane_id)
  match = lane_id.to_s.match(P3_DIRECTOR_LANE) || lane_id.to_s.match(V_DIRECTOR_LANE)
  match ? "C#{match[1]}" : nil
end

errors = []

skill_load_path = options[:skill_load]
projection_path = options[:projection]
routing_path = options[:routing]

[skill_load_path, projection_path, routing_path].each do |path|
  errors << "graph runtime registry is missing: #{path}" unless path.file?
end

errors.concat(schema_validate(SKILL_LOAD_SCHEMA, skill_load_path)) if skill_load_path.file?
errors.concat(schema_validate(PROJECTION_SCHEMA, projection_path)) if projection_path.file?
errors.concat(schema_validate(ROUTING_SCHEMA, routing_path)) if routing_path.file?

skill_load = skill_load_path.file? ? load_yaml(skill_load_path) : {}
projection = projection_path.file? ? load_yaml(projection_path) : {}
routing = routing_path.file? ? load_yaml(routing_path) : {}
judgment_registry = JUDGMENT_REGISTRY.file? ? load_yaml(JUDGMENT_REGISTRY) : {}
graph_source_digest = graph_source_set_digest(routing, errors)

active_graph_surfaces = Array(routing.dig("writer_boundary", "active_graph_surfaces")).map(&:to_s).to_set
EXPLICIT_NON_RUBY_RUNTIME_DEPENDENCIES.each do |relative|
  unless active_graph_surfaces.include?(relative)
    errors << "required non-Ruby runtime dependency is outside active graph source closure: #{relative}"
  end
end
validate_active_ruby_dependency_closure(active_graph_surfaces, errors)
current_profile_releases = judgment_registry["current_profile_releases"]
unless current_profile_releases.is_a?(Hash)
  errors << "current judgment profile release registry is missing"
  current_profile_releases = {}
end
current_profile_releases.each_value do |pointer|
  next unless pointer.is_a?(Hash)

  release_path = pointer["path"].to_s
  promotion_path = pointer.dig("promotion_binding", "path").to_s
  unless active_graph_surfaces.include?(release_path)
    errors << "current judgment profile release is outside active graph source closure: #{release_path}"
  end
  unless active_graph_surfaces.include?(promotion_path)
    errors << "current judgment profile promotion is outside active graph source closure: #{promotion_path}"
  end
end

%w[shadow_not_default hold].include?(skill_load["status"].to_s) ||
  errors << "graph skill-load status must remain shadow_not_default until switch"
errors << "graph skill-load must not be an active default writer" unless skill_load.dig("activation", "default_writer") == "legacy_pinned"
errors << "graph v2 requires verified default-switch receipt" unless skill_load.dig("activation", "graph_v2_requires") == "verified_default_switch_receipt"
errors << "existing runs must remain legacy-pinned in skill-load" unless skill_load.dig("activation", "existing_runs") == "legacy_pinned"
errors << "dual active writer must fail closed in skill-load" unless skill_load.dig("activation", "dual_active_writer") == "fail_closed"
errors << "historical harness ids must be parse-only" unless skill_load.dig("activation", "historical_harness_ids") == "parse_only_legacy_capsule"

errors << "projection must remain shadow_not_default" unless %w[shadow_not_default hold].include?(projection["status"].to_s)
errors << "projection source registry path mismatch" unless projection.dig("source_registry", "path") == "automation/graph-skill-load-profiles.yaml"
errors << "URLs must be excluded from packs" unless projection.dig("defaults", "url_projection") == "exclude_from_pack_recover_via_source_id"
errors << "raw pools must be excluded from packs" unless projection.dig("defaults", "raw_pool_projection") == "exclude_from_pack"
recover = projection.dig("compact_source_projection", "recoverability") || {}
%w[source_id locator sha256].each do |field|
  errors << "compact source recoverability missing #{field}" unless recover[field] == "required"
end
forbidden = Array(projection["forbidden_pack_fields"]).map(&:to_s)
FORBIDDEN_PACK_KEYS.each do |field|
  errors << "projection missing forbidden pack field: #{field}" unless forbidden.include?(field)
end

errors << "default routing must remain shadow_not_default" unless %w[shadow_not_default hold].include?(routing["status"].to_s)
errors << "existing runs must remain legacy-pinned" unless routing.dig("writer_boundary", "existing_runs") == "legacy_pinned"
errors << "new runs must default legacy-pinned" unless routing.dig("writer_boundary", "new_runs", "default") == "legacy_pinned"
errors << "new-run graph v2 requires verified switch receipt" unless routing.dig("writer_boundary", "new_runs", "graph_v2_requires") == "verified_default_switch_receipt"
errors << "dual active writer must fail closed" unless routing.dig("writer_boundary", "dual_active_writer") == "fail_closed"
errors << "historical harness ids must stay parse-only" unless routing.dig("writer_boundary", "historical_harness_ids") == "parse_only_legacy_capsule"
routing_patterns = routing.dig("cohort_succession", "lane_id_pattern") || {}
CANONICAL_DIRECTOR_LANE_ID_PATTERNS.each do |key, canonical|
  label, grammar = DIRECTOR_LANE_PATTERN_LABELS.fetch(key)
  unless routing_patterns[key] == canonical
    errors << "graph-default-routing #{label} lane_id_pattern must match canonical #{grammar} grammar"
  end
end
errors << "P3 identity must exact-carry into V" unless routing.dig("cohort_succession", "same_cohort_carry") == "p3_ci_section_cohort_id_exact_carries_to_v_ci"
errors << "02B to 03V must be same-cohort successor" unless routing.dig("cohort_succession", "pixel_to_playback") == "same_cohort_cdd_successor"
parallelism = routing.dig("cohort_succession", "cross_cohort_parallelism") || {}
errors << "disjoint P3-Ci cohort lanes must allow bounded parallelism" unless parallelism["planning_p3_ci"] == "allowed_for_disjoint_cohort_lanes"
errors << "disjoint V-Ci cohort lanes must allow bounded parallelism" unless parallelism["section_cluster_v_ci"] == "allowed_for_disjoint_cohort_lanes"
errors << "capacity must not create a cohort lane" unless parallelism["capacity_creates_lane"] == false
errors << "cross-cohort parallelism requires disjoint write scope" unless parallelism["requires_disjoint_write_scope"] == true
errors << "cross-cohort parallelism must obey lower capacity and backpressure" unless parallelism["lower_provider_combined_cap_and_backpressure_win"] == true
errors << "active writer maximum must be one per lane/stage" unless routing.dig("session_caps", "active_writer_per_lane_stage") == 1
errors << "physical session maximum must be two" unless routing.dig("session_caps", "physical_per_lane_stage", "maximum") == 2
errors << "successor must be read-only before CAS" unless routing.dig("session_caps", "successor_before_cas") == "read_only_not_active_writer"
errors << "CAS must atomically retire primary before activating successor" unless routing.dig("session_caps", "cas_commit") == "atomic_retire_primary_then_activate_successor"
provider_ceiling = routing.dig("session_caps", "provider_physical_ceiling") || {}
errors << "Grok Build non-root physical ceiling must be eight" unless provider_ceiling["grok_build_nonroot"] == 8
errors << "Cursor Agent non-root physical ceiling must be six" unless provider_ceiling["cursor_agent_nonroot"] == 6
errors << "combined physical ceiling must be fourteen" unless provider_ceiling["combined"] == 14
errors << "lower provider live cap must win" unless provider_ceiling["lower_live_cap_wins"] == true
errors << "third session must HOLD" unless routing.dig("session_caps", "third_session") == "hold_never_auto_spawn"
errors << "same-session correction must stay in the same room" unless routing.dig("same_session_correction", "physical_session") == "same_session"
errors << "backpressure must forbid launch at unreviewed limit" unless routing.dig("backpressure", "new_launch_when_limit_reached") == "forbidden"
gate_ids = Array(routing.dig("founder_gates", "normal_cycle")).map(&:to_s)
errors << "Founder gates must be G0--G4" unless gate_ids == %w[G0 G1 G2 G3 G4]

skill_rows = Array(skill_load["skill_bindings"]).select { |row| row.is_a?(Hash) }
read_rows = Array(skill_load["read_bindings"]).select { |row| row.is_a?(Hash) }
binding_rows = skill_rows + read_rows
binding_map = {}
binding_rows.each do |row|
  id = row["binding_id"].to_s
  errors << "duplicate binding_id: #{id}" if binding_map.key?(id) || id.empty?
  binding_map[id] = row
  relative = row["path"].to_s
  unless repo_file?(relative)
    errors << "binding path is missing: #{relative}"
    next
  end
  unless options[:case]
    actual = file_sha256(relative)
    errors << "binding SHA-256 is stale: #{relative}" unless actual == row["sha256"].to_s
  end
  if parse_only_id?(id)
    errors << "historical harness id used as active graph binding: #{id}=#{relative}"
  end
end

profiles = Array(skill_load["profiles"]).select { |row| row.is_a?(Hash) }
profiles_by_id = profiles.each_with_object({}) { |row, memo| memo[row["profile_id"].to_s] = row }
skill_ids = skill_rows.map { |row| row["binding_id"].to_s }.to_set
read_ids = read_rows.map { |row| row["binding_id"].to_s }.to_set

required_profiles = %w[
  overall_director planning_cdd_p1 planning_cdd_p2 planning_cdd_p3_ci
  section_cluster_cdd_ci section_image_motion_worker edit_director
]
required_profiles.each do |profile_id|
  errors << "missing graph profile: #{profile_id}" unless profiles_by_id.key?(profile_id)
end

p3 = profiles_by_id["planning_cdd_p3_ci"] || {}
vci = profiles_by_id["section_cluster_cdd_ci"] || {}
errors << "P3 must be a cohort template" unless p3["profile_kind"] == "cohort_template" && p3["cohort_template"] == true
errors << "V-Ci must be a cohort template" unless vci["profile_kind"] == "cohort_template" && vci["cohort_template"] == true
errors << "P3 lane_id_pattern must match canonical planning_p3_cN grammar" unless p3["lane_id_pattern"] == P3_LANE_ID_PATTERN
errors << "V-Ci lane_id_pattern must match canonical section_cluster_v_cN grammar" unless vci["lane_id_pattern"] == V_LANE_ID_PATTERN
errors << "skill-load P3 lane_id_pattern must match graph-default-routing" unless p3["lane_id_pattern"] == routing_patterns["planning_p3_ci"]
errors << "skill-load V-Ci lane_id_pattern must match graph-default-routing" unless vci["lane_id_pattern"] == routing_patterns["section_cluster_v_ci"]
errors << "P3 identity_carry_to must be section_cluster_cdd_ci" unless p3["identity_carry_to"] == "section_cluster_cdd_ci"
errors << "V-Ci identity_carry_from must be planning_cdd_p3_ci" unless vci["identity_carry_from"] == "planning_cdd_p3_ci"
errors << "P1/P2/P3 writable sets must be disjoint" unless [
  profiles_by_id.dig("planning_cdd_p1", "writable_decision_set"),
  profiles_by_id.dig("planning_cdd_p2", "writable_decision_set"),
  p3["writable_decision_set"]
].uniq.length == 3
errors << "section media worker must return to the cohort CDD" unless profiles_by_id.dig("section_image_motion_worker", "return_route", "recipient_role") == "section_cluster_cdd_ci"
errors << "Overall promotion owner must remain overall_director" unless profiles_by_id.dig("overall_director", "authority", "promotion_owner") == "overall_director"
errors << "no fixed CDD count policy missing" unless skill_load.dig("registry_policy", "no_fixed_cdd_count") == true
errors << "cohort source must be roster-derived" unless skill_load.dig("cohort_instantiation", "source") == "section_roster_derived"
errors << "capacity may not create a cohort" unless skill_load.dig("cohort_instantiation", "capacity_may_not_create_cohort") == true

profiles.each do |profile|
  profile_id = profile["profile_id"].to_s
  Array(profile["required_skill_ids"]).each do |binding_id|
    errors << "unknown skill binding in #{profile_id}: #{binding_id}" unless skill_ids.include?(binding_id.to_s)
  end
  Array(profile["required_read_ids"]).each do |binding_id|
    errors << "unknown read binding in #{profile_id}: #{binding_id}" unless read_ids.include?(binding_id.to_s)
  end
  missing_exclusions = COMPACT_EXCLUSIONS - Array(profile["compact_exclusions"]).map(&:to_s)
  missing_exclusions.each { |token| errors << "#{profile_id} missing compact exclusion: #{token}" }
  errors << "#{profile_id} physical generation must cap at two" unless profile.dig("succession", "physical_generation_max") == 2
  Array(profile.dig("phase_load", "checkpoints")).each do |checkpoint|
    next unless checkpoint.is_a?(Hash)

    allowed_skills = Array(profile["required_skill_ids"]).map(&:to_s).to_set
    allowed_reads = Array(profile["required_read_ids"]).map(&:to_s).to_set
    checkpoint_skills = Array(checkpoint["required_skill_ids"]).map(&:to_s).to_set
    checkpoint_reads = Array(checkpoint["required_read_ids"]).map(&:to_s).to_set
    (checkpoint_skills - allowed_skills).each do |binding_id|
      errors << "checkpoint skill is outside profile allowed union: #{profile_id}.#{checkpoint['checkpoint_id']}=#{binding_id}"
    end
    (checkpoint_reads - allowed_reads).each do |binding_id|
      errors << "checkpoint read is outside profile allowed union: #{profile_id}.#{checkpoint['checkpoint_id']}=#{binding_id}"
    end
    if profile["profile_kind"] != "maintenance_only" && checkpoint_skills.empty?
      errors << "creative checkpoint must declare at least one skill: #{profile_id}.#{checkpoint['checkpoint_id']}"
    end
  end
end

Array(projection["rules"]).each do |rule|
  next unless rule.is_a?(Hash)

  binding_id = rule["binding_id"].to_s
  row = binding_map[binding_id]
  unless row
    errors << "projection rule unknown binding: #{binding_id}"
    next
  end
  next unless rule["mode"] == "markdown_headings"

  headings = markdown_headings(row["path"].to_s)
  Array(rule["headings"]).each do |heading|
    errors << "projection heading missing in #{row['path']}: #{heading}" unless headings.include?(heading.to_s)
  end
end

def verify_switch_receipt(receipt, errors, prefix, expected_revision:, expected_source_digest:)
  unless receipt.is_a?(Hash)
    errors << "#{prefix}: graph v2 requires a verified default-switch receipt"
    return
  end
  SWITCH_RECEIPT_FIELDS.each do |field|
    errors << "#{prefix}: switch receipt missing #{field}" if receipt[field].to_s.strip.empty?
  end
  sha = receipt["source_set_sha256"].to_s
  errors << "#{prefix}: switch receipt source_set_sha256 is not a SHA-256" unless sha.match?(/\A[a-f0-9]{64}\z/)
  unless expected_source_digest && sha == expected_source_digest
    errors << "#{prefix}: switch receipt source_set_sha256 does not match active graph source bytes"
  end
  errors << "#{prefix}: switch receipt graph_revision does not match active graph revision" unless receipt["graph_revision"].to_s == expected_revision.to_s
  errors << "#{prefix}: switch receipt founder_authority must be founder" unless receipt["founder_authority"].to_s == "founder"
  unless receipt["switch_boundary"].to_s == "new_runs_only_after_verified_receipt"
    errors << "#{prefix}: switch receipt boundary must be new_runs_only_after_verified_receipt"
  end
  verified_at = receipt["verified_at"].to_s
  begin
    Time.iso8601(verified_at)
    raise ArgumentError unless verified_at.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/)
  rescue ArgumentError
    errors << "#{prefix}: switch receipt verified_at must be ISO8601"
  end
end

def validate_runtime_case(document, routing, skill_load, graph_source_digest, errors)
  errors << "runtime case schema_version must be idol-graph-runtime-case.v1" unless document["schema_version"] == "idol-graph-runtime-case.v1"
  run_class = document.dig("run", "run_class").to_s
  requested = document.dig("writer", "requested").to_s
  active = Array(document.dig("writer", "active")).map(&:to_s)
  receipt = document["switch_receipt"]

  if run_class == "existing_run" && requested == "graph_v2"
    errors << "existing run remains legacy-pinned"
  end
  if run_class == "new_run" && requested == "graph_v2"
    verify_switch_receipt(
      receipt,
      errors,
      "new run",
      expected_revision: skill_load["schema_version"],
      expected_source_digest: graph_source_digest
    )
  end
  if active.include?("graph_v2") && active.include?("legacy_harness")
    errors << "dual active writer"
  end
  if active.length > 1 && active.uniq.length > 1
    errors << "dual active writer"
  end
  errors << "writer active set must contain exactly one writer" unless active.length == 1 && active.uniq.length == 1
  errors << "requested writer must equal the unique active writer" unless active == [requested]
  if requested == "graph_v2" && receipt.nil? && run_class != "existing_run"
    errors << "graph v2 requires a verified default-switch receipt"
  end

  Array(document["active_authoring_ids"]).each do |id|
    errors << "historical harness id used as active authoring: #{id}" if parse_only_id?(id)
  end

  graph_runtime = requested == "graph_v2" || active.include?("graph_v2")
  cohort_ids = Array(document["cohorts"]).each_with_object([]) do |row, ids|
    ids << row["cohort_id"].to_s if row.is_a?(Hash)
  end.to_set
  writers = Array(document["active_writers"]).select { |row| row.is_a?(Hash) }
  writers.each do |row|
    next unless graph_runtime

    lane = row["lane_id"].to_s
    unless lane.match?(CANONICAL_DIRECTOR_LANE)
      errors << "runtime Director writer lane_id is not canonical: #{lane}"
      next
    end
    expected_role = director_lane_role(lane)
    errors << "runtime Director writer role does not match lane #{lane}" unless row["role"].to_s == expected_role
    unless director_lane_macro_stage(lane).include?(row["stage"].to_s)
      errors << "runtime Director writer macro-stage does not match lane #{lane}"
    end
    expected_cohort = director_lane_cohort_id(lane)
    if expected_cohort
      errors << "runtime cohort writer section_cohort_id does not match lane #{lane}" unless row["section_cohort_id"].to_s == expected_cohort
      errors << "runtime cohort writer lane is outside canonical cohort roster: #{lane}" unless cohort_ids.include?(expected_cohort)
    end
  end
  active_p3_cohorts = writers.each_with_object([]) do |row, ids|
    match = row["lane_id"].to_s.match(P3_DIRECTOR_LANE)
    ids << match[1] if match && row["stage"].to_s == "planning_cell"
  end.to_set
  active_v_cohorts = writers.each_with_object([]) do |row, ids|
    match = row["lane_id"].to_s.match(V_DIRECTOR_LANE)
    ids << match[1] if match && row["stage"].to_s == "section_cluster_production"
  end.to_set
  active_p3_cohorts.intersection(active_v_cohorts).each do |index|
    errors << "P3 and V cannot both be active writers for cohort C#{index} across the G-40 handoff"
  end
  writers.group_by do |row|
    lane = row["lane_id"].to_s
    stage = row["stage"].to_s
    lane.empty? || stage.empty? ? row["scope"].to_s : "#{lane}/#{stage}"
  end.each do |scope, rows|
    next if scope.empty?

    errors << "dual active writer for lane/stage #{scope}" if rows.length > 1
  end

  sessions = Array(document["sessions"]).select { |row| row.is_a?(Hash) }
  sessions.each do |row|
    next unless graph_runtime

    lane = row["lane_id"].to_s
    unless lane.match?(CANONICAL_DIRECTOR_LANE)
      errors << "runtime Director session lane_id is not canonical: #{lane}"
      next
    end
    expected_role = director_lane_role(lane)
    errors << "runtime Director session role does not match lane #{lane}" unless row["role"].to_s == expected_role
    unless director_lane_macro_stage(lane).include?(row["stage"].to_s)
      errors << "runtime Director session macro-stage does not match lane #{lane}"
    end
    expected_cohort = director_lane_cohort_id(lane)
    if expected_cohort
      errors << "runtime cohort session section_cohort_id does not match lane #{lane}" unless row["section_cohort_id"].to_s == expected_cohort
      errors << "runtime cohort session lane is outside canonical cohort roster: #{lane}" unless cohort_ids.include?(expected_cohort)
    end
    errors << "runtime Director session_id is required on #{lane}/#{row['stage']}" if row["session_id"].to_s.strip.empty?
  end
  if graph_runtime
    sessions.group_by { |row| row["session_id"].to_s }.each do |session_id, rows|
      next if session_id.empty? || rows.length == 1

      errors << "physical session_id must be unique across Director lanes/stages: #{session_id}"
    end
  end
  p3_active_sessions = sessions.each_with_object([]) do |row, ids|
    match = row["lane_id"].to_s.match(P3_DIRECTOR_LANE)
    ids << match[1] if match && row["state"].to_s == "active_writer"
  end.to_set
  v_active_sessions = sessions.each_with_object([]) do |row, ids|
    match = row["lane_id"].to_s.match(V_DIRECTOR_LANE)
    ids << match[1] if match && row["state"].to_s == "active_writer"
  end.to_set
  p3_active_sessions.intersection(v_active_sessions).each do |index|
    errors << "P3 session must be read-only after V activation for cohort C#{index}"
  end
  live_provider_sessions = sessions.reject do |row|
    row["lane_id"].to_s == "overall" || %w[retired retired_read_only graph_logically_retired].include?(row["state"].to_s)
  end
  live_provider_sessions.each do |row|
    provider = row["provider"].to_s
    errors << "live non-root physical session provider is missing or unsupported" unless %w[grok cursor].include?(provider)
  end
  grok_live = live_provider_sessions.count { |row| row["provider"].to_s == "grok" }
  cursor_live = live_provider_sessions.count { |row| row["provider"].to_s == "cursor" }
  combined_live = grok_live + cursor_live
  provider_ceiling = routing.dig("session_caps", "provider_physical_ceiling") || {}
  errors << "Grok live physical session ceiling exceeded: #{grok_live}>#{provider_ceiling['grok_build_nonroot']}" if grok_live > Integer(provider_ceiling["grok_build_nonroot"] || 0)
  errors << "Cursor live physical session ceiling exceeded: #{cursor_live}>#{provider_ceiling['cursor_agent_nonroot']}" if cursor_live > Integer(provider_ceiling["cursor_agent_nonroot"] || 0)
  errors << "combined live physical session ceiling exceeded: #{combined_live}>#{provider_ceiling['combined']}" if combined_live > Integer(provider_ceiling["combined"] || 0)

  sessions.group_by { |row| [row["lane_id"].to_s, row["stage"].to_s] }.each do |(lane, stage), rows|
    next unless graph_runtime

    generations = rows.map { |row| row["generation"].to_s }
    errors << "third session on #{lane}/#{stage}" if rows.length > 2 || generations.include?("third")
    errors << "duplicate session generation on #{lane}/#{stage}" unless generations.uniq.length == generations.length
    invalid_generations = generations.reject { |generation| %w[primary successor].include?(generation) }
    errors << "session generation must be primary or successor on #{lane}/#{stage}" unless invalid_generations.empty?
    if generations.include?("successor") && !(rows.length == 2 && generations.sort == %w[primary successor])
      errors << "successor requires one retained primary on #{lane}/#{stage}"
      next
    end
    unless generations.include?("successor")
      errors << "single Director session must be primary on #{lane}/#{stage}" unless rows.length == 1 && generations == ["primary"]
      next
    end

    primary = rows.find { |row| row["generation"].to_s == "primary" }
    successor = rows.find { |row| row["generation"].to_s == "successor" }
    if primary["session_id"].to_s == successor["session_id"].to_s
      errors << "primary and successor session_id must be distinct on #{lane}/#{stage}"
    end
    committed = successor["cas_committed"]
    if committed == false
      errors << "successor writes before CAS on #{lane}/#{stage}" unless successor["state"].to_s == "read_only"
      errors << "primary must remain active before CAS on #{lane}/#{stage}" unless primary["state"].to_s == "active_writer"
    elsif committed == true
      errors << "successor must be active after CAS on #{lane}/#{stage}" unless successor["state"].to_s == "active_writer"
      errors << "primary must be retired after CAS on #{lane}/#{stage}" unless primary["state"].to_s == "retired_read_only"
    else
      errors << "successor CAS state is missing on #{lane}/#{stage}"
    end
  end

  cohorts = Array(document["cohorts"]).select { |row| row.is_a?(Hash) }
  section_count = Integer(document.dig("run", "section_count") || 0)
  canonical_sizes = partition_cohort_sizes(section_count)
  actual_sizes = cohorts.map { |row| Array(row["sections"]).length }
  if canonical_sizes == :invalid || actual_sizes != canonical_sizes
    errors << "cohort partition must be contiguous 2 or 3 and match the canonical partition"
  end
  section_owner = {}
  cohorts.each_with_index do |cohort, index|
    expected_cohort_id = "C#{index + 1}"
    errors << "cohort id must exact-carry canonical #{expected_cohort_id}" unless cohort["cohort_id"].to_s == expected_cohort_id
    sections = Array(cohort["sections"]).map(&:to_s)
    size = sections.length
    if size == 1 && section_count != 1
      errors << "singleton cohort is allowed only for a one-section title"
    elsif size != 1 && ![2, 3].include?(size)
      errors << "cohort #{cohort['cohort_id']} must contain 2 or 3 sections"
    end
    sections.each do |section_id|
      if section_owner.key?(section_id)
        errors << "section #{section_id} mapped more than once"
      else
        section_owner[section_id] = cohort["cohort_id"].to_s
      end
    end
  end
  expected_sections = (1..section_count).map { |index| format("S%02d", index) }
  unless cohorts.flat_map { |cohort| Array(cohort["sections"]).map(&:to_s) } == expected_sections
    errors << "cohort partition must preserve the exact contiguous section roster"
  end

  if graph_runtime
    expected_active_keys = Set.new
    expected_authoring_ids = Set.new
    cohorts.each do |cohort|
      cohort_id = cohort["cohort_id"].to_s
      index = cohort_id.delete_prefix("C")
      stage = cohort["runtime_stage"].to_s
      scheduling_state = cohort["scheduling_state"].to_s
      unless COHORT_RUNTIME_STAGES.include?(stage)
        errors << "cohort #{cohort_id} runtime_stage must be planning_cell or section_cluster_production"
        next
      end
      unless (COHORT_WRITER_REQUIRED_STATES + COHORT_NONWRITER_STATES).include?(scheduling_state)
        errors << "cohort #{cohort_id} scheduling_state is unsupported"
        next
      end

      if stage == "planning_cell"
        lane = "planning_p3_c#{index}"
        authoring_id = "planning_cdd_p3_c#{index}"
      else
        lane = "section_cluster_v_c#{index}"
        authoring_id = "section_cluster_cdd_c#{index}"
      end
      next unless COHORT_WRITER_REQUIRED_STATES.include?(scheduling_state)

      expected_active_keys << [lane, stage, cohort_id]
      expected_authoring_ids << authoring_id
    end

    actual_writer_keys = writers.each_with_object(Set.new) do |row, keys|
      next unless director_lane_cohort_id(row["lane_id"])

      keys << [row["lane_id"].to_s, row["stage"].to_s, row["section_cohort_id"].to_s]
    end
    actual_session_keys = sessions.each_with_object(Set.new) do |row, keys|
      next unless director_lane_cohort_id(row["lane_id"]) && row["state"].to_s == "active_writer"

      keys << [row["lane_id"].to_s, row["stage"].to_s, row["section_cohort_id"].to_s]
    end
    unless actual_writer_keys == expected_active_keys
      errors << "active cohort writer set must exactly equal writer-required roster"
    end
    unless actual_session_keys == expected_active_keys
      errors << "active cohort session set must exactly equal writer-required roster"
    end

    cohort_authoring_ids = Array(document["active_authoring_ids"]).map(&:to_s).select do |id|
      id.match?(/\A(?:planning_cdd_p3_c|section_cluster_cdd_c)[1-9][0-9]*\z/)
    end.to_set
    unless cohort_authoring_ids == expected_authoring_ids
      errors << "active cohort authoring id set must exactly equal writer-required roster"
    end

    expected_active_keys.each do |lane, stage, cohort_id|
      matching_writers = writers.select do |row|
        [row["lane_id"].to_s, row["stage"].to_s, row["section_cohort_id"].to_s] == [lane, stage, cohort_id]
      end
      matching_sessions = sessions.select do |row|
        row["state"].to_s == "active_writer" &&
          [row["lane_id"].to_s, row["stage"].to_s, row["section_cohort_id"].to_s] == [lane, stage, cohort_id]
      end
      errors << "writer-required cohort #{cohort_id}/#{stage} must have exactly one active writer" unless matching_writers.length == 1
      errors << "writer-required cohort #{cohort_id}/#{stage} must have exactly one active session" unless matching_sessions.length == 1
      next unless matching_writers.length == 1 && matching_sessions.length == 1

      writer_id = matching_writers.first["writer_id"].to_s
      session_id = matching_sessions.first["session_id"].to_s
      unless !writer_id.empty? && writer_id == session_id
        errors << "active cohort writer_id must exact-bind the active physical session_id for #{cohort_id}/#{stage}"
      end
    end
  end

  Array(document["succession"]).each do |row|
    next unless row.is_a?(Hash)

    from_cohort = row["from_cohort_id"].to_s
    to_cohort = row["to_cohort_id"].to_s
    errors << "P3-Ci must exact-carry into the same V-Ci cohort" unless from_cohort == to_cohort && !from_cohort.empty?
  end

  pack = document["pack"]
  if pack.is_a?(Hash)
    FORBIDDEN_PACK_KEYS.each do |field|
      errors << "Role Context Pack contains forbidden field: #{field}" if pack.key?(field) && !pack[field].nil?
    end
    %w[source_id locator sha256].each do |field|
      errors << "Role Context Pack missing recoverable #{field}" if pack[field].to_s.strip.empty?
    end
    sha = pack["sha256"].to_s
    errors << "Role Context Pack sha256 is not a SHA-256" unless sha.empty? || sha.match?(/\A[a-f0-9]{64}\z/)
  end

  correction = document["correction"]
  if correction.is_a?(Hash)
    errors << "same-session correction opened a new physical session" if correction["same_session"] == false
    submission = Integer(correction["submission"] || 1)
    errors << "same-package correction exceeded three submissions" if submission > 3
  end

  backpressure = document["backpressure"]
  if backpressure.is_a?(Hash)
    unreviewed = Integer(backpressure["unreviewed_aggregate_manifests"] || 0)
    launched = backpressure["new_launch"] == true
    limit = routing.dig("backpressure", "unreviewed_aggregate_manifest_limit_per_lane") || 2
    errors << "backpressure forbids new launch at unreviewed limit" if unreviewed >= limit && launched
  end

  errors << "Founder gate bypass is HOLD" unless document["gate_bypass"].to_s.empty?
end

case_id = nil
case_expect = nil
case_errors = []
if options[:case]
  case_path = options[:case]
  unless case_path.file?
    errors << "runtime case is missing: #{case_path}"
  else
    runtime_case = load_yaml(case_path)
    case_id = runtime_case["case_id"].to_s
    case_expect = runtime_case["expect"].to_s
    validate_runtime_case(runtime_case, routing, skill_load, graph_source_digest, case_errors)
    if case_expect == "pass"
      errors.concat(case_errors)
    elsif case_expect == "fail"
      wanted = Array(runtime_case["expect_error_substrings"]).map(&:to_s)
      if case_errors.empty?
        errors << "expected runtime case to fail: #{case_id}"
      else
        wanted.each do |fragment|
          errors << "expected error not found: #{fragment}" unless case_errors.any? { |error| error.include?(fragment) }
        end
      end
    else
      errors << "runtime case expect must be pass or fail"
      errors.concat(case_errors)
    end
  end
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "graph_revision" => skill_load["schema_version"],
  "active_graph_source_set_sha256" => graph_source_digest,
  "skill_load_status" => skill_load["status"].to_s,
  "projection_status" => projection["status"].to_s,
  "default_writer" => skill_load.dig("activation", "default_writer").to_s,
  "existing_runs_writer" => routing.dig("writer_boundary", "existing_runs").to_s,
  "new_runs_default_writer" => routing.dig("writer_boundary", "new_runs", "default").to_s,
  "graph_v2_requires" => routing.dig("writer_boundary", "new_runs", "graph_v2_requires").to_s,
  "profile_count" => profiles.length,
  "skill_binding_count" => skill_rows.length,
  "read_binding_count" => read_rows.length,
  "errors" => errors
}
if options[:case]
  result["case_id"] = case_id
  result["case_expect"] = case_expect
  result["case_status"] = case_errors.empty? ? "pass" : "fail"
  result["case_errors"] = case_errors
end

if options[:json]
  puts JSON.pretty_generate(result)
else
  puts "Graph Engineering runtime projection: #{result['status'].upcase}"
  puts "Profiles: #{profiles.length}; skill bindings: #{skill_rows.length}; read bindings: #{read_rows.length}"
  if options[:case]
    puts "Case #{case_id}: expect=#{case_expect} case_status=#{result['case_status']}"
    case_errors.each { |error| warn error }
  end
  errors.each { |error| puts "- #{error}" }
end

exit(errors.empty? ? 0 : 1)
