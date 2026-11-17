# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "support/active_image_generation_fixture"

class IdolPrepareImageRenderCorrectionTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_prepare_image_render_correction.rb")
  REQUEST_PREPARER = ROOT.join("scripts", "idol_prepare_image_generation_request.rb")
  PACKET_ID = "PKT_BC01_ACTION"

  def setup
    @fixture = ActiveImageGenerationFixture.create
    @request_path = prepare_ready_request
    @request = load_yaml(@request_path)
    @source_image = write_file("outputs/#{PACKET_ID}.png", "generated source pixels")
    @prior_review = write_prior_review
    write_authorization
    write_spec
  end

  def teardown
    @fixture&.cleanup
  end

  def test_v12_context_v8_fp17_correction_is_exactly_bound_and_holds_openai_execution
    output = run_dir.join("work", "image_render_corrections", PACKET_ID, "request.yaml")
    result = run_correction(output: output, write: true)

    assert result[:status].success?, result[:stderr]
    request = load_yaml(output)
    assert_equal "idol_image_render_correction.v8", request["schema_version"]
    assert_equal "idol_image_generation_request.v12", request.dig("base_request", "schema_version")
    assert_equal "openai_api_gpt_image_2", request.dig("base_request", "execution_adapter_id")
    assert_equal "idol-harness-context-pack.v7", request.dig("immutable_inputs", "context_pack", "schema_version")
    assert_equal "front-planning-readiness.v17", request.dig("immutable_inputs", "planning_source", "schema_version")
    assert_equal "active_v12_logical_role_plan_and_combined_attachment_order_unchanged", request.dig("immutable_inputs", "visual_reference_attachment_policy")
    assert_equal @request["section_cohort_id"], request.dig("immutable_inputs", "section_cohort_id")
    assert_equal value_sha(@request.fetch("reference_role_plan")), request.dig("immutable_inputs", "reference_role_plan_sha256")
    assert_equal "hold", request["status"]
    assert_includes request["hold_reasons"].join(" "), "no separate Founder-gated correction executor"
  end

  def test_fp16_hash_drift_fails_closed
    @spec.dig("execution_context", "planning_source")["sha256"] = "0" * 64
    rewrite_spec

    result = run_correction

    refute result[:status].success?
    assert_includes result[:stderr], "stale base planning source hash"
  end

  def test_context_must_be_active_v7
    context = load_yaml(@fixture.context_path("BC01_ACTION"))
    context["schema_version"] = "idol-harness-context-pack.v6"
    stale_context = write_yaml("work/correction-context-v6.yaml", context)
    @spec.dig("execution_context", "context_pack").merge!(artifact_ref(stale_context, "idol-harness-context-pack.v6"))
    rewrite_spec

    result = run_correction

    refute result[:status].success?
    assert_match(/context pack.*(?:v7|schema validation)/i, result[:stderr])
  end

  def test_render_local_correction_cannot_change_scene_intent
    @spec.dig("corrected_prompt", "scene_intent") << " changed world"
    refresh_corrected_prompt_sha
    rewrite_spec

    result = run_correction

    refute result[:status].success?
    assert_includes result[:stderr], "may not change scene_intent"
  end

  def test_founder_authorization_hash_drift_becomes_hold
    @authorization["base_request_sha256"] = "0" * 64
    rewrite_authorization
    refresh_spec_authorization_ref
    rewrite_spec
    output = run_dir.join("work", "image_render_corrections", PACKET_ID, "held.yaml")

    result = run_correction(output: output, write: true)

    assert result[:status].success?, result[:stderr]
    request = load_yaml(output)
    assert_equal "hold", request["status"]
    assert_includes request["hold_reasons"], "authorization base request hash does not match"
  end

  private

  def run_dir
    @fixture.mv.run_dir
  end

  def relative(path)
    path.expand_path.relative_path_from(ROOT).to_s
  end

  def sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def value_sha(value)
    canonical = case value
                when Hash
                  value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = value_sha_value(value.fetch(key)) }
                else
                  value_sha_value(value)
                end
    Digest::SHA256.hexdigest(JSON.generate(canonical))
  end

  def value_sha_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = value_sha_value(value.fetch(key)) }
    when Array
      value.map { |item| value_sha_value(item) }
    else
      value
    end
  end

  def artifact_ref(path, version = nil)
    {"path" => relative(path), "sha256" => sha(path)}.tap do |ref|
      ref["schema_version"] = version if version
    end
  end

  def load_yaml(path)
    YAML.safe_load(path.read, aliases: true)
  end

  def write_file(relative_path, bytes)
    path = run_dir.join(relative_path)
    path.dirname.mkpath
    path.binwrite(bytes)
    path
  end

  def write_yaml(relative_path, document)
    path = run_dir.join(relative_path)
    path.dirname.mkpath
    path.write(YAML.dump(document))
    path
  end

  def prepare_ready_request
    approval = @fixture.write_approval(packet_id: PACKET_ID)
    output = run_dir.join("work", "image-generation-requests", "#{PACKET_ID}.yaml")
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      REQUEST_PREPARER.to_s,
      run_dir.to_s,
      "--source-prompt-packets", @fixture.source_02b_path.to_s,
      "--packet-id", PACKET_ID,
      "--approval-source", approval.to_s,
      "--output", output.to_s,
      "--write",
      chdir: ROOT.to_s
    )
    raise "base request failed: #{stderr}\n#{stdout}" unless status.success?
    output
  end

  def write_prior_review
    pointer = @request.fetch("cut_pointer")
    write_yaml(
      "review/correction-prior-review.yaml",
      {
        "schema_version" => "idol_generated_branch_cut_review.v4",
        "content_id" => run_dir.basename.to_s,
        "status" => "hold",
        "branch_cut_reviews" => [{
          "core_cut_id" => pointer.fetch("parent_core_cut_id"),
          "branch_cut_id" => pointer.fetch("cut_id"),
          "packet_id" => PACKET_ID,
          "image_path" => relative(@source_image),
          "decision" => "hold",
          "review_note" => "Remove only the duplicated edge around the registered marker."
        }]
      }
    )
  end

  def write_authorization
    @authorization = {
      "schema_version" => "idol_image_render_correction_authorization.v1",
      "authorization_id" => "IRCA_TEST_ARTIFACT_REPAIR",
      "authorized_by" => "founder",
      "content_id" => run_dir.basename.to_s,
      "correction_id" => "IRC_TEST_ARTIFACT_REPAIR",
      "packet_id" => PACKET_ID,
      "base_request_sha256" => sha(@request_path),
      "source_generated_image_sha256" => sha(@source_image),
      "prior_review_sha256" => sha(@prior_review),
      "execution_adapter_id" => "openai_api_gpt_image_2",
      "allowed_categories" => ["render_artifact_removal"],
      "max_attempts" => 2,
      "authorized_attempt_indexes" => [1, 2],
      "external_execution_approved" => true,
      "paid_generation_approved" => true
    }
    @authorization_path = write_yaml("review/image-render-correction-authorization.yaml", @authorization)
  end

  def rewrite_authorization
    @authorization_path.write(YAML.dump(@authorization))
  end

  def write_spec
    packet_ref = @request.fetch("source_prompt_packet")
    packets = load_yaml(ROOT.join(packet_ref.fetch("path")))
    packet = packets.fetch("prompt_packets").fetch(packet_ref.fetch("json_pointer").split("/").last.to_i)
    lock_pointer = "#{packet_ref.fetch('json_pointer')}/five_line_components/visible_details/background_and_space"
    lock_value = packet.dig("five_line_components", "visible_details", "background_and_space")
    base = @request.fetch("prompt")
    corrected = {
      "identity_reference_rule" => base.fetch("identity_reference_rule"),
      "scene_intent" => base.fetch("scene_intent"),
      "visible_details" => "#{base.fetch('visible_details')} Remove the duplicated marker edge only; preserve 4K, high quality, and high detail.",
      "action_cue" => base.fetch("action_cue"),
      "avoid" => "#{base.fetch('avoid')} Also avoid duplicated marker edges."
    }
    context_path = @fixture.context_path("BC01_ACTION")
    planning_path = @fixture.mv.front_path
    review_record = load_yaml(@prior_review).fetch("branch_cut_reviews").first
    candidate = run_dir.join("outputs", "corrections", "#{PACKET_ID}-IRC_TEST_ARTIFACT_REPAIR-a01.png")
    @spec = {
      "schema_version" => "idol_image_render_correction_spec.v1",
      "content_id" => run_dir.basename.to_s,
      "correction_id" => "IRC_TEST_ARTIFACT_REPAIR",
      "packet_id" => PACKET_ID,
      "authoring_owner" => "model_authored_render_correction",
      "authoring_reason" => "Repair one named render artifact without changing creative truth.",
      "base_request" => artifact_ref(@request_path),
      "execution_context" => {
        "context_pack" => artifact_ref(context_path, "idol-harness-context-pack.v7"),
        "planning_source" => artifact_ref(planning_path, "front-planning-readiness.v17")
      },
      "source_generated_image" => artifact_ref(@source_image),
      "prior_review" => artifact_ref(@prior_review).merge(
        "record_pointer" => "/branch_cut_reviews/0",
        "record_value_sha256" => @fixture.mv.value_sha(review_record)
      ),
      "defect" => {
        "defect_id" => "DEF_DUPLICATED_EDGE",
        "categories" => ["render_artifact_removal"],
        "observed_problem" => "A duplicated marker edge is visible.",
        "expected_correction" => "Remove only the duplicate edge.",
        "changed_prompt_sections" => %w[visible_details avoid],
        "base_lock_refs" => [{
          "json_pointer" => lock_pointer,
          "value_sha256" => @fixture.mv.value_sha(lock_value),
          "repair_relation" => "restore_existing_lock_not_new_direction"
        }]
      },
      "corrected_prompt" => corrected,
      "preservation_assertions" => %w[
        parent_core_cut_timing_and_section_ownership
        branch_cut_id_sequence_derivation_and_distinct_contribution
        member_visual_input_set_and_order visual_reference_binding_set_and_order
        explicit_founder_locks story_and_world core_action_and_gaze camera_geometry
        wardrobe_lane aspect_ratio_and_quality original_generated_output_retained
      ].to_h { |field| [field, true] },
      "authorization_source" => artifact_ref(@authorization_path),
      "attempt" => {
        "index" => 1,
        "candidate_output_path" => relative(candidate),
        "expected_review_receipt_path" => relative(Pathname.new("#{candidate}.review.yaml"))
      }
    }
    refresh_corrected_prompt_sha
    @spec_path = write_yaml("work/image_render_corrections/#{PACKET_ID}/spec.yaml", @spec)
  end

  def refresh_corrected_prompt_sha
    corrected = @spec.fetch("corrected_prompt")
    text = [
      "Identity reference rule: #{corrected.fetch('identity_reference_rule')}",
      "Scene intent: #{corrected.fetch('scene_intent')}",
      "Visible details: #{corrected.fetch('visible_details')}",
      "Action cue: #{corrected.fetch('action_cue')}",
      "Avoid: #{corrected.fetch('avoid')}"
    ].join("\n")
    corrected["text_sha256"] = Digest::SHA256.hexdigest(text)
  end

  def refresh_spec_authorization_ref
    @spec["authorization_source"] = artifact_ref(@authorization_path)
  end

  def rewrite_spec
    @spec_path.write(YAML.dump(@spec))
  end

  def run_correction(output: nil, write: false)
    arguments = [RbConfig.ruby, SCRIPT.to_s, run_dir.to_s, "--spec", @spec_path.to_s]
    arguments.concat(["--output", output.to_s]) if output
    arguments << "--write" if write
    stdout, stderr, status = Open3.capture3(*arguments, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end
end
