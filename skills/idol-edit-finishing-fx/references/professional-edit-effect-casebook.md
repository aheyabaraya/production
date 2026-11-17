# Professional Edit Effect Casebook (04FX Query Surface)

Use this file whenever anyone asks for:

- 편집 효과 / 전환 효과 / finishing FX examples
- CapCut·프리미어·뮤비 에디터 감각의 실제 사례
- “딱딱하다 / 허전하다 / 임팩트 없다 / 프로 느낌이 아니다”
- smash cut, dip to black, whip, impact frame, match cut sell, grade glue
- 04FX `effect_type` 무엇을 고를지

**Scope:** 04FX finishing only. Does **not** own 04 cut selection,
`source_in`/`source_out`, speed, or geometry. If the cut itself is wrong,
return to `idol-editing-qc`.

**Companion files:**

- type/params catalog: `local-ffmpeg-transition-effect-catalog.md`
- AE vocabulary map: `ae-like-effect-map.md`

**Intensity default:** short accents = 2–4 frames at the active recipe FPS unless noted.

---

## How To Query This Casebook

Search by any of:

1. **Founder language:** 딱딱, 허전, 임팩트, 전환 없음, 소스 이질감, 코러스 약함
2. **Editor language:** smash cut, dip to black, impact frame, whip pan sell,
   match-on-action accent, energy jump, source family glue
3. **Song moment:** section gate, downbeat, snare, drop, lyric punch, hold, stop
4. **Local type:** `dip_flash`, `punch_zoom`, `xfade`, `grain_pulse`, ...

Each case has:

- **Signal** — what you see/hear that justifies FX
- **Pro move** — what editors actually call the craft
- **04FX recipe** — local types + starting params
- **Do not** — amateur trap
- **Pass test** — when the effect is allowed into final

---

## A. Hard Cut Family (대부분 효과 없이, 필요할 때만 악센트)

### A1. Clean hard cut (기본 정답)

- **Aliases:** straight cut, butt cut, hard cut, 하드컷
- **Signal:** 몸 착지·시선 고정·카메라 스톱이 이미 음악 마커와 맞음
- **Pro move:** 효과가 아니라 **cut precision**이 주인공
- **04FX recipe:** audit disposition `none_needed`; optional `hard_cut_note`
  remains metadata only and is never a passed FX record
- **Do not:** 매 컷마다 flash
- **Pass test:** 효과 없이 재생해도 박자·스토리 핸드오프가 읽힘

### A2. Motivated hard reset

- **Aliases:** smash into new world, hard reset, cold open into chorus
- **Signal:** 세계/공간/시선 상태가 의도적으로 끊김
- **Pro move:** reset을 숨기지 않고 **선언**
- **04FX recipe:** optional short `dip_flash` 3f @0.18–0.25 **or** nothing
- **Do not:** dissolve로 리셋을 부드럽게 위장
- **Pass test:** “다른 장면으로 점프”가 의도처럼 읽힘

### A3. Smash cut (감정적/리듬적 충돌)

- **Aliases:** smash cut, shock cut
- **Signal:** 조용한 홀드 → 폭음/풀 에너지, 또는 그 반대
- **Pro move:** 대비 자체로 타격. 효과를 얹을 때도 **1회성**
- **04FX recipe:**
  - 진입: `flash` 2f @0.35–0.50 **or** `punch_zoom` 2–3f @1.04
  - 퇴장: `fade_to_black` 3–4f only if void grammar
- **Do not:** smash마다 같은 white flash
- **Pass test:** 한 방의 놀라움; 다음 4마디에 효과 잔상 없음

---

## B. Section / Chorus Gates (뮤비 에디터가 가장 많이 손대는 자리)

### B1. Soft section handoff (구절→프리코러스 등)

- **Aliases:** soft gate, section seam, 섹션 경계
- **Signal:** hard cut은 맞지만 경계가 너무 건조
- **Pro move:** **dip to black / exposure dip**으로 숨을 한 번
- **04FX recipe:** `dip_flash` 3–4f @0.18–0.28 (safe default 후보)
- **Do not:** 긴 dissolve
- **Pass test:** 다음 섹션 첫 글자/첫 동작이 가려지지 않음

### B2. Chorus lift / drop entrance

