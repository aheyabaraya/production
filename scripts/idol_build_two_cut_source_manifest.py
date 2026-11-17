#!/usr/bin/env python3
"""Build IDOL routed beat source manifests from 02B prompt packets.

Solo beats are routed to founder-approved two-cut source sheets. Beats with two
to four declared members are routed to separate single-frame 16:9 source images
with up to two API face refs. Five-or-more member group/formation beats are
routed to an internal-identity single-frame manifest with no API face refs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from idol_openai_image_model_policy import require_openai_image_model


MANIFEST_SCHEMA_VERSION = "idol_cut_only_keyframe_generation_manifest.v1"
TWO_CUT_CANVAS_WIDTH = 1280
TWO_CUT_CANVAS_HEIGHT = 1440
TWO_CUT_FRAME_HEIGHT = 720
SINGLE_FRAME_WIDTH = 1280
SINGLE_FRAME_HEIGHT = 720
INTERNAL_MODEL_MIN_SUBJECTS = 5
DEPRECATED_IDENTITY_VARIANT_PATTERN = re.compile(r"no[-_ ]?mic", re.I)
RETIRED_GENERATED_FACE_UPSCALE_PATTERN = re.compile(
    r"(?:^|/)face-only-reference-upscaled\.png$", re.I
)


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def load_yaml(path: Path) -> Any:
    import yaml  # type: ignore

    return yaml.safe_load(path.read_text(encoding="utf-8"))


def write_yaml(path: Path, data: Any) -> None:
    import yaml  # type: ignore

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=120),
        encoding="utf-8",
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve(path_text: str | Path) -> Path:
    path = Path(path_text)
    return path if path.is_absolute() else Path.cwd() / path


def rel_repo_path(path: Path | str) -> str:
    path_obj = Path(path)
    if not path_obj.is_absolute():
        return path_obj.as_posix()
    try:
        return path_obj.relative_to(Path.cwd()).as_posix()
    except ValueError:
        return path_obj.as_posix()


def validate_face_only_reference(path_text: str) -> str:
    path = resolve(path_text)
    path_lower = str(path).lower()
    if RETIRED_GENERATED_FACE_UPSCALE_PATTERN.search(path.as_posix()):
        raise ValueError(
            f"retired generated-master face-only upscale is not allowed: {path}; "
            "use the registry-selected direct-source face-only upscale"
        )
    if DEPRECATED_IDENTITY_VARIANT_PATTERN.search(str(path)):
        raise ValueError(
            f"deprecated no-mic identity reference is not allowed: {path}; use the approved face-only identity reference"
        )
    if "face-only-reference" not in path_lower:
        raise ValueError(f"member face reference must use the approved face-only identity reference: {path}")
    return path_text


def slug(text: str) -> str:
    value = text.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def slug_upper(text: str) -> str:
    value = text.strip().upper()
    value = re.sub(r"[^A-Z0-9]+", "_", value)
    return value.strip("_")


def clean_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return "; ".join(clean_text(item) for item in value if clean_text(item))
    if isinstance(value, dict):
        return "; ".join(f"{key}: {clean_text(item)}" for key, item in value.items() if clean_text(item))
    text = str(value)
    replacements = [
        (r"\bboot landing\b", "boot mark"),
        (r"\bboots landing\b", "boot marks"),
        (r"\bpose landing\b", "pose endpoint"),
        (r"\bcamera lands on\b", "camera finishes on"),
        (r"\blanding\b", "endpoint"),
        (r"\blands\b", "hits"),
        (r"\blanded\b", "ended"),
        (r"\bland\b", "hit"),
        (r"착지", "end pose"),
        (r"high quality,\s*detail high,\s*", ""),
        (r"high quality\s*", ""),
        (r"detail high,\s*", ""),
    ]
    for pattern, replacement in replacements:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    text = text.replace("  ", " ")
    return text.strip(" ;\n\t")


def prompt_camera_text(camera: str, shot_scale: str, member_count: int) -> tuple[str, str]:
    _ = member_count
    return camera, shot_scale


def member_display_name(code: str, identity_lock: dict[str, Any]) -> str:
    for trait in identity_lock.get("fixed_traits") or []:
        trait_text = str(trait)
        if trait_text.startswith(code):
            return trait_text.replace(" face identity", "")
    return code


def load_video_timelines(index_path: Path) -> dict[str, str]:
    timelines: dict[str, str] = {}
    if not index_path.exists():
        return timelines
    index = load_yaml(index_path) or {}
    prompt_rows = index.get("prompts") or []
    for row in prompt_rows:
        output_path = row.get("output_prompt_path")
        packet_id = row.get("packet_id")
        if not packet_id or not output_path:
            continue
        prompt_path = resolve(str(output_path))
        if not prompt_path.exists():
            continue
        for line in prompt_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("Timeline:"):
                timelines[str(packet_id)] = line.split(":", 1)[1].strip()
                break
    return timelines


def packet_by_id(packet_data: dict[str, Any]) -> list[dict[str, Any]]:
    packets = packet_data.get("prompt_packets") or packet_data.get("packets") or []
    if not isinstance(packets, list) or not packets:
        raise ValueError("02B packet file has no prompt_packets")
    return [packet for packet in packets if isinstance(packet, dict)]


def face_ref_registry(packets: list[dict[str, Any]]) -> dict[str, str]:
    registry: dict[str, str] = {}
    for packet in packets:
        refs = ((packet.get("identity_lock") or {}).get("member_references") or {})
        for code, record in refs.items():
            path_text = record.get("face_reference") if isinstance(record, dict) else ""
            if path_text:
                registry[str(code)] = validate_face_only_reference(str(path_text))
    return dict(sorted(registry.items()))


def registry_for_packets(packets: list[dict[str, Any]], registry: dict[str, str]) -> dict[str, str]:
    used = sorted({code for packet in packets for code in subject_codes(packet)})
    return {code: registry[code] for code in used if registry.get(code)}


def subject_codes(packet: dict[str, Any]) -> list[str]:
    focus = (packet.get("identity_lock") or {}).get("member_focus") or []
    return [str(item) for item in focus]


def title_display(packet_data: dict[str, Any], override: str = "") -> str:
    if override:
        return override
    catalog = packet_data.get("title_catalog") or {}
    for key in ("title_display_name", "title_display", "title", "title_key"):
        if catalog.get(key):
            return str(catalog[key]).upper()
    return str(packet_data.get("title_display_name") or packet_data.get("title_key") or "IDOL").upper()


def content_id_for(packet_data: dict[str, Any], override: str = "") -> str:
    content_id = str(override or packet_data.get("content_id") or "").strip()
    if not content_id:
        raise ValueError("content_id is missing; pass --content-id or set content_id in the 02B packet file")
    return content_id


def title_key_for_paths(packet_data: dict[str, Any], title_name: str, override: str = "") -> str:
    catalog = packet_data.get("title_catalog") or {}
    candidates = (
        override,
        catalog.get("title_key"),
        packet_data.get("title_key"),
        packet_data.get("content_id"),
        title_name,
        "idol",
    )
    for candidate in candidates:
        text = slug(str(candidate or ""))
        if text:
            return text
    return "idol"


def apply_derived_defaults(args: argparse.Namespace, packet_path: Path, packet_data: dict[str, Any], title_name: str) -> None:
    content_id = content_id_for(packet_data, args.content_id)
    title_key = title_key_for_paths(packet_data, title_name, args.title_key)
    if not args.title_key and title_key == "idol":
        title_key = slug(content_id) or title_key
    keyframe_prefix = slug_upper(args.keyframe_prefix or title_key or content_id or "IDOL")

    args.content_id = content_id
    args.title_key = title_key
    args.keyframe_prefix = keyframe_prefix
    if not args.output_root:
        args.output_root = str(packet_path.parent / "generations" / "image" / f"{title_key}-two-cut-solo-beat-source-v1")
    if not args.single_output_root:
        args.single_output_root = str(packet_path.parent / "generations" / "image" / f"{title_key}-single-cut-multi-beat-source-v1")
    if not args.group_internal_output_root:
        args.group_internal_output_root = str(packet_path.parent / "generations" / "image" / f"{title_key}-internal-group-beat-source-v1")
    if not args.manifest_out:
        args.manifest_out = str(packet_path.parent / f"02B-{title_key}-two-cut-solo-beat-source-generation-manifest-v1.yaml")
    if not args.single_manifest_out:
        args.single_manifest_out = str(packet_path.parent / f"02B-{title_key}-single-cut-multi-beat-source-generation-manifest-v1.yaml")
    if not args.group_internal_manifest_out:
        args.group_internal_manifest_out = str(packet_path.parent / f"02B-{title_key}-internal-group-beat-source-generation-manifest-v1.yaml")
    if not args.video_index:
        candidate_video_index = packet_path.parent / "generations" / "video-prompts" / "video-prompt-index.yaml"
        if candidate_video_index.exists():
            args.video_index = str(candidate_video_index)


def prompt_parts(packet: dict[str, Any]) -> dict[str, str | list[str]]:
    identity_lock = packet.get("identity_lock") or {}
    director = packet.get("director_chain") or {}
    micro_cut = ((packet.get("micro_beat_sheet") or {}).get("cuts") or [{}])[0]
    framing = packet.get("keyframe_framing_lock") or {}
    note = (packet.get("prompt_compile_contract") or {}).get("director_compile_note") or {}

    codes = subject_codes(packet)
    names = [member_display_name(code, identity_lock) for code in codes]
    member_count = len(codes)
    camera = clean_text(micro_cut.get("camera") or director.get("director_treatment") or note.get("camera_treatment"))
    shot_scale = clean_text(micro_cut.get("shot_scale") or framing.get("shot_scale") or note.get("action_scale"))
    camera_prompt, shot_scale_prompt = prompt_camera_text(camera, shot_scale, member_count)

    return {
        "codes": codes,
        "names": names,
        "who": " and ".join(names) if names else "the visible member",
        "space": clean_text(director.get("space_or_object") or micro_cut.get("space") or note.get("specific_space")),
        "action": clean_text(
            micro_cut.get("visible_body_action")
            or director.get("visible_action")
            or note.get("visible_action")
        ),
        "camera": camera_prompt,
        "wardrobe": clean_text(
            micro_cut.get("wardrobe")
            or director.get("wardrobe_read")
            or note.get("wardrobe_read")
            or director.get("wardrobe_motion")
            or note.get("wardrobe_motion")
        ),
        "cue": clean_text(
            micro_cut.get("lyric_original_text")
            or director.get("lyric_original_text")
            or note.get("lyric_original_text")
            or director.get("primary_audio_section_cue")
            or director.get("onset_hit")
        ),
        "background": clean_text(
            micro_cut.get("object_or_background_response")
            or director.get("background_or_object_reaction")
        ),
        "must_show": clean_text(framing.get("must_show") or micro_cut.get("must_show")),
        "shot_scale": shot_scale_prompt,
        "avoid": clean_text((note.get("avoid") or []) + (framing.get("must_not_collapse_to") or [])),
        "visible_moment": clean_text(micro_cut.get("visible_body_action", "")),
        "prompt_focus": clean_text(note.get("final_prompt_intent", "")),
        "source_camera": clean_text(camera),
    }


def start_pose_text(action: str) -> str:
    action = action.rstrip(".; ")
    return (
        "freeze the readable beginning before the action completes: "
        f"{action}. Keep the first weight shift, first hand/eye/foot contact, "
        "and the still-unresolved garment or body line visible."
    )


def end_pose_text(action: str) -> str:
    action = action.rstrip(".; ")
    return (
        "show the completed endpoint after the action resolves: "
        f"{action}. The final hand, gaze, foot, shoulder, garment, or formation "
        "state must be visibly different from the start while staying in the same beat and space."
    )


def motion_delta_text(action: str) -> str:
    action = action.rstrip(".; ")
    return (
        "the two frames must imply a specific motion gap, not two alternate stills: "
        f"{action}. Separate the first readable trigger from the completed endpoint "
        "through body level, hand path, foot/floor contact, gaze, fabric stop, or camera distance."
    )


def two_cut_framing_guard(member_count: int) -> str:
    if member_count <= 1:
        return (
            "Solo framing guard: preserve the packet's 02A/02B camera and shot-scale lock. "
            "Use medium, close-medium, or three-quarter framing only when no wider body route, floor line, or formation evidence is explicitly locked. "
            "If feet or floor line must be visible, keep natural head-to-body scale and never use below-footline distortion."
        )
    return (
        "Two-cut routing guard: this sheet mode is intended for one declared member. "
        "If more members are needed, route the beat to the single-frame 16:9 multi-member manifest."
    )


def prompt_for_two_cut_packet(packet: dict[str, Any], timeline: str, title_name: str) -> str:
    packet_id = str(packet["packet_id"])
    beat_id = str(packet["beat_id"])
    parts = prompt_parts(packet)
    codes = list(parts["codes"])
    names = list(parts["names"])
    who = str(parts["who"])
    action = str(parts["action"]).rstrip(".; ")
    start_pose = start_pose_text(action)
    motion_delta = motion_delta_text(action)
    end_pose = end_pose_text(action)
    framing_guard = two_cut_framing_guard(len(codes))

    return f"""# {packet_id}_TWO_CUT_SOURCE

