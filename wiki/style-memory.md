# Style Memory

Record concrete founder style decisions here only after real review, selection,
rejection, or repeated run validation.

Use this shape:

```yaml
- date:
  source_run:
  decision:
  keep_using:
  avoid_or_reduce:
  note:
```

Do not store generic branding adjectives without a concrete decision behind
them.

Song generation rule: style memory is not a default Suno/manual prompt input.
Use it for hard bans, concrete production constraints, and completed-review
decisions only. Song prompts may use only references explicitly named in the
current run or selected PRE-00 artifact.

```yaml
- date: "2026-05-22"
  source_run: global
  decision: "Ancient and medieval costume directions are banned until the founder explicitly unlocks them for a specific run."
  keep_using:
    - "contemporary idol/MV styling"
    - "performance-ready or editorial song-specific wardrobe"
  avoid_or_reduce:
    - "ancient costume cues"
    - "medieval costume cues"
    - "historical court dress, armor, fantasy-medieval robes, dynasty styling, or period gowns"
  note: "This is a hard founder constraint, not a generic style note."
```

```yaml
- date: "2026-05-24"
  source_run: global
  decision: "Expand M03 Yeul from pure stability lead into a cool rhythm rap-vocal anchor while preserving her clean balance identity."
  keep_using:
    - "Yeul as cool spoken-groove line"
    - "Yeul as UK-garage / house rhythm binder"
    - "Yeul as transition anchor between vocal and rap energy"
  avoid_or_reduce:
    - "turning Yeul into a hard main rapper"
    - "using Yeul only as soft clean balance when a unit needs rhythmic weight"
  note: "Applied to assets/member-registry.yaml and assets/voice-style-index.md."
```

```yaml
- date: "2026-05-24"
  source_run: global
  decision: "Lock the unit registry to code-name units derived from active member roles and creative popular girl-group coordinates."
  keep_using:
    - "internal code-name unit labels (see active assets/unit-registry.yaml)"
    - "member lists sorted by member code for founder readability"
    - "external group examples when useful"
  avoid_or_reduce:
    - "using external idol group names as unit names"
    - "labeling one unit as the default main-title unit"
    - "forcing Rena as the default center across all units"
  note: "Applied to assets/unit-registry.yaml, assets/member-registry.yaml first_unit_fit, and unit-code schema enums."
```

```yaml
- date: "2026-05-24"
  source_run: global
  decision: "Reflect member public-height lines as 170-plus, 165-line, and 160-line asset groups, while keeping AURORA-M voice examples separate from named-idol reference notes."
  keep_using:
    - "public_height_cm as the basis for profile and formation height lines"
    - "170 이상: M05, M07, M10"
    - "165 라인: M01, M02, M04, M08, M09, M11, M13"
    - "160 라인: M03, M12"
    - "M12 character-board fixed body identity: 164cm / 52kg"
    - "AURORA-M representative voice coordinates plus separate named-reference notes when useful"
  avoid_or_reduce:
    - "using runtime_height_cm as public profile height grouping"
    - "using legacy M12 runtime 169cm / 56kg over the character board"
    - "treating named idol references as forbidden reference anchors in member voice notes, Suno prompts, generation prompts, or public-facing text"
  note: "Applied to assets/member-registry.yaml, assets/member-profile-summary.md, and assets/voice-style-index.md."
```

```yaml
- date: "2026-05-25"
  source_run: runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL
  decision: "For future song starts, use founder-provided reference songs first, then let Codex assign the sound direction to the best-fit unit; do not start from abstract Suno style prompting alone."
  keep_using:
    - "founder brings concrete songs or sections as the sound anchor"
    - "Codex maps each reference function to unit fit, section use, and prompt constraints"
    - "separate wanted functions from unwanted traits before writing Suno prompts"
  avoid_or_reduce:
    - "abstract style-only Suno prompts as the first creative move"
    - "trying to fix a bad generated direction through repeated prompt adjectives"
    - "forcing a full-roster unit before the reference songs prove fit"
  note: "Founder review from the FULL_CODE / ROOT_SIGNAL Suno style probe attempt: results felt off, too hard to diagnose, and less useful than reference-first unit assignment."
```

