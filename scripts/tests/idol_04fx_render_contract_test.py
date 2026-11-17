#!/usr/bin/env python3
"""Regression tests for the IDOL 04FX compiler and local FFmpeg renderer.

All media and run fixtures are created under /private/tmp and removed after the
suite.  Creative selection is intentionally out of scope: these tests only
prove registry coverage, deterministic compilation, fail-closed final gates,
frame-locked geometry/FPS, and duration-preserving xfade mechanics.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path
from typing import Any

import yaml
import jsonschema


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import idol_video_ffmpeg_revise_render as renderer  # noqa: E402
from lib.idol_edit_effect_registry import load_effect_registry  # noqa: E402


COMPILER = SCRIPTS / "idol_04fx_compile_recipe_effects.py"
RENDERER = SCRIPTS / "idol_video_ffmpeg_revise_render.py"
EDIT_MAP_READINESS = SCRIPTS / "validate_edit_map_readiness.rb"
DELIVERY_QC = SCRIPTS / "idol_edit_delivery_qc.py"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(payload, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def write_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


class Idol04FxRenderContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_context = tempfile.TemporaryDirectory(
            prefix="idol-04fx-render-contract-", dir="/private/tmp"
        )
        cls.temp_root = Path(cls.temp_context.name)
        cls.ffmpeg = renderer.tool_path("ffmpeg")
        cls.registry = load_effect_registry()
        cls.media_root = cls.temp_root / "media"
        cls.media_root.mkdir(parents=True, exist_ok=True)
        cls.source_a = cls.media_root / "source-a.mp4"
        cls.source_b = cls.media_root / "source-b.mp4"
        cls.audio = cls.media_root / "master.wav"
        cls._generate_media_fixture(cls.source_a, hue=0)
        cls._generate_media_fixture(cls.source_b, hue=75)
        cls._run(
            [
                cls.ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:sample_rate=48000:duration=6",
                "-c:a",
                "pcm_s16le",
                str(cls.audio),
            ],
            check=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_context.cleanup()

    @classmethod
    def _run(
        cls, command: list[str], *, check: bool = False, cwd: Path = ROOT
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=cwd,
            text=True,
            capture_output=True,
            check=check,
        )

    @classmethod
    def _generate_media_fixture(cls, output: Path, *, hue: int) -> None:
        cls._run(
            [
                cls.ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=640x360:rate=60:duration=4",
                "-vf",
                f"hue=h={hue}",
                "-an",
                "-c:v",
                "libx264",
                "-preset",
                "ultrafast",
                "-crf",
                "12",
                "-pix_fmt",
                "yuv420p",
                str(output),
            ],
            check=True,
        )

    def _write_v3_recipe_fixture(
        self,
        *,
        run_root: Path,
        fps: Fraction,
        width: int,
        height: int,
        timeline: list[dict[str, Any]],
        effects: list[dict[str, Any]] | None = None,
        boundary_handles: list[dict[str, Any]] | None = None,
    ) -> tuple[Path, Path, Path, Path]:
        """Write a probe-backed, schema-valid v3 recipe and its bound 04 sources."""

        run_root.mkdir(parents=True, exist_ok=True)
        content_id = run_root.name
        if not re.fullmatch(r"[A-Z0-9][A-Z0-9_-]{2,80}", content_id):
            self.fail(f"invalid fixture content id: {content_id}")

        recipe_rel = Path(
            "generations/video/qc/sync-workbench-v1/final-recipe-v1.yaml"
        )
        marker_rel = Path("generations/video/qc/edit-marker-plan-v6.yaml")
        edit_map_rel = Path("04-edit-map.yaml")
        audio_rel = Path("audio/selected/master.wav")
        audio_motion_rel = Path("research/audio-motion-director-map-v1.yaml")
        source_root_rel = Path("generations/video/raw")

        audio_path = run_root / audio_rel
        write_bytes(audio_path, self.audio.read_bytes())
        source_fixture_by_name = {
            "source-a.mp4": self.source_a,
            "source-b.mp4": self.source_b,
        }
        for source_name, source_fixture in source_fixture_by_name.items():
            write_bytes(run_root / source_root_rel / source_name, source_fixture.read_bytes())

        write_yaml(
            run_root / audio_motion_rel,
            {
                "schema_version": "idol_audio_motion_director_map.v1",
                "content_id": content_id,
                "stable_audio_extracts": {"signals": []},
            },
        )
        lineage_paths = {
            "audio_branch_cut_placements": (
                run_root / "work/04-lineage/audio-branch-cut-placement-v4.yaml"
            ),
            "video_prompt_manifests": (
                run_root / "work/04-lineage/03V-video-prompt-manifest-v7.yaml"
            ),
            "playback_review_records": (
                run_root / "work/04-lineage/03V-playback-review-v1.yaml"
            ),
        }
        storyline_text = (
            "The fixture film opens on a held route, transfers attention through "
            "the tested sections, and preserves the final displaced state."
        )
        storyline_text_sha = hashlib.sha256(
            storyline_text.encode("utf-8")
        ).hexdigest()
        storyline = {
            "contract_version": "front_planning_storyline_lineage.v1",
            "pre00_lineage": {
                "pre00_storyline_original": {
                    "version_id": "PRE00_STORYLINE_V001",
                    "full_storyline_text": storyline_text,
                    "full_storyline_text_sha256": storyline_text_sha,
                    "reference_bindings": [],
                }
            },
            "front_planning_revisions": [],
            "active_version": {
                "lineage_scope": "pre00",
                "version_id": "PRE00_STORYLINE_V001",
                "version_json_pointer": "/storyline_lineage/pre00_lineage/pre00_storyline_original",
                "full_storyline_text": storyline_text,
                "full_storyline_text_sha256": storyline_text_sha,
            },
        }
        screen_nodes_by_slot: dict[str, dict[str, Any]] = {}
        source_screen_nodes: list[dict[str, Any]] = []
        source_video_cues: list[dict[str, Any]] = []
        for index, row in enumerate(timeline):
            slot = str(row["slot"])
            section_id = str((row.get("section_ids") or [f"S{index:02d}"])[0])
            core_cut_id = f"C{section_id[1:]}"
            branch_cut_ids = [] if index == 0 else [f"BC{section_id}_{slot}"]
            cue_id = f"03VCUE_{section_id}_{slot}"
            storyline_role = "seed" if index == 0 else "progress"
            observable_screen_proof = (
                f"The {slot} fixture preserves the reviewed {section_id} screen state."
            )
            screen_nodes_by_slot[slot] = {
                "screen_progression_map_id": f"SPM_{content_id}",
                "screen_progression_node_id": f"SPN_{content_id}_{slot}",
                "section_id": section_id,
                "major_scene_id": f"MJ{section_id[1:]}",
                "core_cut_id": core_cut_id,
                "branch_cut_ids": branch_cut_ids,
                "source_03v_cue_ids": [cue_id],
                "storyline_role": storyline_role,
                "observable_screen_proof": observable_screen_proof,
            }
            source_screen_nodes.append(
                {
                    "node_id": f"SPN_{content_id}_{slot}",
                    "node_type": "core_slot",
                    "section_id": section_id,
                    "major_scene_id": f"MJ{section_id[1:]}",
                    "source_id": core_cut_id,
                    "storyline_role": storyline_role,
                    "observable_screen_proof": observable_screen_proof,
                    "continuity_in": f"The reviewed state enters {slot}.",
                    "continuity_out": f"The reviewed state exits {slot}.",
                }
            )
            core_hash = hashlib.sha256(
                f"{content_id}:{slot}:official_core".encode("utf-8")
            ).hexdigest()
            source_images = [
                {
                    "production_cut_id": core_cut_id,
                    "production_cut_type": "official_core",
                    "parent_core_cut_id": core_cut_id,
                    "sha256": core_hash,
                }
            ]
            if branch_cut_ids:
                source_images.append(
                    {
                        "production_cut_id": branch_cut_ids[0],
                        "production_cut_type": "branch",
                        "parent_core_cut_id": core_cut_id,
                        "sha256": hashlib.sha256(
                            f"{content_id}:{slot}:branch".encode("utf-8")
                        ).hexdigest(),
                    }
                )
            source_video_cues.append(
                {
                    "cue_id": cue_id,
                    "screen_progression_map_id": f"SPM_{content_id}",
                    "screen_progression_node_id": f"SPN_{content_id}_{slot}",
                    "section_id": section_id,
                    "major_scene_id": f"MJ{section_id[1:]}",
                    "core_cut_id": core_cut_id,
                    "branch_cut_ids": branch_cut_ids,
                    "source_production_cut_images": source_images,
                    "source_image_ids": [
                        source["production_cut_id"] for source in source_images
                    ],
                    "source_pixel_hashes": [
                        source["sha256"] for source in source_images
                    ],
                }
            )
        screen_progression = {
            "screen_progression_map_id": f"SPM_{content_id}",
            "nodes": source_screen_nodes,
        }
        for family, path in lineage_paths.items():
            if family == "video_prompt_manifests":
                write_yaml(
                    path,
                    {
                        "schema_version": "idol_video_prompt_manifest.v7",
                        "content_id": content_id,
                        "storyline_lineage_projection": {
                            "projected_value": storyline,
                        },
                        "screen_progression_projection": {
                            "projected_value": screen_progression,
                        },
                        "cues": source_video_cues,
                    },
                )
                continue
            write_yaml(
                path,
                {
                    "schema_version": f"fixture.{family}",
                    "content_id": content_id,
                },
            )

        marker_slots: list[dict[str, Any]] = []
        for index, row in enumerate(timeline):
            slot = str(row["slot"])
            section_id = str((row.get("section_ids") or [f"S{index:02d}"])[0])
            start_frame = int(row["output_in_frame"])
            end_frame = int(row["output_out_frame"])
            decision = None
            if index > 0:
                decision = {
                    "method": "cut_on_action",
                    "timing_relation": "exact_hit",
                    "timing_offset_frames": 0,
                    "pre_cut_evidence": "The outgoing motion reaches its reviewed handoff.",
                    "cut_frame_evidence": "The Edit Boundary lands on the selected-audio marker.",
                    "post_cut_evidence": "The incoming motion begins without a duplicate frame.",
                    "story_attention_handoff": "Attention transfers to the incoming section action.",
                    "screen_direction_or_composition": "The fixture preserves matched screen direction.",
                    "no_effect_pass": True,
                    "route": "keep_04",
                }
            marker_slots.append(
                {
                    "slot": slot,
                    "section_id": section_id,
                    "transition_id": None if index == 0 else f"CUT_{slot}",
                    "output_range": {
                        "start_seconds": float(Fraction(start_frame, 1) / fps),
                        "end_seconds": float(Fraction(end_frame, 1) / fps),
                        "start_frame": start_frame,
                        "end_frame": end_frame,
                        "duration_frames": end_frame - start_frame,
                    },
                    "cue_role": "Fixture section action",
                    "nearby_markers": {
                        "beats_seconds": [float(Fraction(start_frame, 1) / fps)],
                        "strong_onsets_seconds": [],
                        "feature_boundaries_seconds": [],
                        "lyric_or_section_handoff": None,
                    },
                    "source_lineage": {
                        "screen_progression_node": screen_nodes_by_slot[slot],
                        "source_origin": "03v_production_cut_derived",
                        "source_03v_cue_ids": [f"03VCUE_{section_id}_{slot}"],
                        "source_core_cut_ids": [f"C{section_id[1:]}"],
                        "source_branch_cut_ids": list(
                            screen_nodes_by_slot[slot]["branch_cut_ids"]
                        ),
                        "continuity_target_branch_cut_ids": [],
                        "lineage_note": "This Edit Slot derives from the passed fixture Branch Cut.",
                    },
                    "source_candidates": [
                        {
                            "candidate_id": f"SRC_{slot}",
                            "source": (
                                source_root_rel / Path(str(row["source"])).name
                            ).as_posix(),
                            "source_in": float(row["source_in"]),
                            "source_out": float(row["source_out"]),
                            "speed_hint": 1.0,
                        }
                    ],
                    "source_action_marker": {
                        "visible_event": "The reviewed fixture action reaches the Edit Boundary.",
                        "source_time_seconds": float(row["source_in"]),
                        "body_part_or_motion": "fixture action",
                        "camera_event": "locked fixture camera",
                        "source_frame": 0,
                        "source_fps": {
                            "numerator": fps.numerator,
                            "denominator": fps.denominator,
                        },
                    },
                    "incoming_cut_decision": decision,
                    "cut_density": "hold" if index == 0 else "medium",
                    "alignment_basis": ["beat_or_onset", "visible_body_landing", "cue_role"],
                    "motion_continuity": "The fixture motion remains continuous.",
                    "story_flow_continuity": "The fixture attention handoff remains readable.",
                    "space_visible_feeling_progression": "The fixture space remains stable.",
                    "directorial_transition_intent": "Use the reviewed action match.",
                    "audio_marker_alignment": "The visible action and audio marker share the boundary.",
                    "slot_status": "pass",
                    "open_questions": [],
                    "pass_fail_note": "The fixture Edit Slot is ready for recipe binding.",
                }
            )

        write_yaml(
            run_root / marker_rel,
            {
                "schema_version": "idol_edit_marker_plan.v6",
                "content_id": content_id,
                "status": "recipe_ready",
                "owner": "04_edit",
                "storyline_lineage_projection": {
                    "source_video_prompt_manifest": {
                        "path": str(lineage_paths["video_prompt_manifests"]),
                        "sha256": sha256_file(
                            lineage_paths["video_prompt_manifests"]
                        ),
                    },
                    "source_video_prompt_manifest_json_pointer": "/storyline_lineage_projection/projected_value",
                    "source_value_sha256": hashlib.sha256(
                        json.dumps(
                            storyline,
                            ensure_ascii=False,
                            sort_keys=True,
                            separators=(",", ":"),
                        ).encode("utf-8")
                    ).hexdigest(),
                    "projected_value": storyline,
                    "consumption_rule": "read_complete_pre00_original_active_full_text_revision_history_density_review_and_reference_receipts_before_edit_timing_or_cutpoint_authorship",
                },
                "screen_progression_projection": {
                    "source_video_prompt_manifest": {
                        "path": str(lineage_paths["video_prompt_manifests"]),
                        "sha256": sha256_file(
                            lineage_paths["video_prompt_manifests"]
                        ),
                    },
                    "source_video_prompt_manifest_json_pointer": "/screen_progression_projection/projected_value",
                    "source_value_sha256": hashlib.sha256(
                        json.dumps(
                            screen_progression,
                            ensure_ascii=False,
                            sort_keys=True,
                            separators=(",", ":"),
                        ).encode("utf-8")
                    ).hexdigest(),
                    "projected_value": screen_progression,
                    "consumption_rule": "exact_copy_no_paraphrase_or_default",
                },
                "production_cut_lineage_sources": {
                    family: [
                        {
                            "path": str(path),
                            "sha256": sha256_file(path),
                        }
                    ]
                    for family, path in lineage_paths.items()
                },
                "source_recipe": recipe_rel.as_posix(),
                "source_audio": audio_rel.as_posix(),
                "source_audio_motion_director_map": {
                    "path": audio_motion_rel.as_posix(),
                    "sha256": sha256_file(run_root / audio_motion_rel),
                },
                "timebase": {
                    "fps": {
                        "numerator": fps.numerator,
                        "denominator": fps.denominator,
                    },
                    "frame_interval": "start_inclusive_end_exclusive",
                    "drop_frame": False,
                    "start_timecode": "00:00:00:00",
                },
                "audio_phase_lock": {
                    "status": "manual_locked",
                    "meter_beats": 4,
                    "phase_source": "Fixture phase lock.",
                    "anchor_seconds": 0.0,
                    "anchor_beat_in_bar": 1,
                    "use_rule": "Use only for the fixture meter context.",
                },
                "upstream_intent_context": {
                    "available": True,
                    "sources": {},
                    "use_as": ["intent_map", "candidate_narrowing", "cue_function_seed"],
                    "not_edit_truth": [
                        "source_in",
                        "source_out",
                        "speed_factor",
                        "final_cutpoint",
                        "final_candidate_selection",
                        "final_geometry_override",
                    ],
                    "proof_required_in_04": [
                        "actual_source_exists",
                        "first_useful_action",
                        "motion_peak",
                        "beat_or_onset_alignment",
                        "cue_function_alignment",
                        "contact_sheet_qc",
                        "preview_qc",
                        "source_quality_qc",
                    ],
                },
                "initial_alignment_pass": {
                    "analysis_inputs": {
                        "selected_audio": audio_rel.as_posix(),
                        "cue_sheet": "review/fixture-cue.yaml",
                        "audio_motion_director_map": audio_motion_rel.as_posix(),
                    },
                    "baseline_cut_read": {
                        "roughcut_or_recipe": "fixture",
                        "what_already_works": ["The source order is fixed for the test."],
                        "what_is_not_marker_locked_yet": [],
                        "first_pass_goal": "Preserve exact frame continuity.",
                    },
                    "alignment_method": [
                        "music_marker",
                        "source_action_marker",
                        "cue_function_marker",
                    ],
                    "source_motion_scan": {
                        "motion_csv_dir": None,
                        "source_first_seconds_scan": True,
                        "motion_peak_scan": True,
                        "candidate_source_contact_sheet": True,
                    },
                    "marker_lock_required_before_recipe": True,
                },
                "timeline_slots": marker_slots,
            },
        )
        write_yaml(
            run_root / edit_map_rel,
            {
                "schema_version": "idol_edit_map.v4",
                "content_id": content_id,
                "status": "locked_for_final_render",
                "source_files": {
                    "review_record": "review/fixture.yaml",
                    "cue_sheet": "research/fixture-cue.yaml",
                    "audio_track": audio_rel.as_posix(),
                    "raw_video_dir": source_root_rel.as_posix(),
                },
                "master_timeline": {"audio_duration_seconds": 6.0},
                "rough_outputs": [
                    {
                        "output_id": "FINAL_PREVIEW",
                        "path": "generations/video/qc/previews/final-audit-preview-v1.mp4",
                        "status": "passed",
                        "duration_seconds": 1.0,
                    }
                ],
                "recipe_qc_contract": {
                    "current_final_recipe": str(run_root / recipe_rel),
                    "final_render_recipe_path": str(
                        run_root
                        / "generations/video/qc/finishing-fx-v1/"
                        "final-recipe-zero-04fx-v1.yaml"
                    ),
                    "final_render_manifest_path": str(run_root / "render-manifest.yaml"),
                    "final_render_status": "not_rendered",
                },
                "manual_adjustment_workflow": {
                    "current_final_recipe": str(run_root / recipe_rel),
                    "script_to_rerun": "scripts/idol_video_ffmpeg_revise_render.py",
                    "editable_fields": ["source_in", "source_out", "duration_frames"],
                    "rule": "04 owns exact cut truth.",
                    "active_candidate_status": "passed",
                },
                "qc_contact_sheets": {
                    "directory": "generations/video/qc/contact-sheets",
                    "slots": {},
                },
                "edit_marker_plan_ref": {
                    "schema": "idol_edit_marker_plan.v6",
                    "path": str(run_root / marker_rel),
                    "sha256": sha256_file(run_root / marker_rel),
                    "status": "recipe_ready",
                    "source_recipe": str(run_root / recipe_rel),
                },
                "screen_progression_projection": {
                    "source_video_prompt_manifest": {
                        "path": str(lineage_paths["video_prompt_manifests"]),
                        "sha256": sha256_file(
                            lineage_paths["video_prompt_manifests"]
                        ),
                    },
                    "source_video_prompt_manifest_json_pointer": "/screen_progression_projection/projected_value",
                    "source_value_sha256": hashlib.sha256(
                        json.dumps(
                            screen_progression,
                            ensure_ascii=False,
                            sort_keys=True,
                            separators=(",", ":"),
                        ).encode("utf-8")
                    ).hexdigest(),
                    "projected_value": screen_progression,
                    "consumption_rule": "exact_copy_no_paraphrase_or_default",
                },
                "edit_unit_screen_progression_nodes": [
                    {
                        **screen_nodes_by_slot[str(row["slot"])],
                        "edit_unit_id": f"SEG_{row['slot']}",
                    }
                    for row in timeline
                ],
                "audio_marker_handoff": {
                    "source_audio": str(run_root / audio_rel),
                    "audio_motion_director_map": {
                        "path": audio_motion_rel.as_posix(),
                        "sha256": sha256_file(run_root / audio_motion_rel),
                    },
                    "main_grid_bpm": 120,
                    "strong_onsets_seconds": [],
                },
                "upstream_intent_context_contract": {
                    "use_upstream_context": True,
                    "read_scope": [
                        "audio_production_cut_placement",
                        "03v_source_production_cut_images",
                        "03v_previous_next_continuity",
                        "03v_edit_handoff",
                        "03v_playback_review",
                        "story_flow_continuity",
                        "space_visible_feeling_progression",
                    ],
                    "sources": {
                        "audio_branch_cut_placement": str(
                            lineage_paths["audio_branch_cut_placements"]
                        ),
                        "video_prompt_manifest": str(
                            lineage_paths["video_prompt_manifests"]
                        ),
                        "playback_review": str(
                            lineage_paths["playback_review_records"]
                        ),
                    },
                },
                "effect_audit_summary": {
                    "finishing_fx_map_path": str(
                        run_root
                        / "generations/video/qc/finishing-fx-v1/"
                        "04FX-finishing-map-v1.yaml"
                    ),
                    "compile_manifest_path": str(
                        run_root
                        / "generations/video/qc/finishing-fx-v1/"
                        "final-zero-04fx-compile-manifest-v1.yaml"
                    ),
                    "compile_status": "pending",
                    "transition_opportunity_audit_status": "pending",
                },
                "final_closeout_inventory": {
                    "schema": "idol_edit_qc_closeout.v3",
                    "path": str(run_root / "edit-closeout-v3.yaml"),
                    "status": "pending",
                    "validation_status": "pending",
                },
                "edit_policy": ["Preserve 04 cut truth through final render."],
            },
        )

        full_timeline: list[dict[str, Any]] = []
        for index, row in enumerate(timeline):
            slot = str(row["slot"])
            source_name = Path(str(row["source"])).name
            if source_name not in source_fixture_by_name:
                self.fail(f"unknown fixture source: {source_name}")
            source_rel = source_root_rel / source_name
            source_path = run_root / source_rel
            probe_rel = Path(
                f"generations/video/qc/source-probes/{slot}-probe-v1.yaml"
            )
            write_yaml(run_root / probe_rel, renderer.ffprobe_media(source_path))

            output_in_frame = int(row["output_in_frame"])
            output_out_frame = int(row["output_out_frame"])
            duration_frames = int(row["duration_frames"])
            output_in = float(Fraction(output_in_frame, 1) / fps)
            output_out = float(Fraction(output_out_frame, 1) / fps)
            output_duration = float(Fraction(duration_frames, 1) / fps)
            source_in = float(row["source_in"])
            source_out = float(row["source_out"])
            speed_factor = (source_out - source_in) / output_duration
            full_timeline.append(
                {
                    "segment_id": f"SEG_{slot}",
                    "slot": slot,
                    "marker_slot_ref": slot,
                    "screen_progression_node": screen_nodes_by_slot[slot],
                    "section_ids": list(
                        row.get("section_ids") or [f"S{index:02d}"]
                    ),
                    "source": source_rel.as_posix(),
                    "source_sha256": sha256_file(source_path),
                    "source_probe_ref": probe_rel.as_posix(),
                    "source_probe_sha256": sha256_file(run_root / probe_rel),
                    "source_in": source_in,
                    "source_out": source_out,
                    "output_in_frame": output_in_frame,
                    "output_out_frame": output_out_frame,
                    "duration_frames": duration_frames,
                    "output_in": output_in,
                    "output_out": output_out,
                    "output_duration": output_duration,
                    "retime": {
                        "mode": "constant",
                        "speed_factor": speed_factor,
                        "cadence_method": "frame_sampling",
                        "cadence_qc_required": True,
                    },
                    "geometry": {
                        "policy": "inherit_render_spec",
                        "anchor_x": 0.5,
                        "anchor_y": 0.5,
                    },
                }
            )

        audio_probe = renderer.ffprobe_media(audio_path)
        audio_stream = next(
            row
            for row in audio_probe["streams"]
            if row.get("codec_type") == "audio"
        )
        recipe_path = run_root / recipe_rel
        write_yaml(
            recipe_path,
            {
                "schema_version": "idol_edit_recipe.v3",
                "content_id": content_id,
                "status": "locked_for_04fx",
                "owner": "04_edit",
                "source_edit_map": {
                    "path": edit_map_rel.as_posix(),
                    "sha256": sha256_file(run_root / edit_map_rel),
                },
                "source_edit_marker_plan": {
                    "path": marker_rel.as_posix(),
                    "sha256": sha256_file(run_root / marker_rel),
                },
                "audio_program": {
                    "path": audio_rel.as_posix(),
                    "sha256": sha256_file(audio_path),
                    "duration_seconds": float(audio_probe["format"]["duration"]),
                    "sample_rate": int(audio_stream["sample_rate"]),
                    "channel_layout": str(
                        audio_stream.get("channel_layout") or "mono"
                    ),
                    "start_sample": 0,
                },
                "audio_path": audio_rel.as_posix(),
                "timebase": {
                    "fps": {
                        "numerator": fps.numerator,
                        "denominator": fps.denominator,
                    },
                    "start_timecode": "00:00:00:00",
                    "drop_frame": False,
                    "frame_interval": "start_inclusive_end_exclusive",
                },
                "render_spec": {
                    "fps": {
                        "numerator": fps.numerator,
                        "denominator": fps.denominator,
                    },
                    "width": width,
                    "height": height,
                    "sample_aspect_ratio": "1/1",
                    "fit_mode": "fit_pad",
                    "background": "black",
                    "pixel_format": "yuv420p",
                },
                "color_pipeline": {
                    "input_interpretation": "Fixture sources interpreted as Rec.709 limited range.",
                    "working_space": "Rec.709 gamma 2.4",
                    "transform": "Explicit fixture Rec.709 pass-through override.",
                    "delivery": {
                        "color_range": "tv",
                        "color_space": "bt709",
                        "color_transfer": "bt709",
                        "color_primaries": "bt709",
                    },
                },
                "timeline": full_timeline,
                "boundary_handle_contracts": boundary_handles or [],
                "grade_profiles": {},
                "effects": effects or [],
                "delivery_policy": {
                    "mezzanine": {
                        "container": "mp4",
                        "video_codec": "libx264",
                        "audio_codec": "aac",
                        "chroma_policy": "yuv420p fixture delivery",
                    },
                    "platform_derivatives": [],
                    "audio_qc_targets": {
                        "integrated_lufs_target": None,
                        "true_peak_ceiling_dbtp": -1.0,
                        "normalization_policy": "analysis_only_no_auto_normalize",
                    },
                },
                "qc_requirements": {
                    "frame_step_cutpoint_qc": True,
                    "color_metadata_qc": True,
                    "audio_delivery_qc": True,
                    "retime_cadence_qc": True,
                    "black_and_silence_qc": True,
                },
            },
        )
        return recipe_path, run_root / edit_map_rel, run_root / marker_rel, audio_path

    def _strict_zero_fx_compile(
        self, run_root: Path, recipe_path: Path
    ) -> tuple[Path, Path, Path]:
        """Complete the mandatory audit without forcing an effect selection."""

        recipe = yaml.safe_load(recipe_path.read_text(encoding="utf-8"))
        content_id = str(recipe["content_id"])
        edit_map_rel = Path(str(recipe["source_edit_map"]["path"]))
        marker_rel = Path(str(recipe["source_edit_marker_plan"]["path"]))
        audio_rel = Path(str(recipe["audio_path"]))
        preview_rel = Path("generations/video/qc/previews/final-audit-preview-v1.mp4")
        write_bytes(run_root / preview_rel, self.source_a.read_bytes())
        fx_root_rel = Path("generations/video/qc/finishing-fx-v1")
        fx_map_rel = fx_root_rel / "04FX-finishing-map-v1.yaml"
        section_ids = list(
            dict.fromkeys(
                section_id
                for row in recipe["timeline"]
                for section_id in row["section_ids"]
            )
        )
        fps_spec = recipe["render_spec"]["fps"]
        fps = Fraction(int(fps_spec["numerator"]), int(fps_spec["denominator"]))
        event_priority = {
            "section_boundary": 0,
            "story_handoff": 4,
        }
        events_by_frame: dict[int, list[dict[str, Any]]] = {}
        for left, right in zip(recipe["timeline"], recipe["timeline"][1:]):
            frame = int(left["output_out_frame"])
            left_slot = str(left["slot"])
            right_slot = str(right["slot"])
            left_sections = sorted(set(map(str, left["section_ids"])))
            right_sections = sorted(set(map(str, right["section_ids"])))
            boundary_sections = sorted(set(left_sections + right_sections))
            frame_events = events_by_frame.setdefault(frame, [])
            frame_events.append(
                {
                    "event_id": f"recipe_cut:{left_slot}:{right_slot}:f{frame}",
                    "kind": "story_handoff",
                    "section_ids": boundary_sections,
                }
            )
            if left_sections and right_sections and left_sections != right_sections:
                frame_events.append(
                    {
                        "event_id": (
                            f"recipe_section:{'+'.join(left_sections)}>"
                            f"{'+'.join(right_sections)}:f{frame}"
                        ),
                        "kind": "section_boundary",
                        "section_ids": boundary_sections,
                    }
                )
        coverage_points: list[dict[str, Any]] = []
        expected_event_ids: list[str] = []
        for point_index, frame in enumerate(sorted(events_by_frame), start=1):
            frame_events = sorted(
                events_by_frame[frame], key=lambda event: str(event["event_id"])
            )
            event_ids = [str(event["event_id"]) for event in frame_events]
            kinds = sorted(
                {str(event["kind"]) for event in frame_events},
                key=event_priority.__getitem__,
            )
            point_sections = sorted(
                {
                    section_id
                    for event in frame_events
                    for section_id in event["section_ids"]
                }
            )
            expected_event_ids.extend(event_ids)
            coverage_points.append(
                {
                    "point_id": f"TP_FINAL_FIXTURE_{point_index:03d}",
                    "program_time": float(Fraction(frame, 1) / fps),
                    "program_frame": frame,
                    "kind": kinds[0],
                    "section_ids": point_sections,
                    "coverage_event_ids": event_ids,
                    "coverage_kinds": kinds,
                    "disposition": "none_needed",
                    "rationale": (
                        "Full-master playback confirms the accepted 04 cut or "
                        "04-owned base transition needs no additional 04FX effect."
                    ),
                }
            )
        coverage_payload = "".join(
            f"{event_id}\n" for event_id in sorted(set(expected_event_ids))
        )
        coverage_sha256 = hashlib.sha256(coverage_payload.encode("utf-8")).hexdigest()
        fx_map = {
            "schema_version": "idol_edit_finishing_fx.v2",
            "content_id": content_id,
            "status": "passed_for_final_render",
            "source_edit_map": edit_map_rel.as_posix(),
            "source_recipe": recipe_path.relative_to(run_root).as_posix(),
            "source_edit_marker_plan": marker_rel.as_posix(),
            "source_audio_or_cue_map": "research/audio-motion-director-map-v1.yaml",
            "effect_registry_ref": "automation/edit-effect-registry.yaml",
            "dependency_lock": {
                "digest_algorithm": "sha256",
                "source_edit_map_sha256": sha256_file(run_root / edit_map_rel),
                "source_recipe_sha256": sha256_file(recipe_path),
                "source_edit_marker_plan_sha256": sha256_file(run_root / marker_rel),
                "source_audio_or_cue_map_sha256": sha256_file(
                    run_root / "research/audio-motion-director-map-v1.yaml"
                ),
                "passed_preview_sha256": sha256_file(run_root / preview_rel),
            },
            "preview_gate": {
                "gate_type": "full_master",
                "section_ids": section_ids,
                "preview_path": preview_rel.as_posix(),
                "edit_preview_status": "passed",
                "fx_allowed": True,
            },
            "track_tone_world_guard": {
                "tone_and_manner": "The accepted fixture preview remains unchanged.",
                "world_space_preserve": "Preserve the complete test-frame geometry.",
                "identity_body_preserve": "Preserve the probe-backed source pixels.",
                "color_light_limits": "Do not add an unreviewed exposure effect.",
                "repeated_effect_drift_guard": "No 04FX effect is needed for this fixture.",
            },
            "transition_opportunity_audit": {
                "audit_status": "complete_no_fx_needed",
                "catalog_ref": (
                    "skills/idol-edit-finishing-fx/references/"
                    "local-ffmpeg-transition-effect-catalog.md"
                ),
                "coverage_contract": {
                    "coverage_version": "recipe_marker_audio_exact_v1",
                    "coverage_scope": "full_master",
                    "digest_algorithm": "sha256_sorted_utf8_lines_v1",
                    "expected_event_count": len(set(expected_event_ids)),
                    "covered_event_count": len(set(expected_event_ids)),
                    "expected_event_ids_sha256": coverage_sha256,
                    "covered_event_ids_sha256": coverage_sha256,
                },
                "safe_defaults_applied": False,
                "points": coverage_points,
            },
            "fx_records": [],
            "final_render_policy": {
                "include_only_passed_fx": True,
                "single_high_quality_render_after_fx_pass": True,
                "timing_change_returns_to_04_edit": True,
                "post_edit_transition_audit_required_before_final_master": True,
                "final_qc_no_new_creative_fx_by_default": True,
            },
            "automation_boundaries": [
                "The strict compiler may prove a completed zero-FX audit; it may not select an effect."
            ],
        }
        fx_map_path = run_root / fx_map_rel
        write_yaml(fx_map_path, fx_map)
        output = run_root / fx_root_rel / "final-recipe-zero-04fx-v1.yaml"
        manifest = run_root / fx_root_rel / "final-zero-04fx-compile-manifest-v1.yaml"
        result = self._run(
            [
                sys.executable,
                str(COMPILER),
                "--fx-map",
                str(fx_map_path),
                "--recipe",
                str(recipe_path),
                "--output",
                str(output),
                "--manifest",
                str(manifest),
                "--pass-only",
                "--merge-into-recipe",
            ]
        )
        self.assertEqual(0, result.returncode, result.stderr or result.stdout)
        manifest_payload = yaml.safe_load(manifest.read_text(encoding="utf-8"))
        self.assertEqual(
            "complete_no_fx_needed", manifest_payload["selection"]["audit_status"]
        )
        self.assertEqual([], manifest_payload["selection"]["selected_pass_fx_ids"])
        self.assertEqual([], manifest_payload["selection"]["compiled_fx_ids"])
        self.assertEqual(0, manifest_payload["compiled_output"]["compiled_04fx_count"])
        return output, manifest, fx_map_path

    def _smoke_effect(self, effect_type: str) -> dict[str, Any]:
        effect: dict[str, Any] = {
            "type": effect_type,
            "start": 8 / 24,
            "duration": 5 / 24,
            "start_frame": 8,
            "duration_frames": 5,
            "fx_id": f"FX_SMOKE_{effect_type.upper()}",
            "status": "draft",
            "origin": "04fx",
        }
        parameters: dict[str, dict[str, Any]] = {
            "flash": {"opacity": 0.4, "color": [255, 255, 255]},
            "dip_flash": {"opacity": 0.2, "color": [0, 0, 0]},
            "punch_zoom": {
                "factor": 1.04,
                "anchor_x": 0.5,
                "anchor_y": 0.5,
                "curve": "ease_in_out",
                "attack_frames": 1,
                "hold_frames": 3,
                "release_frames": 1,
            },
            "zoom_hold": {
                "factor": 1.035,
                "anchor_x": 0.45,
                "anchor_y": 0.45,
                "curve": "attack_hold_release",
                "attack_frames": 1,
                "hold_frames": 3,
                "release_frames": 1,
            },
            "micro_freeze": {},
            "blur_pulse": {"sigma": 1.2},
            "horizontal_blur_whip": {"sigma": 2.2, "sigma_v": 0.1},
            "tmix_smear": {"frames": 3},
            "unsharp_pulse": {"luma_amount": 0.6},
            "brightness_pulse": {"amount": 0.06},
            "color_pulse": {
                "brightness": 0.02,
                "contrast": 1.08,
                "saturation": 1.1,
                "gamma": 0.98,
            },
            "contrast_pulse": {"contrast": 1.1},
            "saturation_pulse": {"saturation": 1.15},
            "hue_pulse": {"degrees": 8, "saturation": 1.04},
            "temperature_pulse": {"temperature": 6200},
            "eq_grade_window": {
                "brightness": 0.02,
                "contrast": 1.05,
                "saturation": 1.04,
                "gamma": 0.98,
            },
            "vignette_pulse": {"vignette_angle": 0.52},
            "grain_pulse": {"strength": 6},
            "rgb_split": {"pixels": 2},
            "chromatic_shift": {"cbh": 2, "cbv": 0, "crh": -2, "crv": 0},
            "shake": {"amplitude": 3, "frequency_x": 10, "frequency_y": 13},
            "edge_flash": {},
            "drawtext_hit": {
                "text": "SIGNAL",
                "fontsize": 28,
                "fontcolor": "white",
                "x": "(w-text_w)/2",
                "y": "h*0.12",
            },
            "fade_to_black": {"opacity": 0.85},
            "fade_from_black": {"opacity": 0.85},
            "fade_to_white": {"opacity": 0.8},
            "fade_from_white": {"opacity": 0.8},
            "negate_flash": {},
            "pixelize_pulse": {"block": 8},
        }
        self.assertIn(effect_type, parameters, f"missing smoke fixture for {effect_type}")
        effect.update(parameters[effect_type])
        return effect

    def test_every_supported_single_stream_effect_executes_in_ffmpeg(self) -> None:
        supported = [
            name
            for name, spec in self.registry.effects.items()
            if spec.get("renderer_status") == "supported_now"
            and spec.get("timeline_class") == "single_stream"
        ]
        self.assertGreaterEqual(len(supported), 25)

        for effect_type in supported:
            with self.subTest(effect_type=effect_type):
                effect = self._smoke_effect(effect_type)
                filters = renderer.effect_filter_chain(
                    [effect],
                    input_label="0:v",
                    output_label="vout",
                    width=320,
                    height=180,
                    total_duration=1.5,
                    fps=Fraction(24, 1),
                    pixel_format="yuv420p",
                )
                result = self._run(
                    [
                        self.ffmpeg,
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-f",
                        "lavfi",
                        "-i",
                        "testsrc2=size=320x180:rate=24:duration=1.5",
                        "-filter_complex",
                        ";".join(filters),
                        "-map",
                        "[vout]",
                        "-frames:v",
                        "36",
                        "-f",
                        "null",
                        "-",
                    ]
                )
                self.assertEqual(0, result.returncode, result.stderr)

    def test_every_registered_named_xfade_transition_executes_in_ffmpeg(self) -> None:
        self.assertGreaterEqual(len(self.registry.transitions), 50)
        self.assertNotIn("custom", self.registry.transitions)
        for transition in sorted(self.registry.transitions):
            with self.subTest(transition=transition):
                result = self._run(
                    [
                        self.ffmpeg,
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-f",
                        "lavfi",
                        "-i",
                        "testsrc2=size=320x180:rate=24:duration=0.5",
                        "-f",
                        "lavfi",
                        "-i",
                        "color=c=navy:size=320x180:rate=24:duration=0.5",
                        "-filter_complex",
                        (
                            f"[0:v][1:v]xfade=transition={transition}:"
                            "duration=0.125:offset=0.375[vout]"
                        ),
                        "-map",
                        "[vout]",
                        "-f",
                        "null",
                        "-",
                    ]
                )
                self.assertEqual(0, result.returncode, result.stderr)

    def _preview_compile_fixture(self, root: Path) -> tuple[Path, Path, Path, Path]:
        recipe_path = root / "recipe.yaml"
        fx_map_path = root / "fx-map.yaml"
        output_path = root / "compiled-recipe.yaml"
        manifest_path = root / "compile-manifest.yaml"
        write_yaml(
            recipe_path,
            {
                "schema_version": "idol_edit_recipe.v3",
                "render_spec": {
                    "fps": {"numerator": 24, "denominator": 1},
                    "width": 320,
                    "height": 180,
                    "fit_mode": "fit_pad",
                    "pixel_format": "yuv420p",
                },
                "effects": [{"type": "hard_cut_note", "note": "04 base effect"}],
            },
        )
        records = [
            (
                "FX_DRAW_TEXT",
                "drawtext_hit",
                {
                    "text": "SIGNAL",
                    "fontsize": 52,
                    "fontcolor": "white",
                    "x": "(w-text_w)/2",
                    "y": "h*0.12",
                },
            ),
            (
                "FX_EQ_GRADE",
                "eq_grade_window",
                {
                    "brightness": 0.02,
                    "contrast": 1.06,
                    "saturation": 1.04,
                    "gamma": 0.98,
                },
            ),
            ("FX_TEMPERATURE", "temperature_pulse", {"temperature": 6200}),
            ("FX_HUE", "hue_pulse", {"degrees": 9, "saturation": 1.03}),
            ("FX_TMIX", "tmix_smear", {"frames": 4}),
        ]
        write_yaml(
            fx_map_path,
            {
                "schema_version": "preview-fixture",
                "fx_records": [
                    {
                        "fx_id": fx_id,
                        "status": "draft",
                        "time_range": f"{index / 2:.3f}-{index / 2 + 0.25:.3f}",
                        "effect_design": {
                            "effect_type": effect_type,
                            "duration_frames": 6,
                            "program_start_frame": index * 12,
                            "program_start_seconds": index / 2,
                            "renderer_status": "supported_now",
                            "parameters": parameters,
                        },
                    }
                    for index, (fx_id, effect_type, parameters) in enumerate(records, 1)
                ],
            },
        )
        return recipe_path, fx_map_path, output_path, manifest_path

    def test_compiler_preserves_typed_parameters_and_hash_bindings(self) -> None:
        root = self.temp_root / "compiler-preserve"
        recipe, fx_map, output, manifest = self._preview_compile_fixture(root)
        result = self._run(
            [
                sys.executable,
                str(COMPILER),
                "--fx-map",
                str(fx_map),
                "--recipe",
                str(recipe),
                "--output",
                str(output),
                "--manifest",
                str(manifest),
                "--merge-into-recipe",
            ]
        )
        self.assertEqual(0, result.returncode, result.stderr)

        compiled_recipe = yaml.safe_load(output.read_text(encoding="utf-8"))
        effects = {
            effect.get("fx_id"): effect
            for effect in compiled_recipe["effects"]
            if effect.get("origin") == "04fx"
        }
        self.assertEqual("SIGNAL", effects["FX_DRAW_TEXT"]["text"])
        self.assertEqual(52, effects["FX_DRAW_TEXT"]["fontsize"])
        self.assertEqual(0.02, effects["FX_EQ_GRADE"]["brightness"])
        self.assertEqual(0.98, effects["FX_EQ_GRADE"]["gamma"])
        self.assertEqual(6200, effects["FX_TEMPERATURE"]["temperature"])
        self.assertEqual(9, effects["FX_HUE"]["degrees"])
        self.assertEqual(4, effects["FX_TMIX"]["frames"])
        self.assertEqual("hard_cut_note", compiled_recipe["effects"][0]["type"])

        compile_manifest = yaml.safe_load(manifest.read_text(encoding="utf-8"))
        self.assertEqual(
            sha256_file(recipe), compile_manifest["source_bindings"]["recipe"]["sha256"]
        )
        self.assertEqual(
            sha256_file(fx_map), compile_manifest["source_bindings"]["fx_map"]["sha256"]
        )
        self.assertEqual(
            sha256_file(ROOT / "automation" / "edit-effect-registry.yaml"),
            compile_manifest["source_bindings"]["effect_registry"]["sha256"],
        )
        self.assertEqual(
            sha256_file(output), compile_manifest["compiled_output"]["sha256"]
        )
        self.assertEqual(5, compile_manifest["compiled_output"]["compiled_04fx_count"])
        self.assertEqual([], compile_manifest["selection"]["skipped_pass_fx_ids"])

    def test_compiler_rejects_unknown_parameters_and_unrenderable_pass(self) -> None:
        for case_name, effect_type, status, renderer_status, parameters in (
            ("unknown-parameter", "dip_flash", "draft", "supported_now", {"bogus": 1}),
            ("unrenderable-pass", "dip_flash", "pass", "needs_script_extension", {"opacity": 0.2}),
            ("metadata-only-pass", "hard_cut_note", "pass", "metadata_only", {}),
        ):
            with self.subTest(case_name=case_name):
                root = self.temp_root / f"compiler-{case_name}"
                recipe = root / "recipe.yaml"
                fx_map = root / "fx-map.yaml"
                output = root / "output.yaml"
                manifest = root / "manifest.yaml"
                write_yaml(
                    recipe,
                    {
                        "schema_version": "idol_edit_recipe.v3",
                        "render_spec": {
                            "fps": {"numerator": 24, "denominator": 1},
                            "width": 320,
                            "height": 180,
                        },
                    },
                )
                write_yaml(
                    fx_map,
                    {
                        "fx_records": [
                            {
                                "fx_id": "FX_FAIL_CLOSED",
                                "status": status,
                                "time_range": "0.500-0.750",
                                "effect_design": {
                                    "effect_type": effect_type,
                                    "duration_frames": 6,
                                    "program_start_frame": 12,
                                    "program_start_seconds": 0.5,
                                    "renderer_status": renderer_status,
                                    "parameters": parameters,
                                },
                            }
                        ]
                    },
                )
                result = self._run(
                    [
                        sys.executable,
                        str(COMPILER),
                        "--fx-map",
                        str(fx_map),
                        "--recipe",
                        str(recipe),
                        "--output",
                        str(output),
                        "--manifest",
                        str(manifest),
                        "--statuses",
                        status,
                        "--merge-into-recipe",
                    ]
                )
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(output.exists())
                self.assertFalse(manifest.exists())

    def test_compiler_rejects_conflicting_duplicate_parameter_sources(self) -> None:
        root = self.temp_root / "compiler-conflicting-parameter"
        recipe = root / "recipe.yaml"
        fx_map = root / "fx-map.yaml"
        output = root / "output.yaml"
        manifest = root / "manifest.yaml"
        write_yaml(
            recipe,
            {
                "schema_version": "idol_edit_recipe.v3",
                "render_spec": {
                    "fps": {"numerator": 24, "denominator": 1},
                    "width": 320,
                    "height": 180,
                },
            },
        )
        write_yaml(
            fx_map,
            {
                "fx_records": [
                    {
                        "fx_id": "FX_CONFLICT",
                        "status": "draft",
                        "effect_design": {
                            "effect_type": "dip_flash",
                            "duration_frames": 6,
                            "program_start_frame": 12,
                            "program_start_seconds": 0.5,
                            "renderer_status": "supported_now",
                            "opacity": 0.7,
                            "parameters": {"opacity": 0.2},
                        },
                    }
                ]
            },
        )
        result = self._run(
            [
                sys.executable,
                str(COMPILER),
                "--fx-map",
                str(fx_map),
                "--recipe",
                str(recipe),
                "--output",
                str(output),
                "--manifest",
                str(manifest),
                "--merge-into-recipe",
            ]
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("conflicting duplicate values", result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse(manifest.exists())

    def _final_compile_fixture(self, fixture_id: str) -> tuple[Path, Path, Path, Path]:
        run_root = self.temp_root / "runs" / "aurora-m" / "fx-contract" / fixture_id
        timeline = [
            {
                "slot": "R01",
                "source": "source-a.mp4",
                "section_ids": ["S00"],
                "source_in": 0.25,
                "source_out": 1.25,
                "output_in_frame": 0,
                "output_out_frame": 24,
                "duration_frames": 24,
            },
            {
                "slot": "R02",
                "source": "source-b.mp4",
                "section_ids": ["S01"],
                "source_in": 0.25,
                "source_out": 1.25,
                "output_in_frame": 24,
                "output_out_frame": 48,
                "duration_frames": 24,
            },
        ]
        recipe_path, edit_map_path, marker_path, audio_path = (
            self._write_v3_recipe_fixture(
                run_root=run_root,
                fps=Fraction(24, 1),
                width=320,
                height=180,
                timeline=timeline,
            )
        )
        edit_map_rel = edit_map_path.relative_to(run_root)
        marker_rel = marker_path.relative_to(run_root)
        recipe_rel = recipe_path.relative_to(run_root)
        audio_rel = audio_path.relative_to(run_root)
        preview_rel = Path("generations/video/qc/previews/S00-S01-preview-v1.mp4")
        fx_preview_rel = Path(
            "generations/video/qc/finishing-fx-v1/FX_S00_LIGHT_CARRY-preview-v1.mp4"
        )
        fx_sheet_rel = Path(
            "generations/video/qc/finishing-fx-v1/FX_S00_LIGHT_CARRY-contact-sheet-v1.png"
        )
        fx_map_rel = Path(
            "generations/video/qc/finishing-fx-v1/04FX-finishing-map-v1.yaml"
        )
        write_bytes(run_root / preview_rel, self.source_a.read_bytes())
        write_bytes(run_root / fx_preview_rel, self.source_a.read_bytes())
        (run_root / fx_sheet_rel).parent.mkdir(parents=True, exist_ok=True)
        self._run(
            [
                self.ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(run_root / fx_preview_rel),
                "-frames:v",
                "1",
                str(run_root / fx_sheet_rel),
            ],
            check=True,
        )

        required_checks = [
            "timing_feel",
            "identity_body_preserved",
            "full_space_world_preserved",
            "tone_manner_preserved",
            "mobile_readable",
            "flicker_flash_safe",
            "source_quality_not_hidden",
            "repeated_effect_drift_checked",
        ]
        fx_map = {
            "schema_version": "idol_edit_finishing_fx.v2",
            "content_id": fixture_id,
            "status": "passed_for_final_render",
            "source_edit_map": edit_map_rel.as_posix(),
            "source_recipe": recipe_rel.as_posix(),
            "source_edit_marker_plan": marker_rel.as_posix(),
            "source_audio_or_cue_map": "research/audio-motion-director-map-v1.yaml",
            "effect_registry_ref": "automation/edit-effect-registry.yaml",
            "dependency_lock": {
                "digest_algorithm": "sha256",
                "source_edit_map_sha256": sha256_file(run_root / edit_map_rel),
                "source_recipe_sha256": sha256_file(run_root / recipe_rel),
                "source_edit_marker_plan_sha256": sha256_file(run_root / marker_rel),
                "source_audio_or_cue_map_sha256": sha256_file(
                    run_root / "research/audio-motion-director-map-v1.yaml"
                ),
                "passed_preview_sha256": sha256_file(run_root / preview_rel),
            },
            "preview_gate": {
                "gate_type": "full_master",
                "section_ids": ["S00", "S01"],
                "preview_path": preview_rel.as_posix(),
                "edit_preview_status": "passed",
                "fx_allowed": True,
            },
            "track_tone_world_guard": {
                "tone_and_manner": "Keep the restrained blue-black track tone.",
                "world_space_preserve": "Keep corridor depth and the practical light route.",
                "identity_body_preserve": "Keep face, hands, feet, and body path readable.",
                "color_light_limits": "No clipped whites or exposure pumping.",
                "repeated_effect_drift_guard": "Use this light carry once.",
            },
            "transition_opportunity_audit": {
                "audit_status": "complete_fx_passed",
                "catalog_ref": (
                    "skills/idol-edit-finishing-fx/references/"
                    "local-ffmpeg-transition-effect-catalog.md"
                ),
                "coverage_contract": {
                    "coverage_version": "recipe_marker_audio_exact_v1",
                    "coverage_scope": "full_master",
                    "digest_algorithm": "sha256_sorted_utf8_lines_v1",
                    "expected_event_count": 2,
                    "covered_event_count": 2,
                    "expected_event_ids_sha256": hashlib.sha256(
                        (
                            "recipe_cut:R01:R02:f24\n"
                            "recipe_section:S00>S01:f24\n"
                        ).encode("utf-8")
                    ).hexdigest(),
                    "covered_event_ids_sha256": hashlib.sha256(
                        (
                            "recipe_cut:R01:R02:f24\n"
                            "recipe_section:S00>S01:f24\n"
                        ).encode("utf-8")
                    ).hexdigest(),
                },
                "points": [
                    {
                        "point_id": "TP_S00_S01",
                        "program_time": 1.0,
                        "program_frame": 24,
                        "kind": "section_boundary",
                        "section_ids": ["S00", "S01"],
                        "coverage_event_ids": [
                            "recipe_cut:R01:R02:f24",
                            "recipe_section:S00>S01:f24",
                        ],
                        "coverage_kinds": ["section_boundary", "story_handoff"],
                        "disposition": "manual_fx_proposed",
                        "proposed_effect_type": "dip_flash",
                        "fx_id_ref": "FX_S00_LIGHT_CARRY",
                        "rationale": "The passed hard cut benefits from one restrained dip.",
                    }
                ],
            },
            "fx_records": [
                {
                    "fx_id": "FX_S00_LIGHT_CARRY",
                    "section_ids": ["S00", "S01"],
                    "time_range": "1.000-1.250",
                    "source_edit_segment_refs": ["SEG_R01", "SEG_R02"],
                    "eligibility": {
                        "edit_preview_passed": True,
                        "edit_boundary_timing_locked": True,
                        "source_action_marker_known": True,
                        "effect_job": "transition_bridge",
                    },
                    "trigger": {
                        "audio_or_section_cue": "The section stop at frame 24.",
                        "source_action_marker": "The coat edge clears before the foot plant.",
                    },
                    "visible_basis": "The outgoing coat edge crosses the lens.",
                    "effect_design": {
                        "effect_type": "dip_flash",
                        "duration_frames": 6,
                        "program_start_frame": 24,
                        "program_start_seconds": 1.0,
                        "opacity": 0.22,
                        "renderer_status": "supported_now",
                        "visible_action": "A restrained dark dip follows the coat edge.",
                        "endpoint": "The dip clears before the incoming face appears.",
                    },
                    "reason_it_helps": "It signs the section change without changing timing.",
                    "protection_guards": {
                        "face_hand_foot_body": "Do not cover the face, hands, or planted foot.",
                        "full_space_world": "Keep corridor depth visible.",
                        "tone_and_manner": "Keep the practical-light treatment.",
                        "timing_feel": "End before the next pickup.",
                        "mobile_readability": "Keep the face readable on mobile.",
                    },
                    "fail_conditions": ["Reject if it makes the cut feel late."],
                    "preview_qc": {
                        "preview_path": fx_preview_rel.as_posix(),
                        "preview_sha256": sha256_file(run_root / fx_preview_rel),
                        "contact_sheet_path": fx_sheet_rel.as_posix(),
                        "contact_sheet_sha256": sha256_file(run_root / fx_sheet_rel),
                        "checks": required_checks,
                        "qc_note": "The recorded preview keeps the body readable.",
                    },
                    "status": "pass",
                }
            ],
            "final_render_policy": {
                "include_only_passed_fx": True,
                "single_high_quality_render_after_fx_pass": True,
                "timing_change_returns_to_04_edit": True,
                "post_edit_transition_audit_required_before_final_master": True,
                "final_qc_no_new_creative_fx_by_default": True,
            },
            "automation_boundaries": [
                "Automation validates paths and hashes only; it does not infer pass."
            ],
        }
        write_yaml(run_root / fx_map_rel, fx_map)
        return run_root, recipe_path, run_root / fx_map_rel, run_root / preview_rel

    def test_final_compiler_is_pass_complete_and_recipe_hash_fail_closed(self) -> None:
        run_root, recipe, fx_map, _preview = self._final_compile_fixture(
            "FX_COMPILE_PASS_001"
        )
        output = run_root / "generations/video/qc/finishing-fx-v1/final-compiled.yaml"
        manifest = run_root / "generations/video/qc/finishing-fx-v1/final-manifest.yaml"
        command = [
            sys.executable,
            str(COMPILER),
            "--fx-map",
            str(fx_map),
            "--recipe",
            str(recipe),
            "--output",
            str(output),
            "--manifest",
            str(manifest),
            "--pass-only",
            "--merge-into-recipe",
        ]
        result = self._run(command)
        self.assertEqual(0, result.returncode, result.stderr)
        payload = yaml.safe_load(manifest.read_text(encoding="utf-8"))
        self.assertEqual(
            ["FX_S00_LIGHT_CARRY"], payload["selection"]["selected_pass_fx_ids"]
        )
        self.assertEqual(
            payload["selection"]["selected_pass_fx_ids"],
            payload["selection"]["compiled_fx_ids"],
        )
        self.assertEqual([], payload["selection"]["skipped_pass_fx_ids"])

        stale_root, stale_recipe, stale_fx_map, _ = self._final_compile_fixture(
            "FX_COMPILE_STALE_001"
        )
        stale_recipe.write_text(
            stale_recipe.read_text(encoding="utf-8") + "\nstale_change: true\n",
            encoding="utf-8",
        )
        stale_output = stale_root / "generations/video/qc/finishing-fx-v1/stale.yaml"
        stale_manifest = stale_root / "generations/video/qc/finishing-fx-v1/stale-manifest.yaml"
        stale_result = self._run(
            [
                sys.executable,
                str(COMPILER),
                "--fx-map",
                str(stale_fx_map),
                "--recipe",
                str(stale_recipe),
                "--output",
                str(stale_output),
                "--manifest",
                str(stale_manifest),
                "--pass-only",
                "--merge-into-recipe",
            ]
        )
        self.assertNotEqual(0, stale_result.returncode)
        self.assertIn("source_recipe_sha256 mismatch", stale_result.stderr)
        self.assertFalse(stale_output.exists())
        self.assertFalse(stale_manifest.exists())

    def test_edit_map_strict_final_render_gate_accepts_immutable_compile_chain(self) -> None:
        run_root = self.temp_root / "runs" / "aurora-m" / "final-gate" / "EDIT_FINAL_GATE_001"
        recipe, edit_map, _marker, _audio = self._write_v3_recipe_fixture(
            run_root=run_root,
            fps=Fraction(24, 1),
            width=320,
            height=180,
            timeline=[
                {
                    "slot": "R01",
                    "source": "source-a.mp4",
                    "section_ids": ["S00"],
                    "source_in": 0.25,
                    "source_out": 1.25,
                    "output_in_frame": 0,
                    "output_out_frame": 24,
                    "duration_frames": 24,
                }
            ],
        )
        final_recipe, manifest, _fx_map = self._strict_zero_fx_compile(
            run_root, recipe
        )
        result = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "final-render",
                str(edit_map),
            ]
        )
        self.assertEqual(0, result.returncode, result.stderr or result.stdout)
        self.assertIn("ready for final render", result.stdout)

        edit_map_payload = yaml.safe_load(edit_map.read_text(encoding="utf-8"))
        edit_map_payload["status"] = "draft"
        write_yaml(edit_map, edit_map_payload)
        draft_status = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "final-render",
                str(edit_map),
            ]
        )
        self.assertNotEqual(0, draft_status.returncode)
        self.assertIn("top-level edit status must be", draft_status.stderr)

        edit_map_payload["status"] = "locked_for_final_render"
        edit_map_payload["manual_adjustment_workflow"].pop("active_candidate_status")
        write_yaml(edit_map, edit_map_payload)
        missing_candidate_pass = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "final-render",
                str(edit_map),
            ]
        )
        self.assertNotEqual(0, missing_candidate_pass.returncode)
        self.assertIn("active_candidate_status must explicitly pass", missing_candidate_pass.stderr)

        edit_map_payload["manual_adjustment_workflow"]["active_candidate_status"] = "passed"
        write_yaml(edit_map, edit_map_payload)

        manifest.write_text(
            manifest.read_text(encoding="utf-8") + "\nstale: true\n",
            encoding="utf-8",
        )
        stale = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "final-render",
                str(edit_map),
            ]
        )
        self.assertNotEqual(0, stale.returncode)
        self.assertIn("schema validation failed", stale.stderr)
        self.assertTrue(final_recipe.is_file())

    def test_closeout_gate_binds_render_delivery_and_cutpoint_receipts(self) -> None:
        run_root = self.temp_root / "runs" / "aurora-m" / "closeout-gate" / "EDIT_CLOSEOUT_GATE_001"
        recipe, edit_map_path, marker_path, audio_path = self._write_v3_recipe_fixture(
            run_root=run_root,
            fps=Fraction(24, 1),
            width=320,
            height=180,
            timeline=[
                {
                    "slot": "R01",
                    "source": "source-a.mp4",
                    "section_ids": ["S00"],
                    "source_in": 0.25,
                    "source_out": 1.25,
                    "output_in_frame": 0,
                    "output_out_frame": 24,
                    "duration_frames": 24,
                }
            ],
        )
        final_recipe, fx_manifest, fx_map = self._strict_zero_fx_compile(
            run_root, recipe
        )
        master = run_root / "master.mp4"
        render_manifest = run_root / "render-manifest.yaml"
        render_result = self._run(
            [
                sys.executable,
                str(RENDERER),
                "--run-root",
                str(run_root),
                "--recipe",
                str(final_recipe),
                "--output",
                str(master),
                "--profile",
                "final",
                "--render-mode",
                "filter",
                "--fx-compile-manifest",
                str(fx_manifest),
                "--render-manifest",
                str(render_manifest),
            ]
        )
        self.assertEqual(0, render_result.returncode, render_result.stderr)

        delivery_report = run_root / "generations/video/qc/final-delivery-qc.yaml"
        delivery_result = self._run(
            [
                sys.executable,
                str(DELIVERY_QC),
                "--video",
                str(master),
                "--recipe",
                str(final_recipe),
                "--output",
                str(delivery_report),
            ]
        )
        self.assertEqual(0, delivery_result.returncode, delivery_result.stderr)
        delivery = yaml.safe_load(delivery_report.read_text(encoding="utf-8"))
        self.assertEqual("measurement_complete", delivery["status"])

        cutpoint_manifest = run_root / "generations/video/qc/cutpoint-frame-step-manifest.yaml"
        write_yaml(
            cutpoint_manifest,
            {
                "schema_version": "idol_edit_cutpoint_sheet_manifest.v1",
                "plan": {"path": str(marker_path), "sha256": sha256_file(marker_path)},
                "rendered_video": {
                    "path": str(master),
                    "sha256": sha256_file(master),
                    "fps": {"numerator": 24, "denominator": 1},
                    "observed_fps_float": 24.0,
                    "frame_count": 24,
                },
                "frame_zero_definition": "incoming_slot_first_frame",
                "frame_extraction": "single_pass_sequential_decode_no_random_gop_seek",
                "drop_frame_timecode": False,
                "entries": [],
                "interpretation_boundary": "review_surface_only_no_automatic_cut_pass",
            },
        )

        keeper = run_root / "generations/video/qc/source-keeper-index.yaml"
        cleanup = run_root / "generations/video/qc/cache-cleanup-manifest.yaml"
        final_sheet = run_root / "generations/video/qc/final-contact-sheet.png"
        mismatch = run_root / "generations/video/qc/source-family-review.md"
        for path, data in (
            (keeper, b"sources: [source-a.mp4]\n"),
            (cleanup, b"kept: [master.mp4]\n"),
            (final_sheet, b"fixture contact sheet\n"),
            (mismatch, b"# Source family review\n\nPass.\n"),
        ):
            write_bytes(path, data)

        receipt = yaml.safe_load(render_manifest.read_text(encoding="utf-8"))
        recipe_payload = yaml.safe_load(final_recipe.read_text(encoding="utf-8"))
        output = receipt["output"]
        loudness = delivery["audio_measurements"]["master"]["loudness"]
        decoded = delivery["audio_measurements"]["master"]["decoded_samples"]
        silence = delivery["audio_measurements"]["master"]["silence"]
        color_tags = {
            key: output[key]
            for key in ("color_range", "color_space", "color_transfer", "color_primaries")
        }
        closeout_path = run_root / "edit-closeout-v3.yaml"
        closeout = {
            "schema_version": "idol_edit_qc_closeout.v3",
            "content_id": run_root.name,
            "status": "ready_for_05",
            "final_master": {
                "path": str(master),
                "sha256": sha256_file(master),
                "duration_seconds": output["duration_seconds"],
                "fps": receipt["render_spec"]["fps"],
                "frame_count": output["frame_count"],
                "width": output["width"],
                "height": output["height"],
                "pixel_format": output["pixel_format"],
                "container": receipt["encoding"]["container"],
                "video_codec": output["video_codec"],
                "audio_codec": output["audio_codec"],
                "sample_aspect_ratio": recipe_payload["render_spec"]["sample_aspect_ratio"],
                "color_tags": color_tags,
                "delivery_geometry": "320x180 fixture",
                "geometry_policy": "founder_specified",
            },
            "final_recipe": {
                "path": str(final_recipe),
                "sha256": sha256_file(final_recipe),
                "schema_version": "idol_edit_recipe.v3",
                "status": "final_render_ready",
                "validation_status": "pass",
                "source_clean_lineage_checked": True,
                "render_engine": "local_ffmpeg",
            },
            "runtime_cache_ladder": {
                "completed_stages": ["single_full_quality_final_render", "final_qc"],
                "full_quality_final_render_count": 1,
            },
            "source_inventory": {
                "recipe_source_count": 1,
                "missing_source_count": 0,
                "source_keeper_index": str(keeper),
                "source_keeper_index_sha256": sha256_file(keeper),
                "recipe_source_hashes_verified": True,
                "raw_sources": ["generations/video/raw/source-a.mp4"],
                "generated_sources": [],
            },
            "qc_artifacts": {
                "final_contact_sheet": str(final_sheet),
                "cutpoint_sheets": [],
                "blackdetect_report": str(delivery_report),
                "silence_report": str(delivery_report),
                "source_family_mismatch_report": str(mismatch),
                "audio_delivery_report": str(delivery_report),
                "color_metadata_report": str(delivery_report),
                "retime_cadence_report": str(delivery_report),
            },
            "tone_quality_qc": {
                "tone_grade_consistency_checked": True,
                "source_family_mismatch_checked": True,
                "quality_mismatch_checked": True,
                "remaining_watch_items": [],
            },
            "cache_cleanup": {
                "manifest_path": str(cleanup),
                "kept_artifacts": [str(master), str(final_recipe)],
                "deleted_artifacts": [],
                "review_status": "complete",
                "protected_artifacts_preserved": True,
            },
            "render_lineage": {
                "fx_compile_manifest": {
                    "path": str(fx_manifest),
                    "sha256": sha256_file(fx_manifest),
                    "validation_status": "pass",
                },
                "final_render_manifest": {
                    "path": str(render_manifest),
                    "sha256": sha256_file(render_manifest),
                    "validation_status": "pass",
                },
                "hash_chain_status": "pass",
            },
            "professional_qc": {
                "delivery_qc_report": {
                    "path": str(delivery_report),
                    "sha256": sha256_file(delivery_report),
                    "validation_status": "pass",
                },
                "frame_step_cutpoint_manifest": {
                    "path": str(cutpoint_manifest),
                    "sha256": sha256_file(cutpoint_manifest),
                    "validation_status": "pass",
                },
                "program_integrity": {
                    "expected_frame_count": 24,
                    "actual_frame_count": 24,
                    "duration_delta_frames": 0,
                    "fps_match": True,
                    "geometry_match": True,
                    "sample_aspect_ratio_match": True,
                    "frame_step_cutpoints_checked": True,
                    "status": "pass",
                },
                "color_delivery": {
                    "metadata_checked": True,
                    "source_interpretation_checked": True,
                    "working_to_delivery_transform_checked": True,
                    "pixel_format": output["pixel_format"],
                    **color_tags,
                    "status": "pass",
                },
                "audio_delivery": {
                    "selected_audio_sha256": recipe_payload["audio_program"]["sha256"],
                    "sample_rate": recipe_payload["audio_program"]["sample_rate"],
                    "channel_layout": recipe_payload["audio_program"]["channel_layout"],
                    "integrated_lufs": loudness["integrated_lufs"],
                    "lra_lu": loudness["loudness_range_lu"],
                    "true_peak_dbtp": loudness["true_peak_dbtp"],
                    "clipping_sample_count": decoded["samples_at_or_above_threshold"],
                    "lead_silence_seconds": silence["lead_silence_seconds"],
                    "trail_silence_seconds": silence["trail_silence_seconds"],
                    "audio_video_duration_delta_seconds": 0.0,
                    "normalization_policy": "analysis_only_no_auto_normalize",
                    "status": "pass",
                },
                "retime_cadence": {
                    "retimed_segment_count": 0,
                    "duplicate_candidate_count": delivery["video_measurements"]["frame_hash_cadence"].get("adjacent_exact_duplicate_pairs", 0),
                    "judder_candidate_count": 0,
                    "cadence_measurement_checked": True,
                    "body_identity_playback_checked": True,
                    "status": "pass",
                },
                "black_silence": {
                    "blackdetect_checked": True,
                    "unintended_black_frame_count": 0,
                    "silence_checked": True,
                    "unintended_silence_count": 0,
                    "status": "pass",
                },
                "manual_playback": {
                    "identity_body_preserved": True,
                    "hands_feet_cadence_reviewed": True,
                    "story_continuity_reviewed": True,
                    "mobile_readability_reviewed": True,
                    "review_note": "Synthetic fixture playback checked.",
                    "status": "pass",
                },
            },
            "social_derivative_policy": {
                "public_source": "final_master",
                "raw_source_public_use": "not_allowed",
            },
            "platform_derivatives": [],
        }
        write_yaml(closeout_path, closeout)

        edit_map = yaml.safe_load(edit_map_path.read_text(encoding="utf-8"))
        edit_map["recipe_qc_contract"]["final_render_status"] = "qc_pass"
        edit_map["effect_audit_summary"]["compile_status"] = "pass"
        edit_map["effect_audit_summary"]["transition_opportunity_audit_status"] = "complete_no_fx_needed"
        edit_map["final_closeout_inventory"].update(
            {
                "sha256": sha256_file(closeout_path),
                "status": "ready_for_05",
                "validation_status": "pass",
            }
        )
        write_yaml(edit_map_path, edit_map)

        closeout_result = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "closeout",
                str(edit_map_path),
            ]
        )
        self.assertEqual(
            0, closeout_result.returncode, closeout_result.stderr or closeout_result.stdout
        )
        self.assertIn("ready for 05", closeout_result.stdout)

        closeout["schema_version"] = "idol_edit_qc_closeout.v2"
        write_yaml(closeout_path, closeout)
        edit_map["final_closeout_inventory"]["sha256"] = sha256_file(closeout_path)
        write_yaml(edit_map_path, edit_map)
        legacy_closeout = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "closeout",
                str(edit_map_path),
            ]
        )
        self.assertNotEqual(0, legacy_closeout.returncode)
        self.assertIn("requires idol_edit_qc_closeout.v3", legacy_closeout.stderr)

        closeout["schema_version"] = "idol_edit_qc_closeout.v3"
        closeout["professional_qc"]["black_silence"]["unintended_black_frame_count"] = 1
        write_yaml(closeout_path, closeout)
        edit_map["final_closeout_inventory"]["sha256"] = sha256_file(closeout_path)
        write_yaml(edit_map_path, edit_map)
        blocked = self._run(
            [
                "ruby",
                str(EDIT_MAP_READINESS),
                "--mode",
                "closeout",
                str(edit_map_path),
            ]
        )
        self.assertNotEqual(0, blocked.returncode)
        self.assertIn("schema validation failed", blocked.stderr)

    def _render_recipe(
        self,
        *,
        name: str,
        fps: Fraction,
        width: int,
        height: int,
        frame_count: int,
        timeline: list[dict[str, Any]],
        effects: list[dict[str, Any]] | None = None,
        boundary_handles: list[dict[str, Any]] | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        content_id = re.sub(r"[^A-Z0-9_-]", "_", name.upper())[:80]
        run_root = self.temp_root / "runs" / "aurora-m" / "render-contract" / content_id
        recipe, _edit_map, _marker, _audio = self._write_v3_recipe_fixture(
            run_root=run_root,
            fps=fps,
            width=width,
            height=height,
            timeline=timeline,
            effects=effects,
            boundary_handles=boundary_handles,
        )
        final_recipe, fx_manifest, _fx_map = self._strict_zero_fx_compile(
            run_root, recipe
        )
        output = run_root / "master.mp4"
        receipt = run_root / "render-manifest.yaml"
        result = self._run(
            [
                sys.executable,
                str(RENDERER),
                "--run-root",
                str(run_root),
                "--recipe",
                str(final_recipe),
                "--output",
                str(output),
                "--profile",
                "final",
                "--render-mode",
                "filter",
                "--fx-compile-manifest",
                str(fx_manifest),
                "--render-manifest",
                str(receipt),
            ]
        )
        self.assertEqual(0, result.returncode, result.stderr)
        receipt_payload = yaml.safe_load(receipt.read_text(encoding="utf-8"))
        probe = renderer.ffprobe_media(output)
        video = next(row for row in probe["streams"] if row["codec_type"] == "video")
        self.assertEqual(frame_count, int(video["nb_frames"]))
        self.assertEqual(
            sha256_file(fx_manifest),
            receipt_payload["source_bindings"]["fx_compile_manifest"]["sha256"],
        )
        return receipt_payload, video

    def test_final_render_rejects_missing_audit_compile_manifest_immediately(self) -> None:
        run_root = (
            self.temp_root
            / "runs"
            / "aurora-m"
            / "missing-audit"
            / "FINAL_MISSING_AUDIT_MANIFEST"
        )
        recipe, _edit_map, _marker, _audio = self._write_v3_recipe_fixture(
            run_root=run_root,
            fps=Fraction(24, 1),
            width=320,
            height=180,
            timeline=[
                {
                    "slot": "R01",
                    "source": "source-a.mp4",
                    "section_ids": ["S00"],
                    "source_in": 0.25,
                    "source_out": 1.25,
                    "output_in_frame": 0,
                    "output_out_frame": 24,
                    "duration_frames": 24,
                }
            ],
        )
        output = run_root / "master-without-audit.mp4"
        receipt = run_root / "render-without-audit-manifest.yaml"
        result = self._run(
            [
                sys.executable,
                str(RENDERER),
                "--run-root",
                str(run_root),
                "--recipe",
                str(recipe),
                "--output",
                str(output),
                "--profile",
                "final",
                "--render-mode",
                "filter",
                "--render-manifest",
                str(receipt),
            ]
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("final render requires --fx-compile-manifest", result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse(receipt.exists())

    def test_final_profile_rejects_preview_window_before_final_validation(self) -> None:
        with self.assertRaises(SystemExit) as error:
            renderer.render(
                recipe_path=Path("missing-recipe.yaml"),
                run_root=Path("missing-run"),
                output_path=Path("missing-final.mov"),
                profile="final",
                preview_start=0.0,
                preview_end=1.0,
                render_mode="filter",
                fx_compile_manifest=Path("forged-compile-manifest.yaml"),
                render_manifest=Path("forged-final-receipt.yaml"),
            )
        self.assertIn("cannot use --preview-start/--preview-end", str(error.exception))

    def test_completed_zero_fx_audit_renders_without_forcing_an_effect(self) -> None:
        receipt, video = self._render_recipe(
            name="zero-fx-final-success",
            fps=Fraction(24, 1),
            width=320,
            height=180,
            frame_count=12,
            timeline=[
                {
                    "slot": "R01",
                    "source": "source-a.mp4",
                    "section_ids": ["S00"],
                    "source_in": 0.25,
                    "source_out": 0.75,
                    "output_in_frame": 0,
                    "output_out_frame": 12,
                    "duration_frames": 12,
                }
            ],
        )
        self.assertEqual(12, receipt["output"]["frame_count"])
        self.assertEqual("24/1", video["avg_frame_rate"])

    def test_duration_preserving_xfade_keeps_program_frame_count(self) -> None:
        fps = Fraction(24, 1)
        timeline = [
            {
                "slot": "R01",
                "source": "source-a.mp4",
                "source_in": 0.25,
                "source_out": 1.25,
                "output_in_frame": 0,
                "output_out_frame": 24,
                "duration_frames": 24,
            },
            {
                "slot": "R02",
                "source": "source-b.mp4",
                "source_in": 0.25,
                "source_out": 1.25,
                "output_in_frame": 24,
                "output_out_frame": 48,
                "duration_frames": 24,
            },
        ]
        effects = [
            {
                "type": "xfade",
                "start": 1.0,
                "duration": 4 / 24,
                "start_frame": 24,
                "duration_frames": 4,
                "fx_id": "FX_XFADE_DURATION_SAFE",
                "status": "pass",
                "origin": "04_edit",
                "transition": "fade",
                "from_slot": "R01",
                "to_slot": "R02",
                "transition_handle_ref": "HANDLE_R01_R02",
                "transition_handle_contract": {
                    "mode": "duration_preserving",
                    "fixed_program_cut_frame": 24,
                    "fixed_program_cut_seconds": 1.0,
                    "transition_frames": 4,
                    "pre_cut_frames": 2,
                    "post_cut_frames": 2,
                },
            }
        ]
        boundary_handles = [
            {
                "handle_id": "HANDLE_R01_R02",
                "mode": "duration_preserving",
                "from_slot": "R01",
                "to_slot": "R02",
                "fixed_program_cut_frame": 24,
                "fixed_program_cut_seconds": 1.0,
                "transition_frames": 4,
                "pre_cut_frames": 2,
                "post_cut_frames": 2,
                "04_preview_ref": "generations/video/qc/previews/final-audit-preview-v1.mp4",
            }
        ]
        receipt, video = self._render_recipe(
            name="xfade-duration-safe",
            fps=fps,
            width=320,
            height=180,
            frame_count=48,
            timeline=timeline,
            effects=effects,
            boundary_handles=boundary_handles,
        )
        self.assertEqual(48, receipt["render_spec"]["expected_frame_count"])
        self.assertEqual(48, receipt["output"]["frame_count"])
        self.assertEqual("24/1", video["avg_frame_rate"])

    def test_frame_locked_geometry_and_rational_fps_matrix(self) -> None:
        cases = [
            ("fps24-3x2", Fraction(24, 1), 300, 200, 24),
            ("fps25-portrait", Fraction(25, 1), 180, 320, 25),
            ("fps2997-landscape", Fraction(30000, 1001), 320, 180, 30),
        ]
        for name, fps, width, height, frame_count in cases:
            with self.subTest(name=name):
                duration = float(Fraction(frame_count, 1) / fps)
                timeline = [
                    {
                        "slot": "R01",
                        "source": "source-a.mp4",
                        "source_in": 0.25,
                        "source_out": 0.25 + duration,
                        "output_in_frame": 0,
                        "output_out_frame": frame_count,
                        "duration_frames": frame_count,
                    }
                ]
                receipt, video = self._render_recipe(
                    name=name,
                    fps=fps,
                    width=width,
                    height=height,
                    frame_count=frame_count,
                    timeline=timeline,
                )
                self.assertEqual(width, int(video["width"]))
                self.assertEqual(height, int(video["height"]))
                self.assertEqual(
                    f"{fps.numerator}/{fps.denominator}", video["avg_frame_rate"]
                )
                self.assertEqual(width, receipt["output"]["width"])
                self.assertEqual(height, receipt["output"]["height"])

    def test_final_encoding_contract_supports_prores_pcm_and_checks_container(self) -> None:
        payload = {
            "delivery_policy": {
                "mezzanine": {
                    "container": "mov",
                    "video_codec": "prores_ks",
                    "video_profile": "hq",
                    "audio_codec": "pcm_s24le",
                    "chroma_policy": "4:2:2 10-bit mezzanine",
                }
            }
        }
        encoding = renderer.encoding_spec(
            payload,
            "final",
            Path("master.mov"),
            preset="medium",
            crf="16",
            audio_bitrate="192k",
        )
        self.assertEqual("prores_ks", encoding.video_codec)
        self.assertEqual("pcm_s24le", encoding.audio_codec)
        self.assertIn("3", encoding.video_args)
        with self.assertRaisesRegex(SystemExit, "must match"):
            renderer.encoding_spec(
                payload,
                "final",
                Path("master.mp4"),
                preset="medium",
                crf="16",
                audio_bitrate="192k",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
