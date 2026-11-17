#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "lib/idol_run_layout"

ROOT = Pathname.new(__dir__).join("..").expand_path
EDIT_MAP_SCHEMA = ROOT.join("schemas", "edit-map.schema.json")
CLOSEOUT_SCHEMA = ROOT.join("schemas", "edit-qc-closeout.schema.json")
COMPILE_MANIFEST_SCHEMA = ROOT.join("schemas", "edit-finishing-fx-compile-manifest.schema.json")
RENDER_MANIFEST_SCHEMA = ROOT.join("schemas", "edit-render-manifest.schema.json")
DELIVERY_QC_SCHEMA = ROOT.join("schemas", "edit-delivery-qc.schema.json")
CUTPOINT_MANIFEST_SCHEMA = ROOT.join("schemas", "edit-cutpoint-sheet-manifest.schema.json")
DELIVERY_QC_SCRIPT = ROOT.join("scripts", "idol_edit_delivery_qc.py")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
VIDEO_PYTHON = ROOT.join("scripts", "idol-video-python")
RECIPE_VALIDATOR = ROOT.join("scripts", "validate_edit_recipe.py")
MARKER_PLAN_VALIDATOR = ROOT.join("scripts", "validate_edit_marker_plan.py")
FX_VALIDATOR = ROOT.join("scripts", "validate_edit_finishing_fx.rb")
COMPILE_VALIDATOR = ROOT.join("scripts", "validate_edit_finishing_fx_compile.py")

