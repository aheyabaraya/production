# IDOL 창작 판정 권한 및 호출 경로 감사

- 감사일: 2026-07-14
- 기준: 로컬 `main` + 현재 dirty worktree
- 기준 커밋: `a5a284e` (`Replace mechanical creative gates with contextual LLM review`)
- 범위: 활성 01 / 02 / 02A / Storyboard Review / 02B / 03V와 공유 gate, schema, registry, test
- 실행 권한: `gpt-5.6-sol / XHigh` semantic owner
- 제외: 외부 접근, 다운로드, 업로드, 유료 호출, 이미지 생성, push

## Founder 요약

직전 커밋의 방향은 상위 정책에서는 옳았지만 실제 실행 경로까지 완성되어
있지 않았다. 정책은 창작 적합성을 LLM 문맥 검토에 맡겼으나, runtime에는
카메라 vocabulary 13종, 대안 개수, 신체 부위 칸, 춤 단어, prompt substring,
정책 문구 정규식, source path token, 비율과 중복 prompt 같은 신호가 여전히
창작 pass/fail을 결정했다. Stage registry는 01~02B schema/validator와 끊겨
있었고, 02A LLM reviewer receipt는 실제 실행 기록 없이 자기기입 문자열로
통과할 수 있었다.

이번 수정은 기계 안전장치를 삭제하지 않았다. ID·enum·경로·SHA-256·정확한
coverage·exact-copy·output ownership·실행 parameter·approval·receipt provenance는
계속 기계가 검증한다. 이야기, 관계, 사건 인과, 몸·표정·시선, 카메라 적합성,
참조 적용, 반복/reprise, parent/child 충분성, 풍부함은 section LLM과 whole-film
LLM만 판정하도록 활성 경로를 분리했다.

최종 재검수에서는 03V 활성 v3 경로도 다시 처음부터 추적했다. 이 경로에는
춤 token, 추상·일반 표현 정규식, prose 길이, prompt 내 exact phrase, semantic
reversal/similarity, 19개 status와 24자 prose 칸이 남아 있었다. 이 신호들은
같은 화면 의도를 자연스럽게 다시 쓴 문장을 실패시키고, 반대로 정답 문구를
복창한 얇은 motion prompt를 통과시킬 수 있었다. 활성 v3에서는 이를 제거하고
manifest/index exact projection과 source/image bytes/hash/order, coverage, 실행
provenance만 기계 검증하며 section LLM과 별도 whole-timeline root가 창작 적합성을
판정하게 바꿨다. legacy v1/v2는 읽기 호환만 유지하며 readiness를 닫을 수 없다.
마지막 문장형 검수에서 cue마다 다섯 칸을 요구하던 `camera_capture`, 70–85% word
allocation, 고정 prompt 순서, dance token 금지도 추가로 발견했다. v3는 통합
`camera_route`를 창작 handoff로 삼고 분리 camera axes를 선택적 호환 projection으로
낮췄으며, skill은 비율·문장 순서·token 금지 대신 장면별 관련 화면 증거를 묻는다.

지침은 내용을 더 압축해 누락을 만들지 않도록 안전 상한만 소폭 확장했다.
`AGENTS.md` 검토 상한은 5,000→5,200단어, 정적 harness startup 상한은
10,000→10,200단어다. 4,000/8,500단어의 관리 목표와 경고는 유지했으므로
팽창을 정상화하지 않으며, 최종 검사 시점 로컬 정본 4,955/9,837단어는 통과한다.

ONE MOVE 00/01/02/02A/02B 창작 정본은 이 작업의 patch 대상에 넣지 않았다.
다만 공유 dirty worktree에서 최종 검증 중 01/02/02A가 2026-07-14 18:41 KST에
별도로 갱신되어, 이 감사의 앞선 checkpoint와 최종 SHA-256이 달라졌다. 해당
동시 변경을 되돌리거나 stale SHA에 맞추지 않고 현재 로컬 정본으로 보존했다.
00과 02B는 앞선 checkpoint와 동일하다.

## 실제 연결 지도

