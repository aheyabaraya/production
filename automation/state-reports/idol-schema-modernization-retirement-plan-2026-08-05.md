# IDOL 스키마 현대화·퇴역 계획

- 기준일: 2026-08-05 (Asia/Seoul)
- 성격: 승인된 개선 계획과 실행 closeout
- gate effect: none
- canonical creative mutation: none
- 구현 승인: 2026-08-05 Founder 승인 완료
- 실행 상태: 구현·검증 완료, 물리 삭제 0건
- 범위: IDOL 루트 스키마, contract/surface registry, schema validator와 직접 producer/consumer
- 제외: 활성 런 창작 정본, `runs/aurora-m/su/**`, `cf/**`, 유료·외부 실행, 그래프 active integration

## 1. 결론

스키마를 정리하는 방향에는 동의한다. 다만 모든 파일의 숫자만 일괄 상승시키는
방식은 사용하지 않는다. 각 스키마의 최신 버전은 그 계약 owner와 실제
producer/consumer가 합의한 **한 개의 current authoring version**이어야 한다.

권고 방식은 다음과 같다.

```text
현재 계약·consumer 역참조
→ active / auxiliary / definitions / compatibility / retired 분류
→ 현행 계약은 읽기 가능한 버전 한 개로 정규화
→ 대체 계약으로 값·경로·SHA·권한을 손실 없이 이관
→ 구형 신규 작성과 실행 경로 차단
→ 역사 증거는 별도 retired 위치에 보존
→ 검증 주기 후에만 물리 삭제 검토
```

즉, **최신화와 퇴역을 함께 진행하되 삭제부터 시작하지 않는다.** 현재
미등록 23개에는 현행 보조 계약, 이관 미완료 계약, 실제 퇴역 잔재가 섞여 있다.

## 2. 현재 검증된 기준선

- root `schemas/*.json`: 120개
- contract-version registry route: 100개
- 그중 root `schemas/` route: 97개
- Workbench 아래 외부 schema route: 3개
- 실제 root 미등록 schema: 23개
- 전체 root schema exact-content duplicate group: 0
- 전체 root schema duplicate `$id` group: 0
- active registered schema high-overlap diagnostic: 1쌍
  - `03v-generated-playback-intake`
  - `03v-playback-review-worklist`
  - 순차 intake와 review preparation이므로 병합하지 않는다.

현재 validator의 `inactive_or_auxiliary_schema_count: 20`은 root schema 120개에서
외부 3개를 포함한 registry route 100개를 단순 차감한 값이다. 실제 root 미등록
수는 23개이므로 이 label을 삭제 후보 수로 사용하지 않는다.

현재 다음 검증은 PASS다.

- contract-version registry validation
- surface-version registry validation
- active artifact routing validation

이 PASS는 현재 active route의 구조가 닫힌다는 뜻이지, 미등록 23개가 모두
불필요하거나 삭제 가능하다는 뜻은 아니다.

## 3. 최신화 원칙

### 3.1 최신 버전의 의미

1. 전 스키마가 같은 숫자를 가질 필요는 없다.
2. 실제 contract shape나 authority가 바뀔 때만 authoring version을 올린다.
3. active contract는 `readable_versions`에 current version 하나만 둔다.
4. 역사 버전은 active schema의 enum fallback으로 남기지 않는다.
5. 이관되지 않은 과거 artifact는 evidence-only 또는 HOLD다.
6. provider 이름만 바뀐 후속 계약도 old/new 동시 authoring을 허용하지 않는다.

### 3.2 생명주기 상태

`automation/harness-contract-version-registry.yaml`을 active contract 목록이자
전체 schema 생명주기 inventory로 확장한다.

| 상태 | 의미 | 신규 작성 | active 실행 |
| --- | --- | --- | --- |
| `active_authoring` | 정본 또는 현행 run-owned contract | 허용 | 허용 |
| `active_auxiliary` | 현행 audit, receipt, registry, source-hub, QC 보조 계약 | 허용 | owner 범위에서 허용 |
| `definitions_only` | `$defs` 또는 runtime validator용 library | top-level 작성 금지 | 직접 실행 없음 |
| `compatibility_read_only` | state/history를 읽기 위한 과도기 계약 | 금지 | advancement authority 없음 |
| `retired_evidence` | 대체가 끝난 역사 계약 | 금지 | 금지 |
| `tombstoned` | 검증 주기를 마치고 bytes 제거가 승인된 계약 | 금지 | 금지 |

