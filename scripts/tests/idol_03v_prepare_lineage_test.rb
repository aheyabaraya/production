# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_03v_source_discovery"

class Idol03VPrepareLineageTest < Minitest::Test
  RUN_REL = "runs/test-album/prep-lineage/0712_PREP_LINEAGE_TEST"
  ONE_PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC").freeze

  def setup
    @root = Pathname.new(Dir.mktmpdir("idol-03v-prepare-lineage-", "/private/tmp"))
    @run = @root.join(RUN_REL)
    FileUtils.mkdir_p(@run)
    write("#{RUN_REL}/run-manifest.yaml", YAML.dump(
      "schema_version" => "idol-run-manifest.v1", "status" => "active", "album_key" => "test-album",
      "title_key" => "prep-lineage", "run_id" => @run.basename.to_s, "content_id" => @run.basename.to_s,
      "canonical_run_root" => RUN_REL, "artifact_revision_owner" => "git", "compatibility_authoring" => "forbidden"
    ))
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.directory?
  end

  def test_official_core_and_branch_join_one_typed_review_and_placement_union
    fixture = build_fixture
    result = reconcile(fixture)

    assert_empty result.errors
    assert_equal %w[official_core branch], result.joined_cues.map { |cue| cue.dig("review_record", "production_cut_type") }
    assert_nil result.joined_cues.first["prompt_packet"]
    assert_equal "PKT_BC01_ACTION", result.joined_cues.last.dig("prompt_packet", "packet_id")
    assert_equal "APCP_C01", result.joined_cues.first.dig("placement_production_cut_unit", "placement_id")
    assert_match(/PRODUCTION_CUT_REVIEW\z/, result.bound_source_refs.fetch("production_cut_review"))
  end

  def test_snapshot_prompt_packet_mismatch_is_rejected
    fixture = build_fixture
    alternate = write("#{RUN_REL}/02B-prompt-packets-v99.yaml", fixture.fetch("packets_path").read)
    row = fixture.fetch("snapshot").fetch("sources").find { |source| source["role"] == "prompt_packets" }
    row.merge!(hashed(alternate))
    fixture.fetch("snapshot")["source_set_sha256"] = Idol03VSourceDiscovery.canonical_source_set_digest(fixture.fetch("snapshot")["sources"])

    result = reconcile(fixture)

    assert result.errors.any? { |error| error.include?("source snapshot prompt_packets path/sha256 does not match") }
  end

  def test_snapshot_typed_review_mismatch_is_rejected
    fixture = build_fixture
    alternate = write("#{RUN_REL}/alternate-production-cut-review.yaml", fixture.fetch("review_path").read)
    row = fixture.fetch("snapshot").fetch("sources").find { |source| source["role"] == "production_cut_review" }
    row.merge!(hashed(alternate))
    fixture.fetch("snapshot")["source_set_sha256"] = Idol03VSourceDiscovery.canonical_source_set_digest(fixture.fetch("snapshot")["sources"])

    result = reconcile(fixture)

    assert result.errors.any? { |error| error.include?("source snapshot production_cut_review path/sha256 does not match") }
  end

  def test_missing_official_core_placement_is_rejected
    fixture = build_fixture
    fixture.fetch("placement").fetch("production_cut_units").shift

    result = reconcile(fixture)

    assert result.errors.any? { |error| error.include?("eligible Production Cut cue 1 must join exactly one placement unit") }
    assert result.errors.any? { |error| error.include?("exact 1:1 cardinality") }
  end

  def test_branch_cannot_join_a_packet_from_another_parent_core
    fixture = build_fixture
    fixture.fetch("placement").fetch("production_cut_units").last["parent_core_cut_id"] = "C99"

    result = reconcile(fixture)

    assert result.errors.any? { |error| error.include?("must join exactly one placement unit by type/id/parent Core/review image") }
  end

  def test_missing_passed_production_cut_snapshot_image_is_rejected
    fixture = build_fixture
    fixture.fetch("snapshot").fetch("sources").reject! { |source| source["role"].to_s.start_with?("passed_production_cut_image_") && source["path"].include?("C01.png") }

    result = reconcile(fixture)

    assert result.errors.any? { |error| error.include?("passed_production_cut_image snapshot row") }
  end

  private

  def reconcile(fixture)
    Idol03VSourceDiscovery.reconcile_ready_authoring_lineage(
      snapshot: fixture.fetch("snapshot"), placement: fixture.fetch("placement"),
      placement_path: fixture.fetch("placement_path"), repo_root: @root, run_path: @run
    )
  end

  def build_fixture
    core_image = write_binary("#{RUN_REL}/generations/production-cuts/C01.png", ONE_PIXEL_PNG)
    branch_image = write_binary("#{RUN_REL}/generations/production-cuts/BC01_ACTION.png", ONE_PIXEL_PNG + "branch")
    direction_path = write("#{RUN_REL}/01-song-choreography-performance-mv-map.yaml", YAML.dump("schema_version" => "3.0", "content_id" => @run.basename.to_s))
    storyboard_path = write("#{RUN_REL}/02A-master-storyboard.yaml", YAML.dump("schema_version" => "3.0", "content_id" => @run.basename.to_s))
    packets_path = write("#{RUN_REL}/02B-prompt-packets.yaml", YAML.dump(
      "schema_version" => "2.5", "content_id" => @run.basename.to_s, "status" => "approved",
      "prompt_packets" => [{"core_cut_id" => "C01", "branch_cut_id" => "BC01_ACTION", "packet_id" => "PKT_BC01_ACTION"}]
    ))
    reviews = [
      review_spec("official_core", "C01", "C01", nil, core_image),
      review_spec("branch", "BC01_ACTION", "C01", "PKT_BC01_ACTION", branch_image)
    ]
    review_path = write("#{RUN_REL}/03-production-cut-review.yaml", YAML.dump(
      "schema_version" => "idol-production-cut-review.v1", "content_id" => @run.basename.to_s, "status" => "passed",
      "source_01_direction" => hashed(direction_path), "source_02a" => hashed(storyboard_path), "source_02b" => hashed(packets_path),
      "production_cut_reviews" => reviews
    ))
    audio_path = write_binary("#{RUN_REL}/audio/selected.wav", "selected audio bytes\n")
    audio_motion_path = write("#{RUN_REL}/research/audio-motion-director-map-v1.yaml", YAML.dump("schema_version" => "fixture", "timeline" => "0.000-2.000"))
    units = reviews.each_with_index.map do |review, index|
      {
        "placement_id" => index.zero? ? "APCP_C01" : "APCP_BC01_ACTION",
        "production_cut_id" => review.fetch("production_cut_id"), "production_cut_type" => review.fetch("production_cut_type"),
        "parent_core_cut_id" => review.fetch("parent_core_cut_id"), "packet_id" => review["packet_id"],
        "passed_source_image" => {"path" => review.fetch("path"), "sha256" => review.fetch("sha256")}
      }
    end
    placement = {
      "schema_version" => "idol_audio_production_cut_placement.v5", "content_id" => @run.basename.to_s, "status" => "ready_for_03v",
      "source_audio" => hashed(audio_path), "source_audio_motion_map" => hashed(audio_motion_path),
      "source_production_cut_review" => hashed(review_path), "source_01_direction" => hashed(direction_path),
      "source_02a" => hashed(storyboard_path), "source_02b" => hashed(packets_path), "production_cut_units" => units
    }
    placement_path = write("#{RUN_REL}/03V-audio-branch-cut-placement.yaml", YAML.dump(placement))
    snapshot = Idol03VSourceDiscovery.scan(run_path: @run, repo_root: @root, generated_at: "2026-07-12T03:00:00Z").document
    snapshot_errors = Idol03VSourceDiscovery.validate_snapshot(snapshot, repo_root: @root, run_root: @run)
    raise "fixture source snapshot invalid: #{snapshot_errors.join('; ')}" unless snapshot_errors.empty?
    {"placement" => placement, "placement_path" => placement_path, "snapshot" => snapshot, "review_path" => review_path, "packets_path" => packets_path}
  end

  def review_spec(type, id, parent, packet_id, image_path)
    {
      "production_cut_id" => id, "production_cut_type" => type, "parent_core_cut_id" => parent, "packet_id" => packet_id,
      "path" => image_path.relative_path_from(@root).to_s, "sha256" => Digest::SHA256.file(image_path).hexdigest,
      "pixel_review_status" => "passed_production_cut"
    }
  end

  def hashed(path)
    {"path" => path.relative_path_from(@root).to_s, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def write(relative_path, content)
    path = @root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    path.write(content)
    path
  end

  def write_binary(relative_path, content)
    path = @root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, content)
    path
  end
end
