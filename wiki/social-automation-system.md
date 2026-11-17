# Social, Automation, And Artifact System

This page holds run artifact policy, post-review handoff rules, social
publishing/analytics rules, git artifact policy, and automation boundaries.

For an operational question such as whether X/TikTok/YouTube currently work,
credential recovery, or the exact approved upload route, start with
`wiki/platform-credential-and-draft-upload-ops.md`, then use
`skills/idol-social-metadata-upload/SKILL.md`. This page is the detailed policy
owner, not the fastest posting runbook.

For the prospective placement rule for new files, outputs, handoff packets,
Drive mirrors, automation pointers, and cleanup rounds, see
`wiki/artifact-management-system.md`. This page keeps the detailed post-review,
package, social, and ledger policies.

## Run Artifact Layout

Song-led content runs use this shape. Create subdirectories only when they
actually contain content:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/
  research/
    pre-00-research-radar.yaml
    drafts/
    probes/
    tmp/
    reference-song-fit-vN.md
    song-candidate-set-vN.md
    suno-prompt-packet-vN.md
    selected-audio-analysis-vN.md
    selected-audio-analysis-vN.json
    audio-motion-director-map-vN.yaml
  run-manifest.yaml
  00A-song-lock.yaml
  01-song-choreography-performance-mv-map.yaml
  02A-master-storyboard.yaml
  02B-prompt-packets.yaml
  03-generated-branch-cut-review.yaml
  03V-audio-branch-cut-placement.yaml
  03V-storyboard-assist.yaml
  03V-video-prompt-manifest.yaml
  exports/
    board-prompts/
    manifests/
  generations/
    boards/
    video/
      raw/
        additional/
      qc/
        finishing-fx-vN/
      master/
    video-prompts/
      SECTION_OR_CUE/
        prompt.txt
  04-edit-map.yaml
  05-package.yaml
  publishing-plan.md
  analytics-summary.md
```

Main contract YAMLs stay at run root so they act as the source of truth.
Supporting run artifacts go under `research/`, `exports/`, and `generations/`.
Markdown notes created during graph-engineering work follow
`wiki/artifact-management-system.md`: durable notes get stable stage/purpose
names under `research/`, `review/`, `handoff/`, or `generations/video-prompts/`;
scratch stays under `research/drafts/`, `research/probes/`, or `research/tmp/`.

Active scripts accept only `generations/video/raw/additional/`. Historical
misspelled folders remain evidence-only and must be migrated through a
hash-bound plan before reuse.

Run integrity checks:

- Root contract files are source of truth; generated exports and Drive mirrors
  are supporting records or transport, not replacement truth.
- Do not create empty template directories just to satisfy a route check.
- Do not mix song-led outputs, CF-code outputs, board exports, video prompts,
  and final renders into the same generation lane.
- A copied Drive handoff is valid only when the canonical run-owned source also
  exists.
- If a path is declared by a schema or `export_contract`, use that path instead
  of inventing a convenient output folder.

## Pre-00 Research Radar Output

Automation/inbox runs keep compact candidate briefs outside content run roots.
Only the founder-selected, normalized route enters the target run as:

```text
research/pre-00-research-radar.yaml
```

## Post-Review Video Prompt Authoring

After Founder image review passes, the assigned exact-one-section post-02A
image-motion owner under CDD writes video prompts for the actual passed visual
lock into the run folder. That visual lock is one to three passed Production
Cut images of type `official_core` or `branch` per Motion Storyboard. The owner
uses `idol-video-prompt` as the canonical authoring skill; legacy MV/stage/mix
prompt skills are old-output references only. Grok app, Grok TUI, or Grok CLI
are optional external refinement/execution routes only when the Founder
explicitly asks for them. Transfer to the Founder-selected model follows the project-data approval
owned by `AGENTS.md`. Video generation and Drive mutation retain their separate
current-task authorization; preparing a source pack grants neither.

The generated Branch review records exact generated Branch images, then the
typed Production Cut review joins its passed rows with 01's passed Official
Core primary images in G-40 order. Only passed `official_core|branch` rows may
enter Audio Production-Cut Placement and 03V. The legacy placement filename
does not narrow those active semantics to Branch rows. A contact sheet is
navigation or review evidence only, never a source visual lock.

For section-image-to-video work, source-pack creation is not completion. 03V
must bind the one to three passed typed Production Cut images, cue timing,
motion route, transition intent, output paths, and contextual section/whole-
video review before merge.
Drive mirrors are convenience copies, not readiness gates.

Use the Codex source-pack helper when the pass set needs structured authoring:

```text
ruby scripts/idol_prepare_video_prompt_authoring.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID --write
```

Use the source-pack Grok helper only for Founder-requested external refinement:

```text
ruby scripts/idol_prepare_grok_video_prompt_handoff.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID --source-pack runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/03V-authoring-source-pack.yaml --founder-requested --write
```

Canonical prompt files remain under:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video-prompts/
```

