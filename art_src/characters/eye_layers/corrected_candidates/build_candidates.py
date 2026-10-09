#!/usr/bin/env python3
"""Generate source-local CPU blink candidates and review contacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
CONFIG = HERE / "candidate_plan.json"
SOURCE_INDEX = ROOT / "art_src/characters/eye_layers/sources.json"
SOURCE_MAP = {"repairer": "repairer", "granny": "granny"}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_config() -> tuple[list[dict], dict[str, dict]]:
    candidates = json.loads(CONFIG.read_text(encoding="utf-8"))["characters"]
    sources = {entry["id"]: entry for entry in json.loads(SOURCE_INDEX.read_text(encoding="utf-8"))}
    return candidates, sources


def verify_source(root: Path, item: dict, source_index: dict[str, dict], override: Path | None = None) -> Image.Image:
    indexed = source_index[item["id"]]
    if item["source"] != indexed["source"] or item["sha256"] != indexed["sha256"]:
        raise ValueError(f"candidate source does not match canonical source index: {item['id']}")
    path = override or root / item["source"]
    if not path.is_file():
        raise ValueError(f"missing source for {item['id']}: {path}")
    actual = digest(path)
    if actual != item["sha256"]:
        raise ValueError(f"source hash mismatch for {item['id']}: expected {item['sha256']}, got {actual}")
    image = Image.open(path)
    if image.mode != "RGBA" or image.size != tuple(indexed["canvas"]):
        raise ValueError(f"source must be native RGBA {indexed['canvas']}: {item['id']} got {image.mode} {image.size}")
    return image.copy()


def poly_mask(size: tuple[int, int], points: list[list[float]]) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon([(round(x), round(y)) for x, y in points], fill=255)
    return mask


def harmonic_skin(source: Image.Image, mask: Image.Image) -> Image.Image:
    """Continue the local skin gradient inward from the eye mask's boundary."""
    box = mask.getbbox()
    if box is None:
        raise ValueError("empty eye mask")
    x0, y0, x1, y1 = max(0, box[0] - 1), max(0, box[1] - 1), min(source.width, box[2] + 1), min(source.height, box[3] + 1)
    region = source.crop((x0, y0, x1, y1))
    region_mask = mask.crop((x0, y0, x1, y1))
    pix = region.load()
    mpix = region_mask.load()
    width, height = region.size
    values = [[[float(pix[x, y][channel]) for channel in range(3)] for y in range(height)] for x in range(width)]
    unknown = [(x, y) for x in range(width) for y in range(height) if mpix[x, y] > 0]
    if not unknown:
        raise ValueError("eye mask has no pixels")
    boundary = []
    for x, y in unknown:
        neighbors = [(nx, ny) for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                     if 0 <= nx < width and 0 <= ny < height and mpix[nx, ny] == 0]
        if neighbors:
            boundary.extend((x, y, nx, ny) for nx, ny in neighbors)
    if not boundary:
        raise ValueError("eye mask has no fixed boundary")
    for x, y in unknown:
        # A neutral initialization avoids propagating open-eye colors into the fill.
        values[x][y] = [sum(pix[nx, ny][c] for _, _, nx, ny in boundary) / len(boundary) for c in range(3)]
    for _ in range(500):
        for x, y in unknown:
            neighbors = [(nx, ny) for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                         if 0 <= nx < width and 0 <= ny < height]
            values[x][y] = [sum(values[nx][ny][c] if mpix[nx, ny] else pix[nx, ny][c] for nx, ny in neighbors) / len(neighbors)
                            for c in range(3)]
    result = source.copy()
    out = result.load()
    original = source.load()
    global_mask = mask.load()
    for lx, ly in unknown:
        gx, gy = x0 + lx, y0 + ly
        if global_mask[gx, gy] and original[gx, gy][3]:
            out[gx, gy] = tuple(max(0, min(255, round(v))) for v in values[lx][ly]) + (original[gx, gy][3],)
    return result