READY_SHARD_STATUSES = %w[ready_for_merge merged].freeze
REQUIRED_READY_SHARD_FIELDS = %w[
  story_flow_continuity
  space_visible_feeling_progression
  directorial_transition_intent
].freeze
FINAL_AUDIT_STATUSES = %w[complete_no_fx_needed complete_fx_passed].freeze
FINAL_RENDER_TOP_STATUSES = %w[locked_for_final_render].freeze
CLOSEOUT_TOP_STATUSES = %w[
  locked_for_final_render
  ready_for_05
  final_master_ready_local
  final_complete_platform_records_closed
].freeze
FINAL_CANDIDATE_PASS_STATUSES = %w[
  passed
  founder_passed
  approved_for_final_render
  locked_for_final_render
  qc_pass
].freeze
STATUS_SEPARATOR = "[_\\s-]"
REVIEW_STATUS_PATTERN = /(?:^|#{STATUS_SEPARATOR})(?:needs_founder|needs.*review|rendered_needs|calibration|timing_test|hold|blocked)(?:$|#{STATUS_SEPARATOR})/i
REJECT_STATUS_PATTERN = /(?:^|#{STATUS_SEPARATOR})(?:rejected|failed|unrecoverable|mismatch)(?:$|#{STATUS_SEPARATOR})/i
SHA256_PATTERN = /\A[a-f0-9]{64}\z/.freeze
CUTPOINT_FRAME_OFFSETS = [-3, -2, -1, 0, 1, 2, 3, 6].freeze

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_path(path)
  return nil if blank?(path)

  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : ROOT.join(raw).cleanpath
end

def readable_file?(path)
  resolved = resolve_path(path)
  resolved && File.file?(resolved.to_s)
end

def load_yaml_hash(path)
  doc = YAML.safe_load(Pathname.new(path).read, permitted_classes: [], permitted_symbols: [], aliases: true)
  return doc if doc.is_a?(Hash)

  warn "ERROR: edit map must be a YAML mapping: #{path}"
  exit 1
rescue Errno::ENOENT
  warn "ERROR: edit map is not readable: #{path}"
  exit 1
rescue Psych::SyntaxError => e
  warn "ERROR: edit map YAML syntax error: #{e.message}"
  exit 1
end

def load_mapping(path, label, errors)
  document = YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
  unless document.is_a?(Hash)
    errors << "#{label} must be a YAML/JSON mapping: #{path}"
    return nil
  end
  document
rescue Errno::ENOENT
  errors << "#{label} is not readable: #{path}"
  nil
rescue Psych::SyntaxError => e
  errors << "#{label} YAML syntax error: #{e.message}"
  nil
end

def count_by_status(records)
  records.each_with_object(Hash.new(0)) do |record, counts|
    status = record.is_a?(Hash) ? record["status"].to_s : "invalid"
    counts[status.empty? ? "missing" : status] += 1
  end
end

def infer_run_root(path)
  current = path.expand_path.dirname
  loop do
    parts = current.each_filename.to_a
    runs_index = parts.rindex("runs")
    if runs_index
      relative = parts[runs_index..].join("/")
      return current if IdolRunLayout::ACTIVE_RUN_ROOT_PATTERN.match?(relative)
      return current if relative == "runs/2026-07-29/0729_ONE_MOVE"
    end
    return nil if current.root?

    current = current.parent
  end
end

def path_within?(path, parent)
  value = path.expand_path.to_s
  root = parent.expand_path.to_s.sub(%r{/+\z}, "")
  value == root || value.start_with?("#{root}/")
end

def resolve_declared_path(value, owner_path)
  return nil if blank?(value)

  raw = Pathname.new(value.to_s)
  return raw.expand_path if raw.absolute?

  if raw.each_filename.first == "runs"
    return ROOT.join(raw).expand_path
  end

  run_root = infer_run_root(owner_path)
  run_candidate = run_root&.join(raw)&.expand_path
  return run_candidate if run_candidate&.exist?

  ROOT.join(raw).expand_path
end

def resolve_required_file(value, owner_path, label, errors, same_run: true)
  if blank?(value)
    errors << "#{label} is required"
    return nil
  end

  path = resolve_declared_path(value, owner_path)
  unless path&.file? && path.readable?
    errors << "#{label} is not readable: #{value}"
    return nil
  end

  owner_run = infer_run_root(owner_path)
  if same_run && owner_run && !path_within?(path.realpath, owner_run.realpath)
    errors << "#{label} must remain inside owning run #{owner_run}: #{value}"
    return nil
  end
  path.realpath
rescue Errno::ENOENT, ArgumentError => e
  errors << "#{label} is not readable: #{value} (#{e.message})"
  nil
end

def sha256_file(path)
  Digest::SHA256.file(path.to_s).hexdigest
end

def verify_sha(path, declared, label, errors)
  unless declared.to_s.match?(SHA256_PATTERN)
    errors << "#{label}.sha256 must be a lowercase SHA-256 digest"
    return
  end
  actual = sha256_file(path)
  errors << "#{label}.sha256 mismatch: declared bytes are stale" unless actual == declared
end

def verify_binding(binding, owner_path, label, errors, same_run: true)
  unless binding.is_a?(Hash)
    errors << "#{label} must be a path/SHA binding"
    return nil
  end
  path = resolve_required_file(binding["path"], owner_path, "#{label}.path", errors, same_run: same_run)
  verify_sha(path, binding["sha256"], label, errors) if path
  path
end

def same_path?(left, right)
  left && right && left.realpath == right.realpath
rescue Errno::ENOENT
  false
end

def validate_schema(schema_path, artifact_path, label, errors)
  stdout, stderr, status = Open3.capture3(
    VIDEO_PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    schema_path.to_s,
    artifact_path.to_s,
    chdir: ROOT.to_s
  )
  return if status.success?

  detail = [stdout, stderr].reject(&:empty?).join(" ").strip
  detail = detail.lines.first(8).join.strip
  errors << "#{label} schema validation failed#{detail.empty? ? '' : ": #{detail}"}"
rescue Errno::ENOENT => e
  errors << "#{label} schema validator is unavailable: #{e.message}"
end

def run_validator(command, label, errors)
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
  return if status.success?

  detail = [stdout, stderr].reject(&:empty?).join(" ").strip
  errors << "#{label} failed#{detail.empty? ? '' : ": #{detail}"}"
rescue Errno::ENOENT => e
  errors << "#{label} is unavailable: #{e.message}"
end

def rational_fps(value)
  case value
  when Hash
    numerator = Integer(value["numerator"])
    denominator = Integer(value["denominator"])
    return nil if numerator <= 0 || denominator <= 0

    Rational(numerator, denominator)
  when Numeric
    Rational(value.to_s)
  when String
    numerator, denominator = value.split(/[\/:]/, 2)
    denominator ? Rational(Integer(numerator), Integer(denominator)) : Rational(value)
  end
rescue ArgumentError, TypeError, ZeroDivisionError
  nil
end

def render_video_codec(value)
  case value.to_s.downcase
  when "h264", "libx264" then "libx264"
  when "prores", "prores_ks" then "prores_ks"
  else value.to_s.downcase
  end
end

def probed_video_codec(value)
  case value.to_s.downcase
  when "h264", "libx264" then "h264"
  when "prores", "prores_ks" then "prores"
  else value.to_s.downcase
  end
end

def validate_compile_manifest(manifest_path, expected_recipe, expected_source_recipe, expected_fx_map, expected_audit, errors, semantic_revalidate: true)
  if semantic_revalidate
    run_validator(
      [
        VIDEO_PYTHON.to_s,
        COMPILE_VALIDATOR.to_s,
        manifest_path.to_s,
        "--expect-output",
        expected_recipe.to_s,
        "--require-final"
      ],
      "04FX compile manifest semantic validation",
      errors
    )
  end
  validate_schema(COMPILE_MANIFEST_SCHEMA, manifest_path, "04FX compile manifest", errors)
  manifest = load_mapping(manifest_path, "04FX compile manifest", errors)
  return nil unless manifest

  errors << "04FX compile manifest must use compile_mode=final_pass_only" unless manifest["compile_mode"] == "final_pass_only"
  bindings = manifest["source_bindings"].is_a?(Hash) ? manifest["source_bindings"] : {}
  bound_fx_map = verify_binding(bindings["fx_map"], manifest_path, "04FX compile source FX map", errors)
  bound_source_recipe = verify_binding(bindings["recipe"], manifest_path, "04FX compile source recipe", errors)
  verify_binding(bindings["effect_registry"], manifest_path, "04FX effect registry", errors, same_run: false)
  errors << "04FX compile source FX map does not match edit-map pointer" unless same_path?(bound_fx_map, expected_fx_map)
  errors << "04FX compile source recipe does not match editable 04 recipe" unless same_path?(bound_source_recipe, expected_source_recipe)

  selection = manifest["selection"].is_a?(Hash) ? manifest["selection"] : {}
  selected_ids = Array(selection["selected_pass_fx_ids"]).map(&:to_s)
  compiled_ids = Array(selection["compiled_fx_ids"]).map(&:to_s)
  skipped_ids = Array(selection["skipped_pass_fx_ids"]).map(&:to_s)
  errors << "04FX final compile selected/compiled FX ids differ" unless selected_ids == compiled_ids
  errors << "04FX final compile skipped passed FX ids: #{skipped_ids.join(', ')}" unless skipped_ids.empty?
  errors << "04FX compile audit status does not match edit-map audit status" unless selection["audit_status"].to_s == expected_audit.to_s
  if expected_audit == "complete_no_fx_needed" && (!selected_ids.empty? || !compiled_ids.empty?)
    errors << "complete_no_fx_needed must compile zero 04FX records"
  elsif expected_audit == "complete_fx_passed" && compiled_ids.empty?
    errors << "complete_fx_passed must compile at least one passed FX record"
  end

  output = manifest["compiled_output"].is_a?(Hash) ? manifest["compiled_output"] : {}
  output_path = verify_binding(output, manifest_path, "04FX compiled output", errors)
  errors << "04FX final compile output must be a merged_recipe" unless output["kind"] == "merged_recipe"
  errors << "04FX compiled output does not match current final recipe" unless same_path?(output_path, expected_recipe)
  if output["compiled_04fx_count"].is_a?(Integer) && output["compiled_04fx_count"] != compiled_ids.length
    errors << "04FX compiled_04fx_count does not match compiled_fx_ids"
  end
  manifest
end

def validate_final_render_mode(edit_map, edit_map_path, errors, revalidate_pre_render_sources: true)
  recipe_contract = edit_map["recipe_qc_contract"]
  unless recipe_contract.is_a?(Hash)
    errors << "recipe_qc_contract is required for final-render mode"
    return {}
  end
  base_recipe_path = resolve_required_file(
    recipe_contract["current_final_recipe"],
    edit_map_path,
    "recipe_qc_contract.current_final_recipe",
    errors
  )
  manual_recipe = edit_map.dig("manual_adjustment_workflow", "current_final_recipe")
  if base_recipe_path && !blank?(manual_recipe)
    manual_path = resolve_required_file(
      manual_recipe,
      edit_map_path,
      "manual_adjustment_workflow.current_final_recipe",
      errors
    )
    errors << "manual and recipe-QC current final recipe pointers disagree" unless same_path?(manual_path, base_recipe_path)
  end
  if base_recipe_path && revalidate_pre_render_sources
    command = [
      VIDEO_PYTHON.to_s,
      RECIPE_VALIDATOR.to_s,
      base_recipe_path.to_s,
      "--require-v3",
      "--mode",
      "preview"
    ]
    run_root = infer_run_root(edit_map_path)
    command.concat(["--run-root", run_root.to_s]) if run_root
    run_validator(command, "editable 04 recipe validation", errors)
  end
  render_recipe_path = resolve_required_file(
    recipe_contract["final_render_recipe_path"],
    edit_map_path,
    "recipe_qc_contract.final_render_recipe_path",
    errors
  )
  if render_recipe_path && revalidate_pre_render_sources
    command = [
      VIDEO_PYTHON.to_s,
      RECIPE_VALIDATOR.to_s,
      render_recipe_path.to_s,
      "--require-v3",
      "--mode",
      "final-render"
    ]
    run_root = infer_run_root(edit_map_path)
    command.concat(["--run-root", run_root.to_s]) if run_root
    run_validator(command, "compiled final-render recipe validation", errors)
  end

  effect_summary = edit_map["effect_audit_summary"]
  unless effect_summary.is_a?(Hash)
    errors << "effect_audit_summary is required for final-render mode"
    return { base_recipe_path: base_recipe_path, recipe_path: render_recipe_path }
  end
  summary_audit_status = effect_summary["transition_opportunity_audit_status"].to_s
  if %w[fail stale].include?(effect_summary["compile_status"].to_s)
    errors << "effect_audit_summary.compile_status blocks final render"
  end

  fx_map_path = resolve_required_file(
    effect_summary["finishing_fx_map_path"],
    edit_map_path,
    "effect_audit_summary.finishing_fx_map_path",
    errors
  )
  if fx_map_path
    if revalidate_pre_render_sources
      run_validator(
        [RbConfig.ruby, FX_VALIDATOR.to_s, fx_map_path.to_s],
        "04FX final map validation",
        errors
      )
    end
    fx_map = load_mapping(fx_map_path, "04FX final map", errors)
    actual_audit = fx_map&.dig("transition_opportunity_audit", "audit_status").to_s
    errors << "04FX transition opportunity audit is not final: #{actual_audit.inspect}" unless FINAL_AUDIT_STATUSES.include?(actual_audit)
    if FINAL_AUDIT_STATUSES.include?(summary_audit_status) && actual_audit != summary_audit_status
      errors << "edit-map and 04FX transition audit statuses disagree"
    end
  end
  audit_status = actual_audit.to_s
  compile_manifest_path = resolve_required_file(
    effect_summary["compile_manifest_path"],
    edit_map_path,
    "effect_audit_summary.compile_manifest_path",
    errors
  )
  compile_manifest = if compile_manifest_path && render_recipe_path && base_recipe_path && fx_map_path
                       validate_compile_manifest(
                         compile_manifest_path,
                         render_recipe_path,
                         base_recipe_path,
                         fx_map_path,
                         audit_status,
                         errors,
                         semantic_revalidate: revalidate_pre_render_sources
                       )
                     end
  render_status = recipe_contract["final_render_status"].to_s
  unless %w[not_rendered rendered_pending_qc qc_pass].include?(render_status)
    errors << "recipe_qc_contract.final_render_status is not usable for final render: #{render_status.inspect}"
  end

  {
    base_recipe_path: base_recipe_path,
    recipe_path: render_recipe_path,
    fx_map_path: fx_map_path,
    compile_manifest_path: compile_manifest_path,
    compile_manifest: compile_manifest
  }
end

def require_matching_binding(binding, owner_path, expected_path, expected_sha, label, errors)
  path = verify_binding(binding, owner_path, label, errors)
  errors << "#{label}.path does not match the owning pointer" unless same_path?(path, expected_path)
  if expected_sha && binding.is_a?(Hash) && binding["sha256"].to_s != expected_sha.to_s
    errors << "#{label}.sha256 does not match the owning digest"
  end
  path
end

def validate_closeout_mode(edit_map, edit_map_path, final_context, errors)
  recipe_contract = edit_map["recipe_qc_contract"].is_a?(Hash) ? edit_map["recipe_qc_contract"] : {}
  errors << "recipe_qc_contract.final_render_status must be qc_pass for closeout" unless recipe_contract["final_render_status"] == "qc_pass"
  render_manifest_path = resolve_required_file(
    recipe_contract["final_render_manifest_path"],
    edit_map_path,
    "recipe_qc_contract.final_render_manifest_path",
    errors
  )

  closeout_pointer = edit_map["final_closeout_inventory"]
  unless closeout_pointer.is_a?(Hash)
    errors << "final_closeout_inventory is required for closeout mode"
    return
  end
  errors << "final_closeout_inventory.status must be ready_for_05" unless closeout_pointer["status"] == "ready_for_05"
  errors << "final_closeout_inventory.validation_status must be pass" unless closeout_pointer["validation_status"] == "pass"
  closeout_path = resolve_required_file(
    closeout_pointer["path"],
    edit_map_path,
    "final_closeout_inventory.path",
    errors
  )
  return unless closeout_path
  unless %w[.yaml .yml .json].include?(closeout_path.extname.downcase)
    errors << "closeout mode requires a structured YAML/JSON closeout, not #{closeout_path.extname}"
    return
  end

  verify_sha(closeout_path, closeout_pointer["sha256"], "final_closeout_inventory", errors)
  validate_schema(CLOSEOUT_SCHEMA, closeout_path, "edit QC closeout", errors)
  closeout = load_mapping(closeout_path, "edit QC closeout", errors)
  return unless closeout

  errors << "closeout mode requires idol_edit_qc_closeout.v3" unless closeout["schema_version"] == "idol_edit_qc_closeout.v3"
  errors << "closeout status must be ready_for_05" unless closeout["status"] == "ready_for_05"
  errors << "closeout content_id does not match edit map" unless closeout["content_id"].to_s == edit_map["content_id"].to_s

  recipe_path = final_context[:recipe_path]
  final_recipe = closeout["final_recipe"].is_a?(Hash) ? closeout["final_recipe"] : {}
  closeout_recipe_path = resolve_required_file(final_recipe["path"], closeout_path, "closeout.final_recipe.path", errors)
  verify_sha(closeout_recipe_path, final_recipe["sha256"], "closeout.final_recipe", errors) if closeout_recipe_path
  errors << "closeout final recipe does not match edit-map final-render recipe" unless same_path?(closeout_recipe_path, recipe_path)
  recipe = recipe_path && load_mapping(recipe_path, "final edit recipe", errors)
  marker_pointer = edit_map.dig("edit_marker_plan_ref", "path")
  marker_path = resolve_required_file(marker_pointer, edit_map_path, "edit_marker_plan_ref.path", errors)
  recipe_marker_path = verify_binding(
    recipe && recipe["source_edit_marker_plan"],
    recipe_path,
    "final recipe source edit-marker plan",
    errors
  )
  errors << "final recipe marker-plan binding does not match the edit-map pointer" unless same_path?(recipe_marker_path, marker_path)

  lineage = closeout["render_lineage"].is_a?(Hash) ? closeout["render_lineage"] : {}
  compile_path = final_context[:compile_manifest_path]
  compile_sha = compile_path && sha256_file(compile_path)
  require_matching_binding(
    lineage["fx_compile_manifest"],
    closeout_path,
    compile_path,
    compile_sha,
    "closeout.render_lineage.fx_compile_manifest",
    errors
  )
  render_path = require_matching_binding(
    lineage["final_render_manifest"],
    closeout_path,
    render_manifest_path,
    render_manifest_path && sha256_file(render_manifest_path),
    "closeout.render_lineage.final_render_manifest",
    errors
  )
  return unless render_path

  validate_schema(RENDER_MANIFEST_SCHEMA, render_path, "final render manifest", errors)
  render_manifest = load_mapping(render_path, "final render manifest", errors)
  return unless render_manifest

  errors << "final render manifest profile must be final" unless render_manifest["profile"] == "final"
  render_bindings = render_manifest["source_bindings"].is_a?(Hash) ? render_manifest["source_bindings"] : {}
  require_matching_binding(
    render_bindings["recipe"],
    render_path,
    recipe_path,
    recipe_path && sha256_file(recipe_path),
    "final render source recipe",
    errors
  )
  require_matching_binding(
    render_bindings["fx_compile_manifest"],
    render_path,
    compile_path,
    compile_sha,
    "final render source 04FX compile manifest",
    errors
  )
  selected_audio_path = recipe && resolve_declared_path(recipe.dig("audio_program", "path"), recipe_path)
  require_matching_binding(
    render_bindings["audio"],
    render_path,
    selected_audio_path,
    recipe&.dig("audio_program", "sha256"),
    "final render source selected audio",
    errors
  )

  final_master = closeout["final_master"].is_a?(Hash) ? closeout["final_master"] : {}
  master_path = resolve_required_file(final_master["path"], closeout_path, "closeout.final_master.path", errors)
  verify_sha(master_path, final_master["sha256"], "closeout.final_master", errors) if master_path
  output = render_manifest["output"].is_a?(Hash) ? render_manifest["output"] : {}
  render_output_path = verify_binding(output, render_path, "final render output", errors)
  errors << "render manifest output does not match closeout final master" unless same_path?(render_output_path, master_path)
  if output["sha256"].to_s != final_master["sha256"].to_s
    errors << "render manifest and closeout final-master digests disagree"
  end

  %w[frame_count width height].each do |field|
    errors << "render manifest and closeout final_master.#{field} disagree" unless output[field] == final_master[field]
  end
  render_spec = render_manifest["render_spec"].is_a?(Hash) ? render_manifest["render_spec"] : {}
  recipe_expected_frames = Array(recipe && recipe["timeline"]).sum do |segment|
    segment.is_a?(Hash) && segment["duration_frames"].is_a?(Integer) ? segment["duration_frames"] : 0
  end
  if recipe_expected_frames <= 0
    errors << "final recipe has no positive frame-locked program duration"
  else
    errors << "render manifest expected_frame_count does not equal the complete final recipe" unless render_spec["expected_frame_count"] == recipe_expected_frames
    errors << "render output frame_count does not equal the complete final recipe" unless output["frame_count"] == recipe_expected_frames
  end
  errors << "render manifest and closeout final-master FPS disagree" unless rational_fps(render_spec["fps"]) == rational_fps(final_master["fps"])
  errors << "render manifest expected and actual pixel formats disagree" unless render_spec["pixel_format"].to_s == output["pixel_format"].to_s
  errors << "render manifest and closeout final-master pixel formats disagree" unless output["pixel_format"].to_s == final_master["pixel_format"].to_s
  encoding = render_manifest["encoding"].is_a?(Hash) ? render_manifest["encoding"] : {}
  errors << "render manifest and closeout final-master containers disagree" unless encoding["container"].to_s == final_master["container"].to_s
  errors << "render manifest and closeout final-master video codecs disagree" unless output["video_codec"].to_s == final_master["video_codec"].to_s
  errors << "render manifest and closeout final-master audio codecs disagree" unless output["audio_codec"].to_s == final_master["audio_codec"].to_s
  recipe_mezzanine = recipe&.dig("delivery_policy", "mezzanine") || {}
  errors << "final-render container does not match recipe delivery policy" unless encoding["container"].to_s.downcase == recipe_mezzanine["container"].to_s.downcase
  errors << "final-render requested video codec does not match recipe delivery policy" unless render_video_codec(encoding["requested_video_codec"]) == render_video_codec(recipe_mezzanine["video_codec"])
  errors << "final-render requested audio codec does not match recipe delivery policy" unless encoding["requested_audio_codec"].to_s.downcase == recipe_mezzanine["audio_codec"].to_s.downcase
  errors << "observed final-master video codec does not match recipe delivery policy" unless probed_video_codec(output["video_codec"]) == probed_video_codec(recipe_mezzanine["video_codec"])
  errors << "observed final-master audio codec does not match recipe delivery policy" unless output["audio_codec"].to_s.downcase == recipe_mezzanine["audio_codec"].to_s.downcase
  if master_path && master_path.extname.downcase.delete_prefix(".") != final_master["container"].to_s.downcase
    errors << "final-master file extension does not match its declared container"
  end
  final_color_tags = final_master["color_tags"].is_a?(Hash) ? final_master["color_tags"] : {}
  %w[color_range color_space color_transfer color_primaries].each do |field|
    errors << "render output and closeout final-master #{field} disagree" unless output[field].to_s == final_color_tags[field].to_s
  end
  fps = rational_fps(final_master["fps"])
  if fps && output["duration_seconds"].is_a?(Numeric) && final_master["duration_seconds"].is_a?(Numeric)
    tolerance = 0.5 / fps.to_f
    if (output["duration_seconds"].to_f - final_master["duration_seconds"].to_f).abs > tolerance
      errors << "render manifest and closeout final-master durations differ by more than half a frame"
    end
  end

  source_inventory = closeout["source_inventory"].is_a?(Hash) ? closeout["source_inventory"] : {}
  recipe_source_paths = []
  Array(recipe && recipe["timeline"]).each_with_index do |segment, index|
    next unless segment.is_a?(Hash)

    source_path = resolve_required_file(
      segment["source"],
      recipe_path,
      "final recipe timeline[#{index}].source",
      errors
    )
    if source_path
      verify_sha(source_path, segment["source_sha256"], "final recipe timeline[#{index}].source", errors)
      recipe_source_paths << source_path
    end
    probe_path = resolve_required_file(
      segment["source_probe_ref"],
      recipe_path,
      "final recipe timeline[#{index}].source_probe_ref",
      errors
    )
    verify_sha(probe_path, segment["source_probe_sha256"], "final recipe timeline[#{index}].source_probe_ref", errors) if probe_path
  end
  unique_recipe_source_count = recipe_source_paths.map(&:to_s).uniq.length
  errors << "closeout recipe-source count does not match the final recipe" unless source_inventory["recipe_source_count"] == unique_recipe_source_count
  keeper_path = resolve_required_file(
    source_inventory["source_keeper_index"],
    closeout_path,
    "closeout.source_inventory.source_keeper_index",
    errors
  )
  verify_sha(keeper_path, source_inventory["source_keeper_index_sha256"], "closeout source keeper index", errors) if keeper_path

  qc_artifacts = closeout["qc_artifacts"].is_a?(Hash) ? closeout["qc_artifacts"] : {}
  %w[
    final_contact_sheet
    blackdetect_report
    silence_report
    source_family_mismatch_report
    audio_delivery_report
    color_metadata_report
    retime_cadence_report
  ].each do |field|
    resolve_required_file(qc_artifacts[field], closeout_path, "closeout.qc_artifacts.#{field}", errors)
  end
  declared_cutpoint_sheets = Array(qc_artifacts["cutpoint_sheets"]).each_with_index.each_with_object([]) do |(path, index), paths|
    resolved = resolve_required_file(path, closeout_path, "closeout.qc_artifacts.cutpoint_sheets[#{index}]", errors)
    paths << resolved if resolved
  end
  cleanup = closeout["cache_cleanup"].is_a?(Hash) ? closeout["cache_cleanup"] : {}
  resolve_required_file(cleanup["manifest_path"], closeout_path, "closeout.cache_cleanup.manifest_path", errors)

  recipe_render_spec = recipe&.fetch("render_spec", {}) || {}
  errors << "closeout sample-aspect ratio does not match final recipe" unless final_master["sample_aspect_ratio"].to_s.tr(":", "/") == recipe_render_spec["sample_aspect_ratio"].to_s.tr(":", "/")
  program_qc = closeout.dig("professional_qc", "program_integrity") || {}
  errors << "professional QC expected frames do not match render manifest" unless program_qc["expected_frame_count"] == render_spec["expected_frame_count"]
  errors << "professional QC actual frames do not match render manifest" unless program_qc["actual_frame_count"] == output["frame_count"]
  audio_qc = closeout.dig("professional_qc", "audio_delivery") || {}
  audio_program = recipe&.fetch("audio_program", {}) || {}
  errors << "closeout selected-audio digest does not match final recipe" unless audio_qc["selected_audio_sha256"].to_s == audio_program["sha256"].to_s
  errors << "closeout sample rate does not match final recipe" unless audio_qc["sample_rate"] == audio_program["sample_rate"]
  errors << "closeout channel layout does not match final recipe" unless audio_qc["channel_layout"].to_s == audio_program["channel_layout"].to_s
  if fps && audio_qc["audio_video_duration_delta_seconds"].is_a?(Numeric) &&
     audio_qc["audio_video_duration_delta_seconds"].to_f > 0.5 / fps.to_f
    errors << "audio/video duration delta exceeds half a frame"
  end

  color_qc = closeout.dig("professional_qc", "color_delivery") || {}
  color_tags = final_master["color_tags"].is_a?(Hash) ? final_master["color_tags"] : {}
  recipe_color_delivery = recipe&.dig("color_pipeline", "delivery") || {}
  {
    "pixel_format" => final_master["pixel_format"],
    "color_range" => color_tags["color_range"],
    "color_space" => color_tags["color_space"],
    "color_transfer" => color_tags["color_transfer"],
    "color_primaries" => color_tags["color_primaries"]
  }.each do |field, expected|
    errors << "professional color QC #{field} does not match final master" unless color_qc[field].to_s == expected.to_s
  end
  %w[color_range color_space color_transfer color_primaries].each do |field|
    errors << "final-master color tag #{field} does not match final recipe delivery" unless color_tags[field].to_s == recipe_color_delivery[field].to_s
  end

  professional_qc = closeout["professional_qc"].is_a?(Hash) ? closeout["professional_qc"] : {}
  delivery_qc_path = require_matching_binding(
    professional_qc["delivery_qc_report"],
    closeout_path,
    resolve_required_file(
      qc_artifacts["audio_delivery_report"],
      closeout_path,
      "closeout.qc_artifacts.audio_delivery_report",
      errors
    ),
    professional_qc.dig("delivery_qc_report", "sha256"),
    "closeout.professional_qc.delivery_qc_report",
    errors
  )
  if delivery_qc_path
    validate_schema(DELIVERY_QC_SCHEMA, delivery_qc_path, "edit delivery QC report", errors)
    delivery_qc = load_mapping(delivery_qc_path, "edit delivery QC report", errors)
    if delivery_qc
      errors << "ready closeout requires a complete delivery QC measurement" unless delivery_qc["status"] == "measurement_complete"
      errors << "delivery QC report has unresolved measurement issues" unless Array(delivery_qc["issues"]).empty?
      tooling = delivery_qc["tooling"].is_a?(Hash) ? delivery_qc["tooling"] : {}
      tool_script_path = verify_binding(
        tooling["script"],
        delivery_qc_path,
        "delivery QC tooling script",
        errors,
        same_run: false
      )
      errors << "delivery QC report was not produced by the current delivery-QC script bytes" unless same_path?(tool_script_path, DELIVERY_QC_SCRIPT)
      report_schema_path = verify_binding(
        tooling["report_schema"],
        delivery_qc_path,
        "delivery QC report schema",
        errors,
        same_run: false
      )
      errors << "delivery QC report does not bind the current delivery-QC schema bytes" unless same_path?(report_schema_path, DELIVERY_QC_SCHEMA)
      delivery_bindings = delivery_qc["source_bindings"].is_a?(Hash) ? delivery_qc["source_bindings"] : {}
      require_matching_binding(
        delivery_bindings["master_video"],
        delivery_qc_path,
        master_path,
        master_path && sha256_file(master_path),
        "delivery QC master video",
        errors
      )
      require_matching_binding(
        delivery_bindings["recipe"],
        delivery_qc_path,
        recipe_path,
        recipe_path && sha256_file(recipe_path),
        "delivery QC final recipe",
        errors
      )
      require_matching_binding(
        delivery_bindings["selected_audio"],
        delivery_qc_path,
        selected_audio_path,
        recipe&.dig("audio_program", "sha256"),
        "delivery QC selected audio",
        errors
      )

      comparison = delivery_qc["program_comparison"].is_a?(Hash) ? delivery_qc["program_comparison"] : {}
      errors << "delivery QC expected frames do not match render manifest" unless comparison["expected_program_frames"] == render_spec["expected_frame_count"]
      errors << "delivery QC observed frames do not match final master" unless comparison["observed_program_frames"] == output["frame_count"]
      errors << "delivery QC frame-count comparison is not true" unless comparison["program_frame_count_matches"] == true
      errors << "delivery QC FPS comparison is not true" unless comparison["fps_matches"] == true
      if fps && comparison["duration_delta_frames"].is_a?(Numeric) &&
         comparison["duration_delta_frames"].to_f.abs > 0.5
        errors << "delivery QC program duration differs from the recipe by more than half a frame"
      end
      geometry = comparison["geometry"].is_a?(Hash) ? comparison["geometry"] : {}
      %w[width_matches height_matches sample_aspect_ratio_matches pixel_format_matches].each do |field|
        errors << "delivery QC geometry #{field} is not true" unless geometry[field] == true
      end
      delivery_encoding = comparison["delivery_encoding"].is_a?(Hash) ? comparison["delivery_encoding"] : {}
      %w[container_matches video_codec_matches audio_codec_matches].each do |field|
        errors << "delivery QC encoding #{field} is not true" unless delivery_encoding[field] == true
      end
      errors << "delivery QC expected container does not match recipe" unless delivery_encoding["expected_container"].to_s.downcase == recipe_mezzanine["container"].to_s.downcase
      errors << "delivery QC observed container does not match final master" unless delivery_encoding["observed_container_from_extension"].to_s.downcase == final_master["container"].to_s.downcase
      errors << "delivery QC expected video codec does not match recipe" unless render_video_codec(delivery_encoding["expected_video_codec"]) == render_video_codec(recipe_mezzanine["video_codec"])
      errors << "delivery QC observed video codec does not match final master" unless probed_video_codec(delivery_encoding["observed_video_codec"]) == probed_video_codec(final_master["video_codec"])
      errors << "delivery QC expected audio codec does not match recipe" unless delivery_encoding["expected_audio_codec"].to_s.downcase == recipe_mezzanine["audio_codec"].to_s.downcase
      errors << "delivery QC observed audio codec does not match final master" unless delivery_encoding["observed_audio_codec"].to_s.downcase == final_master["audio_codec"].to_s.downcase
      color_comparison = comparison["color_metadata"].is_a?(Hash) ? comparison["color_metadata"] : {}
      %w[color_range color_space color_transfer color_primaries].each do |field|
        errors << "delivery QC color #{field} comparison is not true" unless color_comparison.dig(field, "matches") == true
        errors << "delivery QC expected color #{field} does not match recipe" unless color_comparison.dig(field, "expected").to_s == recipe_color_delivery[field].to_s
        errors << "delivery QC observed color #{field} does not match final master" unless color_comparison.dig(field, "observed").to_s == color_tags[field].to_s
      end

      report_video = delivery_qc["video_probe"].is_a?(Hash) ? delivery_qc["video_probe"] : {}
      {
        "width" => final_master["width"],
        "height" => final_master["height"],
        "pixel_format" => final_master["pixel_format"]
      }.each do |field, expected|
        errors << "delivery QC video probe #{field} does not match final master" unless report_video[field] == expected
      end
      errors << "delivery QC video probe codec does not match final master" unless probed_video_codec(report_video["codec"]) == probed_video_codec(final_master["video_codec"])
      errors << "delivery QC video probe sample-aspect ratio does not match final master" unless report_video["sample_aspect_ratio"].to_s.tr(":", "/") == final_master["sample_aspect_ratio"].to_s.tr(":", "/")
      report_video_color = report_video["color"].is_a?(Hash) ? report_video["color"] : {}
      %w[color_range color_space color_transfer color_primaries].each do |field|
        errors << "delivery QC video probe #{field} does not match final master" unless report_video_color[field].to_s == color_tags[field].to_s
      end

      master_audio_probe = delivery_qc["master_audio_probe"].is_a?(Hash) ? delivery_qc["master_audio_probe"] : {}
      selected_audio_probe = delivery_qc["selected_audio_probe"].is_a?(Hash) ? delivery_qc["selected_audio_probe"] : {}
      errors << "delivery QC master-audio codec does not match final master" unless master_audio_probe["codec"].to_s.downcase == final_master["audio_codec"].to_s.downcase
      %w[sample_rate channel_layout].each do |field|
        errors << "delivery QC master-audio #{field} does not match final recipe" unless master_audio_probe[field].to_s == audio_program[field].to_s
        selected_value = selected_audio_probe[field].to_s
        unless %w[unknown N/A].include?(selected_value) || selected_value == audio_program[field].to_s
          errors << "delivery QC selected-audio #{field} does not match final recipe"
        end
      end

      report_master_audio = delivery_qc.dig("audio_measurements", "master") || {}
      report_loudness = report_master_audio["loudness"].is_a?(Hash) ? report_master_audio["loudness"] : {}
      report_samples = report_master_audio["decoded_samples"].is_a?(Hash) ? report_master_audio["decoded_samples"] : {}
      report_silence = report_master_audio["silence"].is_a?(Hash) ? report_master_audio["silence"] : {}
      {
        "integrated_lufs" => report_loudness["integrated_lufs"],
        "lra_lu" => report_loudness["loudness_range_lu"],
        "true_peak_dbtp" => report_loudness["true_peak_dbtp"],
        "clipping_sample_count" => report_samples["samples_at_or_above_threshold"],
        "lead_silence_seconds" => report_silence["lead_silence_seconds"],
        "trail_silence_seconds" => report_silence["trail_silence_seconds"]
      }.each do |field, report_value|
        errors << "professional audio QC #{field} does not match delivery report" unless audio_qc[field] == report_value
      end
      black_silence_qc = professional_qc["black_silence"].is_a?(Hash) ? professional_qc["black_silence"] : {}
      candidate_counts = {
        "black" => Array(delivery_qc.dig("video_measurements", "blackdetect", "intervals")).length,
        "silence" => Array(report_silence["intervals"]).length
      }
      candidate_counts.each do |kind, measured_count|
        candidate_field = "#{kind}_candidate_interval_count"
        intentional_field = "intentional_#{kind}_interval_count"
        unintended_field = "unintended_#{kind}_interval_count"
        declared_count = black_silence_qc[candidate_field]
        if declared_count.nil?
          errors << "professional black/silence QC must classify #{kind} candidates from the delivery report" if measured_count.positive?
          next
        end
        errors << "professional #{kind} candidate count does not match delivery report" unless declared_count == measured_count
        intentional_count = black_silence_qc[intentional_field]
        unintended_count = black_silence_qc[unintended_field]
        unless intentional_count.is_a?(Integer) && unintended_count.is_a?(Integer) &&
               intentional_count + unintended_count == measured_count
          errors << "professional #{kind} candidate dispositions do not account for every measured interval"
        end
      end
      if candidate_counts.values.any?(&:positive?) && blank?(black_silence_qc["candidate_disposition_note"])
        errors << "professional black/silence QC candidate_disposition_note is required when candidates exist"
      end
      delivery_delta = delivery_qc.dig("audio_measurements", "delivery_delta") || {}
      errors << "delivery QC master/selected sample rates disagree" unless delivery_delta["sample_rate_matches"] == true
      unless %w[unknown N/A].include?(selected_audio_probe["channel_layout"].to_s) ||
             delivery_delta["channel_layout_matches"] == true
        errors << "delivery QC master/selected channel layouts disagree"
      end
      target = delivery_qc["target_comparison"].is_a?(Hash) ? delivery_qc["target_comparison"] : {}
      audio_targets = recipe&.dig("delivery_policy", "audio_qc_targets") || {}
      errors << "delivery QC normalization policy does not match recipe" unless target["normalization_policy"].to_s == audio_targets["normalization_policy"].to_s
      errors << "delivery QC integrated-LUFS target does not match recipe" unless target["integrated_lufs_target"] == audio_targets["integrated_lufs_target"]
      errors << "delivery QC true-peak ceiling does not match recipe" unless target["true_peak_ceiling_dbtp"] == audio_targets["true_peak_ceiling_dbtp"]
      errors << "delivery QC measured true peak does not match professional QC" unless target["measured_true_peak_dbtp"] == audio_qc["true_peak_dbtp"]
      errors << "delivery QC true peak exceeds the recipe ceiling" unless target["true_peak_within_ceiling"] == true

      retime_qc = professional_qc["retime_cadence"].is_a?(Hash) ? professional_qc["retime_cadence"] : {}
      cadence = delivery_qc.dig("video_measurements", "frame_hash_cadence") || {}
      errors << "delivery QC frame-hash cadence measurement is incomplete" unless cadence["status"] == "measured"
      errors << "professional retimed-segment count does not match delivery report" unless retime_qc["retimed_segment_count"] == Array(delivery_qc.dig("retime_cadence", "recipe_retimed_segments")).length
      errors << "professional duplicate-candidate count does not match delivery report" unless retime_qc["duplicate_candidate_count"] == cadence["adjacent_exact_duplicate_pairs"]
    end
  end

  cutpoint_path = verify_binding(
    professional_qc["frame_step_cutpoint_manifest"],
    closeout_path,
    "closeout.professional_qc.frame_step_cutpoint_manifest",
    errors
  )
  if cutpoint_path
    validate_schema(CUTPOINT_MANIFEST_SCHEMA, cutpoint_path, "cutpoint frame-step manifest", errors)
    cutpoint_manifest = load_mapping(cutpoint_path, "cutpoint frame-step manifest", errors)
    if cutpoint_manifest
      cutpoint_video = cutpoint_manifest["rendered_video"].is_a?(Hash) ? cutpoint_manifest["rendered_video"] : {}
      require_matching_binding(
        cutpoint_video,
        cutpoint_path,
        master_path,
        master_path && sha256_file(master_path),
        "cutpoint manifest rendered video",
        errors
      )
      errors << "cutpoint manifest FPS does not match final master" unless rational_fps(cutpoint_video["fps"]) == fps
      errors << "cutpoint manifest frame count does not match final master" unless cutpoint_video["frame_count"] == final_master["frame_count"]
      if fps && cutpoint_video["observed_fps_float"].is_a?(Numeric) &&
         (cutpoint_video["observed_fps_float"].to_f - fps.to_f).abs > 0.001
        errors << "cutpoint manifest observed FPS differs from the final timebase"
      end
      require_matching_binding(
        cutpoint_manifest["plan"],
        cutpoint_path,
        marker_path,
        marker_path && sha256_file(marker_path),
        "cutpoint manifest marker plan",
        errors
      )
      recipe_timeline = Array(recipe && recipe["timeline"])
      expected_boundaries = recipe_timeline.each_cons(2).map do |outgoing, incoming|
        {
          "from_slot" => outgoing["slot"],
          "to_slot" => incoming["slot"],
          "cut_frame" => incoming["output_in_frame"]
        }
      end
      entries = Array(cutpoint_manifest["entries"])
      errors << "cutpoint manifest boundary count does not match the final recipe" unless entries.length == expected_boundaries.length
      boundary_ids = entries.each_with_object([]) do |entry, ids|
        ids << entry["boundary_id"] if entry.is_a?(Hash)
      end
      errors << "cutpoint manifest boundary ids are not unique" unless boundary_ids.uniq.length == boundary_ids.length
      entries.zip(expected_boundaries).each_with_index do |(entry, expected), index|
        next unless entry.is_a?(Hash) && expected

        label = "cutpoint manifest entries[#{index}]"
        %w[from_slot to_slot cut_frame].each do |field|
          errors << "#{label}.#{field} does not match the final recipe boundary" unless entry[field] == expected[field]
        end
        errors << "#{label}.requested_offsets must be #{CUTPOINT_FRAME_OFFSETS.inspect}" unless entry["requested_offsets"] == CUTPOINT_FRAME_OFFSETS
        errors << "#{label} has an incomplete review window" unless entry["window_status"] == "complete" && Array(entry["missing_offsets"]).empty?
        expected_frames = CUTPOINT_FRAME_OFFSETS.map { |offset| expected["cut_frame"] + offset }
        errors << "#{label}.captured_frames do not match the required frame-step window" unless entry["captured_frames"] == expected_frames
        sheet_path = resolve_required_file(entry["sheet"], cutpoint_path, "#{label}.sheet", errors)
        verify_sha(sheet_path, entry["sheet_sha256"], "#{label}.sheet", errors) if sheet_path
        unless sheet_path && declared_cutpoint_sheets.any? { |declared| same_path?(sheet_path, declared) }
          errors << "#{label}.sheet is not registered in closeout.qc_artifacts.cutpoint_sheets"
        end
      end
    end
  end

  derivative_ids = []
  Array(closeout["platform_derivatives"]).each_with_index do |derivative, index|
    next unless derivative.is_a?(Hash)

    label = "closeout.platform_derivatives[#{index}]"
    derivative_ids << derivative["derivative_id"].to_s
    derivative_path = resolve_required_file(derivative["path"], closeout_path, "#{label}.path", errors)
    verify_sha(derivative_path, derivative["sha256"], label, errors) if derivative_path
    errors << "#{label} is not derived from the final-master digest" unless derivative["derived_from_master_sha256"].to_s == final_master["sha256"].to_s
    errors << "#{label} must not reuse the final-master path" if same_path?(derivative_path, master_path)
  end
  errors << "platform derivative ids must be unique" unless derivative_ids.uniq.length == derivative_ids.length
  if closeout.dig("social_derivative_policy", "public_source") == "platform_derivative_from_final" && derivative_ids.empty?
    errors << "platform_derivative_from_final requires at least one hash-bound platform derivative"
  end
end

options = { mode: "readiness" }
parser = OptionParser.new do |opts|
  opts.banner = "usage: scripts/validate_edit_map_readiness.rb [--mode readiness|final-render|closeout] PATH_TO_04-edit-map.yaml"
  opts.on("--mode MODE", %w[readiness final-render closeout], "Validation depth") do |mode|
    options[:mode] = mode
  end
end
begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "ERROR: #{e.message}"
  warn parser
  exit 2
end
edit_map_arg = ARGV.shift
if edit_map_arg.nil? || !ARGV.empty?
  warn parser
  exit 2
end

edit_map_path = resolve_path(edit_map_arg)
edit_map = load_yaml_hash(edit_map_path)
errors = []
warnings = []

validate_schema(EDIT_MAP_SCHEMA, edit_map_path, "edit map", errors)
marker_plan_path = verify_binding(
  edit_map["edit_marker_plan_ref"],
  edit_map_path,
  "edit_marker_plan_ref",
  errors
)
if marker_plan_path
  run_validator(
    [
      VIDEO_PYTHON.to_s,
      MARKER_PLAN_VALIDATOR.to_s,
      marker_plan_path.to_s,
      "--require-v6"
    ],
    "active v6 edit marker plan validation",
    errors
  )

  marker_plan = load_yaml_hash(marker_plan_path)
  unless edit_map["screen_progression_projection"] == marker_plan["screen_progression_projection"]
    errors << "edit-map must exact-carry the marker-plan screen_progression_projection"
  end
  marker_nodes = Array(marker_plan["timeline_slots"]).each_with_object([]) do |slot, nodes|
    next unless slot.is_a?(Hash)

    node = slot.dig("source_lineage", "screen_progression_node")
    nodes << node if node
  end
  marker_nodes_by_id = marker_nodes.to_h { |node| [node["screen_progression_node_id"].to_s, node] }
  Array(edit_map["edit_unit_screen_progression_nodes"]).each_with_index do |node, index|
    next unless node.is_a?(Hash)

    expected = marker_nodes_by_id[node["screen_progression_node_id"].to_s]
    projected = node.reject { |key, _value| key == "edit_unit_id" }
    errors << "edit_unit_screen_progression_nodes[#{index}] is not reverse-reachable to the marker-plan node" unless expected == projected
  end
end

status_text = edit_map["status"].to_s
errors << "top-level edit status is not final-ready: #{status_text}" if status_text.match?(REJECT_STATUS_PATTERN)
if options[:mode] == "final-render" && !FINAL_RENDER_TOP_STATUSES.include?(status_text)
  errors << "top-level edit status must be one of #{FINAL_RENDER_TOP_STATUSES.join(', ')} for final-render mode (got #{status_text.inspect})"
elsif options[:mode] == "closeout" && !CLOSEOUT_TOP_STATUSES.include?(status_text)
  errors << "top-level edit status must be one of #{CLOSEOUT_TOP_STATUSES.join(', ')} for closeout mode (got #{status_text.inspect})"
end

manual = edit_map["manual_adjustment_workflow"]
if manual.is_a?(Hash)
  current_final_recipe = manual["current_final_recipe"]
  if blank?(current_final_recipe)
    errors << "manual_adjustment_workflow.current_final_recipe is blank; no final edit recipe is locked"
  elsif !readable_file?(current_final_recipe)
    errors << "manual_adjustment_workflow.current_final_recipe is not readable: #{current_final_recipe}"
  end

  active_candidate_status = manual["active_candidate_status"].to_s
  if %w[final-render closeout].include?(options[:mode]) && !FINAL_CANDIDATE_PASS_STATUSES.include?(active_candidate_status)
    errors << "manual_adjustment_workflow.active_candidate_status must explicitly pass for #{options[:mode]} mode; allowed=#{FINAL_CANDIDATE_PASS_STATUSES.join(', ')} got=#{active_candidate_status.inspect}"
  elsif active_candidate_status.match?(REVIEW_STATUS_PATTERN)
    errors << "active edit candidate still needs review or is held: #{active_candidate_status}"
  elsif active_candidate_status.match?(REJECT_STATUS_PATTERN)
    errors << "active edit candidate is rejected/failed: #{active_candidate_status}"
  end

  %w[
    current_recut_recipe
    current_recut_preview
    current_recut_review
    regeneration_prompt_for_true_b01_repair
  ].each do |field|
    path = manual[field]
    next if blank?(path)

    warnings << "#{field} is declared but not readable: #{path}" unless readable_file?(path)
  end
else
  errors << "manual_adjustment_workflow is missing or not a mapping"
end

shards = edit_map.dig("section_workflow", "shards")
if shards.is_a?(Array)
  nonready = shards.select do |shard|
    next true unless shard.is_a?(Hash)

    !READY_SHARD_STATUSES.include?(shard["status"].to_s)
  end
  unless nonready.empty?
    status_counts = count_by_status(nonready).sort.map { |status, count| "#{status}=#{count}" }.join(", ")
    sample = nonready.first(8).map { |shard| "#{shard['shard_id']}:#{shard['status']}" }.join(", ")
    errors << "#{nonready.length} section shard(s) are not ready for merge (#{status_counts}); sample: #{sample}"
  end
  ready_missing_story_fields = shards.select do |shard|
    next false unless shard.is_a?(Hash) && READY_SHARD_STATUSES.include?(shard["status"].to_s)

    REQUIRED_READY_SHARD_FIELDS.any? { |field| blank?(shard[field]) }
  end
  unless ready_missing_story_fields.empty?
    sample = ready_missing_story_fields.first(8).map do |shard|
      missing = REQUIRED_READY_SHARD_FIELDS.select { |field| blank?(shard[field]) }.join("/")
      "#{shard['shard_id']}:#{missing}"
    end.join(", ")
    errors << "#{ready_missing_story_fields.length} ready section shard(s) are missing story/director continuity fields: #{sample}"
  end
else
  warnings << "section_workflow.shards is missing; non-sharded edit readiness will depend on final recipe only"
end

rough_outputs = edit_map["rough_outputs"]
if rough_outputs.is_a?(Array)
  review_outputs = rough_outputs.select do |output|
    output.is_a?(Hash) && output["status"].to_s.match?(REVIEW_STATUS_PATTERN)
  end
  rejected_outputs = rough_outputs.select do |output|
    output.is_a?(Hash) && output["status"].to_s.match?(REJECT_STATUS_PATTERN)
  end
  unless review_outputs.empty?
    sample = review_outputs.first(8).map { |output| "#{output['output_id']}:#{output['status']}" }.join(", ")
    errors << "#{review_outputs.length} rough output(s) still need founder/playback review or are timing tests; sample: #{sample}"
  end
  unless rejected_outputs.empty?
    warnings << "#{rejected_outputs.length} rough output(s) are rejected evidence and must not be promoted as final edit truth"
  end
else
  errors << "rough_outputs is missing or not an array"
end

final_context = {}
if options[:mode] == "final-render" || options[:mode] == "closeout"
  # Pre-render revalidates the mutable 04 recipe/FX dependencies. Closeout uses
  # the immutable compile and render receipts instead: updating the edit-map
  # index after render must not invalidate the historical pre-render lock.
  final_context = validate_final_render_mode(
    edit_map,
    edit_map_path,
    errors,
    revalidate_pre_render_sources: options[:mode] == "final-render"
  )
end
validate_closeout_mode(edit_map, edit_map_path, final_context, errors) if options[:mode] == "closeout"

if errors.empty?
  case options[:mode]
  when "final-render"
    puts "OK: edit map v4, recipe v3, completed 04FX audit, and final compile bytes are ready for final render"
  when "closeout"
    puts "OK: edit closeout v3, Edit Recipe v3 render lineage, final master bytes, and professional QC evidence are ready for 05"
  else
    puts "OK: edit map has a readable locked final recipe and no non-ready shard/candidate state detected"
  end
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
