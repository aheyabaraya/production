# Suno Prompt Authoring Detail

Read this file before creating, revising, or auditing a saved run-owned Suno
prompt packet. Keep live chat-only lyric/style drafting lightweight; this detail
applies when a packet is being written to the run or used as the founder manual
Suno handoff.

## Table Of Contents

- Reference fit and source lineage
- Whole-song composition gate
- Reference audio, motif, and vocal evidence
- Fresh source-audio musical analysis protocol
- Rapid PRE-00S Style probe and candidate diagnostic
- Song craft lock and candidate audition
- Known-good prompt specificity gate
- Prompt standard
- Detailed checks

## Reference Fit And Source Lineage

If the founder provides reference songs, timestamps, or complaints that the
current Suno direction feels wrong, write or update a fit summary before copy
boxes. The fit summary should separate:

- tempo / lyric-density fit: numeric BPM or defensible BPM feel with source or
  estimate status, duration/runtime family, available lyric/transcript status,
  section-level phrase-hit density, repeated hook density, short-vs-long line
  pattern, and the target runtime / phrase-count / line-length instruction for
  the new song
- meaning-delivery fit: what the reference song makes the listener understand or
  feel, where that meaning becomes clear, which lyric/repetition/silence/section
  turn carries it, how it should inform the current run's original lyric/message
  target, and what must not be copied
- arrangement / instrumentation fit: how drums/percussion, bass/low end,
  melodic or texture instruments, harmony bed, FX/sound design, silence, and
  section-layer changes create body timing, hook memory, contrast, release, or
  scene pressure. Record the function, not just the instrument name.
- melody / topline fit: contour, hook motif behavior, phrase length and spacing,
  landing/release points, section contrast, vocal events, and how the melody
  helps meaning delivery. This is functional analysis, not note-by-note
  transcription.
- wanted functions: intro impact, rap placement, verse pocket, pre-chorus lift,
  chorus mechanic, rhythm/tempo feel, vocal color, and song feel/temperature
- lyric/section structure: when a reference song drives the prompt, inspect its
  labeled lyric structure or line-distribution map before copy boxes so the
  prompt can preserve functional roles such as rap, vocal turn, pre-chorus,
  chorus, post-chorus, interlude, bridge, and outro; reference words, titles,
  topline notes, and artist names may be recorded in internal fit notes, but
  copy-ready Suno boxes should translate them into sound, structure, vocal, or
  meaning functions by default. Include explicit artist names, song titles, or
  source hook labels in copy-ready boxes only when the founder explicitly asks
  for that test and the current Suno surface accepts them.
- rejected traits: dated chorus, band-forward sound, club-only drop, or any
  founder-specific dislikes
- unit fit: which active unit should own the sound, and why FULL_CODE is or is
  not justified

Before Suno text fields, also close source/reference lineage using existing artifacts
instead of inventing a parallel prompt-only model. The packet should be able to
point backward to:

- `reference-song-fit.founder_references[].ref_id` for founder song or media
  references
- `reference-song-fit.function_breakdown[].function_id` for transferable sound,
  lyric-delivery, structure, or reference functions
- `reference-song-fit.arrangement_instrumentation_fit` for transferable
  instrument, production-layer, silence/drop, and section-arrangement functions
- `reference-song-fit.melody_topline_fit` for transferable melody, topline,
  hook, phrase-spacing, landing, and vocal-event functions
- reference-audio sidecars such as beat grids, onset candidates, pitch-contour
  proxies, and repeated motif candidates when local audio is available
- `reference-song-fit.meaning_delivery_fit.current_lyric_message_target` and
  `prompt_handoff.lyrics_seed_policy` for the prompt's message/lyric target
- `reference-song-fit.source_links[]` for run-owned visual bundles, contact
  sheets, local analysis packs, or external source URLs
- `reference-song-fit.rejected_traits[]`, `meaning_delivery_fit.mismatch_risks`,
  and legacy note fields such as `reference_mismatch_note` for selected-source surfaces,
  mismatch notes, or non-selected-source drift

Do not create new generic fields such as `intent_locks`, `source_anchors`, or
`reference_functions_v2` inside the Suno packet when those existing IDs and
paths can be cited. If the source evidence does not fit the reference-song fit
schema, create a run-owned `research/*-intake-vN.md` or bundle file and add it
to `source_links[]` with a short function note. Downstream artifacts should then
carry the normal refs: `source_refs.reference_song_fit`,
`source_refs.suno_prompt_packet`, selected-audio `reference_fit_delta`, and
lyrics-bridge `reference_meaning_alignment`.

When the Founder selects the Loom music reference-function map, cite each
selected group entry independently in the reference fit. The map is a private
per-reference research surface: it must not be averaged into a single Loom
sound profile, and none of its prose is a copy-ready Suno Style, Lyrics, or
Negative box. A current song still requires its own audio, structure, message,
and target-transfer evidence.

This fit summary is pre-generation reference analysis. It must stay in
`research/reference-song-fit-vN.*` and must not be saved as
`selected-audio-analysis-vN.*`. Selected-audio analysis starts only after the
founder returns an actual Suno/manual candidate take.

## Reference Audio, Motif, And Vocal Evidence

When reference media is captured locally, keep audio with video when possible.
Video/contact sheets support screen grammar; audio supports song-making
evidence. Use `scripts/idol-video-python scripts/idol_audio_precision_markers.py`
or an existing extractor from `scripts/README.md` to create evidence sidecars
when useful.

Reference-audio sidecars may support:

