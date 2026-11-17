# Founder Collaboration, Reference Development, And Workbench Final Improvement Plan

Status: final consolidated proposal v0.3; local connector corrections
implemented and dummy-qualified on 2026-08-05
Date: 2026-08-04
Primary scope: IDOL full-song MV and master-derived short-form
Boundary scope: CF remains an isolated commercial-production lane
Authority: Founder-reviewed noncanonical proposal. This file does not itself
change active policy, schema, skill, stage truth, paid-generation permission, or
public-release authority.

This document supersedes v0.2 and the earlier design recommendations in this
file. The
implementation evidence in
`automation/state-reports/idol-director-workbench-reference-and-asset-routing-audit-2026-08-04.md`
remains useful, but any cross-lane card or reference recommendation in that
audit is superseded by the IDOL/CF separation decision below.

## 1. Final Decisions

The production system should keep its current stage order and improve the
handoffs, Founder interaction, and projection layer around it. It should not
create another planning stage or make the Workbench a second source of creative
truth.

The agreed operating decisions are:

1. Use Director-led production with Founder milestone control as the default.
2. Let automatic PRE-00 output open the first Founder choice directly. Do not
   add a separate `Direction Seed`, `A1`, or other canonical stage.
3. Keep the Founder in direct conversation for song development. Run visual
   preparation asynchronously after the PRE-00 direction/reference preview has
   been reviewed, so the Founder does not have to manage song and visual detail
   at the same time.
4. Keep FP Final as a logical creative lock, but do not require a separate
   meeting when a provisional 01/02A package is already ready. One review cycle
   may present FP first and the exact 02A scope second, in canonical order.
5. Use the Workbench as the visible Overall Director room over the existing
   graph-engineering runtime. The stable Founder HTML and Workbench must show the same IDOL
   projection, not independently summarized cards.
6. After exact 02A approval, let fresh section-scoped provider-resolved
   `section_image_motion_worker / worker_high` lineages own 02B,
   generation, pixel review, and 03V handoff. The Workbench only coordinates and
   projects their status and results.
7. Keep canonical media once at its owning path. Boards, contact sheets,
   thumbnails, and caches are pointers or rebuildable views, never second
   owners.
8. Do not lift Grok or Luna fan-out ceilings. More parallel sessions are useful
   only while byte ownership is disjoint and the Overall Director can review
   returns without backlog.
9. Preserve the current review-board visual language. Keep its dark palette,
   typography, card shape, image-first tone, containment behavior, section
   navigation, and overall density; improve only information allocation,
   grouping, filtering, collapsing, and continuity management.
10. Keep one versioned review-board lineage that can receive new references and
    generated images without losing earlier decisions. Workbench and HTML must
    display the same revision, active cycle, asset states, roles, and order.

### Explicitly rejected and excluded

Do **not** create a normalized cross-lane contract such as `MAIN 1..N`,
`SUPPORT 0..N`, `co-MAIN`, or one shared MAIN/SUPPORT authority model for IDOL
and CF.

- IDOL keeps its IDOL-native Front Planning, reference-application, Key Screen,
  01, 02A, and 02B semantics.
- CF keeps its own CF00-CF70 stages and its asymmetric commercial-reference
  authority: once selected, one governing main controls the approved campaign
  route, while supporting references fill phase-scoped details without
  reordering or replacing it.
- The two lanes may reuse low-level UI mechanics only after separate adapters
  exist. They do not share creative card fields, cardinality rules, canonical
  bytes, stage ids, or reference authority.
- The Ionia board is a useful CF layout and interaction example. It is not the
  semantic template for an IDOL MV board.

## 2. What Is Already Active And Should Not Be Proposed Again

The following are confirmed current baselines. Later implementation should
preserve and connect them rather than rewrite them as new features.

