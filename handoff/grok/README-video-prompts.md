# IDOL Video Prompt Routing

This page is a routing note, not a second prompt-authoring specification. The
active creative contract is `skills/idol-video-prompt/SKILL.md`; the only Grok
03V execution detail lives in
`flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md`.
CF-code is frozen under the IDOL `AGENTS.md` boundary; stop here for CF
work. Its archived instructions do not open an active production route.

## Canonical Owner

Video prompt truth stays under:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video-prompts/
```

The active v8 03V manifest, section QA record, canonical prompt files, and any
upload-ready package are run-owned surfaces. `handoff/` and `drive-sync/` are
derived operator surfaces and never become a second canonical prompt store.

When Grok is the exact 03V section owner selected by the current run and
Department Dispatch, it authors only that section's run-owned canonical output
through `idol-video-prompt` and does not create this handoff package. The routes below apply only to a requested cross-surface
transfer.

## Common Preparation

Assigned 03V authoring and a requested Grok handoff begin from the same
hash-bound 03V source discovery, typed Production Cut Review, Audio
Production-Cut Placement, and source-set digest:

```text
ruby scripts/idol_prepare_video_prompt_authoring.rb \
  runs/ALBUM_KEY/TITLE_KEY/RUN_ID
```

Use `--write` only when the required source gate is ready and the task
authorizes materialization. The default written pack is
`runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/03V-authoring-source-pack.yaml`.
This prepares a derived bootstrap; it does not replace the owning skill, policy, schema, 02A,
02B, Founder review, or 03V source truth.

## Optional Grok Route

Only after the Founder explicitly requests Grok app/TUI/CLI prompt work:

```text
ruby scripts/idol_prepare_grok_video_prompt_handoff.rb \
  runs/ALBUM_KEY/TITLE_KEY/RUN_ID \
  --source-pack runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/03V-authoring-source-pack.yaml \
  --founder-requested
```

Add `--write` only to materialize the validated derived request. The adapter
reads the already-written source pack, rechecks its exact sources through the
common preparation without writing, verifies the same source-set digest, and
validates its reference pack against
`schemas/grok-video-prompt-reference-pack.schema.json`.

The assigned 03V owner processes only its exact section, one cue or a bounded
contiguous cue group at a time from the compact reference pack. The central index preserves whole-film
order, source lineage, and section-close QA; the handoff reference pack binds
the common source-set digest. Full 02A/02B or research trees are reopened only
for a named missing projection or contradiction.

## Prompt Boundary

The attached image pixels own appearance, identity, styling, world, light,
material, and visible start state. Generator-facing text spends its words on:

- the first observable trigger;
- visible subject/object/environment/system motion or an intentional hold;
- camera height, scale/distance, direction/angle, depth, placement and crop;
- a motivated camera route, timing, endpoint, and edit handoff.

Internal cut, packet, section, source, schema, skill, and Founder-review ids
stay in the active v8 03V manifest, never `prompt.txt`. When upstream
choreography presence is `absent`, the generator prompt omits every dance or
choreography activation term, including negative wording. Acting, gaze, body
holds, and object/environment behavior may remain when authored. A
non-member-led frame remains object-, environment-, or system-led.

## Still Image Tool Route

Grok image-to-image execution is a separate 02B adapter. It follows:

```text
flows/02B/image-prompts/GROK-IMAGE-LOCAL-SOURCE.md
```

That route consumes an already-authored, hash-bound provider-neutral image
request. It may attach the exact approved visible-face identity inputs followed
by the exact declared visual references and execute the request, but it may not
invent or rewrite creative prompt content.

## Mirrors And Legacy Material

Create a Drive mirror only on an explicit Founder request, after canonical
validation. Old `flows/02-03/grok-imagine/` packages and legacy Drive staging
are archive/recovery evidence, not the active video-prompt or image-tool route.
File presence never means generation approval, playback pass, or public-release
approval.
