# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "yaml"

# G1 hex-strip: FP/reference instruction slices must not tell models to copy
# SHA-256 into prose or YAML. Envelope/schema SHA fields stay elsewhere.
class IdolG1HexStripInstructionTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  PROFILES = ROOT.join("automation", "harness-skill-load-profiles.yaml")
  PROFILE_IDS = %w[creative_development_director reference_research_generalist].freeze
  SLICE_PREFIXES = [
    "skills/idol-front-planning-director/",
    "skills/idol-reference-research-department/"
  ].freeze

  COPY_SHA_IMPERATIVES = [
    /01 receives exact hashes/i,
    /bind the exact hash/i,
    /canonical row-value SHA-256/i,
    /per-frame paths\/SHA-256/i,
    /cell\/frame id, path, and SHA-256/i,
    /frame_path_sha256:\s*\[exact selected artifact\]/i,
    /id, path, SHA-256, and observable/i,
    /derivative path, and SHA-256/i
  ].freeze

  def test_fp_and_reference_instruction_slices_do_not_ask_models_to_copy_sha
    paths = instruction_slice_paths
    refute_empty paths, "expected FP/reference skill-load slices"

    paths.each do |relative|
      text = ROOT.join(relative).read
      COPY_SHA_IMPERATIVES.each do |pattern|
        refute_match(
          pattern,
          text,
          "#{relative} still contains copy-SHA-256 imperative #{pattern.inspect}"
        )
      end
    end

    joined = paths.map { |relative| ROOT.join(relative).read }.join("\n")
    assert_match(/source_id/, joined)
    assert_match(/connected/, joined)
    assert_match(/not_connected/, joined)
    assert_match(/scripts stamp SHA/i, joined)
  end

  def instruction_slice_paths
    document = YAML.safe_load(PROFILES.read, aliases: true)
    skill_by_id = index_bindings(document.fetch("skill_bindings"))
    read_by_id = index_bindings(document.fetch("read_bindings"))
    ids = []
    document.fetch("profiles").each do |profile|
      next unless PROFILE_IDS.include?(profile["profile_id"])

      ids.concat(Array(profile["required_skill_ids"]))
      ids.concat(Array(profile["required_read_ids"]))
      Array(profile.dig("phase_load", "checkpoints")).each do |checkpoint|
        ids.concat(Array(checkpoint["required_skill_ids"]))
        ids.concat(Array(checkpoint["required_read_ids"]))
      end
    end

    ids.uniq.map { |id| skill_by_id[id] || read_by_id[id] }.compact.select do |path|
      SLICE_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    end.uniq.sort
  end

  def index_bindings(rows)
    Array(rows).each_with_object({}) { |row, memo| memo[row.fetch("binding_id")] = row.fetch("path") }
  end
end
