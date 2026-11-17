# IDOL 최초 시작 프롬프트·스킬 버전 관리 개선안

- 작성일: 2026-08-06 (Asia/Seoul)
- 상태: 완료 — Phase 1–4 구현·분리 스냅샷 회귀 PASS, Phase 5 격리 더미 pilot 및 최종 회귀 PASS
- 시행 조건: 진행 중인 레퍼런스 관련 수정이 종료되고, 아래 대상 파일의 현재
  소유권과 SHA-256을 다시 확인한 뒤 별도 실행
- gate effect: none
- canonical creative mutation: none
- active run write: none
- paid/external action: none

## 0. 2026-08-06 시행 현황

- 기존 `Founder start authorization -> Overall/CDD warm-open -> Overall 판단
  -> CDD/worker -> director review/promotion` 순서와 권한을 유지했다.
- Startup Admission은 기존 세션 route 안의 첫 Overall model turn 직전에만
  들어가며, 새 stage·Founder gate·창작 owner를 만들지 않는다.
- Overall Read Gate와 두 번째 12블록 launch는 같은 물리 Overall 세션을
  사용한다. CDD는 Overall의 typed route 뒤에만 시작하고, CDD EOF return 전에는
  기존 worker control을 막는다.
- 선택적 clean snapshot에서 profile stale binding 0, contract/schema 누락 0,
  surface SHA 누락 0을 확인했고 Department Dispatch, Workbench, native host와
  instruction/current-next 회귀가 통과했다.
- 캔버스의 admission lifecycle row는 감사 projection일 뿐이다. Workbench를 새로
  열거나 materially resume하면 이전 row를 권한으로 재사용하지 않고 현재 profile과
  SHA를 다시 확인한다.
- Founder의 2026-08-06 현재 지시에 따라 Phase 5는 SU나 다른 실제 런을 사용하지
  않는다. 임시 run binding에서 `Overall -> CDD -> bounded worker 1명 -> CDD review
  -> Overall promotion`을 닫는 격리 더미 pilot을 이번 개선의 수용 증거로 사용한다.
  이는 startup/version-management 하네스의 수용 증거이며 실제 창작 결과의 PASS나
  특정 production run의 진행 증거로 확대하지 않는다.

## 1. 목적

Founder가 매번 다음과 같은 일반 지시를 반복하지 않아도 되게 한다.

> 관련 문서와 스킬을 꼼꼼히 끝까지 읽고 실제 결과에 적용하라.

Founder는 앞으로도 제작 시작 또는 재개 의사와 이번 창작 방향은 직접 말한다.
그러나 역할별 작업법, 필수 읽기, 적용 증거, 출력 형식, HOLD 조건과 반환 경로는
하네스가 같은 방식으로 준비하고 검증해야 한다.

목표 동작은 다음과 같다.

```text
Founder의 짧은 시작·재개 지시
-> 현재 런과 다음 합법 단계 확인
-> 역할별 등록 프로필과 필수 읽기 자동 선택
-> 최신 path / revision / SHA-256 검증
-> 최초 감독 Read Gate
-> Overall Director가 현재 증거를 읽고 Current Assignment Delta 작성
-> 같은 세션에 12블록 Compiled Launch Prompt 자동 전달
-> CDD와 각 작업자는 자신의 등록 Recipe와 필수 문서를 EOF까지 읽고 작업
-> 반환 bytes와 근거를 감독이 검토
-> 검토된 결과만 승격 또는 HOLD
```

일관성의 의미는 매번 같은 문장을 생성하는 것이 아니다. 같은 역할, 입력,
필수 읽기, 판단 경계, 근거 요구, 검토와 승격 절차를 적용하는 것이다. 창작 결과의
차이는 현재 곡·타깃·레퍼런스·Founder 방향에서 나와야 하며, 시작 프롬프트 누락이나
서로 다른 읽기 범위에서 나오면 안 된다.

## 2. 현재 확인된 상태

### 이미 존재하는 기반

현재 하네스에는 다음 기반이 있다.

1. `provider-neutral-studio-kernel.md`가 하나의 시작 명령을 다음 세 층으로
   정의한다.
   - Registered Department Recipe
   - Director-authored Current Assignment Delta
   - Mechanical Dispatch Envelope
