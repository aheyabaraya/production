#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"

REPO_ROOT = Pathname.new(__dir__).join("..").expand_path
FOUNDER_INTERVENTION_VALIDATOR = REPO_ROOT.join("scripts", "validate_founder_intervention_receipt.rb")
SCHEMA_VALIDATOR = REPO_ROOT.join("scripts", "validate_json_schema.py")
PYTHON_RUNNER = REPO_ROOT.join("scripts", "idol-video-python")
LLM_REVIEW_EXECUTION_SCHEMA = REPO_ROOT.join("schemas", "llm-review-execution-record.schema.json")

options = {root: Pathname.new(Dir.pwd).expand_path}
OptionParser.new do |parser|
  parser.banner = "usage: scripts/validate_video_prompt_section_qa_readiness.rb PATH_TO_03v-section-video-prompt-qa.yaml [--root PATH]"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
end.parse!

qa_arg = ARGV.shift
abort "ERROR: PATH_TO_03v-section-video-prompt-qa.yaml is required" if qa_arg.to_s.strip.empty?

root = options[:root].cleanpath
qa_path = Pathname.new(qa_arg)
qa_path = root.join(qa_path) unless qa_path.absolute?
qa_path = qa_path.cleanpath

def load_yaml_hash(path, label)
  doc = YAML.safe_load(path.read, aliases: true)
  return doc if doc.is_a?(Hash)

  raise ArgumentError, "#{label} must be a YAML mapping: #{path}"
rescue Errno::ENOENT
  raise ArgumentError, "#{label} is not readable: #{path}"
rescue Psych::SyntaxError => e
  raise ArgumentError, "#{label} YAML syntax error: #{e.message}"
end

def resolve_path(root, value)
  path = Pathname.new(value.to_s)
  path = root.join(path) unless path.absolute?
  path.cleanpath
end

def normalized_path(root, value)
  resolve_path(root, value).expand_path.to_s
end

