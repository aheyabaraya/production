# IDOL Studio Record-Bus Boundary

Status: disabled by default
Scope: Notion IDOL Studio, Drive `IDOL_STUDIO`, Grok Bot studio roles, Slack
studio rooms, and accepted-stage progress recording only
Authority: this page grants no write, upload, dispatch, promotion, release, or
external-mutation permission

This page closes the conditional safety route named by `AGENTS.md`. It does not
activate an IDOL Studio lane and is not part of ordinary PRE-00 -> 05 startup.
The local repository remains the source of truth.

## Activation

Do not load or use this route during ordinary MV authoring. It activates only
when the Founder explicitly opts in to one exact current task involving Notion
IDOL Studio, Drive `IDOL_STUDIO`, a Grok Bot studio role, Slack studio rooms, or
accepted-stage progress recording.

Activation must name the target service, exact record or room, allowed action,
current run/stage, source artifact path and SHA-256, and whether an external
write is authorized. A general request to continue production, use Grok CLI,
or improve Graph Engineering is not activation. Missing exact authority is HOLD.

## Local Versus Grok Bot Writes

Local canonical creative truth is authored, reviewed, promoted, and tracked in
this repository under the ordinary owner and Founder gates. Grok CLI or Grok
Bot transport cannot become a canonical owner, infer a Founder decision, or
silently mirror local work to an external system.

An activated record-bus write may exact-copy only the reviewed stage-progress
fields and pointers explicitly authorized for that task. It must retain the
local source path, SHA-256, run, stage, owner, decision epoch, and write receipt.
No provider fallback is allowed. A failed external write leaves local truth
unchanged and returns HOLD.

## Talk, Record, And Build

Conversation, record keeping, and creative production are separate actions.

- Talking in a studio room does not create canonical truth or a Founder lock.
- Recording an accepted milestone does not reopen, summarize away, or promote
  creative bytes.
- Building the MV stays on the active IDOL-native production route and its
  Department Dispatch, Goal, Role Context Pack, review, and promotion gates.
- External upload, paid generation, public release, and destructive cleanup
  each require their own explicit authority.

After an accepted stage closeout, at most one bounded
`stage_progress_recorder` worker may exact-copy the authorized milestone. Raw
worker pools, private reasoning, full transcripts, secrets, and unrelated run
artifacts are excluded.

## Isolation From Production

This record-bus boundary adds no stage, role, schema family, current-next row,
creative owner, promotion authority, or automatic continuation. Ordinary MV
startup does not read Studio records and Studio availability cannot satisfy a
production input, source, pixel, playback, Founder, or release gate.

When the route is inactive, perform no Notion, Drive, Grok Bot, or Slack write.
When activated, preserve one-way exact-pointer lineage from reviewed local
truth to the external record and never import external record prose as current
creative truth without a separate, explicit source-intake decision.
