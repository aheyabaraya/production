#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "time"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
ACTIVE_SCHEMA = ROOT.join("schemas", "harness-current-next.schema.json")
LEGACY_SCHEMA = ROOT.join("schemas", "harness-current-next-v1-legacy.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")
DDI_SCHEMA_VERSION = "idol-director-dispatch-index.v4"
CURRENT_NEXT_SCHEMA_VERSION = "harness-current-next.v2"

def usage_error(message)
  warn "ERROR: #{message}"
  warn "usage: ruby scripts/idol_harness_current_next.rb RUN_ROOT [--director-dispatch-index PATH] [--next-unit LEGACY_PATH] [--founder-gate LEGACY_PATH] [--output-yaml PATH] [--output-md PATH] [--write]"
  warn "   or: ruby scripts/idol_harness_current_next.rb --render-from-yaml PATH [--output-md PATH] [--write|--check-readout]"
  exit 2
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_path(path)
  return nil if blank?(path)

  raw = Pathname.new(path.to_s)
  resolved = raw.absolute? ? raw.expand_path : ROOT.join(raw).expand_path
  root = ROOT.to_s
  usage_error("path escapes repository root: #{path}") unless resolved.to_s == root || resolved.to_s.start_with?("#{root}#{File::SEPARATOR}")
  resolved
end

def relative_path(path)
  resolve_path(path).relative_path_from(ROOT).to_s
end

def real_path_contained?(path, base)
  target = path.realpath.to_s
  root = base.realpath.to_s
  target == root || target.start_with?("#{root}#{File::SEPARATOR}")
rescue Errno::ENOENT, Errno::EACCES
  false
end

def load_yaml_hash(path, label)
  resolved = resolve_path(path)
  usage_error("#{label} is not readable: #{path}") unless resolved&.file?
  value = YAML.safe_load(
    resolved.read(encoding: "utf-8"),
    permitted_classes: [Date, Time],
    aliases: true
  )
  usage_error("#{label} must be a mapping") unless value.is_a?(Hash)
  value.transform_keys(&:to_s)
rescue Psych::Exception => error
  usage_error("cannot parse #{label}: #{error.message}")
end

def canonical_json_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      original = value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonical_json_value(value.fetch(original))
    end
  when Array
    value.map { |item| canonical_json_value(item) }
  when Date, Time
    value.iso8601
  else
    value
  end
end

def row_sha256(row)
  Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(row)))
end

def artifact_pointer(path, role)
  resolved = resolve_path(path)
  usage_error("artifact is not readable: #{path}") unless resolved&.file?
  usage_error("artifact resolves outside repository root: #{path}") unless real_path_contained?(resolved, ROOT)
  {
    "path" => resolved.relative_path_from(ROOT).to_s,
    "sha256" => Digest::SHA256.file(resolved).hexdigest,
    "role" => role
  }
end

def verified_binding(binding, label, expected_role: nil, required_path: nil)
  usage_error("#{label} must be an artifact binding") unless binding.is_a?(Hash)
  path = resolve_path(binding["path"])
  usage_error("#{label} is not readable: #{binding['path']}") unless path&.file?
  usage_error("#{label} resolves outside repository root") unless real_path_contained?(path, ROOT)
  expected = binding["sha256"].to_s
  usage_error("#{label} SHA-256 is malformed") unless expected.match?(/\A[a-f0-9]{64}\z/)
  actual = Digest::SHA256.file(path).hexdigest
  usage_error("#{label} SHA-256 is stale") unless actual == expected
  role = binding["role"].to_s
  usage_error("#{label} role must be #{expected_role}") if expected_role && role != expected_role
  if required_path
    required = resolve_path(required_path)
    usage_error("#{label} must bind #{relative_path(required)}") unless path == required
  end
  {"path" => relative_path(path), "sha256" => expected, "role" => role}
end

def same_binding?(left, right)
  %w[path sha256 role].all? { |key| left.is_a?(Hash) && right.is_a?(Hash) && left[key].to_s == right[key].to_s }
end

def validate_schema!(document, schema, label)
  Tempfile.create(["idol-current-next", ".yaml"]) do |candidate|
    candidate.write(YAML.dump(document))
    candidate.flush
    stdout, stderr, status = Open3.capture3(
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      schema.to_s,
      candidate.path,
      chdir: ROOT.to_s
    )
    usage_error("#{label} schema validation failed: #{[stderr, stdout].join(' ').strip}") unless status.success?
  end
