#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_front_planning_sequence_core_hold"

ROOT = Pathname.new(__dir__).join("..").expand_path
options = {admission_graph: false}
OptionParser.new do |parser|
  parser.on("--admission-graph") { options[:admission_graph] = true }
end.parse!

path = ARGV.fetch(0)
source_path = Pathname.new(path)
unless source_path.file?
  warn "sequence-core-hold: Front Planning path is missing"
  exit 1
end
if IdolFrontPlanningSequenceCoreHold.skip_frozen_legacy?(path, admission_graph: options[:admission_graph])
  puts "sequence-core-hold: skip frozen COLOR STAY v17 without --admission-graph"
  exit 0
end

document = YAML.safe_load(source_path.read, aliases: true)
document = {} unless document.is_a?(Hash)

holds = IdolFrontPlanningSequenceCoreHold.holds(document)
if holds.empty?
  puts "sequence-core-hold: pass"
  exit 0
end

holds.each do |row|
  warn "HOLD: #{row.fetch('code')} core_slot=#{row.fetch('core_slot_id')} sequence_unit=#{row.fetch('sequence_unit')} candidate_count=#{row.fetch('candidate_count')}"
end
exit 1
