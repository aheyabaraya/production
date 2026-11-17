---
name: idol-contextual-creative-judgment
description: Apply the Graph-bound 0-4 prose evidence profile at PRE-FP, reference, Front Planning, Draft Keyframe, 02B pixel, 03V playback, or 04 edit review without averaging scores or granting automatic creative PASS.
---

# IDOL Contextual Creative Judgment

## Purpose

This is a co-loaded Graph Engineering judgment skill. It does not create a
standalone reviewer, replace the owning creative skill, or grant promotion
authority. Apply only the exact `judgment_profile_id` projected into the
current Role Context Pack and only to the hash-bound artifacts named there.
Author the result as `schemas/graph-contextual-judgment.schema.json` and run
`scripts/validate_graph_contextual_judgment.rb` before returning it.
The artifact exact-binds the originating Dispatch, native Goal event, stage-local
Role Context Pack, evaluated output manifest, author session, and profile-value
hash. A reviewed Dispatch points to the validated artifact; a prose score copied
into a report is not a Graph judgment.
To avoid a circular content hash, `execution_binding.dispatch` points to the
immutable returned Dispatch snapshot that predates the judgment. The later
reviewed Dispatch snapshot may point forward to the judgment; neither file is
rewritten in place.

## Read / Write Contract

Read the exact current Role Context Pack, its bound judgment profile release,
the hash-bound artifacts named for the checkpoint, and the active judgment
schema and validator before authoring. Write only the contextual-judgment
artifact assigned by the Dispatch; do not rewrite the profile release, source
artifacts, reviewed Dispatch, or any creative output under judgment.

At `exact_returned_work_review`, use the candidate's profile release in the
projected review input. The Director writes a production review result instead
of repeating the worker's contextual judgment or applying a different stage's
profile. `scripts/idol_graph_production_review.rb project` copies the exact
candidate, evidence handles, current locks and selected node context for this
review; it does not write observations, scores or a decision. Open the actual
governed files and pixels/playback, preserve the projected metadata, and write
natural observations, findings and bounded correction requirements. The
returned review must bind the Director's own launched Role Context Pack,
independent session and output manifest. Graph promotion verifies those bytes;
a valid projection or a launched-only review cannot close the review.

## Scale

- `4`: governing evidence for this scope; the criterion is production-ready.
- `3`: strong usable evidence; combine or make only a bounded correction.
- `2`: comparison evidence only; material correction is required before use.
- `1`: reject for the current work; the proposed transfer would weaken it.
- `0`: hard collision with a lock, identity, source, feasibility, or screen job.

Never total, average, weight, rank, or convert the vector to a percentage.
Scripts validate range, provenance, profile completeness, and graph routing;
only the assigned human or model authors the grade and prose judgment.

## Prose Evidence Per Criterion

For every applicable criterion write all of:

1. exact typed evidence references in `evidence_locator`;
2. observable claim;
3. screen or playback consequence;
4. what must be preserved;
5. what must change;
6. what must not be inferred;
7. correction action;
8. acceptance evidence that would close the correction.

Current authoring uses `idol_graph_contextual_judgment.v2`. Each
`evidence_locator` is a nonempty array of references with the declared source's
`path` and `sha256`. For a particular structured row, also supply its
`json_pointer` and canonical `value_sha256` together. The validator resolves
these references to actual source bytes; a descriptive string or URL cannot
substitute. Keep the observable claim and other judgment prose natural. For
G2 pixel closure, every criterion covers the exact image of every target Cut,
directly or through a resolved row binding that image. Existing source and
output manifests remain the owners; do not create another asset inventory.
Active pixel_02b derives those targets from the fully verified output manifest:
hash-bound generated still-image outputs (established image suffixes/media types
such as PNG/JPEG/WebP; never semantic filename guesses and never guessed Cut IDs)
and, when present, every in-scope `idol_generated_branch_cut_review.v4`
`branch_cut_reviews` row `image_path` and `image_sha256`. A bound generated image
does not wait for a later G2 review document. Extra keys do not remove a canonical
row. Filename words are legal. A missing image binding or invalid G2 row id HOLDs
rather than dropping the row so other rows can pass. Active promotion also HOLDs
when no image target exists. Historical audit does not treat an empty target set as
coverage.
V1 prose-only locators remain readable only through explicit historical audit
and cannot enter new authoring or active promotion.

Use an explicit `not_applicable` row only when the bound profile permits it and
give the exact scope reason. Performance readability remains in the exact
vector as `not_applicable` when the title has no performance job; it is numeric
when performance is supporting or primary.

## Stage Boundaries

PRE-FP judges and locks target empathy, audience promise, message progression,
and the complete opening-to-ending storyline. Later stages do not rescore
those locks; they report exact lock violations or observable realization.

Reference work judges decision-ready candidates before selection. Preserve the
wiki reference-function chain from interpretation receipt through Front
Planning, 01/02A application, and the 02B role plan. `media_type` describes how
evidence is inspected; it never replaces `function`. Motion is mandatory for
every material Major. Character visual, scene visual package, motion reference,
and optional prop reference remain the only active roles. A scene visual
package may compile world/look/light with still composition, but each function
is judged separately and their synthesis collision is judged before compile.
Authorized selected-reference fidelity is not a generic copy or novelty failure.

The existing `fp_hero_core` remains the Draft Keyframe Proof surface. 02B
judges actual generated pixels. 03V and 04 judge actual playback. Planning,
pixel, playback, and edit criteria are not silently reused across stages.

## Decision And Graph Edge

`eligible_for_director_review` requires every applicable criterion at or above
its profile floor and every named critical criterion at `4`. It means only that
the owning Director may review the exact bytes. It is never creative PASS.

- `combine_or_correct` -> `revise_same_owner` for a bounded same-scope change.
- `hold` -> `return_to_smallest_owner` for missing or stale truth/evidence.
- `reject` -> `stop` for the candidate or route, preserving the rejection reason.
- `eligible_for_director_review` -> `director_review`.

The Director independently checks exact bytes and either promotes, returns a
bounded correction, or holds. The legal chain is output `judged_by` contextual
judgment `selects_next` Director review, followed by the Director's `promotes`
edge to those same bytes. Founder gates remain separate.

## Hard Boundaries

- A hard-gate finding cannot be averaged away.
- A hard gate or grade `0` routes to `hold`; grade `1` routes to `reject`.
  Grade `2` or another below-floor result routes to bounded correction or hold.
- A source URL is not required in the Role Context Pack. Preserve source id,
  locator, local path, and SHA-256; recover the URL only from intake lineage.
- Do not infer creative truth from schema validity, provider success, or file
  existence.
- Do not repeat target/message scoring downstream of PRE-FP.
- Do not allow a low candidate score to mutate the selected storyline or lock.
- Do not create a new `02A Draft` artifact type.
- Authorized selected-reference fidelity is not a generic copy or novelty
  failure. Do not add a copy, novelty, or taste-total criterion.
- When the current assignment authorizes camera-only refinement, preserve the
  cut's emotion, action, and current-song role. 01/02A may refine still
  distance, angle, or framing only; 03V after passed pixels owns temporal
  camera movement, push-in, and speed. Evaluate visible cue, camera,
  readability, and continuity against the bound checkpoint profile only. Never
  total, average, or treat eligibility as automatic PASS.
