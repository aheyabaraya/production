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
require_relative "support/active_mv_fixture"

class IdolSequenceMotionAnalysisTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_sequence_motion_analysis.rb")
  PRODUCER = ROOT.join("scripts", "idol_prepare_sequence_motion_analysis.rb")
  MEASUREMENT_SCRIPT = ROOT.join("scripts", "idol_measure_sequence_motion_timeline.py")
  MEASUREMENT_SCHEMA = ROOT.join("schemas", "sequence-motion-machine-measurement.schema.json")
  FP_VALIDATOR = ROOT.join("scripts", "validate_front_planning_readiness.rb")
  DIRECTION_VALIDATOR = ROOT.join("scripts", "validate_01_section_direction.rb")
  STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")
  SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  PYTHON = ROOT.join("scripts", "idol-video-python")
  SCHEMA = ROOT.join("schemas", "sequence-motion-analysis.schema.json")
  DIRECTION_SCHEMA = ROOT.join("schemas", "song-choreography-performance-mv-map.schema.json")
  PROMPT_CLAUSES = [
    "Conditional visible identity: do not require a readable face in every cut; when identity is visible, preserve exact current-title identity.",
    "No forced frontal face or gaze: side, rear, silhouette, occluded, wide, and fast-turn views remain legal when they serve the scene.",
    "Member-specific visible cues: preserve every visible member-specific hair, styling, clothing, silhouette, and detail cue even when the face is unreadable.",
    "Continuous camera energy is a hypothesis: test it against body action, gaze, camera translation and rotation, lens, angle, composition, depth, occlusion, reveal, and start-to-landing evidence; it is never a forced default.",
    "Intentional locked hold is allowed: retain a motivated static or locked choice when it is stronger than movement."
  ].freeze

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture&.cleanup
    @outside_dir && FileUtils.remove_entry(@outside_dir) if @outside_dir&.directory?
  end

  # Steering case 1/2: unavailable continuous video is explicit, while frame-
  # and Flow-derived opportunity remains typed inference rather than observation.
  def test_source_video_unavailable_keeps_observed_and_inferred_evidence_separate
    document = analysis
    document.fetch("candidate_analyses").each do |candidate|
      review = candidate.fetch("continuous_motion_source_review")
      assert_equal "source_video_unavailable", review.fetch("inspection_status")
      assert_empty review.fetch("observed_interframe_events")
      candidate.fetch("inferred_camera_opportunities").each do |opportunity|
        assert_equal "inferred", opportunity.fetch("evidence_status")
        refute_includes opportunity.fetch("inference_basis"), "observed_interframe_event"
        assert_empty opportunity.fetch("observed_event_ids")
      end
    end
    prepare_pre_copy!(document)
    assert_success validate_pre, "baseline source-unavailable inference must pass transport admission"
  end

  # Steering case 3: literal transfer is impossible without inspected source
  # bytes and an exact OBS id; function-equivalent transfer remains legal.
  def test_literal_transfer_requires_inspected_source_and_exact_observed_event
    baseline = analysis
    document = deep_copy(baseline)
    opportunity = document.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0)
    opportunity["inference_basis"] << "observed_interframe_event"
    opportunity["observed_event_ids"] = ["OBS_FAST_ARC"]
    opportunity["literal_transfer"] = {
      "supported" => true,
      "source_motion_family" => "pan",
      "observed_event_ids" => ["OBS_FAST_ARC"],
      "hold_reason" => nil
    }
    prepare_pre_copy!(document)
    result = validate_pre
    refute result[:status].success?
    assert_match(/literal transfer requires an inspected continuous source video|cites an observed event but none exists/, errors(result))

    assert baseline.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0, "function_equivalent_transfer", "supported")

    no_safe = deep_copy(baseline)
    no_safe_opportunity = no_safe.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0)
    no_safe_opportunity["function_equivalent_transfer"] = {
      "supported" => false,
      "alternative_motion_families" => [],
      "equivalence_reason" => "No safe transfer is supportable."
    }
    prepare_pre_copy!(no_safe)
    no_safe_result = validate_pre
    refute no_safe_result[:status].success?
    assert_includes errors(no_safe_result), "no-safe-motion result requires analysis HOLD"
  end

  def test_inspected_governing_video_supports_observed_pan_and_zoom_pulses_without_default_orbit
    document = build_inspected_observed_analysis
    review = document.dig("candidate_analyses", 0, "continuous_motion_source_review")
    events = review.fetch("observed_interframe_events")
    opportunities = document.dig("candidate_analyses", 0, "inferred_camera_opportunities")
    assert_equal %w[OBS_LATERAL_PAN OBS_REPEATED_ZOOM_PULSE], events.map { |event| event.fetch("event_id") }
    assert events.all? { |event| event.fetch("evidence_status") == "observed" }
    refute_includes events.map { |event| event.fetch("observed_motion_family") }, "full_orbit"
    assert_equal %w[pan zoom_pulse], opportunities.map { |row| row.dig("literal_transfer", "source_motion_family") }
    assert_equal events.map { |event| [event.fetch("event_id")] }, opportunities.map { |row| row.fetch("observed_event_ids") }
    assert_success validate_pre
  end

  def test_genuine_rapid_full_orbit_is_positive_but_pan_cannot_be_relabelled_as_full_orbit
    document = build_inspected_observed_analysis
    candidate = document.dig("candidate_analyses", 0)
    review = candidate.fetch("continuous_motion_source_review")
    governing_id = review.dig("source_video", "governing_sequence_unit_id")
    orbit_event = {
      "event_id" => "OBS_RAPID_FULL_ORBIT",
      "evidence_status" => "observed",
      "source_time_range_seconds" => {"start" => 0.25, "end" => 3.75},
      "observed_motion_family" => "full_orbit",
      "observed_perceptual_functions" => ["speed", "disorientation", "reveal", "parallax"],
      "observed_body_action_fact" => "dance_phrase",
      "observed_gaze_and_head_fact" => "stable_nonfrontal",
      "observed_camera_translation_fact" => "compound_translation",
      "observed_camera_rotation_fact" => "full_orbit_clockwise",
      "observed_rotation_degrees" => 360.0,
      "observed_full_orbit_completed" => true,
      "observed_lens_change_fact" => "none_observed",
      "observed_angle_change_fact" => "compound",
      "observed_composition_change_fact" => "compound",
      "observed_depth_change_fact" => "parallax_increases",
      "observed_occlusion_change_fact" => "compound",
      "observed_reveal_change_fact" => "reveals_environment",
      "observed_speed_profile" => "A rapid continuous clockwise circuit completes one genuine 360-degree orbit before landing.",
      "observed_entry_state" => "The subject begins in a rear three-quarter relation.",
      "observed_exit_state" => "The camera returns to the same rear three-quarter axis after one complete circuit.",
      "related_sequence_unit_ids" => [governing_id],
      "confidence" => "high"
    }
    review.fetch("observed_interframe_events") << orbit_event
    orbit_opportunity = deep_copy(candidate.fetch("inferred_camera_opportunities").first)
    orbit_opportunity["opportunity_id"] = "INF_MJ01_RAPID_FULL_ORBIT"
    orbit_opportunity["observed_event_ids"] = [orbit_event.fetch("event_id")]
    orbit_opportunity["perceptual_functions"] = orbit_event.fetch("observed_perceptual_functions")
    orbit_opportunity["geometry_support"] = "The admitted continuous source completes one rapid 360-degree circuit; no other cut inherits orbit by default."
    orbit_opportunity.dig("joint_motion_reading")["camera_translation"] = "The camera translates around the subject while preserving the action axis."
    orbit_opportunity.dig("joint_motion_reading")["camera_rotation"] = "One observed clockwise 360-degree orbit completes and returns to its starting axis."
    orbit_opportunity["literal_transfer"] = {
      "supported" => true,
      "source_motion_family" => "full_orbit",
      "observed_event_ids" => [orbit_event.fetch("event_id")],
      "perceptual_functions" => orbit_event.fetch("observed_perceptual_functions"),
      "camera_translation_fact" => "compound_translation",
      "camera_rotation_fact" => "full_orbit_clockwise",
      "rotation_degrees" => 360.0,
      "full_orbit_completed" => true,
      "lens_change_fact" => "none_observed",
      "hold_reason" => nil
    }
    candidate.fetch("inferred_camera_opportunities") << orbit_opportunity
    prepare_pre_copy!(document)
    assert_success validate_pre

    relabelled = deep_copy(document)
    pan_literal = relabelled.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0, "literal_transfer")
    pan_literal["source_motion_family"] = "full_orbit"
    pan_literal["camera_rotation_fact"] = "full_orbit_clockwise"
    pan_literal["rotation_degrees"] = 360.0
    pan_literal["full_orbit_completed"] = true
    prepare_pre_copy!(relabelled)
    rejected = validate_pre
    refute rejected[:status].success?
    assert_includes errors(rejected), "literal transfer source_motion_family must exact-copy cited observed event OBS_LATERAL_PAN"

    disguised_orbit = build_inspected_observed_analysis
    disguised_event = disguised_orbit.dig("candidate_analyses", 0, "continuous_motion_source_review", "observed_interframe_events", 0)
    disguised_event["observed_camera_rotation_fact"] = "full_orbit_clockwise"
    disguised_event["observed_rotation_degrees"] = 360.0
    disguised_event["observed_full_orbit_completed"] = true
    refute schema_result(disguised_orbit, SCHEMA)[:status].success?, "a non-full-orbit event cannot carry full-orbit completion facts"
  end

  def test_full_orbit_is_held_when_rear_world_or_identity_support_is_unsupported
    document = build_inspected_observed_analysis
    candidate = document.dig("candidate_analyses", 0)
    event = candidate.dig("continuous_motion_source_review", "observed_interframe_events", 0)
    event.merge!(
      "event_id" => "OBS_UNSUPPORTED_FULL_ORBIT",
      "observed_motion_family" => "full_orbit",
      "observed_perceptual_functions" => ["speed", "disorientation", "reveal", "parallax"],
      "observed_camera_translation_fact" => "compound_translation",
      "observed_camera_rotation_fact" => "full_orbit_clockwise",
      "observed_rotation_degrees" => 360.0,
      "observed_full_orbit_completed" => true,
      "observed_lens_change_fact" => "none_observed"
    )
    opportunity = candidate.fetch("inferred_camera_opportunities").first
    opportunity["observed_event_ids"] = [event.fetch("event_id")]
    opportunity["perceptual_functions"] = event.fetch("observed_perceptual_functions")
    opportunity["literal_transfer"] = {
      "supported" => true,
      "source_motion_family" => "full_orbit",
      "observed_event_ids" => [event.fetch("event_id")],
      "perceptual_functions" => event.fetch("observed_perceptual_functions"),
      "camera_translation_fact" => "compound_translation",
      "camera_rotation_fact" => "full_orbit_clockwise",
      "rotation_degrees" => 360.0,
      "full_orbit_completed" => true,
      "lens_change_fact" => "none_observed",
      "hold_reason" => nil
    }
    %w[rear_world_direction identity].each do |dimension|
      finding = candidate.dig("motion_support_finding", dimension)
      finding["support_state"] = "unsupported"
      finding["recommended_01_disposition"] = "reject"
    end
    prepare_pre_copy!(document)
    literal_result = validate_pre
    refute literal_result[:status].success?
    assert_includes errors(literal_result), "literal full_orbit must be held when rear_world_direction and identity support is unsupported"

    safe_alternative = deep_copy(document)
    safe_opportunity = safe_alternative.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0)
    safe_opportunity["literal_transfer"] = {
      "supported" => false,
      "source_motion_family" => nil,
      "observed_event_ids" => [],
      "perceptual_functions" => [],
      "camera_translation_fact" => nil,
      "camera_rotation_fact" => nil,
      "rotation_degrees" => nil,
      "full_orbit_completed" => nil,
      "lens_change_fact" => nil,
      "hold_reason" => "The admitted orbit cannot transfer because rear-world direction and visible identity support are incomplete."
    }
    safe_opportunity["function_equivalent_transfer"] = {
      "supported" => true,
      "alternative_motion_families" => ["partial_arc", "lateral_track"],
      "equivalence_reason" => "A partial arc or lateral track preserves reveal and energy without inventing unsupported rear-world or identity bytes."
    }
    prepare_pre_copy!(safe_alternative)
    assert_success validate_pre

    unsafe_equivalent = deep_copy(safe_alternative)
    unsafe_equivalent.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0, "function_equivalent_transfer", "alternative_motion_families") << "full_orbit"
    prepare_pre_copy!(unsafe_equivalent)
    equivalent_result = validate_pre
    refute equivalent_result[:status].success?
    assert_includes errors(equivalent_result), "function-equivalent alternatives must exclude full_orbit when rear_world_direction and identity support is unsupported"
  end

  def test_observed_ids_are_global_and_each_event_includes_its_governing_sequence_unit
    document = build_inspected_observed_analysis
    duplicate = deep_copy(document.dig("candidate_analyses", 0, "continuous_motion_source_review", "observed_interframe_events", 0))
    document.dig("candidate_analyses", 0, "continuous_motion_source_review", "observed_interframe_events") << duplicate
    prepare_pre_copy!(document)
    duplicate_result = validate_pre
    refute duplicate_result[:status].success?
    assert_includes errors(duplicate_result), "must be globally unique"

    document = build_inspected_observed_analysis
    document.dig("candidate_analyses", 0, "continuous_motion_source_review", "observed_interframe_events", 0)["related_sequence_unit_ids"] = []
    prepare_pre_copy!(document)
    governing_result = validate_pre
    refute governing_result[:status].success?
    assert_includes errors(governing_result), "must include its governing Sequence Unit"
  end

  def test_inspected_source_rejects_arbitrary_cross_run_stale_and_unordered_manifest_evidence
    document = build_inspected_observed_analysis
    arbitrary = @fixture.run_dir.join("references", "arbitrary-source.mp4")
    arbitrary.binwrite("arbitrary repo video bytes\n")
    source_ref = document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video")
    source_ref["path"] = relative(arbitrary)
    source_ref["sha256"] = Digest::SHA256.file(arbitrary).hexdigest
    prepare_pre_copy!(document)
    arbitrary_result = validate_pre
    refute arbitrary_result[:status].success?
    assert_includes errors(arbitrary_result), "never arbitrary or cross-run bytes"

    document = build_inspected_observed_analysis
    cross_run = @fixture.run_container.join("other-title", "OTHER_RUN", "research", "reference-intake", "SEQU_REF_01", "source-video.mp4")
    cross_run.dirname.mkpath
    cross_run.binwrite("cross-run video bytes\n")
    source_ref = document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video")
    source_ref["path"] = relative(cross_run)
    source_ref["sha256"] = Digest::SHA256.file(cross_run).hexdigest
    prepare_pre_copy!(document)
    cross_run_result = validate_pre
    refute cross_run_result[:status].success?
    assert_includes errors(cross_run_result), "never arbitrary or cross-run bytes"

    document = build_inspected_observed_analysis
    manifest_path = ROOT.join(document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video", "governing_manifest_path"))
    manifest = JSON.parse(manifest_path.read)
    sheet_path = ROOT.join(manifest.dig("sheets", 0, "path"))
    sheet_path.binwrite(sheet_path.binread + "stale\n")
    prepare_pre_copy!(document)
    stale_result = validate_pre
    refute stale_result[:status].success?
    assert_includes errors(stale_result), "governing manifest sheet 1 SHA is stale"

    document = build_inspected_observed_analysis
    manifest_path = ROOT.join(document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video", "governing_manifest_path"))
    manifest = JSON.parse(manifest_path.read)
    manifest.dig("sheets", 0, "cells", 0)["order"] = 2
    manifest_path.binwrite(JSON.pretty_generate(manifest) + "\n")
    prepare_pre_copy!(document)
    order_result = validate_pre
    refute order_result[:status].success?
    assert_includes errors(order_result), "cell order must be contiguous"

    document = build_inspected_observed_analysis
    manifest_path = ROOT.join(document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video", "governing_manifest_path"))
    manifest = JSON.parse(manifest_path.read)
    manifest.dig("sheets", 0, "timestamps")[1] = 0.0
    manifest.dig("sheets", 0, "cells", 1)["source_timestamp_seconds"] = 0.0
    manifest_path.binwrite(JSON.pretty_generate(manifest) + "\n")
    prepare_pre_copy!(document)
    timestamp_order_result = validate_pre
    refute timestamp_order_result[:status].success?
    assert_includes errors(timestamp_order_result), "cell timestamps must be globally strictly increasing"

    document = build_inspected_observed_analysis
    manifest_path = ROOT.join(document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video", "governing_manifest_path"))
    manifest = JSON.parse(manifest_path.read)
    manifest.dig("sheets", 0)["cells"] = []
    manifest_path.binwrite(JSON.pretty_generate(manifest) + "\n")
    prepare_pre_copy!(document)
    empty_result = validate_pre
    refute empty_result[:status].success?
    assert_includes errors(empty_result), "timestamps/cells/count must be exact and nonempty"

    document = build_inspected_observed_analysis
    source_ref = document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video")
    source_ref["source_identity"] = "UNBOUND-SOURCE"
    source_ref["inspected_locator"] = "unbound locator"
    prepare_pre_copy!(document)
    unbound_provenance_result = validate_pre
    refute unbound_provenance_result[:status].success?
    assert_includes errors(unbound_provenance_result), "source_identity must exact-copy its governing Front Planning reference unit"
    assert_includes errors(unbound_provenance_result), "inspected_locator must exact-copy its governing Front Planning reference unit selected_locator"
  end

  def test_identity_visibility_and_joint_motion_reading_do_not_force_a_front_face_or_motion_default
    document = analysis
    finding = document.dig("candidate_analyses", 0, "motion_support_finding")
    visibility = finding.fetch("identity_visibility")
    assert_equal "intentionally_unreadable", visibility.fetch("intent")
    assert_equal "exact_current_title_identity_nonfrontal_allowed", visibility.fetch("fidelity_when_visible")
    assert_equal "all_listed_visible_cues_preserve_exact_current_title_fidelity", visibility.fetch("visible_cue_fidelity")
    assert_includes visibility.fetch("visible_identity_cues"), "styling"
    assert_includes visibility.fetch("visible_identity_cues"), "clothing"
    refute_includes visibility.fetch("visible_identity_cues"), "face_when_visible"
    assert_equal "adopt", finding.dig("identity", "recommended_01_disposition")
    refute_match(/front(?:al)? (?:face|gaze) required/i, visibility.fetch("scene_function_reason"))

    reading = document.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0, "joint_motion_reading")
    %w[body_action_energy camera_translation camera_rotation lens_change subject_gaze_and_head_direction angle_and_composition_reframing depth_occlusion_reveal start_and_landing continuous_camera_energy_review].each do |key|
      assert reading.key?(key), "missing joint motion reading #{key}"
    end
    refute_match(/front(?:al)? gaze required/i, reading.fetch("subject_gaze_and_head_direction"))

    side_profile = deep_copy(document)
    side_visibility = side_profile.dig("candidate_analyses", 0, "motion_support_finding", "identity_visibility")
    side_visibility["intent"] = "optional_partial"
    side_visibility["visible_identity_cues"] = ["face_when_visible", "hair", "styling", "clothing"]
    side_visibility["scene_function_reason"] = "A nonfrontal side profile may remain readable while gaze follows the scene action."
    assert schema_result(side_profile, SCHEMA)[:status].success?

    absent = deep_copy(document)
    absent_visibility = absent.dig("candidate_analyses", 0, "motion_support_finding", "identity_visibility")
    absent_visibility["intent"] = "member_absent"
    absent_visibility["visible_identity_cues"] = []
    absent_visibility["scene_function_reason"] = "The environment-only comparison contains no member."
    assert schema_result(absent, SCHEMA)[:status].success?

    direction = load_yaml(@fixture.direction_path)
    adoption = direction.dig("section_directions", 0, "sequence_motion_adoptions", 0)
    assert_equal "adopt", adoption.dig("dimension_dispositions", "identity")
    assert_match(/intentionally unreadable rear-view identity cues/i, adoption.fetch("authored_reason"))
    assert_match(/rear three-quarter/i, direction.dig("official_core_cuts", 0, "identity_when_visible"))

    bad_visibility = deep_copy(document)
    bad_visibility.dig("candidate_analyses", 0, "motion_support_finding", "identity_visibility")["intent"] = "front_face_required"
    refute schema_result(bad_visibility, SCHEMA)[:status].success?

    bad_unreadable = deep_copy(document)
    bad_unreadable.dig("candidate_analyses", 0, "motion_support_finding", "identity_visibility", "visible_identity_cues") << "face_when_visible"
    refute schema_result(bad_unreadable, SCHEMA)[:status].success?

    bad_absent = deep_copy(absent)
    bad_absent.dig("candidate_analyses", 0, "motion_support_finding", "identity_visibility", "visible_identity_cues") << "clothing"
    refute schema_result(bad_absent, SCHEMA)[:status].success?

    bad_reading = deep_copy(document)
    bad_reading.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0, "joint_motion_reading").delete("subject_gaze_and_head_direction")
    refute schema_result(bad_reading, SCHEMA)[:status].success?
  end

  def test_dispatch_exact_binds_storyline_output_acceptance_and_return_evidence
    document = analysis
    prepare_pre_copy!(document)
    assert_success validate_pre

    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    objective = dispatch.dig("launch", "task", "objective")
    assert_includes objective, document.dig("analysis_scope", "active_storyline_passage_binding", "source_value_sha256")
    prompt = dispatch.dig("launch", "compiled_launch_prompt", "rendered_prompt")
    front = load_yaml(@fixture.front_path)
    assert_includes prompt, front.dig("storyline_lineage", "active_version", "full_storyline_text")
    assert_includes prompt, front.dig("major_scene_catalog", 0, "semantic_event_or_relation_job")
    front.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates").each do |candidate|
      %w[sequence_composition_id flow_reading mismatch_and_risk].each { |field| assert_includes prompt, candidate.fetch(field) }
      candidate.fetch("typed_sequence_unit_ids").each { |unit_id| assert_includes prompt, unit_id }
    end
    PROMPT_CLAUSES.each { |clause| assert_equal 1, prompt.scan(clause).length }
    acceptance = dispatch.dig("launch", "bounded_output", "anti_flat_evidence_requirements").join(" ")
    %w[body gaze identity styling clothing].each { |term| assert_includes acceptance.downcase, term }
    assert_includes acceptance, "independent CDD review"

    dispatch.dig("launch", "bounded_output")["anti_flat_evidence_requirements"] = ["Compare the candidate group."]
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    result = validate_pre
    refute result[:status].success?
    assert_match(/joint-reading term|exact return evidence/, errors(result))
  end

  def test_each_identity_and_camera_clause_is_fail_closed_in_rendered_prompt_and_requirement_for_pre_copy_and_strict
    document = analysis
    PROMPT_CLAUSES.each do |clause|
      prepare_pre_copy!(document)
      omit_sequence_prompt_clause!(clause, from: :rendered_prompt)
      pre_prompt = validate_pre
      refute pre_prompt[:status].success?
      assert_includes errors(pre_prompt), "rendered prompt must carry exact Sequence clause"

      prepare_pre_copy!(document)
      omit_sequence_prompt_clause!(clause, from: :quality_requirement)
      pre_requirement = validate_pre
      refute pre_requirement[:status].success?
      assert_includes errors(pre_requirement), "QUALITY-SEQUENCE-MOTION-ACCEPTANCE must independently carry exact clause"

      @fixture.rewrite_sequence_motion(document)
      omit_sequence_prompt_clause!(clause, from: :rendered_prompt)
      strict_prompt = validate_strict
      refute strict_prompt[:status].success?
      assert_includes errors(strict_prompt), "rendered prompt must carry exact Sequence clause"

      @fixture.rewrite_sequence_motion(document)
      omit_sequence_prompt_clause!(clause, from: :quality_requirement)
      strict_requirement = validate_strict
      refute strict_requirement[:status].success?
      assert_includes errors(strict_requirement), "QUALITY-SEQUENCE-MOTION-ACCEPTANCE must independently carry exact clause"
    end
  end

  def test_rendered_prompt_rejects_omitted_actual_storyline_major_job_or_candidate_value
    document = analysis
    front = load_yaml(@fixture.front_path)
    values = [
      front.dig("storyline_lineage", "active_version", "full_storyline_text"),
      front.dig("major_scene_catalog", 0, "semantic_event_or_relation_job"),
      front.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates", 0, "flow_reading")
    ]
    values.each do |value|
      prepare_pre_copy!(document)
      dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
      compiled = dispatch.dig("launch", "compiled_launch_prompt")
      compiled["rendered_prompt"] = compiled.fetch("rendered_prompt").sub(value, "[OMITTED]")
      compiled["rendered_prompt_sha256"] = Digest::SHA256.hexdigest(compiled.fetch("rendered_prompt"))
      write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
      result = validate_pre
      refute result[:status].success?
      assert_includes errors(result), "rendered prompt must carry the exact active storyline, Major semantic job, and complete candidate values once"
    end
  end

  def test_sequence_requirement_rows_and_independent_cdd_results_fail_closed
    document = analysis
    prepare_pre_copy!(document)
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    dispatch.dig("launch", "requirement_manifest").reject! do |row|
      row.fetch("requirement_id") == "QUALITY-SEQUENCE-MOTION-ACCEPTANCE"
    end
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    missing_launch_requirement = validate_pre
    refute missing_launch_requirement[:status].success?
    assert_includes errors(missing_launch_requirement), "requirement_manifest is missing QUALITY-SEQUENCE-MOTION-ACCEPTANCE"

    prepare_pre_copy!(document)
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    policy_requirement = dispatch.dig("launch", "requirement_manifest").find do |row|
      row.fetch("requirement_id") == "POLICY-SEQUENCE-MOTION-EVIDENCE"
    end
    policy_requirement.fetch("source_binding")["sha256"] = "0" * 64
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    stale_policy_binding = validate_pre
    refute stale_policy_binding[:status].success?
    assert_includes errors(stale_policy_binding), "must exact hash-bind the current governing graph-engineering routing policy bytes"

    @fixture.rewrite_sequence_motion(document)
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    dispatch.dig("director_review", "requirement_results").reject! do |row|
      row.fetch("requirement_id") == "POLICY-SEQUENCE-MOTION-EVIDENCE"
    end
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    missing_cdd_result = validate_strict
    refute missing_cdd_result[:status].success?
    assert_includes errors(missing_cdd_result), "independent CDD requirement_results is missing POLICY-SEQUENCE-MOTION-EVIDENCE"

    @fixture.rewrite_sequence_motion(document)
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    quality_result = dispatch.dig("director_review", "requirement_results").find do |row|
      row.fetch("requirement_id") == "QUALITY-SEQUENCE-MOTION-ACCEPTANCE"
    end
    quality_result["result"] = "hold"
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    held_cdd_result = validate_strict
    refute held_cdd_result[:status].success?
    assert_includes errors(held_cdd_result), "independent CDD requirement_results must PASS QUALITY-SEQUENCE-MOTION-ACCEPTANCE"
  end

  # Steering case 4: one worker owns the complete ordered 2..4 candidate group.
  def test_complete_candidate_group_and_major_scope_are_exact
    document = analysis
    assert_equal 2, document.fetch("candidate_analyses").length
    assert_equal document.dig("analysis_scope", "candidate_ids"), document.fetch("candidate_analyses").map { |row| row.fetch("sequence_composition_id") }
    prepare_pre_copy!(document)
    assert_success validate_pre

    bad = analysis
    bad["major_scene_id"] = "MJ99"
    prepare_pre_copy!(bad)
    result = validate_pre
    refute result[:status].success?
    assert_match(/major_scene_id binding differs|dispatch id must be sequence-motion-analysis-MJ99/, errors(result))
  end

  # Steering case 5/6: only the selected FP candidate may carry the exact
  # analysis file/row and review receipt; a stale value hash fails closed.
  def test_selected_only_reachability_rejects_nonselected_and_stale_bindings
    front = load_yaml(@fixture.front_path)
    candidates = front.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates")
    candidates[1]["sequence_motion_analysis_binding"] = deep_copy(candidates[0].fetch("sequence_motion_analysis_binding"))
    candidates[0].dig("sequence_motion_analysis_binding")["value_sha256"] = "0" * 64
    write_yaml(@fixture.front_path, front)
    result = run_command(RbConfig.ruby, FP_VALIDATOR, "--json", @fixture.front_path)
    refute result[:status].success?
    detail = errors(result)
    assert_match(/non-?selected|only the selected/i, detail)
    assert_match(/value SHA-256|row hash|stale/i, detail)
  end

  # Steering case 7: analysis is advisory and cannot acquire 01/02A fields.
  def test_analysis_schema_rejects_official_core_or_branch_creative_truth
    document = analysis
    document["official_core_cuts"] = [{"core_cut_id" => "C99"}]
    document.dig("candidate_analyses", 0)["branch_cuts"] = [{"branch_cut_id" => "BC99"}]
    result = schema_result(document, SCHEMA)
    refute result[:status].success?
    assert_match(/additional propert|unexpected/i, [result[:stdout], result[:stderr]].join("\n"))
  end

  # Steering case 8: inferred opportunity cannot author final temporal camera.
  def test_inference_cannot_author_speed_envelope_stop_or_landing
    document = analysis
    opportunity = document.dig("candidate_analyses", 0, "inferred_camera_opportunities", 0)
    opportunity["camera_speed"] = "fast"
    opportunity["motion_envelope"] = "accelerate then stop"
    opportunity["final_landing"] = "land on face"
    result = schema_result(document, SCHEMA)
    refute result[:status].success?
    assert_equal "03V_after_passed_production_cut_pixel_review", document.dig("authority_boundary", "final_temporal_camera_owner")
  end

  # Steering case 9: backpressure and same-scope active overlap HOLD, while
  # immutable promoted/hold evidence does not block a successor attempt.
  def test_adaptive_backpressure_and_overlap_are_fail_closed
    document = analysis
    prepare_pre_copy!(document)
    current_dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    peer_path = @fixture.run_dir.join("work", "department-dispatches", "sequence-motion-analysis-MJ01--attempt-02.yaml")
    peer = deep_copy(current_dispatch)
    peer["dispatch_id"] = "sequence-motion-analysis-MJ01--attempt-02"
    peer.dig("lineage")["attempt_id"] = peer.fetch("dispatch_id")
    peer.dig("lineage")["attempt_number"] = 2
    peer.dig("lineage")["previous_attempt_id"] = current_dispatch.fetch("dispatch_id")
    peer.dig("launch", "task")["task_id"] = peer.fetch("dispatch_id")
    peer.dig("launch", "task", "exact_scope")["artifact_paths"] = [relative(@fixture.sequence_motion_analysis_path.dirname.join("attempt-02.yaml"))]
    peer.dig("lifecycle")["current_state"] = "launched"
    write_yaml(peer_path, peer)

    active_result = validate_pre
    refute active_result[:status].success?
    assert_includes errors(active_result), "overlap HOLD"

    peer.dig("lifecycle")["current_state"] = "promoted"
    write_yaml(peer_path, peer)
    terminal_spoof = validate_pre
    refute terminal_spoof[:status].success?
    assert_includes errors(terminal_spoof), "claims terminal state without verifiable"

    peer["dispatch_id"] = "sequence-motion-analysis-MJ02--attempt-01"
    peer.dig("lineage")["attempt_id"] = peer.fetch("dispatch_id")
    peer.dig("lineage")["attempt_number"] = 1
    peer.dig("lineage")["previous_attempt_id"] = nil
    peer.dig("launch", "task")["task_id"] = peer.fetch("dispatch_id")
    peer.dig("launch", "task", "exact_scope")["section_ids"] = ["S02"]
    peer.dig("launch", "task", "exact_scope")["artifact_paths"] = [relative(@fixture.run_dir.join("research", "sequence-motion-analysis", "S02--MJ02", "attempt-01.yaml"))]
    peer.dig("lifecycle")["current_state"] = "launched"
    disjoint_path = peer_path
    write_yaml(disjoint_path, peer)
    assert_success validate_pre

    saturated = analysis
    saturated.dig("dispatch_and_authorship")["review_backpressure"] = "cdd_review_queue_saturated"
    prepare_pre_copy!(saturated)
    result = validate_pre
    refute result[:status].success?
    assert_includes errors(result), "backpressure requires analysis status HOLD"
  end

  def test_attempt_specific_successor_requires_exact_immutable_terminal_predecessor
    predecessor_id = load_yaml(@fixture.sequence_motion_dispatch_path).fetch("dispatch_id")
    successor_path, successor_dispatch_path = build_successor_attempt(previous_attempt_id: predecessor_id)
    assert_match(%r{/S01--MJ01/attempt-02\.yaml\z}, successor_path.to_s)
    assert_match(/sequence-motion-analysis-MJ01--attempt-02\.yaml\z/, successor_dispatch_path.to_s)
    assert_success validate_pre(successor_path)

    predecessor_artifact_bytes = @fixture.sequence_motion_analysis_path.binread
    @fixture.sequence_motion_analysis_path.unlink
    missing_output = validate_pre(successor_path)
    refute missing_output[:status].success?
    assert_match(/internally exact immutable terminal receipt|claims terminal state without verifiable/, errors(missing_output))
    @fixture.sequence_motion_analysis_path.binwrite(predecessor_artifact_bytes)

    stale_source_dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    stale_policy = stale_source_dispatch.dig("launch", "requirement_manifest").find do |row|
      row.fetch("requirement_id") == "POLICY-SEQUENCE-MOTION-EVIDENCE"
    end
    previous_binding = stale_policy.fetch("source_binding")
    archived_binding = {
      "path" => previous_binding.fetch("path"),
      "sha256" => "a" * 64,
      "role" => previous_binding.fetch("role")
    }
    stale_policy["source_binding"] = archived_binding
    archived_reviewer_row = deep_copy(
      stale_source_dispatch.dig("director_review", "reviewer_read_closure").find do |row|
        row.fetch("path") == previous_binding.fetch("path") && row.fetch("sha256") == previous_binding.fetch("sha256")
      end
    )
    archived_reviewer_row["path"] = archived_binding.fetch("path")
    archived_reviewer_row["sha256"] = archived_binding.fetch("sha256")
    stale_source_dispatch.dig("director_review", "reviewer_read_closure") << archived_reviewer_row
    stale_source_dispatch.dig("runtime_return", "input_digest")["sha256"] = @fixture.value_sha(
      "lineage" => stale_source_dispatch.fetch("lineage"),
      "review_submission" => stale_source_dispatch.fetch("review_submission"),
      "launch" => stale_source_dispatch.fetch("launch")
    )
    write_yaml(@fixture.sequence_motion_dispatch_path, stale_source_dispatch)
    assert_success validate_pre(successor_path), "a terminal DDC's internally exact historical policy binding must not be reinterpreted against later live policy bytes"

    stale_policy.fetch("source_binding")["path"] = relative(@fixture.run_dir.join("archive", "missing-historical-routing-policy.md"))
    archived_reviewer_row["path"] = stale_policy.fetch("source_binding").fetch("path")
    stale_source_dispatch.dig("runtime_return", "input_digest")["sha256"] = @fixture.value_sha(
      "lineage" => stale_source_dispatch.fetch("lineage"),
      "review_submission" => stale_source_dispatch.fetch("review_submission"),
      "launch" => stale_source_dispatch.fetch("launch")
    )
    write_yaml(@fixture.sequence_motion_dispatch_path, stale_source_dispatch)
    missing_read = validate_pre(successor_path)
    refute missing_read[:status].success?
    assert_match(/internally exact immutable terminal receipt|claims terminal state without verifiable/, errors(missing_read))

    predecessor = load_yaml(@fixture.sequence_motion_dispatch_path)
    predecessor.dig("lifecycle")["current_state"] = "returned"
    predecessor["director_review"] = nil
    predecessor["promotion"] = nil
    write_yaml(@fixture.sequence_motion_dispatch_path, predecessor)
    nonterminal = validate_pre(successor_path)
    refute nonterminal[:status].success?
    assert_match(/predecessor must close as promoted or hold|overlap HOLD/, errors(nonterminal))

    @fixture.rewrite_sequence_motion(analysis)
    missing_path, = build_successor_attempt(previous_attempt_id: nil)
    missing = validate_pre(missing_path)
    refute missing[:status].success?
    assert_includes errors(missing), "later Sequence Motion attempt must resolve its immutable predecessor DDC in the same run"

    @fixture.rewrite_sequence_motion(analysis)
    exact_predecessor = load_yaml(@fixture.sequence_motion_dispatch_path)
    wrong_predecessor_id = "sequence-motion-analysis-MJ99--attempt-01"
    wrong_predecessor = deep_copy(exact_predecessor)
    wrong_predecessor["dispatch_id"] = wrong_predecessor_id
    wrong_predecessor.dig("lineage")["attempt_id"] = wrong_predecessor_id
    write_yaml(@fixture.sequence_motion_dispatch_path.dirname.join("#{wrong_predecessor_id}.yaml"), wrong_predecessor)
    wrong_successor_path, = build_successor_attempt(previous_attempt_id: wrong_predecessor_id)
    wrong_identity = validate_pre(wrong_successor_path)
    refute wrong_identity[:status].success?
    assert_includes errors(wrong_identity), "previous_attempt_id must name the exact same-Major immediately preceding attempt"
  end

  # Steering case 10/11: active units remain exact-five at 1s; legacy 3s is
  # readable source evidence only and cannot enter a new analysis.
  def test_exact_five_one_second_passes_and_legacy_three_second_is_rejected
    prepare_pre_copy!(analysis)
    assert_success validate_pre

    front = load_yaml(@fixture.front_path)
    unit = front.dig("reference_connection_research", "reference_units", 0, "sequence_unit")
    unit["declared_cadence_seconds"] = 3
    unit.fetch("ordered_frames").each_with_index { |frame, index| frame["timestamp_seconds"] = index * 3.0 }
    write_yaml(@fixture.front_path, front)
    result = validate_pre
    refute result[:status].success?
    assert_match(/legacy three-second units are read-only|not consecutive exact one-second/, errors(result))
  end

  def test_typed_01_adoption_resolves_selected_analysis_and_existing_truth_ids
    result = run_command(RbConfig.ruby, DIRECTION_VALIDATOR, "--json", @fixture.direction_path)
    assert_success result, "01 typed Sequence Motion adoption must pass after central source/profile refresh"

    direction = load_yaml(@fixture.direction_path)
    direction.dig("section_directions", 0, "sequence_motion_adoptions", 0, "applied_still_camera_coverage_ids") << "CAM-UNKNOWN"
    write_yaml(@fixture.direction_path, direction)
    result = run_command(RbConfig.ruby, DIRECTION_VALIDATOR, "--json", @fixture.direction_path)
    refute result[:status].success?
    assert_includes errors(result), "unknown still camera coverage row"

    direction.dig("section_directions", 0).delete("sequence_motion_adoptions")
    schema = schema_result(direction, DIRECTION_SCHEMA)
    refute schema[:status].success?
  end

  def test_01_overall_disposition_aggregate_is_typed_and_reject_has_a_legal_02a_path
    direction = load_yaml(@fixture.direction_path)
    adoption = direction.dig("section_directions", 0, "sequence_motion_adoptions", 0)

    inconsistent_reject = deep_copy(direction)
    inconsistent_reject.dig("section_directions", 0, "sequence_motion_adoptions", 0)["overall_disposition"] = "reject"
    refute schema_result(inconsistent_reject, DIRECTION_SCHEMA)[:status].success?
    write_yaml(@fixture.direction_path, inconsistent_reject)
    inconsistent_result = run_command(RbConfig.ruby, DIRECTION_VALIDATOR, "--json", @fixture.direction_path)
    refute inconsistent_result[:status].success?
    assert_match(/overall Sequence Motion reject requires all nine dimensions rejected|every applied truth id list empty/, errors(inconsistent_result))

    legal_reject = deep_copy(direction)
    rejected_adoption = legal_reject.dig("section_directions", 0, "sequence_motion_adoptions", 0)
    rejected_adoption["overall_disposition"] = "reject"
    rejected_adoption.fetch("dimension_dispositions").keys.each { |dimension| rejected_adoption.fetch("dimension_dispositions")[dimension] = "reject" }
    rejected_adoption["applied_official_core_cut_ids"] = []
    rejected_adoption["applied_still_camera_coverage_ids"] = []
    rejected_adoption["applied_branching_opportunity_ids"] = []
    rejected_adoption["authored_reason"] = "01 independently rejects every advisory Sequence Motion dimension while retaining its own Official Core truth."
    assert schema_result(legal_reject, DIRECTION_SCHEMA)[:status].success?
    write_yaml(@fixture.direction_path, legal_reject)
    direction_result = run_command(RbConfig.ruby, DIRECTION_VALIDATOR, "--json", @fixture.direction_path)
    refute_match(/overall Sequence Motion reject|Sequence Motion .* carry requires/, errors(direction_result))

    storyboard = load_yaml(@fixture.storyboard_path)
    branches = storyboard.fetch("master_storyboard").flat_map { |core| core.dig("compile_seed", "branch_cuts") }
    assert branches.any?, "the global 1..N Branch structure remains present on a legal Sequence reject path"
    branches.each do |branch|
      branch.dig("still_camera_spec")["shot_scale_distance"] = "same legal global branch view"
      branch.dig("still_camera_spec")["camera_height"] = "same legal global branch height"
      branch.dig("still_camera_spec")["direction_angle"] = "same legal global branch direction"
      branch["required_visibility"] = ["one globally required item"]
    end
    write_yaml(@fixture.storyboard_path, storyboard)
    storyboard_result = run_command(RbConfig.ruby, STORYBOARD_VALIDATOR, "--json", @fixture.storyboard_path)
    refute_match(/adopted Sequence Motion findings require|02A Sequence Motion/, errors(storyboard_result))

    inconsistent_adopt = deep_copy(direction)
    inconsistent_adopt.dig("section_directions", 0, "sequence_motion_adoptions", 0)["overall_disposition"] = "adopt"
    refute schema_result(inconsistent_adopt, DIRECTION_SCHEMA)[:status].success?
    assert_equal "partial", adoption.fetch("overall_disposition")
  end

  def test_02a_proves_branch_depth_view_reveal_crop_identity_occlusion_and_continuity_carry
    result = run_command(RbConfig.ruby, STORYBOARD_VALIDATOR, "--json", @fixture.storyboard_path)
    assert_success result, "02A branch carry must pass after central source/profile refresh"

    storyboard = load_yaml(@fixture.storyboard_path)
    branches = storyboard.fetch("master_storyboard").flat_map { |core| core.dig("compile_seed", "branch_cuts") }
    branches.each do |branch|
      camera = branch.fetch("still_camera_spec")
      camera["depth_design"] = ""
      camera["crop_negative_space"] = ""
      camera["shot_scale_distance"] = "same view"
      camera["camera_height"] = "same height"
      camera["direction_angle"] = ""
      branch["required_visibility"] = ["single item"]
      branch["distinct_screen_contribution"] = ""
      branch["continuity_in"] = ""
      branch["continuity_out"] = ""
      branch["branch_time_relation"] = ""
    end
    visible = branches.find { |branch| Array(branch["visible_member_focus"]).any? }
    visible.dig("member_visual_compile_input")["selected_album_member_visual_asset_ids"] = []
    visible.dig("member_visual_compile_input")["head_orientation"] = ""
    visible.dig("member_visual_compile_input")["occlusion"] = ""
    write_yaml(@fixture.storyboard_path, storyboard)
    result = run_command(RbConfig.ruby, STORYBOARD_VALIDATOR, "--json", @fixture.storyboard_path)
    refute result[:status].success?
    detail = errors(result)
    %w[depth crop alternate-view reveal rear/world-direction identity/occlusion continuity start/landing].each do |dimension|
      assert_includes detail, "Sequence Motion #{dimension}"
    end
  end

  def test_pre_copy_is_not_strict_validity_and_changed_returned_bytes_hold
    document = analysis
    prepare_pre_copy!(document)
    assert_success validate_pre
    strict = validate_strict
    refute strict[:status].success?
    assert_match(/must be promoted|independent final CDD/, errors(strict))
    fp = run_command(RbConfig.ruby, FP_VALIDATOR, "--json", @fixture.front_path)
    refute fp[:status].success?
    assert_match(/must be promoted|independent final CDD|owner validation failed/, errors(fp))

    authored = @fixture.run_dir.join("work", "sequence-motion-authored", "attempt-01.yaml")
    authored.dirname.mkpath
    authored.binwrite(@fixture.sequence_motion_analysis_path.binread + "\n")
    changed = validate_pre(authored)
    refute changed[:status].success?
    assert_includes errors(changed), "returned DDC output must bind the exact deterministic target path and authored SHA"
  end

  def test_strict_review_of_different_hash_or_rejected_held_state_fails
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    dispatch.dig("director_review", "reviewed_outputs", 0)["sha256"] = "0" * 64
    dispatch.dig("director_review", "reviewed_outputs", 0)["path"] = relative(@fixture.run_dir.join("research", "sequence-motion-analysis", "wrong.yaml"))
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    result = validate_strict
    refute result[:status].success?
    assert_includes errors(result), "independent final CDD Department Dispatch review"

    @fixture.rewrite_sequence_motion(analysis)
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    dispatch.dig("director_review")["disposition"] = "reject"
    dispatch.dig("lifecycle")["current_state"] = "hold"
    dispatch.dig("lifecycle", "events").last["state"] = "hold"
    dispatch.dig("promotion")["decision"] = "hold"
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    result = validate_strict
    refute result[:status].success?
    assert_includes errors(result), "independent final CDD Department Dispatch review"
  end

  def test_pre_copy_requires_returned_ddc_not_launched
    @fixture.return_sequence_motion_dispatch_for_copy!
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    dispatch.dig("lifecycle")["current_state"] = "launched"
    dispatch.dig("lifecycle")["events"] = dispatch.dig("lifecycle", "events").first(2)
    dispatch["runtime_return"] = nil
    dispatch.dig("review_control")["queue_state"] = "not_eligible"
    dispatch.dig("review_control")["queued_at"] = nil
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
    result = validate_pre
    refute result[:status].success?
    assert_match(/requires DDC lifecycle returned|native_goal.*stale/i, errors(result))
  end

  def test_producer_is_atomic_idempotent_and_holds_different_or_symlink_output
    prepare_pre_copy!(analysis)
    source = @fixture.run_dir.join("work", "sequence-motion-authored", "attempt-01.yaml")
    source.dirname.mkpath
    FileUtils.cp(@fixture.sequence_motion_analysis_path, source)
    @fixture.sequence_motion_analysis_path.unlink

    File.open(@fixture.sequence_motion_analysis_path.dirname, File::RDONLY) do |scope_lock|
      scope_lock.flock(File::LOCK_EX)
      locked = run_command(RbConfig.ruby, PRODUCER, source, "--write")
      refute locked[:status].success?
      assert_includes errors(locked), "atomic Major scope ownership is already held"
      refute @fixture.sequence_motion_analysis_path.exist?
    end

    first = run_command(RbConfig.ruby, PRODUCER, source, "--write")
    assert first[:status].success?, [first[:stdout], first[:stderr]].join("\n")
    assert_equal "copied_pending_cdd_review", JSON.parse(first[:stdout]).fetch("write_state")
    assert_equal source.binread, @fixture.sequence_motion_analysis_path.binread

    identical = run_command(RbConfig.ruby, PRODUCER, source, "--write")
    assert identical[:status].success?
    assert_equal "existing_identical_pending_cdd_review", JSON.parse(identical[:stdout]).fetch("write_state")

    @fixture.sequence_motion_analysis_path.binwrite("different bytes\n")
    different = run_command(RbConfig.ruby, PRODUCER, source, "--write")
    refute different[:status].success?
    assert_includes errors(different), "output already exists with different bytes"

    @fixture.sequence_motion_analysis_path.unlink
    File.symlink(source, @fixture.sequence_motion_analysis_path)
    symlink = run_command(RbConfig.ruby, PRODUCER, source, "--write")
    refute symlink[:status].success?
    assert_includes errors(symlink), "output path is a symlink"
  end

  def test_producer_rolls_back_when_directory_persistence_fails_after_link
    prepare_pre_copy!(analysis)
    source = @fixture.run_dir.join("work", "sequence-motion-authored", "attempt-01.yaml")
    source.dirname.mkpath
    FileUtils.cp(@fixture.sequence_motion_analysis_path, source)
    @fixture.sequence_motion_analysis_path.unlink

    shim = @fixture.run_dir.join("work", "fail-first-directory-fsync.rb")
    shim.binwrite(<<~RUBY)
      class File
        alias_method :idol_sequence_original_fsync, :fsync
        def fsync
          target = ENV["IDOL_SEQUENCE_FAIL_DIRECTORY_FSYNC"]
          if target && !Thread.current[:idol_sequence_directory_fsync_failed] && File.directory?(path) && File.expand_path(path) == File.expand_path(target)
            Thread.current[:idol_sequence_directory_fsync_failed] = true
            raise Errno::EIO, "injected directory fsync failure"
          end
          idol_sequence_original_fsync
        end
      end
    RUBY
    stdout, stderr, status = Open3.capture3(
      {
        "RUBYOPT" => "-r#{shim}",
        "IDOL_SEQUENCE_FAIL_DIRECTORY_FSYNC" => @fixture.sequence_motion_analysis_path.dirname.to_s
      },
      RbConfig.ruby,
      PRODUCER.to_s,
      source.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    result = {stdout: stdout, stderr: stderr, status: status}
    refute status.success?
    assert_includes errors(result), "atomic exact-copy persistence failed after link"
    refute @fixture.sequence_motion_analysis_path.exist?, "a failed post-link directory fsync must roll back the just-created output"
  end

  def test_producer_post_copy_rechecks_auto_discovered_peer_and_rolls_back
    prepare_pre_copy!(analysis)
    source = @fixture.run_dir.join("work", "sequence-motion-authored", "attempt-01.yaml")
    source.dirname.mkpath
    FileUtils.cp(@fixture.sequence_motion_analysis_path, source)
    @fixture.sequence_motion_analysis_path.unlink

    peer_path = @fixture.run_dir.join("work", "department-dispatches", "sequence-motion-analysis-MJ01--attempt-02.yaml")
    peer = load_yaml(@fixture.sequence_motion_dispatch_path)
    peer["dispatch_id"] = "sequence-motion-analysis-MJ01--attempt-02"
    peer.dig("lineage")["attempt_id"] = peer.fetch("dispatch_id")
    peer.dig("lineage")["attempt_number"] = 2
    peer.dig("lineage")["previous_attempt_id"] = "sequence-motion-analysis-MJ01--attempt-01"
    peer.dig("launch", "task")["task_id"] = peer.fetch("dispatch_id")
    peer.dig("launch", "task", "exact_scope")["artifact_paths"] = [relative(@fixture.sequence_motion_analysis_path.dirname.join("attempt-02.yaml"))]
    peer.dig("lifecycle")["current_state"] = "launched"

    watcher = Process.fork do
      sleep(0.001) until @fixture.sequence_motion_analysis_path.exist?
      write_yaml(peer_path, peer)
      exit!(0)
    end
    result = run_command(RbConfig.ruby, PRODUCER, source, "--write")
    Process.wait(watcher)
    watcher_reaped = true
    refute result[:status].success?
    assert_match(/copied bytes failed post-copy transport admission.*overlap HOLD/, errors(result))
    refute @fixture.sequence_motion_analysis_path.exist?, "post-copy overlap HOLD must roll back only the just-created exact-copy output"
  ensure
    Process.wait(watcher) if watcher && !watcher_reaped
  end

  def test_repo_local_symlink_to_outside_is_rejected
    prepare_pre_copy!(analysis)
    @outside_dir = Pathname.new(Dir.mktmpdir("idol-sma-outside-", "/private/tmp"))
    outside = @outside_dir.join("outside.yaml")
    outside.binwrite(@fixture.sequence_motion_analysis_path.binread)
    link = @fixture.run_dir.join("work", "outside-analysis.yaml")
    File.symlink(outside, link)
    result = validate_pre(link)
    refute result[:status].success?
    assert_match(/outside the repository|cannot be a symlink/, errors(result))
  end

  def test_admitted_range_may_be_broader_than_the_five_sequence_samples
    document = build_inspected_observed_analysis
    document.dig("candidate_analyses", 0, "continuous_motion_source_review", "source_video", "admitted_time_range_seconds")["end"] = 10.0
    prepare_pre_copy!(document)
    assert_success validate_pre, "a longer admitted playback range must remain legal when the five Sequence timestamps stay inside it"
  end

  def test_unbound_inspected_fixture_bytes_remain_valid_without_measurement
    document = build_inspected_observed_analysis
    refute document.dig("candidate_analyses", 0, "continuous_motion_source_review").key?("machine_measurement_binding")
    prepare_pre_copy!(document)
    assert_success validate_pre, "legacy unbound inspected analyses must remain valid"
  end

  def test_explicit_binding_holds_without_crash_when_inspected_video_is_missing
    skip "ffmpeg/ffprobe or measurement script missing" unless ffmpeg_bin && ffprobe_bin && MEASUREMENT_SCRIPT.file? && MEASUREMENT_SCHEMA.file?
    document = build_inspected_observed_analysis(media: :synthetic_video)
    video_path = inspected_video_path
    measurement_path = @fixture.run_dir.join("research", "sequence-motion-analysis", "S01--MJ01", "attempt-01.measurement.json")
    measure = run_measurement!(video_path, measurement_path)
    assert measure[:status].success?, [measure[:stdout], measure[:stderr]].join("\n")
    document.dig("candidate_analyses", 0, "continuous_motion_source_review")["machine_measurement_binding"] = {
      "path" => relative(measurement_path),
      "sha256" => Digest::SHA256.file(measurement_path).hexdigest,
      "schema_version" => "idol_sequence_motion_machine_measurement.v1"
    }
    video_path.unlink
    prepare_pre_copy!(document)
    result = validate_pre
    refute result[:status].success?
    detail = [errors(result), result[:stderr], result[:stdout]].join("\n")
    refute_match(/undefined method/, detail)
    assert_match(/machine measurement cannot be checked without a live inspected video|source video is missing or outside the repository/, detail)
  end

  def test_explicit_measurement_binding_producer_and_stale_tamper
    skip "ffmpeg/ffprobe or measurement script missing" unless ffmpeg_bin && ffprobe_bin && MEASUREMENT_SCRIPT.file? && MEASUREMENT_SCHEMA.file?
    document = build_inspected_observed_analysis(media: :synthetic_video)
    video_path = inspected_video_path
    measurement_path = @fixture.run_dir.join("research", "sequence-motion-analysis", "S01--MJ01", "attempt-01.measurement.json")
    measure = run_measurement!(video_path, measurement_path)
    assert measure[:status].success?, [measure[:stdout], measure[:stderr]].join("\n")
    document.dig("candidate_analyses", 0, "continuous_motion_source_review")["machine_measurement_binding"] = {
      "path" => relative(measurement_path),
      "sha256" => Digest::SHA256.file(measurement_path).hexdigest,
      "schema_version" => "idol_sequence_motion_machine_measurement.v1"
    }
    prepare_pre_copy!(document)
    assert_success validate_pre, "explicit measurement binding must pass transport admission"

    source = @fixture.run_dir.join("work", "sequence-motion-authored", "attempt-01.yaml")
    source.dirname.mkpath
    FileUtils.cp(@fixture.sequence_motion_analysis_path, source)
    @fixture.sequence_motion_analysis_path.unlink
    copied = run_command(RbConfig.ruby, PRODUCER, source, "--write")
    assert copied[:status].success?, [copied[:stdout], copied[:stderr]].join("\n")
    assert_success validate_pre, "exact-copy preparer must preserve the explicit measurement binding"

    stale = JSON.parse(measurement_path.read)
    stale["source"]["sha256"] = "0" * 64
    measurement_path.write(JSON.pretty_generate(stale) + "\n")
    rebound = load_yaml(@fixture.sequence_motion_analysis_path)
    rebound.dig("candidate_analyses", 0, "continuous_motion_source_review")["machine_measurement_binding"]["sha256"] = Digest::SHA256.file(measurement_path).hexdigest
    prepare_pre_copy!(rebound)
    tampered = validate_pre
    refute tampered[:status].success?
    assert_match(/source SHA must equal the live inspected video SHA/, errors(tampered))
  end

  def test_disjoint_major_collection_paths_can_coexist_without_a_single_file_collision
    root = @fixture.run_dir.join("research", "sequence-motion-analysis")
    first = root.join("S01--MJ01", "attempt-01.yaml")
    second = root.join("S02--MJ02", "attempt-01.yaml")
    second.dirname.mkpath
    second.binwrite("disjoint major evidence\n")
    assert first.file?
    assert second.file?
    refute_equal first, second
  end

  private

  def analysis
    load_yaml(@fixture.sequence_motion_analysis_path)
  end

  def prepare_pre_copy!(document)
    @fixture.rewrite_sequence_motion(document)
    @fixture.return_sequence_motion_dispatch_for_copy!
  end

  def omit_sequence_prompt_clause!(clause, from:)
    dispatch = load_yaml(@fixture.sequence_motion_dispatch_path)
    case from
    when :rendered_prompt
      compiled = dispatch.dig("launch", "compiled_launch_prompt")
      compiled["rendered_prompt"] = compiled.fetch("rendered_prompt").sub(clause, "")
      compiled["rendered_prompt_sha256"] = Digest::SHA256.hexdigest(compiled.fetch("rendered_prompt"))
    when :quality_requirement
      quality = dispatch.dig("launch", "requirement_manifest").find do |row|
        row.fetch("requirement_id") == "QUALITY-SEQUENCE-MOTION-ACCEPTANCE"
      end
      quality["affected_scope"] = quality.fetch("affected_scope").sub(clause, "")
    else
      raise ArgumentError, "unknown omission surface #{from}"
    end
    write_yaml(@fixture.sequence_motion_dispatch_path, dispatch)
  end

  def build_successor_attempt(previous_attempt_id:)
    front = load_yaml(@fixture.front_path)
    artifact_path = @fixture.run_dir.join("research", "sequence-motion-analysis", "S01--MJ01", "attempt-02.yaml")
    dispatch_path = @fixture.run_dir.join("work", "department-dispatches", "sequence-motion-analysis-MJ01--attempt-02.yaml")
    artifact_path.dirname.mkpath
    artifact_path.binwrite("pending successor bytes\n")
    provisional = @fixture.sequence_motion_dispatch_document(
      front,
      artifact_path: artifact_path,
      audio_motion_map_path: @fixture.audio_motion_map_path,
      attempt_number: 2,
      previous_attempt_id: previous_attempt_id
    )
    write_yaml(dispatch_path, provisional)
    document = ActiveSequenceMotionFixture.document(
      @fixture,
      front,
      dispatch_path: dispatch_path,
      audio_motion_map_path: @fixture.audio_motion_map_path,
      attempt_key: "attempt-02"
    )
    write_yaml(artifact_path, document)
    final_dispatch = @fixture.sequence_motion_dispatch_document(
      front,
      artifact_path: artifact_path,
      audio_motion_map_path: @fixture.audio_motion_map_path,
      attempt_number: 2,
      previous_attempt_id: previous_attempt_id
    )
    write_yaml(dispatch_path, final_dispatch)
    returned = load_yaml(dispatch_path)
    returned.dig("lifecycle")["current_state"] = "returned"
    returned.dig("lifecycle")["events"] = Array(returned.dig("lifecycle", "events")).first(3)
    returned.dig("review_control")["queue_state"] = "queued"
    returned.dig("review_control")["review_lease"] = nil
    returned.dig("review_control")["promotion_lease"] = nil
    returned["director_review"] = nil
    returned["promotion"] = nil
    write_yaml(dispatch_path, returned)
    [artifact_path, dispatch_path]
  end

  def build_inspected_observed_analysis(media: :fixture_bytes)
    front = load_yaml(@fixture.front_path)
    unit = front.dig("reference_connection_research", "reference_units", 0, "sequence_unit")
    intake_root = @fixture.run_dir.join("research", "reference-intake", unit.fetch("sequence_unit_id"))
    manifest_path = intake_root.join("qc-sheet-manifest.json")
    video_path = intake_root.join("source-video.mp4")
    sheet_path = intake_root.join("sheets", "part-001.png")
    cell_paths = 5.times.map { |index| intake_root.join("cells", format("cell-%02d.png", index + 1)) }
    manifest_path.dirname.mkpath
    sheet_path.dirname.mkpath
    cell_paths.first.dirname.mkpath
    if media == :synthetic_video
      write_synthetic_mp4!(video_path)
    else
      video_path.binwrite("registered source video fixture bytes\n")
    end
    sheet_path.binwrite("registered source sheet fixture bytes\n")
    cell_paths.each_with_index { |path, index| path.binwrite("registered source cell #{index + 1} fixture bytes\n") }
    video_sha = Digest::SHA256.file(video_path).hexdigest
    sheet_sha = Digest::SHA256.file(sheet_path).hexdigest
    cells = cell_paths.each_with_index.map do |path, index|
      {
        "cell_id" => format("CELL-%02d", index + 1),
        "order" => index + 1,
        "source_timestamp_seconds" => index.to_f,
        "label_timestamp_seconds" => index.to_f,
        "label" => format("src %06.3fs / song %06.3fs", index.to_f, index.to_f),
        "cell_crop" => {
          "path" => relative(path),
          "sha256" => Digest::SHA256.file(path).hexdigest,
          "size_bytes" => path.size
        }
      }
    end
    manifest = {
      "schema_version" => "idol_video_qc_sheet_manifest.v1",
      "video" => relative(video_path),
      "source_video" => {"path" => relative(video_path), "sha256" => video_sha, "size_bytes" => video_path.size},
      "preset" => "one-second",
      "interval_seconds" => 1.0,
      "label_offset_seconds" => 0.0,
      "segment_duration_seconds" => 60.0,
      "columns" => 5,
      "thumb_width" => 280,
      "thumb_height" => 158,
      "sheet_count" => 1,
      "sheets" => [{
        "part_index" => 1,
        "path" => relative(sheet_path),
        "source_time_range" => "0.000-4.000",
        "timestamp_count" => 5,
        "timestamps" => [0.0, 1.0, 2.0, 3.0, 4.0],
        "cells" => cells,
        "sha256" => sheet_sha,
        "size_bytes" => sheet_path.size
      }]
    }
    manifest_path.binwrite(JSON.pretty_generate(manifest) + "\n")
    unit["manifest"] = {"path" => relative(manifest_path), "sha256" => Digest::SHA256.file(manifest_path).hexdigest}
    unit.fetch("ordered_frames").each_with_index do |frame, index|
      frame["artifact"] = {"path" => relative(cell_paths.fetch(index)), "sha256" => Digest::SHA256.file(cell_paths.fetch(index)).hexdigest}
    end
    write_yaml(@fixture.front_path, front)

    provisional = @fixture.sequence_motion_dispatch_document(
      front,
      artifact_path: @fixture.sequence_motion_analysis_path,
      audio_motion_map_path: @fixture.audio_motion_map_path
    )
    write_yaml(@fixture.sequence_motion_dispatch_path, provisional)
    document = ActiveSequenceMotionFixture.document(
      @fixture,
      front,
      dispatch_path: @fixture.sequence_motion_dispatch_path,
      audio_motion_map_path: @fixture.audio_motion_map_path,
      attempt_key: "attempt-01"
    )
    candidate = document.dig("candidate_analyses", 0)
    candidate["continuous_motion_source_review"] = {
      "inspection_status" => "inspected",
      "source_video" => {
        "path" => relative(video_path),
        "sha256" => video_sha,
        "source_identity" => front.dig("reference_connection_research", "reference_units", 0, "source_identity"),
        "inspected_locator" => front.dig("reference_connection_research", "reference_units", 0, "selected_locator"),
        "governing_sequence_unit_id" => unit.fetch("sequence_unit_id"),
        "governing_manifest_path" => unit.dig("manifest", "path"),
        "admitted_time_range_seconds" => {"start" => 0.0, "end" => 4.0}
      },
      "unavailable_reason" => nil,
      "observed_interframe_events" => [{
        "event_id" => "OBS_LATERAL_PAN",
        "evidence_status" => "observed",
        "source_time_range_seconds" => {"start" => 0.0, "end" => 2.0},
        "observed_motion_family" => "pan",
        "observed_perceptual_functions" => ["directionality", "continuity", "reveal"],
        "observed_body_action_fact" => "object_interaction",
        "observed_gaze_and_head_fact" => "not_visible",
        "observed_camera_translation_fact" => "none_observed",
        "observed_camera_rotation_fact" => "pan_left",
        "observed_rotation_degrees" => 32.0,
        "observed_full_orbit_completed" => false,
        "observed_lens_change_fact" => "none_observed",
        "observed_angle_change_fact" => "locked",
        "observed_composition_change_fact" => "subject_shifts_right",
        "observed_depth_change_fact" => "parallax_increases",
        "observed_occlusion_change_fact" => "decreases",
        "observed_reveal_change_fact" => "reveals_environment",
        "observed_speed_profile" => "A steady lateral move eases before the midpoint.",
        "observed_entry_state" => "Guide at frame right with the hand entering.",
        "observed_exit_state" => "Guide nearer center with the registered contact readable.",
        "related_sequence_unit_ids" => [unit.fetch("sequence_unit_id")],
        "confidence" => "high"
      }, {
        "event_id" => "OBS_REPEATED_ZOOM_PULSE",
        "evidence_status" => "observed",
        "source_time_range_seconds" => {"start" => 2.0, "end" => 4.0},
        "observed_motion_family" => "zoom_pulse",
        "observed_perceptual_functions" => ["impact", "scale", "acceleration", "deceleration"],
        "observed_body_action_fact" => "intentional_hold",
        "observed_gaze_and_head_fact" => "stable_nonfrontal",
        "observed_camera_translation_fact" => "none_observed",
        "observed_camera_rotation_fact" => "none_observed",
        "observed_rotation_degrees" => 0.0,
        "observed_full_orbit_completed" => false,
        "observed_lens_change_fact" => "repeated_in_out",
        "observed_angle_change_fact" => "locked",
        "observed_composition_change_fact" => "compound",
        "observed_depth_change_fact" => "compound",
        "observed_occlusion_change_fact" => "none_observed",
        "observed_reveal_change_fact" => "none_observed",
        "observed_speed_profile" => "Quick in-out pulse, brief settle, then a smaller repeated pulse.",
        "observed_entry_state" => "Medium scale with three planes readable.",
        "observed_exit_state" => "Returned medium scale with the guide state retained.",
        "related_sequence_unit_ids" => [unit.fetch("sequence_unit_id")],
        "confidence" => "high"
      }]
    }
    opportunity = candidate.fetch("inferred_camera_opportunities").first
    opportunity["inference_basis"] = ["observed_interframe_event", "sequence_frame_observations", "contextual_flow_reading", "major_screen_job", "audio_motion_cue"]
    opportunity["observed_event_ids"] = ["OBS_LATERAL_PAN"]
    opportunity["geometry_support"] = "The observed lateral pan supports directionality, while final intensity remains for 03V."
    opportunity.dig("joint_motion_reading")["camera_translation"] = "An observed lateral pan translates the composition across the stable action axis."
    opportunity.dig("joint_motion_reading")["camera_rotation"] = "The observed pan rotates view direction laterally without implying an orbit."
    opportunity.dig("joint_motion_reading")["lens_change"] = "No lens change belongs to this first observed event."
    opportunity["literal_transfer"] = {
      "supported" => true,
      "source_motion_family" => "pan",
      "observed_event_ids" => ["OBS_LATERAL_PAN"],
      "perceptual_functions" => ["directionality", "continuity", "reveal"],
      "camera_translation_fact" => "none_observed",
      "camera_rotation_fact" => "pan_left",
      "rotation_degrees" => 32.0,
      "full_orbit_completed" => false,
      "lens_change_fact" => "none_observed",
      "hold_reason" => nil
    }
    zoom_opportunity = deep_copy(opportunity)
    zoom_opportunity["opportunity_id"] = "INF_MJ01_ZOOM_PULSE"
    zoom_opportunity["observed_event_ids"] = ["OBS_REPEATED_ZOOM_PULSE"]
    zoom_opportunity["perceptual_functions"] = ["impact", "scale", "acceleration", "deceleration"]
    zoom_opportunity["geometry_support"] = "The repeated observed scale pulses support bounded in-out energy without prescribing 03V intensity."
    zoom_opportunity.dig("joint_motion_reading")["camera_translation"] = "Physical translation cannot be separated from lens change in the admitted source and is not claimed."
    zoom_opportunity.dig("joint_motion_reading")["camera_rotation"] = "No rotation is observed in the pulse event."
    zoom_opportunity.dig("joint_motion_reading")["lens_change"] = "Two observed tighten-release scale pulses support the zoom-pulse family."
    zoom_opportunity.dig("joint_motion_reading")["continuous_camera_energy_review"] = "continuous_camera_energy_supported_contextually"
    zoom_opportunity["literal_transfer"] = {
      "supported" => true,
      "source_motion_family" => "zoom_pulse",
      "observed_event_ids" => ["OBS_REPEATED_ZOOM_PULSE"],
      "perceptual_functions" => ["impact", "scale", "acceleration", "deceleration"],
      "camera_translation_fact" => "none_observed",
      "camera_rotation_fact" => "none_observed",
      "rotation_degrees" => 0.0,
      "full_orbit_completed" => false,
      "lens_change_fact" => "repeated_in_out",
      "hold_reason" => nil
    }
    zoom_opportunity["function_equivalent_transfer"] = {
      "supported" => true,
      "alternative_motion_families" => ["repeated_in_out", "move_to_settle"],
      "equivalence_reason" => "A bounded repeated in-out or move-to-settle can preserve the observed impact function if 03V pixels support it."
    }
    candidate.fetch("inferred_camera_opportunities") << zoom_opportunity
    document.dig("dispatch_and_authorship")["result_sha256"] = @fixture.value_sha(
      "candidate_analyses" => document.fetch("candidate_analyses"),
      "comparative_recommendation" => document.fetch("comparative_recommendation")
    )
    write_yaml(@fixture.sequence_motion_analysis_path, document)
    final_dispatch = @fixture.sequence_motion_dispatch_document(
      front,
      artifact_path: @fixture.sequence_motion_analysis_path,
      audio_motion_map_path: @fixture.audio_motion_map_path
    )
    write_yaml(@fixture.sequence_motion_dispatch_path, final_dispatch)
    @fixture.return_sequence_motion_dispatch_for_copy!
    document
  end

  def validate_pre(path = @fixture.sequence_motion_analysis_path, *extra)
    run_command(RbConfig.ruby, VALIDATOR, "--json", "--pre-cdd-copy", *extra, path)
  end

  def validate_strict(path = @fixture.sequence_motion_analysis_path)
    run_command(RbConfig.ruby, VALIDATOR, "--json", path)
  end

  def schema_result(document, schema)
    path = @fixture.run_dir.join("work", "schema-probe-#{schema.basename('.schema.json')}.yaml")
    write_yaml(path, document)
    run_command(PYTHON, SCHEMA_VALIDATOR, schema, path)
  end

  def run_command(*command)
    stdout, stderr, status = Open3.capture3(*command.map(&:to_s), chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def errors(result)
    parsed = JSON.parse(result[:stdout])
    Array(parsed["errors"]).join("\n")
  rescue JSON::ParserError
    [result[:stderr], result[:stdout]].join("\n")
  end

  def assert_success(result, message = nil)
    assert result[:status].success?, [message, errors(result)].compact.join("\n")
  end

  def assert_only_central_profile_hold(result)
    refute result[:status].success?, "central dirty SHA rows are expected to HOLD until central refresh"
    detail = errors(result)
    assert_match(/SHA-256 is stale|must exact-copy the selected checkpoint (?:skill|read) bindings/, detail)
    refute_match(/Sequence Motion (?:depth|crop|alternate|reveal|identity|continuity).*requires/i, detail)
  end

  def load_yaml(path)
    YAML.safe_load(Pathname.new(path).read, aliases: true)
  end

  def write_yaml(path, value)
    path = Pathname.new(path)
    path.dirname.mkpath
    path.binwrite(YAML.dump(value))
    path
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def ffmpeg_bin
    @ffmpeg_bin ||= ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].find { |path| File.executable?(path) } || `command -v ffmpeg`.to_s.strip
    @ffmpeg_bin.empty? ? nil : @ffmpeg_bin
  end

  def ffprobe_bin
    @ffprobe_bin ||= ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"].find { |path| File.executable?(path) } || `command -v ffprobe`.to_s.strip
    @ffprobe_bin.empty? ? nil : @ffprobe_bin
  end

  def inspected_video_path
    front = load_yaml(@fixture.front_path)
    unit_id = front.dig("reference_connection_research", "reference_units", 0, "sequence_unit", "sequence_unit_id")
    @fixture.run_dir.join("research", "reference-intake", unit_id, "source-video.mp4")
  end

  def write_synthetic_mp4!(path)
    stdout, stderr, status = Open3.capture3(
      ffmpeg_bin,
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "lavfi",
      "-i",
      "color=c=green:s=160x90:r=24:d=5",
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      path.to_s
    )
    raise "ffmpeg synthetic video failed: #{stderr}#{stdout}" unless status.success?
  end

  def run_measurement!(video_path, output_path)
    output_path.dirname.mkpath
    cache_dir = output_path.dirname.join("_machine-cache")
    run_command(
      PYTHON,
      MEASUREMENT_SCRIPT,
      "--repo-root",
      ROOT,
      "--video",
      video_path,
      "--output",
      output_path,
      "--cache-dir",
      cache_dir,
      "--admitted-start",
      "0",
      "--admitted-end",
      "4",
      "--sample-times",
      "0,1,2,3,4"
    )
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
