# Pinterest 레퍼런스 확장 최종 개선안

상태: 2026-08-08 활성 하네스 반영 완료. 이 문서의 `기존` 열은 변경 전
비교용이며 현재 권한은 AGENTS → policy → schema → skill 순으로 판단한다.

## 결론

Pinterest는 기존 메인·서브 레퍼런스를 대체하는 별도 체계가 아니다.
기존 01R 레퍼런스 조사량을 늘리는 추가 후보 풀이고, 특히 미감·공간·
재질·구도와 Major/Key Screen에서 예상되는 Core Cut의 화면을 잡는 데
사용한다. 새 단계나 별도 canonical 권한은 만들지 않는다. 대신 일반
World/Still 조사와 섞여 미감 탐색이 얕아지지 않도록 Pinterest
Visual/Composition 전용 물리 작업자와 전용 profile을 하나 둔다. World/Still은
자기 범위의 이미지 조사를 독립적으로 계속하고, 두 작업은 source territory와
출력 경로가 분리된 경우 provider capacity 안에서 병렬로 움직인다.

적용 대상은 전체 IDOL 하네스의 신규 또는 실질적으로 재개되는 작업이다.
기존에 PASS된 멤버 카드와 영향받지 않은 섹션은 이 정책만으로 다시 열지
않는다. SU 원본과 SU의 canonical 산출물은 수정 대상이 아니다. 앞서 만든
SU 시험 수집물은 가능성 확인용 임시 증거로만 남으며 전역 하네스의 정식
입력이나 새 기준 파일이 아니다.

## 변경 전과 변경 후

| 항목 | 기존 | 개선 후 |
|---|---|---|
| 섹션 레퍼런스 | 공식·원본 중심의 메인/서브 후보, 섹션당 3개 비교 바닥 | 기존 풀을 유지하고 Pinterest 후보를 활성 비주얼 섹션당 5장 이상 추가 |
| Founder 방향 정렬 | 완성 FP 후보와 섹션 방향 비교 | Direction Alignment에서 각 활성 비주얼 섹션 Pinterest 5장 이상을 개별 이미지와 contact sheet로 함께 비교 |
| 내부 FP Close | 기존 disposition으로 선택 | 활성 비주얼 섹션마다 Pinterest 3장 이상이 `applied` 또는 `combined`; 기존 레퍼런스는 유지 |
| 역할 | governing/supporting 기능 설명 | 각 핀에 `main_reference` 또는 `supporting_visual_reference`와 구체적 화면 역할 병기 |
| 검색 시작 | 매체별 검색 또는 넓은 무드 키워드 탐색 | 기본 모델이 먼저 제한 없이 무엇을 찾을지와 작품·인물·세계 lead를 만들고, 구체화된 뒤에 적합한 매체로 수집 |
| 검색어 | 긴 자연어 문장 또는 모든 매체에 같은 키워드 | 모델의 연상 방식은 제한하지 않으며, 구체적인 lead가 나온 뒤에만 작품명 검색이나 Pinterest용 짧은 명사 묶음을 사용 |
| 작업자 | 일반 World/Still 작업 안에서 Pinterest까지 처리 | Pinterest 미감·composition 전용 물리 작업자 1명을 독립 dispatch하고 World/Still과 안전한 범위에서 병렬 실행한 뒤 CDD 검토 후 Overall에 연결 |
| 관리 스키마 | Pinterest를 기존 source class에 억지로 편입할 위험 | 새 검색 스키마는 만들지 않고 기존 Reference Working Index에 `public_pinterest_pin` eligibility만 추가 |
| 멤버 비주얼 | 필요한 스타일링 근거를 CDD가 선별 | 새 카드·완전 리스타일 멤버만 멤버별 Pinterest 5장 이상 비교 후 선별 |
| 02A 이후 | 선택 레퍼런스의 최소 조합을 Branch Cut에 연결 | PASS된 핀만 같은 방식으로 연결하며 5장을 전부 첨부하지 않음 |
| 수집 화질 | 영상 래퍼가 낮은 해상도를 허용할 수 있었음 | 영상은 최소 720px 짧은 변, 기본 최대 1920px 긴 변; 핀도 최소 720px 짧은 변 |

