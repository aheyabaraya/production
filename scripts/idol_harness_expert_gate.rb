#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "time"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path

options = {json: false, strict: false, output: nil}
parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_harness_expert_gate.rb RUN_ROOT [--json] [--strict]"
  opts.on("--json", "Emit JSON") { options[:json] = true }
  opts.on("--strict", "Treat every applicable missing expert contract as failure") { options[:strict] = true }
  opts.on("--output PATH", "Write the machine-readable report to PATH") { |value| options[:output] = Pathname.new(value).expand_path }
end
parser.parse!

run_argument = ARGV.shift
if run_argument.to_s.empty?
  warn parser
  exit 2
end

run_path = Pathname.new(run_argument)
run_path = ROOT.join(run_path) unless run_path.absolute?
run_path = run_path.expand_path
unless run_path.directory?
  warn "run root not found: #{run_path}"
  exit 2
end

def load_structured(path)
  return {} unless path&.file?

  if path.extname.downcase == ".json"
    JSON.parse(path.read)
  else
    YAML.safe_load(path.read, aliases: true) || {}
  end
rescue JSON::ParserError, Psych::SyntaxError => e
  {"_parse_error" => e.message}
end

def latest(run_path, patterns)
  path = patterns.flat_map { |pattern| Dir.glob(run_path.join(pattern).to_s) }
                 .select { |candidate| File.file?(candidate) }
                 .sort
                 .last
  path && Pathname.new(path)
end

def ready_claim?(status)
  text = status.to_s.downcase
  return false if text.empty?
  return false if text.match?(/draft|candidate|provisional|founder_review|hold|replan|blocked|precanonical/)

  text.match?(/ready|locked|selected|approved|complete|pass/)
end

def gate(id:, applies:, status:, blocking:, artifact:, evidence:, missing:)
  {
    "id" => id,
    "applies" => applies,
    "status" => status,
    "blocking" => blocking,
    "artifact" => artifact,
    "evidence" => evidence,
    "missing" => missing
  }
end

gates = []