def nearby_skin(source: Image.Image, item: dict, mask: Image.Image) -> Image.Image:
    """Sample a manually chosen same-face skin patch when a clean donor area exists."""
    offset = item.get("skin_sample_offset")
    if offset is None:
        return harmonic_skin(source, mask)
    dx, dy = offset
    result = source.copy()
    src, dst, mp = source.load(), result.load(), mask.load()
    for y in range(source.height):
        for x in range(source.width):
            if not mp[x, y]:
                continue
            sx, sy = x + dx, y + dy
            if not (0 <= sx < source.width and 0 <= sy < source.height):
                raise ValueError(f"skin donor is outside canvas: {item['id']} ({x},{y}) -> ({sx},{sy})")
            donor = src[sx, sy]
            if donor[3] < 240 or max(donor[:3]) < 60:
                raise ValueError(f"unsafe dark/transparent skin donor: {item['id']} ({sx},{sy})={donor}")
            patch = [src[nx, ny] for ny in range(max(0, sy - 1), min(source.height, sy + 2))
                     for nx in range(max(0, sx - 1), min(source.width, sx + 2))
                     if src[nx, ny][3] >= 240 and max(src[nx, ny][:3]) >= 60]
            dst[x, y] = tuple(int(statistics.median(pixel[c] for pixel in patch)) for c in range(3)) + (donor[3],)
    return result


def repairer_skin_bands(source: Image.Image, item: dict, mask: Image.Image) -> Image.Image:
    """Interpolate only from source skin bands on both sides of the visible eye."""
    bands = item.get("skin_donor_bands", {})
    left, right = bands.get("left"), bands.get("right")
    if not left or not right:
        raise ValueError("repairer half requires recorded left/right skin donor bands")
    lx0, ly0, lx1, ly1 = left
    rx0, ry0, rx1, ry1 = right
    if not (0 <= lx0 < lx1 <= source.width and 0 <= rx0 < rx1 <= source.width
            and 0 <= ly0 < ly1 <= source.height and 0 <= ry0 < ry1 <= source.height):
        raise ValueError("repairer skin donor bands exceed the native source")
    if ly1 - ly0 != ry1 - ry0:
        raise ValueError("repairer left/right skin donor bands must span the same rows")
    src, mask_pixels = source.load(), mask.load()
    left_anchor, right_anchor = (lx0 + lx1 - 1) / 2.0, (rx0 + rx1 - 1) / 2.0
    if right_anchor <= left_anchor:
        raise ValueError("repairer right skin band must be right of the left band")
    for band in (left, right):
        x0, y0, x1, y1 = band
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b, a = src[x, y]
                if a < 240 or r < 100 or g < 60 or b < 45:
                    raise ValueError(f"unsafe repairer skin donor ({x},{y})={(r, g, b, a)}")

    def side_color(x0: int, x1: int, y: int) -> tuple[int, int, int]:
        return tuple(round(sum(src[x, y][channel] for x in range(x0, x1)) / (x1 - x0)) for channel in range(3))

    result = source.copy()
    out = result.load()
    for y in range(source.height):
        donor_y = min(max(y, ly0), ly1 - 1)
        luma = side_color(lx0, lx1, donor_y)
        ruma = side_color(rx0, rx1, donor_y)
        for x in range(source.width):
            if not mask_pixels[x, y]:
                continue
            t = max(0.0, min(1.0, (x - left_anchor) / (right_anchor - left_anchor)))
            color = tuple(round(luma[c] * (1.0 - t) + ruma[c] * t) for c in range(3))
            out[x, y] = color + (src[x, y][3],)
    return result