end

def validate_ddi_order!(ddi)
  holds = Array(ddi["holds"])
  hold_ids = holds.map { |row| row.is_a?(Hash) ? row["hold_id"].to_s : "" }
  usage_error("DDI holds are not in canonical hold_id order") unless hold_ids == hold_ids.sort
  usage_error("DDI hold ids must be unique and non-empty") unless hold_ids.all? { |id| !id.empty? } && hold_ids.uniq.length == hold_ids.length

  queue = ddi["review_queue"]
  usage_error("DDI review_queue must be a mapping") unless queue.is_a?(Hash)
  unless queue["selection_order"].to_s == "dependency_rank_then_returned_at_then_dispatch_id"
    usage_error("DDI review queue selection order is unsupported")
  end
  items = Array(queue["items"])
  expected = items.sort_by do |row|
    [row["dependency_rank"].to_i, blank?(row["returned_at"]) ? "9999" : row["returned_at"].to_s, row["dispatch_id"].to_s]
  end
  usage_error("DDI review queue is not in its declared canonical order") unless items == expected

  action_ids = Array(ddi["next_actions"]).map { |row| row.is_a?(Hash) ? row["next_action_id"].to_s : "" }
  usage_error("DDI next-action ids must be unique and non-empty") unless action_ids.all? { |id| !id.empty? } && action_ids.uniq.length == action_ids.length

  heads = Array(ddi["current_heads"])
  expected_heads = heads.sort_by { |row| [row["stage_id"].to_s, row["logical_artifact_id"].to_s, row["head_id"].to_s] }
  usage_error("DDI canonical heads are not in canonical stage/artifact/head order") unless heads == expected_heads
end

def load_ddi(run_path, requested_path)
  exact_path = run_path.join("work", "director-dispatch-index.yaml").expand_path
  requested = resolve_path(requested_path || exact_path)
  usage_error("director dispatch index must use the exact run-owned path #{relative_path(exact_path)}") unless requested == exact_path
  ddi = load_yaml_hash(exact_path, "director dispatch index")
  usage_error("director dispatch index schema must be #{DDI_SCHEMA_VERSION}") unless ddi["schema_version"].to_s == DDI_SCHEMA_VERSION
  run_rel = relative_path(run_path)
  usage_error("director dispatch index belongs to another run") unless ddi["run"].to_s == run_rel
  source_set_sha = ddi["source_set_sha256"].to_s
  usage_error("director dispatch index source_set_sha256 is malformed") unless source_set_sha.match?(/\A[a-f0-9]{64}\z/)
  unless ddi.dig("source_set_digest", "sha256").to_s == source_set_sha
    usage_error("director dispatch index source-set hashes disagree")
  end
  validate_ddi_order!(ddi)
  binding = artifact_pointer(exact_path, "director_dispatch_index_v4")
  [ddi, binding]
end

def dispatch_rows_by_id(ddi)
  rows = Array(ddi["dispatches"])
  ids = rows.map { |row| row.is_a?(Hash) ? row["dispatch_id"].to_s : "" }
  usage_error("DDI dispatch ids must be unique and non-empty") unless ids.all? { |id| !id.empty? } && ids.uniq.length == ids.length
  rows.to_h { |row| [row["dispatch_id"].to_s, row] }
end

def action_dispatch_id(ddi, action_id)
  matches = Array(ddi["dispatches"]).select { |row| Array(row["next_action_ids"]).map(&:to_s).include?(action_id.to_s) }
  usage_error("DDI next action #{action_id} does not resolve to exactly one dispatch") unless matches.length == 1
  matches.first["dispatch_id"].to_s
end

