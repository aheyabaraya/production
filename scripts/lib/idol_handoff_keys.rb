# frozen_string_literal: true

module IdolHandoffKeys
  module_function

  def slug(value)
    value.to_s.downcase.gsub(/[^0-9a-z가-힣]+/, "-").gsub(/\A-|-+\z/, "")
  end

  def title_key(value, fallback:)
    key = slug(value.nil? || value.to_s.empty? ? fallback : value)
    abort "title key cannot be empty" if key.empty?

    key
  end
end
