#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

class IdolBoundedRegistryClosureTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  CLOSURE = ROOT.join(
    "development",
    "four-day-final-review-20260912",
    "director-parallel",
    "C03",
    "closure-correction",
    "idol_bounded_registry_closure.rb"
  )
  EXAMPLE = ROOT.join(
    "development",
    "four-day-final-review-20260912",
    "director-parallel",
    "C03",
    "closure-correction",
    "accepted-path-manifest.v1.example.json"
  )
  COPY_RELATIVE = %w[
    AGENTS.md
    automation/graph-default-routing.yaml
    automation/graph-skill-load-profiles.yaml
    automation/graph-role-context-projection.yaml
    automation/harness-role-context-projection.yaml
    automation/harness-skill-load-profiles.yaml
    automation/harness-execution-contract.yaml
    automation/harness-surface-version-registry.yaml
    automation/harness-provider-profile-registry.yaml
    automation/providers/grok-build-profiles.yaml
    automation/idol-script-registry.yaml
    schemas/kinetic-change-point-slot-sheet.schema.json
    policies/harness-routing-and-sources.md
    scripts/validate_harness_skill_load_profiles.rb
    scripts/lib/idol_role_context_pack.rb
    scripts/lib/idol_source_connection_contract.rb
    scripts/lib/idol_run_followup_sidecar.rb
    skills/idol-orchestrator/references/provider-neutral-studio-kernel.md
  ].freeze
  HISTORIC = "development/front-planning-workbench/docs/evidence/grok-1.0.3-role-lifecycle-receipt-2026-08-14.json"
  TRACKED = (COPY_RELATIVE + [HISTORIC, "automation/idol-script-registry.yaml"]).uniq.freeze

  def setup
    skip "closure script not applied yet" unless CLOSURE.file?
    skip "manifest shell not applied yet" unless EXAMPLE.file?
  end

  def populate(sandbox)
    COPY_RELATIVE.each do |rel|
      src = ROOT.join(rel)
      next unless src.file?
      dest = sandbox.join(rel)
      dest.dirname.mkpath
      FileUtils.cp(src, dest)
    end
    historic = sandbox.join(HISTORIC)
    historic.dirname.mkpath
    historic.write("{\"historic\":true,\"do_not_rewrite\":true}\n")
  end

  def seed_throwaway_fixtures!(sandbox)
    routing = sandbox.join("automation/graph-default-routing.yaml")
    inserted = "    - scripts/lib/idol_role_context_pack.rb\n    - scripts/lib/idol_source_connection_contract.rb\n    - scripts/lib/idol_run_followup_sidecar.rb\n"
    missing = "    - scripts/lib/idol_role_context_pack.rb\n    - scripts/lib/idol_run_followup_sidecar.rb\n"
    text = routing.read
    routing.write(text.sub(inserted, missing)) if text.include?(inserted)
    grok = sandbox.join("automation/providers/grok-build-profiles.yaml")
    grok_text = grok.read
    unless grok_text.include?("# throwaway-closure-test-drift")
      grok_text += "\n" unless grok_text.end_with?("\n")
      grok.write(grok_text + "# throwaway-closure-test-drift\n")
    end
  end

  def write_manifest(sandbox, reviewed:)
    path = sandbox.join("manifest.json")
    path.write(JSON.pretty_generate({
      "schema_version" => "idol-bounded-registry-closure-manifest.v1",
      "director_reviewed" => reviewed,
      "accepted_paths" => []
    }))
    path
  end

  def run_closure(sandbox, extra, manifest:)
    record = sandbox.join("closure-record.json")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      CLOSURE.to_s,
      "--root",
      sandbox.to_s,
      "--manifest",
      manifest.to_s,
      "--record",
      record.to_s,
      *extra
    )
    [stdout, stderr, status, record]
  end

  def snapshot(sandbox)
    TRACKED.each_with_object({}) do |rel, memo|
      path = sandbox.join(rel)
      memo[rel] = path.file? ? Digest::SHA256.file(path.to_s).hexdigest : nil
    end
  end

  def checkpoint(profile, id)
    Array(profile.dig("phase_load", "checkpoints")).find { |row| row["checkpoint_id"] == id }
  end

  def surface_row(sandbox, rel)
    doc = YAML.safe_load(sandbox.join("automation/harness-surface-version-registry.yaml").read, aliases: true)
    Array(doc["surfaces"]).find { |row| row.is_a?(Hash) && row["path"] == rel }
  end

  def test_unreviewed_write_fails_and_does_not_touch_files
    Dir.mktmpdir("bounded-closure-unreviewed-") do |directory|
      sandbox = Pathname.new(directory)
      populate(sandbox)
      before = snapshot(sandbox)
      _stdout, stderr, status, _record = run_closure(sandbox, ["--write"], manifest: write_manifest(sandbox, reviewed: false))
      refute status.success?
      assert_includes stderr, "director_reviewed"
      assert_equal before, snapshot(sandbox)
    end
  end

  def test_dry_run_does_not_write
    Dir.mktmpdir("bounded-closure-dry-") do |directory|
      sandbox = Pathname.new(directory)
      populate(sandbox)
      before = snapshot(sandbox)
      _stdout, stderr, status, record = run_closure(sandbox, [], manifest: write_manifest(sandbox, reviewed: true))
      assert status.success?, stderr
      payload = JSON.parse(record.read)
      assert_equal true, payload["dry_run"]
      assert_equal before, snapshot(sandbox)
    end
  end

  def test_write_pins_equal_final_bytes_and_second_run_is_idempotent
    Dir.mktmpdir("bounded-closure-write-") do |directory|
      sandbox = Pathname.new(directory)
      populate(sandbox)
      seed_throwaway_fixtures!(sandbox)
      historic_before = sandbox.join(HISTORIC).read
      registry_before = sandbox.join("automation/idol-script-registry.yaml").read
      original_routing_sha = Digest::SHA256.file(sandbox.join("automation/graph-default-routing.yaml").to_s).hexdigest
      provider_before = YAML.safe_load(sandbox.join("automation/harness-provider-profile-registry.yaml").read, aliases: true)
      cursor_source_sha = provider_before.fetch("logical_profiles").fetch("frontier_director").fetch("providers").fetch("cursor").fetch("source_sha256")
      openai_lane_sha = provider_before.fetch("media_lanes").fetch("openai_image_api_current").fetch("provider_profile_source_sha256")
      manifest = write_manifest(sandbox, reviewed: true)
      _stdout, stderr, status, record = run_closure(sandbox, ["--write"], manifest: manifest)
      assert status.success?, stderr
      payload = JSON.parse(record.read)
      assert_equal false, payload["dry_run"]
      assert_equal true, payload["converged"]
      refute_empty payload["changed_files"]
      changed_paths = payload.fetch("changed_files").map { |row| row["path"] }
      assert_includes changed_paths, "automation/graph-default-routing.yaml"
      assert_includes changed_paths, "automation/harness-provider-profile-registry.yaml"
      assert_includes changed_paths, "automation/harness-execution-contract.yaml"
      assert_includes changed_paths, "automation/harness-surface-version-registry.yaml"
      payload.fetch("pin_closure").each do |row|
        assert_equal true, row["matches_target_bytes"], row.inspect
        actual = Digest::SHA256.file(sandbox.join(row["target"]).to_s).hexdigest
        assert_equal actual, row["sha256"], row.inspect
      end
      routing = sandbox.join("automation/graph-default-routing.yaml").read
      assert_includes routing, "    - scripts/lib/idol_role_context_pack.rb\n    - scripts/lib/idol_source_connection_contract.rb\n    - scripts/lib/idol_run_followup_sidecar.rb\n"
      routing_sha = Digest::SHA256.hexdigest(routing)
      refute_equal original_routing_sha, routing_sha
      graph = YAML.safe_load(sandbox.join("automation/graph-skill-load-profiles.yaml").read, aliases: true)
      routing_pin = Array(graph["read_bindings"]).find { |row| row["binding_id"] == "graph_default_routing" }
      assert_equal routing_sha, routing_pin["sha256"]
      agents = Array(graph["read_bindings"]).find { |row| row["binding_id"] == "agents" }
      assert_equal Digest::SHA256.file(sandbox.join("AGENTS.md").to_s).hexdigest, agents["sha256"]
      kinetic = Array(graph["read_bindings"]).find { |row| row["binding_id"] == "kinetic_slot_sheet_schema" }
      assert_equal "content-addressed", kinetic["revision"]
      assert sandbox.join("automation/graph-skill-load-profiles.yaml").read.match?(/^  - binding_id: kinetic_slot_sheet_schema$/)
      grok = YAML.safe_load(sandbox.join("automation/providers/grok-build-profiles.yaml").read, aliases: true)
      successor = grok.dig("nonmedia_activation_evidence", "evidence_refs", "cdd_successor_contract")
      assert_equal Digest::SHA256.file(sandbox.join("policies/harness-routing-and-sources.md").to_s).hexdigest, successor["sha256"]
      grok_sha = Digest::SHA256.file(sandbox.join("automation/providers/grok-build-profiles.yaml").to_s).hexdigest
      provider_registry = YAML.safe_load(sandbox.join("automation/harness-provider-profile-registry.yaml").read, aliases: true)
      %w[frontier_director director_deep worker_high research_medium].each do |logical|
        row = provider_registry.fetch("logical_profiles").fetch(logical).fetch("providers").fetch("grok")
        assert_equal "automation/providers/grok-build-profiles.yaml", row.fetch("source_path"), logical
        assert_equal grok_sha, row.fetch("source_sha256"), logical
      end
      grok_lane = provider_registry.fetch("media_lanes").fetch("grok_build_oauth_subscription")
      assert_equal "automation/providers/grok-build-profiles.yaml", grok_lane.fetch("provider_profile_source")
      assert_equal grok_sha, grok_lane.fetch("provider_profile_source_sha256")
      assert_equal cursor_source_sha, provider_registry.fetch("logical_profiles").fetch("frontier_director").fetch("providers").fetch("cursor").fetch("source_sha256")
      assert_equal openai_lane_sha, provider_registry.fetch("media_lanes").fetch("openai_image_api_current").fetch("provider_profile_source_sha256")
      grok_index_pins = payload.fetch("pin_closure").select do |row|
        row["catalog"] == "automation/harness-provider-profile-registry.yaml" && row["target"] == "automation/providers/grok-build-profiles.yaml"
      end
      assert_equal 5, grok_index_pins.length
      assert_equal 4, grok_index_pins.count { |row| row["sha_key"] == "source_sha256" }
      assert_equal 1, grok_index_pins.count { |row| row["sha_key"] == "provider_profile_source_sha256" }
      grok_index_pins.each do |row|
        assert_equal grok_sha, row["sha256"], row.inspect
        assert_equal true, row["matches_target_bytes"], row.inspect
      end
      contract = sandbox.join("automation/harness-execution-contract.yaml").read
      registry_sha = Digest::SHA256.file(sandbox.join("automation/harness-provider-profile-registry.yaml").to_s).hexdigest
      assert_includes contract, "registry_sha256: #{registry_sha}"
      execution_pin = payload.fetch("pin_closure").find do |row|
        row["catalog"] == "automation/harness-execution-contract.yaml" && row["target"] == "automation/harness-provider-profile-registry.yaml" && row["sha_key"] == "registry_sha256"
      end
      assert execution_pin, "missing execution-contract registry_sha256 pin"
      assert_equal registry_sha, execution_pin["sha256"]
      %w[
        automation/graph-default-routing.yaml
        automation/graph-skill-load-profiles.yaml
        automation/graph-role-context-projection.yaml
        automation/harness-role-context-projection.yaml
        automation/harness-skill-load-profiles.yaml
        automation/harness-execution-contract.yaml
        automation/harness-provider-profile-registry.yaml
        automation/providers/grok-build-profiles.yaml
      ].each do |rel|
        next unless payload["changed_files"].any? { |row| row["path"] == rel }
        row = surface_row(sandbox, rel)
        assert row, "missing surface row for #{rel}"
        assert_equal Digest::SHA256.file(sandbox.join(rel).to_s).hexdigest, row["sha256"], rel
      end
      harness = YAML.safe_load(sandbox.join("automation/harness-skill-load-profiles.yaml").read, aliases: true)
      grok_pin = Array(harness["read_bindings"]).find { |row| row["binding_id"] == "grok_build_profiles" }
      if grok_pin
        assert_equal Digest::SHA256.file(sandbox.join("automation/providers/grok-build-profiles.yaml").to_s).hexdigest, grok_pin["sha256"]
      end
      assert_equal historic_before, sandbox.join(HISTORIC).read
      assert_equal registry_before, sandbox.join("automation/idol-script-registry.yaml").read
      first = snapshot(sandbox)
      _stdout2, stderr2, status2, record2 = run_closure(sandbox, ["--write"], manifest: manifest)
      assert status2.success?, stderr2
      payload2 = JSON.parse(record2.read)
      assert_equal [], payload2["changed_files"]
      assert payload2.fetch("pin_closure").all? { |row| row["matches_target_bytes"] }
      assert_equal first, snapshot(sandbox)
    end
  end

  def test_kinetic_and_kernel_scope
    Dir.mktmpdir("bounded-closure-scope-") do |directory|
      sandbox = Pathname.new(directory)
      populate(sandbox)
      _stdout, stderr, status, _record = run_closure(sandbox, ["--write"], manifest: write_manifest(sandbox, reviewed: true))
      assert status.success?, stderr
      graph = YAML.safe_load(sandbox.join("automation/graph-skill-load-profiles.yaml").read, aliases: true)
      harness = YAML.safe_load(sandbox.join("automation/harness-skill-load-profiles.yaml").read, aliases: true)
      p3 = Array(graph["profiles"]).find { |row| row["profile_id"] == "planning_cdd_p3_ci" }
      p1 = Array(graph["profiles"]).find { |row| row["profile_id"] == "planning_cdd_p1" }
      p2 = Array(graph["profiles"]).find { |row| row["profile_id"] == "planning_cdd_p2" }
      fp = Array(harness["profiles"]).find { |row| row["profile_id"] == "pre_02a_development_block_fp" }
      cdd = Array(harness["profiles"]).find { |row| row["profile_id"] == "creative_development_director" }
      assert_includes Array(p3["required_read_ids"]), "kinetic_slot_sheet_schema"
      assert_includes Array(checkpoint(p3, "p3_section_kinetic_architecture")["required_read_ids"]), "kinetic_slot_sheet_schema"
      refute_includes Array(checkpoint(p3, "p3_draft_keyframe_proof")["required_read_ids"]), "kinetic_slot_sheet_schema"
      refute_includes Array(checkpoint(p1, "p1_g40_integration_handoff")["required_read_ids"]), "kinetic_slot_sheet_schema"
      refute_includes Array(checkpoint(p2, "p2_visual_reference_development")["required_read_ids"]), "kinetic_slot_sheet_schema"
      assert_includes Array(fp["required_read_ids"]), "kinetic_slot_sheet_schema"
      assert_includes Array(checkpoint(fp, "fp_close_shard")["required_read_ids"]), "kinetic_slot_sheet_schema"
      refute_includes Array(checkpoint(fp, "section_01_core_direction")["required_read_ids"]), "kinetic_slot_sheet_schema"
      refute_includes Array(checkpoint(cdd, "cdd_direction_alignment")["required_read_ids"]), "kinetic_slot_sheet_schema"
      refute_includes Array(fp["required_read_ids"]), "provider_neutral_studio_kernel"
      heading = "      - Who Authors And Who Reads\n      - Department Instruction Delivery\n      - Fixed Twelve-Block Command\n"
      assert_includes sandbox.join("automation/harness-role-context-projection.yaml").read, heading
      assert_includes sandbox.join("automation/graph-role-context-projection.yaml").read, heading
    end
  end
end