## 이번 통합 하네스 개선과의 연결

Pinterest 확장은 아래 개선과 한 흐름으로 적용한다.

| 개선 축 | 활성 동작 |
|---|---|
| MV/티저 용어 | 사람에게 보이는 설명은 `전체 영상` 또는 `완성본`을 사용한다. `whole_film`은 기존 호환이 필요한 내부 scope token일 뿐이며 장편영화식 서사나 기승전결을 강제하지 않는다. 실제 소스 유형인 official visual/concept film, film/series source 명칭은 유지한다. |
| Founder 개입 | 첫 입력 뒤 내부 Discovery를 진행하고, Founder는 Direction Alignment에서 타깃·메시지·Major 방향·영상 형식·섹션 역할·섹션별 Pinterest 비교를 본다. 같은 Overall/CDD epoch가 내부 FP Close -> 역할별 01 -> 02A까지 진행한 뒤, Founder는 안정적인 리뷰보드의 02A Final Planning에서 정확한 FP Close storyline과 01/02A를 함께 본다. |
| 스토리라인 보존 | Direction Alignment에서 전체 영상과 모든 섹션을 설명하고, 내부 FP Close에서 planned cut/Key Screen까지 해시로 고정한다. 02A Final Planning은 이 설명을 요약 재작성하지 않고 read-only lineage로 그대로 보여준다. |
| 레퍼런스 역할 라우팅 | 세 generalist는 CDD의 섹션·기능 coverage와 매체에 따라 story/sequence, camera/composition, world/object/material challenge, conditional performance 중 각자 하나의 checkpoint만 받는다. 동일 역할 또는 섹션 중복은 CDD가 분리된 gap을 명시한 경우에만 허용한다. 모든 역할 모듈을 한 작업자에게 읽히지 않으며, 적게 읽는 것 자체가 목표가 아니라 맡은 판단이 전문적으로 결정 가능해질 때까지 조사한다. |
| 01 MV Director 라우팅 | 모든 01 작업은 direction/camera/bundle core와 마지막 integration을 읽는다. song/story, world/wardrobe/material, choreography, performance/body/gaze 세부 모듈은 실제 섹션 역할이 선언된 경우에만 추가한다. performance 방향은 choreography 권한을 자동으로 불러오지 않는다. |
| 리뷰보드 | 기계 전용 board coordinator가 한 안정적 `RUN/review/founder-workbench.html`에 Direction Alignment와 02A Final Planning을 투영한다. coordinator는 creative truth, PASS, promotion을 만들지 않는다. |
| 과거 얼굴 보조 스킬 | 세 얼굴 helper는 실제 2026-06 연구 런이 경로를 참조하므로 삭제하지 않는다. 대신 active skill-load profile에는 포함하지 않고 역사 증거용 isolated surface로만 유지한다. 현재 타이틀의 얼굴/멤버 정체성은 `idol-member-visual-identity`만 라우팅한다. |
| 검증 대체 | 최근 계약을 실제로 끝까지 따른 production run이 아직 없으므로, MV/티저 형식 중립성, 두 Founder gate, FP storyline 보존, 역할별 read 분리, 섹션별 Pinterest 수량, board 투영, 02B/유료 생성 권한 경계를 한 더미 통합 테스트에서 함께 검증한다. |

## Founder 개입과 수량 기준

1. 첫 방향 입력 이후 Founder Direction Alignment에서 활성 비주얼
   **섹션별로** Pinterest 후보를 최소 5장 보여준다.
2. 5장은 기존 메인·서브 후보에 **추가**된다. 기존 레퍼런스를 지우거나
   Pinterest로 자동 교체하지 않는다.
3. 각 후보에는 다음을 같이 표시한다.
   - 공개 pin URL 또는 pin id
   - 개별 로컬 이미지 경로와 SHA-256
   - 대상 섹션과 레퍼런스 기능
   - 제안 역할: `main_reference` 또는 `supporting_visual_reference`
   - Major, Key Screen, 예상 Core Cut에서 무엇을 지배하거나 보조하는지
4. Founder는 이미지를 개별적으로 PASS/HOLD/REJECT하거나 다른 레퍼런스와
   결합한다. sheet 전체를 하나의 레퍼런스로 PASS하지 않는다.
