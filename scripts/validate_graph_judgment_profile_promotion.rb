#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require_relative "lib/idol_graph_judgment_profile_promotion_contract"

ROOT = Pathname.new(__dir__).join("..").expand_path.cleanpath
options = {root: ROOT, registry_status: "shadow_not_default", mode: "active_promotion"}
OptionParser.new do |parser|
  parser.banner = "usage: validate_graph_judgment_profile_promotion.rb [--root PATH] [--registry-status STATUS] [--mode active_promotion|historical_audit] PROMOTION CURRENT_RELEASE"
  parser.on("--root PATH") { |value| options[:root] = Pathname.new(value).expand_path.cleanpath }
  parser.on("--registry-status STATUS") { |value| options[:registry_status] = value }
  parser.on("--mode MODE", %w[active_promotion historical_audit]) { |value| options[:mode] = value }
end.parse!
promotion_arg = ARGV.shift
release_arg = ARGV.shift
abort "usage: validate_graph_judgment_profile_promotion.rb [--root PATH] [--registry-status STATUS] [--mode active_promotion|historical_audit] PROMOTION CURRENT_RELEASE" if promotion_arg.to_s.empty? || release_arg.to_s.empty? || ARGV.any?

root = options.fetch(:root)
promotion_path = Pathname.new(promotion_arg)
promotion_path = root.join(promotion_path) unless promotion_path.absolute?
release_path = Pathname.new(release_arg)
release_path = root.join(release_path) unless release_path.absolute?
abort "profile promotion artifact is missing" unless promotion_path.file?
abort "current profile release is missing" unless release_path.file?

promotion = YAML.safe_load(promotion_path.read, permitted_classes: [Date, Time], aliases: true)
release = YAML.safe_load(release_path.read, permitted_classes: [Date, Time], aliases: true)
abort "profile promotion artifact must be an object" unless promotion.is_a?(Hash)
abort "current profile release must be an object" unless release.is_a?(Hash)

current_release = {
  "path" => release_path.realpath.relative_path_from(root.realpath).to_s,
  "sha256" => Digest::SHA256.file(release_path).hexdigest,
  "release_value_sha256" => release["release_value_sha256"],
  "profile_value_sha256" => release["profile_value_sha256"]
}
binding = {
  "path" => promotion_path.realpath.relative_path_from(root.realpath).to_s,
  "sha256" => Digest::SHA256.file(promotion_path).hexdigest
}
errors = IdolGraphJudgmentProfilePromotionContract.validate_binding(
  root: root,
  binding: binding,
  current_release: current_release,
  profile_id: release.dig("profile", "profile_id"),
  registry_status: options.fetch(:registry_status),
  validation_mode: options.fetch(:mode)
)
abort errors.join("\n") unless errors.empty?

puts "graph creative judgment profile promotion valid"
