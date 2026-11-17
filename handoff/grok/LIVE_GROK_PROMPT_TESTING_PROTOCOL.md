# LIVE_GROK_PROMPT_TESTING_PROTOCOL

**Purpose**: Defines the temporary operating mode for founder-requested real-time iterative refinement of video prompts (or similar creative generation work) using Grok + external generators, while the founder works directly from Drive/Finder.

This protocol exists because the full IDOL harness middle contracts (03V, video-prompt-index, PKT structured records, run-owned canonical files) are intentionally "heavy" to support automation, section QA, edit handoff, resumption, and auditability. Applying full sync discipline on every micro creative direction makes live sequential testing loops impractically slow.

The protocol allows speed during the creative discovery phase without permanently weakening the contracts that automation relies on.

## When This Protocol Applies

- Founder explicitly requests Grok/Drive handoff for live, sequential, real-time testing (e.g. "finder에서 열어줘, 프롬프트들이랑 같이 보면서 작업하게", "b01 지금 할게 순차적으로 만들어가보자").
- Typical triggers: post-02B / 03V video prompt refinement where the founder wants to test many short bridge-two-image (or single-beat) clips one by one with immediate external generation feedback and micro adjustments (body action, camera catch, timing, arm lift, zoom behavior, etc.).
- Scope: Primarily 03-review video-prompt work, but the pattern can be adapted to other live Grok creative iteration sessions when the same speed-vs-contract tension appears.

It does **not** apply to normal Codex authoring, automation-driven steps, or when the founder has not requested the live Drive loop.

## Activation (Per-Session)

1. The active handoff document (the file pointed to by `handoff/grok/current.md`, e.g. `handoff/grok/video-prompts.md` or equivalent for the run) must contain a clear "Current Operating Mode: Live Sequential Prompt Iteration" declaration that references this protocol.
2. In the corresponding drive-sync folder for the session (e.g. `drive-sync/02_GPT_GROK_HANDOFF/03-review_..._video-prompts/CONTENT_ID/`), create a visible marker file named `LIVE_GROK_SEQUENTIAL_PROMPT_TESTING.md` (or `LIVE_GROK_PROMPT_TESTING.md`).
3. The marker file should:
   - State that live mode is active.
   - Reference this protocol document.
   - Summarize the session-specific sync policy and signals.
   - Be placed at the top level of the drive-sync session folder so it is immediately visible when the founder opens the folder in Finder.
4. Optionally note the exception in the drive-sync README.md for that session (the generated README normally says "edit run-owned first").

The presence of the `LIVE_GROK_..._TESTING.md` marker file in the working drive-sync folder + the declaration in the active handoff is the operational signal that "we are in live mode for this session."

## Operating Rules While Live Mode Is Active

**Hot path (fast iteration):**
- The prompt.txt files inside the upload packs in the drive-sync folder (`video-input-packs/.../bridge-two-image/XX_Bxx/prompt.txt` or equivalent) are the primary working copies.
- Grok prioritizes editing only the relevant drive-sync prompt.txt, translating the founder's Korean creative direction into strict observable screen language (per AGENTS.md and the idol-video-prompt skill's strict language filter), and immediately surfacing the full clean prompt block for copy-paste.
- This supports the sequential per-cue loop the founder typically uses ("B01 now", "next", specific feedback like "make the zoom-in catch sharply on the transition to image 2").

**Canonical / harness contract path (batched):**
- Run-owned canonical files (`runs/.../generations/video-prompts/.../prompt.txt`)
- PKT_*.md records (Ready-to-Use blocks and analysis)
- 03V-video-prompt-manifest-v5.yaml (camera action, camera route, body route, endpoint, adjacent continuity, pacing, and Branch-Cut lineage for each cue)
- the hash-bound 03V authoring source pack and storyboard-assist board used by that cue
- These are **not** updated on every micro tweak.

Promotion to the canonical layers happens only on explicit founder signals such as:
- "이 버전으로 가자"
- "accept Bxx" / "이 clip은 이 방향"
- "sync 해", "batch sync", "지금 sync"
- Natural boundaries (end of a section, after several clips are stable)
- Or when the founder declares the live loop complete.

While the marker is active, temporary divergence between drive-sync prompt.txt and the canonical records is expected and declared.

**Non-negotiable invariants (never relaxed):**
- All AGENTS.md rules (mandatory starting ritual at the beginning of relevant work, internal English / user-facing follows user language, observable screen language in generator-facing text, no abstract labels, no reintroduction of banned terms).
- idol-video-prompt skill language filter for prompt.txt.
- Exact fidelity to the chosen @image1 / @image2 files, identity, outfit, lighting, environment.
- Avoid lists and safety/identity guards.
- Previous/next continuity and section logic must still be respected in the prompt prose even if the full 03V/index fields are updated later.

## Deactivation / End of Live Phase

When the founder signals the end of the live sequential testing (e.g. "live 끝", "이제 harness로 넘겨", "full sync 해", or after all clips in scope have been iterated to satisfaction):

1. Rename or mark the per-session marker as `LIVE_GROK_SEQUENTIAL_PROMPT_TESTING_COMPLETED_YYYY-MM-DD.md` and add a short summary of accepted directions if useful.
2. Perform a full reconciliation pass: promote all accepted clip directions into run-owned prompt files, PKT records, 03V cue fields (camera, body, endpoint, continuity), and video-prompt-index.
3. Validate the video-prompt-index and any section QA artifacts.
4. Optionally re-run the official drive sync script so the drive mirror reflects the final canonical state.
5. Update the active handoff document to remove or mark the live mode declaration as completed.
6. Return to normal discipline: edit run-owned first; drive copies are mirrors only.

After deactivation, the harness contracts (03V + index + run-owned) must accurately reflect the final chosen prompt behavior for any downstream automation, 04 edit, package, or future resumption.

## How to Activate for Future Sessions ("Next Time")

When a new founder-requested Grok/Drive video prompt (or similar) handoff is created:

1. Follow the normal Grok handoff setup (the scripts or manual equivalent that populates drive-sync for the run).
2. In the new active handoff document (the file `handoff/grok/current.md` will point to), add a "Current Operating Mode" section that says live sequential prompt testing is active and references this protocol + the per-session marker.
3. In the drive-sync folder created for that session, place a `LIVE_GROK_SEQUENTIAL_PROMPT_TESTING.md` marker (copy/adapt from a previous completed one or from this protocol).
4. Update the generated drive-sync README.md with a temporary exception note pointing to the marker.
5. Tell Grok (or the person doing the work) that the live protocol is now in effect for that session.

The protocol is activated per-run by the combination of the marker file + handoff declaration. It is deactivated by completing the marker and reconciling.

## Relation to Other Documents

- This is an execution surface exception documented under `handoff/grok/`.
- It does not change core harness rules in AGENTS.md, wiki/production-system.md, or the idol-video-prompt skill.
- It complements the existing flow docs: `handoff/grok/flows/03-review/video-prompts/README.md`, `GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md`, `handoff/grok/README-video-prompts.md`, and the drive sync scripts.
- The drive-sync READMEs (per-session) document the normal "canonical first" rule and note this as a temporary exception when the marker is present.
- When in doubt, the active handoff document + the per-session LIVE marker take precedence for the duration of that live loop.

## Maintenance

Update this protocol when the underlying tension (live creative speed vs. harness contract integrity) changes, or when new patterns emerge from repeated use. Keep the per-session marker lightweight (reference this document + session details + acceptance signals).

Created to address founder feedback on iteration speed during real-time video prompt testing while preserving long-term automation viability.
