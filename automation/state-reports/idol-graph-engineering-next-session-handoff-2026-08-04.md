# IDOL 그래프 엔지니어링 다음 세션 Handoff

- 기준일: 2026-08-04
- 성격: 새 Codex 채팅용 read-first 상태 요약
- gate effect: none
- canonical mutation: none
- 상세 근거: `automation/state-reports/idol-graph-engineering-and-agent-topology-audit-2026-08-04.md`
- 기존 validator call-graph 근거: `automation/state-reports/grok-harness-efficiency-audit.md`

## 1. 새 세션이 먼저 알아야 할 결론

1. 현재 IDOL 하네스의 큰 단계·권한 구조는 유지한다.
2. Branch Cut의 최상위 판정은 새 정보가 아니라 개연성이다.
3. 좋은 레퍼런스·화면 판단 기준은 이미 `idol-front-planning-director`에 대부분 존재한다.
4. 새 Judgment Card, 새 창작 schema, 새 creative validator를 만들지 않는다.
5. 기존 Decision Set 검토 순서를 `개연성 → 화면 기여 → source evidence → 비중복성 → 실행 가능성`으로 정렬한다.
6. 창작 최종 PASS에 합산 총점을 쓰지 않는다. retrieval score는 검색 순서에만 쓸 수 있다.
7. 반복 활용 이력은 Founder 취향 데이터가 맞다. 단 `source_quality`, `founder_affinity`, `current_title_fit`을 분리한다.
8. logical CDD는 영구 채팅이 아니라 파일로 지속되는 decision lineage다.
9. 실제 CDD physical session은 한 시점에 하나만 활성화한다. 필요할 때 같은 lineage의 새 session으로 순차 교체한다.
10. 짧은 reference/development worker는 비서 역할을 할 수 있지만 CDD의 PASS/REJECT 권한은 갖지 않는다.
11. reference catalog는 처음부터 EOF 정독하는 문서가 아니라 검색 가능한 pointer index로 사용한다.
12. Rhai는 현재 우선순위가 아니다.
13. pre-02A의 실제 Founder-facing 판단 Sol은 CDD이며 Overall은 startup·promotion·final acceptance 때만 깨어난다.
14. Overall, CDD와 worker는 polling하지 않고 하위 완료·HOLD·권한 요청·milestone event로만 깨어난다.
15. context 오염 감지는 넓게 하되 physical CDD rollover는 자동 실행하지 않는다.
16. 경고, 안전 checkpoint와 Founder 확인 없이 세션을 갑자기 바꾸지 않는다.
17. CDD·부서 worker 호출 양식을 미리 두는 것은 권장한다.
18. 단, 고정 창작 프롬프트가 아니라 `Studio Kernel + 선택 profile + current-run Creative Delta`를 매 호출 조립한다.
19. CDD startup profile과 Department Dispatch v3 worker profile을 분리한다.
20. 기존 skill-load profile이 부서별 required skill, output, return과 HOLD 조건의 단일 소스다.
21. worker `returned`는 creative PASS가 아니며 CDD/지정 Director의 accept/patch/reject/hold와 promotion을 거쳐야 한다.
22. 메인 메시지는 상위 축이지만 reference brief는 target reward, song cue, section role과 missing function까지 결합한다.
23. 레퍼런스 관련성은 `need → observed evidence → bounded transfer → screen consequence → section placement`로 증명한다.
24. 이 연결 규격은 새 schema/artifact가 아니라 기존 Front Planning/Decision Set 필드를 묶는 launch/review contract다.
25. governing/supporting/section-bound source는 official/original professional primary source가 기본이다.
26. AMV/MAD/fan edit는 exact current-task Founder approval 없이는 검색·열람·다운로드·분석·등록·인용·배치할 수 없다. Founder 제공도 자동 승인이 아니다.
27. Founder main reference가 있으면 `main → origin verification → genealogy + functional discovery → placement` 순서로 확장한다.
28. AMV/MAD 승인은 exact source, purpose와 allowed action에만 유효하고 direct scene binding은 별도 explicit lock을 요구한다.

## 2. CDD 세션·event routing·rollover 모델

