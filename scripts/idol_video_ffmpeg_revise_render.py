#!/usr/bin/env python3
"""Render an IDOL section-revise recipe with ffmpeg only.

The recipe is the edit source of truth. This renderer can make low-res proxy
previews from the same recipe, then render the locked pass at full quality.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Any

try:
    import jsonschema
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit(
        f"Missing Python dependency '{exc.name}'. "
        "Run this script through scripts/idol-video-python."
    ) from exc

from lib.idol_edit_effect_registry import (
    EffectContractError,
    load_effect_registry,
    load_unique_yaml,
)

LEGACY_FPS = Fraction(24, 1)
ROOT = Path(__file__).resolve().parent.parent
EFFECT_REGISTRY = load_effect_registry()


@dataclass(frozen=True)
class Segment:
    slot: str
    source: str
    source_in: float
    source_out: float
    output_in: float
    output_out: float
    output_duration: float
    grade: str = ""
    note: str = ""

    @property
    def source_duration(self) -> float:
        return self.source_out - self.source_in

    @property
    def speed_factor(self) -> float:
        return self.source_duration / self.output_duration


@dataclass(frozen=True)
class RenderSpec:
    fps: Fraction
    width: int
    height: int
    fit_mode: str
    background: str
    pixel_format: str

    @property
    def fps_text(self) -> str:
        return f"{self.fps.numerator}/{self.fps.denominator}"

    @property
    def fps_float(self) -> float:
        return float(self.fps)


@dataclass(frozen=True)
class EncodingSpec:
    container: str
    video_codec: str
    audio_codec: str
    video_args: tuple[str, ...]
    audio_args: tuple[str, ...]
    movflags: tuple[str, ...] = ()


def encoding_spec(
    payload: dict[str, Any],
    profile: str,
    output_path: Path,
    *,
    preset: str,
    crf: str,
    audio_bitrate: str,
) -> EncodingSpec:
    if profile != "final":
        return EncodingSpec(
            container=output_path.suffix.lower().lstrip(".") or "mp4",
            video_codec="libx264",
            audio_codec="aac",
            video_args=("-c:v", "libx264", "-preset", preset, "-crf", crf),
            audio_args=("-c:a", "aac", "-b:a", audio_bitrate),
            movflags=("-movflags", "+faststart"),
        )

    mezzanine = ((payload.get("delivery_policy") or {}).get("mezzanine") or {})
    container = str(mezzanine.get("container") or "").lower()
    requested_video = str(mezzanine.get("video_codec") or "").lower()
    requested_audio = str(mezzanine.get("audio_codec") or "").lower()
    if output_path.suffix.lower() != f".{container}":
        raise SystemExit(
            f"final output extension {output_path.suffix!r} must match "
            f"delivery_policy.mezzanine.container={container!r}"
        )

    if requested_video in {"libx264", "h264"}:
        video_codec = "libx264"
        video_args = ["-c:v", video_codec, "-preset", preset, "-crf", crf]
        requested_profile = mezzanine.get("video_profile")
        if requested_profile not in (None, ""):
            video_args += ["-profile:v", str(requested_profile)]
    elif requested_video in {"prores", "prores_ks"}:
        video_codec = "prores_ks"
        profile_value = mezzanine.get("video_profile", 3)
        profile_aliases = {
            "proxy": 0,
            "lt": 1,
            "standard": 2,
            "hq": 3,
            "4444": 4,
            "4444xq": 5,
        }
        profile_number = profile_aliases.get(
            str(profile_value).lower(), profile_value
        )
        try:
            profile_number = int(profile_number)
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"unsupported ProRes video_profile {profile_value!r}") from exc
        if profile_number not in range(0, 6):
            raise SystemExit("ProRes video_profile must resolve to 0..5")
        video_args = ["-c:v", video_codec, "-profile:v", str(profile_number)]
    else:
        raise SystemExit(f"unsupported final video codec: {requested_video!r}")

    if requested_audio == "aac":
        audio_codec = "aac"
        audio_args = ["-c:a", audio_codec, "-b:a", audio_bitrate]
    elif requested_audio in {"pcm_s16le", "pcm_s24le"}:
        audio_codec = requested_audio
        audio_args = ["-c:a", audio_codec]
    else:
        raise SystemExit(f"unsupported final audio codec: {requested_audio!r}")

    movflags = ("-movflags", "+faststart") if container in {"mp4", "mov"} else ()
    return EncodingSpec(
        container=container,
        video_codec=video_codec,
        audio_codec=audio_codec,
        video_args=tuple(video_args),
        audio_args=tuple(audio_args),
        movflags=movflags,
    )


def delivery_color_args(
    payload: dict[str, Any], video_codec: str | None = None
) -> tuple[str, ...]:
    delivery = ((payload.get("color_pipeline") or {}).get("delivery") or {})
    if not delivery:
        return ()
    mappings = (
        ("color_range", "-color_range"),
        ("color_space", "-colorspace"),
        ("color_transfer", "-color_trc"),
        ("color_primaries", "-color_primaries"),
    )
    aliases = {"limited": "tv", "full": "pc"}
    result: list[str] = []
    normalized: dict[str, str] = {}
    for key, option in mappings:
        value = str(delivery.get(key) or "").strip().lower()
        if not value or value == "unknown":
            continue
        value = aliases.get(value, value)
        if not all(character.isalnum() or character in "_-" for character in value):
            raise SystemExit(f"unsafe color metadata value for {key}: {value!r}")
        normalized[key] = value
        result.extend((option, value))
    # FFmpeg's generic color options set the MP4 matrix/range tags for
    # libx264, but this local build does not write transfer/primaries into the
    # H.264 VUI unless the encoder receives the equivalent x264 parameters.
    # Keep both surfaces aligned so ffprobe can verify the immutable render
    # receipt against the recipe delivery contract.
    if video_codec == "libx264":
        x264_parameters: list[str] = []
        if normalized.get("color_primaries"):
            x264_parameters.append(f"colorprim={normalized['color_primaries']}")
        if normalized.get("color_transfer"):
            x264_parameters.append(f"transfer={normalized['color_transfer']}")
        if normalized.get("color_space"):
            x264_parameters.append(f"colormatrix={normalized['color_space']}")
        if normalized.get("color_range") in {"tv", "pc"}:
            x264_parameters.append(
                "fullrange=on" if normalized["color_range"] == "pc" else "fullrange=off"
            )
        if x264_parameters:
            result.extend(("-x264-params", ":".join(x264_parameters)))
    return tuple(result)


def parse_render_spec(payload: dict[str, Any]) -> RenderSpec:
    spec = payload.get("render_spec") or {}
    fps_value = spec.get("fps", payload.get("fps", 24))
    if isinstance(fps_value, dict):
        numerator = int(fps_value.get("numerator", 0))
        denominator = int(fps_value.get("denominator", 0))
        if numerator <= 0 or denominator <= 0:
            raise SystemExit("render_spec.fps numerator/denominator must be positive")
        fps = Fraction(numerator, denominator)
    elif isinstance(fps_value, str):
        fps = Fraction(fps_value)
    else:
        fps = Fraction(str(fps_value))
    if fps <= 0:
        raise SystemExit("render_spec.fps must be positive")

    width = int(spec.get("width", 1920))
    height = int(spec.get("height", 1080))
    if width <= 0 or height <= 0 or width % 2 or height % 2:
        raise SystemExit("render_spec width/height must be positive even integers")
    fit_mode = str(spec.get("fit_mode", spec.get("geometry_policy", "fit_pad")))
    if fit_mode not in {"fit_pad", "fill_crop", "stretch"}:
        raise SystemExit("render_spec.fit_mode must be fit_pad, fill_crop, or stretch")
    return RenderSpec(
        fps=fps,
        width=width,
        height=height,
        fit_mode=fit_mode,
        background=str(spec.get("background", "black")),
        pixel_format=str(spec.get("pixel_format", "yuv420p")),
    )


def tool_path(name: str) -> str:
    for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]:
        preferred = Path(prefix) / name
        if preferred.exists():
            return str(preferred)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(
        f"Missing required tool: {name}. "
        "Run through scripts/idol-video-python or install ffmpeg in Homebrew."
    )


def ffprobe_media(path: Path) -> dict[str, Any]:
    ffprobe = tool_path("ffprobe")
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames,sample_rate,channel_layout,pix_fmt,color_range,color_space,color_transfer,color_primaries",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def media_duration(path: Path) -> float:
    payload = ffprobe_media(path)
    try:
        return float(payload["format"]["duration"])
    except (KeyError, TypeError, ValueError) as exc:
        raise SystemExit(f"ffprobe did not return duration for {path}") from exc


def validate_source_bounds(segments: list[Segment], run_root: Path, fps: Fraction) -> None:
    durations: dict[Path, float] = {}
    tolerance = 0.5 / float(fps)
    for segment in segments:
        path = rel_or_abs(run_root, segment.source).resolve()
        if not path.is_file():
            raise SystemExit(f"recipe source is not readable: {path}")
        if path not in durations:
            durations[path] = media_duration(path)
        duration = durations[path]
        if segment.source_in < -tolerance or segment.source_out > duration + tolerance:
            raise SystemExit(
                f"source handle/trim exceeds {segment.slot} bounds: "
                f"{segment.source_in:.6f}-{segment.source_out:.6f}s vs {duration:.6f}s"
            )


def rel_or_abs(run_root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return run_root / path


def load_segments(recipe_path: Path) -> tuple[dict, list[Segment]]:
    payload = load_unique_yaml(recipe_path) or {}
    rows = payload.get("timeline") or []
    is_active_recipe = payload.get("schema_version") == "idol_edit_recipe.v3"
    spec = parse_render_spec(payload) if is_active_recipe else None
    segments = [
        Segment(
            slot=str(row["slot"]),
            source=str(row["source"]),
            source_in=float(row["source_in"]),
            source_out=float(row["source_out"]),
            output_in=(
                float(Fraction(int(row["output_in_frame"]), 1) / spec.fps)
                if is_active_recipe and spec
                else float(row["output_in"])
            ),
            output_out=(
                float(Fraction(int(row["output_out_frame"]), 1) / spec.fps)
                if is_active_recipe and spec
                else float(row["output_out"])
            ),
            output_duration=(
                float(Fraction(int(row["duration_frames"]), 1) / spec.fps)
                if is_active_recipe and spec
                else float(row["output_duration"])
            ),
            grade=str(row.get("grade", "")),
            note=str(row.get("note", "")),
        )
        for row in rows
    ]
    if not segments:
        raise SystemExit(f"No timeline segments in {recipe_path}")
    return payload, segments


def slice_segments(segments: list[Segment], start: float, end: float) -> list[Segment]:
    sliced: list[Segment] = []
    for seg in segments:
        overlap_start = max(start, seg.output_in)
        overlap_end = min(end, seg.output_out)
        if overlap_end <= overlap_start:
            continue
        rel_start = overlap_start - seg.output_in
        rel_end = overlap_end - seg.output_in
        speed = seg.speed_factor
        sliced.append(
            Segment(
                slot=seg.slot,
                source=seg.source,
                source_in=seg.source_in + rel_start * speed,
                source_out=seg.source_in + rel_end * speed,
                output_in=overlap_start - start,
                output_out=overlap_end - start,
                output_duration=overlap_end - overlap_start,
                grade=seg.grade,
                note=seg.note,
            )
        )
    if not sliced:
        raise SystemExit(f"No recipe segments overlap {start:.3f}-{end:.3f}")
    return sliced


def scaled_geometry(spec: RenderSpec, max_edge: int) -> tuple[int, int]:
    scale = min(1.0, max_edge / max(spec.width, spec.height))
    width = max(2, int(round(spec.width * scale / 2.0)) * 2)
    height = max(2, int(round(spec.height * scale / 2.0)) * 2)
    return width, height


def profile_settings(
    profile: str, spec: RenderSpec
) -> tuple[int, int, str, str, str]:
    if profile == "proxy":
        width, height = scaled_geometry(spec, 960)
        return width, height, "veryfast", "24", "128k"
    if profile == "review":
        width, height = scaled_geometry(spec, 1280)
        return width, height, "fast", "21", "160k"
    if profile == "final":
        return spec.width, spec.height, "medium", "16", "192k"
    raise SystemExit(f"Unknown profile: {profile}")


def grade_filter(payload: dict, seg: Segment) -> str:
    if not seg.grade:
        return ""
    profiles = payload.get("grade_profiles") or {}
    value = profiles.get(seg.grade)
    if value is None:
        raise SystemExit(f"Missing grade profile '{seg.grade}' for segment {seg.slot}")
    if isinstance(value, dict):
        value = value.get("filter", "")
    value = str(value).strip()
    if not value:
        raise SystemExit(f"Empty grade profile '{seg.grade}' for segment {seg.slot}")
    return value


def slice_effects(
    effects: list[dict],
    start: float | None,
    end: float | None,
    fps: Fraction,
) -> list[dict]:
    if start is None:
        return [dict(effect) for effect in effects]
    if end is None or end <= start:
        raise SystemExit("--preview-end must be greater than --preview-start")

    sliced: list[dict] = []
    for effect in effects:
        if "start" not in effect and "start_frame" not in effect:
            continue
        effect_start = (
            float(Fraction(int(effect["start_frame"]), 1) / fps)
            if "start_frame" in effect
            else float(effect["start"])
        )
        duration = (
            float(Fraction(int(effect["duration_frames"]), 1) / fps)
            if "duration_frames" in effect
            else float(effect.get("duration", 0.16))
        )
        effect_end = effect_start + duration
        if effect_end <= start or effect_start >= end:
            continue
        copied = dict(effect)
        # Keep the full curve/window and move it into preview-local time. A
        # negative start means the preview begins mid-effect; restarting the
        # curve at frame zero would create false QC evidence.
        copied["start"] = effect_start - start
        copied["duration"] = duration
        copied["start_frame"] = round((effect_start - start) * float(fps))
        copied["duration_frames"] = max(1, round(duration * float(fps)))
        handles = copied.get("transition_handle_contract")
        if isinstance(handles, dict):
            handles = dict(handles)
            handles["fixed_program_cut_frame"] = int(
                handles["fixed_program_cut_frame"] - round(start * float(fps))
            )
            handles["fixed_program_cut_seconds"] = float(
                Fraction(handles["fixed_program_cut_frame"], 1) / fps
            )
            copied["transition_handle_contract"] = handles
        sliced.append(copied)
    return sliced


XFADE_TRANSITIONS = EFFECT_REGISTRY.transitions
STREAM_EFFECT_TYPES = {
    effect_type
    for effect_type, spec in EFFECT_REGISTRY.effects.items()
    if spec["timeline_class"] in {"single_stream", "metadata"}
}


def canonical_effect_type(effect_type: str) -> str:
    try:
        return EFFECT_REGISTRY.canonical_type(effect_type)
    except EffectContractError as exc:
        raise SystemExit(str(exc)) from exc


def color_expr(effect: dict, default: list[int], opacity: float) -> str:
    value = effect.get("color", default)
    if isinstance(value, str):
        return f"{value}@{opacity:.4f}" if "@" not in value else value
    if not isinstance(value, list | tuple) or len(value) != 3:
        raise SystemExit(f"Bad effect color: {value}")
    channels = [max(0, min(255, int(channel))) for channel in value]
    return f"0x{channels[0]:02x}{channels[1]:02x}{channels[2]:02x}@{opacity:.4f}"


def split_effects(effects: list[dict]) -> tuple[list[dict], list[dict]]:
    stream: list[dict] = []
    boundary: list[dict] = []
    for effect in effects:
        copied = dict(effect)
        effect_type = canonical_effect_type(str(copied.get("type", "")).strip())
        copied["type"] = effect_type
        if effect_type == "xfade":
            boundary.append(copied)
        else:
            stream.append(copied)
    return stream, boundary


def enable_between_frames(start_frame: int, end_frame: int) -> str:
    return f"enable='between(n,{start_frame},{end_frame - 1})'"


def effect_timing(effect: dict[str, Any], fps: Fraction) -> tuple[int, int, float, float]:
    if "start_frame" in effect:
        start_frame = int(effect["start_frame"])
    elif "start" in effect:
        start_frame = round(float(effect["start"]) * float(fps))
    else:
        raise SystemExit(f"effect {effect.get('fx_id') or effect.get('type')} has no start")
    if "duration_frames" in effect:
        duration_frames = int(effect["duration_frames"])
    else:
        duration_frames = max(1, round(float(effect.get("duration", 0.16)) * float(fps)))
    if start_frame < 0:
        # Negative starts are valid only for preview-local windows that begin
        # during an effect. Frame enabling clips naturally at zero.
        clipped_start = 0
    else:
        clipped_start = start_frame
    if duration_frames <= 0:
        raise SystemExit("effect duration_frames must be > 0")
    end_frame = start_frame + duration_frames
    start_seconds = float(Fraction(start_frame, 1) / fps)
    end_seconds = float(Fraction(end_frame, 1) / fps)
    return clipped_start, max(clipped_start + 1, end_frame), start_seconds, end_seconds


def envelope_expr(effect: dict[str, Any], start_frame: int, end_frame: int) -> str:
    duration_frames = max(1, end_frame - start_frame)
    curve = str(effect.get("curve", "attack_hold_release"))
    if curve == "instant":
        return f"between(n,{start_frame},{end_frame - 1})"
    attack = int(effect.get("attack_frames", min(1, duration_frames)))
    release = int(effect.get("release_frames", min(1, max(0, duration_frames - attack))))
    attack = max(0, min(duration_frames, attack))
    release = max(0, min(duration_frames - attack, release))
    hold_end = end_frame - release
    if attack:
        attack_expr = f"(n-{start_frame})/{attack}"
    else:
        attack_expr = "1"
    if release:
        release_expr = f"({end_frame}-n)/{release}"
    else:
        release_expr = "1"
    base = (
        f"if(lt(n,{start_frame}),0,"
        f"if(lt(n,{start_frame + attack}),{attack_expr},"
        f"if(lt(n,{hold_end}),1,"
        f"if(lt(n,{end_frame}),{release_expr},0))))"
    )
    if curve == "linear" or curve == "attack_hold_release":
        return base
    if curve == "ease_in_out":
        return f"(0.5-0.5*cos(PI*({base})))"
    raise SystemExit(f"unsupported effect curve: {curve}")


def effect_filter_chain(
    effects: list[dict],
    input_label: str,
    output_label: str,
    width: int,
    height: int,
    total_duration: float,
    fps: Fraction,
    pixel_format: str,
) -> list[str]:
    """Apply timeline-safe single-stream finishing effects after concat/join."""
    filters: list[str] = []
    current_label = input_label
    effect_idx = 0

    for effect in effects:
        effect_type = canonical_effect_type(str(effect.get("type", "")).strip())
        if not effect_type or effect_type == "hard_cut_note":
            continue
        if effect_type == "xfade":
            # Boundary xfade is applied during segment join, not here.
            continue
        if effect_type not in STREAM_EFFECT_TYPES:
            raise SystemExit(
                f"Unsupported effect type: {effect_type}. "
                "See skills/idol-edit-finishing-fx/references/"
                "local-ffmpeg-transition-effect-catalog.md"
            )
        known_names = set(EFFECT_REGISTRY.payload["common_parameters"]) | set(
            EFFECT_REGISTRY.payload["parameter_specs"]
        )
        parameters = {
            key: value
            for key, value in effect.items()
            if key in known_names
        }
        try:
            EFFECT_REGISTRY.validate_parameters(effect_type, parameters)
        except EffectContractError as exc:
            raise SystemExit(str(exc)) from exc

        start_frame, end_frame, start, end = effect_timing(effect, fps)
        total_frames = round(total_duration * float(fps))
        if start_frame >= total_frames or end_frame <= 0:
            continue
        end_frame = min(total_frames, end_frame)
        end = float(Fraction(end_frame, 1) / fps)

        next_label = f"ve{effect_idx}"
        effect_idx += 1
        en = enable_between_frames(start_frame, end_frame)
        envelope = envelope_expr(effect, start_frame, end_frame)

        if effect_type in {"flash", "dip_flash"}:
            default_opacity = 0.55 if effect_type == "flash" else 0.22
            opacity = max(0.0, min(1.0, float(effect.get("opacity", default_opacity))))
            default_color = [255, 255, 255] if effect_type == "flash" else [0, 0, 0]
            color = color_expr(effect, default_color, opacity)
            filters.append(
                f"[{current_label}]"
                f"drawbox=x=0:y=0:w=iw:h=ih:color={color}:t=fill:{en}"
                f"[{next_label}]"
            )
        elif effect_type in {
            "fade_to_black",
            "fade_from_black",
            "fade_to_white",
            "fade_from_white",
        }:
            white = effect_type.endswith("white")
            default_opacity = float(effect.get("opacity", 0.85 if white else 0.9))
            opacity = max(0.0, min(1.0, default_opacity))
            color = "white" if white else "black"
            progress = (
                f"clip((N-{start_frame})/{max(1, end_frame - start_frame - 1)},0,1)"
            )
            smooth = f"({progress})*({progress})*(3-2*({progress}))"
            weight = f"{opacity:.6f}*({smooth})"
            if effect_type.startswith("fade_from"):
                weight = f"{opacity:.6f}*(1-({smooth}))"
            color_label = f"vc{effect_idx}"
            filters.append(
                f"color=c={color}:s={width}x{height}:r={fps.numerator}/{fps.denominator}:"
                f"d={total_duration:.6f}[{color_label}]"
            )
            filters.append(
                f"[{current_label}][{color_label}]"
                f"blend=all_expr='A*(1-({weight})*between(N,{start_frame},{end_frame - 1}))"
                f"+B*({weight})*between(N,{start_frame},{end_frame - 1})':shortest=1"
                f"[{next_label}]"
            )
        elif effect_type == "punch_zoom":
            factor = max(1.0, float(effect.get("factor", 1.03)))
            anchor_x = max(0.0, min(1.0, float(effect.get("anchor_x", 0.5))))
            anchor_y = max(0.0, min(1.0, float(effect.get("anchor_y", 0.5))))
            dynamic_factor = f"1+({factor - 1.0:.8f})*({envelope})"
            filters.append(
                f"[{current_label}]"
                "scale="
                f"w='trunc(iw*({dynamic_factor})/2)*2':"
                f"h='trunc(ih*({dynamic_factor})/2)*2':"
                "eval=frame,"
                f"crop={width}:{height}:(iw-ow)*{anchor_x:.6f}:(ih-oh)*{anchor_y:.6f},setsar=1"
                f"[{next_label}]"
            )
        elif effect_type == "micro_freeze":
            # Duration-preserving frame replacement. It does not lengthen the
            # program; strong perceptual timing changes still return to 04.
            freeze_source = f"vfzsrc{effect_idx}"
            freeze_replace = f"vfzrep{effect_idx}"
            filters.append(
                f"[{current_label}]split=2[{freeze_source}][{freeze_replace}]"
            )
            filters.append(
                f"[{freeze_source}][{freeze_replace}]"
                f"freezeframes=first={start_frame}:last={end_frame - 1}:replace={start_frame}"
                f"[{next_label}]"
            )
        elif effect_type == "blur_pulse":
            sigma = max(0.1, float(effect.get("sigma", effect.get("factor", 1.0))))
            filters.append(
                f"[{current_label}]"
                f"gblur=sigma={sigma:.4f}:steps=1:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "unsharp_pulse":
            luma = float(effect.get("luma_amount", effect.get("factor", 0.8)))
            filters.append(
                f"[{current_label}]"
                f"unsharp=luma_msize_x=5:luma_msize_y=5:"
                f"luma_amount={luma:.4f}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "brightness_pulse":
            amount = float(effect.get("amount", effect.get("factor", 0.06)))
            filters.append(
                f"[{current_label}]"
                f"eq=brightness='if(between(t,{start:.6f},{end:.6f}),{amount:.4f},0)':eval=frame"
                f"[{next_label}]"
            )
        elif effect_type == "color_pulse":
            contrast = float(effect.get("contrast", 1.08))
            saturation = float(effect.get("saturation", 1.12))
            filters.append(
                f"[{current_label}]"
                f"eq=contrast='if(between(t,{start:.6f},{end:.6f}),{contrast:.4f},1)':"
                f"saturation='if(between(t,{start:.6f},{end:.6f}),{saturation:.4f},1)':eval=frame"
                f"[{next_label}]"
            )
        elif effect_type == "saturation_pulse":
            saturation = float(effect.get("saturation", effect.get("factor", 1.18)))
            filters.append(
                f"[{current_label}]"
                f"eq=saturation='if(between(t,{start:.6f},{end:.6f}),{saturation:.4f},1)':eval=frame"
                f"[{next_label}]"
            )
        elif effect_type == "contrast_pulse":
            contrast = float(effect.get("contrast", effect.get("factor", 1.12)))
            filters.append(
                f"[{current_label}]"
                f"eq=contrast='if(between(t,{start:.6f},{end:.6f}),{contrast:.4f},1)':eval=frame"
                f"[{next_label}]"
            )
        elif effect_type == "hue_pulse":
            degrees = float(effect.get("degrees", effect.get("factor", 8.0)))
            saturation = float(effect.get("saturation", 1.05))
            filters.append(
                f"[{current_label}]"
                f"hue=h={degrees:.4f}:s={saturation:.4f}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "temperature_pulse":
            temperature = float(effect.get("temperature", effect.get("factor", 6500)))
            # colortemperature expects kelvin-ish values; keep mild windowed pulse.
            filters.append(
                f"[{current_label}]"
                f"colortemperature=temperature={temperature:.1f}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "eq_grade_window":
            brightness = float(effect.get("brightness", 0.0))
            contrast = float(effect.get("contrast", 1.0))
            saturation = float(effect.get("saturation", 1.0))
            gamma = float(effect.get("gamma", 1.0))
            filters.append(
                f"[{current_label}]"
                f"eq=brightness='if(between(t,{start:.6f},{end:.6f}),{brightness:.4f},0)':"
                f"contrast='if(between(t,{start:.6f},{end:.6f}),{contrast:.4f},1)':"
                f"saturation='if(between(t,{start:.6f},{end:.6f}),{saturation:.4f},1)':"
                f"gamma='if(between(t,{start:.6f},{end:.6f}),{gamma:.4f},1)':eval=frame"
                f"[{next_label}]"
            )
        elif effect_type == "vignette_pulse":
            angle = float(effect.get("vignette_angle", 0.52))
            filters.append(
                f"[{current_label}]"
                f"vignette=angle={angle:.6f}:x0=w/2:y0=h/2:eval=frame:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "grain_pulse":
            strength = int(max(1, min(30, float(effect.get("strength", effect.get("factor", 8))))))
            filters.append(
                f"[{current_label}]"
                f"noise=alls={strength}:allf=t+u:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "rgb_split":
            px = int(max(1, min(8, float(effect.get("pixels", effect.get("factor", 2))))))
            filters.append(
                f"[{current_label}]"
                f"rgbashift=rh={px}:bv={px}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "chromatic_shift":
            cbh = int(effect.get("cbh", effect.get("factor", 2)))
            cbv = int(effect.get("cbv", 0))
            crh = int(effect.get("crh", effect.get("crw", -cbh)))
            crv = int(effect.get("crv", 0))
            filters.append(
                f"[{current_label}]"
                f"chromashift=cbh={cbh}:cbv={cbv}:crh={crh}:crv={crv}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "shake":
            amp = int(max(1, min(20, float(effect.get("amplitude", effect.get("factor", 4))))))
            frequency_x = float(effect.get("frequency_x", 12.0))
            frequency_y = float(effect.get("frequency_y", 15.0))
            filters.append(
                f"[{current_label}]"
                f"pad=iw+{amp * 2}:ih+{amp * 2}:{amp}:{amp}:color=black,"
                f"fillborders=left={amp}:right={amp}:top={amp}:bottom={amp}:mode=smear,"
                f"crop={width}:{height}:"
                f"x='{amp}+{amp}*({envelope})*sin({frequency_x:.4f}*2*PI*t)':"
                f"y='{amp}+{amp}*({envelope})*cos({frequency_y:.4f}*2*PI*t)',setsar=1"
                f"[{next_label}]"
            )
        elif effect_type == "tmix_smear":
            frames = int(max(2, min(8, float(effect.get("frames", effect.get("factor", 3))))))
            filters.append(
                f"[{current_label}]"
                f"tmix=frames={frames}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "horizontal_blur_whip":
            sigma = max(0.1, float(effect.get("sigma", effect.get("factor", 2.4))))
            sigma_v = max(0.0, float(effect.get("sigma_v", 0.1)))
            filters.append(
                f"[{current_label}]"
                f"gblur=sigma={sigma:.4f}:sigmaV={sigma_v:.4f}:steps=2:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "edge_flash":
            filters.append(
                f"[{current_label}]"
                f"edgedetect=mode=colormix:high=0.2:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "zoom_hold":
            factor = max(1.0, float(effect.get("factor", 1.04)))
            anchor_x = max(0.0, min(1.0, float(effect.get("anchor_x", 0.5))))
            anchor_y = max(0.0, min(1.0, float(effect.get("anchor_y", 0.5))))
            dynamic_factor = f"1+({factor - 1.0:.8f})*({envelope})"
            filters.append(
                f"[{current_label}]"
                "scale="
                f"w='trunc(iw*({dynamic_factor})/2)*2':"
                f"h='trunc(ih*({dynamic_factor})/2)*2':"
                "eval=frame,"
                f"crop={width}:{height}:(iw-ow)*{anchor_x:.6f}:(ih-oh)*{anchor_y:.6f},setsar=1"
                f"[{next_label}]"
            )
        elif effect_type == "drawtext_hit":
            text = (
                str(effect.get("text", ""))
                .replace("\\", r"\\")
                .replace(":", r"\:")
                .replace("'", r"\'")
            )
            if not text:
                raise SystemExit("drawtext_hit requires effect.text")
            fontsize = int(effect.get("fontsize", 48))
            fontcolor = str(effect.get("fontcolor", "white"))
            x = str(effect.get("x", "(w-text_w)/2"))
            y = str(effect.get("y", "h*0.12"))
            filters.append(
                f"[{current_label}]"
                f"drawtext=text='{text}':expansion=none:fontsize={fontsize}:fontcolor={fontcolor}:"
                f"x={x}:y={y}:{en}"
                f"[{next_label}]"
            )
        elif effect_type == "negate_flash":
            filters.append(f"[{current_label}]negate={en}[{next_label}]")
        elif effect_type == "pixelize_pulse":
            block = int(max(2, min(64, float(effect.get("block", effect.get("factor", 8))))))
            filters.append(
                f"[{current_label}]"
                f"pixelize=width={block}:height={block}:{en}"
                f"[{next_label}]"
            )
        else:
            raise SystemExit(f"Unsupported effect type: {effect_type}")

        current_label = next_label

    if current_label == input_label:
        filters.append(f"[{current_label}]null,format={pixel_format}[{output_label}]")
    else:
        filters.append(f"[{current_label}]format={pixel_format}[{output_label}]")
    return filters


def prepare_xfade_segments(
    segments: list[Segment],
    boundary_effects: list[dict[str, Any]],
    spec: RenderSpec,
    *,
    require_duration_preserving: bool,
) -> tuple[list[Segment], dict[int, dict[str, Any]]]:
    """Bind each xfade to one adjacent boundary and allocate source handles."""
    boundary_by_index: dict[int, dict[str, Any]] = {}
    prepend_seconds = [0.0 for _ in segments]
    append_seconds = [0.0 for _ in segments]

    for effect in boundary_effects:
        parameters = {
            key: value
            for key, value in effect.items()
            if key
            in (
                set(EFFECT_REGISTRY.payload["common_parameters"])
                | set(EFFECT_REGISTRY.payload["parameter_specs"])
            )
        }
        try:
            EFFECT_REGISTRY.validate_parameters(
                "xfade",
                parameters,
                require_final_xfade_handles=require_duration_preserving,
            )
        except EffectContractError as exc:
            raise SystemExit(str(exc)) from exc

        transition = str(
            effect.get("transition", effect.get("xfade_transition", "fade"))
        ).strip()
        if transition not in XFADE_TRANSITIONS:
            raise SystemExit(f"Unsupported xfade transition: {transition}")
        duration_frames = int(
            effect.get(
                "duration_frames",
                max(1, round(float(effect.get("duration", 0.16)) * spec.fps_float)),
            )
        )
        duration = float(Fraction(duration_frames, 1) / spec.fps)
        start_frame = int(
            effect.get(
                "start_frame",
                round(float(effect.get("start", -1.0)) * spec.fps_float),
            )
        )

        matched = None
        from_slot = str(effect.get("from_slot", ""))
        to_slot = str(effect.get("to_slot", ""))
        for idx in range(len(segments) - 1):
            cut_frame = round(segments[idx].output_out * spec.fps_float)
            slot_match = from_slot == segments[idx].slot and to_slot == segments[idx + 1].slot
            frame_match = abs(cut_frame - start_frame) <= 1
            if slot_match or (not from_slot and not to_slot and frame_match):
                matched = idx
                break
        if matched is None:
            raise SystemExit(
                f"xfade {effect.get('fx_id') or ''} does not match an adjacent recipe boundary"
            )
        if matched in boundary_by_index:
            raise SystemExit(
                f"duplicate xfade effects at boundary {segments[matched].slot} -> "
                f"{segments[matched + 1].slot}"
            )

        handles = effect.get("transition_handle_contract")
        duration_preserving = isinstance(handles, dict)
        if duration_preserving:
            cut_frame = round(segments[matched].output_out * spec.fps_float)
            if int(handles["fixed_program_cut_frame"]) != cut_frame:
                raise SystemExit(
                    f"xfade fixed_program_cut_frame={handles['fixed_program_cut_frame']} "
                    f"does not match recipe cut frame {cut_frame}"
                )
            if int(handles["transition_frames"]) != duration_frames:
                raise SystemExit("xfade transition_frames must equal duration_frames")
            pre_frames = int(handles["pre_cut_frames"])
            post_frames = int(handles["post_cut_frames"])
            if pre_frames + post_frames != duration_frames:
                raise SystemExit(
                    "xfade pre_cut_frames + post_cut_frames must equal transition_frames"
                )
            pre_seconds = float(Fraction(pre_frames, 1) / spec.fps)
            post_seconds = float(Fraction(post_frames, 1) / spec.fps)
            prepend_seconds[matched + 1] += pre_seconds
            append_seconds[matched] += post_seconds
        elif require_duration_preserving:
            raise SystemExit(
                "final xfade requires a duration-preserving transition_handle_contract"
            )

        boundary_by_index[matched] = {
            **effect,
            "duration": duration,
            "duration_frames": duration_frames,
            "transition": transition,
            "duration_preserving": duration_preserving,
        }

    extended: list[Segment] = []
    for idx, segment in enumerate(segments):
        pre = prepend_seconds[idx]
        post = append_seconds[idx]
        speed = segment.speed_factor
        source_in = segment.source_in - pre * speed
        source_out = segment.source_out + post * speed
        if source_in < -1e-6:
            raise SystemExit(
                f"insufficient incoming source handle before {segment.slot}: "
                f"need {pre * speed:.6f}s"
            )
        extended.append(
            Segment(
                slot=segment.slot,
                source=segment.source,
                source_in=max(0.0, source_in),
                source_out=source_out,
                output_in=segment.output_in - pre,
                output_out=segment.output_out + post,
                output_duration=segment.output_duration + pre + post,
                grade=segment.grade,
                note=segment.note,
            )
        )
    return extended, boundary_by_index


def join_segments_filter(
    labels: list[str],
    segments: list[Segment],
    boundary_by_index: dict[int, dict[str, Any]],
    output_label: str,
    pixel_format: str,
) -> tuple[list[str], float]:
    """Hard-concat or xfade already handle-bound adjacent segment streams."""
    if not labels:
        raise SystemExit("No segment labels to join")

    label_names = [lab.strip("[]") for lab in labels]
    if len(label_names) != len(segments):
        raise SystemExit("Segment/label count mismatch during join")

    if len(label_names) == 1:
        return (
            [f"[{label_names[0]}]null,format={pixel_format}[{output_label}]"],
            float(segments[0].output_duration),
        )

    filters: list[str] = []
    current = label_names[0]
    current_duration = float(segments[0].output_duration)
    for idx in range(len(label_names) - 1):
        nxt = label_names[idx + 1]
        out = f"jx{idx}"
        if idx in boundary_by_index:
            fx = boundary_by_index[idx]
            duration = float(fx["duration"])
            transition = str(fx["transition"])
            if duration >= current_duration or duration >= float(
                segments[idx + 1].output_duration
            ):
                raise SystemExit(
                    f"xfade duration {duration} too long for boundary after {segments[idx].slot}"
                )
            offset = max(0.0, current_duration - duration)
            filters.append(
                f"[{current}][{nxt}]xfade=transition={transition}:"
                f"duration={duration:.6f}:offset={offset:.6f}[{out}]"
            )
            current_duration = (
                current_duration + float(segments[idx + 1].output_duration) - duration
            )
        else:
            filters.append(f"[{current}][{nxt}]concat=n=2:v=1:a=0[{out}]")
            current_duration = current_duration + float(segments[idx + 1].output_duration)
        current = out

    filters.append(f"[{current}]format={pixel_format}[{output_label}]")
    return filters, current_duration


def geometry_filter(spec: RenderSpec, width: int, height: int) -> str:
    if spec.fit_mode == "fit_pad":
        return (
            f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color={spec.background}"
        )
    if spec.fit_mode == "fill_crop":
        return (
            f"scale={width}:{height}:force_original_aspect_ratio=increase,"
            f"crop={width}:{height}:(iw-ow)/2:(ih-oh)/2"
        )
    return f"scale={width}:{height}"


def segment_filter(
    payload: dict,
    seg: Segment,
    width: int,
    height: int,
    spec: RenderSpec,
    idx: int = 0,
) -> tuple[str, str]:
    speed = seg.speed_factor
    if not math.isfinite(speed) or speed <= 0:
        raise SystemExit(f"Bad speed in segment {seg.slot}")
    label = f"v{idx}"
    grade = grade_filter(payload, seg)
    grade_part = f"{grade}," if grade else ""
    output_frames = max(1, round(seg.output_duration * spec.fps_float))
    geometry = geometry_filter(spec, width, height)
    filter_text = (
        f"[{idx}:v]"
        f"trim=start={seg.source_in:.6f}:end={seg.source_out:.6f},"
        f"setpts=(PTS-STARTPTS)/{speed:.8f},"
        f"fps={spec.fps_text},"
        f"trim=end_frame={output_frames},setpts=N/({spec.fps_text}*TB),"
        f"{grade_part}"
        f"{geometry},"
        f"setsar=1,format={spec.pixel_format}"
        f"[{label}]"
    )
    return filter_text, label


def render_segmented(
    ffmpeg: str,
    payload: dict,
    render_segments: list[Segment],
    run_root: Path,
    output_path: Path,
    audio_path: Path,
    audio_start: float,
    total_duration: float,
    width: int,
    height: int,
    preset: str,
    crf: str,
    audio_bitrate: str,
    effects: list[dict],
    spec: RenderSpec,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_base = Path(tempfile.mkdtemp(prefix=f".{output_path.stem}-", dir=output_path.parent))
    try:
        has_effects = any(effect.get("type") != "hard_cut_note" for effect in effects)
        try:
            intermediate_crf = str(max(10, int(crf) - 4)) if has_effects else crf
        except ValueError:
            intermediate_crf = crf

        part_paths: list[Path] = []
        for idx, seg in enumerate(render_segments):
            part_path = tmp_base / f"part-{idx:03d}.mp4"
            filter_text, label = segment_filter(payload, seg, width, height, spec)
            cmd = [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(rel_or_abs(run_root, seg.source)),
                "-filter_complex",
                filter_text,
                "-map",
                f"[{label}]",
                "-an",
                "-c:v",
                "libx264",
                "-preset",
                preset,
                "-crf",
                intermediate_crf,
                "-pix_fmt",
                spec.pixel_format,
                "-r",
                spec.fps_text,
                "-movflags",
                "+faststart",
                str(part_path),
            ]
            subprocess.run(cmd, check=True)
            part_paths.append(part_path)

        concat_list = tmp_base / "parts.txt"
        concat_list.write_text("".join(f"file '{path.as_posix()}'\n" for path in part_paths))
        video_concat = tmp_base / "video-concat.mp4"
        subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(concat_list),
                "-c",
                "copy",
                str(video_concat),
            ],
            check=True,
        )
        video_for_mux = video_concat
        if has_effects:
            video_effects = tmp_base / "video-effects.mp4"
            effect_filters = effect_filter_chain(
                effects,
                input_label="0:v",
                output_label="vout",
                width=width,
                height=height,
                total_duration=total_duration,
                fps=spec.fps,
                pixel_format=spec.pixel_format,
            )
            subprocess.run(
                [
                    ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-i",
                    str(video_concat),
                    "-filter_complex",
                    ";".join(effect_filters),
                    "-map",
                    "[vout]",
                    "-an",
                    "-c:v",
                    "libx264",
                    "-preset",
                    preset,
                    "-crf",
                    crf,
                    "-pix_fmt",
                    spec.pixel_format,
                    "-r",
                    spec.fps_text,
                    "-movflags",
                    "+faststart",
                    str(video_effects),
                ],
                check=True,
            )
            video_for_mux = video_effects

        subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-ss",
                f"{audio_start:.6f}",
                "-t",
                f"{total_duration:.6f}",
                "-i",
                str(audio_path),
                "-i",
                str(video_for_mux),
                "-map",
                "1:v:0",
                "-map",
                "0:a:0",
                "-c:v",
                "copy",
                "-c:a",
                "aac",
                "-b:a",
                audio_bitrate,
                "-movflags",
                "+faststart",
                str(output_path),
            ],
            check=True,
        )
    finally:
        shutil.rmtree(tmp_base, ignore_errors=True)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_fx_compile_manifest(manifest_path: Path, recipe_path: Path) -> None:
    validator = ROOT / "scripts" / "validate_edit_finishing_fx_compile.py"
    launcher = ROOT / "scripts" / "idol-video-python"
    result = subprocess.run(
        [
            str(launcher),
            str(validator),
            str(manifest_path),
            "--expect-output",
            str(recipe_path),
            "--require-final",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(
            "04FX compile manifest validation failed before final render:\n"
            + (result.stdout or result.stderr)
        )


def validate_final_recipe(recipe_path: Path) -> None:
    validator = ROOT / "scripts" / "validate_edit_recipe.py"
    launcher = ROOT / "scripts" / "idol-video-python"
    result = subprocess.run(
        [
            str(launcher),
            str(validator),
            str(recipe_path),
            "--require-v3",
            "--mode",
            "final-render",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(
            "edit recipe validation failed before final render:\n"
            + (result.stdout or result.stderr)
        )


def atomic_write_yaml(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            yaml.safe_dump(payload, handle, allow_unicode=True, sort_keys=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def write_render_receipt(
    path: Path,
    *,
    recipe_path: Path,
    audio_path: Path,
    output_path: Path,
    compile_manifest_path: Path | None,
    spec: RenderSpec,
    width: int,
    height: int,
    profile: str,
    expected_frames: int,
    encoding: EncodingSpec,
    recipe_payload: dict[str, Any],
) -> None:
    probe = ffprobe_media(output_path)
    video_stream = next(
        (row for row in probe.get("streams", []) if row.get("codec_type") == "video"),
        {},
    )
    actual_frames = video_stream.get("nb_frames")
    audio_stream = next(
        (row for row in probe.get("streams", []) if row.get("codec_type") == "audio"),
        {},
    )
    try:
        actual_frames = int(actual_frames)
    except (TypeError, ValueError):
        actual_frames = round(float(probe["format"]["duration"]) * spec.fps_float)
    frame_tolerance = 0 if profile == "final" else 1
    if abs(actual_frames - expected_frames) > frame_tolerance:
        raise SystemExit(
            f"rendered frame count {actual_frames} does not match expected {expected_frames}"
        )
    if profile == "final":
        actual_width = int(video_stream.get("width", 0))
        actual_height = int(video_stream.get("height", 0))
        if (actual_width, actual_height) != (width, height):
            raise SystemExit(
                f"final render geometry {actual_width}x{actual_height} does not match "
                f"recipe {width}x{height}"
            )
        try:
            actual_fps = Fraction(str(video_stream.get("avg_frame_rate") or "0/1"))
        except (ValueError, ZeroDivisionError) as exc:
            raise SystemExit("final render has an unreadable average frame rate") from exc
        if actual_fps != spec.fps:
            raise SystemExit(
                f"final render FPS {actual_fps} does not match recipe {spec.fps}"
            )
        actual_pixel_format = str(video_stream.get("pix_fmt") or "unknown")
        if actual_pixel_format != spec.pixel_format:
            raise SystemExit(
                f"final render pixel format {actual_pixel_format!r} does not match "
                f"recipe {spec.pixel_format!r}"
            )
        codec_aliases = {
            "libx264": "h264",
            "h264": "h264",
            "prores_ks": "prores",
            "prores": "prores",
        }
        actual_video_codec = str(video_stream.get("codec_name") or "unknown").lower()
        expected_video_codec = codec_aliases.get(encoding.video_codec, encoding.video_codec)
        if actual_video_codec != expected_video_codec:
            raise SystemExit(
                f"final render video codec {actual_video_codec!r} does not match "
                f"delivery request {expected_video_codec!r}"
            )
        actual_audio_codec = str(audio_stream.get("codec_name") or "unknown").lower()
        if actual_audio_codec != encoding.audio_codec:
            raise SystemExit(
                f"final render audio codec {actual_audio_codec!r} does not match "
                f"delivery request {encoding.audio_codec!r}"
            )
        expected_delivery = ((recipe_payload.get("color_pipeline") or {}).get("delivery") or {})
        color_aliases = {"limited": "tv", "full": "pc"}
        for field in ("color_range", "color_space", "color_transfer", "color_primaries"):
            expected = str(expected_delivery.get(field) or "").lower()
            if not expected or expected == "unknown":
                continue
            expected = color_aliases.get(expected, expected)
            actual = str(video_stream.get(field) or "unknown").lower()
            actual = color_aliases.get(actual, actual)
            if actual != expected:
                raise SystemExit(
                    f"final render {field} {actual!r} does not match recipe {expected!r}"
                )
    receipt = {
        "schema_version": "idol_edit_render_manifest.v1",
        "profile": profile,
        "source_bindings": {
            "recipe": {"path": str(recipe_path), "sha256": sha256_file(recipe_path)},
            "audio": {"path": str(audio_path), "sha256": sha256_file(audio_path)},
        },
        "render_spec": {
            "fps": {"numerator": spec.fps.numerator, "denominator": spec.fps.denominator},
            "width": width,
            "height": height,
            "pixel_format": spec.pixel_format,
            "fit_mode": spec.fit_mode,
            "expected_frame_count": expected_frames,
        },
        "encoding": {
            "container": encoding.container,
            "requested_video_codec": encoding.video_codec,
            "requested_audio_codec": encoding.audio_codec,
        },
        "output": {
            "path": str(output_path),
            "sha256": sha256_file(output_path),
            "duration_seconds": float(probe["format"]["duration"]),
            "frame_count": actual_frames,
            "width": int(video_stream.get("width", 0)),
            "height": int(video_stream.get("height", 0)),
            "avg_frame_rate": str(video_stream.get("avg_frame_rate", "")),
            "video_codec": str(video_stream.get("codec_name") or "unknown"),
            "audio_codec": str(audio_stream.get("codec_name") or "unknown"),
            "pixel_format": str(video_stream.get("pix_fmt") or "unknown"),
            "color_range": str(video_stream.get("color_range") or "unknown"),
            "color_space": str(video_stream.get("color_space") or "unknown"),
            "color_transfer": str(video_stream.get("color_transfer") or "unknown"),
            "color_primaries": str(video_stream.get("color_primaries") or "unknown"),
        },
    }
    if compile_manifest_path is not None:
        receipt["source_bindings"]["fx_compile_manifest"] = {
            "path": str(compile_manifest_path),
            "sha256": sha256_file(compile_manifest_path),
        }
    receipt_schema = json.loads(
        (ROOT / "schemas" / "edit-render-manifest.schema.json").read_text()
    )
    jsonschema.Draft202012Validator(receipt_schema).validate(receipt)
    atomic_write_yaml(path, receipt)


def render(
    recipe_path: Path,
    run_root: Path,
    output_path: Path,
    profile: str,
    preview_start: float | None,
    preview_end: float | None,
    render_mode: str,
    fx_compile_manifest: Path | None,
    render_manifest: Path | None,
) -> None:
    if profile == "final" and (preview_start is not None or preview_end is not None):
        raise SystemExit(
            "final render cannot use --preview-start/--preview-end; "
            "render the complete frame-locked program or use the review profile"
        )
    ffmpeg = tool_path("ffmpeg")
    if profile == "final":
        if fx_compile_manifest is None:
            raise SystemExit(
                "final render requires --fx-compile-manifest proving the completed "
                "04FX transition-opportunity audit, including a valid zero-FX result"
            )
        validate_final_recipe(recipe_path.resolve())
        validate_fx_compile_manifest(
            fx_compile_manifest.resolve(), recipe_path.resolve()
        )
    payload, segments = load_segments(recipe_path)
    spec = parse_render_spec(payload)
    if profile == "final" and payload.get("schema_version") == "idol_edit_recipe.v3" and not payload.get("render_spec"):
        raise SystemExit("idol_edit_recipe.v3 final render requires render_spec")
    audio_value = (payload.get("audio_program") or {}).get(
        "path", payload.get("audio_path", "audio/selected/loom-dubut.mp3")
    )
    audio_path = rel_or_abs(run_root, audio_value)
    if not audio_path.is_file():
        raise SystemExit(f"selected audio is not readable: {audio_path}")

    audio_start = 0.0
    render_segments = segments
    render_effects = payload.get("effects") or []
    if preview_start is not None:
        if preview_end is None or preview_end <= preview_start:
            raise SystemExit("--preview-end must be greater than --preview-start")
        audio_start = preview_start
        render_segments = slice_segments(segments, preview_start, preview_end)
        render_effects = slice_effects(render_effects, preview_start, preview_end, spec.fps)

    recipe_duration = sum(seg.output_duration for seg in render_segments)
    expected_frames = round(recipe_duration * spec.fps_float)
    recipe_duration = float(Fraction(expected_frames, 1) / spec.fps)
    if profile == "final" and media_duration(audio_path) + 0.5 / spec.fps_float < audio_start + recipe_duration:
        raise SystemExit("selected audio is shorter than the frame-locked final program")
    width, height, preset, crf, audio_bitrate = profile_settings(profile, spec)
    encoding = encoding_spec(
        payload,
        profile,
        output_path,
        preset=preset,
        crf=crf,
        audio_bitrate=audio_bitrate,
    )
    color_args = delivery_color_args(payload, encoding.video_codec)
    stream_effects, boundary_effects = split_effects(render_effects)
    if render_mode == "segments":
        if profile == "final":
            raise SystemExit(
                "final render requires --render-mode filter so the recipe delivery codec "
                "is applied in one source-clean encode"
            )
        if boundary_effects:
            raise SystemExit(
                "Boundary xfade effects require --render-mode filter "
                "(segment concat path is hard-cut only)."
            )
        validate_source_bounds(render_segments, run_root, spec.fps)
        render_segmented(
            ffmpeg,
            payload,
            render_segments,
            run_root,
            output_path,
            audio_path,
            audio_start,
            recipe_duration,
            width,
            height,
            preset,
            crf,
            audio_bitrate,
            stream_effects,
            spec,
        )
        receipt_path = render_manifest
        if profile == "final" and receipt_path is None:
            receipt_path = output_path.with_name(f"{output_path.stem}-render-manifest.yaml")
        if receipt_path is not None:
            write_render_receipt(
                receipt_path,
                recipe_path=recipe_path.resolve(),
                audio_path=audio_path.resolve(),
                output_path=output_path.resolve(),
                compile_manifest_path=fx_compile_manifest.resolve() if fx_compile_manifest else None,
                spec=spec,
                width=width,
                height=height,
                profile=profile,
                expected_frames=expected_frames,
                encoding=encoding,
                recipe_payload=payload,
            )
        print(output_path)
        if receipt_path is not None:
            print(receipt_path)
        return
    if render_mode != "filter":
        raise SystemExit(f"Unknown render mode: {render_mode}")

    effective_segments, boundary_by_index = prepare_xfade_segments(
        render_segments,
        boundary_effects,
        spec,
        require_duration_preserving=profile == "final",
    )
    validate_source_bounds(effective_segments, run_root, spec.fps)

    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"]
    for seg in effective_segments:
        cmd += ["-i", str(rel_or_abs(run_root, seg.source))]
    audio_input_index = len(effective_segments)

    filters: list[str] = []
    labels: list[str] = []
    for idx, seg in enumerate(effective_segments):
        filter_text, label = segment_filter(payload, seg, width, height, spec, idx)
        labels.append(f"[{label}]")
        filters.append(filter_text)

    join_filters, joined_duration = join_segments_filter(
        labels,
        effective_segments,
        boundary_by_index,
        output_label="vbase" if stream_effects else "vout",
        pixel_format=spec.pixel_format,
    )
    filters.extend(join_filters)
    total_duration = joined_duration
    if stream_effects:
        filters.extend(
            effect_filter_chain(
                stream_effects,
                input_label="vbase",
                output_label="vout",
                width=width,
                height=height,
                total_duration=total_duration,
                fps=spec.fps,
                pixel_format=spec.pixel_format,
            )
        )

    if profile == "final" and abs(total_duration - recipe_duration) > 0.5 / spec.fps_float:
        raise SystemExit(
            f"final joined duration {total_duration:.6f}s changed frame-locked program "
            f"duration {recipe_duration:.6f}s"
        )

    cmd += ["-ss", f"{audio_start:.6f}", "-t", f"{total_duration:.6f}", "-i", str(audio_path)]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd += [
        "-filter_complex",
        ";".join(filters),
        "-map",
        "[vout]",
        "-map",
        f"{audio_input_index}:a:0",
        *encoding.video_args,
        "-pix_fmt",
        spec.pixel_format,
        *color_args,
        "-r",
        spec.fps_text,
        "-fps_mode",
        "cfr",
        *encoding.audio_args,
        *encoding.movflags,
        str(output_path),
    ]
    if profile != "final":
        cmd.insert(-1, "-shortest")
    subprocess.run(cmd, check=True)
    if boundary_effects and abs(joined_duration - recipe_duration) > 0.5 / spec.fps_float:
        print(
            f"preview note: legacy boundary xfade shortened video by "
            f"{recipe_duration - joined_duration:.3f}s "
            f"(recipe {recipe_duration:.3f}s -> render {joined_duration:.3f}s); "
            "re-check selected-audio sync",
            flush=True,
        )
    receipt_path = render_manifest
    if profile == "final" and receipt_path is None:
        receipt_path = output_path.with_name(f"{output_path.stem}-render-manifest.yaml")
    if receipt_path is not None:
        write_render_receipt(
            receipt_path,
            recipe_path=recipe_path.resolve(),
            audio_path=audio_path.resolve(),
            output_path=output_path.resolve(),
            compile_manifest_path=fx_compile_manifest.resolve() if fx_compile_manifest else None,
            spec=spec,
            width=width,
            height=height,
            profile=profile,
            expected_frames=expected_frames if profile == "final" else round(total_duration * spec.fps_float),
            encoding=encoding,
            recipe_payload=payload,
        )
    print(output_path)
    if receipt_path is not None:
        print(receipt_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, default=Path("runs/2026-05-24/AURORA_M_FULL_CODE_ROOT_SIGNAL"))
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile", choices=["proxy", "review", "final"], default="proxy")
    parser.add_argument("--render-mode", choices=["filter", "segments"], default="filter")
    parser.add_argument("--preview-start", type=float)
    parser.add_argument("--preview-end", type=float)
    parser.add_argument(
        "--fx-compile-manifest",
        type=Path,
        help="Hash-bound final_pass_only 04FX compile manifest for a final recipe.",
    )
    parser.add_argument(
        "--render-manifest",
        type=Path,
        help="Output render receipt. Final renders create one beside the output by default.",
    )
    args = parser.parse_args()
    if (args.preview_start is None) != (args.preview_end is None):
        parser.error("--preview-start and --preview-end must be provided together")
    render(
        recipe_path=args.recipe,
        run_root=args.run_root,
        output_path=args.output,
        profile=args.profile,
        preview_start=args.preview_start,
        preview_end=args.preview_end,
        render_mode=args.render_mode,
        fx_compile_manifest=args.fx_compile_manifest,
        render_manifest=args.render_manifest,
    )


if __name__ == "__main__":
    main()
