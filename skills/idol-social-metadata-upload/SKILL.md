---
name: idol-social-metadata-upload
description: |
  Check whether X, TikTok, YouTube/Shorts, or Instagram posting is ready; recover
  platform credentials without exposing values; prepare the common social queue,
  approved public/draft upload, and post-upload closeout. Use for “does posting
  work?”, OAuth/401/client_key failures, publishing-plan/platform-post queues,
  social metadata, API upload, draft upload, public post routing, or social-kit
  closeout after a master, short, clip, or CF is ready.
---

# IDOL Social Metadata Upload

Use this skill to keep public upload copy disciplined and reusable across Loom /
AURORA-M releases, and to run the local draft-upload path after Founder approval.

## Fast lookup

| Request | First source/action | Owning continuation |
| --- | --- | --- |
| “Do X/TikTok/YouTube work now?” | `wiki/platform-credential-and-draft-upload-ops.md` and `python3 scripts/idol_platform_auth_status.py` | Verify the latest platform-specific success artifact; do not infer public status from a draft |
| Credential/OAuth failure | The matching recovery section in the ops page | Re-run the value-free status before any apply |
| Multi-platform copy/queue | This skill's common queue contract | X copy → `x-posting-template`; TikTok/Instagram copy → `reels-tiktok-template`; YouTube stays here |
| Actual upload/post | Exact run-owned approval artifact and queue | X dedicated public adapter; TikTok/YouTube draft uploader; Instagram manual |
| Already attempted/uploaded | Run queue, tracker, log, and global ledger | Post-upload social closeout in this skill |
| Founder supplies a public URL | Exact run-owned queue row plus public timestamp, member/content, and visual mapping | Dry-run/apply `idol_social_public_closeout.py`; analytics, Signal Deck, and title registry close together |

## Required Reads

- Read `AGENTS.md` and `wiki/platform-credential-and-draft-upload-ops.md`.
- Read `wiki/social-automation-system.md` for approval, ledger, analytics,
  artifact, or automation-boundary work.
- Read `wiki/artifact-management-system.md` before creating catalog lookup files,
  deleting previews, collapsing versions, or writing cleanup logs.
- Read the current run `publishing-plan.md`, the selected asset path, and the latest metadata review or package file.
- Read `schemas/platform-release-approval.schema.json` before any external
  action and `schemas/publishing-record.schema.json` when a completed plan has
  become an immutable closeout record.
- Read `schemas/signal-deck-publication.schema.json` before authoring a public
  URL closeout or changing the Signal Deck member/track/CF publication mapping.
- For song/CF message and poetic hooks, read durable sources in order:
  brand-core locks under `business-marketing/brand-management/**` when group
  wording is needed; then run `00A-song-lock.yaml`, passed Front Planning,
  CF strategy locks, `research/selected-audio-analysis-*`, or a Founder source
  quote preserved in the current thread/run.
- For X thread craft (full prompts), read only
  `skills/x-posting-template/SKILL.md` (complete template; no extra ref files).
- For IG/TikTok caption shape, read only
  `skills/reels-tiktok-template/SKILL.md` (complete template; no extra ref files).

## Publish order (batch lock)

```text
1) X first (API / CF X schedule path)
2) TikTok + YouTube + YouTube Shorts (API draft uploader)
3) Instagram Reels (manual package only)
```

Non-X rows in a multi-platform batch should set `scheduled_after_x: true` and
`publish_order` > 1 unless Founder locks an exception.

## One Queue, Platform-Specific Execution

Use one run-owned `platform-posts*.jsonl` structure for X, Instagram Reels,
TikTok, YouTube, and YouTube Shorts. The common row is the metadata and evidence
contract; `delivery_mode` and `execution_lane` select the adapter:

| Platform | `delivery_mode` | `execution_lane` | Execution result |
| --- | --- | --- | --- |
| X | `public_api_post` | `x_hash_bound_public_adapter` | Public URL/id only after the dedicated X adapter succeeds |
| TikTok | `platform_draft` | `tiktok_inbox_api` | `uploaded_tiktok_inbox`; user completes editing/posting in TikTok |
| YouTube | `platform_draft` | `youtube_private_api` | Private Studio draft |
| YouTube Shorts | `platform_draft` | `youtube_shorts_private_api` | Private Studio draft |
| Instagram Reels | `manual_upload_package` | `instagram_manual` | Manual package/checklist; no API-success claim |