Beat: {beat_id}
Timeline: {timeline}

## Visible Image Prompt

Create one clean two-frame beat source sheet for {title_name}, a cinematic K-pop MV. Canvas is exactly 1280x1440. Split the canvas into exactly two stacked horizontal 16:9 frames: CUT01_START occupies x=0 y=0 w=1280 h=720, and CUT02_END occupies x=0 y=720 w=1280 h=720. The visible output must contain only these two MV still frames. Do not render any text, numbers, frame labels, captions, UI, logos, contact-sheet design, reference panels, swatches, or readable signage text. A thin plain divider is acceptable only if each half stays clean enough to crop into a standalone 1280x720 image.

Use the attached face-only reference image for facial identity: {", ".join(names) if names else "declared member identity"}. Keep the same visible member identity, wardrobe lane, packet-locked lighting, body proportions, hair, makeup, and scene continuity across both frames. Do not take pose, outfit, lighting, crop, or background from face-only identity references unless the packet explicitly marks those images as direct visual references.

Scene continuity: {who} in {parts["space"]}, under the packet's locked scene lighting. Background/object behavior: {parts["background"]}.

Wardrobe lock: {parts["wardrobe"]}. Preserve the packet-locked wardrobe, styling, material, and silhouette literally. Do not replace it with unrelated office suiting, business shirts, runway fashion, glamour styling, tourist styling, armor, or any outfit lane absent from the packet.

