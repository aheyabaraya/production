# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "yaml"
require_relative "support/department_dispatch_profile_fixture"

class ValidateDepartmentDispatchTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb")
  PROFILE_REGISTRY = ROOT.join("automation", "harness-skill-load-profiles.yaml")
  STUDIO_KERNEL = ROOT.join("skills", "idol-orchestrator", "references", "provider-neutral-studio-kernel.md")
  SECTION_CLI = ROOT.join("scripts", "idol_harness_sections.rb")
  SECTION_SOURCE = ROOT.join("runs", "2026-07-05", "0705_GIRL_BADUK_WORLD_SIGNAL", "01-song-choreography-performance-mv-map.yaml")
  V19_OUTPUT_CASES = {
    "decision_set" => {
      role: "department_worker",
      bindings: %w[selected_source_evidence]
    },
    "director_development_report" => {
      role: "creative_development_director",
      bindings: %w[decision_set]
    },
    "section_dispatch_map" => {
      role: "creative_development_director",
      bindings: %w[selected_audio_analysis audio_motion_map]
    },
    "section_reference_set" => {
      role: "department_worker",
      bindings: %w[section_dispatch_map reference_working_index selected_source_evidence]
    },
    "reference_working_index_delta" => {
      role: "department_worker",
      bindings: %w[reference_working_index selected_source_evidence]
    }
  }.freeze
  V19_REVIEW_CRITERIA = {
    "decision_set" => %w[actual_selected_media source_to_screen_delta nonoverlap],
    "director_development_report" => %w[one_work_synthesis raw_pool_removed material_risk],
    "section_dispatch_map" => %w[independent_visual_job connected_boundaries],
    "section_reference_set" => %w[comparison_floor source_function_diversity entry_exit],
    "reference_working_index_delta" => %w[level_a_b_c deduplication],
    "pre_02a_section_working_shard" => %w[observable_nonredundant_events anti_flat_current_work_evidence section_boundary],
    "founder_briefing_projection" => %w[reviewed_milestone_only source_set_exactness projection_authority_boundary]
  }.freeze
  BASE_REVIEW_CRITERIA = %w[
    goal_opened_and_pursued
    founder_instruction_coverage
    owning_skill_application
    schema_and_contract_conformance
    current_assignment_resolution
    required_output_coverage
    observable_specificity
    source_and_pixel_grounding
    storyline_preservation
    locks_scope_and_unaffected_truth
    honest_completion_state
  ].freeze
  REQUIREMENT_CATEGORIES = %w[founder skill policy contract schema output quality hold goal].freeze

  def setup
    @title_root = ROOT.join("runs", "harness-test", "department-dispatch")
    @run = @title_root.join("DISPATCH_#{SecureRandom.hex(4).upcase}")
    @source = @run.join("research", "source.yaml")
    @output = @run.join("00A-song-lock.yaml")
    @dispatch_id = "SONG_LOCK_#{SecureRandom.hex(3).upcase}"
    @dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    @skill = ROOT.join("skills", "idol-song-lock", "SKILL.md")
    @linked_read = ROOT.join("AGENTS.md")
    @source.dirname.mkpath
    @dispatch.dirname.mkpath
    @source.write("selected_song: fixture\n")
    @output.write("schema_version: '1.5'\nstatus: locked\n")
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    @title_root.rmdir if @title_root&.directory? && @title_root.children.empty?
    album_root = ROOT.join("runs", "harness-test")
    album_root.rmdir if album_root.directory? && album_root.children.empty?
  end

  def test_promoted_dispatch_binds_runtime_reads_outputs_and_director_review
    write_dispatch(promoted_dispatch)
    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal "pass", result["status"]
    assert_equal "promoted", result["lifecycle_state"]
    assert_equal [relative(@output)], result["outputs"]
  end

  def test_dummy_startup_pilot_closes_one_cdd_reviewed_overall_promoted_worker_result
    rule = V19_OUTPUT_CASES.fetch("decision_set")
    document = v19_dispatch(
      output_kind: "decision_set",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings),
      owner: "fixture-reference-worker"
    )
    launch = document.fetch("launch")
    launch.fetch("authority")["director_owner"] = "fixture-cdd"
    launch.fetch("recipient").merge!(
      "owner" => "fixture-cdd",
      "role" => "creative_development_director",
      "return_route" => "director_output_review"
    )
    document.dig("runtime_return", "wake_event")["recipient_role"] = "creative_development_director"
    document.fetch("director_review")["director"] = {
      "owner" => "fixture-cdd",
      "role" => "creative_development_director"
    }
    document.dig("review_control", "review_lease")["director_owner"] = "fixture-cdd"
    document.dig("lifecycle", "events", 0)["actor"] = "fixture-cdd"
    document.dig("lifecycle", "events", 3)["actor"] = "fixture-cdd"
    sync_v18_promotion(document)
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal "pass", result.fetch("status")
    assert_equal "promoted", result.fetch("lifecycle_state")
    assert_equal "fixture-cdd", document.dig("director_review", "director", "owner")
    assert_equal "overall_director", document.dig("promotion", "promoter", "role")
  end

  def test_v8_rejects_launch_prompt_without_goal_first_directive
    document = promoted_dispatch
    prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt")
    document.dig("launch", "compiled_launch_prompt")["rendered_prompt"] = prompt.lines.drop(1).join.sub(/\A\s+/, "")
    refresh_compiled_launch_digest(document)
    refresh_input_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "must begin with the registered Goal-first runtime directive"
  end

  def test_v8_rejects_goal_opened_after_reads_or_creative_work
    document = promoted_dispatch
    document.dig("runtime_return", "runtime_goal")["opened_at"] = "2026-08-03T10:01:40+09:00"
    refresh_result_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "runtime Goal must open before every required skill or linked-module read completes"
    assert_includes stderr, "runtime Goal must open before creative work starts"
  end

  def test_v8_worker_self_check_must_exact_cover_every_requirement
    document = promoted_dispatch
    document.dig("runtime_return", "worker_fulfillment_claims").pop
    refresh_result_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "worker fulfillment claims must exact-cover launch.requirement_manifest requirement ids"
  end

  def test_v8_director_must_independently_read_the_exact_governing_bytes
    document = promoted_dispatch
    document.dig("director_review", "reviewer_read_closure").pop
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "Director reviewer read closure must exact-cover required skills, linked modules, and semantically reviewed skill/policy/contract/schema sources"
  end

  def test_v8_director_must_judge_every_declared_requirement
    document = promoted_dispatch
    document.dig("director_review", "requirement_results").pop
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "Director requirement results must exact-cover launch.requirement_manifest requirement ids"
  end

  def test_fp_cdd_readiness_includes_pre00_expand_recipe_row
    document = promoted_dispatch(owner_role: "creative_development_director")
    ids = document.dig("launch", "requirement_manifest").map { |row| row["requirement_id"] }
    assert_includes ids, "POLICY-PRE00-EXPAND-PLANT-MAJOR-ADD-CORE"
    assert_includes ids, "POLICY-EXTRA-CORE-FAST-TEMPO"
  end

  def test_fp_cdd_readiness_holds_when_recipe_rows_are_missing
    document = promoted_dispatch(owner_role: "creative_development_director")
    document.dig("launch", "requirement_manifest").reject! do |row|
      row["requirement_id"].to_s.start_with?("OUTPUT-FP-", "OUTPUT-SEQUENCE-", "POLICY-REFERENCE-", "CONTRACT-STORYLINE-", "HOLD-CORE-", "OUTPUT-CAMERA-")
    end
    refresh_input_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "requirement_manifest missing immutable recipe row OUTPUT-FP-ROUTES-ABC"
  end

  def test_fp_cdd_readiness_holds_generic_follow_skill_row_when_recipe_rows_exist
    document = promoted_dispatch(owner_role: "creative_development_director")
    skill_row = document.dig("launch", "requirement_manifest").find { |row| row["category"] == "skill" }
    skill_row["expected_output_target"] = "follow the registered skill"
    refresh_input_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "must not PASS as a generic follow-skill row when recipe rows exist"
  end

  def test_closed_director_review_holds_null_evidence_sha256
    document = promoted_dispatch
    document.dig("director_review", "requirement_results").first["evidence_sha256"] = nil
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "closed director_review.requirement_results[0].evidence_sha256 must not be null"
  end

  def test_v2_rejects_v1_authoring
    document = promoted_dispatch
    document["schema_version"] = "idol-department-dispatch.v1"
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "schema validation failed"
  end

  def test_v2_requires_an_explicit_bounded_output_kind
    document = promoted_dispatch
    document.dig("launch", "bounded_output").delete("output_kind")
    refresh_input_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "schema validation failed"
  end

  def test_v3_binds_attempt_lineage_into_the_runtime_input_digest
    document = promoted_dispatch
    document.fetch("lineage")["session_id"] = "DIFFERENT_SESSION"
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "input_digest SHA-256 is stale"
  end

  def test_v3_rejects_an_unregistered_compiled_launch_checkpoint
    document = promoted_dispatch
    document.dig("launch", "compiled_launch_prompt", "selected_profile")["checkpoint_id"] = "not_registered"
    refresh_compiled_launch_digest(document)
    refresh_input_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "compiled launch selected checkpoint is not registered"
  end

  def test_v3_rejects_a_stale_rendered_launch_prompt_hash
    document = promoted_dispatch
    document.dig("launch", "compiled_launch_prompt")["rendered_prompt"] = "tampered launch prompt"
    refresh_input_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "compiled launch rendered prompt SHA-256 is stale"
  end

  def test_v3_rejects_a_launch_command_missing_a_registered_block
    document = promoted_dispatch
    prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt")
    prompt = prompt.sub(/\n\n## 09 Quality Proof\n.*?(?=\n\n## 10 Return-Ready Conditions)/m, "")
    document.dig("launch", "compiled_launch_prompt")["rendered_prompt"] = prompt
    refresh_compiled_launch_digest(document)
    refresh_input_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "must contain \"## 09 Quality Proof\" exactly once"
  end

  def test_v8_fixture_exact_projects_manifest_and_anti_flat_rows_to_registered_blocks
    document = promoted_dispatch
    prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt")
    document.dig("launch", "requirement_manifest").each do |requirement|
      line = dispatch_fixture_requirement_projection_line(requirement)
      heading = case requirement.fetch("category")
                when "founder" then "## 03 Current Creative Job"
                when "quality" then "## 09 Quality Proof"
                else "## 07 Required Work"
                end
      payload = JSON.parse(line.delete_prefix(DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX))
      assert_equal DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_FIELDS, payload.keys
      assert_equal 1, prompt.lines.count { |prompt_line| prompt_line.chomp == line }, requirement.fetch("requirement_id")
      assert_includes prompt_block(prompt, heading), line, requirement.fetch("requirement_id")
    end
    document.dig("launch", "bounded_output", "anti_flat_evidence_requirements").each do |requirement|
      line = dispatch_fixture_anti_flat_projection_line(requirement)
      assert_equal 1, prompt.lines.count { |prompt_line| prompt_line.chomp == line }, requirement
      assert_includes prompt_block(prompt, "## 09 Quality Proof"), line, requirement
    end
  end

  def test_v8_rejects_each_projected_block_when_an_applicable_line_is_omitted
    prompt_projection_cases(promoted_dispatch).each do |label, entry|
      document = promoted_dispatch
      prompt = remove_prompt_line(
        document.dig("launch", "compiled_launch_prompt", "rendered_prompt"),
        entry.fetch(:line)
      )
      replace_rendered_prompt(document, prompt)
      write_dispatch(document)

      _stdout, stderr, status = validate
      refute status.success?, label
      assert_includes stderr, entry.fetch(:exact_once_error), label
    end
  end

  def test_v8_rejects_each_projected_block_when_an_applicable_line_is_duplicated
    prompt_projection_cases(promoted_dispatch).each do |label, entry|
      document = promoted_dispatch
      prompt = duplicate_prompt_line(
        document.dig("launch", "compiled_launch_prompt", "rendered_prompt"),
        entry.fetch(:line)
      )
      replace_rendered_prompt(document, prompt)
      write_dispatch(document)

      _stdout, stderr, status = validate
      refute status.success?, label
      assert_includes stderr, entry.fetch(:exact_once_error), label
    end
  end

  def test_v8_rejects_each_projected_block_when_an_exact_value_is_changed
    prompt_projection_cases(promoted_dispatch).each do |label, entry|
      document = promoted_dispatch
      wrong_line = tamper_projection_line(entry.fetch(:line))
      prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt").sub(entry.fetch(:line), wrong_line)
      replace_rendered_prompt(document, prompt)
      write_dispatch(document)

      _stdout, stderr, status = validate
      refute status.success?, label
      assert_includes stderr, "unexpected or non-exact", label
      assert_includes stderr, entry.fetch(:exact_once_error), label
    end
  end

  def test_v8_rejects_tampering_of_each_machine_projection_field
    baseline = promoted_dispatch
    requirement = baseline.dig("launch", "requirement_manifest").find { |row| row["category"] == "founder" }
    line = dispatch_fixture_requirement_projection_line(requirement)
    DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_FIELDS.each do |field|
      document = promoted_dispatch
      payload = JSON.parse(line.delete_prefix(DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX))
      payload[field] = if field == "director_semantic_review_required"
                         !payload.fetch(field)
                       else
                         "#{payload.fetch(field)}#wrong-value"
                       end
      wrong_line = "#{DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX}#{JSON.generate(payload)}"
      prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt").sub(line, wrong_line)
      replace_rendered_prompt(document, prompt)
      write_dispatch(document)

      _stdout, stderr, status = validate
      refute status.success?, field
      assert_includes stderr, "unexpected or non-exact requirement projection line", field
      assert_includes stderr, "exact-project requirement #{requirement.fetch('requirement_id').inspect} exactly once", field
    end
  end

  def test_v8_rejects_missing_or_extra_machine_projection_fields
    baseline = promoted_dispatch
    requirement = baseline.dig("launch", "requirement_manifest").find { |row| row["category"] == "founder" }
    line = dispatch_fixture_requirement_projection_line(requirement)
    payload = JSON.parse(line.delete_prefix(DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX))

    {
      "missing field" => payload.reject { |key, _value| key == "evidence_type" },
      "extra field" => payload.merge("category" => requirement.fetch("category"))
    }.each do |label, wrong_payload|
      document = promoted_dispatch
      wrong_line = "#{DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX}#{JSON.generate(wrong_payload)}"
      prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt").sub(line, wrong_line)
      replace_rendered_prompt(document, prompt)
      write_dispatch(document)

      _stdout, stderr, status = validate
      refute status.success?, label
      assert_includes stderr, "unexpected or non-exact requirement projection line", label
      assert_includes stderr, "exact-project requirement #{requirement.fetch('requirement_id').inspect} exactly once", label
    end
  end

  def test_v8_rejects_each_projected_block_when_a_line_is_moved_to_the_wrong_block
    prompt_projection_cases(promoted_dispatch).each do |label, entry|
      document = promoted_dispatch
      wrong_heading = entry.fetch(:heading) == "## 07 Required Work" ? "## 03 Current Creative Job" : "## 07 Required Work"
      prompt = move_prompt_line(
        document.dig("launch", "compiled_launch_prompt", "rendered_prompt"),
        entry.fetch(:line),
        wrong_heading
      )
      replace_rendered_prompt(document, prompt)
      write_dispatch(document)

      _stdout, stderr, status = validate
      refute status.success?, label
      assert_includes stderr, entry.fetch(:wrong_block_error), label
    end
  end

  def test_v8_rejects_whole_owning_skill_prose_duplicated_into_the_launch_prompt
    document = promoted_dispatch
    skill_path = ROOT.join(document.dig("launch", "required_skills", 0, "path"))
    prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt")
    whitespace_reformatted_skill = skill_path.read.lines.map { |line| "  #{line}" }.join.strip
    prompt = prompt.sub("\n\n## 08 Output Contract", "\n#{whitespace_reformatted_skill}\n\n## 08 Output Contract")
    replace_rendered_prompt(document, prompt)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "must not duplicate the whole owning skill prose"
  end

  def test_v3_rejects_task_role_that_does_not_match_the_selected_profile
    document = promoted_dispatch
    document.dig("launch", "task")["role"] = "department_worker"
    document.dig("runtime_return", "runtime_owner")["role"] = "department_worker"
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "task role must match selected provider-neutral profile role"
  end

  def test_v3_rejects_a_missing_registered_checkpoint_read
    document = promoted_dispatch
    document.dig("launch", "required_skills", 0, "linked_reads").pop
    document.dig("runtime_return")["skill_revisions"] = dispatch_fixture_runtime_skill_revisions(
      document.dig("launch", "required_skills")
    )
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "launch linked reads must exact-copy the selected checkpoint read bindings"
  end

  def test_v3_accepts_the_same_provider_neutral_command_for_grok_transport
    document = promoted_dispatch
    document.fetch("lineage")["provider"] = "grok"
    document.dig("runtime_return", "runtime_goal")["provider"] = "grok"
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_v3_wake_must_exact_copy_returned_output_pointers
    document = promoted_dispatch
    document.dig("runtime_return", "wake_event", "output_pointers", 0)["role"] = "relabelled wake output"
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "wake event output pointers must exact-copy runtime outputs"
  end

  def test_v3_wake_forbids_raw_commentary
    document = promoted_dispatch
    document.dig("runtime_return", "wake_event")["raw_commentary_included"] = true
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "schema validation failed"
  end

  def test_later_attempt_requires_a_previous_attempt_pointer
    document = promoted_dispatch
    document.fetch("lineage")["attempt_number"] = 2
    refresh_input_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "later lineage attempt must name previous_attempt_id"
  end

  def test_later_attempt_requires_a_resolvable_canonical_predecessor
    document = promoted_dispatch
    document.fetch("lineage")["attempt_number"] = 2
    document.fetch("lineage")["previous_attempt_id"] = "MISSING_PREDECESSOR"
    refresh_input_digest(document)
    write_dispatch(document)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "later lineage attempt must resolve its canonical predecessor"
  end

  def test_same_session_successor_accepts_changed_bytes_after_closed_hold
    predecessor = hold_dispatch(promoted_dispatch, retry_route: "same_session_new_attempt")
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: revised\n")
    write_dispatch(current)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_unchanged_successor_reuses_predecessor_review_instead_of_reopening_review
    predecessor = hold_dispatch(promoted_dispatch, retry_route: "same_session_new_attempt")
    current = successor_after(predecessor)
    write_dispatch(current)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "must contain changed bytes for its invalidated repair target"
  end

  def test_upstream_owner_hold_forbids_a_direct_child_successor
    predecessor = hold_dispatch(promoted_dispatch, retry_route: "upstream_owner")
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: revised-upstream\n")
    write_dispatch(current)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "upstream_owner predecessor disposition forbids a direct child successor"
  end

  def test_submission_two_may_route_one_final_targeted_retry
    problem = "The bounded decision still lacks the required visible consequence."
    predecessor = hold_dispatch(
      promoted_dispatch,
      retry_route: "same_session_new_attempt",
      problem: problem
    )
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: revised-but-same-defect\n")
    current = hold_dispatch(current, retry_route: "same_session_new_attempt", problem: problem)
    write_dispatch(current)

    stdout, stderr, status = validate("--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal 2, JSON.parse(stdout).fetch("review_submission_number")
  end

  def test_submission_three_may_pass_after_a_second_targeted_repair
    first = hold_dispatch(promoted_dispatch, retry_route: "same_session_new_attempt")
    second = successor_after(first, output_bytes: "schema_version: '1.5'\nstatus: revision-two\n")
    second = hold_dispatch(second, retry_route: "same_session_new_attempt")
    third = successor_after(second, output_bytes: "schema_version: '1.5'\nstatus: revision-three-passed\n")
    write_dispatch(third)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal 3, result.fetch("review_submission_number")
    assert_equal 3, result.fetch("review_submission_maximum")
  end

  def test_submission_three_cannot_open_a_fourth_child_retry
    first = hold_dispatch(promoted_dispatch, retry_route: "same_session_new_attempt")
    second = successor_after(first, output_bytes: "schema_version: '1.5'\nstatus: revision-two\n")
    second = hold_dispatch(second, retry_route: "same_session_new_attempt")
    third = successor_after(second, output_bytes: "schema_version: '1.5'\nstatus: revision-three-held\n")
    third = hold_dispatch(third, retry_route: "same_session_new_attempt")
    write_dispatch(third)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "review submission 3 is the final allowed submission"
  end

  def test_targeted_correction_repairs_one_of_ten_outputs_and_freezes_the_other_nine
    predecessor = promoted_dispatch
    add_bounded_outputs(predecessor, total: 10)
    predecessor = hold_dispatch(predecessor, retry_route: "same_session_new_attempt")
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: only-failed-cut-repaired\n")
    write_dispatch(current)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal [relative(@output)], current.dig("launch", "task", "exact_scope", "artifact_paths")
    assert_equal 1, current.dig("review_submission", "repair_targets").length
    assert_equal 9, current.dig("review_submission", "frozen_outputs").length
  end

  def test_held_correction_cannot_reset_its_review_counter
    predecessor = hold_dispatch(promoted_dispatch, retry_route: "same_session_new_attempt")
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: counter-reset-attempt\n")
    current["review_submission"] = {
      "review_cycle_id" => current.fetch("dispatch_id"),
      "submission_number" => 1,
      "maximum_submissions" => 3,
      "submission_kind" => "initial",
      "root_attempt_id" => current.fetch("dispatch_id"),
      "previous_submission_attempt_id" => nil,
      "correction_source" => nil,
      "repair_targets" => [],
      "repair_acceptance_criteria" => [],
      "frozen_outputs" => []
    }
    refresh_input_digest(current)
    write_dispatch(current)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "cannot reset to an initial submission"
  end

  def test_targeted_correction_cannot_reassign_the_section_worker_role
    predecessor = hold_dispatch(promoted_dispatch, retry_route: "same_session_new_attempt")
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: reassigned-worker\n")
    current.dig("launch", "task")["role"] = "edit_shard_worker"
    refresh_input_digest(current)
    write_dispatch(current)

    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "same section-worker line"
  end

  def test_new_session_correction_preserves_review_counter_while_starting_lineage_attempt_one
    predecessor = hold_dispatch(promoted_dispatch, retry_route: "new_session_new_lineage")
    current = successor_after(predecessor, output_bytes: "schema_version: '1.5'\nstatus: new-session-correction\n")
    current.fetch("lineage")["lineage_id"] = "LINEAGE_NEW_#{SecureRandom.hex(3).upcase}"
    current.fetch("lineage")["session_id"] = "SESSION_NEW_#{SecureRandom.hex(3).upcase}"
    current.fetch("lineage")["attempt_number"] = 1
    current.fetch("lineage")["previous_attempt_id"] = nil
    refresh_input_digest(current)
    write_dispatch(current)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal 2, result.fetch("review_submission_number")
    assert_equal 1, current.dig("lineage", "attempt_number")
  end

  def test_multiple_outputs_require_a_hash_bound_aggregate_manifest
    second_output = @run.join("research", "second-output.yaml")
    second_output.write("second: output\n")
    document = promoted_dispatch
    second = hashed_artifact(second_output, "second bounded result")
    document.dig("launch", "task", "exact_scope", "artifact_paths") << relative(second_output)
    document.dig("launch", "bounded_output", "expected_paths") << relative(second_output)
    document.dig("launch", "bounded_output")["maximum_artifact_count"] = 2
    document.dig("runtime_return", "outputs") << second
    document.dig("runtime_return", "output_inventory")["artifact_count"] = 2
    document.dig("director_review", "reviewed_outputs") << deep_copy(second)
    document.dig("promotion", "approved_working_outputs") << deep_copy(second)
    document.dig("promotion", "canonical_artifacts") << deep_copy(second)
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "multiple returned outputs require aggregate_manifest inventory mode"
  end

  def test_nonaccept_review_requires_the_fixed_correction_unit
    document = promoted_dispatch
    document.fetch("director_review")["disposition"] = "hold"
    document.fetch("director_review").fetch("rubric_results").first["result"] = "hold"
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "schema validation failed"
  end

  def test_stale_output_bytes_fail_runtime_review_and_promotion_bindings
    write_dispatch(promoted_dispatch)
    @output.write("schema_version: '1.5'\nstatus: silently_changed\n")
    _stdout, stderr, status = validate("--require-promoted")
    refute status.success?
    assert_includes stderr, "runtime_return.outputs[0] SHA-256 is stale"
    assert_includes stderr, "director_review.reviewed_outputs[0] SHA-256 is stale"
    assert_includes stderr, "promotion.canonical_artifacts[0] SHA-256 is stale"
  end

  def test_runtime_cannot_replace_or_skip_launch_skill_revision
    document = promoted_dispatch
    document.fetch("runtime_return").fetch("skill_revisions").first["revision"] = "different-revision"
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "runtime skill revisions must exact-copy launch skill/read revisions and record EOF"
  end

  def test_lifecycle_cannot_skip_returned_before_review
    document = promoted_dispatch
    document.fetch("lifecycle")["events"].delete_at(2)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "lifecycle events must be the exact prefix"
  end

  def test_reviewed_hold_is_valid_evidence_but_not_an_active_promotion
    document = promoted_dispatch
    document.fetch("lifecycle")["current_state"] = "hold"
    document.fetch("lifecycle").fetch("events").last["state"] = "hold"
    document.fetch("director_review")["disposition"] = "hold"
    document.fetch("director_review").fetch("rubric_results").first["result"] = "hold"
    document.fetch("director_review")["correction"] = {
      "problem" => "The returned decision needs a bounded revision before promotion.",
      "evidence" => [
        {
          "kind" => "returned_output",
          "locator" => relative(@output),
          "source_sha256" => sha(@output),
          "observation" => "The exact returned bytes contain the unresolved review point."
        }
      ],
      "screen_consequence" => "Promoting now would carry the unresolved decision into the next screen stage.",
      "correction_action" => "Revise only the returned decision in the same physical task.",
      "remaining_risk" => "The next attempt still requires a fresh director review.",
      "affected_owner" => "fixture-worker",
      "invalidated_outputs" => [deep_copy(document.dig("runtime_return", "outputs", 0))],
      "complete_problem_set" => true,
      "acceptance_criteria" => ["The revised output resolves the named defect without changing unaffected truth."],
      "retry_route" => "same_session_new_attempt"
    }
    document.fetch("promotion")["decision"] = "hold"
    document.fetch("promotion")["mode"] = "held_without_promotion"
    document.fetch("promotion")["approved_at"] = nil
    document.fetch("promotion")["approved_working_outputs"] = []
    document.fetch("promotion")["coordinator"] = nil
    document.fetch("promotion")["copy_completed_at"] = nil
    document.fetch("promotion")["canonical_artifacts"] = []
    document.fetch("promotion")["reason"] = "Director held promotion for revision."
    refresh_promotion_baseline(document)
    write_dispatch(document)

    stdout, stderr, status = validate("--json")
    assert status.success?, [stdout, stderr].join("\n")

    _required_stdout, required_stderr, required_status = validate("--require-promoted")
    refute required_status.success?
    assert_includes required_stderr, "must be promoted for this active gate"
  end

  def test_cf_shaped_dispatch_uses_the_shared_schema_and_validator
    with_cf_fixture do
      write_dispatch(promoted_dispatch(stage_id: "cf20", owner_role: "cf-direction-owner"))
      stdout, stderr, status = validate("--require-promoted", "--json")
      assert status.success?, [stdout, stderr].join("\n")
      result = JSON.parse(stdout)
      assert_equal "pass", result["status"]
      assert_equal run_relative, result["run"]
      assert_equal "cf20", result["stage_id"]
      assert_match(%r{\Acf/runs/CF_.+/work/department-dispatches/}, result["dispatch"])
    end
  end

  def test_cf_dispatch_still_requires_the_exact_run_owned_stable_path
    with_cf_fixture do
      document = promoted_dispatch(stage_id: "cf20", owner_role: "cf-direction-owner")
      wrong_path = @dispatch.dirname.join("WRONG_TASK_ID.yaml")
      wrong_path.write(YAML.dump(document))
      @dispatch = wrong_path
      _stdout, stderr, status = validate
      refute status.success?
      assert_includes stderr, "department dispatch must live at #{run_relative}/work/department-dispatches/#{@dispatch_id}.yaml"
    end
  end

  def test_v19_output_kinds_accept_opaque_artifact_bytes_only_when_role_owner_and_sources_are_exact
    V19_OUTPUT_CASES.each do |output_kind, rule|
      document = v19_dispatch(
        output_kind: output_kind,
        owner_role: rule.fetch(:role),
        binding_kinds: rule.fetch(:bindings)
      )
      write_dispatch(document)
      stdout, stderr, status = validate("--require-promoted", "--json")
      assert status.success?, "#{output_kind} failed\n#{stdout}\n#{stderr}"
      assert_equal "pass", JSON.parse(stdout)["status"]
    end
  end

  def test_v8_founder_briefing_projection_uses_working_output_overall_review_and_immutable_history
    @output = @run.join("work", "department-dispatches", "outputs", "#{@dispatch_id}.json")
    @output.dirname.mkpath
    source = @run.join("research", "v18-bindings", "founder_briefing_source_set.yaml")
    source.dirname.mkpath
    source.write("transport_fixture: founder_briefing_source_set\n")
    source_row = {"path" => relative(source), "sha256" => sha(source)}
    source_set_sha256 = Digest::SHA256.hexdigest("#{source_row['path']}\t#{source_row['sha256']}")
    briefing = {
      "schema_version" => "front-planning-workbench.founder-briefing.v1",
      "run_root" => run_relative,
      "source_set_sha256" => source_set_sha256,
      "projection_status" => "ready",
      "current_stage" => {"stage_id" => "front_planning_integration", "label" => "Front Planning review", "status" => "review", "progress_percent" => 50, "source_milestone_ids" => ["MS1"]},
      "quality_watch" => [],
      "decisions_needed" => [],
      "holds" => [],
      "next_owner" => nil,
      "artifact_links" => [{"label" => "Reviewed source", "path" => source_row["path"], "sha256" => source_row["sha256"], "source_milestone_ids" => ["MS1"]}],
      "reviewed_milestones" => [{
        "milestone_id" => "MS1", "stage_id" => "front_planning_integration", "label" => "Reviewed source",
        "review_owner" => "overall_director", "review_state" => "reviewed",
        "source_path" => source_row["path"], "source_sha256" => source_row["sha256"],
        "review_receipt_schema_version" => "front-planning-workbench.founder-briefing-milestone-review.v1",
        "review_receipt_path" => source_row["path"], "review_receipt_sha256" => source_row["sha256"]
      }],
      "source_set" => {"digest_algorithm" => "sorted_path_sha256_pairs_v1", "members" => [source_row]},
      "authority_boundary" => {
        "projection_class" => "run_local_noncanonical", "canonical" => false, "creative_truth" => false,
        "promotion" => false, "dispatch" => false, "generation" => false, "external_action" => false,
        "raw_worker_transcript" => false
      }
    }
    @output.write(JSON.pretty_generate(briefing) + "\n")

    document = v19_dispatch(
      output_kind: "founder_briefing_projection",
      owner_role: "department_worker",
      binding_kinds: %w[founder_briefing_source_set],
      stage_id: "founder_briefing_projection",
      profile_id: "founder_briefing",
      checkpoint_id: "briefing_refresh"
    )
    launch = document.fetch("launch")
    launch.dig("task", "exact_scope")["mode"] = "artifact"
    launch.fetch("authority")["director_owner"] = "fixture-overall"
    launch.fetch("authority")["promotion_owner"] = "fixture-overall"
    launch.fetch("recipient").merge!("owner" => "fixture-overall", "role" => "overall_director", "return_route" => "director_output_review")
    document.dig("runtime_return", "wake_event")["recipient_role"] = "overall_director"
    document.fetch("director_review")["director"] = {"owner" => "fixture-overall", "role" => "overall_director"}
    document.dig("review_control", "review_lease")["director_owner"] = "fixture-overall"
    document.dig("review_control", "promotion_lease")["overall_owner"] = "fixture-overall"
    document.dig("lifecycle", "events", 0)["actor"] = "fixture-overall"
    document.dig("lifecycle", "events", 3)["actor"] = "fixture-overall"
    document.fetch("promotion")["promoter"] = {"owner" => "fixture-overall", "role" => "overall_director"}
    sync_v18_promotion(document)
    history = @run.join("work", "founder-briefing", "history", "#{source_set_sha256}.json")
    history.dirname.mkpath
    FileUtils.cp(@output, history)
    document.dig("promotion", "canonical_artifacts", 0).merge!(
      "path" => relative(history),
      "sha256" => sha(history),
      "role" => "reviewed Founder briefing immutable history projection"
    )
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)

    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_v8_harness_maintenance_uses_checkpoint_as_transport_stage_and_skill_less_reads
    document = dispatch_fixture_promoted_document(
      run_path: @run,
      dispatch_id: @dispatch_id,
      stage_id: "skill_profile_routing",
      artifact_path: @output,
      owner_role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      assigned_owner: "fixture-maintainer",
      director_owner: "fixture-overall",
      promotion_owner: "fixture-overall",
      recipient_role: "overall_director",
      output_role: "maintenance inventory"
    )
    launch = document.fetch("launch")
    assert_empty launch.fetch("required_skills")
    refute_empty launch.fetch("required_reads")
    document.fetch("routing_identity")["logical_role"] = "mechanical_coordinator"
    document.fetch("routing_identity")["worker_specialty"] = "harness_maintenance"
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)

    stdout, stderr, status = validate("--require-promoted", "--json")
    payload = JSON.parse(stdout)
    errors = Array(payload["errors"])
    structural = errors.reject { |row| row.to_s.include?("SHA-256 is stale") }
    assert_empty structural, [stdout, stderr].join("\n")
    refute_includes errors.join("\n"), "does not own skill_profile_routing"
  end

  def test_v8_harness_maintenance_rejects_a_creative_stage_id
    document = dispatch_fixture_promoted_document(
      run_path: @run,
      dispatch_id: @dispatch_id,
      stage_id: "front_planning_integration",
      artifact_path: @output,
      owner_role: "mechanical_coordinator",
      profile_id: "harness_maintenance",
      checkpoint_id: "skill_profile_routing",
      assigned_owner: "fixture-maintainer",
      director_owner: "fixture-overall",
      promotion_owner: "fixture-overall",
      recipient_role: "overall_director",
      output_role: "maintenance inventory"
    )
    document.fetch("routing_identity")["logical_role"] = "mechanical_coordinator"
    document.fetch("routing_identity")["worker_specialty"] = "harness_maintenance"
    refresh_input_digest(document)
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "compiled launch stage is outside selected profile: harness_maintenance does not own front_planning_integration"
  end

  def test_v19_output_kind_role_matrix_is_hold_only
    rule = V19_OUTPUT_CASES.fetch("decision_set")
    document = v19_dispatch(
      output_kind: "decision_set",
      owner_role: "overall_director",
      binding_kinds: rule.fetch(:bindings)
    )
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "output_kind=decision_set requires task role song_room or department_worker or member_visual_identity_owner or section_owner"
  end

  def test_v19_output_kind_cannot_drop_its_required_binding_declaration
    rule = V19_OUTPUT_CASES.fetch("section_reference_set")
    document = v19_dispatch(
      output_kind: "section_reference_set",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    document.dig("launch", "bounded_output")["required_binding_kinds"] = ["section_dispatch_map"]
    refresh_input_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "output_kind=section_reference_set requires exact required_binding_kinds section_dispatch_map, reference_working_index, selected_source_evidence"
  end

  def test_v19_output_binding_must_exact_copy_a_launch_source_path_and_hash
    rule = V19_OUTPUT_CASES.fetch("reference_working_index_delta")
    document = v19_dispatch(
      output_kind: "reference_working_index_delta",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    binding = document.dig("runtime_return", "outputs", 0, "bindings", 0)
    binding["sha256"] = "0" * 64
    sync_v18_promotion(document)
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "path and SHA-256 must exact-copy launch.sources"
  end

  def test_v19_output_logical_owner_must_exact_copy_launch_ownership
    rule = V19_OUTPUT_CASES.fetch("director_development_report")
    document = v19_dispatch(
      output_kind: "director_development_report",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    document.dig("runtime_return", "outputs", 0, "logical_owner")["owner"] = "different-owner"
    sync_v18_promotion(document)
    refresh_result_digest(document)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "logical_owner must exact-copy launch bounded_output.logical_owner"
  end

  def test_v19_director_review_cannot_relabel_returned_binding_metadata
    rule = V19_OUTPUT_CASES.fetch("decision_set")
    document = v19_dispatch(
      output_kind: "decision_set",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    document.dig("director_review", "reviewed_outputs", 0, "bindings", 0)["binding_kind"] = "other_upstream"
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "director review must exact-copy every returned v18 output and its ownership/bindings"
  end

  def test_v19_director_review_requires_the_exact_output_kind_rubric
    rule = V19_OUTPUT_CASES.fetch("section_dispatch_map")
    document = v19_dispatch(
      output_kind: "section_dispatch_map",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    document.fetch("director_review").fetch("rubric_results").pop
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "output_kind=section_dispatch_map requires exact rubric criteria"
    assert_includes stderr, "independent_visual_job, connected_boundaries"
  end

  def test_v19_promotion_requires_the_declared_overall_promoter
    rule = V19_OUTPUT_CASES.fetch("director_development_report")
    document = v19_dispatch(
      output_kind: "director_development_report",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    document.dig("promotion", "promoter")["owner"] = "undeclared-promoter"
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "promotion promoter must equal launch authority promotion_owner"
  end

  def test_v19_promoted_state_requires_actual_byte_identical_coordinator_copy
    rule = V19_OUTPUT_CASES.fetch("decision_set")
    document = v19_dispatch(
      output_kind: "decision_set",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    canonical = document.dig("promotion", "canonical_artifacts", 0)
    canonical_path = ROOT.join(canonical.fetch("path"))
    canonical_path.write("different canonical bytes\n")
    canonical["sha256"] = sha(canonical_path)
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "must preserve exact approved output bytes"
  end

  def test_v19_reviewed_state_is_valid_before_coordinator_copy_but_is_not_promoted
    rule = V19_OUTPUT_CASES.fetch("reference_working_index_delta")
    document = v19_dispatch(
      output_kind: "reference_working_index_delta",
      owner_role: rule.fetch(:role),
      binding_kinds: rule.fetch(:bindings)
    )
    document.dig("lifecycle")["current_state"] = "reviewed"
    document.dig("lifecycle", "events").pop
    document.dig("review_control")["queue_state"] = "disposition_recorded"
    document.dig("review_control")["promotion_lease"] = nil
    document["promotion"] = nil
    write_dispatch(document)
    stdout, stderr, status = validate("--json")
    assert status.success?, [stdout, stderr].join("\n")

    _required_stdout, required_stderr, required_status = validate("--require-promoted")
    refute required_status.success?
    assert_includes required_stderr, "must be promoted for this active gate"
  end

  def test_pre_02a_dispatch_reuses_and_validates_the_existing_section_slice_contract
    build_pre_02a_section_output
    document = v19_dispatch(
      output_kind: "pre_02a_section_working_shard",
      owner_role: "department_worker",
      binding_kinds: %w[section_dispatch_map section_reference_set section_slice_schema],
      owner: "codex",
      stage_id: "mv_performance_direction",
      section_ids: %w[S00]
    )
    write_dispatch(document)
    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout)["status"]
  end

  def test_pre_02a_dispatch_requires_exact_section_coverage
    build_pre_02a_section_output
    document = v19_dispatch(
      output_kind: "pre_02a_section_working_shard",
      owner_role: "department_worker",
      binding_kinds: %w[section_dispatch_map section_reference_set section_slice_schema],
      owner: "codex",
      stage_id: "mv_performance_direction",
      section_ids: %w[S01]
    )
    write_dispatch(document)
    _stdout, stderr, status = validate
    refute status.success?
    assert_includes stderr, "visual_section_id is outside dispatch exact_scope.section_ids"
    assert_includes stderr, "outputs must exact-cover dispatch exact_scope.section_ids"
  end

  def test_unused_helpers_still_pass_without_receipts
    document = promoted_dispatch
    write_dispatch(document)
    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
  end

  def test_used_helpers_without_receipts_fail
    document = promoted_dispatch
    document["internal_delegation_summary"]["provider_native_helpers_used"] = true
    document["internal_delegation_summary"]["helper_count"] = 1
    write_dispatch(document)
    _stdout, stderr, status = validate("--require-promoted")
    refute status.success?
    assert_includes stderr, "helper_consumption_receipts"
  end

  def test_used_helpers_with_matching_consume_receipt_pass
    document = promoted_dispatch
    attach_helper_receipts(document, dispositions: %w[consume])
    write_dispatch(document)
    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
  end

  def test_hold_receipt_without_sidecar_fails
    document = promoted_dispatch
    attach_helper_receipts(document, dispositions: %w[hold])
    write_dispatch(document)
    _stdout, stderr, status = validate("--require-promoted")
    refute status.success?
    assert_includes stderr, "run_followup sidecar"
  end

  def test_hold_receipt_with_sidecar_passes
    document = promoted_dispatch
    attach_helper_receipts(document, dispositions: %w[hold])
    write_run_followup_sidecar(document.fetch("run"))
    write_dispatch(document)
    stdout, stderr, status = validate("--require-promoted", "--json")
    assert status.success?, [stdout, stderr].join("\n")
  end

  private

  def run_relative
    relative(@run)
  end

  def relative(path)
    path.relative_path_from(ROOT).to_s
  end

  def with_cf_fixture
    original = [@run, @source, @output, @dispatch_id, @dispatch, @skill, @linked_read]
    cf_run = ROOT.join("cf", "runs", "CF_DISPATCH_TEST_#{SecureRandom.hex(4).upcase}")
    @run = cf_run
    @source = @run.join("research", "CF00-source.yaml")
    @output = @run.join("research", "CF20-direction.yaml")
    @dispatch_id = "CF20_#{SecureRandom.hex(3).upcase}"
    @dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    @skill = ROOT.join("cf", "skills", "idol-cf-code", "SKILL.md")
    @linked_read = ROOT.join("cf", "AGENTS.md")
    @source.dirname.mkpath
    @dispatch.dirname.mkpath
    @source.write("advertised_subject: fixture\n")
    @output.write("schema_version: idol-cf20-direction.v1\nstatus: ready\n")
    yield
  ensure
    FileUtils.remove_entry(cf_run) if cf_run&.directory?
    @run, @source, @output, @dispatch_id, @dispatch, @skill, @linked_read = original
  end

  def sha(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[original_key])
      end
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def structured_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def profile_checkpoint_for(owner_role, stage_id)
    return ["song_room_00a", "selected_audio_analysis"] if run_relative.start_with?("cf/")

    case owner_role
    when "song_room"
      ["song_room_00a", "selected_audio_analysis"]
    when "creative_development_director"
      ["creative_development_director", "cdd_startup"]
    when "overall_director"
      ["overall_director", "director_startup"]
    when "department_worker"
      if stage_id == "mv_performance_direction"
        ["pre_02a_development_block_fp", "section_01_core_direction"]
      else
        ["reference_research_generalist", "reference_story_sequence_role"]
      end
    else
      ["song_room_00a", "selected_audio_analysis"]
    end
  end

  def compiled_launch_prompt(profile_id:, checkpoint_id:)
    dispatch_fixture_compiled_launch_prompt(
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      source_ids: ["selected_song"],
      model_or_role_profile: "fixture-provider-neutral-role"
    )
  end

  def prompt_projection_cases(document)
    requirements = document.dig("launch", "requirement_manifest")
    founder = requirements.find { |row| row["category"] == "founder" }
    other = requirements.find { |row| row["category"] == "skill" }
    quality = requirements.find { |row| row["category"] == "quality" }
    anti_flat = document.dig("launch", "bounded_output", "anti_flat_evidence_requirements", 0)
    {
      "Block03 Founder requirement" => {
        line: dispatch_fixture_requirement_projection_line(founder),
        heading: "## 03 Current Creative Job",
        exact_once_error: "exact-project requirement #{founder.fetch('requirement_id').inspect} exactly once",
        wrong_block_error: "requirement #{founder.fetch('requirement_id').inspect} must be in block current_creative_job"
      },
      "Block07 non-Founder/non-quality requirement" => {
        line: dispatch_fixture_requirement_projection_line(other),
        heading: "## 07 Required Work",
        exact_once_error: "exact-project requirement #{other.fetch('requirement_id').inspect} exactly once",
        wrong_block_error: "requirement #{other.fetch('requirement_id').inspect} must be in block required_work"
      },
      "Block09 quality requirement" => {
        line: dispatch_fixture_requirement_projection_line(quality),
        heading: "## 09 Quality Proof",
        exact_once_error: "exact-project requirement #{quality.fetch('requirement_id').inspect} exactly once",
        wrong_block_error: "requirement #{quality.fetch('requirement_id').inspect} must be in block quality_proof"
      },
      "Block09 Anti-Flat evidence" => {
        line: dispatch_fixture_anti_flat_projection_line(anti_flat),
        heading: "## 09 Quality Proof",
        exact_once_error: "exact-project Anti-Flat evidence #{anti_flat.inspect} exactly once",
        wrong_block_error: "Anti-Flat evidence must be in block quality_proof: #{anti_flat.inspect}"
      }
    }
  end

  def prompt_block(prompt, heading)
    headings = DepartmentDispatchProfileFixture::LAUNCH_BLOCK_HEADINGS
    index = headings.index(heading)
    start_marker = "#{heading}\n"
    body = prompt.split(start_marker, 2).fetch(1)
    return body if index == headings.length - 1

    body.split("\n\n#{headings.fetch(index + 1)}", 2).fetch(0)
  end

  def remove_prompt_line(prompt, line)
    lines = prompt.split("\n", -1)
    index = lines.index(line)
    raise "missing prompt projection line: #{line}" unless index

    lines.delete_at(index)
    lines.join("\n")
  end

  def duplicate_prompt_line(prompt, line)
    lines = prompt.split("\n", -1)
    index = lines.index(line)
    raise "missing prompt projection line: #{line}" unless index

    lines.insert(index + 1, line)
    lines.join("\n")
  end

  def move_prompt_line(prompt, line, target_heading)
    lines = remove_prompt_line(prompt, line).split("\n", -1)
    heading_index = lines.index(target_heading)
    raise "missing target prompt heading: #{target_heading}" unless heading_index

    lines.insert(heading_index + 1, line)
    lines.join("\n")
  end

  def tamper_projection_line(line)
    if line.start_with?(DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX)
      payload = JSON.parse(line.delete_prefix(DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX))
      payload["source_locator"] = "#{payload.fetch('source_locator')}#wrong-value"
      "#{DepartmentDispatchProfileFixture::REQUIREMENT_PROJECTION_PREFIX}#{JSON.generate(payload)}"
    else
      payload = JSON.parse(line.delete_prefix(DepartmentDispatchProfileFixture::ANTI_FLAT_PROJECTION_PREFIX))
      payload["anti_flat_evidence_requirement"] = "#{payload.fetch('anti_flat_evidence_requirement')} wrong-value"
      "#{DepartmentDispatchProfileFixture::ANTI_FLAT_PROJECTION_PREFIX}#{JSON.generate(payload)}"
    end
  end

  def replace_rendered_prompt(document, prompt)
    compiled = document.dig("launch", "compiled_launch_prompt")
    compiled["rendered_prompt"] = prompt
    compiled["rendered_prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    refresh_compiled_launch_digest(document)
    refresh_input_digest(document)
  end

  def hashed_artifact(path, role)
    {"path" => relative(path), "sha256" => sha(path), "role" => role}
  end

  def attach_helper_receipts(document, dispositions:)
    document["internal_delegation_summary"]["provider_native_helpers_used"] = true
    document["internal_delegation_summary"]["helper_count"] = dispositions.length
    receipts = dispositions.each_with_index.map do |disposition, index|
      write_helper_receipt(
        dispatch_id: document.fetch("dispatch_id"),
        helper_id: "helper_fixture_#{index + 1}",
        disposition: disposition,
        receipt_id: "HCR_FIXTURE_#{format('%02d', index + 1)}"
      )
    end
    document["runtime_return"]["helper_consumption_receipts"] = receipts
    refresh_input_digest(document)
    refresh_result_digest(document)
  end

  def write_helper_receipt(dispatch_id:, helper_id:, disposition:, receipt_id:)
    path = @run.join("work", "helper-receipts", "#{receipt_id}.yaml")
    path.dirname.mkpath
    path.write(
      YAML.dump(
        "schema_version" => "idol-helper-consumption-receipt.v1",
        "receipt_id" => receipt_id,
        "parent_dispatch_id" => dispatch_id,
        "helper_id" => helper_id,
        "inspected_inputs" => ["work/fixture/candidate-a.yaml"],
        "finding" => "Fixture helper return for #{helper_id}.",
        "director_disposition" => disposition
      )
    )
    hashed_artifact(path, "helper_consumption_receipt")
  end

  def write_run_followup_sidecar(run_value)
    dest = @run.join("review", "harness-improvement-review.yaml")
    dest.dirname.mkpath
    document = YAML.safe_load(ROOT.join("scripts", "tests", "fixtures", "run-followup-sidecar-valid.yaml").read)
    document["run"] = run_value
    dest.write(YAML.dump(document))
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def binding_source_path(binding_kind)
    return ROOT.join("schemas", "harness-section-slice.schema.json") if binding_kind == "section_slice_schema"

    path = @run.join("research", "v18-bindings", "#{binding_kind}.yaml")
    path.dirname.mkpath
    path.write("transport_fixture: #{binding_kind}\n")
    path
  end

  def v19_dispatch(output_kind:, owner_role:, binding_kinds:, owner: "fixture-worker", stage_id: "front_planning_integration", section_ids: [], profile_id: nil, checkpoint_id: nil)
    profile_id, checkpoint_id = profile_checkpoint_for(owner_role, stage_id) if profile_id.nil? || checkpoint_id.nil?
    document = promoted_dispatch(
      stage_id: stage_id,
      owner_role: owner_role,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id
    )
    launch = document.fetch("launch")
    launch.dig("authority")["assigned_owner"] = owner
    launch.dig("authority")["promotion_owner"] = "fixture-promoter"
    document.dig("review_control", "promotion_lease")["overall_owner"] = "fixture-promoter"
    launch.dig("authority")["canonical_write"] = "forbidden"
    launch.dig("task", "exact_scope")["mode"] = section_ids.length == 1 ? "section" : "section_set" unless section_ids.empty?
    launch.dig("task", "exact_scope")["section_ids"] = section_ids
    launch.dig("bounded_output")["output_kind"] = output_kind
    launch.dig("bounded_output")["logical_owner"] = {"owner" => owner, "role" => owner_role}
    launch.dig("bounded_output")["required_binding_kinds"] = binding_kinds
    launch.dig("bounded_output")["maximum_artifact_count"] = section_ids.length unless section_ids.empty?

    bindings = binding_kinds.map do |binding_kind|
      source_id = "v18_#{binding_kind}"
      path = binding_source_path(binding_kind)
      source = {
        "source_id" => source_id,
        "path" => relative(path),
        "sha256" => sha(path),
        "purpose" => "Exact transport source for #{binding_kind}."
      }
      launch.fetch("sources") << source
      {
        "binding_kind" => binding_kind,
        "source_id" => source_id,
        "path" => source["path"],
        "sha256" => source["sha256"]
      }
    end

    document.dig("runtime_return", "runtime_owner")["owner"] = owner
    output = document.dig("runtime_return", "outputs", 0)
    output["output_kind"] = output_kind
    output["logical_owner"] = {"owner" => owner, "role" => owner_role}
    output["decision_epoch"] = launch.dig("founder_context", "decision_epoch")
    output["bindings"] = bindings
    document.fetch("director_review")["rubric_results"] = (BASE_REVIEW_CRITERIA + V19_REVIEW_CRITERIA.fetch(output_kind)).map do |criterion|
      {
        "criterion" => criterion,
        "result" => "pass",
        "evidence" => "The assigned director recorded an explicit #{criterion} judgment for the exact returned bytes."
      }
    end
    promotion = document.fetch("promotion")
    promotion["mode"] = "coordinator_exact_copy"
    promotion["promoter"] = {"owner" => "fixture-promoter", "role" => "overall_director"}
    promotion["approved_at"] = "2026-08-03T10:03:30+09:00"
    promotion["coordinator"] = {"owner" => "fixture-coordinator", "role" => "mechanical_coordinator"}
    promotion["copy_completed_at"] = promotion["decided_at"]
    document.dig("lifecycle", "events").last["actor"] = "fixture-coordinator"
    sync_v18_promotion(document)
    refresh_input_digest(document)
    refresh_result_digest(document)
    document
  end

  def build_pre_02a_section_output
    section_map = @run.join("research", "pre-02a-section-map.yaml")
    mappings = ["S00P", "S00", "S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"].map do |visual_id|
      audio_id = visual_id == "S00P" ? "AUDIO_PRE" : "AUDIO_#{visual_id.delete_prefix('S')}"
      {
        "visual_section_id" => visual_id,
        "audio_section_id" => audio_id,
        "source_audio_section_ids" => [audio_id]
      }
    end
    section_map.write(YAML.dump("mappings" => mappings))
    shard_dir = @run.join("work", "pre-02a-section-working-shards")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SECTION_CLI.to_s,
      "extract",
      SECTION_SOURCE.to_s,
      "--stage",
      "01",
      "--section-map",
      section_map.to_s,
      "--output-dir",
      shard_dir.to_s,
      "--sections",
      "S00",
      "--owner",
      "codex",
      "--json",
      chdir: ROOT.to_s
    )
    assert status.success?, "section extraction failed\n#{stdout}\n#{stderr}"
    @output = shard_dir.join("S00.yaml")
    contract = YAML.safe_load(@output.read, permitted_classes: [], aliases: true)
    contract.fetch("payload")["output_kind"] = "pre_02a_section_working_shard"
    contract.fetch("envelope")["content_digest"] = structured_sha(contract.fetch("payload"))
    @output.write(YAML.dump(contract))
  end

  def sync_v18_promotion(document)
    outputs = deep_copy(document.dig("runtime_return", "outputs"))
    document.dig("runtime_return", "wake_event")["output_pointers"] = deep_copy(outputs)
    document.dig("runtime_return", "wake_event")["aggregate_manifest"] = deep_copy(document.dig("runtime_return", "output_inventory", "aggregate_manifest"))
    document.fetch("director_review")["reviewed_outputs"] = deep_copy(outputs)
    promotion = document.fetch("promotion")
    promotion["approved_working_outputs"] = deep_copy(outputs)
    promotion["canonical_artifacts"] = outputs.each_with_index.map do |source, index|
      canonical_path = @run.join("canonical", "#{source['output_kind']}-#{index}.yaml")
      canonical_path.dirname.mkpath
      FileUtils.cp(ROOT.join(source.fetch("path")), canonical_path)
      deep_copy(source).merge(
        "path" => relative(canonical_path),
        "sha256" => sha(canonical_path),
        "role" => "mechanical coordinator exact-copy result",
        "source_output_path" => source.fetch("path"),
        "source_output_sha256" => source.fetch("sha256")
      )
    end
  end

  def refresh_input_digest(document)
    basis = {
      "lineage" => document.fetch("lineage"),
      "review_submission" => document.fetch("review_submission"),
      "launch" => document.fetch("launch")
    }
    document.dig("runtime_return", "input_digest")["sha256"] = structured_sha(basis)
  end

  def requirement_manifest(required_skills, profile_id: nil, checkpoint_id: nil)
    schema_path = ROOT.join("schemas", "department-dispatch.schema.json")
    sources = {
      "founder" => hashed_artifact(@source, "fixture Founder instruction source"),
      "skill" => {
        "path" => required_skills.first.fetch("path"),
        "sha256" => required_skills.first.fetch("sha256"),
        "role" => "fixture owning skill"
      },
      "policy" => hashed_artifact(@linked_read, "fixture policy source"),
      "contract" => hashed_artifact(@linked_read, "fixture contract source"),
      "schema" => hashed_artifact(schema_path, "fixture owning schema")
    }
    rows = REQUIREMENT_CATEGORIES.each_with_index.map do |category, index|
      {
        "requirement_id" => "#{category.upcase}-#{format('%02d', index + 1)}",
        "category" => category,
        "required" => true,
        "source_locator" => sources[category]&.fetch("path", nil) || "/launch/#{category}",
        "source_binding" => sources[category],
        "affected_scope" => "The exact bounded fixture output and its dispatch lifecycle.",
        "expected_output_target" => category == "goal" ? "/runtime_return/runtime_goal" : relative(@output),
        "evidence_type" => category == "goal" ? "runtime_goal" : (category == "hold" ? "hold" : "artifact"),
        "director_semantic_review_required" => %w[founder skill policy contract schema output quality].include?(category)
      }
    end
    dispatch_fixture_append_recipe_rows!(
      rows,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      output: hashed_artifact(@output, "bounded song-lock result")
    )
    rows
  end

  def mechanical_receipt(requirements, validated_at: "2026-08-03T10:01:50+09:00")
    value = {
      "contract_version" => "mechanical_compliance_receipt.v1",
      "validated_at" => validated_at,
      "validator" => "fixture-department-dispatch-mechanical-validator",
      "checks" => requirements.map do |requirement|
        {
          "check_id" => "MECH-#{requirement.fetch('requirement_id')}",
          "requirement_id" => requirement.fetch("requirement_id"),
          "check_kind" => requirement.fetch("category") == "goal" ? "goal_order" : "coverage",
          "target" => requirement.fetch("expected_output_target"),
          "result" => "pass",
          "evidence" => "Fixture structural evidence exists for #{requirement.fetch('requirement_id')}."
        }
      end,
      "all_required_checks_pass" => true,
      "receipt_sha256" => "0" * 64
    }
    value["receipt_sha256"] = structured_sha(value.reject { |key, _entry| key == "receipt_sha256" })
    value
  end

  def fulfillment_claims(requirements, output)
    requirements.map do |requirement|
      {
        "requirement_id" => requirement.fetch("requirement_id"),
        "disposition" => "applied",
        "output_evidence" => %w[goal hold].include?(requirement.fetch("category")) ? [] : [deep_copy(output)],
        "explanation" => "The worker applied #{requirement.fetch('requirement_id')} to the exact bounded fixture result."
      }
    end
  end

  def reviewer_read_closure(required_skills, requirements, read_completed_at: "2026-08-03T10:02:30+09:00")
    rows = []
    required_skills.each do |skill|
      rows << {
        "path" => skill.fetch("path"),
        "kind" => "skill",
        "revision" => skill.fetch("revision"),
        "sha256" => skill.fetch("sha256"),
        "read_to_eof" => true,
        "read_completed_at" => read_completed_at
      }
      Array(skill["linked_reads"]).each do |read|
        rows << {
          "path" => read.fetch("path"),
          "kind" => "linked_module",
          "revision" => "hash-bound-launch-read",
          "sha256" => read.fetch("sha256"),
          "read_to_eof" => true,
          "read_completed_at" => read_completed_at
        }
      end
    end
    requirements.each do |requirement|
      next unless requirement["director_semantic_review_required"] == true
      next unless %w[skill policy contract schema].include?(requirement.fetch("category"))
      next unless requirement["source_binding"].is_a?(Hash)

      source = requirement.fetch("source_binding")
      next if rows.any? { |row| row["path"] == source["path"] && row["sha256"] == source["sha256"] }

      rows << {
        "path" => source.fetch("path"),
        "kind" => requirement.fetch("category"),
        "revision" => "hash-bound-requirement-source",
        "sha256" => source.fetch("sha256"),
        "read_to_eof" => true,
        "read_completed_at" => read_completed_at
      }
    end
    rows
  end

  def requirement_review_results(requirements, output)
    requirements.map do |requirement|
      {
        "requirement_id" => requirement.fetch("requirement_id"),
        "result" => "pass",
        "evidence_locator" => output.fetch("path"),
        "evidence_sha256" => output.fetch("sha256"),
        "judgment" => "The Director read the exact returned revision and judged #{requirement.fetch('requirement_id')} complete."
      }
    end
  end

  def promoted_dispatch(stage_id: "song_production_lock", owner_role: "song_room", profile_id: nil, checkpoint_id: nil)
    prepared_at = "2026-08-03T10:00:00+09:00"
    launched_at = "2026-08-03T10:01:00+09:00"
    returned_at = "2026-08-03T10:02:00+09:00"
    reviewed_at = "2026-08-03T10:03:00+09:00"
    promoted_at = "2026-08-03T10:04:00+09:00"
    goal_opened_at = "2026-08-03T10:01:10+09:00"
    work_started_at = "2026-08-03T10:01:30+09:00"
    review_acquired_at = "2026-08-03T10:02:10+09:00"
    review_released_at = "2026-08-03T10:03:10+09:00"
    promotion_acquired_at = "2026-08-03T10:03:20+09:00"
    promotion_released_at = "2026-08-03T10:04:10+09:00"
    profile_id, checkpoint_id = profile_checkpoint_for(owner_role, stage_id) if profile_id.nil? || checkpoint_id.nil?
    director_roles = %w[overall_director creative_development_director edit_director]
    logical_role = director_roles.include?(owner_role) ? owner_role : "worker"
    worker_specialty = case owner_role
                       when "creative_development_director" then "cdd_reviewed_milestone"
                       when "edit_director" then "edit_reviewed_milestone"
                       else stage_id == "edit_assembly_playback_qc" ? "stage_04" : "front_planning"
                       end
    recipient_role = if owner_role == "creative_development_director" || owner_role == "edit_director"
                       "overall_director"
                     elsif stage_id == "edit_assembly_playback_qc"
                       "edit_director"
                     else
                       "creative_development_director"
                     end
    required_skills = if run_relative.start_with?("cf/")
                        [{
                          "path" => relative(@skill),
                          "revision" => "fixture-cf-code-v1",
                          "sha256" => sha(@skill),
                          "eof_required" => true,
                          "linked_reads" => [{
                            "path" => relative(@linked_read),
                            "sha256" => sha(@linked_read),
                            "eof_required" => true,
                            "reason" => "CF repository authority"
                          }]
                        }]
                      else
                        dispatch_fixture_profile_contract(
                          profile_id: profile_id,
                          checkpoint_id: checkpoint_id
                        ).fetch("required_skills")
                      end
    objective = "Return the bounded current song lock for director review."
    requirements = requirement_manifest(required_skills, profile_id: profile_id, checkpoint_id: checkpoint_id)
    launch = {
      "prepared_at" => prepared_at,
      "launched_at" => launched_at,
      "launch_kind" => "worker_dispatch",
      "compiled_launch_prompt" => compiled_launch_prompt(profile_id: profile_id, checkpoint_id: checkpoint_id),
      "task" => {
        "task_id" => @dispatch_id,
        "role" => owner_role,
        "objective" => objective,
        "exact_scope" => {
          "mode" => "whole_run",
          "stage_id" => stage_id,
          "section_ids" => [],
          "artifact_paths" => [relative(@output)]
        }
      },
      "goal_contract" => {
        "required" => true,
        "goal_text" => objective,
        "goal_text_sha256" => Digest::SHA256.hexdigest(objective),
        "source_objective_pointer" => "/launch/task/objective",
        "source_scope_pointer" => "/launch/task/exact_scope",
        "creation_timing" => "before_required_reads_and_creative_work",
        "completion_timing" => "only_after_valid_runtime_return_and_worker_self_check",
        "unsupported_runtime_action" => "goal_surface_unavailable_hold_before_work"
      },
      "requirement_manifest" => requirements,
      "founder_context" => {
        "decision_epoch" => "FOUNDER-EPOCH-TEST-01",
        "locks" => []
      },
      "required_skills" => required_skills,
      "sources" => [
        {
          "source_id" => "selected_song",
          "path" => relative(@source),
          "sha256" => sha(@source),
          "purpose" => "Selected song truth for the bounded lock."
        }
      ],
      "external_permission" => {
        "mode" => "closed_local",
        "allowed_surfaces" => [],
        "approval_reference" => nil
      },
      "bounded_output" => {
        "description" => "One hash-bound song-lock artifact.",
        "output_kind" => "bounded_artifact",
        "expected_paths" => [relative(@output)],
        "maximum_artifact_count" => 1,
        "anti_flat_evidence_requirements" => ["Preserve the selected song decision and its concrete rationale."]
      },
      "authority" => {
        "assigned_owner" => "fixture-worker",
        "director_owner" => "fixture-director",
        "promotion_owner" => "fixture-director",
        "canonical_write" => "bounded_to_expected_paths",
        "external_actions" => "forbidden",
        "may_decide" => ["Bounded song-lock wording inside the declared artifact."],
        "must_not" => ["Change another stage or use an external surface."]
      },
      "hold_conditions" => ["Required skill or source bytes cannot be loaded exactly."],
      "recipient" => {
        "owner" => "fixture-director",
        "role" => recipient_role,
        "return_route" => "director_output_review"
      }
    }
    dispatch_fixture_project_launch_prompt!(launch)
    skill_revisions = dispatch_fixture_runtime_skill_revisions(required_skills)
    outputs = [hashed_artifact(@output, "bounded song-lock result")]
    lineage = {
      "lineage_id" => "LINEAGE_#{@dispatch_id}",
      "attempt_id" => @dispatch_id,
      "attempt_number" => 1,
      "provider" => "codex",
      "runtime_surface" => "test-runtime",
      "session_id" => "SESSION_#{@dispatch_id}",
      "parent_session_id" => "SESSION_FIXTURE_DIRECTOR",
      "parent_lineage_id" => "LINEAGE_FIXTURE_DIRECTOR",
      "parent_dispatch_id" => "DISPATCH_FIXTURE_DIRECTOR",
      "previous_attempt_id" => nil,
      "delegation_depth" => 1,
      "lineage_state" => "active",
      "successor_attempt_id" => nil
    }
    review_submission = {
      "review_cycle_id" => @dispatch_id,
      "submission_number" => 1,
      "maximum_submissions" => 3,
      "submission_kind" => "initial",
      "root_attempt_id" => @dispatch_id,
      "previous_submission_attempt_id" => nil,
      "correction_source" => nil,
      "repair_targets" => [],
      "repair_acceptance_criteria" => [],
      "frozen_outputs" => []
    }
    receipt = mechanical_receipt(requirements)
    claims = fulfillment_claims(requirements, outputs.first)
    goal_completion_basis = {
      "mechanical_compliance_receipt_sha256" => receipt.fetch("receipt_sha256"),
      "worker_fulfillment_claims" => claims,
      "outputs" => outputs,
      "hold_reasons" => []
    }
    runtime_return = {
      "returned_at" => returned_at,
      "work_started_at" => work_started_at,
      "runtime_owner" => {
        "owner" => "fixture-worker",
        "role" => owner_role,
        "runtime_surface" => "test-runtime"
      },
      "runtime_goal" => {
        "provider" => "codex",
        "native_goal_id" => "GOAL-#{@dispatch_id}",
        "opened_at" => goal_opened_at,
        "goal_text_sha256" => launch.dig("goal_contract", "goal_text_sha256"),
        "state_at_return" => "achieved",
        "completion_evidence_sha256" => structured_sha(goal_completion_basis)
      },
      "skill_revisions" => skill_revisions,
      "mechanical_compliance_receipt" => receipt,
      "worker_fulfillment_claims" => claims,
      "input_digest" => {
        "basis" => "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4",
        "sha256" => structured_sha({"lineage" => lineage, "review_submission" => review_submission, "launch" => launch})
      },
      "output_inventory" => {
        "mode" => "single_artifact",
        "artifact_count" => 1,
        "aggregate_manifest" => nil
      },
      "outputs" => outputs,
      "result_digest" => {
        "basis" => "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4",
        "sha256" => "0" * 64
      },
      "transport_closure_summary" => {
        "status" => "clean",
        "creative_bytes_changed" => false,
        "error" => nil,
        "source_digest" => {"basis" => "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4", "sha256" => outputs.first.fetch("sha256")},
        "output_digest" => {"basis" => "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4", "sha256" => outputs.first.fetch("sha256")},
        "schema_version" => "idol-transport-closure-summary.v1",
        "refresh_receipt_pointer" => nil,
        "corroboration_pointers" => [],
        "repair_count" => 0,
        "exceptions" => [],
        "next_owner" => launch.dig("recipient", "role")
      },
      "hold_reasons" => [],
      "wake_event" => {
        "event_kind" => "final",
        "recipient_role" => launch.dig("recipient", "role"),
        "output_pointers" => deep_copy(outputs),
        "aggregate_manifest" => nil,
        "hold_or_rejection_pointers" => [],
        "risk_or_unresolved_decision_pointers" => [],
        "raw_commentary_included" => false
      }
    }
    review_lease_id = "REVIEW-#{@dispatch_id}"
    promotion_lease_id = "PROMOTION-#{@dispatch_id}"
    document = {
      "schema_version" => "idol-department-dispatch.v8",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => @dispatch_id,
      "run" => run_relative,
      "lineage" => lineage,
      "review_submission" => review_submission,
      "lifecycle" => {
        "current_state" => "promoted",
        "events" => [
          {"state" => "prepared", "at" => prepared_at, "actor" => "fixture-director"},
          {"state" => "launched", "at" => launched_at, "actor" => "fixture-runtime"},
          {"state" => "returned", "at" => returned_at, "actor" => "fixture-worker"},
          {"state" => "reviewed", "at" => reviewed_at, "actor" => "fixture-director"},
          {"state" => "promoted", "at" => promoted_at, "actor" => "fixture-director"}
        ]
      },
      "review_control" => {
        "queue_policy" => "single_flight_per_recipient_director_then_global_overall_promotion",
        "queue_state" => "released",
        "queued_at" => returned_at,
        "queue_priority" => {
          "dependency_rank" => 0,
          "returned_at_then_dispatch_id" => true
        },
        "review_lease" => {
          "lease_id" => review_lease_id,
          "director_owner" => "fixture-director",
          "acquired_at" => review_acquired_at,
          "released_at" => review_released_at
        },
        "promotion_lease" => {
          "lease_id" => promotion_lease_id,
          "overall_owner" => "fixture-director",
          "acquired_at" => promotion_acquired_at,
          "released_at" => promotion_released_at
        }
      },
      "routing_identity" => {
        "logical_role" => logical_role,
        "worker_specialty" => worker_specialty,
        "provider" => "codex",
        "logical_profile_alias" => director_roles.include?(logical_role) ? "director_deep" : "worker_high",
        "execution_profile_id" => director_roles.include?(logical_role) ? "codex_director_deep" : "codex_worker_high",
        "resolved_provider_model" => "provider_snapshot_fixture",
        "reasoning_effort" => "high",
        "provider_capability_snapshot_sha256" => "0" * 64,
        "resolved_profile_snapshot_ref" => "RUN/work/provider-profile-snapshot.yaml#/worker_high",
        "session_topology" => "physical_native_session",
        "active_role_binding_id" => "ACTIVE-#{recipient_role.upcase}-FIXTURE",
        "internal_subagent_policy" => "provider_native_default_no_logical_role_or_authority",
        "exact_task_subagent_override" => "none",
        "founder_visible" => director_roles.include?(logical_role),
        "return_recipient_role" => recipient_role,
        "physical_transfer" => nil
      },
      "internal_delegation_summary" => {
        "provider_native_helpers_used" => false,
        "helper_count" => 0,
        "logical_roles_created" => 0,
        "canonical_owner_changed" => false,
        "founder_conversation_authority_granted" => false
      },
      "launch" => launch,
      "runtime_return" => runtime_return,
      "director_review" => {
        "reviewed_at" => reviewed_at,
        "director" => {"owner" => "fixture-director", "role" => recipient_role},
        "review_lease_id" => review_lease_id,
        "reviewer_read_closure" => reviewer_read_closure(required_skills, requirements),
        "mechanical_receipt_sha256" => receipt.fetch("receipt_sha256"),
        "requirement_results" => requirement_review_results(requirements, outputs.first),
        "disposition" => "accept",
        "rubric_results" => BASE_REVIEW_CRITERIA.map do |criterion|
          {
            "criterion" => criterion,
            "result" => "pass",
            "evidence" => "The Director recorded a concrete #{criterion} judgment for the exact returned bytes."
          }
        end,
        "reviewed_outputs" => outputs,
        "summary" => "The director reviewed and accepted the exact returned bytes.",
        "correction" => nil
      },
      "promotion" => {
        "decision" => "promoted",
        "mode" => "direct_canonical_promotion",
        "decided_at" => promoted_at,
        "promoter" => {"owner" => "fixture-director", "role" => "overall_director"},
        "promotion_lease_id" => promotion_lease_id,
        "approved_at" => promoted_at,
        "reason" => "Director review passed the bounded output.",
        "approved_working_outputs" => outputs,
        "coordinator" => nil,
        "copy_completed_at" => nil,
        "canonical_artifacts" => outputs,
        "queue_release_verified" => true,
        "baseline_refresh_evidence_sha256" => "0" * 64,
        "next_recipient" => {
          "owner" => "fixture-orchestrator",
          "role" => "next-stage-coordinator",
          "return_route" => "active_harness_stage"
        }
      }
    }
    refresh_result_digest(document)
    refresh_promotion_baseline(document)
    document
  end

  def refresh_result_digest(document)
    runtime_return = document.fetch("runtime_return")
    completion_basis = {
      "mechanical_compliance_receipt_sha256" => runtime_return.dig("mechanical_compliance_receipt", "receipt_sha256"),
      "worker_fulfillment_claims" => runtime_return["worker_fulfillment_claims"],
      "outputs" => runtime_return["outputs"],
      "hold_reasons" => runtime_return["hold_reasons"]
    }
    runtime_return.dig("runtime_goal")["completion_evidence_sha256"] = structured_sha(completion_basis)
    basis = {
      "work_started_at" => runtime_return["work_started_at"],
      "runtime_owner" => runtime_return["runtime_owner"],
      "runtime_goal" => runtime_return["runtime_goal"],
      "skill_revisions" => runtime_return["skill_revisions"],
      "mechanical_compliance_receipt" => runtime_return["mechanical_compliance_receipt"],
      "worker_fulfillment_claims" => runtime_return["worker_fulfillment_claims"],
      "output_inventory" => runtime_return["output_inventory"],
      "outputs" => runtime_return["outputs"],
      "hold_reasons" => runtime_return["hold_reasons"],
      "wake_event" => runtime_return["wake_event"]
    }
    runtime_return.fetch("result_digest")["sha256"] = structured_sha(basis)
    refresh_promotion_baseline(document) if document["promotion"].is_a?(Hash)
  end

  def refresh_promotion_baseline(document)
    promotion = document.fetch("promotion")
    basis = {
      "dispatch_id" => document.fetch("dispatch_id"),
      "review_lease_id" => document.dig("director_review", "review_lease_id"),
      "promotion_lease_id" => promotion["promotion_lease_id"],
      "decision" => promotion["decision"],
      "approved_working_outputs" => promotion["approved_working_outputs"],
      "canonical_artifacts" => promotion["canonical_artifacts"],
      "decided_at" => promotion["decided_at"]
    }
    promotion["baseline_refresh_evidence_sha256"] = structured_sha(basis)
  end

  def refresh_compiled_launch_digest(document)
    compiled = document.dig("launch", "compiled_launch_prompt")
    basis = compiled.reject { |key, _entry| %w[rendered_prompt compiled_input_sha256 rendered_prompt_sha256].include?(key) }
    compiled["compiled_input_sha256"] = structured_sha(basis)
  end

  def hold_dispatch(document, retry_route:, problem: "The returned decision needs a bounded revision before promotion.")
    output = document.dig("runtime_return", "outputs", 0)
    document.dig("lifecycle")["current_state"] = "hold"
    document.dig("lifecycle", "events").last["state"] = "hold"
    document.dig("director_review")["disposition"] = "hold"
    document.dig("director_review", "rubric_results", 0)["result"] = "hold"
    document.dig("director_review")["correction"] = {
      "problem" => problem,
      "evidence" => [{
        "kind" => "returned_output",
        "locator" => output.fetch("path"),
        "source_sha256" => output.fetch("sha256"),
        "observation" => "The exact returned bytes contain the unresolved scoped defect."
      }],
      "screen_consequence" => "Promotion would carry the unresolved decision into the next screen stage.",
      "correction_action" => "Revise only the bounded returned decision under the declared retry route.",
      "remaining_risk" => "Any successor still requires a fresh Director judgment on changed bytes.",
      "affected_owner" => document.dig("launch", "authority", "assigned_owner"),
      "invalidated_outputs" => [deep_copy(output)],
      "complete_problem_set" => true,
      "acceptance_criteria" => ["The revised output resolves every observed problem in the declared repair scope."],
      "retry_route" => retry_route
    }
    promotion = document.fetch("promotion")
    promotion["decision"] = "hold"
    promotion["mode"] = "held_without_promotion"
    promotion["approved_at"] = nil
    promotion["approved_working_outputs"] = []
    promotion["coordinator"] = nil
    promotion["copy_completed_at"] = nil
    promotion["canonical_artifacts"] = []
    promotion["reason"] = "Director held promotion for the declared correction route."
    refresh_result_digest(document)
    document
  end

  def add_bounded_outputs(document, total:)
    raise ArgumentError, "total must be at least two" if total < 2

    (2..total).each do |number|
      path = @run.join("research", "cut-#{format('%02d', number)}.yaml")
      path.write("cut: #{number}\nstatus: passed\n")
      output = hashed_artifact(path, "bounded cut #{number}")
      document.dig("launch", "task", "exact_scope", "artifact_paths") << relative(path)
      document.dig("launch", "bounded_output", "expected_paths") << relative(path)
      document.dig("runtime_return", "outputs") << deep_copy(output)
    end
    document.dig("launch", "bounded_output")["maximum_artifact_count"] = total
    outputs = document.dig("runtime_return", "outputs")
    document.dig("runtime_return", "wake_event")["output_pointers"] = deep_copy(outputs)
    document.fetch("director_review")["reviewed_outputs"] = deep_copy(outputs)
    document.fetch("promotion")["approved_working_outputs"] = deep_copy(outputs)
    document.fetch("promotion")["canonical_artifacts"] = deep_copy(outputs)
    manifest_path = @run.join("work", "manifests", "#{document.fetch('dispatch_id')}-outputs.yaml")
    manifest_path.dirname.mkpath
    manifest_path.write(YAML.dump("outputs" => outputs.map { |row| {"path" => row.fetch("path"), "sha256" => row.fetch("sha256")} }))
    manifest = hashed_artifact(manifest_path, "aggregate output manifest")
    document.dig("runtime_return", "output_inventory").merge!(
      "mode" => "aggregate_manifest",
      "artifact_count" => total,
      "aggregate_manifest" => manifest
    )
    document.dig("runtime_return", "wake_event")["aggregate_manifest"] = deep_copy(manifest)
    refresh_input_digest(document)
    refresh_result_digest(document)
    document
  end

  def successor_after(predecessor, output_bytes: nil)
    predecessor_id = predecessor.fetch("dispatch_id")
    predecessor_path = @dispatch.dirname.join("#{predecessor_id}.yaml")
    predecessor_path.write(YAML.dump(predecessor))
    predecessor_sha = sha(predecessor_path)
    @output.write(output_bytes) if output_bytes

    @dispatch_id = "SONG_LOCK_#{SecureRandom.hex(3).upcase}"
    @dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    successor = promoted_dispatch
    successor.fetch("lineage").merge!(
      "lineage_id" => predecessor.dig("lineage", "lineage_id"),
      "attempt_number" => predecessor.dig("lineage", "attempt_number").to_i + 1,
      "session_id" => predecessor.dig("lineage", "session_id"),
      "parent_session_id" => predecessor.dig("lineage", "parent_session_id"),
      "parent_lineage_id" => predecessor.dig("lineage", "parent_lineage_id"),
      "parent_dispatch_id" => predecessor.dig("lineage", "parent_dispatch_id"),
      "previous_attempt_id" => predecessor_id,
      "provider" => predecessor.dig("lineage", "provider"),
      "runtime_surface" => predecessor.dig("lineage", "runtime_surface")
    )
    correction = predecessor.dig("director_review", "correction")
    repair_targets = deep_copy(correction.fetch("invalidated_outputs"))
    repair_paths = repair_targets.map { |row| row.fetch("path") }
    frozen_outputs = deep_copy(predecessor.dig("runtime_return", "outputs")).reject do |row|
      repair_paths.include?(row.fetch("path"))
    end
    predecessor_submission = predecessor.fetch("review_submission")
    successor["review_submission"] = {
      "review_cycle_id" => predecessor_submission.fetch("review_cycle_id"),
      "submission_number" => predecessor_submission.fetch("submission_number") + 1,
      "maximum_submissions" => 3,
      "submission_kind" => "targeted_correction",
      "root_attempt_id" => predecessor_submission.fetch("root_attempt_id"),
      "previous_submission_attempt_id" => predecessor_id,
      "correction_source" => {
        "dispatch_id" => predecessor_id,
        "path" => relative(predecessor_path),
        "sha256" => predecessor_sha,
        "json_pointer" => "/director_review/correction"
      },
      "repair_targets" => repair_targets,
      "repair_acceptance_criteria" => deep_copy(correction.fetch("acceptance_criteria")),
      "frozen_outputs" => frozen_outputs
    }
    successor.dig("launch", "task")["objective"] = correction.fetch("correction_action")
    successor.dig("launch", "task")["exact_scope"] = deep_copy(predecessor.dig("launch", "task", "exact_scope")).merge(
      "artifact_paths" => repair_paths
    )
    successor.dig("launch", "goal_contract")["goal_text"] = correction.fetch("correction_action")
    successor.dig("launch", "goal_contract")["goal_text_sha256"] = Digest::SHA256.hexdigest(correction.fetch("correction_action"))
    successor.dig("runtime_return", "runtime_goal")["goal_text_sha256"] = successor.dig("launch", "goal_contract", "goal_text_sha256")
    successor.dig("launch", "bounded_output")["expected_paths"] = repair_paths
    successor.dig("launch", "bounded_output")["maximum_artifact_count"] = repair_paths.length
    target_by_path = repair_targets.each_with_object({}) { |row, result| result[row.fetch("path")] = row }
    %w[runtime_return].each do |container|
      successor.fetch(container).fetch("outputs").each do |row|
        target = target_by_path.fetch(row.fetch("path"))
        row["source_output_path"] = target.fetch("path")
        row["source_output_sha256"] = target.fetch("sha256")
      end
    end
    successor.dig("runtime_return", "wake_event")["output_pointers"] = deep_copy(successor.dig("runtime_return", "outputs"))
    successor.fetch("director_review")["reviewed_outputs"] = deep_copy(successor.dig("runtime_return", "outputs"))
    successor.fetch("promotion")["approved_working_outputs"] = deep_copy(successor.dig("runtime_return", "outputs"))
    successor.fetch("promotion")["canonical_artifacts"] = deep_copy(successor.dig("runtime_return", "outputs"))
    refresh_input_digest(successor)
    refresh_result_digest(successor)
    successor
  end

  def write_dispatch(document)
    @dispatch.write(YAML.dump(document))
  end

  def validate(*arguments)
    Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      *arguments,
      relative(@dispatch),
      chdir: ROOT.to_s
    )
  end
end
