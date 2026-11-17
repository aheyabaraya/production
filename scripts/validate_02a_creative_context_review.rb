#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"

options = {json: false, repo_root: Pathname.new(__dir__).parent}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: validate_02a_creative_context_review.rb REVIEW [--repo-root ROOT] [--json]"
  opts.on("--repo-root ROOT") { |value| options[:repo_root] = Pathname.new(value) }
  opts.on("--json") { options[:json] = true }
end
parser.parse!

review_path = ARGV.shift
abort parser.to_s if review_path.to_s.empty? || !ARGV.empty?

repo_root = options[:repo_root].expand_path.cleanpath
review_path = Pathname.new(review_path).expand_path.cleanpath
schema_path = Pathname.new(__dir__).parent.join("schemas", "02a-creative-context-review.schema.json")
errors = []

unless review_path.file?
  errors << "review file does not exist: #{review_path}"
end

review = review_path.file? ? YAML.load_file(review_path.to_s) : {}
unless review.is_a?(Hash)
  errors << "review document must be an object"
  review = {}
end

if review_path.file?
  python = Pathname.new(__dir__).join("idol-video-python")
  schema_validator = Pathname.new(__dir__).join("validate_json_schema.py")
  stdout, stderr, status = Open3.capture3(
    python.to_s,
    schema_validator.to_s,
    schema_path.to_s,
    review_path.to_s,
    chdir: repo_root.to_s
  )
  errors << "JSON Schema validation failed: #{[stdout, stderr].join(" ").strip}" unless status.success?
end

def resolve_source_path(repo_root, value)
  path = Pathname.new(value.to_s)
  path = repo_root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def canonical_json_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      result[key] = canonical_json_value(value[key])
    end
  when Array
    value.map { |item| canonical_json_value(item) }
  else
    value
  end
end

def review_projection_sha256(review)
  projection = {
    "schema_version" => review["schema_version"],
    "content_id" => review["content_id"],
    "source_02a" => review["source_02a"],
    "review_policy" => review["review_policy"],
    "route" => review["route"],
    "section_reviews" => review["section_reviews"],
    "whole_film_review" => review["whole_film_review"]
  }
  Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(projection)))
end

def structured_value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(value)))
end

def section_review_content_projection(row)
  projection = Marshal.load(Marshal.dump(row))
  projection.delete("source_section_value_sha256")
  projection.delete("review_lineage")
  projection
end

def load_carried_section_review(repo_root:, current_review_path:, row:, section_id:, expected_section_sha:)
  lineage = row["review_lineage"]
  return [nil, nil, nil, []] unless lineage.is_a?(Hash) && lineage["mode"].to_s == "carried_forward_unchanged_section"

  errors = []
  source_ref = lineage["source_review"]
  unless source_ref.is_a?(Hash)
    return [nil, nil, nil, ["#{section_id}: carried review requires source_review"]]
  end
  source_path = resolve_source_path(repo_root, source_ref["path"])
  root_prefix = "#{repo_root}#{File::SEPARATOR}"
  if source_path == current_review_path
    errors << "#{section_id}: carried review cannot point to itself"
    return [nil, source_path, nil, errors]
  end
  unless source_path.to_s == repo_root.to_s || source_path.to_s.start_with?(root_prefix)
    errors << "#{section_id}: carried source review escapes repository root"
    return [nil, source_path, nil, errors]
  end
  unless source_path.file?
    errors << "#{section_id}: carried source review does not exist"
    return [nil, source_path, nil, errors]
  end
  actual_sha = Digest::SHA256.file(source_path).hexdigest
  errors << "#{section_id}: carried source review SHA-256 is stale" unless actual_sha == source_ref["sha256"].to_s
  prior = YAML.load_file(source_path.to_s)
  unless prior.is_a?(Hash)
    errors << "#{section_id}: carried source review must be an object"
    return [nil, source_path, nil, errors]
  end
  prior_row = Array(prior["section_reviews"]).find do |candidate|
    candidate.is_a?(Hash) && candidate["section_id"].to_s == section_id
  end
  unless prior_row
    errors << "#{section_id}: carried source review has no matching section row"
    return [prior, source_path, nil, errors]
  end
  declared_row_sha = lineage["source_section_review_value_sha256"].to_s
  errors << "#{section_id}: carried section review value SHA-256 is stale" unless declared_row_sha == structured_value_sha256(prior_row)
  errors << "#{section_id}: prior section review is not passed" unless prior_row["verdict"].to_s == "pass"
  unless prior_row["source_section_value_sha256"].to_s == expected_section_sha
    errors << "#{section_id}: prior review does not bind the unchanged current section value"
  end
  unless canonical_json_value(section_review_content_projection(row)) ==
         canonical_json_value(section_review_content_projection(prior_row))
    errors << "#{section_id}: carried section review content differs from the bound prior row"
  end
  [prior, source_path, prior_row, errors]
