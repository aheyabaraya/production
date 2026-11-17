#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "pathname"
require "set"
require "time"
require "yaml"
require_relative "lib/idol_skill_contract_paths"

ROOT = Pathname.new(Dir.pwd).cleanpath
PROFILE_REGISTRY = ROOT.join("automation", "harness-skill-load-profiles.yaml")

CORE_SKILLS = Set.new(%w[
  idol-orchestrator
  idol-front-planning-director
  idol-front-planning-development-block
  idol-choreography-board
  idol-pinterest-reference-worker
  idol-reference-research-department
  idol-review-board-coordinator
  idol-world-still-reference-department
  idol-member-visual-identity
  idol-research-radar
  idol-suno-prompt
  idol-song-lock
  idol-mv-director
  idol-choreography-performance
  idol-generation
  idol-video-prompt
  idol-editing-qc
  idol-edit-finishing-fx
  idol-shot-vfx
  idol-video-reference-hub
]).freeze

ISOLATED_SKILLS = Set.new(%w[
  idol-front-planning-handoff
  idol-grid-overlay
  idol-human-face-realism-control
  idol-member-teaser-portrait
  idol-mv-concept-research
  idol-nucleus
  idol-photoreal-human-face-lock
  idol-social-metadata-upload
  idol-surgical-face-architecture
  idol-track-poster
  kling
  reels-tiktok-template
  source-faithful-teaser
  x-posting-template
]).freeze

ROLE_SCOPED_CORE_REQUIRED_READS = {
  # These media skills delegate their exact read set to the selected checkpoint.
  # Requiring the global wiki would restore intentionally omitted context.
  "idol-generation" => Set.new(%w[
    AGENTS.md
    automation/harness-skill-load-profiles.yaml
  ]),
  "idol-video-prompt" => Set.new(%w[
    AGENTS.md
    automation/harness-skill-load-profiles.yaml
  ]),
  "idol-choreography-board" => Set.new(%w[
    AGENTS.md
    policies/creative-production-constitution.md
    policies/section-production.md
    schemas/harness-section-slice.schema.json
    schemas/song-choreography-performance-mv-map.schema.json
    schemas/master-storyboard.schema.json
  ]),
  "idol-reference-research-department" => Set.new(%w[
    AGENTS.md
    policies/harness-routing-and-sources.md
    policies/section-production.md
    schemas/department-dispatch.schema.json
    schemas/reference-working-index.schema.json
    skills/idol-front-planning-director/references/director-operating-contract.md
  ]),
  "idol-pinterest-reference-worker" => Set.new(%w[
    AGENTS.md
    policies/harness-routing-and-sources.md
    policies/section-production.md
    schemas/department-dispatch.schema.json
    schemas/reference-working-index.schema.json
    skills/idol-front-planning-director/references/director-operating-contract.md
    skills/idol-pinterest-reference-worker/references/pinterest-section-comparison-detail.md
  ]),
  "idol-video-reference-hub" => Set.new(%w[
    AGENTS.md
    policies/harness-routing-and-sources.md
    policies/repository-media-security.md
    schemas/department-dispatch.schema.json
    source-materials/video-sources/README.md
    source-materials/video-sources/READ-FIRST.md
    skills/idol-video-reference-hub/references/video-reference-analysis-first-read-contract.md
    scripts/README.md
  ])
}.freeze

def rel_path(path)
  resolved = Pathname.new(path).cleanpath
  resolved.relative_path_from(ROOT).to_s
rescue ArgumentError
  path.to_s
end

def skill_name(skill_path)
  Pathname.new(skill_path).dirname.basename.to_s
end

def mode_for(name, text)
  return "retired-stub" if text.match?(/Status:\s*retired\b/i) || text.include?("[RETIRED / DO NOT USE FOR NEW WORK]")
  return "compat-alias" if text.include?("compatibility alias") || text.include?("isolated compatibility alias")
  return "harness-core" if CORE_SKILLS.include?(name)
  return "isolated-helper" if ISOLATED_SKILLS.include?(name)

  "uncategorized"
end

