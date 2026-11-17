# IDOL Artifact Management System

This page defines where new files, outputs, mirrors, and handoff packets belong.
New active song/MV runs use the album-centered address below. A date-first run
cannot be created or admitted through a generic compatibility rule. Only an
exact in-flight run named in `automation/run-layout-transition.yaml` may finish
in place while its migration plan remains on HOLD; every other date-first run
is evidence-only. The exception expires when that run closes or completes a
validated move, and it does not change any stage, gate, or quality requirement.

## Active Run Address

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/
```

- `ALBUM_KEY` groups the durable album/project.
- `TITLE_KEY` groups the selected title/song.
- `RUN_ID` identifies one production attempt or major run revision.
- `run-manifest.yaml` binds those keys, the stable `content_id`, run lineage,
  and a semantic lock of the unchanged PRE-00 through 05 route.
- Ordinary artifact edits stay in the same run and use Git plus the existing
  smallest-owner revision rules. Do not create a new run for every prompt or
  review edit.

Create and validate active roots with:

```text
python3 scripts/idol_run_layout.py init --album-key ALBUM_KEY --title-key TITLE_KEY --run-id RUN_ID --content-id CONTENT_ID
python3 scripts/idol_run_layout.py validate runs/ALBUM_KEY/TITLE_KEY/RUN_ID
```

For an old in-flight root, run `plan-migration` first. A plan that finds path
references or dependent hashes stays on HOLD; the tool never moves bytes
automatically. Continuing in place is allowed only for an exact registered
exception whose migration-plan hash and PRE-00-through-05 flow lock still
validate. Do not add another date-first path to obtain normal authoring access.

## MV Git Branch And Worktree Projection

Git branches are a physical single-writer transport for MV work, not new
creative stages or Branch Cuts. Use only three node classes:

```text
main -> mv/ALBUM/TITLE/RUN/integration -> mv/ALBUM/TITLE/RUN/lane/STAGE/TASK
```

- `main` receives only a reviewed run-integration merge.
- One run-integration branch is the canonical merge recipient for that run.
- A lane branch opens only for one valid, prepared Department Dispatch v8 and
  exact `artifact_paths`; it returns to the Dispatch recipient Director.
- Song/Front Planning/01/02A work normally stays sequential. Open a lane only
  when a real ownership conflict, disjoint section job, media session, or edit
  shard benefits from physical isolation. Do not create a branch per stage,
  schema, Core, or Branch Cut merely to mirror the graph-engineering graph.
- A worker never merges directly to `main`, creates nested worker branches, or
  expands its Dispatch write scope. Git conflict resolution cannot authorize a
  creative rewrite.

Use `scripts/idol_mv_git_worktree.rb` from a clean worktree. Commands are dry
run unless `--apply` is present:

```text
ruby scripts/idol_mv_git_worktree.rb init-run --run-root runs/ALBUM/TITLE/RUN --base-sha MAIN_SHA --worktree /ABSOLUTE/WORKTREE
ruby scripts/idol_mv_git_worktree.rb open-lane --dispatch RUN/work/department-dispatches/DISPATCH.yaml --base-sha INTEGRATION_SHA --worktree /ABSOLUTE/WORKTREE
ruby scripts/idol_mv_git_worktree.rb merge-ready --dispatch RUN/work/department-dispatches/DISPATCH.yaml --base-sha LANE_BASE_SHA
```

`init-run --apply` creates the exact run-integration branch at the supplied
`main` SHA. `open-lane --apply` first requires the current Department Dispatch
validator to pass, then creates the lane at the exact integration SHA.
`merge-ready` runs from the run-integration worktree and performs no merge: it
requires an accepted Director review, a clean committed lane, exact
Dispatch-scoped changed paths, integration ancestry, and no same-path drift
since the lane base. The Director then reviews the exact diff and merges to the
run-integration branch; the Overall Director merges the accepted run milestone
to `main`. Branch and worktree deletion are never automatic.

These are execution/provenance edges only: `branched_from` and
`reviewed_merge_candidate_for`. Semantic scene/reference relations remain in
their owning creative artifacts, and Git success never grants Founder PASS,
paid generation, upload, release, or canonical promotion.

## Core Rule

Every new file must have one owner, one canonical location, and one reason to
exist.

Use this order:

```text
canonical source -> lookup index -> optional handoff/mirror -> automation pointer
```

Do not invert the order. A Drive folder, global handoff note, queue file, or
temporary export can point to production truth, but it must not become
production truth by itself.

## Canonical, Archive, And Ephemeral Lifecycle

Classify every new artifact before writing it:

| Role | Location | Retention rule |
|---|---|---|
| Active canonical | Schema-declared run root, named research/review owner, selected asset owner, or aggregate manifest/index | Exactly one active path per logical artifact and scope. Patch stable root contracts in place. For text, Git history is the normal revision archive. |
| Active rollback | Beside the active supporting artifact only when a current tool still requires `vN` siblings | Keep at most one previous verified revision per artifact family after review closes. It is a rollback point, not an accumulating archive. |
| Physical archive | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/archive/` with `manifest.yaml` | Exceptional only: irreproducible Founder-selected source, paid-generation provenance, publishing/release proof, required source/legal provenance, reviewed learning, or one rollback checkpoint that cannot live in Git. |
| Ephemeral candidate | `runs/.../work/`, `research/drafts/`, `research/probes/`, `research/tmp/`, ignored local cache, or `/private/tmp` | Cannot satisfy a gate. Candidate count stays unconstrained before selection; after canonical promotion and review close, reject or remove unselected reproducible candidates through an approved cleanup pass. |
| Mirror/handoff copy | `drive-sync/`, global handoff, upload staging, or another declared transfer surface | Temporary and noncanonical. Prefer a pointer plus hash; when bytes must be copied, record the owning canonical path and cleanup gate. |

