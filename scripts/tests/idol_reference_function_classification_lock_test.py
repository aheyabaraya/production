#!/usr/bin/env python3
"""Regression lock for reference purpose-class taxonomy and scene/sequence indexing.

Drives the real catalog validator and asserts that classified batch sources keep:
- only the eight locked purpose classes
- only the five locked retrieval views and fixed mapping
- scene/sequence classification fields including classification_status
- no per-cell catalog units
- an analysis-first wiki index with five secondary function views
- legacy function rows held until scene/sequence reanalysis is complete
- honest cell observations (no boilerplate function_contribution; high unique facts)
- selected_evidence sheet time ranges that intersect source_locator
- catalog_index:true implies a matching REF_* unit
"""

from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "catalog" / "references" / "reference-catalog.yaml"
VALIDATOR_SCRIPT = ROOT / "scripts" / "validate_reference_management_catalog.py"
WIKI_RETRIEVAL = ROOT / "wiki" / "reference-retrieval"

LOCKED_PURPOSE_CLASSES = [
    "major_scene_grammar_or_feeling",
    "background_and_space",
    "still_camera_and_composition",
    "lighting_color_material",
    "subject_state_or_pose",
    "visible_action_or_hold",
    "object_environment_response",
    "edit_or_transition",
]
LOCKED_STATUS = {
    "classified",
    "classified_with_secondary_functions",
    "hold_ambiguous_function",
    "hold_missing_visual_evidence",
    "rejected_no_reusable_function",
}
LOCKED_VIEWS = {
    "major_or_feeling": ["major_scene_grammar_or_feeling"],
    "background_and_light": ["background_and_space", "lighting_color_material"],
    "action": [
        "subject_state_or_pose",
        "visible_action_or_hold",
        "object_environment_response",
    ],
    "camera": ["still_camera_and_composition"],
    "edit": ["edit_or_transition"],
}
CLASSIFICATION_PATHS = [
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/idont-bargain-1s-v1/function-classification-v1.yaml",
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/new-genesis-stage-v1/function-classification-v1.yaml",
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/gimme-dat-love-v1/function-classification-v1.yaml",
    ROOT
    / "cf/runs/CF_PUBG_AURORA_M_GAME_TEASER_001/research/reference-intake/dark-arts-opening-0-10-v1/function-classification-v1.yaml",
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/bv1vu-rr-yoedx-v1/function-classification-v1.yaml",
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/bv1k54y1f7ny-v1/function-classification-v1.yaml",
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/kiss-n-tell-1s-v1/function-classification-v1.yaml",
    ROOT
    / "runs/2026-07-29/0729_ONE_MOVE/research/reference-intake/orion-yoasobi-1s-v1/function-classification-v1.yaml",
]
BATCH_UNIT_PREFIXES = (
    "REF_IDB_",
    "REF_NG_",
    "REF_GDL_",
    "REF_DA_",
    "REF_CITY_",
    "REF_GEM_",
    "REF_KNT_",
    "REF_ORN_",
)
BANNED_FUNCTION_CONTRIBUTION = {
    "supports scene function via continuous 1s observation",
}
SCENE_REQUIRED = [
    "scene_id",
    "source_time_range",
    "primary_purpose_class",
    "secondary_purpose_classes",
    "retrieval_views",
    "observable_screen_fact",
    "reusable_function",
    "classification_basis",
    "evidence_sheet_ids",
    "evidence_cell_ids",
    "search_terms_ko",
    "search_terms_en",
    "classification_status",
]
SEQUENCE_REQUIRED = [
    "sequence_id",
    "primary_purpose_class",
    "secondary_purpose_classes",
    "retrieval_views",
    "reusable_function_summary",
    "included_scene_ids",
    "evidence_range",
    "classification_basis",
    "search_terms",
    "classification_status",
]
CELL_REQUIRED = [
    "timestamp",
    "cell_id",
    "observed_fact",
    "function_contribution",
    "purpose_class_candidates",
    "owning_scene_id",
]


def load_validator_module():
    spec = importlib.util.spec_from_file_location(
        "validate_reference_management_catalog", VALIDATOR_SCRIPT
    )
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def parse_seconds_range(text: str) -> tuple[float, float] | None:
    """Parse first time range like 00.000-11.000s or 82.000-99.000s from locator text."""
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*(?:s)?\s*[-–]\s*(\d+(?:\.\d+)?)\s*s?",
        text,
        flags=re.IGNORECASE,
    )
    if not match:
        return None
    return float(match.group(1)), float(match.group(2))


