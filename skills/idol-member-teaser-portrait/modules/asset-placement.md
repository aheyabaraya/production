# Asset Placement & Naming (Self-Contained Rules)

This skill does not modify any scripts or automation. These are the manual placement conventions the skill expects the user or operator to follow.

## Base Clean Profile Portraits

**Canonical location**
```
assets/members/Mxx/
  face-only-reference.png                          ← current approved base
  face-only-reference-v2.png                       ← optional approved refresh
  character-board.png                              ← master identity contract (never overwrite)
```

**When refreshing the base set**
- Create `face-only-reference-v2.png` (or a date/version-suffixed face-only file)
- Do not delete the previous `-1` version until founder explicitly approves the new set as the new base
- Update the fallback `face-only-reference.png` only after approval
- Run the web optimize script manually if you want the web profile.webp to update (this skill does not trigger it)

## Album / Track Teaser Portrait Variants

**Recommended structure** (follows existing pattern in the repo for per-album member assets)

```
assets/members/Mxx/
  albums/
    ALBUM_KEY/
      TITLE_KEY/                    ← or just ALBUM_KEY if title-level not needed
        profile-teaser-v1.jpg
        profile-teaser-v1-M01.jpg   ← optional explicit member suffix
        ...
```

Alternative flat naming (if you prefer simpler):

```
assets/members/Mxx/
  albums/
    code-root-signal/
      aurora-m-full-code-root-signal/
        M01-profile-teaser-v1.jpg
        M02-profile-teaser-v1.jpg
        ...
```

**Naming suggestions**
- `profile-teaser-v1.jpg`
- `profile-teaser-[ALBUM_SLUG].jpg`
- `teaser-portrait-[short-mood].jpg`
- Always include the member code in the filename when the folder contains multiple members

## Character Board Rule

The `character-board.png` (or .PNG) in the root `assets/members/Mxx/` folder is the **master identity document**.

- Never overwrite it with a teaser portrait
- Never use a teaser portrait as the new character board
- If body proportion or face geometry needs to change permanently, that is a separate founder-level identity decision, not a teaser portrait task

## Relationship to Web Assets

The web side currently pulls base profiles through:
- `web/scripts/optimize-assets.mjs` (converts the approved face-only source → `profile.webp`)

This skill produces the source images. It is the operator's responsibility to run the optimize script afterward if web assets need updating. The skill itself has no automation connection.

## Drive Sync / Handoff

If a founder-requested Grok or GPT handoff needs these portraits, copy only the specific base or variant images needed into the temporary handoff pack. Do not treat the entire skill folder as a handoff surface.

## Registry Notes

The `assets/member-registry.yaml` already points to:
- `local_assets.face_reference`

When a new base portrait is approved, the registry path can be updated manually. This skill does not perform that update.

## Summary of Isolation

This skill only defines:
- Visual contracts
- Prompt templates
- Placement recommendations

It does not:
- Call any scripts
- Update registries
- Modify AGENTS.md or production graph-engineering order
- Create automation
- Add itself to wiki or handoff flows

All integration is future work and requires explicit founder request.