- **Aliases:** chorus hit, drop in, energy jump sell
- **Signal:** 에너지·온셋·퍼커시브 점프 + 포메이션/카메라 확장
- **Pro move:** 게이트를 **음악 이벤트와 같은 프레임**에 못 박음
- **04FX recipe (pick 1–2, not all):**
  - `punch_zoom` 2–3f @1.03–1.05
  - optional `brightness_pulse` 2–3f @0.05–0.08
  - optional `contrast_pulse` 2f @1.08–1.12
- **Do not:** 코러스 전체 동안 줌/플래시 반복
- **Pass test:** 첫 코러스 바만 선명히 “열림”

### B3. Pre-chorus pressure then release

- **Aliases:** build → release, riser land
- **Signal:** 빌드 끝 프레임에서 손·시선·카메라가 모였다가 풀림
- **Pro move:** 빌드 끝은 억누르고, 릴리즈에만 악센트
- **04FX recipe:**
  - build last 4–8f: mild `vignette_pulse` or slight `eq_grade_window` darker
  - release frame: `punch_zoom` or short `flash`
- **Do not:** 빌드 전체에 grain/rgb
- **Pass test:** 압박→해방이 한 호흡으로 읽힘

### B4. Post-chorus vacuum / afterimage

- **Aliases:** afterdrop breath, hangover bar
- **Signal:** 코러스 직후 밀도 급감
- **Pro move:** 여운을 **덜어내는** 방향으로 처리
- **04FX recipe:** `brightness_pulse` 낮은 음수 느낌 대신 짧은 `dip_flash` 2–3f, or `none`
- **Do not:** 여운에 또 punch
- **Pass test:** 다음 버스/버스 엔트리 방해 없음

---

## C. Impact / Dance Hit Language (전문가 핵심)

### C1. Impact frame / hit frame

- **Aliases:** impact frame, freeze frame hit, 히트 프레임
- **Signal:** 발 디딤, 손 clap, 머리 snap, 포메이션 락이 온셋과 일치
- **Pro move:** 그 프레임을 **한 박 더 읽히게**
- **04FX recipe:**
  - primary: `micro_freeze` 1–2f **or** `punch_zoom` 2f @1.04
  - optional: `brightness_pulse` 2f @0.04
- **Do not:** 얼굴 클로즈업에서 강한 blur
- **Pass test:** 히트 후 다음 동작이 늦어 보이지 않음 (늦으면 04로)

### C2. Snare / rimshot punctuation

- **Aliases:** snare flash, rim accent
- **Signal:** 짧은 타격음 + 작은 바디 악센트
- **Pro move:** 큰 효과 말고 **punctuation**
- **04FX recipe:** `flash` 1–2f @0.30–0.45 **or** `saturation_pulse` 2f
- **Do not:** 매 스네어
- **Pass test:** 마디당 최대 1–2회, 패턴이 보이면 제거

### C3. Kick / chest hit

- **Aliases:** kick punch, body boom
- **Signal:** 로우엔드 킥 + 몸통/카메라 푸시
- **Pro move:** 줌 또는 미세 shake, flash는 선택
- **04FX recipe:** `punch_zoom` 2–3f @1.03–1.05; rare `shake` 2f amp 2–4
- **Do not:** shake를 4f 이상
- **Pass test:** 얼굴이 안 흔들려 보임 (모바일)

### C4. Whip transition sell (카메라/바디 휩)

- **Aliases:** whip pan accent, motion blur bridge, 휩 블러
- **Signal:** 실제 소스에 이미 횡/종 모션 스트릭이 있음
- **Pro move:** 있는 모션을 ** boosten**, 없는 모션을 조작으로 만들지 않음
- **04FX recipe:** `horizontal_blur_whip` 2–3f sigma~2.0–2.8 **or** `blur_pulse`
- **Do not:** 정지 얼굴 샷에 휩 위장
- **Pass test:** 다음 컷 첫 클린 프레임이 선명

### C5. Speed ramp endpoint (04가 만든 속도 변화의 마무리)

- **Aliases:** ramp land, speed hit
- **Signal:** 04에서 speed 올린 뒤 착지가 약함
- **Pro move:** **착지 프레임**만 강조. ramp 자체는 04 소유
- **04FX recipe:** land on `micro_freeze` 1f + tiny `punch_zoom`
- **Do not:** 04FX에서 체감 타이밍 재설계
- **Pass test:** 착지가 음악 마커와 ±1f

