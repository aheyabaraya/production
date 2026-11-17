# Video Prompt Source Rules

Use this reference only for a cross-surface post-review video-prompt handoff.
For that handoff, Codex is the default author after founder board pass and Grok
is an optional external execution or refinement route when the Founder asks.
When Grok is the Founder-selected active harness owner, it uses the shared
`idol-video-prompt` route and writes canonical prompt records directly.

## Canonical Handoff Order

1. Founder reviews board images and marks records in `03-review.yaml`.
2. Codex runs `scripts/idol_prepare_video_prompt_authoring.rb` when a structured
   source pack is useful.
3. Codex writes the run-owned prompt files, active v7 03V manifest, and section
   QA.
4. If the founder requests Grok/external refinement, use the separate Grok
   handoff wrapper and paste trigger.

## Allowed Motion Sources

When a motion count guide exists, choreography, count feel, cut-to-cut body
progression, and back-dancer echo timing must come only from:

- the passed review board image
- passed Official Core/Branch Production Cut original(s)
- the matching typed Production Cut Review, the Generated Branch-Cut Review
  when the source is a Branch, Audio Production-Cut Placement, and
  storyboard-assist board
- the matching cue sheet row or cue sheet board
- the run-owned `handoff/*motion-count-guide*.md`

The actual Production Cut originals being animated remain the visual and identity
lock. The storyboard-assist board owns timing, blocking, subject route, and
temporal camera motion; Audio Production-Cut Placement owns the ordered audio
windows. The motion count guide remains the primary choreography/count source.

## Image Prompt Source Use

The 02B image prompt export and manifest may be used to recover the approved
scene intent, camera treatment, wardrobe, avoid list, and CUT01-CUT03 framing
that produced the passed review board. Use `compiled_prompt_block.full_prompt_text`
as a compact intent source. Treat the API `render_wrapper` as layout and quality
metadata only; Follow the selected reference function and current-run locks; treat it into the video prompt or use it as choreography as source provenance.

For Official Core/Branch Production Cuts, use the active 01/02A/02B lineage,
typed Production Cut Review, the Branch generated review when applicable,
audio-placement row, and storyboard-assist board as the current image-to-video
source. Those artifacts explain timing and intent, but the pixels still decide
the visible state, composition, and camera position.

## Motion Bridge Rule

For section-image-to-video work, prompt writing must bridge the gap between
approved images. Use section function plus image differences to write the
missing motion:

```text
ordered Branch-Cut state(s) -> body/object route + camera bridge + section intensity -> observable endpoint
```

Use the storyboard board's ordered source Branch-Cut ids and audio placement to
decide which images belong to one bridge. The prompt should state the motion
path, camera transition, audio cue, and endpoint. Do not write a list of
still-image captions, and do not invent choreography outside the approved
Branch-Cut, board, audio, and motion-guide sources.

## Forbidden Motion Sources

Do not infer choreography or count structure from:

- raw `02B-prompt-packets.yaml`
- old Grok prompt drafts
- imagegen render wrapper text
- unrelated research notes
- face reference images as pose, styling, lighting, or choreography sources

Asset context, face references, member registry, unit registry, and voice rail
may be used for identity/member continuity only. They do not unlock new
choreography.

## Missing Guide Rule

If a passed board needs choreography/count detail and the reference pack has no
motion count guide, mark the cue with `motion_count_guide_missing` in the open
decision fields instead of inventing a count structure.
