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
require_relative "../idol_storyboard_probe_contract"

class IdolStoryboardProbeContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_storyboard_probe_contract.rb")
  SECTIONS = %w[S00 S01].freeze

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-storyboard-probe-contract-"))
    @execution_log_counter = 0
    @normalized_shard_counter = 0
    @repo_root = @tmp.join("repo")
    @repo_root.mkpath
    @source_bytes = {
      "runs/fixture/00-creative-nucleus.yaml" => "nucleus bytes",
      "runs/fixture/01-direction.yaml" => "direction bytes",
      "runs/fixture/whole-film-continuity.yaml" => "continuity bytes"
    }
    @sources = @source_bytes.each_with_index.map do |(path, bytes), index|
      source_file = @repo_root.join(path)
      source_file.dirname.mkpath
      source_file.binwrite(bytes)
      {
        "path" => path,
        "sha256" => Digest::SHA256.file(source_file.to_s).hexdigest,
        "disposition" => index == 2 ? "held" : "applied",
        "function" => index == 2 ? "whole-film continuity context" : "section camera and object truth",
        "target_sections" => index == 0 ? ["S00"] : index == 1 ? ["S01"] : SECTIONS,
        "reason" => index == 2 ? "This source keeps adjacent boundaries coherent." : "This source grounds one section without copying its surface."
      }
    end
    @source_set_sha256 = source_set_digest(@sources)
    @allowlist = write_json(
      "allowlist.json",
      "harness_commit" => "f4fd3a8",
      "section_universe" => SECTIONS,
      "supporting_context_source_paths" => [@sources.last["path"]],
      "sources" => @sources,
      "source_set_sha256" => @source_set_sha256
    )
    @context_digests = {}
    @contexts = SECTIONS.each_with_index.map do |section_id, index|
      document = context(section_id, index + 1)
      document["section_context_sha256"] = Digest::SHA256.hexdigest(JSON.generate(document))
      @context_digests[section_id] = document["section_context_sha256"]
      write_json("#{section_id}-context.json", document)
    end
    @shards = SECTIONS.each_with_index.map do |section_id, index|
      write_json("#{section_id}.json", shard(section_id, index + 1))
    end
    @result = @tmp.join("merged.json")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def test_successful_merge_and_validate_hash_bind_every_shard
    merge!(@shards)
    payload = JSON.parse(@result.read)
    assert_equal "idol_storyboard_probe_result.v1", payload["schema_version"]
    assert_equal "noncanonical_evaluation_only", payload["status"]
    assert_equal SECTIONS, payload.dig("coverage_audit", "completed_section_ids")
    assert_equal 2, payload.dig("coverage_audit", "actual_core_cut_count")
    assert_equal 4, payload.dig("coverage_audit", "actual_keyframe_count")
    assert_equal false, payload.dig("coverage_audit", "numeric_cap_used")
    assert_equal true, payload.dig("coverage_audit", "section_by_section_pass_used")
    assert_equal true, payload.dig("source_use_audit", "reference_closure_complete")
    assert_equal @sources, payload.dig("source_use_audit", "sources")
    assert_equal [@sources.last["path"]], payload.dig("source_use_audit", "unreferenced_source_paths")
    assert_equal @sources.first(2).map { |source| source["path"] }, payload.dig("source_use_audit", "direct_reference_paths")
    assert_equal [@sources.last["path"]], payload.dig("source_use_audit", "supporting_context_paths")
    assert_equal true, payload.dig("source_use_audit", "direct_reference_closure_complete")
    assert_equal true, payload.dig("source_use_audit", "supporting_context_closure_complete")
    payload["shard_receipts"].each do |receipt|
      assert Pathname.new(receipt["path"]).absolute?
      assert_equal Digest::SHA256.file(receipt["path"]).hexdigest, receipt["sha256"]
      assert Pathname.new(receipt["context_path"]).absolute?
      assert_equal Digest::SHA256.file(receipt["context_path"]).hexdigest, receipt["context_file_sha256"]
    end

    stdout, = run_cli("validate", @result, "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--json")
    report = JSON.parse(stdout)
    assert_equal true, report["ok"]
    assert_equal 4, report["actual_keyframe_count"]
  end

  def test_merge_rejects_exact_raw_shards_without_normalization_and_execution_receipts
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","),
      "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "deterministic_normalization_receipt is required"
    assert_includes stderr, "execution_receipt is required"
    refute @result.exist?
  end

  def test_zero_keyframes_fails_closed_before_output_write
    document = JSON.parse(@shards.first.read)
    document.dig("section", "storyboard_core_cuts", 0)["keyframe_shots"] = []
    @shards[0].write(JSON.pretty_generate(document))

    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "keyframe_shots must be a non-empty array"
    refute @result.exist?
  end

  def test_coverage_count_lie_is_rejected
    merge!(@shards)
    payload = JSON.parse(@result.read)
    payload["coverage_audit"]["actual_keyframe_count"] += 100
    @result.write(JSON.pretty_generate(payload))

    _stdout, stderr, status = run_cli_raw(
      "validate", @result, "--allowlist", @allowlist, "--sections", SECTIONS.join(",")
    )
    refute status.success?
    assert_includes stderr, "coverage_audit does not match counts and ids derived"
  end

  def test_source_path_and_hash_invention_are_rejected
    invented = JSON.parse(@shards.first.read)
    invented.dig("section", "storyboard_core_cuts", 0, "reference_uses", 0)["source_path"] = "runs/fixture/invented.yaml"
    @shards[0].write(JSON.pretty_generate(invented))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "outside the allowlist"

    @shards[0].write(JSON.pretty_generate(shard("S00", 1)))
    merge!(@shards)
    payload = JSON.parse(@result.read)
    payload.dig("source_use_audit", "sources", 0)["sha256"] = Digest::SHA256.hexdigest("invented")
    @result.write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "validate", @result, "--allowlist", @allowlist, "--sections", SECTIONS.join(",")
    )
    refute status.success?
    assert_includes stderr, "source_use_audit does not match allowlisted paths/hashes"
  end

  def test_allowlist_rejects_stale_missing_symlink_and_escape_source_bytes
    first_source = @repo_root.join(@sources.first["path"])
    first_source.binwrite("mutated bytes")
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "sha256 does not match source bytes"

    first_source.binwrite(@source_bytes.fetch(@sources.first["path"]))
    second_source = @repo_root.join(@sources[1]["path"])
    second_source.delete
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "path is not a readable regular file"

    second_source.binwrite(@source_bytes.fetch(@sources[1]["path"]))
    symlink_target = @repo_root.join("runs/fixture/symlink-target.yaml")
    symlink_target.binwrite(@source_bytes.fetch(@sources[1]["path"]))
    second_source.delete
    File.symlink(symlink_target.to_s, second_source.to_s)
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "path must not be a symlink"

    escaped_sources = Marshal.load(Marshal.dump(@sources))
    escaped_sources.first["path"] = "../outside.yaml"
    escaped_allowlist = write_json(
      "escaped-allowlist.json",
      "harness_commit" => "f4fd3a8",
      "section_universe" => SECTIONS,
      "supporting_context_source_paths" => [@sources.last["path"]],
      "sources" => escaped_sources,
      "source_set_sha256" => source_set_digest(escaped_sources)
    )
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", escaped_allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "normalized repo-relative path"
  end

  def test_missing_and_duplicate_sections_are_rejected
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, @shards.first
    )
    refute status.success?
    assert_includes stderr, "missing expected section shards: S01"

    duplicate = write_json("S00-duplicate.json", shard("S00", 1))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, @shards.first, duplicate, @shards.last
    )
    refute status.success?
    assert_includes stderr, "duplicate section shards: S00"
  end

  def test_stale_shard_receipt_is_rejected
    merge!(@shards)
    @shards.first.open("a") { |file| file.write("\n") }

    _stdout, stderr, status = run_cli_raw(
      "validate", @result, "--allowlist", @allowlist, "--sections", SECTIONS.join(",")
    )
    refute status.success?
    assert_includes stderr, "sha256 is stale"
  end

  def test_parent_cut_rewrite_and_missing_required_cut_are_rejected
    payload = JSON.parse(@shards.first.read)
    payload.dig("section", "storyboard_core_cuts", 0)["visible_action_or_hold"] = "A model-invented replacement action."
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "rewrites, drops, or adds parent-cut content"

    payload = shard("S00", 1)
    payload.dig("section", "storyboard_core_cuts").clear
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "must exactly cover required_parent_cuts in order"
  end

  def test_shard_time_and_boundaries_must_exactly_match_context
    payload = JSON.parse(@shards.first.read)
    payload["time_range"] = "0.000-3.500"
    payload["previous_boundary"] = "invented entry boundary"
    payload["next_boundary"] = "invented exit boundary"
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "time_range does not match the bounded section context"
    assert_includes stderr, "previous_boundary does not match the bounded section context"
    assert_includes stderr, "next_boundary does not match the bounded section context"
  end

  def test_stale_context_receipt_and_context_digest_lie_are_rejected
    merge!(@shards)
    @contexts.first.open("a") { |file| file.write("\n") }
    _stdout, stderr, status = run_cli_raw(
      "validate", @result, "--allowlist", @allowlist, "--sections", SECTIONS.join(",")
    )
    refute status.success?
    assert_includes stderr, "context_file_sha256 is stale"

    document = JSON.parse(@contexts.first.read)
    document["section_context_sha256"] = "0" * 64
    @contexts.first.write(JSON.pretty_generate(document))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @tmp.join("digest-lie.json"), *@shards
    )
    refute status.success?
    assert_includes stderr, "section_context_sha256 does not match compact JSON content"
  end

  def test_requires_exactly_one_context_per_expected_section
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--context", @contexts.first,
      "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "missing expected section contexts: S01"
  end

  def test_partial_merge_is_allowed_within_global_section_universe
    output = @tmp.join("partial-merged.json")
    s00 = normalize_for_merge(@shards.first, @contexts.first)
    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", @contexts.first,
      "--output", output, s00, "--json"
    )
    report = JSON.parse(stdout)
    assert_equal 1, report["section_count"]
    assert_equal 1, report["actual_core_cut_count"]
    assert_equal 2, report["actual_keyframe_count"]

    stdout, = run_cli(
      "validate", output, "--allowlist", @allowlist, "--sections", "S00", "--context", @contexts.first, "--json"
    )
    assert_equal true, JSON.parse(stdout)["ok"]

    nonprefix_output = @tmp.join("partial-nonprefix-merged.json")
    s01 = normalize_for_merge(@shards.last, @contexts.last)
    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", "S01", "--context", @contexts.last,
      "--output", nonprefix_output, s01, "--json"
    )
    assert_equal 1, JSON.parse(stdout)["section_count"]
    nonprefix_result = JSON.parse(nonprefix_output.read)
    assert_equal ["S01"], nonprefix_result.dig("coverage_audit", "completed_section_ids")
    assert_equal 2, nonprefix_result.dig("sections", 0, "section_order")
    assert_equal 2, nonprefix_result.dig("shard_receipts", 0, "section_order")
    stdout, = run_cli(
      "validate", nonprefix_output, "--allowlist", @allowlist, "--sections", "S01", "--context", @contexts.last, "--json"
    )
    assert_equal true, JSON.parse(stdout)["ok"]
  end

  def test_shard_commit_and_unknown_allowlist_target_are_rejected
    payload = JSON.parse(@shards.first.read)
    payload["harness_commit"] = "stale-commit"
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "harness_commit does not match the allowlist"

    payload = shard("S00", 1)
    payload.delete("harness_commit")
    @shards[0].write(JSON.pretty_generate(payload))
    merge!(@shards)
    merged = JSON.parse(@result.read)
    assert_equal "f4fd3a8", merged["harness_commit"]
    assert_equal "f4fd3a8", merged.dig("shard_receipts", 0, "harness_commit")

    altered_sources = Marshal.load(Marshal.dump(@sources))
    altered_sources.first["target_sections"] = ["S99"]
    altered_allowlist = write_json(
      "unknown-target-allowlist.json",
      "harness_commit" => "f4fd3a8",
      "section_universe" => SECTIONS,
      "supporting_context_source_paths" => [@sources.last["path"]],
      "sources" => altered_sources,
      "source_set_sha256" => source_set_digest(altered_sources)
    )
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", altered_allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "target_sections contains sections outside allowlist.section_universe: S99"
  end

  def test_noncanonical_merge_output_is_temp_only_and_binds_repo_root
    in_repo_output = @repo_root.join("runs/fixture/02A-master-storyboard.yaml")
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", in_repo_output, *@shards
    )
    refute status.success?
    assert_includes stderr, "--output must stay in an OS temporary directory outside the repository"

    merge!(@shards)
    result = JSON.parse(@result.read)
    expected_binding = {
      "realpath" => @repo_root.realpath.to_s,
      "source_set_sha256" => @source_set_sha256,
      "section_universe" => SECTIONS,
      "supporting_context_source_paths" => [@sources.last["path"]]
    }
    expected_binding["binding_sha256"] = Digest::SHA256.hexdigest(JSON.generate(expected_binding))
    assert_equal expected_binding, result["repo_root_binding"]
  end

  def test_sequence_must_be_positive_integer_and_global_child_ids_must_be_unique
    payload = JSON.parse(@shards.first.read)
    payload.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0)["shot_sequence"] = 0
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "shot_sequence must be an integer >= 1"

    @shards[0].write(JSON.pretty_generate(shard("S00", 1)))
    second = JSON.parse(@shards.last.read)
    first_shot = JSON.parse(@shards.first.read).dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0)
    second_shot = second.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0)
    second_shot["keyframe_shot_id"] = first_shot["keyframe_shot_id"]
    second_shot["packet_id"] = first_shot["packet_id"]
    @shards[1].write(JSON.pretty_generate(second))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "duplicate keyframe_shot_id values across sections"
    assert_includes stderr, "duplicate packet_id values across sections"

    first_cut_id = JSON.parse(@shards.first.read).dig("section", "storyboard_core_cuts", 0, "cut_id")
    second_context = JSON.parse(@contexts.last.read)
    second_context.dig("required_parent_cuts", 0)["required_cut_id"] = first_cut_id
    second_context_digest = rewrite_context(1, second_context)
    second = shard("S01", 2)
    second["section_context_sha256"] = second_context_digest
    second.dig("section", "storyboard_core_cuts", 0)["cut_id"] = first_cut_id
    @shards[1].write(JSON.pretty_generate(second))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "duplicate cut_id values across sections"
  end

  def test_applied_source_requires_evidence_in_at_least_one_declared_probe_target
    context = JSON.parse(@contexts.last.read)
    context.dig("section_plan", "reference_dispositions").clear
    context.dig("required_parent_cuts", 0, "source_parent_cut", "reference_uses").clear
    context["allowed_sources"].reject! { |source| source["path"] == @sources[1]["path"] }
    context_digest = rewrite_context(1, context)

    shard_document = JSON.parse(@shards.last.read)
    shard_document["section_context_sha256"] = context_digest
    shard_document.dig("section", "reference_dispositions").clear
    shard_document.dig("section", "storyboard_core_cuts", 0, "reference_uses").clear
    @shards[1].write(JSON.pretty_generate(shard_document))
    normalized = @shards.each_with_index.map do |shard_path, index|
      normalize_for_merge(shard_path, @contexts[index])
    end
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *normalized
    )
    refute status.success?
    assert_includes stderr, "direct reference sources lack output reference evidence in any declared in-probe target section"
    assert_includes stderr, @sources[1]["path"]
  end

  def test_supporting_source_requires_exact_hash_bound_context_admission
    context = JSON.parse(@contexts.first.read)
    context["allowed_sources"].reject! { |source| source["path"] == @sources.last["path"] }
    context_digest = rewrite_context(0, context)
    shard_document = JSON.parse(@shards.first.read)
    shard_document["section_context_sha256"] = context_digest
    @shards[0].write(JSON.pretty_generate(shard_document))
    normalized = normalize_for_merge(@shards.first, @contexts.first)
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", @contexts.first,
      "--output", @result, normalized
    )
    refute status.success?
    assert_includes stderr, "supporting context sources lack exact context admission in any declared in-probe target section"
    assert_includes stderr, @sources.last["path"]
  end

  def test_section_context_digest_is_required_and_receipt_tamper_is_rejected
    payload = JSON.parse(@shards.first.read)
    payload.delete("section_context_sha256")
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "section_context_sha256 must be exactly 64 lowercase hexadecimal characters"

    @shards[0].write(JSON.pretty_generate(shard("S00", 1)))
    merge!(@shards)
    result = JSON.parse(@result.read)
    result.dig("shard_receipts", 0)["section_context_sha256"] = Digest::SHA256.hexdigest("invented context")
    @result.write(JSON.pretty_generate(result))
    _stdout, stderr, status = run_cli_raw(
      "validate", @result, "--allowlist", @allowlist, "--sections", SECTIONS.join(",")
    )
    refute status.success?
    assert_includes stderr, "section_context_sha256 does not match the merged section projection"
  end

  def test_sparse_noncontiguous_sequence_is_valid_but_duplicate_or_reverse_order_is_not
    sparse = JSON.parse(@shards.first.read)
    shots = sparse.dig("section", "storyboard_core_cuts", 0, "keyframe_shots")
    shots[0]["shot_sequence"] = 10
    shots[1]["shot_sequence"] = 30
    @shards[0].write(JSON.pretty_generate(sparse))
    merge!(@shards)

    shots[1]["shot_sequence"] = 10
    @shards[0].write(JSON.pretty_generate(sparse))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @tmp.join("duplicate-sequence.json"), *@shards
    )
    refute status.success?
    assert_includes stderr, "duplicate shot_sequence"

    shots[0]["shot_sequence"] = 30
    shots[1]["shot_sequence"] = 10
    @shards[0].write(JSON.pretty_generate(sparse))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @tmp.join("reverse-sequence.json"), *@shards
    )
    refute status.success?
    assert_includes stderr, "strictly ascending"
  end

  def test_identity_compile_input_is_required_and_enforces_direct_02b_conditions
    payload = JSON.parse(@shards.first.read)
    shot = payload.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0)
    shot.delete("visible_member_focus")
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "visible_member_focus is required"

    shot["visible_member_focus"] = ["M01"]
    shot.delete("identity_compile_input")
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "identity_compile_input is required"

    shot["identity_compile_input"] = visible_identity("M01").merge("scene_reference_mode" => "api_scene_reference_required")
    @shards[0].write(JSON.pretty_generate(payload))
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *@shards
    )
    refute status.success?
    assert_includes stderr, "text_locks_only for direct 02B inheritance"
  end

  def test_keyframe_cardinality_has_no_numeric_maximum
    sections = SECTIONS
    many = shard("S00", 1)
    many_shots = 137.times.map do |index|
      keyframe_shot("S00", 1, index + 1, sequence: (index + 1) * 10, face_visible: false)
    end
    many.dig("section", "storyboard_core_cuts", 0)["keyframe_shots"] = many_shots
    many.dig("section", "section_quality_check")["actual_keyframe_count"] = many_shots.length
    shard_path = write_json("many.json", many)
    normalized_many = normalize_for_merge(shard_path, @contexts.first)
    normalized_second = normalize_for_merge(@shards.last, @contexts.last)
    output = @tmp.join("many-merged.json")

    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", sections.join(","),
      "--output", output, normalized_many, normalized_second, "--json"
    )
    assert_equal 139, JSON.parse(stdout)["actual_keyframe_count"]
    stdout, = run_cli(
      "validate", output, "--allowlist", @allowlist, "--sections", sections.join(","), "--json"
    )
    assert_equal 139, JSON.parse(stdout)["actual_keyframe_count"]
  end

  def test_core_cut_cardinality_has_no_numeric_maximum
    section_id = "S00"
    output_cuts = []
    required_parent_cuts = []
    73.times do |index|
      sequence_number = index + 100
      output_cut = Marshal.load(Marshal.dump(cut(section_id, 1)))
      output_cut["cut_id"] = format("C%03d_MANY_CORE_CUT", sequence_number)
      output_cut["keyframe_shots"].each_with_index do |shot, shot_index|
        shot["keyframe_shot_id"] = format("KS_MANY_%03d_%02d", sequence_number, shot_index + 1)
        shot["packet_id"] = format("PKT_B%03d_MANY_%02d", sequence_number, shot_index + 1)
      end
      parent_cut = Marshal.load(Marshal.dump(output_cut))
      parent_cut.delete("keyframe_shots")
      parent_cut["cut_id"] = format("LEGACY_MANY_%03d", sequence_number)
      output_cuts << output_cut
      required_parent_cuts << {"required_cut_id" => output_cut["cut_id"], "source_parent_cut" => parent_cut}
    end

    context = JSON.parse(@contexts.first.read)
    context["required_parent_cuts"] = required_parent_cuts
    context.dig("section_plan", "section_quality_check")["actual_core_cut_count"] = output_cuts.length
    context.dig("section_plan", "section_quality_check")["actual_keyframe_count"] = output_cuts.length * 2
    context_digest = rewrite_context(0, context)

    shard_document = JSON.parse(@shards.first.read)
    shard_document["section_context_sha256"] = context_digest
    shard_document.dig("section", "storyboard_core_cuts").replace(output_cuts)
    shard_document.dig("section", "section_quality_check")["actual_core_cut_count"] = output_cuts.length
    shard_document.dig("section", "section_quality_check")["actual_keyframe_count"] = output_cuts.length * 2
    @shards[0].write(JSON.pretty_generate(shard_document))
    normalized_first = normalize_for_merge(@shards.first, @contexts.first)
    normalized_second = normalize_for_merge(@shards.last, @contexts.last)

    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result,
      normalized_first, normalized_second, "--json"
    )
    report = JSON.parse(stdout)
    assert_equal 74, report["actual_core_cut_count"]
    assert_equal 148, report["actual_keyframe_count"]
  end

  def test_normalize_shard_repairs_only_locked_parent_fields_and_records_receipt
    raw_document = JSON.parse(@shards.first.read)
    raw_document.dig("section", "storyboard_core_cuts", 0)["visible_action_or_hold"] = "model drift that must not survive normalization"
    raw_document.dig("section")["section_story_job"] = "model-rewritten section plan"
    raw_path = write_json("raw-parent-drift.json", raw_document)
    execution_log = execution_log_for(raw_path, @contexts.first)
    output = @tmp.join("normalized-parent-drift.json")

    stdout, = run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", execution_log,
      "--output", output, "--json"
    )
    report = JSON.parse(stdout)
    assert_operator report["repaired_locked_field_count"], :>=, 2
    assert_includes report["repaired_locked_field_paths"], "section.section_story_job"
    assert_includes report["repaired_locked_field_paths"], "section.storyboard_core_cuts[0].visible_action_or_hold"

    normalized = JSON.parse(output.read)
    context = JSON.parse(@contexts.first.read)
    assert_equal context.dig("section_plan", "section_story_job"), normalized.dig("section", "section_story_job")
    assert_equal context.dig("required_parent_cuts", 0, "source_parent_cut", "visible_action_or_hold"), normalized.dig("section", "storyboard_core_cuts", 0, "visible_action_or_hold")
    assert_equal raw_document.dig("section", "storyboard_core_cuts", 0, "keyframe_shots"), normalized.dig("section", "storyboard_core_cuts", 0, "keyframe_shots")
    assert_equal Digest::SHA256.file(raw_path.to_s).hexdigest, normalized.dig("deterministic_normalization_receipt", "raw_sha256")

    merged = @tmp.join("normalized-merge.json")
    normalized_second = normalize_for_merge(@shards.last, @contexts.last)
    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", merged,
      output, normalized_second, "--json"
    )
    assert_equal 2, JSON.parse(stdout)["actual_core_cut_count"]
  end

  def test_normalize_shard_rejects_invalid_keyframes_and_missing_or_extra_cuts
    invalid = JSON.parse(@shards.first.read)
    invalid.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0).delete("identity_compile_input")
    invalid_path = write_json("raw-invalid-keyframe.json", invalid)
    invalid_log = execution_log_for(invalid_path, @contexts.first)
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", invalid_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", invalid_log,
      "--output", @tmp.join("invalid-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "identity_compile_input is required"

    missing = JSON.parse(@shards.first.read)
    missing.dig("section", "storyboard_core_cuts").clear
    missing_path = write_json("raw-missing-cut.json", missing)
    missing_log = execution_log_for(missing_path, @contexts.first)
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", missing_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", missing_log,
      "--output", @tmp.join("missing-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "must exactly cover context required_cut_id values in order"

    extra = JSON.parse(@shards.first.read)
    extra_cut = Marshal.load(Marshal.dump(extra.dig("section", "storyboard_core_cuts", 0)))
    extra_cut["cut_id"] = "C999_EXTRA_CUT"
    extra.dig("section", "storyboard_core_cuts") << extra_cut
    extra_path = write_json("raw-extra-cut.json", extra)
    extra_log = execution_log_for(extra_path, @contexts.first)
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", extra_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", extra_log,
      "--output", @tmp.join("extra-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "must exactly cover context required_cut_id values in order"
  end

  def test_normalize_shard_no_drift_has_zero_repairs_and_identical_keyframes
    raw_document = JSON.parse(@shards.last.read)
    raw_path = write_json("raw-no-drift.json", raw_document)
    execution_log = execution_log_for(raw_path, @contexts.last)
    output = @tmp.join("normalized-no-drift.json")
    stdout, = run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.last,
      "--execution-log", execution_log,
      "--output", output, "--json"
    )
    report = JSON.parse(stdout)
    assert_equal 0, report["repaired_locked_field_count"]
    assert_empty report["repaired_locked_field_paths"]
    normalized = JSON.parse(output.read)
    assert_equal raw_document.dig("section", "storyboard_core_cuts", 0, "keyframe_shots"), normalized.dig("section", "storyboard_core_cuts", 0, "keyframe_shots")
    assert_equal report["keyframe_shots_sha256"], normalized.dig("deterministic_normalization_receipt", "keyframe_shots_sha256")
  end

  def test_normalize_shard_collapses_only_exact_deep_equal_duplicate_cut
    raw_document = JSON.parse(@shards.first.read)
    original_cut = raw_document.dig("section", "storyboard_core_cuts", 0)
    raw_document.dig("section", "storyboard_core_cuts") << Marshal.load(Marshal.dump(original_cut))
    raw_path = write_json("raw-exact-duplicate.json", raw_document)
    execution_log = execution_log_for(raw_path, @contexts.first)
    output = @tmp.join("normalized-exact-duplicate.json")
    stdout, = run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", execution_log,
      "--output", output, "--json"
    )
    report = JSON.parse(stdout)
    assert_equal 1, report["collapsed_exact_duplicate_cuts"].length
    removal = report["collapsed_exact_duplicate_cuts"].first
    assert_equal 1, removal["removed_raw_index"]
    assert_equal "section.storyboard_core_cuts[1]", removal["removed_raw_path"]
    assert_equal "section.storyboard_core_cuts[0]", removal["exact_duplicate_of"]
    assert_includes report["repaired_locked_field_paths"], "section.storyboard_core_cuts[1]"

    normalized = JSON.parse(output.read)
    assert_equal 1, normalized.dig("section", "storyboard_core_cuts").length
    assert_equal original_cut["keyframe_shots"], normalized.dig("section", "storyboard_core_cuts", 0, "keyframe_shots")
    refute_equal report["raw_keyframe_shots_sha256"], report["keyframe_shots_sha256"]
  end

  def test_normalize_shard_rejects_nonidentical_duplicate_cut
    raw_document = JSON.parse(@shards.first.read)
    duplicate = Marshal.load(Marshal.dump(raw_document.dig("section", "storyboard_core_cuts", 0)))
    duplicate["visible_action_or_hold"] = "same id but different locked action"
    raw_document.dig("section", "storyboard_core_cuts") << duplicate
    raw_path = write_json("raw-different-duplicate.json", raw_document)
    execution_log = execution_log_for(raw_path, @contexts.first)
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", execution_log,
      "--output", @tmp.join("different-duplicate-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "must exactly cover context required_cut_id values in order"
  end

  def test_normalize_shard_requires_execution_log_and_rejects_actual_max_when_context_is_xhigh
    raw_document = JSON.parse(@shards.first.read)
    raw_path = write_json("raw-execution-route.json", raw_document)
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--output", @tmp.join("missing-execution-log.json")
    )
    refute status.success?
    assert_includes stderr, "requires --execution-log PATH"

    xhigh_log = execution_log_for(raw_path, @contexts.first, effort: "max")
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", xhigh_log, "--output", @tmp.join("xhigh-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "actual effort \"max\" does not match context effort \"xhigh\""
  end

  def test_execution_receipt_uses_latest_completed_matching_resumed_turn
    raw_document = JSON.parse(@shards.first.read)
    raw_path = write_json("raw-resumed-max.json", raw_document)
    rows = execution_turn_rows(
      turn_id: "earlier-max", raw_document: raw_document, context_path: @contexts.first, effort: "max"
    )
    rows.concat(
      execution_turn_rows(
        turn_id: "latest-xhigh", raw_document: raw_document, context_path: @contexts.first, effort: "xhigh"
      )
    )
    log = write_execution_log("resumed-max.jsonl", rows)
    output = @tmp.join("resumed-max-normalized.json")
    run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", log, "--output", output, "--json"
    )

    receipt = JSON.parse(output.read).fetch("execution_receipt")
    assert_equal "latest-xhigh", receipt["turn_id"]
    assert_equal "gpt-5.6-sol", receipt["actual_model"]
    assert_equal "xhigh", receipt["actual_effort"]
    assert_equal true, receipt["task_complete"]
    assert_equal Digest::SHA256.file(log.to_s).hexdigest, receipt["execution_log_sha256"]
  end

  def test_execution_log_rejects_wrong_raw_unfinished_turn_and_missing_context_path
    raw_document = JSON.parse(@shards.first.read)
    raw_path = write_json("raw-log-correlation.json", raw_document)
    cases = {
      "wrong-raw" => execution_turn_rows(
        turn_id: "wrong-raw", raw_document: JSON.parse(@shards.last.read), context_path: @contexts.first
      ),
      "unfinished" => execution_turn_rows(
        turn_id: "unfinished", raw_document: raw_document, context_path: @contexts.first, complete: false
      ),
      "missing-context" => execution_turn_rows(
        turn_id: "missing-context", raw_document: raw_document, context_path: @contexts.first, include_context: false
      )
    }
    cases.each do |name, rows|
      log = write_execution_log("#{name}.jsonl", rows)
      _stdout, stderr, status = run_cli_raw(
        "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
        "--execution-log", log, "--output", @tmp.join("#{name}-normalized.json")
      )
      refute status.success?, name
      assert_includes stderr, "no completed turn whose user message names the exact context path", name
    end
  end

  def test_authoring_rebind_accepts_exact_compact_hash_attestation_without_reprinting_raw_json
    context_path = write_authoring_context("S00", 1)
    raw_path = write_json(
      "authoring-compact-attestation-raw.json",
      authoring_shard(JSON.parse(context_path.read), cut_count: 3)
    )
    attestation_stdout, = run_cli(
      "attest", raw_path, "--allowlist", @allowlist, "--context", context_path
    )
    assert_equal compact_execution_attestation(raw_path, context_path), JSON.parse(attestation_stdout)
    log = write_execution_log(
      "compact-attestation.jsonl",
      compact_execution_turn_rows(
        turn_id: "compact-attestation",
        raw_path: raw_path,
        context_path: context_path
      )
    )
    output = @tmp.join("compact-attestation-normalized.json")

    run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
      "--execution-log", log, "--output", output, "--json"
    )

    receipt = JSON.parse(output.read).fetch("execution_receipt")
    assert_equal "idol_storyboard_probe_execution.v2", receipt["receipt_version"]
    assert_equal "compact_hash_attestation", receipt["evidence_mode"]
    assert_equal "gpt-5.6-sol", receipt["actual_model"]
    assert_equal "xhigh", receipt["actual_effort"]
  end

  def test_compact_hash_attestation_rejects_wrong_hash_missing_raw_binding_and_child_mode
    context_path = write_authoring_context("S00", 1)
    raw_path = write_json(
      "authoring-invalid-compact-raw.json",
      authoring_shard(JSON.parse(context_path.read), cut_count: 1)
    )
    attestation = compact_execution_attestation(raw_path, context_path)
    cases = {
      "wrong-hash" => {
        message: "Compact receipt for #{context_path.expand_path} and #{raw_path.expand_path}",
        attestation: attestation.merge("raw_sha256" => "0" * 64)
      },
      "missing-raw-path" => {
        message: "Compact receipt for #{context_path.expand_path}",
        attestation: attestation
      }
    }
    cases.each do |name, row|
      log = write_execution_log(
        "#{name}-compact.jsonl",
        execution_turn_rows(
          turn_id: name,
          raw_document: row[:attestation],
          context_path: context_path,
          user_message: row[:message]
        )
      )
      _stdout, stderr, status = run_cli_raw(
        "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
        "--execution-log", log, "--output", @tmp.join("#{name}-compact-normalized.json")
      )
      refute status.success?, name
      assert_includes stderr, "exact compact hash attestation", name
    end

    child_raw = write_json("child-compact-raw.json", JSON.parse(@shards.first.read))
    child_attestation = compact_execution_attestation(child_raw, @contexts.first)
    child_log = write_execution_log(
      "child-compact.jsonl",
      execution_turn_rows(
        turn_id: "child-compact",
        raw_document: child_attestation,
        context_path: @contexts.first,
        user_message: "Compact receipt for #{@contexts.first.expand_path} and #{child_raw.expand_path}"
      )
    )
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", child_raw, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", child_log, "--output", @tmp.join("child-compact-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "exact compact hash attestation"
  end

  def test_merge_reverifies_execution_receipt_and_rejects_stale_log
    raw_document = JSON.parse(@shards.first.read)
    raw_path = write_json("raw-stale-log.json", raw_document)
    log = execution_log_for(raw_path, @contexts.first)
    normalized = @tmp.join("stale-log-normalized.json")
    run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", @contexts.first,
      "--execution-log", log, "--output", normalized
    )
    log.open("a") { |file| file.write("\n") }

    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","),
      "--output", @tmp.join("stale-log-merged.json"), normalized, @shards.last
    )
    refute status.success?
    assert_includes stderr, "execution_receipt does not match current execution-log/raw/context evidence"
  end

  def test_continuity_rejects_legacy_malformed_and_unknown_keyframe_ids
    invalid_tokens = ["KF_UNKNOWN_01", "KSB_UNKNOWN_01", "KSS00P_UNKNOWN", "KSC_UNKNOWN", "KS_UNKNOWN_01"]
    invalid_tokens.each do |token|
      payload = shard("S00", 1)
      payload.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0)["continuity_out"] = "continue through #{token}"
      @shards[0].write(JSON.pretty_generate(payload))
      _stdout, stderr, status = run_cli_raw(
        "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","),
        "--output", @tmp.join("invalid-continuity-#{token}.json"), *@shards
      )
      refute status.success?, token
      if token.start_with?("KS_")
        assert_includes stderr, "references unknown keyframe id #{token}", token
      else
        assert_includes stderr, "contains invalid continuity id token #{token}", token
      end
    end
  end

  def test_continuity_accepts_existing_cross_section_adjacent_keyframe_ids
    first = JSON.parse(@shards.first.read)
    second = JSON.parse(@shards.last.read)
    first_last = first.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 1)
    second_first = second.dig("section", "storyboard_core_cuts", 0, "keyframe_shots", 0)
    first_last["continuity_out"] = "the route continues into #{second_first.fetch('keyframe_shot_id')}"
    second_first["continuity_in"] = "inherit the line from #{first_last.fetch('keyframe_shot_id')}"
    @shards[0].write(JSON.pretty_generate(first))
    @shards[1].write(JSON.pretty_generate(second))

    merge!(@shards)
    assert_equal 4, JSON.parse(@result.read).dig("coverage_audit", "actual_keyframe_count")
  end

  def test_authoring_normalization_rejects_a_truncated_local_keyframe_id_before_merge
    context_path = write_authoring_context("S00", 1)
    raw_document = authoring_shard(JSON.parse(context_path.read), cut_count: 1)
    shots = raw_document.dig("section", "storyboard_core_cuts", 0, "keyframe_shots")
    exact_id = shots.first.fetch("keyframe_shot_id")
    truncated_id = exact_id.sub(/_\d+\z/, "")
    shots.last["continuity_in"] = "inherit the local state from #{truncated_id}"
    raw_path = write_json("authoring-truncated-local-id-raw.json", raw_document)
    log = execution_log_for(raw_path, context_path)

    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
      "--execution-log", log, "--output", @tmp.join("authoring-truncated-local-id-normalized.json")
    )

    refute status.success?
    assert_includes stderr, "uses truncated local keyframe id #{truncated_id}"
    assert_includes stderr, "use exact #{exact_id}"
  end

  def test_section_02a_authoring_one_cut_preserves_full_creative_section_and_binds_mode
    context_path = write_authoring_context("S00", 1)
    context_document = JSON.parse(context_path.read)
    raw_document = authoring_shard(context_document, cut_count: 1)
    raw_path = write_json("authoring-one-cut-raw.json", raw_document)
    normalized = normalize_authoring(raw_path, context_path, "authoring-one-cut-normalized.json")
    normalized_document = JSON.parse(normalized.read)

    assert_equal raw_document["section"], normalized_document["section"]
    receipt = normalized_document.fetch("deterministic_normalization_receipt")
    assert_equal "section_02a_authoring", receipt["probe_mode"]
    assert_equal receipt["raw_creative_section_semantic_sha256"], receipt["normalized_creative_section_semantic_sha256"]
    assert_equal "section_02a_authoring", normalized_document.dig("execution_receipt", "probe_mode")

    output = @tmp.join("authoring-one-cut-result.json")
    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", context_path,
      "--output", output, normalized, "--json"
    )
    assert_equal 1, JSON.parse(stdout)["actual_core_cut_count"]
    result = JSON.parse(output.read)
    assert_equal "section_02a_authoring", result["probe_mode"]
    assert_equal "section_02a_authoring", result.dig("shard_receipts", 0, "probe_mode")
  end

  def test_section_02a_authoring_has_no_parent_cut_cap_at_74_cuts
    context_path = write_authoring_context("S00", 1)
    raw_document = authoring_shard(JSON.parse(context_path.read), cut_count: 74)
    raw_path = write_json("authoring-74-cut-raw.json", raw_document)
    normalized = normalize_authoring(raw_path, context_path, "authoring-74-cut-normalized.json")
    output = @tmp.join("authoring-74-cut-result.json")

    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", context_path,
      "--output", output, normalized, "--json"
    )
    report = JSON.parse(stdout)
    assert_equal 74, report["actual_core_cut_count"]
    assert_equal 148, report["actual_keyframe_count"]
    assert_equal false, JSON.parse(output.read).dig("coverage_audit", "numeric_cap_used")
  end

  def test_section_02a_authoring_accepts_one_and_seven_keyframes_without_a_parent_local_cap
    context_path = write_authoring_context("S00", 1)
    raw_document = authoring_shard(JSON.parse(context_path.read), cut_count: 2)
    cuts = raw_document.dig("section", "storyboard_core_cuts")
    cuts.first["keyframe_shots"] = [cuts.first.fetch("keyframe_shots").first]

    seed = cuts.last.fetch("keyframe_shots").first
    cuts.last["keyframe_shots"] = 7.times.map do |index|
      shot = Marshal.load(Marshal.dump(seed))
      sequence = index + 1
      shot["keyframe_shot_id"] = format("KS_AUTH_S00_1002_%02d", sequence)
      shot["packet_id"] = format("PKT_B1002_AUTH_S00_%02d", sequence)
      shot["shot_role"] = "observable_state_#{sequence}"
      shot["shot_sequence"] = sequence
      shot["visible_action"] = "Observable authored state #{sequence} changes the hand, object, or camera relation without repeating a start/end placeholder."
      shot["continuity_in"] = sequence == 1 ? "inherit the first parent endpoint" : "inherit observable state #{sequence - 1}"
      shot["continuity_out"] = sequence == 7 ? "hand off to the next section boundary" : "hand off to observable state #{sequence + 1}"
      shot
    end
    raw_document.dig("section", "section_quality_check")["actual_keyframe_count"] = 8
    raw_path = write_json("authoring-one-and-seven-keyframes-raw.json", raw_document)
    normalized = normalize_authoring(raw_path, context_path, "authoring-one-and-seven-keyframes-normalized.json")
    output = @tmp.join("authoring-one-and-seven-keyframes-result.json")

    stdout, = run_cli(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", context_path,
      "--output", output, normalized, "--json"
    )
    report = JSON.parse(stdout)
    assert_equal 2, report["actual_core_cut_count"]
    assert_equal 8, report["actual_keyframe_count"]
    assert_equal [1, 7], JSON.parse(output.read).dig("sections", 0, "storyboard_core_cuts").map { |cut| cut.fetch("keyframe_shots").length }
    assert_equal false, JSON.parse(output.read).dig("coverage_audit", "numeric_cap_used")
  end

  def test_authoring_parent_cut_count_can_change_when_split_obligations_remain_exactly_covered
    context_path = write_authoring_context("S00", 1, obligation_ids: %w[OBL_S00_A OBL_S00_B])
    context_document = JSON.parse(context_path.read)
    variants = {
      1 => {0 => %w[OBL_S00_A OBL_S00_B]},
      2 => {0 => ["OBL_S00_A"], 1 => ["OBL_S00_B"]}
    }
    variants.each do |cut_count, assignments|
      raw = authoring_shard(context_document, cut_count: cut_count, obligation_assignments: assignments)
      raw_path = write_json("authoring-count-#{cut_count}-raw.json", raw)
      normalized = normalize_authoring(raw_path, context_path, "authoring-count-#{cut_count}-normalized.json")
      output = @tmp.join("authoring-count-#{cut_count}-result.json")
      stdout, = run_cli(
        "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", context_path,
        "--output", output, normalized, "--json"
      )
      assert_equal cut_count, JSON.parse(stdout)["actual_core_cut_count"]
    end
  end

  def test_authoring_rejects_missing_unknown_and_duplicate_split_obligation_refs
    context_path = write_authoring_context("S00", 1, obligation_ids: %w[OBL_S00_A OBL_S00_B])
    context_document = JSON.parse(context_path.read)
    cases = {
      "missing" => ["OBL_S00_A"],
      "unknown" => %w[OBL_S00_A OBL_S00_B OBL_UNKNOWN],
      "duplicate" => %w[OBL_S00_A OBL_S00_A OBL_S00_B]
    }
    cases.each do |name, refs|
      raw = authoring_shard(context_document, cut_count: 1, obligation_assignments: {0 => refs})
      raw_path = write_json("authoring-obligation-#{name}-raw.json", raw)
      log = execution_log_for(raw_path, context_path)
      _stdout, stderr, status = run_cli_raw(
        "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
        "--execution-log", log, "--output", @tmp.join("authoring-obligation-#{name}-normalized.json")
      )
      refute status.success?, name
      assert_includes stderr, name == "missing" ? "missing required refs" : name == "unknown" ? "contains unknown refs" : "duplicate refs", name
    end
  end

  def test_authoring_rejects_missing_unknown_and_duplicate_upstream_lock_refs
    context_path = write_authoring_context("S00", 1)
    context_document = JSON.parse(context_path.read)
    expected = authoring_upstream_ids(context_document)
    cases = {
      "missing" => expected.drop(1),
      "unknown" => expected + ["LOCK_UNKNOWN"],
      "duplicate" => expected + [expected.first]
    }
    cases.each do |name, refs|
      raw = authoring_shard(context_document, cut_count: 1)
      raw.dig("section", "storyboard_core_cuts", 0)["upstream_lock_refs"] = refs
      raw_path = write_json("authoring-upstream-#{name}-raw.json", raw)
      log = execution_log_for(raw_path, context_path)
      _stdout, stderr, status = run_cli_raw(
        "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
        "--execution-log", log, "--output", @tmp.join("authoring-upstream-#{name}-normalized.json")
      )
      refute status.success?, name
      assert_includes stderr, name == "missing" ? "missing required refs" : name == "unknown" ? "contains unknown refs" : "duplicate refs", name
    end
  end

  def test_authoring_normalization_rejects_any_post_normalization_creative_mutation
    context_path = write_authoring_context("S00", 1)
    raw = authoring_shard(JSON.parse(context_path.read), cut_count: 1)
    raw_path = write_json("authoring-mutation-raw.json", raw)
    normalized = normalize_authoring(raw_path, context_path, "authoring-mutation-normalized.json")
    normalized_document = JSON.parse(normalized.read)
    normalized_document.dig("section", "storyboard_core_cuts", 0)["visible_action_or_hold"] = "tampered creative action"
    normalized.write(JSON.pretty_generate(normalized_document))

    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", context_path,
      "--output", @tmp.join("authoring-mutation-result.json"), normalized
    )
    refute status.success?
    assert_includes stderr, "section_02a_authoring normalization mutated the Terra creative section payload"
  end

  def test_authoring_context_rejects_required_parent_cuts_and_nested_parent_truth_leaks
    context_path = write_authoring_context("S00", 1)
    context_document = JSON.parse(context_path.read)
    context_document["required_parent_cuts"] = [{"required_cut_id" => "C999_LEAK"}]
    context_document.dig("section_plan")["source_parent_cut"] = {"cut_id" => "C999_LEAK"}
    leaked_parent_truth = Marshal.load(Marshal.dump(cut("S00", 1)))
    leaked_parent_truth.delete("cut_id")
    leaked_parent_truth.delete("keyframe_shots")
    context_document.dig("section_plan")["leaked_parent_truth"] = leaked_parent_truth
    context_document.delete("section_context_sha256")
    context_document["section_context_sha256"] = Digest::SHA256.hexdigest(JSON.generate(context_document))
    context_path.write(JSON.pretty_generate(context_document))
    raw = authoring_shard(context_document, cut_count: 1)
    raw_path = write_json("authoring-leaked-input-raw.json", raw)
    log = execution_log_for(raw_path, context_path)

    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
      "--execution-log", log, "--output", @tmp.join("authoring-leaked-input-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "required_parent_cuts is forbidden in a section_02a_authoring input"
    assert_includes stderr, "source_parent_cut is forbidden in a section_02a_authoring input"
    assert_includes stderr, "contains a forbidden full parent-cut creative truth payload"
  end

  def test_authoring_rejects_cut_time_outside_section_bounds_and_raw_receipt_bypass
    context_path = write_authoring_context("S00", 1)
    context_document = JSON.parse(context_path.read)
    raw = authoring_shard(context_document, cut_count: 1)
    raw_path = write_json("authoring-raw-bypass.json", raw)
    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", "S00", "--context", context_path,
      "--output", @tmp.join("authoring-raw-bypass-result.json"), raw_path
    )
    refute status.success?
    assert_includes stderr, "deterministic_normalization_receipt is required"

    raw.dig("section", "storyboard_core_cuts", 0)["time_range"] = "3.900000-4.500000"
    out_of_bounds = write_json("authoring-out-of-bounds-raw.json", raw)
    log = execution_log_for(out_of_bounds, context_path)
    _stdout, stderr, status = run_cli_raw(
      "normalize-shard", out_of_bounds, "--allowlist", @allowlist, "--context", context_path,
      "--execution-log", log, "--output", @tmp.join("authoring-out-of-bounds-normalized.json")
    )
    refute status.success?
    assert_includes stderr, "time_range falls outside the section time bounds"
  end

  def test_authoring_accepts_negative_to_negative_and_negative_to_zero_time_ranges
    cases = {
      "negative-negative" => ["-8.000--4.000", "-8.000--6.400"],
      "negative-zero" => ["-8.000-0.000", "-8.000-0.000"]
    }

    cases.each do |name, (section_time_range, cut_time_range)|
      context_path = authoring_context_with_time_range(name, section_time_range)
      context_document = JSON.parse(context_path.read)
      raw = authoring_shard(context_document, cut_count: 1)
      raw.dig("section", "storyboard_core_cuts", 0)["time_range"] = cut_time_range
      raw_path = write_json("authoring-#{name}-raw.json", raw)
      normalized = normalize_authoring(raw_path, context_path, "authoring-#{name}-normalized.json")

      assert_equal cut_time_range,
        JSON.parse(normalized.read).dig("section", "storyboard_core_cuts", 0, "time_range")
    end
  end

  def test_authoring_rejects_malformed_decreasing_and_out_of_bounds_negative_time_ranges
    cases = {
      "malformed" => ["--8.000--6.400", "must be a valid increasing numeric range"],
      "decreasing" => ["-6.400--8.000", "must be a valid increasing numeric range"],
      "out-of-bounds" => ["-8.500--6.400", "falls outside the section time bounds"]
    }

    cases.each do |name, (cut_time_range, expected_error)|
      context_path = authoring_context_with_time_range(name, "-8.000-0.000")
      context_document = JSON.parse(context_path.read)
      raw = authoring_shard(context_document, cut_count: 1)
      raw.dig("section", "storyboard_core_cuts", 0)["time_range"] = cut_time_range
      raw_path = write_json("authoring-negative-#{name}-raw.json", raw)
      log = execution_log_for(raw_path, context_path)
      _stdout, stderr, status = run_cli_raw(
        "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
        "--execution-log", log, "--output", @tmp.join("authoring-negative-#{name}-normalized.json")
      )

      refute status.success?, name
      assert_includes stderr, expected_error, name
    end
  end

  def test_merge_rejects_mixed_child_and_section_authoring_modes
    authoring_context_path = write_authoring_context("S00", 1)
    authoring_raw = authoring_shard(JSON.parse(authoring_context_path.read), cut_count: 1)
    authoring_raw_path = write_json("authoring-mixed-raw.json", authoring_raw)
    authoring_normalized = normalize_authoring(authoring_raw_path, authoring_context_path, "authoring-mixed-normalized.json")
    child_normalized = normalize_for_merge(@shards.last, @contexts.last)

    _stdout, stderr, status = run_cli_raw(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","),
      "--context", authoring_context_path, "--context", @contexts.last,
      "--output", @tmp.join("mixed-mode-result.json"), authoring_normalized, child_normalized
    )
    refute status.success?
    assert_includes stderr, "mixed probe_mode contexts are forbidden"
  end

  private

  def source_set_digest(sources)
    pairs = sources.map { |source| [source.fetch("path"), source.fetch("sha256")] }.sort
    Digest::SHA256.hexdigest(JSON.generate(pairs))
  end

  def write_json(name, payload)
    path = @tmp.join(name)
    path.write("#{JSON.pretty_generate(payload)}\n")
    path
  end

  def compact_execution_attestation(raw_path, context_path)
    raw_document = JSON.parse(Pathname.new(raw_path).read)
    context_document = JSON.parse(Pathname.new(context_path).read)
    IdolStoryboardProbeContract.compact_execution_attestation(
      raw_path,
      raw_document,
      {
        "path" => Pathname.new(context_path).expand_path.cleanpath.to_s,
        "probe_mode" => context_document.fetch("probe_mode"),
        "section_id" => context_document.fetch("section_id")
      }
    )
  end

  def compact_execution_turn_rows(turn_id:, raw_path:, context_path:, model: "gpt-5.6-sol", effort: "xhigh")
    execution_turn_rows(
      turn_id: turn_id,
      raw_document: compact_execution_attestation(raw_path, context_path),
      context_path: context_path,
      model: model,
      effort: effort,
      user_message: "Compact receipt for #{Pathname.new(context_path).expand_path.cleanpath} and #{Pathname.new(raw_path).expand_path.cleanpath}"
    )
  end

  def execution_turn_rows(turn_id:, raw_document:, context_path:, model: "gpt-5.6-sol", effort: "xhigh", complete: true, include_context: true, user_message: nil)
    rows = [
      {"type" => "turn_context", "payload" => {"turn_id" => turn_id, "model" => model, "effort" => effort}},
      {
        "type" => "event_msg",
        "payload" => {
          "type" => "user_message",
          "message" => user_message || (include_context ? "Use bounded context #{Pathname.new(context_path).expand_path.cleanpath}" : "Use the supplied bounded context.")
        }
      },
      {
        "type" => "event_msg",
        "payload" => {"type" => "agent_message", "phase" => "final_answer", "message" => JSON.generate(raw_document)}
      }
    ]
    rows << {"type" => "event_msg", "payload" => {"type" => "task_complete", "turn_id" => turn_id}} if complete
    rows
  end

  def write_execution_log(name, rows)
    path = @tmp.join(name)
    path.write("#{rows.map { |row| JSON.generate(row) }.join("\n")}\n")
    path
  end

  def execution_log_for(raw_path, context_path, model: "gpt-5.6-sol", effort: "xhigh", complete: true, include_context: true)
    @execution_log_counter += 1
    raw_document = JSON.parse(Pathname.new(raw_path).read)
    rows = execution_turn_rows(
      turn_id: format("turn-%03d", @execution_log_counter),
      raw_document: raw_document,
      context_path: context_path,
      model: model,
      effort: effort,
      complete: complete,
      include_context: include_context
    )
    write_execution_log(format("execution-%03d.jsonl", @execution_log_counter), rows)
  end

  def rewrite_context(index, document)
    document.delete("section_context_sha256")
    digest = Digest::SHA256.hexdigest(JSON.generate(document))
    document["section_context_sha256"] = digest
    @contexts[index].write("#{JSON.pretty_generate(document)}\n")
    @context_digests[document["section_id"]] = digest
    digest
  end

  def shard(section_id, order)
    cut_number = order
    {
      "schema_version" => "idol_storyboard_probe_section.v1",
      "status" => "noncanonical_evaluation_only",
      "probe_mode" => "child_keyframe_elaboration",
      "harness_commit" => "f4fd3a8",
      "section_id" => section_id,
      "section_order" => order,
      "time_range" => order == 1 ? "0.000-4.000" : "4.000-8.000",
      "model_route" => {"model" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high"},
      "source_set_sha256" => @source_set_sha256,
      "section_context_sha256" => @context_digests.fetch(section_id),
      "previous_boundary" => previous_boundary(order),
      "next_boundary" => next_boundary(order),
      "section" => section_plan(section_id, order).merge("storyboard_core_cuts" => [cut(section_id, cut_number)])
    }
  end

  def context(section_id, order)
    parent_cut = Marshal.load(Marshal.dump(cut(section_id, order)))
    parent_cut.delete("keyframe_shots")
    parent_cut["cut_id"] = "LEGACY_#{section_id}_#{order}"
    {
      "schema_version" => "idol_storyboard_probe_section_input.v1",
      "status" => "noncanonical_evaluation_only",
      "probe_mode" => "child_keyframe_elaboration",
      "harness_commit" => "f4fd3a8",
      "section_id" => section_id,
      "section_order" => order,
      "time_range" => time_range(order),
      "model_route" => {"model" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high"},
      "source_set_sha256" => @source_set_sha256,
      "previous_boundary" => previous_boundary(order),
      "next_boundary" => next_boundary(order),
      "section_plan" => section_plan(section_id, order),
      "required_parent_cuts" => [
        {"required_cut_id" => cut(section_id, order)["cut_id"], "source_parent_cut" => parent_cut}
      ],
      "allowed_sources" => Marshal.load(Marshal.dump(@sources))
    }
  end

  def write_authoring_context(section_id, order, obligation_ids: ["OBL_#{section_id}_WHOLE_WINDOW"])
    plan = Marshal.load(Marshal.dump(section_plan(section_id, order)))
    plan["lock_id"] = "PLAN_#{section_id}"
    source_locks = @sources.each_with_index.map do |source, index|
      source.merge(
        "lock_id" => format("SRC_%s_%02d", section_id, index + 1),
        "source_path" => source.fetch("path")
      ).reject { |key, _value| key == "path" }
    end
    document = {
      "schema_version" => "idol_storyboard_probe_section_input.v2",
      "status" => "noncanonical_evaluation_only",
      "probe_mode" => "section_02a_authoring",
      "harness_commit" => "f4fd3a8",
      "section_id" => section_id,
      "section_order" => order,
      "time_range" => time_range(order),
      "model_route" => {"model" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high"},
      "source_set_sha256" => @source_set_sha256,
      "previous_boundary" => previous_boundary(order),
      "next_boundary" => next_boundary(order),
      "root_locked_envelope" => {
        "lock_id" => "ROOT_#{section_id}",
        "harness_commit" => "f4fd3a8",
        "section_id" => section_id,
        "section_order" => order,
        "time_range" => time_range(order),
        "model_route" => {"model" => "gpt-5.6-sol", "effort" => "xhigh", "verbosity" => "high"},
        "source_set_sha256" => @source_set_sha256
      },
      "section_plan" => plan,
      "whole_film_locks" => [
        {"lock_id" => "WHOLE_FILM_#{section_id}", "requirement" => "Advance the whole-film line without restating the thesis."}
      ],
      "boundary_locks" => [
        {"lock_id" => "BOUNDARY_PREVIOUS_#{section_id}", "boundary" => "previous", "text" => previous_boundary(order)},
        {"lock_id" => "BOUNDARY_NEXT_#{section_id}", "boundary" => "next", "text" => next_boundary(order)}
      ],
      "source_locks" => source_locks,
      "split_obligations" => obligation_ids.map do |obligation_id|
        {"obligation_id" => obligation_id, "requirement" => "Resolve #{obligation_id} in exactly one authored parent-cut assignment."}
      end
    }
    document["section_context_sha256"] = Digest::SHA256.hexdigest(JSON.generate(document))
    write_json("#{section_id}-authoring-context-#{obligation_ids.length}.json", document)
  end

  def authoring_context_with_time_range(name, time_range)
    source_path = write_authoring_context("S00", 1)
    document = JSON.parse(source_path.read)
    document["time_range"] = time_range
    document.dig("root_locked_envelope")["time_range"] = time_range
    document.dig("section_plan")["time_range"] = time_range
    document.delete("section_context_sha256")
    document["section_context_sha256"] = Digest::SHA256.hexdigest(JSON.generate(document))
    write_json("S00-authoring-#{name}-context.json", document)
  end

  def authoring_upstream_ids(context_document)
    [
      context_document.dig("root_locked_envelope", "lock_id"),
      context_document.dig("section_plan", "lock_id"),
      *Array(context_document["whole_film_locks"]).map { |row| row["lock_id"] },
      *Array(context_document["boundary_locks"]).map { |row| row["lock_id"] },
      *Array(context_document["source_locks"]).map { |row| row["lock_id"] }
    ]
  end

  def authoring_cut(section_id, order, index, total, upstream_refs:, obligation_refs:)
    result = Marshal.load(Marshal.dump(cut(section_id, order)))
    suffix = section_id.gsub(/[^A-Z0-9]/, "_")
    number = order * 1000 + index
    section_start = order == 1 ? 0.0 : 4.0
    left = section_start + (index - 1) * 4.0 / total
    right = section_start + index * 4.0 / total
    result["cut_id"] = format("C%04d_AUTH_%s", number, suffix)
    result["time_range"] = format("%.6f-%.6f", left, right)
    result["visible_action_or_hold"] = "Authored action #{index}: M01 redirects the practical line through one observable state change."
    result["continuity_in"] = index == 1 ? previous_boundary(order) : "inherit authored action #{index - 1}"
    result["continuity_out"] = index == total ? next_boundary(order) : "hand off to authored action #{index + 1}"
    result["upstream_lock_refs"] = upstream_refs
    result["split_obligation_refs"] = obligation_refs
    result["keyframe_shots"].each_with_index do |shot, shot_index|
      shot["keyframe_shot_id"] = format("KS_AUTH_%s_%04d_%02d", suffix, number, shot_index + 1)
      shot["packet_id"] = format("PKT_B%04d_AUTH_%s_%02d", number, suffix, shot_index + 1)
    end
    result
  end

  def authoring_shard(context_document, cut_count:, obligation_assignments: nil)
    upstream_ids = authoring_upstream_ids(context_document)
    obligation_ids = Array(context_document["split_obligations"]).map { |row| row["obligation_id"] }
    assignments = obligation_assignments || {0 => obligation_ids}
    cuts = cut_count.times.map do |offset|
      authoring_cut(
        context_document["section_id"],
        context_document["section_order"],
        offset + 1,
        cut_count,
        upstream_refs: offset.zero? ? upstream_ids : [],
        obligation_refs: Array(assignments[offset])
      )
    end
    section = Marshal.load(Marshal.dump(context_document["section_plan"]))
    section.dig("section_quality_check")["actual_core_cut_count"] = cuts.length
    section.dig("section_quality_check")["actual_keyframe_count"] = cuts.sum { |row| row["keyframe_shots"].length }
    section["storyboard_core_cuts"] = cuts
    {
      "schema_version" => "idol_storyboard_probe_section.v1",
      "status" => "noncanonical_evaluation_only",
      "probe_mode" => "section_02a_authoring",
      "harness_commit" => context_document["harness_commit"],
      "section_id" => context_document["section_id"],
      "section_order" => context_document["section_order"],
      "time_range" => context_document["time_range"],
      "model_route" => Marshal.load(Marshal.dump(context_document["model_route"])),
      "source_set_sha256" => context_document["source_set_sha256"],
      "section_context_sha256" => context_document["section_context_sha256"],
      "previous_boundary" => context_document["previous_boundary"],
      "next_boundary" => context_document["next_boundary"],
      "section" => section
    }
  end

  def normalize_authoring(raw_path, context_path, name)
    log = execution_log_for(raw_path, context_path)
    output = @tmp.join(name)
    run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
      "--execution-log", log, "--output", output, "--json"
    )
    output
  end

  def section_plan(section_id, order)
    {
      "section_id" => section_id,
      "time_range" => time_range(order),
      "section_story_job" => "A bounded evaluation-only screen event for #{section_id}.",
      "reference_dispositions" => [
        {"source_path" => @sources[order - 1]["path"], "function" => "camera and object relation"}
      ],
      "section_quality_check" => {"actual_core_cut_count" => 1, "actual_keyframe_count" => 2}
    }
  end

  def time_range(order)
    order == 1 ? "0.000-4.000" : "4.000-8.000"
  end

  def previous_boundary(order)
    order == 1 ? "song entry from black" : "previous hand remains on the line"
  end

  def next_boundary(order)
    order == 2 ? "last hand releases the line" : "the hand direction continues into S01"
  end

  def cut(section_id, number)
    suffix = section_id.gsub(/[^A-Z0-9]/, "_")
    {
      "cut_id" => format("C%03d_%s_OPEN", number, suffix),
      "time_range" => "#{number - 1}.000-#{number}.000",
      "audio_cue" => "the section bass accent lands",
      "visible_action_or_hold" => "M01 places one hand on the floor line and holds the wrist still.",
      "composition" => "M01 stays on the left third while the floor line crosses foreground to background.",
      "camera" => {
        "height" => "waist height",
        "shot_scale_distance" => "medium-wide at four metres",
        "direction_angle" => "three-quarter left angle",
        "depth_framing" => "hand foreground, member midground, open route background",
        "movement_or_hold" => "short lateral track then locked hold",
        "screen_placement_crop" => "full hand and feet remain inside the left two thirds",
        "readability_reason" => "the hand contact and opened route remain visible together"
      },
      "continuity_in" => "the prior line direction enters from frame left",
      "continuity_out" => "the held wrist sends the line toward the next section",
      "reference_uses" => [
        {"source_path" => @sources[number - 1]["path"], "function" => "camera geometry only"}
      ],
      "keyframe_shots" => [
        keyframe_shot(section_id, number, 1, sequence: 10, face_visible: true),
        keyframe_shot(section_id, number, 2, sequence: 30, face_visible: false)
      ],
      "image_prompt_blueprint" => "Photorealistic M01, floor line, full hand contact, waist-height medium-wide camera, no text."
    }
  end

  def keyframe_shot(section_id, cut_number, shot_number, sequence:, face_visible:)
    suffix = section_id.gsub(/[^A-Z0-9]/, "_")
    shot = {
      "keyframe_shot_id" => format("KS_%s_%03d_%03d", suffix, cut_number, shot_number),
      "packet_id" => format("PKT_B%02d_%s_%03d", cut_number, suffix, shot_number),
      "shot_role" => shot_number == 1 ? "hand approaches line" : "line remains after contact",
      "shot_sequence" => sequence,
      "visible_action" => shot_number == 1 ? "M01 lowers the hand toward the line" : "the line stays open under the held hand",
      "composition_lock" => "hand in foreground and route in background",
      "camera_treatment" => "waist-height three-quarter hold",
      "shot_scale" => "medium-wide",
      "space_or_object" => "practical floor line",
      "required_visibility" => ["hand", "floor line", "route depth"],
      "render_facing_action_cue" => "show the exact hand-to-line state without adding motion",
      "continuity_in" => "inherit the prior hand direction",
      "continuity_out" => "preserve the line direction into the next ordered frame",
      "visible_member_focus" => face_visible ? ["M01"] : [],
      "identity_compile_input" => face_visible ? visible_identity("M01") : no_face_identity
    }
    shot
  end

  def visible_identity(member)
    {
      "face_visible" => true,
      "face_visibility_reason" => "M01 face remains readable beside the hand action.",
      "identity_focus_members" => [member],
      "identity_reference_source" => "member_registry_face_only",
      "scene_reference_mode" => "text_locks_only"
    }
  end

  def no_face_identity
    {
      "face_visible" => false,
      "face_visibility_reason" => "The crop shows only the hand, object, and floor route.",
      "identity_focus_members" => [],
      "identity_reference_source" => "none",
      "scene_reference_mode" => "text_locks_only"
    }
  end

  def merge!(shards)
    normalized = shards.map do |shard_path|
      document = JSON.parse(Pathname.new(shard_path).read)
      context_path = @contexts.find do |candidate|
        JSON.parse(candidate.read)["section_id"].to_s == document["section_id"].to_s
      end
      normalize_for_merge(shard_path, context_path)
    end
    shards.replace(normalized)
    run_cli(
      "merge", "--allowlist", @allowlist, "--sections", SECTIONS.join(","), "--output", @result, *shards, "--json"
    )
  end

  def normalize_for_merge(raw_path, context_path)
    raise "missing context for #{raw_path}" unless context_path

    @normalized_shard_counter += 1
    execution_log = execution_log_for(raw_path, context_path)
    output = @tmp.join(format("merge-normalized-%03d.json", @normalized_shard_counter))
    run_cli(
      "normalize-shard", raw_path, "--allowlist", @allowlist, "--context", context_path,
      "--execution-log", execution_log, "--output", output
    )
    output
  end

  def run_cli(*args)
    stdout, stderr, status = run_cli_raw(*args)
    assert status.success?, "command failed: #{args.join(' ')}\nstdout=#{stdout}\nstderr=#{stderr}"
    [stdout, stderr, status]
  end

  def run_cli_raw(*args)
    values = args.map(&:to_s)
    command = values.shift
    unless values.include?("--context")
      @contexts.reverse_each do |context_path|
        values.unshift(context_path.to_s)
        values.unshift("--context")
      end
    end
    values.unshift(@repo_root.to_s)
    values.unshift("--repo-root")
    Open3.capture3(RbConfig.ruby, SCRIPT.to_s, command, *values, chdir: ROOT.to_s)
  end
end
