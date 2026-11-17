from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from threading import RLock
from typing import Any

from .paths import DATA_PATH, TOOL_ROOT
from .validation import validate_state


class TrackerStore:
    """Atomic JSON store whose writes are restricted to the tracker tool root."""

    def __init__(self, data_path: Path = DATA_PATH, *, allowed_root: Path = TOOL_ROOT):
        self.data_path = data_path.resolve()
        try:
            self.data_path.relative_to(allowed_root.resolve())
        except ValueError as exc:
            raise ValueError("tracker data path must stay inside the configured tracker root") from exc
        self._lock = RLock()

    def load(self) -> dict[str, Any]:
        with self._lock:
            with self.data_path.open("r", encoding="utf-8") as handle:
                state = json.load(handle)
            validate_state(state)
            return state

    def save(self, state: dict[str, Any]) -> None:
        validate_state(state)
        with self._lock:
            self.data_path.parent.mkdir(parents=True, exist_ok=True)
            temp_path: Path | None = None
            try:
                with tempfile.NamedTemporaryFile(
                    "w",
                    encoding="utf-8",
                    dir=self.data_path.parent,
                    prefix=".tracker-",
                    suffix=".json.tmp",
                    delete=False,
                ) as handle:
                    json.dump(state, handle, ensure_ascii=False, indent=2)
                    handle.write("\n")
                    handle.flush()
                    os.fsync(handle.fileno())
                    temp_path = Path(handle.name)
                os.replace(temp_path, self.data_path)
            finally:
                if temp_path and temp_path.exists():
                    temp_path.unlink()