def select_frontier(ddi)
  holds = Array(ddi["holds"])
  index = holds.index { |row| row.is_a?(Hash) && row["state"].to_s == "open" }
  if index
    row = holds.fetch(index)
    return {
      "kind" => "open_hold",
      "id" => row["hold_id"].to_s,
      "dispatch_id" => blank?(row["dispatch_id"]) ? nil : row["dispatch_id"].to_s,
      "json_pointer" => "/holds/#{index}",
      "row_sha256" => row_sha256(row),
      "state" => row["state"].to_s
    }
  end

  queue_items = Array(ddi.dig("review_queue", "items"))
  index = queue_items.index { |row| row.is_a?(Hash) && row["blocks_next"] == true }
  if index
    row = queue_items.fetch(index)
    return {
      "kind" => "review_queue",
      "id" => row["dispatch_id"].to_s,
      "dispatch_id" => row["dispatch_id"].to_s,
      "json_pointer" => "/review_queue/items/#{index}",
      "row_sha256" => row_sha256(row),
      "state" => row["queue_state"].to_s
    }
  end

  actions = Array(ddi["next_actions"])
  index = actions.index do |row|
    row.is_a?(Hash) && %w[open ready in_progress].include?(row["state"].to_s)
  end
  if index
    row = actions.fetch(index)
    action_id = row["next_action_id"].to_s
    return {
      "kind" => "next_action",
      "id" => action_id,
      "dispatch_id" => action_dispatch_id(ddi, action_id),
      "json_pointer" => "/next_actions/#{index}",
      "row_sha256" => row_sha256(row),
      "state" => row["state"].to_s
    }
  end

  has_indexed_evidence = !Array(ddi["dispatches"]).empty? ||
    !Array(ddi["current_heads"]).empty? ||
    !holds.empty? || !queue_items.empty? || !actions.empty? ||
    ddi.dig("dispatch_source_set", "entry_count").to_i.positive?
  {
    "kind" => has_indexed_evidence ? "no_actionable_unit" : "migration_hold",
    "id" => nil,
    "dispatch_id" => nil,
    "json_pointer" => nil,
    "row_sha256" => nil,
    "state" => has_indexed_evidence ? "none" : "ddi_has_no_indexed_dispatch_evidence"
  }
end

def canonical_head_projection(ddi, selection)
  heads = Array(ddi["current_heads"])
  current = []
  held_or_ambiguous = false
  heads.each_with_index do |row, index|
    usage_error("DDI current_heads[#{index}] must be a mapping") unless row.is_a?(Hash)
    state = row["state"].to_s
    ambiguous = row["supersession_state"].to_s == "ambiguous_hold"
    held_or_ambiguous ||= state == "held" || ambiguous
    next unless state == "current"

    artifact = verified_binding(row["artifact"], "DDI current_heads[#{index}].artifact")
    current << {
      "head_id" => row["head_id"].to_s,
      "json_pointer" => "/current_heads/#{index}",
      "row_sha256" => row_sha256(row),
      "artifact" => artifact
    }
  end
  if held_or_ambiguous && selection["kind"] != "open_hold"
    usage_error("DDI held or ambiguous canonical head lacks the required open HOLD frontier")
  end

  rows = dispatch_rows_by_id(ddi)
  selected_dispatch = rows[selection["dispatch_id"].to_s]
  if selected_dispatch
    matching = heads.select { |row| row["source_dispatch_id"].to_s == selection["dispatch_id"].to_s }
    invalid = matching.any? { |row| row["state"].to_s != "current" || row["supersession_state"].to_s == "ambiguous_hold" }
    if invalid && selection["kind"] != "open_hold"
      usage_error("selected dispatch resolves only to a held, stale, or ambiguous canonical head")
    end
    if selected_dispatch.dig("lifecycle", "current_state").to_s == "promoted" && matching.none? { |row| row["state"].to_s == "current" }
      usage_error("promoted selected dispatch lacks its corresponding current canonical head")
    end
  end

  resolution = if held_or_ambiguous
                 "held_or_ambiguous"
               elsif current.any?
                 "bound"
               elsif selected_dispatch
                 "not_yet_promoted"
               else
                 "none_declared"
               end
  {"resolution" => resolution, "items" => current}
end

def latest_file(pattern)
  paths = Dir.glob(ROOT.join(pattern).to_s).map { |path| Pathname.new(path) }.select(&:file?)
  paths.max_by { |path| [path.mtime, path.to_s] }
end

def optional_legacy_pointer(path, role)
  resolved = resolve_path(path)
  return nil unless resolved&.file?
  artifact_pointer(resolved, role)
end

