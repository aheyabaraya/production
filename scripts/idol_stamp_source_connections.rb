#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_source_connection_contract"

# Exact-copy disk SHA onto model-authored source pointers.
# Does not write canonical creative filenames. Does not fill creative fields.
options = { root: nil, model_facing: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/idol_stamp_source_connections.rb --root PATH [--model-facing] [ROWS.json|ROWS.yaml]"
  opts.on("--root PATH", "Repository or run root that contains the pointer paths") { |value| options[:root] = value }
  opts.on("--model-facing", "Project check-only model-facing pointers without hex; HOLD when unconnected") { options[:model_facing] = true }
end
parser.parse!

if options[:root].to_s.empty?
  warn parser.banner
  exit 2
end

raw = ARGF.read
document = if raw.strip.start_with?("{", "[")
             JSON.parse(raw)
           else
             YAML.safe_load(raw, aliases: true)
           end
rows = if document.is_a?(Array)
         document
       elsif document.is_a?(Hash)
         document["rows"] || document["sources"] || document["creative_source_pointers"]
       end
unless rows.is_a?(Array)
  warn "input must be an array, or an object with rows/sources/creative_source_pointers"
  exit 2
end
rows = rows.map { |row| row.is_a?(Hash) && row.key?("row") ? row["row"] : row }

root = Pathname.new(options[:root]).expand_path
if options[:model_facing]
  projected = IdolSourceConnectionContract.project_rows(root, rows)
  puts JSON.pretty_generate("rows" => projected)
  blocked = projected.any? { |result| result.dig("connection", "status") != "connected" }
  exit(blocked ? 1 : 0)
end

results = IdolSourceConnectionContract.stamp_rows(root, rows)
blocked = results.any? { |result| result.dig("connection", "status") != "connected" }
puts JSON.pretty_generate("rows" => results)
exit(blocked ? 1 : 0)
