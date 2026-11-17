# Grok Video Prompt Pre-Flight Checklist

**Project**:
**Request Packet**:
**Date**:
**Grok Operator**:

This checklist is a companion to the single Grok CLI source runbook. It does
not replace or restate the workflow.

Primary runbook:

```text
handoff/grok/flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md
```

## Required Checks

- [ ] I opened the request packet and paste trigger.
- [ ] I opened the primary runbook above.
- [ ] I opened the compact brief named in the request, if present.
- [ ] I opened the run-owned `handoff/grok-video-prompt-reference-pack-*.yaml`.
- [ ] I confirmed the active run path and output root.
- [ ] I confirmed I will process only records with a passed typed Production
      Cut Review and a ready Audio Production-Cut Placement.
- [ ] I confirmed every new prompt uses `selected_skill: idol-video-prompt`.
- [ ] I confirmed Drive sync is not an output source and will not be updated
      unless Codex/founder explicitly asks for Drive/manual transfer.

## Per-Cue Checks

- [ ] Actual visual lock image opened.
- [ ] Matching cue sheet row/board opened.
- [ ] Typed Production Cut Review, the Generated Branch-Cut Review when the
      source is a Branch, Audio Production-Cut Placement, and the matching 03V
      storyboard-assist board opened.
- [ ] Motion count guide opened when present.
- [ ] Audio motion / cue BPM map opened when present.
- [ ] Prompt file will be written under the run-owned
      `generations/video-prompts/` folder and indexed by the active
      `idol_video_prompt_manifest.v8` artifact.

## Completion

Return prompt count, index path, skipped cues, and open decisions. If this
checklist is copied into a request folder, save it as
`pre-flight-checklist-YYYY-MM-DD.md`.
