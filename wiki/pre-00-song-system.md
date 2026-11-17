# PRE-00 And Song System

This page holds detailed rules for lightweight PRE-00 inspiration, PRE-00S
reference-song fit, selected-audio analysis, and song lock. Use it when starting
a route, evaluating a song reference, writing a Suno/manual packet, or promoting
a selected audio take.

## Two Song Analysis Lanes

Keep these lanes separate:

- `reference-song fit`: pre-generation reference analysis. It reads
  founder-provided reference songs, sections, or timestamps to extract wanted
  functions, rejected traits, unit fit, and Suno/manual prompt guidance. It
  writes `research/reference-song-fit-vN.md` and may follow
  `schemas/reference-song-fit.schema.json`. It is not our generated song
  analysis and must not write `selected-audio-analysis-vN.*`.
- `selected-audio analysis`: post-generation or post-intake production
  analysis. It reads the actual Suno/manual/founder-returned candidate take that
  may become the track. It writes
  `research/selected-audio-analysis-vN.md` and optional `.json` using
  `schemas/selected-audio-analysis.schema.json`.
  It must be deeper than reference-song fit: keep sound texture, hook mechanics,
  speed/groove, song feel/temperature, vocal/rap color, production dynamics, and
  reference-fit delta before making 00A, Front Planning, 01, or 02A decisions. If the song has
  lyrics, it must start from the original lyric/transcript source, not a hook
  summary or remembered section labels.

Do not call both artifacts "audio analysis" in founder-facing routing. Reference
song fit helps make the song; selected-audio analysis analyzes the song we may
actually produce.

## PRE-00 Target, Trend, And Inspiration Brief

PRE-00 begins with a light Founder-facing comparison surface, then closes one
run-owned target/trend foundation before song direction. The chat cards stay
compact; the selected contract carries the evidence needed for the lock and
one complete natural-language opening-to-ending MV storyline.

Use PRE-00 to offer compact cards the founder can react to:

- possible situation or emotional premise
- target connection, audience promise, and attraction/rejection trigger
- current trend opportunity, expiry/volatility, and do-not-copy boundary
- one main music-video or other visual reference and one to two supporting
  references, with exact locator, distinct function, and mismatch risk
- one-line message direction
- possible song feel or reference family
- possible MV image or object hook
- obvious risk or avoid note
- why it may be worth expanding

Keep these cards short enough that the Founder can quickly choose, combine, or
reject connections. Do not create contact sheets, reference-song metrics, deep
MV interpretation, selected-audio analysis, song locks, or long source packs by
default. Song direction remains held until the structured/run-owned PRE-00
records the Founder-locked primary target, current trend synthesis, immutable
full storyline original, contextual density PASS, and its exact reference
functions/exclusions. Compact candidate cards never substitute for that
selected full-text storyline.

