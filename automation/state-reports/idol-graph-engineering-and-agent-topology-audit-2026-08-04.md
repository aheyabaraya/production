# IDOL 그래프 엔지니어링·에이전트 토폴로지 감사

- 기준일: 2026-08-04 (Asia/Seoul)
- 성격: 비정본 아키텍처 감사 및 변경 제안
- 적용 상태: 이 문서 자체는 활성 정책·스키마·스킬·런 상태를 변경하지 않는다.
- 목표: Founder가 메시지와 일부 입력만 주어도, 좋은 핵심 레퍼런스의 조사·비교·선택·배치부터 Major/Key Screen 초안과 02A Core/Branch Cut까지 높은 품질로 자율 전개되는 구조인지 점검한다.

## 1. 결론

현재 IDOL 하네스의 큰 틀은 유지하는 편이 맞다. 이미 다음 그래프들이 존재한다.

1. PRE-00부터 05까지의 단계 그래프
2. 소스·레퍼런스·정본 산출물의 provenance 그래프
3. Founder, Overall Director, CDD, 부서 worker의 권한 그래프
4. 섹션별 소유권·병렬 실행·합류 그래프
5. Founder 개입 이후 영향을 받은 범위만 다시 투영하는 invalidation 그래프
6. 생성·검수·편집으로 이어지는 세션 계보 그래프

따라서 전면 재작성이나 즉시 Rust/Rhai로 옮기는 것이 우선은 아니다. 현재의 가장 큰 빈틈은 위 그래프들이 여러 정책·스키마·스킬에 나뉘어 있고, 한 런의 실제 상태를 하나의 typed dynamic run graph로 투영하는 실행 계층이 아직 없다는 점이다.

권고 구조는 다음과 같다.

```text
정본 creative truth: 기존 YAML/JSON 산출물과 Founder lock
        ↓ 투영
typed run graph: node, edge, owner, gate, state, input hash, output hash
        ↓ 실행
현재: Ruby/Python validator와 runner
후일: 필요할 때 Rust host + 제한된 Rhai guard expression
```

Rhai는 그래프 자체가 아니다. 그래프 엔진 안에서 `이 노드를 지금 실행해도 되는가`, `어느 후속 노드를 무효화할 것인가` 같은 제한된 조건식을 안전하게 평가하는 선택지다.

## 2. Founder 목표를 이 감사에서 해석한 방식

원하는 결과는 단순 자동 완성이 아니다.

- Founder가 명확한 메시지, 필수 요소, 보유 레퍼런스를 주면 AI가 그것을 확장한다.
- Founder가 핵심 레퍼런스를 주지 않은 경우에도 AI가 먼저 좋은 후보를 찾아온다.
- 후보를 많이 나열하는 데서 끝나지 않고 왜 좋은지 비교해 하나의 추천으로 좁힌다.
- 각 레퍼런스를 어느 섹션과 화면 기능에 쓸지 배치한다.
- Major/Key Screen과 Core Cut 초안이 좋은 수준으로 나온다.
- Branch Cut은 단순히 서로 다른 그림이 아니라 상위 사건과 영화 전체 흐름을 확장한다.
- Founder의 필수 개입 지점은 보존하되, 그 사이 과정은 되묻지 않고 reviewable한 상태까지 진행한다.
- 속도와 토큰 효율은 품질을 훼손하지 않는 범위에서 극대화한다.

## 3. 현재 구조에서 이미 잘 된 부분

### 3.1 큰 단계와 권한 구조

현재 stage registry는 5개 phase, 19개 stage로 유효하며, artifact routing도 19/19가 연결되어 있다. Overall Director가 최종 추천·승격·Founder 제시를 소유하고, CDD는 pre-02A 개발을 지휘하며, Luna/Max worker는 경계가 정해진 조사·개발·섹션 산출물을 반환한다. 최종 권한이 둘로 갈라지지 않는 점이 좋다.

### 3.2 레퍼런스와 화면 번역에 대한 품질 계약

현재 계약은 다음을 이미 강하게 요구한다.

- 실제 source identity, locator, path, hash와 pixel observation 보존
- active visual section마다 최소 3개 reference unit, 2개 original source, 2개 기능 비교
- Founder가 직접 선택한 full-scene/sequence 문법의 하위 단계 보존
- Front Planning에서 reference disposition과 섹션 배치
- 01에서 action, staging, camera, space/object, transition으로 확장
- 02A에서 Core Cut과 Branch Cut으로 generation coverage 배분
- Branch가 같은 정보의 반복이 아니라 독립적인 화면 기여를 보유

즉, 레퍼런스가 단순 mood citation으로 사라지거나 Branch Cut이 같은 장면의 변형 이미지 수만 늘리는 것을 막는 기반은 이미 강하다.

### 3.3 세션 분리

pre-02A CDD와 post-02A section generation lineage가 분리되어 있고, 후자는 한 물리 섹션만 소유하도록 제한되어 있다. 이는 오래된 기획 대화가 이미지·모션 실행 세션에 섞이는 것을 막는다.

## 4. 보완해야 할 핵심

### 4.1 통합된 동적 런 그래프

정적 stage DAG 외에 한 런의 실제 실행 상태를 아래처럼 투영할 필요가 있다.

- node type: stage, department job, section, Core Cut, Branch Cut, review, generation, playback, edit
- edge type: requires, derives-from, owned-by, reviewed-by, invalidates, joins, blocks, binds-reference
- node state: not-ready, ready, running, returned, reviewed, passed, held, invalidated
- runtime evidence: input digest, skill revision, result digest, output hash, owner lease, decision epoch
- resource rule: 같은 정본 bytes는 한 owner만 쓰고, disjoint section만 병렬 실행

이 계층은 creative truth를 새로 쓰지 않는다. 기존 정본을 읽어 실행 가능 상태와 영향 범위를 계산하는 투영·조정 계층이어야 한다.

### 4.2 Branch Cut의 최상위 판정은 개연성

Branch Cut에서 가장 중요한 것은 개연성이다. `관객이 새로 읽게 되는 정보가 있다`는 조건은 개연성을 통과한 뒤 Branch를 만들 가치가 있는지 확인하는 하위 조건이다. 새 정보만 최상위에 두면 무작위로 새로운 화면을 끼워 넣어도 통과할 수 있다.

모든 Branch Cut은 다음 연결을 설명해야 한다.

```text
whole-film message/story spine
  → section job과 audio cue
    → parent Core event의 상태 변화
      → 이 Branch가 새로 드러내거나 연장하는 것
        → 앞뒤 Branch/Core와의 인과·감정·공간·편집 연결
```

여기서 개연성은 사실적인 서사만 뜻하지 않는다. 시적·비선형·초현실 MV도 앞 장면이 만든 질문, 감정, 공간 규칙, 오브젝트 상태, 음악적 압력 또는 편집 기대 중 하나를 이어받고 다음 화면에 넘겨야 한다. 새 정보, 반응, 공간 결과, insert, aftermath, transition은 이 연결 안에 있을 때만 유효하다. 상위 사건을 진전시키지 않고 인접 흐름을 끊는 새로움은 Branch 확장이 아니라 HOLD 대상이다.

판정 순서는 다음과 같이 고정하는 편이 맞다.

1. whole-film/section/Core와의 인과·감정·공간·음악·편집 개연성
2. 이 Branch가 추가하는 필수 화면 정보
3. 인접 Branch/Core와의 비중복성
4. 실제 생성·모션·편집 가능성

### 4.3 새 판단 시스템을 만들지 않고 기존 Director 스킬의 기준을 정렬

`skills/idol-front-planning-director/SKILL.md`에는 이미 좋은 레퍼런스와 화면을 고르는 판단 계약이 상당 부분 존재한다. CDD가 exact media, source-to-screen delta, 세 가지 current-work dependency, observable state change, Core/neighbor distinction, transformed recurrence, whole-film consequence, rejected collision, strongest executable invariant와 concrete risk를 검토하게 되어 있다. Quality Gate에도 pacing, message, continuity, non-repetition, reference combination과 화면 관찰 가능성이 들어 있다.

따라서 별도의 `Director Judgment Card` 스킬·산출물·스키마·validator를 추가하지 않는다. 그것은 같은 판단을 한 번 더 적고 한 번 더 검증하는 새 drift 지점이 된다. 필요한 변경은 기존 CDD Decision Set과 Director Development Report 안에서 흩어진 판단을 한 번의 비교 순서로 정렬하는 것이다. 아래의 `Director Judgment Lens`는 새 정본 artifact가 아니라 기존 Director 스킬 안의 짧은 검토 순서다.

#### Hard stop

아래 중 하나가 발생하면 다른 장점으로 상쇄하지 않고 탈락 또는 HOLD한다.

- source identity 또는 실제 관찰 근거가 없다.
- Founder lock, member identity, 안전, claim, 출력 형식과 충돌한다.
- 선택된 노래의 섹션 cue 및 whole-film spine과 연결되지 않는다.
- 이미 있는 장면과 동일한 화면 정보를 반복한다.
- 생성·촬영·편집 가능성을 설명하지 못하면서 핵심 아이디어도 보존하지 못한다.

