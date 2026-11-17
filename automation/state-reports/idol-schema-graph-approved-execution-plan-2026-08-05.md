# IDOL 스키마·그래프 승인 실행 계획

- 승인일: 2026-08-05 (Asia/Seoul)
- 승인 범위: 스키마 현대화·퇴역과 비정본 graph v1 개선
- 상태: 완료 (active graph integration 제외)
- gate effect: none
- canonical creative mutation: none
- paid/external action: none
- active run write: none

## 목표

레퍼런스 선택에서 최종 결과물까지의 품질·권한·provenance를 약화하지 않으면서:

1. 모든 schema를 active contract 또는 명시적 non-authoring lifecycle에 정확히 한 번
   분류한다.
2. active contract는 한 개의 current/readable version만 사용한다.
3. 이관이 끝난 old contract는 신규 작성·실행을 차단하고 retired evidence로 격리한다.
4. graph v0를 실제 IDOL artifact를 읽을 수 있는 pointer-only v1로 확장한다.
5. graph는 worker 후보, CDD 판단, Overall/Founder authority와 affected-only 범위를
   설명하되 creative truth나 Current Next를 쓰지 않는다.

## 고정 경계

- `runs/aurora-m/su/**`는 읽거나 쓰지 않는다.
- 다른 active run의 creative prose, Founder decision, review board, media를 수정하지 않는다.
- non-SU parity는 pointer/status/hash/owner/section 범위의 read-only snapshot만 사용한다.
- graph는 canonical owner, Founder state, creative PASS, paid approval을 만들지 않는다.
- schema migration script는 creative 값을 작성·의역·보완하지 않는다.
- 현재 dirty worktree의 unrelated 변경을 되돌리거나 덮어쓰지 않는다.
- tracked schema/registry/validator가 바뀌면 contract/surface revision과 SHA를 같은
  patch에서 갱신한다.

## 실행 순서

### A. Schema S0 — inventory

- contract registry v3에 `non_authoring_schemas` lifecycle inventory를 추가한다.
- hard-coded retired/non-authoring 목록을 registry-owned data로 대체한다.
- root/external/retired schema count를 분리한다.
- active contract와 lifecycle inventory의 중복·누락·SHA·path를 검증한다.

수용 기준:

- unclassified root schema 0
- duplicate active/lifecycle path 0
- lifecycle SHA mismatch 0
- current active stage contract 누락 0

### B. Schema S1 — current auxiliary

다음 current support contract를 active auxiliary로 등록한다.

- downloaded reference hub
- edit cutpoint sheet manifest
- edit effect registry
- edit QC closeout
- harness frontier check
- LLM review execution record
- reference song fit
- video reference hub cadence audit
- reference fragment crop lock acquisition bridge

`social-analytics`는 definitions-only로 분류하며 현재 별도 작업 bytes를 보존한다.

### C. Schema S2/S3 — migration blockers

- crop-lock은 reference-intake parity가 증명될 때까지 active auxiliary로 유지한다.
- cue BPM은 active Edit Marker Plan의 legacy required pointer를 현행 audio placement로
  교체한 뒤 퇴역한다.
- harness artifact envelope는 state-check compatibility reader가 남아 있는 동안
  read-only로 유지한다.
- single/two-cut legacy generation runner는 신규 prepare/submit을 fail-closed한 뒤
  schema를 퇴역한다.

### D. Schema S4 — retired evidence

replacement가 이미 있는 old 00/01A/02/01R/02B/03V/Terra/wardrobe schema를
`retired_evidence`로 동결한다. exact historical consumer가 남아 있으면 현재 path를
보존하고, active authoring과 실행만 차단한다. 물리 이동은 replay parity와 품질 이득이
둘 다 증명될 때만 한다.

### E. Graph G1 — locator와 identity

- evidence locator를 JSON Pointer, YAML Pointer, Markdown heading/line hash로 확장한다.
- `logical_entity_id`는 owner-authored stable id만 exact-copy한다.
- `evidence_location_id`는 path+locator+hash로 별도 계산한다.
- script가 logical id를 추론하거나 창작 prose를 graph에 복사하면 FAIL한다.

### F. Graph G2 — reference decision lineage

- 복수 worker candidate를 허용한다.
- candidate마다 source/frame pointer, section, disposition proposal을 보존한다.
- CDD selected/combined/rejected/hold는 별도 model-authored decision pointer를 요구한다.
- Overall promotion과 explicit Founder decision predecessor를 계속 강제한다.

### G. Graph G3 — affected-only preview

- hash/decision change에서 declared dependency만 순회한다.
- affected section, smallest legal owner, invalidated binding/review와 preserved section을
  advisory preview로 출력한다.
- unrelated section이 포함되거나 dependency evidence가 없으면 HOLD한다.

### H. Graph G4 — actual read-only parity

- 허용된 non-SU historical snapshot에서 Director Dispatch Index 존재 여부, Action
  Queue, Next Unit, Founder Gate, Current Next의 pointer/status/hash/owner/section을 읽는다.
- graph preview와 field별 parity/mismatch를 출력한다.
- mismatch는 graph PASS나 active write가 아니라 advisory HOLD다.

## 진행 기록

