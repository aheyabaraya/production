# IDOL Harness Founder Decision

generated_at: 2026-06-11T02:28:22+09:00
run: `runs/2026-05-26/0526_SONG_SELECTION`
status: `active`

## Decision

- gate: `front_03v_playback_gate_S00-S03`
- section_range: `S00-S03`
- decision_id: `approve_front_chunk_generation`
- decision_label: Approve S00-S03 generation/playback route
- decision_input_text: S00-S03 생성 승인: route=grok_manual_drive_mirror
- flags: paid=true, external=true, continue_local=false, qa_pass=false
- explicit_approval_recorded: `true`
- approved_execution_route: `grok_manual_drive_mirror`
- next_local_section: `S04`
- next_action: Generate or collect the S00-S03 clips through the approved route (default route name: grok_manual_drive_mirror), then update only generation_playback_probe evidence after playback review.

## Sources

- current_next: `automation/current-next.yaml`
- founder_gate: `automation/founder-gates/2026-06-11-0526_SONG_SELECTION-03v-front-gate-s00-s03.yaml`
- next_unit: `automation/next-units/2026-06-11-0526_SONG_SELECTION-harness-next-unit.yaml`
- action_queue: `automation/action-queues/2026-06-11-0526_SONG_SELECTION-03v-action-queue.yaml`
- decision_source: founder_chat

## Forbidden Actions

- Do not mark section QA pass from structure alone.
- Do not treat Drive mirror prompt files as canonical.
- Do not run paid video generation without explicit founder approval.
- Do not mark S00-S03 section QA pass until generated playback evidence exists and is reviewed.
- Do not extend approval beyond S00-S03 unless the founder names that wider scope.
- Do not use this gate packet as upload, publish, Drive mutation, or platform API approval.