```text
AGENTS.md
  ├─ protected quality invariants / priority / Founder authority
  └─ Required Starting Ritual
      ↓
wiki/production-system.md + wiki/INDEX.md
  └─ route/read-model discovery
      ↓
conditional policies
  ├─ creative-production-constitution.md
  │    └─ 창작 판단과 deterministic authority 경계
  ├─ harness-routing-and-sources.md
  │    └─ source/model/owner/section route
  └─ section-production.md
       └─ section shard → merge → section review → whole-film review → Founder HTML
      ↓
owning skills and required modules
  ├─ 01: skills/idol-mv-director/**
  ├─ 02/02A/02B: skills/idol-generation/**
  ├─ 03V: skills/idol-video-prompt/**
  └─ Grok native owner: .grok/skills/idol-grok-harness-owner/**
      ↓
transport contracts
  ├─ schemas/song-choreography-performance-mv-map.schema.json
  ├─ schemas/generation-map.schema.json
  ├─ schemas/master-storyboard.schema.json
  ├─ schemas/prompt-packets.schema.json
  ├─ schemas/02a-creative-context-review.schema.json
  ├─ schemas/llm-review-execution-record.schema.json
  ├─ schemas/video-prompt-manifest.schema.json
  ├─ schemas/video-prompt-section-qa.schema.json
  └─ schemas/03v-creative-context-review-execution-record.schema.json
      ↓
automation/harness-stage-registry.yaml
  ├─ stage owner / upstream / schema / validator command
  ├─ decision ownership and downstream projection
  └─ deterministic vs LLM authority declaration
      ↓
actual local runtime
  ├─ scripts/idol_harness_state_check.rb
  ├─ scripts/idol_harness_expert_gate.rb
  ├─ scripts/idol_prompt_packet_compile.rb
  ├─ scripts/validate_02b_imagegen_contract.rb
  ├─ scripts/validate_02a_creative_context_review.rb
  ├─ scripts/validate_video_prompt_manifest.rb
  ├─ scripts/validate_video_prompt_index.rb
  └─ scripts/validate_video_prompt_section_qa_readiness.rb
      ↓
hash-bound section reviewer execution records
  → hash-bound whole-film reviewer execution record
  → same review projected into hash-bound Founder HTML
  → Founder pass / hold / reject

Audio–Frame Placement
  → 03V manifest v3
  → exact manifest/index projection + one-section ownership
  → hash-bound section contextual review v2
  → separate whole-timeline root reconciliation
  → readiness
  → Founder Motion Playback Review
```

Registry는 validator command를 선언하고 경로 연결을 검증하는 semantic registry다.
각 validator를 한 번에 실행하는 workflow engine은 아니다. 현재 run readiness의
실제 판정은 state check와 expert gate가 직접 파일을 찾고 하위 validator를
호출하는 구조이므로, registry 연결과 runtime hard-code를 둘 다 감사했다.

## Stage별 authority와 호출

| Stage | 창작 정본 owner | schema / 주요 runtime | 기계 권한 | LLM 권한 |
| --- | --- | --- | --- | --- |
| 01 | 섹션 의미, 사건 유형과 인과, 관계 변화, 세계 규칙, 감정 route, choreography role, camera family | `song-choreography-performance-mv-map.schema.json`; `idol_harness_state_check.rb`; `idol_harness_expert_gate.rb` | 타입, ID, source/hash, section coverage, declared contract 존재 | 선택한 사건과 카메라가 곡·관계·화면에 맞는지 |
| 02 | 생성 coverage와 output allocation | `generation-map.schema.json`; state/expert gate | cut/section pointer, coverage, budget/approval | coverage가 장면을 납작하게 만들거나 빠뜨리는지 |
| 02A | 01 락 안의 cut-local visible state, 정확한 camera geometry/composition, child keyframe progression, transition endpoint | `master-storyboard.schema.json`; storyboard contract; expert gate | ID/order/exact cover, parent-child link, hash, source carry | 사건의 구체성, parent/child 역할, 표정·시선·깊이·빛·연결 |
| Review | section과 whole-film 문맥 판정 | `02a-creative-context-review.schema.json`; `llm-review-execution-record.schema.json`; `validate_02a_creative_context_review.rb` | reviewer assignment, source SHA, 실제 execution record SHA, scope, 완료, HTML SHA | section verdict, whole-film progression, reprise, continuity, 수정 지시 |
| 02B | provider-neutral exact compile와 export state | `prompt-packets.schema.json`; compiler; `validate_02b_imagegen_contract.rb` | exact blueprint copy, prompt/hash, reference order/path/SHA, packet ownership, route, approval | prompt가 장면을 충분히 전달하는지는 02A/LLM review로 회귀 |
| 03V | passed frame 사이의 body/object/environment/camera/timing/endpoint motion | `video-prompt-manifest.schema.json`; `video-prompt-section-qa.schema.json`; manifest/index/readiness validators | source와 image bytes/hash/order, ID, section/packet coverage, manifest→index exact projection, 실행 record와 owner/profile | section motion의 구체성·개연성·카메라·끝점·연결과 whole-timeline 반복/진행 |

