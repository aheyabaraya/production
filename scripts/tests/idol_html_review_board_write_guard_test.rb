# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'pathname'
require 'open3'
require 'rbconfig'
require 'digest'
require 'yaml'

IDOL_HTML_WRITE_TEST_ROOT = Pathname.new(__dir__).join('../..').expand_path
IDOL_HTML_WRITE_TEST_RENDERER = IDOL_HTML_WRITE_TEST_ROOT.join('scripts/idol_html_review_board.rb')
source = IDOL_HTML_WRITE_TEST_RENDERER.read
parts = source.split("\noptions = {", 2)
raise 'renderer entrypoint boundary changed' unless parts.length == 2
eval(parts.first, TOPLEVEL_BINDING, IDOL_HTML_WRITE_TEST_RENDERER.to_s)
require IDOL_HTML_WRITE_TEST_ROOT.join('scripts/tests/support/active_review_board_fixture').to_s

class IdolHtmlReviewBoardWriteGuardTest < Minitest::Test
  def setup
    @fixture = ActiveReviewBoardFixture.create
  end

  def teardown
    @fixture.cleanup
  end

  def renderer
    IdolHtmlReviewBoard.new(@fixture.manifest_path, repo_root: IDOL_HTML_WRITE_TEST_ROOT)
  end

  def output
    @fixture.output_path
  end

  def assert_output_kept(expected)
    assert_equal expected, output.read
  end

  def test_all_declared_input_kinds_are_rechecked_before_publish
    receipt = @fixture.mv.run_dir.join('work', 'distinct-receipt.json')
    receipt.write('{"synthetic_receipt":true}')
    doc = @fixture.manifest
    doc.fetch('sections').first.fetch('founder_lineage')['founder_receipt'] = {
      'path' => @fixture.relative(receipt), 'sha256' => Digest::SHA256.file(receipt).hexdigest
    }
    @fixture.manifest_path.write(YAML.dump(doc))
    renderer.write!
    original_output = output.read
    paths = [@fixture.manifest_path, IDOL_HTML_WRITE_TEST_ROOT.join(doc.fetch('sources').first.fetch('path')),
             receipt, IDOL_HTML_WRITE_TEST_ROOT.join(doc.fetch('review_assets').first.fetch('canonical_path'))]
    assert_equal 4, paths.uniq.length
    paths.each do |path|
      board = renderer
      prior = path.binread
      begin
        path.binwrite(prior + "\nchanged\n")
        error = assert_raises(ReviewBoardContractError) { board.write! }
        assert_match(/changed before publish/, error.message)
        assert_output_kept(original_output)
      ensure
        path.binwrite(prior)
      end
    end
  end

  def test_changed_shell_bytes_after_render_are_rejected
    board = renderer
    css = @fixture.mv.run_dir.join('work', 'test-shell.css')
    js = @fixture.mv.run_dir.join('work', 'test-lightbox.js')
    css.write('body { color: black; }')
    js.write('// synthetic shell')
    board.define_singleton_method(:shell_asset_path) { |name| name.end_with?('.css') ? css : js }
    board.define_singleton_method(:render_html) do
      html = super()
      css.write('body { color: red; }')
      html
    end
    assert_raises(ReviewBoardContractError) { board.write! }
    refute output.exist?
    assert_empty output.dirname.glob('.founder-workbench.html.tmp-*')
  end

  def test_competing_validators_do_not_last_writer_win
    first = renderer
    stale = renderer
    reply = first.write!
    original = output.read
    assert_equal Digest::SHA256.hexdigest(original), reply.fetch('output_sha256')
    assert_raises(ReviewBoardContractError) { stale.write! }
    assert_output_kept(original)
    assert_equal reply.keys.sort, renderer.write!.keys.sort
  end

  def test_changed_generated_output_is_not_overwritten
    renderer.write!
    board = renderer
    changed = output.read + "\n<!-- competing generated result -->\n"
    output.write(changed)
    assert_raises(ReviewBoardContractError) { board.write! }
    assert_output_kept(changed)
  end

  def test_write_exception_removes_only_owned_temp
    leftover = output.dirname.join(".founder-workbench.html.tmp-#{Process.pid}-0")
    leftover.write('preexisting unowned temporary file')
    board = renderer
    board.define_singleton_method(:allocate_output_temp!) do
      path, io = super()
      io.define_singleton_method(:write) { |_bytes| raise IOError, 'injected write failure' }
      [path, io]
    end
    assert_raises(IOError) { board.write! }
    assert_equal 'preexisting unowned temporary file', leftover.read
    assert_equal [leftover], output.dirname.glob('.founder-workbench.html.tmp-*')
    refute output.exist?
    assert output.dirname.join('.founder-workbench.html.lock').file?
  end

  def test_replaced_temp_name_is_not_deleted_by_cleanup
    board = renderer
    substitute = nil
    board.define_singleton_method(:allocate_output_temp!) do
      path, io = super()
      substitute = path
      io.define_singleton_method(:fsync) do
        File.rename(path, path.sub_ext('.owned-original'))
        path.write('other writer replacement')
      end
      [path, io]
    end
    assert_raises(ReviewBoardContractError) { board.write! }
    assert_equal 'other writer replacement', substitute.read
    refute output.exist?
  end

  def test_output_symlink_and_hardlink_refuse_replacement
    renderer.write!
    saved = output.read
    linked = output.dirname.join('other-generated.html')
    File.link(output, linked)
    assert_raises(ReviewBoardContractError) { renderer }
    assert_equal saved, linked.read
    linked.unlink
    output.unlink
    linked.write(saved)
    File.symlink(linked, output)
    assert_raises(ReviewBoardContractError) { renderer }
    assert_equal saved, linked.read
  end

  def test_lock_symlink_and_nonregular_path_are_rejected
    lock = output.dirname.join('.founder-workbench.html.lock')
    target = output.dirname.join('unrelated-test.txt')
    target.write('unchanged')
    board = renderer
    File.symlink(target, lock)
    assert_raises(ReviewBoardContractError) { board.write! }
    assert_equal 'unchanged', target.read
    lock.unlink
    lock.mkdir
    assert_raises(ReviewBoardContractError) { renderer.write! }
    refute output.exist?
  end

  def test_lock_path_replacement_after_acquisition_holds
    board = renderer
    swapped = false
    board.define_singleton_method(:verify_lock_identity!) do |io, path|
      unless swapped
        File.rename(path, path.sub_ext('.old-lock'))
        path.write('replacement lock')
        swapped = true
      end
      super(io, path)
    end
    assert_raises(ReviewBoardContractError) { board.write! }
    refute output.exist?
  end

  def test_publish_holds_real_cross_process_flock
    board = renderer
    lock_path = output.dirname.join('.founder-workbench.html.lock')
    observed = nil
    board.define_singleton_method(:allocate_output_temp!) do
      text, error, status = Open3.capture3(
        RbConfig.ruby, '-e', 'File.open(ARGV[0], File::RDWR) { |f| puts(f.flock(File::LOCK_EX | File::LOCK_NB) == false) }', lock_path.to_s
      )
      raise error unless status.success?
      observed = text.strip
      super()
    end
    board.write!
    assert_equal 'true', observed
    assert lock_path.file?
  end

  def test_same_inode_temp_byte_change_holds_before_publish
    board = renderer
    board.define_singleton_method(:allocate_output_temp!) do
      path, io = super()
      original_fsync = io.method(:fsync)
      io.define_singleton_method(:fsync) do
        original_fsync.call
        path.binwrite("mutated same inode")
      end
      [path, io]
    end
    error = assert_raises(ReviewBoardContractError) { board.write! }
    assert_match(/temporary bytes changed/, error.message)
    refute output.exist?
    assert_empty output.dirname.glob('.founder-workbench.html.tmp-*')
  end

  def test_fifo_swap_after_input_precheck_never_blocks_read
    board = renderer
    input = @fixture.mv.run_dir.join('work', 'fifo-input.json')
    input.write('{"value":true}')
    swapped = false
    board.define_singleton_method(:guard_input_file!) do |path, label|
      result = super(path, label)
      if path == input && !swapped
        File.rename(input, input.sub_ext('.original'))
        raise 'mkfifo failed' unless system('mkfifo', input.to_s)
        swapped = true
      end
      result
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(ReviewBoardContractError) { board.send(:load_document, input, 'synthetic FIFO') }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2.0
  end

  def test_parent_symlink_swap_after_read_is_rechecked_before_parse
    board = renderer
    folder = @fixture.mv.run_dir.join('work', 'post-read')
    folder.mkdir
    input = folder.join('input.json')
    input.write('{"value":true}')
    original_open = File.method(:open)
    swapped = false
    wrapper = lambda do |path, *args, &block|
      original_open.call(path, *args) do |io|
        if path.to_s == input.to_s
          original_stat = io.method(:stat)
          calls = 0
          io.define_singleton_method(:stat) do
            calls += 1
            if calls == 2 && !swapped
              moved = folder.sub_ext('.original')
              File.rename(folder, moved)
              File.symlink(moved, folder)
              swapped = true
            end
            original_stat.call
          end
        end
        block.call(io)
      end
    end
    File.stub(:open, wrapper) do
      error = assert_raises(ReviewBoardContractError) { board.send(:load_document, input, 'post-read source') }
      assert_match(/symlink/, error.message)
    end
    assert swapped
  end

  def test_manifest_and_output_parent_symlink_guards
    alias_manifest = @fixture.manifest_path.dirname.join('alias.yaml')
    File.symlink(@fixture.manifest_path, alias_manifest)
    assert_raises(ReviewBoardContractError) { IdolHtmlReviewBoard.new(alias_manifest, repo_root: IDOL_HTML_WRITE_TEST_ROOT) }
    board = renderer
    old_review = output.dirname
    moved = old_review.sub_ext('.original')
    File.rename(old_review, moved)
    File.symlink(moved, old_review)
    assert_raises(ReviewBoardContractError) { board.write! }
    refute moved.join(output.basename).exist?
  end
end
