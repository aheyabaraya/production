
# Ruby 2.6 compatibility: Array#filter_map arrived in 2.7
class Array
  def filter_map
    each_with_object([]) do |item, out|
      value = yield item
      out << value unless value.nil?
    end
  end unless method_defined?(:filter_map)
end
#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"
require "digest"
require_relative "lib/idol_current_next_v2"
require_relative "lib/idol_run_layout"

ROOT = Pathname.new(Dir.pwd).cleanpath
STATUS_SEPARATOR = "[_\\s-]"
EDIT_REVIEW_STATUS_PATTERN = /(?:^|#{STATUS_SEPARATOR})(?:needs_founder|needs.*review|rendered_needs|calibration|timing_test|hold|blocked)(?:$|#{STATUS_SEPARATOR})/i
EDIT_REJECT_STATUS_PATTERN = /(?:^|#{STATUS_SEPARATOR})(?:rejected|failed|unrecoverable|mismatch)(?:$|#{STATUS_SEPARATOR})/i

Check = Struct.new(
  :id,
  :group,
  :label,
  :status,
  :blocking,
  :artifact,
  :command,
  :exit_status,
  :details,
  keyword_init: true
)

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_state_check.rb RUN_ROOT [--album-key KEY --title-key KEY] [--write-report|--report PATH] [--json]"
  exit 2
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def normalize_run_pointer(value)
  pointer = value.to_s.strip
  return nil if pointer.empty?

  empty_markers = %w[none null nil n/a not_selected no_active_unit no_active_run]
  empty_markers.include?(pointer.downcase) ? nil : pointer
end

def resolve_path(path)
  return nil if blank?(path)

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : (ROOT + raw).cleanpath
end

def rel_path(path)
  resolved = resolve_path(path)
  return "" unless resolved

  resolved.relative_path_from(ROOT).to_s
rescue ArgumentError
  resolved.to_s
end

def run_layout_repo_root(path)
  cursor = Pathname.new(path).expand_path
  until cursor.root?
    return cursor.parent if cursor.basename.to_s == "runs"

    cursor = cursor.parent
  end
  ROOT
end

def readable_file?(path)
  resolved = resolve_path(path)
  resolved && File.file?(resolved.to_s)
end

def readable_path?(path)
  resolved = resolve_path(path)
  resolved && File.exist?(resolved.to_s)
end

def load_yaml(path)
  resolved = resolve_path(path)
  return {} unless resolved && File.file?(resolved.to_s)

  doc = YAML.load_file(resolved.to_s)
  doc.is_a?(Hash) ? doc : {}
rescue Psych::SyntaxError
  {}
end

def current_context_for_run(run_path)
  current_next = load_yaml("automation/current-next.yaml")
  return nil unless normalize_run_pointer(current_next["run"]) == normalize_run_pointer(rel_path(run_path))

  @idol_current_next_v2_contexts ||= {}
  @idol_current_next_v2_contexts[rel_path(run_path)] ||= IdolCurrentNextV2.load_active(
    path: "automation/current-next.yaml",
    run: rel_path(run_path),
    root: ROOT,
    require_actionable: false
  )
rescue IdolCurrentNextV2::Error => error
  usage_error(error.message)
end

def current_pointer_for_run(run_path)
  context = current_context_for_run(run_path)
  context && context["document"]
end

def inferred_active_stage_id(run_path)
  context = current_context_for_run(run_path)
  selected_stage = context ? IdolCurrentNextV2.authority_scope(context)["stage_id"].to_s : ""
  return selected_stage unless selected_stage.empty?

  stage_sources = [
    ["master_package_release", "05-package.yaml"],
    ["edit_assembly_playback_qc", "04-edit-map.yaml"],
    ["image_prompt_compilation", "02B-prompt-packets.yaml"],
    ["mv_storyboard_direction", "02A-master-storyboard.yaml"],
    ["mv_performance_direction", "01-song-choreography-performance-mv-map.yaml"],
    ["song_production_lock", "00A-song-lock.yaml"]
  ]
  found = stage_sources.find { |_stage_id, relative| run_path.join(relative).file? }
  return found.first if found

  readiness = Dir.glob(run_path.join("research", "front-planning-readiness-v*.{yaml,yml,json}").to_s)
  readiness.empty? ? nil : "front_planning_integration"
end

def active_section_ids_for_run(run_path)
  context = current_context_for_run(run_path)
  return [] unless context

  values = Array(IdolCurrentNextV2.authority_scope(context)["section_ids"])
  values.flat_map { |value| value.to_s.scan(/\bS\d{2,}[A-Z]?\b/) }.uniq
end

def collect_pointer_paths(value, result = [])
  case value
  when Hash
    value.each_value { |child| collect_pointer_paths(child, result) }
  when Array
    value.each { |child| collect_pointer_paths(child, result) }
  when String
    result << value if value.start_with?("runs/") && !value.include?("#")
  end
  result
end

def active_revision_contracts(run_path, contracts)
  active_stage_id = inferred_active_stage_id(run_path)
  context = current_context_for_run(run_path)
  pointer_paths = context ? IdolCurrentNextV2.selected_pointer_paths(context).map { |path| rel_path(path) }.uniq : []
  active_sections_root = active_stage_id.to_s.empty? ? nil : run_path.join("work", active_stage_id, "sections").expand_path.to_s

  contracts.select do |path|
    expanded = Pathname.new(path).expand_path.to_s
    rel = rel_path(path)
    pointer_paths.include?(rel) ||
      (active_sections_root && (expanded == active_sections_root || expanded.start_with?(active_sections_root + File::SEPARATOR)))
  end
end

def front_planning_entry_gate_required_for_run?(run_path)
  return true if inferred_active_stage_id(run_path).to_s == "front_planning_integration"

  song_lock = run_path.join("00A-song-lock.yaml")
  song_lock.file? && load_yaml(song_lock)["status"].to_s == "locked"
end

def advisory_candidate_path?(path)
  pathname = Pathname.new(path)
  basename = pathname.basename.to_s.downcase
  return true if basename.match?(/(?:\A|[-_.])(candidate|draft|backup|archive)(?:[-_.]|\z)/)

  pathname.each_filename.any? { |segment| %w[candidates archive archives].include?(segment.downcase) }
end

def latest_match(run_path, patterns, canonical_only: false)
  matches = patterns.flat_map do |pattern|
    Dir.glob((run_path + pattern).to_s)
  end.select { |path| File.file?(path) }
  matches.reject! { |path| advisory_candidate_path?(path) } if canonical_only

  return nil if matches.empty?

  sorted = matches.sort_by do |path|
    basename = File.basename(path)
    version = basename.match(/(?:^|[-_])v(\d+)(?:\D|$)/)&.[](1)&.to_i || -1
    [version, File.mtime(path), path]
  end
  rel_path(sorted.last)
end

def add_worklist_check(checks, id:, group:, label:, source_artifact:, worklist_artifact:, generator_command:)
  source_path = resolve_path(source_artifact)
  unless source_path && File.file?(source_path.to_s)
    checks << Check.new(
      id: id,
      group: group,
      label: label,
      status: "missing",
      blocking: true,
      artifact: source_artifact.to_s,
      command: "",
      exit_status: nil,
      details: "Source artifact for worklist freshness is missing: #{source_artifact}"
    )
    return
  end

  if blank?(worklist_artifact) || !readable_file?(worklist_artifact)
    checks << Check.new(
      id: id,
      group: group,
      label: label,
      status: "missing",
      blocking: true,
      artifact: worklist_artifact.to_s.empty? ? "(not found)" : worklist_artifact.to_s,
      command: generator_command,
      exit_status: nil,
      details: "Required blocker worklist is missing. Generate it with: #{generator_command}"
    )
    return
  end

  worklist_path = resolve_path(worklist_artifact)
  source_mtime = File.mtime(source_path.to_s)
  worklist_mtime = File.mtime(worklist_path.to_s)
  stale = worklist_mtime < source_mtime

  details = [
    "source_artifact: #{rel_path(source_path)}",
    "source_mtime: #{source_mtime.iso8601}",
    "worklist_artifact: #{rel_path(worklist_path)}",
    "worklist_mtime: #{worklist_mtime.iso8601}"
  ]
  details << "Regenerate it with: #{generator_command}" if stale

  checks << Check.new(
    id: id,
    group: group,
    label: label,
    status: stale ? "fail" : "pass",
    blocking: stale,
    artifact: rel_path(worklist_path),
    command: generator_command,
    exit_status: nil,
    details: details.join("\n")
  )
end

def first_existing(run_path, candidates)
  candidates.each do |candidate|
    path = run_path + candidate
    return rel_path(path) if File.file?(path.to_s)
  end
  nil
end

def resolve_audio_input_lineage(lineage_path)
  document = load_yaml(lineage_path)
  errors = []
  resolved_inputs = {}
  root_prefix = "#{ROOT}#{File::SEPARATOR}"

  unless document["schema_version"].to_s == "idol-audio-input-lineage.v1"
    errors << "schema_version must be idol-audio-input-lineage.v1"
  end
  unless document["status"].to_s == "active_pointer_only"
    errors << "status must be active_pointer_only"
  end

  {
    "selected_audio_analysis" => "selected-audio analysis",
    "audio_motion_director_map" => "audio-motion director map"
  }.each do |input_id, label|
    pointer = document.dig("inputs", input_id)
    unless pointer.is_a?(Hash)
      errors << "#{label} pointer is missing"
      next
    end

    path_text = pointer["canonical_path"].to_s
    declared_sha = pointer["sha256"].to_s
    source_path = resolve_path(path_text)
    source_inside_repo = source_path && (source_path.to_s == ROOT.to_s || source_path.to_s.start_with?(root_prefix))
    unless source_inside_repo
      errors << "#{label} canonical_path must stay inside this repository: #{path_text}"
      next
    end
    unless source_path.file?
      errors << "#{label} canonical source is missing: #{path_text}"
      next
    end

    begin
      real_path = source_path.realpath
      unless real_path.to_s == ROOT.to_s || real_path.to_s.start_with?(root_prefix)
        errors << "#{label} canonical_path resolves outside this repository: #{path_text}"
        next
      end
    rescue SystemCallError => e
      errors << "#{label} canonical_path cannot be resolved: #{path_text} (#{e.message})"
      next
    end

    unless declared_sha.match?(/\A[a-f0-9]{64}\z/)
      errors << "#{label} sha256 is missing or malformed"
      next
    end
    actual_sha = Digest::SHA256.file(source_path.to_s).hexdigest
    unless actual_sha == declared_sha
      errors << "#{label} sha256 mismatch for #{path_text}: declared=#{declared_sha} actual=#{actual_sha}"
      next
    end

    resolved_inputs[input_id] = rel_path(source_path)
  end

  {
    "document" => document,
    "resolved_inputs" => resolved_inputs,
    "errors" => errors
  }
end

def capture_command(command)
  argv = Array(command).map(&:to_s)
  stdout, stderr, status = Open3.capture3(*argv, chdir: ROOT.to_s)
  [stdout, stderr, status.exitstatus || 1]
rescue Errno::ENOENT => e
  ["", e.message, 127]
end

def compact_details(stdout, stderr, limit: 18)
  lines = []
  [stdout, stderr].each do |text|
    text.to_s.each_line do |line|
      stripped = line.rstrip
      lines << stripped unless stripped.empty?
    end
  end
  return "" if lines.empty?

  clipped = lines.first(limit)
  clipped << "... #{lines.length - limit} more line(s)" if lines.length > limit
  clipped.join("\n")
end

def command_label(command)
  command.join(" ")
end

def add_missing_check(checks, id:, group:, label:, artifact:, blocking:)
  check = Check.new(
    id: id,
    group: group,
    label: label,
    status: "missing",
    blocking: blocking,
    artifact: artifact.to_s,
    command: "",
    exit_status: nil,
    details: blocking ? "Required artifact is missing." : "Optional artifact is not present."
  )
  checks << check
  check
end

def add_command_check(checks, id:, group:, label:, artifact:, command:, blocking_on_fail: true)
  unless readable_file?(artifact)
    add_missing_check(
      checks,
      id: id,
      group: group,
      label: label,
      artifact: artifact,
      blocking: blocking_on_fail
    )
    return checks.last
  end

  stdout, stderr, exit_status = capture_command(command)
  check = Check.new(
    id: id,
    group: group,
    label: label,
    status: exit_status.zero? ? "pass" : "fail",
    blocking: !exit_status.zero? && blocking_on_fail,
    artifact: artifact.to_s,
    command: command_label(command),
    exit_status: exit_status,
    details: compact_details(stdout, stderr)
  )
  checks << check
  check
end

def add_revision_contract_set_check(checks, run_path)
  superseded_root = run_path.join("work", "superseded").expand_path.to_s
  candidates = Dir.glob(run_path.join("work", "**", "*.{yaml,yml,json}").to_s).sort.reject do |path|
    expanded = Pathname.new(path).expand_path.to_s
    expanded == superseded_root || expanded.start_with?(superseded_root + File::SEPARATOR)
  end
  contracts = candidates.select do |path|
    load_yaml(path)["schema_version"].to_s == "idol-harness-artifact-envelope.v1"
  end

  if contracts.empty?
    checks << Check.new(
      id: "revisioned_artifact_contracts",
      group: "harness",
      label: "typed revision/hash artifact contracts",
      status: "missing",
      blocking: false,
      artifact: rel_path(run_path.join("work")),
      command: "ruby scripts/validate_harness_artifact_contract.rb PATH --json",
      exit_status: nil,
      details: "No additive envelope artifacts exist yet. Legacy canonical artifacts remain readable, but revision coherence cannot be proven from typed parent/digest lineage."
    )
    return
  end

  active_contracts = active_revision_contracts(run_path, contracts)
  if active_contracts.empty?
    checks << Check.new(
      id: "revisioned_artifact_contracts",
      group: "harness",
      label: "active typed revision/hash artifact contracts",
      status: "pass",
      blocking: false,
      artifact: rel_path(run_path.join("work")),
      command: "ruby scripts/validate_harness_artifact_contract.rb ACTIVE_PATH --json",
      exit_status: 0,
      details: "active_contract_count=0\nhistorical_envelope_count=#{contracts.length}\nhistorical work envelopes are excluded from current readiness unless the active pointer or active stage sections directory names them"
    )
    return
  end

  failures = []
  summaries = active_contracts.map do |path|
    stdout, stderr, exit_status = capture_command(["ruby", "scripts/validate_harness_artifact_contract.rb", path, "--json"])
    parsed = JSON.parse(stdout) rescue {}
    failures << rel_path(path) unless exit_status.zero?
    "#{rel_path(path)}: #{parsed['status'] || (exit_status.zero? ? 'pass' : 'fail')} revision=#{parsed['revision'] || '?'} stage=#{parsed['stage_id'] || '?'}#{stderr.to_s.strip.empty? ? '' : " stderr=#{stderr.to_s.strip}"}"
  end

  checks << Check.new(
    id: "revisioned_artifact_contracts",
    group: "harness",
    label: "active typed revision/hash artifact contracts",
    status: failures.empty? ? "pass" : "fail",
    blocking: !failures.empty?,
    artifact: active_contracts.map { |path| rel_path(path) }.join(", "),
    command: "ruby scripts/validate_harness_artifact_contract.rb ACTIVE_PATH --json",
    exit_status: failures.empty? ? 0 : 1,
    details: (summaries + ["active_contract_count=#{active_contracts.length}", "historical_envelope_count=#{contracts.length - active_contracts.length}"]).join("\n")
  )
end

def dispatch_binding?(rows, path, sha256 = nil)
  Array(rows).any? do |row|
    next false unless row.is_a?(Hash) && row["path"].to_s == path.to_s

    sha256.nil? || row["sha256"].to_s == sha256.to_s
  end
end

def legacy_stage_baseline_status(run_path, stage_id, artifact_rel, artifact_sha)
  receipt_root = run_path.join("work", "skill-application-receipts", stage_id)
  receipt_paths = Dir.glob(receipt_root.join("**", "*.{yaml,yml}").to_s).sort.map { |path| Pathname.new(path) }
  return nil if receipt_paths.empty?

  matching = receipt_paths.each_with_object([]) do |receipt_path, result|
    document = load_yaml(receipt_path)
    next unless document["schema_version"].to_s == "idol-skill-application-receipt.v3"
    next unless document["run"].to_s == rel_path(run_path)
    next unless document["stage_id"].to_s == stage_id.to_s
    next unless document["status"].to_s == "complete"
    next if document["owner"].to_s.empty?
    next unless document.dig("owning_skill", "read_complete") == true
    next if Array(document["application_evidence"]).empty?
    next unless document.dig("creative_authorship", "script_authored_creative_values") == false
    next unless Array(document["output_targets"]).map(&:to_s).include?(artifact_rel)
    next unless dispatch_binding?(document["output_evidence"], artifact_rel, artifact_sha)

    result << [receipt_path, receipt_path.mtime]
  end

  if matching.empty?
    stale_whole = receipt_root.join("whole.yaml")
    details = [
      "No single stage-local legacy receipt independently binds the exact current canonical artifact path and SHA-256; a Department Dispatch is required.",
      "legacy_receipts_checked=#{receipt_paths.length}"
    ]
    details << "stale_or_ineligible_whole=#{rel_path(stale_whole)}" if stale_whole.file?
    return ["missing", details.join("\n")]
  end

  baseline_path, = matching.max_by { |path, modified_at| [modified_at, path.to_s] }
  [
    "pass",
    "legacy_baseline=#{rel_path(baseline_path)}\nartifact=#{artifact_rel}\nartifact_sha256=#{artifact_sha}\ncompatibility=evidence_only_non_authoring\nnext_material_resumption_requires_dispatch=true\nThe one frozen stage-local receipt is not v18 application evidence, is not combined with another receipt, and must not be refreshed."
  ]
end

def department_dispatch_status(run_path, stage_id, artifact_path, scope_mode: nil)
  artifact = resolve_path(artifact_path)
  return ["missing", "Active stage artifact is missing: #{artifact_path}"] unless artifact&.file?

  artifact_rel = rel_path(artifact)
  artifact_sha = Digest::SHA256.file(artifact.to_s).hexdigest
  dispatch_root = run_path.join("work", "department-dispatches")
  stage_rows = Dir.glob(dispatch_root.join("*.yaml").to_s).sort.each_with_object([]) do |path, result|
    document = load_yaml(path)
    next unless document.dig("launch", "task", "exact_scope", "stage_id").to_s == stage_id.to_s

    result << [Pathname.new(path), document]
  end
  rows = stage_rows.select do |_path, document|
    expected_paths = Array(document.dig("launch", "bounded_output", "expected_paths")).map(&:to_s)
    expected_paths.include?(artifact_rel) ||
      dispatch_binding?(document.dig("runtime_return", "outputs"), artifact_rel) ||
      dispatch_binding?(document.dig("promotion", "canonical_artifacts"), artifact_rel)
  end

  if rows.empty?
    if stage_rows.empty?
      legacy_baseline = legacy_stage_baseline_status(run_path, stage_id, artifact_rel, artifact_sha)
      return legacy_baseline if legacy_baseline
    end
    launched_paths = stage_rows.map { |path, _document| rel_path(path) }
    launch_detail = launched_paths.empty? ? "none" : launched_paths.join(", ")
    return [
      "missing",
      "Missing department dispatch for #{stage_id} and #{artifact_rel}. Expected one stable task record under #{rel_path(dispatch_root)}/TASK_ID.yaml. Same-stage dispatch records without this output binding: #{launch_detail}. Legacy receipts remain readable evidence only; once a new same-stage dispatch is launched they cannot carry the gate."
    ]
  end

  failures = []
  rows.sort_by { |path, document| [document.dig("promotion", "decided_at").to_s, path.to_s] }.reverse_each do |dispatch_path, document|
    stdout, stderr, status = capture_command([
      "ruby",
      "scripts/validate_department_dispatch.rb",
      "--require-promoted",
      dispatch_path
    ])
    issues = []
    issues << "dispatch validator failed: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ')}" unless status.zero?
    scope = document.dig("launch", "task", "exact_scope")
    issues << "dispatch must target stage #{stage_id}" unless scope.is_a?(Hash) && scope["stage_id"].to_s == stage_id.to_s
    if scope_mode && scope.is_a?(Hash) && scope["mode"].to_s != scope_mode.to_s
      issues << "dispatch scope must use #{scope_mode}"
    end
    unless dispatch_binding?(document.dig("runtime_return", "outputs"), artifact_rel, artifact_sha)
      issues << "runtime return does not bind current artifact bytes: #{artifact_rel}"
    end
    unless dispatch_binding?(document.dig("director_review", "reviewed_outputs"), artifact_rel, artifact_sha)
      issues << "director review does not bind current artifact bytes: #{artifact_rel}"
    end
    unless dispatch_binding?(document.dig("promotion", "canonical_artifacts"), artifact_rel, artifact_sha)
      issues << "promotion does not bind current canonical artifact bytes: #{artifact_rel}"
    end

    if issues.empty?
      return [
        "pass",
        "dispatch=#{rel_path(dispatch_path)}\nstage_id=#{stage_id}\nartifact=#{artifact_rel}\nartifact_sha256=#{artifact_sha}\ndirector_disposition=#{document.dig('director_review', 'disposition')}"
      ]
    end
    failures << "#{rel_path(dispatch_path)}:\n#{issues.join("\n")}"
  end

  ["fail", failures.join("\n")]
end

def front_planning_entry_gate_status(run_path, readiness_path)
  department_dispatch_status(
    run_path,
    "front_planning_integration",
    readiness_path,
    scope_mode: "whole_run"
  )
end

def stage_department_dispatch_status(run_path)
  stage_artifacts = {
    "front_planning_integration" => latest_match(run_path, ["research/front-planning-readiness-v*.yaml", "research/front-planning-readiness-v*.yml"], canonical_only: true),
    "song_production_lock" => first_existing(run_path, ["00A-song-lock.yaml"]),
    "mv_performance_direction" => first_existing(run_path, ["01-song-choreography-performance-mv-map.yaml"]),
    "mv_storyboard_direction" => first_existing(run_path, ["02A-master-storyboard.yaml"])
  }.compact
  return ["pass", "No Front Planning-through-02A stage artifacts require an active department dispatch yet."] if stage_artifacts.empty?

  active_stage_id = inferred_active_stage_id(run_path)
  active_artifact = stage_artifacts[active_stage_id]
  unless active_artifact
    return [
      "pass",
      "active_stage_id=#{active_stage_id}\nhistorical_stage_artifact_count=#{stage_artifacts.length}\nOnly the current or materially resumed stage requires a promoted dispatch; legacy receipts and earlier dispatches remain provenance evidence."
    ]
  end

  department_dispatch_status(run_path, active_stage_id, active_artifact)
end

def run_owned_canonical_creative_mutator_status(run_path)
  stdout, stderr, status = capture_command([
    "ruby",
    "scripts/idol_creative_truth_guard.rb",
    rel_path(run_path),
    "--json"
  ])
  document = JSON.parse(stdout)
  return ["pass", "#{document['scripts_scanned']} run-owned helper(s) passed target-aware creative-write inspection."] if status.zero?

  details = Array(document["offenders"]).map do |row|
    reasons = Array(row["reasons"]).map { |reason| reason["reason"].to_s }.reject(&:empty?).uniq
    "#{row['path']}: #{reasons.join(', ')}"
  end
  [
    "fail",
    "Run-owned helpers may write diagnostic candidates under work/ only. Canonical creative writes, selected/held planning-state writes, script-authored creative verdicts, and script-claimed model authorship are blocked:\n#{details.join("\n")}"
  ]
rescue JSON::ParserError
  ["fail", "Creative-truth guard failed without valid JSON: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ')}"]
end

def founder_intervention_receipts_status(run_path)
  receipts = Dir.glob(run_path.join("review", "founder-interventions", "*.{yaml,yml}").to_s).sort
  return ["pass", "No Founder intervention receipt is pending."] if receipts.empty?

  active_invalid = []
  pending = []
  complete = []
  historical_pending = []
  historical_receipts = []
  current_context = current_context_for_run(run_path)
  current_next = current_context && current_context["document"]
  active_paths = current_context ? IdolCurrentNextV2.selected_pointer_paths(current_context).map { |path| rel_path(path) }.uniq : []
  active_sections = active_section_ids_for_run(run_path)
  active_stage_id = inferred_active_stage_id(run_path)
  active_recorded_at = active_paths.filter_map do |path|
    value = load_yaml(path)["recorded_at"].to_s
    Time.parse(value) unless value.empty?
  rescue ArgumentError
    nil
  end.max
  receipts.each do |path|
    receipt = Pathname.new(path)
    document = load_yaml(receipt)
    intervention_status = document["status"].to_s
    receipt_rel = rel_path(receipt)
    receipt_sections = Array(document.dig("routing", "affected_section_ids")).map(&:to_s)
    receipt_stage = document.dig("routing", "owning_stage_id").to_s
    recorded_at = Time.parse(document["recorded_at"].to_s) rescue nil
    later_active_scope = current_next &&
                         active_recorded_at &&
                         recorded_at &&
                         recorded_at > active_recorded_at &&
                         receipt_stage == active_stage_id &&
                         !(receipt_sections & active_sections).empty?
    readiness_relevant = current_next.nil? || active_paths.include?(receipt_rel) || later_active_scope

    unless readiness_relevant
      historical_receipts << "#{document['intervention_id'] || receipt.basename}=#{intervention_status.empty? ? 'legacy_or_unclassified' : intervention_status} (#{receipt_rel})"
      historical_pending << "#{document['intervention_id']}=#{intervention_status} (#{receipt_rel})" unless %w[integrated superseded].include?(intervention_status)
      next
    end

    stdout, stderr, status = capture_command([
      "ruby",
      "scripts/validate_founder_intervention_receipt.rb",
      receipt
    ])
    unless status.zero?
      active_invalid << "#{receipt_rel}: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ')}"
      next
    end

    if %w[integrated superseded].include?(intervention_status)
      complete << "#{document['intervention_id']}=#{intervention_status}"
    else
      pending << "#{document['intervention_id']}=#{intervention_status} (#{receipt_rel})"
    end
  end

  return ["fail", active_invalid.join("\n")] unless active_invalid.empty?
  unless pending.empty?
    return [
      "fail",
      "Founder intervention is not integrated; hold its affected scope and return to the declared owning stage:\n#{pending.join("\n")}"
    ]
  end

  details = complete
  details << "historical_receipt_count=#{historical_receipts.length}"
  details << "historical_or_other_scope_pending=#{historical_pending.length}"
  details.concat(historical_pending.first(10).map { |row| "diagnostic_only: #{row}" })
  details << "Historical or other-section receipts are provenance diagnostics only; validate them when that exact scope resumes."
  ["pass", details.join("\n")]
end

def add_internal_check(checks, id:, group:, label:, artifact:, blocking_on_fail: true)
  unless readable_file?(artifact)
    add_missing_check(
      checks,
      id: id,
      group: group,
      label: label,
      artifact: artifact,
      blocking: blocking_on_fail
    )
    return
  end

  status, details = yield
  checks << Check.new(
    id: id,
    group: group,
    label: label,
    status: status,
    blocking: status != "pass" && blocking_on_fail,
    artifact: artifact.to_s,
    command: "",
    exit_status: nil,
    details: details.to_s
  )
end

def add_schema_check(checks, id:, group:, label:, schema:, artifact:, required: false)
  unless readable_file?(artifact)
    add_missing_check(
      checks,
      id: id,
      group: group,
      label: label,
      artifact: artifact,
      blocking: required
    )
    return checks.last
  end

  command = [
    "scripts/idol-video-python",
    "scripts/validate_json_schema.py",
    schema,
    artifact.to_s
  ]
  add_command_check(
    checks,
    id: id,
    group: group,
    label: label,
    artifact: artifact,
    command: command,
    blocking_on_fail: true
  )
end

def required_hash_fields_missing(hash, fields)
  return fields unless hash.is_a?(Hash)

  fields.select do |field|
    value = hash[field]
    value.respond_to?(:empty?) ? value.empty? : blank?(value)
  end
end

def track_local_first_direction_status(track_board)
  planning = track_board.dig("track_usage_board", "local_first_direction_planning")
  missing = required_hash_fields_missing(
    planning,
    %w[local_sources_checked_first local_sources_checked storyline_spine space_pool camera_body_vocabulary rerun_gate]
  )
  return ["fail", "Missing local_first_direction_planning fields: #{missing.join(', ')}"] unless missing.empty?

  return ["fail", "local_sources_checked_first must be true"] unless planning["local_sources_checked_first"] == true

  local_sources = Array(planning["local_sources_checked"]).map(&:to_s).reject(&:empty?)
  return ["fail", "local_sources_checked must name at least one local source"] if local_sources.empty?

  missing_sources = local_sources.reject { |source| readable_file?(source) }
  return ["fail", "local_sources_checked paths missing: #{missing_sources.join(', ')}"] unless missing_sources.empty?

  rerun_gate = planning["rerun_gate"]
  missing_rerun = required_hash_fields_missing(rerun_gate, %w[decision])
  missing_rerun << "missing_questions" unless rerun_gate.is_a?(Hash) && rerun_gate.key?("missing_questions")
  return ["fail", "rerun_gate missing fields: #{missing_rerun.join(', ')}"] unless missing_rerun.empty?

  details = [
    "local_sources_checked: #{local_sources.length}",
    "rerun_decision: #{rerun_gate['decision']}",
    "missing_questions: #{Array(rerun_gate['missing_questions']).length}"
  ]
  ["pass", details.join("\n")]
end

def track_style_system_lock_status(track_board)
  style_lock = track_board.dig("track_usage_board", "style_system_lock")
  missing = required_hash_fields_missing(
    style_lock,
    %w[silhouette_material_palette motion_read_priorities motif_limits reject_terms]
  )
  return ["fail", "Missing style_system_lock fields: #{missing.join(', ')}"] unless missing.empty?

  motion_priorities = Array(style_lock["motion_read_priorities"]).map(&:to_s).reject(&:empty?)
  reject_terms = Array(style_lock["reject_terms"]).map(&:to_s).reject(&:empty?)
  return ["fail", "style_system_lock.motion_read_priorities must be non-empty"] if motion_priorities.empty?
  return ["fail", "style_system_lock.reject_terms must be non-empty"] if reject_terms.empty?

  motif_limits = style_lock["motif_limits"].to_s.downcase
  unless motif_limits.include?("do not") && (motif_limits.include?("default") || motif_limits.include?("stuff"))
    return ["fail", "style_system_lock.motif_limits must block default motif stuffing"]
  end

  details = [
    "motion_read_priorities: #{motion_priorities.length}",
    "reject_terms: #{reject_terms.length}",
    "motif_limits: #{style_lock['motif_limits']}"
  ]
  ["pass", details.join("\n")]
end

def active_front_planning_readiness_status(readiness, run_rel, content_id)
  issues = []
  details = []
  unless readiness["schema_version"].to_s == "front-planning-readiness.v17"
    return ["fail", "Front Planning must use the active front-planning-readiness.v17 contract"]
  end
  issues << "Front Planning content_id differs from the owning run identity" unless readiness["content_id"].to_s == content_id.to_s

  status = readiness["status"].to_s
  founder_decision = readiness.dig("founder_gate", "decision").to_s
  expected = {
    "draft" => "pending",
    "founder_review" => "pending",
    "direction_aligned" => "pass",
    "director_closed" => "pass",
    "hold" => "hold",
    "rejected" => "reject"
  }[status]
  issues << "Front Planning status is not an active v17 state" unless expected
  issues << "Front Planning status #{status} requires founder_gate.decision=#{expected}" if expected && founder_decision != expected

  verify_pointer = lambda do |binding, label|
    unless binding.is_a?(Hash)
      issues << "#{label} must be a path/SHA-256 binding"
      next
    end
    value = binding["path"].to_s
    declared = binding["sha256"].to_s
    path = resolve_path(value)
    if value.empty? || !path&.file?
      issues << "#{label} is missing: #{value}"
    elsif !declared.match?(/\A[a-f0-9]{64}\z/)
      issues << "#{label} has no lowercase SHA-256"
    elsif Digest::SHA256.file(path.to_s).hexdigest != declared
      issues << "#{label} SHA-256 mismatch"
    end
  end

  verify_pointer.call(readiness["selected_song_lock"], "selected_song_lock")
  visual = readiness["current_title_visual_identity"]
  if visual.is_a?(Hash)
    expected_root = "assets/members/album-assets/#{visual['album_key']}/#{visual['title_key']}"
    issues << "current-title asset_root does not match its album/title keys" unless visual["asset_root"].to_s == expected_root
    verify_pointer.call(visual["asset_manifest"], "current-title asset manifest")
  end
  assets = Array(visual.is_a?(Hash) ? visual["assets"] : nil).select { |row| row.is_a?(Hash) }
  asset_by_id = {}
  assets.each do |asset|
    asset_id = asset["asset_id"].to_s
    issues << "current-title visual asset has a blank asset_id" if asset_id.empty?
    issues << "current-title visual assets duplicate #{asset_id}" if !asset_id.empty? && asset_by_id.key?(asset_id)
    asset_by_id[asset_id] = asset unless asset_id.empty?
    verify_pointer.call({"path" => asset["path"], "sha256" => asset["sha256"]}, "visual asset #{asset_id}")
  end

  research = readiness["reference_connection_research"]
  units = Array(research.is_a?(Hash) ? research["reference_units"] : nil).select { |row| row.is_a?(Hash) }
  unit_by_id = {}
  units.each do |unit|
    unit_id = unit["reference_unit_id"].to_s
    issues << "reference unit has a blank reference_unit_id" if unit_id.empty?
    issues << "reference units duplicate #{unit_id}" if !unit_id.empty? && unit_by_id.key?(unit_id)
    unit_by_id[unit_id] = unit unless unit_id.empty?
    verify_pointer.call({"path" => unit["source_path"], "sha256" => unit["source_sha256"]}, "reference unit #{unit_id}")
  end

  sections = Array(readiness["section_plan"]).select { |row| row.is_a?(Hash) }
  section_ids = sections.map { |row| row["section_id"].to_s }
  duplicates = section_ids.reject(&:empty?).group_by(&:itself).select { |_id, rows| rows.length > 1 }.keys
  issues.concat(duplicates.map { |id| "Front Planning duplicates section #{id}" })
  known_sections = section_ids.reject(&:empty?).uniq
  units.each do |unit|
    unknown = Array(unit["target_section_ids"]).map(&:to_s) - known_sections
    issues << "reference unit #{unit['reference_unit_id']} targets unknown sections: #{unknown.join(', ')}" unless unknown.empty?
  end

  sections.each do |section|
    section_id = section["section_id"].to_s
    assigned_ids = (
      Array(section["sequence_reference_unit_ids"]) +
      Array(section["scene_reference_unit_ids"]) +
      Array(section["choreography_reference_unit_ids"]) +
      Array(section["major_scene_flow"]).flat_map { |scene| scene.is_a?(Hash) ? Array(scene["reference_unit_ids"]) : [] }
    ).map(&:to_s).reject(&:empty?).uniq
    assigned_ids.each do |unit_id|
      unit = unit_by_id[unit_id]
      if unit.nil?
        issues << "#{section_id} assigns unknown reference unit #{unit_id}"
      elsif !Array(unit["target_section_ids"]).map(&:to_s).include?(section_id)
        issues << "#{section_id} assigns reference unit #{unit_id} without a matching target section"
      end
    end

    (Array(section["member_visual_asset_ids"]) + Array(section["background_world_asset_ids"])).map(&:to_s).reject(&:empty?).uniq.each do |asset_id|
      asset = asset_by_id[asset_id]
      if asset.nil?
        issues << "#{section_id} assigns unknown current-title asset #{asset_id}"
      elsif !Array(asset["section_ids"]).map(&:to_s).include?(section_id)
        issues << "#{section_id} assigns asset #{asset_id} without matching section scope"
      end
    end
  end

  details << "run: #{run_rel}"
  details << "status: #{status}"
  details << "sections: #{sections.length}"
  details << "reference_units: #{units.length}"
  details << "current_title_assets: #{assets.length}"
  details << "comparison_floor: adaptive decision-ready actual units; exact-five one-second Sequence Unit remains schema/validator enforced"
  details << "creative_adequacy: contextual Director/Founder judgment only; counts do not pass or fail it"
  issues.empty? ? ["pass", details.join("\n")] : ["fail", (issues + details).join("\n")]
end

def active_front_planning_transfer_gate_status(readiness_path, artifacts)
  issues = []
  details = []
  front_path = resolve_path(readiness_path)
  expected_front = {
    "path" => rel_path(front_path),
    "sha256" => Digest::SHA256.file(front_path.to_s).hexdigest
  }

  one_path = artifacts["01"]
  one = nil
  if readable_file?(one_path)
    one = load_yaml(one_path)
    issues << "01 must use active schema 3.0" unless one["schema_version"].to_s == "3.0"
    issues << "01 source_front_planning does not match active Front Planning path/hash" unless one["source_front_planning"] == expected_front
    details << "01 Front Planning lineage: checked"
  else
    details << "01: not present; transfer check is waiting"
  end

  two_a_path = artifacts["02A"]
  if readable_file?(two_a_path)
    two_a = load_yaml(two_a_path)
    issues << "02A must use active schema 3.0" unless two_a["schema_version"].to_s == "3.0"
    issues << "02A source_front_planning does not match active Front Planning path/hash" unless two_a["source_front_planning"] == expected_front
    if readable_file?(one_path)
      expected_one = {
        "path" => rel_path(one_path),
        "sha256" => Digest::SHA256.file(resolve_path(one_path).to_s).hexdigest
      }
      issues << "02A source_01_direction does not match active 01 path/hash" unless two_a["source_01_direction"] == expected_one
    else
      issues << "02A exists without its active 01 owner artifact"
    end
    details << "02A Front Planning/01 lineage: checked"
  else
    details << "02A: not present; transfer check is waiting"
  end

  issues.empty? ? ["pass", details.join("\n")] : ["fail", (issues + details).join("\n")]
end

def active_section_owner_coverage_status(artifacts, readiness:)
  details = []
  issues = []
  expected_sections = Array(readiness.is_a?(Hash) ? readiness["section_plan"] : nil).filter_map do |row|
    row["section_id"].to_s if row.is_a?(Hash) && !blank?(row["section_id"])
  end

  one_path = artifacts["01"]
  if readable_file?(one_path)
    one = load_yaml(one_path)
    actual = Array(one["section_directions"]).filter_map do |row|
      row["section_id"].to_s if row.is_a?(Hash) && !blank?(row["section_id"])
    end
    issues << "01 section_directions must exact-cover Front Planning sections in order" unless actual == expected_sections
    details << "01 sections: #{actual.length}/#{expected_sections.length}"
  else
    details << "01: not present; section coverage check is waiting"
  end

  two_a_path = artifacts["02A"]
  if readable_file?(two_a_path)
    two_a = load_yaml(two_a_path)
    actual = Array(two_a["section_shards"]).flat_map do |row|
      row.is_a?(Hash) ? Array(row["section_ids"]).map(&:to_s) : []
    end
    issues << "02A section_shards must exact-cover Front Planning sections in order" unless actual == expected_sections
    details << "02A sections: #{actual.length}/#{expected_sections.length}"
  else
    details << "02A: not present; section coverage check is waiting"
  end

  issues.empty? ? ["pass", details.join("\n")] : ["fail", (issues + details).join("\n")]
end

def record_id(record)
  return "" unless record.is_a?(Hash)

  %w[core_cut_id branch_cut_id cue_id cut_id beat_id packet_id id shard_id].each do |field|
    value = record[field].to_s.strip
    return value unless value.empty?
  end
  ""
end

def present_hash?(value)
  value.is_a?(Hash) && !value.empty?
end

def nested_value(record, path)
  path.reduce(record) do |current, key|
    current.is_a?(Hash) ? current[key] : nil
  end
end

def present_at_any_path?(record, paths)
  paths.any? do |path|
    value = nested_value(record, path)
    value.is_a?(Hash) ? !value.empty? : !blank?(value)
  end
end

def count_present(records, paths)
  records.count { |record| present_at_any_path?(record, paths) }
end

def sample_missing_ids(records, paths, limit: 8)
  records.reject { |record| present_at_any_path?(record, paths) }
         .first(limit)
         .map { |record| record_id(record) }
         .reject(&:empty?)
end

def value_contains_any?(value, needles)
  text = value.to_s.downcase
  needles.any? { |needle| text.include?(needle) }
end

def edit_marker_plan_carry_counts(slots)
  slots.each_with_object(Hash.new(0)) do |slot, counts|
    source_marker = slot["source_action_marker"].is_a?(Hash) ? slot["source_action_marker"] : {}
    counts["source_action"] += 1 unless blank?(source_marker["visible_event"])

    camera_values = [
      source_marker["camera_event"],
      slot["motion_continuity"],
      slot["directorial_transition_intent"],
      slot["audio_marker_alignment"]
    ]
    counts["camera_or_motion_carry"] += 1 if camera_values.any? do |value|
      value_contains_any?(value, ["camera", "gaze", "view", "frame", "motion", "body", "hand", "foot", "object"])
    end

    counts["story_flow"] += 1 unless blank?(slot["story_flow_continuity"])
    counts["space_visible_feeling"] += 1 unless blank?(slot["space_visible_feeling_progression"])
    counts["directorial_transition"] += 1 unless blank?(slot["directorial_transition_intent"])
    counts["audio_marker_alignment"] += 1 unless blank?(slot["audio_marker_alignment"])
  end
end

def video_trace_records(video_manifest_path)
  return ["none", nil, []] unless readable_file?(video_manifest_path)

  manifest = load_yaml(video_manifest_path)
  ["03V manifest", video_manifest_path, Array(manifest["cues"]).select { |cue| cue.is_a?(Hash) }]
end

def planning_video_edit_trace_status(artifacts)
  two_a_path = artifacts["02A"]
  return ["pass", "02A master storyboard is not present; upstream trace check is waiting."] unless readable_file?(two_a_path)

  two_a = load_yaml(two_a_path)
  unless two_a["schema_version"].to_s == "3.0"
    return [
      "fail",
      "Historical 02A schema #{two_a['schema_version'].inspect} is evidence-only; " \
      "active 03V/04 trace requires 3.0 immutable Official-Core and Branch-Cut truth."
    ]
  end

  core_cuts = Array(two_a["master_storyboard"]).select { |cut| cut.is_a?(Hash) }
  return ["fail", "02A 3.0 master storyboard has no Core Cut records."] if core_cuts.empty?

  branch_cuts = core_cuts.flat_map do |core_cut|
    Array(core_cut.dig("compile_seed", "branch_cuts")).select { |branch_cut| branch_cut.is_a?(Hash) }
  end
  details = [
    "02A_core_cuts: #{core_cuts.length}",
    "02A_branch_cuts: #{branch_cuts.length}"
  ]
  issues = []
  core_ids = core_cuts.map { |core_cut| core_cut["core_cut_id"].to_s }.reject(&:empty?)
  branch_ids = branch_cuts.map { |branch_cut| branch_cut["branch_cut_id"].to_s }.reject(&:empty?)
  issues << "02A Core Cut ids are missing or duplicated." unless core_ids.length == core_cuts.length && core_ids.uniq.length == core_ids.length
  issues << "02A Branch Cut ids are missing or duplicated." unless branch_ids.length == branch_cuts.length && branch_ids.uniq.length == branch_ids.length

  core_cuts.each do |core_cut|
    core_id = core_cut["core_cut_id"].to_s
    branches = Array(core_cut.dig("compile_seed", "branch_cuts")).select { |branch| branch.is_a?(Hash) }
    issues << "02A Core Cut #{core_id} has no Branch Cuts." if branches.empty?
    issues << "02A Core Cut #{core_id} is missing its immutable 01 Core projection." unless present_hash?(core_cut["imported_core"])
    issues << "02A Core Cut #{core_id} is missing its exact 01 source pointer/hash." unless present_hash?(core_cut["source_01_core"])
    issues << "02A Core Cut #{core_id} must remain owned by the immutable 01 import." unless core_cut["authorship_owner"].to_s == "01_imported_immutable"
    issues << "02A Core Cut #{core_id} reports an unauthorized Core mutation." unless core_cut["core_mutation_performed"] == false
  end
  branch_cuts.each do |branch_cut|
    branch_id = branch_cut["branch_cut_id"].to_s
    %w[core_event_derivation distinct_screen_contribution visible_action composition_lock camera_treatment continuity_in continuity_out].each do |field|
      issues << "02A Branch Cut #{branch_id} is missing #{field}." if blank?(branch_cut[field])
    end
  end

  video_source_label, video_source_path, video_records = video_trace_records(artifacts["03V"])
  if video_records.empty?
    details << "03V/video prompt trace: not present; downstream trace check is waiting."
  else
    video_cue_ids = video_records.map { |record| record["cue_id"].to_s }.reject(&:empty?)
    video_core_ids = video_records.map { |record| record["core_cut_id"].to_s }.reject(&:empty?)
    overlap = video_core_ids.count { |id| core_ids.include?(id) }
    details << "#{video_source_label}: #{video_records.length} record(s) from #{video_source_path}"
    details << "03V cue Core-Cut ids matching 02A: #{overlap}/#{video_core_ids.length}" unless video_core_ids.empty?

    {
      "03V_source_production_cut_images" => [[["source_production_cut_images"]], "03V cue(s) missing passed Official-Core/Branch Production-Cut image lineage"],
      "03V_subject_motion_routes" => [[["subject_motion_route"]], "03V cue(s) missing body/object/environment/hold motion route"],
      "03V_camera_motion_routes" => [[["camera_motion_route"]], "03V cue(s) missing camera motion route"],
      "03V_previous_next_continuity" => [[["previous_next_continuity"]], "03V cue(s) missing previous/next continuity"],
      "03V_edit_handoff" => [[["edit_handoff"]], "03V cue(s) missing 04 edit handoff"]
    }.each do |label, (paths, issue_prefix)|
      count = count_present(video_records, paths)
      details << "#{label}: #{count}/#{video_records.length}"
      missing = sample_missing_ids(video_records, paths)
      issues << "#{issue_prefix}: #{missing.join(', ')}" if count != video_records.length && !missing.empty?
    end

    video_records.each do |cue|
      cue_id = cue["cue_id"].to_s
      cue_core_id = cue["core_cut_id"].to_s
      issues << "03V cue #{cue_id} references unknown Core Cut #{cue_core_id}." unless core_ids.include?(cue_core_id)
      Array(cue["source_production_cut_images"]).each do |image|
        next unless image.is_a?(Hash)

        production_cut_id = image["production_cut_id"].to_s
        production_cut_type = image["production_cut_type"].to_s
        parent_core_id = image["parent_core_cut_id"].to_s
        issues << "03V cue #{cue_id} Production Cut #{production_cut_id} carries the wrong parent Core Cut." unless parent_core_id == cue_core_id
        case production_cut_type
        when "official_core"
          issues << "03V cue #{cue_id} references unknown Official Core #{production_cut_id}." unless core_ids.include?(production_cut_id)
          issues << "03V cue #{cue_id} Official Core #{production_cut_id} must identify itself as parent Core." unless production_cut_id == parent_core_id
        when "branch"
          issues << "03V cue #{cue_id} references unknown Branch Cut #{production_cut_id}." unless branch_ids.include?(production_cut_id)
        else
          issues << "03V cue #{cue_id} Production Cut #{production_cut_id} has unknown type #{production_cut_type.inspect}."
        end
      end
    end
  end

  edit_map_path = artifacts["04"]
  edit_marker_plan_path = artifacts["edit_marker_plan"]
  if readable_file?(edit_marker_plan_path)
    edit_marker_plan = load_yaml(edit_marker_plan_path)
    slots = Array(edit_marker_plan["timeline_slots"]).select { |slot| slot.is_a?(Hash) }
    counts = edit_marker_plan_carry_counts(slots)
    details << "04_edit_marker_plan_slots: #{slots.length}"
    details << "04_edit_marker_plan_version: #{edit_marker_plan['schema_version']}"
    issues << "04 marker plan must use active idol_edit_marker_plan.v6." unless edit_marker_plan["schema_version"].to_s == "idol_edit_marker_plan.v6"
    lineage_count = slots.count { |slot| present_hash?(slot["source_lineage"]) }
    details << "04_marker_plan_branch_lineage: #{lineage_count}/#{slots.length}"
    issues << "04 marker plan slots are missing Branch-Cut/03V source lineage." unless lineage_count == slots.length

    known_video_cue_ids = video_records.map { |record| record["cue_id"].to_s }.reject(&:empty?)
    slots.each do |slot|
      lineage = slot["source_lineage"]
      next unless lineage.is_a?(Hash)

      slot_id = slot["slot"].to_s
      source_origin = lineage["source_origin"].to_s
      source_branch_ids = Array(lineage["source_branch_cut_ids"]).map(&:to_s)
      target_branch_ids = Array(lineage["continuity_target_branch_cut_ids"]).map(&:to_s)
      source_cue_ids = Array(lineage["source_03v_cue_ids"]).map(&:to_s)
      (source_branch_ids + target_branch_ids).uniq.each do |branch_id|
        issues << "04 Edit Slot #{slot_id} references unknown Branch Cut #{branch_id}." unless branch_ids.include?(branch_id)
      end
      if source_origin == "03v_branch_derived"
        source_cue_ids.each do |cue_id|
          issues << "04 Edit Slot #{slot_id} references unknown 03V cue #{cue_id}." unless known_video_cue_ids.include?(cue_id)
        end
      end
    end

    {
      "04_marker_plan_source_action_markers" => "source_action",
      "04_marker_plan_camera_or_motion_carry" => "camera_or_motion_carry",
      "04_marker_plan_story_flow_continuity" => "story_flow",
      "04_marker_plan_space_visible_feeling_progression" => "space_visible_feeling",
      "04_marker_plan_directorial_transition_intent" => "directorial_transition",
      "04_marker_plan_audio_marker_alignment" => "audio_marker_alignment"
    }.each do |label, key|
      details << "#{label}: #{counts[key]}/#{slots.length}"
    end

    if slots.any?
      issues << "04 edit marker plan slots have no source-action marker carry." if counts["source_action"].zero?
      issues << "04 edit marker plan slots have no camera/body/object motion carry." if counts["camera_or_motion_carry"].zero?
      issues << "04 edit marker plan slots have no story-flow continuity carry." if counts["story_flow"].zero?
      issues << "04 edit marker plan slots have no directorial transition intent carry." if counts["directorial_transition"].zero?
    end
  end

  if readable_file?(edit_map_path)
    edit_map = load_yaml(edit_map_path)
    shards = Array(edit_map.dig("section_workflow", "shards")).select { |shard| shard.is_a?(Hash) }
    upstream = edit_map["upstream_intent_context_contract"]
    read_scope = upstream.is_a?(Hash) ? Array(upstream["read_scope"]).map(&:to_s) : []
    edit_marker_ref = edit_map["edit_marker_plan_ref"].is_a?(Hash) ? edit_map["edit_marker_plan_ref"] : {}
    shard_marker_refs = shards.map { |shard| shard.dig("paths", "edit_marker_plan").to_s }.reject(&:empty?)
    details << "04_edit_map: #{edit_map_path}"
    details << "04_edit_map_version: #{edit_map['schema_version']}"
    issues << "04 edit map must use active idol_edit_map.v4." unless edit_map["schema_version"].to_s == "idol_edit_map.v4"
    details << "04_upstream_read_scope: #{read_scope.join(', ')}" unless read_scope.empty?
    details << "04_edit_marker_plan: #{edit_marker_plan_path}" if readable_file?(edit_marker_plan_path)

    if readable_file?(edit_marker_plan_path)
      marker_rel = rel_path(edit_marker_plan_path)
      referenced = edit_marker_ref["path"].to_s == marker_rel || shard_marker_refs.include?(marker_rel)
      issues << "04 edit marker plan exists but is not referenced from 04-edit-map edit_marker_plan_ref.path or section shard edit_marker_plan." unless referenced
      issues << "04-edit-map edit_marker_plan_ref.schema must be idol_edit_marker_plan.v6." unless edit_marker_ref["schema"].to_s == "idol_edit_marker_plan.v6"
    elsif !blank?(edit_marker_ref["path"])
      issues << "04-edit-map edit_marker_plan_ref.path points to a missing file: #{edit_marker_ref['path']}"
    end

    if shards.empty?
      details << "04_section_workflow_shards: not present; whole-film edit route."
    else
      {
        "04_source_action_markers" => [[["source_action_marker"]], "04 shard(s) missing source_action_marker"],
        "04_story_flow_continuity" => [[["story_flow_continuity"]], "04 shard(s) missing story_flow_continuity"],
        "04_space_visible_feeling_progression" => [[["space_visible_feeling_progression"]], "04 shard(s) missing space_visible_feeling_progression"],
        "04_directorial_transition_intent" => [[["directorial_transition_intent"]], "04 shard(s) missing directorial_transition_intent"]
      }.each do |label, (paths, issue_prefix)|
        count = count_present(shards, paths)
        details << "#{label}: #{count}/#{shards.length}"
        missing = sample_missing_ids(shards, paths)
        issues << "#{issue_prefix}: #{missing.join(', ')}" if count != shards.length && !missing.empty?
      end

      expected_scope = %w[
        audio_production_cut_placement
        03v_source_production_cut_images
        03v_previous_next_continuity
        03v_edit_handoff
        03v_playback_review
        story_flow_continuity
        space_visible_feeling_progression
      ]
      if read_scope.any?
        missing_scope = expected_scope - read_scope
        issues << "04 upstream_intent_context_contract.read_scope missing trace source(s): #{missing_scope.join(', ')}" unless missing_scope.empty?
      end
    end
  else
    details << "04 edit map: not present; edit trace check is waiting."
  end

  if issues.empty?
    ["pass", details.join("\n")]
  else
    ["fail", (issues + details).join("\n")]
  end
end

def script_run_path_registry_status
  registry_path = resolve_path("automation/idol-script-registry.yaml")
  unless registry_path && File.file?(registry_path.to_s)
    return ["fail", "policy_source: automation/idol-script-registry.yaml\nregistry is missing."]
  end

  begin
    registry = YAML.safe_load(File.read(registry_path.to_s, encoding: "UTF-8"), permitted_classes: [], permitted_symbols: [], aliases: false)
  rescue StandardError => error
    return ["fail", "policy_source: automation/idol-script-registry.yaml\nregistry parse failed: #{error.message}"]
  end
  unless registry.is_a?(Hash) && registry["script_entries"].is_a?(Array)
    return ["fail", "policy_source: automation/idol-script-registry.yaml\nregistry script_entries is missing or invalid."]
  end

  scripts_dir = resolve_path("scripts")
  return ["fail", "scripts/ directory is not readable."] unless scripts_dir && Dir.exist?(scripts_dir.to_s)

  run_path_pattern = %r{(?:runs/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9가-힣][a-z0-9가-힣-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}|runs/[0-9]{4}-[0-9]{2}-[0-9]{2}/[A-Z0-9][A-Z0-9_-]+)}
  run_token_pattern = /\b(?:0526_SONG_SELECTION|0611_WORLD_CUP_PULSO|AURORA_M_FULL_CODE_ROOT_SIGNAL|UNNAME_SIGNAL_001|LAST_GOODBYE_MESSAGE)\b/
  one_off_pattern = /\b(?:one-off|source-first edit alignment draft for LOW|WORLD_CUP_PULSO-only)\b/i
  entries = registry.fetch("script_entries")
  one_off_registry = entries.select { |entry| entry.is_a?(Hash) && entry["status"] == "one_off" }.filter_map { |entry| entry["path"] }
  compatibility_registry = entries.select { |entry| entry.is_a?(Hash) && entry["status"] == "compatibility" }.filter_map { |entry| entry["path"] }
  classified_registry = (one_off_registry + compatibility_registry).map { |path| File.basename(path) }.uniq
  detected_run_paths = []
  unclassified_run_paths = []
  detected_one_offs = []
  unclassified_one_offs = []

  Dir.glob((scripts_dir + "*").to_s).sort.each do |path|
    next unless File.file?(path)

    basename = File.basename(path)
    next if %w[README.md INDEX.md].include?(basename)
    next if basename == File.basename(__FILE__)

    text = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
    has_run_path = text.match?(run_path_pattern) || text.match?(run_token_pattern)
    is_one_off = text.match?(one_off_pattern)

    if has_run_path
      detected_run_paths << basename
      unclassified_run_paths << basename unless classified_registry.include?(basename)
    end

    if is_one_off
      detected_one_offs << basename
      unclassified_one_offs << basename unless one_off_registry.include?(basename)
    end
  end

  details = [
    "policy_source: automation/idol-script-registry.yaml",
    "creative_interpretation_evaluated: false",
    "known_one_off_helpers: #{one_off_registry.sort.join(', ')}",
    "known_compatibility_default_scripts: #{compatibility_registry.sort.join(', ')}",
    "detected_run_path_scripts: #{detected_run_paths.length}",
    "detected_run_paths: #{detected_run_paths.sort.join(', ')}",
    "detected_one_off_scripts: #{detected_one_offs.length}",
    "detected_one_offs: #{detected_one_offs.sort.join(', ')}"
  ]

  unless unclassified_run_paths.empty? && unclassified_one_offs.empty?
    details << "unclassified_run_path_scripts: #{unclassified_run_paths.sort.join(', ')}" unless unclassified_run_paths.empty?
    details << "unclassified_one_off_scripts: #{unclassified_one_offs.sort.join(', ')}" unless unclassified_one_offs.empty?
    return ["fail", details.join("\n")]
  end

  ["pass", details.join("\n")]
end

def python_video_runtime_isolation_status
  command = ["scripts/idol-video-python", "--check"]
  stdout, stderr, exit_status = capture_command(command)
  text = [stdout, stderr].join("\n")
  video_python = text[/^python:\s*(.+)$/, 1].to_s.strip
  video_version = text[/^version:\s*(\S+)$/, 1].to_s.strip
  system_python = nil
  system_version = nil
  system_differs = nil
  required_missing = []
  pin_mismatches = []
  in_required = false
  in_requirements_pins = false

  text.each_line do |line|
    stripped = line.strip
    if stripped == "system_python:"
      system_python = ""
      next
    end

    if !system_python.nil? && stripped.start_with?("executable:")
      system_python = stripped.sub(/\Aexecutable:\s*/, "")
      next
    end

    if !system_python.nil? && stripped.start_with?("version:")
      system_version = stripped.sub(/\Aversion:\s*/, "")
      next
    end

    if !system_python.nil? && stripped.start_with?("differs_from_video_runtime:")
      system_differs = stripped.sub(/\Adiffers_from_video_runtime:\s*/, "")
      next
    end

    in_required = true if stripped == "required:"
    in_required = false if stripped == "extended installed analysis:"
    in_requirements_pins = true if stripped == "requirements pins:"
    in_requirements_pins = false if stripped == "extended installed analysis:"
    required_missing << stripped.sub(/:\s*MISSING\z/, "") if in_required && stripped.match?(/:\s*MISSING\z/)
    pin_mismatches << stripped if in_requirements_pins && stripped.include?(" MISMATCH")
  end

  issues = []
  issues << "`scripts/idol-video-python --check` exited #{exit_status}" unless exit_status.zero?
  issues << "video runtime did not report a Python executable" if blank?(video_python)
  issues << "video runtime is not `.venv-video/bin/python`: #{video_python}" unless video_python.include?("/.venv-video/bin/python")
  issues << "video runtime did not report a Python version" if blank?(video_version)
  issues << "missing required modules: #{required_missing.join(', ')}" unless required_missing.empty?
  issues << "requirements pin mismatches: #{pin_mismatches.join('; ')}" unless pin_mismatches.empty?

  details = [
    "command: #{command_label(command)}",
    "exit_status: #{exit_status}",
    "video_python: #{video_python}",
    "video_version: #{video_version}",
    "system_python: #{system_python || 'unknown'}",
    "system_version: #{system_version || 'unknown'}",
    "system_differs_from_video_runtime: #{system_differs || 'unknown'}",
    "required_missing: #{required_missing.empty? ? 'none' : required_missing.join(', ')}",
    "requirements_pin_mismatches: #{pin_mismatches.empty? ? 'none' : pin_mismatches.join('; ')}",
    "policy: media/audio/video/schema Python work must use scripts/idol-video-python, not bare python3."
  ]
  details << "issues: #{issues.join('; ')}" unless issues.empty?

  [issues.empty? ? "pass" : "fail", details.join("\n")]
end

def grok_drive_write_guard_status
  guard_specs = [
    {
      path: "scripts/idol_asset_drive_sync.py",
      option: /--founder-requested/,
      guard: /write and not founder_requested|args\.write and not args\.founder_requested/
    },
    {
      path: "scripts/idol_grok_imagine_drive_sync.py",
      option: /--founder-requested/,
      guard: /args\.write and not args\.founder_requested/
    },
    {
      path: "scripts/idol_video_prompt_drive_sync.rb",
      option: /--founder-requested/,
      guard: /options\[:write\]\s*&&\s*!options\[:founder_requested\]/
    },
    {
      path: "scripts/idol_prepare_grok_video_prompt_handoff.rb",
      option: /--founder-requested/,
      guard: /options\[:write\]\s*&&\s*!options\[:founder_requested\]|unless\s+options\[:founder_requested\]/
    },
    {
      path: "scripts/idol_founder_pass_harness.rb",
      option: /--founder-requested/,
      guard: /options\[:write\]\s*&&\s*options\[:sync_grok_imagine\]\s*&&\s*!options\[:founder_requested\]/
    }
  ]

  issues = []
  details = ["guard_policy: Drive/Grok handoff writes require --founder-requested; dry checks may run without it."]
  guard_specs.each do |spec|
    path = spec[:path]
    resolved = resolve_path(path)
    unless resolved && File.file?(resolved.to_s)
      issues << "#{path}: script is missing"
      next
    end

    text = File.read(resolved.to_s, encoding: "UTF-8", invalid: :replace, undef: :replace)
    has_option = text.match?(spec[:option])
    has_guard = text.match?(spec[:guard])
    details << "#{path}: option=#{has_option} guard=#{has_guard}"
    issues << "#{path}: missing --founder-requested option" unless has_option
    issues << "#{path}: missing write guard tied to founder_requested" unless has_guard
  end

  if issues.empty?
    ["pass", details.join("\n")]
  else
    ["fail", (issues + details).join("\n")]
  end
end

def album_reference_index_pointer_status(index_path)
  index = load_yaml(index_path)
  items = Array(index["items"]).select { |item| item.is_a?(Hash) }
  owner_prefixes = {
    "runs" => "runs/",
    "source-materials" => "source-materials/",
    "assets/members/album-assets" => "assets/members/album-assets/"
  }
  active_statuses = %w[working selected founder_locked asset_promoted]
  prefix_errors = []
  catalog_canonical_paths = []
  missing_active_paths = []
  active_checked = 0

  items.each do |item|
    item_id = item["item_id"].to_s
    owner_layer = item["owner_layer"].to_s
    canonical_path = item["canonical_path"].to_s
    expected_prefix = owner_prefixes[owner_layer]

    if expected_prefix && !canonical_path.start_with?(expected_prefix)
      prefix_errors << "#{item_id}: owner_layer=#{owner_layer} canonical_path=#{canonical_path}"
    end

    catalog_canonical_paths << "#{item_id}: #{canonical_path}" if canonical_path.start_with?("catalog/albums/")

    next unless active_statuses.include?(item["status"].to_s)

    active_checked += 1
    missing_active_paths << "#{item_id}: #{canonical_path}" unless readable_path?(canonical_path)
  end

  details = [
    "items: #{items.length}",
    "catalog_is_pointer_only: #{index.dig('storage_policy', 'catalog_is_pointer_only')}",
    "active_pointer_paths_checked: #{active_checked}",
    "owner_layer_prefix_errors: #{prefix_errors.length}",
    "catalog_canonical_paths: #{catalog_canonical_paths.length}",
    "missing_active_pointer_paths: #{missing_active_paths.length}"
  ]
  issues = []
  issues << "owner_layer/canonical_path prefix mismatch: #{prefix_errors.first(8).join('; ')}" unless prefix_errors.empty?
  issues << "reference/contact canonical_path must not live under catalog/albums: #{catalog_canonical_paths.first(8).join('; ')}" unless catalog_canonical_paths.empty?
  issues << "active pointer canonical_path is missing locally: #{missing_active_paths.first(8).join('; ')}" unless missing_active_paths.empty?

  if issues.empty?
    ["pass", details.join("\n")]
  else
    ["fail", (issues + details).join("\n")]
  end
end

def catalog_pointer_only_status(title_root)
  title_path = resolve_path(title_root)
  return ["fail", "Catalog title root is not readable: #{title_root}"] unless title_path && Dir.exist?(title_path.to_s)

  media_extensions = %w[
    .aif .aiff .avi .flac .gif .jpeg .jpg .m4a .m4v .mkv .mov .mp3 .mp4
    .png .psd .tar .tgz .tif .tiff .wav .webm .webp .zip
  ]
  scanned = 0
  media_files = []

  Dir.glob((title_path + "**/*").to_s).sort.each do |path|
    next unless File.file?(path)

    scanned += 1
    ext = File.extname(path).downcase
    next unless media_extensions.include?(ext)

    media_files << rel_path(path)
  end

  details = [
    "catalog_title_root: #{title_root}",
    "catalog_files_scanned: #{scanned}",
    "media_files_in_catalog: #{media_files.length}"
  ]
  return ["pass", details.join("\n")] if media_files.empty?

  ["fail", (["Catalog title root contains media/archive files; keep large originals in runs/source-materials/assets owners: #{media_files.first(12).join(', ')}"] + details).join("\n")]
end

def infer_context_from_hermes(run_rel)
  sprint_path = "automation/hermes/current-sprint.yaml"
  sprint = load_yaml(sprint_path)
  context = sprint.fetch("active_context", {})
  return {} unless context.is_a?(Hash)
  return {} unless context["active_run"].to_s == run_rel

  {
    "album_key" => context["album_key"],
    "title_key" => context["title_key"],
    "observed_status" => context["observed_status"],
    "source" => sprint_path
  }
end

def video_prompt_count(manifest_path)
  manifest = load_yaml(manifest_path)
  cues = manifest["cues"]
  cues.is_a?(Array) ? cues.length : nil
end

def edit_map_readiness(edit_map_path)
  edit_map = load_yaml(edit_map_path)
  issues = []

  status_text = edit_map["status"].to_s
  if status_text.match?(EDIT_REJECT_STATUS_PATTERN)
    issues << "top-level edit status is not final-ready: #{status_text}"
  end

  manual = edit_map["manual_adjustment_workflow"]
  if manual.is_a?(Hash)
    current_final_recipe = manual["current_final_recipe"]
    if blank?(current_final_recipe)
      issues << "manual_adjustment_workflow.current_final_recipe is blank; no final edit recipe is locked."
    elsif !readable_file?(current_final_recipe)
      issues << "manual_adjustment_workflow.current_final_recipe is not readable: #{current_final_recipe}"
    end

    active_candidate_status = manual["active_candidate_status"].to_s
    if active_candidate_status.match?(EDIT_REVIEW_STATUS_PATTERN)
      issues << "active edit candidate still needs review or is held: #{active_candidate_status}"
    end
  else
    issues << "manual_adjustment_workflow is missing or not a mapping."
  end

  shards = edit_map.dig("section_workflow", "shards")
  if shards.is_a?(Array)
    nonready = shards.map do |shard|
      next unless shard.is_a?(Hash)

      shard_status = shard["status"].to_s
      next if %w[ready_for_merge merged].include?(shard_status)

      "#{shard['shard_id']}:#{shard_status}"
    end.compact
    issues << "section_workflow has non-ready shard status(es): #{nonready.first(8).join(', ')}" unless nonready.empty?
  end

  rough_outputs = edit_map["rough_outputs"]
  if rough_outputs.is_a?(Array)
    current_candidates = rough_outputs.map do |output|
      next unless output.is_a?(Hash)

      output_status = output["status"].to_s
      next unless output_status.match?(EDIT_REVIEW_STATUS_PATTERN) || output_status.match?(EDIT_REJECT_STATUS_PATTERN)

      "#{output['output_id']}:#{output_status}"
    end.compact
    issues << "rough_outputs still include review/rejected/timing-test candidates: #{current_candidates.first(8).join(', ')}" unless current_candidates.empty?
  end

  if issues.empty?
    ["pass", "Edit map has a readable locked final recipe and no non-ready shard/candidate status detected."]
  else
    ["fail", issues.join("\n")]
  end
end

def drift_notes(checks, hermes_context, manifest_path)
  observed = hermes_context["observed_status"]
  return [] unless observed.is_a?(Hash)

  by_id = checks.to_h { |check| [check.id, check] }
  notes = []

  video_status = observed["video_prompt_manifest"].to_s
  if video_status.match?(/\bready|pass|complete/i) && by_id["video_prompt_manifest"]&.status == "fail"
    notes << "Hermes says video_prompt_manifest=#{video_status.inspect}, but the active 03V manifest validator fails."
  end

  qa_status = observed["section_qa"].to_s
  if qa_status.match?(/\bpass|ready|complete/i)
    qa_check = by_id["video_prompt_section_qa_readiness"] || by_id["video_prompt_manifest"]
    section_schema = by_id["video_prompt_section_qa_schema"]
    if qa_check&.status == "fail" || section_schema&.status == "fail"
      notes << "Hermes says section_qa=#{qa_status.inspect}, but current section QA validation is not clean."
    end
  end

  expected_prompt_count = observed["prompt_count"]
  actual_prompt_count = readable_file?(manifest_path) ? video_prompt_count(manifest_path) : nil
  if expected_prompt_count && actual_prompt_count && expected_prompt_count.to_i != actual_prompt_count
    notes << "Hermes prompt_count=#{expected_prompt_count.inspect}, but the active 03V manifest has #{actual_prompt_count} cue record(s)."
  end

  notes
end

def active_handoff_run
  path = "handoff/grok/current.md"
  resolved = resolve_path(path)
  return nil unless resolved && File.file?(resolved.to_s)

  text = File.read(resolved.to_s, encoding: "utf-8")
  active_block = text.match(/## Active Run\s+```text\s+([^`]+?)\s+```/m)
  return normalize_run_pointer(active_block[1]) if active_block

  text.match(%r{(?:runs/[a-z0-9][a-z0-9-]{1,120}/[a-z0-9가-힣][a-z0-9가-힣-]{1,120}/[A-Za-z0-9][A-Za-z0-9._-]{2,120}|runs/2026-07-29/0729_ONE_MOVE)})&.[](0)
end

def current_next_run
  current_next = load_yaml("automation/current-next.yaml")
  normalize_run_pointer(current_next["run"])
end

def downstream_upstream_reference_issues(run_path)
  artifact = run_path + "01-song-choreography-performance-mv-map.yaml"
  return [] unless File.file?(artifact.to_s)

  document = load_yaml(artifact)
  slices = Array(document.dig("section_gate", "slices")).select { |row| row.is_a?(Hash) }
  slices.map do |slice|
    matches = Array(slice["upstream_refs"]).select do |reference|
      text = reference.to_s.downcase
      text.include?("/02a-") || text.include?("/02b-") || text.include?("/03v-") ||
        text.include?("/04-") || text.include?("/review/02b") || text.include?("generated_board_review")
    end
    next if matches.empty?

    samples = matches.first(2).map { |reference| File.basename(reference.to_s) }.join(",")
    "#{slice['section_id']}: #{matches.length} downstream-shaped reference(s) stored in upstream_refs; sample=#{samples}"
  end.compact
end

def independent_readiness_axes(run_path:, run_rel:, checks:, drifts:)
  current_context = current_context_for_run(run_path)
  current_next = current_context ? current_context["document"] : load_yaml("automation/current-next.yaml")
  selection = current_context ? current_context["selection"] : {}
  current_run_matches = normalize_run_pointer(current_next["run"]) == normalize_run_pointer(run_rel)
  selected_status = [current_next["status"], selection["kind"], selection["state"]].compact.join(" ").downcase
  explicit_ready = selection["kind"].to_s == "next_action" && current_next["status"].to_s == "ready"

  contract_failures = checks.select do |check|
    check.blocking == true && check.status != "pass"
  end
  schema_valid = contract_failures.empty?

  revision_issues = Array(drifts) + downstream_upstream_reference_issues(run_path)
  all_revision_contracts = Dir.glob(run_path.join("work", "**", "*.{yaml,yml,json}").to_s).map do |path|
    begin
      document = load_yaml(path)
      path if document["schema_version"].to_s == "idol-harness-artifact-envelope.v1"
    rescue StandardError
      nil
    end
  end.compact
  revision_contracts = active_revision_contracts(run_path, all_revision_contracts)
  revision_verified = revision_contracts.empty? || revision_contracts.all? do |path|
    document = load_yaml(path)
    document.dig("envelope", "readiness", "revision_coherent") == true
  end
  revision_coherent = if revision_issues.any?
                        false
                      elsif revision_verified
                        true
                      else
                        nil
                      end

  expert_check = checks.find { |check| check.id.to_s == "conditional_expert_quality_gates" }
  expert_status = expert_check&.details.to_s[/"overall_status"\s*:\s*"([a-z_]+)"/, 1].to_s
  expert_clear = %w[pass not_applicable].include?(expert_status)

  founder_pending = current_run_matches && current_next["owner"].to_s.downcase.include?("founder")
  founder_gate = founder_pending ? "pending" : "not_applicable"

  stage_ready = current_run_matches && explicit_ready && schema_valid && revision_coherent == true && expert_clear && founder_gate != "pending"
  next_unit_resumable = stage_ready && selection["kind"].to_s == "next_action"

  {
    schema_valid: schema_valid,
    revision_coherent: revision_coherent,
    stage_ready: stage_ready,
    founder_gate: founder_gate,
    next_unit_resumable: next_unit_resumable,
    basis: {
      schema_valid: ["blocking_schema_or_semantic_failures=#{contract_failures.map(&:id).join(',')}"],
      revision_coherent: revision_issues.empty? ? ["active_revision_contract_count=#{revision_contracts.length}", "historical_revision_contract_count=#{all_revision_contracts.length - revision_contracts.length}", "revision_verified=#{revision_verified}"] : revision_issues,
      stage_ready: ["current_run_matches=#{current_run_matches}", "ddi_selection_status=#{selected_status}", "explicit_ready=#{explicit_ready}", "expert_quality_status=#{expert_status.empty? ? 'unknown' : expert_status}"],
      founder_gate: ["ddi_selection_owner=#{current_next['owner']}", "founder_pending=#{founder_pending}"],
      next_unit_resumable: ["stage_ready=#{stage_ready}", "ddi_selection_kind=#{selection['kind']}"]
    }
  }
end

def pointer_drift_notes(run_rel)
  notes = []
  handoff_run = active_handoff_run
  next_run = current_next_run

  if !blank?(handoff_run) && !blank?(next_run) && handoff_run != next_run
    notes << "Active handoff run=#{handoff_run.inspect}, but automation/current-next.yaml run=#{next_run.inspect}."
  end
  if !blank?(handoff_run) && handoff_run != run_rel
    notes << "This state check is for #{run_rel.inspect}, while the active handoff points to #{handoff_run.inspect}."
  end
  if !blank?(next_run) && next_run != run_rel
    notes << "This state check is for #{run_rel.inspect}, while automation/current-next.yaml points to #{next_run.inspect}."
  end

  notes
end

def status_counts(checks)
  checks.each_with_object(Hash.new(0)) { |check, counts| counts[check.status] += 1 }
end

def overall_status(checks)
  blocking = checks.select(&:blocking)
  return "validator_pass" if blocking.empty?
  return "blocked_by_missing_required_artifacts" if blocking.any? { |check| check.status == "missing" } &&
                                                    blocking.none? { |check| check.status == "fail" }

  "blocked_by_validator_failures"
end

def next_action_for(check)
  case check.id
  when "skill_path_contracts"
    "Repair skill Required Reads or Read/Write Contract blocks and any unreadable referenced paths before trusting skill routing."
  when "skill_purpose_contract_matrix"
    "Repair missing purpose-specific skill contracts: core skills need Required Reads, AGENTS/wiki routing, schema references, and explicit output/write boundaries."
  when "script_policy_run_path_registry"
    "Declare top-level scripts with hard-coded run paths in `automation/idol-script-registry.yaml`, move them under the owning run, or refactor them into run-agnostic helpers."
  when "python_video_runtime_isolation"
    "Run `scripts/idol-video-python --check`, restore `.venv-video` if needed, and keep media/audio/video/schema Python work on the launcher instead of bare `python3` after system Python upgrades."
  when "grok_drive_write_guards"
    "Restore `--founder-requested` write guards on Drive/Grok handoff mirror scripts. Dry checks may run freely, but scripts that write under drive-sync or prepare Grok handoff packets must require explicit founder-requested confirmation."
  when "title_reference_pointer_integrity", "title_contact_sheet_pointer_integrity"
    "Repair the title reference/contact-sheet index so `owner_layer` matches the `canonical_path` owner prefix, active pointers resolve locally, and catalog keeps pointer rows instead of canonical media files."
  when "title_catalog_pointer_only"
    "Move media/archive files out of the catalog title root into the owning run, source-materials, or assets/members/album-assets location, then leave compact pointer rows in the title index."
  when "title_output_registry_schema"
    "Repair the title output registry structure against `schemas/title-output-registry.schema.json`; keep run-specific status/source-step labels as strings and leave semantic path/current-pointer checks to the registry validator."
  when "title_output_registry"
    "Repair title output registry semantic issues: non-declared output rows must point to readable files, latest_pointers must match registered existing artifacts, and declared future outputs must not be promoted as latest pointers."
  when "video_prompt_section_qa_readiness"
    "Complete section QA through actual source-image/prompt review, clip-duration music fit, motion/camera fit, story-spine, person-only risk, and playback probe before changing section QA statuses to `pass`. Use the run-owned `review/03v-section-video-prompt-qa-worklist-v*.md` when present."
  when "edit_map_readiness"
    "Do not promote the edit. Lock a readable final recipe only after failed shards are rebuilt or retired, review-needed candidates receive founder/playback decisions, and source-action/audio-marker alignment passes. Use the run-owned `review/04-edit-readiness-worklist-v*.md` when present."
  when "package_final_lineage"
    "Do not project or release the package. Revalidate 04 closeout, the full-master 04FX audit, deterministic compile receipt, complete final-render receipt, and byte-identical hash-bound final_master with `scripts/validate_package_readiness.py`."
  when "edit_readiness_worklist"
    "Generate or refresh the run-owned 04 edit readiness worklist before handing the blocker to automation: `ruby scripts/idol_edit_readiness_worklist.rb RUN_ROOT --write`."
  when "video_prompt_section_qa_worklist"
    "Generate or refresh the run-owned 03V section QA worklist before handing the blocker to automation: `ruby scripts/idol_video_prompt_section_qa_worklist.rb RUN_ROOT --write`."
  when "front_planning_readiness_schema"
    "Repair the run-owned `research/front-planning-readiness-v*.yaml` against `schemas/front-planning-readiness.schema.json` before trusting the front-planning handoff."
  when "front_planning_readiness_refs"
    "Repair Front Planning v17 source paths/hashes, selected-route storyline binding, current-title assets, A/B/C route, Major Scene, screen-progression, and section assignments; close named evidence gaps with decision-ready actual units and preserve at least one applied or combined exact-five ordered consecutive one-second Sequence Unit per active visual section. No fixed unit/source/function count grants or blocks creative adequacy. Structural success does not replace Director or Founder creative judgment."
  when "front_planning_interpretation_receipts"
    "Repair the Front Planning interpretation receipt pointer/value hashes, inspected-source hashes, selected cell/crop locators, or revision/invalidation evidence. A later session may consume the receipt but may not silently reread the whole source."
  when "front_planning_transfer_gate_shape"
    "Patch current 01/02A source bindings so deep Front Planning sources move through section-level direction and 02A Core-Cut/Branch-Cut refs. This check is structural only; Codex/Founder still own the creative interpretation."
  when "front_planning_department_dispatch"
    "Launch one Front Planning department dispatch under `RUN/work/department-dispatches/TASK_ID.yaml`; the runtime must enforce the exact skill and required EOF reads, return the current readiness bytes, and receive director review plus promotion before the gate clears."
  when "stage_department_dispatch"
    "For the current or materially resumed Front Planning-through-02A stage, launch the exact bounded department dispatch, record runtime-enforced skill/source revisions and input/result digests, then bind the returned output bytes through director review and promotion. Legacy skill-application receipts remain evidence only."
  when "run_owned_canonical_creative_mutators"
    "Retire canonical-write and creative-verdict authority from run-owned repair/materializer helpers. Run `ruby scripts/idol_creative_truth_guard.rb RUN_ROOT --json`; keep only schema-repair candidates governed by `schemas/schema-repair-candidate.schema.json` under `work/`, and return canonical authorship to the owning human/model stage."
  when "harness_execution_contract", "harness_skill_load_profiles", "harness_skill_load_profiles_semantics", "harness_contract_version_registry", "harness_contract_version_registry_semantics"
    "Repair the active execution, skill-load, or version-routing contract against its schema and exact current path hashes before routing another stage."
  when "active_section_owner_coverage"
    "Make 01 and 02A exact-cover the ordered Front Planning v17 sections, selected A/B/C route and its hash-bound active storyline, Major Scenes, screen-progression nodes, and Founder-passed reference bindings. Keep each reference unit, current-title asset, and section owner in its active owning artifact; scripts may check coverage but cannot choose the creative route."
  when "direction_section_contract"
    "Repair 01 against the active 3.0 direction validator so every section exactly projects the passed Front Planning target, selected route, screen progression, Major Scene and reference bindings, and each Official Core owns exactly one passed primary image."
  when "master_storyboard"
    "Repair 02A against the active 3.0 storyboard validator so it exact-imports the immutable 01 Official-Core head, preserves the complete PRE-00-rooted storyline and screen-progression lineage, and authors only uncapped 1..N Branch Cuts beneath each Core."
  when "planning_video_edit_trace"
    "Patch 02A Official-Core/Branch-Cut action and still-camera fields, current 03V v7 Production-Cut source/continuity/edit handoff, and 04 v4 Edit-Slot screen-progression lineage so source action, camera route, story flow, and directorial transition intent remain traceable. This check is structural only; do not automate the creative interpretation."
  when "video_prompt_manifest"
    "Repair the 03V manifest against `schemas/video-prompt-manifest.schema.json`, including source_production_cut_images, previous_next_continuity, and edit_handoff, before 04 readiness."
  when "generated_board_review"
    "Repair the generated-board review record against `schemas/review.schema.json`; only founder-passed records may enter video prompt authoring."
  else
    if check.status == "missing"
      "Create or locate the required artifact, then rerun the state checker."
    else
      "Inspect the failed command output, repair the owning artifact, and rerun the state checker."
    end
  end
end

def markdown_report(run_rel:, album_key:, title_key:, generated_at:, checks:, hermes_context:, drifts:)
  counts = status_counts(checks)
  status = overall_status(checks)
  blocking = checks.select(&:blocking)

  lines = []
  lines << "# IDOL Graph Engineering State Report"
  lines << ""
  lines << "generated_at: #{generated_at}"
  lines << "run: `#{run_rel}`"
  lines << "album_key: `#{album_key || 'unknown'}`"
  lines << "title_key: `#{title_key || 'unknown'}`"
  lines << "overall_status: `#{status}`"
  lines << ""
  lines << "## Summary"
  lines << ""
  lines << "- pass: #{counts['pass']}"
  lines << "- pending: #{counts['pending']}"
  lines << "- fail: #{counts['fail']}"
  lines << "- missing: #{counts['missing']}"
  lines << "- blocking: #{blocking.length}"
  lines << ""
  lines << "## Gate Verdict"
  lines << ""
  if blocking.empty?
    lines << "- Canonical Graph Engineering readiness is clean for the checks this tool knows how to run."
  else
    lines << "- Canonical Graph Engineering readiness is blocked by current local evidence."
    blocking.first(10).each do |check|
      lines << "- `#{check.id}`: #{check.status} - #{check.label}"
    end
    lines << "- ... #{blocking.length - 10} more blocking check(s)" if blocking.length > 10
  end
  lines << ""
  unless blocking.empty?
    lines << "## Next Actions"
    lines << ""
    blocking.each do |check|
      lines << "- `#{check.id}`: #{next_action_for(check)}"
    end
    lines << ""
  end
  lines << "## State Pointer Drift"
  lines << ""
  if hermes_context["source"]
    lines << "- compared_against: `#{hermes_context['source']}`, `automation/current-next.yaml`, `handoff/grok/current.md`"
  else
    lines << "- compared_against: `automation/current-next.yaml`, `handoff/grok/current.md`"
  end
  if drifts.empty?
    lines << "- No state pointer drift detected by this checker."
  else
    drifts.each { |note| lines << "- #{note}" }
  end
  lines << ""
  lines << "## Checks"
  lines << ""
  lines << "| group | id | status | blocking | artifact |"
  lines << "| --- | --- | --- | --- | --- |"
  checks.each do |check|
    lines << "| #{check.group} | `#{check.id}` | #{check.status} | #{check.blocking ? 'yes' : 'no'} | `#{check.artifact}` |"
  end
  lines << ""

  failed = checks.select { |check| %w[fail missing].include?(check.status) && !blank?(check.details) }
  unless failed.empty?
    lines << "## Failed Or Missing Details"
    lines << ""
    failed.each do |check|
      lines << "### #{check.id}"
      lines << ""
      lines << "- label: #{check.label}"
      lines << "- artifact: `#{check.artifact}`"
      lines << "- status: `#{check.status}`"
      lines << "- blocking: `#{check.blocking}`"
      lines << "- exit_status: `#{check.exit_status}`" unless check.exit_status.nil?
      lines << "- command: `#{check.command}`" unless blank?(check.command)
      lines << ""
      lines << "```text"
      lines << check.details
      lines << "```"
      lines << ""
    end
  end

  lines.join("\n")
end

options = {
  album_key: nil,
  title_key: nil,
  report: nil,
  write_report: false,
  json: false
}

OptionParser.new do |parser|
  parser.on("--album-key KEY") { |value| options[:album_key] = value }
  parser.on("--title-key KEY") { |value| options[:title_key] = value }
  parser.on("--report PATH") { |value| options[:report] = value }
  parser.on("--write-report") { options[:write_report] = true }
  parser.on("--json") { options[:json] = true }
end.parse!

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg)

run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path && Dir.exist?(run_path.to_s)
layout_repo_root = run_layout_repo_root(run_path)
layout_errors = IdolRunLayout.validate(run_path, repo_root: layout_repo_root)
usage_error(layout_errors.join("; ")) unless layout_errors.empty?
run_identity = IdolRunLayout.identity(run_path, repo_root: layout_repo_root)

run_rel = rel_path(run_path)
content_id = run_identity.fetch("content_id")
hermes_context = infer_context_from_hermes(run_rel)
album_key = options[:album_key] || run_identity["album_key"]
title_key = options[:title_key] || run_identity["title_key"]
usage_error("--album-key differs from the resolved run identity") if options[:album_key] && options[:album_key] != run_identity["album_key"]
usage_error("--title-key differs from the resolved run identity") if options[:title_key] && options[:title_key] != run_identity["title_key"]

checks = []

add_command_check(
  checks,
  id: "stage_registry_schema",
  group: "harness",
  label: "semantic stage registry schema",
  artifact: "automation/harness-stage-registry.yaml",
  command: ["scripts/idol-video-python", "scripts/validate_json_schema.py", "schemas/harness-stage-registry.schema.json", "automation/harness-stage-registry.yaml"]
)

add_command_check(
  checks,
  id: "stage_registry_semantics",
  group: "harness",
  label: "semantic stage registry aliases and ownership",
  artifact: "automation/harness-stage-registry.yaml",
  command: ["ruby", "scripts/idol_harness_stage.rb", "validate"]
)

add_command_check(
  checks,
  id: "artifact_routing_semantics",
  group: "harness",
  label: "album-run artifact routing exact-covers active stage owners",
  artifact: "automation/harness-artifact-routing.yaml",
  command: ["ruby", "scripts/validate_harness_artifact_routing.rb"]
)

add_schema_check(
  checks,
  id: "harness_execution_contract",
  group: "harness",
  label: "active Graph Engineering execution prompt contract",
  schema: "schemas/harness-execution-contract.schema.json",
  artifact: "automation/harness-execution-contract.yaml",
  required: true
)

add_schema_check(
  checks,
  id: "harness_skill_load_profiles",
  group: "harness",
  label: "provider-neutral exact-path skill-load profiles",
  schema: "schemas/harness-skill-load-profiles.schema.json",
  artifact: "automation/harness-skill-load-profiles.yaml",
  required: true
)

add_command_check(
  checks,
  id: "harness_skill_load_profiles_semantics",
  group: "harness",
  label: "skill/read hashes, startup admission, stages, roles, and return routes match active v21",
  artifact: "automation/harness-skill-load-profiles.yaml",
  command: ["ruby", "scripts/validate_harness_skill_load_profiles.rb"]
)

add_schema_check(
  checks,
  id: "harness_contract_version_registry",
  group: "harness",
  label: "current contract version routing registry",
  schema: "schemas/harness-contract-version-registry.schema.json",
  artifact: "automation/harness-contract-version-registry.yaml",
  required: true
)

add_command_check(
  checks,
  id: "harness_contract_version_registry_semantics",
  group: "harness",
  label: "current/readable contract versions match owning schemas",
  artifact: "automation/harness-contract-version-registry.yaml",
  command: ["ruby", "scripts/validate_harness_contract_version_registry.rb"]
)

add_command_check(
  checks,
  id: "harness_surface_version_registry_semantics",
  group: "harness",
  label: "tracked Graph Engineering surface revisions and hashes match current bytes",
  artifact: "automation/harness-surface-version-registry.yaml",
  command: ["ruby", "scripts/validate_harness_surface_version_registry.rb"]
)

add_command_check(
  checks,
  id: "video_source_analysis_registry",
  group: "harness",
  label: "local source-owned video analysis registry and READ-FIRST projection",
  artifact: "source-materials/video-sources/reference-analysis-registry.yaml",
  command: ["scripts/idol-video-python", "scripts/idol_video_reference_analysis_registry.py", "verify"]
)

add_command_check(
  checks,
  id: "conditional_expert_quality_gates",
  group: "harness",
  label: "conditional professional craft/readiness gates",
  artifact: "scripts/idol_harness_expert_gate.rb",
  command: ["ruby", "scripts/idol_harness_expert_gate.rb", run_rel, "--json"],
  blocking_on_fail: false
)
expert_check = checks.last
expert_report_status = expert_check.details.to_s[/"overall_status"\s*:\s*"([a-z_]+)"/, 1].to_s
if %w[pass pending fail].include?(expert_report_status)
  expert_check.status = expert_report_status
  expert_check.blocking = expert_report_status == "fail"
end

add_command_check(
  checks,
  id: "skill_path_contracts",
  group: "harness",
  label: "skill read/path contract validator",
  artifact: "scripts/idol_skill_contract_check.rb",
  command: ["ruby", "scripts/idol_skill_contract_check.rb"]
)

add_command_check(
  checks,
  id: "skill_purpose_contract_matrix",
  group: "harness",
  label: "skill purpose/read-write contract matrix",
  artifact: "scripts/idol_skill_contract_matrix.rb",
  command: ["ruby", "scripts/idol_skill_contract_matrix.rb", "--strict"]
)

add_command_check(
  checks,
  id: "script_registry",
  group: "harness",
  label: "script registry matches current files",
  artifact: "scripts/idol_script_registry_check.rb",
  command: ["ruby", "scripts/idol_script_registry_check.rb"]
)

add_revision_contract_set_check(checks, run_path)

add_internal_check(
  checks,
  id: "stage_department_dispatch",
  group: "harness",
  label: "runtime-enforced department dispatch and director promotion through 02A",
  artifact: "scripts/validate_department_dispatch.rb"
) do
  stage_department_dispatch_status(run_path)
end

add_internal_check(
  checks,
  id: "run_owned_canonical_creative_mutators",
  group: "harness",
  label: "run-owned scripts cannot write canonical creative truth",
  artifact: "scripts/idol_creative_truth_guard.rb"
) do
  run_owned_canonical_creative_mutator_status(run_path)
end

add_internal_check(
  checks,
  id: "founder_intervention_receipts",
  group: "harness",
  label: "Founder interventions are routed, integrated, and revalidated",
  artifact: "schemas/founder-intervention-receipt.schema.json"
) do
  founder_intervention_receipts_status(run_path)
end

add_internal_check(
  checks,
  id: "script_policy_run_path_registry",
  group: "harness",
  label: "script run-path policy registry",
  artifact: "automation/idol-script-registry.yaml",
  blocking_on_fail: false
) do
  script_run_path_registry_status
end

add_internal_check(
  checks,
  id: "python_video_runtime_isolation",
  group: "harness",
  label: "Python media runtime isolation",
  artifact: "scripts/idol-video-python",
  blocking_on_fail: false
) do
  python_video_runtime_isolation_status
end

add_internal_check(
  checks,
  id: "grok_drive_write_guards",
  group: "harness",
  label: "Drive/Grok handoff write guards",
  artifact: "handoff/grok/CONNECTIONS.md"
) do
  grok_drive_write_guard_status
end

core_schemas = [
  ["song_lock", "Song Production Lock [00A]", "schemas/song-lock.schema.json", "00A-song-lock.yaml", true],
  ["mv_director_map", "Section Direction Expansion [01]", "schemas/song-choreography-performance-mv-map.schema.json", "01-song-choreography-performance-mv-map.yaml", true]
]

core_schemas.each do |id, label, schema, filename, required|
  add_schema_check(
    checks,
    id: id,
    group: "core",
    label: label,
    schema: schema,
    artifact: rel_path(run_path + filename),
    required: required
  )
end

master_storyboard_artifact = first_existing(run_path, ["02A-master-storyboard.yaml"])
direction_artifact = first_existing(run_path, ["01-song-choreography-performance-mv-map.yaml"])
prompt_packets_artifact = first_existing(run_path, ["02B-prompt-packets.yaml"])
video_manifest_artifact = latest_match(
  run_path,
  [
    "03V-video-prompt-manifest-v*.yaml",
    "generations/video-prompts/03V-video-prompt-manifest-v*.yaml"
  ]
)
edit_map_artifact = first_existing(run_path, ["04-edit-map.yaml"])
edit_marker_plan_artifact = latest_match(
  run_path,
  [
    "generations/video/qc/edit-marker-plan-v*.yaml",
    "generations/video/qc/sync-workbench-v*/edit-marker-plan-v*.yaml",
    "review/04-edit-marker-plan-v*.yaml",
    "04-edit-marker-plan-v*.yaml"
  ]
)
edit_finishing_fx_artifact = latest_match(run_path, ["generations/video/qc/finishing-fx-v*/04FX-finishing-map-v*.yaml"])
package_artifact = first_existing(run_path, ["05-package.yaml"])
final_edit_claimed = false
package_final_claimed = false
if package_artifact
  package_status = load_yaml(package_artifact)["status"].to_s
  package_final_claimed = %w[
    packaged_ready_local
    ready_for_social_planning
    founder_review
    approved_for_public_release
    final_complete_platform_records_closed
  ].include?(package_status)
  final_edit_claimed ||= package_final_claimed
end
if edit_map_artifact
  edit_map_document = load_yaml(edit_map_artifact)
  final_render_status = edit_map_document.dig("recipe_qc_contract", "final_render_status").to_s
  final_edit_claimed ||= %w[rendered_pending_qc qc_pass].include?(final_render_status)
end
optional_schema_artifacts = [
  ["prompt_packets", "Image Prompt Compile [02B]", "schemas/prompt-packets.schema.json", prompt_packets_artifact],
  ["edit_map", "Edit Assembly Map [04]", "schemas/edit-map.schema.json", edit_map_artifact],
  ["edit_marker_plan", "Edit Marker Plan [04]", "schemas/edit-marker-plan.schema.json", edit_marker_plan_artifact],
  ["package", "Master Package & Release Plan [05]", "schemas/package.schema.json", package_artifact]
]

optional_schema_artifacts.each do |id, label, schema, artifact|
  if artifact
    add_schema_check(checks, id: id, group: "run", label: label, schema: schema, artifact: artifact)
  else
    add_missing_check(checks, id: id, group: "run", label: label, artifact: "(not found)", blocking: false)
  end
end

if master_storyboard_artifact
  add_command_check(
    checks,
    id: "master_storyboard",
    group: "run",
    label: "Coverage, Core Cuts, And Branch Cuts [02A]",
    artifact: master_storyboard_artifact,
    command: ["ruby", "scripts/validate_master_storyboard.rb", master_storyboard_artifact]
  )
else
  add_missing_check(
    checks,
    id: "master_storyboard",
    group: "run",
    label: "Coverage, Core Cuts, And Branch Cuts [02A]",
    artifact: "(not found)",
    blocking: false
  )
end

if prompt_packets_artifact && master_storyboard_artifact
  prompt_packets_status = load_yaml(prompt_packets_artifact)["status"].to_s
  prompt_packets_ready_claimed = prompt_packets_status.match?(/approved|generation_ready|ready_for_|complete/i)
  add_command_check(
    checks,
    id: "prompt_packets_semantic_contract",
    group: "run",
    label: "02B structural lineage, direct-revision, and ownership fidelity",
    artifact: prompt_packets_artifact,
    command: [
      "ruby",
      "scripts/validate_02b_imagegen_contract.rb",
      "--mode", "authoring",
      prompt_packets_artifact
    ],
    blocking_on_fail: prompt_packets_ready_claimed
  )
end

if package_artifact && package_final_claimed
  add_command_check(
    checks,
    id: "package_final_lineage",
    group: "run",
    label: "05 package semantic 04FX-to-final-master lineage",
    artifact: package_artifact,
    command: [
      "scripts/idol-video-python",
      "scripts/validate_package_readiness.py",
      package_artifact
    ]
  )
end

if direction_artifact
  add_command_check(
    checks,
    id: "direction_section_contract",
    group: "run",
    label: "01 section direction and Front Planning projection",
    artifact: direction_artifact,
    command: ["ruby", "scripts/validate_01_section_direction.rb", direction_artifact]
  )
end

if video_manifest_artifact
  add_command_check(
    checks,
    id: "video_prompt_manifest",
    group: "run",
    label: "Motion Direction & Prompting [03V] schema and source freshness",
    artifact: video_manifest_artifact,
    command: ["ruby", "scripts/validate_video_prompt_manifest.rb", video_manifest_artifact]
  )
else
  add_missing_check(
    checks,
    id: "video_prompt_manifest",
    group: "run",
    label: "Motion Direction & Prompting [03V] schema and source freshness",
    artifact: "(not found)",
    blocking: false
  )
end

if edit_finishing_fx_artifact
  add_command_check(
    checks,
    id: "edit_finishing_fx",
    group: "run",
    label: "Edit Finishing FX [04FX] schema and dependency freshness",
    artifact: edit_finishing_fx_artifact,
    command: ["ruby", "scripts/validate_edit_finishing_fx.rb", edit_finishing_fx_artifact]
  )
else
  add_missing_check(
    checks,
    id: "edit_finishing_fx",
    group: "run",
    label: "Edit Finishing FX [04FX] schema and dependency freshness",
    artifact: "(not found)",
    blocking: final_edit_claimed
  )
end

if master_storyboard_artifact
  add_internal_check(
    checks,
    id: "planning_video_edit_trace",
    group: "run",
    label: "02A to 03V/04 planning trace",
    artifact: master_storyboard_artifact,
    blocking_on_fail: false
  ) do
    planning_video_edit_trace_status(
      {
        "02A" => master_storyboard_artifact,
        "03V" => video_manifest_artifact,
        "04" => edit_map_artifact,
        "edit_marker_plan" => edit_marker_plan_artifact
      }
    )
  end
end

if edit_map_artifact
  edit_worklist_yaml = latest_match(run_path, ["review/04-edit-readiness-worklist-v*.yaml"])
  add_command_check(
    checks,
    id: "edit_map_readiness",
    group: "run",
    label: "04 edit map readiness",
    artifact: edit_map_artifact,
    command: final_edit_claimed ?
      ["ruby", "scripts/validate_edit_map_readiness.rb", "--mode", "final-render", edit_map_artifact] :
      ["ruby", "scripts/validate_edit_map_readiness.rb", edit_map_artifact]
  )

  add_worklist_check(
    checks,
    id: "edit_readiness_worklist",
    group: "run",
    label: "04 edit readiness blocker worklist freshness",
    source_artifact: edit_map_artifact,
    worklist_artifact: edit_worklist_yaml || latest_match(run_path, ["review/04-edit-readiness-worklist-v*.md"]),
    generator_command: "ruby scripts/idol_edit_readiness_worklist.rb #{run_rel} --write"
  )
  if edit_worklist_yaml
    add_schema_check(
      checks,
      id: "edit_readiness_worklist_schema",
      group: "run",
      label: "04 edit readiness blocker worklist schema",
      schema: "schemas/harness-blocker-worklist.schema.json",
      artifact: edit_worklist_yaml
    )
  end
end

audio_input_lineage = latest_match(run_path, ["research/audio-input-lineage-v*.yaml", "research/audio-input-lineage-v*.json"], canonical_only: true)
audio_input_lineage_resolution = audio_input_lineage ? resolve_audio_input_lineage(audio_input_lineage) : nil
audio_input_lineage_schema_valid = false
if audio_input_lineage
  audio_schema_check = add_schema_check(
    checks,
    id: "audio_input_lineage_schema",
    group: "research",
    label: "preserved audio input lineage schema",
    schema: "schemas/audio-input-lineage.schema.json",
    artifact: audio_input_lineage,
    required: true
  )
  audio_input_lineage_schema_valid = audio_schema_check&.status == "pass"
  add_internal_check(
    checks,
    id: "audio_input_lineage_integrity",
    group: "research",
    label: "preserved audio input canonical path and SHA-256 integrity",
    artifact: audio_input_lineage,
    blocking_on_fail: true
  ) do
    lineage_errors = Array(audio_input_lineage_resolution["errors"])
    if !audio_input_lineage_schema_valid
      ["fail", "Audio input lineage schema must pass before its pointers can be admitted."]
    elsif lineage_errors.empty?
      resolved = audio_input_lineage_resolution["resolved_inputs"]
      ["pass", "selected_audio_analysis=#{resolved['selected_audio_analysis']}\naudio_motion_director_map=#{resolved['audio_motion_director_map']}\ncreative_inheritance=forbidden"]
    else
      ["fail", lineage_errors.join("\n")]
    end
  end
end

selected_audio = latest_match(run_path, ["research/selected-audio-analysis-v*.yaml", "research/selected-audio-analysis-v*.json"], canonical_only: true)
if selected_audio.nil? && audio_input_lineage_schema_valid && Array(audio_input_lineage_resolution["errors"]).empty?
  selected_audio = audio_input_lineage_resolution.dig("resolved_inputs", "selected_audio_analysis")
end
if selected_audio
  add_schema_check(
    checks,
    id: "selected_audio_schema",
    group: "research",
    label: "selected-audio analysis schema",
    schema: "schemas/selected-audio-analysis.schema.json",
    artifact: selected_audio
  )
  add_command_check(
    checks,
    id: "selected_audio_validator",
    group: "research",
    label: "selected-audio analysis validator",
    artifact: selected_audio,
    command: ["ruby", "scripts/validate_selected_audio_analysis.rb", selected_audio]
  )
else
  add_missing_check(checks, id: "selected_audio", group: "research", label: "selected-audio analysis", artifact: "(not found)", blocking: false)
end

front_planning_downstream_artifacts = [
  first_existing(run_path, ["00A-song-lock.yaml"]),
  first_existing(run_path, ["01-song-choreography-performance-mv-map.yaml"]),
  first_existing(run_path, ["02A-master-storyboard.yaml"]),
  first_existing(run_path, ["02B-prompt-packets.yaml"])
].compact
front_planning_required = front_planning_downstream_artifacts.any? do |artifact|
  document = load_yaml(artifact)
  !document["status"].to_s.match?(/\A(?:rejected|superseded|archive)/i)
end
front_planning_entry_required = front_planning_entry_gate_required_for_run?(run_path)
front_planning_readiness = latest_match(run_path, ["research/front-planning-readiness-v*.yaml", "research/front-planning-readiness-v*.json"], canonical_only: true)
if front_planning_readiness
  add_schema_check(
    checks,
    id: "front_planning_readiness_schema",
    group: "research",
    label: "front-planning readiness schema",
    schema: "schemas/front-planning-readiness.schema.json",
    artifact: front_planning_readiness
  )
  add_command_check(
    checks,
    id: "front_planning_interpretation_receipts",
    group: "research",
    label: "Front Planning reference interpretation receipts",
    artifact: front_planning_readiness,
    command: ["ruby", "scripts/validate_reference_interpretation_contract.rb", "--mode", "owner", front_planning_readiness]
  )
  add_internal_check(
    checks,
    id: "front_planning_readiness_refs",
    group: "research",
    label: "front-planning readiness source refs and anti-bias guard",
    artifact: front_planning_readiness
  ) do
    active_front_planning_readiness_status(load_yaml(front_planning_readiness), run_rel, content_id)
  end
  add_internal_check(
    checks,
    id: "front_planning_transfer_gate_shape",
    group: "research",
    label: "active Front Planning → 01 → 02A path/hash lineage",
    artifact: front_planning_readiness,
    blocking_on_fail: front_planning_required
  ) do
    active_front_planning_transfer_gate_status(
      front_planning_readiness,
      {
        "01" => first_existing(run_path, ["01-song-choreography-performance-mv-map.yaml"]),
        "02A" => first_existing(run_path, ["02A-master-storyboard.yaml"])
      }
    )
  end
  add_internal_check(
    checks,
    id: "front_planning_department_dispatch",
    group: "research",
    label: "active Front Planning department dispatch and director promotion",
    artifact: "scripts/validate_department_dispatch.rb",
    blocking_on_fail: front_planning_entry_required
  ) do
    front_planning_entry_gate_status(run_path, front_planning_readiness)
  end
  add_command_check(
    checks,
    id: "front_planning_readiness_validator",
    group: "research",
    label: "Front Planning readiness validator consume",
    artifact: front_planning_readiness,
    command: ["ruby", "scripts/validate_front_planning_readiness.rb", front_planning_readiness.to_s],
    blocking_on_fail: front_planning_required || front_planning_entry_required
  )
  add_command_check(
    checks,
    id: "front_planning_sequence_core_hold",
    group: "research",
    label: "Front Planning Sequence-parent Core-dump HOLD consume",
    artifact: front_planning_readiness,
    command: ["ruby", "scripts/validate_front_planning_sequence_core_hold.rb", front_planning_readiness.to_s],
    blocking_on_fail: front_planning_required || front_planning_entry_required
  )
else
  add_missing_check(
    checks,
    id: "front_planning_readiness",
    group: "research",
    label: "front-planning readiness index",
    artifact: "(not found)",
    blocking: front_planning_required
  )
  run_root_front_planning = first_existing(run_path, ["front-planning.yaml"])
  if run_root_front_planning
    add_command_check(
      checks,
      id: "front_planning_sequence_core_hold",
      group: "research",
      label: "Front Planning Sequence-parent Core-dump HOLD consume",
      artifact: run_root_front_planning,
      command: ["ruby", "scripts/validate_front_planning_sequence_core_hold.rb", run_root_front_planning.to_s],
      blocking_on_fail: front_planning_required || front_planning_entry_required
    )
  end
end

add_internal_check(
  checks,
  id: "active_section_owner_coverage",
  group: "research",
  label: "active Front Planning/01/02A section owner coverage",
  artifact: first_existing(run_path, ["01-song-choreography-performance-mv-map.yaml"]) || front_planning_readiness || "(not found)",
  blocking_on_fail: false
) do
  active_section_owner_coverage_status(
    {
      "01" => first_existing(run_path, ["01-song-choreography-performance-mv-map.yaml"]),
      "02A" => first_existing(run_path, ["02A-master-storyboard.yaml"])
    },
    readiness: front_planning_readiness ? load_yaml(front_planning_readiness) : nil
  )
end

audio_motion = latest_match(run_path, ["research/audio-motion-director-map-v*.yaml", "research/audio-motion-director-map-v*.json"], canonical_only: true)
if audio_motion.nil? && audio_input_lineage_schema_valid && Array(audio_input_lineage_resolution["errors"]).empty?
  audio_motion = audio_input_lineage_resolution.dig("resolved_inputs", "audio_motion_director_map")
end
if audio_motion
  add_schema_check(
    checks,
    id: "audio_motion_schema",
    group: "research",
    label: "audio motion director map schema",
    schema: "schemas/audio-motion-director-map.schema.json",
    artifact: audio_motion
  )
  add_command_check(
    checks,
    id: "audio_motion_validator",
    group: "research",
    label: "audio motion director map validator",
    artifact: audio_motion,
    command: ["ruby", "scripts/validate_audio_motion_director_map.rb", audio_motion]
  )
elsif selected_audio
  add_missing_check(
    checks,
    id: "audio_motion_director_map",
    group: "research",
    label: "audio motion director map",
    artifact: "(not found)",
    blocking: true
  )
end

review_record = latest_match(run_path, ["review/03-generated-branch-cut-review-v*.yaml", "review/03-generated-branch-cut-review-v*.json"])
if review_record
  add_schema_check(
    checks,
    id: "generated_board_review",
    group: "review",
    label: "generated Branch-Cut review",
    schema: "schemas/review.schema.json",
    artifact: review_record
  )
  add_command_check(
    checks,
    id: "generated_branch_cut_review_validator",
    group: "review",
    label: "generated Branch-Cut review validator",
    artifact: review_record,
    command: ["ruby", "scripts/validate_generated_branch_cut_review.rb", review_record]
  )
end

qa_path = latest_match(
  run_path,
  [
    "review/03v-section-video-prompt-qa-v*.yaml",
    "review/03V/**/03v-section-video-prompt-qa-v*.yaml"
  ],
  canonical_only: true
)
if qa_path
  add_schema_check(
    checks,
    id: "video_prompt_section_qa_schema",
    group: "video",
    label: "video prompt section QA schema",
    schema: "schemas/video-prompt-section-qa.schema.json",
    artifact: qa_path
  )
  add_command_check(
    checks,
    id: "video_prompt_section_qa_readiness",
    group: "video",
    label: "video prompt section QA readiness",
    artifact: qa_path,
    command: ["ruby", "scripts/validate_video_prompt_section_qa_readiness.rb", qa_path]
  )
  video_prompt_section_qa_worklist_yaml = latest_match(run_path, ["review/03v-section-video-prompt-qa-worklist-v*.yaml"])
  add_worklist_check(
    checks,
    id: "video_prompt_section_qa_worklist",
    group: "video",
    label: "video prompt section QA blocker worklist freshness",
    source_artifact: qa_path,
    worklist_artifact: video_prompt_section_qa_worklist_yaml || latest_match(run_path, ["review/03v-section-video-prompt-qa-worklist-v*.md"]),
    generator_command: "ruby scripts/idol_video_prompt_section_qa_worklist.rb #{run_rel} --write"
  )
  if video_prompt_section_qa_worklist_yaml
    add_schema_check(
      checks,
      id: "video_prompt_section_qa_worklist_schema",
      group: "video",
      label: "video prompt section QA blocker worklist schema",
      schema: "schemas/harness-blocker-worklist.schema.json",
      artifact: video_prompt_section_qa_worklist_yaml
    )
  end
end

publishing_plan = rel_path(run_path + "publishing-plan.md")
if readable_file?(publishing_plan)
  add_command_check(
    checks,
    id: "publishing_plan",
    group: "social",
    label: "publishing plan validator",
    artifact: publishing_plan,
    command: ["scripts/idol-video-python", "scripts/validate_publishing_plan.py", publishing_plan]
  )
else
  add_missing_check(
    checks,
    id: "publishing_plan",
    group: "social",
    label: "publishing plan validator",
    artifact: publishing_plan,
    blocking: false
  )
end

if album_key && title_key
  track_board = "catalog/albums/#{album_key}/#{title_key}/track-creative-board.yaml"
  registry = "catalog/albums/#{album_key}/#{title_key}/output-registry.yaml"
  reference_index = "catalog/albums/#{album_key}/#{title_key}/reference-index.yaml"
  contact_sheet_index = "catalog/albums/#{album_key}/#{title_key}/contact-sheet-index.yaml"
  add_schema_check(
    checks,
    id: "track_creative_board",
    group: "catalog",
    label: "catalog Track Continuity Board",
    schema: "schemas/track-creative-board.schema.json",
    artifact: track_board
  )
  add_internal_check(
    checks,
    id: "track_local_first_direction_planning",
    group: "catalog",
    label: "track local-first direction planning gate",
    artifact: track_board
  ) do
    track_local_first_direction_status(load_yaml(track_board))
  end
  add_internal_check(
    checks,
    id: "track_style_system_lock",
    group: "catalog",
    label: "track style system lock gate",
    artifact: track_board
  ) do
    track_style_system_lock_status(load_yaml(track_board))
  end
  add_schema_check(
    checks,
    id: "title_output_registry_schema",
    group: "catalog",
    label: "title output registry schema",
    schema: "schemas/title-output-registry.schema.json",
    artifact: registry
  )
  add_command_check(
    checks,
    id: "title_output_registry",
    group: "catalog",
    label: "title output registry validator",
    artifact: registry,
    command: ["scripts/idol-video-python", "scripts/idol_title_output_registry.py", "validate", "--registry", registry]
  )
  if readable_file?(reference_index)
    add_schema_check(
      checks,
      id: "title_reference_index",
      group: "catalog",
      label: "title reference pointer index",
      schema: "schemas/album-reference-index.schema.json",
      artifact: reference_index
    )
    add_internal_check(
      checks,
      id: "title_reference_pointer_integrity",
      group: "catalog",
      label: "title reference pointer owner/path integrity",
      artifact: reference_index,
      blocking_on_fail: false
    ) do
      album_reference_index_pointer_status(reference_index)
    end
  else
    add_missing_check(
      checks,
      id: "title_reference_index",
      group: "catalog",
      label: "title reference pointer index",
      artifact: reference_index,
      blocking: false
    )
  end
  if readable_file?(contact_sheet_index)
    add_schema_check(
      checks,
      id: "title_contact_sheet_index",
      group: "catalog",
      label: "title contact-sheet pointer index",
      schema: "schemas/album-reference-index.schema.json",
      artifact: contact_sheet_index
    )
    add_internal_check(
      checks,
      id: "title_contact_sheet_pointer_integrity",
      group: "catalog",
      label: "title contact-sheet pointer owner/path integrity",
      artifact: contact_sheet_index,
      blocking_on_fail: false
    ) do
      album_reference_index_pointer_status(contact_sheet_index)
    end
  else
    add_missing_check(
      checks,
      id: "title_contact_sheet_index",
      group: "catalog",
      label: "title contact-sheet pointer index",
      artifact: contact_sheet_index,
      blocking: false
    )
  end
  add_internal_check(
    checks,
    id: "title_catalog_pointer_only",
    group: "catalog",
    label: "title catalog pointer-only file hygiene",
    artifact: registry,
    blocking_on_fail: false
  ) do
    catalog_pointer_only_status("catalog/albums/#{album_key}/#{title_key}")
  end
end

generated_at = Time.now.iso8601
drifts = drift_notes(checks, hermes_context, video_manifest_artifact) + pointer_drift_notes(run_rel)
status = overall_status(checks)
readiness_axes = independent_readiness_axes(run_path: run_path, run_rel: run_rel, checks: checks, drifts: drifts)
report = markdown_report(
  run_rel: run_rel,
  album_key: album_key,
  title_key: title_key,
  generated_at: generated_at,
  checks: checks,
  hermes_context: hermes_context,
  drifts: drifts
)

if options[:json]
  payload = {
    generated_at: generated_at,
    run: run_rel,
    content_id: content_id,
    album_key: album_key,
    title_key: title_key,
    overall_status: status,
    readiness_axes: readiness_axes,
    counts: status_counts(checks),
    blocking_checks: checks.select(&:blocking).map(&:id),
    next_actions: checks.select(&:blocking).to_h { |check| [check.id, next_action_for(check)] },
    state_pointer_drift: drifts,
    hermes_drift: drifts,
    checks: checks.map(&:to_h)
  }
  puts JSON.pretty_generate(payload)
else
  puts "IDOL Graph Engineering state: #{status}"
  puts "run: #{run_rel}"
  puts "checks: #{status_counts(checks).sort.map { |key, value| "#{key}=#{value}" }.join(', ')}"
  puts "readiness: schema=#{readiness_axes[:schema_valid]} revision=#{readiness_axes[:revision_coherent].inspect} stage=#{readiness_axes[:stage_ready]} founder=#{readiness_axes[:founder_gate]} resumable=#{readiness_axes[:next_unit_resumable]}"
  blocking = checks.select(&:blocking)
  if blocking.any?
    puts "blocking:"
    blocking.first(12).each { |check| puts "- #{check.id}: #{check.status} - #{check.label}" }
    puts "- ... #{blocking.length - 12} more" if blocking.length > 12
  end
  if drifts.any?
    puts "state_pointer_drift:"
    drifts.each { |note| puts "- #{note}" }
  end
end

if options[:write_report] || options[:report]
  default_report = "automation/state-reports/#{Time.now.strftime('%Y-%m-%d')}-#{content_id}-harness-state.md"
  report_path = resolve_path(options[:report] || default_report)
  FileUtils.mkdir_p(report_path.dirname)
  report_path.write(report, encoding: "utf-8")
  puts "report: #{rel_path(report_path)}" unless options[:json]
end

exit(status == "validator_pass" ? 0 : 1)