Camera and framing: source shot scale is {parts["shot_scale"]}. Source camera intent: {parts["camera"]}. {framing_guard} Use a different but continuous camera feeling between the two halves only when compatible with the packet camera: the start frame may hold slightly wider or more side/three-quarter; the end frame may push in, dolly back, reduce toward the center, or hold the final stop, but it must stay in the same space and beat.

CUT01_START top frame: {who} must {start_pose} Keep the expression, gaze, hands, feet, wardrobe edge, and floor line readable without making the pose look airborne, falling, crouched, kneeling, or lunging unless the beat explicitly asks.

CUT02_END bottom frame: {who} must {end_pose} Preserve the same identity, wardrobe, lighting, and space. The end frame should be clear enough to become the final source image for a short video clip.

Motion delta: {motion_delta}

Audio/lyric cue: {parts["cue"]}

Must show: {parts["must_show"]}

Clean render guard: 4K, high quality, high detail, premium idol MV still, polished details, clean anatomy, natural idol proportions, connected neck and shoulders, readable hands/fingers/feet, grounded contact when feet are visible, coherent scene face lighting, stable floor and surface reflections. Avoid: {parts["avoid"]}; no airborne body, no falling pose, no drop-down action, no malformed fingers, no warped feet, no twisted limbs, no pasted face, no distorted proportions, no readable text.
"""


def single_identity_instruction(parts: dict[str, str | list[str]], internal_identity: bool) -> str:
    names = list(parts["names"])
    if internal_identity:
        return (
            "No face reference images are attached for this five-or-more member group/formation beat. "
            f"Use the model's internal IDOL identity synthesis from the visible member list: {', '.join(names) if names else 'the declared visible members'}. "
            "Keep every visible member distinct, preserve the packet-locked roles, wardrobe lanes, body proportions, spacing, and center/edge placement, "
            "and prioritize clean group readability over exact individual face matching."
        )
    return (
        f"Use the attached face-only reference images only for facial identity: {', '.join(names) if names else 'declared member identities'}. "
        "Keep the visible member identities, wardrobe lane, packet-locked lighting, body proportions, hair, makeup, and scene continuity. "
        "Do not take pose, outfit, lighting, crop, or background from face-only identity references unless the packet explicitly marks those images as direct visual references."
    )


def prompt_for_single_packet(
    packet: dict[str, Any],
    timeline: str,
    title_name: str,
    internal_identity: bool = False,
) -> str:
    packet_id = str(packet["packet_id"])
    beat_id = str(packet["beat_id"])
    parts = prompt_parts(packet)
    who = str(parts["who"])
    action = str(parts["action"]).rstrip(".; ")

    return f"""# {packet_id}_SINGLE_CUT_SOURCE

