#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_graph_criterion_evidence_contract"
require_relative "lib/idol_storyboard_collected_angle_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "review.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
STORYBOARD_VALIDATOR = ROOT.join("scripts", "validate_master_storyboard.rb")
PROMPT_VALIDATOR = ROOT.join("scripts", "validate_02b_imagegen_contract.rb")
UPSCALE_VALIDATOR = ROOT.join("scripts", "validate_local_image_upscale_receipt.py")
GRAPH_DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_graph_director_lineage.rb")
GRAPH_JUDGMENT_VALIDATOR = ROOT.join("scripts", "validate_graph_contextual_judgment.rb")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {root: ROOT, json: false, max_errors: 40}
OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_generated_branch_cut_review.rb [options] PATH"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--json") { options[:json] = true }
  opts.on("--max-errors COUNT", Integer) { |value| options[:max_errors] = value }
end.parse!

artifact_arg = ARGV.shift
abort "generated Branch-Cut review path is required" if artifact_arg.to_s.empty? || !ARGV.empty?

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "document must be an object" unless value.is_a?(Hash)
  value
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def inside?(path, root)
  relative = path.relative_path_from(root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

def bound_source(ref, label, root, errors)
  path = resolve_path(ref.to_h["path"], root)
  unless inside?(path, root) && path.file?
    errors << "#{label} is missing or outside the repository"
    return [nil, nil]
  end
  actual = Digest::SHA256.file(path).hexdigest
  errors << "#{label} SHA-256 is stale" unless ref.to_h["sha256"].to_s == actual
  [path, load_mapping(path)]
end

def canonical_json_value(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
      result[key] = canonical_json_value(value[key])
    end
  when Array
    value.map { |item| canonical_json_value(item) }
  else
    value
  end
end

def structured_value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical_json_value(value)))
end

LEGACY_DELEGATED_PIXEL_CRITERIA = %w[
  character_identity_visual_continuity
  scene_visual_package
  action_pose_motion_anchor
  multi_reference_synthesis
  neighbor_cut_distinct_contribution
  artifact_anatomy_crop_provider_input_stability
  material_prop_scale_contact_state_continuity
].freeze

GRAPH_PIXEL_CRITERIA = %w[
  visible_scene_job_and_neighbor_delta
  identity_and_character_visual
  scene_visual_package_pixels
  still_composition_camera_depth_crop
  motion_pose_action_anchor
  prop_interaction_pixels
  continuity_and_generation_artifact_stability
].freeze

def resolve_pointer_value(document, pointer, label, errors)
  return document if pointer.to_s == "/"

  value = document
  pointer.to_s.split("/")[1..].to_a.each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    value = if value.is_a?(Array) && token.match?(/\A(?:0|[1-9]\d*)\z/)
              value.fetch(token.to_i)
            elsif value.is_a?(Hash)
              value.fetch(token)
            else
              raise KeyError, token
            end
  end
  value
rescue KeyError, IndexError
  errors << "#{label} JSON pointer is missing or invalid"
  nil
end

def graph_delegated_contracts(close, root, errors)
  refs = Array(close["department_dispatches"])
  contracts = refs.each_with_index.map do |ref, index|
    path, document = bound_source(ref, "department_dispatches[#{index}]", root, errors)
    next unless path && document

    value = resolve_pointer_value(document, ref.to_h["json_pointer"], "department_dispatches[#{index}]", errors)
    {"path" => path, "dispatch" => value, "ref" => ref}
  end.compact
  graph_count = contracts.count do |contract|
    dispatch = contract["dispatch"]
    dispatch.is_a?(Hash) && dispatch["schema_version"].to_s == "idol-graph-department-dispatch.v1" &&
      dispatch["artifact_type"].to_s == "graph_department_dispatch"
  end
  if graph_count.positive? && graph_count != refs.length
    errors << "delegated pixel close cannot mix Graph and legacy Department Dispatch authoring"
  end
  if graph_count.positive?
    contracts.each_with_index do |contract, index|
      dispatch = contract["dispatch"]
      next unless dispatch.is_a?(Hash) && dispatch["schema_version"].to_s == "idol-graph-department-dispatch.v1" &&
                  dispatch["artifact_type"].to_s == "graph_department_dispatch"

      declared = contract.fetch("ref").to_h["value_sha256"].to_s
      errors << "department_dispatches[#{index}] value SHA-256 is stale" unless declared == structured_value_sha256(dispatch)
    end
  end
  graph_count == refs.length && !refs.empty? ? contracts : nil
