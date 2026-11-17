#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
SOURCE_SET_SCHEMA = ROOT.join("schemas", "review-projection-source-set.schema.json")
OWNER_INDEX_SCHEMA = ROOT.join("schemas", "review-projection-owner-index.schema.json")
PENDING_SCHEMA = ROOT.join("schemas", "review-projection-pending.schema.json")
CURRENT_NEXT_SCHEMA = ROOT.join("schemas", "harness-current-next.schema.json")
BOARD_RENDERER = ROOT.join("scripts", "idol_html_review_board.rb")
CURRENT_NEXT_RENDERER = ROOT.join("scripts", "idol_harness_current_next.rb")

class ReviewProjectionError < StandardError; end

ADAPTER_STAGES = {
  "reference_working_index" => "front_planning",
  "current_title_member_visual" => "front_planning",
  "stage_01" => "01",
  "stage_02a" => "02A",
  "stage_02b" => "02B",
  "generated_branch_review" => "generated_branch_review",
  "stage_03v" => "03V",
  "stage_04" => "04"
}.freeze

ASSET_FIELD_KEYS = %w[
  asset_id surface_locator canonical_path sha256 alt label note media_kind
  original_owner role inspection_action display_lane receipt supersedes_asset_id
  superseded_by_asset_id
].freeze

BINDING_FIELD_KEYS = %w[
  binding_id assignment_state target_id target_level section_id core_cut_id
  branch_cut_id declared_order lane_role disposition review_state state_receipt
  routing_dispatch_id
].freeze

def load_document(path, label)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [], aliases: true)
          end
  raise ReviewProjectionError, "#{label} must be a mapping" unless value.is_a?(Hash)
  value
rescue JSON::ParserError, Psych::Exception => e
  raise ReviewProjectionError, "cannot parse #{label}: #{e.message}"
end

def relative_path(path)
  Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
rescue ArgumentError
  raise ReviewProjectionError, "path escapes repository root: #{path}"
end

def repository_path(raw, label, must_exist: true)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = relative_path(path)
  raise ReviewProjectionError, "#{label} escapes repository root" if relative == ".." || relative.start_with?("../")
  raise ReviewProjectionError, "#{label} is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
end

def verify_binding(binding, label, must_exist: true)
  raise ReviewProjectionError, "#{label} must be an artifact binding" unless binding.is_a?(Hash)
  path, relative = repository_path(binding.fetch("path"), "#{label}.path", must_exist: must_exist)
  expected = binding.fetch("sha256").to_s
  unless expected.match?(/\A[a-f0-9]{64}\z/)
    raise ReviewProjectionError, "#{label}.sha256 must be lowercase SHA-256"
  end
  if must_exist
    actual = Digest::SHA256.file(path).hexdigest
    raise ReviewProjectionError, "#{label} SHA-256 is stale for #{relative}" unless actual == expected
  end
  [path, relative]
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema.to_s,
    path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?
  raise ReviewProjectionError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}"
end

def json_pointer(value, pointer, label)
  raise ReviewProjectionError, "#{label} pointer is missing" if pointer.nil?
  current = value
  pointer.to_s.split("/")[1..].to_a.each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    current = if current.is_a?(Array)
      unless token.match?(/\A(?:0|[1-9]\d*)\z/)
        raise ReviewProjectionError, "#{label} array pointer token is not an index: #{token}"
      end
      current.fetch(token.to_i) { raise ReviewProjectionError, "#{label} array index is missing: #{token}" }
    elsif current.is_a?(Hash)
      current.fetch(token) { raise ReviewProjectionError, "#{label} pointer key is missing: #{token}" }
    else
      raise ReviewProjectionError, "#{label} pointer traverses a scalar at #{token}"
    end
  end
  current
end

def optional_pointer(value, pointer, label)
  return nil if pointer.nil?
  json_pointer(value, pointer, label)
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def canonical_json_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      result[key] = canonical_json_value(value.fetch(key))
    end
  when Array
    value.map { |item| canonical_json_value(item) }
  else
    value
  end
end

def exact_binding_equal?(left, right)
  %w[path sha256 role].all? do |key|
    left.is_a?(Hash) && right.is_a?(Hash) && left[key].to_s == right[key].to_s
  end
end

def canonical_source_digest(source_set)
  payload = deep_copy(source_set)
  payload.delete("source_set_digest")
  payload.delete("projection_revision")
  payload.fetch("base_manifest").delete("sha256")
  owner_pairs = source_bindings(source_set).map do |binding|
    [binding.fetch("path").to_s, binding.fetch("sha256").to_s]
  end.uniq.sort
  canonical = JSON.generate(canonical_json_value(payload))
  [Digest::SHA256.hexdigest(canonical), owner_pairs]
end

def artifact_binding(path, role)
  {
    "path" => relative_path(path),
    "sha256" => Digest::SHA256.file(path).hexdigest,
    "role" => role
  }
end