- beat grid and onset-density evidence
- energy-window evidence
- pitch-contour proxy and broad vocal-register/timbre evidence
- repeated motif candidates: melodic cell, chant, call-response, instrumental
  riff, rhythmic loop, lyric phrase, phonetic hook, or preview hook
- arrangement and vocal-event listening targets

Reference-audio sidecars must not support:

- current-run cut-pressure scores
- current-run MV section video functions
- final prompt wording without Codex/founder listening
- automatic instrument, melody, hook, or meaning decisions

Translate repeated motifs into prompt-ready function, not copied wording. A good
Suno transfer note says how the repetition behaves: where it first appears, how
often it returns, whether it rises, shortens, answers, stacks, or quiets, and
what the new original lyric/hook should do with that behavior.

Vocal evidence should separate measurement from judgment. A pitch-contour proxy
can suggest register movement, but final language such as airy high lead, lower
chest phrase, bright group answer, clipped rap-adjacent delivery, or soft
attack must come from listening and the current run's unit fit.

## Fresh Source-Audio Musical Analysis Protocol

Use this protocol whenever a Founder asks to rebuild a song direction from a
WAV or from a local audio stream. It is a pre-generation reference analysis,
not selected-audio analysis and not a substitute for hearing the eventual
Suno take.

### Source and method lock

- Begin with the exact registered source media. If it is a container or video,
  derive a PCM WAV without changing pitch or timing and record the source path,
  source SHA-256, derived WAV path, derived WAV SHA-256, duration, sample rate,
  channel count, and extraction method.
- Keep fresh measurements in a run-owned bundle. Do not cite an older fit note,
  packet, or chat conclusion as fresh musical evidence. Older material may be
  listed as superseded history only.
- Record the tool/version and analysis window or hop settings for numerical
  sidecars. Script output is evidence; it cannot name an instrument, decide a
  melody, infer a hook, or write prompt language.

### Required musical axes

The fit summary must contain a measured / listening / unknown split for every
axis below. A missing axis is a hold, not an invitation to fill it with a genre
stereotype.

1. **Rhythm, meter, and pocket** — estimated BPM with half/double-time
   alternatives when plausible, beat interval and stability, onset density,
   meter and phase status, subdivision, straight/swing feel, kick/snare/hat or
   transient roles, syncopation, and section-level groove changes. If the
   master does not make meter phase or a named drum role audibly certain, mark
   it unresolved.
2. **Time and form** — actual opening, first layer entry, verse/lift, pre-hook,
   hook/release, post-hook, reset/drop, bridge or late contrast, final return,
   tail, and silence/hold boundaries. Use change-point output as a locator only;
   section function comes from whole-track listening and must be labelled
   provisional when a boundary is approximate.
3. **Spectrum and tone** — band shares or levels for sub, kick/bass, low-mid,
   vocal body, presence, transient/hat, and air; spectral centroid, rolloff,
   bandwidth, contrast, flatness/brightness, spectral tilt, and when each band
   enters or thins. Translate the result into audible low/mid/high behavior,
   not a list of numbers alone.
4. **Dynamics, space, and mix** — RMS/peak/crest, LUFS and true peak when
   available, loudness range or level spread, harmonic/percussive balance,
   stereo correlation/side-to-mid width, mono-risk clues, dry/wet distance,
   reverb tail, saturation, pumping or sidechain, and section-level density.
   State `not_observed` rather than asserting a production technique that the
   source does not prove.
5. **Tonal and harmonic behavior** — key/chroma candidates and confidence,
   mode, audible chord or bass-root motion, harmonic rhythm, suspended/tension
   color, and release points. Numerical key or chord labels are candidates
   until manually checked; a full mix may leave exact chords unknown.
6. **Melody, topline, and prosody** — contour by section, interval direction,
   tessitura, phrase length, syllabic density, pickups, held vowels, landing
   tones, motif size, recurrence, call/response, and how the topline carries
   meaning. Note-level transcription requires an isolated or manually verified
   source; pitch-tracking on the master is only a proxy.
7. **Vocal behavior and range limits** — lead register placement, chest/mix/
   head emphasis as heard, attack, breath, rasp, rap/sing or sing-talk, doubles,
   octave/harmony/group layers, ad-libs, call/response, and where the vocal
   drops or lifts. Set `vocal_range_status: unresolved_from_mix` unless an
   isolated vocal or manual note check supports an actual range; never convert
   pYIN, piptrack, or harmonic-mix MIDI percentiles into singer range.
8. **Arrangement and instrument function** — the functional role and entry/
   exit of kick, bass, percussion, synth, whistle or other hook timbre, keys,
   guitar, pads, FX, vocal chops, silence, and harmonic bed. Instrument names
   are human/assigned-model listening judgments; the extractor must not author
   them. Explain which layer creates motion, hook memory, contrast, pressure, or
   release.
9. **Lyric and meaning delivery** — lyric/transcript availability, phrase-hit
   density, hook repetition, consonant/vowel behavior, section where meaning
   turns, and what the listener understands without exposition. This is a
   reference-function analysis; it must not copy source lyrics or topline.

### Required handoff bundle

Before Style is marked ready, the run must contain or link to:

- the source/derived-audio manifest and hashes;
- measurement JSON/TSV sidecars for rhythm, spectrum, dynamics, tonal proxies,
  pitch proxy, windows, and transition candidates;
- a whole-track human/assigned-model analysis with a provisional section map;
- a per-section musical read covering layer state, vocal event, density, and
  transition function;
- an uncertainty register naming unresolved axes, why they are unresolved, and
  the exact follow-up needed;
- a reference-to-target transfer table stating what is retained, transformed,
  or rejected; and
- external web research links, when used, clearly labelled as context rather
  than WAV evidence.

