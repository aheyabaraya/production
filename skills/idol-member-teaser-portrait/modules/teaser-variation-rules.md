# Album / Track Teaser Portrait Variation Rules

This module defines how to create controlled, content-specific teaser portraits while protecting the base identity lock.

## Philosophy
The teaser variant must still read first as "**[Member]'s profile portrait**" for this album/track, not as "the music video look" or "full concept shot".

One or two very small, intentional deviations are usually enough. More than that and it stops being a teaser portrait.

## Allowed Single or Dual Deviations (Choose Carefully)

1. **Lighting temperature / mood**
   - Slight cool shift (for colder, more distant, or "signal" tracks)
   - Slight warm / soft shift (for emotional, intimate, or warm-toned tracks)
   - Lower key with gentle falloff (for darker or more restrained tracks)
   - Must remain beauty-portrait lighting family — never becomes stage or dramatic cinematic light

2. **Minimal wardrobe addition (still portrait scale)**
   - One thin thread, scarf-tail, or ribbon element (very close to body, not flying)
   - Subtle different neckline or slight cutout in the same black family
   - Extremely light sheer overlay or chiffon detail that does not change silhouette
   - One small restrained accessory that ties to the album concept (tiny bead, thin chain, glass element)
   - **Never**: jackets, coats, heavy outerwear, full concept costume, performance gear

3. **Hair treatment (within member's silhouette)**
   - Wet-look strands or soft gloss
   - Slight change in how hair is worn (one side tucked, loose vs half-up, soft volume change)
   - One small album-appropriate accessory in hair (only if it already fits member's character language)
   - Must not change the recognizable hair silhouette from the base portrait

4. **Micro expression / gaze (still gentle range)**
   - Slightly more direct / quiet intensity in the eyes
   - Softer, more inward half-smile
   - Distant soft gaze (for melancholic or dreamy tracks)
   - Quiet confidence or subtle "knowing" look
   - **Never** crosses into performance face, strong emotion, or cute exaggeration

5. **One tiny concept cue (maximum one, very small)**
   - Single thin reflective thread line
   - One small glass or crystal element catching light
   - Extremely restrained color accent on an accessory only (not on skin or hair)
   - Must occupy less than 5-8% of the visual weight

## Hard Prohibitions (Album/Track Variants)

- No change to face geometry, eye spacing, jaw line, lip shape, or head-to-body ratio
- No environment, background texture, rain, particles, fog, or architecture
- No dramatic side lighting, rim light, or heavy shadow
- No sparkles, glitter, sequins, rhinestones, floating VFX, magical effects
- No performance expression or intense model stare
- No mic, earpieces, or stage equipment
- No full concept wardrobe or heavy outer layers
- No text, logos, or UI elements
- No "pasted face" look — lighting must stay coherent across face, neck, and clothing

## Decision Process Before Generating

1. Read the album/track creative nucleus or selected audio analysis (what is the emotional tone / signal of this content?)
2. Read the member's registry entry (what is their core personality and charming point?)
3. Decide: what is the **single smallest** thing that can carry a whisper of the new content without breaking the portrait contract?
4. If you cannot answer with one clear, minimal change → stay with the base profile contract instead of forcing a variant.

## Example Phrasing in Prompts

Good:
"Add only one very thin translucent glass-blue thread scarf starting from the right collarbone, falling softly along the right side of the torso and ending near the hand. Keep the black tank top fully visible underneath. Add extremely subtle cool blue-white light temperature shift on the thread and right side of face only. Expression remains gentle with slightly more distant soft gaze. All other elements exactly as the clean base profile contract."

Bad (too much):
"Black wet leather jacket, dramatic side lighting, rain on face, intense smoky eye makeup, wind-blown hair, holding a glowing prism, standing in dark rain-glass corridor..."

## Versioning Recommendation

- First variant for an album: `profile-teaser-v1-[ALBUM_SLUG].jpg` or similar
- Keep the previous version when refreshing
- Document in the run folder or album asset manifest what the single intended deviation was

## Relationship to Base Layer

The album/track teaser portrait is **not** a replacement for the base. It is a parallel, content-tinted layer that still depends on the base identity being correct.

If the base set itself needs refreshing, do that first using the base contract, get founder approval, then build album variants from the new clean foundation.