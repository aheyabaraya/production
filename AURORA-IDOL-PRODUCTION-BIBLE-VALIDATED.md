# AURORA Idol Production Bible — Archived Research Synthesis 2026

**Status**: Archived research synthesis. Useful for background reading only; it
does not override `AGENTS.md`, schemas, active `skills/**`, or current run
records.  
**Sources**: Primary director interviews (Han Sa-min 2025, ZANYBROS 2020, GDW/Kim Sung-wook via Koreaboo/YouTube Originals), 2026-05 current K-pop trend research (Korea JoongAng Daily, Billboard Korea, Korea Times, Universal Music Canada/KATSEYE, TikTok x Luminate), official Suno v5.5 product notes, community Suno meta-tag/prompting consensus, director-harness research imports, and cross-referenced production literature.
**Purpose**: Preserve research about real top-tier K-pop idol MV and content production, then translate only selected, still-useful parts into the active IDOL-native harness after founder review.

**Read order for different tasks**:
- Quick overview → Executive Summary
- Planning a new song/MV unit → Sections 1 + 4
- Writing Suno prompts from A/B output → Section 2 + 4.5
- Building E-code MV package or reviewing clips → Sections 1.3 + 3 + 4.4
- Updating harnesses or skills → All of Section 4 + 5

---

## Executive Summary (한글 + English)

**한글 요약**  
K-pop 아이돌 MV 제작은 **노래(감정/메시지) → 컨셉/트리트먼트 → 스토리보드(곡 바/안무 변화 동기화) → 치밀한 사전제작(안무 3~4주 집중 리허설, 스타일링·조명·VFX 설계) → 촬영(3~5일 올나이트, DP가 안무 50회 연구, 퍼포먼스 디렉터 현장 보정) → 포스트(비트+포즈+시선+가사 턴+에너지 전환 다중 트리거 편집, 모티베이티드 VFX/컬러, 아이돌 얼굴 글로우)** 의 흐름으로 진행된다. 디렉터는 컨셉부터 포스트까지 전 과정 소유권을 가지며, **안무가/퍼포먼스 디렉터**는 카메라-리더블 실루엣·카운트·포메이션·멤버 간격을 최우선으로 한다. 에디터는 단순 비트 컷을 넘어 감정/움직임/가사 포인트에서 컷팅한다.

IDOL의 노래-컨셉-안무-스토리보드-생성-편집 하네스는 **실제 산업 파이프라인과 강하게 일치**한다. 특히 Han Sa-min, ZANYBROS, GDW 인터뷰에서 확인된 “노래 느낌 우선, 아티스트 비전 반영, 트리트먼트=계약서, 스토리보드=곡 동기화, 안무 연구, 작은 차이 집중” 원칙은 active IDOL 하네스의 품질 기준으로만 재해석한다.

**강화/추가 제안**:
- Suno 프롬프트: 2010s식 `bright anthem idol title` 템플릿을 폐기하고, 2026-05 기준 `opening-to-recurrence hook`, `hard techno/DnB/hyperpop pressure`, `house/mid-groove emotional pocket`, `pre-hook addiction`, `body-readable micro-hook` 레일로 교체.
- E코드: 다중 편집 트리거(beat + pose land + gaze + lyric turn), VFX 모티베이션, C→E 번역 로직, 포스터 프레임 경제 명시화.
- 하네스: 실제 에디터/DP 피드백 반영하여 review rubric에 “section arc intact”, “choreo readability under crop” 항목 강화.

**English Summary**  
Real K-pop idol MV production follows a music-first, highly collaborative pipeline: **song emotion/message → treatment (director’s visual contract) → music-synced storyboard → 3–4 week choreo rehearsal (performance director on-site) + pre-prod design → 3–5 day shoot (DP studies choreo 50×, dynamic cameras, positive set energy) → post (multi-trigger rhythmic editing on beat/pose/gaze/lyric/energy, motivated VFX/color, idol-face glow)**. The director typically owns the full chain; the choreographer/performance director owns performability, camera-readable body lines, and formation logic.