def legacy_evidence(run_path, next_unit_option, founder_gate_option)
  content_id = run_path.basename.to_s
  next_unit_path = next_unit_option || latest_file("automation/next-units/*-#{content_id}-harness-next-unit.yaml")
  next_pointer = optional_legacy_pointer(next_unit_path, "legacy_harness_next_unit_v1")
  next_document = next_pointer ? load_yaml_hash(next_pointer["path"], "legacy next unit") : {}
  founder_gate_path = founder_gate_option || latest_file("automation/founder-gates/*-#{content_id}-03v-front-gate-*.yaml")
  action_queue_path = next_document["source_action_queue"]
  {
    "selection_authority" => false,
    "source_next_unit" => next_pointer,
    "source_founder_gate" => optional_legacy_pointer(founder_gate_path, "legacy_harness_founder_gate_v1"),
    "source_action_queue" => optional_legacy_pointer(action_queue_path, "legacy_harness_action_queue_v1")
  }
end

def pending_dispatch_ids(ddi)
  ids = Array(ddi["dispatches"]).map { |row| row["dispatch_id"].to_s }
  ids.concat(Array(ddi.dig("review_queue", "items")).map { |row| row["dispatch_id"].to_s })
  Array(ddi["next_actions"]).each do |action|
    action_id = action["next_action_id"].to_s
    matches = Array(ddi["dispatches"]).select { |row| Array(row["next_action_ids"]).map(&:to_s).include?(action_id) }
    ids.concat(matches.map { |row| row["dispatch_id"].to_s })
  end
  ids.reject(&:empty?).uniq
end

def review_projection_pending_summary(run_rel, ddi, ddi_binding)
  pending_path = resolve_path("#{run_rel}/work/review-projection-pending.yaml")
  return nil unless pending_path&.file?

  document = load_yaml_hash(pending_path, "review projection pending index")
  usage_error("review projection pending index is invalid") unless document["schema_version"].to_s == "idol-review-projection-pending.v1"
  usage_error("review projection pending index belongs to another run") unless document["run"].to_s == run_rel
  source_set_pointer = verified_binding(document["source_set"], "review projection source set")
  source_set = load_yaml_hash(source_set_pointer["path"], "review projection source set")
  usage_error("review projection source set must be v2") unless source_set["schema_version"].to_s == "idol-review-projection-source-set.v2"
  usage_error("review projection source set belongs to another run") unless source_set["run"].to_s == run_rel
  source_ddi = verified_binding(source_set["director_dispatch_index"], "review projection source-set DDI", expected_role: "director_dispatch_index_v4")
  usage_error("review projection source-set DDI differs from current-next DDI") unless same_binding?(source_ddi, ddi_binding)
  unless source_set.dig("outputs", "pending_path").to_s == relative_path(pending_path)
    usage_error("review projection source set points to another pending index")
  end
  board_manifest = verified_binding(document["board_manifest"], "review projection board manifest")
  unless source_set.dig("outputs", "manifest_path").to_s == board_manifest["path"]
    usage_error("review projection source set points to another board manifest")
  end
  board = load_yaml_hash(board_manifest["path"], "review projection board")
  usage_error("review projection board belongs to another run") unless board.dig("run", "run_root").to_s == run_rel
  usage_error("review projection pending revision differs from the board") unless board.dig("board", "revision") == document["board_revision"]
  unless board.dig("board", "active_cycle_id").to_s == document["active_cycle_id"].to_s
    usage_error("review projection pending cycle differs from the board")
  end
  unless board.dig("board", "source_set_digest") == source_set["source_set_digest"]
    usage_error("review projection board and source set digest differ")
  end
  items = Array(document["items"])
  unresolved = document.dig("summary", "unresolved_count")
  usage_error("review projection pending count is stale") unless unresolved.is_a?(Integer) && unresolved == items.length
  status = document["status"].to_s
  usage_error("review projection pending status is inconsistent") unless (status == "clear" && items.empty?) || (status == "pending" && !items.empty?)
  known_dispatch_ids = pending_dispatch_ids(ddi)
  compact_items = items.map.with_index do |item, index|
    usage_error("review projection pending item #{index + 1} is invalid") unless item.is_a?(Hash)
    item_ddi = verified_binding(item["director_dispatch_index"], "review projection pending item #{index + 1} DDI", expected_role: "director_dispatch_index_v4")
    usage_error("review projection pending item #{index + 1} DDI differs from current-next DDI") unless same_binding?(item_ddi, ddi_binding)
    dispatch_id = item["dispatch_id"].to_s
    usage_error("review projection pending item #{index + 1} references an unknown DDI dispatch") unless known_dispatch_ids.include?(dispatch_id)
    %w[asset_id binding_id source_stage dispatch_id].to_h { |key| [key, item[key].to_s] }
  end
  {
    "source" => artifact_pointer(pending_path, "review_projection_pending_index"),
    "director_dispatch_index" => ddi_binding.dup,
    "status" => status,
    "board_manifest" => board_manifest,
    "board_revision" => document["board_revision"],
    "active_cycle_id" => document["active_cycle_id"].to_s,
    "unresolved_count" => unresolved,
    "items" => compact_items,
    "next_action" => document["next_action"].to_s,
    "selection_overridden" => false
  }
