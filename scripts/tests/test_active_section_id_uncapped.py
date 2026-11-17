#!/usr/bin/env python3
from __future__ import annotations

import re
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
STAGE_REGISTRY = ROOT / "automation/harness-stage-registry.yaml"
ACTIVE_SUPPORT_SCHEMAS = {
    "schemas/terra-section-lifecycle-execution-record.schema.json",
    "schemas/terra-section-lifecycle-receipt.schema.json",
    "schemas/luna-section-lifecycle-execution-record.schema.json",
    "schemas/luna-section-lifecycle-receipt.schema.json",
    "schemas/video-prompt-section-qa.schema.json",
    "schemas/03v-creative-context-review-execution-record.schema.json",
    "schemas/edit-marker-plan.schema.json",
    "schemas/edit-recipe.schema.json",
    "schemas/llm-review-execution-record.schema.json",
    "schemas/harness-frontier-check.schema.json",
}
BOUNDED_SECTION_PATTERN = re.compile(
    r"\^S\[0-9\]\{2\}(?!,)|\^S\[0-9\]\{2,[0-9]+\}"
)


class ActiveSectionIdUncappedTest(unittest.TestCase):
    def test_active_contracts_do_not_cap_section_cardinality(self) -> None:
        registry = yaml.safe_load(STAGE_REGISTRY.read_text(encoding="utf-8"))
        schemas = {
            schema
            for stage in registry["stages"]
            if stage.get("active") is True
            for schema in stage.get("output_contracts", [])
        }
        schemas.update(ACTIVE_SUPPORT_SCHEMAS)
        offenders: list[str] = []
        for relative in sorted(schemas):
            text = (ROOT / relative).read_text(encoding="utf-8")
            if BOUNDED_SECTION_PATTERN.search(text):
                offenders.append(relative)
        self.assertEqual([], offenders)


if __name__ == "__main__":
    unittest.main()