The optional Drive mirror is:

```text
drive-sync/02_GPT_GROK_HANDOFF/03-review_TITLE_SONG_KEY_video-prompts/CONTENT_ID/
```

The title registry is the cross-day lookup index for the run-owned prompt
files and any founder-requested Drive mirror:

```text
catalog/albums/ALBUM_KEY/TITLE_SONG_KEY/output-registry.yaml
```

After founder pass, Codex may run the Founder-pass graph-engineering check for local validation
and reporting:

```text
ruby scripts/idol_founder_pass_harness.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID --album-key ALBUM_KEY --title-key TITLE_SONG_KEY --pass-date YYYY-MM-DD --write
```

This does not stage Grok/Drive handoff by default. If optional Grok refinement
or Grok Imagine Drive staging is requested in the same step, use the explicit
Grok wrapper or add `--sync-grok-imagine --founder-requested`.

The Drive staging destination is:

```text
drive-sync/02_GPT_GROK_HANDOFF/02-03_TITLE_SONG_KEY_grok-imagine/CONTENT_ID/VERSION/
```

Historical 02-03 Grok Imagine cue sheets used compact `Tempo/Pulse`,
`Audio Cue`, `Action Hint`, `Cut Summary`, and `Prompt Summary` columns. New work
must read the current hash-bound Audio Motion Director Map instead of creating a
cue/BPM compatibility artifact:

```text
ruby scripts/validate_audio_motion_director_map.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/audio-motion-director-map-vN.yaml
```

Every founder-requested Grok/LLM Drive handoff sync must refresh:

```text
drive-sync/02_GPT_GROK_HANDOFF/00_ASSET_CONTEXT/
```

Canonical source for member assets remains `assets/**`.

## Social Publishing And Analytics

After a master, cutdown, or selected short exists, a run may add:

- `publishing-plan.md`
- `analytics-summary.md`

Minimum-intervention graph engineering:

```text
05-package exists
-> create active publishing-plan.md
-> prepare each API video as a receipt-bound 2K-or-higher CFR30 asset
-> prepare one run-owned mixed-platform platform-posts-*.jsonl batch
-> project package/plan/registry state locally with explicit run/content paths
-> validate social ledgers
-> stop at a schema-valid Founder approval artifact bound to the exact canonical
   action-bearing queue SHA-256 before upload, schedule, publish, platform API
   sync, or Drive Sheet mutation
-> after founder-approved upload/API attempt is logged, run post-upload social closeout
-> after all platform facts close, validate the immutable publishing record
```

For a standalone post-05 request, use
`skills/idol-social-release-orchestrator/SKILL.md` instead of opening the MV or
CF graph-engineering route. It keeps one run-owned
`review/social-release-session-v1.json` and one combined
`review/social-release-decision-packet.md`. Register the finished-content batch
once; later wakes refresh the stored pointers and compare the state digest.
`mode=unchanged` performs no rewrite and must not wake the Founder. An exact
approval, upload result, public closeout, Web projection, or fixed checkpoint
advances the same session without asking for the same decision again.