Do not create a physical archive for every edit. `vN` means an active revision
mechanism when a current schema or tool requires it; it does not authorize
keeping every sibling indefinitely. Once a canonical or Founder decision
exists, leave the current revision plus at most one rollback in the active
owner, use Git history for ordinary text, and move only justified irreproducible
evidence into the manifest-backed archive. Rebuildable exports, contact sheets,
previews, derived frames, rejected generation candidates, and mirrors are not
archive material merely because they were expensive to make.

The machine policy is `automation/artifact-lifecycle-policy.yaml`, validated by
`schemas/artifact-lifecycle-policy.schema.json`. A physical archive manifest
validates against `schemas/artifact-archive-manifest.schema.json`. Archive
entries must record artifact family, path, SHA-256, byte size, retention reason,
canonical relation, protection state, and review date when retention is not
permanent. Archive directories and entries must be real paths inside the owning
run; symlinked archives, symlinked contents, and `..`/resolved path escapes fail
the audit. A declared `canonical_path` also cannot cross an intermediate
symlink. The `runs/`, album, title, and run-id ownership route must also be real
rather than symlinked, and any misplaced directory named `archive` under `runs/` is
reported and fully inspected. One artifact family may keep at most one rollback
checkpoint, and that rollback entry must point to its existing current
canonical artifact. An unreadable archive directory or indexed file makes the
audit incomplete/error; it is never treated as an empty or valid archive.

Storage rules:

- Keep one canonical byte copy. Catalogs, libraries, automation, and handoffs
  should point to it instead of copying it.
- A reference `interpretation_receipt` stays on the existing canonical analysis
  row. Front Planning and 01 keep indexes/bindings to that row; derived context
  projects it. Do not create a standalone semantic-cache file, sibling receipt
  archive, or second prose interpretation.
- For reference imagery, keep the original image as canonical provenance and any
  separately approved generation attachment source. A selected contact-sheet
  cell/crop is a derived pointer/hash-bound work surface; downstream workers
  receive that selection, never the whole sheet as fallback.
- Duplicate hashes are evidence for review, never sufficient deletion authority.
  Founder/user-provided files, selected/passed media, member identity assets,
  paid-generation originals, release proof, and anything referenced by an
  active contract are protected.
- A multi-file output lane uses an aggregate manifest/index as its current
  pointer. Do not make the last packet or frame look like the canonical lane.
- Worker/task state uses `work/director-dispatch-index.yaml` and optional
  `work/director-dispatch-views/` as deterministic pointer-only projections.
  Reference research uses `research/reference-working-index.yaml`. These rows
  point to immutable Department Dispatch v8 attempts at
  `RUN/work/department-dispatches/DISPATCH_ID.yaml`, aggregate manifests, and
  exact hashes. Worker outputs, correction sources, and frozen unaffected
  outputs remain inside that same album/title/run; never create a global
  `runs/workers` directory. The rows never embed raw images, transcripts, or
  child output prose. The deterministic index builder is the sole writer. The
  CDD reviews reference deltas before the mechanical merge, and directors load
  only a stage/section-scoped Boot Pack rather than complete child histories.
- Provider sessions are lifecycle surfaces, not creative archives. One active
  OD, CDD, and Edit Director binding points to one physical session each; a
  successor/retired session remains immutable lineage evidence. Resume/fork or
  logical retire/reactivate operations never delete a session, copy canonical
  media, or create another active owner. Internal helpers leave only the parent
  Work Package's declared return/evidence, not a parallel canonical output.
- A folder with at least 20 files or 50 MiB needs a manifest/index. New tracked
  binaries of 10 MiB or more need a canonical owner plus hash, size, retention,
  and provenance metadata.
- Run `python3 scripts/idol_safe_workspace_cleanup.py` without `--apply` for
  storage/lifecycle evidence. Use `--hash-duplicates` only for a deeper scan.
  `--strict-lifecycle` is a closeout audit, not deletion. The existing `--apply`
  remains limited to harmless caches and temporary files and never deletes Git
  object files. Candidate markers and direct-file globs come from the machine
  policy so ignored Suno/style/probe drafts do not count as active revision
  pileups before selection. A forbidden root artifact lane is reported even
  when its name is a symlink rather than a real directory.
- Production deletion is never automatic. It requires a later explicit,
  hash-bound cleanup plan, reverse-reference checks, a verified canonical
  replacement when applicable, and Founder approval. A dirty, untracked,
  changed, referenced, selected, passed, published, or preservation-locked path
  is never eligible.

## Integrity Cost Profiles

Hashes here prove artifact identity and change, not cryptographic security.
The active policy minimizes repeated file reads without weakening promotion or
review gates:

| Profile | Identity | Use |
|---|---|---|
| `canonical_gate` | freshly computed SHA-256 | Canonical truth, Founder lock, approval receipt, release |
| `promotion_or_external_transfer` | freshly computed SHA-256 | Asset promotion, handoff, external transfer |
| `repeat_local_validation` | cached SHA-256 only while size, nanosecond mtime, device, and inode all match | Repeated inventory and unchanged local preflight |
| `working_derived_media` | `stat-v1` metadata fingerprint | Unpromoted preview or rebuildable working media |
| `ephemeral` | none | Disposable probe, scratch, or cache |

