#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_front_planning_local_pairwise_global"

ROOT = Pathname.new(__dir__).join("..").expand_path
options = {admission_graph: false}
OptionParser.new do |parser|
  parser.on("--admission-graph") { options[:admission_graph] = true }
end.parse!

path = ARGV.fetch(0)
source_path = Pathname.new(path)
unless source_path.file?
  warn "local-pairwise-global: Front Planning path is missing"
  exit 1
end
if IdolFrontPlanningLocalPairwiseGlobal.skip_frozen_legacy?(path, admission_graph: options[:admission_graph])
  puts "local-pairwise-global: skip frozen COLOR STAY v17 without --admission-graph"
  exit 0
end

document = YAML.safe_load(source_path.read, aliases: true)
document = {} unless document.is_a?(Hash)

holds = IdolFrontPlanningLocalPairwiseGlobal.holds(document)
if holds.empty?
  puts "local-pairwise-global: pass"
  exit 0
end

holds.each do |row|
  warn "HOLD: #{row.fetch('code')} scope=#{row.fetch('scope')} #{row.fetch('detail')}"
end
exit 1