#### 기존 기준의 비교 순서

1. **Target reward**: 잠긴 관객이 왜 반응하는가.
2. **Message contribution**: 메시지를 seed, complicate, release, resolve, echo 중 어떤 방식으로 진전시키는가.
3. **Audio fit**: 선택된 곡의 정확한 cue, 리듬, 에너지, 가사 의미와 어떻게 맞물리는가.
4. **Screen function**: character, relation, world/system, action, object, space, camera, edit 중 어떤 빈자리를 채우는가.
5. **Source evidence fidelity**: 실제 관찰한 장면 문법을 무엇은 유지하고 무엇은 바꾸는가.
6. **Whole-film causality**: 앞 장면 때문에 가능해지고 다음 장면을 준비하는가.
7. **Current-title specificity**: 다른 곡·멤버·세계관의 명사로 바꾸면 성립하지 않는가.
8. **Non-redundancy**: 인접 후보나 기존 Major/Core와 다른 정보를 주는가.
9. **Composability**: 다른 support reference 및 현재-title member visual과 충돌 없이 결합되는가.
10. **Observable strength**: 몸, 사물, 공간, 카메라, 구도, 빛, 변화로 화면에서 보이는가.
11. **Branch potential**: 하나의 강한 Core event에서 서로 다른 필수 관점·결과·여운을 만들 수 있는가.
12. **Feasibility with idea retention**: 가능한 수준으로 만들면서도 가장 강한 발상을 훼손하지 않는가.

#### 기존 Decision Set의 권고 출력

AI는 기존 Decision Set 안에서 후보마다 아래를 작성한다.

- observed evidence
- exact proposed transfer
- strongest reason to keep
- concrete weakness or mismatch
- relationship to whole-film spine and section job
- why it beats the nearest alternative
- disposition: recommend / combine / hold / reject / search further
- if recommended: Major/Key Screen 및 Core/Branch placement 초안

최종 추천은 하나, 양립 불가능한 대안은 최대 하나만 남긴다.

#### 총점을 두지 않는 이유

창작 최종 판단에는 합산 총점을 두지 않는 편이 낫다. 총점은 `개연성 0점 + 미장센 10점`을 평균내어 살릴 수 있기 때문이다. 개연성, source evidence, Founder lock, identity/safety, 비중복성은 다른 장점으로 보상할 수 없는 hard gate다. 나머지 축은 `strong / viable / weak` 같은 진단 또는 후보 간 pairwise comparison에만 쓴다. 수백 개 후보의 검색 순서를 잡는 retrieval relevance score는 사용할 수 있지만, 그 점수가 CDD의 creative PASS가 되어서는 안 된다.

### 4.4 반복 활용 레퍼런스는 Founder 취향 데이터이기도 하다

현재 reference catalog에는 373개 unit과 검색·기능 분류가 있고 usage history는 13건이다. 13건 중 passed/held 3건은 CF 사례이므로, 이것만으로 IDOL Founder 취향을 추론할 수 없다. 다만 이 시스템이 최근 추가되었다면 표본이 적은 것은 자연스럽고, 실패로 볼 사안은 아니다.

반복적으로 활용할 좋은 소스를 고르는 것이 목적이라면 Founder의 attracted/keep/connect/reject 이력은 실제로 취향 데이터가 맞다. 다만 하나의 값으로 섞지 않고 다음 세 층을 분리해야 한다.

1. `source_quality`: 관찰 가능한 장면 문법, 분석 완성도, 해상도·가용성, 재사용 가능한 기능
2. `founder_affinity`: Founder가 반복해서 끌리거나 유지·연결·거절한 경향
3. `current_title_fit`: 이번 곡, 타깃, 메시지, 멤버, section gap과의 적합성

Founder affinity는 다음 검색의 prior와 shortlist 정렬에는 강하게 사용하되, 현재 곡과의 개연성이나 source evidence를 무시하는 자동 PASS가 되어서는 안 된다. 반대로 source_quality가 높아도 Founder가 반복해서 거절하는 문법이라면 추천 우선순위를 낮추거나 왜 이번에는 예외인지 설명해야 한다.

아래 lifecycle 기록은 이 세 층을 학습하는 데 가치가 있다.

```text
source/reference
  → observed visual evidence
  → 기존 Director Judgment Lens 비교 판단
  → proposed screen function
  → Direction Synthesis 생존 여부
  → FP Final 생존 여부
  → Major/Key Screen 배치
  → 02A Core/Branch 생존 여부
  → 최종 화면 사용 여부와 결과
```

이 기록은 두 가지를 함께 한다.

- Founder의 반복적인 시각 취향과 피해야 할 문법을 다음 검색에 반영한다.
- 처음 추천한 이유가 FP, 02A, 생성·playback에서도 살아남았는지 검증한다.

표본이 적을 때는 취향을 확정하지 않고 `weak prior`로 사용한다. Founder 반응 이력이 없다고 실행을 막는 gate가 되어서는 안 된다.

## 5. CDD 구조와 세션 관리

### 5.1 권고 토폴로지

다중 CDD 권한을 병렬로 두지 않는다.

- logical CDD lineage: 런당 하나
- active physical CDD session: 한 시점에 하나
- physical session rollover: 필요할 때 순차적으로 교체 가능
- successor session: 같은 lineage id, decision epoch, current checkpoint, unresolved decisions, exact hashes만 이어받음
- department workers: 경계가 겹치지 않는 조사·레퍼런스·섹션 작업만 병렬 실행
- Overall Director: CDD 반환물 검토, 추천 승격, Founder 제시와 최종 수용
- active Founder-facing Sol: 한 시점에 Overall 또는 CDD 중 하나
- wake-up route: 하위 세션의 완료·HOLD·권한 요청·milestone event만 상위 세션을 깨움

두 개 이상의 CDD가 동시에 방향을 소유하면 context 오염보다 더 큰 문제가 생긴다. 기준, 메시지, 레퍼런스 처분, section ownership과 Founder 대화가 서로 갈라진다. 반면 물리 CDD 하나를 무한히 오래 유지하면 컨텍스트가 비대해진다. 해법은 여러 CDD의 동시 권한이 아니라, **한 논리 계보 안에서 한 물리 CDD를 순차 교체하는 것**이다.

여기서 `logical CDD`는 계속 열려 있는 별도 모델 채팅이 아니다. 지속되는 것은 파일에 기록된 lineage, decision epoch, 현재 추천, rejected reasons, unresolved decisions, exact artifact/hash 상태와 Founder workbench 주소다. 실제 판단을 수행하는 모델 채팅이 physical CDD session이다.

현행 `idol-front-planning-director` 스킬은 startup부터 02A handoff까지 `one durable Founder-visible room`을 요구한다. 따라서 아래 sequential CDD rollover는 아직 활성 정본이 아니라, `durable room`을 durable decision/workbench lineage로 해석하도록 계약을 명확히 바꿔야 하는 제안이다. 변경 전에는 현행 단일 room 규칙이 우선한다.

따라서 `영구 logical CDD 채팅 + 물리 CDD 비서 채팅`으로 두면 안 된다. 영구 채팅도 완료된 반환물을 계속 먹으면서 결국 오염된다. 올바른 구조는 다음과 같다.

```text
durable CDD state in files
  ↕
Physical CDD Session A — 현재 판단 owner
  ← 짧은 reference/development workers의 완료된 Decision Set만 수신
  → checkpoint와 aggregate report 기록 후 종료

Physical CDD Session B — 같은 logical lineage의 후속 owner
  ← Boot Pack과 unresolved scope만 로드
```

시간 순서로 보면 비서는 여러 명처럼 보일 수 있지만 동시에 여러 CDD가 있는 것은 아니다. Session A가 닫힌 뒤 Session B가 같은 역할과 권한을 승계한다. 별도의 짧은 worker가 수많은 Luna 결과를 정리하는 비서 역할을 맡을 수는 있지만, 그 역할은 CDD가 아니라 `context curator/reference worker`이며 PASS/REJECT 권한이 없다. CDD는 raw pool이 아니라 worker가 완결한 Decision Set과 exact evidence pointer만 받아 최종 비교 판단한다.

Overall과 CDD는 같은 창작 자료를 동시에 판단하지 않는다. startup에서는 Overall이 CDD와 Boot Pack을 만들고 event wait에 들어간다. pre-02A 개발 중에는 physical CDD Sol이 실제 Founder-facing 대화와 worker PASS/REJECT를 소유한다. CDD가 Luna/Max worker를 보낸 뒤에는 polling하지 않고 worker return event를 기다린다. worker는 중간 commentary가 아니라 완료, HOLD, 권한 요청 또는 material conflict만 CDD를 깨운다. CDD는 promoted milestone, Overall 권한 또는 Founder gate가 필요할 때만 compact aggregate report로 Overall을 깨운다.

```text
Overall active → CDD launch → Overall event wait
CDD active → Luna/Max dispatch → CDD event wait
worker final/HOLD → CDD wake → CDD 판단
CDD milestone/authority request → Overall wake → promote/return → wait
```

