# IDOL Repository Media And Security Policy

Status: canonical conditional policy
Owner: `AGENTS.md`
Activation: local audio/video runtime, downloads, browser/source capture,
secrets/config presence checks, 02B API reference inputs, or external media tools
Load rule: read this file completely when activated

The non-overridable secret rule remains summarized in `AGENTS.md`. This file
contains the complete operational contract for the activated media/API route.

## IDOL Repository Work Protocol (Applies to All Work in This Repo)

This protocol applies to **any and all work** performed inside this IDOL repository, regardless of whether it is graph-engineering-related, creative, technical, research, or automation work. It is not limited to one provider surface.

### Audio/Video Runtime Rule

For local audio analysis, video source intake, motion analysis, sync workbench,
QC contact sheets, or other Python-driven media work, do not use bare
`python3`. Use the repo launcher:

```bash
scripts/idol-video-python scripts/<media_script>.py [args...]
```

The launcher pins the interpreter to `.venv-video/bin/python`, exposes
`/opt/homebrew/bin` and `/usr/local/bin` for `ffmpeg`/`ffprobe`, and provides
`scripts/idol-video-python --check` for session diagnostics. If it reports a
missing dependency or tool, stop and report that environment problem instead of
installing packages into a random system Python.
If system `python3` has been upgraded, do not treat that interpreter as the
IDOL media runtime until `.venv-video` has been deliberately rebuilt and
`scripts/idol-video-python --check` passes.

### Mandatory Starting Ritual
For work that activates this media/security module, use the repository starting
ritual without widening it:

1. Read `AGENTS.md`, especially the Operating Model and security/approval gates.
2. Read `wiki/production-system.md` as the lightweight router.
3. Read `wiki/INDEX.md`, then this activated module, the owner skill/schema,
   and current run sources.
4. Grok reads `handoff/grok/current.md` only when the task explicitly resumes
   an existing cross-surface handoff. A Grok-owned graph-engineering run resolves its run
   and frontier from the Founder request and canonical local state.

Do not require a Grok handoff for ordinary registered Cursor work or independent Grok
graph-engineering ownership.

### Security and Sensitive Information Rule (Non-Overridable)

Even when the user has enabled "always approve", yolo mode, full permissions, or any other permissive execution setting, the following strict rules apply without exception:

- Commands that would **dump or print** actual secret values (e.g. `cat .env`, `printenv`, `env`, `echo $SECRET_VAR`, etc.) are **always blocked**.
- When legitimate inspection of configuration or environment-related files is necessary for the task, reading is allowed **only if** the agent can guarantee it will **never output or expose the actual secret values** in any response, reasoning, or visible output. Real values must be redacted (e.g., described as structure only or replaced with `[REDACTED]`).
- Any action involving secrets, tokens, credentials, .env files, or private runtime data still requires explicit founder approval on a case-by-case basis if there is any risk of exposure.
- This policy does not itself grant network authority. Public web search or
  webpage fetch may run only when the higher-level instructions and the current
  task/session approval allow that exact route.
- Any other external network use, Drive, GitHub, repo-external connectors, logged-in/session/cookie-based browser access, paid APIs, external writes, uploads, downloads, or platform sync still requires specific founder approval for that task.

The current Founder grant in `AGENTS.md` and the shared root's **Approved
Project Data For Selected Model Services** already supplies specific approval
for reading and transmitting necessary current-project code, documents,
schemas, images, video, audio, and analysis to the selected Grok Build CLI and
Cursor model services. Same-purpose, same-project additions, retries, and
independent reviews require no renewed consent. Keep current input paths and
hashes as execution evidence without turning them into a per-file approval
gate. This grant excludes secrets, credentials, personal data, excluded
employer and unrelated project material, publishing, deployment, deletion,
and permission changes; it does not select or widen a paid generation job.

Cursor and Grok Build/TUI/CLI share this same scoped approval model. Grok hooks
must not impose a permanent surface-specific denial after the exact current
task has received the required Founder approval; the native permission layer
and the route's own preflight/approval contract remain authoritative. Hooks
must still fail closed when a command would print, interpolate, transmit on the
command line, or otherwise expose a credential. Approved authenticated work
uses a registered repository runner that loads the credential internally; raw
authenticated `curl`, inline `Authorization` headers, inline API-key values,
and secret inspection remain forbidden.

