# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "idol_run_layout"

module Idol03VSourceDiscovery
  READY_VIDEO_PROMPT_STATUSES = %w[
    not_requested
    ready_for_codex_authoring
    ready_for_grok
    ready_for_optional_grok_execution
    codex_authoring
    codex_drafted
    ready_for_founder_review
    grok_running
    ready_for_codex_intake
    complete
  ].freeze

  Result = Struct.new(
    :document,
    :selected_paths,
    :review,
    :eligible_records,
    keyword_init: true
  )

  ReadyLineage = Struct.new(
    :errors,
    :review,
    :eligible_records,
    :prompt_packets,
    :joined_cues,
    :bound_paths,
    :bound_source_refs,
    keyword_init: true
  )

  module_function

  def scan(run_path:, repo_root:, generated_at: Time.now.utc.iso8601)
    run_path = Pathname.new(run_path).expand_path.cleanpath
    repo_root = Pathname.new(repo_root).expand_path.cleanpath
    raise ArgumentError, "run_path must stay inside repo_root" unless inside_root?(run_path, repo_root)
    layout_errors = IdolRunLayout.validate(run_path, repo_root: repo_root)
    raise ArgumentError, layout_errors.join("; ") unless layout_errors.empty?
    run_identity = IdolRunLayout.identity(run_path, repo_root: repo_root)
    review_path = run_path.join("03-production-cut-review.yaml")
    review = load_yaml_hash(review_path)
    founder_pass_records = founder_pass_review_records(review)
    eligible_records = eligible_review_records(review)

    selected = discover_latest_sources(run_path)
    selected["production_cut_review"] = review_path if review_path.file?
    selected["song_lock"] = run_path.join("00A-song-lock.yaml") if run_path.join("00A-song-lock.yaml").file?
    selected["song_choreography_performance_mv_map"] = run_path.join("01-song-choreography-performance-mv-map.yaml") if run_path.join("01-song-choreography-performance-mv-map.yaml").file?
    selected["master_storyboard"] ||= resolved_review_source(review, "source_02a", run_path, repo_root, "02A-master-storyboard.yaml")
    selected["prompt_packets"] ||= resolved_review_source(review, "source_02b", run_path, repo_root, "02B-prompt-packets.yaml")

    placement = load_yaml_hash(selected["audio_branch_cut_placement"])
    {
      "source_audio" => placement["source_audio"],
      "audio_motion_director_map" => placement["source_audio_motion_map"]
    }.each do |role, ref|
      next unless ref.is_a?(Hash)

      path = resolve_repo_path(ref["path"], repo_root)
      selected[role] = path if path&.file?
    end

    add_front_planning_pointer_sources!(selected, repo_root)

    timing_role = "audio_motion_director_map" if selected["audio_motion_director_map"]&.file?
    selected_audio_timing_detected = !timing_role.nil?
    production_cut_pass_detected = !founder_pass_records.empty?
    # IDOL 03V is song-led; CF/ad work is isolated under cf/. Once a typed
    # Production Cut is passed, missing timing evidence must hold authoring
    # rather than making the timing gate disappear.
    gate_applies = production_cut_pass_detected

    source_rows = []
    selected.each do |role, path|
      next unless path&.file?

      source_rows << source_row(role, path, repo_root, required_for_gate: required_role?(role, gate_applies))
    end

    founder_pass_records.each_with_index do |record, index|
      path = resolve_repo_path(record["path"], repo_root)
      next unless path&.file? && inside_root?(path, run_path)

      source_rows << source_row(
        format("passed_production_cut_image_%03d", index + 1),
        path,
        repo_root,
        required_for_gate: production_cut_pass_detected
      )
    end

    source_rows.sort_by! { |row| [row.fetch("role"), row.fetch("path")] }
    source_rows.each_with_index do |row, index|
      row["source_id"] = format("SRC_%03d_%s", index + 1, row.fetch("role").upcase.gsub(/[^A-Z0-9]+/, "_"))
    end

    required_roles = gate_required_roles(production_cut_pass_detected)

    present_roles = source_rows.map { |row| row.fetch("role") }
    missing_required = required_roles.reject do |role|
      if role == "passed_production_cut_image"
        present_roles.any? { |candidate| candidate.start_with?("passed_production_cut_image_") }
      else
        present_roles.include?(role)
      end
    end
    passed_image_count = source_rows.count { |row| row.fetch("role").start_with?("passed_production_cut_image_") }
    if production_cut_pass_detected && passed_image_count != founder_pass_records.length
      missing_required << "passed_production_cut_image"
    end
    missing_required.uniq!
    optional_roles = discoverable_roles - required_roles
    missing_optional = optional_roles.reject { |role| present_roles.include?(role) }

    source_set_sha256 = canonical_source_set_digest(source_rows)
    run_rel = relative_path(run_path, repo_root)
    document = {
      "schema_version" => "idol_03v_source_snapshot.v3",
      "content_id" => run_identity.fetch("content_id"),
      "run" => run_rel,
      "status" => missing_required.empty? ? "current" : "hold_missing_required_sources",
      "generated_at" => generated_at,
      "discovery_contract" => {
        "mode" => "single_run_source_scan",
        "selection_rule" => "latest_numeric_version_per_role",
        "reuse_rule" => "reuse_until_source_set_digest_changes"
      },
      "gate_detection" => {
        "production_cut_pass_detected" => production_cut_pass_detected,
        "selected_audio_timing_detected" => selected_audio_timing_detected,
        "song_led_timing_gate_applies" => gate_applies,
        "eligible_cue_count" => eligible_records.length,
        "founder_pass_count" => founder_pass_records.length,
        "timing_source_role" => timing_role
      },
      "sources" => source_rows,
      "missing_required_roles" => missing_required.sort,
      "missing_optional_roles" => missing_optional.sort,
      "source_set_sha256" => source_set_sha256,
      "automation_boundaries" => {
        "derived_context_only" => true,
        "creative_lock_created" => false,
        "founder_pass_inferred" => false,
        "paid_generation_approved" => false,
        "playback_pass_implied" => false,
        "external_execution_approved" => false
      }
    }

    Result.new(
      document: document,
      selected_paths: selected,
      review: review,
      eligible_records: eligible_records
    )
  end

  def validate_snapshot(document, repo_root:, run_root: nil)
    errors = []
    unless document.is_a?(Hash)
      return ["source snapshot must be a mapping"]
    end

    errors << "schema_version must be idol_03v_source_snapshot.v3" unless document["schema_version"] == "idol_03v_source_snapshot.v3"
    snapshot_run = resolve_repo_path(document["run"], repo_root)
    layout_errors = snapshot_run ? IdolRunLayout.validate(snapshot_run, repo_root: repo_root) : ["snapshot run is missing"]
    unless snapshot_run&.directory? && layout_errors.empty?
      errors << "snapshot run must be a readable runs/ALBUM_KEY/TITLE_KEY/RUN_ID directory with a valid run manifest"
      errors.concat(layout_errors)
      snapshot_run = nil
    end
    if snapshot_run
      identity = IdolRunLayout.identity(snapshot_run, repo_root: repo_root)
      errors << "snapshot content_id must match its run identity" unless document["content_id"].to_s == identity.fetch("content_id").to_s
    end
    if run_root && (!snapshot_run || !inside_root?(snapshot_run, run_root) || snapshot_run.realpath != Pathname.new(run_root).realpath)
      errors << "snapshot run does not match the owning manifest run"
    end
    rows = Array(document["sources"])
    errors << "sources must contain at least one readable source" if rows.empty?
    source_ids = rows.each_with_object([]) { |row, values| values << row["source_id"] if row.is_a?(Hash) }
    errors << "source_id values must be unique" unless source_ids.uniq.length == source_ids.length

    rows.each do |row|
      next unless row.is_a?(Hash)

      path = resolve_repo_path(row["path"], repo_root)
      if path.nil? || !path.file?
        errors << "snapshot source is not readable: #{row['path']}"
        next
      end
      if snapshot_run
        source_rel = relative_path(path, repo_root)
        if row["required_for_gate"] == true && !inside_root?(path, snapshot_run)
          errors << "required snapshot source is outside the owning run: #{row['path']}"
        elsif source_rel.start_with?("runs/") && !inside_root?(path, snapshot_run)
          errors << "snapshot source points into a different run: #{row['path']}"
        end
      end
      actual = Digest::SHA256.file(path.to_s).hexdigest
      errors << "snapshot source hash mismatch: #{row['path']}" unless actual == row["sha256"]
    end

    expected_digest = canonical_source_set_digest(rows)
    errors << "source_set_sha256 does not match canonical source rows" unless expected_digest == document["source_set_sha256"]

    missing = Array(document["missing_required_roles"])
    if document["status"] == "current" && !missing.empty?
      errors << "current snapshot cannot have missing_required_roles"
    elsif document["status"] == "hold_missing_required_sources" && missing.empty?
      errors << "hold snapshot must name missing_required_roles"
    end
    gate = document["gate_detection"].is_a?(Hash) ? document["gate_detection"] : {}
    review_row = rows.find { |row| row.is_a?(Hash) && row["role"] == "production_cut_review" }
    review_path = review_row ? resolve_repo_path(review_row["path"], repo_root) : nil
    review = review_path&.file? ? load_yaml_hash(review_path) : {}
    founder_pass_count = if review.empty?
                           rows.count { |row| row.is_a?(Hash) && row["role"].to_s.start_with?("passed_production_cut_image_") }
                         else
                           founder_pass_review_records(review).length
                         end
    generated_pass = founder_pass_count.positive?
    errors << "gate_detection.production_cut_pass_detected does not match snapshot rows" unless gate["production_cut_pass_detected"] == generated_pass
    errors << "song_led_timing_gate_applies must equal typed Production Cut pass detection in IDOL" unless gate["song_led_timing_gate_applies"] == generated_pass
    if gate.key?("founder_pass_count") && gate["founder_pass_count"].to_i != founder_pass_count
      errors << "gate_detection.founder_pass_count does not match passed_production_cut_image rows"
    end
    present_roles = rows.each_with_object([]) do |row, roles|
      roles << row["role"].to_s if row.is_a?(Hash)
    end
    passed_image_row_count = present_roles.count { |role| role.start_with?("passed_production_cut_image_") }
    expected_missing = gate_required_roles(generated_pass).reject do |role|
      if role == "passed_production_cut_image"
        present_roles.any? { |candidate| candidate.start_with?("passed_production_cut_image_") }
      else
        present_roles.include?(role)
      end
    end.sort
    if generated_pass && passed_image_row_count != founder_pass_count
      expected_missing << "passed_production_cut_image"
      expected_missing.uniq!
      expected_missing.sort!
    end
    unless missing.map(&:to_s).sort == expected_missing
      errors << "missing_required_roles must exactly match required roles absent from sources: expected #{expected_missing.inspect}"
    end
    rows.each do |row|
      next unless row.is_a?(Hash)

      role = row["role"].to_s
      expected_required = required_role?(role, generated_pass)
      unless row["required_for_gate"] == expected_required
        errors << "snapshot source required_for_gate mismatch for #{role}: expected #{expected_required}"
      end
    end
    expected_status = expected_missing.empty? ? "current" : "hold_missing_required_sources"
    errors << "snapshot status must be #{expected_status} for recomputed required roles" unless document["status"] == expected_status
    timing_present = rows.any? do |row|
      row.is_a?(Hash) && row["role"] == "audio_motion_director_map"
    end
    errors << "gate_detection.selected_audio_timing_detected does not match snapshot timing rows" unless gate["selected_audio_timing_detected"] == timing_present
    if generated_pass && !timing_present && !missing.include?("audio_motion_director_map")
      errors << "missing timing evidence must name audio_motion_director_map"
    end
    if snapshot_run
      if review_path&.file?
        founder_pass_records = founder_pass_review_records(review)
        expected_passed = founder_pass_records.each_with_object([]) do |record, values|
          image_path = resolve_repo_path(record["path"], repo_root)
          values << image_path.realpath.to_s if image_path&.file? && inside_root?(image_path, snapshot_run)
        end.sort
        snapshot_passed = rows.each_with_object([]) do |row, values|
          next unless row.is_a?(Hash) && row["role"].to_s.start_with?("passed_production_cut_image_")
          image_path = resolve_repo_path(row["path"], repo_root)
          values << image_path.realpath.to_s if image_path&.file?
        end.sort
        errors << "passed_production_cut_image rows must exactly match typed Production Cut review images" unless snapshot_passed == expected_passed
        if gate.key?("eligible_cue_count") && gate["eligible_cue_count"].to_i != eligible_review_records(review).length
          errors << "gate_detection.eligible_cue_count does not match authoring-eligible Founder-pass review rows"
        end
      else
        errors << "snapshot production_cut_review is not readable for Production Cut reconciliation"
      end
    end
    errors
  end

  def source_refs(document)
    Array(document["sources"]).each_with_object({}) do |row, refs|
      next unless row.is_a?(Hash)

      refs[row.fetch("role")] = row.fetch("source_id")
    end
  end

  def selected_audio_timing_evidence?(path)
    text = Pathname.new(path).read
    text.match?(/\b(?:start_seconds|end_seconds|time_range|section_timing|timeline)\b/i) ||
      text.match?(/\b\d{1,2}:\d{2}(?:\.\d+)?\b/) ||
      text.match?(/\b\d+(?:\.\d+)?\s*(?:-|–|to)\s*\d+(?:\.\d+)?\s*(?:s|sec|seconds?)?\b/i)
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  def source_by_role(document, role)
    Array(document["sources"]).find { |row| row.is_a?(Hash) && row["role"] == role }
  end

  # Reconciles the source-discovery read model with the validated typed
  # Production Cut review and Audio Production-Cut Placement. Official Cores
  # join 01/02A pixel authority without inventing a Branch packet; Branches also
  # join their exact approved 02B packet.
  def reconcile_ready_authoring_lineage(snapshot:, placement:, placement_path:, repo_root:, run_path:)
    repo_root = Pathname.new(repo_root).expand_path.cleanpath
    run_path = Pathname.new(run_path).expand_path.cleanpath
    placement_path = Pathname.new(placement_path)
    placement_path = repo_root.join(placement_path) unless placement_path.absolute?
    placement_path = placement_path.expand_path.cleanpath
    errors = []
    bound_paths = {}
    bound_source_refs = {}

    unless placement.is_a?(Hash) && placement["schema_version"].to_s == "idol_audio_production_cut_placement.v5"
      errors << "ready authoring lineage requires idol_audio_production_cut_placement.v5"
    end
    unless %w[ready_for_03v passed].include?(placement.is_a?(Hash) ? placement["status"].to_s : "")
      errors << "ready authoring lineage requires a ready_for_03v or passed placement"
    end
    unless inside_root?(placement_path, run_path) && placement_path.file?
      errors << "Audio Production-Cut Placement path must be a readable file inside the owning run"
    end

    bound_records = {
      "production_cut_review" => placement.is_a?(Hash) ? placement["source_production_cut_review"] : nil,
      "song_choreography_performance_mv_map" => placement.is_a?(Hash) ? placement["source_01_direction"] : nil,
      "master_storyboard" => placement.is_a?(Hash) ? placement["source_02a"] : nil,
      "prompt_packets" => placement.is_a?(Hash) ? placement["source_02b"] : nil,
      "source_audio" => placement.is_a?(Hash) ? placement["source_audio"] : nil,
      "audio_motion_director_map" => placement.is_a?(Hash) ? placement["source_audio_motion_map"] : nil
    }

    bound_records.each do |role, record|
      label = "placement #{role}"
      unless record.is_a?(Hash)
        errors << "#{label} must be a path/sha256 mapping"
        next
      end

      path = resolve_repo_path(record["path"], repo_root)
      unless path&.file? && inside_root?(path, run_path)
        errors << "#{label} must resolve to a readable file inside the owning run: #{record['path']}"
        next
      end
      actual_sha = Digest::SHA256.file(path.to_s).hexdigest
      unless record["sha256"].to_s == actual_sha
        errors << "#{label} sha256 does not match #{record['path']}"
        next
      end
      bound_paths[role] = path

      rows = Array(snapshot.is_a?(Hash) ? snapshot["sources"] : nil).select do |row|
        row.is_a?(Hash) && row["role"].to_s == role
      end
      if rows.length != 1
        errors << "source snapshot must contain exactly one #{role} row bound to placement; found #{rows.length}"
        next
      end
      snapshot_row = rows.first
      snapshot_path = resolve_repo_path(snapshot_row["path"], repo_root)
      unless snapshot_path&.file? && same_realpath?(snapshot_path, path) && snapshot_row["sha256"].to_s == actual_sha
        errors << "source snapshot #{role} path/sha256 does not match the placement-bound source"
        next
      end
      source_id = snapshot_row["source_id"].to_s
      if source_id.empty?
        errors << "source snapshot #{role} row requires a source_id"
      else
        bound_source_refs[role] = source_id
      end
    end

    placement_rows = Array(snapshot.is_a?(Hash) ? snapshot["sources"] : nil).select do |row|
      row.is_a?(Hash) && row["role"].to_s == "audio_branch_cut_placement"
    end
    if placement_rows.length != 1
      errors << "source snapshot must contain exactly one audio_branch_cut_placement row; found #{placement_rows.length}"
    elsif placement_path.file?
      row = placement_rows.first
      row_path = resolve_repo_path(row["path"], repo_root)
      placement_sha = Digest::SHA256.file(placement_path.to_s).hexdigest
      unless row_path&.file? && same_realpath?(row_path, placement_path) && row["sha256"].to_s == placement_sha
        errors << "source snapshot audio_branch_cut_placement row does not match the validated placement"
      else
        source_id = row["source_id"].to_s
        if source_id.empty?
          errors << "source snapshot audio_branch_cut_placement row requires a source_id"
        else
          bound_source_refs["audio_branch_cut_placement"] = source_id
        end
      end
    end

    review = load_yaml_hash(bound_paths["production_cut_review"])
    prompt_packets = load_yaml_hash(bound_paths["prompt_packets"])
    errors << "placement-bound typed Production Cut review must be a readable mapping" if review.empty?
    errors << "placement-bound 02B prompt packets must be a readable mapping" if prompt_packets.empty?
    if !review.empty? && review["content_id"].to_s != run_path.basename.to_s
      errors << "placement-bound typed Production Cut review content_id does not match the owning run"
    end
    if !prompt_packets.empty? && prompt_packets["content_id"].to_s != run_path.basename.to_s
      errors << "placement-bound 02B prompt packets content_id does not match the owning run"
    end

    founder_pass_records = founder_pass_review_records(review)
    eligible_records = eligible_review_records(review)
    errors << "placement-bound typed Production Cut review has no eligible passed cuts" if eligible_records.empty?

    production_units = Array(placement.is_a?(Hash) ? placement["production_cut_units"] : nil).select { |row| row.is_a?(Hash) }
    errors << "ready placement must contain production_cut_units" if production_units.empty?
    packets = Array(prompt_packets["prompt_packets"]).select { |row| row.is_a?(Hash) }
    packet_groups = packets.group_by { |row| row["packet_id"].to_s }
    duplicate_packet_ids = packet_groups.select { |packet_id, rows| !packet_id.empty? && rows.length > 1 }.keys.sort
    unless duplicate_packet_ids.empty?
      errors << "placement-bound 02B prompt packets contain duplicate packet_id values: #{duplicate_packet_ids.join(', ')}"
    end

    joined_cues = []
    matched_unit_counts = Hash.new(0)
    eligible_records.each_with_index do |record, index|
      label = "eligible Production Cut cue #{index + 1}"
      packet_id = record["packet_id"].to_s
      production_cut_id = record["production_cut_id"].to_s
      production_cut_type = record["production_cut_type"].to_s
      parent_core_cut_id = record["parent_core_cut_id"].to_s
      review_image_path = resolve_repo_path(record["path"], repo_root)
      if production_cut_id.empty? || !%w[official_core branch].include?(production_cut_type) || parent_core_cut_id.empty?
        errors << "#{label} requires exact Production Cut type, id, and parent Core"
        next
      end
      unless review_image_path&.file? && inside_root?(review_image_path, run_path)
        errors << "#{label} review image is not readable inside the owning run"
        next
      end

      unit_matches = production_units.each_with_index.each_with_object([]) do |(unit, unit_index), values|
        unit_image_path = resolve_repo_path(unit.dig("passed_source_image", "path"), repo_root)
        next unless unit["production_cut_id"].to_s == production_cut_id
        next unless unit["production_cut_type"].to_s == production_cut_type
        next unless unit["parent_core_cut_id"].to_s == parent_core_cut_id
        next unless unit_image_path&.file? && same_realpath?(unit_image_path, review_image_path)

        values << [unit_index, unit]
      end
      if unit_matches.length != 1
        errors << "#{label} must join exactly one placement unit by type/id/parent Core/review image; found #{unit_matches.length}"
        next
      end

      unit_index, production_unit = unit_matches.first
      image_sha = Digest::SHA256.file(review_image_path.to_s).hexdigest
      unless production_unit.dig("passed_source_image", "sha256").to_s == image_sha && record["sha256"].to_s == image_sha
        errors << "#{label} placement passed_source_image SHA-256 does not match typed review pixels"
      end
      matched_unit_counts[unit_index] += 1

      packet = nil
      if production_cut_type == "branch"
        packet_matches = packet_groups.fetch(packet_id, [])
        if packet_matches.length != 1
          errors << "#{label} Branch must join exactly one packet in placement-bound 02B; found #{packet_matches.length}"
          next
        end
        packet = packet_matches.first
        unless packet["core_cut_id"].to_s == parent_core_cut_id &&
               packet["branch_cut_id"].to_s == production_cut_id &&
               production_unit["packet_id"].to_s == packet_id
          errors << "#{label} typed review, placement, and 02B Branch identities do not match"
          next
        end
      elsif !record["packet_id"].nil? || !production_unit["packet_id"].nil?
        errors << "#{label} Official Core must not invent a Branch packet"
        next
      end

      passed_rows = Array(snapshot.is_a?(Hash) ? snapshot["sources"] : nil).select do |row|
        next false unless row.is_a?(Hash) && row["role"].to_s.start_with?("passed_production_cut_image_")

        row_path = resolve_repo_path(row["path"], repo_root)
        row_path&.file? && same_realpath?(row_path, review_image_path) && row["sha256"].to_s == image_sha
      end
      if passed_rows.length != 1
        errors << "#{label} must join exactly one passed_production_cut_image snapshot row; found #{passed_rows.length}"
        next
      end
      passed_source_id = passed_rows.first["source_id"].to_s
      if passed_source_id.empty?
        errors << "#{label} passed_production_cut_image snapshot row requires a source_id"
        next
      end

      joined_cues << {
        "review_record" => record,
        "placement_production_cut_unit" => production_unit,
        "prompt_packet" => packet,
        "review_image_source_ref" => passed_source_id
      }
    end

    unmatched_units = production_units.each_index.reject { |index| matched_unit_counts[index] == 1 }
    unless unmatched_units.empty?
      placement_ids = unmatched_units.map { |index| production_units[index]["placement_id"].to_s }
      errors << "every placement Production Cut must join exactly one eligible typed review cue; unmatched or duplicate: #{placement_ids.join(', ')}"
    end
    unless joined_cues.length == eligible_records.length && joined_cues.length == production_units.length
      errors << "eligible Production Cut cues, placement units, and joined cues must have exact 1:1 cardinality"
    end

    ReadyLineage.new(
      errors: errors.uniq,
      review: review,
      eligible_records: eligible_records,
      prompt_packets: prompt_packets,
      joined_cues: joined_cues,
      bound_paths: bound_paths,
      bound_source_refs: bound_source_refs
    )
  end

  def eligible_review_records(review)
    Array(review["production_cut_reviews"]).select { |record| eligible_review_record?(record) }
  end

  def founder_pass_review_records(review)
    Array(review["production_cut_reviews"]).select do |record|
      record.is_a?(Hash) && record["pixel_review_status"].to_s == "passed_production_cut"
    end
  end

  def eligible_review_record?(record)
    record.is_a?(Hash) &&
      %w[official_core branch].include?(record["production_cut_type"].to_s) &&
      record["pixel_review_status"].to_s == "passed_production_cut"
  end

  def review_prompt_disposition(record)
    eligible_review_record?(record) ? "authoring_eligible" : "blocked"
  end

  def normalized_review_prompt_status(record)
    record.to_h["pixel_review_status"].to_s
  end

  def review_core_cut_id(record)
    record.to_h["parent_core_cut_id"].to_s
  end

  def review_core_branch_identity_missing?(record)
    record.to_h["parent_core_cut_id"].to_s.empty? || record.to_h["production_cut_id"].to_s.empty?
  end

  def load_yaml_hash(path)
    return {} unless path&.file?

    document = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
    document.is_a?(Hash) ? document : {}
  rescue Psych::SyntaxError
    {}
  end

  def discover_latest_sources(run_path)
    patterns = {
      "front_planning_readiness" => ["research/front-planning-readiness-v*.yaml", "research/front-planning-readiness-v*.json"],
      "selected_audio_analysis" => ["research/selected-audio-analysis-v*.yaml", "research/selected-audio-analysis-v*.json", "research/selected-audio-analysis-v*.md", "research/audio-analysis-v*.md"],
      "audio_motion_director_map" => ["research/audio-motion-director-map-v*.yaml"],
      "prompt_export_index" => ["exports/02B/export-index.yaml"],
      "grok_imagine_handoff_index" => ["handoff/02-03-grok-imagine-*-webp/handoff-index.json"],
      "cue_sheet_board" => ["handoff/02-03-grok-imagine-*-webp/00-review/cue-sheet-v*.md"],
      "motion_count_guide" => ["handoff/*motion-count-guide*.md"],
      "image_choreo_summary" => ["handoff/*image-choreo-summary*.md"],
      "video_prompt_manifest_03v" => ["03V-video-prompt-manifest*.yaml"],
      "audio_branch_cut_placement" => ["03V-audio-branch-cut-placement.yaml", "review/03v-audio-branch-cut-placement-v*.yaml"]
    }
    patterns.each_with_object({}) do |(role, globs), selected|
      candidates = globs.flat_map { |pattern| Dir.glob(run_path.join(pattern).to_s) }
                        .select { |path| File.file?(path) }
                        .uniq
                        .sort_by { |path| version_sort_key(path) }
      selected[role] = Pathname.new(candidates.last) unless candidates.empty?
    end
  end

  def discoverable_roles
    %w[
      production_cut_review
      song_lock
      front_planning_readiness
      selected_audio_analysis
      audio_motion_director_map
      song_choreography_performance_mv_map
      master_storyboard
      prompt_packets
      prompt_export_index
      grok_imagine_handoff_index
      cue_sheet_board
      motion_count_guide
      image_choreo_summary
      video_prompt_manifest_03v
      audio_branch_cut_placement
      source_audio
      album_visual_asset_manifest
    ]
  end

  def required_role?(role, gate_applies)
    return true if role == "production_cut_review"
    return false unless gate_applies

    %w[audio_motion_director_map audio_branch_cut_placement source_audio].include?(role) || role.start_with?("passed_production_cut_image_")
  end

  def gate_required_roles(gate_applies)
    roles = ["production_cut_review"]
    return roles unless gate_applies

    roles + %w[passed_production_cut_image audio_branch_cut_placement source_audio audio_motion_director_map]
  end

  def add_front_planning_pointer_sources!(selected, repo_root)
    readiness_path = selected["front_planning_readiness"]
    readiness = load_yaml_hash(readiness_path)
    visual_identity = readiness["current_title_visual_identity"]
    return unless visual_identity.is_a?(Hash)

    manifest = visual_identity["asset_manifest"]
    raw_path = manifest.is_a?(Hash) ? manifest["path"] : nil
    path = resolve_repo_path(raw_path, repo_root)
    selected["album_visual_asset_manifest"] = path if path&.file?
  end

  def resolved_review_source(review, key, run_path, repo_root, fallback)
    ref = review[key]
    raw = ref.is_a?(Hash) ? ref["path"] : nil
    path = resolve_repo_path(raw, repo_root)
    return path if path&.file?

    fallback_path = run_path.join(fallback)
    fallback_path.file? ? fallback_path : nil
  end

  def source_row(role, path, repo_root, required_for_gate:)
    {
      "role" => role,
      "path" => relative_path(path, repo_root),
      "sha256" => Digest::SHA256.file(path.to_s).hexdigest,
      "required_for_gate" => required_for_gate
    }
  end

  def canonical_source_set_digest(rows)
    canonical_rows = Array(rows).each_with_object([]) do |row, values|
      next unless row.is_a?(Hash)

      values << {
        "source_id" => row["source_id"],
        "role" => row["role"],
        "path" => row["path"],
        "sha256" => row["sha256"],
        "required_for_gate" => row["required_for_gate"]
      }
    end.sort_by { |row| [row["source_id"].to_s, row["role"].to_s, row["path"].to_s] }
    Digest::SHA256.hexdigest(JSON.generate(canonical_rows))
  end

  def resolve_repo_path(raw_path, repo_root)
    return nil if raw_path.to_s.strip.empty?

    path = Pathname.new(raw_path.to_s)
    resolved = path.absolute? ? path.cleanpath : Pathname.new(repo_root).join(path).cleanpath
    inside_root?(resolved, repo_root) ? resolved : nil
  end

  def same_realpath?(left, right)
    return false unless left&.file? && right&.file?

    left.realpath == right.realpath
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  def relative_path(path, repo_root)
    path = Pathname.new(path).expand_path.cleanpath
    root = Pathname.new(repo_root).expand_path.cleanpath
    path.relative_path_from(root).to_s
  rescue ArgumentError
    path.to_s
  end

  def inside_root?(path, root)
    candidate = Pathname.new(path).expand_path.cleanpath
    owner = Pathname.new(root).expand_path.cleanpath
    candidate = candidate.realpath if candidate.exist?
    owner = owner.realpath if owner.exist?
    candidate.to_s == owner.to_s || candidate.to_s.start_with?("#{owner}/")
  rescue Errno::ENOENT, Errno::EACCES
    false
  end

  def version_sort_key(path)
    versions = path.to_s.scan(/(?:\A|[-_])v(\d+)(?=\D|\z)/i).flatten.map(&:to_i)
    [versions.empty? ? -1 : versions.last, path.to_s]
  end
end
