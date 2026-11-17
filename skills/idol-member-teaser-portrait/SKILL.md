---
name: idol-member-teaser-portrait
description: |
  IDOL-native isolated skill for creating and refreshing clean member profile
  portraits and lightly varied teaser portraits.
  Produces two layers:
  - Base clean identity portraits (plain studio, minimal black top, soft beauty lighting)
  - Album/track-specific teaser portrait variants with only restrained changes
  Use for portrait/profile surfaces, not for a current-title full styling
  replacement or face / upper-body / full-body character card; route those jobs
  to idol-member-visual-identity.
  This skill is intentionally isolated. Do not auto-wire it into scripts, harnesses, or other skills until explicitly requested.
---

# IDOL Member Teaser Portrait

Create consistent, reusable member profile and teaser portraits while preserving exact face and body identity.

This skill exists so that every new album or track can have its own set of member teaser portraits without drifting from the established member identity.

It does not own the reusable current-title member character card. When the task
preserves only the approved face while replacing hair, makeup, accessories,
wardrobe, materials, footwear, and silhouette, use
`idol-member-visual-identity` instead.

## Read / Write Contract

- Status: active isolated identity-asset helper.
- Required reads: this `SKILL.md`, the target member `character-board` and
  current approved face reference under `assets/members/Mxx/`, and the relevant
  `assets/member-registry.yaml` row. For album/track variants, also read the
  current track context that the founder names.
- Allowed outputs: base profile portraits under the member asset folder, or
  album/track teaser portraits under
  `assets/members/Mxx/albums/ALBUM_KEY/TITLE_KEY/`.
- Forbidden outputs: graph-engineering stage artifacts, run truth updates, catalog
  registry promotion, automated wiring, or public/social package updates unless
  separately requested.
- Registry behavior: none by default; any durable catalog or release registry
  pointer is a separate founder-approved task.
- Founder gates: founder approval is required for paid generation, external
  upload/sync, base identity refreshes, or automation wiring.

## Two Layers

