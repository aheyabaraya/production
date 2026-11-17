# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "active_image_generation_fixture"
require_relative "../../lib/idol_storyboard_collected_angle_contract"

class ActiveAudioBranchCutPlacementFixture
  ROOT = ActiveMvFixture::ROOT
  PYTHON = ROOT.join("scripts", "idol-video-python")
  UPSCALER = ROOT.join("scripts", "idol_local_image_upscale.py")
  PRODUCTION_REVIEW_PRODUCER = ROOT.join("scripts", "idol_prepare_production_cut_review.rb")

  attr_reader :image_fixture, :run_dir, :review_path, :production_review_path,
              :placement_path, :review, :production_review, :placement,
              :audio_path, :audio_motion_map_path

  def self.create
    fixture = new
    fixture.build
  rescue StandardError
    fixture&.cleanup
    raise
  end

  def cleanup
    image_fixture&.cleanup
  end

  def build
    @image_fixture = ActiveImageGenerationFixture.create
    @run_dir = image_fixture.mv.run_dir
    @audio_path = write_file(run_dir.join("audio", "selected.wav"), "selected audio fixture bytes\n")
    @audio_motion_map_path = image_fixture.mv.audio_motion_map_path
    @review = review_document
    @review_path = write_yaml(run_dir.join("review", "generated-branch-cut-review.yaml"), review)
    create_passed_upscales
    create_production_cut_review
    @placement = placement_document
    @placement_path = write_yaml(run_dir.join("03V-audio-branch-cut-placement.yaml"), placement)
    self
  end

  def rewrite_review(refresh_placement_hash: true)
    write_yaml(review_path, review)
    if refresh_placement_hash
      production_review["source_generated_branch_cut_review"] = artifact_ref(review_path)
      rewrite_production_review(refresh_placement_hash: true)
    end
  end

  def rewrite_production_review(refresh_placement_hash: true)
    write_yaml(production_review_path, production_review)
    if refresh_placement_hash
      placement["source_production_cut_review"] = artifact_ref(production_review_path)
      rewrite_placement
    end
  end

  def refresh_production_review
    create_production_cut_review
    placement["source_production_cut_review"] = artifact_ref(production_review_path)
    rewrite_placement
  end

  def rewrite_placement
    write_yaml(placement_path, placement)
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(ROOT).to_s
  end

  def artifact_ref(path)
    {
      "path" => relative(path),
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  private

  def content_id
    image_fixture.source_02b.fetch("content_id")
  end

  def write_file(path, content)
    path.dirname.mkpath
    path.binwrite(content)
    path
  end

  def write_yaml(path, document)
    path.dirname.mkpath
    path.write(YAML.dump(document))
    path
  end

  def branch_cut_rows
    @branch_cut_rows ||= image_fixture.source_02b.fetch("prompt_packets").each_with_index.map do |packet, index|
      image_path = run_dir.join(
        "generations",
        "image",
        "passed",
        format("%02d-%s.png", index + 1, packet.fetch("packet_id"))
      )
      write_fixture_png(image_path, index)
      {
        "packet" => packet,
        "image_path" => image_path,
        "observable_pixel_truth" => [
          "Passed Branch Cut #{index + 1} shows the exact planned token state in the current-title corridor.",
          "The member remains rear-facing when present, the face is unreadable, and the still-camera",
          "height, crop, lateral direction, foreground rail, and corridor depth remain visible."
        ].join(" ")
      }
    end
  end

  def write_fixture_png(path, index)
    path.dirname.mkpath
    code = <<~PYTHON
      from PIL import Image
      import sys
      index = int(sys.argv[2])
      Image.new("RGB", (192, 108), (32 + index * 24, 64 + index * 16, 96 + index * 8)).save(sys.argv[1], format="PNG")
    PYTHON
    stdout, stderr, status = Open3.capture3(PYTHON.to_s, "-c", code, path.to_s, index.to_s, chdir: ROOT.to_s)
    raise "fixture PNG creation failed: #{stderr}\n#{stdout}" unless status.success?
    path
  end

  def create_passed_upscales
    stdout, stderr, status = Open3.capture3(
      PYTHON.to_s,
      UPSCALER.to_s,
      "passed-review",
      "--root",
      ROOT.to_s,
      "--review",
      review_path.to_s,
      chdir: ROOT.to_s
    )
    raise "fixture local upscale failed: #{stderr}\n#{stdout}" unless status.success?
  end

  def create_production_cut_review
    @production_review_path = run_dir.join("03-production-cut-review.yaml")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      PRODUCTION_REVIEW_PRODUCER.to_s,
      run_dir.to_s,
      "--root",
      ROOT.to_s,
      "--master-storyboard",
      image_fixture.mv.storyboard_path.to_s,
      "--generated-branch-cut-review",
      review_path.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    raise "fixture Production Cut review failed: #{stderr}\n#{stdout}" unless status.success?

    @production_review = YAML.safe_load(production_review_path.read, aliases: true)
  end

  def upscaled_ref(review_row)
    source = ROOT.join(review_row.fetch("image_path"))
    receipt = JSON.parse(Pathname.new("#{source}.upscale.json").read)
    receipt.fetch("operations").first.fetch("output").slice("path", "sha256")
  end

  def upscale_receipt_ref(review_row)
    source = ROOT.join(review_row.fetch("image_path"))
    artifact_ref(Pathname.new("#{source}.upscale.json"))
  end

  def review_document
    packets = branch_cut_rows.map { |row| row.fetch("packet") }
    {
      "schema_version" => "idol_generated_branch_cut_review.v4",
      "content_id" => content_id,
      "status" => "passed",
      "source_02a" => artifact_ref(image_fixture.mv.storyboard_path),
      "source_02b" => artifact_ref(image_fixture.source_02b_path),
      "section_reviews" => [
        {
          "section_id" => "S01",
          "source_section_packet_set_sha256" => image_fixture.mv.value_sha(packets),
          "review_lineage" => {"mode" => "current_source_review"},
          "packet_ids" => packets.map { |packet| packet.fetch("packet_id") },
          "decision" => "pass",
          "continuity_observation" => "The token direction, current-title appearance, corridor axis, and still-camera depth remain continuous.",
          "repetition_observation" => "The overhead response and consequence hold add different observable information instead of repeating the member-contact Branch Cut. Full-storyboard camera-angle pixel review covers Official Core primaries and every generated Branch still, including non-adjacent pairs.",
          "collected_image_camera_angle_pixel_review" => collected_pixel_camera_angle_review,
          "note" => "Active fixture pass."
        }
      ],
      "branch_cut_reviews" => branch_cut_rows.map do |row|
        packet = row.fetch("packet")
        {
          "packet_id" => packet.fetch("packet_id"),
          "source_02b_branch_cut_packet_value_sha256" => image_fixture.mv.value_sha(packet),
          "review_lineage" => {"mode" => "current_source_review"},
          "branch_cut_id" => packet.fetch("branch_cut_id"),
          "section_id" => packet.fetch("execution_section_id"),
          "core_cut_id" => packet.fetch("core_cut_id"),
          "image_path" => relative(row.fetch("image_path")),
          "image_sha256" => Digest::SHA256.file(row.fetch("image_path")).hexdigest,
          "pixel_dimensions" => {"width" => 192, "height" => 108},
          "observable_pixel_truth" => row.fetch("observable_pixel_truth"),
          "core_event_fidelity_result" => "The image remains a derived realization of the exact parent Core-Cut calibration event.",
          "distinct_screen_contribution_result" => packet.dig("branch_cut_lock", "distinct_screen_contribution"),
          "member_visual_result" => "Current-title member appearance is preserved only where the member is visible.",
          "scene_reference_result" => "The applied object action and lateral corridor grammar remain readable.",
          "still_camera_result" => "The frame preserves the planned still height, distance, direction, crop, and depth.",
          "body_and_object_integrity" => "No malformed body or object geometry is present in the fixture record.",
          "decision" => "pass",
          "review_note" => "Founder-pass fixture."
        }
      end,
      "review_surface" => {
        "html_contract_version" => "idol-html-review-board.v12",
        "hierarchy" => "target_and_message_then_whole_film_and_section_flow_then_sections_then_core_cuts_then_branch_cuts",
        "decision_values" => ["PASS", "HOLD", "REJECT"]
      },
      "automation_boundaries" => {
        "audio_branch_cut_placement_may_start_after_pass" => true,
        "paid_video_generation_approved" => false,
        "external_video_execution_approved" => false,
        "playback_pass_implied" => false,
        "edit_readiness_implied" => false
      },
      "open_questions" => []
    }
  end

  def collected_pixel_camera_angle_review
    storyboard = YAML.safe_load(image_fixture.mv.storyboard_path.read, aliases: true)
    review = Marshal.load(Marshal.dump(storyboard.dig("camera_diversity_review", "collected_image_camera_angle_review")))
    sha_by_cut = branch_cut_rows.to_h do |row|
      [row.fetch("packet").fetch("branch_cut_id"), Digest::SHA256.file(row.fetch("image_path")).hexdigest]
    end
    Array(review["distinct_images"]).each do |image|
      next unless image["production_cut_type"] == "branch"

      image["image_sha256"] = sha_by_cut.fetch(image.fetch("cut_id"))
    end
    Array(review["pairs"]).each do |pair|
      %w[left right].each do |side|
        cut_id = pair.fetch("#{side}_cut_id")
        next unless sha_by_cut.key?(cut_id)

        pair["#{side}_image_sha256"] = sha_by_cut.fetch(cut_id)
      end
    end
    review["generated_pixel_closure"] = true
    review["incomplete_pixel_bindings"] = []
    review
  end

  def placement_document
    direction = YAML.safe_load(image_fixture.mv.direction_path.read, aliases: true)
    choreography_policy_by_section = Array(direction["section_directions"]).to_h do |section|
      [section.fetch("section_id"), section.fetch("choreography_presence_policy")]
    end
    branch_reviews_by_id = review.fetch("branch_cut_reviews").to_h do |row|
      [row.fetch("branch_cut_id"), row]
    end
    units = production_review.fetch("production_cut_reviews").each_with_index.map do |review_row, index|
      branch_review = branch_reviews_by_id[review_row.fetch("production_cut_id")]
      passed_source = review_row.slice("path", "sha256")
      placement_image = branch_review ? upscaled_ref(branch_review) : passed_source
      {
        "placement_id" => format("APCP_%02d", index + 1),
        "production_cut_id" => review_row.fetch("production_cut_id"),
        "production_cut_type" => review_row.fetch("production_cut_type"),
        "parent_core_cut_id" => review_row.fetch("parent_core_cut_id"),
        "packet_id" => review_row.fetch("packet_id"),
        "section_id" => review_row.fetch("section_id"),
        "major_scene_id" => review_row.fetch("major_scene_id"),
        "active_storyline_version_id" => review_row.fetch("active_storyline_version_id"),
        "screen_progression_node_id" => review_row.fetch("screen_progression_node_id"),
        "scene_phase_context" => review_row.fetch("scene_phase_context"),
        "sequence_phase_binding_ids" => review_row.fetch("sequence_phase_binding_ids"),
        "core_reference_binding_id" => review_row.fetch("core_reference_binding_id"),
        "production_cut_order" => index + 1,
        "order_within_parent_core" => branch_review ? image_fixture.mv.storyboard.fetch("master_storyboard").flat_map { |core| core.dig("compile_seed", "branch_cuts") }.find { |branch| branch.fetch("branch_cut_id") == review_row.fetch("production_cut_id") }.fetch("branch_sequence") : 0,
        "start_seconds" => index.to_f,
        "end_seconds" => (index + 1).to_f,
        "passed_source_image" => passed_source,
        "placement_image" => placement_image,
        "placement_image_role" => branch_review ? "validated_local_upscale" : "original_passed_pixels",
        "local_upscale_receipt" => branch_review ? upscale_receipt_ref(branch_review) : nil,
        "primary_audio_cue" => review_row.fetch("primary_audio_cue"),
        "actual_visible_state" => review_row["observable_pixel_truth"] || review_row.fetch("review_note"),
        "subject_or_object_transition_need" => "Advance the token into the next passed state without changing member appearance or still-frame geometry.",
        "previous_next_continuity_need" => "Preserve token direction, current-title appearance, corridor axis, crop, light, and depth.",
        "choreography_presence_policy" => choreography_policy_by_section.fetch(review_row.fetch("section_id")),
        "camera_motion_unassigned" => true,
        "future_edit_marker_basis" => "The audible percussion aligns with the visible token-state change."
      }
    end
    {
      "schema_version" => "idol_audio_production_cut_placement.v5",
      "content_id" => content_id,
      "status" => "ready_for_03v",
      "source_audio" => artifact_ref(audio_path),
      "source_audio_motion_map" => artifact_ref(audio_motion_map_path),
      "source_production_cut_review" => artifact_ref(production_review_path),
      "source_01_direction" => artifact_ref(image_fixture.mv.direction_path),
      "source_02a" => artifact_ref(image_fixture.mv.storyboard_path),
      "source_02b" => artifact_ref(image_fixture.source_02b_path),
      "coverage" => {
        "audio_start_seconds" => units.first.fetch("start_seconds"),
        "audio_end_seconds" => units.last.fetch("end_seconds"),
        "positive_gap_count" => 0,
        "overlap_count" => 0,
        "official_core_count" => units.count { |row| row["production_cut_type"] == "official_core" },
        "branch_count" => units.count { |row| row["production_cut_type"] == "branch" },
        "production_cut_count" => units.length,
        "production_cut_ids" => units.map { |row| row.fetch("production_cut_id") },
        "coverage_note" => "Typed Official Core and Branch Production Cuts cover the selected interval without gaps or overlaps."
      },
      "production_cut_units" => units,
      "camera_motion_ownership" => "unassigned_here_03V_authors_temporal_camera_after_inspecting_actual_passed_pixels",
      "automation_boundaries" => {
        "passed_images_remain_pixel_authority" => true,
        "local_upscale_is_transport_derivative_only" => true,
        "storyboard_board_not_created" => true,
        "camera_motion_authored" => false,
        "paid_video_generation_approved" => false,
        "external_video_execution_approved" => false,
        "playback_pass_implied" => false,
        "edit_readiness_implied" => false
      }
    }
  end
end
