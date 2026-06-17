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


def notes_have_tags(notes: Any, expected_tags: dict[str, str]) -> bool:
    if not isinstance(notes, str):
        return False
    tokens = notes.replace(",", " ").replace(";", " ").split()
    found: dict[str, str] = {}
    for token in tokens:
        if ":" not in token:
            continue
        key, value = token.split(":", 1)
        found[key.strip().lower()] = value.strip()
    return all(found.get(key.lower()) == value for key, value in expected_tags.items())


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

    allowed_additional_ids = set(controller.get("allowed_additional_semantic_ids", []))
    for pad_id in sorted(all_pads):
        if pad_id in allowed_additional_ids:
            continue
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
    requested_profile = runtime.get("profile") if isinstance(runtime, dict) else None
    profiles = data.get("profiles", {})
    if isinstance(requested_profile, str) and isinstance(profiles, dict):
        profile = profiles.get(requested_profile)
        if isinstance(profile, dict):
            return requested_profile, profile
    if isinstance(profiles, dict):
        profile = profiles.get("msvp")
        if isinstance(profile, dict):
            return "msvp", profile
        profile = profiles.get("default")
        if isinstance(profile, dict):
            return "default", profile
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
    expected_ids = {item["pad_id"] for item in lane_contract["parameters"]}
    actual_by_param: dict[str, str] = {}

    for pad_id, pad in pads_by_id.items():
        osc = pad.get("osc", {})
        address = osc.get("address")
        if not isinstance(address, str) or not address.startswith(expected_prefix):
            continue
        param_name = address[len(expected_prefix) :]
        if param_name in actual_by_param:
            errors.append(f"{interop_path}: duplicate {lane_name} OSC binding for '{param_name}'")
            continue
        actual_by_param[param_name] = pad_id

    for param_name, expected in expected_by_param.items():
        pad_id = expected["pad_id"]
        pad = pads_by_id.get(pad_id)
        if pad is None:
            errors.append(f"{interop_path}: missing {lane_name} pad '{pad_id}'")
            continue
        midi = pad.get("midi", {})
        osc = pad.get("osc", {})
        scope = f"{interop_path}:{pad_id}"
        if midi.get("type") != "cc":
            add_mismatch(errors, scope, "midi.type", midi.get("type"), "cc")
        if midi.get("channel") != expected_channel:
            add_mismatch(errors, scope, "midi.channel", midi.get("channel"), expected_channel)
        if midi.get("cc") != expected["cc"]:
            add_mismatch(errors, scope, "midi.cc", midi.get("cc"), expected["cc"])
        expected_address = expected_prefix + param_name
        if osc.get("address") != expected_address:
            add_mismatch(errors, scope, "osc.address", osc.get("address"), expected_address)
        if osc.get("args") != [0.5]:
            add_mismatch(errors, scope, "osc.args", osc.get("args"), [0.5])
        if not notes_have_tags(pad.get("notes"), {"lane": lane_name, "target": param_name, "normalized": "0..1"}):
            errors.append(f"{scope}: notes must tag lane:{lane_name} target:{param_name} normalized:0..1")

    for param_name in sorted(actual_by_param):
        if param_name not in expected_by_param:
            errors.append(f"{interop_path}: unknown {lane_name} parameter '{param_name}'")
    for pad_id in sorted(pads_by_id):
        if pad_id.startswith(f"msvp_{lane_name}_") and pad_id not in expected_ids:
            errors.append(f"{interop_path}: unknown {lane_name} pad '{pad_id}'")


def validate_msvp_runtime(
    errors: list[str],
    interop_path: Path,
    data: dict[str, Any],
    contract: dict[str, Any],
) -> None:
    endpoint_runtime = contract.get("endpoint_runtime", {})
    if not isinstance(endpoint_runtime, dict):
        return

    if data.get("interopVersion") != endpoint_runtime.get("interop_version"):
        add_mismatch(
            errors,
            str(interop_path),
            "interopVersion",
            data.get("interopVersion"),
            endpoint_runtime.get("interop_version"),
        )

    runtime = data.get("runtime")
    if not isinstance(runtime, dict):
        errors.append(f"{interop_path}: runtime must be an object")
        return

    if runtime.get("profile") != endpoint_runtime.get("profile"):
        add_mismatch(errors, str(interop_path), "runtime.profile", runtime.get("profile"), endpoint_runtime.get("profile"))
    if runtime.get("rigTunedMode") != endpoint_runtime.get("rig_tuned_mode_default"):
        add_mismatch(
            errors,
            str(interop_path),
            "runtime.rigTunedMode",
            runtime.get("rigTunedMode"),
            endpoint_runtime.get("rig_tuned_mode_default"),
        )

    midi_runtime = runtime.get("midi")
    if not isinstance(midi_runtime, dict):
        errors.append(f"{interop_path}: runtime.midi must be an object")
    else:
        midi_expected = endpoint_runtime.get("midi", {})
        if midi_runtime.get("preferredInput") != midi_expected.get("preferred_input"):
            add_mismatch(
                errors,
                str(interop_path),
                "runtime.midi.preferredInput",
                midi_runtime.get("preferredInput"),
                midi_expected.get("preferred_input"),
            )
        if midi_runtime.get("macroChannel") != midi_expected.get("macro_channel"):
            add_mismatch(
                errors,
                str(interop_path),
                "runtime.midi.macroChannel",
                midi_runtime.get("macroChannel"),
                midi_expected.get("macro_channel"),
            )
        if midi_runtime.get("analysisChannel") != midi_expected.get("analysis_channel"):
            add_mismatch(
                errors,
                str(interop_path),
                "runtime.midi.analysisChannel",
                midi_runtime.get("analysisChannel"),
                midi_expected.get("analysis_channel"),
            )

    osc_runtime = runtime.get("osc")
    if not isinstance(osc_runtime, dict):
        errors.append(f"{interop_path}: runtime.osc must be an object")
    else:
        osc_expected = endpoint_runtime.get("osc", {})
        if osc_runtime.get("listenPort") != osc_expected.get("listen_port"):
            add_mismatch(
                errors,
                str(interop_path),
                "runtime.osc.listenPort",
                osc_runtime.get("listenPort"),
                osc_expected.get("listen_port"),
            )
        if osc_runtime.get("targetHost") != osc_expected.get("target_host"):
            add_mismatch(
                errors,
                str(interop_path),
                "runtime.osc.targetHost",
                osc_runtime.get("targetHost"),
                osc_expected.get("target_host"),
            )
        if osc_runtime.get("targetPort") != osc_expected.get("target_port"):
            add_mismatch(
                errors,
                str(interop_path),
                "runtime.osc.targetPort",
                osc_runtime.get("targetPort"),
                osc_expected.get("target_port"),
            )


