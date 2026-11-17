# Performance Memory

Record IDOL-specific performance discoveries here after review or repeated use.
This is not a general external dance knowledge bank.

Use this shape:

```yaml
- date:
  source_run:
  member_or_group:
  performance_pattern:
  worked_because:
  prompt_or_direction_pattern:
  reuse_when:
```

Possible entries include member signatures, successful point choreography
phrases, performance camera behaviors, video-generation choreography prompt
patterns, and movement-to-edit patterns that held up in review.

```yaml
- date: "2026-05-27"
  source_run: runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL
  member_or_group: "FULL_CODE / music-video edit automation"
  performance_pattern: "Use cue function plus audio onset plus visible body landing as the cut decision, not raw clip length alone; treat founder-made r*-* variants as combinable materials inside a slot."
  worked_because: "The final master reached full selected-audio duration while preserving opener hold, rap intensity, chorus wide-body read, and final hold; QC caught and fixed R08 UI frames, then founder combo pass improved R01/R03/R06/R07 by using more candidate material with speed control."
  prompt_or_direction_pattern:
    - "Generate candidate/source contact sheets before selecting variants."
    - "Render from recipe YAML, then verify with 1-second full contact sheet and cut-change pre/post sheet."
    - "Use 92.29 BPM as main grid and 184.57 BPM only for accent detail."
    - "For r*-* variants, test composition inside the same R slot before picking only one."
    - "Treat missing dedicated tail sources as source-limited, not creatively complete."
  reuse_when: "Any IDOL MV edit needs automatic R-slot assembly, beat/onset alignment, or source-limited full-song preview."
- date: "2026-05-27"
  source_run: runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL
  member_or_group: "FULL_CODE / section-preview edit QC"
  performance_pattern: "Before committing a full render, test the exact disputed time window as a preview; judge speed changes against visible body mechanics, not just whether the target source duration fits the slot."
  worked_because: "R6/R7/R8 iterations showed that the same source can become either musical or awkward depending on the seam, speed factor, and whether the visible landing reaches the lyric or onset point."
  prompt_or_direction_pattern:
    - "Use short preview renders for correction windows such as 40-58s or 1:21-1:32 before full-master render."
    - "For lyric-triggered moments such as call-me hits, shh cuts, or repeated phrase endings, align the cut/effect to the word or ending if the founder names it."
    - "Treat speed above roughly 1.6x as a QC risk unless the visual is a deliberate hit insert, camera whip, or tiny body accent."
    - "Use additional/remake clips as source windows for replacement, hit inserts, or phrase endings, not only as whole-slot replacements."
  reuse_when: "Any IDOL MV edit has founder notes about a specific timestamp feeling late, awkward, too slow, or needing a lyric-synced punch."
- date: "2026-05-29"
  source_run: runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL
  member_or_group: "FULL_CODE / final-master source-clean QC"
  performance_pattern: "After founder approves cut timing, lock quality from the original source lineage instead of preserving sections from an older rendered master; keep the founder-intended source aspect ratio as the master ratio."
  worked_because: "The v11 closeout kept the founder-approved v10 cut choices while expanding preserved v6-master ranges back into original raw source segments, then rendered a 1620x1080 3:2 master. This reduced visible cut-to-cut texture and framing mismatch caused by mixing 3:2 raw sources with recompressed 16:9 master sections."
  prompt_or_direction_pattern:
    - "Before final QC, compare source aspect ratios against the final render profile."
    - "Treat rendered masters as review outputs, not source material, unless the founder intentionally accepts that layer."
    - "For social clips, cut from the current source-clean master or source-clean recipe, not from raw generation candidates that bypass final color, timing, and audio context."
    - "If a platform needs 16:9 or 9:16, derive it intentionally from the source-clean final with crop, pad, or background extension noted in the package."
  reuse_when: "Any IDOL MV final has mixed raw/generated sources, previous-master preserved ranges, or founder concern about inconsistent image quality across cuts."
- date: "2026-05-30"
  source_run: runs/2026-05-26/0526_SONG_SELECTION
  member_or_group: "LOW / 02B generated Branch-Cut identity"
  performance_pattern: "Use face-only references as strong member identity anchors, then let expression and gaze come from the current lyric, rhythm, action, and camera beat."
  worked_because: "The LOW airport v2 wardrobe-lane sample kept member recognition stronger while still allowing the generated face to fit the airport lighting, body action, and beat-specific attitude instead of copying the reference photo expression."
  prompt_or_direction_pattern:
    - "Attach the current member face-only reference whenever member identity is present."
    - "Write identity as face shape, facial proportions, recognizable features, and body-scale continuity."
    - "Write expression and gaze from the beat prompt, not from the reference photo."
    - "Reject outputs where the face looks pasted on, ignores scene lighting, or copies a neutral reference expression that conflicts with the scene."
  reuse_when: "Any IDOL Branch-Cut image, poster, storyboard preview, or video prompt needs strong member recognition without freezing every member into the same expression."
- date: "2026-06-11"
  source_run: runs/2026-05-26/0526_SONG_SELECTION
  member_or_group: "LOW / v20 edit closeout"
  performance_pattern: "For song-led edits, treat beat split seconds as references only; make cuts from lyric/rhythm accents, visible body landings, camera carry, and section-to-section motion continuity."
  worked_because: "The founder rejected mechanical beat-timed versions, then accepted the v7-from-51 highlight structure after the edit favored stronger source moments, smoother late-section drive, and a longer 82.8-90s audio fade with 84.8-90s video fade."
  prompt_or_direction_pattern:
    - "Do not follow a mechanical beat grid when the source motion, vocal cue, and camera carry say the cut should breathe longer or hit earlier."
    - "For repeated hook material, vary source windows, speed, and cut-in/cut-out points; do not stack the same static action with only effects as variation."
    - "When a founder passes a postprocessed ending, record any cloned or held-frame tail as a watchlist so future public-release review can decide whether a source-level ending is needed."
    - "For final social derivatives, cut from the accepted final master and re-encode cleanly; do not register probe files that show SAR or bitstream warnings."
  reuse_when: "Any IDOL MV edit has founder notes that the video feels separate from the song, too mechanical, too repetitive, or needs a longer final fade without rebuilding the full source recipe."
```