2. 모든 정식 Compiled Launch Prompt는 고정된 12개 H2 블록을 사용한다.
3. `automation/harness-skill-load-profiles.yaml`이 역할·checkpoint별 owning skill과
   linked read를 path, revision, SHA-256, EOF 조건으로 등록한다.
4. `schemas/department-dispatch.schema.json`과
   `scripts/validate_department_dispatch.rb`가 프로필, 읽기 목록, 해시, 입력·결과
   digest, 출력, 감독 검토와 승격 경계를 검사한다.
5. Workbench는 이미 준비된 worker Dispatch의 rendered prompt 해시를 확인하고
   그 exact bytes를 작업자에게 전달할 수 있다.

현재 등록 기준으로 Overall Director 시작은 `idol-orchestrator`와 필수 읽기 10개,
CDD 시작은 `idol-front-planning-director`와 필수 읽기 18개를 요구한다. 다른 역할은
현재 checkpoint에 필요한 범위만 읽는다. 전체 저장소를 무차별로 읽게 하지 않고,
현재 작업에 필요한 정확한 문서를 EOF까지 읽게 하는 방향은 유지한다.

### 현재 남은 문제

이 문서를 작성하기 직전의 checkout에서는 다음 문제가 확인됐다. 아래 숫자와 파일
상태는 레퍼런스 작업 종료 후 반드시 다시 측정하며, 시행 시점의 canonical truth로
간주하지 않는다.

1. Workbench의 최초 Overall Director 턴은 간결한 역할 지침, 현재 런 snapshot,
   Founder 메시지를 받는다. 정식 12블록 Compiled Launch Prompt의 exact-byte 전달은
   주로 department worker 경로에서 닫혀 있다.
2. 별도 CDD는 warm-open되지만 자동으로 model turn을 시작하지 않는다. 이는 올바른
   권한 경계지만, 최초 CDD 턴에 등록 프로필 전체가 자동으로 입장 검증되는 증거는
   아직 부족하다.
3. `harness-skill-load-profiles.yaml` 검증에서 16개 binding SHA-256이 현재 파일과
   달랐다. Department Dispatch 검증 테스트는 33개 중 6개가 이 stale binding 때문에
   실패했다. 현재 strict route는 실행보다 HOLD가 맞다.
4. Workbench의 root-v3 structural/dummy smoke는 통과했지만, 실제 제작 런의
   `runs/**/work/department-dispatches/*.yaml`에서 최초 감독부터 worker 반환·검토까지
   닫힌 실사용 증거는 확인되지 않았다.
5. validator와 Workbench delivery는 존재하지만, 최초 Overall/CDD 입장을 위해
   현재 증거를 읽히고 12블록 명령까지 자동 연결하는 하나의 production compiler
   경로는 완결되지 않았다.

## 3. 설계 결정

### 3.1 무작정 하나의 고정 프롬프트를 재사용하지 않는다

다음 세 값은 분리한다.

| 구분 | canonical owner | 성격 |
| --- | --- | --- |
| 반복 작업법 | owning `SKILL.md` + linked reads + skill-load profile | 안정적 Recipe |
| 현재 창작 판단 | assigning Director | 매 시도 새로 작성하는 Delta |
| ids·scope·hash·permission·return | Dispatch Envelope | deterministic exact-copy |

고정 프롬프트에 과거 장면, 예시 문구, 레퍼런스 결론이나 현재 창작 값을 넣지 않는다.
모델이 달라져도 Recipe와 권한은 유지하고, provider/model은 runtime metadata로만
전달한다.

### 3.2 최초 Overall에는 2단계 Startup Admission을 사용한다

최초 Overall Director 앞에는 Current Assignment Delta를 작성할 상위 Director가
없다. 이 공백을 스크립트의 창작 요약으로 채우지 않는다. 다음 두 단계를 같은
세션에서, 추가 Founder 입력 없이 진행한다.

#### A. Startup Read Gate

기계적으로 다음만 묶는다.

- Founder의 시작·재개 문장 verbatim
- exact run / manifest / decision epoch / active owner pointer
- `overall_director.director_startup` profile id와 checkpoint id
- profile registry path와 SHA-256
- owning skill과 모든 required read의 current path / revision / SHA-256
- 외부·유료·공개 작업 기본 금지
- 누락·stale·충돌 시 HOLD

이 단계는 창작 방향을 요약하거나 보완하지 않는다. Overall은 지정된 자료를 EOF까지
읽고 다음을 반환한다.

