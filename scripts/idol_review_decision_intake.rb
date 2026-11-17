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

ROOT = Pathname.new(__dir__).join("..").expand_path
PYTHON = ROOT.join("scripts/idol-video-python")
VALIDATOR = ROOT.join("scripts/validate_json_schema.py")
EXPORT_SCHEMA = ROOT.join("schemas/html-review-decision-export.schema.json")
INTAKE_SCHEMA = ROOT.join("schemas/founder-review-decision-intake.schema.json")
BOARD_VALIDATOR = ROOT.join("scripts/idol_html_review_board.rb")
LOCAL_UPSCALER = ROOT.join("scripts/idol_local_image_upscale.py")
GENERATED_REVIEW_VALIDATOR = ROOT.join("scripts/validate_generated_branch_cut_review.rb")
AUDIO_PLACEMENT_VALIDATOR = ROOT.join("scripts/validate_audio_branch_cut_placement.rb")
GENERATED_REVIEW_SCHEMA = ROOT.join("schemas/review.schema.json")

class IntakeError < StandardError; end

def root_path(raw, must_exist: false)
  path = Pathname.new(raw.to_s)
  path = ROOT.join(path) unless path.absolute?
  path = path.expand_path
  relative = path.relative_path_from(ROOT).to_s
  raise IntakeError, "path escapes repository root: #{raw}" if relative == ".." || relative.start_with?("../")
  raise IntakeError, "required file is missing: #{relative}" if must_exist && !path.file?
  [path, relative]
rescue ArgumentError
  raise IntakeError, "path escapes repository root: #{raw}"
end

def validate_schema(schema, path, label)
  stdout, stderr, status = Open3.capture3(PYTHON.to_s, VALIDATOR.to_s, schema.to_s, path.to_s, chdir: ROOT.to_s)
  raise IntakeError, "#{label} failed schema validation: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def load_structured(path, label)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [], aliases: true)
          end
  raise IntakeError, "#{label} must be a mapping" unless value.is_a?(Hash)
  value
rescue JSON::ParserError, Psych::Exception => e
  raise IntakeError, "cannot parse #{label}: #{e.message}"
end

def preserve_once(path, bytes, label)
  path.dirname.mkpath
  expected_sha = Digest::SHA256.hexdigest(bytes)
  Tempfile.create(["idol-preserve-once", path.extname], path.dirname.to_s) do |temp|
    temp.binmode
    temp.write(bytes)
    temp.flush
    temp.fsync
    begin
      File.link(temp.path, path.to_s)
      return false
    rescue Errno::EEXIST
      stat = File.lstat(path.to_s)
      unless stat.file? && Digest::SHA256.file(path).hexdigest == expected_sha
        raise IntakeError, "existing #{label} conflicts with the exact incoming bytes: #{path.relative_path_from(ROOT)}"
      end
      return true
    end
  end
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

def inside_path?(path, parent)
  relative = path.relative_path_from(parent).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError
  false
end

def verified_run_artifact(binding, run_path, label)
  raise IntakeError, "#{label} must be a path/SHA-256 binding" unless binding.is_a?(Hash)
  path, relative = root_path(binding.fetch("path"), must_exist: true)
  raise IntakeError, "#{label} must stay inside the owning run: #{relative}" unless inside_path?(path, run_path)
  expected = binding.fetch("sha256").to_s
  actual = Digest::SHA256.file(path).hexdigest
  raise IntakeError, "#{label} SHA-256 is stale: #{relative}" unless expected == actual
  [path, relative]
rescue KeyError => e
  raise IntakeError, "#{label} is missing #{e.key}"
end

def run_checked(command, label)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  unless status.success?
    detail = [stderr, stdout].join(" ").strip
    raise IntakeError, "#{label} failed; Founder intake is preserved but 03V remains on mechanical HOLD: #{detail}"
  end
  stdout
end

