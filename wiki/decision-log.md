# Decision Log

This page records compact founder decisions that explain why the operating
flow changed. Do not read this file by default for every run. Read it only when
the founder asks to review past decisions, asks why a workflow changed, or when
a current task directly conflicts with a logged decision.

Use this shape:

```yaml
- date:
  source_context:
  decision:
  trigger:
  changed_flow:
  keep_doing:
  stop_doing:
  files_updated:
  note:
```

```yaml
- date: "2026-08-01 KST"
  source_context: "IDOL reference first-read quality; Founder review that reference answers were too abstract for 02B/03V use"
  decision: "Require media-shaped source-pixel first-read for references: nested 02B-shaped still observation for single stills/cells, and dual-layer sheet flow plus per-anchor still trees for sequence/frame sheets; keep teaching trees in one skill reference, not AGENTS/policies."
  trigger:
    - "Founder observed that reference reviews often answered with mood/function language instead of naming the actual photo/scene and observable camera/action facts needed for 02B image gen and 03V motion."
    - "Sequence/frame sheets need ordered-flow observation, not one still tree forced onto the whole sheet."
    - "Putting full nested trees into AGENTS/policies bloated the always-on constitution and duplicated teaching content."
  changed_flow:
    - "First semantic reference read must be source-pixel observation shaped by media kind (still vs ordered multi-frame sheet), never final generation prose or whole-sheet mood summary."
    - "Canonical teaching owner is skills/idol-front-planning-director/references/director-operating-contract.md under top-level H2 `## 02B-Shaped Source Observation` (Contents + Lane 1/2 H3s); receipt bind/reopen stays under `## Reference Interpretation Checkpoint`."
    - "AGENTS, policies, generation/video skills, and wiki routers keep invariant/hold/pointer only; they must not restate the full nested trees."
    - "AGENTS reviewed word ceiling raised 6500→6700 after trees were moved out; residual bulk is constitution text, not observation trees."
    - "instruction-surface-policy audit headings/terms realigned to current Member Visuals wording and harness_serves_creative_translation phrases."
  keep_doing:
    - "Select hash-bound cells/crops for generation binding; treat whole contact sheets as navigation only."
    - "Hold mood-only, function-only, top-label-only, or incomplete nested leaves before 02B/03V consumption."
    - "Point higher surfaces at the H2 section name so indexing stays stable until a later optional file split."
  stop_doing:
    - "Do not answer reference review with atmosphere/purpose class alone when the surface will feed 02B or 03V."
    - "Do not paste full observation trees into AGENTS, policies, or SKILL.md bodies."
    - "Do not invent continuous camera moves from a sampled sheet that only proves still-state differences."
  files_updated:
    - "AGENTS.md"
    - "automation/instruction-surface-policy.yaml"
    - "automation/harness-surface-version-registry.yaml"
    - "policies/creative-production-constitution.md"
    - "policies/section-production.md"
    - "skills/idol-front-planning-director/SKILL.md"
    - "skills/idol-front-planning-director/references/director-operating-contract.md"
    - "skills/idol-generation/SKILL.md"
    - "skills/idol-generation/references/idol-prompt-packet-structure.md"
    - "skills/idol-generation/references/reference-bound-provider-neutral-authoring.md"
    - "skills/idol-video-prompt/references/video-prompt-authoring-detail.md"
    - "skills/idol-video-reference-hub/references/video-reference-analysis-first-read-contract.md"
    - "wiki/INDEX.md"
    - "wiki/reference-management-system.md"
    - "wiki/reference-retrieval/INDEX.md"
    - "wiki/reference-retrieval/major_or_feeling.md"
    - "wiki/reference-retrieval/background_and_light.md"
    - "wiki/reference-retrieval/action.md"
    - "wiki/reference-retrieval/camera.md"
    - "wiki/reference-retrieval/edit.md"
    - "wiki/decision-log.md"
  note: "Optional later cleanup: split 02B-Shaped Source Observation into its own reference file. Not required for correct routing. Audit PASS after policy term realignment; AGENTS remains above word target with reviewed ceiling 6700."