- 현재 런·단계·잠금 요약
- 이번에 해결할 정확한 현재 과제
- 보존할 unaffected truth
- 필요한 CDD 또는 다음 owner route
- 현재-work quality proof 요구
- unresolved decision과 HOLD

이 반환이 Overall-authored Current Assignment Delta가 된다.

#### B. Compiled Director Launch

검증된 Startup Read Gate, 등록 Recipe, Overall-authored Delta와 Mechanical Envelope를
결합해 기존 12블록 명령을 만든다. 조립기는 고정 heading과 exact-copy 값만 추가하며
Delta를 쓰거나 의역하지 않는다. 같은 물리 Overall 세션에 자동 전달하므로 Founder가
두 번째 프롬프트를 입력하지 않는다.

CDD 시작은 Overall이 작성한 Delta를 사용해 기존 12블록 경로로 연다. 이후 Song,
reference, identity, pre-02A development, post-02A section과 Edit 작업도 동일한 Recipe +
Delta + Envelope 원칙을 사용한다.

### 3.3 casual discussion과 production start를 구분한다

다음 입력만 Startup Admission을 연다.

- Founder가 현재 런의 `시작`, `계속`, `재개`, `진행`을 명시한 경우
- 또는 run manifest에 정확한 current-run route authorization이 존재하는 경우

하네스 설명, 아이디어 대화, 질문, 상태 확인만으로 CDD나 작업자를 자동 생성하지
않는다. 시작 권한은 여전히 Founder가 주지만, 읽기·적용 방법을 Founder에게 다시
쓰게 하지 않는다.

### 3.4 실제 적용은 선언이 아니라 결과로 검토한다

기계 검증은 다음을 확인한다.

- 선택 profile/checkpoint가 등록돼 있는지
- owning skill과 linked read가 정확히 일치하는지
- 모든 SHA-256이 현재 bytes와 일치하는지
- EOF 읽기 기록, input digest와 result digest가 일치하는지
- 정해진 12블록이 한 번씩 올바른 순서로 존재하는지
- placeholder, stale source, 잘못된 owner와 scope가 없는지

그러나 기계는 의미 적용을 승인하지 않는다. recipient Director가 반환 결과에서 다음을
검토한다.

- Recipe가 요구한 비교·관찰·번역·검토 방식이 실제 output에 나타나는가
- Current Assignment Delta의 named gap을 해결했는가
- Founder lock과 unaffected truth를 보존했는가
- source-to-screen, song-to-screen 또는 pixel/playback 근거가 구체적인가
- generic confidence나 self-assertion만 남지 않았는가

## 4. 문서와 버전의 단일 소스 지도

같은 규칙을 여러 파일에 복제하지 않는다. 다음 owner 지도를 유지한다.

| 관리 대상 | canonical owner | consumer / projection |
| --- | --- | --- |
| 역할·승격·Founder 권한 | `AGENTS.md` | policies, skills, Workbench |
| model/session/start routing | `policies/harness-routing-and-sources.md` | orchestrator, execution contract, Workbench |
| 전체 제작 경로의 compact 설명 | `wiki/production-system.md` | 사람용 진입 문서 |
| 12블록과 Recipe/Delta/Envelope 규칙 | `skills/idol-orchestrator/references/provider-neutral-studio-kernel.md` | 모든 director/worker launch |
| 시작·재개 절차 | `skills/idol-orchestrator/SKILL.md` | Overall runtime |
| 역할·checkpoint별 exact read set | `automation/harness-skill-load-profiles.yaml` | Dispatch compiler와 validator |
| runtime/admission/derivation 계약 | `automation/harness-execution-contract.yaml` | schema, Workbench adapter |
| Dispatch bytes와 lifecycle shape | `schemas/department-dispatch.schema.json` | validator, Workbench |
| Workbench provider route | `development/front-planning-workbench/contracts/model-routing.json` | native adapter |
| provider transport 구현 | `development/front-planning-workbench/ui/native-agents.js` | exact prompt delivery |
| structural/hash 검증 | `scripts/validate_department_dispatch.rb`와 `scripts/validate_harness_skill_load_profiles.rb` | tests, CI/local verification |
| authoring contract version | `automation/harness-contract-version-registry.yaml` | contract validator |
| tracked surface revision/SHA | `automation/harness-surface-version-registry.yaml` | surface validator |

