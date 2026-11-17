#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "set"
require_relative "lib/idol_skill_contract_paths"

ROOT = Pathname.new(Dir.pwd).cleanpath

def rel_path(path)
  Pathname.new(path).cleanpath.relative_path_from(ROOT).to_s
rescue ArgumentError
  path.to_s
end

def resolve_candidate(candidate, skill_dir)
  raw = Pathname.new(candidate)
  return [raw.cleanpath] if raw.absolute?

  if candidate.start_with?("references/", "modules/")
    return [(skill_dir + candidate).cleanpath]
  end

  if candidate.start_with?("assets/")
    return [(skill_dir + candidate).cleanpath, (ROOT + candidate).cleanpath]
  end

  [(ROOT + candidate).cleanpath]
end

def existing_path?(candidate, skill_dir)
  resolve_candidate(candidate, skill_dir).any? do |path|
    File.file?(path.to_s) || File.directory?(path.to_s)
  end
end

skill_paths = if ARGV.empty?
  Dir.glob((ROOT + "skills/*/SKILL.md").to_s).sort
else
  ARGV.flat_map do |arg|
    path = Pathname.new(arg)
    path = ROOT + path unless path.absolute?
    if File.directory?(path.to_s)
      [(path + "SKILL.md").to_s]
    else
      [path.to_s]
    end
  end
end

errors = []
warnings = []

skill_paths.each do |skill_path|
  unless File.file?(skill_path)
    errors << "missing SKILL.md: #{rel_path(skill_path)}"
    next
  end

  skill_dir = Pathname.new(skill_path).dirname
  rel_skill = rel_path(skill_path)
  text = File.read(skill_path, encoding: "utf-8")

  unless text.include?("## Required Reads") || text.include?("## Read / Write Contract")
    errors << "#{rel_skill}: missing ## Required Reads or ## Read / Write Contract"
  end

  seen = Set.new
  IdolSkillContractPaths.candidate_paths(text).each do |candidate|
    next if seen.include?(candidate)

    seen << candidate
    next if existing_path?(candidate, skill_dir)

    errors << "#{rel_skill}: referenced path is not readable: #{candidate}"
  end

  retired_stub = text.include?("Status: retired stub")
  # historical retired names (idol-mv-prompt etc.) directories have been removed from the repo
  if !retired_stub && text.match?(/selected_skill:\s*(idol-mv-prompt|idol-stage-prompt|mix-stage-mv)/)
    warnings << "#{rel_skill}: mentions retired selected_skill value; ensure this is only a forbidden/example context"
  end
end

if errors.empty?
  puts "OK: #{skill_paths.length} skill contract(s) checked"
  warnings.each { |warning| warn "WARNING: #{warning}" }
  exit 0
end

errors.each { |error| warn "ERROR: #{error}" }
warnings.each { |warning| warn "WARNING: #{warning}" }
exit 1
