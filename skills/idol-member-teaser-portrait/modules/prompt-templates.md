# Prompt Templates

## Base Profile Portrait (Grok Imagine)

```
Create a high-resolution commercial idol member profile portrait in clean studio beauty style.

Member: [M01] 새얀 / Saeyan — Prism / First Signal

Identity lock (absolute):
- Use the attached character-board.png as the single source of truth for face (front, 3/4, side angles) and body proportion. Do not drift on eye spacing, jaw line, lip shape, face length, or head-to-torso ratio.
- Use the attached current face-only-reference image as the approved soft beauty lighting family and gentle expression baseline.

Strict visual contract:
- Seamless textureless very light gray to off-white studio background only. Zero environment, particles, floor line, or architecture.
- Minimal black fitted sleeveless tank or clean round-neck top. No logos, no hardware, no performance elements.
- Head + upper chest framing with slight natural shoulder line. Comfortable negative space.
- Soft flattering beauty lighting with gentle volume, subtle skin glow, clean catchlights. Face, neck, and top must read as one coherent lit surface.
- Gentle approachable expression: soft closed-mouth smile or calm direct gaze with very slight smile. No performance intensity.

Member personality for subtle tuning:
[personality_rhythm + charming_point from registry]

Output requirements: vertical portrait, high detail, commercial idol portrait quality, natural skin texture, sharp eyes, no text, no watermark, no extra objects, no VFX.

Negative prompt: dramatic lighting, stage light, heavy shadow, wet hair, rain, particles, sparkles, crystals, VFX, fantasy elements, heavy makeup, performance face, mic, earpiece, jacket, outerwear, textured background, environment, text, logo, watermark, identity drift, changed face shape, changed eye spacing, changed jaw, changed body proportion, oversized head, floating head, plastic skin.
```

## Album / Track Teaser Portrait Variant (Grok Imagine)

Start with the base template above, then append one controlled block:

```
Content context: [Album: Code Root Signal] — [Title: Aurora M Full] — [short mood description, e.g. "first signal opening, airy and luminous, rain-glass thread identity"]

Single controlled deviation only (everything else stays exactly on the base contract):
[Describe the one minimal change, e.g. "Add a single very thin translucent glass-blue thread element starting near the right collar, falling softly along the body with extremely subtle cool light catch on the thread only. Keep the black tank top dominant and fully visible. Slight cool temperature shift in the lighting on the right side of face and thread. Expression remains gentle with a slightly more luminous, open quality in the eyes."]

Do not add environment, particles, dramatic light, heavy wardrobe, or performance elements. The image must still read primarily as a clean member profile portrait with one quiet content cue.
```

## Negative Prompt Base (Always Start From This)

```
dramatic lighting, stage lighting, cinematic side light, heavy shadow, rim light, wet hair, rain, water, particles, sparkles, glitter, crystals, VFX, floating elements, fantasy, game art, heavy makeup, smoky eyes, performance expression, intense stare, model pose, mic, in-ear monitor, earpiece, jacket, coat, outerwear, leather, cargo, utility styling, textured background, environment, architecture, floor line, text, logo, watermark, UI, identity drift, changed face, changed eye spacing, changed jaw line, changed lip shape, changed face length, changed body proportion, oversized head, floating head, plastic skin, waxy skin, deformed hands, extra fingers
```

## Tips for Strong Results

- Always attach both the character-board.png and the current clean face reference.
- When doing a variant, describe the **single** change in one clear sentence.
- If you feel the urge to describe many changes, stop and ask: is this still a teaser portrait, or am I accidentally writing an MV still prompt?
- For batch of 13, generate one strong reference member first (often M01 or the center), lock the lighting family and framing, then apply the same family to the rest with only their individual hair + one content cue varying.

## Example of Good Minimal Variant Language

"Only addition: one narrow translucent pearl-white thread ribbon from the left side of the collar, resting lightly against the black top and right hand. Extremely subtle soft cool-white light temperature on the ribbon and left side of face. Gentle expression with a slightly more reflective, quiet gaze. All other elements identical to the clean base profile contract."

This is the level of restraint the skill expects.