# IDOL 스토리라인·02B 프롬프트·작업자 Goal·지시 완수 검토 개선 플랜

- 작성일: 2026-08-06 (Asia/Seoul)
- 상태: **closed-local 시행 완료** — canonical 계약·스키마·스킬·검증기 반영, 실제 제작 run 미검증
- 범위: IDOL Front Planning부터 02B 이미지 프롬프트까지, 공통 Department Dispatch, Codex/Grok 작업자 실행
- CF 범위: 광고 결과 품질에 직접 영향을 주는 최소 대응만 포함
- 실제 run 검사: 없음
- canonical creative mutation: 없음
- active run write: 없음
- paid/external action: 없음
- contract/schema/skill mutation: 있음 — 아래 `22. 시행 결과`에 적용 버전과 검증 증거 기록
- 선행 기반:
  `automation/state-reports/idol-startup-prompt-and-skill-version-management-improvement-plan-2026-08-06.md`

이 문서의 1~21절은 시행 전 진단과 설계 기준이며, 현재 결과는 22절이 소유한다.
이 문서는 새 제작 stage나 새 창작 권한을 만드는 제안이 아니다. 이미 활성화된
Front Planning, 01, 02A, 02B, Department Dispatch, Founder Workbench와
Overall/CDD/section-owner 권한을 유지하면서 다음 네 가지를 닫기 위한 계획이다.

1. Founder와 맞춘 스토리라인을 `전체 -> 섹션 -> 컷` 순서로 점점 상세하게 만든다.
2. 02B 이미지 프롬프트가 그 스토리라인을 필수로 읽고 보존하게 한다.
3. 모든 Codex/Grok 작업자가 작업 시작 즉시 `/goal`을 만들고, 실제 반환까지 목표를
   유지하게 한다.
4. 스킬·계약·Founder 지시를 읽었다는 선언이 아니라 실제 output에 적용하고 완수했는지
   별도 감독 검토가 없으면 승격하지 못하게 한다.

## 1. 결론

현재 하네스는 필요한 부품 대부분을 갖고 있지만 연결이 부족하다.

- Front Planning에는 whole-film spine, section role, Major/Key Screen 상세 필드가 있다.
- 02A에는 Core Cut/Branch Cut과 구체적인 화면·카메라·연속성 진실이 있다.
- 02B에는 정확히 다섯 항목의 자연어 이미지 프롬프트, source inspection receipt,
  same-section bounded context가 있다.
- Department Dispatch에는 목표 문장, exact scope, required skill/read, output path/hash,
  director review와 promotion lifecycle이 있다.
- Startup/skill-version 개선은 등록 Recipe, Current Assignment Delta, 12블록 launch,
  EOF read와 반환 검토 경로를 이미 닫았다.

그러나 다음은 아직 필수 계약이 아니다.

- 세 번의 FP 점검에서 설명이 반드시 `전체 -> 모든 섹션 -> 모든 planning cut`까지
  깊어지는 것
- Founder와 맞춘 자연어 스토리라인의 정확한 포인터·value hash를 01/02A/02B가
  보존하는 것
- 02B author가 Branch Cut뿐 아니라 해당 whole/section/cut 스토리라인을 읽었다는 것
- 프롬프트의 각 창작 항목이 어느 스토리라인 진실을 보존하는지 검토하는 것
- 모든 worker가 실제 `/goal`을 만든 뒤 작업하는 것
- Founder 지시와 skill method를 항목별로 실제 output에 적용했는지 director가
  독립적으로 닫는 것
- 각 작업물이 자신의 owning schema와 exact skill/policy/contract revision을 실제로
  준수했는지 기계 검증과 Director 판단을 분리해 닫는 것
- 여러 worker가 동시에 반환해도 같은 Director가 한꺼번에 승인하지 않고 한 건씩
  읽고 disposition·promotion을 확정한 뒤 다음 건으로 넘어가는 것

따라서 현재 상태는 구조 기반 PASS, 스토리라인·Goal·완수 검토 연결 HOLD다.

## 2. 보존할 활성 기반

다음은 다시 설계하지 않는다.

1. FP의 세 review mode는 그대로 둔다.
   - `discovery`
   - `direction_synthesis`
   - `fp_final`
2. Discovery와 Direction Synthesis는 개발 대화이며, ordinary stage PASS는 FP Final에만
   둔다.
3. 공식 Core/Branch Cut id와 cardinality는 02A가 소유한다.
4. 02B render-facing prompt는 계속 정확히 다섯 항목만 사용한다.
   - `Identity reference rule`
   - `Scene intent`
   - `Visible details`
   - `Action cue`
   - `Avoid`
5. 스크립트는 creative prose, 스토리라인, reference interpretation, `/goal` 내용,
   application evidence 또는 director verdict를 작성하지 않는다.
6. Workbench/HTML은 canonical creative truth를 요약하거나 다시 쓰지 않고 exact-copy
   projection만 한다.
7. 모델/session 변경만으로 레퍼런스 pixels를 다시 읽지 않는다.
8. Founder mismatch는 정확히 영향받은 source/readout/cut만 다시 검사하고 unaffected
   truth는 유지한다.
9. Codex와 Grok은 provider 차이와 무관하게 같은 owner, scope, Goal, completion,
   review, promotion 계약을 사용한다.

## 3. 폐기·백로그 항목 처리 결정

| 항목 | 현재 상태 | 처리 결정 | 이유 |
| --- | --- | --- | --- |
| `creative-nucleus.front_planning_storyline_lock` | retired evidence | **개념만 활성 FP로 이관** | whole-film/section prose와 value hash를 downstream까지 무손실 보존하는 원칙은 유효하지만 retired 00 artifact와 stage를 되살리면 현재 FP 중심 구조를 깨뜨린다. |
| `skill-application-receipt.v3` | legacy run 전용, 신규 authoring 금지 | **별도 receipt 파일은 부활 금지** | read/application/output 증거의 유용한 필드만 Department Dispatch return/review에 흡수한다. 이중 기록과 worker self-certification을 만들지 않는다. |
| `Director Judgment Card` | 현재 FP skill에서 명시적으로 배제 | **계속 배제** | 새 점수표나 creative surface 대신 현재 `director_review.rubric_results`를 고정된 completion rubric으로 강화한다. 숫자나 machine score는 creative PASS가 될 수 없다. |
| CDD Director Boot Pack successor set | 불완전하여 rollover HOLD | **백로그 재개** | 상세 스토리라인, Goal/dispatch 상태, open Founder mismatch를 context compression 뒤 복원하려면 필요하다. |
| Startup prompt/skill-version 개선 | 2026-08-06 격리 더미 pilot까지 완료 | **확장 기반으로 사용** | Recipe/Delta/Envelope와 12블록 launch를 다시 만들지 않고 Goal과 completion audit을 추가한다. |
| `harness-improvement-review` sidecar | material rework용 optional loop | **ordinary gate로 승격 금지** | 반복 실패 학습에는 사용하되 모든 작업의 completion gate를 대신하게 하면 stage가 늘어난다. |
| 02B five-item prompt/compiler | active | **형태 보존, context와 trace만 확장** | 여섯 번째 render prompt 줄이나 장문의 process text를 추가하지 않고 스토리라인을 의미 guard로 사용한다. |

