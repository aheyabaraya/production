# 01 Screen Flow And Wardrobe Read Contract

Use this module when authoring or patching `lyric_to_scene_thinking`,
`director_chain`, 01 research-synthesis-applied direction cards, 01A/02A
pointer carry-through, or any
LOW-style run where story flow and outfit readability can drift into abstract
mood language.

## Screen Grammar

Choose the lightest screen grammar that makes the section concrete. Use the
full causal chain only for an event, reveal, reversal, decision, or state change:

```text
visible_cause -> visible_effect -> viewer_or_camera_change -> next_section_bridge
```

Other valid grammars include:

- observation or reveal: state-in -> noticed detail -> changed viewer read
- suspense or withholding: known state -> held absence/pressure -> delayed handoff
- associative montage: image/action rhyme -> contrast or accumulation -> return
- performance release: entry state -> body/camera phrase -> landing or exit
- transition or environment: material/space state -> camera route -> next state
- aftermath or afterimage: consequence state -> held detail -> unresolved/resolved exit

These scenes still name the concrete audio cue, visible state/action or
intentional stillness, camera/composition, and handoff. They do not invent
cause/effect or repeat the message to satisfy a field.

Do not leave the flow as phrases such as "signal spreads", "route opens",
"space reacts", "hidden stage appears", "viewer follows", or "quiet pull".
Those labels are allowed only after the same card names the visible body,
object, light, route, wardrobe, gaze, or camera change that proves the beat.

Good screen-flow writing:

```text
M11 taps the metal shutter twice on the bass accent.
The shutter light blinks twice and opens a narrow gap.
The camera leaves M11's hand and pushes toward M08's eyes through the gap.
The shutter gap stays open as the next snare pulls M08 forward.
```

Bad screen-flow writing:

```text
The private signal spreads and the route starts following them.
```

## Wardrobe And Material Read

Wardrobe is screen content, not only styling mood. Lock the approved look once
in 01A/style-system truth, then write only the section delta. A directing anchor
may use a full member look, `inheritance_ref` for an unchanged look, or
`material_surface_read` for a non-member scene. 02A materializes the concrete
render-facing values only when generation needs them:

```yaml
wardrobe_read:
  outfit_description:
  wardrobe_motion:
  readability_reason:
  reject_guard:
```

`outfit_description` names the actual garments, silhouette, material, and key
item visible in the shot. A lane name, color palette, or "dark styling" is not
enough.

Use concrete garment language: jacket shape, top, skirt, skort, pants, cargo
panel, boots, glove, belt, chain, strap, tie, scarf, sheer layer, coated fabric,
zipper, hardware, sleeve edge, hair accessory.

`wardrobe_motion` says how that garment or item moves, stops, catches light, or
reveals the action on the rhythm cue. It is optional when clothing remains
static; do not invent fabric movement merely to fill the contract.

`readability_reason` says why the outfit makes face, hand path, foot contact,
torso weight, formation spacing, or section emotion readable.

`reject_guard` blocks vague dark styling, color-only outfits, bulky silhouettes,
hidden hands or feet, wrong era costume drift, identity-obscuring accessories,
and unsupported fantasy/historical styling.

## Carry-Through Rule

01 owns the directing decision. When causal grammar is used, 02A/02B preserve
it; when it is not used, they preserve the concrete visible action/state,
camera, composition, and handoff instead:

```text
01.screen_cause_effect (when present)
-> 02A.screen_cause_effect (when present)
-> 02B.screen_cause_effect (when present)

01.director_chain.wardrobe_read
-> 02A.director_chain.wardrobe_read
-> 02B.director_chain.wardrobe_read
-> prompt_compile_contract.director_compile_note / compiled prompt
```

If a downstream artifact cannot name the visible event/hold, camera,
composition, handoff, or actual render-facing outfit/material, route back to 01
or 01A before writing 02B prompt prose. Absence of a causal chain alone is not a
blocker.
