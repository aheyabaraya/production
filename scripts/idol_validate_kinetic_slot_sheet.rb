#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"
require_relative "lib/idol_kinetic_slot_sheet_contract"

# Presence of a change-point slot sheet for one Major.
# Does not judge cinematic variety.
if ARGV.empty?
  warn "Usage: ruby scripts/idol_validate_kinetic_slot_sheet.rb SHEET.yaml"
  exit 2
end

path = Pathname.new(ARGV.fetch(0)).expand_path
unless path.file?
  warn "kinetic slot sheet missing: #{path}"
  exit 2
end

sheet = if path.extname == ".json"
          JSON.parse(path.read)
        else
          YAML.safe_load(path.read, aliases: true)
        end
errors = IdolKineticSlotSheetContract.validate(sheet)
if errors.empty?
  puts "kinetic-slot-sheet: pass"
  exit 0
end

errors.each { |error| warn error }
exit 1