핵심 부활 대상은 과거 파일이 아니라 다음 원칙이다.

```text
exact Founder-aligned whole-film prose
-> exact section prose
-> exact planning-cut prose
-> 02A Core/Branch realization
-> 02B prompt component trace
```

각 화살표는 path, JSON pointer, source value SHA-256과 author/review lineage를 가진다.

## 4. 목표 제작 흐름

```text
Founder input / references
-> source-owned pixel observation and interpretation receipt
-> Discovery: whole-film visual readout
-> Direction Synthesis: complete whole-film + every-section readout
-> FP Final: complete whole-film + every-section + every Key Screen/planning-cut readout
-> 01: action/staging/reference application expansion without story replacement
-> 02A: official Core Cut and Branch Cut realization with storyline lineage
-> fresh one-section post-02A worker opens /goal
-> worker inspects exact Branch Cut, visual inputs, and storyline bindings
-> 02B five-item prompt is authored
-> worker self-checks required outputs and returns evidence
-> machine validates owning schemas, exact revisions, fields, hashes, registries, and coverage
-> immutable return enters the recipient Director's review queue
-> director takes exactly one return, independently reads the exact outputs and governing
   skill/policy/contract revisions, then reviews Goal, Founder instructions, skill application,
   storyline preservation, prompt specificity, hashes, and scope
-> director commits that return's disposition and promotion/HOLD, refreshes the baseline,
   then takes the next queued return
-> only accepted return becomes Founder-reviewable/promotable
```

## 5. Founder Visual Alignment Narrative

### 5.1 활성 canonical owner

새 narrative는 별도 stage나 별도 문서가 아니라 active Front Planning artifact 안의
하나의 nested contract로 둔다. 제안 이름은 `founder_visual_alignment`다.

아래 예시는 field shape 설명용이며 implementation 전 exact naming/version은 owning
schema patch에서 확정한다.

```yaml
founder_visual_alignment:
  contract_version: founder_visual_alignment.v1
  whole_film_readout:
    narrative_text: "Founder-facing natural-language whole-film flow"
    source_value_sha256: "..."
    evidence_and_inference_boundary: "..."
  section_readouts:
    - section_id: Sxx
      story_state_in: "..."
      section_event_or_hold: "..."
      story_state_out: "..."
      section_narrative_text: "..."
      reference_contributions: []
      transition_to_next: "..."
      source_value_sha256: "..."
  planning_cut_readouts:
    - planning_cut_id: KS_xx
      section_id: Sxx
      narrative_text: "..."
      exact_reference_surface_refs: []
      source_to_screen_contributions: []
      observable_camera_action_light_continuity: "..."
      source_value_sha256: "..."
```

`narrative_text`는 요약 문구나 키워드가 아니다. Founder가 AI가 보고 있는 장면을
텍스트만으로 검토할 수 있는 자연어 설명이어야 한다. 각 planning-cut readout은 최소한
다음을 하나의 장면 흐름으로 설명한다.

- section/audio cue와 장면의 역할
- 누가 또는 무엇이 화면에 보이는가
- 몸·손·시선·표정·오브젝트의 시작 상태
- 실제 보이는 action 또는 intentional hold
- object/environment/system response
- 카메라 높이, 거리/scale, 방향/angle, depth, placement, crop/negative space, lens feel
- light, color, material과 피부·의상·공간 반사
- 각 reference가 공급하는 정확한 요소와 governing/support 관계
- 이전 장면에서 들어오는 상태와 다음 장면으로 넘기는 상태
- 관찰된 pixel truth와 감독 inference의 경계

word count나 문장 수로 통과시키지 않는다. 구체성은 observable field coverage와
source binding으로 검토한다.

### 5.2 FP review mode별 필수 깊이

| review mode | Founder에게 보여야 하는 최소 narrative | 승격 차단 조건 |
| --- | --- | --- |
| `discovery` | 하나의 whole-film readout, rough section order, 각 ingredient의 예상 기능과 가장 큰 mismatch risk | whole-film readout이 없거나 reference 기능이 이미지와 분리된 추상 mood뿐이면 다음 mode HOLD |
| `direction_synthesis` | 각 complete candidate의 whole-film readout과 모든 active section readout, Major/Key Screen 방향, reference 조합·희생·위험 | 한 section이라도 narrative/readout이 없거나 candidate 일부만 상세하면 선택 불가 |
| `fp_final` | promoted whole-film + 모든 section + 모든 Key Screen/planning-cut readout, 정확한 이미지와 source-to-screen contribution | 하나라도 빠지거나 Founder mismatch가 열려 있으면 FP Final PASS 불가 |

FP Final의 planning cut은 Founder review 단위이며 공식 Branch Cut이 아니다. 02A는
planning-cut truth를 보존하면서 필요한 Core/Branch architecture를 정식으로 만든다.

### 5.3 Board projection

같은 `founder-workbench.html`에서 각 review card가 다음 순서로 읽히게 한다.

1. `내가 이 이미지/조합에서 보고 있는 것`
2. `이 장면에서 실제 만들 것`
3. `레퍼런스별로 가져오는 요소`
4. `이 장면이 이전/다음 장면과 연결되는 방식`
5. exact source/selected derivative pixels
6. Founder decision/comment

HTML renderer는 narrative를 만들거나 줄이지 않는다. canonical pointer와 value hash가
맞는 prose를 exact-copy한다. narrative, media, pointer, hash 중 하나라도 다르면 stale
review HOLD다.

## 6. 01과 02A의 스토리라인 보존

### 6.1 01

01은 FP narrative를 바꾸지 않고 다음을 확장한다.

- action/staging detail
- still-camera and composition alternatives
- space/object response
- reference application
- transitions and materially different screen coverage

각 01 section은 exact FP whole/section/planning-cut source pointer와 value hash를 보존하고,
무엇을 확장했는지 별도 delta로 쓴다. 의미를 바꾸는 correction은 FP로 되돌린다.

### 6.2 02A

02A는 각 official Core/Branch Cut에 다음 lineage를 요구한다.

- whole-film readout ref/hash
- owning section readout ref/hash
- source planning-cut/Key Screen readout ref/hash
- Core Cut narrative: governing event와 viewer read
- Branch Cut narrative: 이 화면이 독립적으로 추가하는 관찰 가능한 정보
- reference contribution과 selected derivative order
- entry/exit and neighbor continuity

02A가 새 screen realization을 만들 수는 있지만 FP의 whole/section story를 요약하거나
대체할 수 없다. planning-cut 하나가 여러 Branch Cut으로 확장되면 각 Branch는 같은
상위 meaning과 자신의 distinct contribution을 함께 가진다.

## 7. 02B 이미지 프롬프트의 스토리라인 필수 참조

### 7.1 핵심 결정

02B는 스토리라인 전체를 render prompt에 붙여 넣지 않는다. 대신 prompt author의
필수 creative context와 preservation check로 사용한다. render-facing 다섯 줄은 그대로
유지한다.

```text
Identity reference rule:
Scene intent:
Visible details:
Action cue:
Avoid:
```

### 7.2 Context Pack 확장

