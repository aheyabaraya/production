# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"

class ActiveMvFixtureCleanupTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  FIXTURE = ROOT.join("scripts", "tests", "support", "active_mv_fixture.rb")

  def test_process_exit_removes_only_the_fixture_run_and_asset_package
    source = <<~RUBY
      require #{FIXTURE.to_s.dump}
      fixture = ActiveMvFixture.create
      puts fixture.run_container
      puts fixture.asset_package_dir
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", source, chdir: ROOT.to_s)

    assert status.success?, stderr
    paths = stdout.lines.map { |line| Pathname.new(line.strip) }.reject { |path| path.to_s.empty? }
    assert_equal 2, paths.length
    paths.each { |path| refute path.exist?, "fixture path survived child exit: #{path}" }
  end

  def test_minitest_after_run_removes_fixtures_created_during_autorun
    source = <<~RUBY
      require "minitest/autorun"
      require #{FIXTURE.to_s.dump}

      class ActiveMvFixtureAutorunProbe < Minitest::Test
        def test_create_fixture
          fixture = ActiveMvFixture.create
          puts "FIXTURE_RUN_PATH=\#{fixture.run_container}"
          puts "FIXTURE_ASSET_PATH=\#{fixture.asset_package_dir}"
        end
      end
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", source, chdir: ROOT.to_s)

    assert status.success?, stderr
    paths = stdout.lines.map do |line|
      match = line.strip.match(/\AFIXTURE_(?:RUN|ASSET)_PATH=(.+)\z/)
      Pathname.new(match[1]) if match
    end.compact
    assert_equal 2, paths.length
    paths.each { |path| refute path.exist?, "Minitest fixture path survived child exit: #{path}" }
  end
end
