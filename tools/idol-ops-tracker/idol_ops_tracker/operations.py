from __future__ import annotations

import copy
import threading
from collections import Counter
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

from .paths import IDOL_REPO_ROOT


MV_DEADLINE_DAYS = 7
CF_DEADLINE_DAYS = 3
_TERMINAL_RUN_STATES = {"closed", "discarded"}
_CURRENT_RUN_STATES = {"active", "hold"}
_WORKER_STATES = (
    "prepared",
    "launched",
    "returned",
    "reviewed",
    "promoted",
    "hold",
    "retired",
    "replaced",
    "unknown",
)
_MAX_OPERATION_YAML_BYTES = 2_000_000
_cache_lock = threading.Lock()
_worker_cache: dict[str, tuple[tuple[tuple[str, int, int], ...], dict[str, Any]]] = {}


def _as_datetime(value: Any, fallback_timezone: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, date):
        parsed = datetime.combine(value, time.min)
    elif isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=fallback_timezone or timezone.utc)
    return parsed.astimezone()


def _iso(value: datetime | None) -> str | None:
    return value.isoformat(timespec="seconds") if value else None


def _directory_birthtime(path: Path, now: datetime) -> tuple[datetime | None, str]:
    try:
        stat = path.stat()
    except OSError:
        return None, "unavailable"
    birthtime = getattr(stat, "st_birthtime", None)
    if birthtime is not None:
        return datetime.fromtimestamp(birthtime, tz=timezone.utc).astimezone(now.tzinfo), "filesystem_birthtime"
    return datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).astimezone(now.tzinfo), "mtime_fallback"


def _deadline(created_at: datetime | None, days: int, now: datetime) -> dict[str, Any]:
    if created_at is None:
        return {
            "days": days,
            "at": None,
            "state": "unknown",
            "day_label": "기한 미확인",
            "remaining_seconds": None,
        }
    due = created_at + timedelta(days=days)
    remaining = int((due - now).total_seconds())
    calendar_delta = (due.astimezone(now.tzinfo).date() - now.date()).days
    if calendar_delta > 0:
        day_label = f"D-{calendar_delta}"
    elif calendar_delta == 0:
        day_label = "D-DAY"
    else:
        day_label = f"D+{abs(calendar_delta)}"
    if remaining < 0:
        state = "overdue"
    elif remaining <= 24 * 60 * 60:
        state = "due_soon"
    else:
        state = "on_track"
    return {
        "days": days,
        "at": _iso(due),
        "state": state,
        "day_label": day_label,
        "remaining_seconds": remaining,
    }


def _is_within_repo(path: Path, repo_root: Path) -> bool:
    try:
        path.resolve().relative_to(repo_root.resolve())
    except (OSError, ValueError):
        return False
    return True


def _load_yaml(path: Path) -> dict[str, Any]:
    if path.stat().st_size > _MAX_OPERATION_YAML_BYTES:
        raise ValueError("operation YAML exceeds the 2 MB read limit")
    payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("YAML root is not an object")
    return payload


def _nested(payload: dict[str, Any], *keys: str) -> Any:
    current: Any = payload
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if isinstance(item, (str, int))]


def _repo_relative(path: Path, repo_root: Path) -> str:
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def _event_time(events: Any, state: str, now: datetime) -> datetime | None:
    if not isinstance(events, list):
        return None
    found: datetime | None = None
    for event in events:
        if isinstance(event, dict) and event.get("state") == state:
            parsed = _as_datetime(event.get("at"), now.tzinfo)
            if parsed and (found is None or parsed > found):
                found = parsed
    return found


def _latest_event_time(events: Any, now: datetime) -> datetime | None:
    if not isinstance(events, list):
        return None
    parsed = [
        _as_datetime(event.get("at"), now.tzinfo)
        for event in events
        if isinstance(event, dict)
    ]
    usable = [item for item in parsed if item]
    return max(usable) if usable else None


def _review_label(value: Any) -> str:
    if not isinstance(value, dict):
        return "not_reviewed"
    return str(value.get("disposition") or value.get("status") or value.get("state") or "recorded")


