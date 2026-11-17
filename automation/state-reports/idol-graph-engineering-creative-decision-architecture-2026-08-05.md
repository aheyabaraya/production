# IDOL 그래프 엔지니어링·창작 결정 그래프 방향

- 기준일: 2026-08-05 (Asia/Seoul)
- 성격: 비정본 아키텍처 방향 문서
- gate effect: none
- canonical mutation: none
- 적용 범위: IDOL 루트의 provider-neutral PRE-00→05 하네스
- 제외 범위: `runs/aurora-m/su/**`, 다른 활성 런의 창작 정본, `cf/**`, 유료·외부 실행
- 다음 세션 프롬프트: `automation/state-reports/idol-graph-engineering-next-session-prompt-2026-08-05.md`

## 1. 결론

현재 IDOL 하네스는 그래프를 만들 준비는 잘 되어 있지만 아직 한 런의
상태·증거·창작 판단을 하나의 typed dynamic run graph로 투영해 운영하는
구조는 아니다. 단계, 권한, provenance, Department Dispatch, reference
binding, owner, review, Founder gate, invalidation, action queue와
`current-next`가 이미 존재하므로 기존 하네스를 다른 시스템으로 교체하지
않는다.

권고 방향은 다음과 같다.

```text
기존 창작 정본 + Founder 결정 + 실행 이벤트
                    ↓
      Semantic / Provenance / Execution Graph
                    ↓
후보 상태·검토 상태·영향 범위·다음 작업을 설명하는 read model
                    ↓
AI 감독 판단 / Founder gate / 기존 deterministic runner
```

그래프는 창작자가 아니다. 작업자 AI가 실제 레퍼런스를 읽고 후보군과
적용안을 제안하고, CDD가 후보와 현재 곡·타깃·앞뒤 흐름을 다시 읽은 뒤
새로운 통합 방향을 작성한다. Overall Director가 검토·승격하고 필요한
Founder gate가 닫힌 뒤에만 확정된 창작 truth가 기존 정본에 기록된다.
스크립트·그래프·Rhai는 그 결과를 정확히 복사·검증·전달할 수 있지만,
미결정 창작 값을 조립·의역·추론해서는 안 된다.

## 2. 현재 하네스에서 보존할 설계

새 세션은 이 문서의 요약을 현재 truth로 간주하지 말고 checkout의 실제
파일을 다시 읽어 아래 연결을 검증해야 한다.

```text
AGENTS.md
→ 활성 policies/**
→ automation/harness-contract-version-registry.yaml
→ automation/harness-surface-version-registry.yaml
→ automation/harness-stage-registry.yaml
→ automation/harness-artifact-routing.yaml
→ automation/harness-execution-contract.yaml
→ automation/harness-skill-load-profiles.yaml
→ 각 active stage의 output-contract schema와 producer/consumer validator
→ owning skills/**/SKILL.md와 linked reads
→ Department Dispatch / Director Dispatch Index / Reference Working Index
→ Founder Workbench / action queue / next unit / current-next
→ run-owned canonical artifacts와 validator evidence
```

현재 설계에서 특히 보존할 것은 다음과 같다.

1. PRE-00부터 05까지의 stage authority와 Founder gate
2. one owner per canonical truth와 smallest-owner revision
3. Overall Director, CDD, department worker, post-02A section lineage의 권한 분리
4. provider-neutral 역할과 Codex/Grok/Luna의 runtime mapping 분리
5. Department Dispatch의 exact required reads, input/result digest, immutable attempt,
   director review와 promotion lifecycle
6. official/original-first source 규칙과 restricted-edit permission gate
7. reference의 actual pixels/playback, locator, selected derivative와 SHA-256
8. Front Planning 01R/01R-C → 01 reference application → 02A binding → 02B exact
   prompt projection
9. scripts never author creative truth와 schema pass never equals creative pass
10. Founder intervention 이후 affected-only invalidation과 unaffected truth 보존
11. CDD rollover는 자동 실행하지 않고 안전 checkpoint와 Founder 확인을 요구
12. paid/external execution은 별도 current-task Founder approval을 요구

## 3. 해결하려는 빈틈

현재의 그래프 관계는 여러 계약·스키마·스킬·런 산출물에 분산되어 있다.
그 결과 다음 질문에 한 번에 답하기 어렵다.