The default `idol_platform_draft_upload.py` selection reads a mixed queue but
executes only TikTok and YouTube/Shorts `platform_draft` rows. An explicit X or
Instagram filter is rejected with the correct route instead of silently
misclassifying it as a draft. Do not invent an Instagram API adapter: there is
no repository success record for one.

This skill is the central YouTube/Shorts release owner; do not create a separate
YouTube template skill merely to duplicate this contract.

## Fixed public constants

```text
SIGNAL_DECK_URL = https://loom-signal-deck.vercel.app/

AI_MADE =
AI-made with Grok and GPT.

STACK_SHORT =
GPT image → Grok Imagine → Grok Build

STACK_FULL =
AI-made with Grok and GPT.
Planned with Grok.
Boards / stills: GPT image.
Video: Grok Imagine.
Edit + graph-engineering routing: Grok Build.
Loom production graph engineering.
```

Always place `AI-made with Grok and GPT.` in public copy.
Signal Deck URL: required on TikTok / YouTube / Shorts / Instagram package
captions. On **X**, follow `skills/x-posting-template/SKILL.md` — default is
**reply/bio/level-3**, not every root, per the active X operating lock.

The older compact stack `Grok plan → GPT image → Grok Imagine → edit on Grok
Build.` may remain on an already locked row. New Non-X rows prefer
`GPT image → Grok Imagine → Grok Build`.

## Copy structure by platform

### Non-X (TikTok, YouTube, YouTube Shorts, Instagram package)

Always structure upload copy in this order, **English only**:

1. **Poetic message / receive line** from brand-core or run-locked message
   (required).
2. **Subject frame** — one content-kind line after the message when the clip is
   CF or otherwise category/form-led (required then; recommended on derived
   clips that still read as that category). Genre, product class, occasion,
   form, or mood in **category language only**, grounded in what the screen
   shows. Not a brand-official claim. Example shape:
   `Battle-royale mood game film — drop energy, no official tie-in.`
3. Short description: track, visible members, what the video shows, and whether
   it is a work root or a distinct 3–8s derived clip/hook loop (may merge with
   subject_frame when one line already covers it — do not double-say).
4. **Member intro line** when a named member is meaningfully on screen:
   `{Member} — what they are doing now`, sourced from the brand card or
   run-locked visible action.
5. **Claim guard** on spec CF when a real brand is visually readable.
6. **AI-made disclosure** (`AI_MADE` = `AI-made with Grok and GPT.`).
7. **Short production stack** (`STACK_SHORT`, or the older compact equivalent
   only when already locked).
8. **Signal Deck URL**.
9. Hashtag block / platform tags (subject/product-class tags must match
   subject_frame words).

Tone: poetic and elevated for message/idol lines; subject_frame stays plain and
searchable; stack lines stay clear. Do not invent slogans that are not grounded
in locked planning docs.

Non-X does not inherit X intensity 0: message, disclosure, short stack, and
Signal Deck stay required. Keep production credit compact; do not turn every
caption into a process essay.

### Non-X short-form inventory

- `work_root`: approved CF final or MV cutdown anchoring one work.
- `derived_clip` / `hook_loop`: a distinct **3–8s** member, action, object,
  world, or loop beat from the same work.
- `member_still` / `member_carousel`: Instagram-primary; image-only is not the
  TikTok/YouTube Shorts default.

Plan one work as **one work root plus 2–4 distinct derived clips over later
days** when the approved media supports it. TikTok and YouTube Shorts use the
same video-first bank. The exact approved media bytes may also come from an X
derived row, but every platform receives a re-targeted caption/description.
Caption cloning is forbidden.

About 1–2 TikTok/Shorts clips per day is a local planning heuristic, not a
platform guarantee. Do not add image filler to match the X cadence.

### X

Follow `skills/x-posting-template/SKILL.md` completely (multi-lane; not every
post is a process thread):

- Types: work_root, derived_clip, member_still/clip, craft_gift, harness_proof.
- Member-led posts need a one-line **“doing now”** intro.
- CF/category-led work roots need **subject_frame** after message (see
  x-posting-template); light member stills may omit it.
- Graph Engineering intensity 0–3; level 0–1 omit full stack and root Signal Deck.
- Required disclosure: `AI-made with Grok and GPT.`
- Product magnets: GPT image, Grok Imagine, Grok Build; optional Codex on 2–3.
- Full remixable prompts only on craft_gift / process threads — not internal board locks.
- Prefer publishing X before other platforms in the batch.

