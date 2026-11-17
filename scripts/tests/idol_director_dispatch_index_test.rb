# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "yaml"

require_relative "../idol_director_dispatch_index"
require_relative "support/department_dispatch_profile_fixture"

class IdolDirectorDispatchIndexTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_director_dispatch_index.rb")

  def setup
    @run = ROOT.join("runs", "harness-test", "director-index", "RUN_#{SecureRandom.hex(4).upcase}")
    @dispatch_id = "DISPATCH_#{SecureRandom.hex(3).upcase}"
    @source = @run.join("research", "source.yaml")
    @output = @run.join("research", "result.yaml")
    @dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    @run.join("research").mkpath
    @dispatch.dirname.mkpath
    @source.write("selected: fixture\n")
    @output.write("result: fixture\n")
    write_dispatch
  end

  def teardown
    FileUtils.remove_entry(@run) if @run.directory?
    title = @run.parent
    title.rmdir if title.directory? && title.children.empty?
    album = title.parent
    album.rmdir if album.directory? && album.children.empty?
    root = album.parent
    root.rmdir if root.directory? && root.children.empty?
  end

  def test_build_validate_and_view_are_pointer_only_and_sorted
    stdout, stderr, status = cli("build", "--json", "--view", "stage:song_production_lock", @run.relative_path_from(ROOT).to_s)
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    index_path = ROOT.join(result.fetch("index"))
    assert_equal 1, result.fetch("dispatch_count")
    assert_equal 1, result.fetch("views").length
    view_path = ROOT.join(result.fetch("views").fetch(0))
    view_stdout, view_stderr, view_status = cli("validate", "--json", view_path.relative_path_from(ROOT).to_s)
    assert view_status.success?, [view_stdout, view_stderr].join("\n")

    stdout, stderr, status = cli("validate", "--json", index_path.relative_path_from(ROOT).to_s)
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout).fetch("status")

    index = YAML.safe_load(index_path.read, aliases: true)
    assert_equal "idol-director-dispatch-index.v4", index.fetch("schema_version")
    assert_equal index.fetch("source_set_sha256"), index.dig("source_set_digest", "sha256")
    assert_equal [@dispatch_id], index.fetch("dispatches").map { |row| row.fetch("dispatch_id") }
    assert_equal ["active_v8"], index.dig("dispatch_source_set", "entries").map { |row| row.fetch("classification") }
    head = index.fetch("current_heads").fetch(0)
    assert_match(/\AARTIFACT_[A-F0-9]{64}\z/, head.fetch("logical_artifact_id"))
    assert_equal "promotion.promoter", head.dig("owner_receipt", "source")
    assert_equal "promotion.decided_at", head.fetch("promotion_epoch_source")
    assert_nil head.fetch("supersedes_head_id")

    stdout, stderr, status = cli("boot-pack", "--json", index_path.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "generic boot-pack is retired"
    assert_includes stderr, "cdd-successor prepare"
  end

  def test_dispatch_source_set_hash_binds_current_and_legacy_without_projecting_legacy
    legacy_path = write_legacy_dispatch(
      dispatch_id: "LEGACY_PINNED_A01",
      stage_id: "front_planning_integration",
      artifact_path: @run.join("research", "legacy-evidence.yaml").relative_path_from(ROOT).to_s
    )

    source_set, _documents = IdolDirectorDispatchIndex.dispatch_source_set(@run)
    assert_equal "current", source_set.fetch("status")
    assert_equal 2, source_set.fetch("entry_count")
    assert_equal IdolDirectorDispatchIndex.digest_value(source_set.fetch("entries")), source_set.fetch("sha256")
    entries = source_set.fetch("entries").to_h { |row| [row.fetch("dispatch_id"), row] }
    assert_equal "active_v8", entries.fetch(@dispatch_id).fetch("classification")
    assert_equal "legacy_pinned", entries.fetch("LEGACY_PINNED_A01").fetch("classification")
    assert_equal sha(legacy_path), entries.fetch("LEGACY_PINNED_A01").dig("dispatch_pointer", "sha256")
    assert_equal false, entries.fetch("LEGACY_PINNED_A01").fetch("active_projection")
    assert_empty IdolDirectorDispatchIndex.admission_holds(source_set.fetch("entries"))
  end

  def test_legacy_only_build_emits_v4_hold_without_active_row_or_false_head
    @dispatch.delete
    write_legacy_dispatch(
      dispatch_id: "LEGACY_ONLY_A01",
      stage_id: "front_planning_integration",
      artifact_path: @run.join("research", "legacy-only.yaml").relative_path_from(ROOT).to_s
    )

    index, _pairs, _metadata = IdolDirectorDispatchIndex.build_index(
      @run,
      generated_at: "2026-08-14T00:00:00Z",
      validate_reference: false
    )
    assert_equal "idol-director-dispatch-index.v4", index.fetch("schema_version")
    assert_equal "hold", index.fetch("status")
    assert_empty index.fetch("dispatches")
    assert_empty index.fetch("current_heads")
    assert_equal ["legacy_pinned"], index.dig("dispatch_source_set", "entries").map { |row| row.fetch("classification") }
    assert index.fetch("holds").any? { |hold| hold.fetch("reason_code") == "legacy_dispatches_have_no_current_v8_projection" }

    existing_path = @run.join("work", "director-dispatch-index.yaml")
    existing_path.write(YAML.dump({"schema_version" => "idol-director-dispatch-index.v3", "source_set_sha256" => "0" * 64}))
    output, _views, rebuilt = IdolDirectorDispatchIndex.write_index(
      @run,
      generated_at: "2026-08-14T00:00:00Z",
      validate_reference: false
    )
    assert_equal existing_path, output
    assert_equal "idol-director-dispatch-index.v4", rebuilt.fetch("schema_version")
    assert_equal "hold", rebuilt.fetch("status")
    assert_empty rebuilt.fetch("current_heads")
  end

  def test_dispatch_source_set_holds_unsupported_schema_and_inventory_digest_changes
    unsupported = write_legacy_dispatch(
      dispatch_id: "UNSUPPORTED_A01",
      stage_id: "front_planning_integration",
      artifact_path: @run.join("research", "unsupported.yaml").relative_path_from(ROOT).to_s,
      schema_version: "idol-department-dispatch.v7"
    )
    before, _documents = IdolDirectorDispatchIndex.dispatch_source_set(@run)
    assert_equal "hold", before.fetch("status")
    entry = before.fetch("entries").find { |row| row.fetch("dispatch_id") == "UNSUPPORTED_A01" }
    assert_equal "held_incompatible", entry.fetch("classification")
    assert_equal sha(unsupported), entry.dig("dispatch_pointer", "sha256")
    assert IdolDirectorDispatchIndex.admission_holds(before.fetch("entries")).any? { |hold| hold.fetch("reason_code") == "unsupported_dispatch_schema_version" }

    write_legacy_dispatch(
      dispatch_id: "LATE_LEGACY_A01",
      stage_id: "front_planning_integration",
      artifact_path: @run.join("research", "late-legacy.yaml").relative_path_from(ROOT).to_s
    )
    after, _documents = IdolDirectorDispatchIndex.dispatch_source_set(@run)
    refute_equal before.fetch("sha256"), after.fetch("sha256")
    assert_equal before.fetch("entry_count") + 1, after.fetch("entry_count")
  end

  def test_overlapping_legacy_and_current_scope_holds_admission_and_current_head
    write_legacy_dispatch(
      dispatch_id: "LEGACY_OVERLAP_A01",
      stage_id: "song_production_lock",
      artifact_path: @output.relative_path_from(ROOT).to_s,
      assigned_owner: "different_legacy_owner"
    )
    source_set, _documents = IdolDirectorDispatchIndex.dispatch_source_set(@run)
    holds = IdolDirectorDispatchIndex.admission_holds(source_set.fetch("entries"))
    assert_equal "hold", source_set.fetch("status")
    assert holds.any? { |hold| hold.fetch("reason_code") == "dispatch_admission_scope_overlap" }, holds.inspect

    heads, head_holds = IdolDirectorDispatchIndex.head_projection([head_row("CURRENT_HEAD_A01")])
    assert_empty head_holds
    projected = IdolDirectorDispatchIndex.apply_admission_holds_to_heads(heads, holds)
    assert_empty projected.select { |head| head.fetch("state") == "current" }
    assert_equal ["held"], projected.map { |head| head.fetch("state") }.uniq
  end

  def test_active_v8_owner_scope_ambiguity_is_held_before_projection
    write_legacy_dispatch(
      dispatch_id: "ACTIVE_OWNER_CONFLICT_A01",
      stage_id: "song_production_lock",
      artifact_path: @output.relative_path_from(ROOT).to_s,
      schema_version: "idol-department-dispatch.v8",
      assigned_owner: "different_active_owner"
    )

    source_set, _documents = IdolDirectorDispatchIndex.dispatch_source_set(@run)
    assert_equal "hold", source_set.fetch("status")
    assert_empty source_set.fetch("entries").select { |entry| entry.fetch("classification") == "active_v8" }
    assert_equal ["held_incompatible"], source_set.fetch("entries").map { |entry| entry.fetch("classification") }.uniq
    assert source_set.fetch("entries").all? { |entry| entry.fetch("reason_code") == "dispatch_owner_scope_overlap" }
    holds = IdolDirectorDispatchIndex.admission_holds(source_set.fetch("entries"))
    assert holds.any? { |hold| hold.fetch("reason_code") == "dispatch_owner_scope_overlap" }, holds.inspect
  end

  def test_duplicate_canonical_heads_hold_without_verified_successor
    heads, holds = IdolDirectorDispatchIndex.head_projection([
      head_row("HEAD_ATTEMPT_A01", attempt_number: 1, successor_dispatch_id: "HEAD_ATTEMPT_B01", retirement_state: "replaced"),
      head_row("HEAD_ATTEMPT_B01", attempt_number: 2)
    ])

    assert_empty heads.select { |head| head.fetch("state") == "current" }
    assert_equal ["held"], heads.map { |head| head.fetch("state") }.uniq
    assert_equal ["ambiguous_hold"], heads.map { |head| head.fetch("supersession_state") }.uniq
    assert_equal 1, holds.length
    assert_equal "canonical_head_ambiguity", holds.fetch(0).fetch("reason_code")
  end

  def test_verified_two_way_successor_chain_selects_exactly_one_current_head
    predecessor = head_row(
      "HEAD_ATTEMPT_A01",
      attempt_number: 1,
      successor_dispatch_id: "HEAD_ATTEMPT_B01",
      retirement_state: "replaced"
    )
    successor = head_row(
      "HEAD_ATTEMPT_B01",
      attempt_number: 2,
      previous_attempt_id: "HEAD_ATTEMPT_A01"
    )
    heads, holds = IdolDirectorDispatchIndex.head_projection([predecessor, successor])

    assert_empty holds
    current = heads.select { |head| head.fetch("state") == "current" }
    stale = heads.select { |head| head.fetch("state") == "stale" }
    assert_equal 1, current.length
    assert_equal 1, stale.length
    assert_equal "HEAD_ATTEMPT_B01", current.fetch(0).fetch("source_dispatch_id")
    assert_equal stale.fetch(0).fetch("head_id"), current.fetch(0).fetch("supersedes_head_id")
    assert_equal current.fetch(0).fetch("head_id"), stale.fetch(0).fetch("superseded_by_head_id")
    assert_equal "verified_successor", current.fetch(0).fetch("supersession_state")
  end

  def test_resolved_head_shape_satisfies_v4_schema
    heads, head_holds = IdolDirectorDispatchIndex.head_projection([head_row("HEAD_SCHEMA_A01")])
    assert_empty head_holds
    @dispatch.delete
    write_legacy_dispatch(
      dispatch_id: "LEGACY_SCHEMA_CONTAINER_A01",
      stage_id: "front_planning_integration",
      artifact_path: @run.join("research", "legacy-schema-container.yaml").relative_path_from(ROOT).to_s
    )
    index, _pairs, _metadata = IdolDirectorDispatchIndex.build_index(
      @run,
      generated_at: "2026-08-14T00:00:00Z",
      validate_reference: false
    )
    index["current_heads"] = heads
    errors = IdolDirectorDispatchIndex.schema_errors_for_document(
      IdolDirectorDispatchIndex::INDEX_SCHEMA,
      index,
      "v4 head schema fixture"
    )
    assert_empty errors, errors.join("\n")
  end

  def test_validate_rejects_tampered_duplicate_current_head_projection
    _stdout, stderr, status = cli("build", "--json", @run.relative_path_from(ROOT).to_s)
    assert status.success?, stderr
    index_path = @run.join("work", "director-dispatch-index.yaml")
    document = YAML.safe_load(index_path.read, aliases: true)
    duplicate = Marshal.load(Marshal.dump(document.fetch("current_heads").fetch(0)))
    duplicate["head_id"] = "HEAD_TAMPERED_DUPLICATE"
    document.fetch("current_heads") << duplicate
    index_path.write(YAML.dump(document))

    stdout, _stderr, status = cli("validate", "--skip-reference-validation", index_path.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "current_heads must exact-project one current canonical head"
    assert_includes stdout, "more than one current canonical head"
  end

  def test_validate_rejects_stale_dispatch_pointer_and_digest
    _stdout, stderr, status = cli("build", "--json", @run.relative_path_from(ROOT).to_s)
    assert status.success?, stderr
    index_path = @run.join("work", "director-dispatch-index.yaml")
    document = YAML.safe_load(index_path.read, aliases: true)
    document["dispatches"][0]["input_digest"] = "0" * 64
    index_path.write(YAML.dump(document))
    stdout, _stderr, status = cli("validate", index_path.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "input_digest is stale"
  end

  def test_index_consumes_one_run_local_transport_refresh_without_worker_retry
    document = YAML.safe_load(@dispatch.read, aliases: true)
    document = JSON.parse(JSON.generate(document))
    original_submission = document.dig("review_submission", "submission_number")
    original_output_sha = sha(@output)
    document.dig("runtime_return", "wake_event", "output_pointers", 0)["sha256"] = "a" * 66
    runtime = document.fetch("runtime_return")
    result_basis = %w[
      work_started_at runtime_owner runtime_goal skill_revisions
      mechanical_compliance_receipt worker_fulfillment_claims output_inventory
      outputs hold_reasons wake_event
    ].to_h { |key| [key, runtime[key]] }
    runtime.dig("result_digest")["sha256"] = digest(result_basis)
    @dispatch.write(YAML.dump(document))

    receipt_path = IdolDepartmentTransportRefresh.write_receipt(
      @dispatch,
      owner: "fixture-mechanical-coordinator",
      created_at: "2026-08-13T00:00:00Z"
    )
    stdout, stderr, status = cli("build", "--json", @run.relative_path_from(ROOT).to_s)
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    index = YAML.safe_load(ROOT.join(result.fetch("index")).read, aliases: true)
    row = index.fetch("dispatches").first
    assert_equal receipt_path.relative_path_from(ROOT).to_s, row.dig("transport_refresh_receipt", "path")
    assert_equal original_submission, document.dig("review_submission", "submission_number")
    assert_equal original_output_sha, sha(@output)

    stdout, stderr, status = cli("validate", "--json", result.fetch("index"))
    assert status.success?, [stdout, stderr].join("\n")
  end

  def test_cdd_successor_boot_pack_requires_pointer_bound_read_only_preflight
    stdout, stderr, status = cli("build", "--json", @run.relative_path_from(ROOT).to_s)
    assert status.success?, [stdout, stderr].join("\n")
    checkpoint, source_session, successor_session = write_cdd_successor_checkpoint
    prepare_request = {
      "action" => "prepare",
      "run_root" => @run.relative_path_from(ROOT).to_s,
      "shared_checkpoint_path" => checkpoint.relative_path_from(ROOT).to_s,
      "shared_checkpoint_sha256" => sha(checkpoint),
      "source_session_id" => source_session,
      "successor_session_id" => successor_session,
      "runtime_state" => {
        "active_turn_count" => 0,
        "canonical_writer_idle" => true,
        "founder_gate_open" => false,
        "save_conflict" => false,
        "startup_phase" => "ready",
        "explicit_founder_confirmation" => true
      }
    }
    stdout, stderr, status = cli_with_stdin(JSON.generate(prepare_request), "cdd-successor")
    assert status.success?, [stdout, stderr].join("\n")
    prepared = JSON.parse(stdout)
    pack = prepared.fetch("boot_pack")
    assert_equal "idol-director-boot-pack.v3", pack.fetch("schema_version")
    assert_equal "video_playback_review", pack.dig("lineage_carry", "valid_through_stage")
    assert_equal true, pack.dig("lineage_carry", "exact_copy_only")
    assert_equal "cdd_successor", pack.fetch("profile")
    assert_equal false, pack.dig("authority_boundary", "creative_authority")
    assert_equal source_session, pack.dig("transfer", "source_session_id")
    assert_equal successor_session, pack.dig("transfer", "successor_session_id")
    assert_equal "read_only_preflight", pack.dig("transfer", "successor_authority_state")
    assert_equal @run.join("research", "front-planning-v1.md").relative_path_from(ROOT).to_s,
                 pack.dig("state_blocks", "creative_spine", "current_plan", "path")
    refute pack.to_json.include?("full child transcript")

    pack_path = ROOT.join(prepared.fetch("boot_pack_path"))
    pack_path.dirname.mkpath
    pack_path.write(JSON.pretty_generate(pack) + "\n")
    pack_sha = sha(pack_path)
    plan_pointer = pack.dig("state_blocks", "creative_spine", "current_plan")
    answers = IdolDirectorDispatchIndex::CDD_SUCCESSOR_QUESTIONS.to_h do |question|
      [question, {"answer" => "Current fixture state for #{question}.", "evidence_pointers" => [plan_pointer]}]
    end
    response = {
      "version" => 1,
      "status" => "ready",
      "boot_pack_path" => pack_path.relative_path_from(ROOT).to_s,
      "boot_pack_sha256" => pack_sha,
      "source_session_id" => source_session,
      "successor_session_id" => successor_session,
      "runtime_goal" => {
        "native_goal_id" => "GOAL_CDD_SUCCESSOR_FIXTURE",
        "state" => "achieved",
        "objective_sha256" => pack.dig("admission", "objective_sha256")
      },
      "answers" => answers,
      "authority_acknowledgement" => {
        "preflight_was_read_only" => true,
        "creative_authority_claimed" => false,
        "canonical_write_claimed" => false,
        "prior_session_retirement_observed" => false,
        "founder_confirmation_still_required" => true
      }
    }
    validate_request = {
      "action" => "validate",
      "boot_pack_path" => pack_path.relative_path_from(ROOT).to_s,
      "boot_pack_sha256" => pack_sha,
      "source_session_id" => source_session,
      "successor_session_id" => successor_session,
      "response_text" => "Read-only restore complete.\n<idol_cdd_successor_preflight>#{JSON.generate(response)}</idol_cdd_successor_preflight>"
    }
    stdout, stderr, status = cli_with_stdin(JSON.generate(validate_request), "cdd-successor")
    assert status.success?, [stdout, stderr].join("\n")
    admission = JSON.parse(stdout)
    assert_equal "pass", admission.fetch("status")
    assert_match(/\A[a-f0-9]{64}\z/, admission.fetch("admission_digest"))

    response["answers"]["do_not_revive"]["evidence_pointers"] = [{"path" => "wiki/unbound.md", "sha256" => "0" * 64}]
    validate_request["response_text"] = "<idol_cdd_successor_preflight>#{JSON.generate(response)}</idol_cdd_successor_preflight>"
    _stdout, stderr, status = cli_with_stdin(JSON.generate(validate_request), "cdd-successor")
    refute status.success?
    assert_includes stderr, "cites an unbound pointer"
  end

  def test_same_recipient_director_cannot_review_two_returns_at_once
    errors = []
    projection = IdolDirectorDispatchIndex.review_queue_projection(
      [
        [nil, queue_dispatch("RETURN_A", review_start: "2026-08-04T00:00:10Z", review_end: "2026-08-04T00:00:30Z", promotion_start: "2026-08-04T00:00:31Z", promotion_end: "2026-08-04T00:00:40Z")],
        [nil, queue_dispatch("RETURN_B", returned_at: "2026-08-04T00:00:02Z", review_start: "2026-08-04T00:00:20Z", review_end: "2026-08-04T00:00:35Z", promotion_start: "2026-08-04T00:00:41Z", promotion_end: "2026-08-04T00:00:50Z")]
      ],
      errors
    )

    assert_equal "single_flight_per_recipient_director_then_global_overall_promotion", projection.fetch("policy")
    assert errors.any? { |error| error.include?("review leases overlap") }, errors.inspect
    assert errors.any? { |error| error.include?("review order overlaps") }, errors.inspect
  end

  def test_returns_review_and_promote_sequentially_after_full_prior_closure
    errors = []
    projection = IdolDirectorDispatchIndex.review_queue_projection(
      [
        [nil, queue_dispatch("RETURN_A", review_start: "2026-08-04T00:00:10Z", review_end: "2026-08-04T00:00:20Z", promotion_start: "2026-08-04T00:00:21Z", promotion_end: "2026-08-04T00:00:30Z")],
        [nil, queue_dispatch("RETURN_B", returned_at: "2026-08-04T00:00:02Z", review_start: "2026-08-04T00:00:31Z", review_end: "2026-08-04T00:00:40Z", promotion_start: "2026-08-04T00:00:41Z", promotion_end: "2026-08-04T00:00:50Z")]
      ],
      errors
    )

    assert_empty errors
    assert_equal %w[RETURN_A RETURN_B], projection.fetch("items").map { |item| item.fetch("dispatch_id") }
  end

  def test_overall_promotion_lease_is_global_even_across_different_directors
    errors = []
    IdolDirectorDispatchIndex.review_queue_projection(
      [
        [nil, queue_dispatch("RETURN_A", director: "director_a", review_start: "2026-08-04T00:00:10Z", review_end: "2026-08-04T00:00:20Z", promotion_start: "2026-08-04T00:00:21Z", promotion_end: "2026-08-04T00:00:40Z")],
        [nil, queue_dispatch("RETURN_B", director: "director_b", returned_at: "2026-08-04T00:00:02Z", review_start: "2026-08-04T00:00:11Z", review_end: "2026-08-04T00:00:19Z", promotion_start: "2026-08-04T00:00:30Z", promotion_end: "2026-08-04T00:00:50Z")]
      ],
      errors
    )

    assert errors.any? { |error| error.include?("Overall promotion leases overlap") }, errors.inspect
  end

  def test_reference_index_checks_accepted_delta_pointer_and_alias_digest
    delta = @run.join("research", "delta.yaml")
    manifest = @run.join("research", "source-manifest.yaml")
    selected = @run.join("research", "selected-evidence.yaml")
    review = @run.join("review", "cdd-review.yaml")
    [manifest, selected, review].each { |path| path.dirname.mkpath }
    delta.write("dispatch_id: #{@dispatch_id}\nattempt_id: #{@dispatch_id}\nrows: []\n")
    manifest.write("source: fixture\n")
    selected.write("selected: bounded\n")
    review.write("disposition: accepted\n")
    dispatch = YAML.safe_load(@dispatch.read, aliases: true)
    dispatch_pointer = {"path" => @dispatch.relative_path_from(ROOT).to_s, "sha256" => sha(@dispatch)}
    doc = {
      "schema_version" => "idol-reference-working-index.v3",
      "artifact_type" => "reference_working_index",
      "status" => "current",
      "run" => @run.relative_path_from(ROOT).to_s,
      "owner" => "creative_development_director",
      "generated_at" => "2026-08-04T00:00:00Z",
      "authority_boundary" => {
        "derived_read_model" => true,
        "pointer_only" => true,
        "no_creative_authority" => true,
        "canonical_write" => false,
        "direct_use_granted" => false,
        "founder_approval_inferred" => false,
        "media_bytes_embedded" => false,
        "mechanical_exact_copy_only" => true
      },
      "upstream_heads" => [pointer(manifest, "source_manifest")],
      "worker_deltas" => [{
        "delta_id" => "DELTA_FIXTURE",
        "dispatch_id" => @dispatch_id,
        "attempt_id" => dispatch.dig("lineage", "attempt_id"),
        "path" => delta.relative_path_from(ROOT).to_s,
        "sha256" => sha(delta),
        "state" => "accepted"
      }],
      "rows" => [{
        "row_id" => "REF_ROW_FIXTURE",
        "source_id" => "SOURCE_FIXTURE",
        "reference_unit_id" => "UNIT_FIXTURE",
        "source_manifest" => pointer(manifest, "source_manifest"),
        "analysis_manifest" => nil,
        "selected_evidence" => pointer(selected, "selected_evidence"),
        "selected_locator" => "frame:01",
        "function" => "visible_action_or_hold",
        "disposition" => "applied",
        "source_eligibility" => {
          "classification" => "official_original_professional_primary",
          "public_pin_url_or_id" => nil,
          "origin_identity_verified" => true,
          "active_reuse_eligible" => true,
          "historical_row_reused_without_review" => false,
          "restricted_source_permission" => nil
        },
        "reference_connection_pointers" => [pointer(review, "reference_connection_review")],
        "section_bindings" => [],
        "decision_epoch" => "FOUNDER-EPOCH-FIXTURE",
        "worker_attempt" => {
          "lineage_id" => dispatch.dig("lineage", "lineage_id"),
          "attempt_id" => dispatch.dig("lineage", "attempt_id"),
          "dispatch_id" => @dispatch_id,
          "provider" => "codex",
          "session_id" => dispatch.dig("lineage", "session_id"),
          "dispatch_pointer" => dispatch_pointer
        },
        "cdd_review" => {
          "reviewer" => "creative_development_director",
          "reviewed_at" => "2026-08-04T00:00:01Z",
          "disposition" => "accepted",
          "review_pointer" => pointer(review, "cdd_review")
        },
        "downstream_consumers" => []
      }],
      "holds" => [],
      "next_actions" => []
    }
    pairs = IdolDirectorDispatchIndex.unique_sorted_pairs(IdolDirectorDispatchIndex.pointer_pairs(doc))
    digest = IdolDirectorDispatchIndex.source_set_digest(pairs)
    doc["source_set_digest"] = {
      "algorithm" => "sha256",
      "basis" => "sorted_pointer_path_hash_pairs_v1",
      "sha256" => digest,
      "entry_count" => pairs.length,
      "computed_at" => doc["generated_at"],
      "verified_before_write" => true
    }
    doc["source_set_sha256"] = digest
    reference = @run.join("research", "reference-working-index.yaml")
    reference.write(YAML.dump(doc))

    stdout, stderr, status = cli("validate-reference", "--json", reference.relative_path_from(ROOT).to_s)
    assert status.success?, [stdout, stderr].join("\n")
    assert_equal "pass", JSON.parse(stdout).fetch("status")

    doc["rows"][0]["source_eligibility"]["classification"] = "founder_permitted_restricted_edit"
    reference.write(YAML.dump(doc))
    stdout, _stderr, status = cli("validate-reference", reference.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "schema validation failed"
    doc["rows"][0]["source_eligibility"]["classification"] = "official_original_professional_primary"

    held = Marshal.load(Marshal.dump(doc))
    held["rows"][0]["disposition"] = "held"
    held["rows"][0]["cdd_review"]["disposition"] = "held"
    held["rows"][0]["section_bindings"] = [
      {"section_id" => "S01", "binding_pointer" => pointer(review, "held_binding")}
    ]
    reference.write(YAML.dump(held))
    stdout, _stderr, status = cli("validate-reference", reference.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "schema validation failed"

    restricted = Marshal.load(Marshal.dump(doc))
    eligibility = restricted["rows"][0]["source_eligibility"]
    eligibility["classification"] = "founder_permitted_restricted_edit"
    eligibility["restricted_source_permission"] = {
      "approval_scope" => "exact_current_task_founder_approval",
      "source_identity_or_url" => "fixture-restricted-source",
      "purpose" => "bounded analysis only",
      "allowed_actions" => ["analysis"],
      "founder_approval_pointer" => pointer(review, "founder_approval"),
      "provided_link_or_file_is_approval" => false,
      "rhythm_permission_implies_scene_binding" => false
    }
    reference.write(YAML.dump(restricted))
    stdout, _stderr, status = cli("validate-reference", reference.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "schema validation failed"

    restricted["rows"][0]["section_bindings"] = [
      {"section_id" => "S01", "binding_pointer" => pointer(review, "restricted_binding")}
    ]
    eligibility["restricted_source_permission"]["allowed_actions"] = ["candidate_use"]
    reference.write(YAML.dump(restricted))
    stdout, _stderr, status = cli("validate-reference", reference.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "schema validation failed"

    doc["worker_deltas"][0]["sha256"] = "0" * 64
    reference.write(YAML.dump(doc))
    stdout, _stderr, status = cli("validate-reference", reference.relative_path_from(ROOT).to_s)
    refute status.success?
    assert_includes stdout, "SHA-256 is stale"
  end

  private

  def write_legacy_dispatch(dispatch_id:, stage_id:, artifact_path:, schema_version: "idol-department-dispatch.v4", assigned_owner: "legacy_fixture_owner")
    path = @dispatch.dirname.join("#{dispatch_id}.yaml")
    document = {
      "schema_version" => schema_version,
      "artifact_type" => "department_dispatch",
      "dispatch_id" => dispatch_id,
      "run" => @run.relative_path_from(ROOT).to_s,
      "lineage" => {
        "lineage_id" => "LINEAGE_#{dispatch_id}",
        "attempt_id" => dispatch_id,
        "attempt_number" => 1,
        "lineage_state" => "completed"
      },
      "lifecycle" => {"current_state" => "promoted", "events" => []},
      "launch" => {
        "task" => {
          "task_id" => dispatch_id,
          "exact_scope" => {
            "mode" => "artifact",
            "stage_id" => stage_id,
            "section_ids" => [],
            "artifact_paths" => [artifact_path]
          }
        },
        "authority" => {
          "assigned_owner" => assigned_owner,
          "director_owner" => "legacy_fixture_director",
          "promotion_owner" => "legacy_fixture_overall"
        }
      },
      "promotion" => {
        "decision" => "promoted",
        "decided_at" => "2026-08-03T00:00:00Z",
        "promoter" => {"owner" => "legacy_fixture_overall", "role" => "overall_director"},
        "canonical_artifacts" => [{"path" => artifact_path, "sha256" => "0" * 64, "role" => "legacy_evidence"}]
      }
    }
    path.write(YAML.dump(document))
    path
  end

  def head_row(dispatch_id, attempt_number: 1, previous_attempt_id: nil, successor_dispatch_id: nil, retirement_state: "not_retired")
    artifact = pointer(@output, "canonical_artifact")
    dispatch_pointer = pointer(@dispatch, "department_dispatch")
    scope = {
      "stage_id" => "song_production_lock",
      "section_ids" => [],
      "chunk_ids" => [],
      "artifact_paths" => [@output.relative_path_from(ROOT).to_s],
      "interaction_surface" => "internal"
    }
    owner_receipt = {
      "owner" => "fixture_director",
      "role" => "overall_director",
      "source" => "promotion.promoter",
      "dispatch_pointer" => dispatch_pointer
    }
    {
      "dispatch_id" => dispatch_id,
      "attempt" => {
        "lineage_id" => "LINEAGE_SHARED_HEAD",
        "attempt_id" => dispatch_id,
        "attempt_no" => attempt_number,
        "session_id" => "SESSION_#{dispatch_id}",
        "provider" => "codex",
        "runtime_surface" => "fixture",
        "parent_lineage_id" => nil,
        "parent_dispatch_id" => nil,
        "previous_attempt_id" => previous_attempt_id,
        "successor_dispatch_id" => successor_dispatch_id,
        "session_state" => "complete",
        "retirement" => {
          "state" => retirement_state,
          "at" => retirement_state == "replaced" ? "2026-08-04T00:00:05Z" : nil,
          "reason_code" => retirement_state == "replaced" ? "successor_attempt" : nil
        }
      },
      "scope" => scope,
      "dispatch_pointer" => dispatch_pointer,
      "promotion" => {
        "state" => "promoted",
        "canonical_head_records" => [{
          "logical_artifact_id" => "ARTIFACT_SHARED_HEAD_FIXTURE",
          "logical_identity_basis" => "stage_scope_canonical_path_sha256_v1",
          "artifact" => artifact,
          "promotion_epoch" => "FOUNDER-EPOCH-FIXTURE",
          "promotion_epoch_source" => "canonical_artifact.decision_epoch",
          "promoted_at" => "2026-08-04T00:00:04Z",
          "owner_receipt" => owner_receipt
        }]
      }
    }
  end

  def queue_dispatch(dispatch_id, director: "fixture_director", returned_at: "2026-08-04T00:00:01Z", review_start:, review_end:, promotion_start:, promotion_end:)
    {
      "dispatch_id" => dispatch_id,
      "launch" => {
        "authority" => {
          "director_owner" => director,
          "promotion_owner" => "fixture_overall"
        }
      },
      "runtime_return" => {"returned_at" => returned_at},
      "review_control" => {
        "queue_state" => "released",
        "queue_priority" => {"dependency_rank" => 0},
        "review_lease" => {
          "lease_id" => "REVIEW_#{dispatch_id}",
          "acquired_at" => review_start,
          "released_at" => review_end
        },
        "promotion_lease" => {
          "lease_id" => "PROMOTION_#{dispatch_id}",
          "acquired_at" => promotion_start,
          "released_at" => promotion_end
        }
      },
      "director_review" => {"reviewed_at" => review_end},
      "promotion" => {"decided_at" => promotion_end}
    }
  end

  def cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT.to_s, *args, chdir: ROOT.to_s)
  end

  def cli_with_stdin(stdin, *args)
    Open3.capture3(RbConfig.ruby, SCRIPT.to_s, *args, stdin_data: stdin, chdir: ROOT.to_s)
  end

  def sha(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def pointer(path, role)
    {"path" => path.relative_path_from(ROOT).to_s, "sha256" => sha(path), "role" => role}
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original = value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonicalize(value[original])
      end
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def write_dispatch
    profile_contract = dispatch_fixture_profile_contract(
      profile_id: "song_room_00a",
      checkpoint_id: "selected_audio_analysis"
    )
    compiled_launch = dispatch_fixture_compiled_launch_prompt(
      profile_id: "song_room_00a",
      checkpoint_id: "selected_audio_analysis",
      source_ids: ["selected_fixture"]
    )
    required_skills = profile_contract.fetch("required_skills")
    objective = "Fixture bounded dispatch."
    output = {"path" => @output.relative_path_from(ROOT).to_s, "sha256" => sha(@output), "role" => "fixture_output"}
    categories = %w[founder skill policy contract schema output quality hold goal]
    requirements = categories.each_with_index.map do |category, index|
      source_binding = if category == "skill"
                         skill = required_skills.first
                         {"path" => skill.fetch("path"), "sha256" => skill.fetch("sha256"), "role" => "owning_skill"}
                       end
      {
        "requirement_id" => "#{category.upcase}-#{format('%02d', index + 1)}",
        "category" => category,
        "required" => true,
        "source_locator" => source_binding&.fetch("path", nil) || "/launch/#{category}",
        "source_binding" => source_binding,
        "affected_scope" => "fixture dispatch",
        "expected_output_target" => category == "goal" ? "/runtime_return/runtime_goal" : output.fetch("path"),
        "evidence_type" => category == "goal" ? "runtime_goal" : (category == "hold" ? "hold" : "artifact"),
        "director_semantic_review_required" => true
      }
    end
    launch = {
      "prepared_at" => "2026-08-04T00:00:00Z",
      "launched_at" => "2026-08-04T00:00:01Z",
      "launch_kind" => "worker_dispatch",
      "compiled_launch_prompt" => compiled_launch,
      "task" => {
        "task_id" => @dispatch_id,
        "role" => "song_room",
        "objective" => objective,
        "exact_scope" => {
          "mode" => "whole_run",
          "stage_id" => "song_production_lock",
          "section_ids" => [],
          "artifact_paths" => [@output.relative_path_from(ROOT).to_s]
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
        "decision_epoch" => "FOUNDER-EPOCH-FIXTURE",
        "locks" => [{"lock_id" => "LOCK_FIXTURE", "verbatim" => "Fixture lock", "scope" => "fixture", "source_locator" => "test"}]
      },
      "required_skills" => required_skills,
      "sources" => [{"source_id" => "selected_fixture", "path" => @source.relative_path_from(ROOT).to_s, "sha256" => sha(@source), "purpose" => "Fixture source."}],
      "external_permission" => {"mode" => "closed_local", "allowed_surfaces" => [], "approval_reference" => nil},
      "bounded_output" => {"description" => "Fixture output.", "output_kind" => "bounded_artifact", "expected_paths" => [@output.relative_path_from(ROOT).to_s], "maximum_artifact_count" => 1, "anti_flat_evidence_requirements" => ["Fixture evidence."]},
      "authority" => {"assigned_owner" => "fixture_worker", "director_owner" => "fixture_director", "promotion_owner" => "fixture_director", "canonical_write" => "bounded_to_expected_paths", "external_actions" => "forbidden", "may_decide" => ["fixture"], "must_not" => ["other scope"]},
      "hold_conditions" => ["Fixture hold."],
      "recipient" => {"owner" => "fixture_director", "role" => "creative_development_director", "return_route" => "fixture"}
    }
    dispatch_fixture_project_launch_prompt!(launch)
    lineage = {"lineage_id" => "LINEAGE_#{@dispatch_id}", "attempt_id" => @dispatch_id, "attempt_number" => 1, "provider" => "codex", "runtime_surface" => "fixture", "session_id" => "SESSION_#{@dispatch_id}", "parent_session_id" => "SESSION_PARENT", "parent_lineage_id" => "LINEAGE_PARENT", "parent_dispatch_id" => "DISPATCH_PARENT", "previous_attempt_id" => nil, "delegation_depth" => 1, "lineage_state" => "active", "successor_attempt_id" => nil}
    review_submission = {"review_cycle_id" => @dispatch_id, "submission_number" => 1, "maximum_submissions" => 3, "submission_kind" => "initial", "root_attempt_id" => @dispatch_id, "previous_submission_attempt_id" => nil, "correction_source" => nil, "repair_targets" => [], "repair_acceptance_criteria" => [], "frozen_outputs" => []}
    checks = requirements.map do |requirement|
      {"check_id" => "MECH-#{requirement.fetch('requirement_id')}", "requirement_id" => requirement.fetch("requirement_id"), "check_kind" => "coverage", "target" => requirement.fetch("expected_output_target"), "result" => "pass", "evidence" => "fixture structural check"}
    end
    receipt = {"contract_version" => "mechanical_compliance_receipt.v1", "validated_at" => "2026-08-04T00:00:01.8Z", "validator" => "fixture-validator", "checks" => checks, "all_required_checks_pass" => true, "receipt_sha256" => "0" * 64}
    receipt["receipt_sha256"] = digest(receipt.reject { |key, _value| key == "receipt_sha256" })
    claims = requirements.map do |requirement|
      {"requirement_id" => requirement.fetch("requirement_id"), "disposition" => "applied", "output_evidence" => %w[goal hold].include?(requirement.fetch("category")) ? [] : [output], "explanation" => "fixture worker fulfillment"}
    end
    goal_basis = {"mechanical_compliance_receipt_sha256" => receipt["receipt_sha256"], "worker_fulfillment_claims" => claims, "outputs" => [output], "hold_reasons" => []}
    runtime = {
      "returned_at" => "2026-08-04T00:00:02Z",
      "work_started_at" => "2026-08-04T00:00:01.5Z",
      "runtime_owner" => {"owner" => "fixture_worker", "role" => "song_room", "runtime_surface" => "fixture"},
      "runtime_goal" => {"provider" => "codex", "native_goal_id" => "GOAL_#{@dispatch_id}", "opened_at" => "2026-08-04T00:00:01.1Z", "goal_text_sha256" => launch.dig("goal_contract", "goal_text_sha256"), "state_at_return" => "achieved", "completion_evidence_sha256" => digest(goal_basis)},
      "skill_revisions" => dispatch_fixture_runtime_skill_revisions(launch["required_skills"], read_completed_at: "2026-08-04T00:00:01.3Z"),
      "mechanical_compliance_receipt" => receipt,
      "worker_fulfillment_claims" => claims,
      "input_digest" => {"basis" => "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4", "sha256" => digest("lineage" => lineage, "review_submission" => review_submission, "launch" => launch)},
      "output_inventory" => {"mode" => "single_artifact", "artifact_count" => 1, "aggregate_manifest" => nil},
      "outputs" => [output],
      "result_digest" => {"basis" => "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4", "sha256" => ""},
      "transport_closure_summary" => {
        "status" => "clean", "creative_bytes_changed" => false, "error" => nil,
        "source_digest" => {"basis" => "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4", "sha256" => sha(@source)},
        "output_digest" => {"basis" => "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4", "sha256" => sha(@output)},
        "schema_version" => "idol-transport-closure-summary.v1", "refresh_receipt_pointer" => nil,
        "corroboration_pointers" => [], "repair_count" => 0, "exceptions" => [],
        "next_owner" => "creative_development_director"
      },
      "hold_reasons" => [],
      "wake_event" => {"event_kind" => "final", "recipient_role" => "creative_development_director", "output_pointers" => [output], "aggregate_manifest" => nil, "hold_or_rejection_pointers" => [], "risk_or_unresolved_decision_pointers" => [], "raw_commentary_included" => false}
    }
    runtime["input_digest"]["sha256"] = digest("lineage" => lineage, "review_submission" => review_submission, "launch" => launch)
    runtime_basis = %w[work_started_at runtime_owner runtime_goal skill_revisions mechanical_compliance_receipt worker_fulfillment_claims output_inventory outputs hold_reasons wake_event].to_h { |key| [key, runtime[key]] }
    runtime["result_digest"]["sha256"] = digest(runtime_basis)
    reviewer_reads = required_skills.flat_map do |skill|
      [{"path" => skill.fetch("path"), "kind" => "skill", "revision" => skill.fetch("revision"), "sha256" => skill.fetch("sha256"), "read_to_eof" => true, "read_completed_at" => "2026-08-04T00:00:02.5Z"}] + Array(skill["linked_reads"]).map do |read|
        {"path" => read.fetch("path"), "kind" => "linked_module", "revision" => "hash-bound-launch-read", "sha256" => read.fetch("sha256"), "read_to_eof" => true, "read_completed_at" => "2026-08-04T00:00:02.5Z"}
      end
    end
    requirement_results = requirements.map do |requirement|
      {"requirement_id" => requirement.fetch("requirement_id"), "result" => "pass", "evidence_locator" => output.fetch("path"), "evidence_sha256" => output.fetch("sha256"), "judgment" => "fixture Director fulfillment judgment"}
    end
    rubric = %w[goal_opened_and_pursued founder_instruction_coverage owning_skill_application schema_and_contract_conformance current_assignment_resolution required_output_coverage observable_specificity source_and_pixel_grounding storyline_preservation locks_scope_and_unaffected_truth honest_completion_state].map do |criterion|
      {"criterion" => criterion, "result" => "pass", "evidence" => "fixture #{criterion} judgment"}
    end
    review = {"reviewed_at" => "2026-08-04T00:00:03Z", "director" => {"owner" => "fixture_director", "role" => "overall_director"}, "review_lease_id" => "REVIEW_#{@dispatch_id}", "reviewer_read_closure" => reviewer_reads, "mechanical_receipt_sha256" => receipt["receipt_sha256"], "requirement_results" => requirement_results, "disposition" => "accept", "rubric_results" => rubric, "reviewed_outputs" => [output], "summary" => "fixture", "correction" => nil}
    promotion = {"decision" => "promoted", "mode" => "direct_canonical_promotion", "decided_at" => "2026-08-04T00:00:04Z", "promoter" => {"owner" => "fixture_director", "role" => "overall_director"}, "promotion_lease_id" => "PROMOTION_#{@dispatch_id}", "approved_at" => "2026-08-04T00:00:04Z", "reason" => "fixture", "approved_working_outputs" => [output], "coordinator" => nil, "copy_completed_at" => nil, "canonical_artifacts" => [output], "queue_release_verified" => true, "baseline_refresh_evidence_sha256" => "0" * 64, "next_recipient" => {"owner" => "next", "role" => "next", "return_route" => "fixture"}}
    promotion_basis = {"dispatch_id" => @dispatch_id, "review_lease_id" => review["review_lease_id"], "promotion_lease_id" => promotion["promotion_lease_id"], "decision" => promotion["decision"], "approved_working_outputs" => promotion["approved_working_outputs"], "canonical_artifacts" => promotion["canonical_artifacts"], "decided_at" => promotion["decided_at"]}
    promotion["baseline_refresh_evidence_sha256"] = digest(promotion_basis)
    document = {
      "schema_version" => "idol-department-dispatch.v8",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => @dispatch_id,
      "run" => @run.relative_path_from(ROOT).to_s,
      "lineage" => lineage,
      "review_submission" => review_submission,
      "lifecycle" => {"current_state" => "promoted", "events" => [{"state" => "prepared", "at" => launch["prepared_at"], "actor" => "fixture_director"}, {"state" => "launched", "at" => launch["launched_at"], "actor" => "fixture"}, {"state" => "returned", "at" => runtime["returned_at"], "actor" => "fixture_worker"}, {"state" => "reviewed", "at" => review["reviewed_at"], "actor" => "fixture_director"}, {"state" => "promoted", "at" => promotion["decided_at"], "actor" => "fixture_director"}]},
      "review_control" => {"queue_policy" => "single_flight_per_recipient_director_then_global_overall_promotion", "queue_state" => "released", "queued_at" => runtime["returned_at"], "queue_priority" => {"dependency_rank" => 0, "returned_at_then_dispatch_id" => true}, "review_lease" => {"lease_id" => review["review_lease_id"], "director_owner" => "fixture_director", "acquired_at" => "2026-08-04T00:00:02.2Z", "released_at" => "2026-08-04T00:00:03.1Z"}, "promotion_lease" => {"lease_id" => promotion["promotion_lease_id"], "overall_owner" => "fixture_director", "acquired_at" => "2026-08-04T00:00:03.2Z", "released_at" => "2026-08-04T00:00:04.1Z"}},
      "routing_identity" => {
        "logical_role" => "worker", "worker_specialty" => "front_planning", "provider" => "codex",
        "logical_profile_alias" => "worker_high", "execution_profile_id" => "codex_worker_high",
        "resolved_provider_model" => "provider_snapshot_fixture", "reasoning_effort" => "high",
        "provider_capability_snapshot_sha256" => "0" * 64,
        "resolved_profile_snapshot_ref" => "RUN/work/provider-profile-snapshot.yaml#/worker_high",
        "session_topology" => "physical_native_session", "active_role_binding_id" => "ACTIVE-CDD-FIXTURE",
        "internal_subagent_policy" => "provider_native_default_no_logical_role_or_authority",
        "exact_task_subagent_override" => "none", "founder_visible" => false,
        "return_recipient_role" => "creative_development_director", "physical_transfer" => nil
      },
      "internal_delegation_summary" => {"provider_native_helpers_used" => false, "helper_count" => 0, "logical_roles_created" => 0, "canonical_owner_changed" => false, "founder_conversation_authority_granted" => false},
      "launch" => launch,
      "runtime_return" => runtime,
      "director_review" => review,
      "promotion" => promotion
    }
    @dispatch.write(YAML.dump(document))
  end

  def write_cdd_successor_checkpoint
    source_session = "019fd9ad-eb10-7d80-a69b-453996b5e46f"
    successor_session = "019fd9ad-eb10-7d80-a69b-453996b5e470"
    assignment_id = "creative_development_director:development-through-03v"
    provider_source_path = ".codex/agents/idol-sol-creative-development-director.toml"
    provider_source_sha256 = sha(ROOT.join(provider_source_path))
    provider_profile_pointer = "#/logical_profiles/director_deep/providers/codex/role_profiles/creative_development_director"
    readiness_evidence_sha256 = Digest::SHA256.hexdigest([
      "provider_source_readiness.v1", assignment_id, provider_source_path,
      provider_source_sha256, provider_profile_pointer, "provider_snapshot_model_fixture",
      "provider_snapshot_effort_fixture", "codex_native_threads", "installed_codex_auth", "",
      "active", "active", "true"
    ].join("\n"))
    immutable_profile_key = Digest::SHA256.hexdigest([
      "sha256_utf8_lf_assignment_profile_fields_v1", assignment_id, "codex",
      "codex_native_threads", "front_planning_workbench_startup_admission",
      "cdd_run_profile_fixture", "cdd_execution_profile_fixture", "director_deep",
      "provider_snapshot_model_fixture", "provider_snapshot_effort_fixture",
      "installed_codex_auth", "", provider_source_path, provider_source_sha256,
      provider_profile_pointer, readiness_evidence_sha256
    ].join("\n"))
    provider_binding = {
      "auth_lane" => "installed_codex_auth",
      "auth_authority_ref" => nil,
      "provider_source_path" => provider_source_path,
      "provider_source_sha256" => provider_source_sha256,
      "provider_profile_pointer" => provider_profile_pointer,
      "provider_source_readiness_status" => "ready",
      "provider_source_readiness_auth_lane_exact" => true,
      "provider_source_readiness_evidence_sha256" => readiness_evidence_sha256,
      "immutable_profile_key" => immutable_profile_key
    }
    plan = @run.join("research", "front-planning-v1.md")
    plan.write(YAML.dump({
      "storyline_lineage" => {
        "pre00_lineage" => {"pre00_storyline_original" => {"version_id" => "PRE00_STORYLINE_V001", "full_storyline_text" => "Fixture whole-film storyline."}},
        "active_version" => {"version_id" => "PRE00_STORYLINE_V001", "full_storyline_text" => "Fixture whole-film storyline."}
      },
      "screen_progression_map" => {"screen_progression_map_id" => "SPM_FIXTURE", "nodes" => []}
    }))
    canvas = @run.join("work", "front_planning_integration", "canvas-state.json")
    canvas.dirname.mkpath
    canvas_document = {
      "schema_version" => "front-planning-workbench.canvas-state.v5",
      "run" => {"run_root" => @run.relative_path_from(ROOT).to_s, "content_id" => "FIXTURE_CDD_SUCCESSOR"},
      "founder_epoch" => 7,
      "revision" => {"number" => 1, "updated_at" => "2026-08-04T00:00:10Z", "content_digest" => "1" * 64, "parent_digest" => ""},
      "sections" => [{"id" => "S01", "label" => "Fixture", "order" => 0, "status" => "draft", "time_range" => {"start" => "00:00", "end" => "00:10"}}],
      "assets" => [],
      "nodes" => [],
      "edges" => [],
      "sequence" => [],
      "session_links" => [provider_binding.merge({
        "provider" => "codex",
        "native_session_id" => source_session,
        "session_key" => "creative_development_director:development-through-03v",
        "studio_role" => "creative_development_director",
        "assignment_key" => "development-through-03v",
        "assignment_id" => assignment_id,
        "founder_epoch" => 7,
        "profile_id" => "cdd_run_profile_fixture",
        "execution_profile_id" => "cdd_execution_profile_fixture",
        "logical_profile_alias" => "director_deep",
        "resolved_provider_model" => "provider_snapshot_model_fixture",
        "reasoning_effort" => "provider_snapshot_effort_fixture",
        "binding_source" => "run_route_manifest",
        "status" => "attached_structured",
        "last_turn_id" => "TURN_CDD_FIXTURE",
        "fallback_behavior" => "hold_and_report",
        "runtime_surface" => "front_planning_workbench_startup_admission",
        "lineage_id" => "CDD_LINEAGE_FIXTURE",
        "attempt_id" => "CDD_ATTEMPT_FIXTURE_1",
        "model_or_role_profile" => "creative_development_director.cdd_startup",
        "bounded_scope" => @run.relative_path_from(ROOT).to_s,
        "input_digest" => "2" * 64,
        "checkpoint" => "cdd_startup:admitted",
        "output_manifest" => nil,
        "result_digest" => "3" * 64,
        "review_state" => "passed",
        "successor_lineage_id" => nil,
        "retirement_state" => "active"
      })],
      "pending_reconciliation" => {"dirty" => false, "events" => []}
    }
    canvas.write(JSON.pretty_generate(canvas_document) + "\n")
    checkpoint = @run.join("work", "front_planning_integration", "shared-context", "current.json")
    checkpoint.dirname.mkpath
    checkpoint_document = {
      "schema_version" => "front-planning-workbench.shared-context.v4",
      "checkpoint_id" => "FPCHK-0001",
      "version" => 1,
      "trigger" => "manual",
      "created_at" => "2026-08-04T00:00:11Z",
      "run_root" => @run.relative_path_from(ROOT).to_s,
      "founder_epoch" => 7,
      "active_section_id" => "S01",
      "transition" => nil,
      "plan" => {"path" => plan.relative_path_from(ROOT).to_s, "sha256" => sha(plan)},
      "canvas" => {"path" => canvas.relative_path_from(ROOT).to_s, "file_sha256" => sha(canvas), "revision" => 1, "content_digest" => "1" * 64},
      "planning_state" => {"status" => "draft", "sections" => [{"id" => "S01", "label" => "Fixture", "status" => "draft", "time" => "00:00-00:10"}], "selected_asset_ids" => [], "sequence_asset_ids" => [], "pending_reconciliation_dirty" => false},
      "session_links" => [provider_binding.merge({"provider" => "codex", "session_key" => "creative_development_director:development-through-03v", "studio_role" => "creative_development_director", "assignment_key" => "development-through-03v", "assignment_id" => assignment_id, "founder_epoch" => 7, "profile_id" => "cdd_run_profile_fixture", "execution_profile_id" => "cdd_execution_profile_fixture", "logical_profile_alias" => "director_deep", "resolved_provider_model" => "provider_snapshot_model_fixture", "reasoning_effort" => "provider_snapshot_effort_fixture", "binding_source" => "run_route_manifest", "fallback_behavior" => "hold_and_report", "native_session_id" => source_session, "status" => "attached_structured"})],
      "policy" => {"transcript_included" => false, "model_call_created" => false, "auto_advance" => false}
    }
    checkpoint.write(JSON.pretty_generate(checkpoint_document) + "\n")
    immutable_checkpoint = checkpoint.dirname.join("checkpoints", "checkpoint-FPCHK-0001.json")
    immutable_checkpoint.dirname.mkpath
    immutable_checkpoint.write(checkpoint.read)
    [checkpoint, source_session, successor_session]
  end
end