def _promotion_label(value: Any) -> str:
    if not isinstance(value, dict):
        return "not_started"
    return str(value.get("state") or value.get("disposition") or value.get("status") or "recorded")


def _output_state(paths: list[str], repo_root: Path) -> dict[str, int]:
    existing = 0
    for relative_path in paths:
        candidate = (repo_root / relative_path).resolve()
        try:
            candidate.relative_to(repo_root.resolve())
        except ValueError:
            continue
        if candidate.is_file():
            existing += 1
    return {"declared": len(paths), "existing": existing}


def _worker_attention(state: str, last_event: datetime | None, now: datetime) -> tuple[bool, str | None, int]:
    if state == "hold":
        return True, "HOLD — Director/Founder 판단 필요", 0
    if state == "returned":
        return True, "반환됨 — recipient Director 검토 대기", 1
    if state == "reviewed":
        return True, "검토됨 — Overall promotion 대기", 2
    if state == "prepared":
        return True, "준비됨 — launch 여부 확인 필요", 3
    if state == "launched" and last_event:
        elapsed_hours = (now - last_event).total_seconds() / 3600
        if elapsed_hours >= 24:
            return True, "최근 lifecycle 갱신 24h+ — 실제 실행 여부 미확인", 4
    return False, None, 9


def _worker_from_dispatch(payload: dict[str, Any], path: Path, repo_root: Path, now: datetime) -> dict[str, Any]:
    lineage = payload.get("lineage") if isinstance(payload.get("lineage"), dict) else {}
    lifecycle = payload.get("lifecycle") if isinstance(payload.get("lifecycle"), dict) else {}
    launch = payload.get("launch") if isinstance(payload.get("launch"), dict) else {}
    task = launch.get("task") if isinstance(launch.get("task"), dict) else {}
    scope = task.get("exact_scope") if isinstance(task.get("exact_scope"), dict) else {}
    recipient = payload.get("recipient") if isinstance(payload.get("recipient"), dict) else {}
    events = lifecycle.get("events")
    state = str(lifecycle.get("current_state") or "unknown")
    if state not in _WORKER_STATES:
        state = "unknown"
    launched_at = _as_datetime(launch.get("launched_at"), now.tzinfo) or _event_time(events, "launched", now)
    returned_at = _event_time(events, "returned", now)
    reviewed_at = _event_time(events, "reviewed", now)
    closed_at = _event_time(events, "promoted", now) or _event_time(events, "hold", now)
    last_event = _latest_event_time(events, now) or launched_at or _as_datetime(launch.get("prepared_at"), now.tzinfo)
    attention, attention_reason, urgency_rank = _worker_attention(state, last_event, now)
    artifact_paths = _string_list(scope.get("artifact_paths"))
    profile = _nested(launch, "compiled_launch_prompt", "selected_profile", "model_or_role_profile")
    return {
        "dispatch_id": str(payload.get("dispatch_id") or path.stem),
        "dispatch_path": _repo_relative(path, repo_root),
        "schema_version": str(payload.get("schema_version") or "unknown"),
        "lineage_id": str(lineage.get("lineage_id") or payload.get("dispatch_id") or path.stem),
        "attempt_id": str(lineage.get("attempt_id") or payload.get("dispatch_id") or path.stem),
        "attempt_number": int(lineage.get("attempt_number") or 1),
        "previous_attempt_id": lineage.get("previous_attempt_id"),
        "successor_attempt_id": lineage.get("successor_attempt_id"),
        "lineage_state": str(lineage.get("lineage_state") or "active"),
        "provider": str(lineage.get("provider") or "unknown"),
        "runtime_surface": str(lineage.get("runtime_surface") or "unknown"),
        "session_id": lineage.get("session_id"),
        "role": str(task.get("role") or "worker"),
        "model_profile": str(profile) if profile else None,
        "stage_id": str(scope.get("stage_id") or "unknown"),
        "section_ids": _string_list(scope.get("section_ids")),
        "interaction_surface": str(launch.get("interaction_surface") or payload.get("interaction_surface") or "unknown"),
        "recipient_owner": str(recipient.get("owner") or "unknown"),
        "recipient_role": str(recipient.get("role") or "unknown"),
        "execution_state": state,
        "review_state": _review_label(payload.get("director_review")),
        "promotion_state": _promotion_label(payload.get("promotion")),
        "prepared_at": _iso(_as_datetime(launch.get("prepared_at"), now.tzinfo)),
        "launched_at": _iso(launched_at),
        "returned_at": _iso(returned_at),
        "reviewed_at": _iso(reviewed_at),
        "closed_at": _iso(closed_at),
        "last_event_at": _iso(last_event),
        "elapsed_hours": round((now - last_event).total_seconds() / 3600, 1) if last_event else None,
        "outputs": _output_state(artifact_paths, repo_root),
        "attention": attention,
        "attention_reason": attention_reason,
        "urgency_rank": urgency_rank,
        "activity_verified": False,
    }


