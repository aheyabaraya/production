# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require_relative "../lib/idol_source_connection_contract"

class IdolSourceConnectionContractTest < Minitest::Test
  def setup
    @root = Pathname.new(Dir.mktmpdir("source-connection-"))
    @file = @root.join("refs", "door.txt")
    @file.dirname.mkpath
    @file.write("door-kick still")
    @sha = Digest::SHA256.file(@file).hexdigest
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && @root.exist?
  end

  def pointer(overrides = {})
    {
      "source_id" => "SEQ_DOOR",
      "path" => "refs/door.txt",
      "locator" => "t=00:12",
      "function" => "visible_action_or_hold",
      "disposition" => "applied"
    }.merge(overrides)
  end

  def test_unstamped_path_is_not_connected
    connection = IdolSourceConnectionContract.connection_of(@root, pointer)
    assert_equal "not_connected", connection["status"]
    assert_equal "unstamped", connection["reason"]
  end

  def test_stamp_copies_disk_sha_and_keeps_creative_fields
    result = IdolSourceConnectionContract.stamp(@root, pointer)
    assert result["stamped"]
    assert_equal "connected", result.dig("connection", "status")
    assert_equal @sha, result.dig("row", "sha256")
    assert_equal "visible_action_or_hold", result.dig("row", "function")
    assert_equal "applied", result.dig("row", "disposition")
    assert_equal "t=00:12", result.dig("row", "locator")
  end

  def test_matching_sha_is_connected
    connection = IdolSourceConnectionContract.connection_of(@root, pointer("sha256" => @sha))
    assert_equal "connected", connection["status"]
  end

  def test_stale_sha_is_not_connected_until_stamp
    stale = "a" * 64
    connection = IdolSourceConnectionContract.connection_of(@root, pointer("sha256" => stale))
    assert_equal "not_connected", connection["status"]
    assert_equal "stale_sha256", connection["reason"]

    result = IdolSourceConnectionContract.stamp(@root, pointer("sha256" => stale))
    assert_equal "connected", result.dig("connection", "status")
    assert_equal @sha, result.dig("row", "sha256")
    assert_equal "visible_action_or_hold", result.dig("row", "function")
  end

  def test_missing_file_is_not_connected_and_not_stamped
    result = IdolSourceConnectionContract.stamp(@root, pointer("path" => "refs/missing.txt"))
    refute result["stamped"]
    assert_equal "not_connected", result.dig("connection", "status")
    assert_equal "missing_file", result.dig("connection", "reason")
    assert_nil result.dig("row", "sha256")
  end

  def test_model_facing_omits_hex
    result = IdolSourceConnectionContract.stamp(@root, pointer)
    facing = IdolSourceConnectionContract.model_facing(result.fetch("row"), result.fetch("connection"))
    refute facing.key?("sha256")
    assert_equal "SEQ_DOOR", facing["source_id"]
    assert_equal "refs/door.txt", facing["path"]
    assert_equal "connected", facing.dig("connection", "status")
    assert_equal @sha, result.dig("row", "sha256")
  end

  def test_envelope_keeps_sha
    result = IdolSourceConnectionContract.stamp(@root, pointer)
    envelope = IdolSourceConnectionContract.envelope(result.fetch("row"))
    assert_equal @sha, envelope["sha256"]
  end

  def test_stamp_cli_twice_then_model_facing_omits_hex
    cli = Pathname.new(__dir__).join("..", "idol_stamp_source_connections.rb")
    payload = JSON.generate("rows" => [pointer, pointer("source_id" => "MISSING", "path" => "refs/missing.txt")])
    first, stderr, status = Open3.capture3(RbConfig.ruby, cli.to_s, "--root", @root.to_s, stdin_data: payload)
    refute_equal 0, status.exitstatus, stderr
    first_doc = JSON.parse(first)
    existing = first_doc.fetch("rows").find { |row| row.dig("row", "source_id") == "SEQ_DOOR" }
    missing = first_doc.fetch("rows").find { |row| row.dig("row", "source_id") == "MISSING" }
    assert_equal "connected", existing.dig("connection", "status")
    assert_equal @sha, existing.dig("row", "sha256")
    assert_equal "visible_action_or_hold", existing.dig("row", "function")
    refute missing.fetch("stamped")
    assert_equal "not_connected", missing.dig("connection", "status")

    second, _stderr, status = Open3.capture3(RbConfig.ruby, cli.to_s, "--root", @root.to_s, stdin_data: first)
    refute_equal 0, status.exitstatus
    second_existing = JSON.parse(second).fetch("rows").find { |row| row.dig("row", "source_id") == "SEQ_DOOR" }
    assert_equal "connected", second_existing.dig("connection", "status")
    assert_equal @sha, second_existing.dig("row", "sha256")
    refute second_existing.fetch("stamped")

    facing, _stderr, status = Open3.capture3(
      RbConfig.ruby, cli.to_s, "--root", @root.to_s, "--model-facing",
      stdin_data: JSON.generate("rows" => [existing.fetch("row")])
    )
    assert status.success?
    facing_row = JSON.parse(facing).fetch("rows").first
    refute facing_row.key?("sha256")
    assert_equal "connected", facing_row.dig("connection", "status")
  end

  def test_project_rows_does_not_stamp_unstamped_or_missing
    unstamped = IdolSourceConnectionContract.project_rows(@root, [pointer]).first
    refute unstamped.key?("sha256")
    assert_equal "not_connected", unstamped.dig("connection", "status")
    assert_equal "unstamped", unstamped.dig("connection", "reason")

    missing = IdolSourceConnectionContract.project_rows(@root, [pointer("path" => "refs/missing.txt")]).first
    refute missing.key?("sha256")
    assert_equal "not_connected", missing.dig("connection", "status")
    assert_equal "missing_file", missing.dig("connection", "reason")
  end

  def test_model_facing_rows_is_check_only_for_stale_sha
    facing = IdolSourceConnectionContract.model_facing_rows(@root, [pointer("sha256" => "a" * 64)]).first
    refute facing.key?("sha256")
    assert_equal "not_connected", facing.dig("connection", "status")
    assert_equal "stale_sha256", facing.dig("connection", "reason")
  end

  def test_model_facing_cli_holds_stale_and_unstamped_without_stamping
    cli = Pathname.new(__dir__).join("..", "idol_stamp_source_connections.rb")
    stale = pointer("sha256" => "a" * 64)
    unstamped = pointer("source_id" => "UNSTAMPED")
    facing, stderr, status = Open3.capture3(
      RbConfig.ruby, cli.to_s, "--root", @root.to_s, "--model-facing",
      stdin_data: JSON.generate("rows" => [stale, unstamped])
    )
    refute_equal 0, status.exitstatus, stderr
    rows = JSON.parse(facing).fetch("rows")
    stale_row = rows.find { |row| row["source_id"] == "SEQ_DOOR" }
    unstamped_row = rows.find { |row| row["source_id"] == "UNSTAMPED" }
    refute stale_row.key?("sha256")
    assert_equal "not_connected", stale_row.dig("connection", "status")
    assert_equal "stale_sha256", stale_row.dig("connection", "reason")
    refute unstamped_row.key?("sha256")
    assert_equal "not_connected", unstamped_row.dig("connection", "status")
    assert_equal "unstamped", unstamped_row.dig("connection", "reason")
  end

  def test_in_root_symlink_is_connected_to_target_sha
    link = @root.join("refs", "alias.txt")
    File.symlink("door.txt", link.to_s)
    connection = IdolSourceConnectionContract.connection_of(@root, pointer("path" => "refs/alias.txt", "sha256" => @sha))
    assert_equal "connected", connection["status"]
    result = IdolSourceConnectionContract.stamp(@root, pointer("path" => "refs/alias.txt"))
    assert result["stamped"]
    assert_equal @sha, result.dig("row", "sha256")
  end

  def test_escaped_symlink_is_not_connected_and_not_stamped
    outside = Pathname.new(Dir.mktmpdir("source-connection-outside-"))
    begin
      target = outside.join("decoy.txt")
      target.write("escaped-decoy")
      link = @root.join("refs", "escape.txt")
      File.symlink(target.to_s, link.to_s)
      connection = IdolSourceConnectionContract.connection_of(@root, pointer("path" => "refs/escape.txt"))
      assert_equal "not_connected", connection["status"]
      assert_equal "path_escapes_root", connection["reason"]
      result = IdolSourceConnectionContract.stamp(@root, pointer("path" => "refs/escape.txt"))
      refute result["stamped"]
      assert_equal "path_escapes_root", result.dig("connection", "reason")
      assert_nil result.dig("row", "sha256")
    ensure
      FileUtils.remove_entry(outside) if outside && outside.exist?
    end
  end

  def test_missing_file_under_logical_and_canonical_tmp_root_is_missing_file
    logical = Pathname.new(@root.to_s)
    canonical = @root.realpath
    logical_missing = IdolSourceConnectionContract.connection_of(logical, pointer("path" => "refs/missing.txt"))
    assert_equal "not_connected", logical_missing["status"]
    assert_equal "missing_file", logical_missing["reason"]
    canonical_missing = IdolSourceConnectionContract.connection_of(canonical, pointer("path" => "refs/missing.txt"))
    assert_equal "not_connected", canonical_missing["status"]
    assert_equal "missing_file", canonical_missing["reason"]
    logical_existing = IdolSourceConnectionContract.connection_of(logical, pointer("path" => "refs/door.txt", "sha256" => @sha))
    assert_equal "connected", logical_existing["status"]
    canonical_existing = IdolSourceConnectionContract.connection_of(canonical, pointer("path" => "refs/door.txt", "sha256" => @sha))
    assert_equal "connected", canonical_existing["status"]
  end
end
