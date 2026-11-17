#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require_relative "lib/idol_department_context"

ROOT = Pathname.new(__dir__).join("..").expand_path
MAX_INPUT_BYTES = IdolDepartmentContext::MAX_INPUT_BYTES

options = {root: ROOT}
parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_department_context.rb [--root PATH] < JSON"
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
end

begin
  parser.parse!(ARGV)
  unless ARGV.empty?
    raise IdolDepartmentContext::ContractError, "idol_department_context CLI accepts optional --root only; JSON must arrive on stdin"
  end

  bytes = STDIN.binmode.read(MAX_INPUT_BYTES + 1)
  if bytes.nil?
    raise IdolDepartmentContext::ContractError, "stdin JSON is missing"
  end
  if bytes.bytesize > MAX_INPUT_BYTES
    raise IdolDepartmentContext::ContractError, "stdin JSON exceeds the bounded input size"
  end
  payload = JSON.parse(bytes)
  raise IdolDepartmentContext::ContractError, "stdin JSON must be one object" unless payload.is_a?(Hash)

  action = payload["action"].to_s
  result = case action
           when "prepare"
             IdolDepartmentContext.prepare_from_cli_payload(payload, root: options[:root])
           when "validate"
             IdolDepartmentContext.validate_from_cli_payload(payload, root: options[:root])
           else
             raise IdolDepartmentContext::ContractError, "unsupported action: #{action.empty? ? 'missing' : action}"
           end
  $stdout.write(JSON.generate(result) + "\n")
rescue JSON::ParserError => e
  $stdout.write(JSON.generate({"status" => "hold", "error" => IdolDepartmentContext.truncate_error("stdin JSON is invalid: #{e.message}")}) + "\n")
  exit 1
rescue IdolDepartmentContext::ContractError, KeyError, ArgumentError, Errno::ENOENT, Psych::Exception => e
  $stdout.write(JSON.generate({"status" => "hold", "error" => IdolDepartmentContext.truncate_error(e.message)}) + "\n")
  exit 1
end