def wataru_skin_bands(source: Image.Image, item: dict, mask: Image.Image) -> Image.Image:
    """Interpolate Wataru's eye fill only from the two recorded clean skin bands."""
    upper = item.get("skin_donor_bands", {}).get("upper")
    lower = item.get("skin_donor_bands", {}).get("lower")
    if not upper or not lower:
        raise ValueError("Wataru requires explicit upper and lower skin donor bands")
    ux0, uy0, ux1, uy1 = upper
    lx0, ly0, lx1, ly1 = lower
    src, mp = source.load(), mask.load()
    upper_rows = range(uy0, uy1)
    lower_rows = range(ly0, ly1)
    for y in upper_rows:
        for x in range(ux0, ux1):
            r, g, b, a = src[x, y]
            if a < 240 or not (r > 190 and g > 160 and b > 120):
                raise ValueError(f"unsafe Wataru upper skin donor ({x},{y})={(r, g, b, a)}")
    for y in lower_rows:
        for x in range(lx0, lx1):
            r, g, b, a = src[x, y]
            if a < 240 or not (r > 190 and g > 160 and b > 120):
                raise ValueError(f"unsafe Wataru lower skin donor ({x},{y})={(r, g, b, a)}")

    upper_color = {
        x: tuple(round(sum(src[x, y][channel] for y in upper_rows) / len(upper_rows)) for channel in range(3))
        for x in range(ux0, ux1)
    }
    lower_color = {
        x: tuple(round(sum(src[x, y][channel] for y in lower_rows) / len(lower_rows)) for channel in range(3))
        for x in range(lx0, lx1)
    }
    shared = range(lx0, min(lx1, ux1))
    delta = tuple(round(statistics.median(lower_color[x][c] - upper_color[x][c] for x in shared)) for c in range(3))
    result = source.copy()
    out = result.load()
    for y in range(source.height):
        for x in range(source.width):
            if not mp[x, y]:
                continue
            if x not in upper_color:
                raise ValueError(f"Wataru eye mask exceeds the recorded upper skin donor band at x={x}")
            base = upper_color[x]
            low = lower_color.get(x, tuple(max(0, min(255, base[c] + delta[c])) for c in range(3)))
            t = max(0.0, min(1.0, (y - uy0) / max(1, ly0 + 1 - uy0)))
            color = tuple(round(base[c] * (1.0 - t) + low[c] * t) for c in range(3))
            out[x, y] = color + (src[x, y][3],)
    return result


def draw_clipped_line(base: Image.Image, item: dict, points: list[list[float]], mask: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).line([tuple(point) for point in points], fill=tuple(item["line_rgba"]),
                               width=item["line_width"], joint="curve")
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return Image.alpha_composite(base, layer)


def make_states(source: Image.Image, item: dict) -> tuple[dict[str, Image.Image], Image.Image]:
    mask = poly_mask(source.size, item["eye_mask"])
    cover = ImageChops.multiply(poly_mask(source.size, item["half_cover"]), mask)
    inpainted = wataru_skin_bands(source, item, mask) if item["id"] == "wataru" else nearby_skin(source, item, mask)
    half = source.copy()
    half_fill = repairer_skin_bands(source, item, mask) if item["id"] == "repairer" else inpainted
    half.paste(half_fill, (0, 0), cover)
    half = draw_clipped_line(half, item, item["half_lid"], mask)
    closed = source.copy()
    closed.paste(inpainted, (0, 0), mask)
    closed = draw_clipped_line(closed, item, item["closed_lid"], mask)
    return {"open": source.copy(), "half": half, "closed": closed}, mask


def assert_pixels(source: Image.Image, states: dict[str, Image.Image], mask: Image.Image, char_id: str) -> None:
    src, mp = source.load(), mask.load()
    for state, image in states.items():
        if image.mode != "RGBA" or image.size != (832, 1216):
            raise AssertionError(f"wrong output format: {char_id}/{state}")
        out = image.load()
        for y in range(source.height):
            for x in range(source.width):
                if not mp[x, y] and src[x, y] != out[x, y]:
                    raise AssertionError(f"outside-eye pixel changed: {char_id}/{state} ({x},{y})")
    if states["open"].tobytes() != source.tobytes():
        raise AssertionError(f"open state is not exact source: {char_id}")
    if char_id == "wataru":
        closed = states["closed"].load()
        for y in range(171, 192):
            for x in range(470, 499):
                if mp[x, y] and closed[x, y][0] > 230 and closed[x, y][1] > 210 and closed[x, y][2] > 185:
                    raise AssertionError(f"closed Wataru retains bright sclera pixel ({x},{y})={closed[x, y]}")
    for a, b in (("open", "half"), ("half", "closed"), ("open", "closed")):
        if ImageChops.difference(states[a].convert("RGB"), states[b].convert("RGB")).getbbox() is None:
            raise AssertionError(f"blink states are not distinct: {char_id} {a}/{b}")


