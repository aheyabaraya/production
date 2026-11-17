#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "lib/idol_role_context_pack"

ROOT = Pathname.new(__dir__).join("..").expand_path
PROFILE_REGISTRY_RELATIVE = "automation/harness-skill-load-profiles.yaml"
PROFILE_REGISTRY = ROOT.join(PROFILE_REGISTRY_RELATIVE)
GRAPH_PROFILE_REGISTRY_RELATIVE = "automation/graph-skill-load-profiles.yaml"
SCHEMA_VERSION = "idol-harness-startup-admission.v2"
RUN_ROOT_PATTERN = %r{\Aruns/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9가-힣][a-z0-9가-힣-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}\z}
SHA256_PATTERN = /\A[a-f0-9]{64}\z/
MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_FOUNDER_MESSAGE_BYTES = 256 * 1024

PROFILE_ROUTES = {
  "overall_director" => {"checkpoint_id" => "director_startup", "role" => "overall_director"},
  "creative_development_director" => {"checkpoint_id" => "cdd_startup", "role" => "creative_development_director"}
}.freeze
GRAPH_PLANNING_CDD_PROFILES = %w[planning_cdd_p1 planning_cdd_p2 planning_cdd_p3_ci].freeze
ROLE_CONTEXT_ROUTE_KEYS = %w[
  writer run_class stage_id cdd_profile_id cdd_checkpoint_id section_ids section_cohort_id switch_receipt
].freeze

TWELVE_HEADINGS = [
  "## 01 Dispatch Identity",
  "## 02 Role And Authority",
  "## 03 Current Creative Job",
  "## 04 Exact Scope And Non-Scope",
  "## 05 Input Pointers",
  "## 06 Skill Route",
  "## 07 Required Work",
  "## 08 Output Contract",
  "## 09 Quality Proof",
  "## 10 Return-Ready Conditions",
  "## 11 HOLD Stop And Split Conditions",
  "## 12 Return And Wake"
].freeze

CURRENT_PRIORITY_PROJECTION_CLAUSES = [
  "CDD must scope every current-task priority—including each Founder emphasis and each owning skill, policy, contract, output, quality, and HOLD emphasis—into its own stable row in the existing Department Dispatch Contract requirement_manifest before delegating current work.",
  "Each row must name its exact source locator, affected scope, expected output target, evidence type, and whether recipient-Director semantic review is required; a generic instruction to read or follow a skill is not a substitute, and the whole skill must not be duplicated into the prompt.",
  "Keep the native Goal concise. Workers receive only their scoped requirement_manifest rows in applicable Blocks 03, 07, and 09, never the full Founder conversation or this complete Director Assignment Delta."
].freeze

PRIORITY_CLOSURE_CLAUSES = [
  "For every required scoped priority row, require exact projection into the worker's applicable Blocks 03, 07, and 09, an exact worker fulfillment claim, and an independent recipient-Director requirement result against the returned bytes.",
  "A dropped, merged-away, genericized, or self-asserted priority is a HOLD, not completion."
].freeze

DELTA_KEYS = %w[
  status role_context_receipt founder_request_binding run_stage_lock_summary current_creative_job exact_scope
  non_scope unaffected_truth next_owner_route required_work quality_proof
  unresolved_decisions hold_reasons
].freeze

CDD_DELTA_KEYS = %w[
  status founder_request_binding current_creative_job exact_scope non_scope unaffected_truth required_work
  quality_proof unresolved_decisions hold_reasons
].freeze

FOUNDER_REQUEST_BINDING_KEYS = %w[
  source_action source_json_pointer utf8_bytes sha256
].freeze
FOUNDER_REQUEST_SOURCE_ACTION = "prepare_overall_read_gate"
FOUNDER_REQUEST_JSON_POINTER = "/founder_message"

class StartupAdmissionError < StandardError; end

def fail_admission(message)
  raise StartupAdmissionError, message
end

def sha256_bytes(value)
  Digest::SHA256.hexdigest(value)
end

def sha256_file(path)
  Digest::SHA256.file(path).hexdigest
end

def canonical_value(value)
  case value
  when Hash
    value.keys.sort.each_with_object({}) { |key, out| out[key] = canonical_value(value[key]) }
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def canonical_json(value)
  JSON.generate(canonical_value(value))
end

def digest_value(value)
  sha256_bytes(canonical_json(value))
end

def founder_request_binding(founder_message)
  {
    "source_action" => FOUNDER_REQUEST_SOURCE_ACTION,
    "source_json_pointer" => FOUNDER_REQUEST_JSON_POINTER,
    "utf8_bytes" => founder_message.bytesize,
    "sha256" => sha256_bytes(founder_message)
  }
end

def validate_founder_message!(value)
  message = nonempty_string!(value, "founder_message")
  fail_admission("founder_message must be valid UTF-8") unless message.encoding == Encoding::UTF_8 && message.valid_encoding?
  fail_admission("founder_message exceeds the startup admission limit") if message.bytesize > MAX_FOUNDER_MESSAGE_BYTES
  message
end

def verify_founder_request_binding!(value, founder_message, label)
  exact_keys!(value, FOUNDER_REQUEST_BINDING_KEYS, label)
  expected = founder_request_binding(founder_message)
  fail_admission("#{label} must exact-copy the initial Overall read-gate Founder request locator and SHA-256") unless value == expected
  expected
