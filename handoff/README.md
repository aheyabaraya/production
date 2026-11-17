# Handoff

Manual handoff space for moving compact context between Grok, Codex, ChatGPT,
or another LLM when the founder explicitly wants it.

This folder is not active production truth by itself. Material here becomes
production input only after the founder selects it and Codex moves it into the
owning run folder, such as:

```text
runs/YYYY-MM-DD/CONTENT_ID/research/
runs/YYYY-MM-DD/CONTENT_ID/00-creative-nucleus.yaml
runs/YYYY-MM-DD/CONTENT_ID/00A-song-lock.yaml
```

For new handoff packets, Drive mirrors, run-owned source packs, and returned
material intake, follow `../wiki/artifact-management-system.md`. The canonical
source should stay in the owning run folder whenever a run exists.

## Folders

- `grok/`: handoffs from Grok CLI/TUI or Grok creative/research passes.
  Start with `grok/CONNECTIONS.md` when checking every active Grok or handoff
  connection point. For post-review local video-prompt work through Grok CLI,
  use
  `grok/flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md`.
- `llm/`: handoffs from generic LLM sessions, including ChatGPT-style planning
  or external model notes.

CF-code ad-mode entries in this folder are frozen historical handoffs, not a
current production start. Historical CF package:
`../../../archive/cf-legacy-20260909/README.md`. Current teaser direction:
`../teaser/AGENTS.md`. Do not load archived CF instructions or edit archived
prompt packets.

## Shared Contract

When moving content into this folder, keep it compact and useful:

- Record the source, date, task, and whether private context was used.
- Preserve selected ideas, useful rejected ideas, open questions, and risks.
- Include source URLs only when they were actually used.
- Do not paste secrets, tokens, env content, browser/session data, or private
  runtime material.
- Do not treat a handoff as a lock, approval, generation instruction, or publish
  approval.
- Mark uncertain claims as uncertain instead of making them sound decided.