Workbench JavaScript에는 전체 Recipe나 creative rule을 다시 쓰지 않는다. canonical
profile id, checkpoint id, registry hash와 transport-only instruction만 소비하게 한다.
사람용 문서는 canonical owner를 링크하고 compact flow만 설명한다.

## 5. 스킬 버전과 문서 동기화 규칙

### 5.1 변경 단위

다음 변경은 하나의 atomic patch로 취급한다.

```text
owner instruction / skill / schema 변경
-> owning authoring version 결정
-> dependent profile binding revision / SHA 갱신
-> producer / consumer / validator 갱신
-> harness contract-version registry 갱신
-> harness surface-version registry revision / SHA 갱신
-> focused tests와 전체 closure validation
```

한 파일만 먼저 바꾸고 stale hash를 나중에 고치지 않는다. stale binding은 자동 수선
대상이 아니라 HOLD다.

### 5.2 변경 유형별 처리

| 변경 | 필요한 조치 |
| --- | --- |
| owning skill의 작업 방법 변경 | skill authoring revision, profile binding SHA, surface registry, 관련 tests 갱신 |
| linked read 내용 변경 | 해당 read SHA와 이를 소비하는 모든 checkpoint closure 갱신 |
| profile의 required read 추가·삭제 | profile 계약 변경, validator와 fixture, contract/surface registry 갱신 |
| 12블록 의미·소유권 변경 | Studio Kernel, execution contract, schema/validator, adapter와 registries 동시 갱신 |
| provider/model만 변경 | creative contract는 유지하고 model-routing/adapter/runtime metadata와 해당 surface version만 갱신 |
| 오탈자라도 tracked instruction bytes 변경 | 현재 규칙에 따라 surface revision/SHA를 같은 patch에서 갱신 |

### 5.3 갱신 순서

1. 변경 시작 전 exact target file 목록과 baseline SHA-256을 기록한다.
2. canonical owner부터 수정한다.
3. schema와 validator를 맞춘다.
4. profile registry의 exact read closure를 갱신한다.
5. Workbench와 provider adapter를 canonical 계약에 맞춘다.
6. contract-version registry를 갱신한다.
7. surface-version registry revision/SHA를 마지막 authoring bytes 기준으로 갱신한다.
8. stale binding 0을 확인한다.
9. targeted tests와 전체 instruction/contract/surface closure를 실행한다.
10. 격리 더미 pilot 전주기가 닫히기 전까지 이번 startup/version-management 개선의
    acceptance를 주장하지 않는다.

## 6. 시행 단계

### Phase 0 — 충돌·기준선 Gate

레퍼런스 작업 완료 선언 후 다음을 먼저 수행한다.

- 현재 branch와 worktree를 다시 확인한다.
- 아래 계획 대상 파일의 staged/unstaged/untracked 변경과 active owner를 확인한다.
- reference-related skill, policy, registry 또는 Workbench 변경이 하나라도 진행 중이면
  즉시 중단한다.
- 이전 감사 숫자를 믿지 않고 profile/contract/surface validator를 다시 실행한다.
- 현재 stale binding 목록과 failing tests를 새 기준선으로 기록한다.

Phase 0은 파일을 고치지 않는다.

### Phase 1 — Version Closure 복구

- 모든 owner 파일의 최종 현재 bytes를 확정한다.
- `harness-skill-load-profiles.yaml`의 path/revision/SHA를 현재 bytes와 맞춘다.
- contract/surface registries를 같은 patch에서 갱신한다.
- stale skill binding 0, stale linked read 0을 만든다.
- 기존 Dispatch 테스트가 creative 규칙 완화 없이 통과하는지 확인한다.

이 단계에서는 시작 프롬프트 기능을 아직 바꾸지 않는다. 현재 계약 기준선을 먼저
PASS로 만든다.

### Phase 2 — Overall Startup Read Gate

- execution contract에 provider-neutral Overall startup admission을 명시한다.
- Workbench가 `overall_director.director_startup` profile/checkpoint와 최신 registry
  hash를 선택하도록 한다.
- 최초 Founder 메시지와 current run pointer를 exact-copy한다.
- required skill/read closure가 맞지 않으면 model turn 전에 HOLD한다.
- Overall이 EOF 읽기 후 Current Assignment Delta를 반환하는 contract를 추가한다.
- script나 Workbench가 Delta를 요약·보완하지 못하게 한다.

### Phase 3 — 12블록 Director Launch와 CDD 연결

