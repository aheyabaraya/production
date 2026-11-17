# frozen_string_literal: true

require "date"
require "json"
require "open3"
require "pathname"
require "yaml"

# Mechanical graph-edge check: a helper return is not contribution until a
# consume/reject/hold receipt is bound. Floor helper counts are not quality.
module IdolHelperConsumptionReceipts
  SCHEMA_RELATIVE = "schemas/harness-helper-consumption-receipt.schema.json"
  PYTHON_RELATIVE = "scripts/idol-video-python"
  SCHEMA_VALIDATOR_RELATIVE = "scripts/validate_json_schema.py"
  FORBIDDEN_AUTO_SKILL = %w[auto_skill_save CONSTRAINTS.md weekly_harness_swarm].freeze

  module_function

  def validate(root:, document:, bind_file:)
    errors = []
    summary = document["internal_delegation_summary"].is_a?(Hash) ? document["internal_delegation_summary"] : {}
    helper_count = summary["helper_count"]
    helpers_used = summary["provider_native_helpers_used"] == true
    runtime_return = document["runtime_return"]
    return errors unless runtime_return.is_a?(Hash)

    receipts = Array(runtime_return["helper_consumption_receipts"])
    expected = helpers_used ? Integer(helper_count) : 0
    if !helpers_used || expected.zero?
      errors << "runtime_return.helper_consumption_receipts must be empty when helpers were unused" unless receipts.empty?
      return errors
    end
    if receipts.length != expected
      errors << "runtime_return.helper_consumption_receipts must have #{expected} bound receipt(s) when helper_count is #{expected}"
    end

    dispatch_id = document["dispatch_id"].to_s
    helper_ids = []
    root = Pathname.new(root)
    receipts.each_with_index do |row, index|
      label = "runtime_return.helper_consumption_receipts[#{index}]"
      path, = bind_file.call(errors, label, row)
      next unless path.respond_to?(:file?) && path.file?

      schema_errors_for(root, path).each { |message| errors << "#{label} #{message}" }
      receipt = load_mapping(path)
      next unless receipt.is_a?(Hash)

      FORBIDDEN_AUTO_SKILL.each do |fragment|
        errors << "#{label} must not import #{fragment}" if receipt.to_s.include?(fragment)
      end
      unless receipt["parent_dispatch_id"].to_s == dispatch_id
        errors << "#{label} parent_dispatch_id must equal dispatch_id"
      end
      helper_id = receipt["helper_id"].to_s
      errors << "#{label} helper_id is missing" if helper_id.empty?
      errors << "#{label} duplicate helper_id #{helper_id}" if helper_ids.include?(helper_id)
      helper_ids << helper_id unless helper_id.empty?
      unless %w[consume reject hold].include?(receipt["director_disposition"].to_s)
        errors << "#{label} director_disposition must be consume, reject, or hold"
      end
    end
    errors
  end

  def load_receipts(root:, document:)
    runtime_return = document["runtime_return"]
    return [] unless runtime_return.is_a?(Hash)

    Array(runtime_return["helper_consumption_receipts"]).map do |row|
      next unless row.is_a?(Hash)

      path = Pathname.new(root).join(row["path"].to_s)
      next unless path.file?

      load_mapping(path)
    end.compact
  end

  def schema_errors_for(root, path)
    python = root.join(PYTHON_RELATIVE)
    validator = root.join(SCHEMA_VALIDATOR_RELATIVE)
    schema = root.join(SCHEMA_RELATIVE)
    stdout, stderr, status = Open3.capture3(
      python.to_s,
      validator.to_s,
      schema.to_s,
      path.to_s,
      chdir: root.to_s
    )
    return [] if status.success?

    [[stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip].reject(&:empty?)
  end

  def load_mapping(path)
    YAML.safe_load(Pathname.new(path).read, permitted_classes: [Date, Time], permitted_symbols: [], aliases: true)
  rescue Psych::Exception, TypeError
    {}
  end
end
