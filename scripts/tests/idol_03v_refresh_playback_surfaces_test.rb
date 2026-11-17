# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class Idol03vRefreshPlaybackSurfacesTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_03v_refresh_playback_surfaces.rb")
  APPLY_REVIEW = ROOT.join("scripts", "idol_03v_apply_playback_review_record.rb")

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-03v-refresh-"))
    @run = @tmp.join("runs", "test-album", "refresh-test", "REFRESH_TEST")
    @review = @run.join("review")
    @review.mkpath
    @run.join("run-manifest.yaml").write(YAML.dump(
      "schema_version" => "idol-run-manifest.v1",
      "album_key" => "test-album",
      "title_key" => "refresh-test",
      "run_id" => "REFRESH_TEST",
      "canonical_run_root" => "runs/test-album/refresh-test/REFRESH_TEST",
      "artifact_revision_owner" => "git",
      "compatibility_authoring" => "forbidden"
    ), encoding: "utf-8")
    @worklist = @review.join("03v-section-video-prompt-qa-worklist-v1.yaml")
    write_worklist("0.000-1.000")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def provider_neutral_review_owner
    registry = ROOT.join("automation", "harness-provider-profile-registry.yaml")
    {
      "logical_role" => "creative_development_director",
      "logical_profile_alias" => "director_deep",
      "provider_profile_snapshot_ref" => "automation/harness-provider-profile-registry.yaml#/logical_profiles/director_deep/providers/codex/role_profiles/creative_development_director",
      "provider_capability_snapshot_sha256" => Digest::SHA256.file(registry).hexdigest,
      "automatic_fallback" => "none"
    }
  end

  def write_worklist(timeline)
    @worklist.write(YAML.dump(
      "schema_version" => "harness-blocker-worklist.v2",
      "generated_at" => "2026-07-10T00:00:00+09:00",
      "run" => @run.to_s,
      "worklist_type" => "video_prompt_section_qa",
      "source_artifact" => @review.join("03v-section-video-prompt-qa-v1.yaml").to_s,
      "status" => "worklist_only_not_a_pass_record",
      "summary" => {
        "front_playback_gate_section_range" => "S00-S00",
        "section_count" => 1,
        "packet_count" => 1
      },
      "section_queue" => [
        {
          "section_key" => "S00",
          "section_label" => "intro",
          "status" => "needs_founder",
          "packet_ids" => ["03VCUE_PLAYBACK"],
          "unfinished_checks" => ["generation_playback_probe"],
          "entry_continuity" => "start",
          "exit_continuity" => "hold",
          "review_actions" => [
            {"field" => "generation_playback_probe", "status" => "needs_founder", "action" => "review clip"}
          ],
          "packets" => [
            {
              "packet_id" => "03VCUE_PLAYBACK",
              "timeline" => timeline,
              "audio_motion_slot" => "AMS_001",
              "prompt_path" => @run.join("generations/video-prompts/v1/B01.txt").to_s,
              "start_image" => @run.join("generations/branch-cuts/BC01.png").to_s,
              "end_image" => @run.join("generations/branch-cuts/BC02.png").to_s,
              "upload_pack" => @run.join("generations/video-prompts/v1/upload-ready/01_B01").to_s,
              "start_audio_cue" => "first bass accent",
              "end_audio_cue" => "snare stop",
              "prev_end_to_start" => "start clean",
              "end_to_next_start" => "hold planted foot",
              "edit_point_basis" => "cut on fist stop"
            }
          ]
        }
      ],
      "automation_boundaries" => ["Worklist is not a pass record."]
    ), encoding: "utf-8")
  end

  def run_refresh(*extra)
    Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      @run.to_s,
      "--worklist", @worklist.to_s,
      "--route", "local_test",
      "--write",
      *extra,
      chdir: ROOT.to_s
    )
  end

  def test_identical_sources_use_noop_and_tampered_output_refreshes
    stdout, stderr, status = run_refresh
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "03v_playback_refresh refreshed"
    state_path = @review.join("03v-playback-refresh-state-v1.yaml")
    state = YAML.safe_load(state_path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
    assert_equal "first_refresh", state.dig("summary", "refresh_reason")

    stdout, stderr, status = run_refresh
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "03v_playback_refresh noop"

    @review.join("03v-playback-decision-sheet-v1.md").open("a") { |file| file.puts("tampered") }
    stdout, stderr, status = run_refresh
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "reason=derived_output_stale"
  end

  def test_worklist_change_invalidates_refresh_state
    _stdout, stderr, status = run_refresh
    assert status.success?, stderr
    write_worklist("0.000-1.250")
    stdout, stderr, status = run_refresh
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "reason=source_changed"
  end

  def test_implementation_fingerprint_change_invalidates_noop
    _stdout, stderr, status = run_refresh
    assert status.success?, stderr
    state_path = @review.join("03v-playback-refresh-state-v1.yaml")
    state = YAML.safe_load(state_path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
    state["refresh_contract"]["implementation_fingerprint_sha256"] = "0" * 64
    state_path.write(YAML.dump(state), encoding: "utf-8")
    stdout, stderr, status = run_refresh
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "reason=implementation_changed"
  end

  def test_pass_record_without_clip_digest_cannot_patch_section_qa
    run_rel = @run.relative_path_from(@tmp).to_s
    clip = @run.join("generations", "video", "generated-clips", "clip.mp4")
    clip.dirname.mkpath
    clip.write("not-a-real-video-but-byte-binding-is-the-gate-under-test")
    worklist = @review.join("03v-playback-review-worklist-v1.yaml")
    required_checks = [{"id" => "start_frame_lock"}]
    packet = {
      "packet_id" => "03VCUE_PLAYBACK",
      "section_key" => "S00",
      "timeline" => "0.000-1.000",
      "clip_status" => "present",
      "generated_clip_path" => clip.to_s,
      "generated_clip_sha256" => "",
      "required_checks" => required_checks
    }
    worklist.write(YAML.dump(
      "schema_version" => "idol_03v_playback_review_worklist.v1",
      "run" => run_rel,
      "source_intake" => @review.join("03v-generated-playback-intake-v1.yaml").to_s,
      "source_section_qa" => @review.join("missing-section-qa.yaml").to_s,
      "section_range" => "S00-S00",
      "section_reviews" => [{"section_key" => "S00", "packets" => [packet]}]
    ))
    worklist_sha = Digest::SHA256.file(worklist.to_s).hexdigest
    record = @review.join("03v-playback-review-record-v1.yaml")
    record.write(YAML.dump(
      "schema_version" => "idol_03v_playback_review_record.v1",
      "generated_at" => "2026-07-10T00:00:00+09:00",
      "run" => run_rel,
      "source_review_worklist" => worklist.to_s,
      "source_review_worklist_sha256" => worklist_sha,
      "source_intake" => @review.join("03v-generated-playback-intake-v1.yaml").to_s,
      "source_intake_sha256" => "0" * 64,
      "source_section_qa" => @review.join("missing-section-qa.yaml").to_s,
      "source_section_qa_sha256" => "0" * 64,
      "section_range" => "S00-S00",
      "target_scope" => "section",
      "target_id" => "S00",
      "decision" => "pass",
      "decision_input_text" => "S00-S00 pass: explicit playback review",
      "explicit_founder_review" => true,
      "covered_packets" => [packet.merge(
        "required_check_count" => 1,
        "review_status_after_record" => "pass_recorded"
      )],
      "summary" => {
        "packet_count" => 1,
        "present_clip_count" => 1,
        "missing_clip_count" => 0,
        "all_target_clips_present" => true,
        "can_patch_generation_playback_probe" => true
      }
    ))

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      APPLY_REVIEW.to_s,
      @run.to_s,
      "--record", record.to_s,
      "--root", @tmp.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    refute status.success?, stdout
    assert_includes stderr, "requires a generated clip sha256"
  end

  def test_cross_run_clip_cannot_patch_section_qa_even_with_matching_digest
    run_rel = @run.relative_path_from(@tmp).to_s
    outside_run = @tmp.join("runs", "2026-07-10", "OTHER_RUN")
    clip = outside_run.join("generations/video/clip.mp4")
    clip.dirname.mkpath
    clip.write("cross-run clip bytes")
    clip_sha = Digest::SHA256.file(clip.to_s).hexdigest
    intake = @review.join("03v-generated-playback-intake-v1.yaml")
    intake.write(YAML.dump(
      "schema_version" => "idol_03v_generated_playback_intake.v1",
      "run" => run_rel,
      "route" => "local_test",
      "clips_root" => @run.join("generations/video/generated-clips").to_s
    ))
    source_qa = @review.join("03v-section-video-prompt-qa-v1.yaml")
    source_qa.write(YAML.dump("schema_version" => "idol_video_prompt_section_qa.v1", "sections" => []))
    worklist = @review.join("03v-playback-review-worklist-v1.yaml")
    checks = [{"id" => "start_frame_lock", "label" => "Start frame remains locked."}]
    packet = {
      "packet_id" => "03VCUE_PLAYBACK",
      "section_key" => "S00",
      "timeline" => "0.000-1.000",
      "clip_status" => "present",
      "generated_clip_path" => clip.to_s,
      "generated_clip_sha256" => clip_sha,
      "required_checks" => checks
    }
    worklist.write(YAML.dump(
      "schema_version" => "idol_03v_playback_review_worklist.v1",
      "run" => run_rel,
      "source_intake" => intake.to_s,
      "source_section_qa" => source_qa.to_s,
      "section_range" => "S00-S00",
      "section_reviews" => [{"section_key" => "S00", "packets" => [packet]}]
    ))
    record = @review.join("03v-playback-review-record-v2.yaml")
    record.write(YAML.dump(
      "schema_version" => "idol_03v_playback_review_record.v1",
      "generated_at" => "2026-07-10T00:00:00+09:00",
      "run" => run_rel,
      "source_review_worklist" => worklist.to_s,
      "source_review_worklist_sha256" => Digest::SHA256.file(worklist.to_s).hexdigest,
      "source_intake" => intake.to_s,
      "source_intake_sha256" => Digest::SHA256.file(intake.to_s).hexdigest,
      "source_section_qa" => source_qa.to_s,
      "source_section_qa_sha256" => Digest::SHA256.file(source_qa.to_s).hexdigest,
      "section_range" => "S00-S00",
      "target_scope" => "section",
      "target_id" => "S00",
      "decision" => "pass",
      "decision_input_text" => "S00 pass: explicit playback review",
      "explicit_founder_review" => true,
      "covered_packets" => [packet.merge("required_check_count" => 1, "review_status_after_record" => "pass_recorded")],
      "summary" => {
        "packet_count" => 1,
        "present_clip_count" => 1,
        "missing_clip_count" => 0,
        "all_target_clips_present" => true,
        "can_patch_generation_playback_probe" => true
      }
    ))

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      APPLY_REVIEW.to_s,
      @run.to_s,
      "--record", record.to_s,
      "--root", @tmp.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    refute status.success?, stdout
    assert_includes stderr, "must stay inside the owning run"
  end

  def test_hash_bound_playable_same_run_sources_patch_successfully
    fixture = write_positive_apply_fixture
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      APPLY_REVIEW.to_s,
      @run.to_s,
      "--record", fixture.fetch(:record).to_s,
      "--root", @tmp.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
    output = @review.join("03v-section-video-prompt-qa-v2.yaml")
    assert output.file?
    document = YAML.safe_load(output.read, permitted_classes: [], permitted_symbols: [], aliases: true)
    assert_equal "pass", document["overall_status"]
    assert_equal "pass", document.dig("sections", 0, "status")
    assert_equal [], document.dig("sections", 0, "findings")
    assert_equal "Integrated contextual review passed; only explicit generated playback remained pending.",
                 document.dig("sections", 0, "review_summary")
  end

  def test_same_run_worklist_cannot_disagree_with_hash_bound_intake
    fixture = write_positive_apply_fixture
    worklist = YAML.safe_load(fixture.fetch(:worklist).read, permitted_classes: [], permitted_symbols: [], aliases: true)
    worklist.dig("section_reviews", 0, "packets", 0)["timeline"] = "0.000-9.999"
    fixture.fetch(:worklist).write(YAML.dump(worklist), encoding: "utf-8")
    record = YAML.safe_load(fixture.fetch(:record).read, permitted_classes: [], permitted_symbols: [], aliases: true)
    record["source_review_worklist_sha256"] = Digest::SHA256.file(fixture.fetch(:worklist).to_s).hexdigest
    record.dig("covered_packets", 0)["timeline"] = "0.000-9.999"
    fixture.fetch(:record).write(YAML.dump(record), encoding: "utf-8")

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      APPLY_REVIEW.to_s,
      @run.to_s,
      "--record", fixture.fetch(:record).to_s,
      "--root", @tmp.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    refute status.success?, stdout
    assert_includes stderr, "timeline does not match source intake"
  end

  def write_positive_apply_fixture
    run_rel = @run.relative_path_from(@tmp).to_s
    clips_root = @run.join("generations/video/generated-clips/03v/test")
    clip = clips_root.join("03VCUE_PLAYBACK.mp4")
    clip.dirname.mkpath
    ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].find { |path| File.executable?(path) } || "ffmpeg"
    _stdout, stderr, status = Open3.capture3(
      ffmpeg,
      "-hide_banner", "-loglevel", "error", "-y",
      "-f", "lavfi", "-i", "color=c=black:s=320x180:r=24:d=1",
      "-an", "-c:v", "mpeg4", "-q:v", "5", "-pix_fmt", "yuv420p",
      clip.to_s
    )
    raise "ffmpeg fixture failed: #{stderr}" unless status.success?
    clip_sha = Digest::SHA256.file(clip.to_s).hexdigest
    probe = {
      "status" => "ok",
      "playable" => true,
      "duration_seconds" => 1.0,
      "video_stream_count" => 1,
      "audio_stream_count" => 0,
      "width" => 320,
      "height" => 180,
      "codec_name" => "mpeg4",
      "error" => ""
    }
    checks = [{"id" => "start_frame_lock", "label" => "Start frame remains locked."}]
    packet = {
      "packet_id" => "03VCUE_PLAYBACK",
      "section_key" => "S00",
      "timeline" => "0.000-1.000",
      "clip_status" => "present",
      "clip_file_status" => "present_probe_ok",
      "media_probe" => probe,
      "generated_clip_path" => clip.to_s,
      "generated_clip_sha256" => clip_sha,
      "required_checks" => checks
    }
    video_prompt_manifest = @run.join("03V-video-prompt-manifest.yaml")
    video_prompt_manifest.write(YAML.dump(
      "schema_version" => "idol_video_prompt_manifest.v7",
      "content_id" => "REFRESH_TEST",
      "section_shards" => [{"section_id" => "S00", "cue_ids" => ["03VCUE_PLAYBACK"]}],
      "cues" => [{"cue_id" => "03VCUE_PLAYBACK", "section_id" => "S00", "prompt_text" => "Use the reviewed playback route."}]
    ), encoding: "utf-8")
    section_execution = @review.join("03v-section-contextual-review-execution.yaml")
    whole_execution = @review.join("03v-whole-timeline-review-execution.yaml")
    section_execution.write("completed: true\n", encoding: "utf-8")
    whole_execution.write("completed: true\n", encoding: "utf-8")
    source_qa = @review.join("03v-section-video-prompt-qa-v1.yaml")
    source_qa.write(YAML.dump(
      "schema_version" => "idol_video_prompt_section_qa.v6",
      "content_id" => "REFRESH_TEST",
      "review_unit" => "section",
      "overall_status" => "needs_review",
      "source_video_prompt_manifest_path" => video_prompt_manifest.to_s,
      "source_video_prompt_manifest_sha256" => Digest::SHA256.file(video_prompt_manifest).hexdigest,
      "review_mode" => "contextual_llm_section_and_whole_timeline",
      "review_owner" => provider_neutral_review_owner,
      "sections" => [
        {
          "section_key" => "S00",
          "status" => "needs_review",
          "reviewed_prompt_count" => 1,
          "cue_ids" => ["03VCUE_PLAYBACK"],
          "review_summary" => "Integrated contextual review passed; only explicit generated playback remained pending.",
          "findings" => [],
          "review_execution_record" => {
            "path" => section_execution.to_s,
            "sha256" => Digest::SHA256.file(section_execution).hexdigest
          }
        }
      ],
      "whole_timeline_review" => {
        "status" => "pass",
        "review_summary" => "The whole-timeline route is coherent and has no unresolved cross-section finding.",
        "findings" => [],
        "review_execution_record" => {
          "path" => whole_execution.to_s,
          "sha256" => Digest::SHA256.file(whole_execution).hexdigest
        }
      }
    ), encoding: "utf-8")
    intake = @review.join("03v-generated-playback-intake-v1.yaml")
    intake.write(YAML.dump(
      "schema_version" => "idol_03v_generated_playback_intake.v1",
      "run" => run_rel,
      "route" => "local_test",
      "source_worklist" => "#{run_rel}/review/03v-section-video-prompt-qa-worklist-v1.yaml",
      "source_section_qa" => source_qa.to_s,
      "section_range" => "S00-S00",
      "clips_root" => clips_root.to_s,
      "clip_queue" => [packet]
    ), encoding: "utf-8")
    worklist = @review.join("03v-playback-review-worklist-v1.yaml")
    worklist.write(YAML.dump(
      "schema_version" => "idol_03v_playback_review_worklist.v1",
      "run" => run_rel,
      "source_intake" => intake.to_s,
      "source_section_qa" => source_qa.to_s,
      "section_range" => "S00-S00",
      "section_reviews" => [{"section_key" => "S00", "packets" => [packet]}]
    ), encoding: "utf-8")
    record = @review.join("03v-playback-review-record-v1.yaml")
    record.write(YAML.dump(
      "schema_version" => "idol_03v_playback_review_record.v1",
      "generated_at" => "2026-07-10T00:00:00+09:00",
      "run" => run_rel,
      "status" => "recorded",
      "source_review_worklist" => worklist.to_s,
      "source_review_worklist_sha256" => Digest::SHA256.file(worklist.to_s).hexdigest,
      "source_intake" => intake.to_s,
      "source_intake_sha256" => Digest::SHA256.file(intake.to_s).hexdigest,
      "source_section_qa" => source_qa.to_s,
      "source_section_qa_sha256" => Digest::SHA256.file(source_qa.to_s).hexdigest,
      "section_range" => "S00-S00",
      "target_scope" => "section",
      "target_id" => "S00",
      "decision" => "pass",
      "decision_input_text" => "S00 pass: explicit playback review",
      "decision_note" => "Visible body route, camera stop, and endpoint all pass.",
      "review_source" => "founder_test_fixture",
      "explicit_founder_review" => true,
      "covered_sections" => ["S00"],
      "covered_packets" => [packet.slice("packet_id", "section_key", "timeline", "clip_status", "generated_clip_path", "generated_clip_sha256", "required_checks").merge(
        "required_check_count" => 1,
        "review_status_after_record" => "pass_recorded"
      )],
      "summary" => {
        "packet_count" => 1,
        "present_clip_count" => 1,
        "missing_clip_count" => 0,
        "pending_review_count" => 1,
        "all_target_clips_present" => true,
        "can_patch_generation_playback_probe" => true
      },
      "next_action" => "Apply the hash-bound playback pass to the covered section QA.",
      "automation_boundaries" => ["This fixture records playback review only."]
    ), encoding: "utf-8")
    {record: record, worklist: worklist}
  end
end