end

def validate_graph_delegated_judgments(close, reviews, contracts, root, errors)
  by_section = {}
  contracts.each_with_index do |contract, index|
    path = contract.fetch("path")
    dispatch = contract.fetch("dispatch")
    run_validator(GRAPH_DISPATCH_VALIDATOR, path, root, "Graph department_dispatches[#{index}]", errors)
    errors << "Graph delegated dispatch must be reviewed" unless dispatch["lifecycle_state"].to_s == "reviewed"
    errors << "Graph delegated dispatch must use pixel_02b" unless dispatch["judgment_profile_id"].to_s == "pixel_02b"
    errors << "Graph delegated dispatch cannot co-author contextual_grade_vector" if dispatch.key?("contextual_grade_vector")
    judgment_path, judgment = bound_source(dispatch["contextual_judgment"], "Graph department_dispatches[#{index}] contextual judgment", root, errors)
    next unless judgment_path && judgment

    run_validator(GRAPH_JUDGMENT_VALIDATOR, judgment_path, root, "Graph department_dispatches[#{index}] contextual judgment", errors)
    errors << "Graph delegated judgment must select Director review" unless judgment["decision"].to_s == "eligible_for_director_review" && judgment["next_edge"].to_s == "director_review"
    errors << "Graph delegated judgment status must be ready_for_director_review" unless judgment["status"].to_s == "ready_for_director_review"
    unless judgment.dig("execution_binding", "assignment_id").to_s == dispatch["dispatch_id"].to_s
      errors << "Graph delegated output judged_by relation differs from Dispatch"
    end
    unless judgment.dig("execution_binding", "goal_id").to_s == dispatch.dig("goal_evidence", "native_goal_id").to_s &&
           judgment.dig("execution_binding", "goal_terminal_event_sha256").to_s == dispatch.dig("goal_evidence", "goal_terminal_event_sha256").to_s
      errors << "Graph delegated judgment Goal relation differs from persisted terminal event"
    end
    section_ids = Array(dispatch["section_ids"]).map(&:to_s)
    errors << "Graph delegated dispatch must bind exactly one section" unless section_ids.length == 1
    section_id = section_ids.first
    errors << "Graph delegated dispatch section is duplicated" if by_section.key?(section_id)
    by_section[section_id] = judgment
    expected_images = reviews.select { |row| row["section_id"].to_s == section_id }.map do |row|
      {"path" => row.fetch("image_path"), "sha256" => row.fetch("image_sha256")}
    end
    begin
      IdolGraphCriterionEvidenceContract.verify!(root: root, document: judgment, expected_cut_images: expected_images)
    rescue IdolGraphCriterionEvidenceContract::ContractError => e
      errors << "#{section_id} criterion evidence: #{e.message}"
    end
  end

  reviews.each do |review|
    packet_id = review["packet_id"].to_s
    if review.key?("generated_production_cut_vector")
      errors << "#{packet_id} Graph delegated close forbids legacy generated_production_cut_vector co-authoring"
    end
    judgment = by_section[review["section_id"].to_s]
    unless judgment
      errors << "#{packet_id} has no section-bound Graph contextual judgment"
      next
    end
    sources = Array(judgment["source_artifacts"])
    unless sources.any? { |source| source.to_h["path"].to_s == review["image_path"].to_s && source.to_h["sha256"].to_s == review["image_sha256"].to_s }
      errors << "#{packet_id} output is not the exact judged_by source artifact"
    end
    criteria = Array(judgment["criteria"])
    ids = criteria.map { |row| row.to_h["criterion_id"].to_s }
    errors << "#{packet_id} Graph pixel criteria must exact-cover pixel_02b" unless ids == GRAPH_PIXEL_CRITERIA
    criteria.each do |criterion|
      id = criterion.to_h["criterion_id"].to_s
      result = criterion.to_h["result"]
      next unless close["decision"] == "pass"

      if %w[scene_visual_package_pixels still_composition_camera_depth_crop motion_pose_action_anchor].include?(id)
        errors << "#{packet_id} #{id} must equal grade 4" unless result == 4
      elsif result.is_a?(Integer)
        errors << "#{packet_id} #{id} must be at least grade 3" if result < 3
      end
    end
  end