상위가 하위 상태를 반복 조회하거나 raw worker chat을 계속 수신하면 sleep의 의미가 사라지고 컨텍스트가 중복된다. wake payload는 exact manifest, survivor, rejected reason, material risk, unresolved decision과 path/hash만 포함한다.

### 5.2 CDD 이관 감지·경고·Founder 확인

CDD rollover의 감지 범위는 넓게 잡되 실제 이관 문턱은 높게 잡는다. 최적화 로직이 자동으로 세션을 바꾸지 않는다. 어떤 trigger도 그 자체로 이관 권한이 아니다.

#### 넓은 감지 범위

다음 중 하나라도 발견하면 먼저 경고 후보로 기록한다.

1. **run/title 오염**: 다른 album/title/run, 다른 섹션의 상세 truth 또는 post-02A 자료가 현재 CDD 판단에 섞임
2. **decision 오염**: 이전 decision epoch, 교체된 Founder lock, 탈락·HOLD 후보, 비구속 proposal을 현재 lock처럼 다시 사용함
3. **scope 오염**: passed member visual이나 unaffected section을 이유 없이 재개방하거나 worker/CDD/Overall 권한이 겹침
4. **reference 오염**: raw pool·전체 catalog·rejected dump가 current shortlist보다 커짐, source function이 mood summary로 축약됨, 같은 source를 이유 없이 반복해서 다시 읽음
5. **evidence 손실**: exact source id, locator, path/hash, current revision 또는 preserve/discard 근거를 현재 답변에서 회수하지 못함
6. **continuity 손실**: whole-film spine, section job, Core/neighbor 관계 또는 entry/exit 상태와 충돌하는 추천이 반복됨
7. **판단 흔들림**: 이미 답한 질문을 반복하거나 서로 모순된 disposition을 내고, generic/noun-swap 장면이나 같은 carrier 반복이 늘어남
8. **context 압력**: 다음 판단의 exact evidence를 넣을 여유가 부족하거나 완료·탈락 자료가 active decision context보다 커짐
9. **worker 누적**: 미검토 return, retry, Pass B와 pending worker가 쌓여 현재 owner와 반환 대상을 한 번에 설명하기 어려움
10. **checkpoint drift**: Boot Pack 이후 policy/schema/skill/source bytes 또는 canonical hash가 바뀌어 현재 세션의 전제가 오래됨
11. **compaction/transport 손실**: 세션 요약·handoff·transport 이후 Founder wording, unresolved decision 또는 exact binding이 빠짐
12. **오류 반복**: 같은 validation/dispatch 오류나 stale pointer를 고친 뒤에도 동일 원인으로 다시 발생함

감지 범위를 넓게 잡는 목적은 조기 발견이다. 경고가 곧 오염 확정이나 즉시 이관을 의미하지 않는다.

#### 경고 단계

1. `CDD_CONTEXT_WATCH`: 비차단 조기 경고. 현재 작업은 계속하고 증거를 더 확인한다.
2. `CDD_ROLLOVER_RECOMMENDED`: material risk가 확인됨. 권고 시점과 checkpoint 준비 상태를 Founder에게 알리되 현재 세션은 유지한다.
3. `CDD_ROLLOVER_READY`: 안전 checkpoint가 완성됨. Founder가 `지금 이관 / 현재 세션 유지 / 다음 milestone로 연기` 중 하나를 정한다.
4. `CDD_CONTEXT_EMERGENCY_HOLD`: 현재 세션이 Founder lock·identity·ownership·exact evidence를 보존할 수 없다고 입증된 경우. 새 세션을 몰래 열지 않고 affected scope를 HOLD하고 Founder에게 보고한다.

동일 decision epoch와 affected scope에는 같은 수준의 경고를 반복 전송하지 않는다. severity가 올라가거나 새 증거가 생길 때만 갱신해 경고 자체가 Founder 대화를 오염시키지 않게 한다.

#### Founder-visible 경고 메시지의 필수 내용

- 현재 경고 수준과 발견된 구체적 증거
- 영향을 받는 title, section, decision과 worker ids
- 지금 계속할 경우의 실제 위험
- checkpoint 준비 여부
- 다음 세션에 그대로 이어지는 것
- 다음 세션에 싣지 않을 raw/완료/탈락 context
- 권고 이관 시점과 예상 이득
- `지금 이관 / 유지 / 연기` 선택

Founder-facing 메시지는 다음처럼 한눈에 보이게 한다.

```text
[CDD_ROLLOVER_RECOMMENDED — 아직 이관하지 않음]
발견한 징후:
근거:
영향 범위:
현재 작업 상태: 계속 진행 / 임시 HOLD
지금 유지할 때의 위험:
checkpoint 준비 상태:
다음 세션에 이어지는 것:
다음 세션에서 제외되는 것:
권고 시점과 기대 효과:
Founder 선택: 지금 이관 / 현재 유지 / 다음 milestone로 연기
```

`CDD_CONTEXT_EMERGENCY_HOLD`를 제외한 모든 rollover에는 명시적 Founder 확인이 필요하다. Emergency도 자동 이관이 아니라 먼저 HOLD와 복구 가능한 checkpoint를 보고한다.

#### 안전 checkpoint 조건

- Founder lock과 current decision epoch가 기록됨
- 모든 반환물이 PASS/REJECT/HOLD 또는 explicit pending으로 분류됨
- pending worker의 lineage/session/attempt, owner와 return recipient가 명확함
- current recommendation, rejected reasons와 unresolved decisions가 파일에 기록됨
- exact paths/hashes와 Founder workbench가 current bytes와 일치함
- canonical write/merge 또는 paid/external action이 진행 중이지 않음
- successor Boot Pack이 raw chat 없이 현재 truth를 재구성할 수 있음
- 이전 physical CDD가 종료되기 전 successor가 CDD 권한을 얻지 않음

Founder 대화 도중, 미검토 worker return이 남은 상태, canonical merge 중, paid/external 실행 중에는 이관하지 않는다. 기본 natural boundary는 Direction Synthesis 완료, FP/01/02A 작업 성격 전환, material Founder epoch 변경이다. 세션 수를 채우기 위한 이관은 금지한다.

### 5.3 현재 CDD에 실제로 포함되는 것

현재 선언은 세 층에서 서로 다르다.

1. `automation/harness-execution-contract.yaml`의 요약 CDD profile: CDD skill과 6개 직접 read, 약 **32,848 words**
2. `automation/harness-skill-load-profiles.yaml`의 CDD startup checkpoint: CDD skill과 10개 read, 약 **40,854 words**
3. `skills/idol-front-planning-director/SKILL.md`의 Required Reads를 실제 적용: 스키마와 전체 reference catalog까지 확장되어 기본 약 **78,848 words**

일반적인 reference 연결 작업에서는 operating contract가 더해져 약 **82,538 words**가 된다. board contract까지의 16개 핵심 파일 합계는 약 **85,157 words**, 일반 Founder board 작업은 약 **90,464 words**, member/styling 비교 예제까지 포함하면 약 **94,365 words**다. 이 수치는 2026-08-04 재검토 시점의 live bytes 기준이며, Founder가 동시에 파일을 정리하고 있으므로 다음 세션에서 다시 산출해야 한다.

특히 전체 `catalog/references/reference-catalog.yaml` 37,570 words가 Required Reads에 직접 포함되어 있다. 최근 구조에서 검색 worker와 Reference Working Index가 shortlist를 만들도록 바꾸었어도, 이 연결이 남아 있어 CDD가 전체 카탈로그를 다시 읽도록 요구한다.

`wiki/reference-management-system.md`가 명시한 정식 의도는 이미 전체 카탈로그 정독이 아니라 source identity, search term, purpose class 검색이다. 즉 엔지니어링 방향은 맞고 CDD Required Reads와 worker load profile이 그 검색형 설계를 아직 어기고 있다. 현재는 전용 catalog query 도구 없이 YAML 텍스트 검색과 별도의 source-hub lookup이 나뉘어 있으므로, 정본 YAML은 유지하되 deterministic derived retrieval index 또는 작은 query command를 두는 편이 적절하다. 조회 결과는 creative truth가 아니라 pointer-only shortlist여야 한다.

### 5.4 권고 CDD Boot Pack

CDD가 항상 들고 갈 핵심은 다음으로 제한한다.

- role, authority, must-not, Founder gate
- locked target와 target content contract
- selected song/audio analysis 및 00A 핵심
- Founder brief, must, avoid, explicit locks
- whole-film message/story spine 최신본
- 현재 Decision Set과 unresolved contradiction
- section boundary와 section job
- current-title member visual bindings
- Reference Working Index shortlist: source id, locator, observed function, mismatch risk, 필요한 pointer/hash
- current checkpoint, decision epoch, canonical artifact hashes

전체 catalog, 다른 title package, raw research pool, 완료된 worker 채팅, 다른 섹션의 상세 산출물은 기본 Boot Pack에 넣지 않는다. 필요한 항목은 pointer로 조회하고, 해당 작업을 맡은 worker가 exact source를 EOF/pixel inspection한 뒤 압축되지 않은 근거를 반환한다.

