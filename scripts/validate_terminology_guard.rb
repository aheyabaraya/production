#!/usr/bin/env ruby
# frozen_string_literal: true

require "find"
require "open3"

ROOT = File.expand_path("..", __dir__)

DEFAULT_ROOTS = %w[
  schemas
  skills
  wiki
  docs
  handoff
  automation
  catalog
  drive-sync
  scripts
].freeze

TEXT_EXTENSIONS = %w[.md .json .yaml .yml .rb .py].freeze

EXCLUDED_FILES = %w[
  schemas/prompt-packets-v1.3-legacy.schema.json
  scripts/tests/validate_terminology_guard_test.rb
].freeze

EXCLUDED_PREFIXES = %w[
  .git/
  cf/
  drive-sync/02_GPT_GROK_HANDOFF/
  drive-sync/99_ARCHIVE/
].freeze

FIELD_CONTEXT_PATTERNS = {
  "proof_target" => [
    /compatibility field name/i,
    /visual\s+readability target/i,
    /schema field/i,
    /contract label/i
  ],
  "visual_evidence" => [
    /compatibility (?:field name|label)/i,
    /visible details/i,
    /body\/action readability detail/i,
    /schema field/i,
    /contract label/i
  ],
  "review_surface" => [
    /compatibility field name/i,
    /review material/i,
    /review stage/i,
    /founder lock|approval source/i,
    /schema field/i,
    /contract label/i
  ],
  "audio_pressure" => [
    /compatibility field name/i,
    /audio cue\/tension/i,
    /pacing and motion/i,
    /schema field/i,
    /contract label/i
  ],
  "lyric_pressure" => [
    /compatibility field name/i,
    /lyric cue\/tension/i,
    /schema field/i,
    /contract label/i
  ]
}.freeze

STALE_OPERATOR_TERMS = {
  /\bBeat Completeness\b/i => "Use Cut Completeness for active operator-facing graph-engineering guidance.",
  /\b02A storyboard beats\b/i => "Use 02A storyboard cuts for active screen-event units.",
  /\b02A timeline scene beats\b/i => "Use 02A timeline scene cuts for active screen-event units.",
  /\bAPI beat-level keyframe generation\b/i => "Use one Branch-Cut generation request per active 02B packet.",
  /\b12-beat overview\b/i => "Use 12-cut overview for active 02A preview review language.",
  /\b2-3 beat detail\b/i => "Use 2-3 cut detail for active 02A preview review language.",
  /\bEach cell is one 02A beat\b/i => "Use Each cell is one 02A cut for active preview review language.",
  /\bBEAT \[Bxx\]/i => "Use CUT [Cxx] for active preview review labels.",
  /\bShort Beat Title\b/i => "Use Short Cut Title for active founder review labels.",
  /\bsection\/beat cards\b/i => "Use section/cut cards for active 01R and 02A screen-event planning.",
  /\bAffected 02A beats\b/i => "Use affected 02A cuts for active screen-event planning.",
  /\bbeat-level composition\b/i => "Use cut-level composition for active screen-event review.",
  /\binternal packet\/beat ids\b/i => "Use internal packet/cut ids or legacy beat ids.",
  /\bFounder-approved beat source mode\b/i => "Use Founder-approved legacy beat-source clip mode when naming the compatibility lane.",
  /\bBeat source framing defaults\b/i => "Use Legacy beat-source framing defaults for the compatibility lane.",
  /\bcurrent beat prompt\b/i => "Use current cut prompt for active prompt guidance.",
  /\bgroup beat\b/i => "Use group cut when referring to active screen-event framing.",
  /\bbeat ids or cue ids\b/i => "Use cut ids, legacy beat ids, or cue ids when compatibility fields are involved.",
  /\bbeat moves from @image1\b/i => "Use cut or clip movement language for video prompts.",
  /\bbeat pacing\b/i => "Use cut pacing or cue pacing for operator-facing video prompt language.",
  /\bempty-scene beat\b/i => "Use empty-scene cut for active screen-event language.",
  /\bproof target\b/i => "Use visual readability target for operator-facing text.",
  /\bvisual evidence\b/i => "Use Visible details for prompt labels; Visual evidence is allowed only as a legacy fallback.",
  /\breview surface\b/i => "Use review material or review stage for operator-facing text.",
  /\baudio pressure\b/i => "Use audio cue/tension for operator-facing text.",
  /\blyric pressure\b/i => "Use lyric cue/tension for operator-facing text."
}.freeze

# These are retired labels, not forbidden natural-language concepts. Camera,
# reference, and lyric prose may still use the same ordinary words.
LABEL_ONLY_TERMS = [
  "proof target", "visual evidence", "review surface", "audio pressure", "lyric pressure"
].freeze