end

def validate_legacy_delegated_vectors(close, reviews, errors)
  reviews.each do |review|
    packet_id = review["packet_id"].to_s
    vector = review["generated_production_cut_vector"]
    unless vector.is_a?(Hash)
      errors << "#{packet_id} legacy-pinned delegated pixel close requires parse-only generated_production_cut_vector"
      next
    end
    criteria = Array(vector["criteria"])
    ids = criteria.map { |row| row.to_h["criterion_id"].to_s }
    errors << "#{packet_id} legacy delegated pixel criteria must exact-cover the seven registered criteria" unless ids == LEGACY_DELEGATED_PIXEL_CRITERIA
    criteria.each do |criterion|
      next unless criterion.is_a?(Hash)
      id = criterion["criterion_id"].to_s
      result = criterion["result"]
      if close["decision"] == "pass"
        if id == "scene_visual_package"
          errors << "#{packet_id} still-camera/composition close must equal 4" unless result == 4
        elsif id == "action_pose_motion_anchor"
          errors << "#{packet_id} motion-anchor readability must equal 4" unless result == 4
        elsif result.is_a?(Integer)
          errors << "#{packet_id} #{id} must be at least 3" if result < 3
        elsif id == "character_identity_visual_continuity"
          errors << "#{packet_id} character criterion has invalid N/A result" unless result == "not_applicable_member_absent"
        elsif id == "material_prop_scale_contact_state_continuity"
          errors << "#{packet_id} prop criterion has invalid N/A result" unless result == "not_applicable_no_material_prop"
        else
          errors << "#{packet_id} #{id} cannot be N/A"
        end
      end
    end
  end
end

def validate_delegated_pixel_close(document, reviews, root, errors)
  close = document["delegated_pixel_close"]
  return unless close.is_a?(Hash)

  errors << "delegated pixel close mode must be g2_delegated_cdd" unless close["mode"] == "g2_delegated_cdd"
  errors << "delegated pixel close forbids fallback" unless close["automatic_fallback"] == "none"
  expected_sections = reviews.map { |row| row["section_id"].to_s }.uniq
  errors << "delegated pixel close section scope differs from reviewed pixels" unless Array(close["section_ids"]).map(&:to_s) == expected_sections

  packet_bindings = Array(close["pixel_review_packet_bindings"])
  expected_packet_ids = reviews.map { |row| row["packet_id"].to_s }
  errors << "delegated pixel close packet bindings must exact-cover review rows in order" unless packet_bindings.map { |row| row.to_h["packet_id"].to_s } == expected_packet_ids
  packet_bindings.zip(reviews).each do |binding, review|
    next unless binding.is_a?(Hash) && review.is_a?(Hash)
    unless binding["review_value_sha256"].to_s == structured_value_sha256(review)
      errors << "#{review['packet_id']} delegated pixel review value SHA-256 is stale"
    end
  end

  graph_contracts = graph_delegated_contracts(close, root, errors)
  if graph_contracts
    validate_graph_delegated_judgments(close, reviews, graph_contracts, root, errors)
  else
    validate_legacy_delegated_vectors(close, reviews, errors)
    vector_drift = reviews.any? { |review| review.dig("generated_production_cut_vector", "material_drift") == true }
    vector_target_violation = reviews.any? { |review| review.dig("generated_production_cut_vector", "target_lock_violation") == true }
    vector_message_violation = reviews.any? { |review| review.dig("generated_production_cut_vector", "message_lock_violation") == true }
    errors << "delegated pixel close material-drift summary differs from packet vectors" unless close["material_drift"] == vector_drift
    errors << "delegated pixel close target-lock summary differs from packet vectors" unless close["target_lock_violation"] == vector_target_violation
    errors << "delegated pixel close message-lock summary differs from packet vectors" unless close["message_lock_violation"] == vector_message_violation
  end

  if close["decision"] == "pass"
    errors << "delegated pass cannot carry material drift" unless close["material_drift"] == false
    errors << "delegated pass cannot violate the target lock" unless close["target_lock_violation"] == false
    errors << "delegated pass cannot violate the message lock" unless close["message_lock_violation"] == false
  end
  if document["status"] == "passed"
    errors << "passed delegated review requires CDD pass" unless close["decision"] == "pass"
  end
