#!/usr/bin/env ruby
# frozen_string_literal: true

module IdolSkillContractPaths
  PATH_PATTERN = %r{
    (?<![A-Za-z0-9_.-])
    (
      AGENTS\.md
      |
      (?:(?:
          \.grok/skills|skills|schemas|scripts|wiki|handoff|analytics|catalog|assets|runs|
          automation|business-marketing|source-materials|reference-library|cf|references|modules
        )
        /[A-Za-z0-9가-힣._/\-*]+
      )
    )
  }x

  PLACEHOLDER_PATTERN = /
    YYYY|CONTENT_ID|ALBUM_KEY|TITLE_KEY|TITLE_SONG_KEY|Mxx|M01-M13|
    path\/to|RUN_ROOT|SOURCE|DEST|INPUT|OUTPUT|\*|\.\.\.
  /x

  TRAILING_PUNCTUATION = /[.,;:)\]}]+$/

  module_function

  def candidate_paths(text)
    candidates = []

    text.scan(/\[[^\]]+\]\(([^)]+)\)/) do |match|
      # A Markdown fragment locates a heading within the referenced file.
      candidates << match.first.partition("#").first
    end

    text.scan(/`([^`\n]+)`/) do |match|
      candidates.concat(path_fragments(match.first))
    end

    candidates.concat(path_fragments(text))
    candidates.map { |value| normalize_candidate(value) }.compact.uniq
  end

  def path_fragments(text)
    text.to_s.scan(PATH_PATTERN).flatten
  end

  def normalize_candidate(value)
    text = value.to_s.strip
    return nil if text.empty?
    return nil if text.start_with?("http://", "https://", "mailto:", "#")

    text = text.sub(TRAILING_PUNCTUATION, "")
    return nil if text.empty? || text.match?(PLACEHOLDER_PATTERN)

    text
  end
end
