# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class IdolScriptRegistryCheckTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  CHECKER = ROOT.join("scripts", "idol_script_registry_check.rb")
  STATE_CHECKER = ROOT.join("scripts", "idol_harness_state_check.rb")

  def fixture
    directory = Pathname.new(Dir.mktmpdir("idol-script-registry-test-"))
    FileUtils.mkdir_p(directory.join("scripts", "registry"))
    FileUtils.mkdir_p(directory.join("automation"))
    directory.join("scripts", "demo.rb").write("#!/usr/bin/env ruby\nputs :ok\n")
    directory.join("scripts", "README.md").write(<<~README)
      # Start Here
      scripts/INDEX.md
      automation/idol-script-registry.yaml
      scripts/registry/
    README
    directory.join("scripts", "INDEX.md").write(<<~INDEX)
      # Index
      <!-- idol-script-registry: complete-roster -->
      scripts/demo.rb
      registry/demo.md
    INDEX
    directory.join("scripts", "registry", "demo.md").write("# Demo\n\n` scripts/demo.rb `\n")
    registry = {
      "schema_version" => "idol-script-registry.v1",
      "status" => "active",
      "script_roots" => [{
        "id" => "top_level_scripts",
        "path" => "scripts",
        "include_globs" => ["*.rb"],
        "exclude_paths" => []
      }],
      "documentation_surfaces" => {
        "start_here" => { "id" => "start_here", "path" => "scripts/README.md", "kind" => "start_here", "required" => true },
        "index" => { "id" => "full_index", "path" => "scripts/INDEX.md", "kind" => "full_index", "required" => true },
        "role_guides" => [{ "id" => "demo", "path" => "scripts/registry/demo.md", "kind" => "role_guide", "required" => true, "role" => "Demo" }]
      },
      "authority_profiles" => {
        "mechanical_default" => {
          "creative_truth" => "forbidden",
          "founder_approval" => "never_inferred",
          "external_action" => "closed_by_default",
          "caveat" => "mechanical only"
        }
      },
      "script_entries" => [{
        "path" => "scripts/demo.rb",
        "guide_id" => "demo",
        "status" => "active",
        "authority_profile" => "mechanical_default"
      }]
    }
    registry_path = directory.join("automation", "idol-script-registry.yaml")
    registry_path.write(YAML.dump(registry))
    [directory, registry, registry_path]
  end

  def run_checker(root, registry_path)
    stdout, stderr, status = Open3.capture3(
      "ruby", CHECKER.to_s, "--json", "--root", root.to_s, "--registry", registry_path.to_s,
      chdir: ROOT.to_s
    )
    [JSON.parse(stdout), stderr, status]
  end

  def test_machine_registry_passes_without_readme_script_prose
    root, _registry, registry_path = fixture
    report, stderr, status = run_checker(root, registry_path)
    assert status.success?, stderr
    assert_equal "pass", report.fetch("status")
    assert_equal 1, report.fetch("discovered_count")
    assert_empty report.fetch("missing_entries")
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_missing_discovered_path_fails_closed
    root, _registry, registry_path = fixture
    root.join("scripts", "new.rb").write("puts :new\n")
    report, _stderr, status = run_checker(root, registry_path)
    refute status.success?
    assert_equal "fail", report.fetch("status")
    assert_includes report.fetch("missing_entries"), "scripts/new.rb"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_stale_declared_path_fails_closed
    root, registry, registry_path = fixture
    registry["script_entries"] << {
      "path" => "scripts/not-installed.rb",
      "guide_id" => "demo",
      "status" => "active",
      "authority_profile" => "mechanical_default"
    }
    registry_path.write(YAML.dump(registry))
    report, _stderr, status = run_checker(root, registry_path)
    refute status.success?
    assert_equal "fail", report.fetch("status")
    assert_includes report.fetch("stale_entries"), "scripts/not-installed.rb"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_malformed_registry_fails_closed_without_stack_trace
    root, registry, registry_path = fixture
    registry.delete("script_roots")
    registry_path.write(YAML.dump(registry))
    report, stderr, status = run_checker(root, registry_path)
    refute status.success?, stderr
    assert_equal "fail", report.fetch("status")
    assert_includes report.fetch("errors").join("\n"), "script_roots must be a non-empty array"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_state_checker_uses_machine_registry_not_readme_labels
    source = STATE_CHECKER.read(encoding: "UTF-8")
    assert_includes source, "automation/idol-script-registry.yaml"
    refute_includes source, "registry_items_after_label"
    assert_includes source, 'artifact: "automation/idol-script-registry.yaml"'
  end
end