The session is a read model, not approval or external authority. Its contract
is `schemas/social-release-session.schema.json`; its local-only builder is
`scripts/idol_social_release_session.py`. A plain PASS cannot be widened into
draft upload, public publish, scheduling, or Web deploy authority.

Multi-platform public batch order (Founder exception only if locked):

```text
1) X first — skills/x-posting-template (work roots + derived clips + member
   stills; craft/process threads optional; graph-engineering intensity 0–3)
2) TikTok + YouTube / YouTube Shorts — idol-social-metadata-upload + reels-tiktok-template
3) Instagram Reels — manual package (reels-tiktok-template)
```

The common queue does not imply one common external API. Route each row by its
declared execution contract:

| Platform | `delivery_mode` | Adapter |
| --- | --- | --- |
| X | `public_api_post` | dedicated hash-bound X public adapter |
| TikTok | `platform_draft` | TikTok inbox API |
| YouTube / Shorts | `platform_draft` | private YouTube upload API |
| Instagram Reels | `manual_upload_package` | manual package/checklist |

The automatic draft uploader selects only TikTok and YouTube/Shorts from a
mixed queue. Explicit X or Instagram filters fail with their correct route.

Every API-bound video uses `idol_api_upload_2k30_high_quality.v1`: long edge at
least 2560, short edge at least 1440, exact CFR30, progressive H.264/yuv420p,
and AAC48k audio at 256kbps or higher. TikTok/YouTube/Shorts queues bind the
exact run-owned `idol_api_upload_video.v1` preparation receipt. The X and
automatic draft adapters probe the bytes before network access; the latter also
revalidates the receipt before staging and again from the byte-identical upload
snapshot. No uploader performs a hidden quality-lowering transcode.

Public copy constants for active Loom social templates:

- Language: English only; poetic idol/message lines from brand-core or run locks
- AI-made disclosure (required): `AI-made with Grok and GPT.`
- Non-X stack body line: `Grok plan → GPT image → Grok Imagine → edit on Grok Build.`
  (or compact `GPT image → Grok Imagine → Grok Build`)
- X: follow `skills/x-posting-template/SKILL.md` multi-lane + graph-engineering intensity;
  full stack and root Signal Deck are **not** defaults on light member/clip posts
- Non-X: Signal Deck URL required in caption/description
- X Signal Deck: reply/bio/level-3 default (see x-posting-template)
- Always include: `https://loom-signal-deck.vercel.app/`
- X may omit a separate message line when the hook carries intent; IG/TT/YT require message
- **Subject frame** (content-kind line after message): required on CF or
  category/form-led work roots; category language only; screen-true; pair with
  subject/product-class tags; not a brand-official claim. Light X member stills
  may omit. See x-posting-template / reels-tiktok-template /
  idol-social-metadata-upload.
- Full image prompt (exactly one) and full video prompt: X process threads only
- Idol branding is integrated into each post; not a separate default campaign lane

Package structure follows the 90s+ master policy. `05-package.yaml` and package
outputs should distinguish:

```text
90s_plus_master
45s_cutdown
short_derivatives
platform_upload_packages
```

The 90s+ master is the source content unit. The 45s cutdown and shorts derive
from it or from the same source-clean recipe; they are not independent masters.
Register every master, cutdown, short, package, and platform draft package in
the title `output-registry.yaml`.

