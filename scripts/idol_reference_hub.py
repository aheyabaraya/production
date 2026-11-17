#!/usr/bin/env python3
"""Build and query the IDOL run-external downloaded-reference hub.

This module is deliberately network-free.  It normalizes legacy source indexes
and canonical per-source manifests, deduplicates by platform identity, URL, and
declared/local SHA-256, and fails closed before a caller considers acquisition.
It never downloads, deletes, moves, uploads, or approves media.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections.abc import Iterable
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import yaml


SCHEMA_VERSION = "idol_downloaded_reference_hub.v1"
DEFAULT_HUB_ROOT = Path("source-materials/video-sources")
DEFAULT_CATALOG_NAME = "reference-hub-catalog.yaml"
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
BVID_RE = re.compile(r"(?i)\b(BV[0-9A-Za-z]{10})\b")
AVID_RE = re.compile(r"(?i)(?:^|[^A-Za-z0-9])av(\d{5,})(?:[^0-9]|$)")
YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
INSTAGRAM_SHORTCODE_RE = re.compile(r"^[A-Za-z0-9_-]{5,}$")
TRACKING_QUERY_KEYS = {"feature", "si", "spm_id_from", "share_source", "igsh", "igshid"}

MEDIA_FIELDS = (
    "video_file",
    "local_video",
    "analysis_clean_video_file",
    "audio_file",
    "local_audio",
    "output_path",
    "media_file",
)
CONTACT_FIELDS = ("contact_sheet", "contact_sheets")
FRAME_INDEX_FIELDS = ("frame_index", "frame_index_path")
METADATA_FIELDS = (
    "info_json",
    "local_info_json",
    "thumbnail",
    "scene_detection_csv",
    "prior_local_reading",
)


class HubError(ValueError):
    """A fail-closed reference-hub contract error."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_payload(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def boundaries() -> dict[str, bool]:
    return {
        "network_access_performed": False,
        "download_approved": False,
        "creative_lock_created": False,
        "generation_input_allowed": False,
        "edit_source_allowed": False,
    }


