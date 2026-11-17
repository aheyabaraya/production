#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_02a_storyboard_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PACKET_SCHEMA = ROOT.join("schemas", "prompt-packets.schema.json")
INTAKE_SCHEMA = ROOT.join("schemas", "founder-review-decision-intake.schema.json")
AUTHORING_VALIDATOR = ROOT.join("scripts", "validate_02b_imagegen_contract.rb")

class MergeError < StandardError; end

def resolve_repo_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(ROOT).to_s
  raise MergeError, "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  raise MergeError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise MergeError, "path escapes repository root: #{raw}"
end

def load_mapping(path, label)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
          end
  raise MergeError, "#{label} must be an object" unless value.is_a?(Hash)
  value
rescue JSON::ParserError, Psych::Exception => e
  raise MergeError, "cannot parse #{label}: #{e.message}"
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?
  raise MergeError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}"
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

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def refresh_local_lineage_packet_hashes!(document)
  packets_by_id = Array(document["prompt_packets"]).to_h { |packet| [packet["packet_id"].to_s, packet] }
  Array(document["section_shards"]).each do |shard|
    Array(shard.dig("local_lineage", "packet_states")).each do |state|
      packet = packets_by_id[state["packet_id"].to_s]
      raise MergeError, "#{state['packet_id']} local lineage has no packet" unless packet
      state["packet_value_sha256"] = value_sha256(packet)
    end
  end
end

def verify_pointer(pointer, label)
  raise MergeError, "#{label} must be a path and SHA-256 object" unless pointer.is_a?(Hash)
  path, = resolve_repo_path(pointer["path"], must_exist: true)
  actual = Digest::SHA256.file(path).hexdigest
  raise MergeError, "#{label} SHA-256 is stale" unless pointer["sha256"].to_s == actual
  path
end

def source_shard_branches(source, shard)
  core_cuts = Array(source["master_storyboard"])
  core_cuts_by_id = core_cuts.to_h { |core_cut| [core_cut["core_cut_id"].to_s, core_cut] }
  Array(shard["core_cut_ids"]).flat_map do |core_cut_id|
    core_cut = core_cuts_by_id.fetch(core_cut_id.to_s)
    Array(core_cut.dig("compile_seed", "branch_cuts")).map do |branch_cut|
      [core_cut_id.to_s, branch_cut]
    end
  end
end

def validate_all_pass_intake!(intake, intake_path, section_id)
  raise MergeError, "#{intake_path} must use active decision intake v12" unless intake["schema_version"] == "idol_founder_review_decision_intake.v12"
  raise MergeError, "#{intake_path} must be a g30_fp_final review" unless intake["review_mode"] == "g30_fp_final"
  raise MergeError, "#{intake_path} is not ready for owner routing" unless intake["status"] == "ready_for_owner_routing"
  summary = intake["summary"].to_h
  active_count = summary["active_review_count"].to_i
  action_counts = summary["action_counts"].to_h
  unless active_count.positive? &&
         summary["decision_count"].to_i == active_count &&
         summary["pass_count"].to_i == active_count &&
         summary["hold_count"].to_i.zero? &&
         summary["reject_count"].to_i.zero? &&
         action_counts["pass"].to_i == active_count &&
         action_counts.reject { |action, _count| action == "pass" }.values.all? { |count| count.to_i.zero? } &&
         Array(summary["missing_review_keys"]).empty?
    raise MergeError, "#{intake_path} must be a complete all-PASS review cycle"
  end
  decisions = Array(intake["decisions"])
  unless decisions.length == active_count &&
         decisions.all? do |decision|
           decision["review_mode"] == "g30_fp_final" &&
             decision["action"] == "pass" &&
             decision["routing_status"] == "no_change_pass"
         end
    raise MergeError, "#{intake_path} decision rows differ from its all-PASS summary"
  end
  unless decisions.all? { |decision| Array(decision["affected_section_ids"]).map(&:to_s) == [section_id] }
    raise MergeError, "#{intake_path} may affect only reviewed section #{section_id}"
  end
end

options = {sections: [], intakes: [], write: false}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prompt_packet_section_merge.rb SOURCE_02A --section SECTION_02B --decision-intake INTAKE [repeat] --output 02B-prompt-packets.yaml --write"
  opts.on("--section PATH", "Reviewed active 2.6 section artifact; repeat once per source section.") { |value| options[:sections] << value }
  opts.on("--decision-intake PATH", "Founder review intake paired by position with --section.") { |value| options[:intakes] << value }
  opts.on("--output PATH", "Canonical merged 02B output.") { |value| options[:output] = value }
  opts.on("--write", "Write the validated canonical merge.") { options[:write] = true }
end.parse!

