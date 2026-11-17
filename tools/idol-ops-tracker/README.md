# IDOL Ops Control

IDOL 저장소 안의 여러 운영 축을 한 화면에서 관리하는 로컬 전용 트래커다.
IDOL MV, Business & Marketing, CF, Loom Web을 같은 포트폴리오로 보되 각 lane의 원본 authority와 gate는 합치지 않는다.

이 도구는 production harness가 아니다. 원본 문서와 run artifact는 읽기 전용이며, 화면에서 저장한 값은 오직 `tools/idol-ops-tracker/data/tracker.json`에만 기록된다.

## 실행

추가 설치는 필요 없다. IDOL 저장소 루트에서 실행한다.

```bash
python3 tools/idol-ops-tracker/start.py
```

브라우저에서 아래 주소를 연다.

```text
http://127.0.0.1:4177
```

### macOS 우측 상단 패널

메뉴 막대에서 열고 닫을 수 있는 로컬 AppKit 패널을 빌드한다.

```bash
tools/idol-ops-tracker/macos/build-app.sh
open "tools/idol-ops-tracker/dist/IDOL Ops Control.app"
```

패널은 `compact.html`을 우측 상단 floating panel로 띄우며 `초소형(Peek) → 반접기 요약(Compact) → 전체(Expanded)` 세 크기를 버튼 하나로 전환한다. 반접기 요약은 전체 높이의 약 절반에서 열린 MV family와 MAIN/SUB 전환만 남긴다. macOS 표준 노란색 최소화 버튼도 사용할 수 있고, 마지막 패널 크기는 다음 실행에도 복원된다. 실행 중인 tracker가 없으면 같은 폴더의 `start.py`를 loopback 전용으로 시작한다. 앱을 종료하면 앱이 직접 시작했던 서버도 함께 종료한다. 현재 빌드는 로그인 항목을 등록하거나 `/Applications`에 설치하지 않는다.

데이터와 source probe만 검사하고 종료하려면:

```bash
python3 tools/idol-ops-tracker/start.py --check
```

## 첫 사용 순서

1. 관리할 프로젝트를 연다.
2. 실제 목표, 시작일, 목표일, 다음 점검일, 다음 행동을 입력한다.
3. 현재 run 또는 근거 artifact의 repo-relative 경로를 프로젝트·마일스톤에 연결한다.
4. 마일스톤 범위와 가중치 합계가 100인지 확인하고 저장한다.
5. Founder가 현재 기준을 승인한 시점에만 `기준선 잠금`을 누른다.
6. 이후 각 마일스톤의 상태, gate, evidence를 갱신한다.

초기 네 프로젝트는 모두 `기준선 대기`다. 실제 active run이나 일정이 하나로 확정되지 않은 상태를 임의로 추정하지 않기 위해 완료율도 `—`로 시작한다.

## 완료율 기준

마일스톤 가중치는 다음 세 조건을 모두 만족할 때만 완료율에 들어간다.

- `status = completed`
- `gate = PASS` 또는 `not_required`
- 필수 evidence 경로가 IDOL 저장소 안의 실제 파일로 존재 (폴더 경로는 증거로 세지 않음)

Founder 기준선이 잠기지 않았으면 완료율은 계산하지 않는다. 기준선이 잠긴 뒤에는 마일스톤 ID, 범위명, 가중치, 증거 필수 여부를 서버에서 변경 불가로 보호한다.

프로젝트 자체를 `완료`로 닫으려면 기준선이 잠겨 있고, 모든 마일스톤이 위 조건으로 검증 완료되었으며, 열린 blocker가 없어야 한다. 화면 표기만으로 포트폴리오에서 일을 숨길 수 없도록 서버와 데이터 validator가 함께 막는다.

AI 작업의 `running`, 대화량, 파일 수, 토큰 수, 반환 완료는 프로젝트 완료율에 포함하지 않는다. AI 작업은 `실행 상태`와 `결과 검증 상태`를 따로 기록하며, 실제 마일스톤 근거로 승격된 경우에만 프로젝트 쪽 evidence로 연결한다.

## 화면 구성

- `전체 현황`: 검증 완료율, 점검 필요 프로젝트, 다음 행동, lane 구성
- `프로젝트`: 목표·기간·기준선·마일스톤·gate·evidence·blocker
- `일정`: 프로젝트 기간 경과율과 검증 완료율 비교, 목표일·점검일 모음
- `Founder 결정`: 실행 상태와 분리된 승인·보류·기각 기록
- `AI 작업`: task/thread 단위 실행·반환·검토 기록
- `MV 작업자`: 현재 MV run의 등록된 Department Dispatch를 lineage별 최신 attempt로 접은 읽기 전용 view
- `원본·신뢰도`: 연결한 경로의 존재·수정 시각과 제한적인 Git 신호