These boundaries are **never waived** by permission modes. They take precedence over convenience. Violating the "do not expose actual values" principle is treated as a serious breach of protocol.

### Project-Confined Grok CLI Runtime

An IDOL Grok process starts with this repository as its resolved working root,
`--no-auto-update`, and the tracked `idol-repo` sandbox in
`.grok/sandbox.toml`. That profile extends `workspace`, not `strict`, so
Overall Director Grok can read host tools and write the whole IDOL tree,
including from nested cwd. Do not redefine `idol-repo` in
`~/.grok/sandbox.toml`. The tracked `.grok/sandbox.toml` declares the IDOL write
root, read-only `.git`, network restriction, and listed secret-file denials.
The tracked `.grok/config.toml` adds its enumerated read/edit/shell permission
rules and child-environment filtering. Actual execution must apply both;
source declarations alone do not prove effective read/write/network isolation,
and these Grok files do not govern Cursor My Machines. A missing or unapplied
project sandbox is a HOLD, not permission to fall back to the CLI default.

Workbench may expose structured ACP or an explicit raw TUI, but both bind the
same exact run-route assignment, model, effort, provider-source SHA-256,
readiness state, and repository root. The xAI credential may be inherited only
by the exact approved Grok host process from an already approved runtime secret
lane; it is never copied into a run artifact, receipt, UI field, command line,
log, child shell, or generated file. Raw terminal text is conversational
evidence only. It cannot enter a Founder briefing, Director review, canonical
artifact, or generation request until the normal hash-bound return and review
route admits an exact file under the active run.

That Grok-host inheritance rule does not authorize the separate direct xAI API
media lane. A registered repository xAI API executor may load `XAI_API_KEY`
internally from its process environment or the ignored `.env.xai.local` file
only after it has revalidated the exact current-job Founder external/paid
authority, request, provider-registry snapshot, provider-owned profile source
SHA-256, model, API version, credential-free HTTPS origin, endpoint, request and
response contracts, operation, count, spend envelope, and expected output. The
lane stays default-disabled and activation-HOLDs before credential access when
any registration byte is absent, stale, or mismatched. It never passes the
credential to a child process, prints, logs, hashes, or writes it, follows a
redirect, or falls back to Grok subscription, OpenAI, another xAI profile, model,
endpoint, auth lane, or transport. Loading the credential does not itself grant
network or paid-generation authority; both remain separately Founder-gated for
the exact job.

### `yt-dlp` Source Safety Rule

`yt-dlp` is not a free-form downloader in this repository. Use only a registered
platform entry, and only for public sources on that platform. Active registered
capture routes are:

- public Bilibili via `scripts/yt-dlp-bilibili.sh` (default discovery lane)
- public Instagram posts/Reels/IGTV via `scripts/yt-dlp-instagram-reference.sh`
- public YouTube / YouTube Shorts via `scripts/yt-dlp-youtube-reference.sh`
  when the Founder separately and explicitly names YouTube for the current task

Instagram is an allowed registered reference-capture route. It is not banned.
Prefer the Instagram entry when the current task needs a public Instagram post,
Reel, or IGTV URL. Keep Instagram capture public/no-account and cookie-free
unless a later Founder-approved cookie route is separately registered.

TikTok and Instagram Reels trend reporting remains a separate public-web
observation route. The weekly/monthly short-form reports may store public URLs,
source identity, literal observations, evidence status, lifecycle phase, and
response-proxy limits. That observation lane may not use logged-in or
personalized For You/Explore feeds, cookies, private pages, account/session
state, bulk screenshots, bulk media capture, copied audio/video, uploads,
publishing, or platform sync. Named single-URL Instagram reference capture
through the registered Instagram wrapper is allowed outside that bulk
observation lane when the current-task capture approval binds the exact public
URL. If a trend claim cannot be verified through a public no-account source,
hold or downgrade the claim rather than accessing a private surface.