- 한 reference candidate가 worker 제안인지 CDD 선택인지 Overall 승격인지
  Founder lock인지
- CDD가 무엇을 실제로 읽고 어떤 후보를 결합·탈락시켰는지
- 한 frame/crop 또는 source hash가 바뀌면 어느 Section과 downstream만 다시
  검토해야 하는지
- 현재 HOLD의 직접 원인과 그 원인을 닫을 합법적인 owner가 누구인지
- 어떤 worker return이 아직 CDD review를 받지 않았는지
- 어떤 Section들이 source, canonical bytes와 output path가 완전히 분리되어
  병렬 실행 가능한지
- 현재 `current-next`가 어떤 증거·gate·owner 관계에서 도출됐는지

또한 worker output의 `applied`, `combined`, `selected_anchor` 같은 표현은
비정본 제안이어도 겉으로는 최종 결정처럼 보일 수 있다. 기존 disposition을
바꾸는 새 창작 schema를 만들기보다, 그래프에서 proposal authority와 effective
decision state를 분리해야 한다.

## 4. 목표 그래프 구조

### 4.1 세 개의 분리된 그래프

#### Semantic Graph

AI가 작성하고 감독이 검토하는 창작 관계다.

```text
audience promise
→ message role
→ song section cue
→ section job / missing screen function
→ reference candidate and worker proposal
→ CDD synthesis
→ Major / Key Screen
→ Core Cut / Branch Cut
→ observable screen proof
```

Semantic edge는 `supports`, `embodies`, `contrasts`, `causes`, `answers`,
`transforms`, `transitions_to`, `proposes_for`, `preserves`, `discards`,
`combined_with`, `challenges`, `selected_by`, `rejected_by`처럼 의미를 가진다.
각 관계에는 실제 evidence pointer, author role, review state, current-song
consequence와 이유가 필요하다. 스크립트는 관계의 존재·경로·해시만 검증하며
관계 이유를 작성하지 않는다.

#### Provenance Graph

기계적으로 검증할 수 있는 증거 계보다.

```text
source identity
→ canonical media bytes / SHA-256
→ registered analysis
→ frame sheet / selected cell / crop / bounded sequence
→ interpretation receipt
→ worker candidate evidence
→ CDD decision input
→ 01 / 02A / 02B binding
→ generated image / 03V / edit output and review receipt
```

이 그래프는 raw media를 복사하지 않고 exact path, JSON pointer, revision,
SHA-256와 binding order를 기록한다.

#### Execution Graph

결정과 작업의 lifecycle을 계산하는 그래프다.

```text
stage / department job / section / review / gate / generation / playback / edit
→ dispatch / lineage / attempt / owner lease / checkpoint
→ prepared / launched / returned / reviewed / promoted | hold
→ requires / blocks / joins / invalidates / owned_by / reviewed_by
```

Execution Graph는 ready/HOLD/next owner와 영향 범위를 계산할 수 있지만
creative PASS, reference selection, Founder lock 또는 paid approval을 만들 수 없다.

### 4.2 공통 ID와 상태

세 그래프는 같은 stable id를 참조하되 같은 필드에 모든 의미를 섞지 않는다.
최소 공통 상태는 다음처럼 분리한다.

```text
raw_evidence
→ worker_candidate
→ cdd_selected | cdd_combined | cdd_rejected | cdd_hold
→ overall_promoted | overall_returned | overall_hold
→ founder_locked | founder_passed | founder_held | founder_rejected
→ projected_downstream
→ invalidated | superseded
```

기존 artifact의 `applied/combined/held/rejected` disposition은 그대로 보존한다.
그래프는 그 값의 author와 authority level을 함께 기록하여 worker의
`proposed combined`가 CDD의 effective decision으로 오인되지 않게 한다.

## 5. 레퍼런스와 프레임시트의 그래프 흐름

### 5.1 작업자 후보 제안

Reference worker는 단순 수집자가 아니다. Dispatch가 제공한 target, message,
selected audio/section cue, current section job, missing function, Founder locks,
member/world constraints와 exact source pointers를 읽은 뒤 실제 pixels/playback을
검토한다. 각 후보는 최소한 다음을 반환한다.