`idol-harness-context-pack.v5`의 successor는 한 section worker에게 다음을 추가로 준다.

- compact whole-film readout ref/value hash
- current full section readout ref/value hash
- current Branch Cut의 source planning-cut readout ref/value hash
- current Core/Branch cut narrative refs/value hashes
- immediate branch siblings의 cut readout refs/value hashes
- same-section previous/next Core의 compact narrative refs/value hashes
- open Founder mismatch가 없다는 current receipt

다른 section 상세, raw transcript, raw research pool, rejected candidates는 계속 제외한다.
즉 스토리라인은 더 정확해지지만 context는 여전히 one-section bounded다.

### 7.3 Prompt delta와 authoring inspection

`prompt-packet-delta`의 `direct_prompt_revision`에는 다음 binding을 필수화한다.

```text
storyline_context_binding
storyline_context_value_sha256
inspected_storyline_source_refs
prompt_component_storyline_trace
storyline_preservation_assertions
```

`authoring_inspection_receipt`는 기존 Branch Cut, visual references, current-title assets에
더해 exact storyline refs를 읽었다는 model/human declaration을 기록한다. 스크립트는
hash와 set/order만 검사하며 읽었다고 주장할 수 없다.

`prompt_component_storyline_trace`는 내부 metadata이며 render text가 아니다.

| 02B component | 반드시 보존할 narrative truth |
| --- | --- |
| `Identity reference rule` | 현재 title appearance continuity와 member visibility, 스토리라인이 요구하는 인물 존재 방식 |
| `Scene intent` | whole-film/section/Core/Branch에서 이 이미지가 수행하는 단일 장면 목적 |
| `Visible details` | planning-cut/Branch Cut의 공간·카메라·구도·빛·재질과 reference surface grammar |
| `Action cue` | 시작 상태, visible action/hold, object/environment response와 장면의 물리적 결과 |
| `Avoid` | identity/reference/storyline drift, portrait bias, 잘못된 상태·구도·추상화 |

### 7.4 02B director review

02B packet은 다음을 모두 만족해야 `accept`될 수 있다.

1. exact Branch Cut과 visual inputs를 실제 검사했다.
2. exact whole/section/planning-cut/Core/Branch storyline refs를 검사했다.
3. 다섯 prompt component가 해당 storyline truth와 모순되지 않는다.
4. `Scene intent`가 모호한 mood가 아니라 이 컷의 구체적 screen job을 말한다.
5. `Visible details`와 `Action cue`가 Founder에게 보여준 장면보다 얕아지지 않는다.
6. reference별 기여와 attachment order를 지킨다.
7. 새로운 plot beat, 새 action, 새 카메라 truth를 02B에서 만들지 않는다.
8. required quality terms와 provider-neutral prompt shape를 지킨다.

Wording만 불충분하면 해당 02B packet을 고친다. Visible action, still view,
composition, reference application이 바뀌면 02A로 돌아간다. Whole/section story meaning이
바뀌면 FP로 돌아간다.

## 8. Founder visual-read mismatch 처리

기존 `direct_comment` 또는 `HOLD`에 `reason_code: visual_read_mismatch`를 추가한다.
새 Founder gate나 별도 decision system은 만들지 않는다.

필수 입력은 다음과 같다.

- Founder verbatim comment
- disputed narrative field pointer/value hash
- disputed media/binding ids와 selected derivative path/hash
- affected whole/section/planning-cut/Core/Branch ids
- mismatch 종류: pixel observation, reference contribution, staging/action, camera,
  light/material, continuity 또는 prompt translation

처리 순서는 다음과 같다.

```text
Founder mismatch
-> exact disputed derivative만 reopen
-> new interpretation/readout revision
-> complete affected flow를 다시 작성
-> before/after narrative와 unchanged truth를 board에 projection
-> smallest owner patch
-> affected downstream만 invalidate/revalidate
```

모델/session 변경만으로 재검사를 열지 않는다. Founder mismatch가 해소되지 않은 범위는
Goal이나 schema가 complete여도 promotion HOLD다.

## 9. 모든 작업자의 `/goal` 필수화

### 9.1 원칙

모든 CDD department worker, pre-02A development worker, post-02A section owner,
image/prompt worker, 03V worker, Edit shard worker와 CF worker는 정식 작업을 시작할 때
반드시 `/goal` 또는 검증 가능한 해당 runtime의 native goal 기능을 먼저 연다.

텍스트에 `목표: ...`라고 쓰는 것만으로 대체할 수 없다. runtime goal id/state를
Dispatch가 확인할 수 있어야 한다. Codex 또는 Grok adapter가 이 기능을 지원하지
않거나 증명할 수 없으면 creative work 전에 `goal_surface_unavailable` HOLD다.

### 9.2 Goal source

Goal 내용은 worker가 임의로 줄이거나 추상화하지 않는다. assigning Director가 작성한
다음 값을 exact source로 사용한다.

- `task.objective`
- exact scope와 non-scope
- expected outputs와 paths
- current quality proof
- return-ready conditions
- Founder locks와 must/avoid
- stop/HOLD conditions

Compiled Launch Prompt의 첫 runtime action은 다음 의미를 갖는다.

```text
1. exact Dispatch를 읽는다.
2. Dispatch-bound objective로 /goal을 생성한다.
3. goal id와 exact goal text hash를 attempt에 기록한다.
4. 그 뒤 owning skill과 required reads를 EOF까지 읽는다.
5. return-ready conditions가 닫힐 때까지 goal을 유지한다.
```

### 9.3 Department Dispatch Goal Contract

Department Dispatch successor에는 다음 provider-neutral shape가 필요하다.

```yaml
goal_contract:
  required: true
  source_objective_pointer: /launch/task/objective
  source_scope_pointer: /launch/task/exact_scope
  goal_text_sha256: "..."
  creation_timing: before_required_reads_and_creative_work
  completion_timing: only_after_valid_runtime_return_and_self_check
  unsupported_runtime_action: hold_before_work

runtime_goal:
  provider: codex | grok
  native_goal_id: "..."
  opened_at: "..."
  state_at_return: active | achieved | runtime_blocked
  completion_evidence_sha256: "..."
```

Goal은 작업 owner의 집중·완성률 장치이지 creative PASS나 Founder PASS가 아니다.
worker가 Goal을 achieved로 닫아도 director review가 HOLD면 promotion할 수 없다.
부분 output, schema-only PASS, 질문만 남긴 반환, generic summary는 Goal 완료가 아니다.

Dispatch HOLD와 runtime goal status는 분리한다. runtime이 허용하지 않는 상태를
거짓으로 기록하지 말고, exact Dispatch hold reason을 남긴다.

## 10. 지시·스킬·계약 완수 검토

### 10.1 세 층 검증

Annotation 1은 `worker = 기계 검증`, `Director = 내용 판단`만을 뜻하지 않는다.
검증 주체와 권한은 다음 세 층으로 분리한다.

1. `mechanical_compliance_receipt`
   - deterministic validator가 exact owning schema path/version/SHA, required/conditional
     fields, enum/cross-field invariant, source/output hashes, registry revision, profile closure,
     output coverage와 lifecycle state를 검사
   - skill을 실제로 적용했다거나 creative output이 충분하다고 주장할 수 없음
