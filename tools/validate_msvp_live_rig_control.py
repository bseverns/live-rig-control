#!/usr/bin/env python3
"""Validate live-rig-control and MSVP interop files against the canonical contract."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        raise SystemExit(f"Missing file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON/YAML in {path}: {exc}")


def add_mismatch(errors: list[str], scope: str, field: str, actual: Any, expected: Any) -> None:
    errors.append(f"{scope}: {field} is {actual!r}, expected {expected!r}")


def collect_all_pads(profiles: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], list[str]]:
    pads_by_id: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for profile_id, profile in profiles.items():
        pads = profile.get("pads", [])
        if not isinstance(pads, list):
            errors.append(f"profile '{profile_id}' has non-list pads")
            continue
        for pad in pads:
            pad_id = pad.get("id")
            if not isinstance(pad_id, str) or not pad_id:
                errors.append(f"profile '{profile_id}' contains a pad without a valid id")
                continue
            if pad_id in pads_by_id:
                errors.append(f"duplicate pad id '{pad_id}'")
                continue
            pads_by_id[pad_id] = pad
    return pads_by_id, errors


def profile_pads_by_id(profile: dict[str, Any], profile_id: str) -> tuple[dict[str, dict[str, Any]], list[str]]:
    pads = profile.get("pads", [])
    if not isinstance(pads, list):
        return {}, [f"profile '{profile_id}' has non-list pads"]
    result: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for pad in pads:
        pad_id = pad.get("id")
        if not isinstance(pad_id, str) or not pad_id:
            errors.append(f"profile '{profile_id}' contains a pad without a valid id")
            continue
        if pad_id in result:
            errors.append(f"profile '{profile_id}' has duplicate pad id '{pad_id}'")
            continue
        result[pad_id] = pad
    return result, errors


def validate_controller_lane(
    errors: list[str],
    scope_prefix: str,
    pads_by_id: dict[str, dict[str, Any]],
    lane_name: str,
    lane_contract: dict[str, Any],
) -> None:
    for item in lane_contract["parameters"]:
        pad_id = item["pad_id"]
        pad = pads_by_id.get(pad_id)
        if pad is None:
            errors.append(f"{scope_prefix}: missing {lane_name} pad '{pad_id}'")
            continue
        midi = pad.get("midi", {})
        if midi.get("type") != "cc":
            add_mismatch(errors, f"{scope_prefix}:{pad_id}", "midi.type", midi.get("type"), "cc")
        if midi.get("channel") != lane_contract["channel"]:
            add_mismatch(
                errors,
                f"{scope_prefix}:{pad_id}",
                "midi.channel",
                midi.get("channel"),
                lane_contract["channel"],
            )
        if midi.get("cc") != item["cc"]:
            add_mismatch(errors, f"{scope_prefix}:{pad_id}", "midi.cc", midi.get("cc"), item["cc"])
        if lane_contract.get("controller_emits_osc_mirror") is False and "osc" in pad:
            errors.append(f"{scope_prefix}:{pad_id}: controller should not emit OSC for {lane_name} lane")


def validate_live_rig(mappings_path: Path, contract: dict[str, Any]) -> tuple[list[str], list[str]]:
    data = load_json(mappings_path)
    profiles = data.get("profiles")
    if not isinstance(profiles, dict):
        return [f"{mappings_path}: missing profiles object"], []

    controller = contract["controller_surface"]
    profile_id = controller["profile_id"]
    profile = profiles.get(profile_id)
    if not isinstance(profile, dict):
        return [f"{mappings_path}: missing controller profile '{profile_id}'"], []

    all_pads, global_errors = collect_all_pads(profiles)
    profile_pads, profile_errors = profile_pads_by_id(profile, profile_id)
    errors = [f"{mappings_path}: {msg}" for msg in (global_errors + profile_errors)]
    checks: list[str] = []

    if profile.get("label") != controller["label"]:
        add_mismatch(errors, f"{mappings_path}:{profile_id}", "label", profile.get("label"), controller["label"])
    if profile.get("section") != controller["section"]:
        add_mismatch(errors, f"{mappings_path}:{profile_id}", "section", profile.get("section"), controller["section"])
    if profile.get("order") != controller["order"]:
        add_mismatch(errors, f"{mappings_path}:{profile_id}", "order", profile.get("order"), controller["order"])

    scene_contract = contract["controls"]["scene_triggers"]
    expected_scenes = {scene["semantic_id"]: scene for scene in scene_contract["scenes"]}
    for scene_id, expected in expected_scenes.items():
        pad = profile_pads.get(scene_id)
        if pad is None:
            errors.append(f"{mappings_path}: missing scene pad '{scene_id}' in profile '{profile_id}'")
            continue
        osc = pad.get("osc", {})
        if osc.get("address") != expected["osc_address"]:
            add_mismatch(errors, f"{mappings_path}:{scene_id}", "osc.address", osc.get("address"), expected["osc_address"])
        if controller["scene_midi_fallback_emitted_by_controller"] is False and "midi" in pad:
            errors.append(f"{mappings_path}:{scene_id}: controller should not emit MIDI note fallback on this profile")

    for pad_id in sorted(all_pads):
        if pad_id.startswith("vid_scene_") and pad_id not in expected_scenes:
            errors.append(f"{mappings_path}: unknown semantic ID '{pad_id}'")

    validate_controller_lane(errors, str(mappings_path), profile_pads, "macro", contract["controls"]["macro_lane"])
    validate_controller_lane(
        errors,
        str(mappings_path),
        profile_pads,
        "analysis",
        contract["controls"]["analysis_lane"],
    )

    if not errors:
        checks.append(
            f"{mappings_path}: profile '{profile_id}' matches OSC scenes plus macro ch {contract['controls']['macro_lane']['channel']} and analysis ch {contract['controls']['analysis_lane']['channel']}"
        )
        checks.append(
            f"{mappings_path}: controller keeps scene commands OSC-only and exposes 7 macro + 7 analysis controls"
        )
    return errors, checks


def get_msvp_profile(data: dict[str, Any]) -> tuple[str | None, dict[str, Any] | None]:
    runtime = data.get("runtime", {})
    requested_profile = runtime.get("profile")
    profiles = data.get("profiles", {})
    if isinstance(requested_profile, str) and isinstance(profiles, dict):
        profile = profiles.get(requested_profile)
        if isinstance(profile, dict):
            return requested_profile, profile
    if isinstance(profiles, dict) and len(profiles) == 1:
        profile_id, profile = next(iter(profiles.items()))
        if isinstance(profile, dict):
            return profile_id, profile
    return None, None


def validate_endpoint_lane(
    errors: list[str],
    pads_by_id: dict[str, dict[str, Any]],
    interop_path: Path,
    lane_name: str,
    lane_contract: dict[str, Any],
) -> None:
    expected_channel = lane_contract["channel"]
    expected_prefix = lane_contract["osc_equivalent_prefix"]
    expected_by_param = {item["name"]: item for item in lane_contract["parameters"]}
    actual_by_param: dict[str, dict[str, Any]] = {}

    for pad_id, pad in pads_by_id.items():
        osc = pad.get("osc", {})
        address = osc.get("address")
        if not isinstance(address, str) or not address.startswith(expected_prefix):
            continue
        param_name = address[len(expected_prefix) :]
        if param_name in actual_by_param:
            errors.append(f"{interop_path}: duplicate {lane_name} OSC binding for '{param_name}'")
            continue
        actual_by_param[param_name] = {"pad_id": pad_id, "pad": pad}

    for param_name, expected in expected_by_param.items():
        payload = actual_by_param.get(param_name)
        if payload is None:
            errors.append(f"{interop_path}: missing {lane_name} parameter '{param_name}'")
            continue
        pad = payload["pad"]
        midi = pad.get("midi", {})
        scope = f"{interop_path}:{payload['pad_id']}"
        if midi.get("type") != "cc":
            add_mismatch(errors, scope, "midi.type", midi.get("type"), "cc")
        if midi.get("channel") != expected_channel:
            add_mismatch(errors, scope, "midi.channel", midi.get("channel"), expected_channel)
        if midi.get("cc") != expected["cc"]:
            add_mismatch(errors, scope, "midi.cc", midi.get("cc"), expected["cc"])

    for param_name in sorted(actual_by_param):
        if param_name not in expected_by_param:
            errors.append(f"{interop_path}: unknown {lane_name} parameter '{param_name}'")


def validate_msvp(interop_path: Path, contract: dict[str, Any]) -> tuple[list[str], list[str]]:
    data = load_json(interop_path)
    runtime = data.get("runtime", {})
    midi_runtime = runtime.get("midi", {}) if isinstance(runtime, dict) else {}
    profile_id, profile = get_msvp_profile(data)
    if profile is None:
        return [f"{interop_path}: no usable profile found"], []

    pads_by_id, profile_errors = profile_pads_by_id(profile, profile_id)
    errors = [f"{interop_path}: {msg}" for msg in profile_errors]
    checks: list[str] = []

    scene_contract = contract["controls"]["scene_triggers"]
    macro_contract = contract["controls"]["macro_lane"]
    analysis_contract = contract["controls"]["analysis_lane"]
    expected_scenes = {scene["semantic_id"]: scene for scene in scene_contract["scenes"]}

    if midi_runtime.get("macroChannel") != macro_contract["channel"]:
        add_mismatch(
            errors,
            str(interop_path),
            "runtime.midi.macroChannel",
            midi_runtime.get("macroChannel"),
            macro_contract["channel"],
        )
    if midi_runtime.get("analysisChannel") != analysis_contract["channel"]:
        add_mismatch(
            errors,
            str(interop_path),
            "runtime.midi.analysisChannel",
            midi_runtime.get("analysisChannel"),
            analysis_contract["channel"],
        )

    for scene_id, expected in expected_scenes.items():
        pad = pads_by_id.get(scene_id)
        if pad is None:
            errors.append(f"{interop_path}: missing scene pad '{scene_id}'")
            continue
        midi = pad.get("midi", {})
        osc = pad.get("osc", {})
        scope = f"{interop_path}:{scene_id}"
        if midi.get("type") != "note":
            add_mismatch(errors, scope, "midi.type", midi.get("type"), "note")
        if midi.get("channel") != scene_contract["msvp_receive_channel"]:
            add_mismatch(
                errors,
                scope,
                "midi.channel",
                midi.get("channel"),
                scene_contract["msvp_receive_channel"],
            )
        if midi.get("note") != expected["midi_note"]:
            add_mismatch(errors, scope, "midi.note", midi.get("note"), expected["midi_note"])
        if osc.get("address") != expected["osc_address"]:
            add_mismatch(errors, scope, "osc.address", osc.get("address"), expected["osc_address"])

    for pad_id in sorted(pads_by_id):
        if pad_id.startswith("vid_scene_") and pad_id not in expected_scenes:
            errors.append(f"{interop_path}: unknown semantic ID '{pad_id}'")

    validate_endpoint_lane(errors, pads_by_id, interop_path, "macro", macro_contract)
    validate_endpoint_lane(errors, pads_by_id, interop_path, "analysis", analysis_contract)

    if not errors:
        checks.append(
            f"{interop_path}: scenes match canonical IDs, OSC addresses, note fallback, macro ch {macro_contract['channel']}, analysis ch {analysis_contract['channel']}"
        )
        checks.append(
            f"{interop_path}: macro and analysis expose {len(macro_contract['parameters'])} canonical parameters each"
        )
    return errors, checks


def parse_args() -> tuple[argparse.Namespace, Path, Path]:
    repo_root = Path(__file__).resolve().parents[1]
    default_contract = repo_root / "contracts" / "msvp_live_rig_control.yaml"
    default_live_rig = repo_root / "src" / "mappings.json"
    default_msvp = repo_root.parent / "MSVP" / "MidiVideoSyphonBeats" / "data" / "live_rig_interop.json"

    parser = argparse.ArgumentParser(
        description="Validate live-rig-control and MSVP files against the canonical MSVP/live-rig contract."
    )
    parser.add_argument("--contract", type=Path, default=default_contract, help="Path to the canonical contract file.")
    parser.add_argument(
        "--live-rig-mappings",
        type=Path,
        default=None,
        help="Path to a live-rig-control mappings.json file. Defaults to src/mappings.json when no explicit target is selected.",
    )
    parser.add_argument(
        "--msvp-interop",
        type=Path,
        default=None,
        help="Path to MSVP's live_rig_interop.json. Defaults to the sibling MSVP checkout when no explicit target is selected.",
    )
    return parser.parse_args(), default_live_rig, default_msvp


def main() -> int:
    args, default_live_rig, default_msvp = parse_args()
    contract_root = load_json(args.contract)
    contract = contract_root.get("contract")
    if not isinstance(contract, dict):
        print(f"ERROR {args.contract}: missing top-level 'contract' object")
        return 1

    selected_targets: list[tuple[str, Path]] = []
    if args.live_rig_mappings is not None:
        selected_targets.append(("live-rig-control", args.live_rig_mappings))
    if args.msvp_interop is not None:
        selected_targets.append(("MSVP", args.msvp_interop))
    if not selected_targets:
        selected_targets.append(("live-rig-control", default_live_rig))
        if default_msvp.exists():
            selected_targets.append(("MSVP", default_msvp))

    errors: list[str] = []
    checks: list[str] = [f"Contract {contract['name']} v{contract['version']}"]

    for target_name, path in selected_targets:
        if target_name == "live-rig-control":
            target_errors, target_checks = validate_live_rig(path, contract)
        else:
            target_errors, target_checks = validate_msvp(path, contract)
        errors.extend(target_errors)
        checks.extend(target_checks)

    if errors:
        print("FAIL")
        for item in checks:
            print(f"  {item}")
        for err in errors:
            print(f"  ERROR: {err}")
        return 1

    print("PASS")
    for item in checks:
        print(f"  {item}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
