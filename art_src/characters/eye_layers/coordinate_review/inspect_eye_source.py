#!/usr/bin/env python3
"""Render one original native head crop with source-coordinate axes for manual review."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
SOURCE_INDEX = ROOT / "art_src/characters/eye_layers/sources.json"
HEAD_INDEX = ROOT / ".godot/eye_sources/heads.json"
OUT = ROOT / "art_src/characters/eye_layers/coordinate_review"
SPECS = {"rin": "rin_side", "mei": "mei_side"}
ALIASES = {"repairman_chen": "repairer", "ah_po": "granny"}
SOURCE_IDS = {"repairer": "repairman_chen", "granny": "ah_po"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> tuple[dict[str, dict], dict[str, dict]]:
    sources = {item["id"]: item for item in json.loads(SOURCE_INDEX.read_text(encoding="utf-8"))}
    heads = {item["id"]: item for item in json.loads(HEAD_INDEX.read_text(encoding="utf-8"))}
    return sources, heads


def spec_blink(char_id: str) -> dict | None:
    spec_name = SPECS.get(char_id)
    if not spec_name:
        return None
    data = json.loads((ROOT / f"tools/comfyui/specs/{spec_name}.json").read_text(encoding="utf-8"))
    return data.get("blink")


def points(raw: list, stride: int) -> list[tuple[float, float]]:
    if raw and isinstance(raw[0], (int, float)):
        return [(float(raw[i]), float(raw[i + 1])) for i in range(0, len(raw), stride)]
    return [(float(p[0]), float(p[1])) for p in raw]


def render(char_id: str, window: tuple[int, int, int, int] | None, scale: int,
           quad_override: list[float] | None = None, upper_override: list[float] | None = None,
           lower_override: list[float] | None = None) -> Path:
    sources, heads = records()
    head_id = SOURCE_IDS.get(char_id, char_id)
    if char_id not in sources or head_id not in heads:
        raise ValueError(f"unknown character id: {char_id}")
    entry = sources[char_id]
    source_path = ROOT / entry["source"]
    actual_hash = sha256(source_path)
    if actual_hash != entry["sha256"]:
        raise ValueError(f"source hash mismatch for {char_id}: {actual_hash}")
    source = Image.open(source_path)
    if source.mode != "RGBA" or source.size != tuple(entry["canvas"]):
        raise ValueError(f"source is not native RGBA {entry['canvas']}: {char_id} {source.mode} {source.size}")
    bbox = heads[head_id]["head_bbox"]
    if window is None:
        x0, y0, x1, y1 = bbox
        margin = 3
        window = (max(0, x0 - margin), max(0, y0 - margin), min(source.width, x1 + margin), min(source.height, y1 + margin))
    x0, y0, x1, y1 = window
    if not (0 <= x0 < x1 <= source.width and 0 <= y0 < y1 <= source.height):
        raise ValueError(f"window outside source canvas: {window}")

    crop = source.crop(window)
    background = Image.new("RGBA", crop.size, (128, 128, 128, 255))
    background.alpha_composite(crop)
    enlarged = background.resize((crop.width * scale, crop.height * scale), Image.Resampling.NEAREST)
    border = 26
    output = Image.new("RGB", (enlarged.width + border, enlarged.height + border), (40, 46, 57))
    output.paste(enlarged.convert("RGB"), (border, border))
    draw = ImageDraw.Draw(output)
    for sx in range(x0 - (x0 % 5), x1 + 1, 5):
        px = border + (sx - x0) * scale
        draw.line((px, border - 4, px, border), fill=(220, 220, 220))
        if sx % 10 == 0:
            draw.text((px - 5, 3), str(sx), fill="white")
    for sy in range(y0 - (y0 % 5), y1 + 1, 5):
        py = border + (sy - y0) * scale
        draw.line((border - 4, py, border, py), fill=(220, 220, 220))
        if sy % 10 == 0:
            draw.text((2, py - 4), str(sy), fill="white")

    blink = spec_blink(char_id)
    if blink or quad_override:
        quad = points(quad_override, 2) if quad_override else points(blink["eye"], 2)
        upper = points(upper_override, 2) if upper_override else (points(blink["lid"], 2) if blink else [])
        lower = points(lower_override, 2) if lower_override else []
        mapped_quad = [(border + (x - x0) * scale, border + (y - y0) * scale) for x, y in quad]
        draw.line(mapped_quad + [mapped_quad[0]], fill=(40, 255, 80), width=max(2, scale // 2))
        for curve, color in ((upper, (255, 70, 50)), (lower, (40, 200, 255))):
            if curve:
                mapped_curve = [(border + (x - x0) * scale, border + (y - y0) * scale) for x, y in curve]
                draw.line(mapped_curve, fill=color, width=max(2, scale // 2), joint="curve")
        cx = round(sum(p[0] for p in mapped_quad) / len(mapped_quad))
        cy = round(sum(p[1] for p in mapped_quad) / len(mapped_quad))
        draw.line((cx - scale, cy, cx + scale, cy), fill=(255, 255, 0), width=1)
        draw.line((cx, cy - scale, cx, cy + scale), fill=(255, 255, 0), width=1)

    target = OUT / f"{char_id}-source-window.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    output.save(target)
    print(json.dumps({"id": char_id, "source": entry["source"], "sha256": actual_hash, "canvas": source.size,
                      "head_bbox": bbox, "window": window, "spec_blink": blink,
                      "quad_override": quad_override, "upper_override": upper_override,
                      "lower_override": lower_override, "output": str(target)}, ensure_ascii=False))
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    ids = sorted(json.loads(SOURCE_INDEX.read_text(encoding="utf-8"))[i]["id"] for i in range(9))
    parser.add_argument("--id", required=True, choices=sorted(set(ids + ["repairman_chen", "ah_po"])))
    parser.add_argument("--window", nargs=4, type=int, metavar=("X0", "Y0", "X1", "Y1"), help="source-coordinate crop; default shows full head bbox")
    parser.add_argument("--scale", type=int, default=4, help="nearest-neighbor integer zoom for inspection")
    parser.add_argument("--quad", nargs=8, type=float, metavar=("X0", "Y0", "X1", "Y1", "X2", "Y2", "X3", "Y3"), help="manual review polygon overlay")
    parser.add_argument("--upper-lid", nargs="+", type=float, help="manual upper-lid curve overlay, x y pairs")
    parser.add_argument("--lower-lid", nargs="+", type=float, help="manual lower-lid curve overlay, x y pairs")
    args = parser.parse_args()
    for name, value in (("upper-lid", args.upper_lid), ("lower-lid", args.lower_lid)):
        if value is not None and len(value) < 4 or value is not None and len(value) % 2:
            parser.error(f"--{name} requires at least two x/y points")
    source_id = ALIASES.get(args.id, args.id)
    render(source_id, tuple(args.window) if args.window else None, args.scale, args.quad, args.upper_lid, args.lower_lid)


if __name__ == "__main__":
    main()
