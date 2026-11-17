# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "yaml"

require_relative "../idol_department_transport_refresh"
require_relative "support/department_dispatch_profile_fixture"

class IdolDepartmentTransportRefreshTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  REFRESH_SCRIPT = ROOT.join("scripts", "idol_department_transport_refresh.rb")
  DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_department_dispatch.rb")

  def setup
    @run = ROOT.join("runs", "harness-test", "transport-refresh", "RUN_#{SecureRandom.hex(4).upcase}")
    @dispatch_id = "TRANSPORT_#{SecureRandom.hex(3).upcase}"
    @artifact = @run.join("00A-song-lock.yaml")
    @dispatch = @run.join("work", "department-dispatches", "#{@dispatch_id}.yaml")
    @artifact.dirname.mkpath
    @dispatch.dirname.mkpath
    @artifact.write("schema_version: '1.5'\nstatus: locked\n")
    @document = dispatch_fixture_promoted_document(
      run_path: @run,
      dispatch_id: @dispatch_id,
      stage_id: "song_production_lock",
      artifact_path: @artifact,
      owner_role: "song_room",
      profile_id: "song_room_00a",
      checkpoint_id: "selected_audio_analysis"
    )
    # The shared fixture intentionally reuses Ruby objects before serialization;
    # break those in-memory aliases so each receipt pointer can drift alone.
    @document = JSON.parse(JSON.generate(@document))
    @dispatch.write(YAML.dump(@document))
  end

  def teardown
    FileUtils.remove_entry(@run) if @run&.directory?
    title = @run&.parent
    title.rmdir if title&.directory? && title.children.empty?
    album = title&.parent
    album.rmdir if album&.directory? && album.children.empty?
    harness = album&.parent
    harness.rmdir if harness&.directory? && harness.children.empty?
  end

  def test_one_bad_duplicate_hash_closes_mechanically_without_goal_or_submission
    original_artifact_sha = Digest::SHA256.file(@artifact.to_s).hexdigest
    original_submission = @document.dig("review_submission", "submission_number")
    @document.dig("runtime_return", "wake_event", "output_pointers", 0)["sha256"] = "a" * 66
    refresh_raw_result_digest(@document)
    @dispatch.write(YAML.dump(@document))

    classification = classify
    assert_equal "mechanical_refresh_eligible", classification.fetch("status"), JSON.pretty_generate(classification)
    assert_equal false, classification.fetch("native_goal_opened")
    assert_equal false, classification.fetch("review_submission_incremented")

    stdout, stderr, status = cli(
      REFRESH_SCRIPT,
      "write",
      "--json",
      "--owner",
      "fixture-mechanical-coordinator",
      "--created-at",
      "2026-08-13T00:00:00Z",
      relative(@dispatch)
    )
    assert status.success?, [stdout, stderr].join("\n")
    receipt_result = JSON.parse(stdout)
    receipt = ROOT.join(receipt_result.fetch("receipt_path"))
    assert receipt.file?

    raw_stdout, _raw_stderr, raw_status = cli(DISPATCH_VALIDATOR, "--json", relative(@dispatch))
    refute raw_status.success?
    assert_includes JSON.parse(raw_stdout).fetch("errors").join("\n"), "wake event output pointers must exact-copy runtime outputs"

    stdout, stderr, status = cli(
      DISPATCH_VALIDATOR,
      "--require-promoted",
      "--transport-refresh",
      relative(receipt),
      "--json",
      relative(@dispatch)
    )
    assert status.success?, [stdout, stderr].join("\n")
    result = JSON.parse(stdout)
    assert_equal original_submission, result.fetch("review_submission_number")
    assert_equal false, result.fetch("transport_refresh_consumed_goal")
    assert_equal false, result.fetch("transport_refresh_consumed_review_submission")
    assert_equal original_artifact_sha, Digest::SHA256.file(@artifact.to_s).hexdigest
    assert_equal "a" * 66, YAML.safe_load(@dispatch.read, aliases: true).dig("runtime_return", "wake_event", "output_pointers", 0, "sha256")
  end

  def test_changed_governing_input_routes_once_to_director_and_writes_no_receipt
    source_path = ROOT.join(@document.dig("launch", "required_skills", 0, "path"))
    current = Digest::SHA256.file(source_path.to_s).hexdigest
    stale = current == ("b" * 64) ? ("c" * 64) : ("b" * 64)
    replace_path_hash_everywhere!(@document, relative(source_path), stale)
    refresh_raw_digests(@document)
    @dispatch.write(YAML.dump(@document))

    classification = classify
    assert_equal "director_input_impact_recheck_required", classification.fetch("status")
    assert_equal "original_recipient_director", classification.fetch("next_owner")
    assert_equal false, classification.fetch("native_goal_opened")
    assert_equal false, classification.fetch("review_submission_incremented")

    stdout, _stderr, status = cli(
      REFRESH_SCRIPT,
      "write",
      "--json",
      "--owner",
      "fixture-mechanical-coordinator",
      relative(@dispatch)
    )
    refute status.success?
    assert_includes JSON.parse(stdout).fetch("errors").join("\n"), "director_input_impact_recheck_required"
    refute @run.join("work", "department-transport-refreshes").directory?
  end

  def test_changed_creative_output_never_enters_mechanical_refresh
    @artifact.write("schema_version: '1.5'\nstatus: changed-after-review\n")
    classification = classify
    assert_equal "director_output_receipt_recheck_required", classification.fetch("status"), JSON.pretty_generate(classification)
    assert_equal 0, classification.fetch("refresh_target_count")
    assert_equal false, classification.fetch("native_goal_opened")
  end

  def test_tampered_receipt_cannot_project_a_creative_output_hash
    @document.dig("runtime_return", "wake_event", "output_pointers", 0)["sha256"] = "a" * 66
    refresh_raw_result_digest(@document)
    @dispatch.write(YAML.dump(@document))
    receipt_path = IdolDepartmentTransportRefresh.write_receipt(
      @dispatch,
      owner: "fixture-mechanical-coordinator",
      created_at: "2026-08-13T00:00:00Z"
    )
    receipt = YAML.safe_load(receipt_path.read, aliases: true)
    receipt.fetch("bindings").first["target_json_pointer"] = "/runtime_return/outputs/0/sha256"
    receipt["receipt_sha256"] = IdolDepartmentTransportRefresh.structured_sha256(
      IdolDepartmentTransportRefresh.receipt_without_digest(receipt)
    )
    receipt_path.write(YAML.dump(receipt))

    error = assert_raises(IdolDepartmentTransportRefresh::ValidationError) do
      IdolDepartmentTransportRefresh.validate_receipt(receipt_path)
    end
    assert_includes error.errors.join("\n"), "must exact-cover"
  end

  private

  def classify
    stdout, stderr, status = cli(REFRESH_SCRIPT, "classify", "--json", relative(@dispatch))
    assert status.success?, [stdout, stderr].join("\n")
    JSON.parse(stdout)
  end

  def cli(script, *args)
    Open3.capture3(RbConfig.ruby, script.to_s, *args, chdir: ROOT.to_s)
  end

  def relative(path)
    Pathname.new(path).relative_path_from(ROOT).to_s
  end

  def replace_path_hash_everywhere!(value, path, replacement)
    case value
    when Hash
      if value["path"].to_s == path && value.key?("sha256")
        value["sha256"] = replacement
      end
      if value["registry_path"].to_s == path && value.key?("registry_sha256")
        value["registry_sha256"] = replacement
      end
      if value["evidence_locator"].to_s == path && value.key?("evidence_sha256")
        value["evidence_sha256"] = replacement
      end
      if value["locator"].to_s == path && value.key?("source_sha256")
        value["source_sha256"] = replacement
      end
      value.each_value { |child| replace_path_hash_everywhere!(child, path, replacement) }
    when Array
      value.each { |child| replace_path_hash_everywhere!(child, path, replacement) }
    end
  end

  def refresh_raw_digests(document)
    compiled = document.dig("launch", "compiled_launch_prompt")
    compiled_basis = compiled.reject do |key, _value|
      %w[rendered_prompt compiled_input_sha256 rendered_prompt_sha256].include?(key)
    end
    compiled["compiled_input_sha256"] = dispatch_fixture_structured_sha(compiled_basis)
    document.dig("runtime_return", "input_digest")["sha256"] = dispatch_fixture_structured_sha(
      "lineage" => document.fetch("lineage"),
      "review_submission" => document.fetch("review_submission"),
      "launch" => document.fetch("launch")
    )
    refresh_raw_result_digest(document)
  end

  def refresh_raw_result_digest(document)
    runtime = document.fetch("runtime_return")
    result_basis = %w[
      work_started_at runtime_owner runtime_goal skill_revisions
      mechanical_compliance_receipt worker_fulfillment_claims output_inventory
      outputs hold_reasons wake_event
    ].to_h { |key| [key, runtime[key]] }
    runtime.dig("result_digest")["sha256"] = dispatch_fixture_structured_sha(result_basis)
  end
end