패널은 열린 MV를 album/title family로 묶어 한눈에 보여 준다. 같은 `previous_run_root`에서 갈라진 분기는 최신 `run_sequence`를 `MAIN`, 나머지를 `SUB`로 표시하고 기준 run은 `BASE`로 접어 둔다. MAIN/SUB는 트래커의 탐색 역할일 뿐 production owner나 Founder 선택을 새로 만들지 않는다. 반접기 요약은 열린 MV family와 선택한 MAIN/SUB만 남기고, 전체 화면에서는 run 상세, MV/CF deadline, worker 상태와 attention 상위 6개를 본다. 전체 worker 목록은 `MV 작업자` 화면에서 dispatch, stage, section, recipient, review, promotion을 구분해 본다.

## 하네스 보호 경계

| 구분 | 허용 |
|---|---|
| 읽기 | 연결된 repo 경로 metadata, MV `run-manifest` routing/created_at, DDI 또는 Department Dispatch의 lineage/lifecycle/scope/recipient/review/promotion 필드, CF run 폴더 birthtime |
| Git 읽기 | branch, HEAD commit, tracked 변경 신호; untracked 전체 탐색은 하지 않음 |
| 쓰기 | `tools/idol-ops-tracker/data/tracker.json` 한 파일의 원자적 교체 |
| 네트워크 | 없음; 서버는 loopback 주소만 허용 |
| 외부 전송 | 없음 |
| 원본 수정 | 없음 |
| 삭제 | UI/API에 삭제 action 없음 |

다음 영역은 이 도구가 수정하지 않는다.

- `runs/**`
- `automation/**`
- `schemas/**`
- `skills/**`
- `policies/**`
- `wiki/**`
- `cf/**`, `web/**`, `business-marketing/**`의 원본

트래커의 PASS는 production artifact의 Founder/Overall Director PASS를 새로 만들거나 대체하지 않는다. 트래커에는 이미 존재하는 source truth와 승인 상태를 기록할 뿐이다.

## 데이터 백업과 이동

원본 데이터는 `data/tracker.json`이다. 서버 실행 중에는 `/api/export`에서 derived 상태를 포함한 JSON을 읽을 수 있다. 복구가 필요하면 서버를 끈 뒤 `tracker.json`을 버전 관리나 별도 백업에서 되돌린다.

## 검증

```bash
node --check tools/idol-ops-tracker/web/app.js
python3 -m unittest discover -s tools/idol-ops-tracker/tests -v
python3 tools/idol-ops-tracker/start.py --check
```

## MV/CF deadline

- MV: `run-manifest.created_at` 기준 7일. 없을 때만 run 폴더 birthtime/mtime을 fallback으로 쓴다.
- CF: `cf/runs/CF_*` 폴더 birthtime 기준 3일. birthtime을 읽을 수 없는 파일시스템에서는 mtime fallback을 명시한다.
- deadline은 tracker의 운영 신호이며 production PASS, Founder gate, release authority를 만들지 않는다.

## 현재 한계

- 패널의 MV board는 CF, SNS 운영, still board, retirement 같은 비-MV run을 제외한다. album/title 안에서는 `active`/`hold`를 우선하고 최신 `run_sequence`를 MAIN 표시로 선택한다. 명시적인 canonical main-selector가 생기면 그 source가 이 표시 규칙보다 우선되어야 한다.
- DDI가 없으면 `work/department-dispatches/*.yaml`을 직접 읽어 lineage별 최신 attempt로 접는다. 이 경우 화면에 `DIRECT PROJECTION · INCOMPLETE`를 표시하며 서로 연결되지 않은 stale lineage를 임의로 종료 처리하지 않는다.
- 원본 본문을 수집하거나 의미를 자동 판정하지 않는다. evidence는 경로 존재 여부만 기계 검증한다.
- Git dirty probe는 tracked 파일만 본다. IDOL root 전체 스캔은 응답 지연을 피하려고 기본 비활성화하여 `미확인`으로 표시하고, 별도 Web repo만 확인한다.
- 기준선의 물질적 변경은 v1에서 자동 unlock하지 않는다. 새 기준을 만들 때는 별도 프로젝트 또는 명시적인 후속 버전 설계가 필요하다.
