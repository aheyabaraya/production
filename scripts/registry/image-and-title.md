# 02B prompt, image-generation preparation, title assets, and output registry

Machine source: `automation/idol-script-registry.yaml`.

Use only exact 02A/02B lineage and current-title bindings. Compile or prepare requests without paraphrasing authored prompts; generation and paid action stay behind their explicit gates.

Authority boundary: The image model guard is gpt-image-2-only. Face-only identity lanes and historical packet fallbacks are forbidden.

Route: passed 02A/02B lineage → exact current-title inputs → prompt/request preparation → paid-generation and pixel gates.

## Registered scripts

- `scripts/idol_02b_batch_api_runner.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_build_two_cut_source_manifest.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_cut_keyframe_batch_api_runner.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_execute_image_generation_request.py` — status: `active`; authority: `founder_approved_external_write`.
- `scripts/idol_export_02b_prompt_manifests.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_luna_to_grok_section_transfer.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_dispatch.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_request_selection.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_section_worklist.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_image_generation_section_worklist_v7_legacy.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_openai_image_model_policy.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_image_generation_request.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prepare_image_generation_request_v8_legacy.rb` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_prepare_image_render_correction.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prompt_packet_compile.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_prompt_packet_section_merge.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_split_beat_source_manifest_by_section.py` — status: `historical`; authority: `historical_evidence_only`.
- `scripts/idol_title_output_registry.py` — status: `active`; authority: `mechanical_default`.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
