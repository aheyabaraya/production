# frozen_string_literal: true

require "json"
require "pathname"

module IdolVideoPromptSectionQaContract
  module_function

  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  SCHEMA = ROOT.join("schemas", "video-prompt-section-qa.schema.json")

  def document
    @document ||= JSON.parse(SCHEMA.read)
  end

  def required_check_ids
    Array(document.dig("properties", "sections", "items", "properties", "checked_fields", "required")).map(&:to_s).freeze
  end

  def section_status_values
    Array(document.dig("properties", "sections", "items", "properties", "status", "enum")).map(&:to_s).freeze
  end

  def check_status_values
    Array(document.dig("$defs", "checkStatus", "enum")).map(&:to_s).freeze
  end
end
