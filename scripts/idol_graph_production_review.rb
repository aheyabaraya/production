#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require_relative "lib/idol_graph_production_review_contract"

options = {root: Pathname.new(__dir__).join("..").expand_path}
parser = OptionParser.new do |p|
  p.banner = "usage: idol_graph_production_review.rb project --judgment PATH --output PATH | verify --review PATH [--root PATH]"
  p.on("--root PATH") { |v| options[:root] = Pathname.new(v).expand_path }
  p.on("--judgment PATH") { |v| options[:judgment] = v }
  p.on("--review PATH") { |v| options[:review] = v }
  p.on("--output PATH") { |v| options[:output] = v }
end
action = ARGV.shift
parser.parse!
abort parser.to_s unless ARGV.empty? && %w[project verify].include?(action)
contract = IdolGraphProductionReviewContract
root = options.fetch(:root)
begin
  if action == "project"
    abort parser.to_s unless options[:judgment] && options[:output]
    result = contract.project_input(root: root, judgment_pointer: contract.pointer(root, options[:judgment]))
    target = Pathname.new(options[:output])
    target = root.join(target) unless target.absolute?
    relative = target.expand_path.relative_path_from(root).to_s
    contract.check!(relative != ".." && !relative.start_with?("../"), "review output must stay inside the repository")
    contract.check!(target.dirname.directory?, "review output directory must already exist")
    real_parent = target.dirname.realpath.relative_path_from(root.realpath).to_s
    contract.check!(real_parent != ".." && !real_parent.start_with?("../"), "review output parent escapes repository")
    bytes = JSON.pretty_generate(result) + "\n"
    if target.exist? || target.symlink?
      contract.check!(target.file? && !target.symlink? && target.read == bytes, "immutable review input already exists with different bytes")
    else
      target.open(File::WRONLY | File::CREAT | File::EXCL, 0o644) { |f| f.write(bytes) }
    end
    puts JSON.pretty_generate({"status" => "projected", "review_input" => contract.pointer(root, target), "input_digest_sha256" => contract.digest(result), "creative_decision" => false})
  else
    abort parser.to_s unless options[:review]
    result = contract.verify!(root: root, review_pointer: contract.pointer(root, options[:review]))
    puts JSON.pretty_generate({"status" => "provenance_validated", "director_decision" => result.dig("output", "decision"), "input_digest_sha256" => result["review_input_digest_sha256"], "automatic_creative_pass" => false})
  end
rescue contract::ContractError, Errno::ENOENT, ArgumentError => e
  warn e.message
  exit 1
end
