#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

ROOT = Pathname.new(__dir__).join("..", "..").expand_path
VALIDATOR = ROOT.join("scripts", "validate_graph_runtime_projection.rb")
FIXTURES = ROOT.join("scripts", "tests", "fixtures", "graph-runtime")
SKILL_LOAD = ROOT.join("automation", "graph-skill-load-profiles.yaml")
PROJECTION = ROOT.join("automation", "graph-role-context-projection.yaml")
ROUTING = ROOT.join("automation", "graph-default-routing.yaml")
CANONICAL_DIRECTOR_LANE_ID_PATTERNS = {
  "overall" => "^overall$",
  "planning_p1" => "^planning_p1$",
  "planning_p2" => "^planning_p2$",
  "planning_p3_ci" => "^planning_p3_c[1-9][0-9]*$",
  "section_cluster_v_ci" => "^section_cluster_v_c[1-9][0-9]*$",
  "edit_director" => "^edit_director$"
}.freeze
DIRECTOR_LANE_PATTERN_LABELS = {
  "overall" => "overall",
  "planning_p1" => "P1",
  "planning_p2" => "P2",
  "planning_p3_ci" => "P3",
  "section_cluster_v_ci" => "V-Ci",
  "edit_director" => "edit_director"
}.freeze
DIRECTOR_LANE_PATTERN_GRAMMAR = {
  "overall" => "overall",
  "planning_p1" => "planning_p1",
  "planning_p2" => "planning_p2",
  "planning_p3_ci" => "planning_p3_cN",
  "section_cluster_v_ci" => "section_cluster_v_cN",
  "edit_director" => "edit_director"
}.freeze