def _worker_from_index(row: dict[str, Any], repo_root: Path, now: datetime) -> dict[str, Any]:
    attempt = row.get("attempt") if isinstance(row.get("attempt"), dict) else {}
    task = row.get("task") if isinstance(row.get("task"), dict) else {}
    scope = row.get("scope") if isinstance(row.get("scope"), dict) else {}
    lifecycle = row.get("lifecycle") if isinstance(row.get("lifecycle"), dict) else {}
    state = str(lifecycle.get("current_state") or "unknown")
    if state not in _WORKER_STATES:
        state = "unknown"
    last_event = next(
        (
            parsed
            for parsed in (
                _as_datetime(lifecycle.get("closed_at"), now.tzinfo),
                _as_datetime(lifecycle.get("reviewed_at"), now.tzinfo),
                _as_datetime(lifecycle.get("returned_at"), now.tzinfo),
                _as_datetime(lifecycle.get("launched_at"), now.tzinfo),
                _as_datetime(lifecycle.get("prepared_at"), now.tzinfo),
            )
            if parsed
        ),
        None,
    )
    attention, attention_reason, urgency_rank = _worker_attention(state, last_event, now)
    dispatch_pointer = row.get("dispatch_pointer") if isinstance(row.get("dispatch_pointer"), dict) else {}
    artifact_paths = _string_list(scope.get("artifact_paths"))
    return {
        "dispatch_id": str(row.get("dispatch_id") or "unknown"),
        "dispatch_path": str(dispatch_pointer.get("path") or "unknown"),
        "schema_version": "idol-director-dispatch-index.v2/row",
        "lineage_id": str(attempt.get("lineage_id") or row.get("dispatch_id") or "unknown"),
        "attempt_id": str(attempt.get("attempt_id") or row.get("dispatch_id") or "unknown"),
        "attempt_number": int(attempt.get("attempt_no") or 1),
        "previous_attempt_id": attempt.get("previous_attempt_id"),
        "successor_attempt_id": attempt.get("successor_dispatch_id"),
        "lineage_state": str(attempt.get("session_state") or "active"),
        "provider": str(attempt.get("provider") or "unknown"),
        "runtime_surface": str(attempt.get("runtime_surface") or "unknown"),
        "session_id": attempt.get("session_id"),
        "role": str(task.get("logical_role") or "worker"),
        "model_profile": None,
        "stage_id": str(scope.get("stage_id") or "unknown"),
        "section_ids": _string_list(scope.get("section_ids")),
        "interaction_surface": str(scope.get("interaction_surface") or "unknown"),
        "recipient_owner": str(task.get("return_recipient") or "unknown"),
        "recipient_role": "director",
        "execution_state": state,
        "review_state": _review_label(row.get("review")),
        "promotion_state": _promotion_label(row.get("promotion")),
        "prepared_at": _iso(_as_datetime(lifecycle.get("prepared_at"), now.tzinfo)),
        "launched_at": _iso(_as_datetime(lifecycle.get("launched_at"), now.tzinfo)),
        "returned_at": _iso(_as_datetime(lifecycle.get("returned_at"), now.tzinfo)),
        "reviewed_at": _iso(_as_datetime(lifecycle.get("reviewed_at"), now.tzinfo)),
        "closed_at": _iso(_as_datetime(lifecycle.get("closed_at"), now.tzinfo)),
        "last_event_at": _iso(last_event),
        "elapsed_hours": round((now - last_event).total_seconds() / 3600, 1) if last_event else None,
        "outputs": _output_state(artifact_paths, repo_root),
        "attention": attention,
        "attention_reason": attention_reason,
        "urgency_rank": urgency_rank,
        "activity_verified": attempt.get("session_state") in {"active", "resumed"},
    }


