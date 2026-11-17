#!/usr/bin/env python3
"""Structural-only verify for Front Planning Founder visual review boards.

Does not check song story, member packages, or IP content — only the universal
shell contract markers and page order. The verifier auto-detects either the
managed hand-authored shell or the active generated v12 projection.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_MARKERS = [
    'id="global-spine"',
    'id="summary"',
    'id="member-index"',
    'id="core-cut-board"',
    "core-visual-layout",
    "member-visual-rail",
    "media-carousel",
    "core-reference-grid",
    "data-carousel",
    "data-carousel-track",
    "data-carousel-prev",
    "data-carousel-next",
    "media-index",
    "scroll-snap-type:x",
    "branch-cut-extension",
    "zoomable",
    'id="lb"',
    "object-fit:contain",
    "--member-rail:clamp(280px,28vw,420px)",
    "--visible-slots",
    "--font-sans",
    "--font-mono",
    "scroll-margin-top",
]

GENERATED_V12_MARKERS = [
    '<meta name="idol-generator" content="idol_html_review_board.v12">',
    '<meta name="idol-review-board-visual-profile" content="idol-dark-core-readable-v2">',
    "creative-spine",
    "review-cycle",
    "review-card",
    "core-visual-layout",
    "member-visual-rail",
    "core-reference-grid",
    "media-carousel",
    "data-carousel",
    "data-carousel-track",
    "data-carousel-prev",
    "data-carousel-next",
    "media-index",
    "branch-cut-extension",
    "zoomable",
    'id="lb"',
    "object-fit:contain",
    "--member-rail:clamp(280px,28vw,420px)",
    "--visible-slots",
    "--font-sans",
    "--font-mono",
    "scroll-margin-top",
    "refreshCarousels",
    "t === img",
    "data-review-choice",
    "input.value.split(/[\\n,]+/)",
]

# Tokens that must not appear in the *managed shell* files (structure pollution).
SHELL_FORBIDDEN = re.compile(
    r"\bONE MOVE\b|\b0715_ONE_MOVE\b|\bCHOOM\b|\breze\b|\bjinx\b|\bmaki\b|"
    r"\bkonan\b|\bjjk\b|\bPrecision under pressure\b|"
    r"crouch_stone|eightysix_t",
    re.I,
)



def check_no_cover_crop(html: str) -> list[str]:
    """Visual-reference boards must not use object-fit:cover on media CSS."""
    errors: list[str] = []
    # Strip comments so ban prose does not false-positive.
    stripped = re.sub(r"/\*.*?\*/", " ", html, flags=re.S)
    stripped = re.sub(r"<!--.*?-->", " ", stripped, flags=re.S)
    covers = re.findall(r"object-fit\s*:\s*cover\b", stripped, flags=re.I)
    if covers:
        errors.append(
            f"object-fit:cover found {len(covers)} time(s); use contain for visual/styling/character refs"
        )
    if "<img" in html.lower():
        compact = stripped.replace(" ", "")
        if "object-fit:contain" not in compact:
            errors.append("missing object-fit:contain for image boards")
    return errors

def check_generated_v12_board(html: str) -> list[str]:
    errors: list[str] = []
    compact = html.replace(" ", "")
    for marker in GENERATED_V12_MARKERS:
        if marker not in html and marker.replace(" ", "") not in compact:
            errors.append(f"missing generated-v12 marker {marker}")
    errors.extend(check_no_cover_crop(html))
    return errors


def check_managed_shell_board(html: str) -> list[str]:
    errors: list[str] = []
    for m in REQUIRED_MARKERS:
        if m not in html and m.replace(" ", "") not in html.replace(" ", ""):
            if m == "object-fit:contain" and "object-fit: contain" in html:
                continue
            errors.append(f"missing marker {m}")

    if 'id="song-structure-timeline"' not in html and 'class="timeline"' not in html:
        errors.append("missing song-structure-timeline or .timeline")

    gs = html.find('id="global-spine"')
    sm = html.find('id="summary"')
    mi = html.find('id="member-index"')
    cc = html.find('id="core-cut-board"')
    if min(gs, sm, mi, cc) < 0:
        errors.append("missing global-spine/summary/member-index/core-cut-board anchors")
    elif not (gs < sm < mi < cc):
        errors.append(
            f"order must be global-spine < summary < member-index < core-cut-board; "
            f"gs={gs} sm={sm} mi={mi} cc={cc}"
        )

    if html.count("zoomable") < 1:
        errors.append("missing zoomable media wiring")
    if "lb.classList" not in html and "classList.add('open')" not in html and "classList.add(\"open\")" not in html:
        # external script ok if script src points to lightbox
        if "board-lightbox" not in html and "lb-img" not in html:
            errors.append("lightbox wiring missing")
    if "t === img" not in html and "target === image" not in html:
        errors.append("enlarged-image second-click close wiring missing")
    if "refreshCarousels" not in html:
        errors.append("carousel overflow control wiring missing")

    errors.extend(check_no_cover_crop(html))
    return errors


def check_board(html: str) -> list[str]:
    if '<meta name="idol-generator" content="idol_html_review_board.v12">' in html:
        return check_generated_v12_board(html)
    return check_managed_shell_board(html)


def check_shell_clean(path: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    hits = SHELL_FORBIDDEN.findall(text)
    # allow word fragments only if real package names
    bad = [h for h in hits if h]
    if bad:
        errors.append(f"{path.name}: shell polluted with run-specific tokens {sorted(set(bad))}")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("html", type=Path, nargs="?", help="Managed-shell or generated-v12 run board HTML to verify")
    ap.add_argument(
        "--check-shell",
        action="store_true",
        help="Verify managed shell files have no run-specific tokens",
    )
    args = ap.parse_args()
    errors: list[str] = []
    here = Path(__file__).resolve().parent

    if args.check_shell:
        for name in ("board-shell.css", "board-shell.html", "board-lightbox.js", "README.md"):
            p = here / name
            if p.exists():
                errors.extend(check_shell_clean(p))
        # contract one level up
        contract = here.parent / "founder-visual-review-board-contract.md"
        if contract.exists():
            t = contract.read_text(encoding="utf-8")
            # contract may mention path patterns but not package IP
            for pat, label in [
                (r"\bONE MOVE\b", "ONE MOVE"),
                (r"\b0715_ONE_MOVE\b", "0715_ONE_MOVE"),
                (r"\bCHOOM\b", "CHOOM"),
                (r"\breze\b", "reze"),
                (r"crouch_stone", "crouch_stone"),
            ]:
                if re.search(pat, t, re.I):
                    errors.append(f"contract polluted: {label}")
        shell_html = (here / "board-shell.html").read_text(encoding="utf-8")
        shell_css = (here / "board-shell.css").read_text(encoding="utf-8")
        shell_js = (here / "board-lightbox.js").read_text(encoding="utf-8")
        errors.extend(check_board(shell_html + "\n<style>" + shell_css + "</style>\n<script>" + shell_js + "</script>"))

    if args.html:
        if not args.html.exists():
            print(f"FAIL: missing {args.html}")
            return 1
        errors.extend(check_board(args.html.read_text(encoding="utf-8")))

    if not args.html and not args.check_shell:
        ap.print_help()
        return 2

    if errors:
        print("FAIL")
        for e in errors:
            print(" -", e)
        return 1
    print("PASS: structure/shell OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