| Area | Confirmed current baseline | Final-plan treatment |
|---|---|---|
| IDOL route | `PRE-00 -> song/audio/00A -> Front Planning with 01R/01R-C -> FP Final -> 01 -> 02A -> 02B -> generated review -> 03V -> 04/04FX -> 05` | Preserve |
| PRE-00 | Automatic target/trend work produces two to four target connections; each has one main visual preview and one to two supporting previews before target choice | Use as the first Founder milestone; add no stage |
| Director topology | One continuing Overall Director, one durable pre-02A Creative Development Director, bounded departments, and fresh post-02A section owners | Preserve |
| Front Planning | Discovery, Direction Synthesis, 01R and optional 01R-C, and one FP Final already belong to one workbench flow | Preserve |
| Reference evidence | Official/original-first search, exact locators, selected frame/crop/sequence derivatives, source paths/hashes, and per-section comparison floors already exist | Preserve |
| Contact sheets | Whole sheets are navigation evidence and count as zero; the selected cell, crop, frame, or bounded sequence is the usable unit | Preserve |
| 02A | Core and Branch counts are uncapped and follow the screen job rather than a quota | Preserve |
| 02B | One prompt packet per Branch Cut contains exactly five natural-language items; member identity is attached only when a member is meaningfully visible | Preserve |
| File management | Run, source, identity, review, generation, edit, and delivery locations are already defined; review surfaces point to originals | Preserve |
| Stable board | One `RUN/review/founder-workbench.html` lineage and one source manifest already exist | Extend the projection; do not create another board |
| Concurrency | Provider and stage ceilings, disjoint ownership, and review-backpressure rules already exist | Do not raise the ceilings |

There is therefore no need to redesign the production graph, invent a new
reference quota, create a second FP, or make a special Workbench-only creative
artifact.

## 3. Final IDOL Production And Founder-Collaboration Flow

### Canonical order

```text
automatic PRE-00 research
-> Founder target/direction choice
-> Song Room conversation + asynchronous visual preparation
-> selected audio and selected-audio analysis
-> 00A
-> Front Planning [Discovery + 01R/01R-C + Direction Synthesis + FP Final]
-> 01
-> 02A
-> 02B
-> generated-image review
-> placement and 03V
-> edit/QC and delivery
```

Master-derived shorts come from the passed full-song spine and master
continuity. They do not open a second Front Planning route or a separate
reference-quota system.

### 3.1 Intake and automatic PRE-00

The minimum Founder input is intentionally small:

- full-song MV or master-derived short-form intent;
- title/song identity when already known;
- one sentence describing the audience response, message, or feeling;
- any hard `must` or `avoid` condition;
- optional references, partial order, or member-visual direction.

PRE-00 then prepares two to four evidence-backed target connections. Each
connection already includes a reviewable main visual preview, one to two
supporting previews, the expected song and screen reward, fit, and mismatch
risk. These previews support target selection only. They are not direct-use
locks or section bindings.

The PRE-00 result itself is the first Founder selection packet. There is no
waiting step between that result and the first choice, and no new formal `A1`
stage.

### 3.2 Song Room and visual preparation

After the Founder selects the PRE-00 target/audience promise:

- the Founder develops and chooses the song through direct Song Room
  conversation;
- the CDD independently prepares verified visual sources, world/action/camera
  families, provisional Major Scene families, and any authorized current-title
  member-visual draft;
- the visual lane starts from the selected PRE-00 direction and the Founder's
  response to its reference previews;
- it returns one curated recommendation rather than asking the Founder to
  follow raw research or every worker turn.

The Founder may inspect or redirect a material visual reference while the song
is being developed, but ordinary visual preparation does not require continuous
conversation. Before selected audio and 00A, the visual lane may prepare
families and provisional order only. It may not finalize exact song-section
placement, official Core/Branch ids, 02B prompts, or edit timing.

### 3.3 Front Planning

Selected audio and 00A are the synchronization point. The CDD aligns the
prepared visual inputs to the real song and builds the whole-video plan.

The Founder-facing FP package should show:

- the locked target, audience promise, and MV message;
- selected-song section order and whole-video progression;
- ordered Major Scenes;
- Key Screen Sequences that show how the important visible events develop;
- selected references already placed at their intended sections and sequence
  positions;
- exact selected cells, frames, crops, or bounded sequences for direct use;
- current-title member visuals only where a member is meaningfully visible;
- the transition, continuity, and risk consequences of the recommendation.

The Founder may pass, hold, reject, reorder, replace, or move a reference to a
different named section. The Founder does not need to sort a raw search pool.

### 3.4 FP Final and 02A review

FP Final remains necessary because it locks the whole-video meaning, Major/Key
Screen order, and reference application before generation geometry is fixed.
It does not need to become a separate appointment.

When the recommendation is mature, the studio may prepare provisional 01 and
02A material behind the same review cycle. The interaction remains ordered:

1. Founder reviews and passes FP Final for the named scope.
2. Only that passed scope becomes eligible for its prepared 01/02A projection.
3. Founder reviews exact Core Cuts, Branch Cuts, selected single-image inputs,
   attachment order, and member-visual use.
4. A HOLD affects only the named sections and their downstream dependents.

This shortens the Founder session without merging the canonical stages or
allowing 02A to approve itself before FP.

### 3.5 Post-02A execution