def generated_review_post_pass_transition(intake, active_cycle, run_path)
  unless active_cycle["cycle_kind"] == "g50_branch_results" &&
         active_cycle["stage_id"] == "generated_branch_cut_review" &&
         intake["review_mode"] == "g50_branch_results"
    return {
      "triggered" => false,
      "reason" => "not_generated_branch_cut_founder_gate"
    }
  end

  decisions = Array(intake["decisions"])
  complete_all_pass = intake["status"] == "ready_for_owner_routing" &&
                      intake.dig("summary", "missing_review_keys") == [] &&
                      !decisions.empty? &&
                      decisions.all? { |row| row["action"] == "pass" }
  unless complete_all_pass
    return {
      "triggered" => false,
      "reason" => "founder_decision_is_not_complete_all_pass"
    }
  end

  output_bindings = decisions.map { |row| row["returned_output"] }
  unique_bindings = output_bindings.uniq { |binding| [binding.to_h["path"], binding.to_h["sha256"]] }
  unless unique_bindings.length == 1
    raise IntakeError, "generated Branch-Cut Founder PASS must bind one exact returned review output"
  end
  review_path, review_relative = verified_run_artifact(
    unique_bindings.first,
    run_path,
    "generated Branch-Cut returned review output"
  )
  review = load_structured(review_path, "generated Branch-Cut returned review output")
  unless review["schema_version"] == "idol_generated_branch_cut_review.v4"
    raise IntakeError,
          "generated Branch-Cut returned output must use idol_generated_branch_cut_review.v4"
  end
  validate_schema(GENERATED_REVIEW_SCHEMA, review_path, "generated Branch-Cut returned review output")
  unless Array(review["section_reviews"]).all? { |row| row.is_a?(Hash) && row["decision"] == "pass" } &&
         Array(review["branch_cut_reviews"]).all? { |row| row.is_a?(Hash) && row["decision"] == "pass" }
    raise IntakeError,
          "explicit Founder all-PASS cannot promote a generated review whose section or Branch-Cut inspection is not pass"
  end

  IdolGeneratedReviewPostPass.apply!(
    review_path: review_path,
    run_path: run_path,
    root: ROOT,
    python: PYTHON,
    schema_validator: VALIDATOR,
    review_schema: GENERATED_REVIEW_SCHEMA,
    local_upscaler: LOCAL_UPSCALER,
    generated_review_validator: GENERATED_REVIEW_VALIDATOR,
    audio_placement_validator: AUDIO_PLACEMENT_VALIDATOR,
    trigger: "explicit_complete_founder_pass_intake",
    allowed_pending_status: "founder_review",
    pass_application: "founder_direct_update"
  )
rescue IdolGeneratedReviewPostPass::Error => e
  raise IntakeError, "#{e.message}; Founder intake is preserved but 03V remains on mechanical HOLD"
end

def safe_visual_output_name(value)
  normalized = value.to_s.gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/\A[-.]+|[-.]+\z/, "")
  normalized.empty? ? "founder-passed-visual" : normalized
end