| Layer | When to use | Location | Characteristics |
|-------|-------------|----------|-----------------|
| **Base Profile Portrait** | Major identity refresh, new member onboarding, or when the clean foundation set needs updating | `assets/members/Mxx/face-only-reference.png` (M03 keeps the repository's `.PNG` case) | Plain seamless light background, minimal black fitted top, soft beauty lighting, gentle approachable expression, no performance elements |
| **Album/Track Teaser Portrait** | Every new album or track that needs member visual presence (website cards, key art, social, handoff) | `assets/members/Mxx/albums/ALBUM_KEY/TITLE_KEY/profile-teaser-*.jpg` (or agreed naming) | Same face + body proportion lock + very controlled addition of album/track mood (subtle wardrobe, lighting temperature, micro-gesture, tiny concept cue). Still reads as "member teaser portrait", not MV still or full concept shot |

## Core Identity Lock (Non-Negotiable)

Every generation **must** treat these two sources as the single source of truth:

1. `assets/members/Mxx/character-board.png` (or .PNG)
   - Face lock (front / 3/4 / side angles)
   - Full body proportion lock (even when image is cropped to head+shoulders)
   - Eye spacing, jaw line, lip shape, face length, torso-to-head ratio
   - Explicit "DO NOT DRIFT" rules on the board

2. Current approved face-only reference in the same folder (`face-only-reference.png`, or the repository's exact-case equivalent)
   - Current approved lighting family and expression baseline for clean portraits

**Rule**: The generated portrait must be recognizable as the same person in the character board and the current face reference. No invented age, no original fictional identity comparisons, no body proportion changes.

## Visual Contract — Base Profile Portrait

From the existing approved M01–M13 face-only identity set:

- **Background**: Seamless, textureless, very light gray to off-white studio backdrop. No environment, no particles, no floor line, no architecture.
- **Wardrobe**: Minimal black fitted sleeveless tank or round-neck top. Clean neckline. No logos, no heavy hardware, no performance mic or earpieces.
- **Framing**: Head + upper chest / slight shoulder line. Not pure floating head, not full torso. Comfortable breathing room around the subject.
- **Lighting**: Soft, flattering beauty lighting. Gentle volume on face, subtle skin glow, clean catchlights in eyes. Even, non-dramatic. Face, neck, and top read as one coherent lit surface.
- **Expression & Gaze**: Gentle, approachable. Soft closed-mouth smile or calm direct-to-camera gaze with very slight smile. Not performance intensity, not blank, not overly cute.
- **Hair & Details**: Member-specific natural hair styling (as seen in current approved set). Very light, tasteful micro-accessories only when they already exist in the member's character language (tiny crystals, small earrings, etc.). Nothing that reads as costume.
- **Quality**: High-resolution commercial idol portrait. Sharp eyes, clean skin texture, natural but polished makeup. No text, no watermarks, no extra objects.

**Negative (Base)**: dramatic lighting, heavy shadows, stage lighting, wet hair, rain, particles, sparkles, crystals, VFX, fantasy elements, heavy makeup, performance expression, mic, earpiece, jacket, outerwear, textured background, environment, text, logo, watermark, identity drift, changed face shape, changed eye spacing, changed jaw, changed body proportion.

## Visual Contract — Album/Track Teaser Portrait Variant

Use the exact same face + body lock as the base.

Allowed controlled deviations (one or two at most per set):

- Subtle wardrobe shift that still reads "minimal portrait" (e.g., same black base + one thin thread/scarf element, or a different neckline in the same black family, or a very light outer layer that does not cover the torso)
- Lighting temperature shift that supports the album/track mood (slightly cooler, warmer, lower key, soft color accent in the light)
- Hair styling that is still the member's recognizable silhouette but with one small album-appropriate change (wet-look strands, slight updo, loose vs tied, one accessory)
- Micro-expression or gaze shift that carries the track's emotional tone (slightly more intense eyes, softer half-smile, distant gaze, quiet confidence) while staying inside the gentle portrait range
- One tiny concept cue only if it stays extremely small and does not dominate (single thin thread line, one small glass bead, one restrained color accent on accessory)

**Hard stops for variants**:
- No full concept outfits
- No heavy outerwear or jackets that change silhouette
- No stage/MV lighting or dramatic side light
- No particles, rain, water, VFX, sparkles, sequins
- No performance face or intense expression
- No change to body proportion or face geometry
- No environment or background texture (still plain or extremely minimal)

The result must still feel like "this member's clean teaser portrait for this album", not "this is the music video look".

## Prompt Template for Grok Imagine (Base)

```
Create a high-resolution commercial idol member profile portrait, clean studio beauty shot.

Subject: [MEMBER_CODE] [KOREAN_NAME] / [ENGLISH_NAME] — [PROFILE_WORD] / [INITIAL_IDENTITY]

Exact face and body identity lock:
- Use the attached character-board.png as the definitive face lock (front, 3/4, side) and body proportion reference. Zero drift on eye spacing, jaw line, lip shape, face length, head-to-torso ratio.
- Use the attached current face-only-reference image as the approved lighting family and gentle expression baseline.

Visual contract (strict):
- Seamless textureless very light gray to off-white studio background only. No environment, no floor, no particles, no architecture.
- Minimal black fitted sleeveless tank or clean round-neck top. No logos, no heavy details, no performance gear.
- Head + upper chest framing with slight shoulder line visible. Comfortable negative space.
- Soft flattering beauty lighting with gentle volume, subtle skin glow, clean catchlights. Face, neck and top read as one coherent surface.
- Gentle approachable expression: soft closed-mouth smile or calm direct gaze with very slight smile. No performance intensity.

Member personality cues for expression (do not overplay):
[Insert 1-2 lines from member-registry.yaml: personality_rhythm + charming_point]

Output: vertical 3:4 or 4:5 portrait, high detail, commercial idol portrait quality, no text, no watermark, no extra objects.

Negative prompt: dramatic lighting, stage light, heavy shadow, wet hair, rain, particles, sparkles, crystals, VFX, fantasy, heavy makeup, performance face, mic, earpiece, jacket, outerwear, textured background, environment, text, logo, identity drift, changed face, changed eye spacing, changed jaw, changed body proportion, oversized head, floating head.
```

## Prompt Template for Grok Imagine (Album/Track Teaser Variant)

Start from the base template above, then add one controlled paragraph:

```
Album/Track context: [ALBUM_NAME] — [TITLE] — [one-sentence mood or signal of the track]

Allowed single controlled variation only:
[Describe the one thing you are changing, e.g. "Add a single thin translucent glass-blue thread scarf from collar to right hand, very light and close to body, no knot, soft rain-glass gloss on the thread only. Keep the black base top and all other elements exactly as the clean profile contract."]

Expression adjustment (still inside gentle portrait range):
[One short description tied to the track's emotional tone]

Everything else (background, lighting coherence, framing, wardrobe base, face geometry, body proportion) remains identical to the base profile contract. Do not add environment, particles, dramatic light, or performance elements.
```

## Usage (Isolated)

1. Read the target member's `character-board.png` and current canonical
   `face-only-reference.png` (M03: `face-only-reference.PNG`) in
   `assets/members/Mxx/`.
2. Read the relevant rows from `assets/member-registry.yaml` (personality_rhythm, charming_point, signature_mark, profile_word, initial_identity).
3. Decide base or album/track variant.
4. Write the prompt using the templates above.
5. Generate.
6. Save with clear naming (include version or date if needed).
7. Place in the correct folder per the two-layer rule.

Do not run this skill as part of any automated flow until the founder explicitly approves wiring.

## When Not To Use This Skill

- Full current-title styling replacement or a face / upper-body / full-body
  three-panel card → use `idol-member-visual-identity`
- Full MV storyboard or 02B image generation → use `idol-video-prompt` + 02B process
- Website full "Signal Atelier" teaser cards -> use the private planning in
  `business-marketing/docs/interactive-idol-web/` only after founder approval
  for the current task
- Heavy concept or performance portraits → not the job of this skill

This skill is for clean, reusable member identity portraits that can serve as face anchors for everything else.

---

**Status**: Isolated skill. No external references or automation connections exist yet. Created on founder request for repeatable per-album/track member teaser portrait work.
