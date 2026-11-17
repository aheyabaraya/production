# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"

require_relative "../lib/idol_graph_provider_binding_contract"

class IdolGraphProviderBindingContractTest < Minitest::Test
  def setup
    @root = Pathname.new(Dir.mktmpdir("idol-graph-provider-binding-", "/private/tmp"))
    @providers = @root.join("automation/providers")
    @providers.mkpath
    @grok_path = @providers.join("grok-build-profiles.yaml")
    @cursor_path = @providers.join("cursor-agent-profiles.yaml")
    write_yaml(@grok_path, grok_source)
    write_yaml(@cursor_path, cursor_source)
    @registry_path = @root.join("automation/harness-provider-profile-registry.yaml")
    write_registry
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.directory?
  end

  def test_resolves_exact_grok_frontier_director
    result = resolve(binding_for("frontier_director", "grok", "grok_director_frontier"), "planning_cdd")

    assert_equal "grok-4.6", result.fetch("resolved_provider_model")
    assert_equal "xhigh", result.fetch("reasoning_effort")
    assert_equal "creative_development_director", result.fetch("normalized_logical_role")
    assert_equal sha(@grok_path), result.fetch("provider_profile_source_sha256")
    assert_equal sha(@registry_path), result.fetch("provider_capability_snapshot_sha256")
  end

  def test_resolves_exact_grok_worker_high
    result = resolve(binding_for("worker_high", "grok", "grok_worker_high"), "section_image_motion_worker")

    assert_equal "grok_worker_high", result.fetch("execution_profile_id")
    assert_equal "high", result.fetch("reasoning_effort")
    assert_equal true, result.fetch("full_owner_ready")
  end

  def test_graph_department_worker_maps_to_provider_worker_role_at_worker_high
    result = resolve(binding_for("worker_high", "grok", "grok_worker_high"), "department_worker")

    assert_equal "worker", result.fetch("normalized_logical_role")
  end

  def test_cursor_active_text_only_is_valid_for_text_worker
    result = resolve(binding_for("worker_high", "cursor", "cursor_luna_max"), "worker")

    assert_equal "active_text_only", result.fetch("harness_status")
    assert_equal "cursor_cli_local_physical_chat", result.fetch("runtime_surface")
  end

  def test_rejects_direct_codex_provider
    error = assert_contract_error("direct_codex_forbidden") do
      resolve(binding_for("frontier_director", "codex", "codex_director"), "overall_director")
    end

    assert_includes error.message, "direct Codex"
  end

  def test_rejects_unknown_provider
    assert_contract_error("unknown_provider") do
      resolve(binding_for("frontier_director", "openai", "made_up"), "overall_director")
    end
  end

  def test_rejects_unknown_logical_alias
    assert_contract_error("unknown_logical_profile_alias") do
      resolve(binding_for("fabricated_alias", "grok", "grok_director_frontier"), "overall_director")
    end
  end

  def test_rejects_fabricated_execution_profile
    assert_contract_error("binding_mismatch") do
      resolve(binding_for("frontier_director", "grok", "fabricated_profile"), "overall_director")
    end
  end

  def test_rejects_registry_profile_that_does_not_exist_in_provider_source
    registry = YAML.safe_load(@registry_path.read)
    registry["logical_profiles"]["frontier_director"]["providers"]["grok"]["provider_profile_id"] = "missing_profile"
    write_yaml(@registry_path, registry)

    assert_contract_error("unknown_provider_profile") do
      resolve(binding_for("frontier_director", "grok", "missing_profile"), "overall_director")
    end
  end

  def test_rejects_exact_model_mismatch
    binding = binding_for("worker_high", "grok", "grok_worker_high")
    binding["resolved_provider_model"] = "grok-fabricated"

    assert_contract_error("binding_mismatch") { resolve(binding, "worker") }
  end

  def test_rejects_reasoning_effort_mismatch
    binding = binding_for("worker_high", "grok", "grok_worker_high")
    binding["reasoning_effort"] = "medium"

    assert_contract_error("binding_mismatch") { resolve(binding, "worker") }
  end

  def test_rejects_stale_provider_source_hash
    File.open(@grok_path, "a") { |file| file.write("\n# source drift\n") }

    assert_contract_error("stale_provider_source_sha") do
      resolve(binding_for("worker_high", "grok", "grok_worker_high"), "worker")
    end
  end

  def test_rejects_stale_registry_capability_snapshot_hash
    binding = binding_for("worker_high", "grok", "grok_worker_high")
    binding["provider_capability_snapshot_sha256"] = "f" * 64

    assert_contract_error("binding_mismatch") { resolve(binding, "worker") }
  end

  def test_rejects_hold_profile
    assert_contract_error("profile_not_founder_verified") do
      resolve(binding_for("research_medium", "grok", "grok_worker_medium"), "research_worker")
    end
  end

  def test_rejects_active_text_only_profile_for_section_media_owner
    assert_contract_error("profile_not_active_for_role") do
      resolve(binding_for("worker_high", "cursor", "cursor_luna_max"), "section_image_motion_worker")
    end
  end

  def test_rejects_director_profile_without_full_owner_readiness
    assert_contract_error("director_full_owner_not_ready") do
      resolve(binding_for("frontier_director", "cursor", "cursor_grok_46_xhigh"), "edit_director")
    end
  end

  private

  def resolve(binding, role)
    IdolGraphProviderBindingContract.resolve!(
      root: @root,
      registry_path: @registry_path,
      binding: binding,
      studio_role: role
    )
  end

  def assert_contract_error(code)
    error = assert_raises(IdolGraphProviderBindingContract::ContractError) { yield }
    assert_equal code, error.code
    error
  end

  def write_yaml(path, value)
    path.dirname.mkpath
    path.write(YAML.dump(value))
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def binding_for(logical_alias, provider, profile_id)
    source = provider == "cursor" ? cursor_source : grok_source
    profile = source.dig("profiles", profile_id) || {}
    {
      "registered_provider" => provider,
      "runtime_surface" => source["runtime_surface"],
      "logical_profile_alias" => logical_alias,
      "execution_profile_id" => profile_id,
      "resolved_provider_model" => profile["exact_model"] || "fixture-model",
      "reasoning_effort" => profile["reasoning_effort"] || "fixture-effort",
      "provider_capability_snapshot_sha256" => sha(@registry_path),
      "fallback_allowed" => false,
      "silent_substitution_allowed" => false
    }
  end

  def grok_source
    {
      "schema_version" => "idol-grok-build-provider-profiles.v1",
      "status" => "active",
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "profiles" => {
        "grok_director_frontier" => profile("grok-4.6", "xhigh", %w[overall_director creative_development_director edit_director]),
        "grok_worker_high" => profile("grok-4.6", "high", %w[worker mechanical_coordinator section_image_motion_worker]),
        "grok_worker_medium" => profile(
          "grok-4.6",
          "medium",
          %w[research_worker department_worker],
          capability_status: "hold",
          harness_status: "hold",
          full_owner_ready: false
        )
      }
    }
  end

  def cursor_source
    {
      "schema_version" => "idol-cursor-agent-provider-profiles.v2",
      "status" => "active_with_assignment_holds",
      "provider" => "cursor",
      "runtime_surface" => "cursor_cli_local_physical_chat",
      "profiles" => {
        "cursor_grok_46_xhigh" => profile(
          "cursor-grok-4.6-xhigh",
          "xhigh",
          %w[department_worker overall_director creative_development_director edit_director],
          full_owner_ready: false
        ),
        "cursor_luna_max" => profile(
          "gpt-5.6-luna-max",
          "max",
          %w[worker mechanical_coordinator section_image_motion_worker],
          harness_status: "active_text_only"
        )
      }
    }
  end

  def profile(model, effort, roles, capability_status: "founder_verified", harness_status: "active", full_owner_ready: true)
    {
      "exact_model" => model,
      "reasoning_effort" => effort,
      "eligible_logical_roles" => roles,
      "capability_status" => capability_status,
      "harness_status" => harness_status,
      "full_owner_ready" => full_owner_ready,
      "unavailable_or_mismatch_action" => "hold_and_report"
    }
  end

  def write_registry
    write_yaml(@registry_path, {
      "logical_profiles" => {
        "frontier_director" => {
          "eligible_logical_roles" => %w[overall_director creative_development_director edit_director],
          "providers" => {
            "grok" => registration(@grok_path, "grok_director_frontier", grok_source.dig("profiles", "grok_director_frontier")),
            "cursor" => registration(@cursor_path, "cursor_grok_46_xhigh", cursor_source.dig("profiles", "cursor_grok_46_xhigh"))
          }
        },
        "worker_high" => {
          "eligible_logical_roles" => %w[worker mechanical_coordinator section_image_motion_worker],
          "providers" => {
            "grok" => registration(@grok_path, "grok_worker_high", grok_source.dig("profiles", "grok_worker_high")),
            "cursor" => registration(@cursor_path, "cursor_luna_max", cursor_source.dig("profiles", "cursor_luna_max"))
          }
        },
        "research_medium" => {
          "eligible_logical_roles" => %w[research_worker department_worker],
          "providers" => {
            "grok" => registration(@grok_path, "grok_worker_medium", grok_source.dig("profiles", "grok_worker_medium"))
          }
        }
      }
    })
  end

  def registration(path, profile_id, profile)
    {
      "source_kind" => "provider_yaml",
      "source_path" => path.relative_path_from(@root).to_s,
      "source_sha256" => sha(path),
      "provider_profile_id" => profile_id,
      "capability_status" => profile["capability_status"],
      "harness_status" => profile["harness_status"],
      "full_owner_ready" => profile["full_owner_ready"]
    }
  end
end
