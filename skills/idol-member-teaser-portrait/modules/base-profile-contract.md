# Base Profile Portrait Contract

This is the canonical clean foundation layer for all AURORA-M / Loom member portraits.

## Purpose
- Primary face identity reference for all future image and video generation
- Clean profile images for website member pages and intro cards
- Neutral starting point that does not carry any album/track concept

## Visual Rules (Observed from Approved Set)

**Background**
- Seamless, completely textureless
- Very light gray to off-white (close to #f5f5f5 ~ #fafafa range)
- No gradient, no vignette, no environment, no floor line, no particles, no light leaks

**Framing & Composition**
- Head + upper chest with slight shoulder line visible
- Comfortable negative space around the subject (not tight crop, not floating head)
- Vertical portrait orientation (3:4 or 4:5 preferred)
- Subject centered or very slightly off-center for natural breathing room

**Wardrobe (Strict)**
- Black fitted sleeveless tank top or clean round-neck top
- Matte or very subtle sheen knit/jersey/satin
- Simple neckline (crew or slight scoop)
- No logos, no prints, no heavy hardware, no belts, no outer layers
- No performance mic, no earpieces, no in-ear monitors

**Lighting**
- Soft, even beauty lighting
- Gentle modeling on cheekbones and jaw
- Subtle skin glow / natural highlight on forehead, nose bridge, cheek
- Clean catchlights in both eyes
- Face, neck, and upper chest read as one continuous lit surface
- No dramatic side light, no heavy shadow under chin or on neck
- No colored gels or strong temperature shifts

**Expression & Gaze**
- Gentle and approachable
- Soft closed-mouth smile (corners of mouth slightly up) OR calm direct gaze with very subtle smile
- Eyes soft but readable
- No performance intensity, no "model stare", no overly cute aegyo, no blank affect
- Expression must feel like a real person you could have a quiet conversation with

**Hair & Grooming**
- Member-specific natural styling (long loose, half-up, bun, bob, etc.)
- Clean, polished, no excessive flyaways
- Very light, tasteful micro-accessories only when already part of the member's approved character language (tiny crystal pins, small dangling earrings, etc.)
- No heavy headpieces, no visible hair extensions or wigs that change silhouette drastically

**Makeup & Skin**
- Natural but polished idol beauty makeup
- Clean base, soft blush, defined but soft eyes, natural lip
- Skin texture visible but smoothed — not plastic, not poreless
- Subtle highlighter only on highest points

**Quality Bar**
- Commercial high-resolution idol portrait
- Sharp, clear eyes with good catchlight
- Natural skin detail
- No compression artifacts, no over-sharpening
- No text, no watermarks, no logos, no UI elements, no extra objects in frame

## What This Layer Must Never Become
- Stage portrait
- Concept photo
- MV still
- Fashion editorial
- Fantasy / game art
- Heavy glamour shot

It must remain the clean, reusable identity anchor.

## Reference Sources (Always Read First)
1. `assets/members/Mxx/character-board.png` — definitive face angles + body proportion lock
2. `assets/members/Mxx/face-only-reference.png` (or latest approved face-only version) — current approved lighting + expression baseline for the clean style
3. Relevant rows in `assets/member-registry.yaml` — personality_rhythm, charming_point, profile_word for subtle expression tuning

## Naming Convention (Base)
- `face-only-reference.png` (current approved; M03 uses `face-only-reference.PNG`)
- When refreshing: `face-only-reference-v2.png` or date-suffixed face-only version
- Keep the previous version until the new one is explicitly approved as the new base

Do not overwrite the previous base without founder confirmation.
