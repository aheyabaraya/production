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
require_relative "../lib/idol_reference_evaluation_contract"

class IdolReferenceEvaluationTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_reference_evaluation.rb")
  FIXTURES = ROOT.join("scripts", "tests", "fixtures", "reference-evaluation")
  SOURCES = %w[
    still-stance.json
    alt-source-same-function.json
    camera-subject-unresolved.json
    same-file-two-spans.json
  ].freeze
  CONTROLLED = %w[
    polished_unsupported_action_claim
    different_source_same_scene_function
    camera_subject_ambiguity
    correct_file_wrong_time_span
    supported_bound_observation
    authored_uncertainty_hold
  ].freeze

  def setup
    @outer = Pathname.new(Dir.mktmpdir("idol-ref-eval-outer-"))
    @dir = @outer.join("repo")
    @dir.mkpath
    SOURCES.each { |name| FileUtils.cp(FIXTURES.join(name), @dir.join(name)) }
  end

  def teardown
    FileUtils.remove_entry(@outer) if @outer&.directory?
  end

  def parse(name)
    JSON.parse(@dir.join(name).read)
  end

  def file_ref(name)
    {"path" => name, "sha256" => Digest::SHA256.file(@dir.join(name)).hexdigest}
  end

  def value_ref(name, pointer, value, role: "authored_source_observation")
    file_ref(name).merge(
      "role" => role,
      "json_pointer" => pointer,
      "value_sha256" => IdolReferenceEvaluationContract.value_sha256(value)
    )
  end

  def write_json(name, object)
    path = @dir.join(name)
    path.write(JSON.pretty_generate(object))
    path
  end

  def authorship
    {
      "owner" => "human_or_assigned_model",
      "author_role" => "evaluation_author",
      "author_session_id" => "author-session-1"
    }
  end

  def reviewer(session: "reviewer-session-2")
    {
      "owner" => "human_or_assigned_model",
      "role" => "evaluation_reviewer",
      "session_id" => session
    }
  end

  def case_shell(id, category, sources, bindings, claim, expected, extras = {})
    {
      "schema_version" => "idol-reference-evaluation.v1",
      "artifact_type" => "reference_evaluation_case",
      "authority" => "evaluation_evidence_only_never_production_pass",
      "case_id" => id,
      "category" => category,
      "evidence_class" => "synthetic_fixture",
      "fixture_notice" => IdolReferenceEvaluationContract::SYNTHETIC_NOTICE,
      "inspection_kind" => "not_pixel_inspection",
      "claimed_observation" => claim,
      "source_artifacts" => sources,
      "evidence_bindings" => bindings,
      "expected_contextual_observation" => expected,
      "authorship" => authorship
    }.merge(extras)
  end

  def review_shell(id, case_name, observations, decision)
    {
      "schema_version" => "idol-reference-evaluation.v1",
      "artifact_type" => "reference_evaluation_review",
      "authority" => "independent_authored_review_never_production_pass",
      "review_id" => id,
      "case" => file_ref(case_name),
      "reviewer" => reviewer,
      "observations" => observations,
      "review_decision" => decision
    }
  end

  def observation(binding, prose, uncertainty: false)
    {
      "evidence" => binding.slice("path", "sha256", "json_pointer", "value_sha256"),
      "prose" => prose,
      "uncertainty" => uncertainty
    }
  end

  def write_pair(category)
    still = parse("still-stance.json")
    alt = parse("alt-source-same-function.json")
    camera = parse("camera-subject-unresolved.json")
    spans = parse("same-file-two-spans.json")
    case category
    when "polished_unsupported_action_claim"
      binding = value_ref("still-stance.json", "/authored_visible_facts", still["authored_visible_facts"])
      write_json("case.json", case_shell(
        "REFEV_SYNTH_UNSUPPORTED_ACTION_01",
        category,
        [file_ref("still-stance.json")],
        [binding],
        {
          "prose" => "The subject sprints cleanly across the frame with a readable lead foot plant.",
          "action_claim" => "subject sprints across the frame"
        },
        {
          "prose" => "The bound fixture facts record a still stance and do not record the claimed sprint.",
          "uncertainty" => false
        }
      ))
      write_json("review.json", review_shell(
        "REFEVR_SYNTH_UNSUPPORTED_ACTION_01",
        "case.json",
        [observation(binding, "Independent review: the bound facts do not record the claimed sprint.")],
        "hold"
      ))
    when "different_source_same_scene_function"
      left = value_ref("still-stance.json", "/authored_scene_function", still["authored_scene_function"])
      right = value_ref("alt-source-same-function.json", "/authored_scene_function", alt["authored_scene_function"])
      write_json("case.json", case_shell(
        "REFEV_SYNTH_SAME_FUNCTION_01",
        category,
        [file_ref("still-stance.json"), file_ref("alt-source-same-function.json")],
        [left, right],
        {"prose" => "Two sources are offered for the same doorway-hold function."},
        {
          "prose" => "Both bound function strings name a doorway hold. No source is selected as winner.",
          "uncertainty" => false
        },
        "scene_function_claims" => [
          {"source_path" => "still-stance.json", "function_prose" => still["authored_scene_function"]},
          {"source_path" => "alt-source-same-function.json", "function_prose" => alt["authored_scene_function"]}
        ]
      ))
      write_json("review.json", review_shell(
        "REFEVR_SYNTH_SAME_FUNCTION_01",
        "case.json",
        [
          observation(left, "First source is bound as a doorway hold."),
          observation(right, "Second source is bound as a doorway hold. No winner is selected.")
        ],
        "agree"
      ))
    when "camera_subject_ambiguity"
      binding = value_ref(
        "camera-subject-unresolved.json",
        "/camera_subject_resolution",
        camera["camera_subject_resolution"]
      )
      write_json("case.json", case_shell(
        "REFEV_SYNTH_CAMERA_SUBJECT_01",
        category,
        [file_ref("camera-subject-unresolved.json")],
        [binding],
        {"prose" => "The frame contents shift rightward."},
        {
          "prose" => "The bound fixture does not separate camera translation from subject travel.",
          "uncertainty" => true
        },
        "camera_subject_resolution" => IdolReferenceEvaluationContract::CAMERA_SUBJECT_AMBIGUITY
      ))
      write_json("review.json", review_shell(
        "REFEVR_SYNTH_CAMERA_SUBJECT_01",
        "case.json",
        [observation(binding, "Independent review leaves camera versus subject unresolved.", uncertainty: true)],
        "uncertain"
      ))
    when "correct_file_wrong_time_span"
      bound = spans.dig("spans", "span_10_14", "sequence_sample_timestamps_seconds")
      binding = value_ref(
        "same-file-two-spans.json",
        "/spans/span_10_14/sequence_sample_timestamps_seconds",
        bound,
        role: "one_second_analysis_surface"
      )
      write_json("case.json", case_shell(
        "REFEV_SYNTH_WRONG_SPAN_01",
        category,
        [file_ref("same-file-two-spans.json")],
        [binding],
        {"prose" => "The claimed Sequence window is the later corridor hold on this same file."},
        {
          "prose" => "The bound Sequence samples are 10-14, not the claimed 40-44 samples.",
          "uncertainty" => false
        },
        "time_claim" => {
          "kind" => "sequence_samples",
          "timestamps_seconds" => [40, 41, 42, 43, 44]
        }
      ))
      write_json("review.json", review_shell(
        "REFEVR_SYNTH_WRONG_SPAN_01",
        "case.json",
        [observation(binding, "Same file hash is bound, but the authored Sequence claim names a different five-sample span.")],
        "hold"
      ))
    when "supported_bound_observation", "novel_unspecified_category"
      binding = value_ref("still-stance.json", "/authored_visible_facts", still["authored_visible_facts"])
      write_json("case.json", case_shell(
        category == "novel_unspecified_category" ? "REFEV_SYNTH_NOVEL_CATEGORY_01" : "REFEV_SYNTH_SUPPORTED_01",
        category,
        [file_ref("still-stance.json")],
        [binding],
        {"prose" => "The subject stands still at the doorway facing frame left."},
        {
          "prose" => "The bound fixture facts record that still doorway stance.",
          "uncertainty" => false
        }
      ))
      write_json("review.json", review_shell(
        category == "novel_unspecified_category" ? "REFEVR_SYNTH_NOVEL_CATEGORY_01" : "REFEVR_SYNTH_SUPPORTED_01",
        "case.json",
        [observation(binding, "Independent review agrees the bound facts record the still doorway stance.")],
        "agree"
      ))
    when "authored_uncertainty_hold"
      binding = value_ref(
        "camera-subject-unresolved.json",
        "/authored_visible_facts",
        camera["authored_visible_facts"]
      )
      write_json("case.json", case_shell(
        "REFEV_SYNTH_UNCERTAIN_HOLD_01",
        category,
        [file_ref("camera-subject-unresolved.json")],
        [binding],
        {"prose" => "Rightward shift is visible; cause is not settled."},
        {
          "prose" => "Author records legitimate uncertainty and asks for HOLD.",
          "uncertainty" => true
        },
        "camera_subject_resolution" => IdolReferenceEvaluationContract::CAMERA_SUBJECT_AMBIGUITY
      ))
      write_json("review.json", review_shell(
        "REFEVR_SYNTH_UNCERTAIN_HOLD_01",
        "case.json",
        [observation(binding, "Independent review keeps HOLD for unresolved camera versus subject.", uncertainty: true)],
        "hold"
      ))
    else
      raise "unknown controlled example #{category}"
    end
  end

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT.to_s, *args, "--root", @dir.to_s, "--json")
  end

  def assert_incomplete_payload(payload)
    assert_kind_of Hash, payload
    assert_equal "incomplete", payload["mechanical_closure"]
    assert_equal false, payload["production_pass"]
    assert_equal false, payload["semantic_quality_determined"]
    assert_equal false, payload["automatic_winner"]
    assert_kind_of Array, payload["findings"]
    refute_empty payload["findings"]
  end

  CONTROLLED.each do |category|
    define_method("test_#{category}_pair_is_mechanically_complete_and_not_production_pass") do
      write_pair(category)
      stdout, stderr, status = run_cli("validate-pair", "case.json", "review.json")
      payload = JSON.parse(stdout)
      assert status.success?, stderr
      assert_equal "complete", payload["mechanical_closure"]
      assert_equal false, payload["production_pass"]
      assert_equal category, payload["category"]
      assert_equal false, payload.dig("independence", "session_id_declaration_is_runtime_proof")
      if category == "correct_file_wrong_time_span"
        assert_equal "sequence_samples", payload["time_claim_kind"]
        assert_equal true, payload["bound_sequence_samples"]
        assert_equal "claimed_and_bound_differ", payload["time_span_alignment"]
      end
      errors, result = IdolReferenceEvaluationContract.evaluate_pair(
        root: @dir, case_path: "case.json", review_path: "review.json"
      )
      assert_empty errors
      assert_equal "complete", result["mechanical_closure"]
    end
  end

  def test_unknown_category_is_accepted_without_code_change
    write_pair("novel_unspecified_category")
    stdout, stderr, status = run_cli("validate-pair", "case.json", "review.json")
    payload = JSON.parse(stdout)
    assert status.success?, stderr
    assert_equal "novel_unspecified_category", payload["category"]
    assert_equal false, payload["production_pass"]
  end

  def test_scalar_and_malformed_nested_inputs_fail_closed_without_raise
    [nil, [], "scalar", 3].each do |value|
      errors, extras = IdolReferenceEvaluationContract.validate_case(root: @dir, document: value)
      assert_kind_of Array, errors
      assert_kind_of Hash, extras
      refute_empty errors
    end
    write_pair("supported_bound_observation")
    document = JSON.parse(@dir.join("case.json").read)
    document["authorship"] = "author-session-1"
    document["source_artifacts"] = "still-stance.json"
    errors, extras = IdolReferenceEvaluationContract.validate_case(root: @dir, document: document)
    refute_empty errors
    assert_kind_of Hash, extras
    write_json("case.json", document)
    stdout, stderr, status = run_cli("validate-case", "case.json")
    refute status.success?, stderr
    assert_incomplete_payload(JSON.parse(stdout))
    write_json("scalar.json", "not-an-object")
    stdout, _stderr, status = run_cli("validate-case", "scalar.json")
    refute status.success?
    assert_incomplete_payload(JSON.parse(stdout))
  end

  def test_schema_invalid_but_semantically_plausible_payloads_are_incomplete
    write_pair("supported_bound_observation")
    document = JSON.parse(@dir.join("case.json").read)
    missing = document.dup
    missing.delete("authority")
    errors, = IdolReferenceEvaluationContract.validate_case(root: @dir, document: missing)
    refute_empty errors
    plausible = document.dup
    plausible["inspection_kind"] = "eyeballed"
    errors, = IdolReferenceEvaluationContract.validate_case(root: @dir, document: plausible)
    refute_empty errors
    scored = document.dup
    scored["quality_scores"] = {"action" => 5}
    errors, = IdolReferenceEvaluationContract.validate_case(root: @dir, document: scored)
    refute_empty errors
    write_json("case.json", scored)
    stdout, _stderr, status = run_cli("validate-pair", "case.json", "review.json")
    refute status.success?
    assert_incomplete_payload(JSON.parse(stdout))
  end

  def test_stale_extra_source_used_only_by_scene_function_claims_is_incomplete
    write_pair("supported_bound_observation")
    still = parse("still-stance.json")
    document = JSON.parse(@dir.join("case.json").read)
    document["source_artifacts"] << {
      "path" => "alt-source-same-function.json",
      "sha256" => "0" * 64
    }
    document["scene_function_claims"] = [
      {"source_path" => "still-stance.json", "function_prose" => still["authored_scene_function"]},
      {"source_path" => "alt-source-same-function.json", "function_prose" => "doorway hold as a still beat"}
    ]
    write_json("case.json", document)
    review = JSON.parse(@dir.join("review.json").read)
    review["case"] = file_ref("case.json")
    write_json("review.json", review)
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: @dir, case_path: "case.json", review_path: "review.json"
    )
    refute_empty errors
    assert_equal "incomplete", result["mechanical_closure"]
    assert errors.any? { |row| row.include?("SHA-256 is stale") }
  end

  def test_normalized_dot_slash_case_path_binds_the_same_bytes
    write_pair("supported_bound_observation")
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: @dir, case_path: "./case.json", review_path: "review.json"
    )
    assert_empty errors, errors.inspect
    assert_equal "case.json", result.dig("case", "path")
    review = JSON.parse(@dir.join("review.json").read)
    review["case"]["path"] = "./case.json"
    write_json("review.json", review)
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: @dir, case_path: "case.json", review_path: "review.json"
    )
    assert_empty errors, errors.inspect
    assert_equal "complete", result["mechanical_closure"]
  end

  def test_noncadence_five_tuple_is_rejected_by_library_and_cli
    write_pair("correct_file_wrong_time_span")
    document = JSON.parse(@dir.join("case.json").read)
    document["time_claim"]["timestamps_seconds"] = [0, 2, 4, 6, 8]
    errors, extras = IdolReferenceEvaluationContract.validate_case(root: @dir, document: document)
    refute_empty errors
    assert extras.is_a?(Hash)
    assert errors.any? { |row| row.include?("one-second cadence") }
    write_json("case.json", document)
    review = JSON.parse(@dir.join("review.json").read)
    review["case"] = file_ref("case.json")
    write_json("review.json", review)
    stdout, _stderr, status = run_cli("validate-pair", "case.json", "review.json")
    refute status.success?
    payload = JSON.parse(stdout)
    assert_incomplete_payload(payload)
    assert payload["findings"].any? { |row| row.to_s.include?("one-second cadence") }
  end

  def test_cli_structured_incomplete_output_for_pair
    write_json("broken.json", [1, 2, 3])
    write_pair("supported_bound_observation")
    stdout, _stderr, status = run_cli("validate-pair", "broken.json", "review.json")
    refute status.success?
    assert_incomplete_payload(JSON.parse(stdout))
  end

  def test_same_author_review_is_rejected_as_assertion_only
    write_pair("supported_bound_observation")
    review = JSON.parse(@dir.join("review.json").read)
    review["reviewer"]["session_id"] = "author-session-1"
    write_json("review.json", review)
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: @dir, case_path: "case.json", review_path: "review.json"
    )
    refute_empty errors
    assert errors.any? { |row| row.include?("declaration only, not runtime proof") }
    assert_equal "same", result.dig("independence", "session_id_declaration")
    assert_equal false, result.dig("independence", "session_id_declaration_is_runtime_proof")
  end

  def test_clean_process_has_tmpdir_and_cli_completes
    lib = ROOT.join("scripts", "lib", "idol_reference_evaluation_contract.rb")
    probe = <<~'RUBY'
      require ARGV.fetch(0)
      abort "Dir.mktmpdir missing" unless Dir.respond_to?(:mktmpdir)
      Dir.mktmpdir("idol-ref-eval-probe-") { |dir| abort "not a dir" unless File.directory?(dir) }
      print "mktmpdir-ok"
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", probe, lib.to_s, chdir: ROOT.to_s)
    assert status.success?, stderr
    assert_equal "mktmpdir-ok", stdout
    write_pair("supported_bound_observation")
    stdout, stderr, status = run_cli("validate-pair", "case.json", "review.json")
    assert status.success?, stderr
    payload = JSON.parse(stdout)
    assert_equal "complete", payload["mechanical_closure"]
    assert_equal false, payload["production_pass"]
  end

  def test_validate_case_and_pair_recheck_source_freshness_after_overlay
    write_pair("supported_bound_observation")
    document = JSON.parse(@dir.join("case.json").read)
    errors, extras = IdolReferenceEvaluationContract.validate_case(root: @dir, document: document)
    assert_empty errors, errors.inspect
    assert extras.is_a?(Hash)
    sha = Digest::SHA256.file(@dir.join("still-stance.json")).hexdigest
    verified = [{"path" => "still-stance.json", "sha256" => sha}]
    assert_empty IdolReferenceEvaluationContract.recheck_verified_sources(@dir, verified)
    @dir.join("still-stance.json").write("tampered-source-bytes")
    drifted = IdolReferenceEvaluationContract.recheck_verified_sources(@dir, verified)
    assert drifted.any? { |row| row.include?("drifted before result publication") }
    errors, extras = IdolReferenceEvaluationContract.validate_case(root: @dir, document: document)
    refute_empty errors
    assert extras.is_a?(Hash)
    assert errors.any? { |row| row.include?("SHA-256 is stale") || row.include?("drifted before result publication") }
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: @dir, case_path: "case.json", review_path: "review.json"
    )
    refute_empty errors
    assert_equal "incomplete", result["mechanical_closure"]
  end
end