중요한 원칙은 `핵심만 전달`이 `얕은 계획`을 의미하지 않는다는 점이다. CDD의 입력은 작게 유지하되, 각 worker가 맡은 exact source와 owning skill은 전부 읽고 증거를 반환해야 한다.

이 방식은 원하는 엔지니어링에 적합하다. retrieval은 넓고 싸게, source inspection은 선택된 범위에서 깊게, director context는 작고 결정 중심으로 유지하기 때문이다. 단, worker의 요약문만 전달하면 source evidence가 손실되므로 Decision Set에는 exact source id, locator, path/hash, observed facts, preserve/discard, mismatch, rejected reason과 confidence를 남겨 CDD가 필요할 때 원본 증거를 재확인할 수 있어야 한다.

### 5.5 CDD Successor Boot Pack 최소 계약

#### 현재 실제 구현

현재 `scripts/idol_director_dispatch_index.rb`는 `idol-director-boot-pack.v1`을 생성한다. 소스는 Director Dispatch Index와 canonical heads이며 다음을 담는다.

- `run`, `scope`, `current_stage`
- `decision_epoch`
- `active_founder_locks`
- `open_or_held_tasks`
- `current_canonical_heads`
- `active_board_cycle`
- `next_actions`
- `exact_lineage_checkpoint`

이는 현재 작업 위치, owner, attempt와 hash를 되찾는 실행 복구 팩으로는 유효하다. 그러나 current recommendation, whole-film creative spine, rejected/do-not-revive 이유, unresolved creative decisions와 active Reference Working Index view가 명시적 필수 필드가 아니다. 따라서 현재 v1만으로 physical CDD를 chat-free하게 교체하기에는 창작 맥락이 부족하다.

`schemas/harness-context-pack.schema.json`의 v5는 02B 한 section/Branch worker용이다. FP·01·02A와 인접 Core/Branch, 현재 visual bindings만 싣는 post-02A execution pack이므로 CDD successor pack과 합치거나 대신 사용하지 않는다.

현재는 전용 CDD successor schema가 없다. 새 schema를 바로 추가하기보다 기존 Director Boot Pack의 `cdd_successor` profile과 기존 model-authored Director Development Report/checkpoint pointer를 확장하는 편이 validator 증가를 막는다.

#### 최소 공통 Kernel

다음 열 개 block은 모든 CDD successor pack에 필수다.

| Block | 최소 내용 | 전달 방식 |
|---|---|---|
| 1. Pack identity | run/content id, profile, generated time, source session, successor target, pack version | small exact values |
| 2. Role and authority | logical role CDD, current owner lease, allowed decisions, must-not, Overall/Founder gate | contract path/hash + compact projection |
| 3. Founder truth | decision epoch, verbatim active locks, must/avoid, intervention receipt pointers, pending Founder decision | exact lock values + pointers |
| 4. Common creative spine | locked target/audience promise, selected song/00A/audio map, message, whole-film progression, section map | compact model-authored projection + canonical path/hash |
| 5. Director decision checkpoint | one current recommendation, passed decisions, `do_not_revive` ids/reasons, unresolved decisions, material risk | latest reviewed Director Development Report path/hash + compact current rows |
| 6. Active evidence view | relevant Reference Working Index filtered view, surviving source/locator/function/path/hash, current-title visual bindings | pointer-only scoped view |
| 7. Canonical heads | current active artifact paths, schema/revision, SHA-256 and affected scope | exact pointers |
| 8. Execution state | open/HOLD/pending dispatches, lineage/session/attempt/owner, reviewed state, return recipient | Director Dispatch Index projection |
| 9. Review and next route | active workbench cycle, pending Founder cards, next actions, stop/hold conditions, recommended wake target | compact values + pointers |
| 10. Transfer integrity | source-set digest, pack digest, outgoing checkpoint, required contract/skill/load-profile revisions, exclusions | deterministic hashes |

Common creative spine과 recommendation/rejected reasons는 script가 새로 요약하거나 판단해서는 안 된다. CDD가 작성하고 Overall이 검토한 기존 Director Development Report 또는 current canonical projection을 exact-copy/pointer projection한다. deterministic builder는 paths, hashes, ids, selected compact values와 digest만 조립한다.

#### Stage-conditional module

공통 Kernel 외에는 successor가 바로 맡을 next scope만 추가한다.

- Song module: active lyric/arrangement question, selected-audio and audio-map evidence
- Reference module: active section gap, shortlist survivors, exact evidence pointers, rejected collision ids
- FP/01 module: active Major/Key Screen, section entry/exit, adjacent section boundary only
- 02A module: active section's Core/Branch coverage, relevant neighbor and exact binding pointers
- Member Visual exception: current-title manifest and only the unresolved new/restyle decision

다른 module은 preload하지 않는다. 다음 작업 중 필요해질 때 exact pointer로 phase-load한다.

#### 절대 넣지 않는 것

- full chat transcript와 완료된 worker 대화
- 전체 reference catalog, raw candidate pool, rejected media dump
- 다른 title/run의 package와 unrelated section detail
- historical prompt/scene prose와 inactive stage artifact
- full contact sheet 또는 원본 media bytes
- Founder가 보지 않았거나 CDD가 검토하지 않은 worker summary

탈락 이유 자체는 잃으면 안 되므로 `do_not_revive`의 id, one-line reason과 evidence pointer만 남기고 탈락 media/prose는 싣지 않는다.

#### 크기 가이드

고정 word ceiling으로 creative truth를 잘라내지 않는다. 대신 successor가 사용할 usable context를 기준으로 다음을 진단 목표로 둔다.

- 공통 Kernel + mandatory startup reads: 약 25% 이내
- next-scope exact evidence: 최소 50% 확보
- 새 판단과 출력 여유: 최소 25% 확보

이 비율을 넘으면 summary를 더 압축하지 않고 optional module을 pointer/phase-load로 내린다. exact lock, selected evidence와 unresolved decision을 토큰 절약을 이유로 삭제하지 않는다.

#### Successor admission check

새 physical CDD는 다음 일곱 질문을 pack과 pointer만으로 정확히 답하기 전에는 CDD 권한을 얻지 않는다.

1. 지금 어떤 run/stage/scope를 맡는가.
2. Founder가 정확히 무엇을 lock했고 무엇은 proposal인가.
3. 현재 추천과 그 이유는 무엇인가.
4. 무엇이 탈락/HOLD이고 왜 되살리면 안 되는가.
5. 어떤 결정이 아직 미해결인가.
6. 현재 canonical heads, active evidence와 pending owner는 누구인가.
7. 다음 행동, stop condition과 Overall/Founder wake 조건은 무엇인가.

답이 불완전하면 rollover를 실행하지 않고 기존 CDD를 유지하거나 `CDD_CONTEXT_EMERGENCY_HOLD`로 보고한다. Successor는 read-only preflight만 할 수 있고, 이전 CDD가 checkpoint를 닫고 owner lease를 반납하기 전에는 creative/write authority를 받지 않는다.

### 5.6 CDD·부서 worker의 Compiled Launch Prompt

#### 판단

이 제안은 좋다. Founder가 매번 각 부서에 긴 지시를 다시 쓰게 하는 대신 역할, 스킬 라우팅, 입력 경계, 완료·HOLD 조건과 반환 형식을 미리 정의하는 것이 현재 하네스 방향과 맞는다. 다만 **부서마다 고정된 창작 프롬프트 전문을 저장해 반복 사용하면 품질이 나빠진다.** 곡 제목과 메시지 명사만 바뀐 채 같은 장면 문법, 같은 검색어, 같은 카메라와 같은 레퍼런스 취향을 재생산하는 템플릿 공장이 되기 쉽기 때문이다.

권고안은 고정 프롬프트 라이브러리가 아니라 기존 계약에서 매 호출마다 조립하는 `Compiled Launch Prompt`다.

```text
고정 Studio Kernel
  + 선택된 Director/Department Profile
  + 현재 run/task의 Creative Delta
  = 이번 세션에만 유효한 Launch Prompt
```

현재 기반은 이미 상당 부분 존재한다.

- `schemas/department-dispatch.schema.json` v3: task, exact scope, Founder locks, required skills/read hashes, source bindings, permission, bounded output, authority, HOLD conditions, recipient, runtime return, Director review와 promotion을 소유한다.
- `automation/harness-skill-load-profiles.yaml`: 18개 역할 profile별 required skill, phase load, output contract, return route와 department-specific HOLD condition을 소유한다.
- `.codex/agents/*.toml`: Overall, CDD, Luna department, post-02A section worker의 지속적인 역할·권한·금지 규칙을 소유한다.
- `skills/*/SKILL.md`: 실제 창작 판단과 부서별 작업 방법을 소유한다.

따라서 새 creative schema, 새 품질 점수 또는 부서별 거대 프롬프트 파일을 만들 필요가 없다. 빠진 것은 이 기존 truth를 중복 없이 사람이 읽을 수 있는 한 번의 호출문으로 투영하는 얇은 launch compiler/view다.

