# IDOL Harness Creativity Audit - 2026-07-04

Purpose: record the July 4, 2026 harness adjustment that keeps IDOL MV planning from collapsing into uniform performance-video direction, generic face/profile prompting, or one-pass whole-track storyboarding.

## Findings

- The active bottleneck was not a missing top-level harness stage. The issue was that deep front planning, section-level directing, reference transfer, and prebuilt album visual assets could be separated too loosely, leaving 01/02A/02B to rediscover or simplify them.
- A second check found one active quota-like contract outside the emotion work:
  the structured PRE-00 radar schema required exactly five route candidates.
  That could make automation pad a brief with weak or duplicate ideas.
- `front-planning readiness` should remain the single source-preserving front-planning contract. It now owns optional `section_work_plan` for section-sharded story/director work and optional `album_visual_asset_plan` for title-specific visual assets.
- Album visual assets are not mood references. For INK-style runs, member solo sheets, identity-source copies, wardrobe/look sheets, space sheets, object-system sheets, background/world references, and keyframe inserts must travel forward as the current title's visual package.
- Downstream image generation should not fall back to generic profile photos or unrelated boards when a matching title-specific album asset exists. Face identity remains face-only; solo/space/object/wardrobe/keyframe assets attach only through the scene-reference path when allowed.

## Claude Fable vs GPT Read

External sources checked on 2026-07-04:

- Anthropic model docs say Claude Fable 5 is Anthropic's most capable widely released model for demanding reasoning and long-horizon agentic work, with a 1M-token context window and 128k output limit: https://platform.claude.com/docs/en/about-claude/models/overview
- OpenAI docs say GPT-5.5 is the flagship model for complex reasoning/coding and complex production workflows, and that it benefits from outcome-first prompts, explicit success criteria, evidence rules, and representative evaluation examples: https://developers.openai.com/api/docs/guides/latest-model
- Creativity benchmarks remain mixed and domain-sensitive. LitBench focuses on creative-writing evaluation reliability and found Claude 3.7 Sonnet the strongest off-the-shelf judge, not proof that every Claude model is always the best writer or MV director: https://arxiv.org/abs/2507.00769
- AGC-Bench reports model strengths differ by creative domain and that prompting explicitly for creativity matters: https://arxiv.org/abs/2607.01152

Conclusion: treat the claim "Claude Fable is always more creative than GPT for MV/scenario planning" as unproven. It is reasonable to expect Claude Fable to be strong for long, nuanced planning, but the safer IDOL response is to remove the process patterns that make any model generic: one-pass whole-track authoring, vague mood language, missing route alternatives, missing section merge checks, and loose asset handoff.

## Harness Response

- Keep front planning as one founder-facing readiness handoff, but allow internal section sharding through `section_work_plan`.
- Let structured PRE-00 radar declare a 3-7 route scope. Five remains a normal
  review shape, not a quota; hold instead of padding weak route candidates.
- Require section slices to preserve audio cue, lyric/no-lyric guard, source/reference function, visible action, composition/camera lock, transition-in/out, status, and downstream 01 transfer.
- Make 01 choose concrete section-director routes before 02A when a section is storytelling-heavy, reference-heavy, long, dense, or at risk of uniform treatment.
- Let front planning and 01/02A correct one-background or one-visible-feeling flattening through `space_visible_feeling_progression_policy`, section `space_visible_feeling_arc`, and `director_chain.space_visible_feeling_progression`; repeated spaces or feelings are allowed only when their function changes.
- Do not keep the draft `space_emotion_*` names as compatibility aliases; the visible-feeling names replace them.
- Let 02A/02B expand keyframes by creative proof need, not legacy global packet caps.
- Carry title-specific album visual assets through `album_visual_asset_plan`, then into 01A text locks, 02A source refs, 02B scene-reference inputs, or 03V handoff according to each asset's declared role.
- Allow 02B scene/composition references from `assets/members/album-assets/**` only when front-planning readiness declares the exact asset and the prompt packet records the usage rule and transfer locks.
- Follow-up stage-level application check is recorded in
  `automation/skill-stage-creativity-application-audit-2026-07-04.md`. It
  confirms that creativity support should stay inside existing stage contracts:
  01 route alternatives, 02A/02B proof-based expansion, 03V `planning_carry`,
  and 04 `story_flow_continuity` / `directorial_transition_intent`, rather than
  becoming another top-level stage.

## Removed Or Consolidated

- No files were deleted for this audit.
- The fixed PRE-00 five-route quota was removed from the active schema and
  skill/automation wording. Existing five-route records remain valid.
- The separate concept of a front-planning section-lock stage was consolidated into `front-planning-readiness.section_work_plan`.
- The generic profile-photo fallback was demoted: it is now allowed only when the matching album identity-source copy or album visual asset is missing, blocked, or not declared for the current title.
- Loose visual-board usage was narrowed: album member solo, space, object, wardrobe/look, and keyframe insert images must be declared and routed as text locks or scene-reference inputs instead of being rediscovered ad hoc in 02B.
