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

ROOT = Pathname.new(__dir__).join("..").expand_path
OUTPUT_SCHEMA = ROOT.join("schemas/image-render-correction.schema.json")
LEGACY_OUTPUT_SCHEMA = ROOT.join("schemas/image-render-correction-v7-legacy.schema.json")
BASE_REQUEST_SCHEMA = ROOT.join("schemas/image-generation-request.schema.json")
LEGACY_BASE_REQUEST_SCHEMA = ROOT.join("schemas/image-generation-request-v11-legacy.schema.json")
CONTEXT_SCHEMA = ROOT.join("schemas/harness-context-pack.schema.json")
FRONT_PLANNING_SCHEMA = ROOT.join("schemas/front-planning-readiness.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
PYTHON_RUNNER = ROOT.join("scripts/idol-video-python")

ADAPTERS = %w[
  codex_imagegen
  openai_api_gpt_image_2
  grok_image
  xai_api_media
].freeze

READY_BASE_STATUSES = %w[
  ready
  submitted
  completed
].freeze

CORRECTION_CATEGORIES = %w[
  anatomy_repair
  identity_fidelity_repair
  lighting_integration_repair
  render_artifact_removal
  forbidden_text_or_logo_removal
  crop_safe_margin_restore
  locked_detail_restore
  color_exposure_match
  material_surface_cleanup
].freeze

PRESERVATION_FIELDS = %w[
  parent_core_cut_timing_and_section_ownership
  branch_cut_id_sequence_derivation_and_distinct_contribution
  member_visual_input_set_and_order
  visual_reference_binding_set_and_order
  explicit_founder_locks
  story_and_world
  core_action_and_gaze
  camera_geometry
  wardrobe_lane
  aspect_ratio_and_quality
  original_generated_output_retained
].freeze

SPEC_KEYS = %w[
  schema_version
  content_id
  correction_id
  packet_id
  authoring_owner
  authoring_reason
  base_request
  execution_context
  source_generated_image
  prior_review
  defect
  corrected_prompt
  preservation_assertions
  authorization_source
  attempt
].freeze

options = {run: nil, spec: nil, output: nil, write: false}
OptionParser.new do |opts|
  opts.banner = "usage: scripts/idol_prepare_image_render_correction.rb RUN --spec PATH [options]"
  opts.on("--run PATH", "Run root. Alternative to positional RUN.") { |value| options[:run] = value }
  opts.on("--spec PATH", "Human/model-authored compact correction spec.") { |value| options[:spec] = value }
  opts.on("--output PATH", "Derived correction request output path.") { |value| options[:output] = value }
  opts.on("--write", "Write the derived request. This never executes generation.") { options[:write] = true }
end.parse!

run_arg = options[:run] || ARGV.shift
abort "run path is required" if run_arg.to_s.strip.empty?
abort "--spec is required" if options[:spec].to_s.strip.empty?

def load_mapping(path, label)
  abort "missing #{label}: #{path}" unless path.file? && path.readable?

  value = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
  abort "#{label} must be a mapping: #{path}" unless value.is_a?(Hash)

  value
rescue Psych::SyntaxError => e
  abort "#{label} YAML parse failed: #{e.message}"
end

def repo_path(raw)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path.expand_path
end

def repo_relative(path)
  path.expand_path.relative_path_from(ROOT).to_s
rescue ArgumentError
  path.to_s
end

def within?(path, root)
  expanded = path.expand_path.to_s
  root_expanded = root.expand_path.to_s
  expanded == root_expanded || expanded.start_with?("#{root_expanded}#{File::SEPARATOR}")
end

def require_repo_file(raw, expected_sha: nil, label: "file", within_root: nil)
  abort "#{label} path must be repository-relative" if Pathname.new(raw.to_s).absolute?
  path = repo_path(raw)
  abort "#{label} escapes the repository: #{raw}" unless within?(path, ROOT)
  abort "#{label} must stay inside #{repo_relative(within_root)}" if within_root && !within?(path, within_root)
  abort "missing #{label}: #{raw}" unless path.file? && path.readable?

  real = path.realpath
  abort "#{label} resolves outside the repository: #{raw}" unless within?(real, ROOT)
  abort "#{label} resolves outside the owning run: #{raw}" if within_root && !within?(real, within_root)
  sha = Digest::SHA256.file(real).hexdigest
  abort "stale #{label} hash for #{raw}: expected #{expected_sha}, got #{sha}" if expected_sha && expected_sha.to_s != sha
  [real, sha]
rescue SystemCallError => e
  abort "#{label} cannot be resolved: #{e.message}"
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.to_h do |key|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      [key, canonical_value(value[source_key])]
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def json_pointer_get(document, pointer)
  return document if pointer.to_s.empty?
  abort "invalid JSON pointer: #{pointer}" unless pointer.to_s.start_with?("/")

  pointer.split("/")[1..].reduce(document) do |value, token|
    key = token.gsub("~1", "/").gsub("~0", "~")
    case value
    when Hash
      abort "JSON pointer does not resolve: #{pointer}" unless value.key?(key)
      value[key]
    when Array
      abort "JSON pointer array index is invalid: #{pointer}" unless key.match?(/\A(?:0|[1-9][0-9]*)\z/)
      index = key.to_i
      abort "JSON pointer array index is out of range: #{pointer}" unless index < value.length
      value[index]
    else
      abort "JSON pointer traverses a scalar: #{pointer}"
    end
  end
end

def require_keys(hash, keys, label)
  abort "#{label} must be a mapping" unless hash.is_a?(Hash)
  missing = keys.reject { |key| hash.key?(key) }
  abort "#{label} is missing: #{missing.join(', ')}" unless missing.empty?
end

def allow_keys(hash, keys, label)
  extras = hash.keys.map(&:to_s) - keys
  abort "#{label} has unsupported fields: #{extras.sort.join(', ')}" unless extras.empty?
end

def require_nonempty(value, label)
  abort "#{label} must be non-empty" if value.to_s.strip.empty?
  value.to_s
end

def require_sha(value, label)
  abort "#{label} must be a lowercase SHA-256" unless value.to_s.match?(/\A[a-f0-9]{64}\z/)
  value.to_s
end

def validate_schema!(schema, document, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON_RUNNER.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    document.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?

  abort ["#{label} schema validation failed", stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n")
end

def five_prompt_sections(text)
  match = text.to_s.match(
    /\AIdentity reference rule: (.*?)\nScene intent: (.*?)\nVisible details: (.*?)\nAction cue: (.*?)\nAvoid: (.*)\z/m
  )
  abort "base prompt must contain exactly the five canonical prompt sections" unless match

  {
    "identity_reference_rule" => match[1],
    "scene_intent" => match[2],
    "visible_details" => match[3],
    "action_cue" => match[4],
    "avoid" => match[5]
  }
end

def same_path?(left, right)
  left.expand_path == right.expand_path
rescue SystemCallError
  false
end

run = repo_path(run_arg)
abort "run must stay inside runs/: #{run_arg}" unless repo_relative(run).start_with?("runs/")
abort "run does not exist: #{run_arg}" unless run.directory?
run_real = run.realpath
content_id = run.basename.to_s
run_rel = repo_relative(run)

spec_path = repo_path(options[:spec])
abort "correction spec must stay inside the owning run" unless within?(spec_path, run)
spec = load_mapping(spec_path, "image render correction spec")
allow_keys(spec, SPEC_KEYS, "correction spec")
require_keys(spec, SPEC_KEYS, "correction spec")
abort "correction spec schema_version must be idol_image_render_correction_spec.v1" unless spec["schema_version"] == "idol_image_render_correction_spec.v1"
abort "correction spec content_id must match the owning run" unless spec["content_id"].to_s == content_id

correction_id = require_nonempty(spec["correction_id"], "correction_id")
abort "correction_id is invalid" unless correction_id.match?(/\AIRC_[A-Z0-9_]{2,80}\z/)
packet_id = require_nonempty(spec["packet_id"], "packet_id")
abort "packet_id is invalid" unless packet_id.match?(/\APKT_BC[0-9]{2,}_[A-Z0-9_]+\z/)
authoring_owner = spec["authoring_owner"].to_s
abort "authoring_owner is invalid" unless %w[human_authored_render_correction model_authored_render_correction].include?(authoring_owner)
authoring_reason = require_nonempty(spec["authoring_reason"], "authoring_reason")

base_ref = spec["base_request"]
require_keys(base_ref, %w[path sha256], "base_request")
allow_keys(base_ref, %w[path sha256], "base_request")
base_request_path, base_request_sha = require_repo_file(
  base_ref["path"],
  expected_sha: require_sha(base_ref["sha256"], "base_request.sha256"),
  label: "base image-generation request",
  within_root: run
)
base_request = load_mapping(base_request_path, "base image-generation request")
base_request_version = base_request["schema_version"].to_s
unless %w[idol_image_generation_request.v11 idol_image_generation_request.v12].include?(base_request_version)
  abort "base request must be active v12 or strict legacy v11"
end
base_request_schema = base_request_version == "idol_image_generation_request.v12" ? BASE_REQUEST_SCHEMA : LEGACY_BASE_REQUEST_SCHEMA
validate_schema!(base_request_schema, base_request_path, "base image-generation request")
abort "base request content_id does not match the run" unless base_request["content_id"].to_s == content_id
abort "base request run does not match the run" unless base_request["run"].to_s == run_rel
abort "base request packet_id does not match the correction spec" unless base_request["packet_id"].to_s == packet_id
abort "render correction currently requires an official_branch request" unless base_request["mode"].to_s == "official_branch"
core_cut_id = require_nonempty(base_request.dig("cut_pointer", "parent_core_cut_id"), "base request parent Core Cut id")
branch_cut_id = require_nonempty(base_request.dig("cut_pointer", "cut_id"), "base request Branch Cut id")
abort "base request must already be ready" unless READY_BASE_STATUSES.include?(base_request["status"].to_s)
adapter = base_request.dig("execution", "execution_adapter_id").to_s
abort "base request adapter is unsupported" unless ADAPTERS.include?(adapter)

execution_context = spec["execution_context"]
require_keys(execution_context, %w[context_pack planning_source], "execution_context")
allow_keys(execution_context, %w[context_pack planning_source], "execution_context")
context_ref = execution_context["context_pack"]
planning_ref = execution_context["planning_source"]
require_keys(context_ref, %w[path sha256 schema_version], "base context pack")
require_keys(planning_ref, %w[path sha256 schema_version], "base planning source")
context_path, = require_repo_file(context_ref["path"], expected_sha: require_sha(context_ref["sha256"], "base context pack.sha256"), label: "base context pack", within_root: run)
planning_path, = require_repo_file(planning_ref["path"], expected_sha: require_sha(planning_ref["sha256"], "base planning source.sha256"), label: "base planning source", within_root: run)
validate_schema!(CONTEXT_SCHEMA, context_path, "base context pack")
validate_schema!(FRONT_PLANNING_SCHEMA, planning_path, "base planning source")
context_document = load_mapping(context_path, "base context pack")
planning_document = load_mapping(planning_path, "base planning source")
abort "base context pack must be active v7" unless context_ref["schema_version"] == "idol-harness-context-pack.v7" && context_document["schema_version"] == "idol-harness-context-pack.v7"
abort "base planning source must be active FP v17" unless planning_ref["schema_version"] == "front-planning-readiness.v17" && planning_document["schema_version"] == "front-planning-readiness.v17"
source_snapshots = Array(context_document["source_snapshot"])
planning_snapshot = source_snapshots.find { |row| row["role"] == "front_planning" }
source_02a_ref = source_snapshots.find { |row| row["role"] == "storyboard_02a" }
abort "context pack lacks exact FP and 02A source snapshots" unless planning_snapshot && source_02a_ref
abort "context FP16 source differs from correction planning source" unless planning_snapshot.slice("path", "sha256", "schema_version") == planning_ref.slice("path", "sha256", "schema_version")
abort "base request Cut source differs from context 02A source" unless base_request.dig("cut_pointer", "source_path").to_s == source_02a_ref["path"].to_s
source_02a_path, = require_repo_file(source_02a_ref["path"], expected_sha: require_sha(source_02a_ref["sha256"], "base source 02A.sha256"), label: "base source 02A", within_root: run)
source_02b_ref = base_request["source_prompt_packet"]
require_keys(source_02b_ref, %w[path sha256 schema_version json_pointer value_sha256], "base source 02B")
source_02b_path, = require_repo_file(source_02b_ref["path"], expected_sha: require_sha(source_02b_ref["sha256"], "base source 02B.sha256"), label: "base source 02B", within_root: run)

base_prompt = base_request["prompt"]
prompt_fields = %w[
  identity_reference_rule
  scene_intent
  visible_details
  action_cue
  avoid
  full_prompt_text
  full_prompt_sha256
  label_order
]
require_keys(base_prompt, prompt_fields, "base request prompt")
base_prompt_text = require_nonempty(base_prompt["full_prompt_text"], "base request prompt.full_prompt_text")
base_prompt_sha = Digest::SHA256.hexdigest(base_prompt_text)
abort "base request prompt hash is stale" unless base_prompt["full_prompt_sha256"].to_s == base_prompt_sha
base_sections = five_prompt_sections(base_prompt_text)
%w[identity_reference_rule scene_intent visible_details action_cue avoid].each do |field|
  abort "base request prompt field #{field} does not match full_prompt_text" unless base_prompt[field].to_s == base_sections[field]
end
expected_label_order = ["Identity reference rule", "Scene intent", "Visible details", "Action cue", "Avoid"]
abort "base request prompt label order is stale" unless Array(base_prompt["label_order"]) == expected_label_order

attachment_order = Array(base_request["attachments"])
member_visual_inputs = attachment_order.select { |input| input["role"] == "current_title_member_visual" }
scene_reference_inputs = attachment_order.reject { |input| input["role"] == "current_title_member_visual" }
abort "base request attachment order digest is stale" unless value_sha256(attachment_order) == base_request["attachment_order_sha256"].to_s

member_visual_inputs.each_with_index do |input, index|
  require_keys(input, %w[actual_path sha256], "member_visual_inputs[#{index}]")
  require_repo_file(input["actual_path"], expected_sha: input["sha256"], label: "member visual input #{index}")
end
scene_reference_inputs.each_with_index do |input, index|
  require_keys(input, %w[actual_path sha256], "scene_reference_inputs[#{index}]")
  require_repo_file(input["actual_path"], expected_sha: input["sha256"], label: "scene reference input #{index}")
end
attachment_order.each_with_index do |input, index|
  require_keys(input, %w[order role binding_id asset_id actual_path sha256], "attachment_order[#{index}]")
  require_repo_file(input["actual_path"], expected_sha: input["sha256"], label: "combined attachment #{index}")
end
abort "base request combined attachment order is stale" unless attachment_order.each_with_index.all? { |attachment, index| attachment["order"] == index + 1 }

base_approval_path = base_request.dig("approval", "approval_source", "path")
base_approval_sha = base_request.dig("approval", "approval_source", "sha256")
require_repo_file(base_approval_path, expected_sha: base_approval_sha, label: "base request approval", within_root: run)

source_02b = load_mapping(source_02b_path, "source 02B")
prompt_pointer = source_02b_ref["json_pointer"].to_s
packet = json_pointer_get(source_02b, prompt_pointer)
abort "base source Prompt Packet value hash is stale" unless value_sha256(packet) == source_02b_ref["value_sha256"].to_s
abort "source 02B does not contain the base request packet" unless packet["packet_id"].to_s == packet_id
packet_index = prompt_pointer.split("/").last.to_i
abort "base request prompt no longer matches source 02B" unless packet.dig("rendered_five_lines", "full_prompt_text").to_s == base_prompt_text
if base_request_version == "idol_image_generation_request.v12"
  abort "base request reference_role_plan differs from source 02B" unless base_request["reference_role_plan"] == packet["reference_role_plan"]
  if base_request["section_cohort_id"].to_s != packet["section_cohort_id"].to_s
    abort "base request section cohort differs from source 02B"
  end
end

source_image_ref = spec["source_generated_image"]
require_keys(source_image_ref, %w[path sha256], "source_generated_image")
allow_keys(source_image_ref, %w[path sha256], "source_generated_image")
source_image_path, source_image_sha = require_repo_file(
  source_image_ref["path"],
  expected_sha: require_sha(source_image_ref["sha256"], "source_generated_image.sha256"),
  label: "source generated image",
  within_root: run
)

prior_review_ref = spec["prior_review"]
require_keys(prior_review_ref, %w[path sha256 record_pointer record_value_sha256], "prior_review")
allow_keys(prior_review_ref, %w[path sha256 record_pointer record_value_sha256], "prior_review")
prior_review_path, prior_review_sha = require_repo_file(
  prior_review_ref["path"],
  expected_sha: require_sha(prior_review_ref["sha256"], "prior_review.sha256"),
  label: "prior generated-image review",
  within_root: run
)
prior_review = load_mapping(prior_review_path, "prior generated-image review")
review_pointer = prior_review_ref["record_pointer"].to_s
abort "prior review record_pointer must select one Branch-Cut review" unless review_pointer.match?(%r{\A/branch_cut_reviews/[0-9]+\z})
review_record = json_pointer_get(prior_review, review_pointer)
abort "prior review record must be a mapping" unless review_record.is_a?(Hash)
abort "prior review record hash is stale" unless value_sha256(review_record) == require_sha(prior_review_ref["record_value_sha256"], "prior_review.record_value_sha256")
abort "prior review packet_id does not match" unless review_record["packet_id"].to_s == packet_id
abort "prior review Core Cut does not match" unless review_record["core_cut_id"].to_s == core_cut_id
abort "prior review Branch Cut does not match" unless review_record["branch_cut_id"].to_s == branch_cut_id
review_status = review_record["decision"].to_s
abort "prior review must be hold or reject before correction" unless %w[hold reject].include?(review_status)
review_image_path = repo_path(review_record["image_path"])
abort "prior review image does not match source_generated_image" unless same_path?(review_image_path, source_image_path)

defect = spec["defect"]
require_keys(defect, %w[defect_id categories observed_problem expected_correction changed_prompt_sections base_lock_refs], "defect")
allow_keys(defect, %w[defect_id categories observed_problem expected_correction changed_prompt_sections base_lock_refs], "defect")
defect_id = require_nonempty(defect["defect_id"], "defect.defect_id")
abort "defect_id is invalid" unless defect_id.match?(/\ADEF_[A-Z0-9_]{2,80}\z/)
require_nonempty(defect["observed_problem"], "defect.observed_problem")
require_nonempty(defect["expected_correction"], "defect.expected_correction")
categories = Array(defect["categories"]).map(&:to_s)
abort "defect.categories must contain one or more unique categories" unless categories.any? && categories.uniq == categories
unknown_categories = categories - CORRECTION_CATEGORIES
abort "unsupported correction categories: #{unknown_categories.join(', ')}" unless unknown_categories.empty?
declared_changed_sections = Array(defect["changed_prompt_sections"]).map(&:to_s)
abort "changed_prompt_sections must contain only visible_details and avoid" unless declared_changed_sections.any? && (declared_changed_sections - %w[visible_details avoid]).empty? && declared_changed_sections.uniq == declared_changed_sections

lock_refs = Array(defect["base_lock_refs"])
abort "defect.base_lock_refs must contain at least one source 02B lock" if lock_refs.empty?
lock_refs.each_with_index do |lock_ref, index|
  require_keys(lock_ref, %w[json_pointer value_sha256 repair_relation], "defect.base_lock_refs[#{index}]")
  allow_keys(lock_ref, %w[json_pointer value_sha256 repair_relation], "defect.base_lock_refs[#{index}]")
  pointer = lock_ref["json_pointer"].to_s
  abort "base lock must stay inside the exact source 02B packet" unless pointer.start_with?("/prompt_packets/#{packet_index}/")
  abort "base lock repair_relation must restore an existing lock" unless lock_ref["repair_relation"] == "restore_existing_lock_not_new_direction"
  value = json_pointer_get(source_02b, pointer)
  abort "base lock value hash is stale: #{pointer}" unless value_sha256(value) == require_sha(lock_ref["value_sha256"], "base_lock_refs[#{index}].value_sha256")
end

corrected = spec["corrected_prompt"]
prompt_fields = %w[identity_reference_rule scene_intent visible_details action_cue avoid text_sha256]
require_keys(corrected, prompt_fields, "corrected_prompt")
allow_keys(corrected, prompt_fields, "corrected_prompt")
prompt_sections = prompt_fields.first(5).to_h { |field| [field, require_nonempty(corrected[field], "corrected_prompt.#{field}")] }
corrected_prompt_text = [
  "Identity reference rule: #{prompt_sections['identity_reference_rule']}",
  "Scene intent: #{prompt_sections['scene_intent']}",
  "Visible details: #{prompt_sections['visible_details']}",
  "Action cue: #{prompt_sections['action_cue']}",
  "Avoid: #{prompt_sections['avoid']}"
].join("\n")
corrected_prompt_sha = Digest::SHA256.hexdigest(corrected_prompt_text)
abort "corrected_prompt.text_sha256 does not match the exact five-section prompt" unless corrected["text_sha256"].to_s == corrected_prompt_sha

%w[identity_reference_rule scene_intent action_cue].each do |field|
  abort "render-local correction may not change #{field}" unless prompt_sections[field] == base_sections[field]
end
actual_changed_sections = %w[visible_details avoid].select { |field| prompt_sections[field] != base_sections[field] }
abort "corrected prompt must change visible_details and/or avoid" if actual_changed_sections.empty?
abort "changed_prompt_sections must exactly match the changed five-section fields" unless declared_changed_sections.sort == actual_changed_sections.sort
required_quality_terms = ["4K", "high quality", "high detail"]
prompt_downcase = corrected_prompt_text.downcase
abort "corrected prompt must retain 4K, high quality, and high detail" unless required_quality_terms.all? { |term| prompt_downcase.include?(term.downcase) }

preservation = spec["preservation_assertions"]
require_keys(preservation, PRESERVATION_FIELDS, "preservation_assertions")
allow_keys(preservation, PRESERVATION_FIELDS, "preservation_assertions")
abort "every preservation assertion must be true" unless PRESERVATION_FIELDS.all? { |field| preservation[field] == true }

attempt = spec["attempt"]
require_keys(attempt, %w[index candidate_output_path expected_review_receipt_path], "attempt")
allow_keys(attempt, %w[index candidate_output_path expected_review_receipt_path], "attempt")
attempt_index = attempt["index"]
abort "attempt.index must be an integer from 1 through 5" unless attempt_index.is_a?(Integer) && attempt_index.between?(1, 5)
base_output_path = repo_path(base_request.dig("expected_output", "path"))
abort "base expected output must stay inside the owning run" unless within?(base_output_path, run)
candidate_output = repo_path(attempt["candidate_output_path"])
abort "candidate output must stay inside the owning run" unless within?(candidate_output, run)
abort "candidate output must stay in the base packet output family" unless within?(candidate_output, base_output_path.dirname)
abort "candidate output basename must retain packet_id" unless candidate_output.basename.to_s.include?(packet_id)
abort "candidate output must preserve the base image extension" unless candidate_output.extname.downcase == base_output_path.extname.downcase
abort "candidate output may not overwrite the base expected output" if same_path?(candidate_output, base_output_path)
abort "candidate output may not overwrite the correction source image" if same_path?(candidate_output, source_image_path)

source_family_ok = within?(source_image_path, base_output_path.dirname) && source_image_path.basename.to_s.include?(packet_id)
abort "source generated image must belong to the same packet output family" unless source_family_ok

expected_review_receipt = repo_path(attempt["expected_review_receipt_path"])
abort "expected review receipt must stay inside the owning run" unless within?(expected_review_receipt, run)

authorization_ref = spec["authorization_source"]
require_keys(authorization_ref, %w[path sha256], "authorization_source")
allow_keys(authorization_ref, %w[path sha256], "authorization_source")
authorization_path, authorization_sha = require_repo_file(
  authorization_ref["path"],
  expected_sha: require_sha(authorization_ref["sha256"], "authorization_source.sha256"),
  label: "Founder render-correction authorization",
  within_root: run
)
authorization = load_mapping(authorization_path, "Founder render-correction authorization")
authorization_keys = %w[
  schema_version authorization_id authorized_by content_id correction_id packet_id
  base_request_sha256 source_generated_image_sha256 prior_review_sha256 execution_adapter_id
  allowed_categories max_attempts authorized_attempt_indexes
  external_execution_approved paid_generation_approved
]
require_keys(authorization, authorization_keys, "Founder render-correction authorization")
allow_keys(authorization, authorization_keys, "Founder render-correction authorization")
abort "authorization schema_version is invalid" unless authorization["schema_version"] == "idol_image_render_correction_authorization.v1"
authorization_id = require_nonempty(authorization["authorization_id"], "authorization.authorization_id")
abort "authorization_id is invalid" unless authorization_id.match?(/\AIRCA_[A-Z0-9_]{2,80}\z/)

hold_reasons = []
hold_reasons << "authorization owner must be founder" unless authorization["authorized_by"] == "founder"
hold_reasons << "authorization content_id does not match" unless authorization["content_id"].to_s == content_id
hold_reasons << "authorization correction_id does not match" unless authorization["correction_id"].to_s == correction_id
hold_reasons << "authorization packet_id does not match" unless authorization["packet_id"].to_s == packet_id
hold_reasons << "authorization base request hash does not match" unless authorization["base_request_sha256"].to_s == base_request_sha
hold_reasons << "authorization source image hash does not match" unless authorization["source_generated_image_sha256"].to_s == source_image_sha
hold_reasons << "authorization prior review hash does not match" unless authorization["prior_review_sha256"].to_s == prior_review_sha
hold_reasons << "authorization execution adapter does not match" unless authorization["execution_adapter_id"].to_s == adapter

allowed_categories = Array(authorization["allowed_categories"]).map(&:to_s)
hold_reasons << "authorization allowed_categories are invalid" unless allowed_categories.any? && allowed_categories.uniq == allowed_categories && (allowed_categories - CORRECTION_CATEGORIES).empty?
hold_reasons << "one or more defect categories are outside Founder authorization" unless (categories - allowed_categories).empty?
max_attempts = authorization["max_attempts"]
hold_reasons << "authorization max_attempts must be an integer from 1 through 5" unless max_attempts.is_a?(Integer) && max_attempts.between?(1, 5)
authorized_attempt_indexes = Array(authorization["authorized_attempt_indexes"])
valid_attempt_indexes = authorized_attempt_indexes.all? { |value| value.is_a?(Integer) && value.between?(1, 5) } && authorized_attempt_indexes.uniq == authorized_attempt_indexes
hold_reasons << "authorization attempt indexes are invalid" unless authorized_attempt_indexes.any? && valid_attempt_indexes
if max_attempts.is_a?(Integer)
  hold_reasons << "authorization attempt indexes exceed max_attempts" if authorized_attempt_indexes.any? { |value| value.is_a?(Integer) && value > max_attempts }
  hold_reasons << "attempt index exceeds max_attempts" if attempt_index > max_attempts
end
hold_reasons << "exact attempt index is not Founder-authorized" unless authorized_attempt_indexes.include?(attempt_index)
hold_reasons << "external execution is not Founder-approved" unless authorization["external_execution_approved"] == true
hold_reasons << "paid generation is not Founder-approved" unless authorization["paid_generation_approved"] == true
hold_reasons << "candidate output already exists; choose a new non-overwriting attempt path" if candidate_output.exist?

if adapter == "openai_api_gpt_image_2"
  hold_reasons << "OpenAI #{base_request_version.split('.').last} base execution is registered, but this correction artifact has no separate Founder-gated correction executor; gpt-image-2 and exact edit-source order remain locked"
elsif adapter == "xai_api_media"
  hold_reasons << "xAI API media correction activation requires both an exact registered image-edit profile and a separate Founder-gated correction executor that binds this v7 artifact; no fallback is allowed"
end

status = if hold_reasons.any?
           "hold"
         elsif adapter == "codex_imagegen"
           "ready_for_codex_builtin_imagegen"
         elsif adapter == "grok_image"
           "ready_for_manual_execution"
         else
           "ready_for_section_llm_execution"
         end

correction_version = base_request_version == "idol_image_generation_request.v12" ? "idol_image_render_correction.v8" : "idol_image_render_correction.v7"
reference_role_plan_sha = base_request_version == "idol_image_generation_request.v12" ? value_sha256(base_request.fetch("reference_role_plan")) : nil
request = {
  "schema_version" => correction_version,
  "artifact_type" => "image_render_correction_request",
  "content_id" => content_id,
  "run" => run_rel,
  "correction_id" => correction_id,
  "packet_id" => packet_id,
  "core_cut_id" => core_cut_id,
  "branch_cut_id" => branch_cut_id,
  "authoring" => {
    "owner" => authoring_owner,
    "reason" => authoring_reason,
    "creative_scope" => "render_local_repair_only_no_canonical_02b_rewrite"
  },
  "base_request" => {
    "path" => repo_relative(base_request_path),
    "sha256" => base_request_sha,
    "schema_version" => base_request["schema_version"],
    "execution_adapter_id" => adapter,
    "status" => base_request["status"],
    "prompt_sha256" => base_prompt_sha
  },
  "source_02a" => {
    "path" => source_02a_ref["path"],
    "sha256" => source_02a_ref["sha256"]
  },
  "source_02b" => {
    "path" => source_02b_ref["path"],
    "sha256" => source_02b_ref["sha256"]
  },
  "source_generated_image" => {
    "path" => repo_relative(source_image_path),
    "sha256" => source_image_sha,
    "role" => "edit_source_generated_image"
  },
  "prior_review" => {
    "path" => repo_relative(prior_review_path),
    "sha256" => prior_review_sha,
    "record_pointer" => review_pointer,
    "record_value_sha256" => value_sha256(review_record),
    "record_status" => review_status
  },
  "defect" => {
    "defect_id" => defect_id,
    "categories" => categories,
    "observed_problem" => defect["observed_problem"],
    "expected_correction" => defect["expected_correction"],
    "changed_prompt_sections" => declared_changed_sections,
    "base_lock_refs" => lock_refs
  },
  "corrected_prompt" => prompt_sections.merge(
    "text" => corrected_prompt_text,
    "text_sha256" => corrected_prompt_sha,
    "copy_policy" => "human_or_model_authored_exact_five_section_prompt_no_adapter_rewrite"
  ),
  "preservation_assertions" => preservation,
  "immutable_inputs" => {
    "member_visual_inputs_sha256" => value_sha256(member_visual_inputs),
    "scene_reference_inputs_sha256" => value_sha256(scene_reference_inputs),
    "attachment_order_sha256" => base_request["attachment_order_sha256"],
    "reference_role_plan_sha256" => reference_role_plan_sha,
    "section_cohort_id" => base_request["section_cohort_id"],
    "context_pack" => {
      "path" => context_ref["path"],
      "sha256" => context_ref["sha256"],
      "schema_version" => context_ref["schema_version"]
    },
    "planning_source" => {
      "path" => planning_ref["path"],
      "sha256" => planning_ref["sha256"],
      "schema_version" => planning_ref["schema_version"]
    },
    "attachment_order" => "edit_source_then_existing_combined_attachment_order",
    "visual_reference_attachment_policy" => base_request_version == "idol_image_generation_request.v12" ?
      "active_v12_logical_role_plan_and_combined_attachment_order_unchanged" :
      "active_v11_combined_attachment_order_unchanged"
  }.reject { |_key, value| value.nil? },
  "authorization" => {
    "path" => repo_relative(authorization_path),
    "sha256" => authorization_sha,
    "authorization_id" => authorization_id,
    "authorized_by" => authorization["authorized_by"],
    "base_request_sha256" => authorization["base_request_sha256"],
    "execution_adapter_id" => authorization["execution_adapter_id"],
    "allowed_categories" => allowed_categories,
    "max_attempts" => max_attempts,
    "authorized_attempt_indexes" => authorized_attempt_indexes,
    "external_execution_approved" => authorization["external_execution_approved"],
    "paid_generation_approved" => authorization["paid_generation_approved"]
  },
  "attempt" => {
    "index" => attempt_index,
    "candidate_output_path" => repo_relative(candidate_output),
    "expected_review_receipt_path" => repo_relative(expected_review_receipt),
    "original_output_preserved" => true
  },
  "execution_contract" => {
    "execution_adapter_id" => adapter,
    "execution_mode" => "image_edit_from_existing_generated_candidate",
    "one_request_per_attempt" => true,
    "canonical_02b_recompile_forbidden" => true,
    "prompt_adapter_rewrite_forbidden" => true,
    "source_image_overwrite_forbidden" => true,
    "verify_live_hashes_before_dispatch" => true,
    "openai_model" => "gpt-image-2",
    "openai_edit_source_preflight_status" => adapter == "openai_api_gpt_image_2" ? "hold_no_registered_correction_executor" : "not_openai_adapter"
  },
  "review_contract" => {
    "status" => "pending_pixel_inspection_cdd_review_and_founder_selection",
    "inspection_scope" => "named_defect_delta_plus_identity_continuity_anatomy_regression_guard",
    "named_defect_id" => defect_id,
    "required_checks" => [
      "named_defect_resolved",
      "identity_regression_absent",
      "continuity_regression_absent",
      "anatomy_regression_absent"
    ],
    "allowed_technical_dispositions" => ["technical_pass", "technical_hold", "locked_rubric_rerun"],
    "pixel_inspection_required" => true,
    "auto_pass_forbidden" => true,
    "cdd_review_required" => true,
    "founder_final_selection_required" => true,
    "overall_promotion_required" => true
  },
  "status" => status,
  "hold_reasons" => hold_reasons.uniq
}

yaml = YAML.dump(request)
temp = Tempfile.new(["idol-image-render-correction", ".yaml"])
temp.write(yaml)
temp.flush
output_schema = correction_version == "idol_image_render_correction.v8" ? OUTPUT_SCHEMA : LEGACY_OUTPUT_SCHEMA
validate_schema!(output_schema, Pathname.new(temp.path), "derived image render correction")
temp.close!

default_output = run.join("work/image_render_corrections/#{packet_id}/#{correction_id}-attempt-#{format('%02d', attempt_index)}.yaml")
output = options[:output] ? repo_path(options[:output]) : default_output
abort "derived correction request must stay inside the owning run" unless within?(output, run)
abort "derived correction request may not overwrite the correction spec" if same_path?(output, spec_path)
abort "derived correction request already exists; use a new attempt or output path" if options[:write] && output.exist?

if options[:write]
  output.dirname.mkpath
  output.write(yaml)
end

puts JSON.pretty_generate(
  "write" => options[:write],
  "output" => repo_relative(output),
  "status" => status,
  "correction_id" => correction_id,
  "packet_id" => packet_id,
  "execution_adapter_id" => adapter,
  "attempt_index" => attempt_index,
  "base_request_sha256" => base_request_sha,
  "source_generated_image_sha256" => source_image_sha,
  "corrected_prompt_sha256" => corrected_prompt_sha,
  "candidate_output_path" => repo_relative(candidate_output),
  "hold_reasons" => hold_reasons.uniq
)