end

def selection_status(selection)
  {
    "open_hold" => "hold",
    "review_queue" => "review_required",
    "next_action" => "ready",
    "no_actionable_unit" => "no_actionable_units",
    "migration_hold" => "migration_hold"
  }.fetch(selection["kind"])
end

def selection_owner(ddi, selection)
  return nil if selection["json_pointer"].nil?
  case selection["kind"]
  when "open_hold"
    Array(ddi["holds"])[selection["json_pointer"].split("/").last.to_i]["owner"].to_s
  when "review_queue"
    Array(ddi.dig("review_queue", "items"))[selection["json_pointer"].split("/").last.to_i]["director_owner"].to_s
  when "next_action"
    Array(ddi["next_actions"])[selection["json_pointer"].split("/").last.to_i]["owner"].to_s
  end.then { |value| blank?(value) ? nil : value }
end

def run_keys(run_path)
  relative = relative_path(run_path)
  segments = relative.split("/")
  if segments.length >= 4 && segments.first == "runs"
    [segments[-3], segments[-2]]
  elsif segments.length == 3 && segments.first == "runs"
    [segments[1], nil]
  else
    [run_path.parent.basename.to_s, nil]
  end
end

def build_payload(run_path, ddi_path, next_unit_option, founder_gate_option)
  run_rel = relative_path(run_path)
  ddi, ddi_binding = load_ddi(run_path, ddi_path)
  selection = select_frontier(ddi)
  canonical_heads = canonical_head_projection(ddi, selection)
  album_key, title_key = run_keys(run_path)
  payload = {
    "schema_version" => CURRENT_NEXT_SCHEMA_VERSION,
    "artifact_type" => "harness_current_next",
    "generated_at" => Time.now.iso8601,
    "run" => run_rel,
    "album_key" => album_key,
    "title_key" => title_key,
    "status" => selection_status(selection),
    "owner" => selection_owner(ddi, selection),
    "frontier_binding" => {
      "director_dispatch_index" => ddi_binding,
      "source_set_sha256" => ddi["source_set_sha256"].to_s,
      "selection" => selection,
      "canonical_heads" => canonical_heads
    },
    "legacy_evidence" => legacy_evidence(run_path, next_unit_option, founder_gate_option),
    "automation_boundaries" => [
      "DDI v4 is the only active frontier selection authority.",
      "Legacy Queue, Next Unit, Founder Gate, and review-pending files are evidence-only projections.",
      "This mechanical projection never authors creative truth, infers Founder approval, promotes a canonical head, or starts execution."
    ],
    "forbidden_actions" => [
      "Do not advance from a schema, hash, file-existence, or pointer-only PASS.",
      "Do not use legacy evidence or review-projection pending rows to override frontier_binding.selection.",
      "Do not perform generation, upload, external mutation, release, or destructive cleanup from this pointer."
    ],
    "refresh_commands" => [
      "ruby scripts/idol_director_dispatch_index.rb build #{run_rel} --json",
      "ruby scripts/idol_director_dispatch_index.rb validate #{ddi_binding['path']} --json",
      "ruby scripts/idol_harness_current_next.rb #{run_rel} --write",
      "scripts/idol-video-python scripts/validate_json_schema.py schemas/harness-current-next.schema.json automation/current-next.yaml",
      "ruby scripts/idol_harness_frontier_check.rb #{run_rel} --json"
    ]
  }
  pending = review_projection_pending_summary(run_rel, ddi, ddi_binding)
  payload["review_projection_pending"] = pending if pending
  validate_schema!(payload, ACTIVE_SCHEMA, "current-next v2")
  payload
end

