#!/usr/bin/env python3
"""Active 02B local-export regression checks."""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import idol_export_02b_prompt_manifests as exporter


class Idol02BSectionExecutionTest(unittest.TestCase):
    def setUp(self) -> None:
        asset_parent = ROOT / "assets" / "members" / "album-assets"
        asset_parent.mkdir(parents=True, exist_ok=True)
        self.asset_temp = tempfile.TemporaryDirectory(
            prefix="TEST_ACTIVE_EXPORT_",
            dir=asset_parent,
        )
        self.run_temp = tempfile.TemporaryDirectory(
            prefix="idol-active-export-",
            dir=ROOT / "runs",
        )
        self.album_key = Path(self.asset_temp.name).name
        self.title_key = "TITLE"
        self.member_path = Path(self.asset_temp.name) / self.title_key / "M01" / "member.png"
        self.member_path.parent.mkdir(parents=True, exist_ok=True)
        self.member_path.write_bytes(b"active current-title member pixels")
        self.scene_path = Path(self.run_temp.name) / "references" / "sequence-cell.png"
        self.scene_path.parent.mkdir(parents=True, exist_ok=True)
        self.scene_path.write_bytes(b"selected sequence cell pixels")
        self.source_path = Path(self.run_temp.name) / "02B-prompt-packets.yaml"
        self.source_path.write_text("schema_version: '2.6'\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.run_temp.cleanup()
        self.asset_temp.cleanup()

    def test_member_packet_exports_current_title_visual_before_scene_reference(self) -> None:
        packet = self.packet(member_visible=True)
        manifest, prompt = exporter.packet_manifest(
            self.source_path,
            exporter.file_sha256(self.source_path),
            {"content_id": "ACTIVE_EXPORT_TEST"},
            packet,
        )

        self.assertEqual("idol_02b_packet_export_manifest.v4", manifest["schema_version"])
        self.assertEqual("gpt-image-2", manifest["quality_contract"]["model"])
        self.assertEqual(
            ["current_title_member_visual", "governing_scene_or_sequence_reference"],
            [row["role"] for row in manifest["attachment_order"]],
        )
        self.assertEqual([1, 2], [row["input_slot"] for row in manifest["attachment_order"]])
        self.assertEqual(
            self.relative(self.member_path),
            manifest["member_visual_inputs"][0]["path"],
        )
        self.assertEqual(
            self.relative(self.scene_path),
            manifest["scene_reference_inputs"][0]["path"],
        )
        self.assertEqual(packet["compiled_prompt_block"]["full_prompt_text"], prompt)
        self.assertFalse(manifest["execution_boundary"]["paid_generation_approved"])

    def test_object_only_packet_keeps_scene_reference_without_member_visual(self) -> None:
        packet = self.packet(member_visible=False)
        manifest, _prompt = exporter.packet_manifest(
            self.source_path,
            exporter.file_sha256(self.source_path),
            {"content_id": "ACTIVE_EXPORT_TEST"},
            packet,
        )

        self.assertEqual("not_visible", manifest["member_visual_applicability"])
        self.assertEqual([], manifest["member_visual_inputs"])
        self.assertEqual(1, len(manifest["scene_reference_inputs"]))
        self.assertEqual(
            ["governing_scene_or_sequence_reference"],
            [row["role"] for row in manifest["attachment_order"]],
        )

    def test_cross_title_member_visual_is_rejected(self) -> None:
        packet = self.packet(member_visible=True)
        packet["attachments"][0]["actual_path"] = self.relative(self.scene_path)
        packet["attachments"][0]["sha256"] = exporter.file_sha256(self.scene_path)

        with self.assertRaisesRegex(exporter.ExportError, "outside the current-title package"):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def test_temporal_camera_motion_cannot_enter_image_export(self) -> None:
        packet = self.packet(member_visible=False)
        block = packet["compiled_prompt_block"]
        block["action_cue"] = "The camera pushes in while the token remains separated."
        block["full_prompt_text"] = self.prompt_text(block)
        block["full_prompt_sha256"] = hashlib.sha256(
            block["full_prompt_text"].encode("utf-8")
        ).hexdigest()

        with self.assertRaisesRegex(exporter.ExportError, "temporal camera motion belongs to 03V"):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def test_face_only_path_is_rejected_instead_of_becoming_an_identity_lane(self) -> None:
        face_path = (
            Path(self.asset_temp.name)
            / self.title_key
            / "M01"
            / "face-only-reference"
            / "member.png"
        )
        face_path.parent.mkdir(parents=True, exist_ok=True)
        face_path.write_bytes(b"prohibited face lane")
        packet = self.packet(member_visible=True)
        packet["attachments"][0]["actual_path"] = self.relative(face_path)
        packet["attachments"][0]["sha256"] = exporter.file_sha256(face_path)

        with self.assertRaisesRegex(exporter.ExportError, "face-only reference"):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def test_retired_no_mic_path_is_rejected_before_export(self) -> None:
        retired_path = (
            Path(self.asset_temp.name)
            / self.title_key
            / "M01"
            / "member-no_mic.png"
        )
        retired_path.parent.mkdir(parents=True, exist_ok=True)
        retired_path.write_bytes(b"retired identity pixels")
        packet = self.packet(member_visible=True)
        packet["attachments"][0]["actual_path"] = self.relative(retired_path)
        packet["attachments"][0]["sha256"] = exporter.file_sha256(retired_path)

        with self.assertRaisesRegex(exporter.ExportError, "retired no-mic/no_mic path"):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def test_rendered_five_lines_drift_is_rejected(self) -> None:
        packet = self.packet(member_visible=False)
        rendered = dict(packet["rendered_five_lines"])
        rendered["scene_intent"] = "Silently replace the authored still purpose."
        rendered["full_prompt_text"] = self.prompt_text(rendered)
        rendered["full_prompt_sha256"] = hashlib.sha256(
            str(rendered["full_prompt_text"]).encode("utf-8")
        ).hexdigest()
        packet["rendered_five_lines"] = rendered
        with self.assertRaisesRegex(
            exporter.ExportError, "rendered_five_lines differs from compiled_prompt_block"
        ):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def test_attachment_projection_drift_is_rejected(self) -> None:
        packet = self.packet(member_visible=True)
        packet["visual_reference_bindings"] = [
            {
                "order": row["order"],
                "reference_scope": (
                    "member_visual"
                    if row["role"] == "current_title_member_visual"
                    else "scene_visual"
                ),
                "binding_id": row["binding_id"],
                "asset_id": row["asset_id"],
                "actual_path": row["actual_path"],
                "sha256": row["sha256"],
            }
            for row in packet["attachments"]
        ]
        exporter.packet_manifest(
            self.source_path,
            exporter.file_sha256(self.source_path),
            {"content_id": "ACTIVE_EXPORT_TEST"},
            packet,
        )
        member = next(
            row for row in packet["attachments"] if row["role"] == "current_title_member_visual"
        )
        scene = next(
            row for row in packet["attachments"] if row["role"] != "current_title_member_visual"
        )
        scene["actual_path"] = member["actual_path"]
        scene["sha256"] = member["sha256"]
        with self.assertRaisesRegex(
            exporter.ExportError,
            "attachments must remain the transport projection of locked 02A visual_reference_bindings",
        ):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def test_grok_native_export_uses_adapter_model_label(self) -> None:
        packet = self.packet(member_visible=False)
        packet["execution"] = {
            "execution_adapter_id": "grok_image",
            "provider_model_or_tool": "grok_image",
        }
        manifest, _prompt = exporter.packet_manifest(
            self.source_path,
            exporter.file_sha256(self.source_path),
            {"content_id": "ACTIVE_EXPORT_TEST"},
            packet,
        )
        self.assertEqual("grok_image", manifest["quality_contract"]["model"])

    def test_openai_export_rejects_non_gpt_image_2_model(self) -> None:
        packet = self.packet(member_visible=False)
        packet["execution"]["provider_model_or_tool"] = "gpt-image-1"
        with self.assertRaisesRegex(exporter.ExportError, "gpt-image-2"):
            exporter.packet_manifest(
                self.source_path,
                exporter.file_sha256(self.source_path),
                {"content_id": "ACTIVE_EXPORT_TEST"},
                packet,
            )

    def packet(self, *, member_visible: bool) -> dict[str, object]:
        block: dict[str, object] = {
            "identity_reference_rule": (
                "Use the selected current-title member visual for appearance only."
                if member_visible
                else "No member visual is attached because no member is visible."
            ),
            "scene_intent": (
                "Make the restrained hand contact read as the cause."
                if member_visible
                else "Hold the displaced token as the world consequence."
            ),
            "visible_details": (
                "4K, high quality, high detail; rear-view member on the left and token at center."
                if member_visible
                else "4K, high quality, high detail; no person, token on the lower-right third."
            ),
            "action_cue": (
                "The gloved hand is in contact with the token."
                if member_visible
                else "The token remains visibly separated from the rail."
            ),
            "avoid": (
                "Avoid readable face, frontal gaze, or distorted hands."
                if member_visible
                else "Avoid any person, portrait framing, or duplicated token."
            ),
            "label_order": exporter.PROMPT_LABELS,
        }
        block["full_prompt_text"] = self.prompt_text(block)
        block["full_prompt_sha256"] = hashlib.sha256(
            str(block["full_prompt_text"]).encode("utf-8")
        ).hexdigest()

        bindings: list[dict[str, object]] = []
        selected: list[dict[str, object]] = []
        if member_visible:
            member_sha = exporter.file_sha256(self.member_path)
            bindings.append(
                {
                    "binding_id": "VRB_MEMBER_M01",
                    "asset_id": "VIS-M01",
                    "actual_path": self.relative(self.member_path),
                    "sha256": member_sha,
                    "role": "current_title_member_visual",
                    "order": 1,
                    "pixel_inspection_status": "passed",
                    "locked": True,
                }
            )
            selected.append(
                {
                    "asset_id": "VIS-M01",
                    "actual_path": self.relative(self.member_path),
                    "sha256": member_sha,
                }
            )
        bindings.append(
            {
                "binding_id": "VRB_SCENE_SEQ",
                "asset_id": "REF-01",
                "actual_path": self.relative(self.scene_path),
                "sha256": exporter.file_sha256(self.scene_path),
                "role": "governing_scene_or_sequence_reference",
                "order": len(bindings) + 1,
                "pixel_inspection_status": "passed",
                "locked": True,
            }
        )
        return {
            "packet_id": "PKT_BC01_ACTION" if member_visible else "PKT_BC02_OBJECT",
            "mode": "official_branch",
            "core_cut_id": "C01" if member_visible else "C02",
            "branch_cut_id": "BC01_ACTION" if member_visible else "BC02_OBJECT",
            "execution_section_id": "S01",
            "member_visual_applicability": "meaningfully_visible" if member_visible else "not_visible",
            "five_line_components": {
                "identity_reference_rule": {
                    "current_title_visual_bindings": ["VIS-M01"] if member_visible else []
                }
            },
            "member_visual_lock": {
                "member_visual_reference_policy": "required" if member_visible else "prohibited",
                "package_album_key": self.album_key,
                "package_title_key": self.title_key,
                "selected_assets": selected,
            },
            "attachments": bindings,
            "compiled_prompt_block": block,
            "rendered_five_lines": dict(block),
            "execution": {
                "execution_adapter_id": "openai_api_gpt_image_2",
                "provider_model_or_tool": "gpt-image-2",
            },
            "export_contract": {
                "expected_output_path": (
                    f"{self.relative(Path(self.run_temp.name))}/outputs/"
                    f"{'PKT_BC01_ACTION' if member_visible else 'PKT_BC02_OBJECT'}.png"
                )
            },
        }

    @staticmethod
    def prompt_text(block: dict[str, object]) -> str:
        return "\n".join(
            [
                f"Identity reference rule: {block['identity_reference_rule']}",
                f"Scene intent: {block['scene_intent']}",
                f"Visible details: {block['visible_details']}",
                f"Action cue: {block['action_cue']}",
                f"Avoid: {block['avoid']}",
            ]
        )

    @staticmethod
    def relative(path: Path) -> str:
        return path.resolve().relative_to(ROOT).as_posix()


if __name__ == "__main__":
    unittest.main()