The real start happens after the founder selects or expands a route. Then create
a run-owned intake brief similar to LEFT IN THAT NIGHT:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/harness-intake-brief-vN.md
```

That intake should preserve the concrete situation, message, memory/source
details, reference names, visual objects, lyric seeds, private/public guards,
and founder corrections. From there, route into PRE-00S reference-song fit,
Suno/manual prompt, selected-audio analysis, and downstream production as
needed.

## PRE-00 Research Radar

The radar is a candidate generator and evidence surface, not the decision
maker. The Founder locks one primary target after comparing two to four target
connections; the radar then offers three to five target-fit routes that vary
message, song emotion, unit, performance hook, MV image, and risk profile.
Each target connection must be visually judgeable: show one governing main
reference and one or two supporting references, why the target responds to
them, what each contributes, and where the combination could mislead. These
previews support target selection; Front Planning later reinspects and binds
the final reference use by section.

For a reference-led title, PRE-00 `1.8` first adopts the exact main idol song's
verified audience as the title-target base. It then profiles each candidate
scene/world reference audience and selects only an aligned narrowing or bounded
acquisition bridge. The resolved target is the evidence-backed intersection of
viewer situation, desired reward, code literacy, platform behavior, and
rejection triggers. A generic Loom/K-pop baseline remains context only; a
surface match, fandom union, or contradictory intersection cannot become the
title target.
The active trend pulse is refreshed every two weeks from weekly idol activity
HTML reports, the separate weekly TikTok/Instagram short-form platform report,
and current public-source checks. The two weekly reports have different owners:
one observes group/promotion activity and the other observes platform-native
attention, participation, sound, camera, editing, text, and replay behavior.
PRE-00 may point toward possible
song-reference lanes, but PRE-00S reference-song fit should not run until the
founder has supplied or selected song references worth expanding. A recurring
discovery pass should run only when the founder wants new ideas or the active
slate needs refresh.

Before PRE-00 or new song brainstorming, read:

```text
source-materials/trend-pulse-records/latest.md
source-materials/audience-research/global-kpop-fandom-target-v1.md
```

When the route needs current group/activity examples, style scans, fan/proxy
signals, or available statistics, also read:

```text
source-materials/idol-activity-reports/weekly/latest.md
```

When the route depends on a current short-form hook, participation mechanic,
audio-entry behavior, camera/crop pattern, loop/edit grammar, caption/text role,
save/share proxy, derivative strategy, or CF platform behavior, also read:

```text
source-materials/short-form-trend-reports/weekly/latest.md
```

Do not treat a weekly platform signal as direct creative direction. PRE-00 uses
only the transferable function accepted by the active biweekly pulse, while
preserving platform scope, evidence status, lifecycle phase, proxy limitation,
and source-application scope.

PRE-00 may include public Bilibili reference mining, and registered public
Instagram single-URL capture, only when the founder explicitly asks for a
research pass, or when a selected route has become a run-owned intake and needs
source support. Use it as a supplement to the active trend pulse and current-run
research, not as a replacement for either.
Build Bilibili search/sample lanes, and named Instagram post/Reel/IGTV samples
when needed, from the active trend questions and route gaps, then preserve
literal source observations first: visible hook behavior, camera/crop pattern,
performance readability, song structure pressure, audience signal, styling cue,
staging, and exact timestamp window. Add extracted functions after the raw
observation, not instead of it. `yt-dlp` is allowed only through the registered
Bilibili and Instagram public wrappers without account cookies, and only to
create metadata, timestamps, low-resolution contact sheets, short analysis cuts,
or audio/onset facts that become notes. Raw media must not become a durable IDOL
asset, generation reference, edit source, prompt packet input, or catalog
output until founder-selected and registered through the source hub. Record the
boundary in `research_policy.public_reference_mining_policy` when used.

When the founder asks for more than light cards, PRE-00 research can become
field-ready. Choose vectors from this set based on the active trend record and
current route gaps:

- `trend_hypothesis_fit`: what the active trend pulse predicts, what the
  source confirms, and what it contradicts.
- `song_hook_structure`: the actual intro arc and its ordinary 8-12s setup
  range, sonic identity, hook seed or deliberate hold, pre-hook, first full
  hook, middle return, phrase-hit density, rhythm pressure, and section function
  for `reference-song fit`, selected-audio analysis, and later `00A` trigger
  cues.
- `target_empathy_message`: viewer situation, identification point, emotional
  promise, and mismatch risk as evidence for the PRE-00 target lock and later
  Front Planning translation.
- `choreography_performance_readability`: visible body action, hand/foot/gaze
  cue, formation or member focus, and crop safety as evidence for Front
  Planning section assignment, optional choreography use, and later 01
  observable action. PRE-00 never turns this into a song-lock action.
- `camera_edit_grammar`: shot scale, camera height/angle, move or hold, cut
  timing, and readable motion event as evidence for Front Planning reference
  use, 01 still-camera authorship, 02A coverage, 03V temporal camera motion, and
  04 edit-readiness. PRE-00 does not lock the route.
- `mv_world_storyline`: space, object, foreground/empty-scene insert, conflict
  or turn, and visual metaphor as a Front Planning reference-connection and
  section-spine candidate that 01 may later expand.
- `wardrobe_material_motion`: silhouette, material behavior, accessory cue,
  color limit, and body-proportion risk for the Front Planning current-title
  visual package and later 01 action/material consequences.
- `unit_member_identity_fit`: which active unit/member can own the route,
  vocal/performance role, center risk, and asset-fit constraint for
  Front Planning member/section assignment.
- `generation_promptability_risk`: whether the idea can become stable
  Core-Cut events and distinct Branch-Cut screens without member/body/world
  confusion for Front Planning, 01, 02A, and 02B.
- `derivative_social_viability`: 8-15s replay moment, thumbnail/readable first
  frame, 45s cutdown shape, and short caption hook for `derivative_plan_seed`
  and later social planning.
- `short_form_platform_behavior`: TikTok-specific, Instagram Reels-specific,
  and cross-platform hook/audio/camera/edit/text/participation/replay mechanics;
  evidence phase and saturation; platform divergence; and what can be
  transferred without copying a creator post or campaign surface. Feed the
  audience/content search question, `derivative_plan_seed`, and later platform
  adaptation rather than locking an MV route by itself.
- `source_diversity_raw_trace`: source-lane mix, exact observed detail, timestamp
  windows, and raw/source-to-route trace for `source_ref_ids`,
  `source_time_ranges`, `function_extracts`, and downstream trace refs.

When public references are captured with `yt-dlp` or a similar local intake
helper after founder approval, preserve video and audio together when both are
available:

- source video or sampled contact sheets for screen grammar, camera, action,
  crop, styling, and edit observation
- source audio for BPM feel, beat/onset density, vocal/pitch proxy, arrangement
  evidence, and repeated motif/hook candidates
- source identity: title, artist/channel/source, URL or local path, timestamp
  range, and the specific function being analyzed

For reference-audio analysis, scripts may create beat grids, onset candidates,
energy windows, pitch-contour proxies, vocal-register/timbre evidence, and
repeated motif/hook candidates. They must not create current-run cut-pressure
scores, current-run section video functions, final Suno prompt wording, or MV
edit decisions. Those belong to Codex/founder interpretation and, after a real
candidate take exists, selected-audio analysis.

When wardrobe, material, silhouette, color, or accessory direction matters, also
read:

```text
source-materials/fashion-trend-records/latest.md
```

References should be current enough for their function:

- trend-pulse records refresh every two weeks
- weekly idol activity HTML reports refresh weekly when the active slate needs
  current idol/group observation
- weekly TikTok/Instagram short-form platform reports refresh weekly when hook,
  derivative, participation, or platform behavior matters
- fashion records refresh by season or after roughly 8-12 weeks when styling depends on them
- public idol/pop promotion signals should usually be rechecked within 2-4 weeks
- current-run web research should be rechecked before Front Planning if more
  than 14 days pass
- narrative media references can live longer as function material, not trend validation

PRE-00 routes combine reference families:

- `song`: structure, hook mechanics, rhythm tension, vocal/rap color, song message
- `media_narrative`: message, character position, conflict, emotional premise, visual metaphor
- `fashion`: silhouette, material, color, accessories, construction
- `idol`: AURORA-M member/unit/voice/performance-readability ownership

Use active trend-pulse, weekly idol-activity HTML, weekly short-form-platform
HTML when relevant, fashion records, local IDOL assets, and message-hook bank
dedupe before doing duplicate research. Newly useful message
functions and hook combinations should go to `creative-bank/message-hooks/`
only when they are useful enough to prevent reuse.

Only Founder-selected PRE-00 material should move into the content run as
`research/pre-00-research-radar.yaml` or into a run-owned
`research/harness-intake-brief-vN.md`. It must carry the complete locked target,
trend synthesis, content contract, nested reference-audience lineage, only the
selected route, and `storyline_lineage`. The active v3 registered handoff
exact-copies both `primary_target` and the complete storyline lineage: immutable
original, active full-text version, append-only revision history, contextual
density review, and exact reference snapshots/functions/exclusions. Song Room,
Front Planning, 01, 02A, 02B, 03V, and 04 read that full lineage; no compact
`whole_film_progression` or section summary replaces it. PRE-00 never creates
an active 00 artifact. If no selected/promising song, Founder song/source anchor, or
Founder-locked manual audio direction exists, keep the work in intake,
PRE-00S, Suno, or manual exploration. After an actual take is selected, analyze
it, create the audio-motion map and 00A, then let Front Planning preserve the
locked target and immutable storyline original while appending any necessary
parent-linked full-text revision and authoring message, references,
current-title visuals, and the whole-video/section execution spine.

## PRE-00S Reference-Song Fit

For song-led routes, especially title/debut routes where hook feel decides the
unit, insert a PRE-00S reference-song fit pass before a Suno prompt.

Preferred input:

```text
founder-provided song / section / timestamp
-> reference read
-> unit fit
-> wanted traits, usable mechanics, and rejected traits
-> Suno/manual prompt packet only after fit is clear
```

Read references for:

- opening architecture: first sonic identity signal, actual intro boundary,
  setup promise, and hook seed or deliberate hold
- rap placement
- verse pocket
- pre-chorus lift
- chorus mechanic
- rhythm/tempo feel
- arrangement/instrumentation function: drums and percussion, bass/low end,
  lead or texture instruments, harmony bed, FX/sound design, silence/drop, and
  how each layer creates body timing, hook memory, section lift, or scene
  pressure
- melody/topline function: contour, hook motif, phrase length and spacing,
  landing/release points, section contrast, vocal events, and how the melody
  makes the message readable
- repetition / motif function: recurring melodic cell, chant, call-response,
  instrumental riff, rhythmic loop, lyric phrase, phonetic hook, or preview
  hook that appears before the chorus and returns later. Record how the
  repetition is introduced, intensified, varied, or quieted, and how it should
  shape Suno Style/Lyrics while keeping the new song's own wording.
- vocal pitch / color evidence: whether the useful reference surface sits in a
  high, middle, or low-feeling register; whether the attack is breathy, bright,
  chesty, soft, clipped, rap-adjacent, group-stacked, or call-response; and
  which claims are manual listening judgments versus pitch-contour proxy
  evidence from local audio.
- numeric BPM or defensible BPM feel, with source or estimate status
- duration / runtime family
- lyric density: line count, phrase-hit count, syllable/word cluster length,
  repeated hook density, and section-by-section vocal-entry spacing
- meaning delivery: what message, feeling stance, hook claim, or listener
  identification the reference makes clear, and how lyric placement, repetition,
  section order, vocal emphasis, contrast, silence, or release makes it clear
- vocal color
- song feel/temperature
- unwanted traits

Lyric/section structure is mandatory when available. Inspect reliable lyric or
line-distribution structure for intro, verse, rap, vocal turn, pre-chorus,
chorus, post-chorus, interlude, bridge, outro, ad-lib, or vocal-burst placement.
Use it to map function, part architecture, mood, contrast, and reference feel.
When lyrics or a reliable meaning read are available, also map the reference's
meaning-delivery method against the current run's original lyric/message target:
what the listener is meant to understand or feel, which phrase or silence makes
that clear, which section turns the meaning, and what must be rewritten as an
original IDOL lyric instead of copied reference wording.

BPM and lyric-density analysis is mandatory for founder-provided reference
songs when they are shaping a Suno/manual prompt. Do not rely only on genre
labels or vibe adjectives. For each reference, record:

- BPM or BPM feel, and where it came from; if unavailable, mark it as an
  estimate or unknown rather than inventing certainty
- duration or analyzed timestamp range
- available lyric/transcript status
- number or estimate of short phrase hits, repeated hooks, and long sentence
  lines
- section density map: where the reference is sparse, where it stacks vocal
  hits, where it repeats, and where it stretches
- meaning-delivery map: where the reference states, hides, repeats, turns, or
  resolves its message, and how that should inform the new song's original lyric
  pressure, hook clarity, target-empathy receive, and section order
- arrangement map: which instruments or production layers carry movement,
  hook memory, contrast, or transition; record the function, not just the
  instrument name
- melody/topline map: how the melody rises, falls, repeats, lands, stretches,
  chants, or leaves silence, and how that should shape the new song's hook,
  section length, vocal delivery, and lyric spacing
- target translation: expected runtime range, section lengths, phrase-hit
  density, and line-length rules for the new song

Use this density read to decide how much text belongs in the Suno lyrics box.
At similar BPM, fewer lyric hits usually makes the song feel more open or slow;
more short phrase hits makes the song feel faster, more edit-ready, or more
chant-driven. Longer sentence lines should be placed only where the reference
also stretches, usually pre-chorus, bridge, or lift sections.

Do not paste numeric BPM into the copy-ready Suno Style box by default. Use
exact BPM only when the founder locks it, when the reference-song fit says the
BPM itself is part of the function, or when selected audio confirms it. The
internal reference fit must still record BPM/duration/density so prompt lyrics,
section length, and runtime are not guessed.

Reference-song fit artifacts should follow
`schemas/reference-song-fit.schema.json` and expose:

- founder references
- BPM / runtime / lyric-density fit
- arrangement / instrumentation fit: layer functions, section arrangement map,
  target translation, and Suno style/negative implications
- melody / topline fit: contour, hook motif behavior, phrase spacing, landing
  points, vocal event map, meaning connection, and Suno style/lyrics
  implications
- meaning-delivery fit: reference meaning read, current lyric/message target,
  transfer method, mismatch risk, and direct-reference-following note
- wanted functions
- rejected traits
- recommended active unit
- prompt handoff readiness
- founder decisions still needed

### Pre-Suno Source / Reference Lineage

Before writing a Suno/manual prompt packet for a reference-led or source-heavy
route, close a lightweight lineage check inside the existing artifacts. Do not
create a new top-level schema, new `intent_*` field family, or new stage name
when the existing fields can carry the data.

Use these existing fields as the carry-forward contract:

| upstream need | existing field to use | downstream consumer |
| --- | --- | --- |
| core song/message intent | `meaning_delivery_fit.current_lyric_message_target` and `prompt_handoff.lyrics_seed_policy` | Suno prompt packet, selected-audio reference-fit delta, Front Planning and 01/02A direction |
| founder-provided song/media/source refs | `founder_references[].ref_id` and `source_links[]` | Suno packet notes, selected-audio reference-fit delta, and Front Planning source trace |
| usable musical or lyric-delivery functions | `function_breakdown[].function_id`, `source_ref_ids`, `wanted_function`, `prompt_translation` | Suno Style/Lyrics/Negative boxes and selected-audio `reference_fit_delta` |
| instrument, arrangement, or production-layer functions | `arrangement_instrumentation_fit` plus related `function_breakdown[]` IDs | Suno Style/Negative boxes, selected-audio reference-fit delta, audio-motion questions |
| melody, topline, phrase, or vocal-event functions | `melody_topline_fit` plus related `function_breakdown[]` IDs | Suno Style/Lyrics boxes, selected-audio hook fit, audio-motion timing map |
| visual boards, contact sheets, image bundles, or local analysis packs | `source_links[]` with a short function note | Front Planning 01R/01R-C reference connection, 01, and 02A |
| selected-source surfaces, mismatch notes, or non-selected-source drift | `rejected_traits[]` and `meaning_delivery_fit.mismatch_risks` | Suno Negative box, Front Planning and 01/02A review questions |

The Suno packet may add a readable `Source / Reference Lineage` markdown section,
but it should cite these existing field IDs and paths instead of inventing a
parallel source model. If a run needs extra context, add it as a run-owned
`research/*-intake-vN.md` or bundle file and point to it from `source_links[]`.
Only add a new schema field when a later validated artifact cannot otherwise
trace the source, function, or decision.

This artifact is not allowed to decide final 90s+ master timing, final section
cuts, final lyric interpretation, 00A lock fields, or 02A beat logic. Those
belong to selected-audio analysis and later production files after a real
candidate take exists.

Scripts may extract reference-audio features such as tempo estimate, onset
density, energy windows, beat-grid sidecars, band-energy share,
percussive/harmonic balance, chroma change, pitch-contour proxy, vocal-register
evidence, and repeated motif candidates. They must not name the creative
function by themselves. Codex must listen/read and write the actual
`arrangement_instrumentation_fit`, `melody_topline_fit`, motif/repetition
transfer, and `function_breakdown` interpretation.

## Suno / Manual Prompt Packets

`idol-suno-prompt` writes a run-owned copy-ready packet after unit/song fit is
chosen. It does not run Suno, call paid audio APIs, or lock final audio.

The runnable Suno surface should stay simple and explicitly named:
`Suno Prompt: Style`, `Suno Prompt: Lyrics`, and `Suno Prompt: Negative`. When a
reference-led prompt needs a few decisive instrument or melody-inst anchors, put
them in an `Optional Style Add-On` directly after the base Style so the founder
can paste them into Style or omit them for an A/B run without rewriting Lyrics.

Prompt lyrics are hook probes, not final locks. When the founder returns a
generated take, transcribe or summarize the actual hook moment and fit final
hook language to the audio instead of forcing prompt lyrics to survive.

During live Suno exploration, do not mutate `00A`, Front Planning, active handoff fields,
or memory for every style, lyrics, hook, or prompt draft. Drafts stay in chat
or in a run-owned packet only when the founder asks to save one. Production
truth changes after a selected take or explicit lock.

When a run-owned Suno/manual prompt packet becomes the current founder manual
test, refresh the compact run intake or current handoff note if one exists. It
should name the latest `reference-song-fit-vN`, the current
`suno-prompt-packet-vN`, source/reference bundles such as visual, contact-sheet,
and audio-analysis bundles, and the exact founder return needed. Do not create a
new schema for this refresh unless automation needs validation; use existing
`source_refs`, `source_links`, packet notes, or the run's compact intake first.

## Song Lock

Song direction should be settled before choreography, performance direction, MV
direction, and generation packets become detailed. Do not create an active 00A
until the Founder has selected an actual audio take.

The song lock is a compact decision contract. It records what the production
will not change; it is not the full selected-audio analysis, Front Planning, or
the 01 direction map. Keep source references and deep section notes in
`research/selected-audio-analysis-vN.*`. PRE-00 owns the Founder-locked primary
target. Front Planning exact-projects that target, tests selected-song fit, and
owns the MV message, member/reference/visual assignment, and section flow.
Target reselection stays in PRE-00. 01 owns shootable action, staging, space use,
and still-camera geometry.

The song lock owns only selected-song decisions:

- selected audio status and exact selected-take identity
- selected-audio analysis path and SHA-256
- audio-motion map path and SHA-256
- source original lyric/transcript file when lyrics are draft or locked
- BPM/BPM feel and perceived pulse summary
- canonical section ids, time ranges, and lyric-function summaries
- hook, opening-arc behavior across the actual intro boundary, and the
  recognizable carrier shared by the first full hook and middle/later returns
- song editability read from selected-audio analysis: audible section
  boundaries, musical anchor events, cutdown viability, and static-loop risk
- non-negotiable trigger cues
- song-derived meaning and emotional guards for later Front Planning
- audio-pressure summaries and unanswered Front Planning questions
- from active schema `1.5`, selected-take craft consequences, canonical section
  timing, lyric/music function, energy/density, audible triggers, and meaning
  guards

There is no section-to-screen action map in 00A. Front Planning chooses what
each section shows after target, message, current-title visual identity,
members, references, and whole-video progression are considered together.
01/02A then author observable action and still-frame geometry; 03V authors
temporal camera motion only after passed images exist.

When a selected take arrives, create or refresh selected-audio analysis first,
then create the audio-motion map from its actual generated/founder-returned
lyrics and timing before promoting `00A` or Front Planning. If the selected
audio later changes, revise 00A first and invalidate only affected Front
Planning, 01, 02A, 02B, 03V, or 04 scopes.

## Selected Audio Planning Draft

Before promoting selected audio into 00A, create a Founder-facing
planning draft in `research/selected-audio-analysis-vN.md` and, when useful,
`research/selected-audio-analysis-vN.json`.

It must be section-first. Do not accept a vague "intro/verse/chorus" summary as
the first serious song analysis.

Required contents:

- `lyrics_original`: run-owned original lyric/transcript source and original
  text for the selected take. This comes before `lyrics_full_read`,
  section_map, song editability, director seeds, cue BPM, or 04 handoff. If the
  full lyrics are unavailable, mark the missing original as a blocker/risk.
- `sonic_function_read`: whole-track sound/function analysis of the actual
  candidate take. Include sound texture, hook mechanics, tempo/speed/groove,
  song feel/temperature, vocal/rap color, production dynamics, reference-fit
  delta, and downstream questions for Suno retry/keep, 00A, Front Planning,
  choreography/performance, 02A coverage, and edit.
- precision audio marker sidecars when the track will drive MV/edit work:
  create or cite beat-grid, onset-candidate, pitch-contour-proxy, and repeated
  motif candidate files with timestamps rounded to at least `0.001s`. These
  files are evidence for selected-audio analysis, audio-motion maps, 00A
  editability guards, 01/02A timing, and later 04 edit marker planning. They do
  not lock exact 04 cutpoints by themselves.
- `song_editability_read`: post-generation read of whether the actual song has
  usable audible edit anchors. Name section-boundary readability, vocal entries,
  pickups, landings, hook hits, ad-libs, backing drum/percussion hits, bass
  hits/drops, texture-density changes, silence or breath gaps, resets, breaks,
  final tags, cutdown viability, and any static-loop risk. This is analysis
  after a returned take, not a Suno prompt-writing rule and not a 04 cutpoint
  decision.
- exact available lyric/transcript source, with uncertain words marked
- `lyrics_full_read`: full-song meaning pass before section directing. It must
  state whether full lyrics/transcript are available, summarize the whole lyric
  arc, identify message turns/repeated phrases, map unresolved or uncertain
  lines, and explain how the complete lyric changes the selected-song listener
  response evidence, reference-song meaning-delivery comparison, and downstream
  questions for Front Planning, choreography, and edit decisions. If lyrics are not
  available, record that as a blocker or risk instead of skipping the field.
- canonical section architecture using `intro`, `verse`, `pre_chorus`,
  `chorus`, `post_chorus`, `interlude`, `bridge`, `outro`, or explained
  `other`
- section BPM/pulse read, energy curve, local tempo spike or boundary notes, and
  section-level `sonic_read`: sound texture, hook or motif, speed/groove,
  emotion shift, and production detail
- full-song and section-level repetition/motif read: recurring melody cell,
  chant, call-response, instrumental riff, rhythm loop, lyric phrase, phonetic
  hook, preview hook, return variation, and the downstream question for Suno
  retry, hook lock, 00A trigger cues, and later Front Planning variation.
- vocal pitch/color read: manual listening judgment plus any pitch-contour proxy
  evidence for high/mid/low-feeling vocal register, rap vs sung phrase, held
  note, group stack, breath, attack, brightness/darkness, and where the vocal
  line opens space for longer screen holds.
- section/audio-layer cue map for later section and beat splitting: lead lyric
  or no-lyric cue, vocal/rap entry, ad-lib, pickup, landing, backing
  drum/percussion accent, bass hit/drop, texture-density change, silence/breath,
  and which of those cues are true boundary evidence versus background texture
- lyric meaning and section function as a section seed, not a finished directing
  chain. Selected-audio analysis should name what job the lyric section does in
  the song, but it should not pretend to finish choreography, camera blocking,
  scene blocking, or wardrobe motion by itself.
- `lyric_function_seed` for every active section:
  `role_label -> section_job -> lyric_pressure -> audio_trigger -> downstream_question`.
  Here `lyric_pressure` is the compatibility field name for the lyric
  cue/tension the downstream question must resolve.
  Use role labels only as indexes, such as declaration, pull, lift,
  hook_landing, body_memory, reset, close_confession, final_return, or
  final_seal. Example: `declaration -> quiet control starts before the song gets
  loud -> the listener should lean in before understanding why -> low-body
  accent -> Front Planning must decide the section role and 01 must later make
  its body/object state observable`.
- selected-song listener response evidence, compared against the locked PRE-00
  target rather than used to select another target
- vocal/rap role and voice-fit evidence without final member allocation
- song-derived screen-readability questions without choosing choreography,
  action, or camera
- open Front Planning questions for locked-target fit, message, member
  assignment, visual identity, references, and section flow
- promotion recommendation for 00A

After this draft, create or refresh
`research/audio-motion-director-map-vN.yaml` for video/MV-bound work. An
existing catalog track board may mirror the resulting status, but it is a
derived read model and never an active gate or second planning owner.

## Front Planning

After a Founder-locked PRE-00 target/trend foundation and passed 00A, create the
run-owned detailed Front Planning report:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/front-planning-readiness-vN.yaml
```

Use `schemas/front-planning-readiness.schema.json`.

This ordering applies to new runs. A run already beyond the boundary, including
an active Front Planning review, keeps its accepted target baseline unless the
Founder explicitly reopens it.

This is the canonical detailed planning artifact, not a pointer-only index or a
form that later stages refill. It owns:

- exact locked-target projection, selected-song fit, and audience promise;
- MV message and emotional result;
- whole-video and section progression;
- integrated 01R reference connection and optional 01R-C selected crops;
- current-title member visuals, background/space, object/material assets, and
  exact section assignments;
- member allocation and choreography policy;
- major scene flow in each section;
- section entry/exit continuity and downstream 01 questions.

Current-title visual assets live under
`assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**`. INK demonstrates
organization and review depth only; its styling and pixels never transfer to a
new title. A profile, character board, or other input used to create a member
visual stops at that asset-production job. Later 02A/02B generation uses the
passed current-title member visual, not a separate face-reference lane.

Sequence sheets are frame flows captured from public video sources. Front
Planning assigns selected sequences or frame/crop scene references to sections
and records their exact direct use. 01 expands their action, staging, still
camera, placement, crop, and ordered grammar. Contact sheets remain navigation
evidence; selected cells/crops travel as their own paths and hashes.

Automation validates schema, paths, hashes, exact projection, and review state.
It does not select the target, interpret references, write scene direction, or
claim creative adequacy. A Founder correction routes to the smallest owner:
00A for song truth, PRE-00 for an explicitly reopened target, and Front Planning
for message, member/visual/reference assignment, or the section spine.

## Audio Motion Director Map

After selected-audio analysis, create the mandatory
backbeat/frame-split bridge for any video/MV-bound song:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/audio-motion-director-map-vN.yaml
```

Use `schemas/audio-motion-director-map.schema.json` and validate it with:

```text
ruby scripts/validate_audio_motion_director_map.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/audio-motion-director-map-vN.yaml
```

This map is not cleanup after 02A. It is an audio-evidence bridge: it tells 00A
and Front Planning which audio/vocal cue, backing drum/percussion hit, bass
hit/drop, high-transient grid, vocal hold, silence, motif return, or
texture-density change creates timing pressure. It leaves the screen answer
open.

Required contents:

- source selected-audio analysis
- stable tempo, perceived pulse, meter, duration, and uncertainty
- precision marker sources when available: beat-grid TSV, onset-candidate TSV,
  pitch-contour proxy TSV, repeated motif candidate TSV/JSON, and their
  evidence-only rule
- stable audio signals and their source evidence
- exact section ids, order, and timing copied from selected-audio analysis
- section pulse, energy density, accents, stops/resets, vocal/lyric triggers,
  motif returns, and audible state-change pressure
- screen-readability questions and editability evidence
- explicit deferral of temporal camera motion to 03V after passed pixels

Do not write a generic BPM sheet, but also do not import the Founder reference
map or scene grammar into this audio layer. Reference interpretation belongs to
Front Planning and 01. Body blocking, scene action, choreography, camera rhythm,
prompt overlay, styling, spatial design, Core-Cut/Branch-Cut cardinality, and
final edit timing
are forbidden here.

Gate:

- before `00A`, Front Planning, `01`, or `02A`, a video/MV-bound selected-audio
  run must have a valid
  `audio-motion-director-map-vN.yaml`
- `source_selected_audio_analysis` must point to the latest selected-audio
  analysis with an exact SHA-256
- section ids, order, and timing must match selected-audio analysis exactly
- missing audio-motion map after selected-audio analysis blocks the graph-engineering route
  state checker until the map is created or the run is explicitly marked as
  non-video / non-MV work
