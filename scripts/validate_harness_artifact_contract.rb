#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "tempfile"
require "yaml"

REPO_ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_ENVELOPE_SCHEMA = REPO_ROOT.join("schemas", "harness-artifact-envelope.schema.json")
DEFAULT_STAGE_REGISTRY = REPO_ROOT.join("automation", "harness-stage-registry.yaml")
SCHEMA_VALIDATOR = REPO_ROOT.join("scripts", "validate_json_schema.py")
PYTHON_LAUNCHER = REPO_ROOT.join("scripts", "idol-video-python")
EXPECTED_SCHEMA_VERSION = "idol-harness-artifact-envelope.v1"
SECTION_SLICE_SCHEMA = "schemas/harness-section-slice.schema.json"
SECTION_SLICE_KIND = "harness_section_slice"
SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze
RESUMABLE_FOUNDER_STATES = %w[clear not_applicable].freeze
MEMBER_CARRY_MODES = %w[member_led mixed_member_world].freeze
GROUP_CARRY_MODES = %w[unit_or_group_led].freeze

options = {
  root: REPO_ROOT,
  envelope_schema: DEFAULT_ENVELOPE_SCHEMA,
  registry: DEFAULT_STAGE_REGISTRY,
  json: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_harness_artifact_contract.rb [options] PATH"
  opts.on("--root PATH", String, "Repository root for schema and repo-relative reference paths") do |value|
    options[:root] = Pathname.new(value).expand_path
  end
  opts.on("--envelope-schema PATH", String, "Artifact envelope schema path") do |value|
    options[:envelope_schema] = Pathname.new(value).expand_path
  end
  opts.on("--registry PATH", String, "Graph Engineering stage registry path") do |value|
    options[:registry] = Pathname.new(value).expand_path
  end
  opts.on("--json", "Emit a machine-readable result") do
    options[:json] = true
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser
  exit 2
end

contract_arg = ARGV.shift
if contract_arg.to_s.strip.empty? || !ARGV.empty?
  warn parser
  exit 2
end

def blank?(value)
  return true if value.nil?
  return value.strip.empty? if value.is_a?(String)
  return value.empty? if value.respond_to?(:empty?)

  false
end

def load_document(path)
  text = path.read
  document = if path.extname.downcase == ".json"
               JSON.parse(text)
             else
               YAML.safe_load(text, permitted_classes: [Date, Time], aliases: false)
             end
  raise TypeError, "document root must be a mapping" unless document.is_a?(Hash)

  document
end

def canonicalize(value)
  case value
  when Hash
    value.each_with_object({}) do |(key, child), normalized|
      normalized[key.to_s] = canonicalize(child)
    end.sort.to_h
  when Array
    value.map { |child| canonicalize(child) }
  when Date, Time, DateTime
    value.iso8601
  else
    value
  end
end

def payload_digest(payload)
  Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
end

def resolve_path(raw_path, root)
  return nil if blank?(raw_path)

  path = Pathname.new(raw_path.to_s)
  path.absolute? ? path.cleanpath : root.join(path).cleanpath
end

def within_directory?(path, directory)
  normalized_path = path.expand_path.cleanpath.to_s
  normalized_directory = directory.expand_path.cleanpath.to_s
  normalized_path == normalized_directory || normalized_path.start_with?(normalized_directory + File::SEPARATOR)
end

def run_schema_validation(schema_path, document_path)
  stdout, stderr, status = Open3.capture3(
    PYTHON_LAUNCHER.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema_path.to_s,
    document_path.to_s
  )
  output = [stdout, stderr].join("\n").lines.map(&:strip).reject(&:empty?)
  [status.success?, output]
rescue Errno::ENOENT => e
  [false, ["schema validator could not run: #{e.message}"]]
end

def parse_revision_contract(path, label, errors)
  return nil unless path&.file?

  document = load_document(path)
  unless document["schema_version"] == EXPECTED_SCHEMA_VERSION && document["envelope"].is_a?(Hash) && document["payload"].is_a?(Hash)
    errors << "#{label} is not an #{EXPECTED_SCHEMA_VERSION} contract: #{path}"
    return nil
  end
  document
rescue JSON::ParserError, Psych::SyntaxError, TypeError => e
  errors << "#{label} parse error for #{path}: #{e.message}"
  nil
end

def reference_identity(reference)
  [reference["artifact_id"], reference["revision"], reference["content_digest"]].map(&:to_s).join("|")
end

def frequencies(values)
  values.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }
end

def verify_reference(reference, label, root, stage_ids, current_path, errors)
  return unless reference.is_a?(Hash)

  path = resolve_path(reference["path"], root)
  unless path&.file?
    errors << "#{label}.path is not a readable file: #{reference['path']}"
    return
  end
  if path.expand_path.cleanpath == current_path.expand_path.cleanpath
    errors << "#{label}.path may not point to the current contract"
    return
  end

  declared_digest = reference["content_digest"].to_s
  unless declared_digest.match?(SHA256_PATTERN)
    errors << "#{label}.content_digest must be a lowercase SHA-256 digest"
    return
  end

  case reference["ref_type"]
  when "legacy_snapshot"
    actual_digest = Digest::SHA256.file(path.to_s).hexdigest
    errors << "#{label}.content_digest mismatch for legacy snapshot #{reference['path']}" unless declared_digest == actual_digest
    errors << "#{label}.revision must be null for legacy_snapshot" unless reference["revision"].nil?
  when "artifact_revision"
    document = parse_revision_contract(path, label, errors)
    return unless document

    envelope = document["envelope"]
    actual_digest = payload_digest(document["payload"])
    errors << "#{label}.artifact_id does not match referenced contract" unless reference["artifact_id"].to_s == envelope["artifact_id"].to_s
    errors << "#{label}.stage_id does not match referenced contract" unless reference["stage_id"].to_s == envelope["stage_id"].to_s
    errors << "#{label}.revision does not match referenced contract" unless reference["revision"] == envelope["revision"]
    errors << "#{label}.content_digest does not match referenced envelope" unless declared_digest == envelope["content_digest"].to_s
    errors << "#{label}.content_digest does not match referenced payload" unless declared_digest == actual_digest
  else
    errors << "#{label}.ref_type is not supported: #{reference['ref_type'].inspect}"
  end

  stage_id = reference["stage_id"]
  if !stage_id.nil? && !stage_ids.include?(stage_id.to_s)
    errors << "#{label}.stage_id is not registered: #{stage_id}"
  end
end

def endpoint_nil?(endpoint)
  endpoint.is_a?(Hash) && endpoint["audio_section_id"].nil? && endpoint["visual_section_id"].nil?
end

def endpoint_complete?(endpoint)
  endpoint.is_a?(Hash) && !blank?(endpoint["audio_section_id"]) && !blank?(endpoint["visual_section_id"])
end

def endpoint_matches?(endpoint, namespace)
  endpoint.is_a?(Hash) &&
    endpoint["audio_section_id"].to_s == namespace["audio_section_id"].to_s &&
    endpoint["visual_section_id"].to_s == namespace["visual_section_id"].to_s
end