suno_path = latest(run_path, ["research/suno-prompt-packet-v*.md"])
if suno_path
  text = suno_path.read
  founder_test = text.match?(/founder_manual_suno_test/i) || text.match?(/founder manual/i)
  required_headings = ["Song Craft Lock", "Candidate Audition Plan"]
  missing = required_headings.reject { |heading| text.match?(/^##\s+#{Regexp.escape(heading)}\s*$/i) }
  status = if !founder_test
             "not_applicable"
           elsif missing.empty?
             "pass"
           elsif options[:strict]
             "fail"
           else
             "legacy_gap"
           end
  gates << gate(
    id: "song_prompt_craft_plan",
    applies: founder_test,
    status: status,
    blocking: status == "fail",
    artifact: suno_path.relative_path_from(ROOT).to_s,
    evidence: ["founder_test=#{founder_test}", "required_headings=#{required_headings.join(',')}"] ,
    missing: missing
  )
else
  gates << gate(id: "song_prompt_craft_plan", applies: false, status: "not_applicable", blocking: false, artifact: nil, evidence: [], missing: [])
end

audio_path = latest(run_path, ["research/selected-audio-analysis-v*.yaml", "research/selected-audio-analysis-v*.yml", "research/selected-audio-analysis-v*.json"])
audio = load_structured(audio_path)
if audio_path
  audio_status = audio["status"].to_s
  selection_ready = ready_claim?(audio_status)
  craft = audio["song_craft_evaluation"]
  missing = []
  missing << "song_craft_evaluation" unless craft.is_a?(Hash) && !craft.empty?
  if craft.is_a?(Hash)
    candidate_ids = Array(craft["candidate_ids"]).map(&:to_s)
    score_ids = Array(craft["audition_scorecard"]).map { |row| row.is_a?(Hash) ? row["candidate_id"].to_s : nil }.compact
    missing << "selected_candidate_id_not_in_candidate_ids" unless candidate_ids.include?(craft["selected_candidate_id"].to_s)
    missing << "candidate_scorecard_alignment" unless (candidate_ids - score_ids).empty?
    if craft["evaluation_mode"] == "comparative"
      missing << "comparative_candidate_count" if candidate_ids.uniq.length < 2
    end
  end
  status = if missing.empty?
             "pass"
           elsif selection_ready || options[:strict]
             "fail"
           else
             "pending"
           end
  gates << gate(
    id: "selected_audio_song_craft",
    applies: true,
    status: status,
    blocking: status == "fail",
    artifact: audio_path.relative_path_from(ROOT).to_s,
    evidence: ["audio_status=#{audio_status}", "selection_ready_claim=#{selection_ready}"],
    missing: missing
  )
else
  gates << gate(id: "selected_audio_song_craft", applies: false, status: "not_applicable", blocking: false, artifact: nil, evidence: [], missing: [])
end

direction_path = run_path.join("01-song-choreography-performance-mv-map.yaml")
direction = load_structured(direction_path)
if direction_path.file?
  direction_status = direction["status"].to_s
  direction_ready = direction_status == "passed"
  section_rows = Array(direction["section_directions"]).select { |row| row.is_a?(Hash) }
  director_missing = []
  director_missing << "schema_version=2.0" unless direction["schema_version"].to_s == "2.0"
  director_missing << "source_front_planning" unless direction["source_front_planning"].is_a?(Hash)
  director_missing << "source_song_lock" unless direction["source_song_lock"].is_a?(Hash)
  director_missing << "front_planning_consumption_contract" unless direction["front_planning_consumption_contract"].is_a?(Hash)
  director_missing << "target_message_projection" unless direction["target_message_projection"].is_a?(Hash)
  director_missing << "whole_film_spine_projection" unless direction["whole_film_spine_projection"].is_a?(Hash)
  director_missing << "founder_visual_alignment_projection" unless direction["founder_visual_alignment_projection"].is_a?(Hash)
  director_missing << "section_directions" if section_rows.empty?
  section_rows.each do |section|
    section_id = section["section_id"].to_s
    prefix = section_id.empty? ? "section_direction" : section_id
    director_missing << "#{prefix}.section_alignment_projection" unless section["section_alignment_projection"].is_a?(Hash)
    director_missing << "#{prefix}.planning_cut_alignment_projections" if Array(section["planning_cut_alignment_projections"]).empty?
    director_missing << "#{prefix}.scene_expansions" if Array(section["scene_expansions"]).empty?
    Array(section["scene_expansions"]).each do |scene|
      next unless scene.is_a?(Hash)

      director_missing << "#{prefix}.source_key_screen_anchor_ids" if Array(scene["source_key_screen_anchor_ids"]).empty?
      director_missing << "#{prefix}.branching_opportunities" if Array(scene["branching_opportunities"]).empty?
      Array(scene["branching_opportunities"]).each do |opportunity|
        next unless opportunity.is_a?(Hash)

        director_missing << "#{prefix}.branching_opportunity.source_key_screen_anchor_ids" if Array(opportunity["source_key_screen_anchor_ids"]).empty?
      end
    end
    camera_rows = Array(section["still_camera_coverage"]).select { |row| row.is_a?(Hash) }
    director_missing << "#{prefix}.still_camera_coverage" if camera_rows.empty?
    camera_rows.each do |camera|
      director_missing << "#{prefix}.camera.source_key_screen_anchor_ids" if Array(camera["source_key_screen_anchor_ids"]).empty?
      unless camera["temporal_camera_owner"].to_s == "03V_after_passed_image_pixel_inspection"
        director_missing << "#{prefix}.temporal_camera_owner"
      end
    end
    if %w[primary supporting].include?(section["choreography_presence_policy"].to_s) &&
       !section["choreography_reference_binding"].is_a?(Hash)
      director_missing << "#{prefix}.choreography_reference_binding"
    end
  end
  director_status = if director_missing.empty?
                      "pass"
                    elsif direction_ready || options[:strict]
                      "fail"
                    else
                      "pending"
                    end
  gates << gate(
    id: "front_planning_to_01_direction_expansion",
    applies: true,
    status: director_status,
    blocking: director_status == "fail",
    artifact: direction_path.relative_path_from(ROOT).to_s,
    evidence: [
      "direction_status=#{direction_status}",
      "schema_version=#{direction['schema_version']}",
      "section_count=#{section_rows.length}",
      "still_camera_owner=01_and_02a",
      "temporal_camera_owner=03v_after_passed_pixels",
      "creative_adequacy_authority=contextual_llm_review"
    ],
    missing: director_missing
  )

  active_choreo_sections = section_rows.select do |row|
    %w[primary supporting].include?(row["choreography_presence_policy"].to_s)
  end.map { |row| row["section_id"].to_s }.reject(&:empty?)
  covered_sections = section_rows.select do |row|
    row["choreography_reference_binding"].is_a?(Hash)
  end.map { |row| row["section_id"].to_s }.reject(&:empty?)
  choreography_missing = active_choreo_sections - covered_sections
  choreography_status = if active_choreo_sections.empty?
                          "not_applicable"
                        elsif choreography_missing.empty?
                          "pass"
                        elsif direction_ready || options[:strict]
                          "fail"
                        else
                          "pending"
                        end
  gates << gate(
    id: "choreography_execution_feasibility",
    applies: active_choreo_sections.any?,
    status: choreography_status,
    blocking: choreography_status == "fail",
    artifact: direction_path.relative_path_from(ROOT).to_s,
    evidence: ["active_primary_supporting_sections=#{active_choreo_sections.join(',')}", "covered_sections=#{covered_sections.join(',')}"],
    missing: choreography_missing.uniq
  )
else
  gates << gate(id: "front_planning_to_01_direction_expansion", applies: false, status: "not_applicable", blocking: false, artifact: nil, evidence: [], missing: [])
  gates << gate(id: "choreography_execution_feasibility", applies: false, status: "not_applicable", blocking: false, artifact: nil, evidence: [], missing: [])
end

storyboard_path = run_path.join("02A-master-storyboard.yaml")
storyboard = load_structured(storyboard_path)
if storyboard_path.file?
  cuts = Array(storyboard["master_storyboard"]).select { |row| row.is_a?(Hash) }
  storyboard_status = storyboard["status"].to_s
  storyboard_ready = ready_claim?(storyboard_status)
  storyboard_structure_errors = []
  storyboard_structure_errors << "active 02A requires schema_version=3.0" unless storyboard["schema_version"].to_s == "3.0"
  cuts.each do |core_cut|
    core_cut_id = core_cut["core_cut_id"].to_s
    prefix = core_cut_id.empty? ? "core_cut" : core_cut_id
    storyboard_structure_errors << "#{prefix}.compile_seed.branch_cuts" if Array(core_cut.dig("compile_seed", "branch_cuts")).empty?
  end
  review_path = latest(run_path, ["review/02a-creative-context-review-v*.yaml", "review/02a-creative-context-review-v*.yml"])
  review = load_structured(review_path)
  review_errors = storyboard_structure_errors
  if review_path
    validator = ROOT.join("scripts", "validate_02a_creative_context_review.rb")
    _stdout, stderr, contract_status = Open3.capture3(
      RbConfig.ruby,
      validator.to_s,
      review_path.to_s,
      chdir: ROOT.to_s
    )
    review_errors << stderr.strip unless contract_status.success?
    unless review["schema_version"].to_s == "idol-02a-creative-context-review.v7"
      review_errors << "active 02B readiness requires idol-02a-creative-context-review.v7 with storyline, immutable Official Core fidelity, screen progression, and Branch-Cut distinctness review"
    end
  else
    review_errors << "missing review/02a-creative-context-review-vN.yaml"
  end

  section_verdicts = Array(review["section_reviews"]).map do |row|
    row["verdict"].to_s if row.is_a?(Hash)
  end.compact
  whole_verdict = review.dig("whole_film_review", "verdict").to_s
  founder_decision = review.dig("founder_gate", "decision").to_s
  contextual_pass = review_errors.empty? &&
                    section_verdicts.any? && section_verdicts.all? { |value| value == "pass" } &&
                    whole_verdict == "pass" && founder_decision == "pass"
  contextual_hold = section_verdicts.any? { |value| %w[revise hold].include?(value) } ||
                    %w[revise hold].include?(whole_verdict) || %w[hold reject].include?(founder_decision)
  review_status = if contextual_pass
                    "pass"
                  elsif review_errors.any? && (storyboard_ready || options[:strict])
                    "fail"
                  elsif contextual_hold && (storyboard_ready || options[:strict])
                    "fail"
                  else
                    "pending"
                  end
  gates << gate(
    id: "storyboard_llm_creative_context_review",
    applies: cuts.any?,
    status: review_status,
    blocking: review_status == "fail",
    artifact: review_path ? review_path.relative_path_from(ROOT).to_s : storyboard_path.relative_path_from(ROOT).to_s,
    evidence: [
      "machine_creative_judgment_forbidden=true",
      "review_schema_version=#{review['schema_version']}",
      "section_review_count=#{section_verdicts.length}",
      "section_verdicts=#{section_verdicts.join(',')}",
      "whole_film_verdict=#{whole_verdict}",
      "founder_decision=#{founder_decision}"
    ],
    missing: review_errors.reject(&:empty?) + (contextual_hold ? ["contextual_llm_review_requires_revision_or_hold"] : [])
  )
else
  gates << gate(id: "storyboard_llm_creative_context_review", applies: false, status: "not_applicable", blocking: false, artifact: nil, evidence: [], missing: [])
end

editing_reference = ROOT.join("skills", "idol-editing-qc", "references", "editing-qc-detail.md")
hardcoded_bpm_hits = editing_reference.file? ? editing_reference.read.scan(/\b\d{2,3}\.\d+\s*BPM\b/i).uniq : []
editing_status = hardcoded_bpm_hits.empty? ? "pass" : "fail"
gates << gate(
  id: "editing_run_specific_grid_hygiene",
  applies: true,
  status: editing_status,
  blocking: editing_status == "fail",
  artifact: editing_reference.relative_path_from(ROOT).to_s,
  evidence: ["hardcoded_decimal_bpm_count=#{hardcoded_bpm_hits.length}"],
  missing: hardcoded_bpm_hits.map { |value| "remove_run_specific_grid:#{value}" }
)

overall_status = if gates.any? { |item| item["status"] == "fail" }
                   "fail"
                 elsif gates.any? { |item| %w[pending legacy_gap].include?(item["status"]) }
                   "pending"
                 else
                   "pass"
                 end

report = {
  "schema_version" => "idol-harness-expert-quality-report.v1",
  "generated_at" => Time.now.iso8601,
  "run" => run_path.relative_path_from(ROOT).to_s,
  "mode" => options[:strict] ? "strict" : "active_only",
  "overall_status" => overall_status,
  "readiness_rule" => "schema validity is independent; an applicable pending/fail expert gate prevents stage_ready but does not imply Founder approval",
  "gates" => gates
}

if options[:output]
  FileUtils.mkdir_p(options[:output].dirname)
  options[:output].write("#{JSON.pretty_generate(report)}\n")
end

if options[:json]
  puts JSON.pretty_generate(report)
else
  puts "IDOL expert quality gates: #{overall_status} (#{report['mode']})"
  gates.each do |item|
    puts "- #{item['id']}: #{item['status']}#{item['missing'].empty? ? '' : " | missing=#{item['missing'].join(',')}"}"
  end
end

exit(overall_status == "fail" ? 1 : 0)