end

def json_pointer_exists?(document, pointer)
  return true if pointer.to_s.empty?
  return false unless pointer.to_s.start_with?("/")

  current = document
  pointer.to_s.split("/")[1..].each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    if current.is_a?(Hash) && current.key?(token)
      current = current[token]
    elsif current.is_a?(Array) && token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < current.length
      current = current[token.to_i]
    else
      return false
    end
  end
  true
end

def validate_execution_record(repo_root:, receipt:, expected_owner:, expected_profile:, expected_sections:, expected_source_sha:, expected_session_type:, expected_role_id:, expected_producer:)
  errors = []
  unless receipt.is_a?(Hash)
    return ["#{expected_sections.join(',')}: execution_receipt is required for active runner-bound review", nil, nil]
  end

  errors << "#{expected_sections.join(',')}: execution receipt must assign the exact review scope" unless Array(receipt["assigned_section_ids"]).map(&:to_s).sort == expected_sections.sort
  errors << "#{expected_sections.join(',')}: execution receipt source_02a_sha256 must match source 02A" unless receipt["source_02a_sha256"].to_s == expected_source_sha
  errors << "#{expected_sections.join(',')}: execution receipt session_type must be #{expected_session_type}" unless receipt["session_type"].to_s == expected_session_type
  errors << "#{expected_sections.join(',')}: execution receipt role_id must be #{expected_role_id}" unless receipt["role_id"].to_s == expected_role_id
  errors << "#{expected_sections.join(',')}: execution receipt must be completed" unless receipt["completed"] == true

  record_ref = receipt["execution_record"]
  unless record_ref.is_a?(Hash)
    errors << "#{expected_sections.join(',')}: execution_receipt.execution_record is required for active runner-bound review"
    return [errors, nil, receipt["session_id"].to_s]
  end

  record_path = resolve_source_path(repo_root, record_ref["path"])
  root_prefix = "#{repo_root}#{File::SEPARATOR}"
  unless record_path.to_s == repo_root.to_s || record_path.to_s.start_with?(root_prefix)
    errors << "#{expected_sections.join(',')}: execution record escapes repository root"
    return [errors, record_path, receipt["session_id"].to_s]
  end
  unless record_path.file?
    errors << "#{expected_sections.join(',')}: execution record does not exist: #{record_path}"
    return [errors, record_path, receipt["session_id"].to_s]
  end

  actual_sha = Digest::SHA256.file(record_path.to_s).hexdigest
  errors << "#{expected_sections.join(',')}: execution record sha256 mismatch" unless actual_sha == record_ref["sha256"].to_s
  record = YAML.load_file(record_path.to_s)
  unless record.is_a?(Hash)
    errors << "#{expected_sections.join(',')}: execution record must be an object"
    return [errors, record_path, receipt["session_id"].to_s]
  end

  comparisons = {
    "schema_version" => "idol-llm-review-execution-record.v2",
    "producer" => expected_producer,
    "surface_owner" => expected_owner,
    "session_type" => expected_session_type,
    "role_id" => expected_role_id,
    "session_id" => receipt["session_id"].to_s,
    "profile" => expected_profile,
    "source_02a_sha256" => expected_source_sha,
    "completion_state" => "completed"
  }
  comparisons.each do |field, expected|
    errors << "#{expected_sections.join(',')}: execution record #{field} must match the bound review receipt" unless record[field].to_s == expected.to_s
  end
  errors << "#{expected_sections.join(',')}: execution record producer must match receipt" unless record_ref["producer"].to_s == expected_producer
  errors << "#{expected_sections.join(',')}: execution record assigned_section_ids must exact-cover the review scope" unless Array(record["assigned_section_ids"]).map(&:to_s).sort == expected_sections.sort
  errors << "#{expected_sections.join(',')}: execution record requires an exact provider profile snapshot" unless record["provider_profile_snapshot_ref"].to_s.match?(%r{\Aautomation/harness-provider-profile-registry\.yaml#/logical_profiles/director_deep/providers/(?:codex|grok)(?:/.*)?\z})
  errors << "#{expected_sections.join(',')}: execution record provider capability snapshot hash is invalid" unless record["provider_capability_snapshot_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
  expected_stage = expected_session_type.include?("section") ? "02a_section_context" : "02a_whole_film_reconciliation"
  errors << "#{expected_sections.join(',')}: execution record review_stage must match 02A review scope" unless record["review_stage"].to_s == expected_stage
  errors << "#{expected_sections.join(',')}: execution record may not claim a canonical semantic write" unless record["canonical_semantic_write_performed"] == false

  [errors, record_path, receipt["session_id"].to_s]
end

source_ref = review["source_02a"].is_a?(Hash) ? review["source_02a"] : {}
source_path = resolve_source_path(repo_root, source_ref["path"])
source = {}
if !source_path.file?
  errors << "source_02a.path does not exist: #{source_path}"
else
  actual_sha = Digest::SHA256.file(source_path.to_s).hexdigest
  errors << "source_02a.sha256 mismatch: expected #{source_ref['sha256']}, got #{actual_sha}" unless source_ref["sha256"].to_s == actual_sha
  source = YAML.load_file(source_path.to_s)
  unless source.is_a?(Hash)
    errors << "source_02a must be an object"
    source = {}
  end
end

unless source.empty?
  errors << "content_id does not match source 02A" unless review["content_id"].to_s == source["content_id"].to_s
  errors << "source_02a.schema_version does not match source 02A" unless source_ref["schema_version"].to_s == source["schema_version"].to_s
end

core_cuts_by_section = Hash.new { |hash, key| hash[key] = [] }
all_core_cut_ids = []
all_branch_cut_ids = []
Array(source["master_storyboard"]).each do |core_cut|
  next unless core_cut.is_a?(Hash)

  core_cut_id = core_cut["core_cut_id"].to_s
  all_core_cut_ids << core_cut_id unless core_cut_id.empty?
  section_ids = [core_cut.dig("imported_core", "section_id").to_s].reject(&:empty?)
  fallback = core_cut_id[/_(S[0-9]{2}[A-Z]?)_/, 1]
  section_ids = [fallback] if section_ids.empty? && fallback
  errors << "#{core_cut_id}: source section is missing" if section_ids.empty?
  section_ids.each { |section_id| core_cuts_by_section[section_id] << core_cut_id }
  Array(core_cut.dig("compile_seed", "branch_cuts")).each do |branch_cut|
    all_branch_cut_ids << branch_cut["branch_cut_id"].to_s if branch_cut.is_a?(Hash)
  end
end

review_rows = Array(review["section_reviews"]).select { |row| row.is_a?(Hash) }
review_section_ids = review_rows.map { |row| row["section_id"].to_s }
duplicate_sections = review_section_ids.group_by(&:itself).select { |id, rows| !id.empty? && rows.length > 1 }.keys
errors << "section_reviews repeats section ids: #{duplicate_sections.join(', ')}" unless duplicate_sections.empty?

expected_sections = core_cuts_by_section.keys.sort
declared_sections = review_section_ids.sort
errors << "section_reviews must exact-cover source 02A sections: expected #{expected_sections.join(', ')}, got #{declared_sections.join(', ')}" unless declared_sections == expected_sections

route = review["route"].is_a?(Hash) ? review["route"] : {}
active_v7 = review["schema_version"].to_s == "idol-02a-creative-context-review.v7"
active_runner_bound = active_v7
errors << "only idol-02a-creative-context-review.v7 is active" unless active_v7

source_01 = nil
active_front_planning_02a = source["schema_version"].to_s == Idol02AStoryboardContract::ACTIVE_SCHEMA_VERSION
source_01_label = if active_front_planning_02a
                    source.dig("source_01_direction", "path").to_s
                  else
                    source.dig("source_direction_contract", "source_01_path").to_s
                  end
if active_v7
  source_01_sha = if active_front_planning_02a
                    source.dig("source_01_direction", "sha256").to_s
                  else
                    source.dig("source_direction_contract", "source_01_sha256").to_s
                  end
  if source_01_label.empty? || source_01_sha.empty?
    errors << "active v7 source 02A requires hash-bound source_direction_contract 01 truth"
  else
    source_01_path = resolve_source_path(repo_root, source_01_label)
    root_prefix = "#{repo_root}#{File::SEPARATOR}"
    if !source_01_path.to_s.start_with?(root_prefix)
      errors << "source_direction_contract.source_01_path escapes repository root"
    elsif !source_01_path.file?
      errors << "source_direction_contract.source_01_path does not exist: #{source_01_path}"
    else
      actual_source_01_sha = Digest::SHA256.file(source_01_path.to_s).hexdigest
      if !active_front_planning_02a && actual_source_01_sha != source_01_sha
        errors << "source_direction_contract.source_01_sha256 mismatch"
      end
      loaded_source_01 = YAML.load_file(source_01_path.to_s)
      source_01 = loaded_source_01 if loaded_source_01.is_a?(Hash)
      errors << "source_direction_contract source 01 must be an object" unless source_01
    end
  end
end

section_session_ids = []
execution_record_paths = []
review_rows.each do |row|
  section_id = row["section_id"].to_s
  expected_core_cut_ids = core_cuts_by_section[section_id].uniq.sort
  declared_core_cut_ids = Array(row["source_core_cut_ids"]).map(&:to_s).sort
  unless declared_core_cut_ids == expected_core_cut_ids
    errors << "#{section_id}: source_core_cut_ids must exact-cover source 02A Core Cuts"
  end
  expected_section_sha = Idol02AStoryboardContract.section_review_sha256(source, section_id)
  declared_section_sha = row["source_section_value_sha256"].to_s
  if !declared_section_sha.empty? && declared_section_sha != expected_section_sha
    errors << "#{section_id}: source_section_value_sha256 is stale"
  end
  lineage_mode = row.dig("review_lineage", "mode").to_s
  carried_review = lineage_mode == "carried_forward_unchanged_section"
  prior_review = nil
  expected_receipt_source_sha = source_ref["sha256"].to_s
  if carried_review
    errors << "#{section_id}: carried review requires source_section_value_sha256" if declared_section_sha.empty?
    prior_review, _prior_path, _prior_row, carry_errors = load_carried_section_review(
      repo_root: repo_root,
      current_review_path: review_path,
      row: row,
      section_id: section_id,
      expected_section_sha: expected_section_sha
    )
    errors.concat(carry_errors)
    if prior_review
      errors << "#{section_id}: carried review owner differs from the current route" unless prior_review.dig("route", "surface_owner").to_s == route["surface_owner"].to_s
      expected_receipt_source_sha = prior_review.dig("source_02a", "sha256").to_s
    end
  elsif !lineage_mode.empty? && lineage_mode != "current_source_review"
    errors << "#{section_id}: review_lineage mode is invalid"
  end

  if active_v7
    core_import_review = row["core_import_immutability_review"]
    unless core_import_review.is_a?(Hash)
      errors << "#{section_id}: active v7 requires core_import_immutability_review"
    else
      reviewed_core_cut_ids = Array(core_import_review["reviewed_core_cut_ids"]).map(&:to_s).sort
      unless reviewed_core_cut_ids == expected_core_cut_ids
        errors << "#{section_id}: core import immutability review must exact-cover imported 01 Core Cuts"
      end
      if row["verdict"].to_s == "pass"
        errors << "#{section_id}: passing review requires imported Core immutability pass" unless core_import_review["verdict"].to_s == "pass"
        errors << "#{section_id}: passing review requires exactly one passed 01 primary image per Core" unless core_import_review["one_image_per_core_verified"] == true
        errors << "#{section_id}: passing review requires exact Core reference bindings" unless core_import_review["core_reference_binding_verified"] == true
        errors << "#{section_id}: passing review cannot detect a 02A Core mutation" unless core_import_review["02a_core_mutation_detected"] == false
      end
    end

    upstream_review = row["upstream_realization_review"]
    unless upstream_review.is_a?(Hash)
      errors << "#{section_id}: active v7 requires upstream_realization_review"
    else
      reviewed_core_cut_ids = Array(upstream_review["reviewed_core_cut_ids"]).map(&:to_s).sort
      unless reviewed_core_cut_ids == expected_core_cut_ids
        errors << "#{section_id}: upstream_realization_review.reviewed_core_cut_ids must exact-cover source 02A Core Cuts"
      end

      source_01_field_refs = Array(upstream_review["source_01_field_refs"]).map { |value| value.to_s.strip }.reject(&:empty?)
      errors << "#{section_id}: upstream_realization_review requires at least two unique canonical 01 field refs" unless source_01_field_refs.uniq.length >= 2
      source_01_field_refs.uniq.each do |field_ref|
        pointer = if !source_01_label.empty? && field_ref.start_with?("#{source_01_label}#")
                    field_ref.delete_prefix("#{source_01_label}#")
                  elsif field_ref.start_with?("01#")
                    field_ref.delete_prefix("01#")
                  end
        if pointer.to_s.empty? || !source_01 || !json_pointer_exists?(source_01, pointer)
          errors << "#{section_id}: upstream_realization_review source 01 field ref does not resolve: #{field_ref}"
        end
      end

      if row["verdict"].to_s == "pass"
        unless upstream_review["core_cut_realization_verdict"].to_s == "pass"
          errors << "#{section_id}: a passing section requires core_cut_realization_verdict pass"
        end
        errors << "#{section_id}: a passing section cannot detect script substitution" unless upstream_review["script_substitution_detected"] == false
      end
    end

    core_branch_review = row["core_branch_realization_review"]
    unless core_branch_review.is_a?(Hash)
      errors << "#{section_id}: active v7 requires core_branch_realization_review"
    else
      reviewed_core_cut_ids = Array(core_branch_review["reviewed_core_cut_ids"]).map(&:to_s).sort
      section_branch_ids = Array(source["master_storyboard"]).select do |core_cut|
        core_cut.is_a?(Hash) && core_cut.dig("imported_core", "section_id").to_s == section_id
      end.flat_map do |core_cut|
        Array(core_cut.dig("compile_seed", "branch_cuts")).map { |branch_cut| branch_cut["branch_cut_id"].to_s }
      end.sort
      reviewed_branch_cut_ids = Array(core_branch_review["reviewed_branch_cut_ids"]).map(&:to_s).sort
      errors << "#{section_id}: core-branch review must exact-cover Core Cuts" unless reviewed_core_cut_ids == expected_core_cut_ids
      errors << "#{section_id}: core-branch review must exact-cover Branch Cuts" unless reviewed_branch_cut_ids == section_branch_ids
      if row["verdict"].to_s == "pass"
        errors << "#{section_id}: passing review requires Core-event fidelity pass" unless core_branch_review["core_event_fidelity_verdict"] == "pass"
        errors << "#{section_id}: passing review requires Branch-Cut distinctness pass" unless core_branch_review["branch_distinctness_verdict"] == "pass"
        errors << "#{section_id}: passing review cannot retain a start/end template" unless core_branch_review["start_end_template_detected"] == false
        errors << "#{section_id}: passing review cannot place a different governing event under the same Core Cut" unless core_branch_review["event_theft_detected"] == false
      end
    end

    storyline_review = row["storyline_realization_review"]
    source_shard = Idol02AStoryboardContract.find_section_shard(source, section_id: section_id)
    unless storyline_review.is_a?(Hash)
      errors << "#{section_id}: active v7 requires storyline_realization_review"
    else
      section_alignment_value = source_shard.to_h.dig("section_alignment_projection", "projected_value")
      expected_section_alignment_sha = Idol02AStoryboardContract.value_sha256(section_alignment_value)
      unless storyline_review["source_section_alignment_sha256"].to_s == expected_section_alignment_sha
        errors << "#{section_id}: storyline review section alignment hash is stale"
      end
      expected_planning_hashes = Array(source_shard.to_h["planning_cut_alignment_projections"]).map do |projection|
        {
          "planning_cut_id" => projection["planning_cut_id"],
          "source_key_screen_id" => projection["source_key_screen_id"],
          "value_sha256" => Idol02AStoryboardContract.value_sha256(projection["projected_value"])
        }
      end
      unless storyline_review["source_planning_cut_alignment_hashes"] == expected_planning_hashes
        errors << "#{section_id}: storyline review planning-cut hashes must exact-cover source order and values"
      end
      unless Array(storyline_review["reviewed_branch_cut_ids"]).map(&:to_s).sort == section_branch_ids
        errors << "#{section_id}: storyline review must exact-cover Branch Cuts"
      end
      if row["verdict"].to_s == "pass"
        errors << "#{section_id}: passing review requires detailed storyline preservation pass" unless storyline_review["detailed_storyline_preservation_verdict"].to_s == "pass"
        errors << "#{section_id}: passing review requires coherent Branch expansion pass" unless storyline_review["branch_expansion_coherence_verdict"].to_s == "pass"
        errors << "#{section_id}: passing review requires 02B prompt readiness pass" unless storyline_review["02b_prompt_readiness_verdict"].to_s == "pass"
      end
    end
  end

  profile = row.dig("reviewer", "profile").to_s
  errors << "#{section_id}: reviewer.profile must match route.section_reviewer_profile" unless profile == route["section_reviewer_profile"].to_s
  errors << "#{section_id}: active review requires one integrated review_summary" if active_runner_bound && row["review_summary"].to_s.strip.empty?

  if active_runner_bound
    owner = route["surface_owner"].to_s
    if owner == "codex"
      session_type = "codex_section_review"
      role_id = "idol-02a-section-context-reviewer"
      producer = "registered_codex_reviewer_runner"
    else
      session_type = "grok_root_section_review"
      role_id = "grok-root-section-context-reviewer"
      producer = "registered_grok_root_reviewer_runner"
    end
    receipt_errors, record_path, session_id = validate_execution_record(
      repo_root: repo_root,
      receipt: row.dig("reviewer", "execution_receipt"),
      expected_owner: owner,
      expected_profile: profile,
      expected_sections: [section_id],
      expected_source_sha: expected_receipt_source_sha,
      expected_session_type: session_type,
      expected_role_id: role_id,
      expected_producer: producer
    )
    errors.concat(receipt_errors)
    execution_record_paths << record_path.to_s if record_path
    section_session_ids << session_id unless carried_review || session_id.to_s.empty?
  end

  Array(row["findings"]).each do |finding|
    next unless finding.is_a?(Hash)
    unknown_core_cuts = Array(finding["affected_core_cut_ids"]).map(&:to_s) - all_core_cut_ids
    unknown_branches = Array(finding["affected_branch_cut_ids"]).map(&:to_s) - all_branch_cut_ids
    errors << "#{finding['finding_id']}: unknown affected_core_cut_ids #{unknown_core_cuts.join(', ')}" unless unknown_core_cuts.empty?
    errors << "#{finding['finding_id']}: unknown affected_branch_cut_ids #{unknown_branches.join(', ')}" unless unknown_branches.empty?
  end
end

whole = review["whole_film_review"].is_a?(Hash) ? review["whole_film_review"] : {}
whole_sections = Array(whole["section_ids"]).map(&:to_s).sort
errors << "whole_film_review.section_ids must exact-cover all source 02A sections" unless whole_sections == expected_sections
errors << "whole_film_review reviewer.profile must match route.whole_film_reviewer_profile" unless whole.dig("reviewer", "profile").to_s == route["whole_film_reviewer_profile"].to_s
errors << "whole_film_review active review requires one integrated review_summary" if active_runner_bound && whole["review_summary"].to_s.strip.empty?
if active_v7
  storyline_progression = whole["storyline_progression_review"]
  unless storyline_progression.is_a?(Hash)
    errors << "whole_film_review active v7 requires storyline_progression_review"
  else
    whole_readout = source.dig(
      "founder_visual_alignment_projection",
      "projected_value",
      "whole_film_readout"
    )
    expected_whole_sha = Idol02AStoryboardContract.value_sha256(whole_readout)
    unless storyline_progression["source_whole_film_readout_sha256"].to_s == expected_whole_sha
      errors << "whole_film_review storyline progression hash is stale"
    end
    unless Array(storyline_progression["reviewed_section_ids"]).map(&:to_s).sort == expected_sections
      errors << "whole_film_review storyline progression must exact-cover sections"
    end
    if whole["verdict"].to_s == "pass" && storyline_progression["progressive_detail_verdict"].to_s != "pass"
      errors << "passing whole-film review requires progressive storyline detail pass"
    end
  end
end
if active_runner_bound
  owner = route["surface_owner"].to_s
  profile = whole.dig("reviewer", "profile").to_s
  session_type = owner == "codex" ? "codex_root_reconciliation" : "root_reconciliation"
  role_id = owner == "codex" ? "idol-02a-whole-film-reconciler" : "grok-root-whole-film-reconciler"
  producer = if owner == "codex"
    "registered_codex_reviewer_runner"
  else
    "registered_grok_root_reviewer_runner"
  end
  receipt_errors, record_path, root_session_id = validate_execution_record(
    repo_root: repo_root,
    receipt: whole.dig("reviewer", "execution_receipt"),
    expected_owner: owner,
    expected_profile: profile,
    expected_sections: expected_sections,
    expected_source_sha: source_ref["sha256"].to_s,
    expected_session_type: session_type,
    expected_role_id: role_id,
    expected_producer: producer
  )
  errors.concat(receipt_errors)
  execution_record_paths << record_path.to_s if record_path
  unless section_session_ids.all? { |session_id| session_id == root_session_id }
    errors << "active v7 requires every newly reviewed section and whole-film reconciliation to stay in one continuing overall-director session"
  end
  duplicate_records = execution_record_paths.group_by(&:itself).select { |record_path_value, rows| !record_path_value.empty? && rows.length > 1 }.keys
  errors << "active execution records must be unique per section and whole-film review: #{duplicate_records.join(', ')}" unless duplicate_records.empty?
end
Array(whole["findings"]).each do |finding|
  next unless finding.is_a?(Hash)
  unknown_core_cuts = Array(finding["affected_core_cut_ids"]).map(&:to_s) - all_core_cut_ids
  unknown_branches = Array(finding["affected_branch_cut_ids"]).map(&:to_s) - all_branch_cut_ids
  errors << "#{finding['finding_id']}: unknown affected_core_cut_ids #{unknown_core_cuts.join(', ')}" unless unknown_core_cuts.empty?
  errors << "#{finding['finding_id']}: unknown affected_branch_cut_ids #{unknown_branches.join(', ')}" unless unknown_branches.empty?
end

if active_runner_bound
  founder_gate = review["founder_gate"].is_a?(Hash) ? review["founder_gate"] : {}
  founder_html_path = resolve_source_path(repo_root, founder_gate["review_html_path"])
  root_prefix = "#{repo_root}#{File::SEPARATOR}"
  if !founder_html_path.to_s.start_with?(root_prefix)
    errors << "founder review HTML escapes repository root"
  elsif !founder_html_path.file?
    errors << "founder review HTML does not exist: #{founder_html_path}"
  else
    founder_html_sha = founder_gate["review_html_sha256"].to_s
    errors << "active runner-bound founder_gate.review_html_sha256 is required" if founder_html_sha.empty?
    actual_founder_html_sha = Digest::SHA256.file(founder_html_path.to_s).hexdigest
    errors << "founder review HTML sha256 mismatch" unless founder_html_sha == actual_founder_html_sha
    expected_projection_sha = review_projection_sha256(review)
    declared_projection_sha = founder_gate["review_projection_sha256"].to_s
    errors << "active runner-bound founder_gate.review_projection_sha256 is required" if declared_projection_sha.empty?
    errors << "founder review projection sha256 mismatch" unless declared_projection_sha == expected_projection_sha
    html = founder_html_path.read
    projection_marker = /data-idol-review-projection-sha256=([\"'])#{Regexp.escape(expected_projection_sha)}\1/
    errors << "founder review HTML is not bound to the exact section and whole-film review projection" unless html.match?(projection_marker)
  end
end

result = {
  "valid" => errors.empty?,
  "review_path" => review_path.to_s,
  "source_02a_path" => source_path.to_s,
  "section_count" => expected_sections.length,
  "section_review_count" => review_rows.length,
  "core_cut_count" => all_core_cut_ids.length,
  "branch_cut_count" => all_branch_cut_ids.length,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
else
  puts(errors.empty? ? "02A creative context review: valid" : "02A creative context review: invalid")
  errors.each { |error| warn "- #{error}" }
end
exit(errors.empty? ? 0 : 1)
