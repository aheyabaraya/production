# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "pathname"
require "open3"
require "rbconfig"
require "yaml"
require "date"

class IdolGrokHandoffFileManagementTest < Minitest::Test
  SOURCE = Pathname.new(ENV.fetch("HANDOFF_SOURCE", File.expand_path("../idol_prepare_grok_video_prompt_handoff.rb", __dir__)))

  def setup
    @tmp = Pathname.new(Dir.mktmpdir("idol-handoff-check-", "/private/tmp"))
    @root = @tmp.join("repo").tap(&:mkdir)
    @run = @root.join("runs/test").tap { |path| FileUtils.mkdir_p(path) }
    @dest = @run.join("handoff/grok/03V")
    source = SOURCE.read
    helpers = source[source.index("def resolve_path")...source.index("def validate_schema")]
    mod = Module.new
    mod.module_eval(helpers, SOURCE.to_s)
    @helper = Object.new.extend(mod)
    @outputs = %w[reference.yaml brief.md request.md trigger.md].to_h { |name| [@dest.join(name), "synthetic #{name}\n"] }
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def held(&block)
    _out, err = capture_io { assert_raises(SystemExit, &block) }
    refute_empty err
  end

  def test_write_and_identical_reuse_preserve_inodes_and_times
    @helper.write_owned_outputs(@outputs, @dest, @run)
    before = @outputs.keys.to_h { |p| [p, [p.stat.ino, p.stat.mtime, p.binread]] }
    @helper.write_owned_outputs(@outputs, @dest, @run)
    assert_equal before, @outputs.keys.to_h { |p| [p, [p.stat.ino, p.stat.mtime, p.binread]] }
    assert_equal @outputs, @outputs.keys.to_h { |p| [p, p.binread] }
  end

  def test_existing_difference_holds_before_creating_missing_outputs
    FileUtils.mkdir_p(@dest)
    prior = @outputs.keys.last
    prior.write("previous reviewed version\n")
    held { @helper.write_owned_outputs(@outputs, @dest, @run) }
    assert_equal "previous reviewed version\n", prior.read
    assert @outputs.keys[0...-1].none?(&:exist?)
  end

  def test_matching_partial_group_resumes_without_rewriting
    FileUtils.mkdir_p(@dest)
    prior, bytes = @outputs.first
    prior.write(bytes)
    inode = prior.stat.ino
    @helper.write_owned_outputs(@outputs, @dest, @run)
    assert_equal inode, prior.stat.ino
    assert @outputs.keys.all?(&:file?)
  end

  def test_source_must_be_inside_declared_owner
    other = @tmp.join("synthetic.txt").tap { |p| p.write("fixture") }
    held { @helper.read_owned_file(other, @root) }
  end

  def test_source_symlink_is_rejected_and_regular_source_reads
    source = @run.join("source.yaml").tap { |p| p.write("synthetic: true\n") }
    link = @run.join("linked.yaml")
    File.symlink(source, link)
    held { @helper.read_owned_file(link, @run) }
    assert_equal source.binread, @helper.read_owned_file(source, @run)
  end

  def test_output_parent_symlink_is_rejected
    other = @root.join("other").tap(&:mkdir)
    File.symlink(other, @run.join("handoff"))
    held { @helper.write_owned_outputs(@outputs, @dest, @run) }
    assert_empty other.children
  end

  def test_output_leaf_symlink_is_rejected_without_target_change
    FileUtils.mkdir_p(@dest)
    other = @run.join("prior.txt").tap { |p| p.write("keep") }
    File.symlink(other, @outputs.keys.first)
    held { @helper.write_owned_outputs(@outputs, @dest, @run) }
    assert_equal "keep", other.read
    assert @outputs.keys.drop(1).none?(&:exist?)
  end

  def test_output_leaf_must_belong_to_handoff_directory
    held { @helper.write_owned_outputs({@run.join("different.md") => "fixture"}, @dest, @run) }
    refute @run.join("different.md").exist?
  end

  def test_existing_directory_cannot_be_read_as_source
    held { @helper.read_owned_file(@run, @root) }
  end

  def test_cli_rejects_invalid_version_before_any_source_load
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SOURCE.to_s, @run.to_s,
      "--root", @root.to_s, "--source-pack", "missing.yaml", "--version", "invalid label",
      "--founder-requested", "--write")
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "local handoff version must be a filename label"
    refute @dest.exist?
  end
end
