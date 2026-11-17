# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "securerandom"
require "tmpdir"
require "yaml"
require_relative "support/department_dispatch_profile_fixture"

class ValidateCompanyOpsIdolBridgeTest < Minitest::Test
  include DepartmentDispatchProfileFixture

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  VALIDATOR = ROOT.join("scripts", "validate_company_ops_idol_bridge.rb")
  CONTRACT = ROOT.join("automation", "company-ops-idol-bridge.yaml")
  DIGEST = "a" * 64

  def setup
    @world = self.class.world
    @world.fetch(:ledger_path).write("")
  end

  def test_standing_contract_passes
    stdout, stderr, status = run_validator
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_admitted_packet_may_execute
    stdout, stderr, status = run_validator(record: valid_record)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_pass_paths_report_json_pass
    [
      valid_record,
      begin
        record = valid_record
        record["authority"]["submission_number"] = 3
        record
      end,
      begin
        record = valid_record
        record["improvement"]["kind"] = "routine"
        record["improvement"]["founder_approval"] = false
        record
      end
    ].each do |record|
      stdout, stderr, status = run_validator(record: record)
      assert status.success?, "#{stdout}\n#{stderr}"
      assert_equal "pass", JSON.parse(stdout).fetch("status")
    end
  end

  def test_execution_before_goal_admission_fails
    refute_record("execution is forbidden before Department Dispatch, native Goal, and Role Context Pack admission") do |record|
      record["idol_admission"]["native_goal_status"] = "missing"
    end
  end

  def test_missing_goal_file_with_admitted_status_fails
    refute_record("native Goal file is missing") do |record|
      record["idol_admission"]["native_goal_path"] = "runs/harness-test/missing-goal.md"
      record["idol_admission"]["native_goal_status"] = "admitted"
      record["execution"]["allowed"] = true
    end
  end

  def test_goal_id_mismatch_fails
    refute_record("native Goal id mismatch") do |record|
      record["idol_admission"]["native_goal_id"] = "OTHER-GOAL"
      record["company_ops_packet"]["native_goal_name"] = "OTHER-GOAL"
    end
  end

  def test_missing_dispatch_fails
    refute_record("Department Dispatch is missing") do |record|
      record["idol_admission"]["dispatch_path"] = "runs/harness-test/missing/work/department-dispatches/MISSING.yaml"
      record["execution"]["allowed"] = true
    end
  end

  def test_missing_pack_fails
    refute_record("Role Context Pack is missing") do |record|
      record["idol_admission"]["role_context_pack_path"] = "runs/harness-test/missing/pack.json"
      record["execution"]["allowed"] = true
    end
  end

  def test_stale_dispatch_hash_fails
    refute_record("Department Dispatch SHA-256 is stale") do |record|
      record["idol_admission"]["dispatch_sha256"] = DIGEST
      record["execution"]["allowed"] = true
    end
  end

  def test_stale_pack_hash_fails
    refute_record("Role Context Pack SHA-256 is stale") do |record|
      record["idol_admission"]["role_context_pack_sha256"] = DIGEST
      record["execution"]["allowed"] = true
    end
  end

  def test_stale_goal_hash_fails
    refute_record("native Goal SHA-256 is stale") do |record|
      record["idol_admission"]["native_goal_sha256"] = DIGEST
      record["execution"]["allowed"] = true
    end
  end

  def test_dotdot_goal_path_fails
    refute_record("native Goal path escapes IDOL root") do |record|
      record["idol_admission"]["native_goal_path"] = "../company-ops/AGENTS.md"
    end
  end

  def test_symlink_dispatch_escape_fails
    root = @world.fetch(:artifact_root)
    inner = root.join("runs/harness-test/x/work/sources")
    inner.mkpath
    link = inner.join("escape-link.yaml")
    FileUtils.ln_s("/etc/hosts", link)
    refute_record("Department Dispatch path escapes IDOL root") do |record|
      record["idol_admission"]["dispatch_path"] = "runs/harness-test/x/work/sources/escape-link.yaml"
      record["execution"]["allowed"] = true
    end
  ensure
    FileUtils.rm_f(link) if defined?(link) && link
  end

  def test_garbage_dispatch_invokes_real_validator
    root = @world.fetch(:artifact_root)
    dispatch = root.join("runs/harness-test/x/work/department-dispatches/X.yaml")
    dispatch.dirname.mkpath
    dispatch.write("schema_version: idol-department-dispatch.v8\nartifact_type: garbage\n")
    record = valid_record
    record["idol_admission"]["dispatch_path"] = "runs/harness-test/x/work/department-dispatches/X.yaml"
    record["idol_admission"]["dispatch_sha256"] = Digest::SHA256.file(dispatch).hexdigest
    record["execution"]["allowed"] = true
    stdout, stderr, status = run_validator(record: record)
    refute status.success?, "#{stdout}\n#{stderr}"
    payload = JSON.parse(stdout)
    assert_equal "fail", payload.fetch("status")
    assert_includes "#{stdout}\n#{stderr}", "Department Dispatch v8 validator failed"
  end

  def test_absolute_dispatch_path_fails
    refute_record("Department Dispatch path escapes IDOL root") do |record|
      record["idol_admission"]["dispatch_path"] = "/tmp/not-idol-dispatch.yaml"
    end
  end

  def test_unbound_packet_digest_fails
    refute_record("packet packet_digest is unbound") do |record|
      record["company_ops_packet"]["packet_digest"] = ""
    end
  end

  def test_unbound_author_fails
    refute_record("packet author_agent_id is unbound") do |record|
      record["company_ops_packet"]["author_agent_id"] = ""
    end
  end

  def test_unbound_profile_fails
    refute_record("packet profile_id is unbound") do |record|
      record["company_ops_packet"]["profile_id"] = ""
    end
  end

  def test_unbound_session_fails
    refute_record("packet session_id is unbound") do |record|
      record["company_ops_packet"]["session_id"] = ""
    end
  end

  def test_unbound_lease_fails
    refute_record("packet writer_lease_id is unbound") do |record|
      record["company_ops_packet"]["writer_lease_id"] = ""
    end
  end

  def test_unbound_input_digest_fails
    refute_record("packet input_digest is unbound") do |record|
      record["company_ops_packet"]["input_digest"] = ""
    end
  end

  def test_self_review_fails
    refute_record("worker self-review is forbidden") do |record|
      record["authority"]["self_review"] = true
      record["execution"]["allowed"] = true
    end
  end

  def test_same_owner_reviewer_fails
    refute_record("worker self-review is forbidden") do |record|
      record["authority"]["director_owner"] = record["authority"]["assigned_owner"]
    end
  end

  def test_self_promote_fails
    refute_record("worker self-promotion is forbidden") do |record|
      record["authority"]["self_promote"] = true
      record["execution"]["promoted"] = true
    end
  end

  def test_same_owner_promoter_fails
    refute_record("worker self-promotion is forbidden") do |record|
      record["authority"]["promotion_owner"] = record["authority"]["assigned_owner"]
    end
  end

  def test_founder_conversation_owner_fails
    refute_record("worker cannot inherit Founder or external authority") do |record|
      record["authority"]["founder_conversation_owner"] = true
      record["execution"]["allowed"] = true
    end
  end

  def test_grandchildren_fail
    refute_record("creative grandchildren are forbidden") do |record|
      record["authority"]["may_create_grandchildren"] = true
    end
  end

  def test_fourth_submission_fails
    refute_record("fourth submission is forbidden; HOLD or route upstream") do |record|
      record["authority"]["submission_number"] = 4
      record["execution"]["allowed"] = true
    end
  end

  def test_other_lane_fails
    refute_record("worker cannot take another lane") do |record|
      record["company_ops_packet"]["lane_id"] = "other_lane"
      record["execution"]["allowed"] = true
    end
  end

  def test_founder_authority_inheritance_fails
    refute_record("worker cannot inherit Founder or external authority") do |record|
      record["authority"]["inherits_founder_or_external_authority"] = true
      record["execution"]["allowed"] = true
    end
  end

  def test_helper_ceiling_mutation_fails
    refute_record("Company Ops 15-session capacity cannot mutate IDOL 8-native-helper or lane ceilings") do |record|
      record["capacity"]["company_ops_may_mutate_idol_ceilings"] = true
    end
  end

  def test_multiplied_ceilings_fail
    refute_record("Company Ops 15-session capacity cannot mutate IDOL 8-native-helper or lane ceilings") do |record|
      record["capacity"]["ceilings_are_multiplied"] = true
    end
  end

  def test_overwritten_helper_maximum_fails
    refute_record("IDOL native-helper maximum must remain 8") do |record|
      record["capacity"]["idol_native_helper_maximum"] = 15
    end
  end

  def test_session_maximum_eight_fails
    refute_record("Company Ops physical session maximum must remain 15") do |record|
      record["capacity"]["company_ops_physical_session_maximum"] = 8
    end
  end

  def test_session_maximum_one_twenty_fails
    refute_record("Company Ops physical session maximum must remain 15") do |record|
      record["capacity"]["company_ops_physical_session_maximum"] = 120
    end
  end

  def test_raw_markdown_cannot_execute
    refute_record("raw Markdown/YAML/judgment evidence cannot trigger execution") do |record|
      record["command_kind"] = "raw_markdown"
      record["execution"]["allowed"] = true
    end
  end

  def test_raw_yaml_cannot_execute
    refute_record("raw Markdown/YAML/judgment evidence cannot trigger execution") do |record|
      record["command_kind"] = "raw_yaml"
      record["execution"]["allowed"] = true
    end
  end

  def test_judgment_evidence_cannot_execute
    refute_record("raw Markdown/YAML/judgment evidence cannot trigger execution") do |record|
      record["command_kind"] = "judgment_evidence"
      record["execution"]["allowed"] = true
    end
  end

  def test_cursor_cloud_live_post_fails
    refute_record("Cursor Cloud remains no-live-POST branch-return-only") do |record|
      record["cursor_cloud"]["live_post"] = true
      record["company_ops_packet"]["provider"] = "cursor-cloud"
      record["execution"]["allowed"] = false
    end
  end

  def test_cursor_cloud_auto_create_pr_fails
    refute_record("Cursor Cloud remains no-live-POST branch-return-only") do |record|
      record["cursor_cloud"]["auto_create_pr"] = true
      record["execution"]["allowed"] = false
    end
  end

  def test_cursor_cloud_return_kind_live_post_fails
    refute_record("Cursor Cloud remains no-live-POST branch-return-only") do |record|
      record["cursor_cloud"]["return_kind"] = "live_post"
      record["execution"]["allowed"] = false
    end
  end

  def test_provider_alias_fails
    refute_record("only provider grok-build with runtime_surface grok_build_cli_acp may execute on this bridge") do |record|
      record["company_ops_packet"]["provider"] = "cursor-cli"
      record["execution"]["allowed"] = true
    end
  end

  def test_grok_bot_cannot_execute
    refute_record("only provider grok-build with runtime_surface grok_build_cli_acp may execute on this bridge") do |record|
      record["company_ops_packet"]["provider"] = "grok-bot"
      record["execution"]["allowed"] = true
    end
  end

  def test_repository_company_ops_cannot_execute
    refute_record("grok-build packet repository must be idol") do |record|
      record["company_ops_packet"]["repository"] = "company-ops"
      record["execution"]["allowed"] = true
    end
  end

  def test_authority_commit_true_fails
    refute_record("grok-build packet authority.commit must remain false") do |record|
      record["company_ops_packet"]["authority"]["commit"] = true
    end
  end

  def test_graph_v2_switch_without_receipt_fails
    refute_record("Graph v2 remains shadow_not_default; verified_default is refused") do |record|
      record["idol_admission"]["graph_v2_status"] = "verified_default"
      record["idol_admission"]["graph_v2_switch_receipt"] = nil
    end
  end

  def test_forged_graph_switch_receipt_fails
    refute_record("Graph v2 remains shadow_not_default; verified_default is refused") do |record|
      record["idol_admission"]["graph_v2_status"] = "verified_default"
      record["idol_admission"]["graph_v2_switch_receipt"] = "forged-receipt"
    end
  end

  def test_duplicate_claim_fails
    write_ledger([{
      "claim_id" => "claim-kurisu-1",
      "packet_digest" => DIGEST,
      "state" => "claimed"
    }])
    refute_record("duplicate claim is forbidden") do |record|
      record["execution"]["claimed"] = true
    end
  end

  def test_duplicate_promotion_fails
    write_ledger([{
      "claim_id" => "claim-kurisu-1",
      "packet_digest" => DIGEST,
      "state" => "promoted"
    }])
    refute_record("duplicate promotion is forbidden") do |record|
      record["execution"]["promoted"] = true
      record["execution"]["state"] = "promoted"
      record["execution"]["output_digest"] = DIGEST
    end
  end

  def test_lost_wake_resume_without_second_claim_passes
    write_ledger([{
      "claim_id" => "claim-kurisu-1",
      "packet_digest" => DIGEST,
      "state" => "claimed"
    }])
    record = valid_record
    record["restart_state"]["resume_from_durable_claim"] = true
    record["execution"]["claimed"] = false
    record["execution"]["allowed"] = true
    stdout, stderr, status = run_validator(record: record)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_lost_wake_resume_with_second_claim_fails
    write_ledger([{
      "claim_id" => "claim-kurisu-1",
      "packet_digest" => DIGEST,
      "state" => "claimed"
    }])
    refute_record("lost-wake resume must reuse the durable claim without a second claim") do |record|
      record["restart_state"]["resume_from_durable_claim"] = true
      record["execution"]["claimed"] = true
    end
  end

  def test_frozen_unaffected_hash_change_fails
    refute_record("unaffected frozen hash changed") do |record|
      record["invalidation_state"]["frozen_outputs"] = [{
        "path" => @world.fetch(:frozen_relative),
        "sha256" => DIGEST
      }]
    end
  end

  def test_repair_target_may_mismatch_frozen_hash
    record = valid_record
    record["invalidation_state"]["repair_targets"] = [{
      "path" => @world.fetch(:frozen_relative),
      "sha256" => DIGEST
    }]
    record["invalidation_state"]["frozen_outputs"] = [{
      "path" => @world.fetch(:frozen_relative),
      "sha256" => DIGEST
    }]
    stdout, stderr, status = run_validator(record: record)
    assert status.success?, "#{stdout}\n#{stderr}"
    assert_equal "pass", JSON.parse(stdout).fetch("status")
  end

  def test_governing_change_without_founder_approval_fails
    refute_record("governing instruction/policy/schema/skill/provider change requires Founder approval") do |record|
      record["improvement"]["kind"] = "governing"
      record["improvement"]["founder_approval"] = false
    end
  end

  def test_proposer_only_approval_fails
    refute_record("proposer-only approval is forbidden") do |record|
      record["improvement"]["proposer_only_approval"] = true
    end
  end

  def test_active_goal_hot_swap_fails
    refute_record("active-Goal hot swap is forbidden") do |record|
      record["improvement"]["active_goal_hot_swap"] = true
    end
  end

  def test_automatic_preference_promotion_fails
    refute_record("automatic preference promotion is forbidden") do |record|
      record["improvement"]["automatic_preference_promotion"] = true
    end
  end

  def test_competing_loop_fails
    refute_record("competing improvement loop is forbidden") do |record|
      record["improvement"]["competing_loop"] = true
    end
  end

  def test_copied_creative_truth_in_pointer_tree_fails
    Dir.mktmpdir("idol-company-ops-pointers-") do |dir|
      ops = Pathname.new(dir)
      files = {
        "organization/generated/director-profiles/kurisu.idol_graph_cdd.md" => "# Kurisu\n",
        "organization/generated/department-indexes/idol-operations.md" => "# index\n",
        "skills/company-ops-agent-navigation/references/kurisu-idol-graph-cdd.md" => "# nav\n",
        "organization/generated/bot-defaults/kurisu.idol_graph_cdd.json" => "{\"note\": \"idol-invariant: copied PRE-00 rule\"}\n"
      }
      files.each do |relative, body|
        path = ops.join(relative)
        path.dirname.mkpath
        path.write(body)
      end
      stdout, stderr, status = run_validator(extra: ["--company-ops-root", ops.to_s])
      refute status.success?, "#{stdout}\n#{stderr}"
      assert_includes "#{stdout}\n#{stderr}", "Company Ops pointer copies IDOL creative truth"
    end
  end

  def test_unbound_role_fails
    refute_record("assigned Company Ops role is not bound to harness_maintenance") do |record|
      record["company_ops_packet"]["assigned_role_id"] = "yui.reference_worker"
      record["idol_admission"]["profile_id"] = "harness_maintenance"
    end
  end

  def test_denied_allowed_path_fails
    refute_record("allowed_paths entry is outside harness-maintenance write scope") do |record|
      record["company_ops_packet"]["allowed_paths"] = ["AGENTS.md"]
    end
  end

  def test_missing_allowed_paths_fails
    refute_record("allowed_paths") do |record|
      record["company_ops_packet"].delete("allowed_paths")
    end
  end

  def test_yaml_alias_record_fails_closed
    Dir.mktmpdir("idol-bridge-alias-", "/tmp") do |dir|
      path = Pathname.new(dir).join("aliased.yaml")
      path.write(<<~YAML)
        a: &anchor { k: 1 }
        b: *anchor
      YAML
      world = @world
      validator = world.fetch(:artifact_root).join("scripts", "validate_company_ops_idol_bridge.rb")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, validator.to_s, "--json", "--root", world.fetch(:artifact_root).to_s,
        "--record", path.to_s,
        chdir: world.fetch(:artifact_root).to_s
      )
      refute status.success?, "#{stdout}\n#{stderr}"
      payload = JSON.parse(stdout)
      assert_equal "fail", payload.fetch("status")
      joined = payload.fetch("errors").join("\n")
      assert(
        joined.include?("ingress record is missing or unreadable") ||
          joined.include?("ingress record schema"),
        joined
      )
    end
  end

  def valid_record
    world = @world
    {
      "schema_version" => "idol-company-ops-idol-bridge.v1",
      "artifact_type" => "company_ops_idol_ingress_record",
      "company_ops_packet" => {
        "provider" => "grok-build",
        "packet_digest" => DIGEST,
        "author_agent_id" => "becca.od",
        "assigned_role_id" => "kurisu.idol_graph_cdd",
        "profile_id" => "grok_4_6_xhigh",
        "session_id" => "11111111-1111-4111-8111-111111111111",
        "writer_lease_id" => "lease-kurisu-1",
        "writer_lease_version" => 1,
        "lane_id" => "harness_maintenance",
        "input_digest" => DIGEST,
        "repository" => "idol",
        "model" => "grok-4.6",
        "reasoning_effort" => "xhigh",
        "fallback" => "none",
        "native_goal_name" => world.fetch(:goal_id),
        "allowed_paths" => [world.fetch(:frozen_relative)],
        "authority" => {
          "commit" => false,
          "push" => false,
          "merge" => false,
          "deploy" => false,
          "publish" => false,
          "spend" => false,
          "auth_material" => false
        }
      },
      "idol_admission" => {
        "native_goal_id" => world.fetch(:goal_id),
        "native_goal_status" => "admitted",
        "native_goal_path" => world.fetch(:goal_relative),
        "native_goal_sha256" => world.fetch(:goal_sha),
        "dispatch_path" => world.fetch(:dispatch_relative),
        "dispatch_sha256" => world.fetch(:dispatch_sha),
        "role_context_pack_path" => world.fetch(:pack_relative),
        "role_context_pack_sha256" => world.fetch(:pack_sha),
        "profile_id" => "harness_maintenance",
        "lane_id" => "harness_maintenance",
        "provider" => "grok",
        "runtime_surface" => "grok_build_cli_acp",
        "execution_profile_id" => "grok_worker_high",
        "graph_v2_status" => "shadow_not_default",
        "graph_v2_switch_receipt" => nil
      },
      "authority" => {
        "assigned_owner" => "kurisu.idol_graph_cdd",
        "director_owner" => "grok-overall-director",
        "promotion_owner" => "grok-overall-director",
        "self_review" => false,
        "self_promote" => false,
        "may_create_grandchildren" => false,
        "submission_number" => 1,
        "founder_conversation_owner" => false,
        "inherits_founder_or_external_authority" => false
      },
      "capacity" => {
        "idol_native_helper_maximum" => 8,
        "company_ops_physical_session_maximum" => 15,
        "company_ops_may_mutate_idol_ceilings" => false,
        "ceilings_are_multiplied" => false
      },
      "cursor_cloud" => {
        "live_post" => false,
        "auto_create_pr" => false,
        "return_kind" => "branch_return_only"
      },
      "command_kind" => "compiled_intent_md",
      "improvement" => {
        "competing_loop" => false,
        "kind" => "none",
        "founder_approval" => false,
        "proposer_only_approval" => false,
        "active_goal_hot_swap" => false,
        "automatic_preference_promotion" => false
      },
      "invalidation_state" => {
        "repair_targets" => [],
        "frozen_outputs" => [{
          "path" => world.fetch(:frozen_relative),
          "sha256" => world.fetch(:frozen_sha)
        }]
      },
      "restart_state" => {
        "claim_id" => "claim-kurisu-1",
        "resume_from_durable_claim" => false,
        "ledger_path" => world.fetch(:ledger_relative)
      },
      "execution" => {
        "allowed" => true,
        "claimed" => false,
        "promoted" => false,
        "state" => "admitted",
        "output_digest" => nil
      }
    }
  end

  def refute_record(needle)
    record = valid_record
    yield record
    stdout, stderr, status = run_validator(record: record)
    refute status.success?, "expected failure for #{needle}, got #{stdout}\n#{stderr}"
    assert_includes "#{stdout}\n#{stderr}", needle
  end

  def run_validator(record: nil, extra: [])
    world = @world || self.class.world
    root = world.fetch(:artifact_root)
    validator = root.join("scripts", "validate_company_ops_idol_bridge.rb")
    ops = ROOT.join("..", "..", "company-ops")
    Dir.mktmpdir("idol-bridge-record-", "/tmp") do |dir|
      args = [RbConfig.ruby, validator.to_s, "--json", "--root", root.to_s]
      args += ["--company-ops-root", ops.to_s] if ops.directory?
      args += extra
      if record
        path = Pathname.new(dir).join("record.yaml")
        path.write(YAML.dump(record))
        args += ["--record", path.to_s]
      end
      Open3.capture3(*args, chdir: root.to_s)
    end
  end

  def write_ledger(rows)
    @world.fetch(:ledger_path).write(rows.map { |row| JSON.generate(row) }.join("\n") + "\n")
  end

  def self.world
    @world ||= build_world
  end

  def self.build_world
    generator = allocate
    artifact_root = Pathname.new(Dir.mktmpdir("idol-bridge-", "/tmp"))
    %w[scripts schemas automation wiki policies skills].each do |name|
      src = ROOT.join(name)
      next unless src.exist?
      FileUtils.cp_r(src, artifact_root.join(name))
    end
    %w[AGENTS.md README.md].each do |name|
      src = ROOT.join(name)
      FileUtils.cp(src, artifact_root.join(name)) if src.file?
    end
    venv = ROOT.join(".venv-video")
    FileUtils.ln_s(venv, artifact_root.join(".venv-video")) if venv.exist?
    dispatch_id = "BRIDGE#{SecureRandom.hex(3).upcase}"
    run = "runs/harness-test/company-ops-bridge/#{dispatch_id}"
    run_path = artifact_root.join(run)
    goal_relative = "#{run}/work/sources/GOAL.md"
    frozen_relative = "#{run}/work/sources/frozen.yaml"
    ledger_relative = "#{run}/work/claim-ledger.jsonl"
    dispatch_relative = "#{run}/work/department-dispatches/#{dispatch_id}.yaml"
    pack_relative = "#{run}/work/outputs/role-context-pack.json"
    output_relative = "#{run}/work/outputs/bridge-return.yaml"
    goal_id = "GOAL-#{dispatch_id}"
    FileUtils.mkdir_p(run_path.join("work/department-dispatches"))
    FileUtils.mkdir_p(run_path.join("work/sources"))
    FileUtils.mkdir_p(run_path.join("work/outputs"))
    artifact_root.join(goal_relative).write(<<~TEXT)
      # Goal: #{goal_id}

      Status: admitted
      native_goal_id: #{goal_id}
    TEXT
    artifact_root.join(frozen_relative).write("frozen: true\n")
    artifact_root.join(ledger_relative).write("")
    artifact_root.join(output_relative).write("return: fixture\n")
    generator.write_prepared_dispatch(
      root: artifact_root,
      run: run,
      dispatch_id: dispatch_id,
      goal_relative: goal_relative,
      output_relative: output_relative
    )
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      artifact_root.join("scripts/idol_role_context_pack.rb").to_s,
      "build-dispatch",
      "--dispatch", dispatch_relative,
      "--output", pack_relative,
      chdir: artifact_root.to_s
    )
    raise "fixture pack build failed: #{stdout}\n#{stderr}" unless status.success?

    {
      artifact_root: artifact_root,
      run: run,
      run_path: run_path,
      goal_id: goal_id,
      goal_relative: goal_relative,
      goal_sha: Digest::SHA256.file(artifact_root.join(goal_relative)).hexdigest,
      frozen_relative: frozen_relative,
      frozen_sha: Digest::SHA256.file(artifact_root.join(frozen_relative)).hexdigest,
      ledger_relative: ledger_relative,
      ledger_path: artifact_root.join(ledger_relative),
      dispatch_relative: dispatch_relative,
      dispatch_sha: Digest::SHA256.file(artifact_root.join(dispatch_relative)).hexdigest,
      pack_relative: pack_relative,
      pack_sha: Digest::SHA256.file(artifact_root.join(pack_relative)).hexdigest
    }
  end

  def write_prepared_dispatch(root:, run:, dispatch_id:, goal_relative:, output_relative:)
    profile_id = "harness_maintenance"
    checkpoint_id = "skill_profile_routing"
    objective = "Bind native_goal_id #{dispatch_id} and return the exact bounded harness_maintenance bridge artifact."
    profile_contract = dispatch_fixture_profile_contract(profile_id: profile_id, checkpoint_id: checkpoint_id)
    required_skills = profile_contract.fetch("required_skills")
    required_reads = Array(profile_contract.dig("checkpoint", "required_read_ids")).map do |binding_id|
      row = Array(dispatch_fixture_profile_registry["read_bindings"]).find { |candidate| candidate["binding_id"].to_s == binding_id.to_s }
      {
        "path" => row.fetch("path"),
        "sha256" => row.fetch("sha256"),
        "eof_required" => true,
        "reason" => "Exact registered read for #{profile_id}.#{checkpoint_id}."
      }
    end
    policy_read = required_reads.first
    goal_path = root.join(goal_relative)
    grok_profiles = root.join("automation", "providers", "grok-build-profiles.yaml")
    execution_contract = root.join("automation", "harness-execution-contract.yaml")
    dispatch_schema = root.join("schemas", "department-dispatch.schema.json")
    sources = [{
      "source_id" => "native_goal_binding",
      "path" => goal_relative,
      "sha256" => Digest::SHA256.file(goal_path).hexdigest,
      "purpose" => "Fixture Goal bytes."
    }]
    requirement_sources = {
      "founder" => {"path" => goal_relative, "sha256" => Digest::SHA256.file(goal_path).hexdigest, "role" => "goal"},
      "skill" => {"path" => policy_read.fetch("path"), "sha256" => policy_read.fetch("sha256"), "role" => "read"},
      "policy" => {"path" => policy_read.fetch("path"), "sha256" => policy_read.fetch("sha256"), "role" => "policy"},
      "contract" => {"path" => "automation/harness-execution-contract.yaml", "sha256" => Digest::SHA256.file(execution_contract).hexdigest, "role" => "contract"},
      "schema" => {"path" => "schemas/department-dispatch.schema.json", "sha256" => Digest::SHA256.file(dispatch_schema).hexdigest, "role" => "schema"}
    }
    requirements = %w[founder skill policy contract schema output quality hold goal].each_with_index.map do |category, index|
      {
        "requirement_id" => "#{category.upcase}-#{format('%02d', index + 1)}",
        "category" => category,
        "required" => true,
        "source_locator" => requirement_sources[category]&.fetch("path", nil) || "/launch/#{category}",
        "source_binding" => requirement_sources[category],
        "affected_scope" => "The exact bounded fixture artifact.",
        "expected_output_target" => category == "goal" ? "/runtime_return/runtime_goal" : output_relative,
        "evidence_type" => category == "goal" ? "runtime_goal" : (category == "hold" ? "hold" : "artifact"),
        "director_semantic_review_required" => %w[founder skill policy contract schema output quality].include?(category)
      }
    end
    dispatch_fixture_append_recipe_rows!(
      requirements,
      profile_id: profile_id,
      checkpoint_id: checkpoint_id,
      output: {"path" => goal_relative, "sha256" => Digest::SHA256.file(goal_path).hexdigest, "role" => "recipe"}
    )
    anti_flat = ["Keep the fixture Goal, Dispatch, and Pack hash-bound."]
    launch = {
      "prepared_at" => "2026-09-05T17:00:00Z",
      "launched_at" => nil,
      "launch_kind" => "worker_dispatch",
      "compiled_launch_prompt" => dispatch_fixture_compiled_launch_prompt(
        profile_id: profile_id,
        checkpoint_id: checkpoint_id,
        source_ids: ["native_goal_binding"],
        model_or_role_profile: "grok_worker_high"
      ),
      "task" => {
        "task_id" => dispatch_id,
        "role" => "mechanical_coordinator",
        "objective" => objective,
        "exact_scope" => {"mode" => "artifact", "stage_id" => checkpoint_id, "section_ids" => [], "artifact_paths" => [output_relative]}
      },
      "goal_contract" => {
        "required" => true,
        "goal_text" => objective,
        "goal_text_sha256" => Digest::SHA256.hexdigest(objective),
        "source_objective_pointer" => "/launch/task/objective",
        "source_scope_pointer" => "/launch/task/exact_scope",
        "creation_timing" => "before_required_reads_and_creative_work",
        "completion_timing" => "only_after_valid_runtime_return_and_worker_self_check",
        "unsupported_runtime_action" => "goal_surface_unavailable_hold_before_work"
      },
      "requirement_manifest" => requirements,
      "founder_context" => {"decision_epoch" => "FOUNDER-EPOCH-FIXTURE", "locks" => []},
      "required_skills" => required_skills,
      "required_reads" => required_reads,
      "sources" => sources,
      "external_permission" => {"mode" => "closed_local", "allowed_surfaces" => [], "approval_reference" => nil},
      "bounded_output" => {
        "description" => "One hash-bound fixture artifact.",
        "output_kind" => "bounded_artifact",
        "expected_paths" => [output_relative],
        "maximum_artifact_count" => 1,
        "anti_flat_evidence_requirements" => anti_flat
      },
      "authority" => {
        "assigned_owner" => "kurisu.idol_graph_cdd",
        "director_owner" => "grok-overall-director",
        "promotion_owner" => "grok-overall-director",
        "canonical_write" => "bounded_to_expected_paths",
        "external_actions" => "forbidden",
        "may_decide" => ["structural_maintenance_delta"],
        "must_not" => ["creative_authoring", "self_review"]
      },
      "hold_conditions" => ["Required Goal, skill, source, or contract bytes cannot be verified exactly."],
      "recipient" => {"owner" => "grok-overall-director", "role" => "overall_director", "return_route" => "overall_director_after_review"}
    }
    launch.delete("required_reads") if required_reads.empty?
    dispatch_fixture_project_launch_prompt!(launch)
    document = {
      "schema_version" => "idol-department-dispatch.v8",
      "artifact_type" => "department_dispatch",
      "dispatch_id" => dispatch_id,
      "run" => run,
      "lineage" => {
        "lineage_id" => "LINEAGE_#{dispatch_id}",
        "attempt_id" => dispatch_id,
        "attempt_number" => 1,
        "provider" => "grok",
        "runtime_surface" => "grok_build_cli_acp",
        "session_id" => nil,
        "parent_session_id" => "SESSION_GROK_OVERALL_DIRECTOR",
        "parent_lineage_id" => "LINEAGE_GROK_OVERALL_DIRECTOR",
        "parent_dispatch_id" => "DISPATCH_GROK_OVERALL_DIRECTOR",
        "previous_attempt_id" => nil,
        "delegation_depth" => 1,
        "lineage_state" => "active",
        "successor_attempt_id" => nil
      },
      "review_submission" => {
        "review_cycle_id" => dispatch_id,
        "submission_number" => 1,
        "maximum_submissions" => 3,
        "submission_kind" => "initial",
        "root_attempt_id" => dispatch_id,
        "previous_submission_attempt_id" => nil,
        "correction_source" => nil,
        "repair_targets" => [],
        "repair_acceptance_criteria" => [],
        "frozen_outputs" => []
      },
      "lifecycle" => {
        "current_state" => "prepared",
        "events" => [{"state" => "prepared", "at" => launch.fetch("prepared_at"), "actor" => "grok-overall-director"}]
      },
      "review_control" => {
        "queue_policy" => "single_flight_per_recipient_director_then_global_overall_promotion",
        "queue_state" => "not_eligible",
        "queued_at" => nil,
        "queue_priority" => {"dependency_rank" => 0, "returned_at_then_dispatch_id" => true},
        "review_lease" => nil,
        "promotion_lease" => nil
      },
      "launch" => launch,
      "routing_identity" => {
        "logical_role" => "mechanical_coordinator",
        "worker_specialty" => "harness_maintenance",
        "provider" => "grok",
        "logical_profile_alias" => "worker_high",
        "execution_profile_id" => "grok_worker_high",
        "resolved_provider_model" => "grok-4.6",
        "reasoning_effort" => "high",
        "provider_capability_snapshot_sha256" => Digest::SHA256.file(grok_profiles).hexdigest,
        "resolved_profile_snapshot_ref" => "automation/providers/grok-build-profiles.yaml#/profiles/grok_worker_high",
        "session_topology" => "physical_native_session",
        "active_role_binding_id" => "ACTIVE-KURISU-IDOL-GRAPH-CDD",
        "internal_subagent_policy" => "provider_native_default_no_logical_role_or_authority",
        "exact_task_subagent_override" => "none",
        "founder_visible" => false,
        "return_recipient_role" => "overall_director",
        "physical_transfer" => nil
      },
      "internal_delegation_summary" => {
        "provider_native_helpers_used" => false,
        "helper_count" => 0,
        "logical_roles_created" => 0,
        "canonical_owner_changed" => false,
        "founder_conversation_authority_granted" => false
      },
      "runtime_return" => nil,
      "director_review" => nil,
      "promotion" => nil
    }
    root.join(run, "work/department-dispatches/#{dispatch_id}.yaml").write(YAML.dump(document))
  end
end

Minitest.after_run do
  world = ValidateCompanyOpsIdolBridgeTest.instance_variable_get(:@world)
  FileUtils.rm_rf(world[:artifact_root]) if world && world[:artifact_root]
end
