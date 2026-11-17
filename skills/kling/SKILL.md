---
name: kling
description: |
  Use only when the user explicitly mentions "kling", "Kling", "Kling AI",
  "KlingAI", or asks for a Kling-specific prompt, prompt rewrite, prompt QA,
  image-to-video prompt, text-to-video prompt, start/end-frame prompt, element
  prompt, motion-control prompt, or native-audio/video prompt. Do not use this
  skill for generic video prompting, Sora, Runway, Veo, Grok, OpenAI image/video
  prompts, IDOL graph-engineering routing, 02B image prompt packets, or post-review video
  prompt authoring unless the user explicitly says Kling.
---

# Kling Prompt

Use this skill only when the founder explicitly asks for Kling. It is an
external prompt helper, not an IDOL graph-engineering route, Grok handoff, 02B image
prompt, 03V video-prompt skill, paid generation executor, registry updater,
publisher, or automation step.

## Current-Source Gate

This guidance is a repo-local heuristic snapshot. Kling model names, modes,
audio support, duration limits, settings, and prompt behavior may change. Do not
claim latest/current Kling behavior unless the founder explicitly approves a
current-source check for this task. With approval, verify official Kling
documentation first.

## Read / Write Contract

- Status: active external prompt helper, isolated from the IDOL Graph Engineering.
- Always read: this `SKILL.md`.
- Read for actual Kling prompt drafting or QA:
  `references/kling-prompt-authoring-detail.md`, the user-provided Kling
  mode/context, and any provided source image or existing prompt text.
- Allowed outputs: Kling prompt text, prompt rewrites, QA notes, and suggested
  settings in chat or a founder-named local draft file.
- Forbidden outputs: IDOL graph-engineering artifacts, Grok handoffs, paid generation
  execution, platform upload/sync, registry updates, or claims of latest Kling
  behavior without approved current-source verification.
- Registry behavior: none.
- Founder gates: required for current-source web checks, external upload/sync,
  paid generation, or any durable run/catalog write.

## Mode Router

Pick the generation mode before writing:

1. `text-to-video`: no source image or video; build the full shot from text.
2. `image-to-video`: one source image; preserve the image and describe motion.
3. `start-end frames`: two source images; describe the transition.
4. `elements`: one or more reference subjects/items/scenes; describe the
   interaction.
5. `motion control` or `motion brush`: a reference motion, brush path, or
   controlled region exists.
6. `native audio`: dialogue, narration, singing, rap, ambience, or sound effects
   must be generated with the video.

If the user provides one image, default to image-to-video. If no visual input is
available, default to text-to-video. If the mode is ambiguous and cost/risk is
meaningful, ask one concise question.

## Minimum Prompt Shape

Text-to-video:

```text
[Shot scale] of [specific subject] [one primary action], in [scene with 3-5 concrete elements],
[one main camera move with direction, speed, and endpoint], [lighting], [visual style].
```

Image-to-video:

```text
Preserve the provided image exactly. [Visible subject] [specific movement],
[optional background/object movement], [camera move or static camera],
ending with [clear final pose or settled state].
```

Start/end frames:

```text
Take @image1 as the start frame and @image2 as the end frame. From [start pose/composition],
[subject action route] while [camera route], ending exactly on @image2 with [final pose/composition].
```

## Output Format

Draft:

```text
Kling prompt:
[final prompt]

Settings:
mode: [text-to-video | image-to-video | start-end frames | elements | motion control | native audio]
duration: [5s | 10s | user-specified]
aspect_ratio: [16:9 | 9:16 | 1:1 | user-specified]
quality_mode: [standard | professional | user-specified]

Negative prompt, if supported:
[short avoid list, or "none"]
```

Rewrite:

```text
Rewritten Kling prompt:
[final prompt]

What changed:
- [important fixes only]

Remaining risk:
- [only if a real generation risk remains]
```

## Quality Check

Before returning a Kling prompt, check:

- The task explicitly names Kling.
- Mode is clear.
- The first sentence names visible subject and action.
- Image-to-video prompts preserve the image and focus on motion.
- Camera movement has direction, speed, and endpoint.
- The action fits a 5-10 second clip unless the user requested otherwise.
- There are no more than three sequential subject actions.
- The prompt avoids exact high counts, impossible physics, and overloaded scene
  detail.
- Native-audio prompts label every speaker and do not assume unsupported
  language behavior.
