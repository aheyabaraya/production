# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "pathname"
require "tmpdir"
require "yaml"

module IdolGrokVideoExecutionPackage
  class ContractError < StandardError; end

  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .webp .heic].freeze
  VIDEO_TOOLS = %w[image_to_video reference_to_video].freeze
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze
  EXECUTION_IMAGE_SLOT_TOKEN = /@image(\d+)/.freeze

  module_function

  def named_execution_image_slots(prompt)
    prompt.to_s.scan(EXECUTION_IMAGE_SLOT_TOKEN).flatten.map { |digits| "@image#{digits}" }
  end

  def unattached_execution_image_slots(prompt, attached_count)
    allowed = (1..attached_count.to_i).map { |index| "@image#{index}" }
    named_execution_image_slots(prompt).reject { |token| allowed.include?(token) }.uniq
  end

  def load_mapping(path)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: true)
            end
    raise ContractError, "structured source must be an object: #{path}" unless value.is_a?(Hash)

    value
  rescue JSON::ParserError, Psych::Exception, Errno::ENOENT => e
    raise ContractError, "cannot read structured source: #{path}: #{e.message}"
  end

  def inside?(path, root)
    relative = path.expand_path.cleanpath.relative_path_from(root.expand_path.cleanpath).to_s
    relative != ".." && !relative.start_with?("../")
  rescue ArgumentError
    false
  end

  def exact_file(root, raw, label)
    root = Pathname.new(root).expand_path.cleanpath
    path = Pathname.new(raw.to_s)
    path = root.join(path) unless path.absolute?
    path = path.expand_path.cleanpath
    raise ContractError, "#{label} is outside the repository root" unless inside?(path, root)
    raise ContractError, "#{label} is missing" unless path.file?
    raise ContractError, "#{label} must not be a symlink" if path.symlink?

    real_root = root.realpath
    real_path = path.realpath
    raise ContractError, "#{label} resolves outside the repository root" unless inside?(real_path, real_root)

    real_path
  rescue Errno::ENOENT
    raise ContractError, "#{label} is missing"
  end

  def relative(path, root)
    Pathname.new(path).expand_path.cleanpath.relative_path_from(Pathname.new(root).expand_path.cleanpath).to_s
  rescue ArgumentError
    Pathname.new(path).expand_path.cleanpath.to_s
  end

  def file_sha(path)
    Digest::SHA256.file(path).hexdigest
  end

  def canonical(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) { |key, out| out[key] = canonical(value[key]) }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def value_sha(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def registered_video_lane!(root:, execution:)
    root = Pathname.new(root).expand_path.cleanpath
    registry_path = exact_file(root, "automation/harness-provider-profile-registry.yaml", "provider registry")
    registry = load_mapping(registry_path)
    lane = registry.dig("media_lanes", "grok_build_oauth_subscription")
    raise ContractError, "registered Grok subscription media lane is missing" unless lane.is_a?(Hash)

    source_path = exact_file(root, lane["provider_profile_source"], "Grok provider profile source")
    source_sha = file_sha(source_path)
    raise ContractError, "Grok provider profile source SHA-256 is stale" unless lane["provider_profile_source_sha256"] == source_sha

    source = load_mapping(source_path)
    capability = source.dig("media_capabilities", "video_subscription_cli")
    expected_capability = {
      "auth_lane" => lane["auth_lane"],
      "capability_status" => lane["capability_status"],
      "harness_status" => lane["video_harness_status"],
      "adapter_id" => lane["video_adapter_id"],
      "tools" => lane["video_tools"],
      "direct_image_to_video" => lane["direct_image_to_video"],
      "prompt_rewrite_policy" => lane["video_prompt_rewrite_policy"],
      "automatic_fallback" => lane["automatic_fallback"],
      "output_contract" => lane["video_output_contract"],
      "local_output_required" => lane["video_local_output_required"],
      "current_assignment_inventory_or_adapter_match_required" => lane["video_runtime_inventory_or_adapter_match_required"],
      "cue_specific_founder_external_generation_authority_required" => lane["video_founder_external_generation_authority_required"],
      "allowed_durations_seconds" => lane["video_durations_seconds"],
      "allowed_resolutions" => lane["resolutions"],
      "resolution_1080p" => lane["resolution_1080p"]
    }
    unless capability == expected_capability
      raise ContractError, "Grok video capability differs from the exact central provider snapshot"
    end

    expected_execution = {
      "direct_image_to_video" => "forbidden",
      "source_stage" => "passed_03v",
      "source_image_frame_count" => 1,
      "source_image_review_status" => "passed_production_cut",
      "prompt_source" => "exact_03v_rendered_prompt",
      "prompt_rewrite_policy" => "forbidden",
      "selected_adapter_id" => lane["video_adapter_id"],
      "auth_lane" => "grok_build_oauth",
      "provider_profile_id" => lane["provider_profile_id"],
      "provider_profile_sha256" => source_sha,
      "automatic_fallback" => "none"
    }
    expected_execution.each do |field, expected|
      raise ContractError, "Grok video execution #{field} differs from the exact registered lane" unless execution[field] == expected
    end
    unless Array(lane["video_tools"]).include?(execution["selected_tool"])
      raise ContractError, "Grok video tool is absent from the registered provider capability"
    end
    unless Array(lane["video_durations_seconds"]).include?(execution["requested_duration_seconds"])
      raise ContractError, "Grok video duration is absent from the registered provider capability"
    end
    unless Array(lane["resolutions"]).include?(execution["requested_resolution"])
      raise ContractError, "Grok video resolution is absent from the registered provider capability"
    end

    {
      "lane" => lane,
      "registry_path" => relative(registry_path, root),
      "registry_sha256" => file_sha(registry_path),
      "provider_source_path" => relative(source_path, root),
      "provider_source_sha256" => source_sha,
      "video_harness_status" => lane["video_harness_status"]
    }
  end

  def ordered_inputs!(root:, cue:, execution:, placement: nil, production_review: nil)
    rows = Array(cue["source_production_cut_images"])
    unless rows.all? { |row| row.is_a?(Hash) && !row["production_cut_id"].to_s.empty? }
      raise ContractError, "Grok video input roster contains an invalid Production Cut row"
    end
    ids_in_roster = rows.map { |row| row["production_cut_id"].to_s }
    raise ContractError, "Grok video input roster contains duplicate Production Cut IDs" unless ids_in_roster.uniq == ids_in_roster
    by_id = rows.each_with_object({}) { |row, out| out[row["production_cut_id"].to_s] = row }
    tool = execution["selected_tool"].to_s
    raise ContractError, "unsupported Grok video tool" unless VIDEO_TOOLS.include?(tool)

    ids = if tool == "image_to_video"
            raise ContractError, "image_to_video must use one source and no additional references" unless Array(execution["additional_reference_image_ids"]).empty? && execution["founder_reference_selection"].nil?
            [execution["source_production_cut_id"].to_s]
          else
            selection = execution["founder_reference_selection"]
            expected = [execution["source_production_cut_id"].to_s] + Array(execution["additional_reference_image_ids"]).map(&:to_s)
            unless selection.is_a?(Hash) && selection["founder_authored"] == true && selection["decision"] == "selected_for_reference_to_video" && selection["selected_image_ids_in_order"] == expected
              raise ContractError, "reference_to_video requires the exact Founder-selected image IDs and order"
            end
            raise ContractError, "reference_to_video requires two or three distinct inputs" unless expected.length.between?(2, 3) && expected.uniq == expected
            expected
          end

    resolved = ids.each_with_index.map do |id, index|
      row = by_id[id]
      raise ContractError, "selected Grok video input #{id} is absent from the passed Production Cut roster" unless row.is_a?(Hash)
      unless row["pixel_review_status"] == "passed_production_cut"
        raise ContractError, "selected Grok video input #{id} is not pixel-passed"
      end
      path = exact_file(root, row["path"], "selected Grok video input #{id}")
      digest = file_sha(path)
      raise ContractError, "selected Grok video input #{id} SHA-256 is stale" unless row["sha256"] == digest
      extension = path.extname.downcase
      raise ContractError, "selected Grok video input #{id} has an unsupported image extension" unless IMAGE_EXTENSIONS.include?(extension)
      packed = {
        "order" => index + 1,
        "role" => tool == "image_to_video" ? "frame_1" : "reference_#{index + 1}",
        "production_cut_id" => id,
        "production_cut_type" => row["production_cut_type"],
        "source_path" => relative(path, root),
        "source_sha256" => digest,
        "package_filename" => format("input-%02d%s", index + 1, extension)
      }
      if placement.is_a?(Hash)
        unit = Array(placement["production_cut_units"]).find { |item| item.to_h["production_cut_id"].to_s == id } || {}
        raise ContractError, "selected Grok video input #{id} is absent from audio placement" if unit["production_cut_id"].to_s.empty?
        transport = {"path" => row["path"], "sha256" => row["sha256"]}
        raise ContractError, "selected Grok video input #{id} must exact-match the audio-placement placement_image" unless unit["placement_image"] == transport
        review_row = Array(production_review.to_h["production_cut_reviews"]).find { |item| item.to_h["production_cut_id"].to_s == id } || {}
        raise ContractError, "selected Grok video input #{id} reviewed original is absent from Production Cut review" if review_row["production_cut_id"].to_s.empty?
        raise ContractError, "selected Grok video input #{id} reviewed original must exact-match Production Cut review and audio-placement passed_source_image" unless unit["passed_source_image"] == review_row.slice("path", "sha256")
        if row["production_cut_type"] == "official_core"
          raise ContractError, "selected Grok video Official Core input #{id} must remain the reviewed original" unless transport == unit["passed_source_image"]
        elsif row["production_cut_type"] == "branch"
          raise ContractError, "selected Grok video Branch input #{id} must be the receipt-bound placement upscale" unless unit["placement_image_role"] == "validated_local_upscale" && unit["local_upscale_receipt"].is_a?(Hash)
        end
        packed["reviewed_original_path"] = unit.dig("passed_source_image", "path")
        packed["reviewed_original_sha256"] = unit.dig("passed_source_image", "sha256")
        packed["placement_image_role"] = unit["placement_image_role"]
      end
      packed
    end
    primary = resolved.first
    primary_expectations = {
      "source_production_cut_type" => primary["production_cut_type"],
      "source_image_path" => primary["source_path"],
      "source_image_sha256" => primary["source_sha256"]
    }
    primary_expectations.each do |field, expected|
      raise ContractError, "Grok video execution #{field} differs from the first ordered Production Cut" unless execution[field] == expected
    end
    resolved
  end

  def plan!(root:, manifest_path:, manifest:, cue_id:)
    root = Pathname.new(root).expand_path.cleanpath
    manifest_path = exact_file(root, manifest_path, "video prompt manifest")
    cue = Array(manifest["cues"]).find { |row| row.is_a?(Hash) && row["cue_id"].to_s == cue_id.to_s }
    raise ContractError, "video cue not found: #{cue_id}" unless cue
    execution = cue["grok_execution"]
    raise ContractError, "video cue lacks Grok execution fields" unless execution.is_a?(Hash)
    registration = registered_video_lane!(root: root, execution: execution)
    placement = nil
    production_review = nil
    if manifest["source_audio_branch_cut_placement"].is_a?(Hash) && !manifest.dig("source_audio_branch_cut_placement", "path").to_s.empty?
      placement = load_mapping(exact_file(root, manifest["source_audio_branch_cut_placement"]["path"], "audio placement"))
    end
    if manifest["source_production_cut_review"].is_a?(Hash) && !manifest.dig("source_production_cut_review", "path").to_s.empty?
      production_review = load_mapping(exact_file(root, manifest["source_production_cut_review"]["path"], "Production Cut review"))
    end
    ordered_inputs = ordered_inputs!(root: root, cue: cue, execution: execution, placement: placement, production_review: production_review)

    prompt = cue["prompt_text"].to_s
    prompt_sha = Digest::SHA256.hexdigest(prompt)
    raise ContractError, "video prompt SHA-256 is stale" unless execution["prompt_sha256"] == prompt_sha
    unattached_execution_image_slots(prompt, ordered_inputs.length).each do |slot|
      raise ContractError, "execution prompt names unattached #{slot}; do not rewrite, HOLD"
    end
    section = Array(manifest["section_shards"]).find do |row|
      row.is_a?(Hash) && Array(row["cue_ids"]).map(&:to_s).include?(cue_id.to_s)
    end
    raise ContractError, "video cue is absent from the section shard roster" unless section

    holds = []
    holds << "manifest_not_cdd_passed" unless manifest["status"] == "passed"
    holds << "section_not_cdd_passed" unless section["status"] == "passed"
    holds << "provider_video_harness_#{registration['video_harness_status']}" unless registration["video_harness_status"] == "active"
    holds << "founder_external_video_authority_missing" if execution["founder_generation_authority_id"].to_s.empty?
    expected_output_stem = cue_id.to_s
    run_root = manifest["run_root"].to_s

    {
      "schema_version" => "idol_media_execution_dry_run.v1",
      "contract_status" => "derived_transport_projection_not_execution_authority",
      "media_type" => "video",
      "external_call_performed" => false,
      "dry_run_only" => true,
      "source_manifest" => {
        "path" => relative(manifest_path, root),
        "sha256" => file_sha(manifest_path),
        "schema_version" => manifest["schema_version"],
        "status" => manifest["status"]
      },
      "cue_id" => cue_id,
      "section_id" => cue["section_id"],
      "video_job_id" => execution["video_job_id"],
      "selected_tool" => execution["selected_tool"],
      "prompt_text" => prompt,
      "prompt_sha256" => prompt_sha,
      "ordered_inputs" => ordered_inputs,
      "ordered_input_set_sha256" => value_sha(ordered_inputs.map { |row| row.slice("order", "production_cut_id", "source_path", "source_sha256") }),
      "requested_duration_seconds" => execution["requested_duration_seconds"],
      "requested_aspect_ratio" => execution["requested_aspect_ratio"],
      "requested_resolution" => execution["requested_resolution"],
      "resolution_pass" => execution["resolution_pass"],
      "selected_adapter_id" => execution["selected_adapter_id"],
      "auth_lane" => execution["auth_lane"],
      "provider_profile_id" => execution["provider_profile_id"],
      "provider_profile_sha256" => execution["provider_profile_sha256"],
      "provider_registry_path" => registration["registry_path"],
      "provider_registry_sha256" => registration["registry_sha256"],
      "provider_source_path" => registration["provider_source_path"],
      "provider_video_harness_status" => registration["video_harness_status"],
      "prompt_rewrite_policy" => "forbidden",
      "provider_auth_model_fallback" => "none",
      "external_execution_ready" => holds.empty?,
      "execution_hold_reasons" => holds,
      "operator_package" => {
        "prompt_filename" => "prompt.txt",
        "execution_package_root" => File.join(manifest["canonical_video_prompt_output_root"].to_s, "execution-ready"),
        "expected_output_filename" => "#{expected_output_stem}.mp4",
        "expected_output_match_stem" => expected_output_stem,
        "collection_route" => "grok_provider_native_manual_download_then_hash_bound_03v_import",
        "collection_target_root" => File.join(run_root, "generations/video/generated-clips/03v"),
        "collector" => "scripts/idol_03v_import_generated_clips.rb",
        "intake" => "scripts/idol_03v_generated_playback_intake.rb",
        "playback_review" => "scripts/idol_03v_playback_review_worklist.rb"
      },
      "authority_boundaries" => {
        "package_is_creative_pass" => false,
        "package_is_generation_approval" => false,
        "package_is_playback_pass" => false,
        "package_is_edit_readiness" => false,
        "automatic_fallback" => "none"
      }
    }
  end

  def materialize!(root:, plan:, package_root:)
    root = Pathname.new(root).expand_path.cleanpath
    package_root = Pathname.new(package_root).expand_path.cleanpath
    run_output_root = root.join(plan.dig("operator_package", "execution_package_root")).expand_path.cleanpath
    raise ContractError, "manifest execution package root escapes the repository" unless inside?(run_output_root, root)
    tmp_roots = [Pathname.new("/private/tmp"), Pathname.new(Dir.tmpdir)].map(&:expand_path)
    allowed_root = if inside?(package_root, run_output_root)
                     run_output_root
                   else
                     tmp_roots.find { |tmp_root| inside?(package_root, tmp_root) }
                   end
    raise ContractError, "video execution package root must stay under the run execution-ready root or /private/tmp" unless allowed_root
    raise ContractError, "video execution package root must not be a symlink" if package_root.exist? && package_root.symlink?

    ancestor = package_root
    ancestor = ancestor.parent until ancestor.exist? || ancestor.root?
    allowed_ancestor = allowed_root
    allowed_ancestor = allowed_ancestor.parent until allowed_ancestor.exist? || allowed_ancestor.root?
    unless ancestor.exist? && allowed_ancestor.exist? && inside?(ancestor.realpath, allowed_ancestor.realpath)
      raise ContractError, "video execution package root escapes its allowed boundary through a symlink"
    end

    package_root.mkpath
    slug = [plan["video_job_id"], plan["cue_id"], plan["requested_resolution"]]
      .map { |value| value.to_s.gsub(/[^A-Za-z0-9_.-]+/, "_") }
      .join("__")
    target = package_root.join(slug)
    raise ContractError, "video execution package already exists; overwrite is forbidden" if target.exist?

    temporary = Pathname.new(Dir.mktmpdir(".#{slug}.", package_root.to_s))
    begin
      temporary.join("prompt.txt").binwrite(plan["prompt_text"].to_s.b)
      copied = Array(plan["ordered_inputs"]).map do |row|
        source = exact_file(root, row["source_path"], "Grok video package input #{row['order']}")
        destination = temporary.join(row["package_filename"])
        FileUtils.copy_file(source, destination)
        digest = file_sha(destination)
        raise ContractError, "copied Grok video package input SHA-256 changed" unless digest == row["source_sha256"]
        row.merge("package_path" => row["package_filename"], "package_sha256" => digest)
      end
      package_plan = plan.merge(
        "prompt_text" => nil,
        "materialized_package" => {
          "status" => plan["external_execution_ready"] ? "ready_for_explicit_external_execution" : "prepared_with_holds",
          "folder_name" => slug,
          "prompt_path" => "prompt.txt",
          "prompt_sha256" => file_sha(temporary.join("prompt.txt")),
          "ordered_inputs" => copied
        }
      )
      temporary.join("package-plan.json").write(JSON.pretty_generate(package_plan) + "\n", encoding: "UTF-8")
      temporary.rename(target)
      {
        "package_path" => target.to_s,
        "package_status" => package_plan.dig("materialized_package", "status"),
        "package_plan_path" => target.join("package-plan.json").to_s,
        "package_plan_sha256" => file_sha(target.join("package-plan.json")),
        "file_count" => 2 + copied.length
      }
    ensure
      FileUtils.remove_entry(temporary) if temporary.exist?
    end
  rescue Errno::EEXIST
    raise ContractError, "video execution package already exists; overwrite is forbidden"
  end
end
