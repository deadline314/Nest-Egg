#!/usr/bin/env python3
"""Build CPU-only, source-coordinate contact sheets from the reviewed manifest."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "manifest.json"
SOURCES = ROOT / "art_src/characters/eye_layers/sources.json"
HEADS = ROOT / ".godot/eye_sources/heads.json"
GRAY = (128, 128, 128, 255)
PALETTE = {"quad": (40, 255, 80), "upper": (255, 70, 50), "lower": (40, 200, 255)}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_panel(source: Image.Image, window: list[int], char: dict, scale: int,
                 axes: bool) -> Image.Image:
    x0, y0, x1, y1 = window
    crop = source.crop(window)
    bg = Image.new("RGBA", crop.size, GRAY)
    bg.alpha_composite(crop)
    pixels = bg.resize((crop.width * scale, crop.height * scale), Image.Resampling.NEAREST).convert("RGB")
    pad = 25 if axes else 0
    result = Image.new("RGB", (pixels.width + pad, pixels.height + pad), (40, 46, 57))
    result.paste(pixels, (pad, pad))
    draw = ImageDraw.Draw(result)
    if axes:
        for sx in range(x0 - x0 % 10, x1 + 1, 10):
            px = pad + (sx - x0) * scale
            draw.line((px, 1, px, pad - 2), fill=(225, 225, 225))
            draw.text((px - 6, 2), str(sx), fill="white")
        for sy in range(y0 - y0 % 10, y1 + 1, 10):
            py = pad + (sy - y0) * scale
            draw.line((1, py, pad - 2, py), fill=(225, 225, 225))
            draw.text((2, py - 5), str(sy), fill="white")

    def mapped(points: list[list[float]]) -> list[tuple[float, float]]:
        return [(pad + (float(x) - x0) * scale, pad + (float(y) - y0) * scale) for x, y in points]

    quad = mapped(char["visible_eye_quad"])
    draw.line(quad + [quad[0]], fill=PALETTE["quad"], width=max(1, scale // 3))
    for key in ("upper_lid_curve", "lower_lid_curve"):
        curve = char[key]
        if curve:
            draw.line(mapped(curve), fill=PALETTE["upper" if key.startswith("upper") else "lower"], width=max(1, scale // 3))
    cx = round(sum(x for x, _ in quad) / len(quad))
    cy = round(sum(y for _, y in quad) / len(quad))
    draw.line((cx - scale, cy, cx + scale, cy), fill=(255, 255, 0), width=1)
    draw.line((cx, cy - scale, cx, cy + scale), fill=(255, 255, 0), width=1)
    return result


def main() -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    index = {entry["id"]: entry for entry in json.loads(SOURCES.read_text(encoding="utf-8"))}
    heads = {entry["id"]: entry for entry in json.loads(HEADS.read_text(encoding="utf-8"))}
    assert len(data["characters"]) == 9
    synthetic = Image.new("RGBA", (1, 1), (200, 20, 10, 0))
    gray_test = Image.new("RGBA", (1, 1), GRAY)
    gray_test.alpha_composite(synthetic)
    assert gray_test.getpixel((0, 0)) == GRAY, "transparent source pixels must composite onto gray"
    for char in data["characters"]:
        source_path = ROOT / char["source"]
        assert source_path.is_file(), char["id"]
        actual_hash = sha256(source_path)
        assert actual_hash == char["sha256"] == index[char["id"]]["sha256"], (char["id"], actual_hash)
        source = Image.open(source_path)
        assert source.mode == "RGBA" and list(source.size) == data["native_canvas"]
        assert list(source.size) == index[char["id"]]["canvas"]
        bounds = heads[char.get("display_name", char["id"])]["head_bbox"]
        assert bounds == char["source_head_bbox"], (char["id"], bounds)
        for key in ("visible_eye_quad", "upper_lid_curve", "lower_lid_curve"):
            for x, y in char[key]:
                assert 0 <= x < source.width and 0 <= y < source.height, (char["id"], key, x, y)
        x0, y0, x1, y1 = char["exact_crop"]
        assert 0 <= x0 < x1 <= source.width and 0 <= y0 < y1 <= source.height
        assert all(x0 <= x <= x1 and y0 <= y <= y1 for x, y in char["visible_eye_quad"])
        alpha = source.getchannel("A").crop(tuple(char["exact_crop"]))
        assert alpha.getbbox(), f"no nontransparent source pixels for {char['id']}"
        eye_mask = Image.new("1", source.size, 0)
        ImageDraw.Draw(eye_mask).polygon([tuple(point) for point in char["visible_eye_quad"]], fill=1)
        alpha_under_eye = Image.new("L", source.size, 0)
        alpha_under_eye.paste(source.getchannel("A"))
        assert ImageChops.multiply(alpha_under_eye, eye_mask.convert("L")).getbbox(), f"eye quad misses opaque source pixels: {char['id']}"
        overview = render_panel(source, char["source_head_bbox"], char, 2, axes=False)
        detail = render_panel(source, char["exact_crop"], char, 12, axes=True)
        assert overview.mode == detail.mode == "RGB"
        overview.save(HERE / f"{char['id']}-overview.png")
        detail.save(HERE / f"{char['id']}-eye-detail.png")
        sheet = Image.new("RGB", (overview.width + detail.width + 12,
                                   max(overview.height, detail.height) + 34), (31, 35, 43))
        sheet.paste(overview, (0, 30))
        sheet.paste(detail, (overview.width + 12, 30))
        label = f"{char['id']} | source window (2x) | eye crop (12x nearest) | green=eye / red=upper lid / cyan=lower lid"
        ImageDraw.Draw(sheet).text((6, 8), label, fill=(245, 245, 245))
        sheet.save(HERE / f"{char['id']}-contact.png")
        print(f"OK {char['id']}: {actual_hash}; native={source.size}; crop={char['exact_crop']}")


if __name__ == "__main__":
    main()