| 묶음 | 상태 | 증거 |
| --- | --- | --- |
| 기준선 감사 | PASS | root 120, registry 100, root unregistered 23, exact duplicate 0 |
| Schema 계획 | PASS | `idol-schema-modernization-retirement-plan-2026-08-05.md` |
| Schema S0 | PASS | selected commit tree: registry v3, active 108, non-authoring 14, unclassified 0 |
| Schema S1 | PASS | auxiliary 등록, current/readable version 단일화 |
| Schema S2/S3 | PASS/HOLD | crop-lock 유지, Cue BPM 이관 PASS, legacy generation fail-closed PASS, envelope만 compatibility HOLD |
| Schema S4 | PASS | 12 retired schema 신규 작성 차단·설명 동결; historical exact path 때문에 물리 삭제 0 |
| Graph v0 baseline | PASS | 11 tests, 53 assertions, digest `8180d567...4aac` |
| Graph G1/G2/G3 | PASS | 15 tests, 83 assertions, digest `b952b7e8...1970` |
| Graph G4 | PASS/HOLD | historical Queue→Next→Gate→Current 44/44 PASS; snapshot DDI 부재로 active DDI parity HOLD |
| 전체 closeout | PASS | contract/surface/routing + focused regression suite |

## 정지 조건

다음 중 하나라도 발생하면 해당 묶음을 HOLD하고 이전 묶음의 passed bytes를 유지한다.

- reference selected derivative/path/SHA/section/transfer 손실
- current-title member visual 또는 attachment order 변화
- creative value를 script가 새로 작성해야만 migration 가능
- active run canonical write 필요
- Founder decision 추론 필요
- unrelated section invalidation
- legacy runner 차단이 active v8 generation을 막음
- current dirty owner patch와 안전하게 병합할 수 없음

## 완료 기준

- schema inventory 누락 0
- active readable-version plural 0
- retired schema의 미승인 active consumer 0
- legacy generation submit route 0
- graph의 script-authored semantic reason 0
- worker candidate 무검토 promotion 0
- Founder inference 0
- unrelated invalidation 0
- actual parity mismatch는 모두 설명 가능한 HOLD
- 전체 변경과 미완료 항목이 closeout 문서에 기록됨

## 구현 산출물

- schema closeout:
  `automation/state-reports/idol-schema-modernization-retirement-plan-2026-08-05.md`
- graph direction과 실제 결과:
  `automation/state-reports/idol-graph-engineering-creative-decision-architecture-2026-08-05.md`
- graph v1 proof:
  `work/graph-engineering-v1/`
- actual historical parity:
  `work/graph-engineering-v1/actual-parity-report.json`

현재 active integration을 막는 두 항목은 실패가 아니라 의도적인 품질 경계다.

1. broad state compatibility reader가 남아 있어 artifact envelope를 물리 퇴역하지 않음
2. historical parity snapshot에 DDI가 없어 DDI→Current Next active parity를 주장하지 않음

## 최종 검증 증거

### Registry와 routing

- contract registry: PASS
  - active routes 108
  - active root 105 / external 3
  - non-authoring 14
  - unclassified 0
  - exact duplicate 0
- surface registry: PASS, 406 surfaces / 36 skills
- active artifact routing: PASS, 19 stages exact-covered
- contract/surface/stage registry JSON Schema: PASS

이 숫자는 이번 schema/graph 선택 커밋 기준이다. 별도 TikTok Studio/social analytics
작업의 contract와 surface 변경은 기존 더티로 남기며 이 커밋 수치에 합치지 않는다.

### Edit와 legacy generation

- Edit Marker Plan v4: 9 tests PASS
- Edit Recipe lineage: 10 tests PASS
- cutpoint/contact sheet: 2 tests PASS
- 04FX semantic/lineage validator: 33 runs / 132 assertions PASS
- 04FX actual FFmpeg render matrix: 14 tests PASS
- legacy beat-source new-authoring retirement: 3 tests PASS

### Retired evidence compatibility

- uncapped section compatibility: 1 test PASS
- retired 01R selected/floor checks: 2 runs / 21 assertions PASS
- video-reference sequence compatibility: 4 runs / 45 assertions PASS
- Terra historical lifecycle: 6 runs / 17 assertions PASS
- Luna current lifecycle: 6 runs / 17 assertions PASS

### Graph

- synthetic graph v1: 15 runs / 83 assertions PASS
- immutable historical parity runner: 5 runs / 32 assertions PASS
- actual Queue→Next Unit→Founder Gate→Current Next comparisons: 44 / 44 PASS

### 현재 checkout의 별도 baseline cleanup

후속 승인에 따라 두 잔여 항목도 owner 범위를 보존한 채 닫았다. 연구 projection
test의 5개 stale-shape error는 품질 규칙을 삭제하지 않고 현재 01 v1.9, 01R-C v3,
02A v2.2, 02B v2.1 경로를 검증하도록 갱신했다. 결과는 13 runs / 150 assertions
PASS다. tracked-only terminology guard의 16개 항목은 검사를 완화하지 않고 실제
안내 문구를 현재 `review material/review stage`, `visual inputs` 표현으로 고쳤으며
guard가 PASS했다. 변경한 tracked surface는 revision과 SHA-256을 같은 patch에서
동기화했다.