```text
durable CDD state in files
  - lineage id
  - Founder decision epoch and locks
  - current recommendation
  - rejected reasons
  - unresolved decisions
  - exact artifact paths and hashes
  - workbench pointer
          ↕
one active physical CDD session
          ← completed, bounded Decision Sets from workers
          → reviewed checkpoint and aggregate report
          ↓ close/rollover when context grows
next physical CDD session with minimal Boot Pack
```

영구 logical CDD 채팅과 별도의 physical CDD 비서를 동시에 두지 않는다. 영구 채팅도 반환물을 누적하면서 오염되기 때문이다. 시간상 여러 session id가 존재할 수 있지만 한 순간의 CDD 판단 owner는 하나다.

주의: 현행 Director 스킬은 startup부터 02A까지 `one durable Founder-visible room`을 요구한다. 위 rollover는 아직 활성 규칙이 아니며, 다음 canonical 설계에서 durable room을 `decision/workbench lineage`로 볼지 `동일 물리 채팅`으로 볼지 명시적으로 정리해야 한다. 그 전에는 현행 단일 room 계약을 따른다.

### Event-driven wake-up

```text
Overall active
  → CDD launch + Boot Pack
  → event wait

CDD active and Founder-facing
  → bounded Luna/Max dispatch
  → event wait

worker final/HOLD/authority request
  → CDD wake and PASS/REJECT/HOLD

CDD promoted milestone/Overall authority request
  → Overall wake and promote/return
  → Overall event wait
```

Overall과 CDD는 같은 raw context를 동시에 판단하지 않는다. worker commentary를 부모에게 계속 흘리지 않고 exact aggregate manifest, survivor, rejected reason, risk, unresolved decision과 path/hash만 wake payload로 보낸다.

### 넓은 오염 감지

다음은 모두 `warning candidate`다.

- 다른 album/title/run 또는 다른 섹션의 상세 truth 혼입
- 이전 Founder epoch, 교체된 lock, rejected/HOLD 후보 또는 proposal 재활성화
- passed visual·unaffected section 재개방, owner 중복
- raw pool·전체 catalog·완료 worker chat이 active shortlist보다 커짐
- source function이 mood-only summary로 축약되거나 exact path/hash/revision을 회수하지 못함
- whole-film/section/Core/neighbor continuity와 반복 충돌
- 반복 질문, 모순된 disposition, generic/noun-swap 또는 같은 carrier 반복 증가
- 다음 exact evidence를 담기 어려운 context pressure
- 미검토 worker return, retry, Pass B와 pending owner 누적
- Boot Pack 이후 policy/schema/skill/source/canonical bytes 변경
- compaction/handoff 후 Founder wording·binding·unresolved decision 손실
- 같은 validation/dispatch/stale-pointer 오류 반복

감지되었다고 바로 이관하지 않는다.

### Founder-visible 경고 단계

1. `CDD_CONTEXT_WATCH`: 조기 경고, 현재 세션 유지
2. `CDD_ROLLOVER_RECOMMENDED`: material risk와 권고 시점 제시, 아직 이관하지 않음
3. `CDD_ROLLOVER_READY`: 안전 checkpoint 완성 후 Founder에게 `지금 이관 / 유지 / 다음 milestone로 연기` 제시
4. `CDD_CONTEXT_EMERGENCY_HOLD`: lock·identity·ownership·exact evidence를 보존할 수 없을 때 affected scope를 HOLD하고 보고; 자동 새 세션 금지

경고에는 증거, affected scope, 계속할 위험, checkpoint 상태, 이어갈 truth, 버릴 raw context, 권고 시점과 Founder 선택이 포함되어야 한다. 같은 epoch/scope의 동일 경고는 반복하지 않고 severity나 증거가 달라질 때만 갱신한다.

```text
[CDD_ROLLOVER_RECOMMENDED — 아직 이관하지 않음]
발견한 징후 / 근거 / 영향 범위
현재 작업 상태와 유지할 때의 위험
checkpoint 준비 상태
이어지는 truth / 제외되는 raw context
권고 시점과 기대 효과
Founder 선택: 지금 이관 / 현재 유지 / 다음 milestone로 연기
```

### 안전 이관 gate

