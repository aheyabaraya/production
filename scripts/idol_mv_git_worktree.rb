#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "yaml"

class MvGitWorktreeError < StandardError; end

DEFAULT_REPO = Pathname.new(__dir__).join("..").expand_path

def run_command(*command, allow_failure: false)
  stdout, stderr, status = Open3.capture3(*command)
  unless status.success? || allow_failure
    detail = stderr.to_s.strip
    detail = stdout.to_s.strip if detail.empty?
    raise MvGitWorktreeError, "command failed (#{command.join(' ')}): #{detail}"
  end
  [stdout, stderr, status]
end

def git(repo, *arguments, allow_failure: false)
  run_command("git", "-C", repo.to_s, *arguments, allow_failure: allow_failure)
end

def git_value(repo, *arguments)
  git(repo, *arguments).first.strip
end

def repo_root(raw)
  candidate = Pathname.new(raw).expand_path.cleanpath
  root = Pathname.new(git_value(candidate, "rev-parse", "--show-toplevel")).expand_path.cleanpath
  same_root = begin
    root.realpath == candidate.realpath
  rescue SystemCallError
    root == candidate
  end
  raise MvGitWorktreeError, "--repo must name the current Git worktree root" unless same_root

  candidate
end

def clean_worktree!(repo)
  status = git_value(repo, "status", "--porcelain=v1", "--untracked-files=all")
  raise MvGitWorktreeError, "current worktree must be clean before creating an MV worktree" unless status.empty?
end

def contained_repo_file(repo, raw)
  path = Pathname.new(raw.to_s)
  path = repo.join(path) unless path.absolute?
  path = path.expand_path.cleanpath
  relative = path.relative_path_from(repo).to_s
  if relative == ".." || relative.start_with?("../") || !path.file?
    raise MvGitWorktreeError, "dispatch must be an existing repository file: #{raw}"
  end
  [path, relative]
rescue ArgumentError
  raise MvGitWorktreeError, "dispatch escapes repository: #{raw}"
end

def load_dispatch(repo, raw, accepted_states:)
  path, relative = contained_repo_file(repo, raw)
  document = if path.extname.downcase == ".json"
               JSON.parse(path.read)
             else
               YAML.safe_load(path.read, permitted_classes: [], aliases: true)
             end
  raise MvGitWorktreeError, "dispatch must contain an object" unless document.is_a?(Hash)
  raise MvGitWorktreeError, "dispatch schema_version must be idol-department-dispatch.v8" unless document["schema_version"] == "idol-department-dispatch.v8"
  current_state = document.dig("lifecycle", "current_state").to_s
  unless accepted_states.include?(current_state)
    raise MvGitWorktreeError, "dispatch lifecycle must be #{accepted_states.join(' or ')} for this operation"
  end
  raise MvGitWorktreeError, "dispatch canonical_write must be bounded_to_expected_paths" unless document.dig("launch", "authority", "canonical_write") == "bounded_to_expected_paths"

  scope_paths = Array(document.dig("launch", "task", "exact_scope", "artifact_paths")).map(&:to_s)
  expected_paths = Array(document.dig("launch", "bounded_output", "expected_paths")).map(&:to_s)
  raise MvGitWorktreeError, "dispatch exact artifact paths must be non-empty" if scope_paths.empty?
  raise MvGitWorktreeError, "dispatch exact scope and bounded output paths differ" unless scope_paths.sort == expected_paths.sort

  [document, path, relative]
rescue JSON::ParserError, Psych::Exception => error
  raise MvGitWorktreeError, "unable to parse dispatch: #{error.message}"
end

def validate_dispatch!(repo, relative)
  validator = repo.join("scripts", "validate_department_dispatch.rb")
  raise MvGitWorktreeError, "department dispatch validator is missing" unless validator.file?

  stdout, stderr, status = run_command(
    RbConfig.ruby,
    validator.to_s,
    "--json",
    relative,
    allow_failure: true
  )
  return if status.success?

  detail = stdout.to_s.strip
  detail = stderr.to_s.strip if detail.empty?
  raise MvGitWorktreeError, "department dispatch validation failed: #{detail}"
end