def founder_passed_visual_transition(intake, active_cycle, manifest, run_path)
  return {"triggered" => false, "reason" => "generated_branch_cut_uses_review_bound_transition"} if active_cycle["cycle_kind"] == "g50_branch_results"

  complete_export = intake["status"] == "ready_for_owner_routing" &&
                    intake.dig("summary", "missing_review_keys") == []
  unless complete_export
    return {"triggered" => false, "reason" => "founder_decision_export_is_incomplete"}
  end

  pass_keys = Array(intake["decisions"]).select { |row| row["action"] == "pass" }.map { |row| row["review_key"] }.to_h { |key| [key, true] }
  return {"triggered" => false, "reason" => "no_explicit_founder_pass"} if pass_keys.empty?

  revision_id = active_cycle["revision_id"].to_s
  passed_cards = Array(active_cycle["cards"]).select do |card|
    pass_keys["#{revision_id}::#{card['card_id']}"]
  end
  assets = Array(manifest["review_assets"]).to_h { |asset| [asset["asset_id"].to_s, asset] }
  selected = passed_cards.flat_map do |card|
    Array(card["media"]).each_with_object([]) do |media_ref, rows|
      next unless media_ref.is_a?(Hash) && media_ref["asset_id"] && media_ref["binding_id"]
      asset = assets[media_ref["asset_id"].to_s]
      next unless asset.is_a?(Hash)
      next unless asset["media_kind"] == "image"
      next unless asset["inspection_action"] == "pixel_review_generated_output"
      next unless %w[member_visual generated_branch_cut].include?(asset["role"].to_s)
      binding = Array(asset["bindings"]).find { |row| row["binding_id"].to_s == media_ref["binding_id"].to_s }
      next unless binding
      source_candidate, = root_path(asset["canonical_path"], must_exist: true)
      next unless inside_path?(source_candidate, run_path)
      source_path, source_relative = verified_run_artifact(
        {"path" => asset["canonical_path"], "sha256" => asset["sha256"]},
        run_path,
        "Founder-passed generated visual #{asset['asset_id']}"
      )
      rows << {
        "asset_id" => asset["asset_id"].to_s,
        "source_path" => source_path,
        "source" => source_relative,
        "sha256" => asset["sha256"].to_s
      }
    end
  end.uniq { |row| [row["source"], row["sha256"]] }

  if selected.empty?
    return {"triggered" => false, "reason" => "pass_cards_have_no_new_generated_image_output"}
  end

  output_dir = run_path.join("generations", "upscaled", "founder-passed-visuals")
  command = [PYTHON.to_s, LOCAL_UPSCALER.to_s, "passed-visuals", "--root", ROOT.to_s]
  selected.each do |row|
    output = output_dir.join("#{safe_visual_output_name(row['asset_id'])}-#{row['sha256'][0, 12]}.png")
    row["output"] = output.relative_path_from(ROOT).to_s
    command.concat(["--item", "#{row['source']}=#{row['output']}"])
  end
  upscale = JSON.parse(run_checked(command, "automatic local upscale for explicit Founder-passed generated visuals"))
  results_by_source = Array(upscale["results"]).to_h { |row| [row["source"].to_s, row] }
  selected.each do |row|
    result = results_by_source.fetch(row["source"])
    run_checked(
      [
        PYTHON.to_s,
        ROOT.join("scripts/validate_local_image_upscale_receipt.py").to_s,
        result.fetch("receipt"),
        "--root",
        ROOT.to_s,
        "--source",
        row["source"],
        "--output",
        result.fetch("output"),
        "--purpose",
        "founder_passed_generated_visual",
        "--minimum-long-edge",
        "3840",
        "--json"
      ],
      "Founder-passed generated visual upscale validation"
    )
    row["receipt"] = result.fetch("receipt")
    row["reused"] = result["reused"] == true
    row.delete("source_path")
  end

  {
    "triggered" => true,
    "trigger" => "explicit_founder_pass_cards_with_generated_image_outputs",
    "cycle_kind" => active_cycle["cycle_kind"],
    "local_processing" => "complete",
    "upscaled_visual_count" => selected.length,
    "reused_visual_count" => selected.count { |row| row["reused"] },
    "visuals" => selected,
    "next_stage" => active_cycle["cycle_kind"] == "g20_visual_identity_lock" ?
      "current_title_member_visual_promotion" : "owning_stage_continuation",
    "03v_may_start" => false
  }
rescue JSON::ParserError, KeyError => e
  raise IntakeError, "Founder-passed generated visual upscale failed closed: #{e.message}"
end

def resolve_manifest_scalar(binding, source_documents, label)
  return binding.to_s unless binding.is_a?(Hash)
  source_id = binding.fetch("source_id")
  pointer = binding.fetch("pointer")
  value = source_documents.fetch(source_id) { raise IntakeError, "#{label} references unknown source #{source_id}" }
  pointer.to_s.split("/")[1..].to_a.each do |token|
    token = token.gsub("~1", "/").gsub("~0", "~")
    value = if value.is_a?(Array)
      raise IntakeError, "#{label} array pointer token is not an index: #{token}" unless token.match?(/\A(?:0|[1-9]\d*)\z/)
      value.fetch(token.to_i)
    elsif value.is_a?(Hash)
      value.fetch(token) { raise IntakeError, "#{label} pointer key is missing: #{token}" }
    else
      raise IntakeError, "#{label} pointer traverses a scalar at #{token}"
    end
  end
  value.is_a?(Array) ? value.join(binding.fetch("join", " · ")) : value.to_s
end

options = {write: false}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/idol_review_decision_intake.rb DECISION_EXPORT.json [--output PATH] --write"
  parser.on("--output PATH", "Validated intake output path.") { |value| options[:output] = value }
  parser.on("--write", "Capture the export and write the intake.") { options[:write] = true }