```

```yaml
- date: "2026-07-06 KST"
  source_context: "WORDS_LEFT_IN_THAT_NIGHT / Left in that night discard closeout, runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE"
  decision: "Do not expand generated MV boards from motif density alone; prove the song's emotional owner and visible causal chain before making more boards."
  trigger:
    - "The route accumulated usable ingredients, including Glee-like musical staging, city spaces, orange juice, memory scenes, anime/game references, and member participation, but the founder still read the boards as unrelated stitched material."
    - "Repeated image-board rounds changed color, setting, and motif while the central story connection remained weak."
    - "The founder formally discarded the full MV route and kept only a 30-second residual teaser hold."
  changed_flow:
    - "Before new image-board expansion, write a compact pre-board proof: emotional owner, concrete action, cause-and-effect sequence, motif job, and 30-second proof route."
    - "A motif is not allowed to be only a symbol; it must visibly cause the next action, cut, gaze, space change, or object-state change."
    - "If two consecutive founder reviews say the route feels generic, disconnected, emotionally inaccessible, or unclear in message, stop generating images and run the anti-repeat check before another board."
    - "Keep only the latest selected or final review outputs for discarded routes; preserve source audio/research evidence and the discard record, not every superseded board image."
  keep_doing:
    - "Use references aggressively, but translate each reference into a current-song screen function, not a loose visual collage."
    - "Keep a residual teaser only when it has a clean, bounded purpose and does not imply the full MV is still active."
    - "Mark root run contracts as discarded when the founder formally kills the route so automation cannot continue 02A/02B or generation work by accident."
  stop_doing:
    - "Do not solve a missing story spine by adding more city locations, references, members, motifs, color treatments, or Branch-Cut count."
    - "Do not treat orange juice, instruments, library/stage objects, anime/game nods, or Glee-like staging as sufficient unless each one changes what happens next on screen."
    - "Do not continue paid or preview image generation after the founder has lost emotional attachment to the song or route."
  files_updated:
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/review/left-in-that-night-discard-record-v1.md"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/review/post-discard-anti-repeat-check-v1.md"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/review/30s-teaser-final-hold-v1/"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/00-creative-nucleus.yaml"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/00A-song-lock.yaml"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/01-song-choreography-performance-mv-map.yaml"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/01A-track-visual-board.yaml"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/02-generation-map.yaml"
    - "runs/2026-06-14/0614_LAST_GOODBYE_MESSAGE/02A-master-storyboard.yaml"
  note: "This is a workflow guard from a discarded run, not a ban on musical staging, city spaces, orange-juice motifs, memory scenes, anime/game references, or 30-second teasers."
```


```yaml
- date: "2026-05-26 KST"
  source_context: "FULL_CODE / ROOT_SIGNAL Suno exploration, runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL"
  decision: "Suno song exploration stays song-first and chat-first until the founder selects an actual audio direction."
  trigger:
    - "Early drafts kept producing old K-pop, cheap EDM, repeated rhythm skeletons, or the wrong BLACKPINK-like emotional route instead of the intended BABYMONSTER CHOOM-style performance pressure."
    - "Prompt attempts over-specified bass, kick, drum, BPM, and high-vocal instructions without enough proof from the selected audio."
    - "Live prompt iteration was changing run/harness files before the song itself was chosen, which wasted time and made the state harder to trust."
  changed_flow:
    - "When the founder brings reference songs, Codex reads function, structure, mood, energy, sonic grammar, reference feel, and rejected traits."
    - "Codex recommends the best-fit active unit from the reference functions instead of forcing FULL_CODE by default."
    - "Live Suno style, lyrics, hook, and section drafts stay in chat by default."
    - "Create a run-owned Suno prompt packet only when the founder explicitly asks to save, package, or run that candidate."
    - "Update `00-creative-nucleus.yaml`, `00A-song-lock.yaml`, active handoff fields, or memory only after the founder selects an actual Suno/manual take or explicitly locks an audio direction."
    - "Treat prompt lyrics and hook lines as probes. Fit final hook language to the actual generated audio, phrasing, scansion, and strongest phrase."
  keep_doing:
    - "Use reference-song fit before Suno copy boxes when the founder provides songs or says abstract prompting is failing."
    - "Use normal copy-ready Suno language in chat or prompt packets, not internal graph-engineering jargon."
    - "Describe body-readable rhythm, vocal behavior, hook function, and section duty before naming exact rhythm-section parts."
    - "Use `vocal phrase contour` / hook mechanics / rhythm pressure instead of melody/topline language for reference analysis."
  stop_doing:
    - "Do not revise `00`, `00A`, source links, active prompt pointers, or memory for every chat draft."
    - "Do not treat prompt text as selected audio."
    - "Do not guess exact kick, drum, bass, lead instrument, or BPM unless it is founder-selected, reference-critical, or proven by selected audio."
    - "Do not keep adding negative prompts when the result feels dated or cheap-EDM; revisit reference fit and first-clause function instead."
    - "Use public artist/source names when useful for the prompt or review note."
  files_updated:
    - "AGENTS.md"
    - "wiki/production-system.md"
    - "wiki/INDEX.md"
    - "AURORA-IDOL-PRODUCTION-BIBLE-VALIDATED.md"
    - "automation/pre-00-research-radar.md"
    - "automation/pre-00-research-radar-2026-05-24.yaml"
    - "schemas/pre-00-research-radar.schema.json"
    - "skills/idol-orchestrator/SKILL.md"
    - "skills/idol-suno-prompt/SKILL.md"
    - "skills/idol-song-lock/SKILL.md"
    - "skills/idol-nucleus/SKILL.md"
    - "skills/idol-research-radar/SKILL.md"
    - "skills/idol-song-choreography-performance-mv/modules/song.md"
  note: "This log explains the workflow correction only. It is not a song lock, not a style memory default, and not permission to mutate run files during future Suno brainstorming."
