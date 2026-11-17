# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

# Exact-copy SHA seal for model-authored source pointers.
# Scripts never fill function, disposition, locator, or observations.
# Models never compare hex; they write source_id + path + locator.
module IdolSourceConnectionContract
  CONTRACT_VERSION = "source_connection.v1"
  STATUSES = %w[connected not_connected hold].freeze
  SHA256 = /\A[a-f0-9]{64}\z/
  CREATIVE_FIELDS = %w[
    function
    disposition
    locator
    role_groups
    purpose
    observed_space
    observed_subject
    observed_action_or_hold
    observed_staging
    observed_still_camera
  ].freeze
  MODEL_FACING_FIELDS = %w[
    source_id
    path
    locator
    function
    role_groups
    disposition
    purpose
  ].freeze

  module_function

  def file_sha256(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def resolve_path(root, relative)
    root = Pathname.new(root).expand_path.cleanpath
    relative = relative.to_s
    return nil if relative.empty?

    candidate = Pathname.new(relative)
    real_root = begin
      root.exist? ? root.realpath : root
    rescue Errno::ENOENT, Errno::ELOOP
      root
    end
    path = if candidate.absolute?
             candidate.expand_path.cleanpath
           else
             real_root.join(relative).expand_path.cleanpath
           end
    real_path = begin
      path.exist? ? path.realpath : path
    rescue Errno::ENOENT, Errno::ELOOP
      path
    end
    return real_path if real_path.to_s.start_with?("#{real_root}/") || real_path == real_root
    return nil if path.exist?
    return nil unless path.to_s.start_with?("#{root}/") || path == root

    real_root.join(path.relative_path_from(root))
  end

  def connection_of(root, row)
    row = stringify_keys(row)
    relative = row["path"].to_s
    if relative.empty?
      return status("not_connected", "missing_path")
    end

    path = resolve_path(root, relative)
    if path.nil?
      return status("not_connected", "path_escapes_root")
    end
    unless path.file?
      return status("not_connected", "missing_file")
    end

    actual = file_sha256(path)
    declared = row["sha256"].to_s
    if declared.empty?
      return status("not_connected", "unstamped").merge("disk_sha256" => actual)
    end
    unless declared.match?(SHA256)
      return status("not_connected", "malformed_sha256")
    end
    if declared != actual
      return status("not_connected", "stale_sha256").merge("disk_sha256" => actual)
    end

    status("connected", "path_matches_disk")
  end

  def stamp(root, row)
    row = stringify_keys(row)
    before_creative = snapshot_creative(row)
    connection = connection_of(root, row)
    if connection["status"] == "not_connected" && %w[missing_path missing_file malformed_sha256 path_escapes_root].include?(connection["reason"])
      return {
        "row" => row,
        "connection" => connection,
        "stamped" => false
      }
    end

    path = resolve_path(root, row["path"])
    sealed = row.merge("sha256" => file_sha256(path))
    after_creative = snapshot_creative(sealed)
    if before_creative != after_creative
      raise "source-connection stamp-in filled a creative field"
    end

    {
      "row" => sealed,
      "connection" => status("connected", "path_matches_disk"),
      "stamped" => sealed["sha256"] != row["sha256"].to_s
    }
  end

  def model_facing(row, connection = nil)
    row = stringify_keys(row)
    connection ||= { "status" => "hold", "reason" => "connection_not_projected" }
    facing = MODEL_FACING_FIELDS.each_with_object({}) do |key, out|
      out[key] = row[key] if row.key?(key)
    end
    facing["connection"] = {
      "status" => connection.fetch("status"),
      "reason" => connection.fetch("reason")
    }
    facing
  end

  def envelope(row)
    stringify_keys(row)
  end

  def stamp_rows(root, rows)
    Array(rows).map { |row| stamp(root, row) }
  end

  def project_rows(root, rows)
    Array(rows).map do |row|
      row = stringify_keys(row)
      model_facing(row, connection_of(root, row))
    end
  end

  def model_facing_rows(root, rows)
    project_rows(root, rows)
  end

  def snapshot_creative(row)
    CREATIVE_FIELDS.each_with_object({}) { |key, out| out[key] = row[key] }
  end

  def stringify_keys(row)
    raise ArgumentError, "source pointer must be an object" unless row.is_a?(Hash)

    row.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
  end

  def status(name, reason)
    { "status" => name, "reason" => reason }
  end
end
