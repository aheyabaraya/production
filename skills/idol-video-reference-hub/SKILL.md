---
name: idol-video-reference-hub
description: Use inside the IDOL repository whenever a task proposes, captures, registers, migrates, deduplicates, or reuses a local `yt-dlp` video reference. Enforce preflight-first, approval-gated wrapper capture, one canonical source-hub owner, a read-first analysis registry, duration-aware contact sheets, hash-bound evidence, reusable source-owned Layer A/B scene analysis, and no separate duplicate video bytes.
---

# IDOL Video Reference Hub

Use this skill for every permitted `yt-dlp` source. It owns source evidence and
the reusable source-level scene reading; it does not choose a current project’s
reference disposition or downstream creative binding.

## Required Reads

For capture, migration, registration, or reuse,
`automation/harness-skill-load-profiles.yaml` is the sole profile-body source.
The launcher selects
`source_hub_registration.source_registration_and_reusable_analysis`,
exact-copies its skill/read bindings into the Department Dispatch, and
hash-binds the registry, profile, checkpoint, Studio Kernel, and current-run
Creative Delta. Read every selected path to EOF and do not load the full
reference catalog. The exact source candidate, permission receipt, current-run
caller, and any source manifest/analysis revision are hash-bound launch inputs,
not an inferred second read list. Missing or stale profile/source bytes are a
HOLD.

## Read / Write Contract

Read the selected source-hub manifest and current run caller before any action.
Allowed writes are mechanical source bytes, probe/hash metadata, navigation
sheets, selected-range derivatives, hub registries, and human- or assigned-
model-authored reusable Layer A/B source observation. Forbidden writes are
current-project dispositions, section assignments, downstream prompts, or
canonical MV stage artifacts. CF stage artifacts are frozen compatibility
only; do not open CF operations.

The shared hub owns one canonical source-level analysis prose per registered
source revision. Front Planning 01R/01R-C or another MV run owner consumes
that observation and authors only the current project’s exact locator,
disposition, transfer decision, and binding. The registry script checks paths,
hashes, required headings, declared coverage, and status; it never authors
creative observation. The cross-run catalog may point to this analysis but does
not authorize reuse, attachment, download, or Founder PASS.

In the ordinary post-song IDOL route, the hub supplies evidence only to the
bounded video-capable logical `worker_high` assignment whose exact provider is
pinned from the immutable run snapshot, Grok-preferred when ready, and that owns the named gap under the
durable, Founder-visible Creative Development Director (CDD). An assignment may
combine motion, ordered sequence, styling, and exact selected still evidence
around one disjoint territory. Source and worker counts adapt to decision
readiness and provider capacity; they are never discovery quotas. Image-only
World/Still and Pinterest workers do not load or use this hub. This hub owns only canonical video
media, exact locators, hashes,
navigation/selected-range evidence, and reusable source observation. The CDD
owns the Reference Working Index and governing selection; every current-run
research return goes only to CDD, and the Overall Director alone promotes
current-run creative truth.

## Department Dispatch v8 Return Boundary

When invoked by a current-run research task, launch from one
`idol-department-dispatch.v8` Goal-first Contract. It binds the Founder epoch and locks,
exact source paths/hashes, required skill/module EOF reads and application,
external permission, bounded output paths, Anti-Flat evidence, write authority,
stop conditions, dispatcher, and recipient CDD. Stable `lineage_id` and
physical `session_id` are separate from each immutable `attempt_id` and
`attempt_number`. A correction or retry is a new attempt under the same
lineage/session with retained prior evidence, explicit invalidation, and a
correction unit describing the problem, screen consequence, action, remaining
risk, affected owner, and retry route; never overwrite a prior attempt.

The runtime records skill revisions, EOF/application evidence, input/result
digests, owner, and output inventory. A multi-file source-evidence return
exposes one aggregate manifest with exact child paths and SHA-256 values; the
pointer-only Director Dispatch/Reference Working indexes point to that manifest
instead of copying rows. The hub may author source-owned analysis in its
canonical source path, but it never promotes a current-run disposition or
Founder lock. The CDD reviews the returned evidence and sends any milestone to
Overall; every current-run research worker returns only to CDD.

Keep one stable source identity across this lifecycle:

```text
Discovery Reference Pool candidate
-> selected Evidence Card with complete source-owned media-shaped read
-> exact run/section binding and decision epoch
```

Selection, not mere discovery, triggers the expensive complete semantic read.
Workers submit pointer deltas and never rewrite the index concurrently. Raw
pools remain in excluded work/cache space; downstream section contexts receive
only selected Evidence Cards and exact bindings. The Director Dispatch Index
and Reference Working Index are pointer-only read models over the source-owned
manifest and dispatch attempts; they never embed media, raw pools, transcripts,
or creative truth.

