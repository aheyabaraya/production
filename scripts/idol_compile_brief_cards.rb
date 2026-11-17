#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "yaml"

options = {
  run: nil,
  pass_date: Date.today.iso8601,
  write: false,
  slot_index_path: nil,
  cue_sheet_path: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: scripts/idol_compile_brief_cards.rb RUN_ROOT [--pass-date YYYY-MM-DD] [--slot-index-path PATH] [--write]"
  opts.on("--run PATH", "Run root. Alternative to positional RUN_ROOT.") { |value| options[:run] = value }
  opts.on("--pass-date DATE", "Founder pass date for slot index. Defaults to today.") { |value| options[:pass_date] = value }
  opts.on("--slot-index-path PATH", "Output path for the post-review slot index.") { |value| options[:slot_index_path] = value }
  opts.on("--slot-briefs-path PATH", "Backward-compatible alias for --slot-index-path.") { |value| options[:slot_index_path] = value }
  opts.on("--cue-sheet-path PATH", "Cue sheet to use for slot lookup. Defaults to the parseable sheet with the most slots.") { |value| options[:cue_sheet_path] = value }
  opts.on("--write", "Write only a noncanonical work candidate and derived slot index; never rewrite 02A or 02B.") { options[:write] = true }
end

parser.parse!

run = options[:run] || ARGV.shift
abort parser.to_s unless run

unless options[:pass_date].match?(/\A\d{4}-\d{2}-\d{2}\z/)
  abort "pass date must be YYYY-MM-DD"
end

run_path = Pathname.new(run)
run_abs = run_path.expand_path
content_id = run_abs.basename.to_s
storyboard_path = run_abs.join("02A-master-storyboard.yaml")
packet_path = run_abs.join("02B-prompt-packets.yaml")
review_path = run_abs.join("03-review.yaml")
video_prompt_index_path = run_abs.join("generations", "video-prompts", "video-prompt-index.yaml")

abort "missing 02A master storyboard: #{storyboard_path}" unless storyboard_path.file?
abort "missing 02B prompt packets: #{packet_path}" unless packet_path.file?

slot_index_path = if options[:slot_index_path]
  Pathname.new(options[:slot_index_path]).expand_path
else
  run_abs.join("handoff", "slot-compile-index-#{options[:pass_date]}.yaml")
end

def rel(path)
  Pathname.new(path).expand_path.relative_path_from(Pathname.new(Dir.pwd)).to_s
end

def latest(path_glob)
  Dir.glob(path_glob).sort.last
end

def table_cells(line)
  line.to_s.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
end

def parse_cue_sheet(path)
  return {} unless path && File.file?(path)

  lines = File.readlines(path, encoding: "utf-8")
  rows = {}
  header_indexes = lines.each_index.select { |idx| lines[idx].start_with?("| Slot |") }
  header_indexes.each do |header_index|
    headers = table_cells(lines[header_index])
    lines[(header_index + 2)..].to_a.each do |line|
      break unless line.start_with?("|")

      cells = table_cells(line)
      next unless cells.length >= headers.length

      row = headers.zip(cells).to_h
      slot = row["Slot"].to_s
      rows[slot] = row unless slot.empty?
    end
  end
  rows
end

def best_cue_sheet(paths)
  paths.map do |path|
    rows = parse_cue_sheet(path)
    [path, rows]
  end.select { |_path, rows| rows.any? }
       .max_by { |path, rows| [rows.length, path.to_s] }
end

def time_to_seconds(value)
  text = value.to_s.strip
  return nil unless text.match?(/\A\d+:\d{2}(?:\.\d+)?\z/)

  minutes, seconds = text.split(":", 2)
  (minutes.to_i * 60) + seconds.to_f
end

def parse_time_range(value)
  start_text, end_text = value.to_s.split("-", 2).map { |part| part.to_s.strip }
  [time_to_seconds(start_text), time_to_seconds(end_text)]
end

def overlap_seconds(range_start, range_end, cue)
  cue_start = cue["absolute_start_seconds"]
  cue_end = cue["absolute_end_seconds"]
  return 0.0 if range_start.nil? || range_end.nil? || cue_start.nil? || cue_end.nil?

  [[range_end.to_f, cue_end.to_f].min - [range_start.to_f, cue_start.to_f].max, 0.0].max
end

def cue_slots_for_range(time_range, cue_records)
  range_start, range_end = parse_time_range(time_range)
  cue_records.map do |cue|
    [cue, overlap_seconds(range_start, range_end, cue)]
  end.select { |_cue, score| score.positive? }
             .sort_by { |cue, score| [-score, cue["absolute_start_seconds"].to_f] }
end

def short_source_key(source)
  source.to_s.split(/\s+/).first.to_s
end

def source_family(source, slot)
  text = source.to_s
  return "founder_insert" if text.start_with?("FOUNDER")
  return "new_duo_insert" if slot.to_s.match?(/[A-Z]\z/) || text.include?("DUO INSERT")
  return "new_tail_or_unit_generation" if text.start_with?("NEW")
  return "original_02b_derived" if text.match?(/\AB\d+/)

  "unmatched"
end

def cue_folder_for_slot(run_abs, slot)
  cues_root = run_abs.join("handoff", "02-03-grok-imagine-v12-webp", "cues")
  return nil unless cues_root.directory?

  candidate = Dir.glob(cues_root.join("#{slot}*").to_s).sort.find { |path| File.directory?(path) }
  candidate ? rel(candidate) : nil
end

def final_prompt_fingerprints(packets_doc, run_abs)
  rows = []
  (packets_doc["prompt_packets"] || []).each do |packet|
    packet_id = packet["packet_id"].to_s
    compiled = packet["compiled_prompt_block"] || {}
    storyboard = packet["storyboard_packet"] || {}
    rows << ["#{packet_id}.compiled_prompt_block.full_prompt_text", Digest::SHA256.hexdigest(compiled["full_prompt_text"].to_s)]
    rows << ["#{packet_id}.compiled_prompt_block.review_board_image_prompt_sentence", Digest::SHA256.hexdigest(compiled["review_board_image_prompt_sentence"].to_s)]
    rows << ["#{packet_id}.storyboard_packet.review_board_image_prompt", Digest::SHA256.hexdigest(storyboard["review_board_image_prompt"].to_s)]
  end
  Dir[run_abs.join("exports", "02B", "prompts-compile-v4", "*").to_s].sort.each do |path|
    rows << [rel(path), Digest::SHA256.file(path).hexdigest]
  end
  rows.to_h
end

def ref(path, fragment)
  "#{rel(path)}##{fragment}"
end

def run_rel(run_abs, path)
  Pathname.new(path).expand_path.relative_path_from(run_abs).to_s
end

storyboard = YAML.load_file(storyboard_path.to_s)
packets_doc = YAML.load_file(packet_path.to_s)
review = review_path.file? ? YAML.load_file(review_path.to_s) : {}
video_index = video_prompt_index_path.file? ? YAML.load_file(video_prompt_index_path.to_s) : {}
before_final_fingerprints = final_prompt_fingerprints(packets_doc, run_abs)

cue_bpm_path = latest(run_abs.join("research", "cue-bpm-map-v*.yaml").to_s)
cue_bpm_doc = cue_bpm_path ? YAML.load_file(cue_bpm_path) : {}
cue_records = cue_bpm_doc["cue_tempo_map"] || []
cue_bpm_run_ref = cue_bpm_path ? run_rel(run_abs, cue_bpm_path) : nil

audio_motion_path = latest(run_abs.join("research", "audio-motion-director-map-v*.yaml").to_s)
audio_motion_run_ref = audio_motion_path ? run_rel(run_abs, audio_motion_path) : nil

cue_sheet_candidates = Dir.glob(run_abs.join("handoff", "02-03-grok-imagine-*-webp", "00-review", "cue-sheet-v*.md").to_s).sort
if options[:cue_sheet_path]
  cue_sheet_path = Pathname.new(options[:cue_sheet_path]).expand_path.to_s
  cue_sheet_rows = parse_cue_sheet(cue_sheet_path)
  abort "cue sheet has no parseable Slot table rows: #{cue_sheet_path}" if cue_sheet_rows.empty?
else
  selected_cue_sheet = best_cue_sheet(cue_sheet_candidates)
  cue_sheet_path, cue_sheet_rows = selected_cue_sheet || [nil, {}]
end

expansion_by_beat = (storyboard.dig("packet_expansion_contract", "beat_expansion_index") || []).each_with_object({}) do |entry, memo|
  memo[entry["beat_id"].to_s] = entry
end

packet_by_short_source = (packets_doc["prompt_packets"] || []).each_with_object({}) do |packet, memo|
  beat_key = packet["beat_id"].to_s.split("_", 2).first
  memo[beat_key] = packet["packet_id"]
end

seed_by_beat = {}
seed_by_packet = {}

(storyboard["master_storyboard"] || []).each do |beat|
  beat_id = beat["beat_id"].to_s
  expansion = expansion_by_beat[beat_id] || {}
  scored_cues = cue_slots_for_range(beat["time_range"], cue_records)
  primary_cue = scored_cues.first&.first
  covered_slots = scored_cues.map { |cue, _score| cue["slot"].to_s }
  packet_id = expansion["packet_id"].to_s.empty? ? beat.dig("image_review", "prompt_ref").to_s : expansion["packet_id"].to_s

  seed = {
    "schema_version" => "idol_02a_compile_seed.v2",
    "packet_id" => packet_id,
    "cue_slot" => primary_cue ? primary_cue["slot"].to_s : nil,
    "covered_cue_slots" => covered_slots,
    "member_focus" => Array(beat.dig("visual_frame", "member_focus")).map(&:to_s),
    "review_emphasis" => expansion["review_emphasis"].to_s,
    "required_visibility" => Array(expansion["required_visibility"]).map(&:to_s),
    "action_chain_ref" => "##{beat_id}/visual_frame/performance_action",
    "camera_cut_ref" => "##{beat_id}/visual_frame/camera_treatment",
    "wardrobe_lock_ref" => "##{beat_id}/visual_frame/song_specific_styling",
    "source_refs" => {
      "packet_expansion_contract" => "packet_expansion_contract/#{beat_id}",
      "cue_bpm_map" => cue_bpm_run_ref,
      "audio_motion_director_map" => audio_motion_run_ref
    }
  }
  beat["compile_seed"] = seed
  seed_by_beat[beat_id] = seed
  seed_by_packet[packet_id] = seed
end

(packets_doc["prompt_packets"] || []).each do |packet|
  packet_id = packet["packet_id"].to_s
  beat_id = packet["beat_id"].to_s
  seed = seed_by_beat[beat_id] || seed_by_packet[packet_id] || {}
  cue_slot = seed["cue_slot"].to_s
  compile_contract = packet["prompt_compile_contract"] || {}

  compile_inputs = {
    "schema_version" => "idol_02b_compile_inputs.v1",
    "status" => "refs_ready_for_manual_director_compile",
    "compile_seed_ref" => "02A-master-storyboard.yaml##{beat_id}/compile_seed",
    "cue_bpm_slot" => cue_slot.empty? ? nil : cue_slot,
    "audio_motion_slot" => cue_slot.empty? ? nil : cue_slot,
    "micro_beat_sheet_ref" => "02B-prompt-packets.yaml##{packet_id}/micro_beat_sheet",
    "director_note_required" => true,
    "render_facing" => false,
    "may_generate_final_prompt_prose" => false,
    "source_refs" => {
      "master_storyboard_beat" => beat_id,
      "prompt_packet" => packet_id,
      "cue_bpm_map" => cue_bpm_run_ref,
      "audio_motion_director_map" => audio_motion_run_ref
    }
  }

  reordered = {
    "compile_version" => compile_contract["compile_version"] || "compile-v4",
    "compile_method" => "manual_packet_read_with_compile_inputs",
    "compile_inputs" => compile_inputs
  }
  compile_contract.each do |key, value|
    next if %w[compile_version compile_method compile_brief compile_inputs].include?(key)

    reordered[key] = value
  end
  packet["prompt_compile_contract"] = reordered
end

review_by_slot = (review["board_reviews"] || []).each_with_object({}) do |record, memo|
  memo[record["beat_id"].to_s] = record
end
video_by_slot = (video_index["prompts"] || []).each_with_object({}) do |record, memo|
  memo[record["beat_id"].to_s] = record
end

slot_index = cue_sheet_rows.keys.sort_by { |slot| [slot.gsub(/\D/, "").to_i, slot] }.map do |slot|
  row = cue_sheet_rows[slot] || {}
  review_record = review_by_slot[slot] || {}
  video_record = video_by_slot[slot] || {}
  source = row["Source"].to_s
  source_key = short_source_key(source)
  source_02b_packet_id = packet_by_short_source[source_key]
  {
    "slot_id" => slot,
    "source_family" => source_family(source, slot),
    "source_label" => source,
    "source_02b_packet_id" => source_02b_packet_id,
    "one_to_one_with_02b_packet" => !source_02b_packet_id.to_s.empty?,
    "review_status" => review_record["founder_review_status"],
    "review_image_path" => review_record["review_image_path"],
    "cue_folder" => cue_folder_for_slot(run_abs, slot),
    "cue_bpm_slot" => slot,
    "audio_motion_slot" => slot,
    "video_prompt_output_path" => video_record["output_prompt_path"],
    "prompt_status" => video_record["prompt_status"]
  }
end

slot_doc = {
  "schema_version" => "idol_slot_compile_index.v1",
  "content_id" => content_id,
  "status" => "derived_post_review_index_only",
  "pass_date" => options[:pass_date],
  "source_truth_note" => "This file is a thin derived index for post-review lookup. It is not source truth and never feeds render-facing image prompts.",
  "source_review" => review_path.file? ? rel(review_path) : nil,
  "source_cue_bpm_map" => cue_bpm_path ? rel(cue_bpm_path) : nil,
  "source_audio_motion_director_map" => audio_motion_path ? rel(audio_motion_path) : nil,
  "source_cue_sheet" => cue_sheet_path ? rel(cue_sheet_path) : nil,
  "source_video_prompt_index" => video_prompt_index_path.file? ? rel(video_prompt_index_path) : nil,
  "slot_count" => slot_index.length,
  "slot_index" => slot_index
}

candidate_path = run_abs.join("work", "brief-card-compile", "compile-candidate.yaml")
candidate_doc = {
  "schema_version" => "idol_brief_card_compile_candidate.v1",
  "status" => "derived_noncanonical_candidate",
  "authority" => "measurement_and_exact_reference_projection_only",
  "creative_truth_policy" => "A human or assigned model must author and approve any canonical creative change. This candidate may not be merged by this script.",
  "source_bindings" => [storyboard_path, packet_path].map do |path|
    {"path" => rel(path), "sha256" => Digest::SHA256.file(path).hexdigest}
  end,
  "compile_seeds_by_beat" => seed_by_beat,
  "compile_inputs_by_packet" => (packets_doc["prompt_packets"] || []).each_with_object({}) do |packet, memo|
    memo[packet["packet_id"].to_s] = packet.dig("prompt_compile_contract", "compile_inputs")
  end,
  "slot_index_ref" => rel(slot_index_path)
}

after_final_fingerprints = final_prompt_fingerprints(packets_doc, run_abs)
if before_final_fingerprints != after_final_fingerprints
  abort "refusing to write: final prompt fingerprints changed in memory"
end

if options[:write]
  FileUtils.mkdir_p(candidate_path.dirname)
  candidate_path.write(YAML.dump(candidate_doc))
  FileUtils.mkdir_p(slot_index_path.dirname)
  slot_index_path.write(YAML.dump(slot_doc))
end

seed_chars = (storyboard["master_storyboard"] || []).map { |beat| beat["compile_seed"].to_s.length }.sum
brief_chars = (packets_doc["prompt_packets"] || []).map { |packet| packet.dig("prompt_compile_contract", "compile_brief").to_s.length }.sum
input_chars = (packets_doc["prompt_packets"] || []).map { |packet| packet.dig("prompt_compile_contract", "compile_inputs").to_s.length }.sum

puts JSON.pretty_generate(
  "write" => options[:write],
  "harness" => "thin_compile_refs",
  "run" => run,
  "content_id" => content_id,
  "compile_seed_count" => (storyboard["master_storyboard"] || []).count { |beat| beat["compile_seed"].is_a?(Hash) },
  "compile_seed_chars" => seed_chars,
  "compile_brief_count" => (packets_doc["prompt_packets"] || []).count { |packet| packet.dig("prompt_compile_contract", "compile_brief").is_a?(Hash) },
  "compile_brief_chars" => brief_chars,
  "compile_inputs_count" => (packets_doc["prompt_packets"] || []).count { |packet| packet.dig("prompt_compile_contract", "compile_inputs").is_a?(Hash) },
  "compile_inputs_chars" => input_chars,
  "slot_index_count" => slot_index.length,
  "slot_index_path" => rel(slot_index_path),
  "candidate_path" => rel(candidate_path),
  "canonical_02a_or_02b_written" => false,
  "cue_bpm_map" => cue_bpm_path ? rel(cue_bpm_path) : nil,
  "audio_motion_director_map" => audio_motion_path ? rel(audio_motion_path) : nil,
  "cue_sheet" => cue_sheet_path ? rel(cue_sheet_path) : nil
)