IDOL's active music, choreography, MV direction, generation, and edit-planning
contracts are **strongly validated** by 2020-2025 director interviews (Han
Sa-min, ZANYBROS, GDW). Retired lane names in this archive are not active skill
routes.

**Recommended refinements** (detailed in §4):
- Suno prompting in B-code: replace the older bright-anthem K-pop template with current 2026 rails: opening-to-recurrence hook, hard techno/DnB/hyperpop pressure, house/mid-groove pocket, pre-hook addiction, and body-readable micro-hooks.
- E-code & harness: add explicit multi-trigger edit grammar, C-to-E translation rules, and tighter section-arc preservation checks.
- Daily harness clip economy and posterable frame logic remain realistic.

This document is the single source of truth for grounding future Aurora automation in craft reality while preserving founder creative control.

---

## 1. Real-World K-Pop Idol MV Production Pipeline (Deep)

### 1.1 Overall Sequence & Realistic Timeline

Typical high-profile production (GDW, ZANYBROS, Han Sa-min level):

1. **Song lock + high-level concept** (label + songwriters)
2. **Director attachment + Treatment** (1–3 days intensive listening + writing)
3. **Storyboard** (director-led, shot-by-shot, synced to specific bars, choreo changes, mood shifts)
4. **Pre-production** (3–4 weeks)
   - Choreography creation & idol rehearsal (12+ hr days, often 1 month)
   - Styling, hair, makeup, set/prop design, lighting plan, VFX pre-vis, casting
5. **Principal photography** (3–5 very long days, frequent all-nighters; 2–15 day extremes reported)
6. **Post-production** (1+ week)
   - Offline edit → VFX/compositing → color grade → sound design/finishing → approvals
7. **Delivery + optional performance version** (mostly dance cut)

Total calendar: 2–4 weeks typical; longer when international fan feedback loops or music changes occur (ZANYBROS).

**Key cultural note**: K-pop MVs are differentiated by **flawless, camera-optimized group choreography** as a core promotional asset, not just background. This makes the choreographer/performance director role non-negotiable from early pre-prod through set and sometimes post QC.

### 1.2 Role-by-Role Deep Dive (What Each Focuses On for “Excellent” Results)

**MV Director (e.g. Han Sa-min, Hong Won-ki/ZANYBROS, Kim Sung-wook/GDW)**  
- **Entry**: Usually after song is locked; sometimes parallel to final arrangement.
- **Primary ownership**: The *one-sentence thesis* that turns song emotion/message into visual conflict/world/action so the audience remembers the brand/message. Full story organization (even without strict 3-act beginning/middle/end), key scenes list, then treatment as the binding contract between all departments.
- **Quality focus**: Song feeling first (listen sparingly at the beginning to stay fresh), artist/group identity as hard constraint (not decoration), small authentic differences over forced novelty, total immersion (“if I can’t fully immerse, I can’t make a good video” — Han Sa-min).
- **Handoff artifacts**: Treatment, detailed music-synced storyboard, on-set direction, edit notes, final approval.
- **Quotes/evidence**:
  - Han Sa-min (2025): “concretizing the feelings I get from the song and lyrics… write out the full story… list specific scenes… gather elements for costumes, hair, movements, emotions… communicate directly with the singer.”
  - ZANYBROS: “listen to the music to understand the overall flow… come up with the concept… make a storyboard… 15-second rule for strong opening impact… wide use of color and emphasis on active choreography.”
  - GDW/Kim: Storyboard is “as important as the final outcome”; imagines camera angles, shot rhythm, artist movement, mood, song bars, formation changes.