#### 두 가지 호출 profile

CDD 호출과 worker 호출은 같은 원칙을 쓰되 같은 계약으로 억지로 합치지 않는다.

1. **CDD launch profile**
   - Overall이 한 active physical CDD를 연다.
   - CDD role/authority kernel, `cdd_successor` 또는 startup Director Boot Pack, decision epoch, Founder locks, 현재 whole-film spine, open decisions, owner lease, stop/wake/rollover 조건만 전달한다.
   - 전체 catalog, raw pool, 완료 worker chat과 unrelated section detail은 전달하지 않는다.
   - CDD는 pre-02A creative judgment와 Founder-facing 대화를 소유하지만 Overall promotion/final acceptance 권한은 갖지 않는다.
2. **Department worker launch profile**
   - CDD 또는 해당 Director가 Department Dispatch v3와 정확히 하나의 skill-load profile을 선택한다.
   - worker는 exact task/scope/output만 소유하고 최종 disposition이나 canonical promotion을 하지 않는다.
   - 하나의 Luna studio role이 여러 부서를 실행할 수 있어도 실제 읽기와 완료 조건은 선택된 department profile로 좁힌다.

CDD를 Department Dispatch의 일반 worker로 취급하지 않고, worker에게 CDD의 종합 판단 권한을 주지 않는 것이 중요하다.

#### 매번 조립할 최소 양식

```text
[1. Dispatch identity]
run / lineage / session / attempt / task / selected profile / recipient

[2. Role and authority]
이번 owner가 결정할 수 있는 것 / 할 수 없는 것 / canonical·external 권한

[3. Current creative job]
Founder verbatim message와 명시적 lock
locked target·audience reward
selected song/audio cue
whole-film spine와 assigned section/content role
현재 비어 있는 화면·레퍼런스 기능 또는 풀어야 할 질문

[4. Exact scope and non-scope]
소유 section/artifact/output path / 인접 boundary / 열지 말아야 할 범위

[5. Input pointers]
current source, reference, member asset, canonical head의 path/hash/purpose

[6. Skill route]
required SKILL.md와 linked read의 revision/hash/EOF 순서
이번 phase에만 필요한 conditional read

[7. Required work]
부서가 비교·조사·저작·검증해야 할 구체적인 creative question

[8. Output contract]
output kind, exact path, maximum artifact count, aggregate manifest 조건

[9. Quality proof]
이 부서에 필요한 source evidence, 비교 floor, message/audio/section 연결,
source-to-screen delta, anti-flat/continuity/feasibility 근거

[10. Return-ready conditions]
필수 산출물·증거·hash·manifest가 있고 Director가 실제 판단할 수 있는 상태

[11. HOLD/stop/split conditions]
missing/stale input, permission, owner overlap, evidence floor, identity/safety,
scope 과대, unsupported surface와 다음 smallest action

[12. Return and wake]
정확한 recipient, compact return payload, milestone/HOLD/authority wake 조건
```

고정되는 것은 이 순서와 권한·무결성 규칙이다. 실제 창작 내용인 `[3]`, `[7]`, `[9]`의 current-job 문장은 CDD/Overall이 현재 근거를 바탕으로 작성한다. deterministic script는 기존 contract 값, path, hash, profile row와 이미 승인된 creative projection을 exact-copy하여 조립할 수 있지만 메시지 해석, 검색 방향, 장면 아이디어 또는 품질 PASS를 새로 저작하면 안 된다.

#### 메시지에서 레퍼런스까지의 라우팅

메인 메시지는 검색과 판단의 상위 축이 맞지만, 메시지 문구만 검색어로 바꾸면 비슷한 상징 이미지가 반복된다. worker brief는 다음 교차점에서 만들어야 한다.

```text
Founder message
  × locked audience reward
  × selected-song cue
  × whole-film/section content role
  × 현재 비어 있는 reference function
  × must/avoid와 current-title identity
```

예를 들어 `해방`이라는 메시지를 그대로 이미지 검색어로 쓰는 것이 아니라, 특정 후렴에서 관객이 받아야 할 reward, 그 section이 `release`를 담당하는지 `complicate`를 담당하는지, 현재 부족한 것이 relation/action/world/object/camera 중 무엇인지를 먼저 정한다. 그 결과를 기준으로 reference generalist, image-only World/Still, video source hub, member identity 또는 pre-02A development block 중 하나에 라우팅한다. 이 구조라야 좋은 후보 조사뿐 아니라 선택, 섹션 배치, Major/Core 초안과 Branch Cut까지 한 흐름으로 이어진다.

Founder의 일반 메시지·선호·첫 제안은 `high-priority input`, 명시적으로 말한 lock만 `Founder lock`으로 분리한다. launch compiler가 자연어를 자동 lock으로 승격하면 안 된다.

#### Reference Connection Minimum Contract

레퍼런스 연결은 이미 여러 활성 계약에 부분적으로 존재한다. Front Planning의 `source_lineages`는 main/source/derivative의 `connection_reason`을, `reference_units`는 exact source/locator, target section, screen function, observed facts, function analysis, preserve/discard와 disposition을 갖는다. `function_analysis`는 selected component, transfer boundary, do-not-transfer와 downstream target을 갖고, `section_plan`은 실제 section의 message role, audio cue와 reference unit ids를 소비한다. Reference Research worker도 source-to-screen delta와 weaker-neighbor reason을 반환한다.

따라서 새 `reference connection` schema나 별도 artifact를 만들 필요는 없다. 다만 이 필드들이 검색 시작점부터 배치까지 하나의 인과 사슬로 이어졌는지 확인하는 최소 연결 규격을 Compiled Launch Prompt와 기존 Decision Set review에 둔다.

```text
현재 화면 필요
  → 이 source에서 실제로 관찰한 근거
    → 가져올 component와 가져오지 않을 boundary
      → 현재 곡/멤버/세계로 바꾸는 source-to-screen delta
        → 어느 section의 어떤 screen event를 가능하게 하는가
          → 인접 reference보다 이 후보가 필요한 이유
```

각 survivor는 기존 필드로 다음 일곱 연결을 답해야 한다.

1. **Need**: whole-film message progression, target response, 정확한 audio cue, section message/content role과 현재 missing function 중 무엇을 해결하는가.
2. **Observed evidence**: exact source/locator/path/hash에서 실제로 본 action, relation, space, object response, camera/composition, material/light 또는 ordered grammar는 무엇인가.
3. **Selected component**: source 전체가 아니라 어떤 화면 component를 가져오는가.
4. **Transfer boundary**: member identity, song timing과 current world에 어떻게 번역하며 무엇은 preserve/discard/do-not-transfer하는가.
5. **Placement**: target section/sequence와 downstream FP Key Screen, 01, 02A, 03V 또는 edit 중 어디에 쓰이는가.
6. **Connection role**: existing source kind/function/combination role을 사용해 governing, supporting, lineage/origin 또는 gap/challenge 증거 중 어떤 역할인지 설명한다. 새 enum을 만들지 않는다.
7. **Comparative necessity**: 더 가까운 후보보다 강한 이유, 중복되지 않는 screen contribution, mismatch risk와 이 후보를 빼면 사라지는 화면 정보를 말한다.

관련성의 hard gate는 표면 유사도가 아니라 다음 chain의 완결성이다.

```text
current need
  → observed source evidence
    → bounded transfer
      → observable screen consequence
        → exact section placement
```

하나라도 끊기면 `관련 있어 보임`만으로 survivor가 될 수 없다. 반대로 외형과 장르가 달라도 이 사슬을 더 강하게 만족하면 좋은 기능적 레퍼런스가 될 수 있다. 합산 relevance score는 사용하지 않는다.

검색 자체를 지나치게 고정하지 않는다. Pass A의 visual ignition은 예상 밖의 source와 인접 영역을 탐색할 수 있다. 다만 shortlist에 남는 순간 위 연결을 증명해야 한다. Pass B는 `관련 레퍼런스 더 찾기`처럼 넓게 지시하지 않고, first wave에서 비어 있는 정확한 function, continuity risk 또는 governing candidate의 약점을 named gap으로 보낸다.

Compiled Launch Prompt의 `[3. Current creative job]`에는 Need를, `[7. Required work]`에는 named search/connection claim을, `[9. Quality proof]`에는 위 일곱 연결을 넣는다. 반환은 기존 `section_reference_set`, `reference_working_index_delta`, Front Planning `reference_units`와 `section_plan`에 투영한다. 같은 내용을 새 문서에 다시 복제하지 않는다.

CDD는 다음 세 경우를 HOLD/REJECT한다.

- message나 mood만 비슷하고 observable source evidence와 screen event 연결이 없음
- selected component와 transfer boundary 없이 source 전체를 막연히 차용함
- section placement는 있으나 기존 survivor와 같은 기능·같은 화면 정보를 반복함

#### Official/Original-First Source Policy

