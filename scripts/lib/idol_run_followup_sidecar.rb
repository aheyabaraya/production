# frozen_string_literal: true

require "date"
require "json"
require "open3"
require "pathname"
require "yaml"

# Operational consume path for run_followup. Validates the sidecar when present
# and requires it on material helper recurrence. Never auto-writes skills.
# v1 and v2 remain readable through frozen legacy schemas. v3 records
# pointer/digest-only Founder source bindings plus compact Role Context Pack
# projection rows; it never copies raw Founder wording into the sidecar.
module IdolRunFollowupSidecar
  V1_SCHEMA_RELATIVE = "schemas/harness-improvement-review-v1-legacy.schema.json"
  V2_SCHEMA_RELATIVE = "schemas/harness-improvement-review-v2-legacy.schema.json"
  V3_SCHEMA_RELATIVE = "schemas/harness-improvement-review.schema.json"
  PYTHON_RELATIVE = "scripts/idol-video-python"
  SCHEMA_VALIDATOR_RELATIVE = "scripts/validate_json_schema.py"
  RELATIVE_SIDECAR = "review/harness-improvement-review.yaml"
  V1_VERSION = "idol_harness_improvement_review.v1"
  V2_VERSION = "idol_harness_improvement_review.v2"
  V3_VERSION = "idol_harness_improvement_review.v3"
  AUTHORITY = "non_blocking_review_sidecar_no_stage_gate_creative_or_release_authority"
  FORBIDDEN_IMPORTS = %w[CONSTRAINTS.md auto_skill_save weekly_harness_swarm].freeze
  CREATIVE_SCORE_KEYS = %w[
    creative_score
    similarity_score
    beauty_score
    numeric_score
    weighted_total
  ].freeze
  WORKER_CLOSERS = %w[worker worker_self_claim self_claim model_authored].freeze
  RAW_FEEDBACK_KEYS = %w[
    verbatim
    verbatim_or_marker
    raw_feedback
    raw_commentary
    full_transcript
    session_transcript
  ].freeze
  FOUNDER_APPROVAL_JUDGMENT_CHANGE_KINDS = %w[
    minimum_floor
    critical_four
    not_applicable_rule
  ].freeze
  FORBIDDEN_JUDGMENT_EVOLUTION_KEYS = %w[
    total
    total_score
    average
    average_score
    weighted_total
    weighted_score
    aggregate_score
    auto_tune
    automatic_tuning
    auto_promote
    auto_current_pointer
    current_pointer_update
  ].freeze

  module_function

  def sidecar_path(root, run)
    Pathname.new(root).join(run.to_s, RELATIVE_SIDECAR)
  end

  def material?(document, receipts = [])
    return true if Array(receipts).any? { |row| row.is_a?(Hash) && row["director_disposition"].to_s == "hold" }

    summary = document["internal_delegation_summary"].is_a?(Hash) ? document["internal_delegation_summary"] : {}
    helpers_used = summary["provider_native_helpers_used"] == true
    submission = document["review_submission"].is_a?(Hash) ? document["review_submission"] : {}
    helpers_used && submission["submission_number"].to_i >= 2
  end

  def validate(root:, document:, receipts: [], require_on_material: true, required: false)
    errors = []
    run = document["run"].to_s
    path = sidecar_path(root, run)
    needed = required || (require_on_material && material?(document, receipts))
    if needed && !path.file?
      errors << "material recurrence requires run_followup sidecar #{RELATIVE_SIDECAR} under #{run}"
      return errors
    end
    return errors unless path.file?

    errors.concat(validate_sidecar_file(root: root, path: path, expected_run: run))
    errors
  end

  def validate_sidecar_file(root:, path:, expected_run: nil)
    errors = []
    path = Pathname.new(path)
    unless path.file?
      errors << "run_followup sidecar is missing: #{path}"
      return errors
    end

    sidecar = load_sidecar(path)
    unless sidecar.is_a?(Hash)
      errors << "run_followup sidecar must be a mapping"
      return errors
    end

    version = sidecar["schema_version"].to_s
    schema_relative = schema_relative_for(version)
    if schema_relative.nil?
      errors << "run_followup sidecar schema_version is unknown: #{version.inspect}"
      return errors
    end

    errors.concat(validate_against_schema(root: root, schema_relative: schema_relative, path: path))

    unless expected_run.nil? || sidecar["run"].to_s == expected_run.to_s
      errors << "run_followup sidecar run must equal dispatch run"
    end
    if sidecar["authority"].to_s != AUTHORITY
      errors << "run_followup sidecar must remain a non-blocking review sidecar"
    end
    if sidecar.dig("closeout", "release_gate_effect").to_s != "none"
      errors << "run_followup sidecar must not become an active gate"
    end
    FORBIDDEN_IMPORTS.each do |fragment|
      errors << "run_followup sidecar must not import #{fragment}" if sidecar.to_json.include?(fragment)
    end
    Array(sidecar["issues"]).each_with_index do |issue, index|
      followup = issue.is_a?(Hash) ? issue["harness_followup"] : nil
      next unless followup.is_a?(Hash)

      if followup["status"].to_s == "founder_approved" && followup["overfit_guard"].to_s.strip.empty?
        errors << "issues[#{index}] founder_approved run_followup requires overfit_guard"
      end
      Array(followup["target_surfaces"]).each do |surface|
        errors << "issues[#{index}] run_followup must not target #{surface}" if FORBIDDEN_IMPORTS.include?(surface.to_s)
      end
      errors.concat(validate_judgment_profile_evolution(followup["judgment_profile_evolution"], index: index))
    end
    if [V2_VERSION, V3_VERSION].include?(version)
      errors.concat(validate_founder_creative_closures(sidecar, version: version))
    end
    errors
  end

  def schema_relative_for(version)
    case version
    when V1_VERSION
      V1_SCHEMA_RELATIVE
    when V2_VERSION
      V2_SCHEMA_RELATIVE
    when V3_VERSION
      V3_SCHEMA_RELATIVE
    end
  end

  def load_sidecar(path)
    YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
  rescue Psych::SyntaxError
    nil
  end

  def validate_against_schema(root:, schema_relative:, path:)
    python = Pathname.new(root).join(PYTHON_RELATIVE)
    validator = Pathname.new(root).join(SCHEMA_VALIDATOR_RELATIVE)
    schema = Pathname.new(root).join(schema_relative)
    stdout, stderr, status = Open3.capture3(
      python.to_s,
      validator.to_s,
      schema.to_s,
      path.to_s,
      chdir: Pathname.new(root).to_s
    )
    return [] if status.success?

    ["run_followup sidecar schema failed: #{[stderr, stdout].join(" ").strip}"]
  end

  def validate_founder_creative_closures(sidecar, version:)
    errors = []
    closures = Array(sidecar["founder_creative_closures"])
    if version == V3_VERSION
      recurrence_keys = closures.each_with_object([]) do |closure, values|
        next unless closure.is_a?(Hash)

        key = closure["recurrence_key"].to_s
        values << key unless key.empty?
      end
      duplicate_keys = recurrence_keys.group_by(&:itself).select { |_key, rows| rows.length > 1 }.keys
      duplicate_keys.each do |key|
        errors << "v3 recurrence_key must be unique; merge repeated reason into the existing closure: #{key}"
      end
    end

    closures.each_with_index do |closure, index|
      unless closure.is_a?(Hash)
        errors << "founder_creative_closures[#{index}] must be a mapping"
        next
      end
      prefix = "founder_creative_closures[#{index}]"
      CREATIVE_SCORE_KEYS.each do |key|
        errors << "#{prefix} must not use #{key} as creative approval" if contains_key?(closure, key)
      end
      if version == V3_VERSION
        RAW_FEEDBACK_KEYS.each do |key|
          errors << "#{prefix} v3 must not copy raw Founder feedback key #{key}" if contains_key?(closure, key)
        end
      end
      if closure.dig("shadow_authority", "production_gate_effect").to_s != "none"
        errors << "#{prefix} must not become an active gate"
      end
      if closure.dig("shadow_authority", "auto_preference_lock") == true ||
         closure.dig("preference_candidate", "auto_lock") == true
        errors << "#{prefix} auto lock is rejected"
      end
      closed_by = closure.dig("corrected_result", "closed_by").to_s
      if WORKER_CLOSERS.include?(closed_by) || closure["worker_self_claim"] == true
        errors << "#{prefix} worker self-claim cannot close the correction"
      end
      interpretation = closure["director_interpretation"]
      if interpretation.is_a?(Hash)
        do_not_infer = interpretation.dig("change_contract", "do_not_infer")
        if !do_not_infer.is_a?(Array) || do_not_infer.empty?
          errors << "#{prefix} missing do_not_infer"
        end
      end
      studio = closure["preference_scope"].to_s == "studio_preference_candidate" ||
               closure.dig("preference_candidate", "promotion_state").to_s == "studio_preference_candidate"
      if studio && !closure.dig("preference_candidate", "founder_confirmation").is_a?(Hash)
        errors << "#{prefix} studio preference candidate requires Founder confirmation"
      end
      candidate = closure["preference_candidate"]
      if candidate.is_a?(Hash) &&
         candidate["promotion_state"].to_s != closure["preference_scope"].to_s
        errors << "#{prefix} preference scope must match promotion state"
      end
      if version == V3_VERSION
        projection_scope = closure.dig("context_projection", "applicability", "scope_mode").to_s
        expected_scope = case closure["preference_scope"].to_s
                         when "local_named_scope_only" then "exact_named_scope"
                         when "same_track_candidate" then "same_track_scope"
                         when "studio_preference_candidate" then "studio_confirmed_scope"
                         end
        if !expected_scope.to_s.empty? && projection_scope != expected_scope
          errors << "#{prefix} compact context scope must match preference scope"
        end
      end
      pointer = closure.dig("correction_binding", "json_pointer")
      if closure["correction_binding"].is_a?(Hash) && pointer != "/director_review/correction"
        errors << "#{prefix} must bind the existing Department Dispatch correction unit"
      end
    end
    errors
  end

  def validate_judgment_profile_evolution(proposal, index:)
    return [] if proposal.nil?
    return ["issues[#{index}] judgment_profile_evolution must be a mapping"] unless proposal.is_a?(Hash)

    errors = []
    prefix = "issues[#{index}] judgment_profile_evolution"
    FORBIDDEN_JUDGMENT_EVOLUTION_KEYS.each do |key|
      errors << "#{prefix} must not use aggregate scoring, automatic tuning, or automatic current-pointer change key #{key}" if contains_key?(proposal, key)
    end

    change_kind = proposal["change_kind"].to_s
    if FOUNDER_APPROVAL_JUDGMENT_CHANGE_KINDS.include?(change_kind) && proposal["founder_approval_required"] != true
      errors << "#{prefix} #{change_kind} requires founder_approval_required true"
    end

    authority = proposal["authority"]
    if authority.is_a?(Hash)
      unless authority["aggregate_score_usage"].to_s == "forbidden"
        errors << "#{prefix} aggregate score use is forbidden"
      end
      unless authority["automatic_criterion_tuning"] == false
        errors << "#{prefix} automatic criterion tuning is forbidden"
      end
      unless authority["current_pointer_effect"].to_s == "none"
        errors << "#{prefix} must not change the current profile pointer"
      end
      unless authority["required_sequence"].to_s == "proposal_then_shadow_then_pilot_then_separate_current_pointer_promotion"
        errors << "#{prefix} must preserve proposal -> shadow -> pilot -> separate current-pointer promotion"
      end
      unless authority["current_pointer_promotion_requires_founder_approval"] == true
        errors << "#{prefix} current-pointer promotion requires Founder approval"
      end
    end
    errors
  end

  def contains_key?(value, key)
    case value
    when Hash
      return true if value.key?(key) || value.key?(key.to_sym)

      value.values.any? { |item| contains_key?(item, key) }
    when Array
      value.any? { |item| contains_key?(item, key) }
    else
      false
    end
  end
end