def _fingerprint(paths: list[Path]) -> tuple[tuple[str, int, int], ...]:
    values: list[tuple[str, int, int]] = []
    for path in paths:
        try:
            stat = path.stat()
        except OSError:
            continue
        values.append((str(path), stat.st_size, stat.st_mtime_ns))
    return tuple(values)


def _select_worker_heads(rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], int]:
    lineage_heads: dict[str, dict[str, Any]] = {}
    for row in rows:
        lineage_id = row["lineage_id"]
        current = lineage_heads.get(lineage_id)
        candidate_key = (row.get("attempt_number", 1), row.get("last_event_at") or "", row["dispatch_id"])
        current_key = (
            current.get("attempt_number", 1),
            current.get("last_event_at") or "",
            current["dispatch_id"],
        ) if current else None
        if current is None or candidate_key > current_key:
            lineage_heads[lineage_id] = row

    superseded_attempts = {
        str(row.get("previous_attempt_id"))
        for row in lineage_heads.values()
        if row.get("previous_attempt_id")
    }
    heads = [
        row
        for row in lineage_heads.values()
        if row.get("attempt_id") not in superseded_attempts
        and row.get("lineage_state") not in {"retired", "replaced", "lost"}
        and row.get("execution_state") not in {"retired", "replaced"}
    ]
    heads.sort(key=lambda item: (item["urgency_rank"], item.get("last_event_at") or "", item["dispatch_id"]), reverse=False)
    return heads, max(0, len(rows) - len(heads))


def _worker_projection(run_root: Path, repo_root: Path, now: datetime) -> dict[str, Any]:
    index_path = run_root / "work" / "director-dispatch-index.yaml"
    dispatch_dir = run_root / "work" / "department-dispatches"
    if index_path.is_file() and _is_within_repo(index_path, repo_root):
        source_paths = [index_path]
        source_kind = "director_dispatch_index"
    else:
        source_paths = [
            path
            for path in sorted(dispatch_dir.glob("*.yaml"))
            if path.is_file() and _is_within_repo(path, repo_root)
        ] if dispatch_dir.is_dir() and _is_within_repo(dispatch_dir, repo_root) else []
        source_kind = "department_dispatch_files"

    fingerprint = _fingerprint(source_paths)
    cache_key = str(run_root.resolve())
    with _cache_lock:
        cached = _worker_cache.get(cache_key)
        if cached and cached[0] == fingerprint:
            cached_projection = copy.deepcopy(cached[1])
            for worker in cached_projection.get("workers", []):
                last_event = _as_datetime(worker.get("last_event_at"), now.tzinfo)
                attention, reason, rank = _worker_attention(worker.get("execution_state", "unknown"), last_event, now)
                worker["attention"] = attention
                worker["attention_reason"] = reason
                worker["urgency_rank"] = rank
                worker["elapsed_hours"] = round((now - last_event).total_seconds() / 3600, 1) if last_event else None
            cached_projection["workers"].sort(key=lambda item: (item["urgency_rank"], -(item.get("elapsed_hours") or 0), item["dispatch_id"]))
            cached_projection["urgent"] = [item for item in cached_projection["workers"] if item["attention"]][:6]
            return cached_projection

    errors: list[str] = []
    rows: list[dict[str, Any]] = []
    if source_kind == "director_dispatch_index":
        try:
            index = _load_yaml(index_path)
            raw_rows = index.get("dispatches") if isinstance(index.get("dispatches"), list) else []
            rows = [_worker_from_index(row, repo_root, now) for row in raw_rows if isinstance(row, dict)]
        except (OSError, ValueError, yaml.YAMLError) as exc:
            errors.append(f"{_repo_relative(index_path, repo_root)}: {exc}")
    else:
        for path in source_paths:
            try:
                rows.append(_worker_from_dispatch(_load_yaml(path), path, repo_root, now))
            except (OSError, ValueError, yaml.YAMLError) as exc:
                errors.append(f"{_repo_relative(path, repo_root)}: {exc}")

    heads, history_attempts = _select_worker_heads(rows)
    heads.sort(key=lambda item: (item["urgency_rank"], -(item.get("elapsed_hours") or 0), item["dispatch_id"]))
    counts = Counter(item["execution_state"] for item in heads)
    projection = {
        "source": source_kind,
        "source_path": _repo_relative(index_path, repo_root) if source_kind == "director_dispatch_index" else _repo_relative(dispatch_dir, repo_root),
        "projection_complete": source_kind == "director_dispatch_index" and not errors,
        "authority": "pointer_only_read_model_no_creative_authority",
        "note": (
            "Director Dispatch Index 기준 현재 head"
            if source_kind == "director_dispatch_index"
            else "DDI 없음: dispatch 원본의 lineage별 최신 attempt를 직접 투영한 불완전 view"
        ),
        "counts": {
            "registered_heads": len(heads),
            "history_attempts": history_attempts,
            **{state: counts.get(state, 0) for state in _WORKER_STATES},
        },
        "workers": heads,
        "urgent": [item for item in heads if item["attention"]][:6],
        "errors": errors,
    }
    with _cache_lock:
        _worker_cache[cache_key] = (fingerprint, copy.deepcopy(projection))
    return projection