end

def exact_keys!(value, expected, label)
  fail_admission("#{label} must be an object") unless value.is_a?(Hash)
  actual = value.keys.sort
  wanted = expected.sort
  return if actual == wanted

  fail_admission("#{label} keys must be exactly #{wanted.join(', ')}")
end

def exact_keys_with_optional!(value, required, optional, label)
  fail_admission("#{label} must be an object") unless value.is_a?(Hash)
  actual = value.keys.sort
  minimum = required.sort
  allowed = (required + optional).sort
  missing = minimum - actual
  extra = actual - allowed
  return if missing.empty? && extra.empty?

  fail_admission("#{label} keys must contain #{minimum.join(', ')} and may add only #{optional.join(', ')}")
end

def normalize_role_context_route!(value)
  return nil if value.nil?

  exact_keys!(value, ROLE_CONTEXT_ROUTE_KEYS, "role_context_route")
  fail_admission("role_context_route.writer must be graph_v2") unless value["writer"] == "graph_v2"
  fail_admission("role_context_route.run_class must be new_run") unless value["run_class"] == "new_run"
  profile_id = nonempty_string!(value["cdd_profile_id"], "role_context_route.cdd_profile_id")
  unless GRAPH_PLANNING_CDD_PROFILES.include?(profile_id)
    fail_admission("role_context_route.cdd_profile_id must select one Planning CDD lane")
  end
  nonempty_string!(value["cdd_checkpoint_id"], "role_context_route.cdd_checkpoint_id")
  nonempty_string!(value["stage_id"], "role_context_route.stage_id")
  section_ids = Array(value["section_ids"])
  string_array!(section_ids, "role_context_route.section_ids")
  if profile_id == "planning_cdd_p3_ci"
    fail_admission("P3 graph startup requires a 2--3 section cohort") unless [2, 3].include?(section_ids.length)
    fail_admission("P3 graph startup requires section_cohort_id") unless value["section_cohort_id"].to_s.match?(/\AC[1-9][0-9]*\z/)
  else
    fail_admission("non-P3 graph startup must not carry a section cohort") unless section_ids.empty? && value["section_cohort_id"].nil?
  end
  IdolRoleContextPack.validate_graph_switch_receipt!(ROOT, value["switch_receipt"])
  canonical_value(value)
rescue IdolRoleContextPack::ContractError => e
  fail_admission("role_context_route is held: #{e.message}")
end

def nonempty_string!(value, label)
  fail_admission("#{label} must be a non-empty string") unless value.is_a?(String) && !value.strip.empty?
  value
end

def string_array!(value, label)
  fail_admission("#{label} must be an array") unless value.is_a?(Array)
  value.each { |item| nonempty_string!(item, label) }
  fail_admission("#{label} must not contain duplicates") unless value.uniq.length == value.length
  value
end

def contained_file(relative)
  nonempty_string!(relative, "repository path")
  candidate = ROOT.join(relative).cleanpath
  root_prefix = "#{ROOT}/"
  fail_admission("repository path escapes the IDOL root: #{relative}") unless candidate.to_s.start_with?(root_prefix)
  fail_admission("repository path is not a regular file: #{relative}") unless candidate.file?
  candidate
end

def verify_path_hash!(binding, label, run_root: nil)
  exact_keys!(binding, %w[path sha256], label)
  path = nonempty_string!(binding["path"], "#{label}.path")
  expected = nonempty_string!(binding["sha256"], "#{label}.sha256")
  fail_admission("#{label}.sha256 is invalid") unless expected.match?(SHA256_PATTERN)
  if run_root && !path.start_with?("#{run_root}/")
    fail_admission("#{label}.path must stay inside #{run_root}")
  end
  actual = sha256_file(contained_file(path))
  fail_admission("#{label} SHA-256 is stale: #{path}") unless actual == expected
  {"path" => path, "sha256" => actual}
end

def verify_run_binding!(input)
  binding = input["run_binding"]
  exact_keys!(binding, %w[run_root plan canvas founder_epoch active_owner_role], "run_binding")
  run_root = nonempty_string!(binding["run_root"], "run_binding.run_root")
  fail_admission("run_binding.run_root is not canonical") unless run_root.match?(RUN_ROOT_PATTERN)
  run_path = ROOT.join(run_root).cleanpath
  fail_admission("run root is missing") unless run_path.directory?

  manifest_relative = "#{run_root}/run-manifest.yaml"
  manifest_path = contained_file(manifest_relative)
  manifest = YAML.safe_load(manifest_path.read, aliases: true)
  fail_admission("run manifest does not bind the requested run") unless manifest.is_a?(Hash) && manifest["canonical_run_root"] == run_root
  fail_admission("run manifest is not active") unless manifest["status"] == "active"

  founder_epoch = binding["founder_epoch"]
  fail_admission("run_binding.founder_epoch must be a non-negative integer") unless founder_epoch.is_a?(Integer) && founder_epoch >= 0
  owner = binding["active_owner_role"]
  fail_admission("run_binding.active_owner_role must be overall_director") unless owner == "overall_director"

  {
    "run_root" => run_root,
    "run_manifest" => {"path" => manifest_relative, "sha256" => sha256_file(manifest_path)},
    "plan" => verify_path_hash!(binding["plan"], "run_binding.plan", run_root: run_root),
    "canvas" => verify_path_hash!(binding["canvas"], "run_binding.canvas", run_root: run_root),
    "founder_epoch" => founder_epoch,
    "active_owner_role" => owner
  }