end

def review_content_projection(row, source_hash_field)
  projection = Marshal.load(Marshal.dump(row))
  projection.delete(source_hash_field)
  projection.delete("review_lineage")
  projection
end

def load_prior_review_row(
  root:,
  current_review_path:,
  lineage:,
  collection:,
  id_field:,
  id:,
  row_hash_field:,
  label:
)
  errors = []
  source_ref = lineage.to_h["source_review"]
  unless source_ref.is_a?(Hash)
    return [nil, nil, ["#{label}: carried review requires source_review"]]
  end
  source_path = resolve_path(source_ref["path"], root)
  if source_path == current_review_path
    return [nil, nil, ["#{label}: carried review cannot point to itself"]]
  end
  unless inside?(source_path, root) && source_path.file?
    return [nil, nil, ["#{label}: carried source review is missing or outside the repository"]]
  end
  actual_sha = Digest::SHA256.file(source_path).hexdigest
  errors << "#{label}: carried source review SHA-256 is stale" unless source_ref["sha256"].to_s == actual_sha
  prior = load_mapping(source_path)
  prior_row = Array(prior[collection]).find do |candidate|
    candidate.is_a?(Hash) && candidate[id_field].to_s == id.to_s
  end
  unless prior_row
    return [prior, nil, errors << "#{label}: carried source review has no matching row"]
  end
  unless lineage[row_hash_field].to_s == structured_value_sha256(prior_row)
    errors << "#{label}: carried review row value SHA-256 is stale"
  end
  [prior, prior_row, errors]
rescue JSON::ParserError, Psych::Exception, TypeError => e
  [nil, nil, errors << "#{label}: cannot read carried source review: #{e.message}"]
end

def run_validator(script, path, root, label, errors)
  stdout, stderr, status = Open3.capture3("ruby", script.to_s, "--root", root.to_s, path.to_s, chdir: ROOT.to_s)
  errors << "#{label} failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def validate_passed_upscale(image_path, root, packet_id, errors)
  receipt_path = Pathname.new("#{image_path}.upscale.json")
  unless inside?(receipt_path, root) && receipt_path.file?
    errors << "#{packet_id} passed image is missing its local upscale receipt"
    return nil
  end
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    UPSCALE_VALIDATOR.to_s,
    "--root",
    root.to_s,
    "--source",
    image_path.to_s,
    "--purpose",
    "post_02b_passed_image",
    "--minimum-long-edge",
    "3840",
    "--json",
    receipt_path.to_s,
    chdir: ROOT.to_s
  )
  unless status.success?
    errors << "#{packet_id} local upscale receipt failed validation: #{[stderr, stdout].join(' ').strip}"
    return nil
  end
  receipt = JSON.parse(receipt_path.read)
  Array(receipt["operations"]).find do |operation|
    resolve_path(operation.dig("source", "path"), root) == image_path
  end
rescue JSON::ParserError, TypeError => e
  errors << "#{packet_id} local upscale receipt cannot be read: #{e.message}"
  nil
end

root = options[:root].expand_path.cleanpath
artifact = resolve_path(artifact_arg, root)
errors = []
unless inside?(artifact, root) && artifact.file?
  errors << "generated Branch-Cut review is missing or outside the repository"
end

document = {}
if errors.empty?
  begin
    document = load_mapping(artifact)
  rescue JSON::ParserError, Psych::Exception, TypeError => e
    errors << "cannot parse generated Branch-Cut review: #{e.message}"
  end
end

if artifact.file?
  stdout, stderr, status = Open3.capture3(PYTHON.to_s, SCHEMA_VALIDATOR.to_s, SCHEMA.to_s, artifact.to_s, chdir: ROOT.to_s)
  errors << "JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