After exact 02A approval, one fresh hash-bound provider-resolved
`section_image_motion_worker / worker_high` lineage opens just in time for one
physical section. It receives only the approved section truth,
immediate same-section neighbors, exact reference derivatives and order, and
the current-title member visual when applicable.

That lineage owns:

```text
02B five-item prompt authoring
-> generation
-> pixel and continuity review
-> Generated Branch-Cut Review return
-> approved 03V handoff
```

At most three disjoint section sessions may run asynchronously under the active
IDOL invariant. Grok may execute an approved route as a peer, but it receives no
uncapped subagent pool and no authority to bypass section ownership, external
permission, or Founder gates.

## 4. Founder Intervention Before 02B

The normal interaction schedule is small and predictable.

| Moment | What the Founder does | What the studio does next |
|---|---|---|
| Intake | Gives a short direction, must/avoid, and optional references | Runs PRE-00 automatically |
| First milestone | Selects one target/audience promise and reacts to its visual previews | Opens Song Room and visual preparation |
| Song Room | Directly discusses and chooses the song route | Completes selected-audio analysis and 00A while visual preparation continues |
| FP/02A review cycle | Reviews the whole flow first, then exact pre-generation screens for passed scope | Opens only approved section execution |
| Generated-image review | Passes, holds, or rejects actual pixels | Passed sections continue to placement and 03V |

An extra interruption is justified only for an unresolved material Founder
choice, conflict with an explicit lock, required new member-visual selection,
or paid/external permission. Discovery signals remain optional and nonbinding.

## 5. IDOL Reference Development And Review Language

### 5.1 Distinguish the media forms

| Term | Meaning in the IDOL lane |
|---|---|
| Original source | The official/original MV, visual film, still, campaign, performance, or other verified source identity |
| Sequence/contact sheet | A navigation or comparison view of an original source; it is not itself a usable reference unit |
| Selected reference unit | One exact cell, frame, crop, direct scene image, or bounded contiguous sequence with its own path and SHA-256 |
| Major Scene | A pre-02A whole-video event or scene family used to judge the large flow |
| Key Screen Sequence | An ordered pre-02A presentation of the screens or reference units that show how a Major Scene will unfold; it is not an official Core/Branch contract |
| Core Cut | The 02A parent event, action, effect, condition, or dramatic beat |
| Branch Cut | One independently framed and generatable realization that reveals or extends its parent Core event |

Research candidates may arrive as original sources, bounded video sequences,
or selected still units. The Founder-facing board should never leave that form
ambiguous. Every tile names its source identity, exact locator, media form,
intended function, and whether it is a preview or a direct-use selection.

At 02A and 02B, every still attachment is shown and bound as its own selected
image/frame/crop path. A contact sheet never substitutes for those units. When
an ordered sequence governs the scene, preserve its sequence identity and order
while passing the exact selected derivatives individually to a still-image
execution surface.

### 5.2 Research breadth and Founder-facing size

Do not require a different original source for every Major Scene. Reuse one
strong source or source family across connected Majors when it preserves the
same world, action system, or camera/sequence grammar. Search for a new
governing source when the event, body route, world response, composition,
performance function, material behavior, or other essential screen job truly
changes. Source diversity is comparison evidence, not a collage quota.

The active 01R comparison floor remains at least three reviewable reference
units per active visual section, from at least two original source identities
and at least two directorial/content functions. Three to five selected evidence
units are ordinary; five to eight suit complex work. A candidate unit may be a
standalone image, selected cell/crop/frame, bounded video segment, or contiguous
sequence bundle. A whole sheet counts as zero, and several cells from one scene
do not falsely multiply the comparison count.

The Founder sees the curated, already-placed recommendation and at most one
materially incompatible alternative. The larger comparison set remains
available on demand. The counts describe reviewable evidence units, not a
required number of different full original videos and not a required number of
attachments to blend.

### 5.3 IDOL reference authority without a new cardinality schema

The Founder may supply one reference, a bundle, or three to four important
references. The CDD should place them where they do the strongest work and
state what each unit governs or contributes. Several direct-use units may be
combined across phases or Key Screens when their responsibilities are explicit
and compatible. This does not create a new `MAIN 1..N` schema.

If one governing unit already contains the necessary action, space, camera,
light, and object response, do not invent a supporting attachment merely to
fill a field. The research comparison floor still applies, but comparison
evidence is not a blending quota.

If reference A governs the event, action, and composition while B and C add
only named light, material, object, or transition details, the later prompt
preserves A's screen grammar and adds only those declared details. If A and D
both need to retain incompatible governing events, do not average them:

- create separate Core Cuts when the governing event changes;
- create separate Branch Cuts when they are materially different reveals or
  extensions of the same event;
- reject or hold a unit when it adds no distinct screen information.

### 5.4 Founder movement and reordering

Within the IDOL Workbench, the Founder should be able to reorder reference
units inside a section or move them between named sections, then state the
intended change in ordinary language.

```text
Move A from S02 to S04.
Use it as the governing reference there.
Remove it from S02.
Keep B only for lighting.
```

The final behavior is:

1. Drag/reorder alone records a visible pending placement change.
2. The accompanying instruction supplies role, scope, add/remove, and order
   meaning.
3. When exact, it becomes a `founder_direct_update` for the named fields and
   sections without a second taste veto.
4. The Overall Director or CDD records the smallest-owner patch and invalidates
   only affected downstream revisions.
5. The source bytes are not copied; only bindings and order change.
6. If meaning remains ambiguous, ask one concise question rather than guess.
7. Workbench and HTML re-render from the same patched IDOL state.

### 5.5 IDOL card shown identically in Workbench and HTML

Before 02A, both IDOL surfaces should render the same source-bound card, in the
same order:

```text
SONG / SECTION / CONTENT JOB
SCREEN
MAIN
SUPPORT
SELECTED UNITS AND CONSUMPTION ORDER
KEY IMAGE
MEMBER VISUAL, only when applicable
```

`SCREEN` states the visible event or intentional hold. `MAIN` and `SUPPORT`
show the current IDOL-native reference applications and exact responsibilities;
they do not import CF cardinality or authority. `KEY IMAGE` states the camera
height, distance, direction, angle, depth, composition, placement, crop,
negative space, action/hold, object or environment response, light, material,
and continuity facts that must survive generation.

After 02A, official Core and Branch ids appear beneath the same parent
projection. They do not replace the pre-02A meaning or create duplicated cards.

### 5.6 Translation into 02B

Before authoring a Branch prompt, the section owner inspects the exact Branch
Cut, every selected derivative, and every bound current-title asset in its
declared order. The owner translates the actual pixels and plan into exactly:

1. `Identity reference rule`
2. `Scene intent`
3. `Visible details`
4. `Action cue`
5. `Avoid`

The translation preserves the dominant event, action, space, composition,
still-camera geometry, crop, light, material, and object response. It combines
the passed member visual only when a member is meaningfully visible. A
non-member screen receives no forced identity attachment. Identity never forces
a frontal face, frontal gaze, pose, crop, or camera angle.

## 6. CF Remains A Separate Production System

CF keeps this route and authority inside `cf/`:

```text
CF00 -> CF10 -> CF20 -> CF30 -> CF40 -> CF50 -> CF60 -> CF70
```

Its cards and decisions are built around advertised subject, need, proof,
objection, action, claim safety, platform, and commercial endpoint. Its
reference rule remains asymmetric after lock: the selected governing main owns
the approved campaign route, and supporting references supply only named
phase-scoped details.

Accordingly:

- no IDOL `Major Scene`, `Key Screen Sequence`, FP, 01, 02A, or 02B field is
  used to satisfy a CF stage;
- no CF00-CF70 field is added to an IDOL stage or IDOL card;
- the current IDOL-native Workbench must not mount `cf/runs/**`;
- any future CF Workbench integration requires a CF-owned adapter, contract,
  renderer, validation fixture, and review language;
- common window chrome, image viewing, drag mechanics, or decision buttons may
  be reused only as neutral UI components;
- Ionia may inform spacing, image scale, section navigation, and review
  ergonomics, but not IDOL reference authority or stage meaning.

The current working-tree draft of the IDOL visual-board contract includes
cross-lane example wording that presents CF through the same visible card
sequence. That wording must not be promoted as the final rule. A later
implementation patch must restrict the IDOL contract to IDOL and leave CF
semantics under `cf/`.

## 7. Graph Engineering, Workbench, HTML, And Agent Responsibilities

| Surface or owner | Responsibility |
|---|---|
| Canonical IDOL Graph Engineering | Owns stage truth, reference bindings, Founder epochs, paths/hashes, locks, and smallest-owner invalidation |
| Overall Director | Owns whole-video judgment, Founder presentation, promotion, continuity, and acceptance |
| Creative Development Director | Owns pre-02A development, curated departments, reference placement, and reviewed milestone packages |
| Luna/Max departments | Return bounded evidence or noncanonical shards to CDD before 02A |
| Fresh provider-resolved post-02A section lineage | Owns one section's 02B, generation, pixel review, and 03V handoff through the selected provider's own worker profile and media tools |
| Workbench | Provides the visible Overall room, scoped conversation routing, planning interaction, and state projection |
| Stable Founder HTML | Provides the source-bound review projection and decision surface; it owns no independent creative truth |

