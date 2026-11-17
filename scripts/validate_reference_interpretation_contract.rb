#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_reference_interpretation_contract"

options = {
  root: Pathname.new(__dir__).join("..").expand_path,
  mode: "auto",
  json: false
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/validate_reference_interpretation_contract.rb [options] PATH"
  opts.on("--root PATH", String, "Repository root used to resolve bound sources") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--mode MODE", %w[auto owner direction], "auto, owner, or direction") { |value| options[:mode] = value }
  opts.on("--json", "Emit machine-readable output") { options[:json] = true }
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser
  exit 2
end

path_arg = ARGV.shift
if path_arg.to_s.strip.empty? || !ARGV.empty?
  warn parser
  exit 2
end

path = Pathname.new(path_arg).expand_path
unless path.file?
  warn "reference interpretation artifact not found: #{path}"
  exit 2
end

document = IdolReferenceInterpretationContract.load_document(path)
if document.empty?
  warn "reference interpretation artifact must be structured YAML or JSON: #{path}"
  exit 2
end

errors = []
if %w[auto owner].include?(options[:mode])
  errors.concat(
    IdolReferenceInterpretationContract.validate_owner_document(
      path,
      document,
      root: options[:root]
    )
  )
end
if options[:mode] == "direction" || (options[:mode] == "auto" && document["research_synthesis"].is_a?(Hash))
  errors.concat(
    IdolReferenceInterpretationContract.validate_direction_bindings(
      path,
      document,
      root: options[:root]
    )
  )
end
errors.uniq!

result = {
  "status" => errors.empty? ? "pass" : "fail",
  "artifact" => path.to_s,
  "mode" => options[:mode],
  "receipt_count" => IdolReferenceInterpretationContract.receipts_with_pointers(document).length,
  "application_count" => Array(document.dig("research_synthesis", "selected_application_index")).length,
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "reference interpretation contract: pass"
else
  warn "reference interpretation contract: fail"
  errors.each { |error| warn "- #{error}" }
end

exit(errors.empty? ? 0 : 1)