**Choreographer / Performance Director (often credited separately; works with “performance director” on set)**  
- **Entry**: Very early — parallel to or immediately after treatment; heavy rehearsal before principal shoot.
- **Primary focus for excellence**: Choreography must be (a) concept-fitting and emotionally readable, (b) camera-friendly (silhouette, body lines, formations that read on screen, member spacing that survives wide-to-close), (c) count-precise and weight-shift natural for idols to hit 100+ takes without injury or fatigue, (d) signature “point choreo” moments that become the hook for fans and TikTok.
- **On-set role**: Present every day to correct formations, timing, expressions under camera; often the person who “makes the dance work for the lens” when director or DP asks for adjustments.
- **Evidence**: Koreaboo GDW coverage — idols practice ~1 month 12hr/day; DP studies the choreography “dozens of times (one account: 50×)” to plan moves that enhance rather than fight the dance. Choreographer/performance director is credited and physically on set for refinement.

**Director of Photography / Cinematographer (DP) + Gaffer/Lighting**  
- Studies choreo intensively so camera moves (Jimmy Jib for wide group, Mōvi for fluid, handheld for energy, cranes for dramatic) feel motivated by the dance and song energy.
- Lighting tailored to Asian facial features (bright, flattering key + fill) while still serving dramatic mood; often per-member customization so each idol’s unique traits read.
- Works closely with director on “what I want” meetings, then adapts on set to artist + atmosphere.

**Editor (often in-house at production company or long-term collaborator)**  
- **Not just “cut on the beat”**. Real editors cut on multiple simultaneous triggers: beat, pose landing, gaze change, lyric/emotion turn, formation snap, energy rupture, object reveal, member highlight, camera energy shift.
- Starts with best dance takes, builds rough cut around performance, then weaves in narrative/VFX plates with seamless transitions.
- Works iteratively with director; responsible for section arc preservation and final “visual addictiveness.”
- Post tools: Premiere + After Effects for proxy org, beat-matching, rotoscoping, glows, final export.

**VFX Supervisor / Post Team**  
- On-set green-screen/compositing prep; post keying, CG world extension, particle sync to beat, morph/glitch on transformation moments, matte paintings.
- Must preserve identity and body readability — effects fail when they hide feet/hands/face or break choreo meaning.

**Stylist / Hair & Makeup / Production Designer**  
- Wardrobe, hair, makeup, props, sets that carry narrative meaning and amplify member personality while surviving camera + movement.
- D-code in Aurora (styling/visual rail after C) maps directly here.

**Music / Vocal Side (often upstream of visual director)**  
- Composer, lyricist, arranger, vocal producer, mixing engineer — song is the immovable root. Director listens to capture fresh feeling before over-familiarity sets in.

**Live Stage Director / Concert Lighting & Video Team (separate but related)**  
- Often the same choreographer or a dedicated performance director adapts the MV choreo for arena cameras, lighting cues, LED screens, and sustained 2–3 hour shows. MV version is frequently more cinematic; stage version prioritizes sustained readability and stamina.

### 1.3 Song → Treatment → Storyboard → Shoot → Post (Detailed Sub-Steps)

(See the director interviews for primary source language; Aurora E-code research imports already captured the correct bones.)

**Treatment (Director’s Contract)**: Image-driven, concise, artist-brand aware, budget-aware. Contains concept overview, key scenes, camera style, lighting tone, editing/post direction, wardrobe/choreo references, visual samples. Han Sa-min: “the overall direction of the big concept is most important.”

**Storyboard**: Director (or close team) draws shot-by-shot with explicit timing to song bars, choreo formation changes, mood shifts, camera speed/angle. GDW: “I draw storyboards imagining all of this.”

**Pre-prod & Rehearsal**: Choreo locked enough for camera planning; DP memorizes it; lighting/scrims tested for idol faces; VFX plates planned.

**Shoot**: Multiple cameras, performance + narrative plates, green screen for VFX. Director keeps “vibes” positive despite 12–18hr days — performance quality depends on it.

**Post**: Editor’s multi-trigger rhythm assembly + VFX integration + color (glowy, face-forward, brand-consistent) + director notes rounds + final QC by artist/label/director.

---

## 2. Suno Prompt Engineering — Current 2026 Idol / Global-Pop Standard