The minimum fresh gate is therefore more than BPM, onsets, energy, or a pitch
proxy. If the source is a mixed master and the requested vocal stem or exact
chords are unavailable, the gate can still proceed as a bounded style study,
but only with those limits visible and with no false precision.

## Rapid PRE-00S Style Probe And Candidate Diagnostic

Use this lane when the Founder is trying to make the sound converge quickly
through real Suno takes before committing to a full prompt packet. The lane
shortens the feedback loop, not the evidence standard: source-audio analysis,
reference fit, Founder review, and the selected-audio boundary remain intact.

### State and ownership

Record the working state explicitly:

```text
chat_style_probe
  -> manual_candidate_returned
  -> candidate_diagnostic_only
  -> style_repair_iteration
  -> style_converged_pending_packet
  -> founder_manual_test_packet
  -> selected_audio
```

`chat_style_probe` is copy-ready Style text that has not been saved as a full
packet. `manual_candidate_returned` means the Founder has supplied an actual
Suno take or a usable take identifier. `candidate_diagnostic_only` is an
evidence state for deciding what to repair; it is not selected-audio analysis,
not a scorecard, and not a production lock. `style_converged_pending_packet`
means the Founder accepts the Style direction, while Lyrics, Negative, full
craft, and packet checks may still be open.

Keep the Founder as the generation owner. Codex may prepare copy, inspect
returned audio, compare it to the registered references, and recommend a
repair, but must not invoke paid Suno generation or silently select a take.

### Minimal pre-generation floor

Before the first Style probe:

- complete the Fresh Source-Audio Musical Analysis Protocol when local WAV or
  container audio is supplied;
- close the reference-song fit enough to name the target runtime, speed/body
  feel, section arc, vocal delivery, hook mechanic, arrangement functions, and
  rejected drift;
- preserve the distinction between measured facts, listening judgments,
  inference, and unknowns; and
- write a provisional Style that carries only the control axes needed for the
  current test.

Do not wait for final Lyrics or a selected take to test whether the Style is
too slow, too club-forward, too low-end-heavy, too sparse, too dense, or poorly
integrated with rap-sung delivery. Do wait for the fresh reference floor when
the Founder asks for WAV-grounded analysis. A fast probe without that floor is
only a provisional text experiment and must be labelled accordingly.

### Candidate return contract

Ask the Founder to return, when available:

- the actual audio path, upload name, or take ID;
- duration and a hash when the file is locally available;
- the exact Style/Lyrics/Negative text used, or the Style-only text used;
- the strongest 10-20 second moment and any short transcript if Suno changed
  the lyric or hook; and
- keep/change notes in the Founder's own listening language.

If the candidate is only a short preview, retain its duration and mark
whole-song form, late lift, final chorus, and ending behavior as unknown. Do
not infer a complete 2-3 minute arrangement from a one-minute excerpt.

### Candidate diagnostic frame

Compare the candidate with the same extraction method and reference bundle used
for the source analysis. At minimum, inspect:

| Diagnostic surface | What to compare | Evidence boundary |
| --- | --- | --- |
| Speed and body | BPM alternatives, beat interval, stability, onset rate, subdivision, pocket, perceived drag or rush | Measurements support the comparison; meter phase and pocket remain listening judgments when unresolved |
| Density and movement | section event density, kick/body pressure, transient activity, gap/mute behavior, build and reset | A short preview cannot close the whole-song section map |
| Spectrum and weight | sub/low-mid/vocal-body/presence/air shares, centroid or equivalent tone measures, low-end blanket, vocal masking | Band shares describe the mix; they do not name instruments by themselves |
| Dynamics and space | LUFS/peak/crest/LRA when available, width/correlation, dry/wet distance, contrast, loudness impression | Do not claim a compressor, sidechain, or reverb technique unless heard or evidenced |
| Vocal and hook | register placement, attack, rap-sung integration, phrase length, open-vowel landing, group answer, hook recall | Full-mix pitch tracking is only a register proxy; listening owns vocal behavior |
| Arrangement and fit | intro weight, first low-end entry, reference-function carryover, section lift/reset, club drift, target identity | Function and target transfer are human/assigned-model judgments |

Report each finding as `measured`, `heard`, `inferred`, or `unknown`. Do not
turn a candidate comparison into a numeric quality score before the Founder
has heard it and returned notes. The purpose is to identify the next control
move, not to manufacture an objective winner.

### Failure root to repair

Translate the diagnosis into one audible root before editing the Style. Use the
following as a routing aid, not as an automatic classifier:

| Audible failure root | Repair direction | Keep stable |
| --- | --- | --- |
| Track drags or feels sleepy | increase forward motion through body groove, subdivision, phrase-hit density, or section entry timing | reference hierarchy, message, runtime, vocal identity |
| Low end blankets the song | reduce low-end dominance and restore vocal-body, presence, or open-space contrast | target pocket and hook function |
| Style turns into generic club/4-on-floor | replace generic dance pressure with the reference's body groove, syncopation, mutes, and sung landing | selected reference functions and section arc |
| Rap-sung feels pasted on | specify phrase pocket, register, attack, breath, and the handoff into the melodic pre-hook or hook | hook message and vocal owner |
| Hook is present but not memorable | clarify motif size, open-vowel landing, repetition, response, and post-hook return | tempo/body target and lyric meaning |
| Candidate sounds too empty or too flat | add only the missing contrast, layer entry, response, or late lift identified in the fit | negative-space rule and core arrangement |
| Reference surface is being copied as a mood label | return to the function table and state the exact source-to-target transfer | current unit identity and original lyric/message |