01과 02A의 경계는 registry decision contract에도 고정했다. 같은 route 안의
정확한 몸/오브젝트 상태와 구도 수정은 02A가 소유하지만, action type·관계·인과·
세계 규칙·감정 route·camera family를 바꾸면 먼저 01로 돌아간다. 02B는 어느
쪽의 창작 결정도 새로 만들 수 없다. 03V는 실제 passed image와 Audio–Frame
Placement를 motion으로 구체화하지만, 이전 stage의 appearance·장면·frame timing을
다시 쓰지 않는다. Codex Sol/XHigh section reviewer와 Grok native section reviewer는
같은 v2 evidence 계약을 쓰며, 어느 쪽도 별도 whole-timeline root record 없이
readiness를 닫을 수 없다.

## 잔존 기계 판정과 조치

### 1. 카메라 ontology 완전성

- 위치: `scripts/idol_harness_expert_gate.rb`의 01 camera v2 gate,
  `schemas/song-choreography-performance-mv-map.schema.json`의 camera contract.
- 이전: shot scale, height, angle, movement, speed, envelope, composition, lens,
  transition 등 13개 pool과 모든 section camera route가 있어야 ready였다.
- 폐해: 정지 shot, 의도적 동일 angle reprise, 단순 관찰 장면까지 메뉴 전체를
  채워야 했고 고정 tuple 문장과 가짜 다양성을 유도했다.
- 조치: 활성 v2는 `contextual_creative_review_contract`의 구조만 요구한다.
  pool은 optional vocabulary로 읽을 수 있으며, 적합성과 진행은 LLM이 판단한다.
  route가 선언된 경우에는 exact projection 검증을 유지한다.

### 2. 고정 대안·부모/자식 분할 수

- 위치: 01 schema의 `alternatives minItems: 2`, 02A schema의 camera candidate
  `minItems: 2`, legacy cut chain `min/maxItems: 3`.
- 이전 폐해: 해결된 장면에도 가짜 두 번째 안을 만들고, 한 사건을 기계적으로
  세 조각 내거나 같은 camera 문장을 반복하게 했다.
- 조치: 고정 수를 제거했다. 한 route도 허용하며, 분할 수는 audible/visible
  사건 필요를 LLM이 판단한다. ID/order/coverage는 계속 기계 검증한다.

### 3. 표정 연기 신체 체크리스트

- 위치: `schemas/master-storyboard.schema.json`의 expression acting contract.
- 이전: 눈·턱·입·호흡·어깨·손 등 여섯 칸을 모두 요구했다.
- 폐해: 장면에 중요한 한 시선이나 호흡보다 여섯 부위 복창을 우선하게 했다.
- 조치: 선택한 cue 중 하나 이상을 구조적으로 전달할 수 있게 바꿨다. 얼굴과
  몸의 충분성은 section LLM이 실제 장면 문맥에서 판정한다.

### 4. prompt 단어와 substring 판정

- 위치: `scripts/idol_prompt_packet_compile.rb`의 춤/행동 정규식과 prompt
  presence, `scripts/validate_02b_imagegen_contract.rb`의 reference/camera/policy
  prose substring 검사.
- 이전: `no dance` 같은 부정문도 춤으로 잡을 수 있었고, 같은 의미를 다른
  문장으로 쓰면 실패하면서 요구 단어만 넣은 빈 문장은 통과했다.
