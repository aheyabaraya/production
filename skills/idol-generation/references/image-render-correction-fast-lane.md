# Image Render Correction Fast Lane

Use this route only after one validated active
`idol_image_generation_request.v12` has produced a run-owned image and its exact
Generated Branch-Cut Review row is `hold` or `reject` for a named render-local
defect. It repairs the pixels without rewriting canonical 02A or 02B creative
truth. Historical request versions are evidence only and are not readable
inputs to this active route.

## Why This Route Exists

Minor anatomy, surface, light, crop-safety, or artifact problems should not
force this full loop again:

```text
rewrite 02B -> recompile -> reapprove the packet -> regenerate -> rebuild the
whole review material
```

The approved 02B packet and its provider-neutral request remain the immutable
base. A human or assigned model authors one compact correction spec. The
registered preparer verifies all live hashes and derives one correction request;
it never authors, repairs, or paraphrases the prompt.

## Eligible Corrections

The fast lane is limited to restoring an already declared lock through one or
more of these categories:

- `anatomy_repair`
- `identity_fidelity_repair`
- `lighting_integration_repair`
- `render_artifact_removal`
- `forbidden_text_or_logo_removal`
- `crop_safe_margin_restore`
- `locked_detail_restore`
- `color_exposure_match`
- `material_surface_cleanup`

Only `Visible details` and `Avoid` may change. The corrected prompt is still one
complete, human/model-authored five-section prompt in this exact order:

```text
Identity reference rule
Scene intent
Visible details
Action cue
Avoid
```

`Identity reference rule`, `Scene intent`, and `Action cue` must exact-match the
validated base request. Every changed sentence must restore a named existing
02B lock through a JSON pointer and value hash; it cannot introduce a new
direction.

Return to the owning 02A/02B stage instead when the proposal changes timing,
section, Core-Cut, or Branch-Cut ownership, member-visual/reference set or
order, a Founder lock,
story or world, core action or gaze, camera geometry, wardrobe lane, aspect
ratio, quality target, or expected canonical output family. Ambiguity is a
hold, not a reason to classify a structural change as a minor repair.

## Compact Operating Loop

```text
held/rejected generated image + exact review row
-> author compact correction spec
-> derive and live-check one correction request
-> execute one non-overwriting attempt
-> inspect named defect plus regression guards
-> CDD reviews and recommends; Founder selects or holds; Overall alone promotes
```

Prepare the request with:

```text
ruby scripts/idol_prepare_image_render_correction.rb RUN \
  --spec RUN/work/image_render_corrections/PACKET_ID/spec.yaml \
  --write
```

The default derived path is:

```text
RUN/work/image_render_corrections/PACKET_ID/CORRECTION_ID-attempt-NN.yaml
```

The spec is `idol_image_render_correction_spec.v1`. It names the content,
correction and packet ids; author/reason; base request path/hash; source image
path/hash; exact prior-review path/hash/pointer/value hash; defect categories,
observed problem, expected correction, changed prompt sections, and existing
lock pointers; the full corrected prompt; all preservation assertions; the
Founder authorization path/hash; and the attempt index plus candidate/review
paths.

The preparer automatically verifies the validated v12 base request, canonical
02A v3.0 and 02B v2.6 bytes, active v7 context pack, FP v17 planning source,
approval artifact, current-title
member-visual inputs, scene-reference inputs, the exact combined attachment
order, source image, and prior review. It emits
`idol_image_render_correction.v8` as an adapter-specific ready state or `hold`.
It does not regenerate 02B, mutate the base request, execute a model, upload a
file, or grant approval.

## Bounded Founder Authorization

The run-owned `idol_image_render_correction_authorization.v1` binds:

- Founder identity, content/correction/packet ids;
- exact base-request, source-image, and prior-review hashes;
- one adapter and the allowed correction categories;
- `max_attempts` from one through five and exact authorized attempt indexes;
- explicit external-execution and paid-generation approval booleans.

One valid authorization may cover several named attempts inside that exact
scope. A retry inside the bound attempt indexes does not reopen 02B review or
packet approval. A changed base request, source image, prior review, adapter,
category, input hash, or attempt ceiling needs a new authorization. General
graph-engineering permission never counts as approval for a real paid job.

The correction candidate must stay in the base packet's output directory,
retain the packet id and original extension, and use a new filename. Never
overwrite the source image or the base expected output.

## Adapter Boundary

Registered Grok `grok_image` may become ready when every contract and approval
check passes. It consumes the
edit-source image first, followed by the unchanged v12 combined attachment order
(current-title member visuals and then applicable scene references). No
separate face-reference lane may be introduced during correction.

The active `openai_api_gpt_image_2` v12 base executor does not implicitly gain
correction authority. An OpenAI API correction remains `hold` until a separate
Founder-gated correction executor exists. If that route is later registered, it remains locked to
`gpt-image-2`, the exact current v12 combined attachment order, exact current-job
approval, and a secret-safe runner. Do not improvise an API edit payload.
`xai_api_media` remains default-disabled and holds while its exact registered
image-edit profile is absent or stale and until a separate Founder-gated
correction executor binds this v8 artifact. This preparer reads no secret value,
and the lane may not infer an endpoint/model or fall back.

## Review Boundary

The assigned post-02A section owner pixel-inspects the actual candidate. One
explicitly authorized bounded forensic adviser may assist only for a named
pixel ambiguity. The mandatory scope is deliberately small:

1. the named defect is resolved;
2. identity has not regressed;
3. adjacent visual continuity has not regressed;
4. anatomy has not regressed.

The technical disposition is `technical_pass`, `technical_hold`, or
`locked_rubric_rerun`. Scripts cannot auto-pass it. For a model-authored
correction, the owning V-Ci Section-Cluster CDD after the verified Graph v2
switch—or the pinned legacy CDD before it—provides the creative recommendation,
and the Founder retains final selection authority. For an exact
Founder-authored correction, the section owner, adviser, and owning CDD may report only objective pixel,
identity, continuity, anatomy, safety, or feasibility defects; no additional
LLM taste verdict may veto or reopen the named Founder choice. The Founder
decision may update the exact existing Generated Branch-Cut Review row through
replacement lineage instead of rebuilding or rereviewing the whole section
board. A selected correction is registered with its actual path, SHA-256,
source image, base request, correction request, Founder-direct receipt when
applicable, and review receipt.

One multi-section or whole-video workbench cycle may group several such visible
defects for comparison, but each correction request remains bound to one image
packet and one section owner. Disjoint affected sections may execute their
requests in bounded parallel; the grouped review does not create an all-film
correction request.

## Speed Budget

- Use the active-frontier checker, not the repository-wide audit, before a
  correction attempt.
- Do not rebuild 02A, 02B, the section context pack, prompt export, or whole
  review board when their live hashes still match.
- Local derivation and validation target p95 at or below two seconds on a warm
  workspace; generation time is measured separately.
- Keep one compact spec, one bounded authorization, one derived request, and
  one review receipt per attempt. Reuse the same approved authorization within
  its exact attempt scope.
- Continue in the same provider-resolved post-02A section lifecycle; do not open another
  session merely because a render-local correction is needed.
