# Founder Visual Review Board — managed shell

This folder owns the **structure and presentation shell only**.

| File | Role |
| --- | --- |
| `board-shell.css` | **CSS source of truth** — preserve and edit here |
| `board-shell.html` | Structure skeleton + required ids/classes (no run content) |
| `board-lightbox.js` | Shared carousel controls, indexing state, click-to-enlarge, and click-again-to-close behavior |
| `examples/su-member-visual-reference-connection-board-v1.html` | Sanitized member/styling presentation example with disconnected `INPUT_IMG_XX` slots |
| `../founder-visual-review-board-contract.md` | Policy contract |
| `verify_board_structure.py` | Auto-detecting structural check for the managed shell or generated v12 projection |

## Rules

### Visual-reference no-crop (mandatory)

- All styling / character / scene / outfit reference images use
  **`object-fit: contain`** (full frame visible).
- **`object-fit: cover` is banned** on those panels — it crops shoes, hems,
  hands, hair, and board edges and destabilizes visual locks.
- Prefer `height: auto` + `max-height` + dark letterbox background over fixed
  boxes that force cover.
- Run boards that show visual references must pass the no-crop check in
  `verify_board_structure.py` when applicable.


1. **Structure is universal.** Do not put track titles, member package names,
   IP refs, or section story beats into the shell files.
2. **Run boards carry content.** Stamp or render the active projection at
   `runs/ALBUM_KEY/TITLE_KEY/RUN_ID/review/founder-workbench.html`. Add new
   review cycles to that file; do not create member/styling/stage siblings.
3. **CSS is managed.** When layout/sizing changes, edit `board-shell.css` first,
   then re-stamp or re-embed into active run boards that must stay in sync.
4. **file:// opening:** embed the current `board-shell.css` into a `<style>`
   block and inline or embed `board-lightbox.js` so the Founder can open the
   run HTML without resolving skill-relative links. The skill folder remains
   the edit source; the run file may hold a stamped copy.
5. **Verify structure**, not song story. The verifier checks the legacy managed-shell anchors only on that profile and checks renderer/meta/card/decision markers on an `idol_html_review_board.v12` projection. Do not require shell-only ids on generated v12 HTML.
6. **Keep skill examples media-free.** Use coded `INPUT_IMG_XX` placeholders
   with no real file or URL. Bind actual paths and SHA-256 only in a run-owned
   manifest and its rendered `founder-workbench.html`.
7. **Image count is open-ended.** Continue slot ids after the example's highest
   number (`INPUT_IMG_40`, `INPUT_IMG_41`, and so on). Four controls only the
   desktop visible count; it is never a total-image limit.

## Stamp checklist

- [ ] Page order: global-spine → member index → core/event cards → 02A children
- [ ] Required ids present
- [ ] CSS matches managed shell (or documented intentional delta)
- [ ] All images use `.zoomable` + lightbox
- [ ] Desktop Core-Cut row uses an adaptive member block (`~280px` practical minimum, bounded proportional width) + fluid refs
- [ ] Primary face/style compare side by side when space permits; extra styling stays in one horizontal strip
- [ ] Every media group shows automatic `01 / N` indexing in declared order
- [ ] The right reference row shows at most four desktop slots; overflow uses left/right controls and horizontal scroll instead of wrapping
- [ ] Slot numbering may continue past the example count; there is no total image cap
- [ ] Every image is `contain`; click enlarges, and clicking the enlarged image again closes it
- [ ] `--font-sans`, `--font-mono`, sticky offset, and `900px` breakpoint match
- [ ] Pre-02A `CCxx` anchors are presentation ids, not official Core-Cut ids
- [ ] One pointer-only asset register drives NEW/state/role/supersession groups; no media copy is created for review
- [ ] Workbench and HTML manifest revision, active cycle, and asset counts match or show a stale-review HOLD
- [ ] Stable workbench shows Direction Alignment first, preserves internal FP Close as exact lineage, and presents that storyline plus 01/02A at 02A Final Planning
- [ ] Direction Alignment includes a separate readable Pinterest cohort for every active visual section
- [ ] 02A Final Planning PASS unlocks only the exact affected 02B scope; paid generation remains separate
- [ ] Post-02A IDOL rows carry a typed source stage and canonical path/SHA pointer
- [ ] No invented refs; paths resolve under the run or `assets/**`