def prepare_source_set(owner_index_path, source_set_path, write:)
  validate_schema(OWNER_INDEX_SCHEMA, owner_index_path, "review projection owner index")
  owner_index = load_document(owner_index_path, "review projection owner index")
  run = owner_index.fetch("run")
  expected_index = "#{run}/work/review-projection-owner-index.yaml"
  unless relative_path(owner_index_path) == expected_index
    raise ReviewProjectionError, "owner index must use the stable path #{expected_index}"
  end
  expected_source_set = "#{run}/work/review-projection-source-set.yaml"
  unless relative_path(source_set_path) == expected_source_set
    raise ReviewProjectionError, "source set must use the stable path #{expected_source_set}"
  end

  manifest_path, manifest_relative = repository_path(
    "#{run}/review/manifests/founder-workbench.yaml",
    "stable Founder workbench manifest"
  )
  manifest = load_document(manifest_path, "stable Founder workbench manifest")
  unless manifest.dig("run", "run_root") == run
    raise ReviewProjectionError, "stable Founder workbench manifest belongs to another run"
  end
  board_revision = Integer(manifest.dig("board", "revision"))
  raise ReviewProjectionError, "stable Founder workbench revision must be positive" if board_revision < 1

  sources = deep_copy(Array(owner_index.fetch("sources")))
  source_ids = sources.map { |source| source.fetch("source_id").to_s }
  raise ReviewProjectionError, "owner index source_id values must be unique" unless source_ids.uniq.length == source_ids.length
  source_kinds = sources.map { |source| source.fetch("adapter_kind").to_s }.uniq.sort
  declared_kinds = Array(owner_index.fetch("declared_adapter_kinds")).map(&:to_s).uniq.sort
  unless source_kinds == declared_kinds
    raise ReviewProjectionError, "declared_adapter_kinds must exactly cover the registered owner source classes"
  end

  source_set = {
    "schema_version" => "idol-review-projection-source-set.v2",
    "artifact_type" => "review_projection_source_set",
    "status" => "prepared",
    "run" => run,
    "base_manifest" => artifact_binding(manifest_path, "stable_board_compare_and_swap_base"),
    "projection_revision" => board_revision + 1,
    "source_set_digest" => {},
    "director_dispatch_index" => deep_copy(owner_index.fetch("director_dispatch_index")),
    "sources" => sources,
    "outputs" => {
      "manifest_path" => manifest_relative,
      "html_path" => "#{run}/review/founder-workbench.html",
      "pending_path" => "#{run}/work/review-projection-pending.yaml"
    },
    "authority_boundary" => {
      "pointer_only" => true,
      "exact_copy_only" => true,
      "media_copy_allowed" => false,
      "creative_authority" => false,
      "stage_write_allowed" => false,
      "approval_inference_allowed" => false,
      "new_state_is_revision_derived" => true,
      "compare_and_swap_required" => true,
      "atomic_write_required" => true
    }
  }
  source_set["ordered_review"] = deep_copy(owner_index["ordered_review"]) if owner_index.key?("ordered_review")

  digest, owner_pairs = canonical_source_digest(source_set)
  source_set["source_set_digest"] = {
    "algorithm" => "sha256",
    "basis" => "canonical_projection_query_and_owner_bindings_v1",
    "sha256" => digest,
    "entry_count" => owner_pairs.length
  }
  if manifest.dig("board", "source_set_digest") == source_set["source_set_digest"]
    source_set["projection_revision"] = board_revision
  end

  bytes = YAML.dump(source_set)
  source_set_path.dirname.mkpath
  Tempfile.create(["review-projection-source-set", ".yaml"], source_set_path.dirname.to_s) do |candidate|
    candidate.write(bytes)
    candidate.flush
    validate_schema(SOURCE_SET_SCHEMA, Pathname.new(candidate.path), "prepared review projection source set")
  end
  atomic_write(source_set_path, bytes) if write
  source_set
end

def source_bindings(source_set)
  bindings = Array(source_set.fetch("sources")).map { |source| source.fetch("owner_artifact") }
  bindings << source_set.fetch("director_dispatch_index")
  ordered = source_set["ordered_review"]
  if ordered.is_a?(Hash)
    bindings << ordered.fetch("fp_close_source").fetch("owner_artifact")
    bindings << ordered.fetch("planning_02a_source").fetch("owner_artifact")
  end
  bindings
end

def verify_source_set_digest(source_set)
  source_bindings(source_set).each do |binding|
    verify_binding(binding, "source-set input")
  end
  digest, unique = canonical_source_digest(source_set)
  declared = source_set.fetch("source_set_digest")
  raise ReviewProjectionError, "source_set_digest SHA-256 is stale" unless declared.fetch("sha256") == digest
  unless declared.fetch("entry_count") == unique.length
    raise ReviewProjectionError, "source_set_digest entry_count is stale"
  end
  declared
end

def extracted_fields(row, pointers, keys, label)
  keys.each_with_object({}) do |key, result|
    next unless pointers.key?(key)
    pointer = pointers[key]
    next if pointer.nil?
    result[key] = optional_pointer(row, pointer, "#{label}.#{key}")
  end
end

def verified_artifact_value(value, label)
  verify_binding(value, label)
  deep_copy(value)
end

def validate_media_bytes!(asset, label)
  path, relative = repository_path(asset.fetch("canonical_path"), "#{label}.canonical_path")
  actual = Digest::SHA256.file(path).hexdigest
  unless actual == asset.fetch("sha256")
    raise ReviewProjectionError, "#{label} media SHA-256 is stale for #{relative}"
  end
end

def asset_content_without_lineage(asset)
  asset.reject { |key, _value| %w[first_seen_board_revision bindings].include?(key) }
end