- 검증된 Overall Delta를 기존 Studio Kernel의 12블록 명령으로 조립한다.
- exact rendered bytes와 compiled-input/rendered-prompt SHA를 같은 세션에 전달한다.
- CDD startup도 `creative_development_director.cdd_startup` profile로 동일하게 닫는다.
- CDD가 반환하기 전 Song/reference/identity/development worker launch를 막는다.
- worker 경로는 기존 Department Dispatch v3의 owner/review/promotion 경계를 유지한다.

### Phase 4 — Resume와 checkpoint 일관성

- 같은 물리 세션의 legal next checkpoint는 Founder가 정착된 입력을 다시 말하지
  않아도 새 immutable attempt로 진행한다.
- 새 checkpoint의 exact reads, hashes, activation condition과 input digest를 갱신한다.
- owner/scope가 바뀌거나 Founder/stage/paid/pixel/playback gate를 건너뛰면 HOLD한다.
- CDD physical successor는 기존 Boot Pack과 Founder confirmation 규칙을 유지한다.

### Phase 5 — 격리 더미 Pilot

Founder의 현재 지시에 따라 SU와 실제 제작 런은 건드리지 않고, 임시 fixture에서 다음
한 사이클만 검증한다.

```text
Founder의 짧은 시작 지시
-> Overall Startup Read Gate
-> Overall-authored Delta
-> CDD Compiled Launch Prompt
-> bounded worker 한 개
-> returned bytes
-> CDD review
-> Overall promotion 또는 HOLD
```

외부 검색, 다운로드, 이미지 생성, 유료 작업과 공개 작업은 이 pilot의 기본 범위가
아니다. 더미 pilot은 모두 `closed_local`로 고정하며, 실제 창작값이나 active run bytes를
쓰지 않는다. 실제 런 검증은 이후 Founder가 별도로 요청할 때만 새 범위로 연다.

## 7. 계획된 변경 표면

시행 시점에 다시 감사한 뒤 최소 owner만 확정한다. 현재 예상 표면은 다음과 같다.

### canonical instruction / contract

- `AGENTS.md` — startup invariant가 정말 최상위 규칙이 될 때만 최소 변경
- `policies/harness-routing-and-sources.md`
- `wiki/production-system.md`
- `skills/idol-orchestrator/SKILL.md`
- `skills/idol-orchestrator/references/provider-neutral-studio-kernel.md`
- `automation/harness-execution-contract.yaml`
- `automation/harness-skill-load-profiles.yaml`

### schema / adapter / validator

- `schemas/harness-execution-contract.schema.json`
- `schemas/department-dispatch.schema.json` — 기존 lifecycle 확장이 필요한 경우만
- `development/front-planning-workbench/contracts/model-routing.json`
- `development/front-planning-workbench/contracts/model-routing.schema.json`
- `development/front-planning-workbench/ui/native-agents.js`
- `development/front-planning-workbench/tools/workbench.py`
- `scripts/validate_department_dispatch.rb`
- `scripts/validate_harness_skill_load_profiles.rb`

### version registries / tests

- `automation/harness-contract-version-registry.yaml`
- `automation/harness-surface-version-registry.yaml`
- `automation/instruction-surface-policy.yaml` — 새 invariant 추적이 필요한 경우만
- 기존 관련 test fixture와 focused tests

다음 레퍼런스 창작 표면은 이 개선의 직접 편집 대상이 아니다.

- reference candidate, source analysis와 disposition 내용
- `source-materials/**`의 media/catalog truth
- active run의 reference binding과 selected derivative
- Front Planning의 reference unit, section placement와 creative prose
- 현재 진행 중인 reference skill/policy 개선 내용

이 파일들이 required read로 등록돼 있으면 최종 bytes의 SHA만 profile closure에
반영한다. 이번 개선을 이유로 그 의미나 문장을 고치지 않는다.

## 8. 검증 계획

### 구조·버전

- skill-load profile stale binding: 0
- required skill/read path 누락: 0
- contract registry stale SHA: 0
- surface registry stale SHA: 0
- instruction-surface required term 누락: 0
- 동일 규칙의 복제 owner: 0

### Startup Admission