def build_v2_markdown(payload, source_yaml_path:, source_yaml_sha256:)
  binding = payload.fetch("frontier_binding")
  selection = binding.fetch("selection")
  heads = binding.fetch("canonical_heads")
  lines = [
    "# IDOL Graph Engineering Current Next",
    "",
    "derived_from: `#{source_yaml_path}`",
    "source_yaml_sha256: `#{source_yaml_sha256}`",
    "generated_at: `#{payload['generated_at']}`",
    "run: `#{payload['run']}`",
    "status: `#{payload['status']}`",
    "owner: `#{payload['owner'] || 'none'}`",
    "",
    "## Active DDI Frontier",
    "",
    "- DDI: `#{binding.dig('director_dispatch_index', 'path')}` (`#{binding.dig('director_dispatch_index', 'sha256')}`)",
    "- DDI source set: `#{binding['source_set_sha256']}`",
    "- selection: `#{selection['kind']}` / `#{selection['id'] || 'none'}` / `#{selection['state']}`",
    "- dispatch: `#{selection['dispatch_id'] || 'none'}`",
    "- exact row: `#{selection['json_pointer'] || 'none'}` / `#{selection['row_sha256'] || 'none'}`",
    "",
    "## Canonical Heads",
    "",
    "- resolution: `#{heads['resolution']}`"
  ]
  Array(heads["items"]).each do |item|
    lines << "- `#{item['head_id']}` → `#{item.dig('artifact', 'path')}` (`#{item['json_pointer']}`, `#{item['row_sha256']}`)"
  end
  pending = payload["review_projection_pending"]
  if pending.is_a?(Hash)
    lines.concat([
      "",
      "## Review Projection Pending",
      "",
      "- status: `#{pending['status']}`",
      "- DDI: `#{pending.dig('director_dispatch_index', 'path')}` (`#{pending.dig('director_dispatch_index', 'sha256')}`)",
      "- unresolved: #{pending['unresolved_count']}",
      "- selection_overridden: `#{pending['selection_overridden']}`"
    ])
    Array(pending["items"]).each do |item|
      lines << "- `#{item['asset_id']}` / `#{item['binding_id']}` → `#{item['dispatch_id']}` (#{item['source_stage']})"
    end
    lines << "- next: #{pending['next_action']}"
  end
  lines.concat(["", "## Legacy Evidence (No Selection Authority)", "", "- selection_authority: `false`"])
  payload.fetch("legacy_evidence").each do |key, value|
    next if key == "selection_authority"
    lines << "- #{key}: `#{value.is_a?(Hash) ? value['path'] : 'none'}`"
  end
  lines.concat(["", "## Automation Boundaries", ""])
  Array(payload["automation_boundaries"]).each { |row| lines << "- #{row}" }
  lines.concat(["", "## Forbidden Actions", ""])
  Array(payload["forbidden_actions"]).each { |row| lines << "- #{row}" }
  lines.concat(["", "## Refresh Commands", ""])
  Array(payload["refresh_commands"]).each { |row| lines << "- `#{row}`" }
  lines.join("\n")
end

def build_legacy_markdown(payload, source_yaml_path:, source_yaml_sha256:)
  lines = [
    "# IDOL Graph Engineering Current Next (Legacy v1 Evidence)",
    "",
    "derived_from: `#{source_yaml_path}`",
    "source_yaml_sha256: `#{source_yaml_sha256}`",
    "generated_at: `#{payload['generated_at']}`",
    "run: `#{payload['run']}`",
    "status: `#{payload['status']}`",
    "owner: `#{payload['owner']}`",
    "selected_next_unit: `#{payload['selected_unit_id']}`",
    "",
    "This v1 document is frozen legacy evidence and has no active frontier selection authority."
  ]
  pending = payload["review_projection_pending"]
  if pending.is_a?(Hash)
    lines.concat(["", "## Review Projection Pending", "", "- status: `#{pending['status']}`", "- unresolved: #{pending['unresolved_count']}"])
  end
  lines.join("\n")
end

def render_markdown(payload, source_yaml_path:, source_yaml_sha256:)
  case payload["schema_version"].to_s
  when CURRENT_NEXT_SCHEMA_VERSION
    build_v2_markdown(payload, source_yaml_path: source_yaml_path, source_yaml_sha256: source_yaml_sha256)
  when "harness-current-next.v1"
    build_legacy_markdown(payload, source_yaml_path: source_yaml_path, source_yaml_sha256: source_yaml_sha256)
  else
    usage_error("unsupported current-next schema version #{payload['schema_version'].inspect}")
  end