## Non-negotiable route

1. Run `scripts/idol_reference_hub.py preflight URL` first. Reuse registered
   evidence; missing registered evidence is a hold, never a redownload.
2. Do not call bare `yt-dlp`, choose an arbitrary output directory, or retain a
   run-local original. Use an approval-gated wrapper under `scripts/`.
   Public Bilibili uses `scripts/yt-dlp-bilibili.sh`; it owns preflight,
   canonical output, contact-sheet generation, and registration.
   Bilibili is the first public-video discovery/capture platform after context
   mapping and original/official verification. Public YouTube official/original
   sources are a dormant exception: use `scripts/yt-dlp-youtube-reference.sh`
   only after the Founder separately and explicitly instructs YouTube use for
   the current task. Generic research approval or a weak Bilibili result does
   not activate it. The entry requires the explicit-instruction flag and basis
   before delegating to the same fail-closed hub engine without cookies or
   account state. AMV, MAD, and fan edits also require their own exact-source
   restricted permission described below; YouTube permission alone is not it.
3. New wrappers for any other explicitly Founder-approved non-Bilibili source
   must implement this same contract before any download. Each wrapper call
   binds the selected exact official/original URL, title, platform, and task
   basis. One-off shell pipelines are forbidden; a missing registered wrapper
   is a hold. For AMV, MAD, or fan-edit media, approval must additionally name
   that exact source identity/URL, purpose, and allowed action.
4. Keep the sole canonical owner at
   `source-materials/video-sources/{platform}/by-source/SOURCE_ID/`. Runs,
   catalogs, and legacy locations hold pointers or verified hardlinks only,
   never copied media bytes.
5. Render the active reusable review material from the actual source duration.
   Metadata duration must be known and no source over 270 seconds (4 minutes
   30 seconds) may be captured; this ceiling has no heavy-source override.
   Sources at or below 60 seconds use one-second sampling in 5-second parts:
   `contact-sheets/segments-5s-1s/`, preset `one-second`, and
   `--segment-duration 5`. Longer/full-MV sources use three-second sampling in
   15-second parts: `contact-sheets/segments-15s/`, preset `three-second`, and
   `--segment-duration 15`. Both require a hash-bound manifest in `analysis/`.
   Do not create per-cell crops for hub intake. A later selected reference may
   receive its own hash-bound crop only after selection.
6. Register with `idol_reference_hub.py ingest-local`; when replacing an
   existing active cadence, pass `--replace-contact-sheets` plus its QC
   manifest. For an already registered source, use
   `idol_video_reference_segments.py --source-manifest ...` first as a dry run,
   then add `--apply`; it owns the duration-aware render and index replacement.
   New wrapper captures also pass the hash-bound info JSON, verified duration,
   raw view count when available, and duration lane. Keep those values in
   source-manifest `discovery_metadata` and its pointer-catalog projection;
   printing them during capture is not persistence. Keep source manifest,
   frame index, and pointer catalog current.
7. The registered wrapper must run
   `scripts/idol_video_reference_analysis_registry.py sync` after a new capture
   or registered-source reuse. This updates
   `source-materials/video-sources/READ-FIRST.md`. A newly downloaded source is
   deliberately shown as `미분석`; download and contact sheets never count as
   a completed creative analysis.
8. Verify with `idol_reference_hub.py verify` and
   `idol_video_reference_analysis_registry.py verify`. If the same SHA-256 exists as
   separate byte copies, make a hash-bound, reverse-reference-checked cleanup
   plan and get Founder approval before replacing the duplicate with a hardlink
   or removing it. Never delete selected, referenced, or protected media. The
   IDOL state checker must run the analysis-registry verification as a
   blocking local-source preflight; missing or stale local source evidence is
   a hold. Historical CF preset/bridge entrypoints are frozen compatibility
   only and must not open CF operations.

## Read-first analysis contract

Before a later session opens the same source video or broad contact sheets,
open `source-materials/video-sources/READ-FIRST.md`.

- If the source has `상세 분석 있음`, read that exact source-owned analysis
  first. Reopen pixels only when source bytes or selected meaning changed, the
  analysis is incomplete, an identity/safety/feasibility conflict appears, or
  the Founder explicitly asks for re-review.
- If it says `미분석` or `분석 미완료`, do not infer that the source has already
  been understood. Inspect the original video and the exact selected range,
  then author or complete the source-owned analysis.
- A complete analysis states exactly which video, one-second sheet, selected
  range, selected frame/crop, or sub-second turn sheet was inspected. It also
  gives the whole-source flow and timestamped observations of who is visible,
  where they are, what they do and in what order, body travel, posture, hand and
  foot action, expression and gaze, object/environment change, camera geometry
  and movement, composition/depth, lighting/material, edit transition, and the
  state that changes.