현재 활성 계약에는 official MV와 MV-adjacent official source가 기본이라는 문구가 있지만, `amv_or_mad_edit`와 short-form response edit도 허용 유형에 남아 있다. media-security, research-radar, video-reference-hub와 concept-research는 original context 확인 뒤 AMV/MAD/edit를 response-pattern evidence로 사용할 수 있게 한다. 과거 retrieval view에는 AMV unit이 `candidate_for_reuse`로 남아 있다. 따라서 지금 상태는 `공식 우선`이지 `AMV가 governing/selected reference로 들어오는 것을 확실히 막음`은 아니다.

다음 canonical 정렬에서 pre-02A MV reference research의 기본 정책을 `official_original_first`로 명시하는 것이 맞다. 여기서 official/original은 업로더 이름만 뜻하지 않는다. artist/label, 원작자, 제작사, 감독·촬영감독·스튜디오, 배급사, 방송사, 브랜드 또는 권리 보유자가 공개한 원본과 출처가 검증되는 professional primary source를 뜻한다.

##### 기본 선택 가능 source family

우선순위는 고정 quota가 아니라 governing reference와 sequence/scene grammar를 고르는 기본 순서다.

1. **Official MV/visual film**: 공식 뮤직비디오, visual film, official visualizer 중 실제 장면 문법을 읽을 수 있는 원본
2. **Official teaser/trailer/concept film**: comeback trailer, concept film, highlight film, album/artist teaser
3. **Official performance source**: performance film, dance practice, choreography/performance video; 현재 section에 body/blocking/performance 기능이 있을 때만
4. **Official campaign/editorial source**: 브랜드 필름, 패션 필름, 공식 editorial, production-company/director portfolio의 원본
5. **Official narrative/world source**: 영화·시리즈·애니메이션·게임의 공식 장면, trailer, cinematic 또는 권리자/제작자가 공개한 원본
6. **Official still source**: concept photo, key visual, promo still, press still, 공식 poster/editorial image와 출처가 검증된 creator original

`공식 K-pop MV만 찾기`로 좁히지 않는다. Major scene grammar는 official MV/teaser 계열을 우선하되, 특정 world/action/object/camera/edit gap은 검증된 영화·애니메이션·게임·광고·패션 원본이 더 강할 수 있다. 핵심은 source type보다 원본성, 출처, 실제 관찰 가능성, current-job fit이다.

##### 기본 선택 불가 source family

- AMV, MAD, fan edit, fan trailer, unofficial music edit
- reaction, compilation, top-scenes montage, clip collection
- 출처가 불명확한 재업로드, 워터마크 제거본, AI upscale/interpolation/re-edit
- Pinterest·블로그·SNS repost처럼 원본 출처가 해결되지 않은 surface
- fan moodboard와 출처 없는 contact sheet

AMV, MAD와 fan edit는 단순 선택 불가를 넘어 **Founder-explicit-approval-only source**다. 현재 작업에서 Founder가 exact source와 허용 목적을 명시적으로 승인하지 않았다면 agent가 자율적으로 검색, query에 포함, 결과 열기, 다운로드·capture, playback/pixel inspection, 분석, source registration, 인용, response-pattern 사용, governing/supporting 후보화 또는 section/direct-use binding을 해서는 안 된다. 검색 결과에 우연히 나타나면 열지 않고 official/original route를 계속한다. Founder가 링크나 파일을 제공한 사실만으로 분석·사용 승인을 추론하지 않는다.

Founder가 승인할 때는 exact current-task scope, source identity/URL, 허용 목적과 허용 action을 verbatim permission으로 남긴다. 예를 들어 `이 AMV의 편집 리듬만 분석`은 해당 편집 관찰만 허용하며 장면·캐릭터·세계 근거는 official original에서 다시 확인한다. direct scene binding이나 이미지 사용은 별도 explicit lock 없이는 허용되지 않는다. 승인되지 않은 AMV/MAD가 현재 요청의 필수 source라면 `founder_permission_missing` HOLD이며 agent가 대신 허가하거나 비슷한 AMV를 찾지 않는다.

AMV/MAD/fan edit를 제외한 Pinterest·블로그·SNS repost, compilation metadata와 fan moodboard도 governing/supporting/section-bound unit이 될 수 없다. 이들은 원작 제목이나 official original 후보를 찾는 navigation surface로만 사용할 수 있으며, survivor에는 추적한 official/original unit을 넣는다. 원천을 찾지 못하면 `unresolved_origin` HOLD이고 비공식 surface로 빈칸을 채우지 않는다.

#### Founder Main Reference: Origin-First Discovery

기억한 `원천 → 발굴` 구조는 활성 정책에도 다음 형태로 존재한다.

```text
main reference
→ source work, myth, genre or visual grammar
→ derived or adjacent works
→ target/message/content connection
→ section-specific screen use
```

이를 현재 official-first 정책과 결합하면 Founder가 메인 레퍼런스를 줄 때의 실행 순서는 다음과 같다.

```text
Founder main reference 보존
  → 표면 분류: official original / official derivative / repost / AMV·fan edit
    → 원천·공식본·creator/production lineage 확인
      → 메인 레퍼런스의 selected component와 기능 분해
        → 같은 계보의 official works 발굴
          → 같은 기능을 더 잘 푸는 official/original analogues 발굴
            → governing/supporting/challenge 후보 비교
              → exact section placement와 source-to-screen delta
```

두 종류의 확장을 구분한다.

1. **Genealogy discovery**: 원작, 공식 adaptation, creator/director/production company의 관련 work, documented influence, motif lineage를 따라간다.
2. **Functional discovery**: 계보가 같지 않아도 현재 필요한 action, relation, world/system, object response, camera, composition, material/light 또는 edit 기능을 더 잘 수행하는 official/original source를 찾는다.

계보 관계와 기능 유사성을 혼동하지 않는다. documented influence가 없으면 `영향을 받았다`고 말하지 않고 narrative/formal/screen analogue로 제한한다.

Founder main reference가 없을 때는 반대로 `current need → official source-family search → origin verification → connection comparison → section placement`의 function-first route를 사용한다. 즉 두 경로는 다음처럼 정리된다.

```text
Founder main reference 있음:
main → origin verification → genealogy + functional discovery → placement

Founder main reference 없음:
need/function → official discovery → origin verification → comparison → placement
```

Compiled Launch Prompt에는 `source policy`, `main-reference mode`, 허용 source family, 금지 source family, origin-verification requirement와 named exception을 넣는다. AMV/MAD permission은 기본 `not_authorized`이며, 허용 시 exact Founder verbatim approval pointer와 allowed purpose/action을 넣는다. worker는 raw unofficial link가 아니라 original source id, official locator, exact evidence path/hash와 원천 추적 결과를 반환한다.

#### 완료·실패의 의미

`worker가 끝났다고 말함`과 `creative PASS`를 분리한다.

- `returned`: worker가 계약된 bytes, evidence, hashes와 HOLD reason을 반환한 상태다. 아직 creative PASS가 아니다.
- `director_review.accept/patch/reject/hold`: CDD 또는 지정 Director가 실제 source와 current-work 기준으로 판단한다.
- `promoted`: 지정 promotion owner가 검토된 exact bytes만 다음 truth로 승격한다.
- `split_required`: 범위가 너무 넓거나 owner가 겹칠 때 worker가 exact unowned subscopes와 risk를 돌려주는 과대 범위 신호다. 새 lifecycle state를 만들기보다 기존 return/HOLD 근거 안에서 recipient가 sibling dispatch 여부를 결정한다.

Return-ready 조건은 schema PASS만으로 충족되지 않는다. 최소한 required read의 실제 적용, exact source/media evidence, department-specific comparison 또는 observable proof, current message/audio/section과의 연결, output inventory/hash, recipient가 선택할 수 있는 survivor와 weaker-neighbor/rejected reason이 있어야 한다. 반대로 input·permission·evidence가 빠진 경우에는 억지 candidate를 만들지 않고 HOLD와 다음 smallest action을 반환한다.

#### 품질과 효율을 망치는 구현

아래 방식이라면 이 제안은 개별로이며 도입하지 않는 편이 낫다.

- 모든 부서에 전체 AGENTS, 정책, catalog와 다른 부서 산출물을 매번 붙인다.
- 부서별 skill 내용을 launch prompt에 복사해 두 군데에서 유지한다.
- 메시지 키워드만 바꾸는 고정 검색어·장면·카메라 예시를 기본값으로 둔다.
- 빈 creative field를 script가 generic prose나 placeholder로 채운다.
- 기계적 체크 완료를 creative PASS로 취급한다.
- worker에게 raw pool 최대화나 정해진 후보 수 채우기를 성공 조건으로 준다.
- Founder의 일반 대화를 자동 lock으로 바꾼다.
- 모든 worker의 전체 대화와 탈락 후보를 CDD에 계속 누적한다.

#### 기대 효과와 검증 방법

올바르게 구현하면 Founder의 반복 명령은 줄고, 누락된 skill/HOLD/return 조건 때문에 다시 부르는 횟수도 줄어든다. 토큰 절감은 프롬프트를 짧게 써서가 아니라 필요한 profile과 exact evidence만 로드하고 skill 전문을 복제하지 않는 데서 나온다. 품질은 자동으로 좋아지는 것이 아니라, 모든 worker가 같은 최소 증거와 명확한 실패 조건을 지키고 CDD가 비교 가능한 반환물을 받기 때문에 안정된다.