end

def atomic_write(path, bytes)
  path.dirname.mkpath
  Tempfile.create([".idol-current-next", path.extname], path.dirname.to_s) do |candidate|
    candidate.binmode
    candidate.write(bytes)
    candidate.flush
    candidate.fsync
    File.rename(candidate.path, path.to_s)
  end
end

options = {
  director_dispatch_index: nil,
  next_unit: nil,
  founder_gate: nil,
  output_yaml: nil,
  output_md: nil,
  render_from_yaml: nil,
  check_readout: false,
  write: false
}

OptionParser.new do |parser|
  parser.on("--director-dispatch-index PATH") { |value| options[:director_dispatch_index] = value }
  parser.on("--next-unit PATH") { |value| options[:next_unit] = value }
  parser.on("--founder-gate PATH") { |value| options[:founder_gate] = value }
  parser.on("--output-yaml PATH") { |value| options[:output_yaml] = value }
  parser.on("--output-md PATH") { |value| options[:output_md] = value }
  parser.on("--render-from-yaml PATH") { |value| options[:render_from_yaml] = value }
  parser.on("--check-readout") { options[:check_readout] = true }
  parser.on("--write") { options[:write] = true }
end.parse!

if options[:check_readout] && blank?(options[:render_from_yaml])
  usage_error("--check-readout requires --render-from-yaml PATH")
end

unless blank?(options[:render_from_yaml])
  usage_error("--write and --check-readout are mutually exclusive") if options[:write] && options[:check_readout]
  unless blank?(options[:director_dispatch_index]) && blank?(options[:next_unit]) && blank?(options[:founder_gate]) && blank?(options[:output_yaml])
    usage_error("--render-from-yaml cannot be combined with build inputs or --output-yaml")
  end
  source_path = resolve_path(options[:render_from_yaml])
  payload = load_yaml_hash(source_path, "canonical current-next YAML")
  schema = payload["schema_version"].to_s == CURRENT_NEXT_SCHEMA_VERSION ? ACTIVE_SCHEMA : LEGACY_SCHEMA
  validate_schema!(payload, schema, "canonical current-next YAML")
  source_bytes = source_path.binread
  source_sha = Digest::SHA256.hexdigest(source_bytes)
  markdown = render_markdown(payload, source_yaml_path: relative_path(source_path), source_yaml_sha256: source_sha)
  output_path = resolve_path(options[:output_md] || source_path.to_s.sub(/\.ya?ml\z/i, ".md"))
  usage_error("derived Markdown path must differ from canonical YAML path") if output_path == source_path
  if options[:check_readout]
    usage_error("derived current-next Markdown is missing: #{relative_path(output_path)}") unless output_path.file?
    unless output_path.binread == markdown.b
      warn "ERROR: derived current-next Markdown is stale for #{relative_path(source_path)} (sha256=#{source_sha})"
      exit 1
    end
    puts "OK: #{relative_path(output_path)} is derived from #{relative_path(source_path)} (sha256=#{source_sha})"
  elsif options[:write]
    atomic_write(output_path, markdown)
    puts "wrote #{relative_path(output_path)} from #{relative_path(source_path)} (sha256=#{source_sha})"
  else
    puts markdown
  end
  exit 0
end

run_arg = ARGV.shift
usage_error("RUN_ROOT is required") if blank?(run_arg) || !ARGV.empty?
run_path = resolve_path(run_arg)
usage_error("RUN_ROOT is not a directory: #{run_arg}") unless run_path&.directory?

payload = build_payload(run_path, options[:director_dispatch_index], options[:next_unit], options[:founder_gate])
yaml_text = YAML.dump(payload)
output_yaml = resolve_path(options[:output_yaml] || "automation/current-next.yaml")
output_md = resolve_path(options[:output_md] || "automation/current-next.md")
markdown = render_markdown(
  payload,
  source_yaml_path: relative_path(output_yaml),
  source_yaml_sha256: Digest::SHA256.hexdigest(yaml_text)
)

if options[:write]
  atomic_write(output_yaml, yaml_text)
  atomic_write(output_md, markdown)
  puts "wrote #{relative_path(output_yaml)}"
  puts "wrote #{relative_path(output_md)}"
else
  puts yaml_text
end
