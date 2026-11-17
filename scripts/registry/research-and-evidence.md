# Audio, reference, source, and measurable evidence routes

Machine source: `automation/idol-script-registry.yaml`.

Use only local registered sources unless the exact current task grants external permission. Measurement and source registration preserve evidence; they do not select references or author screen meaning.

Authority boundary: Official/original source defaults and Founder permission requirements remain in the linked source policies; restricted-source absence is a HOLD.

Route: local registered source → permission/origin check → measurable evidence → owner review; never jump from measurement to screen meaning.

## Registered scripts

- `scripts/idol_01r_reference_gap_worklist.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_audio_precision_markers.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_bilibili_reference_fetch.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_candidate_audio_probe.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_compile_brief_cards.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_cue_bpm_map.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_measure_sequence_motion_timeline.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_sequence_motion_analysis.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_audio_metrics.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_catalog_lookup.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_comparison_packet.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_evaluation.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_hub.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_intro_audio_metrics.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_reference_music_feature_extract.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_reference_section_segments.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_analysis_registry.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_sequence_unit_registry.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_hub_audit.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_reference_segments.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_worldcup_reference_audio_instrument_probe.py` — status: `one_off`; authority: `one_off_measurement_only`.
- `scripts/validate_reference_interpretation_contract.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_reference_management_catalog.py` — status: `active`; authority: `mechanical_default`.
- `scripts/yt-dlp-bilibili.sh` — status: `active`; authority: `founder_permission_external_capture`.
- `scripts/yt-dlp-instagram-reference.sh` — status: `active`; authority: `founder_permission_external_capture`.
- `scripts/yt-dlp-youtube-reference.sh` — status: `active`; authority: `founder_permission_external_capture`.

Reference comparison packets: `scripts/idol_reference_comparison_packet.py` is deterministic preparation. It binds named lookup candidates and window or individual evidence pointers, verifies contained paths and the exact five-frame one-second Sequence contract, and never ranks, selects, scores diversity, infers a semantic event, authors an observation, or grants creative PASS. Reference evaluation: `scripts/idol_reference_evaluation.rb` plus `scripts/lib/idol_reference_evaluation_contract.rb` check case/review structure and exact source binding against `schemas/reference-evaluation.schema.json`. Pixel meaning remains human or assigned-model judgment. Mechanical completeness is not production PASS. Do not treat model-written observations as machine fact. Optional benchmark fixtures are not an installed default.

Sequence-window machine measurement stays on the existing SMA pipeline. Use the registered multi-index local pointer lookup for a named gap: narrow metadata and alternatives first, then inspect survivor pixels or playback. Preserve distinct functional use. Do not choose a numeric winner or a source-count quota. If an exact admitted continuous-video boundary exists and a temporal gap warrants it, the existing sequence-motion worker may run `scripts/idol_measure_sequence_motion_timeline.py` through `scripts/idol-video-python` on that bound source window before authoring SMA. Required flags: `--repo-root`, `--video`, `--output`, `--admitted-start`, `--admitted-end`, `--sample-times` (exactly five comma-separated timestamps at one-second cadence). Optional: `--cache-dir`, `--analysis-width` (default 160), `--analysis-height` (default 90), `--luma-delta-candidate-threshold` (default 0.25), `--window-end-pad-seconds` (default 0.05), `--force-refresh`. The responsible owner selects `--output`; that path must resolve inside the owning repository and the actual run/task authorized scope. Do not invent an automatic production run path. Normal reversible test outputs in that scope are authorized. Omitting `--cache-dir` uses `_machine-cache` beside that selected `--output` parent. The measurement script produces only the diagnostic artifact. The research generalist may optionally bind its path and SHA-256 in `continuous_motion_source_review.machine_measurement_binding`. The existing sequence-motion validator consumes that optional binding. `idol_prepare_sequence_motion_analysis.rb` remains SMA exact-copy transport only. If the video is unavailable, do not fabricate a binding; existing typed inference or HOLD remains. Then the model authors the semantic SMA; the preparer exact-copies, the validator checks, and CDD reviews. Measurement supplies optical-flow, discontinuity, and decoded-PTS diagnostics only. It cannot resolve camera-versus-subject or pan/orbit semantics, cannot pick an automatic Major or Sequence winner, and creates no stage, quality score, or automatic transition.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