Before any `yt-dlp` extraction, check whether the original source video, local
download, contact sheet, dense observation note, or run/reference-library
pointer already exists. Prefer existing source notes and contact sheets over
new downloads. Use the network-free `scripts/idol_reference_hub.py preflight`
for this check; do not substitute a broad filesystem search or title-only guess.
Every permitted new `yt-dlp` original belongs under the one run-external
`source-materials/video-sources/{platform}/by-source/SOURCE_ID/` owner with its
source manifest and reusable broad contact-sheet/frame-index evidence.
Run/catalog/reference-library surfaces may point to that owner but may not
become a second canonical media store. If the source is registered but its local
bytes or evidence are missing/stale, hold for explicit recovery; do not silently
redownload it. When a new public Bilibili source is still needed, inspect
metadata first. Duration must be known and no video over 270 seconds (4 minutes
30 seconds) may be downloaded; this is a hard ceiling and cannot be bypassed by
the heavy-source approval flag. Playlists/collections, live/compilation uploads,
still require narrow Founder approval before full download. Estimated file size
alone is not a capture hold when duration and format edge bounds already pass
(Founder lift 2026-08-11 of the prior 250 MB soft size hold). Search at-or-below-60-second sources through a shorts/short-form
lane and above-60-through-270-second sources through an MV/music/original-content
lane. Every query must bind the selected-song target/message, a supplied
reference or reference-function anchor, and a named screen gap. After relevance
and diversity gates pass, prefer higher raw public view count without upload-age
normalization. Popularity never overrides fit or anti-repetition checks.
The wrapper must persist the hash-bound metadata file, verified duration,
duration lane, and raw view count when available into the canonical source
manifest and pointer catalog. Console output alone is not discovery evidence;
01R records the exact query, relevance/diversity gates, and post-gate rank in
its run-owned capture row.
Before capture, establish content identity and context. Use NamuWiki,
Wikipedia, or an equivalent encyclopedic page only as a discovery map; verify
important title, character, scene, and event meaning against the original or an
official source. Ordinary discovery and capture admit only an official/original
professional primary source whose identity, rights holder or verified creator,
scene/segment context, and selection reason are unambiguous enough to reject a
wrong download. AMV, MAD, fan edit, fan trailer, and unofficial music edit are
closed unless the Founder has approved the exact current-task source identity or
URL, purpose, and allowed action. Without that permission, do not query, open,
download, capture, play, inspect, analyze, register, cite, candidate, or bind the
edit; skip an incidental result and continue through official/original sources.
A supplied link or file is not permission, and approval to observe edit rhythm
does not authorize direct scene binding. Missing required permission is
`founder_permission_missing` HOLD. Raw view count is a post-relevance response
signal for an otherwise eligible source, never proof of target fit or
directorial quality by itself.
The registered Bilibili wrapper must fail closed before metadata or media
network access unless the caller supplies an explicit current-task approval
flag, a non-empty approval basis, and an exact matching approved URL. It must
not synthesize a generic approval basis or treat capture eligibility as
approval. Network-free lookup/preflight and reuse of already registered local
evidence remain allowed without those capture bindings.

Do not use bare `yt-dlp` or invent an unregistered platform wrapper. Private
pages, login-bound pages, and account/session-based sources remain closed unless
a separately registered cookie/session route and exact Founder approval exist.
YouTube remains especially sensitive because automated extraction may create
account or access risk. Do not search or extract YouTube as an automatic
fallback after Bilibili or Instagram. Only a separate, explicit Founder
instruction naming YouTube for the current task activates public YouTube
official/original research after the context gate above. Then use only the
registered `scripts/yt-dlp-youtube-reference.sh` route with no cookies or
account/session state. The wrapper additionally requires
`IDOL_YOUTUBE_EXPLICIT_FOUNDER_INSTRUCTION=1` and a non-empty
`IDOL_YOUTUBE_FOUNDER_INSTRUCTION_BASIS` before hub preflight. Generic public
research permission, a failed Bilibili or Instagram search, or prior YouTube
permission does not activate it. Keep the permission narrow to the named task
and use the minimum needed format or metadata; it is not standing permission for
future work. YouTube permission alone never activates an AMV, MAD, or fan edit;
that source class still needs its own exact source/purpose/action approval and
any direct-use lock. Every actual call still binds its selected exact URL,
resolved title, platform identity, and task basis.