One major variable remains the default for each repair. A coupled repair cluster
is valid only when the fields are one failure root—for example, a slow,
low-end-heavy candidate may require a coordinated change to forward motion,
low-end balance, and rap-sung pocket. Write the cluster as:

```text
failure_root:
fields_changed:
constraints_held:
evidence:
next_listen_for:
```

Do not solve an audio failure by stacking more adjectives, adding every
reference artist, or moving all rejected traits into Style. If the diagnosis
shows the reference fit itself is wrong, revise the fit summary first and then
repair the Style.

### Style-only prompt budget and convergence

During the rapid lane, the Style may be one compact positive paragraph. It
should name the primary sound, body/rhythm pocket, low-end behavior, vocal
delivery, hook mechanic, section contrast, and finish only when those are the
current test axes. Defer detailed Lyrics and Negative until the Founder asks
for a packet or the Style has converged.

If the Founder or the destination surface gives a character limit, count the
actual final Style string and keep it within that limit. Treat a request such
as “1000 characters” as a ceiling, not a target to pad. Keep a compact internal
control note for omitted decisions rather than overflowing the copy box.

Style convergence requires:

- the Founder has heard the latest candidate and accepts the direction, or
  explicitly names the remaining repair;
- the latest diagnosis is recorded as candidate-only evidence;
- the accepted Style is traceable to its reference fit and probe history; and
- no unresolved failure root that would obviously recreate the rejected output
  remains unaddressed.

Only then promote the Style into a saved founder-test packet and run the full
Whole-Song Composition Gate, Song Craft Lock, Known-Good Prompt Specificity
Gate, Lyrics, Negative, Variant Plan, and Founder Return checks.

### Promotion boundary

Keep every returned candidate and repair iteration distinguishable. A
`candidate_diagnostic_only` file or note may be cited by the packet's probe
history, but it must never be named `selected-audio-analysis`, `selected_audio`,
`00A`, or `song_lock`. Selected-audio analysis begins only after the Founder
chooses the actual take for the song and the audio-motion map is authorized.

## Whole-Song Composition Gate

- When a founder reference song drives the prompt, do not write or revise the
  Style box or Lyrics box from hook feel, first seconds, isolated chorus
  texture, or broad artist vibe alone.
- First inspect the whole-track reference structure from available local
  section maps, audio metrics, founder timestamps, or listening notes. Record
  the full structure in the fit summary before copy boxes: opening/setup,
  verse/lift, pre-hook/build, hook/release, post-hook, reset/break, final
  landing, approximate time spans, energy/onset-density notes when available,
  and which reference owns each function.
- Translate that reference structure into the current target arc before writing
  copy boxes. The target may be a full-song arc, a cutdown arc, or a short test
  arc depending on the founder's current runtime direction. The target arc must
  name the job of every section, not just the lyric theme.
- Translate the reference's meaning-delivery method into the current original
  lyric target before writing the Lyrics box. The packet must say how the new
  hook or repeated phrase will make the listener understand the message, where
  the meaning turns, and which lines should stay concise so the song does not
  overexplain.
- The Style box must reflect the target arc in compact music-production
  language, but it does not need to list every section. Put detailed section
  order in the Lyrics tags and packet notes; keep the Style box focused on the
  necessary sound, rhythm, vocal, hook, and production decisions.
- The Lyrics box section tags must inherit the same target arc. Do not mark the
  packet ready if the Lyrics box only has generic verse/pre-hook/hook labels
  while the reference fit contains a more specific composition map.

Execution discipline:

- Treat this skill as an execution checklist, not a document to skim. Do not
  claim a Suno packet is ready until the relevant required reads, reference fit,
  whole-song composition gate, copy boxes, variants, QC, and Checks section all
  pass.
- When revising an existing packet after founder criticism, first identify
  which skill rule or packet field failed, then patch the packet and any
  upstream fit/radar fields that would otherwise recreate the same mistake.
- Do not respond by only adding a new rule to this skill. A skill update may be
  useful, but the active packet must also be audited and corrected against the
  existing rules.
- If the founder says the prompt is ignoring reference songs, do a full
  reference-structure audit before editing lyrics or Style. Do not jump straight
  to surface lyric rewrites.

## Song Craft Lock And Candidate Audition

The Rapid PRE-00S Style Probe may defer this lock while Style wording is being
auditioned. It becomes mandatory before the accepted Style is promoted into a
saved founder manual-test packet. Candidate diagnostics can reveal a craft
problem, but they do not close the lock or create comparative scores.

Before a saved packet becomes a founder manual test, lock the musical craft
questions that a dense Style box alone cannot prove:

- hook prosody: which syllables carry stress, which word or phonetic shape owns
  the melodic landing, and where lyric stress could fight the intended melody
- singability and memory: vowel openness, consonant congestion, breath length,
  repeated-hook mouth feel, rhyme or near-rhyme, and semantic compression
- topline and harmony: contour across verse/pre-hook/hook, tension and release,
  register lift or drop, phrase spacing, and the final landing
- section density: how lyric density, drums/low end, texture, silence, and vocal
  layers differ across verse, lift, hook, reset, and final return
- vocal production: lead/double/group/harmony stack, response placement,
  ad-lib purpose, and which vocal events are intentionally absent

Record unknowns as test variables rather than filling them with generic craft
language. Then define the candidate audition before generation: stable message
and unit constraints, the single major variable each version changes, weighted
listen-for criteria, automatic rejection conditions, and the evidence the
founder should return. Suggested criteria are first-impact fit, hook recall,
prosody/singability, section contrast, vocal identity, reference-function fit,
meaning delivery, and MV/edit usability.

