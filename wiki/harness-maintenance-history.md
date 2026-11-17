# IDOL Harness Maintenance History

Status: frozen migration snapshot
Canonical active rules: `wiki/harness-maintenance-rules.md`
Source checkpoint: `3a175dc`

This file preserves the former append-only maintenance history losslessly. It is
not part of the normal harness bootstrap and must not be loaded for ordinary
authoring, routing, validation, or resume work. Use Git commits and the active
machine/schema version for normal change history. Read this snapshot only for a
specific compatibility investigation, provenance audit, or archive-recovery
task.

## Historical Changes

- **2026-07-11**: Superseded the same-day ceiling-only v6 routing policy with
  adaptive upper-two v7 routing. The root remains Sol/Ultra/High, and every
  model may use only its catalog-adjacent ceiling or the immediately lower
  effort: Sol Ultra/Max, Terra Ultra/Max, and Luna Max/XHigh. New creative
  direction, Founder-facing or production-changing judgment, high-risk repair,
  and final validation stay on Sol/Ultra. Straightforward locked-source drafts
  and simple reversible bounded judgments now default to distinct read-only
  Terra/Max roles; material ambiguity or conflict raises them to the matching
  Terra/Ultra role. Routine deterministic evidence reduction defaults to
  Luna/XHigh, while large, anomalous, or interdependent evidence uses Luna/Max.
  A read-only Sol/Max profile is available only for bounded already-framed
  synthesis. The nine concrete custom-agent TOMLs make every selection an
  executable profile rather than a YAML-only label; four-thread and one-level
  concurrency limits are unchanged. Lower-tier use requires an explicit
  complexity reason and is never an availability fallback. The route CLI can
  select only a declared profile, the catalog validator proves adjacency, and
  the root performs scope/source/authority and escalation checks without
  automatically repeating an entire routine worker analysis. Token or latency
  savings remain unproven until a same-source quality-first paired evaluation.
- **2026-07-11**: Made creative-director independence and artifact lifecycle
  explicit without adding a new production stage or duplicate creative schema.
  Founder notes, preferences, first ideas, and supplied references are now
  high-priority inputs rather than automatic locks; Codex must preserve and
  independently test them, challenge a materially weaker route with concrete
  song/screen consequences, and execute only the Founder's informed explicit
  lock as final. Every Founder-supplied reference must close as applied,
  combined, held, or rejected with function, target, and reason, while selected
  grammar is recomposed into a current-song-specific scene or sequence
  consequence instead of generic mood matching or source replay. Artifact
  retention is now state-based rather than count-based: creative candidates
  remain uncapped before selection, then one canonical plus at most one rollback
  stays active after close; Git owns ordinary text history, physical archives
  are exceptional and manifest-backed, and rebuildable outputs or transfer
  mirrors cannot become archive truth. The cleanup helper gained a non-
  destructive lifecycle/duplicate audit surface; its apply path remains
  harmless-cache-only, so existing in-flight and legacy material is reported
  rather than silently moved or deleted.
- **2026-07-11**: Closed the remaining 02A-to-02B cardinality execution gap.
  Schemas already had no numeric maximum, but shell-free v0.2 previously used a
  child packet id/role/sequence only and compiled every same-parent packet from
  the same parent action, composition, and camera. Expanded cuts now require a
  complete hash-bound 02A `compile_seed.keyframe_shots[]` creative lock for
  every packet; the compiler copies it into 02B `keyframe_shot_lock`, overlays
  only those 02A-authored values, and leaves the compact delta non-creative.
  Child rows may be start, intermediate, peak, reaction, insert, hold,
  endpoint, or other ordered states with no maximum and no contiguous-sequence
  requirement; the parent `keyframe_boundary_contract` still owns cut
  start/end continuity. Identity inherits from the parent unless a child row
  explicitly selects a different parent-authorized face subset or no-face crop,
  still within the two-face API limit; no-face member crops preserve a separate
  `visible_member_focus` instead of erasing the screen owner. Direct v0.2 also rejects
  missing/duplicate child locks and requires the 02A section shards to cover
  every canonical cut exactly once. Regression tests now prove a three-keyframe
  same-window compile with a no-face member crop plus missing-lock,
  duplicate-sequence, duplicate-prompt, duplicate-master-cut, and
  missing-section failures while keeping sparse legacy rows and the v0.1
  migration verifier compatible.
- **2026-07-11**: Closed the director-flatness audit by replacing per-cut
  thesis/empathy completeness with distributed whole-video completeness. New 01
  authoring declares a broad `direction_form`, one `message_distribution`, and
  camera strategy; only narrative/hybrid forms require a causal director spine.
  Section ids no longer trigger shards by themselves, scene alternatives belong
  to flatness-risk transitions or sequences, and one route may cross several
  sections. `screen_cause_effect`, cut-level `message_function`, and
  `empathy_function` are backward-compatible optional anchors rather than
  universal requirements. The 02A-to-02B compiler now omits absent anchors and
  derives founder-facing image purpose from the local scene/cue job instead of
  the nucleus message. Concrete audio, visible action/hold, camera/composition,
  identity when visible, keyframe boundaries, source trace, and uncapped cut
  expansion remain strict so creative freedom does not reduce production depth.
- **2026-07-11**: Closed the direct 05 platform-draft bypass and retry-ambiguity
  gaps. Founder release approval now binds the exact run-root
  `05-package.yaml` path/SHA-256 and canonical deliverable-manifest digest in
  addition to queue and per-post asset bytes; runtime validation rechecks
  package schema, content owner, and asset-to-deliverable linkage. Direct upload
  dry-run remains network-free and exposes the package/asset manifest, while
  apply requires distinct contract/evidence paths, an exact active-plan owner,
  and social-lane tracker/log files. Approved media is copied and re-hashed into
  content-addressed run-owned staging; before each request the uploader
  atomically fsyncs a started intent and records `upload_in_progress`. A crash or
  ambiguous result leaves a started/unknown attempt that blocks automatic retry
  until reconciled, preventing duplicate posts and same-path asset TOCTOU.
- **2026-07-10**: Extended the quality-first optimization from post-02B through
  03V, 04/04FX, 05, publishing, and analytics without replacing the established
  creative or review flow. Audio–Frame Placement is now a schema/semantic
  contract bound to selected audio, generated-keyframe review, detailed
  timeline, animatic/timing table, and concrete frame units; a one-pass 03V
  source snapshot removes repeated discovery while legacy prep stays hold.
  Focused playback surfaces use worklist/clip/output digests for safe no-op
  refresh and carry generated-clip SHA-256 into explicit review. 04 source
  intake independently caches probe, motion, and contact-sheet evidence by
  source/config fingerprint, while 04FX v2 binds the exact recipe and passed
  preview and rejects stale dependencies. 05/social helpers now require
  explicit run/content/queue/package/plan/registry paths; external apply is
  bound to a schema-valid Founder approval artifact and canonical action-bearing
  queue digest plus exact approved asset bytes, with no global-queue or Aurora
  V2 secret fallback. The owning `05-package.yaml` is validated before atomic
  projection and a recovery journal records replacement/rollback state. Active
  plans, immutable publishing records, remote-publication pointers, and
  run-filtered no-metrics evidence are separate contracts. Downstream decision
  ownership and 5.6-family shadow cases were added so efficiency gains cannot
  replace detailed creative sources, infer pass, or compensate for
  quality/evidence regression.
- **2026-07-10**: Moved shadow evaluation entirely inside the gpt-5.6
  family. The adoption snapshot then recorded `gpt-5.6-sol / ultra / codex /
  current_default`; the active route is superseded by the 2026-07-11
  model-and-mode policy below. Candidate descriptors are operator-supplied, and 5.5 or
  cross-family ledgers are rejected. Paired ledgers hash-bind the harness,
  source/task, execution, and case artifacts, use one resolvable git commit,
  and keep profile output roots separate. Quality/evidence hard gates still outrank
  token, latency, retry, or tool-call gains. 03V also gained a backward-
  compatible v2 motion/camera-first contract: passed images own visible
  appearance/world truth, while generator prompts compile canonical motion,
  five-axis camera capture, pacing, and endpoint without repeating every
  internal field. The owning skill remains compact; only the Founder-requested
  per-cut 1–3-frame storyboard branch was split into a conditional reference
  and schema-backed artifact. Three frames limits one board, not total cuts,
  and the direct route remains default.
- **2026-07-11**: Replaced the v3 `xhigh/standard` model-and-mode policy with
  an executable Ultra-only routing contract. The active baseline is now
  `idol_sol_creative_synthesis / gpt-5.6-sol / model_reasoning_effort: ultra`.
  Project `.codex/config.toml` pins Sol/Ultra and direct-worker limits
  (`max_threads: 4`, `max_depth: 1`); the four project custom agents pin
  Sol/Ultra creative synthesis, Sol/Ultra final validation, Terra/Ultra bounded
  specialist review, and Luna/Ultra non-authoritative evidence checking. The
  v4 suite/result schema records the actual custom-agent id and rejects legacy
  `reasoning_effort`/`execution_mode` descriptors, so old v3 ledgers remain
  archive evidence rather than appearing to be Ultra runs. The new routing
  validator cross-checks YAML policy and TOML configuration, rejects high/xhigh/
  max fallback, role/model drift, nested fan-out, and a Luna route without
  independent verification. A model/surface that cannot run Ultra holds instead
  of lowering quality; Terra/Luna findings now require a hash-bound Sol primary
  validation artifact in both the ledger and matching execution manifest before
  any production-impacting decision can pass.
- **2026-07-11**: Superseded the earlier same-day four-agent route after both the
  bundled and freshly refreshed Codex catalogs showed no Ultra support for Luna. Active routing
  now contains three project custom agents: Sol/Ultra creative synthesis,
  read-only Sol/Ultra primary validation, and read-only Terra/Ultra specialist
  review.
  `max_threads: 4` still means one root plus at most three direct subagents, and
  `max_depth: 1` still bans recursive fan-out. The routing closeout now requires
  a current model-catalog preflight, never substitutes Luna/Max for Ultra, and
  retains `model_verbosity: high` on authoring/final-review roles to protect
  creative depth. Direct tools and registered deterministic scripts remain the
  default. IDOL has no active Responses PTC runner; PTC and the other optional
  GPT-5.6 Responses features require separate measured adoption and cannot be
  inferred from Codex Ultra. A final audit then closed the bundled-catalog
  evidence gap: routing preflight now runs refreshed `codex debug models` plus
  `codex --version`; shadow ledgers must hash-bind the exact captured catalog,
  match both live checks at validation time, and bind current project/role
  config hashes. Stale or fabricated runtime attestations fail closed.
- **2026-07-11**: Superseded the same-day global Ultra-only and current-local
  attestation policy with task-fit routing at each model's highest supported
  effort. The active ceiling map is Sol/Ultra/High for new creative synthesis,
  high-risk repair, and final judgment; separate Terra/Ultra/High roles for
  locked-source section drafts and bounded specialist review; and Luna/Max/Medium
  for read-only repeatable evidence reduction after direct scripts. Luna/Max is
  the current Luna ceiling, not a quality-lowering replacement for Luna/Ultra.
  Selected models may not silently run below their declared ceiling; a listed
  alternative uses its own ceiling or the route holds. The dispatch validator
  still checks current catalog capability, but shadow ledgers no longer bind to
  current catalog bytes, CLI version, or project/role TOML hashes. Evaluation
  keeps same-source/task/harness hashes, profile-specific artifacts, quality and
  evidence hard gates, and reconciled per-agent usage. The orchestrator now has
  to resolve the route, actually delegate to the named custom agent, record the
  selected route and reason, and return every advisory result to root Sol for
  canonical merge or production judgment.
