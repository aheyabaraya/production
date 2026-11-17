# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

class ValidateGraphSectionCohortMapTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_graph_section_cohort_map.rb")
  FIXTURES = ROOT.join("scripts", "tests", "fixtures", "graph-authority")

  VALID_MAPS = {
    "valid-cohort-map-one-section.json" => [1],
    "valid-cohort-map-one-section-production.json" => [1],
    "valid-cohort-map-4.json" => [2, 2],
    "valid-cohort-map-5.json" => [2, 3],
    "valid-cohort-map-6.json" => [3, 3],
    "valid-cohort-map-7.json" => [2, 2, 3],
    "valid-cohort-map-8.json" => [2, 3, 3],
    "valid-cohort-map-9.json" => [3, 3, 3]
  }.freeze

  def test_valid_partition_fixtures_pass
    VALID_MAPS.each do |name, sizes|
      stdout, stderr, status = validate(FIXTURES.join(name))
      assert status.success?, [name, stdout, stderr].join("\n")
      assert_includes stdout, "graph-section-cohort-map: pass"
      assert_includes stdout, "partition [#{sizes.join(',')}]"
      document = JSON.parse(FIXTURES.join(name).read)
      actual = document.fetch("cohorts").map { |cohort| cohort.fetch("section_ids").length }
      assert_equal sizes, actual, name
      json_stdout, json_stderr, json_status = Open3.capture3(
        "ruby",
        VALIDATOR.to_s,
        "--json",
        FIXTURES.join(name).to_s,
        chdir: ROOT.to_s
      )
      assert json_status.success?, [name, json_stdout, json_stderr].join("\n")
      assert_equal sizes, JSON.parse(json_stdout).fetch("partition"), name
    end
  end

  def test_production_map_cross_checks_lineage
    stdout, stderr, status = Open3.capture3(
      "ruby",
      VALIDATOR.to_s,
      "--lineage",
      FIXTURES.join("valid-lineage-production.json").to_s,
      FIXTURES.join("valid-cohort-map-5.json").to_s,
      chdir: ROOT.to_s
    )
    assert status.success?, [stdout, stderr].join("\n")
  end

  def test_production_map_rejects_cdd_reviewer_session_not_bound_to_active_v_ci_writer
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts").first.fetch("cdd_reviewer")["session_id"] = "UNRELATED_CDD_SESSION"
    _stdout, stderr, status = validate_document_with_lineage(document)
    refute status.success?
    assert_includes stderr, "CDD reviewer session must exact-bind the active writer"
  end

  def test_production_map_rejects_cdd_reviewer_logical_lineage_drift
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts").first.fetch("cdd_reviewer")["logical_lineage_id"] = "UNRELATED_LINEAGE"
    _stdout, stderr, status = validate_document_with_lineage(document)
    refute status.success?
    assert_includes stderr, "CDD reviewer logical lineage must exact-bind"
  end

  def test_rejects_overlapping_sections
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[1].fetch("section_ids")[0] = "S02"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "section S02 is mapped more than once"
  end

  def test_rejects_unmapped_section
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[1]["section_ids"] = ["S03", "S04"]
    document.fetch("cohorts")[1]["section_output_writers"].reject! { |row| row["section_id"] == "S05" }
    document.fetch("p3_to_v_carry")[1]["exact_section_ids"] = ["S03", "S04"]
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "section S05 is not mapped"
  end

  def test_rejects_singleton_inside_multi_section_title
    document = load_fixture("valid-cohort-map-4.json")
    document.fetch("cohorts")[1]["section_ids"] = ["S03"]
    document.fetch("cohorts")[1]["section_output_writers"].reject! { |row| row["section_id"] == "S04" }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "size must be 2 or 3 except a one-section title"
  end

  def test_rejects_noncontiguous_cohort
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[0]["section_ids"] = ["S01", "S03"]
    document.fetch("p3_to_v_carry")[0]["exact_section_ids"] = ["S01", "S03"]
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "sections are not contiguous"
  end

  def test_rejects_capacity_created_extra_cohorts
    document = load_fixture("valid-cohort-map-4.json")
    extra = Marshal.load(Marshal.dump(document.fetch("cohorts").last))
    extra["section_cohort_id"] = "C3"
    extra["planning_lane_id"] = "planning_p3_c3"
    extra["section_ids"] = ["S04"]
    extra["section_output_writers"] = [
      {"section_id" => "S04", "owner" => "fixture-section-s04-writer", "role" => "section_image_motion_worker"}
    ]
    document.fetch("cohorts")[1]["section_ids"] = ["S03"]
    document.fetch("cohorts")[1]["section_output_writers"].reject! { |row| row["section_id"] == "S04" }
    document.fetch("cohorts") << extra
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/size must be 2 or 3|capacity may not create extra cohorts/, stderr)
  end

  def test_rejects_nonminimal_three_cohorts_for_six_sections
    document = load_fixture("valid-cohort-map-6.json")
    first = document.fetch("cohorts").fetch(0)
    second = document.fetch("cohorts").fetch(1)
    third = Marshal.load(Marshal.dump(second))
    first["section_ids"] = ["S01", "S02"]
    first["section_output_writers"].reject! { |row| row["section_id"] == "S03" }
    second["section_ids"] = ["S03", "S04"]
    second["section_output_writers"] = [
      {"section_id" => "S03", "owner" => "fixture-section-s03-writer", "role" => "section_image_motion_worker"},
      {"section_id" => "S04", "owner" => "fixture-section-s04-writer", "role" => "section_image_motion_worker"}
    ]
    third["section_cohort_id"] = "C3"
    third["planning_lane_id"] = "planning_p3_c3"
    third["cdd_reviewer"]["lane_id"] = "planning_p3_c3"
    third["section_ids"] = ["S05", "S06"]
    third["section_output_writers"] = [
      {"section_id" => "S05", "owner" => "fixture-section-s05-writer", "role" => "section_image_motion_worker"},
      {"section_id" => "S06", "owner" => "fixture-section-s06-writer", "role" => "section_image_motion_worker"}
    ]
    document.fetch("cohorts") << third

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "capacity may not create extra cohorts"
  end

  def test_rejects_nonminimal_four_cohorts_for_eight_sections
    document = load_fixture("valid-cohort-map-8.json")
    base = document.fetch("cohorts")
    base[0]["section_ids"] = ["S01", "S02"]
    base[1]["section_ids"] = ["S03", "S04"]
    base[1]["section_output_writers"].reject! { |row| row["section_id"] == "S05" }
    base[2]["section_ids"] = ["S05", "S06"]
    base[2]["section_output_writers"] = [
      {"section_id" => "S05", "owner" => "fixture-section-s05-writer", "role" => "section_image_motion_worker"},
      {"section_id" => "S06", "owner" => "fixture-section-s06-writer", "role" => "section_image_motion_worker"}
    ]
    fourth = Marshal.load(Marshal.dump(base[2]))
    fourth["section_cohort_id"] = "C4"
    fourth["planning_lane_id"] = "planning_p3_c4"
    fourth["cdd_reviewer"]["lane_id"] = "planning_p3_c4"
    fourth["section_ids"] = ["S07", "S08"]
    fourth["section_output_writers"] = [
      {"section_id" => "S07", "owner" => "fixture-section-s07-writer", "role" => "section_image_motion_worker"},
      {"section_id" => "S08", "owner" => "fixture-section-s08-writer", "role" => "section_image_motion_worker"}
    ]
    document.fetch("cohorts") << fourth

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "capacity may not create extra cohorts"
  end

  def test_rejects_noncanonical_cohort_id_case
    document = load_fixture("valid-cohort-map-4.json")
    document.fetch("cohorts").first["section_cohort_id"] = "c1"

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/section_cohort_id|pattern/i, stderr)
  end

  def test_rejects_missing_section_output_writer
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[0]["section_output_writers"].pop
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "must have exactly one output writer"
  end

  def test_rejects_two_writers_for_one_section
    document = load_fixture("valid-cohort-map-one-section.json")
    document.fetch("cohorts")[0].fetch("section_output_writers") << {
      "section_id" => "S01",
      "owner" => "fixture-section-s01-writer-b",
      "role" => "section_image_motion_worker"
    }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "must have exactly one output writer"
  end

  def test_rejects_missing_cdd_reviewer_owner
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[0]["cdd_reviewer"]["owner"] = ""
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/CDD reviewer|minLength|is too short/i, stderr)
  end

  def test_rejects_cdd_reviewer_lane_drift
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts").first.fetch("cdd_reviewer")["lane_id"] = "section_cluster_v_c2"

    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "CDD reviewer lane must exact-carry"
  end

  def test_rejects_missing_return_recipient
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[0]["return_recipient"]["owner"] = ""
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_match(/return recipient|minLength|is too short/i, stderr)
  end

  def test_rejects_missing_production_carry
    document = load_fixture("valid-cohort-map-5.json")
    document["p3_to_v_carry"] = []
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "P3-Ci to V-Ci cohort carry is missing or inexact"
  end

  def test_rejects_p3_c1_carried_into_v_c2
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("p3_to_v_carry")[0]["production_lane_id"] = "section_cluster_v_c2"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "P3-Ci to V-Ci cohort carry is missing or inexact for C1"
  end

  def test_rejects_overlapping_section_writers_across_cohorts
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("cohorts")[1].fetch("section_output_writers") << {
      "section_id" => "S02",
      "owner" => "fixture-section-s02-writer-overlap",
      "role" => "section_image_motion_worker"
    }
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "section S02 writer is outside cohort C2"
  end

  def test_rejects_stale_handoff_hash
    document = load_fixture("valid-cohort-map-5.json")
    document.fetch("p3_to_v_carry")[0].fetch("planning_handoff")["sha256"] =
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    _stdout, stderr, status = validate_document(document)
    refute status.success?
    assert_includes stderr, "SHA-256 is stale"
  end

  private

  def load_fixture(name)
    JSON.parse(FIXTURES.join(name).read)
  end

  def validate(path)
    Open3.capture3("ruby", VALIDATOR.to_s, path.to_s, chdir: ROOT.to_s)
  end

  def validate_document(document)
    Dir.mktmpdir("idol-graph-cohort-") do |directory|
      path = Pathname.new(directory).join("document.json")
      path.write(JSON.pretty_generate(document) + "\n")
      validate(path)
    end
  end

  def validate_document_with_lineage(document)
    Dir.mktmpdir("idol-graph-cohort-lineage-") do |directory|
      path = Pathname.new(directory).join("document.json")
      path.write(JSON.pretty_generate(document) + "\n")
      Open3.capture3(
        "ruby", VALIDATOR.to_s,
        "--lineage", FIXTURES.join("valid-lineage-production.json").to_s,
        path.to_s,
        chdir: ROOT.to_s
      )
    end
  end
end
