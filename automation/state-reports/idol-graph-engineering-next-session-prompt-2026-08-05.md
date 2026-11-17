# IDOL 그래프 엔지니어링 새 세션 프롬프트

- 기준일: 2026-08-05 (Asia/Seoul)
- 용도: 새 Codex 또는 Grok 세션에서 현재 하네스 전체 연결을 감사하고,
  그래프 엔지니어링 방향의 장단점을 검토한 뒤 비정본 v0까지 진행
- gate effect: none
- canonical mutation: none
- 방향 문서: `automation/state-reports/idol-graph-engineering-creative-decision-architecture-2026-08-05.md`

> 2026-08-05 실행 상태: 이 프롬프트의 감사와 v0 단계는 완료됐고 graph v1 및
> immutable historical parity까지 구현됐다. 새 세션은 v0를 다시 만들지 말고
> `work/graph-engineering-v1/README.md`, 승인 실행 계획, 방향 문서 13절을 현재
> handoff로 사용한다. DDI가 없는 과거 snapshot을 DDI parity로 확대하지 않으며,
> active integration은 별도 Founder 승인 전까지 HOLD다.

아래 본문을 새 세션의 첫 명령문으로 사용한다.

---

당신은 IDOL 하네스의 Overall-level 아키텍처 검토자이자, 승인 범위 안에서만
움직이는 bounded graph-engineering 구현 담당자다. 작업 루트는 다음이다.

`/Users/yuminseog/aheyabaraya_hq_root/hq-control/creative/IDOL`

## 임무

현재 IDOL 하네스를 전제로 그래프 엔지니어링 방향을 다시 검토하라. 기존
단계·권한·Founder gate·창작 판단을 다른 시스템으로 교체하지 말고, 흩어진
semantic/provenance/execution 관계를 typed dynamic run graph로 투영하는 것이
실제로 품질, 추적성, 재개, affected-only invalidation과 병렬 소유권 관리에
이득인지 검증하라. 장점뿐 아니라 복잡도, schema rigidity, stale projection,
창작 자동 조립, 이중 권위와 운영 비용을 반대 관점에서 강하게 검토하라.

이 작업은 고립된 새 graph schema를 설계하는 일이 아니다. 반드시 현재 IDOL
하네스 전체의 설계 상태와 연결을 먼저 파악해야 한다. 아래 연결을 실제
checkout의 producer/consumer, version, path, schema, validator와 runtime field까지
추적하라.

```text
AGENTS.md
→ activated policies/**
→ harness contract-version registry
→ harness surface-version registry
→ stage registry
→ artifact routing
→ execution contract
→ skill-load profiles
→ every active output-contract schema and its producer/consumer validator
→ owning SKILL.md와 linked reads
→ Department Dispatch / Director Dispatch Index / Reference Working Index
→ Founder Workbench / review projection
→ state check / action queue / next unit / current-next
→ run-owned canonical artifacts / validators / outputs
```

문서에 적힌 v20, v7 같은 번호를 그대로 믿지 말고 현재 bytes와 version registry를
다시 확인하라. 문서와 실제 계약이 다르면 현재 `AGENTS.md → policy → schema →
skill → run artifact` 권위 순서를 따른다.

## 필수 read-first

처음에는 수정하지 말고 다음을 현재 checkout에서 EOF까지 읽어라. linked read가
현재 profile에서 추가로 요구되면 그것도 EOF까지 읽어라.

1. `AGENTS.md`
2. `automation/harness-contract-version-registry.yaml`
3. `automation/harness-surface-version-registry.yaml`
4. `automation/harness-stage-registry.yaml`
5. `automation/harness-artifact-routing.yaml`
6. `automation/harness-execution-contract.yaml`
7. `automation/harness-skill-load-profiles.yaml`
8. `policies/creative-production-constitution.md`
9. `policies/harness-routing-and-sources.md`
10. `policies/section-production.md`
11. `wiki/production-system.md`
12. `wiki/harness-contract-evidence-graph.md`
13. `wiki/reference-management-system.md`
14. `skills/idol-orchestrator/SKILL.md`
15. `skills/idol-front-planning-director/SKILL.md`
16. `skills/idol-front-planning-director/references/director-operating-contract.md`
17. `skills/idol-reference-research-department/SKILL.md`
18. `skills/idol-world-still-reference-department/SKILL.md`
19. `skills/idol-front-planning-handoff/SKILL.md`
20. `schemas/department-dispatch.schema.json`
21. `schemas/director-dispatch-index.schema.json`
22. `schemas/reference-working-index.schema.json`
23. `schemas/harness-stage-registry.schema.json`
24. `schemas/harness-artifact-routing.schema.json`
25. `schemas/harness-action-queue.schema.json`
26. `schemas/harness-next-unit.schema.json`
27. `schemas/harness-current-next.schema.json`
28. `schemas/reference-fragment-crop-lock.schema.json`
29. `scripts/validate_department_dispatch.rb`
30. `scripts/validate_harness_artifact_routing.rb`
31. `scripts/validate_harness_contract_version_registry.rb`
32. `scripts/idol_director_dispatch_index.rb`
33. `scripts/idol_harness_stage.rb`
34. `scripts/idol_harness_action_queue.rb`
35. `scripts/idol_harness_next_unit.rb`
36. `scripts/idol_harness_current_next.rb`
37. `automation/state-reports/idol-graph-engineering-and-agent-topology-audit-2026-08-04.md`
38. `automation/state-reports/idol-graph-engineering-next-session-handoff-2026-08-04.md`
39. `automation/state-reports/idol-graph-engineering-creative-decision-architecture-2026-08-05.md`