- source identity, locator, selected derivative path와 SHA-256
- observed pixel/playback facts
- named section need
- bounded transfer와 preserve/discard boundary
- observable screen consequence와 exact placement
- current-song/member/world specificity
- strength, mismatch, feasibility와 weaker-neighbor reason
- worker proposal disposition과 제거 시 잃는 screen information

작업자는 여러 후보, candidate anchor frame, 적용안, 결합안과 challenge를
제안할 수 있다. 그러나 governing direction, canonical binding, Founder lock은
결정할 수 없다.

### 5.2 프레임시트

```text
source video
→ ordered frame/sequence sheet
→ Layer A ordered-flow observation
→ worker-proposed anchor candidates A / B / C
→ Layer B exact still observation per candidate anchor
→ CDD selected/combined/rejected anchors
→ promoted reference binding
```

전체 sheet는 navigation과 ordered grammar evidence다. 선택 후보 셀·프레임·크롭은
각자 경로와 SHA-256를 가진다. 추출 스크립트는 이미 작업자/감독이 후보로
지정한 픽셀을 분리할 수 있지만 새로운 creative candidate를 고르지 않는다.

### 5.3 CDD 통합 판단

CDD는 graph context pack으로 다음만 받는다.

- 현재 판단 질문과 missing screen function
- 관련 worker candidate와 actual evidence pointers
- target/message/song cue/section role
- Founder locks와 current-title bindings
- previous/next boundary와 whole-film consequence
- candidate mismatch, conflict, rejected reason와 unresolved decision

Context pack은 fixed labels와 exact pointers/values만 조립한다. CDD가 이 자료를
직접 읽고 후보의 선택·결합·탈락을 판단하여 새로운 통합 방향 C와 이유를
작성한다. CDD-authored C가 없으면 `creative_decision_required` HOLD다. Python,
Ruby, Rhai 또는 graph projection이 A/B 필드를 붙여 C를 만들 수 없다.

## 6. Schema가 딱딱해지지 않게 하는 경계

새 schema를 만든다면 graph transport에만 제한한다.

강하게 고정할 수 있는 것:

- node/edge id와 type
- canonical pointer, revision, SHA-256
- author, owner, reviewer, decision epoch
- lifecycle state, gate, invalidation scope
- evidence pointer와 required reason 존재 여부

AI에게 열어둘 것:

- 왜 후보를 선택·결합·탈락했는지
- source-to-screen 변화의 구체적 의미
- 장면의 개연성·새로운 화면 기여·앞뒤 연결
- 현재 곡·타깃·멤버·세계에만 성립하는 이유
- 가장 강한 추천과 위험

새 graph schema가 Front Planning, Decision Set, 01, 02A 또는 02B의 창작 필드를
복제해서는 안 된다. Graph node는 기존 owner artifact와 exact pointer/hash를
가리키고, 필요한 소량의 runtime state와 relationship evidence만 가진다.

## 7. 장점

1. worker 후보와 감독 선택, Founder lock을 혼동하지 않는다.
2. reference에서 최종 화면까지 선택 이유와 evidence를 추적할 수 있다.
3. 변경 시 affected-only invalidation을 계산해 무관한 Section을 보호한다.
4. CDD가 raw pool 대신 현재 판단에 필요한 후보와 근거만 받는다.
5. provider/session이 바뀌어도 결정 lineage와 exact evidence를 복원할 수 있다.
6. owner 충돌, stale hash, 미검토 return과 gate 우회를 일찍 발견한다.
7. disjoint Section 병렬 실행과 join/backpressure를 명확히 계산할 수 있다.
8. `왜 HOLD인가`, `누가 다음 owner인가`, `이 reference를 어디서 쓰는가`에
   근거 경로로 답할 수 있다.

## 8. 단점과 위험