def mv_run_parts(run_root)
  parts = run_root.to_s.split("/")
  unless parts.length == 4 && parts.first == "runs" && parts.drop(1).all? { |part| !part.empty? }
    raise MvGitWorktreeError, "MV run root must be runs/ALBUM_KEY/TITLE_KEY/RUN_ID"
  end
  parts.drop(1)
end

def ref_component(value)
  result = value.to_s.downcase
    .gsub(/[^\p{L}\p{N}_-]+/u, "-")
    .gsub(/-+/, "-")
    .gsub(/\A[-_]+|[-_]+\z/, "")
  raise MvGitWorktreeError, "branch component is empty after normalization: #{value.inspect}" if result.empty?

  result
end

def integration_branch(run_root)
  "mv/#{mv_run_parts(run_root).map { |part| ref_component(part) }.join('/')}/integration"
end

def lane_branch(run_root, stage_id, task_id)
  "mv/#{mv_run_parts(run_root).map { |part| ref_component(part) }.join('/')}/lane/#{ref_component(stage_id)}/#{ref_component(task_id)}"
end

def valid_branch!(repo, branch)
  _stdout, stderr, status = git(repo, "check-ref-format", "--branch", branch, allow_failure: true)
  raise MvGitWorktreeError, "derived branch name is invalid: #{branch} #{stderr.to_s.strip}" unless status.success?
end

def resolve_commit(repo, ref)
  git_value(repo, "rev-parse", "--verify", "#{ref}^{commit}")
rescue MvGitWorktreeError
  raise MvGitWorktreeError, "Git ref does not resolve to a commit: #{ref}"
end

def require_expected_sha!(actual, expected, label)
  unless expected.to_s.match?(/\A[a-f0-9]{40}\z/)
    raise MvGitWorktreeError, "#{label} SHA must be an exact 40-character lowercase Git commit"
  end
  raise MvGitWorktreeError, "#{label} SHA is stale: expected #{expected}, current #{actual}" unless actual == expected
end

def branch_exists?(repo, branch)
  git(repo, "show-ref", "--verify", "--quiet", "refs/heads/#{branch}", allow_failure: true).last.success?
end

def safe_new_worktree_path(repo, raw)
  raise MvGitWorktreeError, "--worktree is required" if raw.to_s.empty?

  path = Pathname.new(raw).expand_path.cleanpath
  raise MvGitWorktreeError, "worktree path must be absolute" unless path.absolute?
  raise MvGitWorktreeError, "worktree path must not be the filesystem root" if path.to_s == "/"
  raise MvGitWorktreeError, "worktree path already exists: #{path}" if path.exist? || path.symlink?

  relative = path.relative_path_from(repo).to_s
  if relative != ".." && !relative.start_with?("../")
    raise MvGitWorktreeError, "new worktrees must stay outside the current repository worktree"
  end
  path
rescue ArgumentError
  raise MvGitWorktreeError, "unable to resolve worktree path: #{raw}"
end

def branch_projection(operation:, run_root:, branch:, base_branch:, base_sha:, worktree:, dispatch: nil, dispatch_relative: nil, dispatch_sha256: nil, applied: false)
  task = dispatch&.dig("launch", "task") || {}
  scope = task["exact_scope"] || {}
  recipient = dispatch&.dig("routing_identity", "return_recipient_role") || "overall_director"
  nodes = [
    {"node_id" => base_branch, "node_type" => base_branch == "main" ? "main_branch" : "run_integration_branch"},
    {"node_id" => branch, "node_type" => operation == "init-run" ? "run_integration_branch" : "bounded_dispatch_lane"}
  ]
  edges = [
    {"edge_type" => "branched_from", "from" => branch, "to" => base_branch},
    {"edge_type" => "reviewed_merge_candidate_for", "from" => branch, "to" => base_branch}
  ]

  {
    "status" => applied ? "created" : "dry_run",
    "authority" => "git_transport_only_no_creative_or_promotion_authority",
    "operation" => operation,
    "run_root" => run_root,
    "branch" => branch,
    "base_branch" => base_branch,
    "base_sha" => base_sha,
    "worktree" => worktree.to_s,
    "dispatch" => dispatch && {
      "path" => dispatch_relative,
      "sha256" => dispatch_sha256,
      "dispatch_id" => dispatch["dispatch_id"],
      "stage_id" => scope["stage_id"],
      "section_ids" => Array(scope["section_ids"]),
      "assigned_owner" => dispatch.dig("launch", "authority", "assigned_owner"),
      "return_recipient" => recipient,
      "write_paths" => Array(scope["artifact_paths"])
    },
    "execution_graph" => {"nodes" => nodes, "edges" => edges},
    "merge_policy" => {
      "worker_direct_to_main" => false,
      "director_review_required" => true,
      "merge_creates_creative_truth" => false,
      "delete_branch_automatically" => false
    }
  }
