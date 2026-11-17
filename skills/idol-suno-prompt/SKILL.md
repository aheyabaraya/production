---
name: idol-suno-prompt
description: "Use inside the IDOL repository whenever creating or revising a Suno/manual audio prompt packet, rapid PRE-00S Style probe, or returned-candidate audio diagnosis from a selected PRE-00 route, reference-song fit, song-direction seed, or provisional song structure. Triggers on Suno, manual audio generation, Style prompt, WAV/reference-song analysis, candidate take diagnosis, lyrics box, custom lyrics, meta-tagged lyrics, hook tests, pre-00 song probe, Founder-provided song references, or Founder manual Suno run handoff."
---

# IDOL Suno Prompt

Use this skill when a run needs a founder-runnable Suno prompt packet. This
includes the optional PRE-00S song probe after a Founder-selected PRE-00 route
and before actual selected-audio analysis.

This skill does not run Suno, call paid audio APIs, or lock a final song.

## Live Drafting Boundary

When the founder is still trying lyrics, style wording, hook wording, or section
shape in conversation, do not create or update run files by default. Answer with
copy-ready text in chat.

Create or revise a run-owned prompt packet only when the Founder explicitly asks
to save, package, or run that candidate. Do not update
`00A-song-lock.yaml`, Front Planning, or active production fields from prompt
drafts alone. 00A is authored only after the Founder selects an actual audio
take and selected-audio analysis plus the audio-motion map pass.

## Founder-visible Song Room And Dispatch Boundary

Song prompt work belongs to one separate physical Founder-visible Song Room
under the durable Creative Development Director (CDD). The Song Room carries
PRE-00S Style probes, lyric/arrangement revisions, candidate diagnostics, the
Founder-selected take, selected-audio analysis, audio-motion evidence, and the
00A package in one reusable task. A HOLD or later 00A correction resumes that
same physical child room; it never opens a duplicate Overall conversation or a
parallel Song Room. Every Song Room return goes only to CDD for review, and only
the Overall Director promotes canonical truth.

Launch and return use the active `idol-department-dispatch.v8` Goal-first Contract. Stable
`lineage_id`/`session_id` are separate from each immutable
`attempt_id`/`attempt_number`; a correction is a new attempt under the same
lineage/session with retained prior output, explicit invalidation, and
evidence-bearing correction details. The runtime records required EOF reads,
skill revisions, input/result digests, owner, and output inventory. A multi-file
song return exposes one aggregate manifest with exact child paths and SHA-256
values. Director Dispatch and Reference Working Index surfaces are pointer-only
read models, never copied packet or transcript stores.

## Rapid PRE-00S Style Probe Lane

Use this lane when the Founder wants the fastest audible convergence and is still
deciding the song's Style, groove, vocal delivery, hook behavior, or arrangement
pressure. It is an audio-in-the-loop search lane, not a replacement for fresh
reference analysis, the full packet gates, or selected-audio review.

Keep the state explicit:

```text
chat_style_probe
  -> manual_candidate_returned
  -> candidate_diagnostic_only
  -> style_repair_iteration
  -> style_converged_pending_packet
  -> founder_manual_test_packet
  -> selected_audio
```

Run the loop as follows:

1. Establish the reference floor first. If the Founder supplied WAV or local
   audio, complete the Fresh Reference-Audio Gate and reference-to-target fit
   before writing the first Style. If no local audio exists, record the
   reference-fit evidence and the unresolved musical axes instead of guessing.
2. Draft a Style-only candidate in chat unless the Founder explicitly asks to
   save a packet. Defer full Lyrics, Negative, Song Craft Lock, and production
   state while the Style is being auditioned. The Style remains provisional.
3. The Founder runs Suno manually and returns the actual candidate audio or
   take identifier. Codex does not run paid Suno generation on the Founder's
   behalf.
4. Diagnose the returned candidate immediately against the same reference
   evidence. Separate measured values, listening judgments, inference, and
   unknowns. A short preview may diagnose speed, pocket, density, spectrum,
   dynamics, vocal placement, hook behavior, and arrangement drift, but its
   missing full-song form must remain unknown.
5. Translate the diagnosis into a failure root and a targeted Style repair.
   Change one major variable by default. A bounded coupled repair cluster is
   allowed only when several fields are one audible failure root; record the
   root, fields changed, and constraints held stable.
6. Repeat only until the Founder accepts the Style direction. A candidate in
   this loop is `candidate_diagnostic_only`, never selected audio, and never a
   basis for 00A or Front Planning.

When the Style converges, recover the accepted Style and its probe history into
the run-owned packet, then complete the whole-song composition, song-craft,
prompt-specificity, Lyrics, Negative, variant, and Founder-return gates. Only
the later Founder-selected take may enter selected-audio analysis and 00A.