def composite_crop(image: Image.Image, box: list[int], scale: int, axes: bool = False) -> Image.Image:
    x0, y0, x1, y1 = box
    crop = image.crop(tuple(box))
    bg = Image.new("RGBA", crop.size, (128, 128, 128, 255))
    bg.alpha_composite(crop)
    enlarged = bg.resize((crop.width * scale, crop.height * scale), Image.Resampling.NEAREST).convert("RGB")
    if not axes:
        return enlarged
    pad = 28
    out = Image.new("RGB", (enlarged.width + pad, enlarged.height + pad), (37, 42, 51))
    out.paste(enlarged, (pad, pad))
    d = ImageDraw.Draw(out)
    for x in range(x0 - x0 % 5, x1 + 1, 5):
        px = pad + (x - x0) * scale
        d.line((px, pad - 5, px, pad), fill="white")
        if x % 10 == 0:
            d.text((px - 6, 2), str(x), fill="white")
    for y in range(y0 - y0 % 5, y1 + 1, 5):
        py = pad + (y - y0) * scale
        d.line((pad - 5, py, pad, py), fill="white")
        if y % 10 == 0:
            d.text((2, py - 4), str(y), fill="white")
    return out


def write_output(root: Path, output: Path, items: list[dict], source_index: dict[str, dict], overrides: dict[str, Path] | None = None) -> dict[str, dict[str, str]]:
    output.mkdir(parents=True, exist_ok=True)
    output_hashes: dict[str, dict[str, str]] = {}
    manifest_path = output / "manifest.json"
    if manifest_path.is_file():
        out_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    else:
        out_manifest = {"status": "pending_visual_review", "note": "Candidates are not approved for runtime; inspect every contact sheet. Open images are exact source copies.", "characters": {}}
    out_manifest.setdefault("status", "pending_visual_review")
    out_manifest.setdefault("note", "Candidates are not approved for runtime; inspect every contact sheet. Open images are exact source copies.")
    out_manifest.setdefault("characters", {})
    for item in items:
        source = verify_source(root, item, source_index, (overrides or {}).get(item["id"]))
        states, mask = make_states(source, item)
        assert_pixels(source, states, mask, item["id"])
        target_dir = output / "characters" / item["id"]
        target_dir.mkdir(parents=True, exist_ok=True)
        output_hashes[item["id"]] = {}
        for state, image in states.items():
            path = target_dir / f"{state}.png"
            image.save(path, format="PNG", optimize=False)
            saved = Image.open(path)
            if saved.mode != "RGBA" or saved.size != source.size or saved.tobytes() != image.tobytes():
                raise AssertionError(f"saved PNG pixels differ from candidate: {item['id']}/{state}")
            output_hashes[item["id"]][state] = digest(path)
        mask.save(target_dir / "eye_mask.png")

        # Contact sheet: three gray-composited head states, then the same three eye crops at 12x.
        overview = [composite_crop(states[s], item["head_bbox"], 2) for s in ("open", "half", "closed")]
        detail = [composite_crop(states[s], item["detail_crop"], 12, axes=True) for s in ("open", "half", "closed")]
        gutter, title_h, label_h = 8, 20, 18
        row1_h, row2_h = max(im.height for im in overview), max(im.height for im in detail)
        width = max(sum(im.width for im in overview) + 2 * gutter, sum(im.width for im in detail) + 2 * gutter)
        sheet = Image.new("RGB", (width, title_h + label_h + row1_h + gutter + label_h + row2_h + gutter), (31, 35, 43))
        draw = ImageDraw.Draw(sheet)
        draw.text((8, 4), f"{item['id']} | open / half / closed | CPU candidate | eye detail: 12x nearest", fill=(245, 245, 245))
        y = title_h + label_h
        x = gutter
        for state, image in zip(("open", "half", "closed"), overview):
            draw.text((x, title_h), f"{state} head", fill=(245, 245, 245))
            sheet.paste(image, (x, y))
            x += image.width + gutter
        y += row1_h + gutter + label_h
        x = gutter
        for state, image in zip(("open", "half", "closed"), detail):
            draw.text((x, y - label_h), f"{state} eye", fill=(245, 245, 245))
            sheet.paste(image, (x, y))
            x += image.width + gutter
        sheet.save(output / f"{item['id']}-contact.png")
        out_manifest["characters"][item["id"]] = {
            "source": item["source"], "source_sha256": item["sha256"], "native_canvas": list(source.size),
            "eye_mask": item["eye_mask"], "half_cover": item["half_cover"], "half_lid": item["half_lid"],
            "closed_lid": item["closed_lid"], "confidence": item["confidence"], "notes": item["notes"],
            "skin_fill_method": item.get("skin_fill_method", "same-character local skin sample (median 3x3)" if item.get("skin_sample_offset") else "harmonic continuation from eye-mask boundary"),
            "skin_donor_bands": item.get("skin_donor_bands"),
            "random_seed": item.get("random_seed"),
            "skin_sample_offset": item.get("skin_sample_offset"),
            "outputs_sha256": output_hashes[item["id"]],
            "visual_status": item.get("visual_status", "candidate_pending_root_review"),
            "visual_review_note": item.get("visual_review_note", "Source-local candidate; root must approve visual quality.")
        }
    (output / "manifest.json").write_text(json.dumps(out_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return output_hashes


def self_test() -> None:
    items, source_index = load_config()
    transparent_pixel = Image.new("RGBA", (1, 1), (10, 20, 30, 0))
    if composite_crop(transparent_pixel, [0, 0, 1, 1], 1).getpixel((0, 0)) != (128, 128, 128):
        raise AssertionError("transparent pixels are not composited against gray")
    with tempfile.TemporaryDirectory(prefix="corrected-eye-candidates-") as temp:
        temp_path = Path(temp)
        one = write_output(ROOT, temp_path / "one", items, source_index)
        two = write_output(ROOT, temp_path / "two", items, source_index)
        if one != two:
            raise AssertionError("repeated candidate builds differ")
        bad_path = temp_path / "wrong-source.png"
        bad = Image.open(ROOT / items[0]["source"]).copy()
        px = bad.getpixel((1, 1))
        bad.putpixel((1, 1), (px[0] ^ 1, px[1], px[2], px[3]))
        bad.save(bad_path)
        try:
            verify_source(ROOT, items[0], source_index, bad_path)
        except ValueError as error:
            if "hash mismatch" not in str(error):
                raise
        else:
            raise AssertionError("bad source was accepted")
    print("PASS: source hashes, native RGBA 832x1216, exact open, masked outside-pixel equality, 3 distinct states, bad-source rejection, deterministic rerun")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="run CPU-only self checks without writing deliverables")
    parser.add_argument("--ids", nargs="+", help="regenerate only the named candidate ids")
    args = parser.parse_args()
    items, source_index = load_config()
    if args.check:
        self_test()
    else:
        if args.ids:
            unknown = set(args.ids) - {item["id"] for item in items}
            if unknown:
                parser.error(f"unknown candidate ids: {sorted(unknown)}")
            items = [item for item in items if item["id"] in set(args.ids)]
        hashes = write_output(ROOT, HERE, items, source_index)
        print(f"Wrote {sum(len(states) for states in hashes.values())} native RGBA states and {len(hashes)} review contacts to {HERE}")


if __name__ == "__main__":
    main()
