# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/idol_graph_criterion_evidence_contract"

class IdolGraphCriterionEvidenceContractTest < Minitest::Test
  CONTRACT = IdolGraphCriterionEvidenceContract

  def setup
    @root = Pathname.new(Dir.mktmpdir("criterion-evidence-"))
    @root.join("one.png").write("first exact fixture body")
    @root.join("two.png").write("second exact fixture body")
    @root.join("rows.json").write(JSON.generate("rows" => [{"image_path" => "one.png", "image_sha256" => ref("one.png")["sha256"]}]))
    @doc = {"schema_version" => "idol_graph_contextual_judgment.v2", "source_artifacts" => %w[one.png two.png rows.json].map { |p| ref(p) },
            "criteria" => [{"criterion_id" => "identity", "evidence_locator" => [ref("one.png"), ref("two.png")]}], "hard_gate_findings" => []}
  end

  def teardown
    FileUtils.remove_entry(@root) if @root.directory?
  end

  def ref(path)
    {"path" => path, "sha256" => Digest::SHA256.file(@root.join(path)).hexdigest}
  end

  def verify(images = nil)
    CONTRACT.verify!(root: @root, document: @doc, expected_cut_images: images)
  end

  def test_exact_declared_files_cover_each_target_cut
    assert verify([ref("one.png"), ref("two.png")])
  end

  def test_unresolved_free_text_and_undeclared_file_cannot_supply_evidence
    @doc["criteria"][0]["evidence_locator"] = "unresolved://not-a-bound-source"
    assert_raises(CONTRACT::ContractError) { verify }
    @doc["criteria"][0]["evidence_locator"] = [{"path" => "unknown.png", "sha256" => "0" * 64}]
    assert_raises(CONTRACT::ContractError) { verify }
  end

  def test_current_file_hash_must_match_declared_evidence
    @root.join("one.png").write("changed body")
    error = assert_raises(CONTRACT::ContractError) { verify }
    assert_includes error.message, "SHA-256 is stale"
  end

  def test_every_criterion_must_cover_every_exact_cut
    @doc["criteria"] << {"criterion_id" => "composition", "evidence_locator" => [ref("one.png")]}
    error = assert_raises(CONTRACT::ContractError) { verify([ref("one.png"), ref("two.png")]) }
    assert_includes error.message, "composition evidence does not cover every exact target Cut"
  end

  def test_same_hash_in_wrong_source_path_does_not_cover_missing_cut
    @root.join("other.png").write(@root.join("two.png").read)
    @doc["source_artifacts"] << ref("other.png")
    @doc["criteria"][0]["evidence_locator"] = [ref("one.png"), ref("other.png")]
    assert_raises(CONTRACT::ContractError) { verify([ref("one.png"), ref("two.png")]) }
  end

  def test_exact_structured_row_can_bind_its_real_cut_image
    value = JSON.parse(@root.join("rows.json").read)["rows"][0]
    @doc["criteria"][0]["evidence_locator"] = [ref("rows.json").merge("json_pointer" => "/rows/0", "value_sha256" => CONTRACT.value_sha256(value))]
    assert verify([ref("one.png")])
    @doc["criteria"][0]["evidence_locator"][0]["value_sha256"] = "0" * 64
    assert_raises(CONTRACT::ContractError) { verify }
  end

  def test_nested_row_image_hash_is_verified_without_expected_cut_set
    value = {"image_path" => "one.png", "image_sha256" => "0" * 64}
    @root.join("rows.json").write(JSON.generate("rows" => [value]))
    @doc["source_artifacts"] = [ref("rows.json")]
    @doc["criteria"][0]["evidence_locator"] = [ref("rows.json").merge("json_pointer" => "/rows/0", "value_sha256" => CONTRACT.value_sha256(value))]
    error = assert_raises(CONTRACT::ContractError) { verify }
    assert_includes error.message, "row image SHA-256 is stale"
  end

  def test_g2_review_rows_are_cut_targets_including_contact_sheet_filename
    named = @root.join("contact-sheet-named-cut.png")
    named.write("typed cut whose filename contains contact-sheet")
    branch = @root.join("branch-cut.png")
    sheet = @root.join("contact-sheet.png")
    unmarked = @root.join("unmarked.png")
    branch.write("typed generated branch cut")
    sheet.write("sheet only")
    unmarked.write("unmarked still")
    named_sha = Digest::SHA256.file(named).hexdigest
    branch_sha = Digest::SHA256.file(branch).hexdigest
    review = {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "branch_cut_reviews" => [
        {
          "packet_id" => "PKT_BC01_NAMED",
          "branch_cut_id" => "BC01_NAMED",
          "section_id" => "S01",
          "core_cut_id" => "C01",
          "image_path" => "contact-sheet-named-cut.png",
          "image_sha256" => named_sha,
          "media_kind" => "contact_sheet"
        },
        {
          "packet_id" => "PKT_BC01_ACTION",
          "branch_cut_id" => "BC01_ACTION",
          "section_id" => "S01",
          "core_cut_id" => "C01",
          "image_path" => "branch-cut.png",
          "image_sha256" => branch_sha
        }
      ]
    }
    review_path = @root.join("g2-review.json")
    review_path.write(JSON.generate(review))
    expected = CONTRACT.expected_cut_images_from_authentic_manifest(
      root: @root,
      manifest: {
        "outputs" => [
          {"path" => "g2-review.json", "sha256" => Digest::SHA256.file(review_path).hexdigest}
        ]
      },
      section_ids: ["S01"]
    )
    assert_equal [
      {"path" => "contact-sheet-named-cut.png", "sha256" => named_sha},
      {"path" => "branch-cut.png", "sha256" => branch_sha}
    ], expected
  end

  def test_g2_row_with_media_kind_does_not_disappear
    cut = @root.join("cut.png")
    cut.write("cut body")
    sha = Digest::SHA256.file(cut).hexdigest
    review = {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "branch_cut_reviews" => [{
        "packet_id" => "PKT_BC01_CUT",
        "branch_cut_id" => "BC01_CUT",
        "section_id" => "S01",
        "core_cut_id" => "C01",
        "image_path" => "cut.png",
        "image_sha256" => sha,
        "media_kind" => "contact_sheet"
      }]
    }
    targets = CONTRACT.generated_branch_cut_image_targets(review, %w[S01])
    assert_equal [{"path" => "cut.png", "sha256" => sha}], targets
  end

  def test_g2_malformed_row_holds_instead_of_dropping_valid_siblings
    named = @root.join("ok.png")
    named.write("ok")
    review = {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "branch_cut_reviews" => [
        {
          "packet_id" => "PKT_BC01_OK",
          "branch_cut_id" => "BC01_OK",
          "section_id" => "S01",
          "core_cut_id" => "C01",
          "image_path" => "ok.png",
          "image_sha256" => Digest::SHA256.file(named).hexdigest
        },
        {
          "packet_id" => "PKT_BC01_BAD",
          "branch_cut_id" => "BC01_BAD",
          "section_id" => "S01",
          "core_cut_id" => "C01",
          "image_path" => "ok.png"
        }
      ]
    }
    error = assert_raises(CONTRACT::ContractError) { CONTRACT.generated_branch_cut_image_targets(review, %w[S01]) }
    assert_includes error.message, "branch_cut_reviews[1] is missing image_path/image_sha256"
  end

  def test_g2_invalid_row_id_holds
    named = @root.join("cut.png")
    named.write("cut")
    review = {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "branch_cut_reviews" => [{
        "packet_id" => "PKT_BC01_CUT",
        "branch_cut_id" => "not-a-branch",
        "section_id" => "S01",
        "core_cut_id" => "C01",
        "image_path" => "cut.png",
        "image_sha256" => Digest::SHA256.file(named).hexdigest
      }]
    }
    error = assert_raises(CONTRACT::ContractError) { CONTRACT.generated_branch_cut_image_targets(review) }
    assert_includes error.message, "packet_id/branch_cut_id/section_id/core_cut_id is invalid"
  end

  def test_g2_v4_document_without_branch_cut_reviews_holds
    error = assert_raises(CONTRACT::ContractError) {
      CONTRACT.generated_branch_cut_image_targets("schema_version" => "idol_generated_branch_cut_review.v4")
    }
    assert_includes error.message, "branch_cut_reviews array"
  end

  def test_hash_bound_generated_png_output_is_a_cut_target_without_g2_review
    pixel = @root.join("BC01_ACTION.png")
    pixel.write("synthetic G2 pixel fixture bytes\n")
    expected = CONTRACT.expected_cut_images_from_authentic_manifest(
      root: @root,
      manifest: {"outputs" => [{"path" => "BC01_ACTION.png", "sha256" => Digest::SHA256.file(pixel).hexdigest}]}
    )
    assert_equal [{"path" => "BC01_ACTION.png", "sha256" => Digest::SHA256.file(pixel).hexdigest}], expected
  end

  def test_two_direct_image_outputs_are_both_cut_targets_and_omitting_one_holds
    one = @root.join("one.png")
    two = @root.join("two.png")
    one.write("first generated pixel")
    two.write("second generated pixel")
    expected = CONTRACT.expected_cut_images_from_authentic_manifest(
      root: @root,
      manifest: {"outputs" => [ref("one.png"), ref("two.png")]}
    )
    assert_equal [ref("one.png"), ref("two.png")], expected
    @doc["source_artifacts"] = [ref("one.png"), ref("two.png")]
    @doc["criteria"][0]["evidence_locator"] = [ref("one.png")]
    error = assert_raises(CONTRACT::ContractError) { verify(expected) }
    assert_includes error.message, "does not cover every exact target Cut image"
  end

  def test_missing_row_and_invalid_pointer_escape_fail
    %w[/rows/9 /rows/0/missing /rows/~2].each do |pointer|
      @doc["criteria"][0]["evidence_locator"] = [ref("rows.json").merge("json_pointer" => pointer, "value_sha256" => "0" * 64)]
      assert_raises(CONTRACT::ContractError) { verify }
    end
  end

  def test_pointer_and_value_hash_are_an_indivisible_binding
    @doc["criteria"][0]["evidence_locator"] = [ref("rows.json").merge("json_pointer" => "/rows/0")]
    assert_raises(CONTRACT::ContractError) { verify }
  end

  def test_symlink_cannot_escape_the_declared_repository
    outside = Pathname.new(Dir.mktmpdir("criterion-outside-"))
    outside.join("source.txt").write("external fixture")
    @root.join("link.txt").make_symlink(outside.join("source.txt"))
    binding = ref("link.txt")
    @doc["source_artifacts"] << binding
    @doc["criteria"][0]["evidence_locator"] = [binding]
    assert_raises(CONTRACT::ContractError) { verify }
  ensure
    FileUtils.remove_entry(outside) if outside&.directory?
  end

  def test_legacy_shape_never_silently_enters_current_authoring
    @doc["schema_version"] = "idol_graph_contextual_judgment.v1"
    assert_raises(CONTRACT::ContractError) { verify }
  end
end