def sheet_part_range_from_path(path: str) -> tuple[float, float] | None:
    """Extract start/end seconds from dense 1s part filenames with ms stamps."""
    match = re.search(r"part-\d+-(\d{8})ms-(\d{8})ms", path)
    if match:
        start_ms = int(match.group(1))
        end_ms = int(match.group(2))
        return start_ms / 1000.0, end_ms / 1000.0
    # whole-range opening sheet used by Dark Arts 0-10
    if "dark-arts-opening-0-10-one-second" in path:
        return 0.0, 10.0
    return None


def ranges_intersect(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return a[0] < b[1] and b[0] < a[1]


def expected_unit_ids_for_scene(source_key: str, scene_id: str) -> set[str]:
    if source_key.endswith("LHUMzyMq084") or "idont-bargain" in source_key:
        return {f"REF_IDB_{scene_id}"}
    if scene_id.startswith("NG_"):
        return {f"REF_{scene_id}", f"REF_NG_{scene_id}"}
    if scene_id.startswith("GDL_"):
        return {f"REF_{scene_id}", f"REF_GDL_{scene_id}"}
    if scene_id.startswith("DA_"):
        return {f"REF_{scene_id}", f"REF_DA_{scene_id}"}
    if scene_id.startswith("CITY_"):
        return {f"REF_{scene_id}", f"REF_CITY_{scene_id}"}
    if scene_id.startswith("GEM_"):
        return {f"REF_{scene_id}", f"REF_GEM_{scene_id}"}
    if scene_id.startswith("KNT_"):
        return {f"REF_{scene_id}", f"REF_KNT_{scene_id}"}
    if scene_id.startswith("ORN_"):
        return {f"REF_{scene_id}", f"REF_ORN_{scene_id}"}
    return {f"REF_{scene_id}"}


class ReferenceFunctionClassificationLockTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.validator = load_validator_module()
        cls.catalog = yaml.safe_load(CATALOG.read_text(encoding="utf-8"))
        cls.unit_ids = {
            unit["reference_unit_id"] for unit in cls.catalog["reference_units"]
        }

    def test_catalog_validator_passes_on_live_catalog(self):
        errors = self.validator.validate_catalog(CATALOG)
        self.assertEqual(errors, [], msg="\n".join(errors))

    def test_taxonomy_lock_matches_catalog_and_wiki_contract(self):
        self.assertEqual(self.catalog["purpose_classes"], LOCKED_PURPOSE_CLASSES)
        self.assertEqual(self.catalog["retrieval_views"], LOCKED_VIEWS)
        wiki = (ROOT / "wiki/reference-management-system.md").read_text(encoding="utf-8")
        for purpose in LOCKED_PURPOSE_CLASSES:
            self.assertIn(purpose, wiki)
        for view in LOCKED_VIEWS:
            self.assertTrue(
                (WIKI_RETRIEVAL / f"{view}.md").is_file(),
                f"missing wiki retrieval view {view}",
            )
        retrieval_index = WIKI_RETRIEVAL / "INDEX.md"
        self.assertTrue(retrieval_index.is_file())
        index_text = retrieval_index.read_text(encoding="utf-8")
        self.assertIn("Reference Scene And Sequence Retrieval Index", index_text)
        self.assertIn("Sequence flow observation", index_text)
        self.assertIn("nested 02B-shaped", index_text)
        self.assertIn("HOLD", index_text)

    def test_batch_classification_files_have_required_fields_and_locked_enums(self):
        for path in CLASSIFICATION_PATHS:
            self.assertTrue(path.is_file(), path)
            doc = yaml.safe_load(path.read_text(encoding="utf-8"))
            self.assertGreaterEqual(len(doc.get("one_second_cells") or []), 1, path.name)
            self.assertGreaterEqual(len(doc.get("scenes") or []), 1, path.name)
            self.assertGreaterEqual(len(doc.get("sequences") or []), 1, path.name)

            for scene in doc["scenes"]:
                for key in SCENE_REQUIRED:
                    self.assertIn(key, scene, f"{path.name} scene missing {key}")
                self.assertIn(scene["classification_status"], LOCKED_STATUS)
                purposes = [scene["primary_purpose_class"]] + list(
                    scene.get("secondary_purpose_classes") or []
                )
                for purpose in purposes:
                    self.assertIn(purpose, LOCKED_PURPOSE_CLASSES)
                for view in scene["retrieval_views"]:
                    self.assertIn(view, LOCKED_VIEWS)
                if str(scene.get("classification_status", "")).startswith("classified"):
                    self.assertGreaterEqual(len(scene["reusable_function"]), 20)

            for sequence in doc["sequences"]:
                for key in SEQUENCE_REQUIRED:
                    self.assertIn(key, sequence, f"{path.name} sequence missing {key}")
                self.assertIn(sequence["classification_status"], LOCKED_STATUS)
                purposes = [sequence["primary_purpose_class"]] + list(
                    sequence.get("secondary_purpose_classes") or []
                )
                for purpose in purposes:
                    self.assertIn(purpose, LOCKED_PURPOSE_CLASSES)

            for cell in doc["one_second_cells"]:
                for key in CELL_REQUIRED:
                    self.assertIn(key, cell, f"{path.name} cell missing {key}")
                for purpose in cell.get("purpose_class_candidates") or []:
                    self.assertIn(purpose, LOCKED_PURPOSE_CLASSES)

    def test_cell_observations_are_not_boilerplate(self):
        for path in CLASSIFICATION_PATHS:
            doc = yaml.safe_load(path.read_text(encoding="utf-8"))
            cells = doc["one_second_cells"]
            facts = [cell["observed_fact"].strip() for cell in cells]
            contribs = [cell["function_contribution"].strip() for cell in cells]
            for contrib in contribs:
                self.assertNotIn(
                    contrib.lower(),
                    {item.lower() for item in BANNED_FUNCTION_CONTRIBUTION},
                    f"{path.name} uses banned boilerplate function_contribution",
                )
                self.assertNotEqual(
                    contrib.lower(),
                    "supports scene function via continuous 1s observation",
                )
            # Unique observed_fact rate: logo/title holds may repeat; require high uniqueness.
            unique_ratio = len(set(facts)) / max(len(facts), 1)
            self.assertGreaterEqual(
                unique_ratio,
                0.85,
                f"{path.name} unique observed_fact ratio {unique_ratio:.2f} too low",
            )
            # Non-logo/endcard cells should almost all be unique.
            non_hold = [
                fact
                for fact in facts
                if "logo" not in fact.lower()
                and "title hold" not in fact.lower()
                and "black field" not in fact.lower()
            ]
            if non_hold:
                non_hold_ratio = len(set(non_hold)) / len(non_hold)
                self.assertGreaterEqual(
                    non_hold_ratio,
                    0.95,
                    f"{path.name} non-hold unique fact ratio {non_hold_ratio:.2f}",
                )

    def test_catalog_index_true_implies_matching_reference_unit(self):
        for path in CLASSIFICATION_PATHS:
            doc = yaml.safe_load(path.read_text(encoding="utf-8"))
            source_key = doc.get("source_key") or doc.get("source_identity") or path.as_posix()
            for scene in doc["scenes"]:
                if not scene.get("catalog_index"):
                    # false must not be a silent drop: require explicit reason when present
                    if "catalog_index_reason" in scene:
                        self.assertTrue(str(scene["catalog_index_reason"]).strip())
                    continue
                expected = expected_unit_ids_for_scene(source_key, scene["scene_id"])
                self.assertTrue(
                    expected & self.unit_ids,
                    f"{path.name} {scene['scene_id']} catalog_index true but no unit in {expected}",
                )
            for sequence in doc["sequences"]:
                if not sequence.get("catalog_index"):
                    continue
                sid = sequence["sequence_id"]
                candidates = {
                    f"REF_IDB_{sid}",
                    f"REF_NG_{sid}",
                    f"REF_GDL_{sid}",
                    f"REF_DA_{sid}",
                    f"REF_CITY_{sid}",
                    f"REF_GEM_{sid}",
                    f"REF_KNT_{sid}",
                    f"REF_ORN_{sid}",
                    f"REF_{sid}",
                }
                self.assertTrue(
                    candidates & self.unit_ids,
                    f"{path.name} {sid} catalog_index true but no unit in {candidates}",
                )

    def test_batch_catalog_units_are_scene_or_sequence_not_cells(self):
        batch_units = [
            unit
            for unit in self.catalog["reference_units"]
            if str(unit.get("reference_unit_id", "")).startswith(BATCH_UNIT_PREFIXES)
        ]
        self.assertGreaterEqual(len(batch_units), 20)
        for unit in batch_units:
            unit_id = unit["reference_unit_id"]
            self.assertNotIn("1S_", unit_id)
            self.assertEqual(unit["direct_use_mode"], "not_authorized_by_catalog")
            self.assertEqual(unit["reuse_status"], "candidate_for_reuse")
            self.assertIsNotNone(unit.get("analysis_ref"))
            self.assertTrue(
                str(unit["source_locator"]).startswith(("sequence ", "scene ")),
                unit_id,
            )
            for purpose in unit["purpose_classes"]:
                self.assertIn(purpose, LOCKED_PURPOSE_CLASSES)
            analysis_path = ROOT / unit["analysis_ref"]["path"]
            self.assertTrue(analysis_path.is_file(), analysis_path)
            analysis_name = unit["analysis_ref"]["path"]
            self.assertTrue(
                analysis_name.endswith("function-classification-v1.yaml")
                or analysis_name.endswith("directing-analysis.md")
                or "directing-analysis" in analysis_name
                or "first-read" in analysis_name,
                f"{unit_id} analysis_ref should be a classification, directing, or completed first-read analysis: {analysis_name}",
            )

    def test_selected_evidence_sheet_range_intersects_source_locator(self):
        for unit in self.catalog["reference_units"]:
            unit_id = unit.get("reference_unit_id", "")
            if not unit_id.startswith(BATCH_UNIT_PREFIXES):
                continue
            locator_range = parse_seconds_range(unit.get("source_locator") or "")
            if locator_range is None:
                self.fail(f"{unit_id} source_locator has no parseable time range")
            sheet_hits = 0
            for evidence in unit.get("selected_evidence") or []:
                path = evidence.get("path") or ""
                if not path.endswith((".png", ".jpg", ".jpeg", ".webp")):
                    continue
                sheet_range = sheet_part_range_from_path(path)
                if sheet_range is None:
                    # selected strip without ms stamps is allowed as extra evidence
                    continue
                self.assertTrue(
                    (ROOT / path).is_file(),
                    f"{unit_id} missing evidence file {path}",
                )
                self.assertTrue(
                    ranges_intersect(locator_range, sheet_range),
                    f"{unit_id} evidence {path} range {sheet_range} does not intersect "
                    f"locator {locator_range}",
                )
                sheet_hits += 1
            # GDL dense-sheet units must have at least one timestamped sheet evidence
            if unit_id.startswith("REF_GDL_"):
                self.assertGreaterEqual(
                    sheet_hits,
                    1,
                    f"{unit_id} needs at least one time-ranged sheet in selected_evidence",
                )

    def test_wiki_retrieval_rows_point_at_catalog_units(self):
        unit_ids = {
            unit["reference_unit_id"]
            for unit in self.catalog["reference_units"]
            if str(unit.get("reference_unit_id", "")).startswith(BATCH_UNIT_PREFIXES)
        }
        for view in LOCKED_VIEWS:
            text = (WIKI_RETRIEVAL / f"{view}.md").read_text(encoding="utf-8")
            self.assertIn("Secondary Reference Function View", text)
            self.assertIn("Legacy function-only queue", text)
            self.assertIn("analysis is primary; this function view is secondary", text)
            self.assertIn("HOLD", text)
            self.assertTrue(
                any(unit_id in text for unit_id in unit_ids),
                f"{view} has no batch unit pointer",
            )

    def test_wiki_evidence_path_intersects_row_timestamp_range(self):
        """Wiki evidence column must not lag catalog selected_evidence rebinds."""
        unit_by_id = {
            unit["reference_unit_id"]: unit
            for unit in self.catalog["reference_units"]
            if str(unit.get("reference_unit_id", "")).startswith(BATCH_UNIT_PREFIXES)
        }
        checked = 0
        for view in LOCKED_VIEWS:
            text = (WIKI_RETRIEVAL / f"{view}.md").read_text(encoding="utf-8")
            for line in text.splitlines():
                if not line.startswith("|") or "reference_unit_id" in line or line.startswith("|---"):
                    continue
                # table rows end with | `REF_...` |
                unit_match = re.search(
                    r"`(REF_(?:IDB|NG|GDL|DA|CITY|GEM|KNT|ORN)_[A-Z0-9_]+)`\s*\|?\s*$",
                    line,
                )
                if not unit_match:
                    # also allow unit id not only at end
                    unit_match = re.search(
                        r"`(REF_(?:IDB|NG|GDL|DA|CITY|GEM|KNT|ORN)_[A-Z0-9_]+)`",
                        line,
                    )
                if not unit_match:
                    continue
                unit_id = unit_match.group(1)
                unit = unit_by_id.get(unit_id)
                if unit is None:
                    continue
                locator_range = parse_seconds_range(unit.get("source_locator") or "")
                self.assertIsNotNone(locator_range, f"{view} {unit_id} missing locator range")
                # evidence column is a backticked path; prefer image paths
                evidence_paths = re.findall(r"`([^`]+?\.(?:png|jpg|jpeg|webp))`", line)
                self.assertTrue(
                    evidence_paths,
                    f"{view} row for {unit_id} has no image evidence pointer",
                )
                # every timestamped sheet cited in the row must intersect locator
                for path in evidence_paths:
                    sheet_range = sheet_part_range_from_path(path)
                    if sheet_range is None:
                        continue
                    self.assertTrue(
                        ranges_intersect(locator_range, sheet_range),
                        f"{view} {unit_id} wiki evidence {path} range {sheet_range} "
                        f"does not intersect locator {locator_range}",
                    )
                    checked += 1
        self.assertGreaterEqual(checked, 10, "expected multiple wiki evidence range checks")


if __name__ == "__main__":
    unittest.main()