- **2026-07-10**: Closed the Front Planning-to-02B optimization acceptance
  gaps. `front_planning_integration` is now a registry-owned semantic substage
  with physical `section_work_plan` extraction/merge support; decision owners
  and downstream projections are machine-validated instead of living only in a
  prose table. New-run deterministic 02B uses shell-free v0.2 with a minimal
  02A-owned identity compile input, while v0.1 is retained only for legacy long
  02B migration. Materialization is bound to the exact source-02A snapshot.
  The original adoption checkpoint used a 5.5 regression label; the later
  2026-07-10 policy entry above supersedes that active route while preserving
  this note as history.
- **2026-07-10**: Added `automation/harness-stage-registry.yaml` and
  `schemas/harness-stage-registry.schema.json` as the canonical compatibility
  layer between clearer semantic/operator stage names and existing numeric
  codes, root filenames, schemas, and commands. New routing should use stable
  semantic ids such as `mv_storyboard_direction` and
  `image_prompt_compilation`; operator labels may evolve, while `00`, `00A`,
  `01`, `02A`, `02B`, `03V`, `04`, and other legacy identifiers remain
  resolvable. This naming improvement does not create new top-level stages.
- **2026-07-10**: Added the additive revision envelope and physical section
  slice contracts, with canonical payload digests, parent lineage, typed
  upstream/feedback refs, invalidations, and five independent readiness axes.
  `idol_harness_sections.rb` detects fake monolith pointers and supports
  explicit-map extraction, validation, revision sealing, and lossless mechanical
  merge for 01/02/02A/02B without inferring equal-looking section ids. Added the
  compact 02A-to-02B delta and deterministic compiler as a migration path: the
  delta may change only operational packaging, while the normal v1.4 02B remains
  a materialized compatibility artifact for Founder review and export.
  Mapping-only verification may omit readiness because it writes nothing;
  materialization requires hash-bound passed storyboard context and expert
  reports. Conditional song-craft, director/camera,
  choreography-feasibility, storyboard-coverage, anti-under-splitting, and
  edit-grid gates protect depth. Cut/keyframe count remains unbounded and must
  expand when independent audio or screen-state events would collapse. The
  model/harness shadow suite makes quality and evidence non-regression a hard
  gate before token or speed gains count.
- **2026-07-08**: CF-code front planning was tightened without changing the
  CF00-CF70 stage order. CF10/CF30/CF40 schemas now expose a front-planning
  spine so high-concept ads can record compact-only versus longer
  subject-rule-timeline planning, visible trigger/reaction/payoff survival,
  cutdown compression, camera-variety policy, and CF40 carry. CF40 QC now
  requires the front-planning spine to survive and confirms the generation
  surface is not pre-locked to Seedance. Seedance was lowered to an optional
  CF60 surface: it is loaded only when founder-requested or selected by the
  active CF60 packet, and its packet schema no longer hardcodes a prior
  orange/black-box palette as a global default.
- **2026-07-08**: Python runtime isolation was made visible after the local
  system `python3` upgrade. `scripts/idol-video-python --check` now reports both
  the `.venv-video` interpreter and the system `python3` interpreter, verifies
  direct `requirements-video.txt` pins against installed package versions, and
  `idol_harness_state_check.rb` reports a non-blocking
  `python_video_runtime_isolation` check with pin-mismatch details. IDOL
  audio/video/media and Python-backed schema/registry helpers should continue
  to use the launcher; do not install packages into a newly upgraded system
  Python to fix IDOL media scripts.
- **2026-07-08**: The 01 director lane was split from the dance/performance
  specialist. The canonical skill name is now `idol-mv-director`; the old
  `idol-song-choreography-performance-mv` name remains only as a compatibility
  alias for older prompts and legacy-named `01-song-choreography-performance-mv-map.yaml`
  artifacts. `idol-mv-director` acts as the 01 MV director/router for song,
  section carrier, MV world, camera/composition, choreography/performance
  activation, and 01A visual locks. The new
  `idol-choreography-performance` skill owns dance, body-action, formation,
  performance blocking, and camera-readable member/body evidence only when the
  selected section route actually needs it. The old choreography/performance
  module paths under the 01 skill are compatibility pointers only. The 01/02A/02B
  schemas gained optional choreography-presence and camera-coverage carry fields
  so future runs can record whether choreography is primary/supporting/minimal/
  absent and which camera route was selected after comparing alternatives.
  The same split now treats 01 as a storyline-led MV director pass: story-led
  runs must record the director storyline spine, viewer information flow,
  section story-state change, camera directing strategy, and choreography
  integration rule before 02A/02B packet authoring.
- **2026-07-08**: Drive/Grok handoff mirror write guards were made enforceable.
  `idol_asset_drive_sync.py` now requires `--founder-requested` for `--write`,
  Grok/Drive wrapper scripts pass that confirmation through when already
  founder-requested, and `idol_harness_state_check.rb` now has a structural
  `grok_drive_write_guards` check. Dry checks remain allowed without founder
  confirmation; any script writing Drive/Grok handoff mirrors must prove the
  explicit request.
- **2026-07-08**: Title output-registry validation was tightened without adding
  a new harness stage. `schemas/title-output-registry.schema.json` now treats
  run-specific `source_step` and `status` labels as strings, while
  `scripts/idol_title_output_registry.py validate` owns semantic path checks:
  non-declared outputs must point to readable files, latest pointers must match
  registered existing artifacts, and future `declared` outputs stay in
  `outputs[]` until the file exists instead of being promoted to
  `latest_pointers`.
- **2026-07-08**: Title reference/contact-sheet pointer hygiene was added to
  the existing harness state check, not as a new harness stage. The checker now
  reports owner-layer/canonical-path prefix mismatches, missing active pointer
  targets, and media/archive files stored directly under a catalog title root so
  catalog folders remain compact lookup surfaces while large originals stay in
  `runs/`, `source-materials/`, or `assets/members/album-assets/`.
- **2026-07-08**: The harness state check now classifies top-level scripts that
  contain hard-coded run paths, legacy content tokens, or explicit one-off
  language against the `scripts/README.md` `Known one-off helpers` and
  `Known compatibility-default scripts` sections. A script may still keep a
  legacy sample/default path when it is intentionally documented as
  compatibility-default, and run-specific one-off helpers remain allowed when
  classified as one-off. Unclassified run-bound scripts now fail the structural
  policy check instead of passing merely because their filename appears
  somewhere in the README.
- **2026-07-08**: Active 02A/02B preview and generation-review guidance was
  tightened from beat-first screen-event language to cut-first language. The
  compatibility names `beat_id`, `beat_response`, beat-source manifest schemas,
  and `single-beat/` upload rows remain allowed when explicitly framed as
  legacy/compatibility surfaces, while active operator-facing review labels now
  use cut, cut id, cut-level composition, and CUT `[Cxx]`. The terminology guard
  now blocks the old beat-first preview labels, old beat-count review-sheet
  labels, old section-card wording, old composition wording, old prompt wording,
  and unqualified beat-source mode headings from returning to active guidance.
- **2026-07-08**: `idol-generation` now records the 01R-C reference-surface
  hierarchy for 02A preview boards and canonical 02A updates: the selected
  reference crop/cell stays the primary followed surface, while run/member/world
  visual assets are secondary anchors for identity, styling, material, pose, and
  texture unless 01R-C explicitly marks an asset fragment as primary.

- **2026-07-08**: `idol_harness_state_check.rb` now includes a non-blocking
  01/02A story-camera-action repetition profile. The check summarizes section
  and cut records for message/goal text, visual anchors, visible actions,
  camera/composition signatures, camera-family distribution, frame-subject
  distribution, and space/visible-feeling carry. It is a structural visibility
  aid only: intentional repetition remains allowed when the repeated surface has
  a changed story function, object state, camera relation, member ownership, or
  transition purpose.
- **2026-07-08**: `section_gate.slices[]` in
  `schemas/song-choreography-performance-mv-map.schema.json` gained optional
  `space_visible_feeling_progression` so section-sharded 01 work can record the
  same progression contract that already existed in `director_chain`. The state
  check now separates explicit progression-field coverage from fallback
  transition/quality-note traces. This avoids adding a new stage while making
  flattened space, camera, or visible-feeling repetition easier to spot before
  02A.
- **2026-07-08**: Active operator-facing screen-event terminology now uses
  `Cut Completeness` for the former beat-named completeness section. Legacy schema keys and file
  names such as `beat_id`, `beat_role`, beat-source manifest names, and
  `single-beat/` upload folders remain compatibility surfaces, but current
  guidance now uses `cut` for planned screen events, `shot/keyframe packet` for
  generated image units, and `beat/onset` only for audio-analysis timing. The
  terminology guard now blocks stale beat-first headings and phrases from
  returning to active operator-facing docs.
- **2026-07-08**: `handoff/grok/HARNESS-STEP-COMMANDS.md` was clarified so
  slash commands are entry aliases, not new top-level stages. The command map
  now separates 02, 02A, and 02B as their real artifact gates, routes 01R/01A
  and optional 01R-C through the 01 bundle, and says active intake documents are
  loaded only when `handoff/grok/current.md` points to a concrete active run or
  run-owned source pack. Archive handoff snapshots remain excluded from the
  default read surface.
- **2026-07-08**: `handoff/grok/current.md` was slimmed back to a true current
  pointer surface. The previous verbose INK/ATTITUDE/WORDS snapshot content was
  preserved under `handoff/grok/archive/2026-07-04-current-snapshots.md`, while
  the current file now states that no active Grok handoff is selected and points
  to archive/current-next surfaces. This keeps the Grok starting ritual fast and
  prevents archived titles from reading like active tasks.
- **2026-07-08**: `idol_harness_state_check.rb` now treats active-run pointer
  markers such as `none`, `null`, `not_selected`, and `no_active_run` as empty
  pointers instead of concrete run paths. This removes false drift noise after a
  title is intentionally archived or no active unit is selected, while still
  reporting drift when `handoff/grok/current.md` or `automation/current-next.yaml`
  points to a different concrete run.
- **2026-07-08**: Reference-library retrieval guidance was clarified without
  changing the storage model. Album/title `reference-index.yaml` and
  `contact-sheet-index.yaml` remain the current-title pointer surfaces, large
  media remains in the owning run/source/asset layer, and `reference-library/**`
  is only for reviewed reusable functions. The README now states the local
  lookup order and requires any reused function to be translated back into the
  current song's section cue, visible action, camera route, composition,
  ownership, and avoid notes before it reaches storyboard, prompt, video-prompt,
  or edit work.
- **2026-07-08**: 04 edit marker planning was connected more explicitly to
  automation without changing the 04 edit flow. `idol-editing-qc` now names
  `schemas/edit-marker-plan.schema.json` in its required reads and output
  boundary, `idol-orchestrator` routes recipe-starting 04 work through the
  existing 04-owned marker plan before recipe lock, and
  `idol_harness_state_check.rb` validates an edit marker plan when present. It
  now also summarizes timeline-slot carry for source-action markers,
  camera/body/object motion carry, story-flow continuity,
  space-visible-feeling progression, directorial transition intent, and
  audio-marker alignment. When both `04-edit-map.yaml` and an edit marker plan
  exist, the state check also verifies that the plan is referenced from
  `edit_marker_plan_ref` or the active section shard. This remains structural
  trace validation only: exact source in/out, speed, candidate choice, geometry,
  final cutpoint, and playback pass stay 04-owned review decisions.