| 위험 | 결과 | 방지 원칙 |
| --- | --- | --- |
| graph가 정본을 복제 | YAML/graph가 서로 달라짐 | graph는 rebuildable read model, owner pointer/hash만 기록 |
| worker 제안을 확정으로 오인 | 감독 검토 우회 | proposal state와 effective decision state 분리 |
| schema 과잉 | 창작이 필드 채우기로 축소 | topology/state만 schema화, 판단 이유는 AI 작성 |
| edge 폭증 | 유지보수·조회가 더 어려워짐 | 필요한 typed relation만 등록하고 generic 중복 edge 금지 |
| context pack 누락 | CDD 판단이 얇아짐 | exact required inputs와 missing-evidence HOLD |
| script semantic assembly | 문맥 없는 창작 truth 생성 | model-authored decision 없으면 HOLD, exact-copy only |
| 점수 자동 PASS | 개연성·근거 hard stop 우회 | score는 retrieval 보조만, 창작 PASS 금지 |
| graph DB/Rhai 조기 도입 | 복잡도와 의존성 증가 | 로컬 파일 기반 shadow projection부터 시작 |
| graph 결과가 current-next와 충돌 | 두 실행 권위 발생 | 초기에는 advisory/shadow only, 기존 authority 우선 |

## 9. 기술 선택

Phase 0–3에는 외부 graph service, 결제, GPU, 고용량 RAM 또는 Rhai가 필요하지
않다. 기존 Ruby/Python과 YAML/JSON/JSONL로 충분하다. Graph에는 media bytes가
아니라 pointer/hash/state/edge만 둔다.

Rhai 또는 다른 expression runtime은 다음 조건이 모두 충족된 뒤에만 검토한다.

- typed graph와 event ledger가 실제 런에서 안정적으로 재생성됨
- 기존 validator/current-next와 shadow parity를 보임
- 제한된 deterministic guard가 반복적으로 필요함
- creative edge 작성, Founder decision, canonical write, paid/external action과
  완전히 분리됨

허용 가능한 Rhai 예시는 `필수 review가 존재하는가`, `owner lease가 해제됐는가`,
`어느 declared dependent를 invalidated로 표시할 것인가`다. Reference 선택,
candidate 결합, scene 작성, creative PASS는 허용되지 않는다.

## 10. 단계별 도입안

### Phase 0 — 현재 연결 감사

- current checkout의 AGENTS→policy→registry→schema→skill/profile→dispatch/index→
  queue/current-next→validator 연결을 다시 작성한다.
- stage registry와 artifact routing이 가리키는 모든 active output contract,
  producer, consumer와 validator를 따라가며 누락·중복·orphan을 확인한다.
- version과 producer/consumer를 현재 bytes에서 확인한다.
- 중복 authority, orphan consumer, stale version/hash와 기존 graph-like surface를
  찾는다.
- active run과 SU creative truth를 읽거나 수정하지 않는다.

### Phase 1 — 비정본 read-only graph v0

- `work/graph-engineering-v0/` 아래에만 graph contract, sample projection,
  projector와 테스트 후보를 둔다.
- 기존 artifacts와 fixtures를 읽고 node/edge/pointer/state만 투영한다.
- creative artifact, active schema/skill/policy/runner와 current-next를 쓰지 않는다.
- semantic edge는 기존 AI-authored field를 exact pointer로 연결하며 새 의미를
  생성하지 않는다.

### Phase 2 — Shadow parity

- graph-derived blockers/next owner를 기존 action queue/next-unit/current-next와
  비교한다.
- candidate가 review 없이 promoted가 되지 않는지 검사한다.
- graph를 다시 생성했을 때 동일한 digest와 정렬을 얻는지 검사한다.
- source/skill/output hash 변경 fixture에서 정확한 affected-only scope를 비교한다.

### Phase 3 — Append-only event와 advisory invalidation

- dispatch lifecycle, director review, Founder decision, artifact change, owner
  lease와 invalidation을 append-only event로 기록하는 비정본 모델을 검토한다.
- 기존 정본에서 재생성 가능한 projection으로 유지한다.
- graph는 HOLD와 제안만 만들고 active action queue/current-next authority를
  가지지 않는다.

### Phase 4 — 제한된 deterministic integration

- shadow evidence가 충분하고 Founder가 active integration을 명시 승인한 뒤에만
  next-owner wake, owner-collision stop, deterministic rebuild와 affected-only
  invalidation projection을 활성화한다.
- tracked instruction/policy/schema/skill/script를 바꾸면 owning contract version
  registry와 surface revision/SHA-256를 같은 patch에서 갱신한다.

### Phase 5 — 선택적 engine

- 파일 기반 projection이 실제 병목이 될 때만 SQLite, graph database, CEL 또는
  constrained Rhai를 비교한다.
- 저장 기술 교체는 authority나 creative judgment를 넓히지 않는다.

## 11. 수용 기준

