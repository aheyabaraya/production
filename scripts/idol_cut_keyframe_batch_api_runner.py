#!/usr/bin/env python3
"""Prepare and run IDOL cut/beat-source keyframes through OpenAI Batch API.

This runner consumes a run-owned cut/beat-source keyframe manifest. It writes a
Batch API request JSONL where each row generates one visible storyboard cut
image or founder-approved beat source sheet. Face-reference manifests attach
only the declared face-only references as image inputs; five-or-more member
internal-identity manifests use text-only image generation with no image inputs.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from idol_openai_image_model_policy import assert_openai_image_request_jsonl, require_openai_image_model


SCHEMA_VERSION = "idol_cut_keyframe_batch_api.2026_05_v1"
MANIFEST_SCHEMA_VERSION = "idol_cut_only_keyframe_generation_manifest.v1"
EDIT_ENDPOINT = "/v1/images/edits"
GENERATION_ENDPOINT = "/v1/images/generations"
COMPLETION_WINDOW = "24h"
DEFAULT_ENV_FILE = ".runtime/secrets/openai-imagegen.env"
TERMINAL_STATUSES = {"completed", "failed", "expired", "cancelled"}
DEFAULT_CUT_ONLY_SIZE = "1536x1024"
DEFAULT_TWO_FRAME_SHEET_SIZE = "1280x1440"
DEFAULT_SINGLE_FRAME_16X9_SIZE = "1280x720"
REQUIRED_IMAGE_QUALITY = "high"
REQUIRED_PROMPT_TERMS = ("4K", "high quality", "high detail")
DEPRECATED_IDENTITY_VARIANT_PATTERN = re.compile(r"no[-_ ]?mic", re.I)
RETIRED_GENERATED_FACE_UPSCALE_PATTERN = re.compile(
    r"(?:^|/)face-only-reference-upscaled\.png$", re.I
)
LEGACY_RETIREMENT_MESSAGE = (
    "legacy cut/beat-source generation is retired for new prepare and submit; "
    "use one validated idol_image_generation_request.v8 per Branch Cut and the active section dispatch ledger"
)


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
        raise RuntimeError("PyYAML is required to read the cut/beat-source manifest")


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


def require_openai_client(env_file: Path):
    load_secret_env(env_file)
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is not set")
    try:
        from openai import OpenAI
    except ImportError as error:
        raise RuntimeError("openai package is not installed in this Python environment") from error
    return OpenAI()


def resolve_path(path_value: str | Path) -> Path:
    path = Path(path_value)
    return path if path.is_absolute() else Path.cwd() / path


def reject_deprecated_identity_variant(keyframe_id: str, path: Path) -> None:
    if RETIRED_GENERATED_FACE_UPSCALE_PATTERN.search(path.as_posix()):
        raise ValueError(
            f"{keyframe_id}: retired generated-master face-only upscale is not allowed; "
            f"use the registry-selected direct-source face-only upscale: {path}"
        )
    if DEPRECATED_IDENTITY_VARIANT_PATTERN.search(str(path)):
        raise ValueError(
            f"{keyframe_id}: deprecated no-mic identity reference is not allowed; use the approved face-only identity reference: {path}"
        )


def image_data_url(path: Path) -> str:
    mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def extract_visible_prompt(path: Path, header_mode: str = "cut_only") -> str:
    text = path.read_text(encoding="utf-8")
    marker = "## Visible Image Prompt"
    prompt = text.split(marker, 1)[1].strip() if marker in text else text.strip()
    missing_terms = [term for term in REQUIRED_PROMPT_TERMS if term.lower() not in prompt.lower()]
    if missing_terms:
        raise ValueError(
            f"{path}: prompt must include {', '.join(REQUIRED_PROMPT_TERMS)} before post-02B generation"
        )
    if header_mode == "two_frame_sheet":
        header = (
            "Use the attached face-only reference image(s) for facial identity anchoring. "
            "Do not take wardrobe, pose, background, crop marks, or layout from face-only identity references unless the packet explicitly marks those images as direct visual references. "
            "The visible output must be only the requested two-frame beat source sheet, with no reference panels, "
            "no visible labels, no captions, no UI, and no readable text. "
            "Each half of the sheet must be a clean crop-safe 16:9 MV still: top frame is the beat start pose, "
            "bottom frame is the beat end pose. Follow the declared wardrobe literally; do not replace packet-locked "
            "styling with office suiting, collared white office shirts, bare-leg skirts, generic runway fashion, "
            "tourist styling, armor, or any outfit lane absent from the prompt. Preserve the packet camera and framing; "
            "use medium, close-medium, or three-quarter performance framing only when no wider body route, floor line, "
            "or formation evidence is locked. Avoid forced solo full-body framing, below-footline distortion, crouch, "
            "kneel, or lunge unless the prompt explicitly asks.\n\n"
        )
    elif header_mode == "single_frame_16x9":
        header = (
            "Use the attached face-only reference image(s) for facial identity anchoring. "
            "Do not take wardrobe, pose, background, crop marks, or layout from face-only identity references unless the packet explicitly marks those images as direct visual references. "
            "The visible output must be only one clean crop-safe 16:9 beat source image, with no reference panels, "
            "no visible labels, no captions, no UI, and no readable text. Follow the declared wardrobe literally. "
            "For multi-member, group, or formation beats, preserve the packet camera and keep the frame only as wide as needed to read spacing, "
            "foot route, floor marks, synchronized body levels, and the intended center energy.\n\n"
        )
    elif header_mode == "single_frame_16x9_internal_group":
        header = (
            "No face reference images are attached for this five-or-more member group or formation beat. "
            "Use the model's internal IDOL group identity synthesis from the prompt's member list, roles, "
            "wardrobe lanes, blocking, center/edge placement, and scene context. The visible output must be only "
            "one clean crop-safe 16:9 beat source image, with no reference panels, no visible labels, no captions, "
            "no UI, and no readable text. Prioritize clean group readability, distinct silhouettes, correct spacing, "
            "and packet-locked wardrobe/action over exact individual face matching.\n\n"
        )
    else:
        header = (
            "Use the attached face-only reference image(s) for facial identity anchoring. "
            "Do not take wardrobe, pose, background, crop marks, or layout from face-only identity references unless the packet explicitly marks those images as direct visual references. "
            "The visible output must be only the requested storyboard CUT image, with no reference panels.\n\n"
        )
    return header + prompt


def generation_contract(manifest: dict[str, Any]) -> dict[str, Any]:
    contract = manifest.get("generation_contract") or {}
    return contract if isinstance(contract, dict) else {}


def prompt_header_mode_for_manifest(manifest: dict[str, Any]) -> str:
    return str(generation_contract(manifest).get("prompt_header_mode") or "cut_only")


def endpoint_for_manifest(manifest: dict[str, Any]) -> str:
    contract = generation_contract(manifest)
    endpoint = str(contract.get("api_endpoint") or "")
    if endpoint:
        return endpoint
    if str(contract.get("identity_source_mode") or "") == "model_internal_identity":
        return GENERATION_ENDPOINT
    return EDIT_ENDPOINT


def identity_source_mode_for_keyframe(manifest: dict[str, Any], keyframe: dict[str, Any]) -> str:
    mode = str(keyframe.get("identity_source_mode") or generation_contract(manifest).get("identity_source_mode") or "")
    return mode or "face_only_reference_inputs"


def default_size_for_manifest(manifest: dict[str, Any]) -> str:
    contract = generation_contract(manifest)
    if contract.get("size"):
        return str(contract["size"])
    if prompt_header_mode_for_manifest(manifest) == "two_frame_sheet":
        return DEFAULT_TWO_FRAME_SHEET_SIZE
    if prompt_header_mode_for_manifest(manifest) == "single_frame_16x9":
        return DEFAULT_SINGLE_FRAME_16X9_SIZE
    return DEFAULT_CUT_ONLY_SIZE


def default_quality_for_manifest(manifest: dict[str, Any]) -> str:
    return str(generation_contract(manifest).get("quality") or "high")


def required_highest_quality(requested: str, manifest_default: str) -> str:
    quality = requested or manifest_default or REQUIRED_IMAGE_QUALITY
    if quality != REQUIRED_IMAGE_QUALITY:
        raise ValueError(
            f"post-02B image generation requires quality={REQUIRED_IMAGE_QUALITY}; lower quality is forbidden"
        )
    return quality


def required_execution_section(plans: list[dict[str, Any]]) -> str:
    sections = sorted({str(plan.get("section") or "").strip() for plan in plans})
    if "" in sections:
        raise ValueError("every post-02B generation keyframe must declare its execution section")
    if len(sections) != 1:
        raise ValueError("post-02B generation prepare accepts exactly one section; split the manifest by section first")
    return sections[0]


def default_model_for_manifest(manifest: dict[str, Any]) -> str:
    return require_openai_image_model(
        generation_contract(manifest).get("model") or "gpt-image-2",
        context=f"{manifest.get('content_id', 'cut manifest')} generation_contract.model",
    )


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = load_structured(path)
    if not isinstance(manifest, dict):
        raise ValueError(f"manifest must be an object: {path}")
    if manifest.get("schema_version") != MANIFEST_SCHEMA_VERSION:
        raise ValueError(f"unsupported manifest schema: {manifest.get('schema_version')}")
    if manifest.get("status") != "ready_for_generation":
        raise ValueError("manifest status must be ready_for_generation")
    if not isinstance(manifest.get("keyframes"), list) or not manifest["keyframes"]:
        raise ValueError("manifest keyframes are missing")
    manifest["_manifest_path"] = str(path)
    return manifest


def prompt_path_for_keyframe(manifest: dict[str, Any], keyframe: dict[str, Any]) -> Path:
    prompt_dir = resolve_path(str(manifest["prompt_dir"]))
    stem = str(keyframe["id"]).lower()
    path = prompt_dir / f"{stem}.md"
    if not path.exists():
        raise FileNotFoundError(f"{keyframe['id']}: prompt file missing: {path}")
    return path


def api_face_ref_dir(manifest: dict[str, Any], args: argparse.Namespace) -> Path:
    if args.api_face_ref_dir:
        return resolve_path(args.api_face_ref_dir)
    return resolve_path(str(manifest["output_root"])) / "face-refs-api"


def make_api_face_ref_copy(source: Path, member_id: str, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{member_id}-face-only-reference-api.jpg"
    if out_path.exists() and out_path.stat().st_mtime >= source.stat().st_mtime:
        return out_path
    try:
        from PIL import Image
    except ImportError as error:
        raise RuntimeError("Pillow is required for --face-ref-mode api-copy") from error
    with Image.open(source) as image:
        image = image.convert("RGB")
        image.thumbnail((512, 768))
        image.save(out_path, format="JPEG", quality=92, optimize=True)
    return out_path


def make_tight_face_ref_copy(source: Path, member_id: str, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{member_id}-face-only-reference-tight-v2-api.jpg"
    if out_path.exists() and out_path.stat().st_mtime >= source.stat().st_mtime:
        return out_path
    try:
        from PIL import Image
    except ImportError as error:
        raise RuntimeError("Pillow is required for --face-ref-mode tight-crop") from error
    with Image.open(source) as image:
        image = image.convert("RGB")
        width, height = image.size
        # Source member refs are portrait beauty photos; crop away shoulders,
        # upper chest, and wardrobe so API input behaves as identity-only.
        left = int(width * 0.10)
        right = int(width * 0.90)
        top = int(height * 0.04)
        bottom = int(height * 0.60)
        crop = image.crop((left, top, right, bottom))
        crop.thumbnail((640, 768))
        crop.save(out_path, format="JPEG", quality=94, optimize=True)
    return out_path


def face_ref_records(manifest: dict[str, Any], keyframe: dict[str, Any], args: argparse.Namespace) -> list[dict[str, Path | str]]:
    identity_mode = identity_source_mode_for_keyframe(manifest, keyframe)
    declared_refs = keyframe.get("api_face_refs") or []
    if identity_mode == "model_internal_identity":
        if declared_refs:
            raise ValueError(f"{keyframe['id']}: internal identity mode must not declare API face refs")
        return []
    registry = manifest.get("member_face_refs") or {}
    records: list[dict[str, Path | str]] = []
    for ref_id in declared_refs:
        path_text = registry.get(ref_id)
        if not path_text:
            raise ValueError(f"{keyframe['id']}: missing member_face_refs entry for {ref_id}")
        source_path = resolve_path(str(path_text))
        if not source_path.exists():
            raise FileNotFoundError(f"{keyframe['id']}: face reference missing: {source_path}")
        if "face-only-reference" not in str(source_path).lower():
            raise ValueError(f"{keyframe['id']}: API input must be face-only reference: {source_path}")
        reject_deprecated_identity_variant(str(keyframe["id"]), source_path)
        if args.face_ref_mode == "tight-crop":
            request_path = make_tight_face_ref_copy(source_path, str(ref_id), api_face_ref_dir(manifest, args))
        elif args.face_ref_mode == "api-copy":
            request_path = make_api_face_ref_copy(source_path, str(ref_id), api_face_ref_dir(manifest, args))
        else:
            request_path = source_path
        if "face-only-reference" not in str(request_path).lower():
            raise ValueError(f"{keyframe['id']}: request image must remain face-only reference: {request_path}")
        records.append({"member_id": str(ref_id), "source_path": source_path, "request_path": request_path})
    if not records:
        raise ValueError(f"{keyframe['id']}: no face-only API refs declared")
    if len(records) > 2:
        raise ValueError(f"{keyframe['id']}: max two face-only refs per request")
    if len({str(record["request_path"]) for record in records}) != len(records):
        raise ValueError(f"{keyframe['id']}: duplicate face-only refs")
    return records


def output_path_for_keyframe(manifest: dict[str, Any], keyframe: dict[str, Any]) -> Path:
    output_root = resolve_path(str(manifest["output_root"]))
    return output_root / str(keyframe["output_image"])


def build_plan(manifest: dict[str, Any], keyframe: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    prompt_path = prompt_path_for_keyframe(manifest, keyframe)
    refs = face_ref_records(manifest, keyframe, args)
    output_path = output_path_for_keyframe(manifest, keyframe)
    header_mode = prompt_header_mode_for_manifest(manifest)
    identity_mode = identity_source_mode_for_keyframe(manifest, keyframe)
    endpoint = GENERATION_ENDPOINT if identity_mode == "model_internal_identity" else endpoint_for_manifest(manifest)
    if output_path.exists() and not args.include_existing:
        raise FileExistsError(f"{keyframe['id']}: output already exists: {output_path}")
    return {
        "keyframe_id": keyframe["id"],
        "section": keyframe.get("section", ""),
        "timeline": keyframe.get("timeline", ""),
        "source_group": keyframe.get("source_group", ""),
        "prompt_path": str(prompt_path),
        "output": str(output_path),
        "model": require_openai_image_model(
            args.model or default_model_for_manifest(manifest),
            context=f"{keyframe['id']} generation model",
        ),
        "size": args.size or default_size_for_manifest(manifest),
        "quality": required_highest_quality(args.quality, default_quality_for_manifest(manifest)),
        "output_format": args.output_format,
        "prompt_header_mode": header_mode,
        "identity_source_mode": identity_mode,
        "endpoint": endpoint,
        "image_inputs": [
            {
                "path": str(record["request_path"]),
                "source_path": str(record["source_path"]),
                "sha256": sha256_file(Path(str(record["request_path"]))),
                "source_sha256": sha256_file(Path(str(record["source_path"]))),
                "member_id": str(record["member_id"]),
                "reference_mode": "face_only_reference",
            }
            for record in refs
        ],
    }


def request_for_plan(plan: dict[str, Any]) -> dict[str, Any]:
    prompt = extract_visible_prompt(Path(plan["prompt_path"]), str(plan.get("prompt_header_mode") or "cut_only"))
    images = [{"image_url": image_data_url(Path(item["path"]))} for item in plan["image_inputs"]]
    body = {
        "model": plan["model"],
        "prompt": prompt,
        "n": 1,
        "size": plan["size"],
        "quality": plan["quality"],
        "output_format": plan["output_format"],
    }
    if images:
        body["images"] = images
    return {
        "custom_id": plan["keyframe_id"],
        "method": "POST",
        "url": plan.get("endpoint") or EDIT_ENDPOINT,
        "body": body,
    }


def default_batch_dir(manifest: dict[str, Any], run_label: str) -> Path:
    return resolve_path(str(manifest["output_root"])) / "batch-api" / run_label


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    raise ValueError(LEGACY_RETIREMENT_MESSAGE)
    manifest_path = resolve_path(args.manifest)
    manifest = load_manifest(manifest_path)
    run_label = args.run_label or f"cut-keyframes-{now_label()}"
    batch_dir = default_batch_dir(manifest, run_label)
    request_path = batch_dir / "request.jsonl"
    state_path = batch_dir / "batch-api-run.json"
    plans = [build_plan(manifest, keyframe, args) for keyframe in manifest["keyframes"]]
    execution_section_id = required_execution_section(plans)
    endpoints = sorted({str(plan.get("endpoint") or EDIT_ENDPOINT) for plan in plans})
    if len(endpoints) != 1:
        raise ValueError(f"manifest mixes Batch API endpoints ({', '.join(endpoints)}); split routes before prepare")
    request_rows = [request_for_plan(plan) for plan in plans]
    request_bytes = "".join(jsonl_dump(row) for row in request_rows).encode("utf-8")
    state = {
        "schema_version": SCHEMA_VERSION,
        "status": "prepared",
        "created_at": now_iso(),
        "content_id": manifest.get("content_id", ""),
        "execution_section_id": execution_section_id,
        "manifest": str(manifest_path),
        "run_label": run_label,
        "endpoint": endpoints[0],
        "completion_window": COMPLETION_WINDOW,
        "request_count": len(request_rows),
        "request_jsonl_path": str(request_path),
        "request_jsonl_bytes": len(request_bytes),
        "request_jsonl_sha256": hashlib.sha256(request_bytes).hexdigest(),
        "founder_api_approval_required": True,
        "founder_api_approval_record": {},
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
    return {
        "state": str(state_path),
        "write": bool(args.write),
        "request_count": len(request_rows),
        "request_jsonl_sha256": state["request_jsonl_sha256"],
        "first_keyframe": plans[0]["keyframe_id"],
        "last_keyframe": plans[-1]["keyframe_id"],
    }


def load_state(path_value: str) -> tuple[Path, dict[str, Any]]:
    state_path = resolve_path(path_value)
    state = json.loads(state_path.read_text(encoding="utf-8"))
    if state.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"unsupported state schema: {state.get('schema_version')}")
    return state_path, state


def write_state(path: Path, state: dict[str, Any]) -> None:
    path.write_text(json_dump(state), encoding="utf-8")


def submit(args: argparse.Namespace) -> dict[str, Any]:
    raise ValueError(LEGACY_RETIREMENT_MESSAGE)
    if not args.write:
        raise ValueError("submit requires --write")
    if not args.founder_approved:
        raise ValueError("submit requires --founder-approved for paid Batch API execution")
    state_path, state = load_state(args.state)
    if state.get("status") != "prepared":
        raise ValueError(f"state status must be prepared for submit; got {state.get('status')}")
    if state.get("openai", {}).get("batch_id") and not args.force:
        raise ValueError("state already has a batch_id; use --force only for an intentional duplicate")
    request_path = Path(state["request_jsonl_path"])
    if sha256_file(request_path) != state["request_jsonl_sha256"]:
        raise ValueError("request JSONL hash mismatch; rerun prepare")
    assert_openai_image_request_jsonl(request_path, context="CUT keyframe Batch API submit")
    client = require_openai_client(Path(args.env_file))
    with request_path.open("rb") as handle:
        input_file = client.files.create(file=handle, purpose="batch")
    batch = client.batches.create(
        input_file_id=input_file.id,
        endpoint=str(state.get("endpoint") or EDIT_ENDPOINT),
        completion_window=COMPLETION_WINDOW,
        metadata={
            "idol_content_id": str(state.get("content_id", ""))[:512],
            "idol_run_label": str(state.get("run_label", ""))[:512],
            "idol_route": "cut_keyframe_imagegen_batch_api",
        },
    )
    batch_plain = object_to_plain(batch)
    state["status"] = "submitted"
    state["submitted_at"] = now_iso()
    state["founder_api_approval_record"] = {
        "approved": True,
        "approval_source": "current_thread",
        "route": "cut_keyframe_batch_api",
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
    plans = {str(plan["keyframe_id"]): plan for plan in state.get("plans", [])}
    imported: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    for line in output_rows:
        keyframe_id = str(line.get("custom_id") or "")
        plan = plans.get(keyframe_id)
        if not plan:
            skipped.append({"keyframe_id": keyframe_id, "reason": "custom_id_not_in_state"})
            continue
        response = line.get("response") or {}
        status_code = int(response.get("status_code") or 0)
        if status_code < 200 or status_code >= 300 or line.get("error"):
            failed.append({"keyframe_id": keyframe_id, "status_code": status_code, "error": line.get("error") or response.get("body")})
            continue
        output_path = Path(plan["output"])
        if output_path.exists() and not args.force:
            skipped.append({"keyframe_id": keyframe_id, "reason": "output_exists", "output": str(output_path)})
            continue
        try:
            image_bytes = image_bytes_from_batch_line(line)
        except ValueError as error:
            failed.append({"keyframe_id": keyframe_id, "error": str(error)})
            continue
        if args.write:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(image_bytes)
        imported.append({"keyframe_id": keyframe_id, "generated_image_ref": str(output_path), "write": bool(args.write)})
    for line in error_rows:
        failed.append({"keyframe_id": line.get("custom_id", ""), "error": line.get("error") or line})
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


def add_env_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--env-file", default=DEFAULT_ENV_FILE, help="local env file containing OPENAI_API_KEY; values are never printed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare", help="write Batch API request/state from a cut/beat-source manifest")
    prepare_parser.add_argument("--manifest", required=True)
    prepare_parser.add_argument("--run-label", default="")
    prepare_parser.add_argument("--model", default="", help="override model; defaults to manifest generation_contract.model or gpt-image-2")
    prepare_parser.add_argument("--size", default="", help="override size; defaults to manifest generation_contract.size")
    prepare_parser.add_argument("--quality", default="", help="only high is accepted; defaults to manifest generation_contract.quality or high")
    prepare_parser.add_argument("--output-format", default="png")
    prepare_parser.add_argument("--face-ref-mode", choices=("tight-crop", "api-copy", "original"), default="tight-crop")
    prepare_parser.add_argument("--api-face-ref-dir", default="")
    prepare_parser.add_argument("--include-existing", action="store_true")
    prepare_parser.add_argument("--write", action="store_true")

    submit_parser = subparsers.add_parser("submit", help="submit a prepared request to OpenAI Batch API")
    submit_parser.add_argument("--state", required=True)
    submit_parser.add_argument("--write", action="store_true")
    submit_parser.add_argument("--founder-approved", action="store_true")
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

    import_parser = subparsers.add_parser("import", help="import generated images into expected output paths")
    import_parser.add_argument("--state", required=True)
    import_parser.add_argument("--download", action="store_true")
    import_parser.add_argument("--write", action="store_true")
    import_parser.add_argument("--force", action="store_true")
    add_env_arg(import_parser)

    args = parser.parse_args()
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
        else:
            raise ValueError(f"unknown command: {args.command}")
    except Exception as error:
        print(json_dump({"ok": False, "error": str(error)}), end="")
        return 1
    print(json_dump({"ok": True, "result": result}), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