---

## D. Match Cut / Continuity Sells (전문가: “효과를 적게, 연결을 많이”)

### D1. Match-on-action accent

- **Aliases:** action match sell, continuity cut boost
- **Signal:** 손/발/시선 방향이 이미 매치인데 경계가 약함
- **Pro move:** match를 **빛/노출 한 방**으로 서명
- **04FX recipe:** `brightness_pulse` 2–3f @0.04–0.07 **or** `dip_flash` 2–3f @0.15
- **Do not:** wipe로 매치를 대체
- **Pass test:** 동작 연속이 더 잘 보임, 효과가 주인공 아님

### D2. Eyeline / gaze handoff

- **Aliases:** eyeline match, look-off cut
- **Signal:** A 시선 끝 → B 대상/멤버
- **Pro move:** 시선 프레임 직후에만 아주 짧은 accent
- **04FX recipe:** usually `none`; if needed `brightness_pulse` 2f
- **Do not:** rgb split on face
- **Pass test:** 시선 경로가 끊기지 않음

### D3. Object / prop state handoff

- **Aliases:** object match, prop bridge
- **Signal:** 폰/거울/티켓/신호선 등 오브젝트 상태가 컷을 이음
- **Pro move:** 오브젝트 하이라이트, 얼굴 가림 금지
- **04FX recipe:** mild `contrast_pulse` or `saturation_pulse` 2–3f; optional later `source_overlay` if precomp exists
- **Do not:** 풀스크린 flash로 오브젝트 가리기
- **Pass test:** 오브젝트가 다음 샷에서도 추적 가능

### D4. Reflection / glass bridge

- **Aliases:** reflection match, glass wipe natural
- **Signal:** 반사면이 이미 두 공간을 섞음
- **Pro move:** 반사 문법 존중, 인위 wipe 최소
- **04FX recipe:** soft `eq_grade_window` unify 4–8f; rare short `xfade=fade` only through a passed 04 boundary handle
- **Do not:** pixelize
- **Pass test:** 세계 규칙이 유지됨

---

## E. Graphic / Stylized Transitions (쓸 때는 세계 문법 있을 때만)

### E1. Dip to black / fadeblack gate

- **Aliases:** dip to black, fade to black, 암전 게이트
- **Signal:** 밤/시스템 오프/막간/리셋
- **Pro move:** **동기화된 짧은** 암전
- **04FX recipe:**
  - timeline-safe: `fade_to_black` 3–5f
  - boundary: `xfade` transition=`fadeblack` duration 0.12–0.20s (sync recheck)
- **Do not:** 매 섹션 암전
- **Pass test:** 암전 직후 첫 정보 프레임이 읽힘

### E2. Dip to white / blow-out

- **Aliases:** flash cut, white-out, 과다노출 전환
- **Signal:** 플래시·카메라 벌브·드림 점프 문법
- **Pro move:** 하양 전환은 **이벤트**
- **04FX recipe:** `fade_to_white`/`flash` 2–4f; flash-safety QC
- **Do not:** 어두운 무드 트랙에 남발
- **Pass test:** 광과민/깜빡임 위험 없음

### E3. Soft dissolve / crossfade (드물게)

- **Aliases:** dissolve, crossfade, 디졸브
- **Signal:** 기억/시간 경과/몽환, 그리고 컷 품질은 이미 통과
- **Pro move:** 약컷 메우기용 dissolve는 아마추어 신호
- **04FX recipe:** `xfade` transition=`fade`/`dissolve`/`fadeslow` 3–6f only through a duration-preserving 04 handle
- **Do not:** 댄스 연속 컷에 dissolve
- **Pass test:** 얼굴/안무 디테일 손실 허용 범위 안

### E4. Directional wipe / slide (그래픽 뮤비)

- **Aliases:** wipe left/right, slide transition, cover/reveal
- **Signal:** UI 패널, 스테이지 카드, 명시적 방향 동선
- **Pro move:** wipe 방향 = 카메라/바디 exit 방향
- **04FX recipe:** `xfade` `wipeleft|wiperight|slideleft|...` 2–4f
- **Do not:** 방향 동기 없는 랜덤 wipe
- **Pass test:** 다음 샷 주인공이 wipe에 안 잘림