begin
  source_arg = ARGV.shift
  raise MergeError, "SOURCE_02A is required" if source_arg.to_s.empty?
  raise MergeError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  raise MergeError, "at least one --section is required" if options[:sections].empty?
  raise MergeError, "each --section needs one paired --decision-intake" unless options[:sections].length == options[:intakes].length
  raise MergeError, "--output and --write are required" unless options[:output] && options[:write]

  source_path, source_rel = resolve_repo_path(source_arg, must_exist: true)
  source = load_mapping(source_path, "source 02A")
  source_sha = Digest::SHA256.file(source_path).hexdigest
  cover_errors = Idol02AStoryboardContract.section_exact_cover_errors(source, require_shards: true)
  raise MergeError, "source 02A exact-cover check failed: #{cover_errors.join('; ')}" unless cover_errors.empty?
  source_shards = Array(source["section_shards"])
  core_cut_order = Array(source["master_storyboard"]).each_with_index.to_h do |core_cut, index|
    [core_cut["core_cut_id"].to_s, index]
  end

  output_path, output_rel = resolve_repo_path(options[:output])
  raise MergeError, "canonical merge output must be named 02B-prompt-packets.yaml" unless output_path.basename.to_s == "02B-prompt-packets.yaml"
  raise MergeError, "canonical merge output must stay beside its source 02A" unless output_path.dirname == source_path.dirname

  section_docs = {}
  intake_refs = []
  section_context_review_refs = []
  options[:sections].zip(options[:intakes]).each_with_index do |(section_arg, intake_arg), index|
    section_path, section_rel = resolve_repo_path(section_arg, must_exist: true)
    intake_path, intake_rel = resolve_repo_path(intake_arg, must_exist: true)
    validate_schema(PACKET_SCHEMA, section_path, "section artifact #{index + 1}")
    validate_schema(INTAKE_SCHEMA, intake_path, "decision intake #{index + 1}")
    section = load_mapping(section_path, "section artifact #{index + 1}")
    intake = load_mapping(intake_path, "decision intake #{index + 1}")

    raise MergeError, "#{section_rel} must use active prompt packet schema 2.6" unless section["schema_version"] == "2.6"
    raise MergeError, "#{section_rel} must contain exactly one section shard" unless Array(section["section_shards"]).length == 1
    shard = section["section_shards"].first
    source_shard = source_shards.find { |row| row["shard_id"].to_s == shard["shard_id"].to_s }
    raise MergeError, "#{section_rel} names an unknown 02A shard" unless source_shard
    shard_id = source_shard["shard_id"].to_s
    raise MergeError, "02A shard #{shard_id} was supplied twice" if section_docs.key?(shard_id)
    section_id = Array(source_shard["section_ids"]).first.to_s
    raise MergeError, "#{section_rel} section id differs from 02A" unless shard["section_id"].to_s == section_id
    unless Array(shard["core_cut_ids"]) == Array(source_shard["core_cut_ids"])
      raise MergeError, "#{section_rel} Core Cut ids differ from 02A"
    end
    raise MergeError, "#{section_rel} source 02A path differs" unless resolve_repo_path(section.dig("input_files", "master_storyboard")).first == source_path
    raise MergeError, "#{section_rel} compile shard trace differs" unless section.dig("input_files", "section_compile_shard_id").to_s == shard_id
    unless shard["local_lineage"].is_a?(Hash)
      raise MergeError, "#{section_rel} active 2.6 requires local lineage; no compatibility fallback is available"
    end
    lineage_errors = Idol02AStoryboardContract.prompt_section_lineage_errors(source, section, shard)
    unless lineage_errors.empty?
      raise MergeError, "#{section_rel} local lineage is stale: #{lineage_errors.join('; ')}"
    end

    packets = Array(section["prompt_packets"])
    raise MergeError, "#{section_rel} contains an inactive compiler packet" unless packets.all? { |packet| Idol02AStoryboardContract.active_compiled_packet?(packet) }
    expected_branches = source_shard_branches(source, source_shard)
    expected_packet_ids = expected_branches.map { |_core_cut_id, branch_cut| branch_cut["packet_id"].to_s }
    raise MergeError, "#{section_rel} packet order/coverage differs from 02A" unless packets.map { |packet| packet["packet_id"].to_s } == expected_packet_ids
    expected_branches.zip(packets).each do |(core_cut_id, branch_cut), packet|
      unless packet["core_cut_id"].to_s == core_cut_id
        raise MergeError, "#{packet['packet_id']} Core Cut differs from 02A"
      end
      unless packet["branch_cut_lock"] == branch_cut
        raise MergeError, "#{packet['packet_id']} Branch Cut lock differs from 02A"
      end
    end

    validate_all_pass_intake!(intake, intake_rel, section_id)
    board_manifest_path = verify_pointer(intake.dig("source_board", "manifest"), "#{intake_rel} source board manifest")
    board_manifest = load_mapping(board_manifest_path, "source board manifest")
    section_sha = Digest::SHA256.file(section_path).hexdigest
    binds_exact_section = Array(board_manifest["sources"]).any? do |row|
      next false unless row.is_a?(Hash)
      resolve_repo_path(row["path"]).first == section_path && row["sha256"].to_s == section_sha
    rescue MergeError
      false
    end
    raise MergeError, "#{intake_rel} board manifest does not bind the exact reviewed section artifact" unless binds_exact_section

    approved = deep_copy(section)
    approved["status"] = "approved"
    approved["section_shards"].each { |row| row["status"] = "passed" }
    approved["prompt_packets"].each { |packet| packet["status"] = "approved" }
    refresh_local_lineage_packet_hashes!(approved)
    section_docs[shard_id] = approved
    intake_refs << {"path" => intake_rel, "artifact_sha256" => Digest::SHA256.file(intake_path).hexdigest}
    review_path, review_rel = resolve_repo_path(section.dig("input_files", "storyboard_context_review"), must_exist: true)
    review_sha = Digest::SHA256.file(review_path).hexdigest
    unless section.dig("input_files", "storyboard_context_review_sha256").to_s == review_sha
      raise MergeError, "#{section_rel} storyboard context review SHA-256 is stale"
    end
    section_context_review_refs << {
      "section_id" => section_id,
      "path" => review_rel,
      "artifact_sha256" => review_sha
    }
  end

  expected_shard_ids = source_shards.map { |row| row["shard_id"].to_s }
  missing = expected_shard_ids - section_docs.keys
  extra = section_docs.keys - expected_shard_ids
  raise MergeError, "missing reviewed section shards: #{missing.join(', ')}" unless missing.empty?
  raise MergeError, "unknown reviewed section shards: #{extra.join(', ')}" unless extra.empty?

  ordered_docs = expected_shard_ids.map { |shard_id| section_docs.fetch(shard_id) }
  selected_execution = ordered_docs.first["run_execution_selection"]
  unless ordered_docs.all? { |document| document["run_execution_selection"] == selected_execution }
    raise MergeError, "reviewed section shards disagree on the exact provider-specific run execution selection"
  end
  packets = ordered_docs.flat_map { |document| Array(document["prompt_packets"]) }
  packets.sort_by! do |packet|
    [core_cut_order.fetch(packet["core_cut_id"].to_s), packet.dig("branch_cut_lock", "branch_sequence").to_i]
  end
  exactness_errors = Idol02AStoryboardContract.direct_branch_cut_packet_exactness_errors(source, packets)
  raise MergeError, "02A/02B exactness failed: #{exactness_errors.join('; ')}" unless exactness_errors.empty?

  merged = deep_copy(ordered_docs.first)
  merged["status"] = "approved"
  merged["input_files"]["master_storyboard"] = source_rel
  merged["input_files"]["master_storyboard_sha256"] = source_sha
  merged["input_files"].delete("section_compile_shard_id")
  merged["input_files"].delete("section_compile_scope_sha256")
  merged["input_files"]["section_review_intakes"] = intake_refs
  merged["input_files"]["section_context_reviews"] = section_context_review_refs
  merged["prompt_packets"] = packets
  merged["section_shards"] = ordered_docs.flat_map { |document| Array(document["section_shards"]) }
  merged["open_questions"] = ordered_docs.flat_map { |document| Array(document["open_questions"]) }.uniq
  refresh_local_lineage_packet_hashes!(merged)

  serialized = YAML.dump(merged)
  Tempfile.create(["idol-02b-merge", ".yaml"], output_path.dirname.to_s) do |file|
    file.write(serialized)
    file.flush
    temp_path = Pathname.new(file.path)
    validate_schema(PACKET_SCHEMA, temp_path, "canonical 02B merge")
    stdout, stderr, status = Open3.capture3(
      "ruby",
      AUTHORING_VALIDATOR.to_s,
      "--mode",
      "authoring",
      "--run-root",
      source_path.dirname.to_s,
      temp_path.to_s,
      chdir: ROOT.to_s
    )
    raise MergeError, "canonical 02B authoring validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
    file.close
    File.rename(temp_path, output_path)
  end

  puts JSON.pretty_generate(
    "status" => "approved",
    "output" => output_rel,
    "output_sha256" => Digest::SHA256.file(output_path).hexdigest,
    "source_02a_sha256" => source_sha,
    "section_shards" => expected_shard_ids,
    "packet_count" => packets.length,
    "creative_text_authored_by_merge" => false,
    "generation_approved" => false
  )
rescue MergeError, KeyError => e
  warn "ERROR: #{e.message}"
  exit 1
end
