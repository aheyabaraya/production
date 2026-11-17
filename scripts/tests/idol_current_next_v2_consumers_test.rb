# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "yaml"
require_relative "../lib/idol_current_next_v2"

class IdolCurrentNextV2ConsumersTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  RECORD = ROOT.join("scripts", "idol_harness_record_founder_decision.rb")
  APPLY = ROOT.join("scripts", "idol_harness_apply_founder_decision.rb")
  VALIDATE = ROOT.join("scripts", "validate_03v_front_playback_gate.rb")
  LEGACY_KEYS = %w[source_next_unit source_founder_gate source_action_queue].freeze

  def setup
    @run = ROOT.join("runs", "harness-test", "current-next-consumer", "RUN_#{SecureRandom.hex(4).upcase}")
    @work = @run.join("work")
    @work.mkpath
    @run_rel = @run.relative_path_from(ROOT).to_s
    write_fixture
  end

  def teardown
    FileUtils.remove_entry(@run) if @run.directory?
  end

  def test_active_v2_loads_exact_ddi_row_and_typed_legacy_join
    context = load_context
    legacy = IdolCurrentNextV2.require_03v_legacy_gate!(context)

    assert_equal "next_action", context.dig("selection", "kind")
    assert_equal "/next_actions/0", context.dig("selection", "json_pointer")
    assert_equal "03V_DISPATCH", context.dig("selection", "dispatch_id")
    assert_equal "harness-next-unit.v1", legacy.dig("next_unit", "schema_version")
    assert_equal "03v_front_playback_generation", legacy.dig("founder_gate", "gate_type")
  end

  def test_active_v1_is_rejected
    @current_next.write(YAML.dump("schema_version" => "harness-current-next.v1", "run" => @run_rel))

    error = assert_raises(IdolCurrentNextV2::Error) { load_context }
    assert_includes error.message, "v1 is legacy evidence only"
  end

  def test_03v_validator_rejects_v1_before_legacy_gate_checks
    @current_next.write(YAML.dump("schema_version" => "harness-current-next.v1", "run" => @run_rel))
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      VALIDATE.to_s,
      @run_rel,
      "--action-queue", relative(@action_queue),
      "--next-unit", relative(@next_unit),
      "--founder-gate", relative(@founder_gate),
      "--current-next", relative(@current_next),
      chdir: ROOT.to_s
    )

    refute status.success?
    assert_includes stderr, "v1 is legacy evidence only"
  end

  def test_founder_decision_apply_rejects_v1_before_writes
    @current_next.write(YAML.dump("schema_version" => "harness-current-next.v1", "run" => @run_rel))
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      APPLY.to_s,
      @run_rel,
      "--decision", "hold_front_gate",
      "--current-next", relative(@current_next),
      "--write",
      chdir: ROOT.to_s
    )

    refute status.success?
    assert_includes stderr, "v1 is legacy evidence only"
  end

  def test_open_hold_cannot_authorize_03v_continuation
    write_fixture(selection_kind: :open_hold)

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "HOLD and review_queue rows cannot authorize continuation"
  end

  def test_review_queue_cannot_authorize_03v_continuation
    write_fixture(selection_kind: :review_queue)

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "HOLD and review_queue rows cannot authorize continuation"
  end

  def test_unrelated_dispatch_sources_cannot_borrow_legacy_evidence
    write_fixture(omit_dispatch_source: "source_founder_gate")

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "exactly one legacy_harness_founder_gate_v1 binding"
  end

  def test_wrong_typed_source_id_cannot_authorize_legacy_evidence
    write_fixture(wrong_source_id: "source_action_queue")

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "exactly one legacy_harness_action_queue_v1 binding"
  end

  def test_non_v8_department_dispatch_cannot_authorize_legacy_evidence
    write_fixture(dispatch_schema: "idol-department-dispatch.v7")

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "schema must be idol-department-dispatch.v8"
  end

  def test_non_advance_action_code_cannot_authorize_03v_continuation
    write_fixture(action_code: "director_review")

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "does not authorize 03V continuation"
  end

  def test_unrelated_stage_scope_cannot_authorize_03v_continuation
    write_fixture(stage_id: "edit_assembly_playback_qc")

    error = assert_raises(IdolCurrentNextV2::Error) do
      IdolCurrentNextV2.require_03v_legacy_gate!(load_context)
    end
    assert_includes error.message, "does not authorize a 03V operation"
  end

  def test_stale_legacy_evidence_hash_is_rejected_before_meaning_is_read
    @founder_gate.open("a") { |file| file.puts("tampered: true") }

    error = assert_raises(IdolCurrentNextV2::Error) { load_context }
    assert_includes error.message, "legacy_evidence source_founder_gate SHA-256 is stale"
  end

  def test_founder_decision_recorder_reads_gate_only_through_v2_adapter
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      RECORD.to_s,
      @run_rel,
      "--decision", "hold_front_gate",
      "--current-next", relative(@current_next),
      chdir: ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    payload = YAML.safe_load(stdout, permitted_classes: [], permitted_symbols: [], aliases: true)
    assert_equal relative(@founder_gate), payload["source_founder_gate"]
    assert_equal relative(@next_unit), payload["source_next_unit"]
    assert_equal relative(@action_queue), payload["source_action_queue"]
    assert_equal "03v_front_playback_generation", payload["gate_type"]
    assert_equal "hold_front_gate", payload["decision_id"]
  end

  private

  def relative(path)
    Pathname.new(path).relative_path_from(ROOT).to_s
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def write_yaml(path, document)
    path.dirname.mkpath
    path.write(YAML.dump(document), encoding: "utf-8")
  end

  def artifact_binding(path, role)
    {"path" => relative(path), "sha256" => sha(path), "role" => role}
  end

  def legacy_documents
    action_queue = {
      "schema_version" => "harness-action-queue.v1",
      "run" => @run_rel,
      "active_founder_gate_decision" => {},
      "queues" => []
    }
    next_unit = {
      "schema_version" => "harness-next-unit.v1",
      "run" => @run_rel,
      "selected_unit_id" => "front_03v_playback_gate:S01-S01"
    }
    founder_gate = {
      "schema_version" => "harness-founder-gate.v1",
      "run" => @run_rel,
      "gate_id" => "front_03v_playback_gate_S01-S01",
      "gate_type" => "03v_front_playback_generation",
      "section_range" => "S01-S01",
      "section_ids" => ["S01"],
      "packet_count" => 1,
      "current_local_status" => {
        "next_local_section" => "",
        "local_ready_sections" => ["S01"],
        "remaining_check" => "generation_playback_probe",
        "next_local_continuation_allowed" => false
      },
      "allowed_decisions" => [{
        "id" => "hold_front_gate",
        "label" => "Hold this front gate.",
        "requires_explicit_approval" => false,
        "allows_paid_generation" => false,
        "allows_external_execution" => false,
        "continues_local_qa" => false,
        "marks_section_qa_pass" => false,
        "next_action" => "Keep the gate on HOLD."
      }],
      "automation_boundaries" => ["Evidence only."],
      "forbidden_actions" => ["Do not infer approval."]
    }
    [action_queue, next_unit, founder_gate]
  end

  def write_fixture(
    selection_kind: :next_action,
    omit_dispatch_source: nil,
    wrong_source_id: nil,
    dispatch_schema: "idol-department-dispatch.v8",
    action_code: "advance_dispatch",
    stage_id: "video_playback_review"
  )
    @action_queue = @work.join("legacy-action-queue.yaml")
    @next_unit = @work.join("legacy-next-unit.yaml")
    @founder_gate = @work.join("legacy-founder-gate.yaml")
    action_queue, next_unit, founder_gate = legacy_documents
    write_yaml(@action_queue, action_queue)
    next_unit["source_action_queue"] = relative(@action_queue)
    write_yaml(@next_unit, next_unit)
    founder_gate["source_next_unit"] = relative(@next_unit)
    founder_gate["source_action_queue"] = relative(@action_queue)
    write_yaml(@founder_gate, founder_gate)

    legacy_paths = {
      "source_next_unit" => @next_unit,
      "source_founder_gate" => @founder_gate,
      "source_action_queue" => @action_queue
    }
    sources = LEGACY_KEYS.each_with_object([]) do |key, rows|
      next if key == omit_dispatch_source

      role = IdolCurrentNextV2::LEGACY_ROLES.fetch(key)
      rows << {
        "source_id" => key == wrong_source_id ? "wrong_#{role}" : role,
        "path" => relative(legacy_paths.fetch(key)),
        "sha256" => sha(legacy_paths.fetch(key)),
        "purpose" => "Exact #{role} evidence for this 03V dispatch."
      }
    end
    @dispatch = @work.join("department-dispatch.yaml")
    write_yaml(@dispatch, {
      "schema_version" => dispatch_schema,
      "artifact_type" => "department_dispatch",
      "dispatch_id" => "03V_DISPATCH",
      "run" => @run_rel,
      "launch" => {"sources" => sources}
    })
    dispatch_pointer = {"path" => relative(@dispatch), "sha256" => sha(@dispatch)}
    scope = {
      "scope_kind" => "section",
      "stage_id" => stage_id,
      "section_ids" => ["S01"],
      "chunk_ids" => []
    }
    dispatch_row = {
      "dispatch_id" => "03V_DISPATCH",
      "scope" => {
        "stage_id" => stage_id,
        "section_ids" => ["S01"]
      },
      "lifecycle" => {"current_state" => "prepared"},
      "dispatch_pointer" => dispatch_pointer,
      "next_action_ids" => ["NEXT_03V_DISPATCH"]
    }
    holds = []
    review_items = []
    actions = [{
      "next_action_id" => "NEXT_03V_DISPATCH",
      "scope" => scope,
      "action_code" => action_code,
      "owner" => "creative_development_director",
      "state" => "ready",
      "dependency_pointers" => [dispatch_pointer]
    }]
    if selection_kind == :open_hold
      holds << {
        "hold_id" => "HOLD_03V_DISPATCH",
        "scope" => scope.merge("scope_kind" => "hold_view"),
        "dispatch_id" => "03V_DISPATCH",
        "owner" => "creative_development_director",
        "evidence_pointers" => [dispatch_pointer],
        "state" => "open"
      }
    elsif selection_kind == :review_queue
      review_items << {
        "dispatch_id" => "03V_DISPATCH",
        "director_owner" => "creative_development_director",
        "dependency_rank" => 0,
        "returned_at" => "2026-08-14T00:00:00+09:00",
        "queue_state" => "queued",
        "blocks_next" => true
      }
    end
    source_set_sha = "a" * 64
    ddi = {
      "schema_version" => "idol-director-dispatch-index.v4",
      "run" => @run_rel,
      "source_set_sha256" => source_set_sha,
      "source_set_digest" => {"sha256" => source_set_sha},
      "dispatch_source_set" => {"entry_count" => 1},
      "dispatches" => [dispatch_row],
      "review_queue" => {
        "selection_order" => "dependency_rank_then_returned_at_then_dispatch_id",
        "items" => review_items
      },
      "current_heads" => [],
      "holds" => holds,
      "next_actions" => actions
    }
    @ddi = @work.join("director-dispatch-index.yaml")
    write_yaml(@ddi, ddi)
    selection = IdolCurrentNextV2.expected_selection(ddi)
    current_next = {
      "schema_version" => "harness-current-next.v2",
      "artifact_type" => "harness_current_next",
      "run" => @run_rel,
      "album_key" => "harness-test",
      "title_key" => "current-next-consumer",
      "status" => IdolCurrentNextV2.expected_status(selection),
      "owner" => "creative_development_director",
      "frontier_binding" => {
        "director_dispatch_index" => artifact_binding(@ddi, "director_dispatch_index_v4"),
        "source_set_sha256" => source_set_sha,
        "selection" => selection,
        "canonical_heads" => {"resolution" => "not_yet_promoted", "items" => []}
      },
      "legacy_evidence" => {
        "selection_authority" => false,
        "source_next_unit" => artifact_binding(@next_unit, "legacy_harness_next_unit_v1"),
        "source_founder_gate" => artifact_binding(@founder_gate, "legacy_harness_founder_gate_v1"),
        "source_action_queue" => artifact_binding(@action_queue, "legacy_harness_action_queue_v1")
      }
    }
    @current_next = @work.join("current-next.yaml")
    write_yaml(@current_next, current_next)
  end

  def load_context
    IdolCurrentNextV2.load_active(
      path: relative(@current_next),
      run: @run_rel,
      root: ROOT,
      require_actionable: true,
      require_legacy: LEGACY_KEYS
    )
  end
end