Status: refreshed 2026-05-25 after current K-pop trend review. The older
`fourth-generation bright anthem idol title` template is retired. It over-pulled
Suno toward 2010s/early-2020s K-pop title songs, band-pop correction loops, and
EDM avoidance language.

### 2.1 Current Trend Read

Use the current market as multiple rails, not one default genre:

- **Techno 2.0 / hard electronic pressure**: current girl-group releases are
  leaning harder, faster, and louder, with hard techno, drum-and-bass,
  hyperpop, fast repetitive kicks, distorted electronic impact, chant hooks, and
  anti-drop structures. This works for short-form because the physical hit is
  immediate.
- **House / mid-groove emotional pocket**: house is also reasserting itself as
  an identity sound when used as emotional rhythm, minimal bassline, nonchalance,
  and continuity rather than festival EDM.
- **Opening-to-recurrence song economy**: the actual intro arc, ordinarily
  around 8-12 seconds when the song structure supports it, establishes a
  specific sonic identity, completes the setup, and seeds or deliberately
  withholds the memory carrier. The first full hook and its middle return
  preserve that carrier while changing density, ownership, scale, or
  consequence. The pre-hook can be the addiction engine; the chorus can share
  memory work with the post-hook and later return.
- **Global-pop girl-group edge**: current global idol-pop can be brash,
  playful, hyperpop-adjacent, low-end-aware, and gesture-driven rather than only
  polished, bright, or anthemic.
- **Suno v5.5 personalization**: v5.5 adds Voices, Custom Models, and My Taste.
  Prompting should therefore define a compact AURORA-M production identity and
  avoid generic genre piles.

### 2.2 Style Box Standard

Custom Mode remains mandatory. The first 20-30 words still carry the most
weight, but the first words must now identify the **active rhythm or section
function**, not a generic K-pop generation label.

Front-load in this order:

```text
rhythm or energy pocket -> hook behavior -> vocal pocket -> production texture -> section economy -> light guardrails
```

Use exact BPM, kick, drum, bass, or lead-instrument language only when it is an
intentional input from the founder, a reference-function decision, or a selected
audio result. BPM can remain in internal trend, choreography, or edit analysis,
but copy-ready Suno boxes should not paste a numeric BPM by default. If those
details are guesses, they tend to over-steer Suno into dated dance-pop, cheap
EDM, or band-correction loops. When uncertain, describe body function instead:
clean pocket, restrained impact, dry snap, negative space, short repeatable body
phrase, or vocal-led tension.

Preferred copy-ready current anchors:

- `asymmetrical mid-groove`
- `body-led pocket pop`
- `fast hard-techno idol pressure`
- `drum-and-bass pulse with pop-vocal space`
- `hyperpop-edged synthetic-bite global girl-group pop`
- `minimal house groove as emotional rhythm`
- `close rap-vocal pocket`
- `pre-hook color shift as the addiction point`
- `anti-drop physical release`
- `short-form-ready body phrase`

Avoid as default first words:

- `catchy fourth-generation K-pop idol`
- `girl group debut title track`
- `explosive anthemic chorus`
- `bright powerful group chorus`
- `supersaw synth hook`
- `sidechained bass`
- `massive synth drop`
- `radio-ready high-energy dance track`
- `live-drum momentum` unless the founder specifically wants a band/OP route

Use light negative prompting. Do not fill the Style box with every avoided
genre; too much `no EDM / no rock / no club` keeps Suno orbiting those spaces.
Name the replacement behavior instead: `clear pocket, restrained release, dry
snap, spacious low end, no festival drop`.

### 2.3 Current Style Pack Templates

Use these as starting rails. Replace wording per run, keep the first clause
logic, and omit numeric BPM unless it has been intentionally locked.

**A. Tension Pocket / Modern Groove**

```text
asymmetrical idol mid-groove, body-led rhythmic pocket in the first two seconds, close cool rap-vocal, atmospheric dark texture, spacious low end, dry body-readable percussion, pre-hook vocal color shift as the addiction point, restrained hook release, short repeatable body phrase, polished but spacious mix, no festival drop
```

