# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

# Locator sheet into one full-text storyline. Presence, lineage shape, and
# not-empty / not-PRE-00-restatement only. Scripts never judge whether the
# pointed passage is cinematically recoverable.
module IdolStorylineDensityLocatorContract
  CONTRACT_VERSION = "storyline_density_locator.v1"
  SIBLING_SUFFIXES = %w[.density-locators.yaml .density-locators.yml .density-locators.json].freeze
  MARKDOWN_EXTENSIONS = %w[.md .markdown].freeze
  STAGES = %w[pre00 front_planning].freeze
  ROW_IDS = %w[
    opening
    change_mechanism
    stretch_action
    member_function
    place
    peak
    afterimage
    reference_function_or_exclusion
    deferred
  ].freeze
  SHA256 = /\A[a-f0-9]{64}\z/
  RESTATEMENT_NOT_EXPANDED = "pre00_storyline_not_expanded Front Planning must append a full-text descendant, plant Majors, and mark plus add Cores; a PRE-00 restatement is not expansion"
  RESTATEMENT_EMPTY = "pre00_storyline_not_expanded Front Planning descendant full text is empty"
  RESTATEMENT_BYTES = "pre00_storyline_not_expanded Front Planning active full text is a PRE-00 restatement"

  module_function

  def complete_sheet(source_path, parent_source_path: nil, parent_full_storyline_text_sha256: nil)
    locators = ROW_IDS.to_h do |row_id|
      [row_id, { "passage_locator" => "#{source_path}##{row_id}" }]
    end
    sheet = {
      "contract_version" => CONTRACT_VERSION,
      "source_path" => source_path.to_s,
      "locators" => locators
    }
    sheet["parent_source_path"] = parent_source_path.to_s unless parent_source_path.to_s.empty?
    unless parent_full_storyline_text_sha256.to_s.empty?
      sheet["parent_full_storyline_text_sha256"] = parent_full_storyline_text_sha256.to_s
    end
    sheet
  end

  def sibling_sheet_path(artifact_path, existing_only: false)
    path = Pathname.new(artifact_path)
    SIBLING_SUFFIXES.each do |suffix|
      candidate = path.sub_ext(suffix)
      return candidate if candidate.file?
    end
    return nil if existing_only

    path.sub_ext(SIBLING_SUFFIXES.fetch(0))
  end

  def sheet?(value)
    value.is_a?(Hash) && value.key?("locators")
  end

  def markdown?(path)
    MARKDOWN_EXTENSIONS.include?(Pathname.new(path).extname.downcase)
  end

  def validate(root, sheet)
    errors = []
    unless sheet.is_a?(Hash)
      return ["density locator sheet must be an object"]
    end

    source_path = sheet["source_path"].to_s
    source_file = nil
    if source_path.empty?
      errors << "density locator sheet missing source_path"
    else
      source_file = resolve_under_root(root, source_path)
      if source_file.nil?
        errors << "density locator source_path escapes repository root"
      elsif !source_file.file?
        errors << "density locator source_path is missing: #{source_path}"
      elsif source_file.read.strip.empty?
        errors << "density locator source_path is empty: #{source_path}"
      end
    end

    errors.concat(parent_lineage_errors(root, sheet, source_file))

    rows = sheet["locators"]
    unless rows.is_a?(Hash)
      errors << "density locator sheet missing locators object"
      return errors
    end

    ROW_IDS.each do |row_id|
      row = rows[row_id]
      unless row.is_a?(Hash)
        errors << "density locator missing row: #{row_id}"
        next
      end

      locator = row["passage_locator"].to_s.strip
      errors << "density locator empty passage_locator: #{row_id}" if locator.empty?
    end

    extra = rows.keys.map(&:to_s) - ROW_IDS
    extra.each { |row_id| errors << "density locator unknown row: #{row_id}" }
    errors
  end

  def closeable?(root, sheet)
    validate(root, sheet).empty?
  end

  def close_artifact(root, artifact_path, document: nil, stage: nil)
    path = Pathname.new(artifact_path)
    unless path.file?
      return ["density locator artifact missing: #{path}"]
    end

    if markdown?(path)
      return close_markdown(root, path)
    end

    loaded = document.nil? ? load_mapping(path) : document
    if sheet?(loaded)
      return validate(root, loaded)
    end

    close_document(root, path, loaded, infer_stage(loaded, stage))
  end

  def close_markdown(root, path)
    errors = []
    relative = repo_relative(root, path)
    if path.read.strip.empty?
      errors << "density locator source text is empty: #{relative}"
    end

    sheet_path = sibling_sheet_path(path, existing_only: true)
    if sheet_path.nil?
      errors << "density locator sheet missing for #{relative}"
      return errors
    end

    sheet = load_mapping(sheet_path)
    errors.concat(validate(root, sheet))
    declared = resolve_under_root(root, sheet["source_path"].to_s)
    unless declared && declared == artifact_realpath(path)
      errors << "density locator source_path does not bind the markdown original"
    end
    errors
  end

  def lineage_errors(document, stage)
    lineage = lineage_from(document)
    return ["density locator lineage missing"] unless lineage.is_a?(Hash)

    errors = []
    original = original_version(lineage)
    if original.is_a?(Hash)
      if original["full_storyline_text"].to_s.strip.empty?
        errors << "density locator lineage original full text is empty"
      else
        errors.concat(declared_text_sha_errors(original, "density locator lineage original full text hash is stale"))
      end
    else
      errors << "density locator lineage original missing"
    end

    Array(pre00_revisions(lineage)).each do |revision|
      next unless revision.is_a?(Hash)

      label = revision["version_id"].to_s
      if revision["full_storyline_text"].to_s.strip.empty?
        errors << "density locator lineage revision full text is empty: #{label}"
      else
        errors.concat(declared_text_sha_errors(revision, "density locator lineage revision full text hash is stale: #{label}"))
      end
      if revision["parent_full_storyline_text_sha256"].to_s.empty?
        errors << "density locator lineage revision missing parent hash: #{label}"
      end
    end

    return errors unless stage.to_s == "front_planning"

    fp_revisions = Array(lineage["front_planning_revisions"])
    active_scope = lineage.dig("active_version", "lineage_scope").to_s
    if fp_revisions.empty? || active_scope == "pre00"
      errors << RESTATEMENT_NOT_EXPANDED
    end
    latest = fp_revisions.last
    if latest.is_a?(Hash) && latest["full_storyline_text"].to_s.strip.empty?
      errors << RESTATEMENT_EMPTY
    end
    original_sha = original.is_a?(Hash) ? original["full_storyline_text_sha256"].to_s : ""
    active = lineage["active_version"]
    active_sha = active.is_a?(Hash) ? active["full_storyline_text_sha256"].to_s : ""
    if active.is_a?(Hash) && !active["full_storyline_text"].to_s.strip.empty?
      errors.concat(declared_text_sha_errors(active, "density locator lineage active full text hash is stale"))
    end
    if !original_sha.empty? && original_sha == active_sha
      errors << RESTATEMENT_BYTES
    end
    original_text = original.is_a?(Hash) ? original["full_storyline_text"].to_s : ""
    latest_text = latest.is_a?(Hash) ? latest["full_storyline_text"].to_s : ""
    active_text = active.is_a?(Hash) ? active["full_storyline_text"].to_s : ""
    if !original_text.strip.empty? && (original_text == latest_text || (!active_text.empty? && original_text == active_text))
      errors << RESTATEMENT_BYTES unless errors.include?(RESTATEMENT_BYTES)
    end
    fp_revisions.each do |revision|
      next unless revision.is_a?(Hash)

      unless revision["full_storyline_text"].to_s.strip.empty?
        errors.concat(declared_text_sha_errors(revision, "density locator lineage Front Planning revision full text hash is stale: #{revision['version_id']}"))
      end
      next unless revision["parent_full_storyline_text_sha256"].to_s.empty?

      errors << "density locator lineage Front Planning revision missing parent hash: #{revision['version_id']}"
    end
    errors
  end

  def load_mapping(path)
    path = Pathname.new(path)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, aliases: true)
            end
    raise TypeError, "document must be an object" unless value.is_a?(Hash)

    value
  end

  def infer_stage(document, stage = nil)
    declared = stage.to_s
    return declared if STAGES.include?(declared)
    return "front_planning" if document.is_a?(Hash) && document["schema_version"].to_s.start_with?("front-planning-readiness")
    return "front_planning" if document.is_a?(Hash) && document.dig("storyline_lineage", "front_planning_revisions")

    "pre00"
  end

  def resolve_under_root(root, relative)
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

  def repo_relative(root, path)
    Pathname.new(path).expand_path.relative_path_from(Pathname.new(root).expand_path).to_s
  rescue ArgumentError
    path.to_s
  end

  def lineage_from(document)
    return nil unless document.is_a?(Hash)
    return document if document.key?("pre00_storyline_original") ||
                       document.key?("pre00_lineage") ||
                       document.key?("front_planning_revisions")

    document["storyline_lineage"]
  end

  def original_version(lineage)
    lineage["pre00_storyline_original"] || lineage.dig("pre00_lineage", "pre00_storyline_original")
  end

  def pre00_revisions(lineage)
    lineage["pre00_storyline_revisions"] || lineage.dig("pre00_lineage", "pre00_storyline_revisions")
  end

  def close_document(root, path, document, stage)
    errors = []
    relative = repo_relative(root, path)
    sheet_path = sibling_sheet_path(path, existing_only: true)
    if sheet_path.nil?
      errors << "density locator sheet missing for #{relative}"
    else
      sheet = load_mapping(sheet_path)
      errors.concat(validate(root, sheet))
      declared = resolve_under_root(root, sheet["source_path"].to_s)
      unless declared && declared == artifact_realpath(path)
        errors << "density locator source_path does not bind the artifact"
      end
    end
    errors.concat(lineage_errors(document, stage))
    errors
  end

  def parent_lineage_errors(root, sheet, source_file)
    parent_path = sheet["parent_source_path"].to_s
    parent_sha = sheet["parent_full_storyline_text_sha256"].to_s
    return [] if parent_path.empty? && parent_sha.empty?

    errors = []
    if parent_path.empty? || parent_sha.empty?
      errors << "density locator parent lineage requires parent_source_path and parent_full_storyline_text_sha256"
      return errors
    end
    unless parent_sha.match?(SHA256)
      errors << "density locator parent_full_storyline_text_sha256 is malformed"
    end

    parent_file = resolve_under_root(root, parent_path)
    if parent_file.nil?
      errors << "density locator parent_source_path escapes repository root"
      return errors
    end
    unless parent_file.file?
      errors << "density locator parent_source_path is missing: #{parent_path}"
      return errors
    end

    parent_text = documented_storyline_text(parent_file)
    if parent_text.to_s.strip.empty?
      errors << "density locator parent_source_path has no documented full_storyline_text"
      return errors
    end
    actual = Digest::SHA256.hexdigest(parent_text)
    errors << "density locator parent_full_storyline_text_sha256 is stale" unless actual == parent_sha
    source_text = source_file&.file? ? documented_storyline_text(source_file) : nil
    if source_text && !source_text.strip.empty? && source_text == parent_text
      errors << RESTATEMENT_BYTES
    end
    errors
  end

  def documented_storyline_text(path)
    return nil unless path && path.file?
    return path.read if markdown?(path)

    document = begin
      load_mapping(path)
    rescue JSON::ParserError, Psych::Exception, TypeError
      return nil
    end
    lineage = lineage_from(document)
    return nil unless lineage.is_a?(Hash)

    active = lineage.dig("active_version", "full_storyline_text")
    return active if active.is_a?(String) && !active.strip.empty?

    original = original_version(lineage)
    return original["full_storyline_text"] if original.is_a?(Hash) && original["full_storyline_text"].to_s.strip != ""

    nil
  end

  def declared_text_sha_errors(version, message)
    declared = version["full_storyline_text_sha256"].to_s
    return [] if declared.empty?

    actual = Digest::SHA256.hexdigest(version["full_storyline_text"].to_s)
    declared == actual ? [] : [message]
  end

  def artifact_realpath(path)
    path = Pathname.new(path).expand_path.cleanpath
    path.exist? ? path.realpath : path
  rescue Errno::ENOENT, Errno::ELOOP
    Pathname.new(path).expand_path.cleanpath
  end
end
