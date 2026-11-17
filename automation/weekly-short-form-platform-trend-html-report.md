# Weekly Short-Form Platform Trend HTML Report Automation Contract

## Purpose

Create one weekly public-source HTML report that observes TikTok and Instagram
Reels short-form behavior as a platform/content layer separate from the weekly
idol activity report. The report tracks how attention, participation, sound,
camera, editing, text, creator behavior, and replay mechanics are changing. It
feeds the biweekly IDOL trend pulse but does not create a PRE-00 route, MV
direction, CF route, publishing plan, or platform post by itself.

## Canonical Ownership And Cadence

Write the weekly report under:

```text
source-materials/short-form-trend-reports/weekly/
```

Recommended name:

```text
YYYY-WW-tiktok-instagram-short-form-trend-report.html
```

Then update:

```text
source-materials/short-form-trend-reports/weekly/latest.md
```

Run weekly when the active slate needs current short-form behavior. This is a
parallel observation lane to `automation/weekly-idol-activity-html-report.md`,
not a subsection of the idol activity report and not a replacement for it.

## Required Reads

```text
AGENTS.md
wiki/production-system.md
wiki/pre-00-song-system.md
source-materials/short-form-trend-reports/README.md
source-materials/short-form-trend-reports/weekly/TEMPLATE.html
source-materials/short-form-trend-reports/weekly/latest.md
source-materials/trend-pulse-records/latest.md
source-materials/idol-activity-reports/weekly/latest.md
```

Read the active fashion record only when the report makes a material, styling,
silhouette, accessory, or color claim.

## Public Research Boundary

Use public web research/fetch only. The normal source order is:

1. public official TikTok or Instagram/Meta trend, creator, newsroom, business,
   or platform-guidance pages;
2. public, stable creator/artist/brand post URLs that can be observed without a
   login, cookie, personalized feed, or private account;
3. reputable reporting or public analytics summaries that state their date,
   geography, sample, and method;
4. current local weekly reports, trend pulses, and prior short-form reports.

Do not use logged-in TikTok/Instagram sessions, For You/Explore personalization,
private pages, cookies, browser profile state, private connectors, paid APIs,
uploads, downloads, `yt-dlp`, bulk media capture, platform sync, or external
writes. If a public page cannot be verified without those, record the source as
unavailable and use a different public source or hold the claim. A public trend
report is observation evidence, not permission to copy, download, repost, or
use its media as generation/edit input.

## Sampling And Evidence Rules

Every claimed signal records:

- platform: `tiktok`, `instagram_reels`, or `cross_platform`;
- geography/language and audience/category scope when known;
- observation window and source publication/observation dates;
- exact public source identities and URLs;
- observed behavior separated from analyst inference;
- evidence status: `official_platform_declared`, `observed_single`,
  `repeated_same_platform`, `cross_platform_repeated`, or
  `unverified_hypothesis`;
- trend phase: `emerging`, `growing`, `mature`, `saturated`, `fading`,
  `reappearing`, or `unclear`;
- response proxy and its limitation; and
- contradiction, platform difference, or reject reason.

Do not infer a trend from one high-view post. A non-official weekly signal
normally needs at least three distinct public examples on the same platform to
be called `repeated_same_platform`. A `cross_platform_repeated` signal normally
needs at least two distinct examples on each platform. If access or sample
quality cannot meet that bar, keep the row as `observed_single` or
`unverified_hypothesis`; do not pad it with near-duplicate reposts.

Raw views, likes, comments, saves, shares, or use counts are optional response
proxies. Record them only when publicly visible and source-citable. Do not
compare unlike metrics as if they were equivalent, normalize away missing
context, or treat raw popularity as creative quality.

## Required Report Contents

Use the HTML template and include:

- integrated weekly conclusion;
- access/coverage statement and missing-evidence holds;
- TikTok-specific signals;
- Instagram Reels-specific signals;
- cross-platform common signals and meaningful divergences;
- trend lifecycle matrix showing emergence, growth, maturity, saturation,
  fading, or reappearance;
- first 0-2 second hook, 3-8 second retention, loop/ending, and replay behavior;
- audio-function observations such as sound-tag entry, beat/drop placement,
  dialogue/spoken setup, silence/breath, remix reuse, or save-to-library intent,
  without copying lyrics;
- camera/crop, body/action, object/system, text/caption, edit/time, comment/
  participation, creator/artist/brand behavior, and platform-native mechanics;
- K-pop/idol adjacency and current weekly idol-report cross-check;
- AURORA-M/Loom usable function, transformation requirement, rejection risk,
  and which later research question it may inform;
- candidates to promote into the next biweekly trend pulse; and
- noise, saturation, platform-only tricks, unsafe copying, and stale signals to
  reject or recheck.

## Promotion Rule

The weekly report may nominate a signal for the biweekly trend pulse only when
it is `official_platform_declared`, `repeated_same_platform`, or
`cross_platform_repeated`, has a current source window, names its platform
scope, and states how it could affect song hook, target response, screen role,
short-form derivative, or distribution behavior. The pulse owner independently
accepts, revises, or rejects the nomination.

Do not promote a creator's protected character, exact choreography, caption,
audio, edit sequence, visual identity, or campaign surface. Promote the
transferable function and its evidence, not the post itself.

## Boundaries

This automation must not create run folders, PRE-00 radar artifacts,
`00-creative-nucleus.yaml`, song locks, MV/CF routes, prompt packets, paid
generation requests, publishing plans, social ledgers, platform drafts, memory
promotions, uploads, downloads, or external sync. Founder review and the
biweekly pulse decide whether any signal enters later creative research.
