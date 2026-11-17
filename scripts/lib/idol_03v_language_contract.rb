# frozen_string_literal: true

module Idol03VLanguageContract
  DANCE_UNAMBIGUOUS_PATTERN = /\b(?:dance|dancing|dance[- ]?routine|dance phrase|choreograph\w*|k[- ]?pop dance|waacking|voguing|tutting|house footwork|heels choreography|dancehall|twerking)\b|(?:춤|안무|군무|댄스|팝핑|락킹|왁킹|보깅|터팅|트월킹)/i
  DANCE_AMBIGUOUS_STYLE_PATTERN = /\b(?:popping|locking)\b/i
  DANCE_STYLE_CONTEXT_PATTERN = /\b(?:dance|routine|footwork|isolation|choreo|style|technique)\b|(?:춤|안무|군무|댄스|루틴|풋워크|아이솔레이션|스타일|테크닉)/i
  SYNCHRONIZED_DANCE_PATTERN = /\b(?:synchroni[sz]ed|formation)\b.{0,60}\b(?:footwork|steps?|body isolations?|routine|phrase)\b|(?:동기화된|맞춘|맞춰|일제히|동시에|대형).{0,30}(?:스텝|발동작|몸동작|아이솔레이션|루틴)/i
  BEAT_MATCHED_STEP_PATTERN = /(?:\b(?:beat|rhythm)\b.{0,35}\b(?:same|matching|synchroni[sz]ed)\b.{0,25}\b(?:step|footwork|body move)|\b(?:same|matching)\b.{0,20}\b(?:step|footwork)\b.{0,30}\b(?:beat|rhythm)\b|(?:박자|리듬|비트).{0,25}(?:맞춰|맞춘|따라|동시에|일제히).{0,25}(?:같은|동일한)?\s*(?:스텝|발동작|몸동작).{0,25}(?:반복|맞추|밟|움직))/i
  NEGATED_DANCE_PATTERNS = [
    /\b(?:no|without)\s+(?:any\s+|added\s+|full\s+|new\s+)?(?:dance|dancing|choreograph\w*|synchroni[sz]ed (?:step|movement|routine)s?)\b/i,
    /\b(?:do not|don't|never)\s+(?:(?:add|insert|use|perform|include|show|activate)\s+)?(?:any\s+|full\s+|new\s+)?(?:dance|dancing|choreograph\w*|synchroni[sz]ed (?:step|movement|routine)s?)\b/i,
    /(?:춤|안무|군무|댄스|팝핑|락킹)(?:\s*동작)?(?:을|를|은|는|이|가)?\s*(?:(?:넣|추가하|사용하|쓰|하|추|보이|활성화하)\s*)?지\s*않(?:는다|음|도록)?/i,
    /(?:춤|안무|군무|댄스|팝핑|락킹)(?:\s*동작)?(?:을|를|은|는)?\s*(?:사용|추가|삽입|활성화)?\s*(?:없이|없음|금지)/i,
    /(?:박자|리듬|비트).{0,30}(?:같은|동일한|맞춘|맞춰|일제히|동시에).{0,20}(?:스텝|발동작|몸동작).{0,30}(?:않|금지|없)/i
  ].freeze

  ENGLISH_APPEARANCE_INVENTORY_PATTERN = /(?:
    identit(?:y|ies).{0,100}(?:styling|outfits?).{0,100}(?:hair|makeup|jewelry)
    |(?:face|hair).{0,100}makeup.{0,100}(?:jewelry|wardrobe)
    |(?:face\s*(?:shape|features?|contour)|hair\s*(?:style|color|length)|makeup|jewel(?:ry|lery)|earrings?|necklace|wardrobe|outfit|body\s*proportions?|limb\s*proportions?).{0,100}(?:keep|preserve|retain|unchanged|same|identical|restate|reproduce)
  )/imx

  KOREAN_APPEARANCE_CATEGORY_PATTERNS = [
    /(?:얼굴형|얼굴\s*(?:윤곽|생김새|이목구비|외모)|이목구비)/,
    /(?:헤어\s*(?:스타일|컬러|색|길이)|머리\s*(?:모양|스타일|색|길이)|(?:긴|짧은|검은|금발|갈색|붉은)\s*머리(?:카락)?)/,
    /(?:메이크업|화장(?:법|색)?)/,
    /(?:장신구|주얼리|귀걸이|목걸이|팔찌|반지|피어싱)/,
    /(?:의상|옷차림|착장|드레스|재킷|스커트|바지\s*실루엣)/,
    /(?:신체\s*비율|몸(?:매)?\s*비율|체형|체격|다리\s*길이|팔\s*길이)/
  ].freeze
  KOREAN_APPEARANCE_RESTATEMENT_PATTERN = /(?:그대로|동일(?:하게|한)?|같은|변경하지|바꾸지|유지(?:하|해|한다|하고)|보존(?:하|해|한다)|고정(?:하|해|한다)|재현(?:하|해|한다)|복제(?:하|해|한다)|묘사(?:하|해|한다)|입고|착용(?:하|해|한다))/
  IMAGE_SOURCE_LOCK_POSITIVE_PATTERNS = [
    /\b(?:use|treat|keep)\b.{0,60}\b(?:source image|image\d?|visual source)\b.{0,40}\b(?:as|control|lock|unchanged|authoritative|complete)\b/i,
    /\b(?:use|treat)\b.{0,60}\bas\s+(?:the\s+)?(?:complete\s+)?visual source\b/i,
    /\b(?:source image|image\d?)\b.{0,50}\b(?:controls?|locks?|remains? authoritative)\b/i,
    /\bkeep\b.{0,40}\bvisible appearance\b.{0,30}\b(?:unchanged|identical|the same)\b/i,
    /(?:완전한\s*시각\s*소스)(?:로|로서)?\s*(?:사용|삼|취급|고정|따르)/,
    /(?:이미지|@image\d?).{0,35}(?:시각\s*(?:기준|소스)|완전한\s*소스).{0,25}(?:사용|삼|취급|고정|따르)/,
    /(?:보이는\s*외형|외형과\s*장면|장면).{0,35}(?:그대로\s*)?(?:유지|보존|고정|변경하지|바꾸지)/
  ].freeze
  IMAGE_SOURCE_LOCK_NEGATION_PATTERNS = [
    /\b(?:do\s+not|don't|never|must\s+not|should\s+not)\b.{0,45}\b(?:use|treat|accept|follow|keep)\b.{0,70}\b(?:source image|image\d?|visual source)\b/i,
    /\b(?:source image|image\d?|visual source)\b.{0,55}\b(?:is\s+not|isn't|must\s+not|should\s+not|cannot|can't)\b.{0,35}\b(?:source|control|lock|authoritative)\b/i,
    /(?:완전한\s*시각\s*소스|이미지.{0,30}시각\s*(?:기준|소스)).{0,25}(?:사용|삼|취급|고정|따르)(?:하)?지\s*않/,
    /(?:완전한\s*시각\s*소스|이미지.{0,30}시각\s*(?:기준|소스)).{0,20}(?:아니|금지|거부)/
  ].freeze

  module_function

  def dance_activation?(value)
    deep_text_values(value).any? do |text|
      audit = NEGATED_DANCE_PATTERNS.reduce(text.to_s) { |memo, pattern| memo.gsub(pattern, " ") }
      audit.match?(DANCE_UNAMBIGUOUS_PATTERN) ||
        audit.match?(SYNCHRONIZED_DANCE_PATTERN) ||
        audit.match?(BEAT_MATCHED_STEP_PATTERN) ||
        (audit.match?(DANCE_AMBIGUOUS_STYLE_PATTERN) && audit.match?(DANCE_STYLE_CONTEXT_PATTERN))
    end
  end

  def dance_token?(value)
    deep_text_values(value).any? do |text|
      probe = text.to_s
      probe.match?(DANCE_UNAMBIGUOUS_PATTERN) ||
        probe.match?(SYNCHRONIZED_DANCE_PATTERN) ||
        probe.match?(BEAT_MATCHED_STEP_PATTERN) ||
        (probe.match?(DANCE_AMBIGUOUS_STYLE_PATTERN) && probe.match?(DANCE_STYLE_CONTEXT_PATTERN))
    end
  end

  def appearance_restatement_inventory?(value)
    deep_text_values(value).any? do |text|
      normalized = text.to_s.unicode_normalize(:nfc)
      next true if normalized.match?(ENGLISH_APPEARANCE_INVENTORY_PATTERN)

      category_count = KOREAN_APPEARANCE_CATEGORY_PATTERNS.count { |pattern| normalized.match?(pattern) }
      category_count.positive? && normalized.match?(KOREAN_APPEARANCE_RESTATEMENT_PATTERN)
    end
  end

  def image_source_lock?(value)
    text = deep_text_values(value).join(" ").unicode_normalize(:nfc)
    return false if text.empty?
    return false if IMAGE_SOURCE_LOCK_NEGATION_PATTERNS.any? { |pattern| text.match?(pattern) }

    IMAGE_SOURCE_LOCK_POSITIVE_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def deep_text_values(value)
    case value
    when Hash
      value.values.flat_map { |item| deep_text_values(item) }
    when Array
      value.flat_map { |item| deep_text_values(item) }
    when String
      [value]
    else
      []
    end
  end
end