active가 아닌 schema도 다음을 선언한다.

- owner
- original path와 current path
- schema id와 version
- lifecycle state
- replacement contract
- allowed historical consumers
- new authoring forbidden 여부
- migration blocker
- exact SHA-256
- retirement decision/approval

Ruby validator 내부의 hard-coded retired/non-authoring 배열은 이 registry 데이터로
대체한다. 모든 schema가 active contract 또는 lifecycle inventory 중 정확히 한 곳에
속하지 않으면 FAIL한다.

## 4. 미등록 23개 판정과 목표 상태

### 4.1 현행 보조 계약 — 유지·등록 9개

| schema | 현재 역할 | 목표 |
| --- | --- | --- |
| `downloaded-reference-hub` | source hub catalog/manifest/frame index 계약 | `active_auxiliary`로 등록하고 hub producer/validator를 명시 |
| `edit-cutpoint-sheet-manifest` | 04 boundary frame-step QC manifest | `active_auxiliary`로 등록 |
| `edit-effect-registry` | 실행 가능한 04FX registry YAML 계약 | registry YAML을 실제 schema로 검증하고 `active_auxiliary` 등록 |
| `edit-qc-closeout` | 최종 04 closeout v2 | v2만 current로 남기고 v1은 retired evidence로 분리 |
| `harness-frontier-check` | active frontier read model | `active_auxiliary`로 등록 |
| `llm-review-execution-record` | 02A review execution identity evidence | `active_auxiliary`로 등록 |
| `reference-song-fit` | Founder song reference 기반 PRE-00S 분석 | current 1.2 한 개로 정규화·등록하고 1.1은 evidence-only |
| `social-analytics` | runtime validator용 definitions-only library | `definitions_only`로 명시; 현행 작업 중인 bytes와 충돌하지 않게 별도 patch |
| `video-reference-hub-cadence-audit` | reference hub cadence 감사 결과 | `active_auxiliary`로 등록 |

이 묶음은 삭제 대상이 아니다. registry에 없어서 불필요해 보였을 뿐, 레퍼런스
선택·편집 QC·Frontier 판단·Song reference 분석·SNS 검증에 실제 사용된다.

### 4.2 이관 또는 active/retired 충돌 해결이 먼저인 5개

#### `reference-fragment-crop-lock`

현재 schema는 active v3를 선언하고, Front Planning handoff와 Workbench adapter는
이를 `reference-intake.v2` 입력으로 사용한다. 그러나 artifact routing/contract
validator는 retired pattern으로 취급한다.

우선 권고:

- 단기: `active_auxiliary` acquisition/selection bridge로 재분류
- 장기: crop/acquisition owner가 `reference-intake.v2`를 직접 작성할 수 있을 때 퇴역
- 이관 parity: source identity, locator, selected derivative path/SHA, target sections,
  direct-follow strength, preserve/transfer locks가 모두 같아야 함

이 parity가 없으면 삭제하지 않는다.

#### `cue-bpm-map`

producer와 validator는 inactive historical로 선언되어 있지만 active
`edit-marker-plan.v3`가 `source_cue_bpm_map`을 필수로 요구한다.

이관 순서:

1. Edit Marker Plan을 새 current version으로 올린다.
2. Audio-Branch-Cut Placement와 current audio-motion/selected-audio evidence를
   현행 timing source로 고정한다.
3. edit-map, 04FX lineage validator와 fixtures를 새 source로 갱신한다.
4. active authoring에서 cue BPM pointer가 0임을 확인한다.
5. 그 뒤 `cue-bpm-map`을 `retired_evidence`로 옮긴다.

#### `harness-artifact-envelope`

producer는 inactive지만 broad state check와 historical artifact validator가 아직
읽는다. current stage authority로 승격하지 않고 `compatibility_read_only`로 명시한다.
State check가 current owner artifact, run manifest, dispatch/receipt와 직접 lineage를
읽도록 이관된 뒤에만 퇴역한다.

#### single/two-cut beat-source generation manifests

- `single-cut-beat-source-generation-manifest`
- `two-cut-beat-source-generation-manifest`

