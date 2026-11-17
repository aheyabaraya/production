# Identity Guard — Track Poster

Full-body key visuals carry higher face, neck, head-to-body, limb, and lighting
drift risk than clean portraits. Identity is therefore a local authoring gate
and a generated-output review gate, not a reason to paste a fixed taxonomy into
every prompt.

## Local Evidence

Inspect the member character board and current-title identity source together.
Use the character board to judge multi-angle face geometry and body proportion;
use the current-title source for the approved current identity, skin/light
behavior, and expression baseline. Fall back to the current clean profile only
when no current-title identity source exists.

Also inspect the intended crop and pose. A face may remain accurate while the
head/neck/shoulder connection or limb scale drifts in a full-body composition.
Judge the whole visible figure.

This identity check verifies the current attachment and generated result; it
does not reopen a bound reference's current-song interpretation.

## Provider Boundary

Local inspection is always separate from external attachment permission.

- Grok/native or manual I2I may receive only the exact images approved for that
  current job and recorded by path/hash/order.
- OpenAI track-poster work is `gpt-image-2` only and has no standing upload
  allowlist. Do not attach the character board or any other non-allowlisted
  image without an exact later policy/Founder approval for the job.
- Text-only generation is not production-ready when a visible member identity
  cannot be grounded in an approved provider input.

## Prompt Language

Use a compact positive lock, adapted to the actual approved attachments:

```text
Use the attached current-title identity image as the identity source for the
visible member; preserve the same recognizable face and natural body scale
while following this prompt for expression, pose, wardrobe, camera, and space.
```

Do not claim an unattached image is attached. Do not enumerate facial anatomy
unless a prior output failed on that exact feature. Negative language should be
specific to observed risk, such as pasted-head lighting, neck disconnection,
changed head-to-body ratio, extra fingers, or generic-idol face drift.

## Output Review

Before Founder review, check:

- recognizability against the current-title identity source;
- face angle and expression still fit the prompt rather than copying a source
  photo's expression;
- neck, shoulder, head, torso, hand, foot, and limb scale form one body;
- shared light direction, exposure, color temperature, and shadow across face,
  body, wardrobe, and environment;
- no beauty-face lighting pasted onto a differently lit world;
- no generic-idol beautification or fashion-model proportion drift;
- no reference image, board, caption, or process mark rendered into the frame.

Any failed identity or proportion check is a hold. Do not hide it by cropping
the face out, changing member ownership, or weakening the current-title visual
system.