## Message rules

- Preserve the locked message meaning; restate **poetically** in English without
  changing the promise.
- Translate Korean founder wording into elevated English for public text.
- Keep the message short enough to read before the fold.
- If founder phrase and canonical run message agree, combine carefully; do not
  replace founder intent with a prettier unrelated metaphor.
- Record `copy_source_refs` on the plan/queue row when known.

## Subject frame (body line — all platforms)

`subject_frame` names **what kind of content** the post is, after the message:

| Field | Role |
| --- | --- |
| `message_line` | What the viewer should receive (promise / temperature / thesis) |
| `subject_frame` | Genre, form, product class, occasion, or mood — screen-true category language |

Rules:

1. **Required** on CF or category/form-led work roots (all platforms that carry
   that root). **Recommended** on derived clips that still read as the category.
2. One English line. Prefer plain searchable wording over poetry.
3. Ground only in approved media or the run’s CF subject / track-form lock.
4. Category language only — never invent an official brand partnership. Spec CF
   still uses the separate claim-guard line when a real brand is readable.
5. Mirror the same words into subject/product-class **hashtags** on Non-X (and
   light X tags when used).

## Platform defaults

- Public group name: `Loom`.
- Internal/project tag: `AURORA-M` (YouTube tags/keywords when useful).
- Hashtag-safe public form: `#AURORAM` only as optional internal echo — prefer
  public `#Loom`.
- Baseline public hashtags for TikTok / YouTube / YouTube Shorts / Reels queues:
  `#AI #AIIdol #Kpop #VirtualIdol #Loom`.
- Add track, member, `#Harne`, `#AIMusic`, `#AIMV`, `#AIKpop` when relevant.
- Members on screen must be namable in metadata when public names exist.

## Subject / product tags (CF + MV — common)

This skill is the **shared** post-05 SNS owner for both **MV/music clips** and
**CF commercials**. Do not invent a CF-only upload skill for tags or draft
routing.

Subject framing is **two layers**: (1) caption `subject_frame` body line, then
(2) matching hashtags. Tags alone do not replace the body line on
category-led CF/MV work roots.

After baseline Loom/AI tags, every TT / YT / Shorts / IG queue row must also
carry **subject-true discovery tags** when the clip has a clear advertised
subject, track form, or visible category:

| Lane | Add (examples of *kind*, not fixed list) | Never add |
| --- | --- | --- |
| **CF** | Product **class / category / occasion / material / use** grounded in CF locks (e.g. eyewear, lipstick, morning routine, fashion film) | Real **brand** names, retailer handles, official campaign tags, partnership/endorsement tags, or anything that reads as an official brand ad |
| **MV / music** | Track title, form, genre/mood, member when on screen (`#AIMV`, `#AIMusic`, title/member) | Fake collab brands, trend spam (`#fyp` / `#viral` defaults), unrelated product tags |

Rules:

1. Prefer **category language**, not brand language. A Gentle Monster–style
   eyewear *study* may use `#eyewear` / `#fashionfilm` — never the brand name
   as a tag unless the Founder explicitly locks a real partnership claim.
2. Spec / portfolio CF copy already says “not an official brand campaign”;
   tags must not undo that by implying brand ownership.
3. Pull product-class words from the run’s CF subject brief, product lane, or
   visible on-screen object — not from free invention. Reuse those words in
   `subject_frame` and in `hashtags`.
4. Record `subject_frame` and subject tags in the queue **before** draft upload
   so Founder review and TT paste-back use the same list.
5. Keep total tags lean (baseline + a few subject/track/member tags). Do not
   flood.

## YouTube Shorts

- Use the **same video-first clip bank as TikTok**: one work root plus 2–4
  distinct 3–8s derived clips or hook loops over later days when available.
- The same approved media bytes may be shared with an X derived row, but the
  Shorts description must be re-targeted rather than copied from X or TikTok.
- Description is slightly fuller than TikTok: message → **subject_frame** when
  CF/category-led → track/work and visible action → member “doing now” line when
  member-led → claim guard if needed → AI-made disclosure →
  `GPT image → Grok Imagine → Grok Build` → Signal Deck → tags matching
  subject_frame.
- Image-only is not the Shorts default; do not add still filler to meet an X
  posting cadence.
- Do not paste full image/video prompts (those belong only on public-remixable
  X craft/process lanes).