### E5. Circle / radial / shutter (포털·시스템)

- **Aliases:** iris, circle open/close, radial wipe
- **Signal:** 눈/포털/감시 UI/시스템 월드
- **Pro move:** 세계 규칙 있을 때만
- **04FX recipe:** `xfade` `circleopen|circleclose|radial|vertopen|horzclose`
- **Do not:** 일반 로맨스 버스에 iris
- **Pass test:** 세계 톤과 일치

### E6. Digital breakup (글리치 계열)

- **Aliases:** glitch cut, RGB split hit, pixel dissolve
- **Signal:** 디지털/오류/신호 세계 + 실제 onset
- **Pro move:** 1–3f, 드물게
- **04FX recipe:** `rgb_split`/`chromatic_shift` 1–2f; or `xfade=pixelize`; `edge_flash` 1–2f
- **Do not:** 뷰티 얼굴 히어로에 장기 글리치
- **Pass test:** 정체성 손상 없음

---

## F. Tone / Source-Family Unification (프로 뮤비 필수 현실)

### F1. Mixed-source glue

- **Aliases:** source family match, grade glue, 소스 이질감 제거
- **Signal:** A/B 소스 감마·그레인·채도가 다름
- **Pro move:** 컷을 바꾸기 전에 **톤 통합**
- **04FX recipe:**
  - short: `eq_grade_window` 6–12f
  - mild `grain_pulse` across seam
  - optional `temperature_pulse` if WB mismatch
- **Better long-form:** recipe `grade` / `grade_profiles` on segments
- **Do not:** hue 크게 돌려 “다른 뮤비” 만들기
- **Pass test:** 경계에서 소스 점프가 덜 보임

### F2. Night vs stage unify

- **Aliases:** exposure match, black level match
- **Signal:** 한 샷은 뭉개진 블랙, 한 샷은 회색
- **Pro move:** contrast/brightness window, not flash spam
- **04FX recipe:** `contrast_pulse` + `eq_grade_window`
- **Do not:** 전체 flash로 가리기
- **Pass test:** 얼굴 디테일 유지

### F3. Chorus color accent (팔레트 안)

- **Aliases:** color hit, sat pop
- **Signal:** 코러스 오브젝트/의상 컬러가 주인공
- **Pro move:** 채도/대비 짧은 상승
- **04FX recipe:** `saturation_pulse` 2–4f or `color_pulse`
- **Do not:** 피부 과채도
- **Pass test:** 스킨 톤 자연

---

## G. Readability / Reinforcement (좋은 컷을 “더 읽히게”)

### G1. Face landing reinforce

- **Aliases:** face read boost, portrait settle
- **Signal:** 얼굴 착지는 맞는데 한 프레임 약함
- **Pro move:** 아주 약한 밝기/샤픈
- **04FX recipe:** `brightness_pulse` 2f @0.03–0.05; rare `unsharp_pulse` low
- **Do not:** pixelize/edge/rgb
- **Pass test:** 메이크/아이라인 손상 없음

### G2. Foot plant / formation lock

- **Aliases:** foot hit, formation freeze feel
- **Signal:** 군무 락 포인트
- **Pro move:** plant 프레임 accent
- **04FX recipe:** `micro_freeze` 1–2f or `punch_zoom` 2f
- **Do not:** 전 멤버 얼굴이 작을 때 강한 vignette로 더 죽이기
- **Pass test:** 발/대열이 더 선명

### G3. Camera stop sell

- **Aliases:** lock-off accent, stop-frame
- **Signal:** 무빙 끝 스톱이 음악 스톱과 만남
- **Pro move:** 스톱 순간에만
- **04FX recipe:** `dip_flash` 2f or `brightness_pulse`
- **Do not:** 무빙 중 blur 과다
- **Pass test:** 스톱이 “의도된 종료”로 읽힘

### G4. Lyric word hit (들릴 때만)

- **Aliases:** kinetic word, lyric pop, 가사 타격
- **Signal:** 특정 단어가 청각적으로 들리고, 화면에 단어/심볼 동기가 있음
- **Pro move:** 텍스트는 장식이 아니라 **큐**
- **04FX recipe:** `drawtext_hit` 4–10f; optional `punch_zoom` on same window
- **Do not:** 안 들리는 가사에 텍스트 도배
- **Pass test:** 모바일에서 읽히고 얼굴 안 가림