문서상 legacy evidence-only지만 old Batch runner에는 prepare/submit/status/download/
import 경로가 남아 있다. 두 schema는 서로 다른 shape인데 같은
`idol_cut_only_keyframe_generation_manifest.v1` token도 공유한다.

이관 순서:

1. active `image-generation-request.v8`와 Branch-Cut route가 필요한 생성 기능을
   모두 소유함을 확인한다.
2. legacy builder와 Batch runner가 새 요청을 prepare/submit하지 못하도록 fail-closed한다.
3. old manifest를 active fallback으로 읽는 consumer가 0인지 확인한다.
4. historical crop/inspection이 필요하면 read-only tool과 schema를 retired 위치에 함께 둔다.
5. 두 schema를 함께 퇴역한다.

### 4.3 1차 퇴역 묶음 후보 9개

| schema | active replacement 또는 퇴역 근거 |
| --- | --- |
| `03v-creative-context-review-execution-record` | pre-manifest 03V validator가 이미 retired; 현행 playback intake/worklist와 section lifecycle 사용 |
| `creative-nucleus` | active 00A Song Lock + Front Planning이 creative spine 소유 |
| `generation-map` | 02A Master Storyboard coverage + 02B packet/request가 소유 |
| `mv-direction-reference-mining` | Front Planning v11 + Reference Working Index + 01 reference applications가 소유 |
| `prompt-packets-v1.3-legacy` | active `prompt-packets` v2.1이 Branch Cut별 packet 소유 |
| `track-visual-board` | current-title member visual package + Front Planning이 소유 |
| `wardrobe-style-review` | current-title package와 Front Planning styling truth가 소유 |
| `terra-section-lifecycle-execution-record` | registered Luna execution record v1 존재 |
| `terra-section-lifecycle-receipt` | registered Luna receipt v1 존재 |

이 9개는 실제 이전 상태 잔재에 가장 가깝다. 다만 역사 테스트, terminology guard,
surface registry 또는 validator path를 먼저 retired 위치로 바꾼 뒤 이동한다.

Terra→Luna는 후속 schema가 이미 등록됐지만 다음 잔재가 남아 있다.

- Terra schema 두 개
- Terra validator와 tests
- surface registry의 active처럼 보이는 role 문구
- 일부 contract consumer의 `terra_section_execution` 명칭

이 묶음을 하나의 provider-migration closeout patch로 처리한다.

## 5. 물리 배치

현행 authoring schema는 기존 root에 유지한다.

```text
schemas/*.schema.json
```

퇴역 bytes를 보존해야 하면 다음처럼 격리한다.

```text
schemas/retired/CONTRACT_ID/VERSION.schema.json
```

contract-version registry가 original path, retired path, replacement와 SHA-256를
기록한다. active producer/consumer는 `schemas/retired/**`를 읽을 수 없다. 역사 검증
도구만 declared allowed consumer로 접근할 수 있다.

물리 삭제는 다음이 모두 닫힌 뒤 별도 승인한다.

- active producer/consumer/skill reference 0
- active run authoring reference 0
- external-capable legacy execution path 0
- canonical replacement 존재
- migration/parity test PASS
- 역사 증거 retention 필요 없음 또는 Git 복구로 충분하다는 Founder 결정

## 6. 구현 묶음

### S0 — inventory 정확도

변경 후보:

- `automation/harness-contract-version-registry.yaml`
- owning registry schema
- `scripts/validate_harness_contract_version_registry.rb`
- `automation/harness-surface-version-registry.yaml`

결과:

- root unclassified schema 0
- active와 non-authoring count 분리
- hard-coded retirement list 제거
- duplicate/path/version 검사 범위 유지

### S1 — 현행 auxiliary 정규화

9개 현행 보조 계약을 active auxiliary 또는 definitions-only로 등록한다.
`edit-qc-closeout`과 `reference-song-fit`은 readable version을 한 개로 만든다.
현재 수정 중인 `social-analytics`는 별도 owner patch가 안정된 뒤 합류한다.

### S2 — 품질 경로 이관

- crop-lock의 active bridge 여부 확정과 reference-intake parity
- cue BPM 의존을 Audio-Branch-Cut Placement로 교체
- harness envelope compatibility reader 축소

