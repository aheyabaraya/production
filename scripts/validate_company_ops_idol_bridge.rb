#!/usr/bin/env ruby
# frozen_string_literal: true

# Fail-closed Company Ops -> IDOL admission bridge. Validates structure,
# hashes, and declared gates only. Never authors creative truth or grants PASS.

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "company-ops-idol-bridge.schema.json")
CONTRACT = ROOT.join("automation", "company-ops-idol-bridge.yaml")
EXECUTION_CONTRACT = ROOT.join("automation", "harness-execution-contract.yaml")
GRAPH_ROUTING = ROOT.join("automation", "graph-default-routing.yaml")
DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb")
PACK_VALIDATOR = ROOT.join("scripts", "idol_role_context_pack.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
COPIED_TRUTH_MARKERS = [
  "idol-invariant:",
  "pre00_storyline_original",
  "Official Core Storyboard"
].freeze
POINTER_KEYS = %w[director_profile department_index navigation_skill bot_defaults].freeze
EXECUTABLE_COMMAND_KINDS = %w[validated_json compiled_intent_md].freeze
NON_EXECUTABLE_COMMAND_KINDS = %w[raw_markdown raw_yaml judgment_evidence].freeze
CLOSED_AUTHORITY = {
  "commit" => false,
  "push" => false,
  "merge" => false,
  "deploy" => false,
  "publish" => false,
  "spend" => false,
  "auth_material" => false
}.freeze

options = {json: false, record: nil, company_ops_root: nil, root: nil}
OptionParser.new do |parser|
  parser.banner = "usage: ruby scripts/validate_company_ops_idol_bridge.rb [--json] [--record PATH] [--root PATH] [--company-ops-root PATH]"
  parser.on("--json") { options[:json] = true }
  parser.on("--record PATH") { |value| options[:record] = value }
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--company-ops-root PATH") { |value| options[:company_ops_root] = value }
end.parse!

def load_mapping(path, aliases: false)
  return nil unless path.file?

  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, aliases: aliases)
          end
  value.is_a?(Hash) ? value : nil
rescue JSON::ParserError, Psych::Exception
  nil
end