end.parse!

begin
  export_arg = ARGV.shift
  raise IntakeError, "DECISION_EXPORT.json is required" if export_arg.to_s.empty?
  raise IntakeError, "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  raise IntakeError, "--write is required to preserve the Founder decision export" unless options[:write]
  export_path = Pathname.new(export_arg).expand_path
  raise IntakeError, "decision export is missing: #{export_arg}" unless export_path.file?
  validate_schema(EXPORT_SCHEMA, export_path, "decision export")
  export = load_structured(export_path, "decision export")
  unless export["schema_version"] == "idol-html-review-board.decision-export.v12"
    raise IntakeError, "only the active Workbench review decision-export v12 contract is accepted"
  end

  manifest_path, manifest_rel = root_path(export.fetch("manifest_path"), must_exist: true)
  manifest_sha = Digest::SHA256.file(manifest_path).hexdigest
  raise IntakeError, "decision export manifest SHA-256 is stale" unless manifest_sha == export.fetch("manifest_sha256")
  stdout, stderr, status = Open3.capture3("ruby", BOARD_VALIDATOR.to_s, "validate", manifest_path.to_s, "--json", chdir: ROOT.to_s)
  raise IntakeError, "Founder workbench manifest is invalid: #{[stderr, stdout].join(' ').strip}" unless status.success?
  manifest = load_structured(manifest_path, "Founder workbench manifest")
  raise IntakeError, "decision export must come from the active board-v12 workbench" unless manifest["schema_version"] == "idol-html-review-board.v12"
  board = manifest.fetch("board")
  source_documents = Array(manifest.fetch("sources")).each_with_object({}) do |source, docs|
    source_path, = root_path(source.fetch("path"), must_exist: true)
    docs[source.fetch("source_id")] = load_structured(source_path, "board source #{source.fetch('source_id')}")
  end
  raise IntakeError, "decision export board_id mismatch" unless export["board_id"].to_s == board["board_id"].to_s
  raise IntakeError, "decision export board_revision mismatch" unless export["board_revision"] == board["revision"]
  review_mode = board.fetch("review_mode")
  raise IntakeError, "decision export review_mode mismatch" unless export["review_mode"] == review_mode

  run_rel = manifest.dig("run", "run_root").to_s
  run_path, = root_path(run_rel)
  raise IntakeError, "workbench run root is missing" unless run_path.directory?
  active_cycle_id = board["active_cycle_id"].to_s
  active_cycle = Array(manifest["sections"]).find { |row| row["cycle_id"].to_s == active_cycle_id }
  raise IntakeError, "active review cycle is missing" unless active_cycle
  revision_id = active_cycle["revision_id"].to_s

  canonical_cards = Array(active_cycle["cards"]).to_h do |card|
    review_key = "#{revision_id}::#{card.fetch('card_id')}"
    [review_key, card]
  end
  exported_rows = Array(export["decisions"])
  duplicate_keys = exported_rows.map { |row| row["review_key"].to_s }.group_by(&:itself).select { |_key, rows| rows.length > 1 }.keys
  raise IntakeError, "decision export contains duplicate review keys: #{duplicate_keys.join(', ')}" unless duplicate_keys.empty?
  unknown_keys = exported_rows.map { |row| row["review_key"].to_s } - canonical_cards.keys
  raise IntakeError, "decision export contains keys outside the active cycle: #{unknown_keys.join(', ')}" unless unknown_keys.empty?

  intake_decisions = exported_rows.map do |row|
    review_key = row.fetch("review_key")
    card = canonical_cards.fetch(review_key)
    target = card.fetch("review_target")
    expected = {
      "card_id" => card.fetch("card_id"),
      "cycle_kind" => active_cycle.fetch("cycle_kind"),
      "review_mode" => review_mode,
      "section_id" => active_cycle["section_id"],
      "scope_mode" => active_cycle.fetch("scope_mode"),
      "affected_section_ids" => card.fetch("affected_section_ids"),
      "stage_id" => active_cycle.fetch("stage_id"),
      "revision_id" => revision_id,
      "decision_scope" => card.fetch("decision_scope", "creative_selection"),
      "revision_scope" => card.fetch("revision_scope"),
      "review_target_id" => target.fetch("target_id"),
      "review_target_level" => target.fetch("level"),
      "review_target_number" => target.fetch("display_number"),
      "planning_cut_id" => target["planning_cut_id"],
      "core_cut_id" => target["core_cut_id"],
      "branch_cut_id" => target["branch_cut_id"],
      "decision_owner" => card.fetch("decision_owner"),
      "decision_question" => resolve_manifest_scalar(card.fetch("decision_question"), source_documents, "#{review_key}.decision_question"),
      "legal_actions" => card.fetch("legal_actions"),
      "affected_scope" => card.fetch("affected_scope"),
      "blocking_effect" => card.fetch("blocking_effect"),
      "decision_epoch" => card.fetch("decision_epoch"),
      "dispatch_id" => card.fetch("dispatch_id"),
      "returned_output" => card.fetch("returned_output"),
      "director_review" => card.fetch("director_review"),
      "founder_lineage" => card.fetch("founder_lineage"),
      "worker_evidence" => card.fetch("worker_evidence")
    }
    expected.each do |field, value|
      raise IntakeError, "#{review_key} #{field} drifted from the active workbench manifest" unless row[field] == value
    end
    annotation = row.fetch("note", "").to_s
    action = row.fetch("action")
    if %w[hold reject search_further direct_comment reject_archive revise_experiment teaser_first_full_mv_hold internal_hold material_exception].include?(action) && annotation.strip.empty?
      raise IntakeError, "#{review_key} #{action} requires a Founder annotation"
    end
    related_card_ids = Array(row["related_card_ids"])
    unknown_related = related_card_ids - canonical_cards.values.map { |candidate| candidate.fetch("card_id") }
    raise IntakeError, "#{review_key} related_card_ids contain unknown cards: #{unknown_related.join(', ')}" unless unknown_related.empty?
    target_copy = {
      "target_id" => target.fetch("target_id"),
      "level" => target.fetch("level"),
      "display_number" => target.fetch("display_number"),
      "label" => target.fetch("label")
    }
    %w[section_id planning_cut_id core_cut_id branch_cut_id].each { |field| target_copy[field] = target[field] if target[field] }
    {
      "review_key" => review_key,
      "cycle_kind" => active_cycle.fetch("cycle_kind"),
      "review_mode" => review_mode,
      "action" => action,
      "annotation" => annotation,
      "routing_status" => if review_mode == "g00_direction_draft"
                            "exploratory_signal"
                          elsif review_mode == "g30_fp_final"
                            if action == "select_candidate"
                              "candidate_selected_for_overall_promotion"
                            else
                              "g30_route_feedback"
                            end
                          elsif review_mode == "g30_experiment_disposition"
                            "experiment_disposition"
                          elsif review_mode == "video_playback_internal"
                            {"internal_pass" => "cdd_internal_pass", "internal_hold" => "cdd_internal_hold", "material_exception" => "cdd_material_exception"}.fetch(action)
                          else
                            {"pass" => "no_change_pass", "hold" => "founder_hold", "reject" => "founder_rejected"}.fetch(action)
                          end,
      "stage_id" => active_cycle.fetch("stage_id"),
      "revision_id" => revision_id,
      "decision_scope" => card.fetch("decision_scope", "creative_selection"),
      "revision_scope" => card.fetch("revision_scope"),
      "affected_section_ids" => card.fetch("affected_section_ids"),
      "review_target" => target_copy,
      "decision_owner" => card.fetch("decision_owner"),
      "decision_question" => resolve_manifest_scalar(card.fetch("decision_question"), source_documents, "#{review_key}.decision_question"),
      "legal_actions" => card.fetch("legal_actions"),
      "affected_scope" => card.fetch("affected_scope"),
      "blocking_effect" => card.fetch("blocking_effect"),
      "decision_epoch" => card.fetch("decision_epoch"),
      "dispatch_id" => card.fetch("dispatch_id"),
      "returned_output" => card.fetch("returned_output"),
      "director_review" => card.fetch("director_review"),
      "founder_lineage" => card.fetch("founder_lineage"),
      "worker_evidence" => card.fetch("worker_evidence")
    }.tap do |intake_row|
      intake_row["related_card_ids"] = related_card_ids unless related_card_ids.empty?
      named_field_locks = Array(row["named_field_locks"])
      intake_row["named_field_locks"] = named_field_locks unless named_field_locks.empty?
    end
  end

  selected_candidates = intake_decisions.select { |row| row["action"] == "select_candidate" }
  if selected_candidates.length > 1
    raise IntakeError, "g30_fp_final accepts at most one selected complete route for Overall promotion"
  end

  export_sha = Digest::SHA256.file(export_path).hexdigest
  capture_rel = "#{run_rel}/review/decision-exports/#{board.fetch('board_id')}-r#{board.fetch('revision')}-#{export_sha[0, 12]}.json"
  capture_path, = root_path(capture_rel)
  missing_review_keys = canonical_cards.keys - exported_rows.map { |row| row["review_key"].to_s }
  counts = intake_decisions.group_by { |row| row["action"] }.transform_values(&:length)
  intake_status = if review_mode == "g00_direction_draft"
                    "captured_for_director_synthesis"
                  else
                    missing_review_keys.empty? ? "ready_for_owner_routing" : "hold"
                  end
  intake = {
    "schema_version" => "idol_founder_review_decision_intake.v12",
    "artifact_type" => "workbench_review_decision_intake",
    "review_mode" => review_mode,
    "run" => run_rel,
    "source_board" => {
      "board_id" => board.fetch("board_id"),
      "board_revision" => board.fetch("revision"),
      "manifest" => {"path" => manifest_rel, "sha256" => manifest_sha},
      "decision_export" => {"path" => capture_rel, "sha256" => export_sha}
    },
    "status" => intake_status,
    "summary" => {
      "active_review_count" => canonical_cards.length,
      "decision_count" => intake_decisions.length,
      "pass_count" => counts.fetch("pass", 0),
      "hold_count" => counts.fetch("hold", 0),
      "reject_count" => counts.fetch("reject", 0),
      "action_counts" => counts,
      "missing_review_keys" => missing_review_keys
    },
    "decisions" => intake_decisions,
    "creative_rereview_policy" => if review_mode == "g00_direction_draft"
      "director_synthesizes_g00_non_gate_feedback"
    elsif review_mode == "g30_fp_final"
      "overall_routes_one_selected_complete_g30_route_without_automatic_merge"
    elsif review_mode == "video_playback_internal"
      "cdd_internal_playback_checkpoint_without_founder_gate"
    else
      "founder_direct_decision_skips_additional_llm_creative_verdict"
    end,
    "automation_boundaries" => {
      "canonical_creative_write_performed" => false,
      "decision_interpreted_or_rewritten" => false,
      "downstream_invalidation_authored" => false,
      "gate_status_inferred" => false,
      "unnamed_field_lock_created" => false
    }
  }
  output_path, output_rel = root_path(options[:output] || "#{run_rel}/review/decision-intake/#{board.fetch('board_id')}-r#{board.fetch('revision')}.yaml")
  raise IntakeError, "intake output must stay inside the owning run" unless output_rel.start_with?("#{run_rel}/")
  yaml = YAML.dump(intake)
  Tempfile.create(["idol-review-decision-intake", ".yaml"]) do |temp|
    temp.write(yaml)
    temp.flush
    validate_schema(INTAKE_SCHEMA, Pathname.new(temp.path), "decision intake")
  end
  capture_already_present = preserve_once(capture_path, export_path.binread, "decision export capture")
  intake_already_present = preserve_once(output_path, yaml.b, "decision intake")
  post_pass_transition = if active_cycle["cycle_kind"] == "g50_branch_results"
                           generated_review_post_pass_transition(intake, active_cycle, run_path)
                         else
                           founder_passed_visual_transition(intake, active_cycle, manifest, run_path)
                         end
  puts JSON.pretty_generate(
    "status" => intake["status"],
    "output" => output_rel,
    "captured_export" => capture_rel,
    "already_ingested" => capture_already_present && intake_already_present,
    "summary" => intake["summary"],
    "post_pass_transition" => post_pass_transition
  )
rescue IntakeError => e
  warn "ERROR: #{e.message}"
  exit 1
end
