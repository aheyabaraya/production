# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module Idol02AStoryboardContract
  ACTIVE_SCHEMA_VERSION = "3.0"
  ACTIVE_COMPILER_VERSION = "1.6"
  ACTIVE_COMPILER_PROFILE = "provider_neutral_one_cut_one_image_translation_v2_6"
  LOCAL_LINEAGE_VERSION = "idol_02a_02b_local_lineage.v2"
  MEMBER_VISUAL_APPLICABILITY_VALUES = %w[
    meaningfully_visible
    visible_but_member_visual_unnecessary
    not_visible
  ].freeze
  GLOBAL_PROMPT_CONTEXT_FIELDS = %w[
    content_id
    output_intent
    target_message_summary
    whole_film_spine
    creative_role_harness
    branch_subject_mix_policy
    coverage_plan
  ].freeze
  # core_cut_ids is exact-cover transport scope. Core roster changes are captured by
  # each Core-Cut context and immediate same-section neighborhood, so including the
  # whole roster here would unnecessarily invalidate every packet in a section.
  SECTION_NONCREATIVE_FIELDS = %w[status path core_cut_ids].freeze
  BRANCH_CUT_FIELDS = %w[
    branch_cut_id
    parent_core_cut_id
    active_storyline_version_id
    screen_progression_node_id
    section_id
    parent_major_scene_id
    scene_phase_context
    order_within_core
    contribution_type
    directorial_or_edit_job
    primary_still_job_count
    packet_id
    branch_role
    branch_sequence
    core_event_derivation
    distinct_screen_contribution
    branch_time_relation
    visible_action
    composition_lock
    camera_treatment
    still_camera_spec
    shot_scale
    space_or_object
    required_visibility
    render_facing_action_cue
    continuity_in
    continuity_out
    visible_member_focus
    member_visual_compile_input
    visual_reference_bindings
    storyline_alignment_binding
    expected_output
    generation_status
  ].freeze
  KEYFRAME_SHOT_LOCK_FIELDS = %w[
    keyframe_shot_id
    packet_id
    shot_role
    shot_sequence
    visible_action
    composition_lock
    camera_treatment
    shot_scale
    space_or_object
    required_visibility
    render_facing_action_cue
    continuity_in
    continuity_out
  ].freeze
  KEYFRAME_SHOT_OPTIONAL_FIELDS = %w[
    identity_compile_input
    visible_member_focus
  ].freeze
  KEYFRAME_SHOT_ALLOWED_FIELDS = (KEYFRAME_SHOT_LOCK_FIELDS + KEYFRAME_SHOT_OPTIONAL_FIELDS).freeze

  module_function

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

  def keyframe_shot_lock_errors(label, value)
    return ["#{label} must be a structured 02A-authored child-shot lock"] unless value.is_a?(Hash)

    errors = []
    unexpected = value.keys.map(&:to_s) - KEYFRAME_SHOT_ALLOWED_FIELDS
    errors << "#{label} contains unsupported fields: #{unexpected.join(', ')}" unless unexpected.empty?
    KEYFRAME_SHOT_LOCK_FIELDS.each do |field|
      item = value[field]
      if field == "required_visibility"
        valid = item.is_a?(Array) && item.any? && item.map(&:to_s).all? { |text| !text.strip.empty? } && item.map(&:to_s).uniq.length == item.length
        errors << "#{label}.required_visibility must be a non-empty unique list" unless valid
      elsif field == "shot_sequence"
        errors << "#{label}.shot_sequence must be an integer >= 1" unless item.is_a?(Integer) && item >= 1
      elsif item.to_s.strip.empty?
        errors << "#{label}.#{field} is required"
      end
    end
    errors << "#{label}.keyframe_shot_id must match the active KS identifier contract" unless value["keyframe_shot_id"].to_s.match?(/\AKS[0-9A-Z_]{2,80}\z/)
    errors << "#{label}.packet_id must match the active packet identifier contract" unless value["packet_id"].to_s.match?(/\APKT_[BC][0-9]{2,}_[A-Z0-9_]+\z/)
    errors
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def member_visual_applicability(member_input, visible_members)
    declared = member_input["member_visual_applicability"].to_s
    return declared unless declared.empty?

    visible_members.empty? ? "not_visible" : "meaningfully_visible"
  end

  def member_visual_contract_errors(label, member_input, visible_members, selected_ids)
    applicability = member_visual_applicability(member_input, visible_members)
    policy = member_input["member_visual_reference_policy"].to_s
    errors = []

    unless MEMBER_VISUAL_APPLICABILITY_VALUES.include?(applicability)
      return ["#{label}.member_visual_applicability is invalid"]
    end

    case applicability
    when "meaningfully_visible"
      errors << "#{label} meaningfully-visible member requires visible_member_focus" if visible_members.empty?
      unless policy == "required" && selected_ids.any?
        errors << "#{label} meaningfully-visible member must require at least one current-title member visual"
      end
    when "visible_but_member_visual_unnecessary"
      errors << "#{label} visible-but-unnecessary member requires visible_member_focus" if visible_members.empty?
      unless policy == "prohibited" && selected_ids.empty?
        errors << "#{label} visible-but-unnecessary member must prohibit member visuals"
      end
    when "not_visible"
      errors << "#{label} not-visible member state requires empty visible_member_focus" unless visible_members.empty?
      unless policy == "prohibited" && selected_ids.empty?
        errors << "#{label} no-member Branch Cut must prohibit member visuals"
      end
    end
    errors
  end

  def inside_real_root?(path, owner_root)
    candidate = Pathname.new(path.to_s).realpath
    owner = Pathname.new(owner_root.to_s).realpath
    relative = candidate.relative_path_from(owner).to_s
    relative != ".." && !relative.start_with?("../")
  rescue ArgumentError, Errno::EACCES, Errno::ENOENT
    false
  end

  def admitted_visual_source_roots(root:, run_path:, album_key:, title_key:)
    repository = Pathname.new(root.to_s)
    [
      Pathname.new(run_path.to_s),
      repository.join("assets", "members", "album-assets", album_key.to_s, title_key.to_s),
      repository.join("source-materials")
    ]
  end

  def visual_source_admission_error(path:, root:, run_path:, album_key:, title_key:, label:)
    candidate = Pathname.new(path.to_s)
    return "#{label} is missing" unless candidate.file?

    roots = admitted_visual_source_roots(
      root: root,
      run_path: run_path,
      album_key: album_key,
      title_key: title_key
    )
    return nil if roots.any? { |owner| owner.directory? && inside_real_root?(candidate, owner) }

    relative = begin
      candidate.expand_path.relative_path_from(Pathname.new(root.to_s).expand_path).to_s
    rescue ArgumentError
      candidate.to_s
    end
    "#{label} is outside admitted current-run, current-title, or selected source-material roots: #{relative}"
  end

  def record_core_cut_id(record)
    record.is_a?(Hash) ? record["core_cut_id"].to_s : ""
  end

  def section_id_for_shard(shard)
    Array(shard.to_h["section_ids"]).first.to_s
  end

  def find_section_shard(document, section_id: nil, shard_id: nil)
    Array(document.to_h["section_shards"]).find do |row|
      next false unless row.is_a?(Hash)

      shard_matches = shard_id.to_s.empty? || row["shard_id"].to_s == shard_id.to_s
      section_matches = section_id.to_s.empty? || section_id_for_shard(row) == section_id.to_s
      shard_matches && section_matches
    end
  end

  def section_core_cuts(document, shard)
    cuts_by_id = Array(document.to_h["master_storyboard"]).select { |row| row.is_a?(Hash) }
      .to_h { |core_cut| [record_core_cut_id(core_cut), core_cut] }
    Array(shard.to_h["core_cut_ids"]).map { |core_cut_id| cuts_by_id[core_cut_id.to_s] }.compact
  end

  def global_prompt_context_projection(document)
    result = GLOBAL_PROMPT_CONTEXT_FIELDS.each_with_object({}) do |field, projection|
      projection[field] = deep_copy(document[field]) if document.key?(field)
    end
    whole_readout = document.dig(
      "founder_visual_alignment_projection",
      "projected_value",
      "whole_film_readout"
    )
    result["founder_visual_alignment_whole_film_readout"] = deep_copy(whole_readout) if whole_readout
    result
  end

  def section_assignment_projection(shard)
    shard.to_h.each_with_object({}) do |(key, value), result|
      next if SECTION_NONCREATIVE_FIELDS.include?(key.to_s)

      result[key.to_s] = deep_copy(value)
    end
  end

  def branch_cut_roster(core_cut)
    Array(core_cut.to_h.dig("compile_seed", "branch_cuts")).map do |branch_cut|
      next {} unless branch_cut.is_a?(Hash)

      {
        "branch_cut_id" => branch_cut["branch_cut_id"],
        "packet_id" => branch_cut["packet_id"],
        "branch_role" => branch_cut["branch_role"],
        "branch_sequence" => branch_cut["branch_sequence"],
        "distinct_screen_contribution" => branch_cut["distinct_screen_contribution"]
      }
    end
  end

  def core_cut_context_projection(core_cut)
    projection = deep_copy(core_cut.to_h)
    projection.delete("compile_seed")
    projection["branch_cut_roster"] = branch_cut_roster(core_cut)
    projection
  end

  def section_invariant_projection(document, shard)
    {
      "lineage_contract_version" => LOCAL_LINEAGE_VERSION,
      "global_prompt_context" => global_prompt_context_projection(document),
      "section_assignment" => section_assignment_projection(shard)
    }
  end

  def section_invariant_sha256(document, shard)
    value_sha256(section_invariant_projection(document, shard))
  end

  def boundary_sha256(shard, boundary)
    field = boundary.to_s == "entry" ? "transition_in" : "transition_out"
    value_sha256(
      "section_id" => section_id_for_shard(shard),
      "boundary" => boundary.to_s,
      "value" => shard.to_h[field]
    )
  end

  def section_review_projection(document, section_id)
    shard = find_section_shard(document, section_id: section_id)
    core_cuts = if shard
             section_core_cuts(document, shard)
           else
             Array(document.to_h["master_storyboard"]).select do |core_cut|
               core_cut.is_a?(Hash) && core_cut.dig("imported_core", "section_id").to_s == section_id.to_s
             end
           end
    {
      "lineage_contract_version" => LOCAL_LINEAGE_VERSION,
      "global_prompt_context" => global_prompt_context_projection(document),
      "section_id" => section_id.to_s,
      "section_assignment" => shard && section_assignment_projection(shard),
      "core_cuts" => deep_copy(core_cuts)
    }
  end

  def section_review_sha256(document, section_id)
    value_sha256(section_review_projection(document, section_id))
  end

  def same_section_context_payload(document, shard, selected_core_cuts, core_position, current_branch_cut, branch_position)
    current_core_cut = selected_core_cuts.fetch(core_position)
    branch_cuts = Array(current_core_cut.dig("compile_seed", "branch_cuts"))
    previous_branch_cut = branch_position.zero? ? nil : branch_cuts.fetch(branch_position - 1)
    next_branch_cut = branch_position == branch_cuts.length - 1 ? nil : branch_cuts.fetch(branch_position + 1)
    previous_core_cut = core_position.zero? ? nil : selected_core_cuts.fetch(core_position - 1)
    next_core_cut = core_position == selected_core_cuts.length - 1 ? nil : selected_core_cuts.fetch(core_position + 1)
    {
      "context_policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only",
      "whole_film_invariants" => global_prompt_context_projection(document),
      "section_assignment" => section_assignment_projection(shard),
      "previous_core_cut" => previous_core_cut && core_cut_context_projection(previous_core_cut),
      "parent_core_cut" => core_cut_context_projection(current_core_cut),
      "next_core_cut" => next_core_cut && core_cut_context_projection(next_core_cut),
      "previous_branch_cut" => previous_branch_cut && deep_copy(previous_branch_cut),
      "current_branch_cut" => deep_copy(current_branch_cut),
      "next_branch_cut" => next_branch_cut && deep_copy(next_branch_cut)
    }
  end

  def same_section_context_sha256(document, shard, selected_core_cuts, core_position, current_branch_cut, branch_position)
    value_sha256(
      same_section_context_payload(
        document,
        shard,
        selected_core_cuts,
        core_position,
        current_branch_cut,
        branch_position
      )
    )
  end

  def branch_cut_lock_errors(label, branch_cut)
    return ["#{label} must be an object"] unless branch_cut.is_a?(Hash)

    errors = []
    missing = BRANCH_CUT_FIELDS - branch_cut.keys.map(&:to_s)
    extra = branch_cut.keys.map(&:to_s) - BRANCH_CUT_FIELDS
    errors << "#{label} is missing fields: #{missing.join(', ')}" unless missing.empty?
    errors << "#{label} contains inactive fields: #{extra.join(', ')}" unless extra.empty?
    errors << "#{label}.branch_cut_id is invalid" unless branch_cut["branch_cut_id"].to_s.match?(/\ABC[0-9A-Z_]{2,80}\z/)
    errors << "#{label}.packet_id is invalid" unless branch_cut["packet_id"].to_s.match?(/\APKT_BC[0-9]{2,}_[A-Z0-9_]+\z/)
    unless branch_cut["branch_sequence"].is_a?(Integer) && branch_cut["branch_sequence"] >= 1
      errors << "#{label}.branch_sequence must be an integer >= 1"
    end
    %w[
      branch_role core_event_derivation distinct_screen_contribution branch_time_relation
      visible_action composition_lock camera_treatment shot_scale space_or_object
      render_facing_action_cue continuity_in continuity_out
    ].each do |field|
      errors << "#{label}.#{field} is required" if branch_cut[field].to_s.strip.empty?
    end
    required_visibility = Array(branch_cut["required_visibility"])
    errors << "#{label}.required_visibility must be non-empty and unique" if required_visibility.empty? || required_visibility.any? { |value| value.to_s.strip.empty? } || required_visibility.uniq.length != required_visibility.length

    member_input = branch_cut["member_visual_compile_input"]
    unless member_input.is_a?(Hash)
      errors << "#{label}.member_visual_compile_input must be an object"
      return errors
    end
    visible_members = Array(branch_cut["visible_member_focus"]).map(&:to_s)
    selected_ids = Array(member_input["selected_album_member_visual_asset_ids"]).map(&:to_s)
    errors.concat(member_visual_contract_errors(label, member_input, visible_members, selected_ids))

    bindings = Array(branch_cut["visual_reference_bindings"])
    errors << "#{label}.visual_reference_bindings requires at least one exact scene or Sequence reference" unless bindings.any? { |row| row.is_a?(Hash) && row["reference_scope"].to_s == "scene_visual" }
    orders = bindings.map { |row| row["order"] if row.is_a?(Hash) }.compact
    errors << "#{label}.visual_reference_bindings order must be contiguous from 1" unless orders == (1..bindings.length).to_a
    member_binding_ids = bindings.map do |row|
      row["asset_id"].to_s if row.is_a?(Hash) && row["reference_scope"].to_s == "member_visual"
    end.compact
    errors << "#{label} selected member assets must equal member bindings in order" unless member_binding_ids == selected_ids
    if member_visual_applicability(member_input, visible_members) == "meaningfully_visible" && member_binding_ids.empty?
      errors << "#{label} meaningfully visible member requires at least one passed current-title Member Visual binding"
    end
    first_scene_index = bindings.index { |row| row.is_a?(Hash) && row["reference_scope"].to_s == "scene_visual" }
    if first_scene_index && bindings.drop(first_scene_index + 1).any? { |row| row.is_a?(Hash) && row["reference_scope"].to_s == "member_visual" }
      errors << "#{label}.visual_reference_bindings must keep all Member Visual bindings before exact scene or Sequence bindings"
    end
    bindings.each_with_index do |binding, index|
      binding_label = "#{label}.visual_reference_bindings[#{index}]"
      unless binding.is_a?(Hash)
        errors << "#{binding_label} must be an object"
        next
      end
      errors << "#{binding_label}.actual_path may not use the face-only lane" if binding["actual_path"].to_s.match?(%r{(^|/)face-only-reference(?:-|\.|/)}i)
      errors << "#{binding_label}.sha256 is invalid" unless binding["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
      errors << "#{binding_label}.must_inspect_pixels must be true" unless binding["must_inspect_pixels"] == true
    end
    errors
  end

  def section_exact_cover_errors(document, require_shards: true)
    return ["02A schema_version must be #{ACTIVE_SCHEMA_VERSION}"] unless document.is_a?(Hash) && document["schema_version"].to_s == ACTIVE_SCHEMA_VERSION

    core_cuts = Array(document["master_storyboard"]).select { |row| row.is_a?(Hash) }
    shards = Array(document["section_shards"]).select { |row| row.is_a?(Hash) }
    return ["02A requires section_shards"] if require_shards && shards.empty?

    errors = []
    core_cut_ids = core_cuts.map { |core_cut| record_core_cut_id(core_cut) }
    if core_cut_ids.any?(&:empty?) || core_cut_ids.uniq.length != core_cut_ids.length
      errors << "02A Core-Cut ids must be non-empty and unique"
    end
    shard_core_cut_ids = shards.flat_map { |shard| Array(shard["core_cut_ids"]).map(&:to_s) }
    unless shard_core_cut_ids == core_cut_ids && shard_core_cut_ids.uniq.length == shard_core_cut_ids.length
      errors << "02A section shards must exact-cover Core Cuts once and in canonical order"
    end

    core_cuts_by_id = core_cuts.to_h { |core_cut| [record_core_cut_id(core_cut), core_cut] }
    shards.each do |shard|
      section_ids = Array(shard["section_ids"]).map(&:to_s)
      errors << "#{shard['shard_id']} must own exactly one section" unless section_ids.length == 1
      Array(shard["core_cut_ids"]).each do |core_cut_id|
        core_cut = core_cuts_by_id[core_cut_id.to_s]
        if core_cut.nil?
          errors << "#{shard['shard_id']} contains unknown Core Cut #{core_cut_id}"
          next
        end
        unless [core_cut.dig("imported_core", "section_id").to_s] == section_ids
          errors << "#{core_cut_id} section ownership differs from #{shard['shard_id']}"
        end
      end
    end
    errors
  end

  def active_compiled_packet?(packet)
    packet.is_a?(Hash) &&
      packet.dig("local_trace", "compiler_version").to_s == ACTIVE_COMPILER_VERSION &&
      packet.dig("local_trace", "compiler_profile").to_s == ACTIVE_COMPILER_PROFILE
  end

  def prompt_section_lineage_errors(source, prompt_document, prompt_shard)
    errors = []
    lineage = prompt_shard.to_h["local_lineage"]
    return ["#{prompt_shard.to_h['shard_id']}: local_lineage is required for local carry-forward"] unless lineage.is_a?(Hash)

    unless lineage["contract_version"].to_s == LOCAL_LINEAGE_VERSION
      errors << "#{prompt_shard['shard_id']}: local lineage contract is inactive"
    end
    section_id = prompt_shard["section_id"].to_s
    source_shard = find_section_shard(source, section_id: section_id, shard_id: prompt_shard["shard_id"])
    return errors << "#{prompt_shard['shard_id']}: source 02A shard is missing" unless source_shard

    unless Array(prompt_shard["core_cut_ids"]).map(&:to_s) == Array(source_shard["core_cut_ids"]).map(&:to_s)
      errors << "#{prompt_shard['shard_id']}: Core-Cut ids differ from current 02A"
    end
    expected_section_sha = section_invariant_sha256(source, source_shard)
    unless lineage["source_02a_section_invariants_sha256"].to_s == expected_section_sha
      errors << "#{prompt_shard['shard_id']}: section invariant hash is stale"
    end
    unless lineage["entry_boundary_sha256"].to_s == boundary_sha256(source_shard, "entry")
      errors << "#{prompt_shard['shard_id']}: entry boundary hash is stale"
    end
    unless lineage["exit_boundary_sha256"].to_s == boundary_sha256(source_shard, "exit")
      errors << "#{prompt_shard['shard_id']}: exit boundary hash is stale"
    end

    packets = Array(prompt_document.to_h["prompt_packets"]).select do |packet|
      packet.is_a?(Hash) && packet["execution_section_id"].to_s == section_id
    end
    packet_by_id = packets.to_h { |packet| [packet["packet_id"].to_s, packet] }
    states = Array(lineage["packet_states"])
    state_ids = states.map { |state| state.to_h["packet_id"].to_s }
    expected_packet_ids = Array(prompt_shard["packet_ids"]).map(&:to_s)
    errors << "#{prompt_shard['shard_id']}: packet lineage must exact-cover packet ids in order" unless state_ids == expected_packet_ids

    core_cuts = section_core_cuts(source, source_shard)
    expected_branches = core_cuts.each_with_index.flat_map do |core_cut, core_position|
      Array(core_cut.dig("compile_seed", "branch_cuts")).each_with_index.map do |branch_cut, branch_position|
        [core_cut, core_position, branch_cut, branch_position]
      end
    end
    expected_ids = expected_branches.map { |_core, _core_position, branch, _branch_position| branch.to_h["packet_id"].to_s }
    errors << "#{prompt_shard['shard_id']}: current 02A Branch-Cut coverage differs" unless expected_ids == expected_packet_ids

    state_by_id = states.to_h { |state| [state.to_h["packet_id"].to_s, state.to_h] }
    expected_branches.each do |core_cut, core_position, branch_cut, branch_position|
      packet_id = branch_cut.to_h["packet_id"].to_s
      packet = packet_by_id[packet_id]
      state = state_by_id[packet_id]
      next errors << "#{prompt_shard['shard_id']}: missing packet #{packet_id}" unless packet
      next errors << "#{prompt_shard['shard_id']}: missing lineage state for #{packet_id}" unless state

      errors << "#{packet_id}: packet lineage value hash is stale" unless state["packet_value_sha256"].to_s == value_sha256(packet)
      branch_sha = value_sha256(branch_cut)
      unless state["source_02a_branch_cut_value_sha256"].to_s == branch_sha
        errors << "#{packet_id}: current Branch-Cut hash differs from local lineage"
      end
      unless canonical_value(packet["branch_cut_lock"]) == canonical_value(branch_cut)
        errors << "#{packet_id}: Branch-Cut lock differs from current 02A"
      end
      unless packet["core_cut_id"].to_s == record_core_cut_id(core_cut)
        errors << "#{packet_id}: parent Core-Cut id differs from current 02A"
      end

      core_context_sha = value_sha256(core_cut_context_projection(core_cut))
      unless state["source_core_cut_context_value_sha256"].to_s == core_context_sha
        errors << "#{packet_id}: Core-Cut context hash is stale"
      end
      context_sha = same_section_context_sha256(
        source,
        source_shard,
        core_cuts,
        core_position,
        branch_cut,
        branch_position
      )
      unless state["source_same_section_context_sha256"].to_s == context_sha &&
             packet.dig("same_section_context", "context_value_sha256").to_s == context_sha
        errors << "#{packet_id}: same-section context lineage is stale"
      end
      unless packet.dig("local_trace", "source_branch_cut_value_sha256").to_s == branch_sha
        errors << "#{packet_id}: local Branch-Cut trace is stale"
      end
    end
    errors
  end

  def direct_branch_cut_packet_exactness_errors(document, packets)
    errors = section_exact_cover_errors(document, require_shards: true)
    return errors unless errors.empty?

    core_cuts = Array(document["master_storyboard"])
    expected = core_cuts.flat_map do |core_cut|
      Array(core_cut.dig("compile_seed", "branch_cuts")).map do |branch_cut|
        [record_core_cut_id(core_cut), branch_cut]
      end
    end
    actual = Array(packets)
    errors << "02B packets must all use the active compiler" unless actual.all? { |packet| active_compiled_packet?(packet) }
    expected_ids = expected.map { |_core_cut_id, branch_cut| branch_cut["packet_id"].to_s }
    actual_ids = actual.map { |packet| packet["packet_id"].to_s }
    errors << "02B packets must exact-cover all 02A Branch Cuts in order" unless actual_ids == expected_ids
    errors << "02B packet ids must be unique" unless actual_ids.uniq.length == actual_ids.length

    expected.each_with_index do |(core_cut_id, branch_cut), index|
      errors.concat(branch_cut_lock_errors("#{core_cut_id}.compile_seed.branch_cuts[#{index}]", branch_cut))
      packet = actual[index]
      next unless packet

      errors << "#{packet['packet_id']} core_cut_id differs from 02A" unless packet["core_cut_id"].to_s == core_cut_id
      errors << "#{packet['packet_id']} branch_cut_lock differs from 02A" unless packet["branch_cut_lock"] == branch_cut
      unless packet["branch_cut_id"].to_s == branch_cut["branch_cut_id"].to_s
        errors << "#{packet['packet_id']} branch_cut_id differs from 02A"
      end
    end
    errors
  end
end
