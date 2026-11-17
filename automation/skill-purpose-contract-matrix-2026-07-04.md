# IDOL Skill Purpose Contract Matrix

generated_at: 2026-08-08T17:38:43+09:00
status: `pass`

This report checks whether each IDOL skill exposes a purpose-specific read contract, schema/reference pointers, and write/output boundaries. It does not validate creative quality by itself; it highlights where automation can or cannot rely on machine-readable contracts.

## Summary

- harness-core: 18
- isolated-helper: 11
- uncategorized: 7
- issues_or_schema_gaps: 0

## Findings

- No contract gaps detected by this matrix.

## Matrix

| skill | mode | read contract | output boundary | schema refs | local refs | write refs |
| --- | --- | --- | --- | --- | --- | --- |
| `idol-choreography-board` | uncategorized | Required Reads | yes | none | none | none |
| `idol-choreography-performance` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/harness-section-slice.schema.json`<br>`schemas/master-storyboard.schema.json`<br>`schemas/song-choreography-performance-mv-map.schema.json` | `modules/choreography.md`<br>`modules/performance-direction.md` | none |
| `idol-edit-finishing-fx` | harness-core | Required Reads | yes | `schemas/edit-finishing-fx-compile-manifest.schema.json`<br>`schemas/edit-finishing-fx.schema.json`<br>`schemas/edit-map.schema.json`<br>`schemas/edit-recipe.schema.json` +1 | `references/ae-like-effect-map.md`<br>`references/local-ffmpeg-transition-effect-catalog.md`<br>`references/professional-edit-effect-casebook.md` | none |
| `idol-editing-qc` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/edit-cutpoint-sheet-manifest.schema.json`<br>`schemas/edit-delivery-qc.schema.json`<br>`schemas/edit-finishing-fx.schema.json` +6 | `references/editing-qc-detail.md`<br>`references/professional-edit-decision-casebook.md` | none |
| `idol-front-planning-development-block` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/harness-section-slice.schema.json`<br>`schemas/master-storyboard.schema.json` | `references/02a-coverage-authoring-detail.md` | none |
| `idol-front-planning-director` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/director-dispatch-index.schema.json`<br>`schemas/front-planning-readiness.schema.json`<br>`schemas/html-review-board.schema.json` +2 | `references/director-operating-contract.md`<br>`references/founder-visual-review-board-contract.md`<br>`references/founder-visual-review-board/`<br>`references/founder-visual-review-board/examples/su-member-visual-reference-connection-board-v1.html` | none |
| `idol-front-planning-handoff` | isolated-helper | Required Reads | no | none | `references/file-contract.md`<br>`references/reference-reuse-handoff-example.md` | none |
| `idol-generation` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/image-generation-request.schema.json`<br>`schemas/master-storyboard.schema.json`<br>`schemas/prompt-packet-delta.schema.json` +2 | `references/02a-preview-harness-handoff.md`<br>`references/image-render-correction-fast-lane.md`<br>`references/prompt-packet-compile-detail.md` | none |
| `idol-grid-overlay` | isolated-helper | Read / Write Contract | yes | none | none | none |
| `idol-human-face-realism-control` | isolated-helper | Required Reads | yes | none | `references/face-memory-point-taxonomy.md`<br>`references/score-to-prompt-translation.md` | none |
| `idol-member-teaser-portrait` | isolated-helper | Read / Write Contract | yes | none | none | `assets/member-registry.yaml` |
| `idol-member-visual-identity` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json` | `references/character-card-contract.md`<br>`references/character-card-prompt-field-guide.md` | `assets/member-registry.yaml`<br>`assets/members/face-only-upscale-manifest.json` |
| `idol-mv-concept-research` | uncategorized | Required Reads | yes | none | `references/candidate-set-quality-contract.md`<br>`references/source-genealogy-method.md` | none |
| `idol-mv-director` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/harness-section-slice.schema.json`<br>`schemas/master-storyboard.schema.json` | `modules/choreography.md`<br>`modules/performance-direction.md`<br>`modules/screen-flow-wardrobe.md`<br>`modules/song.md` | none |
| `idol-nucleus` | harness-core | Required Reads | yes | `schemas/front-planning-readiness.schema.json`<br>`schemas/song-lock.schema.json` | none | none |
| `idol-orchestrator` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json` | `references/orchestration-routing-detail.md`<br>`references/provider-neutral-studio-kernel.md` | none |
| `idol-photoreal-human-face-lock` | isolated-helper | Required Reads | yes | none | `references/founder-face-source-function-bank-v1.md`<br>`references/openai-image-prompt-contract.md`<br>`references/photoreal-human-face-control-taxonomy.md` | none |
| `idol-pinterest-reference-worker` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/harness-section-slice.schema.json`<br>`schemas/reference-working-index.schema.json` | `references/pinterest-section-comparison-detail.md` | none |
| `idol-reference-research-department` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/harness-section-slice.schema.json`<br>`schemas/reference-working-index.schema.json` | none | none |
| `idol-research-radar` | harness-core | Required Reads | yes | `schemas/pre-00-research-radar.schema.json`<br>`schemas/reference-song-fit.schema.json` | `references/research-radar-authoring-detail.md`<br>`references/weekly-visual-idol-report-contract.md` | none |
| `idol-review-board-coordinator` | harness-core | Required Reads | yes | `schemas/harness-section-slice.schema.json`<br>`schemas/html-review-board.schema.json` | none | none |
| `idol-shot-vfx` | uncategorized | Required Reads | no | none | `references/04vfx-manual-use-and-runtime.md`<br>`references/shot-vfx-catalog.md` | none |
| `idol-social-metadata-upload` | isolated-helper | Required Reads | yes | `schemas/platform-release-approval.schema.json`<br>`schemas/publishing-record.schema.json`<br>`schemas/signal-deck-publication.schema.json` | none | none |
| `idol-song-choreography-performance-mv` | uncategorized | Read / Write Contract | yes | none | none | none |
| `idol-song-lock` | harness-core | Required Reads | yes | `schemas/audio-motion-director-map.schema.json`<br>`schemas/department-dispatch.schema.json`<br>`schemas/selected-audio-analysis.schema.json`<br>`schemas/song-lock.schema.json` | `references/selected-audio-song-lock-detail.md` | none |
| `idol-suno-prompt` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/reference-song-fit.schema.json` | `references/suno-prompt-authoring-detail.md` | `assets/voice-style-index.md` |
| `idol-surgical-face-architecture` | isolated-helper | Required Reads | yes | none | `references/compact-prompt-compiler.md`<br>`references/surgical-face-axis-taxonomy.md` | none |
| `idol-track-key-visual` | uncategorized | Read / Write Contract | yes | none | none | none |
| `idol-track-poster` | isolated-helper | Read / Write Contract | yes | none | `modules/how-to-generate-with-references.md`<br>`modules/identity-guard.md`<br>`modules/prompt-approach.md`<br>`modules/visual-contract.md` | none |
| `idol-video-prompt` | harness-core | Required Reads | yes | `schemas/audio-branch-cut-placement.schema.json`<br>`schemas/department-dispatch.schema.json`<br>`schemas/review.schema.json`<br>`schemas/video-prompt-manifest.schema.json` +1 | `references/storyboard-assisted-branch-cuts.md` | none |
| `idol-video-reference-hub` | uncategorized | Required Reads | yes | `schemas/department-dispatch.schema.json` | `references/video-reference-analysis-example.md` | none |
| `idol-world-still-reference-department` | harness-core | Required Reads | yes | `schemas/department-dispatch.schema.json`<br>`schemas/reference-working-index.schema.json` | `references/world-still-contact-sheet-contract.md` | none |
| `kling` | isolated-helper | Read / Write Contract | yes | none | `references/kling-prompt-authoring-detail.md` | none |
| `reels-tiktok-template` | isolated-helper | Read / Write Contract | yes | none | none | none |
| `source-faithful-teaser` | uncategorized | Required Reads | no | none | none | none |
| `x-posting-template` | isolated-helper | Read / Write Contract | yes | none | none | none |

## Interpretation

- Harness-core skills are mostly managed by `Required Reads`, schemas, and run-owned output paths.
- Retired/alias/external-helper skills are safer when they expose `Read / Write Contract` plus explicit forbidden outputs.
- Prose-only outputs are acceptable for isolated/manual work, but they are weak surfaces for minimum-intervention automation.

## Skill Size Inventory

This inventory is informational. It surfaces skills that may need router/reference
splitting during the next real edit, without turning line count into a readiness gate.

| lines | skill | mode | local refs |
| ---: | --- | --- | --- |
| 821 | `idol-front-planning-director` | harness-core | `references/director-operating-contract.md`<br>`references/founder-visual-review-board-contract.md`<br>`references/founder-visual-review-board/`<br>`references/founder-visual-review-board/examples/su-member-visual-reference-connection-board-v1.html` |
| 599 | `idol-social-metadata-upload` | isolated-helper | none |
| 533 | `x-posting-template` | isolated-helper | none |
| 456 | `idol-orchestrator` | harness-core | `references/orchestration-routing-detail.md`<br>`references/provider-neutral-studio-kernel.md` |
| 447 | `idol-generation` | harness-core | `references/02a-preview-harness-handoff.md`<br>`references/image-render-correction-fast-lane.md`<br>`references/prompt-packet-compile-detail.md` |
| 421 | `idol-edit-finishing-fx` | harness-core | `references/ae-like-effect-map.md`<br>`references/local-ffmpeg-transition-effect-catalog.md`<br>`references/professional-edit-effect-casebook.md` |
| 414 | `idol-editing-qc` | harness-core | `references/editing-qc-detail.md`<br>`references/professional-edit-decision-casebook.md` |
| 383 | `reels-tiktok-template` | isolated-helper | none |
| 341 | `idol-research-radar` | harness-core | `references/research-radar-authoring-detail.md`<br>`references/weekly-visual-idol-report-contract.md` |
| 338 | `idol-video-reference-hub` | uncategorized | `references/video-reference-analysis-example.md` |
| 326 | `idol-photoreal-human-face-lock` | isolated-helper | `references/founder-face-source-function-bank-v1.md`<br>`references/openai-image-prompt-contract.md`<br>`references/photoreal-human-face-control-taxonomy.md` |
| 326 | `idol-video-prompt` | harness-core | `references/storyboard-assisted-branch-cuts.md` |
| 306 | `idol-mv-director` | harness-core | `modules/choreography.md`<br>`modules/performance-direction.md`<br>`modules/screen-flow-wardrobe.md`<br>`modules/song.md` |
| 283 | `idol-suno-prompt` | harness-core | `references/suno-prompt-authoring-detail.md` |
| 247 | `idol-mv-concept-research` | uncategorized | `references/candidate-set-quality-contract.md`<br>`references/source-genealogy-method.md` |
| 245 | `idol-reference-research-department` | harness-core | none |
| 228 | `idol-track-poster` | isolated-helper | `modules/how-to-generate-with-references.md`<br>`modules/identity-guard.md`<br>`modules/prompt-approach.md`<br>`modules/visual-contract.md` |
| 226 | `idol-member-visual-identity` | harness-core | `references/character-card-contract.md`<br>`references/character-card-prompt-field-guide.md` |
| 220 | `idol-shot-vfx` | uncategorized | `references/04vfx-manual-use-and-runtime.md`<br>`references/shot-vfx-catalog.md` |
| 219 | `idol-song-lock` | harness-core | `references/selected-audio-song-lock-detail.md` |
| 217 | `idol-choreography-performance` | harness-core | `modules/choreography.md`<br>`modules/performance-direction.md` |
| 193 | `idol-world-still-reference-department` | harness-core | `references/world-still-contact-sheet-contract.md` |
| 191 | `idol-front-planning-development-block` | harness-core | `references/02a-coverage-authoring-detail.md` |
| 178 | `idol-choreography-board` | uncategorized | none |
| 173 | `idol-member-teaser-portrait` | isolated-helper | none |
| 163 | `idol-front-planning-handoff` | isolated-helper | `references/file-contract.md`<br>`references/reference-reuse-handoff-example.md` |
| 150 | `source-faithful-teaser` | uncategorized | none |
| 148 | `idol-human-face-realism-control` | isolated-helper | `references/face-memory-point-taxonomy.md`<br>`references/score-to-prompt-translation.md` |
| 138 | `idol-surgical-face-architecture` | isolated-helper | `references/compact-prompt-compiler.md`<br>`references/surgical-face-axis-taxonomy.md` |
| 131 | `kling` | isolated-helper | `references/kling-prompt-authoring-detail.md` |
| 128 | `idol-pinterest-reference-worker` | harness-core | `references/pinterest-section-comparison-detail.md` |
| 89 | `idol-grid-overlay` | isolated-helper | none |
| 59 | `idol-review-board-coordinator` | harness-core | none |
| 54 | `idol-nucleus` | harness-core | none |
| 33 | `idol-track-key-visual` | uncategorized | none |
| 24 | `idol-song-choreography-performance-mv` | uncategorized | none |