The cache at `.runtime/cache/artifact-integrity-sha256-v1.json` has no gate
authority. Promotion always recomputes SHA-256. A different digest may replace
this only after a measured local speed win and an explicit contract migration;
digest length is not shortened merely because security is not the purpose.

## Version Truth By Artifact Kind

Versioning is not one filename rule for every kind of file:

| Artifact kind | Active version rule | Closeout rule |
|---|---|---|
| Root stage contract | Keep the stable canonical filename and update its internal revision/status in place. Git owns ordinary text history. | Keep one current file. Do not create `final`, `latest`, or dated copies. |
| Supporting research or review text | Prefer a stable descriptive filename plus an internal revision. Use sibling `vN` only when the owning schema or tool requires it. | Keep current plus at most one verified rollback after the owning review closes. |
| Versioned folder family | Treat `folder-v3/`, `folder-v4/`, and `folder-v5/` as the same version family as files. A folder boundary does not exempt it from the current-plus-rollback limit. | Consolidate the surviving owner through an index and a reviewed cleanup plan; never infer the winner from the highest number alone. |
| Original binary or paid/generated return | Bytes are immutable. Record the original path, size, and SHA-256; a material byte change receives a new artifact id. | Preserve every original actually used by a final deliverable and any separately protected provenance. |
| Rebuildable sheet, proxy, preview, or export | Keep one current projection with source hashes, build settings, and generator revision. Reuse it when that complete recipe and output evidence match. | Regenerate only changed work; retain an explicitly required rollback after review and do not accumulate a version archive. |
| Founder decision, approval, upload result, or cleanup receipt | Immutable event record with its own id/time and exact affected paths. | Never overwrite or collapse execution history. |
| Run | A new `RUN_ID` means a new production attempt or major run revision, not an ordinary prompt, image, or review edit. | The closed run remains the owner of its final inventory and receipts. |

The practical speed rule is therefore small: unchanged local validation may use
the metadata-guarded SHA-256 cache, while selection, promotion, handoff, final
delivery, and cleanup always recompute SHA-256. This avoids repeated large-file
reads without weakening any quality or Founder gate.

## Research Is A Lifecycle Zone

`RUN/research/` is used by several early stages, but its child folders do not
all have the same authority:

| Research class | Normal location | Gate authority |
|---|---|---|
| Durable song, audience, direction, reference analysis, or selected evidence | Named files under `RUN/research/`, or `RUN/research/reference-intake/REFERENCE_UNIT_ID/` | May satisfy its owning stage only when the owning schema/skill and required receipt also pass. |
| Selected audio evidence | Owning named evidence folder under `RUN/research/` | May be cited by 00A and downstream contracts. |
| Unselected web stills, broad local experiments, or disposable extraction | `research/_local_reference_cache/`, `drafts/`, `probes/`, `tmp/`, or `style-drafts/` | None. Selection must leave the ephemeral folder before downstream use. |
| Reusable downloaded video original, navigation sheets, and Layer A/B source reading | `source-materials/video-sources/{platform}/by-source/SOURCE_ID/` | Source identity, evidence, and canonical reusable observation; the run owns only project-specific disposition and binding. |
| Reusable externally obtained still-image original | `source-materials/image-sources/by-source/SOURCE_ID/` | Immutable source/provenance evidence only; direct use and creative analysis remain current-run decisions. |
| Founder-locked current-title asset | `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` | Title asset input after its promotion manifest and Founder state pass. |

Do not create optional research folders in advance. A durable child folder with
at least 20 files or 50 MiB needs a top-level `manifest.yaml`, `index.yaml`, or
`INDEX.md` that names its source identities, status, selected units,
downstream readers, and cleanup boundary. Nested manifests do not replace the
top-level map for a large collection.

The lifecycle audit is read-only unless `--apply` is explicitly added:

```text
python3 scripts/idol_safe_workspace_cleanup.py --strict-lifecycle
```

It reports file and folder version pileups, empty optional research folders,
and large durable research folders without a top-level index. A report of no
textual downstream pointer is a review signal, not proof that bytes are unused.
Deletion still requires the cleanup process below.

## Placement Table

