# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "yaml"
require_relative "support/active_mv_fixture"

class Idol02ACreativeContextReviewTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_02a_creative_context_review.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_active_v7_contextual_review_passes
    assert_valid
  end

  def test_v6_is_not_active
    mutate { |review| review["schema_version"] = "idol-02a-creative-context-review.v6" }
    assert_invalid("only idol-02a-creative-context-review.v7 is active")
  end

  def test_v7_requires_core_import_immutability_review
    mutate { |review| review.fetch("section_reviews").first.delete("core_import_immutability_review") }
    assert_invalid("active v7 requires core_import_immutability_review")
  end

  def test_passing_review_rejects_detected_02a_core_mutation
    mutate do |review|
      review.dig("section_reviews", 0, "core_import_immutability_review")["02a_core_mutation_detected"] = true
    end
    assert_invalid("passing review cannot detect a 02A Core mutation")
  end

  def test_core_import_review_must_exact_cover_imported_cores
    mutate do |review|
      review.dig("section_reviews", 0, "core_import_immutability_review", "reviewed_core_cut_ids").pop
    end
    assert_invalid("must exact-cover imported 01 Core Cuts")
  end

  def test_section_reviews_must_exact_cover_source_sections
    mutate { |review| review["section_reviews"].clear }
    assert_invalid("section_reviews must exact-cover source 02A sections")
  end

  def test_source_core_cut_ids_must_exact_cover_imported_cores
    mutate { |review| review.dig("section_reviews", 0, "source_core_cut_ids").pop }
    assert_invalid("source_core_cut_ids must exact-cover source 02A Core Cuts")
  end

  def test_upstream_realization_review_is_required
    mutate { |review| review.fetch("section_reviews").first.delete("upstream_realization_review") }
    assert_invalid("active v7 requires upstream_realization_review")
  end

  def test_upstream_source_01_field_refs_must_resolve
    mutate do |review|
      review.dig("section_reviews", 0, "upstream_realization_review", "source_01_field_refs")[0] =
        "01#/section_directions/0/missing_field"
    end
    assert_invalid("source 01 field ref does not resolve")
  end

  def test_passing_review_rejects_script_substitution
    mutate do |review|
      review.dig("section_reviews", 0, "upstream_realization_review")["script_substitution_detected"] = true
    end
    assert_invalid("passing section cannot detect script substitution")
  end

  def test_storyline_planning_cut_hashes_must_exact_match_source
    mutate do |review|
      review.dig("section_reviews", 0, "storyline_realization_review", "source_planning_cut_alignment_hashes", 0)["value_sha256"] = "0" * 64
    end
    assert_invalid("planning-cut hashes must exact-cover source order and values")
  end

  def test_passing_review_requires_02b_prompt_readiness
    mutate do |review|
      review.dig("section_reviews", 0, "storyline_realization_review")["02b_prompt_readiness_verdict"] = "hold"
    end
    assert_invalid("passing review requires 02B prompt readiness pass")
  end

  def test_source_02a_hash_must_match_exact_storyboard_bytes
    mutate { |review| review.dig("source_02a", "sha256").replace("0" * 64) }
    assert_invalid("source_02a.sha256 mismatch")
  end

  def test_required_canonical_section_review_field_cannot_be_missing
    mutate { |review| review.fetch("section_reviews").first.delete("source_core_cut_ids") }
    assert_invalid("'source_core_cut_ids' is a required property")
  end

  def test_review_content_id_must_match_source_02a
    mutate { |review| review["content_id"] = "WRONG_CONTENT" }
    assert_invalid("content_id does not match source 02A")
  end

  def test_whole_film_review_must_exact_cover_source_sections
    mutate { |review| review.dig("whole_film_review", "section_ids").clear }
    assert_invalid("whole_film_review.section_ids must exact-cover all source 02A sections")
  end

  def test_execution_receipt_must_bind_the_exact_source_02a_hash
    mutate do |review|
      review.dig("section_reviews", 0, "reviewer", "execution_receipt", "source_02a_sha256").replace("0" * 64)
    end
    assert_invalid("execution receipt source_02a_sha256 must match source 02A")
  end

  def test_execution_record_requires_provider_neutral_profile_snapshot
    record = @fixture.run_dir.join("work", "review-execution", "02A-S01.yaml")
    document = YAML.safe_load(record.read, aliases: true)
    document.delete("provider_profile_snapshot_ref")
    record.write(YAML.dump(document))
    refresh_execution_record_hash(record, section: true)
    assert_invalid("requires an exact provider profile snapshot")
  end

  private

  def mutate
    review = YAML.safe_load(@fixture.context_review_path.read, aliases: true)
    yield review
    @fixture.context_review_path.write(YAML.dump(review))
  end

  def run_validator
    Open3.capture3("ruby", VALIDATOR.to_s, "--repo-root", ROOT.to_s, @fixture.context_review_path.to_s, chdir: ROOT.to_s)
  end

  def refresh_execution_record_hash(record, section:)
    review = YAML.safe_load(@fixture.context_review_path.read, aliases: true)
    receipt = if section
                review.dig("section_reviews", 0, "reviewer", "execution_receipt", "execution_record")
              else
                review.dig("whole_film_review", "reviewer", "execution_receipt", "execution_record")
              end
    receipt["sha256"] = Digest::SHA256.file(record).hexdigest
    @fixture.context_review_path.write(YAML.dump(review))
  end

  def assert_valid
    stdout, stderr, status = run_validator
    assert status.success?, [stderr, stdout].join("\n")
    assert_includes stdout, "valid"
  end

  def assert_invalid(fragment)
    stdout, stderr, status = run_validator
    refute status.success?, [stderr, stdout].join("\n")
    assert_includes [stderr, stdout].join("\n"), fragment
  end
end
