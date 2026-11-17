---
name: idol-front-planning-handoff
description: Prepare compact file-based handoffs, reusable reference-analysis bridges, stable review-projection owner registrations, raw CLI prompts, and selected local reference intake for an active IDOL Front Planning run. Use when routing a bounded task between Codex/Grok surfaces, preventing unnecessary reference rereads in a later session, registering a canonical owner for the stable Founder board, or loading already-cropped reference frames to the canvas.
---

# IDOL Front Planning Handoff

Use this skill only within the active Front Planning integration surface. It
keeps Codex CLI, Grok CLI, Planning threads, and Raw TUI sessions separate while
giving them the same small, hash-bound file pointers.

## Required Reads

Read the active run's canonical Front Planning document, canvas, and, when it
exists, `shared-context/current.json`. Treat them as pointers to the truth, not
text to copy into another provider session. Read
`references/file-contract.md` before creating a task packet or a reference
intake packet. When creating a reusable reference-analysis handoff, also read
`references/reference-reuse-handoff-example.md`. That file is teaching
metadata only; never copy its placeholder values into a run.

## Choose the lightest route

| Need | Route |
| --- | --- |
| Founder is continuing ordinary direction dialogue | Use the selected Planning thread; do not make a handoff. |
| A separately owned Raw Codex/Grok TUI needs one bounded task | Create one `FPHT-...json` task packet, then explicitly send its one-line path prompt to that TUI. |
| A useful Raw-TUI answer needs to survive | Founder or operator writes a compact optional return note; do not scrape or mirror the terminal transcript. |
| A later session should reuse completed reference interpretation | Create one pointer-only run handoff with current owner hashes, section/reference pointers, exact selected-frame inventory, re-review conditions, and the current gate. |
| Existing local crop-lock has selected frames for named song sections | Build an intake packet with `reference_intake_from_crop_lock.py`, then manually sync/apply it to the canvas. |
| A canonical owner result must appear on the stable Founder board | Register its exact owner/pointer adapter in `RUN/work/review-projection-owner-index.yaml`; never hand-author the derived source set. |

Never synchronize, resume, fork, or map a structured session ID to a Raw TUI
session ID. Never put a provider transcript, API credential, or full image bytes
inside a handoff packet.

## File handoff workflow

1. Confirm the task is bounded: one target, one reason, exactly one active
   section (or a whole-video continuity review that authors no section payload),
   and only the selected asset IDs needed for the answer.
2. Save the canonical plan/canvas first. Create the task with
   `tools/workbench.py handoff-task`, or use the Workbench's explicit
   **Handoff → TUI** control.
3. The packet must point to the current plan and canvas hashes. Add the current
   shared context or reference intake only when it materially reduces rereading.
   Include the compact `target_message_screen_contract`—including its selected
   validated audience connections, audience promise/content pillars, whole-MV
   content roles, do-not-serve rules, and only the connection-and-role-bound
   search vectors relevant to the task—the active section,
   previous/next boundaries, and only the reference receipt rows that section
   consumes. Do not copy the full report, full plan, full contact sheets, or all
   sections.
4. In a Raw TUI, send only the generated one-line instruction: read the task
   file, do the bounded task, return a compact result, and do not write
   canonical Front Planning files.
5. Treat the terminal response as transient. Bring a decision back through the
   Founder or a structured planning turn; only then update the document/canvas.

No handoff itself triggers a model call. No return is mandatory. A task packet
is coordination evidence, not a new creative lock.

## Reference-reuse handoff workflow

Use this route only when the reusable source analysis and current-run Front
Planning binding already have their separate canonical owners and the goal is
to prevent a later session from reopening broad selected visual material.

1. Verify the current hashes of the canonical Front Planning owner, the
   pointer index, and every selected-frame manifest the later session will
   traverse. For local video references, also verify
   `source-materials/video-sources/READ-FIRST.md` and its analysis registry.
   A video may be marked complete only when the linked source-owned analysis
   names its actual original-video and one-second inputs, whole-source flow,
   and timestamped who-does-what scene record.
2. For every selected sequence, classify its next use:
   - `interpretation_only`: a bounded strip or sequence bundle may remain the
     evidence because no exact source pixel will govern a later frame.
   - `direct_visual`: every selected phase must have its own stable frame or
     crop path and SHA-256. The whole sheet and review strip remain navigation
     evidence only.