| Need | Location | Rule |
|---|---|---|
| Run-specific planning, analysis, intake, reference notes, deep front planning | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/` | Keep source-preserving notes here. Use `vN` only while a current schema/tool requires active revision; after selection keep the current file plus at most one rollback. |
| Run worker/session lineage and scoped director resume state | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/work/director-dispatch-index.yaml`, `work/director-dispatch-views/`, and generated Boot Pack output | Pointer/hash metadata only. Rebuild atomically from immutable dispatch attempts and aggregate manifests; no hand editing, raw media, or full transcript storage. |
| Run reference research working lookup | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-working-index.yaml` | Workers return disjoint deltas; the CDD reviews creative application and one mechanical writer performs the compare-and-swap merge. Source bytes and analyses remain at their canonical owners. |
| Canonical stage contracts | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/00...05*.yaml` | Root contract files are the current production state. They may cite research, review, exports, and generation files. |
| Founder/generation review, returned-image intake, contact-sheet review records, worklists | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/` | Store review material, decision intake, and selected-reference intake here. Use `review/manifests/founder-workbench.yaml` plus `review/founder-workbench.html` as the stable collapsible Founder workbench; store canonical decisions under `review/founder-interventions/`. A review folder should include an index/manifest when it contains multiple images, sheets, or candidates. |
| API exports, prompt exports, packet manifests, batch manifests | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/exports/` | Exports are reproducible outputs from locked artifacts. `exports/02B/sections/Sxx/` is a pointer-based execution package; the root 02B packet file remains canonical and no root all-song API aggregate is kept. |
| Generated branch-cut images, boards, raw video, QC sheets, prompt files, renders | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/` | Generated media stays in the run. Use subfolders by lane, such as `branch-cuts/`, `boards/`, `video/raw/`, `video/raw/additional/`, `video/qc/`, `video/master/`, and `video-prompts/`. New added video uses only `video/raw/additional/`; a populated historical `video/raw/addiontal/` folder is evidence-only and holds active intake until a hash-bound migration plan closes. A built-in tool or LLM return outside the run is temporary until copied to the packet's expected path, hashed, pixel-inspected, and registered. |
| Run-owned source packs or cue packs for another worker | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/` | This is the canonical handoff source pack for the run. Global handoff files may point here. |
| Stable cross-day lookup for an album/title | `catalog/albums/ALBUM_KEY/TITLE_KEY/` | Keep compact read-models, `output-registry.yaml`, optional `reference-index.yaml`, and optional `contact-sheet-index.yaml` pointers here; catalog stores pointers instead of full run-file mirrors. |
| Cross-run reference management sheet | `catalog/references/reference-catalog.yaml` | Pointer-only source, analysis, purpose-class, and immutable usage-history lookup. It never grants creative application, direct use, attachment, or Founder PASS. |
| Long-lived founder/source material | `source-materials/` | Use only for durable briefs or references that should outlive one run. Ordinary run research stays in the run. |
| Repeatedly useful references after one or more runs | `reference-library/` | Promote only when a reference has durable reuse value. Do not promote a run-specific motif as default. |
| Member, voice, unit, identity, and approved promoted album assets | `assets/` | Base identity and selected promoted boards only. Do not overwrite base member boards with run styling. |
| Shared scripts | `scripts/` | Only reusable validators, extractors, worklist builders, contact-sheet builders, state reporters, exports, or preflight helpers. One-off run helpers should stay under the run unless intentionally reusable. |
| Automation state, queues, gates, next action pointers | `automation/` | These files point to run truth and founder gates. They do not create creative approval or production locks. |
| Global Grok/LLM coordination | `handoff/grok/`, `handoff/llm/` | Keep compact request packets, active pointers, and advisory returns here. Production intake must move selected material into the run. |
| Manual Drive/Grok/GPT transfer copy | `drive-sync/02_GPT_GROK_HANDOFF/` | Create only when the founder requests a handoff or external review. It is a mirror, not canonical truth. |
| Source-faithful teaser | Path selected by `teaser/AGENTS.md` | Active isolated teaser direction; retain its source, production and approval gates. Do not infer a CF migration or new global run layout. |
| Frozen CF history | `../../archive/cf-legacy-20260909/cf/` from IDOL root | Original bytes remain in the HQ archive. `cf/` is a historical read/hash compatibility link, not an active run or output destination. CF and song/MV artifacts remain separate. |

## Album Reference And Contact Sheet Indexes

Create album/title reference indexes when references or contact sheets become
large enough, reused enough, or scattered enough that broad search becomes the
only way to find them. This is a lookup contract, not a new media dump.

Use these optional files:

```text
catalog/albums/ALBUM_KEY/TITLE_KEY/reference-index.yaml
catalog/albums/ALBUM_KEY/TITLE_KEY/contact-sheet-index.yaml
```

Validate them against:

```text
schemas/album-reference-index.schema.json
```

Storage rule:

- Keep `catalog/albums/ALBUM_KEY/TITLE_KEY/` pointer-only by default. It may
  store compact read-models, manifests, and small review notes, but should not
  receive full copies of every source video, generated frame folder, or contact
  sheet.
- Keep run-specific reference downloads, generated review boards, and contact
  sheets in the owning `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/**` folder unless the founder
  asks for a cleanup/migration.
- For deterministic HTML review boards, keep the thin source-bound projection
  manifest at `RUN/review/manifests/founder-workbench.yaml` and the rebuildable
  rendered HTML at `RUN/review/founder-workbench.html`. Increment the manifest's
  internal board/section revisions and fold superseded cycles in that one
  surface instead of accumulating a new HTML file per review. One active cycle
  may cover one section, a named multi-section set, or the whole video, while
  every card records exact affected section ids for later section-owned
  fanout. Canonical
  02A/01/reference/03V artifacts and validated Founder-intervention receipts
  remain the creative truth; the manifest owns only source pointers and review
  layout choices, browser-local decisions are intake candidates, and the HTML
  owns no independent creative fields.
- A Founder-direct update keeps the last passed review and its exact source
  bytes as the single active rollback pair until the affected route closes.
  The current canonical owner remains at its stable path; ordinary later text
  history belongs in Git, not an expanding set of `vN`, `final`, or copied
  review/output folders.
- Keep durable cross-run external source caches in `source-materials/**` when
  they are reused across albums or production units.