5. 내부 FP Close에서 활성 비주얼 섹션당 최소 3장의 Pinterest 이미지가
   `applied` 또는 `combined`로 남아야 한다. 이것은 선택·활용 바닥이지
   02A나 생성 입력에 3장 또는 5장을 무조건 붙이라는 뜻이 아니다.

## 메인과 서브를 나누는 기준

Pinterest라는 출처가 역할을 결정하지 않는다. 기존 레퍼런스 기준을 그대로
쓴다.

- `main_reference`: 해당 Major/Core Cut의 화면 문법이나 핵심 미감,
  공간 구조, 구도, 오브젝트 반응을 지배한다. 제거하면 그 화면의 핵심
  판단이 바뀐다.
- `supporting_visual_reference`: 메인이 갖지 못한 재질, 조명, 보조 구도,
  의상 디테일, 연속성 또는 실행 가능성을 보강한다. 메인의 문법을
  희석하지 않는다.

같은 핀이 한 Core Cut에서는 메인이고 다른 Core Cut에서는 서브일 수 있다.
따라서 역할 설명에는 항상 대상 섹션과 화면 단위를 함께 쓴다.

## 자유로운 방향 탐색과 매체별 수집의 분리

하네스는 기본 모델이 레퍼런스를 떠올리고 찾아가는 방식까지 제한하지 않는다.
Front Planning의 타깃·메시지·섹션 역할·메인 레퍼런스·미해결 화면 기능은
“어떤 종류의 것을 찾을지” 판단하는 문맥이며, 작품명이나 검색어를 미리
고정하는 필터가 아니다. 모델은 비유, 장르 지식, 작품·인물 연상, 시각적
유사성과 반대 사례를 자유롭게 사용해 구체적인 lead를 만들 수 있어야 한다.
이것은 Pinterest에만 적용하는 예외가 아니라 YouTube, TikTok, Instagram,
공식 작품·캠페인, 제작자 포트폴리오를 포함한 전체 레퍼런스 조사에 적용되는
전반 원칙이다.

예를 들어 “차가운 얼음의 공간이 펼쳐진 화면”이라는 필요에서 `겨울왕국`의
얼음 궁전을 떠올릴 수 있고, 애니메이션 맥락이 함께 있다면 `루키아의 만해`를
떠올릴 수도 있다. 이 연결을 하네스가 사전에 금지하거나, 정해진 명사 조합만
쓰도록 만들지 않는다. 먼저 모델이 왜 그 작품·인물·공간을 찾을지와 어느
Major/Key Screen 또는 Core Cut에 도움이 되는지를 제안한다.

탐색과 수집은 다음 두 층으로 나눈다.

1. **Reference lead 생성**: Overall/CDD와 할당된 모델이 찾을 이미지의 종류,
   필요한 미감·composition·동작/공간 기능, 가능한 작품·인물·세계 lead를
   자유롭게 뽑는다. 작품명을 처음부터 알고 있을 필요가 없고, 이 단계에는
   고정 검색어 형식이나 키워드 수 제한을 두지 않는다.
2. **구체화된 lead의 매체 수집**: 작품명, 인물, 장면, 미감 방향 또는
   composition 축이 충분히 구체화된 뒤에만 가장 적합한 매체와 보존 방법을
   고른다. 이때 검색어를 매체에 맞게 짧게 다듬을 수 있지만, 이는 운송·수집
   효율을 위한 실행 판단이지 모델의 연상을 제한하는 창작 규칙이 아니다.

Pinterest 작업자는 이 자유로운 lead 생성의 결과와 함께 Overall/CDD가 정한
무드를 반드시 이어받는다. 여기서 무드는 검색어 한두 개가 아니라 해당 화면이
유지해야 할 감각적 방향과 관찰 가능한 결과다. 예를 들면 색온도·노출·빛의
방향, 표면 재질, 공간 밀도와 깊이, 피사체 배치, crop/negative space,
composition의 긴장과 정적 정도를 포함한다. 작업자는 이 목표를 바꾸지 않되,
그 목표에 도달할 작품·인물·세계 lead와 세부 검색 방식은 자유롭게 확장한다.

