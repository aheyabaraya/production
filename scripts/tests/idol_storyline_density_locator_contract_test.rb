# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_storyline_density_locator_contract"

class IdolStorylineDensityLocatorContractTest < Minitest::Test
  CLI = Pathname.new(__dir__).join("..", "idol_validate_storyline_density_locators.rb")

  def setup
    @root = Pathname.new(Dir.mktmpdir("density-locator-"))
    @story = @root.join("research", "pre00-storyline-original.md")
    @story.dirname.mkpath
    @story.write("She stays at the pillar while the gold invitation waits.\n")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && @root.exist?
  end

  def sheet(overrides = {})
    IdolStorylineDensityLocatorContract.complete_sheet(
      "research/pre00-storyline-original.md"
    ).merge(overrides)
  end

  def write_sheet!(payload = sheet, path: sibling_path)
    path.write(YAML.dump(payload))
    path
  end

  def sibling_path
    @story.sub_ext(".density-locators.yaml")
  end

  def original_text
    "She stays at the pillar while the gold invitation waits.\n"
  end

  def original_sha
    Digest::SHA256.hexdigest(original_text)
  end

  def expanded_text
    "#{original_text.strip} Front Planning plants MJ01 as the governing pillar event.\n"
  end

  def expanded_sha
    Digest::SHA256.hexdigest(expanded_text)
  end

  def front_document(overrides = {})
    original = {
      "version_id" => "PRE00_STORYLINE_V001",
      "full_storyline_text" => original_text,
      "full_storyline_text_sha256" => original_sha
    }
    expansion = {
      "version_id" => "FP_STORYLINE_V001",
      "parent_version_id" => "PRE00_STORYLINE_V001",
      "parent_full_storyline_text_sha256" => original_sha,
      "full_storyline_text" => expanded_text,
      "full_storyline_text_sha256" => expanded_sha
    }
    {
      "schema_version" => "front-planning-readiness.v17",
      "storyline_lineage" => {
        "pre00_lineage" => {
          "pre00_storyline_original" => original,
          "pre00_storyline_revisions" => []
        },
        "front_planning_revisions" => [expansion],
        "active_version" => {
          "lineage_scope" => "front_planning",
          "version_id" => "FP_STORYLINE_V001",
          "full_storyline_text" => expanded_text,
          "full_storyline_text_sha256" => expanded_sha
        }
      }
    }.merge(overrides)
  end

  def test_complete_locator_sheet_closes
    assert_empty IdolStorylineDensityLocatorContract.validate(@root, sheet)
    assert IdolStorylineDensityLocatorContract.closeable?(@root, sheet)
  end

  def test_empty_passage_is_not_a_close
    broken = sheet
    broken["locators"]["opening"]["passage_locator"] = " "
    errors = IdolStorylineDensityLocatorContract.validate(@root, broken)
    assert_includes errors, "density locator empty passage_locator: opening"
    refute IdolStorylineDensityLocatorContract.closeable?(@root, broken)
  end

  def test_missing_row_is_not_a_close
    broken = sheet
    broken["locators"].delete("place")
    errors = IdolStorylineDensityLocatorContract.validate(@root, broken)
    assert_includes errors, "density locator missing row: place"
  end

  def test_missing_source_file_is_not_a_close
    errors = IdolStorylineDensityLocatorContract.validate(
      @root,
      sheet("source_path" => "research/missing.md")
    )
    assert errors.any? { |error| error.include?("source_path is missing") }
  end

  def test_empty_source_file_is_not_a_close
    @story.write("   \n")
    errors = IdolStorylineDensityLocatorContract.validate(@root, sheet)
    assert_includes errors, "density locator source_path is empty: research/pre00-storyline-original.md"
  end

  def test_markdown_sibling_sheet_closes
    write_sheet!
    errors = IdolStorylineDensityLocatorContract.close_artifact(@root, @story, stage: "pre00")
    assert_empty errors
  end

  def test_markdown_without_sibling_is_not_a_close
    errors = IdolStorylineDensityLocatorContract.close_artifact(@root, @story, stage: "pre00")
    assert_includes errors, "density locator sheet missing for research/pre00-storyline-original.md"
  end

  def test_markdown_empty_passage_is_not_a_close
    broken = sheet
    broken["locators"]["afterimage"]["passage_locator"] = ""
    write_sheet!(broken)
    errors = IdolStorylineDensityLocatorContract.close_artifact(@root, @story, stage: "pre00")
    assert_includes errors, "density locator empty passage_locator: afterimage"
  end

  def test_front_planning_restatement_is_not_a_close
    artifact = @root.join("front-planning.yaml")
    document = front_document
    document["storyline_lineage"]["front_planning_revisions"] = []
    document["storyline_lineage"]["active_version"] = {
      "lineage_scope" => "pre00",
      "version_id" => "PRE00_STORYLINE_V001",
      "full_storyline_text" => original_text,
      "full_storyline_text_sha256" => original_sha
    }
    artifact.write(YAML.dump(document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("front-planning.yaml"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    errors = IdolStorylineDensityLocatorContract.close_artifact(
      @root,
      artifact,
      document: document,
      stage: "front_planning"
    )
    assert_includes errors, IdolStorylineDensityLocatorContract::RESTATEMENT_NOT_EXPANDED
  end

  def test_front_planning_empty_descendant_is_not_a_close
    artifact = @root.join("front-planning.yaml")
    document = front_document
    document["storyline_lineage"]["front_planning_revisions"][0]["full_storyline_text"] = " \n"
    artifact.write(YAML.dump(document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("front-planning.yaml"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    errors = IdolStorylineDensityLocatorContract.close_artifact(
      @root,
      artifact,
      document: document,
      stage: "front_planning"
    )
    assert_includes errors, IdolStorylineDensityLocatorContract::RESTATEMENT_EMPTY
  end

  def test_front_planning_same_bytes_as_pre00_is_not_a_close
    artifact = @root.join("front-planning.yaml")
    document = front_document
    document["storyline_lineage"]["front_planning_revisions"][0]["full_storyline_text"] = original_text
    document["storyline_lineage"]["front_planning_revisions"][0]["full_storyline_text_sha256"] = original_sha
    document["storyline_lineage"]["active_version"]["full_storyline_text"] = original_text
    document["storyline_lineage"]["active_version"]["full_storyline_text_sha256"] = original_sha
    artifact.write(YAML.dump(document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("front-planning.yaml"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    errors = IdolStorylineDensityLocatorContract.close_artifact(
      @root,
      artifact,
      document: document,
      stage: "front_planning"
    )
    assert_includes errors, IdolStorylineDensityLocatorContract::RESTATEMENT_BYTES
  end

  def test_front_planning_missing_parent_hash_is_not_a_close
    document = front_document
    document["storyline_lineage"]["front_planning_revisions"][0]["parent_full_storyline_text_sha256"] = ""
    errors = IdolStorylineDensityLocatorContract.lineage_errors(document, "front_planning")
    assert errors.any? { |error| error.include?("missing parent hash") }
  end

  def test_cli_accepts_a_sheet_and_discovers_markdown_sibling
    write_sheet!
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, CLI.to_s, "--root", @root.to_s, write_sheet!.to_s
    )
    assert status.success?, [stderr, stdout].join("\n")
    assert_includes stdout, "storyline-density-locators: pass"

    markdown_stdout, markdown_stderr, markdown_status = Open3.capture3(
      RbConfig.ruby, CLI.to_s, "--root", @root.to_s, "--stage", "pre00", @story.to_s
    )
    assert markdown_status.success?, [markdown_stderr, markdown_stdout].join("\n")
  end

  def test_cli_rejects_markdown_without_sibling
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, CLI.to_s, "--root", @root.to_s, "--stage", "pre00", @story.to_s
    )
    refute status.success?
    assert_includes stderr, "density locator sheet missing"
  end

  def test_yaml_close_requires_source_path_bound_to_the_artifact
    artifact = @root.join("front-planning.yaml")
    document = front_document
    artifact.write(YAML.dump(document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("research/pre00-storyline-original.md"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    errors = IdolStorylineDensityLocatorContract.close_artifact(
      @root,
      artifact,
      document: document,
      stage: "front_planning"
    )
    assert errors.any? { |error| error.include?("does not bind the artifact") }
  end

  def test_yaml_close_accepts_source_path_bound_to_the_artifact
    artifact = @root.join("front-planning.yaml")
    document = front_document
    artifact.write(YAML.dump(document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("front-planning.yaml"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    errors = IdolStorylineDensityLocatorContract.close_artifact(
      @root,
      artifact,
      document: document,
      stage: "front_planning"
    )
    refute errors.any? { |error| error.include?("does not bind the artifact") }
    assert_empty errors
  end

  def test_parent_full_storyline_text_sha256_hashes_documented_text_not_envelope
    expanded = @root.join("research", "fp-storyline.md")
    expanded.write(expanded_text)
    parent = @root.join("research", "parent-lineage.yaml")
    parent.write(
      YAML.dump(
        "pre00_storyline_original" => {
          "version_id" => "PRE00_STORYLINE_V001",
          "full_storyline_text" => original_text,
          "full_storyline_text_sha256" => original_sha
        }
      )
    )
    file_sha = Digest::SHA256.file(parent).hexdigest
    refute_equal original_sha, file_sha

    ok = IdolStorylineDensityLocatorContract.complete_sheet(
      "research/fp-storyline.md",
      parent_source_path: "research/parent-lineage.yaml",
      parent_full_storyline_text_sha256: original_sha
    )
    assert_empty IdolStorylineDensityLocatorContract.validate(@root, ok)

    stale = IdolStorylineDensityLocatorContract.complete_sheet(
      "research/fp-storyline.md",
      parent_source_path: "research/parent-lineage.yaml",
      parent_full_storyline_text_sha256: file_sha
    )
    errors = IdolStorylineDensityLocatorContract.validate(@root, stale)
    assert_includes errors, "density locator parent_full_storyline_text_sha256 is stale"
  end

  def test_parent_same_documented_text_as_source_is_a_restatement
    parent = @root.join("research", "parent-lineage.yaml")
    parent.write(
      YAML.dump(
        "pre00_storyline_original" => {
          "version_id" => "PRE00_STORYLINE_V001",
          "full_storyline_text" => original_text,
          "full_storyline_text_sha256" => original_sha
        }
      )
    )
    sheet = IdolStorylineDensityLocatorContract.complete_sheet(
      "research/pre00-storyline-original.md",
      parent_source_path: "research/parent-lineage.yaml",
      parent_full_storyline_text_sha256: original_sha
    )
    errors = IdolStorylineDensityLocatorContract.validate(@root, sheet)
    assert_includes errors, IdolStorylineDensityLocatorContract::RESTATEMENT_BYTES
  end

  def test_front_planning_copied_text_with_different_declared_hash_is_not_a_close
    artifact = @root.join("front-planning.yaml")
    document = front_document
    fake_sha = Digest::SHA256.hexdigest("not-the-original")
    document["storyline_lineage"]["front_planning_revisions"][0]["full_storyline_text"] = original_text
    document["storyline_lineage"]["front_planning_revisions"][0]["full_storyline_text_sha256"] = fake_sha
    document["storyline_lineage"]["active_version"]["full_storyline_text"] = original_text
    document["storyline_lineage"]["active_version"]["full_storyline_text_sha256"] = fake_sha
    artifact.write(YAML.dump(document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("front-planning.yaml"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    errors = IdolStorylineDensityLocatorContract.close_artifact(
      @root,
      artifact,
      document: document,
      stage: "front_planning"
    )
    assert_includes errors, IdolStorylineDensityLocatorContract::RESTATEMENT_BYTES
    assert errors.any? { |error| error.include?("full text hash is stale") }
  end

  def test_lineage_original_declared_hash_must_match_text
    document = front_document
    document["storyline_lineage"]["pre00_lineage"]["pre00_storyline_original"]["full_storyline_text_sha256"] = "a" * 64
    errors = IdolStorylineDensityLocatorContract.lineage_errors(document, "pre00")
    assert_includes errors, "density locator lineage original full text hash is stale"
  end

  def test_in_root_source_symlink_closes
    link = @root.join("research", "story-alias.md")
    File.symlink(@story.basename.to_s, link.to_s)
    errors = IdolStorylineDensityLocatorContract.validate(
      @root,
      IdolStorylineDensityLocatorContract.complete_sheet("research/story-alias.md")
    )
    assert_empty errors
  end

  def test_escaped_source_symlink_is_not_a_close
    outside = Pathname.new(Dir.mktmpdir("density-locator-outside-"))
    begin
      target = outside.join("decoy.md")
      target.write("escaped-decoy-storyline\n")
      link = @root.join("research", "escaped.md")
      File.symlink(target.to_s, link.to_s)
      errors = IdolStorylineDensityLocatorContract.validate(
        @root,
        IdolStorylineDensityLocatorContract.complete_sheet("research/escaped.md")
      )
      assert errors.any? { |error| error.include?("escapes repository root") }
    ensure
      FileUtils.remove_entry(outside) if outside && outside.exist?
    end
  end

  def test_cli_rejects_yaml_sheet_bound_to_a_different_source
    artifact = @root.join("front-planning.yaml")
    artifact.write(YAML.dump(front_document))
    write_sheet!(
      IdolStorylineDensityLocatorContract.complete_sheet("research/pre00-storyline-original.md"),
      path: artifact.sub_ext(".density-locators.yaml")
    )
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, CLI.to_s, "--root", @root.to_s, "--stage", "front_planning", artifact.to_s
    )
    refute status.success?
    assert_includes stderr, "does not bind the artifact"
  end

  def test_missing_source_under_logical_and_canonical_tmp_root_is_missing_not_escape
    logical = Pathname.new(@root.to_s)
    canonical = @root.realpath
    logical_errors = IdolStorylineDensityLocatorContract.validate(
      logical,
      sheet("source_path" => "research/missing.md")
    )
    assert logical_errors.any? { |error| error.include?("source_path is missing") }
    refute logical_errors.any? { |error| error.include?("escapes repository root") }
    canonical_errors = IdolStorylineDensityLocatorContract.validate(
      canonical,
      sheet("source_path" => "research/missing.md")
    )
    assert canonical_errors.any? { |error| error.include?("source_path is missing") }
    refute canonical_errors.any? { |error| error.include?("escapes repository root") }
  end
end
