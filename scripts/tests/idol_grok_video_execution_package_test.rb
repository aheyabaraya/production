# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_grok_video_execution_package"

class IdolGrokVideoExecutionPackageTest < Minitest::Test
  def setup
    @temporary = Pathname.new(Dir.mktmpdir("idol-grok-video-package-", "/private/tmp"))
    @root = @temporary.join("repo")
    @root.join("automation/providers").mkpath
    @run = @root.join("work", "dummy-run")
    @run.join("pixels").mkpath
    @manifest_path = @run.join("03V-video-prompt-manifest.yaml")
    write_provider_sources
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary.exist?
  end

  def test_i2v_prompt_naming_unattached_slot_holds_without_rewrite
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    manifest.dig("cues", 0)["prompt_text"] = "Use @image1 and @image2."
    manifest.dig("cues", 0, "grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(manifest.dig("cues", 0)["prompt_text"])
    write_manifest(manifest)
    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(
        root: @root,
        manifest_path: @manifest_path,
        manifest: manifest,
        cue_id: "03VCUE_DUMMY_01"
      )
    end
    assert_match(/unattached @image2/, error.message)
    assert_equal "Use @image1 and @image2.", manifest.dig("cues", 0, "prompt_text")
  end

  def test_i2v_prompt_naming_image4_holds_without_rewrite
    prompt = "Use @image1 then @image4."
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    manifest.dig("cues", 0)["prompt_text"] = prompt
    manifest.dig("cues", 0, "grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    write_manifest(manifest)
    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(
        root: @root,
        manifest_path: @manifest_path,
        manifest: manifest,
        cue_id: "03VCUE_DUMMY_01"
      )
    end
    assert_match(/unattached @image4/, error.message)
    refute_match(/unattached @image1[^0-9]/, error.message)
    assert_equal prompt, manifest.dig("cues", 0, "prompt_text")
  end

  def test_i2v_prompt_naming_image5_holds_without_rewrite
    prompt = "Use @image1 then @image5."
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    manifest.dig("cues", 0)["prompt_text"] = prompt
    manifest.dig("cues", 0, "grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    write_manifest(manifest)
    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(
        root: @root,
        manifest_path: @manifest_path,
        manifest: manifest,
        cue_id: "03VCUE_DUMMY_01"
      )
    end
    assert_match(/unattached @image5/, error.message)
    assert_equal prompt, manifest.dig("cues", 0, "prompt_text")
  end

  def test_i2v_prompt_naming_image10_is_not_a_prefix_of_image1
    prompt = "Use @image10 as the only still."
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    manifest.dig("cues", 0)["prompt_text"] = prompt
    manifest.dig("cues", 0, "grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    write_manifest(manifest)
    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(
        root: @root,
        manifest_path: @manifest_path,
        manifest: manifest,
        cue_id: "03VCUE_DUMMY_01"
      )
    end
    assert_match(/unattached @image10/, error.message)
    refute_match(/unattached @image1[^0-9]/, error.message)
    assert_equal prompt, manifest.dig("cues", 0, "prompt_text")
  end

  def test_reference_to_video_three_inputs_may_name_image1_to_image3
    prompt = "Use @image1, @image2, and @image3 in Founder order."
    rows = [
      source_row("CUT_A", ".png", "first-pixel"),
      source_row("CUT_B", ".jpg", "second-pixel"),
      source_row("CUT_C", ".webp", "third-pixel")
    ]
    manifest = manifest_for(rows: rows, tool: "reference_to_video")
    manifest.dig("cues", 0)["prompt_text"] = prompt
    manifest.dig("cues", 0, "grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    write_manifest(manifest)
    plan = IdolGrokVideoExecutionPackage.plan!(
      root: @root,
      manifest_path: @manifest_path,
      manifest: manifest,
      cue_id: "03VCUE_DUMMY_01"
    )
    assert_equal %w[CUT_A CUT_B CUT_C], plan["ordered_inputs"].map { |row| row["production_cut_id"] }
    assert_equal prompt, plan["prompt_text"]
    result = IdolGrokVideoExecutionPackage.materialize!(
      root: @root,
      plan: plan,
      package_root: @temporary.join("packages-rtv3")
    )
    package = Pathname.new(result.fetch("package_path"))
    assert_equal prompt, package.join("prompt.txt").read
    assert_equal rows[0]["sha256"], Digest::SHA256.file(package.join("input-01.png")).hexdigest
    assert_equal rows[1]["sha256"], Digest::SHA256.file(package.join("input-02.jpg")).hexdigest
    assert_equal rows[2]["sha256"], Digest::SHA256.file(package.join("input-03.webp")).hexdigest
  end

  def test_reference_to_video_three_inputs_reject_image4_without_rewrite
    prompt = "Use @image1 @image2 @image3 @image4."
    rows = [
      source_row("CUT_A", ".png", "first-pixel"),
      source_row("CUT_B", ".jpg", "second-pixel"),
      source_row("CUT_C", ".webp", "third-pixel")
    ]
    manifest = manifest_for(rows: rows, tool: "reference_to_video")
    manifest.dig("cues", 0)["prompt_text"] = prompt
    manifest.dig("cues", 0, "grok_execution")["prompt_sha256"] = Digest::SHA256.hexdigest(prompt)
    write_manifest(manifest)
    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(
        root: @root,
        manifest_path: @manifest_path,
        manifest: manifest,
        cue_id: "03VCUE_DUMMY_01"
      )
    end
    assert_match(/unattached @image4/, error.message)
    assert_equal prompt, manifest.dig("cues", 0, "prompt_text")
  end

  def test_i2v_package_exact_copies_one_selected_input_and_keeps_founder_hold
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    write_manifest(manifest)

    plan = IdolGrokVideoExecutionPackage.plan!(
      root: @root,
      manifest_path: @manifest_path,
      manifest: manifest,
      cue_id: "03VCUE_DUMMY_01"
    )

    assert_equal ["CUT_A"], plan.fetch("ordered_inputs").map { |row| row.fetch("production_cut_id") }
    assert_equal "frame_1", plan.dig("ordered_inputs", 0, "role")
    assert_equal false, plan["external_execution_ready"]
    assert_includes plan["execution_hold_reasons"], "founder_external_video_authority_missing"
    refute plan["execution_hold_reasons"].any? { |reason| reason.start_with?("provider_video_harness_") }

    result = IdolGrokVideoExecutionPackage.materialize!(
      root: @root,
      plan: plan,
      package_root: @temporary.join("packages")
    )
    package = Pathname.new(result.fetch("package_path"))
    assert_equal "prepared_with_holds", result["package_status"]
    assert_equal manifest.dig("cues", 0, "prompt_text"), package.join("prompt.txt").read
    assert_equal rows[0]["sha256"], Digest::SHA256.file(package.join("input-01.png")).hexdigest
    package_plan = JSON.parse(package.join("package-plan.json").read)
    assert_equal "03VCUE_DUMMY_01.mp4", package_plan.dig("operator_package", "expected_output_filename")
    assert_equal "scripts/idol_03v_import_generated_clips.rb", package_plan.dig("operator_package", "collector")
    assert_nil package_plan["prompt_text"]
    assert_equal Digest::SHA256.file(package.join("package-plan.json")).hexdigest, result["package_plan_sha256"]
    duplicate = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.materialize!(
        root: @root,
        plan: plan,
        package_root: @temporary.join("packages")
      )
    end
    assert_match(/overwrite is forbidden/, duplicate.message)
  end

  def test_active_registered_lane_becomes_ready_only_with_cdd_pass_and_founder_authority
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    manifest["status"] = "passed"
    manifest.dig("section_shards", 0)["status"] = "passed"
    manifest.dig("cues", 0, "grok_execution")["founder_generation_authority_id"] = "FOUNDER_VIDEO_AUTH_DUMMY"
    write_manifest(manifest)

    plan = IdolGrokVideoExecutionPackage.plan!(
      root: @root,
      manifest_path: @manifest_path,
      manifest: manifest,
      cue_id: "03VCUE_DUMMY_01"
    )

    assert_equal "active", plan["provider_video_harness_status"]
    assert_equal true, plan["external_execution_ready"]
    assert_equal [], plan["execution_hold_reasons"]
    assert_equal false, plan["external_call_performed"]
  end

  def test_reference_to_video_preserves_founder_selected_order
    rows = [
      source_row("CUT_A", ".png", "first-pixel"),
      source_row("CUT_B", ".jpg", "second-pixel"),
      source_row("CUT_C", ".webp", "third-pixel")
    ]
    manifest = manifest_for(rows: rows, tool: "reference_to_video")
    write_manifest(manifest)
    plan = IdolGrokVideoExecutionPackage.plan!(root: @root, manifest_path: @manifest_path, manifest: manifest, cue_id: "03VCUE_DUMMY_01")
    assert_equal %w[CUT_A CUT_B CUT_C], plan["ordered_inputs"].map { |row| row["production_cut_id"] }
    assert_equal %w[reference_1 reference_2 reference_3], plan["ordered_inputs"].map { |row| row["role"] }

    manifest.dig("cues", 0, "grok_execution", "founder_reference_selection", "selected_image_ids_in_order").reverse!
    with_error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(root: @root, manifest_path: @manifest_path, manifest: manifest, cue_id: "03VCUE_DUMMY_01")
    end
    assert_match(/exact Founder-selected/, with_error.message)
  end

  def test_stale_provider_profile_binding_is_rejected_before_packaging
    row = source_row("CUT_A", ".png", "first-pixel")
    manifest = manifest_for(rows: [row], tool: "image_to_video")
    manifest.dig("cues", 0, "grok_execution")["provider_profile_sha256"] = "0" * 64
    write_manifest(manifest)
    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.plan!(root: @root, manifest_path: @manifest_path, manifest: manifest, cue_id: "03VCUE_DUMMY_01")
    end
    assert_match(/provider_profile_sha256 differs/, error.message)
  end

  def test_run_owned_package_rejects_parent_symlink_escape
    rows = [source_row("CUT_A", ".png", "first-pixel")]
    manifest = manifest_for(rows: rows, tool: "image_to_video")
    write_manifest(manifest)
    plan = IdolGrokVideoExecutionPackage.plan!(root: @root, manifest_path: @manifest_path, manifest: manifest, cue_id: "03VCUE_DUMMY_01")
    execution_root = @root.join(plan.dig("operator_package", "execution_package_root"))
    execution_root.mkpath
    outside = @temporary.join("outside-package-root")
    outside.mkpath
    File.symlink(outside, execution_root.join("escape"))

    error = assert_raises(IdolGrokVideoExecutionPackage::ContractError) do
      IdolGrokVideoExecutionPackage.materialize!(
        root: @root,
        plan: plan,
        package_root: execution_root.join("escape", "nested")
      )
    end
    assert_match(/escapes its allowed boundary through a symlink/, error.message)
  end

  private

  def write_provider_sources
    @provider_path = @root.join("automation/providers/grok-build-profiles.yaml")
    @provider_path.write(YAML.dump(
      "media_capabilities" => {
        "video_subscription_cli" => {
          "auth_lane" => "subscription_oauth",
          "capability_status" => "founder_verified",
          "harness_status" => "active",
          "adapter_id" => "grok_build_video",
          "tools" => %w[image_to_video reference_to_video],
          "direct_image_to_video" => "forbidden",
          "prompt_rewrite_policy" => "forbidden",
          "automatic_fallback" => "none",
          "output_contract" => "exact_expected_output_path_sha256_playback_review",
          "local_output_required" => true,
          "current_assignment_inventory_or_adapter_match_required" => true,
          "cue_specific_founder_external_generation_authority_required" => true,
          "allowed_durations_seconds" => [6, 10],
          "allowed_resolutions" => %w[480p 720p],
          "resolution_1080p" => "rejected"
        }
      }
    ))
    provider_sha = Digest::SHA256.file(@provider_path).hexdigest
    @registry_path = @root.join("automation/harness-provider-profile-registry.yaml")
    @registry_path.write(YAML.dump(
      "media_lanes" => {
        "grok_build_oauth_subscription" => {
          "provider" => "grok",
          "auth_lane" => "subscription_oauth",
          "capability_status" => "founder_verified",
          "image_harness_status" => "active",
          "video_harness_status" => "active",
          "provider_profile_id" => "grok_worker_high",
          "provider_profile_source" => "automation/providers/grok-build-profiles.yaml",
          "provider_profile_source_sha256" => provider_sha,
          "video_tools" => %w[image_to_video reference_to_video],
          "video_adapter_id" => "grok_build_video",
          "video_output_contract" => "exact_expected_output_path_sha256_playback_review",
          "video_local_output_required" => true,
          "video_runtime_inventory_or_adapter_match_required" => true,
          "video_founder_external_generation_authority_required" => true,
          "direct_image_to_video" => "forbidden",
          "video_prompt_rewrite_policy" => "forbidden",
          "video_durations_seconds" => [6, 10],
          "resolutions" => %w[480p 720p],
          "resolution_1080p" => "rejected",
          "automatic_fallback" => "none"
        }
      }
    ))
    @provider_sha = provider_sha
  end

  def source_row(id, extension, bytes)
    path = @run.join("pixels", "#{id.downcase}#{extension}")
    path.binwrite(bytes)
    {
      "production_cut_id" => id,
      "production_cut_type" => id == "CUT_A" ? "official_core" : "branch",
      "path" => path.relative_path_from(@root).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "pixel_review_status" => "passed_production_cut"
    }
  end

  def manifest_for(rows:, tool:)
    prompt = "Move only through the reviewed route and land on the declared endpoint."
    ids = rows.map { |row| row["production_cut_id"] }
    additional = tool == "reference_to_video" ? ids.drop(1) : []
    selection = if tool == "reference_to_video"
                  {
                    "selection_id" => "FOUNDER_SELECTION_DUMMY",
                    "selected_image_ids_in_order" => ids,
                    "decision" => "selected_for_reference_to_video",
                    "founder_authored" => true
                  }
                end
    {
      "schema_version" => "idol_video_prompt_manifest.v7",
      "status" => "ready_for_cdd_review",
      "run_root" => @run.relative_path_from(@root).to_s,
      "canonical_video_prompt_output_root" => @run.join("generations/video-prompts").relative_path_from(@root).to_s,
      "section_shards" => [{"section_id" => "S01", "cue_ids" => ["03VCUE_DUMMY_01"], "status" => "ready_for_cdd_review"}],
      "cues" => [{
        "cue_id" => "03VCUE_DUMMY_01",
        "section_id" => "S01",
        "prompt_text" => prompt,
        "source_production_cut_images" => rows,
        "grok_execution" => {
          "video_job_id" => "VIDJOB_DUMMY_01",
          "direct_image_to_video" => "forbidden",
          "source_stage" => "passed_03v",
          "source_production_cut_id" => ids.first,
          "source_production_cut_type" => rows.first["production_cut_type"],
          "source_image_path" => rows.first["path"],
          "source_image_sha256" => rows.first["sha256"],
          "source_image_frame_count" => 1,
          "source_image_review_status" => "passed_production_cut",
          "prompt_source" => "exact_03v_rendered_prompt",
          "prompt_rewrite_policy" => "forbidden",
          "selected_tool" => tool,
          "additional_reference_image_ids" => additional,
          "founder_reference_selection" => selection,
          "prompt_sha256" => Digest::SHA256.hexdigest(prompt),
          "requested_duration_seconds" => 6,
          "requested_aspect_ratio" => "16:9",
          "requested_resolution" => "480p",
          "resolution_pass" => "480p_test",
          "selected_adapter_id" => "grok_build_video",
          "auth_lane" => "grok_build_oauth",
          "provider_profile_id" => "grok_worker_high",
          "provider_profile_sha256" => @provider_sha,
          "automatic_fallback" => "none",
          "founder_generation_authority_id" => nil
        }
      }]
    }
  end

  def write_manifest(manifest)
    @manifest_path.write(YAML.dump(manifest))
  end
end
