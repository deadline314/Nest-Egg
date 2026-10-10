"""Offline hand-attachment contract: referenced variants, finite anchors and reproducible exports."""
import copy
import json
import tempfile
from pathlib import Path

from check_spec import check


root = Path(__file__).resolve().parents[2]
recipe = json.loads((root / "tools/comfyui/recipes/rin.json").read_text(encoding="utf8"))
spec = json.loads((root / recipe["spec"]).read_text(encoding="utf8"))
assert not check(recipe, spec, True)[0]
for change, expected in [("missing", ".grip_texture"), ("wrong_bone", ".grip_texture"), ("unreferenced", ".uses"), ("invalid_grasp", ".grasp")]:
    trial = copy.deepcopy(spec)
    if change == "missing":
        trial["parts"]["hand"]["uses"][0]["grip_texture"] = "absent_hand"
    elif change == "wrong_bone":
        trial["parts"]["hand"]["uses"][0]["bone"] = "head"
    elif change == "unreferenced":
        trial["parts"]["hand"]["uses"][0].pop("grip_texture")
    else:
        trial["parts"]["hand_grip"]["grasp"] = [float("nan"), 0]
    assert any(expected in error for error in check(recipe, trial, True)[0]), change
character = json.loads((root / "art/characters/rin/character.json").read_text(encoding="utf8"))
hands = [part for part in character["parts"] if part["bone"] in ("hand_front", "hand_back")]
assert len(hands) == 2 and hands[0]["texture"] != hands[1]["texture"]
for hand in hands:
    variant = spec["parts"][hand["grip_texture"]]
    from cut_rig_parts import frame
    import numpy as np
    wrist = np.array(spec["joints"]["palm"])
    tip = np.array(spec["joints"]["fingertip"])
    x, y = frame("hand", wrist, tip)
    displacement = np.array(variant["grasp"]) - wrist
    expected = np.array([displacement @ x, displacement @ y]) / spec["illustration_px_per_wp"]
    assert np.max(np.abs(expected - hand["grip_offset"])) < 0.0003
print("hand attachments: missing references/wrong bones/unreferenced layers/nonfinite anchors rejected; two independent slots and exported palm offsets agree")
from cut_layers import load_native_grips
native = load_native_grips(spec, root)
assert set(native) == {"hand_left_grip"}
data, definition = native["hand_left_grip"]
assert definition["size"] == [226, 142] and definition["pivot"] == [26.0822, 25.9259]
assert definition["texture_scale"] == 0.018283541156251144
assert data == (root / spec["native_grips"]["hand_left_grip"]["source"]).read_bytes()
for field, value in [("source", "tools/comfyui/cut_layers.py"), ("source", "art_src/characters/missing.png"), ("source", None),
                     ("sha256", "0" * 64), ("size", [225, 142]), ("texture_scale", 0),
                     ("texture_scale", float("nan")), ("texture_scale", True), ("texture_scale", "0.01"),
                     ("pivot", [float("inf"), 0]), ("pivot", [0]), ("pivot", [False, 0])]:
    trial = copy.deepcopy(spec)
    trial["native_grips"]["hand_left_grip"][field] = value
    try:
        load_native_grips(trial, root)
    except ValueError:
        pass
    else:
        raise AssertionError(f"invalid native grip accepted: {field}={value}")
for native_setting in [[], {"head": spec["native_grips"]["hand_left_grip"]}, {"hand_left_grip": None}]:
    try:
        load_native_grips(dict(spec, native_grips=native_setting), root)
    except ValueError:
        pass
    else:
        raise AssertionError(f"invalid native grip setting accepted: {native_setting}")
assert load_native_grips(dict(spec, native_grips={}), root) == {}
print("native grips: source byte identity/density/pivot; invalid source/hash/size/numeric fields/unreferenced slot rejected")
from build_character import Build

before = (root / "art/characters/rin/character.json").read_bytes()
with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    (work / "06_parts").mkdir()
    for invalid in ["tools/comfyui/cut_layers.py", "art_src/characters/missing.py", "art_src/characters/rin_hands/manifest.json"]:
        trial = copy.deepcopy(recipe)
        trial.update(work=str(work), source_rebuilds=[invalid])
        path = work / "recipe.json"
        path.write_text(json.dumps(trial), encoding="utf8")
        try:
            Build(path, False, None).step_textures()
        except SystemExit as error:
            assert "invalid registered source rebuild" in str(error)
        else:
            raise AssertionError(f"untrusted source rebuild accepted: {invalid}")