- 조치: 활성 `reference_bound_02a_prompt_blueprint_v1_4` 컴파일러는 02A가
  author한 blueprint를 exact-copy하고 hash를 검증한다. 활성 reference-bound
  v1.4 validator도 prompt 의미 substring 대신 source projection, child exact
  cover, structured carry, reference path/hash/order, packet ownership, approval만
  검사하고 종료한다.

### 5. source path token이 reference 의미를 대신함

- 위치: `scripts/idol_harness_state_check.rb`의 raw source token trace.
- 이전: 실제 interpretation/application binding이 있어도 file stem이나 source
  id 문자열을 01/02A prose에 다시 써야 ready가 될 수 있었다. 우연한 substring
  일치도 false pass가 가능했다.
- 조치: raw token 결과는 nonblocking diagnostic으로 낮췄다. 활성 경로는
  application id, path, SHA와 exact binding을 사용한다.

### 6. 오디오-화면 map의 일반 단어 금지

- 위치: `scripts/validate_audio_motion_director_map.rb`.
- 이전: generic word 발견을 error로 처리해 문맥상 필요한 표현까지 막았다.
- 조치: warning으로 전환했다. 실제 화면의 빈약함은 downstream LLM review가
  section cue와 장면을 함께 읽고 판정한다.

### 7. 비율·중복 prompt·고정 수정량

- 위치: `wiki/generation-review-system.md`,
  `skills/idol-generation/references/idol-imagegen-validation-contract.md`,
  `schemas/prompt-packets.schema.json`.
- 이전: frame subject 비율, 유사 angle 자동 hold, 최소 세 축 변경, 동일 prompt
  자동 reject가 장면의 reprise 기능을 무시했다.
- 조치: 수치 quota와 자동 hold/reject를 제거했다. 동일 prompt hash는 output
  ownership/reuse 확인 신호일 뿐 창작 실패가 아니다. legacy
  `duplicate_prompt_signature_check` enum은 읽기 호환 alias이며 활성 작업은
  `prompt_output_ownership_check`를 쓴다.

### 8. LLM review의 체크리스트 복창과 실행 증거 부재

- 위치: `02a-creative-context-review` schema/validator, section-production policy,
  generation skill.
- 이전: section과 whole-film topic별 짧은 prose 칸을 모두 채우면 실제 review
  실행 없이도 pass 문자열을 적을 수 있었다. Codex는 receipt가 없고 Grok도
  자기기입 session 문자열이어서 비대칭 우회가 가능했다. Founder HTML은 path만
  있고 SHA가 없었다.
- 조치: v2는 통합 `review_summary`와 typed findings를 중심으로 한다. 기존 topic
  field는 선택 lens다. Codex/Grok 모두 같은 runner-owned execution record의
  path+SHA, 실제 source SHA, profile, role, section scope, completed 상태를 대조한다.
  section별 record와 별도 whole-film record가 모두 필요하며 session/record 재사용을
  막는다. Founder HTML은 파일 SHA-256뿐 아니라 source·route·section reviews·
  whole-film review의 canonical projection digest를 HTML 구조 marker와 대조한다.

### 9. Registry 미연결·owner 비대칭·01/02A 중복 소유

- 위치: `automation/harness-stage-registry.yaml`, registry schema,
  `scripts/idol_harness_stage.rb`.
- 이전: 03V 이후와 달리 01/02/02A/review/02B에 schema와 validator edge가 없었다.
  Storyboard review owner 문자열에서 Grok이 빠졌고, 01과 02A가 action/camera를
  동시에 canonical로 설명했다.
- 조치: 다섯 stage에 schema/validator command를 연결했다. validation authority
  scope stage가 연결을 빠뜨리면 registry validation이 실패한다. review owner는
  Founder + active harness owner로 통일했고, 01/02A의 의미 route 대 cut-local
  realization 경계를 decision contract에 명시했다.

### 10. instruction priority와 sharding 충돌

- 위치: `skills/idol-mv-director/SKILL.md`,
  `references/01-bundle-authoring-detail.md`.
- 이전: owning skill의 priority에서 activated policy가 빠졌고, 상위 section
  policy는 새 multi-section 작업을 물리 shard로 요구하는데 하위 reference는
  long/dense일 때만 shard라고 했다.
