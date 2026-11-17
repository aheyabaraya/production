# Prompt Packet Legacy Review Board Policy

Read this only for explicit historical storyboard-board diagnostics. It is not
an active generation path. Active 02B v2.1 Branch-Cut prompts must not ask the
model to render boards, labels, coordinate wrappers, support panels, or
triptychs.

## Legacy Diagnostic Scope

The legacy board is for founder visual review, not an audit sheet. It may be
used only when a run explicitly needs to inspect an older board artifact.

Do not copy `keyframe_framing_lock`, `imagegen_guard`, or any legacy board field
into a current packet. Active packets use the v2.1 structured five-line
Core-Cut/Branch-Cut contract.

## Legacy Layout Rules

If diagnostic rendering is explicitly required, keep the board visual-first and
readable:

- fixed top-left label block with only short packet number, section label,
  source timecode, and visible AURORA-M member codes/names
- fixed horizontal coordinate wrapper with the declared internal variant
- CUT01, CUT02, and CUT03 are the large top storyboard triptych
- CUT panels vary camera angle, shot scale, or composition intensity while
  preserving one continuous beat
- no right reference strip, face photo panel, wardrobe swatches, background
  swatches, support panels, checklist, or long text beside the image
- visible text limited to the short label block and CUT labels inside matching
  panels
- no more than two visible generated members per board

Face-only crops from `identity_lock.member_references` are API identity inputs
only. Preserve identity while matching scene lighting, exposure, color
temperature, shadows, skin tone continuity, neck/shoulder connection,
perspective, and scale. Do not paste a head or cutout onto a generated body.

## Legacy Render Guard

If the diagnostic wrapper is used, include high-quality/proportion guards:

- clean anatomy
- natural elegant idol proportions
- readable hands, fingers, and feet
- grounded weight
- coherent lighting direction
- controlled exposure
- consistent color temperature
- soft realistic shadows

Negative guards should cover warped limbs, extra fingers, broken hands,
pasted-face lighting, pasted heads, mismatched necks, skin-tone breaks, wrong
perspective scale, and distorted proportions.

## Active Boundary

Operational notes, validation comments, local paths, source audit notes, and
long justifications stay in historical records, not in rendered prompt text.
No active packet or execution adapter may consume this policy as a compatibility
fallback.