def validate_transition(transition, direction, namespace, feedback_ids, errors)
  label = "payload.transition_#{direction}"
  return errors << "#{label} must be a mapping" unless transition.is_a?(Hash)

  from = transition["from"]
  to = transition["to"]
  boundary_kind = transition["boundary_kind"].to_s

  [from, to].each_with_index do |endpoint, index|
    next if endpoint_nil?(endpoint) || endpoint_complete?(endpoint)

    errors << "#{label}.#{index.zero? ? 'from' : 'to'} must set both audio_section_id and visual_section_id, or set both to null"
  end

  if direction == "in"
    errors << "#{label}.to must match the active audio and visual section ids" unless endpoint_matches?(to, namespace)
    errors << "#{label}.boundary_kind may not be exit" if boundary_kind == "exit"
  else
    errors << "#{label}.from must match the active audio and visual section ids" unless endpoint_matches?(from, namespace)
    errors << "#{label}.boundary_kind may not be entry" if boundary_kind == "entry"
  end

  case boundary_kind
  when "entry"
    errors << "#{label}.from must be null at an entry boundary" unless endpoint_nil?(from)
    errors << "#{label}.to must be a complete section endpoint" unless endpoint_complete?(to)
  when "internal"
    errors << "#{label}.from and .to must both be complete at an internal boundary" unless endpoint_complete?(from) && endpoint_complete?(to)
  when "exit"
    errors << "#{label}.from must be a complete section endpoint" unless endpoint_complete?(from)
    errors << "#{label}.to must be null at an exit boundary" unless endpoint_nil?(to)
  end

  Array(transition["feedback_ref_ids"]).each do |ref_id|
    errors << "#{label}.feedback_ref_ids contains unknown feedback ref #{ref_id}" unless feedback_ids.include?(ref_id.to_s)
  end
  if %w[blocked needs_founder].include?(transition["status"].to_s) && Array(transition["blockers"]).empty?
    errors << "#{label}.blockers must explain a blocked or needs_founder transition"
  end
end

root = options[:root].expand_path.cleanpath
contract_path = resolve_path(contract_arg, root)
envelope_schema = options[:envelope_schema]
envelope_schema = root.join(envelope_schema).cleanpath unless envelope_schema.absolute?
registry_path = options[:registry]
registry_path = root.join(registry_path).cleanpath unless registry_path.absolute?

unless contract_path&.file?
  warn "ERROR: contract is not readable: #{contract_arg}"
  exit 1
end
unless envelope_schema.file?
  warn "ERROR: envelope schema is not readable: #{envelope_schema}"
  exit 1
end
unless registry_path.file?
  warn "ERROR: stage registry is not readable: #{registry_path}"
  exit 1
end

begin
  contract = load_document(contract_path)
  registry = load_document(registry_path)
rescue JSON::ParserError, Psych::SyntaxError, TypeError => e
  warn "ERROR: parse error: #{e.message}"
  exit 1
end

errors = []
warnings = []
schema_errors = []
revision_errors = []
payload_contract_errors = []

envelope_schema_ok, envelope_schema_output = run_schema_validation(envelope_schema, contract_path)
schema_errors.concat(envelope_schema_output) unless envelope_schema_ok

envelope = contract["envelope"].is_a?(Hash) ? contract["envelope"] : {}
payload = contract["payload"].is_a?(Hash) ? contract["payload"] : {}

payload_schema_path = resolve_path(envelope["payload_schema"], root)
schemas_root = root.join("schemas")
if payload_schema_path.nil? || !payload_schema_path.file? || !within_directory?(payload_schema_path, schemas_root)
  schema_errors << "envelope.payload_schema must resolve to a readable schema under schemas/: #{envelope['payload_schema']}"
else
  Tempfile.create(["idol-harness-payload-", ".json"]) do |tempfile|
    tempfile.write(JSON.pretty_generate(canonicalize(payload)))
    tempfile.flush
    payload_schema_ok, payload_schema_output = run_schema_validation(payload_schema_path, Pathname.new(tempfile.path))
    schema_errors.concat(payload_schema_output) unless payload_schema_ok
  end
end

stage_ids = Array(registry["stages"]).each_with_object([]) do |stage, result|
  result << stage["stage_id"].to_s if stage.is_a?(Hash) && !blank?(stage["stage_id"])
end.to_set
stage_by_id = Array(registry["stages"]).each_with_object({}) do |stage, result|
  result[stage["stage_id"].to_s] = stage if stage.is_a?(Hash)
end

stage_id = envelope["stage_id"].to_s
revision_errors << "envelope.stage_id is not registered: #{stage_id.inspect}" unless stage_ids.include?(stage_id)
if payload.key?("stage_id") && payload["stage_id"].to_s != stage_id
  revision_errors << "payload.stage_id must match envelope.stage_id"
