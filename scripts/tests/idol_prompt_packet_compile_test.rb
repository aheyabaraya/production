# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_mv_fixture"

class IdolPromptPacketCompileTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_prompt_packet_compile.rb")

  def setup
    @fixture = ActiveMvFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def test_active_v3_storyboard_and_v7_context_review_compile
    result = run_compiler("--verify-only")

    assert result[:status].success?, result[:stderr]
    payload = JSON.parse(result[:stdout])
    assert_equal "1.6", payload.fetch("compiler_version")
    assert_equal "S01", payload.fetch("section_id")
    assert_equal 2, payload.fetch("core_cut_count")
    assert_equal 3, payload.fetch("packet_count")
    assert_equal 3, payload.fetch("five_line_prompt_count")
    assert_equal "3.0", @fixture.storyboard.fetch("schema_version")
    assert_equal "idol-02a-creative-context-review.v7",
                 YAML.safe_load(@fixture.context_review_path.read, aliases: true).fetch("schema_version")
  end

  def test_compiled_packets_are_provider_neutral_one_cut_one_image_v2_6
    output = @fixture.run_dir.join("02B-section-S01.yaml")
    result = run_compiler("--output", output.to_s)

    assert result[:status].success?, result[:stderr]
    document = YAML.safe_load(output.read, aliases: true)
    assert_equal "2.6", document.fetch("schema_version")
    assert_equal 3, document.fetch("prompt_packets").length
    document.fetch("prompt_packets").each do |packet|
      assert_equal "official_branch", packet.fetch("mode")
      assert_equal "branch", packet.dig("cut_pointer", "cut_type")
      assert_equal packet.fetch("branch_cut_id"), packet.dig("cut_pointer", "cut_id")
      assert_equal 5, packet.dig("compiled_prompt_block", "full_prompt_text").lines.length
      assert_includes packet.dig("compiled_prompt_block", "full_prompt_text"),
                      "4K, high quality, high detail"
      assert_equal 1, packet.dig("execution", "output_count")
      assert_equal "C1", packet.fetch("section_cohort_id")
      assert_equal %w[character_visual scene_visual_package motion_reference],
                   packet.fetch("reference_role_plan").fetch("logical_role_groups").map { |row| row.fetch("logical_role") }
    end
  end

  def test_compiler_reaches_imported_official_core_section_context
    output = @fixture.run_dir.join("02B-section-S01-core-lineage.yaml")
    result = run_compiler("--output", output.to_s)

    assert result[:status].success?, result[:stderr]
    packets = YAML.safe_load(output.read, aliases: true).fetch("prompt_packets")
    assert_equal %w[C01 C01 C02], packets.map { |packet| packet.fetch("core_cut_id") }
    assert packets.all? { |packet| packet.fetch("execution_section_id") == "S01" }
  end

  def test_fp_hero_core_compiles_through_the_same_five_line_profile
    delta = generic_delta("fp_hero_core")
    @fixture.delta_path.write(YAML.dump(delta))
    output = @fixture.run_dir.join("FP-hero-core-packets.yaml")

    result = run_compiler("--output", output.to_s)

    assert result[:status].success?, result[:stderr]
    packet = YAML.safe_load(output.read, aliases: true).fetch("prompt_packets").fetch(0)
    assert_equal "fp_hero_core", packet.fetch("mode")
    assert_equal "hero_core", packet.dig("cut_pointer", "cut_type")
    assert_equal "planning_candidate_only", packet.fetch("authority_status")
    assert_equal 5, packet.dig("compiled_prompt_block", "full_prompt_text").lines.length
    assert_equal %w[current_title_member_visual governing_scene_or_sequence_reference],
                 packet.fetch("attachments").map { |row| row.fetch("role") }
    plan = packet.fetch("reference_role_plan")
    assert_equal "none", plan.fetch("performance_mode")
    assert_equal packet.fetch("attachments").map { |row| row.fetch("binding_id") },
                 plan.fetch("attachment_order_binding_ids")
    scene = plan.fetch("logical_role_groups").find { |row| row.fetch("logical_role") == "scene_visual_package" }
    motion = plan.fetch("logical_role_groups").find { |row| row.fetch("logical_role") == "motion_reference" }
    assert_equal scene.fetch("composition_anchor_binding_id"), motion.fetch("attachment_binding_ids").fetch(0)
    assert_equal "background_and_space", scene.dig("world_look_function_lineage", 0, "purpose")
    assert_equal "still_camera_and_composition", scene.dig("composition_anchor_function_lineage", "purpose")
    assert_equal "visible_action_or_hold", motion.dig("motion_function_lineage", 0, "purpose")
  end

  def test_official_core_compiles_through_the_same_five_line_profile
    delta = generic_delta("official_core")
    @fixture.delta_path.write(YAML.dump(delta))
    output = @fixture.run_dir.join("01-official-core-packets.yaml")

    result = run_compiler("--output", output.to_s)

    assert result[:status].success?, result[:stderr]
    packet = YAML.safe_load(output.read, aliases: true).fetch("prompt_packets").fetch(0)
    assert_equal "official_core", packet.fetch("mode")
    assert_equal "official_core", packet.dig("cut_pointer", "cut_type")
    assert_equal "official_core_storyboard_authorized", packet.fetch("authority_status")
    assert_equal "C01", packet.fetch("core_cut_id")
    assert_equal 5, packet.dig("compiled_prompt_block", "full_prompt_text").lines.length
  end

  def test_generic_mode_cannot_masquerade_as_another_source_stage
    delta = generic_delta("fp_hero_core")
    delta.fetch("packets").fetch(0)["mode"] = "official_core"
    @fixture.delta_path.write(YAML.dump(delta))

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_includes result[:stderr], "mode differs from compile_target"
  end

  def test_generic_storyline_node_hash_drift_is_rejected
    delta = generic_delta("official_core")
    packet = delta.fetch("packets").fetch(0)
    packet.dig("cut_context", "source_storyline_binding_ref")["value_sha256"] = "0" * 64
    packet.fetch("authoring_inspection_receipt")["source_storyline_alignment_binding_sha256"] = "0" * 64
    @fixture.delta_path.write(YAML.dump(delta))

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_includes result[:stderr], "cut_context must exact-copy"
  end

  def test_generic_visible_member_cannot_drop_current_title_visual_attachment
    delta = generic_delta("fp_hero_core")
    packet = delta.fetch("packets").fetch(0)
    packet["attachments"] = packet.fetch("attachments").reject { |row| row["role"] == "current_title_member_visual" }
    @fixture.delta_path.write(YAML.dump(delta))

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_match(/attachments|current_title_member_visual|schema validation/i, result[:stderr])
  end

  def test_legacy_delta_schema_is_rejected_without_migration
    @fixture.delta["schema_version"] = "1.2"
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_includes result[:stderr], "'1.6' was expected"
  end

  def test_stale_context_review_version_is_rejected
    review = YAML.safe_load(@fixture.context_review_path.read, aliases: true)
    review["schema_version"] = "idol-02a-creative-context-review.v6"
    @fixture.context_review_path.write(YAML.dump(review))
    @fixture.delta.dig("readiness_evidence", "storyboard_context_review")["artifact_sha256"] =
      Digest::SHA256.file(@fixture.context_review_path).hexdigest
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_includes result[:stderr], "idol-02a-creative-context-review.v7"
  end

  def test_v1_3_rejects_empty_canonical_objects
    @fixture.delta["direct_compile_basis"] = {}
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_match(/direct_compile_basis|image_quality|schema validation/i, result[:stderr])
  end

  def test_v1_3_rejects_empty_attachment_set
    @fixture.delta.dig("packets", 0)["attachments"] = []
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_match(/attachments|non-empty|schema validation/i, result[:stderr])
  end

  def test_storyline_binding_hash_drift_is_rejected
    @fixture.delta.dig("packets", 0, "direct_prompt_revision", "storyline_authoring_binding")["source_branch_storyline_binding_sha256"] = "0" * 64
    @fixture.rewrite_delta
    result = run_compiler("--verify-only")
    refute result[:status].success?
    assert_includes result[:stderr], "source_branch_storyline_binding_sha256 is stale"
  end

  def test_component_consumption_gap_is_rejected
    @fixture.delta.dig("packets", 0, "direct_prompt_revision", "storyline_authoring_binding", "component_consumption", "whole_film").delete("avoid")
    @fixture.rewrite_delta
    result = run_compiler("--verify-only")
    refute result[:status].success?
    assert_includes result[:stderr], "union must cover every storyline-sensitive prompt component"
  end

  def test_neighbor_hash_drift_is_rejected
    @fixture.delta.dig("packets", 0, "direct_prompt_revision", "same_section_context", "next_branch_cut", "value_sha256").replace("0" * 64)
    @fixture.rewrite_delta
    result = run_compiler("--verify-only")
    refute result[:status].success?
    assert_includes result[:stderr], "next_branch_cut.value_sha256 is stale"
  end

  def test_missing_motion_reference_role_is_rejected
    packet = @fixture.delta.fetch("packets").fetch(0)
    motion = packet.dig("reference_role_plan", "logical_role_groups").find { |row| row["logical_role"] == "motion_reference" }
    motion.replace(
      "logical_role" => "prop_reference",
      "applicability" => "not_applicable_no_material_prop",
      "attachment_binding_ids" => []
    )
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_match(/motion_reference|required roles/i, result[:stderr])
  end

  def test_reference_function_lineage_rejects_media_type_as_function
    scene = @fixture.delta.dig("packets", 0, "reference_role_plan", "logical_role_groups").find { |row| row["logical_role"] == "scene_visual_package" }
    scene.dig("composition_anchor_function_lineage")["source_media_type"] = "still_camera_and_composition"
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_match(/source_media_type|schema validation/i, result[:stderr])
  end

  def test_reference_function_lineage_rejects_stale_function_value
    motion = @fixture.delta.dig("packets", 0, "reference_role_plan", "logical_role_groups").find { |row| row["logical_role"] == "motion_reference" }
    motion.dig("motion_function_lineage", 0)["function_value_sha256"] = "0" * 64
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_includes result[:stderr], "function_value_sha256 is stale"
  end

  def test_scene_world_binding_without_exact_function_lineage_is_rejected
    packet = @fixture.delta.fetch("packets").fetch(0)
    plan = packet.fetch("reference_role_plan")
    scene = plan.fetch("logical_role_groups").find { |row| row["logical_role"] == "scene_visual_package" }
    member_id = packet.fetch("attachments").find { |row| row["role"] == "current_title_member_visual" }.fetch("binding_id")
    scene.fetch("attachment_binding_ids") << member_id
    scene.fetch("world_look_binding_ids") << member_id
    @fixture.rewrite_delta

    result = run_compiler("--verify-only")

    refute result[:status].success?
    assert_includes result[:stderr], "world/look bindings must each carry exact function lineage"
  end

  def test_carry_forward_keeps_unmutated_approved_packet
    prior_path = write_approved_prior
    omit_first_delta_packet_and_bind_carry_forward(prior_path)
    result = run_compiler("--verify-only")
    assert result[:status].success?, result[:stderr]
  end

  def test_carry_forward_rejects_rendered_five_lines_drift
    prior_path = write_approved_prior
    prior = YAML.safe_load(prior_path.read, aliases: true)
    drifted = prior.fetch("prompt_packets").fetch(0)
    rendered = drifted.fetch("rendered_five_lines")
    rendered["scene_intent"] = "Silently replace the authored still purpose."
    rendered["full_prompt_text"] = [
      "Identity reference rule: #{rendered.fetch('identity_reference_rule')}",
      "Scene intent: #{rendered.fetch('scene_intent')}",
      "Visible details: #{rendered.fetch('visible_details')}",
      "Action cue: #{rendered.fetch('action_cue')}",
      "Avoid: #{rendered.fetch('avoid')}"
    ].join("\n")
    rendered["full_prompt_sha256"] = Digest::SHA256.hexdigest(rendered.fetch("full_prompt_text"))
    refresh_prior_packet_hash!(prior, drifted)
    prior_path.write(YAML.dump(prior))
    omit_first_delta_packet_and_bind_carry_forward(prior_path)

    result = run_compiler("--verify-only")
    refute result[:status].success?
    assert_includes result[:stderr], "rendered_five_lines differs from compiled_prompt_block"
  end

  def test_carry_forward_rejects_attachment_store_drift
    prior_path = write_approved_prior
    prior = YAML.safe_load(prior_path.read, aliases: true)
    drifted = prior.fetch("prompt_packets").fetch(0)
    member = drifted.fetch("attachments").find { |row| row["role"] == "current_title_member_visual" }
    scene = drifted.fetch("attachments").find { |row| row["role"] != "current_title_member_visual" }
    scene["actual_path"] = member.fetch("actual_path")
    scene["sha256"] = member.fetch("sha256")
    refresh_prior_packet_hash!(prior, drifted)
    prior_path.write(YAML.dump(prior))
    omit_first_delta_packet_and_bind_carry_forward(prior_path)

    result = run_compiler("--verify-only")
    refute result[:status].success?
    assert_includes result[:stderr], "attachments changed and must be supplied in this delta"
  end

  def test_fp_hero_core_authoring_validator_accepts_compiled_packet
    output = compile_generic_document("fp_hero_core")
    stdout, stderr, status = validate_02b(output)
    assert status.success?, [stderr, stdout].join("\n")
  end

  def test_official_core_authoring_validator_accepts_compiled_packet
    output = compile_generic_document("official_core")
    stdout, stderr, status = validate_02b(output)
    assert status.success?, [stderr, stdout].join("\n")
  end

  def test_fp_hero_core_authoring_validator_rejects_rendered_five_lines_drift
    output = compile_generic_document("fp_hero_core")
    document = YAML.safe_load(output.read, aliases: true)
    packet = document.fetch("prompt_packets").fetch(0)
    compiled_intent = packet.dig("compiled_prompt_block", "scene_intent")
    packet["rendered_five_lines"] = JSON.parse(JSON.generate(packet.fetch("rendered_five_lines")))
    rendered = packet.fetch("rendered_five_lines")
    rendered["scene_intent"] = "Silently replace the authored still purpose."
    rendered["full_prompt_text"] = [
      "Identity reference rule: #{rendered.fetch('identity_reference_rule')}",
      "Scene intent: #{rendered.fetch('scene_intent')}",
      "Visible details: #{rendered.fetch('visible_details')}",
      "Action cue: #{rendered.fetch('action_cue')}",
      "Avoid: #{rendered.fetch('avoid')}"
    ].join("\n")
    rendered["full_prompt_sha256"] = Digest::SHA256.hexdigest(rendered.fetch("full_prompt_text"))
    assert_equal compiled_intent, packet.dig("compiled_prompt_block", "scene_intent")
    refute_equal compiled_intent, rendered.fetch("scene_intent")
    output.write(YAML.dump(document))

    _stdout, stderr, status = validate_02b(output)
    refute status.success?
    assert_includes stderr, "rendered_five_lines must exact-copy compiled_prompt_block"
  end

  def test_fp_hero_core_authoring_validator_rejects_matching_generated_store_rewrite
    output = compile_generic_document("fp_hero_core")
    document = YAML.safe_load(output.read, aliases: true)
    packet = document.fetch("prompt_packets").fetch(0)
    authored_visible = packet.dig("five_line_components", "visible_details", "background_and_space")
    rewritten_visible = [
      "Background and space — rewritten space",
      "Still camera and composition — camera height: rewritten height; shot scale/distance: rewritten distance; direction/angle: rewritten angle; depth: rewritten depth; subject placement: rewritten placement; crop/negative space: rewritten crop; lens feel: rewritten lens",
      "Lighting, color, and material — rewritten light",
      "4K, high quality, high detail"
    ].join("; ")
    packet["compiled_prompt_block"] = JSON.parse(JSON.generate(packet.fetch("compiled_prompt_block")))
    packet["rendered_five_lines"] = JSON.parse(JSON.generate(packet.fetch("rendered_five_lines")))
    %w[compiled_prompt_block rendered_five_lines].each do |key|
      store = packet.fetch(key)
      store["visible_details"] = rewritten_visible
      store["full_prompt_text"] = [
        "Identity reference rule: #{store.fetch('identity_reference_rule')}",
        "Scene intent: #{store.fetch('scene_intent')}",
        "Visible details: #{store.fetch('visible_details')}",
        "Action cue: #{store.fetch('action_cue')}",
        "Avoid: #{store.fetch('avoid')}"
      ].join("\n")
      store["full_prompt_sha256"] = Digest::SHA256.hexdigest(store.fetch("full_prompt_text"))
    end
    assert_equal authored_visible, packet.dig("five_line_components", "visible_details", "background_and_space")
    output.write(YAML.dump(document))

    _stdout, stderr, status = validate_02b(output)
    refute status.success?
    assert_includes stderr, "compiled visible_details differs from the authored structured component serialization"
  end

  private

  def canonical_sha(value)
    canonical = case value
                when Hash
                  value.keys.sort.each_with_object({}) { |key, result| result[key] = JSON.parse(JSON.generate(value[key])) }
                else
                  value
                end
    Digest::SHA256.hexdigest(JSON.generate(deep_sort(canonical)))
  end

  def deep_sort(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = deep_sort(value[source_key])
      end
    when Array
      value.map { |item| deep_sort(item) }
    else
      value
    end
  end

  def generic_delta(mode)
    source_path = mode == "fp_hero_core" ? @fixture.front_path : @fixture.direction_path
    source = YAML.safe_load(source_path.read, aliases: true)
    fp = YAML.safe_load(@fixture.front_path.read, aliases: true)
    if mode == "fp_hero_core"
      source_cut = source.fetch("hero_core_cut_candidates").fetch(0)
      pointer = "/hero_core_cut_candidates/0"
      cut_id = source_cut.fetch("hero_core_id")
      core_slot_id = source_cut.fetch("core_slot_id")
      node = source.dig("screen_progression_map", "nodes", 0)
      node_pointer = "/screen_progression_map/nodes/0"
      section_id = node.fetch("section_id")
      major_scene_id = node.fetch("major_scene_id")
      storyline_version_id = source.dig("screen_progression_map", "active_storyline_version_id")
      applicability = "meaningfully_visible"
      scene_reference = fp.fetch("core_visual_candidate_sets").fetch(0).fetch("candidates").fetch(0)
      scene_binding_id = scene_reference.fetch("candidate_id")
      scene_asset_id = scene_binding_id
    else
      source_cut = source.fetch("official_core_cuts").fetch(0)
      pointer = "/official_core_cuts/0"
      cut_id = source_cut.fetch("core_cut_id")
      core_slot_id = source_cut.fetch("source_core_slot_id")
      node = source.dig("screen_progression_map_projection", "projected_value", "nodes", 0)
      node_pointer = "/screen_progression_map_projection/projected_value/nodes/0"
      section_id = source_cut.fetch("section_id")
      major_scene_id = source_cut.fetch("parent_major_scene_id")
      storyline_version_id = source_cut.fetch("active_storyline_version_id")
      applicability = source_cut.fetch("member_visual_applicability")
      scene_reference = source_cut.fetch("core_reference_binding")
      scene_binding_id = scene_reference.fetch("binding_id")
      scene_asset_id = scene_reference.fetch("selected_reference_candidate_id")
    end
    member_asset = fp.dig("current_title_visual_identity", "assets", 0)
    attachments = [
      attachment(member_asset, 1, "current_title_member_visual", member_asset.fetch("asset_id"), member_asset.fetch("asset_id")),
      attachment(scene_reference, 2, "governing_scene_or_sequence_reference", scene_binding_id, scene_asset_id)
    ]
    branch_components = Marshal.load(Marshal.dump(@fixture.delta.dig("packets", 0, "five_line_components")))
    branch_components.dig("identity_reference_rule", "current_title_visual_bindings").replace([member_asset.fetch("asset_id")])
    branch_components.dig("scene_intent")["core_slot_or_core_component"] =
      mode == "fp_hero_core" ? "Author the selected Hero candidate for this exact Core Slot without promoting it." : source_cut.fetch("required_screen_information")
    branch_components.dig("scene_intent")["branch_expansion_component"] = nil
    rendered = render_generic(branch_components)
    output_path = @fixture.run_dir.join("outputs", "#{cut_id}.png").relative_path_from(ROOT).to_s
    execution = Marshal.load(Marshal.dump(@fixture.delta.dig("packets", 0, "execution")))
    execution["expected_output_path"] = output_path
    packet = {
      "packet_id" => "PKT_#{cut_id}",
      "mode" => mode,
      "source_cut_ref" => {"cut_id" => cut_id, "json_pointer" => pointer, "value_sha256" => canonical_sha(source_cut)},
      "cut_context" => {
        "section_id" => section_id,
        "major_scene_id" => major_scene_id,
        "active_storyline_version_id" => storyline_version_id,
        "screen_progression_node_id" => node.fetch("node_id"),
        "member_visual_applicability" => applicability,
        "source_core_slot_id" => core_slot_id,
        "source_storyline_binding_ref" => {"json_pointer" => node_pointer, "value_sha256" => canonical_sha(node)}
      },
      "expected_output_path" => output_path,
      "derivative_route_id" => "DERIVATIVE_MAIN_MV",
      "production_scope_id" => "PSCOPE_FULL_MV",
      "authoring_model_profile_id" => "fixture_assigned_model",
      "execution" => execution,
      "five_line_components" => branch_components,
      "rendered_five_lines" => rendered,
      "attachments" => attachments,
      "reference_role_plan" => reference_role_plan(attachments, applicability),
      "authoring_inspection_receipt" => {
        "inspection_owner" => "human_or_assigned_model",
        "source_cut_contract_sha256" => canonical_sha(source_cut),
        "source_storyline_alignment_binding_sha256" => canonical_sha(node),
        "inspected_storyline_levels" => ["whole_film", "section", "major_scene", "planning_core_or_slot"],
        "inspected_visual_reference_binding_ids" => attachments.map { |row| row.fetch("binding_id") },
        "inspected_current_title_asset_ids" => [member_asset.fetch("asset_id")],
        "authored_component_order" => ["identity_reference_rule", "scene_intent", "visible_details", "action_cue", "avoid"],
        "creative_fill_policy" => "human_or_assigned_model_only_scripts_exact_copy_and_fixed_labels_only",
        "storyline_inspection_note" => "The assigned author inspected exact whole-film, Section, Major, and Core-slot lineage.",
        "inspection_note" => "The assigned author inspected every attachment in exact order."
      },
      "adoption_lineage" => {"adopted_from_packet_id" => nil, "same_image_bytes_reusable" => false, "canonical_promotion_inferred" => false}
    }
    delta = Marshal.load(Marshal.dump(@fixture.delta))
    delta.delete("source_02a")
    delta.delete("section_compile_scope")
    delta.delete("readiness_evidence")
    delta.delete("carry_forward_source_02b")
    delta["compile_target"] = mode
    delta["source_cut_artifact"] = {
      "path" => source_path.relative_path_from(ROOT).to_s,
      "artifact_sha256" => Digest::SHA256.file(source_path).hexdigest,
      "schema_version" => source.fetch("schema_version")
    }
    delta.dig("direct_compile_basis")["default_render_prompt_mode"] = "single_cut_16_9"
    delta.dig("output")["coverage_status"] = "complete"
    delta["packets"] = [packet]
    delta
  end

  def attachment(source, order, role, binding_id, asset_id)
    {
      "order" => order,
      "role" => role,
      "binding_id" => binding_id,
      "asset_id" => asset_id,
      "actual_path" => source["path"] || source.fetch("actual_path"),
      "sha256" => source.fetch("sha256"),
      "pixel_inspection_status" => "passed",
      "locked" => true
    }
  end

  def reference_role_plan(attachments, applicability)
    @fixture.send(:reference_role_plan, attachments, applicability)
  end

  def render_generic(components)
    identity = components.fetch("identity_reference_rule").fetch("visible_identity")
    scene = components.fetch("scene_intent").fetch("core_slot_or_core_component")
    visible = components.fetch("visible_details")
    camera = visible.fetch("still_camera_and_composition")
    visible_line = [
      "Background and space — #{visible.fetch('background_and_space')}",
      "Still camera and composition — camera height: #{camera.fetch('camera_height')}; shot scale/distance: #{camera.fetch('shot_scale_distance')}; direction/angle: #{camera.fetch('direction_angle')}; depth: #{camera.fetch('depth_design')}; subject placement: #{camera.fetch('subject_placement')}; crop/negative space: #{camera.fetch('crop_negative_space')}; lens feel: #{camera.fetch('lens_feel')}",
      "Lighting, color, and material — #{visible.fetch('lighting_color_material')}",
      "4K, high quality, high detail"
    ].join("; ")
    action = components.fetch("action_cue")
    action_line = [
      "Subject state or pose — #{action.fetch('subject_state_or_pose')}",
      "Visible action or hold — #{action.fetch('visible_action_or_hold')}",
      ("Object/environment response — #{action.fetch('object_environment_response')}" if action["object_environment_response"])
    ].compact.join("; ")
    rows = {
      "identity_reference_rule" => identity,
      "scene_intent" => scene,
      "visible_details" => visible_line,
      "action_cue" => action_line,
      "avoid" => components.fetch("avoid")
    }
    text = [
      "Identity reference rule: #{identity}",
      "Scene intent: #{scene}",
      "Visible details: #{visible_line}",
      "Action cue: #{action_line}",
      "Avoid: #{rows.fetch('avoid')}"
    ].join("\n")
    rows.merge(
      "full_prompt_text" => text,
      "full_prompt_sha256" => Digest::SHA256.hexdigest(text),
      "label_order" => ["Identity reference rule", "Scene intent", "Visible details", "Action cue", "Avoid"]
    )
  end

  def run_compiler(*arguments)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      @fixture.delta_path.to_s,
      *arguments,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end

  def write_approved_prior
    prior_path = @fixture.run_dir.join("02B-section-S01-prior.yaml")
    result = run_compiler("--output", prior_path.to_s)
    raise result[:stderr] unless result[:status].success?
    prior = YAML.safe_load(prior_path.read, aliases: true)
    prior["status"] = "approved"
    prior.fetch("prompt_packets").each { |packet| packet["status"] = "approved" }
    prior.fetch("prompt_packets").each { |packet| refresh_prior_packet_hash!(prior, packet) }
    prior_path.write(YAML.dump(prior))
    prior_path
  end

  def refresh_prior_packet_hash!(document, packet)
    state = document.dig("section_shards", 0, "local_lineage", "packet_states").find do |row|
      row["packet_id"] == packet["packet_id"]
    end
    state["packet_value_sha256"] = @fixture.value_sha(packet)
  end

  def omit_first_delta_packet_and_bind_carry_forward(prior_path)
    omitted_id = YAML.safe_load(prior_path.read, aliases: true).fetch("prompt_packets").fetch(0).fetch("packet_id")
    @fixture.delta["packets"] = @fixture.delta.fetch("packets").reject { |row| row["packet_id"] == omitted_id }
    @fixture.delta["carry_forward_source_02b"] = {
      "path" => prior_path.relative_path_from(ROOT).to_s,
      "artifact_sha256" => Digest::SHA256.file(prior_path).hexdigest
    }
    @fixture.rewrite_delta
  end

  def compile_generic_document(mode)
    @fixture.delta_path.write(YAML.dump(generic_delta(mode)))
    output = @fixture.run_dir.join("#{mode}-packets.yaml")
    result = run_compiler("--output", output.to_s)
    raise result[:stderr] unless result[:status].success?
    output
  end

  def validate_02b(path)
    Open3.capture3(
      RbConfig.ruby,
      ROOT.join("scripts", "validate_02b_imagegen_contract.rb").to_s,
      "--mode", "authoring",
      "--run-root", @fixture.run_dir.to_s,
      path.to_s,
      chdir: ROOT.to_s
    )
  end
end