The Workbench is therefore not a standalone planning application beside the
graph-engineering runtime. It reads current canonical owners, records allowed Founder actions
through the existing decision/intervention route, and refreshes the same board
projection.

### 7.1 Implemented post-02A projection

02B and generated-image results can now appear under their owning section
while the Workbench is open:

- each section card reads the canonical job/status/result path and SHA-256;
- a new result triggers a scoped refresh or appears on the next reload;
- the board shows the original through a safe pointer or rebuildable proxy;
- the Workbench does not copy the original merely to display it;
- PASS/HOLD/REJECT returns through the owning generated-review contract;
- only affected sections refresh.

This behavior is now implemented as a read-only, owner-backed projection. The
native Workbench remains `front_planning_integration_only` for authoring, but
its managed board route checks and, when required, deterministically refreshes
the same stable manifest/HTML from the registered IDOL owners for 01, 02A, 02B,
generated Branch review, 03V, and 04. Owner/query drift produces a visible HOLD;
the Workbench does not acquire stage-writing or media-owning authority.

### 7.2 Review-board version and accumulation management

The basic board lineage already exists and should be retained:

- one stable `founder-workbench.html` path;
- an integer board revision;
- one active cycle id;
- an explicit `supersedes_revision_id` chain;
- earlier cycles collapsed and read-only;
- decision exports bound to the exact manifest revision and SHA-256.

The original v0.3 diagnosis was that stable board lineage solved file
proliferation but not asset accumulation. The implemented path now closes that
gap: a stable owner index registers canonical feeds, the deterministic
assembler compiles the derived source set, and one pointer-only asset register
makes every eligible incoming item represented or explicitly held without
turning the board into a second owner or an endlessly expanded gallery.

The existing board projection now carries one pointer-only review asset
register. It does not own the media or creative decision. For every visible or
pending asset, it projects:

- stable asset id, canonical path, SHA-256, media kind, and original owner;
- first-seen board revision and most recent binding revision;
- exact section, Core, Branch, or later review target;
- current lane-owned role and current disposition/review state;
- whether it is new since the Founder's last reviewed board revision;
- replacement or supersession relation when applicable;
- the decision receipt or canonical owner that explains its state.

New media enters a visible `NEW SINCE LAST REVIEW` inbox. It remains there until
it is assigned to a target and classified by the owning lane. Nothing disappears
merely because it was not selected. Unused, held, rejected, or superseded items
move to collapsed, count-bearing groups and retain their canonical pointers and
decision lineage.

The board materializes the active cycle, new inbox, and last passed rollback at
normal detail. Older cycles remain available through their compact headers and
load media only when opened. Reusing an existing path/hash adds a new typed
binding, not another copy or visually duplicated asset record. This keeps
long-running boards reviewable while preserving every decision and source.

Workbench and HTML must not implement separate board models. The Workbench
should dock or open the same generated board projection and show the same:

- board revision and active cycle;
- `new`, active, held, rejected, passed, and superseded counts;
- reference/output grouping and declared order;
- Founder decisions and pending items;
- selected filter and expanded/collapsed state when that view state is saved.

If Workbench and HTML manifest revisions differ, both surfaces show a visible
stale/refresh hold instead of letting the Founder review mismatched material.
View preferences such as filters and open groups remain noncanonical UI state;
creative role, order, disposition, and approval remain canonical-owner
projections.

### 7.3 Minimal visual cleanup, not a redesign

The current style is the baseline. Do not change the palette, typography,
rounded card language, decision buttons, `object-fit: contain`, large-image
priority, or overall visual character. Make four focused layout corrections.

#### A. Give Face / Style Identity enough comparison space

The current fixed `220px` member rail and vertical face-then-style stack are too
narrow for at-a-glance comparison. Keep the left-member/right-reference card
shape, but make the desktop member allocation adaptive rather than fixed:

- use a practical minimum around `280px` and a bounded proportional width,
  instead of forcing every card to `220px`;
- show the primary face and primary style side by side when space permits;
- put additional styling images in one compact horizontal strip/carousel rather
  than extending the rail as a long vertical stack;
- keep full-frame `contain` behavior and click-to-enlarge;
- at the existing responsive breakpoint, stack the complete member block above
  references at full width.

