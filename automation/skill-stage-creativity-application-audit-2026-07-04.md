# IDOL Skill Stage Creativity Application Audit - 2026-07-04

Purpose: check whether the active IDOL skill harness applies creativity support across the full MV pipeline without forcing one uniform performance-video plan, generic profile-image fallback, or unnecessary extra harness stages.

## Decision

No new top-level harness stage is needed.

The current split should stay:

```text
front-planning-readiness.section_work_plan
-> 01 section_gate / lyric_to_scene_thinking section route alternatives
-> 02A section shards and keyframe/cut locks
-> 02B prompt packets
-> 03V section_shards and cue-level planning_carry
-> 04 section_workflow with story_flow_continuity / directorial_transition_intent
-> merged canonical artifact
```

This supports asynchronous section work while leaving the founder-facing flow unified. The sections can be worked independently, then merged through continuity checks instead of making the founder manage many separate planning documents.

## Stage Application Matrix

| Stage | Active skill or contract | Creative job | Creativity risk | Guard now required |
| --- | --- | --- | --- | --- |
| PRE-00 / research | `idol-research-radar`, trend/source records | Find routes, references, audience tension, and source functions before a content unit is selected. | Trend scans can become formulaic, or a fixed five-route shape can force weak filler ideas. | Treat references as source function, quality bar, camera route, object behavior, or edit logic, not style-only mood. Declare the route count for the current pass; five is a normal review shape, not a quota. |
| Suno/manual prompt | `idol-suno-prompt` | Convert reference-song function, hook delivery, and whole-song composition into promptable sound/lyric variants. | Prompting can become abstract genre stacking. | Keep reference-song delivery method, section function, hook placement, and listening QC visible. |
| Selected audio / lyric bridge | `idol-song-lock`, `idol-lyrics-direction-bridge`, selected-audio analysis, audio-motion director map | Lock the actual song's section cues, lyric/no-lyric meaning guards, and visible motion/edit seeds. | Lyric summaries can dominate image direction. | Lyrics are guards unless the line is the audible turn; audio/section cues and backing rhythm must produce observable body/object/camera/edit timing. |
| Track board / 00 / 00A | `idol-nucleus`, title registry, track creative board | Hold the content unit's message, audience receive, song support, world, and production lane. | The nucleus can over-compress complex story choices. | Use front-planning readiness when deep notes exist; preserve source refs and section-level open questions instead of flattening them into mood. |
| Front planning | `front-planning-readiness.schema.json` | Single source-preserving handoff for founder/Codex section notes, current-title album visual assets, source maps, space/visible-feeling progression, and open gates. | A separate section-lock stage would fragment the harness; a weak plan can also flatten the MV into one background and one feeling. | Keep `section_work_plan`, `space_visible_feeling_progression_policy`, `space_visible_feeling_arc`, and `album_visual_asset_plan` inside front-planning readiness; do not create another top-level stage for the same job. |
| 01 direction | `idol-mv-director` | Expand song, storyline, section carrier, MV direction, source mining, camera coverage, choreography/performance activation, visual locks, and space/visible-feeling progression into one director-chain map. | A single director pass can still flatten sections if it repeats message, space, or camera grammar without story-state change. | Section route choices may be story/narrative, object/system, camera/composition, performance/body, environment/empty-space, or hybrid. The selected route must explain why it fits the section and how its space/background/screen-read feeling continues or changes adjacent sections. |
| 01R source mining | `idol-mv-director` and `mv-direction-reference-mining` | Mine reference scenes and timestamps for useful screen solutions. | Reference work can become copy suppression or generic inspiration. | Preserve source identity and the exact followed surface: camera route, world rule, object behavior, section turn, edit logic, styling rule, or scene grammar. |
| 01A visual locks | `track-visual-board` contract inside 01 bundle | Lock wardrobe, background, object, unit character, and album-specific visual assets before generation. | Generic profile or loose board fallback. | Use current-title `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` when declared; INK paths are examples or INK-owned only. |
| 02 / 02A / 02B | `idol-generation` | Build generation map, music-led storyboard, prompt packets, preview review, and export/preflight records. | Old packet counts or face-heavy review shapes can become caps. | No global 02A/02B upper cap. Split only when the section cue, composition, object/space state, camera handoff, or edit endpoint needs it. Frame-subject mix is a diagnostic, not a quota. |
| 02B image assets | `album_visual_asset_plan`, prompt-packet scene-reference fields | Carry title-specific member solo sheets, wardrobe/look sheets, spaces, objects, and keyframe inserts into generation. | Album assets can be treated as mood references or replaced by old profiles. | Use declared current-title assets first, with usage rule and transfer lock; face identity remains face-only and scene/composition assets use the allowed scene-reference route. |
| 03V video prompts | `idol-video-prompt`, `video-prompt-manifest.schema.json` | Turn passed images plus song/section context into image-anchored body, object, camera, and story-flow motion. | 03V can become motion-only choreography activation. | Use `planning_carry_sources`, section shard `planning_carry_scope`, and cue `planning_carry` when upstream planning exists; actual image pixels still control identity, styling, start state, and endpoint. |
| 04 edit | `idol-editing-qc`, `edit-map.schema.json` | Choose exact source, timing, speed, cutpoints, recipes, previews, and QC. | Edit can follow only visible motion or upstream prompt-slot order. | Section shards may record `story_flow_continuity`, `space_visible_feeling_progression`, and `directorial_transition_intent`; 04 owns exact edit timing and rejects mechanical upstream seconds as edit commands. |
| 04FX | `idol-edit-finishing-fx` | Optional post-preview finishing for transition bridges, beat accents, tone/source-family unification, and world/object continuity. | FX can hide weak footage or become a new stage. | Use only after a section/chunk edit preview passes; if timing, source choice, speed, or geometry changes, return to 04 edit recipe. |
| Package / social | `idol-social-metadata-upload`, `reels-tiktok-template`, `x-posting-template` | Write message-first public metadata and platform drafts after media is ready. | Public copy can flatten the MV into generic idol/performance claims. | Preserve title message, viewer receive, release context, founder gates, and platform boundary; no upload without explicit approval. |
| Face/helper skills | `idol-human-face-realism-control`, `idol-photoreal-human-face-lock`, `idol-surgical-face-architecture`, `idol-member-teaser-portrait`, `idol-track-poster`, `idol-grid-overlay`, `kling` | Isolated support for identity, portrait, poster, grid, or external prompt tasks. | Helper skills can pull MV planning back toward face-first or tool-first output. | Use only when the task specifically needs them; they do not override 01/02A/02B/03V section story, album asset, or generation contracts. |