def sha256(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def schema_errors(path)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return [] if status.success?

  [[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip]
end

def default_company_ops_root
  ROOT.join("..", "..", "company-ops").expand_path
end

def copied_creative_truth?(path)
  return false unless path.file?

  text = path.read
  COPIED_TRUTH_MARKERS.any? { |marker| text.include?(marker) }
end

def contained_relative(root, raw)
  return nil if raw.to_s.empty? || raw.to_s.include?("\0")

  candidate = Pathname.new(raw.to_s)
  return nil if candidate.absolute?
  return nil if candidate.each_filename.any? { |part| part == ".." || part == "." }

  root = root.expand_path
  root = root.realpath if root.exist?
  path = root.join(candidate).expand_path.cleanpath
  if path.exist? || path.symlink?
    return nil if path.symlink? && !path.exist?
    path = path.realpath
    root = root.realpath
  end
  relative = path.relative_path_from(root).to_s
  return nil if relative == ".." || relative.start_with?("../")

  [path, relative]
rescue ArgumentError, Errno::ENOENT
  nil
end

def validate_live_constants(contract)
  errors = []
  execution = load_mapping(EXECUTION_CONTRACT) || {}
  helper = execution.dig("live_worker_capacity", "provider_capacity", "grok_nonroot") || {}
  unless helper["ordinary_maximum"] == 8 && helper["reviewed_maximum"] == 8
    errors << "IDOL grok_nonroot native-helper maximum is not 8"
  end
  capacity = contract["capacity_separation"] || {}
  errors << "bridge contract idol native-helper ordinary maximum must remain 8" unless capacity["idol_native_helper_ordinary_maximum"] == 8
  errors << "bridge contract idol native-helper reviewed maximum must remain 8" unless capacity["idol_native_helper_reviewed_maximum"] == 8
  errors << "bridge contract Company Ops physical session maximum must remain 15" unless capacity["company_ops_physical_session_maximum"] == 15
  errors << "Company Ops 15-session ceiling cannot mutate IDOL helper caps" unless capacity["company_ops_may_mutate_idol_ceilings"] == false
  errors << "Company Ops and IDOL ceilings must not be multiplied" unless capacity["ceilings_are_multiplied"] == false
  errors << "cross-process occupancy must not be claimed synchronized" unless capacity["cross_process_occupancy_synchronized"] == false
  graph = load_mapping(GRAPH_ROUTING) || {}
  errors << "Graph v2 is not shadow_not_default" unless graph["status"].to_s == "shadow_not_default"
  errors << "bridge contract Graph v2 status must remain shadow_not_default" unless contract.dig("graph_v2", "status").to_s == "shadow_not_default"
  hold = contract["company_ops_runner_hold"] || {}
  errors << "HOLE-1 latch status must be latched" unless hold["status"].to_s == "latched" && hold["hole_id"].to_s == "HOLE-1"
  errors << "IDOL validator must latch Company Ops grok_runner" unless hold["idol_validator_latches_company_ops_runner"] == true
  errors
end

def validate_company_ops_pointers(contract, ops_root)
  errors = []
  return errors unless ops_root.directory?

  Array(contract["company_ops_role_bindings"]).each do |row|
    next unless row.is_a?(Hash)

    pointers = row["company_ops_pointers"]
    next unless pointers.is_a?(Hash)

    POINTER_KEYS.each do |key|
      relative = pointers[key].to_s
      path = ops_root.join(relative)
      errors << "Company Ops pointer is missing: #{relative}" unless path.file?
      errors << "Company Ops pointer copies IDOL creative truth: #{relative}" if copied_creative_truth?(path)
    end
  end
  errors
end

def load_claim_ledger(path)
  return [] unless path.file?

  rows = []
  path.each_line do |line|
    stripped = line.strip
    next if stripped.empty?

    row = JSON.parse(stripped)
    rows << row if row.is_a?(Hash)
  rescue JSON::ParserError
    next
  end
  rows
end

def invoke_dispatch_validator(path)
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    DISPATCH_VALIDATOR.to_s,
    "--json",
    path.to_s,
    chdir: ROOT.to_s
  )
  return [] if status.success?

  details = begin
    payload = JSON.parse(stdout)
    Array(payload["errors"]).join("; ")
  rescue JSON::ParserError
    [stdout, stderr].join(" ").strip
  end
  ["Department Dispatch v8 validator failed: #{details}"]
end

def invoke_pack_validator(path)
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    PACK_VALIDATOR.to_s,
    "validate",
    path.to_s,
    chdir: ROOT.to_s
  )
  return [] if status.success?

  details = begin
    payload = JSON.parse(stdout)
    Array(payload["errors"]).join("; ")
  rescue JSON::ParserError
    [stdout, stderr].join(" ").strip
  end
  ["Role Context Pack validator failed: #{details}"]
end

def allowed_path?(relative, contract)
  allow = Array(contract.dig("path_allowlist", "prefixes")).map(&:to_s)
  deny = Array(contract.dig("path_allowlist", "denied_prefixes")).map(&:to_s)
  return false if deny.any? { |prefix| relative == prefix || relative.start_with?(prefix) }

  allow.any? { |prefix| relative == prefix || relative.start_with?(prefix) }
end

