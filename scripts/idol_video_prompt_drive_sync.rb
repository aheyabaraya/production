#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_handoff_keys"

options = {
  run: nil,
  pass_date: Date.today.iso8601,
  album_key: "aurora-m",
  title_key: nil,
  write: false,
  founder_requested: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: scripts/idol_video_prompt_drive_sync.rb RUN_ROOT [--album-key ALBUM_KEY] [--title-key TITLE_KEY] [--pass-date YYYY-MM-DD] [--write]"
  opts.on("--run PATH", "Run root. Alternative to positional RUN_ROOT.") { |value| options[:run] = value }
  opts.on("--pass-date DATE", "Founder pass / sync date. Defaults to today.") { |value| options[:pass_date] = value }
  opts.on("--album-key KEY", "Stable album key for catalog/albums. Defaults to aurora-m.") { |value| options[:album_key] = IdolHandoffKeys.slug(value) }
  opts.on("--title-key KEY", "Stable title-song key for Drive mirror. Defaults to CONTENT_ID slug.") { |value| options[:title_key] = value }
  opts.on("--write", "Write Drive mirror outputs. Without this, run a dry check.") { options[:write] = true }
  opts.on("--founder-requested", "Confirm the founder explicitly requested this Drive handoff mirror.") { options[:founder_requested] = true }
end

parser.parse!

run = options[:run] || ARGV.shift
abort parser.to_s unless run

unless options[:pass_date].match?(/\A\d{4}-\d{2}-\d{2}\z/)
  abort "pass date must be YYYY-MM-DD"
end

if options[:write] && !options[:founder_requested]
  abort "refusing to write video prompt Drive handoff without --founder-requested"
end

run_path = File.expand_path(run)
content_id = File.basename(run_path)
album_key = IdolHandoffKeys.slug(options[:album_key])
title_key = IdolHandoffKeys.title_key(options[:title_key], fallback: content_id)
title_output_registry_path = File.join("catalog/albums", album_key, title_key, "output-registry.yaml")
video_prompt_dir = File.join(run_path, "generations", "video-prompts")
index_path = File.join(video_prompt_dir, "video-prompt-index.yaml")
review_path = File.join(run_path, "03-review.yaml")
python_bin = File.exist?(".venv-video/bin/python") ? ".venv-video/bin/python" : "python3"

abort "missing video prompt directory: #{video_prompt_dir}" unless Dir.exist?(video_prompt_dir)
abort "missing video prompt index: #{index_path}" unless File.file?(index_path)
index_for_review_path = YAML.load_file(index_path) || {}
unless File.file?(review_path)
  indexed_review_path = index_for_review_path["source_review_record_path"].to_s
  unless indexed_review_path.empty?
    indexed_review = Pathname.new(indexed_review_path)
    review_path = if indexed_review.absolute?
                    indexed_review.cleanpath.to_s
                  else
                    Pathname.new(Dir.pwd).join(indexed_review).cleanpath.to_s
                  end
  end
end
abort "missing review file: #{review_path}" unless File.file?(review_path)

validator = ["ruby", "scripts/validate_video_prompt_index.rb", index_path, review_path]
validator_stdout, validator_stderr, validator_status = Open3.capture3(*validator)
unless validator_status.success?
  abort [validator_stderr, validator_stdout].reject(&:empty?).join("\n")
end

asset_sync_command = [
  python_bin,
  "scripts/idol_asset_drive_sync.py",
  "--sync-date",
  options[:pass_date]
]
asset_sync_command << "--write" if options[:write]
asset_sync_command << "--founder-requested" if options[:founder_requested]
asset_sync_stdout, asset_sync_stderr, asset_sync_status = Open3.capture3(*asset_sync_command)
abort asset_sync_stderr unless asset_sync_status.success?
asset_sync_result = JSON.parse(asset_sync_stdout)

drive_root = "drive-sync/02_GPT_GROK_HANDOFF"
destination_parent = File.join(drive_root, "03-review_#{title_key}_video-prompts", content_id)
destination_prompt_dir = File.join(destination_parent, "video-prompts")
destination_input_pack_dir = File.join(destination_parent, "video-input-packs")
destination_upload_ready_dir = File.join(destination_parent, "upload-ready")
motion_reference_intake_sources = Dir.glob(File.join(run_path, "review", "03v-motion-reference-intake-v*"))
  .select { |path| File.directory?(path) }
  .sort
motion_reference_intake_source = motion_reference_intake_sources.last
motion_reference_intake_destination = File.join(destination_parent, "motion-reference-intake")
copy_bridge_source = "handoff/grok/video-prompts.md"
copy_bridge_destination = File.join(destination_parent, "00-copy-paste-video-prompts.md")
readme_path = File.join(destination_parent, "README.md")

prompt_files = Dir.glob(File.join(video_prompt_dir, "**", "*")).select { |path| File.file?(path) }
prompt_markdown_count = prompt_files.count { |path| File.extname(path) == ".md" }
index = YAML.load_file(index_path)

repo_root = Pathname.new(Dir.pwd)
video_prompt_root = Pathname.new(video_prompt_dir).realpath

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def resolve_repo_path(path, repo_root)
  raw = Pathname.new(path.to_s)
  raw.absolute? ? raw.cleanpath : repo_root.join(raw).cleanpath
end

def upload_pack_root_for(folder)
  return nil unless folder

  current = folder.cleanpath
  6.times do
    return current if File.file?((current + "PACK_INDEX.csv").to_s)

    parent = current.dirname
    break if parent == current

    current = parent
  end
  nil
end

def relative_to_root(path, root)
  Pathname.new(path).relative_path_from(root).to_s
rescue ArgumentError
  nil
end

def upload_ready_source_for(index, repo_root)
  explicit = index.dig("record_rule", "founder_operator_surface").to_s
  explicit_path = blank?(explicit) ? nil : resolve_repo_path(explicit, repo_root)
  return explicit_path if explicit_path && Dir.exist?(explicit_path.to_s)

  source_of_truth = index.dig("record_rule", "source_of_truth").to_s
  return nil if blank?(source_of_truth)

  candidate = resolve_repo_path(File.join(source_of_truth, "upload-ready"), repo_root)
  Dir.exist?(candidate.to_s) ? candidate : nil
end

upload_ready_source = upload_ready_source_for(index, repo_root)
upload_ready_file_count = upload_ready_source ? Dir.glob(File.join(upload_ready_source.to_s, "**", "*")).count { |path| File.file?(path) } : 0

indexed_prompt_paths = Array(index["prompts"]).map do |record|
  next unless record.is_a?(Hash)

  record["output_prompt_path"]
end.compact

indexed_prompt_sources = indexed_prompt_paths.map do |path|
  source = resolve_repo_path(path, repo_root)
  abort "indexed prompt is missing: #{path}" unless File.file?(source)

  relative = relative_to_root(source.realpath, video_prompt_root)
  abort "indexed prompt is outside video prompt directory: #{path}" if relative.nil? || relative.start_with?("../")

  [source.to_s, relative]
end

upload_pack_sources = Array(index["prompts"]).map do |record|
  next unless record.is_a?(Hash)

  folder_value = record["upload_pack_folder"].to_s
  next if blank?(folder_value)

  folder = resolve_repo_path(folder_value, repo_root)
  abort "upload_pack_folder is missing: #{folder_value}" unless Dir.exist?(folder.to_s)

  pack_root = upload_pack_root_for(folder)
  abort "PACK_INDEX.csv is missing for upload_pack_folder: #{folder_value}" unless pack_root

  [pack_root.to_s, pack_root.basename.to_s]
end.compact.uniq

upload_pack_destinations = upload_pack_sources.map do |(_source_root, pack_name)|
  File.join(destination_input_pack_dir, pack_name)
end

upload_pack_file_count = upload_pack_sources.sum do |source_root, _pack_name|
  Dir.glob(File.join(source_root, "**", "*")).count { |path| File.file?(path) }
end

indexed_path_counts = indexed_prompt_sources.each_with_object(Hash.new(0)) do |(_source, relative), counts|
  counts[relative] += 1
end
duplicate_indexed_paths = indexed_path_counts.select { |_path, count| count > 1 }.keys
abort "duplicate indexed prompt output paths: #{duplicate_indexed_paths.join(", ")}" unless duplicate_indexed_paths.empty?

if options[:write]
  index["handoff_copy"] ||= {}
  index["handoff_copy"]["updated"] = File.file?(copy_bridge_source)
  index["handoff_copy"]["path"] = copy_bridge_source
  index["handoff_copy"]["note"] = "Copied into Drive mirror when present."
  index["drive_sync_mirror"] ||= {}
  index["drive_sync_mirror"]["updated"] = true
  index["drive_sync_mirror"]["path"] = destination_parent + "/"
  index["drive_sync_mirror"]["note"] = "Created by scripts/idol_video_prompt_drive_sync.rb after validation."
  File.write(index_path, YAML.dump(index))

  FileUtils.rm_rf(destination_parent)
  FileUtils.mkdir_p(destination_parent)
  FileUtils.mkdir_p(destination_prompt_dir)
  FileUtils.cp(index_path, File.join(destination_prompt_dir, "video-prompt-index.yaml"))
  indexed_prompt_sources.each do |source, relative|
    destination = File.join(destination_prompt_dir, relative)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination)
  end
  unless upload_pack_sources.empty?
    FileUtils.mkdir_p(destination_input_pack_dir)
    upload_pack_sources.each do |source_root, pack_name|
      destination = File.join(destination_input_pack_dir, pack_name)
      FileUtils.rm_rf(destination)
      FileUtils.cp_r(source_root, destination)
    end
  end
  if upload_ready_source
    FileUtils.rm_rf(destination_upload_ready_dir)
    FileUtils.cp_r(upload_ready_source.to_s, destination_upload_ready_dir)
  end

  if File.file?(copy_bridge_source)
    FileUtils.cp(copy_bridge_source, copy_bridge_destination)
  end
  if motion_reference_intake_source
    FileUtils.mkdir_p(motion_reference_intake_destination)
    intake_entries = Dir.glob(File.join(motion_reference_intake_source, "*"))
    FileUtils.cp_r(intake_entries, motion_reference_intake_destination) unless intake_entries.empty?
  end

  ([index_path] + indexed_prompt_sources.map(&:first)).uniq.each do |path|
    stdout, stderr, status = Open3.capture3(
      python_bin,
      "scripts/idol_title_output_registry.py",
      "register-path",
      "--run",
      run,
      "--album-key",
      album_key,
      "--title-key",
      title_key,
      "--output-type",
      "video_prompt",
      "--path",
      path,
      "--source-step",
      "post_review_video",
      "--output-status",
      "exported",
      "--notes",
      "validated post-review video prompt source",
      "--write"
    )
    abort [stderr, stdout].reject(&:empty?).join("\n") unless status.success?
  end
  [
    [destination_parent, "03-review video prompt Drive mirror parent"],
    [destination_prompt_dir, "03-review video prompt Drive mirror prompt folder"],
    [readme_path, "03-review video prompt Drive mirror README"]
  ].tap do |paths|
    if upload_ready_source
      paths << [destination_upload_ready_dir, "03-review flat upload-ready mirror"]
    end
    upload_pack_destinations.each do |path|
      paths << [path, "03-review video input upload pack mirror"]
    end
    if motion_reference_intake_source
      paths << [motion_reference_intake_destination, "03-review video prompt motion reference intake mirror"]
    end
  end.each do |path, note|
    stdout, stderr, status = Open3.capture3(
      python_bin,
      "scripts/idol_title_output_registry.py",
      "register-path",
      "--run",
      run,
      "--album-key",
      album_key,
      "--title-key",
      title_key,
      "--output-type",
      "drive_handoff_package",
      "--path",
      path,
      "--source-step",
      "drive_sync",
      "--output-status",
      "exported",
      "--notes",
      note,
      "--write"
    )
    abort [stderr, stdout].reject(&:empty?).join("\n") unless status.success?
  end

  readme = <<~MARKDOWN
    # #{content_id} Video Prompt Drive Mirror

    Flow: `03-review/video-prompts`
    Title key: `#{title_key}`
    Sync date: `#{options[:pass_date]}`

    This folder is a Drive-facing mirror for founder/manual tool use. The
    canonical source remains in:

    `#{run}/generations/video-prompts/`

    ## Contents

    - `upload-ready/`: flat timeline-order manual upload queue. Use this first
      when the operator is uploading clips by hand.
    - `video-prompts/`: validated run-owned prompt files and index mirror
    - `video-input-packs/`: image upload packs for manual video generation;
      each `PACK_INDEX.csv` row is one video clip. `bridge-two-image` rows attach
      `@image1` and `@image2` together; `single-beat` rows attach only `@image1`.
    - `00-copy-paste-video-prompts.md`: optional copy-paste bridge when present
    - `motion-reference-intake/`: optional Drive-facing copy of run-owned
      GPT/reference motion images used only as video prompt motion guidance
    - Shared asset context:
      `drive-sync/02_GPT_GROK_HANDOFF/00_ASSET_CONTEXT/`

    ## Rule

    Edit the run-owned files first, validate `video-prompt-index.yaml`, then
    re-run the sync. Do not treat this Drive copy as source truth.
    If `upload-ready/` is present, use it as the human upload surface. Its
    canonical source remains under the run-owned video-prompt package.
    If `video-input-packs/` is present, its canonical source remains under
    `#{run}/generations/video-prompts/upload-packs/`; do not edit the Drive copy
    first.
    If `motion-reference-intake/` is present, its canonical source remains under
    `#{run}/review/03v-motion-reference-intake-vN/`; it does not patch 02A/02B
    and is not a paid image API input by default.
  MARKDOWN
  File.write(readme_path, readme)

  drive_readme = File.join(drive_root, "README.md")
  if File.file?(drive_readme)
    text = File.read(drive_readme)
    block = <<~MARKDOWN

      ### Active 03-Review Video Prompt Mirror

      ```text
      03-review_#{title_key}_video-prompts/#{content_id}/
      ```

      This is a Drive-facing mirror. Canonical video prompt files remain in
      `#{run}/generations/video-prompts/`.
    MARKDOWN
    if text.match?(/### Active 03-Review Video Prompt Mirror\n\n```text\n.*?\n```\n\nThis is a Drive-facing mirror.*?(?=\n### |\z)/m)
      text = text.sub(/### Active 03-Review Video Prompt Mirror\n\n```text\n.*?\n```\n\nThis is a Drive-facing mirror.*?(?=\n### |\z)/m, block.strip)
    else
      text = text.rstrip + "\n" + block
    end
    File.write(drive_readme, text)
  end

  manifest = "drive-sync/MANIFEST.md"
  if File.file?(manifest)
    package_entry = "- `02_GPT_GROK_HANDOFF/03-review_#{title_key}_video-prompts/#{content_id}/`"
    text = File.read(manifest)
    section = <<~MARKDOWN
      <!-- IDOL_VIDEO_PROMPT_MIRRORS_START -->
      Active video prompt mirrors:

      #{package_entry}
      <!-- IDOL_VIDEO_PROMPT_MIRRORS_END -->
    MARKDOWN
    if text.include?("<!-- IDOL_VIDEO_PROMPT_MIRRORS_START -->") && text.include?("<!-- IDOL_VIDEO_PROMPT_MIRRORS_END -->")
      text = text.sub(
        /<!-- IDOL_VIDEO_PROMPT_MIRRORS_START -->.*?<!-- IDOL_VIDEO_PROMPT_MIRRORS_END -->/m,
        section.strip
      )
    elsif text.include?("Templates and guidance:\n\n")
      text = text.sub("Templates and guidance:\n\n", "#{section}\n\nTemplates and guidance:\n\n")
    else
      text = text.rstrip + "\n\n" + section
    end
    File.write(manifest, text)
  end

  report_dir = File.join(run_path, "handoff")
  FileUtils.mkdir_p(report_dir)
end

result = {
  "write" => options[:write],
  "harness" => "video_prompt_drive_sync",
  "run" => run,
  "content_id" => content_id,
  "album_key" => album_key,
  "title_key" => title_key,
  "title_output_registry_path" => title_output_registry_path,
  "pass_date" => options[:pass_date],
  "founder_requested" => options[:founder_requested],
  "source_prompt_dir" => video_prompt_dir,
  "source_index" => index_path,
  "validator" => validator_stdout.strip,
  "asset_sync" => asset_sync_result,
  "prompt_file_count" => prompt_files.length,
  "prompt_markdown_count" => prompt_markdown_count,
  "indexed_prompt_count" => indexed_prompt_sources.length,
  "upload_ready_source" => upload_ready_source&.to_s,
  "upload_ready_destination" => upload_ready_source ? destination_upload_ready_dir : nil,
  "upload_ready_file_count" => upload_ready_file_count,
  "upload_pack_count" => upload_pack_sources.length,
  "upload_pack_file_count" => upload_pack_file_count,
  "destination" => destination_parent,
  "upload_pack_destinations" => upload_pack_destinations,
  "motion_reference_intake_source" => motion_reference_intake_source,
  "motion_reference_intake_destination" => motion_reference_intake_source ? motion_reference_intake_destination : nil,
  "copied_bridge" => File.file?(copy_bridge_source)
}

if options[:write]
  report_path = File.join(run_path, "handoff", "03-review-video-prompt-drive-sync-#{title_key}.json")
  result["report_path"] = report_path
  File.write(report_path, JSON.pretty_generate(result) + "\n")
end

puts JSON.pretty_generate(result)