레퍼런스 선택, selected derivative, path/SHA, section binding, prompt attachment order,
Audio-Branch-Cut timing과 edit playback 증거가 약해지면 이 묶음은 HOLD다.

### S3 — legacy generation route 종료

- single/two-cut legacy builder/runner의 신규 prepare/submit 차단
- active v8 request route 외 fallback 0
- historical read-only crop/inspection만 필요 시 격리

### S4 — 1차 퇴역 묶음 이동

9개 후보와 직접 historical validator/test만 이동한다. active skill, policy, runtime
route나 canonical artifact를 바꾸지 않는다. Terra→Luna stale consumer 명칭도 함께
정리한다.

### S5 — 삭제 판단

한 차례 전체 검증과 실제 non-SU read-only parity 확인 후 Founder에게 exact path,
hash, replacement, rollback을 제시한다. 승인 전에는 bytes를 삭제하지 않는다.

## 7. 품질 보호 수용 기준

1. root unclassified schema: 0
2. active contract의 readable version 수: 각 1
3. duplicate `$id`: 0
4. exact-content duplicate: 0
5. retired schema를 읽는 active producer/skill: 0
6. legacy 외부 실행 가능 runner: 0
7. crop-lock→reference-intake exact path/hash/section/transfer 손실: 0
8. active 04 authoring의 cue BPM legacy 의존: 0
9. current-title member identity/reference binding 변화: 0
10. 02A Branch Cut→02B packet→generation request의 attachment order 변화: 0
11. active stage/routing/contract/surface validator: PASS
12. reference hub, edit readiness/QC, Luna lifecycle, social analytics 관련 검증: PASS
13. active run canonical bytes 변경: 0
14. paid/external call: 0

Schema validation PASS는 창작 품질 PASS가 아니다. 실제 레퍼런스 선택과 결과물
과정의 품질은 source identity, selected pixel/sequence, exact locator/path/SHA,
section application, current-title identity, prompt binding, pixel/playback review가
그대로 유지되는지로 판정한다.

## 8. 롤백

- 각 묶음은 독립 commit/patch로 유지한다.
- active schema migration 전 baseline schema/registry SHA를 기록한다.
- current artifact bytes는 in-place 자동 변환하지 않는다.
- migration failure 시 current registry route와 producer를 이전 current bytes로 되돌린다.
- retired 이동은 원래 path와 SHA를 registry에 보존하여 원위치 복원이 가능해야 한다.
- active run이나 Founder decision은 rollback 대상에 포함하지 않는다.

## 9. 이번 문서가 승인하지 않는 것

- 스키마 일괄 version-number bump
- active contract의 legacy fallback 유지
- reference/crop/sequence 정보 축약
- old generation runner를 compatibility route로 재사용
- active run artifact 자동 변환
- schema pass를 creative PASS로 간주
- 그래프의 active current-next, invalidation 또는 canonical write 통합
- 물리 삭제

그래프 개선은 이후 Founder의 별도 승인으로 비정본 v1까지 진행됐다. 결과와 active
integration HOLD 경계는
`idol-graph-engineering-creative-decision-architecture-2026-08-05.md`에 기록한다.

## 10. 승인 후 실제 실행 결과

이 절은 위 계획의 예상 수치와 이동안을 현재 실행 결과로 대체한다.

### 10.1 inventory와 current version

| 항목 | 실행 결과 |
| --- | --- |
| root schema | 120 |
| active contract route | 108 |
| active root route | 105 |
| active external route | 3 |
| non-authoring lifecycle | 14 |
| unclassified root schema | 0 |
| `retired_evidence` | 12 |
| `compatibility_read_only` | 1 |
| `definitions_only` | 1 |
| exact duplicate group | 0 |
| duplicate active/lifecycle route | 0 |
| active readable-version plural | 0 |

Contract registry를 v3 전체 inventory로 확장했고, hard-coded retired 목록을
제거했다. 새 작업은 각 active contract의 한 개 current/readable version만 통과한다.
미등록처럼 보이던 현행 보조 계약 9개는 active route에 등록됐다.

다음 multi-version schema는 current version 하나만 남겼다.

- `edit-qc-closeout`: v2
- `reference-song-fit`: 1.2
- `skill-application-receipt`: v3
- `founder-intervention-receipt`: v2
- `social-evidence-snapshot`: v2

