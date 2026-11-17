---
name: idol-track-poster
description: |
  IDOL-native skill for creating track-specific poster and key visual assets.
  Full-body or strong 3/4 hero images that turn a selected Front Planning
  current-title member/background visual plan into reviewable album assets.
  These are the official representative visual assets / key art for each track,
  designed to carry member appearance and title identity into later MV work.
  Use it inside Front Planning to test candidates, then promote a selected asset
  only after the Founder passes it and Front Planning integrates its exact
  current-song consequence by path and hash.
---

# IDOL Track Poster

Create high-quality, track-specific full-body (or strong 3/4) poster and key visual images that serve as the official visual identity for that track.

These "Track Posters" are meant to be the main representative visual assets for an album/track — used for key art, website heroes, social campaign main images, physical goods, etc.

They sit between the clean neutral member portraits and the actual MV production stills.

This is the canonical IDOL skill for both `track poster` and `track key visual`
requests. Older "track key visual" wording routes here; do not maintain a
separate key-visual skill.

## Read / Write Contract

- Status: active canonical track poster/key-visual and current-title hero-asset
  lane.
- Required reads: read this `SKILL.md`,
  `modules/how-to-generate-with-references.md`, `modules/identity-guard.md`,
  `modules/prompt-approach.md`, `modules/visual-contract.md`, required member
  identity assets, the latest `research/front-planning-readiness-vN.yaml` when
  it exists, and the selected Front Planning plan/canvas plus every assigned
  reference's bound interpretation. Open an assigned actual visual source only
  when its `inspection_action` requires inspection or it is an approved
  generation attachment.
- Allowed outputs: Founder-reviewed candidates under the run-owned Front
  Planning/Grok generation lane. Promote one selected track poster or key visual
  under `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` or
  `assets/tracks/ALBUM_KEY/TITLE_KEY/posters/` only after Founder PASS and
  Front Planning integration, then update its current-title-package manifest
  and readiness entry.
- Forbidden outputs: 01/02A/02B/03V/04 graph-engineering artifacts, image-generation
  manifests, prompt-packet exports, catalog registration, or
  package/social promotion unless the Founder separately asks for that work.
- Registry behavior: none by default; poster/key-visual registry promotion is a
  separate task.
- Founder gates: founder approval is required for paid generation, external
  upload/sync, candidate selection, Front Planning integration, canonical asset
  promotion, registry promotion, or replacement of an existing canonical key
  visual.

## Core Philosophy

- **Track posters are grounded asset-production jobs, not free generations.**
  Use exact Founder-approved identity and visual sources to make the
  current-title member visual. A clean member profile may be used inside this
  asset-production job when no current-title source exists. Those production
  inputs do not become direct 02A or 02B attachments: the passed current-title
  member visual is the downstream appearance source.

- **Member identity is sacred** — the assigned current-title identity/track-
  poster author under CDD consumes the bound identity meaning before authoring.
  One explicitly authorized bounded forensic adviser may inspect the character
  board and current-title identity source locally for one named actual-pixel
  risk, then returns evidence only to the assigned author and CDD. The adviser
  does not author prompt prose, select a candidate, or promote an asset.
  Which files may be
  attached externally is a separate provider/security decision; never turn a
  local planning read into implied upload permission.

- **The track's visual spine lives in the image** — a Front Planning
  candidate tests
  the selected Front Planning world, wardrobe/material intent, body/object
  language, and actual references. A canonical asset must express the passed
  Front Planning current-title package; the candidate does not become its own
  parallel creative truth.

- **Poster utility first** — the image must work as a strong, readable, iconic still at multiple sizes.

## Phase-Aware Source Materials

1. Front Planning candidate lane
   - latest `research/front-planning-readiness-vN.yaml`
   - selected Front Planning plan/canvas and its current key-visual/space/object
     intent
   - every assigned actual visual/space/object/camera reference with canonical
     path/SHA-256 and its matching Front Planning receipt id
2. Front Planning lock and promotion lane
   - `current_title_visual_package` — title-local member, background/space,
     object/material, and section-use assignments
   - selected candidate path/hash and exact current-song consequence
   - Founder PASS plus updated package manifest/readiness
   - no separate 01A or 02 confirmation artifact

3. Asset-production identity sources
   - `assets/members/Mxx/character-board.png` (or .PNG) — **master face + full body proportion lock**. This is the single source of truth for identity.
   - Current-title album identity-source copy from
     `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` when
     `current_title_visual_identity` or its asset manifest declares it.
   - Current clean base portrait — asset-production fallback only when no
     current-title source exists; never a direct 02B attachment.

4. Supporting when available or required by the current phase
   - 00A song lock and exact selected audio
   - current Front Planning member/section roles and selected references

## Reference And Provider Policy — Current-Title Source First

- Track poster generation **must** start from the current-title album identity
  source when declared by `current_title_visual_identity` or its asset manifest.
  Use the base member approved profile photo only as fallback.
- One explicitly authorized bounded forensic adviser may inspect both the
  character board and current-title identity source locally for one named risk;
  the assigned current-title identity/track-poster author under CDD then
  authors the track-specific prompt from the active phase source:
  the selected Front Planning plan/canvas and current-title visual-package
  truth. Consume the
  selected visual references' bound interpretations; inspect their pixels only
  when `inspection_action` requires a new/revised receipt. The adviser returns
  observable facts and a reversible technical pass/hold/rerun only; scripts or templates
  may not fill pose, camera, space, wardrobe, or creative prompt sentences.