2. `worker_fulfillment_claim`
   - worker가 어떤 요구를 어느 output field/path에 적용했다고 주장하는지
   - exact output hash와 evidence pointer
   - unresolved/held/not-applicable 이유
   - worker가 validator를 실행할 수는 있지만 mechanical PASS를 creative self-PASS로
     바꿀 수 없음
3. `director_fulfillment_review`
   - recipient Director가 실제 bytes/media와 exact governing skill, linked module,
     activated policy, contract 및 owning schema revision을 읽고 항목별로 독립 판단
   - worker claim을 그대로 승인하지 않음
   - required row 하나라도 HOLD/FAIL이면 disposition `accept` 금지

별도 manual `skill-application-receipt` 파일은 만들지 않는다. 세 층 모두를
`department-dispatch` return/review lifecycle 안에 둔다.

Director는 worker의 `read_to_eof` 선언을 빌려 쓰지 않는다. `reviewer_read_closure`가
exact path, authoring version/revision, SHA-256과 linked-read closure를 증명해야 한다.
같은 Director가 이미 동일 SHA의 전체 내용을 읽었다면 그 closure는 재사용할 수 있지만,
한 byte라도 바뀌면 해당 surface를 다시 읽기 전에는 review를 시작할 수 없다.

### 10.2 Requirement manifest

assigning Director는 Current Assignment Delta에서 요구를 stable id로 분해한다.

```text
FOUNDER-xx  Founder verbatim/explicit lock or request
SKILL-xx    owning skill의 현재 작업에 적용되는 필수 방법
POLICY-xx   activated policy와 AGENTS invariant의 현재 작업 요구
CONTRACT-xx lifecycle, authority, owner, gate, return/promotion 계약 요구
SCHEMA-xx   owning artifact schema/version/field/cross-field/consumer 요구
OUTPUT-xx   expected artifact/field/media coverage
QUALITY-xx  observable/detail/reference/continuity quality proof
HOLD-xx     forbidden action, missing evidence, or stop condition
GOAL-xx     runtime /goal creation and completion evidence
```

각 row는 다음을 가진다.

- source path/JSON pointer/value hash
- required 또는 conditional
- exact affected scope
- expected output target
- expected evidence type
- worker claim
- director disposition
- director evidence locator/hash

스크립트는 row 존재, required coverage, ids, pointers, hashes와 allowed state만
검사한다. row 내용이나 semantic result를 만들지 않는다.

### 10.3 스키마·스킬·계약 준수의 exact 검사

모든 작업물은 자신의 artifact type에 해당하는 active owner를 먼저 resolve한다.
`어떤 schema인지 모른 채 필드가 있어 보인다`는 검증이 아니다. mechanical layer는
최소한 다음을 fail-closed로 검사한다.

1. owning schema path, authoring version과 file SHA가 profile/contract/registry와 일치함
2. required 및 조건부 필드, enum, id cardinality, cross-field invariant가 모두 통과함
3. retired/deprecated field나 다른 stage/CF lane의 schema로 대체하지 않음
4. declared source/output pointer, byte hash, value hash, attachment/order가 실제 bytes와
   일치함
5. producer와 모든 required consumer/adapter/projection이 같은 authoring meaning을 사용함
6. skill/policy/contract 변경 작업이면 owning version, surface revision과 SHA-256이 같은
   patch의 registry에 반영됨
7. 변경된 schema/validator/adapter의 positive fixture와 각 required negative fixture가
   실제로 실행되고 기대한 PASS/FAIL을 냄

그 다음 worker는 `SKILL/POLICY/CONTRACT/SCHEMA` requirement마다 실제 output
field/path와 결정을 evidence로 연결한다. Director는 exact revision을 독립적으로 읽은 뒤
다음을 판단한다.

- 기계적으로 유효한 필드가 해당 skill method의 목적과 순서를 실제로 수행했는가
- 계약의 owner, scope, Founder gate, smallest-owner correction과 unaffected truth를
  지켰는가
- schema를 채웠을 뿐 아니라 작업물 내용이 section/cut/prompt의 실질적 요구를
  충족하는가
- 누락된 consumer, hidden HOLD, 추상적 대체 또는 잘못된 stage 의미가 없는가

즉 schema PASS는 입장 조건이고, worker claim은 검토용 증거이며, Director의 독립
판단만이 `accept` 후보를 만든다. Founder PASS가 필요한 지점은 그 뒤에도 유지된다.

### 10.4 고정 Director completion rubric

모든 Codex/Grok creative return은 최소한 다음 rubric을 항목별로 닫는다.

1. **Goal opened and pursued** — exact Dispatch objective로 작업 전 Goal이 생성됐는가.
2. **Founder instruction coverage** — verbatim 요청과 명시적 lock/must/avoid가 모두
   output에 반영되거나 정확한 HOLD로 남았는가.
3. **Owning skill application** — EOF 선언이 아니라 skill method가 실제 output
   decision과 evidence에 나타나는가.
4. **Schema and contract conformance** — exact owning schema와 active policy/contract의
   required meaning, owner, gate, version, consumer 및 registry가 모두 닫혔는가.
5. **Current assignment resolution** — named gap을 해결했는가, 다른 문제로 주제를
   바꾸지 않았는가.
6. **Required output coverage** — 모든 section/cut/packet/path가 exact-cover되는가.
7. **Observable specificity** — 추상 mood, 짧은 자신감 문장, `cinematic/premium/dynamic`
   같은 말만 남지 않고 body/object/environment/camera/composition/light/continuity가
   보이는가.
8. **Source and pixel grounding** — exact source/selected derivative/playback와
   source-to-screen consequence가 연결되는가.
9. **Storyline preservation** — whole/section/cut meaning과 reference contribution이
   downstream에서 축약·변형되지 않았는가.
10. **Locks, scope, and unaffected truth** — Founder lock, owner boundary, unrelated
   section과 prior passed truth를 보존했는가.
11. **Honest completion state** — unresolved, uncertainty, feasibility/safety/permission
    문제가 숨겨지지 않았는가.

`rubric_results`의 criterion을 임의의 한 줄로 대체하지 못하게 profile/checkpoint별
required criterion id set을 등록한다. 작업 성격에 따라 추가 criterion은 허용하지만
기본 row는 생략할 수 없다.

### 10.5 추상적·과도하게 간결한 반환 차단

word count나 장문 강제는 사용하지 않는다. 대신 다음은 evidence 부족 HOLD다.

- `완료`, `적용함`, `skill을 따름`이라는 self-assertion만 있음
- reference id/path/hash 없이 mood 또는 기능만 말함
- 섹션 하나를 대표 문장 하나로 줄이고 active cuts를 누락함
- camera/light/action을 `dynamic`, `cinematic`, `premium`으로 대체함
- Founder의 문장을 다시 인용하지만 output field에 어디 반영했는지 없음
- prompt가 storyline보다 얕아져 누가 무엇을 어떻게 하는지 사라짐
- expected path는 있으나 actual output hash가 없음
- 질문 또는 다음 할 일만 남기고 Goal을 complete 처리함

### 10.6 동시 반환의 Director 순차 처리