### 10.2 품질 경로 이관

- `reference-fragment-crop-lock.v3`는 삭제하지 않고 현행 acquisition/selection
  bridge로 등록했다. selected derivative, locator, path/SHA와 section transfer를
  줄이는 강제 이관은 하지 않았다.
- Edit Marker Plan은 v4, Edit Map은 v3으로 올리고 legacy Cue BPM 필수를 제거했다.
  둘 다 current Audio Motion Director Map path/SHA를 요구하며 04FX validator도
  onset/drop/lyric signal lineage를 같은 source에서 확인한다.
- local FFmpeg에 `drawtext`가 실제로 없음을 회귀 중 발견해 effect registry를
  `metadata_only`로 바로잡았다. 지원하지 않는 효과를 PASS하는 경로는 없다.
- `harness-artifact-envelope`는 broad compatibility validator가 아직 읽으므로
  `compatibility_read_only`로 유지했다. 이 파일만 현재 남은 이관 blocker다.

### 10.3 legacy generation 종료

single/two-cut beat-source builder와 sharder는 신규 작성이 fail-closed다. Batch
runner의 신규 prepare/paid submit도 fail-closed이며, 이미 제출된 역사 작업의
status/download/import recovery만 남겼다. active generation route는 section-scoped
Image Generation Request와 Dispatch Ledger다.

### 10.4 퇴역 schema의 실제 처리

12개 old schema는 모두 `new_authoring: false`이고 schema 자체 설명에도
`retired evidence-only`와 active replacement를 명시했다. 하지만 이번에는 root에서
이동하거나 삭제하지 않았다.

| 묶음 | 물리 삭제 판정 | 근거 |
| --- | --- | --- |
| old 03V review execution | 금지 | uncapped-section compatibility test와 authority audit가 exact path를 읽음 |
| old 00/02/01A/wardrobe | 보류 | radar, audit, surface history, handoff가 exact path를 보존 |
| Cue BPM | 보류 | historical skill-purpose matrix의 exact read path 보존 |
| old 01R mining | 금지 | reference projection/sequence contract tests가 읽음 |
| prompt packets v1.3 | 금지 | terminology guard와 generation reference가 의도적으로 읽음 |
| Terra receipt/execution | 금지 | historical Terra validator가 읽음 |
| single/two-cut manifests | 보류 | active authoring consumer는 0이지만 2026-07-08 closeout의 exact replay command를 보존 |

즉, 현재 남은 파일은 active authoring 잔재가 아니라 명시적으로 동결된
compatibility/evidence bytes다. 지금 지우면 레퍼런스 선택이나 생성 품질이 좋아지는
효과는 없고 역사 검증·재현성만 떨어진다. 따라서 **신규 사용 차단은 완료했지만
물리 삭제는 0건**이 가장 이득이 큰 판정이다.

### 10.5 겹치는 schema 판정

overlap diagnostic은 6쌍을 찾았지만 exact duplicate는 0이다.

- 5쌍은 active replacement와 retired evidence, 또는 retired single/two variant다.
  authoring을 병합하지 않고 lifecycle로 분리하는 것이 맞다.
- 유일한 active/active 쌍인 `03v-generated-playback-intake`와
  `03v-playback-review-worklist`는 generated clip 수집과 사람 검토 준비라는 서로
  다른 owner state를 가진 순차 계약이다. 병합하면 intake evidence와 review
  disposition 경계가 흐려지므로 유지한다.

### 10.6 최종 삭제 원칙

향후 `keep_in_place`를 archive/delete로 바꾸려면 exact historical consumer를 먼저
새 위치로 안전하게 이관하고 replay parity를 보여야 한다. 파일이 낡아 보인다는
이유, 필드 overlap 또는 최신 숫자로의 일괄 bump는 삭제 근거가 아니다.

### 10.7 closeout

Contract registry, surface registry, active artifact routing과 세 registry의 JSON
Schema 검증이 모두 PASS했다. 편집 이관, 실제 FFmpeg effect matrix, legacy generation
차단, retired 01R/Terra compatibility 회귀도 PASS했다. 상세 숫자와 후속 baseline
cleanup 결과는 `idol-schema-graph-approved-execution-plan-2026-08-05.md`에 남겼다.
