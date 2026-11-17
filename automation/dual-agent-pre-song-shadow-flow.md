# Dual-Agent Pre-Song Shadow Flow

## Purpose

Use this optional shadow flow when the founder wants Codex and Grok to both
help before the song direction is locked. It is for early research, route
comparison, and MV storyline exploration. It does not replace PRE-00, `00`, or
`00A`; it gives the founder better options before those files become serious
production truth.

## Placement

```text
founder seed or rough song intent
-> optional dual-agent shadow pass
-> PRE-00 route selection or direct 00 draft
-> 00 creative nucleus
-> 00A song lock
```

Run it before `00A-song-lock.yaml` when the song is still being chosen, or when
the founder wants competing story/song routes before committing.

## Roles

- Hermes: calls workers, stores raw outputs, and records comparison state.
- Codex: researches, checks sources, reads local IDOL truth, verifies asset fit,
  and synthesizes the founder-facing recommendation.
- Grok: produces external creative/trend research, emotional routes, hooks, and
  storyline alternatives from a redacted packet.
- Founder: chooses the route, review direction, song intent, and whether
  anything moves into `00` or `00A`.

## Safety Boundary

Grok TUI operates with the same repository access as Codex. Both work directly
inside this repo. When running a shadow pass, Grok may still receive a redacted
or limited task packet depending on the sensitivity of the exploration, but it
does not require running outside the repository (e.g. in `/private/tmp`).

Send Grok only the context necessary for the task unless the founder explicitly
approves sharing additional internal IDOL material.

Do not send these to Grok by default:

- member registries, private run YAMLs, face references, generated boards, or
  unpublished assets
- secrets, tokens, env files, browser/session stores, or private runtime folders
- locked production files unless the founder explicitly approves that context

## Standard Packet

The packet should be short and explicit:

```yaml
task_type: pre_song_shadow
founder_seed:
song_intent:
emotion_arc:
must_avoid:
public_research_allowed: false
private_context_allowed_for_grok: false
requested_outputs:
  - codex_research_notes
  - grok_creative_routes
  - mv_storyline_options
  - codex_synthesis
```

## Worker Outputs

Codex should return:

- source-grounded research notes when research is approved
- song direction risks and open questions
- IDOL asset/unit fit checks
- a compact recommendation for founder selection

Grok should return:

- 2-5 creative routes or storylines
- first 15s ideas, hook/motif options, and emotional arc variants
- no claims about private IDOL assets unless they were included in the redacted
  packet

## Storyline Pass

When a song or song seed is being chosen, ask both workers for one or more
90-second MV storyline options before `00A` is locked. The storyline pass should
answer:

- what the viewer feels in the first 15 seconds
- what emotional turn happens before the chorus
- what image or movement makes the hook memorable
- what short-form derivative naturally comes from the master
- what risk could make the route feel generic, unsafe, or off-brand

## Handoff

Raw worker outputs should stay in a run-owned folder once a run exists:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/dual-agent-shadow/
  task-packet.yaml
  codex-output.md
  grok-output.md
  codex-synthesis.md
```

If no run exists yet, keep the temporary comparison in `automation/` and move
only founder-selected material into the later run folder.

## Founder Gate

This flow may recommend, compare, and draft. It must stop before:

- locking `00` or `00A`
- paid generation or media API calls
- public posting, upload, scheduling, or syncing
- overwriting production YAML
- promoting memory

Founder selection is the only thing that turns a shadow route into production
input.
