#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"
require_relative "lib/idol_generated_review_post_pass"
require_relative "lib/idol_graph_criterion_evidence_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
REVIEW_SCHEMA = ROOT.join("schemas", "review.schema.json")
APPROVAL_SCHEMA = ROOT.join("schemas", "image-generation-section-approval.schema.json")
REQUEST_SCHEMA = ROOT.join("schemas", "image-generation-request.schema.json")
RECEIPT_SCHEMA = ROOT.join("schemas", "image-generation-execution-receipt.schema.json")
COHORT_VALIDATOR = ROOT.join("scripts", "validate_graph_section_cohort_map.rb")
GRAPH_DISPATCH_VALIDATOR = ROOT.join("scripts", "validate_graph_director_lineage.rb")
GRAPH_JUDGMENT_VALIDATOR = ROOT.join("scripts", "validate_graph_contextual_judgment.rb")
LOCAL_UPSCALER = ROOT.join("scripts", "idol_local_image_upscale.py")
GENERATED_REVIEW_VALIDATOR = ROOT.join("scripts", "validate_generated_branch_cut_review.rb")
AUDIO_PLACEMENT_VALIDATOR = ROOT.join("scripts", "validate_audio_branch_cut_placement.rb")

class AuthorityRequest < StandardError; end
class MechanicalHold < StandardError; end

GRAPH_PIXEL_CRITERIA = %w[
  visible_scene_job_and_neighbor_delta
  identity_and_character_visual
  scene_visual_package_pixels
  still_composition_camera_depth_crop
  motion_pose_action_anchor
  prop_interaction_pixels
  continuity_and_generation_artifact_stability
].freeze

def canonical(value)
  case value
  when Hash
    value.keys.map(&:to_s).sort.each_with_object({}) { |key, result| result[key] = canonical(value[key]) }
  when Array
    value.map { |item| canonical(item) }
  else
    value
  end
end

def value_sha256(value)
  Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
end

def load_mapping(path, label)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [], aliases: true)
          end
  raise AuthorityRequest, "#{label} must be a mapping" unless value.is_a?(Hash)
  value
rescue JSON::ParserError, Psych::Exception => e
  raise AuthorityRequest, "cannot parse #{label}: #{e.message}"
end

def root_path(raw, root, must_exist: true)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(root).to_s
  raise AuthorityRequest, "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  raise AuthorityRequest, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise AuthorityRequest, "path escapes repository root: #{raw}"
end

def inside?(path, parent)
  relative = path.relative_path_from(parent).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

def resolve_pointer(document, pointer, label)
  return document if pointer == "/"
  value = document
  pointer.to_s.split("/")[1..].to_a.each do |raw_token|
    token = raw_token.gsub("~1", "/").gsub("~0", "~")
    value = if value.is_a?(Array)
      raise AuthorityRequest, "#{label} pointer token is not an array index: #{token}" unless token.match?(/\A(?:0|[1-9]\d*)\z/)
      value.fetch(token.to_i)
    elsif value.is_a?(Hash)
      value.fetch(token) { raise AuthorityRequest, "#{label} pointer key is missing: #{token}" }
    else
      raise AuthorityRequest, "#{label} pointer traverses a scalar"
    end
  end
  value
rescue IndexError
  raise AuthorityRequest, "#{label} pointer array index is missing"
end

def verified_artifact_ref(ref, root, run_path, label)
  raise AuthorityRequest, "#{label} must be a path/SHA-256 binding" unless ref.is_a?(Hash)
  path, relative = root_path(ref.fetch("path"), root)
  raise AuthorityRequest, "#{label} must stay inside the owning run: #{relative}" unless inside?(path, run_path)
  actual = Digest::SHA256.file(path).hexdigest
  raise AuthorityRequest, "#{label} SHA-256 is stale: #{relative}" unless ref.fetch("sha256").to_s == actual
  [path, relative, load_mapping(path, label)]
rescue KeyError => e
  raise AuthorityRequest, "#{label} is missing #{e.key}"
end

