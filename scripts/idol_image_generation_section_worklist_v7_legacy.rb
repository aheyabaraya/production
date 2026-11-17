#!/usr/bin/env ruby
# Pinned legacy reader only. New worklists use idol_image_generation_section_worklist.rb v8.
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_run_layout"

CODE_ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON_RUNNER = CODE_ROOT.join("scripts/idol-video-python")
SCHEMA_VALIDATOR = CODE_ROOT.join("scripts/validate_json_schema.py")
REQUEST_SCHEMA = CODE_ROOT.join("schemas/image-generation-request.schema.json")
WORKLIST_SCHEMA = CODE_ROOT.join("schemas/image-generation-section-worklist.schema.json")
SELECTION_SCHEMA = CODE_ROOT.join("schemas/image-generation-request-selection.schema.json")
CONTEXT_PACK_VALIDATOR = CODE_ROOT.join("scripts/validate_harness_context_pack.rb")
READY_STATUSES = %w[ready].freeze
IGNORED_REQUEST_PATH_SEGMENTS = %w[archive archived history superseded rejected].freeze

options = {repo_root: CODE_ROOT, write: false}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_image_generation_section_worklist.rb RUN_ROOT [options]"
  parser.on("--requests-root DIR", "image-generation request directory") { |value| options[:requests_root] = value }
  parser.on("--selection FILE", "exact active request selection; defaults to RUN/work/image_generation_requests/active-selection.yaml when present") { |value| options[:selection] = value }
  parser.on("--output FILE", "derived section worklist output") { |value| options[:output] = value }
  parser.on("--write", "write the validated derived worklist") { options[:write] = true }
  parser.on("--repo-root DIR", "repository root override") { |value| options[:repo_root] = Pathname.new(value).expand_path }
end.parse!

abort "RUN_ROOT is required" unless ARGV.length == 1
repo_root = Pathname.new(options[:repo_root]).expand_path

def repo_path(root, raw, must_exist: false)
  candidate = Pathname.new(raw).absolute? ? Pathname.new(raw).expand_path : root.join(raw).expand_path
  relative = candidate.relative_path_from(root).to_s
  abort "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  abort "required file is missing: #{relative}" if must_exist && !candidate.file?
  [candidate, relative]
rescue ArgumentError
  abort "path escapes repository root: #{raw}"
end

def load_yaml_hash(path, label)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
  abort "#{label} root must be a mapping" unless value.is_a?(Hash)
  value
rescue Psych::Exception => e
  abort "cannot parse #{label}: #{e.message}"
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON_RUNNER.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: CODE_ROOT.to_s
  )
  abort "#{label} failed schema validation:\n#{[stderr, stdout].reject { |row| row.to_s.strip.empty? }.join("\n")}" unless status.success?
end