end

actual_payload_digest = payload_digest(payload)
unless envelope["content_digest"].to_s == actual_payload_digest
  revision_errors << "envelope.content_digest does not match canonical payload digest"
end

revision = envelope["revision"]
parent = envelope["parent"].is_a?(Hash) ? envelope["parent"] : {}
if revision == 1
  unless parent["path"].nil? && parent["revision"].nil? && parent["content_digest"].nil?
    revision_errors << "revision 1 must declare an explicit null parent path/revision/content_digest"
  end
elsif revision.is_a?(Integer) && revision >= 2
  parent_path = resolve_path(parent["path"], root)
  unless parent_path&.file?
    revision_errors << "parent.path is not readable for revision #{revision}: #{parent['path']}"
  else
    if parent_path.expand_path.cleanpath == contract_path.expand_path.cleanpath
      revision_errors << "parent.path may not point to the current contract"
    end
    parent_document = parse_revision_contract(parent_path, "parent", revision_errors)
    if parent_document
      parent_envelope = parent_document["envelope"]
      parent_actual_digest = payload_digest(parent_document["payload"])
      revision_errors << "parent artifact_id must match current artifact_id" unless parent_envelope["artifact_id"].to_s == envelope["artifact_id"].to_s
      revision_errors << "current revision must be exactly parent revision + 1" unless revision == parent_envelope["revision"].to_i + 1
      revision_errors << "parent.revision does not match parent envelope" unless parent["revision"] == parent_envelope["revision"]
      revision_errors << "parent.content_digest does not match parent envelope" unless parent["content_digest"].to_s == parent_envelope["content_digest"].to_s
      revision_errors << "parent.content_digest does not match canonical parent payload digest" unless parent["content_digest"].to_s == parent_actual_digest
    end
  end
else
  revision_errors << "envelope.revision must be an integer >= 1"
end

upstream_refs = Array(envelope["upstream_refs"])
feedback_refs = Array(envelope["feedback_refs"])
upstream_ref_ids = upstream_refs.each_with_object([]) { |ref, ids| ids << ref["ref_id"].to_s if ref.is_a?(Hash) }
feedback_ref_ids = feedback_refs.each_with_object([]) { |ref, ids| ids << ref["ref_id"].to_s if ref.is_a?(Hash) }

upstream_refs.each_with_index do |reference, index|
  verify_reference(reference, "envelope.upstream_refs[#{index}]", root, stage_ids, contract_path, revision_errors)
end
feedback_refs.each_with_index do |reference, index|
  verify_reference(reference, "envelope.feedback_refs[#{index}]", root, stage_ids, contract_path, revision_errors)
end

[ ["upstream_refs", upstream_ref_ids], ["feedback_refs", feedback_ref_ids] ].each do |label, ids|
  frequencies(ids).each do |ref_id, count|
    revision_errors << "envelope.#{label} repeats ref_id #{ref_id.inspect}" if blank?(ref_id) || count > 1
  end
end

cross_ref_ids = upstream_ref_ids & feedback_ref_ids
cross_ref_ids.each do |ref_id|
  revision_errors << "ref_id #{ref_id.inspect} may not appear in both upstream_refs and feedback_refs"
end
upstream_identities = upstream_refs.each_with_object([]) do |ref, identities|
  identities << reference_identity(ref) if ref.is_a?(Hash)
end.to_set
feedback_refs.each do |ref|
  next unless ref.is_a?(Hash) && upstream_identities.include?(reference_identity(ref))

  revision_errors << "the same artifact revision may not appear as both upstream truth and feedback: #{ref['ref_id']}"
end