Beat: {beat_id}
Timeline: {timeline}

## Visible Image Prompt

Create one clean single-frame 16:9 beat source image for {title_name}, a cinematic K-pop MV. Canvas is exactly 1280x720. The visible output must contain only one MV still frame. Do not render any text, numbers, frame labels, captions, UI, logos, contact-sheet design, reference panels, swatches, or readable signage text.

{single_identity_instruction(parts, internal_identity)}

Scene continuity: {who} in {parts["space"]}, under the packet's locked scene lighting. Background/object behavior: {parts["background"]}.

Wardrobe lock: {parts["wardrobe"]}. Preserve the packet-locked wardrobe, styling, material, and silhouette literally. Do not replace it with unrelated office suiting, business shirts, runway fashion, glamour styling, tourist styling, armor, or any outfit lane absent from the packet.

Camera and framing: source shot scale is {parts["shot_scale"]}. Source camera intent: {parts["camera"]}. Multi-member source rule: keep the camera only as wide as needed to read spacing, foot route, floor marks, synchronized body levels, and center energy. Use a clean medium-wide, wide, side-track, three-quarter, or controlled front angle only when it follows the packet camera, and do not split the image into start/end panels.

Single frame moment: show the beat's most readable completed action mark as one still image. Visible members: {who}. Visible action: {action}. Keep face direction, gaze, hands, feet, wardrobe edge, spacing, and floor line readable without making the pose look airborne, falling, crouched, kneeling, or lunging unless the beat explicitly asks.

Audio/lyric cue: {parts["cue"]}

Must show: {parts["must_show"]}

