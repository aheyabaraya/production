#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_role_context_pack"

ROOT = Pathname.new(__dir__).join("..").expand_path
SCHEMA = ROOT.join("schemas", "role-context-pack.schema.json")
PYTHON = ROOT.join("scripts", "idol-video-python")
SCHEMA_VALIDATOR = ROOT.join("scripts", "validate_json_schema.py")

options = {root: ROOT, json: true}
parser = OptionParser.new do |opts|
  opts.banner = <<~TEXT
    usage:
      ruby scripts/idol_role_context_pack.rb build-dispatch --dispatch PATH [--output PATH]
      ruby scripts/idol_role_context_pack.rb build-profile --request PATH [--output PATH]
      ruby scripts/idol_role_context_pack.rb validate PATH

    build-profile defaults to legacy_pinned. An explicit graph_v2 request must
    carry run_class=new_run and the exact verified switch_receipt object.
  TEXT
  opts.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--dispatch PATH") { |value| options[:dispatch] = value }
  opts.on("--request PATH") { |value| options[:request] = value }
  opts.on("--output PATH") { |value| options[:output] = value }
end

action = ARGV.shift
parser.parse!(ARGV)
root = options[:root].expand_path.cleanpath

def load_mapping(path)
  value = path.extname.downcase == ".json" ? JSON.parse(path.read) : YAML.safe_load(path.read, aliases: true)
  raise IdolRoleContextPack::ContractError, "request must be an object" unless value.is_a?(Hash)
  value
end

def validate_schema(path, root)
  stdout, stderr, status = Open3.capture3(
    PYTHON.to_s,
    SCHEMA_VALIDATOR.to_s,
    SCHEMA.to_s,
    path.to_s,
    chdir: root.to_s
  )
  raise IdolRoleContextPack::ContractError, "role-context JSON Schema validation failed: #{[stderr, stdout].join(' ').strip}" unless status.success?
end

def safe_output(root, raw)
  path = Pathname.new(raw)
  path = root.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(root).to_s
  raise IdolRoleContextPack::ContractError, "output path escapes repository" if relative == ".." || relative.start_with?("../")
  path
end

begin
case action
when "build-dispatch"
  raise IdolRoleContextPack::ContractError, "--dispatch is required" if options[:dispatch].to_s.empty?
  pack = IdolRoleContextPack.build_from_dispatch(root: root, dispatch_path: options[:dispatch])
when "build-profile"
  raise IdolRoleContextPack::ContractError, "--request is required" if options[:request].to_s.empty?
  request_path = safe_output(root, options[:request])
  request = load_mapping(request_path)
  pack = IdolRoleContextPack.build(root: root, **request.transform_keys(&:to_sym))
when "validate"
  raw = ARGV.shift
  raise IdolRoleContextPack::ContractError, "pack path is required" if raw.to_s.empty? || !ARGV.empty?
  path = safe_output(root, raw)
  raise IdolRoleContextPack::ContractError, "pack file is missing" unless path.file?
  validate_schema(path, root)
  pack = load_mapping(path)
  errors = IdolRoleContextPack.validate_pack(root: root, pack: pack)
  puts JSON.pretty_generate({"status" => errors.empty? ? "pass" : "fail", "errors" => errors})
  exit(errors.empty? ? 0 : 1)
else
  warn parser
  exit 2
end

rendered = JSON.pretty_generate(pack) + "\n"
if options[:output]
  output = safe_output(root, options[:output])
  output.dirname.mkpath
  output.write(rendered)
  validate_schema(output, root)
  errors = IdolRoleContextPack.validate_pack(root: root, pack: pack)
  raise IdolRoleContextPack::ContractError, errors.join("; ") unless errors.empty?
  puts JSON.pretty_generate({"status" => pack.fetch("status"), "path" => output.relative_path_from(root).to_s, "sha256" => Digest::SHA256.file(output).hexdigest})
else
  puts rendered
end
rescue IdolRoleContextPack::ContractError, KeyError, JSON::ParserError, Psych::Exception => e
  warn "HOLD: #{e.message}"
  exit 1
end