Do not invent A/B scores before audio exists. After actual takes return,
`selected-audio-analysis` owns the real `song_craft_evaluation` and comparative
scorecard; the Suno packet owns only the predeclared test and listen-for plan.

## Known-Good Prompt Specificity Gate

Use this gate when a packet is meant to become a founder manual Suno test, when
the founder asks for an Ink/PULSO-level prompt, or when a previous chat-only
prompt is identified as the best basis. The goal is to carry the selected
reference or previous prompt at the level of musical specificity that made it
controllable, including direct imitation of the chosen surface when that is the
founder/current-run direction.

A packet is sufficiently specified when all of these are true:

- Lyrics section tags state section-local vocal distance, vocal owner or layer
  behavior, rhythm/phrase density, low-end state, drum or percussion state,
  synth/texture state, transition behavior, and instrumental gap behavior where
  they serve the selected structure.
- The Style box works as a compact sound specification with opening design,
  low-end entry, rhythm pocket, hook mechanic, section contrast, vocal-event
  plan, production texture, and final mix target.
- The Negative box names the concrete failure outputs that would ruin this run:
  random ad-libs, filler vocal noises, hype shouts, flat topline, weak hook,
  spoken-only chorus, generic EDM loop, wrong intro weight, wrong vocal energy,
  or dated genre drift.
- The packet specifies the completed opening arc across the actual intro
  boundary, its sonic identity, the first vocal and low-end entries, and the
  hook seed or deliberate hold used before the first full hook.
- The hook specification names motif size, repetition behavior, landing
  word/phonetic shape, group answer, post-hook, and final-repeat variation as
  applicable to the selected structure.

For a saved founder-test packet, write the three copy boxes with this level of
coverage:

1. Lyrics box: every section tag uses executable musical descriptors, normally
   4-6 pipe fields. Cover section function, vocal tone/distance/ownership,
   rhythm or phrase-density behavior, low-end/drum/texture state, and
   transition/FX/space behavior when relevant. Do not put MV camera, prop, or
   choreography instructions in the tag.
2. Style box: use one dense positive-direction paragraph. It may be longer than
   a simple mood prompt when full-song control requires it, but every clause
   must do production work. Include the first sound, whether bass is held back
   or enters early, groove or body-pulse family, drum/percussion character,
   bass/low-end behavior, melodic or texture instrument family, hook motif
   behavior, section lift or reset, vocal register/layer behavior, instrumental
   gaps or mutes, final chorus lift, runtime family, and polished mix target
   only when those are intentional decisions from the reference fit or founder
   direction. When those instrument or melody-inst details are helpful but may
   over-steer Suno, keep the base Style usable without them and place 1-3 core
   anchors in an optional Style add-on.
3. Negative box: make it a failure-output filter, not a second style prompt.
   Include founder-specific misses from earlier generations, reference-fit
   mismatch risks, and non-selected-source drift. Do not use the Negative box to
   block direct following of the selected reference surface; use it to prevent
   musical failure issues such as random ad-libs, vocal chops as fillers,
   background shouts, under-sung chorus, monotone rap, weak breathy lead, flat
   one-step chorus, thin club loop, rock-band chorus, bright tropical drift, or
   intro low-end behavior that contradicts the intended first impact.

Before marking the packet ready, confirm these control axes are either specified
or intentionally left open:

- actual intro boundary and ordinarily 8-12 second opening-arc completion
- sonic identity developed across the opening arc
- hook seed or deliberate hold before the first full hook
- first sung or spoken vocal hook behavior
- bass and low-end entry timing
- tempo or groove feel and body-pulse behavior
- drum/percussion family and snap/space
- melodic, synth, harmony-bed, or texture instrument family
- pre-chorus or pre-hook lift behavior
- main hook motif size, repetition, and landing behavior
- recognizable middle return and its density, ownership, scale, or release change
- post-hook connector or instrumental fill behavior
- rap, reset, bridge, or late vocal-turn placement
- lead vocal register, texture, attack, and group/double/harmony layering
- silence, hard mute, instrumental-only gap, riser, or transition FX behavior
- final chorus/outro variation and runtime/mix finish
- failure-output terms that directly answer prior bad generations or founder
  dislikes

If the best prompt currently exists only in chat or session history, recover the
exact Style, Lyrics, and Negative copy boxes into the run's
`research/suno-prompt-packet-vN.md` or cite the recovered source inside a
run-owned packet before downstream selected-audio analysis or 00A treats it as
lineage. A chat-only prompt can guide
live drafting, but it is not durable production evidence once it becomes the
chosen manual-test basis.

## Prompt Standard

Follow the local Bible's Suno standard:

- The founder-facing runnable surface should be simple and explicitly named:
  `Suno Prompt: Style`, `Suno Prompt: Lyrics`, and `Suno Prompt: Negative`. If
  core instrument or melody-inst anchors are needed, add a separate
  `Optional Style Add-On` directly after the base Style. The add-on should be
  pasteable after the base Style or omitted completely; Lyrics and Negative must
  not depend on it.
- Custom Mode is mandatory.
- In the Rapid PRE-00S Style Probe, Style may be tested before Lyrics and
  Negative are written. Once a Style converges, recover the accepted text and
  probe history into the full packet; do not treat a Style-only take as a
  complete prompt packet.
- Style box front-loads the most important 20-30 words.
- Style box should read like a compact music production spec, not a mood note:
  primary genre or concrete sound function, one optional subgenre or groove
  when useful, energy feel, rhythm/movement pocket, lead texture only when it is
  intentional, vocal tone/register/delivery, hook or chorus behavior, and
  production finish.