- Keep this skill as the YouTube/Shorts copy owner; do not create a separate
  YouTube template skill.

## Upload Boundary

- Founder approval is required before any platform API upload, schedule, public publish, or external sync.
- Approval must be a run-owned schema-valid artifact bound to the exact
  run/content scope, canonical action-bearing queue SHA-256, approved post ids,
  exact run-root `05-package.yaml` path/SHA-256 and deliverable-manifest digest,
  and each approved asset path/SHA-256. The live helper revalidates package
  schema, content ownership, deliverable linkage, and asset bytes. A CLI flag,
  package status, old approval note, or global ledger row is not approval.
- Active post-05 rows exact-carry the v2 package production-graph digest and
  the selected output's ordered Edit Segment ids, screen-progression node ids,
  and Section ids under `release_provenance_version: idol_release_provenance.v2`.
  The uploader preserves the same fields in queue and log;
  any partial or stale trace is a HOLD before network access. These evidence
  fields cannot promote, revise, or overwrite 05/04 creative truth.
- Upload helpers create draft/private surfaces only unless the founder explicitly approves public publish.
- TikTok inbox upload may not prefill the caption through the current API path. Still record the exact caption and tags in the queue, tracker, and final report so the founder can paste them at publish time.
- The approval artifact is the stable run-owned
  `review/platform-release-approval-vN.yaml|json`; its exact bytes and SHA-256
  are CLI inputs. A CF70/04FX skill receipt is not a platform authorization.

## API Video Quality Lock

Every video sent through the X, TikTok, YouTube, or YouTube Shorts API must pass
`idol_api_upload_2k30_high_quality.v1` before any network request: long edge at
least 2560, short edge at least 1440, exact CFR 30fps, progressive H.264
`yuv420p`, and AAC audio at 48kHz / at least 256kbps. TikTok/YouTube/Shorts API
rows additionally bind the run-owned `idol_api_upload_video.v1` receipt in both
`api_upload_quality_profile` and `api_upload_quality_receipt`.

Prepare that local asset before Founder approval with
`scripts/idol_prepare_api_upload_video.py`. Already-compliant bytes are copied
without recompression; a lower-resolution or non-30fps source uses a
no-downscale Lanczos, CRF14/preset-slow, AAC320k local derivative. This may
prevent avoidable delivery loss but cannot recover detail absent from the
source. The uploader sends only the exact approved, content-addressed bytes and
never silently transcodes, substitutes, or lowers quality. Preparation and its
receipt perform no upload and grant no external or public-release authority.

## Credential Preflight And Recovery

Run the value-free status command before any apply:

```bash
python3 scripts/idol_platform_auth_status.py
```

Recovery commands:

```bash
python3 scripts/idol_tiktok_oauth_reauth.py --open-browser
python3 scripts/idol_youtube_oauth_reauth.py --open-browser
python3 scripts/idol_x_oauth_reauth.py
```

TikTok Desktop reauth writes `tiktok.env` and `tiktok-token.json` locally with
mode `0600`, requires the `video.upload` scope, and never prints token values.
If the TikTok client files are missing, enter the existing app client key and
secret only in the local browser setup page. For a pre-review test app, use the
active Sandbox Credentials (not App ID or Production Draft credentials),
add the Desktop platform, register the account as a Sandbox target user, and
apply the Sandbox changes. Production status `Draft` is not the Sandbox test
environment.
Never paste values into chat. The uploader persists rotated TikTok/YouTube
access and refresh tokens atomically.

The apply preflight stops before it creates an upload attempt when required
credentials are missing. A deterministic pre-request credential/refresh
failure is finalized as `failed` and may be retried with `--retry-failed`.
Only a `started` or `unknown` attempt blocks automatic retry until reconciled.

Current success anchors for route selection (not standing publication claims):

- X: 2026-07-28 dedicated public adapter, root plus three replies completed.
- TikTok: 2026-07-29 Sandbox Desktop OAuth and
  `uploaded_tiktok_inbox` row
  `CF_COSMETIC_TARGET_DISCOVERY_001-TT-20260728-001` in
  `analytics/records/platform-posts.jsonl`.
- YouTube Shorts: 2026-07-29 private Studio draft `rxwn61IROQc`.
- Instagram Reels: no repository API-success evidence; manual package only.

## Local Workflow