- casual discussion은 model/task launch를 만들지 않는다.
- 명시적 start/resume은 Overall startup profile을 선택한다.
- 필수 파일 하나의 SHA가 다르면 model turn 전에 HOLD한다.
- Founder 메시지는 verbatim이며 기계 요약이 없다.
- Overall이 읽기 전 CDD/worker dispatch를 만들 수 없다.
- Overall Delta가 없으면 12블록 명령을 조립할 수 없다.
- Founder의 두 번째 일반 프롬프트 없이 같은 세션에서 다음 단계가 이어진다.

### Compiled Launch

- 12개 heading이 정확히 한 번씩 같은 순서로 존재한다.
- Blocks 03, 07, 09에 placeholder/TBD/TODO가 없다.
- profile/checkpoint와 task role/stage가 일치한다.
- rendered prompt hash와 compiled input hash가 일치한다.
- provider adapter가 creative wording을 바꾸지 않는다.

### 실제 적용·검토

- EOF 선언과 schema PASS만으로 creative PASS가 되지 않는다.
- output별 고정 review criteria와 current-work proof가 존재한다.
- 반환 output path/SHA가 Director review와 exact-copy된다.
- CDD 검토 전 Overall promotion이 불가능하다.
- unrelated reference/section/run invalidation이 0이다.

### 회귀

- Department Dispatch validator test
- harness skill-load profile validator/test
- harness execution contract schema/test
- model-routing agent validation
- Workbench native-agent and Luna dispatch smoke
- instruction-surface policy validation
- harness contract/surface registry validation
- state check -> action queue -> next unit -> current-next read-only parity

더미 fixture 통과는 실제 창작 적용 증거가 아니다. 이번 개선의 마지막 수용 기준은
Founder가 지정한 격리 더미 pilot에서 읽기, Delta, Dispatch, 반환, CDD 검토와 Overall
승격이 한 사이클로 닫히고 SU·active run·외부·유료 표면 변경이 0인 것이다.

## 9. 정지 조건

다음 중 하나라도 발생하면 시행을 즉시 중단한다.

1. 계획 대상 파일 중 하나를 레퍼런스 작업 또는 다른 active owner가 수정 중이다.
2. Phase 0 이후 대상 파일 SHA가 외부에서 다시 바뀐다.
3. current reference meaning, selected source, locator, derivative, disposition 또는
   section placement를 이번 개선이 변경해야 한다.
4. 스크립트가 Current Assignment Delta나 creative proof를 작성·요약·보완해야만
   구현할 수 있다.
5. stale binding을 숨기거나 validator를 약화해야만 테스트가 통과한다.
6. Founder의 casual discussion을 production start로 해석해야 한다.
7. CDD/Overall/Founder 권한 또는 paid/external gate를 우회해야 한다.
8. unrelated dirty worktree 변경을 되돌리거나 덮어써야 한다.

중단 시 현재 통과한 bytes를 유지하고, 겹친 파일과 필요한 다음 최소 행동만 Founder에게
보고한다.

## 10. 완료 기준

다음이 모두 충족돼야 완료다.

- Founder는 `이 런을 시작/계속해`와 창작 방향만 입력한다.
- Founder가 일반적인 `꼼꼼히 읽고 적용하라` 문장을 반복하지 않는다.
- Overall과 CDD의 최초 입장이 등록 profile/checkpoint와 current SHA에 묶인다.
- 모든 작업자는 exact owning skill과 linked reads를 EOF까지 읽는다.
- missing/stale read는 실행 전에 HOLD된다.
- actual application은 returned evidence와 Director review로 확인된다.
- Codex/Grok provider 차이가 role, prompt bytes, gate와 promotion을 바꾸지 않는다.
- 스킬이나 owning document 변경 시 profile, contract registry, surface registry와 tests가
  같은 patch에서 동기화된다.
- active reference creative truth와 unrelated run bytes 변경은 0이다.
- 격리 더미 pilot 한 사이클이 PASS로 닫히고 SU·active run bytes 변경이 0이다.

## 11. 시행 시작 시 첫 행동

레퍼런스 작업 종료 후 이 문서를 실행할 때는 곧바로 편집하지 않는다. 먼저 다음을
보고한다.

1. 현재 target-file ownership과 overlap 결과
2. current profile/contract/surface validation 결과
3. stale binding과 failing test의 새 기준선
4. 실제 최소 변경 파일 목록
5. 이 계획과 현재 canonical bytes 사이의 차이
6. proceed 또는 HOLD 추천

Founder가 그 현재 기준선을 확인한 뒤 Phase 1부터 진행한다.