그 다음 `automation/harness-stage-registry.yaml`,
`automation/harness-artifact-routing.yaml`과 contract-version registry가 가리키는
모든 active output-contract schema를 따라가서 EOF까지 읽고, 각 schema의 실제
producer, consumer와 validator를 확인하라. 전체 `schemas/**`를 목적 없이 읽는
것이 아니라 active route의 연결을 끝까지 닫는 방식으로 조사하라.

전체 reference catalog, raw media pool, active run의 창작 내용이나 unrelated archive는
읽지 마라. 필요한 구조는 schema, contract, skill, validator와 fixture에서 확인하라.

## 절대 경계

1. `runs/aurora-m/su/**`를 읽거나 수정하지 마라.
2. 다른 활성 run의 creative truth, Founder decision, review board와 current-next를
   수정하지 마라.
3. `cf/**`를 IDOL MV graph에 섞지 마라.
4. 외부 네트워크, MCP, API, paid generation, upload, publish, secret, 계정과
   credential을 사용하지 마라.
5. graph database, Rhai, CEL, Rust host 또는 새 외부 dependency를 설치하지 마라.
6. graph를 새로운 canonical creative truth나 두 번째 stage authority로 만들지 마라.
7. 새 Judgment Card, 중복 creative schema 또는 합산 점수 기반 creative PASS를
   만들지 마라.
8. word/line/size 진단을 이유로 기존 instruction, policy, schema 또는 skill을
   분할·압축·재작성하지 마라.

## 창작 권한의 핵심

다음이 이 감사와 설계의 중심이다.

```text
YAML·source media·곡·타깃·앞뒤 장면을 assigned model이 실제로 읽음
→ 작업자 AI가 근거 있는 복수 reference/frame 후보와 적용안을 작성
→ CDD가 후보와 actual evidence를 다시 읽고 선택·결합·탈락을 판단
→ CDD가 새로운 통합 방향 C와 이유를 직접 작성
→ Overall Director가 검토·승격
→ 필요한 Founder gate
→ 확정된 C를 기존 owner artifact에 기록
→ script는 exact-copy / validate / route만 수행
```

Python, Ruby, Rhai, graph projection 또는 template compiler가 A/B YAML 필드를
붙이거나 의역해 C를 만들면 실패다. 이미 human/model-authored이고 director-reviewed된
결정만 exact-copy할 수 있다. CDD-authored decision이 없으면
`creative_decision_required` HOLD를 제안하라.

Reference worker는 단순 수집자가 아니다. 실제 pixels/playback과 source analysis를
읽고 다음을 갖춘 후보군을 CDD에게 반환해야 한다.

- exact source identity, locator, derivative path와 SHA-256
- observed source evidence
- named need와 bounded transfer
- preserve/discard boundary
- observable screen consequence와 exact placement
- current-song/member/world dependency
- mismatch, feasibility와 weaker-neighbor reason
- candidate anchor frames와 proposed applied/combined/held/rejected disposition

Worker proposal은 canonical selection이 아니다. 최소 상태를 다음처럼 분리해라.

```text
raw_evidence
→ worker_candidate
→ cdd_selected | cdd_combined | cdd_rejected | cdd_hold
→ overall_promoted | overall_returned | overall_hold
→ founder_locked | founder_passed | founder_held | founder_rejected
→ projected_downstream
```

Frame/sequence sheet는 전체를 한 mood image로 취급하지 마라. Layer A ordered-flow
observation, worker-proposed anchor candidate와 각 anchor의 Layer B pixel observation을
분리하라. 전체 sheet는 navigation/ordered grammar evidence이며 selected still이나
generation attachment가 아니다. 추출 script는 이미 제안·선택된 픽셀만 분리할 수
있고 새 candidate를 선택할 수 없다.

## 감사할 세 그래프

### Semantic Graph

`target/message → song cue → section job → reference candidate/worker proposal →
CDD synthesis → Major/Key Screen → Core/Branch → observable screen proof`를
추적하라. Semantic edge의 이유는 AI가 작성하고 감독이 검토해야 한다.