class ValidateGraphRuntimeProjectionTest < Minitest::Test
  def run_validator(*extra)
    Open3.capture3("ruby", VALIDATOR.to_s, "--json", *extra, chdir: ROOT.to_s)
  end

  def active_graph_source_set_sha256
    stdout, stderr, status = run_validator
    assert status.success?, [stdout, stderr].join("\n")
    digest = JSON.parse(stdout).fetch("active_graph_source_set_sha256")
    assert_match(/\A[a-f0-9]{64}\z/, digest)
    digest
  end

  def test_shipped_registries_pass
    stdout, stderr, status = run_validator
    assert status.success?, [stdout, stderr].join("\n")
    payload = JSON.parse(stdout)
    assert_equal "pass", payload["status"]
    assert_equal "idol-graph-skill-load-profiles.v1", payload["graph_revision"]
    assert_match(/\A[a-f0-9]{64}\z/, payload["active_graph_source_set_sha256"])
    assert_equal "shadow_not_default", payload["skill_load_status"]
    assert_equal "shadow_not_default", payload["projection_status"]
    assert_equal "legacy_pinned", payload["default_writer"]
    assert_equal "legacy_pinned", payload["existing_runs_writer"]
    assert_equal "legacy_pinned", payload["new_runs_default_writer"]
    assert_equal "verified_default_switch_receipt", payload["graph_v2_requires"]
    assert_operator payload["profile_count"], :>=, 8
  end

  def test_shipped_registries_are_shadow_not_default
    skill_load = YAML.safe_load(SKILL_LOAD.read)
    projection = YAML.safe_load(PROJECTION.read)
    routing = YAML.safe_load(ROUTING.read)
    assert_equal "shadow_not_default", skill_load["status"]
    assert_equal "legacy_pinned", skill_load.dig("activation", "default_writer")
    assert_equal "verified_default_switch_receipt", skill_load.dig("activation", "graph_v2_requires")
    assert_equal "shadow_not_default", projection["status"]
    assert_equal "exclude_from_pack_recover_via_source_id", projection.dig("defaults", "url_projection")
    assert_equal "legacy_pinned", routing.dig("writer_boundary", "existing_runs")
    assert_equal "fail_closed", routing.dig("writer_boundary", "dual_active_writer")
    assert_equal %w[G0 G1 G2 G3 G4], routing.dig("founder_gates", "normal_cycle")
    assert_equal "p3_ci_section_cohort_id_exact_carries_to_v_ci", routing.dig("cohort_succession", "same_cohort_carry")
    assert_equal 8, routing.dig("session_caps", "provider_physical_ceiling", "grok_build_nonroot")
    assert_equal 6, routing.dig("session_caps", "provider_physical_ceiling", "cursor_agent_nonroot")
    assert_equal 14, routing.dig("session_caps", "provider_physical_ceiling", "combined")
    assert_equal true, routing.dig("session_caps", "provider_physical_ceiling", "lower_live_cap_wins")
  end

  def test_p3_and_v_are_cohort_templates_with_identity_carry
    skill_load = YAML.safe_load(SKILL_LOAD.read)
    profiles = skill_load.fetch("profiles").each_with_object({}) { |row, memo| memo[row["profile_id"]] = row }
    p3 = profiles.fetch("planning_cdd_p3_ci")
    vci = profiles.fetch("section_cluster_cdd_ci")
    assert_equal "cohort_template", p3["profile_kind"]
    assert_equal "cohort_template", vci["profile_kind"]
    assert_equal "section_cluster_cdd_ci", p3["identity_carry_to"]
    assert_equal "planning_cdd_p3_ci", vci["identity_carry_from"]
    assert_equal "^planning_p3_c[1-9][0-9]*$", p3["lane_id_pattern"]
    assert_equal "^section_cluster_v_c[1-9][0-9]*$", vci["lane_id_pattern"]
    assert_equal "section_cluster_cdd_ci", profiles.dig("section_image_motion_worker", "return_route", "recipient_role")
    routing = YAML.safe_load(ROUTING.read)
    patterns = routing.fetch("cohort_succession").fetch("lane_id_pattern")
    assert_equal CANONICAL_DIRECTOR_LANE_ID_PATTERNS, patterns
    assert_equal p3["lane_id_pattern"], patterns.fetch("planning_p3_ci")
    assert_equal vci["lane_id_pattern"], patterns.fetch("section_cluster_v_ci")
  end

  def test_nine_sections_activate_three_disjoint_cdds_before_and_after_g40
    planning = YAML.safe_load(FIXTURES.join("parallel-cohort-cdds.yaml").read)
    production = YAML.safe_load(FIXTURES.join("parallel-production-cohort-cdds.yaml").read)
    planning_lanes = planning.fetch("active_writers").map { |row| row.fetch("lane_id") }
    production_lanes = production.fetch("active_writers").map { |row| row.fetch("lane_id") }
    assert_equal %w[planning_p3_c1 planning_p3_c2 planning_p3_c3], planning_lanes
    assert_equal %w[section_cluster_v_c1 section_cluster_v_c2 section_cluster_v_c3], production_lanes
    routing_patterns = YAML.safe_load(ROUTING.read).fetch("cohort_succession").fetch("lane_id_pattern")
    p3_pattern = Regexp.new(routing_patterns.fetch("planning_p3_ci"))
    v_pattern = Regexp.new(routing_patterns.fetch("section_cluster_v_ci"))
    planning_lanes.each { |lane| assert_match p3_pattern, lane }
    production_lanes.each { |lane| assert_match v_pattern, lane }
    assert_equal 3, planning.fetch("active_writers").length
    assert_equal 3, production.fetch("active_writers").length
    planning_handoff_sessions = production.fetch("sessions").select { |row| row.fetch("lane_id").start_with?("planning_p3_c") }
    assert planning_handoff_sessions.all? { |row| row.fetch("state") == "retired_read_only" }
  end

  [
    "existing-run-legacy-pin.yaml"
  ].each do |name|
    define_method("test_pass_fixture_#{name.tr('-.', '_')}") do
      stdout, stderr, status = run_validator("--case", FIXTURES.join(name).to_s)
      assert status.success?, [stdout, stderr].join("\n")
      payload = JSON.parse(stdout)
      assert_equal "pass", payload["status"]
      assert_equal "pass", payload["case_status"], payload["case_errors"].inspect
      assert_empty payload["case_errors"]
    end
  end

  [
    "new-run-graph-v2-with-switch.yaml",
    "parallel-cohort-cdds.yaml",
    "parallel-production-cohort-cdds.yaml"
  ].each do |name|
    define_method("test_pass_fixture_#{name.tr('-.', '_')}") do
      Dir.mktmpdir("graph-runtime-current-source-set") do |directory|
        document = YAML.safe_load(FIXTURES.join(name).read)
        document.fetch("switch_receipt")["source_set_sha256"] = active_graph_source_set_sha256
        path = Pathname.new(directory).join(name)
        path.write(YAML.dump(document))
        stdout, stderr, status = run_validator("--case", path.to_s)
        assert status.success?, [stdout, stderr].join("\n")
        payload = JSON.parse(stdout)
        assert_equal "pass", payload["status"]
        assert_equal "pass", payload["case_status"], payload["case_errors"].inspect
        assert_empty payload["case_errors"]
      end
    end
  end

  {
    "new-run-graph-v2-without-switch.yaml" => "graph v2 requires a verified default-switch receipt",
    "existing-run-graph-write.yaml" => "existing run remains legacy-pinned",
    "dual-active-writer.yaml" => "dual active writer",
    "same-lane-stage-dual-writer.yaml" => "dual active writer for lane/stage",
    "successor-writes-before-cas.yaml" => "successor writes before CAS",
    "harness-id-active-authoring.yaml" => "historical harness id used as active authoring",
    "wrong-cohort-succession.yaml" => "P3-Ci must exact-carry into the same V-Ci cohort",
    "url-in-pack.yaml" => "Role Context Pack contains forbidden field: url",
    "unrecoverable-source.yaml" => "Role Context Pack missing recoverable locator",
    "third-session.yaml" => "third session",
    "same-session-correction-new-physical.yaml" => "same-session correction opened a new physical session",
    "backpressure-launch.yaml" => "backpressure forbids new launch at unreviewed limit",
    "gate-bypass.yaml" => "Founder gate bypass is HOLD",
    "invalid-partition.yaml" => "cohort partition must be contiguous 2 or 3",
    "forged-switch-receipt.yaml" => "switch receipt source_set_sha256 does not match active graph source bytes",
    "requested-active-mismatch.yaml" => "requested writer must equal the unique active writer",
    "nonminimal-six-cohorts.yaml" => "cohort partition must be contiguous 2 or 3 and match the canonical partition",
    "nonminimal-eight-cohorts.yaml" => "cohort partition must be contiguous 2 or 3 and match the canonical partition",
    "grok-provider-capacity.yaml" => "Grok live physical session ceiling exceeded",
    "cursor-provider-capacity.yaml" => "Cursor live physical session ceiling exceeded",
    "combined-provider-capacity.yaml" => "combined live physical session ceiling exceeded"
  }.each do |name, fragment|
    define_method("test_fail_fixture_#{name.tr('-.', '_')}") do
      stdout, stderr, status = run_validator("--case", FIXTURES.join(name).to_s)
      assert status.success?, [stdout, stderr, "expected registry+case wrapper to pass while the case itself fails"].join("\n")
      payload = JSON.parse(stdout)
      assert_equal "pass", payload["status"], payload["errors"].inspect
      assert_equal "fail", payload["case_status"], payload["case_errors"].inspect
      assert payload["case_errors"].any? { |error| error.include?(fragment) }, payload["case_errors"].inspect
    end
  end

  def test_rejects_stale_skill_binding_hash
    Dir.mktmpdir("graph-skill-load") do |directory|
      document = YAML.safe_load(SKILL_LOAD.read)
      document.fetch("skill_bindings").first["sha256"] = "0" * 64
      path = Pathname.new(directory).join("profiles.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--skill-load", path.to_s)
      refute status.success?
      assert_includes stdout, "binding SHA-256 is stale"
    end
  end

  def test_rejects_current_profile_release_outside_active_source_closure
    Dir.mktmpdir("graph-routing-release-closure") do |directory|
      document = YAML.safe_load(ROUTING.read)
      document.fetch("writer_boundary").fetch("active_graph_surfaces").delete(
        "automation/graph-creative-judgment-profile-releases/pre_fp_storyline/9acb8808d3a04745198f91ed2a5e1650bc8d2e3a2ac158e1774f7d9e1f2372c4.yaml"
      )
      path = Pathname.new(directory).join("routing.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--routing", path.to_s)
      refute status.success?
      assert_includes stdout, "current judgment profile release is outside active graph source closure"
    end
  end

  def test_rejects_current_profile_promotion_outside_active_source_closure
    Dir.mktmpdir("graph-routing-promotion-closure") do |directory|
      document = YAML.safe_load(ROUTING.read)
      document.fetch("writer_boundary").fetch("active_graph_surfaces").delete(
        "automation/graph-creative-judgment-profile-promotions/bootstrap-shadow-seed/pre_fp_storyline.yaml"
      )
      path = Pathname.new(directory).join("routing.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--routing", path.to_s)
      refute status.success?
      assert_includes stdout, "current judgment profile promotion is outside active graph source closure"
    end
  end

  def test_rejects_transitive_ruby_dependency_outside_active_source_closure
    %w[
      scripts/lib/idol_graph_goal_evidence_contract.rb
      scripts/lib/idol_graph_output_manifest_contract.rb
      scripts/lib/idol_current_next_v2.rb
      scripts/lib/idol_source_connection_contract.rb
    ].each do |dependency|
      Dir.mktmpdir("graph-routing-runtime-closure") do |directory|
        document = YAML.safe_load(ROUTING.read)
        document.fetch("writer_boundary").fetch("active_graph_surfaces").delete(dependency)
        path = Pathname.new(directory).join("routing.yaml")
        path.write(YAML.dump(document))
        stdout, _stderr, status = run_validator("--routing", path.to_s)
        refute status.success?, dependency
        assert_includes stdout, "required Ruby dependency is outside active graph source closure", dependency
        assert_includes stdout, dependency
      end
    end
  end

  def write_hash_fresh_skill_load(path)
    document = YAML.safe_load(SKILL_LOAD.read, aliases: true)
    %w[skill_bindings read_bindings].each do |key|
      Array(document[key]).each do |row|
        next unless row.is_a?(Hash) && row["path"].to_s != ""
        source = ROOT.join(row["path"])
        row["sha256"] = Digest::SHA256.file(source.to_s).hexdigest if source.file?
        row["revision"] = row["revision"].to_s if row.key?("revision")
      end
    end
    path.write(YAML.dump(document))
  end

  def test_rejects_source_connection_contract_outside_active_ruby_closure
    Dir.mktmpdir("graph-routing-source-connection-closure") do |directory|
      routing = YAML.safe_load(ROUTING.read)
      routing.fetch("writer_boundary").fetch("active_graph_surfaces").delete("scripts/lib/idol_source_connection_contract.rb")
      routing_path = Pathname.new(directory).join("routing.yaml")
      routing_path.write(YAML.dump(routing))
      skill_path = Pathname.new(directory).join("skill-load.yaml")
      write_hash_fresh_skill_load(skill_path)
      stdout, _stderr, status = run_validator("--routing", routing_path.to_s, "--skill-load", skill_path.to_s)
      refute status.success?
      assert_includes stdout, "required Ruby dependency is outside active graph source closure"
      assert_includes stdout, "scripts/lib/idol_source_connection_contract.rb"
    end
  end

  def test_rejects_missing_writer_and_active_session_for_writer_required_cohort
    Dir.mktmpdir("graph-runtime-missing-cohort") do |directory|
      document = YAML.safe_load(FIXTURES.join("parallel-cohort-cdds.yaml").read)
      document.fetch("active_writers").reject! { |row| row["section_cohort_id"] == "C3" }
      document.fetch("sessions").reject! { |row| row["section_cohort_id"] == "C3" }
      document.fetch("active_authoring_ids").delete("planning_cdd_p3_c3")
      path = Pathname.new(directory).join("case.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--case", path.to_s)
      refute status.success?
      assert_includes stdout, "active cohort writer set must exactly equal writer-required roster"
      assert_includes stdout, "active cohort session set must exactly equal writer-required roster"
      assert_includes stdout, "writer-required cohort C3/planning_cell must have exactly one active writer"
      assert_includes stdout, "writer-required cohort C3/planning_cell must have exactly one active session"
    end
  end

  def test_rejects_lone_successor_without_retained_primary_or_cas
    Dir.mktmpdir("graph-runtime-lone-successor") do |directory|
      document = YAML.safe_load(FIXTURES.join("new-run-graph-v2-with-switch.yaml").read)
      successor = document.fetch("sessions").find { |row| row["generation"] == "successor" }
      successor["state"] = "active_writer"
      successor.delete("cas_committed")
      document["sessions"] = [successor]
      document.fetch("active_writers").first["writer_id"] = successor.fetch("session_id")
      path = Pathname.new(directory).join("case.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--case", path.to_s)
      refute status.success?
      assert_includes stdout, "successor requires one retained primary on section_cluster_v_c1/section_cluster_production"
    end
  end


  def test_rejects_noncanonical_cohort_lane_pattern_in_profile_registry
    {
      "planning_cdd_p3_ci" => [
        "P3 lane_id_pattern must match canonical planning_p3_cN grammar",
        "skill-load P3 lane_id_pattern must match graph-default-routing"
      ],
      "section_cluster_cdd_ci" => [
        "V-Ci lane_id_pattern must match canonical section_cluster_v_cN grammar",
        "skill-load V-Ci lane_id_pattern must match graph-default-routing"
      ]
    }.each do |profile_id, fragments|
      Dir.mktmpdir("graph-skill-load") do |directory|
        document = YAML.safe_load(SKILL_LOAD.read)
        profile = document.fetch("profiles").find { |row| row["profile_id"] == profile_id }
        profile["lane_id_pattern"] = "^mutated_#{profile_id}_c[1-9][0-9]*$"
        path = Pathname.new(directory).join("profiles.yaml")
        path.write(YAML.dump(document))
        stdout, _stderr, status = run_validator("--skill-load", path.to_s)
        refute status.success?, profile_id
        fragments.each { |fragment| assert_includes stdout, fragment, profile_id }
        refute_includes stdout, "graph-default-routing P3 lane_id_pattern must match canonical"
        refute_includes stdout, "graph-default-routing V-Ci lane_id_pattern must match canonical"
        refute_includes stdout, "assignment-routing P3 lane_id_pattern must match canonical"
        refute_includes stdout, "assignment-routing V-Ci lane_id_pattern must match canonical"
      end
    end
  end

  def test_rejects_graph_default_routing_lane_id_pattern_drift
    CANONICAL_DIRECTOR_LANE_ID_PATTERNS.each_key do |key|
      Dir.mktmpdir("graph-default-routing-lanes") do |directory|
        document = YAML.safe_load(ROUTING.read)
        document["cohort_succession"]["lane_id_pattern"][key] = "^mutated_#{key}$"
        path = Pathname.new(directory).join("routing.yaml")
        path.write(YAML.dump(document))
        stdout, _stderr, status = run_validator("--routing", path.to_s)
        refute status.success?, key
        label = DIRECTOR_LANE_PATTERN_LABELS.fetch(key)
        grammar = DIRECTOR_LANE_PATTERN_GRAMMAR.fetch(key)
        assert_includes stdout, "graph-default-routing #{label} lane_id_pattern must match canonical #{grammar} grammar", key
        if key == "planning_p3_ci"
          assert_includes stdout, "skill-load P3 lane_id_pattern must match graph-default-routing"
        elsif key == "section_cluster_v_ci"
          assert_includes stdout, "skill-load V-Ci lane_id_pattern must match graph-default-routing"
        end
      end
    end
  end

  def test_rejects_arbitrary_noncanonical_director_lane_in_runtime_case
    Dir.mktmpdir("graph-runtime-case") do |directory|
      document = YAML.safe_load(FIXTURES.join("new-run-graph-v2-with-switch.yaml").read)
      document.fetch("active_writers").first["lane_id"] = "banana"
      document.fetch("sessions").first["lane_id"] = "banana"
      path = Pathname.new(directory).join("case.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--case", path.to_s)
      refute status.success?
      assert_includes stdout, "runtime Director writer lane_id is not canonical"
      assert_includes stdout, "runtime Director session lane_id is not canonical"
    end
  end

  def test_rejects_same_cohort_p3_and_v_active_across_g40
    Dir.mktmpdir("graph-runtime-g40") do |directory|
      document = YAML.safe_load(FIXTURES.join("parallel-cohort-cdds.yaml").read)
      document.fetch("active_writers") << {
        "scope" => "section_cluster_v_c1",
        "lane_id" => "section_cluster_v_c1",
        "role" => "section_cluster_cdd_ci",
        "section_cohort_id" => "C1",
        "stage" => "section_cluster_production",
        "writer_id" => "v_c1_primary"
      }
      document.fetch("sessions") << {
        "lane_id" => "section_cluster_v_c1",
        "role" => "section_cluster_cdd_ci",
        "section_cohort_id" => "C1",
        "stage" => "section_cluster_production",
        "provider" => "grok",
        "generation" => "primary",
        "state" => "active_writer"
      }
      path = Pathname.new(directory).join("case.yaml")
      path.write(YAML.dump(document))
      stdout, _stderr, status = run_validator("--case", path.to_s)
      refute status.success?
      assert_includes stdout, "P3 and V cannot both be active writers for cohort C1"
      assert_includes stdout, "P3 session must be read-only after V activation for cohort C1"
    end
  end
end
