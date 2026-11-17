# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "yaml"
require_relative "active_audio_branch_cut_placement_fixture"

class ActiveProductionCutReviewFixture
  ROOT = ActiveMvFixture::ROOT
  PRODUCER = ROOT.join("scripts", "idol_prepare_production_cut_review.rb")

  attr_reader :source_fixture, :run_dir, :review_path, :review

  def self.create
    fixture = new
    fixture.build
  rescue StandardError
    fixture&.cleanup
    raise
  end

  def build
    @source_fixture = ActiveAudioBranchCutPlacementFixture.create
    @run_dir = source_fixture.run_dir
    @review_path = run_dir.join("03-production-cut-review.yaml")
    result = run_producer(write: true)
    unless result.fetch(:status).success?
      raise "Production Cut review fixture build failed: #{result.fetch(:stderr)}\n#{result.fetch(:stdout)}"
    end
    @review = YAML.safe_load(review_path.read, aliases: true)
    self
  end

  def cleanup
    source_fixture&.cleanup
  end

  def run_producer(write: false)
    command = [
      RbConfig.ruby,
      PRODUCER.to_s,
      run_dir.to_s,
      "--root",
      ROOT.to_s,
      "--master-storyboard",
      source_fixture.image_fixture.mv.storyboard_path.to_s,
      "--generated-branch-cut-review",
      source_fixture.review_path.to_s
    ]
    command << "--write" if write
    stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
    {stdout: stdout, stderr: stderr, status: status}
  end

  def rewrite_review
    review_path.write(YAML.dump(review))
  end

  def reload_review
    @review = YAML.safe_load(review_path.read, aliases: true)
  end

  def artifact_ref(path)
    {
      "path" => Pathname.new(path).expand_path.relative_path_from(ROOT).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest
    }
  end
end