worker는 disjoint ownership 아래 동시에 작업하고 동시에 반환할 수 있다. 반환별
mechanical preflight도 서로 다른 bytes를 대상으로 병렬 실행할 수 있다. 그러나 같은
recipient Director의 semantic review와 canonical promotion은 반드시 single-flight다.

```text
multiple immutable worker returns
-> mechanical preflight per return
-> deterministic Director return queue
-> one review lease
-> Director reads one complete return + governing revisions
-> accept / patch / reject / HOLD
-> canonical or board update is committed by the single writer
-> current baseline, hashes, affected dependencies, and queue are refreshed
-> review lease is released
-> only then may the next return enter director_review_in_progress
```

필수 규칙은 다음과 같다.

- 한 Director에게 `director_review_in_progress`는 한 번에 정확히 한 건만 허용한다.
- 여러 반환을 한 summary로 묶어 읽지 않고 batch `accept`하지 않는다.
- upstream dependency 또는 Founder correction 반환을 먼저 처리하고, 그 외에는
  `returned_at + dispatch_id`의 결정적 순서를 사용한다.
- Founder가 우선순위를 바꾸면 reorder reason과 새 queue revision을 기록한다.
- 현재 건이 Founder 입력을 기다리면 먼저 공식 `HOLD`와 affected scope를 기록하고
  review lease를 해제한 뒤 다음 독립 건으로 이동할 수 있다.
- 각 accept/HOLD 뒤 새 canonical/workbench/index hash를 기준선으로 고정한 다음 다음
  반환을 읽는다. 이전 기준선으로 다음 건을 동시에 판단하지 않는다.
- CDD, Overall Director, Edit Director는 각자 같은 single-flight inbox 규칙을 사용한다.
  Overall의 canonical promotion은 여러 하위 Director 결과가 와도 전역 한 건씩 처리한다.
- 새 worker launch는 이미 활성화된 backpressure 규칙대로 review queue가 밀리면 멈춘다.

따라서 병렬성은 worker 제작과 독립 mechanical preflight에만 남고, 인간/LLM 감독 판단,
merge와 promotion은 순차 처리된다.

## 11. Codex/Grok provider parity

두 provider는 같은 canonical Dispatch bytes와 requirement ids를 받는다.

- 같은 `/goal` objective와 completion condition
- 같은 required skill/read closure
- 같은 storyline context pointers/hashes
- 같은 expected outputs와 evidence
- 같은 director completion rubric
- 같은 HOLD와 promotion rule

provider adapter는 다음만 다룬다.

- native task/session transport
- native `/goal` 또는 auditable goal API invocation
- provider runtime goal id/state capture
- exact rendered prompt delivery
- returned output pointer capture

adapter가 creative objective, 스토리라인, completion claim 또는 review verdict를
요약·의역·보완하면 안 된다. 한 provider만 Goal이나 completion review를 건너뛰는
fallback은 금지한다.

## 12. Context compression과 Director Boot Pack

CDD successor와 long-session compaction을 위해 deterministic Boot Pack에 다음을
추가한다.

- active whole-film readout pointer/value hash
- every active section readout pointer/value hash
- current review scope의 planning-cut/Core/Branch readout pointers/value hashes
- active board revision/cycle
- open `visual_read_mismatch` rows
- active Goal ids/states와 owning Dispatch attempts
- required skill/profile revisions and read closure
- accepted/held director completion reviews
- do-not-revive decisions
- current owner, next action, stop/wake conditions

raw transcript, raw candidate pool, full catalog, unrelated sections와 media bytes는 넣지
않는다. 이미지는 canonical path/hash pointer로만 유지한다.

compression 또는 physical successor는 readout을 먼저 복원한다. session change만으로
pixels를 다시 읽지 않으며 mismatch, changed bytes, changed selected derivative,
incomplete lock 또는 identity/safety/feasibility conflict일 때만 exact source를 reopen한다.

## 13. CF 최소 대응

CF에는 IDOL FP의 전체 창작 계층이나 세 review mode를 복제하지 않는다. 광고 품질에
직접 영향을 주는 네 층만 CF owner schema에 둔다.

1. `whole_ad_readout`
   - advertised subject, target need, promise, objection, proof/payoff, recall/CTA의 전체
     cause-effect 흐름
2. `commercial_phase_readout`
   - CF30 selected route의 phase/job, subject-triggered rule change, reference contribution,
     next-phase reason
3. `core_branch_readout`
   - CF40 Core event와 각 Branch의 visible subject, action, world/object response,
     camera/composition/light, subject proof, next-cut reason
4. `cf50_prompt_storyline_binding`
   - 각 frame/prompt가 whole ad와 해당 Core/Branch readout pointer/value hash를 읽고
     보존했다는 authoring inspection과 director review

CF50의 기존 five-item prompt shape는 유지한다. CF prompt가 지켜야 할 핵심은 다음뿐이다.

- advertised subject가 장면의 원인인가
- governing main reference의 phase/action/camera/composition order가 유지되는가
- supporting reference가 선언된 detail만 공급하는가
- subject proof/payoff, world/system response와 CTA/recall이 사라지지 않는가
- Branch별 카메라·구도·빛·행동이 충분히 구체적이고 반복되지 않는가

공통 Department Dispatch의 `/goal`과 instruction completion review는 CF worker에도
동일하게 적용한다. CF creative fields는 반드시 `cf/` owner schema와 adapter가 소유한다.
IDOL FP narrative schema나 Major/Key Screen/Core/Branch meaning을 CF stage 충족에 쓰지
않는다.

현재 CF는 CF00 consolidated Founder PASS 뒤에 routine choice 없이 CF10-CF50을 진행한다.
이번 최소 대응은 새로운 세 번의 Founder gate를 자동 추가하지 않는다. 대신 기존
Workbench에서 quality-critical readout과 HOLD/comment routing을 볼 수 있게 한다. 별도
세 번의 CF Founder gate는 Founder가 명시적으로 요청할 때만 독립 정책 변경으로 연다.

## 14. 예상 계약·파일 변경 표면

시행 시 현재 owner와 SHA를 다시 검사하고 최소 patch를 확정한다.

### IDOL creative truth and review

- `schemas/front-planning-readiness.schema.json`
- `skills/idol-front-planning-director/SKILL.md`
- `skills/idol-front-planning-director/references/founder-visual-review-board-contract.md`
- `schemas/html-review-board.schema.json`
- review projection owner adapters, renderer와 focused tests
- `schemas/song-choreography-performance-mv-map.schema.json`
- `schemas/master-storyboard.schema.json`

### 02B context, prompt, and review

- `schemas/harness-context-pack.schema.json`
- `schemas/prompt-packet-delta.schema.json`
- `schemas/prompt-packets.schema.json`
- `skills/idol-generation/SKILL.md`
- `skills/idol-generation/references/prompt-packet-compile-detail.md`
- `automation/harness-execution-contract.yaml`
- `automation/harness-skill-load-profiles.yaml`
- `scripts/idol_prompt_packet_compile.rb`
- `scripts/idol_build_context_pack.rb` 또는 current owning context-pack builder
- relevant validators and tests

### Goal and completion lifecycle

