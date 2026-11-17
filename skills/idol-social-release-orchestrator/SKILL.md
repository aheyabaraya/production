---
name: idol-social-release-orchestrator
description: >-
  Run the standalone post-05 IDOL SNS flow when the Founder gives one finished
  asset or asks for SNS templates, Harne/Loom publishing preparation, social
  analysis, Signal Deck/Web closeout, or a minimum-intervention agentic
  release. Use this outside MV/CF creation: register the finished content once,
  author platform copy through the owning template skills, project one local
  package, present one Founder decision packet, resume from the exact approval
  without asking again, record public facts, and route only T+24h/T+72h/T+7d
  analytics. Never infer external upload, public publish, deploy, or approval
  authority.
---

# IDOL Social Release Orchestrator

## Purpose

Own the thin coordination layer above the existing social contracts. The
Founder should provide the finished content once, then only judge or name a
correction. Preserve the existing queue, approval, upload, closeout, Signal
Deck, and analytics owners; do not build a second posting system.

This is a standalone post-05 route. Do not start the MV or CF creative graph-engineering route,
load production departments, or reopen song, reference, image, video, or edit
work unless the Founder separately asks to revise the finished content.

## Authority

- The model may inspect, author platform copy, create local run artifacts,
  validate, hash, project local packages, and refresh the session read model.
- Deterministic scripts may copy declared values and derive paths, hashes,
  status, due checkpoints, and decision views. They never author copy or infer
  approval.
- Founder owns exact creative acceptance, external draft upload, public
  publish, scheduling, deploy, and any destructive action.
- A plain `PASS` means creative acceptance only. External authority requires
  the explicit packet reply `PASS DRAFT` or `PASS PUBLIC`, or an equally exact
  current-task instruction naming the action and bound packet.
- Never print secret values. Run the value-free credential status only when an
  approved external action is actually next.

## Required Reads

At the start of a new or materially resumed release, create the named Goal and
record a bounded Department Dispatch Contract for this local post-05 owner.
Read these exact files to EOF before action:

1. `AGENTS.md`
2. `wiki/social-automation-system.md`
3. `analytics/README.md`
4. `scripts/README.md`
5. `scripts/registry/release-and-platform.md`
6. `skills/idol-social-metadata-upload/SKILL.md`

Load only the needed platform authoring owner:

- X copy or thread: `skills/x-posting-template/SKILL.md`
- TikTok, YouTube Shorts, or Instagram Reels copy:
  `skills/reels-tiktok-template/SKILL.md`
- Credential recovery or an approved external draft action:
  `wiki/platform-credential-and-draft-upload-ops.md`
- Cohort judgment after valid measurements:
  `business-marketing/skills/loom-sns-cohort-analysis/SKILL.md`

Do not load the full production-system or CF stack for this route.

## Founder Interaction Contract

Accept the finished asset path or attachment plus any explicit intent. Reuse
facts that already exist in the asset, its sidecar, the run manifest, 05
package, prior Founder text, or the current session. Ask only when a missing
fact changes public meaning, legal/identity safety, platform selection, or
external authority and cannot be recovered locally.

The normal Founder interaction is:

1. one finished-content handoff;
2. one combined decision packet;
3. one response: `PASS DRAFT`, `PASS MANUAL`, `PASS PUBLIC`, `수정 — ...`, or
   `HOLD — ...`;
4. public URL plus actual `published_at` only when a manual platform cannot
   return those facts automatically.

Never ask the Founder to re-enter content ID, asset path, platform, caption,
hashtags, member mapping, schedule, or approval scope when the exact value is
already bound in the session. Never split one unchanged batch into separate
platform review rounds.

## Canonical Session

One release owns these stable run paths:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/
├── 05-package.yaml
├── publishing-plan.md
├── exports/social/.../platform-posts.jsonl
└── review/
    ├── social-release-session-v1.json
    └── social-release-decision-packet.md
```

`schemas/social-release-session.schema.json` owns the session contract.
`scripts/idol_social_release_session.py` is the read-model builder. The session
stores the queue, package, plan, registry, assets, valid approvals, public/Web
facts, fixed metric windows, and one next action. It performs zero external
actions.

If `review/social-release-session-v1.json` already exists, run `refresh`; do
not rediscover all runs or register a second session. An unchanged state must
return `mode=unchanged` and cause no file rewrite or Founder wake.

## Flow

### 1. Register The Finished Content Once

Resolve or create one active run. Keep the finished byte owner inside that run
and hash it. Author, do not script-generate, the following truths:

- `05-package.yaml` using `idol_package.v2`, with the exact finished
  deliverable and its hash-bound output -> ordered 04 Edit Segment ->
  screen-progression node/Section trace;
- one run-owned mixed-platform queue with platform copy and exact asset paths;
- `publishing-plan.md` with the same post IDs and scope;
- one matching title output registry owner.

Use Loom/Harne public naming. Do not claim publication, performance, member
visibility, track/CF mapping, or official affiliation without evidence. Use
the platform template owners for copy; the common metadata skill owns queue
and approval semantics.

If several old queues exist, choose the exact current batch once and pass that
path during registration. Ambiguity is a hold, never “newest file wins.”

### 2. Validate And Build The Local Package

Run the existing validators and projector before review. Use the exact current
timestamp and paths; no network is involved:

```bash
scripts/idol-video-python scripts/idol_social_release_sync.py \
  --run-root RUN_ROOT \
  --content-id CONTENT_ID \
  --queue QUEUE \
  --package-contract RUN_ROOT/05-package.yaml \
  --package RUN_ROOT/exports/social/release-package/BATCH_ID \
  --publishing-plan RUN_ROOT/publishing-plan.md \
  --registry TITLE_OUTPUT_REGISTRY \
  --projected-at ISO_8601_KST \
  --approval-status pending_founder_approval \
  --apply