assert (root / "art/characters/rin/character.json").read_bytes() == before
print("registered sources: outside/missing/non-script inputs reject before replacing character output")

# A cut must keep every painted joint row; normal-map rim suppression cannot erase source overlap.
import subprocess
import sys
from PIL import Image

with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    (work / "06_parts").mkdir()
    image = Image.new("RGBA", (24, 32))
    for y in range(12, 24):
        for x in range(8, 16):
            image.putpixel((x, y), (80, y * 8, 120, 255))
    image.save(work / "06_parts/limb.png")
    fixture = {"id": "cut_fixture", "display_name": "cut", "tex_px_per_wp": 1, "illustration_px_per_wp": 1,
               "scale": 1, "ground_y": 32, "glow": {}, "joints": {"hip": [12, 0], "tip": [12, 32]},
               "bones": [{"name": "hip", "parent": "", "tip": "tip"}],
               "parts": {"limb": {"from": "hip", "to": "tip", "mode": "bone", "y": [12, 24],
                                  "uses": [{"name": "limb", "bone": "hip", "z": 0}]}},
               "weapon_anchor": {"from": "hip", "to": "tip", "bone": "hip", "dx": 0, "dy": 0, "reach": 1}}
    (work / "spec.json").write_text(json.dumps(fixture), encoding="utf8")
    subprocess.run([sys.executable, str(root / "tools/comfyui/cut_layers.py"), "--spec", str(work / "spec.json"),
                    "--work", str(work), "--char", str(work / "char"), "--rig", str(work / "rig.json")],
                   check=True, capture_output=True)
    result = np.array(Image.open(work / "char/parts/limb.png"))
    assert result.shape[:2] == (12, 13)
    assert np.count_nonzero(result[:, :, 3] == 255) == 12 * 8
    assert list(result[:, 3, 1]) == [y * 8 for y in range(12, 24)]
print("joint cutting: all first/last painted rows and source overlap survive export")

import shutil
with tempfile.TemporaryDirectory() as directory:
    sandbox = Path(directory)
    for name in ("rin_hands", "rin_worn_coat"):
        source = root / "art_src/characters" / name
        target = sandbox / "art_src/characters" / name
        record = json.loads((source / "manifest.json").read_text(encoding="utf8"))
        for file in ["rebuild.py", "manifest.json", *record["sources"]]:
            destination = target / file
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(source / file, destination)
        approved = sandbox / record["approved_source"]
        approved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(root / record["approved_source"], approved)
        outputs = sandbox / "art_src/characters/rin2/overrides/refined"
        outputs.mkdir(parents=True, exist_ok=True)
        sentinel = outputs / "previous.txt"
        sentinel.write_bytes(b"previous accepted output")
        broken = target / next(iter(record["sources"]))
        original = broken.read_bytes()
        broken.write_bytes(original + b"damaged")
        result = subprocess.run([sys.executable, str(target / "rebuild.py")], capture_output=True)
        assert result.returncode != 0 and b"source changed" in result.stderr
        assert sentinel.read_bytes() == b"previous accepted output"
        assert not any((outputs / f"{part}.png").exists() for part in record["outputs"])
        broken.write_bytes(original)
        subprocess.run([sys.executable, str(target / "rebuild.py")], check=True, capture_output=True)
        snapshots = {part: (outputs / f"{part}.png").read_bytes() for part in record["outputs"]}
        subprocess.run([sys.executable, str(target / "rebuild.py")], check=True, capture_output=True)
        assert snapshots == {part: (outputs / f"{part}.png").read_bytes() for part in record["outputs"]}
        if name == "rin_hands":
            for part, old, coordinates in [("arm_upper", "original_upper", "missing_upper_pixels"),
                                            ("hand", "original_hand", "missing_connector_pixels")]:
                restored = Image.open(outputs / f"{part}.png")
                original = Image.open(target / record["mechanical_wrist"][old])
                for point in record["mechanical_wrist"][coordinates]:
                    assert restored.getpixel(tuple(point)) == original.getpixel(tuple(point))
print("registered sources: damaged originals preserve previous output; byte-identical rebuild; all 50 chrome reflection pixels restored from originals")