- `skills/idol-orchestrator/references/provider-neutral-studio-kernel.md`
- `schemas/department-dispatch.schema.json`
- `schemas/director-dispatch-index.schema.json`
- `schemas/harness-execution-contract.schema.json`
- `automation/harness-execution-contract.yaml`
- `automation/harness-skill-load-profiles.yaml`
- Workbench Codex/Grok provider adapters
- `scripts/idol_director_dispatch_index.rb`
- `scripts/tests/idol_director_dispatch_index_test.rb`
- `scripts/validate_department_dispatch.rb`
- Director Dispatch Index/Boot Pack projection owner and tests

### Founder mismatch

- `schemas/html-review-decision-export.schema.json`
- `schemas/founder-review-decision-intake.schema.json`
- `schemas/founder-intervention-receipt.schema.json` only if the current typed reason cannot
  be represented without a version change
- affected-only invalidation and board refresh tests

### CF-owned minimum surface

- `cf/AGENTS.md` only if a top-level invariant is required
- `cf/skills/idol-cf-code/SKILL.md`
- active CF00/CF30/CF40/CF50 owner schemas
- CF Workbench adapter/projection fixture
- `automation/cf-contract-version-registry.yaml`
- CF surface registry and focused validators/tests

### Registries

모든 tracked instruction/schema/skill/validator/script 변경은 같은 patch에서 다음을
갱신한다.

- `automation/harness-contract-version-registry.yaml`
- `automation/harness-surface-version-registry.yaml`
- `automation/instruction-surface-policy.yaml` when a new invariant is tracked
- CF 변경은 CF-owned contract/surface registry

## 15. 예상 authoring version 방향

정확한 version number는 Phase 0 current registry audit 뒤 확정하지만 required-field와
consumer 의미가 바뀌므로 단순 SHA refresh로 처리하지 않는다.

예상 successor 범위는 다음과 같다.

- Front Planning readiness: narrative hierarchy를 요구하는 새 authoring version
- HTML review board: mode별 narrative coverage를 요구하는 새 authoring version
- 01/02A: exact narrative lineage를 요구하는 successor version
- Harness context pack: storyline refs를 포함하는 successor version
- Prompt delta/canonical packets: storyline binding과 trace를 요구하는 successor version
- Department Dispatch: Goal contract와 three-layer compliance/fulfillment review를 요구하는 successor
  version
- Director Dispatch Index: immutable return queue, one active review lease와 sequential
  disposition/promotion을 요구하는 successor version
- Harness execution/profile: Goal-first launch, exact schema/contract compliance와 fixed
  completion rubric을 요구하는
  successor version/revision
- CF00/CF30/CF40/CF50: lane-local readout binding을 추가하는 최소 successor version

기존 active authoring version을 뒤에서 의미 변경하지 않는다. historical artifacts는
evidence로 읽을 수 있지만 새 contract에 자동 창작 migration하지 않는다.

## 16. 시행 순서

### Phase 0 — Current ownership and baseline audit

- branch/worktree/active owner와 target paths를 확인한다.
- current authoring versions, profile closure와 surface hashes를 다시 측정한다.
- 진행 중인 reference/Workbench/Dispatch edit와 overlap하면 HOLD한다.
- 실제 run은 건드리지 않고 schemas, fixtures, adapters와 dummy paths만 대상으로 한다.

### Phase 1 — Active FP narrative hierarchy

- `founder_visual_alignment` owner와 schema를 추가한다.
- Discovery/Direction Synthesis/FP Final coverage condition을 추가한다.
- board가 narrative와 exact pixels를 같은 card에서 exact-copy projection하게 한다.
- missing whole/section/planning-cut, stale hash와 partial candidate negative fixtures를
  추가한다.

### Phase 2 — 01/02A lineage and 02B storyline binding

- 01과 02A에 exact narrative source pointer/value hash를 연결한다.
- context pack에 bounded storyline context를 추가한다.
- 02B delta, canonical packet, authoring inspection과 prompt-component trace를 확장한다.
- compiler가 creative prose를 쓰지 않고 hashes/coverage만 검사하는지 증명한다.

### Phase 3 — Goal-first Department Dispatch

- provider-neutral Goal Contract를 Department Dispatch에 추가한다.
- 12블록 Compiled Launch Prompt의 first runtime action을 `/goal` 생성으로 고정한다.
- Codex/Grok adapters에서 native goal invocation과 id/state capture를 구현한다.
- goal missing, goal after creative work, wrong goal hash, premature achieved와 unsupported
  runtime negative fixtures를 추가한다.

### Phase 4 — Instruction fulfillment and director acceptance

- mechanical compliance receipt, Requirement manifest, worker claim, reviewer read closure와
  director fulfillment review를 Dispatch lifecycle에 추가한다.
- `SKILL/POLICY/CONTRACT/SCHEMA` requirement가 exact path/version/revision/SHA 및 실제
  output evidence를 요구하게 한다.
- profile/checkpoint별 fixed rubric ids를 등록한다.
- all-required-pass 없이는 director `accept`와 Overall promotion을 금지한다.
- skill read-only claim, abstract output, partial coverage, missing output hash와 hidden HOLD
  cases를 검증한다.
- Director Dispatch Index에 immutable return queue와 한 건의 active review lease만
  허용하고, disposition·single-writer commit·baseline refresh 뒤 다음 반환을 연다.
- simultaneous return, batch accept, concurrent review leases, stale-baseline second review와
  out-of-order dependency review negative fixtures를 추가한다.

### Phase 5 — Founder mismatch and Boot Pack

- `visual_read_mismatch` reason route를 decision intake에 연결한다.
- affected narrative/source/cut만 reopen, revise, invalidate, reproject한다.
- Boot Pack에 narrative, Goal, fulfillment, board와 open mismatch state를 추가한다.
- successor restoration이 incomplete하면 기존처럼 HOLD한다.

### Phase 6 — CF minimum mirror

- whole ad, commercial phase, Core/Branch, CF50 prompt storyline binding만 추가한다.
- subject proof, main-reference order와 action/camera/light/CTA 보존을 director rubric에
  넣는다.
- 공통 Goal/fulfillment lifecycle을 CF worker에 적용하되 CF creative schema는 분리한다.

### Phase 7 — Closed-local acceptance

실제 제작 run, 외부 검색, 이미지 생성, 유료/공개 작업 없이 fixtures와 격리 dummy
workflow로 다음을 닫는다.

```text
FP three-mode narrative coverage
-> exact 01/02A lineage
-> one Branch Cut context pack
-> worker /goal
-> 02B prompt authoring
-> worker fulfillment claim
-> director fulfillment review
-> Founder review projection
-> one mismatch correction
-> affected-only refresh
```

Codex와 Grok adapter를 각각 같은 fixture로 검증한다. dummy PASS는 실제 창작 품질 PASS가
아니며 production run 검증은 Founder의 별도 요청이 있을 때만 연다.

## 17. 검증 매트릭스

### Mechanical PASS