- **2026-07-08**: Added the optional 01R-C reference fragment crop lock as an
  internal 01R sub-artifact for runs where selected contact-sheet cells, frame
  crops, or visual asset fragments must drive 02/02A camera, pose, object,
  material, light, crop, or composition decisions. This is not a new top-level
  harness stage. The artifact validates against
  `schemas/reference-fragment-crop-lock.schema.json`; `idol_harness_state_check.rb`
  validates it when present and structurally checks selected fragment id trace
  into existing 02/02A artifacts. 02 now treats selected fragment ids as
  section-level mini-storyboard scaffolding, and 02A makes only selected ids
  official through current-song cut cues, keyframe boundary contracts, source
  refs, and `reference_contact_sheet_contract`.
- **2026-07-07**: 01R local reference capture was tightened into a reusable
  cache/index workflow. New public-video scrubs should use a run-local ignored
  `_local_reference_cache/manifest.local.yaml`, pointer-only album/title
  `reference-index.yaml` and `contact-sheet-index.yaml` rows, and optional
  source-materials/reference-library promotion only after reviewed reuse. Dense
  2-3 second contact sheets are now second-pass selected-range evidence and
  must be split by section, source range, or fixed 30-60 second parts instead
  of becoming one giant full-MV sheet. `mv-direction-reference-mining` gained
  optional cache/index pointers and structured contact-sheet review records;
  `idol_video_qc_sheet.py` gained 2s/3s presets plus segmented sheet manifests.
- **2026-07-04**: A second creativity audit removed the fixed PRE-00
  five-route quota from the active radar schema and skill language.
  `schemas/pre-00-research-radar.schema.json` now allows a declared 3-7 route
  scope so automation can hold or use fewer stronger candidates instead of
  padding a brief with weak duplicates. The legacy five-route output label
  remains schema-valid for existing records, but new full radar work should use
  the scoped route count when five distinct functions are not available. The
  social metadata skill also now treats `#Ink` as an INK-only track tag example,
  not a reusable hashtag default for every title.
- **2026-07-04**: A follow-up common-contract audit removed the project-specific
  downloaded-reference hub path from the shared artifact-management guidance so
  one reference hub cannot become the default for unrelated albums. Shared docs
  now say to cite any useful hub through the active run, readiness, reference
  index, or source cache that owns it. 03V also gained optional
  `planning_carry_sources` and cue-level `planning_carry` so front-planning
  section story, object/space continuity, current-title album visual assets,
  and reference/contact-sheet pointer indexes can travel into video prompts
  without reopening 01/02A. 04 edit-map shards gained
  `story_flow_continuity` and `directorial_transition_intent` so edit choices
  can follow section story flow or visible directing technique, not only motion
  continuity. These are not new top-level stages and do not set exact 04
  cutpoints.