invalidation_keys = Set.new
Array(envelope["invalidates"]).each_with_index do |invalidation, index|
  label = "envelope.invalidates[#{index}]"
  next unless invalidation.is_a?(Hash)

  target_path = resolve_path(invalidation["target_path"], root)
  unless target_path&.file?
    revision_errors << "#{label}.target_path is not readable: #{invalidation['target_path']}"
    next
  end
  target_document = parse_revision_contract(target_path, label, revision_errors)
  next unless target_document

  target_envelope = target_document["envelope"]
  target_actual_digest = payload_digest(target_document["payload"])
  revision_errors << "#{label}.target_artifact_id does not match target contract" unless invalidation["target_artifact_id"].to_s == target_envelope["artifact_id"].to_s
  revision_errors << "#{label}.target_revision does not match target contract" unless invalidation["target_revision"] == target_envelope["revision"]
  revision_errors << "#{label}.target_digest does not match target envelope" unless invalidation["target_digest"].to_s == target_envelope["content_digest"].to_s
  revision_errors << "#{label}.target_digest does not match target payload" unless invalidation["target_digest"].to_s == target_actual_digest

  key = [invalidation["target_artifact_id"], invalidation["target_revision"], invalidation["target_digest"]].join("|")
  revision_errors << "#{label} duplicates another invalidation target" if invalidation_keys.include?(key)
  invalidation_keys << key
  if invalidation["target_artifact_id"].to_s == envelope["artifact_id"].to_s &&
     invalidation["target_revision"] == revision && invalidation["target_digest"].to_s == actual_payload_digest
    revision_errors << "#{label} may not invalidate the current artifact revision"
  end
end