Instagram public post/Reel/IGTV capture uses only
`scripts/yt-dlp-instagram-reference.sh`, binds the exact approved URL, and
shares the hub's current-task approval, 270-second ceiling, canonical
`instagram/by-source/{shortcode}` owner, contact-sheet, and hash registration
rules. TikTok, X, streaming-service, and any other non-registered platform
remain prohibited until a separately registered platform wrapper and exact
Founder approval exist. The absence of a registered wrapper is a hold rather
than permission to improvise one. A preserved historical local YouTube or
Instagram byte may be indexed as `historical_existing_only` with
`future_network_permission: false`; its existence is not approval for a new
network request.

### 02B Current-Title Visual Input Allowlist

The current v12 Production-Cut request is the only new-run image execution
envelope. Historical Branch-only request versions remain evidence/readers and
cannot be selected for new execution.

This subsection governs repository-constructed external image payloads. Every
surface consumes the same approved provider-neutral Cut packet, exact prompt
hash, ordered local attachments, one expected output path, and immutable
run-selected provider/auth/capability snapshot. If the Founder omits the image
provider, the exact current physical assignment uses only its own registered
native surface. The target default is the current Grok CLI Section owner:
Grok Build subscription uses the registered `grok_image` adapter and selects
native `image_edit` when attachments are present or `image_gen` when none are
present. Legacy Codex `imagegen` is not an active ordinary lane.
Slash-command and legacy `grok_image_manual` routes are invalid. Optional
Cursor Luna image stays off unless the Founder names it as a substitute and is never selected by omission. OpenAI API execution must use
`gpt-image-2` and requires explicit Founder selection. Founder-approved xAI API is a separate
parallel lane and opens only from the exact registered provider-owned profile
and matching current-job Founder authority described above. Subscription,
Cursor Luna, OpenAI API, and xAI API never silently replace or fall back to one
another. A tool name, auth lane, runtime event, model, or capability receipt is
valid only for its owning provider and exact current session; absence or drift
is a HOLD before execution.

Face-only is the sole approved facial-identity source for a member-visual build
and any registered identity-input request. `no-mic`/`no_mic` variants are
retired: a validator must reject them rather than selecting a sibling or
silently rewriting the path. After the current-title card passes, the active
02B request carries that card and has no separate downstream face-only lane.

The historical `scripts/idol_02b_batch_api_runner.py` is not an active Batch
adapter and must fail before preparation or external access. An active executor
must consume only the current provider-conditional request, revalidate the exact
Founder generation authority, provider/auth snapshot, attachment order, prompt
bytes, count, and expected output immediately before execution, and write the
actual output path/SHA/pixel-state receipt. Legacy board/keyframe manifests are
not compatibility inputs.

Founder approval for the current paid image job may authorize only the exact
files declared in one validated section execution package. The root 02B index
or all-song aggregate is never a submit surface. The active route has no
separate face-only or identity-reference input lane.

- Member visuals, album visual identity, and section background/space/object
  inputs must all live under the current title's declared
  `assets/members/album-assets/ALBUM_KEY/TITLE_KEY/**` package or another exact
  current-title path explicitly declared by that package. INK is an
  organization/depth example only; no INK pixels, clothing, hair, makeup,
  objects, or spaces may enter another title.
- A current-title member visual may attach only when that member is meaningfully
  visible. It controls appearance, hair, makeup, wardrobe, material,
  silhouette, and body continuity. It never requires a visible/readable face,
  frontal head, frontal gaze, pose, crop, still-camera geometry, or proportion.
- A back view or silhouette may retain the member visual for appearance
  continuity. A world-, object-, environment-, or system-only Cut must not
  attach a member visual.
- Front Planning does not create a title-global independently promoted
  background/world asset lane. A Cut-scoped `scene_visual_package` may bind a
  separately reviewed `world_look_binding` and still `composition_anchor`, then
  compile the compatible pair together. Major/Key Screen text and selected
  sequence frames/crops or Founder-supplied scene images carry that space and
  scene grammar when the owning FP/01/02A stage binds them to the Cut.
- A sequence sheet is navigation and ordered-flow evidence, not one image input.
  Every selected cell or crop must be materialized as its own path and SHA-256
  and preserve the chosen action, staging, still-camera geometry, placement,
  crop, and ordered sequence role.
- Every attachment must carry its active role, actual path, SHA-256, Section/
  Major/Core/Branch binding, pixel-inspection status, and current-job
  approval. The request preserves one combined attachment order exactly as
  accepted in 02A and 02B.
