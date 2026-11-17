#!/usr/bin/env python3
"""Contract test: public Pinterest pins use a dedicated section-scoped route.

Reads the active policy/skill surfaces (not copies) and asserts:
- public pins may download/register with pin identity
- visual-identity policy may prefer Pinterest while ordinary reference workers
  do not inherit its named-gap search/capture assignment
- old navigation-only / mandatory non-pin origin bans are gone
- private/logged-in and face-only boundaries remain
- graph-engineering surface registry revision+sha256 match file bytes for those surfaces
"""

from __future__ import annotations

import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SURFACES = [
    ROOT / "policies" / "repository-media-security.md",
    ROOT / "policies" / "harness-routing-and-sources.md",
    ROOT / "skills" / "idol-world-still-reference-department" / "SKILL.md",
    ROOT / "skills" / "idol-pinterest-reference-worker" / "SKILL.md",
    ROOT / "skills" / "idol-pinterest-reference-worker" / "references" / "pinterest-section-comparison-detail.md",
    ROOT / "skills" / "idol-pinterest-reference-worker" / "references" / "2d-source-to-photoreal-wardrobe-method.md",
    ROOT / "skills" / "idol-front-planning-director" / "SKILL.md",
    ROOT / "skills" / "idol-reference-research-department" / "SKILL.md",
    ROOT / "source-materials" / "image-sources" / "README.md",
    ROOT / "schemas" / "reference-working-index.schema.json",
]

REGISTRY = ROOT / "automation" / "harness-surface-version-registry.yaml"

# Old ban prose that must not reappear on active still surfaces.
FORBIDDEN = [
    "Raw pins, reposts, search thumbnails, fan moodboards, and near-duplicates remain",
    "Pinterest, reposts, blogs, search thumbnails, fan moodboards",
    "Pinterest, reposts, blogs, compilation metadata, fan",
    "only visually strong,\nnonrepetitive survivors receive original-source tracing",
]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _registry_row(path: Path) -> tuple[int, str]:
    rel = path.relative_to(ROOT).as_posix()
    text = REGISTRY.read_text(encoding="utf-8")
    pattern = (
        rf"path: {re.escape(rel)}\n"
        rf"(?:    [^\n]+\n)*?"
        rf"    current_revision: (\d+)\n"
        rf"    sha256: ([0-9a-f]+)"
    )
    match = re.search(pattern, text)
    if not match:
        raise AssertionError(f"registry missing surface path {rel}")
    return int(match.group(1)), match.group(2)


