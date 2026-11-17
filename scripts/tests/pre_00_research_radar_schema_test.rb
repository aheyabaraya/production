# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_storyline_density_locator_contract"

class Pre00ResearchRadarSchemaTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCHEMA = ROOT.join("schemas", "pre-00-research-radar.schema.json")
  HANDOFF_SCHEMA = ROOT.join("schemas", "pre-00-selection-handoff.schema.json")
  VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
  HANDOFF_BUILDER = ROOT.join("scripts", "idol_pre00_selection_handoff.rb")

  def test_active_v1_8_preserves_full_storyline_reference_hierarchies_and_fp_launch_lock
    with_fixture do |artifact, _document|
      result = validate(artifact)

      assert result[:status].success?, result[:stderr]
    end
  end

  def test_old_version_is_not_an_active_authoring_contract
    with_fixture do |artifact, document|
      document["schema_version"] = "1.4"
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_match(/1\.8/, result[:stderr])
    end
  end

  def test_pre00_cannot_prewrite_a_retired_00_or_downstream_lock
    with_fixture do |artifact, document|
      document["recommended_00_draft"] = {"core_message" => "wrong owner"}
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "recommended_00_draft"
    end
  end

  def test_every_candidate_must_handoff_questions_instead_of_finished_truth
    with_fixture do |artifact, document|
      document.fetch("candidate_routes").first.delete("route_seed")
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "route_seed"
    end
  end

  def test_target_and_trend_foundation_is_required_before_route_review
    with_fixture do |artifact, document|
      document.delete("target_trend_foundation")
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "target_trend_foundation"
    end
  end

  def test_selected_route_requires_founder_locked_target
    with_fixture do |artifact, document|
      document["status"] = "selected"
      document["founder_selection"] = {
        "action" => "select_one",
        "route_ids" => ["ROUTE_TEST_01"],
        "selection_note" => "Founder selected the route.",
        "next_song_direction_action" => "design_song_direction"
      }
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "founder_locked"

      document.fetch("target_trend_foundation")["lock_status"] = "founder_locked"
      artifact.write(YAML.dump(document))
      assert validate(artifact)[:status].success?
    end
  end

  def test_target_lock_compares_two_to_four_connections
    with_fixture do |artifact, document|
      document.fetch("target_trend_foundation")["connection_candidates"] = [
        document.fetch("target_trend_foundation").fetch("connection_candidates").first
      ]
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "connection_candidates"
    end
  end

  def test_each_target_connection_requires_one_main_and_one_to_two_supporting_references
    with_fixture do |artifact, document|
      document.fetch("target_trend_foundation").fetch("connection_candidates").first.delete("reference_preview")
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "reference_preview"
    end
  end

  def test_primary_target_requires_reference_audience_transplant_lineage
    with_fixture do |artifact, document|
      document.dig("target_trend_foundation", "primary_target").delete("reference_audience_lineage")
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "reference_audience_lineage"
    end
  end

  def test_selected_target_rejects_an_unverified_main_reference_song_audience
    with_fixture do |artifact, document|
      document["status"] = "selected"
      document.fetch("target_trend_foundation")["lock_status"] = "founder_locked"
      document.dig("target_trend_foundation", "primary_target", "reference_audience_lineage", "main_reference_song", "evidence")["evidence_status"] = "working_hypothesis"
      document["founder_selection"] = {
        "action" => "select_one",
        "route_ids" => ["ROUTE_TEST_01"],
        "selection_note" => "Founder selected the route.",
        "next_song_direction_action" => "design_song_direction"
      }
      artifact.write(YAML.dump(document))

      result = validate(artifact)

      refute result[:status].success?
      assert_includes result[:stderr], "verified_current_run"
    end
  end

  def test_selected_handoff_rejects_intersection_ids_that_do_not_match_selected_scene_profiles
    with_fixture do |artifact, document|
      document["status"] = "selected"
      document.fetch("target_trend_foundation")["lock_status"] = "founder_locked"
      document.dig("target_trend_foundation", "primary_target", "reference_audience_lineage", "intersection_decision")["selected_scene_source_ref_ids"] = ["REF_MEDIA_NARRATIVE_CC"]
      document["founder_selection"] = {
        "action" => "select_one",
        "route_ids" => ["ROUTE_TEST_01"],
        "selection_note" => "Founder selected the route.",
        "next_song_direction_action" => "design_song_direction"
      }
      root = artifact.dirname
      radar = root.join("automation", "pre-00-selected.yaml")
      radar.dirname.mkpath
      radar.write(YAML.dump(document))

      _stdout, stderr, status = Open3.capture3(
        "ruby", HANDOFF_BUILDER.to_s,
        "--root", root.to_s,
        "--radar", "automation/pre-00-selected.yaml",
        "--run", "runs/test-album/test-title/TEST_RUN",
        "--output", "runs/test-album/test-title/TEST_RUN/research/pre00-selection-handoff-v1.yaml",
        chdir: ROOT.to_s
      )

      refute status.success?
      assert_includes stderr, "intersection ids do not match selected scene profiles"
    end
  end

  def test_selected_handoff_rejects_a_stale_full_storyline_text_hash
    with_fixture do |artifact, document|
      select_document(document)
      document.dig("storyline_lineage", "pre00_storyline_original")["full_storyline_text"] << " The ending was silently changed."
      root = artifact.dirname
      radar = root.join("automation", "pre-00-selected.yaml")
      radar.dirname.mkpath
      radar.write(YAML.dump(document))

      _stdout, stderr, status = build_handoff(root, radar)

      refute status.success?
      assert_includes stderr, "full storyline text SHA-256 is stale"
    end
  end

  def test_selected_handoff_rejects_a_reference_snapshot_that_no_longer_matches_the_radar
    with_fixture do |artifact, document|
      select_document(document)
      document.dig("storyline_lineage", "pre00_storyline_original", "reference_bindings", 0, "source_snapshot", "short_note").replace("Silent divergence.")
      root = artifact.dirname
      radar = root.join("automation", "pre-00-selected.yaml")
      radar.dirname.mkpath
      radar.write(YAML.dump(document))

      _stdout, stderr, status = build_handoff(root, radar)

      refute status.success?
      assert_includes stderr, "source snapshot differs from the current radar"
    end
  end

  def test_selected_radar_builds_one_exact_copy_song_and_visual_handoff_without_new_authority
    with_fixture do |artifact, document|
      document["status"] = "selected"
      document.fetch("target_trend_foundation")["lock_status"] = "founder_locked"
      document["founder_selection"] = {
        "action" => "select_one",
        "route_ids" => ["ROUTE_TEST_01"],
        "selection_note" => "Founder selected route one and kept the locked target.",
        "next_song_direction_action" => "design_song_direction"
      }
      root = artifact.dirname
      radar = root.join("automation", "pre-00-selected.yaml")
      radar.dirname.mkpath
      radar.write(YAML.dump(document))
      write_locator_sheet!(root, radar)
      run = "runs/test-album/test-title/TEST_RUN"
      output = "#{run}/research/pre00-selection-handoff-v1.yaml"

      stdout, stderr, status = Open3.capture3(
        "ruby", HANDOFF_BUILDER.to_s,
        "--root", root.to_s,
        "--radar", "automation/pre-00-selected.yaml",
        "--run", run,
        "--output", output,
        "--created-at", "2026-08-04T12:00:00+09:00",
        chdir: ROOT.to_s
      )
      assert status.success?, [stdout, stderr].join("\n")

      handoff = root.join(output)
      schema_result = validate_schema(HANDOFF_SCHEMA, handoff)
      assert schema_result[:status].success?, schema_result[:stderr]
      payload = YAML.safe_load(handoff.read)
      assert_equal "idol-pre00-selection-handoff.v4", payload.fetch("schema_version")
      assert_equal document.fetch("storyline_lineage"), payload.dig("storyline_lineage", "value")
      assert_equal document.fetch("visual_reference_hierarchy"), payload.dig("visual_reference_hierarchy", "value")
      assert_equal document.fetch("audio_reference_hierarchy"), payload.dig("audio_reference_hierarchy", "value")
      assert_equal document.fetch("title_target_intersection"), payload.dig("title_target_intersection", "value")
      assert_equal document.fetch("fp_launch_lock"), payload.dig("fp_launch_lock", "value")
      assert_equal "/storyline_lineage", payload.dig("storyline_lineage", "source_pointer")
      assert_equal "PRE00_STORYLINE_V001", payload.dig("storyline_lineage", "value", "active_version", "version_id")
      assert_equal document.dig("target_trend_foundation", "primary_target"), payload.dig("selected_target", "value")
      assert_equal document.dig("target_trend_foundation", "primary_target", "reference_audience_lineage"), payload.dig("selected_target", "value", "reference_audience_lineage")
      assert_equal document.fetch("candidate_routes").first, payload.fetch("selected_routes").first.fetch("value")
      assert_equal document.fetch("founder_selection"), payload.dig("founder_response", "value")
      assert_equal false, payload.dig("authority_boundary", "paid_generation_authorized")
      assert_equal false, payload.dig("authority_boundary", "downstream_truth_authorized")
      assert_equal true, payload.dig("startup", "song_room", "duplicate_founder_brief_forbidden")
      assert_equal true, payload.dig("startup", "visual_preparation", "parallel_with_song_conversation")
      assert_equal 64, payload.dig("integrity", "handoff_payload_sha256").length
      assert_equal %w[song_room_context front_planning section_01 section_02a section_02b section_03v section_04], payload.dig("integrity", "storyline_consumer_chain")

      inspect_stdout, inspect_stderr, inspect_status = Open3.capture3(
        "ruby", HANDOFF_BUILDER.to_s,
        "--root", root.to_s,
        "--run", run,
        "--inspect", output,
        chdir: ROOT.to_s
      )
      assert inspect_status.success?, [inspect_stdout, inspect_stderr].join("\n")
      inspected = JSON.parse(inspect_stdout)
      assert_equal true, inspected["available"]
      assert_equal output, inspected["path"]
      assert_equal document.dig("target_trend_foundation", "primary_target"), inspected.dig("context", "selectedTarget")
      assert_equal document.fetch("candidate_routes").first, inspected.dig("context", "selectedRoutes", 0)
      assert_equal document.fetch("storyline_lineage"), inspected.dig("context", "storylineLineage")

      _repeat_stdout, repeat_stderr, repeat_status = Open3.capture3(
        "ruby", HANDOFF_BUILDER.to_s,
        "--root", root.to_s,
        "--radar", "automation/pre-00-selected.yaml",
        "--run", run,
        "--output", output,
        "--created-at", "2026-08-04T12:00:00+09:00",
        chdir: ROOT.to_s
      )
      refute repeat_status.success?
      assert_includes repeat_stderr, "output already exists"

      changed = YAML.safe_load(radar.read, aliases: true)
      changed["founder_selection"]["selection_note"] = "Changed after handoff."
      radar.write(YAML.dump(changed))
      _stale_stdout, stale_stderr, stale_status = Open3.capture3(
        "ruby", HANDOFF_BUILDER.to_s,
        "--root", root.to_s,
        "--run", run,
        "--inspect", output,
        chdir: ROOT.to_s
      )
      refute stale_status.success?
      assert_includes stale_stderr, "source radar SHA-256 is stale"
    end
  end

  def test_selected_handoff_requires_a_density_locator_sheet
    with_fixture do |artifact, document|
      select_document(document)
      root = artifact.dirname
      radar = root.join("automation", "pre-00-selected.yaml")
      radar.dirname.mkpath
      radar.write(YAML.dump(document))

      _stdout, stderr, status = build_handoff(root, radar)

      refute status.success?
      assert_includes stderr, "density locator sheet missing"
    end
  end

  def test_handoff_builder_rejects_a_radar_path_that_escapes_its_declared_root
    with_fixture do |artifact, document|
      document["status"] = "selected"
      document.fetch("target_trend_foundation")["lock_status"] = "founder_locked"
      document["founder_selection"] = {
        "action" => "select_one",
        "route_ids" => ["ROUTE_TEST_01"],
        "selection_note" => "Founder selected route one.",
        "next_song_direction_action" => "design_song_direction"
      }
      artifact.write(YAML.dump(document))
      declared_root = artifact.dirname.join("contained-root")
      declared_root.mkpath
      _stdout, stderr, status = Open3.capture3(
        "ruby", HANDOFF_BUILDER.to_s,
        "--root", declared_root.to_s,
        "--radar", "../#{artifact.basename}",
        "--run", "runs/test-album/test-title/TEST_RUN",
        "--output", "runs/test-album/test-title/TEST_RUN/research/pre00-selection-handoff-v1.yaml",
        chdir: ROOT.to_s
      )

      refute status.success?
      assert_includes stderr, "radar path escapes repository root"
    end
  end

  def test_handoff_inspection_rejects_rebound_sources_even_with_current_value_and_payload_hashes
    with_selected_handoff do |root, document, path, original|
      cases = [
        ["selected_routes[0]", ->(payload) {
          payload["selected_routes"][0] = test_binding("/candidate_routes/1", document.fetch("candidate_routes")[1])
        }],
        ["selected_connection", ->(payload) {
          payload["selected_connection"] = test_binding("/target_trend_foundation/connection_candidates/1", document.dig("target_trend_foundation", "connection_candidates", 1))
        }],
        ["reference_preview", ->(payload) {
          payload["reference_preview"] = test_binding("/target_trend_foundation/connection_candidates/1/reference_preview", document.dig("target_trend_foundation", "connection_candidates", 1, "reference_preview"))
        }],
        ["selected_routes count", ->(payload) {
          payload["selected_routes"] << payload["selected_routes"].first
        }],
        ["message_progression", ->(payload) {
          payload["message_progression"] = payload.fetch("emotional_progression")
        }],
        ["must_and_avoid.rejection_triggers", ->(payload) {
          payload["must_and_avoid"]["rejection_triggers"] = payload.dig("must_and_avoid", "attraction_triggers")
        }]
      ]
      cases.each do |label, change|
        payload = Marshal.load(Marshal.dump(original))
        change.call(payload)
        write_handoff_with_current_hash(path, payload)

        stdout, stderr, status = inspect_handoff(root, path)

        refute status.success?, "#{label} accepted a different source despite unchanged Founder selection: #{stdout}"
        assert_includes stderr, label
        assert_includes stderr, "Founder-selected source"
      end
    end
  end

  def test_handoff_inspection_preserves_combined_route_order_and_nonfirst_connection
    route_ids = %w[ROUTE_TEST_03 ROUTE_TEST_01]
    with_selected_handoff(route_ids: route_ids, connection_index: 1) do |root, document, path, original|
      stdout, stderr, status = inspect_handoff(root, path)
      assert status.success?, [stdout, stderr].join("\n")
      context = JSON.parse(stdout).fetch("context")
      assert_equal route_ids, context.fetch("selectedRoutes").map { |route| route.fetch("route_id") }
      assert_equal document.dig("target_trend_foundation", "connection_candidates", 1), context.fetch("selectedConnection")
      assert_equal document.fetch("storyline_lineage"), context.fetch("storylineLineage")

      [original.fetch("selected_routes").reverse, original.fetch("selected_routes").take(1)].each do |changed_routes|
        payload = Marshal.load(Marshal.dump(original))
        payload["selected_routes"] = changed_routes
        write_handoff_with_current_hash(path, payload)
        _stdout, stderr, status = inspect_handoff(root, path)
        refute status.success?
        assert_includes stderr, "Founder-selected source"
      end
    end
  end

  private

  def with_selected_handoff(route_ids: ["ROUTE_TEST_01"], connection_index: 0)
    with_fixture do |artifact, document|
      select_document(document)
      document["founder_selection"]["action"] = route_ids.length > 1 ? "combine_routes" : "select_one"
      document["founder_selection"]["route_ids"] = route_ids
      document["storyline_lineage"]["pre00_storyline_original"]["selected_route_ids"] = route_ids
      document["target_trend_foundation"]["primary_target"]["selected_connection_id"] = document.dig("target_trend_foundation", "connection_candidates", connection_index, "connection_id")
      root = artifact.dirname
      radar = root.join("automation", "pre-00-selected.yaml")
      radar.dirname.mkpath
      radar.write(YAML.dump(document))
      write_locator_sheet!(root, radar)
      stdout, stderr, status = build_handoff(root, radar)
      assert status.success?, [stdout, stderr].join("\n")
      path = root.join("runs/test-album/test-title/TEST_RUN/research/pre00-selection-handoff-v1.yaml")
      yield root, document, path, YAML.safe_load(path.read)
    end
  end

  def test_binding(pointer, value)
    {"source_pointer" => pointer, "value" => value, "value_sha256" => canonical_value_sha(value)}
  end

  def write_handoff_with_current_hash(path, payload)
    unsigned = Marshal.load(Marshal.dump(payload))
    unsigned.fetch("integrity").delete("handoff_payload_sha256")
    payload["integrity"]["handoff_payload_sha256"] = canonical_value_sha(unsigned)
    path.write(YAML.dump(payload))
  end

  def inspect_handoff(root, path)
    Open3.capture3(
      "ruby", HANDOFF_BUILDER.to_s,
      "--root", root.to_s,
      "--run", "runs/test-album/test-title/TEST_RUN",
      "--inspect", path.relative_path_from(root).to_s,
      chdir: ROOT.to_s
    )
  end

  def with_fixture
    Dir.mktmpdir("pre00-research-radar-v1-8") do |directory|
      artifact = Pathname.new(directory).join("pre-00-research-radar.yaml")
      document = fixture_document
      artifact.write(YAML.dump(document))
      yield artifact, document
    end
  end

  def fixture_document
    refs = {
      "REF_AUDIENCE_AA" => research_input("Audience source", "audience", "audience_behavior"),
      "REF_TREND_BB" => research_input("Trend source", "trend", "current_opportunity"),
      "REF_SONG_AA" => research_input("Song source", "song", "song_structure"),
      "REF_MEDIA_NARRATIVE_BB" => research_input("Narrative source", "media_narrative", "media_narrative"),
      "REF_FASHION_CC" => research_input("Fashion source", "fashion", "silhouette"),
      "REF_IDOL_DD" => research_input("Idol source", "idol", "idol_identity")
    }
    ref_ids = refs.keys

    lineage = storyline_lineage(refs)
    document = {
      "schema_version" => "1.8",
      "radar_id" => "RADAR_TEST_001",
      "date" => "2026-07-25",
      "mode" => "manual",
      "status" => "founder_review",
      "research_policy" => {
        "method_basis" => "Current public evidence plus Founder-supplied source review.",
        "current_research_required" => true,
        "minimum_reference_count" => 6,
        "candidate_route_count" => 3,
        "reference_families" => %w[audience trend song media_narrative fashion idol],
        "unit_registry" => "assets/unit-registry.yaml",
        "reference_depth_goal" => "Find defensible route questions before selecting or producing audio.",
        "combination_rule" => "Each route combines all four creative route families under the target/trend foundation.",
        "unity_rule" => "One song question and one coherent screen-world question govern each route.",
        "ref_id_integrity_rule" => "Every source link resolves to research_inputs.",
        "allowed_output" => "target_trend_locked_route_brief_before_song_selection",
        "handoff_target" => "locked_target_to_song_direction_and_candidate_audio_path"
      },
      "research_freshness" => {
        "policy_ref" => "Current evidence is rechecked before song selection.",
        "recheck_before_song_selection" => ["availability", "source meaning"],
        "durable_record_rule" => "Preserve source identity and observation date.",
        "bank_record_rule" => "Do not promote provisional route claims as reusable truth."
      },
      "research_vectors" => [
        {
          "vector_id" => "target_empathy_message",
          "research_question" => "Which listener tension can the selected song direction genuinely serve?",
          "sample_rule" => "Compare evidence from every reference family.",
          "extraction_fields" => ["observable attraction", "rejection trigger"],
          "downstream_roles" => ["pre00_target_trend_lock", "song_direction_design", "front_planning_locked_target_translation"],
          "reject_if_missing" => "Hold a route that cannot connect listener reward to a song question."
        }
      ],
      "research_inputs" => refs,
      "target_trend_foundation" => target_trend_foundation,
      "candidate_routes" => 3.times.map { |index| candidate_route(index + 1, ref_ids) },
      "storyline_lineage" => lineage,
      "founder_decision_needed" => ["Select, combine, hold, or reject the candidate route direction."]
    }
    document.merge(migration_fields(refs, lineage))
  end

  def migration_fields(refs, lineage)
    typed_slot = lambda do |slot, ref_id, function|
      {
        "slot_id" => slot,
        "source_ref_id" => ref_id,
        "source_identity" => refs.fetch(ref_id).fetch("title"),
        "selected_locator" => "Exact bounded #{slot} surface.",
        "named_function" => function,
        "evidence_status" => "verified_current_run",
        "disposition" => "applied",
        "transfer_boundary" => "Transfer only the named function.",
        "do_not_transfer" => ["source identity", "unselected surface"]
      }
    end
    slots = {
      "A" => typed_slot.call("A", "REF_MEDIA_NARRATIVE_BB", "governing visual event grammar"),
      "B" => typed_slot.call("B", "REF_FASHION_CC", "bounded material and silhouette support"),
      "C" => typed_slot.call("C", "REF_IDOL_DD", "bounded performer readability support"),
      "X" => typed_slot.call("X", "REF_SONG_AA", "main song-specific reference"),
      "Y" => typed_slot.call("Y", "REF_MEDIA_NARRATIVE_BB", "bounded audio-to-story tension support"),
      "Z" => typed_slot.call("Z", "REF_IDOL_DD", "bounded performance-release support")
    }
    audience_template = {
      "audience_definition" => "Viewers who value distinct member contrast and visible agency.",
      "viewer_situation" => "They want a controlled build whose choices stay legible.",
      "desired_reward" => "An earned collective turn.",
      "literacy_and_codes" => ["member contrast", "pressure and release"],
      "platform_behavior" => ["replays the turn and compares contributions"],
      "attraction_triggers" => ["distinct actions accumulating into one event"],
      "rejection_triggers" => ["interchangeable delivery"]
    }
    evidence = {
      "source_ref_ids" => ["REF_SONG_AA", "REF_AUDIENCE_AA"],
      "evidence_status" => "verified_current_run",
      "counterevidence" => ["Established artist context may account for part of the reward."],
      "freshness_note" => "Checked for this current run."
    }
    active = lineage.fetch("active_version")
    {
      "visual_reference_hierarchy" => {
        "main_a" => slots.fetch("A"),
        "subs_b_c" => [slots.fetch("B"), slots.fetch("C")],
        "hierarchy_rule" => "A_governs_visual_direction_B_and_C_supply_distinct_named_functions_without_averaging_or_replacing_A"
      },
      "audio_reference_hierarchy" => {
        "main_x" => slots.fetch("X"),
        "subs_y_z" => [slots.fetch("Y"), slots.fetch("Z")],
        "hierarchy_rule" => "X_is_the_main_song_specific_reference_Y_and_Z_supply_distinct_bounded_audio_functions"
      },
      "reference_transfer_exclusion_map" => slots.values.map do |slot|
        {
          "slot_id" => slot.fetch("slot_id"),
          "source_ref_id" => slot.fetch("source_ref_id"),
          "transfer_functions" => [slot.fetch("named_function")],
          "exclusions" => slot.fetch("do_not_transfer")
        }
      end,
      "audience_profiles" => [
        {
          "profile_id" => "AUD_PROFILE_X_SONG",
          "reference_slot" => "X",
          "profile_scope" => "song_specific",
          "audience_profile" => audience_template,
          "evidence" => evidence,
          "classification" => "target_base_input"
        },
        {
          "profile_id" => "AUD_PROFILE_X_ARTIST_SEGMENT",
          "reference_slot" => "X",
          "profile_scope" => "artist_relevant_segment",
          "audience_profile" => audience_template,
          "evidence" => evidence,
          "classification" => "target_base_input"
        },
        {
          "profile_id" => "AUD_PROFILE_A_SCENE",
          "reference_slot" => "A",
          "profile_scope" => "scene_or_surface_reference",
          "audience_profile" => audience_template,
          "evidence" => evidence,
          "classification" => "aligned_narrowing"
        }
      ],
      "x_reference_audience_envelope" => {
        "main_x_source_ref_id" => "REF_SONG_AA",
        "song_specific_profile_id" => "AUD_PROFILE_X_SONG",
        "artist_relevant_segment_profile_id" => "AUD_PROFILE_X_ARTIST_SEGMENT",
        "evidence_status" => "verified_current_run",
        "counterevidence" => ["Do not generalize the complete artist fandom."],
        "envelope_definition" => "The verified overlap of song-specific listeners and the relevant artist segment.",
        "exclusions" => ["unbounded artist fandom"]
      },
      "title_target_intersection" => {
        "status" => "resolved",
        "evidence_status" => "verified_current_run",
        "x_envelope_role" => "base",
        "included_reference_profile_ids" => ["AUD_PROFILE_X_SONG", "AUD_PROFILE_X_ARTIST_SEGMENT", "AUD_PROFILE_A_SCENE"],
        "classified_reference_profiles" => [{"profile_id" => "AUD_PROFILE_A_SCENE", "classification" => "aligned_narrowing", "reason" => "Adds visible consequence without replacing the song reward."}],
        "final_target_definition" => "Listeners who value distinct member contrast and visible agency in a reactive world.",
        "viewer_situation" => "They want personal choices to accumulate into a legible shared turn.",
        "desired_reward" => "A controlled build with a consequential release.",
        "code_literacy" => ["member contrast", "cause and effect"],
        "platform_behavior" => ["replays the turning point"],
        "rejection_triggers" => ["detached spectacle"],
        "counterevidence" => ["The restrained entry may narrow immediate-impact viewers."],
        "intersection_rule" => "X_audience_envelope_is_the_base_other_reference_profiles_may_narrow_or_bridge_but_never_form_an_unbounded_fandom_union"
      },
      "message_progression" => progression_fixture("agency becomes visible through accumulated choices"),
      "emotional_progression" => progression_fixture("pressure turns into earned collective release"),
      "sequence_runs" => [],
      "fp_autonomy_envelope" => {
        "director_may_author_three_complete_routes" => true,
        "director_may_develop_without_mid_gate" => true,
        "founder_intervention_points" => ["direction_alignment", "g40_core_branch_authorization"],
        "external_or_paid_actions_authorized" => false
      },
      "source_acquisition_authority" => {"status" => "not_authorized", "scope" => [], "authority_id" => nil},
      "planning_image_authority" => {"status" => "not_authorized", "scope" => [], "authority_id" => nil, "paid_generation_authorized" => false},
      "operating_observation" => {"target_duration_minutes" => nil, "founder_dialogue_seconds" => nil, "source_blocked_seconds" => nil, "song_creation_seconds" => nil, "timing_is_gate" => false},
      "fp_launch_lock" => {
        "status" => "locked",
        "target_evidence_status" => "verified_current_run",
        "active_storyline_version_id" => active.fetch("version_id"),
        "active_storyline_sha256" => active.fetch("full_storyline_text_sha256"),
        "visual_reference_slots" => %w[A B C],
        "audio_reference_slots" => %w[X Y Z],
        "timing_used_as_gate" => false
      }
    }
  end

  def progression_fixture(turn)
    {
      "opening_state" => "The system appears complete while individual agency is constrained.",
      "ordered_turns" => [turn, "Distinct responses accumulate into one shared consequence."],
      "ending_or_afterimage" => "The first calibration mark remains permanently offset.",
      "non_repetition_rule" => "Each turn changes viewer knowledge or world state rather than restating one thesis."
    }
  end

  def storyline_lineage(refs)
    text = <<~STORYLINE.strip
      The video opens inside a calibration city that appears complete but keeps every member on a route chosen by the system. One member notices that the guide line does not match her own pace, and her deliberate refusal becomes the first visible break rather than an abstract declaration. The other members encounter different forms of the same pressure; each response changes a small, persistent part of the city, so their separate actions accumulate instead of repeating one heroic beat. At the song's turn, the routes stop behaving as private obstacles and reveal one shared mechanism that can be redirected only when the members keep their distinct choices legible. The release is not a victory montage: the city continues to resist, but its guides now follow choices already made by the members. The ending returns to the first calibration mark, left permanently offset as a quiet record that the system has changed.
    STORYLINE
    text_sha = Digest::SHA256.hexdigest(text)
    bindings = %w[REF_SONG_AA REF_MEDIA_NARRATIVE_BB REF_IDOL_DD].map do |ref_id|
      snapshot = refs.fetch(ref_id)
      {
        "source_ref_id" => ref_id,
        "source_json_pointer" => "/research_inputs/#{ref_id}",
        "source_value_sha256" => canonical_value_sha(snapshot),
        "source_snapshot" => Marshal.load(Marshal.dump(snapshot)),
        "selected_locator" => "The bounded source moment named in the PRE-00 research input.",
        "storyline_function" => "Supports one specific pressure, choice, or accumulated-world-response function in the full flow.",
        "transfer_boundary" => "Transfer the function and relationship only; do not reproduce source identity or unselected scene grammar.",
        "do_not_transfer" => ["source characters", "source world identity", "unselected styling surface"],
        "affected_story_scope" => "Opening pressure through the shared turn and ending afterimage.",
        "disposition" => ref_id == "REF_IDOL_DD" ? "context_only" : "applied_to_storyline",
        "direct_visual_use_authorized" => false
      }
    end
    {
      "contract_version" => "pre00_storyline_lineage.v1",
      "pre00_storyline_original" => {
        "version_id" => "PRE00_STORYLINE_V001",
        "parent_version_id" => nil,
        "parent_full_storyline_text_sha256" => nil,
        "full_storyline_text" => text,
        "full_storyline_text_sha256" => text_sha,
        "selected_route_ids" => ["ROUTE_TEST_01"],
        "reference_bindings" => bindings,
        "authorship_receipt" => {
          "authored_by" => "assigned_director",
          "authoring_method" => "assigned_director_model_authored_natural_language",
          "authored_at" => "2026-08-13T10:00:00+09:00",
          "founder_status" => "selected",
          "verbatim_full_text_preserved" => true
        },
        "execution_detail_boundary" => {
          "natural_language_whole_mv_flow" => true,
          "timecodes" => false,
          "camera_geometry" => false,
          "core_or_branch_cuts" => false,
          "generation_prompts" => false
        }
      },
      "pre00_storyline_revisions" => [],
      "active_version" => {
        "version_id" => "PRE00_STORYLINE_V001",
        "version_json_pointer" => "/storyline_lineage/pre00_storyline_original",
        "full_storyline_text_sha256" => text_sha
      },
      "contextual_density_review" => {
        "method" => "assigned_director_contextual_review_no_machine_similarity_or_numeric_density_score",
        "reviewed_version_id" => "PRE00_STORYLINE_V001",
        "reviewed_full_storyline_text_sha256" => text_sha,
        "decision" => "pass",
        "opening_to_ending_flow_review" => "The opening condition, accumulation, shared turn, release, and afterimage form one readable whole-video flow.",
        "causal_or_associative_continuity_review" => "Every local choice leaves a persistent state that motivates the shared turn.",
        "state_and_turn_specificity_review" => "Pressure, refusal, accumulation, redirection, and the retained offset mark are distinguishable states.",
        "reference_influence_review" => "Each connected reference has a bounded function and explicit exclusions instead of a whole-source copy instruction.",
        "ending_afterimage_review" => "The final offset calibration mark preserves the consequence without restating the thesis.",
        "execution_detail_deferral_review" => "The text contains no timecode, camera geometry, Core/Branch Cut, or generation-prompt authorship."
      },
      "preservation_contract" => {
        "original_rule" => "pre00_storyline_original_is_immutable_and_is_never_overwritten_or_deleted",
        "revision_rule" => "every_change_appends_a_new_full_text_version_with_parent_hash_reason_changed_passages_and_preserved_invariants",
        "reference_rule" => "every_storyline_reference_travels_with_exact_source_snapshot_hash_function_transfer_boundary_and_do_not_transfer_scope",
        "downstream_rule" => "song_room_front_planning_01_02a_02b_03v_and_04_consume_the_original_active_version_revision_history_and_reference_bindings",
        "summary_rule" => "whole_film_progression_and_other_summaries_are_indexes_only_and_never_substitute_for_the_full_storyline"
      }
    }
  end

  def canonical_value_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_test_value(value)))
  end

  def canonical_test_value(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical_test_value(value.fetch(key))] }
    when Array
      value.map { |item| canonical_test_value(item) }
    else
      value
    end
  end

  def select_document(document)
    document["status"] = "selected"
    document.fetch("target_trend_foundation")["lock_status"] = "founder_locked"
    document["founder_selection"] = {
      "action" => "select_one",
      "route_ids" => ["ROUTE_TEST_01"],
      "selection_note" => "Founder selected the route.",
      "next_song_direction_action" => "design_song_direction"
    }
  end

  def build_handoff(root, radar)
    Open3.capture3(
      "ruby", HANDOFF_BUILDER.to_s,
      "--root", root.to_s,
      "--radar", radar.relative_path_from(root).to_s,
      "--run", "runs/test-album/test-title/TEST_RUN",
      "--output", "runs/test-album/test-title/TEST_RUN/research/pre00-selection-handoff-v1.yaml",
      chdir: ROOT.to_s
    )
  end

  def write_locator_sheet!(root, radar)
    radar.sub_ext(".density-locators.yaml").write(
      YAML.dump(
        IdolStorylineDensityLocatorContract.complete_sheet(radar.relative_path_from(root).to_s)
      )
    )
  end

  def target_trend_foundation
    {
      "lock_status" => "proposed",
      "connection_candidates" => [
        {
          "connection_id" => "TARGET_CONNECTION_AGENCY",
          "connection_type" => "actual_audience_overlap",
          "audience_definition" => "Viewers who want precise agency stories rather than generic triumph.",
          "response_mechanism" => "Pressure becomes a legible choice with a consequence.",
          "expected_song_reward" => "An earned stop-and-release turn.",
          "expected_screen_reward" => "One consequential choice that changes the world state.",
          "reference_preview" => reference_preview(
            "REF_MEDIA_NARRATIVE_BB",
            "REF_IDOL_DD",
            "The main scene grammar establishes consequence; the supporting idol reference tests readable ownership."
          ),
          "evidence_ref_ids" => ["REF_AUDIENCE_AA", "REF_TREND_BB"],
          "counterevidence" => ["The restrained entry may underserve viewers seeking immediate impact."],
          "recommendation" => "primary"
        },
        {
          "connection_id" => "TARGET_CONNECTION_SURFACE",
          "connection_type" => "surface_only_similarity",
          "audience_definition" => "Viewers attracted only by the current visual surface.",
          "response_mechanism" => "Immediate recognition without a deeper shared reward.",
          "expected_song_reward" => "A familiar current sound surface.",
          "expected_screen_reward" => "Fast visual recognition.",
          "reference_preview" => reference_preview(
            "REF_IDOL_DD",
            "REF_FASHION_CC",
            "The current idol surface leads while the styling support shows why this remains only surface similarity."
          ),
          "evidence_ref_ids" => ["REF_TREND_BB"],
          "counterevidence" => ["No durable audience need connects this surface to the route."],
          "recommendation" => "test_only"
        }
      ],
      "primary_target" => {
        "selected_connection_id" => "TARGET_CONNECTION_AGENCY",
        "audience_definition" => "Viewers who want precise agency stories rather than generic triumph.",
        "viewer_situation" => "They feel constrained by an external script.",
        "desire_or_tension" => "They want self-directed action without losing emotional complexity.",
        "audience_promise" => "A controlled pressure-and-release experience with an earned turn.",
        "attraction_triggers" => ["Precise stop-and-release mechanics"],
        "rejection_triggers" => ["Disconnected mood images"],
        "do_not_serve" => ["Generic empowerment montage"],
        "platform_behavior" => ["Revisits a legible turning point and compares interpretations"],
        "reference_audience_lineage" => reference_audience_lineage
      },
      "trend_synthesis" => {
        "durable_signals" => ["Character action remains more memorable than trend decoration"],
        "current_opportunities" => ["Controlled visual restraint before a sharp release"],
        "expiry_or_volatility" => ["Recheck the current platform expression before song selection"],
        "do_not_copy" => ["Do not reproduce a currently popular creator surface"],
        "source_ref_ids" => ["REF_TREND_BB"]
      },
      "content_contract" => {
        "content_pillars" => ["Agency under pressure"],
        "familiar_codes_to_retain" => ["Readable member identity"],
        "novelty_or_tension_to_add" => ["The world visibly resists the member's choice"],
        "song_reward_requirements" => ["The selected song must earn a clear pressure-to-release turn"],
        "screen_reward_requirements" => ["The viewer must see one consequential choice"]
      },
      "evidence" => {
        "audience_source_ref_ids" => ["REF_AUDIENCE_AA"],
        "counterevidence" => ["A restraint-led route may underserve viewers seeking immediate impact"],
        "evidence_strength" => "medium",
        "freshness_note" => "Audience and trend sources were checked for this radar date."
      },
      "downstream_rule" => "the_locked_target_is_a_fixed_input;_song_and_front_planning_may_test_fit_but_must_not_silently_reselect_it"
    }
  end

  def reference_audience_lineage
    {
      "contract_version" => "reference_audience_transplant.v1",
      "brand_baseline_role" => "context_only_not_title_target",
      "main_reference_song" => {
        "source_ref_id" => "REF_SONG_AA",
        "artist_or_group" => "Reference Artist",
        "song_title" => "Reference Song",
        "locator_note" => "Exact official song and bounded release context.",
        "audience_profile" => {
          "audience_definition" => "Listeners who seek precise character contrast and an earned turn.",
          "viewer_situation" => "They want distinct voices to stay legible inside one group event.",
          "desired_reward" => "A controlled build that resolves into shared agency.",
          "literacy_and_codes" => ["member-to-member contrast", "sectional pressure and release"],
          "platform_behavior" => ["replays the turn and compares member delivery"],
          "attraction_triggers" => ["distinct entrances that accumulate into one event"],
          "rejection_triggers" => ["interchangeable member delivery"]
        },
        "evidence" => {
          "source_ref_ids" => ["REF_SONG_AA", "REF_AUDIENCE_AA"],
          "evidence_status" => "verified_current_run",
          "counterevidence" => ["The reference reward may depend on an established artist context."],
          "freshness_note" => "Song-specific audience evidence was checked for this radar."
        },
        "transplant_status" => "adopted_as_target_base"
      },
      "scene_reference_audiences" => [
        {
          "source_ref_id" => "REF_MEDIA_NARRATIVE_BB",
          "locator_note" => "Exact official scene or bounded sequence.",
          "audience_profile" => {
            "audience_definition" => "Viewers who reward legible choice inside a reactive world.",
            "viewer_situation" => "They want a world rule to make character action consequential.",
            "desired_reward" => "A visible state change caused by one choice.",
            "literacy_and_codes" => ["cause-and-effect world response"],
            "platform_behavior" => ["replays the trigger and consequence"],
            "attraction_triggers" => ["observable environmental resistance"],
            "rejection_triggers" => ["detached mood montage"]
          },
          "evidence" => {
            "source_ref_ids" => ["REF_MEDIA_NARRATIVE_BB", "REF_AUDIENCE_AA"],
            "evidence_status" => "verified_current_run",
            "counterevidence" => ["The scene grammar may over-narrow the song audience."],
            "freshness_note" => "The exact scene and its audience function were rechecked for this radar."
          },
          "fit_disposition" => "aligned_narrowing",
          "effect_on_base_target" => "Narrows the song audience toward viewers who need visible consequence.",
          "selected_for_intersection" => true
        }
      ],
      "intersection_decision" => {
        "status" => "resolved",
        "base_source_ref_id" => "REF_SONG_AA",
        "selected_scene_source_ref_ids" => ["REF_MEDIA_NARRATIVE_BB"],
        "final_target_definition" => "Listeners who value distinct member contrast and visible agency inside a reactive world.",
        "shared_viewer_situation" => "They want an ensemble choice to change the system around it.",
        "shared_reward" => "Distinct voices accumulate into one consequential release.",
        "shared_literacy_and_codes" => ["member contrast", "cause-and-effect world response"],
        "shared_platform_behavior" => ["replays the turning point and compares member contribution"],
        "preserved_rejection_triggers" => ["interchangeable voices", "detached spectacle"],
        "exclusions" => ["viewers seeking only a familiar surface without the song reward"],
        "decision_rule" => "main_reference_song_audience_is_the_base;_selected_scene_audiences_may_narrow_or_bridge_but_never_silently_replace_or_union"
      }
    }
  end

  def reference_preview(main_ref_id, supporting_ref_id, comparison_note)
    {
      "main_reference" => {
        "source_ref_id" => main_ref_id,
        "role" => "main_governing_candidate",
        "medium" => "music_video",
        "locator_note" => "Named bounded scene or sequence for Founder preview.",
        "target_response_reason" => "Shows the clearest visual form of the proposed audience reward.",
        "proposed_transfer_function" => "Governing situation and screen grammar if the target is selected.",
        "mismatch_risk" => "May overstate the current route before the selected song exists."
      },
      "supporting_references" => [
        {
          "source_ref_id" => supporting_ref_id,
          "role" => "supporting_candidate",
          "medium" => "music_video",
          "locator_note" => "Named bounded supporting scene for comparison.",
          "target_response_reason" => "Adds one missing attraction or readability function.",
          "proposed_transfer_function" => "Support only; it does not replace the main grammar.",
          "mismatch_risk" => "Could flatten the connection if treated as equal governing direction."
        }
      ],
      "comparison_note" => comparison_note,
      "preview_boundary" => "target_selection_evidence_only;_front_planning_must_reinspect_and_bind_final_section_use"
    }
  end

  def research_input(title, family, lane)
    {
      "title" => title,
      "path_or_url" => "source://#{family}",
      "reference_family" => family,
      "reference_lane" => lane,
      "short_note" => "Observed evidence for a bounded route question.",
      "useful_function" => "Tests one route assumption without locking downstream creative truth.",
      "source_use_boundary" => "Research evidence only until a later owning stage applies it."
    }
  end

  def candidate_route(index, ref_ids)
    {
      "route_id" => format("ROUTE_TEST_%02d", index),
      "route_name" => "Candidate route #{index}",
      "situation_feeling" => "Controlled pressure that may open into deliberate agency.",
      "provisional_message" => "A question about choosing action under pressure.",
      "provisional_song_direction" => "Test a restrained verse against a sharply released hook.",
      "locked_target_fit" => {
        "target_reward_served" => "The route makes agency feel earned rather than announced.",
        "response_mechanism" => "A precise stop-and-release song and screen turn.",
        "route_specific_risk" => "The release may feel too late for the locked target.",
        "validation_question" => "Does an actual take make the release feel earned?"
      },
      "recommended_unit" => {
        "unit_code" => "EXEC_06",
        "unit_purpose" => "Test a provisional vocal and performance color.",
        "member_codes" => ["M01"],
        "unit_fit_reason" => "The unit can test restraint and release without final casting.",
        "unit_risk" => "Front Planning must re-evaluate member placement after the song is selected."
      },
      "source_ref_ids" => ref_ids,
      "lane_ref_ids" => {
        "song" => ["REF_SONG_AA"],
        "media_narrative" => ["REF_MEDIA_NARRATIVE_BB"],
        "fashion" => ["REF_FASHION_CC"],
        "idol" => ["REF_IDOL_DD"]
      },
      "combined_signal" => "All four sources support testing controlled pressure rather than locking a finished MV.",
      "visual_world_candidate" => "A contemporary system space whose rules may visibly react to a member.",
      "first_screen_hook" => "Test whether one visible system interruption can carry the opening.",
      "primary_screen_driver" => "mixed_member_world",
      "why_aurora_m_can_own_it" => "The route leaves member, section, and exact scene decisions to the selected song.",
      "risk_or_gap" => "No actual selected take yet proves the section release.",
      "route_seed" => {
        "song_direction_questions" => ["Which hook contrast makes the pressure legible without cliché?"],
        "candidate_audio_validation_questions" => ["Does the returned take expose a real stop and release?"],
        "front_planning_candidate" => {
          "message_translation_hypothesis" => "Translate the locked audience promise into agency as a response to external scripting.",
          "visual_identity_hypothesis" => "Test a current-title contemporary system world.",
          "whole_film_progression_hypothesis" => "Test restraint, visible complication, release, and afterimage.",
          "reference_connection_questions" => ["Which direct sequence grammar survives the selected song?"],
          "current_title_asset_questions" => ["Which member and background packages must be created after song selection?"]
        },
        "source_links" => ref_ids,
        "risks" => ["The route may flatten if the selected audio lacks a meaningful contrast."],
        "open_questions" => ["Which actual take and section architecture should advance?"]
      }
    }
  end

  def validate(artifact)
    validate_schema(SCHEMA, artifact)
  end

  def validate_schema(schema, artifact)
    stdout, stderr, status = Open3.capture3(
      ROOT.join("scripts", "idol-video-python").to_s,
      VALIDATOR.to_s,
      schema.to_s,
      artifact.to_s,
      chdir: ROOT.to_s
    )
    {stdout: stdout, stderr: stderr, status: status}
  end
end
