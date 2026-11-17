# IDOL Skill Purpose Contract Matrix

generated_at: 2026-06-10T18:12:23+09:00
status: `pass`

This report checks whether each IDOL skill exposes a purpose-specific read contract, schema/reference pointers, and write/output boundaries. It does not validate creative quality by itself; it highlights where automation can or cannot rely on machine-readable contracts.

## Summary

- compat-alias: 1
- harness-core: 10
- isolated-helper: 6
- retired-stub: 3
- issues_or_schema_gaps: 0

## Findings

- No contract gaps detected by this matrix.

## Matrix

| skill | mode | read contract | output boundary | schema refs | local refs | write refs |
| --- | --- | --- | --- | --- | --- | --- |
| `idol-editing-qc` | harness-core | Required Reads | yes | `schemas/edit-map.schema.json`<br>`schemas/review.schema.json` | none | none |
| `idol-generation` | harness-core | Required Reads | yes | `schemas/audio-motion-director-map.schema.json`<br>`schemas/cue-bpm-map.schema.json`<br>`schemas/generation-map.schema.json`<br>`schemas/master-storyboard.schema.json` +5 | `references/02a-preview-harness-handoff.md`<br>`references/generation-authoring-detail.md`<br>`references/idol-imagegen-validation-contract.md`<br>`references/idol-prompt-packet-structure.md` +1 | `assets/member-registry.yaml`<br>`assets/voice-style-index.md` |
| `idol-grid-overlay` | isolated-helper | Read / Write Contract | yes | none | none | none |
| `idol-lyrics-direction-bridge` | harness-core | Required Reads | yes | `schemas/lyrics-direction-bridge.schema.json`<br>`schemas/selected-audio-analysis.schema.json` | none | none |
| `idol-member-teaser-portrait` | isolated-helper | Read / Write Contract | yes | none | none | `assets/member-registry.yaml` |
| `idol-nucleus` | harness-core | Required Reads | yes | `schemas/creative-nucleus.schema.json`<br>`schemas/lyrics-direction-bridge.schema.json`<br>`schemas/reference-song-fit.schema.json` | none | `assets/member-registry.yaml`<br>`assets/unit-registry.yaml`<br>`assets/voice-style-index.md` |
| `idol-orchestrator` | harness-core | Required Reads | yes | `schemas/audio-motion-director-map.schema.json`<br>`schemas/creative-nucleus.schema.json`<br>`schemas/edit-map.schema.json`<br>`schemas/generation-map.schema.json` +13 | none | none |
| `idol-research-radar` | harness-core | Required Reads | yes | `schemas/pre-00-research-radar.schema.json`<br>`schemas/reference-song-fit.schema.json` | `references/research-radar-authoring-detail.md` | `assets/member-registry.yaml`<br>`assets/unit-registry.yaml`<br>`assets/voice-style-index.md` |
| `idol-song-choreography-performance-mv` | harness-core | Required Reads | yes | `schemas/song-choreography-performance-mv-map.schema.json`<br>`schemas/track-visual-board.schema.json` | `modules/choreography.md`<br>`modules/integration.md`<br>`modules/mv-direction.md`<br>`modules/performance-direction.md` +3 | `assets/member-registry.yaml`<br>`assets/unit-registry.yaml`<br>`assets/voice-style-index.md` |
| `idol-song-lock` | harness-core | Required Reads | yes | `schemas/audio-motion-director-map.schema.json`<br>`schemas/cue-bpm-map.schema.json`<br>`schemas/lyrics-direction-bridge.schema.json`<br>`schemas/selected-audio-analysis.schema.json` +2 | `references/selected-audio-song-lock-detail.md` | `assets/member-registry.yaml`<br>`assets/voice-style-index.md` |
| `idol-suno-prompt` | harness-core | Required Reads | yes | `schemas/reference-song-fit.schema.json` | none | `assets/voice-style-index.md` |
| `idol-track-key-visual` | compat-alias | Read / Write Contract | yes | none | none | none |
| `idol-track-poster` | isolated-helper | Read / Write Contract | yes | none | `modules/how-to-generate-with-references.md`<br>`modules/identity-guard.md` | none |
| `idol-video-prompt` | harness-core | Required Reads | yes | `schemas/video-prompt-manifest.schema.json`<br>`schemas/video-prompt-section-qa.schema.json` | `references/video-prompt-authoring-detail.md` | none |
| `kling` | isolated-helper | Read / Write Contract | yes | none | none | none |
| `reels-tiktok-template` | isolated-helper | Read / Write Contract | yes | none | none | none |
| `x-posting-template` | isolated-helper | Read / Write Contract | yes | none | none | none |

## Interpretation

- Harness-core skills are mostly managed by `Required Reads`, schemas, and run-owned output paths.
- Retired/alias/external-helper skills are safer when they expose `Read / Write Contract` plus explicit forbidden outputs.
- Prose-only outputs are acceptable for isolated/manual work, but they are weak surfaces for minimum-intervention automation.