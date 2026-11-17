#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "harness-standing-constraint-catalog.schema.json")
CATALOG = ROOT.join("automation", "harness-standing-constraint-catalog.yaml")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")
FORBIDDEN_PATH_FRAGMENTS = %w[CONSTRAINTS.md auto_skill_save weekly_harness_swarm].freeze

errors = []

unless CATALOG.file?
  errors << "catalog is missing: automation/harness-standing-constraint-catalog.yaml"
else
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    CATALOG.to_s,
    chdir: ROOT.to_s
  )
  errors << [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip unless status.success?

  document = YAML.safe_load(CATALOG.read, aliases: true)
  document = {} unless document.is_a?(Hash)
  ids = []
  Array(document["constraints"]).each do |row|
    next unless row.is_a?(Hash)

    constraint_id = row["constraint_id"].to_s
    ids << constraint_id
    owner_path = row["owner_path"].to_s
    owner = ROOT.join(owner_path)
    errors << "#{constraint_id} owner_path is missing: #{owner_path}" unless owner.file?
    FORBIDDEN_PATH_FRAGMENTS.each do |fragment|
      errors << "#{constraint_id} owner_path must not be #{fragment}" if owner_path.split("/").include?(fragment)
    end
  end
  ids.group_by(&:itself).each do |constraint_id, rows|
    errors << "duplicate constraint_id: #{constraint_id}" if rows.length > 1
  end
end

if errors.empty?
  puts "standing-constraint-catalog: pass"
  exit 0
end

errors.each { |error| warn error }
exit 1