New packages use `idol_package.v2`. `production_graph_trace` binds the exact
run-root 04 edit-map path/SHA and canonical compiled recipe path/SHA, then maps
each 05 output to ordered Edit Segment ids plus the exact screen-progression
node and Section projection. Release projection and direct draft upload copy
that mapping into the queue, sidecar, upload log, and eventual public ledger
under the explicit `idol_release_provenance.v2` marker. Older package evidence
without that marker remains legacy evidence and cannot impersonate a complete
new trace.
A changed 04 byte, unknown segment, or partial trace holds. Founder approval is
still separately required for upload and publication, and analytics evidence
is append-only: it cannot mutate the package, recipe, or edit map.
The active package schema accepts v2 only. Historical v1 evidence remains
readable solely through `schemas/package-v1-legacy.schema.json` and cannot
enter release projection or upload as current authoring.

Validate package readiness with:

```text
scripts/idol-video-python scripts/validate_json_schema.py schemas/package.schema.json runs/ALBUM_KEY/TITLE_KEY/RUN_ID/05-package.yaml
```

Validate social plan readiness with:

```text
scripts/idol-video-python scripts/validate_publishing_plan.py runs/ALBUM_KEY/TITLE_KEY/RUN_ID/publishing-plan.md
```

`publishing-plan.md` remains the founder-readable plan, while
`schemas/publishing-plan.schema.json` is applied through the validator's
machine-readable extract. A plan that fails validation may still be a useful
draft, but automation must not treat it as ledger-ready.

Active and closed shapes are separate contracts:

```text
scripts/idol-video-python scripts/validate_publishing_plan.py RUN/publishing-plan.md --mode active
scripts/idol-video-python scripts/validate_publishing_plan.py RUN/publishing-plan.md --mode closed
```

The closed shape uses `schemas/publishing-record.schema.json` and is immutable
publication evidence. `--mode auto` may detect either shape, but release
projection must refuse a closed record instead of converting it back into an
active queue. A final master may be a local path or an observed platform URL/id
under `schemas/package.schema.json`; a URL does not prove publication unless
the publishing record or ledger records that fact.

After the Founder passes the master, post-05 work does not open or promote a
retired 01A board. Current-title member visuals were already bound through Front
Planning, while final-used visual and media bytes remain run-owned and are
registered through the active 05 package/final-delivery lineage. Post-05
automation may add pointer-only lookup or publication evidence, but it does not
copy a planning board into a new creative owner or overwrite member sources.

After posts are published or manually recorded:

```text
published URLs / post ids / metric rows
-> update platform ledgers
-> validate social ledgers
-> build a run-owned filtered `idol_social_evidence_snapshot.v3`
   (including the release output -> 04 graph evidence when present)
-> refresh catalog social-kit and cleanup/version log
-> write analytics-summary.md
-> prepare compact Social Pulse rows
-> founder-review production-direction candidates
```

The active snapshot schema accepts v3 only. Preserved v2 snapshots use
`schemas/social-evidence-snapshot-v2-legacy.schema.json` as a compatibility
reader; analytics producers never write that legacy contract.

Edit, package, manual-upload packages, platform draft logs, and social assets
must also register in the active title registry:

```text
catalog/albums/ALBUM_KEY/TITLE_SONG_KEY/output-registry.yaml
```

The local run folder remains the source path. The title registry is the lookup
index that keeps a track's downstream outputs together when editing,
packaging, and social work span multiple days.

External-action helpers are explicit-scope only:

```text
scripts/idol-video-python scripts/idol_social_release_sync.py \
  --run-root RUN --content-id ID --queue RUN/QUEUE.jsonl \
  --package-contract RUN/05-package.yaml \
  --package RUN/PACKAGE --publishing-plan RUN/publishing-plan.md \
  --registry catalog/albums/ALBUM/TITLE/output-registry.yaml \
  --projected-at ISO8601 [--apply]

scripts/idol-video-python scripts/idol_platform_draft_upload.py \
  --run-root RUN --content-id ID --queue RUN/QUEUE.jsonl \
  --package-contract RUN/05-package.yaml \
  --tracker RUN/exports/social/BATCH/TRACKER.md \
  --log RUN/exports/social/BATCH/UPLOAD.jsonl

scripts/idol-video-python scripts/idol_social_public_closeout.py \
  --closeout RUN/review/public-closeout-POST_ID.json [--apply]

scripts/idol-video-python scripts/idol_social_release_session.py register \
  --run-root RUN --queue RUN/QUEUE.jsonl \
  --registry catalog/albums/ALBUM/TITLE/output-registry.yaml [--apply]

scripts/idol-video-python scripts/idol_social_release_session.py refresh \
  --session RUN/review/social-release-session-v1.json [--apply]

scripts/idol-video-python scripts/idol_prepare_api_upload_video.py \
  --run-root RUN --content-id ID --source RUN/MASTER.mp4 \
  --output RUN/exports/social/BATCH/ID_2K30_API_UPLOAD.mp4 \
  --receipt RUN/exports/social/BATCH/ID_2K30_API_UPLOAD.receipt.yaml [--write]
```

The local projector performs no network action. It validates the owning
`05-package.yaml`, stages queue/package/plan/registry projections, validates the
staged set, then atomically replaces the live set with a run-owned recovery
journal. Apply mode cannot use `--skip-title-registry`; a release projection or
upload result must remain bound to the exact active title registry. Any approved
projection, and every upload `--apply`, additionally
requires the matching run-owned `--approval-artifact` and `--approval-sha256`.
The approval contract is `schemas/platform-release-approval.schema.json`; its
action, platform, post-id, exact package path/SHA/deliverable-manifest, and
asset-path/SHA scope is authoritative. Direct dry-run emits the package and
asset-linkage manifest with no network. Apply requires distinct protected input
and evidence paths plus an exact active-plan content owner, copies approved
bytes into content-addressed run-owned staging, and uploads only that snapshot.
Each outgoing media chunk is compared with a preflight byte manifest immediately
before its request. The automatic draft uploader supports TikTok, YouTube, and
YouTube Shorts; Instagram Reels remains a manual-package lane until an explicit
uploader implementation exists. Regular X public API publishing remains on the
dedicated hash-bound X adapter because X has no native draft object; mixed
queues are allowed, while explicit X/Instagram draft filters fail instead of
silently treating those rows as drafts.
The session builder also performs no network action. It stores exact source
bindings once, rejects ambiguous multi-queue discovery, excludes stale
approvals from current authority, observes local publication/Signal Deck/fixed
checkpoint facts, and emits only one next action. It never authors captions or
Founder approval. Eligible Signal Deck closeout still requires an existing MV
track or CF mapping and exact Web visual lineage; general member/process/social
content must not be falsely mapped into that schema, and Web deploy remains a
separate Founder-approved action.
Before a request it atomically fsyncs a started intent under
`exports/social/upload-attempts/` and records `upload_in_progress`; unresolved
started/unknown attempts block automatic retry. Approval, queue, package,
deliverable, asset, snapshot, and attempt digests stay in queue, tracker, and
attempt-log evidence. Neither helper may auto-select the global ledger, infer
approval from package status, or use Aurora V2 secret defaults.

Run `python3 scripts/idol_platform_auth_status.py` before apply. The status is
value-free. Use the platform browser recovery command when readiness is false:

```text
python3 scripts/idol_tiktok_oauth_reauth.py --open-browser
python3 scripts/idol_youtube_oauth_reauth.py --open-browser
python3 scripts/idol_x_oauth_reauth.py
```

TikTok reauth uses Desktop PKCE, requires `video.upload`, and stores
`tiktok.env` plus `tiktok-token.json` under `.runtime/secrets/` with mode
`0600`. When app credentials are missing, they are entered only on the local
setup page. Never paste or log token/client-secret values. Deterministic
pre-request credential failures are finalized as `failed` and are retryable;
only `started` or `unknown` attempts require reconciliation before retry.
For pre-review integrations, use the active Sandbox Desktop client, register
`http://127.0.0.1:8766/oauth2callback` exactly, add the posting account as a
Sandbox target user, and apply the Sandbox changes. The verified 2026-07-29
baseline is `uploaded_tiktok_inbox`, not a public-post result.

