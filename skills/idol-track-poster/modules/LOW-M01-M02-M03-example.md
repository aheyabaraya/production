# LOW Track Poster Examples — M01, M02, M03 (First Test — Discarded)

**Status**: First test generation. Images were deleted by founder immediately after review because face reference locking was not strong enough.

**Lesson**: Text description alone is insufficient. The rule "attach and strictly use the actual character-board + clean face reference images" must be enforced much more aggressively (now baked into identity-guard.md and prompt structure).

**Track**: LOW historical first test
**Source**: 01A-track-visual-board.yaml (background_board + wardrobe_board + unit adaptations)
**Date of generation**: 2026-05-30 (first test using this skill)

This document is kept only as historical record of the first attempt and the key lesson learned. Use the old prompts, LOW airport spaces, wardrobe lanes, body language, lighting, or filename prefixes in another track only when that track explicitly locks those surfaces.

## Wardrobe Lane Assignments Used (LOW 01A)

- **M01 Saeyan**: scarf_tail_motion lane (adapted for First Signal / airy prism role)
- **M02 Serin**: compact_pressure / precision utility lane (Mirror Guide role)
- **M03 Yeul**: compact_pressure (official assignment from 01A for this unit)

## Generated Images

### M01 Saeyan — LOW Track Poster v1
**File**: historical LOW M01 example image under `examples/`

**Prompt summary used**:
- scarf_tail_motion lane with thin cool blue thread element
- Airport moving walkway / security threshold
- Grounded wide stance + subtle palm ripple hand gesture with the thread
- Cold fluorescent + window light, unified across figure and environment

**Observations**:
- Face and body proportion read as Saeyan correctly.
- The thin thread element works as a light signal cue without overpowering.
- Lighting feels coherent (cold airport).
- Pose has opening/signal energy while staying inside the low-pressure world.
- Good poster readability.

### M02 Serin — LOW Track Poster v1
**File**: historical LOW M02 example image under `examples/`

**Prompt summary used**:
- Precision compact_pressure lane with structured cropped jacket + vertical zipper/tie detail
- Airport moving walkway area
- Strong vertical hand cue (precision/mirror gesture) + grounded stance
- Cold fluorescent lighting

**Observations**:
- Face reads clearly as Serin.
- The structured black outfit with zipper detail gives clean mirror/precision feel.
- Pose has good vertical line and controlled power.
- Note: Text "M02 서린 / MIRROR GUIDE / ORACLE" and "TRACK 02" was baked in by the generator (common in poster-style gens). For final assets we can regenerate without text or edit out.

### M03 Yeul — LOW Track Poster v1
**File**: historical LOW M03 example image under `examples/`

**Prompt summary used**:
- Official compact_pressure lane (fitted base + cropped utility bolero + narrow tie + harness/belt hardware)
- Security checkpoint / scanner gate area
- Low grounded stance + hand adjusting tie, low focused gaze, strong boot presence
- Cold fluorescent + scanner light

**Observations**:
- Face and short bob read correctly as Yeul.
- Wardrobe (cropped jacket, harness, cargo pants, boots, headset) matches LOW Elastic Body Signal language very well.
- Scanner gate + "SCAN IN PROGRESS" + floor markings reinforce the world strongly.
- Pose feels like controlled rhythm anchor / final seal moment.
- Very strong match to the 01A direction.

## What Worked Well (First Pass)

- Identity held reasonably well across all three when the guard block was strong.
- The LOW wardrobe lanes translated visibly (especially M03).
- Cold airport lighting + specific objects (scanner, moving walkway, floor lines) gave clear track DNA.
- Full-body + boot contact + garment details read as "Elastic Body Signal" rather than generic black outfit.

## What Needs Improvement / Next Iteration Notes

- Some generations added baked-in text (member name + role). For clean asset versions we should add "no text, no logo" more aggressively in negative.
- M02 outfit came out a bit more "structured jacket" than the softer utility we sometimes see in LOW refs — can refine the description of "cropped utility bolero vs sharp cropped jacket".
- M01 thread could be made slightly more visible or have better tension in v2.
- Overall quality is already usable as strong direction references.

---

**Founder note**:
If these directions feel good, we can:
1. Keep these as v1 reference examples in the skill.
2. Refine the prompts based on your feedback and generate cleaner v2 versions (no baked text, tighter wardrobe, better pose lock).
3. Decide final placement (probably under `assets/members/album-assets/aurora-m/low/` or similar once approved).

These three images are currently the best concrete proof-of-concept for the `idol-track-poster` skill using real LOW 01A source material.
