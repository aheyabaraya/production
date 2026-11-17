#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "time"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
CANVAS_SCHEMA = ROOT.join("development", "front-planning-workbench", "contracts", "canvas-state.schema.json")
RECEIPT_SCHEMA = ROOT.join("schemas", "founder-intervention-receipt.schema.json")
RECEIPT_VALIDATOR = ROOT.join("scripts", "validate_founder_intervention_receipt.rb")
PROJECTION_ASSEMBLER = ROOT.join("scripts", "idol_review_projection_assembler.rb")

class FounderDirectUpdateError < StandardError; end

REQUIRED_CHECKS = %w[
  schema_and_hash_integrity
  reference_and_identity_integrity
  safety_and_feasibility
  pixel_or_playback_qa_when_output_exists
  external_and_paid_approval_when_applicable
].freeze

STAGE_IDS = {
  "01" => "mv_performance_direction",
  "02A" => "mv_storyboard_direction",
  "02B" => "image_prompt_compilation",
  "generated_branch_review" => "generated_branch_cut_review",
  "03V" => "video_motion_direction",
  "04" => "edit_assembly_playback_qc"
}.freeze

def fail_update(message)
  raise FounderDirectUpdateError, message
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, output|
      output[key] = canonical_value(value.fetch(key))
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

def repository_path(raw, label, must_exist: true)
  path = Pathname.new(raw.to_s)
  fail_update("#{label} must be repository-relative") if path.absolute? || raw.to_s.empty?
  path = ROOT.join(path).cleanpath
  relative = path.relative_path_from(ROOT).to_s
  fail_update("#{label} escapes the repository") if relative == ".." || relative.start_with?("../")
  fail_update("#{label} is missing: #{relative}") if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  fail_update("#{label} escapes the repository")
end

def load_yaml(path, label)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: true)
  fail_update("#{label} must be a mapping") unless value.is_a?(Hash)
  value
rescue Psych::Exception => e
  fail_update("#{label} cannot be parsed: #{e.message}")
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  fail_update("#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}") unless status.success?
end

def validate_document(schema, bytes, suffix, label)
  Tempfile.create(["founder-direct-update", suffix], "/private/tmp") do |candidate|
    candidate.binmode
    candidate.write(bytes)
    candidate.flush
    validate_schema(schema, Pathname.new(candidate.path), label)
  end
end

def atomic_write(path, bytes)
  path.dirname.mkpath
  Tempfile.create([".founder-direct-update", path.extname], path.dirname.to_s) do |candidate|
    candidate.binmode
    candidate.write(bytes)
    candidate.flush
    candidate.fsync
    File.rename(candidate.path, path.to_s)
  end
end

def restore(path, bytes)
  if bytes.nil?
    path.delete if path.exist?
  else
    atomic_write(path, bytes)
  end
end

def artifact(path, role)
  {
    "path" => path.relative_path_from(ROOT).to_s,
    "sha256" => Digest::SHA256.file(path).hexdigest,
    "role" => role
  }
end

def verify_artifact(binding, label)
  fail_update("#{label} must be a path/SHA binding") unless binding.is_a?(Hash)
  path, relative = repository_path(binding["path"], "#{label}.path")
  expected = binding["sha256"].to_s
  fail_update("#{label}.sha256 is invalid") unless expected.match?(/\A[a-f0-9]{64}\z/)
  actual = Digest::SHA256.file(path).hexdigest
  fail_update("#{label} is stale: #{relative}") unless actual == expected
  path
end

def exact_keys(value, keys, label)
  fail_update("#{label} must be an object") unless value.is_a?(Hash)
  unknown = value.keys.map(&:to_s) - keys
  fail_update("#{label} contains unsupported keys: #{unknown.join(', ')}") unless unknown.empty?
end

def normalize_instruction(value)
  value.to_s.gsub(/\s+/, " ").strip
end