- required Goal contract 존재
- Goal text source pointer/hash 일치
- Goal이 creative work보다 먼저 생성됨
- required skills/linked reads path/revision/SHA와 EOF evidence 일치
- reviewer의 독립 skill/policy/contract/schema read closure 일치
- exact owning schema path/version/SHA와 required/conditional/cross-field 검사 통과
- producer-consumer authoring version과 tracked registry revision/SHA 일치
- Requirement manifest exact coverage
- expected output path와 actual SHA 존재
- narrative whole/section/planning-cut coverage
- 01/02A/02B source pointer/value hash lineage
- 02B prompt component trace와 authoring inspection set/order
- five-item prompt shape와 quality terms
- no sixth line, internal ids/paths/hashes 또는 process text
- director review에 모든 required rubric id 존재
- any HOLD/FAIL이면 accept/promotion 불가
- 한 recipient Director당 active review lease가 최대 한 건
- review disposition과 single-writer commit 및 baseline refresh 전 다음 review 시작 불가
- batch accept와 stale-baseline promotion 없음
- affected-only invalidation and stable board revision
- contract/surface registry stale hash 0

### LLM Director PASS

- Founder instruction을 실제 결과가 충족함
- skill method가 output decisions에 보임
- narrative가 이미지와 reference contributions를 구체적으로 설명함
- whole/section/cut progression이 자연스럽고 비반복적임
- prompt가 narrative를 축약해 의미를 잃지 않음
- action, camera, composition, light, material과 continuity가 observable함
- uncertainty와 mismatch가 숨겨지지 않음
- CF는 subject proof/cause-effect/main route/CTA를 보존함

기계는 LLM Director PASS를 대신하지 않는다. LLM review도 Founder PASS를 대신하지
않는다.

## 18. 필수 negative fixtures

1. Goal이 없음
2. output을 만든 뒤 Goal을 열었음
3. Dispatch와 다른 추상 Goal을 열었음
4. partial output인데 Goal을 achieved로 닫음
5. skill/read는 기록했지만 application evidence가 없음
6. Founder 지시 한 항목을 누락함
7. whole-film readout만 있고 section/cut readout이 없음
8. 한 section 또는 Key Screen만 짧은 대표 문장으로 뭉갬
9. reference pixels/path/hash 없이 mood-only 설명
10. prompt가 storyline ref/hash를 읽지 않음
11. prompt가 Founder-facing scene보다 얕거나 새 action을 추가함
12. exact Branch Cut은 같지만 stale storyline hash를 사용함
13. director rubric required row가 하나 빠짐
14. worker self-claim만으로 director accept를 시도함
15. one section mismatch가 whole film을 invalidate함
16. Grok만 Goal 또는 rubric을 건너뛰는 fallback을 사용함
17. CF prompt가 제품/서비스/게임 등 advertised subject 없이 mood film으로 남음
18. 작업물이 틀린 stage 또는 retired schema로 validation을 우회함
19. schema는 PASS하지만 required consumer/adapter가 이전 authoring version을 사용함
20. worker가 skill 적용을 주장하지만 Director에게 exact revision read closure가 없음
21. 두 worker 반환이 동시에 `director_review_in_progress`가 됨
22. 여러 반환을 하나의 summary와 batch `accept`로 닫음
23. 첫 반환의 commit/baseline refresh 전에 두 번째 반환을 판단함
24. downstream 반환을 upstream correction보다 먼저 승격함

Structural fixtures는 deterministic validator가 fail시킨다. mood-only, image/text
misread, prompt/storyline flattening과 같은 creative cases는 LLM Director review fixture가
HOLD해야 한다. semantic similarity score로 자동 판정하지 않는다.

## 19. 완료 기준

다음이 모두 충족돼야 이번 개선을 완료로 부른다.

- Founder의 FP 세 점검에서 narrative가 실제로 `전체 -> 섹션 -> planning cut`으로
  깊어진다.
- FP Final의 모든 active section/Key Screen이 상세 readout과 exact reference pixels를
  가진다.
- 01/02A/02B가 같은 narrative meaning을 pointer/value hash로 보존한다.
- 02B author는 exact storyline와 visual inputs를 검사하지 않으면 prompt를 만들 수 없다.
- 02B prompt는 다섯 항목을 유지하면서도 Founder-facing 장면보다 얕아지지 않는다.
- visual-read mismatch는 exact pixels 재검사와 complete affected-flow 재브리핑으로
  닫힌다.
- 모든 Codex/Grok worker가 creative work 전에 `/goal` 또는 검증 가능한 native goal을
  연다.
- Goal 없는 worker launch와 premature completion은 fail-closed다.
- 모든 return은 Founder/skill/output/quality/HOLD requirement를 항목별로 증명한다.
- 모든 작업물은 exact owning schema와 active skill/policy/contract revision에 대한
  mechanical receipt, worker evidence mapping과 Director의 독립 read closure를 가진다.
- recipient Director가 실제 bytes/media를 검토한 뒤에만 accept한다.
- worker 반환이 동시에 와도 같은 Director는 한 건씩 읽고 disposition·single-writer
  commit·baseline refresh를 끝낸 뒤 다음 건을 검토한다.
- Overall canonical promotion은 하위 review가 여러 건 완료되어도 전역 한 건씩 진행한다.
- abstract/generic/partial 반환은 schema PASS나 self-assertion만으로 승격하지 못한다.
- context compression 뒤 narrative, Goal, completion review와 open mismatch가 복원된다.
- CF는 IDOL과 schema를 섞지 않고 광고 품질에 직접 영향을 주는 storyline/prompt/Goal/
  completion 항목만 갖는다.
- Codex/Grok parity fixture가 같은 계약으로 PASS한다.
- stale registry/profile/surface hash가 0이다.
- active run, paid/external/public mutation 없이 closed-local acceptance가 끝난다.

## 20. 명시적 비목표

- retired 00 Creative Nucleus stage 부활
- `creative-nucleus.schema.json`을 active authoring으로 재등록
- 새 Storyline stage 또는 별도 Founder board 생성
- manual per-worker skill-application receipt 재생성
- Director Judgment Card 또는 numeric creative score 부활
- word count/문장 수를 creative adequacy로 사용
- scripts가 narrative, Goal, application evidence 또는 verdict 작성
- 모든 session change마다 전체 이미지 재검사
- 02B에 여섯 번째 render prompt heading 추가
- provider-specific creative prompt rewrite
- IDOL/CF creative schema 통합
- 실제 production run, generation 또는 외부 호출을 이 계획 작성만으로 허가

## 21. 시행 시작 전 보고할 것

이 계획을 실제 구현할 때는 곧바로 canonical 파일을 고치지 않는다. 먼저 다음을
Founder에게 보고한다.

1. current owner와 dirty overlap
2. active versions와 target surface SHA
3. 기존 startup/version-management 개선과의 exact reuse 범위
4. storyline/02B/Goal/completion 각각의 최소 변경 파일
5. CF 최소 patch와 IDOL과 분리되는 경계
6. focused tests와 closed-local acceptance 범위
7. proceed 또는 HOLD 추천

Founder가 이 기준선을 확인한 뒤 Phase 1부터 atomic patch 단위로 진행한다.

## 22. 시행 결과 — 2026-08-06 closed-local

Founder가 본 대화에서 목표 설정과 즉시 수정을 지시했으므로 1~21절의 기준선을 따라
canonical 계약·스키마·스킬·검증기를 수정했다. 실제 제작 run, 이미지 생성, 외부 검색,
유료 호출, 공개 작업은 실행하지 않았다.