This changes allocation, not the visual design or the member-identity rules.

#### B. Make Core-Cut cards image-first and decision-sized

Facts and provenance are already collapsible, but `DIRECTION`, `SCREEN PROOF`,
the question, and long supporting copy are still open together. Keep the image,
one compact screen/decision summary, the exact review question, and decision
buttons visible by default. Place full Direction, Screen Proof, detailed facts,
contracts, and provenance in clearly labelled keyboard-accessible disclosure
groups.

Do not delete or silently line-clamp production truth. The collapsed header
must show the essential one- or two-line consequence and item count, and the
full text remains searchable and available on demand.

#### C. Separate used, undecided, and inactive material visibly

The current board can collapse whole cycles and filter undecided cards, but it
does not filter media by reference disposition or generated-output review
state. Add a compact filter row with counts, using text labels as well as color:

```text
NEW | ACTIVE / USED | CANDIDATE / HELD | REJECTED | SUPERSEDED | OUTPUTS
```

Default review shows `NEW` and `ACTIVE / USED`. Candidate/held remains one
click away. Rejected and superseded remain preserved but collapsed. A media
card displays its state badge directly over or immediately below the image;
the Founder should not need to open file/hash metadata to discover whether it
was used.

State must come from the lane's actual receipt or output review. The renderer
must not infer `used` from position, filename, visibility, or visual similarity.

#### D. Group references by their actual role

Role and disposition are separate questions: role explains what an image is
for; disposition explains whether it survived. Render role groups with visible
headings, counts, and individual collapse controls instead of one undifferentiated
carousel.

For IDOL, the visible groups may express its existing native applications such
as governing/Main, named Support jobs, context/alternative evidence, and
generated outputs. CF must use its own commercial labels and asymmetric
governing-main/phase-support authority. The shared shell may provide the group,
count, collapse, and filter mechanics, but it must not normalize IDOL and CF
role cardinality or meaning.

The current Ionia manifest confirms the gap rather than defining the solution:
revision 13 retains four cycles, including three superseded cycles, so board
version lineage is working; however, its 95 media rows are currently represented
as 73 `diagnostic` and 22 `member_visual` items with no visible reference
dispositions. That makes its accumulated media hard to scan by use and role.

## 8. Fixed IDOL File Placement And Capacity Rules

`RUN` below means `runs/ALBUM_KEY/TITLE_KEY/RUN_ID`.

| Asset class | Canonical placement |
|---|---|
| Unselected run-local reference cache | `RUN/research/_local_reference_cache/` |
| Selected cell, crop, frame, or bounded sequence | `RUN/research/reference-intake/REFERENCE_UNIT_ID/` |
| Reference working lookup | `RUN/research/reference-working-index.yaml` |
| Reusable video original and source analysis | `source-materials/video-sources/PLATFORM/by-source/SOURCE_ID/` |
| Reusable still original and source record | `source-materials/image-sources/by-source/SOURCE_ID/` |
| Current-title member visuals, grouped by member | `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/` |
| Temporary planning/Grok roughs | `RUN/generations/front-planning/grok-roughs/JOB_ID/` |
| Founder board source and render | `RUN/review/manifests/founder-workbench.yaml` and `RUN/review/founder-workbench.html` |
| Section 02B export | `RUN/exports/02B/sections/Sxx/` |
| Section image-generation request | `RUN/work/image_generation_requests/sections/Sxx/` |
| Generated Branch original | `RUN/generations/branch-cuts/Sxx/BRANCH_CUT_ID/original.png` |
| Storyboard boards | `RUN/generations/boards/` |
| Video prompts and media | `RUN/generations/video-prompts/` and `RUN/generations/video/{raw,raw/additional,qc,master,cutdown,shorts}/` |
| Edit working files | `RUN/work/edit/SECTION_OR_CHUNK/` |
| Delivery truth | `RUN/package/final-delivery/manifest.yaml` |

Capacity and cleanup rules are:

- originals are immutable and stored once;
- selected derivatives receive their own paths and hashes, while whole sheets
  remain navigation evidence;
- review HTML, contact sheets, and thumbnails point to the owner and do not
  receive copied originals;
- a rebuildable proxy or sheet keeps one current projection with source hashes
  and build settings rather than an accumulating version archive;
- no new persistent Workbench cache location becomes canonical merely for UI
  convenience;
- temporary roughs and unselected caches remain noncanonical and are reviewed
  through the existing cleanup lifecycle rather than deleted automatically;
- member visuals are title-local and member-organized, never scattered into
  run review folders as new identity owners;