- **2026-07-05**: Follow-up subagent audit tightened the July 4 creativity
  changes into active automation contracts. Remaining active emotion-labeled
  fields were renamed instead of kept as aliases:
  `song_emotion` -> `song_feeling`,
  `viewer_emotional_state` -> `viewer_feeling_state`,
  `emotion_or_atmosphere` -> `visible_feeling_or_atmosphere`,
  `emotional_temperature` -> `feeling_temperature`, and
  `lyric_emotion` -> `lyric_meaning_or_visible_feeling` on active schemas and
  validators. 04 section shards and edit marker slots now require
  `story_flow_continuity`, `space_visible_feeling_progression`, and
  `directorial_transition_intent` so a motion-only edit cannot pass readiness.
  Track-poster and beat-source identity paths now prefer current-title album
  identity-source copies under
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` before base member
  profile fallback.
- **2026-07-04**: The full skill-stage creativity application audit is recorded
  in `automation/skill-stage-creativity-application-audit-2026-07-04.md`.
  The result keeps creativity support inside existing contracts rather than
  adding more visible harness stages: 01 route alternatives, 02A/02B
  proof-based expansion, 03V `planning_carry`, and 04
  `story_flow_continuity` / `directorial_transition_intent`. Future automation
  may check trace fields, source ownership, section readiness, and merge status;
  it must not score creative originality, enforce a fixed route mix, or choose
  exact 04 edit cutpoints.
- **2026-07-04**: Front planning and 01/02A gained a space/visible-feeling progression
  guard so Codex can correct one-background or one-visible-feeling flattening before
  generation. The guard lives inside existing contracts:
  `front-planning-readiness.section_work_plan.space_visible_feeling_progression_policy`,
  per-section `space_visible_feeling_arc`, 01/02A
  `director_chain.space_visible_feeling_progression`, and selected route notes. It is
  not a quota for variety and not a new stage; repeated spaces or feelings are
  valid when the repeated section changes story function, object state, camera
  relation, member ownership, or visible consequence.
  This follow-up removed the draft `space_emotion_progression_policy`,
  `space_emotion_arc`, `space_emotion_progression`, and `emotion_state`
  contract names instead of adding visible-feeling aliases beside them.
- **2026-07-04**: Album/title reference and contact-sheet storage was clarified
  as pointer-first and storage-light. When large references or contact sheets are
  reused across days or scattered across runs, create optional
  `catalog/albums/ALBUM_KEY/TITLE_KEY/reference-index.yaml` and/or
  `contact-sheet-index.yaml` records validated by
  `schemas/album-reference-index.schema.json`. Catalog remains a compact lookup
  surface; large files stay in one owner: the run folder for run-specific
  material, `source-materials/**` for durable cross-run source caches, or
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` only for founder-locked
  album visual assets. INK paths are examples or INK-owned records only; new
  albums must resolve their own `ALBUM_KEY/TITLE_KEY` paths.
- **2026-07-04**: Front-planning readiness gained
  `album_visual_asset_plan` so INK-style prebuilt album member, look, space,
  object, wardrobe/material, and keyframe-insert images can travel with the
  readiness handoff instead of being rediscovered later. Album assets live under
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` as the canonical asset
  owner, with catalog mirrors for lookup. 01/01A/02A/02B/03V should use those
  current-title assets before falling back to generic profile or loose board
  material. 02B scene/reference input validation now allows the declared album
  asset root while still blocking arbitrary external image inputs. This is not a
  new top-level stage.
- **2026-07-04**: Section-director alternatives were added inside the existing
  01/02A lane to reduce one-pass uniform MV planning. For storytelling-heavy,
  reference-heavy, long, dense, or previously uniform runs, 01 may now record
  `section_director_alternatives` and `selected_director_route` in
  `section_gate.slices[]` or `lyric_to_scene_thinking[]`; 02A may record
  `section_director_route_lock` so the winning route becomes official
  cut/keyframe boundaries while rejected routes remain avoid guards. The
  audio-motion schema gained optional director-use notes so section energy,
  pulse density, onset, backing rhythm, vocal holds, texture changes, and
  no-lyric resets can steer story/directing choices instead of lyric-only
  planning. A same-day follow-up folded the proposed standalone
  `front-planning-section-lock` route into
  `front-planning-readiness.section_work_plan`: founder/Codex section-by-section
  story, object, space, route, transition, or keyframe drafts now stay inside
  the single front-planning readiness contract. The founder-facing handoff stays
  unified while Codex/automation may work section slices asynchronously and then
  merge the selected routes into 01/02A. This is not a new top-level stage.
- **2026-07-04**: The frame-subject mix guard was de-duplicated and softened
  from a default ratio into a diagnostic anti-face-dominance check. The canonical
  current wording now lives in `wiki/generation-review-system.md`; generation
  skill references point there instead of restating the same numeric ranges.
  The ranges are warning ranges only, not quotas, targets, or a balancing rule.
  Current song cue, story state, object system, camera route, and founder draft
  decide the actual subject mix.
- **2026-07-03**: Song/reference audio analysis was tightened without adding a
  new top-level stage. Reference media intake may now preserve video and audio
  together when founder-approved captures exist; registered precision sidecars
  can provide beat grids, onset candidates, pitch-contour proxies, vocal
  register/color evidence, and repeated motif/hook candidates. Reference-audio
  sidecars feed reference-song fit and Suno/manual song planning only; they do
  not create current-run cut-pressure scores, MV section video functions, or 04
  edit timing. Selected-audio sidecars for the actual candidate take may feed
  selected-audio analysis, lyrics/audio-motion transition, 00A source pointers,
  01/02A timing pressure, and later 04 edit-marker planning while leaving final
  cutpoints and source choices to 04.
- **2026-07-02**: Market research cadence was changed from first-of-month trend
  refresh to a three-layer loop: weekly idol activity HTML reports, biweekly
  trend-pulse records, and month-end HTML summaries. The active PRE-00 and new
  song market hypothesis now starts from
  `source-materials/trend-pulse-records/latest.md`; weekly HTML reports under
  `source-materials/idol-activity-reports/weekly/` provide current idol
  activity observations, and monthly HTML summaries under
  `source-materials/idol-activity-reports/monthly/` are archive/comparison
  surfaces. Legacy `source-materials/monthly-trend-records/**` records remain
  historical baselines only. This is not a new production stage and does not
  create founder locks, PRE-00 routes, song locks, paid generation, publishing,
  or memory promotion by itself.
- **2026-07-01**: 02B image-input handling was updated after the ATTITUDE A58
  face+scene reference tests showed that face-only references can drift toward
  beauty portraits. `schemas/prompt-packets.schema.json`,
  `skills/idol-generation/`, and `wiki/production-system.md` now support an
  optional 02A-to-02B scene-reference intake gate plus packet-local
  `scene_reference_input` and `api_reference_input_plan`. Face references remain
  identity anchors only. Founder-approved scene/composition references control
  camera, space, light, texture, material, motif/object behavior, and action
  center without overriding identity, member ownership, song meaning, wardrobe
  lane, or core action. This is not a new top-level stage or paid-generation
  approval.
- **2026-06-29**: 02/02A/02B generation guidance was tightened for repeated
  device and flat-frame regression after the ATTITUDE fansign rehearsal review.
  Member-centered cuts now still require adjacent shot-scale, camera-height,
  camera-angle, depth, subject-placement, action-endpoint, and story-consequence
  variation. A mirror, glass, screen, threshold, table axis, floor/light mark,
  empty chair, card, garment touch, or similar device may not carry the same
  function across consecutive sections unless the cut changes function, owner,
  scale, camera side, object state, and handoff. Founder-banned devices must
  enter the run blocklist and existing packets using them become hold/revise.
  Visible camera equipment is not the default viewer proof; unless explicitly
  requested, POV is written as the scene the camera sees.
- **2026-06-29**: Suno prompt packet authoring was tightened without adding a
  new harness stage or schema. `idol-suno-prompt` now keeps the founder-facing
  runnable surface as `Suno Prompt: Style`, `Suno Prompt: Lyrics`, and
  `Suno Prompt: Negative`, with any decisive but unstable instrument or
  melody-inst anchors placed in an `Optional Style Add-On` that can be pasted
  after the base Style or omitted for A/B testing. This prevents broad
  instrument lists from flattening generation while still allowing true
  point-sound anchors from reference-song fit to steer the track.
- **2026-06-29**: 02A/02B count fields were clarified after the ATTITUDE harness
  review showed that a run-local packet count could read like a revived cap.
  `schemas/generation-map.schema.json`, `schemas/master-storyboard.schema.json`,
  `schemas/prompt-packets.schema.json`, `skills/idol-generation/`, `wiki/generation-review-system.md`, and
  `wiki/production-system.md` now allow or require scope language around
  `current_high_density_review_target`, `expected_keyframe_packet_count`, and
  `current_packet_count`: current review/export scope, founder-selected scope,
  budget scope, or partial authoring scope. These numbers are not global caps.
- **2026-06-29**: 01R image-reference handling was tightened inside the existing
  01 bundle without adding a new stage. `mv-direction-reference-mining` now has
  an optional `reference_image_intake` coverage map plus source-file pointers
  for reference registries and image manifests. The 01 skill now requires
  local-first reference class/lane checks, explicit gap actions, and
  `needs_asset_reingest` status for missing founder/local images before public
  searching or 01A/02A promotion.
- **2026-06-27**: Added `skills/idol-surgical-face-architecture/` as an
  analysis and prompt-architecture layer for differentiated original
  photoreal character faces. It uses plastic-surgery-style morphology axes
  internally to prevent repeated eyes, jawlines, noses, and flat midface depth,
  then compiles concise identity-separation prompts for `idol-photoreal-human-face-lock`
  or related generation work. This is not medical advice, not a specific-person
  procedure analysis lane, and not a new production stage.
- **2026-06-26**: Added `skills/idol-human-face-realism-control/` as an
  independent face-realism and identity-control skill. It translates 0-10
  MetaHuman-style face scores into prompt-ready visible morphology, memory
  points, asymmetry locks, and review deltas while keeping public figure references as
  source-function references only. This does not add a new production
  stage or route through the retired Jellobus face artifacts.
- **2026-06-24**: Post-upload social closeout was added to the final harness
  path after founder-approved social API upload or upload-attempt logging.
  `wiki/production-system.md`, `wiki/social-automation-system.md`,
  `skills/idol-orchestrator/SKILL.md`, and
  `skills/idol-social-metadata-upload/SKILL.md` now route final social cleanup
  through one compact closeout: refresh album/title `social-kit`, keep one final
  X posting plan and one final section bank, record version deltas in
  `version-log.md`, update registry/README pointers, and delete only
  stale preview/scratch files that are not referenced or protected. This is not
  a new creative stage and does not approve posting, publishing, scheduling,
  platform API sync, or deletion of final masters, trackers, ledgers, or
  preservation-locked visual boards.
- **2026-06-24**: Social platform draft hashtag enforcement was tightened
  without adding a new harness stage. TikTok, YouTube, YouTube Shorts, and
  Instagram Reels draft rows must carry `#AI`, `#AIIdol`, `#Kpop`,
  `#VirtualIdol`, and `#Loom`; the platform draft upload helper now appends the
  required set before external API calls, while social ledger validation warns
  on historical or draft rows that are missing the baseline public tags.
- **2026-06-24**: Camera specificity was tightened without adding a new stage or
  schema field family. The active camera geometry minimum is camera height,
  camera-to-subject distance/shot scale, camera direction/angle, and
  foreground/background depth, but those four axes are not sufficient by
  themselves. 01, 02A, 02B, and 03V guidance now also requires subject/object
  placement, crop or negative-space pressure, floor/reflection or foreground
  anchor, movement or hold, and a framing reason tied to the section cue before
  camera technique words such as push-in, orbit, rack focus, or match cut are
  treated as ready.
- **2026-06-20**: Added `idol-edit-finishing-fx` as an optional 04-owned
  finishing pass, not a new top-level stage. After a section or contiguous chunk
  edit preview passes, Codex may write a run-owned
  `04FX-finishing-map-vN.yaml` validated by
  `schemas/edit-finishing-fx.schema.json`, render short FX previews, and include
  only passed transition, beat-accent, tone, world/object, or source-reinforcement
  effects in the final high-quality render. The pass must preserve face, hands,
  feet, core body action, full space, world atmosphere, visual-system rules, and
  track tone-and-manner. Any effect that changes perceived timing routes back to
  the 04 edit recipe.
- **2026-06-20**: Added the 02A abstract-to-concrete autonomy standard after
  the Ink 02A pass required heavy founder micro-direction to reach the right
  level of section detail. `skills/idol-generation/SKILL.md`,
  `skills/idol-generation/references/generation-authoring-detail.md`, and
  `wiki/generation-review-system.md` now require Codex to translate founder
  emotion, symbolic direction, and reference-function intent into observable
  screen carriers: body action, object state, environment/crowd pressure,
  camera route, wardrobe/material motion, start/peak/end frame states, and
  transition handoff. Founder detail is a correction/lock surface, not a
  prerequisite for a cinematically specific first 02A pass.
- **2026-06-20**: Song-led MV keyframe generation now has a default post-02B
  03V prep bundle triggered by a 02B generated-board pass. After the founder
  passes generated keyframes and selected-audio timing or an audio-motion
  director map exists, Codex should create or refresh
  `review/03v-audio-frame-placement-vN.yaml`, a readable
  `review/03v-final-audio-detailed-timeline-vN.*`, an audio-retimed image-only
  animatic, its frame timing table, and title output-registry / current-handoff
  pointers, then move the passed keyframes directly into the 03V upload/handoff
  surface before `idol-video-prompt`, Grok, or another video-generation surface
  continues. This codifies the Ink/Pulso timing lesson: provisional contact-sheet
  or evenly spaced image-only previews are useful for connection review, but
  they are not enough for 03V. The 03V prep must carry decimal start/end timing,
  audio/section cue, lyric or no-lyric guard, body/object route, camera route,
  endpoint, and continuity without spending paid video generation or replacing
  founder review.
- **2026-06-19**: `schemas/master-storyboard.schema.json` now accepts
  `packet_expansion_contract.current_high_density_review` as a run-owned pointer
  to the active high-density 02A review artifact. Ink already used this field to
  keep the 58-keyframe section-link review traceable before 02B scope selection;
  the schema now matches the active artifact instead of treating the pointer as
  drift.
- **2026-06-19**: Added the frame-subject mix guard after the Ink section
  keyframe proof sheets showed that `face readable` could be overinterpreted as
  face dominance. `skills/idol-generation/SKILL.md`,
  `wiki/generation-review-system.md`, and the imagegen validation contract now
  require 02A preview sheets, 02B prompts, and generated-image review to
  preserve run-locked wide/environment, object insert, non-member pressure, and
  member close-up ratios. This older default-ratio wording was later
  de-duplicated and softened on 2026-07-04; use the current diagnostic wording
  in `wiki/generation-review-system.md`.
- **2026-06-19**: 02A/02B cut, board, and keyframe counts were unlocked at the
  top harness level. Old values such as 27, 39, 64, or a 12-frame preview are
  now documented as local defaults or historical review shapes only, not global
  caps. `AGENTS.md`, `wiki/production-system.md`,
  `wiki/generation-review-system.md`, `skills/idol-generation/SKILL.md`, and
  the generation/master storyboard schemas now route count control through
  concrete split evidence, visible-job need, section merge QC, founder review,
  budget scope, and paid-generation approval. `full_group_max: null` is valid
  for runs with no fixed review cap, and high-density review targets may be
  recorded explicitly.
- **2026-06-19**: Canonical visual lock packages were added as a 01A/visual-board
  lane refinement, not a new top-level stage. When a founder has locked the
  route but has not supplied enough production-ready visual detail, Codex should
  create concrete section-flow, album/group look lock, member solo reference
  sheets, space reference sheets, object/prop system boards, and
  section-to-reference maps before 02A/02B relies on them. The optional
  `schemas/track-visual-board.schema.json` field
  `canonical_visual_lock_package` groups those pointers when 01A needs them.
  This codifies the Ink lesson: downstream generation should inherit detailed
  faces, hair, wardrobe, spaces, props, and section usage from 01A locks instead
  of inventing them inside 02A prompts.
- **2026-06-19**: 03V manual upload packaging gained a single human-facing
  surface rule. New video-prompt packages should create or refresh a flat
  `upload-ready/` queue in timeline order, with each numbered folder containing
  `prompt.txt`, `image1.png`, and optional `image2.png`. Typed
  `upload-packs/bridge-two-image` and `upload-packs/single-beat` remain for
  validators, Drive sync, and script compatibility, but founder/operator
  handoff and current-next pointers should expose `upload-ready/` first to
  avoid making operators move through duplicate prompt/image structures.
- **2026-06-18**: Recent audio/section-first and composition-first contracts
  were de-duplicated after final maintenance review. `composition_lock` and
  `section_visual_quality_note` remain required by readiness/merge policy, but
  draft section shards no longer have to carry placeholder values only to pass
  schema shape. In 02B, `primary_audio_section_cue` is an alias when helpful:
  existing `director_chain.onset_hit` and `pre_edit_marker_contract.music_marker`
  still satisfy the primary cue contract when they already name the audible
  trigger. `keyframe_framing_lock.composition_lock` is now preferred
  packet-local evidence rather than the only accepted location; validation also
  accepts the same composition lock from `director_chain`, `visual_frame`, or
  `director_compile_note`. This preserves the new creative standards while
  avoiding repeated copy-paste fields.
- **2026-06-18**: Frame-subject flexibility was added as a harness contract
  refinement without adding a new stage. `primary_member` and `member_owner`
  now mean identity/part ownership when members are visible, not a requirement
  that every section, cut, or packet be member-led. Core PRE-00/00/01/02/02A/02B
  schemas and owning skills now expose `primary_screen_driver`,
  `frame_subject_mix_policy`, `frame_subject_mode`, `visual_system_anchor`,
  `world_or_object_anchor`, and world/object continuity checks so routes can
  intentionally mix member-led, unit/group-led, world/object-led,
  environment-insert, system-transition, or mixed member/world beats. This is a
  coexistence contract: member-led performance/identity frames remain valid, and
  non-member screen drivers must also be preserved when selected. Review and
  merge gates must preserve the chosen screen drivers instead of rebalancing the
  mix by habit.
- **2026-06-18**: The 02A/02B imagegen validator and 02A storyboard schema were
  aligned to that coexistence contract. Member-led and mixed cuts still require
  member/body evidence, but `world_object_led`, `environment_insert`, and
  `system_transition` cuts now validate through `visual_system_anchor`,
  concrete `space_or_object`, `must_show.world_or_object`, camera evidence, and
  material/surface readability instead of forcing fake member focus or body
  proof. `member_focus` remains identity evidence when a member is visible, not
  the universal image-generation basis.
- **2026-06-18**: Lyric cues were demoted from the default image-planning driver
  to a secondary meaning guard unless the lyric line is the actual audible turn.
  `01`, `02A`, `02B`, schema descriptions, and generation review docs now make
  selected-audio/section cues the primary timing anchor and require composition
  locks before camera-technique language. Start/end keyframes should record
  frame geometry, subject/object placement, depth, crop pressure, light/color
  balance, and the visible change between those composition states. Section
  review must also judge visual quality: composition strength, shot-scale
  rhythm, foreground/depth, color/light coherence, continuity/variation between
  keyframes, world/object progression, and whether a section has become boring
  lyric literalism. This is a coexistence refinement, not a ban on lyric-led or
  member-led frames when the song actually needs them.
- **2026-06-17**: Pulso closeout confirmed the useful founder-co-driven
  section preview loop without adding a new stage. `wiki/production-system.md`
  now states that, inside section-gated production, each founder-reviewed
  section or contiguous chunk should record source choice, fix/hold/pass
  decision, visible issue, timing change, and next-section boundary in the
  owning review, QC, edit, or package artifact before work widens. Chat-only
  section decisions are not sufficient handoff truth, and local previews do not
  become merged readiness until the section record preserves audio cue, source
  basis, timing, and transition evidence.
- **2026-06-16**: Added `wiki/artifact-management-system.md` as the prospective
  placement contract for new files, generated outputs, run-owned handoff packs,
  global LLM/Grok handoff packets, Drive mirrors, automation pointers, and
  cleanup rounds. The rule is canonical-source-first: keep run-owned truth in
  `runs/YYYY-MM-DD/CONTENT_ID/`, use catalog as lookup, handoff/drive-sync as
  transfer copies, and automation as pointers. Existing in-flight scattered
  material is preserved until the founder requests a cleanup pass.
- **2026-06-16**: Extended `wiki/artifact-management-system.md` with a Markdown
  file policy. New `.md` files created during harness work must be classified
  as durable research, draft/probe/tmp, review material, run-owned handoff,
  prompt file, export, catalog lookup, automation summary, or global advisory
  handoff before writing. Durable run-owned Markdown should carry a compact
  status/source/downstream block, and loose run-root `notes.md` style files are
  disallowed for new work.
- **2026-06-16**: The reusable contact-sheet helpers gained named layout
  presets so agents do not have to reinvent columns, thumbnail size, grouping,
  or interval choices for the founder's recurring review surfaces.
  `idol_cut_keyframe_contact_sheet.py`, `idol_edit_marker_contact_sheets.py`,
  and `idol_video_qc_sheet.py` now support presets such as `founder-review`,
  `overview`, `detail`, `dense-qc`, and `one-second` while still allowing manual
  overrides. This remains review-surface assembly only; it does not interpret
  images, choose winners, or make founder review decisions.
- **2026-06-16**: `scripts/README.md` was expanded from a policy note into the
  canonical reusable automation registry. It now groups state/queue helpers,
  validators, extraction-only scripts, contact-sheet/review-surface builders,
  02B export/imagegen helpers, 03V playback/handoff helpers, 04 edit/QC helpers,
  and known one-off run scripts. `wiki/production-system.md`,
  `idol-orchestrator`, `idol-generation`, `idol-video-prompt`, and
  `idol-editing-qc` now route script selection through that registry so agents
  can reuse common tools such as contact-sheet builders without turning creative
  interpretation into scripts.
- **2026-06-16**: `skills/idol-generation/SKILL.md` was slimmed from 320 lines
  to 261 lines by replacing the long top-level output-shape and validation
  checklist with a compact `Output Shape And Checks` router. Detailed 02/02A/02B
  authoring, packet compile, and API/imagegen checks remain in the directly
  linked `references/generation-authoring-detail.md`,
  `references/idol-prompt-packet-structure.md`,
  `references/prompt-packet-compile-detail.md`, and
  `references/idol-imagegen-validation-contract.md`. The top-level skill keeps
  the stage router, required reads, front-planning transfer gate,
  keyframe-boundary/pre-edit/reference-sheet invariants, and founder/API stop
  gates visible.
- **2026-06-16**: `scripts/idol_harness_state_check.rb` now reports a
  nonblocking `front_planning_transfer_gate_shape` check when a run has
  `research/front-planning-readiness-vN.yaml`. The check counts whether 01 uses
  section-level `front_planning_transfer` records, whether 01 section cards have
  `screen_cause_effect` and `director_chain`, and whether 02A cuts carry
  source-section, keyframe-boundary, compile-seed, and readiness-token traces.
  This is structural trace validation only. It must not evaluate whether
  Codex's or the founder's creative interpretation is good, and it must not
  automate contact-sheet, reference-function, song-meaning, motif, or keyframe
  decisions.
- **2026-06-16**: Top-level script policy was tightened for music/audio and
  edit helper scripts. `scripts/README.md` now separates extraction-only
  helpers, review/worklist helpers, compatibility-default scripts, and one-off
  run helpers. Reference/candidate audio scripts now emit measurement-only
  method notes; `idol_reference_section_segments.py` uses neutral
  `measurement_bucket` labels instead of section-function guesses; and
  `idol_worldcup_reference_audio_instrument_probe.py` reports measurement flags
  instead of instrument/arrangement guidance. This preserves speed from
  extraction while keeping song fit, arrangement, melody, instrument function,
  and prompt decisions with Codex/founder review.
- **2026-06-16**: `schemas/song-choreography-performance-mv-map.schema.json`
  now allows optional
  `lyric_to_scene_thinking[].front_planning_transfer` for LEFT/PULSO-style deep
  front-planning runs. This closes a section-level traceability gap: 01 can
  record selected source refs, extracted function, current-song trigger, screen
  translation, and 02A cut/keyframe implication without copying raw planning
  notes or adding a new stage. `idol-generation` consumes this as a preferred
  bridge when present, while 02A still owns the official cut/keyframe contract.
- **2026-06-16**: `skills/idol-nucleus/SKILL.md` was slimmed into a
  router-style nucleus skill. Detailed external brainstorm intake, PRE-00 route
  handoff, nucleus draft rules, minimum output shape, and founder-review
  checklist now live in the directly linked
  `skills/idol-nucleus/references/nucleus-authoring-detail.md`. The top-level
  skill keeps the hard gate that `00` is song-backed and, when deep front
  planning exists, only a thin source/function promotion contract.
- **2026-06-16**: `skills/idol-editing-qc/SKILL.md` was slimmed into a
  router-style edit skill. Detailed 04 section-sharding, upstream intent usage,
  cache/render workflow, audio-marker alignment, automatic recognition assist,
  source intake, cut decision, QC, effect, closeout, command template, and
  memory-promotion rules now live in the directly linked
  `skills/idol-editing-qc/references/editing-qc-detail.md`. This preserves the
  boundary that scripts and recognition may gather evidence only; final source
  choice, timing, identity, geometry, and founder pass/fail remain review
  decisions.
- **2026-06-16**: `skills/idol-orchestrator/SKILL.md` was slimmed from a
  long decision ladder into a router-style skill. Detailed next-step routing,
  post-review handoff, output verification, and founder-gate rules now live in
  the directly linked
  `skills/idol-orchestrator/references/orchestration-routing-detail.md`. This
  keeps the front-planning carry rules visible in the core router while
  preserving the full decision ladder for concrete resume/orchestration work.
- **2026-06-16**: `skills/idol-suno-prompt/SKILL.md` was slimmed into a
  router-style skill. Detailed reference-song fit, source lineage, whole-song
  composition, copy-box, arrangement/instrumentation, melody/topline, and full
  checklist rules now live in the directly linked
  `skills/idol-suno-prompt/references/suno-prompt-authoring-detail.md`. This
  follows the local maintenance rule that large skills should move procedural
  detail into references only when the detail is still required and directly
  discoverable.
- **2026-06-16**: `scripts/idol_skill_contract_matrix.rb` now includes an
  informational skill size inventory. Line count is not a readiness gate, but
  the report makes oversized skills visible so future slimming can happen during
  the next real edit instead of through broad speculative rewrites.
- **2026-06-16**: Schema `$id` values were normalized to the active
  `https://aheyabaraya.local/idol/schemas/...` pattern where missing or
  off-pattern IDs were found. `social-analytics.schema.json` remains a
  definitions-only row-contract library because runtime validation is currently
  owned by `scripts/validate_social_analytics.rb`; it should not be treated as
  a top-level ledger schema until a separate object contract is added. A
  `scripts/README.md` script policy now separates reusable validators,
  extractors, worklists, state reports, and export/preflight helpers from
  run-specific one-off production scripts. The harness state checker now also
  reports top-level scripts with hard-coded run paths when they are not
  documented in `scripts/README.md`; this is a registry/policy check only, not
  a judgment of creative interpretation.
- **2026-06-16**: The front-planning downstream trace checker was tightened to
  inspect existing `00`, `00A`, `01`, and `02A` carry-gate artifacts separately.
  A trace passes only when each existing carry gate contains a readiness source
  id/path token. This is still source-trace validation only: it may report that
  a gate dropped the source lineage, but it must not judge the creative quality
  of the interpretation or automate contact-sheet/reference meaning decisions.
- **2026-06-16**: `01` and `02A` were clarified as the official transfer gates
  for LEFT/PULSO-style front planning. `research/front-planning-readiness-vN`
  remains only a source-preserving index: 01 must translate each selected
  source/reference into current-song `screen_cause_effect` and `director_chain`,
  and 02A must preserve that translated function as section/cut/keyframe
  contracts through existing `source_sections`, `director_chain`,
  `compile_seed.source_refs`, `keyframe_boundary_contract`, and optional
  `reference_contact_sheet_contract`. This does not add a new stage or a new
  creative-analysis script. Automation may check only that readiness source refs
  remain traceable in downstream artifacts; it must not judge whether the
  translation is creatively good.
- **2026-06-16**: `00` and `00A` were clarified as thin promotion contracts
  when LEFT/PULSO-style deep front planning exists. The lineage to preserve is
  `source/reference chosen -> function extracted -> concrete production
  decision`. `00` should use existing `source_links` and
  `song_seed.reference_functions` to promote only nucleus-level decisions,
  while `00A` should use existing `audio_to_visual_read`, `trigger_cues`,
  `action_directive`, `proof_target` (visual readability target),
  `trigger_anchor`, `handoff_strength`, and
  `output_lane` to promote only selected-song section contracts. No new schema
  fields or scripts were added for this clarification; automation remains
  limited to schema/path/contract checks and must not interpret creative
  reference function.
- **2026-06-15**: PRE-00 was re-scoped as a lightweight founder inspiration
  surface, not a default deep-analysis pass. It should present compact route
  cards that help the founder choose, combine, or reject directions. Deep
  LEFT-style work begins after founder selection through a run-owned intake
  brief that preserves concrete situation, message, references, visual objects,
  lyric seeds, and guards. PRE-00S reference-song fit, contact-sheet review,
  audio feature extraction, and source research should run only after a selected
  route or explicit founder request.
- **2026-06-15**: `reference-song-fit` was extended to schema v1.2 for
  arrangement/instrumentation and melody/topline analysis. The new fields make
  the repeated PRE-00 reference-song read explicit: drums/percussion,
  bass/low-end, melodic textures, harmony beds, FX/sound design, section-level
  arrangement changes, topline contour, hook motif behavior, phrase spacing,
  landing/release points, vocal events, and meaning-delivery connection. This
  remains Codex/human interpretation. The helper script
  `scripts/idol_reference_music_feature_extract.py` may extract tempo, onset,
  energy, band-share, percussive/harmonic, chroma, and pitch-proxy evidence
  only; it must not infer instruments, decide melody function, write prompt
  language, or promote a run-specific sound into a future default.
- **2026-06-15**: Front-planning readiness was added as a thin run-owned
  source-preserving index at `research/front-planning-readiness-vN.yaml`.
  It captures the useful PULSO / LEFT IN THAT NIGHT pattern without creating a
  new top-level stage: deep intake, lyric, audio, visual-board, storyline,
  director, POV, wardrobe, and section/cut/frame notes stay in their original
  run-owned files, while the readiness index records source paths, downstream
  handoff use, automation boundaries, and an anti-bias guard. Automation may
  validate schema shape and path existence only; contact-sheet interpretation,
  reference-function analysis, meaning decisions, and motif/default promotion
  remain founder/Codex creative work.
- **2026-06-15**: `audio-motion-director-map` was promoted from optional
  post-review support to a mandatory post-selected-audio gate for video/MV-bound
  song work. After selected-audio analysis and lyrics direction bridge, Codex
  must create or refresh `research/audio-motion-director-map-vN.yaml` before
  track creative board, `00`, `00A`, `01R`, `01`, or `02A` treats the run as
  production-ready. The map must combine actual lyric/no-lyric cues as then
  defined, now interpreted under the 2026-06-18 rule as primary audio/section
  cues plus lyric meaning guards unless the lyric line is the audible turn,
  backing drum/percussion/bass triggers, high-transient or hat grids, vocal
  holds, texture-density changes, founder reference-map tone, and current-run
  scene grammar into observable body/object/camera/cut timing. The harness state
  checker now blocks when selected-audio analysis exists but the audio-motion
  map is missing, so future video work does not discover the first real frame
  split only during 03V/04.
- **2026-06-14**: Suno/manual prompt readiness was clarified as source/reference
  lineage through existing artifacts, not a new top-level stage or new generic
  field family. Reference-led or source-heavy routes should close the prompt
  basis through `reference-song-fit` fields already present:
  `founder_references`, `function_breakdown`, `meaning_delivery_fit`,
  `prompt_handoff`, and `source_links`. Suno packets may expose a readable
  `Source / Reference Lineage` section, but it should cite those upstream IDs
  and paths so selected-audio analysis, lyrics direction bridge, 00, 01, 02A,
  02B, 03V, and 04 can follow normal `source_refs`, `source_links`, and
  `reference_functions` instead of maintaining a parallel source model.
- **2026-06-12**: `idol-suno-prompt` was tightened conservatively for
  reference-led Suno authoring. Copy-ready Suno boxes now treat artist names,
  song titles, and source hook labels as opt-in rather than default; references
  should normally be translated into sound, structure, vocal, lyric, and
  meaning functions. The skill also relaxes `primary genre` from mandatory to
  `primary genre or concrete sound function`, keeps detailed section order in
  Lyrics tags and packet notes instead of overloading the Style box, and adds a
  reference-backed instrumentation / vocal-event decision lock before copy boxes
  when founder references or local reference audio drive the prompt. This does
  not add a new harness stage or schema.
- **2026-06-12**: 02A/02B cut-to-keyframe expansion was clarified. A 02A cut is
  the parent timing/story event and the minimum coverage unit, not the maximum
  image count. 02B remains one API image per packet, but a parent cut may own
  1..N same-window keyframe shot packets when upstream story, member relay,
  identity, object, camera, space, or transition proof cannot be judged in one
  image. Split 02A only when the audio cue, screen cause/effect, story state,
  camera handoff, object/space state, or edit endpoint changes.
- **2026-06-12**: Reference research contact sheets can now influence 02A/02B
  image generation through `reference_contact_sheet_contract`. This records the
  source sheet, selected cells or frames, transferable visual functions,
  translated text locks, followed reference surfaces, and mismatch/avoid notes.
  Contact sheets may be attached or followed directly when the founder or packet
  contract asks for that; otherwise the selected source surface should still be
  named and described in render-facing prompt prose.
- **2026-06-12**: 04 edit marker thinking was moved upstream only where video
  source is not required. Active 02A cuts and 02B packets now carry
  `pre_edit_marker_contract` with music marker, cue-function marker, planned
  source-action marker, start/action-peak/end states, edit handoff basis, and
  render-facing action cue. This improves cut splitting and keyframe placement
  before image generation while preserving the boundary that actual
  `source_in`, `source_out`, speed, final cutpoint, final source candidate,
  geometry, and playback pass remain 04-owned after generated source motion
  exists.
- **2026-06-12**: Founder/operator terminology was clarified to use
  `section -> cut -> shot/keyframe packet`. Existing schema fields such as
  `beat_id` remain compatibility keys, and active schemas now accept cut-first
  fields such as `cut_id`, `cut_role`, `cut_expansion_index`,
  `expected_cut_count`, `individual_cut_keyframe`, and `micro_cut_sheet`.
  Review and handoff language should call music-led screen events `cuts`. Dense
  rap, added-vocal, ad-lib, or
  phrase-accent changes must be split into cuts before paid image generation so
  images can become the source for video generation, rather than waiting for
  03V/04 to discover the micro-split.
- **2026-06-12**: Reference-song fit, Suno prompt handoff, lyrics direction
  bridge, 01, and 02A were reinforced to carry meaning delivery, not only sound
  feel, BPM, lyric density, good scenes, or edit sync. Reference songs should be
  read for how they make message, hook claim, emotional stance, or listener
  identification clear; the method is then compared against the current run's
  original lyric/message target and rewritten into IDOL-owned meaning. This
  records the production lesson that visually polished work can still feel
  weaker when the meaning path is less readable, while a legible whole-track
  message/empathy progression makes a track easier to understand and remember.
- **2026-06-11**: Section/beat splitting was reinforced without adding a new
  harness stage. Reference research should actively find strong source scenes
  and timestamps, then translate them into current-song functions. Selected-audio
  analysis must preserve lyric/vocal cues plus relevant backing drum,
  percussion, bass, ad-lib, texture-density, silence, and pickup/landing
  evidence. 01R/01 must translate reference research before it can influence
  section shards, and 02A beat ids must show the selected-audio trigger and
  adapted reference function rather than treating reference timecodes, equal
  seconds, output slots, or prompt-count needs as current-song boundaries.
- **2026-06-11**: 01R/local-first direction planning, `style_system_lock`, and
  face-visible identity input were added as harness contract refinements without
  adding a new top-level stage. Codex must inspect local run sources, dense MV
  observations, founder boards, visual boards, and contact sheets before any
  reference rerun; reruns must answer a named missing question. 02B now treats
  visible member faces as the trigger for no-mic face-only API inputs, while
  no-face keyframes may declare `identity_input: none` and attach no face image.
  Style locks must define the run's concrete wardrobe/background grammar without
  defaulting to flags, national colors, face paint, LED/stage sets, or one-motif
  stuffing unless founder-locked.
- **2026-06-11**: 03V front gates now cap the active founder/generation surface
  to the current front chunk instead of automatically widening to every
  contiguous playback-only section. For the LOW active run this means
  `S00-S03` / 12 packets is the current gate, while `S00-S14` / 41 packets is
  recorded only as total local-ready coverage and `S04` remains the next chunk.
  This lets generated playback prove the opening chunk before automation moves
  to the next chunk, instead of forcing all 41 prompts into one approval surface.
- **2026-06-11**: 03V generated playback gained a run-owned intake surface:
  `review/03v-generated-playback-intake-v1.yaml/.md`, generated by
  `scripts/idol_03v_generated_playback_intake.rb`. The intake maps expected
  generated clips for the active front gate back to packet IDs, clip candidate
  paths, upload packs, and `generation_playback_probe` review status without
  changing section QA state. Focused 03V refresh commands and founder-decision
  application now regenerate this intake so clip collection can resume from a
  single file after generation.
- **2026-06-11**: 03V generated playback intake now treats `clip_status:
  present` as a playable-media state, not file existence. It probes discovered
  clips through `scripts/idol-video-python`/`ffprobe` and records
  `clip_file_status`, `media_probe`, `found_clip_file_count`, and
  `media_probe_issue_count`. A directly placed but unplayable clip remains a
  pass blocker in the intake, playback review worklist, decision sheet, and
  front-gate validator until it is replaced and the focused 03V playback
  artifacts are regenerated.
- **2026-06-11**: 03V generated clips can now be imported from a loose download
  folder with `scripts/idol_03v_import_generated_clips.rb` and
  `schemas/03v-generated-clip-import.schema.json`. The import maps source video
  filenames to upload-pack names or packet IDs, writes a run-owned audit
  manifest under `review/03v-generated-clip-imports/`, and can refresh the
  focused generated playback intake, playback review worklist, playback
  decision sheet, action queue, next unit, founder gate, and current-next
  pointer when `--refresh-worklists --refresh-current-next` are used. Ambiguous
  or duplicate packet matches are left for manual correction; the import never
  marks `generation_playback_probe` pass and does not route Drive, publishing,
  package, or edit readiness.
- **2026-06-11**: 03V generated playback also gained a schema-backed playback
  review worklist at `review/03v-playback-review-worklist-v1.yaml/.md`,
  generated by `scripts/idol_03v_playback_review_worklist.rb`. It turns the
  active front-gate intake into packet-level review checks for start frame,
  endpoint, cue timing, body route, camera route, identity/body stability,
  space/object evidence, and continuity cut basis. Refresh commands and
  founder-decision application now regenerate this worklist after intake so a
  generated clip batch can be reviewed without reopening broad 03V context.
- **2026-06-11**: 03V playback review also gained a compact decision sheet:
  `review/03v-playback-decision-sheet-v1.yaml/.md`, generated by
  `scripts/idol_03v_playback_decision_sheet.rb` and validated by
  `schemas/03v-playback-decision-sheet.schema.json`. It compresses the
  packet-level worklist into one founder/operator response surface for
  `S00-S03 pass`, `hold`, or `fix PKT_Bxx`, while preserving the same rule that
  missing clips block pass and playback evidence cannot mutate QA without the
  explicit apply command. The markdown sheet must expose the gate pass
  checklist, section questions, and packet focus checks; do not hide required
  playback checks only inside YAML.
- **2026-06-11**: 03V playback decisions gained a separate record surface:
  `review/03v-playback-review-records/*.yaml/.md`, generated by
  `scripts/idol_03v_record_playback_review.rb`. The recorder accepts compact
  founder/operator text for `pass`, `hold`, or `fix`, resolves packet/section/gate
  targets, refuses `pass` when target clips are missing, and never mutates 03V
  section QA, Drive, publishing, or edit readiness. Approved generation handoff
  units now expose a record-command template so playback decisions can be logged
  without reopening broad context.
- **2026-06-11**: 03V playback decisions also gained a one-command wrapper:
  `scripts/idol_03v_apply_playback_decision.rb`. It records `pass`, `hold`, or
  `fix` from compact founder/operator text, schema-validates the record, and for
  explicit clip-present `pass` decisions immediately runs the section-QA patch
  plus focused 03V refresh. `hold` and `fix` remain record-only. This keeps the
  founder-facing input short while preserving the same safety gates: no pass
  with missing clips, no QA mutation without explicit founder-reviewed pass, and
  no Drive/publishing/edit readiness side effects.
- **2026-06-11**: Approved 03V generation/playback handoff units now surface the
  exact run-owned upload-pack root, run-owned `PACK_INDEX.csv`, drive-mirror
  upload root, drive-mirror `PACK_INDEX.csv`, upload-pack count, generated
  clip import command, generated playback intake, playback review worklist,
  one-command playback decision template, playback review record command, and
  playback-review apply command.
  The front-gate validator checks those paths in approved-route mode so a founder
  approval can move directly into route handoff/clip collection without another
  operator search step.
- **2026-06-11**: Approved-route `automation/current-next.md` now renders those
  handoff details as a short ordered command path: use the approved upload-pack
  root, import downloaded generated clips, open the compact playback decision
  sheet, then apply the founder-reviewed `pass` / `hold` / `fix` command. The
  front-gate validator also checks that the direct playback decision command
  template is present, so approval-to-playback review does not depend on an
  operator reopening the larger action queue. Do not expose a literal
  `pass|hold|fix` command template on an operator-facing surface; the playback
  parser treats that as ambiguous. Render separate pass, hold, and fix commands.
- **2026-06-11**: The 03V front-gate validator now also checks that the
  run-owned generated playback intake, playback review worklist, and playback
  decision sheet point to the same active front-gate section range, source
  worklist, source section QA, packet IDs, and clip root. This blocks stale
  temp/probe playback surfaces from drifting away from
  `automation/current-next.yaml` while still leaving clip import, playback
  review, and section-QA pass as separate gates. It also requires the focused
  action queue, next-unit, founder gate, and current-next surfaces to carry
  refresh commands for the generated playback intake, playback review worklist,
  and playback decision sheet so a resume surface cannot silently drop one of
  the playback-gate files.
- **2026-06-11**: 03V playback pass records can now be applied to a new
  section-QA candidate with `scripts/idol_03v_apply_playback_review_record.rb`
  and `schemas/03v-section-qa-patch-record.schema.json`. The apply step only
  accepts `pass` records with explicit founder review, present target clips, a
  patchable playback summary, and full-section packet coverage. It writes a
  `review/03v-section-qa-patch-records/*.yaml/.md` audit plus a new section-QA
  candidate, rather than mutating the canonical QA by default. This preserves
  the chunked flow: if `S00-S03` passes playback, automation can move to `S04`
  instead of forcing all 41 local-ready packets through one gate. It still does
  not approve paid generation, Drive mutation, publishing, or edit readiness.
- **2026-06-11**: 03V front-gate scanning now skips only fully passed chunks,
  not individual passed sections. A pass-applied section-QA candidate therefore
  keeps the focused gate on `S00-S03` when only `S00` has passed, with
  `passed_section_ids=S00` and `remaining_section_ids=S01,S02,S03`; after the
  whole `S00-S03` chunk passes, the next focused gate moves to the chunk
  beginning at `S04`. The LOW temp probes verified `S00`-only pass keeps
  `S00-S03`, while full `S00-S03` pass advances to `S04-S06` with `S07` as the
  next local section. Focused refresh commands now carry `--qa <source section
  QA>` so candidate-based queues do not accidentally fall back to the older
  canonical QA on the next refresh. `scripts/idol_harness_action_queue.rb` also
  accepts `--worklist PATH` for safe temp/probe validation of candidate
  worklists without rewriting run-owned automation pointers. Keep this helper
  on the 03V section-QA/front-gate path; it must not route 04/edit readiness.
- **2026-06-11**: Playback review record parsing now treats a named section
  range such as `S00-S03 pass` as a gate-level review before checking individual
  section IDs. This prevents a full front-chunk pass from being accidentally
  reduced to `S00` only. The end-to-end temp probe verified
  `record -> apply --refresh-focused-queue`: `S00 pass` keeps the active gate on
  `S00-S03`, while `S00-S03 pass` patches all four front sections and advances
  the focused current pointer to `S04-S06`. The live run-owned pointer was then
  restored to canonical `03v-section-video-prompt-qa-v2.yaml` / `S00-S03`
  because no real generated clips have been founder-passed yet.
- **2026-06-11**: `scripts/validate_03v_front_playback_gate.rb` now accepts
  optional generated-playback artifact overrides (`--playback-intake`,
  `--playback-worklist`, and `--playback-decision-sheet`) so chunk transition
  probes can validate temp candidate flows without mutating live run-owned
  playback files. The default live paths remain unchanged.
- **2026-06-11**: 03V playback review records now carry the required playback
  check IDs and labels for each covered packet, so a short founder response such
  as `S00-S03 이상없음` can remain minimal while the audit record still shows
  which start-frame, endpoint, audio timing, body, camera, identity, space, and
  continuity checks were covered. The recorder also rejects an explicit section
  range that does not match the current playback gate, preventing a mistyped
  `S01-S03 pass` from being silently applied to `S00-S03`.
- **2026-06-11**: Applying a 03V playback pass record now compares each covered
  packet back to the source playback review worklist before patching section QA:
  section key, timeline, clip status, generated clip path, required check IDs,
  required check count, and recorded review status must match. This keeps a
  stale or hand-edited pass record from advancing the chunk gate.
- **2026-06-11**: Playback `fix` decisions must now target one packet, for
  example `fix PKT_B03: <visible issue>` or `B03 수정: <visible issue>`. Gate- or
  section-wide fix records are rejected because they force the next worker to
  reopen the whole chunk instead of repairing a concrete generated clip/prompt.
- **2026-06-11**: Playback review records now include a structured
  `decision_note`. `hold` and `fix` records require a visible reason or issue
  note, while `pass` may keep the compact founder wording. This prevents
  actionable playback feedback from living only inside a freeform chat sentence.
- **2026-06-11**: The direct 03V playback review recorder now validates its
  written YAML against `schemas/03v-playback-review-record.schema.json` through
  the repo launcher before returning success. This keeps the exposed record-only
  command as reliable as the one-command apply wrapper when an operator logs a
  `hold` or packet-level `fix`.
- **2026-06-11**: The 03V generated-clip import flow gained
  `--refresh-current-next`. When used with `--refresh-worklists`, clip import can
  refresh generated playback intake, playback review worklist, playback decision
  sheet, focused action queue, next unit, founder gate, current-next, and the
  front-gate validator in one pass. Approved generation/playback handoff command
  templates must include this option so the operator-facing next surface does
  not lag behind newly imported clips.
- **2026-06-11**: 03V generated-clip import manifests now run a repo-launcher
  media probe for each imported or skipped-existing video and record duration,
  stream count, dimensions, codec, and playable status. If any imported clip is
  unprobeable or has no positive video duration/dimensions, the import manifest
  is written as partial but playback worklist/current-next refresh stops before
  the clip can appear as founder playback-ready.
- **2026-06-11**: `scripts/idol_03v_apply_playback_review_record.rb` now runs
  repo-launcher schema validation as part of `--write` and
  `--refresh-focused-queue`: playback review record, candidate section QA,
  patch record, refreshed 03V worklist, generated playback intake, playback
  review worklist, action queue, next unit, founder gate, current-next, and the
  front-gate validator are all checked inside the single apply command. This
  removes the separate manual validation step after a founder playback pass.
- **2026-06-11**: 03V founder-decision application now self-validates the
  founder decision, generated playback intake, playback review worklist, action
  queue, next unit, founder gate, current-next, and front-gate validator inside
  `scripts/idol_harness_apply_founder_decision.rb`. The front-gate contract also
  separates `next_local_section` from `next_local_continuation_allowed`: for LOW,
  `S04` is a next playback chunk after full `S00-S03` pass, not a local-QA
  founder choice, because S00-S14 are already local-ready and only playback
  review remains.
- **2026-06-11**: Approved 03V generation/playback decisions now advance the
  focused queue to the active front chunk handoff, for example
  `prepare_03v_generation_playback:S00-S03`, instead of reselecting the same
  founder gate. The active decision carries
  `approved_execution_route`, current-next surfaces the route and next step, and
  the front-gate validator accepts this as
  `approved_generation_route_pending_playback` while still forbidding QA-pass
  promotion until generated clips are reviewed.
- **2026-06-11**: 03V front-gate founder examples now expose
  `grok_manual_drive_mirror` as the default explicit generation/playback route
  name instead of leaving `route=<named route>` placeholders in the visible
  current-next surface. The active LOW Grok handoff was also refreshed to state
  the focused 03V truth: S00-S14 local source/prompt QA is closed, the active
  gate is only S00-S03 / 12 packets, and edit readiness is not refreshed or
  advanced by this 03V handoff.
- **2026-06-11**: Final 03V front-gate packets now omit
  `continue_local_next_section` unless `next_local_continuation_allowed` is
  true. `next_local_section` may still name the next playback chunk after the
  current chunk passes; it is not by itself permission to offer a local-QA
  founder choice. This prevents automation from offering a dead or misleading
  "continue next section" action when only generated playback review remains.
- **2026-06-10**: 03V section QA gained a front-chunk stop gate so automation
  does not keep auditing later sections when the already-checked opening chunk
  only needs founder playback/generation review. The 03V worklist now records
  `front_playback_gate_ready`, the section range, minimum section threshold,
  packet count, and next local section in structured YAML. The action queue can
  be generated with `--only-check video_prompt_section_qa_readiness` to produce
  a 03V-focused queue that prepends `front_03v_playback_gate:S00-S03` before
  any broad S04+ QA unit. The next-unit selector prefers that explicit gate and
  its refresh commands preserve the focused 03V path, avoiding unintended full
  harness state checks or 04 edit-worklist refresh during video-prompt
  continuation work. The focused queue's default output path must be the
  `*-03v-action-queue.yaml` family so a short `--only-check
  video_prompt_section_qa_readiness --write` command cannot overwrite or
  masquerade as the broad harness action queue. Founder-required front gates may
  also emit a schema-backed `automation/founder-gates/*-03v-front-gate-*.yaml`
  decision packet, but that packet only narrows the allowed choices; it must not
  imply paid generation approval, playback pass, external execution, publishing,
  Drive mutation, or a wider section scope. The front-gate validator should
  check this packet's source links, allowed decision ids, approval flags, and
  forbidden-action guards so the founder-facing packet cannot drift from the
  automation gate. The focused 03V refresh may also write
  `automation/current-next.yaml` and `.md` as the stable operator pointer to the
  current founder decision; the validator should check that pointer against the
  same next-unit, action-queue, and founder-gate sources so dated artifacts do
  not drift from the visible "next" surface. A founder decision may be recorded
  as `automation/founder-decisions/current.yaml`; when that active decision is
  an allowed `continue_local_next_section`, the focused 03V action queue and
  next-unit selector should skip the already-surfaced front gate and choose the
  named next local section, while still forbidding paid generation, external
  execution, and QA-pass promotion by implication. That local continuation path
  must be offered only when `next_local_continuation_allowed=true`; when the
  named next section is already playback-only, progression belongs to the
  playback-pass apply flow instead. The current-next pointer should carry the
  selected unit's actionable detail fields, including unfinished checks, review
  actions, packet ids, prompt/image/upload paths, upload-pack `prompt.txt`
  execution paths, continuity notes, validation command, and the still-pending
  front gate, so an operator can resume without opening dated queue files. The
  front-gate validator should also fail stale selected-unit summaries that drift
  from the source worklist, stale prompt/image/upload paths, and missing
  upload-pack `prompt.txt` / `image1.png` / `image2.png` files before automation
  treats the pointer as resumable.
  `scripts/idol_harness_apply_founder_decision.rb`
  may apply a recorded founder choice and refresh the focused 03V queue,
  founder-gate packet, next-unit, and current pointer in one pass; paid or
  external routes still require explicit approval and a named execution route.
- **2026-06-10**: Skill purpose contracts became machine-auditable. Added
  `scripts/idol_skill_contract_matrix.rb` and
  `automation/skill-purpose-contract-matrix-2026-06-10.md` to summarize each
  skill's mode, Required Reads or Read/Write Contract, schema refs, local
  reference/module refs, and write boundaries. `idol-editing-qc` gained an
  explicit `## Output Boundary` so 04 edit work cannot silently promote previews
  or patch prompt truth. Added
  `scripts/idol_video_prompt_section_qa_worklist.rb` and the LOW
  `review/03v-section-video-prompt-qa-worklist-v1.md` artifact so blocked 03V
  section QA becomes a concrete per-section execution queue rather than a long
  validator error, then added the matching schema-backed `.yaml` sidecar for
  automation. The skill matrix now supports strict mode and is wired into
  `scripts/idol_harness_state_check.rb` alongside
  `scripts/idol_skill_contract_check.rb`, so skill contract drift is a blocking
  harness-state failure instead of a manual audit note. Edit readiness status
  matching now treats underscore-joined review/rejected status values as
  non-ready. Added `scripts/idol_edit_readiness_worklist.rb` and the LOW
  `review/04-edit-readiness-worklist-v1.md` artifact so blocked 04 edit
  readiness is broken into final-recipe, active-candidate, shard,
  rough-output, and promotion-guard actions without approving an edit preview,
  then added the matching schema-backed `.yaml` sidecar for automation.
  `scripts/idol_harness_state_check.rb` now also verifies that these blocker
  worklists exist and are not older than their source artifacts, so automation
  can route a blocked run to a current action queue instead of a stale note.
  Added `schemas/harness-action-queue.schema.json` and
  `scripts/idol_harness_action_queue.rb` so the current state report, blocker
  worklists, and Hermes founder gates can be compacted into a schema-valid
  ordered action queue without changing any production approval state. The action
  queue now expands structured blocker worklists into per-unit `next_units` so
  automation can see section QA units, edit recipe locks, shard repair/retire
  units, and rough-output review/reject units without reparsing Markdown. Added
  `schemas/harness-blocker-worklist.schema.json` so blocker worklists are
  machine-readable and schema-validated, not Markdown-only. Added
  `schemas/harness-next-unit.schema.json` and
  `scripts/idol_harness_next_unit.rb` so the ordered queue is reduced to one
  schema-valid resume target under `automation/next-units/`; the selector picks
  the first non-founder-gated unit from the highest-priority blocker before
  falling back to founder-required decisions. Added
  `scripts/idol_harness_refresh.rb` as the single local refresh wrapper that
  regenerates the state report, refreshes blocker worklists, regenerates the
  action queue, emits the next-unit resume target, and validates worklist/action
  queue/next-unit schemas while preserving real readiness blockers as
  `actionable_blocked`.
- **2026-06-10**: 03V and 04 readiness validators were split so automation can
  report the actual blocked surface instead of blaming a broad parent artifact.
  `validate_video_prompt_index.rb` now validates video-prompt index structure,
  prompt semantic carry-through, upload-pack parity, and section-QA linkage
  without requiring section QA to be final `pass`. Section completion is checked
  separately by `scripts/validate_video_prompt_section_qa_readiness.rb`.
  `scripts/validate_edit_map_readiness.rb` similarly owns final-recipe, shard,
  and rough-output readiness for `04-edit-map.yaml`. The state checker now
  reports `video_prompt_section_qa_readiness` and `edit_map_readiness` as the
  remaining LOW blockers while the 03V index itself can pass.
- **2026-06-10**: LOW downstream readiness checks were split between
  structural validity and production readiness. `review.schema.json` now accepts
  current Codex-authored `video_prompt_*` review records as well as legacy
  `grok_video_prompt_*` records. `audio-motion-director-map` validation accepts
  YAML or JSON selected-audio data and preserves legacy audio-analysis pointers
  as audit-only compatibility. `edit-map` schema accepts current repair/QC
  fields, while `idol_harness_state_check.rb` adds a separate
  `edit_map_readiness` gate so missing final recipes, failed shards, timing
  tests, or founder-playback-needed candidates still block automation.
- **2026-06-10**: Package/social readiness gained schema-backed local checks
  without adding a new top-level stage. `schemas/package.schema.json` validates
  run-owned `05-package.yaml`; `schemas/publishing-plan.schema.json` is applied
  through `scripts/validate_publishing_plan.py`, which extracts the required
  metadata, selected clips, draft queue, and approval-state sections from the
  founder-readable Markdown plan. `idol_harness_state_check.rb` now runs these
  checks when the files exist, so Hermes and orchestration can distinguish
  package/social drafts from ledger-ready local state while still stopping before
  upload, schedule, publish, platform API sync, or external Drive mutation.
- **2026-06-10**: Beat splitting was tightened after LOW edit review showed
  that rough seconds and prompt-slot logic can survive too far downstream.
  `production-system`, `generation-review-system`, `idol-generation`,
  `idol-editing-qc`, and the 02/02A/02B schema descriptions now define B##
  beats as music-led screen events, not equal-duration buckets. A beat boundary
  needs cue, pulse, lyric/no-lyric, vocal owner, accent/onset, body phrase,
  camera attention, story, space/object, or edit-handoff evidence. Equal-second
  slicing, PACK_INDEX row matching, prompt-count filling, and old sample shapes
  are explicit hold reasons. Founder correction on the same pass clarified that
  the operative gate is the beat's start/end keyframe contract: 02A, 02B, and
  03V now carry `keyframe_boundary_contract` with `start_audio_cue`,
  `start_keyframe`, `end_audio_cue`, `end_keyframe`,
  `motion_between_keyframes`, `prev_end_to_start`, `end_to_next_start`,
  `edit_point_basis`, and `single_keyframe_exception`. A single review keyframe
  is not enough for video-source readiness unless it is a valid hold, insert,
  empty-scene cut, or founder-approved one-frame exception.
- **2026-06-09**: Named dance vocabulary anchors were added to the existing
  choreography, 02B prompt-compile, and 03V video-prompt language contracts
  without creating a new stage or schema artifact. Terms such as waacking,
  voguing, popping, locking, tutting, house footwork, heels choreography,
  dancehall, or twerking may be used as exact model-facing motion-family cues.
  The exact dance name should stay in the prompt when it improves model
  recognition, then be translated in the same card, prompt note, or
  generator-facing sentence into visible foot route, weight shift, body level,
  hip/torso/hand path, gaze, camera readability, endpoint, and any needed
  idol-performance tone guard.
- **2026-06-09**: 01R MV direction reference mining was reinforced as
  section/function-first research rather than a new route or choreography-only
  pass. When researching, ask how source MVs solve comparable jobs such as an
  intro, reveal, verse entry, hook, bridge, transition, object beat,
  empty-space beat, or ending memory. `choreography` remains a useful keyword
  or source function when the current section needs it, but raw source
  observations still stay in 01R and only adapted current-song functions may
  flow into 01 `screen_cause_effect`, `director_chain`, 02A trace refs, 03V
  motion seeds, or 04 edit seeds.
- **2026-06-08**: Post-review video-prompt motion guidance changed from
  image-plausible-only wording to image-anchored choreography expansion. The
  passed image remains the identity, styling, wardrobe, lighting, camera, source
  order, and endpoint anchor, but `idol-video-prompt` may now use compact
  choreography activation language. For Grok-style video generation, the
  generator-facing prompt header should start with
  `cinematic 4K IDOL choreography music video` when readable body motion is
  needed, and body text may use phrases such as
  `clear K-pop idol choreography phrase` when paired immediately with visible
  body/camera mechanics. A
  `choreography_recovery` note was added to the 03V schema for failed-motion
  cases where ordinary prompts repeatedly produce static poses, camera-only
  movement, or unreadable body motion. Recovery may rewrite `expected_motion`,
  `body_route`, `choreography_bridge`, and `prompt.txt`, but it must route back
  to 01/03V if it would change meaning, member ownership, wardrobe, source image,
  camera anchor, or endpoint.
- **2026-06-07**: 01 screen-flow authoring was tightened inside the existing
  `01` bundle without adding a new top-level harness stage. The
  `song-choreography-performance-mv-map` schema now requires
  `lyric_to_scene_thinking.screen_cause_effect` for visible cause, visible
  effect, viewer/camera change, and next-section bridge, and
  `director_chain.wardrobe_read` for actual outfit description, wardrobe motion,
  readability reason, and reject guard. This change addresses founder feedback
  that abstract phrases such as "signal spreads", "route opens", or "space
  reacts" do not create a saleable/story-readable spine, and that wardrobe must
  show what the member is wearing rather than only naming a mood, color lane, or
  material feel. Follow-up alignment on the same date split the detailed rule
  into `skills/idol-mv-director/modules/screen-flow-wardrobe.md`
  and updated 01R, 02A, 02B, preview handoff, prompt-packet structure,
  PRE-00/research target docs, and 02B validation/export helpers so
  `screen_cause_effect` and `wardrobe_read` survive downstream instead of
  collapsing back to `wardrobe_motion` or abstract flow wording.
- **2026-06-05**: Post-review video camera guidance now includes
  transition-match grammar inside existing 03V/video-prompt and 04 continuity
  fields rather than adding a new harness stage. The `idol-video-prompt` skill,
  `video-prompt-manifest` schema descriptions, and production/review wiki pages
  now allow motivated angle- or direction-matched cuts, reflection match cuts,
  object/garment occlusion wipes, anchored orbit, slight diagonal/Dutch tilt,
  and acceleration-into-cut/deceleration-out timing when the bridge also names
  inherited body direction, speed, step phase, foot/floor contact, hand path,
  garment swing, or body momentum. These terms must preserve source identity,
  wardrobe, and image locks; they cannot hide pose jumps, morphs, or unrelated
  camera angles.
- **2026-06-02**: Post-review video input packs now enforce a one-row-one-clip
  invariant. A `PACK_INDEX.csv` row is exactly one video clip: solo and
  duo/two-member two-cut sources use one `bridge-two-image` row with `@image1`
  and `@image2` attached together, while original founder-passed
  three-plus-member/group frames use one `single-beat` row with only `@image1`.
  The `idol-video-prompt` skill, production and review wiki pages, Codex/Grok
  authoring request generators, and `scripts/validate_video_prompt_index.rb`
  now all preserve that distinction so two-cut clips are not split and group
  originals remain interleaved in beat order.
- **2026-06-06**: Post-review video-prompt validation now blocks structure-only
  packs. Each 03V/index/prompt record must preserve lyric or no-lyric cue,
  audio/tension, visible start pose, body route, camera route, endpoint, and
  previous/next continuity. Generic bridge text such as "follow the beat action"
  or "move between the two visible poses" is invalid even when `PACK_INDEX.csv`
  and upload folders are correct. Follow-up tightening on the same date clarified
  that batch authoring is allowed, but 03V/video-prompt QA must close by section
  key through a run-owned section QA artifact linked from
  `video-prompt-index.yaml`.
- **2026-06-02**: Section-gated production was raised from optional
  downstream sharding into a required execution discipline when selected-audio
  section ids exist or full-track authoring would blur timing, ownership, or
  transitions. This does not add a new top-level harness stage or step command.
  It requires `01`, `01A`, `02`, `02A`, `02B`, `03V`, and `04` work slices to
  finish with section refs, timing, cue, owner, visible response, transition
  in/out, output path, open questions, and status before the next slice
  advances, then keeps the merged canonical artifact as the founder and
  automation gate surface. The lower schemas and owning skills now expose
  matching section-gate fields for 01, 01A, 02/02A/02B, 03V, 04 edit maps,
  edit marker plans, 01R direction cards, and title output registry trace keys.
  Follow-up harness audit also aligned the canonical video-prompt language to
  endpoint/final-hold wording, excluded temporary GPT/Drive source packs from
  the terminology guard, and reconciled active LOW contracts for 02A layout and
  review-emphasis variants, 01R raw-capture guards, lyrics-direction bridge
  motion memo fields, track-board prompt text locks, and title output registry
  post-review statuses.
- **2026-06-01**: PRE-00 Bilibili-only public reference mining was added as a
  bounded discovery supplement for faster/diverse radar research. The rule is
  recorded at the AGENTS permission layer, the PRE-00 specialist page, the
  automation contract, the `idol-research-radar` skill, and the PRE-00 radar
  schema via `research_policy.public_reference_mining_policy`. It also adds
  optional `research_vectors`, reference-level raw observations,
  `source_time_ranges`, `function_extracts`, and route-level
  `downstream_handoff_map` so PRE-00 observations remain inspectable while also
  pointing at later fields such as `target_empathy_seed`, `director_chain`,
  `compile_seed`, `03V`, and 04 edit-readiness. It does not add a new harness
  stage or allow raw media to become generation/edit/source assets.
- **2026-06-01**: 02A GPT/reference intake was tightened as an optional 02A
  review pass, not a new harness stage. Album/title drive-sync lanes are the
  preferred exchange surface, but returned material remains advisory until
  founder selection and run-owned intake. 02A may absorb only beat-level camera,
  blocking, crop, body-level, space/object, wardrobe-readability, or action
  carry-guard refinements inside existing 01 direction; changes to song meaning,
  member ownership, core action/action type, MV world, wardrobe lane, or section
  `director_chain` route back to 01 or 01A.
- **2026-05-30**: Downstream section-shard support was formalized without
  adding new top-level step commands. 02/02A/02B, 03V, and 04 may decompose
  internally by selected-audio section, but founder gates and automation still
  advance from the merged canonical artifacts.
- **2026-05-29**: Initial creation of this page. Moved general maintenance concerns out of `handoff/grok/HARNESS-MAINTENANCE-RULES.md` into a neutral wiki location so both Codex and Grok follow the same standards. Language precision rules were consolidated by reference rather than duplication.

---

**This document is part of the harness surface.** Treat changes to it with the same care as changes to production-system.md or the core skills.
