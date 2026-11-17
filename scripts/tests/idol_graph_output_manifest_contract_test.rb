# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"

require_relative "../lib/idol_graph_output_manifest_contract"

class IdolGraphOutputManifestContractTest < Minitest::Test
  def setup
    @sandbox = Pathname.new(Dir.mktmpdir("idol-graph-output-manifest-", "/private/tmp"))
    @root = @sandbox.join("repo")
    @root.mkpath
    @output_path = @root.join("runs/fixture/work/outputs/result.yaml")
    @output_path.dirname.mkpath
    @output_path.write("result: exact\n")
    @dispatch = {
      "dispatch_id" => "DISPATCH_FIXTURE_A",
      "assigned_owner" => "fixture-worker-a",
      "input_digest_sha256" => "4" * 64,
      "bounded_output" => {
        "output_kind" => "fixture_result",
        "expected_paths" => [relative(@output_path)],
        "maximum_artifact_count" => 1
      }
    }
    @manifest_path = @root.join("runs/fixture/work/manifests/dispatch-a.yaml")
    write_manifest
  end

  def teardown
    FileUtils.remove_entry(@sandbox) if @sandbox&.directory?
  end

  def test_verifies_exact_manifest_and_output_bytes
    result = verify(pointer)

    assert_equal "DISPATCH_FIXTURE_A", result.fetch("dispatch_id")
    assert_equal sha(@manifest_path), result.fetch("manifest_sha256")
    assert_equal relative(@output_path), result.fetch("outputs").first.fetch("path")
    assert_equal sha(@output_path), result.fetch("outputs").first.fetch("sha256")
  end

  def test_rejects_null_manifest
    assert_contract_error("null_manifest") { verify(nil) }
  end

  def test_rejects_stale_manifest_sha
    stale = pointer.merge("sha256" => "f" * 64)

    assert_contract_error("stale_manifest_sha") { verify(stale) }
  end

  def test_rejects_manifest_path_outside_repository
    outside = @sandbox.join("outside-manifest.yaml")
    outside.write(@manifest_path.read)
    outside_pointer = {"path" => "../outside-manifest.yaml", "sha256" => sha(outside)}

    assert_contract_error("path_escapes_repository") { verify(outside_pointer) }
  end

  def test_rejects_absolute_manifest_path_even_when_inside_repository
    absolute_pointer = {"path" => @manifest_path.to_s, "sha256" => sha(@manifest_path)}

    assert_contract_error("path_not_repository_relative") { verify(absolute_pointer) }
  end

  def test_rejects_dispatch_id_mismatch
    write_manifest("dispatch_id" => "DISPATCH_OTHER")

    assert_contract_error("manifest_identity_mismatch") { verify(pointer) }
  end

  def test_rejects_wrong_manifest_schema_version
    write_manifest("schema_version" => "idol-graph-output-manifest.v0")

    assert_contract_error("manifest_identity_mismatch") { verify(pointer) }
  end

  def test_rejects_wrong_manifest_artifact_type
    write_manifest("artifact_type" => "other_dispatch_manifest")

    assert_contract_error("manifest_identity_mismatch") { verify(pointer) }
  end

  def test_rejects_assigned_owner_mismatch
    write_manifest("assigned_owner" => "different-worker")

    assert_contract_error("manifest_identity_mismatch") { verify(pointer) }
  end

  def test_rejects_input_digest_mismatch
    write_manifest("input_digest_sha256" => "9" * 64)

    assert_contract_error("manifest_identity_mismatch") { verify(pointer) }
  end

  def test_rejects_manifest_reuse_by_another_dispatch
    other_dispatch = @dispatch.merge(
      "dispatch_id" => "DISPATCH_FIXTURE_B",
      "assigned_owner" => "fixture-worker-b",
      "input_digest_sha256" => "5" * 64
    )

    assert_contract_error("manifest_identity_mismatch") { verify(pointer, other_dispatch) }
  end

  def test_rejects_missing_output_file
    write_manifest("outputs" => [{"path" => "runs/fixture/work/outputs/missing.yaml", "sha256" => "a" * 64}])

    assert_contract_error("missing_file") { verify(pointer) }
  end

  def test_rejects_stale_output_sha
    write_manifest("outputs" => [{"path" => relative(@output_path), "sha256" => "a" * 64}])

    assert_contract_error("stale_output_sha") { verify(pointer) }
  end

  def test_rejects_output_path_outside_repository
    outside = @sandbox.join("outside-result.yaml")
    outside.write("result: outside\n")
    write_manifest("outputs" => [{"path" => "../outside-result.yaml", "sha256" => sha(outside)}])

    assert_contract_error("path_escapes_repository") { verify(pointer) }
  end

  def test_rejects_empty_outputs
    write_manifest("outputs" => [])

    assert_contract_error("outputs_missing") { verify(pointer) }
  end

  def test_rejects_duplicate_output_paths
    output = {"path" => relative(@output_path), "sha256" => sha(@output_path)}
    write_manifest("outputs" => [output, output.dup])

    assert_contract_error("duplicate_output") { verify(pointer) }
  end

  def test_rejects_valid_repo_file_outside_dispatch_scope
    unrelated = @root.join("work/unrelated.yaml")
    unrelated.dirname.mkpath
    unrelated.write("result: unrelated\n")
    write_manifest("outputs" => [{"path" => relative(unrelated), "sha256" => sha(unrelated)}])

    assert_contract_error("output_scope_mismatch") { verify(pointer) }
  end

  def test_rejects_output_kind_drift
    write_manifest("output_kind" => "other_kind")

    assert_contract_error("output_kind_mismatch") { verify(pointer) }
  end

  private

  def verify(manifest_pointer, dispatch = @dispatch)
    IdolGraphOutputManifestContract.verify!(root: @root, pointer: manifest_pointer, dispatch: dispatch)
  end

  def assert_contract_error(code)
    error = assert_raises(IdolGraphOutputManifestContract::ContractError) { yield }
    assert_equal code, error.code
    error
  end

  def write_manifest(overrides = {})
    manifest = {
      "schema_version" => IdolGraphOutputManifestContract::SCHEMA_VERSION,
      "artifact_type" => IdolGraphOutputManifestContract::ARTIFACT_TYPE,
      "dispatch_id" => @dispatch.fetch("dispatch_id"),
      "assigned_owner" => @dispatch.fetch("assigned_owner"),
      "input_digest_sha256" => @dispatch.fetch("input_digest_sha256"),
      "output_kind" => @dispatch.dig("bounded_output", "output_kind"),
      "outputs" => [{"path" => relative(@output_path), "sha256" => sha(@output_path)}]
    }.merge(overrides)
    @manifest_path.dirname.mkpath
    @manifest_path.write(YAML.dump(manifest))
  end

  def pointer
    {"path" => relative(@manifest_path), "sha256" => sha(@manifest_path)}
  end

  def relative(path)
    path.relative_path_from(@root).to_s
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end
end
