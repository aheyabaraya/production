#!/usr/bin/env python3
"""Audit IDOL instruction surfaces without treating length as creative quality."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_POLICY = REPO_ROOT / "automation" / "instruction-surface-policy.yaml"


def word_count(text: str) -> int:
    return len(text.split())


def load_policy(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"policy must be an object: {path}")
    return data


def resolve_path(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve()
    root_resolved = root.resolve()
    try:
        candidate.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError(f"path escapes root: {relative}") from exc
    return candidate


def read_text(root: Path, relative: str, errors: list[dict[str, str]]) -> str | None:
    try:
        path = resolve_path(root, relative)
    except ValueError as exc:
        errors.append({"code": "path_escape", "path": relative, "message": str(exc)})
        return None
    if not path.is_file():
        errors.append({"code": "file_missing", "path": relative, "message": "required instruction file is missing"})
        return None
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        errors.append({"code": "file_unreadable", "path": relative, "message": str(exc)})
        return None


def finding(code: str, path: str, message: str) -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def heading_stanza(text: str, heading: str) -> str | None:
    """Return one Markdown heading's section, including its heading line."""

    lines = text.splitlines()
    try:
        start = next(index for index, line in enumerate(lines) if line.strip() == heading)
    except StopIteration:
        return None

    level = len(heading) - len(heading.lstrip("#"))
    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index].strip()
        if line.startswith("#"):
            candidate_level = len(line) - len(line.lstrip("#"))
            if candidate_level <= level:
                end = index
                break
    return "\n".join(lines[start:end])


def projected_heading_stanza(text: str, heading: str) -> tuple[str | None, str | None]:
    """Return one exact Markdown heading section using its title without hashes."""

    lines = text.splitlines()
    matches: list[tuple[int, int]] = []
    fenced = False
    for index, line in enumerate(lines):
        if re.match(r"^[ \t]*(?:```|~~~)", line):
            fenced = not fenced
            continue
        if fenced:
            continue
        match = re.match(r"^(#{1,6})[ \t]+(.+?)[ \t]*$", line)
        if match and match.group(2) == heading:
            matches.append((index, len(match.group(1))))
    if not matches:
        return None, "missing"
    if len(matches) != 1:
        return None, "ambiguous"

    start, level = matches[0]
    end = len(lines)
    fenced = False
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if re.match(r"^[ \t]*(?:```|~~~)", line):
            fenced = not fenced
            continue
        if fenced:
            continue
        match = re.match(r"^(#{1,6})[ \t]+", line)
        if match and len(match.group(1)) <= level:
            end = index
            break
    return "\n".join(lines[start:end]), None


def projection_rule(registry: dict[str, Any], binding_id: str, profile_id: str) -> tuple[dict[str, Any] | None, str | None]:
    rules = [
        row for row in registry.get("rules", [])
        if isinstance(row, dict)
        and str(row.get("binding_id", "")) == binding_id
        and profile_id in [str(value) for value in row.get("profile_ids", [])]
    ]
    if len(rules) > 1:
        return None, "multiple exact profile rules"
    if rules:
        return rules[0], None
    wildcard = [
        row for row in registry.get("rules", [])
        if isinstance(row, dict)
        and str(row.get("binding_id", "")) == binding_id
        and "*" in [str(value) for value in row.get("profile_ids", [])]
    ]
    if len(wildcard) > 1:
        return None, "multiple wildcard rules"
    return (wildcard[0], None) if wildcard else (None, None)


