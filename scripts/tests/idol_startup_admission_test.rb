# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "tmpdir"
require "yaml"
require_relative "support/department_dispatch_profile_fixture"

SCRIPT_PATH = Pathname.new(__dir__).join("..", "idol_startup_admission.rb").expand_path
REAL_ROOT = SCRIPT_PATH.dirname.dirname
require SCRIPT_PATH.to_s

class IdolStartupAdmissionTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  RUN_ROOT = "runs/test-album/test-title/TEST_STARTUP_001"
  DDC_VALIDATOR_RELATIVE = "scripts/validate_department_dispatch.rb"
  PROFILE_CHECKPOINTS = {
    "overall_director" => "director_startup",
    "creative_development_director" => "cdd_startup",
    "reference_research_generalist" => "reference_story_sequence_role",
    "pre_02a_development_block_fp" => "section_01_core_direction"
  }.freeze
  SEQUENCE_FOUNDER_MESSAGE = [
    "Read the complete active storyline and the current Section/Major job plus every candidate in the same complete Major group.",
    "Judge body action and gaze/head together with camera translation, rotation, lens, angle, composition, depth, occlusion, reveal, and start/landing.",
    "Continuous camera energy is a hypothesis, never a default: locked or intentional HOLD is legal, and 360/full orbit is never presumed over pan, lateral motion, zoom pulses, or another supported family.",
    "Face readability is conditional. Never force a frontal/readable face or front gaze; when identity is visible, preserve the exact current-title hair, styling, clothing, silhouette, face, and member-specific cues that are actually visible."
  ].join("\n").freeze
  SEQUENCE_REQUIREMENT_OVERRIDES = {
    "founder" => {
      "requirement_id" => "FOUNDER-SEQUENCE-CONTEXT",
      "affected_scope" => "Exact active full-storyline passage, current Section/Major screen job, and the complete two-to-four Sequence Composition candidate group; no candidate or identity visibility intent may be dropped or genericized."
    },
    "skill" => {
      "requirement_id" => "SKILL-SEQUENCE-MOTION-APPLICATION",
      "affected_scope" => "Jointly analyze body action, gaze/head, camera translation and rotation, lens, angle/composition, depth/occlusion/reveal, and start/landing. Continuous camera energy stays a hypothesis; locked or intentional HOLD is valid, and no 360/full-orbit or any other motion family is a default."
    },
    "quality" => {
      "requirement_id" => "QUALITY-SEQUENCE-MOTION-ACCEPTANCE",
      "affected_scope" => "Condition face readability on the scene; never force a frontal/readable face or front gaze. Preserve every actually visible current-title hair, styling, clothing, silhouette, face, and member-specific cue exactly, including side, rear, silhouette, occluded, wide, and fast-turn views, and require independent CDD review of the exact returned bytes."
    }
  }.freeze

  def setup
    @temporary = Pathname.new(Dir.mktmpdir("idol-startup-admission"))
    @original_root = Object.const_get(:ROOT)
    @original_registry = Object.const_get(:PROFILE_REGISTRY)
    replace_constant(:ROOT, @temporary)
    replace_constant(:PROFILE_REGISTRY, @temporary.join(PROFILE_REGISTRY_RELATIVE))
    copy_profile_closure
    prepare_run
  end

  def teardown
    replace_constant(:ROOT, @original_root)
    replace_constant(:PROFILE_REGISTRY, @original_registry)
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  def test_complete_overall_and_cdd_admission_preserves_exact_director_delta
    founder_message = "이 런을 계속해. 기존 흐름과 확정값은 유지해."
    prepared = prepare_read_gate(founder_message)

    assert_equal "prepared", prepared.fetch("status")
    assert_equal Digest::SHA256.hexdigest(founder_message), prepared.fetch("founder_message_sha256")
    assert_includes prepared.fetch("rendered_prompt"), founder_message
    assert_equal 1, exact_occurrence_count(
      prepared.fetch("rendered_prompt"),
      founder_verbatim_block(founder_message, founder_request_binding(founder_message))
    )
    assert_equal Digest::SHA256.hexdigest(prepared.fetch("rendered_prompt")), prepared.fetch("rendered_prompt_sha256")

    delta = startup_delta(prepared, founder_message)
    overall = compile_overall(founder_message, envelope("idol_startup_delta", delta))

    assert_equal "compiled", overall.fetch("status")
    TWELVE_HEADINGS.each { |heading| assert_equal 1, overall.fetch("rendered_prompt").lines.count { |line| line.chomp == heading } }
    assert_includes overall.fetch("rendered_prompt"), delta.fetch("current_creative_job")
    assert_includes overall.fetch("rendered_prompt"), delta.fetch("required_work")
    assert_includes overall.fetch("rendered_prompt"), delta.fetch("quality_proof")
    assert_equal 1, overall.fetch("rendered_prompt").scan(founder_message).length
    assert_includes overall.fetch("rendered_prompt"), "[Founder request exact-copy binding | #{canonical_json(founder_request_binding(founder_message))}]"
    assert_includes overall.fetch("rendered_prompt"), "scope every current-task priority"
    assert_includes overall.fetch("rendered_prompt"), "exact projection into the worker's applicable Blocks 03, 07, and 09"
    assert_includes prompt_block(overall.fetch("rendered_prompt"), 6), "Keep the native Goal concise"
    assert_includes prompt_block(overall.fetch("rendered_prompt"), 6), "never the full Founder conversation"
    refute_includes prompt_block(overall.fetch("rendered_prompt"), 6), founder_message
    refute_includes prompt_block(overall.fetch("rendered_prompt"), 8), founder_message

    cdd_delta = {
      "status" => "ready",
      "founder_request_binding" => founder_request_binding(founder_message),
      "current_creative_job" => "세 후보의 화면 결과를 비교해 Founder가 고를 완결 후보를 준비한다.",
      "exact_scope" => "현재 Front Planning Direction Synthesis",
      "non_scope" => "02A 이후 제작과 기존 확정 구간",
      "unaffected_truth" => ["기존 타깃과 선택 음원", "현재 하네스 단계 순서"],
      "required_work" => "등록 Recipe를 적용하고 후보별 근거·반대 해석·화면 결과를 제시한다.",
      "quality_proof" => "각 후보가 현재 곡과 관객 약속에 주는 실제 화면 차이를 증명한다.",
      "unresolved_decisions" => ["Founder의 기본 후보 선택"],
      "hold_reasons" => []
    }
    cdd = compile_cdd(founder_message, "Overall route\n#{envelope('idol_cdd_startup_delta', cdd_delta)}")

    assert_equal "compiled", cdd.fetch("status")
    assert_equal "creative_development_director", cdd.dig("selected_profile", "role")
    TWELVE_HEADINGS.each { |heading| assert_equal 1, cdd.fetch("rendered_prompt").lines.count { |line| line.chomp == heading } }
    assert_includes cdd.fetch("rendered_prompt"), cdd_delta.fetch("current_creative_job")
    assert_equal 1, cdd.fetch("rendered_prompt").scan(founder_message).length
    assert_includes cdd.fetch("rendered_prompt"), "[Founder request exact-copy binding | #{canonical_json(founder_request_binding(founder_message))}]"
    assert_includes cdd.fetch("rendered_prompt"), "a generic instruction to read or follow a skill is not a substitute"
    assert_includes cdd.fetch("rendered_prompt"), "A dropped, merged-away, genericized, or self-asserted priority is a HOLD"

    receipt = {
      "status" => "ready",
      "role_context_receipt" => receipt_for(cdd.fetch("role_context_pack")),
      "hold_reasons" => []
    }
    controls = '<fp_dispatch>{"version":3,"jobs":[]}</fp_dispatch>'
    validated = validate_cdd(founder_message, "CDD ready\n#{envelope('idol_cdd_startup_return', receipt)}\n#{controls}")

    assert_equal "validated", validated.fetch("status")
    assert_equal "CDD ready\n#{controls}", validated.fetch("controller_text")
    assert_empty validated.fetch("hold_reasons")
  end

  def test_no_cdd_route_preserves_visible_overall_text
    founder_message = "현재 상태만 이어서 판단해."
    result = compile_cdd(
      founder_message,
      "Overall answer\n#{envelope('idol_overall_startup_return', {'status' => 'ready', 'cdd_required' => false, 'hold_reasons' => []})}"
    )

    assert_equal "no_route", result.fetch("status")
    assert_equal "Overall answer", result.fetch("controller_text")
    assert_nil result.fetch("rendered_prompt")
  end

  def test_stale_required_read_holds_before_a_model_prompt
    required_path = @temporary.join("skills/idol-orchestrator/SKILL.md")
    required_path.write("changed after profile binding\n")

    error = assert_raises(StartupAdmissionError) { prepare_read_gate("이 런을 시작해.") }

    assert_includes error.message, "startup binding SHA-256 is stale"
  end

  def test_role_context_receipt_must_exact_copy_compiled_pack
    founder_message = "이 런을 시작해."
    prepared = prepare_read_gate(founder_message)
    delta = startup_delta(prepared, founder_message)
    delta.fetch("role_context_receipt")["pack_digest"] = "0" * 64

    error = assert_raises(StartupAdmissionError) do
      compile_overall(founder_message, envelope("idol_startup_delta", delta))
    end

    assert_includes error.message, "exact-copy the compiled startup pack receipt"
  end

  def test_delta_marker_must_be_final_and_machine_cannot_fill_missing_prose
    founder_message = "이 런을 시작해."
    prepared = prepare_read_gate(founder_message)
    delta = startup_delta(prepared, founder_message)
    delta["quality_proof"] = ""

    error = assert_raises(StartupAdmissionError) do
      compile_overall(founder_message, "#{envelope('idol_startup_delta', delta)}\nextra")
    end

    assert_match(/final bytes|non-empty string/, error.message)
  end

  def test_founder_verbatim_is_exactly_once_in_each_director_hop_even_with_multiline_text
    founder_message = "첫째, 스토리라인을 끝까지 읽어라.\n둘째, 얼굴을 모든 컷에 강제하지 말고 보일 때만 정확히 유지해라."
    prepared = prepare_read_gate(founder_message)
    delta = startup_delta(prepared, founder_message)
    overall = compile_overall(founder_message, envelope("idol_startup_delta", delta))

    assert_equal 1, overall.fetch("rendered_prompt").scan(founder_message).length
    assert_equal Digest::SHA256.hexdigest(founder_message), overall.fetch("founder_message_sha256")

    cdd_delta = {
      "status" => "ready",
      "founder_request_binding" => founder_request_binding(founder_message),
      "current_creative_job" => "현재 우선사항을 작업 가능한 범위로 좁힌다.",
      "exact_scope" => "현재 CDD 과제 라우팅",
      "non_scope" => "새 역할·Stage·창작 권한",
      "unaffected_truth" => ["기존 소유권", "기존 단계"],
      "required_work" => "각 우선사항을 독립 requirement row로 분해한다.",
      "quality_proof" => "worker fulfillment와 CDD result가 각 row를 닫는다.",
      "unresolved_decisions" => ["현재 작업자 배치"],
      "hold_reasons" => []
    }
    cdd = compile_cdd(founder_message, envelope("idol_cdd_startup_delta", cdd_delta))

    assert_equal 1, cdd.fetch("rendered_prompt").scan(founder_message).length
    assert_equal Digest::SHA256.hexdigest(founder_message), cdd.fetch("founder_message_sha256")
  end

  def test_missing_founder_request_binding_holds_both_director_compilers
    founder_message = "현재 요청을 원문 그대로 전달해."
    prepared = prepare_read_gate(founder_message)
    overall_delta = startup_delta(prepared, founder_message)
    overall_delta.delete("founder_request_binding")

    overall_error = assert_raises(StartupAdmissionError) do
      compile_overall(founder_message, envelope("idol_startup_delta", overall_delta))
    end
    assert_includes overall_error.message, "founder_request_binding"

    cdd_delta = valid_cdd_delta(founder_message)
    cdd_delta.delete("founder_request_binding")
    cdd_error = assert_raises(StartupAdmissionError) do
      compile_cdd(founder_message, envelope("idol_cdd_startup_delta", cdd_delta))
    end
    assert_includes cdd_error.message, "founder_request_binding"
  end

  def test_changed_founder_bytes_cannot_rebind_a_stale_read_gate_delta
    founder_message = "스토리라인을 보존하고 현재 요청을 이어가."
    changed_message = "스토리라인을 보존하고 현재 요청을 다르게 이어가."
    prepared = prepare_read_gate(founder_message)
    overall_delta = startup_delta(prepared, founder_message)

    overall_error = assert_raises(StartupAdmissionError) do
      compile_overall(changed_message, envelope("idol_startup_delta", overall_delta))
    end
    assert_includes overall_error.message, "initial Overall read-gate Founder request locator"

    cdd_error = assert_raises(StartupAdmissionError) do
      compile_cdd(changed_message, envelope("idol_cdd_startup_delta", valid_cdd_delta(founder_message)))
    end
    assert_includes cdd_error.message, "initial Overall read-gate Founder request locator"
  end

  def test_founder_request_hash_or_locator_mismatch_holds
    founder_message = "현재 우선순위를 정확히 유지해."
    prepared = prepare_read_gate(founder_message)
    overall_delta = startup_delta(prepared, founder_message)
    overall_delta.fetch("founder_request_binding")["sha256"] = "0" * 64

    hash_error = assert_raises(StartupAdmissionError) do
      compile_overall(founder_message, envelope("idol_startup_delta", overall_delta))
    end
    assert_includes hash_error.message, "locator and SHA-256"

    cdd_delta = valid_cdd_delta(founder_message)
    cdd_delta.fetch("founder_request_binding")["source_json_pointer"] = "/founder_summary"
    locator_error = assert_raises(StartupAdmissionError) do
      compile_cdd(founder_message, envelope("idol_cdd_startup_delta", cdd_delta))
    end
    assert_includes locator_error.message, "locator and SHA-256"
  end

  def test_founder_binding_rejects_an_invented_paraphrase_field
    founder_message = "의역하지 말고 이 문장을 그대로 전달해."
    prepared = prepare_read_gate(founder_message)
    delta = startup_delta(prepared, founder_message)
    delta.fetch("founder_request_binding")["founder_request_paraphrase"] = "현재 우선순위를 잘 반영한다."

    error = assert_raises(StartupAdmissionError) do
      compile_overall(founder_message, envelope("idol_startup_delta", delta))
    end

    assert_includes error.message, "founder_request_binding keys must be exactly"
  end

  def test_founder_request_omission_is_rejected_for_overall_and_cdd_block_three
    founder_message = "원문을 Block 03에서 누락하지 마."
    prepared = prepare_read_gate(founder_message)
    overall = compile_overall(
      founder_message,
      envelope("idol_startup_delta", startup_delta(prepared, founder_message))
    )
    cdd = compile_cdd(founder_message, envelope("idol_cdd_startup_delta", valid_cdd_delta(founder_message)))
    binding = founder_request_binding(founder_message)
    exact_block = founder_verbatim_block(founder_message, binding)

    {
      "overall_director" => overall.fetch("rendered_prompt"),
      "creative_development_director" => cdd.fetch("rendered_prompt")
    }.each do |role, prompt|
      omitted = prompt.sub(exact_block, "[Founder request omitted]")
      error = assert_raises(StartupAdmissionError) do
        verify_twelve_block_founder_carry!(omitted, founder_message, binding, role)
      end
      assert_match(/verbatim exactly once|Block 03 omitted/, error.message)
    end
  end

  def test_duplicate_founder_verbatim_is_rejected_for_overall_and_cdd
    founder_message = "원문은 Director Assignment Delta에 한 번만 둬."
    prepared = prepare_read_gate(founder_message)
    overall = compile_overall(
      founder_message,
      envelope("idol_startup_delta", startup_delta(prepared, founder_message))
    )
    cdd = compile_cdd(founder_message, envelope("idol_cdd_startup_delta", valid_cdd_delta(founder_message)))
    binding = founder_request_binding(founder_message)
    exact_block = founder_verbatim_block(founder_message, binding)

    {
      "overall_director" => overall.fetch("rendered_prompt"),
      "creative_development_director" => cdd.fetch("rendered_prompt")
    }.each do |role, prompt|
      duplicated = prompt.sub(exact_block, "#{exact_block}\n#{exact_block}")
      error = assert_raises(StartupAdmissionError) do
        verify_twelve_block_founder_carry!(duplicated, founder_message, binding, role)
      end
      assert_includes error.message, "verbatim exactly once"

      duplicated_payload = prompt.sub(
        "Current-priority projection rule:",
        "#{founder_message}\n\nCurrent-priority projection rule:"
      )
      payload_error = assert_raises(StartupAdmissionError) do
        verify_twelve_block_founder_carry!(duplicated_payload, founder_message, binding, role)
      end
      assert_includes payload_error.message, "must not duplicate"
    end
  end

  def test_sequence_priorities_and_projection_closure_are_fail_closed_across_overall_and_cdd_startup
    prepared = prepare_read_gate(SEQUENCE_FOUNDER_MESSAGE)
    overall = compile_overall(
      SEQUENCE_FOUNDER_MESSAGE,
      envelope("idol_startup_delta", startup_delta(prepared, SEQUENCE_FOUNDER_MESSAGE))
    )
    cdd = compile_cdd(
      SEQUENCE_FOUNDER_MESSAGE,
      envelope("idol_cdd_startup_delta", valid_cdd_delta(SEQUENCE_FOUNDER_MESSAGE))
    )
    binding = founder_request_binding(SEQUENCE_FOUNDER_MESSAGE)

    {
      "overall_director" => overall.fetch("rendered_prompt"),
      "creative_development_director" => cdd.fetch("rendered_prompt")
    }.each do |role, prompt|
      assert_equal 1, prompt.scan(SEQUENCE_FOUNDER_MESSAGE).length, role
      assert_equal 1, prompt_block(prompt, 2).scan(SEQUENCE_FOUNDER_MESSAGE).length, role

      {
        6 => CURRENT_PRIORITY_PROJECTION_CLAUSES,
        8 => PRIORITY_CLOSURE_CLAUSES
      }.each do |block_index, clauses|
        clauses.each do |clause|
          assert_equal 1, prompt.scan(clause).length, "#{role} #{clause}"
          assert_equal 1, prompt_block(prompt, block_index).scan(clause).length, "#{role} #{clause}"

          startup_priority_mutations(prompt, clause, block_index).each do |mutation, mutated_prompt|
            error = assert_raises(StartupAdmissionError, "#{role} #{block_index} #{mutation}") do
              verify_twelve_block_founder_carry!(mutated_prompt, SEQUENCE_FOUNDER_MESSAGE, binding, role)
            end
            assert_includes error.message, "exact-carry each current-priority rule once", "#{role} #{block_index} #{mutation}"
          end
        end
      end
    end
  end

  def test_sequence_requirement_rows_exact_project_to_worker_blocks_and_reject_all_projection_drift
    document, dispatch_path = build_promoted_dispatch(
      dispatch_id: "SEQUENCE_PROMPT_001",
      stage_id: "front_planning_integration",
      profile_id: "reference_research_generalist",
      checkpoint_id: "reference_story_sequence_role",
      artifact_text: "sequence_motion_analysis: fixture\nstatus: ready_for_cdd_review\n",
      requirement_overrides: SEQUENCE_REQUIREMENT_OVERRIDES
    )
    stdout, stderr, status = validate_temp_dispatch(dispatch_path)
    assert status.success?, [stdout, stderr].join("\n")

    rows = document.dig("launch", "requirement_manifest").select do |row|
      SEQUENCE_REQUIREMENT_OVERRIDES.key?(row.fetch("category"))
    end
    rows.each do |row|
      line = dispatch_fixture_requirement_projection_line(row)
      expected_heading = case row.fetch("category")
                         when "founder" then "## 03 Current Creative Job"
                         when "quality" then "## 09 Quality Proof"
                         else "## 07 Required Work"
                         end
      assert_equal 1, document.dig("launch", "compiled_launch_prompt", "rendered_prompt").lines.count { |entry| entry.chomp == line }
      assert_includes ddc_prompt_block(document.dig("launch", "compiled_launch_prompt", "rendered_prompt"), expected_heading), line

      ddc_projection_mutations(document, line, expected_heading).each do |mutation, mutated|
        write_temp_dispatch(dispatch_path, mutated)
        mutation_stdout, mutation_stderr, mutation_status = validate_temp_dispatch(dispatch_path)
        refute mutation_status.success?, "#{row.fetch('requirement_id')} #{mutation}: #{mutation_stdout}\n#{mutation_stderr}"
        assert_match(/exact-project requirement|unexpected or non-exact requirement projection|must be in block/, [mutation_stdout, mutation_stderr].join("\n"), "#{row.fetch('requirement_id')} #{mutation}")
      end
      write_temp_dispatch(dispatch_path, document)
    end
  end

  def test_01_identity_adoption_contextual_hold_receipt_blocks_promotion_for_generic_or_face_forcing_prose
    variants = {
      "GENERIC" => {
        artifact_text: "official_core_id: C01\nidentity_when_visible: preserve identity\n",
        judgment: "HOLD: the adopted 01 identity prose is generic and does not preserve the exact actually visible current-title clothing, styling, silhouette, face, or member-specific cues."
      },
      "FACE_FORCING" => {
        artifact_text: "official_core_id: C01\nidentity_when_visible: every cut must show a frontal readable face and front gaze\n",
        judgment: "HOLD: the adopted 01 identity prose forces frontal face readability and front gaze instead of honoring the selected scene visibility intent."
      }
    }

    variants.each do |label, variant|
      overrides = {
        "quality" => {
          "requirement_id" => "QUALITY-01-IDENTITY-ADOPTION",
          "affected_scope" => "CDD contextually reviews the exact returned 01 adoption and Official Core bytes. Every actually visible current-title cue remains exact, while frontal/readable face or front gaze is never forced; genericized or face-forcing prose is HOLD, not promotion.",
          "director_semantic_review_required" => true
        }
      }
      document, dispatch_path = build_promoted_dispatch(
        dispatch_id: "IDENTITY_#{label}_001",
        stage_id: "mv_performance_direction",
        profile_id: "pre_02a_development_block_fp",
        checkpoint_id: "section_01_core_direction",
        artifact_text: variant.fetch(:artifact_text),
        requirement_overrides: overrides
      )
      quality_result = document.dig("director_review", "requirement_results").find do |row|
        row.fetch("requirement_id") == "QUALITY-01-IDENTITY-ADOPTION"
      end
      quality_result["result"] = "hold"
      quality_result["judgment"] = variant.fetch(:judgment)
      exact_output = document.dig("runtime_return", "outputs", 0)
      assert_equal exact_output.fetch("path"), quality_result.fetch("evidence_locator")
      assert_equal exact_output.fetch("sha256"), quality_result.fetch("evidence_sha256")
      write_temp_dispatch(dispatch_path, document)

      stdout, stderr, status = validate_temp_dispatch(dispatch_path)
      refute status.success?, "#{label}: #{stdout}\n#{stderr}"
      detail = [stdout, stderr].join("\n")
      assert_includes detail, "director disposition accept requires every requirement result to pass", label
      refute_match(/evidence.*SHA-256 is stale/i, detail, label)
    end
  end

  def test_explicit_graph_shadow_route_has_startup_consumer_parity_without_changing_legacy_default
    copy_graph_startup_closure
    route = graph_role_context_route
    founder_message = "Graph shadow pilot에서 현재 P1 과제만 검토해. 기본 writer는 바꾸지 마."
    prepared = prepare_overall_read_gate(
      "action" => "prepare_overall_read_gate",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "role_context_route" => route
    )
    assert_equal "graph_v2", prepared.dig("role_context_pack", "activation_binding", "writer")
    assert_equal GRAPH_PROFILE_REGISTRY_RELATIVE, prepared.dig("profile_registry", "path")
    assert_equal "overall_director", prepared.dig("selected_profile", "profile_id")

    overall = compile_overall_launch(
      "action" => "compile_overall_launch",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "assistant_output" => envelope("idol_startup_delta", startup_delta(prepared, founder_message)),
      "role_context_route" => route
    )
    assert_equal "compiled", overall.fetch("status")
    assert_equal "graph_v2", overall.dig("role_context_pack", "activation_binding", "writer")

    cdd = compile_cdd_launch(
      "action" => "compile_cdd_launch",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "assistant_output" => envelope("idol_cdd_startup_delta", valid_cdd_delta(founder_message)),
      "role_context_route" => route
    )
    assert_equal "compiled", cdd.fetch("status")
    assert_equal "planning_cdd_p1", cdd.dig("selected_profile", "profile_id")
    assert_equal "p1_story_audience_lead", cdd.dig("selected_profile", "checkpoint_id")
    assert_equal "frontier_director", cdd.dig("role_context_pack", "provider_binding", "logical_profile_alias")
    assert_equal "creative_route_discovery", cdd.dig("role_context_pack", "identity", "stage_id")

    receipt = {
      "status" => "ready",
      "role_context_receipt" => receipt_for(cdd.fetch("role_context_pack")),
      "hold_reasons" => []
    }
    validated = validate_cdd_return(
      "action" => "validate_cdd_return",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "assistant_output" => envelope("idol_cdd_startup_return", receipt),
      "role_context_route" => route
    )
    assert_equal "validated", validated.fetch("status")
    assert_equal cdd.dig("role_context_pack", "projection", "pack_digest"), validated.dig("role_context_pack", "projection", "pack_digest")
    Tempfile.create(["idol-graph-startup-admission", ".json"]) do |file|
      file.write(JSON.pretty_generate(validated))
      file.flush
      _stdout, stderr, status = Open3.capture3(
        REAL_ROOT.join("scripts/idol-video-python").to_s,
        REAL_ROOT.join("scripts/validate_json_schema.py").to_s,
        REAL_ROOT.join("schemas/harness-startup-admission.schema.json").to_s,
        file.path,
        chdir: REAL_ROOT.to_s
      )
      assert status.success?, stderr
    end

    legacy = prepare_read_gate(founder_message)
    assert_equal PROFILE_REGISTRY_RELATIVE, legacy.dig("profile_registry", "path")
    assert_equal "legacy_pinned", legacy.dig("role_context_pack", "activation_binding", "writer")

    missing_receipt = Marshal.load(Marshal.dump(route))
    missing_receipt["switch_receipt"] = nil
    error = assert_raises(StartupAdmissionError) do
      prepare_overall_read_gate(
        "action" => "prepare_overall_read_gate",
        "run_binding" => run_binding,
        "founder_message" => founder_message,
        "role_context_route" => missing_receipt
      )
    end
    assert_includes error.message, "verified default-switch receipt"
  end

  def test_graph_startup_pack_routes_p2_and_p3_to_p1_while_p1_returns_to_overall_and_overall_to_founder
    copy_graph_startup_closure
    routes = {
      "planning_cdd_p1" => ["creative_route_discovery", "p1_story_audience_lead", [], nil, {"role" => "overall_director"}],
      "planning_cdd_p2" => ["creative_route_discovery", "p2_visual_reference_development", [], nil, {"role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}],
      "planning_cdd_p3_ci" => ["front_planning_integration", "p3_section_kinetic_architecture", %w[S01 S02], "C1", {"role" => "planning_cdd_p1", "return_route" => "planning_cdd_p1_exact_link"}]
    }
    routes.each do |profile_id, (stage_id, checkpoint_id, section_ids, cohort_id, expected_recipient)|
      route = graph_role_context_route(
        profile_id: profile_id,
        stage_id: stage_id,
        checkpoint_id: checkpoint_id,
        section_ids: section_ids,
        section_cohort_id: cohort_id
      )
      profile = attach_role_context_pack!(
        load_profile!("creative_development_director", role_context_route: route),
        verify_run_binding!("run_binding" => run_binding),
        role_context_route: route
      )
      pack = profile.fetch("role_context_pack")
      assert_equal expected_recipient, pack.dig("current_node", "return_recipient"), profile_id
      assert_equal expected_recipient.fetch("role"), pack.dig("authority_binding", "promotion_owner"), profile_id
    end

    overall_route = graph_role_context_route
    overall = prepare_overall_read_gate(
      "action" => "prepare_overall_read_gate",
      "run_binding" => run_binding,
      "founder_message" => "Graph startup return topology를 확인해.",
      "role_context_route" => overall_route
    )
    assert_equal({"role" => "founder"}, overall.dig("role_context_pack", "current_node", "return_recipient"))
  end

  private

  def graph_role_context_route(profile_id: "planning_cdd_p1", stage_id: "creative_route_discovery", checkpoint_id: "p1_story_audience_lead", section_ids: [], section_cohort_id: nil)
    {
      "writer" => "graph_v2",
      "run_class" => "new_run",
      "stage_id" => stage_id,
      "cdd_profile_id" => profile_id,
      "cdd_checkpoint_id" => checkpoint_id,
      "section_ids" => section_ids,
      "section_cohort_id" => section_cohort_id,
      "switch_receipt" => {
        "receipt_id" => "GRAPH_SWITCH_STARTUP_FIXTURE_001",
        "founder_authority" => "founder",
        "graph_revision" => "idol-graph-skill-load-profiles.v1",
        "switch_boundary" => "new_runs_only_after_verified_receipt",
        "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(@temporary),
        "verified_at" => "2026-09-03T00:00:00+09:00"
      }
    }
  end

  def copy_graph_startup_closure
    registry_path = REAL_ROOT.join(GRAPH_PROFILE_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_path.read, aliases: true)
    routing = YAML.safe_load(REAL_ROOT.join(IdolRoleContextPack::GRAPH_ROUTING_REGISTRY_RELATIVE).read, aliases: true)
    paths = Array(registry["skill_bindings"]).map { |row| row.fetch("path") }
    paths.concat(Array(registry["read_bindings"]).map { |row| row.fetch("path") })
    paths.concat(Array(routing.dig("writer_boundary", "active_graph_surfaces")))
    paths.concat([
      IdolRoleContextPack::GRAPH_PROJECTION_REGISTRY_RELATIVE,
      IdolRoleContextPack::GRAPH_ROUTING_REGISTRY_RELATIVE
    ])
    paths.uniq.each do |relative|
      destination = @temporary.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end
    Array(registry["skill_bindings"]).each do |row|
      row["sha256"] = Digest::SHA256.file(@temporary.join(row.fetch("path"))).hexdigest
    end
    Array(registry["read_bindings"]).each do |row|
      row["sha256"] = Digest::SHA256.file(@temporary.join(row.fetch("path"))).hexdigest
    end
    @temporary.join(GRAPH_PROFILE_REGISTRY_RELATIVE).write(YAML.dump(registry))
  end

  def dispatch_fixture_root
    @temporary
  end

  def prompt_block(prompt, index)
    heading = "#{TWELVE_HEADINGS.fetch(index)}\n"
    start = prompt.index(heading)
    raise "missing prompt heading #{heading.inspect}" unless start

    body_start = start + heading.length
    return prompt[body_start..] if index == TWELVE_HEADINGS.length - 1

    next_heading = "\n\n#{TWELVE_HEADINGS.fetch(index + 1)}\n"
    finish = prompt.index(next_heading, body_start)
    raise "missing next prompt heading #{next_heading.inspect}" unless finish

    prompt[body_start...finish]
  end

  def startup_priority_mutations(prompt, clause, block_index)
    changed = "CHANGED#{clause[1..]}"
    wrong_block_index = block_index == 6 ? 8 : 6
    without_clause = prompt.sub(clause, "")
    {
      "missing" => without_clause,
      "changed" => prompt.sub(clause, changed),
      "duplicate" => prompt.sub(clause, "#{clause}\n#{clause}"),
      "wrong_block" => insert_after_startup_heading(without_clause, wrong_block_index, clause)
    }
  end

  def insert_after_startup_heading(prompt, block_index, value)
    heading = "#{TWELVE_HEADINGS.fetch(block_index)}\n"
    prompt.sub(heading, "#{heading}#{value}\n")
  end

  def build_promoted_dispatch(dispatch_id:, stage_id:, profile_id:, checkpoint_id:, artifact_text:, requirement_overrides:)
    run_path = @temporary.join("runs", "test-album", "test-title", dispatch_id)
    artifact_path = run_path.join("work", "fixture-output.yaml")
    artifact_path.dirname.mkpath
    artifact_path.write(artifact_text)
    document = dispatch_fixture_promoted_document(
      run_path: run_path,
      dispatch_id: dispatch_id,
      stage_id: stage_id,
      artifact_path: artifact_path,
      owner_role: "department_worker",
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      assigned_owner: "fixture-department-worker",
      director_owner: "fixture-cdd",
      promotion_owner: "fixture-overall",
      recipient_role: "creative_development_director",
      requirement_overrides_by_category: requirement_overrides
    )
    dispatch_path = run_path.join("work", "department-dispatches", "#{dispatch_id}.yaml")
    write_temp_dispatch(dispatch_path, document)
    [document, dispatch_path]
  end

  def write_temp_dispatch(path, document)
    path.dirname.mkpath
    path.write(YAML.dump(document))
  end

  def validate_temp_dispatch(path)
    relative = path.relative_path_from(@temporary).to_s
    Open3.capture3(
      RbConfig.ruby,
      @temporary.join(DDC_VALIDATOR_RELATIVE).to_s,
      "--json",
      relative,
      chdir: @temporary.to_s
    )
  end

  def ddc_projection_mutations(document, line, expected_heading)
    prompt = document.dig("launch", "compiled_launch_prompt", "rendered_prompt")
    wrong_heading = expected_heading == "## 07 Required Work" ? "## 03 Current Creative Job" : "## 07 Required Work"
    {
      "missing" => prompt.lines.reject { |entry| entry.chomp == line }.join,
      "changed" => prompt.sub(line, "CHANGED#{line[1..]}"),
      "duplicate" => prompt.sub(line, "#{line}\n#{line}"),
      "wrong_block" => relocate_ddc_line(prompt, line, wrong_heading)
    }.transform_values do |mutated_prompt|
      mutated = Marshal.load(Marshal.dump(document))
      compiled = mutated.dig("launch", "compiled_launch_prompt")
      compiled["rendered_prompt"] = mutated_prompt
      compiled["rendered_prompt_sha256"] = Digest::SHA256.hexdigest(mutated_prompt)
      input_basis = {
        "lineage" => mutated.fetch("lineage"),
        "review_submission" => mutated.fetch("review_submission"),
        "launch" => mutated.fetch("launch")
      }
      mutated.dig("runtime_return", "input_digest")["sha256"] = dispatch_fixture_structured_sha(input_basis)
      mutated
    end
  end

  def relocate_ddc_line(prompt, line, target_heading)
    lines = prompt.split("\n", -1)
    source_index = lines.index(line)
    raise "missing DDC projection line" unless source_index
    lines.delete_at(source_index)
    heading_index = lines.index(target_heading)
    raise "missing DDC target heading" unless heading_index
    lines.insert(heading_index + 1, line)
    lines.join("\n")
  end

  def ddc_prompt_block(prompt, heading)
    headings = DepartmentDispatchProfileFixture::LAUNCH_BLOCK_HEADINGS
    index = headings.index(heading)
    body = prompt.split("#{heading}\n", 2).fetch(1)
    return body if index == headings.length - 1
    body.split("\n\n#{headings.fetch(index + 1)}", 2).fetch(0)
  end

  def valid_cdd_delta(founder_message)
    {
      "status" => "ready",
      "founder_request_binding" => founder_request_binding(founder_message),
      "current_creative_job" => "현재 우선사항을 작업 가능한 범위로 좁힌다.",
      "exact_scope" => "현재 CDD 과제 라우팅",
      "non_scope" => "새 역할·Stage·창작 권한",
      "unaffected_truth" => ["기존 소유권", "기존 단계"],
      "required_work" => "각 우선사항을 독립 requirement row로 분해한다.",
      "quality_proof" => "worker fulfillment와 CDD result가 각 row를 닫는다.",
      "unresolved_decisions" => ["현재 작업자 배치"],
      "hold_reasons" => []
    }
  end

  def replace_constant(name, value)
    Object.send(:remove_const, name) if Object.const_defined?(name)
    Object.const_set(name, value)
  end

  def copy_profile_closure
    registry_source = REAL_ROOT.join(PROFILE_REGISTRY_RELATIVE)
    registry = YAML.safe_load(registry_source.read, aliases: true)
    profiles = Array(registry["profiles"]).select { |row| PROFILE_CHECKPOINTS.key?(row["profile_id"]) }
    skill_map = Array(registry["skill_bindings"]).to_h { |row| [row["binding_id"], row] }
    read_map = Array(registry["read_bindings"]).to_h { |row| [row["binding_id"], row] }
    selected_checkpoints = profiles.map do |profile|
      checkpoint_id = PROFILE_CHECKPOINTS.fetch(profile.fetch("profile_id"))
      checkpoint = Array(profile.dig("phase_load", "checkpoints")).find { |row| row["checkpoint_id"] == checkpoint_id }
      raise "missing test profile checkpoint #{profile.fetch('profile_id')}.#{checkpoint_id}" unless checkpoint
      checkpoint
    end
    selected_skill_ids = selected_checkpoints.flat_map { |checkpoint| Array(checkpoint["required_skill_ids"]) }.uniq
    selected_read_ids = selected_checkpoints.flat_map { |checkpoint| Array(checkpoint["required_read_ids"]) }.uniq
    paths = selected_checkpoints.flat_map do |checkpoint|
      Array(checkpoint["required_skill_ids"]).map { |id| skill_map.fetch(id).fetch("path") } +
        Array(checkpoint["required_read_ids"]).map { |id| read_map.fetch(id).fetch("path") }
    end.uniq
    paths.concat(
      %w[
        scripts/validate_department_dispatch.rb
        scripts/lib/idol_checkpoint_closure_catalog.rb
        scripts/lib/idol_helper_consumption_receipts.rb
        scripts/lib/idol_run_followup_sidecar.rb
        scripts/idol_department_transport_refresh.rb
        scripts/validate_json_schema.py
        scripts/idol-video-python
        schemas/department-dispatch.schema.json
        schemas/department-transport-refresh.schema.json
        automation/harness-execution-contract.yaml
        automation/harness-checkpoint-closure-catalog.yaml
        automation/harness-role-context-projection.yaml
        automation/harness-provider-profile-registry.yaml
        automation/providers/grok-build-profiles.yaml
        skills/idol-orchestrator/references/provider-neutral-studio-kernel.md
      ]
    )
    paths.uniq!
    paths.each do |relative|
      destination = @temporary.join(relative)
      destination.dirname.mkpath
      FileUtils.cp(REAL_ROOT.join(relative), destination)
    end
    FileUtils.ln_s(REAL_ROOT.join(".venv-video"), @temporary.join(".venv-video"))
    Array(registry["skill_bindings"]).each do |row|
      next unless selected_skill_ids.include?(row["binding_id"])

      row["sha256"] = Digest::SHA256.file(REAL_ROOT.join(row.fetch("path"))).hexdigest
    end
    Array(registry["read_bindings"]).each do |row|
      next unless selected_read_ids.include?(row["binding_id"])

      row["sha256"] = Digest::SHA256.file(REAL_ROOT.join(row.fetch("path"))).hexdigest
    end
    destination = @temporary.join(PROFILE_REGISTRY_RELATIVE)
    destination.dirname.mkpath
    destination.write(YAML.dump(registry))
  end

  def prepare_run
    run_path = @temporary.join(RUN_ROOT)
    run_path.join("work/front_planning_integration").mkpath
    run_path.join("run-manifest.yaml").write(
      YAML.dump(
        "schema_version" => "idol-run-manifest.v1",
        "status" => "active",
        "canonical_run_root" => RUN_ROOT
      )
    )
    @plan_path = "#{RUN_ROOT}/research/front-planning-v1.md"
    @canvas_path = "#{RUN_ROOT}/work/front_planning_integration/canvas-state.json"
    @temporary.join(@plan_path).dirname.mkpath
    @temporary.join(@plan_path).write("# Test plan\n")
    @temporary.join(@canvas_path).write("{\"schema_version\":\"test\"}\n")
  end

  def run_binding
    {
      "run_root" => RUN_ROOT,
      "plan" => {"path" => @plan_path, "sha256" => Digest::SHA256.file(@temporary.join(@plan_path)).hexdigest},
      "canvas" => {"path" => @canvas_path, "sha256" => Digest::SHA256.file(@temporary.join(@canvas_path)).hexdigest},
      "founder_epoch" => 3,
      "active_owner_role" => "overall_director"
    }
  end

  def prepare_read_gate(founder_message)
    prepare_overall_read_gate(
      "action" => "prepare_overall_read_gate",
      "run_binding" => run_binding,
      "founder_message" => founder_message
    )
  end

  def compile_overall(founder_message, assistant_output)
    compile_overall_launch(
      "action" => "compile_overall_launch",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "assistant_output" => assistant_output
    )
  end

  def compile_cdd(founder_message, assistant_output)
    compile_cdd_launch(
      "action" => "compile_cdd_launch",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "assistant_output" => assistant_output
    )
  end

  def validate_cdd(founder_message, assistant_output)
    validate_cdd_return(
      "action" => "validate_cdd_return",
      "run_binding" => run_binding,
      "founder_message" => founder_message,
      "assistant_output" => assistant_output
    )
  end

  def receipt_for(pack)
    {
      "schema_version" => pack.fetch("schema_version"),
      "pack_id" => pack.fetch("pack_id"),
      "pack_digest" => pack.dig("projection", "pack_digest"),
      "source_set_sha256" => pack.dig("projection", "source_set_sha256"),
      "provider_profile_id" => pack.dig("provider_binding", "provider_profile_id"),
      "status" => "applied"
    }
  end

  def startup_delta(packet, founder_message)
    {
      "status" => "ready",
      "role_context_receipt" => receipt_for(packet.fetch("role_context_pack")),
      "founder_request_binding" => founder_request_binding(founder_message),
      "run_stage_lock_summary" => "현재 런은 Front Planning에 있으며 기존 단계 순서를 유지한다.",
      "current_creative_job" => "현재 Founder 방향을 읽고 다음 합법 owner에게 정확히 라우팅한다.",
      "exact_scope" => "현재 런의 시작 판단과 Front Planning route",
      "non_scope" => "창작값 자동 작성, downstream 자동 진입, 유료·외부 작업",
      "unaffected_truth" => ["기존 Founder lock", "현재 단계 순서"],
      "next_owner_route" => "creative_development_director",
      "required_work" => "현재 증거를 검토하고 CDD에 전달할 정확한 과제 Delta를 작성한다.",
      "quality_proof" => "현재 곡·타깃·화면 결과와 연결된 근거로 route를 설명한다.",
      "unresolved_decisions" => ["Direction Synthesis 기본 후보 선택"],
      "hold_reasons" => []
    }
  end

  def envelope(marker, payload)
    "<#{marker}>#{JSON.generate(payload)}</#{marker}>"
  end
end