3. Write an exact selected-frame inventory at the owning manifest. Each row
   names the sequence id, frame id, order or phase, source asset id, path,
   SHA-256, target sections, direct-use role, and the existing preserve/discard
   boundary. Extraction may isolate already selected pixels; it may not make a
   new creative selection.
4. Write one pointer-only run handoff. It contains canonical owner paths and
   hashes, the smallest required read order, section-to-reference pointers,
   exact sequence/frame ids, allowed re-review triggers, and the current
   Founder/downstream gate. When a local video is used, put the shared
   `READ-FIRST.md` before the source manifest in that order and point to the
   completed source-owned analysis. It does not restate the reference analysis.
5. Validate every listed file and hash. Hold if a direct sequence points only
   to a broad sheet, a contact sheet, or a review strip.

A session or model change is not a re-review trigger. Changed bytes or meaning,
an incomplete disposition, an identity/safety/feasibility conflict, or an
explicit Founder request may reopen only the affected interpretation.

## Review-projection owner handoff

1. Finish and validate the canonical owner artifact and its required state or
   review receipt before registering it. The board cannot be the first owner of
   a path, role, disposition, eligibility, or approval.
2. Add one exact adapter row to
   `RUN/work/review-projection-owner-index.yaml`. Bind the owner path, SHA-256,
   expected schema version, inventory/state pointers, field pointers, and the
   registered adapter kind. Declare every included adapter kind exactly once.
3. Let the managed Workbench or `idol_review_projection_assembler.rb` compile
   the derived `review-projection-source-set.yaml`. Do not type its digest,
   projection revision, `new_since_last_review`, or pending state by hand.
4. Hold when an owner, dispatch index, eligibility owner, or receipt is missing
   or stale. A source-set or board refresh never creates creative truth, copies
   media, selects a current-next run, creates a task, or infers Founder PASS.
5. When `automation/current-next.yaml` already points to this run, the
   assembler exact-copies the pending projection summary and refreshes its
   derived Markdown. Another run's pointer remains untouched.

## Local reference-intake workflow

1. Use the existing, approved media path first. For every local `yt-dlp`
   capture, registration, migration, or duplicate check, invoke
   `idol-video-reference-hub`; it enforces the approved wrapper, source-hub
   ownership, duration-aware review sheets, and the shared read-first analysis
   registry before human/creative selection and crop-lock. A new source stays
   `미분석` until the source owner registers the detailed analysis; this skill
   does not widen source permission or infer completion.
2. Convert the selected `idol_reference_fragment_crop_lock.v3` to the current
   run's `reference-intake/current.json` using the existing media Python runtime.
   The adapter exact-copies the selected fragment pointer, direct-follow
   strength, and transfer locks so the later key image can name what must
   survive; it does not invent a main/support role.
3. Use **Sync intake** in the Workbench or `apply-reference-intake` while the
   canvas is stable. The operation creates candidate nodes per named section;
   it does not select a winner or add anything to the Scene Build Rail.
4. Arrange only selected derivatives in the order the intended work will be
   made: MV uses audio-section/time order, and a short-form derivative uses its
   opening/retention/payoff/loop order without breaking the master. Label the
   governing main reference separately from supporting references that fill
   named gaps. For CF work, stop and read `cf/AGENTS.md`; this IDOL skill does
   not define the commercial lane's production order.
5. Founder drags/lassos frames, labels them, and uses **Define beat + add** or
   **Add selection** only when the intended screen order is deliberate. Every
   beat states the screen event and the key-image must-carry items: visible
   subject, action or hold, still-camera geometry, composition, space/object
   response, identity when applicable, light/material, and continuity out.

Do not auto-watch folders, import an unassigned broad contact sheet, re-download
registered evidence, or make a model call to decide what enters the canvas.

## Boundaries

- No OpenAI/xAI API endpoint, key, credit purchase, or automatic retry.
- No downstream `00`/`00A`/`01`/`02`/`02A`/`02B` write or lock.
- Contact sheets remain deterministic local review output.
- Teaching examples and past-run handoffs are instruction metadata, not
  creative defaults. Exclude them from context packs, prompt packets, section
  payloads, and production source lists.
- Raw terminal settings such as `/model`, `/reasoning`, `/resume`, and
  `/compact` remain native CLI choices; this skill does not override them.
- Keep task instructions under 6,000 characters, selected asset pointers at 32
  or fewer, and return requests at 1,800 characters unless a deliberate
  operator exception is recorded.
