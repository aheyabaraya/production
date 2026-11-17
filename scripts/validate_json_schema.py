#!/usr/bin/env python3
"""Validate JSON or YAML documents against a JSON Schema."""

from __future__ import annotations

import argparse
from datetime import date, datetime
import json
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "Missing dependency: PyYAML. Run with an IDOL Python environment that has PyYAML installed."
    ) from exc

try:
    import jsonschema
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "Missing dependency: jsonschema. Run with .venv-video/bin/python or install jsonschema in the active environment."
    ) from exc


class UniqueKeyLoader(yaml.SafeLoader):
    """Reject duplicate YAML keys before schema validation."""


def construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"duplicate key: {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_unique_mapping
)


def load_document(path: Path) -> Any:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        return json.loads(text)
    return normalize_yaml_scalars(yaml.load(text, Loader=UniqueKeyLoader))


def normalize_yaml_scalars(value: Any) -> Any:
    """Convert YAML-native date objects into JSON-compatible schema values."""
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, list):
        return [normalize_yaml_scalars(item) for item in value]
    if isinstance(value, dict):
        return {key: normalize_yaml_scalars(item) for key, item in value.items()}
    return value


def error_path(error: jsonschema.ValidationError) -> str:
    if not error.absolute_path:
        return "$"
    return "$." + ".".join(str(part) for part in error.absolute_path)


def validator_for(schema: dict[str, Any]) -> jsonschema.protocols.Validator:
    validator_cls = jsonschema.validators.validator_for(schema)
    validator_cls.check_schema(schema)
    return validator_cls(schema, format_checker=jsonschema.FormatChecker())


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate one or more JSON/YAML files against a JSON Schema."
    )
    parser.add_argument("schema", type=Path, help="Path to a JSON Schema file.")
    parser.add_argument("documents", nargs="+", type=Path, help="JSON/YAML files to validate.")
    parser.add_argument(
        "--max-errors",
        type=int,
        default=20,
        help="Maximum errors printed per document (default: 20; 0 means unlimited).",
    )
    args = parser.parse_args()
    if args.max_errors < 0:
        parser.error("--max-errors must be zero or greater")

    try:
        schema = load_document(args.schema)
    except (OSError, json.JSONDecodeError, yaml.YAMLError) as exc:
        raise SystemExit(f"{args.schema}: schema load failed: {exc}") from exc
    validator = validator_for(schema)
    failed = False

    for document_path in args.documents:
        try:
            document = load_document(document_path)
        except (OSError, json.JSONDecodeError, yaml.YAMLError) as exc:
            failed = True
            print(f"{document_path}: invalid", file=sys.stderr)
            print(f"  - $: document load failed: {exc}", file=sys.stderr)
            continue
        errors = sorted(validator.iter_errors(document), key=lambda err: list(err.absolute_path))
        if errors:
            failed = True
            print(f"{document_path}: invalid", file=sys.stderr)
            visible_errors = errors if args.max_errors == 0 else errors[: args.max_errors]
            for error in visible_errors:
                print(f"  - {error_path(error)}: {error.message}", file=sys.stderr)
            omitted = len(errors) - len(visible_errors)
            if omitted:
                print(
                    f"  - ... {omitted} additional schema error(s) omitted; "
                    "rerun with --max-errors 0 outside model context",
                    file=sys.stderr,
                )
        else:
            print(f"{document_path}: schema ok")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