1. Update or create the run-owned metadata review file.
2. Prepare every API-bound video with the 2K/30fps quality helper, then create a
   run-owned `platform-posts-*.jsonl` queue bound to that exact output and
   receipt. Prefer **X rows first** in the batch documentation; execute X before
   TT/YT when applying multi-platform release.
3. Project the local release surfaces with
   `scripts/idol_social_release_sync.py`, explicit `--run-root`, `--content-id`,
   run-owned queue/package paths, and the owning
   `--package-contract RUN/05-package.yaml`. The projector stages and validates queue, plan,
   package, and registry outputs before atomic replacement and writes a
   recovery journal; it performs no network action. Apply mode may not use
   `--skip-title-registry`: release state must remain one atomic projection.
4. Use `scripts/idol_platform_draft_upload.py` with explicit `--run-root`,
   `--content-id`, `--package-contract RUN/05-package.yaml`, and run-owned
   `--queue`, `--tracker`, and `--log` paths. Dry-run is local and prints the
   package/deliverable/asset-linkage manifest. `--apply` additionally requires
   the exact `--approval-artifact` and `--approval-sha256`; only its approved
   actions, platforms, post ids, package bytes, and byte-identical assets may
   run. Before a request, the uploader writes and fsyncs a run-owned started
   intent, marks the queue row `upload_in_progress`, and uploads only a
   content-addressed run-owned snapshot whose request chunks are checked
   against a preflight byte manifest immediately before transmission. Apply
   mode may not skip the exact active title registry. The automatic uploader
   supports TikTok, YouTube, and YouTube Shorts. X uses its dedicated public
   adapter and Instagram Reels uses the manual release-package lane. A mixed
   common queue is valid because each row declares its execution lane. Never
   auto-retry while a started or unknown intent remains unresolved. Preserve
   the stamped approval, queue, package-contract, production-graph, snapshot,
   attempt, and asset digests in queue/tracker/log.
5. Register or append successful rows to the global social ledger when appropriate.
6. Update `publishing-plan.md`, package/registry pointers, and the upload tracker with the resulting YouTube Studio URL or TikTok inbox marker.
7. **Founder draft-review handoff (mandatory after API draft upload)** — most
   TT/YT/Shorts rows land as inbox/private drafts. Immediately after a
   successful draft upload, guide the Founder to review **before** public
   publish. Do not treat draft upload as “done shipping.” Hand off:
   - platform draft/inbox/Studio URLs or markers from the tracker
   - exact caption/description already used or ready to paste
   - full `hashtags` list: baseline + **subject/product-class tags** (no brand
     tags) + track/member when relevant
   - note that TikTok may not prefill caption/tags — paste at publish time
   - reminder: public publish / schedule still needs separate Founder approval
8. After API upload or upload attempt logging is complete, run the post-upload social closeout below.
9. When the Founder makes the draft public and supplies its URL, author the
   exact run-owned public-closeout input and use the local public-closeout
   helper below. Signal Deck deployment remains a separate approved action.

Use `scripts/validate_publishing_plan.py` when changing structured publishing-plan sections. Preserve existing unrelated worktree changes.
Use `--mode active` while it is a plan and `--mode closed` after it becomes an
immutable publication record; `--mode auto` may detect the shape. Never push a
closed record back through active release projection.

For analytics handoff, create a run-owned compact snapshot with
`ruby scripts/idol_social_evidence_snapshot.rb RUN_ROOT --content-id ID --write`.
Its no-post, not-published, and no-metrics states are evidence states, not
performance conclusions.

## Queue row fields (recommended)

