# frozen_string_literal: true

require "digest"
require "date"
require "json"
require "pathname"
require "yaml"

module IdolReferenceInterpretationContract
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze
  INTERPRETATION_BINDING_CONTRACT = "reference_interpretation_receipt.v1"
  REQUIRED_COMPONENT_ROLES = %w[source_observation evidence_locator selected_function].freeze
  SELECTED_SURFACE_SCOPES = %w[selected_sheet_cells selected_frame selected_crop selected_board_cells].freeze
  DERIVATIVE_REQUIRED_SCOPES = %w[selected_sheet_cells selected_board_cells].freeze
  DERIVATION_KINDS_BY_SCOPE = {
    "selected_sheet_cells" => "contact_sheet_cell_crop",
    "selected_board_cells" => "board_cell_crop"
  }.freeze
  MEDIA_KIND_TOKENS = %w[
    image video video_frame contact_sheet board crop generated_image other
    video_selected_range image_selected_crop
  ].freeze
  NONINITIAL_REOPEN_TRIGGERS = %w[
    source_bytes_changed
    selected_surface_changed_or_missing
    interpretation_incomplete_or_held
    selected_audio_materially_changes_function
    identity_safety_feasibility_conflict
    founder_explicit_reinterpretation
  ].freeze

  module_function

  def canonicalize(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, memo|
        raw_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        memo[key] = canonicalize(value[raw_key])
      end
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def canonical_digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def pointer_value(document, pointer)
    value = pointer.to_s
    value = value.delete_prefix("#")
    return document if value.empty?
    return nil unless value.start_with?("/")

    value.split("/").drop(1).reduce(document) do |memo, raw_token|
      token = raw_token.gsub("~1", "/").gsub("~0", "~")
      case memo
      when Hash
        break nil unless memo.key?(token)

        memo[token]
      when Array
        break nil unless token.match?(/\A(?:0|[1-9][0-9]*)\z/)

        memo[token.to_i]
      else
        break nil
      end
    end
  end

  def load_document(path)
    return {} unless path&.file?

    document = if path.extname.downcase == ".json"
                 JSON.parse(path.read)
               else
                 YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
               end
    document.is_a?(Hash) ? document : {}
  rescue JSON::ParserError, Psych::SyntaxError
    {}
  end

  def inside_root?(path, root)
    expanded = (path.exist? ? path.realpath : path.expand_path).to_s
    root_text = (root.exist? ? root.realpath : root.expand_path).to_s
    expanded == root_text || expanded.start_with?("#{root_text}#{File::SEPARATOR}")
  end

  def resolve_path(value, owner_path:, root:)
    raw = Pathname.new(value.to_s)
    return raw.cleanpath if raw.absolute?

    root_candidate = root.join(raw).cleanpath
    return root_candidate if root_candidate.exist?

    owner_path.dirname.join(raw).cleanpath
  end

  def source_refs_by_id(document)
    Array(document["source_refs"]).each_with_object({}) do |row, result|
      next unless row.is_a?(Hash)

      source_id = row["id"].to_s
      result[source_id] = row unless source_id.empty?
    end
  end

  def receipts_with_pointers(document)
    rows = []
    Array(document.dig("interpretation_contract", "reference_interpretation_index")).each_with_index do |receipt, index|
      rows << [receipt, "/interpretation_contract/reference_interpretation_index/#{index}"] if receipt.is_a?(Hash)
    end
    Array(document["reference_captures"]).each_with_index do |capture, index|
      next unless capture.is_a?(Hash) && capture["interpretation_receipt"].is_a?(Hash)

      rows << [capture["interpretation_receipt"], "/reference_captures/#{index}/interpretation_receipt"]
    end
    Array(document["fragments"]).each_with_index do |fragment, index|
      next unless fragment.is_a?(Hash) && fragment["interpretation_receipt"].is_a?(Hash)

      rows << [fragment["interpretation_receipt"], "/fragments/#{index}/interpretation_receipt"]
    end
    rows
  end

  def receipt_by_id(document, receipt_id)
    receipts_with_pointers(document).find do |receipt, _pointer|
      receipt["interpretation_id"].to_s == receipt_id.to_s
    end
  end

  def component_document(receipt, owner_document:, owner_path:, root:, errors:, label:)
    owner = receipt["component_owner"]
    unless owner.is_a?(Hash)
      errors << "#{label}.component_owner must be a mapping"
      return [nil, nil]
    end

    case owner["mode"].to_s
    when "self"
      [owner_document, owner_path]
    when "front_planning_source_ref"
      source_ref_id = owner["source_ref_id"].to_s
      source_ref = source_refs_by_id(owner_document)[source_ref_id]
      unless source_ref
        errors << "#{label}.component_owner references unknown source_ref_id #{source_ref_id}"
        return [nil, nil]
      end

      source_path = resolve_path(source_ref["path"], owner_path: owner_path, root: root)
      unless inside_root?(source_path, root) && source_path.file? && source_path.readable?
        errors << "#{label}.component_owner source is not a readable in-repository file: #{source_ref['path']}"
        return [nil, nil]
      end
      begin
        unless inside_root?(source_path.realpath, root)
          errors << "#{label}.component_owner source resolves outside the repository"
          return [nil, nil]
        end
      rescue SystemCallError
        errors << "#{label}.component_owner source realpath cannot be resolved"
        return [nil, nil]
      end
      actual_sha = Digest::SHA256.file(source_path.to_s).hexdigest
      unless owner["artifact_sha256"].to_s == actual_sha
        errors << "#{label}.component_owner artifact_sha256 is stale"
        return [nil, nil]
      end
      document = load_document(source_path)
      if document.empty?
        errors << "#{label}.component_owner source must be structured YAML or JSON"
        return [nil, nil]
      end
      [document, source_path]
    else
      errors << "#{label}.component_owner.mode must be self or front_planning_source_ref"
      [nil, nil]
    end
  end

  def validate_receipt(receipt, owner_document:, owner_path:, root:, label: "interpretation_receipt")
    errors = []
    unless receipt.is_a?(Hash)
      return ["#{label} must be a mapping"]
    end

    receipt_id = receipt["interpretation_id"].to_s
    errors << "#{label}.interpretation_id is missing" if receipt_id.empty?
    errors << "#{label}.consume_mode must forbid source rereading" unless receipt["consume_mode"].to_s == "consume_bound_interpretation_without_source_reread"

    component_doc, component_path = component_document(
      receipt,
      owner_document: owner_document,
      owner_path: owner_path,
      root: root,
      errors: errors,
      label: label
    )
    component_roles = []
    if component_doc
      Array(receipt["components"]).each_with_index do |component, index|
        component_label = "#{label}.components[#{index}]"
        unless component.is_a?(Hash)
          errors << "#{component_label} must be a mapping"
          next
        end
        role = component["role"].to_s
        component_roles << role unless role.empty?
        pointer = component["json_pointer"].to_s
        value = pointer_value(component_doc, pointer)
        if value.nil?
          errors << "#{component_label}.json_pointer does not resolve in #{component_path}"
          next
        end
        expected_digest = canonical_digest(value)
        errors << "#{component_label}.value_sha256 is stale" unless component["value_sha256"].to_s == expected_digest
        if role == "selected_function"
          if !value.is_a?(String)
            errors << "#{component_label} selected_function must resolve to one exact string"
          elsif MEDIA_KIND_TOKENS.include?(value.strip.downcase)
            errors << "#{component_label} selected_function must name a screen function, not a media kind"
          end
        end
      end
    end
    (REQUIRED_COMPONENT_ROLES - component_roles).each do |role|
      errors << "#{label}.components is missing required role #{role}"
    end

    Array(receipt["inspected_sources"]).each_with_index do |source, index|
      source_label = "#{label}.inspected_sources[#{index}]"
      unless source.is_a?(Hash)
        errors << "#{source_label} must be a mapping"
        next
      end
      inspected_path = resolve_path(source["path"], owner_path: owner_path, root: root)
      unless inside_root?(inspected_path, root) && inspected_path.file? && inspected_path.readable?
        errors << "#{source_label}.path is not a readable in-repository file"
        next
      end
      begin
        errors << "#{source_label}.path resolves outside the repository" unless inside_root?(inspected_path.realpath, root)
      rescue SystemCallError
        errors << "#{source_label}.path realpath cannot be resolved"
      end
      actual_sha = Digest::SHA256.file(inspected_path.to_s).hexdigest
      errors << "#{source_label}.sha256 is stale" unless source["sha256"].to_s == actual_sha
      if SELECTED_SURFACE_SCOPES.include?(source["inspection_scope"].to_s) && Array(source["selected_cells_or_frames"]).empty?
        errors << "#{source_label}.selected_cells_or_frames is required for targeted sheet/frame/crop inspection"
      end

      derivative_required = source["media_kind"].to_s == "contact_sheet" ||
                            DERIVATIVE_REQUIRED_SCOPES.include?(source["inspection_scope"].to_s)
      selected_ids = Array(source["selected_cells_or_frames"]).map(&:to_s).reject(&:empty?).uniq
      derivatives = Array(source["selected_surface_artifacts"])
      if derivative_required && derivatives.empty?
        errors << "#{source_label}.selected_surface_artifacts must carry each selected sheet/board cell as its own path and hash"
      end
      derivative_ids = []
      derivatives.each_with_index do |derivative, derivative_index|
        derivative_label = "#{source_label}.selected_surface_artifacts[#{derivative_index}]"
        unless derivative.is_a?(Hash)
          errors << "#{derivative_label} must be a mapping"
          next
        end
        surface_id = derivative["surface_id"].to_s
        derivative_ids << surface_id unless surface_id.empty?
        errors << "#{derivative_label}.surface_id is missing" if surface_id.empty?
        derivative_path = resolve_path(derivative["path"], owner_path: owner_path, root: root)
        unless inside_root?(derivative_path, root) && derivative_path.file? && derivative_path.readable?
          errors << "#{derivative_label}.path is not a readable in-repository selected derivative"
          next
        end
        begin
          errors << "#{derivative_label}.path resolves outside the repository" unless inside_root?(derivative_path.realpath, root)
          if derivative_required && inspected_path.file? && derivative_path.realpath == inspected_path.realpath
            errors << "#{derivative_label}.path must be a selected derivative, not the whole sheet/board source"
          end
        rescue SystemCallError
          errors << "#{derivative_label}.path realpath cannot be resolved"
        end
        derivative_sha = Digest::SHA256.file(derivative_path.to_s).hexdigest
        errors << "#{derivative_label}.sha256 is stale" unless derivative["sha256"].to_s == derivative_sha
        next unless derivative_required

        source_path = resolve_path(derivative["source_path"], owner_path: owner_path, root: root)
        unless inside_root?(source_path, root) && source_path.file? && source_path.readable?
          errors << "#{derivative_label}.source_path must be the readable inspected source"
          next
        end
        begin
          errors << "#{derivative_label}.source_path must match the inspected source" unless source_path.realpath == inspected_path.realpath
        rescue SystemCallError
          errors << "#{derivative_label}.source_path realpath cannot be resolved"
        end
        errors << "#{derivative_label}.source_sha256 must match the inspected source" unless derivative["source_sha256"].to_s == actual_sha

        expected_kind = DERIVATION_KINDS_BY_SCOPE.fetch(source["inspection_scope"].to_s, "contact_sheet_cell_crop")
        errors << "#{derivative_label}.derivation_kind must be #{expected_kind}" unless derivative["derivation_kind"].to_s == expected_kind
      end
      if derivative_required && derivative_ids.sort != selected_ids.sort
        errors << "#{source_label}.selected_surface_artifacts surface_ids must exactly match selected_cells_or_frames"
      end
      if derivative_ids.length != derivative_ids.uniq.length
        errors << "#{source_label}.selected_surface_artifacts contains duplicate surface_id values"
      end
    end

    revision = receipt["revision"]
    unless revision.is_a?(Hash)
      errors << "#{label}.revision must be a mapping"
      return errors
    end
    number = revision["number"].to_i
    trigger = revision["reopen_trigger"].to_s
    previous = revision["previous_receipt_sha256"]
    invalidates = revision["invalidates_from_stage"].to_s
    if number == 1
      errors << "#{label}.revision 1 must use initial_analysis" unless trigger == "initial_analysis"
      errors << "#{label}.revision 1 must not declare a previous receipt" unless previous.nil?
      errors << "#{label}.revision 1 must not invalidate downstream" unless invalidates == "none"
    elsif number >= 2
      errors << "#{label}.revision #{number} has an unapproved reopen trigger" unless NONINITIAL_REOPEN_TRIGGERS.include?(trigger)
      errors << "#{label}.revision #{number} requires previous_receipt_sha256" unless previous.to_s.match?(SHA256_PATTERN)
      errors << "#{label}.revision #{number} must invalidate affected downstream" if invalidates.empty? || invalidates == "none"
      errors << "#{label}.revision #{number} requires a concrete reason" if revision["reason"].to_s.strip.empty?
    else
      errors << "#{label}.revision.number must be at least 1"
    end

    errors
  end

  def validate_owner_document(owner_path, document, root:)
    errors = []
    seen = {}
    receipts_with_pointers(document).each do |receipt, pointer|
      receipt_id = receipt["interpretation_id"].to_s
      if seen.key?(receipt_id)
        errors << "duplicate interpretation_id #{receipt_id} at #{pointer} and #{seen[receipt_id]}"
      else
        seen[receipt_id] = pointer
      end
      errors.concat(validate_receipt(receipt, owner_document: document, owner_path: owner_path, root: root, label: pointer))
    end

    captures = Array(document["reference_captures"])
    selected_capture_refs = Array(document.dig("selection_output", "selected_application_refs")).map do |value|
      value.to_s.split("#", 2).first
    end.reject(&:empty?).uniq
    selected_capture_indexes = []
    captures.each_with_index do |capture, index|
      next unless capture.is_a?(Hash)

      selected = capture["capture_status"].to_s == "selected_for_01" || selected_capture_refs.include?(capture["reference_id"].to_s)
      next unless selected

      selected_capture_indexes << index
      next if capture["interpretation_receipt"].is_a?(Hash)

      errors << "/reference_captures/#{index} selected_for_01 requires interpretation_receipt before 01 handoff"
    end
    if %w[approved_for_01 adapted_to_01 codex_applied_for_02a_review].include?(document["status"].to_s) && selected_capture_indexes.empty?
      errors << "ready 01R must identify at least one selected capture and bind its interpretation_receipt"
    end

    if document["schema_version"].to_s == "idol_reference_fragment_crop_lock.v2"
      ready_fragment_ids = Array(document["section_fragment_map"]).each_with_object([]) do |row, ids|
        next unless row.is_a?(Hash) && %w[ready_for_01 adapted_to_01].include?(row["status"].to_s)

        ids.concat(Array(row["fragment_ids"]).map(&:to_s))
      end.uniq
      Array(document["fragments"]).each_with_index do |fragment, index|
        next unless fragment.is_a?(Hash)

        required = fragment["status"].to_s == "selected" || ready_fragment_ids.include?(fragment["fragment_id"].to_s)
        next unless required && !fragment["interpretation_receipt"].is_a?(Hash)

        errors << "/fragments/#{index} selected/ready v2 fragment requires interpretation_receipt before 01 handoff"
      end
      if %w[ready_for_01 adapted_to_01].include?(document["status"].to_s) &&
         Array(document["fragments"]).none? { |fragment| fragment.is_a?(Hash) && (fragment["status"].to_s == "selected" || ready_fragment_ids.include?(fragment["fragment_id"].to_s)) }
        errors << "ready 01R-C v2 must identify at least one selected fragment and bind its interpretation_receipt"
      end
    end
    errors
  end

  def direction_contract_advertised?(synthesis, sources_by_id:, direction_path:, root:)
    return true if synthesis["interpretation_binding_contract"].to_s == INTERPRETATION_BINDING_CONTRACT

    sources_by_id.values.any? do |source|
      source_path = resolve_source_artifact(source, direction_path: direction_path, root: root)
      next false unless inside_root?(source_path, root) && source_path.file? && source_path.readable?
      next false unless source["artifact_sha256"].to_s == Digest::SHA256.file(source_path.to_s).hexdigest

      receipts_with_pointers(load_document(source_path)).any?
    end
  end

  def resolve_source_artifact(row, direction_path:, root:)
    resolve_path(row["path"], owner_path: direction_path, root: root)
  end

  def resolved_receipt_for_binding(binding, sources_by_id:, direction_path:, root:, errors:, label:)
    source_id = binding["source_id"].to_s
    source = sources_by_id[source_id]
    unless source
      errors << "#{label}.source_id references unknown 01 source artifact #{source_id}"
      return nil
    end
    source_path = resolve_source_artifact(source, direction_path: direction_path, root: root)
    unless inside_root?(source_path, root) && source_path.file? && source_path.readable?
      errors << "#{label} source artifact is not readable: #{source['path']}"
      return nil
    end
    actual_source_sha = Digest::SHA256.file(source_path.to_s).hexdigest
    unless source["artifact_sha256"].to_s == actual_source_sha
      errors << "#{label} source artifact_sha256 is stale"
      return nil
    end
    source_document = load_document(source_path)
    receipt_pointer = binding["source_receipt_json_pointer"].to_s
    receipt = pointer_value(source_document, receipt_pointer)
    unless receipt.is_a?(Hash)
      errors << "#{label}.source_receipt_json_pointer does not resolve to an interpretation receipt"
      return nil
    end
    receipt_digest = canonical_digest(receipt)
    errors << "#{label}.source_receipt_sha256 is stale" unless binding["source_receipt_sha256"].to_s == receipt_digest
    errors << "#{label}.receipt_id does not match its source receipt" unless binding["receipt_id"].to_s == receipt["interpretation_id"].to_s
    errors << "#{label}.source_revision does not match its source receipt" unless binding["source_revision"].to_i == receipt.dig("revision", "number").to_i
    errors << "#{label}.consume_mode does not match its source receipt" unless binding["consume_mode"].to_s == receipt["consume_mode"].to_s
    errors.concat(validate_receipt(receipt, owner_document: source_document, owner_path: source_path, root: root, label: "#{label}.source_receipt"))
    {
      "receipt" => receipt,
      "source" => source,
      "source_path" => source_path,
      "source_document" => source_document
    }
  end

  def resolved_components(receipt, owner_document:, owner_path:, root:)
    errors = []
    component_doc, = component_document(
      receipt,
      owner_document: owner_document,
      owner_path: owner_path,
      root: root,
      errors: errors,
      label: receipt["interpretation_id"].to_s
    )
    return [{}, errors] unless component_doc

    values = Array(receipt["components"]).each_with_object({}) do |component, result|
      next unless component.is_a?(Hash)

      result[component["role"].to_s] = pointer_value(component_doc, component["json_pointer"])
    end
    [values, errors]
  end

  def validate_direction_bindings(direction_path, direction, root:)
    synthesis = direction["research_synthesis"]
    return [] unless synthesis.is_a?(Hash)

    errors = []
    sources_by_id = Array(synthesis["source_artifacts"]).each_with_object({}) do |source, result|
      next unless source.is_a?(Hash)

      source_id = source["source_id"].to_s
      result[source_id] = source unless source_id.empty?
    end
    contract_advertised = direction_contract_advertised?(
      synthesis,
      sources_by_id: sources_by_id,
      direction_path: direction_path,
      root: root
    )
    Array(synthesis["selected_application_index"]).each_with_index do |application, application_index|
      next unless application.is_a?(Hash)

      app_id = application["application_id"].to_s
      bindings = Array(application["interpretation_bindings"])
      if bindings.empty?
        errors << "01 application #{app_id} is missing interpretation_bindings under #{INTERPRETATION_BINDING_CONTRACT}" if contract_advertised
        next
      end
      resolved = bindings.each_with_index.each_with_object([]) do |(binding, binding_index), rows|
        unless binding.is_a?(Hash)
          errors << "01 application #{app_id} interpretation_bindings[#{binding_index}] must be a mapping"
          next
        end
        item = resolved_receipt_for_binding(
          binding,
          sources_by_id: sources_by_id,
          direction_path: direction_path,
          root: root,
          errors: errors,
          label: "01 application #{app_id} interpretation_bindings[#{binding_index}]"
        )
        rows << item.merge("binding" => binding) if item
      end
      receipt_counts = resolved.each_with_object(Hash.new(0)) do |item, counts|
        counts[item.dig("receipt", "interpretation_id").to_s] += 1
      end
      duplicates = receipt_counts.select { |_id, count| count > 1 }.keys
      duplicates.each { |id| errors << "01 application #{app_id} binds interpretation receipt #{id} more than once" }

      app_targets = Array(application["target_section_ids"]).map(&:to_s)
      resolved.each do |item|
        receipt = item["receipt"]
        receipt_targets = Array(receipt["target_section_ids"]).map(&:to_s)
        if receipt_targets.any? && (app_targets & receipt_targets).empty?
          errors << "01 application #{app_id} does not overlap interpretation #{receipt['interpretation_id']} target sections"
        end
        unless %w[applied combined].include?(receipt["disposition"].to_s)
          errors << "01 application #{app_id} consumes #{receipt['disposition']} interpretation #{receipt['interpretation_id']}"
        end
        components, component_errors = resolved_components(
          receipt,
          owner_document: item["source_document"],
          owner_path: item["source_path"],
          root: root
        )
        errors.concat(component_errors.map { |error| "01 application #{app_id}: #{error}" })
        binding = item["binding"]
        case binding["binding_mode"].to_s
        when "exact"
          unless components["selected_function"].to_s == application["selected_function"].to_s
            errors << "01 application #{app_id} selected_function reinterprets its exact bound receipt"
          end
        when "combined_in_01"
          if binding["reason"].to_s.strip.empty?
            errors << "01 application #{app_id} combined binding requires reason"
          end
        else
          errors << "01 application #{app_id} has unknown interpretation binding_mode"
        end
      end
      if bindings.any? { |binding| binding.is_a?(Hash) && binding["binding_mode"].to_s == "combined_in_01" } && bindings.length < 2
        only_receipt = resolved.first&.dig("receipt")
        errors << "01 application #{app_id} combined_in_01 requires multiple receipts or one upstream combined receipt" unless only_receipt&.dig("disposition").to_s == "combined"
      end
      errors << "01 application index #{application_index} has no resolved interpretation receipt" if resolved.empty?
    end
    errors
  end

  def resolved_direction_interpretations(direction_path, direction, root:)
    synthesis = direction["research_synthesis"]
    return [[], []] unless synthesis.is_a?(Hash)

    errors = []
    sources_by_id = Array(synthesis["source_artifacts"]).each_with_object({}) do |source, result|
      result[source["source_id"].to_s] = source if source.is_a?(Hash)
    end
    rows = []
    Array(synthesis["selected_application_index"]).each do |application|
      next unless application.is_a?(Hash)

      Array(application["interpretation_bindings"]).each_with_index do |binding, index|
        next unless binding.is_a?(Hash)

        resolved = resolved_receipt_for_binding(
          binding,
          sources_by_id: sources_by_id,
          direction_path: direction_path,
          root: root,
          errors: errors,
          label: "#{application['application_id']}.interpretation_bindings[#{index}]"
        )
        next unless resolved

        components, component_errors = resolved_components(
          resolved["receipt"],
          owner_document: resolved["source_document"],
          owner_path: resolved["source_path"],
          root: root
        )
        errors.concat(component_errors)
        rows << {
          "interpretation_id" => resolved["receipt"]["interpretation_id"],
          "source_application_id" => application["application_id"],
          "source_id" => binding["source_id"],
          "source_artifact_path" => resolved["source"]["path"],
          "source_receipt_json_pointer" => binding["source_receipt_json_pointer"],
          "source_receipt_sha256" => binding["source_receipt_sha256"],
          "source_revision" => binding["source_revision"],
          "binding_mode" => binding["binding_mode"],
          "source_identities" => Array(application["source_identities"]),
          "target_section_ids" => Array(application["target_section_ids"]),
          "disposition" => resolved["receipt"]["disposition"],
          "components" => components,
          "inspected_sources" => Array(resolved["receipt"]["inspected_sources"]),
          "consume_mode" => resolved["receipt"]["consume_mode"],
          "inspection_action" => "consume_bound_interpretation"
        }
      end
    end
    [rows.uniq { |row| [row["source_application_id"], row["interpretation_id"]] }, errors.uniq]
  end

  def resolved_owner_interpretations(owner_path, document, root:)
    errors = validate_owner_document(owner_path, document, root: root)
    rows = receipts_with_pointers(document).map do |receipt, pointer|
      components, component_errors = resolved_components(
        receipt,
        owner_document: document,
        owner_path: owner_path,
        root: root
      )
      errors.concat(component_errors)
      {
        "interpretation_id" => receipt["interpretation_id"],
        "source_application_id" => nil,
        "source_id" => nil,
        "source_artifact_path" => begin
          owner_path.relative_path_from(root).to_s
        rescue ArgumentError
          owner_path.to_s
        end,
        "source_receipt_json_pointer" => pointer,
        "source_receipt_sha256" => canonical_digest(receipt),
        "source_revision" => receipt.dig("revision", "number"),
        "binding_mode" => "upstream_owner_receipt",
        "source_identities" => [],
        "target_section_ids" => Array(receipt["target_section_ids"]),
        "disposition" => receipt["disposition"],
        "components" => components,
        "inspected_sources" => Array(receipt["inspected_sources"]),
        "consume_mode" => receipt["consume_mode"],
        "inspection_action" => "consume_bound_interpretation"
      }
    end
    [rows, errors.uniq]
  end
end
