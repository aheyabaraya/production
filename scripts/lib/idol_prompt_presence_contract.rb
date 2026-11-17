# frozen_string_literal: true

# Presence-policy validation for generator-facing image prompt text. The
# compiler never writes a dance/choreography sentence. Creative motion language
# must already exist in the 02A model-authored prompt blueprint.
module IdolPromptPresenceContract
  DANCE_TOKEN_PATTERN = /\b(?:dance|dancing|dancer|choreography|choreographic|choreo|formation\s+dance)\b|(?:춤|안무|군무|댄스)/i

  module_function

  def choreography_policy(cut)
    policy = cut["choreography_presence_policy"].to_s.strip
    policy = cut.dig("director_chain", "choreography_presence_policy").to_s.strip if policy.empty?
    policy
  end

  def dance_token?(text)
    text.to_s.match?(DANCE_TOKEN_PATTERN)
  end

  def generator_text_errors(cut, text, label: "generator prompt")
    policy = choreography_policy(cut)
    return [] unless %w[absent minimal_body_gaze_hold_guard].include?(policy)
    return [] unless dance_token?(text)

    ["#{label} must omit every dance/choreography token when choreography_presence_policy is #{policy}; use only the authored visible action/hold"]
  end
end
