#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "tempfile"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
VALIDATOR = Pathname.new(__dir__).join("validate_sequence_motion_analysis.rb").expand_path

options = {root: ROOT, output: nil, write: false, json: true}
parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_prepare_sequence_motion_analysis.rb AUTHORED_ANALYSIS [options]"
  opts.on("--root PATH", "Repository root used to resolve and hash exact sources.") { |value| options[:root] = Pathname.new(value).expand_path }
  opts.on("--output PATH", "Run-owned exact-copy destination. Defaults to the deterministic Section/Major/attempt path under RUN_ROOT/research/sequence-motion-analysis/.") { |value| options[:output] = value }
  opts.on("--write", "Write only the validated authored bytes. No creative truth is authored.") { options[:write] = true }
  opts.on("--no-json", "Print a short text result.") { options[:json] = false }
end

begin
  parser.parse!
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

source_arg = ARGV.shift
if source_arg.to_s.strip.empty? || !ARGV.empty?
  warn parser
  exit 2
end

def resolve_path(raw, root)
  path = Pathname.new(raw.to_s)
  path = root.join(path) unless path.absolute?
  path.expand_path.cleanpath
end

def inside?(path, root)
  lexical = path.relative_path_from(root).to_s
  return false if lexical == ".." || lexical.start_with?("../")

  ancestor = path
  suffix = []
  until ancestor.exist?
    suffix.unshift(ancestor.basename.to_s)
    parent = ancestor.parent
    return false if parent == ancestor
    ancestor = parent
  end
  resolved = suffix.reduce(ancestor.realpath) { |current, part| current.join(part) }.cleanpath
  real_root = root.realpath
  relative = resolved.relative_path_from(real_root).to_s
  relative != ".." && !relative.start_with?("../")
rescue ArgumentError, Errno::ENOENT, Errno::EACCES
  false
end