```yaml
- date: "2026-07-12"
  source_run: global
  decision: "Remove Hearts2Hearts and ILLIT from active Loom unit/group color. Primary idol coordinates are BLACKPINK, MEOVV, KISS OF LIFE, (G)I-DLE, LE SSERAFIM, and aespa. Soft-teen / pristine Hearts2Hearts-ILLIT purpose language is not Loom unit language."
  keep_using:
    - "BLACKPINK, MEOVV, KISS OF LIFE, (G)I-DLE, LE SSERAFIM, aespa as primary unit reference_coordinates"
    - "unit purpose language that keeps tension, groove character, performance proof, and mature vocal-rap contrast"
  avoid_or_reduce:
    - "Hearts2Hearts in assets/unit-registry or Loom brand unit color"
    - "ILLIT in assets/unit-registry or Loom brand unit color"
    - "easy-listening / soft short-form / low-pressure / too-pristine unit purpose language derived from those groups"
  note: "Applied to assets/unit-registry.yaml and business-marketing reference palette docs."
```

```yaml
- date: "2026-07-12"
  source_run: global
  decision: "Lock named voice reference coordinates in assets/voice-style-index.md from the founder 2026-05-17 voice preference map and R-VOICE vault clusters. Named artists are reference mechanics only, not member identity."
  keep_using:
    - "founder preference map as source of which voices matter"
    - "M08 primary anchor Minnie; M01 air/EDM feature; M05 clear lift; M09/M12 bright articulate hook"
    - "functional member vocal rails plus named anchors max two primary per member"
  avoid_or_reduce:
    - "imitating exact celebrity voice or hit melodies"
    - "forcing R-VOICE-04 male tenors onto the default 13-member female rail"
    - "public Loom/Harne copy that names real artists as member identity"
  note: "Applied to assets/voice-style-index.md. Detailed analysis notes remain in business-marketing/research for human review."
```

```yaml
- date: "2026-07-12"
  source_run: global
  decision: "Lock active Loom unit codes to short terminal/AI words: exec, tui, cache, sync, echo, curl, cli, repo."
  keep_using:
    - "EXEC_06, TUI_06, CACHE_05, SYNC_05, ECHO_05, CURL_06, CLI_05, REPO"
    - "easy pretty pronunciation for internal unit labels"
  avoid_or_reduce:
    - "CROWN / NOIR / BAND fashion unit labels"
    - "KERNEL_06, SIGNAL_API_06, CACHE_LOOP_05, MIRROR_SYS_05, SHADE_STACK_05, MOTION_GPU_06, MELO_PORT_05, FULL_CODE as active unit codes"
  note: "Applied to assets/unit-registry.yaml v5, member first_unit_fit, and unit enums in schemas. Historical runs may still show legacy codes."
```

```yaml
- date: "2026-05-26"
  source_run: global
  decision: "Do not paste numeric BPM into copy-ready Suno Style boxes by default; use exact BPM only when the founder locks it, reference-song fit intentionally requires it, or selected-audio analysis confirms it."
  keep_using:
    - "energy feel and body-function language in Suno Style boxes"
    - "internal BPM analysis for trend, choreography, song-lock, and edit timing when useful"
    - "exact BPM in 00A/song-lock or edit records after an audio source exists"
  avoid_or_reduce:
    - "default numeric BPM in Suno copy boxes"
    - "guessing kick, drum, bass, or lead-instrument detail to force rhythm"
    - "using internal monthly BPM hypotheses as pasted Suno instructions"
  note: "Founder correction during new song prep: BPM hypotheses are useful for analysis, but Suno should be guided by pocket, energy, release behavior, and vocal/body function unless exact tempo is intentionally locked."
```

```yaml
- date: "2026-07-13"
  source_run: runs/2026-07-05/0705_GIRL_BADUK_WORLD_SIGNAL
  decision: "For Founder-facing visual storyboard and reference review, default to a local HTML review wall when its production cost is modest; every source image must be shown uncropped."
  keep_using:
    - "local HTML review walls with section navigation and cut-level reference/action/camera evidence"
    - "object-fit contain or equivalent full-image presentation with letterboxing when aspect ratios differ"
    - "clickable canonical artifact paths alongside the review wall"
    - "the cited source run only as provenance for review-wall layout geometry and evidence order"
  avoid_or_reduce:
    - "object-fit cover or fixed crops that hide any part of a review reference"
    - "text-only visual review when a compact local HTML wall can present the evidence more clearly"
    - "building elaborate review UI when a static local HTML file is sufficient"
    - "reusing any source-run scene, action, object, member pose, camera route, composition, or prompt wording through this layout decision"
  note: "Founder approved the cited prior-run 46-parent HTML layout as default review material when its cost stays modest. This stores layout provenance only and is not a creative-content source."
```