def projected_binding_words(
    *,
    text: str,
    path: str,
    kind: str,
    binding_id: str,
    profile_id: str,
    registry: dict[str, Any],
) -> tuple[int, list[str]]:
    rule, rule_error = projection_rule(registry, binding_id, profile_id)
    if rule_error:
        return 0, [rule_error]
    defaults = registry.get("defaults", {}) if isinstance(registry.get("defaults"), dict) else {}
    if rule:
        mode = str(rule.get("mode", ""))
    elif kind == "skill":
        mode = str(defaults.get("skill_mode", "full_file"))
    elif Path(path).suffix.lower() in {".json", ".yaml", ".yml", ".rb", ".py", ".js", ".ts", ".toml"}:
        mode = str(defaults.get("structured_read_mode", "pointer_only"))
    else:
        mode = str(defaults.get("markdown_read_mode", "full_file"))

    if mode == "full_file":
        return word_count(text), []
    if mode == "pointer_only":
        return 0, []
    if mode != "markdown_headings":
        return 0, [f"unsupported projection mode {mode}"]

    errors: list[str] = []
    projected_words = 0
    for heading in rule.get("headings", []) if rule else []:
        stanza, locator_error = projected_heading_stanza(text, str(heading))
        if locator_error:
            errors.append(f"{locator_error} heading {heading}")
        elif stanza is not None:
            projected_words += word_count(stanza)
    return projected_words, errors


def yaml_document(text: str, path: str) -> tuple[Any | None, dict[str, str] | None]:
    try:
        return yaml.safe_load(text), None
    except yaml.YAMLError as exc:
        return None, finding("runtime_registry_invalid", path, f"YAML parse failed: {exc}")