---

## H. Founder Complaint → Case Routing (쿼리 최단 경로)

| Founder / review phrase | Open cases | First try |
|---|---|---|
| 딱딱하다 / hard / dry cuts | B1, D1, A2 | `dip_flash` 3–4f |
| 허전하다 / empty / thin | C1, G2, B2 | hit `punch_zoom` or `micro_freeze` |
| 임팩트 없다 / no punch | C1–C3, B2 | `punch_zoom` + optional low flash |
| 전환이 없다 | B1, E1, D1 | safe dip; not wipe spam |
| 프로 느낌 아니다 | F1, B2, C1 | grade glue + one gate accent |
| 소스가 제각각 | F1–F2 | `eq_grade_window` / grain / grade profiles |
| 코러스 약함 | B2, B3 | one chorus-entry package |
| 얼굴이 안 읽힘 | G1; maybe return 04 | tiny brightness; else recut |
| 너무 싸 보인다 / CapCut | reject E4–E6 spam | shorten, lower opacity, fewer events |
| 글리치 원함 | E6 only if world allows | 1–2f rgb_split |
| 암전/여운 | E1, B4 | short fade_to_black |
| 디졸브 원함 | E3 rare | xfade fade with sync note |

---

## I. Ready-To-Copy 04FX Effect Sketches

Values are starting points expressed in frames at the active recipe FPS. Always preview.

### I1. Safe section boundary (default proposal)

```yaml
type: dip_flash
start: 32.000          # program seconds at boundary
duration: 0.167        # 4 frames
opacity: 0.22
```

### I2. Chorus entry punch

```yaml
type: punch_zoom
start: 45.000
duration: 0.125        # 3f
factor: 1.04
```

### I3. Snare flash

```yaml
type: flash
start: 12.458
duration: 0.083        # 2f
opacity: 0.40
```

### I4. Hit freeze-look

```yaml
type: micro_freeze
start: 18.250
duration: 0.083
```

### I5. Source glue window

```yaml
type: eq_grade_window
start: 20.000
duration: 0.333
brightness: 0.02
contrast: 1.06
saturation: 1.04
gamma: 0.98
```

### I6. Digital glitch tick

```yaml
type: rgb_split
start: 50.000
duration: 0.083
pixels: 2
```

### I7. Boundary fadeblack (sync-risk)

```yaml
type: xfade
start_frame: 1536
duration_frames: 4
start: 64.000          # seconds projection
duration: 0.167        # seconds projection
transition: fadeblack
from_slot: R12
to_slot: R13
transition_handle_ref: HANDLE_R12_R13
timeline_impact: program_frames_unchanged
```

### I8. Lyric word

```yaml
type: drawtext_hit
start: 22.100
duration: 0.333
text: SIGNAL
fontsize: 52
fontcolor: white
x: (w-text_w)/2
y: h*0.12
```

### I9. Whip sell

```yaml
type: horizontal_blur_whip
start: 28.000
duration: 0.125
sigma: 2.2
```

### I10. Warm/cool gate

```yaml
type: temperature_pulse
start: 36.000
duration: 0.200
temperature: 6200
```

---

## J. Expert Combinations (패키지, 과하지 않게)

한 이벤트에 **최대 2개** 타입. 3개 이상이면 대부분 과함.

| Package name | Combo | Use |
|---|---|---|
| Soft seam | `dip_flash` | 건조한 섹션 경계 |
| Chorus open | `punch_zoom` + optional `brightness_pulse` | 코러스 첫 타 |
| Dance hit | `micro_freeze` + optional tiny `flash` | 군무 락 |
| Glue seam | `eq_grade_window` + mild `grain_pulse` | 소스 이질감 |
| System tick | `rgb_split` or `edge_flash` | 디지털 월드만 |
| Void gate | `fade_to_black` or xfade `fadeblack` | 의도된 암전 |
| Word hit | `drawtext_hit` + optional `punch_zoom` | 들린 단어 |

---

## K. Song-Form Map (어디를 먼저 볼지)

