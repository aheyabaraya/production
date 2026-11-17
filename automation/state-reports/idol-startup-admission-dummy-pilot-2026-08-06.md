# IDOL Startup Admission 격리 더미 파일럿 결과

- 날짜: 2026-08-06 (Asia/Seoul)
- 결과: PASS
- 대상: startup prompt·skill version/hash admission 경로
- 실제 제작 런 사용: 없음
- SU 접근·수정: 없음
- 외부·유료·공개 동작: 없음 (`closed_local`, `forbidden`)
- canonical creative mutation: 없음

## 수용한 전주기

```text
Founder 더미 시작 문장
-> Overall Read Gate
-> 같은 Overall 물리 세션의 12블록 Compiled Launch
-> typed CDD route
-> CDD 12블록 Compiled Launch와 EOF return
-> bounded reference worker 1명
-> prepared -> launched -> returned
-> CDD exact-output review
-> Overall exact-copy promotion
```

Startup Admission은 기존 흐름 안의 입장 검증으로만 작동했다. 새 stage, Founder gate,
creative owner 또는 자동 creative PASS를 만들지 않았다. Workbench worker runtime은
`returned`까지만 기록하고 `director_review`와 `promotion`을 비워 두었다. 별도
Department Dispatch 검증 fixture에서만 CDD 검토와 Overall 승격을 명시적으로 작성해
정확한 output path/SHA, reviewer, promoter와 lifecycle을 검증했다.

## 검증 증거

| 검증 | 결과 |
| --- | --- |
| 격리 더미 전주기 | PASS — Overall -> CDD -> worker 1명 -> CDD review -> Overall promotion |
| Startup compiler | 5 runs, 56 assertions, 0 failures |
| Department Dispatch | 34 runs, 123 assertions, 0 failures |
| skill-load profiles | 17 profiles, 18 skill bindings, 46 read bindings, stale 0 |
| contract registry | 109 routes, mismatch 0 |
| surface registry | 410 surfaces, 36 skills, stale 0 |
| profile regression | 19 runs, 57 assertions, 0 failures |
| execution preset | 5 runs, 107 assertions, 0 failures |
| active instruction | 6 runs, 39 assertions, 0 failures |
| model routing | validator PASS, 6 tests PASS |
| instruction surface | audit PASS, 11 tests PASS |
| current-next | 3 runs, 27 assertions, 0 failures |
| Workbench Python | 75 tests PASS |
| Workbench UI | syntax and all smoke tests PASS |
| native Objective-C host | clang `-Werror` and integration checks PASS |

Instruction audit의 기존 target warning은 blocking ceiling이 아니라 진단값이며, 이번
변경이 수정하지 않은 `AGENTS.md`와 maintenance 표면에 남아 있다. 이를 없애려고 문서를
억지로 압축하거나 하네스 흐름을 바꾸지 않았다. 이번에 수정한 Front Planning skill은
현재 reviewed ceiling 안에 있다.

## 수용 경계

이 PASS는 startup/version-management 하네스가 등록 profile, EOF read set, current SHA,
동일 세션 전달, worker return, 감독 검토와 승격 경계를 보존한다는 증거다. 특정 실제
런의 창작 결과가 PASS했다는 뜻은 아니다. 실제 런 검증은 Founder가 이후 별도 요청할
때만 새 범위로 연다.
