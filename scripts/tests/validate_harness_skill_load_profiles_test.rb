#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

ROOT = Pathname.new(__dir__).join("..", "..").expand_path
VALIDATOR = ROOT.join("scripts", "validate_harness_skill_load_profiles.rb")
SOURCE = ROOT.join("automation", "harness-skill-load-profiles.yaml")

class ValidateHarnessSkillLoadProfilesTest < Minitest::Test
  def with_registry
    Dir.mktmpdir("skill-load-profiles") do |directory|
      document = YAML.safe_load(SOURCE.read, aliases: true)
      (Array(document["skill_bindings"]) + Array(document["read_bindings"])).each do |row|
        row["sha256"] = Digest::SHA256.file(ROOT.join(row.fetch("path")).to_s).hexdigest
      end
      path = Pathname.new(directory).join("profiles.yaml")
      path.write(YAML.dump(document))
      yield path, document
    end
  end

  def run_validator(path)
    Open3.capture3("ruby", VALIDATOR.to_s, "--registry", path.to_s, "--json", chdir: ROOT.to_s)
  end

  def checkpoint_reads(document, profile_id, checkpoint_id)
    profile = document.fetch("profiles").find { |row| row["profile_id"] == profile_id }
    checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == checkpoint_id }
    checkpoint.fetch("required_read_ids")
  end

  def test_accepts_hash_bound_profile_registry
    with_registry do |path, _document|
      stdout, stderr, status = run_validator(path)
      assert status.success?, [stdout, stderr].join("\n")
      assert_includes stdout, '"status": "pass"'
    end
  end

  def test_shipped_registry_scopes_overall_cdd_and_02b_stage_manuals
    document = YAML.safe_load(SOURCE.read, aliases: true)
    bindings = document.fetch("read_bindings").each_with_object({}) { |row, memo| memo[row.fetch("binding_id")] = row }
    %w[section_production_policy section_production_front_planning section_production_02b_pixel section_production_04].each do |binding_id|
      assert_equal true, bindings.fetch(binding_id).fetch("eof_required")
    end

    overall = checkpoint_reads(document, "overall_director", "director_startup")
    assert_includes overall, "production_system"
    assert_includes overall, "section_production_policy"
    refute_includes overall, "section_production_02b_pixel"
    refute_includes overall, "section_production_04"

    cdd = checkpoint_reads(document, "creative_development_director", "cdd_direction_alignment")
    assert_includes cdd, "section_production_front_planning"
    refute_includes cdd, "section_production_02b_pixel"
    refute_includes cdd, "section_production_04"

    image = checkpoint_reads(document, "post_02a_02b_image", "section_02b_image")
    assert_includes image, "section_production_02b_pixel"
    refute_includes image, "section_production_front_planning"
    refute_includes image, "section_production_04"
  end

  def test_rejects_stale_binding_hash
    with_registry do |path, document|
      document.fetch("skill_bindings").first["sha256"] = "0" * 64
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "binding SHA-256 is stale"
    end
  end

  def test_rejects_wrong_cdd_return_route
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      profile.fetch("return_route")["recipient_role"] = "overall_director"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "return recipient mismatch for reference_research_generalist"
    end
  end

  def test_rejects_founder_briefing_with_a_creative_stage_or_promotion
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "founder_briefing" }
      profile.fetch("stage_ids") << "front_planning_integration"
      profile.fetch("return_route")["promotion_route"] = "overall_director_after_review"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "projection-only profile must not invent a creative stage"
      assert_includes stdout, "founder_briefing must publish only reviewed projection bytes without creative promotion"
    end
  end

  def test_rejects_cdd_canonical_write
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
      profile.fetch("output_contract")["canonical_write"] = "owner_only"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "CDD canonical_write must be forbidden"
    end
  end

  def test_rejects_cdd_that_claims_its_own_review_or_promotion
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
      profile.fetch("authority")["review_owner"] = "creative_development_director"
      profile.fetch("authority")["promotion_owner"] = "creative_development_director"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "CDD review owner must remain Overall"
      assert_includes stdout, "CDD promotion owner must remain Overall"
    end
  end

  def test_rejects_overall_that_loses_promotion_authority
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "overall_director" }
      profile.fetch("authority")["promotion_owner"] = "creative_development_director"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "Overall promotion owner must remain overall_director"
    end
  end

  def test_rejects_cdd_without_the_shared_studio_kernel
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
      profile.fetch("required_read_ids").delete("provider_neutral_studio_kernel")
      profile.dig("phase_load", "checkpoints").each do |checkpoint|
        checkpoint.fetch("required_read_ids").delete("provider_neutral_studio_kernel")
      end
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "CDD profile missing canonical contract read: provider_neutral_studio_kernel"
    end
  end

  def test_rejects_overall_without_the_shared_studio_kernel
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "overall_director" }
      profile.fetch("required_read_ids").delete("provider_neutral_studio_kernel")
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids").delete("provider_neutral_studio_kernel")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "Overall profile missing orchestration contract read: provider_neutral_studio_kernel"
    end
  end

  def test_rejects_edit_director_without_the_shared_studio_kernel
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "edit_director" }
      profile.fetch("required_read_ids").delete("provider_neutral_studio_kernel")
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids").delete("provider_neutral_studio_kernel")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "Edit Director profile missing launch contract read: provider_neutral_studio_kernel"
    end
  end

  def test_rejects_full_reference_catalog_profile_read
    with_registry do |path, document|
      document.fetch("read_bindings") << {
        "binding_id" => "reference_catalog",
        "path" => "catalog/references/reference-catalog.yaml",
        "revision" => "content-addressed",
        "sha256" => Digest::SHA256.file(ROOT.join("catalog/references/reference-catalog.yaml").to_s).hexdigest,
        "eof_required" => true
      }
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      profile.fetch("required_read_ids") << "reference_catalog"
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids") << "reference_catalog"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "full reference catalog must not be a profile EOF binding"
    end
  end

  def test_rejects_cdd_skill_in_pre_02a_worker
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      profile.fetch("required_skill_ids") << "front_planning_director"
      profile.dig("phase_load", "checkpoints").first.fetch("required_skill_ids") << "front_planning_director"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "CDD skill may load only in creative_development_director"
    end
  end

  def test_rejects_post_02a_read_in_pre_02a_worker
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      profile.fetch("required_read_ids") << "generation_prompt_compile"
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids") << "generation_prompt_compile"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "pre-02A profile loads forbidden phase/board read"
    end
  end

  def test_rejects_source_hub_skill_in_run_reference_worker
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      profile.fetch("required_skill_ids") << "video_reference_hub"
      profile.dig("phase_load", "checkpoints").first.fetch("required_skill_ids") << "video_reference_hub"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "reference research worker must not load source-hub owner skill"
    end
  end

  def test_rejects_unrelated_still_protocol_in_story_reference_checkpoint
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "reference_story_sequence_role" }
      checkpoint.fetch("required_read_ids") << "source_image_readme"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "reference_story_sequence_role loads unrelated still read"
    end
  end

  def test_rejects_camera_reference_checkpoint_without_camera_vocabulary
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "reference_camera_composition_role" }
      checkpoint.fetch("required_read_ids").delete("mv_camera_module")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "reference_camera_composition_role missing camera vocabulary read: mv_camera_module"
    end
  end

  def test_rejects_camera_vocabulary_in_non_camera_reference_checkpoint
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "reference_story_sequence_role" }
      checkpoint.fetch("required_read_ids") << "mv_camera_module"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "reference_story_sequence_role must not preload camera vocabulary"
    end
  end

  def test_rejects_unrelated_video_protocol_in_world_reference_checkpoint
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "reference_world_object_material_role" }
      checkpoint.fetch("required_read_ids") << "source_video_read_first"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "reference_world_object_material_role loads unrelated video read"
    end
  end

  def test_rejects_video_read_in_world_still_worker
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "world_still_reference_department" }
      profile.fetch("required_read_ids") << "source_video_read_first"
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids") << "source_video_read_first"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "world/still worker loads forbidden video read"
    end
  end

  def test_rejects_unsheeted_world_still_comparison_contract
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "world_still_reference_department" }
      profile.fetch("hold_conditions").delete("multi_image_comparison_without_contact_sheet")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "world/still worker must hold unsheeted multi-image comparison"
    end
  end

  def test_rejects_non_dispatch_world_still_output_kind
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "world_still_reference_department" }
      profile.fetch("output_contract")["kinds"] << "contact_sheet_comparison_receipt"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "profile output kind is outside Department Dispatch v8"
    end
  end

  def test_rejects_render_correction_in_main_image_checkpoint
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_02b_image" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_02b_image" }
      checkpoint.fetch("required_read_ids") << "generation_render_correction"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "main post-02A image checkpoint must not preload render correction"
    end
  end

  def test_rejects_02b_translation_without_media_security_policy
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_02b_image" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_02b_image" }
      checkpoint.fetch("required_read_ids").delete("media_security_policy")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "post_02a_02b_image.section_02b_image missing read binding: media_security_policy"
      assert_includes stdout, "02B translation checkpoint must load media-security input and allowlist policy"
    end
  end

  def test_rejects_member_visual_canonical_write
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "member_visual_identity" }
      profile.fetch("output_contract")["canonical_write"] = "owner_only"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "member visual worker canonical_write must be forbidden"
    end
  end

  def test_rejects_missing_skill_declared_checkpoint
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "reference_story_sequence_role" }
      checkpoint["checkpoint_id"] = "renamed_story_role"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "reference research profile missing role checkpoint"
    end
  end

  def test_rejects_pinterest_worker_without_dedicated_skill
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pinterest_visual_composition_worker" }
      profile.fetch("required_skill_ids").replace(["world_still_reference_department"])
      profile.dig("phase_load", "preload_skill_ids").replace(["world_still_reference_department"])
      profile.dig("phase_load", "checkpoints").first.fetch("required_skill_ids").replace(["world_still_reference_department"])
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "Pinterest worker must use only its dedicated owner skill"
    end
  end

  def test_rejects_board_coordinator_with_full_orchestrator
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "board_coordinator" }
      profile.fetch("required_skill_ids") << "orchestrator"
      profile.dig("phase_load", "checkpoints").first.fetch("required_skill_ids") << "orchestrator"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "board coordinator must not load full orchestrator"
    end
  end

  def test_rejects_board_coordinator_without_creative_authority_bans
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "board_coordinator" }
      profile.dig("authority", "must_not").delete("creative_promotion")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "board coordinator missing mechanical authority ban: creative_promotion"
    end
  end

  def test_rejects_missing_role_routed_mv_detail
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_01_world_wardrobe_detail" }
      checkpoint.fetch("required_read_ids").delete("mv_screen_flow_wardrobe_module")
      profile.fetch("required_read_ids").delete("mv_screen_flow_wardrobe_module")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "pre_02a_development_block_fp.section_01_world_wardrobe_detail missing read binding: mv_screen_flow_wardrobe_module"
    end
  end

  def test_rejects_02a_coverage_without_camera_vocabulary
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_02a_coverage" }
      checkpoint.fetch("required_read_ids").delete("mv_camera_module")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "pre_02a_development_block_fp.section_02a_coverage missing read binding: mv_camera_module"
    end
  end

  def test_rejects_performance_checkpoint_that_blanket_loads_choreography
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_01_performance_detail" }
      checkpoint.fetch("required_read_ids") << "mv_choreography_module"
      checkpoint.fetch("required_skill_ids") << "choreography_performance"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "performance detail must not preload choreography module"
      assert_includes stdout, "section_01_performance_detail loads unrelated authority skill"
    end
  end

  def test_rejects_song_prompt_without_owning_authoring_detail
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "song_room_prompt" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "song_prompt_authoring" }
      checkpoint.fetch("required_read_ids").delete("suno_prompt_authoring_detail")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "song_room_prompt.song_prompt_authoring missing read binding: suno_prompt_authoring_detail"
    end
  end

  def test_rejects_post_05_social_automation_in_song_prompt
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "song_room_prompt" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "song_prompt_authoring" }
      checkpoint.fetch("required_read_ids") << "social_automation_system"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "song_prompt_authoring must not preload post-05 social automation"
    end
  end

  def test_rejects_00a_without_selected_audio_schema
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "song_room_00a" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "selected_audio_analysis" }
      checkpoint.fetch("required_read_ids").delete("selected_audio_schema")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "song_room_00a.selected_audio_analysis missing read binding: selected_audio_schema"
    end
  end

  def test_rejects_profiled_script_checkpoint_without_exact_role_guide
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "song_room_00a" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "selected_audio_analysis" }
      checkpoint.fetch("required_read_ids").delete("scripts_guide_research_evidence")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "profiled script checkpoint must load one exact role guide: song_room_00a.selected_audio_analysis"
    end
  end

  def test_rejects_choreography_without_body_module
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_01_choreography_detail" }
      checkpoint.fetch("required_read_ids").delete("choreography_body_module")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "pre_02a_development_block_fp.section_01_choreography_detail missing read binding: choreography_body_module"
    end
  end

  def test_rejects_choreography_board_without_owning_skill
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_01_choreography_board" }
      checkpoint.fetch("required_skill_ids").replace(["mv_director"])
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "pre_02a_development_block_fp.section_01_choreography_board missing skill binding: choreography_board"
      assert_includes stdout, "section_01_choreography_board loads unrelated authority skill"
    end
  end

  def test_rejects_image_release_without_section_approval_schema
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_02b_image" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_image_generation_release" }
      checkpoint.fetch("required_read_ids").delete("image_generation_section_approval_schema")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "post_02a_02b_image.section_image_generation_release missing read binding: image_generation_section_approval_schema"
    end
  end

  def test_rejects_full_camera_vocabulary_in_02b_translation_checkpoint
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_02b_image" }
      profile.fetch("required_read_ids") << "mv_camera_module"
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_02b_image" }
      checkpoint.fetch("required_read_ids") << "mv_camera_module"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "02B translation checkpoint must not reopen the full camera vocabulary"
    end
  end

  def test_rejects_03v_motion_without_storyboard_detail
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_03v" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_03v_motion_direction" }
      checkpoint.fetch("required_read_ids").delete("video_storyboard_assist_detail")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "post_02a_03v.section_03v_motion_direction missing read binding: video_storyboard_assist_detail"
    end
  end

  def test_rejects_03v_motion_without_authoring_detail
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_03v" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_03v_motion_direction" }
      checkpoint.fetch("required_read_ids").delete("video_prompt_authoring_detail")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "post_02a_03v.section_03v_motion_direction missing read binding: video_prompt_authoring_detail"
    end
  end

  def test_rejects_03v_audio_placement_with_authoring_detail
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_03v" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_03v_audio_placement" }
      checkpoint.fetch("required_read_ids") << "video_prompt_authoring_detail"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "03V audio placement must not preload video prompt authoring detail"
    end
  end

  def test_rejects_03v_playback_review_with_authoring_detail
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_03v" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_03v_playback_review" }
      checkpoint.fetch("required_read_ids") << "video_prompt_authoring_detail"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "03V playback review must not reopen video prompt authoring detail"
    end
  end

  def test_rejects_03v_motion_without_camera_vocabulary
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "post_02a_03v" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "section_03v_motion_direction" }
      checkpoint.fetch("required_read_ids").delete("mv_camera_module")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "post_02a_03v.section_03v_motion_direction missing read binding: mv_camera_module"
    end
  end

  def test_rejects_edit_qc_without_professional_casebook
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "edit_director" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "edit_qc_section" }
      checkpoint.fetch("required_read_ids").delete("editing_casebook")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "edit_director.edit_qc_section missing read binding: editing_casebook"
    end
  end

  def test_rejects_social_automation_in_ordinary_edit_qc
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "edit_director" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "edit_qc_section" }
      checkpoint.fetch("required_read_ids") << "social_automation_system"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "edit_qc_section must defer social automation to edit_social_release"
    end
  end

  def test_rejects_social_release_without_social_automation_system
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "edit_director" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "edit_social_release" }
      checkpoint.fetch("required_read_ids").delete("social_automation_system")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "edit_director.edit_social_release missing read binding: social_automation_system"
    end
  end

  def test_rejects_cdd_startup_checkpoint_specific_reads
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "cdd_startup" }
      checkpoint.fetch("required_read_ids") << "fp_harness_wiki"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "CDD startup must defer checkpoint-specific read to JIT review: fp_harness_wiki"
    end
  end

  def test_rejects_cdd_direction_alignment_without_sequence_and_founder_context
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "cdd_direction_alignment" }
      checkpoint.fetch("required_read_ids").delete("director_room_discovery")
      checkpoint.fetch("required_read_ids").delete("fp_founder_visual_contract")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "creative_development_director.cdd_direction_alignment missing read binding: director_room_discovery"
      assert_includes stdout, "creative_development_director.cdd_direction_alignment missing read binding: fp_founder_visual_contract"
    end
  end

  def test_rejects_reference_sequence_checkpoint_without_sequence_motion_contract
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "reference_research_generalist" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "reference_story_sequence_role" }
      checkpoint.fetch("required_read_ids").delete("sequence_motion_analysis_schema")
      checkpoint.fetch("required_read_ids").delete("sequence_motion_analysis_validator")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "reference_story_sequence_role missing Sequence Motion read: sequence_motion_analysis_schema"
      assert_includes stdout, "reference_story_sequence_role missing Sequence Motion read: sequence_motion_analysis_validator"
    end
  end

  def test_rejects_cdd_sequence_review_without_sequence_motion_contract
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "creative_development_director" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "cdd_sequence_motion_review" }
      checkpoint.fetch("required_read_ids").delete("sequence_motion_analysis_schema")
      checkpoint.fetch("required_read_ids").delete("sequence_motion_analysis_validator")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "creative_development_director.cdd_sequence_motion_review missing read binding: sequence_motion_analysis_schema"
      assert_includes stdout, "creative_development_director.cdd_sequence_motion_review missing read binding: sequence_motion_analysis_validator"
    end
  end

  def test_rejects_finishing_checkpoint_that_preloads_shot_vfx
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "edit_shard" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "finishing_fx_section" }
      checkpoint.fetch("required_skill_ids") << "shot_vfx"
      checkpoint.fetch("required_read_ids") << "shot_vfx_manual"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "finishing_fx_section loads unrelated edit authority skill"
      assert_includes stdout, "finishing_fx_section preloads shot-VFX read: shot_vfx_manual"
    end
  end

  def test_rejects_direction_board_without_html_contract
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "board_coordinator" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "board_direction_alignment" }
      checkpoint.fetch("required_read_ids").delete("html_review_board_schema")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "board_coordinator.board_direction_alignment missing read binding: html_review_board_schema"
    end
  end

  def test_rejects_edit_shard_canonical_write
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "edit_shard" }
      profile.fetch("output_contract")["canonical_write"] = "owner_only"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "edit shard canonical_write must be forbidden"
    end
  end

  def test_rejects_provider_adapter_as_task_profile
    with_registry do |path, document|
      adapter = document.fetch("profiles").first.dup
      adapter["profile_id"] = "grok_worker_adapter"
      document.fetch("profiles") << adapter
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)

      refute status.success?
      assert_includes stdout, "Grok transport adapter must not be a task skill-load profile"
    end
  end

  def test_accepts_explicit_maintenance_only_profile_outside_creative_contract_aliases
    with_registry do |path, _document|
      stdout, stderr, status = run_validator(path)
      assert status.success?, [stdout, stderr].join("\n")
      payload = JSON.parse(stdout)
      assert_equal "pass", payload.fetch("status")
      assert_equal "registered_checkpoint_required_skill_ids_and_required_read_ids_whitespace_words_v1", payload.fetch("checkpoint_load_measurement_basis")
      row = payload.fetch("checkpoint_loads").find do |item|
        item["profile_id"] == "harness_maintenance" && item["checkpoint_id"] == "instruction_policy_wiki"
      end
      refute_nil row
      assert_equal 0, row.fetch("skill_binding_count")
      assert_operator row.fetch("word_count"), :>, 0
    end
  end

  def test_rejects_maintenance_context_in_creative_profile
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "overall_director" }
      profile.fetch("required_read_ids") << "maintenance_rules"
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids") << "maintenance_rules"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "creative profile must not load maintenance context: overall_director=maintenance_rules"
    end
  end

  def test_rejects_full_script_index_in_creative_profile
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "overall_director" }
      profile.fetch("required_read_ids") << "scripts_full_index"
      profile.dig("phase_load", "checkpoints").first.fetch("required_read_ids") << "scripts_full_index"
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "creative profile must not load full script discovery/maintenance surface: overall_director=scripts_full_index"
    end
  end

  def test_rejects_maintenance_profile_creative_skill
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "harness_maintenance" }
      profile.fetch("required_skill_ids") << "orchestrator"
      profile.dig("phase_load", "checkpoints").first.fetch("required_skill_ids") << "orchestrator"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "maintenance-only profile must not load a creative skill: harness_maintenance"
      assert_includes stdout, "maintenance checkpoint must not load a creative skill: instruction_policy_wiki"
    end
  end

  def test_rejects_maintenance_checkpoint_with_multiple_surface_modules
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "harness_maintenance" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "instruction_policy_wiki" }
      checkpoint.fetch("required_read_ids") << "maintenance_schema_contract_registry"
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "maintenance checkpoint must load compact core plus one selected module: instruction_policy_wiki"
    end
  end

  def test_rejects_script_registry_maintenance_without_full_discovery_contract
    with_registry do |path, document|
      profile = document.fetch("profiles").find { |row| row["profile_id"] == "harness_maintenance" }
      checkpoint = profile.dig("phase_load", "checkpoints").find { |row| row["checkpoint_id"] == "script_validator_registry" }
      checkpoint.fetch("required_read_ids").delete("scripts_full_index")
      path.write(YAML.dump(document))

      stdout, _stderr, status = run_validator(path)
      refute status.success?
      assert_includes stdout, "maintenance checkpoint must load compact core plus one selected module: script_validator_registry"
    end
  end
end
