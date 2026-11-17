# IDOL 외부 생성 생태계·로컬 런타임 도입 감사

```yaml
status: complete_read_only_audit
canonical_owner: automation/harness-ecosystem-adoption-audit-2026-07-12.md
decision_date: 2026-07-12
last_method_review: 2026-08-30
decision_priority: quality_first_privacy_before_efficiency
external_mutation: none
live_provider_test: none
```

## 결론

1. Higgsfield가 운영하는 공식 원격 MCP와 REST API, Python 클라이언트,
   CLI, 공개 스킬은 실제로 존재한다. 그러나 현재 확인된 연결은
   **Higgsfield의 원격 MCP를 Claude가 호출하는 별도 서비스 연결**이지,
   Anthropic과 Higgsfield가 공동 운영하는 네이티브 API·공동 계정·공동
   결제 체계가 아니다.
2. Higgsfield 공개 약관과 개인정보 처리방침상 입력 이미지·영상·프롬프트와
   출력물에 대한 학습·개선·마케팅 목적의 광범위한 이용 가능성을 배제할 수
   없다. 따라서 **비공개 멤버 신원/얼굴 자료, Founder 제공 레퍼런스,
   미공개 음원·가사·앨범 키비주얼, 내부 기획·프롬프트, 선택된 프레임은
   Higgsfield MCP/API/CLI/웹에 전송 금지**다. 별도 계약이 이 위험을
   명시적으로 해소하고, 정확한 자산과 작업에 대한 Founder 승인이 있을
   때만 재검토한다.
3. 지금 도입할 것은 외부 생성기가 아니라 **provider-neutral 요청 계약,
   권리·비용·승인 게이트, mock 기반 상태 전이 검증**이다. 실제 MCP 연결,
   SDK/CLI 설치, 인증, 유료 생성은 모두 보류한다.
4. IDOL 미디어 Python 런타임은 `.venv-video`의 Python 3.12.13과 고정
   패키지 세트가 현재 전부 일치하고 공식 점검을 통과한다. 시스템 Python
   3.14.6으로 성급히 교체하면 얻는 이익보다 미디어 의존성 회귀 위험이 더
   크다. **현재 3.12 런타임을 유지**하고, 향후 신규 비미디어 어댑터만
   격리된 3.13/3.14 환경과 이중 CI로 검증한다.
5. 시스템 Ruby는 2.6.10이며 핵심 하네스의 많은 스크립트가
   `#!/usr/bin/env ruby`를 사용한다. 이번 작업에서는 변경하지 않는다.
   Python 업그레이드와 섞지 말고 별도의 재현 가능한 Ruby 런타임·회귀
   테스트 감사로 다뤄야 한다.

이 문서는 한 번의 canonical 감사 결과다. 새 사실이 생기면 이 파일을
고치고 Git 이력을 사용하며, 날짜·버전별 보고서 더미를 만들지 않는다.

## Promptwhat Soul2 방법론 부분 채택

2026-08-30에 `promptwhat/promptwhat-soul2-skill`의 `v1.0.3`, commit
`24c1e6e051d80546b5aff8c9fb771576849b01aa`를 별도 임시 clone에서 읽기
전용 검토했다. IDOL에는 외부 스킬, 샘플 프롬프트, preset, Soul ID,
Higgsfield 실행 lane을 설치하거나 등록하지 않았다.

채택 범위는 기존 02B `Visible details` 안의 조건부 completeness review와
다음 세 가지 source-bound 질문뿐이다: 장면이 요구하는 생활/사용 흔적,
선택된 재질의 가시적 마감과 빛·접촉 반응, 이미 screen job을 받은 색의
선택적 반복. 이는 새 필드나 기본 미학이 아니며, current Cut/current-title
visual/selected reference에 근거가 없으면 작성하지 않는다. 인구학적 identity,
필수 beauty treatment, 착장 개수, 자동 소품, HEX palette, provider preset,
샘플 밀도 모사는 계속 금지한다. 동봉 `golden-prompts.md`는 외부 저장소의
MIT 범위 밖이므로 복사·로딩·실행 calibration에 사용하지 않는다.