end

def changed_paths(repo, range)
  git_value(repo, "diff", "--name-only", "--diff-filter=ACMR", range).lines.map(&:strip).reject(&:empty?).uniq.sort
end

options = {
  repo: DEFAULT_REPO,
  apply: false,
  base_ref: nil,
  base_sha: nil,
  run_root: nil,
  dispatch: nil,
  worktree: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "usage: ruby scripts/idol_mv_git_worktree.rb COMMAND [options]\ncommands: init-run, open-lane, merge-ready"
  opts.on("--repo PATH") { |value| options[:repo] = Pathname.new(value) }
  opts.on("--run-root PATH") { |value| options[:run_root] = value }
  opts.on("--dispatch PATH") { |value| options[:dispatch] = value }
  opts.on("--base-ref REF") { |value| options[:base_ref] = value }
  opts.on("--base-sha SHA") { |value| options[:base_sha] = value }
  opts.on("--worktree PATH") { |value| options[:worktree] = value }
  opts.on("--apply") { options[:apply] = true }
end

command = ARGV.shift
begin
  parser.parse!(ARGV)
  raise MvGitWorktreeError, "unknown or missing command" unless %w[init-run open-lane merge-ready].include?(command)
  raise MvGitWorktreeError, "unexpected positional arguments" unless ARGV.empty?

  repo = repo_root(options[:repo])

  case command
  when "init-run"
    run_root = options[:run_root].to_s
    mv_run_parts(run_root)
    base_branch = options[:base_ref].to_s.empty? ? "main" : options[:base_ref].to_s
    raise MvGitWorktreeError, "init-run base must be main" unless base_branch == "main"
    base_sha = resolve_commit(repo, "refs/heads/main")
    require_expected_sha!(base_sha, options[:base_sha], "main")
    branch = integration_branch(run_root)
    valid_branch!(repo, branch)
    worktree = safe_new_worktree_path(repo, options[:worktree])
    raise MvGitWorktreeError, "run integration branch already exists: #{branch}" if branch_exists?(repo, branch)
    if options[:apply]
      current_branch = git_value(repo, "branch", "--show-current")
      raise MvGitWorktreeError, "init-run --apply must run from main" unless current_branch == "main"
      clean_worktree!(repo)
      git(repo, "worktree", "add", "-b", branch, worktree.to_s, base_sha)
    end
    puts JSON.pretty_generate(branch_projection(
      operation: command,
      run_root: run_root,
      branch: branch,
      base_branch: base_branch,
      base_sha: base_sha,
      worktree: worktree,
      applied: options[:apply]
    ))
  when "open-lane"
    dispatch, dispatch_path, dispatch_relative = load_dispatch(repo, options[:dispatch], accepted_states: ["prepared"])
    run_root = dispatch.fetch("run")
    mv_run_parts(run_root)
    base_branch = integration_branch(run_root)
    requested_base = options[:base_ref].to_s
    unless requested_base.empty? || requested_base == base_branch
      raise MvGitWorktreeError, "lane base must be its exact run integration branch: #{base_branch}"
    end
    raise MvGitWorktreeError, "run integration branch is missing: #{base_branch}" unless branch_exists?(repo, base_branch)
    base_sha = resolve_commit(repo, "refs/heads/#{base_branch}")
    require_expected_sha!(base_sha, options[:base_sha], "integration branch")
    task = dispatch.dig("launch", "task") || {}
    branch = lane_branch(run_root, task.dig("exact_scope", "stage_id"), task["task_id"])
    valid_branch!(repo, branch)
    worktree = safe_new_worktree_path(repo, options[:worktree])
    raise MvGitWorktreeError, "dispatch lane branch already exists: #{branch}" if branch_exists?(repo, branch)
    if options[:apply]
      current_branch = git_value(repo, "branch", "--show-current")
      unless current_branch == base_branch
        raise MvGitWorktreeError, "open-lane --apply must run from the exact run integration branch: #{base_branch}"
      end
      validate_dispatch!(repo, dispatch_relative)
      clean_worktree!(repo)
      git(repo, "worktree", "add", "-b", branch, worktree.to_s, base_sha)
    end
    projection = branch_projection(
      operation: command,
      run_root: run_root,
      branch: branch,
      base_branch: base_branch,
      base_sha: base_sha,
      worktree: worktree,
      dispatch: dispatch,
      dispatch_relative: dispatch_relative,
      dispatch_sha256: Digest::SHA256.file(dispatch_path).hexdigest,
      applied: options[:apply]
    )
    projection["dispatch_validation"] = options[:apply] ? "current_validator_pass" : "deferred_until_apply"
    puts JSON.pretty_generate(projection)
  when "merge-ready"
    raise MvGitWorktreeError, "--apply is not valid for merge-ready" if options[:apply]
    dispatch, dispatch_path, dispatch_relative = load_dispatch(repo, options[:dispatch], accepted_states: ["reviewed"])
    unless dispatch.dig("director_review", "disposition") == "accept"
      raise MvGitWorktreeError, "merge-ready requires an accepted Director review"
    end
    validate_dispatch!(repo, dispatch_relative)
    run_root = dispatch.fetch("run")
    base_branch = integration_branch(run_root)
    base_sha = options[:base_sha].to_s
    require_expected_sha!(resolve_commit(repo, base_sha), base_sha, "lane base")
    task = dispatch.dig("launch", "task") || {}
    branch = lane_branch(run_root, task.dig("exact_scope", "stage_id"), task["task_id"])
    raise MvGitWorktreeError, "dispatch lane branch is missing: #{branch}" unless branch_exists?(repo, branch)
    current_branch = git_value(repo, "branch", "--show-current")
    unless current_branch == base_branch
      raise MvGitWorktreeError, "merge-ready must run from the exact run integration branch: #{base_branch}"
    end
    clean_worktree!(repo)
    integration_sha = resolve_commit(repo, "refs/heads/#{base_branch}")
    lane_sha = resolve_commit(repo, "refs/heads/#{branch}")
    derived_base_sha = git_value(repo, "merge-base", branch, base_branch)
    require_expected_sha!(derived_base_sha, base_sha, "lane base")
    _out, _err, ancestry = git(repo, "merge-base", "--is-ancestor", base_sha, integration_sha, allow_failure: true)
    raise MvGitWorktreeError, "integration branch no longer descends from the lane base" unless ancestry.success?

    lane_paths = changed_paths(repo, "#{base_sha}...#{lane_sha}")
    raise MvGitWorktreeError, "lane has no committed changes" if lane_paths.empty?
    allowed_paths = Array(task.dig("exact_scope", "artifact_paths")).map(&:to_s).sort
    outside_scope = lane_paths - allowed_paths
    raise MvGitWorktreeError, "lane changed paths outside Dispatch scope: #{outside_scope.join(', ')}" unless outside_scope.empty?
    integration_paths = integration_sha == base_sha ? [] : changed_paths(repo, "#{base_sha}..#{integration_sha}")
    overlap = lane_paths & integration_paths
    raise MvGitWorktreeError, "integration changed the same paths since lane creation: #{overlap.join(', ')}" unless overlap.empty?

    puts JSON.pretty_generate({
      "status" => "merge_ready",
      "authority" => "structural_git_transport_check_only",
      "branch" => branch,
      "head_sha" => lane_sha,
      "base_sha" => base_sha,
      "integration_branch" => base_branch,
      "integration_sha" => integration_sha,
      "dispatch" => {"path" => dispatch_relative, "sha256" => Digest::SHA256.file(dispatch_path).hexdigest},
      "changed_paths" => lane_paths,
      "integration_changed_paths_since_base" => integration_paths,
      "review_required" => true,
      "merge_performed" => false
    })
  end
rescue MvGitWorktreeError, KeyError => error
  warn error.message
  exit 1
end
