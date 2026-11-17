# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "active_mv_fixture"

class ActiveImageGenerationFixture
  ROOT = ActiveMvFixture::ROOT
  COMPILER = ROOT.join("scripts", "idol_prompt_packet_compile.rb")
  CONTEXT_BUILDER = ROOT.join("scripts", "idol_harness_context_pack.rb")

  attr_reader :mv, :source_02b_path, :source_02b, :context_paths

  def self.create(before_compile: nil)
    fixture = new(before_compile: before_compile)
    fixture.build
    fixture
  rescue StandardError
    fixture&.cleanup
    raise
  end

  def initialize(before_compile: nil)
    @before_compile = before_compile
  end

  def cleanup
    mv&.cleanup
  end

  def build
    @mv = ActiveMvFixture.create
    @before_compile&.call(mv)
    section_output = mv.run_dir.join("02B-section-S01.yaml")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      COMPILER.to_s,
      mv.delta_path.to_s,
      "--output",
      section_output.to_s,
      chdir: ROOT.to_s
    )
    raise "active 02B fixture compile failed: #{stderr}\n#{stdout}" unless status.success?

    @source_02b = YAML.safe_load(section_output.read, aliases: true)
    source_02b["status"] = "approved"
    source_02b.fetch("prompt_packets").each { |packet| packet["status"] = "approved" }
    source_02b.fetch("section_shards").each { |shard| shard["status"] = "passed" }
    intake_path = write_review_intake
    source_02b.fetch("input_files")["section_review_intakes"] = [
      {
        "path" => mv.relative(intake_path),
        "artifact_sha256" => Digest::SHA256.file(intake_path).hexdigest
      }
    ]
    source_02b.fetch("input_files")["section_context_reviews"] = [
      {
        "section_id" => "S01",
        "path" => mv.relative(mv.context_review_path),
        "artifact_sha256" => Digest::SHA256.file(mv.context_review_path).hexdigest
      }
    ]
    packets_by_id = source_02b.fetch("prompt_packets").to_h do |packet|
      [packet.fetch("packet_id"), packet]
    end
    source_02b.dig("section_shards", 0, "local_lineage", "packet_states").each do |state|
      state["packet_value_sha256"] = mv.value_sha(packets_by_id.fetch(state.fetch("packet_id")))
    end
    @source_02b_path = mv.run_dir.join("02B-prompt-packets.yaml")
    write_source_02b

    @context_paths = {}
    [
      ["C01", "BC01_ACTION"],
      ["C01", "BC01_OVERHEAD"],
      ["C02", "BC02_HOLD"]
    ].each { |core_cut_id, branch_cut_id| build_context(core_cut_id, branch_cut_id) }
    self
  end

  def write_source_02b
    packets_by_id = source_02b.fetch("prompt_packets").to_h { |packet| [packet.fetch("packet_id"), packet] }
    source_02b.fetch("section_shards").each do |shard|
      Array(shard.dig("local_lineage", "packet_states")).each do |state|
        state["packet_value_sha256"] = mv.value_sha(packets_by_id.fetch(state.fetch("packet_id")))
      end
    end
    source_02b_path.write(YAML.dump(source_02b))
  end

  def packet(packet_id)
    source_02b.fetch("prompt_packets").find { |row| row.fetch("packet_id") == packet_id } ||
      raise("unknown packet #{packet_id}")
  end

  def context_path(branch_cut_id)
    context_paths.fetch(branch_cut_id)
  end

  def refresh_context(branch_cut_id)
    selected = source_02b.fetch("prompt_packets").find do |row|
      row.fetch("branch_cut_id") == branch_cut_id
    end || raise("unknown Branch Cut #{branch_cut_id}")
    build_context(selected.fetch("core_cut_id"), branch_cut_id)
  end

  def approval_document(packet_id:, adapter: "openai_api_gpt_image_2")
    selected = packet(packet_id)
    execution = selected.fetch("execution")
    attachments = Array(selected["attachments"])
    {
      "schema_version" => "idol_image_generation_section_approval.v6",
      "artifact_type" => "image_generation_scope_approval",
      "content_id" => mv.run_dir.basename.to_s,
      "section_id" => selected.fetch("execution_section_id"),
      "production_scope_id" => selected.fetch("production_scope_id"),
      "source_prompt_packets_sha256" => Digest::SHA256.file(source_02b_path).hexdigest,
      "run_execution_selection" => source_02b.fetch("run_execution_selection"),
      "execution_adapter_id" => execution.fetch("execution_adapter_id"),
      "provider" => execution.fetch("provider"),
      "auth_lane" => execution.fetch("auth_lane"),
      "provider_profile_id" => execution.fetch("provider_profile_id"),
      "provider_profile_sha256" => execution.fetch("provider_profile_sha256"),
      "provider_capability_snapshot_sha256" => execution.fetch("provider_capability_snapshot_sha256"),
      "founder_generation_authority_id" => "FOUNDER-GEN-AUTH-001",
      "external_execution_approved" => true,
      "paid_generation_approved" => true,
      "approved_output_count" => 1,
      "spend_envelope" => "one exact fixture image request",
      "automatic_fallback" => "none",
      "packets" => [
        {
          "packet_id" => packet_id,
          "mode" => selected.fetch("mode"),
          "cut_id" => selected.dig("cut_pointer", "cut_id"),
          "prompt_sha256" => selected.dig("rendered_five_lines", "full_prompt_sha256"),
          "approved_attachment_sha256s" => attachments.map { |row| row.fetch("sha256") },
          "approved_attachment_paths" => attachments.map { |row| row.fetch("actual_path") },
          "expected_output_path" => selected.dig("export_contract", "expected_output_path"),
          "output_count" => 1,
          "decision" => "approved_for_current_job"
        }
      ]
    }
  end

  def write_approval(packet_id:, adapter: "openai_api_gpt_image_2", mutate: nil)
    document = approval_document(packet_id: packet_id, adapter: adapter)
    mutate.call(document) if mutate
    path = mv.run_dir.join("approvals", "#{packet_id}-#{adapter}.yaml")
    path.dirname.mkpath
    path.write(YAML.dump(document))
    path
  end

  private

  def write_review_intake
    path = mv.run_dir.join("review", "decision-intake", "S01-all-pass.yaml")
    path.dirname.mkpath
    evidence_path = mv.context_review_path
    evidence_pointer = {
      "path" => mv.relative(evidence_path),
      "sha256" => Digest::SHA256.file(evidence_path).hexdigest
    }
    decision_owner = {
      "role" => "overall_director",
      "surface" => "overall_founder_acceptance",
      "promotion_authority" => "overall_final_acceptance"
    }
    returned_output = evidence_pointer.merge("role" => "returned_output")
    attempt_id = "ATTEMPT-02B-S01"
    director_review = evidence_pointer.merge(
      "role" => "director_review",
      "row" => "/director_review/reviewed_outputs/0 attempt_id=#{attempt_id}",
      "pointer" => "/director_review/reviewed_outputs/0"
    )
    founder_lineage = {
      "founder_receipt" => evidence_pointer.merge("role" => "founder_receipt"),
      "decision_export" => evidence_pointer.merge("role" => "decision_export"),
      "decision_intake" => evidence_pointer.merge("role" => "decision_intake")
    }
    worker_evidence = {
      "applicability" => "worker_return",
      "lineage_id" => "LINEAGE-02B-S01",
      "attempt_id" => attempt_id,
      "session_id" => "SESSION-02B-S01",
      "director_dispatch_index" => evidence_pointer.merge(
        "row" => "/director_dispatch_index/rows/0 attempt_id=#{attempt_id}",
        "pointer" => "/director_dispatch_index/rows/0"
      )
    }
    affected_scope = {
      "scope_mode" => "single_section",
      "stage_id" => "image_prompt_compilation",
      "section_ids" => ["S01"],
      "chunk_ids" => ["TARGET-S01"],
      "target_ids" => ["TARGET-S01"]
    }
    document = {
      "schema_version" => "idol_founder_review_decision_intake.v7",
      "artifact_type" => "founder_review_decision_intake",
      "review_mode" => "fp_final",
      "run" => mv.relative(mv.run_dir),
      "source_board" => {
        "board_id" => "ACTIVE-02B-S01",
        "board_revision" => 1,
        "manifest" => {
          "path" => mv.relative(mv.context_review_path),
          "sha256" => Digest::SHA256.file(mv.context_review_path).hexdigest
        },
        "decision_export" => {
          "path" => mv.relative(mv.delta_path),
          "sha256" => Digest::SHA256.file(mv.delta_path).hexdigest
        }
      },
      "status" => "ready_for_owner_routing",
      "summary" => {
        "active_review_count" => 1,
        "decision_count" => 1,
        "pass_count" => 1,
        "hold_count" => 0,
        "reject_count" => 0,
        "action_counts" => {"pass" => 1},
        "missing_review_keys" => []
      },
      "decisions" => [
        {
          "review_key" => "REV-S01::CARD-S01",
          "cycle_kind" => "generated_branch_cut",
          "review_mode" => "fp_final",
          "action" => "pass",
          "annotation" => "",
          "routing_status" => "no_change_pass",
          "stage_id" => "image_prompt_compilation",
          "revision_id" => "REV-S01",
          "decision_scope" => "render_candidate",
          "revision_scope" => "section",
          "affected_section_ids" => ["S01"],
          "decision_owner" => decision_owner,
          "decision_question" => "Does S01 preserve the approved Branch-Cut screen truth?",
          "legal_actions" => %w[pass hold reject],
          "affected_scope" => affected_scope,
          "blocking_effect" => "advances_or_holds_only_bound_scope",
          "decision_epoch" => "FOUNDER-EPOCH-ACTIVE",
          "dispatch_id" => "DISPATCH-02B-S01",
          "returned_output" => returned_output,
          "director_review" => director_review,
          "founder_lineage" => founder_lineage,
          "worker_evidence" => worker_evidence,
          "review_target" => {
            "target_id" => "TARGET-S01",
            "level" => "section",
            "display_number" => "1.1",
            "label" => "S01",
            "section_id" => "S01"
          }
        }
      ],
      "creative_rereview_policy" => "founder_direct_decision_skips_additional_llm_creative_verdict",
      "automation_boundaries" => {
        "canonical_creative_write_performed" => false,
        "decision_interpreted_or_rewritten" => false,
        "downstream_invalidation_authored" => false,
        "gate_status_inferred" => false,
        "unnamed_field_lock_created" => false
      }
    }
    path.write(YAML.dump(document))
    path
  end

  def build_context(core_cut_id, branch_cut_id)
    output = mv.run_dir.join(
      "work",
      "context-packs",
      "S01",
      core_cut_id,
      "#{branch_cut_id}.yaml"
    )
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      CONTEXT_BUILDER.to_s,
      mv.run_dir.to_s,
      "--storyboard",
      mv.storyboard_path.to_s,
      "--section",
      "S01",
      "--core-cut-id",
      core_cut_id,
      "--branch-cut-id",
      branch_cut_id,
      "--task",
      "Prepare the exact current Branch-Cut 02B execution context.",
      "--output",
      output.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    raise "active context fixture failed: #{stderr}\n#{stdout}" unless status.success?
    context_paths[branch_cut_id] = output
  end
end
