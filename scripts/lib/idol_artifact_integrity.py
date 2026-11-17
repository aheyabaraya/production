"""Cost-aware artifact identity profiles for the active IDOL Graph Engineering runtime."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import tempfile
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


CACHE_VERSION = "idol-artifact-integrity-cache.v1"
DEFAULT_CACHE_RELATIVE = Path(".runtime/cache/artifact-integrity-sha256-v1.json")
PROFILES = {
    "canonical_gate": "force_sha256",
    "promotion_or_external_transfer": "force_sha256",
    "repeat_local_validation": "cached_sha256_by_stat",
    "working_derived_media": "stat_fingerprint",
    "ephemeral": "none",
}


def stat_fingerprint(path: str | Path) -> dict[str, Any]:
    stat = Path(path).stat()
    return {
        "algorithm": "stat-v1",
        "size_bytes": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "device": stat.st_dev,
        "inode": stat.st_ino,
        "value": (
            f"stat-v1:{stat.st_size}:{stat.st_mtime_ns}:"
            f"{stat.st_dev}:{stat.st_ino}"
        ),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class IntegrityCache:
    def __init__(
        self,
        repo_root: str | Path,
        cache_path: str | Path | None = None,
    ) -> None:
        self.repo_root = Path(repo_root).resolve()
        self.cache_path = (
            Path(cache_path).resolve()
            if cache_path
            else self.repo_root / DEFAULT_CACHE_RELATIVE
        )
        self.document = self._load()
        self.dirty = False

    def _load(self) -> dict[str, Any]:
        try:
            document = json.loads(self.cache_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            return {"schema_version": CACHE_VERSION, "entries": {}}
        if (
            not isinstance(document, dict)
            or document.get("schema_version") != CACHE_VERSION
            or not isinstance(document.get("entries"), dict)
        ):
            return {"schema_version": CACHE_VERSION, "entries": {}}
        return document

    def _key(self, path: Path) -> str:
        resolved = path.resolve()
        try:
            return resolved.relative_to(self.repo_root).as_posix()
        except ValueError:
            return resolved.as_posix()

    def sha256(self, path: str | Path, *, force: bool = False) -> dict[str, Any]:
        candidate = Path(path).resolve()
        fingerprint = stat_fingerprint(candidate)
        key = self._key(candidate)
        row = self.document["entries"].get(key)
        comparable = {
            field: fingerprint[field]
            for field in ("size_bytes", "mtime_ns", "device", "inode")
        }
        if (
            not force
            and isinstance(row, dict)
            and row.get("sha256")
            and all(row.get(field) == value for field, value in comparable.items())
        ):
            return {
                "algorithm": "sha256",
                "value": row["sha256"],
                "cache": "hit",
                **comparable,
            }
        value = _sha256(candidate)
        self.document["entries"][key] = {"sha256": value, **comparable}
        self.dirty = True
        return {
            "algorithm": "sha256",
            "value": value,
            "cache": "forced" if force else "miss",
            **comparable,
        }

    def inspect(self, path: str | Path, profile: str) -> dict[str, Any]:
        if profile not in PROFILES:
            raise ValueError(f"unknown integrity profile: {profile}")
        mode = PROFILES[profile]
        if mode == "force_sha256":
            result = self.sha256(path, force=True)
        elif mode == "cached_sha256_by_stat":
            result = self.sha256(path, force=False)
        elif mode == "stat_fingerprint":
            result = stat_fingerprint(path)
            result["cache"] = "not_applicable"
        else:
            result = {"algorithm": "none", "value": None, "cache": "not_applicable"}
        result["profile"] = profile
        return result

    def save(self) -> None:
        if not self.dirty:
            return
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=self.cache_path.parent,
            prefix=f".{self.cache_path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            json.dump(self.document, handle, ensure_ascii=False, sort_keys=True)
            handle.write("\n")
            temporary = Path(handle.name)
        os.chmod(temporary, 0o600)
        os.replace(temporary, self.cache_path)
        self.dirty = False


WRITE_BINDING_PROFILE = "canonical_gate"
CANONICAL_FRESH_LIMIT = (
    "Canonical writer and verification bind SHA-256 from a fresh byte read. "
    "Before-read and after-read operation snapshots must match. The per-operation "
    "memo additionally keys ctime_ns and fails closed if a previously bound path "
    "drifts. Publication re-stats and re-hashes every bound path. IntegrityCache "
    "stat-v1 is unchanged and does not detect a same-size mtime-preserving rewrite."
)
REPEAT_LOCAL_DIAGNOSTIC_LIMIT = (
    "repeat_local_validation is diagnostic only. IntegrityCache may reuse a stored "
    "SHA when size_bytes, mtime_ns, device, and inode match. A same-size rewrite "
    "that preserves mtime is not detected by that cache. Diagnostic hits never "
    "become the canonical write or verify binding."
)


def operation_snapshot(path: str | Path) -> dict[str, Any]:
    stat = Path(path).stat()
    return {
        "size_bytes": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "ctime_ns": int(stat.st_ctime_ns),
        "device": int(stat.st_dev),
        "inode": int(stat.st_ino),
    }


class OperationFreshSha:
    def __init__(self) -> None:
        self.rows: dict[str, dict[str, Any]] = {}
        self.fresh_reads = 0
        self.memo_hits = 0
        self.holds: list[str] = []

    def sha256(self, path: str | Path) -> str:
        candidate = Path(path).resolve()
        key = str(candidate)
        try:
            before = operation_snapshot(candidate)
        except OSError as exc:
            message = f"HOLD snapshot_inconsistent: {key} is not readable: {exc}"
            self.holds.append(message)
            raise ValueError(message) from exc
        row = self.rows.get(key)
        if row is not None:
            if row["snapshot"] != before:
                self.holds.append(
                    f"HOLD snapshot_inconsistent: {key} previously bound input changed; refuse mixed-generation binding"
                )
                return str(row["sha256"])
            try:
                after_lookup = operation_snapshot(candidate)
            except OSError as exc:
                self.holds.append(
                    f"HOLD snapshot_inconsistent: {key} is not readable during memo lookup: {exc}"
                )
                return str(row["sha256"])
            if after_lookup != before:
                self.holds.append(
                    f"HOLD snapshot_inconsistent: {key} changed during memo lookup"
                )
                return str(row["sha256"])
            self.memo_hits += 1
            return str(row["sha256"])
        value = _sha256(candidate)
        try:
            after = operation_snapshot(candidate)
        except OSError as exc:
            self.holds.append(
                f"HOLD snapshot_inconsistent: {key} is not readable after fresh byte read: {exc}"
            )
            return value
        if after != before:
            self.holds.append(
                f"HOLD snapshot_inconsistent: {key} changed during fresh byte read"
            )
            return value
        self.rows[key] = {"sha256": value, "snapshot": after}
        self.fresh_reads += 1
        return value

    def bind_bytes(self, path: str | Path, raw: bytes) -> str:
        candidate = Path(path).resolve()
        key = str(candidate)
        try:
            before = operation_snapshot(candidate)
        except OSError as exc:
            message = f"HOLD snapshot_inconsistent: {key} is not readable: {exc}"
            self.holds.append(message)
            raise ValueError(message) from exc
        value = hashlib.sha256(raw).hexdigest()
        try:
            after = operation_snapshot(candidate)
        except OSError as exc:
            self.holds.append(
                f"HOLD snapshot_inconsistent: {key} is not readable after parse-bound read: {exc}"
            )
            return value
        if after != before:
            self.holds.append(
                f"HOLD snapshot_inconsistent: {key} changed during parse-bound read"
            )
            return value
        row = self.rows.get(key)
        if row is not None:
            if row["snapshot"] != after or row["sha256"] != value:
                self.holds.append(
                    f"HOLD snapshot_inconsistent: {key} previously bound input changed; refuse mixed-generation binding"
                )
                return str(row["sha256"])
            self.memo_hits += 1
            return str(row["sha256"])
        self.rows[key] = {"sha256": value, "snapshot": after}
        self.fresh_reads += 1
        return value

    def verify_publication(self) -> list[str]:
        holds = list(self.holds)
        for key, row in self.rows.items():
            path = Path(key)
            try:
                before = operation_snapshot(path)
            except OSError as exc:
                holds.append(
                    f"HOLD snapshot_inconsistent: {key} is not readable before publication: {exc}"
                )
                continue
            if before != row["snapshot"]:
                holds.append(
                    f"HOLD snapshot_inconsistent: {key} input snapshot changed before publication"
                )
                continue
            actual = _sha256(path)
            try:
                after = operation_snapshot(path)
            except OSError as exc:
                holds.append(
                    f"HOLD snapshot_inconsistent: {key} is not readable during publication confirmation read: {exc}"
                )
                continue
            if after != before:
                holds.append(
                    f"HOLD snapshot_inconsistent: {key} changed during publication confirmation read"
                )
                continue
            if actual != row["sha256"]:
                holds.append(
                    f"HOLD snapshot_inconsistent: {key} bytes changed since bind"
                )
        return holds


class HashBinder:
    def __init__(
        self,
        repo_root: str | Path,
        *,
        profile: str = WRITE_BINDING_PROFILE,
    ) -> None:
        if profile not in ("canonical_gate", "repeat_local_validation"):
            raise ValueError(f"unsupported integrity profile: {profile}")
        self.profile = profile
        self.fresh = OperationFreshSha()
        self.cache = (
            IntegrityCache(repo_root) if profile == "repeat_local_validation" else None
        )
        self.diagnostic_hits = 0
        self.diagnostic_misses = 0
        self.diagnostic_disagreements_with_fresh = 0

    def sha256(self, path: str | Path) -> str:
        value = self.fresh.sha256(path)
        if self.cache is not None:
            cached = self.cache.inspect(path, "repeat_local_validation")
            if cached.get("cache") == "hit":
                self.diagnostic_hits += 1
                if cached.get("value") != value:
                    self.diagnostic_disagreements_with_fresh += 1
            else:
                self.diagnostic_misses += 1
        return value

    def bind_bytes(self, path: str | Path, raw: bytes) -> str:
        value = self.fresh.bind_bytes(path, raw)
        if self.cache is not None:
            cached = self.cache.inspect(path, "repeat_local_validation")
            if cached.get("cache") == "hit":
                self.diagnostic_hits += 1
                if cached.get("value") != value:
                    self.diagnostic_disagreements_with_fresh += 1
            else:
                self.diagnostic_misses += 1
        return value

    def verify_publication(self) -> list[str]:
        return self.fresh.verify_publication()

    def report(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "profile": self.profile,
            "write_binding": WRITE_BINDING_PROFILE,
            "write_binding_mode": PROFILES[WRITE_BINDING_PROFILE],
            "limits": (
                REPEAT_LOCAL_DIAGNOSTIC_LIMIT
                if self.profile == "repeat_local_validation"
                else CANONICAL_FRESH_LIMIT
            ),
            "fresh_reads": self.fresh.fresh_reads,
            "memo_hits": self.fresh.memo_hits,
            "publication_hold_count": len(self.fresh.holds),
            "durable_cache_used_for_binding": False,
        }
        if self.cache is not None:
            payload.update(
                {
                    "diagnostic_cache_profile": "repeat_local_validation",
                    "diagnostic_cache_mode": PROFILES["repeat_local_validation"],
                    "diagnostic_hits": self.diagnostic_hits,
                    "diagnostic_misses": self.diagnostic_misses,
                    "diagnostic_disagreements_with_fresh": (
                        self.diagnostic_disagreements_with_fresh
                    ),
                }
            )
        return payload


def atomic_cas_preflight(path: Path, previous: str | None) -> str | None:
    if path.is_symlink():
        return f"HOLD escaped_path: {path} is a symlink; refuse to publish through it"
    if path.exists():
        current = path.read_text(encoding="utf-8")
        if previous is None or current != previous:
            return (
                f"HOLD concurrent_output_change: {path} changed since the operation snapshot"
            )
        return None
    if previous is not None:
        return (
            f"HOLD concurrent_output_change: {path} was removed since the operation snapshot"
        )
    return None


class _PublicationLockState:
    def __init__(self) -> None:
        self.counts: dict[str, int] = {}
        self.fds: dict[str, int] = {}


_PUBLICATION_LOCK_STATE = threading.local()


def _publication_lock_state() -> _PublicationLockState:
    state = getattr(_PUBLICATION_LOCK_STATE, "state", None)
    if state is None:
        state = _PublicationLockState()
        _PUBLICATION_LOCK_STATE.state = state
    return state


def publication_lock_path(destination: Path) -> Path:
    return destination.parent / f".{destination.name}.publish.lock"


def _publish_text(path: Path) -> tuple[str | None, str | None]:
    if path.is_symlink():
        return None, (
            f"HOLD escaped_path: {path} is a symlink; refuse to publish through it"
        )
    if not path.exists():
        return None, None
    try:
        return path.read_text(encoding="utf-8"), None
    except OSError as exc:
        return None, f"HOLD publication_write_failed: {path}: {exc}"


def _preimage_hold(
    path: Path, previous: str | None, current: str | None
) -> str | None:
    if current == previous:
        return None
    if current is None:
        return (
            f"HOLD concurrent_output_change: {path} was removed since the operation snapshot"
        )
    return (
        f"HOLD concurrent_output_change: {path} changed since the operation snapshot"
    )


@contextmanager
def publication_locks(destinations: list[Path]) -> Iterator[list[str]]:
    """Exclusive advisory flock over sorted lock files for named destinations.

    Cooperative overlapping writers share this helper. Nested reuse is allowed
    only for already-held lock files. Process death releases flock with the fd;
    leftover lock files are not holders. Noncooperative writers that skip this
    lock are outside the contract.
    """
    holds: list[str] = []
    unique: list[Path] = []
    seen: set[str] = set()
    for dest in destinations:
        key = str(dest)
        if key in seen:
            continue
        seen.add(key)
        unique.append(dest)
        if dest.is_symlink():
            holds.append(
                f"HOLD escaped_path: {dest} is a symlink; refuse to publish through it"
            )
    if holds:
        yield holds
        return
    ordered = sorted(
        {publication_lock_path(dest) for dest in unique}, key=str
    )
    for lock_path in ordered:
        if lock_path.is_symlink():
            holds.append(
                f"HOLD escaped_path: {lock_path} is a symlink; refuse to publish through it"
            )
    if holds:
        yield holds
        return
    state = _publication_lock_state()
    extra = [path for path in ordered if str(path) not in state.counts]
    if state.counts and extra:
        holds.append(
            "HOLD nested_lock: additional destination while holding publication locks"
        )
        yield holds
        return
    incremented: list[str] = []
    try:
        for lock_path in ordered:
            key = str(lock_path)
            if key in state.counts:
                state.counts[key] += 1
                incremented.append(key)
                continue
            lock_path.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(str(lock_path), os.O_CREAT | os.O_RDWR, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
            except OSError as exc:
                os.close(fd)
                holds.append(
                    f"HOLD publication_lock_failed: {lock_path}: {exc}"
                )
                break
            state.fds[key] = fd
            state.counts[key] = 1
            incremented.append(key)
        yield holds
    finally:
        for key in reversed(incremented):
            if key not in state.counts:
                continue
            state.counts[key] -= 1
            if state.counts[key] > 0:
                continue
            fd = state.fds.pop(key)
            del state.counts[key]
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                os.close(fd)
            except OSError:
                pass


def atomic_cas_replace(path: Path, content: str, *, previous: str | None) -> str | None:
    """Replace one file after a preimage check inside its publication lock.

    Caught OSError unlinks the unpublished temp. Process death may leave a
    sibling .tmp; that temp is not the published destination.
    """
    with publication_locks([path]) as lock_holds:
        if lock_holds:
            return lock_holds[0]
        current, read_hold = _publish_text(path)
        if read_hold:
            return read_hold
        if current == content:
            return None
        held = _preimage_hold(path, previous, current)
        if held:
            return held
        path.parent.mkdir(parents=True, exist_ok=True)
        handle = None
        temporary = None
        try:
            handle = tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=path.parent,
                prefix=f".{path.name}.",
                suffix=".tmp",
                delete=False,
            )
            temporary = Path(handle.name)
            handle.write(content)
            handle.close()
            handle = None
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
            temporary = None
        except OSError as exc:
            if handle is not None:
                try:
                    handle.close()
                except OSError:
                    pass
            if temporary is not None:
                try:
                    temporary.unlink()
                except OSError:
                    pass
            return f"HOLD publication_write_failed: {path}: {exc}"
        except Exception:
            if handle is not None:
                try:
                    handle.close()
                except OSError:
                    pass
            if temporary is not None:
                try:
                    temporary.unlink()
                except OSError:
                    pass
            raise
        return None


class PublicationTarget:
    def __init__(
        self,
        path: Path,
        content: str,
        previous: str | None,
        *,
        role: str,
    ) -> None:
        if role not in ("canonical", "derived"):
            raise ValueError(f"unsupported publication role: {role}")
        self.path = path
        self.content = content
        self.previous = previous
        self.role = role


class PublicationReport:
    def __init__(self) -> None:
        self.holds: list[str] = []
        self.committed: list[str] = []
        self.already_present: list[str] = []
        self.pending: list[str] = []


def publish_canonical_derived(
    *,
    canonical: list[PublicationTarget],
    derived: list[PublicationTarget] | None = None,
) -> PublicationReport:
    """Publish named canonical files, then derived files, under one lock set.

    Derived is written only after a fresh read of every named canonical path
    still equals the intended canonical bytes used to render it. Cooperative
    writers serialize on sorted destination locks and re-check previous bytes
    inside the lock. Not a multi-file filesystem transaction. Caught write
    failures unlink temps; process death may leave temps. Noncooperative
    writers that skip the lock can still tear.
    """
    report = PublicationReport()
    canonical_items = list(canonical)
    derived_items = list(derived or [])
    for item in canonical_items:
        if item.role != "canonical":
            report.holds.append(
                f"HOLD publication_role: {item.path} must use role canonical"
            )
    for item in derived_items:
        if item.role != "derived":
            report.holds.append(
                f"HOLD publication_role: {item.path} must use role derived"
            )
    ordered = canonical_items + derived_items
    if not ordered:
        report.holds.append("HOLD publication_empty: no publication targets")
        return report
    seen: set[str] = set()
    for item in ordered:
        key = str(item.path)
        if key in seen:
            report.holds.append(f"HOLD publication_duplicate_path: {item.path}")
        seen.add(key)
    if report.holds:
        report.pending = [str(item.path) for item in ordered]
        return report
    with publication_locks([item.path for item in ordered]) as lock_holds:
        if lock_holds:
            report.holds.extend(lock_holds)
            report.pending = [str(item.path) for item in ordered]
            return report
        already: set[str] = set()
        for item in ordered:
            current, read_hold = _publish_text(item.path)
            if read_hold:
                report.holds.append(read_hold)
                continue
            if current == item.content:
                report.already_present.append(str(item.path))
                already.add(str(item.path))
                continue
            held = _preimage_hold(item.path, item.previous, current)
            if held:
                report.holds.append(held)
        if report.holds:
            for item in canonical_items:
                if str(item.path) in already:
                    report.committed.append(str(item.path))
            report.pending = [
                str(item.path)
                for item in ordered
                if str(item.path) not in already
            ]
            return report
        committed_canonical = False
        for item in canonical_items:
            if str(item.path) in already:
                report.committed.append(str(item.path))
                committed_canonical = True
                continue
            held = atomic_cas_replace(
                item.path, item.content, previous=item.previous
            )
            if held:
                report.holds.append(held)
                report.pending.extend(
                    str(rest.path)
                    for rest in ordered
                    if str(rest.path) not in report.committed
                )
                return report
            report.committed.append(str(item.path))
            committed_canonical = True
        for item in canonical_items:
            current, read_hold = _publish_text(item.path)
            if read_hold:
                report.holds.append(read_hold)
                report.pending.extend(str(rest.path) for rest in derived_items)
                return report
            if current != item.content:
                report.holds.append(
                    f"HOLD concurrent_output_change: {item.path} canonical changed before derived publication"
                )
                report.pending.extend(str(rest.path) for rest in derived_items)
                return report
        for index, item in enumerate(derived_items):
            if str(item.path) in already:
                report.committed.append(str(item.path))
                continue
            held = atomic_cas_replace(
                item.path, item.content, previous=item.previous
            )
            if held:
                report.holds.append(held)
                report.pending.extend(
                    str(rest.path)
                    for rest in derived_items[index:]
                    if str(rest.path) not in already
                )
                if committed_canonical:
                    report.holds.append(
                        "HOLD derived_publication_incomplete: canonical committed; derived pending"
                    )
                return report
            report.committed.append(str(item.path))
    return report


def read_publication_snapshot(
    paths: list[Path],
) -> tuple[dict[str, str | None], list[str]]:
    """Read named paths under the cooperative publication lock.

    Not a multi-file filesystem atomic read. Cooperative writers are excluded
    during the snapshot. Noncooperative writers can still tear.
    """
    snapshot: dict[str, str | None] = {}
    with publication_locks(list(paths)) as holds:
        if holds:
            return snapshot, holds
        for path in paths:
            current, read_hold = _publish_text(path)
            if read_hold:
                return snapshot, [read_hold]
            snapshot[str(path)] = current
    return snapshot, []
