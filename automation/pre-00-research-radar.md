# PRE-00 Research Radar Automation Contract

## Purpose

Combine audience and current trend evidence, let the Founder lock one primary
target, and produce target-fit route candidates before song direction. Five
routes is common, not a quota; declare a three-to-seven route count and hold
instead of padding weak duplicates.

Every new run also requires a passed causal Story Spine in PRE-00. The Story
Spine states what changes, why it changes, and what audience response/song and
screen reward the change must produce. Five to seven causal states is ordinary
guidance, not a cap or validator quota.

PRE-00 may provide hypotheses and questions. It must not author 00A, Front
Planning, 01, 02A, 02B, 03V, or generation truth.

## Active Contract

Use:

- `skills/idol-research-radar/SKILL.md`;
- `skills/idol-research-radar/references/research-radar-authoring-detail.md`;
- `schemas/pre-00-research-radar.schema.json` version `1.8`.

Write one compact structured artifact only when the Founder explicitly asks for
the full route:

```text
automation/pre-00-research-radar-YYYY-MM-DD.yaml
```

Earlier radar files remain historical evidence and are not active templates.

## Research Inputs

Before a current structured pass:

- read the active audience baseline and evidence needed to compare two to four
  target connections;
- read the active biweekly trend pulse and current evidence needed to separate
  durable signals, current opportunities, and expiry/volatility;
- read the paired weekly idol HTML reports and their image ledger when current
  idol positioning or imagery matters;
- read `source-materials/short-form-trend-reports/weekly/latest.md` and its
  active weekly short-form report when platform behavior matters;
- read the active fashion record when season, silhouette, material, palette, or
  styling matters;
- read Founder references and local source material before public gap search;
- use current research rather than memory-only claims.

If required current evidence is unavailable or stale, hold instead of
presenting it as current.

## Candidate Discipline

Research `audience` and `trend` first to build the target foundation. Then
research these four creative route families separately and combine one useful
function from each:

- song;
- media narrative;
- fashion;
- idol.

Each route:

- serves the locked primary target through a named response mechanism;
- cites at least four distinct creative-route references in addition to the
  audience and trend foundation;
- uses at least one source from every family;
- recommends an active unit without forcing every image to be member-led;
- keeps the message and song direction provisional;
- states one visual-world candidate and observable first-screen hook;
- states the world/relationship change mechanism and a compact beginning ->
  change -> escalation/complication -> peak or plateau -> ending-afterimage
  progression using the PRE-00 comparison fields;
- connects target -> desired response -> song reward -> observable screen
  reward and names participant/reference functions and exclusions;
- carries Song Room/audio validation questions, counterevidence, uncertainty,
  risk, and the later owner of deferred decisions;
- states the principal mismatch or evidence risk;
- contains a `route_seed` made only of song questions, audio validation
  questions, Front Planning hypotheses, source ids, risks, and open questions.

Before target lock, every one of the two to four target connections also shows:

- one main music-video or other visual reference;
- one or two supporting references with different functions;
- exact source id and locator for review;
- why the target responds to each reference;
- proposed transfer function and mismatch risk; and
- why the main governs while support stays subordinate.

These previews make the Founder decision concrete. They are not final Front
Planning reference dispositions or section bindings.

For reference-led MV work, one exact main idol song is the audience base. Its
song-specific profile must be `verified_current_run` before selection. Give
each visual scene/world reference a separate audience profile, then resolve the
title target across viewer situation, desired reward, literacy/codes, platform
behavior, and rejection triggers. Selected scene anchors may narrow the base or
act as a bounded acquisition bridge. Surface-only, rejected, missing, empty, or
contradictory intersections hold; no fandom union or silent target replacement
is allowed.

Do not write exact later-stage field paths. Use the broad downstream roles in
the active schema.

HOLD a route with no beginning, change mechanism, causal progression,
peak/plateau, or afterimage; one that survives target/song/member/world noun
swaps; one that leaves Song Room to invent the dramatic premise; one whose
references provide vibe only; or one whose audience reward remains an
adjective. Also HOLD overreach into exact timecodes, final sections, camera,
shot count, choreography, Core/Branch Cuts, prompts, member distribution, or
intermediate videoization. No Song Room, selected-audio, Front Planning, 01, or
downstream stage opens from a missing or held Story Spine.

## Reference Connection

When a main reference has a source ancestry, trace:

```text
main reference
-> original myth, story, genre, history, or formal system
-> derived or adjacent work
-> audience reward
-> candidate song or screen function
```

Use an encyclopedia-style source to discover names and relationships, then
confirm important meaning in an original or official source. AMVs, MADs, and
short edits may provide evidence of repeatedly selected moments; they do not
replace original context.

Every connection preserves literal observation, inference, counterevidence,
source identity, locator, candidate function, and a validation question.

## Public Media Boundary

Public web research may be used only within the current approved research
scope. Do not use private connectors, logged-in sessions, account cookies,
paid APIs, uploads, publication actions, or external writes without exact
Founder approval.

Founder-approved Bilibili capture:

- uses only public pages and the registered video-reference hub;
- uses no cookies or private sessions;
- retains one source-hub original plus bounded contact-sheet, frame, subtitle,
  chapter, or short analysis evidence;
