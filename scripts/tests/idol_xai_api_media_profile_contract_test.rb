# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/idol_xai_api_media_profile_contract"

class IdolXaiApiMediaProfileContractTest < Minitest::Test
  def test_schema_validator_child_environment_unsets_provider_credentials
    assert_equal(
      {"OPENAI_API_KEY" => nil, "XAI_API_KEY" => nil},
      IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV
    )
  end

  def test_nonsecret_child_environment_removes_inherited_provider_credentials
    original_openai = ENV["OPENAI_API_KEY"]
    original_xai = ENV["XAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "fixture-openai-secret"
    ENV["XAI_API_KEY"] = "fixture-xai-secret"
    stdout, stderr, status = Open3.capture3(
      IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV,
      RbConfig.ruby,
      "-e",
      "print [ENV.key?('OPENAI_API_KEY'), ENV.key?('XAI_API_KEY')].join(',')"
    )
    assert status.success?, stderr
    assert_equal "false,false", stdout
  ensure
    original_openai.nil? ? ENV.delete("OPENAI_API_KEY") : ENV["OPENAI_API_KEY"] = original_openai
    original_xai.nil? ? ENV.delete("XAI_API_KEY") : ENV["XAI_API_KEY"] = original_xai
  end

  def with_fixture_root
    Dir.mktmpdir("idol-xai-profile-", "/private/tmp") do |directory|
      root = Pathname.new(directory)
      root.join("automation/providers").mkpath
      yield root
    end
  end

  def profile_document
    response = {
      "image_encoding" => "base64_json",
      "exact_output_count" => 1,
      "items_json_pointer" => "/data",
      "image_value_json_pointer" => "/b64_json",
      "output_url_allowed_hosts" => []
    }
    {
      "schema_version" => "idol-xai-api-media-provider-profiles.v1",
      "status" => "active",
      "provider" => "xai_api",
      "runtime_surface" => "xai_media_api",
      "profile_source_policy" => {
        "exact_model_owner" => "this_file",
        "exact_endpoint_owner" => "this_file",
        "resolved_snapshot_required" => true,
        "requested_observed_match_required" => true,
        "silent_model_or_auth_fallback" => "forbidden"
      },
      "profiles" => {
        "xai_fixture_image_current" => {
          "exact_model" => "fixture-xai-image-model",
          "image_adapter_id" => "xai_api_media",
          "auth_lane" => "founder_approved_api",
          "api_version" => "fixture-api-v1",
          "api_base_url" => "https://xai-fixture.invalid",
          "authorization_scheme" => "bearer",
          "capability_status" => "active",
          "harness_status" => "active",
          "default_enabled" => false,
          "automatic_fallback" => "none",
          "unavailable_or_mismatch_action" => "hold_and_report",
          "operations" => {
            "image_gen" => {
              "endpoint_path" => "/fixture/v1/images/generations",
              "transport" => "json",
              "attachment_policy" => "forbidden",
              "request_contract" => {
                "model_field" => "model",
                "prompt_field" => "prompt",
                "output_count_field" => "n",
                "attachment_field" => nil,
                "fixed_fields" => {"quality" => "fixture"}
              },
              "response_contract" => response.dup
            },
            "image_edit" => {
              "endpoint_path" => "/fixture/v1/images/edits",
              "transport" => "json_data_url_array",
              "attachment_policy" => "required_all_ordered",
              "request_contract" => {
                "model_field" => "model",
                "prompt_field" => "prompt",
                "output_count_field" => "n",
                "attachment_field" => "images",
                "fixed_fields" => {"quality" => "fixture"}
              },
              "response_contract" => response.dup
            }
          }
        }
      }
    }
  end

  def write_registered_fixture(root)
    profile_path = root.join("automation/providers/xai-fixture.json")
    profile_path.write(JSON.generate(profile_document))
    profile_sha = Digest::SHA256.file(profile_path).hexdigest
    registry_path = root.join("automation/harness-provider-profile-registry.json")
    registry = {
      "media_lanes" => {
        "xai_api_media" => {
          "provider" => "xai",
          "auth_lane" => "founder_approved_api",
          "capability_status" => "active",
          "harness_status" => "active",
          "registration_status" => "registered_exact",
          "provider_profile_id" => "xai_fixture_image_current",
          "provider_profile_source" => "automation/providers/xai-fixture.json",
          "provider_profile_source_sha256" => profile_sha,
          "image_adapter_id" => "xai_api_media",
          "image_output_contract" => "exact_expected_output_path_sha256_pixel_review",
          "default_enabled" => false,
          "selection_only" => false,
          "automatic_fallback" => "none"
        }
      }
    }
    registry_path.write(JSON.generate(registry))
    execution = {
      "execution_adapter_id" => "xai_api_media",
      "provider" => "xai_api",
      "provider_model_or_tool" => "fixture-xai-image-model",
      "selected_native_tool" => nil,
      "auth_lane" => "founder_approved_api",
      "provider_profile_id" => "xai_fixture_image_current",
      "provider_profile_sha256" => profile_sha,
      "provider_capability_snapshot_sha256" => Digest::SHA256.file(registry_path).hexdigest,
      "cli_or_api_version" => "fixture-api-v1",
      "automatic_fallback" => "none"
    }
    [registry_path, profile_path, registry, execution]
  end

  def write_registration_required_fixture(root)
    registry_path = root.join("automation/harness-provider-profile-registry.json")
    registry_path.write(
      JSON.generate(
        "media_lanes" => {
          "xai_api_media" => {
            "provider" => "xai",
            "auth_lane" => "founder_approved_api",
            "capability_status" => "registration_required",
            "harness_status" => "hold",
            "registration_status" => "registration_required",
            "default_enabled" => false,
            "selection_only" => false,
            "automatic_fallback" => "none"
          }
        }
      )
    )
    registry_path
  end

  def ready_request(execution, attachments: [])
    {
      "status" => "ready",
      "hold_reasons" => [],
      "execution" => execution,
      "attachments" => attachments
    }
  end

  def test_registered_exact_branch_resolves_generation_and_edit
    with_fixture_root do |root|
      registry_path, _profile_path, _registry, execution = write_registered_fixture(root)
      generation = IdolXaiApiMediaProfileContract.verify!(
        root: root,
        registry_path: registry_path,
        execution: execution,
        attachment_count: 0
      )
      edit = IdolXaiApiMediaProfileContract.verify!(
        root: root,
        registry_path: registry_path,
        execution: execution,
        attachment_count: 2
      )
      assert_equal "image_gen", generation.fetch("operation_id")
      assert_equal "/fixture/v1/images/edits", edit.fetch("endpoint_path")
    end
  end

  def test_registration_required_branch_holds_without_profile_fields
    with_fixture_root do |root|
      registry_path = write_registration_required_fixture(root)
      error = assert_raises(IdolXaiApiMediaProfileContract::ContractError) do
        IdolXaiApiMediaProfileContract.verify!(
          root: root,
          registry_path: registry_path,
          execution: {},
          attachment_count: 0
        )
      end
      assert_includes error.message, "registration_required HOLD"
    end
  end

  def test_ready_request_resolves_only_against_current_registered_exact_snapshot
    with_fixture_root do |root|
      registry_path, _profile_path, _registry, execution = write_registered_fixture(root)
      registration = IdolXaiApiMediaProfileContract.verify_request!(
        root: root,
        registry_path: registry_path,
        request: ready_request(execution)
      )
      assert_equal "image_gen", registration.fetch("operation_id")
      assert_equal Digest::SHA256.file(registry_path).hexdigest, registration.fetch("registry_sha256")
    end
  end

  def test_handwritten_ready_request_holds_while_current_lane_requires_registration
    with_fixture_root do |root|
      registry_path = write_registration_required_fixture(root)
      execution = {
        "execution_adapter_id" => "xai_api_media",
        "provider" => "xai_api",
        "provider_model_or_tool" => "handwritten-model",
        "selected_native_tool" => nil,
        "auth_lane" => "founder_approved_api",
        "provider_profile_id" => "handwritten-profile",
        "provider_profile_sha256" => "a" * 64,
        "provider_capability_snapshot_sha256" => Digest::SHA256.file(registry_path).hexdigest,
        "cli_or_api_version" => "handwritten-version",
        "automatic_fallback" => "none"
      }
      error = assert_raises(IdolXaiApiMediaProfileContract::ContractError) do
        IdolXaiApiMediaProfileContract.verify_request!(
          root: root,
          registry_path: registry_path,
          request: ready_request(execution)
        )
      end
      assert_includes error.message, "registration_required HOLD"
      assert_includes error.message, "no fallback"
    end
  end

  def test_request_with_hold_reason_cannot_resolve_even_against_registered_profile
    with_fixture_root do |root|
      registry_path, _profile_path, _registry, execution = write_registered_fixture(root)
      request = ready_request(execution)
      request["hold_reasons"] = ["founder approval missing"]
      error = assert_raises(IdolXaiApiMediaProfileContract::ContractError) do
        IdolXaiApiMediaProfileContract.verify_request!(root: root, registry_path: registry_path, request: request)
      end
      assert_includes error.message, "not exact ready"
    end
  end

  def test_active_lifecycle_callers_bind_every_xai_boundary_and_sanitize_schema_children
    scripts_root = Pathname.new(__dir__).join("..").expand_path
    selection = scripts_root.join("idol_image_generation_request_selection.rb").read
    worklist = scripts_root.join("idol_image_generation_section_worklist.rb").read
    dispatch = scripts_root.join("idol_image_generation_dispatch.rb").read

    [selection, worklist, dispatch].each do |source|
      assert_includes source, "IdolXaiApiMediaProfileContract::NONSECRET_CHILD_ENV"
      refute_match(/Open3\.capture3\(PYTHON\.to_s/, source)
    end
    assert_includes selection, "IdolXaiApiMediaProfileContract.verify_request!"
    assert_includes selection, "cannot enter active selection"
    assert_includes worklist, "IdolXaiApiMediaProfileContract.verify_request!"
    assert_includes worklist, "cannot become ready"
    %w[
      dispatch\ init
      dispatch\ pre-claim
      dispatch\ pre-record
      dispatch\ pre-inspect/receipt-validation
    ].each { |boundary| assert_includes dispatch, boundary.gsub("\\ ", " ") }
    assert_operator dispatch.scan("verify_current_xai_snapshot!").length, :>=, 5
  end

  def test_stale_profile_source_hash_holds
    with_fixture_root do |root|
      registry_path, profile_path, _registry, execution = write_registered_fixture(root)
      profile_path.write(profile_path.read + "\n")
      error = assert_raises(IdolXaiApiMediaProfileContract::ContractError) do
        IdolXaiApiMediaProfileContract.verify!(
          root: root,
          registry_path: registry_path,
          execution: execution,
          attachment_count: 0
        )
      end
      assert_includes error.message, "source SHA-256 is stale"
    end
  end

  def test_model_mismatch_holds
    with_fixture_root do |root|
      registry_path, _profile_path, _registry, execution = write_registered_fixture(root)
      execution["provider_model_or_tool"] = "different-model"
      error = assert_raises(IdolXaiApiMediaProfileContract::ContractError) do
        IdolXaiApiMediaProfileContract.verify!(
          root: root,
          registry_path: registry_path,
          execution: execution,
          attachment_count: 0
        )
      end
      assert_includes error.message, "provider_model_or_tool differs"
    end
  end

  def test_registry_fallback_mismatch_holds
    with_fixture_root do |root|
      registry_path, _profile_path, registry, execution = write_registered_fixture(root)
      registry["media_lanes"]["xai_api_media"]["automatic_fallback"] = "other"
      registry_path.write(JSON.generate(registry))
      execution["provider_capability_snapshot_sha256"] = Digest::SHA256.file(registry_path).hexdigest
      error = assert_raises(IdolXaiApiMediaProfileContract::ContractError) do
        IdolXaiApiMediaProfileContract.verify!(
          root: root,
          registry_path: registry_path,
          execution: execution,
          attachment_count: 0
        )
      end
      assert_includes error.message, "automatic_fallback differs"
    end
  end
end