def headings(text)
  text.scan(/^##\s+(.+)$/).flatten
end

def truncate_list(values, limit = 4)
  return "none" if values.empty?

  shown = values.first(limit)
  suffix = values.length > limit ? " +#{values.length - limit}" : ""
  "#{shown.map { |value| "`#{value}`" }.join('<br>')}#{suffix}"
end

def markdown_table_row(values)
  "| #{values.map { |value| value.to_s.gsub("|", "\\|") }.join(" | ")} |"
end

options = {
  output: "automation/skill-purpose-contract-matrix-#{Time.now.strftime('%Y-%m-%d')}.md",
  write: false,
  strict: false
}

OptionParser.new do |parser|
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--write") { options[:write] = true }
  parser.on("--strict") { options[:strict] = true }
end.parse!

skill_paths = Dir.glob((ROOT + "skills/*/SKILL.md").to_s).sort
rows = []
issues = []

profile_document = if PROFILE_REGISTRY.file?
                     YAML.safe_load(PROFILE_REGISTRY.read, aliases: true) || {}
                   else
                     {}
                   end
skill_binding_paths = Array(profile_document["skill_bindings"]).each_with_object({}) do |row, memo|
  memo[row["binding_id"].to_s] = row["path"].to_s if row.is_a?(Hash)
end
read_binding_paths = Array(profile_document["read_bindings"]).each_with_object({}) do |row, memo|
  memo[row["binding_id"].to_s] = row["path"].to_s if row.is_a?(Hash)
end
profile_reads_by_skill = Hash.new { |hash, key| hash[key] = Set.new }
Array(profile_document["profiles"]).each do |profile|
  next unless profile.is_a?(Hash)

  phases = [profile["phase_load"]].compact + Array(profile.dig("phase_load", "checkpoints"))
  skill_ids = Array(profile["required_skill_ids"])
  read_ids = Array(profile["required_read_ids"])
  phases.each do |phase|
    next unless phase.is_a?(Hash)

    skill_ids.concat(Array(phase["preload_skill_ids"] || phase["required_skill_ids"]))
    read_ids.concat(Array(phase["preload_read_ids"] || phase["required_read_ids"]))
  end
  skill_names = skill_ids.map { |id| skill_binding_paths[id.to_s] }.compact.map { |path| Pathname.new(path).dirname.basename.to_s }.uniq
  read_paths = read_ids.map { |id| read_binding_paths[id.to_s] }.compact
  skill_names.each { |name| profile_reads_by_skill[name].merge(read_paths) }
end

skill_paths.each do |path|
  text = File.read(path, encoding: "utf-8")
  name = skill_name(path)
  mode = mode_for(name, text)
  skill_headings = headings(text)
  has_required_reads = skill_headings.include?("Required Reads")
  has_rw_contract = skill_headings.include?("Read / Write Contract")
  paths = IdolSkillContractPaths.candidate_paths(text)
  profile_reads = profile_reads_by_skill[name]
  effective_reads = (paths + profile_reads.to_a).uniq
  schema_refs = effective_reads.select { |candidate| candidate.start_with?("schemas/") }
  local_refs = paths.select { |candidate| candidate.start_with?("references/", "modules/") }
  write_refs = paths.select { |candidate| candidate.start_with?("runs/", "catalog/", "assets/") }
  has_output_contract = skill_headings.any? { |heading| heading.match?(/(?:\A| )(Output|Outputs|Output Shape|Output Location|Output And Validation|Output Placement|Output Boundary|Minimum Output|Upload Boundary|Read \/ Write Contract)\b/i) } ||
                        text.match?(/Allowed outputs:|Forbidden outputs:/)

  if mode == "harness-core"
    issues << "#{name}: core skill missing Required Reads" unless has_required_reads
    issues << "#{name}: active skill/profile route does not bind AGENTS.md" if has_required_reads && !effective_reads.include?("AGENTS.md")
    scoped_required_reads = ROLE_SCOPED_CORE_REQUIRED_READS[name]
    if scoped_required_reads
      missing_scoped_reads = scoped_required_reads - effective_reads.to_set
      missing_scoped_reads.each { |read| issues << "#{name}: role-scoped active route does not bind #{read}" }
    elsif has_required_reads && !effective_reads.include?("wiki/production-system.md")
      issues << "#{name}: active skill/profile route does not bind wiki/production-system.md"
    end
    issues << "#{name}: missing output/write contract" unless has_output_contract
    issues << "#{name}: no schema reference; automation readiness may be prose-only" if schema_refs.empty?
  elsif !has_required_reads && !has_rw_contract
    issues << "#{name}: missing Required Reads or Read / Write Contract"
  end

  if mode == "retired-stub" && !text.match?(/Forbidden outputs?:/i) && !text.match?(/do not write new/i)
    issues << "#{name}: retired stub should explicitly forbid new prompt/output creation"
  end

  rows << {
    name: name,
    mode: mode,
    line_count: text.lines.count,
    read_contract: has_required_reads ? "Required Reads" : (has_rw_contract ? "Read / Write Contract" : "missing"),
    schema_refs: schema_refs.uniq.sort,
    local_refs: local_refs.uniq.sort,
    write_refs: write_refs.uniq.sort,
    output_contract: has_output_contract ? "yes" : "no"
  }
end

lines = []
lines << "# IDOL Skill Purpose Contract Matrix"
lines << ""
lines << "generated_at: #{Time.now.iso8601}"
lines << "status: `#{issues.empty? ? 'pass' : 'needs_attention'}`"
lines << ""
lines << "This report checks whether each IDOL skill exposes a purpose-specific read contract, schema/reference pointers, and write/output boundaries. It does not validate creative quality by itself; it highlights where automation can or cannot rely on machine-readable contracts."
lines << ""
lines << "## Summary"
lines << ""
mode_counts = rows.each_with_object(Hash.new(0)) { |row, counts| counts[row[:mode]] += 1 }
mode_counts.sort.each { |mode, count| lines << "- #{mode}: #{count}" }
lines << "- issues_or_schema_gaps: #{issues.length}"
lines << ""
lines << "## Findings"
lines << ""
if issues.empty?
  lines << "- No contract gaps detected by this matrix."
else
  issues.sort.each { |issue| lines << "- #{issue}" }
end
lines << ""
lines << "## Matrix"
lines << ""
lines << "| skill | mode | read contract | output boundary | schema refs | local refs | write refs |"
lines << "| --- | --- | --- | --- | --- | --- | --- |"
rows.each do |row|
  lines << markdown_table_row([
    "`#{row[:name]}`",
    row[:mode],
    row[:read_contract],
    row[:output_contract],
    truncate_list(row[:schema_refs]),
    truncate_list(row[:local_refs]),
    truncate_list(row[:write_refs])
  ])
end
lines << ""
lines << "## Interpretation"
lines << ""
lines << "- Graph-engineering-core skills are mostly managed by `Required Reads`, schemas, and run-owned output paths."
lines << "- Retired/alias/external-helper skills are safer when they expose `Read / Write Contract` plus explicit forbidden outputs."
lines << "- Prose-only outputs are acceptable for isolated/manual work, but they are weak surfaces for minimum-intervention automation."
lines << ""
lines << "## Skill Size Inventory"
lines << ""
lines << "This inventory is informational. It surfaces skills that may need router/reference"
lines << "splitting during the next real edit, without turning line count into a readiness gate."
lines << ""
lines << "| lines | skill | mode | local refs |"
lines << "| ---: | --- | --- | --- |"
rows.sort_by { |row| [-row[:line_count], row[:name]] }.each do |row|
  lines << markdown_table_row([
    row[:line_count],
    "`#{row[:name]}`",
    row[:mode],
    truncate_list(row[:local_refs])
  ])
end

report = lines.join("\n")

if options[:write]
  output = Pathname.new(options[:output])
  output = ROOT + output unless output.absolute?
  FileUtils.mkdir_p(output.dirname)
  output.write(report, encoding: "utf-8")
  puts "wrote #{rel_path(output)}"
else
  puts report
end

if options[:strict] && !issues.empty?
  warn "ERROR: #{issues.length} skill purpose contract gap(s) detected"
  issues.sort.each { |issue| warn "ERROR: #{issue}" }
  exit 1
end

exit 0