- records literal observations before candidate functions;
- never becomes an automatic generation input, edit source, prompt attachment,
  catalog output, or public package.

The structured artifact records
`research_policy.public_reference_mining_policy`. Missing provenance or
source-hub ownership is a hold.

## Current Evidence Reuse

Reuse active local evidence before duplicate research. Open the weekly HTML
before its image ledger. If a later run selects one embedded figure, Front
Planning decides whether it is:

- a direct reference-connection candidate; or
- a current-title visual asset-production candidate.

The report and extracted pixels do not create a visual lock or generation
attachment.

## Freshness

Use these working windows unless the Founder overrides them:

- current-run web research: current pass, with a 14-day recheck for delayed
  selection or release/news-dependent claims;
- trend pulse: roughly two weeks;
- fashion-season evidence: current season, usually eight to twelve weeks;
- promotion-tied idol signals: two to four weeks;
- short-form platform report: one week;
- narrative functions: durable as story evidence, not as a current-market fact.

Promote only Founder-selected, review-proven, or repeatedly useful functions to
durable banks or source material.

## Founder Gate

Before song direction, the Founder decides whether to:

```text
lock one primary target and its target/trend content contract
select one route
combine named routes and functions
request another pass
archive the brief
```

Record the target in `target_trend_foundation` with
`lock_status: founder_locked` and the route decision in `founder_selection`.
The selected route must already carry a Director-reviewed causal Story Spine;
selection cannot waive or defer that readiness gate.
It must also contain `storyline_lineage.pre00_storyline_original`: one complete
natural-language opening-to-ending MV flow with a raw-text hash, contextual
density PASS, and exact reference functions/exclusions. The original is
immutable. Later changes append a new complete full-text version with parent
hash, reason, changed passages, preserved invariants, and reference receipts;
compact progression fields never replace it.
The nested `primary_target.reference_audience_lineage` records the adopted main
song base, scene-anchor dispositions, resolved intersection, exclusions, and
evidence state.

That exact selected radar is the trigger for the registered deterministic
`scripts/idol_pre00_selection_handoff.rb` builder. Because the lineage is inside
`primary_target`, the builder exact-copies it without authoring or summarizing
new values. Graph Engineering creates one
`idol-pre00-selection-handoff.v4` artifact at the stable run-owned path
`RUN/research/pre00-selection-handoff-v1.yaml`; the compatibility filename stays
fixed while the active payload contract is v3. The handoff exact-copies the
complete storyline lineage for Song Room, Front Planning, 01, 02A, 02B, 03V,
and 04. Before first Workbench context
binding, the native host uses the script's read-only inspect route to verify the
handoff schema, payload hash, selected-radar path/hash/status, and every
exact-copy binding. It then gives that same bounded payload to the existing
Song Room context and the CDD's asynchronous visual-preparation context. The
Founder supplies no second brief or startup command. Handoff creation and
inspection start zero model turns, create no stage, and grant no external or
paid-generation authority. A non-stable path, missing/stale source pointer,
unresolved selected route, or existing conflicting output is a HOLD rather than
a guessed repair or overwrite.

Valid next actions are:

- `design_song_direction`;
- `prepare_manual_or_suno_candidate`;
- `analyze_founder_selected_audio`;
- `hold`.

After an audio take is actually selected:

```text
selected-audio analysis
-> audio-motion director map
-> 00A song-production lock
-> Front Planning
```

PRE-00 never skips that chain.
The selected song and Front Planning may test whether they deliver the locked
audience promise, but they cannot silently select another target. A material
mismatch revises or rejects the song/route unless the Founder explicitly
reopens PRE-00.

## Hold Conditions

Write a schema-valid `status: hold` artifact when:

- audience or trend evidence is missing, stale, or too weak to support a target
  lock;
- the main reference song audience is not current-run verified, a selected
  scene audience is surface-only/unverified, or their intersection is empty or
  contradictory;
- a target connection lacks one main and one-to-two reviewable supporting
  visual references;
- fewer than four usable creative-route source identities exist;
- fewer than three distinct routes survive;
- a route lacks a reference family;
- the declared route count would require filler;
- a route cannot state a concrete audience, song, or screen consequence;
- sources are too vague to reject a wrong connection;
- current claims are stale or unverified;
- the work requires unapproved paid generation, download, private access,
  upload, publication, or other external mutation.

## Verification

Before completion:

- validate against schema version 1.6;
- confirm one primary target, audience promise, content contract, trend
  synthesis, counterevidence, freshness note, and do-not-copy rule are present;
- confirm the main-song base, every selected scene-audience disposition, the
  five-dimension intersection, and exclusions are present and resolved;
- confirm every target connection has one main and one or two supporting visual
  previews with exact locators, distinct functions, and mismatch risks;
- confirm declared and actual route counts match;
- confirm every reference id resolves once;
- confirm each family list is a subset of the route's source ids;
- confirm route seeds remain questions and hypotheses;
- confirm the Founder-locked target foundation and only the selected route enter
  the song candidate path;
- confirm no later creative or generation artifact was created.