def _is_test_run(manifest: dict[str, Any]) -> bool:
    album_key = str(manifest.get("album_key") or "")
    title_key = str(manifest.get("title_key") or "")
    content_id = str(manifest.get("content_id") or "")
    return album_key.startswith("idol-active-suite-") or title_key == "active-title-test" or content_id == "ACTIVE_TITLE_TEST"


def _is_mv_candidate(item: dict[str, Any]) -> bool:
    """Keep the MV board focused on music-video production runs only."""

    title_key = str(item.get("title_key") or "").lower()
    content_id = str(item.get("content_id") or "").lower()
    if title_key.startswith("cf-") or content_id.startswith("cf_"):
        return False
    excluded_tokens = (
        "sns-ops",
        "public-sns",
        "board-sketch-stills",
        "face-source-upscale-retirement",
    )
    return not any(token in title_key or token in content_id for token in excluded_tokens)


def _run_order(item: dict[str, Any]) -> tuple[int, int, str, str]:
    return (
        1 if item.get("lifecycle_class") == "current_contract" else 0,
        int(item.get("run_sequence") or 0),
        str(item.get("created_at") or ""),
        str(item.get("run_id") or ""),
    )


def _discover_mv_runs(repo_root: Path, now: datetime) -> tuple[list[dict[str, Any]], list[str]]:
    discovered: list[dict[str, Any]] = []
    errors: list[str] = []
    runs_root = repo_root / "runs"
    for manifest_path in sorted(runs_root.glob("*/*/*/run-manifest.yaml")):
        if not manifest_path.is_file() or not _is_within_repo(manifest_path, repo_root):
            errors.append(f"unsafe or non-file run manifest skipped: {manifest_path}")
            continue
        try:
            manifest = _load_yaml(manifest_path)
        except (OSError, ValueError, yaml.YAMLError) as exc:
            errors.append(f"{_repo_relative(manifest_path, repo_root)}: {exc}")
            continue
        if _is_test_run(manifest):
            continue
        run_root = manifest_path.parent
        actual_root = _repo_relative(run_root, repo_root)
        declared_root = str(manifest.get("canonical_run_root") or actual_root)
        if declared_root != actual_root:
            errors.append(f"{_repo_relative(manifest_path, repo_root)}: canonical_run_root does not match folder")
        canonical_root = actual_root
        created_at = _as_datetime(manifest.get("created_at"), now.tzinfo)
        created_source = "run_manifest.created_at"
        if created_at is None:
            created_at, created_source = _directory_birthtime(run_root, now)
        status = str(manifest.get("status") or "unknown")
        if status in _TERMINAL_RUN_STATES:
            lifecycle_class = "terminal"
        elif status in _CURRENT_RUN_STATES:
            lifecycle_class = "current_contract"
        else:
            lifecycle_class = "custom_or_unresolved"
        discovered.append(
            {
                "kind": "mv",
                "album_key": str(manifest.get("album_key") or run_root.parent.parent.name),
                "title_key": str(manifest.get("title_key") or run_root.parent.name),
                "run_id": str(manifest.get("run_id") or run_root.name),
                "content_id": str(manifest.get("content_id") or run_root.name),
                "root": canonical_root,
                "manifest_path": _repo_relative(manifest_path, repo_root),
                "status": status,
                "lifecycle_class": lifecycle_class,
                "created_at": _iso(created_at),
                "created_at_source": created_source,
                "run_sequence": int(manifest.get("run_sequence") or 0),
                "previous_run_root": manifest.get("previous_run_root"),
                "deadline": _deadline(created_at, MV_DEADLINE_DAYS, now),
            }
        )

    return discovered, errors


