# IDOL 스토리라인·Goal·완수검토 closed-local 테스트 로그

- 검증일: 2026-08-07 (Asia/Seoul)
- 브랜치: `main`
- 검증 범위: Founder Alignment Storyline, FP→01→02A→02B 계보, 02B/CF50 프롬프트 참조, Goal-first Department Dispatch, 3층 완수 검토, Director single-flight review/promotion
- 실제 제작 run 검사/수정: 없음
- 기존 `runs/**`, `cf/runs/**` mutation: 없음 — 테스트가 만든 임시 fixture 디렉터리만 종료 시 삭제
- 이미지 생성·외부 검색·유료·공개 동작: 없음
- 기존 dirty assets/analytics/business-marketing/current-run 변경: 제외 및 보존

## 1. 최종 결과

```text
Ruby: 280 runs, 1,762 assertions, 0 failures, 0 errors
Python: 40 tests, OK
Model routing: PASS — IDOL execution contract v22
Skill/profile closure: PASS — 17 profiles, 18 skill bindings, 46 read bindings
Contract registry: PASS — 110 routes
Scoped diff check: PASS
```

실제 run을 열어 schema migration이나 production quality를 주장하지 않았다. 위 결과는
계약·스키마·validator·adapter·temp fixture의 closed-local 회귀검증 결과다.

## 2. Ruby 회귀검증

| 테스트 | runs | assertions | 결과 |
| --- | ---: | ---: | --- |
| `validate_department_dispatch_test.rb` | 39 | 142 | PASS |
| `idol_director_dispatch_index_test.rb` | 6 | 44 | PASS |
| `front_planning_readiness_schema_test.rb` | 12 | 36 | PASS |
| `idol_local_revision_propagation_test.rb` | 13 | 43 | PASS |
| `idol_02a_creative_context_review_test.rb` | 17 | 48 | PASS |
| `idol_prompt_packet_compile_test.rb` | 25 | 117 | PASS |
| `idol_html_review_board_test.rb` | 20 | 250 | PASS |
| `idol_review_decision_intake_test.rb` | 11 | 67 | PASS |
| `idol_harness_expert_gate_test.rb` | 7 | 26 | PASS |
| `idol_harness_state_front_planning_gate_test.rb` | 11 | 82 | PASS |
| `validate_schema_repair_candidate_test.rb` | 5 | 15 | PASS |
| `validate_terra_section_lifecycle_receipt_test.rb` | 6 | 17 | PASS |
| `validate_luna_section_lifecycle_receipt_test.rb` | 6 | 17 | PASS |
| `idol_prepare_image_render_correction_test.rb` | 6 | 40 | PASS |
| `idol_review_projection_assembler_test.rb` | 13 | 97 | PASS |
| `idol_harness_shadow_eval_test.rb` | 7 | 93 | PASS |
| `idol_harness_execution_preset_test.rb` | 5 | 107 | PASS |
| `idol_active_instruction_bias_test.rb` | 6 | 39 | PASS |
| `idol_video_prompt_storyboard_assist_test.rb` | 9 | 38 | PASS |
| `idol_storyboard_probe_contract_test.rb` | 49 | 382 | PASS |
| `idol_01r_reference_gap_worklist_test.rb` | 1 | 15 | PASS |
| `idol_harness_context_source_admission_test.rb` | 6 | 47 | PASS |

## 3. Python·정적 검증

| 검증 | 결과 |
| --- | --- |
| `python3 -m unittest cf.scripts.tests.test_cf_audience_contracts` | 12 tests PASS |
| `python3 -m unittest cf.scripts.tests.test_cf_harness_adapters` | 22 tests PASS |
| `python3 -m unittest scripts.tests.validate_idol_model_routing_agents_test` | 6 tests PASS |
| `python3 scripts/validate_idol_model_routing_agents.py` | PASS, v22 route |
| `ruby scripts/validate_harness_skill_load_profiles.rb --json` | PASS |
| `ruby scripts/validate_harness_contract_version_registry.rb` | PASS, 110 routes |
| staged surface/profile hash audit | PASS, 410 surfaces; staged profile hashes 일치 |
| modified Ruby/Python syntax checks | PASS |
| `git diff --check -- . ':(exclude)business-marketing/**'` | PASS |