**B. Techno 2.0 / Short-Form Pressure**

```text
fast hard-techno idol pressure, immediate distorted impact pattern, short chant hook in first two seconds, sharp synthetic stabs, close female rap-vocal attitude, anti-drop body hit, fast pre-hook lift, compact chorus release, high-impact short-form energy, sleek dark mix, no retro Eurodance
```

**C. DnB / Hyperpop Edge**

```text
drum-and-bass pulse with hyperpop-edged synthetic bite, clipped vocal hook in first two seconds, bright synthetic shards, tight vocal articulation, cool rap-vocal pocket, pre-hook lift then anti-drop snap, playful but dangerous global girl-group energy, crisp short-form mix, no big-room EDM
```

**D. House / Emotional Rhythm**

```text
minimal house groove as emotional rhythm, soft low-motion pulse, close airy vocal, understated rim-and-snap pocket, nonchalant verse, addictive pre-hook color shift, smooth restrained release, intimate body-readable hook, polished everyday mood, no maximalist drop
```

**E. Performance Bite / Full-Code Identity**

```text
performance-pop pocket with a clipped opening identity signal that develops through an 8-12 second intro arc, dry low body impact, clipped rap-vocal answer, dark synthetic pressure, pre-hook lift as identity reveal, anti-drop point phrase, compact group response, recognizable middle return, final low tag, modern AURORA-M system energy, no bright anthem chorus
```

### 2.4 Lyrics Box Standard

Lyrics remain hook probes, not final locks. Keep every section meta-tagged:

```text
[Section | core | vocal direction | performance | production | effects]
```

Current section tags should describe **behavior**, not only genre polish:

- Intro: `identity signal`, `breath cut`, `setup promise`, `hook seed or hold`
- Verse: `close rap-vocal pocket`, `low attitude`, `clear empty space`
- Pre-hook: `vocal color shift`, `tension hold`, `addiction point`
- Release: `anti-drop snap`, `body-readable phrase`, `group response`
- Post-hook: `7-12s repeatable phrase`, `micro-choreo`, `lip-shape hook`
- Reset: `texture drop`, `low-tone rap`, `gaze hold`
- Final: `callback`, `bigger pocket`, `memory tag`

Keep lyrics concise. For Suno coherence, 100-140 sung words is usually safer
than long complete poetry. Hook language should favor mouth-feel, rhythm, and
gesture over concept explanation.

### 2.5 Mapping to Aurora B-Code / A-Code

Existing B-code still correctly focuses on message claim, energy curve,
arrangement function, hook function, and stage/choreo function. The refinement
is that B-code must now select a **style rail** before writing copy boxes:

- `tension_pocket`
- `techno_2_0`
- `dnb_hyperpop`
- `house_emotional_groove`
- `performance_bite`
- `custom_founder_reference_fit`

The Suno prompt packet must contain:

- selected style rail and why it fits the unit/message
- Style box with current first-clause rhythm engine
- meta-tagged lyrics skeleton
- focused Negative box with no more than 6-10 avoid items
- one-variable variant plan
- founder manual run gate + listening QC

### 2.6 Iteration & QC Loop

1. During live Suno exploration, keep drafts in chat or candidate research
   packets. Do not update `00`, `00A`, active handoff fields, or memory from
   prompt wording alone.
2. Generate 4-8 variations from one style rail.
3. Change only one variable per variant: rhythm engine, energy pocket, vocal pocket,
   hook density, pre-hook lift, or release behavior. Use a numeric BPM variant
   only after the founder, reference fit, or selected audio makes it intentional.
4. Judge the candidate as one chain: the completed 8-12 second opening arc,
   pre-hook replay value, first full hook, and recognizable middle return before
   the final whole-song polish decision.
5. If the result feels dated, cheap-EDM, or wrongly bass/kick-led, do not add
   more negative terms or hard-code more rhythm-section detail. Re-check the
   reference-song function, re-select the style rail, and rewrite the first
   20-30 words around body function and vocal behavior.