- Founder lock과 decision epoch 기록 완료
- 모든 worker return이 PASS/REJECT/HOLD 또는 explicit pending
- pending lineage/session/attempt, owner와 return recipient 확정
- recommendation, rejected reasons, unresolved decisions 저장
- current paths/hashes와 workbench 동기화
- canonical merge와 paid/external action이 진행 중이지 않음
- successor Boot Pack이 raw chat 없이 truth를 재구성함
- 이전 CDD 종료 전 successor CDD 권한 활성화 금지
- Founder explicit confirmation

Founder 대화 도중, 미검토 return이 있는 상태, canonical write/merge 또는 paid/external 실행 중에는 이관하지 않는다.

### CDD Successor Boot Pack 최소 계약

현재 실제 `idol-director-boot-pack.v1`은 다음 구조를 이미 생성한다.

- current stage와 decision epoch
- active Founder locks
- open/HOLD tasks
- current canonical heads
- active board cycle
- next actions
- exact lineage checkpoint

이 v1은 실행 위치 복구에는 유효하지만 CDD creative state를 chat-free하게 복구하기에는 부족하다. current recommendation, whole-film spine, `do_not_revive` 이유, unresolved creative decisions와 active Reference Working Index view가 필수 필드가 아니기 때문이다. `harness-context-pack.v5`는 02B 한 Branch용이며 CDD 이관 팩이 아니다.

새 schema를 우선 추가하지 말고 기존 Director Boot Pack에 `cdd_successor` profile을 두는 방향을 검토한다. 최소 공통 Kernel:

1. pack/run/session/lineage identity
2. CDD authority와 Overall/Founder gate pointer
3. decision epoch와 exact Founder locks/must/avoid
4. target, song/audio, message, whole-film spine, section map의 compact projection + source path/hash
5. latest reviewed Director Development Report: recommendation, passed decisions, `do_not_revive`, unresolved decisions, risk
6. scoped Reference Working Index view와 current-title visual bindings
7. canonical heads with schema/revision/hash
8. open/HOLD/pending dispatch owner and attempt state
9. active workbench cycle, pending Founder decisions, next/stop/wake conditions
10. source-set/pack/checkpoint digest, required contract revisions와 exclusions

Script는 creative summary를 작성하지 않는다. CDD/Overall이 이미 작성·검토한 report와 canonical projection을 exact-copy/pointer projection한다.

Stage-specific evidence는 Song, Reference, FP/01, 02A, Member Visual exception module 중 next scope 하나만 추가한다. full chat, 전체 catalog, raw/rejected pools, unrelated section, historical prose, full contact sheet와 media bytes는 제외한다. 탈락 후보는 media가 아니라 id + one-line reason + evidence pointer만 남긴다.

진단상 context allocation target은 common kernel/startup reads 약 25%, next-scope exact evidence 최소 50%, 새 판단/출력 여유 최소 25%다. ceiling을 맞추려고 lock·selected evidence·unresolved decision을 삭제하지 않고 optional module을 pointer/phase-load로 내린다.

Successor는 pack만으로 `scope / locks / recommendation / do-not-revive / unresolved / heads-and-owners / next-stop-wake` 일곱 항목을 복원해야 한다. 하나라도 실패하면 이관하지 않는다. read-only preflight는 가능하지만 이전 CDD가 checkpoint를 닫고 owner lease를 반납하기 전 creative/write authority를 받지 않는다.

## 3. CDD·부서 worker Compiled Launch Prompt

### 결론

Founder가 매번 상세 명령을 반복하지 않도록 호출 양식, 스킬 라우팅, 완료·HOLD 조건과 반환 형식을 미리 정의하는 것은 현재 하네스에 적합하다. 이미 다음 truth가 존재하므로 새 creative schema나 총점 validator는 만들지 않는다.

- Department Dispatch v3: exact task/scope, Founder locks, skill/source hash, permission, authority, output, HOLD, return, review와 promotion
- `harness-skill-load-profiles.yaml`: 18개 profile의 required skill/read, output contract, return route와 부서별 HOLD 조건
- `.codex/agents`: Overall, CDD, Luna worker와 post-02A section role kernel
- 각 `SKILL.md`: 실제 부서별 창작 방법과 판단 기준

현재 빈틈은 이 네 층을 실제 호출문으로 중복 없이 조립하는 derived launch view다.