## 4. 테스트 중 발견하고 닫은 회귀

### 4.1 03V video-prompt fixture

- 최초 증상: `idol_video_prompt_storyboard_assist_test.rb`의 positive fixture 3건 실패
- 원인: temp fixture가 새 active 02B `prompt-packets 2.2` 대신 `2.1`을 작성
- 수정: `scripts/tests/support/active_03v_fixture.rb`의 fixture version을 `2.2`로 갱신
- 재검증: 9 runs, 38 assertions PASS

### 4.2 retired storyboard probe의 child-shot 검증 helper

- 최초 증상: 49 runs 중 45 failures, 모두 `keyframe_shot_lock_errors` 미정의로 중단
- 원인: retired read-only probe는 기존 공용 02A child-shot validator를 계속 호출하지만
  공용 라이브러리에서 해당 deterministic helper가 제거된 상태였음
- 수정: 창작값을 작성하지 않는 기존 strict field/id/list validation helper를
  `scripts/lib/idol_02a_storyboard_contract.rb`에 복원
- 재검증: 49 runs, 382 assertions PASS

### 4.3 active 버전 소비자 연결

- 최초 증상: 스테이징 대조 중 01 v2.0 / 02A v2.3 / 02B v2.2로 올라간
  authoring 계약과 달리 일부 활성 상태검사·컨텍스트 팩·도움말·연결 모듈이
  01 v1.9 / 02A v2.2 / 02B v2.1을 계속 요구하는 것을 확인
- 영향: 새 02A v2.3 artifact가 `idol_harness_context_pack.rb`,
  `validate_harness_context_pack.rb`, `idol_harness_expert_gate.rb`,
  `idol_harness_state_check.rb`에서 정상 경로임에도 거절될 수 있었음
- 수정: 활성 소비자와 직접 연결된 schema/skill detail/help text를 현재 버전에 맞추고,
  staged registry/profile 해시를 실제 커밋 바이트 기준으로 재계산
- 재검증:
  - `idol_01r_reference_gap_worklist_test.rb`: 1 run, 15 assertions PASS
  - `idol_harness_context_source_admission_test.rb`: 6 runs, 47 assertions PASS
  - `idol_harness_expert_gate_test.rb`: 7 runs, 26 assertions PASS
  - `idol_harness_state_front_planning_gate_test.rb`: 11 runs, 82 assertions PASS
  - `idol_prompt_packet_compile_test.rb`: 25 runs, 117 assertions PASS

staged registry 검사에서 기존 정책상 git에 넣지 않는 로컬 OAuth reauth script 2개는
HEAD registry가 이미 참조하는 local-only baseline으로 분리했다. 이번 커밋에는 포함하지
않았고, 이번 개선 surface 410개와 skill/read profile 해시는 모두 staged bytes와 일치한다.

## 5. 전역 surface 진단

`validate_harness_surface_version_registry.rb`는 이번 scope 밖의 다음 기존 dirty surface를
계속 보고하므로 전역 exit는 `1`이다.

- `development/front-planning-workbench/ui/app.js`
- `development/front-planning-workbench/ui/startup-admission.js`
- `business-marketing/README.md`
- `business-marketing/planning/loom-sns-public-channel-operating-lock-v2.md`
- `business-marketing/decisions/2026-07-28-loom-sns-public-channel-operating-lock.md`
- `business-marketing/marketing/aurora-m-target-participation-and-go-to-market-v1.md`
- `business-marketing/planning/aurora-m-partial-oss-and-x-copublish-v1.md`

또한 `skills/idol-front-planning-director/SKILL.md`는 754줄로 reviewed ceiling 720 경고가
남아 있다. 현재 요청은 파일 split/compress 권한을 명시하지 않았으므로 protected
invariant에 따라 size remediation을 수행하지 않았다. 이번 기능 관련 contract hash,
skill profile과 registered surface hash는 위 제외 항목 외에 stale 항목이 없다.

## 6. 커밋 경계

이번 커밋은 위 개선의 canonical contract/schema/skill/validator/fixture와 이 로그만
대상으로 한다. 기존 run, generated media, asset deletion, analytics, social/business 문서,
current-run pointer와 다른 작업자의 dirty 변경은 스테이징하지 않는다.