If the Founder gives a character budget for the Style, treat it as a hard output
constraint for that probe: count the final copy, stay within the budget, and do
not pad it with generic adjectives. Keep Style positive-direction only; move
rejected traits to Negative once the full packet is being written. Preserve the
actual returned audio path/name, duration, hash when available, prompt version,
and Founder keep/change notes as candidate evidence rather than silently
replacing the prior probe.

## Required Reads

For the physical Song Room,
`automation/harness-skill-load-profiles.yaml` is the sole static profile-body
source. Use `song_prompt_authoring` for the ordinary prompt/candidate job and
`song_prompt_reference_fit` only when a Founder song reference or selected
sound anchor activates the reference-fit schema. The selected PRE-00 v3 handoff
and its complete `storyline_lineage` (immutable original, active full-text
version, revisions, density review, and all reference functions/exclusions),
actual named trend pulse, audio/reference inputs, and CDD return target remain
hash-bound current-run inputs. The Song Room may test song fit against this
root but may not replace it with a compact progression summary.

1. `AGENTS.md`
2. `wiki/production-system.md` sections `Active Route`,
   `Stage And Session Ownership`, `Dispatch, Context, Review, And Revision`,
   and `Founder Gates And Detail Sources`
3. `policies/harness-routing-and-sources.md` sections
   `Audience And Trend Foundation To Front Planning`, `Model Routing`, and
   `Founder Gates`
4. `wiki/pre-00-song-system.md` sections `PRE-00S Reference-Song Fit`,
   `Suno / Manual Prompt Packets`, and `Song Lock`
5. `AURORA-IDOL-PRODUCTION-BIBLE-VALIDATED.md` sections 2, 4.5, and the Suno
   Generation + Founder QC Gate
6. `source-materials/trend-pulse-records/latest.md`
7. The active biweekly trend pulse named by `latest.md`
8. `assets/voice-style-index.md`
9. `schemas/department-dispatch.schema.json` and the active CDD Founder-board
   contract when the packet is returned for review

Conditional Loom music-branding read:

- `business-marketing/brand-management/core/loom-music-reference-functions-v1.md`,
  when the Founder selects the Loom music reference set for the current
  song-direction task. Read each reference entry independently as a function
  map. This is private upstream research, not a combined Loom style brief and
  not a Suno prompt.

Conditional reads:

- `schemas/reference-song-fit.schema.json`, when founder song references drive
  the prompt.
- `scripts/README.md`, before creating or citing local audio/video analysis
  sidecars.
- The selected `research/pre-00-research-radar.yaml` or automation PRE-00 radar
  when this is a PRE-00S song probe.
- The run's `research/reference-song-fit-vN.md`, if present.
- The run's `research/founder-route-intake.yaml`, if present.
- `references/suno-prompt-authoring-detail.md` when creating, revising, or
  auditing a saved run-owned prompt packet, or when diagnosing a returned
  candidate and deciding whether a Rapid PRE-00S Style has converged.

## Output Boundary