- Keep every unselected result noncanonical and run-owned. Founder selection
  identifies the candidate that Front Planning must integrate; selection alone
  does not authorize canonical promotion or use as an album visual lock. CDD
  reviews the exact integrated bytes, and Overall alone promotes the approved
  boundary.
- Grok/native candidate generation uses the Front Planning workbench's
  hash-bound `grok-imagine-job` I2I path. Attach only the exact parent assets
  reviewed for that single Founder-approved job; the result remains a candidate
  until explicit selection.
- Codex image generation uses `gpt-image-2` only. The repository has no standing
  track-poster upload allowlist: keep the request local unless the Founder
  creates an exact current-job allowlist. Do not attach a character board or
  other non-allowlisted image merely because it was read locally.
- The compact prompt says that attached current-title member visuals control
  appearance continuity, then spends its detail on the track world, space,
  pose/action, camera/composition, material/light integration, and reject drift.
  Do not paste a face-taxonomy inventory already proved by the images.
- Generating the face from text description alone is strictly forbidden.
- After promotion, 01 and 02A consume only the current-title package entry.
  Character boards, clean profiles, and face-only production sources must not
  travel as separate 02B inputs.

Reference interpretation is not a separate poster cache. The first owner-row
`interpretation_receipt` is indexed by Front Planning and remains the semantic
truth through prompt authoring. A model/session change never reopens it; the
allowed reopen triggers, revision, and downstream invalidation follow
`policies/harness-routing-and-sources.md`. Contact-sheet work receives the
selected cell/crop only, while the original remains provenance and any
separately approved attachment source.

This is the core rule of this skill. See `modules/identity-guard.md` for the exact mandatory wording you must use in every prompt.

## LOW Historical Example

These LOW assignments are historical evidence for asset depth only. They are
not current-title defaults and never transfer into another title without that
title's own passed Front Planning package.

- **M03 Yeul**: compact_pressure lead — fitted dark base, cropped shirt-bolero or utility outer, narrow tie/strap line, sharp low-gaze silhouette, grounded footwear, compact hardware.
- **M01 Saeyan**: scarf_tail_motion lane (fitting her First Signal / airy prism identity) — fitted base + one controlled thread/scarf element that can react to movement, light signal cue in the cold airport world.
- **M02 Serin**: compact_pressure or clean utility lane — precision mirror line, controlled silhouette, clean hardware details.

These assignments explain old example generations only.

## Output Expectations

- Strong full-body or three-quarter full-body framing
- The figure must feel physically present in one of the track's defined spaces
- Wardrobe must accurately apply the approved lane(s) for that member in that track
- One clear, powerful, static-readable pose or light action that hints at the track's movement language
- Lighting unifies the person and the environment (no beauty lighting the face separately)
- Works as poster/key art (good silhouette, readable gesture, strong composition)

## Folder & Naming (Recommended)

```
assets/members/album-assets/ALBUM_KEY/TITLE_KEY/
  or
assets/tracks/ALBUM_KEY/TITLE_KEY/posters/
```

Canonical filenames:
- `TITLEKEY_M01_track-poster.jpg`
- `TITLEKEY_M03_track-poster.jpg`

Do not accumulate `v1`, `v2`, `final`, and `final-final` assets. Candidate
history stays in its unique run-owned generation job; the selected canonical
file has one owner, and Git/manifest provenance carries revision history.

## Downstream Handoff

Use this order so the lane does not require its own future output as an input:

```text
selected Front Planning plan/canvas + actual references
-> run-owned candidates
-> Founder selects a candidate for integration
-> Front Planning records and passes its current-song world/wardrobe/role consequence
-> explicit canonical-asset promotion
-> current_title_visual_package + asset manifest path/hash update
-> 01 expansion -> 02A Branch-Cut binding when used
```

After Front Planning confirmation and explicit promotion, record the canonical asset's
path, SHA-256, member/space/object role, actual reference provenance, and
permitted uses in the Front Planning current-title package and its
asset manifest; keep semantic receipts in the separate interpretation index.
01 expands the passed direction, and 02A selects the smallest useful title
visual and scene-reference set for each Branch Cut. 02B preserves that combined
attachment order. Neither stage may rediscover or reinterpret an unselected
rough or unconfirmed candidate.

The key visual is an album/track identity anchor, not a mandate to repeat one
poster composition in every MV cut. 01 and 02A must vary space, camera, action,
and section function while preserving the selected visual system and identity.

See `modules/identity-guard.md` for the current local identity review and
provider-specific attachment boundary.

**Critical operational rule**: every track poster must be grounded in the
current-title identity source available to its approved asset-production job,
and downstream MV generation must use the passed current-title visual instead
of reopening those production inputs.

Read `modules/how-to-generate-with-references.md` and
`modules/identity-guard.md` before generating. They define actual-reference
inspection, model-authored compact prompting, provider approval, and output
review; they are not copy-paste prompt templates.

The earlier text-only test generations are archive evidence, not an active
quality precedent. Active work uses actual selected references and the
provider-specific approval boundary above.
