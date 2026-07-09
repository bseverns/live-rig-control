#!/usr/bin/env python3
"""Sync shared semantic controls from a committed live-rig snapshot mirror."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCAL_SNAPSHOT = REPO_ROOT / "atlas" / "live-rig.default.json"
DEFAULT_SIBLING_SNAPSHOT = REPO_ROOT.parent / "live-rig" / "interop" / "exports" / "live-rig.default.json"
DEFAULT_TARGETS = [
    REPO_ROOT / "src" / "mappings.json",
    REPO_ROOT / "ios" / "Sources" / "LiveRigControlApp" / "Resources" / "mappings.json",
]
TARGET_PROFILE_ID = "msvp"
SCENE_GROUP = {"id": "msvp_scene", "mode": "exclusive", "exclusive": True}
AUTHORITY_IDS = [
    "vid_scene_intro",
    "vid_scene_crash",
    "vid_scene_soft",
    "vid_scene_clean_camera",
    "vid_state_blackout",
    "rig_state_manual_override",
    "macro_analysis_blend",
]
SEMANTIC_TO_RUNTIME_ID = {
    "scene.intro": "vid_scene_intro",
    "scene.crash": "vid_scene_crash",
    "scene.soft": "vid_scene_soft",
    "scene.clean_camera": "vid_scene_clean_camera",
    "state.blackout": "vid_state_blackout",
    "state.manual_override": "rig_state_manual_override",
    "macro.analysis_blend": "macro_analysis_blend",
}
LAYOUT = {
    "vid_scene_intro": {"row": 0, "col": 0, "group": SCENE_GROUP},
    "vid_scene_crash": {"row": 0, "col": 1, "group": SCENE_GROUP},
    "vid_scene_soft": {"row": 0, "col": 2, "group": SCENE_GROUP},
    "vid_scene_clean_camera": {"row": 0, "col": 3, "group": SCENE_GROUP},
    "vid_state_blackout": {"row": 0, "col": 4},
    "rig_state_manual_override": {"row": 0, "col": 5},
    "macro_analysis_blend": {"row": 0, "col": 6},
}
LABEL_OVERRIDES = {
    "vid_scene_intro": "Scene Intro",
    "vid_scene_crash": "Scene Crash",
    "vid_scene_soft": "Scene Soft",
    "vid_scene_clean_camera": "Clean Camera",
    "vid_state_blackout": "Blackout",
    "rig_state_manual_override": "Manual Override",
    "macro_analysis_blend": "Analysis Blend",
}


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"Missing file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc


def ensure_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    return [value] if value is not None else []


def authority_controls(snapshot_path: Path) -> dict[str, dict[str, Any]]:
    snapshot_data = load_json(snapshot_path)
    if isinstance(snapshot_data.get("controller_bindings"), list):
        return authority_controls_from_profile_export(snapshot_data, snapshot_path)

    bindings = snapshot_data.get("bindings")
    if not isinstance(bindings, list):
        raise SystemExit(f"{snapshot_path}: missing 'bindings' list")

    bindings_by_ref = {
        item.get("mappingRef"): item
        for item in bindings
        if isinstance(item, dict) and isinstance(item.get("mappingRef"), str)
    }

    result: dict[str, dict[str, Any]] = {}
    for control_id in AUTHORITY_IDS[:5]:
        binding = bindings_by_ref.get(control_id)
        if binding is None or binding.get("supported") is not True:
            raise SystemExit(f"{snapshot_path}: missing supported binding '{control_id}'")
        result[control_id] = build_runtime_pad(control_id, binding)
    return result


def authority_controls_from_profile_export(snapshot_data: dict[str, Any], snapshot_path: Path) -> dict[str, dict[str, Any]]:
    controls = None
    for controller in snapshot_data["controller_bindings"]:
        if controller.get("controller_name") == "live-rig-control":
            controls = controller.get("controls")
            break
    if not isinstance(controls, list):
        raise SystemExit(f"{snapshot_path}: missing live-rig-control controller controls")

    fallback = fallback_transport_by_semantic(snapshot_data)
    result: dict[str, dict[str, Any]] = {}
    for control in controls:
        runtime_id = SEMANTIC_TO_RUNTIME_ID.get(control.get("semantic_id"))
        if runtime_id:
            result[runtime_id] = build_runtime_pad_from_controller(runtime_id, control, fallback.get(control.get("semantic_id")))
    missing = [control_id for control_id in AUTHORITY_IDS if control_id not in result]
    if missing:
        raise SystemExit(f"{snapshot_path}: missing live-rig-control semantic controls: {', '.join(missing)}")
    return result


def fallback_transport_by_semantic(snapshot_data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for group in ("scenes", "states"):
        for item in snapshot_data.get(group, []):
            if isinstance(item, dict) and isinstance(item.get("id"), str):
                result[item["id"]] = {"triggers": item.get("triggers", [])}
    return result


def build_runtime_pad(control_id: str, binding: dict[str, Any]) -> dict[str, Any]:
    layout = LAYOUT[control_id]
    midi_bindings = binding.get("midi", [])
    osc_bindings = binding.get("osc", [])
    note = None
    if isinstance(midi_bindings, list) and midi_bindings:
        note = midi_bindings[0].get("note")
    if not isinstance(osc_bindings, list) or not osc_bindings:
        raise SystemExit(f"{binding.get('mappingRef', control_id)}: missing OSC transport details in snapshot")
    osc_binding = osc_bindings[0]

    pad: dict[str, Any] = {
        "id": control_id,
        "label": LABEL_OVERRIDES.get(control_id, binding.get("label")),
        "row": layout["row"],
        "col": layout["col"],
        "toggle": True,
        "osc": {
            "address": osc_binding["address"],
            "args": ensure_list(osc_binding.get("onArgs") or osc_binding.get("args")),
            "onArgs": ensure_list(osc_binding.get("onArgs") or osc_binding.get("args")),
            "offArgs": ensure_list(osc_binding.get("offArgs")),
        },
        "notes": build_notes(control_id, note),
        "risk": "high",
        "queuePolicy": "ttl",
        "queueTtlMs": 1000,
    }

    if "group" in layout:
        pad["group"] = layout["group"]

    return pad


def build_runtime_pad_from_controller(control_id: str, control: dict[str, Any], fallback: dict[str, Any] | None) -> dict[str, Any]:
    layout = LAYOUT[control_id]
    osc = control.get("osc")
    if not isinstance(osc, dict) or not osc.get("address"):
        raise SystemExit(f"{control.get('id', control_id)}: missing OSC transport details in profile export")

    is_slider = control_id == "macro_analysis_blend"
    args = ["$value01"] if is_slider else ensure_list(osc.get("onArgs") or osc.get("args"))
    is_blackout = control_id == "vid_state_blackout"
    pad: dict[str, Any] = {
        "id": control_id,
        "label": LABEL_OVERRIDES.get(control_id, control.get("physical_label", control_id)),
        "row": layout["row"],
        "col": layout["col"],
        "osc": {"address": osc["address"], "args": args},
        "notes": build_notes_from_controller(control, fallback),
        "risk": "critical" if is_blackout else ("high" if control.get("safety") or control_id.startswith("vid_scene_") else "medium"),
        "queuePolicy": "safety" if is_blackout else ("latest" if is_slider else "ttl"),
        "queueTtlMs": 1000,
    }
    if is_slider:
        pad["ui"] = {"type": "slider", "min": 0, "max": 127, "step": 1, "initial": 64, "showValue": True}
    else:
        pad["toggle"] = True
        pad["osc"]["onArgs"] = args
        pad["osc"]["offArgs"] = [0]
    if "group" in layout:
        pad["group"] = layout["group"]
    return pad


def build_notes(control_id: str, note: Any) -> str:
    if control_id.startswith("vid_scene_"):
        return (
            "Shared scene cue. OSC primary in live-rig-control; "
            f"canonical MIDI fallback note is {note} on the live-rig semantic lane. "
            "Generated from the committed live-rig snapshot mirror."
        )
    return (
        "Shared blackout state. OSC primary in live-rig-control; "
        f"canonical MIDI fallback note is {note} on the live-rig semantic lane. "
        "Generated from the committed live-rig snapshot mirror."
    )


def build_notes_from_controller(control: dict[str, Any], fallback: dict[str, Any] | None) -> str:
    triggers = fallback.get("triggers", []) if fallback else []
    midi = next((item for item in triggers if isinstance(item, dict) and str(item.get("type", "")).startswith("midi_")), None)
    suffix = ""
    if midi:
        detail = f"ch {midi.get('channel')} " + (f"note {midi.get('note')}" if "note" in midi else f"cc {midi.get('cc')}")
        suffix = f" Canonical MIDI fallback is {detail}."
    return f"{control.get('semantic_id')} from live-rig controller export.{suffix} Generated from the committed live-rig snapshot mirror."


def sync_document(document: dict[str, Any], controls: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], bool]:
    profiles = document.get("profiles")
    if not isinstance(profiles, dict):
        raise SystemExit("Target mapping document missing 'profiles' object")

    profile = profiles.get(TARGET_PROFILE_ID)
    if not isinstance(profile, dict):
        raise SystemExit(f"Target mapping document missing profile '{TARGET_PROFILE_ID}'")

    pads = profile.get("pads")
    if not isinstance(pads, list):
        raise SystemExit(f"Profile '{TARGET_PROFILE_ID}' is missing a valid pads list")

    first_authority_index = next((index for index, pad in enumerate(pads) if pad.get("id") in AUTHORITY_IDS), None)
    first_macro_index = next((index for index, pad in enumerate(pads) if str(pad.get("id", "")).startswith("msvp_macro_")), None)
    insert_at = first_authority_index if first_authority_index is not None else (first_macro_index if first_macro_index is not None else 0)

    remaining = [pad for pad in pads if pad.get("id") not in AUTHORITY_IDS]
    canonical = [controls[control_id] for control_id in AUTHORITY_IDS if control_id in controls]
    next_pads = remaining[:insert_at] + canonical + remaining[insert_at:]

    changed = next_pads != pads
    if changed:
        profile["pads"] = next_pads
    return document, changed


def check_document(document: dict[str, Any], controls: dict[str, dict[str, Any]], target: Path) -> list[str]:
    profiles = document.get("profiles")
    if not isinstance(profiles, dict):
        return [f"{target}: missing 'profiles' object"]
    profile = profiles.get(TARGET_PROFILE_ID)
    if not isinstance(profile, dict):
        return [f"{target}: missing profile '{TARGET_PROFILE_ID}'"]
    pads = profile.get("pads")
    if not isinstance(pads, list):
        return [f"{target}: profile '{TARGET_PROFILE_ID}' has non-list pads"]

    pads_by_id = {pad.get("id"): pad for pad in pads if isinstance(pad, dict)}
    errors: list[str] = []
    for control_id, expected in controls.items():
        actual = pads_by_id.get(control_id)
        if actual is None:
            errors.append(f"{target}: missing authority-synced control '{control_id}'")
            continue
        for field in ("label", "row", "col", "toggle", "notes", "ui", "risk", "queuePolicy", "queueTtlMs"):
            if actual.get(field) != expected.get(field):
                errors.append(f"{target}:{control_id}: {field} is {actual.get(field)!r}, expected {expected.get(field)!r}")
        if actual.get("group") != expected.get("group"):
            errors.append(f"{target}:{control_id}: group is {actual.get('group')!r}, expected {expected.get('group')!r}")
        if actual.get("osc") != expected.get("osc"):
            errors.append(f"{target}:{control_id}: osc mapping does not match live-rig authority")
        if "midi" in actual:
            errors.append(f"{target}:{control_id}: controller should not emit MIDI fallback on the msvp page")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync the shared MSVP semantic controls from the committed live-rig snapshot mirror."
    )
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_LOCAL_SNAPSHOT, help="Committed local mirror of live-rig.default.json.")
    parser.add_argument(
        "--sibling-snapshot",
        type=Path,
        default=DEFAULT_SIBLING_SNAPSHOT,
        help="Sibling live-rig exported snapshot used when refreshing the local mirror.",
    )
    parser.add_argument(
        "--refresh-from-sibling",
        action="store_true",
        help="Refresh the committed local snapshot mirror from the sibling live-rig checkout before syncing.",
    )
    parser.add_argument("--target", type=Path, action="append", default=None, help="Target mapping file to update.")
    parser.add_argument("--check", action="store_true", help="Check alignment without writing files.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.refresh_from_sibling:
        args.snapshot.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.sibling_snapshot, args.snapshot)
        print(f"Refreshed snapshot mirror {args.snapshot} from {args.sibling_snapshot}")

    controls = authority_controls(args.snapshot)
    targets = args.target or DEFAULT_TARGETS

    if args.check:
        errors: list[str] = []
        for target in targets:
            errors.extend(check_document(load_json(target), controls, target))
        if errors:
            print("FAIL")
            for error in errors:
                print(f"  ERROR: {error}")
            return 1
        print("PASS")
        print(f"  Authority controls from {args.snapshot} aligned in {len(targets)} target file(s).")
        return 0

    updated = 0
    for target in targets:
        document = load_json(target)
        next_document, changed = sync_document(document, controls)
        if changed:
            target.write_text(json.dumps(next_document, indent=2) + "\n", encoding="utf-8")
            updated += 1
            print(f"Updated {target}")
        else:
            print(f"No changes needed for {target}")
    print(f"Synced {len(controls)} authority controls from {args.snapshot} across {len(targets)} target file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
