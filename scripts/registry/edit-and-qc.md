# 04 edit source, marker, recipe, FX, QC, and worklists

Machine source: `automation/idol-script-registry.yaml`.

Use explicit run/edit inputs, preserve frame/audio/source hashes, and stop on playback or recipe drift. Worklists are diagnostics and do not promote an edit.

Authority boundary: Final package and release readiness require the active 04 closeout, playback/QC evidence, and Founder/public gates.

Route: explicit 04 source/edit map → marker/recipe/FX/QC → manual playback → package handoff.

## Registered scripts

- `scripts/idol_04fx_compile_recipe_effects.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_04fx_transition_opportunity_seed.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_delivery_qc.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_marker_contact_sheets.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_readiness_worklist.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_edit_recipe_alignment_evidence.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_ffmpeg_revise_render.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_video_sync_workbench.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_audio_motion_director_map.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_finishing_fx.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_finishing_fx_compile.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_map_readiness.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_marker_plan.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_edit_recipe.py` — status: `active`; authority: `mechanical_default`.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