- Style box must be positive-direction only. Put rejected sounds, vocal traits,
  beat patterns, filler warnings, and "no/avoid/without/not" language in the
  Negative box, not in Style. Music terms that contain a negative-looking prefix
  should also be rewritten when a clear positive equivalent exists.
- For copy-ready Suno Style boxes, prefer energy and body-function language over
  numeric BPM. Use exact BPM only when the founder locks it, the current
  reference-song fit intentionally requires it, or selected-audio analysis
  confirms it. Internal trend or choreo analysis can record BPM separately, but
  it should not be pasted into Suno by default.
- Do not guess exact BPM, kick, drum, bass, or lead-instrument design just
  because a prompt needs rhythm information. Name those parts only when the
  reference fit, founder note, or selected audio makes them intentional. If
  low-end-led or kick-led wording is producing dated or cheap EDM results,
  describe the replacement behavior instead: spacious low end,
  body-readable pocket, restrained impact, dry snap, or clean negative space.
- When founder references or local reference audio drive the prompt, make an
  explicit instrumentation and vocal-event decision before writing copy boxes:
  tempo or groove feel; low-end foundation; drum/percussion family; melodic or
  texture instruments; vocal delivery and group behavior; banned vocal events or
  unwanted instruments; and the source basis for each decision. A decision may
  be `intentionally omitted` when it is not musically needed. Only paste the
  musically necessary decisions into the base Style. If the decision is useful
  but should be tested independently, place it in `Optional Style Add-On` with a
  paste/omit policy. Put unwanted sounds in the Negative / Exclude box.
- When founder references have usable audio, also make an explicit melody /
  topline decision before copy boxes: contour, hook motif behavior, phrase
  length, landing/release point, section contrast, vocal event, and whether the
  current prompt should follow the function, follow the selected surface
  directly, transform it into a different current-song route, or leave it open for Suno. Do not ask a script to decide this; feature extracts only supply
  evidence such as energy, onset, band, chroma, or pitch-contour proxy.
- Keep genre stacking controlled. Genre labels are optional, not mandatory. Use
  one primary genre and at most one supporting genre/groove only when those
  labels improve Suno control. If a broad genre tag causes misreads, or if the
  prompt needs more influence, translate it into instruments, rhythm, vocal
  behavior, texture, or section function instead of adding more genre tags.
- Vocal direction should be concrete enough for Suno to render: register,
  texture, attack, delivery, group/layer behavior, and rap/sing function. Prefer
  musical descriptions such as airy alto, bright pop lead, low chest-register
  rap, soft attack, stacked group chorus, or call-response ad-libs over generic
  gender-only labels.
- Lyrics box uses bracketed meta-tag lines for every section:

```text
[Section | core | vocal direction | performance | production | effects]
```

- Use 4-6 pipe descriptors per section.
- For Suno lyrics, keep section tags dry and executable: section/time when
  useful, musical function, vocal behavior, and production behavior. Do not put
  MV/camera direction, body choreography, prop actions, audience-facing mood
  analysis, or vague "feeling" prose inside the Lyrics box tags. Those belong in
  01/02 planning, not in a Suno lyrics packet.
- Keep lyrics concise enough for coherence. For a deliberately short test seed,
  prefer compact lyric fragments and clear section duties over long complete
  poetry. For a full-song test, keep the lines songlike and repeatable rather
  than stretching the message into explanation.
- Negative / avoid box should behave like a focused Exclude list. Name only the
  sounds, instruments, vocal traits, eras, or failure modes that would damage
  this run. Do not overload it with every possible dislike.
- Variant Plan should change one major variable at a time: groove, energy
  pocket, vocal delivery, hook density, chorus/drop behavior, or production
  texture. Keep the message, unit fit, and selected-reference-following
  constraints stable across variants.
- If Suno sliders or advanced controls are used, record them as optional manual
  notes. Treat Weirdness, Style Influence, and similar controls as direction
  tests, not quality upgrades; change one control at a time and write what the
  founder should listen for.
- Assume Suno has no project context. Copy boxes must use normal musical
  language and singable lyrics, not internal graph-engineering terms, unit codes, route
  labels, or planning shorthand.
- Treat external reference names as usable prompt anchors when the founder or
  current run selects them as the standard. Copy-ready Suno boxes may name
  artist names, song titles, and source hook labels directly; pair them with the
  musical surface to follow, such as tempo feel, drum behavior, bass pressure,
  vocal pocket, hook shape, section contrast, or production texture.
- Do not start from broad style adjectives when the founder has provided songs.
  Use the reference-song fit directly: carry over function, structure, mood,
  energy, section contrast, meaning-delivery method, and reference feel before
  making the Style box. If the fit is unclear, stop with a fit question instead
  of writing another speculative prompt.
- When founder references set the song's speed or runtime, use BPM and lyric
  density as internal calibration before writing the Lyrics box. At similar BPM,
  line count and phrase-hit density control perceived speed: short repeated
  fragments increase body/edit pressure, while longer lines stretch the section.
  Record the target runtime range, section lengths, and phrase-hit count in the
  packet. Do not paste numeric BPM into the Style box unless the founder locked
  it or the fit says the exact number is part of the function.
- Lyrics are hook probes. The prompt may include a candidate hook so Suno has
  something to sing, but that hook is not final. Expect Suno to change wording,
  phrasing, contour, and emphasis; after the founder returns a take, fit the
  hook to the actual audio.
- Founder runs Suno manually and returns candidate take notes.
- Prompt iteration does not imply production-state mutation. Do not keep
  changing 00A, source links, active style pointers, or song-lock fields
  every time a candidate prompt changes.

