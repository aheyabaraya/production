# Grok Handoff Flows

Use this folder as the top-level Grok handoff entrypoint by harness step first,
then by workflow. Dates stay in the run-owned package path.

This folder governs only an actual cross-surface handoff. It does not govern a
Founder-selected Grok harness owner, who follows the shared root ritual, stage
schema, and owning IDOL-native skill directly.

Grok handoff routes are dormant by default. Prepare or refresh a Drive/Grok
handoff only when the founder explicitly asks for Grok, Grok Imagine, Grok
TUI/CLI, or Drive handoff. Handoff packets should extract the important source
facts from run-owned handoff material instead of forwarding broad source dumps.

## Active Harness Flows

- `02B/image-prompts/GROK-IMAGE-LOCAL-SOURCE.md`: Founder-requested Grok
  still-image execution adapter for one already-authored 02B request. Current
  or historical scope, input contract, attachment roles, and native-tool
  selection live in that runbook; do not copy its schema version or attachment
  rules here. Preserve approved prompt bytes without creative rewriting.
- `03-review/video-prompts/`: a cross-surface post-review video-prompt handoff
  after the typed Production Cut Review passes. It reuses the same common 03V source snapshot and
  compact per-cue projection. A Grok active owner writes the canonical prompt
  under the run folder through the shared skill, without this handoff. Mirror the
  validated prompt set to `drive-sync/02_GPT_GROK_HANDOFF/03-review_TITLE_SONG_KEY_video-prompts/CONTENT_ID/`
  only when the founder asks for manual transfer.
- `CF-code`: frozen historical ad-mode handoffs, not a current production
  start. Historical CF package:
  `../../../../../archive/cf-legacy-20260909/README.md`. Current teaser
  direction: `../../../teaser/AGENTS.md`. Do not load archived CF instructions
  or edit archived prompt packets. Drive sync packets under
  `drive-sync/02_GPT_GROK_HANDOFF/` remain manual-transfer copies when that
  historical material is retrieved, not canonical source of truth.

Run-owned source packages still live under:

```text
runs/YYYY-MM-DD/CONTENT_ID/handoff/
```

The flow bridge points to the correct run-owned package. Old
`02-03-grok-imagine-*` WebP folders remain historical compatibility packages;
they are not the active `/image` prompt-authoring route and must not be rebuilt
or treated as canonical source truth.

After founder pass, Codex may run the pass harness for validation/reporting, but
it must not stage the Drive/Grok copy unless the founder asks for it.

```text
ruby scripts/idol_founder_pass_harness.rb runs/YYYY-MM-DD/CONTENT_ID --title-key TITLE_SONG_KEY --pass-date YYYY-MM-DD --write
```

Founder-requested legacy 02-03 Grok Imagine Drive staging, only when the
Founder explicitly asks to recover or use an already-built compatibility
package:

```text
ruby scripts/idol_founder_pass_harness.rb runs/YYYY-MM-DD/CONTENT_ID --title-key TITLE_SONG_KEY --pass-date YYYY-MM-DD --sync-grok-imagine --founder-requested --write
```
