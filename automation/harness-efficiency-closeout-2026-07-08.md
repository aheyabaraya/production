# IDOL Harness Efficiency Closeout - 2026-07-08

## Scope

This closeout records the July 8 maintenance pass for the song/MV harness:
skill routing, schema-level judgment criteria, common automation helpers,
artifact ownership, reference/contact-sheet handling, and the 04 edit bridge.

The pass intentionally leaves current run outputs, CF-code material, and
in-flight generated assets untouched except where already owned by their
separate production tasks.

## Result

Pass for the core IDOL song/MV harness.

No new top-level harness stage is needed. The stable shape remains section-
gated work inside existing artifacts, then one merged canonical artifact per
stage.

## Decisions Closed

- `idol-mv-director` is the canonical 01 director lane. The old
  `idol-song-choreography-performance-mv` name remains only as a compatibility
  alias for older prompts, run artifacts, and the legacy-named
  `01-song-choreography-performance-mv-map.yaml` output.
- `idol-choreography-performance` is the separate body/performance specialist.
  It is called only when a selected section needs dance, formation, body-action,
  performance blocking, or camera-readable body evidence.
- Story-led MV direction is now explicit in schema fields:
  `director_storyline_spine`, `camera_directing_strategy`,
  `storyline_director_function`, `camera_coverage_intent`, and
  `choreography_collaboration`.
- 02A/02B camera carry now preserves `storyline_alignment`, so camera variety
  must explain what it changes for viewer information, object state, member
  relation, emotional consequence, or transition state.
- The 01 director skill was slimmed back into a router-style `SKILL.md`; detailed
  section field coverage and closeout checks live in
  `references/01-bundle-authoring-detail.md` and schemas.
- Common mechanical work is already assigned to reusable scripts:
  schema/semantic validators, audio evidence extractors, contact-sheet builders,
  export/preflight helpers, title registry tools, 03V worklists, and 04 edit/QC
  helpers. No new script was added in this pass.
- 04 edit remains structurally sound. It already rejects mechanical upstream
  seconds and now has story-flow, space/visible-feeling, and directorial
  transition fields to preserve upstream directing logic without taking exact
  cutpoints away from 04.

## Automation Boundaries

Automation may check presence, schema shape, path existence, pointer integrity,
contract carry, script registry coverage, and nonblocking repetition profiles.

Automation must not choose story meaning, reference function, contact-sheet
interpretation, choreography quality, camera originality, melody/instrument
function, exact 04 source timing, founder pass/hold/reject, or paid generation
approval.

## Watch Items

- `idol-generation` is now the largest harness-core `SKILL.md` after the 01
  split. It remains acceptable because its detailed 02/02A/02B logic is already
  in linked references, but it is the next candidate for router slimming when it
  is edited for a real generation-lane reason.
- Legacy-named beat-source scripts and schemas remain compatibility surfaces.
  Operator-facing text should say cut/keyframe or legacy beat-source, not treat
  beat ids as active screen-event units.
- Existing run artifacts created before this pass may not contain the new
  story/camera fields. `idol_harness_state_check.rb` reports those fields as
  nonblocking visibility lines so old artifacts stay readable while new runs
  can adopt the stronger criteria.
- Reference-library promotion should remain reviewed and selective: ordinary
  current-run source notes stay in the run; only repeatedly useful source
  functions or source caches move into `source-materials/**` or
  `reference-library/**`.

## Validation Surface

Use this set after related harness edits:

```text
ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "ok #{path}" }' schemas/song-choreography-performance-mv-map.schema.json schemas/master-storyboard.schema.json schemas/prompt-packets.schema.json schemas/single-cut-beat-source-generation-manifest.schema.json schemas/two-cut-beat-source-generation-manifest.schema.json
ruby -c scripts/idol_harness_state_check.rb
ruby -c scripts/idol_prepare_video_prompt_authoring.rb
ruby scripts/idol_script_registry_check.rb
ruby scripts/idol_skill_contract_matrix.rb --strict
ruby scripts/validate_terminology_guard.rb
ruby scripts/idol_harness_state_check.rb runs/2026-07-05/0705_GIRL_BADUK_WORLD_SIGNAL --album-key aurora-m --title-key one-move
```