```text
Studio Kernel
  + CDD 또는 Department Profile
  + current-run Creative Delta
  = one task / one session Launch Prompt
```

### CDD와 worker 분리

- **CDD launch**: Overall이 CDD role/authority와 startup 또는 successor Director Boot Pack을 전달한다. 한 active physical CDD만 pre-02A 판단과 Founder 대화를 소유한다.
- **Department worker launch**: CDD/지정 Director가 Department Dispatch v3와 정확히 한 skill-load profile을 선택한다. worker는 bounded evidence/output만 반환하고 PASS/REJECT·promotion 권한은 갖지 않는다.

CDD를 일반 worker contract에 억지로 넣거나 worker에게 CDD 권한을 주지 않는다.

### 호출문 최소 block

1. dispatch identity: run/lineage/session/attempt/task/profile/recipient
2. role and authority: may-decide, must-not, canonical/external permission
3. current creative job: Founder verbatim message와 explicit locks, target reward, song/audio cue, whole-film/section role, current gap
4. exact scope/non-scope와 output ownership
5. input path/hash/purpose pointers
6. required skill/read revision/hash와 phase-load 순서
7. 이번 부서가 풀 concrete creative question
8. exact output kind/path/count/manifest
9. department-specific quality proof
10. return-ready conditions
11. HOLD/stop/split conditions와 next smallest action
12. recipient와 final/HOLD/authority/milestone wake route

고정되는 것은 순서·권한·무결성이다. current creative job과 실제 판단 기준 적용은 CDD/Overall이 저작한다. deterministic compiler는 기존 contract, profile, path/hash와 이미 승인된 creative projection을 exact-copy할 수 있지만 메시지 해석, 검색 방향, 장면, generic placeholder 또는 creative PASS를 만들 수 없다.

### 메시지 기반 reference routing

메시지만 검색어로 바꾸지 않는다.

```text
message × target reward × selected-song cue × section/content role
        × missing reference function × must/avoid/current-title identity
```

이 교차점에서 integrated reference, image-only World/Still, video source registration, member identity 또는 FP/01/02A development profile을 선택한다. Founder의 일반 입력은 proposal/high-priority input이고 명시적으로 고정한 것만 lock이다.

### Reference Connection Minimum Contract

기존 `source_lineages.connection_reason`, Front Planning `reference_units`, `function_analysis`, `section_plan`, worker의 source-to-screen delta와 weaker-neighbor reason을 재사용한다. 각 survivor는 다음을 연결해야 한다.

1. current need: message progression, target response, audio cue, section role, missing function
2. observed evidence: exact source/locator/path/hash에서 실제로 본 것
3. selected component: source에서 가져올 정확한 화면 요소
4. transfer boundary: current member/song/world로 바꾸는 방식과 preserve/discard/do-not-transfer
5. placement: target section/sequence와 downstream screen job
6. role: 기존 source kind/function/combination role로 governing/supporting/lineage/gap-challenge 설명
7. comparative necessity: weaker neighbor보다 필요한 이유, 중복되지 않는 기여, mismatch risk와 빠질 때 잃는 정보

```text
current need
  → observed source evidence
    → bounded transfer
      → observable screen consequence
        → exact section placement
```

표면이나 mood만 비슷하면 통과하지 않는다. 장르·외형이 달라도 이 연결이 강하면 기능적으로 관련 있는 좋은 후보가 될 수 있다. Pass A는 뜻밖의 source를 찾을 여지를 두되 survivor가 될 때 이 연결을 증명한다. Pass B는 broad related search가 아니라 정확한 missing function/continuity risk/governing weakness만 검색한다. 총점은 쓰지 않는다.

### Official/Original-First와 원천 → 발굴

현행에는 official MV 계열이 기본이라는 문구와 함께 AMV/MAD/edit의 response-pattern 사용도 허용되어 있어 경계가 약하다. 다음 canonical 정렬에서는 아래를 기본으로 한다.

선택 가능 우선 source:

- official MV, visual film, concept film, teaser/trailer/highlight film
- official performance/dance/choreography source는 현재 body/blocking 기능이 있을 때
- official brand/fashion/editorial/director·production-company film
- 영화·시리즈·애니메이션·게임의 official scene/trailer/cinematic
- official concept photo, key visual, promo/press/editorial still과 verified creator original