def _build_mv_families(
    discovered: list[dict[str, Any]],
    repo_root: Path,
    now: datetime,
) -> tuple[list[dict[str, Any]], int]:
    eligible = [item for item in discovered if _is_mv_candidate(item)]
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for item in eligible:
        grouped.setdefault((item["album_key"], item["title_key"]), []).append(item)

    families: list[dict[str, Any]] = []
    for (album_key, title_key), members in grouped.items():
        nonterminal = [item for item in members if item["lifecycle_class"] != "terminal"]
        if not nonterminal:
            continue

        provisional_main = max(nonterminal, key=_run_order)
        previous_root = str(provisional_main.get("previous_run_root") or "")
        base = next((item for item in members if previous_root and item["root"] == previous_root), None)
        operational = [item for item in nonterminal if item is not base]
        if not operational:
            operational = [provisional_main]
            base = None
        main = max(operational, key=_run_order)

        def sub_order(item: dict[str, Any]) -> tuple[int, int, int, str, str]:
            shared_parent = bool(
                main.get("previous_run_root")
                and item.get("previous_run_root") == main.get("previous_run_root")
            )
            same_content = item.get("content_id") == main.get("content_id")
            order = _run_order(item)
            return (1 if shared_parent else 0, 1 if same_content else 0, *order[1:])

        subs = sorted((item for item in operational if item is not main), key=sub_order, reverse=True)
        ordered_runs = [main, *subs]
        family_id = f"{album_key}/{title_key}"
        presented_runs: list[dict[str, Any]] = []
        family_urgent: list[dict[str, Any]] = []
        family_counts: Counter[str] = Counter()
        worker_heads = 0
        for index, source_run in enumerate(ordered_runs):
            run = copy.deepcopy(source_run)
            run["family_id"] = family_id
            run["presentation_role"] = "main" if index == 0 else "sub"
            run["presentation_label"] = "MAIN" if index == 0 else f"SUB {index}"
            run["presentation_authority"] = "tracker_view_only"
            run_root = repo_root / run["root"]
            projection = _worker_projection(run_root, repo_root, now)
            run["worker_projection"] = projection
            counts = projection.get("counts", {})
            worker_heads += int(counts.get("registered_heads") or 0)
            for state in _WORKER_STATES:
                family_counts[state] += int(counts.get(state) or 0)
            family_urgent.extend(
                {
                    **worker,
                    "run_id": run["run_id"],
                    "run_role": run["presentation_label"],
                }
                for worker in projection.get("urgent", [])
            )
            presented_runs.append(run)

        family_urgent.sort(
            key=lambda item: (
                int(item.get("urgency_rank") or 99),
                -(float(item.get("elapsed_hours") or 0)),
                str(item.get("dispatch_id") or ""),
            )
        )
        shared_parent = bool(
            len(ordered_runs) > 1
            and main.get("previous_run_root")
            and all(item.get("previous_run_root") == main.get("previous_run_root") for item in ordered_runs)
        )
        base_summary = None
        if base:
            base_summary = {
                **copy.deepcopy(base),
                "family_id": family_id,
                "presentation_role": "base",
                "presentation_label": "BASE",
                "presentation_authority": "tracker_view_only",
            }
        families.append(
            {
                "family_id": family_id,
                "album_key": album_key,
                "title_key": title_key,
                "content_id": main.get("content_id"),
                "main_run_id": main["run_id"],
                "status": main["status"],
                "lifecycle_class": main["lifecycle_class"],
                "deadline": copy.deepcopy(main["deadline"]),
                "created_at": main.get("created_at"),
                "open_run_count": len(presented_runs),
                "sub_run_count": len(subs),
                "relationship_basis": "shared_previous_run_root" if shared_parent else "same_album_title",
                "presentation_authority": "tracker_view_only_no_production_authority",
                "base_run": base_summary,
                "runs": presented_runs,
                "worker_summary": {
                    "registered_heads": worker_heads,
                    "attention": len(family_urgent),
                    **{state: family_counts[state] for state in _WORKER_STATES},
                },
                "urgent": family_urgent[:8],
            }
        )

    families.sort(
        key=lambda family: (
            1 if family["lifecycle_class"] == "current_contract" else 0,
            family["created_at"] or "",
            family["main_run_id"],
        ),
        reverse=True,
    )
    return families, len(discovered) - len(eligible)


