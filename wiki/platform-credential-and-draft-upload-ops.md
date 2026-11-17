# Platform credential and social delivery ops

**Owner root:** `creative/IDOL/`
**Last updated:** 2026-08-02
**Purpose:** Single operational index for value-safe X, TikTok, YouTube/Shorts,
and Instagram release routing. This file contains names, paths, commands, and
evidence only. It contains no credential values.

## Start here

Use this page first when the request mentions social posting, platform API,
credentials, OAuth, `401`, `client_key`, TikTok Draft, YouTube Draft, or asks
whether X/TikTok/YouTube currently work.

1. Run the value-free health check in section 1.
2. Use `skills/idol-social-metadata-upload/SKILL.md` for the common queue,
   Founder approval, platform routing, execution, and closeout.
3. Load `skills/x-posting-template/SKILL.md` only for X copy, or
   `skills/reels-tiktok-template/SKILL.md` only for TikTok/Instagram copy.
4. Use `wiki/social-automation-system.md` when the task needs the detailed
   approval, ledger, analytics, or artifact policy.

Do not search for a separate YouTube posting skill. YouTube and YouTube Shorts
are owned by `idol-social-metadata-upload`.

## 0. Canonical local paths

```text
IDOL_ROOT =
/Users/yuminseog/aheyabaraya_hq_root/hq-control/creative/IDOL

SECRETS =
$IDOL_ROOT/.runtime/secrets/
```

| Platform | Local files | Field names only |
| --- | --- | --- |
| X | `x.env` | `X_OAUTH2_CLIENT_ID`, `X_OAUTH2_CLIENT_SECRET`, `X_OAUTH2_ACCESS_TOKEN`, `X_OAUTH2_REFRESH_TOKEN`, `X_OAUTH2_REDIRECT_URI`, `X_OAUTH2_SCOPES` |
| TikTok | `tiktok.env`, `tiktok-token.json` | env: `TIKTOK_CLIENT_KEY`, `TIKTOK_CLIENT_SECRET`, `TIKTOK_REDIRECT_URI`, `TIKTOK_SCOPES`; token: `access_token`, `refresh_token`, `scope` |
| YouTube / Shorts | `youtube-client-secret.json`, `youtube-token.json` | client: `installed`/`web` → `client_id`, `client_secret`; token: `access_token`, `refresh_token` |
| Instagram Reels | no API credential contract | manual release package only |

### Portfolio mirror (Content Learning / non-runtime)

Portfolio keeps a dated Desktop OAuth client under
`/Users/yuminseog/portfolio/secrets/` (gitignored). Naming:

- `youtube-oauth-desktop-YYYY-MM-DD.json` — on-disk file **without** `client_id`
- `youtube-oauth-desktop-YYYY-MM-DD.client-id` — sidecar holding `client_id` only

Runtime merge for portfolio scripts lands under
`portfolio/.tmp/content-learning-metrics/` (also gitignored). This does **not**
replace IDOL `.runtime/secrets/youtube-client-secret.json`. IDOL collectors still
read only the IDOL paths above.

Studio analytics backfill note (2026-08-02):
`analytics/out/youtube-studio-backfill-2026-08-02.md`
(appends optional `platform-metrics.jsonl` rows with
`snapshot_id=PORTFOLIO_YOUTUBE_STUDIO_BACKFILL_20260802`; does not rewrite
T+24h/T+72h/T+7d checkpoints).

Relevant implementation:

- `scripts/lib/idol_platform_credentials.py`
- `scripts/idol_platform_auth_status.py`
- `scripts/idol_tiktok_oauth_reauth.py`
- `scripts/idol_youtube_oauth_reauth.py`
- `scripts/idol_x_oauth_reauth.py`
- `scripts/idol_platform_draft_upload.py`
- `scripts/idol_prepare_api_upload_video.py`

### API video quality floor

Before an API video row enters Founder approval, prepare and bind
`idol_api_upload_2k30_high_quality.v1`. The local helper preserves compliant
bytes without recompression; otherwise it makes a no-downscale, Lanczos,
CRF14/preset-slow H.264/AAC320k derivative at exact CFR30. The outgoing file
must have a long edge of at least 2560 and a short edge of at least 1440.