Create or revise:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/suno-prompt-packet-vN.md
```

This file output is optional during early exploration. If the founder only asks
to "try wording", "give me the Suno style", "rewrite the chorus", or similar,
return the candidate in the response and leave the repo untouched. If a packet
is created for manual testing, mark it as a candidate and do not treat it as
selected audio. When a packet or candidate return is saved, it is an immutable
attempt in the Song Room lineage and returns only to CDD; the CDD may expose the
reviewed packet on the single Founder workbench, while the Overall Director
alone promotes it.

When this is a PRE-00S probe before selected-audio analysis, create the run folder and research
packet only after founder route selection exists or the founder explicitly
provides songs/sections as the sound anchor for a new route. Do not create a
song-production lock from the packet alone.

If the founder provides reference songs, timestamps, or criticism that the
current Suno direction feels wrong, write or update a `reference-song-fit-vN.*`
summary before Suno text fields. Keep this as pre-generation reference
analysis. Selected-audio analysis starts only after the founder returns an
actual candidate take.

## Fresh Reference-Audio Gate

When a Founder request asks for WAV-based reference analysis, do not author the
Style from an older packet, mood note, artist comparison, or a short highlight.
Start from the exact locally registered source media, derive a documented WAV
when needed, and keep the source path/hash, derived-WAV path/hash, duration,
sample rate, channels, and extraction method beside the analysis. The fresh
bundle must separate measured values, Codex/Founder listening judgments, and
unknowns. It must cover rhythm and meter, whole-song timing and transitions,
low/mid/high spectrum, dynamics and stereo, tonal/harmonic candidates,
topline/phrase behavior, vocal events and register limits, arrangement-layer
changes, and reference-to-target transfer. A full-mix pitch estimate is a
pitch proxy, never proof of a singer's vocal range.

The gate is open only when every requested axis is either evidenced or marked
unknown with a concrete reason and a next listening/measurement requirement.
Web research may explain artist positioning or production language, but it
cannot replace the source WAV analysis. A style-only candidate may be saved
before Lyrics are rewritten, but it must remain `founder_review` and must not be
treated as a complete runnable prompt packet.

When the Loom music reference-function map is in scope, do not average its
main and sub references into a single sound profile. Select and document each
reference function separately in the run's reference fit, then perform the
fresh source-audio and target-transfer analysis required below. Never paste the
map itself into a Suno Style, Lyrics, or Negative box.

## Prompt Surface

Use Custom Mode. The founder-facing runnable sections must be:

```text
Suno Prompt: Style
Suno Prompt: Lyrics
Suno Prompt: Negative
```

Optional core instrument or melody-inst language belongs in a separate
`Optional Style Add-On` unless the founder explicitly wants it baked into the
base Style. The base Style must still work without that add-on.

Saved packets must follow the detailed standard in
`references/suno-prompt-authoring-detail.md`, including reference fit, source
lineage, whole-song composition gate, song-craft lock, reference-audio evidence
use, known-good prompt specificity gate, full packet output template, and
detailed checks.

## Boundaries

- Reference songs may appear in internal fit notes and copy-ready prompt text
  when the founder/current run selects them as the standard. Pair names with the
  sound, structure, vocal, lyric, or meaning-delivery surface to follow.
- When the founder brings songs, place those songs against active unit fit before
  prompt writing. Recommend FULL_CODE only when the reference functions require
  a full-roster identity route.
- Any local feature-extraction script output is evidence only. It does not
  decide instruments, melody function, target transfer, or prompt wording.
- A fresh source-audio bundle is required before closing a Style driven by local
  WAV evidence; exact vocal range, isolated melody, chord identity, and meter
  phase remain explicitly unresolved when the source is a mixed master.
- If a generated direction fails because the chorus sounds dated, the track
  feels like a rock band, or the beat becomes generic club EDM, treat it as a
  song-fit failure and revisit the fit summary instead of only adding Negative
  terms.
- Hook wording remains provisional unless the founder locked it after hearing
  audio.
- Lyrics box section tags stay musical and executable. They must not contain
  MV/camera direction, choreography, prop actions, or audience-facing mood
  analysis. This restriction applies to bracketed section tags, not to lyric
  lines. Lyrics may be abstract, metaphorical, ambiguous, fragmented, surreal,
  or image-led when those choices are intentional, singable, and coherent with
  the song's voice and progression.
- Prompt iteration does not imply production-state mutation.
- Every packet, candidate diagnosis, and selected-song return names its CDD
  recipient and Department Dispatch v8 lineage/attempt. Worker output never
  bypasses CDD or writes the pointer-only Director Dispatch/Reference indexes.

## Checks

- Chat-only drafting left the repo untouched.
- Saved packets include real `Suno Prompt: Style`, `Suno Prompt: Lyrics`, and
  `Suno Prompt: Negative` sections.
- Founder song references have a reference-song fit summary before copy boxes.
- WAV-driven reference work includes exact source/derived hashes, whole-track
  and section-level measurements, auditory judgments, an uncertainty register,
  and a source-to-target transfer note before Style is marked ready.
- The analysis distinguishes full-mix pitch/register proxies from isolated
  vocal-range claims and never promotes the proxy into a singer's range.
- Saved packets close the whole-song composition gate and prompt specificity
  gate described in `references/suno-prompt-authoring-detail.md`.
- Saved founder-test packets close the song-craft lock: hook prosody and
  singability, topline/harmonic release, section-density contrast, vocal-stack
  plan, and explicit candidate audition criteria. Do not fabricate comparative
  scores before actual takes return.
- Every lyrics section has a bracketed meta-tag line.
- Style is positive-direction only; rejected sounds belong in Negative.
- Variants change one major musical variable at a time.
- The packet records that founder manual run is required and asks the founder to
  return the generated audio, selected take ID/name, best 10-20 seconds, and
  keep/change notes.
- When the Rapid PRE-00S Style Probe Lane is used, the run preserves the state
  transition, candidate provenance, reference-vs-candidate diagnosis, failure
  root, repair fields, stable constraints, and Founder acceptance note. A
  candidate diagnosis is never labelled selected audio.
- Rapid Style repair changes one major musical variable at a time unless a
  documented coupled repair cluster addresses one failure root. The final Style
  respects any Founder character budget and is not padded to fill it.
- The prompt packet path is referenced from the run intake note only after the
  Founder selects it as the current manual test. It enters 00A lineage only
  through an actual selected take, selected-audio analysis, and the audio-motion
  map.
- A correction or retry is a new immutable attempt in the same Song Room, not
  an overwrite; aggregate manifests and input/result digests are current, and
  CDD review precedes any Overall promotion.