## Harness Risks Checked

- **Stage fragmentation**: pass. `front-planning-readiness` remains the single front-planning contract; `section_work_plan` handles section slices inside it.
- **PRE-00 route-count quota**: pass after the second follow-up. `pre-00-research-radar` now allows a declared 3-7 route scope instead of forcing exactly five candidates; hold rather than padding weak duplicates.
- **Choreography/performance bias**: pass with watch. The 01 skill still names choreography/performance because those are real idol MV responsibilities, but current schema and wiki language allow story, object/system, camera/composition, environment/empty-space, and hybrid routes.
- **Generic profile fallback**: pass after the July 5 follow-up. Declared current-title album visual assets and album identity-source copies must be checked before profile fallback or loose board reuse, including track-poster and beat-source manifest paths.
- **Reference/contact-sheet sprawl**: pass after pointer-index clarification. Large files stay in a single owner; catalog title indexes point to canonically useful references/contact sheets.
- **Global keyframe or packet caps**: pass. Counts are local review shapes only; section evidence and founder budget decide expansion.
- **Automation overreach**: pass with watch. Automation may check presence, traceability, schema shape, and merge readiness. It must not score creative originality, enforce route diversity quotas, ban founder-selected reference following, or choose exact 04 cuts.
- **One-space / one-visible-feeling flattening**: pass after this follow-up. Front planning and 01/02A may now carry `space_visible_feeling_progression`; repeated locations or feelings are allowed only when their function changes. This is not a required variety mix.
- **Draft field-name bloat**: pass after this follow-up. The earlier draft names `space_emotion_progression_policy`, `space_emotion_arc`, `space_emotion_progression`, and `emotion_state` were replaced rather than kept as compatibility aliases.
- **03V planning loss**: pass after `planning_carry`. Video prompt work can now carry front planning, 01, 02A/02B, album assets, reference indexes, contact sheets, object/space continuity, and 04 edit seeds without reopening full-track context.
- **04 story/directing loss**: pass after the July 5 follow-up. 04 section shards and edit marker slots now require `story_flow_continuity`, `space_visible_feeling_progression`, and `directorial_transition_intent`, so a motion-only edit cannot pass readiness.