def binding_content_without_revision(binding)
  binding.reject { |key, _value| %w[new_since_last_review latest_binding_revision routing_dispatch_id].include?(key) }
end

def find_dispatch!(dispatch_index, dispatch_id, label)
  rows = Array(dispatch_index["dispatches"])
  matches = rows.select { |row| row.is_a?(Hash) && row["dispatch_id"].to_s == dispatch_id.to_s }
  raise ReviewProjectionError, "#{label} dispatch #{dispatch_id} is absent from Director Dispatch Index" if matches.empty?
  raise ReviewProjectionError, "#{label} dispatch #{dispatch_id} is multiply owned" if matches.length > 1
end

def apply_ordered_review!(manifest, ordered_review)
  return unless ordered_review.is_a?(Hash)

  board = manifest.fetch("board")
  phases = Array(board["review_sequence"])
  unless phases.map { |row| row["phase"] } == %w[fp_close planning_02a]
    raise ReviewProjectionError, "02A Final Planning must declare read-only fp_close then planning_02a"
  end

  fp_binding = ordered_review.fetch("fp_close_source").fetch("owner_artifact")
  fp_path, = verify_binding(fp_binding, "ordered_review.fp_close_source.owner_artifact")
  fp_document = load_document(fp_path, "internal FP Close owner")
  fp_status = json_pointer(
    fp_document,
    ordered_review.fetch("fp_close_source").fetch("status_pointer"),
    "ordered_review.fp_close_source.status"
  )
  fp_closed = Array(ordered_review.dig("fp_close_source", "closed_values")).include?(fp_status.to_s)

  planning = ordered_review.fetch("planning_02a_source")
  planning_path, = verify_binding(planning.fetch("owner_artifact"), "ordered_review.planning_02a_source.owner_artifact")
  planning_document = load_document(planning_path, "02A Final Planning source")
  rows = json_pointer(planning_document, planning.fetch("rows_pointer"), "ordered_review.planning_02a_source.rows")
  raise ReviewProjectionError, "02A Final Planning rows must be an array" unless rows.is_a?(Array)
  ready_values = Array(planning.fetch("ready_values"))
  eligibility = rows.each_with_object({}) do |row, result|
    raise ReviewProjectionError, "02A Final Planning row must be a mapping" unless row.is_a?(Hash)
    target_id = json_pointer(row, planning.fetch("target_id_pointer"), "02A Final Planning target id").to_s
    raise ReviewProjectionError, "duplicate 02A Final Planning target #{target_id}" if result.key?(target_id)
    status = json_pointer(row, planning.fetch("status_pointer"), "02A Final Planning target status")
    result[target_id] = ready_values.include?(status)
  end

  active_cycle = Array(manifest.fetch("sections")).find do |cycle|
    cycle["cycle_id"].to_s == board.fetch("active_cycle_id").to_s
  end
  raise ReviewProjectionError, "active review cycle is missing" unless active_cycle
  seen_exact = []
  active_cycle.fetch("cards").each do |card|
    case card["review_phase"]
    when "fp_close"
      card["phase_state"] = "read_only"
    when "planning_02a"
      target_id = card.dig("review_target", "target_id").to_s
      raise ReviewProjectionError, "02A Final Planning target #{target_id} is absent from its canonical readiness owner" unless eligibility.key?(target_id)
      card["phase_state"] = fp_closed && eligibility.fetch(target_id) ? "active" : "provisional"
      seen_exact << target_id
    end
  end
  unknown = eligibility.keys - seen_exact
  raise ReviewProjectionError, "02A Final Planning owner contains unprojected targets: #{unknown.join(', ')}" unless unknown.empty?
end

