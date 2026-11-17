# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"

module IdolArtifactIntegrity
  CACHE_VERSION = "idol-artifact-integrity-cache.v1"
  DEFAULT_CACHE_RELATIVE = ".runtime/cache/artifact-integrity-sha256-v1.json"
  PROFILES = {
    "canonical_gate" => "force_sha256",
    "promotion_or_external_transfer" => "force_sha256",
    "repeat_local_validation" => "cached_sha256_by_stat",
    "working_derived_media" => "stat_fingerprint",
    "ephemeral" => "none"
  }.freeze

  module_function

  def stat_fingerprint(path)
    stat = File.stat(path)
    mtime_ns = (stat.mtime.to_i * 1_000_000_000) + stat.mtime.nsec
    {
      "algorithm" => "stat-v1",
      "size_bytes" => stat.size,
      "mtime_ns" => mtime_ns,
      "device" => stat.dev,
      "inode" => stat.ino,
      "value" => "stat-v1:#{stat.size}:#{mtime_ns}:#{stat.dev}:#{stat.ino}"
    }
  end

  class Cache
    def initialize(repo_root:, cache_path: nil)
      @repo_root = Pathname.new(repo_root).expand_path
      @cache_path = cache_path ? Pathname.new(cache_path).expand_path : @repo_root.join(DEFAULT_CACHE_RELATIVE)
      @document = load_document
      @dirty = false
    end

    def inspect_path(path, profile:)
      mode = PROFILES.fetch(profile) { raise ArgumentError, "unknown integrity profile: #{profile}" }
      result = case mode
               when "force_sha256"
                 sha256(path, force: true)
               when "cached_sha256_by_stat"
                 sha256(path, force: false)
               when "stat_fingerprint"
                 IdolArtifactIntegrity.stat_fingerprint(path).merge("cache" => "not_applicable")
               else
                 {"algorithm" => "none", "value" => nil, "cache" => "not_applicable"}
               end
      result.merge("profile" => profile)
    end

    def sha256(path, force: false)
      candidate = Pathname.new(path).expand_path
      fingerprint = IdolArtifactIntegrity.stat_fingerprint(candidate)
      comparable = fingerprint.slice("size_bytes", "mtime_ns", "device", "inode")
      key = cache_key(candidate)
      row = @document.fetch("entries", {})[key]
      if !force && row.is_a?(Hash) && !row["sha256"].to_s.empty? &&
         comparable.all? { |field, value| row[field] == value }
        return {"algorithm" => "sha256", "value" => row["sha256"], "cache" => "hit"}.merge(comparable)
      end

      value = Digest::SHA256.file(candidate.to_s).hexdigest
      @document["entries"][key] = {"sha256" => value}.merge(comparable)
      @dirty = true
      {"algorithm" => "sha256", "value" => value, "cache" => force ? "forced" : "miss"}.merge(comparable)
    end

    def save
      return unless @dirty

      FileUtils.mkdir_p(@cache_path.dirname)
      temporary = @cache_path.dirname.join(".#{@cache_path.basename}.#{Process.pid}.tmp")
      temporary.write("#{JSON.generate(@document)}\n", encoding: "UTF-8")
      File.chmod(0o600, temporary)
      File.rename(temporary, @cache_path)
      @dirty = false
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary&.exist?
    end

    private

    def cache_key(path)
      path.relative_path_from(@repo_root).to_s
    rescue ArgumentError
      path.to_s
    end

    def load_document
      document = JSON.parse(@cache_path.read)
      if document.is_a?(Hash) &&
         document["schema_version"] == CACHE_VERSION &&
         document["entries"].is_a?(Hash)
        document
      else
        {"schema_version" => CACHE_VERSION, "entries" => {}}
      end
    rescue Errno::ENOENT, JSON::ParserError
      {"schema_version" => CACHE_VERSION, "entries" => {}}
    end
  end
end