def load_mapping(path)
  value = if path.extname.downcase == ".json"
            JSON.parse(path.read)
          else
            YAML.safe_load(path.read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
          end
  raise TypeError, "authored analysis must contain an object" unless value.is_a?(Hash)
  value
end

def pre_copy_validation(path, root)
  command = [RbConfig.ruby, VALIDATOR.to_s, "--root", root.to_s, "--json", "--pre-cdd-copy"]
  command << path.to_s
  stdout, stderr, status = Open3.capture3(*command, chdir: root.to_s)
  detail = if status.success?
             nil
           else
             begin
               parsed = JSON.parse(stdout)
               Array(parsed["errors"]).join("; ")
             rescue JSON::ParserError
               [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
             end
           end
  [status.success?, detail]
end

root = options[:root].expand_path.cleanpath
source_path = resolve_path(source_arg, root)
errors = []
document = {}
validated_source_bytes = nil

unless inside?(source_path, root) && source_path.file?
  errors << "authored analysis is missing or outside the repository"
else
  begin
    validated_source_bytes = source_path.binread
    document = load_mapping(source_path)
  rescue JSON::ParserError, Psych::Exception, TypeError => error
    errors << "cannot parse authored analysis: #{error.message}"
  end
end

if errors.empty?
  valid, detail = pre_copy_validation(source_path, root)
  unless valid
    errors << "authored analysis failed validation: #{detail}"
  end
  post_validation_bytes = source_path.binread
  if validated_source_bytes != post_validation_bytes
    errors << "authored analysis bytes changed during validation; exact-copy promotion is HOLD"
  end
end

run_root = document.any? ? resolve_path(document["run_root"], root) : root
section_id = document["section_id"].to_s
major_scene_id = document["major_scene_id"].to_s
attempt_key = document.dig("dispatch_and_authorship", "attempt_key").to_s
unless section_id.match?(/\AS[0-9]{2,}[A-Z]?\z/) && major_scene_id.match?(/\AMJ[0-9]{2,}[A-Z0-9_]*\z/)
  errors << "section_id or major_scene_id is unsafe for deterministic output naming"
end
errors << "attempt_key must use the immutable attempt-NN naming contract" unless attempt_key.match?(/\Aattempt-[0-9]{2,}\z/)
expected_output_path = run_root.join("research", "sequence-motion-analysis", "#{section_id}--#{major_scene_id}", "#{attempt_key}.yaml").expand_path.cleanpath
output_path = options[:output] ? resolve_path(options[:output], root) : expected_output_path
errors << "output path must equal the deterministic Section/Major owner path" unless output_path == expected_output_path
errors << "declared run_root is missing or outside the repository" unless inside?(run_root, root) && run_root.directory?
errors << "output must remain inside the owning run_root" unless inside?(output_path, run_root)

source_bytes = validated_source_bytes || ""
source_sha = source_bytes.empty? ? nil : Digest::SHA256.hexdigest(source_bytes)
write_state = "not_requested"
created_output = false

if options[:write] && errors.empty?
  FileUtils.mkdir_p(output_path.dirname)
  if !inside?(output_path.dirname, run_root) || output_path.dirname.symlink?
    errors << "output parent is outside run_root or is a symlink"
  else
    File.open(output_path.dirname.to_s, File::RDONLY) do |scope_lock|
      unless scope_lock.flock(File::LOCK_EX | File::LOCK_NB)
        errors << "single-writer HOLD: atomic Major scope ownership is already held"
        next
      end

      valid_under_lock, locked_detail = pre_copy_validation(source_path, root)
      errors << "authored analysis failed validation after atomic scope acquisition: #{locked_detail}" unless valid_under_lock
      errors << "authored analysis bytes changed before copy; exact-copy promotion is HOLD" unless source_path.binread == source_bytes

      if errors.empty?
        if output_path.symlink?
          errors << "single-writer HOLD: output path is a symlink"
        elsif output_path.file?
          if output_path.binread == source_bytes
            write_state = "existing_identical_pending_cdd_review"
          else
            errors << "single-writer HOLD: output already exists with different bytes"
          end
        else
          Tempfile.create([".sequence-motion-analysis-", ".tmp"], output_path.dirname.to_s) do |temp|
            temp.binmode
            temp.write(source_bytes)
            temp.flush
            temp.fsync
            temp.close
            if output_path.exist? || output_path.symlink?
              errors << "single-writer HOLD: output appeared before atomic promotion"
            else
              begin
                File.link(temp.path, output_path.to_s)
                created_output = true
                File.open(output_path.dirname.to_s, File::RDONLY) { |directory| directory.fsync }
                write_state = "copied_pending_cdd_review"
              rescue Errno::EEXIST
                errors << "single-writer HOLD: output appeared before atomic promotion"
              rescue SystemCallError, IOError => error
                errors << "single-writer HOLD: atomic exact-copy persistence failed after link: #{error.class}: #{error.message}"
              end
            end
          end
        end
      end
      if errors.empty? && Digest::SHA256.file(output_path).hexdigest != source_sha
        errors << "output SHA-256 differs from authored input bytes"
      end
      if errors.empty?
        post_valid, post_detail = pre_copy_validation(output_path, root)
        errors << "copied bytes failed post-copy transport admission: #{post_detail}" unless post_valid
      end
      if errors.any? && created_output
        begin
          if output_path.file? && !output_path.symlink? && output_path.binread == source_bytes
            output_path.unlink
            File.open(output_path.dirname.to_s, File::RDONLY) { |directory| directory.fsync }
            write_state = "rolled_back_failed_transport_admission"
          end
        rescue SystemCallError, IOError => error
          errors << "single-writer HOLD: failed to roll back the just-created exact-copy output: #{error.class}: #{error.message}"
          write_state = "rollback_failed_manual_recovery_required"
        end
      end
      scope_lock.flock(File::LOCK_UN)
    end
  end
end

result = {
  "valid" => errors.empty?,
  "write_requested" => options[:write],
  "write_state" => errors.empty? ? write_state : "hold",
  "transport_role" => "exact_copy_only_no_creative_authorship",
  "transport_admission" => errors.empty? ? "copied_pending_cdd_review" : "hold",
  "downstream_authority" => "none_until_strict_independent_cdd_reviewed_validation",
  "source" => inside?(source_path, root) ? source_path.relative_path_from(root).to_s : source_arg.to_s,
  "source_sha256" => source_sha,
  "output" => inside?(output_path, root) ? output_path.relative_path_from(root).to_s : output_path.to_s,
  "output_sha256" => options[:write] && output_path.file? ? Digest::SHA256.file(output_path).hexdigest : source_sha,
  "analysis_id" => document["analysis_id"],
  "scope_key" => document.dig("dispatch_and_authorship", "scope_key"),
  "errors" => errors
}

if options[:json]
  puts JSON.pretty_generate(result)
elsif errors.empty?
  puts "OK: exact bytes admitted as copied_pending_cdd_review with no downstream authority (#{write_state})"
else
  errors.each { |error| warn "ERROR: #{error}" }
end
exit(errors.empty? ? 0 : 1)