처음부터 전 부서에 적용하지 않는다. 한 section의 `Reference Research → CDD review → FP/01/02A` pilot에서 다음을 비교한다.

- Founder가 추가로 설명한 횟수
- dispatch당 입력/출력 words와 재호출 수
- HOLD가 늦게 발견된 횟수
- raw 후보 대비 CDD survivor와 02A 생존 수
- generic/noun-swap 또는 continuity 실패 수
- CDD가 source evidence를 다시 요청한 횟수

이 지표가 개선되지 않으면 양식을 늘리지 말고 중복 field와 부적절한 고정 문구를 제거한다.

## 6. Rhai 판단

### 6.1 지금 Rhai로 해야 하는가

아니다. 동적 실행 그래프를 만든다는 것과 Rhai를 도입한다는 것은 별개의 결정이다.

현재 먼저 필요한 것은 다음이다.

1. graph node/edge/state/owner/gate의 정본 schema
2. 기존 산출물에서 graph projection 생성
3. ready/running/hold/pass/invalidate 상태 전이
4. section owner lease와 join/fan-out 규칙
5. 기존 Ruby/Python validator가 같은 graph truth를 보도록 통합

이것은 현재 언어로도 구현할 수 있다. 지금 Rhai를 넣으면 YAML 계약, Ruby/Python validator, Rhai 조건식 사이에 세 번째 drift 지점이 생긴다.

### 6.2 나중에 반드시 해야 하는가

반드시 해야 하는 것은 아니다. 아래 조건이 생겼을 때만 유리하다.

- Rust 기반 단일 graph runtime을 실제로 도입한다.
- 조건 변경마다 Rust를 재컴파일하지 않고 제한된 정책식을 바꿀 필요가 잦다.
- 사용자 정의 규칙을 파일에서 안전하게 실행하되 파일·네트워크·secret 접근을 막아야 한다.
- 동일 guard를 여러 runner가 중복 구현하는 문제가 커졌다.

그때 Rhai는 `그래프 데이터`나 `creative judgment`가 아니라 sandboxed guard DSL로만 쓴다.

예:

```text
can_start_02b = section_02a_passed
             && exact_owner_lease_available
             && prompt_packet_hash_current
             && paid_generation_approved
```

### 6.3 기대 효과

| 항목 | Rhai 자체 효과 | 실제 기대치 |
|---|---|---|
| 창작 품질 | 직접 향상 없음 | 누락·잘못된 순서·stale input 실행을 줄여 품질 손실을 간접 방지 |
| 시간 | 작은 guard 평가는 빠름 | 전체 시간은 모델 조사·생성·검수가 지배하므로 단독 효과는 작음 |
| 토큰 | 직접 절감 없음 | 반복되는 상태 판단을 런타임이 처리하고 모델에는 ready node의 최소 Boot Pack만 주면 절감 가능 |
| 신뢰성 | 주요 장점 | 조건식의 sandbox, 결정론적 실행, 공통 guard 재사용 |
| 변경 비용 | 초기에는 큼 | Rust host가 없으면 언어·테스트·배포 표면만 증가 |

즉, 토큰 효율 향상의 핵심은 Rhai가 아니라 **graph projection + 최소 Boot Pack + pointer retrieval + 물리 세션 rollover**다. Rhai는 그 구조가 안정된 후 조건식을 안전하게 바꾸는 편의 계층이다.

## 7. 스키마·검사기 규모 감사

### 7.1 규모

2026-08-04 재검토 시점의 정적 규모는 다음과 같다.

| 표면 | 수 | 줄 | 단어 | bytes |
|---|---:|---:|---:|---:|
| `schemas/*.schema.json` | 116 | 44,512 | 101,209 | 1,500,488 |
| 전용 validate/check/audit 스크립트, 테스트 제외 | 51 | 23,192 | 83,618 | 1,010,236 |

전용 검사 스크립트 51개는 Ruby 39개, Python 12개다. 이름 기반 정적 집계이므로 모든 validation helper를 포괄하는 정본 수치는 아니지만, 유지보수 표면이 큰 것은 분명하다.

계약 registry가 현재 authoring contract로 관리하는 schema는 93개다. 전체 116개 중 23개는 inactive 또는 auxiliary로 분류된다. active stage가 직접 내는 output contract는 22개이고, active script가 참조하는 schema는 78개다. 즉 `스키마 파일 수 = 매 런에서 반드시 검증하는 단계 수`는 아니다.

### 7.2 배보다 배꼽이 큰가

두 가지로 나누어 답해야 한다.

1. **유지보수 표면은 비대하다.** schema 10.1만 단어와 전용 검사기 8.36만 단어는 작은 변경도 schema, custom validator, registry, surface hash, README와 test로 확산되기 쉽다.
2. **매 실행 비용이 항상 그만큼 큰 것은 아니다.** 현재 execution contract는 ordinary active check를 저지연 `idol_harness_frontier_check.rb`로 두고, whole-repository validation은 명시적 maintenance/closeout으로 제한한다. 이 scoped routing 자체는 올바르다.

따라서 문제는 검증을 많이 한다는 사실보다 다음 세 가지다.

- active/inactive/auxiliary 경계가 파일 목록만 봐서는 즉시 드러나지 않는다.
- 공통 무결성 코드가 검사기마다 반복된다.
- broad state checker 안에서 repo-global maintenance 검사가 다시 중첩되는 경로가 남아 있다.

### 7.3 반복 구현

이름 기반 검사기 집합을 검색하면 다음 반복이 보인다.

- 문서 로딩 함수 재구현: 22개 파일
- repository path 해석/containment 재구현: 26개 파일
- SHA-256 검사 재구현: 33개 파일
- generic JSON Schema helper 호출: 27개 파일
- subprocess 실행: 34개 파일

JSON Schema 다음에 cross-file hash, source identity, owner, Founder epoch, section coverage를 검사하는 semantic validator는 필요하다. 두 층을 없애면 안 된다. 다만 YAML load, duplicate-key, path containment, SHA binding, canonical structured hash, error formatting과 schema subprocess는 공통 validation core로 빼고, 각 stage validator는 자기 도메인 규칙만 갖는 편이 낫다.

가장 큰 전용 검사기 중 `validate_video_prompt_index.rb`는 2,571줄인데 현재 README상 inactive historical이다. `validate_cue_bpm_map.rb`, `validate_wardrobe_style_review.rb`, legacy-only `validate_skill_application_receipt.rb`, ordinary route가 금지된 Terra lifecycle validator도 active path와 분리 상태를 더 명확히 할 필요가 있다. 이는 즉시 삭제 근거가 아니라 archive/active 분류 감사 대상이다.

### 7.4 기존 효율 감사에서 이미 확인된 중복

`automation/state-reports/grok-harness-efficiency-audit.md`에는 다음이 이미 근거와 함께 정리되어 있다.

- 한 broad state check 안에서 surface registry schema가 동일 bytes에 두 번 적용됨
- run state check가 repo-global registry/surface/script/skill maintenance 검사를 함께 수행
- stage registry가 여러 subprocess에서 반복 파싱됨
- skill path extraction이 두 checker에서 중복 구현됨
- surface validator가 매번 전체 tracked surface를 hash함

이 항목은 새 validator를 더 만드는 방식으로 해결하면 안 된다. 기존 entrypoint의 호출 그래프를 줄이고 공통 구현으로 모아야 한다.

### 7.5 현재 중앙 검사 상태

재검토 시점의 read-only 결과는 다음과 같다.

| 검사 | 상태 | 결과 |
|---|---|---|
| stage registry | PASS | 5 phases, 19 stages |
| artifact routing | PASS | 19 stages exact coverage |
| contract version registry | PASS | 93 routes, 116 schema files, 23 inactive/auxiliary |
| surface version registry | PASS | 373 surfaces, 36 skills |
| skill-load profiles | PASS | 18 profiles, 18 skill bindings, 39 read bindings |
| instruction surface audit | PASS with warnings | startup 7,623 words; maintenance 10,026 words |
| skill contract check | PASS | 34 skills |
| model routing | PASS | one Overall, one visible startup CDD, flat workers, fresh section lineages |
| reference catalog | PASS | source indexes, analyzed units, usage history, still pointers valid |
| script registry | FAIL | 5 scripts/lib files가 `scripts/README.md`에 미기재 |

미기재 5개는 `idol_api_video_quality.py`, `idol_social_taxonomy.rb`, `validate_final_delivery_manifest.py`, `validate_founder_sequence_control.rb`, `validate_terra_section_lifecycle_receipt.rb`다. 이전 stale surface/hash 문제는 이 재검토 시점에는 통과했지만, worktree가 계속 수정 중이므로 다음 세션에서 같은 명령으로 재확인해야 한다.

### 7.6 스키마·검사기 정리 원칙