### 22.1 적용된 active version

| surface | 시행 결과 |
| --- | --- |
| Department Dispatch | `idol-department-dispatch.v4` — Goal-first, 9개 requirement category, mechanical receipt, worker claim, Director independent review/read closure, fixed rubric, review/promotion lease |
| Director Dispatch Index | `idol-director-dispatch-index.v2` — recipient별 deterministic queue, single-flight review, prior closure와 baseline refresh, Overall global promotion lease |
| Harness Execution | `idol-harness-execution-contract.v22` — 첫 runtime action을 native Goal 생성으로 고정하고 Codex/Grok 동일 lifecycle 적용 |
| Front Planning | `front-planning-readiness.v12` — Discovery의 전체, Direction Synthesis의 전체+모든 섹션, FP Final의 전체+모든 섹션+모든 planning cut 상세 storyline |
| 01 | `song-choreography-performance-mv-map 2.0` — FP storyline exact projection과 expansion-only delta |
| 02A | `master-storyboard 2.3`, context review `v6` — Branch Cut별 exact storyline binding과 02A observable expansion/progression review |
| 02B | prompt delta `1.2`, prompt packets `2.2`, compiler `1.1` — whole/section/planning-cut/02A lineage inspection과 five-component consumption map |
| Founder board | HTML board/export `v9` — exact storyline를 bound pixels 옆에 재작성 없이 projection하고 `visual_read_mismatch`를 smallest owner로 route |
| CF 최소 대응 | CF30 `2.3`, CF40 `3.2`, CF50 `3.1`, CF execution `v7` — 광고 전체/job/phase/cut storyline와 CF50 prompt binding만 lane-local로 적용 |

### 22.2 Annotation 1의 확정된 책임 분리

Annotation 1은 다음 세 층으로 구현했다.

1. **deterministic validator**가 schema field, cross-field invariant, exact path/version/hash,
   order, coverage, Goal timing, queue lease를 기계적으로 검사한다.
2. **worker**는 그 기계 검사를 실행·반환하고, 동시에 모든 requirement id마다 실제로
   어느 output bytes/field에 적용했는지 `worker_fulfillment_claim`을 제출한다. worker의
   자기 주장은 creative PASS가 아니다.
3. **recipient Director**는 worker 선언을 빌려 쓰지 않고 exact returned bytes와 governing
   skill, linked module, policy, contract, schema revision을 직접 읽은 뒤 모든 requirement와
   고정 rubric을 `PASS/HOLD/FAIL`로 독립 판단한다. required row 하나라도 닫히지 않으면
   `accept`와 promotion은 불가능하다.

따라서 `작업자 = 필드 기계검증만`, `Director = 막연한 총평` 구조가 아니다. 기계 검증,
worker의 적용 증거, Director의 독립 내용 판단이 서로 대체할 수 없는 세 층이다.

동시 반환은 제작 병렬성만 유지한다. 같은 Director의 반환은
`dependency_rank -> returned_at -> dispatch_id` 순서로 immutable queue에 들어가며,
Director는 한 번에 하나의 review lease만 가진다. 현재 건의 exact-byte read,
requirement disposition, accept/HOLD, single-writer commit, promotion-or-hold와 baseline/hash
refresh가 끝나기 전에는 다음 건을 열 수 없다. Overall canonical promotion도 전역 lease
하나만 허용한다. batch accept와 stale-baseline 두 번째 review는 validator가 거부한다.

### 22.3 스토리라인과 이미지 재검사 경로

- 스토리라인은 reference pixels를 보며 FP에서 작성되고 `전체 -> 섹션 -> planning cut`
  순서로 깊어진다.
- 01과 02A는 이 값을 pointer/value hash로 exact-project하며 자기 stage의 observable
  expansion만 별도로 기록한다.
- 02B author는 exact Branch Cut과 bound visual inputs뿐 아니라 whole/section/planning-cut/
  02A storyline를 검사해야 하며, 다섯 prompt component가 무엇을 보존하는지 consumption
  map으로 닫는다.
- Founder가 이미지와 설명이 다르다고 하면 `visual_read_mismatch`가 disputed derivative의
  exact pixels를 다시 열고, 대화 가능한 owning CDD/Director에서 complete affected flow를
  다시 브리핑한 뒤 affected descendants만 갱신한다.
- session compaction만으로 pixels를 매번 다시 보지 않는다. unchanged readout은 exact
  pointer/hash로 복원하고, mismatch·changed bytes·불완전 lock·identity/safety/feasibility
  충돌일 때만 pixels를 다시 연다.

### 22.4 closed-local 검증 결과

| 검증 묶음 | 결과 |
| --- | --- |
| Department Dispatch Goal/3층 completion | 39 runs, 142 assertions PASS |
| Director sequential queue/promotion lease | 6 runs, 44 assertions PASS |
| FP progressive storyline | 12 runs, 36 assertions PASS |
| 01/02A/02B local lineage propagation | 13 runs, 43 assertions PASS |
| 02A semantic context review | 17 runs, 48 assertions PASS |
| 02B prompt compile/inspection/trace | 25 runs, 117 assertions PASS |
| Founder HTML board | 20 runs, 250 assertions PASS |
| Founder decision/mismatch intake | 11 runs, 67 assertions PASS |
| expert gate | 7 runs, 26 assertions PASS |
| CF audience and harness adapters | 34 tests PASS |
| provider-neutral model routing | 6 tests PASS, execution contract v22 |
| skill/profile closure | 17 profiles, 18 skill bindings, 46 read bindings PASS |
| contract-version registry | 110 routes PASS |

합계는 Ruby 150 runs/773 assertions와 Python 40 tests(CF 34, routing 6)다. missing Goal, Goal-after-work,
missing worker claim, missing Director read/result, 같은 Director의 overlapping reviews,
global promotion overlap과 stale storyline 같은 핵심 negative fixture가 fail-closed임을
포함한다.

### 22.5 남은 범위와 비차단 진단

- 실제 제작 run은 사용자의 명시대로 검사하지 않았다. 따라서 이번 결과는
  **계약·스키마·스킬·adapter·closed-local fixture PASS**이며 실제 창작물 품질 PASS가
  아니다.
- 같은 session의 compaction은 canonical storyline와 board/dispatch pointer·hash를 다시
  읽는 계약으로 닫혔다. 다만 별도 physical CDD successor를 chat-free하게 교체하는
  full Boot Pack rollover는 기존대로 명시적 HOLD이며 이번 수정이 자동 활성화하지
  않는다. 그 route는 full decision/workbench/reference-index 복원과 별도 Founder 확인이
  모두 있어야 열린다.
- 현재-task가 변경한 contract/profile/surface hash는 정합하다. 전역 surface registry는
  다른 작업 범위의 FP Workbench UI 2개와 business-marketing 문서 5개의 stale hash를
  별도로 보고한다.
- `skills/idol-front-planning-director/SKILL.md`는 754줄로 reviewed ceiling 720 경고가
  남는다. protected invariant상 Founder가 현재 요청에서 size remediation을 명시하지
  않으면 split/compress할 수 없으므로 기능 수정과 분리해 보존했다.
