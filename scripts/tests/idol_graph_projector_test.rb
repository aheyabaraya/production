# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"

require_relative "../idol_graph_projector"
require_relative "../lib/idol_role_context_pack"
require_relative "support/idol_graph_production_review_fixture"

class IdolGraphProjectorTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_graph_projector.rb")
  REGISTRY = ROOT.join("automation", "graph-stage-registry.yaml")
  FIXTURES = ROOT.join("scripts", "tests", "fixtures", "graph")
  PLANNING = FIXTURES.join("positive", "planning-nine-section.yaml")
  HISTORICAL = FIXTURES.join("positive", "historical-legacy.yaml")
  PYTHON = ROOT.join("scripts", "idol-video-python")
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  ERROR = IdolGraphProjector::ContractError

  EXPECTED_STAGE_IDS = %w[
    creative_route_discovery song_direction_design candidate_track_analysis
    audio_screen_motion_map song_production_lock front_planning_integration
    mv_performance_direction mv_storyboard_direction storyboard_review
    image_prompt_compilation image_generation_release_gate branch_cut_generation
    generated_branch_cut_review audio_branch_cut_placement video_motion_direction
    video_playback_review edit_assembly_playback_qc edit_finishing_fx
    master_package_release
  ].freeze

  def test_registry_validates_as_shadow_read_only_without_default_write
    before = REGISTRY.binread
    result = run_script("validate-registry")

    assert result[:status].success?, result[:stderr]
    assert_includes result[:stdout], "19 stages"
    assert_includes result[:stdout], "shadow_read_only"
    assert_includes result[:stdout], "default_writer forbidden"
    assert_includes result[:stdout], "parse-only legacy capsule"
    document = YAML.safe_load(REGISTRY.read, aliases: false)
    assert_equal "idol-graph-stage-registry.v1", document.fetch("schema_version")
    assert_equal "forbidden", document.fetch("default_writer")
    assert_equal "parse_only", document.fetch("legacy_capsule")
    assert_equal EXPECTED_STAGE_IDS, document.fetch("stages").map { |row| row.fetch("stage_id") }
    assert_equal %w[G0 G1 G2 G3 G4], document.fetch("founder_gates").map { |row| row.fetch("gate_id") }
    assert_equal false, document.dig("cohort_policy", "capacity_creates_cohort")
    assert_equal "disjoint_p3_ci_or_v_ci_lanes_within_lower_capacity_and_backpressure", document.dig("studio_execution", "cross_cohort_cdd_parallelism")
    assert_equal "read_only_not_active_writer", document.dig("studio_execution", "successor_before_cas")
    assert_equal true, document.dig("decision_ownership_policy", "one_active_writer_per_lane_stage")
    assert_equal before, REGISTRY.binread
  end

  def test_planning_projection_is_deterministic_and_does_not_author_or_leak_creative_prose
    before = PLANNING.binread
    first = project(PLANNING)
    second = project(PLANNING)
    cli = project_cli(PLANNING)

    assert cli[:status].success?, cli[:stderr]
    assert_equal first, second
    assert_equal first.fetch("projection_digest"), second.fetch("projection_digest")
    assert_equal first, JSON.parse(cli[:stdout])
    assert_equal "pass", first.fetch("status")
    assert_equal "read_only_projection", first.fetch("authority")
    assert_empty first.fetch("hold_reasons")
    refute_includes JSON.generate(first), "FIXTURE_CREATIVE_PROSE_MUST_NOT_LEAK"
    assert_equal before, PLANNING.binread
  end

  def test_six_typed_views_and_promotion_evidence_are_projected
    projection = project(PLANNING)
    views = projection.fetch("views")

    assert_equal %w[
      creative_truth evidence_provenance authority_ownership
      execution_session review_decision provider_capability
    ], views.keys
    views.each_value do |slice|
      assert slice.fetch("node_ids").is_a?(Array)
      assert slice.fetch("edge_ids").is_a?(Array)
    end
    assert_includes views.fetch("creative_truth").fetch("node_ids"), "n_section_s01"
    assert_includes views.fetch("creative_truth").fetch("edge_ids"), "e_storyline_supports_s01"
    assert_includes views.fetch("authority_ownership").fetch("node_ids"), "n_overall"
    assert_includes views.fetch("review_decision").fetch("node_ids"), "n_contextual_judgment_c1"
    assert_includes views.fetch("creative_truth").fetch("edge_ids"), "e_decision_judged_by_context"
    assert_includes views.fetch("authority_ownership").fetch("edge_ids"), "e_judgment_selects_review"
    evidence = projection.fetch("promotion_evidence")
    decision = evidence.find { |row| row.fetch("node_id") == "n_decision_set_c1" }
    refute_nil decision
    assert_equal "n_review_p3_c1", decision.fetch("review_id")
    assert_equal "e_review_promotes_decision", decision.fetch("promotes_edge_id")
    assert_match(/\A[a-f0-9]{64}\z/, decision.fetch("output_hash"))
  end

  def test_nine_section_cohorts_carry_p3_ids_to_v
    projection = project(PLANNING)
    cohorts = projection.fetch("cohorts")

    assert_equal [3, 3, 3], cohorts.fetch("partition").map { |row| row.fetch("size") }
    assert_equal %w[C1 C2 C3], cohorts.fetch("partition").map { |row| row.fetch("cohort_id") }
    assert_equal %w[S01 S02 S03], cohorts.fetch("partition").fetch(0).fetch("section_ids")
    assert_equal %w[S07 S08 S09], cohorts.fetch("partition").fetch(2).fetch("section_ids")
    assert_equal "exact_p3_cohort_id_to_v_cohort", cohorts.fetch("carry_rule")
    p3_ids = cohorts.fetch("planning_p3").map { |row| [row["cohort_id"], row["section_ids"]] }
    v_ids = cohorts.fetch("section_cluster_v").map { |row| [row["cohort_id"], row["section_ids"]] }
    assert_equal p3_ids, v_ids

    active_p3_writers = PLANNING.then { |path| YAML.safe_load(path.read, aliases: false) }.fetch("nodes").select do |node|
      node.fetch("node_class") == "planning_section_cohort_lane" && node.fetch("may_write")
    end
    assert_equal %w[n_p3_c1 n_p3_c2 n_p3_c3], active_p3_writers.map { |node| node.fetch("node_id") }
    assert_equal 3, active_p3_writers.map { |node| node.fetch("scope_id") }.uniq.length
  end

  def test_cohort_partition_examples
    assert_equal [1], IdolGraphProjector::CohortPartitioner.sizes(1)
    assert_equal [2, 2], IdolGraphProjector::CohortPartitioner.sizes(4)
    assert_equal [2, 3], IdolGraphProjector::CohortPartitioner.sizes(5)
    assert_equal [3, 3], IdolGraphProjector::CohortPartitioner.sizes(6)
    assert_equal [2, 2, 3], IdolGraphProjector::CohortPartitioner.sizes(7)
    assert_equal [2, 3, 3], IdolGraphProjector::CohortPartitioner.sizes(8)
    assert_equal [3, 3, 3], IdolGraphProjector::CohortPartitioner.sizes(9)
  end

  def test_six_sections_use_two_canonical_three_section_cohorts
    partition = IdolGraphProjector::CohortPartitioner.partition(%w[S01 S02 S03 S04 S05 S06])

    assert_equal %w[C1 C2], partition.map { |row| row.fetch("cohort_id") }
    assert_equal [3, 3], partition.map { |row| row.fetch("size") }
    assert_equal %w[S01 S02 S03], partition.fetch(0).fetch("section_ids")
    assert_equal %w[S04 S05 S06], partition.fetch(1).fetch("section_ids")
  end

  def test_affected_only_invalidation_preserves_unrelated_sibling
    projection = project(PLANNING)
    query = projection.fetch("invalidation").find { |row| row.fetch("changed_node_id") == "n_major_s01" }

    refute_nil query
    assert_equal ["n_core_s01"], query.fetch("affected_node_ids")
    assert_includes query.fetch("preserved_node_ids"), "n_major_s04"
    refute_includes query.fetch("affected_node_ids"), "n_major_s04"
    assert_equal "invalidates_edges_only", query.fetch("traversal")
  end

  def test_historical_fixture_keeps_parse_only_legacy_pointers
    projection = project(HISTORICAL)

    assert_equal "pass", projection.fetch("status")
    pointers = projection.fetch("legacy_source_pointers")
    refute_empty pointers
    pointers.each do |pointer|
      assert_equal "parse_only", pointer.fetch("capsule")
      assert_equal "automation/harness-stage-registry.yaml", pointer.fetch("path")
      assert_equal "front_planning_integration", pointer.fetch("legacy_id")
    end
    assert_equal [1], projection.dig("cohorts", "partition").map { |row| row.fetch("size") }
  end

  def test_founder_gates_are_exactly_g0_to_g4
    projection = project(PLANNING)
    gates = projection.fetch("founder_gates")

    assert_equal %w[G0 G1 G2 G3 G4], gates.map { |row| row.fetch("gate_id") }
    assert_equal "promoted", gates.find { |row| row["gate_id"] == "G0" }.fetch("state")
    assert_equal "promoted", gates.find { |row| row["gate_id"] == "G1" }.fetch("state")
    assert_equal "planned", gates.find { |row| row["gate_id"] == "G2" }.fetch("state")
    assert_equal "close_founder_gate_g2", projection.fetch("next_legal_actions").fetch(0).fetch("action")
  end

  def test_dual_active_writer_fails_closed
    ledger = load_planning
    primary = node(ledger, "n_p1")
    clone = Marshal.load(Marshal.dump(primary))
    clone["node_id"] = "n_p1_two"
    clone["logical_id"] = "planning_p1_two"
    clone["writer_id"] = "p1_secondary"
    ledger.fetch("nodes") << clone

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/multiple active writers/, error.message)
  end

  def test_missing_promotion_review_fails_closed
    ledger = load_planning
    node(ledger, "n_decision_set_c1").fetch("evidence")["review_id"] = "n_review_g0"

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/no promotes edge from its review/, error.message)
  end

  def test_promoted_output_requires_contextual_judgment
    ledger = load_planning
    ledger.fetch("edges").reject! { |edge| edge["edge_id"] == "e_decision_judged_by_context" }
    ledger.fetch("events").each { |event| Array(event["edge_ids"]).delete("e_decision_judged_by_context") }

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/must have exactly one contextual judged_by edge/, error.message)
  end

  def test_promoted_output_rejects_ineligible_contextual_judgment
    ledger = load_planning
    judgment_node = node(ledger, "n_contextual_judgment_c1")
    judgment_node["judgment_decision"] = "combine_or_correct"
    judgment_node["state"] = "returned"

    error = assert_raises(ERROR) do
      project_document(ledger) do |root|
        path = root.join("evidence", "contextual-judgment.yaml")
        artifact = YAML.safe_load(path.read, aliases: false)
        artifact.fetch("criteria").first["result"] = 2
        artifact["decision"] = "combine_or_correct"
        artifact["next_edge"] = "revise_same_owner"
        artifact["status"] = "draft"
        path.write(YAML.dump(artifact))
        judgment_node.fetch("pointers")["artifact_sha256"] = Digest::SHA256.file(path).hexdigest
        judgment_node.fetch("authorship").fetch("receipt")["value_sha256"] = IdolGraphProjector::Canonical.digest("combine_or_correct")
        edge = ledger.fetch("edges").find { |row| row["edge_id"] == "e_decision_judged_by_context" }
        edge.fetch("authorship").fetch("receipt")["value_sha256"] = IdolGraphProjector::Canonical.digest("combine_or_correct")
      end
    end
    assert_match(/judgment_decision must be "eligible_for_director_review"/, error.message)
  end

  def test_promoted_output_review_must_match_returned_dispatch_reviewer_role
    ledger = load_planning
    review = node(ledger, "n_review_p3_c1")
    review["owner_role"] = "planning_cdd_p3"

    error = assert_raises(ERROR) { project_document(ledger) }

    assert_match(/owner_role against returned Dispatch reviewer/, error.message)
  end

  def test_production_review_projection_preserves_selected_inputs_without_worker_instruction_dump
    with_project_fixture(PLANNING) do |ledger_path|
      root = ledger_path.dirname
      input = JSON.parse(root.join("work/evidence/production-director-review/review-input.json").read)
      pack = YAML.safe_load(root.join(input.dig("worker_role_context_pack", "path")).read, aliases: true)
      assert_equal pack["founder_context"], input["founder_context"]
      assert_equal pack["creative_source_pointers"], input["selected_context_sources"]
      refute input.key?("instruction_slices")
      refute input.key?("provider_binding")
      assert input["inspection_targets"].any?
      assert input["criterion_evidence"].all? { |row| row["evidence_locator"].is_a?(Array) }
    end
  end

  def test_production_review_command_preserves_inputs_and_verifies_the_return
    with_project_fixture(PLANNING) do |ledger_path|
      root = ledger_path.dirname
      directory = root.join("work/evidence/production-director-review")
      input = JSON.parse(directory.join("review-input.json").read)
      output_path = directory.join("command-review-input.json")
      command = [RbConfig.ruby, ROOT.join("scripts/idol_graph_production_review.rb").to_s]
      args = ["project", "--root", root.to_s, "--judgment", input.dig("contextual_judgment", "path"), "--output", output_path.to_s]
      stdout, stderr, status = Open3.capture3(*command, *args)
      assert status.success?, stderr
      assert_equal "projected", JSON.parse(stdout)["status"]
      assert_equal input, JSON.parse(output_path.read)
      bytes = output_path.read
      _stdout, stderr, status = Open3.capture3(*command, *args)
      assert status.success?, stderr
      assert_equal bytes, output_path.read
      stdout, stderr, status = Open3.capture3(*command, "verify", "--root", root.to_s, "--review", directory.join("review-envelope.json").to_s)
      assert status.success?, stderr
      assert_equal false, JSON.parse(stdout)["automatic_creative_pass"]
      blocked_path = directory.join("dangling-output.json")
      File.symlink(directory.join("absent-target.json").to_s, blocked_path)
      _stdout, stderr, status = Open3.capture3(*command, *args[0...-1], blocked_path.to_s)
      refute status.success?
      assert_match(/immutable review input already exists/, stderr)
      refute directory.join("absent-target.json").exist?
    end
  end

  def test_promoted_output_requires_actual_returned_director_review_pointer
    assert_bad_production_review(/Director review envelope|criterion evidence/) do |_root, _ledger, review, _path, _envelope|
      review.delete("pointers")
    end
  end

  def test_promoted_output_rejects_launched_only_director_review
    assert_bad_production_review(/requires a returned Dispatch/) do |root, _ledger, _review, _path, envelope|
      envelope["director_dispatch"] = IdolGraphProductionReviewContract.pointer(root, "work/evidence/production-director-review/director-launched.json")
    end
  end

  def test_promoted_output_rejects_review_by_the_judgment_author_session
    assert_bad_production_review(/independent session/) do |root, _ledger, _review, _path, envelope|
      input = JSON.parse(root.join(envelope.dig("review_input_manifest", "path")).read)
      path = root.join(envelope.dig("director_dispatch", "path"))
      dispatch = JSON.parse(path.read)
      dispatch["output_writer"]["session_id"] = input["author_session_id"]
      path.write(JSON.pretty_generate(dispatch) + "\n")
      envelope["director_dispatch"] = IdolGraphProductionReviewContract.pointer(root, path)
    end
  end

  def test_promoted_output_rejects_uninspected_target_after_all_return_hashes_are_refreshed
    assert_bad_production_review(/omits exact inspection targets/) do |root, _ledger, _review, _path, envelope|
      contract = IdolGraphProductionReviewContract
      input = JSON.parse(root.join(envelope.dig("review_input_manifest", "path")).read)
      output_path = root.join(envelope.dig("review_output", "path"))
      output = JSON.parse(output_path.read)
      output["inspected_artifacts"] = [input["contextual_judgment"].merge("observation" => "Read a report instead of the actual governed output.")]
      output_path.write(JSON.pretty_generate(output) + "\n")
      envelope["review_output"] = contract.pointer(root, output_path)
      dispatch_path = root.join(envelope.dig("director_dispatch", "path"))
      dispatch = JSON.parse(dispatch_path.read)
      manifest_path = root.join(dispatch.dig("output_manifest", "path"))
      manifest = JSON.parse(manifest_path.read)
      manifest["outputs"] = [envelope["review_output"]]
      manifest_path.write(JSON.pretty_generate(manifest) + "\n")
      dispatch["output_manifest"] = contract.pointer(root, manifest_path)
      dispatch_path.write(JSON.pretty_generate(dispatch) + "\n")
      envelope["director_dispatch"] = contract.pointer(root, dispatch_path)
    end
  end

  def test_promoted_output_rejects_rewritten_review_input_even_with_fresh_digest
    assert_bad_production_review(/differs from the exact projected worker sources/) do |root, _ledger, _review, _path, envelope|
      contract = IdolGraphProductionReviewContract
      input_path = root.join(envelope.dig("review_input_manifest", "path"))
      input = JSON.parse(input_path.read)
      input["founder_context"]["decision_epoch"] = "invented_epoch"
      input_path.write(JSON.pretty_generate(input) + "\n")
      envelope["review_input_manifest"] = contract.pointer(root, input_path)
      envelope["review_input_digest_sha256"] = contract.digest(input)
    end
  end

  def test_promoted_output_rejects_other_run_even_when_director_pack_is_internally_valid
    assert_bad_director_pack({run_root: "runs/another-run"}, /Director pack belongs to a different run/)
  end

  def test_production_review_rejects_a_held_pack_even_with_all_fresh_return_hashes
    with_project_fixture(PLANNING) do |ledger_path|
      root = ledger_path.dirname
      contract = IdolGraphProductionReviewContract
      directory = root.join("work/evidence/production-director-review")
      documents = {}
      %w[director-pack review-output director-output-manifest director-returned review-envelope].each do |name|
        documents[name] = JSON.parse(directory.join("#{name}.json").read)
      end
      pack = documents["director-pack"]
      pack["status"] = "hold"
      pack["hold_reasons"] = ["unresolved_selected_context"]
      pack["projection"]["pack_digest"] = IdolRoleContextPack.structured_sha256(
        pack.reject { |key, _| key == "projection" }.merge("projection" => pack.fetch("projection").reject { |key, _| key == "pack_digest" })
      )
      assert_empty IdolRoleContextPack.validate_pack(root: root, pack: pack)
      directory.join("director-pack.json").write(JSON.pretty_generate(pack) + "\n")
      pack_pointer = contract.pointer(root, directory.join("director-pack.json"))
      output = documents["review-output"]
      output["role_context_pack"] = pack_pointer
      directory.join("review-output.json").write(JSON.pretty_generate(output) + "\n")
      output_pointer = contract.pointer(root, directory.join("review-output.json"))
      manifest = documents["director-output-manifest"]
      manifest["outputs"] = [output_pointer]
      directory.join("director-output-manifest.json").write(JSON.pretty_generate(manifest) + "\n")
      dispatch = documents["director-returned"]
      dispatch["output_manifest"] = contract.pointer(root, directory.join("director-output-manifest.json"))
      directory.join("director-returned.json").write(JSON.pretty_generate(dispatch) + "\n")
      envelope = documents["review-envelope"]
      envelope.merge!("role_context_pack" => pack_pointer, "review_output" => output_pointer,
                      "director_dispatch" => contract.pointer(root, directory.join("director-returned.json")))
      directory.join("review-envelope.json").write(JSON.pretty_generate(envelope) + "\n")
      error = assert_raises(contract::ContractError) { contract.verify!(root: root, review_pointer: contract.pointer(root, directory.join("review-envelope.json"))) }
      assert_match(/unresolved holds/, error.message)
    end
  end

  def test_promoted_output_rejects_other_sections_even_when_director_pack_is_internally_valid
    assert_bad_director_pack({section_ids: ["S99"], scope: {"stage_id" => "front_planning_integration", "section_ids" => ["S99"]}}, /Director pack section scope differs/)
  end

  def test_promoted_output_rejects_a_director_pack_without_dispatch_source_kind
    assert_bad_director_pack({source_kind: "profile_checkpoint"}, /source must be a Department Dispatch/)
  end

  def test_promoted_output_rejects_a_different_output_writer_with_a_fresh_dispatch_hash
    assert_bad_production_review(/Director output writer differs/) do |root, _ledger, _review, _path, envelope|
      path = root.join(envelope.dig("director_dispatch", "path"))
      dispatch = JSON.parse(path.read)
      dispatch["output_writer"]["owner"] = "another_director"
      path.write(JSON.pretty_generate(dispatch) + "\n")
      envelope["director_dispatch"] = IdolGraphProductionReviewContract.pointer(root, path)
    end
  end

  def test_promoted_output_review_must_match_returned_dispatch_reviewer_lane
    ledger = load_planning
    review = node(ledger, "n_review_p3_c1")
    review["lane_id"] = "planning_p3_c1"

    error = assert_raises(ERROR) { project_document(ledger) }

    assert_match(/lane_id against returned Dispatch reviewer/, error.message)
  end

  def test_promoted_output_review_must_match_returned_dispatch_recipient
    ledger = load_planning
    review = node(ledger, "n_review_p3_c1")
    review["next_legal_owner"] = "planning_cdd_p2"

    error = assert_raises(ERROR) { project_document(ledger) }

    assert_match(/next_legal_owner against returned Dispatch recipient/, error.message)
  end

  def test_contextual_judgment_node_rejects_ambiguous_reviewed_state
    contextual = node(load_planning, "n_contextual_judgment_c1")
    invalid = Marshal.load(Marshal.dump(contextual))
    invalid["state"] = "reviewed"

    assert schema_ok?("schemas/graph-node.schema.json", contextual)
    refute schema_ok?("schemas/graph-node.schema.json", invalid)
  end

  def test_eligible_judgment_claim_requires_common_profile_validation
    ledger = load_planning
    judgment_node = node(ledger, "n_contextual_judgment_c1")

    error = assert_raises(ERROR) do
      project_document(ledger) do |root|
        path = root.join("evidence", "contextual-judgment.yaml")
        artifact = YAML.safe_load(path.read, aliases: false)
        critical_motion = artifact.fetch("criteria").find do |row|
          row.fetch("criterion_id") == "contiguous_motion_change_and_landing"
        end
        critical_motion["result"] = 3
        path.write(YAML.dump(artifact))
        judgment_node.fetch("pointers")["artifact_sha256"] = Digest::SHA256.file(path).hexdigest
      end
    end
    assert_match(/failed common contextual judgment validation/, error.message)
    assert_match(/contiguous_motion_change_and_landing is a critical grade-4 criterion/, error.message)
  end

  def test_promoted_output_rejects_wrong_selected_review_edge
    ledger = load_planning
    edge = ledger.fetch("edges").find { |row| row["edge_id"] == "e_judgment_selects_review" }
    edge["to_node_id"] = "n_review_g0"

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/must select its exact Director review/, error.message)
  end

  def test_judged_by_rejects_non_judgment_target
    ledger = load_planning
    edge = ledger.fetch("edges").find { |row| row["edge_id"] == "e_decision_judged_by_context" }
    edge["to_node_id"] = "n_review_p3_c1"

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/judged_by must target a contextual_judgment/, error.message)
  end

  def test_third_session_fails_closed
    ledger = load_planning
    session = node(ledger, "n_od_session")
    second = Marshal.load(Marshal.dump(session))
    second["node_id"] = "n_od_session_successor"
    second["logical_id"] = "overall_successor"
    second["session_role"] = "successor"
    second["state"] = "successor_pending"
    third = Marshal.load(Marshal.dump(session))
    third["node_id"] = "n_od_session_third"
    third["logical_id"] = "overall_third"
    third["session_role"] = "primary"
    ledger.fetch("nodes") << second
    ledger.fetch("nodes") << third

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/primary\+successor maximum two/, error.message)
  end

  def test_same_lane_may_have_one_primary_in_each_distinct_stage
    ledger = load_planning
    session = node(ledger, "n_od_session")
    later_stage = Marshal.load(Marshal.dump(session))
    later_stage["node_id"] = "n_od_session_production"
    later_stage["logical_id"] = "overall_production_primary"
    later_stage["stage_id"] = "production_active"
    ledger.fetch("nodes") << later_stage

    assert_equal "pass", project_document(ledger).fetch("status")
  end

  def test_successor_provider_session_cannot_write_before_cas
    ledger = load_planning
    session = node(ledger, "n_od_session")
    successor = Marshal.load(Marshal.dump(session))
    successor["node_id"] = "n_od_session_successor"
    successor["logical_id"] = "overall_successor"
    successor["session_role"] = "successor"
    successor["state"] = "running"
    successor["may_write"] = true
    successor["writer_id"] = "overall_successor"
    ledger.fetch("nodes") << successor

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/cannot write before successor_of CAS/, error.message)
  end

  def test_cohort_overlap_fails_closed
    ledger = load_planning
    node(ledger, "n_p3_c2")["section_ids"] = %w[S03 S04 S05]

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/section_ids/, error.message)
  end

  def test_lowercase_cohort_id_fails_closed
    ledger = load_planning
    node(ledger, "n_p3_c1")["cohort_id"] = "c1"

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/cohort_id must be canonical C1\.\.Cn/, error.message)
  end

  def test_founder_gate_bypass_fails_closed
    ledger = load_planning
    node(ledger, "n_g1")["state"] = "planned"
    node(ledger, "n_g1").delete("evidence")
    ledger.fetch("nodes") << {
      "schema_version" => "idol-graph-node.v1",
      "node_id" => "n_generated",
      "node_class" => "generated_image",
      "view" => "evidence_provenance",
      "logical_id" => "generated_s01",
      "scope_id" => "s01",
      "state" => "running",
      "owner_role" => "section_image_motion_worker",
      "truth_kind" => "evidence",
      "may_write" => false
    }

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/Founder gate G1 bypass/, error.message)
  end

  def test_script_authored_creative_edge_fails_closed
    ledger = load_planning
    edge = ledger.fetch("edges").find { |row| row.fetch("edge_id") == "e_storyline_supports_s01" }
    edge.fetch("authorship")["author_kind"] = "assigned_model"
    edge.fetch("authorship")["author_role"] = "graph_projector"

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/script-authored/, error.message)
  end

  def test_unrelated_invalidation_fails_closed
    ledger = load_planning
    edge = ledger.fetch("edges").find { |row| row.fetch("edge_id") == "e_major_invalidates_core" }
    edge["affected_scope_ids"] = ["S04"]

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/unrelated section/, error.message)
  end

  def test_provider_fallback_fails_closed
    ledger = load_planning
    node(ledger, "n_worker_session")["fallback_policy"] = "use_cursor"

    error = assert_raises(ERROR) { project_document(ledger) }
    assert_match(/fallback_policy/, error.message)
  end

  def test_positive_and_negative_schema_fixtures
    node = load_planning.fetch("nodes").find { |row| row["node_id"] == "n_overall" }
    edge = load_planning.fetch("edges").find { |row| row["edge_id"] == "e_overall_owns_p1" }
    judgment_node = load_planning.fetch("nodes").find { |row| row["node_id"] == "n_contextual_judgment_c1" }
    judged_edge = load_planning.fetch("edges").find { |row| row["edge_id"] == "e_decision_judged_by_context" }
    selected_edge = load_planning.fetch("edges").find { |row| row["edge_id"] == "e_judgment_selects_review" }
    event = load_planning.fetch("events").find { |row| row["event_id"] == "evt_008" }
    projection = project(PLANNING)

    assert schema_ok?("schemas/graph-node.schema.json", node)
    assert schema_ok?("schemas/graph-node.schema.json", judgment_node)
    assert schema_ok?("schemas/graph-edge.schema.json", edge)
    assert schema_ok?("schemas/graph-edge.schema.json", judged_edge)
    assert schema_ok?("schemas/graph-edge.schema.json", selected_edge)
    assert schema_ok?("schemas/graph-event.schema.json", event)
    assert schema_ok?("schemas/graph-run-projection.schema.json", projection)

    refute schema_ok_file?("schemas/graph-node.schema.json", FIXTURES.join("negative", "node-extra-property.json"))
    refute schema_ok_file?("schemas/graph-edge.schema.json", FIXTURES.join("negative", "edge-missing-type.json"))
    refute schema_ok_file?("schemas/graph-event.schema.json", FIXTURES.join("negative", "event-creative-payload.json"))

    invalid_judged_family = Marshal.load(Marshal.dump(judged_edge))
    invalid_judged_family["family"] = "coordination"
    invalid_judged_family["view"] = "authority_ownership"
    refute schema_ok?("schemas/graph-edge.schema.json", invalid_judged_family)

    invalid_selected_family = Marshal.load(Marshal.dump(selected_edge))
    invalid_selected_family["family"] = "authority"
    refute schema_ok?("schemas/graph-edge.schema.json", invalid_selected_family)
  end

  def test_graph_node_schema_rejects_noncanonical_lowercase_cohort_id
    cohort_node = load_planning.fetch("nodes").find { |row| row["node_class"] == "planning_section_cohort_lane" }
    invalid = Marshal.load(Marshal.dump(cohort_node))
    invalid["cohort_id"] = "c1"

    assert schema_ok?("schemas/graph-node.schema.json", cohort_node)
    refute schema_ok?("schemas/graph-node.schema.json", invalid)
  end

  def test_cli_digest_matches_library_digest
    projection = project(PLANNING)
    result = with_project_fixture(PLANNING) do |ledger_path|
      run_script("--ledger", ledger_path.to_s, "digest")
    end

    assert result[:status].success?, result[:stderr]
    assert_equal projection.fetch("projection_digest"), result[:stdout].strip
  end

  private

  def load_planning
    YAML.safe_load(PLANNING.read, aliases: false)
  end

  def node(ledger, node_id)
    ledger.fetch("nodes").find { |row| row.fetch("node_id") == node_id }
  end

  def project(path)
    return IdolGraphProjector::Projector.new(path).build unless path == PLANNING

    with_project_fixture(path) { |ledger_path| IdolGraphProjector::Projector.new(ledger_path).build }
  end

  def project_document(document)
    Dir.mktmpdir("idol-graph-v2-") do |dir|
      root = Pathname.new(dir)
      FileUtils.cp_r(FIXTURES.join("positive", "evidence"), root.join("evidence"))
      FileUtils.cp_r(FIXTURES.join("positive", "work"), root.join("work"))
      copy_contextual_contract_closure(root)
      refresh_contextual_contract_fixture(root, document)
      yield root if block_given?
      ledger_path = root.join("ledger.yaml")
      ledger_path.write(YAML.dump(JSON.parse(JSON.generate(document))))
      return IdolGraphProjector::Projector.new(ledger_path).build
    end
  end

  def project_cli(path)
    with_project_fixture(path) do |ledger_path|
      run_script("--json", "--ledger", ledger_path.to_s, "project")
    end
  end

  def with_project_fixture(path)
    Dir.mktmpdir("idol-graph-v2-fixture-") do |dir|
      root = Pathname.new(dir)
      FileUtils.cp_r(FIXTURES.join("positive", "evidence"), root.join("evidence"))
      FileUtils.cp_r(FIXTURES.join("positive", "work"), root.join("work"))
      copy_contextual_contract_closure(root)
      ledger_path = root.join("ledger.yaml")
      FileUtils.cp(path, ledger_path)
      document = YAML.safe_load(ledger_path.read, aliases: false)
      refresh_contextual_contract_fixture(root, document)
      ledger_path.write(YAML.dump(document))
      return yield ledger_path
    end
  end

  def copy_contextual_contract_closure(destination)
    graph_routing = YAML.safe_load(ROOT.join("automation", "graph-default-routing.yaml").read, aliases: true)
    judgment_registry = YAML.safe_load(ROOT.join("automation", "graph-creative-judgment-registry.yaml").read, aliases: true)
    profile_registry = YAML.safe_load(ROOT.join("automation", "graph-skill-load-profiles.yaml").read, aliases: true)
    pack_path = FIXTURES.join("positive", "work", "evidence", "contextual-role-context-pack.yaml")
    pack = YAML.safe_load(pack_path.read, aliases: true)
    paths = Array(graph_routing.dig("writer_boundary", "active_graph_surfaces"))
    paths.concat(Array(profile_registry["skill_bindings"]).map { |row| row.fetch("path") })
    paths.concat(Array(profile_registry["read_bindings"]).map { |row| row.fetch("path") })
    paths.concat(
      judgment_registry.fetch("current_profile_releases").values.map do |pointer|
        pointer.dig("promotion_binding", "path")
      end
    )
    paths.concat(Array(pack["instruction_slices"]).map { |row| row.fetch("path") })
    paths.concat([
      "automation/graph-default-routing.yaml",
      "automation/graph-role-context-projection.yaml",
      "automation/graph-skill-load-profiles.yaml",
      "automation/graph-creative-judgment-registry.yaml",
      "automation/harness-provider-profile-registry.yaml",
      pack.dig("provider_binding", "provider_source_path"),
      "automation/providers/grok-build-profiles.yaml",
      "automation/providers/cursor-agent-profiles.yaml",
      "schemas/graph-creative-judgment-registry.schema.json",
      "schemas/graph-contextual-judgment.schema.json",
      "schemas/graph-contextual-judgment-v1-legacy.schema.json",
      "schemas/graph-department-dispatch.schema.json",
      "schemas/role-context-pack.schema.json",
      "scripts/validate_graph_contextual_judgment.rb",
      "scripts/lib/idol_graph_criterion_evidence_contract.rb",
      "scripts/validate_json_schema.py"
    ])
    paths.compact.uniq.each do |relative|
      source = ROOT.join(relative)
      target = destination.join(relative)
      target.dirname.mkpath
      FileUtils.cp(source, target)
    end
  end

  def assert_bad_production_review(message)
    with_project_fixture(PLANNING) do |ledger_path|
      root = ledger_path.dirname
      ledger = YAML.safe_load(ledger_path.read, aliases: true)
      promoted = node(ledger, "n_decision_set_c1")
      review = node(ledger, promoted.dig("evidence", "review_id"))
      path = root.join(review.dig("pointers", "artifact_path"))
      envelope = JSON.parse(path.read)
      yield root, ledger, review, path, envelope
      path.write(JSON.pretty_generate(envelope) + "\n")
      review["pointers"]["artifact_sha256"] = Digest::SHA256.file(path).hexdigest if review["pointers"]
      ledger_path.write(YAML.dump(ledger))
      error = assert_raises(ERROR) { IdolGraphProjector::Projector.new(ledger_path).build }
      assert_match message, error.message
    end
  end

  def assert_bad_director_pack(overrides, message)
    assert_bad_production_review(message) do |root, _ledger, _review, _path, envelope|
      contract = IdolGraphProductionReviewContract
      input = JSON.parse(root.join(envelope.dig("review_input_manifest", "path")).read)
      if overrides[:source_kind]
        overrides = {source_envelope: contract.pointer(root, "work/evidence/production-director-review/director-launched.json").merge("kind" => overrides[:source_kind])}
      end
      rebuilt = IdolGraphProductionReviewFixture.build(
        root: root, judgment_path: root.join(input.dig("contextual_judgment", "path")),
        directory: root.join("work/evidence/production-director-review"),
        review_stage: "front_planning_integration", pack_overrides: overrides
      )
      pack = JSON.parse(rebuilt.fetch("pack_path").read)
      assert_empty IdolRoleContextPack.validate_pack(root: root, pack: pack)
      envelope.replace(rebuilt.fetch("envelope"))
    end
  end

  def refresh_contextual_contract_fixture(root, ledger)
    promote_contextual_goal_fixture_to_provider_native(root)
    goal_event_path = root.join("work", "evidence", "contextual-goal-terminal-event.yaml")
    goal_event_sha = Digest::SHA256.file(goal_event_path).hexdigest
    pack_path = root.join("work", "evidence", "contextual-role-context-pack.yaml")
    template = YAML.safe_load(pack_path.read, aliases: true)
    launch_dispatch_path = root.join("work", "evidence", "contextual-launch-dispatch.yaml")
    pack = cached_contextual_contract_pack(root, template, launch_dispatch_path)
    pack_path.write(YAML.dump(pack))

    judgment_path = root.join("evidence", "contextual-judgment.yaml")
    judgment = YAML.safe_load(judgment_path.read, aliases: false)
    judgment["schema_version"] = "idol_graph_contextual_judgment.v2"
    (Array(judgment["criteria"]) + Array(judgment["hard_gate_findings"])).each do |row|
      row["evidence_locator"] = Array(judgment["source_artifacts"]).map { |source| source.slice("path", "sha256") }
    end
    judgment.fetch("execution_binding")["role_context_pack"] = {
      "path" => pack_path.relative_path_from(root).to_s,
      "sha256" => Digest::SHA256.file(pack_path).hexdigest
    }
    judgment.fetch("execution_binding")["profile_release"] = pack.dig(
      "creative_judgment_contract", "profile_release"
    )
    returned_dispatch_path = root.join("work", "evidence", "contextual-dispatch.yaml")
    judgment.fetch("execution_binding")["dispatch"] = {
      "path" => returned_dispatch_path.relative_path_from(root).to_s,
      "sha256" => Digest::SHA256.file(returned_dispatch_path).hexdigest
    }
    judgment.fetch("execution_binding")["goal_terminal_event_sha256"] = goal_event_sha
    judgment_path.write(YAML.dump(judgment))

    node = ledger.fetch("nodes").find { |row| row["node_id"] == "n_contextual_judgment_c1" }
    node["judgment_schema_version"] = "idol_graph_contextual_judgment.v2"
    node.fetch("pointers")["artifact_sha256"] = Digest::SHA256.file(judgment_path).hexdigest
    fixture = IdolGraphProductionReviewFixture.build(
      root: root, judgment_path: judgment_path,
      directory: root.join("work", "evidence", "production-director-review"),
      review_stage: "front_planning_integration"
    )
    ledger.fetch("nodes").each do |candidate|
      next unless candidate["state"] == "promoted" && candidate["owner_role"] != "founder"
      evidence = candidate["evidence"]
      next unless evidence
      review = ledger.fetch("nodes").find { |row| row["node_id"] == evidence["review_id"] }
      next unless review && review["owner_role"] == "planning_cdd_p1"
      review["pointers"] = {
        "artifact_path" => fixture["envelope_path"].relative_path_from(root).to_s,
        "artifact_sha256" => Digest::SHA256.file(fixture["envelope_path"]).hexdigest
      }
      evidence["input_digest"] = IdolGraphProductionReviewContract.digest(fixture["input"])
      evidence["result_digest"] = IdolGraphProductionReviewContract.digest(fixture["output"])
    end
  end

  def promote_contextual_goal_fixture_to_provider_native(root)
    event_path = root.join("work", "evidence", "contextual-goal-terminal-event.yaml")
    event = YAML.safe_load(event_path.read, aliases: true)
    event["evidence_class"] = "provider_native_terminal_event"
    event.delete("fixture_notice")
    event_path.write(YAML.dump(event))
    event_sha = Digest::SHA256.file(event_path).hexdigest

    %w[contextual-launch-dispatch.yaml contextual-dispatch.yaml].each do |name|
      dispatch_path = root.join("work", "evidence", name)
      dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
      provider = dispatch.fetch("provider_binding")
      resolved, holds = IdolRoleContextPack.resolve_provider(
        root: root, role: dispatch.fetch("logical_role"),
        provider: provider.fetch("registered_provider"),
        runtime_surface: provider.fetch("runtime_surface"),
        logical_profile_alias: provider.fetch("logical_profile_alias")
      )
      raise holds.join("; ") unless holds.empty?
      provider.merge!(
        "reasoning_effort" => resolved.fetch("reasoning_effort"),
        "provider_capability_snapshot_sha256" => resolved.fetch("registry_sha256")
      )
      goal = dispatch.fetch("goal_evidence")
      goal["goal_terminal_event_sha256"] = event_sha
      goal.fetch("terminal_event")["sha256"] = event_sha
      dispatch_path.write(YAML.dump(dispatch))
    end
  end

  def cached_contextual_contract_pack(root, template, launch_dispatch_path)
    cached = self.class.instance_variable_get(:@current_contextual_contract_pack)
    return Marshal.load(Marshal.dump(cached)) if cached

    switch_receipt = template.dig("activation_binding", "switch_receipt").merge(
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(root)
    )
    pack = IdolRoleContextPack.build(
      root: root,
      run_root: template.dig("identity", "run_root"),
      assignment_id: template.dig("identity", "assignment_id"),
      role: template.dig("identity", "role"),
      profile_id: template.dig("identity", "profile_id"),
      checkpoint_id: template.dig("identity", "checkpoint_id"),
      stage_id: template.dig("identity", "stage_id"),
      section_ids: template.dig("identity", "section_ids"),
      source_envelope: {
        "kind" => "department_dispatch",
        "path" => launch_dispatch_path.relative_path_from(root).to_s,
        "sha256" => Digest::SHA256.file(launch_dispatch_path).hexdigest
      },
      current_state: template.dig("current_node", "state"),
      scope: template.dig("current_node", "scope"),
      non_scope: template.dig("current_node", "non_scope"),
      authority: template.fetch("authority_binding"),
      founder_epoch: template.dig("founder_context", "decision_epoch"),
      founder_locks: template.dig("founder_context", "locks"),
      creative_sources: template.fetch("creative_source_pointers"),
      output_contract: template.fetch("output_contract"),
      hold_conditions: template.dig("current_node", "stop_conditions"),
      return_recipient: template.dig("current_node", "return_recipient"),
      provider: template.dig("provider_binding", "provider"),
      runtime_surface: template.dig("provider_binding", "runtime_surface"),
      writer: "graph_v2",
      run_class: "new_run",
      switch_receipt: switch_receipt
    )
    self.class.instance_variable_set(:@current_contextual_contract_pack, Marshal.load(Marshal.dump(pack)))
    pack
  end

  def run_script(*arguments)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT.to_s, *arguments, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def schema_ok?(schema_relative, document)
    Tempfile.create(["graph-schema", ".json"]) do |file|
      file.write(JSON.generate(document))
      file.flush
      stdout, stderr, status = Open3.capture3(
        PYTHON.to_s,
        SCHEMA_VALIDATOR.to_s,
        ROOT.join(schema_relative).to_s,
        file.path,
        chdir: ROOT.to_s
      )
      flunk("#{schema_relative}: #{stderr}#{stdout}") unless status.success? || status.exitstatus == 1
      status.success?
    end
  end

  def schema_ok_file?(schema_relative, document_path)
    _stdout, _stderr, status = Open3.capture3(
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      ROOT.join(schema_relative).to_s,
      document_path.to_s,
      chdir: ROOT.to_s
    )
    status.success?
  end
end
