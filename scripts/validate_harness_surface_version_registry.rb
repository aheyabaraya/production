#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
REGISTRY = ROOT.join("automation", "harness-surface-version-registry.yaml")
SCHEMA = ROOT.join("schemas", "harness-surface-version-registry.schema.json")

options = {json: false}
OptionParser.new { |parser| parser.on("--json") { options[:json] = true } }.parse!
errors = []

unless REGISTRY.file?
  errors << "registry is missing: #{REGISTRY.relative_path_from(ROOT)}"
  document = {}
else
  stdout, stderr, status = Open3.capture3(
    ROOT.join("scripts", "idol-video-python").to_s,
    ROOT.join("scripts", "validate_json_schema.py").to_s,
    SCHEMA.to_s,
    REGISTRY.to_s,
    chdir: ROOT.to_s
  )
  errors << [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip unless status.success?
  document = YAML.safe_load(REGISTRY.read, aliases: true)
  document = {} unless document.is_a?(Hash)
end

surfaces = Array(document["surfaces"]).select { |row| row.is_a?(Hash) }
ids = surfaces.map { |row| row["surface_id"].to_s }
paths = surfaces.map { |row| row["path"].to_s }
ids.group_by(&:itself).each { |id, rows| errors << "duplicate surface_id: #{id}" if id.empty? || rows.length > 1 }
paths.group_by(&:itself).each { |path, rows| errors << "duplicate surface path: #{path}" if path.empty? || rows.length > 1 }

surfaces.each do |row|
  path = ROOT.join(row["path"].to_s).cleanpath
  unless path.file?
    errors << "tracked surface is missing: #{row['path']}"
    next
  end
  actual = Digest::SHA256.file(path.to_s).hexdigest
  errors << "tracked surface SHA-256 is stale: #{row['path']}" unless actual == row["sha256"].to_s
end

# A byte hash proves that the registry points at the current file, but it does
# not prove that the AI/model-facing surface role describes the active contract
# version. Keep the small set of execution-critical contracts fail-closed so a
# stale vN role cannot survive a hash refresh unnoticed.
semantic_version_expectations = {
  "automation/harness-execution-contract.yaml" => "v36",
  "schemas/harness-execution-contract.schema.json" => "v36",
  "schemas/director-dispatch-index.schema.json" => "v4",
  "schemas/harness-current-next.schema.json" => "v2",
  "development/front-planning-workbench/contracts/artifact-layout.schema.json" => "v5",
  "development/front-planning-workbench/contracts/canvas-state.schema.json" => "v5",
  "development/front-planning-workbench/contracts/model-routing.json" => "v15",
  "development/front-planning-workbench/contracts/model-routing.schema.json" => "v15",
  "development/front-planning-workbench/contracts/native-bridge.schema.json" => "v6",
  "development/front-planning-workbench/contracts/run-route-manifest.schema.json" => "v4",
  "development/front-planning-workbench/contracts/shared-context-checkpoint.schema.json" => "v4",
  "schemas/prompt-packet-delta.schema.json" => "v1_6",
  "schemas/prompt-packets.schema.json" => "v2_6",
  "schemas/image-generation-request.schema.json" => "v12",
  "schemas/image-generation-section-approval.schema.json" => "v6",
  "schemas/image-generation-request-selection.schema.json" => "v3",
  "schemas/image-generation-section-worklist.schema.json" => "v9",
  "schemas/image-generation-dispatch-ledger.schema.json" => "v4",
  "schemas/image-render-correction.schema.json" => "v8",
  "schemas/image-generation-execution-receipt.schema.json" => "v4",
  "schemas/production-cut-review.schema.json" => "v2",
  "schemas/03v-authoring-source-pack.schema.json" => "v5",
  "schemas/video-prompt-manifest.schema.json" => "v8",
  "schemas/grok-video-prompt-reference-pack.schema.json" => "v7",
  "schemas/codex-native-media-provider-profiles.schema.json" => "v1",
  "schemas/cdd-session-router-state.schema.json" => "v1",
  "schemas/sequence-motion-analysis.schema.json" => "v1",
  "schemas/xai-api-media-provider-profiles.schema.json" => "v1"
}.freeze
surface_by_path = surfaces.each_with_object({}) { |row, memo| memo[row["path"].to_s] = row }
semantic_version_expectations.each do |relative, expected|
  row = surface_by_path[relative]
  if row.nil?
    errors << "execution-critical semantic surface is missing: #{relative}"
    next
  end
  padded_role = "_#{row['role']}_"
  errors << "surface role version is stale: #{relative} must describe #{expected}" unless padded_role.include?("_#{expected}_")
end

semantic_role_expectations = {
  "automation/harness-provider-profile-registry.yaml" => %w[registration_required registered_exact],
  "schemas/harness-provider-profile-registry.schema.json" => %w[registration_required registered_exact]
}.freeze
semantic_role_expectations.each do |relative, fragments|
  row = surface_by_path[relative]
  if row.nil?
    errors << "provider-conditional semantic surface is missing: #{relative}"
    next
  end
  fragments.each do |fragment|
    errors << "surface role semantics are stale: #{relative} must describe #{fragment}" unless row["role"].to_s.include?(fragment)
  end
end

%w[
  schemas/sequence-motion-analysis.schema.json
  scripts/idol_prepare_sequence_motion_analysis.rb
  scripts/validate_sequence_motion_analysis.rb
].each do |relative|
  errors << "Sequence Motion surface is missing: #{relative}" unless surface_by_path.key?(relative)
end

%w[
  .grok/config.toml
  .grok/sandbox.toml
  .grok/skills/idol-cli-bridge/scripts/open_cli.sh
  .grok/skills/idol-cli-bridge/scripts/resolve_cli.py
].each do |relative|
  errors << "Grok physical-session surface is missing: #{relative}" unless surface_by_path.key?(relative)
end

tracked_skill_paths = surfaces.select { |row| row["surface_type"] == "skill" }.map { |row| row["path"].to_s }.to_set
required_skill_paths = Dir.glob(ROOT.join("skills", "*", "SKILL.md").to_s).map { |path| Pathname.new(path).relative_path_from(ROOT).to_s }.to_set
required_skill_paths << ".grok/skills/idol-grok-harness-owner/SKILL.md" if ROOT.join(".grok", "skills", "idol-grok-harness-owner", "SKILL.md").file?
required_skill_paths << ".grok/skills/idol-harness-step/SKILL.md" if ROOT.join(".grok", "skills", "idol-harness-step", "SKILL.md").file?
required_skill_paths << ".grok/skills/idol-cli-bridge/SKILL.md" if ROOT.join(".grok", "skills", "idol-cli-bridge", "SKILL.md").file?
(required_skill_paths - tracked_skill_paths).sort.each { |path| errors << "skill is missing from surface registry: #{path}" }
(tracked_skill_paths - required_skill_paths).sort.each { |path| errors << "surface registry has a non-current skill path: #{path}" }

target = document.dig("skill_shape_policy", "target_lines").to_i
ceiling = document.dig("skill_shape_policy", "reviewed_ceiling_lines").to_i
review_rows = Array(document["skill_shape_reviews"]).select { |row| row.is_a?(Hash) }
review_by_path = review_rows.each_with_object({}) { |row, memo| memo[row["path"].to_s] = row }

required_skill_paths.each do |relative|
  path = ROOT.join(relative)
  lines = path.read.lines.count
  review = review_by_path[relative]
  errors << "skill above #{target} lines lacks a shape review: #{relative} (#{lines})" if lines > target && review.nil?
  if lines > ceiling
    approved_ceiling = review.to_h.dig("ceiling_exception", "maximum_lines").to_i
    unless review.to_h.dig("ceiling_exception", "status") == "founder_approved_existing_exception" && lines <= approved_ceiling
      errors << "skill exceeds reviewed ceiling #{ceiling} and requires explicit Founder instruction before remediation: #{relative} (#{lines})"
    end
  end
  if review
    errors << "skill shape review line count is stale: #{relative}" unless review["observed_lines"].to_i == lines
    if lines <= target && review["disposition"] == "split_required_after_founder_instruction"
      errors << "split_required_after_founder_instruction is inconsistent with a below-target skill: #{relative}"
    end
    if review.key?("ceiling_exception") && lines <= ceiling
      errors << "skill ceiling exception is unnecessary below the reviewed ceiling: #{relative}"
    end
  end
end

known_skill_names = required_skill_paths.map { |path| Pathname.new(path).dirname.basename.to_s }.to_set
Array(document["overlap_reviews"]).each do |row|
  next unless row.is_a?(Hash)
  Array(row["skills"]).each do |skill|
    errors << "overlap review names an unknown skill: #{skill}" unless known_skill_names.include?(skill.to_s)
  end
end

authority_paths = Array(document["creative_adjacent_script_authority"]).each_with_object([]) do |row, result|
  result << row["path"].to_s if row.is_a?(Hash)
end
authority_paths.each do |relative|
  errors << "creative-adjacent script is missing: #{relative}" unless ROOT.join(relative).file?
end
(authority_paths.to_set - paths.to_set).sort.each do |relative|
  errors << "creative-adjacent script lacks a versioned surface entry: #{relative}"
end

guard = document["shared_script_write_guard"].is_a?(Hash) ? document["shared_script_write_guard"] : {}
canonical_tokens = Array(guard["canonical_filename_tokens"]).map(&:to_s).reject(&:empty?)
write_operation = /\b(?:write_text|write_bytes|safe_dump|json\.dump|File\.write|atomic_write)\b|\.write\s*\(/
guard_candidates = Dir.glob(ROOT.join("scripts", "*.{rb,py}").to_s).sort.each_with_object([]) do |path, result|
  text = File.read(path, encoding: "UTF-8")
  next unless text.match?(write_operation)
  next unless canonical_tokens.any? { |token| text.include?(token) }

  result << Pathname.new(path).relative_path_from(ROOT).to_s
rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
  next
end
exemption_rows = Array(guard["noncanonical_exemptions"]).select { |row| row.is_a?(Hash) }
exemption_paths = exemption_rows.map { |row| row["path"].to_s }
exemption_paths.group_by(&:itself).each do |path, rows|
  errors << "duplicate shared-script guard exemption: #{path}" if path.empty? || rows.length > 1
end
(guard_candidates.to_set - authority_paths.to_set - exemption_paths.to_set).sort.each do |relative|
  errors << "shared script with canonical filename and write operation lacks authority classification: #{relative}"
end
(exemption_paths.to_set - guard_candidates.to_set).sort.each do |relative|
  errors << "stale shared-script guard exemption no longer matches the detector: #{relative}"
end

result = {
  "status" => errors.reject(&:empty?).empty? ? "pass" : "fail",
  "surface_count" => surfaces.length,
  "tracked_skill_count" => tracked_skill_paths.length,
  "skill_shape_review_count" => review_rows.length,
  "errors" => errors.reject(&:empty?)
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif result["status"] == "pass"
  puts "OK: #{surfaces.length} versioned Graph Engineering surfaces and #{tracked_skill_paths.length} skills match current bytes"
else
  result["errors"].each { |error| warn "ERROR: #{error}" }
end

exit(result["status"] == "pass" ? 0 : 1)
