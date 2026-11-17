# IDOL Graph Engineering Current Next

derived_from: `automation/current-next.yaml`
source_yaml_sha256: `05c4b2c2d86621ba69824dece360f6080b87c3be883a529175bb0061195c7c4c`
generated_at: `2026-08-03T21:46:45+09:00`
run: `runs/aurora-m/su/0801_SU`
status: `selected`
owner: `codex`
selected_next_unit: `su_front_planning_reauthor_after_founder_hold`

## Current Decision

- unit: `su_front_planning_reauthor_after_founder_hold`
- unit_type: `front_planning_reauthor`
- unit_status: `in_progress`
- unit_owner: `codex`
- requires_founder_decision: `false`
- action: Founder HOLD를 반영해 v12와 ONE MOVE의 흐름·Major Scene을 새 창작 컨텍스트에서 제외하고, 통과된 SU 곡·메시지·멤버 비주얼만으로 S00–S08 전체 흐름과 Major Scene을 새로 제안한다.

### Additional Selected Unit Details

```yaml
canonical_front_planning: runs/aurora-m/su/0801_SU/research/front-planning-readiness-v12.yaml
founder_workbench_manifest: runs/aurora-m/su/0801_SU/review/manifests/founder-workbench.yaml
founder_workbench_html: runs/aurora-m/su/0801_SU/review/founder-workbench.html
front_planning_status: hold
downstream_status: held_before_01_and_02a
current_title_member_visuals:
- M11
- M09
- M05
- M01
- M07
image_generation_authorized: false
paid_generation_authorized: false
external_execution_authorized: false
founder_intervention_receipt: runs/aurora-m/su/0801_SU/review/founder-interventions/FI_SU_FP_V12_HOLD_REAUTHOR_NO_ONE_MOVE_20260803.yaml
```
- validate_after: `새 전체 흐름과 S00–S08 Major Scene이 현재 곡·메시지에서 독립적으로 나왔는지 Overall Director가 검토한 뒤에만 새 fp_final Founder 검토를 연다.`
- reason: Founder가 v12의 흐름과 Major Scene에 ONE MOVE 기획 내용이 섹여 있다고 판단해 전체 Front Planning을 HOLD했다. 그러므로 다음 합법적 소유자는 Founder가 아니라 Overall Director와 별도 Creative Development Director이다.

## Founder Response Examples


## Allowed Decisions


## Sources

- next_unit: ``
- founder_gate: ``
- action_queue: ``

## Automation Boundaries

- SU v12의 창작 의미와 founder_review 상태를 보존한다.
- 현재 검토는 Promote 모드이며 선택 경계와 Workbench만 검증한다. Founder PASS 전에는 01 이후 Execute 검증이나 전체 저장소 감사를 자동 실행하지 않는다.
- 기존 SU skill receipt는 정확히 일치하는 변경 전 바이트의 동결 증거로만 읽고 새로 만들거나 갱신하지 않는다.
- 새 작업이나 바이트 변경은 Department Dispatch, runtime digest, 감독 검토와 승격을 요구한다.
- 이전 runs는 이 v18 구현을 이유로 소급 수정하거나 이름을 바꾸지 않는다.
- 한 개 Workbench에서 discovery, direction_synthesis, fp_final 모드를 사용하되 지금의 정본 검토는 fp_final이다.

## Forbidden Actions

- Founder Front Planning PASS 전에 01, 02A, 02B, 이미지 또는 영상 생성을 시작하지 않는다.
- 이전 ONE MOVE의 Major, 공간, 비주얼, 프롬프트 또는 영수증을 SU 정본으로 승격하지 않는다.
- 보드 노출이나 파일 존재를 Founder PASS 또는 멤버 비주얼 승격으로 해석하지 않는다.
- 유료 생성, 외부 실행, 업로드, 게시를 승인으로 추정하지 않는다.
- Aurora V2, M-code, K-code를 사용하지 않는다.

## Refresh Commands

- `scripts/idol-video-python scripts/validate_json_schema.py schemas/harness-current-next.schema.json automation/current-next.yaml`
- `ruby scripts/idol_harness_current_next.rb --render-from-yaml automation/current-next.yaml --output-md automation/current-next.md --write`
- `ruby scripts/idol_harness_frontier_check.rb runs/aurora-m/su/0801_SU --json`