- video raw, additional raw, QC, master, cutdown, short-form, edit work, and
  delivery remain separate lifecycle zones.

CF assets remain under `cf/runs/**` and the CF-owned layout. This table does not
authorize an IDOL path to store CF truth.

## 9. Remaining Improvements Only

All already-active rules above are excluded from implementation scope. Six
material deltas remain.

### R1. Automatic PRE-00 selection handoff

After the Founder selects one PRE-00 target connection, create one hash-bound
handoff that:

- opens the direct Song Room context;
- starts the CDD's asynchronous visual-preparation context;
- carries the selected target, audience promise, reference previews, must/avoid,
  and Founder response without re-asking for them;
- does not create a new stage or grant paid generation.

### R2. One-session FP Final and 02A review orchestration

Allow provisional 01/02A material to be prepared while FP is converging, then
present it in one active review cycle with a hard internal order: FP Final first,
eligible 02A scope second. A failed FP scope cannot expose itself as approved
02A truth.

### R3. Founder drag plus instruction to canonical patch

Connect an IDOL section move/reorder and exact natural-language instruction to
the existing `founder_direct_update`, smallest-owner patch, affected-scope
invalidation, board re-render, and Workbench reload path. Add conflict handling
for stale external-file changes and preserve the last passed rollback pair.

### R4. IDOL post-02A projection, with CF boundary correction

Add read/projection adapters for IDOL 01, 02A, 02B, generated review, 03V, and
04 status without giving the Workbench stage-writing authority. Show generated
Branch results by canonical pointer and hash under the owning section.

Before promotion, remove cross-lane CF examples from the IDOL card contract.
Any later CF integration is a separate CF-owned adapter project and is not part
of this IDOL adapter patch.

### R5. Review-board continuity and scanability

Extend the stable board projection and Workbench integration so accumulated
references and generated outputs cannot be missed. Preserve the present visual
style while adding:

- revision-aware `new since last review` intake;
- asset-level target, role, disposition/review state, and supersession lineage;
- identical Workbench/HTML revision and card projection;
- adaptive Face / Style comparison allocation;
- decision-sized default card copy with full details on demand;
- visible state filters and badges;
- lane-specific role groups with counts and collapse controls;
- on-demand loading for older collapsed cycles.

### R6. Production acceptance

Complete the existing acceptance work:

- one real Founder-selected song pilot comparing clarity and speed with the old
  multi-window method;
- one real Grok I2I job from a selected canonical parent;
- one real Sequence Rail contact sheet and visual inspection;
- external-file-change reload/merge behavior;
- transactional initial plan-and-canvas creation;
- 150-card and 500-card board pan/zoom, proxy, and M1 memory-pressure tests.

Do not widen fan-out or package a broader runtime merely because a small demo
passes.

For the 2026-08-04 implementation closeout, the Founder explicitly selected a
dummy acceptance run and prohibited touching SU. That run may close the local
mechanical implementation and permit a scoped commit when every dummy,
contract, registry, UI, and drift test passes. It does not replace the later
real-song, real-generation, or real contact-sheet creative acceptance evidence,
and it must not be cited as production-output quality proof.

## 10. Implementation Order

When the Founder authorizes implementation, use this order:

1. Correct the IDOL/CF wording boundary before adding new fields or adapters.
2. Add the PRE-00 selection handoff in the existing graph-engineering owner.
3. Define the IDOL-only source projection needed for the combined FP/02A review
   and drag-plus-instruction route.
4. Patch the canonical decision/intervention path and affected-scope
   invalidation before changing the UI.
5. Make Workbench and stable HTML consume the same IDOL projection.
6. Add the board asset register, revision mismatch hold, status/role filters,
   compact disclosures, and adaptive member comparison layout while preserving
   the existing style tokens and card language.
7. Add post-02A pointer/status adapters and scoped refresh without media copies.
8. Run the real-song, real-image, contact-sheet, reload/transaction, and
   large-board acceptance checks.
9. Update every affected policy, schema, skill, validator, surface revision,
   SHA-256, and owning contract-version registry in the same reviewed patch.

CF is not included in that IDOL implementation patch. If the Founder later
requests CF Workbench support, scope and validate it separately under `cf/`.

## 11. Acceptance Criteria

The improvement is complete only when all of the following are true:

- the canonical IDOL stage order remains unchanged and 01R still closes inside
  Front Planning before FP Final;
- automatic PRE-00 selection opens Song Room and visual preparation without a
  duplicate Founder brief;
- the Founder can focus on direct song conversation while visual research
  proceeds asynchronously;