## 감사 범위와 증거 경계

이번 결론은 두 증거 층을 분리해 사용했다.

- **Terra Max 공개 조사 세션**: 2026-07-12에 공식 제공자 문서와 공식
  저장소만 조사했다. 로컬 IDOL 저장소, 인증 정보, 비공개 파일은 읽거나
  전송하지 않았고, 로그인·미디어 업로드·유료 API 호출·외부 변경을 하지
  않았다.
- **로컬 읽기 전용 점검**: 현재 IDOL 저장소의 런타임 버전, 의존성
  선언, 실행 래퍼, 스크립트 shebang과 Python 3.14 전환 민감 패턴만
  확인했다. 네트워크 호출, 패키지 설치, 가상환경 변경, 업그레이드는 하지
  않았다.

공개 페이지의 기능·가격·모델 목록은 바뀔 수 있다. 실제 도입 시점에는
공식 문서를 다시 확인해야 하며, 이 보고서는 실행 승인이 아니다.

## 확인된 외부 생태계

### Higgsfield

| 표면 | 공개 자료로 확인된 범위 | IDOL 판단 |
| --- | --- | --- |
| 원격 MCP | Higgsfield가 `https://mcp.higgsfield.ai/mcp`를 운영하며 Claude web, Cowork, Claude Code의 Connectors에 추가하도록 안내한다. Higgsfield 계정 로그인과 크레딧을 사용한다. [Higgsfield MCP](https://higgsfield.ai/mcp) | 기술적으로 사용 가능하나 현재 보호 자산에는 금지 |
| REST API | 모델별 비동기 제출, request ID 상태 확인, queued 작업 취소, 결과 URL 반환이 문서화되어 있다. [API 시작 안내](https://docs.higgsfield.ai/docs/how-to/introduction) | provider adapter 후보, 구현·호출은 보류 |
| Image-to-video | `image_url`과 motion prompt를 받는 I2V 흐름과 짧은 반복, request ID 보존, webhook 권고가 문서화되어 있다. [Video guide](https://docs.higgsfield.ai/docs/guides/video) | 공개·합성 자산 평가에만 후보 |
| Webhook | `completed`, `failed`, `nsfw` 최종 상태와 최대 2시간 재시도가 문서화되어 있다. [Webhook guide](https://docs.higgsfield.ai/docs/how-to/webhooks) | 서명 검증 방식이 공개 확인되지 않아 live 도입 보류 |
| Python client | 동기/비동기 제출, polling, 취소, callback, 파일/PIL 업로드를 제공하며 공개 문서상 Python 3.8+다. [SDK 안내](https://docs.higgsfield.ai/docs/how-to/sdk), [공식 저장소](https://github.com/higgsfield-ai/higgsfield-client) | 신규 격리 어댑터 후보, 미디어 venv에 설치 금지 |
| CLI | 모델/워크플로 검색, 비용 조회, 생성·대기·조회·목록·업로드, JSON 출력을 제공한다. [공식 CLI](https://github.com/higgsfield-ai/cli) | 인증·결제 실행 표면이므로 현재 설치/연결 보류 |
| 공개 skills | generation, Soul ID, product photoshoot 등과 Claude Code/Codex/Cursor용 manifest를 공개한다. [공식 skills 저장소](https://github.com/higgsfield-ai/skills) | 코드·명령·권한을 별도 검토한 뒤 참고만 가능; 직접 설치 금지 |

Higgsfield 공개 페이지마다 모델 수 표현이 `30+`, `40+`, `100+`로
일치하지 않는다. 모델 ID나 개수를 하네스에 고정하지 말고, 도입이 승인된
시점의 인증된 live catalog/schema 조회를 실행 진실로 사용해야 한다.

### Claude 연결의 실제 범위

공식적으로 확인된 직접 연결은 다음 구조다.

```text
Claude web / Cowork / Claude Code
        -> public remote MCP
Higgsfield-operated MCP endpoint
        -> Higgsfield account and credits
Higgsfield generation service
```

Anthropic 역시 Claude가 공개 원격 MCP 서버를 custom connector로 연결할
수 있다고 설명하며, 외부 서비스가 데이터 접근·외부 행동을 수행할 수
있으므로 신뢰한 서버만 사용하라고 경고한다.
[Anthropic custom connector 안내](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)

확인되지 않은 것은 다음과 같다.

- Anthropic과 Higgsfield의 공동/네이티브 API, 공동 인증 또는 공동 결제
- Anthropic 공식 디렉터리의 Higgsfield 승인·추천
- 로그인 없이 검증 가능한 모델별 전체 크레딧 표
- Higgsfield webhook 요청의 공식 서명·검증 규약
- 독립된 Anthropic `Assets API`라는 공개 제품
- Higgsfield JavaScript/TypeScript SDK의 일관된 지원 상태

따라서 Claude가 기획하고 Higgsfield가 생성하는 미래 루프도 하나의
서비스처럼 취급하지 않는다. Claude는 typed job을 제안하고, 정책·권리·비용·
Founder 승인을 통과한 deterministic executor만 외부 job을 제출하는 구조가
필수다. Anthropic의 client tool 방식도 애플리케이션이 tool call을 실제로
실행하고 결과를 다시 제공하는 분리를 전제로 한다.
[Claude tool-use contract](https://platform.claude.com/docs/en/agents-and-tools/tool-use/how-tool-use-works)

## 개인정보·권리·IP 판단

Higgsfield는 공개 약관에서 입력·출력의 소유권을 주장하지 않고 상업적
출력 사용을 제한하지 않는다고 설명하는 한편, 입력과 출력에 대해 학습,
제품 개선, moderation, 마케팅 등을 위한 광범위하고 영구적인 이용허락을
규정한다. 또한 타인의 이미지·likeness를 업로드할 권리와 동의 책임을
사용자에게 둔다. [Higgsfield Terms](https://higgsfield.ai/terms-of-use-agreement),
[Privacy Policy](https://higgsfield.ai/privacy-policy),
[Trust](https://higgsfield.ai/trust)

IDOL에서는 법적 최소선보다 보수적으로 다음 자료를 민감한 신원·창작
자산으로 취급한다.

- 멤버 얼굴, 신체, 목소리, Soul/identity 학습 자료와 face-only reference
- Founder가 제공한 이미지·영상·연락처·비공개 메모와 그 선택 crop/frame
- 미공개 음원, 가사, 안무, 콘티, 00~05 기획, 프롬프트, key visual
- 계약 또는 라이선스 범위가 확인되지 않은 외부 레퍼런스 원본·파생물
- `business-marketing/**`, 비밀 설정, 계정·토큰·쿠키 등 비공개 운영 자료

이 자료는 Higgsfield뿐 아니라 Claude Files/Skills/Managed Agents/MCP
Connector 같은 비-ZDR 또는 제3자 처리 표면에도 자동 전송하지 않는다.
Anthropic 공개 문서상 기본 API 보존은 최대 30일이고, Files API, Skills
API, Managed Agents, MCP Connector는 ZDR 대상이 아니다.
[Anthropic 보존 정책](https://privacy.anthropic.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data),
[ZDR 범위](https://privacy.anthropic.com/en/articles/8956058-i-have-a-zero-data-retention-agreement-with-anthropic-what-products-does-it-apply-to)

## IDOL 적용·보류·금지 매트릭스

| 제안 | 상태 | 근거와 다음 조건 |
| --- | --- | --- |
| provider-neutral creative-job/request schema | **적용** | provider 이름과 무관하게 source hash, prompt hash, reference order, rights class, approval state, max cost, request ID, status, result hash를 소유한다. 외부 호출 권한은 포함하지 않는다. |
| 로컬 mock/fixture 상태 전이 테스트 | **적용** | `queued -> running -> completed/failed/nsfw/cancelled`, 중복 webhook, polling fallback, idempotency를 비용 없이 검증한다. |
| Agent Skills/MCP의 구조 개념 | **적용** | procedure는 skill, 실행은 좁은 typed tool/adapter로 분리한다. 공개 사양은 [Agent Skills](https://agentskills.io/specification)와 [MCP](https://modelcontextprotocol.io/specification/2025-11-25)를 참조한다. |
| Higgsfield 공개 skills 내용 검토 | **보류** | 별도 sandbox에서 provenance, shell/network 권한, 설치 hook, 외부 전송, 결제 경로를 먼저 검토한다. IDOL canonical skill에 그대로 복사하거나 설치하지 않는다. |
| Higgsfield REST/Python/CLI adapter | **보류** | 법무·개인정보 검토, 자산 분류, mock 테스트, model allowlist, 비용 상한, exact-job Founder 승인이 선행되어야 한다. |
| Higgsfield remote MCP를 Claude에 연결 | **보류/보호 자산 금지** | 공개·합성·권리 명확 자산만 사용하는 격리 capability test가 별도 승인될 때 재검토한다. MCP 연결 자체가 생성·크레딧 사용 권한을 넓혀서는 안 된다. |
| 공개 synthetic I2V capability test | **보류** | 비canonical sandbox, 소액 상한, 정확한 유료 승인, 결과 보존·삭제 계획, 동일 입력 provider 비교가 필요하다. |
| 비공개 멤버/Founder/앨범 자산 Higgsfield 전송 | **금지** | 공개 약관만으로는 학습·마케팅·장기 라이선스 위험을 해소하지 못한다. 별도 계약과 exact-asset Founder 승인이 없으면 예외가 없다. |
| 프롬프트·레퍼런스 자동 업로드 또는 모델의 직접 submit | **금지** | 모델은 job을 작성/검토할 수 있으나, 실행은 rights/cost/approval을 검증한 좁은 executor만 수행해야 한다. |
| Higgsfield SDK를 `.venv-video`에 추가 | **금지** | 현재 재현 가능한 미디어 런타임을 오염시킨다. 승인 후에도 별도 venv/lockfile을 사용한다. |
| JS/TS SDK를 즉시 production 표준으로 채택 | **보류** | 공식 문서와 공식 저장소의 지원 설명이 일치할 때까지 REST 또는 검증된 Python client가 더 안전하다. |

## 로컬 런타임 감사

### 확인된 현재 상태

| 항목 | 읽기 전용 확인 결과 | 판단 |
| --- | --- | --- |
| 시스템 Python | `/opt/homebrew/bin/python3`, Python 3.14.6 | 최신 언어 검증 후보일 뿐 IDOL 미디어 실행 진실이 아님 |
| IDOL 미디어 Python | `.venv-video/bin/python`, Python 3.12.13 | 현재 유지 |
| 미디어 의존성 | `requirements-video.txt`의 11개 exact pin이 모두 설치 버전과 일치 | 현재 baseline 통과 |
| 미디어 도구 | ffmpeg, ffprobe, ffplay, sox, yt-dlp 발견 | 설치 상태 확인일 뿐 외부 다운로드 승인이 아님 |
| Python 선언 | repo-visible Python manifest는 [`requirements-video.txt`](../requirements-video.txt) 하나; `pyproject.toml`, `Pipfile`, Poetry/uv lock은 없음 | 신규 어댑터는 미디어 환경과 분리된 manifest/lock 필요 |
| Ruby | 시스템 Ruby 2.6.10p210 | 변경 금지; 별도 런타임 감사 필요 |
| Ruby 선언 | repo-visible `Gemfile`, `Gemfile.lock`, gemspec 없음; 현재 Ruby 스크립트의 직접 require는 표준/기본 라이브러리 중심 | 재현성 위험을 Python 전환과 섞지 말고 별도 해결 |
| shebang | `#!/usr/bin/env python3` 53개, `#!/usr/bin/env ruby` 56개 | PATH 변경이 실행기를 바꿀 수 있으므로 canonical wrapper/CI가 중요 |

[`scripts/idol-video-python`](../scripts/idol-video-python) `--check`는 Python 3.12.13에서 numpy, scipy,
librosa, soundfile, moviepy, OpenCV, imageio, imageio-ffmpeg, Pillow, PyYAML,
jsonschema의 존재와 exact pin을 모두 통과했다. 반면 시스템 Python은
3.14.6이므로 bare `python3`와 미디어 런타임이 다르다. 이 차이는 의도된
격리이며, 통합을 이유로 없애면 안 된다.

현재 Python 스크립트에서 `multiprocessing` start method, 직접
`__annotations__` reflection, `asyncio` child-watcher, `distutils`,
`pkg_resources` 사용은 검색되지 않았다. 이는 알려진 3.14 전환 위험 일부가
현재 표면에 없다는 뜻일 뿐, 3.14 호환성을 증명하지는 않는다. C extension과
미디어 패키지의 wheel/codec/성능 회귀는 실제 테스트가 필요하다.

### Python 업그레이드 권고

공개 조사 시점의 Python 최신 안정판은 3.14.6이고 3.13도 지원 중이다.
3.10은 2026년 10월 지원 종료 예정이며, 3.15는 아직 pre-release다.
[Python downloads](https://www.python.org/downloads/),
[지원 버전 현황](https://devguide.python.org/versions/)

그러나 IDOL 로컬 진실을 적용한 권고 순서는 다음과 같다.

1. `.venv-video` Python 3.12.13과 현재 pin은 그대로 유지한다.
2. 향후 승인된 Higgsfield/Claude provider adapter가 실제로 필요해질 때만
   별도의 비미디어 venv와 lockfile을 만든다. 첫 대상은 3.13, 검증 대상은
   3.14로 두거나, 의존성이 모두 확인되면 3.14를 주 대상으로 삼는다.
3. 같은 fixture와 mock contract suite를 3.13/3.14에서 실행한다. 실제
   provider 호출은 이 단계에 포함하지 않는다.
4. 미디어 런타임 3.14 후보는 모든 pin의 설치 가능성, 전체 Python 단위
   테스트, 대표 audio decode/feature extraction, image encode/contact sheet,
   video probe/render, ffmpeg round-trip, hash/metadata 동일성 또는 승인된
   차이를 검증한 뒤에만 만든다.
5. Python 3.14의 Unix `multiprocessing` 기본 start-method 변화,
   deferred annotations, 제거된 asyncio/stdlib API를 다시 정적 검색하고,
   프로세스·reflection 경로가 추가됐으면 명시적 테스트를 둔다.
   [Python 3.14 변경사항](https://docs.python.org/3.14/whatsnew/3.14.html)
6. 후보 환경이 통과해도 즉시 교체하지 않는다. current와 candidate의 동일
   입력 결과, 시간, 메모리, 실패율을 비교하고 quality non-regression 후
   Founder가 전환을 승인한다.

Higgsfield Python client의 공개 하한은 Python 3.8, Claude Agent SDK는
Python 3.10+다. 이 하한은 권장 버전이 아니다. 신규 통합이 승인된다면
3.13/3.14에서 재현 가능한 잠금과 CI를 갖추되, 해당 SDK를 미디어 venv에
섞지 않는다. [Higgsfield SDK](https://docs.higgsfield.ai/docs/how-to/sdk),
[Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview)

### 업그레이드 전 필수 검증

- 현재 `scripts/idol-video-python --check` 결과를 baseline receipt로 보존
- 모든 repo Python/Ruby contract test와 schema validator 통과
- 대표 음원·영상 fixture의 duration, frame count, sample rate, color/codec,
  생성 hash 또는 허용 오차 비교
- 외부 provider 없이 mock request/status/webhook/cancel/retry 테스트
- 의존성 lock, interpreter path, ffmpeg/ffprobe path를 명시한 재현 가능한
  실행기
- current/candidate 병렬 운용과 즉시 rollback 경로
- 실제 외부 호출 단계에는 별도의 rights/privacy/cost/Founder 승인

## 미래 외부 생성 루프의 최소 안전 계약

실제 도입 승인이 나더라도 모델이나 MCP에 광범위한 filesystem, shell,
network, purchase, publish 권한을 주지 않는다. 실행 도구는 다음 정도로
제한한다.

```text
estimate_cost(job)
submit_job(approved_job)
get_status(request_id)
cancel_queued_job(request_id)
fetch_result(request_id, controlled_destination)
```

각 job은 최소한 다음을 hash-bound로 가져야 한다.

- 입력 자산의 canonical owner, SHA-256, rights/consent class, external-transfer
  eligibility
- 모델이 작성한 prompt와 prompt hash, reference 순서와 역할
- provider/model/duration/resolution allowlist와 최대 비용
- 정확한 Founder paid/external-transfer approval receipt
- request ID, 중복 제출 방지 key, 상태 전이, webhook/polling evidence
- 결과 다운로드 hash, QA verdict, provider 보존 만료 전 controlled storage
- 실패/NSFW/취소/재시도와 비용 처리, 삭제·보존 기록

Higgsfield 결과는 공개 FAQ상 최소 7일 접근 가능하고 이후 제거될 수
있으므로, 승인된 결과는 제어된 저장소로 즉시 가져오고 provenance를 남겨야
한다. [Higgsfield FAQ](https://docs.higgsfield.ai/docs/help/faq)

## 도입 게이트

아래 순서를 모두 통과하기 전에는 live 연결을 만들지 않는다.

1. 별도 계약을 포함한 법무·개인정보·입출력 이용권 검토
2. 자산 등급과 source license/likeness consent 기록
3. provider-neutral schema와 deterministic executor의 local-only 구현
4. mock contract, 비용 상한, idempotency, webhook/polling 회귀 테스트
5. 공개·합성 fixture만 사용한 비canonical capability test 계획
6. exact-job 외부 전송 및 paid-generation Founder 승인
7. prompt adherence, 시간 일관성, 허용된 identity 유지, artifact, 실제
   비용·지연을 포함한 동일 입력 비교
8. 결과 보존·삭제·rollback과 provider 변경 시 회귀 테스트

현재 게이트 상태는 **1번 이전의 보류**다. 그러므로 이번 감사가 허용하는
후속 작업은 계약/schema/mock 설계와 공개 문서 재검증뿐이다.

## 미검증·후속 확인 목록

- 인증 후 실제 live model/schema/cost catalog와 plan별 rate limit
- Higgsfield webhook signature 또는 대체 인증 통제
- 별도 enterprise 계약이 입력·출력 학습, 마케팅, 보존, 삭제를 어떻게
  변경하는지
- IDOL 사용 지역·멤버 계약·레퍼런스 라이선스에 맞는 likeness/voice 법적
  검토
- Anthropic 조직 계약의 실제 retention/ZDR 범위와 제3자 MCP 처리 범위
- Higgsfield JS/TS SDK V2의 공식 지원 상태
- 공개 Higgsfield skills의 실제 설치 hook, shell/network 권한, telemetry,
  upload/credit-spend 경로
- Python 3.13/3.14에서의 IDOL 전체 test matrix와 미디어 golden fixture 결과
- Ruby 재현 가능한 버전/의존성 고정과 최신 후보에서의 하네스 회귀 결과

이 항목들은 “없다”는 결론이 아니라 공개·로컬 읽기 전용 감사에서 확인되지
않았다는 뜻이다. 추정으로 자동화 계약을 채우지 않는다.