Post-upload social closeout:

- Use `skills/idol-social-metadata-upload/SKILL.md` after a platform upload,
  draft-upload attempt, or manual-post record has been logged.
- After the Founder makes a TikTok, YouTube/Shorts, or Instagram draft public,
  preserve the exact URL and actual `published_at` in a run-owned closeout
  conforming to `schemas/signal-deck-publication.schema.json`. Bind one existing
  queue row, exact visible member codes, one MV track or CF, and the final-used
  visual source/web paths and hashes.
- Dry-run then apply `scripts/idol_social_public_closeout.py`. One atomic local
  projection updates the global post ledger, the canonical Signal Deck
  publication registry, the existing title registry's remote publication, and
  a run-owned result. The web read model then exposes that publication on the
  exact member pages and matching track or CF page.
- The helper performs no upload, publish, schedule, metric API request,
  external sync, or Signal Deck deployment. Deployment remains a separate
  Founder-approved action.
- Keep one final X posting plan and one final section bank in the album/title
  catalog:
  `catalog/albums/ALBUM_KEY/TITLE_KEY/social-kit/x-posting-plan.md` and
  `catalog/albums/ALBUM_KEY/TITLE_KEY/social-kit/x-section-post-bank.yaml`.
- Record replaced draft/version files in
  `catalog/albums/ALBUM_KEY/TITLE_KEY/social-kit/version-log.md` instead of
  stacking many `vN` social-kit YAML/Markdown files.
- Delete only stale preview/scratch files after inventory and pointer updates.
  Do not delete final masters, source-clean renders, platform trackers, upload
  logs, ledger rows, registry entries, or catalog visual-board assets with
  preservation locks.
- The catalog social-kit is a lookup layer only. Actual uploaded videos, shorts,
  API logs, and QC evidence stay in the owning run folder.

Do not mirror post-package social upload folders into `drive-sync/`. The SNS
automation should inspect the current KST week of run-owned package/export
outputs, publishing plans, title registries, Social Pulse / analysis-sheet
status, and local ledgers, then tell the founder what still needs uploading or
checking. Drive sharing for social remains compact Social Pulse rows only.

Social analytics mapping:

```text
CONTENT_ID = content unit / 90s+ master
post_id = actual social post
template_type = legacy format label or expanded semantic root/derivative/member/process type
content_lane = exact platform lane retained from the approved posting template
content_family = normalized cross-platform analysis family derived without replacing content_lane
format_family = video, still, carousel, thread, poll, full_master, or unknown
shared_media_source_post_id = exact earlier post row whose approved media bytes are reused
message = message being tested
```

New X and mixed-platform rows preserve both the detailed lane and normalized
family. Historical `clip` rows without a lane remain `legacy_clip`; automation
must not backfill them into a new family by guessing. Run-owned v2 evidence
snapshots preserve all distinct fixed measurement windows and expose lane,
family, format, member, learning-field, and shared-media coverage to cohort and
dashboard consumers.

X analytics must use scheduler whitelist rows only. TikTok, YouTube, YouTube
Shorts, and Instagram Reels may use date-based matching when the title/caption
keeps a Track/clip label that can be matched back.

Global ledgers:

```text
analytics/records/platform-posts.jsonl
analytics/records/platform-metrics.jsonl
analytics/records/signal-deck-traffic.jsonl
analytics/records/tiktok-studio-imports.jsonl
analytics/records/tiktok-studio-account-daily.jsonl
analytics/records/tiktok-studio-video-snapshots.jsonl
analytics/out/daily-social-summary-YYYY-MM-DD.md
analytics/out/weekly-social-rollup-YYYY-MM-DD.md
```

Before a content-level analytics read, filter those ledgers into the owning
run instead of loading the full global files into prompt context:

```text
ruby scripts/idol_social_evidence_snapshot.rb RUN_ROOT --content-id ID --write
```

The snapshot records selected row digests and one of `no_post_records`,
`posts_without_published_facts`, `published_without_metrics`,
`published_partial_metrics`, or `measured`. A published fact requires
`published_at` plus a platform post id or HTTPS URL, and `measured` requires
metric coverage for every published fact. All other states are explicit
evidence gaps and must not be converted into complete performance claims.
The source ledgers validate before a staged snapshot atomically replaces the
previous run-owned file.
The default sources are the two canonical `analytics/records/` ledgers and the
run basename must equal the content id. A noncanonical ledger is accepted only
with an explicit `--ledger-override-reason`, which is retained in the snapshot.

The Signal Deck ledger is separate from content evidence: it stores only the
aggregate production visit count from Vercel Web Analytics. Its provider-default
window must not be called a daily/weekly figure or attributed to one post without
a separately approved attribution design. It stores no raw event, visitor,
session, cookie, or IP data.

The Founder-approved raw collector is
`scripts/idol_collect_platform_metrics.py`, governed by
`automation/loom-metric-collector-contract.yaml`. It selects only local ledger
rows already marked `published` when one uncaptured fixed checkpoint is due.
`T+1h` is local publication-fact verification; platform performance snapshots
are collected once at `T+24h`, `T+72h`, and `T+7d`. A completed, missed, or
not-yet-due checkpoint is excluded before authentication or any platform API
call. The rolling 28-day window is used only for weekly cohort/target
aggregation, never for daily per-post refresh. The collector writes only
validated aggregate snapshots and reports a missing public ID/OAuth
scope/configuration without changing the row. YouTube rows also preserve
provider-returned average view duration/percentage, estimated watch time,
subscriber and engaged-view fields, country and other useful aggregate
breakdowns, and the audience-retention curve when available. Each optional
dimension records its own populated/no-row/unsupported/request-failed state;
one unavailable breakdown never discards the base video row. YouTube's direct
single-pass completion rate is not exposed here, so `completion_rate` remains
null unless a direct provider field appears; average percentage viewed is not
renamed as completion. It has no Instagram API route; Instagram Insights
remains manually attached.

Exactly one scheduled automation owns that call: `idol-sns-management` at
09:30 KST. It calls the collector once before composing the founder SNS brief;
the retired `loom-read-only-metric-collector` must not remain enabled or be
recreated. The collector is the automation's only external API surface. OAuth
reauthorization is never attempted by the schedule: it reports a value-free
blocker for a controlled local browser recovery instead.

### Founder-provided TikTok Studio weekly export

TikTok Studio ZIP exports are a second, local evidence path. The Founder sends
the actual `Overview`, `Viewers`, and `Content` ZIPs on Sunday; no automation
downloads them, and no credential or TikTok API call is involved. First run a
dry validation, then apply the same exact paths:

```text
python3 scripts/idol_import_tiktok_studio_exports.py --dry-run --json \
  --input /path/to/Overview_*.zip \
  --input /path/to/Viewers_*.zip \
  --input /path/to/Content_*.zip

python3 scripts/idol_import_tiktok_studio_exports.py --apply --json \
  --input /path/to/Overview_*.zip \
  --input /path/to/Viewers_*.zip \
  --input /path/to/Content_*.zip
```

The importer hashes each ZIP and CSV member, accepts same-value overlap only,
and stops before local mutation on a conflicting daily row or video snapshot.
It keeps three distinct ledgers: the import receipt, daily account values, and
cumulative per-video Content snapshots. It does not copy the raw ZIPs into the
repository by default. Re-supplying an identical batch is a no-op.

`Content.csv` may update `platform-metrics.jsonl` only if its TikTok video ID
exactly matches an existing **published** `platform-posts.jsonl` row. It never
creates a post row or guesses a run/content mapping from a title. An unmatched
video stays usable for account-level analysis, but not as content-level Loom
performance evidence until a real publication fact is added.