```

Then register the durable session:

```bash
scripts/idol-video-python scripts/idol_social_release_session.py register \
  --run-root RUN_ROOT \
  --queue QUEUE \
  --registry TITLE_OUTPUT_REGISTRY \
  --at ISO_8601_KST \
  --apply
```

Validate the publishing plan, social ledger contract, session schema, asset
hashes, and package file set. A schema PASS is structural evidence, not
creative approval.

The projector copies the selected output's package path/hash, deterministic
deliverable-manifest digest, production-graph digest, Edit Segment ids,
screen-progression node ids, and Section ids into the run queue and sidecar,
marked `release_provenance_version: idol_release_provenance.v2`.
Those fields are append-only release provenance. They do not approve upload or
publication and post-05 analytics cannot write back into 05 or 04 truth.

### 3. Give One Decision Packet

Open `review/social-release-decision-packet.md` and independently inspect the
exact asset plus every listed platform row. Present one answer-first summary
to the Founder:

- what will be posted and where;
- the full final copy and schedule;
- any identity, disclosure, format, source, or platform risk;
- what the selected PASS token authorizes;
- only the unresolved choice.

Do not ask for approval per platform when one packet contains the exact batch.
Do not wake the Founder when `refresh` returns `unchanged`.

### 4. Apply One Founder Reply

On `수정`, preserve the verbatim instruction, patch only the named queue and
matching plan rows, recompute the package/session, and return one revised
packet. Unaffected rows keep their text, IDs, paths, and schedule. Any changed
action-bearing queue byte invalidates stale approvals automatically.

On an explicit PASS token, author one
`review/platform-release-approval-vN.json` using
`schemas/platform-release-approval.schema.json`. Bind the exact queue action
SHA, 05 package SHA, deliverable-manifest SHA, post IDs, platforms, actions,
asset paths, and live asset hashes. Record the Founder statement as
`approval_source`; never paraphrase it into broader authority.

Refresh the session after writing the approval:

```bash
scripts/idol-video-python scripts/idol_social_release_session.py refresh \
  --session RUN_ROOT/review/social-release-session-v1.json \
  --at ISO_8601_KST \
  --apply
```

If the approval is exact, continue from `next_action` without asking the same
question again.

### 5. Route The Approved Delivery

- `manual_draft_upload`: re-run the local release projector with the exact
  approval and prepare the manual package. No external action is implied.
- `platform_draft_upload`: run the value-free auth status once, dry-run the
  exact platform uploader, and execute only if the current Founder reply
  explicitly grants that external action. Never retry an ambiguous started
  attempt.
- `public_publish`: use only the platform-specific approved path. Do not infer
  public authority from a draft approval.
- Instagram remains manual where the registered adapter says so. X uses its
  dedicated hash-bound route; do not send it through the TikTok/YouTube draft
  runner.

Store results in the existing queue/tracker/log owners, then refresh the same
session. Do not create a second queue for a successful result update.

### 6. Close Publication, Web, And Analytics Together

After a real public URL and actual `published_at` exist, author the run-owned
closeout record and use `scripts/idol_social_public_closeout.py` for supported
TikTok, YouTube, YouTube Shorts, or Instagram publications. This atomically
updates:

- `analytics/records/platform-posts.jsonl`;
- `web/data/signalDeckPublications.json`;
- the title output registry;
- a run-owned result with T+24h, T+72h, and T+7d due times.

The Signal Deck closeout currently accepts only an already registered MV track
or CF mapping with exact Web visual lineage. For member/process/general social
content without that mapping, do not invent an MV/CF target and do not modify
the in-progress Web platform lane. Record `Web mapping required` once and keep
the social/analytics closeout valid. Web deploy remains a separate explicit
Founder action.

Refresh the session after closeout. A published row without the local ledger
and eligible Signal Deck projection is incomplete evidence, not “done.”

### 7. Run The Analysis Loop Without Relabeling Evidence

The scheduled collector may run exactly once for the due fixed checkpoint.
If preflight or ledger validation fails, stop and return one blocker brief; do
not retry in the same wake. Only `T+24h`, `T+72h`, and `T+7d` are fixed windows.
Backfills, current observations, or Studio exports with a `snapshot_id` remain
non-checkpoint snapshots and must not receive a `measurement_window` value.

After valid collection:

1. validate `platform-posts.jsonl` and `platform-metrics.jsonl`;
2. refresh the run social-evidence snapshot;
3. run the Loom cohort analysis only on eligible current facts;
4. update the Signal Deck traffic view only when source evidence changed;
5. refresh the same session;
6. wake the Founder only for a decision-changing finding or a real blocker.

Do not infer publication from a plan/draft row. Do not infer conversion,
revenue, or performance from views alone.

## Efficiency Guards

- One canonical mixed-platform queue per batch; platform adapters consume
  filtered views of it.
- One session pointer; no broad run scan after registration.
- Compare the session state digest before any rebuild. Unchanged means no
  rewrite, no duplicate validation report, no Founder message.
- Hash the finished bytes once per material change; reuse the bound digest for
  plan, approval, upload, and closeout checks.
- Run credential checks only immediately before an approved external action.
- Do not build or deploy Web when only captions, approvals, or metric due times
  changed.
- Do not rerun the metric collector after a failed single permitted attempt.
- Preserve stale approvals as evidence but exclude them from current authority.
- One correction invalidates only affected action truth; do not rewrite
  unrelated copy or repackage unchanged assets.

## Return Format

Keep Founder-facing output short:

1. current state and whether anything changed;
2. the one decision packet path;
3. the one required reply or fact;
4. what will automatically resume after it;
5. explicit statement that external actions performed are zero unless an exact
   approved external execution actually completed.