6. Lock only after founder approval. The selected take may rewrite the hook;
   update 00A from the actual audio, not the seed lyric.

---

## 3. Video Directing & Editing Mastery for Idol MVs

(Expanded from user’s existing E-code research + new director evidence.)

### 3.1 Camera Language & Motivation (Examples)
- Push-in / dolly-in: on emotional turn or member highlight (identity/emotion).
- Tracking / trucking + orbit: following formations or point-choreo travel (performance power).
- Crane / jib / 4-point wire (Han Sa-min BIGBANG Love Song): dramatic elevation on drop or transformation.
- Handheld + controlled shake: energy, urgency, or raw performance feel (use sparingly, motivated).
- Static or slow composed: posterable frames, emotional close-ups, “memory” shots.

DP studies choreo 50× so moves enhance silhouette, weight shift, and body line rather than fight them.

### 3.2 Rhythm Editing Triggers (Beyond “On the Beat”)
Real editors (and therefore E-code edit_stitch_map logic) cut on:
- Beat / downbeat / kick-snare
- Pose land / formation snap / weight change
- Gaze change / eye contact with camera
- Lyric keyword or emotional turn in vocal
- Energy rupture / section shift
- Object reveal or world pressure change
- Camera energy match (when source camera is already moving)

This is why C-code “visible_action (body path/weight/center/spacing/silhouette)” + “count feel” is so important for downstream E-code to have real edit points.

### 3.3 EDL / Stitch Map / Clip Economy
- Gen clips 6–10 s → safe edited use 2.5–5 s (Aurora daily-harness assumption validated).
- Posterable frames marked at section turns + ending (F-code later owns final still selection).
- Section arc must survive the stitch; no random spectacle.

### 3.4 VFX, Color, Polish (Motivated Only)
Effects succeed when they serve rupture, transformation, power shift, or world pressure. They fail when they hide identity, feet/hands, or choreo meaning. Color grade emphasizes glowing idol faces/eyes while maintaining brand palette.

### 3.5 C-Code (Stage/Practice Boards) → E-Code (Cinematic MV) Translation
- C-code prioritizes **readable performance** (longer phrases, body-line first, practice vs stage contrast).
- E-code can be more aggressive with camera moves, effects, and editorial rhythm **provided** the approved choreo action meaning and member readability survive.
- Director harness already separates the two playbooks correctly; the MD simply adds explicit “C-to-E translation rules” checklist.

---

## 4. Aurora System Validation & Refinement Recommendations

(Full matrix would be 3–4 pages; here are the highest-impact items with citations.)

**4.1 0-G Lane Mapping — Strong Validation**  
0 (architecture) → A (concept/message/identity = director’s thesis/treatment) → B (song + manual Suno) → C (choreographer/stage-director mode) → D (styling/visual rail) → E (MV directing + EDL) → F/G (stills + final package) matches the real sequence director → choreographer/performance director → DP/lighting → editor/post. The “song-feel first, artist identity as constraint, treatment as contract, storyboard music-synced, DP studies choreo” principles in Han Sa-min / ZANYBROS / GDW interviews are already in the user’s E-code research imports and original-content-flow.md. **Keep core structure; minor language polish only.**

**4.2 Idol-Director-Harness — Validated + Expand**  
`idol_director_decision` + rhythm_map + visual_motif + camera/transition/effect_language + review rubric (hook, identity/body readability, rhythm, camera motivation, section arc, final memory frame) is exactly what real directors and editors optimize for.  
**Add**:
- Explicit “multi-trigger edit grammar” field.
- “C-to-E translation” and “choreo readability under crop/vertical” checks.
- “Section arc intact after stitch” as non-negotiable in render iteration.

**4.3 C-Code Choreographer Emulation — High Fidelity**  
“Professional idol choreographer / stage-director / camera-aware performance designer” role mode + visible_action (body path/weight/center/spacing/silhouette) + count feel + choreographer QC + semantic equivalence requirement is correct and necessary. Real choreographers are on set daily refining exactly these things.