def sha256(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def file_hold_reason(root, raw_path, expected_sha, label)
  path, relative = repo_path(root, raw_path)
  return "missing #{label}: #{relative}" unless path.file?
  return "stale #{label} hash: #{relative}" unless sha256(path) == expected_sha.to_s

  nil
end

run_path, run_rel = repo_path(repo_root, ARGV.fetch(0))
layout_errors = IdolRunLayout.validate(run_path, repo_root: repo_root)
abort layout_errors.join("; ") unless layout_errors.empty?

requests_root, requests_root_rel = repo_path(
  repo_root,
  options[:requests_root] || run_path.join("work/image_generation_requests/sections").to_s
)
abort "requests root must stay inside the owning run" unless requests_root_rel.start_with?("#{run_rel}/")
candidate_paths = requests_root.directory? ? requests_root.glob("**/*.yaml").sort : []
ignored_paths, request_paths = candidate_paths.partition do |path|
  relative_segments = path.relative_path_from(requests_root).each_filename.to_a.map(&:downcase)
  (relative_segments & IGNORED_REQUEST_PATH_SEGMENTS).any?
end
discovered_request_paths = request_paths.dup

current_02b = run_path.join("02B-prompt-packets.yaml")
abort "current 02B prompt packets are missing: #{current_02b.relative_path_from(repo_root)}" unless current_02b.file?
current_02b_rel = current_02b.relative_path_from(repo_root).to_s
current_02b_sha = sha256(current_02b)

selection_default = run_path.join("work/image_generation_requests/active-selection.yaml")
selection_path = if options[:selection]
                   repo_path(repo_root, options[:selection], must_exist: true).first
                 elsif selection_default.file?
                   selection_default
                 end
selection = nil
selection_rel = nil
selection_sha = nil
selected_pointer_rows = {}
if selection_path
  validate_schema(SELECTION_SCHEMA, selection_path, "active image-generation request selection")
  selection = load_yaml_hash(selection_path, "active image-generation request selection")
  selection_rel = selection_path.relative_path_from(repo_root).to_s
  selection_sha = sha256(selection_path)
  abort "selection belongs to another run" unless selection["run"].to_s == run_rel
  selection_source = selection["source_02b"] || {}
  unless selection_source["path"].to_s == current_02b_rel && selection_source["sha256"].to_s == current_02b_sha
    abort "selection is not bound to current 02B bytes"
  end
  request_paths = Array(selection["requests"]).map do |pointer|
    path, relative = repo_path(repo_root, pointer.fetch("path"), must_exist: true)
    abort "selection request must stay inside the owning run: #{relative}" unless relative.start_with?("#{run_rel}/")
    abort "selection request hash is stale: #{relative}" unless sha256(path) == pointer.fetch("sha256").to_s
    selected_pointer_rows[relative] = pointer
    path
  end
  ignored_paths = []
else
  request_paths = []
end

candidate_rows = request_paths.map do |path|
  request_rel = path.relative_path_from(repo_root).to_s
  validate_schema(REQUEST_SCHEMA, path, "image-generation request #{request_rel}")
  request = load_yaml_hash(path, "image-generation request #{request_rel}")
  abort "request #{request_rel} belongs to another run" unless request["run"] == run_rel
  section_id = request["execution_section_id"].to_s
  abort "request #{request_rel} has no execution_section_id" if section_id.empty?
  abort "request #{request_rel} execution context mismatch" unless request.dig("execution_context", "section_id") == section_id
  abort "request #{request_rel} Core Cut context mismatch" unless request.dig("execution_context", "current_core_cut_id") == request["core_cut_id"]
  abort "request #{request_rel} Branch Cut context mismatch" unless request.dig("execution_context", "current_branch_cut_id") == request["branch_cut_id"]
  if selection
    pointer = selected_pointer_rows.fetch(request_rel)
    {
      "section_id" => section_id,
      "packet_id" => request["packet_id"].to_s,
      "core_cut_id" => request["core_cut_id"].to_s,
      "branch_cut_id" => request["branch_cut_id"].to_s,
      "adapter" => request["adapter"].to_s,
      "expected_output_path" => request["expected_output_path"].to_s
    }.each do |field, actual|
      abort "selection #{field} mismatch for #{request_rel}" unless pointer[field].to_s == actual
    end
  end
  {
    "section_id" => section_id,
    "request" => request,
    "path" => request_rel,
    "sha256" => sha256(path)
  }
end
rows, stale_rows = candidate_rows.partition do |row|
  pointer = row.dig("request", "source_02b") || {}
  pointer["path"].to_s == current_02b_rel && pointer["sha256"].to_s == current_02b_sha
end

duplicate_hold_reasons = []
packet_ids = rows.map { |row| row.dig("request", "packet_id").to_s }
duplicate_packet_ids = packet_ids.group_by(&:itself).select { |_id, grouped| grouped.length > 1 }.keys
duplicate_hold_reasons << "duplicate packet_id in active request set: #{duplicate_packet_ids.join(', ')}" unless duplicate_packet_ids.empty?
output_paths = rows.map { |row| row.dig("request", "expected_output_path").to_s }
duplicate_output_paths = output_paths.group_by(&:itself).select { |_path, grouped| grouped.length > 1 }.keys
duplicate_hold_reasons << "duplicate expected output path in active request set: #{duplicate_output_paths.join(', ')}" unless duplicate_output_paths.empty?

sections = rows.group_by { |row| row["section_id"] }.sort.map do |section_id, section_rows|
  context_packs = section_rows.map { |row| row.dig("request", "execution_context", "context_pack") }.uniq
  planning_sources = section_rows.map { |row| row.dig("request", "execution_context", "planning_source") }.uniq
  abort "section #{section_id} must use one exact planning source" unless planning_sources.length == 1

  hold_reasons = duplicate_hold_reasons.dup
  hold_reasons << "explicit active request selection is missing; build it before dispatch" unless selection
  planning_source_pointer = planning_sources.first
  context_packs.each do |context_pack_pointer|
    context_pack_file_reason = file_hold_reason(
      repo_root,
      context_pack_pointer.fetch("path"),
      context_pack_pointer.fetch("sha256"),
      "Branch Cut context pack"
    )
    hold_reasons << context_pack_file_reason if context_pack_file_reason
    unless context_pack_file_reason
      context_pack_path, context_pack_rel = repo_path(repo_root, context_pack_pointer.fetch("path"), must_exist: true)
      stdout, stderr, status = Open3.capture3(
        "ruby",
        CONTEXT_PACK_VALIDATOR.to_s,
        context_pack_path.to_s,
        "--max-errors",
        "3",
        chdir: CODE_ROOT.to_s
      )
      unless status.success?
        details = [stderr, stdout]
                  .flat_map { |value| value.to_s.lines }
                  .map(&:strip)
                  .reject(&:empty?)
                  .first(3)
                  .join(" | ")
        hold_reasons << "Branch Cut context pack is not execution-ready: #{context_pack_rel} (#{details})"
      end
    end
  end
  planning_source_reason = file_hold_reason(
    repo_root,
    planning_source_pointer.fetch("path"),
    planning_source_pointer.fetch("sha256"),
    "section planning source"
  )
  hold_reasons << planning_source_reason if planning_source_reason

  requests = section_rows.sort_by { |row| [row.dig("request", "packet_id").to_s, row["path"]] }.map do |row|
    request = row["request"]
    hold_reasons.concat(Array(request["hold_reasons"]))
    hold_reasons << "request #{request['packet_id']} is #{request['status']}" unless READY_STATUSES.include?(request["status"])
    {
      "source 02A" => request["source_02a"],
      "source 02B" => request["source_02b"],
      "context pack" => request.dig("execution_context", "context_pack"),
      "planning source" => request.dig("execution_context", "planning_source")
    }.each do |label, pointer|
      reason = file_hold_reason(repo_root, pointer.fetch("path"), pointer.fetch("sha256"), label)
      hold_reasons << reason if reason
    end
    Array(request["member_visual_inputs"]).each do |input|
      reason = file_hold_reason(repo_root, input.fetch("path"), input.fetch("sha256"), "member visual input")
      hold_reasons << reason if reason
    end
    Array(request["scene_reference_inputs"]).each do |input|
      reason = file_hold_reason(repo_root, input.fetch("path"), input.fetch("sha256"), "scene reference input")
      hold_reasons << reason if reason
    end
    Array(request["attachment_order"]).each do |input|
      reason = file_hold_reason(repo_root, input.fetch("path"), input.fetch("sha256"), "combined visual attachment")
      hold_reasons << reason if reason
    end
    approval_path = request.dig("approval", "approval_source_path")
    if approval_path
      reason = file_hold_reason(
        repo_root,
        approval_path,
        request.dig("approval", "approval_source_sha256"),
        "approval source"
      )
      hold_reasons << reason if reason
    end
    prompt_text = request.dig("prompt", "full_prompt_text").to_s
    unless Digest::SHA256.hexdigest(prompt_text) == request.dig("prompt", "full_prompt_sha256")
      hold_reasons << "request #{request['packet_id']} prompt text hash is stale"
    end
    {
      "path" => row["path"],
      "sha256" => row["sha256"],
      "packet_id" => request.fetch("packet_id"),
      "core_cut_id" => request.fetch("core_cut_id"),
      "branch_cut_id" => request.fetch("branch_cut_id"),
      "adapter" => request.fetch("adapter"),
      "request_status" => request.fetch("status"),
      "prompt_sha256" => request.dig("prompt", "full_prompt_sha256"),
      "member_visual_inputs_sha256" => request.fetch("member_visual_inputs_sha256"),
      "scene_reference_inputs_sha256" => request.fetch("scene_reference_inputs_sha256"),
      "attachment_order_sha256" => request.fetch("attachment_order_sha256"),
      "expected_output_path" => request.fetch("expected_output_path"),
      "packet_value_sha256" => request.dig("integrity_contract", "packet_value_sha256")
    }
  end
  hold_reasons = hold_reasons.reject { |value| value.to_s.strip.empty? }.uniq.sort
  section_ready = hold_reasons.empty?
  {
    "section_id" => section_id,
    "status" => section_ready ? "ready" : "hold",
    "fresh_session_required" => true,
    "prompt_authoring_session_reuse_forbidden" => true,
    "fresh_session_boundary" => "sol_approved_02a_section",
    "post_02a_section_lineage_required" => true,
    "second_creative_lineage_after_02b_forbidden" => true,
    "durable_checkpoint_resume_allowed" => true,
    "same_physical_session_required" => false,
    "04_edit_session_included" => false,
    "03v_completion_handoff_required_before_04" => true,
    "execution_controller" => "adapter_native_or_terra_locked_section_executor",
    "sol_execution_forbidden" => true,
    "asynchronous_with_disjoint_sections_allowed" => true,
    "parallel_dispatch" => {
      "enabled" => section_ready,
      "membership" => "all_ready_requests_in_section",
      "mode" => "bounded_parallel_packet_calls",
      "request_unit" => "one_exact_packet_per_generation_call",
      "concurrency_limit_source" => "selected_adapter_or_runtime_current_capacity",
      "same_output_parallel_write_forbidden" => true,
      "failure_isolation" => "failed_packet_holds_without_invalidating_successful_disjoint_outputs",
      "unsupported_runtime_fallback" => "serialize_only_that_adapter_without_rewriting_packets",
      "result_barrier" => "hash_and_pixel_inspect_every_returned_output_before_section_review",
      "controller_script" => "scripts/idol_image_generation_dispatch.rb",
      "ledger_schema" => "schemas/image-generation-dispatch-ledger.schema.json",
      "claim_policy" => "atomic_capacity_bounded_claims",
      "idempotency_policy" => "request_hash_plus_attempt_number",
      "result_recording" => "expected_path_hash_then_pixel_inspection_receipt"
    },
    "context_packs" => context_packs,
    "planning_source" => planning_sources.first,
    "requests" => requests,
    "output_paths" => requests.map { |request| request["expected_output_path"] },
    "hold_reasons" => hold_reasons
  }
end

ready_count = sections.count { |section| section["status"] == "ready" }
source_set = rows.sort_by { |row| row["path"] }.map { |row| {"path" => row["path"], "sha256" => row["sha256"]} }
worklist = {
  "schema_version" => "idol_image_generation_section_worklist.v7",
  "artifact_type" => "derived_image_generation_section_worklist",
  "run" => run_rel,
  "request_set_sha256" => Digest::SHA256.hexdigest(JSON.generate(source_set)),
  "discovery_contract" => {
    "request_root" => requests_root_rel,
    "current_source_02b" => {"path" => current_02b_rel, "sha256" => current_02b_sha},
    "selection_mode" => "explicit_active_selection",
    "selection_source" => selection ? {"path" => selection_rel, "sha256" => selection_sha} : nil,
    "archive_segments_ignored" => IGNORED_REQUEST_PATH_SEGMENTS,
    "selection_rule" => "explicit_selection_exact_path_hash_then_current_02b_binding",
    "stale_candidate_action" => "report_and_exclude_without_blocking_current_work",
    "no_current_request_action" => "emit_hold_worklist_without_crashing",
    "equally_current_duplicate_action" => "hold",
    "candidate_count" => discovered_request_paths.length,
    "selected_count" => rows.length,
    "stale_count" => stale_rows.length,
    "ignored_archive_count" => ignored_paths.length
  },
  "status" => !rows.empty? && ready_count == sections.length ? "ready" : "hold",
  "summary" => {
    "section_count" => sections.length,
    "request_count" => rows.length,
    "ready_section_count" => ready_count,
    "hold_section_count" => sections.length - ready_count
  },
  "sections" => sections,
  "coordinator_contract" => {
    "dispatch_unit" => "one_checkpointed_post_02a_image_motion_lineage_per_section",
    "parallel_rule" => "bounded_parallel_packet_calls_within_each_section_and_asynchronous_disjoint_sections",
    "output_intake" => "direct_scripts_hash_every_result_terra_pixel_inspects_full_section_before_sol_branch_cut_gate",
    "merge_rule" => "sol_reviews_bounded_decision_evidence_and_performs_cross_section_repetition_continuity_and_registry_merge"
  },
  "automation_boundaries" => {
    "derived_noncanonical" => true,
    "task_created" => false,
    "model_called" => false,
    "upload_performed" => false,
    "approval_granted" => false,
    "paid_generation_performed" => false
  }
}

output_path, output_rel = repo_path(
  repo_root,
  options[:output] || run_path.join("work/image_generation_requests/section-worklist.yaml").to_s
)
abort "worklist output must stay inside the owning run" unless output_rel.start_with?("#{run_rel}/")

yaml = YAML.dump(worklist)
Tempfile.create(["idol-image-generation-section-worklist", ".yaml"]) do |temp|
  temp.write(yaml)
  temp.flush
  validate_schema(WORKLIST_SCHEMA, Pathname.new(temp.path), "image-generation section worklist")
end

if options[:write]
  output_path.dirname.mkpath
  output_path.write(yaml)
end

puts JSON.pretty_generate(
  "write" => options[:write],
  "output" => output_rel,
  "status" => worklist["status"],
  "request_set_sha256" => worklist["request_set_sha256"],
  "summary" => worklist["summary"]
)
