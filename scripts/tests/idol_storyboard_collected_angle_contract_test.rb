# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_storyboard_collected_angle_contract"

class IdolStoryboardCollectedAngleContractTest < Minitest::Test
  def setup
    @root = Pathname.new(Dir.mktmpdir("angle-review-"))
    @lock_path = @root.join("founder-locks.yaml")
    @lock_path.write(YAML.dump({"explicit_locks" => ["Repeat this exact pair only."]}))
    @lock_sha = IdolStoryboardCollectedAngleContract.value_sha256("Repeat this exact pair only.")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && @root.exist?
  end

  def document_with(images)
    cores = {}
    images.each do |image|
      if image["production_cut_type"] == "official_core"
        cores[image["cut_id"]] ||= {
          "core_cut_id" => image["cut_id"],
          "section_id" => image["section_id"],
          "imported_core" => {
            "section_id" => image["section_id"],
            "primary_image" => {"sha256" => image["image_sha256"]},
            "camera" => image["still_camera_spec"]
          },
          "compile_seed" => {"branch_cuts" => []}
        }
      end
    end
    images.each do |image|
      next unless image["production_cut_type"] == "branch"

      parent = cores[image["parent_cut_id"].to_s]
      parent ||= cores.values.find { |core| core.dig("imported_core", "section_id").to_s == image["section_id"].to_s }
      parent ||= cores.values.first
      parent.dig("compile_seed", "branch_cuts") << {
        "branch_cut_id" => image["cut_id"],
        "section_id" => image["section_id"],
        "still_camera_spec" => image["still_camera_spec"]
      }
    end
    {"master_storyboard" => cores.values}
  end

  def image(cut_id, type, height, angle, sha, section_id: "S01", parent_cut_id: nil)
    spec = {"camera_height" => height, "direction_angle" => angle}
    pointer = type == "official_core" ? "/master_storyboard/0/imported_core/camera" : "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    {
      "cut_id" => cut_id,
      "production_cut_type" => type,
      "section_id" => section_id,
      "parent_cut_id" => parent_cut_id,
      "image_sha256" => sha,
      "still_camera_spec" => spec,
      "still_camera_binding" => {
        "source_json_pointer" => pointer,
        "source_value_sha256" => IdolStoryboardCollectedAngleContract.value_sha256(spec)
      },
      "geometry_projection_sha256" => IdolStoryboardCollectedAngleContract.geometry_projection_sha(spec)
    }
  end

  def rebind_expected(document, images)
    expected = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    by_cut = images.to_h { |image| [image["cut_id"], image] }
    expected.each do |row|
      source = by_cut[row["cut_id"]]
      next unless source

      row["image_sha256"] = source["image_sha256"].to_s
    end
    expected
  end

  def rebind_bindings!(images, document)
    expected = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    by_cut = expected.to_h { |row| [row["cut_id"], row] }
    images.each do |image|
      row = by_cut[image["cut_id"]]
      next unless row

      image["still_camera_binding"] = row["still_camera_binding"]
      image["geometry_projection_sha256"] = row["geometry_projection_sha256"]
    end
    images
  end

  def complete_review(images, result: "differs", exception: nil, verdict: "pass", generated_pixel_closure: nil, incomplete_pixel_bindings: nil)
    distinct = IdolStoryboardCollectedAngleContract.distinct_images(images)
    pairs = distinct.combination(2).map do |left, right|
      {
        "left_cut_id" => left["cut_id"],
        "right_cut_id" => right["cut_id"],
        "left_image_sha256" => left["image_sha256"],
        "right_image_sha256" => right["image_sha256"],
        "same_image_exact_carry" => false,
        "left_geometry_projection_sha256" => left.fetch("geometry_projection_sha256"),
        "right_geometry_projection_sha256" => right.fetch("geometry_projection_sha256"),
        "shot_scale_not_used_as_angle_proof" => true,
        "contextual_visual_review" => "Full-storyboard pixel and geometry inspection of both stills, including non-adjacent members of the collection.",
        "declared_angle_difference_result" => result,
        "founder_exception" => exception
      }
    end
    review = {
      "contract_version" => IdolStoryboardCollectedAngleContract::CONTRACT_VERSION,
      "scope" => IdolStoryboardCollectedAngleContract::SCOPE,
      "automatic_creative_pass" => false,
      "distinct_images" => distinct.map { |row| row.slice("cut_id", "production_cut_type", "image_sha256", "still_camera_binding", "geometry_projection_sha256") },
      "pairs" => pairs,
      "contextual_full_storyboard_read" => "Compared every distinct production still on the planning/production storyboard."
    }
    review["generated_pixel_closure"] = generated_pixel_closure unless generated_pixel_closure.nil?
    review["incomplete_pixel_bindings"] = incomplete_pixel_bindings unless incomplete_pixel_bindings.nil?
    [review, verdict]
  end

  def test_complete_full_collection_review_is_structurally_valid
    left = image("C01", "official_core", "waist height", "lateral three-quarter rear view", "a" * 64)
    right = image("BC01_OVERHEAD", "branch", "two meters above the guide", "orthographic overhead", "b" * 64)
    images = [left, right]
    document = document_with(images)
    # Repair branch pointer to the actual compiled index.
    images[1]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    review, verdict = complete_review(images)
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "camera_diversity_review"
    )
    assert_empty errors, errors.join("\n")
  end

  def test_adjacent_only_pairs_are_incomplete
    images = [
      image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64),
      image("BC01_ACTION", "branch", "waist height", "rear three-quarter", "b" * 64),
      image("BC01_OVERHEAD", "branch", "overhead", "top-down", "c" * 64)
    ]
    document = document_with(images)
    document["master_storyboard"][0]["compile_seed"]["branch_cuts"] = [
      {"branch_cut_id" => "BC01_ACTION", "still_camera_spec" => images[1]["still_camera_spec"], "expected_output" => {"sha256" => images[1]["image_sha256"]}},
      {"branch_cut_id" => "BC01_OVERHEAD", "still_camera_spec" => images[2]["still_camera_spec"], "expected_output" => {"sha256" => images[2]["image_sha256"]}}
    ]
    images[1]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    images[2]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/1/still_camera_spec"
    review, verdict = complete_review(images)
    review["pairs"] = [review["pairs"].first]
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "camera_diversity_review"
    )
    assert errors.any? { |error| error.include?("complete unordered set") }
  end

  def test_fake_founder_exception_id_is_unbound
    left = image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64)
    right = image("BC01_ACTION", "branch", "waist height", "rear three-quarter", "b" * 64)
    images = [left, right]
    document = document_with(images)
    images[1]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    fake = {
      "lock_id" => "LOCK-REPEAT-FRONT",
      "source_path" => "missing-lock.yaml",
      "source_json_pointer" => "/explicit_locks/0",
      "source_value_sha256" => "0" * 64,
      "named_cut_ids" => %w[C01 BC01_ACTION],
      "conflicting_repeat_reason" => "fabricated"
    }
    review, = complete_review(images, result: "founder_lock_hold", exception: fake, verdict: "hold")
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "hold",
      label: "camera_diversity_review"
    )
    assert errors.any? { |error| error.include?("unbound") || error.include?("missing or unbound") }
  end

  def test_bound_founder_exception_still_cannot_pass
    left = image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64)
    right = image("BC01_ACTION", "branch", "waist height", "rear three-quarter", "b" * 64)
    images = [left, right]
    document = document_with(images)
    images[1]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    exception = {
      "lock_id" => "Repeat this exact pair only.",
      "source_path" => "founder-locks.yaml",
      "source_json_pointer" => "/explicit_locks/0",
      "source_value_sha256" => @lock_sha,
      "named_cut_ids" => %w[C01 BC01_ACTION],
      "conflicting_repeat_reason" => "Founder locked this repeat"
    }
    review, = complete_review(images, result: "founder_lock_hold", exception: exception, verdict: "pass")
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "camera_diversity_review"
    )
    assert errors.any? { |error| error.include?("cannot close camera_diversity_review as pass") }
  end

  def test_declared_same_angle_cannot_pass_without_founder_hold
    left = image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64)
    right = image("BC01_ACTION", "branch", "waist height", "rear three-quarter", "b" * 64)
    images = [left, right]
    document = document_with(images)
    images[1]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    review, = complete_review(images, result: "same", verdict: "pass")
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "camera_diversity_review"
    )
    assert errors.any? { |error| error.include?("same-angle pair cannot close as pass") }
  end

  def test_exact_carry_same_sha_is_one_image
    shared = "a" * 64
    images = [
      image("C01", "official_core", "waist height", "rear three-quarter", shared),
      image("BC01_ACTION", "branch", "waist height", "rear three-quarter", shared)
    ]
    distinct = IdolStoryboardCollectedAngleContract.distinct_images(images)
    assert_equal 1, distinct.length
    assert_empty IdolStoryboardCollectedAngleContract.expected_pair_keys(images)
  end

  def test_stale_generated_image_hash_is_incomplete
    left = image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64)
    right = image("BC01_ACTION", "branch", "overhead", "top-down", "b" * 64)
    images = [left, right]
    document = document_with(images)
    images[1]["still_camera_binding"]["source_json_pointer"] = "/master_storyboard/0/compile_seed/branch_cuts/0/still_camera_spec"
    review, verdict = complete_review(images)
    expected = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    expected[1]["image_sha256"] = "c" * 64
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: expected,
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "pixel_review"
    )
    assert errors.any? { |error| error.include?("image_sha256 differs") || error.include?("exact-cover") }
  end

  def test_missing_review_is_incomplete
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: nil,
      expected_images: [],
      document: {},
      root: @root,
      parent_verdict: "pass",
      label: "camera_diversity_review"
    )
    assert_includes errors, "camera_diversity_review collected_image_camera_angle_review is missing"
  end

  def test_planning_review_cannot_claim_generated_pixel_closure
    left = image("C01", "official_core", "waist height", "lateral three-quarter rear view", "a" * 64)
    right = image("BC01_OVERHEAD", "branch", "two meters above the guide", "orthographic overhead", "b" * 64)
    images = [left, right]
    document = document_with(images)
    rebind_bindings!(images, document)
    review, verdict = complete_review(images, generated_pixel_closure: true)
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: IdolStoryboardCollectedAngleContract.storyboard_production_images(document),
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "camera_diversity_review"
    )
    assert errors.any? { |error| error.include?("planning review cannot claim generated_pixel_closure") }
  end

  def test_source_value_sha256_must_hash_pointer_target_not_geometry_projection
    left = image("C01", "official_core", "waist height", "lateral three-quarter rear view", "a" * 64)
    right = image("BC01_OVERHEAD", "branch", "two meters above the guide", "orthographic overhead", "b" * 64)
    left["still_camera_spec"] = left["still_camera_spec"].merge(
      "shot_scale_distance" => "medium-long shot",
      "depth_design" => "layered corridor"
    )
    images = [left, right]
    document = document_with(images)
    rebind_bindings!(images, document)
    review, verdict = complete_review(images)
    geometry_only = IdolStoryboardCollectedAngleContract.geometry_projection_sha(left["still_camera_spec"])
    refute_equal images[0].dig("still_camera_binding", "source_value_sha256"), geometry_only
    review["distinct_images"][0]["still_camera_binding"]["source_value_sha256"] = geometry_only
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "camera_diversity_review"
    )
    assert errors.any? { |error| error.include?("must hash the exact pointer target, not a geometry projection") }
  end

  def test_storyboard_production_images_leaves_branch_sha_empty_until_generated_rebind
    left = image("C01", "official_core", "waist height", "lateral three-quarter rear view", "a" * 64)
    right = image("BC01_OVERHEAD", "branch", "two meters above the guide", "orthographic overhead", "b" * 64)
    document = document_with([left, right])
    produced = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    branch = produced.find { |row| row["production_cut_type"] == "branch" }
    assert_equal "", branch["image_sha256"]
    assert_equal "S01", produced.map { |row| row["section_id"] }.uniq.join
  end

  def two_section_images
    [
      image("C01", "official_core", "waist height", "lateral three-quarter rear view", "a" * 64, section_id: "S01"),
      image("BC01_OVERHEAD", "branch", "two meters above the guide", "orthographic overhead", "b" * 64, section_id: "S01", parent_cut_id: "C01"),
      image("C02", "official_core", "eye-level", "frontal facing", "c" * 64, section_id: "S02"),
      image("BC02_PROFILE", "branch", "knee-height", "profile facing", "d" * 64, section_id: "S02", parent_cut_id: "C02")
    ]
  end

  def test_section_scoped_generated_pixel_review_does_not_author_other_sections
    images = two_section_images
    document = document_with(images)
    rebind_bindings!(images, document)
    expected = IdolStoryboardCollectedAngleContract.images_for_section(
      IdolStoryboardCollectedAngleContract.storyboard_production_images(document),
      "S01"
    )
    s01 = images.select { |image| image["section_id"] == "S01" }
    expected.each do |row|
      source = s01.find { |image| image["cut_id"] == row["cut_id"] }
      row["image_sha256"] = source["image_sha256"]
    end
    review, = complete_review(s01, generated_pixel_closure: true, incomplete_pixel_bindings: [])
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: expected,
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "S01 collected_image_camera_angle_pixel_review",
      require_generated_pixels: true
    )
    assert_empty errors, errors.join("\n")
    refute_includes review["distinct_images"].map { |row| row["cut_id"] }, "C02"
    refute_includes review["distinct_images"].map { |row| row["cut_id"] }, "BC02_PROFILE"
  end

  def test_whole_board_blank_out_of_scope_hashes_cannot_claim_generated_pixel_closure
    images = two_section_images
    document = document_with(images)
    rebind_bindings!(images, document)
    expected = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    expected.each do |row|
      next unless row["section_id"] == "S01"

      source = images.find { |image| image["cut_id"] == row["cut_id"] }
      row["image_sha256"] = source["image_sha256"]
    end
    review_images = images.map do |image|
      copy = image.dup
      copy["image_sha256"] = "" if image["section_id"] == "S02" && image["production_cut_type"] == "branch"
      copy
    end
    review, = complete_review(review_images, generated_pixel_closure: true, incomplete_pixel_bindings: [])
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: expected,
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "S01 collected_image_camera_angle_pixel_review",
      require_generated_pixels: true
    )
    assert errors.any? { |error| error.include?("cannot claim generated-pixel review") || error.include?("cannot remain incomplete") }
  end

  def test_passed_section_review_with_blank_out_of_scope_hashes_must_declare_incomplete_and_still_cannot_pass
    images = two_section_images
    document = document_with(images)
    rebind_bindings!(images, document)
    expected = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    expected.each do |row|
      next unless row["section_id"] == "S01"

      source = images.find { |image| image["cut_id"] == row["cut_id"] }
      row["image_sha256"] = source["image_sha256"]
    end
    review_images = images.map do |image|
      copy = image.dup
      copy["image_sha256"] = "" if image["section_id"] == "S02" && image["production_cut_type"] == "branch"
      copy
    end
    review, = complete_review(
      review_images,
      generated_pixel_closure: false,
      incomplete_pixel_bindings: ["BC02_PROFILE"]
    )
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: expected,
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "S01 collected_image_camera_angle_pixel_review",
      require_generated_pixels: true
    )
    assert errors.any? { |error| error.include?("passed generated-pixel review cannot remain incomplete") }
  end

  def test_one_section_review_that_authors_another_section_fails_exact_cover
    images = two_section_images
    document = document_with(images)
    rebind_bindings!(images, document)
    expected = IdolStoryboardCollectedAngleContract.images_for_section(
      IdolStoryboardCollectedAngleContract.storyboard_production_images(document),
      "S01"
    )
    expected.each do |row|
      source = images.find { |image| image["cut_id"] == row["cut_id"] }
      row["image_sha256"] = source["image_sha256"]
    end
    review, = complete_review(images, generated_pixel_closure: true, incomplete_pixel_bindings: [])
    errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: expected,
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "S01 collected_image_camera_angle_pixel_review",
      require_generated_pixels: true
    )
    assert errors.any? { |error| error.include?("exact-cover") }
  end

  def test_lock_id_presence_is_exact_not_substring
    sentence = "Repeat this exact pair only."
    structured = {
      "lock_id" => "LOCK-REPEAT-PAIR",
      "verbatim" => sentence,
      "scope" => "camera_pair_C01_BC01_ACTION",
      "source_locator" => "founder-locks.yaml"
    }
    refute IdolStoryboardCollectedAngleContract.lock_id_present_in_bound_source?(sentence, "Repeat")
    refute IdolStoryboardCollectedAngleContract.lock_id_present_in_bound_source?(structured, "LOCK")
    refute IdolStoryboardCollectedAngleContract.lock_id_present_in_bound_source?(structured, "Repeat")
    assert IdolStoryboardCollectedAngleContract.lock_id_present_in_bound_source?(sentence, sentence)
    assert IdolStoryboardCollectedAngleContract.lock_id_present_in_bound_source?(structured, "LOCK-REPEAT-PAIR")
    assert IdolStoryboardCollectedAngleContract.lock_id_present_in_bound_source?(structured, sentence)
  end

  def test_omitted_or_empty_declared_geometry_projection_sha256_cannot_pass_via_expected_fill
    left = image("C01", "official_core", "waist height", "lateral three-quarter rear view", "a" * 64)
    right = image("BC01_OVERHEAD", "branch", "two meters above the guide", "orthographic overhead", "b" * 64)
    images = [left, right]
    document = document_with(images)
    rebind_bindings!(images, document)
    review, verdict = complete_review(images)
    omitted = JSON.parse(JSON.generate(review))
    omitted["distinct_images"][0].delete("geometry_projection_sha256")
    omitted_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: omitted,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "camera_diversity_review"
    )
    assert omitted_errors.any? { |error|
      error.include?("C01") && error.include?("geometry_projection_sha256") && error.include?("missing or stale")
    }
    assert omitted_errors.any? { |error|
      error.include?("left_geometry_projection_sha256") && error.include?("missing or stale")
    }

    blank = JSON.parse(JSON.generate(review))
    blank["distinct_images"][0]["geometry_projection_sha256"] = ""
    blank_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: blank,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: verdict,
      label: "camera_diversity_review"
    )
    assert blank_errors.any? { |error|
      error.include?("C01") && error.include?("geometry_projection_sha256") && error.include?("missing or stale")
    }
  end

  def test_founder_lock_substring_collision_is_rejected
    left = image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64)
    right = image("BC01_ACTION", "branch", "waist height", "rear three-quarter", "b" * 64)
    images = [left, right]
    document = document_with(images)
    rebind_bindings!(images, document)
    string_collision = {
      "lock_id" => "Repeat",
      "source_path" => "founder-locks.yaml",
      "source_json_pointer" => "/explicit_locks/0",
      "source_value_sha256" => @lock_sha,
      "named_cut_ids" => %w[C01 BC01_ACTION],
      "conflicting_repeat_reason" => "Founder locked this repeat"
    }
    review, = complete_review(images, result: "founder_lock_hold", exception: string_collision, verdict: "hold")
    string_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "hold",
      label: "camera_diversity_review"
    )
    assert string_errors.any? { |error| error.include?("lock_id is not present in the bound Founder source") }

    lock = {
      "lock_id" => "LOCK-REPEAT-PAIR",
      "verbatim" => "Repeat this exact pair only.",
      "scope" => "camera_pair_C01_BC01_ACTION",
      "source_locator" => "founder-locks.yaml"
    }
    @root.join("structured-locks.json").write(JSON.generate({"locks" => [lock]}))
    structured_collision = {
      "lock_id" => "LOCK",
      "source_path" => "structured-locks.json",
      "source_json_pointer" => "/locks/0",
      "source_value_sha256" => IdolStoryboardCollectedAngleContract.value_sha256(lock),
      "named_cut_ids" => %w[C01 BC01_ACTION],
      "conflicting_repeat_reason" => "Founder locked this repeat"
    }
    structured_review, = complete_review(images, result: "founder_lock_hold", exception: structured_collision, verdict: "hold")
    structured_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: structured_review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "hold",
      label: "camera_diversity_review"
    )
    assert structured_errors.any? { |error| error.include?("lock_id is not present in the bound Founder source") }
  end

  def test_structured_founder_lock_id_and_verbatim_bind_and_still_cannot_pass
    left = image("C01", "official_core", "waist height", "rear three-quarter", "a" * 64)
    right = image("BC01_ACTION", "branch", "waist height", "rear three-quarter", "b" * 64)
    images = [left, right]
    document = document_with(images)
    rebind_bindings!(images, document)
    lock = {
      "lock_id" => "LOCK-REPEAT-PAIR",
      "verbatim" => "Repeat this exact pair only.",
      "scope" => "camera_pair_C01_BC01_ACTION",
      "source_locator" => "founder-locks.yaml"
    }
    @root.join("structured-locks.json").write(JSON.generate({"locks" => [lock]}))
    exception = {
      "lock_id" => "LOCK-REPEAT-PAIR",
      "source_path" => "structured-locks.json",
      "source_json_pointer" => "/locks/0",
      "source_value_sha256" => IdolStoryboardCollectedAngleContract.value_sha256(lock),
      "named_cut_ids" => %w[C01 BC01_ACTION],
      "conflicting_repeat_reason" => "Founder locked this repeat"
    }
    hold_review, = complete_review(images, result: "founder_lock_hold", exception: exception, verdict: "hold")
    hold_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: hold_review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "hold",
      label: "camera_diversity_review"
    )
    assert_empty hold_errors, hold_errors.join("\n")

    pass_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: hold_review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "pass",
      label: "camera_diversity_review"
    )
    assert pass_errors.any? { |error| error.include?("cannot close camera_diversity_review as pass") }
    refute pass_errors.any? { |error| error.include?("lock_id is not present") }

    verbatim_exception = exception.merge("lock_id" => lock["verbatim"])
    verbatim_review, = complete_review(images, result: "founder_lock_hold", exception: verbatim_exception, verdict: "hold")
    verbatim_errors = IdolStoryboardCollectedAngleContract.validate_review(
      review: verbatim_review,
      expected_images: rebind_expected(document, images),
      document: document,
      root: @root,
      parent_verdict: "hold",
      label: "camera_diversity_review"
    )
    assert_empty verbatim_errors, verbatim_errors.join("\n")
  end
end
