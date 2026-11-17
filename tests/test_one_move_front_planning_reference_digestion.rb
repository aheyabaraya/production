#!/usr/bin/env ruby
# frozen_string_literal: true

# Drives shipped Front Planning validator + digestion closure for 0729_ONE_MOVE.

require "date"
require "digest"
require "open3"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
RUN = ROOT.join("runs/2026-07-29/0729_ONE_MOVE")
READY = RUN.join("research/front-planning-readiness-v1.yaml")
DIGEST = RUN.join("research/front-planning-reference-digestion-v1.yaml")
SELECTION = RUN.join("review/visual-selection-board-v1/selection-map.yaml")
REGISTER = RUN.join("research/current-reference-register-v1.yaml")
VALIDATOR = ROOT.join("scripts/validate_front_planning_readiness.rb")

def sha(path)
  Digest::SHA256.file(path).hexdigest
end

abort "missing readiness" unless READY.file?
abort "missing digestion" unless DIGEST.file?

ready_doc = YAML.safe_load(READY.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
digest_doc = YAML.safe_load(DIGEST.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
selection = YAML.safe_load(SELECTION.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
register = YAML.safe_load(REGISTER.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)

ready_sha = sha(READY)
abort "bound_readiness_sha256 mismatch" unless digest_doc["bound_readiness_sha256"].to_s == ready_sha

stdout, stderr, status = Open3.capture3("ruby", VALIDATOR.to_s, READY.to_s, chdir: ROOT.to_s)
abort "validator failed: #{stderr}#{stdout}" unless status.success?
abort "missing OK line" unless stdout.include?("OK: Front Planning v8")

controls = Hash.new { |h, k| h[k] = [] }
scene_index = {}
Array(ready_doc["section_plan"]).each do |section|
  Array(section["major_scene_flow"]).each do |sc|
    sid = sc["scene_id"].to_s
    scene_index[sid] = sc
    blob = [sc["how_it_is_shown"], sc["continuity_result"]].join(" ")
    %w[controls= digestion_controls=].each do |key|
      next unless blob.include?(key)
      part = blob.split(key, 2).last.split("|", 2).first
      part.split(",").map(&:strip).reject(&:empty?).each do |tok|
        controls[tok] << sid unless controls[tok].include?(sid)
      end
    end
  end
end

counts = digest_doc.fetch("section_counts")
%w[S00 S01 S02 S03 S04 S05 S06 S07 S08].each do |sid|
  c = counts.fetch(sid)
  abort "#{sid} undigested=#{c['undigested_count']}" unless c["undigested_count"].to_i.zero?
end
abort "whole undigested not zero" unless digest_doc.dig("whole_film", "undigested_count").to_i.zero?

connected = []
Array(selection["section_connections"]).each { |row| Array(row["reference_ids"]).each { |rid| connected << rid } }
Array(selection["member_connections"]).each { |row| Array(row["reference_ids"]).each { |rid| connected << rid } }
Array(register["reference_units"]).each do |row|
  connected << row["reference_id"] if %w[applied combined].include?(row["disposition"].to_s)
end
connected.uniq!

Array(digest_doc["digestion_table"]).each do |row|
  rid = row["reference_id"].to_s
  kind = row["kind"].to_s
  if kind == "family" && connected.include?(rid)
    abort "#{rid} not closed" unless %w[consumed combined].include?(row["digestion_status"].to_s)
    abort "#{rid} has no linked scenes" if Array(row["linked_scene_ids"]).empty?
  end
  if %w[selected_surface selected_sequence].include?(kind)
    actual = controls[rid] || []
    linked = Array(row["linked_scene_ids"]).map(&:to_s)
    abort "#{rid} linked_scene_ids != controls exact: #{linked.inspect} vs #{actual.inspect}" unless linked == actual
  end
  if kind == "selected_sequence"
    abort "#{rid} sequence_order_preserved not true" unless row["sequence_order_preserved"] == true
    abort "#{rid} ordered_stage_map < 3" if Array(row["ordered_stage_map"]).length < 3
  end
end

FUNCTION_CUES = {
  "IDB_EDIT_DIRECTING" => {
    "object_intro" => %w[object_macro 사물 empty_board 빈 판 돌 매크로],
    "dense_face_hand_space_crosscut" => %w[dense_crosscut face_hold face_hand 빠른 얼굴],
    "cut_before_finish" => %w[cut_before_finish cut-before-finish 끝나기 전],
    "multi_space_chorus_pressure" => %w[multi_space_chorus chorus_peak 후렴],
    "final_stop_and_recover" => %w[stop_new_events pick_hold 최종 회수 새 사건 정지]
  },
  "GIMME_DAT_LOVE_TONE_SPACE" => {
    "amber_cyan_link" => %w[amber cyan 앰버 청록],
    "wet_reflection" => %w[wet_reflection splash 젖은 반사 물보라],
    "glass_metal_tile_water_material" => %w[wet_glass wet_tile material threshold 재질 타일 유리],
    "close_to_wide_recover" => %w[close_to_wide wide_recover 와이드 회수],
    "same_city_night_material_bridge" => %w[city_night material_bridge threshold 같은 도시 재질]
  }
}

edit = digest_doc.fetch("edit_tone_function_bindings")
FUNCTION_CUES.each do |fam, fns|
  fns.each do |fn, cues|
    scenes = Array(edit.dig(fam, fn))
    abort "empty edit-tone #{fam}.#{fn}" if scenes.empty?
    scenes.each do |sid|
      sc = scene_index[sid.to_s]
      abort "edit-tone #{fam}.#{fn} unknown scene #{sid}" unless sc
      blob = [sc["scene_job"], sc["how_it_is_shown"], sc["continuity_result"]].join(" ").downcase
      unless cues.any? { |c| blob.include?(c.downcase) }
        abort "edit-tone #{fam}.#{fn} scene #{sid} lacks cues #{cues.inspect}: #{blob[0, 160]}"
      end
      shown = [sc["how_it_is_shown"], sc["continuity_result"]].join(" ")
      abort "edit-tone #{fam}.#{fn} scene #{sid} does not control #{fam}" unless shown.include?(fam)
    end
  end
end

Array(edit.dig("IDB_EDIT_DIRECTING", "cut_before_finish")).each do |sid|
  sc = scene_index[sid.to_s]
  blob = [sc["scene_job"], sc["how_it_is_shown"]].join(" ")
  abort "cut_before_finish misbound to #{sid}" unless blob.include?("cut_before") || blob.include?("cut-before") || blob.include?("끝나기 전")
end

# dense must not include pure cut_before scenes without dense cue
Array(edit.dig("IDB_EDIT_DIRECTING", "dense_face_hand_space_crosscut")).each do |sid|
  sc = scene_index[sid.to_s]
  blob = [sc["scene_job"], sc["how_it_is_shown"]].join(" ")
  if blob.include?("cut_before") && !blob.include?("dense") && !blob.include?("face")
    abort "dense_face_hand_space_crosscut misbound cut-before-only scene #{sid}"
  end
end

ready_doc.fetch("section_plan").each do |section|
  story = section.fetch("section_story_function").to_s
  abort "#{section['section_id']} missing ref stamp" unless story.start_with?("[refs connected=")
  abort "#{section['section_id']} stamp undigested not 0" unless story.include?("undigested=0")
end

puts "OK: ONE MOVE reference digestion closed; validator passed; undigested=0; exact controls bind; sequence stages ok; edit-tone cues ok"
puts "ready_sha=#{ready_sha}"
puts "digest_sha=#{sha(DIGEST)}"