def verified_value_ref(ref, root, run_path, label)
  path, relative, document = verified_artifact_ref(ref, root, run_path, label)
  pointer = ref.fetch("json_pointer")
  value = resolve_pointer(document, pointer, label)
  unless ref.fetch("value_sha256").to_s == value_sha256(value)
    raise AuthorityRequest, "#{label} value SHA-256 is stale at #{pointer}"
  end
  [path, relative, document, value]
rescue KeyError => e
  raise AuthorityRequest, "#{label} is missing #{e.key}"
end

def validate_schema!(schema, path, root, label)
  stdout, stderr, status = Open3.capture3(
    root.join("scripts", "idol-video-python").to_s,
    root.join("scripts", "validate_json_schema.py").to_s,
    schema.to_s,
    path.to_s,
    chdir: root.to_s
  )
  return if status.success?
  raise AuthorityRequest, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}"
end

def validate_contract!(script, path, root, label)
  stdout, stderr, status = Open3.capture3("ruby", script.to_s, "--root", root.to_s, path.to_s, chdir: root.to_s)
  return if status.success?
  raise AuthorityRequest, "#{label} failed active validation: #{[stderr, stdout].join(' ').strip}"
end

def exact_equal!(actual, expected, label)
  raise AuthorityRequest, "#{label} differs from the G2 authority envelope" unless actual == expected
end

def preserve_once(path, bytes)
  path.dirname.mkpath
  sha = Digest::SHA256.hexdigest(bytes)
  Tempfile.create(["idol-g2-pixel-close", path.extname], path.dirname.to_s) do |temp|
    temp.binmode
    temp.write(bytes)
    temp.flush
    temp.fsync
    begin
      File.link(temp.path, path.to_s)
      return false
    rescue Errno::EEXIST
      unless path.file? && Digest::SHA256.file(path).hexdigest == sha
        raise MechanicalHold, "existing delegated close intake conflicts with the exact validated bytes"
      end
      return true
    end
  end
end

options = {root: ROOT, write: false, validate_only: false}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_g2_delegated_pixel_close_intake.rb REVIEW.yaml --write [--output PATH]"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--write") { options[:write] = true }
  parser.on("--validate-only") { options[:validate_only] = true }
end.parse!

