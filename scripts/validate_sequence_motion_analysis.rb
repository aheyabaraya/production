#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
ACTIVE_SCHEMA_VERSION = "idol_sequence_motion_analysis.v1"
ACTIVE_FRONT_PLANNING_VERSION = "front-planning-readiness.v17"
ACTIVE_AUDIO_MOTION_VERSION = "idol_audio_motion_director_map.v1"
ACTIVE_DISPATCH_VERSION = "idol-department-dispatch.v8"
SEQUENCE_FRAME_COUNT = 5
SEQUENCE_CADENCE_SECONDS = 1.0
CADENCE_TOLERANCE = 0.001
MEASUREMENT_CONTRACT_VERSION = "idol_sequence_motion_machine_measurement.v1"
CAMERA_SUBJECT_AMBIGUITY = "unresolved_2d_projection_cannot_separate_camera_from_subject"
ACTIVE_SEQUENCE_DISPATCH_STATES = %w[prepared launched returned reviewed].freeze
SEQUENCE_PROMPT_CONTEXT_BEGIN = "SEQUENCE_MOTION_CURRENT_VALUES_CANONICAL_JSON_BEGIN"
SEQUENCE_PROMPT_CONTEXT_END = "SEQUENCE_MOTION_CURRENT_VALUES_CANONICAL_JSON_END"
SEQUENCE_PROMPT_CLAUSES = [
  "Conditional visible identity: do not require a readable face in every cut; when identity is visible, preserve exact current-title identity.",
  "No forced frontal face or gaze: side, rear, silhouette, occluded, wide, and fast-turn views remain legal when they serve the scene.",
  "Member-specific visible cues: preserve every visible member-specific hair, styling, clothing, silhouette, and detail cue even when the face is unreadable.",
  "Continuous camera energy is a hypothesis: test it against body action, gaze, camera translation and rotation, lens, angle, composition, depth, occlusion, reveal, and start-to-landing evidence; it is never a forced default.",
  "Intentional locked hold is allowed: retain a motivated static or locked choice when it is stronger than movement."
].freeze

options = {root: ROOT, json: false, max_errors: 60, pre_cdd_copy: false}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_sequence_motion_analysis.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--pre-cdd-copy", "Transport admission only: require a returned DDC and exact pending target bytes; never grants CDD review or downstream validity.") { options[:pre_cdd_copy] = true }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!

artifact_arg = ARGV.shift
abort "Sequence Motion Analysis path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "#{path} must contain an object" unless value.is_a?(Hash)
  value
end

