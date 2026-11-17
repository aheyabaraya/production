#!/usr/bin/env python3
"""Extract one selected self-contained weekly-report image into its owning run.

This is a deterministic source bridge. It does not interpret images or choose a
reference. After the owning album run selects a report figure, it preserves that
actual visual-reference surface for Front Planning reference connection or
current-title visual asset production; it does not create a creative lock or
authorize any generation attachment. A selected embedded weekly HTML figure
may carry its declared camera, composition, framing, action, space, performance,
motion, edit, or PRE-00 surface into that intake.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Sequence


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
WEEKLY_DIR = Path("source-materials/idol-activity-reports/weekly")
RUNS_DIR = Path("runs")
OUTPUT_RELATIVE_DIR = Path("research/weekly-report-reference-extracts")
MIME_EXTENSIONS = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
}
COMPLETE_STATUS_PATTERN = re.compile(
    r"<dt>\s*status\s*</dt>\s*<dd>\s*complete\s*</dd>", re.IGNORECASE
)
DATA_URI_PATTERN = re.compile(r"\Adata:([^;,]+);base64,([A-Za-z0-9+/=\s]+)\Z", re.DOTALL)
SAFE_NAME_PATTERN = re.compile(r"[^A-Za-z0-9._-]+")


class ReferenceExtractionError(RuntimeError):
    """Raised when a report image cannot become a selected derived surface."""


@dataclass
class FigureRecord:
    attributes: dict[str, str]
    images: list[dict[str, str]] = field(default_factory=list)


class SelectedFigureParser(HTMLParser):
    """Find exactly one figure by its evidence and reference ids."""

    def __init__(self, evidence_id: str, reference_id: str) -> None:
        super().__init__(convert_charrefs=True)
        self.evidence_id = evidence_id
        self.reference_id = reference_id
        self.figure_stack: list[FigureRecord | None] = []
        self.matches: list[FigureRecord] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attribute_map = {key: value or "" for key, value in attrs}
        if tag.lower() == "figure":
            if (
                attribute_map.get("data-evidence-id") == self.evidence_id
                and attribute_map.get("data-reference-id") == self.reference_id
            ):
                self.figure_stack.append(FigureRecord(attribute_map))
            else:
                self.figure_stack.append(None)
            return
        if tag.lower() == "img" and self.figure_stack and self.figure_stack[-1] is not None:
            self.figure_stack[-1].images.append(attribute_map)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if tag.lower() == "figure":
            self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "figure" or not self.figure_stack:
            return
        record = self.figure_stack.pop()
        if record is not None:
            self.matches.append(record)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Extract one selected data-URI report figure into the owning run with "
            "report/ledger/image hash lineage."
        )
    )
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--evidence-id", required=True)
    parser.add_argument("--reference-id", required=True)
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--repo-root", type=Path, default=SCRIPT_ROOT)
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Validate and print the manifest without writing the derived image or manifest.",
    )
    return parser.parse_args(argv)


def resolve_inside(root: Path, path: Path, expected_parent: Path, label: str) -> Path:
    resolved_root = root.resolve()
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(resolved_root)
    except ValueError as error:
        raise ReferenceExtractionError(f"{label} escapes repository root: {path}") from error
    try:
        relative.relative_to(expected_parent)
    except ValueError as error:
        raise ReferenceExtractionError(
            f"{label} must be under {expected_parent.as_posix()}: {path}"
        ) from error
    return resolved


def decode_data_uri(value: str) -> tuple[str, bytes]:
    match = DATA_URI_PATTERN.fullmatch(value.strip())
    if not match:
        raise ReferenceExtractionError("selected figure image must be a decodable base64 data:image URI")
    mime_type = match.group(1).lower()
    extension = MIME_EXTENSIONS.get(mime_type)
    if extension is None:
        raise ReferenceExtractionError(f"selected image MIME type is not reusable as a report derivative: {mime_type}")
    try:
        payload = base64.b64decode(re.sub(r"\s+", "", match.group(2)), validate=True)
    except (binascii.Error, ValueError) as error:
        raise ReferenceExtractionError("selected figure image data URI is not valid base64") from error
    if not payload:
        raise ReferenceExtractionError("selected figure image data URI has no bytes")
    return mime_type, payload


def selected_figure(report_text: str, evidence_id: str, reference_id: str) -> FigureRecord:
    parser = SelectedFigureParser(evidence_id, reference_id)
    parser.feed(report_text)
    parser.close()
    if len(parser.matches) != 1:
        raise ReferenceExtractionError(
            "report must contain exactly one figure matching both "
            f"evidence_id={evidence_id!r} and reference_id={reference_id!r}"
        )
    record = parser.matches[0]
    if record.attributes.get("data-placeholder", "").lower() == "true":
        raise ReferenceExtractionError("selected figure is still marked as a placeholder")
    if record.attributes.get("data-album-visual-reference") != "direct_reference_after_run_selection":
        raise ReferenceExtractionError(
            "selected figure is not marked for direct reference after run selection"
        )
    if record.attributes.get("data-album-visual-scope") != "explicit_reference_selection_required":
        raise ReferenceExtractionError(
            "selected figure does not require an explicit direct-reference selection"
        )
    if len(record.images) != 1:
        raise ReferenceExtractionError("selected figure must contain exactly one image")
    if record.images[0].get("data-placeholder", "").lower() == "true":
        raise ReferenceExtractionError("selected image is still marked as a placeholder")
    return record


def safe_name(value: str) -> str:
    normalized = SAFE_NAME_PATTERN.sub("-", value).strip(".-")
    if not normalized:
        raise ReferenceExtractionError("reference identifiers must contain a filename-safe character")
    return normalized


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def relative_to_root(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def build_manifest(
    *,
    repo_root: Path,
    report_path: Path,
    ledger_path: Path,
    run_root: Path,
    output_path: Path,
    evidence_id: str,
    reference_id: str,
    figure_id: str,
    mime_type: str,
    image_bytes: bytes,
    report_bytes: bytes,
    ledger_bytes: bytes,
    status: str,
) -> dict[str, object]:
    image_hash = sha256_bytes(image_bytes)
    return {
        "schema": "idol_weekly_html_reference_extract.v1",
        "status": status,
        "semantic_read_order": "html_visual_reference_board_then_ledger_then_album_intake_extract",
        "source_report_path": relative_to_root(report_path, repo_root),
        "source_report_sha256": sha256_bytes(report_bytes),
        "reference_ledger_path": relative_to_root(ledger_path, repo_root),
        "reference_ledger_sha256": sha256_bytes(ledger_bytes),
        "source_figure_id": figure_id,
        "image_evidence_id": evidence_id,
        "reference_id": reference_id,
        "embedded_mime": mime_type,
        "embedded_derivative_sha256": image_hash,
        "extracted_path": relative_to_root(output_path, repo_root),
        "extracted_sha256": image_hash,
        "run_root": relative_to_root(run_root, repo_root),
        "album_visual_reference_eligible": True,
        "album_visual_reference_use": (
            "after run selection: existing 01R reference_image_intake and optional "
            "01A wardrobe/style/makeup board"
        ),
        "album_visual_reference_scope": "direct_reference_after_run_selection",
        "general_direction_eligible": True,
        "direct_reference_surfaces": [
            "MV story/world",
            "set/space",
            "camera/composition",
            "body action/choreography",
            "performance",
            "motion",
            "edit",
            "PRE-00 concept route",
        ],
        "downstream_limit": (
            "selected visual-reference intake/pixel inspection only; "
            "not an automatic 02B or API attachment"
        ),
        "creative_lock_created": False,
        "generation_attachment_authorized": False,
    }


def write_or_verify(path: Path, expected: bytes, label: str) -> None:
    if path.exists():
        if path.read_bytes() != expected:
            raise ReferenceExtractionError(f"existing {label} has different bytes: {path}")
        return
    path.write_bytes(expected)


def run(arguments: argparse.Namespace) -> dict[str, object]:
    repo_root = arguments.repo_root.resolve()
    report_path = resolve_inside(repo_root, arguments.report, WEEKLY_DIR, "report")
    ledger_path = resolve_inside(repo_root, arguments.ledger, WEEKLY_DIR, "ledger")
    run_root = resolve_inside(repo_root, arguments.run_root, RUNS_DIR, "run root")
    if not report_path.is_file() or not ledger_path.is_file():
        raise ReferenceExtractionError("report and ledger must both be readable files")

    report_bytes = report_path.read_bytes()
    ledger_bytes = ledger_path.read_bytes()
    report_text = report_bytes.decode("utf-8")
    ledger_text = ledger_bytes.decode("utf-8")
    if not COMPLETE_STATUS_PATTERN.search(report_text):
        raise ReferenceExtractionError("report must declare status: complete before a figure can be extracted")
    if arguments.reference_id not in ledger_text or arguments.evidence_id not in ledger_text:
        raise ReferenceExtractionError("ledger must contain the selected reference_id and image_evidence_id")

    figure = selected_figure(report_text, arguments.evidence_id, arguments.reference_id)
    image_source = figure.images[0].get("src", "")
    mime_type, image_bytes = decode_data_uri(image_source)
    extension = MIME_EXTENSIONS[mime_type]
    output_dir = run_root / OUTPUT_RELATIVE_DIR
    expected_output_dir = (run_root / OUTPUT_RELATIVE_DIR).resolve()
    if output_dir.resolve() != expected_output_dir:
        raise ReferenceExtractionError("weekly report extracts must use the registered run research directory")
    basename = f"{safe_name(arguments.reference_id)}--{safe_name(arguments.evidence_id)}"
    output_path = output_dir / f"{basename}.{extension}"
    manifest_path = output_dir / f"{basename}.json"
    manifest = build_manifest(
        repo_root=repo_root,
        report_path=report_path,
        ledger_path=ledger_path,
        run_root=run_root,
        output_path=output_path,
        evidence_id=arguments.evidence_id,
        reference_id=arguments.reference_id,
        figure_id=figure.attributes.get("id", ""),
        mime_type=mime_type,
        image_bytes=image_bytes,
        report_bytes=report_bytes,
        ledger_bytes=ledger_bytes,
        status="verified" if arguments.verify_only else "extracted",
    )
    if arguments.verify_only:
        return manifest

    output_dir.mkdir(parents=True, exist_ok=True)
    write_or_verify(output_path, image_bytes, "selected image")
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    write_or_verify(manifest_path, manifest_bytes, "extraction manifest")
    return manifest


def main(argv: Sequence[str] | None = None) -> int:
    try:
        manifest = run(parse_args(argv or sys.argv[1:]))
    except (OSError, UnicodeDecodeError, ReferenceExtractionError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