구체적인 lead 이후의 예시는 다음과 같다.

```text
작품·인물 lead: Frozen ice palace / Rukia bankai / Cyberpunk Lucy
Pinterest 미감 확장: neon city / neon city rooftop / neon city wide shot
composition 확장: negative space / low angle / centered symmetry
```

이후 매체와 수집 방법은 고정하지 않고 소스 성격에 맞춘다.

- YouTube 또는 지원되는 공개 영상: 공식·원본 여부와 정확한 URL을 확인한 뒤
  등록된 `yt-dlp` 경로로 보존
- TikTok·Instagram의 공개 게시물: 현재 작업의 외부 접근 권한과 기존 미디어
  정책 안에서 공개 원문, 공개 자산 HTTPS 또는 허용된 요소 캡처 경로 사용
- Pinterest 공개 핀: 미감·색/재질·공간·still composition 후보를 HTTPS
  이미지 보존 또는 이미지 요소 캡처로 고정
- 공식 캠페인·에디토리얼·제작자 페이지: 공개 원문 이미지 자산과 크레딧 보존

`search_need_id`는 모델이 무엇을 떠올릴지 제한하는 입력값이 아니다. 자유로운
탐색에서 선택된 하나의 화면 필요 아래 YouTube, TikTok, Pinterest, Instagram,
웹에서 모인 후보를 함께 비교하기 위한 관리용 묶음이다. 어떤 작품이나 매체가
lead로 나왔다는 사실만으로 사용 권한이나 PASS가 생기지는 않으며, 기존
official/original·제한 소스·외부 접근·Founder gate는 그대로 적용한다.

무드 역시 별도 검색 gate가 아니다. Overall/CDD가 정한 무드 방향은 기존
Department Dispatch의 objective, requirement source binding과 해시로 정확히
전달하고, 작업자는 각 후보가 그 무드를 어떤 픽셀 근거로 이어받는지 Decision
Set에서 설명한다. 무드 입력이 없거나 stale하거나 메인 레퍼런스·메시지와
서로 모순되면 검색어를 임의로 만들어 메우지 않고 해당 범위만 HOLD한다.
이 hash binding은 전달값을 바꾸지 않았다는 무결성 증거이며, 명시적인 Founder
lock이 없는 무드 제안을 자동으로 lock으로 바꾸지는 않는다. 비교 결과에 따라
CDD가 기존 owning field에서 방향을 수정할 수 있다.

검색 썸네일, 읽을 수 없는 이미지, 텍스트 콜라주, near-duplicate, 선택된
화면 필요와 무관한 추천은 검토 후보에서 제외한다. 실제 공개 원문이나 pin과
읽을 수 있는 픽셀/재생 구간을 확인하기 전에는 후보로 계산하지 않는다.

후보가 좋은지 판단하는 바닥은 수량이 아니라 연결성이다. 각 후보는 메인
레퍼런스에서 무엇을 유지·보완·대조하는지, 메시지와 섹션의 어떤 화면 필요를
해결하는지, Major/Key Screen/Core Cut에서 실제로 무엇이 보이게 되는지를
설명해야 한다. 이 조건을 통과한 강한 Pinterest 후보가 섹션당 5장 모이면
검색을 닫으며, 숫자를 채우기 위해 약한 결과를 추가하지 않는다.

## 스키마 결정

Pinterest 검색어만을 위한 새 canonical 스키마나 별도 Pinterest 인덱스는
만들지 않는다. 검색 전 판단은 Front Planning, 작업 범위와 소유권은 기존
Department Dispatch, 후보 비교는 World/Still contact-sheet manifest와
Decision Set, 선택된 소스의 경로·해시·disposition은 Reference Working
Index가 이미 소유한다. 같은 의미를 다시 적는 검색 스키마는 관리 지점만
늘린다.