기본 선택 불가 source:

- AMV, MAD, fan edit/trailer, unofficial music edit
- reaction, compilation, top-scenes montage와 clip collection
- 출처 불명 reupload, AI upscale/interpolation/re-edit
- 원본이 해결되지 않은 Pinterest/SNS/blog repost와 fan moodboard

AMV/MAD/fan edit는 Founder-explicit-approval-only source다. exact current-task source와 목적을 승인받지 않았다면 agent가 자율적으로 검색, query 포함, 결과 열기, 다운로드/capture, playback/pixel inspection, 분석, 등록, 인용, response-pattern 사용 또는 배치를 해서는 안 된다. 검색 결과에 나타나면 열지 않고 official/original route를 계속한다. Founder가 링크나 파일을 제공한 사실만으로 사용 승인을 추론하지 않는다.

승인 시에도 exact source, purpose와 allowed action만 허용한다. `편집 리듬 분석` 승인은 visual scene binding을 허용하지 않는다. 장면·캐릭터·세계 근거는 official original에서 재검증하고 direct scene binding은 별도 explicit lock이 필요하다. 미승인 AMV/MAD가 필수 source라면 `founder_permission_missing` HOLD다.

그 외 Pinterest/SNS/blog repost, compilation metadata와 fan moodboard는 navigation surface로만 original 후보를 찾을 수 있다. survivor에는 official/original unit을 넣고 원천을 찾지 못하면 `unresolved_origin` HOLD한다.

Founder main reference가 있을 때:

```text
main reference 보존
→ official/original/repost/AMV surface 분류
→ 원천·공식본·creator/production lineage 확인
→ selected component와 기능 분해
→ official genealogy discovery + official functional discovery
→ governing/supporting/challenge 비교
→ section placement와 source-to-screen delta
```

Founder main reference가 없을 때:

```text
current need/function
→ official source-family discovery
→ origin verification
→ connection comparison
→ section placement
```

Genealogy relation과 기능 analogue를 분리하고, documented evidence가 없으면 influence라고 부르지 않는다. `공식 우선`은 K-pop MV만 보라는 뜻이 아니라 원본성·출처·관찰 가능성을 우선한다는 뜻이다.

### 완료·실패 의미

- `returned`: output/evidence/hash가 돌아온 상태이며 creative PASS가 아니다.
- `director_review.accept/patch/reject/hold`: CDD/지정 Director의 증거 기반 판단이다.
- `promoted`: promotion owner가 검토한 exact bytes만 승격한 상태다.
- `split_required`: 과대·중첩 scope를 발견했을 때 exact unowned subscopes와 risk를 반환하는 신호다. 별도 lifecycle을 늘리기보다 기존 return/HOLD에서 recipient가 sibling dispatch 여부를 정한다.

Schema PASS만으로 return-ready가 되지 않는다. required read 실제 적용, exact media/source evidence, 부서별 비교/observable proof, message/audio/section 연결, output inventory/hash, survivor와 weaker/rejected reason이 있어야 한다. input·permission·evidence가 빠지면 candidate를 채우지 말고 HOLD한다.

### 금지 구현

- 전체 AGENTS/정책/catalog/다른 부서 산출물을 모든 worker에 붙이기
- skill 전문을 prompt에 복제해 두 개의 truth 만들기
- 메시지 명사만 바꾸는 고정 검색어·장면·카메라 default
- script의 creative field 자동 작성 또는 schema PASS의 creative PASS 승격
- raw pool 수나 후보 수 채우기를 성공 조건으로 삼기
- Founder 일반 대화를 자동 lock으로 승격하기
- worker full chat과 탈락 pool을 CDD에 누적하기

이렇게 구현하면 품질과 토큰 효율이 모두 나빠지므로 도입하지 않는다.

### Pilot 판정

한 section의 `Reference Research → CDD review → FP/01/02A`에서 Founder 추가 설명 횟수, input/output words, retry/HOLD 시점, CDD survivor와 02A 생존 수, generic/continuity 실패와 CDD evidence 재요청 수를 비교한다. 개선이 없으면 field를 더 늘리지 말고 중복 prompt prose를 제거한다.