다음이 모두 증명되지 않으면 active integration을 하지 않는다.

- script-authored 또는 script-paraphrased creative node: 0
- worker candidate의 무검토 promotion: 0
- Founder gate inference 또는 bypass: 0
- duplicate canonical owner: 0
- 동일 입력의 graph rebuild digest 차이: 0
- 무관한 Section invalidation: 0
- direct reference가 source path/hash 없이 연결된 경우: 0
- frame sheet 전체가 selected still/reference unit으로 승격된 경우: 0
- 모든 HOLD에 evidence path, blocking edge와 next legal owner가 존재
- graph projection이 기존 authority와 다를 때 fail-closed하고 차이를 설명
- CDD가 후보 결합 시 실제 source observation과 current-song consequence를 남김

## 12. 새 세션의 필수 산출물

새 세션은 최소 다음을 제공한다.

1. current checkout 기준 전체 연결 지도
2. 이미 존재하는 graph-like 기능과 실제 빈틈
3. 현행 유지, read-only graph, event-sourced graph, 외부 engine 선택지의 장단점
4. 한 개의 주 추천안과 필요할 때만 한 개의 비호환 대안
5. creative authority·Founder gate·schema drift에 대한 실패 시나리오
6. Phase 1 비정본 v0의 최소 node/edge/state와 경로
7. shadow test와 수용 기준
8. active integration 전에 필요한 Founder 결정

새 세션은 이 문서를 그대로 구현 명세로 취급하지 않는다. 현재 repo의 실제
설계와 충돌하는 항목을 먼저 찾고, 더 단순하고 안전한 구조가 있으면 근거와
함께 수정 제안한다.

## 13. 2026-08-05 승인 후 구현 결과

Founder가 schema와 graph 변경을 승인한 뒤에도 active authority로 바로 연결하지
않고, 먼저 비정본 v1과 immutable historical parity까지 구현했다.

### 구현된 graph v1

- 위치: `work/graph-engineering-v1/`
- authority: `advisory_shadow_only`
- three-graph separation: 유지
- locator: JSON Pointer, YAML Pointer, Markdown heading, Markdown line range
- identity: owner-authored `logical_entity_id`와 hash-derived
  `evidence_location_id` 분리
- candidate rule: worker 후보 최소 2개, 후보별 CDD disposition과 model-authored
  reason 필수
- authority rule: worker→CDD→Overall→explicit Founder→downstream 순서 강제
- affected rule: declared execution `invalidates` edge의 section scope만 순회
- output rule: creative prose와 media bytes 미복사

합성 회귀는 15 tests / 83 assertions가 PASS했고 sample projection digest는
`b952b7e8a90579eba367d9cbb0f7ec4fd26b529c635b2f430165c8a03bea1970`이다.

### 실제 과거 상태 parity

working tree의 현재 pointer를 건드리지 않기 위해 commit
`a3830ed96d15c593ad29563759a3b8094d2e7ab9`의 hash-bound blob을 읽었다.

```text
Action Queue
→ Next Unit
→ Founder Gate
→ Current Next
```

run, status, selected queue/unit, owner, Founder-decision requirement, S00-S03,
source chain 44개 비교가 전부 PASS했다. parity runner 회귀는 5 tests / 32
assertions PASS이고 report digest는
`f22d8b617683f36791cd187f3d9ab46a5eb20075a23fc8e269c09ad0cd384d53`이다.

그 snapshot에는 Director Dispatch Index가 없었다. 따라서 DDI parity는 증명되지
않았고, 이 결과를 active integration 근거로 확대하지 않는다. 현재 증거가
지지하는 최선의 방향은 다음과 같다.

1. 파일 기반 semantic/provenance/execution read model을 유지한다.
2. candidate와 CDD 판단을 owner artifact에서 exact pointer/hash로만 읽는다.
3. affected-only는 advisory preview로만 사용한다.
4. current checkout에서 DDI→Queue→Next Unit→Current Next shadow parity가 별도로
   닫힐 때까지 active write, wakeup, invalidation과 engine 도입을 HOLD한다.

이 결과는 외부 graph DB나 Rhai를 지금 도입할 이득이 없다는 초기 권고를
강화한다. 현재 병목은 저장 엔진이 아니라 owner-authored decision evidence와
실제 runtime parity coverage다.
