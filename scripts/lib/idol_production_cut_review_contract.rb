# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "idol_02a_storyboard_contract"

module IdolProductionCutReviewContract
  ACTIVE_SCHEMA_VERSION = "idol-production-cut-review.v2"
  CANONICAL_FILENAME = "03-production-cut-review.yaml"

  module_function

  def load_mapping(path)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
            end
    raise TypeError, "#{path} must contain an object" unless value.is_a?(Hash)

    value
  end

  def resolve_path(raw, root)
    path = Pathname.new(raw.to_s)
    path = root.join(path) unless path.absolute?
    path.expand_path.cleanpath
  end

  def inside?(path, root)
    relative = path.relative_path_from(root).to_s
    relative != ".." && !relative.start_with?("../")
  rescue ArgumentError
    false
  end

  def relative_path(path, root)
    path.expand_path.cleanpath.relative_path_from(root.expand_path.cleanpath).to_s
  end

  def artifact_ref(path, root)
    {
      "path" => relative_path(path, root),
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end

  def canonical_value(value)
    Idol02AStoryboardContract.canonical_value(value)
  end

  def value_sha256(value)
    Idol02AStoryboardContract.value_sha256(value)
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def build_document(run_path:, root:, storyboard:, direction:, prompt_packets:, branch_review:, source_refs:)
    errors = []
    errors << "source 01 direction must be active passed 3.0" unless direction["schema_version"].to_s == "3.0" && direction["status"].to_s == "passed"
    errors << "source 02A must be active passed 3.0" unless storyboard["schema_version"].to_s == "3.0" && storyboard["status"].to_s == "passed"
    errors << "source generated Branch-Cut review must be active passed v4" unless branch_review["schema_version"].to_s == "idol_generated_branch_cut_review.v4" && branch_review["status"].to_s == "passed"
    errors << "source 02B must be active approved 2.6" unless prompt_packets["schema_version"].to_s == "2.6" && prompt_packets["status"].to_s == "approved"

    content_ids = [direction["content_id"], storyboard["content_id"], prompt_packets["content_id"], branch_review["content_id"]].map(&:to_s)
    errors << "01, 02A, 02B, and generated Branch-Cut review content_id values differ" unless content_ids.uniq.length == 1 && !content_ids.first.to_s.empty?

    cohort_successions, section_cohort_by_id, packet_cohort_by_id = build_cohort_successions(prompt_packets, errors)

    g40 = storyboard["g40_core_branch_authorization"].to_h
    errors << "source 02A requires G-40 PASS" unless g40["decision"].to_s == "pass"
    errors << "G-40 derivative route differs from 02A" unless g40["derivative_route_id"].to_s == storyboard["derivative_route_id"].to_s
    errors << "G-40 production scope differs from 02A" unless g40["production_scope_id"].to_s == storyboard["production_scope_id"].to_s

    source_cores = Array(direction["official_core_cuts"])
    storyboard_cores = Array(storyboard["master_storyboard"])
    source_core_ids = source_cores.map { |row| row.to_h["core_cut_id"].to_s }
    storyboard_core_ids = storyboard_cores.map { |row| row.to_h["core_cut_id"].to_s }
    authorized_core_ids = Array(g40["reviewed_core_cut_ids"]).map(&:to_s)
    errors << "02A Core roster differs from source 01 Official Core order" unless storyboard_core_ids == source_core_ids
    errors << "G-40 Core roster differs from source 01 Official Core order" unless authorized_core_ids == source_core_ids

    nested_branch_rows = storyboard_cores.each_with_index.flat_map do |core, core_index|
      Array(core.to_h.dig("compile_seed", "branch_cuts")).each_with_index.map do |branch, branch_index|
        [core, core_index, branch, branch_index]
      end
    end
    nested_branch_ids = nested_branch_rows.map { |_core, _core_index, branch, _branch_index| branch.to_h["branch_cut_id"].to_s }
    authorized_branch_ids = Array(g40["reviewed_branch_cut_ids"]).map(&:to_s)
    errors << "G-40 Branch roster differs from nested 02A Branch order" unless authorized_branch_ids == nested_branch_ids

    branch_reviews = Array(branch_review["branch_cut_reviews"])
    reviewed_branch_ids = branch_reviews.map { |row| row.to_h["branch_cut_id"].to_s }
    errors << "generated Branch-Cut review must exact-cover the authorized Branch roster in order" unless reviewed_branch_ids == authorized_branch_ids
    errors << "generated Branch-Cut review ids must be unique" unless reviewed_branch_ids.uniq.length == reviewed_branch_ids.length
    branch_review_by_id = branch_reviews.to_h { |row| [row.to_h["branch_cut_id"].to_s, row.to_h] }

    section_reviews = Array(branch_review["section_reviews"])
    expected_review_section_ids = branch_reviews.map { |row| row.to_h["section_id"].to_s }.uniq
    actual_review_section_ids = section_reviews.map { |row| row.to_h["section_id"].to_s }
    errors << "generated Branch-Cut section reviews must exact-cover Branch sections in order" unless actual_review_section_ids == expected_review_section_ids
    errors << "passed generated Branch-Cut review requires every section decision pass" unless section_reviews.all? { |row| row.to_h["decision"].to_s == "pass" }

    production_rows = []
    storyboard_cores.each_with_index do |storyboard_core, core_index|
      core_id = storyboard_core.to_h["core_cut_id"].to_s
      source_core = source_cores[core_index].to_h
      imported_core = storyboard_core.to_h["imported_core"].to_h
      unless canonical_value(imported_core) == canonical_value(source_core)
        errors << "#{core_id} imported 02A Core differs from source 01"
      end
      source_01_core = storyboard_core.to_h["source_01_core"].to_h
      expected_source_core_pointer = "/official_core_cuts/#{core_index}"
      errors << "#{core_id} source 01 Core pointer differs" unless source_01_core["source_json_pointer"].to_s == expected_source_core_pointer
      errors << "#{core_id} source 01 Core value SHA-256 is stale" unless source_01_core["source_value_sha256"].to_s == value_sha256(source_core)

      primary_image = source_core["primary_image"].to_h
      errors << "#{core_id} Official Core primary image is not passed" unless primary_image["status"].to_s == "pass"
      errors << "#{core_id} Official Core full-size pixel review is not passed" unless primary_image.dig("pixel_review", "verdict").to_s == "pass"
      validate_image(
        path: primary_image["actual_path"],
        sha256: primary_image["sha256"],
        root: root,
        label: "#{core_id} Official Core primary image",
        errors: errors
      )

      context = production_context(imported_core, core_id, errors)
      section_cohort_id = section_cohort_by_id[context["section_id"]]
      errors << "#{core_id} section has no exact 02B section cohort" if section_cohort_id.to_s.empty?
      production_rows << context.merge(
        "production_cut_id" => core_id,
        "production_cut_type" => "official_core",
        "parent_core_cut_id" => core_id,
        "packet_id" => nil,
        "source_02b_packet_value_sha256" => nil,
        "section_cohort_id" => section_cohort_id,
        "source_01_core" => {
          "source_json_pointer" => expected_source_core_pointer,
          "source_value_sha256" => value_sha256(source_core)
        },
        "source_02a_cut" => {
          "source_json_pointer" => "/master_storyboard/#{core_index}/imported_core",
          "source_value_sha256" => value_sha256(imported_core)
        },
        "source_pixel_review" => {
          "source_artifact_role" => "source_01_direction",
          "source_json_pointer" => "#{expected_source_core_pointer}/primary_image",
          "source_value_sha256" => value_sha256(primary_image),
          "projected_value" => deep_copy(primary_image)
        },
        "path" => primary_image["actual_path"].to_s,
        "sha256" => primary_image["sha256"].to_s,
        "pixel_dimensions" => nil,
        "observable_pixel_truth" => nil,
        "review_note" => primary_image.dig("pixel_review", "note").to_s,
        "pixel_review_status" => "passed_production_cut"
      )

      Array(storyboard_core.to_h.dig("compile_seed", "branch_cuts")).each_with_index do |branch, branch_index|
        branch = branch.to_h
        branch_id = branch["branch_cut_id"].to_s
        source_review = branch_review_by_id[branch_id]
        if source_review.nil?
          errors << "#{branch_id} has no generated Branch-Cut review row"
          next
        end
        errors << "#{branch_id} generated pixel decision is not pass" unless source_review["decision"].to_s == "pass"
        errors << "#{branch_id} packet differs between 02A and generated review" unless source_review["packet_id"].to_s == branch["packet_id"].to_s
        errors << "#{branch_id} parent Core differs between 02A and generated review" unless source_review["core_cut_id"].to_s == core_id
        errors << "#{branch_id} section differs between 02A and generated review" unless source_review["section_id"].to_s == branch["section_id"].to_s
        packet_value_sha256 = source_review["source_02b_branch_cut_packet_value_sha256"].to_s
        errors << "#{branch_id} generated review lacks its exact 02B packet value SHA-256" if packet_value_sha256.empty?
        packet_id = source_review["packet_id"].to_s
        packet_cohort_id = packet_cohort_by_id[packet_id]
        section_cohort_id = section_cohort_by_id[branch["section_id"].to_s]
        errors << "#{branch_id} 02B packet cohort differs from its section cohort" unless !section_cohort_id.to_s.empty? && packet_cohort_id.to_s == section_cohort_id.to_s
        validate_image(
          path: source_review["image_path"],
          sha256: source_review["image_sha256"],
          root: root,
          label: "#{branch_id} generated Branch image",
          errors: errors
        )

        production_rows << production_context(branch, core_id, errors, imported_core: imported_core).merge(
          "production_cut_id" => branch_id,
          "production_cut_type" => "branch",
          "parent_core_cut_id" => core_id,
          "packet_id" => source_review["packet_id"].to_s,
          "source_02b_packet_value_sha256" => packet_value_sha256,
          "section_cohort_id" => section_cohort_id,
          "source_01_core" => {
            "source_json_pointer" => expected_source_core_pointer,
            "source_value_sha256" => value_sha256(source_core)
          },
          "source_02a_cut" => {
            "source_json_pointer" => "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}",
            "source_value_sha256" => value_sha256(branch)
          },
          "source_pixel_review" => {
            "source_artifact_role" => "source_generated_branch_cut_review",
            "source_json_pointer" => "/branch_cut_reviews/#{branch_reviews.index { |row| row.to_h["branch_cut_id"].to_s == branch_id }}",
            "source_value_sha256" => value_sha256(source_review),
            "projected_value" => deep_copy(source_review)
          },
          "path" => source_review["image_path"].to_s,
          "sha256" => source_review["image_sha256"].to_s,
          "pixel_dimensions" => deep_copy(source_review["pixel_dimensions"]),
          "observable_pixel_truth" => source_review["observable_pixel_truth"].to_s,
          "review_note" => source_review["review_note"].to_s,
          "pixel_review_status" => "passed_production_cut"
        )
      end
    end

    production_cut_ids = production_rows.map { |row| row["production_cut_id"].to_s }
    expected_production_cut_ids = storyboard_cores.flat_map do |core|
      [core.to_h["core_cut_id"].to_s] + Array(core.to_h.dig("compile_seed", "branch_cuts")).map { |branch| branch.to_h["branch_cut_id"].to_s }
    end
    errors << "Production Cut order must be each Official Core followed by its Branch children" unless production_cut_ids == expected_production_cut_ids
    errors << "Production Cut ids must be unique" unless production_cut_ids.uniq.length == production_cut_ids.length

    document = {
      "schema_version" => ACTIVE_SCHEMA_VERSION,
      "content_id" => content_ids.first.to_s,
      "status" => "passed",
      "run_root" => relative_path(run_path, root),
      "source_01_direction" => deep_copy(source_refs.fetch("source_01_direction")),
      "source_02a" => deep_copy(source_refs.fetch("source_02a")),
      "source_02b" => deep_copy(source_refs.fetch("source_02b")),
      "source_generated_branch_cut_review" => deep_copy(source_refs.fetch("source_generated_branch_cut_review")),
      "derivative_route_id" => storyboard["derivative_route_id"].to_s,
      "production_scope_id" => storyboard["production_scope_id"].to_s,
      "section_cohort_successions" => cohort_successions,
      "coverage" => {
        "source_g40_authorization" => {
          "source_json_pointer" => "/g40_core_branch_authorization",
          "source_value_sha256" => value_sha256(g40)
        },
        "official_core_cut_ids" => authorized_core_ids,
        "branch_cut_ids" => authorized_branch_ids,
        "production_cut_ids" => production_cut_ids,
        "section_ids" => production_rows.map { |row| row["section_id"].to_s }.uniq,
        "section_cohort_ids" => production_rows.map { |row| row["section_cohort_id"].to_s }.uniq,
        "official_core_count" => authorized_core_ids.length,
        "branch_count" => authorized_branch_ids.length,
        "production_cut_count" => production_rows.length,
        "exact_authorized_scope_covered" => true
      },
      "production_cut_reviews" => production_rows,
      "authority_boundary" => {
        "exact_copy_transport_only" => true,
        "production_cut_pixel_gate_passed" => true,
        "founder_pass_inferred" => false,
        "audio_placement_or_03v_motion_authored" => false,
        "paid_video_generation_approved" => false,
        "external_video_execution_approved" => false,
        "playback_pass_implied" => false,
        "edit_readiness_implied" => false
      },
      "return_recipient_role" => "creative_development_director"
    }
    [document, errors.uniq]
  end

  def build_cohort_successions(prompt_packets, errors)
    packets = Array(prompt_packets["prompt_packets"])
    packet_by_id = packets.to_h { |packet| [packet.to_h["packet_id"].to_s, packet.to_h] }
    errors << "source 02B packet ids must be unique" unless packet_by_id.length == packets.length

    section_cohort_by_id = {}
    packet_cohort_by_id = {}
    cohort_sections = {}
    cohort_sources = Hash.new { |hash, key| hash[key] = [] }
    Array(prompt_packets["section_shards"]).each_with_index do |raw_shard, shard_index|
      shard = raw_shard.to_h
      section_id = shard["section_id"].to_s
      cohort_id = shard["section_cohort_id"].to_s
      if section_id.empty? || cohort_id.empty?
        errors << "source 02B section_shards[#{shard_index}] lacks section_id or section_cohort_id"
        next
      end
      errors << "source 02B section_shards[#{shard_index}] cohort must use canonical C1..Cn form" unless cohort_id.match?(/\AC[1-9][0-9]*\z/)
      if section_cohort_by_id.key?(section_id) && section_cohort_by_id[section_id] != cohort_id
        errors << "source 02B section #{section_id} maps to multiple cohorts"
      end
      section_cohort_by_id[section_id] = cohort_id
      cohort_sections[cohort_id] ||= []
      cohort_sections[cohort_id] << section_id unless cohort_sections[cohort_id].include?(section_id)
      cohort_sources[cohort_id] << {
        "source_json_pointer" => "/section_shards/#{shard_index}",
        "source_value_sha256" => value_sha256(shard)
      }

      shard_packet_ids = Array(shard["packet_ids"]).map(&:to_s)
      shard_packet_ids.each do |packet_id|
        packet = packet_by_id[packet_id]
        if packet.nil?
          errors << "source 02B section shard names unknown packet #{packet_id}"
          next
        end
        errors << "source 02B packet #{packet_id} section differs from its shard" unless packet["execution_section_id"].to_s == section_id
        errors << "source 02B packet #{packet_id} cohort differs from its shard" unless packet["section_cohort_id"].to_s == cohort_id
        packet_cohort_by_id[packet_id] = cohort_id
      end
    end

    packet_ids = packets.map { |packet| packet.to_h["packet_id"].to_s }
    errors << "source 02B section shards must exact-cover packets once" unless packet_cohort_by_id.keys == packet_ids && packet_cohort_by_id.keys.uniq.length == packet_ids.length

    successions = cohort_sections.map do |cohort_id, section_ids|
      suffix = cohort_id.sub(/\AC/, "")
      {
        "section_cohort_id" => cohort_id,
        "section_ids" => section_ids,
        "source_02b_section_shards" => cohort_sources.fetch(cohort_id),
        "planning_cdd_lane_id" => "CDD-P3-C#{suffix}",
        "production_cdd_lane_id" => "CDD-V-C#{suffix}",
        "carry_policy" => "p3_ci_to_v_ci_exact_same_section_cohort",
        "physical_session_policy" => "primary_plus_successor_max_two_per_stage"
      }
    end
    [successions, section_cohort_by_id, packet_cohort_by_id]
  end

  def production_context(cut, parent_core_cut_id, errors, imported_core: nil)
    cut = cut.to_h
    core = imported_core ? imported_core.to_h : cut
    id = cut["branch_cut_id"].to_s.empty? ? cut["core_cut_id"].to_s : cut["branch_cut_id"].to_s
    binding = core["core_reference_binding"].to_h
    waiver_present = !binding["founder_reference_waiver"].nil?
    binding_id = waiver_present ? nil : binding["binding_id"].to_s
    errors << "#{id} lacks an exact Core reference binding or Founder waiver" if !waiver_present && binding_id.empty?
    sequence_ids = Array(core["sequence_phase_bindings"]).map(&:to_s)
    errors << "#{id} lacks the selected Sequence phase binding" if sequence_ids.empty?

    values = {
      "section_id" => cut["section_id"].to_s,
      "major_scene_id" => cut["parent_major_scene_id"].to_s,
      "active_storyline_version_id" => cut["active_storyline_version_id"].to_s,
      "screen_progression_node_id" => cut["screen_progression_node_id"].to_s,
      "scene_phase_context" => cut["scene_phase_context"].to_s,
      "primary_audio_cue" => core["primary_audio_cue"].to_s,
      "sequence_phase_binding_ids" => sequence_ids,
      "core_reference_binding_id" => binding_id.empty? ? nil : binding_id,
      "core_reference_waiver_present" => waiver_present
    }
    values.each do |field, value|
      next if %w[sequence_phase_binding_ids core_reference_binding_id core_reference_waiver_present].include?(field)

      errors << "#{id} lacks #{field}" if value.to_s.empty?
    end
    errors << "#{id} parent Core differs from its typed context" unless parent_core_cut_id.to_s == core["core_cut_id"].to_s
    values
  end

  def validate_image(path:, sha256:, root:, label:, errors:)
    resolved = resolve_path(path, root)
    unless inside?(resolved, root) && resolved.file?
      errors << "#{label} is missing or outside the repository"
      return
    end
    errors << "#{label} SHA-256 is stale" unless sha256.to_s == Digest::SHA256.file(resolved).hexdigest
  end
end