def build_projection(source_set, source_set_path, source_set_sha)
  run = source_set.fetch("run")
  run_path, run_relative = repository_path(run, "run", must_exist: false)
  raise ReviewProjectionError, "run directory is missing: #{run_relative}" unless run_path.directory?
  raise ReviewProjectionError, "CF run roots are forbidden" if run_relative.start_with?("cf/")

  base_path, base_relative = verify_binding(source_set.fetch("base_manifest"), "base_manifest")
  outputs = source_set.fetch("outputs")
  unless base_relative == outputs.fetch("manifest_path")
    raise ReviewProjectionError, "base_manifest must be the same stable manifest path written by the assembler"
  end
  unless base_relative == "#{run}/review/manifests/founder-workbench.yaml"
    raise ReviewProjectionError, "stable manifest must be RUN/review/manifests/founder-workbench.yaml"
  end
  unless outputs.fetch("html_path") == "#{run}/review/founder-workbench.html" &&
         outputs.fetch("pending_path") == "#{run}/work/review-projection-pending.yaml"
    raise ReviewProjectionError, "projection outputs must stay at the three fixed run-owned paths"
  end

  manifest = deep_copy(load_document(base_path, "base Founder workbench manifest"))
  base_manifest = deep_copy(manifest)
  unless manifest.dig("run", "run_root") == run
    raise ReviewProjectionError, "base manifest run root differs from source set"
  end
  unless manifest.dig("board", "output_path") == outputs.fetch("html_path")
    raise ReviewProjectionError, "base manifest HTML output differs from the stable output path"
  end

  board = manifest.fetch("board")
  base_revision = board.fetch("revision")
  target_revision = source_set.fetch("projection_revision")
  unless [base_revision, base_revision + 1].include?(target_revision)
    raise ReviewProjectionError, "projection_revision must equal the base revision or advance it by exactly one"
  end
  last_reviewed = board.fetch("last_reviewed_revision", 0)
  raise ReviewProjectionError, "last reviewed revision cannot exceed the target projection" if last_reviewed > target_revision

  digest = verify_source_set_digest(source_set)
  dispatch_path, = verify_binding(source_set.fetch("director_dispatch_index"), "director_dispatch_index")
  dispatch_index = load_document(dispatch_path, "Director Dispatch Index")
  unless dispatch_index["run"].nil? || dispatch_index["run"] == run
    raise ReviewProjectionError, "Director Dispatch Index belongs to another run"
  end

  existing_assets = Array(manifest["review_assets"]).each_with_object({}) do |asset, result|
    asset_id = asset.fetch("asset_id").to_s
    raise ReviewProjectionError, "duplicate base review asset #{asset_id}" if result.key?(asset_id)
    result[asset_id] = asset
  end
  active_cycle_id = board.fetch("active_cycle_id")
  active_cycle = Array(manifest.fetch("sections")).find { |cycle| cycle["cycle_id"] == active_cycle_id }
  raise ReviewProjectionError, "active cycle #{active_cycle_id} is missing" unless active_cycle
  active_card_by_target = active_cycle.fetch("cards").each_with_object({}) do |card, result|
    target_id = card.dig("review_target", "target_id").to_s
    raise ReviewProjectionError, "duplicate active card target #{target_id}" if result.key?(target_id)
    result[target_id] = card
  end
  active_existing_refs = active_cycle.fetch("cards").flat_map { |card| Array(card["media"]) }.each_with_object([]) do |row, result|
    next unless row.is_a?(Hash) && row.key?("asset_id") && row.key?("binding_id")
    result << [row.fetch("asset_id").to_s, row.fetch("binding_id").to_s]
  end

  projected_assets = {}
  physical_owners = {}
  projected_bindings = {}
  pending_items = []
  inventory_count = 0
  excluded_count = 0

  Array(source_set.fetch("sources")).each_with_index do |source, source_index|
    adapter_kind = source.fetch("adapter_kind")
    expected_stage = ADAPTER_STAGES.fetch(adapter_kind)
    unless source.fetch("source_stage") == expected_stage
      raise ReviewProjectionError, "source #{source.fetch('source_id')} stage must be #{expected_stage} for #{adapter_kind}"
    end
    owner_path, = verify_binding(source.fetch("owner_artifact"), "sources[#{source_index}].owner_artifact")
    owner_document = load_document(owner_path, "source owner #{source.fetch('source_id')}")
    unless owner_document["schema_version"].to_s == source.fetch("expected_schema_version").to_s
      raise ReviewProjectionError, "source #{source.fetch('source_id')} schema version differs from the adapter lock"
    end
    inventory = json_pointer(owner_document, source.fetch("inventory_pointer"), "source #{source.fetch('source_id')} inventory")
    raise ReviewProjectionError, "source #{source.fetch('source_id')} inventory must be an array" unless inventory.is_a?(Array)
    inventory_count += inventory.length
    project_values = Array(source.fetch("project_values")).map(&:to_s)
    excluded_values = Array(source.fetch("excluded_values")).map(&:to_s)

    inventory.each_with_index do |row, row_index|
      row_label = "source #{source.fetch('source_id')} row #{row_index}"
      raise ReviewProjectionError, "#{row_label} must be a mapping" unless row.is_a?(Hash)
      projection_state = json_pointer(row, source.fetch("projection_state_pointer"), "#{row_label}.projection_state").to_s
      if excluded_values.include?(projection_state)
        reason_pointer = source["exclusion_reason_pointer"]
        reason = optional_pointer(row, reason_pointer, "#{row_label}.exclusion_reason").to_s.strip
        raise ReviewProjectionError, "#{row_label} exclusion must name its owner-authored reason" if reason.empty?
        excluded_count += 1
        next
      end
      unless project_values.include?(projection_state)
        raise ReviewProjectionError, "#{row_label} has an unaccounted projection state #{projection_state.inspect}"
      end

      asset = extracted_fields(row, source.fetch("asset_fields"), ASSET_FIELD_KEYS, "#{row_label}.asset")
      binding = extracted_fields(row, source.fetch("binding_fields"), BINDING_FIELD_KEYS, "#{row_label}.binding")
      asset_id = asset.fetch("asset_id").to_s
      binding_id = binding.fetch("binding_id").to_s
      raise ReviewProjectionError, "#{row_label} asset_id is empty" if asset_id.empty?
      raise ReviewProjectionError, "#{row_label} binding_id is empty" if binding_id.empty?
      asset["asset_id"] = asset_id
      asset["sha256"] = asset.fetch("sha256").to_s
      asset["supersedes_asset_id"] = nil unless asset.key?("supersedes_asset_id")
      asset["superseded_by_asset_id"] = nil unless asset.key?("superseded_by_asset_id")
      asset.delete("note") if asset["note"].nil?
      asset.delete("receipt") if asset["receipt"].nil?
      validate_media_bytes!(asset, "#{row_label}.asset")
      binding["binding_id"] = binding_id
      binding["source_stage"] = expected_stage
      binding["state_receipt"] = verified_artifact_value(binding.fetch("state_receipt"), "#{row_label}.state_receipt")
      routing_dispatch_id = binding.delete("routing_dispatch_id")

      physical_key = [asset.fetch("canonical_path"), asset.fetch("sha256")]
      previous_physical_owner = physical_owners[physical_key]
      if previous_physical_owner && previous_physical_owner != asset_id
        raise ReviewProjectionError, "#{row_label} duplicates media bytes owned by #{previous_physical_owner}; reuse its asset_id"
      end
      physical_owners[physical_key] = asset_id

      projected = projected_assets[asset_id]
      if projected
        unless asset_content_without_lineage(projected) == asset_content_without_lineage(asset)
          raise ReviewProjectionError, "#{row_label} changes asset-level truth for #{asset_id} across bindings"
        end
      else
        existing = existing_assets[asset_id]
        first_seen = if existing && existing["canonical_path"] == asset["canonical_path"] && existing["sha256"] == asset["sha256"]
                       existing.fetch("first_seen_board_revision")
                     else
                       target_revision
                     end
        projected = asset.merge("first_seen_board_revision" => first_seen, "bindings" => [])
        projected_assets[asset_id] = projected
      end

      binding_key = [asset_id, binding_id]
      raise ReviewProjectionError, "duplicate projected binding #{asset_id}/#{binding_id}" if projected_bindings.key?(binding_key)
      existing_binding = Array(existing_assets.dig(asset_id, "bindings")).find { |candidate| candidate["binding_id"] == binding_id }
      existing_asset_same = existing_assets[asset_id] &&
                            asset_content_without_lineage(existing_assets.fetch(asset_id)) == asset_content_without_lineage(projected)
      unchanged = existing_asset_same && existing_binding &&
                  binding_content_without_revision(existing_binding) == binding_content_without_revision(binding)
      latest_revision = unchanged ? existing_binding.fetch("latest_binding_revision") : target_revision
      if binding["assignment_state"] == "unassigned"
        latest_revision = target_revision
        unless binding["target_id"].nil? && binding["target_level"] == "unassigned" &&
               binding["lane_role"] == "unassigned" && binding["disposition"] == "new" &&
               binding["review_state"] == "pending"
          raise ReviewProjectionError, "#{row_label} unassigned intake must remain targetless, new, and pending"
        end
        dispatch_id = routing_dispatch_id.to_s
        raise ReviewProjectionError, "#{row_label} unassigned intake is missing routing_dispatch_id" if dispatch_id.empty?
        find_dispatch!(dispatch_index, dispatch_id, row_label)
        pending_items << {
          "asset_id" => asset_id,
          "binding_id" => binding_id,
          "source_stage" => expected_stage,
          "dispatch_id" => dispatch_id,
          "director_dispatch_index" => deep_copy(source_set.fetch("director_dispatch_index")),
          "reason" => "new_unassigned_review_asset_requires_lane_and_target_classification"
        }
      elsif binding["assignment_state"] != "assigned"
        raise ReviewProjectionError, "#{row_label} assignment_state must be assigned or unassigned"
      end
      first_seen = projected.fetch("first_seen_board_revision")
      binding["latest_binding_revision"] = latest_revision
      binding["new_since_last_review"] = first_seen > last_reviewed || latest_revision > last_reviewed
      if binding["assignment_state"] == "unassigned" && !binding["new_since_last_review"]
        raise ReviewProjectionError, "#{row_label} unassigned intake cannot be hidden by the last reviewed revision"
      end
      projected.fetch("bindings") << binding
      projected_bindings[binding_key] = binding
    end
  end

  missing_active = active_existing_refs.reject { |key| projected_bindings.key?(key) }
  unless missing_active.empty?
    raise ReviewProjectionError, "active board bindings were omitted by owner feeds: #{missing_active.map { |row| row.join('/') }.join(', ')}"
  end

  existing_assets.each do |asset_id, existing|
    next unless projected_assets.key?(asset_id)
    Array(existing["bindings"]).each do |binding|
      key = [asset_id, binding.fetch("binding_id").to_s]
      next if projected_bindings.key?(key)
      if binding["new_since_last_review"] || %w[active_used new candidate passed_output].include?(binding["disposition"])
        raise ReviewProjectionError, "current binding #{key.join('/')} was omitted by owner feeds"
      end
      projected_assets.fetch(asset_id).fetch("bindings") << deep_copy(binding)
      projected_bindings[key] = binding
    end
  end

  active_cycle.fetch("cards").each { |card| card["media"] = [] }
  projected_assets.each_value do |asset|
    asset.fetch("bindings").sort_by! { |binding| [binding.fetch("declared_order"), binding.fetch("binding_id")] }
    asset.fetch("bindings").each do |binding|
      next unless binding["assignment_state"] == "assigned"
      target_id = binding.fetch("target_id").to_s
      card = active_card_by_target[target_id]
      next unless card
      card.fetch("media") << {"asset_id" => asset.fetch("asset_id"), "binding_id" => binding.fetch("binding_id")}
    end
  end
  empty_cards = active_cycle.fetch("cards").select { |card| Array(card["media"]).empty? }
  unless empty_cards.empty?
    raise ReviewProjectionError, "active cards lost every owner-backed asset: #{empty_cards.map { |card| card.fetch('card_id') }.join(', ')}"
  end

  apply_ordered_review!(manifest, source_set["ordered_review"])
  board["revision"] = target_revision
  board["projection_revision"] = target_revision
  board["source_set_digest"] = deep_copy(digest)
  manifest["review_assets"] = projected_assets.values.sort_by { |asset| asset.fetch("asset_id") }
  if target_revision == base_revision && manifest != base_manifest
    raise ReviewProjectionError, "projection bytes changed without advancing the board revision"
  end

  summary = {
    "source_count" => source_set.fetch("sources").length,
    "inventory_count" => inventory_count,
    "projected_asset_count" => manifest.fetch("review_assets").length,
    "projected_binding_count" => projected_bindings.length,
    "excluded_count" => excluded_count,
    "unresolved_count" => pending_items.length
  }
  pending = {
    "schema_version" => "idol-review-projection-pending.v1",
    "artifact_type" => "review_projection_pending_index",
    "run" => run,
    "status" => pending_items.empty? ? "clear" : "pending",
    "source_set" => {"path" => source_set_path, "sha256" => source_set_sha, "role" => "review_projection_source_set"},
    "board_manifest" => {"path" => outputs.fetch("manifest_path"), "sha256" => "0" * 64, "role" => "stable_founder_workbench_manifest"},
    "board_revision" => target_revision,
    "active_cycle_id" => active_cycle_id,
    "summary" => summary,
    "items" => pending_items,
    "next_action" => "route_unassigned_items_through_existing_director_dispatch_then_reassemble_same_stable_board",
    "automation_boundaries" => {
      "creative_truth_written" => false,
      "task_created" => false,
      "approval_inferred" => false,
      "current_next_selection_overridden" => false
    }
  }
  [manifest, pending, summary]