- Generated review sheets, unrelated moodboards, unselected research images,
  and another title's asset package remain prohibited.
- If the selected surface cannot accept every candidate attachment within its
  limits, the owning CDD may choose the smallest governing set that still
  covers every required role and carry non-governing observable consequences in
  authored prompt prose. If no such set exists, hold the packet. A compiler or
  worker may not silently drop an image, replace a mandatory role with prose,
  or let a visual-identity input erase the selected scene action and camera
  grammar.
- This allowlist does not approve secret disclosure, publishing, platform sync,
  Drive/GitHub access, or any connector outside the exact image job.

The post-generation bounded correction route does not widen permission. It
requires the exact approved edit source, live hashes, and current-job Founder
authorization. Never improvise an upload or infer paid approval from a
correction specification. If the host blocks submit, keep the request local and
report the hold.

### 03V Subscription And API Video Boundary

03V authoring uses one hash-bound Motion Storyboard containing one to three
passed Production Cut images of type `official_core` or `branch`. That board is
authoring evidence, not automatic execution authority. Default I2V execution
uses one passed Production Cut with the exact canonical 03V prompt and native
`image_to_video`; multiple-reference `reference_to_video` is legal only when a
current Founder receipt selects the exact ordered images. Pre-03V direct media
shortcuts are forbidden.

Registered Grok subscription or Founder-approved xAI API jobs accept only 6 or
10 seconds and 480p or 720p. A 1080p request, unsupported tool, missing source
hash, or requested/observed resolution mismatch is a HOLD, not a reason to retry
through another provider or quality. CDD reviews the actual 480p test before the
same job id may open a 720p candidate. Output ingest records provider, auth lane,
selected native tool, exact source Cut type/id/path/hash, prompt hash, duration,
requested and observed resolution, watermark observation, output path/SHA-256,
and returns to CDD. A local packet, OAuth availability, allowance, or successful
mock grants no external or paid execution permission.

Additional narrow tooling routes remain eligible only for the explicitly
defined PRE-00 public reference mining case and the 01R public web research
case below, and only when higher-level instructions plus current-task
approval allow them. All other sensitive access requires fresh Founder
approval.

Conditional route: PRE-00 research radar may use public Bilibili reference
mining, and may also use registered public Instagram single-URL capture when the
Founder explicitly asks for broader, faster discovery before song or route lock
and current-session network access is allowed. This route is limited to public
Bilibili pages/search results and public Instagram post/Reel/IGTV URLs through
the registered wrappers, with `yt-dlp` use without login cookies, private
sessions, or account state. It may collect metadata, exposed
subtitles/chapters, low-resolution contact-sheet evidence, short analysis cuts,
or audio/onset facts to preserve literal source observations, timestamps, and
field-ready extraction notes. It must be aligned to the active biweekly trend
pulse and current-run research; it does not replace weekly HTML reporting,
trend-pulse refresh, fashion refresh, founder selection, or reference-song fit.
Raw Bilibili or Instagram media is a temporary observation cache until the
founder selects it. Once founder-selected for the current run, it may be
promoted into run-owned reference records, prompt packets, generation inputs,
edit source candidates, catalog registries, packages, or longer-term reference
storage with source notes and intended use. This promotion rule never overrides
the restricted-edit gate: an AMV, MAD, fan edit, fan trailer, or unofficial
music edit remains held unless the exact current-task source identity/URL,
purpose, and allowed action are Founder-approved, and section/direct use also
has its own explicit lock. A supplied or selected link/file and historical
local bytes do not reactivate that source. PRE-00 still does not approve bare
`yt-dlp`, YouTube without its separate Founder instruction, TikTok, X,
streaming services, private pages, or any account-bound source. Record the
policy in `research_policy.public_reference_mining_policy` when used, and
record `research_vectors`, raw source observations, and `function_extracts`
together when Bilibili or Instagram mining informs a route. Do not discard
specific source detail at the collection stage.