- Promote only founder-locked, title-specific visual assets into
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` with a manifest. This is
  the right place for the small set of canonical album member, look, space,
  object, wardrobe/material, identity-source, and branch-cut-insert assets that
  should travel into future Front Planning, 01, 02A, 02B, and 03V work.
- Keep ordinary contact sheets as review surfaces. Promote a contact sheet into
  album assets only when it becomes the title's canonical look, space, object,
  wardrobe/material, or branch-cut-insert board. Otherwise, register it in
  `contact-sheet-index.yaml` and leave the file in its run/source owner.
- Catalog mirrors of large files are legacy or exceptional portability aids.
  New work should prefer `canonical_path` plus optional lightweight mirror
  notes. If a mirror is created, record both canonical and mirror paths, hash,
  status, and cleanup policy in the index.

Path rule:

- `ALBUM_KEY/TITLE_KEY` are placeholders. INK paths stay examples for INK only.
  Resolve the active keys from the title registry, current run, 00A, or Front
  Planning readiness, then write the new album's own paths.

## Unified Reference Evidence Map

The wiki owns one routing map for both video and still-image reference work.
Files remain with their actual canonical owners; “one place” means one
unambiguous lifecycle and lookup path, not one duplicated media dump.

| Step | What is owned | Canonical location | What moves forward |
|---|---|---|---|
| 1. Discovery | Query, candidate URL, source identity check, context, rejection test, and named missing screen job | Durable candidates under `RUN/research/reference-intake/`; disposable exploration under `research/drafts/` or `_local_reference_cache/` | Source identity and why the candidate was inspected |
| 2. Reusable capture | Permitted video original plus broad navigation evidence, or a reusable externally obtained still original | `source-materials/video-sources/{platform}/by-source/SOURCE_ID/` or `source-materials/image-sources/by-source/SOURCE_ID/` | Exact source-manifest pointers and hashes; never another canonical media copy |
| 3. Selected bounded evidence | One selected event range, cell, frame, crop, or still image that can be reviewed independently | Video range may remain hash-bound in the source hub; a run-owned selected still/crop or direct-use derivative goes under `RUN/research/reference-intake/REFERENCE_UNIT_ID/` | Exact path, SHA-256, source locator, inspected pixels, section ids, and attachment role |
| 4. Source analysis, then run disposition | Whole-source progression, timestamped Layer A/B observations, reusable transfer/exclusion boundaries; then current-song/commercial function and `applied`/`combined`/`held`/`rejected` state | Reusable observation under `source-materials/video-sources/{platform}/by-source/SOURCE_ID/analysis/`; current use under `RUN/research/reference-intake/REFERENCE_UNIT_ID/` | Source-analysis revision plus run-owned locator, disposition, and binding |
| 5. Cross-run and album/title lookup | Cross-run source/function/usage pointers plus the current title's selected-unit pointers | `catalog/references/reference-catalog.yaml`, then `catalog/albums/ALBUM_KEY/TITLE_KEY/reference-index.yaml` and optional contact-sheet index | Pointers only; no media mirrors and no inferred creative application |
| 6. Title asset promotion | Founder-locked visual that should govern later work for this title | `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` with a promotion manifest | The promoted title asset and exact original provenance |
| 7. Production binding | Smallest useful selected inputs applied to section/cut truth | Front Planning -> 01 -> 02A -> 02B attachment order -> 03V/edit lineage | Exact ids, paths, hashes, function, and ordering; no raw pool or whole-sheet fallback |

For still images, an unselected download may remain in the ignored local cache.
Once the Founder or director applies or combines it, the exact image or selected
crop plus its source note must be promoted into the durable run-owned
`reference-intake` unit before it can shape 01, 02A, or generation. This closes
the current gap where an ignored cache can otherwise become the only surviving
copy of a selected reference.

For video, always read `source-materials/video-sources/READ-FIRST.md` before
reopening registered media. Use the complete source-owned analysis when its input
hashes and meaning are unchanged. A navigation contact sheet is never a final
reference unit; the selected range receives its required one-second evidence,
and only frames whose pixels continue downstream receive selected
frame/crop derivatives.

The source hub and run have deliberately different jobs:

```text
source hub = source identity + original bytes + reusable navigation evidence + Layer A/B source analysis
run = selected bounded evidence + project-specific disposition + downstream binding/use
cross-run catalog = source/analysis/function/usage pointers
title catalog = current-title selected-unit pointers
assets = Founder-locked current-title promotion
```

Keep adding reusable sources and observations to the source hub. Runs consume
them by path/hash reference by default, or copy only the smallest execution-
required selected derivative with provenance. Never make a run folder the sole
owner of reusable Layer A/B analysis.

## Downloaded Reference Hubs

This workspace has two media-type-specific, run-external source owners:

```text
source-materials/video-sources/
source-materials/image-sources/
```

Do not create another top-level source hub or place large media in
`reference-library/`. Every permitted `yt-dlp` original enters the video owner
first with reusable broad navigation evidence. A reusable externally obtained
still enters the still-image owner once with its immutable original,
provenance, availability, and backup state. Later runs resolve either source
through `catalog/references/reference-catalog.yaml` before downloading or
capturing again.

Hub rule:

- Canonicalize future source media by stable identity at
  `source-materials/video-sources/{platform}/by-source/SOURCE_ID/`. Keep one
  active `source-manifest.yaml` and one active `frame-index.yaml`; use Git for
  text history instead of sibling `vN` or archive piles.
- Keep `reference-hub-catalog.yaml` pointer-only. It groups normalized platform
  id, URL aliases, and matching SHA-256 identities so the same source is reused
  across titles and dated collections.
- Keep `source-materials/image-sources/reference-image-catalog.yaml`
  pointer-only. Its source manifest never grants direct use or generation
  attachment. Founder-supplied direct images may remain in the owning run, so
  this reusable still-image owner does not break or replace the existing
  direct-image route.
- A registered video or still source whose local original is missing is a
  HOLD. Do not silently download it again. `backup_state: local_only` records
  reusable local availability without pretending that cross-machine recovery
  is closed.
- Run `scripts/idol_reference_hub.py preflight URL` before every permitted
  capture. `reuse_existing` means use the registered video/sheets; a registered
  source whose evidence is absent or stale is a hold and may not trigger a
  silent redownload.
- Preserve existing run-owned or dated-collection originals in place until a
  separate hash-bound migration/cleanup is approved. Register them as legacy
  owners or create a verified hardlink into the identity owner; never delete or
  copy them merely to make the tree look uniform.
- For unselected run-specific web stills, dense-sheet experiments, crops, or
  analysis-only derivatives, a gitignored
  `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/_local_reference_cache/` may remain a
  work cache. It points to the hub source manifest and must not hold the only
  canonical `yt-dlp` original. An applied or combined still/crop leaves this
  cache and enters a durable `research/reference-intake/REFERENCE_UNIT_ID/`
  package before downstream use.
- For local-only unselected caches, use `manifest.local.yaml` and keep it inside
  the ignored cache folder. Add or update
  `catalog/albums/ALBUM_KEY/TITLE_KEY/reference-index.yaml` or
  `contact-sheet-index.yaml` with pointer-only records naming the album/title,
  graph-engineering stage, run owner, cache manifest path, source refs, and inspection
  status. A selected frame/contact sheet cell is first promoted to durable
  run-owned reference intake; the catalog then points to that durable owner.
- Optional `aliases/` folders may contain symlinks for quick browsing. They are
  lookup aids only; production artifacts should cite the original owner path
  from the manifest.
- If a requested song lacks a true local choreography source, record that gap in
  the manifest and in the active analysis note before writing prompts that might
  imply direct extraction.

Collections, albums, and runs are pointer groupings, not alternate hubs. Their
indexes cite the source identity owner and selected sheet/cell evidence.

### 01R Local Reference Cache Flow

For 01R source-assisted direction mining, use this lifecycle:

```text
local-first lookup
-> metadata/source note
-> minimum necessary local capture
-> source-hub register
-> reusable broad contact sheet + frame index
-> selected dense sheet parts when needed
-> raw observation note
-> Codex-selected current-song function
-> run cache manifest
-> album/title pointer index
-> optional reusable-function promotion
```

The default owner for a permitted `yt-dlp` original is:

```text
source-materials/video-sources/{platform}/by-source/SOURCE_ID/
```

The optional owner for unselected current-run cache material is:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/_local_reference_cache/
```