## Packet Output Template

Saved run-owned packets should use this shape unless the founder explicitly asks
for a shorter manual-test packet:

```markdown
# CONTENT_ID Suno Prompt Packet vN

Status: founder_manual_suno_test

## Reference Song Fit
- founder references:
- tempo / lyric-density fit:
- arrangement / instrumentation fit:
- melody / topline fit:
- repetition / motif fit:
- vocal pitch / color evidence:
- meaning-delivery fit:
- wanted functions:
- source / reference lineage:
- whole-song composition read:
- target full-song / cutdown / short-test arc:
- rejected traits:
- recommended unit:
- prompt risk:

## Rapid PRE-00S Style Probe History (if used)
- state sequence:
- source/reference bundle:
- candidate takes and provenance:
- candidate-only diagnoses:
- failure roots and repair clusters:
- accepted Style and Founder acceptance note:

## Whole-Song Composition Translation
- reference composition read:
- target full-song / cutdown / short-test arc:
- section timing and function:

## Song Craft Lock
- hook prosody / melodic landing:
- singability / phonetic memory / rhyme compression:
- topline contour / harmonic tension-release:
- section-density contrast:
- vocal stack / response / ad-lib plan:
- intentionally open test variables:

## Candidate Audition Plan
- stable constraints:
- V1 major variable:
- V2 major variable:
- weighted listen-for criteria:
- automatic reject conditions:
- founder return evidence:

## Prompt Specificity Gate
- actual intro boundary / ordinarily 8-12 second opening-arc completion:
- sonic identity developed across the opening arc:
- hook seed or deliberate hold:
- low-end entry:
- groove / drums / texture instruments:
- hook motif and repetition:
- recognizable middle return and development:
- vocal roles / rap reset / harmony stack:
- section lift, gap, mute, or transition:
- final lift / runtime / mix finish:
- failure-output guards:

## Suno Prompt: Style
...

## Optional Style Add-On: Core Instrument / Melody Inst
- mode:
- paste policy:
- add-on text:

## Suno Prompt: Lyrics
...

## Suno Prompt: Negative
...

## Variant Plan
- V1:
- V2:
- V3:

## Optional Suno Settings Notes
- sliders or advanced controls:
- one-variable test:
- listen-for:

## Hook Discovery Notes
- hook intent:
- candidate hook lines:
- what to fit after audio:

## Listening QC
- completed opening arc across the actual intro boundary:
- sonic identity developed across the opening arc:
- addictive pre-hook:
- main release:
- recognizable middle return:
- body phrase:
- reference-use check:

## Founder Return Needed
- audio file or link
- selected take ID/name
- best 10-20 seconds
- keep/change notes
```

Default prompt inputs are the selected PRE-00 route/message, active
member/unit/voice assets, active trend-pulse research, and current-run source
references. Song prompts may use founder-named, current-run, selected PRE-00,
or active research references in internal notes and copy-ready Suno boxes. When
a direct reference-name test is the clearest route, use the artist/song/source
label and the exact musical, lyric, structural, or vocal surface to follow.

If a generated direction fails because the chorus sounds dated, the track feels
like a rock band, or the beat becomes generic club EDM, mark it as a song-fit
failure and revisit the fit summary instead of only adding more Negative terms.
Do not lock exact hook wording before audio selection unless the founder
explicitly locks it.

## Detailed Checks

- The output has real `Suno Prompt: Style`, `Suno Prompt: Lyrics`, and
  `Suno Prompt: Negative` sections, not only notes.
- The packet includes a reference-song fit summary when founder song references
  are driving the sound.
- The packet's `Source / Reference Lineage` or equivalent notes cite existing
  upstream IDs and paths: founder reference ids, function ids, source links,
  message/lyric target, and avoid/misread guards. Do not invent a separate
  source model just for the prompt.
- The reference-song fit summary includes BPM/BPM feel, duration/runtime family,
  lyric or transcript status, line/phrase-hit density, repeated-hook density,
  meaning-delivery fit, and target lyric-length/runtime instructions.
- A fresh WAV-driven fit contains the exact source/derived hashes, measurement
  settings, whole-track and per-section musical reads, measured/listening/
  unknown labels, and an uncertainty register.
- Fresh rhythm coverage includes BPM alternatives, beat interval/stability,
  onset/subdivision, meter/phase status, transient roles, syncopation, and
  pocket changes.
- Fresh spectrum/mix coverage includes low/mid/high bands, centroid/rolloff or
  equivalent tone measures, RMS/peak/crest, LUFS/true peak when available,
  harmonic/percussive balance, and stereo/space observations.
- Fresh tonal/topline/vocal coverage separates key/chord candidates, contour
  and phrase behavior, vocal placement/events, and exact vocal-range status;
  full-mix pYIN/piptrack output is never a vocal-range claim.
- Fresh arrangement coverage records section-layer entries/exits and the
  audible function of each named instrument or texture, with script output
  remaining evidence only.
- Fresh external web research is labelled contextual and never substitutes for
  the local source WAV.
- For `reference-song-fit` schema `1.2`, the summary includes
  arrangement/instrumentation fit and melody/topline fit before copy boxes.
- Arrangement/instrumentation fit names the function of drums/percussion,
  bass/low end, melodic or texture instruments, harmony bed, FX/sound design,
  silence/drop, and section-layer changes instead of only listing instruments.
- Melody/topline fit names contour, hook motif behavior, phrase length and
  spacing, landing/release points, section contrast, vocal events, and how the
  melody carries meaning.
- Any local feature-extraction script output is cited only as evidence. It does
  not decide instruments, melody function, target transfer, or prompt wording.