- 조치: AGENTS → activated policy → schema → owning skill/module → wiki 순서를
  맞췄고 source/run artifact는 instruction보다 낮은 규칙이 아니라 보존해야 할
  creative fact임을 분리했다. 새/실질 재개 multi-section은 section별 physical
  shard, legacy/single-section은 호환 경로로 명시했다.

### 11. 테스트가 창작 정본을 fixture로 사용

- 위치: `scripts/tests/idol_prompt_packet_compile_test.rb`.
- 이전: ONE MOVE 실제 02A/02B/01A를 직접 읽었다. clean checkout에서는 golden
  packet이 없고 dirty checkout에서는 01/02 SHA가 stale하여 baseline이
  `23 runs / 19 failures`였다. 테스트를 통과시키려는 압력이 창작 정본 SHA를
  바꾸거나 stale 값을 따라가게 만들었다.
- 조치: `scripts/tests/fixtures/idol_prompt_packet_compile_fixture.rb`에 한 cut의
  최소 immutable synthetic fixture를 격리했다. live run file을 읽지 않으며,
  창작 prose를 바꾸어도 structural compiler 결과가 의미 품질을 판정하지 않는
  회귀 사례를 추가했다. 결과는 `23 runs / 95 assertions / 0 failures`다.

### 12. 활성 03V의 숨은 단어·길이·유사도·체크리스트 판정

- 위치: `scripts/validate_video_prompt_manifest.rb`,
  `scripts/validate_video_prompt_index.rb`, `scripts/lib/idol_03v_language_contract.rb`,
  `schemas/video-prompt-manifest.schema.json`,
  `schemas/video-prompt-section-qa.schema.json`.
- 이전: choreography token, abstract/generic phrase, 최소 단어·문자 수, manifest
  표현의 prompt exact phrase carry, semantic reversal/similarity heuristic이 활성
  v3 pass/fail을 결정했다. section QA도 19개 status와 여러 24자 prose 칸을
  채우는 방식이라 문맥 검토보다 체크리스트 복창이 쉬웠다. schema/skill은 모든
  cue에 5축 `camera_capture`, 70–85% word allocation, 고정 prompt 순서, absent
  choreography의 전 단어 금지까지 요구했다.
- 폐해: 명확한 body/camera/endpoint를 다른 자연어로 쓴 prompt가 false reject되고,
  빈약한 prompt도 요구 token과 문구를 복사하면 false pass할 수 있었다. 반복이나
  hold의 기능, 이미지에서 이미 보이는 truth, 장면별 motion 밀도도 판단하지 못했다.
- 조치: 활성 v3 validator는 source/hash/image bytes/order, owner, ID/coverage,
  manifest→index exact structured projection, typed upload prompt exact bytes,
  execution provenance만 검증한다. 창작 prose의 token·길이·phrase·similarity를
  점수화하지 않는다. QA v2는 section별 통합 review summary와 typed findings,
  고유 execution record를 받고, 별도 whole-timeline root가 진행·반복·경계를
  재검토한다. Codex와 Grok은 같은 source index SHA, scope, session/profile/role
  대조를 통과해야 하므로 자기기입 receipt나 root 생략으로 우회할 수 없다.
  v3의 `camera_capture`와 `camera_capture_axes`는 선택적 호환 projection으로
  낮췄다. 통합 `camera_route`와 source image를 section LLM이 읽고 장면에 필요한
  높이·거리·방향·깊이·배치·움직임·이유가 전체 review unit에서 회수되는지
  판단한다. skill의 수치 word quota, 고정 문장 order, token 자체 금지도 제거했다.

### 13. 지침 안전 상한의 소폭 확장

- 위치: `automation/instruction-surface-policy.yaml`.
- 조치: `AGENTS.md` reviewed ceiling을 5,200단어, `harness_static_startup` ceiling을
  10,200단어로 확장했다. 목표치는 각각 4,000/8,500단어로 유지해 초과 경고와
  정리 압력을 보존했다.
- 결과: 최종 검사 시점 dirty local truth의 `AGENTS.md` 4,955단어와 harness
  startup 9,837단어가 PASS다. 상한 확장은 창작 필드를 더 강제하거나 startup read를
  늘리지 않으며, 누락을 만들 수 있는 성급한 축약만 피한다.