end

def atomic_write(path, bytes)
  path.dirname.mkpath
  Tempfile.create([".idol-review-projection", path.extname], path.dirname.to_s) do |temp|
    temp.binmode
    temp.write(bytes)
    temp.flush
    temp.fsync
    File.rename(temp.path, path.to_s)
  end
end

def restore_path(path, bytes)
  if bytes.nil?
    path.delete if path.exist?
  else
    atomic_write(path, bytes)
  end
end

def sync_current_next(run, pending, pending_path, current_next_yaml, current_next_md)
  yaml_path, yaml_relative = repository_path(current_next_yaml, "current-next YAML", must_exist: false)
  md_path, md_relative = repository_path(current_next_md, "current-next Markdown", must_exist: false)
  return {"status" => "missing", "path" => yaml_relative} unless yaml_path.file?

  current = load_document(yaml_path, "current-next YAML")
  unless current["schema_version"] == "harness-current-next.v2"
    return {
      "status" => "legacy_evidence_only",
      "path" => yaml_relative,
      "schema_version" => current["schema_version"].to_s
    }
  end
  unless current["run"].to_s == run
    return {"status" => "other_run", "path" => yaml_relative, "run" => current["run"]}
  end

  current_ddi = current.dig("frontier_binding", "director_dispatch_index")
  unless current_ddi.is_a?(Hash) && current_ddi["role"].to_s == "director_dispatch_index_v4"
    raise ReviewProjectionError, "current-next frontier lacks its exact DDI v4 binding"
  end
  verify_binding(current_ddi, "current-next DDI")
  source_set_path, = verify_binding(pending.fetch("source_set"), "pending source set")
  source_set = load_document(source_set_path, "pending source set")
  unless source_set["schema_version"].to_s == "idol-review-projection-source-set.v2" && source_set["run"].to_s == run
    raise ReviewProjectionError, "pending source set is not the same-run active v2 source set"
  end
  source_set_ddi = source_set.fetch("director_dispatch_index")
  verify_binding(source_set_ddi, "pending source-set DDI")
  unless exact_binding_equal?(source_set_ddi, current_ddi)
    raise ReviewProjectionError, "pending source-set DDI differs from the active current-next DDI"
  end
  ddi_path, = verify_binding(current_ddi, "current-next DDI")
  ddi = load_document(ddi_path, "director dispatch index")
  unless ddi["schema_version"].to_s == "idol-director-dispatch-index.v4" && ddi["run"].to_s == run
    raise ReviewProjectionError, "current-next DDI is not the same-run active v4 index"
  end
  known_dispatch_ids = Array(ddi["dispatches"]).map { |row| row.fetch("dispatch_id").to_s }
  known_dispatch_ids.concat(Array(ddi.dig("review_queue", "items")).map { |row| row.fetch("dispatch_id").to_s })
  Array(ddi["next_actions"]).each do |action|
    action_id = action.fetch("next_action_id").to_s
    known_dispatch_ids.concat(Array(ddi["dispatches"]).select { |row| Array(row["next_action_ids"]).map(&:to_s).include?(action_id) }.map { |row| row.fetch("dispatch_id").to_s })
  end
  known_dispatch_ids.uniq!

  compact_items = Array(pending.fetch("items")).map.with_index do |item, index|
    unless exact_binding_equal?(item.fetch("director_dispatch_index"), current_ddi)
      raise ReviewProjectionError, "pending item #{index + 1} DDI differs from the active current-next DDI"
    end
    unless known_dispatch_ids.include?(item.fetch("dispatch_id").to_s)
      raise ReviewProjectionError, "pending item #{index + 1} dispatch is absent from the active DDI"
    end
    item.slice("asset_id", "binding_id", "source_stage", "dispatch_id")
  end
  selection_before = canonical_json_value(current.dig("frontier_binding", "selection"))
  current["review_projection_pending"] = {
    "source" => {
      "path" => relative_path(pending_path),
      "sha256" => Digest::SHA256.file(pending_path).hexdigest,
      "role" => "review_projection_pending_index"
    },
    "director_dispatch_index" => deep_copy(current_ddi),
    "status" => pending.fetch("status"),
    "board_manifest" => deep_copy(pending.fetch("board_manifest")),
    "board_revision" => pending.fetch("board_revision"),
    "active_cycle_id" => pending.fetch("active_cycle_id"),
    "unresolved_count" => pending.dig("summary", "unresolved_count"),
    "items" => compact_items,
    "next_action" => pending.fetch("next_action"),
    "selection_overridden" => false
  }
  unless canonical_json_value(current.dig("frontier_binding", "selection")) == selection_before
    raise ReviewProjectionError, "review projection may not override current-next frontier selection"
  end
  yaml_bytes = YAML.dump(current)
  Tempfile.create(["current-next-review-projection", ".yaml"], yaml_path.dirname.to_s) do |candidate|
    candidate.write(yaml_bytes)
    candidate.flush
    validate_schema(CURRENT_NEXT_SCHEMA, Pathname.new(candidate.path), "current-next review projection")
  end
  atomic_write(yaml_path, yaml_bytes)

  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    CURRENT_NEXT_RENDERER.to_s,
    "--render-from-yaml",
    yaml_relative,
    "--output-md",
    md_relative,
    "--write",
    chdir: ROOT.to_s
  )
  unless status.success?
    raise ReviewProjectionError, "current-next Markdown refresh failed: #{[stderr, stdout].join(' ').strip}"
  end
  {
    "status" => "updated",
    "yaml" => {"path" => yaml_relative, "sha256" => Digest::SHA256.file(yaml_path).hexdigest},
    "markdown" => {"path" => md_relative, "sha256" => Digest::SHA256.file(md_path).hexdigest}
  }
