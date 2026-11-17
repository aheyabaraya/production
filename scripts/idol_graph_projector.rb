#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "lib/idol_graph_production_review_contract"

module IdolGraphProjector
  class ContractError < StandardError; end

  ROOT = Pathname.new(__dir__).join("..").expand_path
  DEFAULT_REGISTRY = ROOT.join("automation", "graph-stage-registry.yaml")
  REGISTRY_VERSION = "idol-graph-stage-registry.v1"
  LEDGER_VERSION = "idol-graph-ledger.v1"
  NODE_VERSION = "idol-graph-node.v1"
  EDGE_VERSION = "idol-graph-edge.v1"
  EVENT_VERSION = "idol-graph-event.v1"
  PROJECTION_VERSION = "idol-graph-run-projection.v1"
  CONTEXTUAL_JUDGMENT_VERSION = "idol_graph_contextual_judgment.v2"
  CONTEXTUAL_JUDGMENT_VALIDATOR = ROOT.join("scripts", "validate_graph_contextual_judgment.rb")
  IDENTIFIER = /\A[a-z][a-z0-9_]*\z/
  SECTION_ID = /\AS[0-9]{2}\z/
  COHORT_ID = /\AC[1-9][0-9]*\z/
  GATE_ID = /\AG[0-4]\z/
  SHA256 = /\A[a-f0-9]{64}\z/
  SCRIPT_AUTHOR = /script|projector|template|compiler|rhai/i
  DIRECTOR_ROLES = %w[
    founder overall_director planning_cdd_p1 planning_cdd_p2 planning_cdd_p3
    section_cluster_cdd edit_director
  ].freeze
  ALL_ROLES = (
    DIRECTOR_ROLES + %w[worker_high research_medium section_image_motion_worker]
  ).freeze
  VIEWS = %w[
    creative_truth evidence_provenance authority_ownership
    execution_session review_decision provider_capability
  ].freeze
  NODE_VIEW = {
    "founder_gate" => "authority_ownership",
    "authority_envelope" => "authority_ownership",
    "decision_epoch" => "authority_ownership",
    "overall_lane" => "authority_ownership",
    "planning_cdd_lane" => "authority_ownership",
    "planning_section_cohort_lane" => "authority_ownership",
    "section_cluster_cdd_lane" => "authority_ownership",
    "edit_director_lane" => "authority_ownership",
    "worker_package" => "authority_ownership",
    "section_cohort" => "authority_ownership",
    "stage_checkpoint" => "execution_session",
    "section" => "creative_truth",
    "major" => "creative_truth",
    "sequence_unit" => "creative_truth",
    "core" => "creative_truth",
    "branch" => "creative_truth",
    "production_cut" => "creative_truth",
    "source" => "evidence_provenance",
    "locator" => "evidence_provenance",
    "derivative" => "evidence_provenance",
    "reference_binding" => "evidence_provenance",
    "attachment_group" => "evidence_provenance",
    "prompt_packet" => "evidence_provenance",
    "generated_image" => "evidence_provenance",
    "motion_storyboard" => "evidence_provenance",
    "video_output" => "evidence_provenance",
    "edit_output" => "evidence_provenance",
    "artifact_pointer" => "evidence_provenance",
    "dispatch" => "execution_session",
    "goal" => "execution_session",
    "provider_session" => "provider_capability",
    "attempt" => "execution_session",
    "return" => "execution_session",
    "output_manifest" => "execution_session",
    "context_pack" => "execution_session",
    "runtime_receipt" => "provider_capability",
    "review" => "review_decision",
    "contextual_judgment" => "review_decision",
    "hold" => "review_decision"
  }.freeze
  EDGE_TYPES = {
    "authority" => %w[owns dispatches returns_to reviews promotes authorized_by constrained_by may_read outside_authority],
    "lineage" => %w[derives_from exact_carries successor_of replaces invalidates preserves],
    "creative" => %w[supports contrasts transforms causes transitions_to embodies complicates resolves judged_by],
    "production" => %w[binds_reference attaches generates animates edits],
    "coordination" => %w[requires blocks joins boundary_with conflicts_with selects_next],
    "provider" => %w[resolved_to executed_by evidenced_by]
  }.freeze
  FAMILY_VIEW = {
    "authority" => "authority_ownership",
    "lineage" => "authority_ownership",
    "creative" => "creative_truth",
    "production" => "evidence_provenance",
    "coordination" => "authority_ownership",
    "provider" => "provider_capability"
  }.freeze
  EVENT_TYPES = %w[
    node_recorded edge_recorded dispatch_opened goal_admitted session_started
    attempt_returned review_recorded promotion_recorded hold_recorded invalidated
    successor_cas_committed lane_retired founder_gate_recorded cohort_bound
  ].freeze
  ACTIVE_WRITER_STATES = %w[admitted running returned reviewed].freeze
  EXPECTED_STAGE_IDS = %w[
    creative_route_discovery song_direction_design candidate_track_analysis
    audio_screen_motion_map song_production_lock front_planning_integration
    mv_performance_direction mv_storyboard_direction storyboard_review
    image_prompt_compilation image_generation_release_gate branch_cut_generation
    generated_branch_cut_review audio_branch_cut_placement video_motion_direction
    video_playback_review edit_assembly_playback_qc edit_finishing_fx
    master_package_release
  ].freeze
  POST_G1_CLASSES = %w[core branch production_cut generated_image motion_storyboard video_output].freeze
  POST_G2_CLASSES = %w[generated_image production_cut].freeze
  POST_G3_CLASSES = %w[video_output edit_output].freeze

  module Canonical
    module_function

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end
  end

  class CohortPartitioner
    def self.sizes(count)
      raise ContractError, "section roster is empty" if count < 1
      return [1] if count == 1
      return [2, 2] + ([3] * ((count - 4) / 3)) if (count % 3) == 1

      case count % 3
      when 0 then [3] * (count / 3)
      when 2 then [2] + ([3] * ((count - 2) / 3))
      else
        raise ContractError, "unpartitionable section count: #{count}"
      end
    end

    def self.partition(section_ids)
      ids = Array(section_ids)
      raise ContractError, "section roster contains duplicates" unless ids.uniq.length == ids.length

      ids.each { |id| raise ContractError, "invalid section id: #{id}" unless id.is_a?(String) && id.match?(SECTION_ID) }
      chunks = []
      cursor = 0
      sizes(ids.length).each_with_index do |size, index|
        slice = ids[cursor, size]
        raise ContractError, "cohort partition overflow" if slice.nil? || slice.length != size

        chunks << {
          "cohort_id" => "C#{index + 1}",
          "section_ids" => slice,
          "size" => size
        }
        cursor += size
      end
      chunks
    end
  end

  class RegistryValidator
    def initialize(path)
      @path = Pathname.new(path).expand_path
    end

    def validate
      raise ContractError, "graph stage registry not found: #{@path}" unless @path.file?

      document = YAML.safe_load(@path.read, aliases: false)
      raise ContractError, "graph stage registry root must be an object" unless document.is_a?(Hash)
      assert_eq(document["schema_version"], REGISTRY_VERSION, "schema_version")
      assert_eq(document["status"], "shadow_read_only", "status")
      assert_eq(document["default_writer"], "forbidden", "default_writer")
      assert_eq(document["legacy_capsule"], "parse_only", "legacy_capsule")
      assert_eq(document["authority"], "read_only_projection", "authority")
      assert_eq(document["creative_truth_policy"], "graph_scripts_never_author", "creative_truth_policy")
      assert_eq(document.dig("migration_policy", "active_default_switch"), "forbidden", "active_default_switch")
      assert_eq(document.dig("migration_policy", "dual_active_writer"), "fail_closed", "dual_active_writer")
      assert_eq(document.dig("migration_policy", "retired_active_stage_labels"), %w[00 01A 02], "retired labels")
      assert_eq(document.dig("studio_execution", "fallback_policy"), "forbidden", "fallback_policy")
      assert_eq(document.dig("cohort_policy", "carry_rule"), "exact_p3_cohort_id_to_v_cohort", "carry_rule")
      assert_eq(document.dig("cohort_policy", "capacity_creates_cohort"), false, "capacity_creates_cohort")

      views = Array(document["views"]).map { |row| row.is_a?(Hash) ? row["view_id"] : nil }
      raise ContractError, "registry must declare the six typed views" unless views == VIEWS

      stages = Array(document["stages"])
      stage_ids = stages.map { |row| row["stage_id"] }
      raise ContractError, "registry stage spine must match the 19-stage PRE-00..05 route" unless stage_ids == EXPECTED_STAGE_IDS

      retired = stages.select { |row| %w[00 01A 02].include?(row["code"].to_s) }
      raise ContractError, "retired stage codes remain active: #{retired.map { |row| row['code'] }.join(', ')}" unless retired.empty?

      gates = Array(document["founder_gates"]).map { |row| row["gate_id"] }
      raise ContractError, "registry founder gates must be exactly G0..G4" unless gates == %w[G0 G1 G2 G3 G4]

      draft = stages.find { |row| row["stage_id"] == "mv_storyboard_direction" }
      unless draft && draft["internal_checkpoint"] == "02a_draft_keyframe" && draft["new_canonical_stage"] == false
        raise ContractError, "02A draft keyframe must remain an internal checkpoint, not a new stage"
      end

      pointers = Array(document["legacy_source_pointers"])
      unless pointers.any? { |row| row["path"] == "automation/harness-stage-registry.yaml" && row["capsule"] == "parse_only" }
        raise ContractError, "registry must pointer the harness stage registry as parse-only legacy"
      end

      {
        "status" => "pass",
        "schema_version" => REGISTRY_VERSION,
        "authority" => "read_only_projection",
        "default_writer" => "forbidden",
        "legacy_capsule" => "parse_only",
        "stage_count" => stages.length,
        "gate_ids" => gates,
        "view_ids" => views
      }
    end

    private

    def assert_eq(actual, expected, label)
      raise ContractError, "#{label} must be #{expected.inspect}, got #{actual.inspect}" unless actual == expected
    end
  end

  class Projector
    def initialize(ledger_path)
      @ledger_path = Pathname.new(ledger_path).expand_path
      raise ContractError, "ledger not found: #{@ledger_path}" unless @ledger_path.file?

      @base = @ledger_path.dirname.realpath
      @ledger = load_mapping(@ledger_path, "ledger")
      @nodes = {}
      @edges = {}
      @events = []
      @contextual_judgments = {}
      @contextual_dispatches = {}
    end

    def build
      validate_root!
      load_nodes!
      load_edges!
      load_events!
      validate_one_overall!
      validate_writers!
      validate_sessions!
      validate_planning_scopes!
      validate_creative_authorship!
      validate_contextual_judgments!
      promotion = validate_promotions!
      gates = validate_founder_gates!
      cohorts = validate_cohorts!
      invalidation = project_invalidation!
      holds = project_holds!
      views = project_views
      providers = project_provider_locks
      legacy = project_legacy_pointers
      body = {
        "schema_version" => PROJECTION_VERSION,
        "authority" => "read_only_projection",
        "run_id" => @ledger.fetch("run_id"),
        "source_ledger_sha256" => Digest::SHA256.file(@ledger_path).hexdigest,
        "hold_reasons" => holds,
        "views" => views,
        "owner_writer_index" => project_writer_index,
        "promotion_evidence" => promotion,
        "invalidation" => invalidation,
        "founder_gates" => gates,
        "cohorts" => cohorts,
        "legacy_source_pointers" => legacy,
        "provider_locks" => providers,
        "next_legal_actions" => project_next_actions(gates, holds)
      }
      body["status"] = holds.empty? ? "pass" : "hold"
      body["projection_digest"] = Canonical.digest(body)
      body
    end

    def self.pretty(projection)
      JSON.pretty_generate(projection) + "\n"
    end

    private

    def validate_root!
      assert_keys!(
        @ledger,
        required: %w[schema_version authority run_id section_roster nodes edges events],
        optional: %w[declared_cohorts invalidation_queries legacy_source_pointers],
        label: "ledger"
      )
      assert!(@ledger["schema_version"] == LEDGER_VERSION, "ledger schema_version must be #{LEDGER_VERSION}")
      assert!(@ledger["authority"] == "read_only_projection", "ledger authority must be read_only_projection")
      assert_identifier!(@ledger["run_id"], "run_id")
      roster = @ledger.fetch("section_roster")
      assert_array!(roster, "section_roster")
      roster.each { |id| assert!(id.is_a?(String) && id.match?(SECTION_ID), "invalid section id: #{id}") }
      assert!(roster.uniq.length == roster.length, "section_roster contains duplicates")
    end

    def load_nodes!
      @ledger.fetch("nodes").each_with_index do |node, index|
        label = "node[#{index}]"
        assert_hash!(node, label)
        assert_eq(node["schema_version"], NODE_VERSION, "#{label}.schema_version")
        node_id = node.fetch("node_id")
        assert_identifier!(node_id, "#{label}.node_id")
        assert!(!@nodes.key?(node_id), "duplicate node_id: #{node_id}")
        node_class = node.fetch("node_class")
        expected_view = NODE_VIEW[node_class]
        assert!(expected_view, "#{label}.node_class is unknown: #{node_class}")
        assert_eq(node["view"], expected_view, "#{label}.view")
        assert_identifier!(node.fetch("logical_id"), "#{label}.logical_id")
        assert_identifier!(node.fetch("scope_id"), "#{label}.scope_id")
        assert!(ALL_ROLES.include?(node["owner_role"]), "#{label}.owner_role is invalid")
        assert!(%w[structural evidence authority].include?(node["truth_kind"]), "#{label}.truth_kind is invalid")
        if node["may_write"]
          assert_identifier!(node["writer_id"], "#{label}.writer_id")
        elsif node.key?("writer_id") && node["writer_id"]
          assert_identifier!(node["writer_id"], "#{label}.writer_id")
        end
        if node["legacy_source"]
          verify_legacy!(node.fetch("legacy_source"), "#{label}.legacy_source")
        end
        if node["authorship"]
          verify_authorship!(node.fetch("authorship"), "#{label}.authorship", creative: false)
        end
        if %w[planning_section_cohort_lane section_cluster_cdd_lane section_cohort].include?(node_class)
          assert!(node["cohort_id"].is_a?(String) && node["cohort_id"].match?(COHORT_ID), "#{label}.cohort_id must be canonical C1..Cn")
        end
        if node_class == "contextual_judgment"
          assert_eq(node["judgment_schema_version"], CONTEXTUAL_JUDGMENT_VERSION, "#{label}.judgment_schema_version")
          assert_identifier!(node["judgment_profile_id"], "#{label}.judgment_profile_id")
          assert!(%w[eligible_for_director_review combine_or_correct hold reject].include?(node["judgment_decision"]), "#{label}.judgment_decision is invalid")
          assert!(!node["may_write"], "#{label} contextual judgment cannot be a writer")
        end
        @nodes[node_id] = node
      end
    end

    def load_edges!
      @ledger.fetch("edges").each_with_index do |edge, index|
        label = "edge[#{index}]"
        assert_hash!(edge, label)
        assert_eq(edge["schema_version"], EDGE_VERSION, "#{label}.schema_version")
        edge_id = edge.fetch("edge_id")
        assert_identifier!(edge_id, "#{label}.edge_id")
        assert!(!@edges.key?(edge_id), "duplicate edge_id: #{edge_id}")
        family = edge.fetch("family")
        allowed = EDGE_TYPES[family]
        assert!(allowed, "#{label}.family is unknown")
        assert!(allowed.include?(edge.fetch("edge_type")), "#{label}.edge_type is invalid for #{family}")
        assert_eq(edge["view"], FAMILY_VIEW.fetch(family), "#{label}.view")
        from = @nodes[edge.fetch("from_node_id")]
        to = @nodes[edge.fetch("to_node_id")]
        assert!(from && to, "#{label} has an unknown endpoint")
        if family == "creative"
          assert!(edge["authorship"], "#{label} creative edge requires authorship")
          verify_authorship!(edge.fetch("authorship"), "#{label}.authorship", creative: true)
        elsif edge["authorship"]
          verify_authorship!(edge.fetch("authorship"), "#{label}.authorship", creative: false)
        end
        if edge["edge_type"] == "invalidates"
          affected = Array(edge["affected_scope_ids"])
          assert!(!affected.empty?, "#{label}.affected_scope_ids must not be empty")
          allowed_scope = Array(from["section_ids"]) & Array(to["section_ids"])
          allowed_scope = [from["scope_id"], to["scope_id"]].compact if allowed_scope.empty?
          extra = affected - allowed_scope
          assert!(extra.empty?, "#{label} invalidates an unrelated section")
        elsif edge.key?("affected_scope_ids")
          raise ContractError, "#{label}.affected_scope_ids is allowed only on invalidates"
        end
        if edge["edge_type"] == "judged_by"
          assert!(to["node_class"] == "contextual_judgment", "#{label} judged_by must target a contextual_judgment")
        elsif edge["edge_type"] == "selects_next"
          assert!(from["node_class"] == "contextual_judgment", "#{label} selects_next must originate at a contextual_judgment")
        end
        @edges[edge_id] = edge
      end
    end

    def load_events!
      seen_seq = {}
      @ledger.fetch("events").each_with_index do |event, index|
        label = "event[#{index}]"
        assert_hash!(event, label)
        assert_eq(event["schema_version"], EVENT_VERSION, "#{label}.schema_version")
        assert_identifier!(event.fetch("event_id"), "#{label}.event_id")
        seq = event.fetch("sequence")
        assert!(seq.is_a?(Integer) && seq >= 1, "#{label}.sequence must be a positive integer")
        assert!(!seen_seq.key?(seq), "duplicate event sequence: #{seq}")
        seen_seq[seq] = true
        assert!(EVENT_TYPES.include?(event.fetch("event_type")), "#{label}.event_type is invalid")
        assert_eq(event["payload_kind"], "structural", "#{label}.payload_kind")
        Array(event["node_ids"]).each do |node_id|
          assert!(@nodes.key?(node_id), "#{label} unknown node_id: #{node_id}")
        end
        Array(event["edge_ids"]).each do |edge_id|
          assert!(@edges.key?(edge_id), "#{label} unknown edge_id: #{edge_id}")
        end
        @events << event
      end
      expected = (1..@events.length).to_a
      actual = @events.map { |event| event.fetch("sequence") }.sort
      assert!(actual == expected, "event sequence must be contiguous from 1")
    end

    def validate_one_overall!
      overall = @nodes.values.select { |node| node["node_class"] == "overall_lane" }
      assert!(overall.length == 1, "exactly one overall_lane is required")
      writers = overall.select { |node| node["may_write"] && node["state"] != "retired" }
      assert!(writers.length == 1, "exactly one active Overall writer is required")
    end

    def validate_writers!
      groups = Hash.new { |hash, key| hash[key] = [] }
      @nodes.each_value do |node|
        next unless node["may_write"]
        next if %w[retired stale invalidated planned].include?(node["state"])

        groups[node.fetch("scope_id")] << node
      end
      groups.each do |scope_id, writers|
        next if writers.length <= 1

        raise ContractError, "scope #{scope_id} has multiple active writers: #{writers.map { |node| node['node_id'] }.join(', ')}"
      end
    end

    def validate_sessions!
      grouped = @nodes.values.select { |node| node["node_class"] == "provider_session" }.group_by do |node|
        [node.fetch("lane_id"), node.fetch("stage_id")]
      end
      grouped.each do |(lane_id, stage_id), sessions|
        label = "lane #{lane_id}/#{stage_id}"
        assert!(sessions.length <= 2, "#{label} exceeds primary+successor maximum two")
        if sessions.length == 2
          roles = sessions.map { |node| node["session_role"] }.sort
          assert!(roles == %w[primary successor], "#{label} sessions must be primary and successor")
          successor = sessions.find { |node| node["session_role"] == "successor" }
          primary = sessions.find { |node| node["session_role"] == "primary" }
          cas = @edges.values.find do |edge|
            edge["edge_type"] == "successor_of" &&
              edge["from_node_id"] == successor["node_id"] &&
              edge["to_node_id"] == primary["node_id"]
          end
          if successor["may_write"]
            assert!(cas, "successor #{successor['node_id']} cannot write before successor_of CAS")
            assert!(primary["state"] == "retired", "primary session must be retired after successor CAS")
            assert!(!primary["may_write"], "retired primary cannot remain an active writer")
          else
            assert!(%w[planned admitted successor_pending].include?(successor["state"]), "successor #{successor['node_id']} must remain read-only before CAS")
          end
        end
        sessions.each do |session|
          assert_eq(session["fallback_policy"], "forbidden", "#{session['node_id']}.fallback_policy")
          executed = @edges.values.select { |edge| edge["edge_type"] == "executed_by" && edge["from_node_id"] == session["node_id"] }
          executed.each do |edge|
            target = @nodes.fetch(edge.fetch("to_node_id"))
            if target["resolved_profile_id"] && target["resolved_profile_id"] != session["resolved_profile_id"]
              raise ContractError, "provider fallback or profile substitution on #{session['node_id']}"
            end
          end
        end
      end
    end

    def validate_planning_scopes!
      planning = @nodes.values.select { |node| %w[planning_cdd_lane planning_section_cohort_lane].include?(node["node_class"]) && node["may_write"] }
      scopes = planning.flat_map { |node| Array(node["write_scope_ids"]) }
      assert!(scopes.uniq.length == scopes.length, "planning write scopes overlap")
      integrators = @nodes.values.select { |node| node["integration_writer"] }
      integrators.each do |node|
        assert_eq(node["owner_role"], "planning_cdd_p1", "only P1 may be the planning integration writer")
      end
    end

    def validate_creative_authorship!
      @edges.each_value do |edge|
        next unless edge["family"] == "creative"

        author = edge.fetch("authorship")
        assert!(%w[founder assigned_model assigned_human].include?(author["author_kind"]), "creative edge #{edge['edge_id']} has invalid author_kind")
        assert!(!author["author_role"].to_s.match?(SCRIPT_AUTHOR), "creative edge #{edge['edge_id']} is script-authored")
      end
    end

    def validate_contextual_judgments!
      expected = {
        "eligible_for_director_review" => ["ready_for_director_review", "director_review"],
        "combine_or_correct" => ["returned", "revise_same_owner"],
        "hold" => ["hold", "return_to_smallest_owner"],
        "reject" => ["rejected", "stop"]
      }
      @nodes.each_value do |node|
        next unless node["node_class"] == "contextual_judgment"

        state, next_edge = expected.fetch(node.fetch("judgment_decision"))
        assert_eq(node["state"], state, "#{node['node_id']}.state")
        pointer = node["pointers"]
        assert_hash!(pointer, "#{node['node_id']}.pointers")
        artifact_path = safe_file(pointer.fetch("artifact_path"), "#{node['node_id']}.pointers.artifact_path")
        artifact_sha = Digest::SHA256.file(artifact_path).hexdigest
        assert_eq(artifact_sha, pointer.fetch("artifact_sha256"), "#{node['node_id']}.pointers.artifact_sha256")
        stdout, stderr, status = Open3.capture3(
          RbConfig.ruby,
          CONTEXTUAL_JUDGMENT_VALIDATOR.to_s,
          "--root",
          @base.to_s,
          pointer.fetch("artifact_path"),
          chdir: ROOT.to_s
        )
        validation_message = [stderr, stdout].reject(&:empty?).join("\n").strip
        assert!(status.success?, "#{node['node_id']}.artifact failed common contextual judgment validation: #{validation_message}")
        artifact = load_mapping(artifact_path, "#{node['node_id']}.artifact")
        assert_eq(artifact["schema_version"], CONTEXTUAL_JUDGMENT_VERSION, "#{node['node_id']}.artifact.schema_version")
        assert_eq(artifact["artifact_type"], "graph_contextual_judgment", "#{node['node_id']}.artifact.artifact_type")
        assert_eq(artifact["profile_id"], node["judgment_profile_id"], "#{node['node_id']}.artifact.profile_id")
        assert_eq(artifact["decision"], node["judgment_decision"], "#{node['node_id']}.artifact.decision")
        assert_eq(artifact["next_edge"], next_edge, "#{node['node_id']}.artifact.next_edge")
        assert_eq(artifact["scope_id"], node["scope_id"], "#{node['node_id']}.artifact.scope_id")
        assert_eq(artifact["aggregate_score_present"], false, "#{node['node_id']}.artifact.aggregate_score_present")
        assert_eq(artifact["automatic_creative_pass"], false, "#{node['node_id']}.artifact.automatic_creative_pass")
        receipt = node.fetch("authorship").fetch("receipt")
        assert_eq(receipt["source_path"], pointer["artifact_path"], "#{node['node_id']}.authorship source")
        assert_eq(receipt["json_pointer"], "/decision", "#{node['node_id']}.authorship pointer")
        dispatch_pointer = artifact.fetch("execution_binding").fetch("dispatch")
        dispatch_path = safe_file(dispatch_pointer.fetch("path"), "#{node['node_id']}.artifact.execution_binding.dispatch.path")
        assert_eq(Digest::SHA256.file(dispatch_path).hexdigest, dispatch_pointer.fetch("sha256"), "#{node['node_id']}.artifact.execution_binding.dispatch.sha256")
        @contextual_judgments[node["node_id"]] = artifact
        @contextual_dispatches[node["node_id"]] = load_mapping(dispatch_path, "#{node['node_id']}.dispatch")
      end
    end

    def validate_promotions!
      promoted = @nodes.values.select { |node| node["state"] == "promoted" && node["node_class"] != "founder_gate" }
      promoted.map do |node|
        evidence = node["evidence"]
        assert!(evidence, "promoted node #{node['node_id']} missing evidence")
        review = @nodes[evidence.fetch("review_id")]
        assert!(review && review["node_class"] == "review" && review["state"] == "reviewed", "promoted node #{node['node_id']} has no reviewed review node")
        assert!(DIRECTOR_ROLES.include?(review["owner_role"]), "promoted node #{node['node_id']} review is not a Director review")
        %w[input_digest result_digest output_hash].each do |key|
          assert_sha!(evidence.fetch(key), "#{node['node_id']}.evidence.#{key}")
        end
        promotes = @edges.values.find do |edge|
          edge["edge_type"] == "promotes" && edge["to_node_id"] == node["node_id"] && edge["from_node_id"] == review["node_id"]
        end
        assert!(promotes, "promoted node #{node['node_id']} has no promotes edge from its review")
        unless node["owner_role"] == "founder"
          review_edges = @edges.values.select do |edge|
            edge["edge_type"] == "reviews" && edge["from_node_id"] == review["node_id"] && edge["to_node_id"] == node["node_id"]
          end
          assert!(review_edges.length == 1, "promoted node #{node['node_id']} must have exactly one Director reviews edge")
          judged_edges = @edges.values.select do |edge|
            edge["edge_type"] == "judged_by" && edge["from_node_id"] == node["node_id"]
          end
          assert!(judged_edges.length == 1, "promoted node #{node['node_id']} must have exactly one contextual judged_by edge")
          judgment = @nodes[judged_edges.first["to_node_id"]]
          assert!(judgment && judgment["node_class"] == "contextual_judgment", "promoted node #{node['node_id']} judgment node is invalid")
          assert_eq(judgment["judgment_decision"], "eligible_for_director_review", "#{judgment['node_id']}.judgment_decision")
          assert_eq(judgment["state"], "ready_for_director_review", "#{judgment['node_id']}.state")
          selected = @edges.values.select do |edge|
            edge["edge_type"] == "selects_next" && edge["from_node_id"] == judgment["node_id"] && edge["to_node_id"] == review["node_id"]
          end
          assert!(selected.length == 1, "promoted node #{node['node_id']} judgment must select its exact Director review")
          dispatch = @contextual_dispatches.fetch(judgment["node_id"])
          reviewer = dispatch.fetch("reviewer")
          recipient = dispatch.fetch("return_recipient")
          reviewer_graph_role = IdolGraphProductionReviewContract.review_graph_role(reviewer.fetch("role"))
          assert_eq(review["owner_role"], reviewer_graph_role, "#{review['node_id']}.owner_role against returned Dispatch reviewer")
          assert_eq(review["lane_id"], reviewer.fetch("lane_id"), "#{review['node_id']}.lane_id against returned Dispatch reviewer")
          assert_eq(recipient.fetch("role"), reviewer.fetch("role"), "#{judgment['node_id']} return_recipient.role against reviewer")
          assert_eq(recipient.fetch("owner"), reviewer.fetch("owner"), "#{judgment['node_id']} return_recipient.owner against reviewer")
          # owner_role describes the topology role, not an assignment's owner ID
          # (for example CDD-V-C1). Exact owner/session remain envelope-bound below.
          assert_eq(review["next_legal_owner"], reviewer_graph_role, "#{review['node_id']}.next_legal_owner against returned Dispatch recipient")
          pointer = node["pointers"]
          assert_hash!(pointer, "promoted node #{node['node_id']}.pointers")
          assert_eq(evidence.fetch("output_hash"), pointer.fetch("artifact_sha256"), "#{node['node_id']}.evidence.output_hash")
          sources = Array(@contextual_judgments.fetch(judgment["node_id"])["source_artifacts"])
          exact_source = sources.any? do |source|
            source.to_h["path"] == pointer["artifact_path"] && source.to_h["sha256"] == pointer["artifact_sha256"]
          end
          assert!(exact_source, "promoted node #{node['node_id']} is not an exact source of its contextual judgment")
          review_pointer = review["pointers"].to_h
          envelope_pointer = {"path" => review_pointer["artifact_path"], "sha256" => review_pointer["artifact_sha256"]}
          judgment_pointer = {"path" => judgment.dig("pointers", "artifact_path"), "sha256" => judgment.dig("pointers", "artifact_sha256")}
          begin
            @production_reviews ||= {}
            cache_key = [envelope_pointer, judgment_pointer]
            verified_review = @production_reviews[cache_key] ||= IdolGraphProductionReviewContract.verify!(
              root: @base, review_pointer: envelope_pointer, expected_judgment: judgment_pointer
            )
          rescue IdolGraphProductionReviewContract::ContractError => e
            raise ContractError, "#{review['node_id']} production Director review: #{e.message}"
          end
          assert_eq(verified_review.dig("output", "decision"), "accept", "#{review['node_id']}.returned Director decision")
          exact_output = {"path" => pointer["artifact_path"], "sha256" => pointer["artifact_sha256"]}
          assert!(verified_review.dig("input", "candidate_outputs").include?(exact_output), "promoted node #{node['node_id']} is outside the returned Director review")
          assert_eq(evidence.fetch("input_digest"), verified_review.fetch("review_input_digest_sha256"), "#{node['node_id']}.review input digest")
          assert_eq(evidence.fetch("result_digest"), verified_review.fetch("result_digest_sha256"), "#{node['node_id']}.review result digest")
        end
        {
          "node_id" => node["node_id"],
          "review_id" => review["node_id"],
          "promotes_edge_id" => promotes["edge_id"],
          "input_digest" => evidence.fetch("input_digest"),
          "result_digest" => evidence.fetch("result_digest"),
          "output_hash" => evidence.fetch("output_hash")
        }
      end.sort_by { |row| row.fetch("node_id") }
    end

    def validate_founder_gates!
      gates = @nodes.values.select { |node| node["node_class"] == "founder_gate" }
      ids = gates.map { |node| node["gate_id"] }.sort
      assert!(ids == %w[G0 G1 G2 G3 G4], "exactly G0..G4 founder_gate nodes are required")
      closed = gates.select { |node| node["state"] == "promoted" }.to_h { |node| [node["gate_id"], node] }
      @nodes.each_value do |node|
        if POST_G1_CLASSES.include?(node["node_class"]) && %w[promoted reviewed running].include?(node["state"])
          assert!(closed["G1"], "Founder gate G1 bypass: #{node['node_id']}")
        end
        if POST_G2_CLASSES.include?(node["node_class"]) && node["state"] == "promoted"
          assert!(closed["G2"], "Founder gate G2 bypass: #{node['node_id']}")
        end
        if POST_G3_CLASSES.include?(node["node_class"]) && node["state"] == "promoted"
          assert!(closed["G3"], "Founder gate G3 bypass: #{node['node_id']}")
        end
        if node["node_class"] == "edit_output" && node["state"] == "promoted"
          assert!(closed["G4"], "Founder gate G4 bypass: #{node['node_id']}")
        end
      end
      gates.sort_by { |node| node["gate_id"] }.map do |node|
        {
          "gate_id" => node.fetch("gate_id"),
          "node_id" => node.fetch("node_id"),
          "state" => node.fetch("state"),
          "required_closed_before" => Array(node["required_closed_before"])
        }
      end
    end

    def validate_cohorts!
      partition = CohortPartitioner.partition(@ledger.fetch("section_roster"))
      if @ledger["declared_cohorts"]
        declared = Array(@ledger["declared_cohorts"]).map do |row|
          {
            "cohort_id" => row.fetch("cohort_id"),
            "section_ids" => Array(row.fetch("section_ids")),
            "size" => Array(row.fetch("section_ids")).length
          }
        end
        assert!(declared == partition, "declared cohorts do not match roster partition")
      end
      mapped = partition.flat_map { |row| row["section_ids"] }
      assert!(mapped == @ledger.fetch("section_roster"), "every section must map to exactly one cohort")
      if partition.length == 1 && partition.first["size"] == 1
        assert!(@ledger.fetch("section_roster").length == 1, "singleton cohort is allowed only for a one-section title")
      elsif @ledger.fetch("section_roster").length > 1
        partition.each do |row|
          assert!([2, 3].include?(row["size"]), "cohort #{row['cohort_id']} size must be 2 or 3")
        end
      end

      p3 = cohort_lanes("planning_section_cohort_lane", partition)
      v_lanes = cohort_lanes("section_cluster_cdd_lane", partition, required: false)
      unless v_lanes.empty?
        p3_ids = p3.map { |row| [row["cohort_id"], row["section_ids"]] }
        v_ids = v_lanes.map { |row| [row["cohort_id"], row["section_ids"]] }
        assert!(p3_ids == v_ids, "V cohort ids must exact-carry P3 cohort ids and section sets")
      end
      {
        "partition" => partition,
        "planning_p3" => p3,
        "section_cluster_v" => v_lanes,
        "carry_rule" => "exact_p3_cohort_id_to_v_cohort"
      }
    end

    def cohort_lanes(node_class, partition, required: true)
      lanes = @nodes.values.select { |node| node["node_class"] == node_class }
      if required
        assert!(lanes.length == partition.length, "#{node_class} count must match roster-derived cohorts")
      elsif lanes.empty?
        return []
      else
        assert!(lanes.length == partition.length, "#{node_class} count must match roster-derived cohorts")
      end
      by_cohort = lanes.to_h { |node| [node.fetch("cohort_id"), node] }
      partition.map do |row|
        lane = by_cohort[row["cohort_id"]]
        assert!(lane, "missing #{node_class} for #{row['cohort_id']}")
        assert_eq(Array(lane["section_ids"]), row["section_ids"], "#{lane['node_id']} section_ids")
        {
          "lane_node_id" => lane["node_id"],
          "cohort_id" => row["cohort_id"],
          "section_ids" => row["section_ids"],
          "state" => lane["state"]
        }
      end
    end

    def project_invalidation!
      outgoing = Hash.new { |hash, key| hash[key] = [] }
      @edges.each_value do |edge|
        outgoing[edge["from_node_id"]] << edge if edge["edge_type"] == "invalidates"
      end
      queries = @ledger["invalidation_queries"]
      starts = if queries
                 Array(queries)
               else
                 outgoing.keys.map { |node_id| { "changed_node_id" => node_id, "scope_ids" => nil } }
               end
      starts.map do |query|
        start_id = query["changed_node_id"] || query["changed_ref"]
        start = @nodes[start_id]
        assert!(start, "invalidation start is unknown: #{start_id}")
        scopes = Array(query["scope_ids"] || start["section_ids"] || [start["scope_id"]])
        affected = []
        visited = { start_id => true }
        queue = [start_id]
        until queue.empty?
          current = queue.shift
          outgoing[current].each do |edge|
            overlap = Array(edge["affected_scope_ids"]) & scopes
            next if overlap.empty?

            target = edge.fetch("to_node_id")
            next if visited[target]

            visited[target] = true
            affected << target
            queue << target
          end
        end
        if query["declared_affected_ids"]
          declared = Array(query["declared_affected_ids"]).sort
          assert!(affected.sort == declared, "declared affected ids do not match invalidation traversal")
        end
        preserved = @nodes.keys.reject { |node_id| visited[node_id] }.sort
        affected.each do |node_id|
          node = @nodes.fetch(node_id)
          assert!(%w[stale invalidated].include?(node["state"]), "affected node #{node_id} must be stale or invalidated")
        end
        {
          "changed_node_id" => start_id,
          "affected_node_ids" => affected.sort,
          "preserved_node_ids" => preserved,
          "scope_ids" => scopes,
          "traversal" => "invalidates_edges_only"
        }
      end.sort_by { |row| row.fetch("changed_node_id") }
    end

    def project_holds!
      @nodes.each_value.with_object([]) do |node, reasons|
        next unless node["state"] == "hold"

        assert!(node["next_legal_owner"], "hold node #{node['node_id']} has no next_legal_owner")
        blockers = @edges.values.select { |edge| edge["edge_type"] == "blocks" && edge["to_node_id"] == node["node_id"] }
        assert!(!blockers.empty?, "hold node #{node['node_id']} has no blocking edge")
        reasons << "hold:#{node['node_id']}"
      end
    end

    def project_views
      VIEWS.to_h do |view|
        [
          view,
          {
            "node_ids" => @nodes.values.select { |node| node["view"] == view }.map { |node| node["node_id"] }.sort,
            "edge_ids" => @edges.values.select { |edge| edge["view"] == view }.map { |edge| edge["edge_id"] }.sort
          }
        ]
      end
    end

    def project_writer_index
      @nodes.values.select { |node| node["may_write"] }.map do |node|
        {
          "scope_id" => node.fetch("scope_id"),
          "owner_role" => node.fetch("owner_role"),
          "writer_id" => node.fetch("writer_id"),
          "may_write" => true,
          "node_id" => node.fetch("node_id")
        }
      end.sort_by { |row| [row["scope_id"], row["node_id"]] }
    end

    def project_provider_locks
      @nodes.values.select { |node| node["node_class"] == "provider_session" }.map do |node|
        {
          "node_id" => node["node_id"],
          "logical_tier" => node.fetch("logical_tier"),
          "resolved_profile_id" => node.fetch("resolved_profile_id"),
          "fallback_policy" => node.fetch("fallback_policy")
        }
      end.sort_by { |row| row.fetch("node_id") }
    end

    def project_legacy_pointers
      rows = []
      @nodes.each_value do |node|
        next unless node["legacy_source"]

        pointer = node.fetch("legacy_source").merge("node_id" => node["node_id"])
        rows << pointer
      end
      Array(@ledger["legacy_source_pointers"]).each do |pointer|
        verify_legacy!(pointer, "ledger.legacy_source_pointers")
        rows << pointer.merge("node_id" => pointer["node_id"] || "ledger")
      end
      rows.sort_by { |row| [row["path"].to_s, row["legacy_id"].to_s, row["node_id"].to_s] }
    end

    def project_next_actions(gates, holds)
      actions = []
      open_gate = gates.find { |row| row["state"] == "planned" }
      if open_gate
        actions << {
          "action" => "close_founder_gate_#{open_gate['gate_id'].downcase}",
          "owner_role" => "founder",
          "scope_id" => open_gate["node_id"]
        }
      end
      holds.each do |reason|
        node_id = reason.split(":", 2).last
        node = @nodes.fetch(node_id)
        actions << {
          "action" => "resolve_hold",
          "owner_role" => node.fetch("next_legal_owner"),
          "scope_id" => node.fetch("scope_id")
        }
      end
      actions
    end

    def verify_authorship!(authorship, label, creative:)
      assert_hash!(authorship, label)
      kind = authorship.fetch("author_kind")
      if creative
        assert!(%w[founder assigned_model assigned_human].include?(kind), "#{label} creative author_kind is invalid")
        assert!(!kind.to_s.match?(SCRIPT_AUTHOR), "#{label} is script-authored")
      else
        assert!(%w[founder assigned_model assigned_human deterministic_projection].include?(kind), "#{label} author_kind is invalid")
      end
      assert!(!authorship.fetch("author_role").to_s.match?(SCRIPT_AUTHOR), "#{label} author_role is script-authored")
      receipt = authorship.fetch("receipt")
      value = resolve_receipt(receipt, label)
      actual = Canonical.digest(value)
      assert_eq(actual, receipt.fetch("value_sha256"), "#{label}.receipt.value_sha256")
    end

    def verify_legacy!(spec, label)
      assert_hash!(spec, label)
      assert_eq(spec["capsule"], "parse_only", "#{label}.capsule")
      relative = spec["local_fixture_path"] || spec.fetch("path")
      path = safe_file(relative, label)
      actual = Digest::SHA256.file(path).hexdigest
      assert_eq(actual, spec.fetch("sha256"), "#{label}.sha256")
    end

    def resolve_receipt(receipt, label)
      path = safe_file(receipt.fetch("source_path"), "#{label}.source_path")
      document = load_source_document(path, "#{label}.source")
      resolve_pointer(document, receipt.fetch("json_pointer"), "#{label}.json_pointer")
    end

    def resolve_pointer(document, pointer, label)
      pointer.split("/").drop(1).reduce(document) do |current, token|
        key = token.gsub("~1", "/").gsub("~0", "~")
        case current
        when Hash
          raise ContractError, "#{label} does not resolve: #{pointer}" unless current.key?(key)

          current.fetch(key)
        when Array
          raise ContractError, "#{label} has invalid array index: #{pointer}" unless key.match?(/\A(?:0|[1-9][0-9]*)\z/)

          index = Integer(key, 10)
          raise ContractError, "#{label} array index is out of range: #{pointer}" unless index < current.length

          current.fetch(index)
        else
          raise ContractError, "#{label} traverses a scalar: #{pointer}"
        end
      end
    end

    def load_source_document(path, label)
      if path.extname.downcase == ".json"
        JSON.parse(path.read)
      else
        YAML.safe_load(path.read, aliases: false)
      end
    rescue JSON::ParserError, Psych::SyntaxError => e
      raise ContractError, "#{label} is invalid: #{e.message}"
    end

    def load_mapping(path, label)
      value = YAML.safe_load(path.read, aliases: false)
      assert_hash!(value, label)
      value
    rescue Psych::SyntaxError => e
      raise ContractError, "#{label} is invalid: #{e.message}"
    end

    def safe_file(relative, label)
      assert!(relative.is_a?(String) && !relative.empty?, "#{label} path must be non-empty")
      path = Pathname.new(relative)
      assert!(!path.absolute? && !path.each_filename.include?(".."), "#{label} path must stay inside the fixture root")
      candidate = @base.join(path).cleanpath
      assert!(candidate.file?, "#{label} path is missing: #{relative}")
      real = candidate.realpath
      prefix = @base.to_s + File::SEPARATOR
      assert!(real.to_s.start_with?(prefix), "#{label} path escapes the fixture root")
      real
    end

    def assert_keys!(value, required:, optional:, label:)
      keys = value.keys
      missing = required - keys
      unknown = keys - required - optional
      raise ContractError, "#{label} is missing keys: #{missing.sort.join(', ')}" unless missing.empty?
      raise ContractError, "#{label} has unknown keys: #{unknown.sort.join(', ')}" unless unknown.empty?
    end

    def assert_hash!(value, label)
      raise ContractError, "#{label} must be an object" unless value.is_a?(Hash)
    end

    def assert_array!(value, label)
      raise ContractError, "#{label} must be an array" unless value.is_a?(Array)
    end

    def assert_identifier!(value, label)
      raise ContractError, "#{label} must be a lowercase identifier" unless value.is_a?(String) && value.match?(IDENTIFIER)
    end

    def assert_sha!(value, label)
      raise ContractError, "#{label} must be a lowercase SHA-256" unless value.is_a?(String) && value.match?(SHA256)
    end

    def assert_eq(actual, expected, label)
      raise ContractError, "#{label} must be #{expected.inspect}, got #{actual.inspect}" unless actual == expected
    end

    def assert!(condition, message)
      raise ContractError, message unless condition
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    registry: IdolGraphProjector::DEFAULT_REGISTRY,
    json: false
  }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: ruby scripts/idol_graph_projector.rb [options] validate-registry|project|digest"
    opts.on("--registry PATH", String, "Graph stage registry path") do |value|
      options[:registry] = Pathname.new(value).expand_path
    end
    opts.on("--ledger PATH", String, "Graph ledger path") do |value|
      options[:ledger] = Pathname.new(value).expand_path
    end
    opts.on("--json", "Emit JSON") do
      options[:json] = true
    end
  end
  parser.parse!
  command = ARGV.shift
  unless %w[validate-registry project digest].include?(command) && ARGV.empty?
    warn parser
    exit 2
  end

  begin
    if command == "validate-registry"
      result = IdolGraphProjector::RegistryValidator.new(options[:registry]).validate
      if options[:json]
        puts JSON.pretty_generate(result)
      else
        puts "OK: graph stage registry valid (#{result['stage_count']} stages, shadow_read_only, default_writer forbidden, parse-only legacy capsule)"
      end
      exit 0
    end

    unless options[:ledger]
      warn "project and digest require --ledger PATH"
      exit 2
    end
    projection = IdolGraphProjector::Projector.new(options[:ledger]).build
    if command == "digest"
      puts projection.fetch("projection_digest")
    elsif options[:json] || command == "project"
      $stdout.write(IdolGraphProjector::Projector.pretty(projection))
    end
    exit(projection.fetch("status") == "pass" ? 0 : 2)
  rescue IdolGraphProjector::ContractError => e
    warn JSON.generate("status" => "fail", "error" => e.message)
    exit 1
  end
end