1. creative quality 판정을 위한 새 schema/validator를 만들지 않는다.
2. generic schema shape와 semantic/cross-file integrity 검사는 모두 유지하되 공통 로딩·경로·hash 구현을 공유한다.
3. active, auxiliary, historical을 하나의 validator registry에서 명시하고 기본 실행 프로필을 분리한다.
4. ordinary run은 frontier + current unit validator만 실행한다.
5. full registry/surface/script scan은 harness maintenance, closeout, release에서만 실행한다.
6. pure duplicate validation은 제거하되 producer/consumer, pre/post-write, paid/external trust boundary의 반복 검사는 유지한다.
7. inactive historical 파일의 이동·삭제·병합은 별도 Founder 명시 지시 전에는 하지 않는다.
8. Ruby/Python을 Rust/Rhai로 일괄 재작성하지 않는다. 먼저 각 언어 내부의 공통 validation core와 호출 routing을 정리한다.

## 8. 현재 감사에서 확인된 위험

- CDD skill의 전체 reference catalog EOF 요구가 검색형 reference-management 설계와 충돌한다.
- execution contract 요약, load profile, CDD skill의 실제 Required Reads가 서로 다른 입력 크기를 선언한다.
- persistent logical chat과 sequential physical session을 혼동하면 CDD가 두 권한으로 갈라지거나 영구 채팅이 다시 오염된다.
- active/auxiliary/historical schema 116개와 검사기 51개의 lifecycle 경계가 여러 registry와 README에 분산되어 있다.
- script registry는 현재 5개 미기재로 FAIL한다.
- 새 department dispatch, director dispatch index, reference working index는 계약상 존재하지만 실제 MV run instance가 아직 충분히 축적되지 않았다.
- worktree가 계속 수정 중이므로 모든 수치와 PASS/FAIL은 snapshot이다.

따라서 새 실행 엔진을 만들기 전에 CDD retrieval/load boundary와 validator routing을 먼저 닫고, 현재 구조로 한 실제 MV section을 Reference Research → CDD → FP → 01 → 02A까지 통과시켜 context 크기와 판단 품질을 측정하는 것이 안전하다.

## 9. 권고 우선순위

### P0 — 기존 CDD 계약 정렬

1. 새 Judgment Card/schema 없이 기존 Director skill의 Decision Set review 순서를 `개연성 → screen contribution → evidence → non-redundancy → feasibility`로 정렬한다.
2. CDD Required Reads에서 전체 reference catalog 직접 EOF 로딩을 제거하고 Reference Working Index의 pointer-only shortlist로 대체한다.
3. execution contract, load profile, CDD skill의 세 선언을 하나의 유효 로딩 규칙으로 맞춘다.
4. Overall → CDD → worker의 event-driven sleep/wake와 compact return payload를 명문화한다.
5. durable state는 파일에 두고 one active physical CDD session이 sequential rollover하는 규칙을 명문화한다.
6. broad context warning, deduped Founder-visible alert, safe checkpoint와 explicit Founder confirmation을 rollover보다 먼저 구현한다.
7. 기존 Department Dispatch v3, skill-load profile, agent role과 Director Boot Pack을 한 번의 `Compiled Launch Prompt`로 투영하는 양식을 확정한다.
8. CDD startup과 department worker launch를 분리하고, 메시지·target·audio·section role·reference gap이 current-job delta에 모두 들어가는지 확인한다.
9. 기존 Front Planning/Decision Set 필드를 재사용해 `need → observed evidence → bounded transfer → screen consequence → section placement` Reference Connection Contract를 launch와 CDD review에 정렬한다.
10. pre-02A reference search를 `official_original_first`로 정렬하고 AMV/MAD/fan edit는 explicit current-task Founder approval 없이는 검색·열람·분석·사용하지 않는다.
11. Founder main reference가 있으면 `main → origin verification → genealogy + functional discovery → placement`, 없으면 function-first official discovery를 사용한다.

### P1 — validator routing과 공통 기반

1. active/auxiliary/historical validator registry와 실행 profile을 명확히 한다.
2. broad state check에서 pure duplicate schema validation과 상시 repo-global scan을 분리한다.
3. Ruby/Python 각각의 shared validated-load, path/hash binding, error-report core를 만든다.
4. 두 번째로 큰 validator가 inactive historical인 상태를 포함해 archive 후보를 분류하되 삭제는 별도 승인으로 둔다.

### P2 — 동적 그래프 투영과 실제 pilot

1. 기존 stage/artifact/authority/invalidation 정보를 typed run graph로 투영한다.
2. graph는 creative truth를 쓰지 않고 상태·소유권·gate·dependency만 계산한다.
3. Reference Research → CDD Decision Set → FP → 01 → 02A의 한 section을 pilot으로 연결한다.
4. CDD input words, worker returns, comparison count, rerun 수, Founder 수정 수와 final survival을 측정한다.

### P3 — 레퍼런스 취향 학습

1. source quality, Founder affinity, current-title fit을 분리해서 기록한다.
2. Founder affinity는 검색 prior와 shortlist ranking에 사용한다.
3. final usage와 generation/playback 생존 결과를 되돌려 취향과 실제 작품 적합성이 어디서 갈리는지 검토한다.

### P4 — Rust/Rhai 재평가

현재 runner의 중복 guard와 drift 비용이 실제로 커졌다는 증거가 생길 때 Rust host를 검토한다. Rhai는 그 후 제한된 guard expression에만 사용한다.

## 10. 이번 문서에서 고정하는 설계 결정

1. 현재 큰 하네스 구조는 유지한다.
2. Overall Director는 하나이며 최종 승격 권한을 유지한다.
3. logical CDD는 지속되는 채팅이 아니라 durable decision lineage다.
4. pre-02A의 실제 Founder-facing 판단 주체는 CDD이며 Overall은 startup·promotion·final acceptance event에서만 깨어난다.
5. Overall, CDD와 worker는 polling하지 않고 완료·HOLD·권한 요청·milestone event로만 서로를 깨운다.
6. 실제 CDD는 한 시점에 하나의 physical session만 활성화하고 필요할 때 후속 session으로 교체한다.
7. context 오염 감지는 넓게 하되 어떤 trigger도 자동 rollover 권한이 아니다.
8. Founder-visible 경고, 안전 checkpoint와 explicit Founder confirmation 없이 physical CDD를 교체하지 않는다.
9. worker/context curator는 비서 역할을 할 수 있지만 CDD PASS/REJECT 권한을 갖지 않는다.
10. 병렬화는 CDD 권한 복제가 아니라 disjoint department/section worker에 적용한다.
11. Branch Cut의 최상위 판정은 whole-film → section → Core → neighbor 연결의 개연성이다.
12. 좋은 레퍼런스와 화면 선택 기준은 기존 Director skill 안에서 정렬하며 새 Card/schema/validator를 만들지 않는다.
13. 창작 최종 판단에 합산 총점을 쓰지 않는다. retrieval score는 검색 순서에만 사용할 수 있다.
14. 반복 활용 레퍼런스 이력은 Founder 취향 데이터가 맞지만 source quality와 current-title fit을 분리한다.
15. reference catalog는 정독 문서가 아니라 검색 가능한 pointer index로 사용한다.
16. 스키마와 semantic validator는 필요하지만 공통 기반과 scoped routing으로 유지비를 줄인다.
17. 동적 run graph는 필요하지만 Rhai는 지금의 선행 조건이 아니다.
18. Rhai는 후일 Rust graph host가 생길 때 제한된 deterministic guard 계층으로만 재검토한다.
19. CDD·worker 호출은 고정 창작 프롬프트가 아니라 `Studio Kernel + role profile + current-run Creative Delta`로 조립한다.
20. launch compiler는 기존 contract와 승인된 creative truth를 투영할 뿐, 메시지 해석·검색 방향·장면·PASS를 저작하지 않는다.
21. worker `returned`는 creative PASS가 아니며 CDD/지정 Director review와 promotion을 반드시 분리한다.
22. 부서별 skill·완료·HOLD 조건은 기존 skill-load profile을 단일 소스로 삼고 launch prompt에 전문을 복제하지 않는다.
23. 레퍼런스 관련성은 표면·mood 유사도가 아니라 current need, 실제 source evidence, transfer boundary, observable screen consequence와 exact section placement의 완결된 연결로 판정한다.
24. Reference Connection Contract는 새 schema/artifact가 아니라 기존 source lineage, reference unit, function analysis, section plan과 Decision Set을 묶는 launch/review 규격이다.
25. governing/supporting/section-bound 레퍼런스는 official/original professional primary source가 기본이다.
26. AMV/MAD/fan edit는 exact current-task Founder approval 없이는 agent가 자율적으로 검색·열람·다운로드·분석·등록·인용·배치하지 않는다. Founder 제공도 자동 승인이 아니다.
27. Founder main reference는 먼저 exact input을 보존하고 원천·공식본을 확인한 뒤 genealogy discovery와 functional discovery를 분리해 확장한다.
28. AMV/MAD 승인은 exact source, purpose와 allowed action에만 효력이 있고 direct scene binding은 별도 explicit lock을 요구한다.
