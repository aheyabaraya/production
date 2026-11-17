#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_checkpoint_closure_catalog"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "harness-checkpoint-closure-catalog.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

options = {json: false}
OptionParser.new { |parser| parser.on("--json") { options[:json] = true } }.parse!

errors = []
catalog_path = IdolCheckpointClosureCatalog.catalog_path(ROOT)
unless catalog_path.file?
  errors << "catalog is missing: #{IdolCheckpointClosureCatalog::CATALOG_RELATIVE}"
else
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    catalog_path.to_s,
    chdir: ROOT.to_s
  )
  errors << [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip unless status.success?
  document = YAML.safe_load(catalog_path.read, aliases: true)
  document = {} unless document.is_a?(Hash)
  ids = []
  Array(document["checkpoints"]).each do |group|
    next unless group.is_a?(Hash)

    Array(group["rows"]).each do |row|
      next unless row.is_a?(Hash)

      requirement_id = row["requirement_id"].to_s
      ids << requirement_id
      prefix = requirement_id.split("-", 2).first.to_s.downcase
      errors << "#{requirement_id} category must match requirement_id prefix" unless prefix == row["category"].to_s
    end
  end
  ids.group_by(&:itself).each do |requirement_id, rows|
    errors << "duplicate recipe requirement_id: #{requirement_id}" if rows.length > 1
  end
end

if errors.empty?
  puts "checkpoint-closure-catalog: pass"
  exit 0
end

errors.each { |error| warn error }
exit 1
