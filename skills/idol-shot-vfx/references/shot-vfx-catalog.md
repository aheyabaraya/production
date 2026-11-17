# IDOL Shot VFX Catalog

Use this catalog to translate a Founder effect name, reference, or situation
into one reviewable shot job. It is a directing aid, not an executable effect
registry. Availability must be rechecked from the local runtime before work.

## Layer Decision

| Requested screen result | Route |
| --- | --- |
| Existing pixels need flash, zoom, blur, grade, xfade, text, grain, or a simple overlay | 04FX |
| The cut, trim, speed, geometry, source, or timing must change | Return to 04 |
| A new 3D object, spatial camera relation, material reveal, tracked insert, depth/occlusion, environment reaction, or simulation must be rendered | 04VFX |
| A rendered element also needs final flash/grade/transition accents | 04VFX candidate → 04 re-intake → 04FX |

## Camera Explanation Aid

The approved local aid is `Add Camera Rigs` `1.8.2` under Blender `5.2.0`.
Use it only after the owning camera decision exists:

- 2D rig: framing edges, placement, crop/negative space, lens-versus-shift;
- Dolly rig: camera height, distance, direction, aim, and straight travel;
- Crane rig: authored elevation, boom length, or arcing spatial relation;
- composition guides: thirds, center, diagonal, golden ratio, and safe areas.

A rig screenshot or proxy explains geometry; it does not become 01, 02A, 03V,
04, or Founder truth. Exact installation identity and preflight live in
`04vfx-manual-use-and-runtime.md`.

## Shot Families

### Hero Object Reveal

- Use when an object must introduce the world before a member appears.
- Observable route: small object in darkness → controlled approach/orbit →
  material or marking becomes readable → wider consequence or scale reveal.
- Local reference: `I DON'T BARGAIN` object intro under
  `runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/idont-bargain-1s-v1/`.
- Preserve the directing grammar, not the PUBG helmet. Replace it with the
  current title's object and world rule.
- QC: silhouette at mobile size, material stability, credible light, camera
  ease, no texture pop, and a clear handoff to the next shot.
- Local status: Blender `5.2.0` and the camera explanation rig are locally
  ready; a real shot still needs the exact passed 04 window and normal 04VFX
  eligibility gate.

### Object State Transformation

- Use when the same object visibly opens, fractures, unfolds, melts, assembles,
  lights, or changes material and that change carries story meaning.
- Require a readable entry state, one causal transformation, and a stable
  endpoint. Do not use undirected “morphing”.
- QC: topology/material continuity, no frame-to-frame volume jump, and no
  transformation that obscures the object's identity.
- Local status: simple keyframed transforms are planned local; fluids, dense
  destruction, and complex procedural growth are heavy holds on M1 8GB.

### Scale Or Space Intervention

- Use when an object or structure must change the perceived size or rules of
  the existing world: hovering monument, expanding ring, opening void, raised
  floor, displaced wall, or impossible interior extension.
- Bind ground plane, horizon, camera height, subject scale, contact shadow, and
  depth order before rendering.
- QC: scale cue, parallax, shadow direction, foreground/background separation,
  and member/body readability.
- Local status: bounded single-shot geometry is planned local; city-scale or
  full-environment builds are heavy holds.

### Portal, Threshold, Or World-Surface Event

- Use when a door, mirror, floor, screen, circle, or material boundary changes
  world state and the change is visible in the shot.
- Specify the triggering body/object action, surface response, reveal order,
  what becomes visible through the threshold, and the exit state.
- QC: edge integration, reflection/refraction logic, spill light, occlusion,
  and no generic sci-fi portal pasted over unrelated footage.
- Local status: simple masked/planar cases may remain 04FX; actual depth and
  world reveal require 04VFX.

### Tracked 3D Insert

- Use when a title object, symbol, device, interface, or physical prop must stay
  attached to a moving surface or camera view.
- Require stable track evidence, lens/camera assumptions, anchor plane, scale,
  occlusion order, shadow/reflection policy, and off-screen behavior.
- QC: track slip, rolling-shutter mismatch, motion blur, lens distortion,
  crossing limbs/objects, and edge chatter.
- Local status: simple short high-contrast tracks are planned local; complex
  occlusion, fast blur, or full camera solve holds until proven.

### Shadow, Reflection, And Occlusion Composite

- Use when a rendered object must feel physically present in existing footage.
- Treat contact shadow, cast shadow, reflection, light wrap, atmospheric depth,
  and foreground occluders as part of the effect, not optional polish.
- QC: light direction, softness, reflection roughness, color contamination,
  alpha fringe, depth crossing, and member identity edges.
- Local status: bounded clean shots are planned local; hair/finger roto or
  production-clean moving mattes may require an approved external route.

### Particles And Environmental Response

- Use for dust, fragments, sparks, petals, rain, light motes, data fragments,
  or debris only when the particles react to a visible action, object, wind,
  collision, or music event.
- Define emitter, force/direction, density, life, depth, collision, and endpoint.
- QC: no face/body cover, no repeated stock loop, credible motion blur, stable
  depth, and no dense simulation for decoration.
- Local status: sparse/baked particles are planned local; long dense simulation
  is a heavy hold.

### 3D Title Or Graphic Object

- Use when typography or a symbol behaves as an object in the shot rather than
  as a flat caption: cast shadow, occupy depth, collide, reflect, or reveal the
  world.
- Use 04FX instead when flat text or a short title hit is sufficient.
- QC: legibility, material and lighting match, depth relation, screen time, and
  no title object competing with a member's face or action.
- Local status: bounded hero typography is planned local after Blender
  preflight passes.

## Common Holds

- Blender or a required plugin is missing.
- The 04 window is not passed or lacks exact frames and source hashes.
- The requested effect changes timing, source, crop, or speed and must return
  to 04 first.
- The same result is already available through 04FX.
- The reference provides only a mood word, not an observable spatial event.
- Identity, body, object, claim, flash, or source-rights risk is unresolved.
- The shot requires full-character CG, a dense city, long fluid/cloth/
  destruction simulation, or high-sample Cycles by default on M1 8GB.
- Paid/external rendering or asset acquisition lacks current-task approval.

## Reference Comparison

For each candidate, compare at least these observable elements:

- entry object/subject size and screen position;
- camera height, distance, direction, angle, and movement;
- reveal order and duration;
- material and light becoming readable;
- foreground/midground/background contribution;
- object/world reaction;
- endpoint and edit handoff.

Do not score generic visual similarity. The selected reference governs only the
declared directing grammar and never authorizes reuse of its protected object,
brand, character, or scene identity.
