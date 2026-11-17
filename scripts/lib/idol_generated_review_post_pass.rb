# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "tempfile"
require "yaml"

module IdolGeneratedReviewPostPass
  class Error < StandardError; end

  module_function

  def apply!(
    review_path:,
    run_path:,
    root:,
    python:,
    schema_validator:,
    review_schema:,
    local_upscaler:,
    generated_review_validator:,
    audio_placement_validator:,
    trigger:,
    allowed_pending_status:,
    pass_application:
  )
    review_path = Pathname.new(review_path).expand_path
    run_path = Pathname.new(run_path).expand_path
    root = Pathname.new(root).expand_path
    review_relative = review_path.relative_path_from(root).to_s
    review = load_mapping(review_path)
    unless review["schema_version"] == "idol_generated_branch_cut_review.v4"
      raise Error, "generated Branch-Cut returned output must use idol_generated_branch_cut_review.v4"
    end
    validate_schema!(python, schema_validator, review_schema, review_path, root)
    unless Array(review["section_reviews"]).all? { |row| row.is_a?(Hash) && row["decision"] == "pass" } &&
           Array(review["branch_cut_reviews"]).all? { |row| row.is_a?(Hash) && row["decision"] == "pass" }
      raise Error, "pixel close cannot promote a generated review whose section or Branch-Cut inspection is not pass"
    end

    source_review_sha256 = Digest::SHA256.file(review_path).hexdigest
    applied = "already_passed"
    if review["status"] == allowed_pending_status
      review["status"] = "passed"
      review.fetch("automation_boundaries")["audio_branch_cut_placement_may_start_after_pass"] = true
      promoted_bytes = YAML.dump(review)
      Tempfile.create(["idol-generated-review-pass", ".yaml"]) do |temp|
        temp.write(promoted_bytes)
        temp.flush
        validate_schema!(python, schema_validator, review_schema, Pathname.new(temp.path), root)
      end
      atomic_replace(review_path, promoted_bytes.b)
      applied = pass_application
    elsif review["status"] != "passed"
      raise Error, "pixel close may promote only #{allowed_pending_status} or reuse an already passed generated review"
    end

    upscale = JSON.parse(run_checked(
      [python.to_s, local_upscaler.to_s, "passed-review", "--root", root.to_s, "--review", review_relative],
      root,
      "automatic local upscale after pixel PASS"
    ))
    run_checked(
      ["ruby", generated_review_validator.to_s, "--json", review_relative],
      root,
      "post-upscale generated Branch-Cut review validation"
    )

    placement_path = run_path.join("03V-audio-branch-cut-placement.yaml")
    if placement_path.file?
      placement_relative = placement_path.relative_path_from(root).to_s
      run_checked(
        ["ruby", audio_placement_validator.to_s, "--json", "--require-ready", placement_relative],
        root,
        "03V Audio Production-Cut Placement validation"
      )
      next_stage = "video_motion_direction"
      ready_for_03v = true
    else
      placement_relative = nil
      next_stage = "audio_branch_cut_placement"
      ready_for_03v = false
    end

    {
      "triggered" => true,
      "trigger" => trigger,
      "local_processing" => "complete",
      "generated_review" => review_relative,
      "generated_review_sha256_before_pass" => source_review_sha256,
      "generated_review_sha256_after_pass" => Digest::SHA256.file(review_path).hexdigest,
      "review_pass_application" => applied,
      "upscaled_packet_count" => Array(upscale["results"]).length,
      "reused_packet_count" => Array(upscale["results"]).count { |row| row["reused"] == true },
      "next_stage" => next_stage,
      "audio_branch_cut_placement" => placement_relative,
      "03v_may_start" => ready_for_03v
    }
  rescue JSON::ParserError => e
    raise Error, "automatic local upscale returned unreadable JSON: #{e.message}"
  rescue KeyError => e
    raise Error, "generated review is missing #{e.key}"
  end

  def load_mapping(path)
    value = if path.extname.downcase == ".json"
              JSON.parse(path.read)
            else
              YAML.safe_load(path.read, permitted_classes: [], aliases: true)
            end
    raise Error, "generated review must be a mapping" unless value.is_a?(Hash)
    value
  rescue JSON::ParserError, Psych::Exception => e
    raise Error, "cannot parse generated review: #{e.message}"
  end

  def validate_schema!(python, validator, schema, path, root)
    stdout, stderr, status = Open3.capture3(
      python.to_s,
      validator.to_s,
      schema.to_s,
      path.to_s,
      chdir: root.to_s
    )
    return if status.success?
    raise Error, "generated Branch-Cut review failed schema validation: #{[stderr, stdout].join(' ').strip}"
  end

  def run_checked(command, root, label)
    stdout, stderr, status = Open3.capture3(*command, chdir: root.to_s)
    return stdout if status.success?
    raise Error, "#{label} failed; 03V remains on mechanical HOLD: #{[stderr, stdout].join(' ').strip}"
  end

  def atomic_replace(path, bytes)
    path.dirname.mkpath
    Tempfile.create([".idol-review-pass", path.extname], path.dirname.to_s) do |temp|
      temp.binmode
      temp.write(bytes)
      temp.flush
      temp.fsync
      File.rename(temp.path, path.to_s)
    end
  end
end