end

def check_current_projection(source_set)
  digest = verify_source_set_digest(source_set)
  manifest_path, manifest_relative = repository_path(
    source_set.dig("outputs", "manifest_path"),
    "stable manifest"
  )
  manifest = load_document(manifest_path, "stable Founder workbench manifest")
  unless manifest.dig("run", "run_root") == source_set.fetch("run")
    raise ReviewProjectionError, "stable manifest belongs to another run"
  end
  unless manifest.dig("board", "source_set_digest") == digest
    raise ReviewProjectionError, "stable board source-set digest differs; refresh is required"
  end
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby,
    BOARD_RENDERER.to_s,
    "validate",
    manifest_path.to_s,
    "--json",
    chdir: ROOT.to_s
  )
  raise ReviewProjectionError, "stable board validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
  {
    "status" => "fresh",
    "manifest" => {
      "path" => manifest_relative,
      "sha256" => Digest::SHA256.file(manifest_path).hexdigest
    },
    "board_revision" => manifest.dig("board", "revision"),
    "active_cycle_id" => manifest.dig("board", "active_cycle_id"),
    "source_set_digest" => digest
  }
end

options = {
  write: false,
  json: false,
  check_current: false,
  prepare_from: nil,
  current_next_yaml: "automation/current-next.yaml",
  current_next_md: "automation/current-next.md"
}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_review_projection_assembler.rb SOURCE_SET.yaml [--prepare-from OWNER_INDEX.yaml] [--write|--check-current] [--json]"
  parser.on("--prepare-from PATH", "Compile or refresh the source set from the run-owned owner index before assembly.") { |value| options[:prepare_from] = value }
  parser.on("--current-next-yaml PATH", "Current-next YAML to update when it points to this run.") { |value| options[:current_next_yaml] = value }
  parser.on("--current-next-md PATH", "Derived current-next Markdown paired with --current-next-yaml.") { |value| options[:current_next_md] = value }
  parser.on("--write", "Atomically replace the stable derived manifest, HTML, and pending index.") { options[:write] = true }
  parser.on("--check-current", "Verify owner hashes, source-set digest, and the current stable board without writing.") { options[:check_current] = true }
  parser.on("--json", "Print a machine-readable result.") { options[:json] = true }