def validate_checks(raw)
  fail_update("checks must be an array") unless raw.is_a?(Array)
  checks = raw.map.with_index do |check, index|
    exact_keys(check, %w[checkId status evidence], "checks[#{index}]")
    check_id = check["checkId"].to_s
    status = check["status"].to_s
    evidence = check["evidence"].to_s.strip
    fail_update("checks[#{index}] has an unknown checkId") unless REQUIRED_CHECKS.include?(check_id)
    fail_update("checks[#{index}] must pass before commit") unless status == "pass"
    fail_update("checks[#{index}] evidence is required") if evidence.empty?
    {"check_id" => check_id, "status" => "pass", "evidence" => evidence}
  end
  fail_update("checks must cover each mandatory check exactly once") unless checks.map { |row| row["check_id"] }.sort == REQUIRED_CHECKS.sort
  checks
end

def collect_invalidations(manifest, affected_sections)
  seen = {}
  Array(manifest["review_assets"]).each do |asset|
    Array(asset["bindings"]).each do |binding|
      next unless affected_sections.include?(binding["section_id"].to_s)
      stage_id = STAGE_IDS[binding["source_stage"].to_s]
      receipt = binding["state_receipt"]
      next unless stage_id && receipt.is_a?(Hash)
      path = verify_artifact(receipt, "downstream state receipt")
      key = [stage_id, receipt["path"].to_s, receipt["sha256"].to_s]
      seen[key] ||= {
        "stage_id" => stage_id,
        "path" => path.relative_path_from(ROOT).to_s,
        "sha256" => receipt["sha256"].to_s,
        "reason" => "Founder direct sequence update affects #{affected_sections.join(', ')}; reproject this exact dependent before reuse."
      }
    end
  end
  seen.values
end