다만 기존 Reference Working Index의 source eligibility에는 공개 Pinterest
핀을 정직하게 나타내는 분류가 없으므로 `public_pinterest_pin`을 추가한다.
이는 새 계약이 아니라 기존 스키마의 최소 확장이다. 이 분류의 verified
identity는 공개 pin URL 또는 pin id와 로컬 이미지 경로/SHA-256의 결합을
뜻하며, 별도 제작자 원본을 확인했다는 주장으로 해석하지 않는다. 모델이 정한
탐색 방향, 선택된 lead와 이어받아야 할 무드는 해당 작업자의 기존 Dispatch
objective/requirement source binding과 Decision Set에 한 번만 남기고, 검색어
형식을 schema로 강제하지 않는다. 01 이후에는 선택된 개별 핀의 기능·역할·
경로·해시와 화면으로 번역된 무드 결과만 전달한다.

## 전달 경로

```text
Overall/CDD reference direction
   (찾을 종류 + 이어받을 무드 + composition 필요 + 대상 섹션)
-> 전용 Pinterest 작업자에게 hash-bound 전달
-> 공개 Pinterest 후보 수집
-> 기존 World/Still contact sheet 비교
-> Front Planning reference unit
   (`source_kind` + `reason/role` + disposition)
-> Founder가 개별 핀 PASS/combined
-> 01 reference application
   (`source_kind` + `role` 정확 복사)
-> 02A Branch Cut visual binding
   (필요한 최소 핀 조합만 선택)
-> 02B exact-copy prompt packet metadata
-> image-generation request scene input
   (`source_kind` + `role` 유지)
-> 별도 paid/external generation 승인
```

02B의 다섯 줄 프롬프트 형식은 바뀌지 않는다. 핀의 경로, 해시, 역할은
메타데이터로 보존하고, 렌더 프롬프트에는 실제로 보일 구도·공간·재질·행동
결과만 자연어로 번역한다.

## 수집 방식

캡처는 토큰 효율이 좋은 경로로 사용한다. 검색 결과 전부를 캡처하지 않고,
명명된 화면 필요와 시각 축을 통과한 shortlist만 로컬에 고정한다. 공개 pin의
읽을 수 있는 이미지 자산을 credential-free HTTPS로 보존하는 것이 우선이고,
자산을 직접 얻을 수 없을 때만 공개 no-account 페이지의 이미지 요소를
캡처한다. 전체 페이지 UI 캡처는 하지 않는다. `shortlist 캡처 -> contact
sheet 한 번 비교 -> 세부 판단이 필요한 개별 이미지만 재개방` 순서로 이미지
입력량을 제한한다. 로그인 세션, 쿠키 전달, 비공개 보드, 대량 스크래핑은
허용하지 않는다.

Codex와 Grok CLI는 모두 다음 공용 도구를 쓴다.

```text
scripts/idol_pinterest_public_capture.py
```

도구는 공개 pin URL, 실제 이미지 자산 또는 로컬 요소 캡처, 승인 근거,
제안 main/support 역할, 출력 경로를 받아 이미지 경로·해시·치수·방법을
기계적으로 기록한다. 검색, 미감 판단, 역할 결정, Founder PASS, 생성 첨부
승인은 하지 않는다.

영상은 등록된 `yt-dlp` 래퍼에서 480p 기준을 폐기한다. 가로형과 세로형에
동일하게 최소 720px 짧은 변을 요구하고, 기본 최대치는 1920px 긴 변이다.
다운로드 후 실제 영상 바이트의 너비와 높이를 다시 검사한 뒤에만 등록과
분석으로 넘긴다.

## 작업자 배분

일반 World/Still 작업과 별도로 Pinterest Visual/Composition 물리 작업자와
provider-neutral profile을 한 개 둔다. 새 단계·별도 creative authority·별도
canonical writer를 만드는 것은 아니다. 기존 이미지 source manifest,
capture helper, contact-sheet contract, Reference Working Index와 Department
Dispatch를 재사용하고, Pinterest 작업에 필요한 mood-carry와 platform-specific
책임만 전용 skill/profile이 소유한다. Overall Director가 Direction Alignment
범위에 이 작업을 등록하고, CDD가 실행·검토하며, 검토된 Decision Set과
Reference Working Index delta만 Overall에 돌려보낸다.

- 작업자는 Pinterest의 미감, 색/재질, 공간, subject placement, crop,
  negative space, still composition만 맡고 영상·동작 문법은 다루지 않는다.
- 작업자는 Overall/CDD가 정한 “무엇을 찾을지”와 이어받을 무드를 정확한
  source pointer/hash로 받되, 작품·인물·세계 lead를 떠올리고 Pinterest 안에서
  세부 검색어를 만드는 방법은 제한받지 않는다.