def validate_record(root, contract, record)
  errors = []
  packet = record["company_ops_packet"] || {}
  admission = record["idol_admission"] || {}
  authority = record["authority"] || {}
  capacity = record["capacity"] || {}
  cursor = record["cursor_cloud"] || {}
  improvement = record["improvement"] || {}
  invalidation = record["invalidation_state"] || {}
  restart = record["restart_state"] || {}
  execution = record["execution"] || {}

  %w[packet_digest author_agent_id assigned_role_id profile_id session_id writer_lease_id lane_id input_digest native_goal_name].each do |field|
    errors << "packet #{field} is unbound" if packet[field].to_s.empty?
  end
  errors << "packet writer_lease_version is unbound" unless packet["writer_lease_version"].is_a?(Integer) && packet["writer_lease_version"] >= 1

  allowed_roles = Array(contract["company_ops_role_bindings"]).map { |row| row.is_a?(Hash) ? row["company_ops_role_id"].to_s : "" }
  unless allowed_roles.include?(packet["assigned_role_id"].to_s)
    errors << "assigned Company Ops role is not bound to harness_maintenance: #{packet['assigned_role_id']}"
  end
  if admission["profile_id"].to_s == "harness_maintenance" && packet["assigned_role_id"].to_s != "kurisu.idol_graph_cdd"
    errors << "harness_maintenance ingress requires kurisu.idol_graph_cdd"
  end

  grok_build = packet["provider"].to_s == "grok-build" && admission["runtime_surface"].to_s == "grok_build_cli_acp"
  if execution["allowed"] == true && !grok_build
    errors << "only provider grok-build with runtime_surface grok_build_cli_acp may execute on this bridge"
  end
  if packet["provider"].to_s == "grok-build"
    errors << "grok-build packet repository must be idol" unless packet["repository"].to_s == "idol"
    errors << "grok-build packet model must be grok-4.6" unless packet["model"].to_s == "grok-4.6"
    errors << "grok-build packet profile_id must be grok_4_6_xhigh" unless packet["profile_id"].to_s == "grok_4_6_xhigh"
    errors << "grok-build packet reasoning_effort must be xhigh" unless packet["reasoning_effort"].to_s == "xhigh"
    errors << "grok-build packet fallback must be none" unless packet["fallback"].to_s == "none"
    CLOSED_AUTHORITY.each do |key, value|
      errors << "grok-build packet authority.#{key} must remain false" unless packet.dig("authority", key) == value
    end
    if packet["native_goal_name"].to_s != admission["native_goal_id"].to_s
      errors << "grok-build native_goal_name must one-way map onto IDOL native_goal_id"
    end
  end

  goal_binding = contained_relative(root, admission["native_goal_path"])
  dispatch_binding = contained_relative(root, admission["dispatch_path"])
  pack_binding = contained_relative(root, admission["role_context_pack_path"])
  errors << "native Goal path escapes IDOL root" if goal_binding.nil?
  errors << "Department Dispatch path escapes IDOL root" if dispatch_binding.nil?
  errors << "Role Context Pack path escapes IDOL root" if pack_binding.nil?

  goal_ok = false
  if goal_binding
    goal_path, goal_relative = goal_binding
    errors << "native Goal file is missing: #{goal_relative}" unless goal_path.file?
    if goal_path.file?
      actual = sha256(goal_path)
      errors << "native Goal SHA-256 is stale" unless actual == admission["native_goal_sha256"].to_s
      text = goal_path.read
      errors << "native Goal id mismatch" unless text.include?(admission["native_goal_id"].to_s)
      admitted_text = text.match(/^Status:\s*(\S+)/i)
      errors << "native Goal file is not admitted" unless admitted_text && admitted_text[1].to_s.downcase == "admitted"
      goal_ok = actual == admission["native_goal_sha256"].to_s &&
                text.include?(admission["native_goal_id"].to_s) &&
                admitted_text && admitted_text[1].to_s.downcase == "admitted" &&
                admission["native_goal_status"].to_s == "admitted"
    end
  end
  errors << "native Goal is not admitted" unless admission["native_goal_status"].to_s == "admitted"

  dispatch_ok = false
  if dispatch_binding
    dispatch_path, dispatch_relative = dispatch_binding
    errors << "Department Dispatch is missing" unless dispatch_path.file?
    if dispatch_path.file?
      actual = sha256(dispatch_path)
      errors << "Department Dispatch SHA-256 is stale" unless actual == admission["dispatch_sha256"].to_s
      document = load_mapping(dispatch_path)
      errors << "Department Dispatch must use idol-department-dispatch.v8" unless document && document["schema_version"].to_s == "idol-department-dispatch.v8"
      dispatch_validator_errors = invoke_dispatch_validator(dispatch_path)
      errors.concat(dispatch_validator_errors)
      dispatch_ok = actual == admission["dispatch_sha256"].to_s &&
                    document && document["schema_version"].to_s == "idol-department-dispatch.v8" &&
                    dispatch_validator_errors.empty?
    end
  end

  pack_ok = false
  if pack_binding
    pack_path, pack_relative = pack_binding
    errors << "Role Context Pack is missing" unless pack_path.file?
    if pack_path.file?
      actual = sha256(pack_path)
      errors << "Role Context Pack SHA-256 is stale" unless actual == admission["role_context_pack_sha256"].to_s
      document = load_mapping(pack_path)
      errors << "Role Context Pack must use idol-role-context-pack.v1" unless document && document["schema_version"].to_s == "idol-role-context-pack.v1"
      pack_validator_errors = invoke_pack_validator(pack_path)
      errors.concat(pack_validator_errors)
      pack_ok = actual == admission["role_context_pack_sha256"].to_s &&
                document && document["schema_version"].to_s == "idol-role-context-pack.v1" &&
                pack_validator_errors.empty?
    end
  end

  admitted = goal_ok && dispatch_ok && pack_ok && grok_build
  if execution["allowed"] == true && !admitted
    errors << "execution is forbidden before Department Dispatch, native Goal, and Role Context Pack admission"
  end

  if NON_EXECUTABLE_COMMAND_KINDS.include?(record["command_kind"].to_s) && execution["allowed"] == true
    errors << "raw Markdown/YAML/judgment evidence cannot trigger execution"
  end
  if execution["allowed"] == true && !EXECUTABLE_COMMAND_KINDS.include?(record["command_kind"].to_s)
    errors << "only validated JSON or compiled intent Markdown may execute"
  end

  if cursor["live_post"] == true || cursor["return_kind"].to_s == "live_post" || cursor["auto_create_pr"] == true
    errors << "Cursor Cloud remains no-live-POST branch-return-only"
  end

  if authority["self_review"] == true || authority["assigned_owner"].to_s == authority["director_owner"].to_s
    errors << "worker self-review is forbidden"
    errors << "execution is forbidden after self-review" if execution["allowed"] == true
  end
  if authority["self_promote"] == true || authority["assigned_owner"].to_s == authority["promotion_owner"].to_s
    errors << "worker self-promotion is forbidden"
    errors << "execution is forbidden after self-promotion" if execution["promoted"] == true || execution["allowed"] == true
  end
  errors << "creative grandchildren are forbidden" if authority["may_create_grandchildren"] == true
  if authority["submission_number"].to_i > 3
    errors << "fourth submission is forbidden; HOLD or route upstream"
    errors << "execution is forbidden after three submissions" if execution["allowed"] == true
  end
  if packet["lane_id"].to_s != admission["lane_id"].to_s
    errors << "worker cannot take another lane"
    errors << "execution is forbidden on another lane" if execution["allowed"] == true
  end
  if authority["founder_conversation_owner"] == true || authority["inherits_founder_or_external_authority"] == true
    errors << "worker cannot inherit Founder or external authority"
    errors << "execution is forbidden with inherited Founder authority" if execution["allowed"] == true
  end

  errors << "IDOL native-helper maximum must remain 8" unless capacity["idol_native_helper_maximum"] == 8
  errors << "Company Ops physical session maximum must remain 15" unless capacity["company_ops_physical_session_maximum"] == 15
  if capacity["company_ops_may_mutate_idol_ceilings"] == true || capacity["ceilings_are_multiplied"] == true
    errors << "Company Ops 15-session capacity cannot mutate IDOL 8-native-helper or lane ceilings"
  end
  if [8, 120].include?(capacity["company_ops_physical_session_maximum"].to_i)
    errors << "Company Ops session ceiling must not overwrite the IDOL helper ceiling"
  end
  if capacity["idol_native_helper_maximum"].to_i == 15
    errors << "Company Ops session ceiling must not overwrite the IDOL helper ceiling"
  end

  errors << "competing improvement loop is forbidden" if improvement["competing_loop"] == true
  errors << "proposer-only approval is forbidden" if improvement["proposer_only_approval"] == true
  errors << "active-Goal hot swap is forbidden" if improvement["active_goal_hot_swap"] == true
  errors << "automatic preference promotion is forbidden" if improvement["automatic_preference_promotion"] == true
  if improvement["kind"].to_s == "governing" && improvement["founder_approval"] != true
    errors << "governing instruction/policy/schema/skill/provider change requires Founder approval"
  end

  if !packet["allowed_paths"].is_a?(Array) || packet["allowed_paths"].empty?
    errors << "packet allowed_paths is unbound"
  end
  Array(packet["allowed_paths"]).each do |raw|
    binding = contained_relative(root, raw)
    if binding.nil?
      errors << "allowed_paths entry escapes IDOL root: #{raw}"
      next
    end

    _path, relative = binding
    unless allowed_path?(relative, contract)
      errors << "allowed_paths entry is outside harness-maintenance write scope: #{relative}"
    end
  end

  Array(invalidation["frozen_outputs"]).each do |row|
    next unless row.is_a?(Hash)

    binding = contained_relative(root, row["path"])
    next if binding.nil?

    path, = binding
    next unless path.file?

    actual = sha256(path)
    if actual != row["sha256"].to_s
      repair_paths = Array(invalidation["repair_targets"]).map { |item| item.is_a?(Hash) ? item["path"].to_s : "" }
      errors << "unaffected frozen hash changed: #{row['path']}" unless repair_paths.include?(row["path"].to_s)
    end
  end

  ledger_raw = restart["ledger_path"].to_s
  ledger_raw = contract.dig("restart", "claim_ledger_path").to_s if ledger_raw.empty?
  ledger_binding = contained_relative(root, ledger_raw)
  if ledger_binding.nil?
    errors << "claim ledger path escapes IDOL root"
    prior = []
  else
    ledger_path, = ledger_binding
    prior = load_claim_ledger(ledger_path)
  end
  claim_id = restart["claim_id"].to_s
  packet_digest = packet["packet_digest"].to_s
  matching = prior.select do |row|
    row["claim_id"].to_s == claim_id || row["packet_digest"].to_s == packet_digest
  end
  if execution["claimed"] == true && matching.any? { |row| %w[claimed promoted].include?(row["state"].to_s) }
    errors << "duplicate claim is forbidden"
  end
  if execution["promoted"] == true && matching.any? { |row| row["state"].to_s == "promoted" }
    errors << "duplicate promotion is forbidden"
  end
  if restart["resume_from_durable_claim"] == true && execution["claimed"] == true
    errors << "lost-wake resume must reuse the durable claim without a second claim"
  end

  graph = load_mapping(GRAPH_ROUTING) || {}
  if admission["graph_v2_status"].to_s != "shadow_not_default" || admission["graph_v2_switch_receipt"].to_s != ""
    if graph["status"].to_s == "shadow_not_default"
      errors << "Graph v2 remains shadow_not_default; verified_default is refused"
    end
  end

  if %w[returned promoted].include?(execution["state"].to_s) && execution["output_digest"].to_s.empty?
    errors << "output digest is unbound"
  end

  errors
