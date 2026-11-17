#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
COMMON_PREP = ROOT.join("scripts", "idol_prepare_video_prompt_authoring.rb")
SCHEMA = ROOT.join("schemas", "grok-video-prompt-reference-pack.schema.json")
SOURCE_PACK_SCHEMA = ROOT.join("schemas", "03v-authoring-source-pack.schema.json")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
PYTHON = ROOT.join("scripts", "idol-video-python")

options = {
  root: ROOT,
  run: nil,
  source_pack: nil,
  version: "v1",
  write: false,
  founder_requested: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prepare_grok_video_prompt_handoff.rb RUN_ROOT --source-pack PATH --founder-requested [options]"
  opts.on("--run PATH", "Run root. Alternative to positional RUN_ROOT.") { |value| options[:run] = value }
  opts.on("--root PATH", "Repository root.") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--source-pack PATH", "Written active 03V authoring source pack.") { |value| options[:source_pack] = value }
  opts.on("--version VERSION", "Local handoff label. Defaults to v1.") { |value| options[:version] = value }
  opts.on("--founder-requested", "Confirm that the Founder explicitly requested this optional Grok handoff.") { options[:founder_requested] = true }
  opts.on("--write", "Write local handoff files. No external call or video generation is performed.") { options[:write] = true }
end

begin
  parser.parse!
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

run_arg = options[:run] || ARGV.shift
if run_arg.to_s.strip.empty? || !ARGV.empty? || options[:source_pack].to_s.strip.empty?
  warn parser
  exit 2
end
abort "optional Grok handoff requires --founder-requested" unless options[:founder_requested]
abort "local handoff version must be a filename label of 1 to 64 letters, digits, dots, underscores or hyphens" unless options[:version].to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/)

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

def relative_path(path, root)
  path.relative_path_from(root).to_s
end

def checked_route!(path, root, kind:, allow_missing: false)
  abort "path must stay inside its declared owner" unless inside?(path, root)
  abort "owner must be an existing canonical directory" unless root.lstat.directory? && root.realpath == root
  current = root
  parts = path.relative_path_from(root).each_filename.to_a.reject { |part| part == "." }
  parts.each_with_index do |part, index|
    current = current.join(part)
    begin
      stat = current.lstat
    rescue Errno::ENOENT
      abort "required path is missing" unless allow_missing
      next
    end
    expected = index == parts.length - 1 ? kind : :directory
    abort "path must use regular files and directories without symlinks" unless expected == :file ? stat.file? : stat.directory?
  end
  abort "file path must name a leaf" if kind == :file && parts.empty?
  path
end

def read_owned_file(path, root)
  checked_route!(path, root, kind: :file)
  File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
    abort "input must be a regular file" unless file.stat.file?
    bytes = file.binmode.read
    checked_route!(path, root, kind: :file)
    stat = path.lstat
    abort "input changed while reading" unless [stat.dev, stat.ino] == [file.stat.dev, file.stat.ino]
    bytes
  end
end

def write_owned_outputs(outputs, handoff_root, run_path)
  checked_route!(handoff_root, run_path, kind: :directory, allow_missing: true)
  missing = []
  outputs.each do |path, bytes|
    abort "handoff output must be a direct child" unless path.parent == handoff_root
    checked_route!(path, run_path, kind: :file, allow_missing: true)
    if path.exist?
      abort "HOLD: same-label output differs; preserve it and reconcile the version" unless read_owned_file(path, run_path) == bytes.b
    else
      missing << [path, bytes]
    end
  end
  return if missing.empty?

  FileUtils.mkdir_p(handoff_root)
  missing.each do |path, bytes|
    checked_route!(path, run_path, kind: :file, allow_missing: true)
    # Exclusive creation preserves earlier output even if another writer arrived.
    # The four-file group is not a transaction; matching partial output can resume.
    File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.binmode.write(bytes)
      file.flush
      file.fsync
    end
  end
end