def _discover_cf_runs(repo_root: Path, now: datetime) -> list[dict[str, Any]]:
    cf_root = repo_root / "cf" / "runs"
    runs: list[dict[str, Any]] = []
    if not cf_root.is_dir():
        return runs
    for run_root in sorted(cf_root.glob("CF_*")):
        if not run_root.is_dir() or not _is_within_repo(run_root, repo_root):
            continue
        created_at, source = _directory_birthtime(run_root, now)
        runs.append(
            {
                "kind": "cf",
                "run_id": run_root.name,
                "content_id": run_root.name,
                "root": _repo_relative(run_root, repo_root),
                "status": "folder_observed",
                "created_at": _iso(created_at),
                "created_at_source": source,
                "deadline": _deadline(created_at, CF_DEADLINE_DAYS, now),
            }
        )
    runs.sort(key=lambda item: item["created_at"] or "", reverse=True)
    return runs


def collect_operations(repo_root: Path = IDOL_REPO_ROOT, now: datetime | None = None) -> dict[str, Any]:
    """Build a read-only operational projection without mutating run or harness bytes."""

    now = now or datetime.now().astimezone()
    repo_root = repo_root.resolve()
    discovered_mv_runs, mv_errors = _discover_mv_runs(repo_root, now)
    mv_families, excluded_mv_runs = _build_mv_families(discovered_mv_runs, repo_root, now)
    mv_runs = [copy.deepcopy(family["runs"][0]) for family in mv_families]
    cf_runs = _discover_cf_runs(repo_root, now)
    selected_family = copy.deepcopy(mv_families[0]) if mv_families else None
    selected_mv = copy.deepcopy(selected_family["runs"][0]) if selected_family else None
    selected_cf = copy.deepcopy(cf_runs[0]) if cf_runs else None
    worker_counts = selected_mv.get("worker_projection", {}).get("counts", {}) if selected_mv else {}
    return {
        "generated_at": now.isoformat(timespec="seconds"),
        "source_mode": "read_only",
        "authority": "tracker_projection_only_no_production_pass",
        "deadline_policy": {
            "mv": {"days": MV_DEADLINE_DAYS, "basis": "run_manifest.created_at_then_folder_birthtime"},
            "cf": {"days": CF_DEADLINE_DAYS, "basis": "cf_run_folder_birthtime"},
        },
        "selected_mv_family_id": selected_family.get("family_id") if selected_family else None,
        "selected_mv_family": selected_family,
        "selected_mv_run": selected_mv,
        "selected_cf_run": selected_cf,
        "mv_families": mv_families,
        "mv_runs": mv_runs,
        "cf_runs": cf_runs[:12],
        "summary": {
            "mv_current_runs": len(mv_runs),
            "mv_open_families": len(mv_families),
            "mv_open_runs": sum(family["open_run_count"] for family in mv_families),
            "mv_excluded_non_mv_runs": excluded_mv_runs,
            "cf_observed_runs": len(cf_runs),
            "worker_heads": worker_counts.get("registered_heads", 0),
            "worker_attention": len(selected_mv.get("worker_projection", {}).get("urgent", [])) if selected_mv else 0,
        },
        "errors": mv_errors,
    }