if document.any?
  unless document["schema_version"].to_s == "idol_generated_branch_cut_review.v4"
    errors << "only idol_generated_branch_cut_review.v4 is active"
  end
  storyboard_path, storyboard = bound_source(document["source_02a"], "source_02a", root, errors)
  prompt_path, prompts = bound_source(document["source_02b"], "source_02b", root, errors)
  run_validator(STORYBOARD_VALIDATOR, storyboard_path, root, "source 02A", errors) if storyboard_path
  if prompt_path
    stdout, stderr, status = Open3.capture3(
      "ruby",
      PROMPT_VALIDATOR.to_s,
      "--mode",
      "authoring",
      "--run-root",
      prompt_path.dirname.to_s,
      prompt_path.to_s,
      chdir: ROOT.to_s
    )
    errors << "source 02B failed active validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
  end

  if storyboard && prompts
    errors << "content_id differs from 02A" unless document["content_id"].to_s == storyboard["content_id"].to_s
    errors << "content_id differs from 02B" unless document["content_id"].to_s == prompts["content_id"].to_s
    errors << "generated review requires canonical approved 02B" unless prompts["status"] == "approved"
    packets = Array(prompts["prompt_packets"])
    packet_by_id = packets.to_h { |row| [row["packet_id"].to_s, row] }
    reviews = Array(document["branch_cut_reviews"])
    section_reviews = Array(document["section_reviews"])
    local_review_lineage_active =
      (reviews + section_reviews).any? { |row| row.is_a?(Hash) && row["review_lineage"].is_a?(Hash) }
    review_ids = reviews.map { |row| row["packet_id"].to_s }
    errors << "Branch-Cut review packet ids must be unique" unless review_ids.uniq.length == review_ids.length
    if document["status"] == "passed"
      errors << "passed review must exact-cover all approved 02B packets in order" unless review_ids == packets.map { |row| row["packet_id"].to_s }
    end
    reviews.each do |review|
      packet_id = review["packet_id"].to_s
      packet = packet_by_id[packet_id]
      if packet.nil?
        errors << "#{packet_id} is not present in source 02B"
        next
      end
      expected_packet_sha = structured_value_sha256(packet)
      declared_packet_sha = review["source_02b_branch_cut_packet_value_sha256"].to_s
      if local_review_lineage_active
        errors << "#{packet_id} local review lineage requires source_02b_branch_cut_packet_value_sha256" if declared_packet_sha.empty?
        errors << "#{packet_id} local review lineage requires review_lineage" unless review["review_lineage"].is_a?(Hash)
      end
      if !declared_packet_sha.empty? && declared_packet_sha != expected_packet_sha
        errors << "#{packet_id} source 02B packet value SHA-256 is stale"
      end
      lineage_mode = review.dig("review_lineage", "mode").to_s
      if lineage_mode == "carried_forward_unchanged_packet"
        errors << "#{packet_id} carried review requires source_02b_branch_cut_packet_value_sha256" if declared_packet_sha.empty?
        prior_review, prior_row, carry_errors = load_prior_review_row(
          root: root,
          current_review_path: artifact,
          lineage: review["review_lineage"],
          collection: "branch_cut_reviews",
          id_field: "packet_id",
          id: packet_id,
          row_hash_field: "source_branch_cut_review_value_sha256",
          label: packet_id
        )
        errors.concat(carry_errors)
        if prior_row
          errors << "#{packet_id} carried source review is not passed" unless prior_review["status"].to_s == "passed"
          errors << "#{packet_id} prior review is not passed" unless prior_row["decision"].to_s == "pass"
          unless prior_row["source_02b_branch_cut_packet_value_sha256"].to_s == expected_packet_sha
            errors << "#{packet_id} prior review does not bind the unchanged current 02B packet"
          end
          unless canonical_json_value(review_content_projection(review, "source_02b_branch_cut_packet_value_sha256")) ==
                 canonical_json_value(review_content_projection(prior_row, "source_02b_branch_cut_packet_value_sha256"))
            errors << "#{packet_id} carried review content differs from the bound prior row"
          end
        end
      elsif !lineage_mode.empty? && lineage_mode != "current_source_review"
        errors << "#{packet_id} review_lineage mode is invalid"
      end
      errors << "#{packet_id} Branch Cut differs from 02B" unless review["branch_cut_id"].to_s == packet["branch_cut_id"].to_s
      errors << "#{packet_id} section differs from 02B" unless review["section_id"].to_s == packet["execution_section_id"].to_s
      errors << "#{packet_id} Core Cut differs from 02B" unless review["core_cut_id"].to_s == packet["core_cut_id"].to_s
      image_path = resolve_path(review["image_path"], root)
      unless inside?(image_path, root) && image_path.file?
        errors << "#{packet_id} reviewed image is missing or outside the repository"
        next
      end
      errors << "#{packet_id} reviewed image SHA-256 is stale" unless Digest::SHA256.file(image_path).hexdigest == review["image_sha256"].to_s
      if review["decision"].to_s == "pass"
        upscale = validate_passed_upscale(image_path, root, packet_id, errors)
        if upscale
          source_dimensions = upscale.dig("source", "pixel_dimensions").to_h
          errors << "#{packet_id} reviewed pixel dimensions are stale" unless review["pixel_dimensions"].to_h == source_dimensions
        end
      end
    end

    section_ids = section_reviews.map { |row| row["section_id"].to_s }
    errors << "section review ids must be unique" unless section_ids.uniq.length == section_ids.length
    section_reviews.each do |section|
      section_id = section["section_id"].to_s
      expected = reviews.select { |row| row["section_id"].to_s == section_id }.map { |row| row["packet_id"].to_s }
      errors << "#{section['section_id']} section review packet coverage differs" unless Array(section["packet_ids"]).map(&:to_s) == expected
      current_section_packets = packets.select { |packet| packet["execution_section_id"].to_s == section_id }
      expected_packet_set_sha = structured_value_sha256(current_section_packets)
      declared_packet_set_sha = section["source_section_packet_set_sha256"].to_s
      if local_review_lineage_active
        errors << "#{section_id} local review lineage requires source_section_packet_set_sha256" if declared_packet_set_sha.empty?
        errors << "#{section_id} local review lineage requires review_lineage" unless section["review_lineage"].is_a?(Hash)
      end
      if !declared_packet_set_sha.empty? && declared_packet_set_sha != expected_packet_set_sha
        errors << "#{section_id} source section packet-set SHA-256 is stale"
      end
      lineage_mode = section.dig("review_lineage", "mode").to_s
      if lineage_mode == "carried_forward_unchanged_section"
        errors << "#{section_id} carried section review requires source_section_packet_set_sha256" if declared_packet_set_sha.empty?
        prior_review, prior_row, carry_errors = load_prior_review_row(
          root: root,
          current_review_path: artifact,
          lineage: section["review_lineage"],
          collection: "section_reviews",
          id_field: "section_id",
          id: section_id,
          row_hash_field: "source_section_review_value_sha256",
          label: section_id
        )
        errors.concat(carry_errors)
        if prior_row
          errors << "#{section_id} carried source review is not passed" unless prior_review["status"].to_s == "passed"
          errors << "#{section_id} prior section review is not passed" unless prior_row["decision"].to_s == "pass"
          unless prior_row["source_section_packet_set_sha256"].to_s == expected_packet_set_sha
            errors << "#{section_id} prior review does not bind the unchanged current packet set"
          end
          unless canonical_json_value(review_content_projection(section, "source_section_packet_set_sha256")) ==
                 canonical_json_value(review_content_projection(prior_row, "source_section_packet_set_sha256"))
            errors << "#{section_id} carried section review content differs from the bound prior row"
          end
        end
      elsif !lineage_mode.empty? && lineage_mode != "current_source_review"
        errors << "#{section_id} review_lineage mode is invalid"
      end
      next unless document["status"] == "passed"

      expected_images = IdolStoryboardCollectedAngleContract.images_for_section(
        IdolStoryboardCollectedAngleContract.storyboard_production_images(storyboard),
        section_id
      )
      reviews.each do |row|
        next unless row["section_id"].to_s == section_id

        expected_images.each do |image|
          next unless image["cut_id"].to_s == row["branch_cut_id"].to_s

          image["image_sha256"] = row["image_sha256"].to_s
        end
      end
      errors.concat(
        IdolStoryboardCollectedAngleContract.validate_review(
          review: section["collected_image_camera_angle_pixel_review"],
          expected_images: expected_images,
          document: storyboard,
          root: root,
          parent_verdict: section["decision"],
          label: "#{section_id} collected_image_camera_angle_pixel_review",
          require_generated_pixels: true
        )
      )
    end
    validate_delegated_pixel_close(document, reviews, root, errors)
  end
end

errors = errors.uniq
errors = errors.first(options[:max_errors]) if options[:max_errors].to_i.positive?
result = {"valid" => errors.empty?, "schema_version" => document["schema_version"], "errors" => errors}
if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: generated Branch-Cut review binds passed pixels and validated local upscales to exact Core-Cut, Branch-Cut, and 02B truth"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
