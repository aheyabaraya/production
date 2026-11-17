# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "pathname"
require "yaml"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/idol_skill_contract_paths"

class IdolActiveInstructionBiasTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path

  # This is a provenance/isolation regression, not a machine judgment of
  # creative quality. It scans only the active shared instruction closure and
  # one fixture-bearing shared validator.
  ACTIVE_SHARED_SURFACES = %w[
    AGENTS.md
    automation/harness-execution-contract.yaml
    policies/creative-production-constitution.md
    policies/harness-routing-and-sources.md
    policies/section-production.md
    wiki/harness-maintenance-rules.md
    skills/idol-orchestrator/SKILL.md
    skills/idol-front-planning-director/SKILL.md
    skills/idol-mv-director/SKILL.md
    skills/idol-generation/SKILL.md
    skills/idol-generation/references/image-render-correction-fast-lane.md
    skills/idol-generation/references/idol-prompt-packet-structure.md
    skills/idol-video-prompt/SKILL.md
    skills/reels-tiktok-template/SKILL.md
    skills/x-posting-template/SKILL.md
    wiki/production-system.md
    wiki/production-system-detail.md
    wiki/front-planning-centered-mv-director-harness.md
    scripts/validate_video_prompt_index.rb
    scripts/tests/support/active_mv_fixture.rb
  ].freeze

  RUN_DERIVED_PATTERNS = {
    "named prior-run identifier" => /\b(?:ONE[ _-]?MOVE|0715_ONE_MOVE|BADUK)\b/i,
    "game-piece scene phrase" => /\b(?:black|white)\s+stone\b|\bstone\s+(?:slides|lands|rests|remains|begins)\b/i,
    "run-specific grid scene phrase" => /\bwet grid\b|\bstone on the (?:lower|upper|left|right)/i,
    "run-specific object phrase" => /\b(?:metal|displaced)\s+token\b|\bfixed rail\b/i,
    "run-specific staging phrase" => /\bgloved hand\b|\blayered corridor\b/i,
    "prior ready-to-copy reference route" => /\bportal departure\b/i,
    "prior title or member copy bank" => /\b(?:RENA|SEIRA|Coca-Cola Memory|Silence Crown)\b/i,
    "prior ready-to-copy social action" => /\b(?:stone click|chorus hand drop|one boot hits|mark returns|can into hand)\b/i
  }.freeze

  REQUIRED_TEACHING_EXAMPLES = {
    "policies/creative-production-constitution.md" =>
      "Non-Prescriptive Teaching Example Contract",
    "wiki/harness-maintenance-rules.md" =>
      "Teaching Example Preservation And Bias Control",
    "wiki/production-system.md" =>
      "How Teaching Examples Work",
    "skills/idol-mv-director/SKILL.md" =>
      "Non-Prescriptive Teaching Example",
    "skills/idol-generation/SKILL.md" =>
      "Non-Prescriptive Teaching Example",
    "skills/idol-generation/references/idol-prompt-packet-structure.md" =>
      "Action Cue Teaching Pattern",
    "skills/idol-video-prompt/SKILL.md" =>
      "Non-Prescriptive Teaching Example"
  }.freeze

  OPENING_TO_RECURRENCE_MARKERS = {
    "AURORA-IDOL-PRODUCTION-BIBLE-VALIDATED.md" =>
      "Opening-to-recurrence song economy",
    "wiki/pre-00-song-system.md" =>
      "recognizable carrier shared by the first full hook and middle/later returns",
    "skills/idol-song-lock/SKILL.md" =>
      "opening-arc behavior that establishes sonic identity",
    "skills/idol-front-planning-director/SKILL.md" =>
      "music-and-screen memory carrier",
    "skills/idol-mv-director/modules/integration.md" =>
      "first-full-hook-to-middle-return consistency",
    "skills/idol-suno-prompt/references/suno-prompt-authoring-detail.md" =>
      "A packet is sufficiently specified when all of these are true",
    "skills/idol-editing-qc/references/editing-qc-detail.md" =>
      "the actual intro boundary establishes the"
  }.freeze

  RETIRED_MASTER_OPENING_PHRASES = /short-form-first|first 1-3|first 3-8s|first 4 seconds|first 15s impact|first-15-second/i

  def test_active_shared_surfaces_contain_no_known_prior_run_scene_language
    violations = ACTIVE_SHARED_SURFACES.flat_map do |relative|
      text = ROOT.join(relative).read
      RUN_DERIVED_PATTERNS.each_with_object([]) do |(label, pattern), rows|
        match = text.match(pattern)
        rows << "#{relative}: #{label}: #{match[0]}" if match
      end
    end

    assert_empty violations, violations.join("\n")
  end

  def test_execution_contract_locks_luna_section_session_and_source_isolation
    contract = YAML.safe_load(
      ROOT.join("automation", "harness-execution-contract.yaml").read,
      aliases: true
    )

    assert_equal "idol-harness-execution-contract.v36", contract.fetch("schema_version")
    assert_equal "physical_section_shard", contract.dig("post_02a_session_routing", "route_id")
    assert_equal "section_owner", contract.dig("post_02a_session_routing", "studio_role")
    assert_equal "post_02a_image_motion", contract.dig("post_02a_session_routing", "assignment_kind")
    refute contract.fetch("post_02a_session_routing").key?("agent_name")
    refute contract.fetch("post_02a_session_routing").key?("model_id")
    assert_equal 14, contract.dig("post_02a_session_routing", "maximum_active_sessions")
    assert_equal 14, contract.dig("post_02a_session_routing", "reviewed_maximum_sessions")
    assert_equal "exactly_one_physical_section", contract.dig("post_02a_session_routing", "session_scope")
    assert_equal "04_is_a_separate_execution_unit", contract.dig("post_02a_session_routing", "edit_boundary")
    assert_equal "creative_development_director", contract.dig("studio_session_routing", "post_song_reference_wave", "return_recipient_role")
    assert_equal "smallest_disjoint_named_gap_assignments_only", contract.dig("studio_session_routing", "post_song_reference_wave", "dispatch_policy")
    assert_equal "floor_six_disjoint_then_named_gap_adaptive", contract.dig("studio_session_routing", "post_song_reference_wave", "assignment_count_policy")
    assert_equal "adaptive_to_professional_decision_readiness_no_fixed_source_floor_or_ceiling", contract.dig("studio_session_routing", "post_song_reference_wave", "source_count_policy")
    assert_equal "adaptive_to_named_gap_no_fixed_discovery_or_application_quota", contract.dig("studio_session_routing", "post_song_reference_wave", "candidate_count_policy")
    assert_equal "never_fill_provider_capacity", contract.dig("studio_session_routing", "post_song_reference_wave", "launch_policy")
    assert_equal "provider_cap_cdd_backpressure_owner_path_collision_and_pending_review", contract.dig("studio_session_routing", "post_song_reference_wave", "queue_policy")
    assert_equal "forbidden", contract.dig("studio_session_routing", "post_song_reference_wave", "world_still_video_access")
    assert_equal "required_hash_bound_uncropped_contact_sheet", contract.dig("studio_session_routing", "post_song_reference_wave", "world_still_every_multi_image_comparison")
    expansion = contract.fetch("section_expansion")
    assert_equal "stage_01", expansion.fetch("official_core_owner")
    assert_equal "exactly_one_passed_primary_image_per_official_core", expansion.fetch("official_core_primary_image_rule")
    assert_equal "immutable_exact_import_no_core_reauthoring", expansion.fetch("stage_02a_core_policy")
    assert_equal "ordered_branch_cuts_only", expansion.fetch("stage_02a_authored_scope")
    assert_equal "edit_director", contract.dig("edit_routing", "edit_shards", "return_recipient_role")
    assert_includes contract.dig("creative_source_isolation", "forbidden_context_sources"), "test_fixtures"
    assert_includes contract.dig("creative_source_isolation", "forbidden_context_sources"), "historical_prompt_or_scene_prose"
    assert_equal(
      "nonprescriptive_teaching_examples_may_show_decision_method_and_multiple_routes_but_never_supply_ready_to_copy_scene_action_camera_motion_or_composition_truth",
      contract.dig("creative_source_isolation", "shared_instruction_rule")
    )
  end

  def test_active_skills_preserve_non_prescriptive_teaching_examples
    missing = REQUIRED_TEACHING_EXAMPLES.each_with_object([]) do |(relative, marker), rows|
      rows << "#{relative}: missing #{marker.inspect}" unless ROOT.join(relative).read.include?(marker)
    end

    assert_empty missing, missing.join("\n")
  end

  def test_opening_to_recurrence_rule_is_present_without_retired_master_phrases
    errors = OPENING_TO_RECURRENCE_MARKERS.each_with_object([]) do |(relative, marker), rows|
      text = ROOT.join(relative).read
      rows << "#{relative}: missing #{marker.inspect}" unless text.include?(marker)
      match = text.match(RETIRED_MASTER_OPENING_PHRASES)
      rows << "#{relative}: retired master-opening phrase: #{match[0]}" if match
    end

    assert_empty errors, errors.join("\n")
  end

  def test_context_and_request_builders_enforce_runtime_source_admission
    contract_library = ROOT.join("scripts", "lib", "idol_02a_storyboard_contract.rb").read
    context_builder = ROOT.join("scripts", "idol_harness_context_pack.rb").read
    request_builder = ROOT.join("scripts", "idol_prepare_image_generation_request.rb").read

    assert_includes contract_library, "visual_source_admission_error"
    assert_includes context_builder, "visual_source_admission_error"
    assert_includes request_builder, "visual_source_admission_error"
  end

  def test_skill_contract_path_parser_keeps_root_agents_instruction
    paths = IdolSkillContractPaths.candidate_paths("Read `AGENTS.md` and `wiki/production-system.md` to EOF.")

    assert_includes paths, "AGENTS.md"
    assert_includes paths, "wiki/production-system.md"
  end

  def test_skill_contract_path_parser_treats_markdown_fragments_as_navigation
    paths = IdolSkillContractPaths.candidate_paths(
      "[Delivery](references/kernel.md#department-instruction-delivery) " \
      "[Kernel](references/kernel.md) [Here](#local-heading)"
    )

    assert_equal ["references/kernel.md"], paths
  end

  def test_skill_contract_path_checker_accepts_fragment_but_rejects_missing_file
    Dir.mktmpdir("idol-skill-link-") do |directory|
      skill = File.join(directory, "skills", "example")
      FileUtils.mkdir_p(File.join(skill, "references"))
      File.write(File.join(skill, "references", "kernel.md"), "## Department Instruction Delivery\n")
      File.write(File.join(skill, "SKILL.md"),
                 "## Required Reads\n[Delivery](references/kernel.md#department-instruction-delivery)\n")

      output, error, status = Open3.capture3(
        RbConfig.ruby, ROOT.join("scripts", "idol_skill_contract_check.rb").to_s,
        chdir: directory
      )
      assert status.success?, output + error

      File.write(File.join(skill, "SKILL.md"),
                 "## Required Reads\n[Missing](references/missing.md#department-instruction-delivery)\n")
      output, error, status = Open3.capture3(
        RbConfig.ruby, ROOT.join("scripts", "idol_skill_contract_check.rb").to_s,
        chdir: directory
      )
      refute status.success?, output + error
      assert_includes error, "referenced path is not readable: references/missing.md"
    end
  end

  def test_skill_matrix_accepts_phase_scoped_media_reads_and_keeps_root_instruction_check
    Dir.mktmpdir("idol-skill-phase-") do |directory|
      %w[idol-generation idol-video-prompt].each do |name|
        target = File.join(directory, "skills", name)
        FileUtils.mkdir_p(target)
        FileUtils.cp(ROOT.join("skills", name, "SKILL.md"), File.join(target, "SKILL.md"))
      end
      profile_path = File.join(directory, "automation", "harness-skill-load-profiles.yaml")
      FileUtils.mkdir_p(File.dirname(profile_path))
      FileUtils.cp(ROOT.join("automation", "harness-skill-load-profiles.yaml"), profile_path)

      output, error, status = Open3.capture3(
        RbConfig.ruby, ROOT.join("scripts", "idol_skill_contract_matrix.rb").to_s,
        "--strict", chdir: directory
      )
      assert status.success?, output + error

      profiles = YAML.safe_load(File.read(profile_path), aliases: true)
      profiles.fetch("read_bindings").each do |binding|
        binding["path"] = "wiki/unrelated.md" if binding["path"] == "AGENTS.md"
      end
      File.write(profile_path, YAML.dump(profiles))
      output, error, status = Open3.capture3(
        RbConfig.ruby, ROOT.join("scripts", "idol_skill_contract_matrix.rb").to_s,
        "--strict", chdir: directory
      )
      refute status.success?, output + error
      assert_includes error, "does not bind AGENTS.md"
    end
  end

  def test_provider_neutral_nonmedia_routing_preserves_cardinality_and_media_exceptions
    orchestrator = ROOT.join("skills", "idol-orchestrator", "SKILL.md").read
    routing_policy = ROOT.join("policies", "harness-routing-and-sources.md").read
    section_policy = ROOT.join("policies", "section-production.md").read
    production_detail = ROOT.join("wiki", "production-system-detail.md").read
    routing_detail = ROOT.join("skills", "idol-orchestrator", "references", "orchestration-routing-detail.md").read

    assert_includes orchestrator, "`worker_high`: the logical ordinary non-media MV/CF department profile"
    assert_includes orchestrator, "new non-media assignments prefer the exact run-resolved\n  Grok CLI profile selected by the Founder"
    assert_includes routing_policy, "new assignments prefer its readiness-valid Grok CLI provider and never fall"
    assert_includes section_policy, "Ordinary non-media reference research and section development resolve the\n  logical `worker_high` profile"
    assert_match(/Pre-02A development: two to four ordinary blocks.*reviewed maximum of five/m, orchestrator)
    assert_includes orchestrator, "Pre-02A 01 Official Core / 02A Branch coverage"
    assert_includes orchestrator, "fresh Founder-visible provider-resolved\n  `section_image_motion_worker / worker_high` session owns exactly one physical"
    assert_includes routing_policy, "post-02A 02B/03V one-section media owner also resolves the logical"
    assert_includes section_policy, "that provider's registered\n  model, effort, tools, auth, and output intake"
    assert_includes orchestrator, "Founder briefing secretary uses Grok CLI `worker_high`"
    refute_includes production_detail, "CDD directs bounded\nLuna/Max departments"
    refute_includes routing_detail, "Ordinary Luna departments"
    refute_includes routing_detail, "Edit Luna"
  end

  def test_active_instruction_versions_and_retired_01a_route_are_current
    section_policy = ROOT.join("policies", "section-production.md").read
    production_detail = ROOT.join("wiki", "production-system-detail.md").read
    video_prompt = ROOT.join("skills", "idol-video-prompt", "SKILL.md").read
    script_index = ROOT.join("scripts", "INDEX.md").read
    cut_prepare = ROOT.join("scripts", "idol_prepare_production_cut_review.rb").read
    social_system = ROOT.join("wiki", "social-automation-system.md").read
    evidence_graph = ROOT.join("wiki", "harness-contract-evidence-graph.md").read
    retired_reference_schema = JSON.parse(ROOT.join("schemas", "mv-direction-reference-mining.schema.json").read)
    edit_marker_schema = JSON.parse(ROOT.join("schemas", "edit-marker-plan.schema.json").read)

    section_02b = ROOT.join("policies", "section-production-02b-pixel.md").read
    assert_includes section_02b, "The v1.6 compiler validates"
    assert_includes production_detail, "`idol_prompt_packet_delta.v1.6`"
    assert_includes production_detail, "`2.6` | `02B-prompt-packets.yaml`"
    assert_includes video_prompt, "FP17 Major/Sequence bindings"
    assert_includes script_index, "source-hashed v3 view"
    assert_includes cut_prepare, "Explicit passed generated Branch-Cut review v4 source."
    assert_includes social_system, "post-05 work does not open or promote a\nretired 01A board"
    assert_includes evidence_graph, "Overall remains the sole Founder-\nconversation owner"
    assert_includes evidence_graph, "only the adaptive named-gap\nreference assignments still needed for decision readiness"
    assert_includes retired_reference_schema.fetch("description"), "front-planning-readiness.v17"
    refute_includes retired_reference_schema.fetch("description"), "front-planning-readiness.v16"
    placement_description = edit_marker_schema.dig("properties", "production_cut_lineage_sources", "description")
    assert_includes placement_description, "Audio Production Cut Placement v5"
    refute_includes placement_description, "Audio-Branch-Cut Placement"
  end
end