def load_mapping(path, bytes)
  value = YAML.safe_load(bytes, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
  raise TypeError, "#{path} must contain an object" unless value.is_a?(Hash)
  value
end

def validate_schema(document, schema: SCHEMA)
  Tempfile.create(["idol-grok-03v-reference-pack", ".yaml"]) do |file|
    file.write(YAML.dump(document))
    file.flush
    stdout, stderr, status = Open3.capture3(
      PYTHON.to_s,
      SCHEMA_VALIDATOR.to_s,
      schema.to_s,
      file.path,
      chdir: ROOT.to_s
    )
    return nil if status.success?
    return [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n").strip
  end
end

root = options[:root].expand_path.cleanpath
run_path = resolve_path(run_arg, root)
source_pack_path = resolve_path(options[:source_pack], root)
checked_route!(run_path, root, kind: :directory)
source_pack_bytes = read_owned_file(source_pack_path, run_path)

source_pack = load_mapping(source_pack_path, source_pack_bytes)
source_pack_schema_error = validate_schema(source_pack, schema: SOURCE_PACK_SCHEMA)
abort source_pack_schema_error if source_pack_schema_error
abort "source pack must be the ready active v5 pack" unless source_pack["schema_version"] == "idol_03v_authoring_source_pack.v5" &&
                                                            source_pack["status"] == "ready_for_model_authoring"
storyline_lineage_projection = source_pack["storyline_lineage_projection"]
abort "source pack must carry the complete PRE-00-rooted storyline lineage" unless storyline_lineage_projection.is_a?(Hash) &&
                                                                                  storyline_lineage_projection["projected_value"].is_a?(Hash)

source_by_role = Array(source_pack["sources"]).to_h { |row| [row["role"].to_s, row] }
required_roles = %w[master_storyboard prompt_packets production_cut_review audio_branch_cut_placement storyboard_assist]
abort "source pack must exact-cover the five active 03V sources" unless source_by_role.keys.sort == required_roles.sort

source_by_role.each do |role, row|
  path = resolve_path(row["path"], root)
  abort "#{role} source SHA-256 is stale" unless Digest::SHA256.hexdigest(read_owned_file(path, root)) == row["sha256"].to_s
end

common_command = [
  RbConfig.ruby,
  COMMON_PREP.to_s,
  run_path.to_s,
  "--root",
  root.to_s,
  "--master-storyboard",
  source_by_role.fetch("master_storyboard").fetch("path"),
  "--prompt-packets",
  source_by_role.fetch("prompt_packets").fetch("path"),
  "--production-cut-review",
  source_by_role.fetch("production_cut_review").fetch("path"),
  "--audio-branch-cut-placement",
  source_by_role.fetch("audio_branch_cut_placement").fetch("path"),
  "--storyboard-assist",
  source_by_role.fetch("storyboard_assist").fetch("path")
]
stdout, stderr, status = Open3.capture3(*common_command, chdir: root.to_s)
abort [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join("\n") unless status.success?
common_result = JSON.parse(stdout)
abort "source pack source-set SHA-256 drifted from active validation" unless common_result["source_set_sha256"] == source_pack["source_set_sha256"]

content_id = run_path.basename.to_s
handoff_root = run_path.join("handoff", "grok", "03V")
reference_pack_path = handoff_root.join("grok-03V-reference-pack-#{options[:version]}.yaml")
brief_path = handoff_root.join("grok-03V-brief-#{options[:version]}.md")
request_path = handoff_root.join("grok-03V-request-#{options[:version]}.md")
trigger_path = handoff_root.join("grok-03V-paste-trigger-#{options[:version]}.md")

reference_pack = {
  "schema_version" => "idol_grok_video_prompt_reference_pack.v7",
  "content_id" => content_id,
  "run_root" => relative_path(run_path, root),
  "status" => options[:write] ? "written" : "dry_run",
  "founder_requested" => true,
  "execution_mode" => "founder_paste_only",
  "source_pack" => {
    "path" => relative_path(source_pack_path, root),
    "sha256" => Digest::SHA256.hexdigest(source_pack_bytes)
  },
  "source_set_sha256" => source_pack["source_set_sha256"],
  "source_artifacts" => required_roles.map { |role| source_by_role.fetch(role) },
  "storyline_lineage_projection" => storyline_lineage_projection,
  "authoring_policy" => {
    "source_gate" => "passed_hash_bound_pixels_and_passed_storyboard_boards_only",
    "attachment_order" => "@image1_storyboard_then_@image2_@image3_optional_@image4_ordered_production_cut_originals",
    "board_authority" => "timing_blocking_subject_route_and_temporal_camera_motion",
    "production_cut_original_authority" => "pixels_identity_style_light_still_composition_and_visible_states",
    "source_union" => "official_core_or_branch",
    "same_parent_default" => true,
    "cross_core_rule" => "both_core_ids_and_continuity_reason_required",
    "camera_motion_owner" => "03V_after_passed_production_cut_review_and_audio_production_cut_placement",
    "creative_prompt_author" => "selected_Grok_surface_under_the_same_active_IDOL_contract",
    "one_section_per_owner" => true
  },
  "section_cohort_successions" => source_pack["section_cohort_successions"],
  "section_shards" => source_pack["section_shards"],
  "reference_files" => {
    "common_authoring_source_pack" => relative_path(source_pack_path, root),
    "local_brief" => relative_path(brief_path, root),
    "request_packet" => relative_path(request_path, root),
    "paste_trigger" => relative_path(trigger_path, root)
  },
  "automation_boundaries" => {
    "derived_handoff_only" => true,
    "canonical_source_mutation_allowed" => false,
    "paid_video_generation_approved" => false,
    "external_video_execution_approved" => false,
    "playback_pass_implied" => false,
    "edit_readiness_implied" => false
  }
}

schema_error = validate_schema(reference_pack)
abort schema_error if schema_error

brief = <<~MARKDOWN
  # Optional Grok 03V Brief

  Use the active source pack at `#{relative_path(source_pack_path, root)}`.
  Read its complete PRE-00-rooted storyline lineage first: immutable original,
  ordered full-text revisions, active full text, density review, and reference
  functions/exclusions. Never substitute a compact whole-film summary.
  Work one physical section at a time and preserve every bound hash and
  attachment order. `@image1` is the storyboard authority for timing, blocking,
  subject route, and temporal camera motion. `@image2` through optional
  `@image4` remain the exact pixel authority.

  Exact-carry each section shard's `section_cohort_id` and its CDD-P3-Ci to
  CDD-V-Ci successor binding. Author only the `idol_video_prompt_manifest.v8`
  creative fields. Camera motion
  belongs here because the passed pixels now exist. Do not reopen Front
  Planning, 01, 02A, or 02B unless the source pack reports a contradiction. Do
  not invent choreography, generate video, or infer paid/external approval.
MARKDOWN

request = <<~MARKDOWN
  # Optional Grok 03V Request

  Founder-requested local handoff: yes
  Reference pack: `#{relative_path(reference_pack_path, root)}`
  Common source pack: `#{relative_path(source_pack_path, root)}`

  Follow the active IDOL 03V contract and return one section-scoped
  `idol_video_prompt_manifest.v8` shard or a concrete hold. Preserve the exact
  `storyline_lineage_projection` value and hash. Keep all internal
  paths, hashes, ids, approvals, and process text outside generator-facing
  prompt prose.
MARKDOWN

trigger = <<~MARKDOWN
  # Grok Paste Trigger

  ```text
  Read AGENTS.md, then the active reference pack at
  #{relative_path(reference_pack_path, root)} and the common source pack at
  #{relative_path(source_pack_path, root)}. Author one physical 03V section
  shard under idol_video_prompt_manifest.v8. Do not generate video or mutate
  canonical upstream artifacts.
  ```
MARKDOWN

if options[:write]
  checked_route!(run_path, root, kind: :directory)
  abort "source pack changed before writing" unless read_owned_file(source_pack_path, run_path) == source_pack_bytes
  source_by_role.each do |role, row|
    path = resolve_path(row["path"], root)
    abort "#{role} source changed before writing" unless Digest::SHA256.hexdigest(read_owned_file(path, root)) == row["sha256"].to_s
  end
  write_owned_outputs({ reference_pack_path => YAML.dump(reference_pack), brief_path => brief,
                        request_path => request, trigger_path => trigger }, handoff_root, run_path)
end

puts JSON.pretty_generate(
  "write" => options[:write],
  "ready" => true,
  "run" => relative_path(run_path, root),
  "content_id" => content_id,
  "source_set_sha256" => source_pack["source_set_sha256"],
  "section_count" => Array(source_pack["section_shards"]).length,
  "reference_pack" => relative_path(reference_pack_path, root),
  "brief" => relative_path(brief_path, root),
  "request" => relative_path(request_path, root),
  "paste_trigger" => relative_path(trigger_path, root),
  "external_execution_approved" => false
)