Clean render guard: 4K, high quality, high detail, premium idol MV still, polished details, clean anatomy, natural idol proportions, connected neck and shoulders, readable hands/fingers/feet, grounded contact when feet are visible, coherent scene face lighting, stable floor and surface reflections. Avoid: {parts["avoid"]}; no airborne body, no falling pose, no drop-down action, no malformed fingers, no warped feet, no twisted limbs, no pasted face, no distorted proportions, no readable text.
"""


def keyframe_id_for_packet(packet_id: str, route: str, keyframe_prefix: str) -> str:
    if packet_id.startswith("PKT_"):
        packet_id = packet_id[len("PKT_") :]
    suffix = "TWO_CUT_SOURCE" if route == "two_cut" else "SINGLE_CUT_SOURCE"
    prefix = slug_upper(keyframe_prefix or "IDOL")
    return f"{prefix}_{packet_id}_{suffix}"


def keyframe_record(
    packet: dict[str, Any],
    index: int,
    timeline: str,
    route: str,
    keyframe_prefix: str,
    internal_identity: bool = False,
) -> dict[str, Any]:
    packet_id = str(packet["packet_id"])
    beat_id = str(packet["beat_id"])
    parts = prompt_parts(packet)
    codes = list(parts["codes"])
    keyframe_id = keyframe_id_for_packet(packet_id, route, keyframe_prefix)
    output_name = f"{slug(packet_id)}-{'two-cut' if route == 'two_cut' else 'single-cut'}-source.png"
    output_subdir = "sheets" if route == "two_cut" else "images"
    section = "two_cut_solo_beat_source_v1" if route == "two_cut" else "single_cut_multi_beat_source_v1"
    return {
        "id": keyframe_id,
        "packet_id": packet_id,
        "beat_id": beat_id,
        "section": section,
        "timeline": timeline,
        "source_group": beat_id,
        "keyframe_index": index,
        "keyframe_count": 1,
        "subject": codes,
        "identity_source_mode": "model_internal_identity" if internal_identity else "face_only_reference_inputs",
        "api_face_refs": [] if internal_identity else codes[:2],
        "api_face_ref_policy": "none_for_five_or_more_member_internal_group" if internal_identity else "max_two_face_only_references",
        "output_image": f"{output_subdir}/{output_name}",
        "source_prompt_packet_path": f"{packet.get('_packet_path', '')}#{packet_id}",
        "source_02b_prompt_export_path": (packet.get("export_contract") or {}).get("prompt_export_path", ""),
        "source_02b_manifest_path": (packet.get("export_contract") or {}).get("manifest_path", ""),
        "camera": parts["source_camera"],
        "prompt_focus": parts["prompt_focus"],
        "visible_moment": parts["visible_moment"],
        "start_pose_lock": start_pose_text(str(parts["visible_moment"] or parts["action"])),
        "motion_delta": motion_delta_text(str(parts["visible_moment"] or parts["action"])),
        "end_pose_lock": end_pose_text(str(parts["visible_moment"] or parts["action"])),
        "camera_delta": "Start and end frames must preserve the packet camera intent while making the camera distance, angle pressure, or final hold visibly purposeful.",
    }


def write_prompt(path: Path, prompt: str, args: argparse.Namespace) -> None:
    if not args.write:
        return
    prompt = re.sub(r"\.{2,}", ".", prompt)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not args.force:
        raise FileExistsError(f"prompt exists: {path}")
    path.write_text(prompt, encoding="utf-8")


def build_two_cut_manifest(
    args: argparse.Namespace,
    packet_path: Path,
    packet_data: dict[str, Any],
    packets: list[dict[str, Any]],
    registry: dict[str, str],
    timelines: dict[str, str],
    title_name: str,
) -> tuple[Path, dict[str, Any]]:
    output_root = Path(args.output_root)
    prompt_dir = output_root / "prompts"
    keyframes: list[dict[str, Any]] = []
    for index, packet in enumerate(packets, start=1):
        packet["_packet_path"] = str(packet_path)
        packet_id = str(packet["packet_id"])
        keyframe_id = keyframe_id_for_packet(packet_id, "two_cut", args.keyframe_prefix)
        prompt_path = prompt_dir / f"{keyframe_id.lower()}.md"
        timeline = timelines.get(packet_id, "")
        write_prompt(prompt_path, prompt_for_two_cut_packet(packet, timeline, title_name), args)
        keyframes.append(keyframe_record(packet, index, timeline, "two_cut", args.keyframe_prefix))

    crop_subdir = f"{slug_upper(str(args.keyframe_prefix))}_TWO_CUT_SOLO_BEAT_SOURCE_V1"

    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "content_id": args.content_id,
        "date_kst": datetime.now().strftime("%Y-%m-%d"),
        "status": "ready_for_generation" if keyframes else "draft",
        "scope": [args.scope or f"{title_name} solo two-cut beat source production"],
        "routing_rule": "only beats with one declared member are routed here; multi-member or formation beats use the single-cut manifest",
        "source_plans": {
            "source_02b_prompt_packets": str(packet_path),
            "source_video_prompts": str(resolve(args.video_index)) if args.video_index else "",
        },
        "output_root": str(output_root),
        "prompt_dir": str(prompt_dir),
        "image_dir": str(output_root / "sheets"),
        "contact_sheet_dir": str(output_root / "contact-sheets"),
        "generation_contract": {
            "visible_output": "one two-frame solo beat source sheet per selected beat",
            "prompt_header_mode": "two_frame_sheet",
            "identity_source_mode": "face_only_reference_inputs",
            "api_endpoint": "/v1/images/edits",
            "model": args.model,
            "quality": args.quality,
            "size": f"{TWO_CUT_CANVAS_WIDTH}x{TWO_CUT_CANVAS_HEIGHT}",
            "aspect_ratio": "8:9_two_cut_sheet",
            "frame_layout": "top frame is the beat start pose; bottom frame is the beat end pose",
            "fixed_canvas": {"width": TWO_CUT_CANVAS_WIDTH, "height": TWO_CUT_CANVAS_HEIGHT},
            "cut_regions": {
                "CUT01_START": {
                    "x": 0,
                    "y": 0,
                    "width": TWO_CUT_CANVAS_WIDTH,
                    "height": TWO_CUT_FRAME_HEIGHT,
                    "aspect_ratio": "16:9",
                    "crop_output": f"crops/{crop_subdir}/{{keyframe_id}}_cut01_start.png",
                },
                "CUT02_END": {
                    "x": 0,
                    "y": TWO_CUT_FRAME_HEIGHT,
                    "width": TWO_CUT_CANVAS_WIDTH,
                    "height": TWO_CUT_FRAME_HEIGHT,
                    "aspect_ratio": "16:9",
                    "crop_output": f"crops/{crop_subdir}/{{keyframe_id}}_cut02_end.png",
                },
            },
            "visible_board_rule": "no visible text, no frame labels, no numbers, no captions, no UI, no logos, no reference panels",
            "crop_rule": "crop the generated sheet exactly by fixed cut_regions; do not infer crop boxes from model content",
            "api_reference_rule": "attach one tight-cropped face-only member reference internally as API image input; use identity only",
            "forbidden_reference_inputs": ["wardrobe_reference", "background_reference", "character_board_as_api_input"],
            "selected_generation_count": len(keyframes),
            "review_rule": "assemble generated separate two-frame sheets into contact sheets only after generation",
            "motion_guard": "no airborne body, no fall, no drop-down motion, no acrobatic hop",
            "camera_guard": "preserve the packet camera/framing lock; medium, close-medium, or three-quarter is only a fallback when no wider body route, floor line, or formation evidence is locked",
            "wardrobe_guard": "preserve packet wardrobe literally; block unrelated office suiting, runway fashion, glamour styling, tourist styling, armor, or outfit lanes absent from the packet",
        },
        "member_face_refs": registry_for_packets(packets, registry),
        "keyframes": keyframes,
    }
    return resolve(args.manifest_out), manifest


def build_single_manifest(
    args: argparse.Namespace,
    packet_path: Path,
    packet_data: dict[str, Any],
    packets: list[dict[str, Any]],
    registry: dict[str, str],
    timelines: dict[str, str],
    title_name: str,
) -> tuple[Path, dict[str, Any]]:
    output_root = Path(args.single_output_root)
    prompt_dir = output_root / "prompts"
    keyframes: list[dict[str, Any]] = []
    for index, packet in enumerate(packets, start=1):
        packet["_packet_path"] = str(packet_path)
        packet_id = str(packet["packet_id"])
        keyframe_id = keyframe_id_for_packet(packet_id, "single_cut", args.keyframe_prefix)
        prompt_path = prompt_dir / f"{keyframe_id.lower()}.md"
        timeline = timelines.get(packet_id, "")
        write_prompt(prompt_path, prompt_for_single_packet(packet, timeline, title_name), args)
        keyframes.append(keyframe_record(packet, index, timeline, "single_cut", args.keyframe_prefix))

    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "content_id": args.content_id,
        "date_kst": datetime.now().strftime("%Y-%m-%d"),
        "status": "ready_for_generation" if keyframes else "draft",
        "scope": [args.single_scope or f"{title_name} multi-member single-cut beat source production"],
        "routing_rule": "beats with two or more declared members are routed here as one clean 16:9 source image per beat",
        "source_plans": {
            "source_02b_prompt_packets": str(packet_path),
            "source_video_prompts": str(resolve(args.video_index)) if args.video_index else "",
        },
        "output_root": str(output_root),
        "prompt_dir": str(prompt_dir),
        "image_dir": str(output_root / "images"),
        "contact_sheet_dir": str(output_root / "contact-sheets"),
        "generation_contract": {
            "visible_output": "one single-frame 16:9 multi-member beat source image per selected beat",
            "prompt_header_mode": "single_frame_16x9",
            "identity_source_mode": "face_only_reference_inputs",
            "api_endpoint": "/v1/images/edits",
            "model": args.model,
            "quality": args.quality,
            "size": f"{SINGLE_FRAME_WIDTH}x{SINGLE_FRAME_HEIGHT}",
            "aspect_ratio": "16:9",
            "frame_layout": "one clean MV still per beat; no start/end split",
            "fixed_canvas": {"width": SINGLE_FRAME_WIDTH, "height": SINGLE_FRAME_HEIGHT},
            "visible_board_rule": "no visible text, no frame labels, no numbers, no captions, no UI, no logos, no reference panels",
            "api_reference_rule": "attach at most two declared face-only member references internally as API image inputs; use identity only; subject may list every visible member",
            "forbidden_reference_inputs": ["wardrobe_reference", "background_reference", "character_board_as_api_input"],
            "selected_generation_count": len(keyframes),
            "review_rule": "assemble generated separate single images into contact sheets only after generation",
            "motion_guard": "no airborne body, no fall, no drop-down motion, no acrobatic hop",
            "camera_guard": "preserve the packet camera/framing lock; widen only as needed for spacing, foot route, floor marks, synchronized body levels, and center energy",
            "wardrobe_guard": "preserve packet wardrobe literally; block unrelated office suiting, runway fashion, glamour styling, tourist styling, armor, or outfit lanes absent from the packet",
        },
        "member_face_refs": registry_for_packets(packets, registry),
        "keyframes": keyframes,
    }
    return resolve(args.single_manifest_out), manifest


def build_group_internal_manifest(
    args: argparse.Namespace,
    packet_path: Path,
    packet_data: dict[str, Any],
    packets: list[dict[str, Any]],
    registry: dict[str, str],
    timelines: dict[str, str],
    title_name: str,
) -> tuple[Path, dict[str, Any]]:
    output_root = Path(args.group_internal_output_root)
    prompt_dir = output_root / "prompts"
    keyframes: list[dict[str, Any]] = []
    for index, packet in enumerate(packets, start=1):
        packet["_packet_path"] = str(packet_path)
        packet_id = str(packet["packet_id"])
        keyframe_id = keyframe_id_for_packet(packet_id, "single_cut", args.keyframe_prefix)
        prompt_path = prompt_dir / f"{keyframe_id.lower()}.md"
        timeline = timelines.get(packet_id, "")
        write_prompt(prompt_path, prompt_for_single_packet(packet, timeline, title_name, internal_identity=True), args)
        keyframes.append(
            keyframe_record(
                packet,
                index,
                timeline,
                "single_cut",
                args.keyframe_prefix,
                internal_identity=True,
            )
        )

    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "content_id": args.content_id,
        "date_kst": datetime.now().strftime("%Y-%m-%d"),
        "status": "ready_for_generation" if keyframes else "draft",
        "scope": [args.group_internal_scope or f"{title_name} five-or-more member internal-identity beat source production"],
        "routing_rule": "beats with five or more declared members use model-internal identity; no API face references are attached",
        "source_plans": {
            "source_02b_prompt_packets": str(packet_path),
            "source_video_prompts": str(resolve(args.video_index)) if args.video_index else "",
        },
        "output_root": str(output_root),
        "prompt_dir": str(prompt_dir),
        "image_dir": str(output_root / "images"),
        "contact_sheet_dir": str(output_root / "contact-sheets"),
        "generation_contract": {
            "visible_output": "one single-frame 16:9 five-or-more member group/formation beat source image per selected beat",
            "prompt_header_mode": "single_frame_16x9_internal_group",
            "identity_source_mode": "model_internal_identity",
            "api_endpoint": "/v1/images/generations",
            "model": args.model,
            "quality": args.quality,
            "size": f"{SINGLE_FRAME_WIDTH}x{SINGLE_FRAME_HEIGHT}",
            "aspect_ratio": "16:9",
            "frame_layout": "one clean MV still per beat; no start/end split",
            "fixed_canvas": {"width": SINGLE_FRAME_WIDTH, "height": SINGLE_FRAME_HEIGHT},
            "visible_board_rule": "no visible text, no frame labels, no numbers, no captions, no UI, no logos, no reference panels",
            "api_reference_rule": "attach no face-only references for five-or-more member group/formation beats; use model-internal identity from prompt text, member names, roles, wardrobe lanes, and blocking",
            "forbidden_reference_inputs": ["face_reference", "wardrobe_reference", "background_reference", "character_board_as_api_input"],
            "selected_generation_count": len(keyframes),
            "review_rule": "assemble generated separate internal-identity single images into contact sheets only after generation",
            "motion_guard": "no airborne body, no fall, no drop-down motion, no acrobatic hop",
            "camera_guard": "preserve the packet camera/framing lock; widen only as needed for group spacing, floor marks, synchronized body levels, and center energy",
            "wardrobe_guard": "preserve packet wardrobe literally; block unrelated office suiting, runway fashion, glamour styling, tourist styling, armor, or outfit lanes absent from the packet",
        },
        "member_face_refs": registry_for_packets(packets, registry),
        "keyframes": keyframes,
    }
    return resolve(args.group_internal_manifest_out), manifest


def write_manifest(path: Path, manifest: dict[str, Any], args: argparse.Namespace) -> None:
    if not args.write:
        return
    if path.exists() and not args.force:
        raise FileExistsError(f"manifest exists: {path}")
    write_yaml(path, manifest)


def build(args: argparse.Namespace) -> dict[str, Any]:
    if args.quality != "high":
        raise ValueError("post-02B image generation requires --quality high; lower quality is forbidden")
    packet_path = resolve(args.packet_path)
    packet_data = load_yaml(packet_path)
    packets = packet_by_id(packet_data)
    title_name = title_display(packet_data, args.title_display_name)
    apply_derived_defaults(args, packet_path, packet_data, title_name)
    if args.internal_model_min_subjects <= args.two_cut_max_subjects:
        raise ValueError("--internal-model-min-subjects must be greater than --two-cut-max-subjects")
    timelines = load_video_timelines(resolve(args.video_index)) if args.video_index else {}
    registry = face_ref_registry(packets)

    two_cut_packets: list[dict[str, Any]] = []
    single_packets: list[dict[str, Any]] = []
    group_internal_packets: list[dict[str, Any]] = []
    for packet in packets:
        codes = subject_codes(packet)
        if len(codes) <= args.two_cut_max_subjects:
            two_cut_packets.append(packet)
        elif len(codes) >= args.internal_model_min_subjects:
            group_internal_packets.append(packet)
        else:
            single_packets.append(packet)

    manifests: list[tuple[str, Path, dict[str, Any]]] = []
    if not args.skip_two_cut:
        manifests.append(
            (
                "two_cut",
                *build_two_cut_manifest(args, packet_path, packet_data, two_cut_packets, registry, timelines, title_name),
            )
        )
    if not args.skip_single_cut:
        manifests.append(
            (
                "single_cut",
                *build_single_manifest(args, packet_path, packet_data, single_packets, registry, timelines, title_name),
            )
        )
    if not args.skip_group_internal:
        manifests.append(
            (
                "group_internal",
                *build_group_internal_manifest(
                    args,
                    packet_path,
                    packet_data,
                    group_internal_packets,
                    registry,
                    timelines,
                    title_name,
                ),
            )
        )

    results: dict[str, Any] = {}
    for route, manifest_path, manifest in manifests:
        write_manifest(manifest_path, manifest, args)
        output_root = resolve(str(manifest["output_root"]))
        prompt_dir = resolve(str(manifest["prompt_dir"]))
        results[route] = {
            "manifest": str(manifest_path),
            "write": bool(args.write),
            "prompt_dir": str(prompt_dir),
            "output_root": str(output_root),
            "keyframe_count": len(manifest["keyframes"]),
            "member_face_ref_count": len(manifest["member_face_refs"]),
            "api_face_ref_count_total": sum(len(row.get("api_face_refs") or []) for row in manifest["keyframes"]),
            "identity_source_mode": (manifest.get("generation_contract") or {}).get("identity_source_mode", ""),
            "api_endpoint": (manifest.get("generation_contract") or {}).get("api_endpoint", ""),
            "manifest_sha256": sha256_file(manifest_path) if args.write else "",
        }

    return {
        "packet_count": len(packets),
        "two_cut_packet_count": len(two_cut_packets),
        "single_cut_packet_count": len(single_packets),
        "group_internal_packet_count": len(group_internal_packets),
        "two_cut_max_subjects": args.two_cut_max_subjects,
        "internal_model_min_subjects": args.internal_model_min_subjects,
        "routes": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet-path", required=True)
    parser.add_argument("--video-index", default="")
    parser.add_argument("--manifest-out", default="")
    parser.add_argument("--output-root", default="")
    parser.add_argument("--single-manifest-out", default="")
    parser.add_argument("--single-output-root", default="")
    parser.add_argument("--group-internal-manifest-out", default="")
    parser.add_argument("--group-internal-output-root", default="")
    parser.add_argument("--content-id", default="")
    parser.add_argument("--title-key", default="")
    parser.add_argument("--keyframe-prefix", default="")
    parser.add_argument("--title-display-name", default="")
    parser.add_argument("--scope", default="")
    parser.add_argument("--single-scope", default="")
    parser.add_argument("--group-internal-scope", default="")
    parser.add_argument("--model", default="gpt-image-2")
    parser.add_argument("--quality", default="high")
    parser.add_argument("--two-cut-max-subjects", type=int, default=1)
    parser.add_argument("--internal-model-min-subjects", type=int, default=INTERNAL_MODEL_MIN_SUBJECTS)
    parser.add_argument("--skip-two-cut", action="store_true")
    parser.add_argument("--skip-single-cut", action="store_true")
    parser.add_argument("--skip-group-internal", action="store_true")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    print(
        json_dump(
            {
                "ok": False,
                "error": (
                    "legacy single/two-cut beat-source manifest authoring is retired; "
                    "use one active idol_image_generation_request.v8 per Branch Cut"
                ),
            }
        ),
        end="",
    )
    return 1
    args.model = require_openai_image_model(args.model, context="two-cut source manifest --model")
    try:
        result = build(args)
    except Exception as error:  # noqa: BLE001
        print(json_dump({"ok": False, "error": str(error)}), end="")
        return 1
    print(json_dump({"ok": True, "result": result}), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