That folder is local-only and ignored by git. Keep a `manifest.local.yaml` in
the same folder with cache set ids, source title, platform/source URL, approval
or policy basis, source-hub manifest/frame-index pointers, inspected sheet
paths, candidate cells or frames, and status. When one unit becomes `applied`
or `combined`, promote its exact bounded evidence and source note to:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/REFERENCE_UNIT_ID/
```

Then add pointer-only rows to the active title's `reference-index.yaml` and/or
`contact-sheet-index.yaml`. The catalog points to the durable selected unit
while broad media remains under its source-hub owner.

Do not turn dense capture into one unreadable sheet. For a new source, first
make a broad scan such as 5-10 second or source-chapter/time-range sheets. Use
2-3 second sampling only for navigation or repair-gap discovery; it cannot
itself satisfy the active exactly-five one-second Sequence Unit. Split dense sheets by useful source range, active section,
or fixed 30-60 second chunks. Each sheet part should carry source-time labels,
and when mapped to the current song, section ids or song-time labels. Record
which sheet part and cell/frame ids were actually selected before applying the
reference in Front Planning, 01, or 02A.

Promotion rule:

- Original video and reusable broad-sheet/frame-index evidence stay in the
  source hub. Unselected local derivatives may stay in the run cache.
  Applied/combined selected derivatives stay in durable run-owned
  `research/reference-intake/` plus the title `reference-index.yaml` or
  `contact-sheet-index.yaml`.
- Founder-locked album visual assets move only to
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` with an asset manifest.
- Existing legacy source collections remain indexed in place. New reusable
  sources already enter `source-materials/video-sources/**` by stable identity,
  so later promotion moves only selected function notes or pointer rows.
- Repeatedly useful abstract functions, such as a camera route, object-system
  behavior, choreography mechanic, or edit grammar, may be summarized in
  `reference-library/**` after one or more reviewed uses. The library note must
  cite the source identity and the exact followed surface; it must not promote a
  prior-run motif, scene noun, action, camera route, or composition as a default
  for later titles.
- For the quick worker-facing lookup order and reusable-function note shape,
  start with `reference-library/README.md` before creating a new library note.

## New File Checklist

Before creating a file or folder, answer:

1. Which run, album/title, asset, handoff, or automation surface owns it?
2. Is it canonical source, generated output, mirror, pointer, or temporary
   scratch?
3. Which upstream source paths must it cite?
4. Which downstream artifact or worker will read it?
5. Does an existing schema, registry, or script already define the correct path?

If the answer is unclear, do not create a new folder. Add a short note to the
current run's `research/`, `review/`, or `handoff/` folder, or report the
placement question to the founder.

## Markdown File Policy

Markdown files are easy to create and easy to lose. Treat every durable `.md`
as one of these classes before writing it:

| Markdown class | Location | Rule |
|---|---|---|
| Founder-facing route cards or light PRE-00 inspiration | Chat by default; if preserved, `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/pre-00-route-cards-vN.md` or a schema-backed radar file | Do not create a run file for every brainstorm. Preserve only selected or reusable route material. |
| Selected route intake, compact brief, or LEFT-style planning brief | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/harness-intake-brief-vN.md` | Durable front-planning source. Cite founder source, concrete situation, message, references, and guards. |
| Reference song, selected audio, lyric bridge, audio-motion explanation, wardrobe/style review | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/*-vN.md` beside optional `.yaml` or `.json` | The `.md` is the AI/model-readable narrative source. The structured sidecar is for validation/automation when present. Keep both paths aligned. |
| Reference notes, MV observations, contact-sheet observations, source bundles | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-*-vN.md` or `research/*-bundle-vN.md` | Store source-preserving observations and function notes here. Do not move ordinary run research to `reference-library/` unless it becomes reusable after review. |
| Informal exploration that is not production truth | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/drafts/`, `research/probes/`, or `research/tmp/` | These files cannot satisfy gates. Promote selected content into a named `research/*-vN.md` before downstream use. |
| Review worklists, contact-sheet review notes, decision sheets, playback/QC notes | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/*-vN.md` or `review/FOLDER/INDEX.md` | Review `.md` files explain the review material or review stage. Decisions that automation reads should have a `.yaml` sidecar or schema-backed record. |
| Run-owned handoff source packs, cue packs, motion guides | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/*.md` | Canonical handoff material for the run. Global `handoff/` or Drive files may point here. |
| Video prompt prose | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video-prompts/**/prompt.txt` or another path declared in `03V-video-prompt-manifest.yaml` | Only after typed passed Production Cut pixels and the owning section's 03V source pack are ready. The active v8 manifest is the sole prompt truth and exact cue/path index; do not create or maintain a separate `video-prompt-index.yaml`. |
| Prompt exports, API prompt readouts, generated package notes | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/exports/**/*.md` | Derived from locked artifacts. Do not edit exports as source truth; regenerate or patch the source artifact. |
| Root production plans without schema-native YAML | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/publishing-plan.md`, `analytics-summary.md` | These are allowed run-root Markdown contracts because their names are stable. Do not add loose root `notes.md`. |
| Album/title lookup notes | `catalog/albums/ALBUM_KEY/TITLE_KEY/*.md` | Keep compact lookup/read-model notes only. Link to run-owned source instead of copying full research. |
| Automation AI/model-readable surfaces | `automation/**/*.md` | Must mirror or point to schema-backed `.yaml`/`.json` state where automation depends on it. Narrative summary only. |
| Global Grok/LLM handoff notes | `handoff/grok/*.md`, `handoff/llm/*.md` | Advisory transfer surfaces. Selected material must be intaken into the owning run before patching production artifacts. |

Downstream hash/read-model artifacts remain run-owned:

- Audio Production-Cut Placement, detailed timing, and playback refresh state:
  `review/03v-audio-branch-cut-placement-vN.yaml`,
  `review/03v-final-audio-detailed-timeline-vN.*`, and
  `review/03v-playback-refresh-state-vN.yaml`.
- Reusable 03V source discovery: `handoff/03v-source-snapshot-vN.yaml`; this is
  a compact path/hash index, not a replacement for the source files.
- Exact external-action approval:
  `review/platform-release-approval-vN.yaml` or another named run-owned review
  path that validates against the same schema. Do not store approval in a
  global ledger or automation pointer alone.
- Filtered performance evidence:
  `analytics/social-evidence-snapshot-vN.yaml`. Global post/metric ledgers stay
  global source truth; the snapshot is the content-scoped read model.
- Observed public URLs are registered as title `remote_publication` pointers;
  uploaded media, trackers, logs, and publication records remain in the run.

### Durable Markdown Header

Durable run-owned `.md` files should start with a compact status block unless
they are generated prompt text, a README, a template, or a table-only review
surface:

```yaml
status:
run:
stage:
source_refs:
downstream_use:
```

Keep this block short. It is not a schema replacement; it tells the next worker
whether the file is draft, founder_review, selected, superseded, or ready for a
specific downstream use.

### Markdown Lifecycle

- If a `.md` note becomes required by `00`, `00A`, `01`, `02A`, `02B`, `03V`,
  or `04`, promote it from `drafts/`, `probes/`, or `tmp/` into a named
  `research/*-vN.md`, `review/*-vN.md`, or `handoff/*.md` artifact.
- If a `.md` summarizes many source files, keep it as an index with source
  links. Do not paste full source prose into a second place.
- If a `.md` is only the AI/model-readable narrative view of a YAML/JSON record, keep the
  structured file as the machine-readable source and update both together.
- If a `.md` is superseded during active production, mark it `status:
  superseded` and point to the replacement until the affected gate closes.
  After close, keep at most one rollback sibling; ordinary text history remains
  in Git and additional unreferenced siblings become cleanup candidates.
- If a `.md` is purely scratch and will not be read downstream, keep it under
  `research/tmp/` or use `/private/tmp` for local tests.

## Naming And Versioning

- Use stable descriptive names: `reference-song-fit-v3.md`,
  `02a-reference-intake-v1/`, `03v-motion-reference-intake-v1/`,
  `grok-video-prompt-reference-pack-TITLE_KEY.yaml`.
- Use `vN` for revised supporting artifacts only when the current schema/tool
  requires sibling revisions. `vN` is not a retention policy. After selection
  and reference validation, keep the current revision plus at most one rollback;
  use Git history for ordinary text. Do not use names such as `final_final`,
  `new`, `latest2`, or `testtest`.
- Root run contracts are the current state. Patch them in place when the
  canonical state changes, while keeping source notes and review evidence in
  versioned supporting files.
- Do not create loose run-root Markdown files such as `notes.md`,
  `analysis.md`, `todo.md`, or `scratch.md`. Put them in the correct run
  subfolder and name the stage or purpose.
- Nontrivial folders containing multiple assets need an `INDEX.md`,
  `manifest.yaml`, or schema-backed index that records source paths, status,
  and downstream use.
- Do not create empty directory trees for future stages.
- Do not create repo-root `tmp/`, `output/`, `outputs/`, or loose review folders
  for run work. Use `/private/tmp` for disposable local tests or the owning run
  folder for durable artifacts.

## Handoff Rules

Handoffs are transfer surfaces, not locks.

Before sending work to Grok, GPT, another LLM, or Drive:

1. Create or identify the run-owned canonical source pack, cue pack, review
   intake, prompt folder, or current artifact.
2. Write a compact handoff that names the canonical run path, task, allowed
   operation, forbidden changes, source refs, expected return shape, and output
   destination.
3. Mirror to `drive-sync/` only when the founder explicitly asks for external
   review, Grok/GPT transfer, or manual upload.
4. Keep returned notes, candidates, or images advisory until the founder selects
   them or Codex intakes them into a run-owned `research/`, `review/`, or
   `generations/` path.
5. Do not patch `00`, `00A`, `01`, `02A`, `02B`, `03V`, or `04` directly from a
   global handoff or Drive folder without a run-owned intake record.

For LLM/GPT storyboard review, the temporary Drive source pack belongs under:

```text
drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/source-pack-vN/
```

Founder-selected returned images must be copied into:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/02a-reference-intake-vN/
```

For Grok/video-prompt work, canonical prompt files belong under:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video-prompts/
```

Optional Grok request packets may point to a run-owned reference pack under:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/
```

Drive mirrors may point to those files, but edits must happen in the run first
and be re-synced.

## Final Delivery And Final-Used Originals

At 05 closeout, keep one stable logical final-delivery root:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/package/final-delivery/manifest.yaml
```

The manifest validates against
`schemas/final-delivery-manifest.schema.json` and is checked with:

```text
scripts/idol-video-python scripts/validate_final_delivery_manifest.py \
  runs/ALBUM_KEY/TITLE_KEY/RUN_ID/package/final-delivery/manifest.yaml
```

New final-delivery authoring uses `idol-final-delivery-manifest.v2`. It binds
the exact `idol_package.v2` bytes, the package's normalized
`/production_graph_trace` digest, and one `package_output_id` per final
deliverable. The validator rechecks the package schema, its 04 map/recipe
source bytes, and the output path/SHA mapping. This closes traceability; it does
not authorize publishing, cleanup, promotion, or post-05 mutation of MV truth.
The active schema accepts v2 only. Preserved v1 manifests remain readable
through `schemas/final-delivery-manifest-v1-legacy.schema.json`; this legacy
reader is non-authoring and never upgrades or rewrites the preserved bytes.

This is a pointer-first collection. It does not copy every planning file,
reference video, image, or raw clip into a second “final” tree. It binds the
one canonical path, byte size, and fresh SHA-256 for:

1. the full-quality final master and every actually closed delivery derivative;
2. every original generated image, raw generated video clip, selected audio,
   or external edit source that is used by one of those deliverables;
3. selected reference source manifests, bounded evidence, run-owned analyses,
   and promoted title-asset manifests that remain necessary to explain the
   final visual lineage;
4. the passed prompt packets/video-prompt manifest, edit map and recipe,
   renderer/QC records, Founder decisions, and required application receipts;
5. the complete 90s+/45s/shortform derivative slate and any unresolved output.

“Final-only” therefore never means “keep only the compressed upload MP4.” It
means:

```text
final deliverables
+ exact final-used original bytes
+ source/reference dependencies
+ prompt/edit/render/QC/Founder lineage
```

Quality preservation is literal:

- Keep the original returned PNG/JPEG or other generated-image bytes used by
  the video. A WebP, thumbnail, contact sheet, or review proxy may coexist, but
  it cannot become the only keeper.
- Keep each raw video source byte file actually used by the final recipe.
  Re-encoded edit proxies and platform derivatives cannot replace it.
- Keep the hash- and QC-bound full-quality master. Delivery recompression is a
  derivative, not the archive-quality source.
- Keep source media at its existing canonical owner and point to it. A final
  inventory is not permission to create role-labeled duplicate copies.

Do not classify a passed but currently unused image or clip as removable until
the coherent master, 45-second cutdown, shorts, and any other planned
derivatives are all explicitly closed. Even then it is only a cleanup
candidate. The final-delivery manifest grants no deletion, publishing, paid
generation, or public-release authority.

The final manifest remains at one stable filename. Git owns its ordinary text
history. If a deliverable's bytes change, give the changed media a new artifact
id and update the manifest; do not create `final-final`, `latest2`, or a dated
final-delivery sibling.

## Cleanup Rule

Existing scattered work is not automatically wrong. Preserve in-flight material.

When cleanup is requested:

1. Inventory files first.
2. Identify canonical source, duplicates, mirrors, and stale scratch.
3. Separate active canonical, one rollback, exceptional archive, ephemeral
   candidate, mirror, and reproducible derivative before proposing action.
4. Propose a hash-bound cleanup plan; duplicate bytes, filename, age, or version
   number alone never authorizes deletion.
5. Before production cleanup, complete and validate
   `package/final-delivery/manifest.yaml`; verify that every final-used original
   and every still-open derivative remains protected.
6. Update `output-registry.yaml`, handoff pointers, automation pointers, and
   source refs after the move.
7. Write an immutable cleanup receipt mapping every removed path/hash to its
   surviving canonical owner or its approved no-replacement disposition.
8. Validate the run still resolves from the run folder, final-delivery
   manifest, and title registry.

No broad cleanup should happen during creative authoring unless the founder
explicitly asks for that cleanup round.