end.parse!

prepared_source_path = nil
prepared_source_before = nil
begin
  source_arg = ARGV.shift
  raise ReviewProjectionError, "SOURCE_SET.yaml is required" if source_arg.to_s.empty?
  raise ReviewProjectionError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  source_path, source_relative = repository_path(
    source_arg,
    "source set",
    must_exist: options[:prepare_from].nil? || !options[:write]
  )
  prepared_candidate = nil
  if options[:prepare_from]
    owner_index_path, = repository_path(options[:prepare_from], "review projection owner index")
    if options[:write]
      prepared_source_path = source_path
      prepared_source_before = source_path.exist? ? source_path.binread : nil
    end
    prepared_candidate = prepare_source_set(owner_index_path, source_path, write: options[:write])
  end
  validate_schema(SOURCE_SET_SCHEMA, source_path, "review projection source set")
  source_bytes = source_path.binread
  source_sha = Digest::SHA256.hexdigest(source_bytes)
  source_set = load_document(source_path, "review projection source set")
  if prepared_candidate && !options[:write] && source_set["source_set_digest"] != prepared_candidate["source_set_digest"]
    raise ReviewProjectionError, "owner index differs from the prepared source set; refresh is required"
  end
  raise ReviewProjectionError, "--write and --check-current are mutually exclusive" if options[:write] && options[:check_current]
  if options[:check_current]
    result = check_current_projection(source_set)
    if options[:json]
      puts JSON.pretty_generate(result)
    else
      puts "fresh: #{result.dig('manifest', 'path')} r#{result.fetch('board_revision')}"
    end
    exit 0
  end
  manifest, pending, summary = build_projection(source_set, source_relative, source_sha)

  manifest_output, = repository_path(source_set.dig("outputs", "manifest_path"), "manifest output", must_exist: false)
  html_output, = repository_path(source_set.dig("outputs", "html_path"), "HTML output", must_exist: false)
  pending_output, = repository_path(source_set.dig("outputs", "pending_path"), "pending output", must_exist: false)
  manifest_yaml = YAML.dump(manifest)

  Tempfile.create(["founder-workbench-candidate", ".yaml"], manifest_output.dirname.to_s) do |candidate|
    candidate.write(manifest_yaml)
    candidate.flush
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      BOARD_RENDERER.to_s,
      "validate",
      candidate.path,
      "--json",
      chdir: ROOT.to_s
    )
    raise ReviewProjectionError, "assembled board is invalid: #{[stderr, stdout].join(' ').strip}" unless status.success?
  end

  result = {
    "status" => options[:write] ? "written" : "validated",
    "source_set" => {"path" => source_relative, "sha256" => source_sha},
    "manifest" => {"path" => relative_path(manifest_output), "sha256" => Digest::SHA256.hexdigest(manifest_yaml)},
    "html" => {"path" => relative_path(html_output)},
    "pending" => {"path" => relative_path(pending_output), "status" => pending.fetch("status")},
    "summary" => summary,
    "source_set_prepared" => !options[:prepare_from].nil?
  }

  if options[:write]
    base_expected = source_set.dig("base_manifest", "sha256")
    current_base = Digest::SHA256.file(manifest_output).hexdigest
    raise ReviewProjectionError, "stable manifest changed during assembly; compare-and-swap aborted" unless current_base == base_expected
    current_source_sha = Digest::SHA256.file(source_path).hexdigest
    raise ReviewProjectionError, "source set changed during assembly; compare-and-swap aborted" unless current_source_sha == source_sha
    verify_source_set_digest(source_set)

    manifest_before = manifest_output.exist? ? manifest_output.binread : nil
    html_before = html_output.exist? ? html_output.binread : nil
    pending_before = pending_output.exist? ? pending_output.binread : nil
    current_next_yaml_path, = repository_path(options[:current_next_yaml], "current-next YAML", must_exist: false)
    current_next_md_path, = repository_path(options[:current_next_md], "current-next Markdown", must_exist: false)
    current_next_yaml_before = current_next_yaml_path.exist? ? current_next_yaml_path.binread : nil
    current_next_md_before = current_next_md_path.exist? ? current_next_md_path.binread : nil
    begin
      atomic_write(manifest_output, manifest_yaml)
      manifest_sha = Digest::SHA256.file(manifest_output).hexdigest
      pending.fetch("board_manifest")["sha256"] = manifest_sha
      pending_yaml = YAML.dump(pending)
      pending_output.dirname.mkpath
      Tempfile.create(["review-projection-pending", ".yaml"], pending_output.dirname.to_s) do |candidate|
        candidate.write(pending_yaml)
        candidate.flush
        validate_schema(PENDING_SCHEMA, Pathname.new(candidate.path), "review projection pending index")
      end
      atomic_write(pending_output, pending_yaml)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        BOARD_RENDERER.to_s,
        "render",
        manifest_output.to_s,
        "--json",
        chdir: ROOT.to_s
      )
      raise ReviewProjectionError, "stable board render failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
      result.fetch("manifest")["sha256"] = manifest_sha
      result.fetch("html")["sha256"] = Digest::SHA256.file(html_output).hexdigest
      result.fetch("pending")["sha256"] = Digest::SHA256.file(pending_output).hexdigest
      result["current_next"] = sync_current_next(
        source_set.fetch("run"),
        pending,
        pending_output,
        options[:current_next_yaml],
        options[:current_next_md]
      )
    rescue StandardError
      restore_path(manifest_output, manifest_before)
      restore_path(html_output, html_before)
      restore_path(pending_output, pending_before)
      restore_path(current_next_yaml_path, current_next_yaml_before)
      restore_path(current_next_md_path, current_next_md_before)
      raise
    end
  end

  if options[:json]
    puts JSON.pretty_generate(result)
  else
    puts "#{result.fetch('status')}: #{result.dig('manifest', 'path')} (#{summary.fetch('projected_asset_count')} assets, #{summary.fetch('unresolved_count')} unresolved)"
  end
rescue ReviewProjectionError, KeyError, TypeError, ArgumentError => e
  restore_path(prepared_source_path, prepared_source_before) if prepared_source_path
  warn "ERROR: #{e.message}"
  exit 1
end
