# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "active_audio_branch_cut_placement_fixture"

# One current-byte 01/02A/02B/Production-Cut source lineage is shared within
# each test process. Individual fixtures write only their own 03V authoring
# surfaces, so negative tests cannot mutate the canonical upstream bytes.
class Active03VFixture
  ROOT = ActiveMvFixture::ROOT
  MANIFEST_SOURCE_FIELDS = %w[
    production_cut_id production_cut_type parent_core_cut_id packet_id path sha256
    pixel_review_status source_production_cut_review source_02a_cut section_id
    major_scene_id active_storyline_version_id screen_progression_node_id
    scene_phase_context primary_audio_cue sequence_phase_binding_ids
    core_reference_binding_id screen_job_binding
  ].freeze

  attr_reader :source_fixture, :run_dir, :front_planning_path, :direction_path,
              :master_storyboard_path, :context_review_path, :prompt_packets_path,
              :review_path, :placement_path, :assist_path, :assist, :production_cuts

  class << self
    def create(branch_count: 3, board_groups: nil, include_official_core: false, collect_same_angle_core_and_action: false)
      new(
        branch_count: branch_count,
        board_groups: board_groups,
        include_official_core: include_official_core,
        collect_same_angle_core_and_action: collect_same_angle_core_and_action
      ).tap(&:build)
    end

    def shared_source_fixture
      @shared_source_fixture ||= ActiveAudioBranchCutPlacementFixture.create
    end

    def cleanup_shared_source_fixture
      @shared_source_fixture&.cleanup
      @shared_source_fixture = nil
    end
  end

  at_exit { cleanup_shared_source_fixture }

  def initialize(branch_count:, board_groups:, include_official_core:, collect_same_angle_core_and_action: false)
    raise ArgumentError, "branch_count must be between 1 and 4" unless branch_count.between?(1, 4)

    @branch_count = branch_count
    @board_groups = board_groups || [(0...branch_count).to_a]
    @include_official_core = include_official_core
    @collect_same_angle_core_and_action = collect_same_angle_core_and_action
    @fixture_id = format("%d-%x", Process.pid, object_id)
  end

  def cleanup
    # Shared upstream source bytes are removed once at process exit. The small
    # per-test 03V files remain inside that same temporary run until then.
    nil
  end

  def build
    @source_fixture = self.class.shared_source_fixture
    @run_dir = source_fixture.run_dir
    mv = source_fixture.image_fixture.mv
    @front_planning_path = mv.front_path
    @direction_path = mv.direction_path
    @master_storyboard_path = mv.storyboard_path
    @context_review_path = mv.context_review_path
    @prompt_packets_path = source_fixture.image_fixture.source_02b_path
    @review_path = source_fixture.production_review_path
    @placement_path = source_fixture.placement_path

    @front = load_yaml(front_planning_path)
    @direction = load_yaml(direction_path)
    @master = load_yaml(master_storyboard_path)
    @context_review = load_yaml(context_review_path)
    @review = load_yaml(review_path)
    @placement = load_yaml(placement_path)

    selected_rows = select_production_rows
    @production_cuts = selected_rows.map { |row| production_cut_image(row) }
    @assist = assist_document
    @assist_path = write_yaml(
      run_dir.join("work", "03v-fixtures", @fixture_id, "03V-storyboard-assist.yaml"),
      assist
    )
    self
  end

  def rewrite_assist
    @assist_path = write_yaml(assist_path, assist)
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def artifact_ref(path)
    {"path" => relative(path), "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def value_sha(value)
    source_fixture.image_fixture.mv.value_sha(value)
  end

  def video_manifest_document(tool: "image_to_video", resolution_pass: "480p_test")
    grok_profile_path = ROOT.join("automation", "providers", "grok-build-profiles.yaml")
    grok_profile_sha = Digest::SHA256.file(grok_profile_path).hexdigest
    cues = assist.fetch("boards").each_with_index.map do |board, index|
      successor = @review.fetch("section_cohort_successions").find do |row|
        row.fetch("section_ids").include?(board.fetch("section_id"))
      end
      section_cohort_id = successor.fetch("section_cohort_id")
      sources = board.fetch("source_production_cut_images").map do |image|
        review_row = @review.fetch("production_cut_reviews").find do |row|
          row.fetch("production_cut_id") == image.fetch("production_cut_id")
        end
        image.slice(*MANIFEST_SOURCE_FIELDS).merge("section_cohort_id" => review_row.fetch("section_cohort_id"))
      end
      prompt = [
        "@image1 fixes the reviewed Motion Storyboard route while the passed Production Cut originals preserve pixel truth.",
        "Begin from the inherited start view, move the token through only the declared states, use one readable camera route, and land on the final causal state for the edit handoff."
      ].join(" ")
      primary = sources.first
      additional_ids = tool == "reference_to_video" ? sources.drop(1).map { |source| source.fetch("production_cut_id") } : []
      founder_selection = if tool == "reference_to_video"
                            {
                              "selection_id" => "FOUNDER_RTV_001",
                              "selected_image_ids_in_order" => sources.map { |source| source.fetch("production_cut_id") },
                              "decision" => "selected_for_reference_to_video",
                              "founder_authored" => true
                            }
                          end
      review_480 = if resolution_pass == "720p_candidate"
                     receipt_path = run_dir.join("work", "03v-fixtures", @fixture_id, format("03VCUE_%02d-480p-review.yaml", index + 1))
                     write_yaml(receipt_path, {"decision" => "pass", "video_job_id" => format("VIDJOB_%02d", index + 1)})
                     {
                       "video_job_id" => format("VIDJOB_%02d", index + 1),
                       "resolution_pass" => "480p_test",
                       "requested_resolution" => "480p",
                       "observed_resolution" => "480p",
                       "decision" => "pass",
                       "reviewer_role" => "creative_development_director",
                       "playback_review_record_path" => relative(receipt_path),
                       "playback_review_record_sha256" => Digest::SHA256.file(receipt_path).hexdigest
                     }
                   end
      {
        "cue_id" => format("03VCUE_C01_%02d", index + 1),
        "active_storyline_version_id" => board.dig("active_storyline_binding", "active_version_id"),
        "screen_progression_map_id" => board.dig("screen_progression_binding", "screen_progression_map_id"),
        "screen_progression_node_id" => board.fetch("screen_progression_node_ids").first,
        "screen_progression_node_ids" => board.fetch("screen_progression_node_ids"),
        "section_id" => board.fetch("section_id"),
        "section_cohort_id" => section_cohort_id,
        "major_scene_id" => board.fetch("major_scene_id"),
        "core_cut_id" => board.fetch("core_cut_id"),
        "branch_cut_ids" => sources.select { |source| source["production_cut_type"] == "branch" }.map { |source| source["production_cut_id"] },
        "active_storyline_passage_pointer" => board.fetch("active_storyline_passage_pointer"),
        "active_storyline_binding" => deep_copy(board.fetch("active_storyline_binding")),
        "selected_sequence_composition_id" => board.fetch("selected_sequence_composition_id"),
        "selected_sequence_unit_ids" => board.fetch("selected_sequence_unit_ids"),
        "sequence_flow_reading_sha256" => board.fetch("sequence_flow_reading_sha256"),
        "selected_sequence_binding" => deep_copy(board.fetch("selected_sequence_binding")),
        "major_scene_binding" => deep_copy(board.fetch("major_scene_binding")),
        "screen_progression_binding" => deep_copy(board.fetch("screen_progression_binding")),
        "selected_core_reference_binding_id" => board.fetch("selected_core_reference_binding_ids").first,
        "selected_core_reference_binding_ids" => board.fetch("selected_core_reference_binding_ids"),
        "core_branch_screen_job" => sources.map { |source| source.dig("screen_job_binding", "value") }.join(" -> "),
        "motion_derivation_note" => board.fetch("motion_derivation_note"),
        "source_production_cut_images" => sources,
        "source_image_ids" => sources.map { |source| source.fetch("production_cut_id") },
        "source_pixel_hashes" => sources.map { |source| source.fetch("sha256") },
        "storyboard_id" => board.fetch("storyboard_id"),
        "inherited_start_view" => board.dig("prompt_handoff", "camera_motion_route", "start_view"),
        "subject_motion_route" => board.dig("prompt_handoff", "subject_motion_route"),
        "camera_motion_route" => board.dig("prompt_handoff", "camera_motion_route").reject { |key, _| key == "start_view" },
        "previous_next_continuity" => "Preserve token direction, current-title identity when visible, light, and the declared screen-progression edge.",
        "edit_handoff" => "Land on the final readable state and return playback to CDD before 04.",
        "prompt_text" => prompt,
        "prompt_rewrite_policy" => "forbidden",
        "grok_execution" => {
          "video_job_id" => format("VIDJOB_%02d", index + 1),
          "section_cohort_id" => section_cohort_id,
          "direct_image_to_video" => "forbidden",
          "source_stage" => "passed_03v",
          "source_production_cut_id" => primary.fetch("production_cut_id"),
          "source_production_cut_type" => primary.fetch("production_cut_type"),
          "source_image_path" => primary.fetch("path"),
          "source_image_sha256" => primary.fetch("sha256"),
          "source_image_frame_count" => 1,
          "source_image_review_status" => "passed_production_cut",
          "prompt_source" => "exact_03v_rendered_prompt",
          "prompt_rewrite_policy" => "forbidden",
          "prompt_sha256" => Digest::SHA256.hexdigest(prompt),
          "selected_tool" => tool,
          "additional_reference_image_ids" => additional_ids,
          "founder_reference_selection" => founder_selection,
          "requested_duration_seconds" => 6,
          "requested_aspect_ratio" => "16:9",
          "resolution_pass" => resolution_pass,
          "requested_resolution" => resolution_pass == "720p_candidate" ? "720p" : "480p",
          "selected_adapter_id" => "grok_build_video",
          "auth_lane" => "grok_build_oauth",
          "provider_profile_id" => "grok_worker_high",
          "provider_profile_sha256" => grok_profile_sha,
          "automatic_fallback" => "none",
          "founder_generation_authority_id" => nil,
          "source_480p_playback_review" => review_480
        }
      }
    end

    active = storyline_active_version
    screen_map = screen_progression_map
    {
      "schema_version" => "idol_video_prompt_manifest.v8",
      "content_id" => @master.fetch("content_id"),
      "status" => "ready_for_cdd_review",
      "run_root" => relative(run_dir),
      "source_front_planning" => artifact_ref(front_planning_path),
      "source_01_direction" => artifact_ref(direction_path),
      "source_master_storyboard" => artifact_ref(master_storyboard_path),
      "source_02a_context_review" => artifact_ref(context_review_path),
      "source_prompt_packets" => artifact_ref(prompt_packets_path),
      "source_production_cut_review" => artifact_ref(review_path),
      "source_audio_branch_cut_placement" => artifact_ref(placement_path),
      "source_storyboard_assist" => artifact_ref(assist_path),
      "storyline_lineage_projection" => {
        "source_json_pointer" => "/storyline_lineage_projection/projected_value",
        "source_value_sha256" => value_sha(@master.dig("storyline_lineage_projection", "projected_value")),
        "projected_value" => deep_copy(@master.dig("storyline_lineage_projection", "projected_value"))
      },
      "screen_progression_projection" => {
        "source_json_pointer" => "/screen_progression_map_projection/projected_value",
        "source_value_sha256" => value_sha(screen_map),
        "projected_value" => deep_copy(screen_map)
      },
      "storyline_projection" => {
        "active_storyline_version_id" => active.fetch("version_id"),
        "active_storyline_full_text_sha256" => active.fetch("full_storyline_text_sha256"),
        "screen_progression_map_id" => screen_map.fetch("screen_progression_map_id")
      },
      "prompt_authoring_policy" => {
        "derivation_order" => "active_storyline_to_selected_sequence_to_core_reference_to_passed_core_or_branch_to_compact_motion_prompt",
        "passed_pixel_authority" => "identity_style_light_and_still_composition",
        "sequence_motion_analysis_role" => "selected_exact_advisory_input_only_reassessed_against_passed_pixels",
        "temporal_camera_owner" => "03V_after_passed_production_cut_review_and_audio_production_cut_placement",
        "edit_owner" => "04_after_passed_03V_playback",
        "compact_motion_prompt" => "start_view_subject_route_one_camera_route_depth_endpoint_continuity_edit_handoff",
        "prompt_rewrite_policy" => "forbidden",
        "default_execution_source" => "one_passed_production_cut_still_image_one_frame",
        "reference_execution_gate" => "founder_selected_exact_image_ids_and_order",
        "duration_seconds" => [6, 10],
        "resolutions" => ["480p", "720p"],
        "resolution_1080p" => "rejected",
        "direct_image_to_video" => "forbidden",
        "return_after_playback" => "creative_development_director"
      },
      "section_cohort_successions" => deep_copy(@review.fetch("section_cohort_successions")),
      "canonical_video_prompt_output_root" => relative(run_dir.join("generations", "video-prompts")),
      "section_shards" => [{
        "section_id" => "S01",
        "section_cohort_id" => @review.dig("section_cohort_successions", 0, "section_cohort_id"),
        "planning_cdd_lane_id" => @review.dig("section_cohort_successions", 0, "planning_cdd_lane_id"),
        "production_cdd_lane_id" => @review.dig("section_cohort_successions", 0, "production_cdd_lane_id"),
        "cohort_carry_policy" => @review.dig("section_cohort_successions", 0, "carry_policy"),
        "cue_ids" => cues.map { |cue| cue.fetch("cue_id") },
        "status" => "ready_for_cdd_review",
        "actual_pixels_checked" => true,
        "transition_in" => "Enter from the exact selected Sequence flow.",
        "transition_out" => "Return playback to CDD before 04.",
        "output_prompt_paths" => cues.map { |cue| relative(run_dir.join("generations", "video-prompts", "#{cue.fetch('cue_id')}.txt")) }
      }],
      "cues" => cues,
      "return_recipient_role" => "creative_development_director"
    }
  end

  private

  def load_yaml(path)
    YAML.safe_load(path.read, aliases: true)
  end

  def write_yaml(path, document)
    path.dirname.mkpath
    path.write(YAML.dump(document))
    path
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def select_production_rows
    rows = Array(@review.fetch("production_cut_reviews"))
    if @collect_same_angle_core_and_action
      return [
        rows.find { |row| row["production_cut_id"] == "C01" },
        rows.find { |row| row["production_cut_id"] == "BC01_ACTION" }
      ].compact
    end
    default_groups = [(0...@branch_count).to_a]
    if @include_official_core && @board_groups == default_groups && @branch_count >= 3
      wanted = %w[C01 BC01_OVERHEAD BC02_HOLD]
      return wanted.map { |id| rows.find { |row| row["production_cut_id"] == id } }.compact.first(@branch_count)
    end
    if !@include_official_core && @branch_count <= 2
      rows.select { |row| row["production_cut_type"] == "branch" && row["parent_core_cut_id"] == "C01" }.first(@branch_count)
    else
      rows.first(@branch_count)
    end
  end

  def production_cut_image(review_row)
    review_index = @review.fetch("production_cut_reviews").index(review_row)
    source_pointer = review_row.dig("source_02a_cut", "source_json_pointer")
    cut = resolve_pointer(@master, source_pointer)
    screen_job_field = review_row.fetch("production_cut_type") == "official_core" ? "required_screen_information" : "directorial_or_edit_job"
    screen_job = cut.fetch(screen_job_field)
    placement_row = Array(@placement.fetch("production_cut_units")).find do |row|
      row.fetch("production_cut_id") == review_row.fetch("production_cut_id")
    end
    raise "fixture placement unit missing for #{review_row.fetch('production_cut_id')}" if placement_row.nil?
    transport = placement_row.fetch("placement_image")
    {
      "production_cut_id" => review_row.fetch("production_cut_id"),
      "production_cut_type" => review_row.fetch("production_cut_type"),
      "parent_core_cut_id" => review_row.fetch("parent_core_cut_id"),
      "packet_id" => review_row["packet_id"],
      "path" => transport.fetch("path"),
      "sha256" => transport.fetch("sha256"),
      "pixel_review_status" => review_row.fetch("pixel_review_status"),
      "passed_pixel_review_ref" => "/production_cut_reviews/#{review_index}",
      "source_production_cut_review" => {
        "source_json_pointer" => "/production_cut_reviews/#{review_index}",
        "source_value_sha256" => value_sha(review_row)
      },
      "source_02a_cut" => deep_copy(review_row.fetch("source_02a_cut")),
      "section_id" => review_row.fetch("section_id"),
      "major_scene_id" => review_row.fetch("major_scene_id"),
      "active_storyline_version_id" => review_row.fetch("active_storyline_version_id"),
      "screen_progression_node_id" => review_row.fetch("screen_progression_node_id"),
      "scene_phase_context" => review_row.fetch("scene_phase_context"),
      "primary_audio_cue" => review_row.fetch("primary_audio_cue"),
      "sequence_phase_binding_ids" => review_row.fetch("sequence_phase_binding_ids"),
      "core_reference_binding_id" => review_row.fetch("core_reference_binding_id"),
      "screen_job_binding" => {
        "source_json_pointer" => "#{source_pointer}/#{screen_job_field}",
        "source_value_sha256" => value_sha(screen_job),
        "value" => screen_job
      },
      "visible_state" => review_row["observable_pixel_truth"] || review_row.fetch("review_note"),
      "unique_state_role" => "supporting_state"
    }
  end

  def resolve_pointer(document, pointer)
    pointer.to_s.split("/").drop(1).reduce(document) do |value, token|
      key = token.gsub("~1", "/").gsub("~0", "~")
      value.is_a?(Array) ? value.fetch(Integer(key, 10)) : value.fetch(key)
    end
  end

  def storyline_active_version
    @master.dig("storyline_lineage_projection", "projected_value", "active_version")
  end

  def screen_progression_map
    @master.dig("screen_progression_map_projection", "projected_value")
  end

  def major_scene_binding
    index = @front.fetch("major_scene_catalog").index { |row| row.fetch("major_scene_id") == "MJ01" }
    value = @front.fetch("major_scene_catalog").fetch(index)
    {
      "source_json_pointer" => "/major_scene_catalog/#{index}",
      "source_value_sha256" => value_sha(value),
      "major_scene_id" => value.fetch("major_scene_id")
    }
  end

  def selected_sequence_binding
    major_index = @front.fetch("major_scene_catalog").index { |row| row.fetch("major_scene_id") == "MJ01" }
    candidate_set = @front.dig("major_scene_catalog", major_index, "sequence_composition_candidate_set")
    selected_id = candidate_set.fetch("selected_sequence_composition_id")
    candidate_index = candidate_set.fetch("candidates").index { |row| row.fetch("sequence_composition_id") == selected_id }
    candidate = candidate_set.fetch("candidates").fetch(candidate_index)
    unit_ids = candidate.fetch("typed_sequence_unit_ids")
    unit_sources = unit_ids.map do |unit_id|
      ref_index = @front.dig("reference_connection_research", "reference_units").index do |row|
        row.dig("sequence_unit", "sequence_unit_id") == unit_id
      end
      unit = @front.dig("reference_connection_research", "reference_units", ref_index, "sequence_unit")
      {
        "sequence_unit_id" => unit_id,
        "source_json_pointer" => "/reference_connection_research/reference_units/#{ref_index}/sequence_unit",
        "source_value_sha256" => value_sha(unit),
        "flow_reading_sha256" => value_sha(unit.fetch("flow_reading"))
      }
    end
    {
      "selected_sequence_composition_id" => selected_id,
      "source_json_pointer" => "/major_scene_catalog/#{major_index}/sequence_composition_candidate_set/candidates/#{candidate_index}",
      "source_value_sha256" => value_sha(candidate),
      "sequence_flow_reading_sha256" => value_sha(candidate.fetch("flow_reading")),
      "sequence_unit_sources" => unit_sources,
      "sequence_motion_analysis_binding" => deep_copy(candidate.fetch("sequence_motion_analysis_binding"))
    }
  end

  def active_storyline_binding
    active = storyline_active_version
    {
      "source_json_pointer" => "/storyline_lineage_projection/projected_value/active_version",
      "source_value_sha256" => value_sha(active),
      "active_version_id" => active.fetch("version_id"),
      "active_full_text_sha256" => active.fetch("full_storyline_text_sha256")
    }
  end

  def screen_progression_binding(images)
    screen_map = screen_progression_map
    node_ids = images.map { |image| image.fetch("screen_progression_node_id") }.uniq
    node_sources = node_ids.map do |node_id|
      index = screen_map.fetch("nodes").index { |node| node.fetch("node_id") == node_id }
      node = screen_map.fetch("nodes").fetch(index)
      {
        "screen_progression_node_id" => node_id,
        "source_json_pointer" => "/screen_progression_map_projection/projected_value/nodes/#{index}",
        "source_value_sha256" => value_sha(node)
      }
    end
    {
      "screen_progression_map_id" => screen_map.fetch("screen_progression_map_id"),
      "source_json_pointer" => "/screen_progression_map_projection/projected_value",
      "source_value_sha256" => value_sha(screen_map),
      "node_sources" => node_sources
    }
  end

  def assist_document
    boards = @board_groups.each_with_index.map do |indices, board_index|
      images = indices.each_with_index.map do |source_index, local_index|
        source = deep_copy(production_cuts.fetch(source_index))
        source["board_order"] = local_index + 1
        source["attachment_slot"] = %w[@image2 @image3 @image4].fetch(local_index)
        source["unique_state_role"] = if local_index.zero?
                                         "start"
                                       elsif local_index == indices.length - 1
                                         "arrival"
                                       else
                                         "transition"
                                       end
        source
      end
      parent_ids = images.map { |image| image.fetch("parent_core_cut_id") }.uniq
      board_path = run_dir.join("work", "03v-fixtures", @fixture_id, "storyboards", format("board-%02d.png", board_index + 1))
      board_path.dirname.mkpath
      board_path.binwrite("motion storyboard #{board_index + 1}\n")
      board_id = format("03VSB_C01_%02d", board_index + 1)
      sequence = selected_sequence_binding
      active = active_storyline_binding
      screen = screen_progression_binding(images)
      {
        "storyboard_id" => board_id,
        "section_id" => images.first.fetch("section_id"),
        "major_scene_id" => images.first.fetch("major_scene_id"),
        "core_cut_id" => images.first.fetch("parent_core_cut_id"),
        "board_order" => board_index + 1,
        "active_storyline_passage_pointer" => "/storyline_lineage_projection/projected_value/active_version/full_storyline_text",
        "active_storyline_binding" => active,
        "selected_sequence_composition_id" => sequence.fetch("selected_sequence_composition_id"),
        "selected_sequence_unit_ids" => sequence.fetch("sequence_unit_sources").map { |row| row.fetch("sequence_unit_id") },
        "sequence_flow_reading_sha256" => sequence.fetch("sequence_flow_reading_sha256"),
        "selected_sequence_binding" => sequence,
        "major_scene_binding" => major_scene_binding,
        "screen_progression_node_ids" => screen.fetch("node_sources").map { |row| row.fetch("screen_progression_node_id") },
        "screen_progression_binding" => screen,
        "selected_core_reference_binding_ids" => images.map { |image| image.fetch("core_reference_binding_id") }.uniq,
        "relationship_mode" => parent_ids.length == 1 ? "same_parent_core" : "cross_core_transition",
        "cross_core_transition" => parent_ids.length == 1 ? nil : {
          "from_core_cut_id" => parent_ids.first,
          "to_core_cut_id" => parent_ids.last,
          "continuity_reason" => "The exact screen-progression edge carries the registered token state across the two Official Cores."
        },
        "source_production_cut_images" => images,
        "board_image" => {
          "path" => relative(board_path),
          "sha256" => Digest::SHA256.file(board_path).hexdigest,
          "attachment_slot" => "@image1",
          "panel_count" => images.length,
          "pixel_truth_policy" => "navigation_and_motion_map_only_ordered_production_cut_originals_remain_pixel_truth"
        },
        "one_image_board_reason" => images.length == 1 ? {
          "reason" => "One passed Production Cut is the sufficient start and landing anchor.",
          "temporal_route_sufficiency" => "The authored hold and stop trigger provide the temporal route without inventing another still state."
        } : nil,
        "previous_board_id" => board_index.zero? ? nil : format("03VSB_C01_%02d", board_index),
        "next_board_id" => board_index == @board_groups.length - 1 ? nil : format("03VSB_C01_%02d", board_index + 2),
        "audio_cue" => images.first.fetch("primary_audio_cue"),
        "motion_derivation_note" => "The exact storyline, selected Sequence flow, screen-progression nodes, and passed pixels require only these non-duplicate states.",
        "prompt_handoff" => prompt_handoff(images),
        "status" => "passed"
      }
    end
    {
      "schema_version" => "idol_video_prompt_storyboard_assist.v4",
      "content_id" => @master.fetch("content_id"),
      "status" => "passed",
      "run_root" => relative(run_dir),
      "source_front_planning" => artifact_ref(front_planning_path),
      "source_01_direction" => artifact_ref(direction_path),
      "source_master_storyboard" => artifact_ref(master_storyboard_path),
      "source_02a_context_review" => artifact_ref(context_review_path),
      "source_prompt_packets" => artifact_ref(prompt_packets_path),
      "source_production_cut_review" => artifact_ref(review_path),
      "source_audio_branch_cut_placement" => artifact_ref(placement_path),
      "activation" => {
        "mode" => "after_passed_production_cuts",
        "pixel_gate" => "every_source_image_is_hash_bound_and_passed_production_cut",
        "source_union" => "official_core_or_branch",
        "default_relationship" => "same_parent_core"
      },
      "storyboard_policy" => {
        "image_count" => "1_to_3_passed_production_cut_images",
        "same_parent_default" => "all_images_share_one_parent_core",
        "cross_core_rule" => "explicit_from_core_to_core_and_continuity_reason_required",
        "more_than_three_rule" => "split_into_ordered_linked_boards",
        "attachment_order" => "@image1_storyboard_then_@image2_@image3_optional_@image4_ordered_production_cut_originals",
        "composite_role" => "order_timing_blocking_subject_route_and_camera_motion_map_only",
        "original_role" => "exact_pixels_identity_style_light_still_composition_and_visible_state",
        "grid_guide_policy" => "if_present_non_visual_alignment_guide_never_render_in_video"
      },
      "output_root" => relative(run_dir.join("generations", "video-prompts")),
      "declared_board_count" => boards.length,
      "boards" => boards,
      "authority_boundary" => {
        "board_controls" => "authoring_and_review_evidence_for_order_timing_blocking_subject_route_and_camera_motion",
        "production_cut_originals_control" => "pixels_identity_style_light_still_composition_and_visible_states",
        "default_video_source" => "one_passed_production_cut_still_image_one_frame",
        "multi_reference_gate" => "founder_exact_image_ids_and_order_selection_required",
        "forbidden_changes" => "no_unpassed_pixels_no_unbound_state_no_identity_or_world_replacement_no_invented_choreography",
        "edit_owner" => "04_only_after_passed_03V_playback"
      },
      "return_recipient_role" => "creative_development_director",
      "validation_commands" => ["ruby scripts/validate_video_prompt_storyboard_assist.rb PATH"]
    }
  end

  def prompt_handoff(images)
    slots = ["@image1"] + images.map { |image| image.fetch("attachment_slot") }
    originals = images.map { |image| "#{image.fetch('attachment_slot')} preserves #{image.fetch('production_cut_id')} exact pixels." }.join(" ")
    {
      "attachment_order" => slots,
      "board_use" => "@image1_controls_order_timing_blocking_subject_route_and_camera_motion_map",
      "production_cut_original_use" => "@image2_to_@image4_control_exact_pixels_identity_style_light_still_composition_and_visible_states",
      "subject_motion_route" => "Advance the token through the ordered visible states while preserving current-title identity when visible and the selected calibration world.",
      "camera_motion_route" => {
        "start_view" => "Begin from the first passed Production Cut's exact angle and composition.",
        "movement_family" => images.length == 1 ? "locked_hold" : "track",
        "movement_direction" => images.length == 1 ? "No translation." : "Track left to right.",
        "speed" => "One deliberate readable pace.",
        "motion_envelope" => "Ease once and settle.",
        "depth_parallax_focus_change" => "Keep the member plane stable while the token separates from the corridor depth.",
        "stop_trigger" => "Stop when the final state is readable.",
        "landing_state_or_reveal" => "Land on the selected causal consequence.",
        "readability_reason" => "One motivated route connects only the passed states."
      },
      "prompt_text" => "@image1 supplies the motion map. #{originals}",
      "negative" => "Do not change identity, light, still composition, state order, or expose any alignment grid.",
      "prompt_rewrite_policy" => "forbidden"
    }
  end
end
