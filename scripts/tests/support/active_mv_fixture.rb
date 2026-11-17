# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../../lib/idol_02a_storyboard_contract"
require_relative "../../lib/idol_storyboard_collected_angle_contract"
require_relative "../../lib/idol_storyline_density_locator_contract"
require_relative "../../lib/idol_kinetic_slot_sheet_contract"
require_relative "active_sequence_motion_fixture"
require_relative "department_dispatch_profile_fixture"

class ActiveMvFixture
  include DepartmentDispatchProfileFixture
  ROOT = Pathname.new(__dir__).join("..", "..", "..").expand_path

  @created_fixtures = []

  class << self
    attr_reader :created_fixtures

    def cleanup_created_fixtures
      Array(created_fixtures).reverse_each do |creator_pid, fixture|
        fixture.cleanup if creator_pid == Process.pid
      end
      created_fixtures.delete_if { |creator_pid, _fixture| creator_pid == Process.pid }
    end
  end

  attr_reader :run_container, :run_dir, :asset_package_dir, :front_path, :direction_path,
              :storyboard_path, :context_review_path, :delta_path, :delta,
              :storyboard, :pre00_handoff_path, :album_key, :title_key,
              :sequence_motion_analysis_path, :audio_motion_map_path,
              :sequence_motion_dispatch_path, :draft_keyframe_grade_path

  def self.create
    fixture = new
    created_fixtures << [Process.pid, fixture]
    fixture.build
    fixture
  rescue StandardError
    fixture&.cleanup
    raise
  end

  def cleanup
    FileUtils.remove_entry(run_container) if run_container&.directory?
    FileUtils.remove_entry(asset_package_dir) if asset_package_dir&.directory?
  end

  def build
    @run_container = Pathname.new(Dir.mktmpdir("idol-active-suite-", ROOT.join("runs").to_s))
    @album_key = run_container.basename.to_s
    @title_key = "active-title-test"
    @run_dir = run_container.join(title_key, "ACTIVE_TITLE_TEST")
    run_dir.mkpath
    @asset_package_dir = ROOT.join("assets", "members", "album-assets", album_key)
    asset_package_dir.mkpath
    write_yaml(
      run_dir.join("run-manifest.yaml"),
      {
        "schema_version" => "idol-run-manifest.v1",
        "status" => "active",
        "album_key" => album_key,
        "title_key" => title_key,
        "run_id" => run_dir.basename.to_s,
        "content_id" => run_dir.basename.to_s,
        "canonical_run_root" => relative(run_dir),
        "artifact_revision_owner" => "git",
        "compatibility_authoring" => "forbidden"
      }
    )

    song = write_file(run_dir.join("00A-song-lock.yaml"), "selected song lock\n")
    member = write_file(asset_package_dir.join(title_key, "M01", "member.png"), "member visual pixels\n")
    sequence = write_file(run_dir.join("references", "sequence-selected-cell.png"), "sequence selected cell pixels\n")
    @sequence_bundle_frames = 5.times.map do |index|
      write_file(
        run_dir.join("references", "sequence", format("frame-%02d.png", index + 1)),
        "sequence bundle frame #{index + 1}\n"
      )
    end
    @sequence_bundle_manifest = write_file(
      run_dir.join("references", "sequence", "manifest.json"),
      "five-frame sequence bundle manifest\n"
    )
    scene = write_file(run_dir.join("references", "scene-crop.png"), "scene crop pixels\n")
    support = write_file(run_dir.join("references", "support-detail.png"), "support detail pixels\n")
    @hero_core_images = [
      write_file(run_dir.join("01", "official-core-C01.png"), "official Core C01 primary image pixels\n"),
      write_file(run_dir.join("01", "official-core-C02.png"), "official Core C02 primary image pixels\n")
    ]
    pins = 5.times.map do |index|
      write_file(
        run_dir.join("references", "pinterest", format("pin-%02d.png", index + 1)),
        "public Pinterest pin fixture #{index + 1}\n"
      )
    end
    analysis = write_file(run_dir.join("references", "directing-analysis.md"), "Detailed source observation and purpose extraction.\n")
    source_manifest = write_file(run_dir.join("references", "source-manifest.yaml"), "source_id: SOURCE-A\n")
    worker_delta = write_file(run_dir.join("research", "reference-delta.yaml"), "dispatch_id: DISPATCH-REF\nattempt_id: ATTEMPT-REF\n")
    worker_dispatch = write_file(
      run_dir.join("work", "department-dispatches", "DISPATCH-REF.yaml"),
      "dispatch_id: DISPATCH-REF\nlineage:\n  attempt_id: ATTEMPT-REF\n"
    )
    selected_audio_analysis_path = write_yaml(
      run_dir.join("research", "selected-audio-analysis.yaml"),
      {
        "schema_version" => "idol_selected_audio_analysis.v1",
        "content_id" => "ACTIVE_TITLE_TEST",
        "section_map" => [{"section_id" => "S01", "reserve_status" => "active", "start_seconds" => 0.0, "end_seconds" => 12.0}]
      }
    )
    @audio_motion_map_path = write_yaml(
      run_dir.join("research", "audio-motion-evidence-map.yaml"),
      {
        "schema_version" => "idol_audio_motion_director_map.v1",
        "content_id" => "ACTIVE_TITLE_TEST",
        "status" => "ready_for_00a",
        "source_selected_audio_analysis" => {"path" => relative(selected_audio_analysis_path), "sha256" => file_sha(selected_audio_analysis_path)},
        "purpose" => {
          "summary" => "Preserve audible timing pressure while leaving all screen answers downstream.",
          "use_rule" => "map_audible_timing_pressure_and_leave_screen_answers_downstream"
        },
        "stable_audio_extracts" => {
          "duration_seconds" => 12.0,
          "tempo" => {"main_grid_bpm" => 120, "perceived_pulse" => "Half-time weight under upper accents.", "alternate_grid_or_uncertainty" => "Double-time accents do not change the main grid."},
          "meter" => "4/4",
          "signals" => [{"signal_id" => "SIG01", "signal_type" => "vocal_entry", "time_seconds" => 1.0, "observed_audio_fact" => "The first vocal enters after one empty beat.", "confidence" => "high", "evidence_refs" => []}],
          "precision_marker_sources" => [],
          "evidence_only_rule" => "measurements_support_listening_and_never_author_creative_truth"
        },
        "section_rhythm_map" => [{
          "section_id" => "S01",
          "start_seconds" => 0.0,
          "end_seconds" => 12.0,
          "main_pulse" => "Half-time weight under short upper accents.",
          "energy_density" => "Sparse until the return.",
          "accent_grid" => "One clear stop before the return.",
          "onset_stop_reset" => "The stop resets the phrase.",
          "vocal_or_lyric_trigger" => "The first vocal and later return are audible.",
          "motif_return" => "The hook returns after the reset.",
          "audible_state_change_pressure" => "release",
          "screen_readability_questions" => ["What visible state change should answer the release?"],
          "editability_evidence" => ["The stop is an audible marker candidate."],
          "temporal_camera_deferred_to_03v" => true
        }],
        "trigger_map" => [{"trigger_id" => "TR01", "section_id" => "S01", "time_seconds" => 8.0, "trigger_type" => "motif_return", "audio_fact" => "The hook returns after the stop.", "candidate_state_change_question" => "Which downstream screen decision should answer the release?", "precision_source_ids" => []}],
        "downstream_boundary" => {
          "provides_audio_pressure_only" => true,
          "front_planning_owns_target_message_visual_members_references_and_section_scene_flow" => true,
          "front_planning_01_02a_own_still_frame_truth" => true,
          "video_prompt_03v_owns_temporal_camera_after_passed_pixels" => true,
          "image_prompt_02b_translates_passed_02a" => true,
          "prompt_prose_forbidden_here" => true
        },
        "song_lock_handoff" => {"section_ids" => ["S01"], "audible_pressure_summary" => ["S01 holds pressure before one release."], "timing_risks" => [], "front_planning_questions" => ["Which visible relation should answer the release?"]},
        "open_questions" => [],
        "hold_reasons" => []
      }
    )
    cdd_review = write_file(run_dir.join("review", "cdd-reference-review.yaml"), "disposition: accepted\n")
    section_binding = write_file(run_dir.join("research", "reference-section-binding.yaml"), "section_id: S01\n")
    manifest = write_file(asset_package_dir.join(title_key, "manifest.yaml"), "active title manifest\n")
    sequence_control_document = founder_sequence_control_document
    upgrade_founder_sequence_control!(sequence_control_document)
    sequence_control = write_yaml(run_dir.join("founder-sequence-control.yaml"), sequence_control_document)
    reference_index = write_reference_index(
      sequence: sequence,
      scene: scene,
      support: support,
      pins: pins,
      analysis: analysis,
      source_manifest: source_manifest,
      worker_delta: worker_delta,
      worker_dispatch: worker_dispatch,
      cdd_review: cdd_review,
      section_binding: section_binding
    )
    pre00_lineage = pre00_storyline_lineage
    pre00_audience_target = {
      "audience_profiles" => [{"profile_id" => "AUD_X", "reference_slot" => "X", "audience_profile" => {"audience_definition" => "Listeners who reward precise visible causality.", "desired_reward" => "An earned screen consequence."}}],
      "x_reference_audience_envelope" => {"reference_slot" => "X", "base_audience_profile_id" => "AUD_X", "boundary" => "The selected X-song audience remains the title target base."},
      "title_target_intersection" => {"intersection_id" => "TTI_ACTIVE_01", "selected_target" => "X-song listeners who reward visible causality.", "decision" => "pass"}
    }
    pre00_audience_bindings = pre00_audience_target.each_with_object({}) do |(field, value), bindings|
      bindings[field] = {"source_pointer" => "/#{field}", "value" => value, "value_sha256" => value_sha(value)}
    end
    pre00_handoff_document = {
      "schema_version" => "idol-pre00-selection-handoff.v4",
      "storyline_lineage" => {
        "source_pointer" => "/storyline_lineage",
        "value" => pre00_lineage,
        "value_sha256" => value_sha(pre00_lineage)
      }
    }.merge(pre00_audience_bindings)
    @pre00_handoff_path = write_yaml(
      run_dir.join("research", "pre00-selection-handoff-v1.yaml"),
      pre00_handoff_document
    )

    front = front_document(
      pre00_handoff: pre00_handoff_path,
      pre00_lineage: pre00_lineage,
      song: song,
      sequence_control: sequence_control,
      member: member,
      sequence: sequence,
      scene: scene,
      support: support,
      pins: pins,
      analysis: analysis,
      manifest: manifest,
      reference_index: reference_index
    )
    upgrade_front_document!(front, pre00_handoff: pre00_handoff_path, sequence: sequence, scene: scene, support: support, pins: pins)
    @front_path = run_dir.join("front-planning.yaml")
    write_yaml(front_path, front)
    write_density_locator_sheet!(front_path)
    write_kinetic_slot_sheet!(front_path)
    attempt_key = "attempt-01"
    @sequence_motion_analysis_path = run_dir.join("research", "sequence-motion-analysis", "S01--MJ01", "#{attempt_key}.yaml")
    write_file(sequence_motion_analysis_path, "pending Sequence Motion Analysis fixture bytes\n")
    @sequence_motion_dispatch_path = run_dir.join("work", "department-dispatches", "sequence-motion-analysis-MJ01--#{attempt_key}.yaml")
    provisional_dispatch = sequence_motion_dispatch_document(
      front,
      artifact_path: sequence_motion_analysis_path,
      audio_motion_map_path: audio_motion_map_path
    )
    write_yaml(sequence_motion_dispatch_path, provisional_dispatch)
    sequence_motion = ActiveSequenceMotionFixture.document(
      self,
      front,
      dispatch_path: sequence_motion_dispatch_path,
      audio_motion_map_path: audio_motion_map_path,
      attempt_key: attempt_key
    )
    write_yaml(sequence_motion_analysis_path, sequence_motion)
    final_dispatch = sequence_motion_dispatch_document(
      front,
      artifact_path: sequence_motion_analysis_path,
      audio_motion_map_path: audio_motion_map_path
    )
    write_yaml(sequence_motion_dispatch_path, final_dispatch)
    selected_candidate = front.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates", 0)
    selected_candidate["sequence_motion_analysis_binding"] = {
      "path" => relative(sequence_motion_analysis_path),
      "sha256" => file_sha(sequence_motion_analysis_path),
      "schema_version" => "idol_sequence_motion_analysis.v1",
      "json_pointer" => "/candidate_analyses/0",
      "value_sha256" => value_sha(sequence_motion.fetch("candidate_analyses").first),
      "independent_cdd_review_binding" => {
        "path" => relative(sequence_motion_dispatch_path),
        "sha256" => file_sha(sequence_motion_dispatch_path),
        "schema_version" => "idol-department-dispatch.v8",
        "json_pointer" => "/director_review",
        "value_sha256" => value_sha(final_dispatch.fetch("director_review"))
      }
    }
    write_yaml(front_path, front)
    write_density_locator_sheet!(front_path)
    write_kinetic_slot_sheet!(front_path)

    direction = direction_document(front, song)
    upgrade_direction_document!(direction, front)
    @direction_path = write_yaml(run_dir.join("01-section-direction.yaml"), direction)

    draft_keyframe = write_file(run_dir.join("02A", "draft-keyframes", "S01-MJ01-fp-hero-core.png"), "Draft Keyframe Proof fp_hero_core pixels\n")
    draft_criteria = %w[
      cut_screen_job_neighbor_delta
      character_visual
      scene_visual_package
      action_pose_motion_readiness
      angle_distance_depth_crop_transition_diversity
      reference_transfer_generation_feasibility
      prop_interaction_readability
    ]
    @draft_keyframe_grade_path = write_yaml(
      run_dir.join("review", "02A-draft-keyframe-contextual-grade.yaml"),
      {
        "schema_version" => "idol_planning_contextual_grade_vector.v1",
        "artifact_type" => "planning_contextual_grade_vector",
        "stage" => "draft_keyframe_proof",
        "scope_id" => direction.fetch("production_scope_id"),
        "authoring_owner" => "human_or_assigned_model",
        "reviewer_role" => "planning_cdd_p3_ci",
        "performance_mode" => "none",
        "preview_packet_mode" => "fp_hero_core",
        "source_artifacts" => [artifact_ref(draft_keyframe)],
        "criteria" => draft_criteria.map do |criterion_id|
          row = {
            "criterion_id" => criterion_id,
            "result" => %w[scene_visual_package action_pose_motion_readiness].include?(criterion_id) ? 4 : 3,
            "evidence_locator" => "exact Draft Keyframe pixels and immediate 02A neighbors",
            "review_note" => "Assigned Planning CDD reviewed exact draft pixels."
          }
          if criterion_id == "prop_interaction_readability"
            row["result"] = "not_applicable_no_material_prop"
            row["not_applicable_reason"] = "No material prop exists in this fixture Cut."
          end
          row
        end,
        "decision" => "eligible_for_director_review",
        "target_message_treatment" => "pre_fp_locks_not_downstream_pixel_scores",
        "aggregate_score_present" => false,
        "automatic_creative_pass" => false,
        "downstream_pixel_rubric_reuse" => "forbidden",
        "status" => "reviewed"
      }
    )

    @storyboard = storyboard_document(front, direction, member, sequence)
    upgrade_storyboard_document!(@storyboard, front, direction)
    @storyboard_path = write_yaml(run_dir.join("02A-storyboard.yaml"), storyboard)
    storyboard_sha = file_sha(storyboard_path)

    context_review = context_review_document(storyboard_sha)
    @context_review_path = write_yaml(run_dir.join("02A-context-review.yaml"), context_review)

    @delta = delta_document(storyboard_sha, member)
    @delta_path = write_yaml(run_dir.join("02B-translation.yaml"), delta)
    self
  end

  def rewrite_storyboard
    @storyboard_path = write_yaml(storyboard_path, storyboard)
    refresh_storyboard_dependents
  end

  def rewrite_delta
    @delta_path = write_yaml(delta_path, delta)
  end

  def rewrite_sequence_motion(document)
    document.dig("dispatch_and_authorship")["result_sha256"] = value_sha(
      "candidate_analyses" => document.fetch("candidate_analyses"),
      "comparative_recommendation" => document.fetch("comparative_recommendation")
    )
    write_yaml(sequence_motion_analysis_path, document)
    front = YAML.safe_load(front_path.read, aliases: true)
    dispatch_path = sequence_motion_dispatch_path
    dispatch = sequence_motion_dispatch_document(front, artifact_path: sequence_motion_analysis_path, audio_motion_map_path: audio_motion_map_path)
    write_yaml(dispatch_path, dispatch)
    selected = front.dig("major_scene_catalog", 0, "sequence_composition_candidate_set", "candidates", 0)
    selected["sequence_motion_analysis_binding"] = {
      "path" => relative(sequence_motion_analysis_path),
      "sha256" => file_sha(sequence_motion_analysis_path),
      "schema_version" => "idol_sequence_motion_analysis.v1",
      "json_pointer" => "/candidate_analyses/0",
      "value_sha256" => value_sha(document.fetch("candidate_analyses").first),
      "independent_cdd_review_binding" => {
        "path" => relative(dispatch_path),
        "sha256" => file_sha(dispatch_path),
        "schema_version" => "idol-department-dispatch.v8",
        "json_pointer" => "/director_review",
        "value_sha256" => value_sha(dispatch.fetch("director_review"))
      }
    }
    write_yaml(front_path, front)
    write_density_locator_sheet!(front_path)
    write_kinetic_slot_sheet!(front_path)
    document
  end

  def return_sequence_motion_dispatch_for_copy!
    dispatch = YAML.safe_load(sequence_motion_dispatch_path.read, aliases: true)
    dispatch.dig("lifecycle")["current_state"] = "returned"
    dispatch.dig("lifecycle")["events"] = Array(dispatch.dig("lifecycle", "events")).first(3)
    review_control = dispatch.fetch("review_control")
    review_control["queue_state"] = "queued"
    review_control["review_lease"] = nil
    review_control["promotion_lease"] = nil
    dispatch["director_review"] = nil
    dispatch["promotion"] = nil
    write_yaml(sequence_motion_dispatch_path, dispatch)
    dispatch
  end

  def refresh_storyboard_dependents
    storyboard_sha = file_sha(storyboard_path)
    review = context_review_document(storyboard_sha)
    @context_review_path = write_yaml(context_review_path, review)
    delta["source_02a"]["artifact_sha256"] = storyboard_sha
    delta["readiness_evidence"]["storyboard_context_review"]["artifact_sha256"] = file_sha(context_review_path)
    refresh_packet_bindings
    rewrite_delta
  end

  def refresh_packet_bindings
    branch_rows.each do |core_cut, core_index, branch_cut, branch_index|
      packet = delta.fetch("packets").find { |row| row["packet_id"] == branch_cut["packet_id"] }
      next unless packet

      packet["parent_core_cut_ref"]["value_sha256"] = value_sha(core_cut)
      packet["branch_cut_ref"]["value_sha256"] = value_sha(branch_cut)
      revision = packet.fetch("direct_prompt_revision")
      revision["source_02a_branch_cut_lock_sha256"] = value_sha(branch_cut)
      revision["same_section_context"] = same_section_context(core_index, branch_index)
      revision["storyline_authoring_binding"] = storyline_authoring_binding(branch_cut)
      receipt = revision.fetch("authoring_inspection_receipt")
      receipt["source_02a_branch_cut_sha256"] = value_sha(branch_cut)
      receipt["source_storyline_alignment_binding_sha256"] = value_sha(
        branch_cut.fetch("storyline_alignment_binding")
      )
      bindings = branch_cut.fetch("visual_reference_bindings")
      receipt["inspected_visual_reference_binding_ids"] = bindings.map { |binding| binding.fetch("binding_id") }
      receipt["inspected_current_title_asset_ids"] = bindings.each_with_object([]) do |binding, ids|
        ids << binding.fetch("asset_id") if binding.fetch("reference_class").start_with?("current_title_")
      end
    end
  end

  def context_sha(core_position, branch_position)
    value_sha(context_payload(core_position, branch_position))
  end

  def value_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end

  def file_sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def sequence_motion_dispatch_document(front, artifact_path:, audio_motion_map_path:, attempt_number: nil, previous_attempt_id: nil)
    major = front.fetch("major_scene_catalog").first
    candidate_set = major.fetch("sequence_composition_candidate_set")
    attempt_key = Pathname.new(artifact_path).basename(".yaml").to_s
    parsed_attempt_number = attempt_key[/\Aattempt-([0-9]{2,})\z/, 1]&.to_i
    attempt_number ||= parsed_attempt_number || 1
    dispatch_id = "sequence-motion-analysis-#{major.fetch('major_scene_id')}--#{attempt_key}"
    snapshot = {
      "major_scene_id" => major.fetch("major_scene_id"),
      "section_id" => major.fetch("section_id"),
      "semantic_event_or_relation_job" => major.fetch("semantic_event_or_relation_job"),
      "candidate_set_id" => candidate_set.fetch("candidate_set_id"),
      "candidates" => candidate_set.fetch("candidates").map do |candidate|
        candidate.slice("sequence_composition_id", "typed_sequence_unit_ids", "flow_reading", "mismatch_and_risk")
      end
    }
    active_storyline_sha = value_sha(front.dig("storyline_lineage", "active_version", "full_storyline_text"))
    objective = "Analyze #{candidate_set.fetch('candidates').map { |row| row.fetch('sequence_composition_id') }.join(', ')} as one MJ01 candidate group; candidate_snapshot_sha256=#{value_sha(snapshot)}; active_storyline_passage_value_sha256=#{active_storyline_sha}; jointly assess motion, gaze, visible identity cues, style, and clothing; author no 01, 02A, or 03V truth."
    dispatch = dispatch_fixture_promoted_document(
      run_path: run_dir,
      dispatch_id: dispatch_id,
      stage_id: "front_planning_integration",
      artifact_path: artifact_path,
      owner_role: "department_worker",
      profile_id: "reference_research_generalist",
      checkpoint_id: "reference_story_sequence_role",
      assigned_owner: "fixture-reference-sequence-worker",
      director_owner: "fixture-cdd",
      recipient_role: "creative_development_director",
      output_role: "worker-authored Sequence Motion Analysis ready for independent CDD review",
      objective: objective
    )
    dispatch.fetch("lineage")["lineage_id"] = "LINEAGE_sequence-motion-analysis-#{major.fetch('major_scene_id')}"
    dispatch.fetch("lineage")["attempt_id"] = dispatch_id
    dispatch.fetch("lineage")["attempt_number"] = attempt_number
    dispatch.fetch("lineage")["previous_attempt_id"] = previous_attempt_id
    artifact_relative = relative(artifact_path)
    scope = dispatch.dig("launch", "task", "exact_scope")
    scope["mode"] = "section"
    scope["section_ids"] = ["S01"]
    scope["artifact_paths"] = [artifact_relative]
    dispatch.dig("launch", "bounded_output")["expected_paths"] = [artifact_relative]
    dispatch.dig("launch", "bounded_output")["description"] = "One immutable worker-authored Sequence Motion Analysis attempt for S01/MJ01."
    dispatch.dig("launch", "bounded_output")["anti_flat_evidence_requirements"] = [
      "Compare every candidate in the exact MJ01 group and type observed events separately from inferred camera opportunities.",
      "Jointly assess body action, gaze and head direction, camera translation and rotation, lens change, angle and composition reframe, depth, occlusion, reveal, and start and landing.",
      "Record only identity cues actually visible, require exact current-title identity, hair, styling, clothing, silhouette, and member-specific detail for those listed cues, and never force a member, frontal face, or frontal gaze.",
      "Name a motion family only from exact observed interframe evidence; orbit and every other family are contextual rather than defaults, and ambiguity remains inference or HOLD.",
      "Return exact analysis path and SHA plus candidate result evidence for independent CDD review without authoring 01, 02A, or 03V truth."
    ]

    manifest_refs = candidate_set.fetch("candidates").flat_map { |candidate| candidate.fetch("typed_sequence_unit_ids") }.uniq.each_with_object([]) do |unit_id, rows|
      unit = front.dig("reference_connection_research", "reference_units").find do |row|
        row.dig("sequence_unit", "sequence_unit_id") == unit_id
      end
      manifest = unit&.dig("sequence_unit", "manifest")
      rows << manifest if manifest
    end
    sources = manifest_refs.uniq { |row| [row.fetch("path"), row.fetch("sha256")] }.each_with_index.map do |row, index|
      {"source_id" => "sequence_manifest_#{format('%02d', index + 1)}", "path" => row.fetch("path"), "sha256" => row.fetch("sha256"), "purpose" => "Exact governing Sequence Unit manifest for the bounded candidate group."}
    end
    sources << {"source_id" => "audio_motion_map", "path" => relative(audio_motion_map_path), "sha256" => file_sha(audio_motion_map_path), "purpose" => "Exact audio timing evidence for S01."}
    dispatch.dig("launch")["sources"] = sources
    apply_sequence_motion_requirement_contract!(dispatch, artifact_relative)
    compiled = dispatch.dig("launch", "compiled_launch_prompt")
    compiled["current_run_creative_delta_source_ids"] = sources.map { |row| row.fetch("source_id") }
    compiled["rendered_prompt"] = sequence_motion_rendered_prompt(
      front,
      requirement_manifest: dispatch.dig("launch", "requirement_manifest"),
      anti_flat_evidence_requirements: dispatch.dig("launch", "bounded_output", "anti_flat_evidence_requirements")
    )
    compiled["rendered_prompt_sha256"] = Digest::SHA256.hexdigest(compiled.fetch("rendered_prompt"))
    compiled_basis = compiled.reject { |key, _value| %w[rendered_prompt compiled_input_sha256 rendered_prompt_sha256].include?(key) }
    compiled["compiled_input_sha256"] = dispatch_fixture_structured_sha(compiled_basis)

    routing = dispatch.fetch("routing_identity")
    routing["worker_specialty"] = "reference_story_sequence"
    routing["session_topology"] = "internal_parent_work_package"
    routing["physical_transfer"] = nil
    routing["active_role_binding_id"] = "ACTIVE-CDD-FIXTURE"
    routing["return_recipient_role"] = "creative_development_director"

    project_sequence_dispatch_checkpoint_bindings!(dispatch)

    runtime = dispatch.fetch("runtime_return")
    runtime.dig("input_digest")["sha256"] = dispatch_fixture_structured_sha(
      "lineage" => dispatch.fetch("lineage"),
      "review_submission" => dispatch.fetch("review_submission"),
      "launch" => dispatch.fetch("launch")
    )
    result_basis = %w[
      work_started_at runtime_owner runtime_goal skill_revisions
      mechanical_compliance_receipt worker_fulfillment_claims output_inventory
      outputs hold_reasons wake_event
    ].to_h { |key| [key, runtime[key]] }
    runtime.dig("result_digest")["sha256"] = dispatch_fixture_structured_sha(result_basis)
    dispatch
  end

  private

  def sequence_motion_current_values(front)
    major = front.fetch("major_scene_catalog").first
    candidate_set = major.fetch("sequence_composition_candidate_set")
    {
      "active_storyline_passage" => front.dig("storyline_lineage", "active_version", "full_storyline_text"),
      "major_scene_id" => major.fetch("major_scene_id"),
      "section_id" => major.fetch("section_id"),
      "semantic_event_or_relation_job" => major.fetch("semantic_event_or_relation_job"),
      "candidate_set_id" => candidate_set.fetch("candidate_set_id"),
      "candidates" => candidate_set.fetch("candidates").map do |candidate|
        candidate.slice("sequence_composition_id", "typed_sequence_unit_ids", "flow_reading", "mismatch_and_risk")
      end
    }
  end

  def sequence_motion_prompt_clauses
    [
      "Conditional visible identity: do not require a readable face in every cut; when identity is visible, preserve exact current-title identity.",
      "No forced frontal face or gaze: side, rear, silhouette, occluded, wide, and fast-turn views remain legal when they serve the scene.",
      "Member-specific visible cues: preserve every visible member-specific hair, styling, clothing, silhouette, and detail cue even when the face is unreadable.",
      "Continuous camera energy is a hypothesis: test it against body action, gaze, camera translation and rotation, lens, angle, composition, depth, occlusion, reveal, and start-to-landing evidence; it is never a forced default.",
      "Intentional locked hold is allowed: retain a motivated static or locked choice when it is stronger than movement."
    ]
  end

  def sequence_motion_rendered_prompt(front, requirement_manifest:, anti_flat_evidence_requirements:)
    context = JSON.pretty_generate(dispatch_fixture_canonicalize(sequence_motion_current_values(front)))
    context_block = [
      "SEQUENCE_MOTION_CURRENT_VALUES_CANONICAL_JSON_BEGIN",
      context,
      "SEQUENCE_MOTION_CURRENT_VALUES_CANONICAL_JSON_END"
    ].join("\n")
    [
      dispatch_fixture_rendered_prompt(
        requirement_manifest: requirement_manifest,
        anti_flat_evidence_requirements: anti_flat_evidence_requirements
      ),
      context_block
    ].join("\n\n")
  end

  def apply_sequence_motion_requirement_contract!(dispatch, artifact_relative)
    requirements = dispatch.dig("launch", "requirement_manifest")
    specifications = {
      "founder" => {
        "requirement_id" => "FOUNDER-SEQUENCE-CONTEXT",
        "source_locator" => "/launch/compiled_launch_prompt/rendered_prompt",
        "source_binding" => nil,
        "affected_scope" => "Exact active full-storyline passage, bounded Section and Major semantic event or relation job, and every value in the complete two-to-four-candidate group are present in SEQUENCE_MOTION_CURRENT_VALUES_CANONICAL_JSON.",
        "evidence_type" => "field"
      },
      "policy" => {
        "requirement_id" => "POLICY-SEQUENCE-MOTION-EVIDENCE",
        "source_locator" => "policies/harness-routing-and-sources.md",
        "source_binding" => {
          "path" => "policies/harness-routing-and-sources.md",
          "sha256" => file_sha(ROOT.join("policies", "harness-routing-and-sources.md")),
          "role" => "governing policy"
        },
        "affected_scope" => "Observed interframe evidence stays separate from inference; motion families are evidence-based and never default to orbit or another family.",
        "evidence_type" => "artifact"
      },
      "quality" => {
        "requirement_id" => "QUALITY-SEQUENCE-MOTION-ACCEPTANCE",
        "source_locator" => "/launch/compiled_launch_prompt/rendered_prompt",
        "source_binding" => nil,
        "affected_scope" => sequence_motion_prompt_clauses.join(" "),
        "evidence_type" => "artifact"
      }
    }
    id_map = {}
    requirements.each do |requirement|
      specification = specifications[requirement.fetch("category")]
      next unless specification

      old_id = requirement.fetch("requirement_id")
      requirement.merge!(specification)
      requirement["expected_output_target"] = artifact_relative
      requirement["director_semantic_review_required"] = true
      id_map[old_id] = requirement.fetch("requirement_id")
    end

    runtime = dispatch.fetch("runtime_return")
    receipt = runtime.fetch("mechanical_compliance_receipt")
    Array(receipt["checks"]).each do |check|
      next unless id_map.key?(check["requirement_id"])

      check["requirement_id"] = id_map.fetch(check["requirement_id"])
      check["check_id"] = "MECH-#{check.fetch('requirement_id')}"
      check["evidence"] = "Fixture structural evidence exists for #{check.fetch('requirement_id')}."
    end
    Array(runtime["worker_fulfillment_claims"]).each do |claim|
      next unless id_map.key?(claim["requirement_id"])

      claim["requirement_id"] = id_map.fetch(claim["requirement_id"])
      claim["explanation"] = "The worker applied #{claim.fetch('requirement_id')} to the exact bounded fixture result."
    end
    Array(dispatch.dig("director_review", "requirement_results")).each do |result|
      next unless id_map.key?(result["requirement_id"])

      result["requirement_id"] = id_map.fetch(result["requirement_id"])
      result["judgment"] = "The Director read the exact returned bytes and judged #{result.fetch('requirement_id')} complete."
    end

    receipt["receipt_sha256"] = dispatch_fixture_structured_sha(receipt.reject { |key, _value| key == "receipt_sha256" })
    dispatch.dig("director_review")["mechanical_receipt_sha256"] = receipt.fetch("receipt_sha256")
    goal_completion_basis = {
      "mechanical_compliance_receipt_sha256" => receipt.fetch("receipt_sha256"),
      "worker_fulfillment_claims" => runtime.fetch("worker_fulfillment_claims"),
      "outputs" => runtime.fetch("outputs"),
      "hold_reasons" => runtime.fetch("hold_reasons")
    }
    runtime.dig("runtime_goal")["completion_evidence_sha256"] = dispatch_fixture_structured_sha(goal_completion_basis)
  end

  def project_sequence_dispatch_checkpoint_bindings!(dispatch)
    launch = dispatch.fetch("launch")
    selected = launch.dig("compiled_launch_prompt", "selected_profile")
    contract = dispatch_fixture_profile_contract(
      profile_id: selected.fetch("profile_id"),
      checkpoint_id: selected.fetch("checkpoint_id")
    )
    required_skills = Marshal.load(Marshal.dump(contract.fetch("required_skills")))
    launch["required_skills"] = required_skills
    launch.delete("required_reads")

    runtime = dispatch.fetch("runtime_return")
    prior_skill = Array(runtime["skill_revisions"]).first
    read_completed_at = prior_skill&.fetch("read_completed_at", nil) || "2026-08-03T12:01:20+09:00"
    runtime["skill_revisions"] = dispatch_fixture_runtime_skill_revisions(
      required_skills,
      read_completed_at: read_completed_at
    )

    projected_reviewer_reads = required_skills.flat_map do |skill|
      [{
        "path" => skill.fetch("path"),
        "kind" => "skill",
        "revision" => skill.fetch("revision"),
        "sha256" => skill.fetch("sha256"),
        "read_to_eof" => true,
        "read_completed_at" => "2026-08-03T12:02:30+09:00"
      }] + Array(skill["linked_reads"]).map do |read|
        {
          "path" => read.fetch("path"),
          "kind" => "linked_module",
          "revision" => "hash-bound-launch-read",
          "sha256" => read.fetch("sha256"),
          "read_to_eof" => true,
          "read_completed_at" => "2026-08-03T12:02:30+09:00"
        }
      end
    end
    non_checkpoint_reads = Array(dispatch.dig("director_review", "reviewer_read_closure")).reject do |row|
      %w[skill linked_module].include?(row["kind"].to_s)
    end
    dispatch.dig("director_review")["reviewer_read_closure"] = (projected_reviewer_reads + non_checkpoint_reads).uniq do |row|
      [row["path"].to_s, row["sha256"].to_s]
    end
  end

  def branch_rows
    storyboard.fetch("master_storyboard").each_with_index.flat_map do |core_cut, core_index|
      Array(core_cut.dig("compile_seed", "branch_cuts")).each_with_index.map do |branch_cut, branch_index|
        [core_cut, core_index, branch_cut, branch_index]
      end
    end
  end

  def write_file(path, content)
    path.dirname.mkpath
    path.binwrite(content)
    {"path" => relative(path), "sha256" => file_sha(path)}
  end

  def write_yaml(path, document)
    path.dirname.mkpath
    path.write(YAML.dump(document))
    path
  end

  def write_density_locator_sheet!(artifact_path)
    write_yaml(
      Pathname.new(artifact_path).sub_ext(".density-locators.yaml"),
      IdolStorylineDensityLocatorContract.complete_sheet(relative(artifact_path))
    )
  end

  def kinetic_slot_sheet_document(major_id: "MJ01", section_id: "S01")
    one = "KSL_#{major_id}_01"
    two = "KSL_#{major_id}_02"
    three = "KSL_#{major_id}_03"
    {
      "schema_version" => IdolKineticSlotSheetContract::CONTRACT_VERSION,
      "major_scene_id" => major_id,
      "section_id" => section_id,
      "automatic_creative_pass" => false,
      "sequence_evidence" => {
        "sequence_unit_ids" => ["SEQU_REF_01"],
        "not_cut_plan" => true
      },
      "slots" => [
        {
          "slot_id" => one,
          "ordinal" => 1,
          "change_axis" => "action",
          "previous_slot_id" => nil,
          "production_binding" => "core",
          "screen_job" => "readable event beat",
          "visible_action_or_hold" => "the subject continues the same event",
          "still_camera" => {
            "camera_height" => "eye",
            "shot_scale_distance" => "MS",
            "direction_angle" => "front",
            "depth" => "subject in middle ground"
          }
        },
        {
          "slot_id" => two,
          "ordinal" => 2,
          "change_axis" => "angle",
          "previous_slot_id" => one,
          "production_binding" => "core",
          "screen_job" => "readable event beat",
          "visible_action_or_hold" => "the subject continues the same event",
          "still_camera" => {
            "camera_height" => "high",
            "shot_scale_distance" => "MS",
            "direction_angle" => "profile",
            "depth" => "subject in middle ground"
          }
        },
        {
          "slot_id" => three,
          "ordinal" => 3,
          "change_axis" => "authored_hold",
          "previous_slot_id" => two,
          "production_binding" => "branch",
          "screen_job" => "readable event beat",
          "visible_action_or_hold" => "the subject continues the same event",
          "hold_reason" => "locked-angle continuation of the same event",
          "continuity_in" => "enters from the prior angle change",
          "continuity_out" => "hands the same body line to the next Major"
        }
      ],
      "core_nail_slot_ids" => [one, two],
      "key_screen_inheritances" => [
        {
          "key_screen_id" => "KS_S01_CONTACT",
          "inherits_from_slot_id" => one,
          "inherits" => "still_camera_and_action",
          "camera_reauthored" => false
        },
        {
          "key_screen_id" => "KS_S01_OVERHEAD",
          "inherits_from_slot_id" => two,
          "inherits" => "still_camera_and_action",
          "camera_reauthored" => false
        }
      ],
      "collected_production_start_pairs" => [
        {
          "left_slot_id" => one,
          "right_slot_id" => two,
          "declared_change_axis_or_hold" => "angle",
          "same_image_exact_carry" => false
        }
      ]
    }
  end

  def write_kinetic_slot_sheet!(artifact_path, major_id: "MJ01", section_id: "S01")
    write_yaml(
      IdolKineticSlotSheetContract.sheet_path_for(artifact_path, major_id),
      kinetic_slot_sheet_document(major_id: major_id, section_id: section_id)
    )
  end

  def artifact_ref(entry)
    {"path" => entry.fetch("path"), "sha256" => entry.fetch("sha256")}
  end

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

  def founder_sequence_control_document
    refs = %w[REF-01 REF-02 REF-03].map do |reference_id|
      {
        "reference_id" => reference_id,
        "assignment_owner" => "assigned_director_proposal",
        "source_identity" => "SOURCE-#{reference_id}",
        "source_path_or_url" => "references/#{reference_id}.png",
        "selected_range_or_surface" => "selected fixture surface",
        "exact_use_function" => "Control one named Major screen contribution.",
        "target_control_major_ids" => ["FSC_MAJOR_01"],
        "preserve" => ["Named function and order."],
        "replace_or_discard" => ["Source identity."],
        "disposition" => "applied"
      }
    end
    {
      "schema_version" => "idol_founder_sequence_control.v2",
      "content_id" => "ACTIVE_TITLE_TEST",
      "lane" => "idol_mv",
      "status" => "director_ready",
      "source_capture" => {
        "start_authorization_mode" => "founder_direction_supplied",
        "founder_verbatim_inputs" => ["The member deliberately breaks one visible system rule and the world records the consequence."],
        "transcription_owner" => "assigned_director_codex_or_grok",
        "founder_does_not_fill_schema_fields" => true
      },
      "story_flow" => {
        "one_line_direction" => "One deliberate action changes the system.",
        "message_or_viewer_result" => "Agency becomes visible through consequence.",
        "opening_state" => "The calibration system appears fixed.",
        "ordered_major_scenes" => [{
          "control_major_id" => "FSC_MAJOR_01",
          "order_index" => 1,
          "direction_owner" => "assigned_director_proposal",
          "direction" => "The member deliberately breaks one visible system rule and the world records the consequence.",
          "major_scene_boundaries" => ["Keep one governing alignment event; do not turn it into a portrait montage."],
          "required_subject_or_member_ids" => ["M01"],
          "required_action_or_hold" => "M01 registers the marker.",
          "space_direction" => "Use scene references for the calibration field; create no background asset.",
          "reference_ids" => ["REF-01", "REF-02"],
          "entry_state" => "The marker is offset.",
          "endpoint" => "The marker is registered.",
          "continuity_to_next" => "The registered state persists."
        }],
        "ending_or_afterimage" => "The registered state remains visible.",
        "hard_locks" => ["Preserve Founder Major order."],
        "forbidden_outcomes" => ["Portrait montage."]
      },
      "reference_plan" => {
        "governing_reference_ids" => ["REF-01"],
        "references" => refs,
        "unresolved_reference_choices" => []
      },
      "director_translation" => {
        "translation_owner" => "assigned_director_codex_or_grok",
        "translated_message" => "The choice changes the route.",
        "observable_sequence" => [{
          "control_major_id" => "FSC_MAJOR_01",
          "visible_action_or_hold" => "M01 registers the marker.",
          "screen_change" => "The guide lights along the registered position.",
          "camera_and_composition_read" => "Lateral depth keeps cause and consequence readable.",
          "sound_opportunity" => "A calibration click marks contact.",
          "endpoint" => "The registered state remains lit.",
          "continuity_to_next" => "Carry the registered state forward."
        }],
        "conflicts_and_resolutions" => [],
        "explicit_founder_locks_preserved" => true,
        "director_fills_unspecified_story_order" => true,
        "reference_roles_are_proposals_unless_founder_locked" => true
      },
      "minimal_intervention_contract" => {
        "founder_may_start_with_one_short_input" => true,
        "director_authors_first_recommended_sequence" => true,
        "director_authors_major_scene_proposals" => true,
        "director_authors_and_quality_checks_key_screens" => true,
        "separate_major_approval_required" => false,
        "separate_key_screen_approval_required" => false,
        "new_member_visual_requires_founder_selection" => true,
        "unresolved_material_conflict_requires_founder_decision" => true,
        "front_planning_final_gate_required" => true,
        "separate_background_asset_generation" => false
      },
      "startup_gate" => {
        "decision" => "start_authorized",
        "unresolved_material_choices" => [],
        "projection_authorized" => true,
        "note" => "Founder authorized the first director proposal."
      }
    }
  end

  def upgrade_founder_sequence_control!(document)
    document["schema_version"] = "idol_founder_sequence_control.v3"
    major = document.dig("story_flow", "ordered_major_scenes", 0)
    major["control_major_id"] = "MJ01"
    major["section_id"] = "S01"
    document.dig("director_translation", "observable_sequence", 0)["control_major_id"] = "MJ01"
    slots = %w[A B C X Y Z]
    document["reference_plan"]["references"] = slots.each_with_index.map do |slot, index|
      reference_id = index < 3 ? format("REF-%02d", index + 1) : "REF-#{slot}"
      {
        "reference_id" => reference_id,
        "reference_slot" => slot,
        "assignment_owner" => "assigned_director_proposal",
        "source_identity" => "SOURCE-#{reference_id}",
        "source_path_or_url" => "references/#{reference_id}.png",
        "selected_range_or_surface" => "selected fixture surface",
        "exact_use_function" => "Control one named Major screen contribution.",
        "target_section_ids" => ["S01"],
        "target_control_major_ids" => ["MJ01"],
        "preserve" => ["Named function and order."],
        "replace_or_discard" => ["Source identity."],
        "disposition" => "applied"
      }
    end
    document.dig("reference_plan", "governing_reference_ids").replace(["REF-01"])
    document
  end

  def alignment_reference(id, locator, contribution, relationship)
    {
      "reference_unit_id" => id,
      "selected_locator" => locator,
      "observable_contribution" => contribution,
      "relationship_to_other_references" => relationship,
      "preserve" => ["Preserve the named observable contribution and its bounded relationship."],
      "discard" => ["Discard source identity and unselected surfaces."]
    }
  end

  def alignment_camera(scale, height, angle)
    {
      "shot_scale_distance" => scale,
      "camera_height" => height,
      "direction_angle" => angle,
      "depth" => "foreground scale marks, subject plane, and flat calibration backdrop",
      "subject_placement" => "member or marker remains offset so the printed guide stays readable",
      "crop_negative_space" => "retain clear space around the marker route and response ring",
      "lens_feel" => "restrained normal perspective without beauty-shot compression"
    }
  end

  def alignment_cut(id, key_screen_id, order, world_cut, references)
    {
      "planning_cut_id" => id,
      "source_key_screen_id" => key_screen_id,
      "section_id" => "S01",
      "sequence_order" => order,
      "primary_audio_cue" => "The first percussive break.",
      "shot_storyline" => world_cut ? "After the hand leaves frame, hold the guide from above so the newly registered geometry becomes the visible consequence." : "Keep the calibration direction and move close enough to read hands and chest before face as M01 aligns the marker.",
      "visible_subjects" => world_cut ? "The marker and printed guide; M01 is absent." : "M01's rear three-quarter torso, hands, and the marker.",
      "subject_state_and_pose" => world_cut ? "No member pose; the system holds its registered state." : "M01 keeps her shoulder still and gathers both hands before one wrist completes the measured alignment.",
      "visible_action_or_hold" => world_cut ? "Hold on the illuminated registration pattern without a second event." : "One small hand adjustment moves the marker from offset to registered position.",
      "gaze_expression_and_body_tension" => world_cut ? "No face; tension transfers to the exact marker position." : "Her gaze stays on her hand, with fine tension in fingers and wrist.",
      "staging_and_blocking" => world_cut ? "Center the marker while keeping the full response ring visible." : "Keep M01 on the left third and the guide unobstructed at center-right.",
      "object_or_environment_response" => world_cut ? "Guide lines illuminate only after registration and remain smaller than the member action." : "The marker changes position; the guide does not react until contact completes.",
      "space_and_depth" => world_cut ? "Orthographic guide layers reveal the complete registered geometry." : "Foreground scale marks and the flat backdrop preserve lateral depth around the hand.",
      "still_camera" => world_cut ? alignment_camera("top-down medium insert at two meters", "two meters above the guide", "orthographic overhead") : alignment_camera("medium-wide at four meters", "waist height", "lateral rear three-quarter view"),
      "light_color_material" => world_cut ? "Neutral silver field with one controlled white response ring." : "Soft neutral reflection on skin and cloth against matte printed surfaces.",
      "reference_contributions" => references,
      "must_show" => world_cut ? ["full registered geometry", "M01 absent after the action"] : ["hands read before face", "marker visibly moves into registration"],
      "avoid" => world_cut ? ["a second magical effect", "cropping the response ring"] : ["frontal face-first portrait", "large theatrical gesture"],
      "continuity_in" => world_cut ? "Match the marker position reached in PC_S01_CONTACT." : "Enter from the unchanged offset state.",
      "continuity_out" => world_cut ? "Leave the registered state as the section afterimage." : "Let the completed marker position motivate the overhead proof.",
      "generation_intent" => world_cut ? "Generate a quiet object-and-world consequence still." : "Generate the hand-first member action still."
    }
  end

  def founder_visual_alignment_document
    ref_01 = alignment_reference("REF-01", "SEQB_REF_01 frames 01-05", "Provides the marker alignment action order.", "Governs action while REF-02 controls camera and REF-03 controls response scale.")
    ref_02 = alignment_reference("REF-02", "selected crop", "Provides lateral placement and calibration-field geometry.", "Supports REF-01 without replacing its ordered action.")
    ref_03 = alignment_reference("REF-03", "selected crop", "Provides the restrained system response after contact.", "Completes the causal read without adding another event.")
    {
      "alignment_version" => "founder_visual_alignment.v1",
      "revision_id" => "ALIGNMENT-ACTIVE-01",
      "authored_at" => "2026-08-06T12:00:00+09:00",
      "authoring_owner" => "creative_development_director",
      "review_phase" => "fp_close",
      "source_reference_unit_ids" => ["REF-01", "REF-02", "REF-03"],
      "whole_film_readout" => {
        "audience_entry_state" => "The viewer first reads an unchanged calibration system.",
        "video_form" => "world_system_led",
        "form_logic" => "The member's restrained action and the calibration world's response carry the selected song without requiring a feature-film plot.",
        "screen_progression" => "The marker begins offset, M01 aligns it, and the system preserves the registered geometry after she leaves the screen.",
        "progression_turns" => ["Her hand moves the marker into registration.", "The guide illuminates and retains the new state."],
        "ending_or_afterimage" => "The registered marker and response ring remain without the member.",
        "member_and_world_relationship" => "A small member action causes a precise but subordinate world response.",
        "camera_progression" => "Move from architectural calibration context to hand-first lateral action, then to overhead spatial proof.",
        "light_color_material_progression" => "Neutral matte surfaces receive soft member reflection, then one controlled white guide response.",
        "reference_combination_logic" => [ref_01, ref_02, ref_03],
        "continuity_and_misread_risks" => ["Do not show a face-first beauty shot.", "Do not make the system reaction larger than the hand action."]
      },
      "section_readouts" => [{
        "section_id" => "S01",
        "primary_audio_cue" => "The first percussive break.",
        "entry_state" => "The marker sits offset and the printed guide is unlit.",
        "section_event" => "M01 aligns the marker and the guide records the registered state.",
        "visible_subjects" => "M01 from behind, her hands, the marker, and the printed guide.",
        "visible_action_or_hold" => "Her hands gather near chest height before one wrist makes the final measured adjustment.",
        "gaze_expression_and_body_tension" => "Her gaze stays on the hand with tension in fingers and wrist, never at camera.",
        "staging_and_blocking" => "M01 holds the left third while the guide and marker remain unobstructed to the right.",
        "object_or_environment_response" => "Guide lines illuminate only when the marker reaches registration.",
        "space_and_depth" => "Foreground scale marks, member plane, and matte backdrop keep the action spatially legible.",
        "still_camera" => alignment_camera("medium-wide at four meters", "waist height", "lateral rear three-quarter view"),
        "light_color_material" => "Soft neutral skin and cloth reflection sits against the cool matte calibration field.",
        "message_or_content_role" => "Seed agency as an observable causal change.",
        "reference_contributions" => [ref_01, ref_02, ref_03],
        "transition_in" => "Begin on the unchanged offset marker.",
        "transition_out" => "Carry the registered position into the overhead proof.",
        "continuity_guard" => "Marker position, hand direction, and guide state must match across both planning cuts."
      }],
      "planning_cut_readouts" => [
        alignment_cut("PC_S01_CONTACT", "KS_S01_CONTACT", 1, false, [ref_01, ref_02]),
        alignment_cut("PC_S01_OVERHEAD", "KS_S01_OVERHEAD", 2, true, [ref_02, ref_03])
      ],
      "review_board_projection" => "whole_video_then_every_section_then_every_planning_cut_alongside_visual_cards",
      "visual_read_mismatch_action" => "reinspect_exact_bound_images_with_founder_revise_smallest_alignment_owner_and_reproject_affected_descendants",
      "downstream_lineage_rule" => "01_and_02A_exact_copy_alignment_pointers_and_value_hashes_02B_reads_bound_cut_alignment_before_prompt_authorship"
    }
  end

  def pre00_storyline_lineage
    text = "The film opens inside a calibration field that appears fixed, but M01 notices that its guide rejects her own pace. She makes one deliberate adjustment and the field records it instead of resetting. The same changed marker becomes evidence for the next state, so the video advances through accumulating consequences rather than repeated declarations. At the turn, the system reveals that it can follow an already-made choice, though it still resists. The ending returns to the first guide with the marker permanently offset as the quiet afterimage of agency."
    text_sha = Digest::SHA256.hexdigest(text)
    {
      "contract_version" => "pre00_storyline_lineage.v1",
      "pre00_storyline_original" => {
        "version_id" => "PRE00_STORYLINE_V001",
        "parent_version_id" => nil,
        "parent_full_storyline_text_sha256" => nil,
        "full_storyline_text" => text,
        "full_storyline_text_sha256" => text_sha,
        "selected_route_ids" => ["ROUTE_ACTIVE_01"],
        "reference_bindings" => [
          {
            "source_ref_id" => "REF_MEDIA_NARRATIVE_ACTIVE",
            "source_json_pointer" => "/research_inputs/REF_MEDIA_NARRATIVE_ACTIVE",
            "source_value_sha256" => "a" * 64,
            "source_snapshot" => {"title" => "Fixture narrative reference"},
            "selected_locator" => "One bounded action-and-consequence passage.",
            "storyline_function" => "Keeps the member action causally connected to a persistent world response.",
            "transfer_boundary" => "Function only; no source identity or source world transfer.",
            "do_not_transfer" => ["source character", "source world"],
            "affected_story_scope" => "opening through ending afterimage",
            "disposition" => "applied_to_storyline",
            "direct_visual_use_authorized" => false
          }
        ],
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
        "opening_to_ending_flow_review" => "The initial constraint, deliberate action, accumulating consequence, turn, and afterimage form one flow.",
        "causal_or_associative_continuity_review" => "The changed marker persists as the continuity carrier.",
        "state_and_turn_specificity_review" => "The fixed, adjusted, following, resisting, and retained states are distinguishable.",
        "reference_influence_review" => "The reference contributes one bounded causal function with exclusions.",
        "ending_afterimage_review" => "The permanently offset marker records the change.",
        "execution_detail_deferral_review" => "No timecode, camera, Core/Branch Cut, or prompt truth is authored."
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

  def front_planning_storyline_lineage(pre00_lineage)
    original = pre00_lineage.fetch("pre00_storyline_original")
    expanded_text = "#{original.fetch('full_storyline_text')} Front Planning plants MJ01 as the governing calibration-field event, marks the action Core and adds the retained-guide Core as the consequence still of that same event."
    expanded_sha = Digest::SHA256.hexdigest(expanded_text)
    expansion = {
      "version_id" => "FP_STORYLINE_V001",
      "parent_version_id" => original.fetch("version_id"),
      "parent_full_storyline_text_sha256" => original.fetch("full_storyline_text_sha256"),
      "full_storyline_text" => expanded_text,
      "full_storyline_text_sha256" => expanded_sha,
      "change_trigger" => "selected_song_lock",
      "change_reason" => "Expand the PRE-00 original into the working film by planting the MJ01 event and marking plus adding its Cores.",
      "changed_story_passages" => ["Plant MJ01 and name the action Core plus the added consequence Core."],
      "preserved_pre00_invariants" => ["Opening constraint, deliberate action, accumulating consequence, turn, and retained afterimage remain intact."],
      "applied_reference_receipts" => [],
      "authorship_receipt" => {
        "authored_by" => "creative_development_director",
        "authored_at" => "2026-08-14T00:00:00Z",
        "founder_status" => "selected",
        "full_text_revision_not_patch_only" => true
      }
    }
    {
      "contract_version" => "front_planning_storyline_lineage.v1",
      "source_pre00_handoff_schema_version" => "idol-pre00-selection-handoff.v3",
      "source_pre00_handoff_json_pointer" => "/storyline_lineage/value",
      "source_pre00_lineage_value_sha256" => value_sha(pre00_lineage),
      "pre00_lineage" => pre00_lineage,
      "front_planning_revisions" => [expansion],
      "active_version" => {
        "lineage_scope" => "front_planning",
        "version_id" => expansion.fetch("version_id"),
        "version_json_pointer" => "/storyline_lineage/front_planning_revisions/0",
        "full_storyline_text" => expansion.fetch("full_storyline_text"),
        "full_storyline_text_sha256" => expansion.fetch("full_storyline_text_sha256")
      },
      "contextual_density_review" => {
        "method" => "overall_director_contextual_review_no_machine_similarity_or_numeric_density_score",
        "reviewed_version_id" => expansion.fetch("version_id"),
        "reviewed_full_storyline_text_sha256" => expansion.fetch("full_storyline_text_sha256"),
        "decision" => "pass",
        "whole_film_flow_review" => "The expanded full text remains coherent from the opening condition to the ending trace and plants MJ01.",
        "reference_change_review" => "FP expansion preserves PRE-00 reference function while adding the governing event.",
        "original_invariant_review" => "The PRE-00 original remains present byte-for-byte inside the projected lineage.",
        "execution_layer_separation_review" => "Section, camera, Core/Branch, and prompt detail remains in its owning layer."
      },
      "preservation_contract" => {
        "pre00_original_rule" => "exact_project_and_preserve_the_complete_pre00_original_and_all_pre00_revisions",
        "revision_rule" => "front_planning_changes_append_full_text_versions_with_parent_hash_reason_passages_invariants_and_reference_receipts",
        "active_text_rule" => "active_version_must_resolve_to_one_preserved_full_text_version_and_match_its_raw_text_sha256",
        "summary_rule" => "whole_film_spine_and_alignment_readouts_expand_and_index_the_storyline_but_never_replace_it",
        "downstream_rule" => "01_02a_02b_03v_and_04_exact_project_this_complete_lineage"
      }
    }
  end

  def front_document(pre00_handoff:, pre00_lineage:, song:, sequence_control:, member:, sequence:, scene:, support:, pins:, analysis:, manifest:, reference_index:)
    {
      "schema_version" => "front-planning-readiness.v15",
      "content_id" => "ACTIVE_TITLE_TEST",
      "status" => "director_closed",
      "source_pre00_handoff" => {"path" => relative(pre00_handoff), "sha256" => file_sha(pre00_handoff)},
      "storyline_lineage" => front_planning_storyline_lineage(pre00_lineage),
      "selected_song_lock" => artifact_ref(song),
      "founder_sequence_control" => {
        "path" => relative(sequence_control),
        "sha256" => file_sha(sequence_control),
        "schema_version" => "idol_founder_sequence_control.v2",
        "lane" => "idol_mv",
        "status" => "director_ready",
        "startup_decision" => "start_authorized",
        "projection_authorized" => true
      },
      "founder_brief" => {
        "verbatim_direction" => "Connect the references into a complete film with minimal Founder intervention.",
        "selected_main_reference_ids" => ["REF-01"],
        "selected_supporting_reference_ids" => ["REF-02", "REF-03"],
        "explicit_locks" => ["Use only the current title visual package for member appearance."],
        "director_questions" => ["How should the object consequence make the message legible?"]
      },
      "target_message_lock" => {
        "primary_target" => "Listeners who reward precise visual storytelling.",
        "audience_promise" => "A readable transformation instead of disconnected portraits.",
        "core_message" => "Agency becomes visible through a changed relation to the system.",
        "desired_response" => "Rewatch the section to follow its causal chain.",
        "content_pillars" => ["member agency", "world reaction"],
        "familiar_codes_to_keep" => ["idol presence"],
        "novelty_or_tension_to_add" => ["the world visibly answers the member"],
        "observable_screen_consequences" => ["the object route changes after the member acts"],
        "do_not_serve" => ["generic portrait montage"]
      },
      "audience_research" => {
        "selected_song_listener_first" => true,
        "anchors" => [
          audience_anchor("AUD-SONG", "selected song", song),
          audience_anchor("AUD-REF", "main reference", sequence)
        ],
        "connections" => [
          target_connection("CON-01", "actual_audience_overlap", "selected_primary"),
          target_connection("CON-02", "shared_reward_adjacency", "selected_supporting")
        ],
        "selection_reason" => "Both sides reward legible transformation; surface resemblance alone was rejected."
      },
      "current_title_visual_identity" => {
        "album_key" => album_key,
        "title_key" => title_key,
        "asset_root" => "assets/members/album-assets/#{album_key}/#{title_key}",
        "asset_manifest" => artifact_ref(manifest),
        "cross_title_rule" => "hold_any_asset_outside_current_album_and_title_unless_founder_selected_that_exact_pixel_as_a_direct_scene_reference",
        "member_visual_rule" => "controls_appearance_hair_makeup_wardrobe_material_silhouette_and_body_continuity_never_forces_face_frontal_gaze_pose_camera_crop_or_proportions",
        "member_visual_creation_rule" => "front_planning_binds_passed_current_title_member_visuals_without_repeat_review_and_routes_only_new_or_fully_restyled_candidates_to_founder_exception_selection",
        "separate_background_asset_generation" => false,
        "assets" => [
          visual_asset("VIS-M01", "member_visual_anchor", ["M01"], member)
        ]
      },
      "major_visual_key_screen_workflow" => {
        "workflow_order" => [
          "founder_supplies_minimum_start_input_or_requests_first_proposal",
          "assigned_director_authors_one_recommended_sequence_major_scene_and_reference_use_plan",
          "assigned_director_binds_passed_member_visuals_and_routes_only_new_or_restyled_candidates_to_exception_review",
          "assigned_director_authors_and_quality_checks_key_screen_anchors",
          "founder_reviews_direction_alignment_for_message_major_video_form_sections_and_reference_direction",
          "director_closes_front_planning_internally_and_preserves_storyline_for_02a_final_planning"
        ],
        "founder_major_authority" => "assigned_director_proposes_whole_video_order_and_major_scenes_from_the_founder_seed_and_the_founder_may_correct_or_lock_them_at_direction_alignment",
        "major_visual_review_rule" => "passed_current_title_member_visuals_bind_without_repeat_review_while_new_or_fully_restyled_candidates_require_founder_exception_selection",
        "key_screen_authority" => "the_creative_development_director_authors_and_quality_checks_all_key_screen_anchors_overall_director_inspects_and_promotes_unless_a_founder_direct_update_replaces_named_fields",
        "key_screen_founder_gate" => "no_separate_founder_key_screen_gate_key_screens_enter_internal_fp_close_and_02a_final_planning",
        "current_title_visual_lifecycle" => "passed_current_title_member_visuals_are_reused_inside_the_title_new_or_restyled_candidates_require_exception_selection_and_no_separate_background_or_world_asset_package_is_created",
        "stage_route_preservation" => "direction_alignment_then_internal_fp_close_then_same_epoch_01_and_02a_no_new_stage"
      },
      "reference_connection_research" => {
        "substage_owner" => "01R_inside_front_planning_with_optional_01R_C_frame_crop_lock",
        "discovery_mode" => "founder_main_origin_first",
        "reference_working_index" => artifact_ref(reference_index),
        "source_lineages" => [
          {
            "lineage_id" => "LINEAGE-01",
            "main_reference_id" => "REF-01",
            "source_or_origin_reference_ids" => ["ORIGIN-A"],
            "derivative_reference_ids" => ["DERIVATIVE-B"],
            "connection_reason" => "The derivative exposes a usable object-response grammar.",
            "evidence" => [artifact_ref(sequence)],
            "director_proposal" => "Assign the ordered action grammar to S01 while retaining current-title appearance."
          }
        ],
        "reference_units" => [
          reference_unit("REF-01", "SOURCE-A", "sequence_sheet", "ordered action", sequence, analysis, true),
          reference_unit("REF-02", "SOURCE-B", "scene_crop", "subject placement", scene, analysis, false),
          reference_unit("REF-03", "SOURCE-A", "supporting_visual_reference", "object consequence", support, analysis, false)
        ] + pins.each_with_index.map { |entry, index| pinterest_reference_unit(index + 1, entry, analysis) },
        "section_comparison_floor" => "at_least_three_reviewable_units_from_two_source_identities_and_two_directorial_functions_per_active_visual_section",
        "section_sequence_bundle_floor" => "at_least_one_applied_or_combined_five_frame_contiguous_sequence_bundle_at_one_or_three_second_cadence_per_active_visual_section",
        "interpretation_reuse_rule" => "reuse_hash_bound_interpretation_until_bytes_meaning_lock_completeness_identity_safety_feasibility_or_explicit_founder_rereview_changes"
      },
      "founder_visual_alignment" => founder_visual_alignment_document,
      "whole_film_spine" => {
        "opening_state" => "The system appears to determine the member's route.",
        "progression" => "The member tests one visible rule.",
        "turn" => "The world begins responding to her choice.",
        "resolution_or_afterimage" => "The system keeps the trace of her action.",
        "message_progression" => "Seed agency, complicate its cost, then leave an observable consequence.",
        "section_flow_summary" => ["S01: the first rule changes after a deliberate action."],
        "recurrence_rule" => "Repeat the object only when its state advances."
      },
      "section_plan" => [
        {
          "section_id" => "S01",
          "time_range" => "00:00.000-00:12.000",
          "primary_audio_cue" => "The first percussive break.",
          "section_story_function" => "Show the first causal break in the system.",
          "message_role" => "seed",
          "assigned_member_ids" => ["M01"],
          "screen_carrier" => "mixed_member_world",
          "member_visual_asset_ids" => ["VIS-M01"],
          "sequence_reference_unit_ids" => ["REF-01"],
          "scene_reference_unit_ids" => ["REF-02", "REF-03"],
          "major_scene_flow" => [
            {
              "scene_id" => "S01-SC01",
              "major_direction" => {
                "authoring_owner" => "assigned_director_proposal",
                "source_control_major_id" => "FSC_MAJOR_01",
                "direction" => "The member deliberately breaks one visible system rule and the world records the consequence.",
                "major_scene_boundaries" => ["Keep one governing alignment event; do not turn it into a portrait montage."]
              },
              "scene_job" => "Establish the system rule and its first visible exception.",
              "space" => "A neutral synthetic calibration field.",
              "visible_subject" => "M01 from behind, with her face unreadable.",
              "visible_action_or_hold" => "She aligns one calibration marker with the printed test guide.",
              "object_or_environment_state" => "The marker changes from the offset sample position to the registered position.",
              "how_it_is_shown" => "Preserve the synthetic chart's lateral placement and flat depth layers.",
              "reference_unit_ids" => ["REF-01", "REF-02"],
              "continuity_result" => "The registered marker remains visible in the next calibration view.",
              "major_visual_evidence" => [
                {
                  "evidence_id" => "MVE_S01_MEMBER_BG",
                  "evidence_kind" => "major_scene_member_visual_test",
                  "artifact" => artifact_ref(member),
                  "visual_job" => "Confirm the current-title member visual in the same Major review unit.",
                  "reference_unit_ids" => ["REF-01", "REF-02"],
                  "current_title_asset_ids" => ["VIS-M01"],
                  "status" => "passed"
                }
              ],
              "director_major_quality_review" => {
                "decision" => "pass",
                "reviewed_ids" => ["MVE_S01_MEMBER_BG"],
                "note" => "The assigned director passed the complete Major evidence."
              },
              "founder_exception_gate" => {
                "required" => true,
                "reason" => "new_or_fully_restyled_current_title_member_visual",
                "decision" => "pass",
                "reviewed_ids" => ["MVE_S01_MEMBER_BG"],
                "note" => "Founder selected the new current-title member visual candidate."
              },
              "key_screen_coverage_reason" => "Two anchors are needed to separate member agency from the system's spatial proof without repeating a face-led composition.",
              "uncovered_key_screen_jobs" => [],
              "key_screen_anchors" => [
                key_screen_anchor(
                  id: "KS_S01_CONTACT",
                  visible_members: ["M01"],
                  member_assets: ["VIS-M01"],
                  camera: {
                    "shot_scale_distance" => "medium-wide at four meters",
                    "camera_height" => "waist height",
                    "direction_angle" => "lateral rear three-quarter view",
                    "depth" => "foreground scale marks, member plane, flat test backdrop",
                    "subject_placement" => "member on the left third with the guide unobstructed",
                    "crop_negative_space" => "open right side for the marker route"
                  },
                  bindings: [
                    key_screen_function_binding("REF-01", "RFN_REF_01_ACTION", "visible_action_or_hold", "pose_action_support"),
                    key_screen_function_binding("REF-02", "RFN_REF_02_CAMERA", "still_camera_and_composition", "camera_composition_support")
                  ],
                  contribution: "Makes the member's measured hand contact and agency readable."
                ),
                key_screen_anchor(
                  id: "KS_S01_OVERHEAD",
                  visible_members: [],
                  member_assets: [],
                  camera: {
                    "shot_scale_distance" => "top-down medium insert at two meters",
                    "camera_height" => "two meters above the guide",
                    "direction_angle" => "orthographic overhead",
                    "depth" => "marker on the guide plane with luminous response lines beneath it",
                    "subject_placement" => "marker centered with the full guide radius visible",
                    "crop_negative_space" => "even margin around the outer response ring"
                  },
                  bindings: [
                    key_screen_function_binding("REF-02", "RFN_REF_02_CAMERA", "still_camera_and_composition", "camera_composition_support"),
                    key_screen_function_binding("REF-03", "RFN_REF_03_OBJECT", "object_environment_response", "object_environment_support")
                  ],
                  contribution: "Reveals the registration geometry and the environment's response without another member portrait."
                )
              ],
              "director_key_screen_quality_review" => {
                "decision" => "pass",
                "reviewed_ids" => ["KS_S01_CONTACT", "KS_S01_OVERHEAD"],
                "note" => "The assigned director passed both Key Screen anchors."
              }
            }
          ],
          "choreography_presence_policy" => "absent",
          "choreography_reference_unit_ids" => [],
          "transition_in" => "Open on the unchanged system rhythm.",
          "transition_out" => "Carry the registered marker state beyond the section.",
          "downstream_01_questions" => ["Which still view best preserves the reference depth?"],
          "status" => "director_passed"
        }
      ],
      "downstream_contract" => {
        "next_stage" => "01_section_direction",
        "absorbed_capabilities" => ["creative_core_lock", "current_title_visual_identity_lock", "generation_coverage_planning"],
        "01_consumption_rule" => "consume_bound_target_message_visual_package_section_member_scene_reference_interpretations_and_founder_visual_alignment_without_reselection",
        "01_visual_projection_rule" => "01_contains_the_reviewable_visual_projection_without_a_separate_01A_artifact",
        "02A_rule" => "02A_absorbs_internal_generation_coverage_and_authors_core_event_cuts_with_1_to_n_distinct_branch_cut_children",
        "02B_rule" => "translate_each_passed_02A_branch_cut_and_its_exact_founder_visual_alignment_lineage_into_the_fixed_five_line_prompt_with_smallest_current_title_visual_subset",
        "founder_visual_alignment_rule" => "whole_video_then_section_then_planning_cut_detail_increases_across_discovery_direction_alignment_and_fp_close_and_is_value_hash_preserved_through_01_02A_02B",
        "local_revision_rule" => "change_the_smallest_owning_field_or_section_and_reproject_only_affected_dependents",
        "temporal_camera_owner" => "03V_after_passed_image_pixel_inspection"
      },
      "founder_gate" => {
        "decision" => "pass",
        "reviewed_scope" => "whole_video",
        "review_note" => "Active fixture pass."
      },
      "review_surface" => {
        "html_contract_version" => "idol-html-review-board.v12",
        "hierarchy" => "target_and_message_then_whole_video_and_section_flow_then_sections_then_core_cuts_then_branch_cuts",
        "front_planning_review_mode" => "founder_direction_alignment_then_internal_fp_close_and_one_02A_final_planning_gate_with_exception_only_interrupts",
        "founder_visual_alignment_projection" => "show_exact_whole_video_section_and_planning_cut_readouts_beside_their_visual_review_cards",
        "mismatch_reconciliation" => "founder_visual_read_mismatch_reopens_exact_bound_pixels_and_smallest_storyline_owner_before_affected_reprojection",
        "decision_values" => ["PASS", "HOLD", "REJECT"]
      },
      "open_questions" => []
    }
  end

  def upgrade_front_document!(document, pre00_handoff:, sequence:, scene:, support:, pins:)
    document["schema_version"] = "front-planning-readiness.v17"
    document["creative_review_graph"] = {
      "local" => {
        "present" => true,
        "owner_role" => "creative_development_director",
        "scope" => "single-major local review"
      },
      "pairwise" => {
        "present" => true,
        "owner_role" => "creative_development_director",
        "scope" => "adjacent-major pairwise review"
      },
      "global" => {
        "present" => true,
        "owner_role" => "overall_director",
        "scope" => "whole-film global review"
      }
    }
    document.dig("storyline_lineage")["source_pre00_handoff_schema_version"] = "idol-pre00-selection-handoff.v4"
    handoff = YAML.safe_load(Pathname.new(pre00_handoff).read, aliases: true)
    document["pre00_audience_target_lineage"] = %w[audience_profiles x_reference_audience_envelope title_target_intersection].to_h do |field|
      [field, handoff.fetch(field)]
    end
    document.dig("founder_sequence_control")["schema_version"] = "idol_founder_sequence_control.v3"
    document.dig("founder_brief")["selected_supporting_reference_ids"] = %w[REF-02 REF-03 REF-X REF-Y REF-Z]

    research = document.fetch("reference_connection_research")
    research.fetch("reference_units").each do |unit|
      unit.delete("sequence_bundle")
      unit["sequence_unit"] = nil unless unit["reference_unit_id"] == "REF-01"
    end
    sequence_reference = research.fetch("reference_units").find { |row| row["reference_unit_id"] == "REF-01" }
    legacy = {
      "continuous_event" => "The figure registers one marker and the aligned state remains visible.",
      "frames" => @sequence_bundle_frames.each_with_index.map do |frame, index|
        {"order_index" => index + 1, "source_timestamp_seconds" => index, "source_frame_or_cell_id" => format("CELL-%02d", index + 1), "artifact" => artifact_ref(frame)}
      end,
      "manifest" => artifact_ref(@sequence_bundle_manifest)
    }
    sequence_unit = {
      "sequence_unit_id" => "SEQU_REF_01",
      "sequence_run_id" => "SRUN_MJ01",
      "event_identity" => legacy.fetch("continuous_event"),
      "frame_selection_mode" => "fixed_cadence",
      "declared_cadence_seconds" => 1,
      "ordered_frames" => legacy.fetch("frames").map do |frame|
        {
          "order_index" => frame.fetch("order_index"),
          "timestamp_seconds" => frame.fetch("source_timestamp_seconds"),
          "source_frame_or_cell_id" => frame.fetch("source_frame_or_cell_id"),
          "artifact" => frame.fetch("artifact")
        }
      end,
      "flow_reading" => {
        "entry_state" => "The marker begins offset from the printed guide.",
        "trigger" => "The figure begins one measured registration action.",
        "visible_transformation" => "The hand and marker traverse the guide in ordered one-second states.",
        "peak_or_reveal" => "The marker reaches registration and the guide response becomes visible.",
        "exit_state" => "The registered relation holds after contact.",
        "camera_composition_depth_progression" => "The fixed lateral view preserves foreground marks, subject plane, and guide plane while the object relation changes.",
        "continuity_to_next" => "The final registered marker state carries into the next Core Slot.",
        "direct_observation_vs_inference" => "Frame states and marker travel are direct observations; agency is the bounded storyline inference.",
        "storyline_transfer_and_exclusion" => "Transfer the ordered action-to-consequence grammar, excluding source identity and unselected world details.",
        "authorship_owner" => "assigned_model"
      },
      "frame_observations" => legacy.fetch("frames").map do |frame|
        order = frame.fetch("order_index")
        {
          "order_index" => order,
          "timestamp_seconds" => frame.fetch("source_timestamp_seconds"),
          "subject_body_object_space" => "The hand, marker, and guide occupy a fixed lateral calibration field at state #{order}.",
          "delta_from_previous" => order == 1 ? "Initial offset state establishes the comparison." : "The marker advances one observable step toward or into registration.",
          "camera_composition_depth" => "Fixed waist-height lateral depth keeps the marker relation readable.",
          "storyline_function" => order < 5 ? "Build the deliberate action." : "Hold the visible consequence.",
          "uncertainty" => "No material uncertainty in the selected fixture frame."
        }
      end,
      "manifest" => legacy.fetch("manifest"),
      "major_reference_eligible" => true,
      "downstream_cut_count_rule" => "five_source_frames_never_imply_five_core_or_branch_cuts"
    }
    sequence_reference["sequence_unit"] = sequence_unit
    sequence_reference["selected_locator"] = "SEQU_REF_01 exact five frames at 00:00-00:04"
    comparison_reference = Marshal.load(Marshal.dump(sequence_reference))
    comparison_reference["reference_unit_id"] = "REF-04"
    comparison_reference["reference_working_index_row_id"] = "RWI-REF-04"
    comparison_reference["selected_locator"] = "SEQU_REF_04 exact five frames at 00:00-00:04"
    comparison_reference.fetch("function_analysis").each do |function|
      function["function_id"] = function.fetch("function_id").sub("RFN_REF_01_", "RFN_REF_04_")
    end
    comparison_reference.fetch("sequence_unit")["sequence_unit_id"] = "SEQU_REF_04"
    research.fetch("reference_units") << comparison_reference
    reference_index_path = ROOT.join(research.fetch("reference_working_index").fetch("path"))
    reference_index_document = YAML.safe_load(reference_index_path.read, aliases: true)
    reference_index_rows = reference_index_document.fetch("rows")
    research.fetch("reference_units").each do |unit|
      row_index = reference_index_rows.index do |row|
        row.fetch("row_id") == unit.fetch("reference_working_index_row_id")
      end
      index_row = reference_index_rows.fetch(row_index)
      function = unit.fetch("function_analysis").first
      target_sections = unit.fetch("target_section_ids").join(", ")
      unit["connection_quality_proof"] = {
        "reference_working_index_json_pointer" => "/rows/#{row_index}",
        "reference_working_index_row_value_sha256" => value_sha(index_row),
        "named_section_need" => "#{target_sections} requires #{unit.fetch('screen_function')} for its named screen job.",
        "observed_source_evidence" => "#{unit.fetch('observed_space')} #{unit.fetch('observed_action_or_hold')}",
        "bounded_transfer" => function.fetch("transfer_boundary"),
        "observable_screen_consequence" => "The #{unit.fetch('screen_function')} remains visible in the targeted screen.",
        "exact_section_placement" => "Place #{unit.fetch('reference_unit_id')} only in #{target_sections} through its named reference bindings.",
        "existing_screen_role" => unit.fetch("screen_function"),
        "nearest_alternative_comparison" => "The nearest fixture alternative does not replace this unit's named #{unit.fetch('screen_function')} role.",
        "non_duplication_case" => "Retain this unit only for its named function; other reference functions remain separately owned.",
        "mismatch_case" => "Hold or reject this unit if the bound pixels no longer show the stated evidence or placement.",
        "removal_loss" => "Removing this unit loses the named #{unit.fetch('screen_function')} evidence in #{target_sections}."
      }
    end
    alignment = document.fetch("founder_visual_alignment")
    [alignment.fetch("whole_film_readout").fetch("reference_combination_logic"), *alignment.fetch("section_readouts").map { |row| row.fetch("reference_contributions") }, *alignment.fetch("planning_cut_readouts").map { |row| row.fetch("reference_contributions") }].flatten.each do |contribution|
      contribution["selected_locator"] = sequence_reference.fetch("selected_locator") if contribution["reference_unit_id"] == "REF-01"
    end
    research["sequence_runs"] = [{
      "sequence_run_id" => "SRUN_MJ01",
      "ordered_sequence_unit_ids" => ["SEQU_REF_01", "SEQU_REF_04"],
      "major_scene_bindings" => ["MJ01"],
      "boundary_frame_policy" => "linked_units_do_not_duplicate_boundary_frames"
    }]
    research["section_comparison_floor"] = "decision_ready_actual_visual_units_for_each_material_major_and_core_slot_without_a_fixed_discovery_quota"
    research.delete("section_sequence_bundle_floor")
    research["section_sequence_unit_floor"] = "at_least_one_applied_or_combined_exact_five_sequence_unit_at_exact_one_second_cadence_per_active_visual_section"

    section = document.fetch("section_plan").first
    section["sequence_unit_ids"] = ["SEQU_REF_01"]
    section.delete("sequence_reference_unit_ids")
    major = section.fetch("major_scene_flow").first
    major["major_scene_id"] = "MJ01"
    major.delete("scene_id")
    major.dig("major_direction")["source_control_major_id"] = "MJ01"

    active_story = document.dig("storyline_lineage", "active_version")
    storyline_text = active_story.fetch("full_storyline_text")
    storyline_sha = Digest::SHA256.hexdigest(storyline_text)
    composition_candidates = [1, 2].map do |index|
      {
        "sequence_composition_id" => "SCOMP_MJ01_0#{index}",
        "typed_sequence_unit_ids" => [index == 1 ? "SEQU_REF_01" : "SEQU_REF_04"],
        "flow_reading" => index == 1 ? "The selected composition carries offset, action, registration, and hold in one causal flow." : "The held alternative emphasizes the same event's spatial proof without changing its order.",
        "mismatch_and_risk" => index == 1 ? "The fixed view must still preserve member agency." : "The alternate may overemphasize the object response.",
        "disposition" => index == 1 ? "selected" : "held",
        "disposition_reason" => index == 1 ? "Best preserves cause and consequence." : "Useful comparison but weaker member causality."
      }
    end
    document["major_scene_catalog"] = [{
      "major_scene_id" => "MJ01",
      "section_id" => "S01",
      "semantic_event_or_relation_job" => "Make one deliberate member action produce a retained system consequence.",
      "material" => true,
      "sequence_composition_candidate_set" => {
        "candidate_set_id" => "SCSET_MJ01",
        "candidates" => composition_candidates,
        "selected_sequence_composition_id" => "SCOMP_MJ01_01"
      }
    }]
    route_section = {
      "section_id" => "S01",
      "major_scene_stack" => {
        "ordered_major_placements" => [{
          "major_scene_id" => "MJ01",
          "order_within_section" => 1,
          "sequence_composition_candidate_set_id" => "SCSET_MJ01",
          "selected_sequence_composition_id" => "SCOMP_MJ01_01",
          "rhythm_and_information_job" => "Carry the first percussive break from offset state through visible registration.",
          "transition_edges" => ["Enter from the fixed field and leave on the retained marker."]
        }],
        "single_major_hold_bridge_rationale" => "One governing event spans the section; its second Core Slot is a retained consequence, not a new Major.",
        "audio_story_information_progression" => "The percussion triggers action, then the release exposes its retained result."
      },
      "route_major_expansions" => [{
        "major_scene_id" => "MJ01",
        "section_id" => "S01",
        "scene_phases" => [
          {"phase_order" => 1, "phase_context" => "member action", "observable_change" => "The marker moves from offset toward registration."},
          {"phase_order" => 2, "phase_context" => "system consequence", "observable_change" => "The guide retains the registered relation after the hand leaves."}
        ],
        "sequence_run_ids" => ["SRUN_MJ01"],
        "core_cut_slots" => [
          {"core_slot_id" => "CS01", "section_id" => "S01", "major_scene_id" => "MJ01", "scene_phase_context" => "member action", "required_screen_information" => "M01 visibly causes the marker registration.", "material_status" => "material"},
          {"core_slot_id" => "CS02", "section_id" => "S01", "major_scene_id" => "MJ01", "scene_phase_context" => "system consequence", "required_screen_information" => "The guide visibly retains the changed registered state.", "material_status" => "material"}
        ],
        "hero_core_cut_candidate_ids" => ["HERO_CS01", "HERO_CS02"]
      }]
    }
    document["candidate_routes"] = %w[A B C].each_with_index.map do |letter, index|
      {
        "candidate_id" => "FP-#{letter}",
        "recommendation_rank" => index + 1,
        "viability_status" => "complete_viable",
        "material_difference" => ["Causal member-to-system progression.", "More restrained spatial proof while retaining causality.", "More graphic object emphasis while retaining member agency."][index],
        "complete_storyline_version" => {
          "version_id" => "FP_ROUTE_#{letter}_STORYLINE_V001",
          "parent_version_id" => active_story.fetch("version_id"),
          "parent_full_storyline_text_sha256" => storyline_sha,
          "full_storyline_text" => storyline_text,
          "full_storyline_text_sha256" => storyline_sha
        },
        "sections" => [Marshal.load(Marshal.dump(route_section))],
        "audience_message_emotion_consequence" => "The target reads agency through an observable action and persistent response.",
        "feasibility_and_risk" => "The full route is feasible with two Official Cores; restraint must not flatten the causal turn."
      }
    end

    candidate_sources = [[sequence, scene], [support, pins.first]]
    document["core_visual_candidate_sets"] = %w[CS01 CS02].each_with_index.map do |slot_id, slot_index|
      candidates = candidate_sources[slot_index].each_with_index.map do |entry, index|
        candidate_id = "CVC_#{slot_id}_0#{index + 1}"
        {
          "candidate_id" => candidate_id,
          "actual_path" => entry.fetch("path"),
          "sha256" => entry.fetch("sha256"),
          "pixel_inspection_status" => "inspected",
          "source_identity" => index.zero? ? "selected registered fixture reference" : "bounded comparison fixture reference",
          "selected_locator" => "exact selected still surface",
          "governing_functions" => [slot_index.zero? ? "member action and composition" : "system consequence and spatial proof"],
          "disposition" => index.zero? ? "selected" : "held",
          "disposition_reason" => index.zero? ? "Best exact reference for the Core Slot." : "Decision-ready alternative retained as evidence."
        }
      end
      {"candidate_set_id" => "CVCSET_#{slot_id}", "core_slot_id" => slot_id, "major_scene_id" => "MJ01", "candidates" => candidates, "selected_candidate_id" => "CVC_#{slot_id}_01"}
    end
    document["core_reference_bindings"] = document["core_visual_candidate_sets"].map do |set|
      selected = set.fetch("candidates").first
      {
        "core_slot_id" => set.fetch("core_slot_id"),
        "major_scene_id" => "MJ01",
        "decision" => {
          "kind" => "selected_exact_reference",
          "selected_reference_candidate_id" => selected.fetch("candidate_id"),
          "actual_path" => selected.fetch("actual_path"),
          "sha256" => selected.fetch("sha256"),
          "pixel_inspection_status" => "inspected",
          "governing_functions" => selected.fetch("governing_functions"),
          "source_to_screen_delta" => "Transfer only the selected function into current-title identity and calibration-world continuity."
        }
      }
    end
    document["reference_coverage_complete"] = true
    document["hero_core_cut_candidates"] = %w[CS01 CS02].each_with_index.map do |slot_id, index|
      {"hero_core_id" => "HERO_#{slot_id}", "core_slot_id" => slot_id, "coverage_role" => index.zero? ? "representative" : "risk", "actual_output" => artifact_ref(@hero_core_images[index]), "pixel_review_status" => "pass", "adoption_status" => "selected_for_01"}
    end
    document["hero_generation_coverage"] = {"required_roles" => %w[representative risk], "covered_roles" => %w[representative risk], "complete" => true, "review_note" => "Actual fixture outputs cover the representative action and the system-response risk."}
    nodes = %w[CS01 CS02].each_with_index.map do |slot_id, index|
      {"node_id" => "SPN_#{slot_id}", "node_type" => "core_slot", "section_id" => "S01", "major_scene_id" => "MJ01", "source_id" => slot_id, "storyline_role" => index.zero? ? "seed the deliberate action" : "retain the visible consequence", "observable_screen_proof" => index.zero? ? "M01 moves the marker into registration." : "The guide remains registered after M01 leaves.", "continuity_in" => index.zero? ? "The marker begins offset." : "Use the exact registered marker position from CS01.", "continuity_out" => index.zero? ? "Carry the completed marker position." : "Leave the registered state as afterimage."}
    end
    document["screen_progression_map"] = {"screen_progression_map_id" => "SPM_ACTIVE_01", "active_storyline_version_id" => active_story.fetch("version_id"), "active_storyline_sha256" => storyline_sha, "nodes" => nodes, "ordered_edges" => [{"from_node_id" => "SPN_CS01", "to_node_id" => "SPN_CS02", "continuity_reason" => "The registered marker position is the exact causal carrier."}], "downstream_projection_rule" => "exact_carry_to_01_02A_02B_03V_and_04_never_substitute_for_full_text_storyline"}
    node_ids = nodes.map { |row| row.fetch("node_id") }
    document["production_scopes"] = [{"production_scope_id" => "PSCOPE_FULL_MV", "route_type" => "full_mv", "selected_node_ids" => node_ids, "unopened_full_mv_node_ids" => [], "state" => "approved_for_01"}]
    document["creative_experiment"] = {
      "experiment_id" => "EXP_ACTIVE_01", "source_direction_head" => {"path" => relative(pre00_handoff), "sha256" => file_sha(pre00_handoff)}, "candidate_route_id" => "FP-A",
      "selected_route_storyline_binding" => {
        "candidate_route_id" => "FP-A",
        "candidate_route_storyline_json_pointer" => "/candidate_routes/0/complete_storyline_version",
        "candidate_route_storyline_value_sha256" => value_sha(document.dig("candidate_routes", 0, "complete_storyline_version")),
        "active_storyline_relation" => "exact_selected_route_text",
        "promoted_storyline_revision_json_pointer" => nil,
        "promoted_storyline_revision_value_sha256" => nil,
        "active_storyline_version_id" => active_story.fetch("version_id"),
        "active_storyline_full_storyline_text_sha256" => active_story.fetch("full_storyline_text_sha256")
      },
      "sequence_candidate_set_ids" => ["SCSET_MJ01"], "selected_sequence_composition_ids" => ["SCOMP_MJ01_01"], "core_visual_candidate_set_ids" => %w[CVCSET_CS01 CVCSET_CS02], "generated_hero_core_ids" => %w[HERO_CS01 HERO_CS02],
      "director_recommendation" => "Advance FP-A because its two Core Slots preserve one causal Major without flattening the consequence.", "founder_decision" => {"disposition" => "full_mv_approved", "note" => "Fixture Founder decision authorizes the full-MV derivative for 01."},
      "derivative_routes" => [{"derivative_route_id" => "DERIV_FULL_MV", "route_type" => "full_mv", "production_scope_id" => "PSCOPE_FULL_MV", "selected_node_ids" => node_ids, "state" => "approved_for_01"}], "reuse_lineage" => "Reuse exact selected route, screen map, Core reference, and Hero output bytes downstream."
    }
    document.dig("downstream_contract")["02A_rule"] = "02A_imports_01_official_core_cuts_and_primary_images_immutably_and_authors_only_1_to_n_ordered_branch_cut_children_per_passed_core"
    document.dig("downstream_contract")["pre00_audience_target_lineage_rule"] = "01_02A_02B_03V_and_04_exact_carry_pre00_audience_profiles_x_envelope_and_title_target_intersection"
    document
  end

  def audience_anchor(id, identity, evidence)
    {
      "anchor_id" => id,
      "source_identity" => identity,
      "audience_attracted" => "Viewers seeking legible visual progression.",
      "promised_experience_or_identity" => "Careful viewers can read the change.",
      "literacy_and_codes" => ["ordered visual consequence"],
      "participation_behavior" => "Rewatch and compare scene states.",
      "content_expectations" => ["observable causality"],
      "rejection_triggers" => ["unmotivated portrait repetition"],
      "evidence" => [artifact_ref(evidence)],
      "freshness" => "current selected-title evidence"
    }
  end

  def target_connection(id, type, decision)
    {
      "connection_id" => id,
      "connection_type" => type,
      "source_anchor_ids" => ["AUD-SONG", "AUD-REF"],
      "target" => "Selected-song listeners who reward visual causality.",
      "response_mechanism" => "A visible action changes the world state.",
      "screen_translation" => "Show the before state, action, and consequence without explanatory text.",
      "evidence" => ["Both anchors reward readable transformation."],
      "counterevidence" => ["Aesthetic overlap alone does not prove shared behavior."],
      "decision" => decision
    }
  end

  def visual_asset(id, type, members, entry)
    {
      "asset_id" => id,
      "asset_type" => type,
      "member_ids" => members,
      "section_ids" => ["S01"],
      "path" => entry.fetch("path"),
      "sha256" => entry.fetch("sha256"),
      "status" => "authorized",
      "visual_control" => type == "member_visual_anchor" ? "M01 current-title appearance continuity." : "S01 world continuity.",
      "allowed_downstream_uses" => type == "member_visual_anchor" ?
        ["01_visual_projection", "02A_branch_cut_selection", "02B_member_visual_reference_input"] :
        ["01_visual_projection", "02A_branch_cut_selection", "02B_scene_reference_input"]
    }
  end

  def reference_unit(id, identity, kind, function, entry, analysis, sequence)
    purpose, function_id = case id
                           when "REF-01"
                             ["visible_action_or_hold", "RFN_REF_01_ACTION"]
                           when "REF-02"
                             ["still_camera_and_composition", "RFN_REF_02_CAMERA"]
                           else
                             ["object_environment_response", "RFN_REF_03_OBJECT"]
                           end
    {
      "reference_unit_id" => id,
      "reference_working_index_row_id" => "RWI-#{id}",
      "source_identity" => identity,
      "source_kind" => kind,
      "source_path" => entry.fetch("path"),
      "source_sha256" => entry.fetch("sha256"),
      "selected_locator" => sequence ? "SEQB_REF_01 frames 01-05" : "selected crop",
      "target_section_ids" => ["S01"],
      "direct_use_mode" => sequence ? "sequence_direct" : "bounded_surface_direct",
      "screen_function" => function,
      "observed_space" => "A synthetic layered calibration field.",
      "observed_subject" => "One fixture figure and one alignment marker.",
      "observed_action_or_hold" => "The figure registers the marker to the guide.",
      "observed_staging" => "Fixture figure left, marker centered on the test guide.",
      "observed_still_camera" => {
        "shot_scale_distance" => "medium-wide at four meters",
        "camera_height" => "waist height",
        "direction_angle" => "lateral three-quarter view",
        "depth" => "foreground scale marks, fixture plane, flat test backdrop",
        "subject_placement" => "left third",
        "crop_negative_space" => "open right side for the object route"
      },
      "ordered_sequence_grammar" => sequence ? ["marker begins offset", "marker reaches registration point", "registered state holds"] : ["single selected state"],
      "sequence_bundle" => sequence ? {
        "bundle_id" => "SEQB_REF_01",
        "source_duration_lane" => "short_at_or_below_60_seconds",
        "sampling_interval_seconds" => 1,
        "cadence_reason" => "one_second_short_source",
        "continuous_event" => "The figure registers one marker and the aligned state remains visible.",
        "source_event_range" => {
          "start_seconds" => 0,
          "end_seconds" => 4,
          "source_timecode_label" => "00:00.000-00:04.000"
        },
        "frame_count" => 5,
        "frames" => @sequence_bundle_frames.each_with_index.map do |frame, index|
          {
            "order_index" => index + 1,
            "source_timestamp_seconds" => index,
            "source_frame_or_cell_id" => format("CELL-%02d", index + 1),
            "artifact" => artifact_ref(frame),
            "observable_state_or_change" => format("Ordered registration state %02d of 05.", index + 1)
          }
        end,
        "manifest" => artifact_ref(@sequence_bundle_manifest),
        "reference_unit_count" => 1,
        "major_reference_eligible" => true,
        "continuity_rule" => "five_ordered_consecutive_samples_from_one_contiguous_event_at_the_declared_cadence"
      } : nil,
      "function_analysis" => [
        {
          "function_id" => function_id,
          "purpose" => purpose,
          "analysis_record" => artifact_ref(analysis),
          "analysis_locator" => "#{id} detailed scene record",
          "observed_fact" => "The selected source surface provides one concrete #{purpose.tr('_', ' ')} decision.",
          "selected_component" => function,
          "transfer_boundary" => "Carry only this named function into the current title member/world and preserve the source locator.",
          "do_not_transfer" => ["source performer identity", "unselected source scene content"],
          "downstream_targets" => ["major_visual_review", "front_planning_key_screen", "01_section_direction", "02A_branch_cut", "02B_prompt_translation"],
          "combination_rule" => "combine_only_the_named_selected_component_with_other_bound_functions_never_recreate_or_reinterpret_the_whole_reference"
        },
        *(id == "REF-01" ? [
          {
            "function_id" => "RFN_REF_01_WORLD",
            "purpose" => "background_and_space",
            "analysis_record" => artifact_ref(analysis),
            "analysis_locator" => "REF-01 selected sequence world/look observation",
            "observed_fact" => "The selected sequence preserves the layered calibration field and the visible guide relation.",
            "selected_component" => "synthetic layered calibration field and guide relation",
            "transfer_boundary" => "Carry only the field organization and guide relation, excluding source identity.",
            "do_not_transfer" => ["source performer identity", "unselected source styling"],
            "downstream_targets" => ["front_planning_key_screen", "01_section_direction", "02A_branch_cut", "02B_prompt_translation"],
            "combination_rule" => "combine_only_the_named_selected_component_with_other_bound_functions_never_recreate_or_reinterpret_the_whole_reference"
          },
          {
            "function_id" => "RFN_REF_01_CAMERA",
            "purpose" => "still_camera_and_composition",
            "analysis_record" => artifact_ref(analysis),
            "analysis_locator" => "REF-01 selected sequence still-camera observation",
            "observed_fact" => "The fixed lateral view keeps foreground marks, subject plane, guide plane, and action axis readable.",
            "selected_component" => "waist-height lateral layered composition",
            "transfer_boundary" => "Carry only still-camera geometry, subject placement, crop, and depth.",
            "do_not_transfer" => ["temporal camera movement", "source performer identity"],
            "downstream_targets" => ["front_planning_key_screen", "01_section_direction", "02A_branch_cut", "02B_prompt_translation"],
            "combination_rule" => "combine_only_the_named_selected_component_with_other_bound_functions_never_recreate_or_reinterpret_the_whole_reference"
          }
        ] : [])
      ],
      "preserve" => ["action and still-camera geometry"],
      "discard" => ["source performer identity"],
      "disposition" => "applied",
      "reason" => "It supplies a concrete screen function."
    }
  end

  def pinterest_reference_unit(number, entry, analysis)
    applied = number <= 3
    purpose = number.odd? ? "still_camera_and_composition" : "lighting_color_material"
    {
      "reference_unit_id" => format("PIN-%02d", number),
      "reference_working_index_row_id" => format("RWI-PIN-%02d", number),
      "source_identity" => format("PINTEREST-PIN-%02d", number),
      "source_kind" => number == 1 ? "main_reference" : "supporting_visual_reference",
      "source_path" => entry.fetch("path"),
      "source_sha256" => entry.fetch("sha256"),
      "selected_locator" => format("public pin %02d full readable still", number),
      "target_section_ids" => ["S01"],
      "direct_use_mode" => applied ? "bounded_surface_direct" : nil,
      "screen_function" => number.odd? ? "negative-space composition" : "cool material and side-light detail",
      "observed_space" => "A readable layered still with distinct foreground and negative space.",
      "observed_subject" => "One figure or object placed against the open section field.",
      "observed_action_or_hold" => "The subject holds a still state suitable for the named planning role.",
      "observed_staging" => "The subject stays off-center so the section action route remains open.",
      "observed_still_camera" => {
        "shot_scale_distance" => "medium-wide at four meters",
        "camera_height" => "waist height",
        "direction_angle" => "lateral three-quarter view",
        "depth" => "foreground edge, subject plane, open background",
        "subject_placement" => "left or right third according to the candidate",
        "crop_negative_space" => "full readable frame with intentional negative space"
      },
      "ordered_sequence_grammar" => ["single selected Pinterest still"],
      "sequence_bundle" => nil,
      "function_analysis" => [{
        "function_id" => format("RFN_PIN_%02d", number),
        "purpose" => purpose,
        "analysis_record" => artifact_ref(analysis),
        "analysis_locator" => format("PIN-%02d pixel observation", number),
        "observed_fact" => "The readable pixels provide a distinct composition or material contribution.",
        "selected_component" => purpose,
        "transfer_boundary" => "Transfer only the named still function, never identity.",
        "do_not_transfer" => ["source identity", "unselected styling"],
        "downstream_targets" => ["front_planning_key_screen", "01_section_direction", "02A_branch_cut"],
        "combination_rule" => "combine_only_the_named_selected_component_with_other_bound_functions_never_recreate_or_reinterpret_the_whole_reference"
      }],
      "preserve" => ["named composition or material function"],
      "discard" => ["source identity"],
      "disposition" => applied ? "applied" : "held",
      "reason" => format("PIN-%02d supports S01 Major/Key Screen composition without replacing the governing action reference.", number)
    }
  end

  def write_reference_index(sequence:, scene:, support:, pins:, analysis:, source_manifest:, worker_delta:, worker_dispatch:, cdd_review:, section_binding:)
    review_pointer = artifact_ref(cdd_review).merge("role" => "cdd_review")
    dispatch_pointer = artifact_ref(worker_dispatch).merge("role" => "department_dispatch")
    source_pointer = artifact_ref(source_manifest).merge("role" => "source_manifest")
    section_binding_pointer = artifact_ref(section_binding).merge("role" => "front_planning_section_binding")
    rows = [
      ["REF-01", "SOURCE-A", "visible_action_or_hold", sequence],
      ["REF-04", "SOURCE-A", "visible_action_or_hold", sequence],
      ["REF-02", "SOURCE-B", "still_camera_and_composition", scene],
      ["REF-03", "SOURCE-A", "object_environment_response", support]
    ].map do |unit_id, source_id, function, selected|
      {
        "row_id" => "RWI-#{unit_id}",
        "source_id" => source_id,
        "reference_unit_id" => unit_id,
        "source_manifest" => source_pointer,
        "analysis_manifest" => artifact_ref(analysis).merge("role" => "source_analysis"),
        "selected_evidence" => artifact_ref(selected).merge("role" => "selected_evidence"),
        "selected_locator" => "fixture selected surface",
        "function" => function,
        "disposition" => "applied",
        "source_eligibility" => {
          "classification" => "official_original_professional_primary",
          "public_pin_url_or_id" => nil,
          "origin_identity_verified" => true,
          "active_reuse_eligible" => true,
          "historical_row_reused_without_review" => false,
          "restricted_source_permission" => nil
        },
        "reference_connection_pointers" => [review_pointer.merge("role" => "reference_connection_review")],
        "section_bindings" => [{"section_id" => "S01", "binding_pointer" => section_binding_pointer}],
        "decision_epoch" => "1",
        "worker_attempt" => {
          "lineage_id" => "LINEAGE-REF",
          "attempt_id" => "ATTEMPT-REF",
          "dispatch_id" => "DISPATCH-REF",
          "provider" => "codex",
          "session_id" => "SESSION-REF",
          "dispatch_pointer" => dispatch_pointer
        },
        "cdd_review" => {
          "reviewer" => "creative_development_director",
          "reviewed_at" => "2026-08-04T00:00:00Z",
          "disposition" => "accepted",
          "review_pointer" => review_pointer
        },
        "downstream_consumers" => []
      }
    end
    rows.concat(pins.each_with_index.map do |selected, index|
      number = index + 1
      applied = index < 3
      {
        "row_id" => format("RWI-PIN-%02d", number),
        "source_id" => format("PINTEREST-PIN-%02d", number),
        "reference_unit_id" => format("PIN-%02d", number),
        "source_manifest" => source_pointer,
        "analysis_manifest" => artifact_ref(analysis).merge("role" => "source_analysis"),
        "selected_evidence" => artifact_ref(selected).merge("role" => "selected_evidence"),
        "selected_locator" => format("public pin %02d full readable still", number),
        "function" => index.even? ? "still_camera_and_composition" : "lighting_color_material",
        "disposition" => applied ? "applied" : "held",
        "source_eligibility" => {
          "classification" => "public_pinterest_pin",
          "public_pin_url_or_id" => format("https://www.pinterest.com/pin/%012d/", number),
          "origin_identity_verified" => true,
          "active_reuse_eligible" => true,
          "historical_row_reused_without_review" => false,
          "restricted_source_permission" => nil
        },
        "reference_connection_pointers" => [review_pointer.merge("role" => "reference_connection_review")],
        "section_bindings" => applied ? [{"section_id" => "S01", "binding_pointer" => section_binding_pointer}] : [],
        "decision_epoch" => "1",
        "worker_attempt" => {
          "lineage_id" => "LINEAGE-PINTEREST",
          "attempt_id" => "ATTEMPT-PINTEREST",
          "dispatch_id" => "DISPATCH-PINTEREST",
          "provider" => "codex",
          "session_id" => "SESSION-PINTEREST",
          "dispatch_pointer" => dispatch_pointer
        },
        "cdd_review" => {
          "reviewer" => "creative_development_director",
          "reviewed_at" => "2026-08-04T00:00:00Z",
          "disposition" => applied ? "accepted" : "held",
          "review_pointer" => review_pointer
        },
        "downstream_consumers" => []
      }
    end)
    document = {
      "schema_version" => "idol-reference-working-index.v3",
      "artifact_type" => "reference_working_index",
      "status" => "current",
      "run" => relative(run_dir),
      "owner" => "creative_development_director",
      "generated_at" => "2026-08-04T00:00:00Z",
      "source_set_digest" => {
        "algorithm" => "sha256",
        "basis" => "sorted_pointer_path_hash_pairs_v1",
        "sha256" => "0" * 64,
        "entry_count" => 0,
        "computed_at" => "2026-08-04T00:00:00Z",
        "verified_before_write" => true
      },
      "source_set_sha256" => "0" * 64,
      "authority_boundary" => {
        "derived_read_model" => true,
        "pointer_only" => true,
        "no_creative_authority" => true,
        "canonical_write" => false,
        "direct_use_granted" => false,
        "founder_approval_inferred" => false,
        "media_bytes_embedded" => false,
        "mechanical_exact_copy_only" => true
      },
      "upstream_heads" => [source_pointer],
      "worker_deltas" => [{
        "delta_id" => "DELTA-REF",
        "dispatch_id" => "DISPATCH-REF",
        "attempt_id" => "ATTEMPT-REF",
        "path" => worker_delta.fetch("path"),
        "sha256" => worker_delta.fetch("sha256"),
        "state" => "accepted"
      }],
      "rows" => rows,
      "holds" => [],
      "next_actions" => []
    }
    path = write_yaml(run_dir.join("research", "reference-working-index.yaml"), document)
    {"path" => relative(path), "sha256" => file_sha(path)}
  end

  def key_screen_function_binding(reference_unit_id, function_id, purpose, combination_role)
    {
      "reference_unit_id" => reference_unit_id,
      "function_id" => function_id,
      "purpose" => purpose,
      "combination_role" => combination_role,
      "applied_component" => "Use only the named #{purpose.tr('_', ' ')} function from this reference."
    }
  end

  def key_screen_anchor(id:, visible_members:, member_assets:, camera:, bindings:, contribution:)
    {
      "key_screen_id" => id,
      "authoring_owner" => "creative_development_director",
      "screen_job" => contribution,
      "primary_audio_cue" => "The first percussive break.",
      "scene_intent" => "Make the governing alignment event readable as one exact still screen.",
      "visible_subject" => visible_members.empty? ? "The registered marker and response guide." : "M01 from behind with her face unreadable.",
      "background_and_space" => "The passed current-title synthetic calibration field.",
      "subject_state_or_pose" => visible_members.empty? ? "No person is visible; the marker holds at registration." : "M01 keeps her shoulder quiet while one hand reaches the guide.",
      "visible_action_or_hold" => visible_members.empty? ? "The registered marker holds while response lines illuminate." : "Her hand presses the marker into registration.",
      "object_or_environment_response" => "The guide changes from flat marks to a luminous registered pattern.",
      "still_camera_and_composition" => camera,
      "camera_variation_reason" => "This view supplies screen information that the neighboring anchor cannot show.",
      "portrait_bias_guard" => "Do not center a readable face or default to a frontal beauty crop.",
      "lighting_color_material" => "Neutral silver field, controlled white guide light, matte printed surfaces.",
      "feeling_or_viewer_effect" => "Measured agency becomes physically legible.",
      "visual_identity_application" => {
        "visible_member_ids" => visible_members,
        "member_visual_asset_ids" => member_assets,
        "space_direction_source" => "major_scene_text_and_exact_scene_references",
        "separate_background_asset_attached" => false
      },
      "reference_function_bindings" => bindings,
      "distinct_screen_contribution" => contribution,
      "non_repetition_guard" => "Do not repeat the neighboring Key Screen's subject placement, scale, or information.",
      "continuity_in" => "The guide begins unchanged.",
      "continuity_out" => "The registered state remains available to 01 and 02A.",
      "downstream_01_expansion_questions" => ["Which staging detail and alternate proof preserve this anchor without replacing it?"],
      "status" => "director_passed"
    }
  end

  def direction_document(front, song)
    section = front.fetch("section_plan").first
    target = front.fetch("target_message_lock")
    spine = front.fetch("whole_film_spine")
    alignment = front.fetch("founder_visual_alignment")
    alignment_section = alignment.fetch("section_readouts").first
    alignment_cuts = alignment.fetch("planning_cut_readouts")
    {
      "schema_version" => "2.1",
      "content_id" => front.fetch("content_id"),
      "status" => "passed",
      "source_front_planning" => {
        "path" => relative(front_path),
        "sha256" => file_sha(front_path)
      },
      "source_song_lock" => artifact_ref(song),
      "director_role" => "creative_development_director_directs_and_reviews_01_story_staging_visual_choreography_and_still_camera_working_shards_overall_director_inspects_and_promotes_exact_bytes",
      "front_planning_consumption_contract" => {
        "target_message" => "exact_projection_no_reselection",
        "storyline_lineage" => "exact_project_complete_pre00_root_active_full_text_revision_history_density_review_and_reference_receipts_no_summary_substitution",
        "pre00_audience_target_lineage" => "exact_project_pre00_audience_profiles_x_envelope_and_title_target_intersection_without_reinterpretation",
        "visual_identity" => "current_title_package_exact_projection_no_cross_title_substitution",
        "section_member_assignment" => "exact_projection_unless_founder_reopens_the_section",
        "major_scene_flow" => "expand_staging_without_replacing_the_front_planning_scene_job",
        "key_screen_anchors" => "expand_director_quality_passed_key_screen_anchors_without_replacing_their_visible_action_still_camera_composition_current_title_visuals_or_reference_function_bindings",
        "reference_interpretations" => "consume_hash_bound_interpretation_and_preserve_direct_grammar",
        "founder_visual_alignment" => "exact_project_whole_film_section_and_planning_cut_readouts_without_paraphrase_or_detail_loss",
        "reopen_rule" => "changed_bytes_or_meaning_incomplete_lock_identity_safety_feasibility_conflict_or_explicit_founder_rereview_only",
        "separate_01a_artifact" => false
      },
      "storyline_lineage_projection" => value_projection("/storyline_lineage", front.fetch("storyline_lineage")),
      "pre00_audience_target_lineage_projection" => value_projection("/pre00_audience_target_lineage", front.fetch("pre00_audience_target_lineage")),
      "target_message_projection" => value_projection("/target_message_lock", target),
      "whole_film_spine_projection" => value_projection("/whole_film_spine", spine),
      "founder_visual_alignment_projection" => value_projection("/founder_visual_alignment", alignment),
      "section_directions" => [
        {
          "section_id" => "S01",
          "source_front_planning_section" => {
            "section_id" => "S01",
            "source_json_pointer" => "/section_plan/0",
            "source_value_sha256" => value_sha(section),
            "assigned_member_ids" => section.fetch("assigned_member_ids"),
            "screen_carrier" => section.fetch("screen_carrier"),
            "member_visual_asset_ids" => section.fetch("member_visual_asset_ids"),
            "background_world_asset_ids" => [],
            "sequence_unit_ids" => section.fetch("sequence_unit_ids"),
            "scene_reference_unit_ids" => section.fetch("scene_reference_unit_ids"),
            "major_scene_ids" => section.fetch("major_scene_flow").map { |row| row.fetch("major_scene_id") },
            "key_screen_anchor_ids" => section.fetch("major_scene_flow").flat_map do |row|
              row.fetch("key_screen_anchors").map { |anchor| anchor.fetch("key_screen_id") }
            end
          },
          "section_alignment_projection" => value_projection(
            "/founder_visual_alignment/section_readouts/0",
            alignment_section
          ).merge("section_id" => "S01"),
          "planning_cut_alignment_projections" => alignment_cuts.each_with_index.map do |cut, index|
            value_projection("/founder_visual_alignment/planning_cut_readouts/#{index}", cut).merge(
              "planning_cut_id" => cut.fetch("planning_cut_id"),
              "source_key_screen_id" => cut.fetch("source_key_screen_id")
            )
          end,
          "section_story_function" => section.fetch("section_story_function"),
          "primary_audio_cue" => section.fetch("primary_audio_cue"),
          "scene_expansions" => [
            {
              "scene_id" => "S01-SC01",
              "source_key_screen_anchor_ids" => ["KS_S01_CONTACT", "KS_S01_OVERHEAD"],
              "front_planning_scene_job" => "Establish the system rule and its first visible exception.",
              "space_blocking" => "M01 occupies the left fixture plane; the calibration marker sits on the middle guide.",
              "subject_entrance_and_position" => "M01 is already present from behind on the left third.",
              "visible_action_or_hold" => "Her hand aligns the calibration marker before the next chart-only view.",
              "acting_or_object_behavior" => "Her shoulder stays still while the wrist makes one measured adjustment.",
              "object_environment_change" => "The marker moves from the offset sample point to the printed registration point.",
              "still_camera_coverage_need" => "Compare a medium-wide alignment check with a marker insert.",
              "branching_strategy" => "Reveal the same alignment event through the member's measured contact and a separate overhead proof of the guide responding.",
              "branching_opportunities" => [
                {
                  "opportunity_id" => "BO_S01_CONTACT",
                  "source_key_screen_anchor_ids" => ["KS_S01_CONTACT"],
                  "core_event_relation" => "The rear three-quarter view shows who performs the governing alignment event.",
                  "distinct_screen_contribution" => "It makes hand contact and member agency readable.",
                  "observable_action_or_hold" => "M01's hand presses the marker into registration.",
                  "space_object_or_relation_change" => "The marker moves from the offset sample point to the guide.",
                  "still_camera_coverage_ids" => ["CAM-S01-01"],
                  "continuity_or_edit_use" => "Carries the contact into the overhead spatial proof.",
                  "non_repetition_guard" => "Do not repeat the same rear medium-wide composition."
                },
                {
                  "opportunity_id" => "BO_S01_OVERHEAD",
                  "source_key_screen_anchor_ids" => ["KS_S01_OVERHEAD"],
                  "core_event_relation" => "The overhead guide response is another revelation of the same alignment event, not a later event.",
                  "distinct_screen_contribution" => "It reveals the full registration geometry and the space reacting around the marker.",
                  "observable_action_or_hold" => "Concentric guide lines illuminate around the registered marker.",
                  "space_object_or_relation_change" => "The calibration field changes from flat marks to an illuminated response pattern.",
                  "still_camera_coverage_ids" => ["CAM-S01-02"],
                  "continuity_or_edit_use" => "Provides a graphic cutaway before the persistent registered state.",
                  "non_repetition_guard" => "Do not reduce this to a closer version of the contact view."
                }
              ],
              "continuity_in" => "The printed guide remains unchanged.",
              "continuity_out" => "The registered marker remains isolated.",
              "02a_core_cut_implication" => "Treat the alignment as one Core Cut with multiple Branch Cuts; make the later persistent registered condition a new Core Cut."
            }
          ],
          "reference_applications" => [
            {
              "application_id" => "VRB_SCENE_SEQ",
              "reference_unit_id" => "REF-01",
              "source_path" => front.dig("reference_connection_research", "reference_units", 0, "source_path"),
              "source_sha256" => front.dig("reference_connection_research", "reference_units", 0, "source_sha256"),
              "direct_use_mode" => "sequence_direct",
              "scene_or_sequence_target" => "S01-SC01 synthetic alignment action and registered state.",
              "preserved_action_or_hold" => "A hand aligns the calibration marker.",
              "preserved_staging" => "Fixture subject on the left and marker at the center guide.",
              "preserved_still_camera" => "Waist-height lateral medium-wide view.",
              "preserved_subject_placement_and_crop" => "Left-third fixture subject with the registration guide visible.",
              "preserved_ordered_grammar" => ["marker begins offset", "hand aligns it", "registered state holds"],
              "intentional_deviation" => [
                "Replace the source identity with the current-title member appearance."
              ],
              "02a_binding_rule" => "bind_each_selected_cell_crop_or_frame_as_its_own_path_and_sha256_never_whole_sheet_fallback"
            }
          ],
          "sequence_motion_adoptions" => [
            {
              "analysis_id" => "SMA_ACTIVE_TITLE_TEST_S01_MJ01",
              "major_scene_id" => "MJ01",
              "selected_sequence_composition_id" => "SCOMP_MJ01_01",
              "overall_disposition" => "partial",
              "dimension_dispositions" => {
                "depth" => "adopt",
                "alternate_view" => "partial",
                "reveal_space" => "adopt",
                "rear_world_direction" => "partial",
                "identity" => "adopt",
                "crop" => "adopt",
                "occlusion" => "partial",
                "continuity" => "adopt",
                "start_landing" => "partial"
              },
              "authored_reason" => "01 independently adopts the supported still depth, reveal, crop, continuity, and intentionally unreadable rear-view identity cues, while partially using alternate-view and state-boundary advice; exact temporal intensity remains 03V-owned.",
              "applied_official_core_cut_ids" => ["C01", "C02"],
              "applied_still_camera_coverage_ids" => ["CAM-S01-01", "CAM-S01-02"],
              "applied_branching_opportunity_ids" => ["BO_S01_CONTACT", "BO_S01_OVERHEAD"]
            }
          ],
          "still_camera_coverage" => [
            {
              "coverage_id" => "CAM-S01-01",
              "scene_id" => "S01-SC01",
              "source_key_screen_anchor_ids" => ["KS_S01_CONTACT"],
              "screen_readability_job" => "Read the hand contact and the marker registration state.",
              "shot_scale_distance" => "medium-wide at four meters",
              "camera_height" => "waist height",
              "direction_angle" => "lateral three-quarter view",
              "depth_design" => "foreground scale marks, fixture plane, flat test backdrop",
              "subject_placement" => "left third",
              "crop_negative_space" => "keep the printed registration guide unobstructed",
              "variation_reason" => "A closer insert isolates the calibration result without repeating the member.",
              "temporal_camera_owner" => "03V_after_passed_image_pixel_inspection"
            },
            {
              "coverage_id" => "CAM-S01-02",
              "scene_id" => "S01-SC01",
              "source_key_screen_anchor_ids" => ["KS_S01_OVERHEAD"],
              "screen_readability_job" => "Read the full guide geometry responding around the marker.",
              "shot_scale_distance" => "top-down medium insert at two meters",
              "camera_height" => "two meters above the guide",
              "direction_angle" => "orthographic overhead",
              "depth_design" => "marker on the guide plane with luminous response lines beneath it",
              "subject_placement" => "marker centered with the full guide radius visible",
              "crop_negative_space" => "even margin around the outer response ring",
              "variation_reason" => "The overhead branch reveals spatial information unavailable in the member-contact view.",
              "temporal_camera_owner" => "03V_after_passed_image_pixel_inspection"
            }
          ],
          "choreography_presence_policy" => "absent",
          "choreography_reference_binding" => nil,
          "visual_projection" => {
            "current_title_album_key" => album_key,
            "current_title_key" => title_key,
            "member_visual_asset_ids" => ["VIS-M01"],
            "background_world_asset_ids" => [],
            "visual_control_rule" => "member_visual_controls_appearance_only_and_never_forces_face_frontal_gaze_pose_camera_crop_or_proportions",
            "02a_selection_rule" => "each_branch_cut_selects_the_smallest_relevant_subset_from_this_authorized_section_pool"
          },
          "transition_in" => section.fetch("transition_in"),
          "transition_out" => section.fetch("transition_out"),
          "02a_authoring_questions" => ["Which visible states are required for the contact and consequence?"],
          "status" => "passed"
        }
      ],
      "downstream_02a_contract" => {
        "coverage_owner" => "02A_internal_no_separate_02_artifact",
        "core_cut_definition" => "parent_major_event_action_effect_condition_or_dramatic_beat_that_may_span_several_framed_screens",
        "branch_cut_definition" => "one_independently_framed_and_generatable_screen_realization_that_derives_from_the_parent_core_event_and_adds_distinct_observable_information",
        "branch_cut_cardinality" => "one_to_n_per_core_cut_without_global_cap_or_fixed_directorial_category_quota",
        "new_core_cut_rule" => "a_new_governing_event_requires_a_new_core_cut_while_a_materially_different_revelation_of_the_same_event_is_a_branch_cut",
        "reference_binding_rule" => "bind_selected_sequence_cells_crops_or_scene_images_individually_with_path_sha256_and_preserved_grammar",
        "member_visual_rule" => "current_title_package_only_smallest_branch_cut_relevant_subset_no_member_visual_when_no_member_is_visible",
        "still_camera_rule" => "02A_authors_height_distance_direction_angle_depth_placement_and_crop_for_each_branch_cut",
        "key_screen_lineage_rule" => "02A_consumes_the_01_section_hash_that_preserves_each_director_quality_passed_front_planning_key_screen_anchor_and_its_expansion",
        "storyline_lineage_rule" => "02A_exact_copies_the_whole_film_section_and_planning_cut_alignment_pointers_values_and_hashes_before_expanding_core_and_branch_cuts",
        "temporal_camera_rule" => "03V_authors_push_pull_pan_tilt_track_orbit_speed_envelope_start_and_stop_after_pixels_pass"
      },
      "review_surface" => {
        "html_contract_version" => "idol-html-review-board.v12",
        "hierarchy" => "target_and_message_then_whole_film_and_section_flow_then_sections_then_core_cuts_then_branch_cuts",
        "founder_visual_alignment_projection" => "exact_readouts_remain_visible_beside_their_01_section_and_cut_expansion_cards",
        "decision_values" => ["PASS", "HOLD", "REJECT"]
      },
      "open_questions" => []
    }
  end

  def upgrade_direction_document!(document, front)
    document["schema_version"] = "3.0"
    active = front.dig("storyline_lineage", "active_version")
    screen_map = front.fetch("screen_progression_map")
    document["imported_fp_head"] = {
      "path" => relative(front_path),
      "sha256" => file_sha(front_path),
      "schema_version" => "front-planning-readiness.v17",
      "selected_candidate_route_id" => "FP-A",
      "active_storyline_version_id" => active.fetch("version_id"),
      "active_storyline_sha256" => active.fetch("full_storyline_text_sha256"),
      "screen_progression_map_id" => screen_map.fetch("screen_progression_map_id"),
      "screen_progression_map_sha256" => value_sha(screen_map)
    }
    document["derivative_route_id"] = "DERIV_FULL_MV"
    document["production_scope_id"] = "PSCOPE_FULL_MV"
    document["screen_progression_map_projection"] = value_projection("/screen_progression_map", screen_map)
    section_direction = document.fetch("section_directions").first
    section_direction.fetch("scene_expansions").each { |row| row["scene_id"] = "MJ01" }
    section_direction.fetch("still_camera_coverage").each { |row| row["scene_id"] = "MJ01" }
    core_refs = front.fetch("core_reference_bindings").to_h { |row| [row.fetch("core_slot_id"), row.fetch("decision")] }
    camera_c01 = {
      "shot_scale_distance" => "medium-wide at four meters",
      "camera_height" => "waist height",
      "direction_angle" => "lateral rear three-quarter view",
      "depth" => "foreground scale marks, member plane, and guide plane",
      "subject_placement" => "cause and consequence remain simultaneously readable",
      "crop_negative_space" => "retain the complete guide response"
    }
    camera_c02 = {
      "shot_scale_distance" => "close insert at one meter",
      "camera_height" => "marker height",
      "direction_angle" => "lateral side view",
      "depth" => "foreground scale marks, marker plane, and guide plane",
      "subject_placement" => "the registered marker remains readable without a member portrait",
      "crop_negative_space" => "retain the left-side scale marks"
    }
    motion = {
      "action_vector" => "Marker travel resolves into a retained registered state.",
      "lead_or_reveal_room" => "Keep clear room along the marker path and response ring.",
      "depth_layers" => "Foreground marks, subject plane, marker plane, matte backdrop.",
      "occlusion_plan" => "The hand may cross the marker only during contact; the final state remains unobstructed.",
      "crop_safe_room" => "Preserve the guide radius and wrist action inside the frame.",
      "start_end_potential" => "Offset start and registered end remain independently readable.",
      "transition_vector" => "Carry the registered marker position from action to consequence."
    }
    document["official_core_cuts"] = %w[CS01 CS02].each_with_index.map do |slot_id, index|
      decision = core_refs.fetch(slot_id)
      image = @hero_core_images[index]
      core_id = "C0#{index + 1}"
      {
        "core_cut_id" => core_id,
        "parent_major_scene_id" => "MJ01",
        "scene_phase_context" => index.zero? ? "member action" : "system consequence",
        "source_core_slot_id" => slot_id,
        "active_storyline_version_id" => active.fetch("version_id"),
        "screen_progression_node_id" => "SPN_#{slot_id}",
        "section_id" => "S01",
        "order_within_section" => index + 1,
        "parent_major_order" => 1,
        "primary_audio_cue" => "The first percussive break.",
        "required_screen_information" => index.zero? ? "M01 visibly causes marker registration." : "The guide retains the registered state after contact.",
        "visible_subject" => index.zero? ? "M01's rear three-quarter torso, hand, marker, and guide." : "The registered marker and complete guide response; M01 is absent.",
        "visible_action_or_hold" => index.zero? ? "M01 completes one measured marker alignment." : "Hold the registered guide state without a second event.",
        "visible_state_change" => index.zero? ? "The marker moves from offset to registered." : "The guide changes from unlit to a retained response.",
        "environment_and_depth" => "The calibration field preserves layered guide, subject, and response planes.",
        "camera" => index.zero? ? camera_c01 : camera_c02,
        "composition" => index.zero? ? "M01 occupies the left third while the marker route remains open." : "Center the marker and preserve the full response ring.",
        "motion_readiness" => motion,
        "identity_when_visible" => index.zero? ? "M01 current-title identity is visible from the rear three-quarter body and hand." : "No member identity is visible.",
        "member_visual_applicability" => index.zero? ? "meaningfully_visible" : "not_visible",
        "core_reference_binding" => {
          "required" => true,
          "binding_id" => "CRB_#{slot_id}",
          "selected_reference_candidate_id" => decision.fetch("selected_reference_candidate_id"),
          "source_type" => index.zero? ? "sequence_crop" : "registered_still",
          "actual_path" => decision.fetch("actual_path"),
          "sha256" => decision.fetch("sha256"),
          "pixel_inspection_status" => "inspected",
          "governing_functions" => decision.fetch("governing_functions"),
          "source_to_screen_delta" => decision.fetch("source_to_screen_delta"),
          "founder_reference_waiver" => nil
        },
        "supporting_reference_bindings" => ["REF-02"],
        "sequence_phase_bindings" => ["SEQU_REF_01"],
        "continuity_in" => [index.zero? ? "The marker begins offset." : "Match C01's exact registered marker position."],
        "continuity_out" => [index.zero? ? "Carry the registered marker into C02." : "Leave the registered guide as the ending trace."],
        "primary_image" => {"status" => "pass", "actual_path" => image.fetch("path"), "sha256" => image.fetch("sha256"), "pixel_review" => {"verdict" => "pass", "note" => "Exact fixture pixels preserve the selected Core job."}},
        "branch_expansion_need" => [index.zero? ? "Expand member contact and exact marker relation through distinct Branch views." : "Expand the spatial consequence without inventing a new governing event."]
      }
    end
    document["hero_core_adoptions"] = document["official_core_cuts"].each_with_index.map do |core, index|
      image = @hero_core_images[index]
      {"hero_core_candidate_id" => "HERO_CS0#{index + 1}", "output_path" => image.fetch("path"), "output_sha256" => image.fetch("sha256"), "adopted_as_core_cut_id" => core.fetch("core_cut_id"), "semantic_equivalence_review" => "The adopted Hero output performs the selected Core Slot without changing its event meaning.", "current_section_review" => "pass", "input_lineage_preserved" => true}
    end
    core_ids = document["official_core_cuts"].map { |row| row.fetch("core_cut_id") }
    document["core_storyboard"] = core_ids
    document["branch_expansion_needs"] = document["official_core_cuts"].map { |row| {"core_cut_id" => row.fetch("core_cut_id"), "needed_contributions" => row.fetch("branch_expansion_need")} }
    document["section_camera_composition_depth_progression"] = [{"section_id" => "S01", "ordered_core_cut_ids" => core_ids, "progression_read" => "Move from hand-led lateral causality to centered overhead spatial proof without repeating scale or subject placement."}]
    document["core_motion_readiness_map"] = document["official_core_cuts"].map { |row| {"core_cut_id" => row.fetch("core_cut_id"), "motion_readiness" => row.fetch("motion_readiness")} }
    document["whole_film_core_review"] = {"verdict" => "pass", "reviewed_core_cut_ids" => core_ids, "anchor_progression_read" => "C01 causes the change and C02 preserves its consequence.", "camera_depth_repetition_review" => "The lateral member action and centered spatial proof are materially distinct."}
    downstream = document.fetch("downstream_02a_contract")
    downstream["coverage_owner"] = "01_owns_official_core_02A_owns_branch_only"
    downstream["pre00_audience_target_lineage_rule"] = "02A_exact_copies_01_pre00_audience_profiles_x_envelope_and_title_target_intersection_projection"
    downstream["still_camera_rule"] = "01_authors_core_camera_composition_depth_and_02A_authors_each_branch_variation"
    document
  end

  def value_projection(pointer, value)
    {
      "source_json_pointer" => pointer,
      "source_value_sha256" => value_sha(value),
      "projected_value" => value
    }
  end

  def storyboard_alignment_projection(source_01_pointer, source_projection)
    value = source_projection.fetch("projected_value")
    {
      "source_01_json_pointer" => source_01_pointer,
      "source_front_planning_json_pointer" => source_projection.fetch("source_json_pointer"),
      "source_value_sha256" => value_sha(value),
      "projected_value" => value
    }
  end

  def storyboard_document(front, direction, member, sequence)
    direction_section = direction.fetch("section_directions").first
    section_alignment = direction_section.fetch("section_alignment_projection")
    cut_alignments = direction_section.fetch("planning_cut_alignment_projections")
    cuts = [
      core_cut(
        id: "C01",
        range: "00:00.000-00:06.000",
        role: "member action",
        visible_members: ["M01"],
        member: member,
        sequence: sequence,
        storyline_cut_alignments: cut_alignments
      ),
      core_cut(
        id: "C02",
        range: "00:06.000-00:12.000",
        role: "object consequence",
        visible_members: [],
        member: member,
        sequence: sequence,
        storyline_cut_alignments: cut_alignments
      )
    ]
    target = front.fetch("target_message_lock")
    spine = front.fetch("whole_film_spine")
    {
      "schema_version" => "2.5",
      "content_id" => front.fetch("content_id"),
      "status" => "passed",
      "source_front_planning" => {"path" => relative(front_path), "sha256" => file_sha(front_path)},
      "source_01_direction" => {"path" => relative(direction_path), "sha256" => file_sha(direction_path)},
      "output_intent" => "Generate exact still states for the member action and its object consequence.",
      "storyline_lineage_projection" => storyboard_alignment_projection(
        "/storyline_lineage_projection/projected_value",
        direction.fetch("storyline_lineage_projection")
      ),
      "pre00_audience_target_lineage_projection" => storyboard_alignment_projection(
        "/pre00_audience_target_lineage_projection/projected_value",
        direction.fetch("pre00_audience_target_lineage_projection")
      ),
      "target_message_summary" => {
        "primary_target" => target.fetch("primary_target"),
        "audience_promise" => target.fetch("audience_promise"),
        "core_message" => target.fetch("core_message"),
        "desired_response" => target.fetch("desired_response"),
        "do_not_serve" => target.fetch("do_not_serve")
      },
      "whole_film_spine" => {
        "opening_state" => spine.fetch("opening_state"),
        "progression" => spine.fetch("progression"),
        "turn" => spine.fetch("turn"),
        "resolution_or_afterimage" => spine.fetch("resolution_or_afterimage"),
        "recurrence_rule" => spine.fetch("recurrence_rule")
      },
      "founder_visual_alignment_projection" => storyboard_alignment_projection(
        "/founder_visual_alignment_projection/projected_value",
        direction.fetch("founder_visual_alignment_projection")
      ),
      "creative_role_harness" => "creative_development_director_directs_and_reviews_02a_immutable_core_import_and_branch_only_working_shards_overall_director_inspects_and_promotes_exact_bytes",
      "branch_subject_mix_policy" => "Use member-led, spatial-response, and object-only Branch Cuts; do not default to readable frontal faces.",
      "coverage_plan" => {
        "owner" => "02A_internal",
        "unit" => "core_event_cut_then_1_to_n_distinct_branch_cut_children",
        "cardinality_rule" => "story_audio_screen_state_camera_composition_transition_and_edit_evidence_decide_counts_no_global_cap",
        "coverage_dimensions" => [
          "audio_or_section_cue",
          "visible_action_or_hold",
          "screen_carrier",
          "space_or_object_state",
          "still_camera_geometry",
          "composition",
          "reference_grammar",
          "continuity"
        ],
        "section_exact_cover_required" => true
      },
      "section_shards" => [
        {
          "shard_id" => "SHARD_S01_ACTIVE",
          "section_ids" => ["S01"],
          "core_cut_ids" => ["C01", "C02"],
          "time_range" => "00:00.000-00:12.000",
          "section_goal" => "Exercise one member-visible state and one object-only state in a synthetic calibration sequence.",
          "assigned_member_ids" => ["M01"],
          "member_owner" => "M01 owns the fixture action; the calibration marker owns the resulting test state.",
          "frame_subject_mode" => "mixed_member_world",
          "visual_system_anchor" => "Synthetic calibration field and registered marker.",
          "authorized_member_visual_asset_ids" => ["VIS-M01"],
          "authorized_scene_reference_binding_ids" => ["VRB_SCENE_SEQ"],
          "source_01_section" => {
            "section_id" => "S01",
            "json_pointer" => "/section_directions/0",
            "value_sha256" => value_sha(direction.fetch("section_directions").first)
          },
          "section_alignment_projection" => storyboard_alignment_projection(
            "/section_directions/0/section_alignment_projection/projected_value",
            section_alignment
          ).merge("section_id" => "S01"),
          "planning_cut_alignment_projections" => cut_alignments.each_with_index.map do |projection, index|
            storyboard_alignment_projection(
              "/section_directions/0/planning_cut_alignment_projections/#{index}/projected_value",
              projection
            ).merge(
              "planning_cut_id" => projection.fetch("planning_cut_id"),
              "source_key_screen_id" => projection.fetch("source_key_screen_id")
            )
          end,
          "transition_in" => transition("first percussion", "calibration guide is unchanged", "alignment marker"),
          "transition_out" => transition("section release", "marker remains registered", "alignment marker"),
          "status" => "passed",
          "path" => relative(run_dir.join("work", "02A", "sections", "S01.yaml"))
        }
      ],
      "master_storyboard" => cuts,
      "founder_planning_gate" => {
        "decision" => "pass",
        "reviewed_scope" => "whole_video",
        "reviewed_section_ids" => ["S01"],
        "review_note" => "Founder reviewed the exact FP Close storyline, 01 expansion, and 02A Core/Branch plan.",
        "storyline_review_order" => "complete_pre00_root_and_active_full_text_lineage_then_fp_close_and_01_expansion_then_02a_core_and_branch_plan",
        "authorizes" => "affected_02B_route_only",
        "paid_generation_authorized" => false
      },
      "review_surface" => {
        "html_contract_version" => "idol-html-review-board.v12",
        "hierarchy" => "target_and_message_then_whole_video_and_section_flow_then_sections_then_core_cuts_then_branch_cuts",
        "decision_values" => ["PASS", "HOLD", "REJECT"],
        "revision_scope_values" => ["branch_cut", "core_cut", "section", "whole_video"]
      },
      "open_questions" => []
    }
  end

  def upgrade_storyboard_document!(document, front, direction)
    document["schema_version"] = "3.0"
    document["derivative_route_id"] = direction.fetch("derivative_route_id")
    document["production_scope_id"] = direction.fetch("production_scope_id")
    source_cores = direction.fetch("official_core_cuts")
    document["imported_core_storyboard_head"] = {
      "source_01_path" => relative(direction_path),
      "source_01_sha256" => file_sha(direction_path),
      "source_01_schema_version" => "3.0",
      "source_json_pointer" => "/official_core_cuts",
      "source_value_sha256" => value_sha(source_cores),
      "projected_value" => source_cores,
      "authorship_owner" => "01_imported_immutable",
      "mutation_rule" => "02A_must_request_01_or_FP_smallest_owner_revision_instead_of_editing_Core_meaning_or_image"
    }
    document["screen_progression_map_projection"] = storyboard_alignment_projection(
      "/screen_progression_map_projection/projected_value",
      direction.fetch("screen_progression_map_projection")
    )

    upgraded_cores = document.fetch("master_storyboard").each_with_index.map do |legacy_core, core_index|
      source_core = source_cores.fetch(core_index)
      branches = legacy_core.dig("compile_seed", "branch_cuts")
      branches.each_with_index do |branch, branch_index|
        branch.merge!(
          "parent_core_cut_id" => source_core.fetch("core_cut_id"),
          "active_storyline_version_id" => source_core.fetch("active_storyline_version_id"),
          "screen_progression_node_id" => source_core.fetch("screen_progression_node_id"),
          "section_id" => source_core.fetch("section_id"),
          "parent_major_scene_id" => source_core.fetch("parent_major_scene_id"),
          "scene_phase_context" => source_core.fetch("scene_phase_context"),
          "order_within_core" => branch_index + 1,
          "contribution_type" => if branch["branch_cut_id"].include?("OVERHEAD")
                                   "spatial_consequence"
                                 elsif branch["branch_cut_id"].include?("HOLD")
                                   "phase"
                                 else
                                   "participant_response"
                                 end,
          "directorial_or_edit_job" => branch.fetch("distinct_screen_contribution"),
          "primary_still_job_count" => 1,
          "expected_output" => {
            "count" => 1,
            "path" => relative(run_dir.join("02B", "images", "#{branch.fetch('branch_cut_id')}.png")),
            "model_or_tool" => "gpt-image-2"
          },
          "generation_status" => "planned"
        )
      end
      {
        "core_cut_id" => source_core.fetch("core_cut_id"),
        "source_01_core" => {"source_json_pointer" => "/official_core_cuts/#{core_index}", "source_value_sha256" => value_sha(source_core)},
        "imported_core" => source_core,
        "authorship_owner" => "01_imported_immutable",
        "core_mutation_performed" => false,
        "compile_seed" => {"branch_cuts" => branches}
      }
    end
    document["master_storyboard"] = upgraded_cores
    branch_rows = upgraded_cores.flat_map do |core|
      core.dig("compile_seed", "branch_cuts").map { |branch| [core, branch] }
    end
    branch_ids = branch_rows.map { |_core, branch| branch.fetch("branch_cut_id") }
    document["official_branch_cuts"] = branch_ids
    document["reference_coverage_matrix"] = branch_rows.map do |core, branch|
      scene_ids = branch.fetch("visual_reference_bindings").select { |row| row.fetch("reference_scope") == "scene_visual" }.map { |row| row.fetch("binding_id") }
      {"core_cut_id" => core.fetch("core_cut_id"), "branch_cut_id" => branch.fetch("branch_cut_id"), "coverage_mode" => "reference_led", "exact_source_binding_ids" => scene_ids, "status" => "complete"}
    end
    document["camera_diversity_review"] = {
      "verdict" => "pass",
      "reviewed_branch_cut_ids" => branch_ids,
      "reviewed_core_cut_ids" => upgraded_cores.map { |core| core.fetch("core_cut_id") },
      "same_core_and_whole_film_read" => "Member contact, overhead spatial proof, and lateral object persistence add distinct information without repeated camera jobs.",
      "collected_image_camera_angle_review" => collected_storyboard_camera_angle_review(document)
    }
    document["branch_generation_manifest"] = {"production_scope_id" => document.fetch("production_scope_id"), "planned_branch_cut_ids" => branch_ids, "expected_output_count_per_branch" => 1, "paid_generation_authorized" => false}
    document["g40_core_branch_authorization"] = {
      "decision" => "pass",
      "derivative_route_id" => document.fetch("derivative_route_id"),
      "production_scope_id" => document.fetch("production_scope_id"),
      "reviewed_core_cut_ids" => source_cores.map { |row| row.fetch("core_cut_id") },
      "reviewed_branch_cut_ids" => branch_ids,
      "draft_keyframe_grade_vector" => {
        "path" => relative(draft_keyframe_grade_path),
        "sha256" => file_sha(draft_keyframe_grade_path),
        "stage" => "draft_keyframe_proof"
      },
      "paid_generation_authorized" => false
    }
    document
  end

  def transition(audio, visible, carrier)
    {
      "audio_trigger" => audio,
      "visible_state" => visible,
      "continuity_carrier" => carrier
    }
  end

  def visual_binding(binding_id:, asset_id:, owner:, entry:, scope:, klass:, order:)
    {
      "binding_id" => binding_id,
      "asset_id" => asset_id,
      "source_owner" => owner,
      "actual_path" => entry.fetch("path"),
      "sha256" => entry.fetch("sha256"),
      "role" => scope == "member_visual" ? "Current-title member appearance continuity only." : "Preserve action, placement, crop, and ordered sequence grammar.",
      "reference_scope" => scope,
      "reference_class" => klass,
      "order" => order,
      "must_inspect_pixels" => true,
      "preserve" => scope == "member_visual" ? ["hair, wardrobe, material, silhouette"] : ["action, staging, still-camera geometry, crop, ordered grammar"],
      "discard" => scope == "member_visual" ? ["source pose or camera implication"] : ["source performer identity"],
      "attachment_permission" => "attach_after_exact_founder_approval"
    }
  end

  def core_cut(id:, range:, role:, visible_members:, member:, sequence:, storyline_cut_alignments:)
    branch_cuts = if id == "C01"
                    [
                      branch_cut(
                        id: "BC01_ACTION",
                        packet_id: "PKT_BC01_ACTION",
                        sequence_number: 1,
                        role: "member contact",
                        visible_members: visible_members,
                        member: member,
                        sequence: sequence,
                        contribution: "Shows who causes the alignment and makes the hand-to-marker contact readable.",
                        time_relation: "On the percussion impact phase, while the marker crosses into registration.",
                        visible_action: "M01's hand aligns the marker from behind.",
                        composition: "Back-view fixture figure on the left third; marker at the center guide.",
                        camera: {
                          "shot_scale_distance" => "medium-wide at four meters",
                          "camera_height" => "waist height",
                          "direction_angle" => "lateral three-quarter rear view",
                          "depth_design" => "foreground scale marks, fixture plane, flat test backdrop",
                          "subject_placement" => "fixture figure left, marker at center guide",
                          "crop_negative_space" => "keep the registration guide visible"
                        },
                        shot_scale: "medium-wide",
                        required_visibility: ["member hand", "alignment marker", "printed registration guide"],
                        action_cue: "The hand is visibly in contact with the marker while it reaches the guide.",
                        continuity_in: "The marker is offset from the printed guide.",
                        continuity_out: "The marker reaches registration and the guide begins to respond.",
                        storyline_projection: storyline_cut_alignments.fetch(0),
                        storyline_expansion_delta: "Specify the first independently generatable contact frame: rear three-quarter hand-to-marker contact at the exact moment registration completes."
                      ),
                      branch_cut(
                        id: "BC01_OVERHEAD",
                        packet_id: "PKT_BC01_OVERHEAD",
                        sequence_number: 2,
                        role: "spatial response",
                        visible_members: [],
                        member: member,
                        sequence: sequence,
                        contribution: "Reveals the full registration geometry and the environment response hidden by the contact view.",
                        time_relation: "Immediately after contact, while the same alignment event spreads through the guide.",
                        visible_action: "Concentric guide lines illuminate around the registered marker.",
                        composition: "No person; the marker is centered inside the complete response pattern.",
                        camera: {
                          "shot_scale_distance" => "top-down medium insert at two meters",
                          "camera_height" => "two meters above the guide",
                          "direction_angle" => "orthographic overhead",
                          "depth_design" => "marker on the guide plane with luminous response lines beneath it",
                          "subject_placement" => "marker centered with the full guide radius visible",
                          "crop_negative_space" => "even margin around the outer response ring"
                        },
                        shot_scale: "top-down medium insert",
                        required_visibility: ["alignment marker", "complete printed guide", "illuminated response rings"],
                        action_cue: "The guide visibly illuminates outward from the registered marker.",
                        continuity_in: "The marker has just reached registration.",
                        continuity_out: "The illuminated geometry leaves the marker visibly locked in place.",
                        storyline_projection: storyline_cut_alignments.fetch(1),
                        storyline_expansion_delta: "Specify the immediate overhead proof frame with the complete response ring visible and no member in frame."
                      )
                    ]
                  else
                    [
                      branch_cut(
                        id: "BC02_HOLD",
                        packet_id: "PKT_BC02_HOLD",
                        sequence_number: 1,
                        role: "object consequence",
                        visible_members: [],
                        member: member,
                        sequence: sequence,
                        contribution: "Proves the changed registration condition persists after the member leaves the frame.",
                        time_relation: "During the sustained-tone hold, after the alignment event has completed.",
                        visible_action: "The marker remains locked at the printed registration point.",
                        composition: "No person; marker in the lower-right test cell beside the printed guide.",
                        camera: {
                          "shot_scale_distance" => "close insert at one meter",
                          "camera_height" => "marker height",
                          "direction_angle" => "lateral side view",
                          "depth_design" => "foreground scale marks, marker plane, flat test backdrop",
                          "subject_placement" => "marker in the lower-right test cell",
                          "crop_negative_space" => "keep the left-side scale marks visible"
                        },
                        shot_scale: "close insert",
                        required_visibility: ["alignment marker", "printed guide", "registered state"],
                        action_cue: "The marker visibly holds at the printed registration point.",
                        continuity_in: "The guide response has settled around the marker.",
                        continuity_out: "The registered marker remains the outgoing continuity carrier.",
                        storyline_projection: storyline_cut_alignments.fetch(1),
                        storyline_expansion_delta: "Extend the aligned overhead consequence into a separate lateral persistence frame so the registered state remains legible after the response settles."
                      )
                    ]
                  end

    {
      "core_cut_id" => id,
      "cut_role" => role,
      "time_range" => range,
      "duration_seconds" => 6.0,
      "source_sections" => ["S01"],
      "song_function" => id == "C01" ? "The percussion gives the member a precise intervention point." : "The sustained tone makes the changed object state readable.",
      "core_event_lock" => {
        "dramatic_job" => id == "C01" ? "Show deliberate agency." : "Prove the world changed.",
        "intended_viewer_read" => id == "C01" ? "A first-time viewer understands that M01 deliberately causes the calibration field to respond." : "A first-time viewer understands that M01's action left a stable change in the world.",
        "core_event" => id == "C01" ? "M01 aligns the calibration marker and the guide responds." : "The registered marker persists after the alignment event.",
        "location" => "Synthetic layered calibration field.",
        "screen_carrier" => id == "C01" ? "M01 hand, alignment marker, and response guide." : "Alignment marker and printed guide.",
        "event_action_or_hold" => id == "C01" ? "M01 aligns the marker with one hand while the guide illuminates." : "The marker holds at the registration point after M01 clears frame.",
        "object_or_environment_consequence" => id == "C01" ? "The marker registers and the guide illuminates outward." : "The registered state remains stable without the member.",
        "member_or_nonmember_state" => id == "C01" ? "M01 is seen from behind in one branch and omitted from the spatial branch." : "No member is visible.",
        "why_it_fits_song" => "The audible break becomes a visible causal break.",
        "must_preserve_across_branches" => ["the same marker alignment event", "the printed registration geometry"],
        "forbidden_event_drift" => ["an unrelated action", "a generic portrait without the calibration state"]
      },
      "core_visual_direction" => {
        "integrated_direction" => id == "C01" ? "Pair member agency with an overhead proof of the same event changing space." : "Isolate the persistent consequence without returning to the member.",
        "member_focus" => visible_members,
        "composition_family" => id == "C01" ? "Rear three-quarter contact plus overhead response geometry." : "Object-only lateral insert.",
        "light_world" => "Neutral calibration illumination with even chart visibility.",
        "performance_or_nonperformance_action" => id == "C01" ? "A measured wrist adjustment, not choreography." : "A static marker hold.",
        "memory_value" => "The registered marker state is the synthetic section trace."
      },
      "camera_coverage_plan" => {
        "contract_version" => "core_camera_coverage.v1",
        "still_camera_only" => true,
        "comparison_job" => id == "C01" ? "Compare who causes the event with how the same event changes the guide geometry." : "Read the persistent registered condition without a member portrait.",
        "coverage_reason" => id == "C01" ? "Two Branch Cuts add different information about one event." : "One Branch Cut is sufficient because this Core Cut owns one independently readable condition.",
        "spatial_anchor_and_axis" => id == "C01" ? "Keep the camera on the rear-left side of M01's hand-to-marker action axis; the marker moves toward the center guide before the overhead branch reveals the same axis as complete geometry." : "Stand on the marker's lateral side, perpendicular to the printed guide, so the locked registration gap and empty member space remain readable.",
        "anchor_view" => if id == "C01"
                           {
                             "camera_position_in_space" => "Four meters from the fixture plane on the rear-left side of M01 and the alignment marker.",
                             "camera_height" => "Waist height relative to M01.",
                             "shot_scale_distance" => "Medium-wide at four meters.",
                             "camera_direction" => "Toward the center guide from the rear-left side.",
                             "camera_angle" => "Lateral three-quarter rear angle.",
                             "depth_design" => "Foreground scale marks, M01 and marker on the fixture plane, flat test backdrop.",
                             "subject_space_composition" => "M01 occupies the left third while the hand-to-marker contact points toward the center guide.",
                             "crop_negative_space" => "Keep the complete registration guide and response space open on frame right.",
                             "lens_feel" => "Natural perspective with undistorted proportions."
                           }
                         else
                           {
                             "camera_position_in_space" => "One meter from the marker on the lateral side of the printed guide.",
                             "camera_height" => "Level with the marker.",
                             "shot_scale_distance" => "Close insert at one meter.",
                             "camera_direction" => "Perpendicular to the marker and printed guide.",
                             "camera_angle" => "Lateral side angle.",
                             "depth_design" => "Foreground scale marks, marker plane, flat test backdrop.",
                             "subject_space_composition" => "The marker occupies the lower-right test cell while the empty member side remains visible.",
                             "crop_negative_space" => "Preserve the left-side scale marks and the gap around the registration point.",
                             "lens_feel" => "Natural close-in perspective without shape distortion."
                           }
                         end,
        "branch_camera_roles" => if id == "C01"
                                   [
                                     {
                                       "branch_cut_id" => "BC01_ACTION",
                                       "camera_role" => "Establish who causes the alignment through readable hand-to-marker contact.",
                                       "relationship_to_anchor" => "Use the Core anchor directly and preserve the rear-left action axis."
                                     },
                                     {
                                       "branch_cut_id" => "BC01_OVERHEAD",
                                       "camera_role" => "Reveal the complete guide response that the contact view cannot show.",
                                       "relationship_to_anchor" => "Preserve the same marker, guide center, and response direction while intentionally changing to an overhead spatial proof."
                                     }
                                   ]
                                 else
                                   [
                                     {
                                       "branch_cut_id" => "BC02_HOLD",
                                       "camera_role" => "Prove that the registered condition persists without returning to a member-led frame.",
                                       "relationship_to_anchor" => "Use the Core anchor directly and hold the lateral marker-to-guide relation."
                                     }
                                   ]
                                 end,
        "protected_continuity" => "Preserve the marker identity, printed guide orientation, registration direction, and screen-readable cause or consequence across the Core Cut.",
        "allowed_variation" => id == "C01" ? "Branch Cuts may change height, distance, and angle when the new view reveals agency versus complete spatial response." : "Only a materially new proof need may depart from the lateral object-only anchor.",
        "creative_variation_rule" => "branch_cuts_may_depart_broadly_from_the_anchor_including_height_distance_direction_angle_axis_depth_placement_crop_lens_and_viewpoint_when_each_departure_adds_new_screen_information_and_preserves_or_explicitly_resets_continuity",
        "forbidden_collapse" => "Do not collapse the coverage into repeated centered face-readable framing, arbitrary axis reversals, or camera changes that reveal no new information.",
        "exact_branch_camera_owner" => "each_branch_cut_still_camera_spec_is_authoritative_anchor_guides_coverage_without_forcing_one_fixed_view",
        "temporal_camera_owner" => "03V_after_passed_image_pixel_inspection"
      },
      "reference_application_ids" => ["VRB_SCENE_SEQ"],
      "choreography_presence_policy" => "absent",
      "choreography_reference_binding" => nil,
      "edit_logic" => {
        "entry_trigger" => id == "C01" ? "first percussion" : "sustained tone",
        "exit_trigger" => id == "C01" ? "guide response settles" : "section release",
        "continuity_carrier" => "alignment marker",
        "next_core_cut_reason" => id == "C01" ? "The object-only hold follows to prove the consequence of M01's completed alignment action." : "The stable marker becomes the section's outgoing afterimage at the audio release."
      },
      "branching_contract" => {
        "branch_count_reason" => id == "C01" ? "The event needs both agency and spatial-consequence screens to be understood." : "The persistent condition has one distinct screen job.",
        "directorial_expansion_logic" => id == "C01" ? "Move from member contact to an overhead revelation of the same guide response." : "Hold on the object-only consequence without repeating the prior event.",
        "distinct_screen_information_rule" => "every_branch_cut_adds_observable_screen_information_or_a_distinct_directorial_job_start_end_labels_or_shot_size_lens_angle_or_beauty_changes_alone_do_not_qualify",
        "event_ownership_rule" => "every_branch_cut_derives_from_and_preserves_the_parent_core_event_without_stealing_a_later_or_unrelated_event",
        "split_to_new_core_cut_rule" => "a_new_governing_event_action_effect_condition_or_dramatic_beat_requires_a_new_core_cut"
      },
      "compile_seed" => {"branch_cuts" => branch_cuts},
      "risks" => []
    }
  end

  def branch_cut(id:, packet_id:, sequence_number:, role:, visible_members:, member:, sequence:, contribution:, time_relation:, visible_action:, composition:, camera:, shot_scale:, required_visibility:, action_cue:, continuity_in:, continuity_out:, storyline_projection:, storyline_expansion_delta:)
    member_visible = visible_members.any?
    bindings = []
    if member_visible
      bindings << visual_binding(
        binding_id: "VRB_MEMBER_M01",
        asset_id: "VIS-M01",
        owner: "front_planning_album_visual_asset",
        entry: member,
        scope: "member_visual",
        klass: "current_title_member_visual",
        order: 1
      )
    end
    bindings << visual_binding(
      binding_id: "VRB_SCENE_SEQ",
      asset_id: "REF-01",
      owner: "front_planning_sequence_scene_reference",
      entry: sequence,
      scope: "scene_visual",
      klass: "founder_sequence_subreference",
      order: bindings.length + 1
    )

    {
      "branch_cut_id" => id,
      "packet_id" => packet_id,
      "branch_role" => role,
      "branch_sequence" => sequence_number,
      "core_event_derivation" => "This screen reveals a distinct part of the parent Core Cut's calibration event without introducing another governing event.",
      "distinct_screen_contribution" => contribution,
      "branch_time_relation" => time_relation,
      "visible_action" => visible_action,
      "composition_lock" => composition,
      "camera_treatment" => "Locked still-camera view with no temporal movement.",
      "still_camera_spec" => {
        "contract_version" => "still_camera_direction.v3"
      }.merge(camera).merge(
        "lens_feel" => "natural perspective with undistorted proportions",
        "motion_camera_ownership" => "03V_after_passed_image_pixel_inspection"
      ),
      "shot_scale" => shot_scale,
      "space_or_object" => "Synthetic calibration field and alignment marker.",
      "required_visibility" => required_visibility,
      "render_facing_action_cue" => action_cue,
      "continuity_in" => continuity_in,
      "continuity_out" => continuity_out,
      "visible_member_focus" => visible_members,
      "member_visual_compile_input" => {
        "member_visual_applicability" => member_visible ? "meaningfully_visible" : "not_visible",
        "member_visual_reference_policy" => member_visible ? "required" : "prohibited",
        "selected_album_member_visual_asset_ids" => member_visible ? ["VIS-M01"] : [],
        "selection_reason" => member_visible ? "M01 is meaningfully visible from behind; preserve current-title appearance without forcing face readability." : "No member is visible in this spatial or object-only Branch Cut.",
        "framing_class" => member_visible ? "back-view medium-wide" : "object-or-space-only view",
        "head_orientation" => member_visible ? "turned away and unreadable" : "not applicable",
        "occlusion" => member_visible ? "face fully hidden by rear orientation" : "no member present",
        "package_album_key" => album_key,
        "package_title_key" => title_key,
        "visual_control_policy" => "current_title_member_visual_controls_appearance_hair_makeup_wardrobe_material_silhouette_and_body_continuity_only_branch_cut_controls_pose_head_gaze_action_still_camera_placement_crop_occlusion_and_proportions"
      },
      "visual_reference_bindings" => bindings,
      "storyline_alignment_binding" => storyboard_alignment_projection(
        storyline_projection.fetch("source_json_pointer").sub(
          %r{\A/founder_visual_alignment/planning_cut_readouts/(\d+)\z},
          '/section_directions/0/planning_cut_alignment_projections/\1/projected_value'
        ),
        storyline_projection
      ).merge(
        "planning_cut_id" => storyline_projection.fetch("planning_cut_id"),
        "source_key_screen_id" => storyline_projection.fetch("source_key_screen_id"),
        "02a_expansion_delta" => storyline_expansion_delta,
        "prompt_lineage_rule" => "02B_must_read_this_exact_storyline_value_and_hash_before_authoring_the_five_prompt_items"
      )
    }
  end

  def context_review_document(storyboard_sha)
    director_session_id = "fixture-continuing-director-session"
    section_record = write_yaml(
      run_dir.join("work", "review-execution", "02A-S01.yaml"),
      llm_review_execution_record(
        session_type: "codex_section_review",
        role_id: "idol-02a-section-context-reviewer",
        session_id: director_session_id,
        section_ids: ["S01"],
        storyboard_sha: storyboard_sha
      )
    )
    root_record = write_yaml(
      run_dir.join("work", "review-execution", "02A-whole-film.yaml"),
      llm_review_execution_record(
        session_type: "codex_root_reconciliation",
        role_id: "idol-02a-whole-film-reconciler",
        session_id: director_session_id,
        section_ids: ["S01"],
        storyboard_sha: storyboard_sha
      )
    )
    section_reviewer = {
      "profile" => "director_deep",
      "execution_scope" => "S01 active 02A context review.",
      "evidence_basis" => ["Passed Front Planning, 01, and exact 02A bytes."],
      "execution_receipt" => llm_review_execution_receipt(
        session_type: "codex_section_review",
        role_id: "idol-02a-section-context-reviewer",
        session_id: director_session_id,
        section_ids: ["S01"],
        storyboard_sha: storyboard_sha,
        record_path: section_record
      ),
      "canonical_semantic_write_performed" => false
    }
    whole_reviewer = {
      "profile" => "director_deep",
      "execution_scope" => "Whole-film reconciliation for S01.",
      "evidence_basis" => ["Passed S01 review and exact 02A bytes."],
      "execution_receipt" => llm_review_execution_receipt(
        session_type: "codex_root_reconciliation",
        role_id: "idol-02a-whole-film-reconciler",
        session_id: director_session_id,
        section_ids: ["S01"],
        storyboard_sha: storyboard_sha,
        record_path: root_record,
        root: true
      ),
      "canonical_semantic_write_performed" => false
    }
    document = {
      "schema_version" => "idol-02a-creative-context-review.v7",
      "content_id" => "ACTIVE_TITLE_TEST",
      "status" => "passed",
      "source_02a" => {
        "path" => relative(storyboard_path),
        "sha256" => storyboard_sha,
        "schema_version" => "3.0"
      },
      "review_policy" => {
        "creative_judgment_owner" => "llm_contextual_review",
        "machine_creative_judgment_forbidden" => true,
        "every_section_review_required" => true,
        "whole_film_review_required" => true
      },
      "route" => {
        "surface_owner" => "codex",
        "section_reviewer_profile" => "director_deep",
        "whole_film_reviewer_profile" => "director_deep",
        "ownership_note" => "One continuing director owns section and whole-film judgment."
      },
      "section_reviews" => [
        {
          "section_id" => "S01",
          "source_section_value_sha256" => Idol02AStoryboardContract.section_review_sha256(storyboard, "S01"),
          "review_lineage" => {"mode" => "current_source_review"},
          "source_core_cut_ids" => ["C01", "C02"],
          "reviewer" => section_reviewer,
          "verdict" => "pass",
          "review_summary" => "C01 keeps one alignment event while BC01_ACTION reveals agency and BC01_OVERHEAD reveals the guide response; C02 correctly becomes a new Core Cut because persistence is the next governing condition.",
          "core_import_immutability_review" => {
            "verdict" => "pass",
            "reviewed_core_cut_ids" => ["C01", "C02"],
            "one_image_per_core_verified" => true,
            "core_reference_binding_verified" => true,
            "02a_core_mutation_detected" => false,
            "review_summary" => "Both 01 Official Cores, their primary images, and exact reference bindings are byte-identical imports; 02A authors only Branch children."
          },
          "upstream_realization_review" => {
            "judgment_owner" => "llm_contextual_review",
            "reviewed_core_cut_ids" => ["C01", "C02"],
            "source_01_field_refs" => [
              "01#/section_directions/0/scene_expansions/0/branching_strategy",
              "01#/section_directions/0/scene_expansions/0/branching_opportunities"
            ],
            "core_cut_realization_verdict" => "pass",
            "script_substitution_detected" => false,
            "review_summary" => "02A preserves 01's alignment-event branch opportunities and separates the later persistent condition."
          },
          "core_branch_realization_review" => {
            "judgment_owner" => "llm_contextual_review",
            "reviewed_core_cut_ids" => ["C01", "C02"],
            "reviewed_branch_cut_ids" => ["BC01_ACTION", "BC01_OVERHEAD", "BC02_HOLD"],
            "core_event_fidelity_verdict" => "pass",
            "branch_distinctness_verdict" => "pass",
            "start_end_template_detected" => false,
            "event_theft_detected" => false,
            "review_summary" => "The contact and overhead response add different observable information about C01; BC02_HOLD belongs to the separate persistence event."
          },
          "storyline_realization_review" => {
            "judgment_owner" => "llm_contextual_review",
            "source_section_alignment_sha256" => value_sha(
              storyboard.dig("section_shards", 0, "section_alignment_projection", "projected_value")
            ),
            "source_planning_cut_alignment_hashes" => storyboard.dig(
              "section_shards", 0, "planning_cut_alignment_projections"
            ).map do |projection|
              {
                "planning_cut_id" => projection.fetch("planning_cut_id"),
                "source_key_screen_id" => projection.fetch("source_key_screen_id"),
                "value_sha256" => value_sha(projection.fetch("projected_value"))
              }
            end,
            "reviewed_branch_cut_ids" => ["BC01_ACTION", "BC01_OVERHEAD", "BC02_HOLD"],
            "detailed_storyline_preservation_verdict" => "pass",
            "branch_expansion_coherence_verdict" => "pass",
            "02b_prompt_readiness_verdict" => "pass",
            "review_summary" => "The hand-first contact Branch retains M01's rear three-quarter body, hand-directed gaze, waist-height lateral camera, soft skin-and-cloth reflection, and restrained response. The overhead Branch preserves the full registered geometry with M01 absent; the lateral persistence Branch extends that same consequence without inventing a second event."
          },
          "core_branch_event_ownership" => "C01 owns alignment and guide response; C02 owns the subsequent persistent condition.",
          "branching_variety_and_repetition" => "C01 varies subject carrier, viewpoint, and spatial information without repeating the same screen; C02 deliberately reduces to one object hold.",
          "strengths" => ["One parent event produces member-led and spatial-response screens without borrowing the next event."],
          "findings" => []
        }
      ],
      "whole_film_review" => {
        "section_ids" => ["S01"],
        "reviewer" => whole_reviewer,
        "verdict" => "pass",
        "review_summary" => "The compact film spine is preserved without portrait repetition.",
        "storyline_progression_review" => {
          "judgment_owner" => "llm_contextual_review",
          "source_whole_film_readout_sha256" => value_sha(
            storyboard.dig(
              "founder_visual_alignment_projection",
              "projected_value",
              "whole_film_readout"
            )
          ),
          "reviewed_section_ids" => ["S01"],
          "progressive_detail_verdict" => "pass",
          "review_summary" => "The whole-film calibration premise becomes a section-level causal action and then cut-level hand contact, overhead proof, and persistent afterimage without losing the reference-combination or camera progression."
        },
        "core_branch_rhythm_and_variety" => "A two-branch causal event resolves into one concise persistence Core Cut, creating density where information changes and restraint where it does not.",
        "strengths" => ["The message is shown through an observable world change."],
        "findings" => []
      },
      "founder_gate" => {
        "review_html_path" => relative(run_dir.join("review", "02A.html")),
        "decision" => "pass",
        "allowed_decisions" => ["pass", "hold", "reject"],
        "canonical_02a_write_performed" => false
      }
    }
    projection = {
      "schema_version" => document["schema_version"],
      "content_id" => document["content_id"],
      "source_02a" => document["source_02a"],
      "review_policy" => document["review_policy"],
      "route" => document["route"],
      "section_reviews" => document["section_reviews"],
      "whole_film_review" => document["whole_film_review"]
    }
    projection_sha = value_sha(projection)
    html = write_file(
      run_dir.join("review", "02A.html"),
      "<!doctype html><html data-idol-review-projection-sha256=\"#{projection_sha}\"><body>Fixture 02A review</body></html>\n"
    )
    document["founder_gate"]["review_html_path"] = html.fetch("path")
    document["founder_gate"]["review_html_sha256"] = html.fetch("sha256")
    document["founder_gate"]["review_projection_sha256"] = projection_sha
    document
  end

  def llm_review_execution_record(session_type:, role_id:, session_id:, section_ids:, storyboard_sha:)
    review_stage = session_type == "codex_section_review" ? "02a_section_context" : "02a_whole_film_reconciliation"
    {
      "schema_version" => "idol-llm-review-execution-record.v2",
      "producer" => "registered_codex_reviewer_runner",
      "surface_owner" => "codex",
      "session_type" => session_type,
      "role_id" => role_id,
      "session_id" => session_id,
      "profile" => "director_deep",
      "provider_profile_snapshot_ref" => "automation/harness-provider-profile-registry.yaml#/logical_profiles/director_deep/providers/codex/role_profiles/creative_development_director",
      "provider_capability_snapshot_sha256" => file_sha(ROOT.join("automation", "harness-provider-profile-registry.yaml")),
      "source_02a_sha256" => storyboard_sha,
      "review_stage" => review_stage,
      "assigned_section_ids" => section_ids,
      "completion_state" => "completed",
      "canonical_semantic_write_performed" => false
    }
  end

  def llm_review_execution_receipt(session_type:, role_id:, session_id:, section_ids:, storyboard_sha:, record_path:, root: false)
    receipt = {
      "session_type" => session_type,
      "role_id" => role_id,
      "session_id" => session_id,
      "assigned_section_ids" => section_ids,
      "source_02a_sha256" => storyboard_sha,
      "completed" => true,
      "execution_record" => {
        "path" => relative(record_path),
        "sha256" => file_sha(record_path),
        "producer" => "registered_codex_reviewer_runner"
      }
    }
    receipt["section_receipts_verified"] = true if root
    receipt
  end

  def delta_document(storyboard_sha, _member)
    packets = branch_rows.map do |core_cut, core_index, branch_cut, branch_index|
      context = same_section_context(core_index, branch_index)
      {
        "packet_id" => branch_cut.fetch("packet_id"),
        "mode" => "official_branch",
        "major_scene_id" => "MJ01",
        "derivative_route_id" => "DERIVATIVE_MAIN_MV",
        "production_scope_id" => "PS_ACTIVE_S01",
        "active_storyline_version_id" => "STORY_ACTIVE_V1",
        "screen_progression_node_id" => "SPN_#{branch_cut.fetch('branch_cut_id')}",
        "authoring_model_profile_id" => "fixture_assigned_model",
        "parent_core_cut_ref" => {
          "core_cut_id" => core_cut.fetch("core_cut_id"),
          "json_pointer" => "/master_storyboard/#{core_index}",
          "value_sha256" => value_sha(core_cut)
        },
        "branch_cut_ref" => {
          "branch_cut_id" => branch_cut.fetch("branch_cut_id"),
          "json_pointer" => "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}",
          "value_sha256" => value_sha(branch_cut)
        },
        "expected_output_path" => relative(run_dir.join("outputs", "#{branch_cut.fetch('packet_id')}.png")),
        "execution" => image_execution_contract(branch_cut),
        "five_line_components" => five_line_components(branch_cut),
        "rendered_five_lines" => rendered_five_lines(branch_cut),
        "attachments" => packet_attachments(branch_cut),
        "reference_role_plan" => reference_role_plan(
          packet_attachments(branch_cut),
          branch_cut.dig("member_visual_compile_input", "member_visual_applicability")
        ),
        "section_cohort_id" => "C1",
        "authoring_inspection_receipt" => active_authoring_inspection_receipt(branch_cut),
        "adoption_lineage" => {
          "adopted_from_packet_id" => nil,
          "same_image_bytes_reusable" => false,
          "canonical_promotion_inferred" => false
        },
        "direct_prompt_revision" => {
          "revision_id" => "02BPR_#{branch_cut.fetch('branch_cut_id')}",
          "authoring_owner" => "model_authored_02b",
          "authoring_reason" => "translate_the_exact_02a_branch_cut_and_bounded_context_into_natural_render_language_without_schema_dumping",
          "source_02a_branch_cut_lock_sha256" => value_sha(branch_cut),
          "same_section_context" => context,
          "storyline_authoring_binding" => storyline_authoring_binding(branch_cut),
          "authoring_inspection_receipt" => authoring_inspection_receipt(branch_cut),
          "preserved_lock_assertions" => {
            "parent_core_cut_timing_and_section_ownership" => true,
            "branch_cut_id_sequence_derivation_and_distinct_contribution" => true,
            "member_visual_input_set_and_order" => true,
            "visual_reference_binding_set_and_order" => true,
            "founder_visual_alignment_storyline" => true,
            "explicit_founder_locks" => true,
            "expected_output_path" => true
          },
          "prompt_blueprint" => prompt_blueprint(branch_cut)
        }
      }
    end
    {
      "schema_version" => "1.6",
      "compiler_profile" => "provider_neutral_one_cut_one_image_translation_v2_6",
      "compile_target" => "official_branch",
      "content_id" => "ACTIVE_TITLE_TEST",
      "source_02a" => {
        "path" => relative(storyboard_path),
        "artifact_sha256" => storyboard_sha,
        "schema_version" => "3.0"
      },
      "direct_compile_basis" => {
        "image_quality" => "highest_available",
        "default_render_prompt_mode" => "single_branch_cut_16_9",
        "default_render_size" => "maximum supported 16:9 dimensions",
        "generation_route" => "prompt_export_only",
        "review_order_policy" => "packet_sequence",
        "prompt_translation_policy" => "model_or_human_authored_natural_language_translation_from_02a_never_schema_dump_or_exact_prompt_copy",
        "member_visual_policy" => "current_title_package_only_select_smallest_branch_cut_relevant_subset_no_separate_face_input",
        "scene_reference_policy" => "preserve_02a_selected_sequence_or_scene_reference_action_staging_composition_still_camera_crop_and_order",
        "context_policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only"
      },
      "section_compile_scope" => {
        "mode" => "sequential_single_physical_section",
        "shard_id" => "SHARD_S01_ACTIVE",
        "section_cohort_id" => "C1",
        "primary_section_id" => "S01",
        "section_ids" => ["S01"],
        "core_cut_ids" => ["C01", "C02"],
        "output_kind" => "noncanonical_02b_section_shard",
        "canonical_merge_policy" => "lossless_ordered_merge_after_section_founder_review_pass"
      },
      "readiness_evidence" => {
        "storyboard_context_review" => {
          "path" => relative(context_review_path),
          "artifact_sha256" => file_sha(context_review_path)
        }
      },
      "run_execution_selection" => {
        "creative_role_provider" => "codex",
        "image_execution_request" => "openai_api_gpt_image_2",
        "image_execution_request_origin" => "founder_explicit",
        "image_execution_session_provider" => "codex",
        "image_execution_lane" => "openai_api_gpt_image_2",
        "video_execution_lane" => "grok_build_oauth_subscription",
        "automatic_fallback" => "none"
      },
      "output" => {
        "format" => "prompt_packets_v2_6",
        "status" => "draft",
        "coverage_status" => "partial",
        "open_questions" => []
      },
      "packets" => packets
    }
  end

  def image_execution_contract(branch_cut)
    provider_profile = ROOT.join("automation", "providers", "openai-image-profiles.yaml")
    provider_registry = ROOT.join("automation", "harness-provider-profile-registry.yaml")
    {
      "execution_adapter_id" => "openai_api_gpt_image_2",
      "provider" => "openai",
      "provider_model_or_tool" => "gpt-image-2",
      "selected_native_tool" => nil,
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => "openai_image_api_current",
      "provider_profile_sha256" => file_sha(provider_profile),
      "provider_capability_snapshot_sha256" => file_sha(provider_registry),
      "cli_or_api_version" => "fixture-v1",
      "founder_generation_authority_id" => nil,
      "prompt_rewrite_policy" => "forbidden",
      "automatic_fallback" => "none",
      "expected_output_path" => relative(run_dir.join("outputs", "#{branch_cut.fetch('packet_id')}.png")),
      "output_count" => 1
    }
  end

  def five_line_components(branch_cut)
    blueprint = prompt_blueprint(branch_cut)
    member_ids = branch_cut.fetch("visual_reference_bindings").each_with_object([]) do |binding, ids|
      ids << binding.fetch("asset_id") if binding.fetch("reference_scope") == "member_visual"
    end
    {
      "authoring_owner" => "human_or_assigned_model",
      "identity_reference_rule" => {
        "visible_identity" => blueprint.fetch("identity_reference_rule"),
        "current_title_visual_bindings" => member_ids,
        "identity_preservation_rule" => "Preserve only passed current-title appearance continuity; the governing scene reference owns pose, action, camera, placement, crop, and depth."
      },
      "scene_intent" => {
        "whole_film_component" => "Carry the calibration film from deliberate intervention into a persistent changed world.",
        "section_component" => "Make the S01 causal calibration response readable.",
        "major_scene_component" => "MJ01 accumulates contact, spatial response, and the registered afterimage.",
        "core_slot_or_core_component" => branch_cut.fetch("branch_role"),
        "branch_expansion_component" => blueprint.fetch("scene_intent")
      },
      "visible_details" => blueprint.fetch("visible_details"),
      "action_cue" => blueprint.fetch("action_cue"),
      "avoid" => blueprint.fetch("avoid")
    }
  end

  def rendered_five_lines(branch_cut)
    blueprint = prompt_blueprint(branch_cut)
    visible = blueprint.fetch("visible_details")
    camera = visible.fetch("still_camera_and_composition")
    visible_line = [
      "Background and space — #{visible.fetch('background_and_space')}",
      "Still camera and composition — camera height: #{camera.fetch('camera_height')}; shot scale/distance: #{camera.fetch('shot_scale_distance')}; direction/angle: #{camera.fetch('direction_angle')}; depth: #{camera.fetch('depth_design')}; subject placement: #{camera.fetch('subject_placement')}; crop/negative space: #{camera.fetch('crop_negative_space')}; lens feel: #{camera.fetch('lens_feel')}",
      "Lighting, color, and material — #{visible.fetch('lighting_color_material')}",
      "4K, high quality, high detail"
    ].join("; ")
    action = blueprint.fetch("action_cue")
    action_parts = [
      "Subject state or pose — #{action.fetch('subject_state_or_pose')}",
      "Visible action or hold — #{action.fetch('visible_action_or_hold')}"
    ]
    action_parts << "Object/environment response — #{action.fetch('object_environment_response')}" if action["object_environment_response"]
    lines = {
      "identity_reference_rule" => blueprint.fetch("identity_reference_rule"),
      "scene_intent" => blueprint.fetch("scene_intent"),
      "visible_details" => visible_line,
      "action_cue" => action_parts.join("; "),
      "avoid" => blueprint.fetch("avoid")
    }
    full_text = [
      "Identity reference rule: #{lines.fetch('identity_reference_rule')}",
      "Scene intent: #{lines.fetch('scene_intent')}",
      "Visible details: #{lines.fetch('visible_details')}",
      "Action cue: #{lines.fetch('action_cue')}",
      "Avoid: #{lines.fetch('avoid')}"
    ].join("\n")
    lines.merge(
      "full_prompt_text" => full_text,
      "full_prompt_sha256" => Digest::SHA256.hexdigest(full_text),
      "label_order" => ["Identity reference rule", "Scene intent", "Visible details", "Action cue", "Avoid"]
    )
  end

  def packet_attachments(branch_cut)
    branch_cut.fetch("visual_reference_bindings").map do |binding|
      {
        "order" => binding.fetch("order"),
        "role" => binding.fetch("reference_scope") == "member_visual" ? "current_title_member_visual" : "governing_scene_or_sequence_reference",
        "binding_id" => binding.fetch("binding_id"),
        "asset_id" => binding.fetch("asset_id"),
        "actual_path" => binding.fetch("actual_path"),
        "sha256" => binding.fetch("sha256"),
        "pixel_inspection_status" => "passed",
        "locked" => true
      }
    end
  end

  def reference_role_plan(attachments, applicability)
    member_ids = attachments.select { |row| row.fetch("role") == "current_title_member_visual" }.map { |row| row.fetch("binding_id") }
    scene_id = attachments.find { |row| row.fetch("role") != "current_title_member_visual" }.fetch("binding_id")
    world_lineage = reference_function_lineage(scene_id, "REF-01", "RFN_REF_01_WORLD", "video_selected_range")
    composition_lineage = reference_function_lineage(scene_id, "REF-01", "RFN_REF_01_CAMERA", "video_selected_range")
    motion_lineage = reference_function_lineage(scene_id, "REF-01", "RFN_REF_01_ACTION", "video_selected_range", sequence_unit: true)
    {
      "authoring_owner" => "human_or_assigned_model",
      "scene_character_compile_mode" => "separate",
      "performance_mode" => "none",
      "attachment_order_binding_ids" => attachments.map { |row| row.fetch("binding_id") },
      "logical_role_groups" => [
        {
          "logical_role" => "character_visual",
          "applicability" => applicability == "meaningfully_visible" ? "required" : "not_applicable_member_absent",
          "attachment_binding_ids" => member_ids
        },
        {
          "logical_role" => "scene_visual_package",
          "applicability" => "required",
          "attachment_binding_ids" => [scene_id],
          "world_look_binding_ids" => [scene_id],
          "composition_anchor_binding_id" => scene_id,
          "world_look_function_lineage" => [world_lineage],
          "composition_anchor_function_lineage" => composition_lineage
        },
        {
          "logical_role" => "motion_reference",
          "applicability" => "required",
          "attachment_binding_ids" => [scene_id],
          "sequence_unit_id" => "SEQU_REF_01",
          "source_locator" => "SEQU_REF_01 exact five frames at 00:00-00:04",
          "sampling_interval_seconds" => 1,
          "sample_count" => 5,
          "contiguous_event" => "The figure registers one marker and the aligned state remains visible.",
          "motion_function_lineage" => [motion_lineage]
        }
      ]
    }
  end

  def reference_function_lineage(attachment_binding_id, reference_unit_id, function_id, source_media_type, sequence_unit: false)
    front = YAML.safe_load(front_path.read, aliases: true)
    unit_index = front.dig("reference_connection_research", "reference_units").index do |row|
      row.fetch("reference_unit_id") == reference_unit_id
    end
    unit = front.dig("reference_connection_research", "reference_units", unit_index)
    function_index = unit.fetch("function_analysis").index do |row|
      row.fetch("function_id") == function_id
    end
    function = unit.fetch("function_analysis").fetch(function_index)
    unit_pointer = "/reference_connection_research/reference_units/#{unit_index}"
    row = {
      "attachment_binding_id" => attachment_binding_id,
      "reference_unit_id" => reference_unit_id,
      "function_id" => function_id,
      "purpose" => function.fetch("purpose"),
      "disposition" => unit.fetch("disposition"),
      "source_media_type" => source_media_type,
      "source_artifact" => {
        "path" => relative(front_path),
        "sha256" => file_sha(front_path),
        "schema_version" => front.fetch("schema_version")
      },
      "reference_unit_json_pointer" => unit_pointer,
      "reference_unit_value_sha256" => value_sha(unit),
      "function_json_pointer" => "#{unit_pointer}/function_analysis/#{function_index}",
      "function_value_sha256" => value_sha(function)
    }
    if sequence_unit
      row["sequence_unit_json_pointer"] = "#{unit_pointer}/sequence_unit"
      row["sequence_unit_value_sha256"] = value_sha(unit.fetch("sequence_unit"))
    end
    row
  end

  def active_authoring_inspection_receipt(branch_cut)
    bindings = branch_cut.fetch("visual_reference_bindings")
    {
      "inspection_owner" => "human_or_assigned_model",
      "source_cut_contract_sha256" => value_sha(branch_cut),
      "source_storyline_alignment_binding_sha256" => value_sha(branch_cut.fetch("storyline_alignment_binding")),
      "inspected_storyline_levels" => ["whole_film", "section", "major_scene", "planning_core_or_slot", "02a_branch_expansion"],
      "inspected_visual_reference_binding_ids" => bindings.map { |binding| binding.fetch("binding_id") },
      "inspected_current_title_asset_ids" => bindings.each_with_object([]) do |binding, ids|
        ids << binding.fetch("asset_id") if binding.fetch("reference_class").start_with?("current_title_")
      end,
      "authored_component_order" => ["identity_reference_rule", "scene_intent", "visible_details", "action_cue", "avoid"],
      "creative_fill_policy" => "human_or_assigned_model_only_scripts_exact_copy_and_fixed_labels_only",
      "storyline_inspection_note" => "Fixture author inspected the whole-film, Section, Major, Core, and Branch storyline levels before authoring.",
      "inspection_note" => "Fixture author inspected every locked current-title and scene-reference image in declared order."
    }
  end

  def prompt_blueprint(branch_cut)
    member_visible = branch_cut.fetch("visible_member_focus").any?
    member_visual_required =
      branch_cut.dig("member_visual_compile_input", "member_visual_reference_policy") == "required"
    spatial_response = branch_cut.fetch("branch_role") == "spatial response"
    camera = branch_cut.fetch("still_camera_spec")
    {
      "authoring_owner" => "model_authored_02b",
      "identity_reference_rule" => member_visual_required ?
        "Use the selected current-title member visual only for hair, wardrobe, material, silhouette, and body continuity; keep her face hidden and her rear orientation unchanged." :
        (member_visible ?
          "No current-title member visual is attached because this visible body fragment does not require appearance continuity." :
          "No member visual is attached because this object-or-space-only Branch Cut contains no visible member."),
      "scene_intent" => member_visible ?
        "Exercise a member-visible hand contact and a readable calibration state." :
        (spatial_response ? "Reveal the full guide response caused by the same alignment event." : "Hold on the registered marker so the persistent consequence remains readable."),
      "visible_details" => {
        "background_and_space" => member_visible ?
          "The passed current-title neutral calibration field surrounds a rear-view fixture figure, a center guide, and readable printed scale marks." :
          (spatial_response ? "The passed current-title calibration guide fills the frame with the complete response radius visible." : "The passed current-title calibration field holds the registered marker beside the printed guide."),
        "still_camera_and_composition" => {
          "camera_height" => camera.fetch("camera_height"),
          "shot_scale_distance" => camera.fetch("shot_scale_distance"),
          "direction_angle" => camera.fetch("direction_angle"),
          "depth_design" => camera.fetch("depth_design"),
          "subject_placement" => camera.fetch("subject_placement"),
          "crop_negative_space" => camera.fetch("crop_negative_space"),
          "lens_feel" => camera.fetch("lens_feel")
        },
        "lighting_color_material" => "Neutral even calibration light keeps the printed chart, marker edges, and current-title material surfaces clearly separated.",
        "render_quality" => "4K, high quality, high detail"
      },
      "action_cue" => {
        "subject_state_or_pose" => member_visible ?
          "M01 stays in a rear three-quarter stance with her shoulder still, face unreadable, and one hand extended to the guide." :
          "No person is present; the alignment marker is the sole foreground subject.",
        "visible_action_or_hold" => member_visible ?
          "The hand is visibly in contact with the alignment marker while the shoulder remains still." :
          (spatial_response ? "The guide lines visibly illuminate outward from the registered marker." : "The alignment marker visibly holds at the printed registration point."),
        "object_environment_response" => spatial_response ?
          "Concentric guide lines illuminate from the marker through the full printed response radius." :
          (member_visible ? "The center guide begins to illuminate at the contact point." : "The printed guide remains stable around the locked marker.")
      },
      "avoid" => member_visible ?
        "Avoid a readable face, frontal gaze, glamour portrait pose, distorted hands, or a changed reference crop." :
        "Avoid any person, portrait framing, duplicated marker, distorted guide marks, or a changed reference crop."
    }
  end

  def storyline_authoring_binding(branch_cut)
    storyline = branch_cut.fetch("storyline_alignment_binding")
    whole_readout = storyboard.dig(
      "founder_visual_alignment_projection",
      "projected_value",
      "whole_film_readout"
    )
    section_readout = storyboard.dig(
      "section_shards",
      0,
      "section_alignment_projection",
      "projected_value"
    )
    {
      "planning_cut_id" => storyline.fetch("planning_cut_id"),
      "source_key_screen_id" => storyline.fetch("source_key_screen_id"),
      "source_branch_storyline_binding_sha256" => value_sha(storyline),
      "whole_film_readout_sha256" => value_sha(whole_readout),
      "section_readout_sha256" => value_sha(section_readout),
      "planning_cut_readout_sha256" => value_sha(storyline.fetch("projected_value")),
      "02a_expansion_delta_sha256" => value_sha(storyline.fetch("02a_expansion_delta")),
      "component_consumption" => {
        "whole_film" => ["scene_intent", "avoid"],
        "section" => [
          "visible_details.background_and_space",
          "visible_details.lighting_color_material",
          "action_cue.subject_state_or_pose"
        ],
        "planning_cut" => [
          "visible_details.still_camera_and_composition",
          "action_cue.visible_action_or_hold"
        ],
        "02a_branch_expansion" => ["action_cue.object_environment_response"]
      },
      "coverage_rule" => "the_union_must_cover_every_storyline_sensitive_prompt_component_before_compile",
      "semantic_review_rule" => "mechanical_mapping_is_not_semantic_proof_the_recipient_director_must_read_the_storyline_and_prompt_then_accept_or_hold"
    }
  end

  def authoring_inspection_receipt(branch_cut)
    bindings = branch_cut.fetch("visual_reference_bindings")
    {
      "inspection_owner" => "model_authored_02b",
      "source_02a_branch_cut_sha256" => value_sha(branch_cut),
      "source_storyline_alignment_binding_sha256" => value_sha(
        branch_cut.fetch("storyline_alignment_binding")
      ),
      "inspected_storyline_levels" => [
        "whole_film",
        "section",
        "planning_cut",
        "02a_branch_expansion"
      ],
      "inspected_visual_reference_binding_ids" => bindings.map { |binding| binding.fetch("binding_id") },
      "inspected_current_title_asset_ids" => bindings.each_with_object([]) do |binding, ids|
        ids << binding.fetch("asset_id") if binding.fetch("reference_class").start_with?("current_title_")
      end,
      "authored_component_order" => [
        "identity_reference_rule",
        "scene_intent",
        "visible_details.background_and_space",
        "visible_details.still_camera_and_composition.camera_height",
        "visible_details.still_camera_and_composition.shot_scale_distance",
        "visible_details.still_camera_and_composition.direction_angle",
        "visible_details.still_camera_and_composition.depth_design",
        "visible_details.still_camera_and_composition.subject_placement",
        "visible_details.still_camera_and_composition.crop_negative_space",
        "visible_details.still_camera_and_composition.lens_feel",
        "visible_details.lighting_color_material",
        "action_cue.subject_state_or_pose",
        "action_cue.visible_action_or_hold",
        "action_cue.object_environment_response",
        "avoid"
      ],
      "creative_fill_policy" => "human_or_assigned_model_inspects_source_truth_and_authors_every_creative_component_scripts_may_only_validate_hash_and_serialize_fixed_labels",
      "storyline_inspection_note" => "Fixture author read the exact whole-film, section, planning-cut, and Branch-Cut expansion storyline values before writing the five prompt items.",
      "inspection_note" => "Fixture author inspected the exact Branch Cut and every bound current-title and scene visual before authoring all structured prompt components."
    }
  end

  def collected_storyboard_camera_angle_review(document)
    images = IdolStoryboardCollectedAngleContract.storyboard_production_images(document)
    distinct = IdolStoryboardCollectedAngleContract.distinct_images(images)
    pairs = distinct.combination(2).map do |left, right|
      {
        "left_cut_id" => left.fetch("cut_id"),
        "right_cut_id" => right.fetch("cut_id"),
        "left_image_sha256" => left.fetch("image_sha256").empty? ? nil : left.fetch("image_sha256"),
        "right_image_sha256" => right.fetch("image_sha256").empty? ? nil : right.fetch("image_sha256"),
        "same_image_exact_carry" => false,
        "left_geometry_projection_sha256" => left.fetch("geometry_projection_sha256"),
        "right_geometry_projection_sha256" => right.fetch("geometry_projection_sha256"),
        "shot_scale_not_used_as_angle_proof" => true,
        "contextual_visual_review" => "Full-storyboard visual comparison of #{left.fetch('cut_id')} and #{right.fetch('cut_id')}, including non-adjacent stills. Shot scale was not used as angle proof.",
        "declared_angle_difference_result" => "differs",
        "founder_exception" => nil
      }
    end
    {
      "contract_version" => IdolStoryboardCollectedAngleContract::CONTRACT_VERSION,
      "scope" => IdolStoryboardCollectedAngleContract::SCOPE,
      "automatic_creative_pass" => false,
      "generated_pixel_closure" => false,
      "distinct_images" => distinct.map do |image|
        {
          "cut_id" => image.fetch("cut_id"),
          "production_cut_type" => image.fetch("production_cut_type"),
          "image_sha256" => image.fetch("image_sha256").empty? ? nil : image.fetch("image_sha256"),
          "still_camera_binding" => image.fetch("still_camera_binding"),
          "geometry_projection_sha256" => image.fetch("geometry_projection_sha256")
        }
      end,
      "pairs" => pairs,
      "contextual_full_storyboard_read" => "Every Official Core primary and Branch still on this production storyboard was compared as one collection, including non-adjacent pairs. A 03V 1-3 packet is not the collection unit."
    }
  end

  def same_section_context(core_index, branch_index)
    core_cuts = storyboard.fetch("master_storyboard")
    core_cut = core_cuts.fetch(core_index)
    branch_cuts = core_cut.dig("compile_seed", "branch_cuts")
    branch_cut = branch_cuts.fetch(branch_index)
    {
      "policy" => "current_branch_plus_parent_core_immediate_branch_siblings_and_immediate_previous_and_next_core_cuts_in_same_section_only",
      "section_id" => "S01",
      "current_core_cut_id" => core_cut.fetch("core_cut_id"),
      "current_branch_cut_id" => branch_cut.fetch("branch_cut_id"),
      "previous_branch_cut" => branch_index.zero? ? nil : neighbor_branch_ref(branch_cuts.fetch(branch_index - 1), core_index, branch_index - 1),
      "next_branch_cut" => branch_index == branch_cuts.length - 1 ? nil : neighbor_branch_ref(branch_cuts.fetch(branch_index + 1), core_index, branch_index + 1),
      "previous_core_cut" => core_index.zero? ? nil : neighbor_core_ref(core_cuts.fetch(core_index - 1), core_index - 1),
      "next_core_cut" => core_index == core_cuts.length - 1 ? nil : neighbor_core_ref(core_cuts.fetch(core_index + 1), core_index + 1),
      "first_core_cut_boundary_rule" => "use_current_section_entry_continuity_when_previous_core_cut_is_null",
      "last_core_cut_boundary_rule" => "use_current_section_exit_continuity_when_next_core_cut_is_null",
      "context_value_sha256" => context_sha(core_index, branch_index)
    }
  end

  def neighbor_core_ref(core_cut, index)
    {
      "core_cut_id" => core_cut.fetch("core_cut_id"),
      "json_pointer" => "/master_storyboard/#{index}",
      "value_sha256" => value_sha(core_cut_context_projection(core_cut))
    }
  end

  def neighbor_branch_ref(branch_cut, core_index, branch_index)
    {
      "branch_cut_id" => branch_cut.fetch("branch_cut_id"),
      "json_pointer" => "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}",
      "value_sha256" => value_sha(branch_cut)
    }
  end

  def context_payload(core_position, branch_position)
    core_cuts = storyboard.fetch("master_storyboard")
    shard = storyboard.fetch("section_shards").first
    current_core_cut = core_cuts.fetch(core_position)
    branch_cut = current_core_cut.dig("compile_seed", "branch_cuts").fetch(branch_position)
    Idol02AStoryboardContract.same_section_context_payload(
      storyboard,
      shard,
      core_cuts,
      core_position,
      branch_cut,
      branch_position
    )
  end

  def core_cut_context_projection(core_cut)
    Idol02AStoryboardContract.core_cut_context_projection(core_cut)
  end
end

at_exit { ActiveMvFixture.cleanup_created_fixtures }
Minitest.after_run { ActiveMvFixture.cleanup_created_fixtures } if defined?(Minitest) && Minitest.respond_to?(:after_run)
