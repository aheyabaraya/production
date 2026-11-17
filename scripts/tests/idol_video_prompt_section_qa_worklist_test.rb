# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolVideoPromptSectionQaWorklistTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_video_prompt_section_qa_worklist.rb")

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-03v-qa-worklist-"))
    @run = @tmp.join("runs", "test-album", "test-title", "TEST_RUN")
    @review = @run.join("review")
    @prompt_dir = @run.join("generations", "video-prompts", "S00", "03VCUE_TEST")
    @review.mkpath
    @prompt_dir.mkpath
    @image = @run.join("generations", "branch-cuts", "BC01.png")
    @image.dirname.mkpath
    @image.write("fixture pixels", encoding: "utf-8")
    @prompt = @prompt_dir.join("prompt.txt")
    @prompt.write("fixture prompt", encoding: "utf-8")
    write_manifest
    write_qa
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp&.directory?
  end

  def test_worklist_uses_active_manifest_cues_and_schema_validates
    output = @review.join("03v-section-video-prompt-qa-worklist-v1.md")
    output_yaml = output.sub_ext(".yaml")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      @run.to_s,
      "--manifest", @manifest.to_s,
      "--qa", @qa.to_s,
      "--output", output.to_s,
      "--output-yaml", output_yaml.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    assert status.success?, "stdout=#{stdout}\nstderr=#{stderr}"

    document = YAML.safe_load(output_yaml.read, permitted_classes: [], permitted_symbols: [], aliases: true)
    assert_equal "harness-blocker-worklist.v2", document["schema_version"]
    assert_equal @manifest.to_s, document.dig("related_artifacts", "video_prompt_manifest")
    assert_equal ["03VCUE_TEST"], document.dig("section_queue", 0, "packet_ids")
    assert_equal "03VCUE_TEST", document.dig("section_queue", 0, "packets", 0, "packet_id")

    schema_stdout, schema_stderr, schema_status = Open3.capture3(
      ROOT.join("scripts", "idol-video-python").to_s,
      ROOT.join("scripts", "validate_json_schema.py").to_s,
      ROOT.join("schemas", "harness-blocker-worklist.schema.json").to_s,
      output_yaml.to_s,
      chdir: ROOT.to_s
    )
    assert schema_status.success?, "stdout=#{schema_stdout}\nstderr=#{schema_stderr}"
  end

  private

  def write_manifest
    @manifest = @run.join("03V-video-prompt-manifest.yaml")
    @manifest.write(YAML.dump(
      "schema_version" => "idol_video_prompt_manifest.v8",
      "content_id" => "TEST_RUN",
      "canonical_video_prompt_output_root" => @run.join("generations", "video-prompts").to_s,
      "section_shards" => [{
        "section_id" => "S00",
        "cue_ids" => ["03VCUE_TEST"],
        "output_prompt_paths" => [@prompt.to_s]
      }],
      "cues" => [{
        "cue_id" => "03VCUE_TEST",
        "section_id" => "S00",
        "timeline" => {
          "start_seconds" => 0.0,
          "end_seconds" => 1.5,
          "audio_cue" => "first bass impact"
        },
        "source_production_cut_images" => [{"path" => @image.to_s}],
        "previous_next_continuity" => "Enter from black and leave on the planted stop.",
        "edit_handoff" => "Cut after the stop reads."
      }]
    ), encoding: "utf-8")
  end

  def write_qa
    @qa = @review.join("03v-section-video-prompt-qa-v1.yaml")
    @qa.write(YAML.dump(
      "schema_version" => "idol_video_prompt_section_qa.v6",
      "content_id" => "TEST_RUN",
      "review_unit" => "section",
      "overall_status" => "needs_review",
      "source_video_prompt_manifest_path" => @manifest.to_s,
      "source_video_prompt_manifest_sha256" => Digest::SHA256.file(@manifest).hexdigest,
      "review_mode" => "contextual_llm_section_and_whole_timeline",
      "review_owner" => provider_neutral_review_owner,
      "sections" => [{
        "section_key" => "S00",
        "status" => "needs_review",
        "reviewed_prompt_count" => 1,
        "cue_ids" => ["03VCUE_TEST"],
        "review_summary" => "The source and prompt are coherent; playback remains.",
        "findings" => [{
          "severity" => "revise",
          "affected_cue_ids" => ["03VCUE_TEST"],
          "issue" => "Playback has not been inspected.",
          "required_action" => "Review the generated clip."
        }],
        "review_execution_record" => {
          "path" => @qa.to_s,
          "sha256" => "0" * 64
        }
      }],
      "whole_timeline_review" => {
        "status" => "needs_review",
        "review_summary" => "One cue remains.",
        "findings" => [],
        "review_execution_record" => {
          "path" => @qa.to_s,
          "sha256" => "0" * 64
        }
      }
    ), encoding: "utf-8")
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
end