## 4. Reference retrieval 모델

### 현행 의도

`wiki/reference-management-system.md`는 이미 catalog를 source identity, search term, purpose class로 검색하고 exact pointer를 따라가도록 지시한다.

### 현행 충돌

`skills/idol-front-planning-director/SKILL.md`와 일부 worker load profile은 37,570-word `catalog/references/reference-catalog.yaml` 전체 EOF를 요구한다. 검색형 설계와 실제 load contract가 충돌한다.

### 목표

```text
broad catalog query
  → pointer-only shortlist
  → bounded worker exact-source analysis/pixel inspection
  → source id + locator + path/hash + observed facts + mismatch + disposition
  → CDD Decision Set comparison
```

정본 YAML은 유지할 수 있다. 별도의 derived retrieval index 또는 작은 query command는 deterministic lookup만 담당하고 creative truth를 쓰지 않는다.

## 5. Director 판단 모델

### 개연성 hard gate

모든 Major/Core/Branch는 다음 연결을 설명해야 한다.

```text
whole-film spine
  → section job and audio cue
    → parent Core event/state
      → Branch contribution
        → neighboring event continuity
```

개연성은 사실주의만 의미하지 않는다. 비선형·초현실 MV도 감정, 공간 규칙, 오브젝트 상태, 음악적 압력 또는 편집 기대를 이어야 한다.

### 총점 금지 이유

개연성, source evidence, Founder lock, identity/safety와 비중복성은 다른 장점으로 보상할 수 없다. `개연성 0 + 미장센 10`을 평균내는 총점은 creative PASS를 왜곡한다. hard gate 후 pairwise comparison과 `strong / viable / weak` 진단만 사용한다.

### 기존 스킬에서 재사용할 판단 근거

- exact selected media
- source-to-screen delta
- three current-work dependencies
- observable before/trigger/after state
- Major/Core/neighbor distinction
- transformed recurrence
- whole-film consequence
- rejected collisions
- strongest executable invariant
- concrete risk

새 artifact를 만들지 말고 기존 Decision Set과 Director Development Report 형식 안에 정렬한다.

## 6. CDD 입력 크기 snapshot

2026-08-04 재검토 시점:

| 선언/작업 | 대략적 words |
|---|---:|
| execution-contract 요약 CDD pack | 32,848 |
| skill-load-profile CDD startup | 40,854 |
| CDD skill Required Reads 기본 | 78,848 |
| 일반 reference 연결 | 82,538 |
| 일반 Founder board 저작 | 90,464 |
| member/styling 예제 포함 | 94,365 |

worktree가 계속 수정 중이므로 다음 세션에서 재산출한다. 전체 catalog EOF 제거 전에는 pointer-only 구조가 실효화되지 않은 것으로 판단한다.

## 7. 스키마·검사기 snapshot

| 표면 | 수 | 줄 | 단어 | bytes |
|---|---:|---:|---:|---:|
| schemas | 116 | 44,512 | 101,209 | 1,500,488 |
| 전용 validate/check/audit scripts, tests 제외 | 51 | 23,192 | 83,618 | 1,010,236 |

- 언어: Ruby 39, Python 12
- active contract registry: 93 schemas
- inactive/auxiliary: 23 schemas
- active stage output contracts: 22
- active script-referenced schemas: 78
- 반복 구현 진단: loaders 22, path resolution 26, SHA checks 33, schema-helper callers 27, subprocess callers 34
- 두 번째로 큰 전용 validator `validate_video_prompt_index.rb` 2,571 lines는 inactive historical

판단: per-run 검증 routing은 scoped frontier를 기본으로 하므로 모든 116 schema/51 validator가 매번 실행되는 것은 아니다. 그러나 유지보수 표면과 공통 코드 중복은 크다.

## 8. 현재 read-only 검사 결과

| 검사 | 상태 |
|---|---|
| active stage registry: 5 phases, 19 stages | PASS |
| artifact routing: 19 stages | PASS |
| contract registry: 93 routes | PASS |
| surface registry: 373 surfaces, 36 skills | PASS |
| skill-load profiles: 18/18/39 | PASS |
| instruction surface audit | PASS with size warnings |
| 34 skill contracts | PASS |
| model routing | PASS |
| reference catalog | PASS |
| scripts registry | FAIL: 5 unmentioned files |