def operator_label_usage?(line, phrase)
  # Also inspect an escaped prompt line inside a JSON/YAML string. Matching a
  # label here never judges what the surrounding creative prose means.
  prefix = /(?:\A|\\n)[ \t]*(?:\{[ \t]*)?(?:["'][^"'\n]+["'][ \t]*:[ \t]*)?(?:\#{1,6}[ \t]+|[-*][ \t]+|\|[ \t]*)?["'`* \t]*/
  line.match?(/#{prefix.source}#{Regexp.escape(phrase)}["'`* \t]*(?::|\||\z)/i)
end

def relative_path(path)
  path.sub(%r{\A#{Regexp.escape(ROOT)}/?}, "")
end

def excluded_path?(relative)
  return true if EXCLUDED_FILES.include?(relative)

  EXCLUDED_PREFIXES.any? { |prefix| relative.start_with?(prefix) }
end

def text_file?(path)
  TEXT_EXTENSIONS.include?(File.extname(path))
end

def tracked_files_to_check(roots)
  stdout, stderr, status = Open3.capture3("git", "ls-files", "-z", "--", *roots, chdir: ROOT)
  raise "git ls-files failed: #{stderr.strip}" unless status.success?

  stdout.split("\0").each_with_object([]) do |relative, files|
    next if relative.empty? || excluded_path?(relative)

    path = File.expand_path(relative, ROOT)
    next unless File.file?(path) && text_file?(path)

    files << path
  end.uniq.sort
end

def files_to_check(paths, tracked_only: false)
  roots = paths.empty? ? DEFAULT_ROOTS : paths
  return tracked_files_to_check(roots) if tracked_only

  roots.flat_map do |entry|
    path = File.expand_path(entry, ROOT)
    next [] unless File.exist?(path)

    if File.file?(path)
      [path]
    else
      found = []
      Find.find(path) do |candidate|
        relative = relative_path(candidate)
        if File.directory?(candidate)
          Find.prune if excluded_path?("#{relative}/")
          next
        end
        next unless File.file?(candidate)
        next unless text_file?(candidate)
        next if excluded_path?(relative)

        found << candidate
      end
      found
    end
  end.uniq.sort
end

def structured_field_line?(line, field)
  stripped = line.strip
  return true if stripped.match?(/\A["']?#{Regexp.escape(field)}["']?\s*:/)
  return true if stripped.match?(/\A-?\s*["']?#{Regexp.escape(field)}["']?\s*[:,]?\s*(?:\{|\[)?\z/)
  return true if stripped.match?(/\A-\s*["']?#{Regexp.escape(field)}["']?\s*,?\z/)
  return true if stripped.match?(/\A#{Regexp.escape(field)}:\s*(?:\z|[#\[{])/)

  false
end

def legacy_visual_evidence_line?(line)
  line.match?(/LEGACY_VISUAL_EVIDENCE_LABEL/) ||
    line.match?(/legacy.*Visual evidence|Visual evidence.*legacy/i) ||
    line.match?(/compatibility.*Visual evidence|Visual evidence.*compatibility/i)
end

def field_context_ok?(field, window)
  FIELD_CONTEXT_PATTERNS.fetch(field).any? { |pattern| window.match?(pattern) }
end

tracked_only = ARGV.delete("--tracked-only")
errors = []

files_to_check(ARGV, tracked_only: !tracked_only.nil?).each do |path|
  relative = relative_path(path)
  lines = File.readlines(path, chomp: true)

  lines.each_with_index do |line, index|
    STALE_OPERATOR_TERMS.each do |pattern, message|
      next unless line.match?(pattern)
      next if pattern.source.include?("visual evidence") && legacy_visual_evidence_line?(line)
      label = LABEL_ONLY_TERMS.find { |phrase| pattern.match?(phrase) }
      next if label && !operator_label_usage?(line, label)

      errors << "#{relative}:#{index + 1}: #{message}"
    end

    next if File.extname(path).match?(/\A\.(?:rb|py)\z/)

    FIELD_CONTEXT_PATTERNS.each_key do |field|
      next unless line.match?(/\b#{Regexp.escape(field)}\b/)
      next if structured_field_line?(line, field)

      window = [
        index.positive? ? lines[index - 1] : "",
        line,
        lines[index + 1].to_s
      ].join(" ")
      next if field_context_ok?(field, window)

      errors << "#{relative}:#{index + 1}: #{field} must be framed as a compatibility field/label with the approved operator-facing term."
    end
  end
end

if errors.empty?
  puts "OK: terminology guard passed"
else
  warn errors.join("\n")
  exit 1
end