**4.4 E-Code MV Package & Research Imports — Already Excellent**  
The imported `mv-directing-process-research`, `mv-camera-movement-research`, `mv-scene-transition-research`, `mv-usable-scene-structures`, `mv-package-harness`, `mv-direction-lock` etc. (2026-05-18) already extracted the right principles from the same director pool. The Layer 2 route families and directing card diversity targets are sound.  
**Refine**: Add explicit VFX motivation rules, multi-trigger edit list, and C-to-E translation checklist into the e-code templates and reservoir.

**4.5 B-Code Suno Bridge — Good Base, Replace Old Style Template**
Progression mapping, groove evidence (web/producer quotes only),
manual_suno_gate, and existing comparison memo are correct in intent.
**Adopt the current 2026 style-rail system** (see §2) into B-code output
packets. The old bright-anthem K-pop template is retired because it pulls Suno
toward dated title-song defaults. B-code should choose the style rail first,
then write copy boxes from rhythm engine, hook behavior, vocal pocket, and
section economy. Live prompt drafts are not B-code locks: keep them chat-only
or candidate packets until the founder selects a manual/Suno take or explicitly
asks to save a candidate as the current manual test.

**4.6 Retired Back-Half Integration — Archive Only**  
The older media-scene storyboard and edit-assembly rails are no longer active
IDOL routes. Keep only the general production lesson: founder selection,
section-arc continuity, Suno/manual listening QC, and edit iteration must remain
visible in run-owned records.

**4.7 Daily-Idol-Content-Harness & Clip Economy — Realistic**  
90 s master + 45 s cutdown + point-choreo shorts from shared 6-10 s Grok
Imagine clips aligns with real editor economy and the “MV-led with embedded
stage/performance moments” philosophy. Short vertical derivatives remain an
IDOL packaging output, not a retired route.

---

## 5. Actionable Checklists & Tools (Condensed)

**Pre-0 / A-Code Quality Gate**  
- One-sentence thesis exists? (song emotion → visual conflict/world → brand memory)
- Artist/group identity treated as hard constraint?
- Treatment-level story/scene list written before jumping to pretty pictures?

**C-Code Choreographer QC (already strong — add 2 items)**  
- Every CUT has explicit body path / weight / center / spacing / silhouette + count feel?
- Camera-readable silhouette preserved in wide + close?
- Semantic equivalence to approved stage motion guaranteed before video prompt bridge?

**E-Code MV Pre-Flight (expanded)**  
- Master timeline has clear section arc and must-land frames?
- Clip candidates pull from ≥4–5 directing families with restraint?
- Edit triggers documented (beat + pose + gaze + lyric + energy)?
- C-code motion meaning and member readability survive all proposed effects/crops?

**Suno Generation + Founder QC Gate**  
- Style box + every lyrics section has meta-tags + performance direction?
- First 20-30 Style words identify the current rhythm engine, not generic K-pop?
- Exact BPM/kick/drum/bass/instrument choices are intentional, not guessed?
- Selected rail is explicit: tension pocket, techno 2.0, DnB/hyperpop, house
  emotional groove, performance bite, or custom reference fit?
- Does the 8-12 second opening arc establish sonic identity and complete its
  setup, and do the first full hook and middle return preserve one recognizable
  memory carrier while developing it?
- `00`/`00A` stays unchanged until the founder selects audio or locks a specific
  direction?
- Manual listen against A-code message and C-code choreo function before lock?

**Director / Editor Review Rubric (harness + additions)**  
- Master opening completes its identity signal, setup promise, and hook seed
  across the actual intro boundary, ordinarily around 8–12 s
- First full hook and middle return share a recognizable music-and-screen
  memory carrier while developing meaning, relation, scale, state, or consequence