end

def load_profile!(profile_id, role_context_route: nil)
  route = PROFILE_ROUTES[profile_id]
  fail_admission("unsupported startup profile: #{profile_id}") unless route
  graph_route = normalize_role_context_route!(role_context_route)
  registry_relative = graph_route ? GRAPH_PROFILE_REGISTRY_RELATIVE : PROFILE_REGISTRY_RELATIVE
  registry_path = graph_route ? contained_file(registry_relative) : PROFILE_REGISTRY
  registry_bytes = registry_path.binread
  registry = YAML.safe_load(registry_bytes, aliases: true)
  expected_status = graph_route ? "shadow_not_default" : "active"
  fail_admission("skill-load profile registry is not admitted for this route") unless registry.is_a?(Hash) && registry["status"] == expected_status
  selected_profile_id = if graph_route && profile_id == "creative_development_director"
    graph_route.fetch("cdd_profile_id")
  else
    profile_id
  end
  selected_checkpoint_id = if graph_route && profile_id == "creative_development_director"
    graph_route.fetch("cdd_checkpoint_id")
  else
    route.fetch("checkpoint_id")
  end
  profile = Array(registry["profiles"]).find { |row| row["profile_id"] == selected_profile_id }
  fail_admission("startup profile is missing: #{selected_profile_id}") unless profile
  if graph_route
    if profile_id == "overall_director"
      fail_admission("graph Overall startup role mismatch") unless profile["role"] == "overall_director"
    else
      fail_admission("graph CDD startup role mismatch") unless GRAPH_PLANNING_CDD_PROFILES.include?(profile["role"])
    end
    unless Array(profile["stage_ids"]).map(&:to_s).include?(graph_route.fetch("stage_id"))
      fail_admission("graph startup stage is outside the exact selected profile")
    end
  else
    fail_admission("startup profile role mismatch: #{profile_id}") unless profile["role"] == route["role"]
  end
  checkpoint = Array(profile.dig("phase_load", "checkpoints")).find { |row| row["checkpoint_id"] == selected_checkpoint_id }
  fail_admission("startup checkpoint is missing: #{selected_checkpoint_id}") unless checkpoint
  fail_admission("startup checkpoint must use a fresh input digest") unless checkpoint["fresh_input_digest"] == true

  skill_map = Array(registry["skill_bindings"]).to_h { |row| [row["binding_id"], row] }
  read_map = Array(registry["read_bindings"]).to_h { |row| [row["binding_id"], row] }
  build = lambda do |ids, map, kind|
    Array(ids).map do |binding_id|
      row = map[binding_id]
      fail_admission("#{selected_profile_id}.#{selected_checkpoint_id} has an unknown #{kind} binding: #{binding_id}") unless row
      record = row.slice("binding_id", "path", "revision", "sha256", "eof_required")
      fail_admission("#{record['path']} must require EOF") unless record["eof_required"] == true
      actual = sha256_file(contained_file(record["path"]))
      fail_admission("startup binding SHA-256 is stale: #{record['path']}") unless actual == record["sha256"]
      record
    end
  end
  skills = build.call(checkpoint["required_skill_ids"], skill_map, "skill")
  reads = build.call(checkpoint["required_read_ids"], read_map, "read")
  fail_admission("startup profile must load at least one owning skill") if skills.empty?

  {
    "registry" => {"path" => registry_relative, "sha256" => sha256_bytes(registry_bytes)},
    "selected_profile" => {
      "profile_id" => selected_profile_id,
      "checkpoint_id" => selected_checkpoint_id,
      "role" => profile.fetch("role"),
      "skills" => skills,
      "reads" => reads
    }
  }
end