### Provenance Graph

`source bytes/hash → analysis → sheet/frame/crop/sequence → interpretation receipt →
worker evidence → selected binding → 01/02A/02B → generated/playback/edit evidence`를
exact path/hash로 추적하라. Raw media를 graph에 복제하지 마라.

### Execution Graph

`stage/job/section/review/gate → dispatch/lineage/attempt/owner/checkpoint →
prepared/launched/returned/reviewed/promoted|hold → invalidation/next owner`를
추적하라. Execution Graph는 creative PASS나 Founder approval을 만들 수 없다.

## 수행 순서

### A. 현재 상태 감사

먼저 read-only로 다음을 제출하라.

1. 현재 stage와 artifact routing 연결 지도
2. role/owner/review/Founder gate 연결 지도
3. schema producer/consumer와 validator call graph
4. reference discovery→observation→candidate→CDD synthesis→01/02A/02B 연결
5. frame sheet→candidate anchor→director-selected anchor 연결
6. Department Dispatch/index/event-like/current-next의 기존 graph 기능
7. 이미 해결된 것, 중복될 것, 실제로 없는 것
8. 현재 문서의 제안이 current contract와 충돌하는 지점

Contract 존재를 runtime compliance로 오인하지 마라. 실제 런을 열지 않는 이
감사에서는 `설계상 보장`, `validator가 보장`, `실제 런 증거가 필요`를 분리해라.

### B. 장단점과 대안 비교

다음을 같은 기준으로 비교하라.

1. 현행 분산 계약 유지
2. 로컬 read-only typed graph projection
3. append-only event + graph projection
4. workflow/graph database 또는 constrained expression runtime

각 선택지에 대해 창작 품질, authority drift, traceability, invalidation precision,
resumability, context pressure, implementation complexity, testability, dependency,
운영 비용과 failure recovery를 평가하라. 한 개의 주 추천안을 내고, 정말
비호환한 대안이 필요할 때만 한 개를 추가하라.

### C. 비정본 Phase 1 진행

감사 결과 material contradiction이 없고 read-only graph v0가 주 추천이면 같은
세션에서 다음 범위까지 진행해도 된다.

- `work/graph-engineering-v0/` 아래에만 비정본 contract, sample projection,
  projector와 tests를 만든다.
- active instruction/policy/schema/skill/runner/run/current-next는 수정하지 않는다.
- fixture 또는 최소 synthetic pointer graph만 사용한다. SU와 active run은 읽지 않는다.
- 기존 YAML/JSON/Markdown의 exact pointer/hash/state만 투영한다.
- semantic relation은 기존 AI-authored field를 가리키며 새 creative prose를
  생성하지 않는다.
- graph-derived next state는 advisory/shadow only다.

현재 계약과 충돌하거나 active surface 변경이 필요하면 prototype을 억지로 만들지
말고 `FOUNDER_DECISION_REQUIRED`로 정리하라.

### D. Active integration gate

Tracked instruction, policy, contract, schema, skill, validator, shared script,
action queue/current-next 또는 runtime route를 바꾸기 전에는 반드시 Founder에게
다음을 제시하고 명시 승인을 받아라.

- 정확한 변경 파일과 owner
- 왜 기존 surface로 해결할 수 없는지
- primary recommendation과 tradeoff
- migration/rollback과 affected scope
- contract-version registry와 surface revision/SHA 갱신 계획
- shadow evidence와 acceptance test

## 비정본 v0 수용 기준

- script-authored/paraphrased creative node 0
- worker candidate의 무검토 promotion 0
- Founder gate inference/bypass 0
- duplicate canonical owner 0
- 동일 입력 rebuild digest 차이 0
- unrelated-section invalidation 0
- source path/hash 없는 direct reference edge 0
- whole frame sheet가 selected still로 승격된 경우 0
- 모든 HOLD가 evidence path, blocking edge, next legal owner를 설명
- 기존 action queue/current-next와 차이가 나면 fail-closed하고 차이를 보고

## 최종 응답 형식

1. **판정** — 그래프 엔지니어링이 현재 IDOL에 실제로 유리한지
2. **현재 전체 연결** — stage, schema, skill, dispatch, review, queue/current-next
3. **이미 있는 것 / 빈틈 / 중복 위험**
4. **장점 / 단점 / 실패 시나리오**
5. **주 추천안** — 한 개, 필요하면 비호환 대안 한 개
6. **Phase 1 결과** — 생성한 비정본 파일, tests와 shadow evidence 또는 HOLD 이유
7. **Active integration 전에 필요한 Founder 결정**

결론을 먼저 말하고, 실제 path·schema·validator evidence로 뒷받침하라. 그래프를
도입하는 것 자체를 목표로 삼지 말고, 현재 하네스보다 명백히 나은 경우에만
유지하라.