begin
  payload = JSON.parse($stdin.read)
  exact_keys(
    payload,
    %w[version runRoot planText canvasValue basePlanSha256 baseCanvasSha256 request checks currentNext],
    "commit payload"
  )
  fail_update("commit payload version must be 1") unless payload["version"] == 1
  run = payload["runRoot"].to_s
  unless run.match?(%r{\Aruns/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9가-힣][a-z0-9가-힣-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}\z})
    fail_update("runRoot is not a canonical IDOL run")
  end
  request = payload["request"]
  exact_keys(
    request,
    %w[version runRoot correctionKind owningTruthSurface founderInstructionVerbatim orderedSequence affectedSectionIds baseline requiredRoute forbidden],
    "direct-update request"
  )
  fail_update("request does not match the commit run") unless request["runRoot"] == run
  fail_update("unsupported direct-update correction kind") unless request["correctionKind"] == "sequence_reorder_and_instruction"
  fail_update("unsupported direct-update owner") unless request["owningTruthSurface"] == "front_planning_sequence"
  instruction = request["founderInstructionVerbatim"].to_s.strip
  fail_update("Founder instruction is required") if instruction.empty?
  checks = validate_checks(payload["checks"])

  plan_path, plan_relative = repository_path("#{run}/research/front-planning-v1.md", "canonical plan")
  canvas_path, canvas_relative = repository_path("#{run}/work/front_planning_integration/canvas-state.json", "canonical canvas")
  manifest_path, manifest_relative = repository_path("#{run}/review/manifests/founder-workbench.yaml", "stable board manifest")
  html_path, html_relative = repository_path("#{run}/review/founder-workbench.html", "stable board HTML")
  source_set_path, source_set_relative = repository_path("#{run}/work/review-projection-source-set.yaml", "review projection source set")
  owner_index_path, owner_index_relative = repository_path("#{run}/work/review-projection-owner-index.yaml", "review projection owner index")
  pending_path, = repository_path("#{run}/work/review-projection-pending.yaml", "review projection pending", must_exist: false)

  current_next = payload["currentNext"].is_a?(Hash) ? payload["currentNext"] : {}
  current_next_yaml, current_next_yaml_relative = repository_path(
    current_next.fetch("yaml", "automation/current-next.yaml"),
    "current-next YAML",
    must_exist: false
  )
  current_next_md, current_next_md_relative = repository_path(
    current_next.fetch("markdown", "automation/current-next.md"),
    "current-next Markdown",
    must_exist: false
  )

  plan_before = plan_path.binread
  canvas_before = canvas_path.binread
  fail_update("canonical plan changed after direct-update authorization") unless Digest::SHA256.hexdigest(plan_before) == payload["basePlanSha256"]
  fail_update("canonical canvas changed after direct-update authorization") unless Digest::SHA256.hexdigest(canvas_before) == payload["baseCanvasSha256"]

  baseline = request["baseline"]
  exact_keys(baseline, %w[plan canvas board founderEpoch], "request baseline")
  fail_update("baseline plan hash differs from commit CAS") unless baseline.dig("plan", "sha256") == payload["basePlanSha256"]
  fail_update("baseline canvas hash differs from commit CAS") unless baseline.dig("canvas", "sha256") == payload["baseCanvasSha256"]
  board_baseline = baseline["board"]
  exact_keys(board_baseline, %w[htmlPath htmlSha256 manifestPath manifestSha256 revision activeCycleId], "board baseline")
  fail_update("board baseline path differs from the stable HTML") unless board_baseline["htmlPath"] == html_relative
  fail_update("board manifest baseline path differs from the stable manifest") unless board_baseline["manifestPath"] == manifest_relative
  fail_update("stable board HTML changed after authorization") unless Digest::SHA256.file(html_path).hexdigest == board_baseline["htmlSha256"]
  fail_update("stable board manifest changed after authorization") unless Digest::SHA256.file(manifest_path).hexdigest == board_baseline["manifestSha256"]

  plan_text = payload["planText"].to_s
  fail_update("updated plan must preserve the exact Founder instruction") unless normalize_instruction(plan_text).include?(normalize_instruction(instruction))
  canvas = payload["canvasValue"]
  fail_update("canvasValue must be an object") unless canvas.is_a?(Hash)
  fail_update("updated canvas belongs to another run") unless canvas.dig("run", "run_root") == run
  fail_update("updated canvas is still pending reconciliation") unless canvas.dig("pending_reconciliation", "dirty") == false
  fail_update("updated Founder epoch must advance exactly once") unless canvas["founder_epoch"] == Integer(baseline["founderEpoch"]) + 1

  ordered = Array(request["orderedSequence"])
  fail_update("orderedSequence cannot be empty") if ordered.empty?
  expected_sequence = ordered.map { |row| [row["assetId"].to_s, row["sectionId"].to_s] }
  actual_sequence = Array(canvas["sequence"]).map { |row| [row["asset_id"].to_s, row["section_id"].to_s] }
  fail_update("updated canvas sequence differs from the exact visible Founder order") unless actual_sequence == expected_sequence
  assets = Array(canvas["assets"]).each_with_object({}) { |asset, index| index[asset["id"].to_s] = asset }
  ordered.each_with_index do |row, index|
    asset = assets[row["assetId"].to_s]
    fail_update("orderedSequence[#{index}] asset is absent from the canvas") unless asset
    fail_update("orderedSequence[#{index}] path differs from the canvas asset") unless row["path"].to_s == asset["path"].to_s
    unless row["sha256"].to_s.empty? || row["sha256"].to_s == asset["sha256"].to_s
      fail_update("orderedSequence[#{index}] SHA-256 differs from the canvas asset")
    end
  end
  affected_sections = Array(request["affectedSectionIds"]).map(&:to_s).uniq
  fail_update("affectedSectionIds must exactly match the sequence sections") unless affected_sections.sort == expected_sequence.map(&:last).uniq.sort

  plan_bytes = plan_text.b
  canvas_bytes = JSON.pretty_generate(canvas, space: " ", object_nl: "\n", array_nl: "\n", indent: "  ") + "\n"
  validate_document(CANVAS_SCHEMA, canvas_bytes, ".json", "reconciled canonical canvas")

  manifest = load_yaml(manifest_path, "stable board manifest")
  fail_update("stable board manifest belongs to another run") unless manifest.dig("run", "run_root") == run
  fail_update("stable board revision differs from the authorization") unless manifest.dig("board", "revision") == board_baseline["revision"]
  fail_update("stable board cycle differs from the authorization") unless manifest.dig("board", "active_cycle_id") == board_baseline["activeCycleId"]
  rollback_manifest = manifest.dig("board", "rollback_pair", "last_passed_manifest")
  verify_artifact(rollback_manifest, "last passed rollback manifest")
  verify_artifact(manifest.dig("board", "rollback_pair", "last_passed_html"), "last passed rollback HTML")
  invalidations = collect_invalidations(manifest, affected_sections)

  id_basis = [run, instruction, payload["baseCanvasSha256"], Time.now.utc.iso8601(6)].join("\n")
  intervention_id = "FI_FPW_#{Digest::SHA256.hexdigest(id_basis)[0, 16].upcase}"
  receipt_directory = ROOT.join(run, "review", "founder-interventions")
  baseline_directory = receipt_directory.join("baselines")
  receipt_path = receipt_directory.join("#{intervention_id}.yaml")
  baseline_canvas_path = baseline_directory.join("#{intervention_id}-canvas.json")
  fail_update("direct-update receipt collision") if receipt_path.exist? || baseline_canvas_path.exist?

  revised_plan = {"path" => plan_relative, "sha256" => Digest::SHA256.hexdigest(plan_bytes), "role" => "revised Front Planning plan"}
  revised_canvas = {"path" => canvas_relative, "sha256" => Digest::SHA256.hexdigest(canvas_bytes), "role" => "reconciled Founder sequence owner"}
  sequence_scope = ordered.map.with_index { |row, index| format("%02d:%s:%s", index + 1, row["sectionId"], row["assetId"]) }.join(" | ")
  recorded_at = Time.now.utc.iso8601
  receipt = {
    "schema_version" => "idol-founder-intervention-receipt.v2",
    "artifact_type" => "founder_intervention_receipt",
    "intervention_id" => intervention_id,
    "run" => run,
    "recorded_at" => recorded_at,
    "source" => {
      "surface" => "founder_review_artifact",
      "locator" => "Director Workbench Scene Build Rail · board r#{board_baseline['revision']} · #{board_baseline['activeCycleId']}",
      "founder_input_verbatim" => instruction
    },
    "authority" => {
      "classification" => "explicit_lock",
      "explicit_lock" => true,
      "scope_statement" => "Affected #{affected_sections.join(', ')}; exact Scene Build Rail order #{sequence_scope}"
    },
    "intervention_mode" => "founder_direct_update",
    "routing" => {
      "owning_stage_id" => "front_planning_integration",
      "required_owner_skill" => "idol-front-planning-director",
      "affected_section_ids" => affected_sections,
      "affected_artifacts" => [revised_plan, revised_canvas],
      "earliest_reauthor_stage_id" => "front_planning_integration",
      "downstream_invalidation_targets" => invalidations,
      "integration_order" => "revise_owning_upstream_section_then_reproject_and_revalidate_only_affected_downstream"
    },
    "change_contract" => {
      "preserve" => ["all unaffected sections, owner bytes, Founder locks, reference identity, and the last passed rollback pair"],
      "change" => ["the exact Scene Build Rail order and the verbatim Founder instruction recorded above"],
      "do_not_infer" => ["no adjacent field, downstream approval, paid generation, external execution, or unaffected-section change"]
    },
    "founder_direct_update" => {
      "correction_kind" => "sequence_reorder_and_instruction",
      "owning_truth_surface" => "front_planning_sequence",
      "decision" => "pass",
      "decision_note" => "Founder directly authored the replacement sequence and instruction; no second taste veto was applied.",
      "baseline_review" => deep_copy(rollback_manifest),
      "baseline_source" => {
        "path" => baseline_canvas_path.relative_path_from(ROOT).to_s,
        "sha256" => Digest::SHA256.hexdigest(canvas_before),
        "role" => "immutable pre-update canvas baseline"
      },
      "authoritative_field_bindings" => [{
        "path" => canvas_relative,
        "sha256" => revised_canvas["sha256"],
        "pointer" => "/sequence",
        "value_sha256" => value_sha256(canvas.fetch("sequence")),
        "role" => "Founder-authored Scene Build Rail order"
      }],
      "creative_review_policy" => "founder_decision_no_creative_advisory_rereview",
      "mandatory_check_ids" => REQUIRED_CHECKS,
      "downstream_policy" => "patch_smallest_owner_and_reproject_affected_dependents_only"
    },
    "status" => "integrated",
    "integration_receipt" => {
      "integrated_at" => recorded_at,
      "revised_artifacts" => [revised_plan, revised_canvas],
      "revalidation_results" => checks,
      "resumable_from_stage_id" => "front_planning_integration"
    }
  }
  receipt_bytes = YAML.dump(receipt)
  validate_document(RECEIPT_SCHEMA, receipt_bytes, ".yaml", "Founder direct-update receipt")

  receipt_source_id = "founder-direct-#{intervention_id.downcase.sub('fi_fpw_', '')}"
  manifest_sources = Array(manifest["sources"])
  manifest_sources.each do |source|
    source["sha256"] = revised_plan["sha256"] if source["path"] == plan_relative
    source["sha256"] = revised_canvas["sha256"] if source["path"] == canvas_relative
  end
  manifest_sources << {
    "source_id" => receipt_source_id,
    "path" => receipt_path.relative_path_from(ROOT).to_s,
    "sha256" => Digest::SHA256.hexdigest(receipt_bytes),
    "role" => "founder_direct_update_receipt"
  }
  manifest["sources"] = manifest_sources
  # The direct-update transaction changes the base projection bytes. Leave the
  # current revision as the CAS baseline and clear the prior query digest so the
  # owner-index assembler advances exactly one revision while rebuilding the
  # same stable board.
  manifest["board"].delete("source_set_digest")
  manifest["board"]["notices"] = Array(manifest.dig("board", "notices")) + [
    {"tone" => "pass", "text" => {"source_id" => receipt_source_id, "pointer" => "/source/founder_input_verbatim"}},
    {"tone" => "info", "text" => {"source_id" => receipt_source_id, "pointer" => "/authority/scope_statement"}}
  ]
  manifest_bytes = YAML.dump(manifest)

  tracked_paths = [
    plan_path, canvas_path, manifest_path, html_path, source_set_path, pending_path,
    current_next_yaml, current_next_md
  ]
  snapshots = tracked_paths.to_h { |path| [path, path.exist? ? path.binread : nil] }
  created_paths = [baseline_canvas_path, receipt_path]
  begin
    atomic_write(baseline_canvas_path, canvas_before)
    atomic_write(plan_path, plan_bytes)
    atomic_write(canvas_path, canvas_bytes)
    atomic_write(receipt_path, receipt_bytes)
    atomic_write(manifest_path, manifest_bytes)

    command = [RbConfig.ruby, PROJECTION_ASSEMBLER.to_s, source_set_relative]
    command.concat(["--prepare-from", owner_index_relative])
    command.concat([
      "--current-next-yaml", current_next_yaml_relative,
      "--current-next-md", current_next_md_relative,
      "--write",
      "--json"
    ])
    projection_stdout, projection_stderr, projection_status = Open3.capture3(*command, chdir: ROOT.to_s)
    unless projection_status.success?
      fail_update("stable board reprojection failed: #{[projection_stderr, projection_stdout].join(' ').strip}")
    end

    validator_stdout, validator_stderr, validator_status = Open3.capture3(
      RbConfig.ruby,
      RECEIPT_VALIDATOR.to_s,
      receipt_path.relative_path_from(ROOT).to_s,
      "--json",
      chdir: ROOT.to_s
    )
    unless validator_status.success?
      fail_update("integrated receipt validation failed: #{[validator_stderr, validator_stdout].join(' ').strip}")
    end
  rescue StandardError
    snapshots.each { |path, bytes| restore(path, bytes) }
    created_paths.each { |path| path.delete if path.exist? }
    raise
  end

  final_manifest = load_yaml(manifest_path, "reprojected stable board manifest")
  output = {
    "version" => 1,
    "status" => "integrated",
    "receipt" => artifact(receipt_path, "Founder direct-update receipt").slice("path", "sha256"),
    "revisedArtifacts" => [artifact(plan_path, "revised plan"), artifact(canvas_path, "reconciled canvas")].map { |row| row.slice("path", "sha256") },
    "invalidatedArtifacts" => invalidations.map { |row| row.slice("path", "sha256") },
    "board" => {
      "htmlPath" => html_relative,
      "htmlSha256" => Digest::SHA256.file(html_path).hexdigest,
      "manifestPath" => manifest_relative,
      "manifestSha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "revision" => final_manifest.dig("board", "revision"),
      "activeCycleId" => final_manifest.dig("board", "active_cycle_id")
    },
    "workbenchReloadRequired" => true
  }
  puts JSON.generate(output)
rescue FounderDirectUpdateError, JSON::ParserError, KeyError, TypeError, ArgumentError => e
  warn "Founder direct update: HOLD: #{e.message}"
  exit 1
end