```yaml
post_id:
content_id:
platform: x | tiktok | youtube | youtube_shorts | instagram_reels
delivery_mode: public_api_post | platform_draft | manual_upload_package
execution_lane: x_hash_bound_public_adapter | tiktok_inbox_api | youtube_private_api | youtube_shorts_private_api | instagram_manual
draft_status: not_uploaded | upload_in_progress | uploaded_tiktok_inbox | uploaded_private_draft | failed_api_upload
publish_order: 1
scheduled_after_x: false
content_lane: work_root | derived_clip_3_8 | hook_loop_3_8 | member_focus_3_8 | member_still | member_carousel | cf_hook_3_8 | mv_highlight
member: []
member_intro_line:       # recommended; required when a named member leads any platform row
track_or_cf:
poetic_hook:
message_line:           # required except optional on x
subject_frame:          # required CF/category-led work roots; recommended matching derived clips
ai_made_line: "AI-made with Grok and GPT."
stack_line: "GPT image → Grok Imagine → Grok Build"
copy_source_refs: []
signal_deck_url: "https://loom-signal-deck.vercel.app/"
signal_deck_on_root: false | true  # x only; default false per x-posting-template
harness_intensity: 0 | 1 | 2 | 3   # x only
shared_media_source_post_id:       # optional source row id; media reuse only, no caption clone
image_full_prompt_count: 0 | 1   # x only
video_full_prompt: false | true  # x only
caption_or_description:
hashtags: []
asset_or_clip:
api_upload_quality_profile: idol_api_upload_2k30_high_quality.v1 # every API video
api_upload_quality_receipt:  # exact automatic-draft idol_api_upload_video.v1 receipt
signal_deck_member_visibility: visible | none
signal_deck_member_codes: []  # exact visible members only
signal_deck_track_id:         # MV only
signal_deck_cf_id:            # CF only
signal_deck_visual_sources: [] # final-used source/web paths and SHA-256
```

## Post-Upload Social Closeout

Run this only after the relevant platform API upload, draft creation, upload
attempt, or manual-post record has been written to the run-owned tracker or
ledger. Do not use this closeout as approval to upload, publish, schedule, or
sync externally.

### Public embed and analytics registration timing

Register a post in `analytics/records/platform-posts.jsonl` **immediately when
the public publication fact becomes locally available**, not when the next
metrics automation happens. This closeout belongs in the same operation that
adds the public item to Loom Signal Deck or records its public share URL.

A Signal Deck embed may close the publication fact only when all of these map
to exactly one run-owned queue row:

- public platform and HTTPS share URL;
- platform post/video ID extracted from that URL;
- actual `published_at` timestamp;
- the queue row's `post_id`, caption, tracking code, and run-owned asset path.

Then upsert that same `post_id` into the global ledger as `published`, preserving
the queue copy and evidence while adding `platform_post_id`, `published_url`,
and `published_at`. Register the HTTPS share URL as `remote_publication` in an
existing owning output registry when that run has one. Deduplicate by both
`post_id` and `(platform, platform_post_id)`; a second embed, rerender, or
automation pass must not create another published row.

A private Studio draft, TikTok inbox marker, guessed title match, or embed URL
without a public publication timestamp is not enough. Keep it planned/draft and
ask for the public URL, post ID, or timestamp instead of guessing.

For TikTok, YouTube, YouTube Shorts, and Instagram Reels, close those facts as
one deterministic local projection:

1. Preserve the Founder's exact public URL and actual `published_at` in a
   run-owned JSON file conforming to the `public_closeout` definition in
   `schemas/signal-deck-publication.schema.json`.
2. Map it to one existing queue row, the exact MV `track_id` or CF `cf_id`, only
   the members visibly present, and at least one final-used visual. Record both
   the source and web paths with SHA-256. Do not infer a member, track, CF, or
   image from titles, filenames, or platform thumbnails.
3. Run the read-only preflight, then apply only after it passes:

```bash
scripts/idol-video-python scripts/idol_social_public_closeout.py \
  --closeout RUN/review/public-closeout-POST_ID.json

scripts/idol-video-python scripts/idol_social_public_closeout.py \
  --closeout RUN/review/public-closeout-POST_ID.json --apply
```

The apply atomically upserts the same publication into
`analytics/records/platform-posts.jsonl`,
`web/data/signalDeckPublications.json`, and the existing title output
registry's `remote_publication`, then writes a run-owned result. The Signal Deck
read model projects it to every exact visible member's Social Proof and Track
Cuts, plus the matching track page or CF page. It returns the fixed T+24h,
T+72h, and T+7d due times, but performs no metric API call, upload, publish,
schedule, external sync, or deployment.

After registration, T+1h is local publication-fact verification only and makes
no performance API call. The metric collector remains the sole external
read-only executor and selects only one uncaptured due checkpoint per post:
`T+24h`, `T+72h`, and `T+7d`. It skips completed, missed, and not-yet-due
checkpoints before authentication, so a growing Signal Deck does not cause
daily re-querying or refresh historical snapshots.

1. Refresh the album/title social lookup folder only as a compact index:
   `catalog/albums/ALBUM_KEY/TITLE_KEY/social-kit/`.
2. Keep actual masters, shorts, upload logs, trackers, and API artifacts in the
   owning run folder. Catalog files should point to those paths.
