# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "tempfile"
require "yaml"

class IdolGrokHandoffContractTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("../..").expand_path
  SCHEMA = ROOT.join("schemas/grok-video-prompt-reference-pack.schema.json")
  VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
  PYTHON = ROOT.join("scripts/idol-video-python")
  WRITER = ROOT.join("scripts/idol_prepare_grok_video_prompt_handoff.rb")
  COMMON_PREP = ROOT.join("scripts/idol_prepare_video_prompt_authoring.rb")
  VIDEO_RUNBOOK = ROOT.join("handoff/grok/flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md")
  IMAGE_RUNBOOK = ROOT.join("handoff/grok/flows/02B/image-prompts/GROK-IMAGE-LOCAL-SOURCE.md")
  FLOW_INDEX = ROOT.join("handoff/grok/flows/README.md")
  VIDEO_README = ROOT.join("handoff/grok/README-video-prompts.md")
  PROMPT_TEMPLATE = ROOT.join("handoff/grok/templates/video-prompt-template.md")
  RETIRED_INDEX_TEMPLATE = ROOT.join("legacy-imports/retired-guidance/handoff/grok/templates/video-prompt-index-template.yaml")

  def validate(document)
    Tempfile.create(["grok-reference-pack", ".yaml"]) do |file|
      file.write(YAML.dump(document))
      file.flush
      return Open3.capture3(
        PYTHON.to_s,
        VALIDATOR.to_s,
        SCHEMA.to_s,
        file.path,
        chdir: ROOT.to_s
      )
    end
  end

  def current_pack
    sha = "a" * 64
    {
      "schema_version" => "idol_grok_video_prompt_reference_pack.v7",
      "content_id" => "TEST_CONTENT_001",
      "run_root" => "runs/2026-07-12/TEST_CONTENT_001",
      "status" => "dry_run",
      "founder_requested" => true,
      "execution_mode" => "founder_paste_only",
      "source_pack" => {
        "path" => "runs/2026-07-12/TEST_CONTENT_001/handoff/03v-authoring-source-pack-v5.yaml",
        "sha256" => sha
      },
      "source_set_sha256" => sha,
      "source_artifacts" => %w[
        master_storyboard
        prompt_packets
        production_cut_review
        audio_branch_cut_placement
        storyboard_assist
      ].map { |role|
        {
          "role" => role,
          "path" => "runs/2026-07-12/TEST_CONTENT_001/source/#{role}.yaml",
          "sha256" => sha
        }
      },
      "storyline_lineage_projection" => {
        "source_01_json_pointer" => "/storyline_lineage_projection/projected_value",
        "source_front_planning_json_pointer" => "/storyline_lineage",
        "source_value_sha256" => sha,
        "projected_value" => {
          "pre00_storyline_original" => {
            "version_id" => "PRE00_STORYLINE_V001",
            "full_storyline_text" => "The complete test storyline remains present."
          }
        }
      },
      "authoring_policy" => {
        "source_gate" => "passed_hash_bound_pixels_and_passed_storyboard_boards_only",
        "attachment_order" => "@image1_storyboard_then_@image2_@image3_optional_@image4_ordered_production_cut_originals",
        "board_authority" => "timing_blocking_subject_route_and_temporal_camera_motion",
        "production_cut_original_authority" => "pixels_identity_style_light_still_composition_and_visible_states",
        "source_union" => "official_core_or_branch",
        "same_parent_default" => true,
        "cross_core_rule" => "both_core_ids_and_continuity_reason_required",
        "camera_motion_owner" => "03V_after_passed_production_cut_review_and_audio_production_cut_placement",
        "creative_prompt_author" => "selected_Grok_surface_under_the_same_active_IDOL_contract",
        "one_section_per_owner" => true
      },
      "section_cohort_successions" => [{
        "section_cohort_id" => "C1",
        "section_ids" => ["S00", "S01"],
        "source_02b_section_shards" => [{"source_json_pointer" => "/section_shards/0", "source_value_sha256" => sha}],
        "planning_cdd_lane_id" => "CDD-P3-C1",
        "production_cdd_lane_id" => "CDD-V-C1",
        "carry_policy" => "p3_ci_to_v_ci_exact_same_section_cohort",
        "physical_session_policy" => "primary_plus_successor_max_two_per_stage"
      }],
      "section_shards" => [
        {
          "section_id" => "S00",
          "section_cohort_id" => "C1",
          "planning_cdd_lane_id" => "CDD-P3-C1",
          "production_cdd_lane_id" => "CDD-V-C1",
          "cohort_carry_policy" => "p3_ci_to_v_ci_exact_same_section_cohort",
          "storyboard_ids" => ["03VSB_S00_A"],
          "board_count" => 1,
          "authoring_scope" => "one_section_only"
        }
      ],
      "reference_files" => {
        "common_authoring_source_pack" => "runs/2026-07-12/TEST_CONTENT_001/handoff/03v-authoring-source-pack-v5.yaml",
        "local_brief" => "runs/2026-07-12/TEST_CONTENT_001/handoff/grok/03V/grok-03V-brief-v1.md",
        "request_packet" => "runs/2026-07-12/TEST_CONTENT_001/handoff/grok/03V/grok-03V-request-v1.md",
        "paste_trigger" => "runs/2026-07-12/TEST_CONTENT_001/handoff/grok/03V/grok-03V-paste-trigger-v1.md"
      },
      "automation_boundaries" => {
        "derived_handoff_only" => true,
        "canonical_source_mutation_allowed" => false,
        "paid_video_generation_approved" => false,
        "external_video_execution_approved" => false,
        "playback_pass_implied" => false,
        "edit_readiness_implied" => false
      }
    }
  end

  def retired_pack
    document = current_pack
    document["schema_version"] = "2.1"
    document
  end

  def test_strict_current_reference_pack_validates
    stdout, stderr, status = validate(current_pack)
    assert status.success?, "stdout=#{stdout}\nstderr=#{stderr}"
    assert_includes stdout, "schema ok"
  end

  def test_current_reference_pack_accepts_an_additional_section_shard
    document = current_pack
    document.fetch("section_shards") << {
      "section_id" => "S01",
      "section_cohort_id" => "C1",
      "planning_cdd_lane_id" => "CDD-P3-C1",
      "production_cdd_lane_id" => "CDD-V-C1",
      "cohort_carry_policy" => "p3_ci_to_v_ci_exact_same_section_cohort",
      "storyboard_ids" => ["03VSB_S01_A"],
      "board_count" => 1,
      "authoring_scope" => "one_section_only"
    }
    stdout, stderr, status = validate(document)
    assert status.success?, "stdout=#{stdout}\nstderr=#{stderr}"
    assert_includes stdout, "schema ok"
  end

  def test_strict_current_reference_pack_rejects_unknown_fields
    document = current_pack
    document["unowned_creative_shortcut"] = true
    _stdout, stderr, status = validate(document)
    refute status.success?
    assert_includes stderr, "invalid"
  end

  def test_retired_reference_pack_is_not_an_active_compatibility_input
    _stdout, stderr, status = validate(retired_pack)
    refute status.success?
    assert_includes stderr, "invalid"
  end

  def test_writer_reuses_common_source_discovery_and_validates_before_write
    text = WRITER.read
    common_text = COMMON_PREP.read
    assert_includes common_text, "idol_03v_authoring_source_pack.v5"
    assert_includes common_text, '"storyline_lineage_projection" => storyline_lineage_projection'
    assert_includes common_text, "Read the complete PRE-00-rooted storyline lineage first"
    assert_includes text, "idol_prepare_video_prompt_authoring.rb"
    assert_includes text, "source pack source-set SHA-256 drifted from active validation"
    assert_includes text, "source pack must exact-cover the five active 03V sources"
    assert_includes text, "03v-authoring-source-pack.schema.json"
    assert_includes text, "production_cut_review"
    assert_includes text, "idol_video_prompt_manifest.v8"
    assert_includes text, "storyline_lineage_projection"
    refute_includes text, "idol_asset_drive_sync.py"
    assert_operator text.index("schema_error = validate_schema(reference_pack)"), :<,
      text.index("if options[:write]")
    assert_includes text, "\"external_video_execution_approved\" => false"
  end

  def test_active_grok_docs_use_provider_neutral_image_request_and_compact_video_control
    image_text = IMAGE_RUNBOOK.read
    assert_includes image_text, "idol_prepare_image_generation_request.rb"
    assert_includes image_text, "registered Grok `grok_image` adapter"
    assert_includes image_text, "Pass `prompt.full_prompt_text` byte-for-byte"
    assert_includes image_text, "actual selected images must be inspected and attached"
    assert_includes image_text, "`attachments[]`"
    assert_match(/current-title member visuals/i, image_text)
    assert_match(/governing scene\/Sequence references/i, image_text)
    refute_match(%r{grok_image_manual|/image|/imagine|imagine_(?:create|edit|video)}, image_text)

    flow_text = FLOW_INDEX.read
    assert_includes flow_text, "02B/image-prompts/GROK-IMAGE-LOCAL-SOURCE.md"
    refute_match(/active[^\n]*flows\/02-03\/grok-imagine/i, flow_text)

    [VIDEO_RUNBOOK.read, VIDEO_README.read, PROMPT_TEMPLATE.read].each do |text|
      assert_includes text, "prompt.txt"
      assert_match(/omit|omits|remove|contains none/i, text)
      assert_match(/negative/i, text)
    end
  end

  def test_video_index_template_is_explicitly_retired_from_the_active_route
    template_text = RETIRED_INDEX_TEMPLATE.read
    document = YAML.safe_load(template_text, permitted_classes: [], aliases: true)
    assert_equal "idol_video_prompt_index.v3", document["schema_version"]
    assert_includes template_text, "RETIRED EVIDENCE-ONLY TEMPLATE"
    assert_includes VIDEO_RUNBOOK.read, "idol_video_prompt_manifest.v8"
    refute_includes VIDEO_RUNBOOK.read, "idol_video_prompt_index.v3"
    refute_includes VIDEO_RUNBOOK.read, "video-prompt-index.yaml"
  end
end