```

```yaml
- date: "2026-05-26 KST"
  source_context: "IDOL local-first git workflow and growing run/generated artifacts"
  decision: "Use git as the local production decision ledger, not as storage for every generated byproduct."
  trigger:
    - "The founder confirmed this repo will not be pushed, but dirty status was still becoming too noisy to distinguish active production decisions from repeated exports, payloads, images, and prompt drafts."
    - "Graph Engineering depends on fast inspection of current run truth: root run contracts, selected research, schemas, skills, wiki, registries, and handoff contracts."
  changed_flow:
    - "Track files that can change future decisions: `00`, `00A`, `01`, `02`, `02A`, `02B`, review/edit/package records, selected research, final prompt packets, promoted bank entries, schemas, skills, scripts, wiki, source materials, and registries."
    - "Keep routine execution output on disk but out of git status."
    - "Use `research/drafts/`, `research/probes/`, or `research/tmp/` for local-only exploration."
    - "Promote a draft by moving it into an active contract location, using a selected/final filename, or intentionally force-adding the exact file."
  keep_doing:
    - "Commit local checkpoints for coherent decision changes, even without pushing."
    - "Leave run root contracts visible in status so the next production step can trust the current state."
    - "Keep durable research visible when it explains why a route, song, visual system, or prompt direction was selected."
  stop_doing:
    - "Do not let `exports/**`, `generations/**`, generated boards, review images, contact sheets, API request/output payloads, batch reports, audio, video, render frames, or Drive sync copies crowd git status."
    - "Do not track repeated Suno/style probes or draft prompt variants unless selected or explicitly preserved as evidence."
    - "Do not use git status as a dump of every generated file; use it as a review snapshot for production truth."
  files_updated:
    - ".gitignore"
    - "business-marketing/docs/git-workflow.md"
    - "wiki/production-system.md"
  blocked_from_default_status:
    - "drive-sync/"
    - "runs/**/exports/"
    - "runs/**/generations/"
    - "runs/**/audio/"
    - "runs/**/video/"
    - "runs/**/renders/"
    - "runs/**/frames/"
    - "runs/**/*.jsonl"
    - "runs/**/batch-api-run.json"
    - "runs/**/import-report.json"
    - "runs/**/request.json"
    - "runs/**/response.json"
    - "runs/**/research/drafts/"
    - "runs/**/research/probes/"
    - "runs/**/research/tmp/"
    - "runs/**/research/suno-prompt-packet-v*.md"
    - "runs/**/research/suno-style-pack-*.md"
    - "runs/**/research/suno-style-probe-*.md"
    - "runs/**/research/audio-analysis-*.json"
    - "creative-bank/message-hooks/candidates/*.yaml"
    - "__pycache__/"
    - "*.pyc"
    - ".runtime/"
  explicit_unblocks:
    - "runs/**/research/suno-prompt-packet-selected.md"
    - "runs/**/research/suno-prompt-packet-final.md"
    - "Any specific ignored evidence file may be preserved with an intentional force-add after founder review."
  note: "This decision is about workflow signal quality, not secrecy. The files still remain on disk unless separately cleaned up."
```
