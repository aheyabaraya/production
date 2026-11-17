"""Shared OpenAI image model policy for IDOL production scripts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ALLOWED_OPENAI_IMAGE_MODEL = "gpt-image-2"
BANNED_OPENAI_IMAGE_MODELS = {"gpt-image-1"}


def require_openai_image_model(model: Any, *, context: str) -> str:
    """Return the allowed model or fail before any OpenAI image request is used."""
    model_name = str(model or ALLOWED_OPENAI_IMAGE_MODEL).strip()
    if model_name == ALLOWED_OPENAI_IMAGE_MODEL:
        return model_name
    if model_name in BANNED_OPENAI_IMAGE_MODELS:
        raise ValueError(f"{context}: {model_name} is banned in IDOL; use {ALLOWED_OPENAI_IMAGE_MODEL}")
    raise ValueError(f"{context}: OpenAI image model must be {ALLOWED_OPENAI_IMAGE_MODEL}; got {model_name!r}")


def assert_openai_image_request_row(row: dict[str, Any], *, context: str) -> None:
    body = row.get("body")
    if not isinstance(body, dict):
        raise ValueError(f"{context}: Batch API row is missing body")
    body["model"] = require_openai_image_model(body.get("model"), context=f"{context} body.model")


def assert_openai_image_request_jsonl(path: Path, *, context: str) -> None:
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw_line.strip():
            continue
        try:
            row = json.loads(raw_line)
        except json.JSONDecodeError as error:
            raise ValueError(f"{context}: invalid JSONL at line {line_number}: {error}") from error
        if not isinstance(row, dict):
            raise ValueError(f"{context}: JSONL line {line_number} must be an object")
        assert_openai_image_request_row(row, context=f"{context} line {line_number}")