### 14. owning skill의 camera/문장형 체크리스트 압력

- 위치: `idol-mv-director/modules/mv-direction.md`,
  `idol-generation/references/idol-prompt-packet-structure.md`,
  `idol-imagegen-validation-contract.md`, `idol-video-prompt/SKILL.md`와
  `video-prompt-authoring-detail.md`.
- 이전: camera height/distance/direction/depth를 “minimum check”로 분리하고,
  2–3문장, 70–85% word allocation, 고정 prompt order, 모든 dance token 금지를
  창작 방법으로 제시했다. 실제 장면보다 같은 field와 문장 구조를 복창하게 하고,
  source image가 증명하지 않는 camera axis까지 채우게 만들 수 있었다.
- 조치: camera 구체성은 cut/blueprint/prompt/source image 전체에서 관련 geometry,
  placement/crop, movement/hold와 이유가 회수되는지를 문맥 검토한다. tuple 분해,
  문장 수·순서·비율, token 존재 자체는 판단 근거가 아니다. 구조 필드는 exact
  handoff가 필요한 경우에만 유지하며, 장면에 필요 없는 축을 invent하지 않는다.

## Authority boundary

| 계층 | 소유 | 금지 |
| --- | --- | --- |
| AGENTS / policy | 불변식, 권한, stage/Founder gate, 문맥 검토 원칙 | 단어 목록·비율·camera pool 수로 창작 합격 판정 |
| Skill / module | 창작 방법, 판단 질문, 선택 가능한 vocabulary, 좋은 대안의 이유 | 모든 장면이 복창할 고정 creative checklist |
| Schema | 전달할 선택 truth의 type/enum/id/path/SHA, link, coverage, state | 좋은 이야기·좋은 카메라를 흉내 내는 필수 prose shape |
| Validator / compiler | exact copy, hash, ownership, unique ID, exact cover, execution/approval | keyword, similarity, frequency, 길이, tuple로 pass/fail/rewrite |
| Section LLM | 한 section의 사건·관계·몸·표정·시선·공간·카메라·경계 | whole-film 최종 판정이나 canonical rewrite |
| Whole-film LLM root | 진행, reprise, 반복 기능, climax/release, 전체 continuity | section receipt 대체 또는 무증거 자기승인 |
| Founder surface | 같은 hash-bound review evidence 표시와 final lock | 검증되지 않은 별도 요약을 approval truth로 사용 |

구체성은 많은 필수 칸으로 보장하지 않는다. 해당 review unit 전체에서 실제
인물/대상, 장소, 변화 또는 hold, audio cue, 몸·오브젝트·환경 반응, 얼굴/시선,
높이·거리·방향·깊이·crop·움직임, 앞뒤 인과를 LLM이 함께 확인한다. 구조 도구는
그 creative payload가 존재하고 다음 단계에 손실 없이 도착했는지만 확인한다.

## 남은 레거시와 제한

아래는 활성 reference-bound 02B release 경로에서는 우회되지만, legacy 읽기와
마이그레이션 때문에 코드에 남아 있다.

- `idol_prompt_packet_compile.rb`의 non-reference-bound / v0.2 prompt builder에는
  `CONCRETE_ACTION_EXCERPT_PATTERN`과 `generator_text_errors`가 남아 있다.
- `validate_02b_imagegen_contract.rb`의 non-reference-bound v1.4 및 이전 schema
  branch에는 prompt substring, retiming/quality keyword, layout prose checklist,
  작품명/file-name heuristic이 남아 있다.
- `validate_video_prompt_index.rb` v1/v2에는 `CONCRETE_MOTION_PATTERN`과 keyword
  검사가 남아 있다. v3 active path는 semantic branch 전에 종료하며 이를
  우회한다. `idol_03v_language_contract.rb`의 dance/image-lock/appearance heuristic도
  v1/v2 legacy 읽기에만 남아 있다.
- `video-prompt-section-qa` v1 checklist는 schema-readable legacy evidence이지만
  활성 v3 readiness를 닫을 수 없다. 새/실질 재개 03V는 section records와 별도
  whole-timeline root record를 가진 v2만 production-capable하다.
