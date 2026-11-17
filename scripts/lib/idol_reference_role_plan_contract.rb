# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"

module IdolReferenceRolePlanContract
  class ContractError < StandardError; end

  FUNCTION_PURPOSES = %w[
    major_scene_grammar_or_feeling
    background_and_space
    still_camera_and_composition
    lighting_color_material
    subject_state_or_pose
    visible_action_or_hold
    object_environment_response
    edit_or_transition
  ].freeze
  SOURCE_MEDIA_TYPES = %w[
    image video video_selected_range image_selected_crop video_frame contact_sheet
    board crop generated_image other
  ].freeze
  MOTION_SOURCE_MEDIA_TYPES = %w[video video_selected_range].freeze
  WORLD_PURPOSES = %w[
    major_scene_grammar_or_feeling background_and_space lighting_color_material
    object_environment_response
  ].freeze
  MOTION_PURPOSES = %w[
    subject_state_or_pose visible_action_or_hold edit_or_transition
  ].freeze

  module_function

  def verify!(plan:, attachments:, member_visual_applicability:, current_section_id:, root:, label: "reference_role_plan")
    mapping!(plan, label)
    fail_contract!("#{label} must be authored by a human or assigned model") unless plan["authoring_owner"].to_s == "human_or_assigned_model"

    attachment_rows = array!(attachments, "#{label} attachments")
    binding_ids = attachment_rows.map { |row| nonempty!(mapping!(row, "#{label} attachment")["binding_id"], "#{label} attachment binding_id") }
    expected_orders = (1..attachment_rows.length).to_a
    fail_contract!("#{label} attachment order must be contiguous from 1") unless attachment_rows.map { |row| row["order"] } == expected_orders
    fail_contract!("#{label} attachment binding ids must be unique") unless binding_ids.uniq.length == binding_ids.length
    attachment_by_id = attachment_rows.to_h { |row| [row.fetch("binding_id").to_s, row] }
    attachment_digests = attachment_rows.map do |row|
      binding_id = row.fetch("binding_id").to_s
      path = repo_path!(row["actual_path"], root, "#{label} attachment #{binding_id} actual_path")
      declared_digest = sha256!(row["sha256"], "#{label} attachment #{binding_id} sha256")
      actual_digest = Digest::SHA256.file(path).hexdigest
      fail_contract!("#{label} attachment #{binding_id} SHA-256 is stale") unless declared_digest == actual_digest
      actual_digest
    end
    unless attachment_digests.uniq.length == attachment_digests.length
      fail_contract!("#{label} identical attachment bytes must be registered once even when paths differ")
    end
    unless Array(plan["attachment_order_binding_ids"]).map(&:to_s) == binding_ids
      fail_contract!("#{label} must exact-carry transport attachment order")
    end

    groups = array!(plan["logical_role_groups"], "#{label}.logical_role_groups")
    roles = groups.map { |group| mapping!(group, "#{label} logical role group")["logical_role"].to_s }
    fail_contract!("#{label} allows no more than four logical role groups") if groups.length > 4
    fail_contract!("#{label} logical role groups must be unique") unless roles.uniq.length == roles.length
    required_roles = %w[character_visual scene_visual_package motion_reference]
    missing = required_roles - roles
    fail_contract!("#{label} is missing required roles: #{missing.join(', ')}") unless missing.empty?
    unknown = roles - (required_roles + ["prop_reference"])
    fail_contract!("#{label} has unknown roles: #{unknown.join(', ')}") unless unknown.empty?
    by_role = groups.to_h { |group| [group.fetch("logical_role"), group] }

    groups.each do |group|
      role = group.fetch("logical_role")
      dangling = Array(group["attachment_binding_ids"]).map(&:to_s) - binding_ids
      fail_contract!("#{label}.#{role} names an unlocked attachment") unless dangling.empty?
    end

    member_ids = attachment_rows.select { |row| row["role"].to_s == "current_title_member_visual" }.map { |row| row["binding_id"].to_s }
    character = by_role.fetch("character_visual")
    character_ids = Array(character["attachment_binding_ids"]).map(&:to_s)
    if member_visual_applicability.to_s == "meaningfully_visible"
      unless character["applicability"].to_s == "required" && character_ids == member_ids && !member_ids.empty?
        fail_contract!("#{label}.character_visual differs from visible current-title inputs")
      end
    elsif character["applicability"].to_s != "not_applicable_member_absent" || !character_ids.empty?
      fail_contract!("#{label} character-absent Cut must not attach a dummy character_visual")
    end

    scene = by_role.fetch("scene_visual_package")
    scene_ids = Array(scene["attachment_binding_ids"]).map(&:to_s)
    world_ids = Array(scene["world_look_binding_ids"]).map(&:to_s)
    composition_id = scene["composition_anchor_binding_id"].to_s
    unless scene["applicability"].to_s == "required" && !scene_ids.empty? &&
           world_ids.uniq.length == world_ids.length && scene_ids.uniq.length == scene_ids.length &&
           scene_ids.sort == (world_ids + [composition_id]).uniq.sort
      fail_contract!("#{label}.scene_visual_package world/look and composition bindings are incomplete")
    end
    world_lineage = array!(scene["world_look_function_lineage"], "#{label}.scene_visual_package.world_look_function_lineage")
    fail_contract!("#{label}.scene_visual_package requires world/look function lineage") if world_lineage.empty?
    unless world_lineage.map { |row| value_sha256(row) }.uniq.length == world_lineage.length
      fail_contract!("#{label}.scene_visual_package function lineage rows must be unique")
    end
    world_lineage.each_with_index do |row, index|
      verify_lineage!(
        lineage: row,
        attachment_binding_ids: world_ids,
        allowed_purposes: WORLD_PURPOSES,
        attachment_by_id: attachment_by_id,
        current_section_id: current_section_id,
        root: root,
        label: "#{label}.scene_visual_package.world_look_function_lineage[#{index}]"
      )
    end
    covered_world_ids = world_lineage.map { |row| row.to_h["attachment_binding_id"].to_s }.uniq
    unless covered_world_ids.sort == world_ids.sort
      fail_contract!("#{label}.scene_visual_package world/look bindings must each carry exact function lineage")
    end
    verify_lineage!(
      lineage: scene["composition_anchor_function_lineage"],
      attachment_binding_ids: [composition_id],
      allowed_purposes: ["still_camera_and_composition"],
      attachment_by_id: attachment_by_id,
      current_section_id: current_section_id,
      root: root,
      label: "#{label}.scene_visual_package.composition_anchor_function_lineage"
    )

    motion = by_role.fetch("motion_reference")
    motion_ids = Array(motion["attachment_binding_ids"]).map(&:to_s)
    unless motion["applicability"].to_s == "required" && !motion_ids.empty? &&
           motion["sampling_interval_seconds"] == 1 && motion["sample_count"] == 5 &&
           !motion["sequence_unit_id"].to_s.empty? && !motion["source_locator"].to_s.empty? &&
           !motion["contiguous_event"].to_s.empty?
      fail_contract!("#{label}.motion_reference requires exactly five contiguous one-second samples")
    end
    motion_lineage = array!(motion["motion_function_lineage"], "#{label}.motion_reference.motion_function_lineage")
    fail_contract!("#{label}.motion_reference requires function lineage") if motion_lineage.empty?
    unless motion_lineage.map { |row| value_sha256(row) }.uniq.length == motion_lineage.length
      fail_contract!("#{label}.motion_reference function lineage rows must be unique")
    end
    motion_lineage.each_with_index do |row, index|
      motion_lineage_row = mapping!(row, "#{label}.motion_reference.motion_function_lineage[#{index}]")
      unless MOTION_SOURCE_MEDIA_TYPES.include?(motion_lineage_row["source_media_type"].to_s)
        fail_contract!("#{label}.motion_reference.motion_function_lineage[#{index}] source_media_type must be video or video_selected_range")
      end
      verify_lineage!(
        lineage: motion_lineage_row,
        attachment_binding_ids: motion_ids,
        allowed_purposes: MOTION_PURPOSES,
        attachment_by_id: attachment_by_id,
        current_section_id: current_section_id,
        root: root,
        label: "#{label}.motion_reference.motion_function_lineage[#{index}]"
      )
      verify_motion_sequence_unit!(
        lineage: motion_lineage_row,
        expected_sequence_unit_id: motion["sequence_unit_id"],
        expected_event_identity: motion["contiguous_event"],
        root: root,
        label: "#{label}.motion_reference.motion_function_lineage[#{index}]"
      )
    end
    sequence_bindings = motion_lineage.map do |row|
      [row.to_h.dig("source_artifact", "path").to_s, row.to_h["sequence_unit_json_pointer"].to_s, row.to_h["sequence_unit_value_sha256"].to_s]
    end
    unless sequence_bindings.uniq.length == 1
      fail_contract!("#{label}.motion_reference must exact-bind one Front Planning Sequence Unit")
    end
    covered_motion_ids = motion_lineage.map { |row| row.to_h["attachment_binding_id"].to_s }.uniq
    unless covered_motion_ids.sort == motion_ids.uniq.sort
      fail_contract!("#{label}.motion_reference attachments must each carry exact function lineage")
    end

    if by_role.key?("prop_reference")
      prop = by_role.fetch("prop_reference")
      prop_ids = Array(prop["attachment_binding_ids"]).map(&:to_s)
      if prop["applicability"].to_s == "required" && prop_ids.empty?
        fail_contract!("#{label} material prop_reference requires at least one attachment")
      end
      if prop["applicability"].to_s == "not_applicable_no_material_prop" && !prop_ids.empty?
        fail_contract!("#{label} non-material prop_reference must not attach dummy input")
      end
      if prop["applicability"].to_s == "required"
        prop_lineage = array!(prop["prop_function_lineage"], "#{label}.prop_reference.prop_function_lineage")
        fail_contract!("#{label}.prop_reference requires function lineage") if prop_lineage.empty?
        unless prop_lineage.map { |row| value_sha256(row) }.uniq.length == prop_lineage.length
          fail_contract!("#{label}.prop_reference function lineage rows must be unique")
        end
        prop_lineage.each_with_index do |row, index|
          verify_lineage!(
            lineage: row,
            attachment_binding_ids: prop_ids,
            allowed_purposes: %w[object_environment_response subject_state_or_pose visible_action_or_hold],
            attachment_by_id: attachment_by_id,
            current_section_id: current_section_id,
            root: root,
            label: "#{label}.prop_reference.prop_function_lineage[#{index}]"
          )
        end
        covered_prop_ids = prop_lineage.map { |row| row.to_h["attachment_binding_id"].to_s }.uniq
        unless covered_prop_ids.sort == prop_ids.uniq.sort
          fail_contract!("#{label}.prop_reference attachments must each carry exact function lineage")
        end
      elsif prop.key?("prop_function_lineage")
        fail_contract!("#{label} non-material prop_reference must not carry function lineage")
      end
    end

    covered_ids = groups.flat_map { |group| Array(group["attachment_binding_ids"]).map(&:to_s) }.uniq
    fail_contract!("#{label} must cover every transport attachment") unless binding_ids.all? { |binding_id| covered_ids.include?(binding_id) }
    plan
  rescue KeyError => e
    fail_contract!("#{label} is missing required field: #{e.key}")
  end

  def verify_lineage!(lineage:, attachment_binding_ids:, allowed_purposes:, attachment_by_id:, current_section_id:, root:, label:)
    row = mapping!(lineage, label)
    binding_id = nonempty!(row["attachment_binding_id"], "#{label}.attachment_binding_id")
    fail_contract!("#{label}.attachment_binding_id is outside its logical role") unless attachment_binding_ids.include?(binding_id)
    attachment = mapping!(attachment_by_id[binding_id], "#{label} attachment")
    attachment_path = repo_path!(attachment["actual_path"], root, "#{label} attachment actual_path")
    attachment_sha = sha256!(attachment["sha256"], "#{label} attachment sha256")
    fail_contract!("#{label} attachment SHA-256 is stale") unless Digest::SHA256.file(attachment_path).hexdigest == attachment_sha

    purpose = nonempty!(row["purpose"], "#{label}.purpose")
    unless FUNCTION_PURPOSES.include?(purpose) && allowed_purposes.include?(purpose)
      fail_contract!("#{label}.purpose is not allowed for this logical reference role")
    end
    media_type = nonempty!(row["source_media_type"], "#{label}.source_media_type")
    fail_contract!("#{label}.source_media_type must describe source shape") unless SOURCE_MEDIA_TYPES.include?(media_type)
    if FUNCTION_PURPOSES.include?(media_type) || SOURCE_MEDIA_TYPES.include?(purpose)
      fail_contract!("#{label} must keep source_media_type separate from purpose")
    end
    fail_contract!("#{label}.disposition must be applied or combined") unless %w[applied combined].include?(row["disposition"].to_s)

    source_ref = mapping!(row["source_artifact"], "#{label}.source_artifact")
    source_path = repo_path!(source_ref["path"], root, "#{label}.source_artifact.path")
    fail_contract!("#{label}.source_artifact.sha256 is stale") unless sha256!(source_ref["sha256"], "#{label}.source_artifact.sha256") == Digest::SHA256.file(source_path).hexdigest
    source_document = load_mapping!(source_path, "#{label}.source_artifact")
    unless source_document["schema_version"].to_s == source_ref["schema_version"].to_s &&
           source_ref["schema_version"].to_s == "front-planning-readiness.v17"
      fail_contract!("#{label}.source_artifact must be the active Front Planning contract")
    end

    unit_pointer = nonempty!(row["reference_unit_json_pointer"], "#{label}.reference_unit_json_pointer")
    unit = mapping!(json_pointer_get!(source_document, unit_pointer), "#{label} referenced Front Planning unit")
    fail_contract!("#{label}.reference_unit_id differs from the referenced Front Planning unit") unless unit["reference_unit_id"].to_s == row["reference_unit_id"].to_s
    unless value_sha256(unit) == sha256!(row["reference_unit_value_sha256"], "#{label}.reference_unit_value_sha256")
      fail_contract!("#{label}.reference_unit_value_sha256 is stale")
    end
    fail_contract!("#{label}.disposition differs from the referenced Front Planning unit") unless unit["disposition"].to_s == row["disposition"].to_s
    unit_source_path = repo_path!(unit["source_path"], root, "#{label} referenced Front Planning unit source_path")
    unit_source_sha = sha256!(unit["source_sha256"], "#{label} referenced Front Planning unit source_sha256")
    unless unit_source_path == attachment_path && unit_source_sha == attachment_sha
      fail_contract!("#{label} referenced Front Planning unit does not exact-bind the physical attachment")
    end
    unless Array(unit["target_section_ids"]).map(&:to_s).include?(nonempty!(current_section_id, "#{label} current_section_id"))
      fail_contract!("#{label} referenced Front Planning unit is outside the current section")
    end

    function_pointer = nonempty!(row["function_json_pointer"], "#{label}.function_json_pointer")
    unless function_pointer.start_with?("#{unit_pointer}/function_analysis/")
      fail_contract!("#{label}.function_json_pointer must stay inside its referenced Front Planning unit")
    end
    function = mapping!(json_pointer_get!(source_document, function_pointer), "#{label} referenced Front Planning function")
    unless function["function_id"].to_s == row["function_id"].to_s && function["purpose"].to_s == purpose
      fail_contract!("#{label} function id or purpose differs from the referenced Front Planning function")
    end
    unless value_sha256(function) == sha256!(row["function_value_sha256"], "#{label}.function_value_sha256")
      fail_contract!("#{label}.function_value_sha256 is stale")
    end
    row
  end

  def verify_motion_sequence_unit!(lineage:, expected_sequence_unit_id:, expected_event_identity:, root:, label:)
    row = mapping!(lineage, label)
    source_ref = mapping!(row["source_artifact"], "#{label}.source_artifact")
    source_path = repo_path!(source_ref["path"], root, "#{label}.source_artifact.path")
    source_document = load_mapping!(source_path, "#{label}.source_artifact")
    unit_pointer = nonempty!(row["reference_unit_json_pointer"], "#{label}.reference_unit_json_pointer")
    sequence_pointer = nonempty!(row["sequence_unit_json_pointer"], "#{label}.sequence_unit_json_pointer")
    unless sequence_pointer == "#{unit_pointer}/sequence_unit"
      fail_contract!("#{label}.sequence_unit_json_pointer must name the Sequence Unit inside its referenced Front Planning unit")
    end

    sequence_unit = mapping!(json_pointer_get!(source_document, sequence_pointer), "#{label} referenced Front Planning Sequence Unit")
    expected_value_digest = sha256!(row["sequence_unit_value_sha256"], "#{label}.sequence_unit_value_sha256")
    unless value_sha256(sequence_unit) == expected_value_digest
      fail_contract!("#{label}.sequence_unit_value_sha256 is stale")
    end
    unless sequence_unit["sequence_unit_id"].to_s == nonempty!(expected_sequence_unit_id, "#{label} expected sequence_unit_id")
      fail_contract!("#{label}.sequence_unit_id differs from the referenced Front Planning Sequence Unit")
    end
    unless sequence_unit["event_identity"].to_s == nonempty!(expected_event_identity, "#{label} expected event_identity")
      fail_contract!("#{label}.contiguous_event differs from the referenced Front Planning Sequence Unit")
    end
    unless sequence_unit["frame_selection_mode"].to_s == "fixed_cadence" && sequence_unit["declared_cadence_seconds"] == 1
      fail_contract!("#{label} referenced Front Planning Sequence Unit must declare fixed one-second cadence")
    end

    frames = array!(sequence_unit["ordered_frames"], "#{label} referenced Front Planning Sequence Unit ordered_frames")
    fail_contract!("#{label} referenced Front Planning Sequence Unit must contain exactly five frames") unless frames.length == 5
    timestamps = verify_sequence_rows!(
      rows: frames,
      label: "#{label} referenced Front Planning Sequence Unit ordered_frames"
    )
    unless timestamps.each_cons(2).all? { |left, right| (right - left - 1.0).abs <= 1e-9 }
      fail_contract!("#{label} referenced Front Planning Sequence Unit timestamps must advance at exact one-second cadence")
    end

    frame_paths = []
    source_frame_ids = []
    frames.each_with_index do |frame, index|
      source_frame_ids << nonempty!(frame["source_frame_or_cell_id"], "#{label} referenced Front Planning Sequence Unit frame #{index + 1} source_frame_or_cell_id")
      artifact = mapping!(frame["artifact"], "#{label} referenced Front Planning Sequence Unit frame #{index + 1} artifact")
      artifact_path = repo_path!(artifact["path"], root, "#{label} referenced Front Planning Sequence Unit frame #{index + 1} path")
      artifact_sha = sha256!(artifact["sha256"], "#{label} referenced Front Planning Sequence Unit frame #{index + 1} sha256")
      unless Digest::SHA256.file(artifact_path).hexdigest == artifact_sha
        fail_contract!("#{label} referenced Front Planning Sequence Unit frame #{index + 1} SHA-256 is stale")
      end
      frame_paths << artifact_path.to_s
    end
    unless frame_paths.uniq.length == frame_paths.length
      fail_contract!("#{label} referenced Front Planning Sequence Unit frame paths must be unique")
    end
    unless source_frame_ids.uniq.length == source_frame_ids.length
      fail_contract!("#{label} referenced Front Planning Sequence Unit source frame ids must be unique")
    end

    observations = array!(sequence_unit["frame_observations"], "#{label} referenced Front Planning Sequence Unit frame_observations")
    fail_contract!("#{label} referenced Front Planning Sequence Unit must contain exactly five frame observations") unless observations.length == 5
    observation_timestamps = verify_sequence_rows!(
      rows: observations,
      label: "#{label} referenced Front Planning Sequence Unit frame_observations"
    )
    unless observation_timestamps == timestamps
      fail_contract!("#{label} referenced Front Planning Sequence Unit observations must align to the five ordered frames")
    end

    mapping!(sequence_unit["flow_reading"], "#{label} referenced Front Planning Sequence Unit flow_reading")
    manifest = mapping!(sequence_unit["manifest"], "#{label} referenced Front Planning Sequence Unit manifest")
    manifest_path = repo_path!(manifest["path"], root, "#{label} referenced Front Planning Sequence Unit manifest path")
    manifest_sha = sha256!(manifest["sha256"], "#{label} referenced Front Planning Sequence Unit manifest sha256")
    unless Digest::SHA256.file(manifest_path).hexdigest == manifest_sha
      fail_contract!("#{label} referenced Front Planning Sequence Unit manifest SHA-256 is stale")
    end
    unless sequence_unit["major_reference_eligible"] == true &&
           sequence_unit["downstream_cut_count_rule"].to_s == "five_source_frames_never_imply_five_core_or_branch_cuts"
      fail_contract!("#{label} referenced Front Planning Sequence Unit is not active motion evidence")
    end
    sequence_unit
  end

  def verify_sequence_rows!(rows:, label:)
    timestamps = rows.each_with_index.map do |raw, index|
      row = mapping!(raw, "#{label}[#{index}]")
      unless row["order_index"] == index + 1
        fail_contract!("#{label} order_index must be exactly 1 through 5")
      end
      timestamp = row["timestamp_seconds"]
      fail_contract!("#{label} timestamp_seconds must be numeric") unless timestamp.is_a?(Numeric)
      fail_contract!("#{label} timestamp_seconds must be nonnegative") if timestamp.negative?
      timestamp.to_f
    end
    fail_contract!("#{label} timestamps must be unique") unless timestamps.uniq.length == timestamps.length
    timestamps
  end

  def canonical(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical(value[source_key])
      end
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def value_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def load_mapping!(path, label)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
            end
    mapping!(value, label)
  rescue JSON::ParserError, Psych::Exception => e
    fail_contract!("cannot parse #{label}: #{e.message}")
  end

  def repo_path!(raw, root, label)
    root_path = Pathname.new(root).expand_path.cleanpath
    path = Pathname.new(nonempty!(raw, label))
    path = root_path.join(path) unless path.absolute?
    path = path.expand_path.cleanpath
    relative = path.relative_path_from(root_path).to_s
    fail_contract!("#{label} escapes the IDOL repository") if relative == ".." || relative.start_with?("../")
    fail_contract!("#{label} is missing: #{relative}") unless path.file?
    path
  rescue ArgumentError
    fail_contract!("#{label} escapes the IDOL repository")
  end

  def json_pointer_get!(document, pointer)
    fail_contract!("JSON pointer must start with '/': #{pointer}") unless pointer.to_s.start_with?("/")
    pointer.to_s.split("/")[1..].reduce(document) do |current, raw_token|
      token = raw_token.gsub("~1", "/").gsub("~0", "~")
      case current
      when Hash
        fail_contract!("JSON pointer not found: #{pointer}") unless current.key?(token)
        current[token]
      when Array
        fail_contract!("JSON pointer array token is invalid: #{pointer}") unless token.match?(/\A(?:0|[1-9][0-9]*)\z/)
        index = token.to_i
        fail_contract!("JSON pointer array index is out of range: #{pointer}") unless index < current.length
        current[index]
      else
        fail_contract!("JSON pointer traverses a scalar: #{pointer}")
      end
    end
  end

  def mapping!(value, label)
    fail_contract!("#{label} must be an object") unless value.is_a?(Hash)
    value
  end

  def array!(value, label)
    fail_contract!("#{label} must be an array") unless value.is_a?(Array)
    value
  end

  def nonempty!(value, label)
    text = value.to_s.strip
    fail_contract!("#{label} must not be empty") if text.empty?
    text
  end

  def sha256!(value, label)
    digest = value.to_s
    fail_contract!("#{label} must be a lowercase SHA-256 digest") unless digest.match?(/\A[0-9a-f]{64}\z/)
    digest
  end

  def fail_contract!(message)
    raise ContractError, message
  end
end