- When reference songs drive the sound, the packet includes a
  `Whole-Song Composition Translation` or equivalent section before copy boxes.
- The whole-song composition section records the reference opening/setup,
  verse/lift, pre-hook/build, hook/release, post-hook, reset/break, and final
  landing functions, with approximate time spans or section ids when available.
- The packet translates the reference structure into the current target arc
  with approximate target times or section guides and a clear job for each
  section. The arc must match the founder's current runtime direction instead
  of forcing every prompt into a short-track shape.
- The packet translates reference meaning delivery into a lyric/message plan:
  listener receive, hook clarity, section where the meaning turns, lines that
  must stay concise, and the selected-reference-following note.
- Saved founder-test packets include a filled `Song Craft Lock` or equivalent
  that covers hook prosody, singability/phonetic memory, topline and harmonic
  release, section-density contrast, and vocal-stack/ad-lib intent without
  pretending an unheard melody or take is already verified.
- Saved founder-test packets include a `Candidate Audition Plan` or equivalent
  with stable constraints, one major variable per version, listen-for criteria,
  reject conditions, and founder return evidence. Comparative scores appear
  only after actual audio candidates exist.
- When the Rapid PRE-00S Style Probe is used, the packet or linked research note
  records its state sequence and keeps each returned candidate distinguishable
  by path/name or take ID, duration, prompt version, and hash when available.
- Rapid candidate diagnosis compares the returned audio with the same reference
  evidence and extraction method, and separates measured, heard, inferred, and
  unknown findings. A short candidate cannot close missing whole-song form.
- Rapid diagnosis identifies one failure root before editing Style. One major
  variable is changed by default; a coupled repair cluster names its root,
  fields changed, stable constraints, evidence, and next listen-for.
- Candidate diagnostics remain `candidate_diagnostic_only`; they are never
  labelled selected-audio analysis, 00A, song lock, or production state.
- The rapid Style probe records Founder acceptance before promotion to a full
  packet, and the accepted Style remains traceable to the reference fit and
  probe history.
- If a Style character budget is given, the saved copy is counted and stays
  within the ceiling without filler or generic padding.
- The Style box inherits that target arc compactly through necessary sound and
  production decisions, not by listing every section or relying only on genre,
  artist vibe, hook texture, or first seconds.
- The Lyrics box section tags inherit the same target arc and are not generic
  when the fit summary contains a specific composition map.
- The known-good prompt specificity gate is closed before the packet is marked
  ready: first sound, first vocal hook, low-end entry, groove, drum/percussion,
  texture instruments, hook motif, section lift/reset, vocal layering,
  instrumental gaps, final lift, runtime/mix finish, and failure-output guards
  are either specified or intentionally left open with a reason.
- Saved packets include a `Prompt Specificity Gate` or equivalent filled
  section before the copy boxes so the control axes are visible to the founder
  and the next operator, not only implied by the copy text.
- Every lyrics section has a bracketed meta-tag line.
- The style box is short, front-loaded, and includes primary genre or concrete
  sound function, optional supporting groove when useful, energy feel,
  rhythm/movement pocket, intentional texture, vocal delivery, hook behavior,
  and production finish.
- The Style box is positive-direction only. It does not contain `no`, `avoid`,
  `without`, `not`, `negative`, `reject`, or similar rejected-trait language.
- The style box does not stack vague genre tags when concrete instruments,
  rhythm, vocal behavior, or section function would be clearer.
- The style box does not assert exact BPM, kick, drum, bass, or instrument
  choices unless they are intentional inputs, not guesses.
- Optional instrument or melody-inst anchors are limited to the few sounds that
  define the song. They should not become a full arrangement list, and the
  packet must say whether to paste or omit them for the next run.
- When founder references or local reference audio drive the prompt, the packet
  records an instrumentation / vocal-event decision lock before copy boxes:
  tempo or groove feel, low-end foundation, drum/percussion family, melodic or
  texture instruments, vocal delivery and group behavior, banned vocal events or
  unwanted instruments, and source basis. Decisions may be intentionally omitted
  when not musically needed.
- Copy-ready Suno boxes avoid artist names, song titles, and source hook labels
  by default, translating references into sound, structure, vocal, or lyric
  functions instead.
- Lyrics box section tags stay musical and executable. They do not contain
  MV/camera direction, body choreography, prop actions, or audience-facing mood
  analysis. This restriction applies to bracketed section tags, not to lyric
  lines. Lyrics may be abstract, metaphorical, ambiguous, fragmented, surreal,
  or image-led when those choices are intentional, singable, and coherent with
  the song's voice and progression.
- The Lyrics box length follows the reference density target instead of an
  arbitrary default duration. If the target is late-1-minute or near-2-minute,
  the packet includes enough lines and repeated phrase hits to support that
  runtime.
- Vocal direction is more specific than gender alone.
- The Negative box is a focused avoid/exclude list, not a cluttered second
  prompt.
- Variants change one major musical variable at a time.
- The packet records that founder manual run is required.
- Hook wording remains provisional unless the founder locked it after hearing
  audio.
- The packet tells the founder to return the actual generated hook wording or a
  short transcript when Suno changes the lyrics.
- The prompt packet path is referenced from the run intake note only after the
  Founder selects it as the current manual test. Early chat candidates do not
  need run-file references.
- When a run-owned packet is saved as the current founder manual test, refresh
  the run's compact intake or current handoff note if present. It should point
  to the latest reference-song fit, the current Suno packet, source/reference
  bundles, and the exact Founder return needed. Do not advance 00A or active
  production state from this packet alone.