01R MV direction reference mining is an eligible public-web route only after the
higher-level instructions and current task/session approval permit network
access. Historical Founder approval of the research purpose is not a standing
network grant. When allowed, keep it limited to public source observation,
source-use analysis, and current-song MV/choreography/fashion/camera direction
mining. It never approves private connectors, Drive, GitHub, secrets,
browser/session stores, paid generation APIs, publishing, upload, scheduling,
or platform sync.
For public still-image discovery in 01R, use a source-first, gap-based model
for every run and album. Inspect founder-provided boards, run-owned images,
contact sheets, official sources, idol activity reports, fashion/trend reports,
prior generated styling sheets, `catalog/references/reference-catalog.yaml`,
the reusable still-image catalog, and catalog/title visual assets before public
image search. If the exact source is already registered, follow its local
original and complete analysis; missing registered bytes are a HOLD and never
permission for silent recapture. Only search public still-image sources for
named missing visual functions such as space, world/system, material,
object/environment, composition, lighting, camera angle, wardrobe, or
performance gesture. Broad space/world/object still discovery belongs to the
physical image-only World/Still department; generalists may perform only their
Dispatch-named selected-still or residual gap work. Do not lock the search to one platform by
default: let the query decide the public source mix, then use free/publicly
accessible sources such as Pexels, Unsplash, Pixabay, Flickr Creative Commons,
Openverse, Wikimedia Commons, museum/archive collections, official brand or
creator pages, and ordinary web image results when they answer the lane.
For a named visual or member-concept gap, public Pinterest is an eligible
fast-discovery and local-capture surface for fashion/editorial and for
composition, space, object/environment, light/material, gesture, camera angle,
and other named still-reference functions—not fashion-only. When catching or
building **visual identity** (title or member look, styling package, concept
look, hair/makeup/wardrobe/silhouette continuity), public Pinterest is the
**first-priority** discovery and local-capture surface under ordinary
current-task public-network permission; ordinary image search and official or
library stills follow when Pinterest does not fill the named gap. Use two
linked passes. The first `visual_ignition` pass searches the visible situation
and felt quality: subject or body action, attitude or relation, object,
material, space, fashion, composition, and sensory state. Do not force K-pop,
camera measurements, lens terms, or schema vocabulary into this first query.
The second `idol_translation` pass keeps the strongest visual seed and adds the
relevant idol context, such as a concept photo, comeback teaser, beauty
editorial, group styling, or performance wardrobe. When the governing scene or
color grammar source is **2D, anime, illustration, or cel-style** and production
look is **photoreal**, wardrobe/styling discovery must not use those 2D frames
as fabric authority: extract function only, match member attributes (for example
hair class), lock one primary garment noun and any king/title bandana color,
then search photoreal fashion and attribute-matched idol concept stills under
`skills/idol-pinterest-reference-worker/references/2d-source-to-photoreal-wardrobe-method.md`.
Keep a **grammar deck** (place/relation/color temperature) separate from a
**wardrobe deck** (real cloth, materials, bandana); generation attachment order
is face-only, then wardrobe pins, then optional grammar stills for place only.
The World/Still department
tests space, world/system, object/environment, composition, light, and material
across diverse still images. It must not search, open, download, play, sample,
screenshot, or extract video or load video-hub instructions. An already
selected Founder/run-owned still frame may be inspected as an independent image
without reopening its source video. When a current-title appearance card is
missing or a full restyle is explicitly authorized, the CDD passes the selected
styling evidence—including public Pinterest pins already preserved locally—to
the conditional Member Visual Identity task for hair, makeup, wardrobe,
accessories, silhouette, and look-continuity judgment. This is not a separate
standing member/styling research lane.

Every comparative judgment involving two or more World/Still images, including
bounded-worker pruning, CDD Pass A/Pass B, and Founder Discovery, must place every compared
candidate on a deterministic uncropped contact sheet with stable candidate id,
function, section ids, source identity, individual path/hash, sheet path/hash,
and preserved order. CDD compares the sheet and opens individual images for
detail. The sheet is comparison evidence only, counts as zero reference units,
and never replaces selected individual image/crop bindings.

A public Pinterest pin is a first-class still source when selected. The public
pin URL or pin id plus the local image path and SHA-256 may serve as source
identity; a separate non-Pinterest creator, brand, or publication page is not
required. Under ordinary current-task public-network permission, download,
register, fully analyze, and promote selected public pins as governing,
supporting, or section-bound still units. Optional origin or attribution notes
are enrichment only and never force `unresolved_origin` HOLD for a public pin.
Prune weak, near-duplicate, and unreadable candidates before the expensive
pixel read. Keep search-result thumbnails that are not yet a selected pin
temporary until the readable pin image is preserved locally. Private or
logged-in Pinterest boards, cookie/session feeds, and bulk scrape without
current-task permission remain closed. Public still candidates never become
member face identity evidence or automatic generation inputs; face-only remains
the sole facial-identity source, and generation attachment still requires the
current-run disposition route.