- Keep the source reading reusable. End with source-level transfer and exclusion
  boundaries so cast, styling, brand, fictional world, or surface art does not
  silently become a later project’s identity. Current-project use belongs only
  in that run’s disposition/binding record.

Register the finished source-owned analysis with:

```bash
scripts/idol-video-python scripts/idol_video_reference_analysis_registry.py register \
  --source-manifest SOURCE_MANIFEST \
  --analysis SOURCE_OWNED_ANALYSIS \
  --analysis-id ANALYSIS_ID \
  --authoring-stage source_first_read \
  --status complete \
  --coverage-summary 'WHOLE SOURCE OR EXACT SELECTED RANGES' \
  --input original_video=SOURCE_VIDEO \
  --input one_second_analysis_surface=ONE_SECOND_MANIFEST
```

Add further `--input` rows for selected-range, sub-second, or selected-frame
evidence actually inspected. Do not register an input merely because it exists.
See `references/video-reference-analysis-example.md` for a generic, noncanonical
analysis example.

## Navigation Surface Versus Selected Reference

The duration-aware hub sheets are reusable navigation evidence, not the final
creative reference. Their part and cell counts are not by themselves a
downstream frame-count prescription, and rendering part count never creates
events or Majors.

- At or below 60 seconds, the one-second / five-second-part surface makes the
  whole short source quickly inspectable. It does not mean every sampled cell
  becomes a reference.
- Above 60 and at or below 270 seconds, the three-second / fifteen-second-part
  surface is a broad index. The owning research stage first finds a relevant
  event range. When that range is attached as a selected reference, render the
  selected range again at a one-second interval; the three-second hub index is
  never the final attached reference surface.
- In both duration lanes, every selected video event attached to a comparison
  unit or interpretation receipt gets hash-bound one-second selected-range
  evidence. There is no fixed dense-evidence duration quota: render as many
  ordered readable parts as the named event and decision require, preserve
  every covered interval, and return a named evidence gap when the event cannot
  yet be read completely. Do not compress the event into one unreadable sheet
  or split one event merely to satisfy a file or worker ceiling.
- In both lanes, one contiguous source event remains one event even when the
  reviewer needs several timestamps to read its start, turn, impact, reaction,
  or endpoint. Longer same-event evidence may span ordered linked exact-five
  Sequence Units without duplicated boundary frames. Rendering those Units or
  readable parts does not create events or Majors. A broad whole-source sheet
  counts as zero reference units.

After the owning Front Planning 01R/01R-C substage selects an
exact event range, reuse
`scripts/idol_video_qc_sheet.py` through `scripts/idol-video-python` with
explicit `--start`/`--duration`, `--interval 1`, and `--manifest`. An explicit
`--times` list is equivalent only when it covers each declared dense window at
no more than one-second gaps. Render longer evidence as ordered parts of no
more than 10 seconds each. Use `--cell-crops-dir` only for frames that will
directly shape a visual decision. Do not create a new crop helper or
automatically crop every navigation or one-second attachment cell. The
creative owner decides event phases and selected timestamps; the script only
extracts the declared frames and hashes the resulting evidence.

The one-second selected-range sheet is the common analysis and receipt surface,
not a downstream frame quota. It does not create one reference unit or 02A child
per second. Historical CF40/CF50 per-second beat or keyframe mapping is frozen
compatibility only and is not an active MV route. Exact sub-second phase frames may be
added when a collision, expression, camera turn, object change, or edit landing
falls between one-second samples. Only those event-driven phase frames whose
pixels must govern downstream visual work receive selected frame/cell/crop
derivatives.

### IDOL Front Planning active Sequence Unit

For active `front-planning-readiness.v17` authoring, the common analysis sheet
is supplemented by at least one selectable Sequence Unit for every active
visual section. The creative owner identifies one contiguous source event; the
hub extracts **exactly five** ordered consecutive samples at exact one-second
cadence and records a hash-bound manifest plus exact path/SHA-256 per frame.

- All five timestamps differ by exactly one second and remain inside the
  same event range. Do not duplicate a frame, mix separate events, or add a
  decorative fifth frame merely to satisfy the count; return a named evidence
  HOLD when the source cannot supply a coherent unit.
- Longer events use ordered linked Sequence Units without duplicated boundary
  frames. A legacy exact-five three-second unit is pinned read-only evidence:
  readers may inspect it, but new authoring never creates, rewrites, upgrades,
  or automatically promotes it.
- The Sequence Unit is one `sequence_direct`-eligible reference unit. A Major Scene
  may bind that unit and 02A may later select the smallest useful hash-bound
  subset; these are five source-evidence frames, **not five required downstream cuts**.