def attach_role_context_pack!(profile_data, run_binding, role_context_route: nil)
  graph_route = normalize_role_context_route!(role_context_route)
  profile = profile_data.fetch("selected_profile")
  role = profile.fetch("role")
  recipient = if role == "overall_director"
                {"role" => "founder"}
              elsif graph_route && %w[planning_cdd_p2 planning_cdd_p3_ci].include?(role)
                {"role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}
              else
                {"role" => "overall_director"}
              end
  authority = if role == "overall_director"
    {"assigned_owner" => role, "promotion_owner" => role, "founder_gate_owner" => "founder"}
  else
    {"assigned_owner" => role, "promotion_owner" => recipient.fetch("role"), "founder_gate_owner" => "founder"}
  end
  creative_sources = %w[run_manifest plan canvas].map do |source_id|
    pointer = run_binding.fetch(source_id)
    row = {
      "source_id" => source_id,
      "path" => pointer.fetch("path"),
      "sha256" => pointer.fetch("sha256"),
      "purpose" => "Exact current startup source; inspect only when the assigned current job requires its bytes."
    }
    if graph_route
      row.merge!(
        "locator" => "document_root",
        "function" => "current_run_#{source_id}",
        "role_groups" => ["startup", role],
        "disposition" => "applied"
      )
    end
    row
  end
  stage_id = graph_route ? graph_route.fetch("stage_id") : "startup_admission"
  section_ids = graph_route ? graph_route.fetch("section_ids") : []
  founder_quality_context = IdolRoleContextPack.extract_founder_quality_context(
    ROOT,
    {"run" => run_binding.fetch("run_root")},
    role: role,
    profile_id: profile.fetch("profile_id"),
    stage_id: stage_id,
    section_ids: section_ids
  )
  pack = IdolRoleContextPack.build(
    root: ROOT,
    run_root: run_binding.fetch("run_root"),
    assignment_id: "STARTUP_#{run_binding.fetch('run_root').split('/').last}_#{role}",
    role: role,
    profile_id: profile.fetch("profile_id"),
    checkpoint_id: profile.fetch("checkpoint_id"),
    stage_id: stage_id,
    section_ids: section_ids,
    source_envelope: run_binding.fetch("run_manifest").merge("kind" => "startup_admission"),
    current_state: "prepared",
    scope: {
      "stage_id" => stage_id,
      "mode" => graph_route ? "graph_shadow_pilot_startup" : "current_run_startup",
      "section_ids" => section_ids,
      "section_cohort_id" => graph_route && graph_route["section_cohort_id"]
    },
    non_scope: %w[paid_generation external_mutation public_release automatic_creative_promotion],
    authority: authority,
    founder_epoch: run_binding.fetch("founder_epoch"),
    founder_locks: [],
    creative_sources: creative_sources,
    output_contract: {"kind" => role == "overall_director" ? "overall_current_assignment_delta" : "cdd_startup_receipt"},
    hold_conditions: %w[stale_bound_source owner_conflict illegal_stage_jump provider_snapshot_mismatch],
    return_recipient: recipient,
    provider: "grok",
    runtime_surface: "grok_cli_acp_or_tui",
    founder_quality_context: founder_quality_context,
    writer: graph_route ? graph_route.fetch("writer") : IdolRoleContextPack::LEGACY_WRITER,
    run_class: graph_route && graph_route.fetch("run_class"),
    switch_receipt: graph_route && graph_route.fetch("switch_receipt")
  )
  errors = IdolRoleContextPack.validate_pack(root: ROOT, pack: pack)
  errors.concat(pack.fetch("hold_reasons")) if pack.fetch("status") == "hold"
  fail_admission("role context pack is held: #{errors.uniq.join('; ')}") unless errors.empty?
  profile_data.merge("role_context_pack" => pack)
rescue IdolRoleContextPack::ContractError, KeyError => e
  fail_admission("role context pack admission failed: #{e.message}")
end

def role_context_receipt(pack)
  {
    "schema_version" => pack.fetch("schema_version"),
    "pack_id" => pack.fetch("pack_id"),
    "pack_digest" => pack.dig("projection", "pack_digest"),
    "source_set_sha256" => pack.dig("projection", "source_set_sha256"),
    "provider_profile_id" => pack.dig("provider_binding", "provider_profile_id"),
    "status" => "applied"
  }
end

def verify_role_context_receipt!(value, pack)
  fail_admission("role_context_receipt must be an object") unless value.is_a?(Hash)
  expected = role_context_receipt(pack)
  fail_admission("role_context_receipt must exact-copy the compiled startup pack receipt") unless value == expected
end

def run_pointer_lines(binding)
  [
    "- run_root: #{binding['run_root']}",
    "- run_manifest: #{binding.dig('run_manifest', 'path')} | sha256=#{binding.dig('run_manifest', 'sha256')}",
    "- plan: #{binding.dig('plan', 'path')} | sha256=#{binding.dig('plan', 'sha256')}",
    "- canvas: #{binding.dig('canvas', 'path')} | sha256=#{binding.dig('canvas', 'sha256')}",
    "- founder_epoch: #{binding['founder_epoch']}",
    "- active_owner_role: #{binding['active_owner_role']}"
  ]
end

def base_packet(action, status, run_binding, profile_data, founder_sha: nil, delta_sha: nil, prompt: nil, controller_text: nil, holds: [])
  prompt_sha = prompt.nil? ? nil : sha256_bytes(prompt)
  input_basis = {
    "action" => action,
    "run_binding" => run_binding,
    "profile_registry" => profile_data["registry"],
    "selected_profile" => profile_data["selected_profile"],
    "role_context_pack_digest" => profile_data.dig("role_context_pack", "projection", "pack_digest"),
    "founder_message_sha256" => founder_sha,
    "director_delta_sha256" => delta_sha,
    "rendered_prompt_sha256" => prompt_sha
  }
  {
    "schema_version" => SCHEMA_VERSION,
    "status" => status,
    "action" => action,
    "run_binding" => run_binding,
    "profile_registry" => profile_data["registry"],
    "selected_profile" => profile_data["selected_profile"],
    "role_context_pack" => profile_data["role_context_pack"],
    "compiled_input_sha256" => digest_value(input_basis),
    "rendered_prompt" => prompt,
    "rendered_prompt_sha256" => prompt_sha,
    "founder_message_sha256" => founder_sha,
    "director_delta_sha256" => delta_sha,
    "controller_text" => controller_text,
    "hold_reasons" => holds.uniq
  }
end

def read_gate_prompt(run_binding, profile_data, founder_message)
  profile = profile_data["selected_profile"]
  pack = profile_data.fetch("role_context_pack")
  receipt_json = canonical_json(role_context_receipt(pack))
  request_binding = founder_request_binding(founder_message)
  prompt = [
    "[IDOL Overall Startup Read Gate]",
    "This is an admission turn in the existing Overall Director session. It does not change the IDOL stage order, create a Founder lock, start CDD work, launch a worker, write a canonical file, or authorize paid/external/public action.",
    "The deterministic compiler has verified every selected instruction source to EOF and projected the exact current-node fragments below. Apply this Role Context Pack instead of rereading the broad source closure. Inspect the hash-bound creative source bytes only as required by the current job. If any pack digest, owner, run pointer, provider snapshot, or authority is unavailable or contradictory, return status hold.",
    "",
    "[Current run pointers]",
    *run_pointer_lines(run_binding),
    "",
    "[Selected startup profile]",
    "- registry: #{profile_data.dig('registry', 'path')} | sha256=#{profile_data.dig('registry', 'sha256')}",
    "- profile/checkpoint: #{profile['profile_id']}.#{profile['checkpoint_id']}",
    "- broad dependency inventory is retained in selected_profile for mechanical invalidation only; it is not an additional runtime read list.",
    "",
    "[Graph-projected Role Context Pack]",
    IdolRoleContextPack.render_runtime_json(pack),
    "",
    founder_verbatim_block(founder_message, request_binding),
    "",
    "After applying the pack and inspecting the needed current creative sources, return exactly one final envelope and no bytes after it:",
    "<idol_startup_delta>{JSON}</idol_startup_delta>",
    "The JSON keys must be exactly: #{DELTA_KEYS.join(', ')}.",
    "founder_request_binding must exact-copy this value without a summary or paraphrase: #{canonical_json(request_binding)}",
    "status is ready or hold. role_context_receipt must exactly equal this JSON value: #{receipt_json}",
    "run_stage_lock_summary, current_creative_job, exact_scope, non_scope, required_work, and quality_proof are your own current-work prose, not a script summary.",
    "unaffected_truth, unresolved_decisions, and hold_reasons are unique non-empty string arrays. next_owner_route is overall_director, creative_development_director, or hold.",
    "A ready result requires empty hold_reasons. A hold result requires at least one concrete hold reason. Do not claim creative PASS from the receipt or from schema validity."
  ].join("\n")
  verify_exact_founder_block!(prompt, founder_message, request_binding, "Overall read-gate prompt")
  prompt
end

def extract_final_envelope!(text, marker)
  nonempty_string!(text, "assistant_output")
  open_marker = "<#{marker}>"
  close_marker = "</#{marker}>"
  fail_admission("#{marker} must appear exactly once") unless text.scan(open_marker).length == 1 && text.scan(close_marker).length == 1
  match = text.match(/\A([\s\S]*?)#{Regexp.escape(open_marker)}([\s\S]*?)#{Regexp.escape(close_marker)}\s*\z/)
  fail_admission("#{marker} must be the final bytes") unless match
  payload = JSON.parse(match[2])
  [match[1].rstrip, payload]
rescue JSON::ParserError => e
  fail_admission("#{marker} JSON is invalid: #{e.message}")
end

def validate_delta!(delta, pack, founder_message)
  exact_keys!(delta, DELTA_KEYS, "startup delta")
  fail_admission("startup delta status must be ready or hold") unless %w[ready hold].include?(delta["status"])
  verify_role_context_receipt!(delta["role_context_receipt"], pack)
  verify_founder_request_binding!(delta["founder_request_binding"], founder_message, "startup delta.founder_request_binding")
  %w[run_stage_lock_summary current_creative_job exact_scope non_scope required_work quality_proof].each do |key|
    nonempty_string!(delta[key], "startup delta.#{key}")
  end
  %w[unaffected_truth unresolved_decisions hold_reasons].each { |key| string_array!(delta[key], "startup delta.#{key}") }
  fail_admission("startup delta.next_owner_route is invalid") unless %w[overall_director creative_development_director hold].include?(delta["next_owner_route"])
  if delta["status"] == "ready"
    fail_admission("a ready startup delta must have no hold_reasons") unless delta["hold_reasons"].empty?
    fail_admission("a ready startup delta cannot route to hold") if delta["next_owner_route"] == "hold"
  else
    fail_admission("a held startup delta requires a hold reason") if delta["hold_reasons"].empty?
    fail_admission("a held startup delta must route to hold") unless delta["next_owner_route"] == "hold"
  end
  delta
end

def validate_cdd_delta!(delta, founder_message)
  exact_keys!(delta, CDD_DELTA_KEYS, "CDD startup delta")
  fail_admission("CDD startup delta status must be ready or hold") unless %w[ready hold].include?(delta["status"])
  verify_founder_request_binding!(delta["founder_request_binding"], founder_message, "CDD startup delta.founder_request_binding")
  %w[current_creative_job exact_scope non_scope required_work quality_proof].each do |key|
    nonempty_string!(delta[key], "CDD startup delta.#{key}")
  end
  %w[unaffected_truth unresolved_decisions hold_reasons].each { |key| string_array!(delta[key], "CDD startup delta.#{key}") }
  if delta["status"] == "ready"
    fail_admission("a ready CDD startup delta must have no hold_reasons") unless delta["hold_reasons"].empty?
  else
    fail_admission("a held CDD startup delta requires a hold reason") if delta["hold_reasons"].empty?
  end
  delta
end

def founder_verbatim_block(founder_message, request_binding)
  message = validate_founder_message!(founder_message)
  binding = verify_founder_request_binding!(request_binding, message, "Founder request binding")
  [
    "[Founder request exact-copy binding | #{canonical_json(binding)}]",
    "[Founder request verbatim begins | utf8_bytes=#{message.bytesize}]",
    message,
    "[Founder request verbatim ends]"
  ].join("\n")
end

def exact_occurrence_count(text, value)
  return 0 if value.empty?

  count = 0
  offset = 0
  while (found = text.index(value, offset))
    count += 1
    offset = found + value.length
  end
  count
end

def verify_exact_founder_block!(prompt, founder_message, request_binding, label)
  block = founder_verbatim_block(founder_message, request_binding)
  fail_admission("#{label} must carry the Founder request verbatim exactly once") unless exact_occurrence_count(prompt, block) == 1

  binding_marker = "[Founder request exact-copy binding | #{canonical_json(request_binding)}]"
  fail_admission("#{label} must carry exactly one hash-bound Founder request locator") unless exact_occurrence_count(prompt, binding_marker) == 1
  payload = "\n#{founder_message}\n"
  fail_admission("#{label} must not duplicate the Founder request outside its exact-copy block") unless exact_occurrence_count(prompt, payload) == 1
  prompt
end

def verify_twelve_block_founder_carry!(prompt, founder_message, request_binding, role)
  verify_exact_founder_block!(prompt, founder_message, request_binding, "#{role} compiled Assignment Delta")
  blocks = [2, 6, 8].to_h do |index|
    heading = "#{TWELVE_HEADINGS.fetch(index)}\n"
    next_heading = "\n\n#{TWELVE_HEADINGS.fetch(index + 1)}\n"
    start = prompt.index(heading)
    finish = start && prompt.index(next_heading, start + heading.length)
    block_number = format("%02d", index + 1)
    fail_admission("#{role} compiled Assignment Delta must contain one complete Block #{block_number}") unless start && finish
    [index, prompt[(start + heading.length)...finish]]
  end

  block_three = blocks.fetch(2)
  expected = founder_verbatim_block(founder_message, request_binding)
  fail_admission("#{role} compiled Assignment Delta Block 03 omitted or changed the Founder request") unless exact_occurrence_count(block_three, expected) == 1

  {
    6 => CURRENT_PRIORITY_PROJECTION_CLAUSES,
    8 => PRIORITY_CLOSURE_CLAUSES
  }.each do |index, clauses|
    block_number = format("%02d", index + 1)
    clauses.each do |clause|
      unless exact_occurrence_count(prompt, clause) == 1 && exact_occurrence_count(blocks.fetch(index), clause) == 1
        fail_admission("#{role} compiled Assignment Delta must exact-carry each current-priority rule once in Block #{block_number}")
      end
    end
  end
  prompt
end

def twelve_block_prompt(role:, run_binding:, profile_data:, delta:, founder_message:)
  profile = profile_data["selected_profile"]
  pack = profile_data.fetch("role_context_pack")
  receipt_json = canonical_json(role_context_receipt(pack))
  request_binding = verify_founder_request_binding!(delta["founder_request_binding"], founder_message, "#{role} delta.founder_request_binding")
  return_instruction = if role == "overall_director"
    [
      "Complete the Overall startup assignment in this same physical session. If CDD work is legally required, end with exactly one <idol_cdd_startup_delta>{JSON}</idol_cdd_startup_delta> envelope using exactly these keys: #{CDD_DELTA_KEYS.join(', ')}.",
      "founder_request_binding must exact-copy the binding in Block 03; never replace it with a summary or paraphrase.",
      "If CDD is not required, end with exactly one <idol_overall_startup_return>{\"status\":\"ready\",\"cdd_required\":false,\"hold_reasons\":[]}</idol_overall_startup_return> envelope. Do not emit both. No bytes may follow the selected envelope."
    ].join(" ")
  else
    [
      "Before any Song, reference, identity, or development worker launch is accepted, exact-copy the applied Role Context Pack receipt below into one <idol_cdd_startup_return>{JSON}</idol_cdd_startup_return> envelope:",
      receipt_json,
      "The JSON keys are exactly status, role_context_receipt, hold_reasons. status is ready or hold. Put this receipt before any existing fp_plan_update, fp_board_ops, or fp_dispatch control envelopes, which must retain their existing order and remain the final bytes."
    ].join(" ")
  end
  authority = role == "overall_director" ? "Founder retains final locks and PASS/HOLD/REJECT; Overall alone owns recommendation and promotion." : "CDD owns bounded pre-02A development and worker review; Overall alone owns canonical promotion and Founder presentation."
  output = role == "overall_director" ? "Return one current Overall decision/routing result and the typed CDD route or no-route envelope described in Block 12." : "Return the CDD startup receipt plus any currently authorized existing control envelopes; do not promote canonical truth."
  current_priority_projection = CURRENT_PRIORITY_PROJECTION_CLAUSES.join(" ")
  priority_closure = PRIORITY_CLOSURE_CLAUSES.join(" ")
  blocks = [
    [TWELVE_HEADINGS[0], "startup_admission=#{digest_value(delta)} | profile=#{profile['profile_id']}.#{profile['checkpoint_id']} | run=#{run_binding['run_root']} | founder_epoch=#{run_binding['founder_epoch']}"],
    [TWELVE_HEADINGS[1], "You are #{role}. #{authority} Provider/model is transport metadata and cannot change this authority."],
    [TWELVE_HEADINGS[2], "#{founder_verbatim_block(founder_message, request_binding)}\n\nDirector-authored current creative job (not a Founder quote or substitute):\n#{delta['current_creative_job']}"],
    [TWELVE_HEADINGS[3], "Scope: #{delta['exact_scope']}\nNon-scope: #{delta['non_scope']}\nPreserve unaffected truth:\n#{delta['unaffected_truth'].map { |item| "- #{item}" }.join("\n")}"],
    [TWELVE_HEADINGS[4], run_pointer_lines(run_binding).join("\n")],
    [TWELVE_HEADINGS[5], "Apply the exact current-node Role Context Pack below. The compiler already verified its full registered source closure; this pack replaces broad instruction rereads and is not an extra layer. Inspect the hash-bound creative sources only as required by the current job.\n#{IdolRoleContextPack.render_runtime_json(pack)}"],
    [TWELVE_HEADINGS[6], "#{delta['required_work']}\n\nCurrent-priority projection rule:\n#{current_priority_projection}"],
    [TWELVE_HEADINGS[7], output],
    [TWELVE_HEADINGS[8], "#{delta['quality_proof']}\n\nPriority closure proof:\n#{priority_closure}"],
    [TWELVE_HEADINGS[9], "Return only after the Role Context Pack receipt is exact, the needed current creative source bytes are inspected, the named current job is answered with current-work evidence, Founder locks and unaffected truth are preserved, and the typed return envelope is complete."],
    [TWELVE_HEADINGS[10], "HOLD on stale/missing bytes, owner or scope conflict, illegal stage jump, unbound Founder decision, or any paid/external/public action without separate approval. Unresolved decisions:\n#{delta['unresolved_decisions'].map { |item| "- #{item}" }.join("\n")}"],
    [TWELVE_HEADINGS[11], return_instruction]
  ]
  prompt = blocks.map { |heading, body| "#{heading}\n#{body}" }.join("\n\n")
  verify_twelve_block_founder_carry!(prompt, founder_message, request_binding, role)
  prompt
end

def prepare_overall_read_gate(input)
  exact_keys_with_optional!(input, %w[action run_binding founder_message], %w[role_context_route], "input")
  founder_message = validate_founder_message!(input["founder_message"])
  run_binding = verify_run_binding!(input)
  route = normalize_role_context_route!(input["role_context_route"])
  profile_data = attach_role_context_pack!(load_profile!("overall_director", role_context_route: route), run_binding, role_context_route: route)
  prompt = read_gate_prompt(run_binding, profile_data, founder_message)
  base_packet("prepare_overall_read_gate", "prepared", run_binding, profile_data, founder_sha: sha256_bytes(founder_message), prompt: prompt)
end

def compile_overall_launch(input)
  exact_keys_with_optional!(input, %w[action run_binding founder_message assistant_output], %w[role_context_route], "input")
  founder_message = validate_founder_message!(input["founder_message"])
  run_binding = verify_run_binding!(input)
  route = normalize_role_context_route!(input["role_context_route"])
  profile_data = attach_role_context_pack!(load_profile!("overall_director", role_context_route: route), run_binding, role_context_route: route)
  _visible, raw_delta = extract_final_envelope!(input["assistant_output"], "idol_startup_delta")
  delta = validate_delta!(raw_delta, profile_data.fetch("role_context_pack"), founder_message)
  delta_sha = digest_value(delta)
  if delta["status"] == "hold"
    return base_packet("compile_overall_launch", "hold", run_binding, profile_data, founder_sha: sha256_bytes(founder_message), delta_sha: delta_sha, holds: delta["hold_reasons"])
  end
  prompt = twelve_block_prompt(
    role: "overall_director",
    run_binding: run_binding,
    profile_data: profile_data,
    delta: delta,
    founder_message: founder_message
  )
  base_packet("compile_overall_launch", "compiled", run_binding, profile_data, founder_sha: sha256_bytes(founder_message), delta_sha: delta_sha, prompt: prompt)
end

def compile_cdd_launch(input)
  exact_keys_with_optional!(input, %w[action run_binding founder_message assistant_output], %w[role_context_route], "input")
  founder_message = validate_founder_message!(input["founder_message"])
  run_binding = verify_run_binding!(input)
  route = normalize_role_context_route!(input["role_context_route"])
  overall_profile = attach_role_context_pack!(load_profile!("overall_director", role_context_route: route), run_binding, role_context_route: route)
  text = nonempty_string!(input["assistant_output"], "assistant_output")
  cdd_count = text.scan("<idol_cdd_startup_delta>").length + text.scan("</idol_cdd_startup_delta>").length
  no_route_count = text.scan("<idol_overall_startup_return>").length + text.scan("</idol_overall_startup_return>").length
  fail_admission("Overall startup return must contain exactly one CDD route or no-route envelope") unless [cdd_count, no_route_count].sort == [0, 2]

  if no_route_count == 2
    visible, payload = extract_final_envelope!(text, "idol_overall_startup_return")
    exact_keys!(payload, %w[status cdd_required hold_reasons], "Overall startup return")
    fail_admission("Overall no-route status must be ready") unless payload["status"] == "ready"
    fail_admission("Overall no-route cdd_required must be false") unless payload["cdd_required"] == false
    fail_admission("Overall no-route hold_reasons must be empty") unless payload["hold_reasons"] == []
    return base_packet("compile_cdd_launch", "no_route", run_binding, overall_profile, founder_sha: sha256_bytes(founder_message), controller_text: visible)
  end

  visible, raw_delta = extract_final_envelope!(text, "idol_cdd_startup_delta")
  delta = validate_cdd_delta!(raw_delta, founder_message)
  delta_sha = digest_value(delta)
  profile_data = attach_role_context_pack!(load_profile!("creative_development_director", role_context_route: route), run_binding, role_context_route: route)
  if delta["status"] == "hold"
    return base_packet("compile_cdd_launch", "hold", run_binding, profile_data, founder_sha: sha256_bytes(founder_message), delta_sha: delta_sha, controller_text: visible, holds: delta["hold_reasons"])
  end
  prompt = twelve_block_prompt(
    role: profile_data.dig("selected_profile", "role"),
    run_binding: run_binding,
    profile_data: profile_data,
    delta: delta,
    founder_message: founder_message
  )
  base_packet("compile_cdd_launch", "compiled", run_binding, profile_data, founder_sha: sha256_bytes(founder_message), delta_sha: delta_sha, prompt: prompt, controller_text: visible)
end

def validate_cdd_return(input)
  exact_keys_with_optional!(input, %w[action run_binding founder_message assistant_output], %w[role_context_route], "input")
  founder_message = validate_founder_message!(input["founder_message"])
  run_binding = verify_run_binding!(input)
  route = normalize_role_context_route!(input["role_context_route"])
  profile_data = attach_role_context_pack!(load_profile!("creative_development_director", role_context_route: route), run_binding, role_context_route: route)
  text = nonempty_string!(input["assistant_output"], "assistant_output")
  open_marker = "<idol_cdd_startup_return>"
  close_marker = "</idol_cdd_startup_return>"
  fail_admission("CDD startup receipt must appear exactly once") unless text.scan(open_marker).length == 1 && text.scan(close_marker).length == 1
  match = text.match(/\A([\s\S]*?)#{Regexp.escape(open_marker)}([\s\S]*?)#{Regexp.escape(close_marker)}\s*([\s\S]*)\z/)
  fail_admission("CDD startup receipt is malformed") unless match
  payload = JSON.parse(match[2])
  exact_keys!(payload, %w[status role_context_receipt hold_reasons], "CDD startup receipt")
  fail_admission("CDD startup receipt status must be ready or hold") unless %w[ready hold].include?(payload["status"])
  verify_role_context_receipt!(payload["role_context_receipt"], profile_data.fetch("role_context_pack"))
  string_array!(payload["hold_reasons"], "CDD startup receipt.hold_reasons")
  if payload["status"] == "ready"
    fail_admission("ready CDD startup receipt must have no hold reasons") unless payload["hold_reasons"].empty?
  else
    fail_admission("held CDD startup receipt requires a hold reason") if payload["hold_reasons"].empty?
  end
  controller_text = [match[1].rstrip, match[3].strip].reject(&:empty?).join("\n")
  status = payload["status"] == "ready" ? "validated" : "hold"
  base_packet("validate_cdd_return", status, run_binding, profile_data, founder_sha: sha256_bytes(founder_message), delta_sha: digest_value(payload), controller_text: controller_text, holds: payload["hold_reasons"])
rescue JSON::ParserError => e
  fail_admission("CDD startup receipt JSON is invalid: #{e.message}")
end

def main
  bytes = STDIN.binmode.read(MAX_INPUT_BYTES + 1)
  fail_admission("startup admission input exceeds #{MAX_INPUT_BYTES} bytes") if bytes.bytesize > MAX_INPUT_BYTES
  input = JSON.parse(bytes)
  action = input["action"]
  result = case action
  when "prepare_overall_read_gate" then prepare_overall_read_gate(input)
  when "compile_overall_launch" then compile_overall_launch(input)
  when "compile_cdd_launch" then compile_cdd_launch(input)
  when "validate_cdd_return" then validate_cdd_return(input)
  else fail_admission("unsupported startup admission action: #{action}")
  end
  puts JSON.pretty_generate(result)
  0
rescue JSON::ParserError => e
  warn JSON.generate({"status" => "hold", "errors" => ["startup admission input JSON is invalid: #{e.message}"]})
  1
rescue StartupAdmissionError, Errno::ENOENT, Psych::SyntaxError => e
  warn JSON.generate({"status" => "hold", "errors" => [e.message]})
  1
end

exit(main) if $PROGRAM_NAME == __FILE__