The current CSV scope contains daily video/profile/reaction counts, new versus
returning viewer counts, and per-video cumulative views/likes/comments/shares.
It does not contain country, age/gender, traffic source, average watch time,
completion rate, or retention-curve data. Those dimensions are recorded as
`not_in_export`, not zero. A weekly cumulative Content snapshot is also not a
fixed `T+24h`, `T+72h`, or `T+7d` result and never replaces a due-time API
checkpoint. A separate per-video TikTok Studio detail screen can only be added
as manual evidence with its exact video ID and observation time.

Publishing, uploading, scheduling, and external API access require founder
approval.

For CF runs, every post-upload closeout also enters the SNS skill's
`CF final-only run closeout` gate. The run keeps one canonical final-delivery
root plus the final master/derivatives, final-used frames and boards, final
prompt/edit recipe, required CF contracts, Founder inputs and receipts, QC
evidence, and immutable upload/publication records. Hash-identical
`attach-media` staging copies and superseded reproducible candidates may be
collapsed only after current pointers are repaired, reverse references are
checked, and a hash-bound cleanup receipt maps every removed path to a surviving
canonical file.

An SNS upload or draft request alone prepares this cleanup and holds before
deletion. Physical cleanup requires the Founder's explicit current-task
instruction to finish, close, or clean the named CF run. This local cleanup gate
does not add upload, publish, schedule, sync, paid-generation, or public-release
authority, and it never deletes Founder-supplied sources, selected/passed media,
paid originals, required rollback evidence, trackers, ledgers, or API results.

Public platform drafts for TikTok, YouTube, YouTube Shorts, and Instagram Reels
must always carry these public hashtags in the queue row, caption/description
surface when the platform supports it, and platform tag list when the API
supports tags:

```text
#AI #AIIdol #Kpop #VirtualIdol #Loom
```

Run-specific tags such as `#Ink`, `#Harne`, member names, track form, or
**product-class / category** tags (CF eyewear, lipstick, fashion-film form,
etc.) may be added after the required set. **Do not** add real brand names,
retailer tags, or partnership tags unless the Founder explicitly locks a real
claim; category language only. The platform draft upload helper enforces the
required baseline set before calling external APIs so incomplete local queue
rows do not publish without the baseline public tags. After draft API upload,
the social owner hands the Founder the draft URL plus caption/tag paste list
for review; draft is not public release.

## Git Artifact Policy

Use git as local production ledger. Track files that change future decisions:

- root run contracts: `00`, `00A`, `01`, `02`, `02A`, `02B`, `03-review`,
  `04-edit-map`, `05-package`
- selected or durable research records
- final prompt packets
- passed `04FX-finishing-map-vN.yaml` files referenced by `04-edit-map.yaml`
- visual system decisions
- promoted creative-bank records
- schemas, skills, scripts, wiki, source materials, registries, and handoff
  contracts

Do not track routine execution byproducts unless founder asks to preserve them:

- `exports/**`
- `generations/**`
- generated boards, review images, contact sheets, FX preview clips, payloads,
  batch reports
- audio, video, render frames
- Drive sync copies
- derived `analytics/out/**` reports
- repeated prompt probes

Use `research/drafts/`, `research/probes/`, or `research/tmp/` for local-only
exploration.

## Automation Boundary

Automation may read run state, validate required files, execute repeatable
steps, and stop at gates. It must not invent review decisions, silently change
the creative nucleus, publish externally, upload, schedule, run paid generation,
or sync external platforms without founder approval.

For CF-code, automation may prepare CF00-CF70 artifacts under `cf/runs/` only
when required inputs exist. It must stop before external research unless
approved for the current task, before paid Grok/xAI generation, and before any
real brand public claim, upload, schedule, post, or platform sync.