def yaml_bytes(document: dict[str, Any]) -> bytes:
    return yaml.safe_dump(
        document,
        allow_unicode=True,
        sort_keys=False,
        width=1000,
    ).encode("utf-8")


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise HubError(f"cannot read YAML {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise HubError(f"YAML root must be a mapping: {path}")
    return payload


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HubError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise HubError(f"JSON root must be a mapping: {path}")
    return payload


def atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
        os.replace(tmp_name, path)
    finally:
        tmp_path = Path(tmp_name)
        if tmp_path.exists():
            tmp_path.unlink()


def _path_parts(raw: str | Path) -> tuple[str, ...]:
    return Path(str(raw)).parts


def safe_repo_path(
    root: Path,
    raw: str | Path,
    *,
    base_rel: Path | None = None,
    allow_absolute: bool = False,
    require_file: bool = False,
) -> tuple[Path, str]:
    value = str(raw).strip()
    if not value:
        raise HubError("empty path is not allowed")
    candidate_raw = Path(value).expanduser()
    if ".." in _path_parts(candidate_raw):
        raise HubError(f"path traversal is not allowed: {value}")
    root_resolved = root.resolve()
    if candidate_raw.is_absolute():
        if not allow_absolute:
            raise HubError(f"absolute path is not allowed here: {value}")
        candidate = candidate_raw
    elif value.startswith(("source-materials/", "runs/", "catalog/", "assets/")):
        candidate = root / candidate_raw
    else:
        candidate = root / (base_rel or Path()) / candidate_raw
    candidate_absolute = candidate.absolute()
    resolved = candidate_absolute.resolve(strict=False)
    try:
        resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise HubError(f"path escapes repository root: {value}") from exc
    if require_file and (
        not candidate_absolute.is_file() or candidate_absolute.is_symlink()
    ):
        raise HubError(f"required regular file is missing: {value}")
    rel = candidate_absolute.relative_to(root.absolute()).as_posix()
    return candidate_absolute, rel


def _platform_slug(value: str) -> str:
    slug = re.sub(r"[^a-z0-9_-]+", "-", value.lower()).strip("-")
    if len(slug) < 2:
        raise HubError(f"invalid platform name: {value!r}")
    return slug[:64]


def _path_id(value: str) -> str:
    # Leading underscores and hyphens are valid platform-id bytes (notably for
    # YouTube); only trim dots that could be confused with path traversal.
    result = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip(".")
    if not result or result in {".", ".."}:
        raise HubError(f"invalid platform id for canonical path: {value!r}")
    return result[:160]


def infer_platform(host: str, explicit: str | None = None) -> str:
    if explicit:
        return _platform_slug(explicit)
    host = host.lower().split(":", 1)[0]
    if host == "b23.tv" or host.endswith(".bilibili.com") or host == "bilibili.com":
        return "bilibili"
    if host == "youtu.be" or host.endswith(".youtube.com") or host == "youtube.com":
        return "youtube"
    if host == "instagram.com" or host.endswith(".instagram.com"):
        return "instagram"
    return "web"


def _normalized_generic_url(parts: Any) -> str:
    host = (parts.hostname or "").lower()
    if not host:
        raise HubError("source URL requires a host")
    port = parts.port
    netloc = host if not port or port == 443 else f"{host}:{port}"
    path = re.sub(r"/{2,}", "/", parts.path or "/")
    if path != "/":
        path = path.rstrip("/")
    query = []
    for key, value in parse_qsl(parts.query, keep_blank_values=True):
        lower = key.lower()
        if lower.startswith("utm_") or lower in TRACKING_QUERY_KEYS:
            continue
        query.append((key, value))
    return urlunsplit(("https", netloc, path, urlencode(sorted(query)), ""))


def normalize_identity(
    url: str | None,
    *,
    explicit_platform: str | None = None,
    explicit_id: str | None = None,
) -> dict[str, str]:
    raw_url = (url or "").strip()
    parts = None
    if raw_url:
        if "://" not in raw_url:
            raw_url = f"https://{raw_url}"
        parts = urlsplit(raw_url)
        if parts.scheme.lower() not in {"http", "https"}:
            raise HubError(f"only public HTTP(S) source URLs are supported: {url}")
        if parts.username or parts.password:
            raise HubError("credential-bearing source URLs are forbidden")
    platform = infer_platform(parts.hostname if parts else "", explicit_platform)
    platform_id = (explicit_id or "").strip()

    if platform == "bilibili":
        haystack = " ".join(filter(None, [platform_id, raw_url]))
        bvid = BVID_RE.search(haystack)
        avid = AVID_RE.search(haystack)
        if bvid:
            value = bvid.group(1)
            platform_id = "BV" + value[2:]
            normalized_url = f"https://www.bilibili.com/video/{platform_id}/"
        elif avid:
            platform_id = f"av{avid.group(1)}"
            normalized_url = f"https://www.bilibili.com/video/{platform_id}/"
        else:
            raise HubError("Bilibili source requires a direct BV or av platform id")
    elif platform == "youtube":
        candidate = platform_id
        if not candidate and parts:
            host = (parts.hostname or "").lower()
            segments = [segment for segment in parts.path.split("/") if segment]
            if host == "youtu.be" and segments:
                candidate = segments[0]
            elif segments and segments[0] in {"shorts", "embed", "live"} and len(segments) > 1:
                candidate = segments[1]
            else:
                candidate = dict(parse_qsl(parts.query)).get("v", "")
        if not YOUTUBE_ID_RE.fullmatch(candidate):
            raise HubError("YouTube source requires an exact 11-character video id")
        platform_id = candidate
        normalized_url = f"https://www.youtube.com/watch?v={platform_id}"
    elif platform == "instagram":
        content_kind = "p"
        candidate = platform_id
        if parts:
            segments = [segment for segment in parts.path.split("/") if segment]
            kind_index = None
            for index, segment in enumerate(segments):
                if segment.lower() in {"p", "reel", "reels", "tv"}:
                    kind_index = index
                    break
            if kind_index is not None and kind_index + 1 < len(segments):
                kind = segments[kind_index].lower()
                content_kind = "reel" if kind in {"reel", "reels"} else ("tv" if kind == "tv" else "p")
                if not candidate:
                    candidate = segments[kind_index + 1]
            elif not candidate and segments:
                # username/media-style residual; last path segment is often the shortcode
                candidate = segments[-1]
        if not candidate or not INSTAGRAM_SHORTCODE_RE.fullmatch(candidate):
            raise HubError(
                "Instagram source requires a public post, Reel, or IGTV shortcode in the URL"
            )
        platform_id = candidate
        normalized_url = f"https://www.instagram.com/{content_kind}/{platform_id}/"
    else:
        if not parts:
            raise HubError("non-Bilibili source identity requires a URL")
        normalized_url = _normalized_generic_url(parts)
        if not platform_id:
            platform_id = "url-" + hashlib.sha256(normalized_url.encode("utf-8")).hexdigest()[:20]
    source_key = f"{platform}:{platform_id}"
    return {
        "platform": platform,
        "platform_id": platform_id,
        "normalized_url": normalized_url,
        "source_key": source_key,
    }


def canonical_source_root(identity: dict[str, str]) -> str:
    return (
        DEFAULT_HUB_ROOT
        / _platform_slug(identity["platform"])
        / "by-source"
        / _path_id(identity["platform_id"])
    ).as_posix()


def identity_keys(identity: dict[str, str]) -> set[str]:
    return {
        f"id:{identity['platform']}:{identity['platform_id']}",
        f"url:{identity['normalized_url']}",
    }


def _flatten_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        result: list[str] = []
        for item in value:
            result.extend(_flatten_strings(item))
        return result
    if isinstance(value, dict):
        result = []
        for key in sorted(value):
            result.extend(_flatten_strings(value[key]))
        return result
    return []


def _first_string(record: dict[str, Any], names: Iterable[str]) -> str | None:
    for name in names:
        value = record.get(name)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _valid_hashes(record: dict[str, Any]) -> list[str]:
    values: list[str] = []
    for field in ("sha256", "source_sha256", "media_sha256"):
        raw = record.get(field)
        if isinstance(raw, str):
            value = raw.lower().strip()
            if SHA256_RE.fullmatch(value):
                values.append(value)
    media = record.get("media")
    if isinstance(media, list):
        for item in media:
            if isinstance(item, dict) and isinstance(item.get("sha256"), str):
                value = item["sha256"].lower().strip()
                if SHA256_RE.fullmatch(value):
                    values.append(value)
    return sorted(set(values))


class ReferenceHub:
    def __init__(
        self,
        root: Path,
        hub_root_rel: Path = DEFAULT_HUB_ROOT,
        catalog_rel: Path | None = None,
    ) -> None:
        self.root = root.resolve()
        self.hub_root_rel = Path(hub_root_rel)
        _, hub_rel = safe_repo_path(self.root, self.hub_root_rel)
        self.hub_root_rel = Path(hub_rel)
        self.hub_root = self.root / self.hub_root_rel
        self.catalog_rel = catalog_rel or self.hub_root_rel / DEFAULT_CATALOG_NAME

    def _collection_root(self, document: dict[str, Any], index_path: Path) -> Path:
        declared = document.get("collection_root")
        if declared is None:
            return Path(index_path.parent.absolute().relative_to(self.root.absolute()))
        _, rel = safe_repo_path(self.root, str(declared))
        return Path(rel)

    def _path_evidence(
        self, value: str, collection_root_rel: Path
    ) -> dict[str, Any]:
        _, rel = safe_repo_path(self.root, value, base_rel=collection_root_rel)
        return {"path": rel}

    def _declared_paths(
        self, record: dict[str, Any], collection_root_rel: Path
    ) -> dict[str, list[dict[str, Any]]]:
        groups: dict[str, tuple[str, ...]] = {
            "media": MEDIA_FIELDS,
            "contact_sheets": CONTACT_FIELDS,
            "frame_indexes": FRAME_INDEX_FIELDS,
            "metadata": METADATA_FIELDS,
        }
        output: dict[str, list[dict[str, Any]]] = {}
        for group, fields in groups.items():
            values: list[str] = []
            for field in fields:
                values.extend(_flatten_strings(record.get(field)))
            evidence = {
                item["path"]: item
                for item in (
                    self._path_evidence(value, collection_root_rel)
                    for value in sorted(set(values))
                )
            }
            output[group] = [evidence[key] for key in sorted(evidence)]
        return output

    @staticmethod
    def _registration_status(declared: dict[str, list[dict[str, Any]]]) -> str:
        primary = (
            declared["media"]
            + declared["contact_sheets"]
        )
        if primary:
            return "evidence_declared"
        return "metadata_only"

    def _legacy_records(
        self, path: Path, warnings: list[str]
    ) -> tuple[list[dict[str, Any]], dict[str, str]]:
        document = load_yaml(path)
        source_index_sha = sha256_file(path)
        path_rel = path.absolute().relative_to(self.root.absolute()).as_posix()
        generated = {
            "path": path_rel,
            "sha256": source_index_sha,
            "record_kind": "legacy_source_index",
        }
        sources = document.get("sources")
        if isinstance(sources, dict):
            rows = [(str(key), value) for key, value in sources.items()]
        elif isinstance(sources, list):
            rows = [(str(index + 1), value) for index, value in enumerate(sources)]
        else:
            warnings.append(f"{path_rel}: sources is not a mapping or list")
            return [], generated
        platform = _first_string(document, ("source_platform", "platform"))
        collection_root = self._collection_root(document, path)
        records: list[dict[str, Any]] = []
        for fallback_id, value in rows:
            if not isinstance(value, dict):
                warnings.append(f"{path_rel}:{fallback_id}: source record is not a mapping")
                continue
            reference_id = _first_string(value, ("ref_id", "source_id", "reference_id")) or fallback_id
            source_url = _first_string(
                value, ("url", "source_url", "webpage_url", "yt_dlp_webpage_url")
            )
            explicit_platform = _first_string(value, ("source_platform", "platform")) or platform
            if explicit_platform and _platform_slug(explicit_platform) == "bilibili":
                explicit_id = _first_string(value, ("bvid", "bv_id", "platform_id"))
            elif explicit_platform and _platform_slug(explicit_platform) == "youtube":
                explicit_id = _first_string(value, ("youtube_id", "video_id", "platform_id"))
            elif explicit_platform and _platform_slug(explicit_platform) == "instagram":
                explicit_id = _first_string(
                    value, ("instagram_id", "shortcode", "reel_id", "platform_id")
                )
            else:
                explicit_id = _first_string(
                    value,
                    (
                        "platform_id",
                        "bvid",
                        "bv_id",
                        "youtube_id",
                        "video_id",
                        "instagram_id",
                        "shortcode",
                        "reel_id",
                    ),
                )
            try:
                identity = normalize_identity(
                    source_url,
                    explicit_platform=explicit_platform,
                    explicit_id=explicit_id,
                )
            except HubError as exc:
                warnings.append(f"{path_rel}:{reference_id}: {exc}")
                continue
            declared = self._declared_paths(value, collection_root)
            records.append(
                {
                    "source_index_path": path_rel,
                    "source_index_sha256": source_index_sha,
                    "record_kind": "legacy_source_index",
                    "reference_id": reference_id,
                    "identity": identity,
                    "title": _first_string(value, ("title", "source_title", "bilibili_title")),
                    "declared_paths": declared,
                    "media_sha256s": _valid_hashes(value),
                    "registration_status": self._registration_status(declared),
                }
            )
        return records, generated

    def _canonical_record(
        self, path: Path
    ) -> tuple[dict[str, Any], dict[str, str]]:
        document = load_yaml(path)
        self.validate_document(document, expected_type="source_manifest")
        source_index_sha = sha256_file(path)
        path_rel = path.absolute().relative_to(self.root.absolute()).as_posix()
        if Path(path_rel).parent.as_posix() != document["canonical_source_root"]:
            raise HubError(
                f"canonical source manifest is not stored at its declared source root: {path_rel}"
            )
        frame_pointer = document.get("frame_index_path")
        if frame_pointer is not None:
            frame_path, frame_rel = safe_repo_path(
                self.root, frame_pointer, require_file=True
            )
            frame_document = load_yaml(frame_path)
            self.validate_document(frame_document, expected_type="frame_index")
            if frame_document["source_key"] != document["identity"]["source_key"]:
                raise HubError(f"frame index source_key mismatch: {frame_rel}")
            if frame_document["source_manifest_path"] != path_rel:
                raise HubError(f"frame index source-manifest pointer mismatch: {frame_rel}")
            contact_pointer = frame_document.get("contact_sheet_manifest")
            if contact_pointer is not None:
                _, source_evidence, _ = self._qc_sheet_manifest_evidence(
                    contact_pointer["path"]
                )
                if not any(
                    item["kind"] == "video"
                    and item["path"] == source_evidence["path"]
                    and item["sha256"] == source_evidence["sha256"]
                    and item["byte_size"] == source_evidence["byte_size"]
                    for item in document["media"]
                ):
                    raise HubError(
                        f"QC sheet manifest source_video does not match source manifest media: {frame_rel}"
                    )
        identity = document["identity"]
        base = Path(document["canonical_source_root"])
        discovery_metadata = document.get("discovery_metadata")
        record: dict[str, Any] = {
            "video_file": [item["path"] for item in document["media"]],
            "contact_sheets": [item["path"] for item in document["contact_sheets"]],
            "frame_index_path": document.get("frame_index_path"),
        }
        if isinstance(discovery_metadata, dict):
            metadata_file = discovery_metadata.get("metadata_file")
            if isinstance(metadata_file, dict) and metadata_file.get("path"):
                record["info_json"] = metadata_file["path"]
        declared = self._declared_paths(record, base)
        occurrence = {
            "source_index_path": path_rel,
            "source_index_sha256": source_index_sha,
            "record_kind": "canonical_source_manifest",
            "reference_id": identity["source_key"],
            "identity": identity,
            "title": document.get("title"),
            "declared_paths": declared,
            "media_sha256s": sorted(item["sha256"] for item in document["media"]),
            "registration_status": self._registration_status(declared),
        }
        if isinstance(discovery_metadata, dict):
            occurrence["discovery_metadata"] = discovery_metadata
        generated = {
            "path": path_rel,
            "sha256": source_index_sha,
            "record_kind": "canonical_source_manifest",
        }
        return occurrence, generated

    def scan(self) -> tuple[list[dict[str, Any]], list[dict[str, str]], list[str]]:
        records: list[dict[str, Any]] = []
        generated_from: list[dict[str, str]] = []
        warnings: list[str] = []
        if not self.hub_root.exists():
            return records, generated_from, warnings
        for path in sorted(self.hub_root.glob("**/source-index-v*.yaml")):
            rows, generated = self._legacy_records(path, warnings)
            records.extend(rows)
            generated_from.append(generated)
        for path in sorted(self.hub_root.glob("*/by-source/*/source-manifest.yaml")):
            row, generated = self._canonical_record(path)
            records.append(row)
            generated_from.append(generated)
        generated_from.sort(key=lambda item: (item["path"], item["record_kind"]))
        return records, generated_from, sorted(set(warnings))

    @staticmethod
    def _group_records(records: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
        parent = list(range(len(records)))

        def find(index: int) -> int:
            while parent[index] != index:
                parent[index] = parent[parent[index]]
                index = parent[index]
            return index

        def union(left: int, right: int) -> None:
            left_root = find(left)
            right_root = find(right)
            if left_root != right_root:
                parent[max(left_root, right_root)] = min(left_root, right_root)

        seen: dict[str, int] = {}
        for index, record in enumerate(records):
            keys = identity_keys(record["identity"])
            keys.update(f"sha:{value}" for value in record["media_sha256s"])
            for key in sorted(keys):
                if key in seen:
                    union(index, seen[key])
                else:
                    seen[key] = index
        groups: dict[int, list[dict[str, Any]]] = {}
        for index, record in enumerate(records):
            groups.setdefault(find(index), []).append(record)
        return list(groups.values())

    @staticmethod
    def _identity_sort(identity: dict[str, str]) -> tuple[str, str, str]:
        return identity["platform"], identity["platform_id"], identity["normalized_url"]

    def _catalog_source(self, group: list[dict[str, Any]]) -> dict[str, Any]:
        preferred = sorted(
            group,
            key=lambda row: (
                row["record_kind"] != "canonical_source_manifest",
                self._identity_sort(row["identity"]),
                row["source_index_path"],
                row["reference_id"],
            ),
        )[0]
        identity_map = {
            (
                row["identity"]["platform"],
                row["identity"]["platform_id"],
                row["identity"]["normalized_url"],
            ): row["identity"]
            for row in group
        }
        aliases = [identity_map[key] for key in sorted(identity_map)]
        titles = sorted({row["title"] for row in group if row.get("title")})
        hashes = sorted({value for row in group for value in row["media_sha256s"]})
        occurrences = sorted(
            group,
            key=lambda row: (
                row["source_index_path"],
                row["reference_id"],
                row["identity"]["source_key"],
            ),
        )
        status_counts = {
            state: sum(row["registration_status"] == state for row in group)
            for state in ("evidence_declared", "metadata_only")
        }
        state = "evidence_declared" if status_counts["evidence_declared"] else "metadata_only"
        chosen_identity = preferred["identity"]
        if preferred["record_kind"] == "canonical_source_manifest":
            canonical_root = Path(preferred["source_index_path"]).parent.as_posix()
        else:
            canonical_root = canonical_source_root(chosen_identity)
        source = {
            "source_key": chosen_identity["source_key"],
            "canonical_identity": chosen_identity,
            "canonical_source_root": canonical_root,
            "aliases": aliases,
            "titles": titles,
            "media_sha256s": hashes,
            "occurrences": occurrences,
            "registration": {
                "state": state,
                "evidence_declared_occurrence_count": status_counts["evidence_declared"],
                "metadata_only_occurrence_count": status_counts["metadata_only"],
            },
            "acquisition_policy": {
                "new_capture_default": (
                    "public_bilibili_current_task_only"
                    if chosen_identity["platform"] == "bilibili"
                    else "exact_founder_approval_required"
                ),
                "historical_existing_only": chosen_identity["platform"] != "bilibili",
            },
        }
        if isinstance(preferred.get("discovery_metadata"), dict):
            source["discovery_metadata"] = preferred["discovery_metadata"]
        return source

    def build_catalog(self) -> dict[str, Any]:
        records, generated_from, warnings = self.scan()
        sources = [self._catalog_source(group) for group in self._group_records(records)]
        sources.sort(key=lambda item: item["source_key"])
        source_set = [
            {"path": item["path"], "sha256": item["sha256"], "record_kind": item["record_kind"]}
            for item in generated_from
        ]
        document = {
            "schema_version": SCHEMA_VERSION,
            "artifact_type": "catalog",
            "hub_root": self.hub_root_rel.as_posix(),
            "catalog_path": Path(self.catalog_rel).as_posix(),
            "scan_contract": {
                "legacy_source_index_glob": "**/source-index-v*.yaml",
                "canonical_manifest_glob": "*/by-source/*/source-manifest.yaml",
                "network_access": False,
                "catalog_pointer_only": True,
                "deterministic_no_timestamp": True,
            },
            "generated_from": source_set,
            "source_index_set_sha256": digest_payload(source_set),
            "sources": sources,
            "scan_warnings": warnings,
            "automation_boundaries": boundaries(),
        }
        self.validate_document(document, expected_type="catalog")
        return document

    def write_catalog(self, *, check: bool = False) -> tuple[bool, dict[str, Any]]:
        document = self.build_catalog()
        content = yaml_bytes(document)
        catalog_path, _ = safe_repo_path(self.root, self.catalog_rel)
        if catalog_path.is_symlink():
            raise HubError("catalog path cannot be a symlink")
        current = catalog_path.read_bytes() if catalog_path.exists() else None
        current_matches = current == content
        if not check and not current_matches:
            atomic_write(catalog_path, content)
        return current_matches, document

    def read_tracked_catalog(self) -> dict[str, Any]:
        catalog_path, _ = safe_repo_path(self.root, self.catalog_rel)
        if not catalog_path.is_file() or catalog_path.is_symlink():
            raise HubError("tracked catalog is missing; run build")
        catalog = load_yaml(catalog_path)
        self.validate_document(catalog, expected_type="catalog")
        return catalog

    def upsert_catalog_source(self, manifest_rel: str) -> None:
        catalog_path, _ = safe_repo_path(self.root, self.catalog_rel)
        if not catalog_path.is_file():
            self.write_catalog(check=False)
            return
        catalog = self.read_tracked_catalog()
        record, generated = self._canonical_record(self.root / manifest_rel)
        source = self._catalog_source([record])
        catalog["sources"] = [
            row
            for row in catalog.get("sources") or []
            if isinstance(row, dict) and row.get("source_key") != source["source_key"]
        ]
        catalog["sources"].append(source)
        catalog["sources"].sort(key=lambda item: item["source_key"])
        catalog["generated_from"] = [
            row
            for row in catalog.get("generated_from") or []
            if isinstance(row, dict) and row.get("path") != generated["path"]
        ]
        catalog["generated_from"].append(generated)
        catalog["generated_from"].sort(key=lambda item: (item["path"], item["record_kind"]))
        catalog["source_index_set_sha256"] = digest_payload(catalog["generated_from"])
        self.validate_document(catalog, expected_type="catalog")
        atomic_write(catalog_path, yaml_bytes(catalog))

    def lookup(self, query: str) -> list[dict[str, Any]]:
        catalog = self.read_tracked_catalog()
        value = query.strip()
        if not value:
            raise HubError("lookup query cannot be empty")
        matches: list[dict[str, Any]] = []
        identity: dict[str, str] | None = None
        if value.startswith(("http://", "https://")):
            identity = normalize_identity(value)
        lower = value.lower()
        for source in catalog["sources"]:
            matched = False
            if SHA256_RE.fullmatch(lower) and lower in source["media_sha256s"]:
                matched = True
            if value == source["source_key"] or any(
                value in {alias["source_key"], alias["platform_id"]}
                for alias in source["aliases"]
            ):
                matched = True
            if identity and any(
                alias["source_key"] == identity["source_key"]
                or alias["normalized_url"] == identity["normalized_url"]
                for alias in source["aliases"]
            ):
                matched = True
            if any(lower in title.lower() for title in source["titles"]):
                matched = True
            if any(
                lower in occurrence["reference_id"].lower()
                for occurrence in source["occurrences"]
            ):
                matched = True
            if matched:
                matches.append(source)
        return matches

    @staticmethod
    def _approval_matches(url: str, basis: str | None, approved_url: str | None) -> bool:
        if not basis or not basis.strip() or not approved_url:
            return False
        try:
            actual = normalize_identity(url)
            approved = normalize_identity(approved_url)
        except HubError:
            return False
        return bool(identity_keys(actual) & identity_keys(approved))

    def runtime_evidence(self, source: dict[str, Any]) -> dict[str, Any]:
        declared: set[str] = set()
        for occurrence in source["occurrences"]:
            paths = occurrence["declared_paths"]
            for group in ("media", "contact_sheets", "frame_indexes"):
                declared.update(item["path"] for item in paths[group])
        available: list[str] = []
        missing: list[str] = []
        for value in sorted(declared):
            path, rel = safe_repo_path(self.root, value)
            if path.is_file() and not path.is_symlink():
                available.append(rel)
            else:
                missing.append(rel)
        if not declared or not available:
            state = "registered_missing"
        elif missing:
            state = "registered_partial"
        else:
            state = "available"
        return {
            "state": state,
            "declared_path_count": len(declared),
            "available_path_count": len(available),
            "missing_path_count": len(missing),
            "available_paths": available,
            "missing_paths": missing,
        }

    def preflight(
        self,
        url: str,
        *,
        approval_basis: str | None = None,
        approved_url: str | None = None,
    ) -> dict[str, Any]:
        identity = normalize_identity(url)
        matches = self.lookup(url)
        if matches:
            source = matches[0]
            runtime_evidence = self.runtime_evidence(source)
            if runtime_evidence["state"] == "available":
                decision = "reuse_existing"
                workflow_eligible = True
                capture_eligible = False
            else:
                decision = "hold_registered_evidence_missing"
                workflow_eligible = False
                capture_eligible = False
            return {
                "decision": decision,
                "workflow_eligible": workflow_eligible,
                "capture_eligible": capture_eligible,
                "external_execution_approved": False,
                "identity": identity,
                "source": source,
                "runtime_evidence": runtime_evidence,
                "reason": (
                    "registered local media/contact-sheet evidence is reusable"
                    if workflow_eligible
                    else "identity is registered but no declared local media/contact-sheet/frame-index evidence exists; silent redownload is forbidden"
                ),
            }
        if identity["platform"] == "bilibili":
            approved = self._approval_matches(url, approval_basis, approved_url)
            return {
                "decision": (
                    "capture_new_public_bilibili_source"
                    if approved
                    else "hold_public_bilibili_requires_current_task_approval"
                ),
                "workflow_eligible": approved,
                "capture_eligible": approved,
                "external_execution_approved": False,
                "caller_supplied_approval_binding": approved,
                "current_task_approval_required": True,
                "identity": identity,
                "canonical_source_root": canonical_source_root(identity),
                "approval_basis": approval_basis if approved else None,
                "reason": (
                    "the caller supplied a current-task basis bound to this exact public Bilibili source; this preflight still performs and approves no download"
                    if approved
                    else "new public Bilibili acquisition fails closed until the caller supplies a current-task basis and matching exact approved URL"
                ),
            }
        approved = self._approval_matches(url, approval_basis, approved_url)
        return {
            "decision": (
                "capture_new_non_bilibili_exact_approval"
                if approved
                else "hold_non_bilibili_requires_exact_founder_approval"
            ),
            "workflow_eligible": approved,
            "capture_eligible": approved,
            "external_execution_approved": False,
            "caller_supplied_approval_binding": approved,
            "current_task_approval_required": True,
            "identity": identity,
            "canonical_source_root": canonical_source_root(identity),
            "approval_basis": approval_basis if approved else None,
            "reason": (
                "the supplied approval basis is bound to this exact normalized source"
                if approved
                else "new YouTube or other non-Bilibili acquisition fails closed without a task-specific basis and matching exact approved URL"
            ),
        }

    @staticmethod
    def _media_kind(path: Path) -> str:
        if path.suffix.lower() in {".aac", ".flac", ".m4a", ".mp3", ".ogg", ".wav"}:
            return "audio"
        if path.suffix.lower() in {".m4v", ".mkv", ".mov", ".mp4", ".webm"}:
            return "video"
        return "other_media"

    def _file_record(self, raw: str | Path, kind: str | None = None) -> dict[str, Any]:
        path, rel = safe_repo_path(
            self.root, raw, allow_absolute=True, require_file=True
        )
        return {
            "kind": kind or self._media_kind(path),
            "path": rel,
            "sha256": sha256_file(path),
            "byte_size": path.stat().st_size,
        }

    def _hardlink_record_into_lane(
        self, record: dict[str, Any], lane_rel: Path
    ) -> dict[str, Any]:
        source, source_rel = safe_repo_path(
            self.root, record["path"], require_file=True
        )
        lane_prefix = lane_rel.as_posix() + "/"
        if source_rel.startswith(lane_prefix):
            return record

        target = self.root / lane_rel / source.name
        if target.exists() and (
            not target.is_file()
            or target.stat().st_size != record["byte_size"]
            or sha256_file(target) != record["sha256"]
        ):
            target = self.root / lane_rel / f"{record['sha256'][:12]}-{source.name}"
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            try:
                os.link(source, target)
            except OSError as exc:
                raise HubError(
                    "historical evidence must be hardlinked into its canonical source lane without duplicating bytes"
                ) from exc
        if target.is_symlink() or not target.is_file():
            raise HubError("canonical historical evidence link is not a regular file")
        if target.stat().st_size != record["byte_size"] or sha256_file(target) != record["sha256"]:
            raise HubError("canonical historical evidence link changed byte identity")
        normalized = dict(record)
        normalized["path"] = target.absolute().relative_to(self.root.absolute()).as_posix()
        return normalized

    def _qc_sheet_manifest_evidence(
        self, raw: str | Path
    ) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
        manifest_path, manifest_rel = safe_repo_path(
            self.root, raw, allow_absolute=True, require_file=True
        )
        document = load_json(manifest_path)
        if document.get("schema_version") != "idol_video_qc_sheet_manifest.v1":
            raise HubError(
                "--contact-sheet-manifest must be idol_video_qc_sheet_manifest.v1"
            )

        source = document.get("source_video")
        if not isinstance(source, dict):
            raise HubError("QC sheet manifest source_video must be a mapping")
        source_path, source_rel = safe_repo_path(
            self.root,
            source.get("path", ""),
            allow_absolute=True,
            require_file=True,
        )
        source_sha = str(source.get("sha256", "")).lower()
        source_size = source.get("size_bytes")
        if not SHA256_RE.fullmatch(source_sha) or not isinstance(source_size, int) or source_size < 1:
            raise HubError("QC sheet manifest source_video hash/size evidence is invalid")
        if source_path.stat().st_size != source_size or sha256_file(source_path) != source_sha:
            raise HubError("QC sheet manifest source_video evidence is stale")
        video_field = document.get("video")
        if isinstance(video_field, str):
            _, video_rel = safe_repo_path(
                self.root, video_field, allow_absolute=True, require_file=True
            )
            if video_rel != source_rel:
                raise HubError("QC sheet manifest video and source_video paths disagree")

        records = document.get("sheets")
        if not isinstance(records, list) or not records:
            raise HubError("QC sheet manifest needs at least one ordered sheet record")
        if document.get("sheet_count") != len(records):
            raise HubError("QC sheet manifest sheet_count does not match sheets")
        manifest_set: set[tuple[str, str, int]] = set()
        ordered_evidence: list[dict[str, Any]] = []
        cell_ids: set[str] = set()
        for expected_part, record in enumerate(records, start=1):
            if not isinstance(record, dict) or record.get("part_index") != expected_part:
                raise HubError("QC sheet manifest part_index order must be contiguous from 1")
            sheet_path, sheet_rel = safe_repo_path(
                self.root,
                record.get("path", ""),
                allow_absolute=True,
                require_file=True,
            )
            sheet_sha = str(record.get("sha256", "")).lower()
            sheet_size = record.get("size_bytes")
            if not SHA256_RE.fullmatch(sheet_sha) or not isinstance(sheet_size, int) or sheet_size < 1:
                raise HubError("QC sheet manifest sheet hash/size evidence is invalid")
            if sheet_path.stat().st_size != sheet_size or sha256_file(sheet_path) != sheet_sha:
                raise HubError(f"QC sheet manifest sheet evidence is stale: {sheet_rel}")
            timestamps = record.get("timestamps")
            cells = record.get("cells")
            count = record.get("timestamp_count")
            if (
                not isinstance(timestamps, list)
                or not isinstance(cells, list)
                or not isinstance(count, int)
                or count < 1
                or count != len(timestamps)
                or count != len(cells)
            ):
                raise HubError("QC sheet manifest timestamps/cells/count are inconsistent")
            for expected_cell, cell in enumerate(cells, start=1):
                if not isinstance(cell, dict) or cell.get("order") != expected_cell:
                    raise HubError("QC sheet manifest cell order must be contiguous from 1")
                cell_id = cell.get("cell_id")
                if not isinstance(cell_id, str) or not cell_id or cell_id in cell_ids:
                    raise HubError("QC sheet manifest cell ids must be nonempty and globally unique")
                cell_ids.add(cell_id)
            key = (sheet_rel, sheet_sha, sheet_size)
            if key in manifest_set:
                raise HubError("QC sheet manifest repeats a sheet path/hash/size tuple")
            manifest_set.add(key)
            ordered_evidence.append(
                {
                    "path": sheet_rel,
                    "sha256": sheet_sha,
                    "byte_size": sheet_size,
                }
            )
        pointer = {
            "path": manifest_rel,
            "sha256": sha256_file(manifest_path),
            "byte_size": manifest_path.stat().st_size,
        }
        source_evidence = {
            "path": source_rel,
            "sha256": source_sha,
            "byte_size": source_size,
        }
        return pointer, source_evidence, ordered_evidence

    def _qc_sheet_manifest_pointer(
        self,
        raw: str | Path,
        *,
        media: list[dict[str, Any]],
        sheets: list[dict[str, Any]],
        canonical_root_rel: Path,
        historical_existing: bool,
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        pointer, source_evidence, ordered_evidence = self._qc_sheet_manifest_evidence(
            raw
        )
        if historical_existing:
            allowed_prefix = self.hub_root_rel.as_posix() + "/"
        else:
            allowed_prefix = canonical_root_rel.as_posix() + "/"
        if not pointer["path"].startswith(allowed_prefix):
            raise HubError(
                "contact-sheet manifest must stay inside the owning durable source root"
            )
        registered_videos = [item for item in media if item["kind"] == "video"]
        if not any(
            item["path"] == source_evidence["path"]
            and item["sha256"] == source_evidence["sha256"]
            and item["byte_size"] == source_evidence["byte_size"]
            for item in registered_videos
        ):
            raise HubError(
                "QC sheet manifest source_video does not match a registered video path/hash/size"
            )
        supplied = {
            (item["path"], item["sha256"], item["byte_size"]): item
            for item in sheets
        }
        if len(supplied) != len(sheets):
            raise HubError("duplicate --contact-sheet evidence is not allowed")
        manifest_set = {
            (item["path"], item["sha256"], item["byte_size"])
            for item in ordered_evidence
        }
        if manifest_set != set(supplied):
            raise HubError(
                "QC sheet manifest sheet path/hash/size set does not match --contact-sheet inputs"
            )
        ordered_sheets = []
        for expected_part, evidence in enumerate(ordered_evidence, start=1):
            supplied_record = supplied[
                (evidence["path"], evidence["sha256"], evidence["byte_size"])
            ]
            ordered_sheets.append(
                {
                    "sheet_id": f"SHEET_{expected_part:03d}",
                    **evidence,
                    "sampling_note": supplied_record.get("sampling_note"),
                }
            )
        return pointer, ordered_sheets

    def ingest_local(
        self,
        *,
        url: str,
        media_paths: list[str],
        contact_sheet_paths: list[str] | None = None,
        contact_sheet_manifest_path: str | None = None,
        replace_contact_sheets: bool = False,
        title: str | None = None,
        approval_basis: str | None = None,
        approved_url: str | None = None,
        historical_existing: bool = False,
        sampling_note: str | None = None,
        info_json_path: str | None = None,
        duration_seconds: float | None = None,
        view_count: int | None = None,
        discovery_lane: str | None = None,
    ) -> dict[str, Any]:
        identity = normalize_identity(url)
        canonical_root_rel = Path(canonical_source_root(identity))
        canonical_root = self.root / canonical_root_rel
        if not historical_existing and not self._approval_matches(
            url, approval_basis, approved_url
        ):
            source_kind = (
                "public Bilibili"
                if identity["platform"] == "bilibili"
                else "non-Bilibili"
            )
            raise HubError(
                f"new {source_kind} registration requires --approval-basis and an exact matching --approved-url"
            )
        media = [self._file_record(path) for path in media_paths]
        if not any(item["kind"] == "video" for item in media):
            raise HubError("local registration requires at least one video record")
        sheets_raw = contact_sheet_paths or []
        sheets = []
        for index, raw in enumerate(sheets_raw, start=1):
            record = self._file_record(raw, kind="other_media")
            sheets.append(
                {
                    "sheet_id": f"SHEET_{index:03d}",
                    "path": record["path"],
                    "sha256": record["sha256"],
                    "byte_size": record["byte_size"],
                    "sampling_note": sampling_note,
                }
            )
        discovery_metadata: dict[str, Any] | None = None
        if duration_seconds is not None or discovery_lane is not None or info_json_path is not None:
            if duration_seconds is None or discovery_lane is None:
                raise HubError(
                    "discovery metadata requires both --duration-seconds and --discovery-lane"
                )
            if isinstance(duration_seconds, bool) or not 0 < float(duration_seconds) <= 270:
                raise HubError("discovery metadata duration must be above zero and at most 270 seconds")
            duration_value = float(duration_seconds)
            expected_lane = "shorts_reference" if duration_value <= 60 else "music_reference"
            if discovery_lane != expected_lane:
                raise HubError(
                    f"discovery lane {discovery_lane!r} does not match duration {duration_value}"
                )
            if view_count is not None and (isinstance(view_count, bool) or view_count < 0):
                raise HubError("raw view count must be a nonnegative integer or omitted")
            metadata_pointer = None
            if info_json_path is not None:
                metadata_record = self._file_record(info_json_path, kind="other_media")
                if not metadata_record["path"].startswith(canonical_root_rel.as_posix() + "/"):
                    raise HubError("discovery metadata file must stay inside the canonical source root")
                metadata_pointer = {
                    "path": metadata_record["path"],
                    "sha256": metadata_record["sha256"],
                    "byte_size": metadata_record["byte_size"],
                }
            discovery_metadata = {
                "duration_seconds": duration_value,
                "discovery_lane": discovery_lane,
                "raw_view_count": view_count,
                "metadata_file": metadata_pointer,
                "ranking_policy": "relevance_and_diversity_then_raw_view_count_descending",
                "upload_age_normalization_applied": False,
            }
        if replace_contact_sheets and not sheets:
            raise HubError(
                "--replace-contact-sheets requires at least one --contact-sheet"
            )
        if replace_contact_sheets and contact_sheet_manifest_path is None:
            raise HubError(
                "--replace-contact-sheets requires --contact-sheet-manifest"
            )
        if not historical_existing:
            allowed_media_prefixes = tuple(
                (canonical_root_rel / lane).as_posix() + "/"
                for lane in ("videos", "audio", "raw")
            )
            for record in media:
                if not record["path"].startswith(allowed_media_prefixes):
                    raise HubError(
                        "new media must already be placed under its canonical source root in videos/, audio/, or raw/: "
                        + canonical_root_rel.as_posix()
                    )
            sheet_prefix = (canonical_root_rel / "contact-sheets").as_posix() + "/"
            for record in sheets:
                if not record["path"].startswith(sheet_prefix):
                    raise HubError(
                        "new contact sheets must already be placed under the canonical source contact-sheets/ lane"
                    )
        elif any(
            not record["path"].startswith(self.hub_root_rel.as_posix() + "/")
            for record in media + sheets
        ):
            raise HubError("historical existing-only registration must still point inside the durable video-source hub")

        if historical_existing:
            media = [
                self._hardlink_record_into_lane(
                    record,
                    canonical_root_rel
                    / ("audio" if record["kind"] == "audio" else "videos"),
                )
                for record in media
            ]
            sheets = [
                self._hardlink_record_into_lane(
                    record, canonical_root_rel / "contact-sheets"
                )
                for record in sheets
            ]

        manifest_path = canonical_root / "source-manifest.yaml"
        frame_index_path = canonical_root / "frame-index.yaml"
        if manifest_path.is_symlink() or frame_index_path.is_symlink():
            raise HubError("canonical manifest and frame-index paths cannot be symlinks")
        manifest_rel = manifest_path.absolute().relative_to(self.root.absolute()).as_posix()
        frame_rel = frame_index_path.absolute().relative_to(self.root.absolute()).as_posix()
        existing_contact_manifest: dict[str, Any] | None = None
        existing_discovery_metadata: dict[str, Any] | None = None
        if manifest_path.exists():
            existing = load_yaml(manifest_path)
            if replace_contact_sheets:
                if (
                    not isinstance(existing, dict)
                    or existing.get("schema_version") != SCHEMA_VERSION
                    or existing.get("artifact_type") != "source_manifest"
                    or existing.get("automation_boundaries") != boundaries()
                ):
                    raise HubError("existing source manifest envelope is invalid")
            else:
                self.validate_document(existing, expected_type="source_manifest")
            if existing["identity"]["source_key"] != identity["source_key"]:
                raise HubError("existing source manifest belongs to another identity")
            if isinstance(existing.get("discovery_metadata"), dict):
                existing_discovery_metadata = existing["discovery_metadata"]
            media = sorted(
                {item["path"]: item for item in existing["media"] + media}.values(),
                key=lambda item: item["path"],
            )
            if replace_contact_sheets:
                sheets = sorted(sheets, key=lambda item: item["path"])
            else:
                sheets = sorted(
                    {item["path"]: item for item in existing["contact_sheets"] + sheets}.values(),
                    key=lambda item: item["path"],
                )
            for index, sheet in enumerate(sheets, start=1):
                sheet["sheet_id"] = f"SHEET_{index:03d}"
            if frame_index_path.is_file():
                existing_frame_index = load_yaml(frame_index_path)
                if replace_contact_sheets:
                    if (
                        not isinstance(existing_frame_index, dict)
                        or existing_frame_index.get("schema_version") != SCHEMA_VERSION
                        or existing_frame_index.get("artifact_type") != "frame_index"
                        or existing_frame_index.get("automation_boundaries") != boundaries()
                    ):
                        raise HubError("existing frame index envelope is invalid")
                else:
                    self.validate_document(existing_frame_index, expected_type="frame_index")
                if existing_frame_index["source_key"] != identity["source_key"]:
                    raise HubError("existing frame index belongs to another identity")
                if existing_frame_index["source_manifest_path"] != manifest_rel:
                    raise HubError("existing frame index points to another source manifest")
                if not replace_contact_sheets:
                    existing_contact_manifest = existing_frame_index.get(
                        "contact_sheet_manifest"
                    )

        if discovery_metadata is None:
            discovery_metadata = existing_discovery_metadata

        contact_manifest_pointer: dict[str, Any] | None = None
        pointer_input = contact_sheet_manifest_path
        if pointer_input is None and existing_contact_manifest is not None:
            pointer_input = existing_contact_manifest["path"]
        if pointer_input is not None:
            contact_manifest_pointer, sheets = self._qc_sheet_manifest_pointer(
                pointer_input,
                media=media,
                sheets=sheets,
                canonical_root_rel=canonical_root_rel,
                historical_existing=historical_existing,
            )
            if (
                contact_sheet_manifest_path is None
                and existing_contact_manifest is not None
                and contact_manifest_pointer != existing_contact_manifest
            ):
                raise HubError("existing contact-sheet manifest pointer is stale")

        if not sheets:
            raise HubError(
                "local registration requires at least one reusable contact sheet"
            )
        if not historical_existing and contact_manifest_pointer is None:
            raise HubError(
                "new capture registration requires a hash-bound QC contact-sheet manifest"
            )

        if historical_existing:
            approval = {
                "mode": "historical_existing_only",
                "basis": approval_basis,
                "approved_url": approved_url,
            }
        elif identity["platform"] == "bilibili":
            approval = {
                "mode": "public_bilibili_current_task",
                "basis": approval_basis,
                "approved_url": normalize_identity(approved_url)["normalized_url"] if approved_url else None,
            }
        else:
            approval = {
                "mode": "exact_non_bilibili_approval",
                "basis": approval_basis,
                "approved_url": normalize_identity(approved_url)["normalized_url"] if approved_url else None,
            }
        if sheets:
            frame_index = {
                "schema_version": SCHEMA_VERSION,
                "artifact_type": "frame_index",
                "source_key": identity["source_key"],
                "source_manifest_path": manifest_rel,
                "contact_sheet_manifest": contact_manifest_pointer,
                "sheets": sheets,
                "frame_index_set_sha256": digest_payload(
                    {
                        "contact_sheet_manifest": contact_manifest_pointer,
                        "sheets": [
                            {"path": sheet["path"], "sha256": sheet["sha256"]}
                            for sheet in sheets
                        ],
                    }
                ),
                "automation_boundaries": boundaries(),
            }
            self.validate_document(frame_index, expected_type="frame_index")
            atomic_write(frame_index_path, yaml_bytes(frame_index))
            frame_pointer: str | None = frame_rel
        else:
            frame_pointer = None
        manifest = {
            "schema_version": SCHEMA_VERSION,
            "artifact_type": "source_manifest",
            "identity": identity,
            "title": title.strip() if title and title.strip() else None,
            "canonical_source_root": canonical_root_rel.as_posix(),
            "approval_basis": approval,
            "media": media,
            "contact_sheets": sheets,
            "frame_index_path": frame_pointer,
            "evidence_status": "registered_local_evidence",
            "automation_boundaries": boundaries(),
        }
        if discovery_metadata is not None:
            manifest["discovery_metadata"] = discovery_metadata
        self.validate_document(manifest, expected_type="source_manifest")
        atomic_write(manifest_path, yaml_bytes(manifest))
        self.upsert_catalog_source(manifest_rel)
        return {
            "decision": "registered_historical_existing" if historical_existing else "registered_local",
            "source_manifest_path": manifest_rel,
            "frame_index_path": frame_pointer,
            "contact_sheet_manifest": contact_manifest_pointer,
            "catalog_path": Path(self.catalog_rel).as_posix(),
            "source_key": identity["source_key"],
            "media_sha256s": sorted(item["sha256"] for item in media),
            "discovery_metadata": discovery_metadata,
        }

    def validate_document(
        self, document: dict[str, Any], *, expected_type: str | None = None
    ) -> None:
        if document.get("schema_version") != SCHEMA_VERSION:
            raise HubError("unexpected downloaded-reference-hub schema_version")
        artifact_type = document.get("artifact_type")
        if expected_type and artifact_type != expected_type:
            raise HubError(f"expected {expected_type}, got {artifact_type!r}")
        if artifact_type not in {"catalog", "source_manifest", "frame_index"}:
            raise HubError(f"unknown downloaded-reference-hub artifact_type: {artifact_type!r}")
        if document.get("automation_boundaries") != boundaries():
            raise HubError("automation boundaries must remain all-false and network-free")
        if artifact_type == "catalog":
            self._validate_catalog(document)
        elif artifact_type == "source_manifest":
            self._validate_manifest(document)
        else:
            self._validate_frame_index(document)

    def _validate_identity(self, identity: Any) -> None:
        if not isinstance(identity, dict):
            raise HubError("identity must be a mapping")
        expected = normalize_identity(
            identity.get("normalized_url"),
            explicit_platform=identity.get("platform"),
            explicit_id=identity.get("platform_id"),
        )
        if identity != expected:
            raise HubError(f"identity is not normalized: {identity!r}")

    def _validate_catalog(self, document: dict[str, Any]) -> None:
        if document.get("hub_root") != self.hub_root_rel.as_posix():
            raise HubError("catalog hub_root does not match this hub")
        generated = document.get("generated_from")
        if not isinstance(generated, list) or digest_payload(generated) != document.get("source_index_set_sha256"):
            raise HubError("catalog source-index-set digest is invalid")
        source_keys: set[str] = set()
        alias_keys: set[str] = set()
        media_hashes: set[str] = set()
        sources = document.get("sources")
        if not isinstance(sources, list):
            raise HubError("catalog sources must be a list")
        for source in sources:
            key = source.get("source_key")
            if key in source_keys:
                raise HubError(f"duplicate catalog source_key: {key}")
            source_keys.add(key)
            self._validate_identity(source.get("canonical_identity"))
            for alias in source.get("aliases", []):
                self._validate_identity(alias)
                for alias_key in identity_keys(alias):
                    if alias_key in alias_keys:
                        raise HubError(f"identity alias appears in more than one source group: {alias_key}")
                    alias_keys.add(alias_key)
            for value in source.get("media_sha256s", []):
                if not SHA256_RE.fullmatch(value):
                    raise HubError(f"invalid media SHA-256: {value}")
                if value in media_hashes:
                    raise HubError(f"media SHA-256 appears in more than one source group: {value}")
                media_hashes.add(value)
            _, root_rel = safe_repo_path(self.root, source.get("canonical_source_root", ""))
            if not root_rel.startswith(self.hub_root_rel.as_posix() + "/"):
                raise HubError("catalog canonical source root escapes hub")
            if source.get("discovery_metadata") is not None:
                self._validate_discovery_metadata(
                    source["discovery_metadata"], expected_root=root_rel
                )

    def _validate_discovery_metadata(
        self, value: Any, *, expected_root: str
    ) -> None:
        if not isinstance(value, dict):
            raise HubError("discovery metadata must be a mapping")
        duration = value.get("duration_seconds")
        if isinstance(duration, bool) or not isinstance(duration, (int, float)):
            raise HubError("discovery metadata duration must be numeric")
        if not 0 < float(duration) <= 270:
            raise HubError("discovery metadata duration must be above zero and at most 270 seconds")
        expected_lane = "shorts_reference" if float(duration) <= 60 else "music_reference"
        if value.get("discovery_lane") != expected_lane:
            raise HubError("discovery metadata lane does not match duration")
        raw_view_count = value.get("raw_view_count")
        if raw_view_count is not None and (
            isinstance(raw_view_count, bool)
            or not isinstance(raw_view_count, int)
            or raw_view_count < 0
        ):
            raise HubError("discovery metadata raw_view_count must be nonnegative or null")
        if value.get("ranking_policy") != "relevance_and_diversity_then_raw_view_count_descending":
            raise HubError("discovery metadata ranking policy is invalid")
        if value.get("upload_age_normalization_applied") is not False:
            raise HubError("discovery metadata must not normalize by upload age")
        pointer = value.get("metadata_file")
        if pointer is None:
            return
        if not isinstance(pointer, dict):
            raise HubError("discovery metadata_file must be a pointer or null")
        path, path_rel = safe_repo_path(self.root, pointer.get("path", ""))
        if not path_rel.startswith(expected_root + "/"):
            raise HubError("discovery metadata file escapes its canonical source root")
        sha = str(pointer.get("sha256", ""))
        byte_size = pointer.get("byte_size")
        if not SHA256_RE.fullmatch(sha) or not isinstance(byte_size, int) or byte_size < 1:
            raise HubError("discovery metadata file pointer is invalid")
        if path.is_file():
            if path.stat().st_size != byte_size or sha256_file(path) != sha:
                raise HubError("discovery metadata file pointer is stale")

    def _validate_manifest(self, document: dict[str, Any]) -> None:
        identity = document.get("identity")
        self._validate_identity(identity)
        expected_root = canonical_source_root(identity)
        if document.get("canonical_source_root") != expected_root:
            raise HubError("source manifest canonical_source_root does not match identity")
        if document.get("discovery_metadata") is not None:
            self._validate_discovery_metadata(
                document["discovery_metadata"], expected_root=expected_root
            )
        approval = document.get("approval_basis")
        if not isinstance(approval, dict) or approval.get("mode") not in {
            "public_bilibili_current_task",
            "exact_non_bilibili_approval",
            "historical_existing_only",
        }:
            raise HubError("source manifest approval basis is invalid")
        approval_mode = approval["mode"]
        if approval_mode == "public_bilibili_current_task":
            if identity["platform"] != "bilibili":
                raise HubError("public-Bilibili approval mode requires a Bilibili identity")
            if not self._approval_matches(
                identity["normalized_url"],
                approval.get("basis"),
                approval.get("approved_url"),
            ):
                raise HubError(
                    "public-Bilibili approval mode requires a current-task basis bound to the exact URL"
                )
        elif approval_mode == "exact_non_bilibili_approval":
            if identity["platform"] == "bilibili":
                raise HubError("non-Bilibili approval mode cannot own a Bilibili identity")
            if not self._approval_matches(
                identity["normalized_url"],
                approval.get("basis"),
                approval.get("approved_url"),
            ):
                raise HubError(
                    "non-Bilibili approval mode requires a basis bound to the exact URL"
                )
        media = document.get("media")
        if not isinstance(media, list) or not media:
            raise HubError("source manifest needs at least one local media record")
        for item in media:
            path, media_rel = safe_repo_path(self.root, item.get("path", ""), allow_absolute=False)
            if not media_rel.startswith(expected_root + "/"):
                raise HubError("source manifest media path escapes its canonical source root")
            if not SHA256_RE.fullmatch(str(item.get("sha256", ""))):
                raise HubError("source manifest media hash is invalid")
            if int(item.get("byte_size", 0)) < 1:
                raise HubError("source manifest media byte_size is invalid")
            if path.exists() and path.is_symlink():
                raise HubError("source manifest media cannot be a symlink")
            if path.is_file():
                if path.stat().st_size != item["byte_size"]:
                    raise HubError(f"source manifest media size is stale: {item['path']}")
                if sha256_file(path) != item["sha256"]:
                    raise HubError(f"source manifest media hash is stale: {item['path']}")
        if not any(item.get("kind") == "video" for item in media):
            raise HubError("source manifest needs at least one video record")
        sheets = document.get("contact_sheets")
        if not isinstance(sheets, list) or not sheets:
            raise HubError("source manifest needs at least one reusable contact sheet")
        for sheet in sheets:
            path, sheet_rel = safe_repo_path(self.root, sheet.get("path", ""))
            if not sheet_rel.startswith(expected_root + "/contact-sheets/"):
                raise HubError("source manifest contact-sheet path escapes its canonical source root")
            value = str(sheet.get("sha256", ""))
            if not SHA256_RE.fullmatch(value) or int(sheet.get("byte_size", 0)) < 1:
                raise HubError("source manifest contact-sheet evidence is invalid")
            if path.is_file():
                if path.stat().st_size != sheet["byte_size"]:
                    raise HubError(f"source manifest contact-sheet size is stale: {sheet['path']}")
                if sha256_file(path) != value:
                    raise HubError(f"source manifest contact-sheet hash is stale: {sheet['path']}")
        frame_pointer = document.get("frame_index_path")
        if not isinstance(frame_pointer, str) or not frame_pointer:
            raise HubError("source manifest requires a frame-index pointer")
        _, frame_rel = safe_repo_path(self.root, frame_pointer)
        if frame_rel != expected_root + "/frame-index.yaml":
            raise HubError("source manifest frame-index pointer escapes its canonical source root")

    def _validate_frame_index(self, document: dict[str, Any]) -> None:
        source_key = str(document.get("source_key", ""))
        if ":" not in source_key:
            raise HubError("frame index source_key is invalid")
        platform, platform_id = source_key.split(":", 1)
        expected_root = (
            DEFAULT_HUB_ROOT
            / _platform_slug(platform)
            / "by-source"
            / _path_id(platform_id)
        ).as_posix()
        sheets = document.get("sheets")
        if not isinstance(sheets, list) or not sheets:
            raise HubError("frame index needs at least one contact sheet")
        pointer = document.get("contact_sheet_manifest")
        qc_sheet_evidence: list[dict[str, Any]] | None = None
        if pointer is not None:
            if not isinstance(pointer, dict):
                raise HubError("frame-index contact_sheet_manifest must be a pointer or null")
            _, pointer_rel = safe_repo_path(self.root, pointer.get("path", ""))
            if not pointer_rel.startswith(expected_root + "/"):
                raise HubError("frame-index contact-sheet manifest escapes its canonical source root")
            current_pointer, _, qc_sheet_evidence = self._qc_sheet_manifest_evidence(
                pointer.get("path", "")
            )
            if current_pointer != pointer:
                raise HubError("frame-index contact-sheet manifest pointer is stale")
        digest_rows = []
        for sheet in sheets:
            path, sheet_rel = safe_repo_path(self.root, sheet.get("path", ""))
            if not sheet_rel.startswith(expected_root + "/contact-sheets/"):
                raise HubError("frame-index sheet path escapes its canonical source root")
            value = str(sheet.get("sha256", ""))
            if not SHA256_RE.fullmatch(value):
                raise HubError("frame-index sheet hash is invalid")
            if int(sheet.get("byte_size", 0)) < 1:
                raise HubError("frame-index sheet byte_size is invalid")
            if path.is_file():
                if path.stat().st_size != sheet["byte_size"]:
                    raise HubError(f"frame-index sheet size is stale: {sheet['path']}")
                if sha256_file(path) != value:
                    raise HubError(f"frame-index sheet hash is stale: {sheet['path']}")
            digest_rows.append({"path": sheet["path"], "sha256": value})
        if qc_sheet_evidence is not None:
            frame_evidence = [
                {
                    "path": sheet["path"],
                    "sha256": sheet["sha256"],
                    "byte_size": sheet["byte_size"],
                }
                for sheet in sheets
            ]
            if frame_evidence != qc_sheet_evidence:
                raise HubError(
                    "frame-index sheet order/evidence does not match its QC sheet manifest"
                )
        digest_input = {
            "contact_sheet_manifest": pointer,
            "sheets": digest_rows,
        }
        digest_matches = digest_payload(digest_input) == document.get(
            "frame_index_set_sha256"
        )
        legacy_null_pointer_digest_matches = (
            "contact_sheet_manifest" not in document
            and digest_payload(digest_rows) == document.get("frame_index_set_sha256")
        )
        if not digest_matches and not legacy_null_pointer_digest_matches:
            raise HubError("frame-index set digest is invalid")
        _, manifest_rel = safe_repo_path(self.root, document.get("source_manifest_path", ""))
        if manifest_rel != expected_root + "/source-manifest.yaml":
            raise HubError("frame-index source-manifest pointer escapes its canonical source root")

    def verify(self) -> dict[str, Any]:
        catalog_path, _ = safe_repo_path(self.root, self.catalog_rel)
        issues: list[str] = []
        holds: list[str] = []
        if not catalog_path.is_file():
            issues.append(f"missing catalog: {Path(self.catalog_rel).as_posix()}")
            return {"valid": False, "issues": issues, "holds": holds}
        try:
            current = load_yaml(catalog_path)
            self.validate_document(current, expected_type="catalog")
            fresh = self.build_catalog()
            if yaml_bytes(current) != yaml_bytes(fresh):
                issues.append("catalog is stale; run build")
            for source in fresh["sources"]:
                if self.runtime_evidence(source)["state"] != "available":
                    holds.append(source["source_key"])
        except HubError as exc:
            issues.append(str(exc))
        return {
            "valid": not issues,
            "issues": issues,
            "holds": sorted(holds),
            "catalog_path": Path(self.catalog_rel).as_posix(),
        }


def _print_json(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Network-free downloaded-reference hub registry and preflight"
    )
    parser.add_argument(
        "--repo-root", default=str(Path(__file__).resolve().parents[1]), help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--hub-root", default=DEFAULT_HUB_ROOT.as_posix(), help=argparse.SUPPRESS
    )
    parser.add_argument("--catalog", default=None, help="repo-relative catalog path")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build", help="rebuild the deterministic pointer catalog")
    build.add_argument("--check", action="store_true", help="fail if catalog bytes are stale")
    build.add_argument("--json", action="store_true", help="print the complete catalog as JSON")

    subparsers.add_parser("verify", help="validate the tracked catalog against current indexes")

    lookup = subparsers.add_parser("lookup", help="lookup by URL, source key, SHA-256, title, or reference id")
    lookup.add_argument("query")

    preflight = subparsers.add_parser("preflight", help="decide reuse, hold, or acquisition eligibility")
    preflight.add_argument("url")
    preflight.add_argument("--approval-basis")
    preflight.add_argument("--approved-url")

    ingest = subparsers.add_parser(
        "ingest-local",
        aliases=["register"],
        help="register already-local canonical media without copying or downloading it",
    )
    ingest.add_argument("--url", required=True)
    ingest.add_argument("--media", action="append", required=True)
    ingest.add_argument("--contact-sheet", action="append", default=[])
    ingest.add_argument(
        "--contact-sheet-manifest",
        help="idol_video_qc_sheet_manifest.v1 JSON whose ordered cells own the supplied contact sheets",
    )
    ingest.add_argument(
        "--replace-contact-sheets",
        action="store_true",
        help="replace an existing source's canonical contact-sheet set with this hash-bound manifest set",
    )
    ingest.add_argument("--title")
    ingest.add_argument("--approval-basis")
    ingest.add_argument("--approved-url")
    ingest.add_argument("--historical-existing", action="store_true")
    ingest.add_argument("--sampling-note")
    ingest.add_argument(
        "--info-json",
        help="optional local yt-dlp info JSON or equivalent metadata evidence inside the canonical source root",
    )
    ingest.add_argument("--duration-seconds", type=float)
    ingest.add_argument("--view-count", type=int)
    ingest.add_argument(
        "--discovery-lane",
        choices=["shorts_reference", "music_reference"],
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.repo_root)
    catalog_rel = Path(args.catalog) if args.catalog else None
    try:
        hub = ReferenceHub(root, Path(args.hub_root), catalog_rel)
        if args.command == "build":
            matched, document = hub.write_catalog(check=args.check)
            if args.json:
                _print_json(document)
            else:
                _print_json(
                    {
                        "catalog_path": document["catalog_path"],
                        "source_count": len(document["sources"]),
                        "source_index_set_sha256": document["source_index_set_sha256"],
                        "status": "current" if matched else ("stale" if args.check else "updated"),
                    }
                )
            return 0 if matched or not args.check else 1
        if args.command == "verify":
            result = hub.verify()
            _print_json(result)
            return 0 if result["valid"] else 1
        if args.command == "lookup":
            matches = hub.lookup(args.query)
            _print_json({"query": args.query, "match_count": len(matches), "matches": matches})
            return 0 if matches else 1
        if args.command == "preflight":
            result = hub.preflight(
                args.url,
                approval_basis=args.approval_basis,
                approved_url=args.approved_url,
            )
            _print_json(result)
            return 0 if result["workflow_eligible"] else 3
        result = hub.ingest_local(
            url=args.url,
            media_paths=args.media,
            contact_sheet_paths=args.contact_sheet,
            contact_sheet_manifest_path=args.contact_sheet_manifest,
            replace_contact_sheets=args.replace_contact_sheets,
            title=args.title,
            approval_basis=args.approval_basis,
            approved_url=args.approved_url,
            historical_existing=args.historical_existing,
            sampling_note=args.sampling_note,
            info_json_path=args.info_json,
            duration_seconds=args.duration_seconds,
            view_count=args.view_count,
            discovery_lane=args.discovery_lane,
        )
        _print_json(result)
        return 0
    except HubError as exc:
        _print_json({"error": str(exc), "status": "hold"})
        return 2


if __name__ == "__main__":
    sys.exit(main())
