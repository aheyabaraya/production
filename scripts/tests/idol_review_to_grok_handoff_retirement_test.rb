# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'open3'
require 'rbconfig'
require 'digest'

class IdolReviewToGrokHandoffRetirementTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join('../..').expand_path
  ORIGINAL = ROOT.join('legacy-imports/retired-guidance/scripts/idol_review_to_grok_handoff.rb')
  STUB = ROOT.join('scripts/idol_review_to_grok_handoff.rb')
  ORIGINAL_LIVE_PATH = ROOT.join('scripts/idol_review_to_grok_handoff.rb')
  SHA = '2f1dbf23bb6458bf36fec6e3205fabad327abee2abb9c1a64514ea919df3cb11'

  def fake_environment
    Dir.mktmpdir('idol-wrapper-retirement-', '/private/tmp') do |tmp|
      bin = File.join(tmp, 'bin')
      run = File.join(tmp, 'run')
      marker = File.join(tmp, 'child-invocation')
      FileUtils.mkdir_p([bin, run])
      fake = File.join(bin, 'ruby')
      File.write(fake, "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$IDOL_AUDIT_CHILD_MARKER\"\necho 'synthetic first child blocked' >&2\nexit 77\n")
      File.chmod(0o755, fake)
      env = {'PATH' => bin + File::PATH_SEPARATOR + ENV.fetch('PATH'), 'IDOL_AUDIT_CHILD_MARKER' => marker}
      # All these are valid OLD-wrapper arguments. Adding its unsupported
      # --source-pack would short-circuit the old parser and make a weak test.
      arguments = [run, '--write', '--founder-requested', '--pass-date', '2026-01-01',
                   '--album-key', 'synthetic-album', '--title-key', 'synthetic-title', '--no-sync-grok-imagine']
      yield env, run, marker, arguments
    end
  end

  def test_original_counterfactual_reaches_first_child_before_handoff
    assert_equal SHA, Digest::SHA256.file(ORIGINAL).hexdigest
    fake_environment do |env, run, marker, arguments|
      loader = 'source = File.binread(ARGV.shift); original = ARGV.shift; eval(source, TOPLEVEL_BINDING, original)'
      _out, error, status = Open3.capture3(env, RbConfig.ruby, '-e', loader,
        ORIGINAL.to_s, ORIGINAL_LIVE_PATH.to_s, *arguments, chdir: ROOT.to_s)
      refute status.success?
      assert File.file?(marker), error
      assert_includes File.read(marker), 'scripts/idol_founder_pass_harness.rb'
      assert_includes File.read(marker), '--write'
      assert_empty Dir.children(run)
    end
  end

  def test_stub_refuses_legacy_approved_write_flags_without_first_child
    fake_environment do |env, run, marker, arguments|
      out, error, status = Open3.capture3(env, RbConfig.ruby, STUB.to_s, *arguments, chdir: ROOT.to_s)
      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "retired: scripts/idol_review_to_grok_handoff.rb is historical evidence only\n", error
      refute File.exist?(marker)
      refute_includes error, run
      refute_includes error, 'synthetic-title'
      assert_empty Dir.children(run)
    end
  end
end