1. **Intro → Verse1:** soft seam or none
2. **Verse → Pre:** B1 soft gate
3. **Pre → Chorus:** B2/B3 (가장 자주 FX 가치 있음)
4. **Chorus internal dance hits:** C1–C3 sparse
5. **Chorus → Verse2:** B4 afterimage / none
6. **Bridge:** D continuity or E stylized if world asks
7. **Final chorus:** one stronger open, then stop repeating
8. **Outro:** E1 void or G3 camera stop; avoid new effect vocabulary

---

## L. Anti-Patterns (전문가들이 바로 까는 것)

1. **Default dissolve** on every cut
2. **White flash every bar**
3. **Whip blur without motion in source**
4. **RGB/glitch on beauty close-up**
5. **Text when lyric is not audible**
6. **FX used to hide wrong cut timing** (return to 04)
7. **Same package on every section gate** (one-effect drift)
8. **Long xfade that desyncs master audio** without recheck
9. **Pixelize on identity faces**
10. **CapCut preset tourism** with no song/world motive

---

## M. fx_record Writing Skeleton (쿼리 후 바로 기입)

```yaml
fx_id: FX_S03_CHORUS_OPEN_PUNCH
section_ids: [S03]
time_range: "45.000-45.125"
source_edit_segment_refs: [SEG_R18]
eligibility:
  edit_preview_passed: true
  edit_boundary_timing_locked: true
  source_action_marker_known: true
  effect_job: music_accent
trigger:
  audio_or_section_cue: "chorus downbeat / energy jump"
  source_action_marker: "unit formation lock + camera stop"
visible_basis: "group freeze and eye-line settle on downbeat"
effect_design:
  effect_type: punch_zoom
  duration_frames: 3
  factor: 1.04
  program_start_seconds: 45.0
  visible_action: "2-3f push on formation lock"
  endpoint: "return to locked composition before next lyric word"
  renderer_status: supported_now
reason_it_helps: "sells chorus open without changing cut timing"
protection_guards:
  face_hand_foot_body: "faces remain centered and readable"
  full_space_world: "stage depth preserved"
  tone_and_manner: "no new color language"
  timing_feel: "must not feel late vs downbeat"
  mobile_readability: "no crop into necks"
fail_conditions:
  - "feels late or early vs audio"
  - "faces crop awkwardly"
  - "repeats every bar"
preview_qc:
  checks: [timing_feel, identity_body_preserved, full_space_world_preserved, tone_manner_preserved, mobile_readable, flicker_flash_safe, source_quality_not_hidden, repeated_effect_drift_checked]
  qc_note: "draft until proxy preview"
status: preview_needed
```

---

## N. Cross-Index: Pro Term → Local Type

| Pro term | Local `effect_type` / path |
|---|---|
| hard cut | audit `none_needed`; optional metadata-only `hard_cut_note` |
| smash cut accent | `flash`, `punch_zoom` |
| dip to black | `dip_flash`, `fade_to_black`, xfade `fadeblack` |
| dip to white / flash cut | `flash`, `fade_to_white`, xfade `fadewhite` |
| impact frame | `micro_freeze`, `punch_zoom` |
| punch in | `punch_zoom`, `zoom_hold` |
| whip blur sell | `horizontal_blur_whip`, `blur_pulse` |
| motion smear | `tmix_smear` |
| crossfade / dissolve | xfade `fade`/`dissolve` |
| wipe / slide / cover / reveal | xfade wipe/slide/cover/reveal family |
| iris / circle | xfade circle/radial |
| glitch / RGB split | `rgb_split`, `chromatic_shift`, `edge_flash` |
| grade glue | `eq_grade_window`, `grade_profiles`, `grain_pulse` |
| color temperature swing | `temperature_pulse` |
| sat pop | `saturation_pulse`, `color_pulse` |
| vignette settle | `vignette_pulse` |
| lyric pop | `drawtext_hit` |
| camera shake hit | `shake` |
| invert flash | `negate_flash` (rare) |
| digital pixel dissolve | `pixelize_pulse`, xfade `pixelize` |

---

## O. Working Rule (한 줄)

> **좋은 04 컷 위에, 음악이 이미 한 말을 화면이 한 번 더 서명하게 하라.
> 효과가 먼저 말하면 아마추어고, 컷이 말하고 효과가 도장 찍으면 프로다.**
