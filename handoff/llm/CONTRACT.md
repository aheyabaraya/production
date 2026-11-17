# LLM Handoff Contract

Use this folder for handoffs from generic LLM sessions, including ChatGPT-style
planning, outside model brainstorming, or compact summaries that should be
revisited later.

## What The LLM Should Leave

Each handoff should capture:

- source model or session label
- date
- task prompt summary
- key decisions proposed
- useful alternatives
- assumptions and uncertainties
- files or schemas it thinks are relevant
- founder decisions still needed

## Boundaries

- LLM notes are advisory unless the founder selects them.
- GPT/LLM outputs are creative draft/reference inputs inside the IDOL harness,
  not creative owners and not canonical source files.
- Do not paste secrets, credentials, env data, browser/session contents, or
  unpublished private assets unless the founder explicitly approved that for the
  current handoff.
- Do not overwrite run files based only on this handoff.
- Do not present guesses as locked IDOL facts.

## Codex Intake

Codex should treat this as a staging area. Before moving anything into
production, Codex checks `AGENTS.md`, schemas, skills, assets, and current run
files, then asks for founder selection when needed.

For placement of source packs, Drive mirrors, returned files, and run-owned
intake records, follow `../../wiki/artifact-management-system.md`. Global LLM
handoff notes are advisory pointers; selected material must be copied into the
owning run before it patches production artifacts.

## 02A GPT Review Flow

For 02A storyboard review through GPT or another general LLM, use:

```text
handoff/llm/02a-gpt-review-flow.md
```

The drive-sync pack is a temporary review copy. For album/title song work, use
`drive-sync/02_GPT_GROK_HANDOFF/albums/ALBUM_KEY/TITLE_KEY/source-pack-vN/`;
returned notes, images, manifests, and alternatives stay in the same
album/title `incoming/` folder until Codex intake. The pack may include
run-owned source files, review sheets, wardrobe references, founder-provided
visual boards or reference images, and active unit face references for manual
GPT upload, but the canonical files remain under `runs/`, `assets/`,
`source-materials/`, and the matching album/title catalog registry.
Founder-selected reference images must be copied into the run-owned
`review/02a-reference-intake-vN/` folder with source path, copied path, hash,
target beats, preserve/discard locks, patch targets, and identity-first priority
before they can patch 02A. After founder-selected GPT review changes are applied
and 02B prompt-packet regeneration starts, delete only the temporary drive-sync
source pack. If a normalized response needs to go back through Drive, place it
under the album/title `outgoing/` folder without overwriting the original
`incoming/` files.
