#!/usr/bin/env python3
"""Historical pre-Branch-Cut OpenAI Batch API runner.

This file is retained only to identify and inspect historical Batch records.
The active 02B v2.2 route uses one idol_image_generation_request.v8 per Branch
Cut. This legacy board/keyframe runner must fail before prepare, upload, submit,
download, import, or cancel; it is not a compatibility route.

Secret values are loaded from .runtime/secrets/openai-imagegen.env when needed
but are never printed.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import mimetypes
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime
from io import BytesIO
from pathlib import Path
from typing import Any

import idol_title_output_registry as title_registry
from idol_openai_image_model_policy import assert_openai_image_request_jsonl, require_openai_image_model


SCHEMA_VERSION = "idol_02b_openai_batch_api.2026_05_v1"
SECTION_EXPORT_INDEX_SCHEMA = "idol_02b_section_export_index.v1"
ENDPOINT = "/v1/images/edits"
GENERATIONS_ENDPOINT = "/v1/images/generations"
COMPLETION_WINDOW = "24h"
TERMINAL_STATUSES = {"completed", "failed", "expired", "cancelled"}
DEFAULT_ENV_FILE = ".runtime/secrets/openai-imagegen.env"
OPENAI_API_BASE = "https://api.openai.com"
PROMPT_WARNING_CHARS = 3500
PROMPT_HARD_FAIL_CHARS = 7000
REQUIRED_IMAGE_QUALITY = "high"
MAXIMUM_SUPPORTED_IMAGE_SIZES = {"1536x1024", "1024x1536", "1024x1024"}
VISIBLE_DETAILS_LABEL = "Visible details"
LEGACY_VISUAL_EVIDENCE_LABEL = "Visual evidence"
VISUAL_DETAILS_LABELS = (VISIBLE_DETAILS_LABEL, LEGACY_VISUAL_EVIDENCE_LABEL)
BEAT_RESPONSE_LABEL = "Beat response"
ACTION_CUE_LABEL = "Action cue"
BEAT_RESPONSE_LABELS = (BEAT_RESPONSE_LABEL, ACTION_CUE_LABEL)
REQUIRED_MANIFEST_FIELDS = (
    "album_key",
    "title_key",
    "title_display_name",
    "title_output_root",
    "title_output_registry_path",
    "packet_id",
    "execution_section_id",
    "board_prompt_export_path",
    "expected_board_image_path",
    "identity_reference",
    "layout_mode",
    "model_plan",
    "render_wrapper",
)
KEYFRAME_MANIFEST_FIELDS = (
    "album_key",
    "title_key",
    "title_display_name",
    "title_output_root",
    "title_output_registry_path",
    "packet_id",
    "execution_section_id",
    "keyframe_prompt_export_path",
    "expected_keyframe_image_path",
    "identity_reference",
    "model_plan",
    "imagegen_guard",
)
REQUIRED_EXPORT_ROW_FIELDS = (
    "album_key",
    "title_key",
    "title_output_registry_path",
    "packet_id",
    "execution_section_id",
    "prompt_export_path",
    "manifest_path",
    "expected_board_image_path",
)
KEYFRAME_EXPORT_ROW_FIELDS = (
    "album_key",
    "title_key",
    "title_output_registry_path",
    "packet_id",
    "execution_section_id",
    "prompt_export_path",
    "manifest_path",
    "expected_keyframe_image_path",
)
CHARACTER_BOARD_INPUT_PATTERNS = (
    "character-board",
    "character_board",
    "character board",
)
DEPRECATED_IDENTITY_VARIANT_PATTERN = re.compile(r"no[-_ ]?mic", re.I)
RETIRED_GENERATED_FACE_UPSCALE_PATTERN = re.compile(
    r"(?:^|/)face-only-reference-upscaled\.png$", re.I
)
DYNAMIC_FRAMING_CLASSES = {
    "foreground_body_detail",
    "wide_angle_reach",
    "overhead_crop",
    "recline_tilt",
}
FRAMING_CLASSES = {
    "face_hand_close",
    "upper_body_action",
    "three_quarter_body_action",
    "full_body_action",
    "full_body_formation",
    *DYNAMIC_FRAMING_CLASSES,
}
FULL_BODY_FRAMING_CLASSES = {"full_body_action", "full_body_formation"}
DYNAMIC_FRAMING_EVIDENCE_PATTERNS = {
    "foreground_body_detail": re.compile(r"foreground|near[- ]lens|lens|close|toward|boot|hand|forced|depth", re.I),
    "wide_angle_reach": re.compile(r"wide[- ]angle|wide angle|wide lens|near|far|depth|reach|lens|perspective", re.I),
    "overhead_crop": re.compile(r"overhead|top[- ]down|top down|floor|formation|geometry|crop", re.I),
    "recline_tilt": re.compile(r"recline|reclined|tilt|lean|floor|ground|torso|body line", re.I),
}


def reject_deprecated_identity_variant(packet_id: str, path: Path) -> None:
    if RETIRED_GENERATED_FACE_UPSCALE_PATTERN.search(path.as_posix()):
        raise ValueError(
            f"{packet_id}: retired generated-master face-only upscale is not allowed; "
            f"use the registry-selected direct-source face-only upscale: {path}"
        )
    if DEPRECATED_IDENTITY_VARIANT_PATTERN.search(str(path)):
        raise ValueError(
            f"{packet_id}: deprecated no-mic identity reference is not allowed; use the approved face-only identity reference: {path}"
        )


ACTIVE_STALE_TERM_PATTERNS = (
    ("technical stage", re.compile(r"\btechnical stage\b", re.I)),
    ("LED grid", re.compile(r"\bLED grid\b", re.I)),
    ("LED lane", re.compile(r"\bLED lane\b", re.I)),
    ("jacket-only", re.compile(r"\bjacket[- ]only\b", re.I)),
    ("tactical", re.compile(r"\btactical\b", re.I)),
    ("combat boots", re.compile(r"\bcombat boots\b", re.I)),
    ("chrome piping", re.compile(r"\bchrome piping\b", re.I)),
    ("calibration axis", re.compile(r"\bcalibration axis\b", re.I)),
    ("support rail", re.compile(r"\bsupport rail\b", re.I)),
    ("bottom-right technical panel", re.compile(r"\bbottom[- ]right technical panel\b", re.I)),
    ("tech interface", re.compile(r"\btech interface\b", re.I)),
    ("screen ID", re.compile(r"\bscreen ID\b", re.I)),
    ("UI logo", re.compile(r"\bUI logo\b", re.I)),
)
CORE_PROMPT_FORBIDDEN_PATTERNS = (
    ("top member-name header", re.compile(r"Top member-name header", re.I)),
    ("visual layout lock", re.compile(r"Visual layout lock", re.I)),
    ("right reference strip", re.compile(r"right reference strip", re.I)),
    ("review board", re.compile(r"review board", re.I)),
    ("top-left label block", re.compile(r"top[- ]left label block", re.I)),
    ("identity checklist", re.compile(r"identity checklist", re.I)),
    ("text beside face photo", re.compile(r"text beside face photo", re.I)),
    ("separate dominant main panel", re.compile(r"separate dominant main panel", re.I)),
    ("director-chain label", re.compile(r"\bDirector chain:", re.I)),
    ("raw audio-anchor label", re.compile(r"\bAudio anchor:|audio_anchor", re.I)),
    ("internal packet id", re.compile(r"\bPKT_[A-Z0-9_]+\b")),
    ("internal beat id", re.compile(r"\bB\d{2}_[A-Z0-9_]+\b")),
    ("raw timecode", re.compile(r"\b\d{1,3}(?:\.\d{1,2})?-\d{1,3}(?:\.\d{1,2})?s\b")),
    ("raw cut label", re.compile(r"\bCUT0[1-3]\b")),
    ("local/source path", re.compile(r"\b(?:runs|schemas|scripts|skills|wiki)/|\.(?:yaml|json|rb|py|md)\b", re.I)),
    ("schema/validator/export label", re.compile(r"\b(?:schema|validator|manifest|export index|export_contract|prompt_compile_contract)\b", re.I)),
)
CONCRETE_MEMBER_PATTERN = re.compile(r"\bM(0[1-9]|1[0-3])\b")
CONCRETE_SPACE_PATTERN = re.compile(
    r"\b(room|street|underpass|alley|poster|wall|wall panel|door|doorway|doorframe|window|mirror|ceiling|screen|hall|lobby|tunnel|bridge|bus shelter|shelter|factory|floor|threshold|rooftop|roof|parking|deck|stair|staircase|stairwell|loading dock|dock|arcade|coin[- ]laundry|city|road|line|shutter|small room|studio|set|stage|platform|corridor|gate|checkpoint|security|scanner|tray|terminal|moving walkway|walkway|boarding|hangar|cargo|baggage|carousel|belt|tarmac|warehouse|bench|rail|metal detector|vehicle|train|subway|bus|elevator|water|shore|forest|field|garden|kitchen|bedroom|school|classroom|office|shop|market|counter|table|chair|curtain|neon|sign|light|shadow)\b",
    re.I,
)
CONCRETE_ACTION_PATTERN = re.compile(
    r"\b(hand|hands|gaze|eyes?|shoulder|shoulders|arm|arms|elbow|elbows|neck|back|waist|torso|chest|leg|legs|knee|knees|boot|boots|foot|feet|step|body|hip|hips|wrist|fingertip|breath|jaw|turn|lift|roll|rebound|stop|hold|walk|pull|touch|lower|cross|settle|enter|land|move|fabric|tie|sleeve|garment|route|mark|circle|hit|freeze|plant|plants|slide|slides|sway|sways|lean|leans|tilt|tilts|spin|spins|open|opens|close|closes|raise|raises|drop|drops|press|presses|point|points|grab|grabs|sweep|sweeps|kick|kicks|stamp|stamps|reach|reaches)\b",
    re.I,
)
CONCRETE_CAMERA_PATTERN = re.compile(
    r"\b(camera|close|medium|wide|upper|full[- ]body|three[- ]quarter|shot scale|angle|composition|framing|push|track|pan|reveal|hold|frame|triptych|low|side|front|rear|profile|diagonal|distance|foreground|overhead|top[- ]down|near[- ]lens|lens|recline|tilt|crop|dolly|gimbal|zoom|pull|back|rack focus|parallax|height|eye[- ]level|hip[- ]height|waist[- ]height|knee[- ]height|low[- ]angle|high[- ]angle|over[- ]shoulder|depth)\b",
    re.I,
)
CONCRETE_BEAT_RESPONSE_PATTERN = re.compile(
    r"\b(hand|hands|gaze|body|torso|step|foot|feet|boot|boots|shoulder|shoulders|arm|arms|elbow|elbows|neck|back|waist|leg|legs|chest|eye|eyes|fabric|camera|wrist|fist|knee|knees|hip|hips|lift|hit|pulse|bounce|stop|hold|roll|rebound|route|mark|breath|drop|drops|land|lands|lower|lowers|sink|sinks|flick|flicks|turn|turns|plant|plants|slide|slides|sway|sways|lean|leans|open|opens|close|closes|raise|raises|press|presses|point|points|grab|grabs|sweep|sweeps|stamp|stamps|reach|reaches)\b",
    re.I,
)
ACTION_FIELD_LYRIC_LEAK_PATTERN = re.compile(r"\b(low[- ]?key|high control|click[- ]?hush|let it roll|low low roll)\b", re.I)
FIXED_RENDER_REGIONS = {
    "top_left_label_block": (0, 0, 100, 8),
    "cut01_panel": (1, 10, 32, 84),
    "cut02_panel": (34, 10, 32, 84),
    "cut03_panel": (67, 10, 32, 84),
}


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def now_label() -> str:
    return datetime.now().astimezone().strftime("%Y%m%dT%H%M%S%z")


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def jsonl_dump(row: dict[str, Any]) -> str:
    return json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def object_to_plain(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, list):
        return [object_to_plain(item) for item in value]
    if isinstance(value, tuple):
        return [object_to_plain(item) for item in value]
    if isinstance(value, dict):
        return {str(key): object_to_plain(item) for key, item in value.items()}
    if hasattr(value, "model_dump"):
        return object_to_plain(value.model_dump(mode="json"))
    if hasattr(value, "to_dict"):
        return object_to_plain(value.to_dict())
    return str(value)


def load_structured(path: Path) -> Any:
    if path.suffix.lower() == ".json":
        return json.loads(path.read_text(encoding="utf-8"))
    try:
        import yaml  # type: ignore

        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except ImportError:
        proc = subprocess.run(
            [
                "ruby",
                "-ryaml",
                "-rjson",
                "-e",
                "print JSON.generate(YAML.load_file(ARGV.fetch(0)))",
                str(path),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return json.loads(proc.stdout)


def write_structured(path: Path, data: Any) -> None:
    try:
        import yaml  # type: ignore

        path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
    except ImportError:
        # JSON is valid YAML, and this avoids adding a runtime dependency.
        path.write_text(json_dump(data), encoding="utf-8")


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        if key:
            values[key] = value
    return values


def load_secret_env(env_file: Path) -> None:
    for key, value in parse_env_file(env_file).items():
        os.environ.setdefault(key, value)


class OpenAIHttpObject(dict):
    def __getattr__(self, key: str) -> Any:
        try:
            return self[key]
        except KeyError as error:
            raise AttributeError(key) from error

    def to_dict(self) -> dict[str, Any]:
        return dict(self)


class OpenAIHttpFiles:
    def __init__(self, client: "OpenAIHttpClient") -> None:
        self.client = client

    def create(self, *, file: Any, purpose: str) -> OpenAIHttpObject:
        filename = Path(getattr(file, "name", "request.jsonl")).name
        file_bytes = file.read()
        boundary = "idol-batch-boundary-" + hashlib.sha256(file_bytes[:1024]).hexdigest()[:24]
        body = b"".join(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                b'Content-Disposition: form-data; name="purpose"\r\n\r\n',
                purpose.encode("utf-8"),
                b"\r\n",
                f"--{boundary}\r\n".encode("utf-8"),
                f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode("utf-8"),
                b"Content-Type: application/jsonl\r\n\r\n",
                file_bytes,
                b"\r\n",
                f"--{boundary}--\r\n".encode("utf-8"),
            ]
        )
        return OpenAIHttpObject(
            self.client.request(
                "POST",
                "/v1/files",
                body=body,
                content_type=f"multipart/form-data; boundary={boundary}",
            )
        )

    def content(self, file_id: str) -> BytesIO:
        return BytesIO(self.client.request_bytes("GET", f"/v1/files/{file_id}/content"))


class OpenAIHttpBatches:
    def __init__(self, client: "OpenAIHttpClient") -> None:
        self.client = client

    def create(self, **payload: Any) -> OpenAIHttpObject:
        return OpenAIHttpObject(self.client.request("POST", "/v1/batches", json_body=payload))

    def retrieve(self, batch_id: str) -> OpenAIHttpObject:
        return OpenAIHttpObject(self.client.request("GET", f"/v1/batches/{batch_id}"))

    def cancel(self, batch_id: str) -> OpenAIHttpObject:
        return OpenAIHttpObject(self.client.request("POST", f"/v1/batches/{batch_id}/cancel", json_body={}))


class OpenAIHttpClient:
    def __init__(self, api_key: str, *, api_base: str = OPENAI_API_BASE) -> None:
        self.api_key = api_key
        self.api_base = api_base.rstrip("/")
        self.files = OpenAIHttpFiles(self)
        self.batches = OpenAIHttpBatches(self)

    def request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict[str, Any] | None = None,
        body: bytes | None = None,
        content_type: str | None = None,
    ) -> dict[str, Any]:
        data = body
        headers = {
            "Authorization": f"Bearer {self.api_key}",
        }
        if json_body is not None:
            data = json.dumps(json_body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        elif content_type:
            headers["Content-Type"] = content_type
        request = urllib.request.Request(self.api_base + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"OpenAI HTTP {error.code}: {detail}") from error

    def request_bytes(self, method: str, path: str) -> bytes:
        request = urllib.request.Request(
            self.api_base + path,
            method=method,
            headers={"Authorization": f"Bearer {self.api_key}"},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"OpenAI HTTP {error.code}: {detail}") from error


def require_openai_client(env_file: Path):
    load_secret_env(env_file)
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    try:
        from openai import OpenAI
    except ImportError:
        return OpenAIHttpClient(api_key)
    return OpenAI()


def image_data_url(path: Path) -> str:
    mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def extract_full_prompt(text: str) -> str:
    marker = "## Full Prompt"
    next_marker = "## Review Prompt Sentence"
    if marker in text:
        text = text.split(marker, 1)[1]
        if next_marker in text:
            text = text.split(next_marker, 1)[0]
    return text.strip()


def resolve_run(path_value: str) -> Path:
    path = Path(path_value)
    return path if path.is_absolute() else Path.cwd() / path


def default_export_index(run_root: Path, section_id: str) -> Path:
    return run_root / "exports" / "02B" / "sections" / section_id / "export-index.yaml"


def default_batch_dir(run_root: Path, run_label: str) -> Path:
    return run_root / "exports" / "imagegen" / "batch-api" / run_label


def load_export_index(run_root: Path, section_id: str, export_index_path: str | None) -> dict[str, Any]:
    path = Path(export_index_path) if export_index_path else default_export_index(run_root, section_id)
    if not path.is_absolute():
        path = Path.cwd() / path
    if not path.exists():
        raise FileNotFoundError(f"export index not found: {path}")
    index = load_structured(path)
    if str(index.get("schema_version") or "") != SECTION_EXPORT_INDEX_SCHEMA:
        raise ValueError(
            "Batch API prepare requires a section execution package "
            f"({SECTION_EXPORT_INDEX_SCHEMA}), not the root all-song export index"
        )
    if str(index.get("execution_section_id") or "") != section_id:
        raise ValueError(
            f"section export index execution_section_id must equal --section-id {section_id}"
        )
    return index


def require_fields(context: str, data: dict[str, Any], fields: tuple[str, ...]) -> None:
    missing = [field for field in fields if data.get(field) in (None, "")]
    if missing:
        raise ValueError(f"{context}: missing required fields: {', '.join(missing)}")


def is_keyframe_export_row(row: dict[str, Any]) -> bool:
    return bool(row.get("expected_keyframe_image_path") or row.get("render_prompt_mode") == "single_keyframe_3_2")


def is_keyframe_manifest(manifest: dict[str, Any]) -> bool:
    schema_version = str(manifest.get("schema_version") or "")
    return bool(
        schema_version.startswith("idol_02b_adaptive_keyframe_prompt_manifest")
        or manifest.get("keyframe_prompt_export_path")
        or manifest.get("expected_keyframe_image_path")
        or manifest.get("imagegen_guard")
    )


def manifest_prompt_export_path(manifest: dict[str, Any]) -> str:
    field = "keyframe_prompt_export_path" if is_keyframe_manifest(manifest) else "board_prompt_export_path"
    return str(manifest.get(field) or "")


def manifest_expected_output_path(manifest: dict[str, Any]) -> str:
    field = "expected_keyframe_image_path" if is_keyframe_manifest(manifest) else "expected_board_image_path"
    return str(manifest.get(field) or "")


def validate_render_framing_cut(packet_id: str, cut: dict[str, Any]) -> None:
    cut_id = str(cut.get("cut") or "")
    framing_class = str(cut.get("framing_class") or "")
    required_visibility = str(cut.get("required_visibility") or "").lower()
    crop_rule = str(cut.get("crop_rule") or "").lower()
    framing_purpose = str(cut.get("framing_purpose") or "")
    if cut_id not in {"CUT01", "CUT02", "CUT03"}:
        raise ValueError(f"{packet_id}: render wrapper cut id must be CUT01, CUT02, or CUT03")
    if framing_class not in FRAMING_CLASSES:
        raise ValueError(f"{packet_id}: {cut_id} framing_class must be one of {', '.join(sorted(FRAMING_CLASSES))}")
    if not required_visibility:
        raise ValueError(f"{packet_id}: {cut_id} required_visibility is missing")
    if not crop_rule:
        raise ValueError(f"{packet_id}: {cut_id} crop_rule is missing")
    if not framing_purpose:
        raise ValueError(f"{packet_id}: {cut_id} framing_purpose is missing")
    if framing_class in DYNAMIC_FRAMING_CLASSES:
        evidence = " ".join([required_visibility, crop_rule, framing_purpose.lower()])
        pattern = DYNAMIC_FRAMING_EVIDENCE_PATTERNS[framing_class]
        if not pattern.search(evidence):
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} must preserve its concrete camera/body geometry evidence")
        if "crop" not in crop_rule or not any(token in crop_rule for token in ("allowed", "intentional", "optional", "partial")):
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} crop_rule must explicitly allow the intended dynamic crop")
        if "do not crop boots" in crop_rule or "head-to-boots" in crop_rule:
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} crop_rule must not collapse back to full-body boot-safe framing")
    elif framing_class in FULL_BODY_FRAMING_CLASSES:
        if not any(token in required_visibility for token in ("head-to-boots", "full body", "both members")):
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} must require full-body/head-to-boots visibility")
        if "do not crop" not in crop_rule or not any(token in crop_rule for token in ("boots", "feet")):
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} crop_rule must protect feet/boots")
        evidence = " ".join([required_visibility, crop_rule, framing_purpose.lower()])
        if not re.search(r"lower|trouser|pants|shoe|foot|feet|boots|ground|weight|landing|stance", evidence):
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} must specify lower-body/footwear/ground or weight evidence")
    elif "optional" not in crop_rule:
        raise ValueError(f"{packet_id}: {cut_id} {framing_class} crop_rule must state that lower body or feet are intentionally optional")
    if framing_class in {"face_hand_close", "upper_body_action"}:
        evidence = " ".join([required_visibility, crop_rule, framing_purpose.lower()])
        if not re.search(r"eye|eyes|jaw|breath|shoulder|hand|hands|finger|chest|sternum|weight", evidence):
            raise ValueError(f"{packet_id}: {cut_id} {framing_class} must specify eye/jaw/breath/shoulder/hand acting evidence")


def numeric_equal(value: Any, expected: int) -> bool:
    try:
        return float(value) == float(expected)
    except (TypeError, ValueError):
        return False


def validate_fixed_coordinate_regions(packet_id: str, regions: Any) -> None:
    if not isinstance(regions, list):
        raise ValueError(f"{packet_id}: render_wrapper.fixed_coordinate_regions must be an array")
    by_region = {str(entry.get("region") or ""): entry for entry in regions if isinstance(entry, dict)}
    for region, (x, y, w, h) in FIXED_RENDER_REGIONS.items():
        entry = by_region.get(region)
        if not entry:
            raise ValueError(f"{packet_id}: render_wrapper.fixed_coordinate_regions missing {region}")
        for field, expected in {"x": x, "y": y, "w": w, "h": h}.items():
            if not numeric_equal(entry.get(field), expected):
                raise ValueError(f"{packet_id}: {region}.{field} must be {expected}")
        if not str(entry.get("purpose") or "").strip():
            raise ValueError(f"{packet_id}: {region}.purpose is required")


def validate_top_left_label_block(packet_id: str, block: Any) -> None:
    if not isinstance(block, dict):
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block is required")
    for field, expected in {"x": 0, "y": 0, "w": 100, "h": 8}.items():
        if not numeric_equal(block.get(field), expected):
            raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.{field} must be {expected}")
    for field in ("packet_code", "packet_number", "section_label", "timecode", "member_codes_names", "visible_text"):
        if not str(block.get(field) or "").strip():
            raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.{field} is required")
    if str(block.get("packet_code") or "") != packet_id:
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.packet_code must match packet_id")
    if not re.search(r"\bB\d{2,}\b", str(block.get("packet_number") or "")):
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.packet_number must be the short packet number")
    if not re.search(r"\bS\d{2,}\b", str(block.get("section_label") or "")):
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.section_label must include the song section")
    if not re.search(r"\b\d{1,3}(?:\.\d{1,2})?-\d{1,3}(?:\.\d{1,2})?s\b", str(block.get("timecode") or "")):
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.timecode must carry a source time range")
    if not CONCRETE_MEMBER_PATTERN.search(str(block.get("member_codes_names") or "")):
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.member_codes_names must include member code(s)")
    visible = str(block.get("visible_text") or "")
    for field in ("packet_number", "section_label", "timecode", "member_codes_names"):
        if str(block.get(field) or "") not in visible:
            raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.visible_text must include {field}")
    if str(block.get("packet_code") or "") in visible:
        raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.visible_text must use packet_number, not full packet_code")
    for cut in ("CUT01", "CUT02", "CUT03"):
        if cut in visible:
            raise ValueError(f"{packet_id}: render_wrapper.top_left_label_block.visible_text must not include {cut}; CUT labels belong inside panels")


def validate_render_wrapper(manifest: dict[str, Any]) -> None:
    packet_id = str(manifest.get("packet_id") or "")
    wrapper = manifest.get("render_wrapper")
    if not isinstance(wrapper, dict) or not wrapper:
        raise ValueError(f"{packet_id}: render_wrapper is required before API submit")
    required_fields = (
        "applies_at",
        "source_boundary",
        "non_creative_rule",
        "reference_image_policy",
        "render_guard_policy",
        "layout_mode",
        "layout_profile_id",
        "aspect_ratio",
        "size",
        "top_left_label_block",
        "fixed_coordinate_regions",
        "panel_label_policy",
        "face_reference_lighting_policy",
        "per_cut_render_framing",
    )
    require_fields(f"{packet_id}: render_wrapper", wrapper, required_fields)
    if wrapper.get("applies_at") != "export_manifest_pre_api":
        raise ValueError(f"{packet_id}: render_wrapper.applies_at must be export_manifest_pre_api")
    if wrapper.get("layout_mode") != manifest.get("layout_mode"):
        raise ValueError(f"{packet_id}: render_wrapper.layout_mode must match manifest.layout_mode")
    boundary = "\n".join(
        str(wrapper.get(field) or "") for field in ("source_boundary", "non_creative_rule", "render_guard_policy")
    ).lower()
    if "not rewrite" not in boundary and "must not rewrite" not in boundary and "non-creative" not in boundary:
        raise ValueError(f"{packet_id}: render_wrapper must declare the non-creative wrapper boundary")
    reference_policy = str(wrapper.get("reference_image_policy") or "").lower()
    if "face" not in reference_policy or "only" not in reference_policy:
        raise ValueError(f"{packet_id}: render_wrapper.reference_image_policy must require face-only references")
    validate_top_left_label_block(packet_id, wrapper.get("top_left_label_block"))
    validate_fixed_coordinate_regions(packet_id, wrapper.get("fixed_coordinate_regions"))
    panel_label_policy = str(wrapper.get("panel_label_policy") or "")
    for cut in ("CUT01", "CUT02", "CUT03"):
        if cut not in panel_label_policy:
            raise ValueError(f"{packet_id}: render_wrapper.panel_label_policy must require {cut}")
    if "top-left corner" not in panel_label_policy.lower():
        raise ValueError(f"{packet_id}: render_wrapper.panel_label_policy must place CUT labels in a panel corner")
    render_guard = str(wrapper.get("render_guard_policy") or "").lower()
    for term in ("quality", "proportion", "anatomy", "hands", "fingers", "feet", "lighting", "exposure", "color temperature"):
        if term not in render_guard:
            raise ValueError(f"{packet_id}: render_wrapper.render_guard_policy must include common quality/proportion/lighting guard term: {term}")
    lighting_policy = str(wrapper.get("face_reference_lighting_policy") or "").lower()
    if "light" not in lighting_policy or "scene" not in lighting_policy:
        raise ValueError(f"{packet_id}: render_wrapper.face_reference_lighting_policy must control face-reference scene lighting")
    if "input" not in lighting_policy or "not render" not in lighting_policy:
        raise ValueError(f"{packet_id}: render_wrapper.face_reference_lighting_policy must keep face references as input-only, not rendered panels")
    for term in ("neck", "skin tone", "perspective", "scale"):
        if term not in lighting_policy:
            raise ValueError(f"{packet_id}: render_wrapper.face_reference_lighting_policy must guard against pasted-head artifacts with {term}")
    per_cut = wrapper.get("per_cut_render_framing")
    if not isinstance(per_cut, list) or len(per_cut) != 3:
        raise ValueError(f"{packet_id}: render_wrapper.per_cut_render_framing must define exactly CUT01-CUT03")
    for cut in per_cut:
        if not isinstance(cut, dict):
            raise ValueError(f"{packet_id}: render_wrapper.per_cut_render_framing entries must be objects")
        validate_render_framing_cut(packet_id, cut)


def validate_imagegen_guard(manifest: dict[str, Any]) -> None:
    packet_id = str(manifest.get("packet_id") or "")
    guard = manifest.get("imagegen_guard")
    if not isinstance(guard, dict) or not guard:
        raise ValueError(f"{packet_id}: imagegen_guard is required before API submit")
    require_fields(
        f"{packet_id}: imagegen_guard",
        guard,
        (
            "api_output_unit",
            "render_prompt_mode",
            "aspect_ratio",
            "size",
            "face_reference_input_policy",
            "lighting_integration_policy",
            "quality_anatomy_guard",
            "crop_safe_frame_policy",
        ),
    )
    if guard.get("api_output_unit") not in {"individual_cut_keyframe", "individual_beat_keyframe"}:
        raise ValueError(
            f"{packet_id}: imagegen_guard.api_output_unit must be individual_cut_keyframe"
            " or legacy individual_beat_keyframe"
        )
    if guard.get("render_prompt_mode") not in {"single_keyframe_3_2", "single_keyframe_16_9"}:
        raise ValueError(f"{packet_id}: imagegen_guard.render_prompt_mode must be single_keyframe_3_2 or single_keyframe_16_9")
    if guard.get("render_prompt_mode") == "single_keyframe_16_9" and guard.get("aspect_ratio") != "16:9":
        raise ValueError(f"{packet_id}: single_keyframe_16_9 must use 16:9 aspect_ratio")
    blocked = " ".join(str(item) for item in (guard.get("model_must_not_render") or [])).lower()
    for term in ("contact_sheet", "layout_wrapper", "visible_cut_labels", "right_reference_strip"):
        if term not in blocked:
            raise ValueError(f"{packet_id}: imagegen_guard.model_must_not_render must block {term}")


def validate_export_index_row(row: dict[str, Any]) -> None:
    required_fields = KEYFRAME_EXPORT_ROW_FIELDS if is_keyframe_export_row(row) else REQUIRED_EXPORT_ROW_FIELDS
    require_fields(str(row.get("packet_id") or "export index row"), row, required_fields)
    if not str(row.get("cut_id") or row.get("beat_id") or "").strip():
        raise ValueError(f"{row.get('packet_id')}: export index row missing cut_id")
    registry_path = str(row.get("title_output_registry_path") or "")
    if not registry_path.startswith("catalog/albums/") or not registry_path.endswith("/output-registry.yaml"):
        raise ValueError(f"{row.get('packet_id')}: title_output_registry_path must be catalog/albums/.../output-registry.yaml")


def selected_packet_rows(
    index: dict[str, Any], section_id: str, packet_ids: list[str], limit: int | None
) -> list[dict[str, Any]]:
    rows = [row for row in index.get("packets", []) if isinstance(row, dict)]
    if packet_ids:
        requested = set(packet_ids)
        rows = [row for row in rows if str(row.get("packet_id")) in requested]
        missing = sorted(requested - {str(row.get("packet_id")) for row in rows})
        if missing:
            raise ValueError("packet ids not found in export index: " + ", ".join(missing))
    if limit is not None:
        rows = rows[:limit]
    if not rows:
        raise ValueError("no packets selected")
    for row in rows:
        validate_export_index_row(row)
        if str(row.get("execution_section_id") or "") != section_id:
            raise ValueError(
                f"{row.get('packet_id')}: section execution package contains a packet owned by "
                f"{row.get('execution_section_id')}, not {section_id}"
            )
    return rows


def load_manifest(row: dict[str, Any]) -> dict[str, Any]:
    path = Path(str(row["manifest_path"]))
    if not path.is_absolute():
        path = Path.cwd() / path
    if not path.exists():
        raise FileNotFoundError(f"manifest not found: {path}")
    manifest = load_structured(path)
    manifest["_manifest_path"] = str(path)
    keyframe_manifest = is_keyframe_manifest(manifest)
    required_fields = KEYFRAME_MANIFEST_FIELDS if keyframe_manifest else REQUIRED_MANIFEST_FIELDS
    require_fields(str(manifest.get("packet_id") or path), manifest, required_fields)
    if not str(manifest.get("cut_id") or manifest.get("beat_id") or "").strip():
        raise ValueError(f"{manifest.get('packet_id')}: manifest missing cut_id")
    if row.get("title_key") != manifest.get("title_key"):
        raise ValueError(f"{manifest.get('packet_id')}: export index title_key must match manifest")
    if row.get("album_key") != manifest.get("album_key"):
        raise ValueError(f"{manifest.get('packet_id')}: export index album_key must match manifest")
    if str(row.get("execution_section_id") or "") != str(manifest.get("execution_section_id") or ""):
        raise ValueError(f"{manifest.get('packet_id')}: export index execution section must match manifest")
    registry_path = str(manifest.get("title_output_registry_path") or "")
    if registry_path != str(row.get("title_output_registry_path") or ""):
        raise ValueError(f"{manifest.get('packet_id')}: export index title registry path must match manifest")
    if not registry_path.startswith("catalog/albums/") or not registry_path.endswith("/output-registry.yaml"):
        raise ValueError(f"{manifest.get('packet_id')}: title_output_registry_path must be catalog/albums/.../output-registry.yaml")
    if not Path(registry_path).exists():
        raise FileNotFoundError(f"{manifest.get('packet_id')}: title output registry missing: {registry_path}")
    if keyframe_manifest:
        if row.get("expected_keyframe_image_path") != manifest.get("expected_keyframe_image_path"):
            raise ValueError(f"{manifest.get('packet_id')}: export index keyframe output path must match manifest")
        validate_imagegen_guard(manifest)
    else:
        if row.get("expected_board_image_path") != manifest.get("expected_board_image_path"):
            raise ValueError(f"{manifest.get('packet_id')}: export index board output path must match manifest")
        validate_render_wrapper(manifest)
    return manifest


def assert_manifest_pending(manifest: dict[str, Any], *, include_generated: bool) -> None:
    packet_id = str(manifest.get("packet_id") or "")
    output_path = Path(manifest_expected_output_path(manifest))
    if not output_path.is_absolute():
        output_path = Path.cwd() / output_path
    if include_generated:
        return
    if manifest.get("imagegen_status") != "not_generated":
        raise ValueError(f"{packet_id}: imagegen_status must be not_generated")
    allowed_review_statuses = {"not_generated", "ready_for_founder_review", "needs_pre_api_review"} if is_keyframe_manifest(manifest) else {"not_generated"}
    if manifest.get("founder_review_status") not in allowed_review_statuses:
        allowed_text = ", ".join(sorted(allowed_review_statuses))
        raise ValueError(f"{packet_id}: founder_review_status must be one of: {allowed_text}")
    if output_path.exists():
        raise FileExistsError(f"{packet_id}: expected output already exists: {output_path}")
    if manifest.get("generation_route") != "prompt_export_only":
        raise ValueError(f"{packet_id}: generation_route must be prompt_export_only before founder paid approval")


def image_input_records_for_manifest(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    refs = manifest.get("identity_reference") or {}
    if str(refs.get("identity_input") or "").strip().lower() == "none" or refs.get("face_visible") is False:
        return []
    inputs = refs.get("actual_image_inputs") or []
    records: list[dict[str, Any]] = []
    for item in inputs:
        if not isinstance(item, dict) or not item.get("attach_to_api", False):
            continue
        reference_mode = str(item.get("reference_mode") or "")
        if reference_mode and reference_mode != "face_only_reference":
            raise ValueError(f"{manifest.get('packet_id')}: image input reference_mode must be face_only_reference")
        path = Path(str(item.get("image_input_path") or ""))
        if not path.is_absolute():
            path = Path.cwd() / path
        if not path.exists():
            raise FileNotFoundError(f"{manifest.get('packet_id')}: image input not found: {path}")
        path_text = str(path).lower()
        if any(pattern in path_text for pattern in CHARACTER_BOARD_INPUT_PATTERNS):
            raise ValueError(f"{manifest.get('packet_id')}: character-board file cannot be an API image input: {path}")
        if "face-only-reference" not in path_text:
            raise ValueError(f"{manifest.get('packet_id')}: image input must be a face-only reference: {path}")
        reject_deprecated_identity_variant(str(manifest.get("packet_id") or ""), path)
        actual_sha256 = sha256_file(path)
        expected_sha256 = str(item.get("image_input_sha256") or "")
        if expected_sha256 and expected_sha256 != actual_sha256:
            raise ValueError(f"{manifest.get('packet_id')}: image input hash mismatch for {path}")
        records.append(
            {
                "path": path,
                "sha256": actual_sha256,
                "member_code": item.get("member_code", ""),
                "member_display_name": item.get("member_display_name", ""),
                "image_input_index": item.get("image_input_index", ""),
                "identity_anchor_label": item.get("identity_anchor_label", ""),
                "reference_mode": reference_mode or "face_only_reference",
                "input_role": "face_reference",
                "usage_rule": "identity anchor only; expression, lighting, styling, pose, and scene follow the current prompt",
            }
        )
    if not records:
        raise ValueError(f"{manifest.get('packet_id')}: no face-only image inputs")
    if len(records) > int(refs.get("max_attached_member_references") or 2):
        raise ValueError(f"{manifest.get('packet_id')}: too many face-only image inputs")
    duplicate_paths = sorted(
        {str(record["path"]) for record in records if [str(item["path"]) for item in records].count(str(record["path"])) > 1}
    )
    if duplicate_paths:
        raise ValueError(f"{manifest.get('packet_id')}: duplicate face-only image inputs: {', '.join(duplicate_paths)}")
    expected_indices = list(range(1, len(records) + 1))
    try:
        actual_indices = [int(record["image_input_index"] or 0) for record in records]
    except (TypeError, ValueError) as error:
        raise ValueError(f"{manifest.get('packet_id')}: face reference image_input_index must be numeric") from error
    if actual_indices != expected_indices:
        raise ValueError(f"{manifest.get('packet_id')}: face reference image_input_index must be 1..N in API attachment order")
    for record in records:
        if not str(record.get("member_display_name") or "").strip():
            raise ValueError(f"{manifest.get('packet_id')}: face reference for {record.get('member_code')} must include member_display_name")
        if not str(record.get("identity_anchor_label") or "").strip():
            raise ValueError(f"{manifest.get('packet_id')}: face reference for {record.get('member_code')} must include identity_anchor_label")
    return records


def scene_input_records_for_manifest(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    ref = manifest.get("scene_reference") or {}
    if not isinstance(ref, dict) or not ref.get("attach_to_api"):
        return []
    reference_mode = str(ref.get("reference_mode") or "")
    if reference_mode != "scene_composition_reference":
        raise ValueError(f"{manifest.get('packet_id')}: scene reference_mode must be scene_composition_reference")
    path = Path(str(ref.get("image_input_path") or ""))
    if not path.is_absolute():
        path = Path.cwd() / path
    if not path.exists():
        raise FileNotFoundError(f"{manifest.get('packet_id')}: scene reference input not found: {path}")
    actual_sha256 = sha256_file(path)
    expected_sha256 = str(ref.get("image_input_sha256") or "")
    if expected_sha256 and expected_sha256 != actual_sha256:
        raise ValueError(f"{manifest.get('packet_id')}: scene reference input hash mismatch for {path}")
    usage_rule = str(ref.get("usage_rule") or "")
    if not usage_rule:
        raise ValueError(f"{manifest.get('packet_id')}: scene reference usage_rule is required")
    return [
        {
            "path": path,
            "sha256": actual_sha256,
            "member_code": "",
            "member_display_name": "",
            "image_input_index": ref.get("image_input_index", ""),
            "identity_anchor_label": "",
            "reference_mode": reference_mode,
            "input_role": "scene_reference",
            "usage_rule": usage_rule,
            "transfer_locks": ref.get("transfer_locks") or {},
        }
    ]


def facepaint_input_records_for_manifest(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    ref = manifest.get("facepaint_reference") or {}
    if not isinstance(ref, dict) or not ref.get("attach_to_api"):
        return []
    reference_mode = str(ref.get("reference_mode") or "")
    if reference_mode != "facepaint_placement_reference":
        raise ValueError(f"{manifest.get('packet_id')}: facepaint reference_mode must be facepaint_placement_reference")
    path = Path(str(ref.get("image_input_path") or ""))
    if not path.is_absolute():
        path = Path.cwd() / path
    if not path.exists():
        raise FileNotFoundError(f"{manifest.get('packet_id')}: facepaint input not found: {path}")
    actual_sha256 = sha256_file(path)
    expected_sha256 = str(ref.get("image_input_sha256") or "")
    if expected_sha256 and expected_sha256 != actual_sha256:
        raise ValueError(f"{manifest.get('packet_id')}: facepaint input hash mismatch for {path}")
    return [
        {
            "path": path,
            "sha256": actual_sha256,
            "member_code": "",
            "member_display_name": "",
            "image_input_index": ref.get("image_input_index", ""),
            "identity_anchor_label": "secondary Pulso face-paint placement/color reference; identity remains the approved face-only reference",
            "reference_mode": reference_mode,
            "input_role": "facepaint_reference",
            "usage_rule": ref.get("usage_rule", ""),
        }
    ]


def all_image_input_records_for_manifest(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    records = (
        image_input_records_for_manifest(manifest)
        + scene_input_records_for_manifest(manifest)
        + facepaint_input_records_for_manifest(manifest)
    )
    return sorted(records, key=lambda record: int(record.get("image_input_index") or 0))


def image_inputs_for_manifest(manifest: dict[str, Any]) -> list[Path]:
    return [record["path"] for record in all_image_input_records_for_manifest(manifest)]


def identity_anchor_lines(manifest: dict[str, Any], *, input_only_language: bool = False) -> list[str]:
    refs = manifest.get("identity_reference") or {}
    anchor_records = refs.get("identity_anchor_order") or refs.get("actual_image_inputs") or []
    lines: list[str] = []
    for item in anchor_records:
        if not isinstance(item, dict):
            continue
        index = item.get("image_input_index", "")
        code = str(item.get("member_code") or "").strip()
        name = str(item.get("member_display_name") or code).strip()
        label = str(item.get("identity_anchor_label") or "").strip()
        if not label and index and code:
            label = f"attached face reference image #{index} = {name} (internal code {code}); use only as this idol's face identity anchor"
        if label:
            if input_only_language:
                label = re.sub(r"\s*;\s*do not render.*$", "", label, flags=re.I)
                lines.append(f"- {label}.")
            else:
                lines.append(f"- {label}; do not render the reference crop as a panel.")
    return lines


def facepaint_reference_lines(manifest: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    for record in facepaint_input_records_for_manifest(manifest):
        index = record.get("image_input_index", "")
        if index:
            lines.append(f"- attached image #{index} = Pulso face-paint placement/color reference; keep it secondary to the approved face-only identity reference.")
    return lines


def scene_reference_lines(manifest: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    for record in scene_input_records_for_manifest(manifest):
        index = record.get("image_input_index", "")
        locks = record.get("transfer_locks") or {}
        lock_text = "; ".join(str(value) for value in locks.values() if str(value).strip())
        usage = str(record.get("usage_rule") or "")
        if index:
            lines.append(
                f"- attached image #{index} = scene/composition reference; {usage}"
                + (f" Transfer locks: {lock_text}" if lock_text else "")
            )
    return lines


def active_prompt_text(prompt: str) -> str:
    active_lines: list[str] = []
    for line in prompt.splitlines():
        stripped = line.strip()
        lowered = stripped.lower()
        if lowered.startswith(("avoid:", "negative:", "forbidden:", "do not ", "no ")):
            continue
        if any(pattern.search(stripped) for _, pattern in ACTIVE_STALE_TERM_PATTERNS) and re.search(
            r"\b(avoid|do not|no|not|without|forbidden|block|exclude)\b", lowered
        ):
            continue
        active_lines.append(line)
    return "\n".join(active_lines)


def prompt_line(prompt: str, label: str) -> str:
    for line in prompt.splitlines():
        if re.match(rf"^{re.escape(label)}:", line, re.I):
            return line
    return ""


def prompt_line_any(prompt: str, labels: tuple[str, ...]) -> str:
    for label in labels:
        line = prompt_line(prompt, label)
        if line:
            return line
    return ""


def reject_action_lyric_leak(packet_id: str, label: str, text: str) -> None:
    if ACTION_FIELD_LYRIC_LEAK_PATTERN.search(text):
        raise ValueError(
            f"{packet_id}: {label} must translate raw lyric words into visible "
            "body/object/camera action"
        )


def prompt_lint(prompt: str, packet_id: str) -> dict[str, Any]:
    warnings: list[str] = []
    char_count = len(prompt)
    byte_count = len(prompt.encode("utf-8"))
    if char_count > PROMPT_HARD_FAIL_CHARS:
        raise ValueError(
            f"{packet_id}: prompt is too long for short director compile "
            f"({char_count} chars > {PROMPT_HARD_FAIL_CHARS})"
        )
    if char_count > PROMPT_WARNING_CHARS:
        warnings.append(f"prompt length warning: {char_count} chars > {PROMPT_WARNING_CHARS}")

    missing_quality_terms = [
        term for term in ("4K", "high quality", "high detail") if term.lower() not in prompt.lower()
    ]
    if missing_quality_terms:
        raise ValueError(
            f"{packet_id}: prompt must include 4K, high quality, and high detail before Batch preparation"
        )

    visual_details = prompt_line_any(prompt, VISUAL_DETAILS_LABELS)
    if prompt_line(prompt, LEGACY_VISUAL_EVIDENCE_LABEL) and not prompt_line(prompt, VISIBLE_DETAILS_LABEL):
        warnings.append("legacy prompt label warning: use Visible details instead of Visual evidence")

    identity_ok = re.search(
        r"attached face references?.+face identit(?:y|ies)|face references?.+identit(?:y|ies)",
        prompt,
        re.I | re.S,
    ) or re.search(r"^Identity reference rule:\s*No face reference is attached", prompt, re.I | re.M)
    checks = {
        "identity_reference_rule": identity_ok,
        "scene_intent": re.search(r"^Scene intent:", prompt, re.I | re.M),
        "visual_evidence": visual_details
        and CONCRETE_CAMERA_PATTERN.search(visual_details)
        and re.search(r"\b(angle|shot scale|composition|framing)\b", visual_details, re.I)
        and re.search(r"\bwardrobe\b", visual_details, re.I),
        "beat_response": re.search(r"^(?:Beat response|Action cue):", prompt, re.I | re.M),
        "avoid": re.search(r"^Avoid:", prompt, re.I | re.M),
    }
    missing = [name for name, ok in checks.items() if not ok]
    if missing:
        raise ValueError(f"{packet_id}: prompt missing required compile fields: {', '.join(missing)}")

    core_leaks = [label for label, pattern in CORE_PROMPT_FORBIDDEN_PATTERNS if pattern.search(prompt)]
    if core_leaks:
        raise ValueError(
            f"{packet_id}: prompt contains internal/layout/review terms that do not belong in the API core prompt: "
            f"{', '.join(core_leaks)}"
        )

    scene_intent = prompt_line(prompt, "Scene intent")
    reject_action_lyric_leak(packet_id, "Scene intent body action", scene_intent)
    if not (
        CONCRETE_MEMBER_PATTERN.search(scene_intent)
        and CONCRETE_SPACE_PATTERN.search(scene_intent)
        and CONCRETE_ACTION_PATTERN.search(scene_intent)
    ):
        raise ValueError(f"{packet_id}: Scene intent must concretely state who, where, and visible action")

    visual_evidence = prompt_line_any(prompt, VISUAL_DETAILS_LABELS)
    reject_action_lyric_leak(packet_id, "Visible details action/readability", visual_evidence)
    if not (
        CONCRETE_CAMERA_PATTERN.search(visual_evidence)
        and CONCRETE_ACTION_PATTERN.search(visual_evidence)
        and re.search(r"\bwardrobe\b", visual_evidence, re.I)
    ):
        raise ValueError(f"{packet_id}: Visible details must state body/action, camera treatment, and wardrobe")

    beat_response = prompt_line_any(prompt, BEAT_RESPONSE_LABELS)
    if not CONCRETE_BEAT_RESPONSE_PATTERN.search(beat_response) or re.search(
        r"\b(?:audio|timecode|bpm|section id|cue id)\b", beat_response, re.I
    ):
        raise ValueError(
            f"{packet_id}: Beat response/Action cue must translate timing into visible body/gaze/fabric/camera reaction"
        )

    active_text = active_prompt_text(prompt)
    stale_hits = [label for label, pattern in ACTIVE_STALE_TERM_PATTERNS if pattern.search(active_text)]
    if stale_hits:
        raise ValueError(f"{packet_id}: active prompt contains stale visual terms: {', '.join(stale_hits)}")

    return {
        "prompt_chars": char_count,
        "prompt_bytes": byte_count,
        "extracted_prompt_sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
        "warnings": warnings,
    }


def prompt_for_manifest(manifest: dict[str, Any]) -> str:
    prompt_path = Path(manifest_prompt_export_path(manifest))
    if not prompt_path.is_absolute():
        prompt_path = Path.cwd() / prompt_path
    if not prompt_path.exists():
        raise FileNotFoundError(f"{manifest.get('packet_id')}: prompt export missing: {prompt_path}")
    prompt = extract_full_prompt(prompt_path.read_text(encoding="utf-8"))
    if not prompt:
        raise ValueError(f"{manifest.get('packet_id')}: prompt export is empty")
    forbidden = ("imagegen_status:", "founder_review_status:", "paid_generation_gate:", "generation_route:")
    if any(token in prompt for token in forbidden):
        raise ValueError(f"{manifest.get('packet_id')}: prompt contains operational status text")
    prompt_lint(prompt, str(manifest.get("packet_id") or ""))
    return prompt


def coordinate_region_lines(wrapper: dict[str, Any]) -> list[str]:
    regions = wrapper.get("fixed_coordinate_regions") or []
    lines: list[str] = []
    for region in regions:
        if not isinstance(region, dict):
            continue
        lines.append(
            "- {region}: x={x} y={y} w={w} h={h}; {purpose}".format(
                region=region.get("region", ""),
                x=region.get("x", ""),
                y=region.get("y", ""),
                w=region.get("w", ""),
                h=region.get("h", ""),
                purpose=region.get("purpose", ""),
            )
        )
    return lines


def api_prompt_for_manifest(manifest: dict[str, Any]) -> str:
    core_prompt = prompt_for_manifest(manifest)
    if is_keyframe_manifest(manifest):
        guard = manifest.get("imagegen_guard") or {}
        identity_lines = identity_anchor_lines(manifest, input_only_language=True)
        if not identity_lines:
            identity_lines = ["- No face reference image is attached for this no-face keyframe; follow the core prompt's body, object, wardrobe, and space identity cues."]
        guard_prompt = [
            "IDENTITY INPUTS:",
            *identity_lines,
            "SCENE REFERENCE INPUTS:",
            *scene_reference_lines(manifest),
            "FACE PAINT INPUTS:",
            *facepaint_reference_lines(manifest),
            "When the core prompt names an internal member code, resolve it through the identity input list above. Use scene references only for camera, space, light, texture, material, motif/object behavior, and action-center transfer.",
            "CORE IMAGE PROMPT:",
            core_prompt,
            "QUALITY AND INPUT GUARD:",
            "Generate one standalone cinematic IDOL MV keyframe from the core prompt and its current-run background/world lock, not a storyboard, contact sheet, or multi-panel layout.",
            str(guard.get("background_text_lock") or ""),
            str(guard.get("wardrobe_text_lock") or ""),
            str(guard.get("wardrobe_negative_guard") or ""),
            str(guard.get("face_lighting_lock") or ""),
            str(guard.get("body_proportion_lock") or ""),
            "Attached face images are identity inputs only; keep them out of the scene as separate crops, stickers, thumbnails, or pasted heads.",
            str(guard.get("lighting_integration_policy") or "Match the generated face identity to the scene lighting, exposure, perspective, neck connection, shoulder connection, and body scale."),
            str(guard.get("quality_anatomy_guard") or "High quality clean anatomy with readable hands, fingers, feet, shoulders, hips, and fabric."),
            str(guard.get("crop_safe_frame_policy") or "Keep the member body action crop-safe inside the generated frame."),
            "No panels, no labels, no inset photos, no split screen, no contact sheet, no storyboard text, no local paths, no schema text.",
        ]
        return "\n".join(line for line in guard_prompt if str(line).strip())

    wrapper = manifest.get("render_wrapper") or {}
    label = wrapper.get("top_left_label_block") or {}
    coordinate_lines = coordinate_region_lines(wrapper)
    per_cut = wrapper.get("per_cut_render_framing") or []
    cut_lines = [
        "- {cut}: {framing_class}; visibility: {required_visibility}; crop: {crop_rule}; purpose: {framing_purpose}".format(
            cut=cut.get("cut", ""),
            framing_class=cut.get("framing_class", ""),
            required_visibility=cut.get("required_visibility", ""),
            crop_rule=cut.get("crop_rule", ""),
            framing_purpose=cut.get("framing_purpose", ""),
        )
        for cut in per_cut
        if isinstance(cut, dict)
    ]
    wrapper_prompt = [
        "NON-CREATIVE RENDER WRAPPER:",
        f"Canvas {wrapper.get('aspect_ratio')} / {wrapper.get('size')}; layout profile {wrapper.get('layout_profile_id')}; layout mode {wrapper.get('layout_mode')}.",
        "Use fixed percent coordinates exactly. Do not rewrite the core scene intent, action, camera, wardrobe, world, or empathy.",
        f"Top-left label block x={label.get('x')} y={label.get('y')} w={label.get('w')} h={label.get('h')}: render small readable text exactly: {label.get('visible_text')}.",
        str(wrapper.get("panel_label_policy") or ""),
        str(wrapper.get("render_guard_policy") or ""),
        str(wrapper.get("face_reference_lighting_policy") or ""),
        "IDENTITY ANCHORS (API image input order):",
        *identity_anchor_lines(manifest),
        "When the core prompt names an internal member code, resolve it through the identity anchor list above.",
        "Fixed coordinate regions:",
        *coordinate_lines,
        "Per-cut render framing:",
        *cut_lines,
        "CORE DIRECTOR PROMPT:",
        core_prompt,
    ]
    return "\n".join(line for line in wrapper_prompt if str(line).strip())


def required_highest_quality(requested: str, manifest_value: str = "") -> str:
    selected = requested or manifest_value or REQUIRED_IMAGE_QUALITY
    if selected != REQUIRED_IMAGE_QUALITY:
        raise ValueError(
            f"02B image generation requires quality={REQUIRED_IMAGE_QUALITY}; lower quality is forbidden"
        )
    return REQUIRED_IMAGE_QUALITY


def required_maximum_size(requested: str) -> str:
    selected = requested or "1536x1024"
    if selected not in MAXIMUM_SUPPORTED_IMAGE_SIZES:
        raise ValueError(
            "02B image generation size must be one of the maximum supported dimensions "
            f"for the locked orientation: {sorted(MAXIMUM_SUPPORTED_IMAGE_SIZES)}"
        )
    return selected


def request_for_manifest(manifest: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    prompt = api_prompt_for_manifest(manifest)
    images = [{"image_url": image_data_url(path)} for path in image_inputs_for_manifest(manifest)]
    model_plan = manifest.get("model_plan") or {}
    model = require_openai_image_model(
        args.model or model_plan.get("model") or "gpt-image-2",
        context=f"{manifest.get('packet_id', 'packet')} model_plan.model",
    )
    quality = required_highest_quality(args.quality, str(model_plan.get("quality") or ""))
    size = required_maximum_size(args.size)
    body: dict[str, Any] = {
        "model": model,
        "prompt": prompt,
        "n": 1,
        "size": size,
        "quality": quality,
        "output_format": args.output_format,
    }
    url = ENDPOINT
    if images:
        body["images"] = images
    else:
        url = GENERATIONS_ENDPOINT
    return {
        "custom_id": str(manifest["packet_id"]),
        "method": "POST",
        "url": url,
        "body": body,
    }


def compact_plan(row: dict[str, Any], manifest: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    prompt = prompt_for_manifest(manifest)
    api_prompt = api_prompt_for_manifest(manifest)
    image_input_records = all_image_input_records_for_manifest(manifest)
    return {
        "album_key": manifest["album_key"],
        "title_key": manifest["title_key"],
        "title_display_name": manifest["title_display_name"],
        "title_output_root": manifest["title_output_root"],
        "title_output_registry_path": manifest["title_output_registry_path"],
        "packet_id": manifest["packet_id"],
        "execution_section_id": manifest["execution_section_id"],
        "cut_id": manifest.get("cut_id") or manifest.get("beat_id", ""),
        "beat_id": manifest.get("beat_id", ""),
        "manifest": manifest["_manifest_path"],
        "prompt_path": manifest_prompt_export_path(manifest),
        "output": manifest_expected_output_path(manifest),
        "members": row.get("members", []),
        "layout_mode": manifest.get("layout_mode", ""),
        "render_prompt_mode": (manifest.get("imagegen_guard") or {}).get("render_prompt_mode", ""),
        "model": require_openai_image_model(
            args.model or (manifest.get("model_plan") or {}).get("model") or "gpt-image-2",
            context=f"{manifest.get('packet_id', 'packet')} plan model",
        ),
        "size": required_maximum_size(args.size),
        "quality": required_highest_quality(
            args.quality, str((manifest.get("model_plan") or {}).get("quality") or "")
        ),
        "output_format": args.output_format,
        "prompt_lint": prompt_lint(prompt, str(manifest.get("packet_id") or "")),
        "api_prompt_chars": len(api_prompt),
        "api_prompt_bytes": len(api_prompt.encode("utf-8")),
        "image_input_count": len(image_input_records),
        "image_inputs": [
            {
                "path": str(record["path"]),
                "sha256": record["sha256"],
                "member_code": record["member_code"],
                "reference_mode": record["reference_mode"],
                "input_role": record.get("input_role", ""),
                "usage_rule": record.get("usage_rule", ""),
            }
            for record in image_input_records
        ],
        "founder_layout_review_required_before_api": False
        if is_keyframe_manifest(manifest)
        else str(manifest.get("layout_mode") or "").startswith(("route_", "performance_", "stage_motion_")),
    }


def title_catalog_from_manifests(manifests: list[dict[str, Any]]) -> dict[str, str]:
    first = manifests[0]
    keys = ("album_key", "title_key", "title_display_name", "title_output_root", "title_output_registry_path")
    catalog = {key: str(first.get(key) or "") for key in keys}
    for manifest in manifests[1:]:
        for key in keys:
            if str(manifest.get(key) or "") != catalog[key]:
                raise ValueError(f"{manifest.get('packet_id')}: mixed title catalog values are not allowed in one batch ({key})")
    return catalog


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    run_root = resolve_run(args.run)
    index = load_export_index(run_root, args.section_id, args.export_index)
    rows = selected_packet_rows(index, args.section_id, args.packet_id, args.limit)
    manifests = [load_manifest(row) for row in rows]
    for manifest in manifests:
        assert_manifest_pending(manifest, include_generated=args.include_generated)
    run_label = args.run_label or f"batch-api-{args.section_id}-{now_label()}"
    batch_dir = default_batch_dir(run_root, run_label)
    request_path = batch_dir / "request.jsonl"
    state_path = batch_dir / "batch-api-run.json"
    request_rows = [request_for_manifest(manifest, args) for manifest in manifests]
    request_bytes = "".join(jsonl_dump(row) for row in request_rows).encode("utf-8")
    plans = [compact_plan(row, manifest, args) for row, manifest in zip(rows, manifests)]
    title_catalog = title_catalog_from_manifests(manifests)
    layout_review_required = any(plan["founder_layout_review_required_before_api"] for plan in plans)
    endpoints = sorted({row["url"] for row in request_rows})
    state = {
        "schema_version": SCHEMA_VERSION,
        "status": "prepared",
        "created_at": now_iso(),
        "content_id": index.get("content_id", ""),
        "execution_section_id": args.section_id,
        "title_catalog": title_catalog,
        "run_root": str(run_root),
        "run_label": run_label,
        "endpoint": endpoints[0] if len(endpoints) == 1 else "mixed:" + ",".join(endpoints),
        "completion_window": COMPLETION_WINDOW,
        "discount_mode": {
            "route": "OpenAI Batch API",
            "completion_window": COMPLETION_WINDOW,
            "note": "Founder shorthand 할인/discount means Batch API route; no exact price claim is made here.",
        },
        "request_count": len(request_rows),
        "request_jsonl_path": str(request_path),
        "request_jsonl_bytes": len(request_bytes),
        "request_jsonl_sha256": hashlib.sha256(request_bytes).hexdigest(),
        "founder_api_approval_required": True,
        "founder_layout_review_before_api": {
            "required": layout_review_required,
            "approval_flag": "--layout-review-approved",
        },
        "plans": plans,
        "openai": {
            "batch_id": "",
            "input_file_id": "",
            "output_file_id": "",
            "error_file_id": "",
            "last_batch_status": "",
            "batch_object": {},
        },
        "local_files": {
            "state_path": str(state_path),
            "output_jsonl_path": str(batch_dir / "output.jsonl"),
            "error_jsonl_path": str(batch_dir / "errors.jsonl"),
            "import_report_path": str(batch_dir / "import-report.json"),
        },
    }
    if args.write:
        batch_dir.mkdir(parents=True, exist_ok=True)
        request_path.write_bytes(request_bytes)
        state_path.write_text(json_dump(state), encoding="utf-8")
        title_registry.register_batch_state_data(state_path, state, write=True)
    return {
        "state": str(state_path),
        "write": bool(args.write),
        "request_count": len(request_rows),
        "request_jsonl_sha256": state["request_jsonl_sha256"],
        "execution_section_id": args.section_id,
        "layout_review_required": layout_review_required,
        "packets": [plan["packet_id"] for plan in plans],
    }


def load_state(path_value: str) -> tuple[Path, dict[str, Any]]:
    path = Path(path_value)
    if not path.is_absolute():
        path = Path.cwd() / path
    state = json.loads(path.read_text(encoding="utf-8"))
    if state.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"unsupported state schema: {state.get('schema_version')}")
    return path, state


def write_state(path: Path, state: dict[str, Any]) -> None:
    path.write_text(json_dump(state), encoding="utf-8")


def assert_state_pending(state: dict[str, Any], *, include_generated: bool = False) -> None:
    for plan in state.get("plans", []):
        manifest = load_structured(Path(plan["manifest"]))
        assert_manifest_pending(manifest, include_generated=include_generated)


def submit(args: argparse.Namespace) -> dict[str, Any]:
    if not args.write:
        raise ValueError("submit requires --write")
    if not args.founder_approved:
        raise ValueError("submit requires --founder-approved for paid Batch API execution")
    state_path, state = load_state(args.state)
    visual_review_block = state.get("visual_review_block") or {}
    if visual_review_block.get("blocked"):
        reason = visual_review_block.get("reason") or "visual review block is active"
        raise ValueError(f"submit blocked: {reason}")
    if state.get("openai", {}).get("batch_id") and not args.force:
        raise ValueError("state already has a batch_id; use --force only for an intentional duplicate")
    if state.get("founder_layout_review_before_api", {}).get("required") and not args.layout_review_approved:
        raise ValueError("layout-review gate is required; pass --layout-review-approved only after founder approval")
    assert_state_pending(state, include_generated=args.include_generated)
    request_path = Path(state["request_jsonl_path"])
    if sha256_file(request_path) != state["request_jsonl_sha256"]:
        raise ValueError("request JSONL hash mismatch; rerun prepare")
    assert_openai_image_request_jsonl(request_path, context="02B Batch API submit")
    client = require_openai_client(Path(args.env_file))
    with request_path.open("rb") as handle:
        input_file = client.files.create(file=handle, purpose="batch")
    batch = client.batches.create(
        input_file_id=input_file.id,
        endpoint=ENDPOINT,
        completion_window=COMPLETION_WINDOW,
        metadata={
            "idol_content_id": str(state.get("content_id", ""))[:512],
            "idol_run_label": str(state.get("run_label", ""))[:512],
            "idol_route": "02b_imagegen_batch_api",
        },
    )
    batch_plain = object_to_plain(batch)
    state["status"] = "submitted"
    state["submitted_at"] = now_iso()
    state["founder_api_approval_record"] = {
        "approved": True,
        "approval_source": "current_thread",
        "route": "discount_mode_batch_api",
    }
    state["openai"].update(
        {
            "input_file_id": input_file.id,
            "input_file_object": object_to_plain(input_file),
            "batch_id": batch.id,
            "last_batch_status": batch_plain.get("status", ""),
            "batch_object": batch_plain,
        }
    )
    write_state(state_path, state)
    return {
        "state": str(state_path),
        "input_file_id": input_file.id,
        "batch_id": batch.id,
        "batch_status": batch_plain.get("status", ""),
        "request_count": state.get("request_count", 0),
    }


def status(args: argparse.Namespace) -> dict[str, Any]:
    state_path, state = load_state(args.state)
    batch_id = state.get("openai", {}).get("batch_id")
    if not batch_id:
        raise ValueError("state has no batch_id; run submit first")
    client = require_openai_client(Path(args.env_file))
    batch = object_to_plain(client.batches.retrieve(batch_id))
    state["openai"].update(
        {
            "last_batch_status": batch.get("status", ""),
            "output_file_id": batch.get("output_file_id") or "",
            "error_file_id": batch.get("error_file_id") or "",
            "batch_object": batch,
        }
    )
    state["status_checked_at"] = now_iso()
    if batch.get("status") in TERMINAL_STATUSES:
        state["status"] = str(batch.get("status"))
    if args.write:
        write_state(state_path, state)
    return {
        "state": str(state_path),
        "write": bool(args.write),
        "batch_id": batch_id,
        "batch_status": batch.get("status", ""),
        "request_counts": batch.get("request_counts", {}),
    }


def read_response_bytes(response: Any) -> bytes:
    content = response.read()
    if isinstance(content, str):
        return content.encode("utf-8")
    return bytes(content)


def download(args: argparse.Namespace) -> dict[str, Any]:
    if not args.write:
        raise ValueError("download requires --write")
    state_path, state = load_state(args.state)
    batch_id = state.get("openai", {}).get("batch_id")
    if not batch_id:
        raise ValueError("state has no batch_id; run submit first")
    client = require_openai_client(Path(args.env_file))
    batch = object_to_plain(client.batches.retrieve(batch_id))
    state["openai"].update(
        {
            "last_batch_status": batch.get("status", ""),
            "output_file_id": batch.get("output_file_id") or "",
            "error_file_id": batch.get("error_file_id") or "",
            "batch_object": batch,
        }
    )
    output_path = Path(state["local_files"]["output_jsonl_path"])
    error_path = Path(state["local_files"]["error_jsonl_path"])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    downloaded: dict[str, str] = {}
    if state["openai"].get("output_file_id"):
        output_path.write_bytes(read_response_bytes(client.files.content(state["openai"]["output_file_id"])))
        downloaded["output_jsonl_path"] = str(output_path)
    if state["openai"].get("error_file_id"):
        error_path.write_bytes(read_response_bytes(client.files.content(state["openai"]["error_file_id"])))
        downloaded["error_jsonl_path"] = str(error_path)
    if not downloaded:
        raise ValueError(f"batch has no downloadable output/error files yet; status={batch.get('status')}")
    state["downloaded_at"] = now_iso()
    state["local_files"]["downloaded"] = downloaded
    write_state(state_path, state)
    return {"state": str(state_path), "batch_status": batch.get("status", ""), "downloaded": downloaded}


def iter_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as error:
            raise ValueError(f"{path}:{line_number}: invalid JSONL: {error}") from error
    return rows


def image_bytes_from_batch_line(line: dict[str, Any]) -> bytes:
    response = line.get("response") or {}
    body = response.get("body") or {}
    data = body.get("data") or []
    if not data or not isinstance(data, list):
        raise ValueError("response.body.data[0].b64_json is missing")
    b64_json = data[0].get("b64_json") if isinstance(data[0], dict) else ""
    if not b64_json:
        raise ValueError("response.body.data[0].b64_json is missing")
    return base64.b64decode(b64_json)


def import_results(args: argparse.Namespace) -> dict[str, Any]:
    state_path, state = load_state(args.state)
    if args.download:
        download(argparse.Namespace(state=args.state, write=True, env_file=args.env_file))
        _, state = load_state(args.state)
    output_rows = iter_jsonl(Path(state["local_files"]["output_jsonl_path"]))
    error_rows = iter_jsonl(Path(state["local_files"]["error_jsonl_path"]))
    plans = {str(plan["packet_id"]): plan for plan in state.get("plans", [])}
    imported: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    for line in output_rows:
        packet_id = str(line.get("custom_id") or "")
        plan = plans.get(packet_id)
        if not plan:
            skipped.append({"packet_id": packet_id, "reason": "custom_id_not_in_state"})
            continue
        response = line.get("response") or {}
        status_code = int(response.get("status_code") or 0)
        if status_code < 200 or status_code >= 300 or line.get("error"):
            failed.append({"packet_id": packet_id, "status_code": status_code, "error": line.get("error") or response.get("body")})
            continue
        manifest_path = Path(plan["manifest"])
        manifest = load_structured(manifest_path)
        keyframe_manifest = is_keyframe_manifest(manifest)
        output_path = Path(plan["output"])
        if not output_path.is_absolute():
            output_path = Path.cwd() / output_path
        allowed_review_statuses = {"not_generated", "ready_for_founder_review"} if keyframe_manifest else {"not_generated"}
        if not args.force and (
            manifest.get("imagegen_status") != "not_generated"
            or manifest.get("founder_review_status") not in allowed_review_statuses
            or output_path.exists()
        ):
            skipped.append(
                {
                    "packet_id": packet_id,
                    "reason": "already_generated_or_not_pending",
                    "imagegen_status": manifest.get("imagegen_status", ""),
                    "founder_review_status": manifest.get("founder_review_status", ""),
                    "output_exists": output_path.exists(),
                }
            )
            continue
        try:
            image_bytes = image_bytes_from_batch_line(line)
        except (ValueError, binascii.Error) as error:
            failed.append({"packet_id": packet_id, "error": str(error)})
            continue
        if args.write:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(image_bytes)
            manifest["imagegen_status"] = "generated_pending_founder_review"
            manifest["founder_review_status"] = "generated_pending_founder_review"
            if keyframe_manifest:
                manifest["generated_keyframe_image_path"] = str(output_path)
            else:
                manifest["generated_review_image_path"] = str(output_path)
            manifest["imagegen_recorded_at"] = now_iso()
            manifest["batch_api_state_path"] = str(state_path)
            write_structured(manifest_path, manifest)
            title_registry.register_generated_review_image_from_manifest(manifest_path, manifest, output_path, write=True)
        imported.append({"packet_id": packet_id, "generated_image_ref": str(output_path), "write": bool(args.write)})
    for line in error_rows:
        failed.append({"packet_id": line.get("custom_id", ""), "error": line.get("error") or line})
    report = {
        "state": str(state_path),
        "write": bool(args.write),
        "output_rows": len(output_rows),
        "error_rows": len(error_rows),
        "imported_count": len(imported),
        "skipped_count": len(skipped),
        "failed_count": len(failed),
        "imported": imported,
        "skipped": skipped,
        "failed": failed,
    }
    if args.write:
        report_path = Path(state["local_files"]["import_report_path"])
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json_dump(report), encoding="utf-8")
        state["imported_at"] = now_iso()
        state["local_files"]["last_import_report_path"] = str(report_path)
        write_state(state_path, state)
    return report


def cancel(args: argparse.Namespace) -> dict[str, Any]:
    if not args.write:
        raise ValueError("cancel requires --write")
    state_path, state = load_state(args.state)
    batch_id = state.get("openai", {}).get("batch_id")
    if not batch_id:
        raise ValueError("state has no batch_id; run submit first")
    client = require_openai_client(Path(args.env_file))
    batch = object_to_plain(client.batches.cancel(batch_id))
    state["status"] = str(batch.get("status") or "cancelling")
    state["cancel_requested_at"] = now_iso()
    state["openai"]["last_batch_status"] = batch.get("status", "")
    state["openai"]["batch_object"] = batch
    write_state(state_path, state)
    return {"state": str(state_path), "batch_status": batch.get("status", "")}


def add_env_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--env-file", default=DEFAULT_ENV_FILE, help="local env file containing OPENAI_API_KEY; values are never printed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare", help="write Batch API request/state from 02B exports")
    prepare_parser.add_argument("--run", required=True, help="run root, e.g. runs/ALBUM_KEY/TITLE_KEY/RUN_ID")
    prepare_parser.add_argument(
        "--section-id",
        required=True,
        help="execution-owning section package to prepare; whole-song Batch requests are intentionally forbidden",
    )
    prepare_parser.add_argument("--export-index", default=None)
    prepare_parser.add_argument("--packet-id", action="append", default=[])
    prepare_parser.add_argument("--run-label", default="")
    prepare_parser.add_argument("--limit", type=int, default=None)
    prepare_parser.add_argument("--model", default="")
    prepare_parser.add_argument("--size", default="1536x1024")
    prepare_parser.add_argument("--quality", default="")
    prepare_parser.add_argument("--output-format", default="png")
    prepare_parser.add_argument("--include-generated", action="store_true")
    prepare_parser.add_argument("--write", action="store_true")

    submit_parser = subparsers.add_parser("submit", help="submit a prepared request to OpenAI Batch API")
    submit_parser.add_argument("--state", required=True)
    submit_parser.add_argument("--write", action="store_true")
    submit_parser.add_argument("--founder-approved", action="store_true")
    submit_parser.add_argument("--layout-review-approved", action="store_true")
    submit_parser.add_argument("--include-generated", action="store_true")
    submit_parser.add_argument("--force", action="store_true")
    add_env_arg(submit_parser)

    status_parser = subparsers.add_parser("status", help="retrieve remote Batch status")
    status_parser.add_argument("--state", required=True)
    status_parser.add_argument("--write", action="store_true")
    add_env_arg(status_parser)

    download_parser = subparsers.add_parser("download", help="download output/error JSONL when available")
    download_parser.add_argument("--state", required=True)
    download_parser.add_argument("--write", action="store_true")
    add_env_arg(download_parser)

    import_parser = subparsers.add_parser("import", help="import generated images into expected review paths")
    import_parser.add_argument("--state", required=True)
    import_parser.add_argument("--download", action="store_true")
    import_parser.add_argument("--write", action="store_true")
    import_parser.add_argument("--force", action="store_true")
    add_env_arg(import_parser)

    cancel_parser = subparsers.add_parser("cancel", help="cancel a remote Batch job")
    cancel_parser.add_argument("--state", required=True)
    cancel_parser.add_argument("--write", action="store_true")
    add_env_arg(cancel_parser)

    args = parser.parse_args()
    print(
        "ERROR: historical Batch runner is inactive; active 02B v2.2 Branch-Cut "
        "execution must use scripts/idol_prepare_image_generation_request.rb and "
        "a registered v7 request adapter",
        file=sys.stderr,
    )
    return 1
    try:
        if args.command == "prepare":
            result = prepare(args)
        elif args.command == "submit":
            result = submit(args)
        elif args.command == "status":
            result = status(args)
        elif args.command == "download":
            result = download(args)
        elif args.command == "import":
            result = import_results(args)
        elif args.command == "cancel":
            result = cancel(args)
        else:
            raise ValueError(f"unknown command: {args.command}")
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(json_dump(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
