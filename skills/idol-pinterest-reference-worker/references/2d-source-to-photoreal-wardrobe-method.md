# 2D / Anime Source → Photoreal Wardrobe Method

Use this module when any of the following is true:

- the governing scene, combat, city, or color grammar source is **2D, anime,
  illustration, or cel-style media**;
- production look is locked to **photoreal cinematic / live-action / AAA 3D**
  materials while those 2D frames remain active;
- the task is **wardrobe, styling, bandana/color-item, member look, or
  fashion-component discovery** for current-title members.

This module does **not** authorize generation, face identity, canonical
promotion, or discarding official 2D scene-grammar boards. It prevents 2D
texture bleed into photoreal wardrobe.

## Authority Split — Two Decks

| Deck | Owns | Must not own |
|---|---|---|
| **Grammar deck** | place, relation, color temperature, tempo, silhouette pressure, section job | fabric weave, anime line, cel shading, IP costume copy |
| **Wardrobe deck** | photoreal garments, materials, hair-match fashion, bandana cloth, accessories | scene story, face identity, 2D cel texture |

Rules:

1. Keep grammar and wardrobe as **separate attachment families**.
2. Never put a 2D/anime frame in a wardrobe/styling attachment slot for generation
   or member-card styling input.
3. Never treat a fashion pin as face identity; face-only remains sole face source.
4. Transfer from 2D sources is **function only**: what the screen needs, not how
   the anime drew cloth.

## Mandatory Pipeline

```text
2D board / source still
  → function extract (place / attitude / color temp / formality / layer density)
  → member attribute match (hair color/length, body silhouette DNA, king color)
  → item lock (one primary garment noun, e.g. shirt, blazer, long coat)
  → bandana/color-mark lock (king or title color system when active)
  → search A: attribute-matched idol/concept photos (optional but preferred)
  → search B: photoreal fashion / editorial for the locked item
  → Founder or CDD pick (thin set)
  → capture + hash + component role
  → generation attaches: face-only → wardrobe pins → optional grammar still for place only
```

### Step 1 — Function extract (from 2D only)

For each king, section, or member thread, write a one-line function row:

- place axis (air, alley, arterial, interior, station, roof, …);
- attitude (authority, heat, order, duel elegance, soft civilian, remain gravity);
- color temperature (gold wash, red spark, cobalt, emerald, desat gray, silver);
- formality (street / semi-formal / unit / editorial);
- layer density (aide-thin vs full-king dense).

Do **not** copy: clan marks, exact uniforms, swords, anime hair physics, cel
highlights, illustration outlines.

### Step 2 — Member attribute match

Read the member registry / character-board DNA and extract:

- hair color and length/style class;
- silhouette family already approved (e.g. sheer asymmetric, cobalt wrap,
  glass-chrome, denim cargo, utility crop);
- height/body continuity constraints when present.

Search preference:

1. **idol / concept / stage photos** whose **hair or silhouette class** matches
   the member (example: red hair need → red-haired idol stills; black wet hair →
   black-haired idol street/stage);
2. if idol pool is weak, **photoreal fashion editorial** with the same attribute
   class is legal;
3. never use 2D/anime stills as the wardrobe material authority.

### Step 3 — One item lock

Pick **one primary garment noun** per member/thread before broad search:

| Formality cue | Example item lock |
|---|---|
| semi-formal / deck / order | shirt + blazer, or white shirt + navy coat |
| street heat | asymmetric sheer top, tech cargo layer |
| interior duel elegance | chrome/halter body + one color accent |
| civilian fog | oversized shirt or wool long coat |
| roof remain | dress shirt + long overcoat |

Search with that noun as the first-query visual kernel. Do not query
storyline paragraphs, lyric paraphrases, or camera essays. Add one noun or
pose only while that named wardrobe gap is still open. Do not open a generic
“cyberpunk aesthetic” dump.

### Step 4 — Bandana / color-mark lock

When the title uses king colors or a mandatory color cloth:

- bandana (or equivalent color mark) **must match the king/title color**;
- capture at least one **real-cloth** bandana/color-item still per color when
  the mark is screen-critical;
- bandana is wardrobe-deck truth, not 2D-symbol art.

### Step 5 — Two search passes

1. **`visual_ignition`** — first query is the locked garment noun. No
   storyline paragraphs, lyric paraphrases, camera essays, K-pop forced terms,
   lens schema, or anime keywords. Second query: one added noun or pose only
   while that named wardrobe gap is still open.
2. **`idol_translation`** — keep the strongest seed; add idol concept / comeback
   teaser / beauty editorial / performance wardrobe only if it preserves
   photoreal fabric.

Drop immediately: anime, cosplay, illustration, fan-art, IP costume, cel.

### Step 6 — Thin pick set

Default target per member (or per king thread):

- **Outer** (1);
- **Body / locked item** (1);
- **Idol hair-read or silhouette-read** (0–1, optional);
- **Bandana / color-mark** (1 when color system is active).

Prefer **3–4 stills per member**, not a large moodboard. More pins after that
are noise unless a named conflict remains.

### Step 7 — Attachment order (generation / member card)

```text
1. face-only (identity)
2. wardrobe-deck pins in component order (outer → body → bandana → …)
3. optional grammar-deck still ONLY for place/relation (never for fabric)
```

If a model starts reading anime cloth, the failure is almost always grammar
stills attached as wardrobe or missing material locks.

## Material Lock Before Silhouette Polish

When production is photoreal, lock real materials before final silhouette polish:

- cloth weave, wool, tech nylon, real leather, real mesh;
- brushed or hard metal hardware (not cartoon chrome);
- real bandana cloth edge under hard light;
- AAA/3D slate as separate VFX layer, color-matched to the king wash.

## HOLD Conditions

HOLD wardrobe discovery when:

- 2D frames are the only wardrobe material authority;
- bandana/color-mark color conflicts with the locked king/title system;
- candidate pool is anime/cosplay-majority;
- grammar and wardrobe decks are mixed in one attachment list without roles;
- member hair/silhouette match was skipped and results fight identity DNA;
- more than a thin pick set is being bulk-attached without CDD/Founder cull;
- a storyline paragraph, lyric paraphrase, or camera essay was queried;
- the first query was not the locked garment noun.

## Outputs

Return a noncanonical pick sheet or Decision Set rows that include:

- function extract from the 2D source;
- member attribute match notes;
- locked item noun;
- bandana/color lock;
- pin URL/id + local path/SHA-256 when captured;
- component role (`outer`, `body`, `bandana`, `hair_read`, …);
- explicit `deck: wardrobe` (never `grammar`).

CDD/Founder select; Overall promotes. This worker/method does not promote.

## Related

- Section kernel-search Pinterest floor: `pinterest-section-comparison-detail.md`
- Capture helper: `scripts/idol_pinterest_public_capture.py`
- Member card build: `skills/idol-member-visual-identity/SKILL.md`
- Media surface rules: `policies/repository-media-security.md`
