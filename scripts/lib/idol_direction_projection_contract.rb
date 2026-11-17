# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "idol_reference_interpretation_contract"

# Read-only freshness and subset checks for the 01 -> 02A -> 02B direction
# projection. Raw research remains in 01; this contract proves that selected
# application ids and structured camera routes still resolve to the exact 01.
module IdolDirectionProjectionContract
  module_function

  def load_document(path)
    text = path.read
    value = path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, aliases: true)
    value.is_a?(Hash) ? value : {}
  end

  def resolve_declared(value, owner_path, root)
    raw = Pathname.new(value.to_s)
    return raw.cleanpath if raw.absolute?

    repo_candidate = root.join(raw).cleanpath
    return repo_candidate if repo_candidate.file?

    owner_path.dirname.join(raw).cleanpath
  end

  def pointer_value(document, reference)
    pointer = reference.to_s.split("#", 2)[1]
    return nil unless pointer&.start_with?("/")

    pointer.split("/").drop(1).reduce(document) do |current, raw_token|
      token = raw_token.gsub("~1", "/").gsub("~0", "~")
      case current
      when Hash
        return nil unless current.key?(token)
        current[token]
      when Array
        return nil unless token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < current.length
        current[token.to_i]
      else
        return nil
      end
    end
  end

  def pointer_part(reference)
    value = reference.to_s
    return value if value.start_with?("/")

    value.split("#", 2)[1].to_s
  end

  def canonical_json_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical_json_value(value[source_key])
      end
    when Array
      value.map { |item| canonical_json_value(item) }
    else
      value
    end
  end

  def structured_value_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(value)))
  end

  def ordered_unique(values)
    seen = {}
    Array(values).each_with_object([]) do |value, result|
      signature = JSON.generate(canonical_json_value(value))
      next if seen[signature]

      seen[signature] = true
      result << value
    end
  end

  def joined_application_text(applications, field)
    ordered_unique(applications.map { |row| row[field].to_s.strip }.reject(&:empty?)).join(" | ")
  end

  def expected_reference_carry(application_by_id, application_ids)
    applications = Array(application_ids).map { |application_id| application_by_id[application_id.to_s] }.compact
    {
      "source_01_application_ids" => Array(application_ids).map(&:to_s),
      "source_identities" => ordered_unique(applications.flat_map { |row| Array(row["source_identities"]).map(&:to_s) }),
      "selected_function" => joined_application_text(applications, "selected_function"),
      "followed_surfaces" => ordered_unique(applications.flat_map { |row| Array(row["followed_surfaces"]) }),
      "cut_consequence" => joined_application_text(applications, "current_song_consequence"),
      "reject_guard" => joined_application_text(applications, "reject_guard")
    }
  end

  def raw_source_identity?(value)
    text = value.to_s.strip
    text.match?(%r{\Ahttps?://}i) ||
      text.match?(%r{\A(?:/|[A-Za-z]:[\\/])}) ||
      text.match?(%r{(?:\A|/)(?:runs|research|assets|source-materials|reference-library)/}i) ||
      text.match?(/\.(?:png|jpe?g|webp|gif|ya?ml|json|md)(?:#.*)?\z/i)
  end

  def cut_sections(cut)
    Array(cut["source_sections"]).map(&:to_s).reject(&:empty?).uniq
  end

  def cut_identifier(cut)
    (cut["cut_id"] || cut["beat_id"]).to_s
  end

  def camera_route_spec?(value)
    value.is_a?(Hash) && value["contract_version"].to_s == "camera_direction.v2"
  end

  def direction_camera_route_rows(direction)
    rows = []
    Array(direction.dig("section_gate", "slices")).each_with_index do |section, index|
      next unless section.is_a?(Hash)

      spec = section["camera_route_spec"]
      next unless camera_route_spec?(spec)

      rows << {
        "section_id" => (section["section_id"] || section["visual_section_id"]).to_s,
        "pointer" => "/section_gate/slices/#{index}/camera_route_spec",
        "route_spec" => spec
      }
    end
    Array(direction["lyric_to_scene_thinking"]).each_with_index do |section, index|
      next unless section.is_a?(Hash)

      spec = section.dig("director_chain", "camera_route_spec")
      next unless camera_route_spec?(spec)

      rows << {
        "section_id" => (section["section_or_beat_id"] || section["section_id"]).to_s,
        "pointer" => "/lyric_to_scene_thinking/#{index}/director_chain/camera_route_spec",
        "route_spec" => spec
      }
    end
    ordered_unique(rows.reject { |row| row["section_id"].empty? })
  end

  def direction_front_planning_rows(direction)
    Array(direction["lyric_to_scene_thinking"]).each_with_index.each_with_object([]) do |(section, index), rows|
      next unless section.is_a?(Hash)

      transfer = section["front_planning_transfer"]
      consequence = transfer["02a_cut_keyframe_implication"] if transfer.is_a?(Hash)
      next if consequence.to_s.strip.empty?

      rows << {
        "section_id" => (section["section_or_beat_id"] || section["section_id"]).to_s,
        "pointer" => "/lyric_to_scene_thinking/#{index}/front_planning_transfer/02a_cut_keyframe_implication",
        "value" => consequence
      }
    end.reject { |row| row["section_id"].empty? }
  end

  def direction_storyline_section_rows(direction)
    rows = []
    [
      [Array(direction.dig("section_gate", "slices")), "/section_gate/slices"],
      [Array(direction["lyric_to_scene_thinking"]), "/lyric_to_scene_thinking"]
    ].each do |sections, pointer_root|
      sections.each_with_index do |section, index|
        next unless section.is_a?(Hash)

        projection = section["front_planning_storyline_section_projection"]
        next unless projection.is_a?(Hash) && projection["disposition"].to_s == "projected"

        lock = projection["section_lock"]
        next unless lock.is_a?(Hash)

        section_id = (section["section_id"] || section["section_or_beat_id"]).to_s
        rows << {
          "section_id" => section_id,
          "pointer" => "#{pointer_root}/#{index}/front_planning_storyline_section_projection/section_lock",
          "value" => lock,
          "projection" => projection,
          "source_kind" => pointer_root == "/section_gate/slices" ? "section_slice" : "lyric_anchor"
        }
      end
    end
    rows.reject { |row| row["section_id"].empty? }
  end

  def validate_storyline_section_projection(section_id, projection, expected_pointer, expected_lock, errors, label)
    unless projection.is_a?(Hash)
      errors << "#{section_id}: #{label} is required for the Founder-locked Front Planning storyline"
      return
    end
    unless projection["disposition"].to_s == "projected"
      errors << "#{section_id}: #{label}.disposition must be projected for the Founder-locked Front Planning storyline"
      return
    end
    unless projection["source_01_json_pointer"].to_s == expected_pointer
      errors << "#{section_id}: #{label}.source_01_json_pointer must bind the matching 01 storyline lock section"
    end
    unless projection["source_value_sha256"].to_s == structured_value_sha256(expected_lock)
      errors << "#{section_id}: #{label}.source_value_sha256 is stale"
    end
    unless projection["section_lock"] == expected_lock
      errors << "#{section_id}: #{label}.section_lock must exactly preserve the Founder-locked Front Planning section"
    end
  end

  def validate_front_planning_storyline_lock(direction_path, direction, root, errors)
    nucleus_ref = direction["source_nucleus"].to_s.strip
    direction_lock = direction.dig("story_distribution", "front_planning_storyline_lock_projection")
    return if nucleus_ref.empty? && !direction_lock.is_a?(Hash)

    nucleus_path = resolve_declared(nucleus_ref, direction_path, root)
    unless nucleus_path.file?
      errors << "source_nucleus is not readable for Front Planning storyline lock: #{nucleus_path}" unless nucleus_ref.empty?
      return
    end
    nucleus = load_document(nucleus_path)
    nucleus_lock = nucleus["front_planning_storyline_lock"]
    return unless nucleus_lock.is_a?(Hash)

    unless direction_lock.is_a?(Hash)
      errors << "story_distribution.front_planning_storyline_lock_projection is required because 00 promotes a Front Planning storyline lock"
      return
    end
    unless direction_lock["contract_version"].to_s == "front_planning_storyline_lock.v1"
      errors << "front_planning_storyline_lock_projection.contract_version must be front_planning_storyline_lock.v1"
    end
    declared_nucleus_path = resolve_declared(direction_lock["source_nucleus_path"], direction_path, root)
    errors << "front_planning_storyline_lock_projection.source_nucleus_path does not match source_nucleus" unless declared_nucleus_path == nucleus_path
    actual_nucleus_sha = Digest::SHA256.file(nucleus_path.to_s).hexdigest
    errors << "front_planning_storyline_lock_projection.source_nucleus_sha256 is stale" unless direction_lock["source_nucleus_sha256"].to_s == actual_nucleus_sha
    errors << "front_planning_storyline_lock_projection.source_01_json_pointer must be /front_planning_storyline_lock" unless direction_lock["source_01_json_pointer"].to_s == "/front_planning_storyline_lock"
    errors << "front_planning_storyline_lock_projection.source_value_sha256 is stale" unless direction_lock["source_value_sha256"].to_s == structured_value_sha256(nucleus_lock)
    %w[whole_film_storyline section_locks preservation_rule].each do |field|
      errors << "front_planning_storyline_lock_projection.#{field} must exactly preserve 00.front_planning_storyline_lock" unless direction_lock[field] == nucleus_lock[field]
    end

    source_front_path = resolve_declared(nucleus_lock["source_front_planning_path"], nucleus_path, root)
    unless source_front_path.file?
      errors << "00 front_planning_storyline_lock.source_front_planning_path is not readable: #{source_front_path}"
      return
    end
    actual_front_sha = Digest::SHA256.file(source_front_path.to_s).hexdigest
    errors << "00 front_planning_storyline_lock.source_front_planning_sha256 is stale" unless nucleus_lock["source_front_planning_sha256"].to_s == actual_front_sha
    front = load_document(source_front_path)
    source_lock = front["storyline_creative_lock"]
    unless source_lock.is_a?(Hash)
      errors << "00 front_planning_storyline_lock source has no storyline_creative_lock"
      return
    end
    errors << "00 front_planning_storyline_lock.source_value_sha256 is stale" unless nucleus_lock["source_value_sha256"].to_s == structured_value_sha256(source_lock)
    %w[whole_film_storyline section_locks preservation_rule].each do |field|
      errors << "00 front_planning_storyline_lock.#{field} must exactly preserve Front Planning" unless nucleus_lock[field] == source_lock[field]
    end

    expected_sections = Array(direction_lock["section_locks"])
    expected_ids = expected_sections.map { |row| row.is_a?(Hash) ? row["section_id"].to_s : "" }
    duplicates = expected_ids.group_by(&:itself).select { |id, rows| !id.empty? && rows.length > 1 }.keys
    errors.concat(duplicates.map { |id| "front_planning_storyline_lock_projection has duplicate section_id #{id}" })
    section_slices = Array(direction.dig("section_gate", "slices")).select { |row| row.is_a?(Hash) }
    expected_sections.each_with_index do |section_lock, index|
      next unless section_lock.is_a?(Hash)

      section_id = section_lock["section_id"].to_s
      expected_pointer = "/story_distribution/front_planning_storyline_lock_projection/section_locks/#{index}"
      matching_slices = section_slices.select { |slice| slice["section_id"].to_s == section_id }
      if matching_slices.empty?
        errors << "#{section_id}: 01 section_gate slice is required for every Founder-locked Front Planning storyline section"
      else
        matching_slices.each do |slice|
          validate_storyline_section_projection(section_id, slice["front_planning_storyline_section_projection"], expected_pointer, section_lock, errors, "section_gate.front_planning_storyline_section_projection")
        end
      end

      Array(direction["lyric_to_scene_thinking"]).select { |row| row.is_a?(Hash) && (row["section_or_beat_id"] || row["section_id"]).to_s == section_id }.each do |row|
        next unless row.key?("front_planning_storyline_section_projection")

        validate_storyline_section_projection(section_id, row["front_planning_storyline_section_projection"], expected_pointer, section_lock, errors, "lyric_to_scene_thinking.front_planning_storyline_section_projection")
      end
    end
  end

  def selected_alternative_camera_row(section, pointer_root)
    selected_route_id = section.dig("selected_director_route", "route_id").to_s
    return nil if selected_route_id.empty?

    index = Array(section["section_director_alternatives"]).index do |route|
      route.is_a?(Hash) && route["route_id"].to_s == selected_route_id
    end
    return nil unless index

    value = section.dig("section_director_alternatives", index, "camera_composition_route")
    return nil if value.to_s.strip.empty?

    {
      "pointer" => "#{pointer_root}/section_director_alternatives/#{index}/camera_composition_route",
      "value" => value
    }
  end

  def direction_camera_intent_rows(direction)
    rows = []
    Array(direction.dig("section_gate", "slices")).each_with_index do |section, index|
      next unless section.is_a?(Hash)

      section_id = (section["section_id"] || section["visual_section_id"]).to_s
      pointer_root = "/section_gate/slices/#{index}"
      candidates = [
        ["#{pointer_root}/camera_coverage_intent", section["camera_coverage_intent"]],
        ["#{pointer_root}/camera_route_spec/summary", section.dig("camera_route_spec", "summary")]
      ]
      selected = selected_alternative_camera_row(section, pointer_root)
      candidates << [selected["pointer"], selected["value"]] if selected
      candidates.each do |pointer, value|
        next if section_id.empty? || value.to_s.strip.empty?

        rows << {"section_id" => section_id, "pointer" => pointer, "value" => value}
      end
    end
    Array(direction["lyric_to_scene_thinking"]).each_with_index do |section, index|
      next unless section.is_a?(Hash)

      section_id = (section["section_or_beat_id"] || section["section_id"]).to_s
      pointer_root = "/lyric_to_scene_thinking/#{index}"
      candidates = [
        ["#{pointer_root}/director_chain/camera_coverage_intent", section.dig("director_chain", "camera_coverage_intent")],
        ["#{pointer_root}/director_chain/camera_route_spec/summary", section.dig("director_chain", "camera_route_spec", "summary")]
      ]
      selected = selected_alternative_camera_row(section, pointer_root)
      candidates << [selected["pointer"], selected["value"]] if selected
      candidates.each do |pointer, value|
        next if section_id.empty? || value.to_s.strip.empty?

        rows << {"section_id" => section_id, "pointer" => pointer, "value" => value}
      end
    end
    ordered_unique(rows)
  end

  def validate_cut_direction_projection(cut, field, label, source_rows, errors)
    cut_id = cut_identifier(cut)
    matching_rows = source_rows.select { |row| cut_sections(cut).include?(row["section_id"].to_s) }
    projection = cut[field]
    if projection.nil?
      errors << "#{cut_id}: #{field} dropped matching 01 #{label}" if matching_rows.any?
      return
    end
    unless projection.is_a?(Hash)
      errors << "#{cut_id}: #{field} must be a structured projection"
      return
    end

    disposition = projection["disposition"].to_s
    if disposition == "not_applicable"
      errors << "#{cut_id}: #{field} cannot be not_applicable while matching 01 #{label} exists" if matching_rows.any?
      return
    end
    unless disposition == "projected"
      errors << "#{cut_id}: #{field}.disposition must be projected or not_applicable"
      return
    end

    pointer = projection["source_01_json_pointer"].to_s
    source_row = matching_rows.find { |row| row["pointer"].to_s == pointer }
    unless source_row
      allowed = matching_rows.map { |row| row["pointer"] }
      errors << "#{cut_id}: #{field}.source_01_json_pointer is not a matching 01 #{label}: #{pointer}; allowed=#{allowed.join(',')}"
      return
    end
    expected = source_row["value"]
    unless projection["source_value_sha256"].to_s == structured_value_sha256(expected)
      errors << "#{cut_id}: #{field}.source_value_sha256 is stale"
    end
    unless projection["selected_consequence"] == expected
      errors << "#{cut_id}: #{field}.selected_consequence must exactly preserve the bound 01 #{label}"
    end
  end

  def validate_cut_storyline_projection(cut, source_rows, errors)
    cut_id = cut_identifier(cut)
    matching_rows = source_rows.select { |row| cut_sections(cut).include?(row["section_id"].to_s) && row["source_kind"] == "section_slice" }
    projection = cut["front_planning_storyline_projection"]
    if projection.nil?
      errors << "#{cut_id}: front_planning_storyline_projection dropped matching Founder-locked Front Planning section" if matching_rows.any?
      return
    end
    unless projection.is_a?(Hash)
      errors << "#{cut_id}: front_planning_storyline_projection must be a structured projection"
      return
    end
    if projection["disposition"].to_s == "not_applicable"
      errors << "#{cut_id}: front_planning_storyline_projection cannot be not_applicable while matching Founder-locked Front Planning section exists" if matching_rows.any?
      return
    end
    unless projection["disposition"].to_s == "projected"
      errors << "#{cut_id}: front_planning_storyline_projection.disposition must be projected or not_applicable"
      return
    end
    pointer = projection["source_01_json_pointer"].to_s
    source_row = matching_rows.find { |row| row["pointer"].to_s == pointer }
    unless source_row
      allowed = matching_rows.map { |row| row["pointer"] }
      errors << "#{cut_id}: front_planning_storyline_projection.source_01_json_pointer is not a matching 01 storyline section: #{pointer}; allowed=#{allowed.join(',')}"
      return
    end
    expected = source_row["value"]
    errors << "#{cut_id}: front_planning_storyline_projection.source_value_sha256 is stale" unless projection["source_value_sha256"].to_s == structured_value_sha256(expected)
    errors << "#{cut_id}: front_planning_storyline_projection.section_lock must exactly preserve the bound 01 Founder-locked storyline section" unless projection["section_lock"] == expected
  end

  def validate_album_visual_asset_use(storyboard_path, storyboard, root, errors)
    Array(storyboard["master_storyboard"]).each do |cut|
      next unless cut.is_a?(Hash)

      use = cut["album_visual_asset_use"]
      next unless use.is_a?(Hash) && use["disposition"].to_s == "selected"

      cut_id = cut_identifier(cut)
      readiness_path = resolve_declared(use["source_readiness_path"], storyboard_path, root)
      unless readiness_path.file?
        errors << "#{cut_id}: album_visual_asset_use.source_readiness_path is not readable: #{readiness_path}"
        next
      end
      run_root = storyboard_path.dirname.expand_path.cleanpath
      unless readiness_path.expand_path.cleanpath.to_s.start_with?("#{run_root}/")
        errors << "#{cut_id}: album_visual_asset_use source readiness must stay inside the owning run"
      end
      readiness_sha = Digest::SHA256.file(readiness_path.to_s).hexdigest
      unless use["source_readiness_sha256"].to_s == readiness_sha
        errors << "#{cut_id}: album_visual_asset_use.source_readiness_sha256 is stale"
      end
      readiness = load_document(readiness_path)
      if !readiness.dig("content", "content_id").to_s.empty? && readiness.dig("content", "content_id").to_s != storyboard["content_id"].to_s
        errors << "#{cut_id}: album_visual_asset_use readiness belongs to another content_id"
      end
      plan = readiness["album_visual_asset_plan"]
      unless plan.is_a?(Hash)
        errors << "#{cut_id}: album_visual_asset_use source readiness has no album_visual_asset_plan"
        next
      end

      expected_manifest_path = resolve_declared(plan["asset_manifest"], readiness_path, root)
      declared_manifest_path = resolve_declared(use["asset_manifest_path"], storyboard_path, root)
      unless declared_manifest_path == expected_manifest_path
        errors << "#{cut_id}: album_visual_asset_use.asset_manifest_path does not match front-planning readiness"
      end
      unless declared_manifest_path.file?
        errors << "#{cut_id}: album_visual_asset_use.asset_manifest_path is not readable: #{declared_manifest_path}"
        next
      end
      manifest_sha = Digest::SHA256.file(declared_manifest_path.to_s).hexdigest
      unless use["asset_manifest_sha256"].to_s == manifest_sha
        errors << "#{cut_id}: album_visual_asset_use.asset_manifest_sha256 is stale"
      end

      assets = Array(plan["assets"]).select { |row| row.is_a?(Hash) }
      assets_by_id = assets.to_h { |row| [row["asset_id"].to_s, row] }
      selected_ids = Array(use["asset_ids"]).map(&:to_s)
      (selected_ids - assets_by_id.keys).each do |asset_id|
        errors << "#{cut_id}: album_visual_asset_use selects unknown readiness asset #{asset_id}"
      end
      allowed_roles = selected_ids.flat_map { |asset_id| Array(assets_by_id.dig(asset_id, "allowed_uses")).map(&:to_s) }.uniq
      Array(use["selected_use_roles"]).map(&:to_s).each do |role|
        errors << "#{cut_id}: album_visual_asset_use role #{role} is not allowed by a selected asset" unless allowed_roles.include?(role)
      end
      next unless readiness["schema_version"].to_s == "front-planning-readiness.v6"

      section_ids = cut_sections(cut)
      assignments = Array(readiness.dig("reference_connection_contract", "section_assignments")).select do |assignment|
        assignment.is_a?(Hash) && section_ids.include?(assignment["section_id"].to_s)
      end
      assigned_sections = assignments.map { |assignment| assignment["section_id"].to_s }
      (section_ids - assigned_sections).each do |section_id|
        errors << "#{cut_id}: Front Planning v6 has no reference assignment for section #{section_id}"
      end
      assigned_ids = assignments.flat_map do |assignment|
        %w[
          album_member_identity_asset_ids
          album_visual_identity_asset_ids
          section_background_asset_ids
        ].flat_map { |field| Array(assignment[field]).map(&:to_s) }
      end.uniq
      (assigned_ids - selected_ids).each do |asset_id|
        errors << "#{cut_id}: album_visual_asset_use drops assigned Front Planning v6 asset #{asset_id}"
      end
      selected_roles = Array(use["selected_use_roles"]).map(&:to_s)
      identity_ids = assignments.flat_map { |assignment| Array(assignment["album_member_identity_asset_ids"]).map(&:to_s) }.uniq
      nonidentity_ids = assignments.flat_map do |assignment|
        Array(assignment["album_visual_identity_asset_ids"]).map(&:to_s) +
          Array(assignment["section_background_asset_ids"]).map(&:to_s)
      end.uniq
      if identity_ids.any? && !selected_roles.include?("02B_identity_reference_input")
        errors << "#{cut_id}: album_visual_asset_use omits the required 02B identity-reference role"
      end
      if nonidentity_ids.any? && !selected_roles.include?("02B_scene_reference_input")
        errors << "#{cut_id}: album_visual_asset_use omits the required 02B scene-reference role"
      end
    end
  rescue JSON::ParserError, Psych::SyntaxError => e
    errors << "album visual asset provenance cannot be parsed: #{e.message}"
  end

  def direction_camera_v2_active?(direction)
    direction.dig("story_distribution", "camera_directing_strategy", "contract_version").to_s == "camera_direction.v2" ||
      direction_camera_route_rows(direction).any?
  end

  def selected_camera_rows(storyboard)
    Array(storyboard["master_storyboard"]).map do |cut|
      next unless cut.is_a?(Hash)
      plan = cut["camera_coverage_plan"]
      if plan.is_a?(Hash)
        selected = Array(plan["candidate_routes"]).find do |row|
          row.is_a?(Hash) && row["route_id"].to_s == plan["selected_route_id"].to_s
        end
        next [cut_identifier(cut), cut_sections(cut), selected["source_01_route_ref"], selected["route_spec"]] if selected.is_a?(Hash) && selected["route_spec"].is_a?(Hash)
      end
      spec = cut.dig("director_chain", "camera_route_spec")
      [cut_identifier(cut), cut_sections(cut), cut.dig("director_chain", "camera_route_source_01_ref"), spec] if spec.is_a?(Hash)
    end.compact
  end

  def validate_exact_scene_references(storyboard_path, storyboard, root, errors)
    return unless storyboard["schema_version"].to_s == "1.5"

    cuts = Array(storyboard["master_storyboard"]).select { |cut| cut.is_a?(Hash) }
    cuts.each do |cut|
      cut_id = cut_identifier(cut)
      contract = cut["reference_contact_sheet_contract"]
      unless contract.is_a?(Hash)
        errors << "#{cut_id}: schema 1.5 requires reference_contact_sheet_contract"
        next
      end
      primary = contract["primary_exact_scene_reference"]
      unless primary.is_a?(Hash)
        errors << "#{cut_id}: schema 1.5 requires one primary_exact_scene_reference"
        next
      end

      global_look_ids = Array(contract["global_look_reference_ids"]).map(&:to_s)
      if global_look_ids.include?(primary["reference_id"].to_s) || global_look_ids.include?(primary["source_identity"].to_s)
        errors << "#{cut_id}: global LOOK cannot also be the cut primary exact-scene reference"
      end

      references = [primary] + Array(contract["secondary_exact_scene_references"]).select { |row| row.is_a?(Hash) }
      references.each_with_index do |reference, index|
        label = index.zero? ? "primary_exact_scene_reference" : "secondary_exact_scene_references[#{index - 1}]"
        declared_path = resolve_declared(reference["actual_path"], storyboard_path, root)
        if !declared_path.file?
          errors << "#{cut_id}: #{label}.actual_path is not readable: #{declared_path}"
        else
          actual_sha = Digest::SHA256.file(declared_path.to_s).hexdigest
          errors << "#{cut_id}: #{label}.sha256 is stale" unless reference["sha256"].to_s == actual_sha
        end
        if index.positive? && reference["secondary_reason"].to_s.strip.empty?
          errors << "#{cut_id}: #{label} requires secondary_reason"
        end

        direct_fields = Array(reference["direct_follow_fields"]).map(&:to_s)
        required_fields = if reference["application_mode"].to_s == "bounded_surface_direct"
                            %w[camera_geometry body_or_object_action expression_gaze crop_perspective]
                          else
                            %w[action_type body_route expression_gaze camera_geometry composition_depth sequence_order]
                          end
        missing_fields = required_fields - direct_fields
        unless missing_fields.empty?
          errors << "#{cut_id}: #{label} dropped direct-follow fields #{missing_fields.join(', ')}"
        end
      end

    end
  end

  def validate_storyboard(storyboard_path, storyboard, root:)
    errors = []
    cuts = Array(storyboard["master_storyboard"]).select { |cut| cut.is_a?(Hash) }
    validate_album_visual_asset_use(storyboard_path, storyboard, root, errors)
    validate_exact_scene_references(storyboard_path, storyboard, root, errors)
    application_carries = cuts.flat_map do |cut|
      Array(cut.dig("reference_direction_carry", "source_01_application_ids")).map(&:to_s)
    end.reject(&:empty?).uniq
    camera_rows = selected_camera_rows(storyboard)
    contract = storyboard["source_direction_contract"]

    declared_direction_path = nil
    declared_direction = {}
    declared_source = storyboard["source_direction_map"].to_s.strip
    unless declared_source.empty?
      declared_direction_path = resolve_declared(declared_source, storyboard_path, root)
      if declared_direction_path.file?
        declared_direction = load_document(declared_direction_path)
      else
        errors << "source_direction_map is not readable: #{declared_direction_path}"
      end
    end
    declared_research_active = declared_direction["research_synthesis"].is_a?(Hash)
    declared_camera_active = direction_camera_v2_active?(declared_direction)
    front_planning_rows = direction_front_planning_rows(declared_direction)
    storyline_rows = direction_storyline_section_rows(declared_direction)
    camera_intent_rows = direction_camera_intent_rows(declared_direction)
    explicit_planning_projection = cuts.any? do |cut|
      %w[front_planning_transfer_projection front_planning_storyline_projection camera_intent_projection].any? do |field|
        cut.dig(field, "disposition").to_s == "projected"
      end
    end
    # A legacy 01 commonly contains ordinary camera-coverage prose. That prose
    # alone must not retroactively opt an existing 02A artifact into the newer
    # hash-bound projection contract. Deep front-planning transfer, structured
    # camera v2, research synthesis, or an explicit downstream projection does.
    governed = declared_research_active || declared_camera_active || front_planning_rows.any? || storyline_rows.any? ||
      contract.is_a?(Hash) || application_carries.any? || camera_rows.any? || explicit_planning_projection
    return errors unless governed
    unless contract.is_a?(Hash)
      reasons = []
      reasons << "01 research_synthesis" if declared_research_active
      reasons << "01 camera_direction.v2" if declared_camera_active
      reasons << "01 front-planning transfer" if front_planning_rows.any?
      reasons << "01 Founder-locked Front Planning storyline" if storyline_rows.any?
      reasons << "02A research application carry" if application_carries.any?
      reasons << "02A structured camera route" if camera_rows.any?
      reasons << "02A planning projection" if explicit_planning_projection
      errors << "source_direction_contract is required because #{reasons.join(' and ')} activates the 01 -> 02 -> 02A projection"
      errors << "source_generation_contract is required for the active 01 -> 02 -> 02A projection" unless storyboard["source_generation_contract"].is_a?(Hash)
      return errors.uniq
    end

    direction_path = resolve_declared(contract["source_01_path"], storyboard_path, root)
    return ["source_direction_contract.source_01_path is not readable: #{direction_path}"] unless direction_path.file?
    if declared_direction_path&.file? && declared_direction_path.expand_path.cleanpath != direction_path.expand_path.cleanpath
      errors << "source_direction_contract.source_01_path does not match source_direction_map"
    end
    actual_sha = Digest::SHA256.file(direction_path.to_s).hexdigest
    errors << "source_direction_contract.source_01_sha256 is stale" unless contract["source_01_sha256"].to_s == actual_sha
    direction = load_document(direction_path)
    validate_front_planning_storyline_lock(direction_path, direction, root, errors)
    front_planning_rows = direction_front_planning_rows(direction)
    storyline_rows = direction_storyline_section_rows(direction)
    camera_intent_rows = direction_camera_intent_rows(direction)
    cuts.each do |cut|
      validate_cut_direction_projection(cut, "front_planning_transfer_projection", "front-planning transfer", front_planning_rows, errors)
      validate_cut_storyline_projection(cut, storyline_rows, errors)
      validate_cut_direction_projection(cut, "camera_intent_projection", "camera intent", camera_intent_rows, errors)
    end
    synthesis = direction["research_synthesis"]
    application_by_id = {}
    selected_applications = []
    if synthesis.is_a?(Hash)
      errors.concat(
        IdolReferenceInterpretationContract.validate_direction_bindings(
          direction_path,
          direction,
          root: root
        ).map { |error| "01 interpretation binding: #{error}" }
      )
      errors << "source_direction_contract.research_synthesis_id does not match 01" unless contract["research_synthesis_id"].to_s == synthesis["integration_id"].to_s
      selected_applications = Array(synthesis["selected_application_index"]).select { |row| row.is_a?(Hash) }
      application_by_id = selected_applications.each_with_object({}) do |row, result|
        application_id = row["application_id"].to_s
        result[application_id] = row unless application_id.empty?
      end
      selected_application_ids = application_by_id.keys
      (application_carries - selected_application_ids).each do |application_id|
        errors << "02A carries unknown or non-selected 01 application #{application_id}"
      end
      selected_applications.each do |application|
        application_id = application["application_id"].to_s
        %w[source_identities selected_function followed_surfaces current_song_consequence canonical_01_field_refs reject_guard].each do |field|
          value = application[field]
          missing = value.nil? || (value.respond_to?(:empty?) && value.empty?)
          errors << "01 application #{application_id} is missing canonical #{field}" if missing
        end
        Array(application["source_identities"]).each do |identity|
          errors << "01 application #{application_id} source_identity must be a human title, not a raw URL/path: #{identity}" if raw_source_identity?(identity)
        end
        Array(application["canonical_01_field_refs"]).each do |reference|
          errors << "01 application #{application_id} canonical field ref does not resolve: #{reference}" if pointer_value(direction, reference).nil?
        end
      end
    elsif application_carries.any?
      errors << "01 research_synthesis is missing for 02A reference_direction_carry"
    end

    generation_contract = storyboard["source_generation_contract"]
    unless generation_contract.is_a?(Hash)
      errors << "source_generation_contract is required for the active 01 -> 02 -> 02A projection"
    else
      generation_path = resolve_declared(generation_contract["source_02_path"], storyboard_path, root)
      declared_generation_path = nil
      declared_generation_source = storyboard["source_generation_map"].to_s.strip
      unless declared_generation_source.empty?
        declared_generation_path = resolve_declared(declared_generation_source, storyboard_path, root)
        errors << "source_generation_map is not readable: #{declared_generation_path}" unless declared_generation_path.file?
      end
      if !generation_path.file?
        errors << "source_generation_contract.source_02_path is not readable: #{generation_path}"
      else
        if declared_generation_path&.file? && declared_generation_path.expand_path.cleanpath != generation_path.expand_path.cleanpath
          errors << "source_generation_contract.source_02_path does not match source_generation_map"
        end
        generation_sha = Digest::SHA256.file(generation_path.to_s).hexdigest
        errors << "source_generation_contract.source_02_sha256 is stale" unless generation_contract["source_02_sha256"].to_s == generation_sha
        generation = load_document(generation_path)
        handoff = generation["direction_handoff_contract"]
        if !handoff.is_a?(Hash)
          errors << "bound 02 direction_handoff_contract is missing"
        else
          handoff_direction_path = resolve_declared(handoff["source_01_path"], generation_path, root)
          errors << "bound 02 source_01_path does not resolve to current 01" unless handoff_direction_path == direction_path
          errors << "bound 02 source_01_sha256 does not match 02A/current 01" unless handoff["source_01_sha256"].to_s == actual_sha && generation_contract["source_01_sha256"].to_s == actual_sha
          errors << "bound 02 research_synthesis_id does not match 02A/current 01" unless handoff["research_synthesis_id"].to_s == contract["research_synthesis_id"].to_s && generation_contract["research_synthesis_id"].to_s == contract["research_synthesis_id"].to_s
          errors << "bound 02 projection_mode must be selected_01_decisions_only" unless handoff["projection_mode"].to_s == "selected_01_decisions_only"
          errors << "source_generation_contract.projection_mode must be pointer_only_02_allocation" unless generation_contract["projection_mode"].to_s == "pointer_only_02_allocation"
          errors << "bound 02 must declare no_new_creative_decisions=true" unless handoff["no_new_creative_decisions"] == true
          section_routes = Array(handoff["section_routes"]).select { |row| row.is_a?(Hash) }
          active_section_ids = cuts.flat_map { |cut| cut_sections(cut) }.uniq
          direction_camera_routes = direction_camera_route_rows(direction)
          active_section_ids.each do |section_id|
            matching_routes = section_routes.select { |row| row["section_id"].to_s == section_id }
            expected_applications = selected_applications.select do |application|
              Array(application["target_section_ids"]).map(&:to_s).include?(section_id)
            end
            expected_application_ids = expected_applications.map { |application| application["application_id"].to_s }.reject(&:empty?).uniq
            allocated_application_ids = matching_routes.flat_map { |row| Array(row["reference_application_ids"]).map(&:to_s) }.uniq
            (expected_application_ids - allocated_application_ids).each do |application_id|
              errors << "bound 02 section #{section_id} dropped selected 01 application #{application_id}"
            end
            carried_application_ids = cuts.select { |cut| cut_sections(cut).include?(section_id) }.flat_map do |cut|
              Array(cut.dig("reference_direction_carry", "source_01_application_ids")).map(&:to_s)
            end.uniq
            (expected_application_ids - carried_application_ids).each do |application_id|
              errors << "02A section #{section_id} dropped selected 01 application #{application_id} from all cut carries"
            end

            expected_camera_routes = direction_camera_routes.select { |row| row["section_id"] == section_id }
            next if expected_camera_routes.empty?

            allocated_camera_refs = matching_routes.flat_map { |row| Array(row["camera_route_refs"]).map(&:to_s) }.uniq
            allocated_camera_specs = allocated_camera_refs.map { |reference| pointer_value(direction, reference) }.select { |value| camera_route_spec?(value) }
            expected_camera_routes.each do |route|
              unless allocated_camera_specs.include?(route["route_spec"])
                errors << "bound 02 section #{section_id} dropped structured 01 camera route #{route['route_spec']['route_id']}"
              end
            end

            section_camera_rows = camera_rows.select { |_cut_id, sections, _reference, _route_spec| sections.include?(section_id) }
            carried_camera_specs = section_camera_rows.map { |_cut_id, _sections, _reference, route_spec| route_spec }
            expected_camera_routes.each do |route|
              unless carried_camera_specs.include?(route["route_spec"])
                errors << "02A section #{section_id} dropped structured 01 camera route #{route['route_spec']['route_id']} from all cuts"
              end
            end
          end
          section_routes.each do |row|
            section_id = row["section_id"].to_s
            field_refs = Array(row["source_01_field_refs"]).map(&:to_s)
            Array(row["reference_application_ids"]).map(&:to_s).each do |application_id|
              application = application_by_id[application_id]
              if application.nil?
                errors << "bound 02 section #{section_id} allocates unknown 01 application #{application_id}"
                next
              end
              target_sections = Array(application["target_section_ids"]).map(&:to_s)
              unless target_sections.include?(section_id)
                errors << "bound 02 section #{section_id} allocates #{application_id}, which targets #{target_sections.join(',')}"
              end
              (Array(application["canonical_01_field_refs"]).map(&:to_s) - field_refs).each do |reference|
                errors << "bound 02 section #{section_id} omitted canonical 01 field ref #{reference} for #{application_id}"
              end
            end
            Array(row["camera_route_refs"]).map(&:to_s).each do |reference|
              resolved_camera = pointer_value(direction, reference)
              if resolved_camera.nil?
                errors << "bound 02 section #{section_id} camera route ref does not resolve in 01: #{reference}"
              elsif !camera_route_spec?(resolved_camera)
                errors << "bound 02 section #{section_id} camera route ref is not a camera_direction.v2 route: #{reference}"
              end
            end
          end
          cuts.each do |cut|
            carry = cut["reference_direction_carry"]
            next unless carry.is_a?(Hash)

            cut_id = cut["cut_id"].to_s
            sections = cut_sections(cut)
            errors << "#{cut_id}: reference_direction_carry requires source_sections" if sections.empty?
            matching_routes = section_routes.select { |row| sections.include?(row["section_id"].to_s) }
            errors << "#{cut_id}: bound 02 has no section route for #{sections.join(',')}" if matching_routes.empty?
            ids = Array(carry["source_01_application_ids"]).map(&:to_s)
            allocated = matching_routes.flat_map { |row| Array(row["reference_application_ids"]).map(&:to_s) }.uniq
            (ids - allocated).each do |application_id|
              errors << "#{cut_id}: application #{application_id} was not allocated by bound 02 for cut section #{sections.join(',')}"
            end
            source_field_refs = matching_routes.flat_map { |row| Array(row["source_01_field_refs"]).map(&:to_s) }.uniq
            ids.each do |application_id|
              application = application_by_id[application_id]
              next unless application

              target_sections = Array(application["target_section_ids"]).map(&:to_s)
              if (target_sections & sections).empty?
                errors << "#{cut_id}: application #{application_id} targets #{target_sections.join(',')} but cut belongs to #{sections.join(',')}"
              end
              missing_refs = Array(application["canonical_01_field_refs"]).map(&:to_s) - source_field_refs
              missing_refs.each do |reference|
                errors << "#{cut_id}: bound 02 section route did not allocate canonical 01 field ref #{reference} for #{application_id}"
              end
            end
            expected_carry = expected_reference_carry(application_by_id, ids)
            exact_scene_primary = cut.dig("reference_contact_sheet_contract", "primary_exact_scene_reference")
            if storyboard["schema_version"].to_s == "1.5" && exact_scene_primary.is_a?(Hash)
              errors << "#{cut_id}: schema 1.5 exact-scene carry must preserve the allocated 01 application ids" unless carry["source_01_application_ids"] == expected_carry["source_01_application_ids"]
              %w[source_identities selected_function followed_surfaces cut_consequence reject_guard].each do |field|
                value = carry[field]
                missing = value.nil? || (value.respond_to?(:empty?) && value.empty?)
                errors << "#{cut_id}: schema 1.5 exact-scene carry is missing #{field}" if missing
              end
            else
              errors << "#{cut_id}: reference_direction_carry differs from canonical 01 application projection" unless carry == expected_carry
            end
          end

          cuts.each do |cut|
            cut_id = cut_identifier(cut)
            sections = cut_sections(cut)
            matching_routes = section_routes.select { |row| sections.include?(row["section_id"].to_s) }
            allocated_field_pointers = matching_routes.flat_map do |row|
              Array(row["source_01_field_refs"]).map { |reference| pointer_part(reference) }
            end.uniq
            %w[front_planning_transfer_projection front_planning_storyline_projection camera_intent_projection].each do |field|
              projection = cut[field]
              next unless projection.is_a?(Hash) && projection["disposition"].to_s == "projected"

              source_pointer = projection["source_01_json_pointer"].to_s
              unless allocated_field_pointers.include?(source_pointer)
                errors << "#{cut_id}: #{field} source pointer was not allocated by bound 02 for cut section #{sections.join(',')}"
              end
            end
          end

          camera_rows.each do |cut_id, sections, reference, _route_spec|
            matching_routes = section_routes.select { |row| sections.include?(row["section_id"].to_s) }
            allocated_refs = matching_routes.flat_map { |row| Array(row["camera_route_refs"]).map(&:to_s) }.uniq
            errors << "#{cut_id}: camera route #{reference} was not allocated by bound 02 for cut section #{sections.join(',')}" unless allocated_refs.include?(reference.to_s)
          end
        end
      end
    end

    camera_rows.each do |cut_id, _sections, reference, route_spec|
      source_value = pointer_value(direction, reference)
      if source_value.nil?
        errors << "#{cut_id}: source_01_route_ref does not resolve in bound 01"
      elsif source_value != route_spec
        errors << "#{cut_id}: structured camera route differs from bound 01 source_01_route_ref"
      end
    end
    errors.uniq
  rescue JSON::ParserError, Psych::SyntaxError => e
    ["bound 01 direction cannot be parsed: #{e.message}"]
  end
end