Both automatic draft uploads and X `tweet_video` execution probe the exact live
bytes again before network access. TikTok/YouTube/Shorts rows must carry the
run-owned `idol_api_upload_video.v1` receipt; a low-resolution, 24fps, VFR,
missing/stale receipt, or altered file is a pre-request hold. The X adapter
re-probes its already hash-bound approved asset. Neither uploader creates a
cheaper derivative or transcodes during upload.

## 1. Value-free health check

```bash
cd /Users/yuminseog/aheyabaraya_hq_root/hq-control/creative/IDOL
python3 scripts/idol_platform_auth_status.py
```

Read only these booleans:

| Platform | Runtime | Recovery |
| --- | --- | --- |
| X | `ready_for_runtime_post`, `ready_for_runtime_metrics` | `ready_for_reauth`, `ready_for_refresh` |
| TikTok | `ready_for_runtime_upload`, `ready_for_runtime_metrics` | `setup_required`, `ready_for_reauth`, `ready_for_refresh`, configured/granted `video.upload` and `video.list` |
| YouTube | `ready_for_runtime_upload`, `ready_for_runtime_metrics` | `ready_for_refresh`, granted account-read and Analytics scopes |

2026-07-29 local state:

| Platform | State | Evidence |
| --- | --- | --- |
| X | ready; live adapter already recovered | 2026-07-28 root plus three replies completed |
| TikTok | ready; Sandbox Desktop OAuth recovered | 2026-07-29 inbox draft completed |
| YouTube | ready | 2026-07-29 Shorts private draft completed |
| Instagram | manual only | no repository API-success evidence |

### 1.1 One scheduled owner

`idol-sns-management` is the sole active daily SNS automation. At 09:30 KST it
runs `scripts/idol_collect_platform_metrics.py --apply --json` exactly once,
then writes the normal founder-facing SNS brief from local state. The former
`loom-read-only-metric-collector` cron is retired. Do not create a second
metric-only cron or manually repeat the collector in the same scheduled pass.

The metric runner is the sole external-API executor inside that automation. It
may read aggregate X, TikTok, YouTube/Shorts, and Vercel metrics only; it may
not publish, upload, schedule, change copy, or open an OAuth browser. Failed
refreshes become a value-free readiness blocker for the founder, not a second
automatic authorization attempt.

## 2. Browser reauthorization

Never paste a client secret, token, authorization code, or refresh token into
chat. Never print or commit `.runtime/secrets/`.

### 2.1 TikTok

```bash
python3 scripts/idol_tiktok_oauth_reauth.py --open-browser
```

The script uses TikTok Desktop Login Kit PKCE. Default callback:

```text
http://127.0.0.1:8766/oauth2callback
```

If the local TikTok client files are missing, the script opens a localhost
setup page. In the existing TikTok developer app:

1. do not confuse a **Production Draft** with a Sandbox: a Production Draft is
   not the restricted test environment;
2. if the integration is pre-review, switch the app page to **Sandbox** and
   select the exact Sandbox that previously handled draft uploads, or create/
   clone one if none exists;
3. use that Sandbox's **Credentials → Client key/Client secret**, not App ID or
   the Production Draft credentials;
4. add **Desktop** under Sandbox App details → Platforms; a Web/Android/iOS-only
   client is the wrong application type for this localhost Desktop flow;
5. add the posting TikTok account under Sandbox **Target users** and apply the
   changes (TikTok notes that propagation may take up to one hour);
6. enable Desktop Login Kit and Content Posting API;
7. make `video.upload` available to the app/user;
8. register the exact callback above;
9. enter the client key and client secret only in the localhost form.

Sandbox is valid for restricted integration testing without production review,
but it does not authorize public-video claims. This runner uses Upload API inbox
drafts only.

The script writes both secret files with mode `0600`, completes OAuth, verifies
that `video.upload` was granted, and prints no secret values. For an existing
valid refresh token:

```bash
python3 scripts/idol_tiktok_oauth_reauth.py --refresh-only
```

If an existing client binding is wrong or the developer app changed, reopen the
localhost client form without printing the old values:

```bash
python3 scripts/idol_tiktok_oauth_reauth.py --open-browser --configure-client
```

Official protocol references:

- <https://developers.tiktok.com/doc/login-kit-desktop/>
- <https://developers.tiktok.com/doc/oauth-user-access-token-management>
- <https://developers.tiktok.com/doc/content-posting-api-reference-upload-video>

### 2.2 YouTube

```bash
python3 scripts/idol_youtube_oauth_reauth.py --open-browser
```

Default callback is `http://127.0.0.1:8765/oauth2callback`. The script writes
`youtube-token.json` with mode `0600` and does not print token values.

### 2.3 X

```bash
python3 scripts/idol_x_oauth_reauth.py
```

Use full browser reauth after `401` or a rejected refresh. Use
`--refresh-only` only when the refresh grant is still accepted:

```bash
python3 scripts/idol_x_oauth_reauth.py --refresh-only
```

### 2.4 One-time metric-read authorization

Complete these browser flows once for the owning accounts before relying on the
daily collector. Each stores a refreshable local token only; the normal daily
run refreshes it internally and must not reopen the browser.

| Platform | Required retained scope | Safe command |
| --- | --- | --- |
| X | `tweet.read` plus the existing standard delivery scopes and `offline.access` | `python3 scripts/idol_x_oauth_reauth.py` |
| TikTok | `video.upload`, `video.list` | `python3 scripts/idol_tiktok_oauth_reauth.py --open-browser --scope video.list` |
| YouTube / Shorts | upload, `youtube.readonly`, `yt-analytics.readonly` | `python3 scripts/idol_youtube_oauth_reauth.py --open-browser --scope https://www.googleapis.com/auth/youtube.readonly --scope https://www.googleapis.com/auth/yt-analytics.readonly` |

The X runner prepares a 0600 local authorization-link file and waits for the
localhost callback; open that link only through the controlled local browser
step, never by copying it into chat. After each authorization, run the
value-free health check from section 1 and confirm only
`ready_for_runtime_metrics: true`. A false value means the app/account did not
grant the requested scope or its refresh token needs recovery; it never means a
draft may be treated as published.

## 3. One common queue, four execution lanes

Use the same run-owned `platform-posts*.jsonl` metadata structure for every
platform, but do not force all rows through one external API.

| Platform | `delivery_mode` | `execution_lane` | Adapter |
| --- | --- | --- | --- |
| X | `public_api_post` | `x_hash_bound_public_adapter` | dedicated X adapter |
| TikTok | `platform_draft` | `tiktok_inbox_api` | automatic inbox upload |
| YouTube | `platform_draft` | `youtube_private_api` | automatic private upload |
| YouTube Shorts | `platform_draft` | `youtube_shorts_private_api` | automatic private upload |
| Instagram Reels | `manual_upload_package` | `instagram_manual` | manual checklist/package |

The draft uploader reads a mixed queue but selects only TikTok and
YouTube/Shorts by default. `--platform x` and `--platform instagram_reels`
fail with the correct route. X has no native draft object in this repository;
Instagram has no implemented API adapter or success record.

The common row should keep:

```yaml
post_id:
content_id:
platform:
delivery_mode:
execution_lane:
asset_or_clip:
api_upload_quality_profile: idol_api_upload_2k30_high_quality.v1
api_upload_quality_receipt:
caption:
hashtags: []
draft_status: not_uploaded
publish_order:
scheduled_after_x:
```

For authoring details:

- X: `skills/x-posting-template/SKILL.md`
- TikTok and Instagram: `skills/reels-tiktok-template/SKILL.md`
- YouTube/Shorts and shared execution: `skills/idol-social-metadata-upload/SKILL.md`

## 4. Recent successful patterns

### 4.1 Global ledger baseline

Source: `analytics/records/platform-posts.jsonl`. Successful delivery markers
(`uploaded_tiktok_inbox`, `uploaded_private_draft`, or the legacy registered
YouTube embed marker) from
2026-05-30 through the current ledger total 111:

| Date | Count | Platforms |
| --- | ---: | --- |
| 2026-05-30 | 12 | TikTok, YouTube Shorts |
| 2026-06-15 | 1 | TikTok |
| 2026-06-16 | 3 | TikTok, YouTube Shorts |
| 2026-06-17 | 13 | TikTok, YouTube, YouTube Shorts |
| 2026-06-21 | 2 | TikTok, YouTube |
| 2026-06-24 | 71 | TikTok, YouTube, YouTube Shorts |
| 2026-06-25 | 6 | YouTube Shorts |
| 2026-07-02 | 1 | YouTube |
| 2026-07-29 | 2 | TikTok, YouTube Shorts |

