"""Shared machine contract for IDOL 04FX effect compile and render.

Creative selection remains in 04FX. This module only canonicalizes catalog
names and rejects parameters the local renderer contract cannot honor.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY_PATH = ROOT / "automation" / "edit-effect-registry.yaml"


class EffectContractError(ValueError):
    """Raised when an effect cannot satisfy the machine registry."""


class UniqueKeyLoader(yaml.SafeLoader):
    """Fail closed when YAML silently attempts to replace a declared key."""


def _construct_unique_mapping(
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
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_unique_mapping
)


def load_unique_yaml(path: Path) -> Any:
    return yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)


@dataclass(frozen=True)
class EffectRegistry:
    payload: dict[str, Any]

    @property
    def effects(self) -> dict[str, dict[str, Any]]:
        return self.payload["effects"]

    @property
    def transitions(self) -> set[str]:
        return set(self.payload["xfade_transitions"])

    @property
    def aliases(self) -> dict[str, str]:
        result: dict[str, str] = {}
        for canonical, spec in self.effects.items():
            result[canonical] = canonical
            for alias in spec.get("aliases", []):
                if alias in result and result[alias] != canonical:
                    raise EffectContractError(
                        f"effect alias {alias!r} maps to multiple canonical types"
                    )
                result[alias] = canonical
        return result

    def canonical_type(self, value: Any) -> str:
        raw = str(value or "").strip()
        if not raw:
            raise EffectContractError("missing effect type")
        canonical = self.aliases.get(raw)
        if canonical is None:
            raise EffectContractError(
                f"unsupported effect type {raw!r}; registry has "
                + ", ".join(sorted(self.effects))
            )
        return canonical

    def effect_spec(self, value: Any) -> tuple[str, dict[str, Any]]:
        canonical = self.canonical_type(value)
        return canonical, self.effects[canonical]

    def validate_parameters(
        self,
        effect_type: Any,
        parameters: dict[str, Any],
        *,
        require_final_xfade_handles: bool = False,
    ) -> dict[str, Any]:
        canonical, effect_spec = self.effect_spec(effect_type)
        if not isinstance(parameters, dict):
            raise EffectContractError(f"{canonical}: parameters must be a mapping")

        common = self.payload["common_parameters"]
        named = self.payload["parameter_specs"]
        allowed_names = set(common) | set(effect_spec.get("parameters", []))
        unknown = sorted(set(parameters) - allowed_names)
        if unknown:
            raise EffectContractError(
                f"{canonical}: unsupported parameters: {', '.join(unknown)}"
            )

        missing = [
            name
            for name in effect_spec.get("required_parameters", [])
            if parameters.get(name) in (None, "")
        ]
        if canonical == "xfade" and not require_final_xfade_handles:
            missing = [
                name for name in missing if name != "transition_handle_contract"
            ]
        if missing:
            raise EffectContractError(
                f"{canonical}: missing required parameters: {', '.join(missing)}"
            )

        for name, value in parameters.items():
            spec = common.get(name) or named.get(name)
            if spec is None:
                raise EffectContractError(f"{canonical}: no parameter spec for {name}")
            self._validate_value(canonical, name, value, spec)

        if canonical == "xfade":
            transition = str(
                parameters.get("transition")
                or parameters.get("xfade_transition")
                or "fade"
            )
            if transition not in self.transitions:
                raise EffectContractError(
                    f"xfade: unsupported transition {transition!r}; custom expressions "
                    "are not accepted by the current local contract"
                )
            handles = parameters.get("transition_handle_contract")
            if handles is not None:
                validate_handle_contract(handles)
            elif require_final_xfade_handles:
                raise EffectContractError(
                    "xfade: final render requires a duration-preserving handle_contract"
                )

        return {**parameters, "type": canonical}

    @staticmethod
    def _validate_value(
        effect_type: str, name: str, value: Any, spec: dict[str, Any]
    ) -> None:
        expected = spec["type"]
        valid = True
        if expected == "number":
            valid = isinstance(value, (int, float)) and not isinstance(value, bool)
        elif expected == "integer":
            valid = isinstance(value, int) and not isinstance(value, bool)
        elif expected == "string":
            valid = isinstance(value, str)
        elif expected == "object":
            valid = isinstance(value, dict)
        elif expected == "color":
            valid = (
                isinstance(value, str)
                and re.fullmatch(
                    r"(?:#[0-9A-Fa-f]{6}|0x[0-9A-Fa-f]{6}|[A-Za-z][A-Za-z0-9_-]{0,31})",
                    value,
                )
                is not None
            ) or (
                isinstance(value, (list, tuple))
                and len(value) == 3
                and all(
                    isinstance(channel, int)
                    and not isinstance(channel, bool)
                    and 0 <= channel <= 255
                    for channel in value
                )
            )
        if not valid:
            raise EffectContractError(
                f"{effect_type}: parameter {name} must be {expected}"
            )

        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if "minimum" in spec and value < spec["minimum"]:
                raise EffectContractError(
                    f"{effect_type}: parameter {name} is below {spec['minimum']}"
                )
            if "exclusive_minimum" in spec and value <= spec["exclusive_minimum"]:
                raise EffectContractError(
                    f"{effect_type}: parameter {name} must exceed "
                    f"{spec['exclusive_minimum']}"
                )
            if "maximum" in spec and value > spec["maximum"]:
                raise EffectContractError(
                    f"{effect_type}: parameter {name} exceeds {spec['maximum']}"
                )
        if "enum" in spec and value not in spec["enum"]:
            raise EffectContractError(
                f"{effect_type}: parameter {name} must be one of {spec['enum']}"
            )
        if isinstance(value, str):
            if "min_length" in spec and len(value) < int(spec["min_length"]):
                raise EffectContractError(
                    f"{effect_type}: parameter {name} is shorter than {spec['min_length']} characters"
                )
            if "max_length" in spec and len(value) > int(spec["max_length"]):
                raise EffectContractError(
                    f"{effect_type}: parameter {name} exceeds {spec['max_length']} characters"
                )
            if "pattern" in spec and re.fullmatch(str(spec["pattern"]), value) is None:
                raise EffectContractError(
                    f"{effect_type}: parameter {name} contains unsupported filter syntax"
                )
            if "forbidden_pattern" in spec and re.search(
                str(spec["forbidden_pattern"]), value
            ):
                raise EffectContractError(
                    f"{effect_type}: parameter {name} contains a forbidden control character"
                )


def validate_handle_contract(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise EffectContractError("xfade handle_contract must be a mapping")
    required = {
        "mode",
        "fixed_program_cut_frame",
        "transition_frames",
        "pre_cut_frames",
        "post_cut_frames",
    }
    missing = sorted(required - set(value))
    if missing:
        raise EffectContractError(
            "xfade handle_contract missing: " + ", ".join(missing)
        )
    if value.get("mode") != "duration_preserving":
        raise EffectContractError(
            "xfade handle_contract.mode must be duration_preserving"
        )
    frame_fields = ("transition_frames", "pre_cut_frames", "post_cut_frames")
    for field in frame_fields:
        item = value.get(field)
        if not isinstance(item, int) or isinstance(item, bool) or item < 0:
            raise EffectContractError(f"xfade handle_contract.{field} must be an integer >= 0")
    if value["transition_frames"] <= 0:
        raise EffectContractError("xfade handle_contract.transition_frames must be > 0")
    if value["pre_cut_frames"] + value["post_cut_frames"] != value["transition_frames"]:
        raise EffectContractError(
            "xfade handle_contract pre_cut_frames + post_cut_frames must equal "
            "transition_frames"
        )
    fixed_frame = value.get("fixed_program_cut_frame")
    if not isinstance(fixed_frame, int) or isinstance(fixed_frame, bool) or fixed_frame < 0:
        raise EffectContractError(
            "xfade handle_contract.fixed_program_cut_frame must be an integer >= 0"
        )
    for field in ("fixed_program_cut_seconds",):
        if field not in value:
            continue
        item = value.get(field)
        if not isinstance(item, (int, float)) or isinstance(item, bool) or item < 0:
            raise EffectContractError(f"xfade handle_contract.{field} must be a number >= 0")
    return value


def load_effect_registry(path: Path | None = None) -> EffectRegistry:
    registry_path = path or DEFAULT_REGISTRY_PATH
    payload = load_unique_yaml(registry_path) or {}
    if not isinstance(payload, dict):
        raise EffectContractError(f"effect registry must be a mapping: {registry_path}")
    if payload.get("schema_version") != "idol_edit_effect_registry.v1":
        raise EffectContractError(
            f"unsupported effect registry version: {payload.get('schema_version')!r}"
        )
    registry = EffectRegistry(payload)
    aliases = registry.aliases
    if len(aliases) < len(registry.effects):
        raise EffectContractError("effect registry alias table is incomplete")
    all_specs = set(payload.get("common_parameters", {})) | set(
        payload.get("parameter_specs", {})
    )
    for effect_type, spec in registry.effects.items():
        unknown = set(spec.get("parameters", [])) - all_specs
        if unknown:
            raise EffectContractError(
                f"{effect_type}: registry parameters have no spec: {sorted(unknown)}"
            )
        missing_required = set(spec.get("required_parameters", [])) - set(
            spec.get("parameters", [])
        )
        if missing_required:
            raise EffectContractError(
                f"{effect_type}: required parameters are not declared: "
                f"{sorted(missing_required)}"
            )
    return registry
