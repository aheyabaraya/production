# Monthly Idol Research Summary Automation Contract

## Purpose

Create one month-end HTML summary from the weekly idol activity reports and
biweekly trend pulses. The monthly summary is an archive and comparison surface.
It is useful for long-view memory, but it is not the first current-market source
for PRE-00.
TikTok/Instagram short-form lifecycle and platform-divergence comparison
belongs to `automation/monthly-short-form-platform-trend-summary.md`; the two
monthly summaries may cross-reference one another but keep separate owners.

## Automation Job

Use local weekly reports, trend pulses, and public web research/fetch only when
current verification is needed. Do not use private connectors, Drive, GitHub,
secrets, logged-in/session/cookie-based browser access, paid APIs,
uploads/downloads, external writes, or platform sync unless the founder approves
that exact task.

Read:

```text
AGENTS.md
wiki/production-system.md
source-materials/idol-activity-reports/README.md
source-materials/idol-activity-reports/weekly/latest.md
source-materials/idol-activity-reports/monthly/TEMPLATE.html
source-materials/trend-pulse-records/latest.md
```

Create the monthly HTML summary under:

```text
source-materials/idol-activity-reports/monthly/
```

Recommended name:

```text
YYYY-MM-idol-research-summary.html
```

Then update:

```text
source-materials/idol-activity-reports/monthly/latest.md
```

## Summary Contents

Use the HTML format to preserve scanability:

- monthly conclusion
- index of weekly reports
- comparison of the month's trend pulses
- repeated song, stage, styling, fandom, and promotion signals
- PRE-00 useful signals
- stale, noisy, saturated, or rejected signals
- AURORA-M/Loom application notes
- next-month recheck questions

## Boundaries

The monthly summary must not override the active trend pulse, founder locks,
member asset alignment, current verified run research, selected audio analysis,
or production contracts.