- v2 video-prompt의 필수 5축 `camera_capture`와 exact axis policy는 legacy
  compatibility branch에 남는다. 활성 v3는 이를 요구하지 않으며, 선언한 경우에만
  알려진 axis/type과 manifest→index exact projection을 구조 검증한다.
- 작업 전부터 dirty인 `scripts/README.md`의 contact-sheet 설명은 아직 review
  artifact를 v1이라고 부른다. 활성 conditional policy와 owning skill은 v2로
  정정했으므로 실행 우선순위상 우회는 없지만, 해당 Founder 변경과 병합할 때
  README 문구를 v2/legacy-v1 설명으로 맞춰야 한다.
- `4K`, `high quality`, `high detail`, 최고 품질/최대 지원 크기, `gpt-image-2`,
  reference attachment 순서와 prompt char limit은 Founder/AGENTS가 고정한 실행
  계약이다. 창작 적합성 score로 사용하지 않고 preflight compatibility로 유지한다.
- 02A schema의 parent, boundary, pre-edit, child, compile-seed projection은 여전히
  verbose하다. 현재는 exact lineage/transfer로만 검증하고 prose 품질을 score하지
  않지만 authoring pressure는 남을 수 있다. 이를 한 번에 정규화하면 기존 run
  migration 폭이 커지므로 이번 안전 범위에서는 삭제하지 않았다.
- section reference comparison floor는 Founder가 고정한 research evidence floor다.
  세 참조를 섞으라는 창작 규칙이 아니며 각 unit disposition과 provenance만
  구조적으로 확인한다.

활성 01~02B reference-bound 및 03V v3 경로에서 이번 감사가 확인한 반복 단어,
camera tuple, prompt similarity/hash, reference frequency, section/prose length,
exact semantic phrase, 고정 alternative/checklist 수에 의한 창작 pass/fail은
제거되었다. 위 legacy branch를 release 가능 상태로 다시 활성화하려면 먼저
같은 authority 분리를 적용해야 한다.

## 테스트 fixture의 남은 결합 부채

이번 장애를 만든 prompt compiler suite는 완전히 격리했다. 다만 다음 downstream
integration suite는 아직 live run을 source template 또는 admission root로 사용한다.
그 자체가 창작 품질 판정은 아니지만 run SHA 변화에 취약하므로 후속 fixture
분리가 필요하다.

- `scripts/tests/idol_harness_sections_test.rb`
- `scripts/tests/idol_harness_context_source_admission_test.rb`
- `scripts/tests/idol_post02b_03v_contracts_test.rb`
- `scripts/tests/idol_03v_placement_revision_binding_test.rb`

이 네 suite는 각각 큰 downstream lineage fixture를 공유하므로, 이번에 급히
ONE MOVE bytes를 복사해 새 정본을 만들지 않았다. 다음 migration에서는 공통
synthetic lineage fixture factory를 만들고 run-specific acceptance test와 unit
test를 분리해야 한다.

최종 재현 결과, `idol_post02b_03v_contracts_test.rb`는 live ONE MOVE에 더 이상
존재하지 않는 `onset_hit`을 fixture builder가 직접 `fetch`하여 34 runs 중
26 errors가 발생한다. `idol_03v_placement_revision_binding_test.rb`는 같은 방식으로
`lyric_meaning_guard`를 직접 `fetch`하여 15 runs 모두 setup에서 error가 난다.
이는 이번 validator 수정의 창작 판정 실패가 아니라, 테스트가 변하는 창작
정본 shape를 fixture API로 오인한 결합 문제다. 두 suite를 억지로 통과시키기
위해 ONE MOVE 00/01/02/02A/02B를 수정하지 않았다.

## 호환성과 migration

- 02A creative review v1은 schema-readable이다. 새/실질 재개 작업에서 active
  pass로 사용할 수 없고 `draft`, `hold`, `superseded`만 허용한다.
- v2 active review는 Codex와 Grok 모두 실행 record와 Founder HTML SHA를 요구한다.
  기존 자기기입 receipt는 migration 전 hold다.
- Grok owner skill과 section-reviewer roster도 active v2 및 runner-owned execution
  record를 직접 지시한다. legacy v1 row나 root가 backfill한 section row는 02B를
  열 수 없다.
