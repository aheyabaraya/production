# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "active_mv_fixture"

class ActiveReviewBoardFixture
  CYCLE_KIND_MODE = {
    "g00_direction_draft" => "g00_direction_draft",
    "g10_song_lock" => "g10_song_lock",
    "g20_visual_identity_lock" => "g20_visual_identity_lock",
    "g30_fp_final" => "g30_fp_final",
    "g30_experiment_disposition" => "g30_experiment_disposition",
    "g40_core_branch_authorization" => "g40_core_branch_authorization",
    "g50_branch_results" => "g50_branch_results",
    "video_playback_internal" => "video_playback_internal",
    "g60_playback_edit" => "g60_playback_edit",
    "g70_release" => "g70_release"
  }.freeze

  attr_reader :mv, :manifest, :manifest_path, :output_path

  def self.create(mv: nil, returned_output_path: nil, cycle_kind: nil)
    new(mv: mv, returned_output_path: returned_output_path, cycle_kind: cycle_kind).tap(&:build)
  end

  def initialize(mv:, returned_output_path:, cycle_kind:)
    @mv = mv
    @owns_mv = mv.nil?
    @returned_output_path = returned_output_path
    @cycle_kind = cycle_kind
  end

  def cleanup
    mv&.cleanup if @owns_mv
  end

  def build
    @mv ||= ActiveMvFixture.create
    @output_path = mv.run_dir.join("review", "founder-workbench.html")
    @manifest_path = mv.run_dir.join("review", "manifests", "active-board.yaml")
    @manifest = manifest_document
    if @cycle_kind
      mode = CYCLE_KIND_MODE.fetch(@cycle_kind)
      @manifest.fetch("board")["review_mode"] = mode
      @manifest.fetch("sections").first["cycle_kind"] = @cycle_kind
      @manifest.fetch("sections").first["review_mode"] = mode
      stage_id = {
        "g20_visual_identity_lock" => "front_planning_integration",
        "g50_branch_results" => "generated_branch_cut_review",
        "video_playback_internal" => "video_motion_direction",
        "g60_playback_edit" => "edit_04",
        "g70_release" => "delivery_05"
      }.fetch(@cycle_kind, @manifest.dig("sections", 0, "stage_id"))
      @manifest.fetch("board")["stage_id"] = stage_id
      @manifest.fetch("sections").first["stage_id"] = stage_id
    end
    write_manifest
    self
  end

  def write_manifest
    refresh_decision_contract!
    manifest_path.dirname.mkpath
    manifest_path.write(YAML.dump(manifest))
  end

  def manifest_sha
    Digest::SHA256.file(manifest_path).hexdigest
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ActiveMvFixture::ROOT).to_s
  end

  def decision_export(decisions: nil)
    cycle = manifest.fetch("sections").first
    default_action = {
      "g00_direction_draft" => "attracted",
      "g30_fp_final" => "select_candidate",
      "g30_experiment_disposition" => "hold",
      "video_playback_internal" => "internal_pass"
    }.fetch(cycle.fetch("review_mode"), "pass")
    rows = cycle.fetch("cards").each_with_index.map do |card, index|
      target = card.fetch("review_target")
      action = cycle.fetch("review_mode") == "g30_fp_final" ? (index.zero? ? "select_candidate" : "hold") : default_action
      {
        "review_key" => "#{cycle.fetch('revision_id')}::#{card.fetch('card_id')}",
        "cycle_kind" => cycle.fetch("cycle_kind"),
        "review_mode" => cycle.fetch("review_mode"),
        "action" => action,
        "card_id" => card.fetch("card_id"),
        "section_id" => cycle["section_id"],
        "scope_mode" => cycle.fetch("scope_mode"),
        "affected_section_ids" => card.fetch("affected_section_ids"),
        "stage_id" => cycle.fetch("stage_id"),
        "revision_id" => cycle.fetch("revision_id"),
        "decision_scope" => card.fetch("decision_scope"),
        "revision_scope" => card.fetch("revision_scope"),
        "review_target_id" => target.fetch("target_id"),
        "review_target_level" => target.fetch("level"),
        "review_target_number" => target.fetch("display_number"),
        "planning_cut_id" => target["planning_cut_id"],
        "core_cut_id" => target["core_cut_id"],
        "branch_cut_id" => target["branch_cut_id"],
        "decision_owner" => card.fetch("decision_owner"),
        "decision_question" => card.fetch("decision_question"),
        "legal_actions" => card.fetch("legal_actions"),
        "affected_scope" => card.fetch("affected_scope"),
        "blocking_effect" => card.fetch("blocking_effect"),
        "decision_epoch" => card.fetch("decision_epoch"),
        "dispatch_id" => card.fetch("dispatch_id"),
        "returned_output" => card.fetch("returned_output"),
        "director_review" => card.fetch("director_review"),
        "founder_lineage" => card.fetch("founder_lineage"),
        "worker_evidence" => card.fetch("worker_evidence")
      }.tap do |row|
        row["note"] = "Keep this complete alternative available without selecting it." if action == "hold"
      end
    end
    rows = decisions.call(rows) if decisions
    {
      "schema_version" => "idol-html-review-board.decision-export.v12",
      "review_mode" => manifest.dig("board", "review_mode"),
      "board_id" => manifest.dig("board", "board_id"),
      "board_revision" => manifest.dig("board", "revision"),
      "manifest_path" => relative(manifest_path),
      "manifest_sha256" => manifest_sha,
      "decisions" => rows
    }
  end

  private

  def refresh_decision_contract!
    mode = manifest.fetch("board").fetch("review_mode")
    cycle_kind = manifest.fetch("sections").first.fetch("cycle_kind", mode)
    cycle_kind = mode unless CYCLE_KIND_MODE[cycle_kind] == mode
    owner = if cycle_kind == "video_playback_internal"
      {"role" => "creative_development_director", "surface" => "cdd_internal_checkpoint", "promotion_authority" => "cannot_promote"}
    else
      {"role" => "overall_director", "surface" => "overall_founder_conversation", "promotion_authority" => "overall_final_acceptance"}
    end
    legal = {
      "g00_direction_draft" => %w[attracted reject hold connect_these keep_only search_further direct_comment],
      "g30_fp_final" => %w[select_candidate hold reject direct_comment],
      "g30_experiment_disposition" => %w[reject_archive revise_experiment teaser_only teaser_first_full_mv_hold full_mv_development hold],
      "video_playback_internal" => %w[internal_pass internal_hold material_exception]
    }.fetch(mode, %w[pass hold reject])
    effect = {
      "g00_direction_draft" => "non_gating_signal_only",
      "g30_fp_final" => "only_explicitly_named_field_or_card_is_fixed",
      "g30_experiment_disposition" => "routes_derivative_scope_without_discarding_other_derivatives",
      "video_playback_internal" => "internal_playback_checkpoint_only"
    }.fetch(mode, "advances_or_holds_only_bound_scope")
    expected_options = case mode
      when "g00_direction_draft"
        [
          {"id" => "attracted", "label" => "ATTRACTED", "tone" => "pass"},
          {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
          {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
          {"id" => "connect_these", "label" => "CONNECT THESE", "tone" => "neutral"},
          {"id" => "keep_only", "label" => "KEEP ONLY", "tone" => "neutral"},
          {"id" => "search_further", "label" => "SEARCH FURTHER", "tone" => "revise"},
          {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
        ]
      when "g30_fp_final"
        [
          {"id" => "select_candidate", "label" => "SELECT COMPLETE ROUTE", "tone" => "pass"},
          {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
          {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
          {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
        ]
      when "g30_experiment_disposition"
        [
          {"id" => "reject_archive", "label" => "REJECT ARCHIVE", "tone" => "reject"},
          {"id" => "revise_experiment", "label" => "REVISE EXPERIMENT", "tone" => "revise"},
          {"id" => "teaser_only", "label" => "TEASER ONLY", "tone" => "pass"},
          {"id" => "teaser_first_full_mv_hold", "label" => "TEASER FIRST · FULL MV HOLD", "tone" => "hold"},
          {"id" => "full_mv_development", "label" => "FULL MV DEVELOPMENT", "tone" => "pass"},
          {"id" => "hold", "label" => "HOLD", "tone" => "hold"}
        ]
      when "video_playback_internal"
        [
          {"id" => "internal_pass", "label" => "CDD PLAYBACK PASS", "tone" => "pass"},
          {"id" => "internal_hold", "label" => "CDD PLAYBACK HOLD", "tone" => "hold"},
          {"id" => "material_exception", "label" => "MATERIAL EXCEPTION", "tone" => "revise"}
        ]
      else
        [
          {"id" => "pass", "label" => "PASS", "tone" => "pass"},
          {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
          {"id" => "reject", "label" => "REJECT", "tone" => "reject"}
        ]
      end
    known_option_sets = [
      %w[attracted reject hold connect_these keep_only search_further direct_comment],
      %w[select_candidate hold reject direct_comment],
      %w[reject_archive revise_experiment teaser_only teaser_first_full_mv_hold full_mv_development hold],
      %w[internal_pass internal_hold material_exception],
      %w[pass hold reject]
    ]
    current_option_ids = Array(manifest["decision_options"]).map { |row| row["id"] }
    manifest["decision_options"] = expected_options if known_option_sets.include?(current_option_ids)
    output = artifact_binding(@returned_output_path || mv.storyboard_path, "returned_output")
    lineage = {
      "founder_receipt" => artifact_binding(mv.storyboard_path, "founder_receipt"),
      "decision_export" => artifact_binding(mv.storyboard_path, "decision_export"),
      "decision_intake" => artifact_binding(mv.storyboard_path, "decision_intake")
    }
    manifest.fetch("sections").each do |cycle|
      cycle["cycle_kind"] = cycle_kind
      cycle["decision_owner"] = owner
      cycle["decision_question"] ||= cycle.fetch("summary")
      cycle["legal_actions"] = legal
      cycle["affected_scope"] = {
        "scope_mode" => cycle.fetch("scope_mode"),
        "stage_id" => cycle.fetch("stage_id"),
        "section_ids" => cycle.fetch("covered_section_ids"),
        "chunk_ids" => cycle.fetch("cards").map { |card| card.fetch("review_target").fetch("target_id") }.uniq,
        "target_ids" => cycle.fetch("cards").map { |card| card.fetch("review_target").fetch("target_id") }.uniq
      }
      cycle["blocking_effect"] = effect
      cycle["decision_epoch"] = "FOUNDER-EPOCH-ACTIVE"
      cycle["dispatch_id"] = "DISPATCH-#{cycle.fetch('cycle_id')}"
      cycle["returned_output"] = output
      cycle_attempt_id = "ATTEMPT-#{cycle.fetch('cycle_id')}"
      cycle["director_review"] = artifact_binding(mv.storyboard_path, "director_review").merge(
        "row" => "/director_review/reviewed_outputs/0 attempt_id=#{cycle_attempt_id}",
        "pointer" => "/director_review/reviewed_outputs/0"
      )
      cycle["worker_evidence"] = worker_evidence(cycle_attempt_id, "SESSION-#{cycle.fetch('cycle_id')}", 0)
      cycle["founder_lineage"] = lineage
      cycle.fetch("cards").each_with_index do |card, card_index|
        target = card.fetch("review_target")
        affected = card.fetch("affected_section_ids")
        refresh_storyline_readout!(card, mode, card_index)
        card["decision_question"] ||= card.fetch("review_question")
        card["decision_owner"] = owner
        card["legal_actions"] = legal
        card["affected_scope"] = {
          "scope_mode" => cycle.fetch("scope_mode"),
          "stage_id" => cycle.fetch("stage_id"),
          "section_ids" => affected,
          "chunk_ids" => [target.fetch("target_id")],
          "target_ids" => [target.fetch("target_id")]
        }
        card["blocking_effect"] = effect
        card["decision_epoch"] = cycle.fetch("decision_epoch")
        card["dispatch_id"] = "DISPATCH-#{card.fetch('card_id')}"
        card["returned_output"] = output
        attempt_id = "ATTEMPT-#{card.fetch('card_id')}"
        card["director_review"] = artifact_binding(mv.storyboard_path, "director_review").merge(
          "row" => "/director_review/reviewed_outputs/#{card_index} attempt_id=#{attempt_id}",
          "pointer" => "/director_review/reviewed_outputs/#{card_index}"
        )
        card["worker_evidence"] = worker_evidence(attempt_id, "SESSION-#{card.fetch('card_id')}", card_index)
        card["founder_lineage"] = lineage
      end
    end
  end

  def refresh_storyline_readout!(card, mode, card_index)
    pointer, alignment_level, depth = case mode
                                      when "g00_direction_draft"
                                        [
                                          "/founder_visual_alignment_projection/projected_value/whole_film_readout",
                                          "whole_film",
                                          "whole_film"
                                        ]
                                      when "g30_fp_final"
                                        if card_index.zero?
                                          [
                                            "/founder_visual_alignment_projection/projected_value/whole_film_readout",
                                            "whole_film",
                                            "whole_film_and_sections"
                                          ]
                                        else
                                          [
                                            "/founder_visual_alignment_projection/projected_value/section_readouts/0",
                                            "section",
                                            "whole_film_and_sections"
                                          ]
                                        end
                                      when "g10_song_lock"
                                        readout = card.fetch("storyline_readout")
                                        readout["progression_depth"] = "whole_film"
                                        return
                                      when "g20_visual_identity_lock", "g30_experiment_disposition"
                                        readout = card.fetch("storyline_readout")
                                        readout["progression_depth"] = "whole_film_and_sections"
                                        return
                                      when "g40_core_branch_authorization", "g50_branch_results", "video_playback_internal", "g60_playback_edit", "g70_release"
                                        readout = card.fetch("storyline_readout")
                                        readout["progression_depth"] = "whole_film_sections_and_cuts"
                                        return
                                      else
                                        raise "unsupported review mode #{mode}"
                                      end
    value = pointer_value(mv.storyboard, pointer)
    readout = card.fetch("storyline_readout")
    readout["alignment_level"] = alignment_level
    readout["progression_depth"] = depth
    readout["title"] = mode == "g00_direction_draft" ? "Exact whole-video storyline" : "Exact whole-video and section storyline"
    readout["source_field_ref"] = {"source_id" => "storyboard", "pointer" => pointer}
    readout["source_value_sha256"] = mv.value_sha(value)
  end

  def artifact_binding(path, role)
    {"path" => relative(path), "sha256" => Digest::SHA256.file(path).hexdigest, "role" => role}
  end

  def worker_evidence(attempt_id, session_id, index)
    {
      "applicability" => "worker_return",
      "lineage_id" => "LINEAGE-#{attempt_id}",
      "attempt_id" => attempt_id,
      "session_id" => session_id,
      "director_dispatch_index" => artifact_binding(mv.storyboard_path, "director_dispatch_index").slice("path", "sha256").merge(
        "row" => "/director_dispatch_index/rows/#{index} attempt_id=#{attempt_id}",
        "pointer" => "/director_dispatch_index/rows/#{index}"
      )
    }
  end

  def manifest_document
    source_path = mv.storyboard_path
    document = {
      "schema_version" => "idol-html-review-board.v12",
      "run" => {
        "run_root" => relative(mv.run_dir),
        "content_id" => mv.run_dir.basename.to_s
      },
      "board" => {
        "board_id" => "ACTIVE-TITLE-REVIEW",
        "stage_id" => "storyboard_02a",
        "review_mode" => "g40_core_branch_authorization",
        "status" => "founder_review",
        "layout_profile" => "founder-production-workbench-v12",
        "legacy_cycle_aliases" => {
          "discovery" => "g00_direction_draft",
          "direction_synthesis" => "g30_fp_final",
          "fp_final" => "g40_core_branch_authorization"
        },
        "revision" => 1,
        "projection_profile" => "founder-workbench-continuity-v1",
        "projection_revision" => 1,
        "last_reviewed_revision" => 0,
        "active_cycle_id" => "CYCLE-ACTIVE-001",
        "storage_scope" => "stable_board_lineage",
        "output_policy" => "replace_generated_projection_same_path",
        "density" => "compact",
        "title" => "Active Title Founder Review",
        "eyebrow" => "MV DIRECTOR WORKBENCH",
        "purpose" => "Review the complete video from target and message through exact Branch-Cut screen truth.",
        "review_question" => "Does each local image preserve the section job without weakening the whole-video message?",
        "target_summary" => mv.storyboard.dig("target_message_summary", "primary_target"),
        "message_summary" => mv.storyboard.dig("target_message_summary", "core_message"),
        "whole_film_flow_summary" => [
          mv.storyboard.dig("whole_film_spine", "opening_state"),
          mv.storyboard.dig("whole_film_spine", "progression"),
          mv.storyboard.dig("whole_film_spine", "turn"),
          mv.storyboard.dig("whole_film_spine", "resolution_or_afterimage")
        ].join(" → "),
        "section_flow_summary" => "S01: M01 redirects the token; the object-only cut proves the world changed.",
        "storyline_alignment_policy" => {
          "progression_rule" => "g00_through_g70_cumulative_exact_storyline_and_screen_progression_projection",
          "visual_mismatch_action" => "reinspect_exact_bound_pixels_with_founder_reconcile_the_smallest_storyline_owner_then_reproject_only_affected_descendants",
          "exact_source_projection" => true
        },
        "review_sequence" => [
          {
            "phase" => "post_02a",
            "order" => 1,
            "stage_id" => "storyboard_02a",
            "gate" => "read_only_projection"
          }
        ],
        "rollback_pair" => {
          "last_passed_manifest" => artifact_binding(source_path, "last_passed_manifest"),
          "last_passed_html" => artifact_binding(source_path, "last_passed_html")
        },
        "output_path" => relative(output_path)
      },
      "sources" => [
        {
          "source_id" => "storyboard",
          "path" => relative(source_path),
          "sha256" => Digest::SHA256.file(source_path).hexdigest,
          "role" => "Canonical active 02A screen truth."
        }
      ],
      "decision_options" => [
        {"id" => "pass", "label" => "PASS", "tone" => "pass"},
        {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
        {"id" => "reject", "label" => "REJECT", "tone" => "reject"}
      ],
      "sections" => [
        {
          "cycle_id" => "CYCLE-ACTIVE-001",
          "review_mode" => "g40_core_branch_authorization",
          "section_id" => "WHOLE_FILM",
          "scope_mode" => "whole_film",
          "covered_section_ids" => ["S01"],
          "stage_id" => "storyboard_02a",
          "revision_id" => "REV-ACTIVE-001",
          "status" => "founder_review",
          "open_by_default" => true,
          "label" => "Whole Video",
          "headline" => "Agency becomes visible through one causal change.",
          "summary" => "Review target, section function, Core-Cut causality, and generated Branch-Cut truth in order.",
          "cards" => [
            card(
              card_id: "CARD-WHOLE",
              title: "Whole-video message progression",
              direction: "Open on system control, show M01's intervention, then leave the changed token as the afterimage.",
              proof: "The member-led cause and object-only consequence carry different message roles.",
              question: "Does the full progression communicate agency without repeating one portrait?",
              decision_scope: "creative_selection",
              revision_scope: "whole_film",
              target: {
                "target_id" => "TARGET-WHOLE",
                "level" => "whole_film",
                "display_number" => "1",
                "label" => "Whole Video"
              },
              pointer: "/whole_film_spine",
              media_id: "MEDIA-WHOLE"
            ),
            card(
              card_id: "CARD-S01",
              title: "S01 causal section flow",
              direction: "M01 redirects the token and then disappears from the object-only proof cut.",
              proof: "C01 owns the action; C02 owns the changed world state.",
              question: "Does S01 show cause and consequence clearly?",
              decision_scope: "screen_truth",
              revision_scope: "section",
              target: {
                "target_id" => "TARGET-S01",
                "parent_target_id" => "TARGET-WHOLE",
                "level" => "section",
                "display_number" => "1.1",
                "label" => "Section S01",
                "section_id" => "S01"
              },
              pointer: "/section_shards/0",
              media_id: "MEDIA-S01"
            ),
            card(
              card_id: "CARD-C01",
              title: "C01 member action",
              direction: "Use a rear-view medium-wide frame so the hand contact, not a frontal face, owns attention.",
              proof: "The member visual controls appearance only; the cut controls pose, crop, and still-camera geometry.",
              question: "Does the core cut preserve the intended action and composition?",
              decision_scope: "screen_truth",
              revision_scope: "core_cut",
              target: {
                "target_id" => "TARGET-C01",
                "parent_target_id" => "TARGET-S01",
                "level" => "core_cut",
                "display_number" => "1.1.1",
                "label" => "Core Cut C01",
                "section_id" => "S01",
                "core_cut_id" => "C01"
              },
              pointer: "/master_storyboard/0",
              media_id: "MEDIA-C01"
            ),
            card(
              card_id: "CARD-BC01",
              title: "BC01 action realization",
              direction: "The gloved hand is in contact with the token while M01 remains turned away.",
              proof: "The frame exposes the hand, token, rear silhouette, and right-side route without requiring face readability.",
              question: "Does this Branch Cut reveal a distinct, executable view of the Core-Cut event?",
              decision_scope: "render_candidate",
              revision_scope: "branch_cut",
              target: {
                "target_id" => "TARGET-BC01",
                "parent_target_id" => "TARGET-C01",
                "level" => "branch_cut",
                "display_number" => "1.1.1.1",
                "label" => "Branch Cut BC01",
                "section_id" => "S01",
                "core_cut_id" => "C01",
                "branch_cut_id" => "BC01_ACTION"
              },
              pointer: "/master_storyboard/0/compile_seed/branch_cuts/0",
              media_id: "MEDIA-BC01"
            )
          ]
        }
      ],
      "review_assets" => []
    }
    document.fetch("sections").each do |cycle|
      cycle.fetch("cards").each_with_index do |review_card, index|
        review_card["screen_summary"] = review_card.fetch("screen_proof")
        review_card["review_phase"] = "post_02a"
        review_card["phase_state"] = "read_only"
        full_media = review_card.fetch("media").first
        binding_id = "BIND-#{full_media.fetch('asset_id')}"
        target = review_card.fetch("review_target")
        lane_role = full_media.fetch("role") == "member_visual" ? "member_identity" : "generated_output"
        state_binding = {
          "binding_id" => binding_id,
          "assignment_state" => "assigned",
          "target_id" => target.fetch("target_id"),
          "target_level" => target.fetch("level"),
          "source_stage" => lane_role == "member_identity" ? "front_planning" : "generated_branch_review",
          "declared_order" => index,
          "lane_role" => lane_role,
          "disposition" => "active_used",
          "review_state" => "reviewed_pass",
          "new_since_last_review" => true,
          "latest_binding_revision" => 1,
          "state_receipt" => artifact_binding(source_path, "asset_state_receipt")
        }
        state_binding["section_id"] = target["section_id"] if target["section_id"]
        state_binding["planning_cut_id"] = target["planning_cut_id"] if target["planning_cut_id"]
        state_binding["core_cut_id"] = target["core_cut_id"] if target["core_cut_id"]
        state_binding["branch_cut_id"] = target["branch_cut_id"] if target["branch_cut_id"]
        asset = document.fetch("review_assets").find do |candidate|
          candidate.fetch("canonical_path") == full_media.fetch("path") &&
            candidate.fetch("sha256") == full_media.fetch("sha256")
        end
        unless asset
          asset = {
            "asset_id" => full_media.fetch("asset_id"),
            "surface_locator" => full_media.fetch("surface_locator"),
            "canonical_path" => full_media.fetch("path"),
            "sha256" => full_media.fetch("sha256"),
            "alt" => full_media.fetch("alt"),
            "label" => full_media.fetch("label"),
            "media_kind" => full_media.fetch("media_type"),
            "original_owner" => "current_title_member_visual_owner",
            "role" => full_media.fetch("role"),
            "inspection_action" => full_media.fetch("inspection_action"),
            "display_lane" => full_media.fetch("display_lane"),
            "first_seen_board_revision" => 1,
            "supersedes_asset_id" => nil,
            "superseded_by_asset_id" => nil,
            "bindings" => []
          }
          document.fetch("review_assets") << asset
        end
        asset.fetch("bindings") << state_binding
        review_card["media"] = [{"asset_id" => asset.fetch("asset_id"), "binding_id" => binding_id}]
      end
    end
    document
  end

  def card(card_id:, title:, direction:, proof:, question:, decision_scope:, revision_scope:, target:, pointer:, media_id:)
    {
      "card_id" => card_id,
      "title" => title,
      "direction" => direction,
      "screen_proof" => proof,
      "storyline_readout" => storyline_readout(pointer, target),
      "review_question" => question,
      "decision_scope" => decision_scope,
      "revision_scope" => revision_scope,
      "affected_section_ids" => ["S01"],
      "review_target" => target,
      "source_field_refs" => [{"source_id" => "storyboard", "pointer" => pointer}],
      "media" => [media(media_id)]
    }
  end

  def storyline_readout(pointer, target)
    value = pointer_value(mv.storyboard, pointer)
    level = target.fetch("level")
    {
      "alignment_level" => {
        "whole_film" => "whole_film",
        "section" => "section",
        "planning_cut" => "planning_cut",
        "core_cut" => "core_cut",
        "branch_cut" => "branch_cut"
      }.fetch(level),
      "progression_depth" => "whole_film_sections_and_cuts",
      "title" => "Exact #{target.fetch('label')} storyline",
      "source_field_ref" => {"source_id" => "storyboard", "pointer" => pointer},
      "source_value_sha256" => mv.value_sha(value),
      "visual_relationship" => "Read the exact source storyline beside the bound pixels; use the visual to test subject, action, camera, light, material, reference contribution, and continuity rather than replacing the text with a mood summary.",
      "exact_source_projection" => true,
      "visual_mismatch_action" => "reinspect_exact_bound_pixels_with_founder_reconcile_the_smallest_storyline_owner_then_reproject_only_affected_descendants",
      "mismatch_state" => "aligned"
    }
  end

  def pointer_value(document, pointer)
    pointer.split("/").drop(1).reduce(document) do |value, token|
      key = token.gsub("~1", "/").gsub("~0", "~")
      value.is_a?(Array) ? value.fetch(Integer(key, 10)) : value.fetch(key)
    end
  end

  def media(media_id)
    binding = mv.storyboard.dig("master_storyboard", 0, "compile_seed", "branch_cuts", 0, "visual_reference_bindings", 0)
    {
      "asset_id" => media_id,
      "surface_locator" => {
        "source_asset_id" => binding.fetch("asset_id"),
        "selected_cell_or_frame_id" => "BC01_ACTION",
        "surface_kind" => "generated_branch_cut"
      },
      "path" => binding.fetch("actual_path"),
      "sha256" => binding.fetch("sha256"),
      "alt" => "Current-title member visual used to inspect appearance continuity.",
      "label" => "BC01 appearance reference",
      "media_type" => "image",
      "role" => "member_visual",
      "display_lane" => "member_face",
      "inspection_action" => "pixel_review_generated_output"
    }
  end
end