- Identity + body/choreo readability under intended crop
- Rhythm energy serves section arc (multi-trigger cuts visible)
- Effects motivated and non-destructive to face/feet/hands/meaning
- Final memory frame / posterable moment exists
- Lane fit (native short vs album-component MV)

---

## 6. Sources & Further Reading (Primary Only)

- Han Sa-min, HallyuTones interview, Dec 18, 2025 (full process, song-feel first, full story, artist communication, CG/AI as tool, small differences).
- ZANYBROS (Hong Won-ki & Kim Jun-hong), Korea Times, Jun 5, 2020 (2–3 week cycle, 15-second rule, color + active choreo, fan staff, 5-day all-night shoots, motivation from artist/fan response).
- GDW / Kim Sung-wook via Koreaboo “K-Pop Music Video Creators Reveal The Full 8-Step Production Process” + YouTube Originals K-Pop Evolution (EVERGLOW “Dun Dun”) and Korea Herald “Mic Drop” interview (storyboard importance, DP studies choreo 50×, per-member lighting, positive set vibes, editor close-up glow).
- Korea JoongAng Daily, "Goodbye cutesy, hello techno: Girl groups embrace harder, faster, louder sounds as trends shift", May 25, 2026 — current girl-group techno trend, short-form suitability, faster/harder electronic pressure.
- Billboard Korea, "더 빠르고 더 강하게 K팝이 선포한 테크노 2.0 시대", May 4, 2026 — hard techno, drum-and-bass, hyperpop, anti-drop and chant structures.
- The Korea Times, "How house music is reclaiming its place in K-pop", Feb 9, 2026 — house as emotional rhythm, minimal beats/basslines, nonchalance over maximalist drops.
- Universal Music Canada, KATSEYE "PINKY UP" press release, Apr 9, 2026 — bold percussion, lead bassline, sleek synth textures, global girl-group pop edge.
- TikTok x Luminate Music Impact Report, Feb 13, 2025 — short-form discovery, Billboard Global 200 virality, and off-platform music value.
- Suno official v5.5 blog/help, Mar 26, 2026 — Voices, Custom Models, My Taste, and stronger personalization model behavior.
- r/SunoAI: “The Guide to Meta Tags in Suno AI”, “Updated my master prompting doc”, v5.5 theory threads (2025–2026) — meta-tag `[Section | ...]` syntax and performance prose conventions only; do not use old K-pop genre libraries as default style truth.
- Existing Aurora E-code research imports (2026-05-18-hq-control-tmp/ + ecode/research/) — already cite many of the same directors + treatment guides + MV language papers.

**Recommended next deep dives** (when time): specific 2025–2026 hit MVs with credited directors, newer Han Sa-min or ZANYBROS work, live concert adaptation case studies, VFX supervisor interviews.

---

## Appendix: Key Quote Bank (Director Voices on Quality)

(For quick reference when writing prompts or reviewing boards)

> “I tend to solidify my thoughts by first concretizing the feelings I get from the song and lyrics… write out the full story—even if it doesn’t have a strict beginning, middle, and end… list specific scenes… organize everything I can think of regarding the characters’ costumes, hair, movements, and emotions.” — Han Sa-min, 2025

> “First of all, we listen to the music to understand the overall flow of the song. Then we come up with the concept of a music video. After that, we make a storyboard… The most impactful scenes or ‘secret codes’ should appear in the first 15 seconds… wide use of color and emphasis on active choreography.” — ZANYBROS, 2020 / earlier process interview

> “I draw storyboards imagining all of this [camera angle, shot rhythm, artist movement, mood, song bars, formation changes], so it’s as important as the final outcome.” — Kim Sung-wook (GDW)

(Additional quotes from the full fetched interviews and Koreaboo coverage are embedded in the sections above.)

---

**End of Bible**  
This document is an archive. Use `AGENTS.md`, `schemas/**`, active
`skills/**`, and the current run folder as the IDOL source of truth.

Founder review and any targeted harness/prompt refinements welcome.

**Next action**: Promote only selected, still-useful research notes into active
IDOL-native schemas or skills after founder review.
