# Biweekly Trend Pulse Refresh Automation Contract

## Purpose

Refresh the active IDOL trend pulse every two weeks. The pulse is the current
market hypothesis for PRE-00, new song brainstorming, Suno/manual prompt setup,
provisional song locks, and creative nucleus routing. It promotes repeated or
founder-relevant weekly observations into a compact decision surface.

## Automation Job

Use public web research/fetch for current public sources when needed. Do not use
private connectors, Drive, GitHub, secrets, logged-in/session/cookie-based
browser access, paid APIs, uploads/downloads, external writes, or platform sync
unless the founder approves that exact task.

Read:

```text
AGENTS.md
wiki/production-system.md
wiki/pre-00-song-system.md
source-materials/trend-pulse-records/latest.md
source-materials/idol-activity-reports/weekly/latest.md
source-materials/short-form-trend-reports/weekly/latest.md
assets/member-registry.yaml
assets/unit-registry.yaml
assets/voice-style-index.md
```

When weekly idol-activity or short-form-platform HTML reports exist for the
covered period, read both before doing new public web research. They are
parallel evidence owners: idol reports describe group/promotion activity;
short-form reports describe TikTok/Instagram attention, participation, sound,
camera, editing, text, and replay behavior. Do not substitute one for the other.
When styling direction is part of the refresh, also read:

```text
source-materials/fashion-trend-records/latest.md
```

Create or update the current pulse under:

```text
source-materials/trend-pulse-records/
```

Recommended name:

```text
YYYY-MM-pulse-NN.md
```

Then update:

```text
source-materials/trend-pulse-records/latest.md
```

## Record Contents

Keep the pulse compact and source-backed:

- covered period and weekly HTML inputs
- what changed since the prior pulse
- current song structures and hook mechanics
- idol activity and promotion signals
- TikTok-specific, Instagram Reels-specific, and cross-platform short-form
  signals, including evidence status and lifecycle phase
- hook/audio/camera/edit/text/participation/replay functions promoted from the
  weekly short-form report, plus platform differences and source-application scopes
- message and audience-position signals
- media narrative signals
- visual, space, styling, wardrobe, stage, and camera implications
- risks, stale signals, and reject traits
- how AURORA-M/Loom can use, transform, or reject the signal
- which findings should roll up into the monthly HTML summary

A short-form signal enters the pulse only when the weekly report marks it
`official_platform_declared`, `repeated_same_platform`, or
`cross_platform_repeated`, and the pulse owner independently confirms the
platform scope, freshness, response-proxy limitation, K-pop relevance, and
transferable function. `observed_single` and `unverified_hypothesis` rows remain
recheck questions. Never convert a specific creator post, choreography, audio,
caption, character, edit sequence, or campaign surface into an IDOL default.

## Boundaries

The automation must not create run folders, PRE-00 artifacts,
`00-creative-nucleus.yaml`, `00A-song-lock.yaml`, Suno packets, paid generation
requests, publishing plans, social ledgers, memory promotions, uploads, or
external sync.