def validate_msvp(interop_path: Path, contract: dict[str, Any]) -> tuple[list[str], list[str]]:
    data = load_json(interop_path)
    if not isinstance(data, dict):
        return [f"{interop_path}: root must be an object"], []

    profile_id, profile = get_msvp_profile(data)
    if profile is None:
        return [f"{interop_path}: no usable profile found"], []

    pads_by_id, profile_errors = profile_pads_by_id(profile, profile_id)
    errors = [f"{interop_path}: {msg}" for msg in profile_errors]
    checks: list[str] = []
    validate_msvp_runtime(errors, interop_path, data, contract)

    scene_contract = contract["controls"]["scene_triggers"]
    macro_contract = contract["controls"]["macro_lane"]
    analysis_contract = contract["controls"]["analysis_lane"]
    expected_scenes = {scene["semantic_id"]: scene for scene in scene_contract["scenes"]}
    scene_group_contract = scene_contract.get("endpoint_group", {})
    scene_midi_contract = scene_contract.get("endpoint_midi", {})
    scene_osc_contract = scene_contract.get("endpoint_osc", {})

    for scene_id, expected in expected_scenes.items():
        pad = pads_by_id.get(scene_id)
        if pad is None:
            errors.append(f"{interop_path}: missing scene pad '{scene_id}'")
            continue
        midi = pad.get("midi", {})
        osc = pad.get("osc", {})
        group = pad.get("group", {})
        scope = f"{interop_path}:{scene_id}"
        if pad.get("toggle") is not True:
            add_mismatch(errors, scope, "toggle", pad.get("toggle"), True)
        if pad.get("mode") != "toggle":
            add_mismatch(errors, scope, "mode", pad.get("mode"), "toggle")
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
        if midi.get("onVelocity") != scene_midi_contract.get("on_velocity"):
            add_mismatch(
                errors,
                scope,
                "midi.onVelocity",
                midi.get("onVelocity"),
                scene_midi_contract.get("on_velocity"),
            )
        if midi.get("offVelocity") != scene_midi_contract.get("off_velocity"):
            add_mismatch(
                errors,
                scope,
                "midi.offVelocity",
                midi.get("offVelocity"),
                scene_midi_contract.get("off_velocity"),
            )
        if osc.get("address") != expected["osc_address"]:
            add_mismatch(errors, scope, "osc.address", osc.get("address"), expected["osc_address"])
        if osc.get("onArgs") != scene_osc_contract.get("on_args"):
            add_mismatch(errors, scope, "osc.onArgs", osc.get("onArgs"), scene_osc_contract.get("on_args"))
        if osc.get("offArgs") != scene_osc_contract.get("off_args"):
            add_mismatch(errors, scope, "osc.offArgs", osc.get("offArgs"), scene_osc_contract.get("off_args"))
        if not isinstance(group, dict):
            errors.append(f"{scope}: group must be an object")
        else:
            if group.get("id") != scene_group_contract.get("id"):
                add_mismatch(errors, scope, "group.id", group.get("id"), scene_group_contract.get("id"))
            if group.get("mode") != scene_group_contract.get("mode"):
                add_mismatch(errors, scope, "group.mode", group.get("mode"), scene_group_contract.get("mode"))
            if group.get("exclusive") != scene_group_contract.get("exclusive"):
                add_mismatch(
                    errors,
                    scope,
                    "group.exclusive",
                    group.get("exclusive"),
                    scene_group_contract.get("exclusive"),
                )
        if not notes_have_tags(
            pad.get("notes"),
            {
                "contract": "rig",
                "scene": expected.get("preset", ""),
                "preset": expected.get("preset", ""),
                "release": scene_contract.get("release_behavior", ""),
            },
        ):
            errors.append(
                f"{scope}: notes must tag contract:rig scene:{expected.get('preset')} "
                f"preset:{expected.get('preset')} release:{scene_contract.get('release_behavior')}"
            )

    for pad_id in sorted(pads_by_id):
        if pad_id.startswith("vid_scene_") and pad_id not in expected_scenes:
            errors.append(f"{interop_path}: unknown semantic ID '{pad_id}'")

    validate_endpoint_lane(errors, pads_by_id, interop_path, "macro", macro_contract)
    validate_endpoint_lane(errors, pads_by_id, interop_path, "analysis", analysis_contract)

    if not errors:
        checks.append(
            f"{interop_path}: runtime profile, MIDI input, OSC routing, scenes, macro ch {macro_contract['channel']}, and analysis ch {analysis_contract['channel']} match contract"
        )
        checks.append(
            f"{interop_path}: scene release semantics and {len(macro_contract['parameters'])}+{len(analysis_contract['parameters'])} MIDI/OSC lane mirrors match MSVP interop"
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
