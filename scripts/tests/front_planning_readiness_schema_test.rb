# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require "open3"
require "pathname"
require "yaml"
require_relative "support/active_mv_fixture"
require_relative "../lib/idol_kinetic_slot_sheet_contract"

class FrontPlanningReadinessSchemaTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_front_planning_readiness.rb")
  STATE_CHECK = ROOT.join("scripts", "idol_harness_state_check.rb")
  ACTIVE_SCHEMA = ROOT.join("schemas", "front-planning-readiness.schema.json")
  LEGACY_SCHEMA = ROOT.join("schemas", "front-planning-readiness-v16-legacy.schema.json")
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = ROOT.join("scripts", "idol-video-python")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_active_v17_fixture_passes
    assert_valid
  end

  def test_new_front_planning_cannot_close_without_a_density_locator_sheet
    sibling = @fixture.front_path.sub_ext(".density-locators.yaml")
    sibling.delete
    assert_invalid("density locator sheet missing")
  end

  def test_new_front_planning_cannot_close_without_a_selected_major_slot_sheet
    IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01").delete
    assert_invalid("kinetic slot sheet missing for MJ01")
  end

  def test_new_front_planning_cannot_close_with_unbound_sequence_or_key_screen_ids
    path = IdolKineticSlotSheetContract.sheet_path_for(@fixture.front_path, "MJ01")
    sheet = YAML.safe_load(path.read, aliases: true)
    sheet["sequence_evidence"]["sequence_unit_ids"] = ["SEQU_REF_04"]
    path.write(YAML.dump(sheet))
    assert_invalid("not bound to selected Sequence Composition")

    sheet["sequence_evidence"]["sequence_unit_ids"] = ["SEQU_REF_01"]
    sheet["key_screen_inheritances"][0]["key_screen_id"] = "KS_MJ01_A"
    path.write(YAML.dump(sheet))
    assert_invalid("Key Screen KS_MJ01_A does not resolve on that Major")
  end

  def test_v16_is_rejected_for_new_authoring_but_readable_only_through_frozen_legacy_schema
    mutate do |document|
      document["schema_version"] = "front-planning-readiness.v16"
      document.delete("creative_review_graph")
      document.fetch("creative_experiment").delete("selected_route_storyline_binding")
      document.dig("reference_connection_research", "reference_units").each do |unit|
        unit.delete("connection_quality_proof")
      end
      document.dig("major_visual_key_screen_workflow", "key_screen_authority").replace(
        "the_assigned_overall_mv_director_codex_or_grok_authors_and_quality_checks_all_key_screen_anchors_unless_a_founder_direct_update_replaces_named_fields"
      )
      document.fetch("section_plan").each do |section|
        section.fetch("major_scene_flow").each do |major|
          major.fetch("key_screen_anchors").each do |anchor|
            anchor["authoring_owner"] = "founder_selected_overall_mv_director_model"
          end
        end
      end
      document.fetch("major_scene_catalog").each do |major|
        major.dig("sequence_composition_candidate_set", "candidates").each do |candidate|
          candidate.delete("sequence_motion_analysis_binding")
        end
      end
    end

    assert_invalid("only front-planning-readiness.v17 is active")
    legacy_stdout, legacy_stderr, legacy_status = run_schema_validator(LEGACY_SCHEMA)
    assert legacy_status.success?, [legacy_stderr, legacy_stdout].join("\n")
    active_stdout, active_stderr, active_status = run_schema_validator(ACTIVE_SCHEMA)
    refute active_status.success?, [active_stderr, active_stdout].join("\n")
  end

  def test_routes_must_be_exactly_fp_a_b_c_in_order
    mutate { |document| document["candidate_routes"].reverse! }
    assert_invalid("exactly ordered FP-A, FP-B, and FP-C")
  end

  def test_selected_route_storyline_binding_is_required
    mutate { |document| document.fetch("creative_experiment").delete("selected_route_storyline_binding") }
    assert_invalid("selected_route_storyline_binding")
  end

  def test_selected_route_storyline_binding_must_resolve_the_selected_route
    mutate do |document|
      document.dig("creative_experiment", "selected_route_storyline_binding")["candidate_route_storyline_json_pointer"] =
        "/candidate_routes/1/complete_storyline_version"
    end
    assert_invalid("must point to /candidate_routes/0/complete_storyline_version")
  end

  def test_exact_selected_route_relation_rejects_an_unrelated_active_storyline
    mutate do |document|
      route_version = document.dig("candidate_routes", 0, "complete_storyline_version")
      route_version["full_storyline_text"] = "A materially different complete route storyline."
      route_version["full_storyline_text_sha256"] = Digest::SHA256.hexdigest(route_version.fetch("full_storyline_text"))
      document.dig("creative_experiment", "selected_route_storyline_binding")["candidate_route_storyline_value_sha256"] = value_sha(route_version)
    end
    assert_invalid("exact-selected route relation requires the active full storyline text to match the selected route")
  end

  def test_connection_quality_proof_is_required
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0).delete("connection_quality_proof")
    end
    assert_invalid("connection_quality_proof")
  end

  def test_connection_quality_proof_rejects_an_empty_required_field
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0, "connection_quality_proof")["named_section_need"] = ""
    end
    assert_invalid("named_section_need")
  end

  def test_connection_quality_proof_pointer_must_resolve_its_exact_index_row
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0, "connection_quality_proof")["reference_working_index_json_pointer"] = "/rows/1"
    end
    assert_invalid("pointer resolves a different Reference Working Index row")
  end

  def test_connection_quality_proof_index_row_hash_must_be_fresh
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0, "connection_quality_proof")["reference_working_index_row_value_sha256"] = "0" * 64
    end
    assert_invalid("Reference Working Index row hash is stale")
  end

  def test_sequence_unit_is_exact_five_at_exact_one_second
    mutate do |document|
      unit = document.dig("reference_connection_research", "reference_units", 0, "sequence_unit")
      unit["declared_cadence_seconds"] = 3
    end
    assert_invalid("declared_cadence_seconds")
  end

  def test_sequence_composition_candidates_are_two_to_four
    mutate do |document|
      document.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates").pop
    end
    assert_invalid("is too short")
  end

  def test_sequence_composition_candidates_cannot_repeat_the_same_sequence_unit_set
    mutate do |document|
      candidates = document.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates")
      candidates[1]["typed_sequence_unit_ids"] = candidates[0].fetch("typed_sequence_unit_ids").dup
    end
    assert_invalid("must not repeat an exact Sequence Unit set")
  end

  def test_core_visual_candidates_are_two_to_four_actual_stills
    mutate { |document| document.dig("core_visual_candidate_sets", 0, "candidates").pop }
    assert_invalid("is too short")
  end

  def test_core_visual_candidates_cannot_repeat_an_identical_file_binding
    mutate do |document|
      candidates = document.dig("core_visual_candidate_sets", 0, "candidates")
      candidates[1]["actual_path"] = candidates[0].fetch("actual_path")
      candidates[1]["sha256"] = candidates[0].fetch("sha256")
    end
    assert_invalid("must not repeat an identical path/SHA-256")
  end

  def test_new_front_planning_must_expand_pre00_instead_of_restating_it
    mutate do |document|
      original = document.dig("storyline_lineage", "pre00_lineage", "pre00_storyline_original")
      document.dig("storyline_lineage")["front_planning_revisions"] = []
      document.dig("storyline_lineage")["active_version"] = {
        "lineage_scope" => "pre00",
        "version_id" => original.fetch("version_id"),
        "version_json_pointer" => "/storyline_lineage/pre00_lineage/pre00_storyline_original",
        "full_storyline_text" => original.fetch("full_storyline_text"),
        "full_storyline_text_sha256" => original.fetch("full_storyline_text_sha256")
      }
      density = document.dig("storyline_lineage", "contextual_density_review")
      density["reviewed_version_id"] = original.fetch("version_id")
      density["reviewed_full_storyline_text_sha256"] = original.fetch("full_storyline_text_sha256")
    end
    assert_invalid("pre00_storyline_not_expanded")
  end

  def test_same_sequence_unit_frames_cannot_fill_the_core_hypothesis_floor
    mutate do |document|
      candidates = document.dig("core_visual_candidate_sets", 0, "candidates")
      candidates[0]["source_identity"] = "SU-OP-CLAIM frame 1"
      candidates[1]["source_identity"] = "SU-OP-CLAIM frame 3"
    end
    assert_invalid("same_event_anchor_counted_as_hypothesis_floor")
  end

  def test_three_cores_on_one_major_hold_without_a_second_counter
    mutate do |document|
      sets = document.fetch("core_visual_candidate_sets")
      third = Marshal.load(Marshal.dump(sets[0]))
      third["candidate_set_id"] = "CVCSET_CS03"
      third["core_slot_id"] = "CS03"
      third["major_scene_id"] = sets[0].fetch("major_scene_id")
      third["candidates"].each_with_index do |row, index|
        row["candidate_id"] = "CVC_CS03_0#{index + 1}"
        row["source_identity"] = "door peak still #{index}"
        row["actual_path"] = "runs/x/stills/door-#{index}.png"
      end
      sets[0]["major_scene_id"] = third["major_scene_id"]
      sets[1]["major_scene_id"] = third["major_scene_id"]
      sets << third
    end
    assert_invalid("third_core_without_new_major")
  end

  def test_same_sequence_unit_cannot_be_counted_as_three_cores
    mutate do |document|
      sets = document.fetch("core_visual_candidate_sets")
      third = Marshal.load(Marshal.dump(sets[0]))
      third["candidate_set_id"] = "CVCSET_CS03"
      third["core_slot_id"] = "CS03"
      third["candidates"].each_with_index do |row, index|
        row["candidate_id"] = "CVC_CS03_0#{index + 1}"
        row["source_identity"] = "SU-OP-CLAIM frame #{index * 2 + 1}"
        row["actual_path"] = "runs/x/SU-OP-CLAIM/frame-0#{index * 2 + 1}.png"
      end
      sets[0]["candidates"].each_with_index do |row, index|
        row["source_identity"] = "SU-OP-CLAIM frame #{index + 1}"
        row["actual_path"] = "runs/x/SU-OP-CLAIM/frame-0#{index + 1}.png"
      end
      sets[1]["candidates"].each_with_index do |row, index|
        row["source_identity"] = "SU-OP-CLAIM frame #{index + 3}"
        row["actual_path"] = "runs/x/SU-OP-CLAIM/frame-0#{index + 3}.png"
      end
      sets << third
    end
    assert_invalid("same_event_sequence_counted_as_three_cores")
  end

  def test_whitespace_front_planning_descendant_is_not_expansion
    mutate do |document|
      blank = " \n"
      blank_sha = Digest::SHA256.hexdigest(blank)
      revision = document.dig("storyline_lineage", "front_planning_revisions", 0)
      revision["full_storyline_text"] = blank
      revision["full_storyline_text_sha256"] = blank_sha
      active = document.dig("storyline_lineage", "active_version")
      active["full_storyline_text"] = blank
      active["full_storyline_text_sha256"] = blank_sha
      density = document.dig("storyline_lineage", "contextual_density_review")
      density["reviewed_full_storyline_text_sha256"] = blank_sha
    end
    assert_invalid("pre00_storyline_not_expanded")
  end

  def test_active_storyline_cannot_restate_pre00_original_bytes
    mutate do |document|
      original = document.dig("storyline_lineage", "pre00_lineage", "pre00_storyline_original")
      text = original.fetch("full_storyline_text")
      sha = original.fetch("full_storyline_text_sha256")
      revision = document.dig("storyline_lineage", "front_planning_revisions", 0)
      revision["full_storyline_text"] = text
      revision["full_storyline_text_sha256"] = sha
      active = document.dig("storyline_lineage", "active_version")
      active["lineage_scope"] = "front_planning"
      active["full_storyline_text"] = text
      active["full_storyline_text_sha256"] = sha
      density = document.dig("storyline_lineage", "contextual_density_review")
      density["reviewed_full_storyline_text_sha256"] = sha
    end
    assert_invalid("pre00_storyline_not_expanded")
  end

  def test_every_selected_material_core_slot_has_a_reference_decision
    mutate { |document| document["core_reference_bindings"].pop }
    assert_invalid("must exact-cover every selected material Core Slot")
  end

  def test_production_scope_may_not_name_an_unknown_screen_node
    mutate { |document| document.dig("production_scopes", 0, "selected_node_ids") << "SPN_UNKNOWN" }
    assert_invalid("names unknown screen progression nodes")
  end

  def test_active_storyline_text_hash_must_match_the_full_text
    mutate do |document|
      document.dig("storyline_lineage", "active_version", "full_storyline_text_sha256").replace("0" * 64)
    end
    assert_invalid("active full storyline text hash is stale")
  end

  def test_reviewed_storyline_descendant_holds_until_sequence_motion_analysis_is_revalidated
    mutate { |document| promote_selected_route_and_add_descendant!(document) }
    assert_invalid("active_storyline_passage_binding value SHA-256 is stale")
  end

  def test_source_pre00_storyline_hash_must_match_the_exact_projected_value
    mutate do |document|
      document.dig("storyline_lineage", "source_pre00_lineage_value_sha256").replace("0" * 64)
    end
    assert_invalid("PRE-00 storyline lineage source hash is stale")
  end

  def test_pre00_title_target_intersection_binding_may_not_drift_in_front_planning
    mutate do |document|
      document.dig("pre00_audience_target_lineage", "title_target_intersection", "value")["selected_target"] = "A broadened generic fandom union"
    end
    assert_invalid("title_target_intersection must exact-copy PRE-00 binding path/hash/value")
  end

  def test_sequence_unit_requires_exactly_five_frames
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0, "sequence_unit", "ordered_frames").pop
    end
    assert_invalid("is too short")
  end

  def test_sequence_unit_requires_contextual_flow_reading
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0, "sequence_unit", "flow_reading")["entry_state"] = ""
    end
    assert_invalid("should be non-empty")
  end

  def test_selected_core_reference_must_exact_copy_its_selected_candidate
    mutate do |document|
      document.dig("core_reference_bindings", 0, "decision", "sha256").replace("0" * 64)
    end
    assert_invalid("must exact-copy selected candidate path and SHA-256")
  end

  def test_reference_unit_must_resolve_to_a_reviewed_working_index_row
    mutate do |document|
      document.dig("reference_connection_research", "reference_units", 0)["reference_working_index_row_id"] = "RWI-MISSING"
    end
    assert_invalid("must resolve to one Reference Working Index row")
  end

  def test_front_planning_content_id_must_match_founder_sequence_control
    mutate { |document| document["content_id"] = "WRONG_CONTENT" }
    assert_invalid("Founder Sequence Control content_id differs from Front Planning")
  end

  def test_malformed_sequence_children_return_json_instead_of_crashing_front_planning
    front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    sequence_path = ROOT.join(front.fetch("founder_sequence_control").fetch("path"))
    original = YAML.safe_load(sequence_path.read, aliases: true)
    [{"story_flow" => "not an object"}, {"reference_plan" => {"references" => [nil]}}].each do |invalid_fields|
      sequence_path.write(YAML.dump(original.merge(invalid_fields)))
      input_bytes = sequence_path.read
      mutate do |document|
        document.fetch("founder_sequence_control")["sha256"] = Digest::SHA256.file(sequence_path).hexdigest
      end
      stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, "--root", ROOT.to_s, "--json", @fixture.front_path.to_s, chdir: ROOT.to_s)
      refute status.success?
      assert stdout.start_with?("{"), "expected a structured validation failure, got: #{stderr}"
      result = JSON.parse(stdout)
      assert_equal false, result.fetch("valid")
      assert_includes result.fetch("errors").join("\n"), "Founder Sequence Control validation failed"
      assert_equal input_bytes, sequence_path.read
    end
  end

  def test_invalid_sequence_reports_root_cause_without_inventing_projection_mismatches
    front = YAML.safe_load(@fixture.front_path.read, aliases: true)
    sequence_path = ROOT.join(front.fetch("founder_sequence_control").fetch("path"))
    sequence = YAML.safe_load(sequence_path.read, aliases: true)
    sequence.fetch("reference_plan").fetch("references").find { |row| row["reference_slot"] == "Z" }["reference_slot"] = "Y"
    source_bytes = YAML.dump(sequence)
    sequence_path.write(source_bytes)
    mutate do |document|
      document.fetch("founder_sequence_control")["sha256"] = Digest::SHA256.file(sequence_path).hexdigest
      document.dig("current_title_visual_identity", "title_key").replace("other-title")
    end
    stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, "--root", ROOT.to_s, "--json", @fixture.front_path.to_s, chdir: ROOT.to_s)
    refute status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal false, result.fetch("valid")
    errors = result.fetch("errors").join("\n")
    assert_includes errors, "exactly one typed Z reference"
    assert_includes errors, "current-title asset_root must equal"
    refute_match(/founder_brief .*must exact-copy|unknown Founder Sequence Control Major|must project every director-ready control Major/, errors)
    assert_equal source_bytes, sequence_path.read
  end

  def test_current_title_key_cannot_point_assets_at_another_title
    mutate { |document| document.dig("current_title_visual_identity", "title_key").replace("other-title") }
    assert_invalid("current-title asset_root must equal")
  end

  def test_required_canonical_storyline_field_cannot_be_missing
    mutate { |document| document.dig("storyline_lineage", "active_version").delete("full_storyline_text") }
    assert_invalid("'full_storyline_text' is a required property")
  end

  def test_one_governing_key_screen_reference_binding_is_valid
    mutate do |document|
      document.fetch("section_plan").each do |section|
        Array(section["major_scene_flow"]).each do |major|
          Array(major["key_screen_anchors"]).each do |key_screen|
            key_screen["reference_function_bindings"] = [key_screen.fetch("reference_function_bindings").first]
          end
        end
      end
    end
    assert_valid
  end

  def test_key_screen_still_requires_one_named_reference_function
    mutate do |document|
      document.dig("section_plan", 0, "major_scene_flow", 0, "key_screen_anchors", 0)["reference_function_bindings"] = []
    end
    assert_invalid("requires at least one named decision-ready reference-function binding")
  end

  def test_key_screen_authority_cannot_reassign_cdd_authorship_and_qa_to_overall
    mutate do |document|
      document.dig("major_visual_key_screen_workflow", "key_screen_authority").replace(
        "the_assigned_overall_mv_director_codex_or_grok_authors_and_quality_checks_all_key_screen_anchors_unless_a_founder_direct_update_replaces_named_fields"
      )
    end
    assert_invalid("key_screen_authority")
  end

  def test_key_screen_authoring_owner_cannot_reassign_cdd_authorship_to_overall
    mutate do |document|
      document.dig("section_plan", 0, "major_scene_flow", 0, "key_screen_anchors", 0)["authoring_owner"] =
        "founder_selected_overall_mv_director_model"
    end
    assert_invalid("authoring_owner")
  end

  def test_pending_founder_decision_is_valid_before_direction_alignment
    mutate do |document|
      document["status"] = "founder_review"
      document.fetch("founder_gate")["decision"] = "pending"
      document.dig("creative_experiment", "founder_decision")["disposition"] = "pending"
      document.dig("creative_experiment", "founder_decision")["note"] = "Awaiting Founder direction alignment."
    end
    assert_valid
  end

  def test_pending_founder_decision_is_rejected_after_direction_alignment
    mutate do |document|
      document.dig("creative_experiment", "founder_decision")["disposition"] = "pending"
    end
    assert_invalid("is inconsistent with Front Planning status")
  end

  def test_final_founder_decision_is_rejected_while_review_is_pending
    mutate do |document|
      document["status"] = "founder_review"
      document.fetch("founder_gate")["decision"] = "pending"
    end
    assert_invalid("is inconsistent with Front Planning status")
  end

  def test_state_check_does_not_reintroduce_fixed_reference_count_failures
    source = STATE_CHECK.read
    refute_includes source, "has fewer than three reviewable reference units"
    refute_includes source, "has fewer than two reference source identities"
    refute_includes source, "has fewer than two directorial/content functions"
    assert_includes source, "exact-five ordered consecutive one-second Sequence Unit per active visual section"
  end

  private

  def promote_selected_route_and_add_descendant!(document)
    original = document.dig("storyline_lineage", "pre00_lineage", "pre00_storyline_original")
    route_version = document.dig("candidate_routes", 0, "complete_storyline_version")
    route_version["full_storyline_text"] = "The selected complete route carries one causal action from opening state to retained afterimage."
    route_version["full_storyline_text_sha256"] = Digest::SHA256.hexdigest(route_version.fetch("full_storyline_text"))
    promotion = storyline_revision(
      id: "FP_STORYLINE_V001",
      parent_id: original.fetch("version_id"),
      parent_sha: original.fetch("full_storyline_text_sha256"),
      text: route_version.fetch("full_storyline_text"),
      trigger: "upstream_conflict_resolution",
      reason: "Exact-promote the Founder-selected complete route into canonical FP lineage."
    )
    descendant_text = "#{promotion.fetch('full_storyline_text')} A reviewed final passage preserves that causal route while clarifying the ending."
    descendant = storyline_revision(
      id: "FP_STORYLINE_V002",
      parent_id: promotion.fetch("version_id"),
      parent_sha: promotion.fetch("full_storyline_text_sha256"),
      text: descendant_text,
      trigger: "founder_revision",
      reason: "Preserve the selected route while applying one reviewed full-text ending clarification."
    )
    document.fetch("storyline_lineage")["front_planning_revisions"] = [promotion, descendant]
    document.fetch("storyline_lineage")["active_version"] = {
      "lineage_scope" => "front_planning",
      "version_id" => descendant.fetch("version_id"),
      "version_json_pointer" => "/storyline_lineage/front_planning_revisions/1",
      "full_storyline_text" => descendant.fetch("full_storyline_text"),
      "full_storyline_text_sha256" => descendant.fetch("full_storyline_text_sha256")
    }
    density = document.dig("storyline_lineage", "contextual_density_review")
    density["reviewed_version_id"] = descendant.fetch("version_id")
    density["reviewed_full_storyline_text_sha256"] = descendant.fetch("full_storyline_text_sha256")
    document.fetch("screen_progression_map")["active_storyline_version_id"] = descendant.fetch("version_id")
    document.fetch("screen_progression_map")["active_storyline_sha256"] = descendant.fetch("full_storyline_text_sha256")
    binding = document.dig("creative_experiment", "selected_route_storyline_binding")
    binding["candidate_route_storyline_value_sha256"] = value_sha(route_version)
    binding["active_storyline_relation"] = "reviewed_full_text_descendant"
    binding["promoted_storyline_revision_json_pointer"] = "/storyline_lineage/front_planning_revisions/0"
    binding["promoted_storyline_revision_value_sha256"] = value_sha(promotion)
    binding["active_storyline_version_id"] = descendant.fetch("version_id")
    binding["active_storyline_full_storyline_text_sha256"] = descendant.fetch("full_storyline_text_sha256")
  end

  def storyline_revision(id:, parent_id:, parent_sha:, text:, trigger:, reason:)
    {
      "version_id" => id,
      "parent_version_id" => parent_id,
      "parent_full_storyline_text_sha256" => parent_sha,
      "full_storyline_text" => text,
      "full_storyline_text_sha256" => Digest::SHA256.hexdigest(text),
      "change_trigger" => trigger,
      "change_reason" => reason,
      "changed_story_passages" => ["One reviewed complete-storyline passage."],
      "preserved_pre00_invariants" => ["Opening condition, causal action, and retained afterimage remain intact."],
      "applied_reference_receipts" => [],
      "authorship_receipt" => {
        "authored_by" => "creative_development_director",
        "authored_at" => "2026-08-14T00:00:00Z",
        "founder_status" => "selected",
        "full_text_revision_not_patch_only" => true
      }
    }
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[source_key])
      end
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def value_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def mutate
    document = YAML.safe_load(@fixture.front_path.read, aliases: true)
    yield document
    @fixture.front_path.write(YAML.dump(document))
  end

  def run_validator
    Open3.capture3("ruby", VALIDATOR.to_s, "--root", ROOT.to_s, @fixture.front_path.to_s, chdir: ROOT.to_s)
  end

  def run_schema_validator(schema)
    Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, schema.to_s, @fixture.front_path.to_s, chdir: ROOT.to_s)
  end

  def assert_valid
    stdout, stderr, status = run_validator
    assert status.success?, [stderr, stdout].join("\n")
    assert_includes stdout, "Front Planning v17"
  end

  def assert_invalid(fragment)
    stdout, stderr, status = run_validator
    refute status.success?, [stderr, stdout].join("\n")
    assert_includes [stderr, stdout].join("\n"), fragment
  end
end