class PinterestStillSourcePolicyTest(unittest.TestCase):
    def test_surfaces_exist(self) -> None:
        for path in SURFACES:
            self.assertTrue(path.is_file(), f"missing surface {path}")

    def test_public_pin_is_first_class_and_local_capture_allowed(self) -> None:
        media = (ROOT / "policies" / "repository-media-security.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("first-class still source", media)
        self.assertRegex(
            media,
            r"download,\s*register,\s*fully analyze,\s*and promote selected public pins",
        )
        self.assertIn("never force `unresolved_origin` HOLD for a public pin", media)
        self.assertIn("pin URL or pin id", media)

    def test_visual_identity_first_priority(self) -> None:
        required = [
            ROOT / "policies" / "repository-media-security.md",
            ROOT / "policies" / "harness-routing-and-sources.md",
            ROOT / "skills" / "idol-front-planning-director" / "SKILL.md",
        ]
        for path in required:
            text = path.read_text(encoding="utf-8")
            self.assertTrue(
                "first-priority" in text or "first priority" in text,
                f"{path.relative_to(ROOT)} lacks visual-identity first-priority language",
            )
            self.assertIn("visual identity", text.lower())
        world = (ROOT / "skills" / "idol-world-still-reference-department" / "SKILL.md").read_text(encoding="utf-8")
        generalist = (ROOT / "skills" / "idol-reference-research-department" / "SKILL.md").read_text(encoding="utf-8")
        self.assertRegex(world, r"stable URL/id as a\s+lead")
        self.assertIn("does not own a named-gap Pinterest comparison assignment", generalist)

    def test_multi_function_still_use_not_fashion_only(self) -> None:
        media = (ROOT / "policies" / "repository-media-security.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("composition", media)
        self.assertIn("not fashion-only", media)
        world = (
            ROOT / "skills" / "idol-world-still-reference-department" / "SKILL.md"
        ).read_text(encoding="utf-8")
        self.assertIn("composition", world)
        self.assertIn("background_and_space", world)
        self.assertIn("object_environment_response", world)

    def test_old_navigation_only_bans_removed(self) -> None:
        for path in SURFACES:
            text = path.read_text(encoding="utf-8")
            for needle in FORBIDDEN:
                self.assertNotIn(
                    needle,
                    text,
                    f"{path.relative_to(ROOT)} still contains ban prose",
                )

    def test_hard_boundaries_intact(self) -> None:
        media = (ROOT / "policies" / "repository-media-security.md").read_text(
            encoding="utf-8"
        )
        # Cross-line "Private or\nlogged-in Pinterest"
        self.assertRegex(media, r"Private or\s+logged-in Pinterest")
        self.assertIn("face-only", media)
        self.assertIn("AMV", media)
        self.assertIn("yt-dlp", media)
        pinterest = (
            ROOT / "skills" / "idol-pinterest-reference-worker" / "SKILL.md"
        ).read_text(encoding="utf-8")
        world = (ROOT / "skills" / "idol-world-still-reference-department" / "SKILL.md").read_text(encoding="utf-8")
        self.assertRegex(pinterest, r"Private/logged-in")
        self.assertIn("yt-dlp", world)

    def test_registry_sha_matches_file_bytes(self) -> None:
        for path in SURFACES:
            rev, reg_sha = _registry_row(path)
            file_sha = _sha256(path)
            self.assertEqual(
                reg_sha,
                file_sha,
                f"{path.relative_to(ROOT)} registry sha mismatch rev={rev}",
            )
            self.assertGreaterEqual(rev, 1)

    def test_kernel_search_forbids_sentence_queries(self) -> None:
        pinterest = (
            ROOT / "skills" / "idol-pinterest-reference-worker" / "SKILL.md"
        ).read_text(encoding="utf-8")
        detail = (
            ROOT
            / "skills"
            / "idol-pinterest-reference-worker"
            / "references"
            / "pinterest-section-comparison-detail.md"
        ).read_text(encoding="utf-8")
        wardrobe = (
            ROOT
            / "skills"
            / "idol-pinterest-reference-worker"
            / "references"
            / "2d-source-to-photoreal-wardrobe-method.md"
        ).read_text(encoding="utf-8")
        for text in (pinterest, detail, wardrobe):
            self.assertIn("visual kernel", text)
            self.assertRegex(text, r"storyline\s+paragraphs")
            self.assertRegex(text, r"lyric\s+paraphrases")
            self.assertRegex(text, r"camera\s+essays")
        for text in (pinterest, detail):
            self.assertIn("Sequence owns the event", text)
            self.assertRegex(text, r"not (?:a\s+)?Sequence\s+Units?")
            self.assertIn("kernel_search", text)
            self.assertRegex(text, r"one\s+noun or pose only")
            self.assertRegex(text, r"named\s+alternative")
            self.assertIn("uniqueness scorer", text)
            self.assertNotIn("uniqueness score from labels", text)
        self.assertRegex(pinterest, r"First query:\s+one visual kernel")
        self.assertRegex(
            pinterest,
            r"additional pins would not change the Director's section\s+decision",
        )
        self.assertRegex(detail, r"Do not treat pins as Sequence")
        self.assertIn("locked garment noun", wardrobe)
        for path in (
            ROOT / "skills" / "idol-pinterest-reference-worker" / "SKILL.md",
            ROOT
            / "skills"
            / "idol-pinterest-reference-worker"
            / "references"
            / "pinterest-section-comparison-detail.md",
            ROOT
            / "skills"
            / "idol-pinterest-reference-worker"
            / "references"
            / "2d-source-to-photoreal-wardrobe-method.md",
        ):
            _rev, reg_sha = _registry_row(path)
            self.assertEqual(_sha256(path), reg_sha, f"{path.relative_to(ROOT)} sha stale")

    def test_extra_same_work_event_grammar_declaration_presence(self) -> None:
        def closeable(row: dict) -> bool:
            if row.get("disposition") not in {"applied", "combined"}:
                return True
            if not row.get("same_work_event_grammar"):
                return True
            return bool(row.get("named_alternative") or row.get("founder_exception"))

        self.assertTrue(
            closeable(
                {
                    "disposition": "applied",
                    "same_work_event_grammar": True,
                    "named_alternative": "PIN_ALT_01",
                }
            )
        )
        self.assertTrue(
            closeable(
                {
                    "disposition": "applied",
                    "same_work_event_grammar": True,
                    "founder_exception": "Founder named the repeat",
                }
            )
        )
        self.assertFalse(
            closeable({"disposition": "applied", "same_work_event_grammar": True})
        )
        self.assertTrue(closeable({"disposition": "held", "same_work_event_grammar": True}))
        self.assertTrue(closeable({"disposition": "applied"}))

    def test_section_and_member_expansion_uses_adaptive_existing_route(self) -> None:
        routing = (
            ROOT / "policies" / "harness-routing-and-sources.md"
        ).read_text(encoding="utf-8")
        pinterest = (
            ROOT / "skills" / "idol-pinterest-reference-worker" / "SKILL.md"
        ).read_text(encoding="utf-8")
        member = (
            ROOT / "skills" / "idol-member-visual-identity" / "SKILL.md"
        ).read_text(encoding="utf-8")
        self.assertIn("Fixed room counts", routing)
        self.assertRegex(routing, r"These decision sets replace per-section pin\s+quotas")
        self.assertIn("does not create a separate Styling Room", routing)
        self.assertRegex(pinterest, r"There is no fixed\s+Pinterest comparison quota")
        self.assertIn("focused decision-ready set sized only to the named component gaps", pinterest)
        self.assertIn("Candidate count is adaptive", member)
        front_planning = (
            ROOT / "skills" / "idol-front-planning-director" / "SKILL.md"
        ).read_text(encoding="utf-8")
        self.assertIn("Candidate count is adaptive", front_planning)

    def test_role_and_downstream_fields_are_preserved(self) -> None:
        direction = (ROOT / "schemas" / "song-choreography-performance-mv-map.schema.json").read_text(encoding="utf-8")
        storyboard = (ROOT / "schemas" / "master-storyboard.schema.json").read_text(encoding="utf-8")
        packets = (ROOT / "schemas" / "prompt-packets.schema.json").read_text(encoding="utf-8")
        request = (ROOT / "schemas" / "image-generation-request.schema.json").read_text(encoding="utf-8")
        for text in (direction, storyboard):
            self.assertIn('"main_reference"', text)
            self.assertIn('"supporting_visual_reference"', text)
            self.assertIn('"role"', text)
        for text in (packets, request):
            self.assertIn('"governing_scene_or_sequence_reference"', text)
            self.assertIn('"supporting_component_reference"', text)
            self.assertIn('"role"', text)

    def test_reference_index_has_truthful_public_pin_eligibility(self) -> None:
        schema = json.loads(
            (ROOT / "schemas" / "reference-working-index.schema.json").read_text(
                encoding="utf-8"
            )
        )
        eligibility = schema["$defs"]["activeSourceEligibility"]["properties"]
        self.assertIn("public_pinterest_pin", eligibility["classification"]["enum"])
        self.assertIn(
            "public pin identity",
            eligibility["origin_identity_verified"]["description"],
        )

    def test_codex_grok_capture_and_720_video_floor_exist(self) -> None:
        capture = (ROOT / "scripts" / "idol_pinterest_public_capture.py").read_text(encoding="utf-8")
        video = (ROOT / "scripts" / "yt-dlp-bilibili.sh").read_text(encoding="utf-8")
        self.assertIn("IDOL_PINTEREST_CAPTURE_APPROVED", capture)
        self.assertIn("min_short_edge", capture)
        self.assertIn("MIN_VIDEO_SHORT_EDGE", video)
        self.assertIn("MIN_VIDEO_SHORT_EDGE < 720", video)


if __name__ == "__main__":
    unittest.main()
