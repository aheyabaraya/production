#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "optparse"
require "pathname"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "harness-helper-consumption-receipt.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

options = {}
OptionParser.new do |parser|
  parser.on("--receipt PATH") { |value| options[:receipt] = value }
end.parse!

receipt = options[:receipt]
if receipt.nil? || receipt.strip.empty?
  warn "usage: validate_helper_consumption_receipt.rb --receipt PATH"
  exit 2
end

path = Pathname.new(receipt)
path = ROOT.join(path) unless path.absolute?

stdout, stderr, status = Open3.capture3(
  PYTHON.to_s,
  SCHEMA_VALIDATOR.to_s,
  SCHEMA.to_s,
  path.to_s,
  chdir: ROOT.to_s
)

unless status.success?
  warn [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
  exit 1
end

puts "helper-consumption-receipt: pass"
exit 0
