# Member Character Card Prompt Field Guide

Read this reference when authoring or revising a clean three-panel member
character-card generation prompt. It defines the reusable prompt categories,
not a member look. Exact colors, hairstyles, garments, accessories, makeup,
body art, and other styling values come only from the current transfer map,
Founder locks, and inspected source images.

## Required Prompt Categories

Author the prompt in this order:

1. **Output request** — request one clean 16:9 landscape character card with
   exactly three generated panels.
2. **Identity authority** — name the approved face-only input as the sole facial
   identity source and state which source traits must not transfer.
3. **Styling authority** — assign every styling input a declared component role
   and state that it controls appearance only, never identity or scene grammar.
4. **Appearance transfer** — fill the current job's values for hair, makeup,
   accessories, wardrobe and layering, materials and hardware, footwear, body
   styling or body-art treatment when applicable, and the resulting silhouette.
5. **Panel evidence** — define the visible proof required from each panel:
   face and makeup on the left, upper-body construction and layering in the
   middle, and an uncropped head-to-toe silhouette with footwear on the right.
6. **Cross-panel continuity** — require one member and one coherent appearance
   across all panels, including every visible styling component and material.
7. **Review presentation** — use a quiet neutral review environment, coherent
   light, readable construction, and the required render-quality terms.
8. **Non-transfer and avoid rules** — reject source identity, body identity,
   pose, camera, crop, background, lighting setup, text, logo, interface,
   watermark, extra people, props, weapons, performance action, scene story,
   malformed anatomy, broken garments, and any explicitly discarded styling.

## Optional Rendering Style And Texture Layer

Use this layer to make the card's surface richer without turning it into a
scene image, fixing one member look as a global default, or changing the
active quality contract. It is an authoring choice for the current card or
run, not a standing member-style preset.

Choose the rendering direction in four bounded parts:

1. **Rendering base** — select one primary base such as `photorealistic live
   action`, `cinematic realism`, or `clean commercial realism`.
2. **Styling register** — select at most one supporting register such as
   `fashion editorial`, `beauty campaign`, `lifestyle realism`, or `studio
   portrait`.
3. **Capture finish** — select at most one finish such as `clean digital`,
   `restrained 35mm texture`, or `medium-format tonal rolloff`.
4. **Texture targets** — name two or three observable surface targets from the
   current transfer map or inspected styling references. Describe how each
   surface receives light or holds structure, not only its material name.

Keep the rendering base, capture finish, light family, and color treatment
consistent across all panels of one card. When a board contains multiple
looks, vary texture through the current look's garment, hardware, hair,
makeup, and construction details rather than changing the whole rendering
style. A clean card may therefore use, for example, washed denim with dry
twill, brushed metal with controlled directional reflection, or short-pile
plush with readable fiber direction, only when those details belong to the
current look.

Project the layer into the existing prompt categories:

- card-level rendering direction belongs in `Review presentation`;
- look-level material and construction targets belong in `Appearance transfer`;
- rejected style drift belongs in `Avoid`.

Do not create a new prompt line for this layer. Keep the active required
render-quality terms, including `4K`, `high quality`, and `high detail`, as the
quality contract. `8K`, `masterpiece`, `award-winning`, and similar adjectives
are not substitutes for that contract. Exact style and texture values still
come only from the current transfer map, Founder locks, and inspected source
images; the examples above are vocabulary patterns, not member-specific
defaults.

## Panel Evidence Roles

| Panel | Required proof category |
|---|---|
| left | facial identity, makeup, face-adjacent hair and accessories |
| middle | hair construction, upper-body layers, garment construction, materials, and accessories |
| right | complete outfit, body styling, silhouette, hands, hem, and footwear without crop |

The evidence role controls what must be readable, not a permanent frontal gaze,
pose, camera, or body proportion. Those choices do not propagate downstream.

## Conditional Prompt Categories

Add these only when the current transfer map or Founder direction requires
them:

- a named revision from a prior candidate;
- exact count or placement constraints for accessories or body styling;
- coverage, safety, anatomy, or garment-legibility constraints;
- a material or construction distinction that the prior result confused; or
- an explicit absence rule for a rejected feature.

Do not turn a conditional correction into a standing default for later members.

## Abstract Prompt Skeleton

```text
Output request: [card format and panel count]
Identity authority: [approved identity input and preservation boundary]
Styling authority: [source roles and non-identity boundary]
Appearance transfer: [current transfer-map values]
Left-panel proof: [face-level evidence]
Middle-panel proof: [upper-body evidence]
Right-panel proof: [uncropped full-body evidence]
Cross-panel continuity: [same member and same appearance]
Review presentation: [neutral environment, coherent light, quality]
Avoid: [source leakage, scene leakage, defects, and current rejected features]
```

This skeleton is an authoring checklist, not fixed render prose. Write one
natural prompt for the current member and keep all member-specific values in
the run-owned transfer map or generation request.
