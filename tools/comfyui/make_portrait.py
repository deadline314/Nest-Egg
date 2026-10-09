"""Dialogue head-and-shoulders portrait (transparent) cut from the cleaned part layers.

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/make_portrait.py --spec tools/comfyui/specs/rin_side.json --work art_src/characters/rin2

Inputs : <work>/07_refined/<part>.png (else 06_parts/), spec["dialog_portrait"] = {"box": [x0, y0, x1, y1], "out": "art/portraits/<id>.png"}
         box is in pixel coordinates of base_rgba.png; every front part is stacked in z order (the dimmed far-side limb copies, named *_back* with a tint, are skipped).
Output : the PNG named by "out" (what data/story/*.json speakers point at).
"""
import argparse
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    cfg = spec["dialog_portrait"]
    work = Path(args.work)
    src = work / "07_refined" if (work / "07_refined").exists() else work / "06_parts"
    overrides = {path.stem: path for path in (work / "overrides/refined").glob("*.png")}
    canvas_size = Image.open(work / "base_rgba.png").size if overrides else None
    for name, path in overrides.items():
        with Image.open(path) as image:
            if name not in spec["parts"] or image.mode != "RGBA" or image.size != canvas_size:
                raise ValueError(f"{path}: portrait source override requires a known part and full-canvas RGBA of size {canvas_size}")
    layers = []
    for part, p in spec["parts"].items():
        for use in p["uses"]:
            if use.get("tint") and "_back" in use["name"]:  # the dimmed copies for the far-side limbs (a front part can carry a tint too: a brightened coat)
                continue
            layers.append((use["z"], part))
    first = Image.open(overrides.get(layers[0][1], src / f"{layers[0][1]}.png"))
    canvas = Image.new("RGBA", first.size, (0, 0, 0, 0))
    for _, part in sorted(layers):
        canvas.alpha_composite(Image.open(overrides.get(part, src / f"{part}.png")).convert("RGBA"))
    crop = canvas.crop(tuple(cfg["box"]))
    size = cfg.get("size", 128)
    out = Path(cfg["out"])
    out.parent.mkdir(parents=True, exist_ok=True)
    crop.resize((size, size), Image.LANCZOS).save(out)
    print(f"  portrait {out} {size}x{size}")


if __name__ == "__main__":
    main()
