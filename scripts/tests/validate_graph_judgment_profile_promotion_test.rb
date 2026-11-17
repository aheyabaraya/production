# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

require_relative "../lib/idol_graph_judgment_profile_promotion_contract"
require_relative "../lib/idol_role_context_pack"

class ValidateGraphJudgmentProfilePromotionTest < Minitest::Test
  EVIDENCE_ROOT = "runs/test-album/test-title/PILOT_001/evidence"
  REAL_ROOT = Pathname.new(__dir__).join("..", "..").expand_path.cleanpath
  SCRIPT = REAL_ROOT.join("scripts", "validate_graph_judgment_profile_promotion.rb")
  PROFILE_ID = "pre_fp_storyline"

  def setup
    @root = Pathname.new(Dir.mktmpdir("graph-judgment-profile-promotion-"))
    install_graph_context_fixture_sources
    @old_release = install_release(YAML.safe_load(current_release_path.read, aliases: true))
    revised = YAML.safe_load(current_release_path.read, aliases: true)
    revised.fetch("profile")["evidence_surface"] = "future_profile_evidence_surface"
    @new_release = install_release(revised)
    @phase_evidence_pointers = install_phase_evidence
    @receipt_pointers = install_receipt_chain
    @promotion_path = install_promotion
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  def test_accepts_exact_lifecycle_and_founder_approval_chain
    errors = validate
    assert_equal [], errors
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      "--root", @root.to_s,
      @promotion_path.relative_path_from(@root).to_s,
      @root.join(@new_release.fetch("path")).to_s,
      chdir: REAL_ROOT.to_s
    )
    assert status.success?, "#{stdout}\n#{stderr}"
  end

  def test_rejects_missing_lifecycle_receipt
    mutate_promotion { |promotion| promotion.fetch("lifecycle_receipts").delete("pilot") }
    assert validation_errors.any? { |message| message.include?("proposal, shadow, pilot") }
  end

  def test_rejects_founder_approval_not_authored_by_founder
    mutate_receipt("founder_approval") { |receipt| receipt.fetch("authorship")["author_kind"] = "assigned_model" }
    refresh_promotion_receipt_pointer("founder_approval")
    assert validation_errors.any? { |message| message.include?("must be authored by founder") }
  end

  def test_rejects_broken_phase_predecessor_chain
    mutate_receipt("pilot") { |receipt| receipt["predecessor_receipt_sha256"] = "0" * 64 }
    refresh_promotion_receipt_pointer("pilot")
    assert validation_errors.any? { |message| message.include?("predecessor does not exact-bind") }
  end

  def test_rejects_release_pointer_change_without_matching_promotion
    mutate_promotion { |promotion| promotion["new_release"] = @old_release }
    assert validation_errors.any? { |message| message.include?("differs from the current profile release") }
  end

  def test_rejects_generic_untyped_phase_evidence
    path = @root.join(@phase_evidence_pointers.fetch("proposal").fetch("path"))
    path.write(YAML.dump("schema_version" => "generic.v1", "claim" => "structural evidence only"))
    refresh_receipt_evidence_pointer("proposal")
    assert validation_errors.any? { |message| message.include?("proposal typed evidence") }
  end

  def test_rejects_synthetic_or_non_founder_selected_pilot
    mutate_phase_evidence("pilot") do |evidence|
      evidence.fetch("payload")["synthetic"] = true
      evidence.fetch("payload")["founder_selected"] = false
    end
    refresh_receipt_evidence_pointer("pilot")
    assert validation_errors.any? { |message| message.include?("Founder-selected real-song run") }
  end

  def test_rejects_director_review_that_does_not_bind_compared_judgments
    evidence = load_phase_evidence("shadow")
    review_pointer = evidence.fetch("payload").fetch("director_review")
    review_path = @root.join(review_pointer.fetch("path"))
    review = YAML.safe_load(review_path.read, aliases: true)
    review["reviewed_judgment_sha256s"] = ["0" * 64]
    review_path.write(YAML.dump(review))
    review_pointer["sha256"] = Digest::SHA256.file(review_path).hexdigest
    evidence.fetch("payload")["director_review"] = review_pointer
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("does not exact-bind the compared judgments") }
  end

  def test_rejects_schema_invalid_skeletal_contextual_judgment
    evidence = load_phase_evidence("shadow")
    pointer = evidence.dig("payload", "comparisons", 0, "new_release_judgment")
    path = @root.join(pointer.fetch("path"))
    path.write(YAML.dump(
      "schema_version" => "idol_graph_contextual_judgment.v2",
      "artifact_type" => "graph_contextual_judgment",
      "profile_id" => PROFILE_ID,
      "checkpoint_id" => "p1_story_audience_lead",
      "execution_binding" => {"profile_value_sha256" => @new_release.fetch("profile_value_sha256")}
    ))
    pointer["sha256"] = Digest::SHA256.file(path).hexdigest
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("failed JSON Schema validation") }
  end

  def test_rejects_shadow_evidence_without_distinct_required_comparisons
    mutate_phase_evidence("shadow") { |evidence| evidence.fetch("payload").fetch("comparisons").pop }
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("misses representative coverage") }
  end

  def test_rejects_proposal_with_unknown_criterion_or_reused_control_evidence
    mutate_phase_evidence("proposal") do |evidence|
      payload = evidence.fetch("payload")
      payload["affected_criterion_ids"] = ["criterion_that_does_not_exist"]
      payload["negative_control_evidence"] = payload.fetch("observed_evidence")
    end
    refresh_receipt_evidence_pointer("proposal")
    errors = validation_errors
    assert errors.any? { |message| message.include?("outside the candidate release") }
    assert errors.any? { |message| message.include?("must be disjoint") }
  end

  def test_rejects_forged_candidate_role_context_projection
    evidence = load_phase_evidence("shadow")
    judgment_pointer = evidence.dig("payload", "comparisons", 0, "new_release_judgment")
    judgment_path = @root.join(judgment_pointer.fetch("path"))
    judgment = YAML.safe_load(judgment_path.read, aliases: true)
    pack_pointer = judgment.dig("execution_binding", "role_context_pack")
    pack_path = @root.join(pack_pointer.fetch("path"))
    pack = YAML.safe_load(pack_path.read, aliases: true)
    pack.fetch("projection")["source_set_sha256"] = "0" * 64
    pack_path.write(YAML.dump(pack))
    pack_pointer["sha256"] = Digest::SHA256.file(pack_path).hexdigest
    judgment_path.write(YAML.dump(judgment))
    judgment_pointer["sha256"] = Digest::SHA256.file(judgment_path).hexdigest
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("failed full candidate projection validation") }
  end

  def test_rejects_candidate_judgment_with_unbound_applicability_tag
    evidence = load_phase_evidence("shadow")
    judgment_pointer = evidence.dig("payload", "comparisons", 0, "new_release_judgment")
    judgment_path = @root.join(judgment_pointer.fetch("path"))
    judgment = YAML.safe_load(judgment_path.read, aliases: true)
    judgment["applicability_tags"] = ["no_performance_job"]
    judgment_path.write(YAML.dump(judgment))
    judgment_pointer["sha256"] = Digest::SHA256.file(judgment_path).hexdigest
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("failed full contextual judgment validation") }
  end

  def test_rejects_judgment_without_provider_authored_response_bytes
    evidence = load_phase_evidence("shadow")
    judgment_pointer = evidence.dig("payload", "comparisons", 0, "new_release_judgment")
    judgment_path = @root.join(judgment_pointer.fetch("path"))
    judgment = YAML.safe_load(judgment_path.read, aliases: true)
    judgment.fetch("execution_binding").delete("author_response")
    judgment_path.write(YAML.dump(judgment))
    judgment_pointer["sha256"] = Digest::SHA256.file(judgment_path).hexdigest
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("author response") }
  end

  def test_rejects_stale_provider_goal_adapter_attestation
    evidence = load_phase_evidence("shadow")
    judgment_pointer = evidence.dig("payload", "comparisons", 0, "new_release_judgment")
    judgment = YAML.safe_load(@root.join(judgment_pointer.fetch("path")).read, aliases: true)
    dispatch = YAML.safe_load(@root.join(judgment.dig("execution_binding", "dispatch", "path")).read, aliases: true)
    event = YAML.safe_load(@root.join(dispatch.dig("goal_evidence", "terminal_event", "path")).read, aliases: true)
    attestation_path = @root.join(event.dig("adapter_attestation", "path"))
    attestation = YAML.safe_load(attestation_path.read, aliases: true)
    attestation["native_goal_id"] = "GOAL_TAMPERED"
    attestation_path.write(YAML.dump(attestation))
    assert validation_errors.any? { |message| message.include?("adapter attestation") }
  end

  def test_rejects_unreturned_director_dispatch_without_output_manifest
    mutate_director_dispatch("shadow") do |dispatch|
      dispatch["lifecycle_state"] = "launched"
      dispatch["legal_next"] = %w[returned hold]
      dispatch["lifecycle_from"] = "prepared"
      dispatch["output_manifest"] = nil
    end
    errors = validation_errors
    assert errors.any? { |message| message.include?("immutable returned snapshot") }
    assert errors.any? { |message| message.include?("output manifest is invalid") }
  end

  def test_rejects_director_dispatch_from_the_wrong_lane
    mutate_director_dispatch("shadow") do |dispatch|
      dispatch["lane_id"] = "edit_director"
      dispatch["logical_role"] = "edit_director"
    end
    assert validation_errors.any? { |message| message.include?("lane, role, or cohort differs") }
  end

  def test_rejects_director_review_without_its_projected_context_pack
    evidence = load_phase_evidence("shadow")
    review_pointer = evidence.dig("payload", "director_review")
    review_path = @root.join(review_pointer.fetch("path"))
    review = YAML.safe_load(review_path.read, aliases: true)
    review.delete("role_context_pack")
    review_path.write(YAML.dump(review))
    review_pointer["sha256"] = Digest::SHA256.file(review_path).hexdigest
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("Role Context Pack") || message.include?("failed JSON Schema validation") }
  end

  def test_rejects_director_context_pack_without_exact_review_input_source
    evidence = load_phase_evidence("shadow")
    review_pointer = evidence.dig("payload", "director_review")
    review = YAML.safe_load(@root.join(review_pointer.fetch("path")).read, aliases: true)
    pack_pointer = review.fetch("role_context_pack")
    pack_path = @root.join(pack_pointer.fetch("path"))
    pack = YAML.safe_load(pack_path.read, aliases: true)
    pack["creative_source_pointers"] = []
    pack_path.write(YAML.dump(pack))
    review.fetch("role_context_pack")["sha256"] = Digest::SHA256.file(pack_path).hexdigest

    errors = []
    IdolGraphJudgmentProfilePromotionContract.validate_director_dispatch(
      @root,
      review.fetch("director_dispatch"),
      review,
      errors
    )
    assert errors.any? { |message| message.include?("must exact-project the review input manifest") }
  end

  def test_rejects_fake_audio_bytes_and_stale_song_identity
    @audio_path.binwrite("this is not audio")
    mutate_phase_evidence("pilot") do |evidence|
      evidence.fetch("payload").fetch("song_identity")["identity_sha256"] = "0" * 64
    end
    refresh_receipt_evidence_pointer("pilot")
    errors = validation_errors
    assert errors.any? { |message| message.include?("lacks a decodable audio stream") }
    assert errors.any? { |message| message.include?("song identity SHA-256 is stale") }
  end

  def test_audio_probe_uses_selected_audio_stream_not_longer_container_duration
    ffmpeg = `command -v ffmpeg`.strip
    skip "ffmpeg is unavailable" if ffmpeg.empty?
    media = @root.join("short-audio-long-container.mp4")
    _stdout, stderr, status = Open3.capture3(
      ffmpeg, "-y", "-loglevel", "error",
      "-f", "lavfi", "-i", "color=c=black:s=16x16:r=1:d=31",
      "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=8000:duration=1",
      "-c:v", "libx264", "-c:a", "aac", media.to_s
    )
    assert status.success?, stderr
    duration = IdolGraphJudgmentProfilePromotionContract.probe_audio_duration(media)
    assert duration && duration < 2.0, "expected the audio stream duration, got #{duration.inspect}"
  end

  def test_rejects_founder_approval_that_differs_from_hash_bound_input
    mutate_phase_evidence("founder_approval") do |evidence|
      evidence.fetch("payload")["founder_input_verbatim"] = "A different unbound instruction."
    end
    refresh_receipt_evidence_pointer("founder_approval")
    assert validation_errors.any? { |message| message.include?("differs from the bound Founder input") }
  end

  def test_rejects_director_self_review_of_profile_evolution_judgments
    evidence = load_phase_evidence("shadow")
    judgment_pointer = evidence.dig("payload", "comparisons", 0, "new_release_judgment")
    judgment = YAML.safe_load(@root.join(judgment_pointer.fetch("path")).read, aliases: true)
    review_pointer = evidence.dig("payload", "director_review")
    review_path = @root.join(review_pointer.fetch("path"))
    review = YAML.safe_load(review_path.read, aliases: true)
    review["reviewer_session_id"] = judgment.dig("execution_binding", "author_session_id")
    review_path.write(YAML.dump(review))
    review_pointer["sha256"] = Digest::SHA256.file(review_path).hexdigest
    write_phase_evidence("shadow", evidence)
    refresh_receipt_evidence_pointer("shadow")
    assert validation_errors.any? { |message| message.include?("must be independent") }
  end

  def test_bootstrap_seed_is_shadow_only_and_authorityless
    registry = YAML.safe_load(REAL_ROOT.join("automation/graph-creative-judgment-registry.yaml").read, aliases: true)
    current_releases = registry.fetch("current_profile_releases")
    assert_equal IdolGraphJudgmentProfilePromotionContract::BOOTSTRAP_SEED_RELEASES.keys.sort, current_releases.keys.sort

    current_releases.each do |profile_id, current|
      binding = current.fetch("promotion_binding")
      assert_equal [], IdolGraphJudgmentProfilePromotionContract.validate_binding(
        root: REAL_ROOT,
        binding: binding,
        current_release: current,
        profile_id: profile_id,
        registry_status: "shadow_not_default",
        validation_mode: "active_promotion"
      ), profile_id
      errors = IdolGraphJudgmentProfilePromotionContract.validate_binding(
        root: REAL_ROOT,
        binding: binding,
        current_release: current,
        profile_id: profile_id,
        registry_status: "default_active",
        validation_mode: "active_promotion"
      )
      assert errors.any? { |message| message.include?("valid only while") }, profile_id
      seed = YAML.safe_load(REAL_ROOT.join(binding.fetch("path")).read, aliases: true)
      assert_equal false, seed.dig("authority", "execution_authority"), profile_id
      assert_equal false, seed.dig("authority", "default_cutover_authority"), profile_id
    end
  end

  def test_bootstrap_seed_cannot_be_reused_for_a_new_release
    seed = YAML.safe_load(
      REAL_ROOT.join("automation/graph-creative-judgment-profile-promotions/bootstrap-shadow-seed/pre_fp_storyline.yaml").read,
      aliases: true
    )
    seed["new_release"] = @new_release
    path = @root.join("automation/graph-creative-judgment-profile-promotions/bootstrap-shadow-seed/pre_fp_storyline.yaml")
    path.dirname.mkpath
    path.write(YAML.dump(seed))
    errors = IdolGraphJudgmentProfilePromotionContract.validate_binding(
      root: @root,
      binding: {"path" => path.relative_path_from(@root).to_s, "sha256" => Digest::SHA256.file(path).hexdigest},
      current_release: @new_release,
      profile_id: PROFILE_ID,
      registry_status: "shadow_not_default",
      validation_mode: "active_promotion"
    )
    assert errors.any? { |message| message.include?("outside the immutable seed set") }
  end

  def test_bootstrap_seed_requires_the_exact_profile_specific_promotion_id
    seed_path = REAL_ROOT.join("automation/graph-creative-judgment-profile-promotions/bootstrap-shadow-seed/pre_fp_storyline.yaml")
    seed = YAML.safe_load(seed_path.read, aliases: true)
    seed["promotion_id"] = "BOOTSTRAP_SHADOW_SEED_REFERENCE_CANDIDATE"
    path = @root.join("automation/graph-creative-judgment-profile-promotions/bootstrap-shadow-seed/pre_fp_storyline.yaml")
    path.dirname.mkpath
    path.write(YAML.dump(seed))
    errors = IdolGraphJudgmentProfilePromotionContract.validate_binding(
      root: @root,
      binding: {"path" => path.relative_path_from(@root).to_s, "sha256" => Digest::SHA256.file(path).hexdigest},
      current_release: @old_release,
      profile_id: PROFILE_ID,
      registry_status: "shadow_not_default",
      validation_mode: "active_promotion"
    )
    assert errors.any? { |message| message.include?("immutable profile seed id") }
  end

  private

  def current_release_path
    registry = YAML.safe_load(REAL_ROOT.join("automation/graph-creative-judgment-registry.yaml").read, aliases: true)
    REAL_ROOT.join(registry.fetch("current_profile_releases").fetch(PROFILE_ID).fetch("path"))
  end

  def copy(relative)
    destination = @root.join(relative)
    destination.dirname.mkpath
    FileUtils.cp(REAL_ROOT.join(relative), destination)
  end

  def install_graph_context_fixture_sources
    routing_relative = "automation/graph-default-routing.yaml"
    profile_relative = "automation/graph-skill-load-profiles.yaml"
    projection_relative = "automation/graph-role-context-projection.yaml"
    [routing_relative, profile_relative, projection_relative].each { |relative| copy(relative) }
    copy("schemas/founder-intervention-receipt.schema.json")
    routing = YAML.safe_load(REAL_ROOT.join(routing_relative).read, aliases: true)
    Array(routing.dig("writer_boundary", "active_graph_surfaces")).each { |relative| copy(relative) }
    profiles = YAML.safe_load(REAL_ROOT.join(profile_relative).read, aliases: true)
    checkpoint_specs = {
      "planning_cdd_p1" => "p1_story_audience_lead",
      "overall_director" => "director_startup"
    }
    checkpoints = checkpoint_specs.map do |profile_id, checkpoint_id|
      profile = Array(profiles["profiles"]).find { |row| row["profile_id"] == profile_id }
      Array(profile.dig("phase_load", "checkpoints")).find { |row| row["checkpoint_id"] == checkpoint_id }
    end
    skill_ids = checkpoints.flat_map { |checkpoint| Array(checkpoint["required_skill_ids"]) }.uniq
    read_ids = checkpoints.flat_map { |checkpoint| Array(checkpoint["required_read_ids"]) }.uniq
    Array(profiles["skill_bindings"]).select { |row| skill_ids.include?(row["binding_id"]) }.each { |row| copy(row.fetch("path")) }
    Array(profiles["read_bindings"]).select { |row| read_ids.include?(row["binding_id"]) }.each { |row| copy(row.fetch("path")) }
    copy("automation/harness-provider-profile-registry.yaml")
    provider_registry = YAML.safe_load(REAL_ROOT.join("automation/harness-provider-profile-registry.yaml").read, aliases: true)
    provider_row = provider_registry.dig("logical_profiles", "frontier_director", "providers", "grok")
    copy(provider_row.fetch("source_path"))
  end

  def install_release(release)
    profile_hash = IdolGraphJudgmentProfilePromotionContract.structured_sha256(release.fetch("profile"))
    release_hash = IdolGraphJudgmentProfilePromotionContract.structured_sha256(
      "policy" => release.fetch("policy"),
      "profile" => release.fetch("profile")
    )
    release["profile_value_sha256"] = profile_hash
    release["release_value_sha256"] = release_hash
    relative = "automation/graph-creative-judgment-profile-releases/#{PROFILE_ID}/#{release_hash}.yaml"
    path = @root.join(relative)
    path.dirname.mkpath
    path.write(YAML.dump(release))
    {
      "path" => relative,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "release_value_sha256" => release_hash,
      "profile_value_sha256" => profile_hash
    }
  end

  def install_phase_evidence
    coverage_cases = %w[expected_pass correction hard_gate counterexample_outside_scope]
    comparisons = coverage_cases.map do |coverage_case|
      comparison = {
        "case_id" => "CASE_#{coverage_case.upcase}",
        "coverage_case" => coverage_case,
        "old_release_judgment" => install_judgment("shadow-old-#{coverage_case}", @old_release, coverage_case, parity_key: coverage_case),
        "new_release_judgment" => install_judgment("shadow-new-#{coverage_case}", @new_release, coverage_case, parity_key: coverage_case)
      }
      if coverage_case == "counterexample_outside_scope"
        comparison["outside_scope_evidence"] = install_supporting_artifact("counterexample-outside-scope-assessment")
        comparison["outside_scope_reason"] = "This valid route lies outside the proposed criterion's declared causal-storyline scope."
      end
      comparison
    end
    shadow_judgments = comparisons.flat_map { |comparison| [comparison.fetch("old_release_judgment"), comparison.fetch("new_release_judgment")] }
    pilot_judgments = [install_judgment("pilot-new", @new_release, "expected_pass", parity_key: "pilot")]
    shadow_inputs = {
      "evaluation_id" => "SHADOW_EVAL_001",
      "checkpoint_ids" => %w[p1_story_audience_lead],
      "comparisons" => comparisons,
      "regressions_found" => 0,
      "result" => "passed_shadow"
    }
    shadow_review = install_director_review("shadow", shadow_judgments, phase_inputs: shadow_inputs)
    @audio_path = @root.join("runs/test-album/test-title/PILOT_001/source/selected-audio.wav")
    @audio_path.dirname.mkpath
    @audio_path.binwrite(wav_fixture_bytes(31))
    selected_audio = {
      "path" => @audio_path.relative_path_from(@root).to_s,
      "sha256" => Digest::SHA256.file(@audio_path).hexdigest
    }
    song_identity_sha256 = IdolGraphJudgmentProfilePromotionContract.structured_sha256("artist" => "TEST ARTIST", "title" => "TEST TITLE")
    selected_audio_duration_seconds = 31.0
    song_identity_artifact = install_song_identity_artifact(selected_audio, song_identity_sha256)
    pilot_founder_source = install_founder_source(
      "pilot-selection",
      "Use this exact song, run, selected audio, and candidate profile release for the real-song profile pilot.",
      classification: "explicit_lock",
      bindings: [song_identity_artifact, selected_audio, @new_release]
    )
    pilot_selection = install_pilot_selection(selected_audio, selected_audio_duration_seconds, song_identity_sha256, song_identity_artifact, pilot_founder_source)
    pilot_inputs = {
      "pilot_id" => "REAL_SONG_PILOT_001",
      "run" => "runs/test-album/test-title/PILOT_001",
      "song_identity" => {
        "artist" => "TEST ARTIST",
        "title" => "TEST TITLE",
        "identity_sha256" => song_identity_sha256
      },
      "song_identity_artifact" => song_identity_artifact,
      "selected_audio" => selected_audio,
      "selected_audio_duration_seconds" => selected_audio_duration_seconds,
      "founder_selection_receipt" => pilot_selection,
      "checkpoint_ids" => %w[p1_story_audience_lead],
      "new_release_judgments" => pilot_judgments,
      "founder_selected" => true,
      "real_song" => true,
      "synthetic" => false,
      "result" => "passed_pilot"
    }
    pilot_review = install_director_review("pilot", pilot_judgments, phase_inputs: pilot_inputs)
    founder_approval_text = "Approve this exact profile release for the current pointer."
    @founder_approval_source = install_founder_source(
      "profile-approval",
      founder_approval_text,
      classification: "approval",
      bindings: [@new_release]
    )
    proposal_observed = install_supporting_artifact("proposal-observed-gap")
    proposal_counterexample = install_supporting_artifact("proposal-counterexample")
    proposal_negative_control = install_supporting_artifact("proposal-negative-control")

    payloads = {
      "proposal" => {
        "change_reason" => "Repeated false negative at the storyline checkpoint",
        "observed_gap_ids" => %w[GAP_001],
        "affected_criterion_ids" => %w[whole_film_opening_to_ending_causality],
        "checkpoint_ids" => %w[p1_story_audience_lead],
        "observed_evidence" => [proposal_observed],
        "counterexample_evidence" => [proposal_counterexample],
        "negative_control_evidence" => [proposal_negative_control],
        "expected_improvement" => "Separate causal continuity from repeated message exposition",
        "overfit_guard" => "Reject title-specific names, scenes, and camera solutions"
      },
      "shadow" => shadow_inputs.merge("director_review" => shadow_review),
      "pilot" => pilot_inputs.merge("director_review" => pilot_review),
      "founder_approval" => {
        "approval_id" => "FOUNDER_PROFILE_APPROVAL_001",
        "source_locator" => "codex-task:founder-message:profile-promotion",
        "founder_input_verbatim" => founder_approval_text,
        "founder_source" => @founder_approval_source,
        "explicit_lock" => true,
        "decision" => "approved_current_pointer_promotion",
        "approved_profile_value_sha256" => @new_release.fetch("profile_value_sha256")
      }
    }
    classes = IdolGraphJudgmentProfilePromotionContract::EVIDENCE_CLASSES
    IdolGraphJudgmentProfilePromotionContract::PHASES.to_h do |phase|
      evidence = {
        "schema_version" => IdolGraphJudgmentProfilePromotionContract::EVOLUTION_EVIDENCE_SCHEMA_VERSION,
        "artifact_type" => IdolGraphJudgmentProfilePromotionContract::EVOLUTION_EVIDENCE_ARTIFACT_TYPE,
        "evidence_id" => "EVIDENCE_#{phase.upcase}",
        "profile_id" => PROFILE_ID,
        "phase" => phase,
        "evidence_class" => classes.fetch(phase),
        "old_release" => @old_release,
        "new_release" => @new_release,
        "payload" => payloads.fetch(phase),
        "authority" => {
          "scripts_author_creative_truth" => false,
          "automatic_profile_tuning" => false,
          "automatic_pointer_change" => false,
          "execution_authority" => false,
          "default_cutover_authority" => false
        },
        "issued_at" => "2026-09-03T00:00:00Z"
      }
      relative = "#{EVIDENCE_ROOT}/#{phase}-typed-evidence.yaml"
      path = @root.join(relative)
      path.dirname.mkpath
      path.write(YAML.dump(evidence))
      [phase, {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}]
    end
  end

  def install_judgment(name, release_pointer, coverage_case, parity_key:)
    release = YAML.safe_load(@root.join(release_pointer.fetch("path")).read, aliases: true)
    profile = release.fetch("profile")
    policy = release.fetch("policy")
    assignment_id = "assignment-shadow-#{parity_key}"
    support = install_supporting_artifact(parity_key)
    results = profile.fetch("criteria").to_h { |criterion| [criterion.fetch("criterion_id"), criterion.fetch("minimum")] }
    hard_gates = []
    decision = case coverage_case
               when "correction"
                 results[profile.fetch("criteria").first.fetch("criterion_id")] = 2
                 "combine_or_correct"
               when "hard_gate"
                 hard_gates << {
                   "finding_id" => "stale_source_lock",
                   "evidence_locator" => [support.slice("path", "sha256")],
                   "consequence" => "The source cannot support promotion.",
                   "required_action" => "Refresh the smallest affected source binding."
                 }
                 "hold"
               when "counterexample_outside_scope"
                 "eligible_for_director_review"
               else
                 "eligible_for_director_review"
               end
    judgment = {
      "schema_version" => "idol_graph_contextual_judgment.v2",
      "artifact_type" => "graph_contextual_judgment",
      "profile_id" => PROFILE_ID,
      "checkpoint_id" => profile.fetch("checkpoints").first,
      "stage_id" => profile.fetch("stages").first,
      "scope_id" => assignment_id,
      "authoring_owner" => "human_or_assigned_model",
      "reviewer_role" => profile.fetch("owner_roles").first,
      "performance_mode" => "none",
      "applicability_tags" => [],
      "applicability_evidence" => [],
      "source_artifacts" => [support],
      "criteria" => profile.fetch("criteria").map do |criterion|
        {
          "criterion_id" => criterion.fetch("criterion_id"),
          "result" => results.fetch(criterion.fetch("criterion_id")),
          "evidence_locator" => [support.slice("path", "sha256")],
          "observable_claim" => "A named observable condition is present in the bound evidence.",
          "screen_consequence" => "The condition changes what the Director can accept on screen.",
          "preserve" => "Preserve the evidence-backed intent.",
          "change" => "Change only the named deficient condition.",
          "do_not_infer" => "Do not infer unobserved creative approval.",
          "correction_action" => "Return the named condition to its smallest owner when needed.",
          "acceptance_evidence" => "A new exact output binding must show the corrected condition."
        }
      end,
      "hard_gate_findings" => hard_gates,
      "decision" => decision,
      "next_edge" => policy.fetch("decision_edges").fetch(decision),
      "target_message_treatment" => profile.fetch("target_message_treatment"),
      "aggregate_score_present" => false,
      "automatic_creative_pass" => false,
      "status" => policy.fetch("decision_status").fetch(decision)
    }
    judgment["execution_binding"] = install_judgment_transport(
      name: name,
      parity_key: parity_key,
      assignment_id: assignment_id,
      release_pointer: release_pointer,
      profile: profile,
      source: support,
      judgment_value: judgment
    )
    relative = "#{EVIDENCE_ROOT}/judgments/#{name}.yaml"
    path = @root.join(relative)
    path.dirname.mkpath
    path.write(YAML.dump(judgment))
    {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def install_supporting_artifact(name)
    relative = "#{EVIDENCE_ROOT}/support/#{name}.yaml"
    path = @root.join(relative)
    return {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest} if path.file?
    path.dirname.mkpath
    path.write(YAML.dump("observed" => true, "name" => name))
    {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def install_judgment_transport(name:, parity_key:, assignment_id:, release_pointer:, profile:, source:, judgment_value:)
    input_digest = Digest::SHA256.hexdigest("same-input-#{parity_key}")
    author_role = profile.fetch("owner_roles").first
    author_session_id = "author-session-#{name}"
    goal_id = "GOAL_#{name.upcase.tr('-', '_')}"
    goal_text = "Author the exact #{name} profile-evolution judgment."
    goal_text_sha = Digest::SHA256.hexdigest(goal_text)
    raw_event_relative = "#{EVIDENCE_ROOT}/transport/#{name}-raw-goal-event.yaml"
    raw_event_path = @root.join(raw_event_relative)
    raw_event_path.dirname.mkpath
    raw_event_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-raw-goal-event.v1",
      "artifact_type" => "graph_provider_raw_goal_event",
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "native_goal_id" => goal_id,
      "goal_text_sha256" => goal_text_sha,
      "terminal_state" => "complete",
      "last_event" => "goal_completed"
    ))
    raw_event_pointer = pointer(raw_event_relative)
    attestation_relative = "#{EVIDENCE_ROOT}/transport/#{name}-goal-attestation.yaml"
    attestation_path = @root.join(attestation_relative)
    attestation_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-goal-adapter-attestation.v1",
      "artifact_type" => "graph_provider_goal_adapter_attestation",
      "assignment_id" => assignment_id,
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "native_goal_id" => goal_id,
      "goal_text_sha256" => goal_text_sha,
      "raw_event" => raw_event_pointer
    ))
    attestation_pointer = pointer(attestation_relative)
    event_relative = "#{EVIDENCE_ROOT}/transport/#{name}-goal-event.yaml"
    event_path = @root.join(event_relative)
    event_path.dirname.mkpath
    event_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-goal-terminal-event.v1",
      "artifact_type" => "graph_provider_goal_terminal_event",
      "evidence_class" => "provider_native_terminal_event",
      "provider" => "grok",
      "native_goal_id" => goal_id,
      "goal_text" => goal_text,
      "goal_text_sha256" => goal_text_sha,
      "goal_semantics" => "grok_goal_completed_admission",
      "terminal_state" => "complete",
      "last_event" => "goal_completed",
      "adapter_attestation" => attestation_pointer
    ))
    event_pointer = pointer(event_relative)

    author_response_relative = "#{EVIDENCE_ROOT}/transport/#{name}-author-response.yaml"
    author_response_path = @root.join(author_response_relative)
    author_response_path.write(YAML.dump(
      "schema_version" => "idol-graph-contextual-judgment-author-response.v1",
      "artifact_type" => "graph_contextual_judgment_author_response",
      "provider" => "grok",
      "native_goal_id" => goal_id,
      "author_role" => author_role,
      "author_session_id" => author_session_id,
      "judgment_value_sha256" => IdolGraphJudgmentProfilePromotionContract.structured_sha256(judgment_value),
      "response_payload" => judgment_value
    ))
    author_response_pointer = pointer(author_response_relative)

    manifest_relative = "#{EVIDENCE_ROOT}/transport/#{name}-output-manifest.yaml"
    manifest_path = @root.join(manifest_relative)
    manifest_path.write(YAML.dump(
      "schema_version" => "idol-graph-output-manifest.v1",
      "artifact_type" => "graph_dispatch_output_manifest",
      "dispatch_id" => assignment_id,
      "assigned_owner" => author_role,
      "input_digest_sha256" => input_digest,
      "output_kind" => "profile_evolution_evaluated_source",
      "outputs" => [source, author_response_pointer]
    ))
    manifest_pointer = pointer(manifest_relative)
    resolved_provider, provider_holds = IdolRoleContextPack.resolve_provider(
      root: @root,
      role: author_role,
      provider: "grok",
      runtime_surface: "grok_build_cli_acp",
      logical_profile_alias: "frontier_director"
    )
    raise "fixture provider did not resolve: #{provider_holds.join(', ')}" unless provider_holds.empty?
    provider = {
      "registered_provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "logical_profile_alias" => "frontier_director",
      "execution_profile_id" => resolved_provider.fetch("provider_profile_id"),
      "resolved_provider_model" => resolved_provider.fetch("exact_model"),
      "reasoning_effort" => resolved_provider.fetch("reasoning_effort"),
      "provider_capability_snapshot_sha256" => resolved_provider.fetch("registry_sha256"),
      "fallback_allowed" => false,
      "silent_substitution_allowed" => false
    }
    reviewer = {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"}
    recipient = {"owner" => "overall_director", "role" => "overall_director", "return_route" => "profile_evolution_shadow_review"}
    dispatch = {
      "schema_version" => "idol-graph-department-dispatch.v1",
      "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => assignment_id,
      "run" => "runs/test-album/test-title/PILOT_001",
      "lane_id" => "planning_p1",
      "section_cohort_id" => nil,
      "section_ids" => [],
      "logical_role" => "planning_cdd",
      "assigned_owner" => author_role,
      "output_writer" => {"owner" => author_role, "role" => "planning_cdd", "session_id" => author_session_id},
      "reviewer" => reviewer,
      "return_recipient" => recipient,
      "provider_binding" => provider,
      "goal_evidence" => {
        "native_goal_id" => goal_id,
        "goal_text_sha256" => goal_text_sha,
        "goal_semantics" => "grok_goal_completed_admission",
        "goal_terminal_state" => "complete",
        "goal_last_event" => "goal_completed",
        "goal_terminal_event_sha256" => event_pointer.fetch("sha256"),
        "terminal_event" => event_pointer
      },
      "input_digest_sha256" => input_digest,
      "bounded_output" => {
        "output_kind" => "profile_evolution_evaluated_source",
        "expected_paths" => [source.fetch("path"), author_response_pointer.fetch("path")],
        "maximum_artifact_count" => 2
      },
      "output_manifest" => manifest_pointer,
      "judgment_profile_id" => PROFILE_ID,
      "stop_conditions" => ["stale_profile_evolution_source"],
      "lifecycle_state" => "returned",
      "legal_next" => %w[reviewed hold],
      "lifecycle_from" => "launched",
      "assignment_pass" => false
    }
    launch_dispatch = Marshal.load(Marshal.dump(dispatch))
    launch_dispatch["output_manifest"] = nil
    launch_dispatch["lifecycle_state"] = "launched"
    launch_dispatch["legal_next"] = %w[returned hold]
    launch_dispatch["lifecycle_from"] = "prepared"
    launch_relative = "#{EVIDENCE_ROOT}/transport/#{name}-launch-dispatch.yaml"
    launch_path = @root.join(launch_relative)
    launch_path.write(YAML.dump(launch_dispatch))
    launch_pointer = pointer(launch_relative)
    dispatch_relative = "#{EVIDENCE_ROOT}/transport/#{name}-dispatch.yaml"
    dispatch_path = @root.join(dispatch_relative)
    dispatch_path.write(YAML.dump(dispatch))
    dispatch_pointer = pointer(dispatch_relative)
    pack_pointer = install_candidate_role_context_pack(
      name: name,
      assignment_id: assignment_id,
      author_role: author_role,
      author_session_id: author_session_id,
      release_pointer: release_pointer,
      profile: profile,
      source: source,
      dispatch: launch_dispatch,
      dispatch_pointer: launch_pointer,
      provider: provider,
      reviewer: reviewer,
      recipient: recipient
    )
    {
      "assignment_id" => assignment_id,
      "author_role" => author_role,
      "author_session_id" => author_session_id,
      "dispatch" => dispatch_pointer,
      "goal_id" => goal_id,
      "goal_terminal_event_sha256" => event_pointer.fetch("sha256"),
      "role_context_pack" => pack_pointer,
      "profile_release" => release_pointer.slice("path", "sha256"),
      "profile_value_sha256" => release_pointer.fetch("profile_value_sha256"),
      "input_digest_sha256" => input_digest,
      "output_manifest" => manifest_pointer,
      "author_response" => author_response_pointer
    }
  end

  def install_candidate_role_context_pack(name:, assignment_id:, author_role:, author_session_id:, release_pointer:, profile:, source:, dispatch:, dispatch_pointer:, provider:, reviewer:, recipient:)
    switch_receipt = {
      "receipt_id" => "PROFILE_EVOLUTION_SHADOW_SWITCH",
      "founder_authority" => "founder",
      "graph_revision" => "idol-graph-skill-load-profiles.v1",
      "switch_boundary" => "new_runs_only_after_verified_receipt",
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(@root),
      "verified_at" => "2026-09-03T00:00:00Z"
    }
    pack = IdolRoleContextPack.build(
      root: @root,
      run_root: dispatch.fetch("run"),
      assignment_id: assignment_id,
      role: author_role,
      profile_id: "planning_cdd_p1",
      checkpoint_id: "p1_story_audience_lead",
      stage_id: "creative_route_discovery",
      section_ids: [],
      source_envelope: {"kind" => "department_dispatch"}.merge(dispatch_pointer),
      current_state: "launched",
      scope: {"assignment_id" => assignment_id},
      non_scope: ["creative_pass"],
      authority: {"assigned_owner" => author_role, "promotion_owner" => "overall_director"},
      founder_epoch: "profile-evolution-shadow",
      founder_locks: [],
      creative_sources: [],
      output_contract: {"kind" => "graph_contextual_judgment"},
      hold_conditions: ["stale_profile_evolution_source"],
      return_recipient: recipient,
      provider: "grok",
      runtime_surface: provider.fetch("runtime_surface"),
      writer: IdolRoleContextPack::GRAPH_WRITER,
      run_class: "new_run",
      switch_receipt: switch_receipt
    )
    contract = pack.fetch("creative_judgment_contract")
    contract["profile_release"] = release_pointer.slice("path", "sha256")
    contract["profile_value_sha256"] = release_pointer.fetch("profile_value_sha256")
    contract["profile"] = profile
    source_set = {
      "projection_registry" => {"path" => pack.dig("projection", "registry_path"), "sha256" => pack.dig("projection", "registry_sha256")},
      "profile_registry" => {"path" => pack.dig("projection", "profile_registry_path"), "sha256" => pack.dig("projection", "profile_registry_sha256")},
      "source_envelope" => pack.fetch("source_envelope"),
      "instructions" => pack.fetch("instruction_slices").map { |row| row.slice("binding_id", "path", "whole_file_sha256", "locator", "fragment_sha256") },
      "creative_sources" => pack.fetch("creative_source_pointers"),
      "founder_quality_context" => nil,
      "provider" => pack.fetch("provider_binding").slice("provider", "provider_profile_id", "provider_source_sha256"),
      "creative_judgment_contract" => contract,
      "graph_dispatch_identity" => pack.fetch("graph_dispatch_identity"),
      "activation_binding" => pack.fetch("activation_binding")
    }
    pack["projection"]["source_set_sha256"] = IdolRoleContextPack.structured_sha256(source_set)
    pack["projection"]["pack_digest"] = IdolRoleContextPack.structured_sha256(pack.reject { |key, _| key == "projection" }.merge(
      "projection" => pack.fetch("projection").reject { |key, _| key == "pack_digest" }
    ))
    relative = "#{EVIDENCE_ROOT}/transport/#{name}-role-context-pack.yaml"
    path = @root.join(relative)
    path.write(YAML.dump(pack))
    pointer(relative)
  end

  def install_founder_source(name, verbatim, classification:, bindings:)
    run = "runs/test-album/test-title/PILOT_001"
    token = name.upcase.tr("-", "_")
    relative = "#{run}/review/founder-interventions/FI_#{token}.yaml"
    path = @root.join(relative)
    path.dirname.mkpath
    document = {
      "schema_version" => "idol-founder-intervention-receipt.v2",
      "artifact_type" => "founder_intervention_receipt",
      "intervention_id" => "FI_#{token}",
      "run" => run,
      "recorded_at" => "2026-09-03T00:00:00Z",
      "source" => {
        "surface" => "codex_task",
        "locator" => "task:profile-evolution:#{name}",
        "founder_input_verbatim" => verbatim
      },
      "authority" => {
        "classification" => classification,
        "explicit_lock" => true,
        "scope_statement" => "Exact profile evolution #{name} scope only"
      },
      "intervention_mode" => "advisory_feedback",
      "routing" => {
        "owning_stage_id" => "creative_route_discovery",
        "required_owner_skill" => "idol-orchestrator",
        "affected_section_ids" => ["ALL"],
        "affected_artifacts" => bindings.map do |binding|
          binding.slice("path", "sha256").merge("role" => "Founder-selected profile evolution evidence")
        end,
        "earliest_reauthor_stage_id" => "creative_route_discovery",
        "downstream_invalidation_targets" => [],
        "integration_order" => "revise_owning_upstream_section_then_reproject_and_revalidate_only_affected_downstream"
      },
      "change_contract" => {
        "preserve" => ["Existing immutable releases and historical judgments"],
        "change" => ["Only the exact named profile evolution decision"],
        "do_not_infer" => ["No execution or Graph default-switch authority"]
      },
      "status" => "captured",
      "integration_receipt" => nil
    }
    path.write(YAML.dump(document))
    {
      "path" => relative,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "json_pointer" => "/source/founder_input_verbatim",
      "value_sha256" => IdolGraphJudgmentProfilePromotionContract.structured_sha256(verbatim)
    }
  end

  def install_song_identity_artifact(selected_audio, song_identity_sha256)
    artifact = {
      "schema_version" => "idol-graph-selected-song-identity.v1",
      "artifact_type" => "graph_selected_song_identity",
      "run" => "runs/test-album/test-title/PILOT_001",
      "artist" => "TEST ARTIST",
      "title" => "TEST TITLE",
      "identity_sha256" => song_identity_sha256,
      "selected_audio" => selected_audio
    }
    relative = "#{EVIDENCE_ROOT}/selected-song-identity.yaml"
    path = @root.join(relative)
    path.write(YAML.dump(artifact))
    pointer(relative)
  end

  def install_pilot_selection(selected_audio, selected_audio_duration_seconds, song_identity_sha256, song_identity_artifact, founder_source)
    selection = {
      "schema_version" => IdolGraphJudgmentProfilePromotionContract::EVOLUTION_EVIDENCE_SCHEMA_VERSION,
      "artifact_type" => IdolGraphJudgmentProfilePromotionContract::PILOT_SELECTION_ARTIFACT_TYPE,
      "selection_id" => "FOUNDER_REAL_SONG_PILOT_SELECTION_001",
      "profile_id" => PROFILE_ID,
      "new_release" => @new_release,
      "run" => "runs/test-album/test-title/PILOT_001",
      "song_identity_sha256" => song_identity_sha256,
      "song_identity_artifact" => song_identity_artifact,
      "selected_audio" => selected_audio,
      "selected_audio_duration_seconds" => selected_audio_duration_seconds,
      "founder_source" => founder_source,
      "founder_selected" => true,
      "authority" => {
        "profile_pointer_change_authorized" => false,
        "execution_authorized" => false,
        "default_cutover_authorized" => false
      },
      "issued_at" => "2026-09-03T00:00:00Z"
    }
    relative = "#{EVIDENCE_ROOT}/pilot-founder-selection.yaml"
    path = @root.join(relative)
    path.write(YAML.dump(selection))
    {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def wav_fixture_bytes(duration_seconds)
    data = "\x00\x01".b * (8_000 * duration_seconds)
    riff_size = 36 + data.bytesize
    "RIFF".b + [riff_size].pack("V") + "WAVEfmt ".b + [16, 1, 1, 8_000, 16_000, 2, 16].pack("VvvVVvv") + "data".b + [data.bytesize].pack("V") + data
  end

  def install_director_review(phase, judgment_pointers, phase_inputs:)
    reviewer_session_id = "overall_director_session_#{phase}"
    review_input = {
      "schema_version" => "idol-graph-profile-evolution-review-input.v1",
      "artifact_type" => "graph_profile_evolution_review_input",
      "profile_id" => PROFILE_ID,
      "phase" => phase,
      "old_release" => @old_release,
      "new_release" => @new_release,
      "phase_payload" => phase_inputs,
      "reviewed_judgment_sha256s" => judgment_pointers.map { |pointer| pointer.fetch("sha256") }
    }
    input_relative = "#{EVIDENCE_ROOT}/#{phase}-director-review-input.yaml"
    input_path = @root.join(input_relative)
    input_path.dirname.mkpath
    input_path.write(YAML.dump(review_input))
    review_input_pointer = pointer(input_relative)
    review_input_digest = IdolGraphJudgmentProfilePromotionContract.structured_sha256(review_input)
    review_output = {
      "review_id" => "DIRECTOR_REVIEW_#{phase.upcase}",
      "profile_id" => PROFILE_ID,
      "phase" => phase,
      "reviewer_role" => "overall_director",
      "reviewer_session_id" => reviewer_session_id,
      "review_input_manifest" => review_input_pointer,
      "review_input_digest_sha256" => review_input_digest,
      "reviewed_judgment_sha256s" => judgment_pointers.map { |pointer| pointer.fetch("sha256") },
      "decision" => "passed_for_profile_evolution"
    }
    output_relative = "#{EVIDENCE_ROOT}/#{phase}-director-review-output.yaml"
    output_path = @root.join(output_relative)
    output_path.dirname.mkpath
    output_path.write(YAML.dump(review_output))
    review_output_pointer = pointer(output_relative)
    director_dispatch = install_director_dispatch(phase, reviewer_session_id, review_input_digest, review_output_pointer)
    role_context_pack = install_director_review_context_pack(phase, director_dispatch, review_input_pointer)
    review_output["role_context_pack"] = role_context_pack
    output_path.write(YAML.dump(review_output))
    review_output_pointer["sha256"] = Digest::SHA256.file(output_path).hexdigest
    dispatch_path = @root.join(director_dispatch.fetch("path"))
    dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
    manifest_path = @root.join(dispatch.dig("output_manifest", "path"))
    manifest = YAML.safe_load(manifest_path.read, aliases: true)
    manifest["outputs"] = [review_output_pointer]
    manifest_path.write(YAML.dump(manifest))
    dispatch.fetch("output_manifest")["sha256"] = Digest::SHA256.file(manifest_path).hexdigest
    dispatch_path.write(YAML.dump(dispatch))
    director_dispatch["sha256"] = Digest::SHA256.file(dispatch_path).hexdigest
    review = {
      "schema_version" => IdolGraphJudgmentProfilePromotionContract::DIRECTOR_REVIEW_SCHEMA_VERSION,
      "artifact_type" => IdolGraphJudgmentProfilePromotionContract::DIRECTOR_REVIEW_ARTIFACT_TYPE,
      "review_id" => "DIRECTOR_REVIEW_#{phase.upcase}",
      "profile_id" => PROFILE_ID,
      "phase" => phase,
      "old_release" => @old_release,
      "new_release" => @new_release,
      "reviewer_role" => "overall_director",
      "reviewer_session_id" => reviewer_session_id,
      "review_input_manifest" => review_input_pointer,
      "review_input_digest_sha256" => review_input_digest,
      "director_dispatch" => director_dispatch,
      "role_context_pack" => role_context_pack,
      "review_output" => review_output_pointer,
      "reviewed_judgment_sha256s" => review_output.fetch("reviewed_judgment_sha256s"),
      "decision" => "passed_for_profile_evolution",
      "authority" => {
        "creative_pass_created" => false,
        "pointer_change_authorized" => false,
        "execution_authorized" => false
      },
      "issued_at" => "2026-09-03T00:00:00Z"
    }
    relative = "#{EVIDENCE_ROOT}/#{phase}-director-review.yaml"
    path = @root.join(relative)
    path.dirname.mkpath
    path.write(YAML.dump(review))
    {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def install_director_review_context_pack(phase, returned_dispatch_pointer, review_input_pointer)
    returned_path = @root.join(returned_dispatch_pointer.fetch("path"))
    launch_dispatch = YAML.safe_load(returned_path.read, aliases: true)
    launch_dispatch["output_manifest"] = nil
    launch_dispatch["lifecycle_state"] = "launched"
    launch_dispatch["legal_next"] = %w[returned hold]
    launch_dispatch["lifecycle_from"] = "prepared"
    launch_relative = "runs/test-album/test-title/PILOT_001/work/#{phase}-director-launch-dispatch.yaml"
    launch_path = @root.join(launch_relative)
    launch_path.write(YAML.dump(launch_dispatch))
    launch_pointer = pointer(launch_relative)
    switch_receipt = {
      "receipt_id" => "PROFILE_EVOLUTION_DIRECTOR_SWITCH",
      "founder_authority" => "founder",
      "graph_revision" => "idol-graph-skill-load-profiles.v1",
      "switch_boundary" => "new_runs_only_after_verified_receipt",
      "source_set_sha256" => IdolRoleContextPack.graph_source_set_sha256(@root),
      "verified_at" => "2026-09-03T00:00:00Z"
    }
    pack = IdolRoleContextPack.build(
      root: @root,
      run_root: launch_dispatch.fetch("run"),
      assignment_id: launch_dispatch.fetch("dispatch_id"),
      role: "overall_director",
      profile_id: "overall_director",
      checkpoint_id: "director_startup",
      stage_id: "creative_route_discovery",
      section_ids: [],
      source_envelope: {"kind" => "department_dispatch"}.merge(launch_pointer),
      current_state: "launched",
      scope: {"profile_evolution_phase" => phase},
      non_scope: ["creative_pass", "automatic_profile_pointer_change"],
      authority: {"assigned_owner" => "overall_director", "promotion_owner" => "founder"},
      founder_epoch: "profile-evolution-review",
      founder_locks: [],
      creative_sources: [
        review_input_pointer.merge(
          "source_id" => IdolGraphJudgmentProfilePromotionContract::DIRECTOR_REVIEW_INPUT_SOURCE_ID,
          "purpose" => IdolGraphJudgmentProfilePromotionContract::DIRECTOR_REVIEW_INPUT_PURPOSE,
          "locator" => "/",
          "function" => IdolGraphJudgmentProfilePromotionContract::DIRECTOR_REVIEW_INPUT_FUNCTION,
          "role_groups" => ["overall_director"],
          "disposition" => "applied"
        )
      ],
      output_contract: {"kind" => "profile_evolution_director_review"},
      hold_conditions: ["stale_profile_evolution_evidence"],
      return_recipient: launch_dispatch.fetch("return_recipient"),
      provider: launch_dispatch.dig("provider_binding", "registered_provider"),
      runtime_surface: launch_dispatch.dig("provider_binding", "runtime_surface"),
      writer: IdolRoleContextPack::GRAPH_WRITER,
      run_class: "new_run",
      switch_receipt: switch_receipt
    )
    relative = "#{EVIDENCE_ROOT}/#{phase}-director-role-context-pack.yaml"
    path = @root.join(relative)
    path.write(YAML.dump(pack))
    pointer(relative)
  end

  def install_director_dispatch(phase, session_id, review_input_digest, review_output)
    goal_text = "Independently review exact profile evolution #{phase} evidence bytes."
    goal_sha = Digest::SHA256.hexdigest(goal_text)
    assignment_id = "PROFILE_EVOLUTION_DIRECTOR_#{phase.upcase}"
    raw_event_relative = "runs/test-album/test-title/PILOT_001/work/#{phase}-director-raw-goal-event.yaml"
    raw_event_path = @root.join(raw_event_relative)
    raw_event_path.dirname.mkpath
    raw_event_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-raw-goal-event.v1",
      "artifact_type" => "graph_provider_raw_goal_event",
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "native_goal_id" => "GOAL_PROFILE_EVOLUTION_#{phase.upcase}",
      "goal_text_sha256" => goal_sha,
      "terminal_state" => "complete",
      "last_event" => "goal_completed"
    ))
    raw_event_pointer = pointer(raw_event_relative)
    attestation_relative = "runs/test-album/test-title/PILOT_001/work/#{phase}-director-goal-attestation.yaml"
    attestation_path = @root.join(attestation_relative)
    attestation_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-goal-adapter-attestation.v1",
      "artifact_type" => "graph_provider_goal_adapter_attestation",
      "assignment_id" => assignment_id,
      "provider" => "grok",
      "runtime_surface" => "grok_build_cli_acp",
      "native_goal_id" => "GOAL_PROFILE_EVOLUTION_#{phase.upcase}",
      "goal_text_sha256" => goal_sha,
      "raw_event" => raw_event_pointer
    ))
    attestation_pointer = pointer(attestation_relative)
    event_relative = "runs/test-album/test-title/PILOT_001/work/#{phase}-director-goal-event.yaml"
    event_path = @root.join(event_relative)
    event_path.dirname.mkpath
    event_path.write(YAML.dump(
      "schema_version" => "idol-graph-provider-goal-terminal-event.v1",
      "artifact_type" => "graph_provider_goal_terminal_event",
      "evidence_class" => "provider_native_terminal_event",
      "provider" => "grok",
      "native_goal_id" => "GOAL_PROFILE_EVOLUTION_#{phase.upcase}",
      "goal_text" => goal_text,
      "goal_text_sha256" => goal_sha,
      "goal_semantics" => "grok_goal_completed_admission",
      "terminal_state" => "complete",
      "last_event" => "goal_completed",
      "adapter_attestation" => attestation_pointer
    ))
    event_pointer = pointer(event_relative)
    manifest_relative = "runs/test-album/test-title/PILOT_001/work/#{phase}-director-output-manifest.yaml"
    manifest_path = @root.join(manifest_relative)
    input_digest = review_input_digest
    manifest_path.write(YAML.dump(
      "schema_version" => "idol-graph-output-manifest.v1",
      "artifact_type" => "graph_dispatch_output_manifest",
      "dispatch_id" => assignment_id,
      "assigned_owner" => "overall_director",
      "input_digest_sha256" => input_digest,
      "output_kind" => "profile_evolution_director_review",
      "outputs" => [review_output]
    ))
    manifest_pointer = pointer(manifest_relative)
    resolved_provider, provider_holds = IdolRoleContextPack.resolve_provider(
      root: @root,
      role: "overall_director",
      provider: "grok",
      runtime_surface: "grok_build_cli_acp",
      logical_profile_alias: "frontier_director"
    )
    raise "fixture Director provider did not resolve: #{provider_holds.join(', ')}" unless provider_holds.empty?
    dispatch = {
      "schema_version" => "idol-graph-department-dispatch.v1",
      "artifact_type" => "graph_department_dispatch",
      "dispatch_id" => assignment_id,
      "run" => "runs/test-album/test-title/PILOT_001",
      "lane_id" => "overall",
      "section_cohort_id" => nil,
      "section_ids" => [],
      "logical_role" => "overall_director",
      "assigned_owner" => "overall_director",
      "output_writer" => {"owner" => "overall_director", "role" => "overall_director", "session_id" => session_id},
      "reviewer" => {"owner" => "overall_director", "role" => "overall_director", "lane_id" => "overall"},
      "return_recipient" => {"owner" => "overall_director", "role" => "overall_director", "return_route" => "profile_evolution_review"},
      "provider_binding" => {
        "registered_provider" => "grok",
        "runtime_surface" => "grok_build_cli_acp",
        "logical_profile_alias" => "frontier_director",
        "execution_profile_id" => resolved_provider.fetch("provider_profile_id"),
        "resolved_provider_model" => resolved_provider.fetch("exact_model"),
        "reasoning_effort" => resolved_provider.fetch("reasoning_effort"),
        "provider_capability_snapshot_sha256" => resolved_provider.fetch("registry_sha256"),
        "fallback_allowed" => false,
        "silent_substitution_allowed" => false
      },
      "goal_evidence" => {
        "native_goal_id" => "GOAL_PROFILE_EVOLUTION_#{phase.upcase}",
        "goal_text_sha256" => goal_sha,
        "goal_semantics" => "grok_goal_completed_admission",
        "goal_terminal_state" => "complete",
        "goal_last_event" => "goal_completed",
        "goal_terminal_event_sha256" => event_pointer.fetch("sha256"),
        "terminal_event" => event_pointer
      },
      "input_digest_sha256" => input_digest,
      "bounded_output" => {
        "output_kind" => "profile_evolution_director_review",
        "expected_paths" => [review_output.fetch("path")],
        "maximum_artifact_count" => 1
      },
      "output_manifest" => manifest_pointer,
      "judgment_profile_id" => PROFILE_ID,
      "stop_conditions" => ["stale_profile_evolution_evidence"],
      "lifecycle_state" => "returned",
      "legal_next" => %w[reviewed hold],
      "lifecycle_from" => "launched",
      "assignment_pass" => false
    }
    relative = "runs/test-album/test-title/PILOT_001/work/#{phase}-director-dispatch.yaml"
    path = @root.join(relative)
    path.write(YAML.dump(dispatch))
    pointer(relative)
  end

  def install_receipt_chain
    previous = nil
    IdolGraphJudgmentProfilePromotionContract::PHASES.to_h do |phase|
      receipt = {
        "schema_version" => IdolGraphJudgmentProfilePromotionContract::RECEIPT_SCHEMA_VERSION,
        "artifact_type" => IdolGraphJudgmentProfilePromotionContract::RECEIPT_ARTIFACT_TYPE,
        "receipt_id" => "RECEIPT_#{phase.upcase}",
        "profile_id" => PROFILE_ID,
        "phase" => phase,
        "old_release" => @old_release,
        "new_release" => @new_release,
        "predecessor_receipt_sha256" => previous,
        "outcome" => IdolGraphJudgmentProfilePromotionContract::OUTCOMES.fetch(phase),
        "evidence" => [@phase_evidence_pointers.fetch(phase)],
        "authorship" => {
          "author_kind" => phase == "founder_approval" ? "founder" : "assigned_model",
          "author_id" => phase == "founder_approval" ? "founder" : "assigned_profile_maintainer"
        },
        "authority" => {
          "scripts_author_creative_truth" => false,
          "automatic_profile_tuning" => false,
          "automatic_pointer_change" => false
        },
        "issued_at" => "2026-09-03T00:00:00Z"
      }
      relative = "#{EVIDENCE_ROOT}/#{phase}.yaml"
      path = @root.join(relative)
      path.dirname.mkpath
      path.write(YAML.dump(receipt))
      pointer = {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}
      previous = pointer.fetch("sha256")
      [phase, pointer]
    end
  end

  def install_promotion
    promotion = {
      "schema_version" => IdolGraphJudgmentProfilePromotionContract::SCHEMA_VERSION,
      "artifact_type" => IdolGraphJudgmentProfilePromotionContract::ARTIFACT_TYPE,
      "promotion_id" => "FOUNDER_APPROVED_PRE_FP_PROFILE_PROMOTION",
      "profile_id" => PROFILE_ID,
      "mode" => "founder_approved_current_pointer_promotion",
      "old_release" => @old_release,
      "new_release" => @new_release,
      "lifecycle_receipts" => @receipt_pointers,
      "authority" => {
        "scripts_author_creative_truth" => false,
        "automatic_profile_tuning" => false,
        "automatic_pointer_change" => false,
        "pointer_change_authority" => "founder_approval_receipt_only",
        "execution_authority" => false,
        "default_cutover_authority" => false
      },
      "status" => "founder_approved_for_current_pointer_change"
    }
    relative = "automation/graph-creative-judgment-profile-promotions/current-pointer/#{PROFILE_ID}/promotion.yaml"
    path = @root.join(relative)
    path.dirname.mkpath
    path.write(YAML.dump(promotion))
    path
  end

  def validate
    IdolGraphJudgmentProfilePromotionContract.validate_binding(
      root: @root,
      binding: {"path" => @promotion_path.relative_path_from(@root).to_s, "sha256" => Digest::SHA256.file(@promotion_path).hexdigest},
      current_release: @new_release,
      profile_id: PROFILE_ID,
      registry_status: "shadow_not_default",
      validation_mode: "active_promotion"
    )
  end

  def validation_errors
    validate
  end

  def mutate_promotion
    promotion = YAML.safe_load(@promotion_path.read, aliases: true)
    yield promotion
    @promotion_path.write(YAML.dump(promotion))
  end

  def mutate_receipt(phase)
    path = @root.join(@receipt_pointers.fetch(phase).fetch("path"))
    receipt = YAML.safe_load(path.read, aliases: true)
    yield receipt
    path.write(YAML.dump(receipt))
  end

  def refresh_promotion_receipt_pointer(phase)
    pointer = @receipt_pointers.fetch(phase)
    path = @root.join(pointer.fetch("path"))
    pointer["sha256"] = Digest::SHA256.file(path).hexdigest
    mutate_promotion { |promotion| promotion.fetch("lifecycle_receipts").fetch(phase)["sha256"] = pointer.fetch("sha256") }
  end

  def refresh_receipt_evidence_pointer(phase)
    evidence_pointer = @phase_evidence_pointers.fetch(phase)
    evidence_path = @root.join(evidence_pointer.fetch("path"))
    evidence_pointer["sha256"] = Digest::SHA256.file(evidence_path).hexdigest
    receipt_path = @root.join(@receipt_pointers.fetch(phase).fetch("path"))
    receipt = YAML.safe_load(receipt_path.read, aliases: true)
    receipt.fetch("evidence").first["sha256"] = evidence_pointer.fetch("sha256")
    receipt_path.write(YAML.dump(receipt))
    refresh_promotion_receipt_pointer(phase)
  end

  def load_phase_evidence(phase)
    YAML.safe_load(@root.join(@phase_evidence_pointers.fetch(phase).fetch("path")).read, aliases: true)
  end

  def write_phase_evidence(phase, evidence)
    @root.join(@phase_evidence_pointers.fetch(phase).fetch("path")).write(YAML.dump(evidence))
  end

  def mutate_phase_evidence(phase)
    evidence = load_phase_evidence(phase)
    yield evidence
    write_phase_evidence(phase, evidence)
  end

  def mutate_director_dispatch(phase)
    evidence = load_phase_evidence(phase)
    review_pointer = evidence.dig("payload", "director_review")
    review_path = @root.join(review_pointer.fetch("path"))
    review = YAML.safe_load(review_path.read, aliases: true)
    dispatch_pointer = review.fetch("director_dispatch")
    dispatch_path = @root.join(dispatch_pointer.fetch("path"))
    dispatch = YAML.safe_load(dispatch_path.read, aliases: true)
    yield dispatch
    dispatch_path.write(YAML.dump(dispatch))
    dispatch_pointer["sha256"] = Digest::SHA256.file(dispatch_path).hexdigest
    review_path.write(YAML.dump(review))
    review_pointer["sha256"] = Digest::SHA256.file(review_path).hexdigest
    write_phase_evidence(phase, evidence)
    refresh_receipt_evidence_pointer(phase)
  end

  def pointer(relative)
    path = @root.join(relative)
    {"path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest}
  end
end