def audit(root: Path, policy: dict[str, Any]) -> dict[str, Any]:
    errors: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    surface_rows: list[dict[str, Any]] = []
    profile_rows: list[dict[str, Any]] = []
    conditional_rows: list[dict[str, Any]] = []
    invariant_rows: list[dict[str, Any]] = []
    routing_contract_rows: list[dict[str, Any]] = []
    exceptions = {row["path"] for row in policy.get("reviewed_size_exceptions", [])}
    text_cache: dict[str, str | None] = {}
    measurement = policy.get("measurement", {})
    if measurement.get("size_finding_authority") != "diagnostic_or_hold_only":
        errors.append(finding("size_authority_invalid", "measurement", "size findings must be diagnostic or hold only"))
    if measurement.get("size_remediation_authority") != "founder_explicit_current_request_only":
        errors.append(finding("size_remediation_authority_invalid", "measurement", "size remediation requires an explicit Founder instruction in the current request"))
    if measurement.get("automatic_size_remediation") is not False:
        errors.append(finding("automatic_size_remediation_forbidden", "measurement", "automatic size remediation must be false"))

    def text_for(relative: str) -> str | None:
        if relative not in text_cache:
            text_cache[relative] = read_text(root, relative, errors)
        return text_cache[relative]

    def check_size(path: str, words: int, target: int, ceiling: int, scope: str) -> None:
        if target > ceiling:
            errors.append(finding("invalid_size_policy", path, f"{scope} target {target} exceeds ceiling {ceiling}"))
        if words > ceiling:
            if path in exceptions:
                warnings.append(finding("reviewed_size_exception_used", path, f"{scope} has {words} words above ceiling {ceiling}"))
            else:
                errors.append(finding("reviewed_ceiling_exceeded", path, f"{scope} has {words} words above ceiling {ceiling}; preserve the file and request explicit Founder instruction before remediation"))
        elif words > target:
            warnings.append(finding("target_exceeded", path, f"{scope} has {words} words above target {target}"))

    seen_surface_ids: set[str] = set()
    seen_surface_paths: set[str] = set()
    for row in policy.get("surfaces", []):
        row_id = str(row["id"])
        path = str(row["path"])
        if row_id in seen_surface_ids:
            errors.append(finding("duplicate_surface_id", path, row_id))
        if path in seen_surface_paths:
            errors.append(finding("duplicate_surface_path", path, row_id))
        seen_surface_ids.add(row_id)
        seen_surface_paths.add(path)
        text = text_for(path)
        words = word_count(text) if text is not None else 0
        lines = len(text.splitlines()) if text is not None else 0
        check_size(path, words, int(row["target_words"]), int(row["reviewed_ceiling_words"]), "surface")
        surface_rows.append({"id": row_id, "path": path, "role": row["role"], "words": words, "lines": lines})

    startup_paths: set[str] = set()
    seen_profile_ids: set[str] = set()
    for row in policy.get("startup_profiles", []):
        row_id = str(row["id"])
        if row_id in seen_profile_ids:
            errors.append(finding("duplicate_profile_id", row_id, row_id))
        seen_profile_ids.add(row_id)
        paths = list(dict.fromkeys(str(path) for path in row["paths"]))
        startup_paths.update(paths)
        words = 0
        for path in paths:
            text = text_for(path)
            if text is not None:
                words += word_count(text)
        check_size(row_id, words, int(row["target_words"]), int(row["reviewed_ceiling_words"]), "startup profile")
        profile_rows.append(
            {
                "id": row_id,
                "kind": str(row.get("kind", "static_bootstrap_diagnostic")),
                "paths": paths,
                "words": words,
            }
        )

    runtime_config = policy.get("runtime_load_measurement")
    runtime_rows: list[dict[str, Any]] = []
    runtime_largest: list[dict[str, Any]] = []
    runtime_measurement: dict[str, Any] = {
        "registry_path": None,
        "projection_registry_path": None,
        "receiver_measurement": "registered_full_source_closure",
        "global_thresholds": {},
        "checkpoints": runtime_rows,
        "largest_checkpoints": runtime_largest,
        "unused_overrides": [],
        "status": "pass",
    }
    if isinstance(runtime_config, dict):
        registry_path = str(runtime_config.get("registry_path", ""))
        runtime_measurement["registry_path"] = registry_path
        projection_registry_path = str(runtime_config.get("projection_registry_path", ""))
        receiver_measurement = str(runtime_config.get("receiver_measurement", "registered_full_source_closure"))
        runtime_measurement["projection_registry_path"] = projection_registry_path or None
        runtime_measurement["receiver_measurement"] = receiver_measurement
        if receiver_measurement not in {"registered_full_source_closure", "projected_instruction_content"}:
            errors.append(finding("runtime_projection_invalid", "runtime_load_measurement", "receiver_measurement is invalid"))
        projection_registry: Any | None = None
        if receiver_measurement == "projected_instruction_content":
            if not projection_registry_path:
                errors.append(finding("runtime_projection_missing", "runtime_load_measurement", "projection_registry_path is required for projected receiver measurement"))
            else:
                projection_text = text_for(projection_registry_path)
                if projection_text is not None:
                    projection_registry, projection_error = yaml_document(projection_text, projection_registry_path)
                    if projection_error:
                        errors.append(projection_error)
                    elif not isinstance(projection_registry, dict):
                        errors.append(finding("runtime_projection_invalid", projection_registry_path, "projection registry must be an object"))
        global_thresholds = {
            "target_words": runtime_config.get("target_words"),
            "reviewed_ceiling_words": runtime_config.get("reviewed_ceiling_words"),
            "target_paths": runtime_config.get("target_paths"),
            "reviewed_ceiling_paths": runtime_config.get("reviewed_ceiling_paths"),
        }
        runtime_measurement["global_thresholds"] = global_thresholds

        def valid_thresholds(thresholds: dict[str, Any], label: str) -> bool:
            valid = True
            for key in ("target_words", "reviewed_ceiling_words", "target_paths", "reviewed_ceiling_paths"):
                value = thresholds.get(key)
                if not isinstance(value, int) or value < 1:
                    errors.append(finding("runtime_threshold_invalid", label, f"{key} must be a positive integer"))
                    valid = False
            if valid and thresholds["target_words"] > thresholds["reviewed_ceiling_words"]:
                errors.append(finding("runtime_threshold_invalid", label, "target_words exceeds reviewed_ceiling_words"))
                valid = False
            if valid and thresholds["target_paths"] > thresholds["reviewed_ceiling_paths"]:
                errors.append(finding("runtime_threshold_invalid", label, "target_paths exceeds reviewed_ceiling_paths"))
                valid = False
            return valid

        valid_thresholds(global_thresholds, "runtime_load_measurement")
        overrides_by_key: dict[tuple[str, str | None], dict[str, Any]] = {}
        override_rows = runtime_config.get("profile_checkpoint_overrides", [])
        if not isinstance(override_rows, list):
            errors.append(finding("runtime_override_invalid", "runtime_load_measurement", "profile_checkpoint_overrides must be an array"))
            override_rows = []
        for override in override_rows:
            if not isinstance(override, dict):
                errors.append(finding("runtime_override_invalid", "runtime_load_measurement", "override must be an object"))
                continue
            profile_id = str(override.get("profile_id", ""))
            checkpoint_id = override.get("checkpoint_id")
            checkpoint_key = str(checkpoint_id) if checkpoint_id is not None else None
            key = (profile_id, checkpoint_key)
            if not profile_id:
                errors.append(finding("runtime_override_invalid", "runtime_load_measurement", "override profile_id is required"))
                continue
            if key in overrides_by_key:
                errors.append(finding("runtime_override_duplicate", "runtime_load_measurement", f"duplicate override {profile_id}.{checkpoint_key or '*'}"))
                continue
            thresholds = {key_name: override.get(key_name) for key_name in global_thresholds}
            valid_thresholds(thresholds, f"runtime_load_measurement.{profile_id}.{checkpoint_key or '*'}")
            overrides_by_key[key] = {"thresholds": thresholds, "key": key}

        registry_text = text_for(registry_path) if registry_path else None
        registry: Any | None = None
        if not registry_path:
            errors.append(finding("runtime_registry_missing", "runtime_load_measurement", "registry_path is required"))
        elif registry_text is not None:
            registry, registry_error = yaml_document(registry_text, registry_path)
            if registry_error:
                errors.append(registry_error)
        if isinstance(registry, dict):
            if registry.get("status") != "active":
                errors.append(finding("runtime_registry_inactive", registry_path, "skill-load profile registry must be active"))
            skill_bindings = {str(row.get("binding_id")): row for row in registry.get("skill_bindings", []) if isinstance(row, dict)}
            read_bindings = {str(row.get("binding_id")): row for row in registry.get("read_bindings", []) if isinstance(row, dict)}
            profiles = registry.get("profiles", [])
            if not isinstance(profiles, list):
                errors.append(finding("runtime_registry_invalid", registry_path, "profiles must be an array"))
                profiles = []
            seen_override_keys: set[tuple[str, str | None]] = set()
            for profile in profiles:
                if not isinstance(profile, dict):
                    errors.append(finding("runtime_profile_invalid", registry_path, "profile must be an object"))
                    continue
                profile_id = str(profile.get("profile_id", ""))
                phase_load = profile.get("phase_load")
                checkpoints = phase_load.get("checkpoints") if isinstance(phase_load, dict) else None
                if not profile_id or not isinstance(checkpoints, list):
                    errors.append(finding("runtime_profile_invalid", registry_path, f"{profile_id or '<missing>'} must declare phase_load.checkpoints"))
                    continue
                for checkpoint in checkpoints:
                    if not isinstance(checkpoint, dict):
                        errors.append(finding("runtime_checkpoint_invalid", registry_path, f"{profile_id} checkpoint must be an object"))
                        continue
                    checkpoint_id = str(checkpoint.get("checkpoint_id", ""))
                    if not checkpoint_id:
                        errors.append(finding("runtime_checkpoint_invalid", registry_path, f"{profile_id} checkpoint_id is required"))
                        continue
                    exact_key = (profile_id, checkpoint_id)
                    wildcard_key = (profile_id, None)
                    override = overrides_by_key.get(exact_key) or overrides_by_key.get(wildcard_key)
                    if override:
                        seen_override_keys.add(override["key"])
                        thresholds = override["thresholds"]
                        threshold_source = "override"
                    else:
                        thresholds = global_thresholds
                        threshold_source = "global"

                    binding_refs: list[tuple[str, str]] = []
                    for binding_id in checkpoint.get("required_skill_ids", []) or []:
                        binding_refs.append(("skill", str(binding_id)))
                    for binding_id in checkpoint.get("required_read_ids", []) or []:
                        binding_refs.append(("read", str(binding_id)))
                    selected_paths: list[str] = []
                    selected_texts: dict[str, str] = {}
                    selected_bindings: list[tuple[str, str, str]] = []
                    missing_bindings: list[str] = []
                    missing_paths: list[str] = []
                    for kind, binding_id in binding_refs:
                        binding_map = skill_bindings if kind == "skill" else read_bindings
                        binding = binding_map.get(binding_id)
                        if not isinstance(binding, dict):
                            missing_bindings.append(f"{kind}:{binding_id}")
                            continue
                        binding_path = str(binding.get("path", ""))
                        if not binding_path:
                            missing_paths.append(f"{kind}:{binding_id}")
                            continue
                        if binding_path not in selected_paths:
                            selected_paths.append(binding_path)
                            bound_text = text_for(binding_path)
                            if bound_text is None:
                                missing_paths.append(binding_path)
                            else:
                                selected_texts[binding_path] = bound_text
                            selected_bindings.append((kind, binding_id, binding_path))
                    if missing_bindings:
                        errors.append(finding("runtime_binding_missing", registry_path, f"{profile_id}.{checkpoint_id}: {', '.join(missing_bindings)}"))
                    if missing_paths:
                        errors.append(finding("runtime_binding_path_missing", registry_path, f"{profile_id}.{checkpoint_id}: {', '.join(missing_paths)}"))
                    path_count = len(selected_paths)
                    original_word_total = sum(word_count(value) for value in selected_texts.values())
                    word_total = original_word_total
                    projection_errors: list[str] = []
                    if receiver_measurement == "projected_instruction_content" and isinstance(projection_registry, dict):
                        word_total = 0
                        for kind, binding_id, binding_path in selected_bindings:
                            bound_text = selected_texts.get(binding_path)
                            if bound_text is None:
                                continue
                            projected_words, binding_errors = projected_binding_words(
                                text=bound_text,
                                path=binding_path,
                                kind=kind,
                                binding_id=binding_id,
                                profile_id=profile_id,
                                registry=projection_registry,
                            )
                            word_total += projected_words
                            projection_errors.extend(f"{binding_id}: {message}" for message in binding_errors)
                        if projection_errors:
                            errors.append(finding("runtime_projection_invalid", f"{profile_id}.{checkpoint_id}", "; ".join(projection_errors)))
                    label = f"{profile_id}.{checkpoint_id}"
                    if isinstance(thresholds.get("target_paths"), int) and path_count > thresholds["target_paths"]:
                        warnings.append(finding("runtime_target_exceeded", label, f"selected path count {path_count} exceeds target {thresholds['target_paths']} ({threshold_source})"))
                    if isinstance(thresholds.get("target_words"), int) and word_total > thresholds["target_words"]:
                        warnings.append(finding("runtime_target_exceeded", label, f"selected word count {word_total} exceeds target {thresholds['target_words']} ({threshold_source})"))
                    if isinstance(thresholds.get("reviewed_ceiling_paths"), int) and path_count > thresholds["reviewed_ceiling_paths"]:
                        errors.append(finding("runtime_reviewed_ceiling_exceeded", label, f"selected path count {path_count} exceeds reviewed ceiling {thresholds['reviewed_ceiling_paths']}"))
                    if isinstance(thresholds.get("reviewed_ceiling_words"), int) and word_total > thresholds["reviewed_ceiling_words"]:
                        errors.append(finding("runtime_reviewed_ceiling_exceeded", label, f"selected word count {word_total} exceeds reviewed ceiling {thresholds['reviewed_ceiling_words']}"))
                    runtime_rows.append(
                        {
                            "profile_id": profile_id,
                            "checkpoint_id": checkpoint_id,
                            "selected_paths": selected_paths,
                            "selected_path_count": path_count,
                            "path_count": path_count,
                            "selected_word_count": word_total,
                            "word_count": word_total,
                            "registered_source_word_count": original_word_total,
                            "projection_errors": projection_errors,
                            "threshold_source": threshold_source,
                            "thresholds": dict(thresholds),
                            "missing_bindings": missing_bindings,
                            "missing_paths": missing_paths,
                        }
                    )
            runtime_measurement["unused_overrides"] = [
                f"{profile_id}.{checkpoint_id or '*'}"
                for profile_id, checkpoint_id in overrides_by_key
                if (profile_id, checkpoint_id) not in seen_override_keys
            ]
        elif registry_text is not None:
            errors.append(finding("runtime_registry_invalid", registry_path, "registry must be an object"))
        runtime_largest.extend(sorted(runtime_rows, key=lambda row: (-int(row["selected_word_count"]), row["profile_id"], row["checkpoint_id"]))[:5])
        runtime_measurement["status"] = "pass" if not any(row["path"] == registry_path for row in errors) and not any(row["code"].startswith("runtime_") for row in errors) else "fail"

    threshold = int(policy.get("measurement", {}).get("long_section_detail_index_threshold_words", 4000))
    seen_conditional_ids: set[str] = set()
    for row in policy.get("conditional_references", []):
        row_id = str(row["id"])
        path = str(row["path"])
        if row_id in seen_conditional_ids:
            errors.append(finding("duplicate_conditional_id", path, row_id))
        seen_conditional_ids.add(row_id)
        detail = text_for(path)
        indexed = text_for(str(row["indexed_by"]))
        routed = text_for(str(row["routed_by"]))
        words = word_count(detail) if detail is not None else 0
        if path in startup_paths:
            errors.append(finding("conditional_in_static_startup", path, "conditional detail must not be in a static startup profile"))
        if indexed is not None and str(row["indexed_token"]) not in indexed:
            errors.append(finding("conditional_index_missing", path, f"{row['indexed_by']} lacks {row['indexed_token']}"))
        if routed is not None and str(row["routed_token"]) not in routed:
            errors.append(finding("conditional_route_missing", path, f"{row['routed_by']} lacks {row['routed_token']}"))
        if routed is not None:
            try:
                active = re.search(str(row["activation_pattern"]), routed, flags=re.MULTILINE) is not None
            except re.error as exc:
                errors.append(finding("activation_pattern_invalid", path, str(exc)))
                active = False
            if not active:
                errors.append(finding("conditional_activation_missing", path, f"activation pattern not found in {row['routed_by']}"))
        missing_headings = []
        if detail is not None:
            detail_lines = set(detail.splitlines())
            missing_headings = [heading for heading in row["required_headings"] if heading not in detail_lines]
            for heading in missing_headings:
                errors.append(finding("conditional_heading_missing", path, heading))
            if row["load_mode"] == "section" and words >= threshold and "## Section Index" not in detail_lines:
                errors.append(finding("long_section_detail_index_missing", path, f"{words} words requires ## Section Index"))
        conditional_rows.append({"id": row_id, "path": path, "load_mode": row["load_mode"], "words": words, "missing_headings": missing_headings})

    seen_invariant_ids: set[str] = set()
    invariant_marker_pattern = re.compile(r"<!-- idol-invariant: [a-z0-9_]+ -->")
    for row in policy.get("protected_invariants", []):
        row_id = str(row["id"])
        path = str(row["path"])
        if row_id in seen_invariant_ids:
            errors.append(finding("duplicate_invariant_id", path, row_id))
        seen_invariant_ids.add(row_id)
        text = text_for(path)
        marker = str(row["marker"])
        missing_terms: list[str] = []
        detail_missing_terms: list[str] = []
        if text is None or marker not in text:
            errors.append(finding("invariant_marker_missing", path, row_id))
        else:
            start = text.index(marker)
            next_match = invariant_marker_pattern.search(text, start + len(marker))
            stanza = text[start:next_match.start() if next_match else len(text)]
            # Markdown wraps semantic phrases across lines. Normalize whitespace
            # so the invariant audit checks meaning-bearing terms rather than
            # layout choices.
            folded = re.sub(r"\s+", " ", stanza).casefold()
            root_terms = row.get("root_required_terms")
            if root_terms is None:
                root_terms = row.get("required_terms", [])
            missing_terms = [str(term) for term in root_terms if str(term).casefold() not in folded]
            for term in missing_terms:
                errors.append(finding("invariant_term_missing", path, f"{row_id}: {term}"))

        detail_path = row.get("detail_path")
        detail_heading = row.get("detail_heading")
        detail_terms = row.get("detail_required_terms")
        if detail_path is not None:
            detail_path = str(detail_path)
            detail_text = text_for(detail_path)
            if detail_terms is None:
                detail_terms = row.get("required_terms", [])
            detail_stanza = detail_text
            if detail_text is not None and detail_heading:
                detail_stanza = heading_stanza(detail_text, str(detail_heading))
                if detail_stanza is None:
                    errors.append(finding("invariant_detail_heading_missing", detail_path, f"{row_id}: {detail_heading}"))
            if detail_stanza is not None:
                folded_detail = re.sub(r"\s+", " ", detail_stanza).casefold()
                detail_missing_terms = [str(term) for term in detail_terms if str(term).casefold() not in folded_detail]
                for term in detail_missing_terms:
                    errors.append(finding("invariant_detail_term_missing", detail_path, f"{row_id}: {term}"))
        elif detail_terms is not None or row.get("detail_heading") is not None or row.get("additional_detail_sources"):
            errors.append(finding("invariant_detail_path_missing", path, row_id))

        additional_sources = row.get("additional_detail_sources", [])
        if additional_sources is not None and not isinstance(additional_sources, list):
            errors.append(finding("invariant_detail_source_invalid", path, row_id))
            additional_sources = []
        for source in additional_sources:
            if not isinstance(source, dict):
                errors.append(finding("invariant_detail_source_invalid", path, row_id))
                continue
            source_path = str(source.get("path", ""))
            source_heading = source.get("heading")
            source_text = text_for(source_path) if source_path else None
            if source_text is None:
                continue
            source_stanza = source_text
            if source_heading:
                source_stanza = heading_stanza(source_text, str(source_heading))
                if source_stanza is None:
                    errors.append(finding("invariant_detail_heading_missing", source_path, f"{row_id}: {source_heading}"))
                    continue
            source_terms = source.get("required_terms", [])
            folded_source = re.sub(r"\s+", " ", source_stanza).casefold()
            source_missing_terms = [str(term) for term in source_terms if str(term).casefold() not in folded_source]
            detail_missing_terms.extend(source_missing_terms)
            for term in source_missing_terms:
                errors.append(finding("invariant_detail_term_missing", source_path, f"{row_id}: {term}"))
        invariant_rows.append({"id": row_id, "path": path, "missing_terms": missing_terms, "detail_missing_terms": detail_missing_terms})

    seen_routing_contract_ids: set[str] = set()
    for row in policy.get("routing_consistency_contracts", []):
        row_id = str(row["id"])
        path = str(row["path"])
        if row_id in seen_routing_contract_ids:
            errors.append(finding("duplicate_routing_contract_id", path, row_id))
        seen_routing_contract_ids.add(row_id)
        text = text_for(path)
        folded = re.sub(r"\s+", " ", text).casefold() if text is not None else ""
        owner_path = row.get("canonical_owner_path")
        cite_term = row.get("consumer_cite_term")
        term_path = str(owner_path) if owner_path else path
        term_text = text_for(term_path) if owner_path else text
        term_folded = re.sub(r"\s+", " ", term_text).casefold() if term_text is not None else ""
        missing_terms = [
            str(term)
            for term in row.get("required_terms", [])
            if str(term).casefold() not in term_folded
        ]
        forbidden_terms = [
            str(term)
            for term in row.get("forbidden_terms", [])
            if str(term).casefold() in folded
        ]
        if owner_path and cite_term and (not folded or str(cite_term).casefold() not in folded):
            errors.append(finding("routing_contract_cite_missing", path, f"{row_id}: {cite_term}"))
        for term in missing_terms:
            errors.append(finding("routing_contract_term_missing", term_path, f"{row_id}: {term}"))
        for term in forbidden_terms:
            errors.append(finding("routing_contract_forbidden_term", path, f"{row_id}: {term}"))
        routing_contract_rows.append(
            {
                "id": row_id,
                "path": path,
                "missing_terms": missing_terms,
                "forbidden_terms": forbidden_terms,
            }
        )

    history = policy.get("maintenance_history", {})
    active_path = str(history.get("active_path", ""))
    frozen_path = str(history.get("frozen_path", ""))
    active = text_for(active_path) if active_path else None
    frozen = text_for(frozen_path) if frozen_path else None
    if active is not None:
        pointer = str(history.get("active_pointer_required", ""))
        if pointer not in active:
            errors.append(finding("history_pointer_missing", active_path, pointer))
        for pattern in history.get("active_forbidden_patterns", []):
            try:
                if re.search(str(pattern), active, flags=re.MULTILINE):
                    errors.append(finding("active_history_append_pattern", active_path, str(pattern)))
            except re.error as exc:
                errors.append(finding("history_pattern_invalid", active_path, str(exc)))
    frozen_words = word_count(frozen) if frozen is not None else 0
    if frozen is not None:
        marker = str(history.get("frozen_status_marker", ""))
        if marker not in frozen:
            errors.append(finding("frozen_history_marker_missing", frozen_path, marker))
        maximum = int(history.get("frozen_max_words", 0))
        if frozen_words > maximum:
            errors.append(finding("frozen_history_grew", frozen_path, f"{frozen_words} words exceeds frozen maximum {maximum}"))
    if history.get("frozen_excluded_from_startup_profiles") is True and frozen_path in startup_paths:
        errors.append(finding("frozen_history_in_startup", frozen_path, "frozen history must not enter startup profiles"))

    return {
        "status": "pass" if not errors else "fail",
        "priority": policy.get("priority"),
        "size_change_control": {
            "finding_authority": measurement.get("size_finding_authority"),
            "remediation_authority": measurement.get("size_remediation_authority"),
            "automatic_remediation": measurement.get("automatic_size_remediation"),
        },
        "surfaces": surface_rows,
        "startup_profiles": profile_rows,
        "runtime_load_measurement": runtime_measurement,
        "conditional_references": conditional_rows,
        "protected_invariants": invariant_rows,
        "routing_consistency_contracts": routing_contract_rows,
        "maintenance_history": {
            "active_path": active_path,
            "frozen_path": frozen_path,
            "frozen_words": frozen_words,
            "excluded_from_startup": frozen_path not in startup_paths,
        },
        "warnings": warnings,
        "errors": errors,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO_ROOT)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        policy = load_policy(args.policy)
        report = audit(args.root.resolve(), policy)
    except (OSError, UnicodeError, ValueError, yaml.YAMLError) as exc:
        report = {"status": "fail", "warnings": [], "errors": [{"code": "audit_setup_failed", "path": str(args.policy), "message": str(exc)}]}

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"instruction surface audit: {report['status'].upper()}")
        for row in report.get("startup_profiles", []):
            print(f"  static bootstrap {row['id']}: {row['words']} words")
        runtime = report.get("runtime_load_measurement", {})
        for row in runtime.get("largest_checkpoints", []):
            print(
                f"  runtime {row['profile_id']}.{row['checkpoint_id']}: "
                f"{row['selected_path_count']} paths / {row['selected_word_count']} words"
            )
        for row in report.get("warnings", []):
            print(f"WARNING {row['code']} {row['path']}: {row['message']}")
        for row in report.get("errors", []):
            print(f"ERROR {row['code']} {row['path']}: {row['message']}")
    return 0 if report.get("status") == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
