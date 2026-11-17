# 03 Review Video Prompt Flow

harness_step: 03-review
flow: video-prompts

Use this flow only for a Founder-requested cross-surface handoff after the
typed Production Cut Review passes. It carries passed storyboard-assist boards
and passed Official Core/Branch Production Cut originals to an
external Grok refinement/execution route. The exact Grok 03V section owner selected by the current run and Department
Dispatch uses `idol-video-prompt` directly for its own section; it does not enter
this handoff flow or merge canonical whole-video bytes.

Do not create or refresh `drive-sync/02_GPT_GROK_HANDOFF/` for this flow unless
the founder explicitly asks for Grok/Drive handoff.

Shared source-pack entrypoint before a handoff:

```text
ruby scripts/idol_prepare_video_prompt_authoring.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID --write
```

Optional Grok handoff entrypoint:

```text
ruby scripts/idol_prepare_grok_video_prompt_handoff.rb runs/ALBUM_KEY/TITLE_KEY/RUN_ID --source-pack runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/03V-authoring-source-pack.yaml --founder-requested --write
```

The optional Grok helper writes the validated local reference pack:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/grok/03V/grok-03V-reference-pack-v1.yaml
```

Canonical outputs belong in:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/generations/video-prompts/
```

Write one canonical prompt record per passed 03V storyboard board. `@image1`
is the storyboard authority for timing, blocking, subject route, and temporal
camera motion. `@image2` through optional `@image4` are the ordered Official
Core/Branch Production Cut originals and remain the pixel authority for
appearance, composition, and visible states.

Video prompts may include camera technique as well as camera angle. Angle/framing
states the view inherited from the passed image or source plan, such as low
front, side track, rear three-quarter, close-medium, or medium-wide. Camera
technique states how the camera behaves over time, such as gimbal follow, dolly
backward, lateral track, push-in, punch-in on a hit, tilt from boot to face,
rack focus, foreground parallax, recoil from a near-lens hand, locked stop,
angle- or direction-matched cut, reflection match cut, object/garment occlusion
wipe, anchored orbit, or slight diagonal/Dutch tilt. Use technique only when it
follows the visible body route and preserves the passed image lock; do not add
random orbit, random pan, an unrelated new angle, or a transition that hides an
impossible pose jump.

If founder/GPT/reference choreography images arrive after 02B generation, they
are video-only motion references. Codex must copy selected images into
`runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/03v-motion-reference-intake-vN/` with source
path, copied path, hash, target beats, preserve/discard locks, and identity
priority before using them. They may refine prompt motion language but do not
patch 01/02A/02B, replace the passed Production Cut visual lock, or become paid image API
inputs by default.

During that intake, analyze camera in two layers. First record observed still
geometry: camera height, direction, shot scale, frame geometry, subject
placement, foreground/depth cue, floor/reflection, and crop pressure. Then
record inferred camera technique only when the image gives a visible basis:
gimbal follow, dolly-back, lateral track, push-in, punch-in, tilt, rack focus,
foreground parallax, recoil, locked stop, angle- or direction-matched cut,
reflection match cut, object/garment occlusion wipe, anchored orbit, or slight
diagonal/Dutch tilt. Still images do not prove a camera move; if the basis is
weak, keep the prompt to locked hold or subtle push. When a bridge crosses a
cut, name the inherited direction, speed, step phase, foot/floor contact, hand
path, garment swing, or body momentum.

The historical `video-prompt-index.yaml`/Drive mirror route is not an active v8
transport. For a Founder-requested external transfer, prepare the validated
run-owned request and source pack with the active handoff builder:

```text
ruby scripts/idol_prepare_grok_video_prompt_handoff.rb \
  runs/ALBUM_KEY/TITLE_KEY/RUN_ID \
  --source-pack runs/ALBUM_KEY/TITLE_KEY/RUN_ID/handoff/03V-authoring-source-pack.yaml \
  --founder-requested \
  --write
```

The run-owned prompt files and any explicit handoff request must also be
registered in:

```text
catalog/albums/ALBUM_KEY/TITLE_SONG_KEY/output-registry.yaml
```

### Live Grok Real-Time Testing Exception (Founder-Requested)

When the founder explicitly requests a live sequential testing loop with direct Finder/drive work and external generators (instead of pure Codex authoring), the reusable protocol applies:

- `handoff/grok/LIVE_GROK_PROMPT_TESTING_PROTOCOL.md`
- Per-session activation uses a visible `LIVE_GROK_SEQUENTIAL_PROMPT_TESTING.md` marker in the drive-sync folder + declaration in the active handoff document.
- While active: drive-sync prompt.txt files are the hot path for fast micro-iteration. Canonical layers (run-owned, PKT, 03V, index) are promoted only on explicit founder acceptance/sync signals.
- This is a temporary exception to support creative speed; full reconciliation is required when the live phase ends.

See the protocol document for activation steps, invariants, and deactivation.

For current workflow rules, see:

- `handoff/grok/README-video-prompts.md`
- `handoff/grok/flows/03-review/video-prompts/GROK-CLI-IDOL-VIDEO-PROMPT-LOCAL-SOURCE.md`
- `handoff/grok/references/video-prompt-source-rules.md`
- `handoff/grok/templates/video-prompt-template.md`
- `schemas/video-prompt-manifest.schema.json`
- `schemas/grok-video-prompt-reference-pack.schema.json`