- A broad hub sheet still counts as zero. Extra sub-second phase frames remain
  supplemental and do not replace or alter the five-frame floor bundle.

Use `idol_video_qc_sheet.py` with an explicit five-value `--times` list (or an
equivalent bounded extraction that yields those exact timestamps), `--manifest`,
and `--cell-crops-dir` for the five selected frame artifacts. The assigned
human/model creative owner chooses the event, cadence, and timestamps. The hub
only extracts and hashes them; it never assigns a section, chooses a governing
reference, or grants Major/direct-use authority.

The selected-reference handoff therefore has two possible evidence shapes:

1. a time-bounded sequence plus readable sheet/segment evidence, when the
   source contributes response, edit, camera, motion, or other functional
   analysis; or
2. one or more hash-bound selected frame/cell/crop derivatives, when the actual
   source pixels must shape a downstream composition, state, pose, object,
   light/material, full-scene, or ordered-sequence realization.

Do not force the first shape into start/end frames. Do not let the second shape
fall back to a whole sheet. The Front Planning reference-connection owner
decides that conditional downstream scope. The source hub owns registration
and reusable source-level analysis; the run owner applies that analysis. A
deterministic integrity check does not author semantic observation.
Historical CF research ownership is frozen compatibility only and is not an
active MV route.

## Boundaries

- Current-task Founder approval is required before public network capture.
  Generic research permission does not grant non-Bilibili extraction, and
  YouTube additionally requires a separate explicit Founder instruction naming
  YouTube for that current task.
- Do not use cookies, private sessions, secrets, or logged-in account state.
- The mechanical pipeline must not create a creative crop selection, promote a
  reference, or pass media to generation, edit, publishing, or external upload.
- A wrapper may gather bytes, hashes, probe metadata, and review sheets only.
  Keep deterministic capture and registration in scripts; keep creative review
  in the owning research/MV stage. When the return enters IDOL Front Planning,
  CDD exposes the selected Evidence Card and source-to-screen delta on the
  single `RUN/review/founder-workbench.html` lineage; the hub never creates a
  separate reference or styling board.

## Discovery contract for the owning research stage

The hub does not choose candidates, but every PRE-00/01R caller must declare
the search lane before capture:

- `shorts_reference`: duration at or below 60 seconds; a capture/discovery
  classification for short sources, including short-form or bounded excerpts.
- `music_reference`: duration above 60 and at or below 270 seconds; search MV,
  music-film, animation/film scene, or other identified original-content
  material that serves the named screen job.

These labels choose duration-aware discovery, sampling, and capture behavior.
They do not require a short-form deliverable, hook quota, derivative field, or
shorts-led MV plan.

For ordinary post-song research, the owning integrated generalist group performs
Pass A and returns a curated source-backed shortlist rather than its raw pool.
The Creative Development Director inspects every returned video/selected range,
records provisional governing/supporting candidates and named gaps, then
re-dispatches only the smallest unresolved named gap. Discovery and worker
counts are adaptive to decision readiness and provider capacity, never a fixed
quality quota. Every added owner remains disjoint, bounded, single-writer, and
stops once its named gap closes or returns HOLD.

Every survivor includes the exact original/selected-range evidence plus its
source-to-screen delta, current-song/member dependency, observable
before/trigger/after state, distinct screen contribution, whole-video
consequence, strongest feasible execution, and concrete risk. Missing evidence
is an Anti-Flat hold. The Department Dispatch v8 Contract names this skill and
all linked modules to read to EOF and apply; launch and return record lineage,
session, immutable attempt/correction state, skill revisions, aggregate
manifest, and matching input/result digests. A manual worker-authored
skill-application receipt is not an active gate, and the return route is CDD
only.

Before preflight for a new capture, the owning research stage must record the
content title, original work or artist, content category, scene/segment context,
verification source ids, and a wrong-download rejection test. Use NamuWiki,
Wikipedia, or an equivalent encyclopedic source as a context map, verify
important meaning in the original or an official source. Without exact
current-task Founder approval, do not put AMV, MAD, or fan-edit terms in a
query, search for them, open an incidental result, download, capture, play,
pixel-inspect, analyze, register, cite, use as response-pattern evidence,
nominate, bind, or directly use them. A supplied link/file is not approval.
Permission must name exact identity/URL, purpose, and allowed action; rhythm
analysis does not permit scene binding. If indispensable, return
`founder_permission_missing`; historical rows remain evidence-only.

Every query combines the selected-song target/message, at least one
Founder-reference or reference-function anchor, and one named missing screen
job such as story situation, space/background, body action, camera route,
object/world system, or transition. Rank raw public `view_count` descending only
after relevance and diversity gates pass. Do not normalize by upload age. A
popular but off-message or repetitive candidate is rejected rather than used to
fill a quota.
