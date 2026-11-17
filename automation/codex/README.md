# Codex Weekly Idol Research Automations

Status: Founder-approved recurring execution configuration

This folder is the repository-owned configuration source for the two Codex
automations that keep the IDOL research evidence chain current. The
active app copies live under `/Users/yuminseog/.codex/automations/`.

| Automation id | Job | KST schedule | Model |
|---|---|---|---|
| `idol-weekly-short-form-research` | Public TikTok/Reels behavior report and freshness pointer | Monday 20:00 | `gpt-5.6-luna` / `max` |
| `idol-weekly-integrated-research` | Integrated field report, fixed Loom pool, M01-M13 target/demand, 26 personas, LSC0-LSC4 SNS cohort coverage, E0-E5 hypotheses, audited rolling-28-day calculation | Monday 22:00 | `gpt-5.6-luna` / `max` |
| `idol-weekly-representative-deep-dive` | One representative comeback-brand deep dive, ledger completion, bundle close | Monday 23:00 | `gpt-5.6-luna` / `max` |
| `idol-biweekly-trend-pulse` | Accept/revise/reject weekly signals into the active PRE-00 market hypothesis | Tuesday 09:00 every two weeks | `gpt-5.6-luna` / `max` |

The one-hour stagger is mandatory. The deep dive holds when the integrated
report or its eligible-comeback selection receipt is incomplete. The
automations may use public web research. The visual-idol lane may acquire only
public, source-bound still-image evidence needed for its self-contained report;
that permission excludes login/cookies, bulk media, video/audio capture,
generation, edit inputs, uploads, publishing, platform sync, and creative locks.

Repository files:

```text
automation/codex/idol-weekly-integrated-research.automation.toml
automation/codex/idol-weekly-representative-deep-dive.automation.toml
```

Active Codex copies:

```text
/Users/yuminseog/.codex/automations/idol-weekly-integrated-research/automation.toml
/Users/yuminseog/.codex/automations/idol-weekly-representative-deep-dive/automation.toml
```

The report agent consumes the schedule; it does not install, edit, duplicate,
or widen these automations.
