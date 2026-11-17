# PULSO Live Compact Prompt Playbook

Reusable workflow for founder-driven Grok Imagine sequential clip testing on
`0611_WORLD_CUP_PULSO` (and the same pattern on future runs).

This documents the method that produced good live results in the Jun 2026
`#035–#062` iteration loop. It complements:

- `.grok/skills/idol-grok-live-video-prompt/SKILL.md` (prompt voice)
- `handoff/grok/LIVE_GROK_PROMPT_TESTING_PROTOCOL.md` (harness sync boundary)

## What This Mode Is

- **Goal**: Ultra-compact, image-grounded prompts the founder can copy-paste
  into Grok Imagine with the exact test image for each assembly number.
- **Not goal**: Full canonical `prompt.md`, 03V manifest, or PKT sync on every tweak.
- **Hot path images**: clip-folder `image1.png`, not review-board PNG alone.

## Folder Map (PULSO draft-v1)

```text
runs/2026-06-11/0611_WORLD_CUP_PULSO/
  review/03v-section-assembly-manifest-v1.yaml   # assembly_seq, timing, member, screen_role
  research/audio-motion-director-map-v2.yaml       # lyric cue per slot (C18, C19, ...)
  generations/video/generated-clips/03v/pulso-main/draft-v1/
    NNN_PACKET_NAME/image1.png                     # upload image for Grok (founder truth)
    NNN_PACKET_NAME/active-image-moderation-safe-crop.png   # optional waist-up crop
  generations/video-prompts/draft-v1/
    NNN_PACKET_NAME/prompt-compact.md
    NNN_PACKET_NAME/prompt-compact-moderation-safe.md       # if moderation blocks
    NNN_PACKET_NAME/source_paths.txt                          # live notes
    COPY-PASTE-START-END.txt                                  # batch copy bundle
```

## Per-Batch Workflow

### 1. Lock the number range

Read `03v-section-assembly-manifest-v1.yaml` for the requested `assembly_seq`
range (e.g. 53–62). Record per cut:

- `assembly_seq`, `packet_id`, member code, `screen_role`
- `start_seconds` / `end_seconds` (for COPY-PASTE header timestamps)
- `prev_end_to_start` / `end_to_next_start` (continuity hint only; do not paste harness labels into prompts)

### 2. Read lyric cues

From `audio-motion-director-map-v2.yaml`, take the slot lyric for that cut
(e.g. C18 → `Breathe in deeper`, C21 → `The whole world on one beat`).

### 3. Re-read every test image

**Mandatory whenever the founder says images changed.**

Open each clip folder's current `image1.png` and describe only what is visible:

- idol present or NOIDOL
- member-consistent look (hair, face paint, outfit colors, mic, pose)
- space (stands aisle, pitch, stage edge, crowd block, wide empty field)
- key objects (ball, referee, drum, scarf, flag banner, phone lights)

**Image wins over manifest** when they disagree (e.g. #055 crowd-only though packet name includes M04).

Check `image1.png` file timestamp after founder uploads.

### 4. Write one compact prompt per cut

Follow `idol-grok-live-video-prompt` shape:

```text
cinematic 4K IDOL music video, high quality.

Start from the provided image exactly. [One sentence: who/where/what is visible in THIS image.] On "[lyric cue]" [one visible action phrase tied to rhythm/lyric]. [One camera sentence: hold, track, small push, side drift — motivated by the action.]

Avoid [short targeted list for this shot].
```

Rules that mattered in practice:

- **Thin**: 1–2 short paragraphs max.
- **Observable only**: no harness ids, Bxx labels, "previous handoff", abstract mood-only phrases.
- **NOIDOL shots**: open with `No idol appears` / `No idol on the pitch`.
- **GLOW-named slots**: body/crowd pulse only — no glow, aura, beams, light trails.
- **Extend block**: add only when founder explicitly requests extend mode.
- **Movement**: prefer step/travel/track over static pose unless image demands a hold.

### 5. Save artifacts

Per cut:

- `prompt-compact.md` in matching `generations/video-prompts/draft-v1/NNN_*/` folder
- optional `source_paths.txt` when moderation or image variants exist

Batch bundle:

- `COPY-PASTE-NNN-NNN.txt` with headers:

```text
========== #053 | M04 Lua | ring breath | 2:15-2:18 ==========
```

### 6. Deliver to founder

- Reply in **Korean** for headers and instructions.
- Prompt body in **plain English** (generator-facing).
- Prefer plain copy-friendly text; `COPY-PASTE-*.txt` for drag-copy from Finder.

## Image Refresh Pattern

When founder replaces convergence / review images:

1. New files land in `generated-clips/.../NNN_*/image1.png` (and sometimes `candidate-IV*.png`).
2. Re-read all images in the affected range.
3. Rewrite every prompt in that range from scratch — do not patch old prose.
4. Regenerate the matching `COPY-PASTE-*.txt` bundle.

Skipped slots (e.g. #044 omitted) stay omitted; do not renumber assembly_seq.

## Moderation Escape Hatch (#061 pattern)

When Grok Imagine repeatedly moderates a clip:

**Common triggers**

- palm/hand reaching toward camera (beckoning/selfie read)
- crop top + mini skirt + chains in full-body frame
- `punches in` / `toward viewer` camera language

**Fix (use together)**

1. Create waist-up crop (~top 58% of frame):

   `active-image-moderation-safe-crop.png` in the clip folder.

2. Write `prompt-compact-moderation-safe.md`:

   - waist-up framing stated explicitly
   - hand → side cheer wave at shoulder height, not toward lens
   - locked chest-height camera, no punch-in
   - drop chain/skirt/low-body wording

3. Note in `source_paths.txt` which image + prompt pair to use.

Text-only prompt edits alone often fail if the source image still shows the triggering pose.

## What We Deliberately Did Not Sync Live

- `generations/video-prompts/draft-v1/NNN_*/prompt.md` (canonical)
- `03V-video-prompt-manifest-v1.yaml`
- drive-sync `bridge-two-image` packs (this loop used local clip `image1.png` directly)

Promote to harness only on founder signals: `이 버전으로 가자`, `sync 해`, section complete.

## Founder Kickoff Phrases (next session)

```text
#053부터 image1.png 바뀌었어. 다시 compact prompt 줘.
#061 moderate 또 당함 — safe 버전 줘.
#063–#071 outro도 같은 방식으로.
```

Grok should: read manifest range → read audio-motion lyric → re-read all `image1.png` → write compact prompts → update COPY-PASTE bundle → paste in chat.

## Quality Checks Before Sending

- [ ] Assembly numbers match manifest (not folder sort order mistakes)
- [ ] Each prompt describes the **current** `image1.png`, not an older pass
- [ ] NOIDOL shots do not invent an idol
- [ ] Lyric cue matches audio-motion map for that slot
- [ ] No glow/beams on GLOW slots unless founder explicitly asked
- [ ] COPY-PASTE file updated for the same range
- [ ] Moderation-flagged cuts have crop + safe prompt noted