def canonical_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
      result[key] = canonical_value(value[source_key])
    end
  when Array
    value.map { |item| canonical_value(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def inside?(path, root)
  lexical = path.relative_path_from(root).to_s
  return false if lexical == ".." || lexical.start_with?("../")

  ancestor = path
  suffix = []
  until ancestor.exist?
    suffix.unshift(ancestor.basename.to_s)
    parent = ancestor.parent
    return false if parent == ancestor
    ancestor = parent
  end
  resolved = suffix.reduce(ancestor.realpath) { |current, part| current.join(part) }.cleanpath
  real_root = root.realpath
  relative = resolved.relative_path_from(real_root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
end

def pointer_value(document, pointer)
  current = document
  pointer.to_s.split("/")[1..].to_a.each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    current = if current.is_a?(Array) && token.match?(/\A(?:0|[1-9]\d*)\z/)
                current.fetch(token.to_i)
              elsif current.is_a?(Hash)
                current.fetch(token)
              else
                raise KeyError, "pointer traverses a scalar"
              end
  end
  current
end

def validate_file_ref(ref, label, root, errors)
  path = resolve_path(ref.to_h["path"], root)
  unless inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository"
    return nil
  end
  errors << "#{label} SHA-256 is stale" unless Digest::SHA256.file(path).hexdigest == ref.to_h["sha256"].to_s
  path
end

def relative_repo_path(path, root)
  path.relative_path_from(root).to_s
rescue ArgumentError
  path.to_s
end

def run_command_validator(command, root, errors, label)
  stdout, stderr, status = Open3.capture3(*command, chdir: root.to_s)
  return if status.success?

  detail = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
  errors << "#{label} failed: #{detail}"
end

def final_dispatch_reviewed_output?(dispatch, artifact_relative, artifact_sha)
  return false unless dispatch.dig("lifecycle", "current_state").to_s == "promoted"
  return false unless dispatch.dig("director_review", "disposition").to_s == "accept"
  return false unless dispatch.dig("director_review", "director", "role").to_s == "creative_development_director"
  return false unless dispatch.dig("promotion", "decision").to_s == "promoted"

  Array(dispatch.dig("director_review", "reviewed_outputs")).any? do |row|
    row.to_h["path"].to_s == artifact_relative && row.to_h["sha256"].to_s == artifact_sha
  end && Array(dispatch.dig("runtime_return", "outputs")).any? do |row|
    row.to_h["path"].to_s == artifact_relative && row.to_h["sha256"].to_s == artifact_sha
  end
end

def validate_value_binding(binding, source, expected_pointer, label, errors)
  binding = binding.to_h
  pointer = binding["source_json_pointer"].to_s
  errors << "#{label} pointer must be #{expected_pointer}" unless pointer == expected_pointer
  begin
    value = pointer_value(source, pointer)
    errors << "#{label} value SHA-256 is stale" unless binding["source_value_sha256"].to_s == value_sha256(value)
    value
  rescue KeyError, IndexError, TypeError
    errors << "#{label} pointer is stale"
    nil
  end
end

def validate_schema(path, schema, root, errors, label)
  stdout, stderr, status = Open3.capture3(
    root.join("scripts", "idol-video-python").to_s,
    root.join("scripts", "validate_json_schema.py").to_s,
    schema.to_s,
    path.to_s,
    chdir: root.to_s
  )
  errors << "#{label} JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def stable_candidate_snapshot(major)
  candidate_set = major.to_h["sequence_composition_candidate_set"].to_h
  {
    "major_scene_id" => major.to_h["major_scene_id"],
    "section_id" => major.to_h["section_id"],
    "semantic_event_or_relation_job" => major.to_h["semantic_event_or_relation_job"],
    "candidate_set_id" => candidate_set["candidate_set_id"],
    "candidates" => Array(candidate_set["candidates"]).map do |candidate|
      {
        "sequence_composition_id" => candidate["sequence_composition_id"],
        "typed_sequence_unit_ids" => candidate["typed_sequence_unit_ids"],
        "flow_reading" => candidate["flow_reading"],
        "mismatch_and_risk" => candidate["mismatch_and_risk"]
      }
    end
  }
end

def stable_prompt_context(front, major)
  stable_candidate_snapshot(major).merge(
    "active_storyline_passage" => front.dig("storyline_lineage", "active_version", "full_storyline_text")
  )
end

def admitted_source_owner(path, root, run_root)
  current_intake = run_root.join("research", "reference-intake").expand_path.cleanpath
  if inside?(path, current_intake)
    parts = path.relative_path_from(current_intake).each_filename.to_a
    return nil if parts.length < 2

    return {"kind" => "current_run_reference_intake", "owner_root" => current_intake.join(parts.first)}
  end

  hub_root = root.join("source-materials", "video-sources").expand_path.cleanpath
  return nil unless inside?(path, hub_root)

  parts = path.relative_path_from(hub_root).each_filename.to_a
  return nil unless parts.length >= 4 && parts[1] == "by-source"

  {"kind" => "registered_video_source_hub", "owner_root" => hub_root.join(parts[0], parts[1], parts[2])}
rescue ArgumentError
  nil
end

def same_admitted_owner?(path, owner)
  owner && inside?(path, owner.fetch("owner_root")) && !path.symlink?
end

def validate_qc_sheet_manifest(manifest_document, manifest_path, video_path, video_ref, governing_unit, root, run_root, label, errors)
  owner = admitted_source_owner(manifest_path, root, run_root)
  if owner.nil? || manifest_path.symlink?
    errors << "#{label} governing manifest must be owned by the exact current-run reference-intake unit or a registered video-source hub owner"
    return
  end
  video_owner = admitted_source_owner(video_path, root, run_root)
  unless video_owner && video_owner["kind"] == owner["kind"] && video_owner["owner_root"] == owner["owner_root"] && !video_path.symlink?
    errors << "#{label} source video and governing manifest must share one exact admitted owner boundary"
  end

  admitted_video = manifest_document["source_video"].to_h
  admitted_path = resolve_path(admitted_video["path"], root)
  errors << "#{label} governing manifest source_video path differs from inspected video" unless admitted_path == video_path
  errors << "#{label} governing manifest source_video SHA differs from inspected video" unless admitted_video["sha256"].to_s == video_ref["sha256"].to_s
  if video_path&.file?
    errors << "#{label} governing manifest source_video size is stale" unless admitted_video["size_bytes"].is_a?(Integer) && admitted_video["size_bytes"] == video_path.size
  end
  errors << "#{label} governing manifest video field differs from source_video path" unless resolve_path(manifest_document["video"], root) == admitted_path

  sheets = manifest_document["sheets"]
  unless sheets.is_a?(Array) && sheets.any? && manifest_document["sheet_count"] == sheets.length
    errors << "#{label} governing manifest requires a nonempty exact ordered sheet set"
    return
  end

  cell_ids = {}
  sheet_paths = {}
  ordered_cells = []
  sheets.each_with_index do |sheet, sheet_index|
    sheet = sheet.to_h
    expected_part = sheet_index + 1
    errors << "#{label} governing manifest sheet part_index order must be contiguous from 1" unless sheet["part_index"] == expected_part
    sheet_path = resolve_path(sheet["path"], root)
    sheet_path_key = relative_repo_path(sheet_path, root)
    errors << "#{label} governing manifest sheet paths must be globally unique" if sheet_paths.key?(sheet_path_key)
    sheet_paths[sheet_path_key] = true
    unless same_admitted_owner?(sheet_path, owner) && sheet_path.file?
      errors << "#{label} governing manifest sheet #{expected_part} is missing, symlinked, or outside its admitted owner"
      next
    end
    sheet_sha = Digest::SHA256.file(sheet_path).hexdigest
    errors << "#{label} governing manifest sheet #{expected_part} SHA is stale" unless sheet["sha256"].to_s == sheet_sha
    errors << "#{label} governing manifest sheet #{expected_part} size is stale" unless sheet["size_bytes"].is_a?(Integer) && sheet["size_bytes"] == sheet_path.size && sheet_path.size.positive?
    timestamps = sheet["timestamps"]
    cells = sheet["cells"]
    count = sheet["timestamp_count"]
    unless timestamps.is_a?(Array) && cells.is_a?(Array) && cells.any? && count.is_a?(Integer) && count == timestamps.length && count == cells.length
      errors << "#{label} governing manifest sheet #{expected_part} timestamps/cells/count must be exact and nonempty"
      next
    end
    cells.each_with_index do |cell, cell_index|
      cell = cell.to_h
      expected_order = cell_index + 1
      cell_id = cell["cell_id"].to_s
      errors << "#{label} governing manifest cell order must be contiguous within sheet #{expected_part}" unless cell["order"] == expected_order
      errors << "#{label} governing manifest cell ids must be nonempty and globally unique" if cell_id.empty? || cell_ids.key?(cell_id)
      cell_ids[cell_id] = true unless cell_id.empty?
      timestamp = cell["source_timestamp_seconds"]
      unless timestamp.is_a?(Numeric) && timestamps[cell_index].is_a?(Numeric) && (timestamp.to_f - timestamps[cell_index].to_f).abs <= CADENCE_TOLERANCE
        errors << "#{label} governing manifest cell #{cell_id} timestamp differs from its ordered sheet timestamp"
      end
      crop = cell["cell_crop"]
      if crop
        crop = crop.to_h
        crop_path = resolve_path(crop["path"], root)
        unless same_admitted_owner?(crop_path, owner) && crop_path.file?
          errors << "#{label} governing manifest cell #{cell_id} crop is missing, symlinked, or outside its admitted owner"
        else
          errors << "#{label} governing manifest cell #{cell_id} crop SHA is stale" unless crop["sha256"].to_s == Digest::SHA256.file(crop_path).hexdigest
          errors << "#{label} governing manifest cell #{cell_id} crop size is stale" unless crop["size_bytes"].is_a?(Integer) && crop["size_bytes"] == crop_path.size && crop_path.size.positive?
        end
      end
      ordered_cells << {"cell_id" => cell_id, "timestamp" => timestamp, "cell_crop" => crop}
    end
  end

  ordered_cells.each_cons(2) do |left, right|
    unless left["timestamp"].is_a?(Numeric) && right["timestamp"].is_a?(Numeric) && right["timestamp"].to_f > left["timestamp"].to_f
      errors << "#{label} governing manifest cell timestamps must be globally strictly increasing in sheet/cell order"
      break
    end
  end

  frames = Array(governing_unit.to_h["ordered_frames"])
  matched_indexes = frames.map do |frame|
    ordered_cells.index { |cell| cell["cell_id"] == frame["source_frame_or_cell_id"].to_s }
  end
  if matched_indexes.any?(&:nil?) || matched_indexes.each_cons(2).any? { |left, right| right != left + 1 }
    errors << "#{label} governing Sequence Unit frames must exact-match one consecutive ordered manifest cell span"
  else
    frames.each_with_index do |frame, frame_index|
      cell = ordered_cells.fetch(matched_indexes.fetch(frame_index))
      errors << "#{label} governing Sequence Unit frame #{frame_index + 1} timestamp differs from its manifest cell" unless cell["timestamp"].is_a?(Numeric) && (cell["timestamp"].to_f - frame["timestamp_seconds"].to_f).abs <= CADENCE_TOLERANCE
      next unless cell["cell_crop"].is_a?(Hash)

      artifact_ref = frame["artifact"].to_h
      unless artifact_ref["path"].to_s == cell.dig("cell_crop", "path").to_s && artifact_ref["sha256"].to_s == cell.dig("cell_crop", "sha256").to_s
        errors << "#{label} governing Sequence Unit frame #{frame_index + 1} must exact-copy its manifest cell crop path/SHA"
      end
    end
  end
end

def fresh_file_binding?(row, root)
  row = row.to_h
  return false if row["path"].to_s.empty?

  path = resolve_path(row["path"], root)
  inside?(path, root) && path.file? && !path.symlink? && row["sha256"].to_s == Digest::SHA256.file(path).hexdigest
rescue Errno::ENOENT, Errno::EACCES
  false
end

def pinned_file_binding?(row, root)
  row = row.to_h
  path = row["path"].to_s
  sha = row["sha256"].to_s
  return false if path.empty? || !sha.match?(/\A[0-9a-f]{64}\z/)

  resolved = resolve_path(path, root)
  inside?(resolved, root) && resolved.file? && !resolved.symlink?
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
end

def skill_read_signature(row)
  row = row.to_h
  {
    "path" => row["path"],
    "revision" => row["revision"],
    "sha256" => row["sha256"],
    "linked_reads" => Array(row["linked_reads"]).map { |read| {"path" => read["path"], "sha256" => read["sha256"]} }
  }
end

def verifiably_terminal_sequence_dispatch?(peer_path, peer, root)
  state = peer.dig("lifecycle", "current_state").to_s
  return false unless %w[promoted hold].include?(state)
  return false unless peer_path.basename.to_s == "#{peer['dispatch_id']}.yaml"
  return false unless peer["runtime_return"].is_a?(Hash) && peer["director_review"].is_a?(Hash) && peer["promotion"].is_a?(Hash)
  return false unless peer.dig("promotion", "decision").to_s == state

  _stdout, _stderr, schema_status = Open3.capture3(
    root.join("scripts", "idol-video-python").to_s,
    root.join("scripts", "validate_json_schema.py").to_s,
    root.join("schemas", "department-dispatch.schema.json").to_s,
    peer_path.to_s,
    chdir: root.to_s
  )
  return false unless schema_status.success?

  expected_states = %w[prepared launched returned reviewed] + [state]
  events = Array(peer.dig("lifecycle", "events"))
  return false unless events.map { |event| event["state"].to_s } == expected_states
  return false unless events.last.to_h["at"].to_s == peer.dig("promotion", "decided_at").to_s
  return false unless events[-2].to_h["at"].to_s == peer.dig("director_review", "reviewed_at").to_s

  selected_profile = peer.dig("launch", "compiled_launch_prompt", "selected_profile").to_h
  return false unless selected_profile["profile_id"].to_s == "reference_research_generalist" && selected_profile["checkpoint_id"].to_s == "reference_story_sequence_role"

  required_skills = Array(peer.dig("launch", "required_skills"))
  return false if required_skills.empty?
  required_skills.each do |skill|
    return false unless pinned_file_binding?(skill, root)
    return false unless Array(skill["linked_reads"]).all? { |read| pinned_file_binding?(read, root) }
  end
  runtime_skills = Array(peer.dig("runtime_return", "skill_revisions"))
  return false unless runtime_skills.map { |row| skill_read_signature(row) } == required_skills.map { |row| skill_read_signature(row) }
  return false unless runtime_skills.all? do |skill|
    skill["read_to_eof"] == true && pinned_file_binding?(skill, root) &&
      Array(skill["linked_reads"]).all? { |read| read["read_to_eof"] == true && pinned_file_binding?(read, root) }
  end

  requirements = Array(peer.dig("launch", "requirement_manifest"))
  return false if requirements.empty?
  requirements.each do |requirement|
    binding = requirement["source_binding"]
    return false if binding.is_a?(Hash) && !pinned_file_binding?(binding, root)
  end

  runtime = peer.fetch("runtime_return")
  expected_input_sha = value_sha256(
    "lineage" => peer["lineage"],
    "review_submission" => peer["review_submission"],
    "launch" => peer["launch"]
  )
  return false unless runtime.dig("input_digest", "basis").to_s == "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4"
  return false unless runtime.dig("input_digest", "sha256").to_s == expected_input_sha

  receipt = runtime["mechanical_compliance_receipt"].to_h
  return false unless receipt["receipt_sha256"].to_s == value_sha256(receipt.reject { |key, _value| key.to_s == "receipt_sha256" })
  completion_basis = {
    "mechanical_compliance_receipt_sha256" => receipt["receipt_sha256"],
    "worker_fulfillment_claims" => runtime["worker_fulfillment_claims"],
    "outputs" => runtime["outputs"],
    "hold_reasons" => runtime["hold_reasons"]
  }
  return false unless runtime.dig("runtime_goal", "completion_evidence_sha256").to_s == value_sha256(completion_basis)
  result_basis = %w[
    work_started_at runtime_owner runtime_goal skill_revisions
    mechanical_compliance_receipt worker_fulfillment_claims output_inventory
    outputs hold_reasons wake_event
  ].to_h { |key| [key, runtime[key]] }
  return false unless runtime.dig("result_digest", "basis").to_s == "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4"
  return false unless runtime.dig("result_digest", "sha256").to_s == value_sha256(result_basis)

  output_rows = Array(runtime["outputs"])
  return false unless output_rows.all? { |row| fresh_file_binding?(row, root) }
  return false unless canonical_value(Array(runtime.dig("wake_event", "output_pointers"))) == canonical_value(output_rows)

  review = peer.fetch("director_review")
  return false unless review.dig("director", "role").to_s == "creative_development_director"
  return false unless review.dig("director", "owner").to_s == peer.dig("launch", "authority", "director_owner").to_s
  return false unless review["mechanical_receipt_sha256"].to_s == receipt["receipt_sha256"].to_s
  return false unless canonical_value(Array(review["reviewed_outputs"])) == canonical_value(output_rows)
  return false unless Array(review["reviewed_outputs"]).all? { |row| fresh_file_binding?(row, root) }
  required_ids = requirements.select { |row| row["required"] == true }.map { |row| row["requirement_id"].to_s }
  result_rows = Array(review["requirement_results"])
  return false unless result_rows.map { |row| row["requirement_id"].to_s }.sort == required_ids.sort
  return false if state == "promoted" && result_rows.any? { |row| row["result"].to_s != "pass" }
  disposition_is_terminal = state == "promoted" ? review["disposition"].to_s == "accept" : review["disposition"].to_s != "accept"
  return false unless disposition_is_terminal

  expected_reviewer_pairs = required_skills.flat_map do |skill|
    [[skill["path"].to_s, skill["sha256"].to_s]] + Array(skill["linked_reads"]).map { |read| [read["path"].to_s, read["sha256"].to_s] }
  end
  requirements.each do |requirement|
    next unless requirement["director_semantic_review_required"] == true && %w[skill policy contract schema].include?(requirement["category"].to_s)
    binding = requirement["source_binding"]
    expected_reviewer_pairs << [binding["path"].to_s, binding["sha256"].to_s] if binding.is_a?(Hash)
  end
  expected_reviewer_pairs.uniq!
  reviewer_reads = Array(review["reviewer_read_closure"])
  actual_reviewer_pairs = reviewer_reads.map { |row| [row["path"].to_s, row["sha256"].to_s] }
  return false unless actual_reviewer_pairs.uniq.length == actual_reviewer_pairs.length && actual_reviewer_pairs.sort == expected_reviewer_pairs.sort
  return false unless reviewer_reads.all? { |row| row["read_to_eof"] == true && pinned_file_binding?(row, root) }

  promotion = peer.fetch("promotion")
  review_control = peer["review_control"].to_h
  return false unless review_control["queue_state"].to_s == "released" && promotion["queue_release_verified"] == true
  return false unless promotion["promotion_lease_id"].to_s == review_control.dig("promotion_lease", "lease_id").to_s
  return false unless review["review_lease_id"].to_s == review_control.dig("review_lease", "lease_id").to_s
  return false unless review_control.dig("review_lease", "director_owner").to_s == peer.dig("launch", "authority", "director_owner").to_s
  return false unless review_control.dig("promotion_lease", "overall_owner").to_s == peer.dig("launch", "authority", "promotion_owner").to_s
  return false unless promotion.dig("promoter", "role").to_s == "overall_director" && promotion.dig("promoter", "owner").to_s == peer.dig("launch", "authority", "promotion_owner").to_s
  return false unless events[-2].to_h["actor"].to_s == review.dig("director", "owner").to_s && events.last.to_h["actor"].to_s == promotion.dig("promoter", "owner").to_s
  promotion_basis = {
    "dispatch_id" => peer["dispatch_id"],
    "review_lease_id" => review["review_lease_id"],
    "promotion_lease_id" => promotion["promotion_lease_id"],
    "decision" => promotion["decision"],
    "approved_working_outputs" => promotion["approved_working_outputs"],
    "canonical_artifacts" => promotion["canonical_artifacts"],
    "decided_at" => promotion["decided_at"]
  }
  return false unless promotion["baseline_refresh_evidence_sha256"].to_s == value_sha256(promotion_basis)
  approved_rows = Array(promotion["approved_working_outputs"])
  canonical_rows = Array(promotion["canonical_artifacts"])
  return false unless approved_rows.all? { |row| fresh_file_binding?(row, root) } && canonical_rows.all? { |row| fresh_file_binding?(row, root) }
  if state == "promoted"
    return false unless promotion["mode"].to_s == "direct_canonical_promotion" && promotion["approved_at"].to_s == promotion["decided_at"].to_s
    return false unless promotion["coordinator"].nil? && promotion["copy_completed_at"].nil?
    return false unless canonical_value(approved_rows) == canonical_value(output_rows) && canonical_value(canonical_rows) == canonical_value(output_rows)
  else
    return false unless promotion["mode"].to_s == "held_without_promotion" && promotion["approved_at"].nil?
    return false unless promotion["coordinator"].nil? && promotion["copy_completed_at"].nil?
    return false unless approved_rows.empty? && canonical_rows.empty?
  end

  true
rescue Errno::ENOENT, Errno::EACCES
  false
end

def discover_active_sequence_dispatch_conflicts(ddc_dir, current_dispatch_path, run_relative, expected_group_relative, major_scene_id, root, errors)
  return unless inside?(ddc_dir, root) && ddc_dir.directory?

  Dir.glob(ddc_dir.join("*.{yaml,yml,json}").to_s).sort.each do |raw_path|
    peer_path = Pathname.new(raw_path).expand_path.cleanpath
    next if peer_path == current_dispatch_path
    begin
      peer = load_mapping(peer_path)
    rescue JSON::ParserError, Psych::Exception, TypeError => error
      errors << "cannot prove disjoint Sequence ownership because #{relative_repo_path(peer_path, root)} is unreadable: #{error.message}" if peer_path.basename.to_s.start_with?("sequence-motion-analysis-")
      next
    end
    sequence_dispatch = peer["dispatch_id"].to_s.start_with?("sequence-motion-analysis-") || peer.dig("routing_identity", "worker_specialty").to_s == "reference_story_sequence"
    next unless sequence_dispatch && peer["run"].to_s == run_relative

    artifact_paths = Array(peer.dig("launch", "task", "exact_scope", "artifact_paths")).map(&:to_s)
    if artifact_paths.length != 1
      errors << "overlap HOLD: active Sequence DDC #{peer['dispatch_id']} has no single provably disjoint Major artifact scope"
      next
    end
    peer_artifact = artifact_paths.first
    match = peer_artifact.match(%r{\A(.+/research/sequence-motion-analysis/(S[0-9]{2,}[A-Z]?--MJ[0-9]{2,}[A-Z0-9_]*))/attempt-[0-9]{2,}\.yaml\z})
    unless match
      errors << "overlap HOLD: active Sequence DDC #{peer['dispatch_id']} has a malformed atomic Major scope"
      next
    end
    peer_group = match[1]
    peer_major = match[2].split("--", 2).last
    next unless peer_group == expected_group_relative || peer_major == major_scene_id.to_s

    state = peer.dig("lifecycle", "current_state").to_s
    next if %w[promoted hold].include?(state) && verifiably_terminal_sequence_dispatch?(peer_path, peer, root)

    if %w[promoted hold].include?(state)
      errors << "overlap HOLD: Sequence DDC #{peer['dispatch_id']} claims terminal state without verifiable runtime, Director review, promotion, and exact DDC closure"
    elsif ACTIVE_SEQUENCE_DISPATCH_STATES.include?(state)
      errors << "overlap HOLD: active Sequence DDC #{peer['dispatch_id']} owns the same Major candidate-group scope"
    else
      errors << "overlap HOLD: same-Major Sequence DDC #{peer['dispatch_id']} has unknown or nonterminal lifecycle state #{state.inspect}"
    end
  end
end

def validate_explicit_machine_measurement_binding(review, video_path, video_ref, frame_times, admitted_range, root, label, errors)
  binding = review["machine_measurement_binding"]
  return if binding.nil?

  unless binding.is_a?(Hash)
    errors << "#{label} machine_measurement_binding must be an object or null"
    return
  end
  path = validate_file_ref(binding, "#{label} machine_measurement_binding", root, errors)
  return unless path

  errors << "#{label} machine_measurement_binding cannot be a symlink" if path.symlink?
  errors << "#{label} machine_measurement_binding schema_version must be #{MEASUREMENT_CONTRACT_VERSION}" unless binding["schema_version"].to_s == MEASUREMENT_CONTRACT_VERSION
  validate_schema(path, root.join("schemas", "sequence-motion-machine-measurement.schema.json"), root, errors, "#{label} machine measurement")
  begin
    measured = JSON.parse(path.read)
  rescue JSON::ParserError => error
    errors << "#{label} machine measurement is not JSON: #{error.message}"
    return
  end

  unless video_path
    errors << "#{label} machine measurement cannot be checked without a live inspected video"
    return
  end
  live_video_sha = video_path.file? ? Digest::SHA256.file(video_path).hexdigest : nil
  unless measured.dig("source", "sha256").to_s == video_ref["sha256"].to_s && live_video_sha && measured.dig("source", "sha256").to_s == live_video_sha
    errors << "#{label} machine measurement source SHA must equal the live inspected video SHA"
  end
  samples = Array(measured["sequence_sample_timestamps_seconds"]).map(&:to_f)
  unless samples.length == SEQUENCE_FRAME_COUNT && frame_times.length == SEQUENCE_FRAME_COUNT && samples.each_with_index.all? { |time, index| (time - frame_times[index]).abs <= CADENCE_TOLERANCE }
    errors << "#{label} machine measurement sample timestamps must exact-match the governing Sequence Unit timestamps"
  end
  samples.each_cons(2).with_index do |(current, following), index|
    unless ((following - current) - SEQUENCE_CADENCE_SECONDS).abs <= CADENCE_TOLERANCE
      errors << "#{label} machine measurement samples #{index + 1}-#{index + 2} are not exact one-second cadence"
    end
  end
  unless samples.any? && samples.min >= admitted_range["start"].to_f && samples.max <= admitted_range["end"].to_f
    errors << "#{label} machine measurement samples must lie inside the admitted source range"
  end
  unless measured.dig("admitted_time_range_seconds", "start").to_f == admitted_range["start"].to_f && measured.dig("admitted_time_range_seconds", "end").to_f == admitted_range["end"].to_f
    errors << "#{label} machine measurement admitted range must exact-copy the inspected source admitted range"
  end
  Array(measured["motion_timeline"]).each_with_index do |row, index|
    unless row.to_h["camera_subject_ambiguity"].to_s == CAMERA_SUBJECT_AMBIGUITY
      errors << "#{label} motion_timeline[#{index}] must leave camera/subject ambiguity unresolved"
    end
  end
  pts = Array(measured["motion_timeline"]).map { |row| row.to_h["pts_seconds"] }
  unless pts.all? { |value| value.is_a?(Numeric) && value.to_f.finite? } && pts.each_cons(2).all? { |left, right| right > left }
    errors << "#{label} machine measurement motion_timeline PTS must be finite and strictly increasing"
  end
  Array(measured["scene_cut_discontinuities"]).each_with_index do |row, index|
    errors << "#{label} scene_cut_discontinuities[#{index}] must remain candidate_discontinuity" unless row.to_h["status"].to_s == "candidate_discontinuity"
  end
end

def validate_sequence_unit(unit, label, errors)
  frames = Array(unit.to_h["ordered_frames"])
  observations = Array(unit.to_h["frame_observations"])
  errors << "#{label} must retain exactly five ordered frames" unless frames.length == SEQUENCE_FRAME_COUNT
  errors << "#{label} must retain exactly five frame observations" unless observations.length == SEQUENCE_FRAME_COUNT
  errors << "#{label} order must be exactly 1..5" unless frames.map { |row| row["order_index"].to_i } == (1..SEQUENCE_FRAME_COUNT).to_a
  cadence = unit.to_h["declared_cadence_seconds"].to_f
  unless (cadence - SEQUENCE_CADENCE_SECONDS).abs <= CADENCE_TOLERANCE
    errors << "#{label} active cadence must be exact one-second; legacy three-second units are read-only and cannot enter new analysis"
  end
  frames.map { |row| row["timestamp_seconds"].to_f }.each_cons(2).with_index do |(current, following), index|
    unless ((following - current) - SEQUENCE_CADENCE_SECONDS).abs <= CADENCE_TOLERANCE
      errors << "#{label} frames #{index + 1}-#{index + 2} are not consecutive exact one-second samples"
    end
  end
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
document = {}

unless inside?(artifact, root) && artifact.file?
  errors << "Sequence Motion Analysis is missing or outside the repository"
else
  errors << "Sequence Motion Analysis artifact cannot be a symlink" if artifact.symlink?
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot parse Sequence Motion Analysis: #{error.message}"
  end
end

if artifact.file?
  validate_schema(artifact, root.join("schemas", "sequence-motion-analysis.schema.json"), root, errors, "Sequence Motion Analysis")
end

front = nil
front_path = nil
audio_map = nil
major = nil
candidate_set = nil
candidate_rows = []

if document.any?
  errors << "only #{ACTIVE_SCHEMA_VERSION} is active" unless document["schema_version"].to_s == ACTIVE_SCHEMA_VERSION
  run_root = resolve_path(document["run_root"], root)
  run_relative = inside?(run_root, root) ? relative_repo_path(run_root, root) : ""
  unless run_relative.match?(%r{\Aruns/[^/]+/[^/]+/[^/]+\z}) && inside?(run_root, root) && run_root.directory?
    errors << "run_root must be one exact runs/ALBUM/TITLE/RUN directory inside the repository"
  end
  run_manifest_path = run_root.join("run-manifest.yaml")
  if inside?(run_manifest_path, run_root) && run_manifest_path.file?
    begin
      run_manifest = load_mapping(run_manifest_path)
      errors << "run manifest canonical_run_root differs from analysis run_root" unless run_manifest["canonical_run_root"].to_s == run_relative
      errors << "run manifest content_id differs from analysis" unless run_manifest["content_id"].to_s == document["content_id"].to_s
      errors << "run manifest must be active" unless run_manifest["status"].to_s == "active"
    rescue JSON::ParserError, Psych::Exception, TypeError => error
      errors << "cannot parse run manifest: #{error.message}"
    end
  else
    errors << "run_root must contain its active run-manifest.yaml"
  end
  errors << "analysis artifact must remain inside run_root" unless inside?(artifact, run_root)
  attempt_key = document.dig("dispatch_and_authorship", "attempt_key").to_s
  deterministic_artifact = run_root.join(
    "research",
    "sequence-motion-analysis",
    "#{document['section_id']}--#{document['major_scene_id']}",
    "#{attempt_key}.yaml"
  ).expand_path.cleanpath
  expected_analysis_relative = relative_repo_path(deterministic_artifact, root)
  if options[:pre_cdd_copy]
    errors << "pre-Cdd-copy transport admission requires ready_for_cdd_review status" unless document["status"].to_s == "ready_for_cdd_review"
  elsif artifact != deterministic_artifact
    errors << "strict Sequence Motion validation requires the deterministic run-local analysis path"
  end

  source_front = document["source_front_planning"].to_h
  front_path = resolve_path(source_front["path"], root)
  if !inside?(front_path, root) || !front_path.file?
    errors << "source_front_planning path is missing or outside the repository"
  else
    begin
      front = load_mapping(front_path)
      errors << "source Front Planning must be #{ACTIVE_FRONT_PLANNING_VERSION}" unless front["schema_version"].to_s == ACTIVE_FRONT_PLANNING_VERSION
      errors << "content_id differs from source Front Planning" unless document["content_id"].to_s == front["content_id"].to_s
      errors << "source_front_planning intentionally must not contain a whole-file sha256" if source_front.key?("sha256")
      errors << "source Front Planning must remain inside the declared run_root" unless inside?(front_path, run_root)

      major_index = Array(front["major_scene_catalog"]).index do |row|
        row["major_scene_id"].to_s == document["major_scene_id"].to_s
      end
      if major_index.nil?
        errors << "major_scene_id does not resolve in source Front Planning"
      else
        major = Array(front["major_scene_catalog"]).fetch(major_index)
        candidate_set = major["sequence_composition_candidate_set"].to_h
        candidate_rows = Array(candidate_set["candidates"])
        base = "/major_scene_catalog/#{major_index}"
        major_id = validate_value_binding(source_front["major_scene_id_binding"], front, "#{base}/major_scene_id", "source_front_planning.major_scene_id_binding", errors)
        section_id = validate_value_binding(source_front["section_id_binding"], front, "#{base}/section_id", "source_front_planning.section_id_binding", errors)
        validate_value_binding(source_front["semantic_event_or_relation_job_binding"], front, "#{base}/semantic_event_or_relation_job", "source_front_planning.semantic_event_or_relation_job_binding", errors)
        validate_value_binding(source_front["candidate_set_id_binding"], front, "#{base}/sequence_composition_candidate_set/candidate_set_id", "source_front_planning.candidate_set_id_binding", errors)
        errors << "major_scene_id binding differs from analysis scope" unless major_id.to_s == document["major_scene_id"].to_s
        errors << "section_id binding differs from analysis scope" unless section_id.to_s == document["section_id"].to_s

        source_candidate_bindings = Array(source_front["candidate_bindings"])
        errors << "source candidate bindings must exact-cover the complete candidate group in order" unless source_candidate_bindings.map { |row| row["sequence_composition_id"].to_s } == candidate_rows.map { |row| row["sequence_composition_id"].to_s }
        source_candidate_bindings.each_with_index do |binding, index|
          candidate = candidate_rows[index]
          next unless candidate
          candidate_base = "#{base}/sequence_composition_candidate_set/candidates/#{index}"
          errors << "candidate binding #{index} composition id differs" unless binding["sequence_composition_id"].to_s == candidate["sequence_composition_id"].to_s
          validate_value_binding(binding["sequence_composition_id_binding"], front, "#{candidate_base}/sequence_composition_id", "candidate #{index} id binding", errors)
          validate_value_binding(binding["typed_sequence_unit_ids_binding"], front, "#{candidate_base}/typed_sequence_unit_ids", "candidate #{index} Sequence Unit binding", errors)
          validate_value_binding(binding["flow_reading_binding"], front, "#{candidate_base}/flow_reading", "candidate #{index} Flow Reading binding", errors)
          validate_value_binding(binding["mismatch_and_risk_binding"], front, "#{candidate_base}/mismatch_and_risk", "candidate #{index} mismatch binding", errors)
        end
        expected_snapshot_sha = value_sha256(stable_candidate_snapshot(major))
        unless source_front["candidate_snapshot_sha256"].to_s == expected_snapshot_sha
          errors << "source_front_planning candidate_snapshot_sha256 is stale"
        end
      end

      active_passage_pointer = "/storyline_lineage/active_version/full_storyline_text"
      validate_value_binding(document.dig("analysis_scope", "active_storyline_passage_binding"), front, active_passage_pointer, "analysis_scope.active_storyline_passage_binding", errors)
    rescue JSON::ParserError, Psych::Exception, TypeError => error
      errors << "cannot parse source Front Planning: #{error.message}"
    end
  end

  audio_ref = document["source_audio_motion_map"].to_h
  audio_path = validate_file_ref(audio_ref, "source_audio_motion_map", root, errors)
  if audio_path
    begin
      audio_map = load_mapping(audio_path)
      errors << "source audio motion map must be #{ACTIVE_AUDIO_MOTION_VERSION}" unless audio_map["schema_version"].to_s == ACTIVE_AUDIO_MOTION_VERSION && audio_ref["schema_version"].to_s == ACTIVE_AUDIO_MOTION_VERSION
      errors << "source audio motion map content_id differs from analysis" unless audio_map["content_id"].to_s == document["content_id"].to_s
      errors << "source audio motion map must be ready_for_00a" unless audio_map["status"].to_s == "ready_for_00a"
      errors << "source audio motion map must remain in the declared run research boundary" unless inside?(audio_path, run_root.join("research"))
      run_command_validator(
        [RbConfig.ruby, root.join("scripts", "validate_audio_motion_director_map.rb").to_s, audio_path.to_s],
        root,
        errors,
        "source audio motion map owner validation"
      )
    rescue JSON::ParserError, Psych::Exception, TypeError => error
      errors << "cannot parse source audio motion map: #{error.message}"
    end
  end

  if major && candidate_set
    scope = document["analysis_scope"].to_h
    candidate_ids = candidate_rows.map { |row| row["sequence_composition_id"].to_s }
    errors << "analysis_scope candidate_set_id differs from Front Planning" unless scope["candidate_set_id"].to_s == candidate_set["candidate_set_id"].to_s
    errors << "analysis_scope candidate_ids must exact-cover the complete candidate group in order" unless Array(scope["candidate_ids"]).map(&:to_s) == candidate_ids
    analyses = Array(document["candidate_analyses"])
    errors << "candidate_analyses must exact-cover the complete candidate group in order" unless analyses.map { |row| row["sequence_composition_id"].to_s } == candidate_ids

    front_units = Array(front.dig("reference_connection_research", "reference_units"))
    observed_event_owners = {}
    analyses.each_with_index do |analysis, analysis_index|
      candidate = candidate_rows[analysis_index]
      next unless candidate
      label = "candidate_analyses[#{analysis_index}]"
      errors << "#{label} candidate_source_binding differs from source_front_planning snapshot binding" unless canonical_value(analysis["candidate_source_binding"]) == canonical_value(Array(document.dig("source_front_planning", "candidate_bindings"))[analysis_index])
      expected_unit_ids = Array(candidate["typed_sequence_unit_ids"]).map(&:to_s)
      unit_bindings = Array(analysis["sequence_unit_bindings"])
      errors << "#{label} Sequence Unit bindings must exact-cover its candidate" unless unit_bindings.map { |row| row["sequence_unit_id"].to_s } == expected_unit_ids
      unit_bindings.each_with_index do |binding, unit_index|
        ref_index = front_units.index { |row| row.dig("sequence_unit", "sequence_unit_id").to_s == binding["sequence_unit_id"].to_s }
        if ref_index.nil?
          errors << "#{label} Sequence Unit #{binding['sequence_unit_id']} does not resolve"
          next
        end
        unit_pointer = "/reference_connection_research/reference_units/#{ref_index}/sequence_unit"
        unit = validate_value_binding(binding, front, unit_pointer, "#{label}.sequence_unit_bindings[#{unit_index}]", errors)
        expected_flow_pointer = "#{unit_pointer}/flow_reading"
        flow = begin
          pointer_value(front, expected_flow_pointer)
        rescue KeyError, IndexError
          nil
        end
        errors << "#{label} Sequence Unit flow pointer differs" unless binding["flow_reading_json_pointer"].to_s == expected_flow_pointer
        errors << "#{label} Sequence Unit flow hash is stale" unless binding["flow_reading_value_sha256"].to_s == value_sha256(flow)
        validate_sequence_unit(unit, "#{label} #{binding['sequence_unit_id']}", errors) if unit.is_a?(Hash)
      end

      Array(analysis["audio_motion_cue_bindings"]).each_with_index do |binding, cue_index|
        next unless audio_map
        begin
          cue = pointer_value(audio_map, binding["source_json_pointer"])
          errors << "#{label} audio cue #{cue_index} value SHA-256 is stale" unless binding["source_value_sha256"].to_s == value_sha256(cue)
          expected_cue_id = cue.to_h["trigger_id"] || cue.to_h["section_id"]
          errors << "#{label} audio cue #{cue_index} id differs" unless binding["cue_id"].to_s == expected_cue_id.to_s
          errors << "#{label} audio cue #{cue_index} section differs" unless cue.to_h["section_id"].to_s == document["section_id"].to_s
        rescue KeyError, IndexError, TypeError
          errors << "#{label} audio cue #{cue_index} pointer is stale"
        end
      end

      review = analysis["continuous_motion_source_review"].to_h
      if review["inspection_status"] != "inspected" && !review["machine_measurement_binding"].nil?
        errors << "#{label} machine_measurement_binding is only legal on an inspected source video"
      end
      if review["inspection_status"] == "inspected"
        video_ref = review["source_video"].to_h
        video_path = validate_file_ref(video_ref, "#{label} source video", root, errors)
        if video_path && (admitted_source_owner(video_path, root, run_root).nil? || video_path.symlink?)
          errors << "#{label} source video must be an exact current-run reference-intake file or a registered video-source hub file, never arbitrary or cross-run bytes"
        end
        governing_id = video_ref["governing_sequence_unit_id"].to_s
        governing_binding = unit_bindings.find { |row| row["sequence_unit_id"].to_s == governing_id }
        governing_reference = front_units.find { |row| row.dig("sequence_unit", "sequence_unit_id").to_s == governing_id }
        if governing_binding.nil?
          errors << "#{label} inspected source video must name one governing candidate Sequence Unit"
        else
          unless governing_reference && video_ref["source_identity"].to_s == governing_reference["source_identity"].to_s
            errors << "#{label} source video source_identity must exact-copy its governing Front Planning reference unit"
          end
          unless governing_reference && video_ref["inspected_locator"].to_s == governing_reference["selected_locator"].to_s
            errors << "#{label} source video inspected_locator must exact-copy its governing Front Planning reference unit selected_locator"
          end
          begin
            governing_unit = pointer_value(front, governing_binding["source_json_pointer"])
            manifest_ref = governing_unit.to_h["manifest"].to_h
            manifest_path = validate_file_ref(manifest_ref, "#{label} governing Sequence Unit manifest", root, errors)
            errors << "#{label} source video governing_manifest_path must exact-copy the Sequence Unit manifest" unless video_ref["governing_manifest_path"].to_s == manifest_ref["path"].to_s
            if manifest_path
              manifest_document = load_mapping(manifest_path)
              errors << "#{label} governing manifest must be idol_video_qc_sheet_manifest.v1" unless manifest_document["schema_version"].to_s == "idol_video_qc_sheet_manifest.v1"
              if video_path
                validate_qc_sheet_manifest(manifest_document, manifest_path, video_path, video_ref, governing_unit, root, run_root, label, errors)
              end
            end
            frame_times = Array(governing_unit.to_h["ordered_frames"]).map { |row| row["timestamp_seconds"].to_f }
            admitted_range = video_ref["admitted_time_range_seconds"].to_h
            unless frame_times.length == SEQUENCE_FRAME_COUNT && admitted_range["start"].is_a?(Numeric) && admitted_range["end"].is_a?(Numeric) && frame_times.min >= admitted_range["start"].to_f && frame_times.max <= admitted_range["end"].to_f
              errors << "#{label} governing Sequence Unit timestamps must lie inside the admitted source range"
            end
            validate_explicit_machine_measurement_binding(
              review,
              video_path,
              video_ref,
              frame_times,
              admitted_range,
              root,
              label,
              errors
            )
          rescue JSON::ParserError, Psych::Exception, TypeError, KeyError, IndexError => error
            errors << "#{label} governing Sequence Unit manifest is invalid: #{error.message}"
          end
        end
        Array(review["observed_interframe_events"]).each do |event|
          event_id = event["event_id"].to_s
          if observed_event_owners.key?(event_id)
            errors << "observed event id #{event_id} must be globally unique across the complete Major candidate group"
          else
            observed_event_owners[event_id] = label
          end
          range = event["source_time_range_seconds"].to_h
          errors << "#{label} observed event #{event_id} end must be after start" unless range["end"].to_f > range["start"].to_f
          admitted_range = video_ref["admitted_time_range_seconds"].to_h
          unless range["start"].to_f >= admitted_range["start"].to_f && range["end"].to_f <= admitted_range["end"].to_f
            errors << "#{label} observed event #{event_id} exceeds the admitted Sequence Unit time boundary"
          end
          unknown = Array(event["related_sequence_unit_ids"]).map(&:to_s) - expected_unit_ids
          errors << "#{label} observed event #{event_id} names unrelated Sequence Units" unless unknown.empty?
          unless Array(event["related_sequence_unit_ids"]).map(&:to_s).include?(governing_id)
            errors << "#{label} observed event #{event_id} must include its governing Sequence Unit"
          end
        end
      end
      observed_count = Array(review["observed_interframe_events"]).length
      observed_ids = Array(review["observed_interframe_events"]).map { |row| row["event_id"].to_s }
      support_finding = analysis["motion_support_finding"].to_h
      unsupported_full_orbit_dimensions = %w[rear_world_direction identity].select do |dimension|
        support_finding.dig(dimension, "support_state").to_s == "unsupported"
      end
      Array(analysis["inferred_camera_opportunities"]).each do |opportunity|
        cited_observed_ids = Array(opportunity["observed_event_ids"]).map(&:to_s)
        if Array(opportunity["inference_basis"]).include?("observed_interframe_event") && observed_count.zero?
          errors << "#{label} inferred opportunity #{opportunity['opportunity_id']} cites an observed event but none exists"
        end
        if Array(opportunity["inference_basis"]).include?("observed_interframe_event")
          errors << "#{label} inferred opportunity #{opportunity['opportunity_id']} must bind exact observed event ids" unless cited_observed_ids.any? && (cited_observed_ids - observed_ids).empty?
        elsif cited_observed_ids.any?
          errors << "#{label} inferred opportunity #{opportunity['opportunity_id']} cannot bind observed event ids without observed evidence basis"
        end
        literal = opportunity["literal_transfer"].to_h
        if literal["supported"] == true
          errors << "#{label} literal transfer requires an inspected continuous source video" unless review["inspection_status"].to_s == "inspected"
          literal_ids = Array(literal["observed_event_ids"]).map(&:to_s)
          errors << "#{label} literal transfer must bind only exact observed event ids" unless literal_ids.any? && (literal_ids - observed_ids).empty?
          errors << "#{label} literal transfer inference must cite observed_interframe_event" unless Array(opportunity["inference_basis"]).include?("observed_interframe_event")
          errors << "#{label} literal transfer observed id must also be cited by its inferred opportunity" unless (literal_ids - cited_observed_ids).empty?
          observed_event = Array(review["observed_interframe_events"]).find { |event| event["event_id"].to_s == literal_ids.first }
          if observed_event
            exact_literal_fields = {
              "source_motion_family" => "observed_motion_family",
              "perceptual_functions" => "observed_perceptual_functions",
              "camera_translation_fact" => "observed_camera_translation_fact",
              "camera_rotation_fact" => "observed_camera_rotation_fact",
              "rotation_degrees" => "observed_rotation_degrees",
              "full_orbit_completed" => "observed_full_orbit_completed",
              "lens_change_fact" => "observed_lens_change_fact"
            }
            exact_literal_fields.each do |literal_field, observed_field|
              unless canonical_value(literal[literal_field]) == canonical_value(observed_event[observed_field])
                errors << "#{label} literal transfer #{literal_field} must exact-copy cited observed event #{literal_ids.first} #{observed_field}"
              end
            end
          end
        elsif Array(literal["observed_event_ids"]).any?
          errors << "#{label} unsupported literal transfer cannot bind observed event ids"
        end
        function = opportunity["function_equivalent_transfer"].to_h
        if unsupported_full_orbit_dimensions.any?
          if literal["supported"] == true && literal["source_motion_family"].to_s == "full_orbit"
            errors << "#{label} literal full_orbit must be held when #{unsupported_full_orbit_dimensions.join(' and ')} support is unsupported"
          end
          if Array(function["alternative_motion_families"]).map(&:to_s).include?("full_orbit")
            errors << "#{label} function-equivalent alternatives must exclude full_orbit when #{unsupported_full_orbit_dimensions.join(' and ')} support is unsupported"
          end
        end
        if literal["supported"] != true && function["supported"] != true && document["status"].to_s != "hold"
          errors << "#{label} no-safe-motion result requires analysis HOLD (locked_hold remains available as a supported function-equivalent family)"
        end
      end
    end

    recommendation = document["comparative_recommendation"].to_h
    errors << "comparative recommendation candidate ids must exact-cover the analyzed group" unless Array(recommendation["compared_candidate_ids"]).map(&:to_s) == candidate_ids
    errors << "comparative recommendation does not resolve" unless candidate_ids.include?(recommendation["recommended_sequence_composition_id"].to_s)
  end

  dispatch = document["dispatch_and_authorship"].to_h
  dispatch_binding = dispatch["dispatch_contract"].to_h
  dispatch_path = resolve_path(dispatch_binding["path"], root)
  dispatch_document = nil
  if !inside?(dispatch_path, root) || !dispatch_path.file?
    errors << "dispatch_and_authorship.dispatch_contract is missing or outside the repository"
  else
    begin
      dispatch_document = load_mapping(dispatch_path)
      if options[:pre_cdd_copy]
        validate_schema(dispatch_path, root.join("schemas", "department-dispatch.schema.json"), root, errors, "returned Department Dispatch v8")
      else
        run_command_validator(
          [RbConfig.ruby, root.join("scripts", "validate_department_dispatch.rb").to_s, "--require-promoted", dispatch_path.to_s],
          root,
          errors,
          "Department Dispatch v8 owner validation"
        )
      end
      attempt_number = dispatch["attempt_number"].to_i
      expected_attempt_key = format("attempt-%02d", attempt_number)
      errors << "attempt_key must deterministically encode attempt_number" unless attempt_key == expected_attempt_key
      expected_dispatch_id = "sequence-motion-analysis-#{document['major_scene_id']}--#{attempt_key}"
      errors << "dispatch schema must be #{ACTIVE_DISPATCH_VERSION}" unless dispatch_document["schema_version"].to_s == ACTIVE_DISPATCH_VERSION && dispatch_binding["schema_version"].to_s == ACTIVE_DISPATCH_VERSION
      errors << "dispatch id must be #{expected_dispatch_id}" unless dispatch_document["dispatch_id"].to_s == expected_dispatch_id && dispatch_binding["dispatch_id"].to_s == expected_dispatch_id
      errors << "dispatch lineage attempt_id must equal its exact assignment id" unless dispatch_document.dig("lineage", "attempt_id").to_s == expected_dispatch_id && dispatch_binding["attempt_id"].to_s == expected_dispatch_id
      errors << "dispatch must live in the declared run Department Dispatch directory" unless dispatch_path == run_root.join("work", "department-dispatches", "#{expected_dispatch_id}.yaml")
      errors << "dispatch run differs from analysis run_root" unless dispatch_document["run"].to_s == run_relative
      errors << "analysis attempt_number must exact-copy DDC lineage" unless dispatch_document.dig("lineage", "attempt_number").to_i == attempt_number
      errors << "analysis previous_attempt_id must exact-copy DDC lineage" unless canonical_value(dispatch["previous_attempt_id"]) == canonical_value(dispatch_document.dig("lineage", "previous_attempt_id"))
      if attempt_number == 1
        errors << "first Sequence Motion attempt cannot name a predecessor" unless dispatch["previous_attempt_id"].nil?
      elsif attempt_number > 1
        previous_attempt_id = dispatch["previous_attempt_id"].to_s
        expected_previous_attempt_id = "sequence-motion-analysis-#{document['major_scene_id']}--#{format('attempt-%02d', attempt_number - 1)}"
        errors << "Sequence Motion previous_attempt_id must name the exact same-Major immediately preceding attempt" unless previous_attempt_id == expected_previous_attempt_id
        previous_path = dispatch_path.dirname.join("#{previous_attempt_id}.yaml")
        if previous_attempt_id.empty? || !inside?(previous_path, run_root) || !previous_path.file? || previous_path.symlink?
          errors << "later Sequence Motion attempt must resolve its immutable predecessor DDC in the same run"
        else
          previous_dispatch = load_mapping(previous_path)
          previous_lineage = previous_dispatch["lineage"].to_h
          errors << "Sequence Motion predecessor id/path binding is stale" unless previous_dispatch["dispatch_id"].to_s == previous_attempt_id && previous_lineage["attempt_id"].to_s == previous_attempt_id
          errors << "Sequence Motion predecessor must preserve the same run and lineage" unless previous_dispatch["run"].to_s == run_relative && previous_lineage["lineage_id"].to_s == dispatch_document.dig("lineage", "lineage_id").to_s
          errors << "Sequence Motion predecessor attempt number must be consecutive" unless previous_lineage["attempt_number"].to_i == attempt_number - 1
          errors << "Sequence Motion predecessor must close with an internally exact immutable terminal receipt before a successor attempt" unless verifiably_terminal_sequence_dispatch?(previous_path, previous_dispatch, root)
          previous_paths = Array(previous_dispatch.dig("launch", "task", "exact_scope", "artifact_paths")).map(&:to_s)
          expected_previous_artifact = run_root.join("research", "sequence-motion-analysis", "#{document['section_id']}--#{document['major_scene_id']}", format("attempt-%02d.yaml", attempt_number - 1))
          errors << "Sequence Motion predecessor must own the same Major at its immutable prior-attempt path" unless previous_paths == [relative_repo_path(expected_previous_artifact, root)]
        end
      end
      task = dispatch_document.dig("launch", "task").to_h
      exact_scope = task["exact_scope"].to_h
      errors << "dispatch task id differs from exact assignment" unless task["task_id"].to_s == expected_dispatch_id
      errors << "dispatch task role must be department_worker" unless task["role"].to_s == "department_worker"
      errors << "dispatch scope must remain in existing front_planning_integration" unless exact_scope["stage_id"].to_s == "front_planning_integration"
      errors << "dispatch scope must own the exact analysis artifact only" unless Array(exact_scope["artifact_paths"]).map(&:to_s) == [expected_analysis_relative]
      errors << "dispatch scope must own the exact analysis section" unless exact_scope["mode"].to_s == "section" && Array(exact_scope["section_ids"]).map(&:to_s) == [document["section_id"].to_s]
      selected_profile = dispatch_document.dig("launch", "compiled_launch_prompt", "selected_profile").to_h
      errors << "dispatch must load reference_research_generalist.reference_story_sequence_role" unless selected_profile["profile_id"].to_s == "reference_research_generalist" && selected_profile["checkpoint_id"].to_s == "reference_story_sequence_role"
      routing = dispatch_document["routing_identity"].to_h
      unless routing["logical_role"].to_s == "worker" && routing["worker_specialty"].to_s == "reference_story_sequence" && routing["logical_profile_alias"].to_s == "worker_high" && routing["return_recipient_role"].to_s == "creative_development_director"
        errors << "dispatch routing must be bounded reference_story_sequence worker_high returning to CDD"
      end
      unless %w[internal_parent_work_package physical_native_session].include?(routing["session_topology"].to_s)
        errors << "dispatch must select exactly one legal worker topology"
      end
      recipient = dispatch_document.dig("launch", "recipient").to_h
      errors << "dispatch return recipient must be creative_development_director" unless recipient["role"].to_s == "creative_development_director"
      source_pairs = Array(dispatch_document.dig("launch", "sources")).map { |row| [row["path"].to_s, row["sha256"].to_s] }.sort
      source_unit_ids = candidate_rows.flat_map { |row| Array(row["typed_sequence_unit_ids"]).map(&:to_s) }.uniq
      manifest_pairs = source_unit_ids.each_with_object([]) do |unit_id, pairs|
        unit_row = Array(front.dig("reference_connection_research", "reference_units")).find do |row|
          row.dig("sequence_unit", "sequence_unit_id").to_s == unit_id
        end
        next unless unit_row
        manifest = unit_row.dig("sequence_unit", "manifest").to_h
        pairs << [manifest["path"].to_s, manifest["sha256"].to_s]
      end
      expected_source_pairs = (manifest_pairs + [[audio_ref["path"].to_s, audio_ref["sha256"].to_s]]).uniq.sort
      errors << "dispatch source set must exact-cover the candidate Sequence Unit manifests plus audio motion map, without hashing the self-referential final FP file" unless source_pairs == expected_source_pairs
      objective = task["objective"].to_s
      errors << "dispatch objective must bind the exact candidate snapshot SHA" unless objective.include?(source_front["candidate_snapshot_sha256"].to_s)
      storyline_value_sha = document.dig("analysis_scope", "active_storyline_passage_binding", "source_value_sha256").to_s
      errors << "dispatch objective must bind the exact active-storyline passage value SHA" unless objective.include?(storyline_value_sha)
      Array(document.dig("analysis_scope", "candidate_ids")).each do |candidate_id|
        errors << "dispatch objective must name every bounded candidate id" unless objective.include?(candidate_id.to_s)
      end
      rendered_prompt = dispatch_document.dig("launch", "compiled_launch_prompt", "rendered_prompt").to_s
      rendered_prompt_sha = dispatch_document.dig("launch", "compiled_launch_prompt", "rendered_prompt_sha256").to_s
      errors << "dispatch rendered prompt SHA-256 is stale" unless rendered_prompt_sha == Digest::SHA256.hexdigest(rendered_prompt)
      errors << "native Goal must stay concise and separate from the full rendered worker prompt" if rendered_prompt == objective
      goal_contract = dispatch_document.dig("launch", "goal_contract").to_h
      unless goal_contract["goal_text"].to_s == objective && goal_contract["goal_text_sha256"].to_s == Digest::SHA256.hexdigest(objective)
        errors << "native Goal must exact-bind only the concise task objective"
      end
      if front && major
        expected_context_json = JSON.pretty_generate(canonical_value(stable_prompt_context(front, major)))
        expected_context_block = [SEQUENCE_PROMPT_CONTEXT_BEGIN, expected_context_json, SEQUENCE_PROMPT_CONTEXT_END].join("\n")
        errors << "dispatch rendered prompt must carry the exact active storyline, Major semantic job, and complete candidate values once" unless rendered_prompt.scan(expected_context_block).length == 1
      end
      SEQUENCE_PROMPT_CLAUSES.each do |clause|
        errors << "dispatch rendered prompt must carry exact Sequence clause: #{clause}" unless rendered_prompt.scan(clause).length == 1
      end
      bounded_output = dispatch_document.dig("launch", "bounded_output").to_h
      acceptance_text = Array(bounded_output["anti_flat_evidence_requirements"]).join(" ").downcase
      %w[body gaze head camera translation rotation lens angle composition depth occlusion reveal start landing identity hair styling clothing silhouette].each do |term|
        errors << "dispatch bounded-output acceptance must carry Sequence joint-reading term #{term}" unless acceptance_text.include?(term)
      end
      unless acceptance_text.include?("exact analysis path") && acceptance_text.include?("sha") && acceptance_text.include?("candidate result evidence") && acceptance_text.include?("independent cdd review")
        errors << "dispatch bounded-output acceptance must require exact return evidence for independent CDD review"
      end
      unless acceptance_text.include?("observed interframe evidence") && acceptance_text.include?("contextual rather than defaults") && acceptance_text.include?("ambiguity remains inference or hold")
        errors << "dispatch bounded-output acceptance must forbid a default orbit or other unevidenced motion family"
      end

      sequence_requirement_categories = {
        "FOUNDER-SEQUENCE-CONTEXT" => "founder",
        "POLICY-SEQUENCE-MOTION-EVIDENCE" => "policy",
        "QUALITY-SEQUENCE-MOTION-ACCEPTANCE" => "quality"
      }
      requirement_rows = Array(dispatch_document.dig("launch", "requirement_manifest"))
      sequence_requirement_categories.each do |requirement_id, category|
        row = requirement_rows.find { |candidate| candidate.to_h["requirement_id"].to_s == requirement_id }
        if row.nil?
          errors << "dispatch requirement_manifest is missing #{requirement_id}"
          next
        end
        unless row["category"].to_s == category && row["required"] == true && row["director_semantic_review_required"] == true
          errors << "dispatch requirement #{requirement_id} must be required #{category} evidence with independent Director semantic review"
        end
        errors << "dispatch requirement #{requirement_id} must target the exact analysis output" unless row["expected_output_target"].to_s == expected_analysis_relative
      end
      founder_requirement = requirement_rows.find { |row| row.to_h["requirement_id"].to_s == "FOUNDER-SEQUENCE-CONTEXT" }.to_h
      errors << "FOUNDER-SEQUENCE-CONTEXT must bind the exact rendered current-values prompt without a self-referential FP file" unless founder_requirement["source_locator"].to_s == "/launch/compiled_launch_prompt/rendered_prompt" && founder_requirement["source_binding"].nil? && founder_requirement["affected_scope"].to_s.include?(SEQUENCE_PROMPT_CONTEXT_BEGIN.sub("_BEGIN", ""))
      quality_requirement = requirement_rows.find { |row| row.to_h["requirement_id"].to_s == "QUALITY-SEQUENCE-MOTION-ACCEPTANCE" }.to_h
      unless quality_requirement["source_locator"].to_s == "/launch/compiled_launch_prompt/rendered_prompt" && quality_requirement["source_binding"].nil?
        errors << "QUALITY-SEQUENCE-MOTION-ACCEPTANCE must bind the exact rendered worker prompt"
      end
      SEQUENCE_PROMPT_CLAUSES.each do |clause|
        errors << "QUALITY-SEQUENCE-MOTION-ACCEPTANCE must independently carry exact clause: #{clause}" unless quality_requirement["affected_scope"].to_s.scan(clause).length == 1
      end
      policy_requirement = requirement_rows.find { |row| row.to_h["requirement_id"].to_s == "POLICY-SEQUENCE-MOTION-EVIDENCE" }.to_h
      policy_source = policy_requirement["source_binding"].to_h
      policy_path = root.join("policies", "harness-routing-and-sources.md").expand_path.cleanpath
      policy_binding_valid = policy_source["path"].to_s == "policies/harness-routing-and-sources.md" &&
        inside?(policy_path, root) && policy_path.file? && !policy_path.symlink? &&
        policy_source["sha256"].to_s == Digest::SHA256.file(policy_path).hexdigest
      errors << "POLICY-SEQUENCE-MOTION-EVIDENCE must exact hash-bind the current governing graph-engineering routing policy bytes" unless policy_binding_valid

      unless options[:pre_cdd_copy]
        result_rows = Array(dispatch_document.dig("director_review", "requirement_results"))
        sequence_requirement_categories.each_key do |requirement_id|
          result = result_rows.find { |candidate| candidate.to_h["requirement_id"].to_s == requirement_id }
          if result.nil?
            errors << "independent CDD requirement_results is missing #{requirement_id}"
          elsif result["result"].to_s != "pass"
            errors << "independent CDD requirement_results must PASS #{requirement_id}"
          end
        end
      end

      field_expectations = {
        "task_binding" => "/launch/task",
        "exact_scope_binding" => "/launch/task/exact_scope",
        "goal_contract_binding" => "/launch/goal_contract",
        "source_set_binding" => "/launch/sources",
        "bounded_output_binding" => "/launch/bounded_output",
        "recipient_binding" => "/launch/recipient",
        "selected_profile_binding" => "/launch/compiled_launch_prompt/selected_profile",
        "rendered_prompt_binding" => "/launch/compiled_launch_prompt/rendered_prompt",
        "routing_identity_binding" => "/routing_identity"
      }
      field_expectations.each do |name, pointer|
        validate_value_binding(dispatch_binding[name], dispatch_document, pointer, "dispatch_and_authorship.dispatch_contract.#{name}", errors)
      end

      goal_binding = dispatch["native_goal"].to_h
      errors << "native Goal must bind the same Department Dispatch path" unless goal_binding["path"].to_s == dispatch_binding["path"].to_s
      {
        "provider_binding" => "/runtime_return/runtime_goal/provider",
        "native_goal_id_binding" => "/runtime_return/runtime_goal/native_goal_id",
        "opened_at_binding" => "/runtime_return/runtime_goal/opened_at",
        "goal_text_sha256_binding" => "/runtime_return/runtime_goal/goal_text_sha256"
      }.each do |name, pointer|
        validate_value_binding(goal_binding[name], dispatch_document, pointer, "dispatch_and_authorship.native_goal.#{name}", errors)
      end
      errors << "native Goal text hash must exact-copy launch.goal_contract" unless dispatch_document.dig("runtime_return", "runtime_goal", "goal_text_sha256").to_s == dispatch_document.dig("launch", "goal_contract", "goal_text_sha256").to_s
      artifact_sha = Digest::SHA256.file(artifact).hexdigest
      if options[:pre_cdd_copy]
        runtime_return = dispatch_document["runtime_return"].to_h
        errors << "pre-Cdd-copy transport admission requires DDC lifecycle returned" unless dispatch_document.dig("lifecycle", "current_state").to_s == "returned"
        errors << "pre-Cdd-copy transport admission cannot contain a Director review" unless dispatch_document["director_review"].nil?
        errors << "pre-Cdd-copy transport admission cannot contain a promotion or HOLD disposition" unless dispatch_document["promotion"].nil?
        errors << "pre-Cdd-copy transport admission requires no runtime hold or rejection" unless Array(runtime_return["hold_reasons"]).empty? && runtime_return.dig("wake_event", "event_kind").to_s == "final"
        expected_output_pair = [[expected_analysis_relative, artifact_sha]]
        output_pairs = Array(runtime_return["outputs"]).map { |row| [row.to_h["path"].to_s, row.to_h["sha256"].to_s] }
        errors << "returned DDC output must bind the exact deterministic target path and authored SHA" unless output_pairs == expected_output_pair
        wake_pairs = Array(runtime_return.dig("wake_event", "output_pointers")).map { |row| [row.to_h["path"].to_s, row.to_h["sha256"].to_s] }
        errors << "returned DDC wake output must exact-copy the deterministic target path and authored SHA" unless wake_pairs == expected_output_pair
        expected_paths = Array(dispatch_document.dig("launch", "bounded_output", "expected_paths")).map(&:to_s)
        errors << "returned DDC bounded output must name only the deterministic target path" unless expected_paths == [expected_analysis_relative]
        evidence_pairs = Array(runtime_return["worker_fulfillment_claims"]).flat_map do |claim|
          Array(claim.to_h["output_evidence"]).map { |row| [row.to_h["path"].to_s, row.to_h["sha256"].to_s] }
        end
        errors << "returned DDC applied evidence must bind only the deterministic target bytes" unless evidence_pairs.any? && (evidence_pairs - expected_output_pair).empty?
        expected_ddc_input = value_sha256(
          "lineage" => dispatch_document["lineage"],
          "review_submission" => dispatch_document["review_submission"],
          "launch" => dispatch_document["launch"]
        )
        errors << "returned DDC input digest is stale" unless runtime_return.dig("input_digest", "basis").to_s == "lineage_review_submission_and_goal_first_launch_contract_canonical_json_v4" && runtime_return.dig("input_digest", "sha256").to_s == expected_ddc_input
        mechanical = runtime_return["mechanical_compliance_receipt"].to_h
        errors << "returned DDC mechanical receipt digest is stale" unless mechanical["receipt_sha256"].to_s == value_sha256(mechanical.reject { |key, _value| key.to_s == "receipt_sha256" })
        completion_basis = {
          "mechanical_compliance_receipt_sha256" => mechanical["receipt_sha256"],
          "worker_fulfillment_claims" => runtime_return["worker_fulfillment_claims"],
          "outputs" => runtime_return["outputs"],
          "hold_reasons" => runtime_return["hold_reasons"]
        }
        errors << "returned native Goal completion evidence is stale" unless runtime_return.dig("runtime_goal", "completion_evidence_sha256").to_s == value_sha256(completion_basis)
        result_basis = %w[
          work_started_at runtime_owner runtime_goal skill_revisions
          mechanical_compliance_receipt worker_fulfillment_claims output_inventory
          outputs hold_reasons wake_event
        ].to_h { |key| [key, runtime_return[key]] }
        errors << "returned DDC result digest is stale" unless runtime_return.dig("result_digest", "basis").to_s == "runtime_goal_reads_compliance_claims_outputs_holds_and_wake_event_canonical_json_v4" && runtime_return.dig("result_digest", "sha256").to_s == value_sha256(result_basis)
      elsif !final_dispatch_reviewed_output?(dispatch_document, expected_analysis_relative, artifact_sha)
        errors << "independent final CDD Department Dispatch review must accept and promote this exact analysis path/SHA"
      end
    rescue JSON::ParserError, Psych::Exception, TypeError, KeyError, IndexError => error
      errors << "dispatch_and_authorship binding is stale: #{error.message}"
    end
  end
  expected_scope_key = "sequence_motion:#{document['content_id']}:#{document['section_id']}:#{document['major_scene_id']}"
  errors << "dispatch scope_key must identify the exact content/section/Major group" unless dispatch["scope_key"].to_s == expected_scope_key
  discover_active_sequence_dispatch_conflicts(
    run_root.join("work", "department-dispatches"),
    dispatch_path,
    run_relative,
    relative_repo_path(deterministic_artifact.dirname, root),
    document["major_scene_id"],
    root,
    errors
  )
  if dispatch["review_backpressure"].to_s != "capacity_available" && document["status"].to_s != "hold"
    errors << "CDD review or upstream backpressure requires analysis status HOLD"
  end
  expected_input_digest = value_sha256(
    {
      "candidate_snapshot_sha256" => document.dig("source_front_planning", "candidate_snapshot_sha256"),
      "source_audio_motion_map_sha256" => document.dig("source_audio_motion_map", "sha256"),
      "analysis_scope" => document["analysis_scope"],
      "dispatch_contract_stable_binding_sha256" => value_sha256(dispatch["dispatch_contract"]),
      "native_goal_stable_binding_sha256" => value_sha256(dispatch["native_goal"])
    }
  )
  errors << "dispatch input_digest_sha256 is stale" unless dispatch["input_digest_sha256"].to_s == expected_input_digest
  expected_result_sha = value_sha256(
    {
      "candidate_analyses" => document["candidate_analyses"],
      "comparative_recommendation" => document["comparative_recommendation"]
    }
  )
  errors << "dispatch result_sha256 is stale" unless dispatch["result_sha256"].to_s == expected_result_sha

end

errors = errors.uniq
errors = errors.first(options[:max_errors]) if options[:max_errors].to_i.positive?
result = {
  "valid" => errors.empty?,
  "validation_mode" => options[:pre_cdd_copy] ? "pre_cdd_copy_transport_admission_only" : "strict_independent_cdd_reviewed",
  "downstream_authority" => options[:pre_cdd_copy] ? "none_copied_pending_cdd_review" : "eligible_only_when_all_strict_checks_pass",
  "schema_version" => document["schema_version"],
  "analysis_id" => document["analysis_id"],
  "scope_key" => document.dig("dispatch_and_authorship", "scope_key"),
  "candidate_snapshot_sha256" => document.dig("source_front_planning", "candidate_snapshot_sha256"),
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: Sequence Motion Analysis v1 preserves observed/inferred separation, exact candidate reachability, one-second Sequence Units, advisory 01 adoption, and 03V temporal-camera authority"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