- 각 후보는 무드를 단어로 반복하지 않고 색온도, 빛, 재질, 공간 깊이, 배치,
  crop과 composition 중 실제 픽셀에서 확인되는 carry evidence를 남긴다.
- Pinterest 작업자는 공개 Pinterest cohort의 capture, pin identity, 5장 이상
  비교와 main/support 제안을 소유한다. 일반 World/Still은 자기 판단으로
  공간·세계·오브젝트·재질·조명·still composition 소스를 계속 찾으며,
  Pinterest quota를 채울 책임은 없다.
- World/Still이 탐색 중 좋은 pin lead를 우연히 발견하는 것은 금지하지 않는다.
  다만 같은 pin을 별도로 캡처·등록하지 않고 stable URL/id pointer만 Pinterest
  작업자에게 넘겨 Reference Working Index에서 중복을 막는다.
- 두 작업자는 서로 다른 dispatch id, source territory, candidate id namespace,
  output directory와 working-index delta path를 가진다. 같은 canonical index나
  board를 동시에 쓰지 않는다.
- 한 번에 한 섹션 또는 작은 연결 섹션 묶음의 5장 후보를 완성하고, 한 명이
  전체 범위를 순차 처리한다. 섹션마다 새 작업자를 만들지 않는다.
- 기본 reference assignment는 세 generalist, World/Still 한 명, Pinterest 한
  명의 다섯 독립 작업이다. 실행 폭은 고정 직렬이 아니라
  `min(5, provider live cap, review/backpressure 허용 폭)`으로 정한다. Grok처럼
  다섯 slot이 가능한 표면은 다섯 작업을 함께 열 수 있고, 현재 Codex처럼
  nonroot slot이 네 개인 표면은 네 작업을 병렬 실행하고 나머지 한 작업만
  다음 가용 slot에 큐잉한다. 어느 작업을 큐잉할지는 입력 readiness와 Founder
  review 시점으로 정하며 World/Still 반환을 Pinterest의 고정 선행조건으로
  만들지 않는다.
- 모든 비교는 개별 이미지와 uncropped contact sheet를 함께 사용한다.
- 조사·캡처·contact-sheet 제작은 병렬일 수 있지만, CDD는 반환물을 기존
  single-flight queue에서 하나씩 검토한다. Overall promotion과 canonical
  index/board merge도 계속 순차적이다.
- 작업자는 main/support와 화면 역할을 제안하지만, CDD/Overall/Founder가
  선택과 승인을 가진다.
- 멤버 5장 비교는 새 카드·완전 리스타일이 필요한 경우에만 기존 Member
  Visual Identity 작업 안에서 멤버별로 순차 수행하며 이 작업자와 섞지 않는다.

이 작업은 Codex와 Grok 어느 쪽에도 같은 profile과 dispatch로 배분할 수 있다.
단, Pinterest cohort에는 한 명의 활성 owner만 있으며 일반 World/Still과
후보 영역 또는 출력 경로가 겹치면 CDD가 launch 전에 범위를 다시 분리한다.

## 충돌 검토

