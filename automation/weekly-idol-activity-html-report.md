# Weekly Idol Activity HTML Report Automation Contract

## Purpose

Create one paired weekly bundle: an image-led integrated-idol HTML report that
tracks newly debuted, comeback, and active groups, plus an image-led deep dive
on exactly one representative brand selected from idols with an official
comeback release in that covered week. The reports are observation surfaces for
Founder review, later biweekly trend-pulse synthesis, and a Founder-requested
PRE-00 concept pass. Neither is a production run or a selected PRE-00 route.
TikTok/Instagram platform-native trend behavior
belongs to the parallel
`automation/weekly-short-form-platform-trend-html-report.md` contract; this
report may cross-reference it but must not absorb or replace it.

The visual/depth benchmark and model ownership live in
`skills/idol-research-radar/references/weekly-visual-idol-report-contract.md`.
Read that contract completely before authoring this report.

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
source-materials/idol-activity-reports/README.md
source-materials/idol-activity-reports/weekly/TEMPLATE.html
source-materials/idol-activity-reports/weekly/REPRESENTATIVE-IDOL-BRAND-TEMPLATE.html
source-materials/idol-activity-reports/weekly/REFERENCE-IMAGE-LEDGER-TEMPLATE.md
skills/idol-research-radar/references/weekly-visual-idol-report-contract.md
source-materials/trend-pulse-records/latest.md
assets/member-registry.yaml
assets/unit-registry.yaml
assets/voice-style-index.md
business-marketing/brand-management/references/loom-weekly-idol-reference-pool-v1.yaml
business-marketing/brand-management/audience/latest.md
business-marketing/skills/loom-sns-cohort-analysis/SKILL.md
business-marketing/brand-management/cohorts/loom-sns-cohort-contract-v1.yaml
business-marketing/brand-management/cohorts/current-loom-sns-cohort-snapshot.yaml
analytics/records/platform-posts.jsonl
analytics/records/platform-metrics.jsonl
```

When styling direction is part of the report, also read:

```text
source-materials/fashion-trend-records/latest.md
```

Resolve the dedicated owner before authoring:

```text
ruby scripts/idol_harness_shadow_eval.rb route weekly_visual_idol_research --execution-scope weekly_research_report --json
```

Create both weekly HTML reports and one authoring-time reference-image ledger
under:

```text
source-materials/idol-activity-reports/weekly/
```

Required names:

```text
YYYY-WW-idol-activity-report.html
YYYY-WW-{idol-brand-slug}-brand-deep-dive-report.html
YYYY-WW-reference-image-ledger.md
```

At the Monday 22:00 integrated checkpoint, validate the two canonical social
ledgers and refresh the Founder-authorized private current cohort snapshot with:

```text
ruby business-marketing/skills/loom-sns-cohort-analysis/scripts/build_snapshot.rb --write
```

This is the only additional weekly write surface. It does not authorize an API
call, personal-data collection, source-ledger mutation, or a dated cohort-file
pile.

Only after both reports pass, update:

```text
source-materials/idol-activity-reports/weekly/latest.md
```

## Cadence And Ownership

The paired bundle covers one KST week on the fixed `Asia/Seoul` timezone.
Freeze the normal observation window on Sunday 23:59. Run the bounded
Luna/Max/High integrated-idol report at Monday 22:00, finish-or-hold it, and
freeze its representative-comeback selection receipt. Run the selected-brand
deep dive at Monday 23:00, exactly one hour later, using that completed field
report and receipt. Monday 23:00 is the bundle completion forecast and includes
a traceable report-scoped PRE-00 candidate interpretation in each report. The
second report must not run early or in parallel with an unfinished first
report, and there is no routine Sol handoff. The HTML header records the
coverage window, source cutoff, timezone, both run checkpoints, one-hour
stagger, start time, original expected completion, actual completion, both
per-report statuses, and the bundle status. After a successful Monday pass the
integrated report is `complete`, the deep dive is `not_started`, and the bundle
is `in_progress`. A missing provenance check or material source gap is
`hold_incomplete`, not a reason to issue a superficial report.

`idol_luna_studio_department` at Luna/Max/High owns this weekly automation scope end
to end: public-source research, source/image analysis, both detailed HTML
reports, report-scoped PRE-00 opportunities,
and—only when the Founder requests it—the three-to-five independent concept
alternatives derived from the report. Sol/XHigh may be explicitly assigned an
independent skill/contract or quality audit, but it is not a scheduled weekly
handoff or co-author. This exception does not apply to full structured radar,
selected-route intake, Front Planning, or MV production. Luna does not
select a route or write a creative lock.

Use `not_started`, `in_progress`, `hold_incomplete`, or `complete` exactly as
defined in the weekly visual report contract. Keep the original Monday 23:00
`expected_complete_at` after a miss. `hold_incomplete` requires named
`blockers` and a `revised_expected_complete_at` on the next declared Monday
23:00 KST recovery checkpoint; `complete` requires a real shared `completed_at`, both
companion reports, every required section/dossier, and zero placeholder,
remote, relative-path, broken, or undecodable report images. One report cannot
advance `latest.md` alone; the paired reference-image ledger must also map every
evidence-bearing figure before the bundle advances. This repository contract
does not create or authorize another scheduler. The only recurring launchers
are the separately Founder-approved Codex automations
`idol-weekly-integrated-research` and
`idol-weekly-representative-deep-dive`; the report agent must not install,
edit, duplicate, or widen them.

## Integrated-Idol Report Contents

Use the HTML format to make scanning fast:

- integrated conclusion
- style branding map that explains each relevant group's identity, audience
  promise, and why its fashion/performance choices work
- one weekly delta row for each fixed Loom comparison group: BLACKPINK, MEOVV,
  aespa, i-dle, BABYMONSTER, and support-only LE SSERAFIM
- weekly new/comeback/active idol activity map
- source-bound image dossiers for every primary group and every idol used as a
  potential concept reference; each dossier includes visible observations,
  positioning logic, transferable function, and direct-reference application scope
- group-by-group style, stage, MV, teaser, photo wall, airport, and SNS signals
- choreography, camera, and performance-readability notes
- fandom, merchandise, gender, age, platform, chart, or engagement proxy signals
  only when trustworthy enough to cite
- Loom overall target movement and one decision row for each M01-M13 target,
  both fan-persona hypotheses, bias motive, and member-led demand hypothesis
- LSC0-LSC4 Loom-owned SNS cohort coverage with source hashes, numerator,
  denominator, window, and `defined_not_populated|partially_populated|populated`
  state, followed by the separate temporary E0-E5 delta; E4 remains
  commerce-only and neither layer substitutes for member persona or identity
- a visible rolling-28-day gross-demand equation using qualified reach,
  fan-intent conversion, buyer conversion, and gross units per ordering buyer,
  with same-cohort denominators, plus net-fulfillment availability status and
  `not_a_forecast` when Loom-owned data is incomplete
- confirmed versus estimated competitor/comeback pressure
- source links with verification notes
- AURORA-M/Loom usable signal, reject signal, and possible active-unit fit
- PRE-00 questions and candidates to promote into the next biweekly trend pulse

## Representative Idol Brand Deep-Dive Contents

Select exactly one brand from idols whose official comeback release falls
inside the coverage window. Debuts, upcoming or unconfirmed comebacks, tours,
SNS-only activity, reissues, and older active promotions are ineligible.
Record `representative_brand_name`, `representative_brand_slug`,
`selection_reason`, `selection_evidence_ids`, and `previous_featured_week` in
both reports, plus `selection_freshness` as `new_brand`,
`material_new_event`, or `founder_explicit_repeat`, and the official
`comeback_release_title`, `comeback_release_date`, and `comeback_evidence_ids`.
Prefer current activity/release relevance, a distinctive and
inspectable brand system, target or competitive adjacency to Loom, and enough
public image evidence. Do not select by familiarity alone or repeat the prior
brand without a material new event. If no eligible comeback brand clears the evidence floor, hold
the bundle instead of researching several weaker brands.

Match the supplied MEOVV example's report logic and analytical depth for the
selected brand: executive
conclusion; thesis verification; evidence and response limits; identity/member
relationship; official release and activity chronology; target and audience;
visual DNA by era; fashion/brand proof; performance and promotion history;
competitors and release calendar; song/album/release architecture implications;
promotion, broadcast, distribution, and rights; budget protection; KPI;
report-scoped PRE-00 bridge; caveats and sources. MEOVV is the benchmark, not
the fixed subject. Strategy alternatives appear
only when the Founder explicitly requests them, as three to five independent
options rather than a simultaneous plan.

Statistics are optional. If no trustworthy public statistic exists, leave the
field out or mark `not_available`. Do not invent demographic, chart, sales,
engagement, or merchandise values.

Images are mandatory for an eligible primary or concept-reference idol dossier.
Embed the approved report image directly as a decodable base64 data URI and
include source identity/title/date/URL or canonical local path, verification
status, literal visible observation, branding/target meaning, transferable
function, non-transferable identity code, concrete album visual-reference role
(wardrobe/styling/makeup/hair-accessory/garment-material or `not_applicable` with a
reason), current-run translation, and direct-reference application scope. The
scope names the selected visual surface and any explicit Founder replacement or
discard; it must not impose a general ban on composition, camera, action,
performance, motion, edit, or PRE-00 use. A decorative thumbnail or a source
list alone is not sufficient.
Before embedding, produce a display-sized optimized derivative: WebP or JPEG
for photographs, PNG only when transparency, line work, or readable text
requires it. Record embedded MIME type, intrinsic pixels, optimized byte size,
derivative SHA-256, and compression or lossless-exception reason in the image
caption. Never reduce an image until the claimed visible evidence becomes
unreadable.
Create the paired `YYYY-WW-reference-image-ledger.md` while selecting and
embedding images. Every evidence-bearing `figure` needs a bundle-unique
`data-reference-id`, `data-album-visual-reference="direct_reference_after_run_selection"`,
an `image_evidence_id`, and one ledger row that records the report/figure ids
and SHA-256 values, original provenance, visible fact, branding/target meaning,
transferable function, non-transferable identity code, direct-reference application scope,
`observe|test|hold|reject` reuse state, and an actual album visual-reference
role. Only images embedded in the completed paired weekly HTML files are
eligible. The completed HTML is read first as the reusable direct-reference
board;
the ledger maps the selected image into a later album's Front Planning
reference connection or current-title visual asset-production candidate. It is
never a detached image collection. Use
`scripts/idol_weekly_report_reference_extract.py` only when a later run selects
one exact figure for that intake or pixel inspection.
If provenance cannot be established, hold that dossier rather than inserting a
generic generated image. A `complete` report has no external CSS/font/script
dependency; clickable provenance links are allowed because they are not image
dependencies.

## Boundaries

The automation must not create run folders, PRE-00 artifacts, 00A, Front
Planning, Suno packets, paid generation
requests, publishing plans, social ledgers, memory promotions, uploads, or
external sync. It must not generate unsolicited concept proposals: three to
five independent alternatives appear only after a Founder request and never as
a simultaneous operating plan.
