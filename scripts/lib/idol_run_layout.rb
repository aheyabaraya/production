# frozen_string_literal: true

require "pathname"
require "digest"
require "json"
require "yaml"

module IdolRunLayout
  RUN_MANIFEST_NAME = "run-manifest.yaml"
  RUN_MANIFEST_VERSION = "idol-run-manifest.v1"
  RUN_LAYOUT_TRANSITION_RELATIVE = "automation/run-layout-transition.yaml"
  RUN_LAYOUT_TRANSITION_VERSION = "idol-run-layout-transition.v1"
  ACTIVE_RUN_ROOT_PATTERN = %r{\Aruns/(?<album_key>[a-z0-9][a-z0-9-]{1,120})/(?<title_key>[a-z0-9가-힣][a-z0-9가-힣-]{1,120})/(?<run_id>[A-Za-z0-9][A-Za-z0-9._-]{2,120})\z}

  module_function

  def relative_root(path, repo_root:)
    candidate = Pathname.new(path)
    candidate = Pathname.new(repo_root).join(candidate) unless candidate.absolute?
    candidate.expand_path.relative_path_from(Pathname.new(repo_root).expand_path).to_s
  rescue ArgumentError
    nil
  end

  def parse(path, repo_root:)
    relative = relative_root(path, repo_root: repo_root)
    match = ACTIVE_RUN_ROOT_PATTERN.match(relative.to_s)
    raise ArgumentError, "active run root must be runs/ALBUM_KEY/TITLE_KEY/RUN_ID; got: #{relative || path}" unless match

    {
      "album_key" => match[:album_key],
      "title_key" => match[:title_key],
      "run_id" => match[:run_id],
      "canonical_run_root" => relative
    }
  end

  def build(album_key:, title_key:, run_id:)
    value = "runs/#{album_key}/#{title_key}/#{run_id}"
    match = ACTIVE_RUN_ROOT_PATTERN.match(value)
    raise ArgumentError, "invalid active run address: #{value}" unless match

    value
  end

  def load_mapping(path, label)
    raise ArgumentError, "#{label} is missing: #{path}" unless path.file?

    value = YAML.safe_load(path.read, aliases: false)
    raise ArgumentError, "#{label} root must be an object: #{path}" unless value.is_a?(Hash)

    value
  end

  def transition_registry(repo_root:)
    load_mapping(
      Pathname.new(repo_root).expand_path.join(RUN_LAYOUT_TRANSITION_RELATIVE),
      "run layout transition registry"
    )
  end

  def transition_entry(path, repo_root:)
    relative = relative_root(path, repo_root: repo_root)
    registry_path = Pathname.new(repo_root).expand_path.join(RUN_LAYOUT_TRANSITION_RELATIVE)
    return nil unless registry_path.file?

    registry = load_mapping(registry_path, "run layout transition registry")
    matches = Array(registry["in_flight_exceptions"]).select do |row|
      row.is_a?(Hash) && row["run_root"].to_s == relative.to_s
    end
    if matches.length > 1
      raise ArgumentError, "run layout transition registry has duplicate entries for: #{relative}"
    end

    matches.first
  end

  def resolve(path, repo_root:)
    address = parse(path, repo_root: repo_root)
    address.merge(
      "layout_status" => "album_layout",
      "transition_entry" => nil,
      "identity_path" => Pathname.new(repo_root).expand_path.join(address.fetch("canonical_run_root"), RUN_MANIFEST_NAME)
    )
  rescue ArgumentError => canonical_error
    entry = transition_entry(path, repo_root: repo_root)
    raise canonical_error unless entry

    {
      "album_key" => entry["album_key"].to_s,
      "title_key" => entry["title_key"].to_s,
      "run_id" => entry["run_id"].to_s,
      "canonical_run_root" => entry["run_root"].to_s,
      "layout_status" => "registered_in_flight_transition",
      "transition_entry" => entry,
      "identity_path" => Pathname.new(repo_root).expand_path.join(RUN_LAYOUT_TRANSITION_RELATIVE)
    }
  end

  def identity(path, repo_root:)
    address = resolve(path, repo_root: repo_root)
    document = if address.fetch("layout_status") == "album_layout"
                 load_mapping(address.fetch("identity_path"), "run manifest")
               else
                 address.fetch("transition_entry")
               end
    address.merge(
      "document" => document,
      "content_id" => document["content_id"].to_s,
      "status" => address.fetch("layout_status") == "album_layout" ? document["status"].to_s : "active"
    )
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        result[key] = canonical_value(value[key])
      end
    when Array
      value.map { |item| canonical_value(item) }
    else
      value
    end
  end

  def active_stage_sequence_sha256(document)
    rows = Array(document["stages"])
           .select { |row| row.is_a?(Hash) && row["active"] == true }
           .sort_by { |row| [row["order"].to_i, row["stage_id"].to_s] }
           .map do |row|
      %w[stage_id order code owner_skill scope inputs founder_gate].to_h do |key|
        [key, row[key]]
      end
    end
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(rows)))
  end

  def within_repo?(path, repo_root)
    relative = path.expand_path.relative_path_from(Pathname.new(repo_root).expand_path).to_s
    relative != ".." && !relative.start_with?("../")
  rescue ArgumentError
    false
  end

  def validate_transition(path, repo_root:, address:, require_directory:)
    errors = []
    root = Pathname.new(repo_root).expand_path
    relative = relative_root(path, repo_root: root)
    entry = address.fetch("transition_entry")
    registry = transition_registry(repo_root: root)
    expected_registry = {
      "schema_version" => RUN_LAYOUT_TRANSITION_VERSION,
      "status" => "active",
      "active_run_template" => "runs/ALBUM_KEY/TITLE_KEY/RUN_ID",
      "generic_date_first_authoring" => "forbidden",
      "new_date_first_run_creation" => "forbidden",
      "quality_flow_change_authority" => "none"
    }
    expected_registry.each do |key, value|
      errors << "run layout transition #{key} must be #{value.inspect}; got #{registry[key].inspect}" unless registry[key] == value
    end

    run_path = Pathname.new(path)
    run_path = root.join(run_path) unless run_path.absolute?
    run_path = run_path.expand_path
    if require_directory && !run_path.directory?
      errors << "run root is not a directory: #{relative}"
      return errors
    end

    expected_entry = {
      "run_root" => relative,
      "state" => "in_flight_finish_in_place",
      "current_next_allowed" => true,
      "existing_canonical_continuation_allowed" => true,
      "new_run_creation_allowed" => false,
      "migration_execution_allowed" => false,
      "expires_when" => "run_closed_or_validated_migration_completed"
    }
    expected_entry.each do |key, value|
      errors << "registered transition #{key} must be #{value.inspect}; got #{entry[key].inspect}" unless entry[key] == value
    end
    if address.fetch("run_id") != Pathname.new(relative).basename.to_s
      errors << "registered transition run_id must match the source folder name"
    end
    begin
      expected_target = build(
        album_key: address.fetch("album_key"),
        title_key: address.fetch("title_key"),
        run_id: address.fetch("run_id")
      )
      unless entry["target_run_root"] == expected_target
        errors << "registered transition target_run_root must equal the canonical album/title/run address #{expected_target}"
      end
    rescue ArgumentError => e
      errors << e.message
    end

    migration = entry["migration_plan"]
    if !migration.is_a?(Hash)
      errors << "registered transition migration_plan must be an object"
    else
      migration_path = Pathname.new(migration["path"].to_s)
      migration_path = root.join(migration_path) unless migration_path.absolute?
      migration_path = migration_path.expand_path
      if !within_repo?(migration_path, root)
        errors << "registered transition migration plan must stay in repository"
      elsif !migration_path.file?
        errors << "registered transition migration plan is missing: #{migration['path']}"
      else
        actual = Digest::SHA256.file(migration_path.to_s).hexdigest
        if migration["sha256"] != actual
          errors << "registered transition migration plan SHA-256 mismatch: expected #{migration['sha256'].inspect}, got #{actual.inspect}"
        end
        plan = load_mapping(migration_path, "run migration plan")
        if plan["status"] != migration["required_status"]
          errors << "registered transition migration plan status differs from the required status"
        end
        if plan["source_run_root"] != relative
          errors << "registered transition migration plan source differs from the registered run"
        end
        if plan["target_run_root"] != entry["target_run_root"]
          errors << "registered transition migration plan target differs from the registered target"
        end
        unless plan["automatic_move_performed"] == false
          errors << "registered transition migration plan must confirm that no automatic move was performed"
        end
      end
    end

    flow = entry["flow_lock"]
    if !flow.is_a?(Hash)
      errors << "registered transition flow_lock must be an object"
    else
      stage_value = flow["stage_registry_path"].to_s
      unless stage_value == "automation/harness-stage-registry.yaml"
        errors << "registered transition stage_registry_path must be automation/harness-stage-registry.yaml"
      end
      stage_path = root.join(stage_value).expand_path
      if !stage_path.file?
        errors << "registered transition stage registry is missing: #{stage_value}"
      else
        registry_sha = Digest::SHA256.file(stage_path.to_s).hexdigest
        if flow["stage_registry_sha256"] != registry_sha
          errors << "registered transition stage registry SHA-256 differs from the active registry"
        end
        stage_document = load_mapping(stage_path, "stage registry")
        semantic_sha = active_stage_sequence_sha256(stage_document)
        if flow["stage_sequence_sha256"] != semantic_sha
          errors << "registered transition stage sequence SHA-256 differs from the active PRE-00 through 05 flow"
        end
      end
    end
    errors
  rescue Psych::SyntaxError => e
    ["run layout transition YAML is invalid: #{e.message}"]
  rescue ArgumentError => e
    [e.message]
  end

  def validate(path, repo_root:, require_directory: true, require_manifest: true)
    errors = []
    begin
      address = resolve(path, repo_root: repo_root)
    rescue ArgumentError => error
      return [error.message]
    end
    if address.fetch("layout_status") == "registered_in_flight_transition"
      return validate_transition(
        path,
        repo_root: repo_root,
        address: address,
        require_directory: require_directory
      )
    end

    run_path = Pathname.new(repo_root).join(address.fetch("canonical_run_root")).expand_path
    if require_directory && !run_path.directory?
      return ["run root is not a directory: #{address.fetch('canonical_run_root')}"]
    end
    return errors unless require_manifest

    manifest_path = run_path.join(RUN_MANIFEST_NAME)
    return ["run manifest is missing: #{manifest_path}"] unless manifest_path.file?

    manifest = YAML.safe_load(manifest_path.read, aliases: false)
    unless manifest.is_a?(Hash)
      return ["run manifest root must be an object: #{manifest_path}"]
    end
    expected = {
      "schema_version" => RUN_MANIFEST_VERSION,
      "album_key" => address.fetch("album_key"),
      "title_key" => address.fetch("title_key"),
      "run_id" => address.fetch("run_id"),
      "canonical_run_root" => address.fetch("canonical_run_root"),
      "artifact_revision_owner" => "git",
      "compatibility_authoring" => "forbidden"
    }
    expected.each do |key, value|
      errors << "run manifest #{key} must be #{value.inspect}; got #{manifest[key].inspect}" unless manifest[key] == value
    end
    errors
  rescue Psych::SyntaxError => e
    ["run manifest YAML is invalid: #{e.message}"]
  end
end
