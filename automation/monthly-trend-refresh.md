# Legacy Monthly Trend Refresh Compatibility Contract

## Purpose

This file is retained as a compatibility pointer for older references to the
first-of-month trend refresh. The active cadence is now:

```text
weekly idol activity HTML report + weekly TikTok/Instagram short-form report
-> biweekly trend pulse refresh
-> month-end idol research HTML summary + short-form platform trend summary
```

The active market hypothesis for PRE-00 and new song routing is the latest
biweekly trend pulse, not a first-of-month monthly record. Legacy monthly trend
records remain archived under `source-materials/monthly-trend-records/`.

## Automation Job

Use these current contracts instead:

```text
automation/weekly-idol-activity-html-report.md
automation/weekly-short-form-platform-trend-html-report.md
automation/biweekly-trend-pulse-refresh.md
automation/monthly-idol-research-summary.md
automation/monthly-short-form-platform-trend-summary.md
```

If an older automation calls this file, route to
`automation/biweekly-trend-pulse-refresh.md` for current-market refresh and to
both `automation/monthly-idol-research-summary.md` and
`automation/monthly-short-form-platform-trend-summary.md` at month end when
their corresponding weekly evidence exists.

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

When styling direction is part of the refresh, also read:

```text
source-materials/fashion-trend-records/latest.md
```

## Current Record Contents

The biweekly trend pulse should stay compact and source-backed:

- current song structures and hook mechanics
- current idol activity and promotion signals
- current TikTok/Instagram short-form platform signals, lifecycle, and
  platform-specific differences
- message and audience-position signals
- media narrative signals
- visual, space, styling, and wardrobe implications
- risks, stale signals, and reject traits
- how AURORA-M/Loom can use, transform, or reject the signal

## Boundaries

The automation must not create run folders, PRE-00 artifacts,
`00-creative-nucleus.yaml`, `00A-song-lock.yaml`, Suno packets, paid generation
requests, publishing plans, social ledgers, or memory promotions.
