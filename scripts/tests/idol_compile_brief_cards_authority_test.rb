# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require "yaml"

class IdolCompileBriefCardsAuthorityTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCRIPT = ROOT.join("scripts", "idol_compile_brief_cards.rb")

  def test_write_creates_only_noncanonical_candidate_and_index
    Dir.mktmpdir("idol-brief-card-authority-", "/private/tmp") do |directory|
      run = Pathname.new(directory).join("0715_TEST")
      run.mkpath
      storyboard = run.join("02A-master-storyboard.yaml")
      packets = run.join("02B-prompt-packets.yaml")
      storyboard.write(YAML.dump(
        "schema_version" => "1.5",
        "master_storyboard" => [],
        "packet_expansion_contract" => {"beat_expansion_index" => []}
      ))
      packets.write(YAML.dump("schema_version" => "1.4", "prompt_packets" => []))
      before = [Digest::SHA256.file(storyboard).hexdigest, Digest::SHA256.file(packets).hexdigest]

      stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT.to_s, run.to_s, "--pass-date", "2026-07-17", "--write",
        chdir: ROOT.to_s
      )

      assert status.success?, [stdout, stderr].join("\n")
      after = [Digest::SHA256.file(storyboard).hexdigest, Digest::SHA256.file(packets).hexdigest]
      assert_equal before, after

      candidate = run.join("work", "brief-card-compile", "compile-candidate.yaml")
      index = run.join("handoff", "slot-compile-index-2026-07-17.yaml")
      assert candidate.file?
      assert index.file?
      document = YAML.safe_load(candidate.read, aliases: true)
      assert_equal "derived_noncanonical_candidate", document["status"]
      assert_includes stdout, '"canonical_02a_or_02b_written": false'
    end
  end
end