if envelope["payload_schema"].to_s == SECTION_SLICE_SCHEMA
  revision_errors << "section-slice payloads must use artifact_kind=#{SECTION_SLICE_KIND}" unless envelope["artifact_kind"].to_s == SECTION_SLICE_KIND
  revision_errors << "payload.contract_kind must be section_slice" unless payload["contract_kind"].to_s == "section_slice"

  bindings = payload["source_bindings"].is_a?(Hash) ? payload["source_bindings"] : {}
  bound_upstream_ids = Array(bindings["upstream_ref_ids"]).map(&:to_s)
  bound_feedback_ids = Array(bindings["feedback_ref_ids"]).map(&:to_s)
  unless bound_upstream_ids.sort == upstream_ref_ids.sort
    revision_errors << "payload.source_bindings.upstream_ref_ids must exactly match envelope.upstream_refs ids"
  end
  unless bound_feedback_ids.sort == feedback_ref_ids.sort
    revision_errors << "payload.source_bindings.feedback_ref_ids must exactly match envelope.feedback_refs ids"
  end

  Array(payload["reference_function_transfers"]).each_with_index do |transfer, index|
    next unless transfer.is_a?(Hash)
    ref_id = transfer["source_ref_id"].to_s
    payload_contract_errors << "payload.reference_function_transfers[#{index}].source_ref_id is not an upstream ref: #{ref_id}" unless upstream_ref_ids.include?(ref_id)
  end
  Array(payload["selected_reference_fragments"]).each_with_index do |fragment, index|
    next unless fragment.is_a?(Hash)
    ref_id = fragment["source_ref_id"].to_s
    payload_contract_errors << "payload.selected_reference_fragments[#{index}].source_ref_id is not an upstream ref: #{ref_id}" unless upstream_ref_ids.include?(ref_id)
  end

  mechanical_merge = payload["mechanical_merge"].is_a?(Hash) ? payload["mechanical_merge"] : {}
  mechanical_source_ref_id = mechanical_merge["source_ref_id"].to_s
  mechanical_source_ref = upstream_refs.find do |reference|
    reference.is_a?(Hash) && reference["ref_id"].to_s == mechanical_source_ref_id
  end
  if mechanical_source_ref.nil?
    payload_contract_errors << "payload.mechanical_merge.source_ref_id must resolve to envelope.upstream_refs"
  elsif mechanical_merge["source_content_digest"].to_s != mechanical_source_ref["content_digest"].to_s
    payload_contract_errors << "payload.mechanical_merge.source_content_digest must match its upstream source digest"
  end

  record_group_ids = []
  Array(mechanical_merge["record_groups"]).each_with_index do |group, group_index|
    label = "payload.mechanical_merge.record_groups[#{group_index}]"
    next unless group.is_a?(Hash)

    record_group_ids << group["group_id"].to_s
    source_record_indexes = Array(group["source_record_indexes"])
    source_record_keys = Array(group["source_record_keys"])
    source_record_ids = Array(group["source_record_ids"])
    embedded_records = Array(group["embedded_records"])

    case group["source_container_kind"].to_s
    when "array"
      unless source_record_indexes.length == embedded_records.length && source_record_keys.empty?
        payload_contract_errors << "#{label} array groups require one source_record_index per embedded record and no source_record_keys"
      end
    when "object"
      unless source_record_keys.length == embedded_records.length && source_record_indexes.empty?
        payload_contract_errors << "#{label} object groups require one source_record_key per embedded record and no source_record_indexes"
      end
    when "root"
      unless embedded_records.length == 1 && source_record_indexes.empty? && source_record_keys.empty? && Array(group["source_container_path"]).empty?
        payload_contract_errors << "#{label} root groups require one embedded record, an empty path, and no record indexes or keys"
      end
    end

    if !source_record_ids.empty? && source_record_ids.length != embedded_records.length
      payload_contract_errors << "#{label}.source_record_ids must be empty or match embedded_records count"
    end
    if frequencies(source_record_indexes).any? { |_index, count| count > 1 }
      payload_contract_errors << "#{label}.source_record_indexes must be unique"
    end
    if frequencies(source_record_keys).any? { |_key, count| count > 1 }
      payload_contract_errors << "#{label}.source_record_keys must be unique"
    end
  end
  if frequencies(record_group_ids).any? { |group_id, count| blank?(group_id) || count > 1 }
    payload_contract_errors << "payload.mechanical_merge.record_groups must use unique non-empty group_id values"
  end

  timing = payload["timing"].is_a?(Hash) ? payload["timing"] : {}
  if timing["start_seconds"].is_a?(Numeric) && timing["end_seconds"].is_a?(Numeric) && timing["end_seconds"] <= timing["start_seconds"]
    payload_contract_errors << "payload.timing.end_seconds must be greater than start_seconds"
  end

  namespace = payload["id_namespace"].is_a?(Hash) ? payload["id_namespace"] : {}
  unless Array(namespace["source_audio_section_ids"]).map(&:to_s).include?(namespace["audio_section_id"].to_s)
    payload_contract_errors << "payload.id_namespace.source_audio_section_ids must include the primary audio_section_id"
  end
  validate_transition(payload["transition_in"], "in", namespace, feedback_ref_ids, payload_contract_errors)
  validate_transition(payload["transition_out"], "out", namespace, feedback_ref_ids, payload_contract_errors)
  if payload.dig("transition_in", "handoff_id").to_s == payload.dig("transition_out", "handoff_id").to_s
    payload_contract_errors << "transition_in and transition_out must use distinct handoff_id values"
  end

  subject = payload["identity_and_subject"].is_a?(Hash) ? payload["identity_and_subject"] : {}
  mode = subject["frame_subject_mode"].to_s
  if MEMBER_CARRY_MODES.include?(mode) && blank?(subject["member_owner"])
    payload_contract_errors << "payload.identity_and_subject.member_owner is required for #{mode}"
  end
  if GROUP_CARRY_MODES.include?(mode) && blank?(subject["member_owner"]) && blank?(subject["unit_owner"])
    payload_contract_errors << "member_owner or unit_owner is required for #{mode}"
  end

  status = payload["status"].to_s
  if status == "done" && !Array(payload["blockers"]).empty?
    payload_contract_errors << "payload.blockers must be empty when status=done"
  end
  if %w[blocked needs_founder].include?(status) && Array(payload["blockers"]).empty?
    payload_contract_errors << "payload.blockers must explain status=#{status}"
  end
end