- FP and exact 02A may be reviewed in one session but remain two ordered logical
  decisions;
- every IDOL reference tile reveals whether it is an original-source preview,
  navigation sheet, selected still/crop, or bounded sequence;
- Workbench and HTML display the same IDOL `SCREEN`, `MAIN`, `SUPPORT`, and
  `KEY IMAGE` content, board revision, active cycle, media state, grouping, and
  order from one source projection;
- every new reference or generated image appears in `new since last review`
  until it receives a target and explicit lane-owned state;
- rejected, held, and superseded media remain findable through collapsed groups
  and are never visually or physically discarded merely to shorten the board;
- Face / Style Identity is comparison-sized on desktop and no longer forced
  into a fixed narrow vertical stack;
- images, a compact screen consequence, the review question, and decision
  controls dominate the default Core-Cut view, while full direction and proof
  remain accessible through labelled disclosures;
- role and disposition are both visible and filterable, without treating them
  as the same property or normalizing IDOL and CF semantics;
- the current dark palette, typography, card language, full-frame containment,
  and overall visual character remain intact;
- a Founder section move plus exact instruction updates the smallest canonical
  owner and only affected downstream scopes;
- a generated 02B image appears under its section by pointer/hash without a
  second original copy;
- member visuals are used only for meaningfully visible members and never force
  frontal composition;
- Grok and Luna stay within active owner and concurrency ceilings;
- temporary media, member assets, generated images, video, edit work, review
  projections, and final delivery remain in their fixed lifecycle locations;
- IDOL fixtures contain no CF stage fields, and CF fixtures do not consume IDOL
  FP/01/02A/02B truth;
- the real-song and large-board acceptance checks pass before the Workbench is
  called a production-complete Overall Director room.

## Change Log

### 2026-08-05 connector correction

- Added the missing native sole-writer transaction for direct Founder updates;
  the Overall session is read-only and returns only the five required checks.
- Added the stable owner index that deterministically compiles the projection
  source set and synchronizes only the same run's automation pending view in
  `current-next`.
- Bound the exact PRE-00 selection handoff into the first Workbench director
  context after read-only validation against the current selected radar.
- Kept the managed review board under continuous refresh monitoring after a
  direct update instead of reopening an unmonitored window.
- Re-ran the non-SU dummy success and rollback paths. This closes local
  connector integrity only; it does not claim real output quality or external
  provider acceptance.

### 2026-08-04 implementation closeout

- Connected the stable board to the owner-backed projection assembler and
  current-next pending index.
- Connected the managed Workbench refresh, drift HOLD, idempotent decision
  intake, and affected-owner return route.
- Replaced the duplicate PRE-00 brief with a hash-bound zero-turn handoff.
- Removed the remaining CF production-order wording from the IDOL UI.
- Qualified the local implementation with non-SU dummy evidence while keeping
  real creative-output acceptance as a later production gate.

### v0.3 — 2026-08-04

- Preserved the current review-board style and limited the design change to
  layout allocation, collapsing, filtering, grouping, and continuity.
- Confirmed that stable board revision and superseded-cycle lineage already
  exist, then added the missing asset-level accumulation and `new since last
  review` requirement.
- Added identical Workbench/HTML revision, active-cycle, asset-state, role, and
  order projection with a stale-revision hold.
- Added adaptive Face / Style comparison space without replacing the existing
  left-member/right-reference card language.
- Added image-first, decision-sized Core-Cut copy with full production truth in
  labelled disclosures.
- Added visible used/candidate/held/rejected/superseded/output filters and
  lane-specific reference-role groups.
- Expanded the remaining implementation list from five to six deltas.

### v0.2 — 2026-08-04

- Consolidated the prior collaboration proposal, Workbench audit, active
  graph-engineering baseline, and asset-routing decisions.
- Removed already-active rules from the implementation backlog.
- Replaced the proposed PRE-00 Direction Seed with a direct handoff from the
  already-automatic PRE-00 selection packet.
- Kept direct Founder Song Room conversation while moving visual preparation to
  an asynchronous reviewed lane.
- Kept FP Final as a logical lock and allowed FP/02A to share one ordered review
  cycle.
- Defined Major Scene, Key Screen Sequence, selected reference unit, Core Cut,
  and Branch Cut in production order.
- Preserved IDOL-only identical Workbench/HTML cards and pointer-only post-02A
  image projection.
- Rejected a common IDOL/CF MAIN/SUPPORT cardinality or authority contract and
  required separate CF semantics and adapters.
- Reduced the remaining implementation scope to five concrete deltas and their
  acceptance criteria.