begin
  root = options[:root].expand_path.cleanpath
  review_arg = ARGV.shift
  raise AuthorityRequest, "generated Branch-Cut review path is required" if review_arg.to_s.empty?
  raise AuthorityRequest, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  unless options[:write] || options[:validate_only]
    raise AuthorityRequest, "--write or --validate-only is required for delegated pixel close"
  end
  review_path, review_relative = root_path(review_arg, root)
  run_path = review_path
  run_path = run_path.parent until run_path == root || run_path.basename.to_s == "review"
  raise AuthorityRequest, "review must live inside RUN/review" if run_path == root
  run_path = run_path.parent

  validate_schema!(root.join("schemas", "review.schema.json"), review_path, root, "generated Branch-Cut review")
  review = load_mapping(review_path, "generated Branch-Cut review")
  raise AuthorityRequest, "delegated close requires review status cdd_review" unless review["status"] == "cdd_review"
  close = review["delegated_pixel_close"]
  raise AuthorityRequest, "delegated_pixel_close is required" unless close.is_a?(Hash)
  unless close["mode"] == "g2_delegated_cdd" && close["automatic_fallback"] == "none"
    raise AuthorityRequest, "delegated close must use g2_delegated_cdd with no fallback"
  end
  if close["decision"] != "pass"
    status = close["decision"] == "hold" ? "hold" : "authority_request"
    puts JSON.pretty_generate(
      "status" => status,
      "review" => review_relative,
      "reasons" => Array(close["authority_request_reasons"]),
      "automatic_fallback" => "none",
      "review_mutated" => false
    )
    exit 2
  end

  g2_path, g2_relative, _g2_document, envelope = verified_value_ref(close["g2_envelope"], root, run_path, "Founder G2 envelope")
  raise AuthorityRequest, "G2 envelope value must be a mapping" unless envelope.is_a?(Hash)
  exact_equal!(envelope["gate_id"], "G2", "gate_id")
  exact_equal!(envelope["projection_kind"], "draft_keyframe", "projection_kind")
  exact_equal!(envelope["decision"], "PASS", "G2 decision")
  exact_equal!(envelope["automatic_fallback"], "none", "automatic fallback")

  review_rows = Array(review["branch_cut_reviews"])
  legacy_vector_row = review_rows.find { |row| row.is_a?(Hash) && row.key?("generated_production_cut_vector") }
  if legacy_vector_row
    raise AuthorityRequest, "#{legacy_vector_row['packet_id']} Graph delegated close forbids legacy generated_production_cut_vector co-authoring"
  end
  unless Array(review["section_reviews"]).all? { |row| row.is_a?(Hash) && row["decision"] == "pass" } &&
         review_rows.all? { |row| row.is_a?(Hash) && row["decision"] == "pass" }
    raise AuthorityRequest, "delegated CDD pass requires every section and pixel review decision to pass"
  end
  packet_ids = review_rows.map { |row| row["packet_id"].to_s }
  section_ids = review_rows.map { |row| row["section_id"].to_s }.uniq
  cut_ids = review_rows.map { |row| row["branch_cut_id"].to_s }
  source_02b_path, _source_02b_relative, source_02b = verified_artifact_ref(review["source_02b"], root, run_path, "review source 02B")
  source_02b_sha256 = Digest::SHA256.file(source_02b_path).hexdigest
  exact_equal!(close["section_ids"], section_ids, "delegated section scope")
  exact_equal!(envelope["section_ids"], section_ids, "G2 section scope")
  exact_equal!(envelope["cut_ids"], cut_ids, "G2 Cut scope")
  exact_equal!(envelope["section_cohort_id"], close["section_cohort_id"], "G2 cohort")

  cohort_path, _cohort_relative, cohort_document, cohort = verified_value_ref(close["cohort_map"], root, run_path, "section cohort map")
  validate_contract!(root.join("scripts", "validate_graph_section_cohort_map.rb"), cohort_path, root, "section cohort map")
  raise AuthorityRequest, "cohort pointer must select a cohort mapping" unless cohort.is_a?(Hash)
  exact_equal!(cohort["section_cohort_id"], close["section_cohort_id"], "cohort id")
  exact_equal!(cohort["section_ids"], section_ids, "cohort section scope")
  exact_equal!(cohort["production_lane_id"], close["cdd_lane_id"], "V-Ci lane")
  exact_equal!(cohort.dig("cdd_reviewer", "owner"), close["cdd_owner"], "cohort CDD owner")
  exact_equal!(cohort.dig("cdd_reviewer", "lane_id"), close["cdd_lane_id"], "cohort CDD lane")
  carry = Array(cohort_document["p3_to_v_carry"]).find { |row| row["section_cohort_id"] == close["section_cohort_id"] }
  raise AuthorityRequest, "P3-Ci to V-Ci carry row is missing" unless carry.is_a?(Hash)
  exact_equal!(carry["planning_lane_id"], cohort["planning_lane_id"], "P3 lane carry")
  exact_equal!(carry["production_lane_id"], close["cdd_lane_id"], "V-Ci lane carry")
  exact_equal!(carry["exact_section_ids"], section_ids, "P3-to-V section carry")
  exact_equal!(carry["exact_carry"], true, "P3-to-V exact carry")

  dispatch_contracts = Array(close["department_dispatches"]).map.with_index do |ref, index|
    path, _relative, _document, dispatch = verified_value_ref(ref, root, run_path, "section writer dispatch #{index + 1}")
    validate_schema!(root.join("schemas", "graph-department-dispatch.schema.json"), path, root, "section writer dispatch #{index + 1}")
    validate_contract!(GRAPH_DISPATCH_VALIDATOR, path, root, "section writer dispatch #{index + 1}")
    raise AuthorityRequest, "section writer dispatch pointer must select a mapping" unless dispatch.is_a?(Hash)
    judgment_ref = dispatch["contextual_judgment"]
    judgment_path, _judgment_relative, judgment = verified_artifact_ref(
      judgment_ref,
      root,
      run_path,
      "section writer dispatch #{index + 1} contextual judgment"
    )
    validate_contract!(GRAPH_JUDGMENT_VALIDATOR, judgment_path, root, "section writer dispatch #{index + 1} contextual judgment")
    {"dispatch" => dispatch, "judgment" => judgment}
  end
  dispatch_rows = dispatch_contracts.map { |contract| contract.fetch("dispatch") }
  dispatched_sections = dispatch_rows.flat_map { |row| Array(row["section_ids"]) }
  exact_equal!(dispatched_sections, section_ids, "section writer dispatch coverage")
  expected_writers = Array(cohort["section_output_writers"]).to_h { |row| [row["section_id"], row["owner"]] }
  dispatch_rows.each do |dispatch|
    dispatch_sections = Array(dispatch["section_ids"])
    raise AuthorityRequest, "each section writer dispatch must own exactly one section" unless dispatch_sections.length == 1
    section_id = dispatch_sections.first
    exact_equal!(dispatch["section_cohort_id"], close["section_cohort_id"], "dispatch cohort")
    exact_equal!(dispatch["lane_id"], close["cdd_lane_id"], "dispatch V-Ci lane")
    exact_equal!(dispatch["logical_role"], "section_image_motion_worker", "dispatch logical role")
    exact_equal!(dispatch.dig("output_writer", "role"), "section_image_motion_worker", "dispatch writer role")
    exact_equal!(dispatch.dig("output_writer", "owner"), expected_writers.fetch(section_id), "dispatch writer owner")
    exact_equal!(dispatch.dig("reviewer", "owner"), close["cdd_owner"], "dispatch CDD reviewer")
    exact_equal!(dispatch.dig("reviewer", "lane_id"), close["cdd_lane_id"], "dispatch CDD lane")
    exact_equal!(dispatch["review_checkpoint"], "02b_pixel", "dispatch review checkpoint")
    exact_equal!(dispatch["judgment_profile_id"], "pixel_02b", "dispatch judgment profile")
    exact_equal!(dispatch["lifecycle_state"], "reviewed", "reviewed Graph dispatch state")
    exact_equal!(dispatch["lifecycle_from"], "returned", "reviewed Graph dispatch predecessor state")
    exact_equal!(dispatch["legal_next"], ["hold"], "reviewed Graph dispatch legal next")
    raise AuthorityRequest, "Graph delegated close forbids legacy contextual_grade_vector" if dispatch.key?("contextual_grade_vector")
  end

  graph_judgment_by_section = {}
  dispatch_contracts.each do |contract|
    dispatch = contract.fetch("dispatch")
    judgment = contract.fetch("judgment")
    section_id = Array(dispatch["section_ids"]).first.to_s
    raise AuthorityRequest, "duplicate Graph contextual judgment for #{section_id}" if graph_judgment_by_section.key?(section_id)
    exact_equal!(judgment["profile_id"], "pixel_02b", "#{section_id} contextual judgment profile")
    exact_equal!(judgment["decision"], "eligible_for_director_review", "#{section_id} contextual judgment decision")
    exact_equal!(judgment["next_edge"], "director_review", "#{section_id} contextual judgment typed next edge")
    exact_equal!(judgment["status"], "ready_for_director_review", "#{section_id} contextual judgment status")
    exact_equal!(judgment.dig("execution_binding", "assignment_id"), dispatch["dispatch_id"], "#{section_id} judged_by assignment relation")
    exact_equal!(judgment.dig("execution_binding", "goal_id"), dispatch.dig("goal_evidence", "native_goal_id"), "#{section_id} Goal relation")
    exact_equal!(judgment.dig("execution_binding", "goal_terminal_event_sha256"), dispatch.dig("goal_evidence", "goal_terminal_event_sha256"), "#{section_id} Goal terminal event relation")
    graph_judgment_by_section[section_id] = judgment
    expected_images = review_rows.select { |row| row["section_id"].to_s == section_id }.map do |row|
      {"path" => row.fetch("image_path"), "sha256" => row.fetch("image_sha256")}
    end
    begin
      IdolGraphCriterionEvidenceContract.verify!(root: root, document: judgment, expected_cut_images: expected_images)
    rescue IdolGraphCriterionEvidenceContract::ContractError => e
      raise AuthorityRequest, "#{section_id} criterion evidence: #{e.message}"
    end
  end

  approvals = Array(close["generation_approvals"]).map.with_index do |ref, index|
    path, _relative, document = verified_artifact_ref(ref, root, run_path, "generation approval #{index + 1}")
    validate_schema!(root.join("schemas", "image-generation-section-approval.schema.json"), path, root, "generation approval #{index + 1}")
    document
  end
  approval_packet_rows = approvals.flat_map { |approval| Array(approval["packets"]).map { |packet| [packet["packet_id"].to_s, [approval, packet]] } }
  raise AuthorityRequest, "generation approval packet ids must be unique" unless approval_packet_rows.map(&:first).uniq.length == approval_packet_rows.length
  approval_packets = approval_packet_rows.to_h
  exact_equal!(approval_packets.keys, packet_ids, "generation approval packet scope")

  request_rows = Array(close["image_generation_requests"]).map.with_index do |ref, index|
    path, relative, document = verified_artifact_ref(ref, root, run_path, "image generation request #{index + 1}")
    validate_schema!(root.join("schemas", "image-generation-request.schema.json"), path, root, "image generation request #{index + 1}")
    raise AuthorityRequest, "image generation request is not ready" unless document["status"] == "ready"
    [document["packet_id"].to_s, [path, relative, document]]
  end
  raise AuthorityRequest, "image generation request packet ids must be unique" unless request_rows.map(&:first).uniq.length == request_rows.length
  requests = request_rows.to_h
  exact_equal!(requests.keys, packet_ids, "image request packet scope")

  receipt_rows = Array(close["execution_receipts"]).map.with_index do |ref, index|
    path, _relative, document = verified_artifact_ref(ref, root, run_path, "execution receipt #{index + 1}")
    validate_schema!(root.join("schemas", "image-generation-execution-receipt.schema.json"), path, root, "execution receipt #{index + 1}")
    [document["packet_id"].to_s, [path, document]]
  end
  raise AuthorityRequest, "execution receipt packet ids must be unique" unless receipt_rows.map(&:first).uniq.length == receipt_rows.length
  receipts = receipt_rows.to_h
  exact_equal!(receipts.keys, packet_ids, "execution receipt packet scope")

  envelope_packets = Array(envelope["packet_authority"])
  exact_equal!(envelope_packets.map { |row| row["packet_id"].to_s }, packet_ids, "G2 packet authority scope")
  envelope_packet_by_id = envelope_packets.to_h { |row| [row["packet_id"].to_s, row] }
  provider = envelope["provider"]
  raise AuthorityRequest, "G2 provider authority must be a mapping" unless provider.is_a?(Hash)

  review_by_packet = review_rows.to_h { |row| [row["packet_id"].to_s, row] }
  packet_ids.each do |packet_id|
    request_path, request_relative, request = requests.fetch(packet_id)
    receipt_path, receipt = receipts.fetch(packet_id)
    approval, approval_packet = approval_packets.fetch(packet_id)
    authority = envelope_packet_by_id.fetch(packet_id)
    review_row = review_by_packet.fetch(packet_id)
    source_prompt_ref = request["source_prompt_packet"]
    source_prompt_path, = root_path(source_prompt_ref["path"], root)
    exact_equal!(source_prompt_path, source_02b_path, "#{packet_id} source prompt path")
    exact_equal!(source_prompt_ref["sha256"], source_02b_sha256, "#{packet_id} source prompt artifact hash")
    source_packet = resolve_pointer(source_02b, source_prompt_ref["json_pointer"], "#{packet_id} source prompt packet")
    exact_equal!(source_prompt_ref["value_sha256"], value_sha256(source_packet), "#{packet_id} source prompt value hash")
    exact_equal!(source_packet["packet_id"], packet_id, "#{packet_id} source prompt packet id")
    exact_equal!(source_packet.dig("rendered_five_lines", "full_prompt_sha256"), authority["prompt_sha256"], "#{packet_id} source prompt bytes")

    exact_equal!(request["section_id"], review_row["section_id"], "#{packet_id} request section")
    exact_equal!(request.dig("cut_pointer", "cut_id"), review_row["branch_cut_id"], "#{packet_id} request Cut")
    exact_equal!(authority["cut_id"], review_row["branch_cut_id"], "#{packet_id} G2 Cut")
    exact_equal!(authority["prompt_sha256"], request.dig("prompt", "full_prompt_sha256"), "#{packet_id} prompt")
    exact_equal!(authority["attachment_order_sha256"], request["attachment_order_sha256"], "#{packet_id} attachment order")
    exact_equal!(authority["approved_attachment_paths"], Array(request["attachments"]).map { |row| row["actual_path"] }, "#{packet_id} attachment paths")
    exact_equal!(authority["approved_attachment_sha256s"], Array(request["attachments"]).map { |row| row["sha256"] }, "#{packet_id} attachment hashes")
    exact_equal!(authority["expected_output_path"], request.dig("expected_output", "path"), "#{packet_id} output path")
    exact_equal!(authority["output_count"], request.dig("quality_contract", "output_count"), "#{packet_id} output count")

    exact_equal!(approval_packet["cut_id"], authority["cut_id"], "#{packet_id} approved Cut")
    exact_equal!(approval_packet["prompt_sha256"], authority["prompt_sha256"], "#{packet_id} approved prompt")
    exact_equal!(approval_packet["approved_attachment_paths"], authority["approved_attachment_paths"], "#{packet_id} approved attachment paths")
    exact_equal!(approval_packet["approved_attachment_sha256s"], authority["approved_attachment_sha256s"], "#{packet_id} approved attachment hashes")
    exact_equal!(approval_packet["expected_output_path"], authority["expected_output_path"], "#{packet_id} approved output path")
    exact_equal!(approval_packet["output_count"], authority["output_count"], "#{packet_id} approved output count")
    exact_equal!(approval["spend_envelope"], envelope["spend_envelope"], "#{packet_id} spend envelope")
    exact_equal!(approval["source_prompt_packets_sha256"], source_02b_sha256, "#{packet_id} approval source 02B")
    exact_equal!(request["production_scope_id"], approval["production_scope_id"], "#{packet_id} production scope")
    exact_equal!(request.dig("approval", "founder_generation_authority_id"), envelope["founder_generation_authority_id"], "#{packet_id} request Founder authority")
    exact_equal!(request.dig("execution", "founder_generation_authority_id"), envelope["founder_generation_authority_id"], "#{packet_id} execution Founder authority")
    exact_equal!(approval["founder_generation_authority_id"], envelope["founder_generation_authority_id"], "#{packet_id} approval Founder authority")

    %w[execution_adapter_id provider provider_profile_id provider_profile_sha256 provider_capability_snapshot_sha256].each do |field|
      exact_equal!(request.dig("execution", field), provider[field], "#{packet_id} provider #{field}")
      exact_equal!(approval[field], provider[field], "#{packet_id} approval provider #{field}")
      exact_equal!(receipt[field], provider[field], "#{packet_id} receipt provider #{field}")
    end
    exact_equal!(request.dig("execution", "automatic_fallback"), "none", "#{packet_id} request fallback")
    exact_equal!(receipt["automatic_fallback"], "none", "#{packet_id} receipt fallback")
    exact_equal!(receipt["request_path"], request_relative, "#{packet_id} receipt request path")
    exact_equal!(receipt["request_sha256"], Digest::SHA256.file(request_path).hexdigest, "#{packet_id} receipt request hash")
    exact_equal!(receipt["request_schema_version"], request["schema_version"], "#{packet_id} receipt request schema")
    exact_equal!(receipt["reference_role_plan_sha256"], value_sha256(request["reference_role_plan"]), "#{packet_id} receipt reference-role plan")
    exact_equal!(receipt["section_cohort_id"], close["section_cohort_id"], "#{packet_id} receipt cohort")
    approval_path, = root_path(receipt["approval_path"], root)
    approval_ref = close["generation_approvals"].find do |ref|
      candidate_path, = root_path(ref["path"], root)
      candidate_path == approval_path
    end
    raise AuthorityRequest, "#{packet_id} receipt approval is outside the bound approval set" unless approval_ref && approval_ref["sha256"] == receipt["approval_sha256"]
    exact_equal!(receipt["approval_sha256"], Digest::SHA256.file(approval_path).hexdigest, "#{packet_id} receipt approval hash")
    approval_source = request.dig("approval", "approval_source")
    raise AuthorityRequest, "#{packet_id} request approval source is missing" unless approval_source.is_a?(Hash)
    exact_equal!(root_path(approval_source["path"], root).first, approval_path, "#{packet_id} request approval path")
    exact_equal!(approval_source["sha256"], receipt["approval_sha256"], "#{packet_id} request approval hash")
    exact_equal!(receipt["prompt_sha256"], authority["prompt_sha256"], "#{packet_id} receipt prompt")
    exact_equal!(receipt["attachment_order_sha256"], authority["attachment_order_sha256"], "#{packet_id} receipt attachment order")
    exact_equal!(receipt["founder_generation_authority_id"], envelope["founder_generation_authority_id"], "#{packet_id} receipt Founder authority")
    exact_equal!(receipt["spend_envelope"], envelope["spend_envelope"], "#{packet_id} receipt spend envelope")
    exact_equal!(receipt["output_path"], review_row["image_path"], "#{packet_id} reviewed output path")
    exact_equal!(receipt["output_sha256"], review_row["image_sha256"], "#{packet_id} reviewed output hash")
    raise AuthorityRequest, "#{packet_id} execution receipt path is missing" unless receipt_path.file?
  end

  exact_equal!(envelope["approved_output_count"], envelope_packets.sum { |row| row["output_count"].to_i }, "G2 output budget")
  exact_equal!(approvals.sum { |row| row["approved_output_count"].to_i }, envelope["approved_output_count"], "approved output budget")
  exact_equal!(envelope["production_scope_ids"], requests.values.map { |_path, _relative, request| request["production_scope_id"] }.uniq, "G2 production scopes")
  exact_equal!(close["material_drift"], false, "material drift")
  exact_equal!(close["target_lock_violation"], false, "target lock violation")
  exact_equal!(close["message_lock_violation"], false, "message lock violation")

  binding_rows = Array(close["pixel_review_packet_bindings"])
  exact_equal!(binding_rows.map { |row| row["packet_id"].to_s }, packet_ids, "pixel review packet bindings")
  binding_rows.zip(review_rows).each do |binding, row|
    exact_equal!(binding["review_value_sha256"], value_sha256(row), "#{row['packet_id']} pixel review packet hash")
    judgment = graph_judgment_by_section.fetch(row["section_id"].to_s) do
      raise AuthorityRequest, "#{row['packet_id']} has no section-bound Graph contextual judgment"
    end
    source_match = Array(judgment["source_artifacts"]).any? do |source|
      source.is_a?(Hash) && source["path"].to_s == row["image_path"].to_s && source["sha256"].to_s == row["image_sha256"].to_s
    end
    raise AuthorityRequest, "#{row['packet_id']} output is not the exact judged_by source artifact" unless source_match
    criteria = Array(judgment["criteria"])
    exact_equal!(criteria.map { |criterion| criterion["criterion_id"] }, GRAPH_PIXEL_CRITERIA, "#{row['packet_id']} review criteria")
    criteria.each do |criterion|
      criterion_id = criterion["criterion_id"]
      result = criterion["result"]
      if %w[scene_visual_package_pixels still_composition_camera_depth_crop].include?(criterion_id)
        raise AuthorityRequest, "#{row['packet_id']} still-camera/composition close must equal 4" unless result == 4
      elsif criterion_id == "motion_pose_action_anchor"
        raise AuthorityRequest, "#{row['packet_id']} motion-anchor readability must equal 4" unless result == 4
      elsif result.is_a?(Integer)
        raise AuthorityRequest, "#{row['packet_id']} #{criterion_id} must be at least 3" if result < 3
      elsif result == "not_applicable"
        next
      else
        raise AuthorityRequest, "#{row['packet_id']} #{criterion_id} has an invalid result"
      end
    end
  end

  if options[:validate_only]
    puts JSON.pretty_generate(
      "status" => "validated",
      "review" => review_relative,
      "section_cohort_id" => close["section_cohort_id"],
      "section_ids" => section_ids,
      "packet_ids" => packet_ids,
      "automatic_fallback" => "none",
      "review_mutated" => false
    )
    exit 0
  end

  before_sha256 = Digest::SHA256.file(review_path).hexdigest
  begin
    transition = IdolGeneratedReviewPostPass.apply!(
      review_path: review_path,
      run_path: run_path,
      root: root,
      python: root.join("scripts", "idol-video-python"),
      schema_validator: root.join("scripts", "validate_json_schema.py"),
      review_schema: root.join("schemas", "review.schema.json"),
      local_upscaler: root.join("scripts", "idol_local_image_upscale.py"),
      generated_review_validator: root.join("scripts", "validate_generated_branch_cut_review.rb"),
      audio_placement_validator: root.join("scripts", "validate_audio_branch_cut_placement.rb"),
      trigger: "g2_delegated_cdd_pixel_close",
      allowed_pending_status: "cdd_review",
      pass_application: "g2_delegated_cdd_update"
    )
  rescue IdolGeneratedReviewPostPass::Error => e
    raise MechanicalHold, e.message
  end

  output_relative = options[:output] || run_path.join("review", "decision-intake", "g2-delegated-pixel-close-#{close['section_cohort_id']}.yaml").relative_path_from(root).to_s
  output_path, output_relative = root_path(output_relative, root, must_exist: false)
  raise AuthorityRequest, "delegated close intake must stay inside the owning run" unless inside?(output_path, run_path)
  intake = {
    "schema_version" => "idol_g2_delegated_pixel_close_intake.v1",
    "artifact_type" => "g2_delegated_pixel_close_intake",
    "status" => "passed",
    "run" => run_path.relative_path_from(root).to_s,
    "review" => {
      "path" => review_relative,
      "sha256_before_pass" => before_sha256,
      "sha256_after_pass" => Digest::SHA256.file(review_path).hexdigest
    },
    "g2_envelope" => {"path" => g2_relative, "sha256" => Digest::SHA256.file(g2_path).hexdigest, "json_pointer" => close.dig("g2_envelope", "json_pointer"), "value_sha256" => close.dig("g2_envelope", "value_sha256")},
    "section_cohort_id" => close["section_cohort_id"],
    "section_ids" => section_ids,
    "cdd_lane_id" => close["cdd_lane_id"],
    "cdd_owner" => close["cdd_owner"],
    "pixel_review_packet_bindings" => binding_rows,
    "post_pass_transition" => transition,
    "automation_boundaries" => {
      "founder_generated_review_recheck_required" => false,
      "material_drift_escalates_to_founder" => true,
      "automatic_fallback" => "none",
      "playback_pass_implied" => false,
      "edit_readiness_implied" => false
    }
  }
  already_present = preserve_once(output_path, YAML.dump(intake).b)
  puts JSON.pretty_generate(
    "status" => "passed",
    "output" => output_relative,
    "already_ingested" => already_present,
    "review" => review_relative,
    "post_pass_transition" => transition
  )
rescue AuthorityRequest => e
  puts JSON.pretty_generate(
    "status" => "authority_request",
    "reason" => e.message,
    "automatic_fallback" => "none",
    "review_mutated" => false
  )
  exit 1
rescue MechanicalHold => e
  puts JSON.pretty_generate(
    "status" => "hold",
    "reason" => e.message,
    "automatic_fallback" => "none"
  )
  exit 1
end