## Automation Harness Contract

If automation validators are extended later, they may only check structural readiness:

- A deep front-planning run has `research/front-planning-readiness-vN.*`.
- Section-heavy work uses `section_work_plan`, `section_gate.slices[]`, 02A section shards, 03V section shards, or 04 `section_workflow` as applicable.
- A section slice records source refs, timing, primary audio/section cue, lyric/no-lyric guard when relevant, identity owner when a member is visible, frame subject mode, composition lock, visible body/object/environment/camera action, transition in/out, status, and output paths.
- 03V carries `planning_carry` when upstream planning sources exist.
- 01/02A carries `space_visible_feeling_progression` when the run risks one-background or one-visible-feeling flattening, or when front planning already has `space_visible_feeling_arc`.
- 04 shards carry story/director/space-visible-feeling fields when edit flow depends on story, gaze, object, space, background/visible-feeling progression, camera direction, hold, or contrast; section-sharded 04 records require all three fields before merge readiness.
- Post-02B outputs are registered in the current title's output registry and optional reference/contact-sheet pointer indexes.

Automation must not check:

- a fixed number of keyframes, cuts, prompt packets, or 03V cues;
- a fixed number of PRE-00 route candidates;
- a required ratio of member-led vs world/object-led frames;
- a required mix of story/performance/object/camera routes;
- a required count or ratio of background, location, or visible-feeling changes;
- a ban on directly following founder-selected reference surfaces;
- a model's subjective creativity score;
- exact 04 source in/out, speed, final cutpoint, or candidate choice before 04 review owns it.

## Common-Contract Contamination Check

- INK is an example/current-title album asset route only. Shared contracts must say `ALBUM_KEY/TITLE_KEY`; new albums must not inherit INK paths.
- `aurora-m` is the internal project album namespace where applicable, not proof that every future album/title should use an INK or Words Left path.
- Reference and contact-sheet indexes are pointer-first, storage-light title lookup surfaces.
- Durable cross-run references belong in `source-materials/**` or `reference-library/**` only when they are repeatedly useful; ordinary run research stays in its owning run.

## Removed Or Consolidated

- No additional files or skills were deleted in this pass.
- The fixed PRE-00 five-route quota was removed from active schema/skill
  language. Existing five-route records remain valid, but new radar passes may
  declare 3-7 routes when that avoids filler.
- The already-proposed standalone front-planning section-lock route remains consolidated into `front-planning-readiness.section_work_plan`.
- The earlier July 4 audit removed the project-specific downloaded-reference hub path from shared artifact-management guidance.
- The generic profile-photo fallback remains demoted: it is only valid when a matching current-title album identity-source copy or declared album visual asset is missing, blocked, or out of scope.
- Active emotion-labeled field names were removed from current contracts rather
  than kept as aliases beside the visible-feeling replacements.

## Net Result

The harness now supports storytelling MV production by section without turning the process into many founder-visible stages. Creativity support is applied through existing contracts: scoped PRE-00 route counts, route alternatives in 01, no global 02A/02B cap, current-title album assets in front planning and generation, `planning_carry` in 03V, and story/directorial edit intent in 04.
