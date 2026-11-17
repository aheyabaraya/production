# Grok Image Tool Local Source Runbook

purpose: execute one already-authored IDOL still-image request through the
registered Grok `grok_image` adapter and its pinned native tool
status: active only after an explicit Founder request for the exact image job
canonical_output: the run-owned path declared by the selected 02B packet

This is an execution adapter inside Image Prompt Compile [02B]. It is not a new
harness stage, does not author a camera/action/identity/world decision, and does
not replace `idol-generation`, 02A, 02B, Founder review, or paid-generation
approval.

## Required Start

From the IDOL repository root, follow this order:

1. Read `AGENTS.md`.
2. Read `wiki/production-system.md`.
3. Read `wiki/INDEX.md`.
4. Read the task-activated policies named by `AGENTS.md`, including creative,
   routing/source, section, and media/security policy for this route.
5. Read `handoff/grok/current.md` and
   `handoff/grok/HARNESS-STEP-COMMANDS.md`.
6. Read `skills/idol-generation/SKILL.md` from start to finish and only the
   operation-required linked references.
7. Read this runbook and the exact run-owned generation request.

Do not load an archived handoff, another title, a broad research folder, or a
Codex-only image-generation plugin. The repository contract and run-owned
request are sufficient.

## Prepare The Derived Request

Prepare one request for one exact 02B packet:

```text
ruby scripts/idol_prepare_image_generation_request.rb \
  runs/YYYY-MM-DD/CONTENT_ID \
  --source-prompt-packets runs/YYYY-MM-DD/CONTENT_ID/02B-prompt-packets.yaml \
  --packet-id PACKET_ID \
  --approval-source RUN_OWNED_APPROVAL_PATH
```

The command above is a dry check. It does not approve or execute generation.
When the Founder has approved the exact external and paid job and supplied the
run-owned approval source, prepare the writable request with the matching
approval source:

```text
ruby scripts/idol_prepare_image_generation_request.rb \
  runs/YYYY-MM-DD/CONTENT_ID \
  --source-prompt-packets runs/YYYY-MM-DD/CONTENT_ID/02B-prompt-packets.yaml \
  --packet-id PACKET_ID \
  --approval-source RUN_OWNED_APPROVAL_PATH \
  --write
```

Writing the request still does not invoke a provider tool.

## Exact Input Contract

Open the generated `idol_image_generation_request.v10` artifact and verify:

- `status` is `ready`;
- `source_prompt_packet` binds active 2.4 bytes, JSON pointer, and value hash;
- `prompt.full_prompt_sha256` matches the exact five-line
  `prompt.full_prompt_text` bytes;
- `quality_contract.render_quality_terms` contains exactly
  `4K`, `high quality`, and `high detail`;
- every `attachments[]` actual file is readable, pixel-inspected, locked, and
  SHA-256 current;
- attachments preserve exact numeric order: current-title member visuals,
  governing scene/Sequence references, then supporting component references;
- every reference is used only for its declared `role`, `preserve`, and
  `discard` contract;
- `execution.execution_adapter_id` is `grok_image` and provider/auth/profile
  snapshots are hash-bound;
- one or more attachments selects `image_edit`; zero attachments selects
  `image_gen`;
- prompt rewriting and provider/auth/model/tool fallback are `forbidden`/`none`;
- `expected_output.path` remains inside the owning run and output count is one.

The actual selected images must be inspected and attached. Do not replace them
with function-only summaries, filenames, or remembered descriptions. Their
bytes remain the reference authority for the approved role.

## Grok Image Tool Execution

For one request:

1. Start a fresh Grok image generation session for only the declared section;
   do not reuse the prompt-authoring session.
2. Attach every `attachments[]` image in exact numeric order and preserve its
   declared role. Current-title identity inputs remain identity-only.
3. Invoke the request's pinned `selected_native_tool`: `image_edit` with one or
   more attachments, or `image_gen` with zero attachments.
4. Pass `prompt.full_prompt_text` byte-for-byte. Do not rewrite, shorten, embellish, or add
   a provider-style preamble.
5. Generate only the requested still image at the highest available quality and
   maximum supported dimensions for the locked aspect ratio.
6. Save the result to `expected_output_path` or return the local generated file
   for Codex intake when the UI cannot write there directly.
7. Record observed output path, status, and any visible failure. Do not infer a
   Founder pass from file presence.

This adapter works for an already-authored planning Hero Core, Official Core, or Official Branch only
when that exact job already exists as locked 02A/02B truth. A track key visual
or pre-02 visual/space exploration remains owned by its active Front Planning /
01 route and `idol-track-poster` or other explicitly selected owning skill; do
not falsely recast it as a 02B packet. Grok may not invent a missing prompt,
camera, action, composition, reference role, or identity choice during
execution.

## Reference And Identity Rules

- Identity references remain identity-only.
- Album or scene references keep their declared camera, space, light, texture,
  object, material, or action-center role; they do not silently become identity
  sources.
- A cached or indexed image is not upload permission. The exact request must
  carry current-job attachment approval.
- Do not substitute a character board, contact sheet, unrelated reference, or
  another title's album asset.
- Do not add a dance or choreography idea merely because the target is an idol
  image. If the upstream visible action contains no dance, the prompt and
  execution remain dance-free.

## Stop Conditions

Stop instead of improvising when:

- the request is `hold`;
- approval evidence is missing;
- a source or image hash is stale;
- an expected reference image is missing;
- the requested prompt differs from the 02B-bound bytes;
- the reference role is ambiguous;
- the output path escapes the owning run;
- the Grok surface would require a creative rewrite to proceed.

This route never approves publishing, Drive mutation, canonical 02A/02B
changes, deletion, or public release.
