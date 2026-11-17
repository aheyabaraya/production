# IDOL Reference Management System

This page is the one routing guide for finding, storing, analyzing, reusing,
and tracing visual references. The compact management sheet is:

```text
catalog/references/reference-catalog.yaml
```

The sheet is pointer-only. It does not copy media, replace source-owned
observation or a run-owned binding, grant direct-use or generation permission, or become creative
truth. Its schema is `schemas/reference-management-catalog.schema.json`.

CDD and workers never load this whole sheet to EOF. A mechanical, purpose-bound
query returns a hash-bound pointer shortlist for the exact current need; the
selected profile receives only that shortlist and the exact source-owned records
it resolves. Historical AMV/MAD/fan-edit rows remain readable evidence but are
excluded from every active shortlist and Reference Working Index admission.
Only a new exact current-task Founder permission for one named source, purpose,
and allowed action can open a bounded dispatch; the historical row, local file,
or supplied link cannot do so.

## One Source, One Analysis Owner, One Current-Run Binding

| Layer | Canonical owner | What it owns |
|---|---|---|
| Reusable video source and observation | `source-materials/video-sources/**` | Original bytes, source identity, provenance, broad navigation evidence, and canonical reusable Layer A/B scene/sequence analysis |
| Reusable still-image source | `source-materials/image-sources/**` | Immutable original still, source identity, provenance, availability, and backup state |
| Cross-run management sheet | `catalog/references/reference-catalog.yaml` | Pointers, purpose classes, search terms, and immutable usage-history events |
| Reusable function note | `reference-library/**` | A reviewed, source-cited camera, action, space, light, feeling, object, or edit function |
| IDOL current-run decision | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/**` | Source-analysis revision, exact selected locator, current-song function, disposition, transfer decision, section assignment, and selected crop/segment |
| CF current-run decision | `cf/runs/CF_CONTENT_ID/research/reference-intake/**` plus `research/CF-reference-bridge.yaml` | Source-analysis revision, advertised-subject function, commercial content job, target CF unit, direct-screen role, disposition, and binding |
| Current-title lookup | `catalog/albums/ALBUM_KEY/TITLE_KEY/reference-index.yaml` | Compact pointers for the active album/title |
| Current-title visual package | `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` | The new Founder-reviewed member-key-visual package built or bound for that album/title; space and background remain scene/reference truth rather than a separate package |
| IDOL current-run creative binding | Front Planning -> 01 -> 02A -> 02B | Major Scene, Key Screen Anchor, section/cut assignment, attachment order, and prompt projection |
| CF current-run creative binding | CF reference bridge -> CF20 -> CF30 -> CF40 -> CF50 -> CF60 -> CF70 | Commercial job, Core Cut, Branch Cut, Branch Cut frame, motion, edit, and package lineage |
| IDOL final delivery | `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/package/final-delivery/manifest.yaml` | Exact final originals, optimized derivatives, hashes, and lineage |
| CF final delivery | `cf/runs/CF_CONTENT_ID/generations/cf-code/package/final-delivery/manifest.yaml` | Exact CF final originals, delivery-optimized derivatives, final-used source bytes, reference dependencies, and edit/QC lineage |

Do not create a second media library under `wiki/`. The wiki explains the
route; the management sheet finds records; the canonical source owner keeps
the bytes.

`source-materials` is cumulative across runs. A run normally binds the exact
source analysis, locator, and hash by pointer. Copy only the smallest selected
range/frame/crop when an execution surface requires physical run-owned bytes;
record its source hash and keep the reusable original and Layer A/B analysis in
the source library. Deleting a run must therefore never delete or invalidate
the canonical source observation.

## Album Run And Work-Folder Mapping

The active address is deliberately:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/
```

The `TITLE_KEY` level is retained so one album can hold several songs without
mixing their run versions. The requested work concepts map to the existing
graph-engineering owners as follows:

| Working concept | Active owner |
|---|---|
| Major Scenes and Key Screen Anchors | `research/front-planning-readiness-vN.yaml`; temporary support may live under `work/front_planning_integration/` |
| Current-run reference bindings | the same Front Planning artifact, then exact 01 and 02A fields |
| 02B prompt projection | root `02B-prompt-packets.yaml` plus section deltas under `work/physical_section_shards/` |
| 02B execution receipts and requests | pointer packages under `exports/02B/sections/Sxx/` |
| Final originals and optimized derivatives | existing run-owned media, collected by `package/final-delivery/manifest.yaml` |

`work/` remains noncanonical execution support. Do not split Major Scenes, Key
Screens, or the canonical 02B packet into new competing owners merely to make a
folder tree look tidy.

## Purpose Classes And Retrieval Views

Every reusable unit may carry one or more observed purpose classes:

- `major_scene_grammar_or_feeling`
- `background_and_space`
- `still_camera_and_composition`
- `lighting_color_material`
- `subject_state_or_pose`
- `visible_action_or_hold`
- `object_environment_response`
- `edit_or_transition`

Only after that visual analysis exists, the management sheet exposes five
secondary retrieval views:

1. Major / feeling
2. Background / light
3. Action
4. Camera
5. Edit

These are function-based lookup shortcuts, not the primary reference record and
not blend quotas. A unit's reusable payload is its scene or sequence analysis:
who or what is present, where it is, what happens or holds, and how the selected
anchor is photographed. Front Planning still compares the required
current-section units and selects only what the song, Major Scene, screen gap,
and continuity require.

## Four-Role Graph Lineage

Graph Engineering current-run bindings use at most four production roles:
`character_visual`, `scene_visual_package`, `motion_reference`, and optional
`prop_reference`. Purpose classes above remain retrieval views; they do not
replace those roles. The recoverable chain is `source_id` → locator →
function/role → disposition (`applied` / `combined` / `held` / `rejected`) →
section/Major/Core binding → 02A Branch, 02B packet, and 03V motion storyboard.
Reconstruct from `source_id`, locator, and SHA-256. Wiki is not a second media
library. Default packs and this summary exclude raw URL lists; URLs live once
in the source-intake manifest.

`media_type` remains a source-shape filter (`image`, `video`, selected range,
or selected crop). It is not a purpose class. Front Planning selects a named
function from inspected pixels, records its applied/combined disposition, and
02B exact-carries that unit/function lineage for each logical use. In the scene
package, `world_look_binding` accepts only Major/world/space/light/material/
object-response functions, while `composition_anchor` accepts
`still_camera_and_composition`; both may point to one registered physical
attachment when the same bytes genuinely cover both jobs.

Before CDD selects a reference unit, apply the Graph `reference_candidate`
0--4 profile to its actual image, crop, ordered Sequence Unit, or selected
range. Grade function specificity, source legibility/provenance, current
section or story-gap fit, transfer boundary, and synthesis collision. Motion
temporal change/landing is 4 whenever `motion_reference` applies; still camera,
composition, and depth are 4 whenever that function applies. Candidate grades
0--2 remain held/rejected evidence and cannot be averaged into a selected
package.

This judgment strengthens rather than replaces wiki function extraction. The
exact chain remains interpretation receipt -> `reference_units` function row
-> Front Planning section/Major/Core binding -> 01/02A application -> 02B
`reference_role_plan` -> 03V carry. `media_type` only chooses the inspection
method. Each 02B function-lineage row must exact-bind the current section and
the same physical attachment path/SHA-256 recorded by its Front Planning unit.
When `prop_reference` is material, every prop attachment carries its own exact
Front Planning function-lineage row; an unbound extra prop or duplicate lineage
row is a HOLD. `character_visual` instead keeps the current-title identity
package provenance and does not invent a second FP function merely to fill a
role.

## Dedicated World / Still Department

The ordinary post-song wave is adaptive under CDD. Open only the disjoint
video-capable generalist, physical image-only World/Still, or physical
Pinterest Visual/Composition assignments required by named screen gaps. After
the active Pass-B returns are reviewed, CDD may reopen only the exact owner of
a named unresolved FP-candidate evidence gap. Provider capacity is a ceiling,
never a room-count or source-count quota.
World/Still owns broad still discovery for space/set, world/system,
object/environment, material/light, and still composition. It loads
`idol-world-still-reference-department` and never loads or uses video search,
video hub, playback, download, sampling, frame extraction, or sequence-analysis
instructions.

Every comparison of two or more World/Still images, from bounded-worker shortlist pruning
through CDD Pass A/Pass B and Founder Discovery, covers all compared candidates
on one or more deterministic hash-bound uncropped contact sheets. The sheet preserves the
authored candidate order and displays candidate id, purpose class, section ids,
source identity, and comparison caption. CDD inspects the sheet and exact
individual images. A whole sheet remains comparison/navigation evidence,
counts as zero reusable units, and never replaces individual image/crop paths
and SHA-256 bindings in the Reference Working Index.

World/system evidence uses `background_and_space` when spatial organization
establishes the rule and `object_environment_response` when visible behavior or
consequence establishes it. Do not add an unregistered purpose-class token.

## Retrieval View Pointers

The five retrieval views are pointer-projected under:

```text
wiki/reference-retrieval/INDEX.md
wiki/reference-retrieval/major_or_feeling.md
wiki/reference-retrieval/background_and_light.md
wiki/reference-retrieval/action.md
wiki/reference-retrieval/camera.md
wiki/reference-retrieval/edit.md
```

Those pages do not author analysis. `reference-retrieval/INDEX.md` defines the
analysis-first lookup order; the five view pages preserve legacy function
classification, source/time locators, and evidence pointers only as a secondary
reanalysis queue. Until the linked source read contains the required nested
still observation and, for a multi-frame sheet, Layer A sequence flow plus
Layer B selected-anchor observations, the row remains HOLD for creative reuse.
The canonical tree and examples live only in
`skills/idol-front-planning-director/references/director-operating-contract.md`
under top-level H2 `## 02B-Shaped Source Observation` (Contents → that section).

## Reuse Order

Before downloading or capturing a source again:

1. Resolve the active `ALBUM_KEY`, `TITLE_KEY`, and `RUN_ID`.
2. Query `catalog/references/reference-catalog.yaml` through
   `scripts/idol_reference_catalog_lookup.py` by the named current need,
   source identity, search term, purpose class, and eligible source family. Do
   not pass the full catalog to a CDD or worker. The resolver returns
   pointer-only `candidate_for_worker_review` rows. A source-owned reusable
   Sequence Unit batch lives under that source's `analysis/` tree; the global
   pointer registry is `source-materials/video-sources/sequence-unit-registry.yaml`.
3. Materialize only the hash-bound pointer shortlist, then follow each retained
   pointer into the video hub, still-image hub, title index, or reusable
   function note. Exclude historical restricted edits and unresolved-origin
   navigation rows before launch.
4. Read the full source-owned registered analysis before reopening unchanged media. If the
   analysis is insufficient for the current question, inspect only the
   hash-bound evidence needed to close that gap.
5. Admit its exact analysis revision, source locator, and named function into the current lane's
   run-owned record: IDOL uses `research/reference-intake/`; CF uses that
   folder plus `research/CF-reference-bridge.yaml`.
6. Record `applied`, `combined`, `held`, or `rejected` in the current owner.
7. Add a usage-history event with `production_lane: idol` or
   `production_lane: cf` only after the lane-owned event or binding exists. A
   catalog row never invents application or Founder PASS.

For governing, supporting, and section-bound IDOL units, use an
official/original professional primary source by default. A Founder main
reference routes through origin verification, official genealogy discovery,
official functional discovery, and placement. With no main reference, begin at
the named function and discover an official/original source family first. A
pin, repost, blog, fan moodboard, compilation, or search thumbnail is navigation
only; if no original is verified, return `unresolved_origin` HOLD.

For a CF usage event, bind the exact `CF-reference-bridge.yaml` entry ids and
their canonical entry-set SHA-256, not the hash of the whole mutable bridge
document. Appending an unrelated Founder reference therefore leaves earlier
usage events valid, while changing any actually used entry makes its own event
stale.

The media and reusable analysis store is shared. The application contract is
not: IDOL keeps song/MV meaning and section ownership; CF must state what the
same source does for advertised-subject proof, objection, action,
subject-engine causality, or the final commercial read.

A registered source whose local original is missing is a HOLD. Never silently
download it again. `backup_state: local_only` means it is reusable on this
workspace but not yet portable to another machine.

## Direct Image Reference Route

The existing direct-image route is unchanged.

- Founder-supplied direct images may remain in the owning run's reference
  intake.
- Reusable externally obtained still originals may be registered once under
  `source-materials/image-sources/by-source/SOURCE_ID/`.
- Selected cells and crops remain separate hash-bound files in the current run.
- `bounded_surface_direct`, `full_scene_direct`, and `sequence_direct` preserve
  their exact current-run path, SHA-256, pixel inspection, function, target,
  preserve/discard rules, and Founder state.
- The shared catalog and still-image manifest never authorize attachment.

Current-title member visuals are created or bound for every album/title during
Front Planning. A passed current-title visual binds without repeat review; a
new or fully restyled candidate requires Founder exception selection. Once
passed, it is that title's default Key Screen and downstream identity input,
never a permanent default across albums. Space, background, light, and
composition stay in observable scene text and exact scene-reference bindings
rather than becoming a separate generated background/world package.

## Front Planning To Prompt

Selected motion-support lineage stays inside the existing reference/FP route:
one material Major candidate group may produce one immutable Sequence Motion
Analysis attempt; CDD independently reviews its exact bytes; only the selected
FP Sequence Composition binds the reviewed row. 01 then owns a typed
adopt/partial/reject decision plus exact existing Core/camera/Branch-opportunity
ids, 02A authors Branch still truth without another analysis pointer, and 03V
exact-carries the selected binding while owning final temporal camera after
pixel PASS. Nonselected candidates and `copied_pending_cdd_review` bytes cannot
reach 01 or 03V.

The unchanged creative route is:

```text
director-proposed Major direction
-> current-title visual/reference evidence and exception selection when needed
-> director Major quality review
-> director-authored and quality-checked Key Screen Anchors
-> one consolidated Front Planning Founder review
-> 01 observable scene expansion
-> imported 01 Official Cores, 02A Branch Cuts, and exact visual bindings
-> 02B prompt projection
```

02B owns five required natural-language prompt items:

1. `Identity reference rule`
2. `Scene intent`
3. `Visible details`
4. `Action cue`
5. `Avoid`

They are serialized as exactly five labeled lines for execution. `Visible
details` separately carries background/space, still camera/composition, and
light/color/material. `Action cue` separately carries subject state/pose,
visible action/hold, and object/environment response. A human or assigned model
authors every item after inspecting the exact Branch Cut and bound images;
scripts only validate and exact-copy.

The Graph v2 FP Close decision uses the `front_planning_close` profile in
`automation/graph-creative-judgment-registry.yaml`, is authored as
`idol_graph_contextual_judgment.v2`, and is validated by
`scripts/validate_graph_contextual_judgment.rb`. Motion and still
camera/composition must each be grade 4 for promotion eligibility. PRE-FP
storyline uses the distinct `pre_fp_storyline` profile. The older planning
vector remains legacy-pinned parse evidence; neither planning profile is the
generated Production-Cut pixel rubric used after 02B rendering.

First-read is media-shaped source-pixel observation (still versus ordered
multi-frame sheet), not the final 02B packet and not a whole-sheet mood summary.
Exact trees and examples:
`skills/idol-front-planning-director/references/director-operating-contract.md`
(top-level H2 `## 02B-Shaped Source Observation`; Contents → that section).

## Final Originals And Optimized Delivery

Final delivery remains pointer-first:

```text
runs/ALBUM_KEY/TITLE_KEY/RUN_ID/package/final-delivery/manifest.yaml
-> run-owned source-clean image/video masters
-> delivery-optimized derivatives
```

Do not duplicate final media merely to create an `original/` or
`delivery-optimized/` folder. The manifest declares which exact run-owned bytes
are source-clean originals and which are optimized derivatives, with fresh
SHA-256 at promotion and delivery gates. Optimized files may change codec,
container, dimensions, or bitrate only through an explicit derivative recipe;
they never replace the quality-preserving original.

## Validation

```text
scripts/idol-video-python scripts/validate_reference_management_catalog.py
scripts/idol-video-python -m unittest scripts.tests.idol_reference_function_classification_lock_test
ruby scripts/validate_planning_contextual_grade_vector.rb PATH
ruby scripts/validate_graph_contextual_judgment.rb PATH
```

The validator checks schemas, pointers, hashes, ids, and local availability. It
does not classify references, author analysis, approve a download, select a
creative function, or advance a Founder gate.