| 비교 항목 | 판단 | 이유와 처리 |
|---|---|---|
| 전체 모델의 자유 탐색 vs Pinterest 무드 계승 | 충돌 없음 | 자유는 작품·인물·검색 경로를 찾는 방법이고, 무드는 작업자가 달성해야 할 화면 목표다. 검색법은 열어 두고 목표만 hash-bound로 전달한다. |
| Overall/CDD의 방향 vs 전용 작업자의 세부 발견 | 충돌 없음 | Overall/CDD가 찾을 종류·무드·화면 필요를 정하고, 작업자는 그 안에서 더 구체적인 작품·핀·composition을 발견한다. |
| 무드 계승 vs main/support 역할 | 충돌 없음 | 무드는 후보군 전체가 이어받는 미감 방향이고, main/support는 특정 Major/Core Cut에서 각 이미지가 맡는 사용 역할이다. |
| 무드 hash binding vs Founder lock | 충돌 없음 | 해시는 작업자에게 정확한 방향을 전달했다는 증거일 뿐이다. 명시적 Founder lock이 아니면 CDD 비교 과정에서 owning field를 수정할 수 있다. |
| 자유 탐색 vs 후보 품질 가드 | 충돌 없음 | 발견 방식은 제한하지 않지만, 후보로 남으려면 실제 픽셀과 화면 기여를 증명해야 한다. |
| 전용 Pinterest 작업자 vs 현재 활성 World/Still 계약 | **반영 완료, 충돌 없음** | Pinterest quota/capture 책임은 전용 skill/profile/dispatch로 이동했고 World/Still은 안정적인 pin URL/id lead pointer만 넘긴다. |
| World/Still의 자유 조사 vs Pinterest 전용 소유권 | 충돌 없음 | World/Still의 발견 방식을 제한하지 않는다. 우연히 발견한 pin은 lead pointer로 넘기고, Pinterest 작업자가 cohort capture/등록을 단일 소유해 중복만 방지한다. |
| 전용 작업자 vs 동시 작업 상한 | **반영 완료, 병렬 가능** | base reference assignment가 4개에서 5개로 늘어났다. 안전한 실행은 모두 직렬화하는 것이 아니라 실제 provider cap까지 병렬 실행하고 초과분만 큐잉하는 것이다. CDD review와 canonical promotion은 계속 single-flight다. |
| 새 검색 스키마 필요성 | 충돌 없음·추가 불필요 | 기존 Dispatch가 무드와 scope의 hash-bound 전달을 소유한다. 별도 검색 스키마는 중복이며 `public_pinterest_pin` eligibility 확장만 유지한다. |

## 변경 전과 현재 구현

아래 `변경 전`은 구현 이전 비교값이다. `현재 구현`이 활성 계약이다.

| 표면 | 변경 전 | 현재 구현 |
|---|---|---|
| 작업자 topology | 3 generalist + 1 World/Still, Pinterest는 World/Still 내부 | 3 generalist + 1 World/Still + 1 Pinterest Visual/Composition |
| World/Still | Pinterest 5장 cohort와 일반 still 조사를 함께 소유 | 일반 space/world/object/material/light/still-composition 조사를 독립 수행; Pinterest quota 제거 |
| Pinterest | 같은 World/Still lineage의 방향 합성 batch | Direction Alignment에 연결된 별도 skill/profile/dispatch/lineage/output path의 전용 작업 |
| 병렬 폭 | reference worker 최대 4, 다섯 번째 supplemental만 사후 queue | 목표 폭 5, 실제 폭은 provider cap과 backpressure 중 더 낮은 값; 가능한 작업은 병렬, 초과분만 queue |
| worker return | 네 base room이 CDD로 반환 | 다섯 disjoint worker가 독립 반환; CDD review는 기존 single-flight queue 유지 |
| canonical write | CDD/기계 writer/Overall이 순차 처리 | 변경 없음; worker 병렬화가 canonical 병렬 쓰기를 허용하지 않음 |
| 스키마 | 기존 reference/index/dispatch 구조 | 새 검색 스키마 없음; 기존 schema 재사용, `public_pinterest_pin` eligibility 유지 |

활성화 패치는 AGENTS, reference policy, production wiki, graph-engineering execution
contract/schema, skill-load profile, World/Still/Pinterest skill, 관련 validator/
test와 version registry에 함께 반영됐다. 이후 어느 한 표면만 되돌아가면 active
truth가 갈라지므로 HOLD다.

## 추가로 반영되는 위치

Pinterest가 들어갈 추가 위치는 새 단계가 아니라 기존 표면의 보강이다.

- Direction Alignment: 활성 비주얼 섹션별 5장 후보 비교와 역할 제안
- Department Dispatch / Director Dispatch Index: 전용 Pinterest 작업자의
  범위, lineage, CDD return, Overall promotion 경로
- skill-load profile: `pinterest_visual_composition_worker` 전용 profile과
  provider-cap 기반 병렬 launch/queue 규칙
- 내부 FP Close: 개별 pin disposition과 섹션당 3장 적용/조합 바닥
- Reference Working Index: 안정적인 pin identity와 disposition
- World/Still contact sheet: main/support와 화면 역할 표시
- 조건부 Member Visual Identity: 멤버별 5장 스타일링 후보 비교
- 01/02A/02B/image request: PASS된 핀의 역할·경로·해시 보존

