#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_helper_consumption_receipts"
require_relative "lib/idol_run_followup_sidecar"

ROOT = Pathname.new(__dir__).join("..").expand_path
options = {require_on_material: false, required: false}
OptionParser.new do |parser|
  parser.on("--sidecar PATH") { |value| options[:sidecar] = value }
  parser.on("--run PATH") { |value| options[:run] = value }
  parser.on("--dispatch PATH") { |value| options[:dispatch] = value }
  parser.on("--require-on-material") { options[:require_on_material] = true }
  parser.on("--require") { options[:required] = true }
end.parse!

errors = []
if options[:sidecar]
  errors = IdolRunFollowupSidecar.validate_sidecar_file(root: ROOT, path: options[:sidecar])
elsif options[:dispatch]
  path = Pathname.new(options[:dispatch])
  path = ROOT.join(path) unless path.absolute?
  document = YAML.safe_load(path.read, aliases: true)
  document = {} unless document.is_a?(Hash)
  receipts = IdolHelperConsumptionReceipts.load_receipts(root: ROOT, document: document)
  errors = IdolRunFollowupSidecar.validate(
    root: ROOT,
    document: document,
    receipts: receipts,
    require_on_material: options[:require_on_material],
    required: options[:required]
  )
elsif options[:run]
  document = {"run" => options[:run]}
  errors = IdolRunFollowupSidecar.validate(
    root: ROOT,
    document: document,
    require_on_material: options[:require_on_material],
    required: options[:required]
  )
else
  warn "usage: validate_run_followup_sidecar.rb --sidecar PATH | --run PATH | --dispatch PATH"
  exit 2
end

if errors.empty?
  puts "run-followup-sidecar: pass"
  exit 0
end
errors.each { |error| warn error }
exit 1