schema_errors.concat(payload_contract_errors)
schema_valid_actual = schema_errors.empty?
revision_coherent_actual = revision_errors.empty?

readiness = envelope["readiness"].is_a?(Hash) ? envelope["readiness"] : {}
basis = readiness["basis"].is_a?(Hash) ? readiness["basis"] : {}
%w[schema_valid revision_coherent stage_ready founder_gate next_unit_resumable].each do |axis|
  errors << "envelope.readiness.basis.#{axis} must contain explicit evidence" if Array(basis[axis]).reject { |item| blank?(item) }.empty?
end

if readiness["schema_valid"] != schema_valid_actual
  errors << "readiness.schema_valid=#{readiness['schema_valid'].inspect} does not match validation result #{schema_valid_actual}"
end
if readiness["revision_coherent"] != revision_coherent_actual
  errors << "readiness.revision_coherent=#{readiness['revision_coherent'].inspect} does not match lineage result #{revision_coherent_actual}"
end

if readiness["stage_ready"] == true
  errors << "stage_ready=true requires schema_valid=true" unless readiness["schema_valid"] == true
  errors << "stage_ready=true requires revision_coherent=true" unless readiness["revision_coherent"] == true
  if envelope["payload_schema"].to_s == SECTION_SLICE_SCHEMA
    errors << "stage_ready=true requires payload.status=done" unless payload["status"].to_s == "done"
    errors << "stage_ready=true requires no payload blockers" unless Array(payload["blockers"]).empty?
  end
end

founder_gate = readiness["founder_gate"].to_s
registry_gate = stage_by_id.dig(stage_id, "founder_gate").to_s
if registry_gate == "none" && !%w[not_applicable clear].include?(founder_gate)
  warnings << "registered stage #{stage_id} has no founder gate, but readiness.founder_gate=#{founder_gate}"
end
if readiness["next_unit_resumable"] == true
  errors << "next_unit_resumable=true requires schema_valid=true" unless readiness["schema_valid"] == true
  errors << "next_unit_resumable=true requires revision_coherent=true" unless readiness["revision_coherent"] == true
  errors << "next_unit_resumable=true requires stage_ready=true" unless readiness["stage_ready"] == true
  unless RESUMABLE_FOUNDER_STATES.include?(founder_gate)
    errors << "next_unit_resumable=true requires founder_gate clear or not_applicable"
  end
end
if %w[pending unknown].include?(founder_gate) && readiness["next_unit_resumable"] == true
  errors << "founder_gate=#{founder_gate} must keep next_unit_resumable=false"
end

errors.concat(schema_errors.map { |error| "schema: #{error}" })
errors.concat(revision_errors.map { |error| "revision: #{error}" })
errors = errors.uniq.sort
warnings = warnings.uniq.sort

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "contract" => contract_path.to_s,
  "artifact_id" => envelope["artifact_id"],
  "revision" => envelope["revision"],
  "stage_id" => stage_id,
  "payload_schema" => envelope["payload_schema"],
  "computed_content_digest" => actual_payload_digest,
  "readiness_axes" => {
    "schema_valid" => readiness["schema_valid"],
    "revision_coherent" => readiness["revision_coherent"],
    "stage_ready" => readiness["stage_ready"],
    "founder_gate" => readiness["founder_gate"],
    "next_unit_resumable" => readiness["next_unit_resumable"]
  },
  "actual_checks" => {
    "schema_valid" => schema_valid_actual,
    "revision_coherent" => revision_coherent_actual
  },
  "errors" => errors,
  "warnings" => warnings
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: Graph Engineering artifact contract verified (artifact=#{envelope['artifact_id']}, revision=#{envelope['revision']}, stage=#{stage_id}, digest=#{actual_payload_digest})"
  warnings.each { |warning| warn "WARNING: #{warning}" }
else
  errors.each { |error| warn "ERROR: #{error}" }
  warnings.each { |warning| warn "WARNING: #{warning}" }
end

exit(errors.empty? ? 0 : 1)