3. For X section posting, keep one final founder-readable plan and one final
   structured section bank:
   - `social-kit/x-posting-plan.md`
   - `social-kit/x-section-post-bank.yaml`
4. Do not keep stacked social-kit `vN` YAML/Markdown files after selection.
   Record the delta in `social-kit/version-log.md`, then remove superseded draft
   files when no README, registry, publishing plan, ledger, or tracker still
   references them.
5. Delete only stale preview/scratch files after inventory. Never delete
   run-owned final masters, source-clean renders, published/upload trackers,
   title-registry rows, or catalog visual boards with preservation locks.
6. Update `output-registry.yaml`, social-kit README, and any current handoff or
   publishing-plan pointer from old `vN` filenames to the final filenames.
7. Validate YAML syntax for changed registry/section-bank files and note any
   broader pre-existing schema incompatibility instead of hiding it.

### CF final-only run closeout

Whenever this skill closes a CF run after a social upload, draft, upload
attempt, or manual-post record, it must also route that run through the
final-only cleanup gate below. The same gate applies when the Founder explicitly
asks to finish, close, or clean a CF run while invoking this skill.

1. Inventory the run and hash every proposed keep/delete target. Name one
   canonical final-delivery root inside the owning run before removing anything.
2. Keep the final master and derivatives, final-used keyframes/storyboards,
   final prompt and edit recipe, required CF stage contracts, Founder inputs and
   intervention receipts, QC evidence, skill receipts, and every immutable
   upload/publication tracker or API result.
3. Repair current boards, registries, handoffs, and social pointers so they
   resolve to the canonical final-delivery files. A top-level `finals/` shelf is
   optional and must remain an explicit pointer or hash-identical user-facing
   mirror, never a second canonical owner.
4. After the immutable upload/result record exists, collapse hash-identical
   social `attach-media` staging copies back to their canonical final-delivery
   files. Remove superseded reproducible candidates and repeated final-package
   mirrors only when their replacement paths and hashes are recorded.
5. Reverse-reference every proposed deletion across README files, registries,
   boards, handoffs, queues, ledgers, trackers, and result records. Historical
   immutable records may retain their original staging path only when the
   cleanup receipt maps that path and hash to the surviving canonical file.
6. Write a hash-bound cleanup plan. Physical deletion requires an explicit
   current-task Founder instruction to close or clean that CF run; a plain
   upload or SNS-skill invocation prepares the plan and holds at the deletion
   gate.
7. Delete only the approved plan, then write a run-owned cleanup receipt with
   kept paths and hashes, removed paths and hashes, reclaimed bytes,
   reverse-reference findings, and any intentionally preserved duplicate.
8. Revalidate every current path, final hash, changed YAML file, registry
   pointer, and publication record after cleanup.

Never delete Founder-supplied source or reference material, selected/passed
media, paid originals, required rollback evidence, publication evidence,
trackers, ledgers, or API result logs. This gate manages local CF artifacts
only; it does not grant upload, publish, schedule, sync, paid generation, or
public-release authority.

The closeout log should read like a release engineer's log: what final file
remains, which draft/version was collapsed, what changed, what was deleted or
kept, and which paths are protected.

## Quality check (metadata)

- [ ] English only
- [ ] Non-X: message required, poetic, from locked sources
- [ ] CF/category-led work roots: **subject_frame** present (screen-true category language)
- [ ] Member-led rows include a sourced plain English “doing now” line
- [ ] `AI-made with Grok and GPT.` present
- [ ] Non-X: short stack present; new rows prefer `GPT image → Grok Imagine → Grok Build`
- [ ] Non-X: Signal Deck URL present; X: Signal Deck per x-posting-template intensity
- [ ] TikTok/Shorts rows use the video-first work-root + derived 3–8s clip bank
- [ ] Shared X media, if any, has platform-retargeted copy rather than a cloned caption
- [ ] Members/track tags when relevant
- [ ] **Subject/product-class tags present when CF or category-led clip** (category only — **no brand tags**); tags match subject_frame
- [ ] Spec CF does not use brand/retailer/partnership tags
- [ ] X-first order respected for the batch
- [ ] Full prompts only on X craft/process lanes per x-posting-template
- [ ] Baseline hashtags on TT/YT/Shorts queues
- [ ] Every API video is exact 2K-or-higher CFR30 and binds its quality receipt
- [ ] After draft API upload: Founder handed draft URL + caption + tag paste list