Most recent TikTok baseline: 2026-07-29
`CF_COSMETIC_TARGET_DISCOVERY_001-TT-20260728-001`, including
`draft_status=uploaded_tiktok_inbox`. Match its Sandbox inbox-draft semantics,
not a public-post claim.

### 4.2 Newer run-owned verified results

| Time | Platform | Result | Evidence |
| --- | --- | --- | --- |
| 2026-07-28 23:01 KST | X | completed public root plus three replies | `cf/runs/CF_COSMETIC_TARGET_DISCOVERY_001/generations/cf-code/package/social/x/x-api-schedule-20260728T230020+0900.result.json` |
| 2026-07-29 09:10 KST | YouTube Shorts | `uploaded_private_draft`, id `rxwn61IROQc` | current bridge queue, tracker, log, and completed upload attempt |
| 2026-07-29 10:05 KST | TikTok | `uploaded_tiktok_inbox`, id `v_inbox_file~v2.7667748920851974160` | current bridge queue, tracker, log, and completed upload attempt |

Do not convert an inbox/private draft result into `published`.

## 5. Current cosmetic bridge run

```text
runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/
  05-package.yaml
  publishing-plan.md
  generations/video/master/cosmetic-morning-luma-v15-sound-off.mp4
  exports/social/2026-07-28-shorts-draft/platform-posts.jsonl
  exports/social/2026-07-28-shorts-draft/draft-upload-tracker.md
  exports/social/2026-07-28-shorts-draft/platform-upload-log.jsonl
  review/platform-release-approval-v1.json
```

Active title registry:

```text
catalog/albums/aurora-m/cf-cosmetic-target-discovery-001/output-registry.yaml
```

Active approval SHA-256:

```text
c02441b792085ea23eb84a4481472dfeeefed14679ad23f14a5ce7d13c4ca525
```

### 5.1 Local dry-run

The default dry-run may inspect the mixed queue and selects only currently
runnable automatic draft rows:

```bash
scripts/idol-video-python scripts/idol_platform_draft_upload.py \
  --run-root runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001 \
  --content-id CF_COSMETIC_TARGET_DISCOVERY_001 \
  --queue runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/exports/social/2026-07-28-shorts-draft/platform-posts.jsonl \
  --package-contract runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/05-package.yaml \
  --tracker runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/exports/social/2026-07-28-shorts-draft/draft-upload-tracker.md \
  --log runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/exports/social/2026-07-28-shorts-draft/platform-upload-log.jsonl \
  --album-key aurora-m \
  --title-key cf-cosmetic-target-discovery-001
```

### 5.2 TikTok retry after reauth

```bash
scripts/idol-video-python scripts/idol_platform_draft_upload.py \
  --run-root runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001 \
  --content-id CF_COSMETIC_TARGET_DISCOVERY_001 \
  --queue runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/exports/social/2026-07-28-shorts-draft/platform-posts.jsonl \
  --package-contract runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/05-package.yaml \
  --tracker runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/exports/social/2026-07-28-shorts-draft/draft-upload-tracker.md \
  --log runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/exports/social/2026-07-28-shorts-draft/platform-upload-log.jsonl \
  --platform tiktok \
  --album-key aurora-m \
  --title-key cf-cosmetic-target-discovery-001 \
  --retry-failed \
  --apply \
  --approval-artifact runs/2026-07-28/CF_COSMETIC_TARGET_DISCOVERY_001/review/platform-release-approval-v1.json \
  --approval-sha256 c02441b792085ea23eb84a4481472dfeeefed14679ad23f14a5ce7d13c4ca525
```

Success means `uploaded_tiktok_inbox`; the account owner still completes
editing/posting inside TikTok. Do not add `--skip-title-registry`.

### 5.3 YouTube/Shorts apply pattern

Use the same command and change `--platform` to `youtube` or
`youtube_shorts`. Use `--retry-failed` only for a row currently marked
`failed_api_upload`. A completed private draft is not selected again.

