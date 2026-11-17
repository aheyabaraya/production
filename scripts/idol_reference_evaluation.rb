#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require_relative "lib/idol_reference_evaluation_contract"

SCRIPT_ROOT = Pathname.new(__dir__).join("..").expand_path
USAGE = "usage: ruby scripts/idol_reference_evaluation.rb validate-case PATH | validate-review PATH --case CASE | validate-pair CASE REVIEW [--root PATH] [--json]"

command = ARGV.shift
options = {root: SCRIPT_ROOT, json: false, case_path: nil}
OptionParser.new do |parser|
  parser.banner = USAGE
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path }
  parser.on("--case PATH") { |value| options[:case_path] = value }
  parser.on("--json") { options[:json] = true }
end.parse!

unless %w[validate-case validate-review validate-pair].include?(command)
  warn USAGE
  exit 2
end

def emit(result, json_mode, ok)
  if json_mode
    puts JSON.pretty_generate(result)
  elsif ok
    puts "reference-evaluation: mechanical completeness; not production PASS"
  else
    warn "reference-evaluation: incomplete"
    Array(result.is_a?(Hash) ? result["findings"] : []).each { |row| warn row }
  end
end

root = options[:root]
begin
  case command
  when "validate-case"
    path_arg = ARGV.shift
    abort USAGE if path_arg.to_s.empty? || ARGV.any?
    errors, result = IdolReferenceEvaluationContract.evaluate_case(root: root, path: path_arg)
    emit(result, options[:json], errors.empty?)
    exit(errors.empty? ? 0 : 1)
  when "validate-review"
    path_arg = ARGV.shift
    case_arg = options[:case_path]
    abort USAGE if path_arg.to_s.empty? || case_arg.to_s.empty? || ARGV.any?
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: root,
      case_path: case_arg,
      review_path: path_arg
    )
    emit(result, options[:json], errors.empty?)
    exit(errors.empty? ? 0 : 1)
  when "validate-pair"
    case_arg = ARGV.shift
    review_arg = ARGV.shift
    abort USAGE if case_arg.to_s.empty? || review_arg.to_s.empty? || ARGV.any?
    errors, result = IdolReferenceEvaluationContract.evaluate_pair(
      root: root,
      case_path: case_arg,
      review_path: review_arg
    )
    emit(result, options[:json], errors.empty?)
    exit(errors.empty? ? 0 : 1)
  end
rescue StandardError => e
  result = {
    "schema_version" => IdolReferenceEvaluationContract::MECHANICAL_RESULT_VERSION,
    "authority" => "structure_and_binding_only_never_semantic_quality_or_production_pass",
    "mechanical_closure" => "incomplete",
    "production_pass" => false,
    "semantic_quality_determined" => false,
    "automatic_winner" => false,
    "findings" => ["reference evaluation failed closed: #{e.message}"]
  }
  emit(result, options[:json], false)
  exit 1
end
