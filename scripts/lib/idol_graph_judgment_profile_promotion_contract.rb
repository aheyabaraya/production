# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "time"
require "yaml"
require_relative "idol_graph_goal_evidence_contract"
require_relative "idol_graph_output_manifest_contract"

module IdolGraphJudgmentProfilePromotionContract
  SCHEMA_VERSION = "idol-graph-creative-judgment-profile-promotion.v1"
  ARTIFACT_TYPE = "graph_creative_judgment_profile_promotion"
  RECEIPT_SCHEMA_VERSION = "idol-graph-creative-judgment-profile-evolution-receipt.v1"
  RECEIPT_ARTIFACT_TYPE = "graph_creative_judgment_profile_evolution_receipt"
  SCHEMA_RELATIVE = "schemas/graph-creative-judgment-profile-promotion.schema.json"
  EVOLUTION_EVIDENCE_SCHEMA_RELATIVE = "schemas/graph-creative-judgment-profile-evolution-evidence.schema.json"
  CONTEXTUAL_JUDGMENT_SCHEMA_RELATIVE = "schemas/graph-contextual-judgment.schema.json"
  DIRECTOR_DISPATCH_SCHEMA_RELATIVE = "schemas/graph-department-dispatch.schema.json"
  ROLE_CONTEXT_PACK_SCHEMA_RELATIVE = "schemas/role-context-pack.schema.json"
  FOUNDER_INTERVENTION_SCHEMA_RELATIVE = "schemas/founder-intervention-receipt.schema.json"
  EVOLUTION_EVIDENCE_SCHEMA_VERSION = "idol-graph-creative-judgment-profile-evolution-evidence.v1"
  EVOLUTION_EVIDENCE_ARTIFACT_TYPE = "graph_creative_judgment_profile_evolution_evidence"
  PILOT_SELECTION_ARTIFACT_TYPE = "graph_creative_judgment_profile_real_song_pilot_selection"
  DIRECTOR_REVIEW_SCHEMA_VERSION = EVOLUTION_EVIDENCE_SCHEMA_VERSION
  DIRECTOR_REVIEW_ARTIFACT_TYPE = "graph_creative_judgment_profile_evolution_director_review"
  VALIDATOR_RELATIVE = "scripts/validate_graph_judgment_profile_promotion.rb"
  IMPLEMENTATION_ROOT = Pathname.new(__dir__).join("..", "..").expand_path.cleanpath
  PHASES = %w[proposal shadow pilot founder_approval].freeze
  OUTCOMES = {
    "proposal" => "accepted_for_shadow",
    "shadow" => "passed_shadow",
    "pilot" => "passed_pilot",
    "founder_approval" => "approved_current_pointer_promotion"
  }.freeze
  EVIDENCE_CLASSES = {
    "proposal" => "observed_gap_proposal",
    "shadow" => "representative_shadow_comparison",
    "pilot" => "founder_selected_real_song_pilot",
    "founder_approval" => "founder_authored_approval"
  }.freeze
  SHADOW_REQUIRED_COVERAGE = %w[expected_pass correction hard_gate counterexample_outside_scope].freeze
  STABLE_DISPATCH_IDENTITY_FIELDS = %w[
    dispatch_id run lane_id section_cohort_id section_ids logical_role assigned_owner
    output_writer reviewer return_recipient
  ].freeze
  DIRECTOR_REVIEW_INPUT_SOURCE_ID = "profile_evolution_review_input"
  DIRECTOR_REVIEW_INPUT_FUNCTION = "exact_director_review_input"
  DIRECTOR_REVIEW_INPUT_PURPOSE = "Exact profile evolution Director review input bytes."
  RECEIPT_KEYS = %w[
    schema_version artifact_type receipt_id profile_id phase old_release new_release
    predecessor_receipt_sha256 outcome evidence authorship authority issued_at
  ].freeze
  RECEIPT_AUTHORITY_KEYS = %w[
    scripts_author_creative_truth automatic_profile_tuning automatic_pointer_change
  ].freeze
  RELEASE_POINTER_KEYS = %w[path sha256 release_value_sha256 profile_value_sha256].freeze
  BOOTSTRAP_SEED_RELEASES = {
    "pre_fp_storyline" => "9acb8808d3a04745198f91ed2a5e1650bc8d2e3a2ac158e1774f7d9e1f2372c4",
    "reference_candidate" => "61a1c28b8a298fc985818a0bf3ba6a62fba32377bd12eac6f05125cb48fae29d",
    "front_planning_close" => "78455593bc2ecc0fd1051ed41c11db5b9b2e33dc934bb66dbdd9891d561b95fb",
    "draft_keyframe_proof" => "1f21557329c7801ff141ab2916df96be7733aea277103e23de12064ade772540",
    "pixel_02b" => "b4494c251e1cfd110cd3d4bf9b4e209317f659c2b0ab7467eacad739598dbfd3",
    "playback_03v" => "c94b9bc99a6a2db949d4f8f561024dbc25aa39c431738bac38c22984618e3fda",
    "edit_04_playback" => "540b8233629516732d9dd43e67d494dc882fb5dacb546d689c05089d8a5068e6"
  }.freeze

  module_function

  def validate_binding(root:, binding:, current_release:, profile_id:, registry_status:, validation_mode: "active_promotion")
    root = Pathname.new(root).expand_path.cleanpath
    errors = []
    unless %w[active_promotion historical_audit].include?(validation_mode.to_s)
      return ["profile promotion validation_mode must be active_promotion or historical_audit"]
    end
    unless binding.is_a?(Hash)
      return ["current profile release promotion_binding is missing"]
    end

    promotion_path = verify_artifact_pointer(root, binding, "profile promotion artifact", errors)
    return errors unless promotion_path

    validate_schema(root, promotion_path, errors)
    promotion = load_document(promotion_path, errors, "profile promotion artifact")
    return errors unless promotion

    errors << "profile promotion schema_version is invalid" unless promotion["schema_version"] == SCHEMA_VERSION
    errors << "profile promotion artifact_type is invalid" unless promotion["artifact_type"] == ARTIFACT_TYPE
    errors << "profile promotion profile_id differs from current profile" unless promotion["profile_id"].to_s == profile_id.to_s
    expected_release = canonical_release_pointer(current_release)
    new_release = canonical_release_pointer(promotion["new_release"])
    errors << "profile promotion new_release differs from the current profile release" unless new_release == expected_release
    validate_release_pointer(root, promotion["new_release"], profile_id, "profile promotion new_release", errors)
    validate_authority(promotion["authority"], errors)

    case promotion["mode"].to_s
    when "bootstrap_shadow_seed"
      expected_seed = BOOTSTRAP_SEED_RELEASES[profile_id.to_s]
      expected_promotion_id = "BOOTSTRAP_SHADOW_SEED_#{profile_id.to_s.upcase}"
      errors << "bootstrap shadow seed profile is outside the immutable seed set" if expected_seed.nil?
      unless expected_seed && promotion.dig("new_release", "release_value_sha256").to_s == expected_seed
        errors << "bootstrap shadow seed release is outside the immutable seed set"
      end
      errors << "bootstrap shadow seed promotion_id differs from the immutable profile seed id" unless promotion["promotion_id"].to_s == expected_promotion_id
      errors << "bootstrap shadow seed is valid only while the judgment registry is shadow_not_default" if validation_mode.to_s == "active_promotion" && registry_status.to_s != "shadow_not_default"
      errors << "bootstrap shadow seed must not carry old_release" if promotion.key?("old_release")
      errors << "bootstrap shadow seed must not carry lifecycle_receipts" if promotion.key?("lifecycle_receipts")
      errors << "bootstrap shadow seed status is invalid" unless promotion["status"] == "bootstrap_shadow_seed_only"
      errors << "bootstrap shadow seed cannot authorize a pointer change" unless promotion.dig("authority", "pointer_change_authority") == "none"
    when "founder_approved_current_pointer_promotion"
      validate_current_pointer_promotion(root, promotion, profile_id, errors)
    else
      errors << "profile promotion mode is invalid"
    end
    errors
  end

  def validate_current_pointer_promotion(root, promotion, profile_id, errors)
    errors << "current-pointer promotion status is invalid" unless promotion["status"] == "founder_approved_for_current_pointer_change"
    errors << "current-pointer promotion must be authorized only by the Founder approval receipt" unless promotion.dig("authority", "pointer_change_authority") == "founder_approval_receipt_only"
    old_release = canonical_release_pointer(promotion["old_release"])
    new_release = canonical_release_pointer(promotion["new_release"])
    errors << "current-pointer promotion old_release is missing" if old_release.empty?
    errors << "current-pointer promotion must change the exact release pointer" if !old_release.empty? && old_release == new_release
    validate_release_pointer(root, promotion["old_release"], profile_id, "profile promotion old_release", errors)

    receipts = promotion["lifecycle_receipts"]
    unless receipts.is_a?(Hash) && receipts.keys.map(&:to_s).sort == PHASES.sort
      errors << "profile promotion must exact-bind proposal, shadow, pilot, and Founder approval receipts"
      return
    end

    previous_sha = nil
    seen = []
    PHASES.each do |phase|
      pointer = receipts[phase]
      receipt_path = verify_artifact_pointer(root, pointer, "#{phase} receipt", errors)
      next unless receipt_path

      receipt_sha = pointer["sha256"].to_s
      errors << "profile promotion lifecycle receipt is duplicated: #{phase}" if seen.include?(receipt_sha)
      seen << receipt_sha
      receipt = load_document(receipt_path, errors, "#{phase} receipt")
      if receipt
        validate_phase_receipt(
          root: root,
          receipt: receipt,
          profile_id: profile_id,
          phase: phase,
          old_release: old_release,
          new_release: new_release,
          expected_predecessor_sha: previous_sha,
          errors: errors
        )
      end
      previous_sha = receipt_sha
    end
  end

  def validate_phase_receipt(root:, receipt:, profile_id:, phase:, old_release:, new_release:, expected_predecessor_sha:, errors:)
    unknown = receipt.keys.map(&:to_s) - RECEIPT_KEYS
    missing = RECEIPT_KEYS - receipt.keys.map(&:to_s)
    errors << "#{phase} receipt contains unsupported fields: #{unknown.join(', ')}" unless unknown.empty?
    errors << "#{phase} receipt is missing fields: #{missing.join(', ')}" unless missing.empty?
    errors << "#{phase} receipt schema_version is invalid" unless receipt["schema_version"] == RECEIPT_SCHEMA_VERSION
    errors << "#{phase} receipt artifact_type is invalid" unless receipt["artifact_type"] == RECEIPT_ARTIFACT_TYPE
    errors << "#{phase} receipt profile_id differs from promotion" unless receipt["profile_id"].to_s == profile_id.to_s
    errors << "#{phase} receipt phase is invalid" unless receipt["phase"].to_s == phase
    errors << "#{phase} receipt old_release differs from promotion" unless canonical_release_pointer(receipt["old_release"]) == old_release
    errors << "#{phase} receipt new_release differs from promotion" unless canonical_release_pointer(receipt["new_release"]) == new_release
    predecessor = receipt["predecessor_receipt_sha256"]
    errors << "#{phase} receipt predecessor does not exact-bind the preceding lifecycle receipt" unless predecessor == expected_predecessor_sha
    errors << "#{phase} receipt outcome is invalid" unless receipt["outcome"].to_s == OUTCOMES.fetch(phase)
    validate_receipt_authorship(receipt["authorship"], phase, errors)
    validate_receipt_authority(receipt["authority"], phase, errors)
    validate_timestamp(receipt["issued_at"], phase, errors)

    validate_phase_evidence(
      root: root,
      pointers: receipt["evidence"],
      profile_id: profile_id,
      phase: phase,
      old_release: old_release,
      new_release: new_release,
      errors: errors
    )
  end

  def validate_phase_evidence(root:, pointers:, profile_id:, phase:, old_release:, new_release:, errors:)
    unless pointers.is_a?(Array) && pointers.length == 1
      errors << "#{phase} receipt requires exactly one typed evolution evidence artifact"
      return
    end
    evidence_path = verify_artifact_pointer(root, pointers.first, "#{phase} typed evidence", errors)
    return unless evidence_path

    validate_document_schema(root, EVOLUTION_EVIDENCE_SCHEMA_RELATIVE, evidence_path, "#{phase} typed evidence", errors)
    evidence = load_document(evidence_path, errors, "#{phase} typed evidence")
    return unless evidence

    errors << "#{phase} typed evidence schema_version is invalid" unless evidence["schema_version"] == EVOLUTION_EVIDENCE_SCHEMA_VERSION
    errors << "#{phase} typed evidence artifact_type is invalid" unless evidence["artifact_type"] == EVOLUTION_EVIDENCE_ARTIFACT_TYPE
    errors << "#{phase} typed evidence profile_id differs from promotion" unless evidence["profile_id"].to_s == profile_id.to_s
    errors << "#{phase} typed evidence phase is invalid" unless evidence["phase"].to_s == phase
    errors << "#{phase} typed evidence class is invalid" unless evidence["evidence_class"].to_s == EVIDENCE_CLASSES.fetch(phase)
    errors << "#{phase} typed evidence old_release differs from promotion" unless canonical_release_pointer(evidence["old_release"]) == old_release
    errors << "#{phase} typed evidence new_release differs from promotion" unless canonical_release_pointer(evidence["new_release"]) == new_release
    validate_receipt_authority(evidence["authority"], "#{phase} typed evidence", errors, full: true)
    validate_timestamp(evidence["issued_at"], "#{phase} typed evidence", errors)

    payload = evidence["payload"]
    return errors << "#{phase} typed evidence payload is missing" unless payload.is_a?(Hash)

    case phase
    when "proposal"
      release_path = verify_artifact_pointer(root, new_release, "proposal new release", errors)
      release = release_path && load_document(release_path, errors, "proposal new release")
      profile = release.to_h["profile"].to_h
      known_criteria = Array(profile["criteria"]).map { |criterion| criterion.to_h["criterion_id"].to_s }
      unknown_criteria = Array(payload["affected_criterion_ids"]).map(&:to_s) - known_criteria
      errors << "proposal affected_criterion_ids are outside the candidate release: #{unknown_criteria.join(', ')}" unless unknown_criteria.empty?
      unknown_checkpoints = Array(payload["checkpoint_ids"]).map(&:to_s) - Array(profile["checkpoints"]).map(&:to_s)
      errors << "proposal checkpoint_ids are outside the candidate release: #{unknown_checkpoints.join(', ')}" unless unknown_checkpoints.empty?
      proposal_sets = %w[observed_evidence counterexample_evidence negative_control_evidence].to_h do |field|
        pointers_for_field = Array(payload[field])
        verified = pointers_for_field.each_with_index.each_with_object([]) do |(pointer, index), rows|
          path = verify_artifact_pointer(root, pointer, "proposal #{field}[#{index}]", errors)
          rows << [pointer.to_h["path"].to_s, pointer.to_h["sha256"].to_s] if path
        end
        [field, verified]
      end
      overlaps = proposal_sets.values.combination(2).flat_map { |left, right| left & right }.uniq
      errors << "proposal observed, counterexample, and negative-control evidence must be disjoint" unless overlaps.empty?
    when "shadow"
      comparisons = Array(payload["comparisons"])
      coverage = comparisons.map { |comparison| comparison.to_h["coverage_case"].to_s }
      required_coverage = SHADOW_REQUIRED_COVERAGE.dup
      required_coverage << "not_applicable" if release_supports_not_applicable?(root, new_release, errors)
      missing = required_coverage - coverage
      errors << "shadow typed evidence misses representative coverage: #{missing.join(', ')}" unless missing.empty?
      duplicate_case_ids = comparisons.group_by { |comparison| comparison.to_h["case_id"].to_s }.select { |_id, rows| rows.length > 1 }.keys
      errors << "shadow typed evidence repeats case ids: #{duplicate_case_ids.join(', ')}" unless duplicate_case_ids.empty?
      records = comparisons.each_with_index.each_with_object([]) do |(comparison, index), memo|
        comparison = comparison.to_h
        if comparison["coverage_case"].to_s == "counterexample_outside_scope"
          verify_artifact_pointer(root, comparison["outside_scope_evidence"], "shadow comparison[#{index}] outside-scope evidence", errors)
          errors << "shadow comparison[#{index}] outside-scope reason is missing" if comparison["outside_scope_reason"].to_s.strip.empty?
        end
        old_records = validate_judgment_set(root, [comparison["old_release_judgment"]], profile_id, old_release, "shadow comparison[#{index}] old-release", errors)
        new_records = validate_judgment_set(root, [comparison["new_release_judgment"]], profile_id, new_release, "shadow comparison[#{index}] new-release", errors)
        old_record = old_records.first
        new_record = new_records.first
        if old_record && new_record
          errors << "shadow comparison[#{index}] checkpoint differs between old and new judgments" unless old_record["checkpoint_id"] == new_record["checkpoint_id"]
          unless Array(payload["checkpoint_ids"]).map(&:to_s).include?(new_record["checkpoint_id"])
            errors << "shadow comparison[#{index}] checkpoint is outside the declared evaluation checkpoints"
          end
          unless comparison_parity(old_record, new_record)
            errors << "shadow comparison[#{index}] old/new judgments do not share the exact scope, input digest, and evaluated source bytes"
          end
          validate_shadow_coverage_case(comparison["coverage_case"], new_record, "shadow comparison[#{index}]", errors)
        end
        memo.concat(old_records).concat(new_records)
      end
      validate_evolution_director_review(root, payload["director_review"], profile_id, phase, old_release, new_release, records, payload, errors)
    when "pilot"
      audio_path = verify_artifact_pointer(root, payload["selected_audio"], "pilot selected_audio", errors)
      duration = probe_audio_duration(audio_path)
      errors << "pilot selected_audio lacks a decodable audio stream of at least 30 seconds" unless duration && duration >= 30.0
      if duration && (duration - payload["selected_audio_duration_seconds"].to_f).abs > 0.5
        errors << "pilot selected_audio duration differs from the probed media bytes"
      end
      validate_pilot_song_identity(root, payload, errors)
      validate_pilot_run_binding(root, payload, audio_path, errors)
      validate_pilot_selection_receipt(root, payload["founder_selection_receipt"], profile_id, new_release, payload, errors)
      records = validate_judgment_set(root, payload["new_release_judgments"], profile_id, new_release, "pilot new-release", errors)
      declared_checkpoints = Array(payload["checkpoint_ids"]).map(&:to_s)
      actual_checkpoints = records.map { |record| record["checkpoint_id"] }.uniq
      errors << "pilot checkpoint_ids do not exact-cover the validated judgments" unless declared_checkpoints.sort == actual_checkpoints.sort
      validate_evolution_director_review(root, payload["director_review"], profile_id, phase, old_release, new_release, records, payload, errors)
      errors << "pilot typed evidence must identify a Founder-selected real-song run" unless payload["founder_selected"] == true && payload["real_song"] == true && payload["synthetic"] == false
    when "founder_approval"
      errors << "Founder typed approval must carry an explicit lock" unless payload["explicit_lock"] == true
      errors << "Founder typed approval decision is invalid" unless payload["decision"] == "approved_current_pointer_promotion"
      unless payload["approved_profile_value_sha256"].to_s == new_release["profile_value_sha256"].to_s
        errors << "Founder typed approval does not exact-bind the new profile value"
      end
      verify_source_value_binding(
        root,
        payload["founder_source"],
        "Founder profile approval source",
        errors,
        expected_value: payload["founder_input_verbatim"],
        required_classification: "approval",
        required_bindings: [new_release]
      )
    end
  end

  def validate_judgment_set(root, pointers, profile_id, release_pointer, label, errors)
    unless pointers.is_a?(Array) && !pointers.empty?
      errors << "#{label} judgment set is missing"
      return []
    end
    pointers.each_with_index.each_with_object([]) do |(pointer, index), shas|
      path = verify_artifact_pointer(root, pointer, "#{label} judgment[#{index}]", errors)
      next unless path

      validate_document_schema(root, CONTEXTUAL_JUDGMENT_SCHEMA_RELATIVE, path, "#{label} judgment[#{index}]", errors)
      judgment = load_document(path, errors, "#{label} judgment[#{index}]")
      next unless judgment
      errors << "#{label} judgment[#{index}] schema_version is invalid" unless judgment["schema_version"] == "idol_graph_contextual_judgment.v2"
      errors << "#{label} judgment[#{index}] artifact_type is invalid" unless judgment["artifact_type"] == "graph_contextual_judgment"
      errors << "#{label} judgment[#{index}] profile_id differs" unless judgment["profile_id"].to_s == profile_id.to_s
      unless judgment.dig("execution_binding", "profile_value_sha256").to_s == release_pointer["profile_value_sha256"].to_s
        errors << "#{label} judgment[#{index}] does not exact-bind the expected profile value"
      end
      expected_release = release_pointer.to_h.slice("path", "sha256")
      actual_release = judgment.dig("execution_binding", "profile_release").to_h.slice("path", "sha256")
      errors << "#{label} judgment[#{index}] does not exact-bind the expected immutable release" unless actual_release == expected_release
      errors << "#{label} judgment[#{index}] checkpoint_id is missing" if judgment["checkpoint_id"].to_s.empty?
      validate_judgment_semantics(root, judgment, release_pointer, "#{label} judgment[#{index}]", errors)
      validate_full_contextual_judgment(root, path, "#{label} judgment[#{index}]", errors)
      shas << {
        "sha256" => pointer["sha256"].to_s,
        "checkpoint_id" => judgment["checkpoint_id"].to_s,
        "stage_id" => judgment["stage_id"].to_s,
        "performance_mode" => judgment["performance_mode"].to_s,
        "applicability_tags" => Array(judgment["applicability_tags"]).map(&:to_s).sort,
        "applicability_evidence" => canonical_value(Array(judgment["applicability_evidence"])),
        "decision" => judgment["decision"].to_s,
        "hard_gate" => Array(judgment["hard_gate_findings"]).any?,
        "not_applicable" => Array(judgment["criteria"]).any? { |criterion| criterion.to_h["result"] == "not_applicable" },
        "author_session_id" => judgment.dig("execution_binding", "author_session_id").to_s,
        "scope_id" => judgment["scope_id"].to_s,
        "input_digest_sha256" => judgment.dig("execution_binding", "input_digest_sha256").to_s,
        "source_bindings" => Array(judgment["source_artifacts"]).map { |source| source.to_h.slice("path", "sha256", "value_sha256") }
      }
    end
  end

  def validate_evolution_director_review(root, pointer, profile_id, phase, old_release, new_release, judgment_records, phase_payload, errors)
    review_path = verify_artifact_pointer(root, pointer, "#{phase} Director review", errors)
    return unless review_path

    validate_document_schema(root, EVOLUTION_EVIDENCE_SCHEMA_RELATIVE, review_path, "#{phase} Director review", errors)
    review = load_document(review_path, errors, "#{phase} Director review")
    return unless review
    errors << "#{phase} Director review schema_version is invalid" unless review["schema_version"] == DIRECTOR_REVIEW_SCHEMA_VERSION
    errors << "#{phase} Director review artifact_type is invalid" unless review["artifact_type"] == DIRECTOR_REVIEW_ARTIFACT_TYPE
    errors << "#{phase} Director review profile_id differs" unless review["profile_id"].to_s == profile_id.to_s
    errors << "#{phase} Director review phase differs" unless review["phase"].to_s == phase
    errors << "#{phase} Director review old_release differs" unless canonical_release_pointer(review["old_release"]) == old_release
    errors << "#{phase} Director review new_release differs" unless canonical_release_pointer(review["new_release"]) == new_release
    judgment_shas = judgment_records.map { |record| record["sha256"] }
    unless Array(review["reviewed_judgment_sha256s"]).map(&:to_s).sort == judgment_shas.sort
      errors << "#{phase} Director review does not exact-bind the compared judgments"
    end
    input_path = verify_artifact_pointer(root, review["review_input_manifest"], "#{phase} Director review input manifest", errors)
    if input_path
      input_manifest = load_document(input_path, errors, "#{phase} Director review input manifest")
      expected_input = {
        "schema_version" => "idol-graph-profile-evolution-review-input.v1",
        "artifact_type" => "graph_profile_evolution_review_input",
        "profile_id" => profile_id,
        "phase" => phase,
        "old_release" => old_release,
        "new_release" => new_release,
        "phase_payload" => phase_payload.reject { |key, _| key == "director_review" },
        "reviewed_judgment_sha256s" => judgment_shas
      }
      errors << "#{phase} Director review input manifest differs from the exact phase inputs" unless canonical_value(input_manifest) == canonical_value(expected_input)
      actual_input_digest = structured_sha256(input_manifest)
      errors << "#{phase} Director review input digest is stale" unless review["review_input_digest_sha256"].to_s == actual_input_digest
    end
    author_sessions = judgment_records.map { |record| record["author_session_id"] }.reject(&:empty?).uniq
    if author_sessions.include?(review["reviewer_session_id"].to_s)
      errors << "#{phase} Director review must be independent from judgment author sessions"
    end
    validate_director_dispatch(root, review["director_dispatch"], review, errors)
    errors << "#{phase} Director review decision is invalid" unless review["decision"] == "passed_for_profile_evolution"
  end

  def validate_shadow_coverage_case(coverage_case, record, label, errors)
    valid = case coverage_case.to_s
            when "expected_pass" then record["decision"] == "eligible_for_director_review"
            when "correction" then record["decision"] == "combine_or_correct"
            when "hard_gate" then record["decision"] == "hold" && record["hard_gate"]
            when "counterexample_outside_scope" then record["decision"] == "eligible_for_director_review"
            when "not_applicable" then record["not_applicable"]
            else false
            end
    errors << "#{label} new-release judgment does not prove its declared coverage case" unless valid
  end

  def comparison_parity(old_record, new_record)
    %w[scope_id input_digest_sha256 source_bindings stage_id performance_mode applicability_tags applicability_evidence].all? do |field|
      canonical_value(old_record[field]) == canonical_value(new_record[field])
    end
  end

  def release_supports_not_applicable?(root, release_pointer, errors)
    path = verify_artifact_pointer(root, release_pointer, "shadow new-release applicability", errors)
    return false unless path
    release = load_document(path, errors, "shadow new-release applicability")
    return false unless release
    Array(release.dig("profile", "criteria")).any? do |criterion|
      !criterion.to_h["applies_when"].to_s.empty? || !criterion.to_h["not_applicable"].to_s.empty?
    end
  end

  def validate_judgment_semantics(root, judgment, release_pointer, label, errors)
    release_path = verify_artifact_pointer(root, release_pointer, "#{label} profile release", errors)
    return unless release_path
    release = load_document(release_path, errors, "#{label} profile release")
    return unless release
    profile = release["profile"].to_h
    policy = release["policy"].to_h
    errors << "#{label} stage_id is outside the profile" unless Array(profile["stages"]).include?(judgment["stage_id"])
    errors << "#{label} checkpoint_id is outside the profile" unless Array(profile["checkpoints"]).include?(judgment["checkpoint_id"])
    errors << "#{label} reviewer_role is outside the profile" unless Array(profile["owner_roles"]).include?(judgment["reviewer_role"])
    errors << "#{label} target_message_treatment differs from the profile" unless judgment["target_message_treatment"] == profile["target_message_treatment"]
    errors << "#{label} scope_id differs from assignment_id" unless judgment["scope_id"].to_s == judgment.dig("execution_binding", "assignment_id").to_s
    errors << "#{label} author_role differs from reviewer_role" unless judgment.dig("execution_binding", "author_role").to_s == judgment["reviewer_role"].to_s

    validate_judgment_transport(root, judgment, release_pointer, label, errors)

    expected_criteria = Array(profile["criteria"])
    rows = Array(judgment["criteria"])
    expected_ids = expected_criteria.map { |criterion| criterion.to_h["criterion_id"].to_s }
    ids = rows.map { |criterion| criterion.to_h["criterion_id"].to_s }
    errors << "#{label} criteria do not exact-cover the profile once" unless ids.sort == expected_ids.sort && ids.uniq.length == ids.length
    by_id = rows.to_h { |criterion| [criterion.to_h["criterion_id"].to_s, criterion.to_h] }
    tags = Array(judgment["applicability_tags"]).map(&:to_s)
    numeric = []
    expected_criteria.each do |criterion|
      criterion = criterion.to_h
      row = by_id[criterion["criterion_id"].to_s].to_h
      result = row["result"]
      applies_when = criterion["applies_when"].to_s
      applies = applies_when.empty? || tags.include?(applies_when)
      if result == "not_applicable"
        allowed = !applies || (!criterion["not_applicable"].to_s.empty? && tags.include?(criterion["not_applicable"].to_s))
        allowed ||= criterion["not_applicable"].to_s == "no_performance_job" && judgment["performance_mode"] == "none"
        errors << "#{label} #{criterion['criterion_id']} cannot be not_applicable" unless allowed
      elsif !applies
        errors << "#{label} #{criterion['criterion_id']} must be not_applicable"
      elsif result.is_a?(Integer)
        numeric << [criterion, result]
      end
    end

    decision = judgment["decision"].to_s
    hard_gates = Array(judgment["hard_gate_findings"])
    expected_decision = if hard_gates.any? || numeric.any? { |_criterion, result| result == 0 }
                          policy.dig("grade_routing", hard_gates.any? ? "hard_gate" : "grade_zero")
                        elsif numeric.any? { |_criterion, result| result == 1 }
                          policy.dig("grade_routing", "grade_one")
                        elsif numeric.any? { |criterion, result| result < criterion["minimum"].to_i || (criterion["critical_four"] == true && result != 4) }
                          Array(policy.dig("grade_routing", "grade_two_or_below_profile_floor"))
                        else
                          policy.dig("grade_routing", "all_applicable_floors_and_critical_fours")
                        end
    valid_decision = expected_decision.is_a?(Array) ? expected_decision.include?(decision) : expected_decision == decision
    errors << "#{label} decision does not follow the bound profile" unless valid_decision
    errors << "#{label} next_edge differs from the profile" unless judgment["next_edge"] == policy.dig("decision_edges", decision)
    errors << "#{label} status differs from the profile" unless judgment["status"] == policy.dig("decision_status", decision)
  end

  def validate_full_contextual_judgment(root, path, label, errors)
    validator = IMPLEMENTATION_ROOT.join("scripts", "validate_graph_contextual_judgment.rb")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      validator.to_s,
      "--root", root.to_s,
      "--mode", "profile_evolution_evidence",
      path.to_s,
      chdir: IMPLEMENTATION_ROOT.to_s
    )
    return if status.success?
    detail = [stderr, stdout].join(" ").strip
    errors << "#{label} failed full contextual judgment validation: #{detail}"
  end

  def validate_judgment_transport(root, judgment, release_pointer, label, errors)
    execution = judgment["execution_binding"].to_h
    dispatch_path = verify_artifact_pointer(root, execution["dispatch"], "#{label} execution dispatch", errors)
    pack_path = verify_artifact_pointer(root, execution["role_context_pack"], "#{label} execution Role Context Pack", errors)
    return unless dispatch_path && pack_path

    validate_document_schema(root, DIRECTOR_DISPATCH_SCHEMA_RELATIVE, dispatch_path, "#{label} execution dispatch", errors)
    dispatch = load_document(dispatch_path, errors, "#{label} execution dispatch")
    return unless dispatch
    errors << "#{label} execution dispatch must be a returned Graph Department Dispatch" unless dispatch["artifact_type"] == "graph_department_dispatch" && dispatch["lifecycle_state"] == "returned"
    errors << "#{label} execution dispatch_id differs" unless dispatch["dispatch_id"].to_s == execution["assignment_id"].to_s
    errors << "#{label} execution dispatch profile differs" unless dispatch["judgment_profile_id"].to_s == judgment["profile_id"].to_s
    errors << "#{label} execution dispatch Goal differs" unless dispatch.dig("goal_evidence", "native_goal_id").to_s == execution["goal_id"].to_s
    errors << "#{label} execution dispatch Goal event differs" unless dispatch.dig("goal_evidence", "goal_terminal_event_sha256").to_s == execution["goal_terminal_event_sha256"].to_s
    errors << "#{label} execution dispatch input digest differs" unless dispatch["input_digest_sha256"].to_s == execution["input_digest_sha256"].to_s
    errors << "#{label} execution dispatch writer session differs" unless dispatch.dig("output_writer", "session_id").to_s == execution["author_session_id"].to_s
    errors << "#{label} execution dispatch manifest differs" unless dispatch["output_manifest"].to_h.slice("path", "sha256") == execution["output_manifest"].to_h.slice("path", "sha256")
    begin
      IdolGraphGoalEvidenceContract.verify!(
        root: root,
        provider_binding: dispatch["provider_binding"],
        goal_evidence: dispatch["goal_evidence"],
        validation_mode: "active_promotion"
      )
    rescue IdolGraphGoalEvidenceContract::ContractError => e
      errors << "#{label} execution Goal evidence is invalid (#{e.code}): #{e.message}"
    end
    validate_provider_goal_attestation(root, dispatch, "#{label} execution Goal", errors)

    manifest = begin
      IdolGraphOutputManifestContract.verify!(root: root, pointer: execution["output_manifest"], dispatch: dispatch)
    rescue IdolGraphOutputManifestContract::ContractError => e
      errors << "#{label} output manifest is invalid (#{e.code}): #{e.message}"
      nil
    end
    response_path = verify_artifact_pointer(root, execution["author_response"], "#{label} author response", errors)
    if response_path
      response = load_document(response_path, errors, "#{label} author response")
      expected_value = judgment.reject { |key, _| key == "execution_binding" }
      expected_response = {
        "schema_version" => "idol-graph-contextual-judgment-author-response.v1",
        "artifact_type" => "graph_contextual_judgment_author_response",
        "provider" => dispatch.dig("provider_binding", "registered_provider"),
        "native_goal_id" => execution["goal_id"],
        "author_role" => execution["author_role"],
        "author_session_id" => execution["author_session_id"],
        "judgment_value_sha256" => structured_sha256(expected_value),
        "response_payload" => expected_value
      }
      errors << "#{label} author response differs from the exact model judgment bytes" unless canonical_value(response) == canonical_value(expected_response)
      if manifest
        response_binding = execution["author_response"].to_h.slice("path", "sha256")
        output_bindings = manifest.fetch("outputs").map { |output| output.slice("path", "sha256") }
        errors << "#{label} output manifest does not exact-bind the author response" unless output_bindings.include?(response_binding)
      end
    end

    validate_document_schema(root, ROLE_CONTEXT_PACK_SCHEMA_RELATIVE, pack_path, "#{label} execution Role Context Pack", errors)
    pack = load_document(pack_path, errors, "#{label} execution Role Context Pack")
    return unless pack
    begin
      require_relative "idol_role_context_pack"
      pack_errors = IdolRoleContextPack.validate_pack(
        root: root,
        pack: pack,
        validation_mode: "profile_evolution_evidence"
      )
      errors.concat(pack_errors.map { |message| "#{label} Role Context Pack failed full candidate projection validation: #{message}" })
    rescue IdolRoleContextPack::ContractError => e
      errors << "#{label} Role Context Pack failed full candidate projection validation: #{e.message}"
    end
    errors << "#{label} Role Context Pack must be a passed Graph v2 pack" unless pack["status"] == "pass" && pack.dig("activation_binding", "writer") == "graph_v2"
    errors << "#{label} Role Context Pack assignment differs" unless pack.dig("identity", "assignment_id").to_s == execution["assignment_id"].to_s
    errors << "#{label} Role Context Pack checkpoint differs" unless pack.dig("identity", "checkpoint_id").to_s == judgment["checkpoint_id"].to_s
    errors << "#{label} Role Context Pack stage differs" unless pack.dig("identity", "stage_id").to_s == judgment["stage_id"].to_s
    errors << "#{label} Role Context Pack role differs" unless pack.dig("identity", "role").to_s == judgment["reviewer_role"].to_s
    errors << "#{label} Role Context Pack profile differs" unless pack.dig("creative_judgment_contract", "profile_id").to_s == judgment["profile_id"].to_s
    errors << "#{label} Role Context Pack profile value differs" unless pack.dig("creative_judgment_contract", "profile_value_sha256").to_s == release_pointer["profile_value_sha256"].to_s
    errors << "#{label} Role Context Pack release differs" unless pack.dig("creative_judgment_contract", "profile_release").to_h == release_pointer.to_h.slice("path", "sha256")
    errors << "#{label} Role Context Pack dispatch identity differs" unless pack.dig("graph_dispatch_identity", "dispatch_id").to_s == dispatch["dispatch_id"].to_s
    projected_dispatch = pack["graph_dispatch_identity"].to_h
    unless %w[prepared launched].include?(projected_dispatch["dispatch_lifecycle_state_at_projection"].to_s)
      errors << "#{label} Role Context Pack judgment identity must come from a prepared or launched Dispatch snapshot"
    end
    projected_stable = projected_dispatch.slice(*STABLE_DISPATCH_IDENTITY_FIELDS)
    expected_stable = dispatch.slice(*STABLE_DISPATCH_IDENTITY_FIELDS)
    errors << "#{label} Role Context Pack stable dispatch identity differs from the returned execution Dispatch" unless canonical_value(projected_stable) == canonical_value(expected_stable)
    pack_provider = pack["provider_binding"].to_h
    dispatch_provider = dispatch["provider_binding"].to_h
    {
      "provider" => "registered_provider",
      "runtime_surface" => "runtime_surface",
      "logical_profile_alias" => "logical_profile_alias",
      "provider_profile_id" => "execution_profile_id",
      "exact_model" => "resolved_provider_model",
      "reasoning_effort" => "reasoning_effort"
    }.each do |pack_field, dispatch_field|
      unless pack_provider[pack_field].to_s == dispatch_provider[dispatch_field].to_s
        errors << "#{label} Role Context Pack provider #{pack_field} differs from execution dispatch #{dispatch_field}"
      end
    end
    unless pack_provider["registry_sha256"].to_s == dispatch_provider["provider_capability_snapshot_sha256"].to_s
      errors << "#{label} Role Context Pack provider registry snapshot differs from execution dispatch capability snapshot"
    end
    unless pack_provider["fallback_policy"] == "forbidden" && dispatch_provider["fallback_allowed"] == false && dispatch_provider["silent_substitution_allowed"] == false
      errors << "#{label} Role Context Pack and execution dispatch fallback boundaries differ"
    end

    source_bindings = Array(judgment["source_artifacts"]).each_with_index.map do |pointer, index|
      path = verify_artifact_pointer(root, pointer, "#{label} source_artifacts[#{index}]", errors)
      path ? [path.relative_path_from(root.realpath).to_s, pointer.to_h["sha256"].to_s] : nil
    end.compact
    if manifest
      output_bindings = manifest.fetch("outputs").map { |output| [output.fetch("path"), output.fetch("sha256")] }
      errors << "#{label} source artifacts are outside the fully verified output manifest" unless (source_bindings - output_bindings).empty?
    end
  end

  def validate_pilot_run_binding(root, payload, audio_path, errors)
    song = payload["song_identity"].to_h
    expected_song_hash = structured_sha256("artist" => song["artist"], "title" => song["title"])
    errors << "pilot song identity SHA-256 is stale" unless song["identity_sha256"].to_s == expected_song_hash
    run = Pathname.new(payload["run"].to_s)
    run_path = root.join(run).expand_path.cleanpath
    unless run_path.directory?
      errors << "pilot run directory is missing"
      return
    end
    return unless audio_path
    begin
      relative = audio_path.realpath.relative_path_from(run_path.realpath).to_s
      errors << "pilot selected_audio must be inside the selected run" if relative == ".." || relative.start_with?("../")
    rescue ArgumentError, Errno::ENOENT
      errors << "pilot selected_audio must be inside the selected run"
    end
  end

  def validate_pilot_song_identity(root, payload, errors)
    path = verify_artifact_pointer(root, payload["song_identity_artifact"], "pilot song identity artifact", errors)
    return unless path
    artifact = load_document(path, errors, "pilot song identity artifact")
    return unless artifact
    expected = {
      "schema_version" => "idol-graph-selected-song-identity.v1",
      "artifact_type" => "graph_selected_song_identity",
      "run" => payload["run"],
      "artist" => payload.dig("song_identity", "artist"),
      "title" => payload.dig("song_identity", "title"),
      "identity_sha256" => payload.dig("song_identity", "identity_sha256"),
      "selected_audio" => payload["selected_audio"].to_h.slice("path", "sha256")
    }
    errors << "pilot song identity artifact differs from the selected song and audio bytes" unless canonical_value(artifact) == canonical_value(expected)
  end

  def validate_pilot_selection_receipt(root, pointer, profile_id, new_release, payload, errors)
    path = verify_artifact_pointer(root, pointer, "pilot Founder selection receipt", errors)
    return unless path
    validate_document_schema(root, EVOLUTION_EVIDENCE_SCHEMA_RELATIVE, path, "pilot Founder selection receipt", errors)
    selection = load_document(path, errors, "pilot Founder selection receipt")
    return unless selection
    errors << "pilot Founder selection receipt artifact_type is invalid" unless selection["artifact_type"] == PILOT_SELECTION_ARTIFACT_TYPE
    errors << "pilot Founder selection receipt profile_id differs" unless selection["profile_id"].to_s == profile_id.to_s
    errors << "pilot Founder selection receipt new_release differs" unless canonical_release_pointer(selection["new_release"]) == new_release
    errors << "pilot Founder selection receipt run differs" unless selection["run"].to_s == payload["run"].to_s
    errors << "pilot Founder selection receipt song identity differs" unless selection["song_identity_sha256"].to_s == payload.dig("song_identity", "identity_sha256").to_s
    errors << "pilot Founder selection receipt song identity artifact differs" unless selection["song_identity_artifact"].to_h == payload["song_identity_artifact"].to_h
    errors << "pilot Founder selection receipt audio differs" unless selection["selected_audio"].to_h == payload["selected_audio"].to_h
    unless (selection["selected_audio_duration_seconds"].to_f - payload["selected_audio_duration_seconds"].to_f).abs <= 0.001
      errors << "pilot Founder selection receipt audio duration differs"
    end
    errors << "pilot Founder selection receipt is not an explicit Founder selection" unless selection["founder_selected"] == true
    authority = selection["authority"].to_h
    unless authority == {"profile_pointer_change_authorized" => false, "execution_authorized" => false, "default_cutover_authorized" => false}
      errors << "pilot Founder selection receipt grants unsupported authority"
    end
    verify_source_value_binding(
      root,
      selection["founder_source"],
      "pilot Founder selection source",
      errors,
      required_classification: "explicit_lock",
      required_run: payload["run"],
      required_bindings: [payload["song_identity_artifact"], payload["selected_audio"], new_release]
    )
    validate_timestamp(selection["issued_at"], "pilot Founder selection receipt", errors)
  end

  def verify_source_value_binding(root, binding, label, errors, expected_value: nil, required_classification: nil, required_run: nil, required_bindings: [])
    path = verify_artifact_pointer(root, binding, label, errors)
    return nil unless path
    validate_document_schema(root, FOUNDER_INTERVENTION_SCHEMA_RELATIVE, path, label, errors)
    source = load_document(path, errors, label)
    return nil unless source
    errors << "#{label} is not a Founder intervention receipt" unless source["artifact_type"] == "founder_intervention_receipt"
    errors << "#{label} is not an explicit Founder lock" unless source.dig("authority", "explicit_lock") == true
    if required_classification && source.dig("authority", "classification").to_s != required_classification
      errors << "#{label} classification differs from #{required_classification}"
    end
    if required_run && source["run"].to_s != required_run.to_s
      errors << "#{label} run differs from the selected pilot run"
    end
    expected_root = root.join(source["run"].to_s, "review", "founder-interventions").expand_path.cleanpath
    begin
      relative = path.realpath.relative_path_from(expected_root.realpath).to_s
      errors << "#{label} must live under its run-local Founder intervention directory" if relative == ".." || relative.start_with?("../")
    rescue ArgumentError, Errno::ENOENT
      errors << "#{label} must live under its run-local Founder intervention directory"
    end
    required_bindings.each do |required|
      matched = Array(source.dig("routing", "affected_artifacts")).any? do |candidate|
        candidate.to_h["path"].to_s == required.to_h["path"].to_s && candidate.to_h["sha256"].to_s == required.to_h["sha256"].to_s
      end
      errors << "#{label} does not exact-bind a required selected artifact" unless matched
    end
    value = resolve_json_pointer(source, binding["json_pointer"], label, errors)
    return nil if value.nil?
    errors << "#{label} value SHA-256 is stale" unless structured_sha256(value) == binding["value_sha256"].to_s
    errors << "#{label} differs from the bound Founder input" unless expected_value.nil? || value == expected_value
    value
  end

  def validate_director_dispatch(root, pointer, review, errors)
    path = verify_artifact_pointer(root, pointer, "#{review['phase']} Director review dispatch", errors)
    return unless path
    validate_document_schema(root, DIRECTOR_DISPATCH_SCHEMA_RELATIVE, path, "#{review['phase']} Director review dispatch", errors)
    dispatch = load_document(path, errors, "#{review['phase']} Director review dispatch")
    return unless dispatch
    errors << "Director review dispatch is not a Graph Department Dispatch" unless dispatch["artifact_type"] == "graph_department_dispatch"
    errors << "Director review dispatch must be an immutable returned snapshot" unless dispatch["lifecycle_state"].to_s == "returned"
    errors << "Director review dispatch writer role differs" unless dispatch["assigned_owner"].to_s == review["reviewer_role"].to_s
    errors << "Director review dispatch writer session differs" unless dispatch.dig("output_writer", "session_id").to_s == review["reviewer_session_id"].to_s
    expected_lane = {
      "overall_director" => ["overall", "overall_director", nil],
      "planning_cdd_p1" => ["planning_p1", "planning_cdd", nil],
      "edit_director" => ["edit_director", "edit_director", nil]
    }[review["reviewer_role"].to_s]
    if review["reviewer_role"].to_s == "section_cluster_cdd_ci"
      match = /\Asection_cluster_v_c([1-9][0-9]*)\z/.match(dispatch["lane_id"].to_s)
      valid_section_lane = match && dispatch["logical_role"].to_s == "section_cluster_cdd" && dispatch["section_cohort_id"].to_s == "C#{match[1]}"
      errors << "Director review dispatch lane, role, or cohort differs from the reviewer" unless valid_section_lane
    elsif expected_lane
      lane, logical_role, cohort = expected_lane
      unless dispatch["lane_id"].to_s == lane && dispatch["logical_role"].to_s == logical_role && dispatch["section_cohort_id"] == cohort
        errors << "Director review dispatch lane, role, or cohort differs from the reviewer"
      end
    end
    errors << "Director review dispatch judgment profile differs" unless dispatch["judgment_profile_id"].to_s == review["profile_id"].to_s
    errors << "Director review dispatch input digest differs from the exact review input manifest" unless dispatch["input_digest_sha256"].to_s == review["review_input_digest_sha256"].to_s
    errors << "profile evolution Director review must be owned by the Overall Director" unless review["reviewer_role"].to_s == "overall_director"
    pack_path = verify_artifact_pointer(root, review["role_context_pack"], "#{review['phase']} Director review Role Context Pack", errors)
    director_pack = pack_path && load_document(pack_path, errors, "#{review['phase']} Director review Role Context Pack")
    if director_pack
      begin
        require_relative "idol_role_context_pack"
        pack_errors = IdolRoleContextPack.validate_pack(root: root, pack: director_pack, validation_mode: "profile_evolution_evidence")
        errors.concat(pack_errors.map { |message| "Director review Role Context Pack failed full projection validation: #{message}" })
      rescue IdolRoleContextPack::ContractError => e
        errors << "Director review Role Context Pack failed full projection validation: #{e.message}"
      end
      errors << "Director review Role Context Pack identity differs" unless director_pack.dig("identity", "assignment_id").to_s == dispatch["dispatch_id"].to_s && director_pack.dig("identity", "role").to_s == "overall_director" && director_pack.dig("identity", "checkpoint_id").to_s == "director_startup"
      errors << "Director review Role Context Pack must come from a launched snapshot" unless director_pack.dig("current_node", "state").to_s == "launched"
      expected_review_source = {
        "source_id" => DIRECTOR_REVIEW_INPUT_SOURCE_ID,
        "path" => review.dig("review_input_manifest", "path"),
        "sha256" => review.dig("review_input_manifest", "sha256"),
        "purpose" => DIRECTOR_REVIEW_INPUT_PURPOSE,
        "locator" => "/",
        "function" => DIRECTOR_REVIEW_INPUT_FUNCTION,
        "role_groups" => ["overall_director"],
        "disposition" => "applied"
      }
      unless canonical_value(Array(director_pack["creative_source_pointers"])) == canonical_value([expected_review_source])
        errors << "Director review Role Context Pack must exact-project the review input manifest as its typed creative source"
      end
      launch_path = verify_artifact_pointer(root, director_pack["source_envelope"], "Director review Role Context Pack launch dispatch", errors)
      launch_dispatch = launch_path && load_document(launch_path, errors, "Director review Role Context Pack launch dispatch")
      if launch_dispatch
        errors << "Director review Role Context Pack source must be a launched Dispatch" unless launch_dispatch["lifecycle_state"].to_s == "launched"
        launch_stable = launch_dispatch.slice(*STABLE_DISPATCH_IDENTITY_FIELDS)
        returned_stable = dispatch.slice(*STABLE_DISPATCH_IDENTITY_FIELDS)
        errors << "Director review Role Context Pack stable dispatch identity differs from the returned Dispatch" unless canonical_value(launch_stable) == canonical_value(returned_stable)
      end
    end
    begin
      IdolGraphGoalEvidenceContract.verify!(
        root: root,
        provider_binding: dispatch["provider_binding"],
        goal_evidence: dispatch["goal_evidence"],
        validation_mode: "active_promotion"
      )
    rescue IdolGraphGoalEvidenceContract::ContractError => e
      errors << "Director review dispatch Goal evidence is invalid (#{e.code}): #{e.message}"
    end
    validate_provider_goal_attestation(root, dispatch, "Director review dispatch Goal", errors)
    begin
      require_relative "idol_role_context_pack"
      resolved_provider, provider_holds = IdolRoleContextPack.resolve_provider(
        root: root,
        role: review["reviewer_role"],
        provider: dispatch.dig("provider_binding", "registered_provider"),
        runtime_surface: dispatch.dig("provider_binding", "runtime_surface"),
        logical_profile_alias: "frontier_director"
      )
      errors << "Director review dispatch provider is unresolved: #{provider_holds.join(', ')}" unless provider_holds.empty?
      provider = dispatch["provider_binding"].to_h
      expected_provider = {
        "registered_provider" => resolved_provider["provider"],
        "runtime_surface" => resolved_provider["runtime_surface"],
        "logical_profile_alias" => resolved_provider["logical_profile_alias"],
        "execution_profile_id" => resolved_provider["provider_profile_id"],
        "resolved_provider_model" => resolved_provider["exact_model"],
        "reasoning_effort" => resolved_provider["reasoning_effort"],
        "provider_capability_snapshot_sha256" => resolved_provider["registry_sha256"],
        "fallback_allowed" => false,
        "silent_substitution_allowed" => false
      }
      errors << "Director review dispatch provider differs from the registered frontier snapshot" unless canonical_value(provider) == canonical_value(expected_provider)
      if director_pack && canonical_value(director_pack["provider_binding"].to_h) != canonical_value(resolved_provider)
        errors << "Director review Role Context Pack provider differs from the registered frontier snapshot"
      end
    rescue IdolRoleContextPack::ContractError => e
      errors << "Director review dispatch provider is invalid: #{e.message}"
    end
    manifest = begin
      IdolGraphOutputManifestContract.verify!(root: root, pointer: dispatch["output_manifest"], dispatch: dispatch)
    rescue IdolGraphOutputManifestContract::ContractError => e
      errors << "Director review dispatch output manifest is invalid (#{e.code}): #{e.message}"
      nil
    end
    output_path = verify_artifact_pointer(root, review["review_output"], "#{review['phase']} Director review output", errors)
    if manifest
      review_binding = review["review_output"].to_h.slice("path", "sha256")
      manifest_bindings = manifest.fetch("outputs").map { |output| output.slice("path", "sha256") }
      errors << "Director review dispatch manifest does not exact-bind the review output" unless manifest_bindings.include?(review_binding)
    end
    if output_path
      output = load_document(output_path, errors, "#{review['phase']} Director review output")
      expected_output = {
        "review_id" => review["review_id"],
        "profile_id" => review["profile_id"],
        "phase" => review["phase"],
        "reviewer_role" => review["reviewer_role"],
        "reviewer_session_id" => review["reviewer_session_id"],
        "review_input_manifest" => review["review_input_manifest"],
        "review_input_digest_sha256" => review["review_input_digest_sha256"],
        "role_context_pack" => review["role_context_pack"],
        "reviewed_judgment_sha256s" => review["reviewed_judgment_sha256s"],
        "decision" => review["decision"]
      }
      errors << "Director review envelope differs from the returned review output bytes" unless canonical_value(output) == canonical_value(expected_output)
    end
  end

  def resolve_json_pointer(document, pointer, label, errors)
    current = document
    pointer.to_s.split("/").drop(1).each do |token|
      token = token.gsub("~1", "/").gsub("~0", "~")
      if current.is_a?(Hash) && current.key?(token)
        current = current[token]
      elsif current.is_a?(Array) && token.match?(/\A(?:0|[1-9][0-9]*)\z/) && token.to_i < current.length
        current = current[token.to_i]
      else
        errors << "#{label} JSON pointer does not resolve: #{pointer}"
        return nil
      end
    end
    current
  end

  def validate_provider_goal_attestation(root, dispatch, label, errors)
    event_path = verify_artifact_pointer(root, dispatch.dig("goal_evidence", "terminal_event"), "#{label} terminal event", errors)
    return unless event_path
    event = load_document(event_path, errors, "#{label} terminal event")
    return unless event
    attestation_path = verify_artifact_pointer(root, event["adapter_attestation"], "#{label} adapter attestation", errors)
    return unless attestation_path
    attestation = load_document(attestation_path, errors, "#{label} adapter attestation")
    return unless attestation
    raw_path = verify_artifact_pointer(root, attestation["raw_event"], "#{label} raw provider event", errors)
    raw = raw_path && load_document(raw_path, errors, "#{label} raw provider event")
    expected_raw = {
      "schema_version" => "idol-graph-provider-raw-goal-event.v1",
      "artifact_type" => "graph_provider_raw_goal_event",
      "provider" => dispatch.dig("provider_binding", "registered_provider"),
      "runtime_surface" => dispatch.dig("provider_binding", "runtime_surface"),
      "native_goal_id" => dispatch.dig("goal_evidence", "native_goal_id"),
      "goal_text_sha256" => dispatch.dig("goal_evidence", "goal_text_sha256"),
      "terminal_state" => dispatch.dig("goal_evidence", "goal_terminal_state"),
      "last_event" => dispatch.dig("goal_evidence", "goal_last_event")
    }
    errors << "#{label} raw provider event differs from the exact dispatch Goal" unless raw && canonical_value(raw) == canonical_value(expected_raw)
    expected_attestation = {
      "schema_version" => "idol-graph-provider-goal-adapter-attestation.v1",
      "artifact_type" => "graph_provider_goal_adapter_attestation",
      "assignment_id" => dispatch["dispatch_id"],
      "provider" => dispatch.dig("provider_binding", "registered_provider"),
      "runtime_surface" => dispatch.dig("provider_binding", "runtime_surface"),
      "native_goal_id" => dispatch.dig("goal_evidence", "native_goal_id"),
      "goal_text_sha256" => dispatch.dig("goal_evidence", "goal_text_sha256"),
      "raw_event" => attestation["raw_event"]
    }
    errors << "#{label} adapter attestation differs from the exact dispatch and raw event" unless canonical_value(attestation) == canonical_value(expected_attestation)
  end

  def probe_audio_duration(path)
    return nil unless path
    stdout, _stderr, status = Open3.capture3(
      "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type,duration,duration_ts,time_base", "-of", "json", path.to_s
    )
    return nil unless status.success?
    payload = JSON.parse(stdout)
    stream = Array(payload["streams"]).find { |candidate| candidate["codec_type"] == "audio" }
    return nil unless stream
    duration = stream["duration"].to_f
    if !duration.positive? && stream["duration_ts"] && stream["time_base"].to_s.match?(%r{\A[1-9][0-9]*/[1-9][0-9]*\z})
      numerator, denominator = stream["time_base"].split("/", 2).map(&:to_f)
      duration = stream["duration_ts"].to_f * numerator / denominator
    end
    duration.positive? ? duration : nil
  rescue JSON::ParserError, Errno::ENOENT
    nil
  end

  def validate_receipt_authorship(authorship, phase, errors)
    unless authorship.is_a?(Hash) && authorship.keys.map(&:to_s).sort == %w[author_id author_kind].sort
      errors << "#{phase} receipt authorship is invalid"
      return
    end
    kind = authorship["author_kind"].to_s
    if phase == "founder_approval"
      errors << "Founder approval receipt must be authored by founder" unless kind == "founder"
      errors << "Founder approval receipt author_id must be founder" unless authorship["author_id"].to_s == "founder"
    elsif !%w[assigned_human assigned_model].include?(kind)
      errors << "#{phase} receipt must be authored by an assigned human or model"
    end
    errors << "#{phase} receipt author_id is missing" if authorship["author_id"].to_s.empty?
  end

  def validate_receipt_authority(authority, phase, errors, full: false)
    expected_keys = full ? RECEIPT_AUTHORITY_KEYS + %w[execution_authority default_cutover_authority] : RECEIPT_AUTHORITY_KEYS
    unless authority.is_a?(Hash) && authority.keys.map(&:to_s).sort == expected_keys.sort
      errors << "#{phase} receipt authority is invalid"
      return
    end
    errors << "#{phase} receipt lets scripts author creative truth" unless authority["scripts_author_creative_truth"] == false
    errors << "#{phase} receipt permits automatic profile tuning" unless authority["automatic_profile_tuning"] == false
    errors << "#{phase} receipt permits automatic current-pointer change" unless authority["automatic_pointer_change"] == false
    if full
      errors << "#{phase} typed evidence grants execution authority" unless authority["execution_authority"] == false
      errors << "#{phase} typed evidence grants default-cutover authority" unless authority["default_cutover_authority"] == false
    end
  end

  def validate_authority(authority, errors)
    return errors << "profile promotion authority is missing" unless authority.is_a?(Hash)

    errors << "profile promotion lets scripts author creative truth" unless authority["scripts_author_creative_truth"] == false
    errors << "profile promotion permits automatic profile tuning" unless authority["automatic_profile_tuning"] == false
    errors << "profile promotion permits automatic current-pointer change" unless authority["automatic_pointer_change"] == false
    errors << "profile promotion must not grant execution authority" unless authority["execution_authority"] == false
    errors << "profile promotion must not grant default-cutover authority" unless authority["default_cutover_authority"] == false
  end

  def validate_release_pointer(root, pointer, profile_id, label, errors)
    unless pointer.is_a?(Hash) && pointer.keys.map(&:to_s).sort == RELEASE_POINTER_KEYS.sort
      errors << "#{label} is not an exact release pointer"
      return
    end
    path = verify_artifact_pointer(root, pointer, label, errors)
    return unless path

    release = load_document(path, errors, label)
    return unless release
    profile = release["profile"].to_h
    policy = release["policy"].to_h
    errors << "#{label} profile_id differs" unless profile["profile_id"].to_s == profile_id.to_s
    profile_hash = structured_sha256(profile)
    release_hash = structured_sha256("policy" => policy, "profile" => profile)
    errors << "#{label} profile_value_sha256 is stale" unless pointer["profile_value_sha256"].to_s == profile_hash && release["profile_value_sha256"].to_s == profile_hash
    errors << "#{label} release_value_sha256 is stale" unless pointer["release_value_sha256"].to_s == release_hash && release["release_value_sha256"].to_s == release_hash
    expected = "automation/graph-creative-judgment-profile-releases/#{profile_id}/#{release_hash}.yaml"
    errors << "#{label} path is not content-addressed" unless pointer["path"].to_s == expected
  end

  def validate_schema(root, promotion_path, errors)
    validate_document_schema(root, SCHEMA_RELATIVE, promotion_path, "profile promotion", errors)
  end

  def validate_document_schema(root, schema_relative, artifact_path, label, errors)
    schema = safe_file(root, schema_relative, "#{label} schema", errors)
    return unless schema
    python = IMPLEMENTATION_ROOT.join("scripts", "idol-video-python")
    validator = IMPLEMENTATION_ROOT.join("scripts", "validate_json_schema.py")
    stdout, stderr, status = Open3.capture3(python.to_s, validator.to_s, schema.to_s, artifact_path.to_s, chdir: root.to_s)
    return if status.success?

    errors << "#{label} failed JSON Schema validation: #{[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(' ').strip}"
  end

  def verify_artifact_pointer(root, pointer, label, errors)
    unless pointer.is_a?(Hash) && !pointer["path"].to_s.empty? && pointer["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
      errors << "#{label} pointer is invalid"
      return nil
    end
    path = safe_file(root, pointer["path"], label, errors)
    return nil unless path
    actual = Digest::SHA256.file(path).hexdigest
    errors << "#{label} SHA-256 is stale" unless actual == pointer["sha256"].to_s
    path
  end

  def safe_file(root, raw_path, label, errors)
    raw = Pathname.new(raw_path.to_s)
    if raw_path.to_s.empty? || raw.absolute?
      errors << "#{label} path must be repository-relative"
      return nil
    end
    candidate = root.join(raw).expand_path.cleanpath
    unless candidate.file?
      errors << "#{label} path is missing: #{raw_path}"
      return nil
    end
    begin
      real_root = root.realpath
      real = candidate.realpath
      relative = real.relative_path_from(real_root).to_s
      if relative == ".." || relative.start_with?("../")
        errors << "#{label} path escapes repository"
        return nil
      end
      real
    rescue ArgumentError, Errno::ENOENT
      errors << "#{label} path escapes repository"
      nil
    end
  end

  def validate_timestamp(value, phase, errors)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    errors << "#{phase} receipt issued_at must be ISO-8601"
  end

  def load_document(path, errors, label)
    value = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
    unless value.is_a?(Hash)
      errors << "#{label} must be an object"
      return nil
    end
    value
  rescue JSON::ParserError, Psych::Exception => e
    errors << "#{label} cannot be parsed: #{e.message}"
    nil
  end

  def canonical_release_pointer(pointer)
    return {} unless pointer.is_a?(Hash)

    RELEASE_POINTER_KEYS.to_h { |key| [key, pointer[key].to_s] }
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical_value(value[key]) }
    when Array
      value.map { |item| canonical_value(item) }
    else value
    end
  end

  def structured_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end
end