Use `scripts/idol_pinterest_public_capture.py` as the common Cursor/Grok CLI
preservation route for a selected public pin. Prefer the readable public image
asset itself through a credential-free HTTPS image URL; this is not a full
desktop screenshot. If the current surface cannot obtain that asset, Cursor or
Grok may save an image-element capture from a public no-account view and pass
that exact file to the helper with `public_no_account_screenshot`. Full-page UI
captures, logged-in boards, cookie/session transfer, and bulk extraction remain
forbidden. The helper requires exact current-task capture authority, preserves
pin URL, method, proposed main/support role, local path/hash and dimensions,
and rejects a still whose short edge is below 720 pixels. Capture and
registration do not select the pin or approve generation.

All registered `yt-dlp` wrappers select and verify a minimum 720-pixel short
edge and a default maximum 1920-pixel long edge. Width and height are both
checked after capture, so portrait and landscape sources use the same rule. A
lower legacy height override is invalid; failure to obtain 720-short-edge bytes
is a HOLD before registration or visual analysis.

When an externally obtained still is selected for durable cross-run reuse,
register its immutable original and provenance once under
`source-materials/image-sources/by-source/SOURCE_ID/`, then point to it from
the central reference catalog. Keep the current-run selected crop, detailed
pixel analysis, exact purpose, preserve/discard rules, and disposition under
`runs/ALBUM_KEY/TITLE_KEY/RUN_ID/research/reference-intake/`. The source
manifest and catalog do not grant `bounded_surface_direct`,
`full_scene_direct`, `sequence_direct`, generation attachment, or Founder PASS.
Founder-supplied direct images may remain run-owned and continue through the
existing direct-image contract without being moved into the reusable hub.

### Graph Source Envelope And Unchanged Capture Permission

Graph Engineering may carry a run-startup source-authority envelope and compact
URL projection. Neither changes this file's capture, download, upload, external
mutation, paid-generation, cookie, private-state, YouTube, unregistered-
platform, or restricted-edit permissions. Exact current-task Founder approval
remains the floor. An envelope that names allowed platforms or official/original
eligibility does not authorize network capture, `yt-dlp`, Pinterest preservation,
browser fetch, or recapture of a missing registered original.

Until this media/security policy itself is changed by Founder-authorized
bytes, the existing exact permission rules above remain higher-priority than
any routing envelope, Decision Set, Role Context Pack, or compact source id.
Compact projection stores a URL once in the Source Intake Manifest and later
passes source id, locator, path, and SHA-256. Capture wrappers still bind the
exact approved URL, current-task approval flag, and approval basis at the
moment of network access. Pointer-only Director capsules do not waive that
binding.

AMV, MAD, fan edit, fan trailer, unofficial music edit, source-unclear
reupload, private or logged-in pages, cookie/session state, bulk scrape, and
unregistered platforms remain closed unless the exact current-task Founder
permission named in this file already exists. This subsection does not add,
delegate, or infer that permission.

### Still, Official, And Registered Video Source Classes

Source-class routing lives in `policies/harness-routing-and-sources.md`. This
file keeps the permission split:

- public Pinterest is a still-image discovery and local-capture class through
  `scripts/idol_pinterest_public_capture.py` under exact current-task public-
  network permission; it is not a motion class, not a facial-identity class,
  and not a `yt-dlp` class;
- official/original professional stills remain eligible still sources under
  the same public/no-account and official/original gates already stated;
- motion, camera-rhythm, and body-transition evidence use official/original
  video through a registered `yt-dlp` wrapper only: Bilibili default,
  Instagram when the exact public URL is approved, YouTube only after a
  separate current-task Founder instruction;
- World/Still workers still must not search, open, download, play, sample,
  screenshot, or extract video.

A Pinterest pin cannot replace mandatory contiguous motion evidence. A
registered video source may later yield a still frame, but that reuse does not
reopen the source video for a still-only worker and does not grant a new
download. Missing registered local bytes remain HOLD, never silent recapture.
