# Current-Title Member Character Card Contract

Status: active reusable method
Owner: `idol-member-visual-identity`
Canonical example class: PUBG member character cards, format evidence only

## Authority Split

| Surface | Controls | Must not control |
|---|---|---|
| approved face-only asset | facial identity and stable facial marks | hair, makeup, accessories, wardrobe, body styling, pose, camera, background |
| selected styling reference | its declared hair, makeup, accessory, wardrobe, material, footwear, or silhouette component | face or body identity, pose, camera, background, text, logo, interface |
| clean three-panel card | passed current-title appearance continuity | scene action, gaze, pose, crop, camera, or composition |
| 02A Branch Cut | scene state, action, gaze, pose, camera, placement, crop, occlusion, proportion | replacement of the passed current-title appearance without Founder exception |

The identity input and styling inputs coexist only during this Front Planning
asset-production job. There is no separate downstream face-reference lane.

## Locked Card Geometry

```text
16:9 landscape canvas
┌────────────────┬────────────────┬────────────────┐
│ FACE           │ UPPER BODY     │ FULL BODY      │
│ identity       │ hair + makeup  │ head to toe    │
│ makeup proof   │ outfit build   │ shoes visible  │
└────────────────┴────────────────┴────────────────┘
```

- exactly three generated panels;
- order is face, upper body, full body;
- equal visual family and one coherent neutral review environment;
- same face, hair, makeup, accessories, garments, materials, and colors in all
  panels;
- full body remains uncropped from head through footwear;
- clean pixels contain no labels or reference strips.

The Founder workbench may place the face source and styling sources beside the
clean card. That surrounding HTML evidence is not baked into the canonical
card.

## Input Order

```text
Image 1 = one approved member face-only identity asset
Image 2..N = Founder-selected styling references in declared component order
```

Every input records actual path, SHA-256, inspection, and role. A later styling
reference cannot silently replace an earlier component. Resolve or hold the
conflict before generation.

## Transfer Map

Every member job explicitly authors these rows:

| Decision | Required value |
|---|---|
| preserve | member face identity only |
| replace | hair and hair color |
| replace | makeup and beauty finish |
| replace | accessories |
| replace | complete wardrobe and layering |
| replace | material, hardware, and color |
| replace | footwear |
| replace | styled silhouette |
| reject | styling-source face and body identity |
| reject | source pose, camera, background, text, interface, and logo |

Member-specific Founder locks refine a row; they do not remove the rows.

## Review Separation

Keep three surfaces distinct:

1. `build inputs`: face plus styling sources, used only for the card job;
2. `selection evidence`: the workbench view pairing those sources with the
   candidate; and
3. `canonical current-title asset`: the clean passed three-panel card.

An overview sheet can help cast-level silhouette review but cannot select or
replace an individual card. No candidate becomes active through model review,
schema validity, file presence, or inclusion in an overview.

## Required Pixel Review

Inspect each panel and the whole card for:

- face match to the approved identity source;
- cross-panel face, hair, makeup, accessory, garment, and color consistency;
- complete replacement of the face source's old styling;
- exact selected styling-component carry;
- absence of styling-source identity transfer;
- readable hair construction and garment layering in upper body;
- complete outfit, silhouette, hands, hem, and footwear in full body;
- anatomy, fabric, hardware, and accessory integrity; and
- absence of text, logos, watermark, props, weapons, action, or scene bias.

Record uncertainty as HOLD. A local defect correction changes only the named
pixel defect and retains the same input order and creative locks unless the
Founder changes the styling truth.

## Founder Gate And Promotion

Candidate states are `founder_review_pending`, `founder_hold`, or
`founder_reject`. The worker returns only to CDD; CDD reviews and curates the
single Founder workbench cycle, and Overall authorizes the recommendation for
Founder presentation. Only explicit `founder_pass`, preserved by CDD and
returned to Overall, permits the active Workbench intake to locally upscale the
exact generated clean card. Overall canonical promotion then requires the
validated source/output receipt; HOLD, REJECT, references, and already-promoted
assets do not enter this treatment.

Promotion writes the clean card into the current-title package and records:

- member id and title id;
- identity source path/SHA-256 as provenance;
- styling source paths/SHA-256 and component roles as provenance;
- selection-evidence pointer/SHA-256;
- original selected clean-card path/SHA-256 and dimensions;
- local upscale receipt path/SHA-256 plus the promoted upscaled clean-card
  path/SHA-256 and dimensions;
- concise appearance lock; and
- Founder selection state and date.

Downstream attaches only the promoted receipt-bound upscaled clean card when the member is
meaningfully visible. The build inputs and selection evidence remain
noncanonical provenance.

## PUBG Example Boundary

PUBG proves the reusable method: one member per clean face/upper/full card,
separate identity-and-style comparison evidence, individual Founder selection,
and clean-card-only promotion. PUBG faces, styling, wardrobes, backgrounds,
prompts, member assignments, and CF scene decisions are not reusable creative
inputs for another title.