- legacy camera pool과 anti-sameness field는 읽을 수 있지만, deprecated
  anti-sameness만으로 active v2 contextual review를 만족할 수 없다.
- legacy alternative/checklist/topic field는 읽을 수 있다. 새 route는 고정 개수나
  topic별 boilerplate를 요구하지 않는다.
- legacy prompt compiler/validator branch는 archive/migration read path다. active
  release는 reference-bound exact-blueprint path를 사용한다.
- 새 execution-record schema와 review v2는 additive artifact다. ONE MOVE creative
  canonical을 자동 migration하거나 수정하지 않는다.
- 03V QA v1과 v1/v2 language heuristic은 legacy 읽기/hold 근거로 남는다. 활성
  v3 closeout은 QA v2로 migration하고 section 및 whole-timeline execution record를
  새로 발급해야 하며, 이전 자기기입 checklist를 자동 승격하지 않는다.

## 검증 결과

- Ruby syntax: 수정된 script 전체 통과
- Stage registry semantic validation: `8 phases / 29 stages / 19 decision contracts / 0 warnings`
- Stage registry JSON Schema: 통과
- 02A review/새 execution-record JSON Schema syntax: 통과
- Prompt compiler: `23 runs / 95 assertions / 0 failures`
- 02A contextual review: `10 runs / 29 assertions / 0 failures`
- Expert gate: `10 runs / 33 assertions / 0 failures`
- Front-planning state: `2 runs / 10 assertions / 0 failures`
- Direction projection: `11 runs / 88 assertions / 0 failures`
- Instruction surface audit: `10 tests / OK`; live audit PASS. 현재
  `AGENTS.md` 4,955단어, harness startup 9,837단어다. target 초과는 경고로
  유지되고 reviewed ceiling만 각각 5,200/10,200단어다.
- 03V manifest/index exactness: `11 runs / 42 assertions / 0 failures`; 통합
  `camera_route`만 둔 v3가 5-field camera tuple 없이 통과하는 회귀 사례 포함
- 03V contextual review readiness: `3 runs / 9 assertions / 0 failures`
- 03V prepare lineage: `8 runs / 51 assertions / 0 failures`
- 03V v3 exact-projection self-test와 Codex/Grok contextual execution-provenance
  self-test: 통과
- 새 03V QA v2 fixture와 execution-record fixture의 JSON Schema validation:
  통과. 기존 v1 QA도 schema-readable 상태를 확인했다.
- `idol_post02b_03v_contracts_test.rb`: live fixture의 `onset_hit` 직접 결합으로
  `34 runs / 26 errors`; `idol_03v_placement_revision_binding_test.rb`: live fixture의
  `lyric_meaning_guard` 직접 결합으로 `15 runs / 15 errors`. 위 fixture migration
  debt이며 별도 synthetic 03V unit/self-test는 모두 통과한다.
- 이번 작업의 tracked 변경 파일만 대상으로 한 `git diff --check`: 통과. 전체
  worktree 검사는 관련 없는 기존 `cf/runs/CF_LUMA_VEIL_TINT_001/README.md`의
  trailing whitespace 두 줄 때문에 실패하며 해당 dirty 파일은 보존했다.

ONE MOVE 보존 확인:

| Artifact | SHA-256 |
| --- | --- |
| 00 | `43879a523c2b13e17157515e356fbaef3208237c14ea66549f9a78cd939d1f89` |
| 01 | `7e5c98099b288f8cad08003aa35cca0e05f041421a4ae60bcb6f17acf81c55ee` |
| 02 | `c59f090f395b1705e291ac5f21dc0e20a034a3584444ed08345fb7aff6114d97` |
| 02A | `f9dd3972de3946a611d514c7ed595f6e7ee279ad3ec1bf60f4049da3d7a91d34` |
| 02B | `a488c32b88ed0e50bc8634402b7d00aaee97f5397a109f1b51c23a7ac83c5f99` |

위 표는 2026-07-14 18:48 KST 최종 관측값이다. 이 감사가 쓴 파일 목록에는
ONE MOVE 00/01/02/02A/02B가 포함되지 않는다.

외부 접근, 다운로드, 업로드, 유료 호출, 이미지 생성, push는 수행하지 않았다.