PRE-00, Song Room, 03V, 04에는 Pinterest 조사 단계를 새로 넣지 않는다.
03V와 04는 이미 생성·PASS된 픽셀과 영상만 소비한다.

## 품질·비용 가드

- 5장은 중복 핀으로 숫자만 채우지 않는다. 최소 두 개 이상의 화면
  기능을 다루고, near-duplicate와 읽을 수 없는 썸네일은 제외한다.
- 어떤 연상이나 검색어로 발견했는지는 탈락 기준이 아니다. 다만 최종 후보는
  단순 키워드 일치나 플랫폼의 무관한 추천에 머물지 않고, 명명된 미감·공간·
  composition 필요와 읽을 수 있는 픽셀을 함께 설명해야 한다.
- Pinterest 후보는 전달받은 무드를 색온도·빛·재질·깊이·배치·crop·
  composition의 관찰 가능한 carry evidence로 증명해야 한다.
- 한 contact sheet는 비교 증거일 뿐 레퍼런스 1장으로 계산하지 않는다.
- 내부 FP Close에서 `applied`/`combined`가 아닌 핀은 01 이후로 전달하지 않는다.
- 02A는 Branch Cut에 필요한 최소 조합만 묶어 컨텍스트와 첨부 과부하를
  막는다.
- Pinterest 출처는 공개 접근과 보존 가능성이 변할 수 있으므로 로컬
  바이트와 해시를 즉시 고정한다.
- 레퍼런스 수집 승인은 유료 생성 승인이나 외부 업로드 승인이 아니다.

## 완료 판단

다음이 모두 성립하면 개선이 적용된 것으로 본다.

- 활성 비주얼 섹션마다 기존 풀과 별도로 Pinterest 후보 5장 이상이 있다.
- 기본 모델이 찾을 종류와 가능한 작품·인물·세계 lead를 자유롭게 만들 수 있고,
  이 원칙이 Pinterest뿐 아니라 전체 레퍼런스 조사에 적용되며, 특정 작품명을
  처음부터 강제하거나 검색어 형식으로 연상을 제한하지 않는다.
- Pinterest 작업자는 Overall/CDD의 hash-bound 무드 방향을 입력으로 받고,
  각 후보가 그 무드를 이어받는 관찰 가능한 픽셀 근거를 반환한다.
- lead가 구체화된 뒤에만 적합한 YouTube·TikTok·Pinterest·Instagram·웹
  수집 경로와 `yt-dlp`·공개 HTTPS·요소 캡처 방식을 선택한다.
- 캡처는 shortlist에만 수행되고 contact sheet 우선 비교를 거친다.
- 모든 핀에 개별 경로/해시, 기능, main/support 제안, 화면 역할이 있다.
- 선택 가능한 공개 핀은 Reference Working Index에서
  `public_pinterest_pin`으로 정직하게 분류된다.
- 내부 FP Close의 활성 비주얼 섹션마다 applied/combined 핀이 3장 이상 있다.
- 새/완전 리스타일 멤버만 멤버별 5장 이상을 비교하며 PASS 카드가 재개봉되지 않는다.
- 01 -> 02A -> 02B -> image request에서 `source_kind`와 `role`이 끊기지 않는다.
- 02A가 모든 후보를 붙이지 않고 Branch Cut별 최소 입력을 선택한다.
- Codex와 Grok이 같은 수집 도구·dispatch·Founder gate를 사용한다.
- Pinterest 전용 물리 작업자 한 명이 CDD 검토를 거쳐 Overall에 반환하며,
  일반 World/Still과 별도 lineage/output을 가지고 가능한 provider에서는 병렬
  실행되며 Member Visual Identity와 출력 범위가 겹치지 않는다.
- 다섯 base reference assignment 중 실제 provider cap까지 병렬 실행하고,
  초과분만 큐잉하며 CDD review와 canonical promotion은 single-flight를 유지한다.
- 영상과 Pinterest 이미지가 720px 짧은 변 기준을 통과한다.
- SU 원본과 canonical 산출물에는 변경이 없다.