Script registry 미기재:

- `scripts/lib/idol_api_video_quality.py`
- `scripts/lib/idol_social_taxonomy.rb`
- `scripts/validate_final_delivery_manifest.py`
- `scripts/validate_founder_sequence_control.rb`
- `scripts/validate_terra_section_lifecycle_receipt.rb`

## 9. Worktree 경계

- branch: `main`
- snapshot status lines: 1,660
- modified: 213
- deleted: 900
- untracked: 547

Founder가 동시에 구조를 수정 중이다. 다음 세션은 모든 drift를 결함으로 단정하거나 자동 수리하지 않는다. 현재 bytes와 registry를 다시 검증하고, 이 문서 이후 변경된 사항을 먼저 분리한다. 기존 사용자 변경을 되돌리거나 삭제하지 않는다.

## 10. 다음 세션의 권고 작업 순서

### P0 — 문서/계약 설계 확정

1. CDD startup pack, effective Required Reads, worker load profile의 중복과 충돌을 표로 확정한다.
2. 전체 catalog EOF를 제거하고 query → shortlist → exact-source worker 경로로 바꾸는 최소 canonical patch를 설계한다.
3. Overall/CDD/worker의 event-driven sleep/wake와 compact wake payload를 기존 dispatch return route로 표현 가능한지 확인한다.
4. broad warning detector, alert deduplication, safe checkpoint, explicit Founder confirmation과 no-rollover zones를 먼저 설계한다.
5. CDD physical session rollover의 checkpoint fields와 handoff stop condition을 기존 dispatch/index schema 안에서 재사용 가능한지 확인한다.
6. 기존 Director skill의 판단 순서만 정렬하고 새 schema/validator가 필요 없는지 최종 확인한다.
7. 기존 role/profile/dispatch/Boot Pack을 조립하는 Compiled Launch Prompt의 12-block derived view를 설계한다.
8. CDD launch와 department worker launch를 분리하고, worker `returned`와 creative review/promotion 경계를 유지한다.
9. 부서별 prompt 전문을 새로 만들지 않고 skill-load profile을 single source로 재사용하는지 확인한다.
10. Reference Connection Minimum Contract를 기존 source lineage/reference unit/function analysis/section plan에 exact projection하고 새 schema를 만들지 않는다.
11. official-original-first source policy를 기존 allowed reference types와 research skills에 정렬하고 AMV/MAD/fan edit를 Founder-explicit-approval-only로 바꾸며 historical rows의 active reuse를 막는다.
12. Founder main-reference origin-first route와 no-main-reference function-first route를 launch profile에 분리한다.

### P1 — validator 감량 설계

1. 51개 validator를 active / auxiliary / historical로 분류한다.
2. pure duplicate call과 반드시 유지할 trust-boundary repetition을 나눈다.
3. Ruby/Python별 common validated-load, path/hash binding, error core 후보를 잡는다.
4. broad state check와 ordinary frontier의 호출 그래프를 분리한다.
5. 파일 삭제·병합·대규모 분할은 Founder의 별도 명시 승인 전에는 하지 않는다.

### P2 — 한 section pilot

Reference Research → pointer shortlist → Decision Set → CDD review → FP → 01 → 02A를 실제 한 section으로 통과시킨다. 다음을 측정한다.

- CDD startup words
- worker별 input/output words
- shortlist와 최종 survivor 수
- Pass B 재호출 수
- physical CDD rollover 시점
- Founder 수정 수
- 02A까지 살아남은 reference와 scene 이유

## 11. 새 세션 시작 지시

새 세션은 이 handoff와 상세 감사 문서를 먼저 읽고, 바로 canonical edit를 시작하지 않는다. live validator와 CDD load paths를 재확인한 뒤 Founder에게 다음 중 무엇을 먼저 변경할지 제안한다.

1. CDD catalog retrieval/load boundary
2. event-driven Overall/CDD/worker routing
3. context warning + Founder-confirmed physical CDD rollover contract
4. validator active/auxiliary/historical routing
5. 한-section pilot instrumentation
6. CDD·worker Compiled Launch Prompt derived view
