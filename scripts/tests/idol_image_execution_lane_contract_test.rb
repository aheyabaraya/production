# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"

require_relative "../lib/idol_image_execution_lane_contract"

class IdolImageExecutionLaneContractTest < Minitest::Test
  def setup
    @root = Pathname.new(Dir.mktmpdir("idol-image-lane-contract-", "/private/tmp"))
    @providers = @root.join("automation/providers")
    @providers.mkpath
    @codex_path = @providers.join("codex-native-media-profiles.yaml")
    @grok_path = @providers.join("grok-build-profiles.yaml")
    write_yaml(@codex_path, {
      "profiles" => {
        "codex_current_session_imagegen" => {
          "execution_adapter_id" => "codex_imagegen",
          "provider_model_or_tool" => "codex_imagegen",
          "selected_native_tool" => "imagegen",
          "auth_lane" => "codex_session",
          "current_session_binding_required" => true,
          "exact_tool_inventory_required" => true
        }
      }
    })
    write_yaml(@grok_path, {
      "media_capabilities" => {
        "image_subscription_cli" => {
          "adapter_id" => "grok_image",
          "auth_lane" => "subscription_oauth",
          "tools" => %w[image_edit image_gen],
          "automatic_fallback" => "none"
        }
      }
    })
    @registry_path = @root.join("automation/harness-provider-profile-registry.yaml")
    write_registry
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.directory?
  end

  def test_provider_omitted_codex_uses_only_current_codex_imagegen
    selection = selection_for("codex")
    execution = execution_for("codex")

    result = verify(selection, execution, 0)

    assert_equal "codex_imagegen", result.fetch("adapter")
    assert_equal "codex", result.fetch("creative_provider")
    assert_equal "codex_session_native", result.fetch("lane")
  end

  def test_provider_omitted_grok_selects_native_generation_or_edit_by_attachments
    selection = selection_for("grok_build")

    generated = verify(selection, execution_for("grok_build", attachment_count: 0), 0)
    edited = verify(selection, execution_for("grok_build", attachment_count: 2), 2)

    assert_equal "grok_image", generated.fetch("adapter")
    assert_equal "grok_build", generated.fetch("creative_provider")
    assert_equal "grok_image", edited.fetch("adapter")
  end

  def test_current_session_native_rejects_cross_provider_assignment_alias
    selection = selection_for("codex").merge("creative_role_provider" => "grok_build")

    error = assert_raises(IdolImageExecutionLaneContract::ContractError) do
      verify(selection, execution_for("codex"), 0)
    end

    assert_includes error.message, "exact current creative assignment provider"
  end

  def test_current_session_native_rejects_cross_provider_tool_alias
    execution = execution_for("codex").merge(
      "execution_adapter_id" => "grok_image",
      "provider" => "xai_grok_build",
      "provider_model_or_tool" => "grok_image",
      "selected_native_tool" => "image_gen",
      "auth_lane" => "subscription_oauth"
    )

    error = assert_raises(IdolImageExecutionLaneContract::ContractError) do
      verify(selection_for("codex"), execution, 0)
    end

    assert_includes error.message, "adapter differs"
  end

  def test_explicit_api_selection_remains_explicit_and_never_becomes_session_native
    selection = selection_for("codex").merge(
      "image_execution_request" => "openai_api_gpt_image_2",
      "image_execution_request_origin" => "founder_explicit",
      "image_execution_lane" => "openai_api_gpt_image_2"
    )
    execution = base_execution.merge(
      "execution_adapter_id" => "openai_api_gpt_image_2",
      "provider" => "openai",
      "provider_model_or_tool" => "gpt-image-2",
      "selected_native_tool" => nil,
      "auth_lane" => "founder_approved_api"
    )

    result = IdolImageExecutionLaneContract.verify_execution_shape!(
      selection: selection,
      execution: execution,
      attachment_count: 0
    )

    assert_equal "openai_api_gpt_image_2", result.fetch("lane")
  end

  def test_native_profile_source_sha_drift_holds_without_fallback
    File.open(@codex_path, "a") { |file| file.write("\n# drift\n") }

    error = assert_raises(IdolImageExecutionLaneContract::ContractError) do
      verify(selection_for("codex"), execution_for("codex"), 0)
    end

    assert_includes error.message, "source SHA-256 is stale"
  end

  private

  def write_yaml(path, value)
    path.dirname.mkpath
    path.write(YAML.dump(value))
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def write_registry
    write_yaml(@registry_path, {
      "media_lanes" => {
        "codex_session_native" => {
          "capability_status" => "active",
          "harness_status" => "active",
          "provider_profile_id" => "codex_current_session_imagegen",
          "provider_profile_source" => "automation/providers/codex-native-media-profiles.yaml",
          "provider_profile_source_sha256" => sha(@codex_path),
          "image_adapter_id" => "codex_imagegen",
          "default_enabled" => true,
          "native_default_scope" => "exact_current_assignment_provider_only",
          "current_session_provider_match_required" => true,
          "cross_provider_tool_aliasing" => "forbidden",
          "automatic_fallback" => "none"
        },
        "grok_build_oauth_subscription" => {
          "capability_status" => "founder_verified",
          "image_harness_status" => "active",
          "provider_profile_id" => "grok_worker_high",
          "provider_profile_source" => "automation/providers/grok-build-profiles.yaml",
          "provider_profile_source_sha256" => sha(@grok_path),
          "image_adapter_id" => "grok_image",
          "default_enabled" => true,
          "native_default_scope" => "exact_current_assignment_provider_only",
          "current_session_provider_match_required" => true,
          "cross_provider_tool_aliasing" => "forbidden",
          "automatic_fallback" => "none"
        }
      }
    })
  end

  def selection_for(provider)
    {
      "creative_role_provider" => provider,
      "image_execution_request" => "current_session_native",
      "image_execution_request_origin" => "founder_omitted_current_session_default",
      "image_execution_session_provider" => provider,
      "image_execution_lane" => provider == "codex" ? "codex_session_native" : "grok_build_oauth_subscription",
      "video_execution_lane" => "other_registered",
      "automatic_fallback" => "none"
    }
  end

  def base_execution
    {
      "prompt_rewrite_policy" => "forbidden",
      "automatic_fallback" => "none",
      "provider_profile_id" => "not_used_by_api_shape_test",
      "provider_profile_sha256" => "0" * 64,
      "provider_capability_snapshot_sha256" => "1" * 64
    }
  end

  def execution_for(provider, attachment_count: 0)
    if provider == "codex"
      base_execution.merge(
        "execution_adapter_id" => "codex_imagegen",
        "provider" => "codex",
        "provider_model_or_tool" => "codex_imagegen",
        "selected_native_tool" => "imagegen",
        "auth_lane" => "codex_session",
        "provider_profile_id" => "codex_current_session_imagegen",
        "provider_profile_sha256" => sha(@codex_path),
        "provider_capability_snapshot_sha256" => sha(@registry_path)
      )
    else
      base_execution.merge(
        "execution_adapter_id" => "grok_image",
        "provider" => "xai_grok_build",
        "provider_model_or_tool" => "grok_image",
        "selected_native_tool" => attachment_count.positive? ? "image_edit" : "image_gen",
        "auth_lane" => "subscription_oauth",
        "provider_profile_id" => "grok_worker_high",
        "provider_profile_sha256" => sha(@grok_path),
        "provider_capability_snapshot_sha256" => sha(@registry_path)
      )
    end
  end

  def verify(selection, execution, attachment_count)
    IdolImageExecutionLaneContract.verify_registered_native_profile!(
      root: @root,
      selection: selection,
      execution: execution,
      attachment_count: attachment_count,
      registry_path: @registry_path
    )
  end
end