end

errors = []
errors.concat(schema_errors(CONTRACT).map { |message| "bridge contract schema: #{message}" })
contract = load_mapping(CONTRACT)
if contract.nil?
  errors << "bridge contract is missing or unreadable: #{CONTRACT.relative_path_from(ROOT)}"
else
  errors.concat(validate_live_constants(contract))
  ops_root = if options[:company_ops_root]
               Pathname.new(options[:company_ops_root]).expand_path
             else
               default_company_ops_root
             end
  errors.concat(validate_company_ops_pointers(contract, ops_root))
end

artifact_root = ROOT
if options[:root]
  requested = Pathname.new(options[:root]).expand_path
  if requested.exist?
    requested = requested.realpath
  end
  artifact_root = requested
end

if options[:record]
  record_path = Pathname.new(options[:record])
  record_path = ROOT.join(record_path) unless record_path.absolute?
  errors.concat(schema_errors(record_path).map { |message| "ingress record schema: #{message}" })
  record = load_mapping(record_path)
  if record.nil?
    errors << "ingress record is missing or unreadable: #{record_path}"
  elsif contract
    errors.concat(validate_record(artifact_root, contract, record))
  end
end

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "contract" => CONTRACT.relative_path_from(ROOT).to_s,
  "record" => options[:record],
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
else
  puts "company-ops-idol-bridge: #{result['status']}"
  errors.each { |error| warn error }
end

exit(errors.empty? ? 0 : 1)
