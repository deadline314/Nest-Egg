"""Reproduce the old same-size text-mask cache bug without ComfyUI or Godot."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[4]
TOOLS = ROOT / "tools" / "comfyui"
sys.path.insert(0, str(TOOLS))
import make_parts  # noqa: E402

LEGACY_REV = "0a09e1bdd97c32d947e9224267fffc8f26c63c6e"
PROMPT = "body"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _save_rgba(path: Path, pixels: np.ndarray) -> None:
    Image.fromarray(pixels, "RGBA").save(path)


def make_fixture(folder: Path) -> dict:
    work = folder / "work"
    (work / "sam").mkdir(parents=True)
    (work / "04_stages/sam_P").mkdir(parents=True)
    (work / "05_groups").mkdir(parents=True)
    (work / "06_parts").mkdir(parents=True)
    original = np.zeros((8, 8, 4), dtype=np.uint8)
    original[1:7, 1:7] = (90, 45, 25, 255)
    stage_original = original.copy()
    stage_original[2:6, 2:6] = (30, 70, 100, 255)
    _save_rgba(work / "base_rgba.png", original)
    _save_rgba(work / "04_stages/P.png", stage_original)

    # Existing gray refs and same-sized masks were derived from the old source.
    make_parts.write_grey_composite(original, work / "base_grey.png")
    make_parts.write_grey_composite(stage_original, work / "04_stages/P_grey.png")
    Image.new("L", (8, 8), 255).save(work / "sam/body.png")
    Image.new("L", (8, 8), 255).save(work / "04_stages/sam_P/body.png")

    changed = original.copy()
    changed[0, 0] = (240, 30, 40, 255)
    changed_stage = stage_original.copy()
    changed_stage[0, 1] = (20, 230, 70, 255)
    _save_rgba(work / "base_rgba.png", changed)
    _save_rgba(work / "04_stages/P.png", changed_stage)

    spec = {
        "id": "cache-red-green",
        "groups": {"body": {"sam": [PROMPT], "complete": {"stage": "P", "occluders": [], "trim": 0, "edge_trim": 0}}},
        "stages": [{"name": "P", "prompt": "peeled body"}],
        "parts": {"body": {"group": "body"}},
        "joints": {"hip": [4, 4]},
        "seam": 0,
    }
    spec_path = work / "spec.json"
    spec_path.write_text(json.dumps(spec), encoding="utf8")
    return {
        "work": work,
        "spec": spec_path,
        "argv": ["make_parts.py", "--spec", str(spec_path), "--work", str(work), "--no-complete"],
        "original": original,
        "changed": changed,
        "stage_original": stage_original,
        "stage_changed": changed_stage,
    }


def load_legacy(folder: Path):
    result = subprocess.run(
        ["git", "show", f"{LEGACY_REV}:tools/comfyui/make_parts.py"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    source = result.stdout
    path = folder / "legacy_make_parts.py"
    path.write_bytes(source)
    spec = importlib.util.spec_from_file_location("legacy_make_parts", path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module, sha(source)


def mock_segment(calls: list, image_path: str, prompts: list[str], out_dir: str,
                 threshold: float = 0.4, refine: int = 2) -> dict:
    calls.append({"input_sha256": sha(Path(image_path).read_bytes()), "prompts": prompts.copy(),
                  "threshold": threshold, "refine": refine})
    output = Path(out_dir)
    output.mkdir(parents=True, exist_ok=True)
    result = {}
    for prompt in prompts:
        path = output / f"{make_parts.slug(prompt)}.png"
        Image.new("L", (8, 8), 255).save(path)
        result[prompt] = path
    return result


def run_case(mode: str, evidence: Path) -> None:
    with tempfile.TemporaryDirectory(prefix=f"cache-{mode}-") as temporary:
        fixture = make_fixture(Path(temporary))
        work = fixture["work"]
        gray_before = (work / "base_grey.png").read_bytes()
        source_sha = sha((work / "base_rgba.png").read_bytes())
        stage_sha = sha((work / "04_stages/P.png").read_bytes())
        calls: list[dict] = []
        if mode == "red":
            runner, legacy_sha = load_legacy(Path(temporary))
        else:
            runner, legacy_sha = make_parts, None
        runner.segment = lambda image, prompts, out, threshold=0.4, refine=2: mock_segment(
            calls, image, prompts, out, threshold, refine)
        with patch.object(sys, "argv", fixture["argv"]):
            runner.main()

        gray_after = (work / "base_grey.png").read_bytes()
        actual = {
            "mode": mode,
            "legacy_revision": LEGACY_REV if mode == "red" else None,
            "legacy_source_sha256": legacy_sha,
            "base_source_sha256": source_sha,
            "stage_source_sha256": stage_sha,
            "base_gray_before_sha256": sha(gray_before),
            "base_gray_after_sha256": sha(gray_after),
            "base_gray_refreshed": gray_after != gray_before,
            "sam_segment_calls": calls,
            "sam_segment_call_count": len(calls),
            "expected_calls": 2,
        }
        if mode == "red":
            (evidence / "red-report.json").write_text(json.dumps(actual, indent=2) + "\n", encoding="utf8")
            assert len(calls) == 2, "legacy bug: same-size base/stage source edits should invalidate both SAM masks"
        else:
            assert len(calls) == 2, "current cache must regenerate base and stage masks on unkeyed changed source"
            assert gray_after != gray_before, "current base gray reference must refresh from current RGBA"
            (evidence / "green-report.json").write_text(json.dumps(actual, indent=2) + "\n", encoding="utf8")


def make_preview(evidence: Path) -> None:
    panels = []
    for label, pixels in [
        ("source before edit", make_fixture_preview(False)),
        ("source after 1px edit", make_fixture_preview(True)),
    ]:
        image = Image.fromarray(pixels, "RGBA")
        bg = Image.new("RGBA", image.size, (128, 128, 128, 255))
        bg.alpha_composite(image)
        panels.append((label, bg.convert("RGB")))
    old_gray = Image.new("RGBA", (8, 8), (128, 128, 128, 255))
    old_gray.alpha_composite(Image.fromarray(make_fixture_preview(False), "RGBA"))
    current = Image.new("RGBA", (8, 8), (128, 128, 128, 255))
    current.alpha_composite(Image.fromarray(make_fixture_preview(True), "RGBA"))
    panels.extend([("stale gray input (old main)", old_gray.convert("RGB")), ("rebuilt gray input (current)", current.convert("RGB"))])
    scale, label_height, gap = 32, 28, 8
    width = len(panels) * (8 * scale) + (len(panels) + 1) * gap
    canvas = Image.new("RGB", (width, 8 * scale + label_height + 2 * gap), (245, 245, 245))
    draw = ImageDraw.Draw(canvas)
    for index, (label, image) in enumerate(panels):
        x = gap + index * (8 * scale + gap)
        draw.text((x, gap), label, fill=(20, 20, 20))
        canvas.paste(image.resize((8 * scale, 8 * scale), Image.Resampling.NEAREST), (x, label_height + gap))
    canvas.save(evidence / "source-cache-before-after.png")


def make_fixture_preview(changed: bool) -> np.ndarray:
    pixels = np.zeros((8, 8, 4), dtype=np.uint8)
    pixels[1:7, 1:7] = (90, 45, 25, 255)
    if changed:
        pixels[0, 0] = (240, 30, 40, 255)
    return pixels


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["red", "green"], required=True)
    args = parser.parse_args()
    evidence = Path(__file__).resolve().parent
    make_preview(evidence)
    run_case(args.mode, evidence)
    print(f"cache regression {args.mode}: evidence={evidence}")


if __name__ == "__main__":
    main()