def validate_hashed_yaml_ref(root, ref, errors, label)
  unless ref.is_a?(Hash) && !ref["path"].to_s.strip.empty? && ref["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
    errors << "#{label} path/sha256 is required"
    return [nil, nil]
  end

  path = resolve_path(root, ref["path"])
  unless path.file?
    errors << "#{label} is not readable: #{ref['path']}"
    return [path, nil]
  end

  actual_sha = Digest::SHA256.file(path.to_s).hexdigest
  errors << "#{label} sha256 is stale" unless actual_sha == ref["sha256"].to_s
  document = load_yaml_hash(path, label)
  [path, document]
rescue ArgumentError => e
  errors << e.message
  [path, nil]
end

def validate_review_execution_record(root:, ref:, label:, expected_sections:, expected_manifest_sha:, expected_storyboard_sha:, expected_production_cut_types:, review_owner:, errors:)
  path, record = validate_hashed_yaml_ref(root, ref, errors, label)
  return unless path&.file? && record

  stdout, stderr, status = Open3.capture3(
    PYTHON_RUNNER.to_s,
    SCHEMA_VALIDATOR.to_s,
    LLM_REVIEW_EXECUTION_SCHEMA.to_s,
    path.to_s,
    chdir: REPO_ROOT.to_s
  )
  unless status.success?
    detail = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
    errors << "#{label} must validate as active idol-llm-review-execution-record.v2: #{detail}"
    return
  end

  errors << "#{label} must use active idol-llm-review-execution-record.v2" unless record["schema_version"].to_s == "idol-llm-review-execution-record.v2"
  errors << "#{label} must be a CDD 03V playback review" unless %w[idol-03v-cdd-playback-reviewer grok-03v-cdd-playback-reviewer].include?(record["role_id"].to_s)
  errors << "#{label} assigned_section_ids must exact-bind its QA scope" unless Array(record["assigned_section_ids"]).map(&:to_s) == expected_sections
  errors << "#{label} source 03V manifest SHA-256 differs from section QA" unless record["source_03v_video_prompt_manifest_sha256"].to_s == expected_manifest_sha
  errors << "#{label} source storyboard-assist SHA-256 differs from the manifest" unless record["source_03v_storyboard_assist_sha256"].to_s == expected_storyboard_sha
  unless Array(record["source_03v_production_cut_types"]).map(&:to_s) == expected_production_cut_types
    errors << "#{label} Production Cut types must exact-bind the manifest scope"
  end
  errors << "#{label} provider snapshot ref differs from section QA review_owner" unless record["provider_profile_snapshot_ref"].to_s == review_owner["provider_profile_snapshot_ref"].to_s
  errors << "#{label} provider snapshot SHA-256 differs from section QA review_owner" unless record["provider_capability_snapshot_sha256"].to_s == review_owner["provider_capability_snapshot_sha256"].to_s
  errors << "#{label} must return to CDD" unless record["return_recipient_role"].to_s == "creative_development_director"
end

begin
  qa = load_yaml_hash(qa_path, "section QA")
rescue ArgumentError => e
  warn "ERROR: #{e.message}"
  exit 1
end

errors = []
schema_version = qa["schema_version"].to_s
active_v6 = schema_version == "idol_video_prompt_section_qa.v6"
contextual_review = active_v6 && qa["review_mode"].to_s == "contextual_llm_section_and_whole_timeline"
founder_direct_review = active_v6 && qa["review_mode"].to_s == "founder_direct_delta"

unless active_v6
  errors << "#{schema_version.empty? ? 'missing schema_version' : schema_version} is historical index-bound or pre-Production-Cut evidence and cannot satisfy active readiness; active schema is idol_video_prompt_section_qa.v6"
end
if active_v6 && !contextual_review && !founder_direct_review
  errors << "review_mode must be contextual_llm_section_and_whole_timeline or founder_direct_delta"
end

overall_status = qa["overall_status"].to_s
errors << "overall_status=#{overall_status.inspect}; expected pass" unless overall_status == "pass"

source_manifest = nil
source_manifest_path = nil
if active_v6
  source_path_value = qa["source_video_prompt_manifest_path"].to_s
  source_manifest_path = resolve_path(root, source_path_value)
  if !source_manifest_path.file?
    errors << "source_video_prompt_manifest_path is not readable: #{source_path_value}"
  else
    actual_sha = Digest::SHA256.file(source_manifest_path.to_s).hexdigest
    unless qa["source_video_prompt_manifest_sha256"].to_s == actual_sha
      errors << "source_video_prompt_manifest_sha256 does not match source_video_prompt_manifest_path"
    end
    begin
      source_manifest = load_yaml_hash(source_manifest_path, "source video prompt manifest")
      unless source_manifest["schema_version"].to_s == "idol_video_prompt_manifest.v8"
        errors << "source video prompt manifest must use idol_video_prompt_manifest.v8"
      end
      unless source_manifest["content_id"].to_s == qa["content_id"].to_s
        errors << "source video prompt manifest content_id differs from section QA"
      end
    rescue ArgumentError => e
      errors << e.message
    end
  end
end

sections = qa["sections"]
unless sections.is_a?(Array) && !sections.empty?
  errors << "sections must contain at least one section QA record"
  sections = []
end

section_status_failures = []

sections.each_with_index do |section, idx|
  unless section.is_a?(Hash)
    errors << "sections[#{idx}] must be a mapping"
    next
  end

  key = section["section_key"].to_s
  label = key.empty? ? "sections[#{idx}]" : key
  status = section["status"].to_s
  section_status_failures << "#{label}=#{status.empty? ? 'missing' : status}" unless status == "pass"

  if contextual_review
    errors << "#{label}: review_summary is required" if section["review_summary"].to_s.strip.empty?
    errors << "#{label}: findings must be an array" unless section["findings"].is_a?(Array)
    record_ref = section["review_execution_record"]
    unless record_ref.is_a?(Hash) && !record_ref["path"].to_s.strip.empty? && record_ref["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
      errors << "#{label}: review_execution_record path/sha256 is required"
    end
  elsif founder_direct_review
    errors << "#{label}: reviewed_prompt_count must be at least 1" unless section["reviewed_prompt_count"].to_i >= 1
    errors << "#{label}: cue_ids must contain the affected 03V cues" unless section["cue_ids"].is_a?(Array) && !section["cue_ids"].empty?
  end
end

if source_manifest
  manifest_sections = Array(source_manifest["section_shards"])
  manifest_section_ids = manifest_sections.map { |row| row.is_a?(Hash) ? row["section_id"].to_s : "" }
  qa_section_ids = sections.map { |row| row.is_a?(Hash) ? row["section_key"].to_s : "" }
  errors << "section QA must exact-cover active 03V manifest sections in order" unless qa_section_ids == manifest_section_ids

  sections.each_with_index do |section, index|
    next unless section.is_a?(Hash)

    expected_cue_ids = Array(manifest_sections[index].to_h["cue_ids"]).map(&:to_s)
    actual_cue_ids = Array(section["cue_ids"]).map(&:to_s)
    label = section["section_key"].to_s.empty? ? "sections[#{index}]" : section["section_key"].to_s
    errors << "#{label}: cue_ids must exact-cover the active 03V manifest section in order" unless actual_cue_ids == expected_cue_ids
    unless section["reviewed_prompt_count"].to_i == expected_cue_ids.length
      errors << "#{label}: reviewed_prompt_count must equal its active 03V cue count"
    end
  end
end

if contextual_review
  errors << "review_mode must be contextual_llm_section_and_whole_timeline" unless qa["review_mode"].to_s == "contextual_llm_section_and_whole_timeline"
  review_owner = qa["review_owner"]
  unless review_owner.is_a?(Hash)
    errors << "review_owner must be a provider-neutral CDD authority snapshot"
  else
    errors << "review_owner.logical_role must be creative_development_director" unless review_owner["logical_role"].to_s == "creative_development_director"
    errors << "review_owner.logical_profile_alias must be director_deep" unless review_owner["logical_profile_alias"].to_s == "director_deep"
    errors << "review_owner.automatic_fallback must be none" unless review_owner["automatic_fallback"].to_s == "none"
    provider_ref = review_owner["provider_profile_snapshot_ref"].to_s
    expected_prefix = "automation/harness-provider-profile-registry.yaml#/logical_profiles/director_deep/providers/"
    errors << "review_owner.provider_profile_snapshot_ref must bind the director_deep registry" unless provider_ref.start_with?(expected_prefix)
    registry_path = REPO_ROOT.join(provider_ref.split("#", 2).first.to_s).cleanpath
    if !registry_path.file?
      errors << "review_owner provider profile registry is not readable"
    else
      registry_sha = Digest::SHA256.file(registry_path.to_s).hexdigest
      errors << "review_owner.provider_capability_snapshot_sha256 is stale" unless review_owner["provider_capability_snapshot_sha256"].to_s == registry_sha
    end
  end
  manifest_cues = Array(source_manifest.to_h["cues"])
  cue_by_id = manifest_cues.each_with_object({}) do |cue, rows|
    rows[cue["cue_id"].to_s] = cue if cue.is_a?(Hash)
  end
  source_storyboard_sha = source_manifest.to_h.dig("source_storyboard_assist", "sha256").to_s
  errors << "source video prompt manifest must bind source_storyboard_assist SHA-256" unless source_storyboard_sha.match?(/\A[a-f0-9]{64}\z/)

  whole = qa["whole_timeline_review"]
  unless whole.is_a?(Hash)
    errors << "whole_timeline_review must be a mapping"
  else
    errors << "whole_timeline_review.status=#{whole['status'].inspect}; expected pass" unless whole["status"].to_s == "pass"
    errors << "whole_timeline_review.review_summary is required" if whole["review_summary"].to_s.strip.empty?
    errors << "whole_timeline_review.findings must be an array" unless whole["findings"].is_a?(Array)
    whole_types = manifest_cues.flat_map do |cue|
      Array(cue.to_h["source_production_cut_images"]).map { |source| source.to_h["production_cut_type"].to_s }
    end.reject(&:empty?).uniq
    validate_review_execution_record(
      root: root,
      ref: whole["review_execution_record"],
      label: "whole_timeline_review.review_execution_record",
      expected_sections: Array(source_manifest.to_h["section_shards"]).map { |shard| shard.to_h["section_id"].to_s },
      expected_manifest_sha: qa["source_video_prompt_manifest_sha256"].to_s,
      expected_storyboard_sha: source_storyboard_sha,
      expected_production_cut_types: whole_types,
      review_owner: review_owner,
      errors: errors
    )
  end

  sections.each_with_index do |section, index|
    next unless section.is_a?(Hash)

    scoped_cues = Array(section["cue_ids"]).map { |cue_id| cue_by_id[cue_id.to_s] }.compact
    scoped_types = scoped_cues.flat_map do |cue|
      Array(cue["source_production_cut_images"]).map { |source| source.to_h["production_cut_type"].to_s }
    end.reject(&:empty?).uniq
    validate_review_execution_record(
      root: root,
      ref: section["review_execution_record"],
      label: "#{section['section_key'].to_s.empty? ? "sections[#{index}]" : section['section_key']}.review_execution_record",
      expected_sections: [section["section_key"].to_s],
      expected_manifest_sha: qa["source_video_prompt_manifest_sha256"].to_s,
      expected_storyboard_sha: source_storyboard_sha,
      expected_production_cut_types: scoped_types,
      review_owner: review_owner,
      errors: errors
    )
  end
elsif founder_direct_review
  errors << "review_mode must be founder_direct_delta" unless qa["review_mode"].to_s == "founder_direct_delta"
  errors << "unchanged_scope_policy is invalid" unless qa["unchanged_scope_policy"].to_s == "reuse_last_passed_contextual_review_without_rerun"
  errors << "playback_followup_policy is invalid" unless qa["playback_followup_policy"].to_s == "rerun_affected_packets_then_hash_bound_playback_qa"
  errors << "Founder-direct delta must not declare review_owner" if qa.key?("review_owner")
  errors << "Founder-direct delta must not declare whole_timeline_review" if qa.key?("whole_timeline_review")

  affected_section_ids = Array(qa["affected_section_ids"]).map(&:to_s)
  section_ids = sections.each_with_object([]) do |section, values|
    values << section["section_key"].to_s if section.is_a?(Hash)
  end
  errors << "affected_section_ids must exactly match sections order" unless affected_section_ids == section_ids

  baseline_path, baseline = validate_hashed_yaml_ref(root, qa["baseline_contextual_qa"], errors, "baseline_contextual_qa")
  if baseline
    errors << "baseline_contextual_qa must be active idol_video_prompt_section_qa.v6" unless baseline["schema_version"].to_s == "idol_video_prompt_section_qa.v6"
    errors << "baseline_contextual_qa overall_status must be pass" unless baseline["overall_status"].to_s == "pass"
    errors << "baseline_contextual_qa review_mode must be contextual LLM section and whole timeline" unless baseline["review_mode"].to_s == "contextual_llm_section_and_whole_timeline"
    errors << "baseline_contextual_qa whole_timeline_review.status must be pass" unless baseline.dig("whole_timeline_review", "status").to_s == "pass"

    baseline_source_path = resolve_path(root, baseline["source_video_prompt_manifest_path"])
    unless baseline_source_path.file?
      errors << "baseline contextual source manifest is not readable"
    else
      actual_baseline_source_sha = Digest::SHA256.file(baseline_source_path.to_s).hexdigest
      errors << "baseline contextual source manifest SHA-256 is stale" unless baseline["source_video_prompt_manifest_sha256"].to_s == actual_baseline_source_sha
    end
  end

  receipt_path, receipt = validate_hashed_yaml_ref(root, qa["founder_direct_intervention"], errors, "founder_direct_intervention")
  if receipt_path&.file?
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      FOUNDER_INTERVENTION_VALIDATOR.to_s,
      receipt_path.to_s,
      "--root",
      root.to_s,
      chdir: root.to_s
    )
    errors << "founder_direct_intervention validation failed: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}" unless status.success?
  end

  if receipt
    direct = receipt["founder_direct_update"].is_a?(Hash) ? receipt["founder_direct_update"] : {}
    errors << "Founder intervention must be v2 founder_direct_update" unless receipt["schema_version"].to_s == "idol-founder-intervention-receipt.v2" && receipt["intervention_mode"].to_s == "founder_direct_update"
    errors << "Founder intervention must be integrated with a pass decision" unless receipt["status"].to_s == "integrated" && direct["decision"].to_s == "pass"
    errors << "Founder intervention correction_kind must be video_prompt_revision" unless direct["correction_kind"].to_s == "video_prompt_revision"
    errors << "Founder intervention owning_truth_surface must be video_prompt_03v" unless direct["owning_truth_surface"].to_s == "video_prompt_03v"

    baseline_ref = qa["baseline_contextual_qa"].is_a?(Hash) ? qa["baseline_contextual_qa"] : {}
    direct_baseline_review = direct["baseline_review"].is_a?(Hash) ? direct["baseline_review"] : {}
    if baseline_path
      errors << "Founder intervention baseline_review path does not match baseline_contextual_qa" unless normalized_path(root, direct_baseline_review["path"]) == baseline_path.expand_path.to_s
    end
    errors << "Founder intervention baseline_review SHA-256 does not match baseline_contextual_qa" unless direct_baseline_review["sha256"].to_s == baseline_ref["sha256"].to_s

    if baseline
      direct_baseline_source = direct["baseline_source"].is_a?(Hash) ? direct["baseline_source"] : {}
      expected_baseline_path = normalized_path(root, baseline["source_video_prompt_manifest_path"])
      errors << "Founder intervention baseline_source path does not match the contextual baseline source" unless normalized_path(root, direct_baseline_source["path"]) == expected_baseline_path
      errors << "Founder intervention baseline_source SHA-256 does not match the contextual baseline source" unless direct_baseline_source["sha256"].to_s == baseline["source_video_prompt_manifest_sha256"].to_s
    end

    current_path = resolve_path(root, qa["source_video_prompt_manifest_path"])
    current_sha = qa["source_video_prompt_manifest_sha256"].to_s
    revised_pairs = Array(receipt.dig("integration_receipt", "revised_artifacts")).each_with_object([]) do |binding, values|
      next unless binding.is_a?(Hash)

      values << [normalized_path(root, binding["path"]), binding["sha256"].to_s]
    end
    errors << "Founder intervention revised_artifacts must bind the current 03V video prompt manifest" unless revised_pairs.include?([current_path.expand_path.to_s, current_sha])

    routed_sections = Array(receipt.dig("routing", "affected_section_ids")).map(&:to_s)
    errors << "Founder intervention affected sections do not match the direct QA delta" unless routed_sections == affected_section_ids
  end
end

unless section_status_failures.empty?
  errors << "#{section_status_failures.length} section status value(s) are not pass: #{section_status_failures.first(12).join(', ')}"
end

if errors.empty?
  if founder_direct_review
    puts "OK: #{sections.length} Founder-direct section delta record(s) ready against passed contextual baseline; affected rerun still requires playback QA"
  else
    puts "OK: #{sections.length} contextual section review record(s) and whole-timeline reconciliation ready"
  end
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
exit 1
