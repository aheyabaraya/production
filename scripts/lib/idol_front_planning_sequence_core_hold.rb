# frozen_string_literal: true

require "pathname"

# Mechanical presence helper for same-event Sequence frames counted as extra
# Core hypotheses. Does not author creative truth. Frozen COLOR STAY v17 is
# skipped unless --admission-graph is set, and only when the pinned file
# exists. A missing pin is not a skip. Skip is path identity plus existence,
# not a byte SHA pin; no in-tree immutable digest of the frozen yaml is
# available. New Front Planning is checked even when the live schema id
# remains front-planning-readiness.v17.

module IdolFrontPlanningSequenceCoreHold
  HOLD_CODE = "same_event_anchor_counted_as_hypothesis_floor"
  SPLIT_CORE_HOLD_CODE = "same_event_sequence_counted_as_three_cores"
  THIRD_CORE_HOLD_CODE = "third_core_without_new_major"
  LIVE_V17 = "front-planning-readiness.v17"
  REPO_ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  FROZEN_RELATIVE_PATHS = [
    "runs/aurora-m/color-stay/20260811_COLOR_STAY_PRE00/front-planning.yaml"
  ].freeze

  module_function

  def holds(document)
    Array(document["core_visual_candidate_sets"]).map { |set| hold_for_set(set) }.compact +
      split_slot_holds(document) +
      third_core_holds(document)
  end

  def split_slot_holds(document)
    slots_by_unit = Hash.new { |hash, key| hash[key] = [] }
    Array(document["core_visual_candidate_sets"]).each do |set|
      next unless set.is_a?(Hash)

      slot = set["core_slot_id"].to_s
      next if slot.empty?

      Array(set["candidates"]).each do |row|
        next unless row.is_a?(Hash)

        unit = sequence_unit_key(row)
        next if unit.nil?
        next if slots_by_unit[unit].include?(slot)

        slots_by_unit[unit] << slot
      end
    end

    slots_by_unit.each_with_object([]) do |(unit, slots), rows|
      next unless slots.length >= 3

      rows << {
        "core_slot_id" => slots.join(","),
        "code" => SPLIT_CORE_HOLD_CODE,
        "sequence_unit" => unit,
        "candidate_count" => slots.length
      }
    end
  end

  def third_core_holds(document)
    slots_by_major = Hash.new { |hash, key| hash[key] = [] }
    Array(document["core_visual_candidate_sets"]).each do |set|
      next unless set.is_a?(Hash)

      major = set["major_scene_id"].to_s
      slot = set["core_slot_id"].to_s
      next if major.empty? || slot.empty?
      next if slots_by_major[major].include?(slot)

      slots_by_major[major] << slot
    end

    slots_by_major.each_with_object([]) do |(major, slots), rows|
      next unless slots.length >= 3

      rows << {
        "core_slot_id" => slots.join(","),
        "code" => THIRD_CORE_HOLD_CODE,
        "sequence_unit" => major,
        "candidate_count" => slots.length
      }
    end
  end

  def hold_for_set(set)
    return nil unless set.is_a?(Hash)

    candidates = Array(set["candidates"]).select { |row| row.is_a?(Hash) }
    return nil if candidates.length < 2

    units = candidates.map { |row| sequence_unit_key(row) }
    known = units.compact
    return nil if known.empty?
    return nil unless known.length == candidates.length
    return nil unless known.uniq.length == 1

    {
      "core_slot_id" => set["core_slot_id"].to_s,
      "code" => HOLD_CODE,
      "sequence_unit" => known.first,
      "candidate_count" => candidates.length
    }
  end

  def sequence_unit_key(candidate)
    identity = candidate["source_identity"].to_s
    match = identity.match(/\A(.+?)\s+frame\s+\d+/i)
    return normalize_unit_token(match[1]) if match

    path = candidate["actual_path"].to_s
    match = path.match(%r{([^/]+)/frame-\d+}i)
    return normalize_unit_token(match[1]) if match

    nil
  end

  def normalize_unit_token(raw)
    token = raw.to_s.strip.upcase
    su = token.match(/(SU-[A-Z0-9_-]+)/)
    su ? su[1] : token
  end

  def skip_frozen_legacy?(path, admission_graph:)
    return false if admission_graph
    return false unless Pathname.new(path.to_s).expand_path.file?

    FROZEN_RELATIVE_PATHS.include?(repo_relative(path))
  end

  def repo_relative(path)
    raw = Pathname.new(path.to_s).expand_path
    root = REPO_ROOT
    raw = raw.realpath if raw.exist?
    root = root.realpath if root.exist?
    raw.relative_path_from(root).to_s
  rescue ArgumentError, Errno::ENOENT
    Pathname.new(path.to_s).to_s
  end
end