### 5.4 X and Instagram

- X: use the current hash-bound queue and
  `cf/scripts/cf_x_post_approved_thread.py`; rebuild an expired scheduled queue
  and re-bind its approval before apply.
- Instagram: export the common row into the manual release package and record a
  public URL/id only after observed manual posting.

## 6. Fast recurrence playbook

1. Run the value-free auth status.
2. Confirm the run, queue, `05-package.yaml`, approval artifact/SHA, 2K/CFR30
   quality receipt, asset hash, and active title registry.
3. If TikTok readiness is false, run its browser reauth. Use the localhost setup
   page only when the app client files are absent.
4. If YouTube readiness is false or refresh returns `invalid_grant`, run its
   browser reauth.
5. If X returns `401`, use full browser reauth, rebuild any expired queue, and
   run the dedicated X adapter.
6. Run the platform-specific dry-run.
7. Apply only with the exact Founder approval artifact.
8. A deterministic pre-request failure is `failed` and may use
   `--retry-failed`. A `started` or `unknown` attempt must be reconciled before
   retry.
9. After the Founder makes a draft public and supplies its exact URL, preserve
   the actual `published_at`, exact visible members, MV track or CF, and
   final-used visual source/web paths and hashes in a run-owned closeout under
   `schemas/signal-deck-publication.schema.json`.
10. Dry-run then apply
    `scripts/idol_social_public_closeout.py --closeout RUN/review/public-closeout-POST_ID.json`.
    This atomically closes the global post ledger, Signal Deck publication
    registry, and existing title registry. It performs no API call or deploy.
11. Keep platform ids/URLs in the run queue, tracker, log, and title registry.
    The global ledger may be published only when the row is supported by the
    observed URL and timestamp.

## 7. Forbidden

- Never print, paste, log, hash, or commit secret values.
- Never infer approval from CF70/04FX skill receipts, package status, or an old
  ledger row.
- Never treat a local X queue as published.
- Never treat a TikTok inbox or YouTube private draft as public.
- Never route X through an Ads account.
- Never invent an Instagram API success or TikTok credentials.
- Never bypass the title registry during apply.

## 8. Recent ops log

| Date | Action | Result |
| --- | --- | --- |
| 2026-08-02 | IDOL API video quality lock | Local preparation receipt plus X/TikTok/YouTube/Shorts pre-request probes now require 2K-or-higher CFR30 high-quality bytes and prohibit uploader transcoding. |
| 2026-08-01 | Public URL closeout and Signal Deck projection | One schema-bound local operation now registers analytics, exact member/track-or-CF visual mapping, embed URL, and title-registry publication without a metric API call or deployment. |
| 2026-07-30 | Phase 1 metric authorization and automation consolidation | X `tweet.read` confirmed; TikTok refresh retained `video.list`; YouTube account-read + Analytics consent completed and one read-only collection wrote two aggregate snapshots. `idol-sns-management` is the one remaining daily caller. |
| 2026-07-29 | TikTok Sandbox Desktop callback repair, OAuth, and apply | callback corrected to `http://127.0.0.1:8766/oauth2callback`; completed inbox draft `v_inbox_file~v2.7667748920851974160` |
| 2026-07-29 | uploader retry-state repair | deterministic pre-request failures now close as `failed`; only ambiguous outcomes stay `unknown` |
| 2026-07-29 | mixed-platform execution contract | common queue now routes X, TikTok, YouTube/Shorts, and Instagram to distinct adapters |
| 2026-07-29 | YouTube browser reauth and Shorts apply | completed private draft `rxwn61IROQc` |
| 2026-07-29 | TikTok auth check | missing client/token files recovered through localhost Desktop PKCE without printing values |
| 2026-07-28 | X browser OAuth reauth and cosmetic thread apply | completed root plus three replies |

## 9. Related sources

- `skills/idol-social-metadata-upload/SKILL.md`
- `skills/x-posting-template/SKILL.md`
- `skills/reels-tiktok-template/SKILL.md`
- `cf/skills/x-api-scheduled-posting/SKILL.md`
- `wiki/social-automation-system.md`
- `scripts/README.md`

This file supersedes scattered credential-layout and social-draft recovery
notes for agent execution.
