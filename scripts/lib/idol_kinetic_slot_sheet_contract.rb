# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"

# Change-point slot sheet for one Major. Presence, binding, neighbor-axis
# declaration, Core 1-2 nails, Key Screen inheritance pointer, and collected
# production-start pair completeness only. Scripts never score uniqueness or
# cinema, never count seconds, and never convert Sequence / scene_phases /
# Core slots / Key Screens into this layer.
module IdolKineticSlotSheetContract
  CONTRACT_VERSION = "kinetic_change_point_slot_sheet.v1"
  CHANGE_AXES = %w[angle action person background authored_hold].freeze
  BINDINGS = %w[core branch].freeze
  CAMERA_AXES = %w[camera_height shot_scale_distance direction_angle depth].freeze
  SLOT_ID = /\AKSL_[A-Z0-9_]{2,100}\z/
  MAJOR_ID = /\AMJ[0-9]{2,}\z/
  SECTION_ID = /\AS[0-9]{2,}[A-Z]?\z/
  KEY_SCREEN_ID = /\AKS_[A-Z0-9_]{2,100}\z/

  module_function

  def validate(sheet)
    unless sheet.is_a?(Hash)
      return ["kinetic slot sheet must be an object"]
    end

    errors = []
    errors << "kinetic slot sheet schema_version must be #{CONTRACT_VERSION}" unless sheet["schema_version"].to_s == CONTRACT_VERSION
    errors << "kinetic slot sheet automatic_creative_pass must be false" unless sheet["automatic_creative_pass"] == false
    errors << "kinetic slot sheet major_scene_id is missing" unless sheet["major_scene_id"].to_s.match?(MAJOR_ID)
    errors << "kinetic slot sheet section_id is missing" unless sheet["section_id"].to_s.match?(SECTION_ID)
    errors.concat(sequence_errors(sheet["sequence_evidence"]))
    errors.concat(slot_errors(sheet))
    errors.concat(core_errors(sheet))
    errors.concat(inheritance_errors(sheet))
    errors.concat(collected_pair_errors(sheet))
    errors
  end

  def closeable?(sheet)
    validate(sheet).empty?
  end

  def expected_pair_keys(slot_ids)
    slot_ids.combination(2).map { |left, right| [left, right].sort }
  end

  def core_nail_slots(sheet)
    Array(sheet.to_h["slots"]).select { |slot| slot.is_a?(Hash) && slot["production_binding"].to_s == "core" }
  end

  def sequence_errors(evidence)
    unless evidence.is_a?(Hash)
      return ["kinetic slot sheet sequence_evidence is missing"]
    end

    errors = []
    ids = Array(evidence["sequence_unit_ids"]).map(&:to_s)
    errors << "kinetic slot sheet sequence_evidence.sequence_unit_ids is empty" if ids.empty? || ids.any?(&:empty?)
    errors << "kinetic slot sheet sequence_evidence.not_cut_plan must be true" unless evidence["not_cut_plan"] == true
    errors
  end

  def slot_errors(sheet)
    slots = sheet["slots"]
    unless slots.is_a?(Array) && !slots.empty?
      return ["kinetic slot sheet slots is empty"]
    end

    errors = []
    seen = []
    slots.each_with_index do |slot, index|
      unless slot.is_a?(Hash)
        errors << "kinetic slot sheet slot #{index + 1} must be an object"
        next
      end

      slot_id = slot["slot_id"].to_s
      errors << "kinetic slot sheet slot #{index + 1} slot_id is missing" unless slot_id.match?(SLOT_ID)
      errors << "kinetic slot sheet duplicate slot_id: #{slot_id}" if seen.include?(slot_id)
      seen << slot_id unless slot_id.empty?
      errors << "kinetic slot sheet #{slot_id} ordinal must be #{index + 1}" unless slot["ordinal"] == index + 1
      axis = slot["change_axis"].to_s
      errors << "kinetic slot sheet #{slot_id} change_axis is missing" unless CHANGE_AXES.include?(axis)
      binding = slot["production_binding"].to_s
      errors << "kinetic slot sheet #{slot_id} production_binding must be core or branch" unless BINDINGS.include?(binding)
      errors << "kinetic slot sheet #{slot_id} screen_job is empty" if slot["screen_job"].to_s.strip.empty?
      errors << "kinetic slot sheet #{slot_id} visible_action_or_hold is empty" if slot["visible_action_or_hold"].to_s.strip.empty?

      previous = slot["previous_slot_id"]
      if index.zero?
        errors << "kinetic slot sheet #{slot_id} previous_slot_id must be null" unless previous.nil?
      else
        expected_previous = slots[index - 1].is_a?(Hash) ? slots[index - 1]["slot_id"].to_s : ""
        errors << "kinetic slot sheet #{slot_id} previous_slot_id must be the prior slot" unless previous.to_s == expected_previous
        prior_axis = slots[index - 1].is_a?(Hash) ? slots[index - 1]["change_axis"].to_s : ""
        unless axis != prior_axis || axis == "authored_hold"
          errors << "kinetic slot sheet #{slot_id} must declare a different change_axis than the previous slot or an authored hold"
        end
      end

      if axis == "authored_hold"
        %w[hold_reason continuity_in continuity_out].each do |key|
          errors << "kinetic slot sheet #{slot_id} #{key} is empty" if slot[key].to_s.strip.empty?
        end
      end

      if binding == "core"
        errors.concat(camera_errors(slot_id, slot["still_camera"]))
      end
    end
    errors
  end

  def camera_errors(slot_id, camera)
    unless camera.is_a?(Hash)
      return ["kinetic slot sheet #{slot_id} still_camera is missing"]
    end

    CAMERA_AXES.map do |axis|
      "kinetic slot sheet #{slot_id} still_camera.#{axis} is empty" if camera[axis].to_s.strip.empty?
    end.compact
  end

  def core_errors(sheet)
    nails = Array(sheet["core_nail_slot_ids"]).map(&:to_s)
    errors = []
    errors << "kinetic slot sheet core_nail_slot_ids must contain 1 or 2 ids" unless (1..2).cover?(nails.length)
    errors << "kinetic slot sheet core_nail_slot_ids must be unique" unless nails.uniq.length == nails.length
    core_ids = core_nail_slots(sheet).map { |slot| slot["slot_id"].to_s }
    unless nails.sort == core_ids.sort
      errors << "kinetic slot sheet core_nail_slot_ids must match the Core-bound slots"
    end
    errors
  end

  def inheritance_errors(sheet)
    inheritances = sheet["key_screen_inheritances"]
    unless inheritances.is_a?(Array)
      return ["kinetic slot sheet key_screen_inheritances is missing"]
    end

    errors = []
    core_ids = core_nail_slots(sheet).map { |slot| slot["slot_id"].to_s }
    covered = []
    inheritances.each_with_index do |row, index|
      unless row.is_a?(Hash)
        errors << "kinetic slot sheet key_screen_inheritances #{index + 1} must be an object"
        next
      end

      errors << "kinetic slot sheet key_screen_id is missing" unless row["key_screen_id"].to_s.match?(KEY_SCREEN_ID)
      slot_id = row["inherits_from_slot_id"].to_s
      errors << "kinetic slot sheet Key Screen must inherit from a Core-bound slot" unless core_ids.include?(slot_id)
      errors << "kinetic slot sheet Key Screen inherits must be still_camera_and_action" unless row["inherits"].to_s == "still_camera_and_action"
      errors << "kinetic slot sheet Key Screen camera_reauthored must be false" unless row["camera_reauthored"] == false
      covered << slot_id unless slot_id.empty?
    end
    (core_ids - covered).each do |slot_id|
      errors << "kinetic slot sheet Core-bound slot missing Key Screen inheritance: #{slot_id}"
    end
    errors
  end

  def collected_pair_errors(sheet)
    pairs = sheet["collected_production_start_pairs"]
    unless pairs.is_a?(Array)
      return ["kinetic slot sheet collected_production_start_pairs is missing"]
    end

    core_ids = core_nail_slots(sheet).map { |slot| slot["slot_id"].to_s }.reject(&:empty?)
    expected = expected_pair_keys(core_ids)
    actual = []
    errors = []
    pairs.each_with_index do |pair, index|
      unless pair.is_a?(Hash)
        errors << "kinetic slot sheet collected pair #{index + 1} must be an object"
        next
      end

      left = pair["left_slot_id"].to_s
      right = pair["right_slot_id"].to_s
      errors << "kinetic slot sheet collected pair #{index + 1} slot ids are missing" if left.empty? || right.empty?
      errors << "kinetic slot sheet collected pair #{left}/#{right} declared_change_axis_or_hold is missing" unless CHANGE_AXES.include?(pair["declared_change_axis_or_hold"].to_s)
      errors << "kinetic slot sheet collected pair #{left}/#{right} same_image_exact_carry must be boolean" unless [true, false].include?(pair["same_image_exact_carry"])
      actual << [left, right].sort
    end
    missing = expected - actual
    extra = actual - expected
    missing.each { |left, right| errors << "kinetic slot sheet collected production-start pair is missing: #{left}/#{right}" }
    extra.each { |left, right| errors << "kinetic slot sheet collected production-start pair is unexpected: #{left}/#{right}" }
    errors
  end

  def directory_for(front_path)
    Pathname.new(front_path.to_s.sub(/\.ya?ml\z/i, ".kinetic-slots"))
  end

  def sheet_path_for(front_path, major_id)
    directory_for(front_path).join("#{major_id}.yaml")
  end

  def selected_major_ids(route)
    Array(route.to_h["sections"]).flat_map do |section|
      Array(section.dig("major_scene_stack", "ordered_major_placements")).map { |row| row.to_h["major_scene_id"].to_s } +
        Array(section["route_major_expansions"]).map { |row| row.to_h["major_scene_id"].to_s }
    end.map(&:to_s).reject(&:empty?).uniq
  end

  def coverage_errors(front_path, major_ids, document: nil, selected_route: nil)
    ids = Array(major_ids).map(&:to_s).reject(&:empty?).uniq
    return ["kinetic slot sheet selected Major roster is empty"] if ids.empty?

    errors = []
    ids.each do |major_id|
      path = sheet_path_for(front_path, major_id)
      unless path.file?
        errors << "kinetic slot sheet missing for #{major_id}"
        next
      end

      sheet = YAML.safe_load(path.read, aliases: true)
      unless sheet.is_a?(Hash)
        errors << "kinetic slot sheet for #{major_id} must be an object"
        next
      end
      if sheet["major_scene_id"].to_s != major_id
        errors << "kinetic slot sheet #{major_id} major_scene_id differs"
      end
      validate(sheet).each { |error| errors << "#{major_id}: #{error}" }
      next unless document.is_a?(Hash)

      errors.concat(selected_route_binding_errors(document, selected_route, major_id, sheet))
    end
    errors
  end

  # Identifier equality only. Scripts do not score cinema, density, or camera prose.
  def selected_route_binding_errors(document, selected_route, major_id, sheet)
    identity = selected_major_identity(document, selected_route, major_id)
    if identity.nil?
      return ["kinetic slot sheet #{major_id} is not on the selected route"]
    end

    errors = []
    if sheet["section_id"].to_s != identity.fetch("section_id")
      errors << "kinetic slot sheet #{major_id} section_id differs from selected route #{identity.fetch('section_id')}"
    end

    authentic_units = identity.fetch("sequence_unit_ids")
    sheet_units = Array(sheet.dig("sequence_evidence", "sequence_unit_ids")).map(&:to_s).reject(&:empty?).uniq
    if authentic_units.empty?
      errors << "kinetic slot sheet #{major_id} selected Sequence Composition does not resolve"
    else
      (sheet_units - authentic_units).each do |unit_id|
        errors << "kinetic slot sheet #{major_id} sequence_unit_ids not bound to selected Sequence Composition: #{unit_id}"
      end
      (authentic_units - sheet_units).each do |unit_id|
        errors << "kinetic slot sheet #{major_id} missing selected Sequence Unit: #{unit_id}"
      end
    end

    authentic_key_screens = identity.fetch("key_screen_ids")
    Array(sheet["key_screen_inheritances"]).each do |row|
      next unless row.is_a?(Hash)

      key_id = row["key_screen_id"].to_s
      next if key_id.empty? || authentic_key_screens.include?(key_id)

      errors << "kinetic slot sheet #{major_id} Key Screen #{key_id} does not resolve on that Major"
    end
    errors
  end

  # Selected-route section ownership is the ordered_major_placements row.
  # Selected Sequence units are that placement's selected_sequence_composition_id
  # resolved onto major_scene_catalog typed_sequence_unit_ids. Key Screens are
  # that Major's section_plan key_screen_id values. Identifier sets only.
  def selected_major_identity(document, selected_route, major_id)
    placement = nil
    section_id = nil
    Array(selected_route.to_h["sections"]).each do |section|
      Array(section.dig("major_scene_stack", "ordered_major_placements")).each do |row|
        next unless row.to_h["major_scene_id"].to_s == major_id

        placement = row.to_h
        section_id = section["section_id"].to_s
      end
    end
    return nil if placement.nil? || section_id.to_s.empty?

    selected_composition_id = placement["selected_sequence_composition_id"].to_s
    catalog = Array(document.to_h["major_scene_catalog"]).find { |row| row.to_h["major_scene_id"].to_s == major_id }.to_h
    candidate = Array(catalog.dig("sequence_composition_candidate_set", "candidates")).find do |row|
      row.to_h["sequence_composition_id"].to_s == selected_composition_id
    end.to_h
    sequence_unit_ids = Array(candidate["typed_sequence_unit_ids"]).map(&:to_s).reject(&:empty?).uniq

    key_screen_ids = []
    Array(document.to_h["section_plan"]).each do |section|
      next unless section.to_h["section_id"].to_s == section_id

      Array(section["major_scene_flow"]).each do |major|
        next unless major.to_h["major_scene_id"].to_s == major_id

        key_screen_ids.concat(Array(major["key_screen_anchors"]).map { |row| row.to_h["key_screen_id"].to_s })
      end
    end

    {
      "section_id" => section_id,
      "sequence_unit_ids" => sequence_unit_ids,
      "key_screen_ids" => key_screen_ids.reject(&:empty?).uniq
    }
  end
end
