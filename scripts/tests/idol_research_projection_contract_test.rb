# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_direction_projection_contract"

class IdolResearchProjectionContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path

  def test_01_reference_application_binds_source_freshness_and_direct_grammar_without_duplicate_trace_key
    schema = JSON.parse(ROOT.join("schemas/song-choreography-performance-mv-map.schema.json").read)
    assert_equal "1.9", schema.dig("properties", "schema_version", "const")

    source_artifact = schema.dig("$defs", "artifactRef")
    assert_equal %w[path sha256], source_artifact.fetch("required")

    application = schema.dig("$defs", "referenceApplication")
    required = application.fetch("required")
    %w[
      reference_unit_id
      source_path
      source_sha256
      direct_use_mode
      scene_or_sequence_target
      preserved_action_or_hold
      preserved_staging
      preserved_still_camera
      preserved_subject_placement_and_crop
      preserved_ordered_grammar
      02a_binding_rule
    ].each { |field| assert_includes required, field }
    assert_equal(
      %w[bounded_surface_direct full_scene_direct sequence_direct],
      application.dig("properties", "direct_use_mode", "enum")
    )
    assert_equal(
      "bind_each_selected_cell_crop_or_frame_as_its_own_path_and_sha256_never_whole_sheet_fallback",
      application.dig("properties", "02a_binding_rule", "const")
    )
    refute_includes required, "downstream_trace_key"
    refute application.fetch("properties").key?("downstream_trace_key")
  end

  def test_v3_fragment_contract_can_close_only_through_01
    schema = JSON.parse(ROOT.join("schemas/reference-fragment-crop-lock.schema.json").read)
    assert_equal "idol_reference_fragment_crop_lock.v3", schema.dig("properties", "schema_version", "const")

    statuses = schema.dig("properties", "status", "enum")
    assert_includes statuses, "adapted_to_01"
    refute_includes statuses, "ready_for_02"

    downstream = schema.dig("properties", "downstream_contract")
    required = schema.fetch("allOf").last.dig("properties", "downstream_contract", "required")
    %w[
      01_reference_applications_must_resolve_fragment_ids
      downstream_must_use_01_application_ids
      raw_fragment_paths_must_not_replace_application_bindings_downstream
      master_storyboard_must_trace_01_application_ids
      direct_follow_surfaces_must_survive
      master_storyboard_contract_fields
      prompt_packets_must_inherit_text_locks
      api_attachment_policy
    ].each { |field| assert_includes required, field }
    assert_equal true, downstream.dig("properties", "01_reference_applications_must_resolve_fragment_ids", "const")
    assert_equal true, downstream.dig("properties", "downstream_must_use_01_application_ids", "const")
    assert_equal true, downstream.dig("properties", "raw_fragment_paths_must_not_replace_application_bindings_downstream", "const")

    receipt_contract = schema.fetch("allOf").find do |row|
      row.dig("if", "properties", "interpretation_contract_version", "const") == "reference_interpretation_receipt.v1"
    end
    receipt_gate = receipt_contract.dig("then", "properties", "fragments", "items", "allOf").find do |row|
      row.dig("if", "properties", "status", "const") == "selected"
    end
    assert_equal ["interpretation_receipt"], receipt_gate.dig("then", "required")
  end

  def test_selected_01r_capture_requires_interpretation_receipt
    schema = JSON.parse(ROOT.join("schemas/mv-direction-reference-mining.schema.json").read)
    receipt_contract = schema.fetch("allOf").find do |row|
      row.dig("if", "properties", "interpretation_contract_version", "const") == "reference_interpretation_receipt.v1"
    end
    capture_gate = receipt_contract.dig("then", "properties", "reference_captures", "items", "allOf").find do |row|
      row.dig("if", "properties", "capture_status", "const") == "selected_for_01"
    end
    assert_equal ["interpretation_receipt"], capture_gate.dig("then", "required")

    gap_contract = schema.fetch("allOf").find do |row|
      row.dig("if", "properties", "reference_gap_contract_version", "const") == "reference_function_coverage.v1"
    end
    assert_equal ["reference_function_coverage"], gap_contract.dig("then", "required")
    visual_gate = gap_contract.dig("then", "properties", "reference_captures", "items", "allOf").find do |row|
      row.dig("if", "properties", "capture_status", "const") == "selected_for_01"
    end
    assert_equal ["visual_direction_read"], visual_gate.dig("then", "required")

    audience_contract = schema.fetch("allOf").find do |row|
      row.dig("if", "properties", "audience_connection_contract_version", "const") == "audience_connection_reference_binding.v1"
    end
    audience_capture_gate = audience_contract.dig("then", "properties", "reference_captures", "items", "allOf").find do |row|
      row.dig("if", "properties", "capture_status", "const") == "selected_for_01"
    end
    assert_equal %w[audience_connection_binding source_context_verification], audience_capture_gate.dig("then", "required")
    assert_equal %w[audience_connection_ids content_role_ids dominant_content_role], audience_contract.dig("then", "properties", "section_direction_cards", "items", "required")

    performance_rule = schema.dig("properties", "reference_captures", "items", "properties", "audience_connection_binding", "properties", "performance_rule", "const")
    assert_equal "performance_choreography_is_optional_not_a_default_reference_target", performance_rule
  end

  def test_new_01r_section_reference_comparison_has_a_real_floor_without_forcing_three_applications
    schema = JSON.parse(ROOT.join("schemas/mv-direction-reference-mining.schema.json").read)
    assert_equal "section_reference_comparison.v1", schema.dig("properties", "reference_comparison_contract_version", "const")

    comparison = schema.dig("$defs", "sectionReferenceComparison")
    reviewed_units = comparison.dig("properties", "reviewed_units")
    assert_equal 3, reviewed_units.fetch("minItems")
    assert_equal 2, comparison.dig("properties", "distinct_source_identity_keys", "minItems")
    assert_equal 2, comparison.dig("properties", "covered_functions", "minItems")
    assert_equal 0, comparison.dig("properties", "selected_unit_ids").fetch("minItems", 0)

    counting = comparison.dig("properties", "counting_policy", "properties")
    assert_equal 3, counting.dig("minimum_reviewed_units", "const")
    assert_equal 2, counting.dig("minimum_distinct_source_identities", "const")
    assert_equal 2, counting.dig("minimum_distinct_functions", "const")
    assert_equal false, counting.dig("whole_contact_sheet_counts_as_unit", "const")
    assert_equal false, counting.dig("maximum_is_capped", "const")
    assert_equal "3_to_5", counting.dig("ordinary_target_range", "const")
    assert_equal "5_to_8", counting.dig("complex_target_range", "const")
    assert_equal "comparison_minimum_does_not_require_three_applied_or_combined_references", counting.dig("application_rule", "const")

    contract = schema.fetch("allOf").find do |row|
      row.dig("if", "properties", "reference_comparison_contract_version", "const") == "section_reference_comparison.v1"
    end
    assert_equal ["section_reference_comparisons"], contract.dig("then", "required")
    assert_equal ["reference_comparison_id"], contract.dig("then", "properties", "section_direction_cards", "items", "required")
  end

  def test_stage_registry_keeps_reference_application_and_still_camera_direction_inside_01
    registry = YAML.safe_load(ROOT.join("automation/harness-stage-registry.yaml").read)
    stage = registry.fetch("stages").find { |row| row.fetch("code") == "01" }
    assert_equal ["schemas/song-choreography-performance-mv-map.schema.json"], stage.fetch("output_contracts")
    refute registry.fetch("stages").any? { |row| row["active"] && row["code"] == "01A" }

    schema = JSON.parse(ROOT.join(stage.fetch("output_contracts").first).read)
    application = schema.dig("$defs", "referenceApplication")
    still_camera = schema.dig("$defs", "stillCameraCoverage")
    assert_includes application.fetch("required"), "source_sha256"
    assert_includes application.fetch("required"), "preserved_still_camera"
    assert_includes still_camera.fetch("required"), "camera_height"
    assert_includes still_camera.fetch("required"), "direction_angle"
    assert_equal "03V_after_passed_image_pixel_inspection", still_camera.dig("properties", "temporal_camera_owner", "const")
  end

  def test_02a_and_02b_visual_reference_binding_shapes_remain_identical
    storyboard = JSON.parse(ROOT.join("schemas/master-storyboard.schema.json").read)
    packets = JSON.parse(ROOT.join("schemas/prompt-packets.schema.json").read)
    storyboard_carry = storyboard.dig("$defs", "visualReferenceBinding")
    packet_carry = packets.dig("$defs", "visualReferenceBinding")

    assert_equal storyboard_carry.fetch("required"), packet_carry.fetch("required")
    assert_equal storyboard_carry.fetch("properties").keys, packet_carry.fetch("properties").keys
  end

  def test_founder_front_planning_storyline_lock_promotes_and_projects_without_compression
    Dir.mktmpdir("idol-front-planning-storyline-lock-") do |directory|
      root = Pathname.new(directory)
      section_lock = {
        "section_id" => "S00",
        "story_state_in" => "She waits outside the room.",
        "section_event_or_hold" => "She opens the door but does not cross it yet.",
        "story_state_out" => "The other member sees the open threshold.",
        "section_storyline" => "The full Founder section prose remains here rather than being reduced to a cut label.",
        "reference_binding_mode" => "receipts_bound",
        "reference_interpretation_ids" => ["RINT_THRESHOLD"],
        "transition_to_next" => "The door edge becomes the next section's foreground."
      }
      preservation = "01_may_expand_direction_reference_application_camera_and_cut_logic_but_must_preserve_each_locked_section_story_state_event_transition_and_order;_02A_and_02B_copy_the_relevant_section_lock_exactly"
      front_lock = {
        "contract_version" => "front_planning_storyline_lock.v1",
        "lock_status" => "founder_locked",
        "founder_lock_basis" => "Founder approved the whole-film and section storyline.",
        "canonical_plan" => {"path" => "front-planning.md", "sha256" => "0" * 64},
        "whole_film_storyline" => "A threshold opens, changes who can see whom, then resolves in a shared exit.",
        "section_locks" => [section_lock],
        "preservation_rule" => preservation
      }
      front_path = root.join("front-planning.yaml")
      front_path.write(YAML.dump("storyline_creative_lock" => front_lock))
      nucleus_lock = {
        "contract_version" => "front_planning_storyline_lock.v1",
        "source_front_planning_path" => front_path.to_s,
        "source_front_planning_sha256" => Digest::SHA256.file(front_path.to_s).hexdigest,
        "source_json_pointer" => "/storyline_creative_lock",
        "source_value_sha256" => IdolDirectionProjectionContract.structured_value_sha256(front_lock),
        "whole_film_storyline" => front_lock["whole_film_storyline"],
        "section_locks" => front_lock["section_locks"],
        "preservation_rule" => preservation
      }
      nucleus_path = root.join("00.yaml")
      nucleus_path.write(YAML.dump("front_planning_storyline_lock" => nucleus_lock))
      direction_lock = {
        "contract_version" => "front_planning_storyline_lock.v1",
        "source_nucleus_path" => nucleus_path.to_s,
        "source_nucleus_sha256" => Digest::SHA256.file(nucleus_path.to_s).hexdigest,
        "source_01_json_pointer" => "/front_planning_storyline_lock",
        "source_value_sha256" => IdolDirectionProjectionContract.structured_value_sha256(nucleus_lock),
        "whole_film_storyline" => nucleus_lock["whole_film_storyline"],
        "section_locks" => nucleus_lock["section_locks"],
        "preservation_rule" => preservation
      }
      direction = {
        "source_nucleus" => nucleus_path.to_s,
        "story_distribution" => {"front_planning_storyline_lock_projection" => direction_lock},
        "section_gate" => {
          "slices" => [
            {
              "section_id" => "S00",
              "front_planning_storyline_section_projection" => {
                "disposition" => "projected",
                "source_01_json_pointer" => "/story_distribution/front_planning_storyline_lock_projection/section_locks/0",
                "source_value_sha256" => IdolDirectionProjectionContract.structured_value_sha256(section_lock),
                "section_lock" => Marshal.load(Marshal.dump(section_lock))
              }
            }
          ]
        }
      }
      direction_path = root.join("01.yaml")
      direction_path.write(YAML.dump(direction))

      errors = []
      IdolDirectionProjectionContract.validate_front_planning_storyline_lock(direction_path, direction, root, errors)
      assert_empty errors

      direction.dig("section_gate", "slices", 0, "front_planning_storyline_section_projection", "section_lock")["story_state_out"] = "A different later-story shortcut."
      errors = []
      IdolDirectionProjectionContract.validate_front_planning_storyline_lock(direction_path, direction, root, errors)
      assert errors.any? { |error| error.include?("must exactly preserve the Founder-locked Front Planning section") }
    end
  end

  def test_02a_section_projection_cannot_drop_or_rewrite_founder_storyline_lock
    section_lock = {
      "section_id" => "S04",
      "story_state_in" => "The two members occupy opposite sides of the threshold.",
      "section_event_or_hold" => "Neither crosses; the held distance becomes the event.",
      "story_state_out" => "The reflected threshold now belongs to both of them.",
      "section_storyline" => "Full Founder section prose survives the cut plan without being converted into a shorter scene label.",
      "reference_binding_mode" => "no_reference_needed",
      "reference_interpretation_ids" => [],
      "transition_to_next" => "The shared reflection carries into the next section."
    }
    source_rows = [{
      "section_id" => "S04",
      "pointer" => "/section_gate/slices/4/front_planning_storyline_section_projection/section_lock",
      "value" => section_lock,
      "source_kind" => "section_slice"
    }]
    cut = {
      "cut_id" => "B40",
      "source_sections" => ["S04"],
      "front_planning_storyline_projection" => {
        "disposition" => "projected",
        "source_01_json_pointer" => source_rows.first.fetch("pointer"),
        "source_value_sha256" => IdolDirectionProjectionContract.structured_value_sha256(section_lock),
        "section_lock" => Marshal.load(Marshal.dump(section_lock))
      }
    }

    errors = []
    IdolDirectionProjectionContract.validate_cut_storyline_projection(cut, source_rows, errors)
    assert_empty errors

    cut.dig("front_planning_storyline_projection", "section_lock")["section_storyline"] = "A shorter replacement."
    errors = []
    IdolDirectionProjectionContract.validate_cut_storyline_projection(cut, source_rows, errors)
    assert errors.any? { |error| error.include?("must exactly preserve the bound 01 Founder-locked storyline section") }
  end

  def test_master_storyboard_22_requires_hash_bound_reference_role_scope_and_order
    schema = JSON.parse(ROOT.join("schemas/master-storyboard.schema.json").read)
    assert_equal "2.2", schema.dig("properties", "schema_version", "const")

    binding = schema.dig("$defs", "visualReferenceBinding")
    required = binding.fetch("required")
    %w[
      binding_id
      actual_path
      sha256
      role
      reference_scope
      reference_class
      order
      must_inspect_pixels
      preserve
      discard
      attachment_permission
    ].each { |field| assert_includes required, field }
    assert_equal %w[member_visual scene_visual], binding.dig("properties", "reference_scope", "enum")
    assert_includes binding.dig("properties", "reference_class", "enum"), "founder_sequence_subreference"
    assert_includes binding.dig("properties", "reference_class", "enum"), "founder_scene_subreference"
    assert_includes schema.dig("$defs", "branchCut", "required"), "visual_reference_bindings"
  end

  def test_exact_01_hash_application_and_camera_pointer_validate_together
    Dir.mktmpdir("idol-direction-projection-") do |directory|
      root = Pathname.new(directory)
      direction_path = root.join("01.yaml")
      inspected_reference_path = root.join("selected-reference-cell.png")
      inspected_reference_path.binwrite("selected reference pixels")
      interpretation_owner_path = root.join("front-planning-readiness.yaml")
      interpretation_owner = {
        "reference_analysis" => {
          "observation" => "The lateral route reveals the pickup through layered depth.",
          "locator" => "selected reference cell 04",
          "selected_function" => "Use the lateral route to reveal the pickup."
        },
        "interpretation_contract" => {"reference_interpretation_index" => []}
      }
      receipt = {
        "interpretation_id" => "RINT_TEST_TRACE",
        "component_owner" => {"mode" => "self"},
        "components" => %w[observation locator selected_function].map do |field|
          role = {"observation" => "source_observation", "locator" => "evidence_locator", "selected_function" => "selected_function"}.fetch(field)
          pointer = "/reference_analysis/#{field}"
          {"role" => role, "json_pointer" => pointer, "value_sha256" => IdolReferenceInterpretationContract.canonical_digest(IdolReferenceInterpretationContract.pointer_value(interpretation_owner, pointer))}
        end,
        "inspected_sources" => [{"path" => inspected_reference_path.to_s, "sha256" => Digest::SHA256.file(inspected_reference_path.to_s).hexdigest, "media_kind" => "image", "inspection_scope" => "full_image", "selected_cells_or_frames" => []}],
        "revision" => {"number" => 1, "reopen_trigger" => "initial_analysis", "previous_receipt_sha256" => nil, "invalidates_from_stage" => "none", "reason" => "Initial selected reference interpretation."},
        "disposition" => "applied",
        "target_section_ids" => ["S00"],
        "target_scopes" => ["section"],
        "consume_mode" => "consume_bound_interpretation_without_source_reread"
      }
      interpretation_owner.dig("interpretation_contract", "reference_interpretation_index") << receipt
      interpretation_owner_path.write(YAML.dump(interpretation_owner))
      route = {
        "contract_version" => "camera_direction.v2",
        "route_id" => "CAM_TEST_TRACE",
        "summary" => "Knee-height lateral route",
        "shot_scale_family" => "SS_MLS",
        "camera_height" => "H_KNEE",
        "direction_angle" => "A_34",
        "depth_design" => "foreground, member, background",
        "movement_family" => "M_TRACK_LATERAL",
        "base_speed" => "V_BRISK",
        "composition_family" => "C_STACK_DEPTH",
        "lens_feel" => "L_NORMAL",
        "audio_story_job" => "show the pickup",
        "refuse_defaults" => []
      }
      front_planning_consequence = "Preserve the rain-threshold reveal as the cut's first, peak, and release composition states."
      camera_intent = "Keep the knee-height lateral axis and layered depth so the pickup reveals the next space."
      direction = {
        "research_synthesis" => {
          "interpretation_binding_contract" => IdolReferenceInterpretationContract::INTERPRETATION_BINDING_CONTRACT,
          "integration_id" => "RSI_TEST_TRACE",
          "source_artifacts" => [
            {
              "source_id" => "SRC_TEST_TRACE",
              "source_type" => "front_planning",
              "path" => interpretation_owner_path.to_s,
              "artifact_sha256" => Digest::SHA256.file(interpretation_owner_path.to_s).hexdigest
            }
          ],
          "selected_application_index" => [
            {
              "application_id" => "APP_TEST_TRACE",
              "source_ids" => ["SRC_TEST_TRACE"],
              "source_identities" => ["Founder reference TEST TRACE"],
              "selected_function" => "Use the lateral route to reveal the pickup.",
              "target_section_ids" => ["S00"],
              "audio_motion_basis" => "The pickup opens the lateral route.",
              "followed_surfaces" => [{"surface_type" => "camera_route", "lock" => "knee-height lateral track through layered depth"}],
              "current_song_consequence" => "The member crosses the frame as the next space opens.",
              "canonical_01_field_refs" => ["01#/lyric_to_scene_thinking/0/director_chain/camera_route_spec"],
              "reject_guard" => "Do not replace the lateral relation with a front portrait.",
              "interpretation_bindings" => [
                {
                  "receipt_id" => "RINT_TEST_TRACE",
                  "source_id" => "SRC_TEST_TRACE",
                  "source_receipt_json_pointer" => "/interpretation_contract/reference_interpretation_index/0",
                  "source_receipt_sha256" => IdolReferenceInterpretationContract.canonical_digest(receipt),
                  "source_revision" => 1,
                  "binding_mode" => "exact",
                  "consume_mode" => "consume_bound_interpretation_without_source_reread"
                }
              ]
            }
          ]
        },
        "lyric_to_scene_thinking" => [
          {
            "section_or_beat_id" => "S00",
            "front_planning_transfer" => {
              "02a_cut_keyframe_implication" => front_planning_consequence
            },
            "director_chain" => {
              "camera_route_spec" => route,
              "camera_coverage_intent" => camera_intent
            }
          }
        ]
      }
      direction_path.write(YAML.dump(direction))
      generation_path = root.join("02.yaml")
      generation_path.write(YAML.dump(
        "direction_handoff_contract" => {
          "source_01_path" => direction_path.to_s,
          "source_01_sha256" => Digest::SHA256.file(direction_path.to_s).hexdigest,
          "research_synthesis_id" => "RSI_TEST_TRACE",
          "projection_mode" => "selected_01_decisions_only",
          "section_routes" => [
            {
              "section_id" => "S00",
              "source_01_field_refs" => [
                "01#/lyric_to_scene_thinking/0/front_planning_transfer/02a_cut_keyframe_implication",
                "01#/lyric_to_scene_thinking/0/director_chain/camera_coverage_intent",
                "01#/lyric_to_scene_thinking/0/director_chain/camera_route_spec"
              ],
              "reference_application_ids" => ["APP_TEST_TRACE"],
              "camera_route_refs" => ["01#/lyric_to_scene_thinking/0/director_chain/camera_route_spec"],
              "generation_coverage_job" => "cover the lateral pickup",
              "must_preserve" => ["APP_TEST_TRACE", "CAM_TEST_TRACE"]
            }
          ],
          "no_new_creative_decisions" => true
        }
      ))
      storyboard_path = root.join("02A.yaml")
      storyboard = {
        "source_direction_map" => direction_path.to_s,
        "source_generation_map" => generation_path.to_s,
        "source_direction_contract" => {
          "source_01_path" => direction_path.to_s,
          "source_01_sha256" => Digest::SHA256.file(direction_path.to_s).hexdigest,
          "research_synthesis_id" => "RSI_TEST_TRACE",
          "projection_mode" => "selected_01_decisions_only"
        },
        "source_generation_contract" => {
          "source_02_path" => generation_path.to_s,
          "source_02_sha256" => Digest::SHA256.file(generation_path.to_s).hexdigest,
          "source_01_sha256" => Digest::SHA256.file(direction_path.to_s).hexdigest,
          "research_synthesis_id" => "RSI_TEST_TRACE",
          "projection_mode" => "pointer_only_02_allocation"
        },
        "master_storyboard" => [
          {
            "cut_id" => "C_TEST",
            "source_sections" => ["S00"],
            "front_planning_transfer_projection" => {
              "disposition" => "projected",
              "source_01_json_pointer" => "/lyric_to_scene_thinking/0/front_planning_transfer/02a_cut_keyframe_implication",
              "source_value_sha256" => Digest::SHA256.hexdigest(JSON.generate(front_planning_consequence)),
              "selected_consequence" => front_planning_consequence
            },
            "camera_intent_projection" => {
              "disposition" => "projected",
              "source_01_json_pointer" => "/lyric_to_scene_thinking/0/director_chain/camera_coverage_intent",
              "source_value_sha256" => Digest::SHA256.hexdigest(JSON.generate(camera_intent)),
              "selected_consequence" => camera_intent
            },
            "reference_direction_carry" => {
              "source_01_application_ids" => ["APP_TEST_TRACE"],
              "source_identities" => ["Founder reference TEST TRACE"],
              "selected_function" => "Use the lateral route to reveal the pickup.",
              "followed_surfaces" => [{"surface_type" => "camera_route", "lock" => "knee-height lateral track through layered depth"}],
              "cut_consequence" => "The member crosses the frame as the next space opens.",
              "reject_guard" => "Do not replace the lateral relation with a front portrait."
            },
            "camera_coverage_plan" => {
              "selected_route_id" => "CAM_TEST_TRACE",
              "candidate_routes" => [
                {
                  "route_id" => "CAM_TEST_TRACE",
                  "source_01_route_ref" => "01#/lyric_to_scene_thinking/0/director_chain/camera_route_spec",
                  "route_spec" => route
                }
              ]
            }
          }
        ]
      }
      storyboard_path.write(YAML.dump(storyboard))
      assert_empty IdolDirectionProjectionContract.validate_storyboard(storyboard_path, storyboard, root: root)

      omitted_projection = Marshal.load(Marshal.dump(storyboard))
      omitted_projection.delete("source_direction_contract")
      omitted_projection.delete("source_generation_contract")
      omitted_cut = omitted_projection.fetch("master_storyboard").first
      omitted_cut.delete("reference_direction_carry")
      omitted_cut.delete("camera_coverage_plan")
      omitted_cut.delete("front_planning_transfer_projection")
      omitted_cut.delete("camera_intent_projection")
      omission_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, omitted_projection, root: root)
      assert omission_errors.any? { |error| error.include?("source_direction_contract is required because 01 research_synthesis and 01 camera_direction.v2") }
      assert omission_errors.any? { |error| error.include?("source_generation_contract is required") }

      dropped_carries = Marshal.load(Marshal.dump(storyboard))
      dropped_cut = dropped_carries.fetch("master_storyboard").first
      dropped_cut.delete("reference_direction_carry")
      dropped_cut.delete("camera_coverage_plan")
      carry_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, dropped_carries, root: root)
      assert carry_errors.any? { |error| error.include?("02A section S00 dropped selected 01 application APP_TEST_TRACE from all cut carries") }
      assert carry_errors.any? { |error| error.include?("02A section S00 dropped structured 01 camera route CAM_TEST_TRACE from all cuts") }

      drifted_front_projection = Marshal.load(Marshal.dump(storyboard))
      drifted_front_projection.dig("master_storyboard", 0, "front_planning_transfer_projection")["selected_consequence"] = "Invented downstream planning consequence."
      front_projection_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, drifted_front_projection, root: root)
      assert front_projection_errors.any? { |error| error.include?("front_planning_transfer_projection.selected_consequence must exactly preserve") }

      stale_camera_projection = Marshal.load(Marshal.dump(storyboard))
      stale_camera_projection.dig("master_storyboard", 0, "camera_intent_projection")["source_value_sha256"] = "0" * 64
      camera_projection_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, stale_camera_projection, root: root)
      assert camera_projection_errors.any? { |error| error.include?("camera_intent_projection.source_value_sha256 is stale") }

      omitted_allocation = YAML.safe_load(generation_path.read)
      omitted_allocation.dig("direction_handoff_contract", "section_routes", 0)["reference_application_ids"] = []
      omitted_allocation.dig("direction_handoff_contract", "section_routes", 0)["camera_route_refs"] = []
      generation_path.write(YAML.dump(omitted_allocation))
      allocation_storyboard = Marshal.load(Marshal.dump(storyboard))
      allocation_storyboard.dig("source_generation_contract", "source_02_sha256").replace(Digest::SHA256.file(generation_path.to_s).hexdigest)
      allocation_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, allocation_storyboard, root: root)
      assert allocation_errors.any? { |error| error.include?("bound 02 section S00 dropped selected 01 application APP_TEST_TRACE") }
      assert allocation_errors.any? { |error| error.include?("bound 02 section S00 dropped structured 01 camera route CAM_TEST_TRACE") }

      generation_path.write(YAML.dump(
        "direction_handoff_contract" => {
          "source_01_path" => direction_path.to_s,
          "source_01_sha256" => Digest::SHA256.file(direction_path.to_s).hexdigest,
          "research_synthesis_id" => "RSI_TEST_TRACE",
          "projection_mode" => "selected_01_decisions_only",
          "section_routes" => [
            {
              "section_id" => "S00",
              "source_01_field_refs" => [
                "01#/lyric_to_scene_thinking/0/front_planning_transfer/02a_cut_keyframe_implication",
                "01#/lyric_to_scene_thinking/0/director_chain/camera_coverage_intent",
                "01#/lyric_to_scene_thinking/0/director_chain/camera_route_spec"
              ],
              "reference_application_ids" => ["APP_TEST_TRACE"],
              "camera_route_refs" => ["01#/lyric_to_scene_thinking/0/director_chain/camera_route_spec"],
              "generation_coverage_job" => "cover the lateral pickup",
              "must_preserve" => ["APP_TEST_TRACE", "CAM_TEST_TRACE"]
            }
          ],
          "no_new_creative_decisions" => true
        }
      ))

      other_generation_path = root.join("02-other.yaml")
      other_generation_path.write(generation_path.read)
      misbound_generation = Marshal.load(Marshal.dump(storyboard))
      misbound_generation.dig("source_generation_contract", "source_02_path").replace(other_generation_path.to_s)
      misbound_generation.dig("source_generation_contract", "source_02_sha256").replace(Digest::SHA256.file(other_generation_path.to_s).hexdigest)
      misbound_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, misbound_generation, root: root)
      assert misbound_errors.any? { |error| error.include?("source_generation_contract.source_02_path does not match source_generation_map") }

      drifted = Marshal.load(Marshal.dump(storyboard))
      drifted_cut = drifted.fetch("master_storyboard").first
      drifted_cut["source_sections"] = ["S01"]
      drifted_cut.fetch("reference_direction_carry")["cut_consequence"] = "Invented downstream consequence."
      drift_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, drifted, root: root)
      assert drift_errors.any? { |error| error.include?("targets S00 but cut belongs to S01") }
      assert drift_errors.any? { |error| error.include?("differs from canonical 01 application projection") }

      direction_path.write(direction_path.read + "\n# mutation\n")
      errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, storyboard, root: root)
      assert errors.any? { |error| error.include?("source_01_sha256 is stale") }
    end
  end

  def test_album_visual_asset_use_binds_readiness_manifest_ids_and_selected_consequence
    Dir.mktmpdir("idol-album-asset-projection-") do |directory|
      root = Pathname.new(directory)
      run_root = root.join("runs/2026-07-12/ASSET_LINEAGE")
      research_root = run_root.join("research")
      asset_root = root.join("assets/album")
      research_root.mkpath
      asset_root.mkpath

      manifest_path = asset_root.join("manifest.yaml")
      manifest_path.write(YAML.dump("schema_version" => "fixture.v1", "asset" => "ASSET_GLASS"))
      readiness_path = research_root.join("front-planning-readiness-v1.yaml")
      readiness_path.write(YAML.dump(
        "content" => {"content_id" => "ASSET_LINEAGE"},
        "album_visual_asset_plan" => {
          "asset_manifest" => manifest_path.relative_path_from(root).to_s,
          "assets" => [
            {
              "asset_id" => "ASSET_GLASS",
              "allowed_uses" => ["02A_storyboard_review", "02B_text_lock_only", "03V_prompt_video_handoff"]
            }
          ]
        }
      ))
      storyboard_path = run_root.join("02A-master-storyboard.yaml")
      selected_use = {
        "disposition" => "selected",
        "source_readiness_path" => readiness_path.relative_path_from(root).to_s,
        "source_readiness_sha256" => Digest::SHA256.file(readiness_path.to_s).hexdigest,
        "asset_manifest_path" => manifest_path.relative_path_from(root).to_s,
        "asset_manifest_sha256" => Digest::SHA256.file(manifest_path.to_s).hexdigest,
        "asset_ids" => ["ASSET_GLASS"],
        "selected_use_roles" => ["02A_storyboard_review", "02B_text_lock_only"],
        "selected_consequence" => "Preserve the selected wet-glass surface and cold reflection as the cut's visible material consequence."
      }
      storyboard = {
        "content_id" => "ASSET_LINEAGE",
        "master_storyboard" => [
          {
            "cut_id" => "C01_GLASS",
            "source_sections" => ["S00"],
            "album_visual_asset_use" => selected_use
          }
        ]
      }
      storyboard_path.write(YAML.dump(storyboard))
      assert_empty IdolDirectionProjectionContract.validate_storyboard(storyboard_path, storyboard, root: root)

      stale = Marshal.load(Marshal.dump(storyboard))
      stale.dig("master_storyboard", 0, "album_visual_asset_use")["asset_manifest_sha256"] = "0" * 64
      stale_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, stale, root: root)
      assert stale_errors.any? { |error| error.include?("album_visual_asset_use.asset_manifest_sha256 is stale") }

      unknown = Marshal.load(Marshal.dump(storyboard))
      unknown.dig("master_storyboard", 0, "album_visual_asset_use")["asset_ids"] = ["ASSET_UNKNOWN"]
      unknown_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, unknown, root: root)
      assert unknown_errors.any? { |error| error.include?("selects unknown readiness asset ASSET_UNKNOWN") }

      not_applicable = {
        "content_id" => "ASSET_LINEAGE",
        "master_storyboard" => [
          {
            "cut_id" => "C01_GLASS",
            "source_sections" => ["S00"],
            "album_visual_asset_use" => {
              "disposition" => "not_applicable",
              "reason" => "No current-title album visual asset was selected for this cut; its source image and 02A direction remain authoritative."
            }
          }
        ]
      }
      assert_empty IdolDirectionProjectionContract.validate_storyboard(storyboard_path, not_applicable, root: root)
    end
  end

  def test_explicit_not_applicable_lineage_does_not_activate_new_contract_for_legacy_camera_prose
    Dir.mktmpdir("idol-legacy-lineage-not-applicable-") do |directory|
      root = Pathname.new(directory)
      direction_path = root.join("01.yaml")
      direction_path.write(YAML.dump(
        "lyric_to_scene_thinking" => [
          {
            "section_or_beat_id" => "S00",
            "director_chain" => {
              "camera_coverage_intent" => "Legacy eye-level medium camera follows the hand across the table."
            }
          }
        ]
      ))
      storyboard_path = root.join("02A.yaml")
      storyboard = {
        "source_direction_map" => direction_path.to_s,
        "master_storyboard" => [
          {
            "cut_id" => "C_LEGACY",
            "source_sections" => ["S00"],
            "front_planning_transfer_projection" => {
              "disposition" => "not_applicable",
              "reason" => "No deep front-planning transfer exists for this legacy cut."
            },
            "camera_intent_projection" => {
              "disposition" => "not_applicable",
              "reason" => "No separately selected structured camera-intent projection exists for this legacy cut."
            }
          }
        ]
      }

      assert_empty IdolDirectionProjectionContract.validate_storyboard(storyboard_path, storyboard, root: root)
    end
  end

  def test_schema_15_exact_scene_hash_and_repetition_contract
    Dir.mktmpdir("idol-exact-scene-") do |directory|
      root = Pathname.new(directory)
      source = root.join("selected-cell.png")
      source.binwrite("selected exact pixels")
      exact = {
        "reference_id" => "REF_EXACT_CELL",
        "source_identity" => "Founder selected cell",
        "actual_path" => source.to_s,
        "sha256" => Digest::SHA256.file(source.to_s).hexdigest,
        "cell_or_frame_id" => "CELL_04",
        "application_mode" => "full_scene_direct",
        "inspection_action" => "pixel_inspected_current_revision",
        "reference_job" => "preserve the selected collision",
        "direct_follow_fields" => %w[action_type body_route expression_gaze camera_geometry composition_depth sequence_order],
        "preserve_exact" => ["collision, gaze and camera perspective"],
        "replace_only" => ["source character identity with the selected member"]
      }
      cut = lambda do |id|
        {
          "cut_id" => id,
          "source_sections" => ["S03"],
          "reference_contact_sheet_contract" => {
            "global_look_reference_ids" => ["ORION_LOOK"],
            "section_candidate_pool_refs" => [],
            "primary_exact_scene_reference" => Marshal.load(Marshal.dump(exact)),
            "secondary_exact_scene_references" => []
          }
        }
      end
      storyboard_path = root.join("02A.yaml")
      valid = {"schema_version" => "1.5", "master_storyboard" => [cut.call("C01_EXACT")]}
      storyboard_path.write(YAML.dump(valid))
      assert_empty IdolDirectionProjectionContract.validate_storyboard(storyboard_path, valid, root: root)

      stale = Marshal.load(Marshal.dump(valid))
      stale.dig("master_storyboard", 0, "reference_contact_sheet_contract", "primary_exact_scene_reference")["sha256"] = "0" * 64
      stale_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, stale, root: root)
      assert stale_errors.any? { |error| error.include?("primary_exact_scene_reference.sha256 is stale") }

      repeated = {"schema_version" => "1.5", "master_storyboard" => %w[C01_REPEAT C02_REPEAT C03_REPEAT].map { |id| cut.call(id) }}
      repeated_errors = IdolDirectionProjectionContract.validate_storyboard(storyboard_path, repeated, root: root)
      refute repeated_errors.any? { |error| error.include?("identical exact-scene reference set repeats") }
    end
  end
end
