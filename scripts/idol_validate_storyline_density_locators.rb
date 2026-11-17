#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require_relative "lib/idol_storyline_density_locator_contract"

# Presence of a locator sheet into one full-text storyline, plus lineage
# and not-empty / not-PRE-00-restatement. Does not judge cinematic recoverability.
options = { root: nil, stage: nil }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/idol_validate_storyline_density_locators.rb --root PATH [--stage pre00|front_planning] ARTIFACT"
  opts.on("--root PATH", "Repository or run root that contains source_path") { |value| options[:root] = value }
  opts.on("--stage STAGE", "pre00 or front_planning close") { |value| options[:stage] = value }
end
parser.parse!

if options[:root].to_s.empty? || ARGV.empty?
  warn parser.banner
  exit 2
end

if !options[:stage].nil? && !IdolStorylineDensityLocatorContract::STAGES.include?(options[:stage].to_s)
  warn "stage must be pre00 or front_planning"
  exit 2
end

path = Pathname.new(ARGV.fetch(0)).expand_path
unless path.file?
  warn "density locator artifact missing: #{path}"
  exit 2
end

errors = IdolStorylineDensityLocatorContract.close_artifact(
  options[:root],
  path,
  stage: options[:stage]
)
if errors.empty?
  puts "storyline-density-locators: pass"
  exit 0
end

errors.each { |error| warn error }
exit 1
