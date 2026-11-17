# frozen_string_literal: true

require "yaml"

module IdolCheckpointClosureCatalog
  CATALOG_RELATIVE = "automation/harness-checkpoint-closure-catalog.yaml"
  GENERIC_FOLLOW = /\bfollow\b.*\b(?:the\s+)?(?:registered\s+)?(?:skill|recipe|everything)\b/i

  module_function

  def catalog_path(root)
    Pathname.new(root).join(CATALOG_RELATIVE)
  end

  def load(root)
    document = YAML.safe_load(catalog_path(root).read, aliases: true)
    raise TypeError, "checkpoint closure catalog must be an object" unless document.is_a?(Hash)
    document
  end

  def matching_groups(root, profile_id:, checkpoint_id:)
    Array(load(root)["checkpoints"]).select do |row|
      next false unless row.is_a?(Hash)

      Array(row["profile_ids"]).map(&:to_s).include?(profile_id.to_s) &&
        Array(row["checkpoint_ids"]).map(&:to_s).include?(checkpoint_id.to_s)
    end
  end

  def recipe_rows(root, profile_id:, checkpoint_id:)
    matching_groups(root, profile_id: profile_id, checkpoint_id: checkpoint_id).flat_map do |group|
      Array(group["rows"]).select { |row| row.is_a?(Hash) }
    end
  end

  def recipe_requirement_ids(root, profile_id:, checkpoint_id:)
    recipe_rows(root, profile_id: profile_id, checkpoint_id: checkpoint_id).map { |row| row["requirement_id"].to_s }
  end

  def generic_follow_skill?(row)
    return false unless row.is_a?(Hash)

    [row["source_locator"], row["affected_scope"], row["expected_output_target"]].any? do |value|
      GENERIC_FOLLOW.match?(value.to_s)
    end
  end
end
