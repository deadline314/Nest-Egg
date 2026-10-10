#!/usr/bin/env python3
"""Build and verify constrained, source-space blink candidates (CPU only)."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw

from cut_layers import part_transform, render_part, validate_eye_state_sources
from cut_rig_parts import frame


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "art_src/characters/eye_layers"))
DATA = ROOT / "art_src/characters/eye_layers/sources.json"
OUT = ROOT / "art_src/characters/eye_layers/candidates"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def legacy_render_part(source: Image.Image, part: dict, joints: dict[str, np.ndarray], k: float) -> np.ndarray | None:
    """Test-only copy of the pre-refactor cut math for byte-parity regression."""
    arr = np.array(source).astype(np.float32)
    pm = arr.copy()
    pm[:, :, :3] *= pm[:, :, 3:4] / 255.0
    pm = cv2.resize(pm, None, fx=k, fy=k, interpolation=cv2.INTER_AREA)
    arr = pm.copy()
    arr[:, :, :3] = pm[:, :, :3] / np.maximum(pm[:, :, 3:4] / 255.0, 1e-3)
    alpha = arr[:, :, 3]
    prem = arr[:, :, :3] * (alpha[:, :, None] / 255.0)
    ys, xs = np.nonzero(alpha > 20)
    if not len(ys):
        return None
    a_pt, b_pt = joints[part["from"]], joints[part["to"]]
    pivot_pt = joints[part.get("pivot", part["from"])]
    ex, ey = frame(part["mode"], a_pt, b_pt)
    rel = np.stack([xs, ys], 1) - pivot_pt
    u, v = rel @ ex, rel @ ey
    lo, hi = part.get("y", (0, source.height))
    pad_top, pad_bottom = (0 if lo > 0 else 3), (1 if hi < source.height else 3)
    umin, umax, vmin, vmax = u.min() - 3, u.max() + 3, v.min() - pad_top, v.max() + pad_bottom
    width, height = int(np.ceil(umax - umin)), int(np.ceil(vmax - vmin))
    pivot = np.array([-umin, -vmin])
    affine = np.float32([
        [ex[0], ey[0], pivot_pt[0] - pivot[0] * ex[0] - pivot[1] * ey[0]],
        [ex[1], ey[1], pivot_pt[1] - pivot[0] * ex[1] - pivot[1] * ey[1]],
    ])
    flags = cv2.INTER_CUBIC | cv2.WARP_INVERSE_MAP
    warped_alpha = np.clip(cv2.warpAffine(alpha, affine, (width, height), flags=flags), 0, 255)
    warped_premul = cv2.warpAffine(prem, affine, (width, height), flags=flags)
    color = np.clip(warped_premul / np.maximum(warped_alpha[:, :, None] / 255.0, 1e-3), 0, 255)
    color[warped_alpha < 4] = 0
    return np.dstack([color, warped_alpha]).astype(np.uint8)


def load_sources() -> list[dict]:
    return json.loads(DATA.read_text(encoding="utf-8"))


def checked_source(root: Path, entry: dict, override: Path | None = None) -> tuple[Path, Image.Image]:
    path = override or (root / entry["source"])
    if not path.is_file():
        raise ValueError(f"missing source for {entry['id']}: {path}")
    actual = sha256(path)
    if actual != entry["sha256"]:
        raise ValueError(f"source hash mismatch for {entry['id']}: {path}; expected {entry['sha256']}, got {actual}")
    image = Image.open(path)
    if image.mode != "RGBA" or image.size != tuple(entry["canvas"]):
        raise ValueError(f"invalid source format for {entry['id']}: {path}; expected RGBA {entry['canvas']}, got {image.mode} {image.size}")
    return path, image.copy()


def polygon_mask(size: tuple[int, int], points: list[list[int]]) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in points], fill=255)
    return mask


def draw_curve(draw: ImageDraw.ImageDraw, points: list[list[int]], color: tuple[int, int, int, int], width: int = 1) -> None:
    draw.line([tuple(p) for p in points], fill=color, width=width, joint="curve")


def skin_fill(source: Image.Image, entry: dict) -> Image.Image:
    """Copy nearby source skin texture, only inside the hand-fitted eye mask."""
    width, height = source.size
    mask = polygon_mask(source.size, entry["eye_mask"])
    out = source.copy()
    src = source.load()
    dst = out.load()
    mask_px = mask.load()
    xs = [p[0] for p in entry["eye_mask"]]
    ys = [p[1] for p in entry["eye_mask"]]
    for x in range(max(0, min(xs)), min(width, max(xs) + 1)):
        rows = [y for y in range(max(0, min(ys)), min(height, max(ys) + 1)) if mask_px[x, y]]
        if not rows:
            continue
        dx, dy = entry["skin_sample_offset"]
        for y in rows:
            sx, sy = min(width - 1, max(0, x + dx)), min(height - 1, max(0, y + dy))
            donor = src[sx, sy]
            if donor[3] == 0 or max(donor[:3]) < 55:
                nearby = [src[nx, ny] for ny in range(max(0, sy - 2), min(height, sy + 3))
                          for nx in range(max(0, sx - 2), min(width, sx + 3))
                          if src[nx, ny][3] > 200 and max(src[nx, ny][:3]) >= 55]
                if not nearby:
                    raise ValueError(f"no opaque nearby skin sample for {entry['id']} at ({x},{y})")
                donor = max(nearby, key=lambda pixel: sum(pixel[:3]))
            dst[x, y] = donor
    return out


def make_candidates(root: Path, output: Path, sources: list[dict], overrides: dict[str, Path] | None = None) -> dict[str, dict[str, str]]:
    output.mkdir(parents=True, exist_ok=True)
    results: dict[str, dict[str, str]] = {}
    for entry in sources:
        _, source = checked_source(root, entry, (overrides or {}).get(entry["id"]))
        mask = polygon_mask(source.size, entry["eye_mask"])
        states = {"open": source.copy()}

        half = source.copy()
        underpaint = skin_fill(source, entry)
        half_mask = polygon_mask(source.size, entry["half_cover"])
        half.paste(underpaint, (0, 0), half_mask)
        half_lines = Image.new("RGBA", source.size, (0, 0, 0, 0))
        draw_curve(ImageDraw.Draw(half_lines), entry["half_lid"], tuple(entry["line_rgba"]), 1)
        half_lines.putalpha(ImageChops.multiply(half_lines.getchannel("A"), mask))
        half = Image.alpha_composite(half, half_lines)
        states["half"] = half

        closed = source.copy()
        closed.paste(underpaint, (0, 0), mask)
        closed_lines = Image.new("RGBA", source.size, (0, 0, 0, 0))
        closed_draw = ImageDraw.Draw(closed_lines)
        draw_curve(closed_draw, entry["closed_lid"], tuple(entry["line_rgba"]), 1)
        if entry.get("closed_crease"):
            draw_curve(closed_draw, entry["closed_crease"], tuple(entry["crease_rgba"]), 1)
        closed_lines.putalpha(ImageChops.multiply(closed_lines.getchannel("A"), mask))
        closed = Image.alpha_composite(closed, closed_lines)
        states["closed"] = closed

        # Every edit, including linework, must stay within the manually fitted eye region.
        for state, image in states.items():
            if image.mode != "RGBA" or image.size != tuple(entry["canvas"]):
                raise AssertionError(f"wrong output format for {entry['id']}/{state}")
            src_px, out_px, mask_px = source.load(), image.load(), mask.load()
            for y in range(source.height):
                for x in range(source.width):
                    if not mask_px[x, y] and src_px[x, y] != out_px[x, y]:
                        raise AssertionError(f"outside-eye pixel changed: {entry['id']}/{state} ({x},{y})")
        if any(ImageChops.difference(states[a].convert("RGB"), states[b].convert("RGB")).getbbox() is None for a, b in (("open", "half"), ("half", "closed"), ("open", "closed"))):
            raise AssertionError(f"blink states are not distinct for {entry['id']}")

        char_dir = output / entry["id"]
        char_dir.mkdir(parents=True, exist_ok=True)
        results[entry["id"]] = {}
        for state, image in states.items():
            target = char_dir / f"{state}.png"
            image.save(target, format="PNG", optimize=False)
            results[entry["id"]][state] = sha256(target)
        # A monochrome target mask lets reviewers see the exact manually selected eye area.
        mask.save(char_dir / "eye_mask.png")
    manifest = {
        "status": "rejected_visual_review",
        "note": "Source-space candidates are diagnostic only; do not consume as runtime blink layers until visual review passes.",
        "candidates": {
            entry["id"]: {
                "source": entry["source"],
                "source_sha256": entry["sha256"],
                "canvas": entry["canvas"],
                "eye_mask": entry["eye_mask"],
                "half_cover": entry["half_cover"],
                "outputs_sha256": results[entry["id"]],
            }
            for entry in sources
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return results


def self_test() -> None:
    sources = load_sources()
    with tempfile.TemporaryDirectory(prefix="eye-layer-check-") as temp:
        base = Path(temp)
        first, second = base / "first", base / "second"
        one = make_candidates(ROOT, first, sources)
        two = make_candidates(ROOT, second, sources)
        if one != two:
            raise AssertionError("rerun produced different candidate hashes")

        bad = base / "bad.png"
        item = sources[0]
        image = Image.open(ROOT / item["source"]).convert("RGBA")
        image.putpixel((0, 0), (0, 0, 0, 0) if image.getpixel((0, 0))[3] else (1, 1, 1, 255))
        image.save(bad)
        try:
            checked_source(ROOT, item, bad)
        except ValueError as error:
            if "source hash mismatch" not in str(error):
                raise
        else:
            raise AssertionError("modified source was accepted")
    print(f"PASS: {len(sources)} sources; RGBA/native size/hash; unchanged pixels outside eye masks; distinct states; deterministic rerun; modified source rejected")


def test_cut_layer_eye_state_validation() -> None:
    """Exercise the cut-layer source gate with tiny CPU-only fixtures."""
    with tempfile.TemporaryDirectory(prefix="eye-state-source-gate-") as temp:
        base = Path(temp)
        original_path = base / "head.png"
        half_path = base / "half.png"
        closed_path = base / "closed.png"
        original = Image.new("RGBA", (16, 12), (154, 91, 66, 255))
        pixels = original.load()
        for y in range(4, 8):
            for x in range(5, 11):
                pixels[x, y] = (20 + x, 10 + y, 4, 255)
        original.save(original_path)
        half, closed = original.copy(), original.copy()
        half.putpixel((7, 5), (154, 91, 66, 255))
        closed.putpixel((7, 5), (99, 52, 44, 255))
        half.save(half_path)
        closed.save(closed_path)

        def metadata(half_source: Path = half_path, closed_source: Path = closed_path) -> dict:
            return {
                "part": "head",
                "eye_mask": [[4, 3], [11, 3], [11, 8], [4, 8]],
                "sources": {
                    "original_head": {"path": str(original_path), "sha256": sha256(original_path)},
                    "half": {"path": str(half_source), "sha256": sha256(half_source)},
                    "closed": {"path": str(closed_source), "sha256": sha256(closed_source)},
                },
            }

        selected, variants = validate_eye_state_sources(metadata(), original_path, (16, 12))
        if selected.size != (16, 12) or set(variants) != {"half", "closed"}:
            raise AssertionError("valid native source variants were not returned")

        def must_reject(config: dict, expected: str) -> None:
            try:
                validate_eye_state_sources(config, original_path, (16, 12))
            except ValueError as error:
                if expected not in str(error):
                    raise AssertionError(f"wrong rejection reason; wanted {expected!r}, got {error!r}") from error
            else:
                raise AssertionError(f"invalid eye-state source accepted; expected {expected}")

        bad_hash = metadata()
        bad_hash["sources"]["half"]["sha256"] = "0" * 64
        must_reject(bad_hash, "hash mismatch")
        outside = base / "outside.png"
        changed = original.copy()
        changed.putpixel((1, 1), (2, 3, 4, 255))
        changed.save(outside)
        must_reject(metadata(half_source=outside), "outside eye_mask")
        alpha = base / "alpha.png"
        changed_alpha = original.copy()
        changed_alpha.putpixel((7, 5), (154, 91, 66, 0))
        changed_alpha.save(alpha)
        must_reject(metadata(closed_source=alpha), "changed source alpha")
        wrong_canvas = base / "wrong-canvas.png"
        Image.new("RGBA", (15, 12), (154, 91, 66, 255)).save(wrong_canvas)
        must_reject(metadata(half_source=wrong_canvas), "must be native RGBA")
        bad_point = metadata()
        bad_point["eye_mask"][0] = [-1, 3]
        must_reject(bad_point, "outside")
    print("PASS: cut-layer eye-state gate accepts valid native variants and rejects bad hash, outside-mask edits, alpha edits, wrong canvas, and out-of-bounds masks")


def test_private_export_reproducibility() -> None:
    """Check all nine transforms twice without touching published open textures."""
    from export_candidates import PRIVATE_EXPORT_ROOT, RECIPE, ROOT, export, read_json, source_head_path

    recipe = read_json(RECIPE)
    candidate_manifest = read_json(ROOT / recipe["candidate_manifest"])
    open_hashes = {}
    input_hashes = {}
    for skin_id, mapping in recipe["characters"].items():
        skin = read_json(ROOT / mapping["recipe"])
        actual_skin_id = skin["id"]
        spec = read_json(ROOT / skin["spec"])
        work = ROOT / skin["work"]
        k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
        joints = {name: np.array(point, dtype=float) * k for name, point in spec["joints"].items()}
        for part_name, part in spec["parts"].items():
            source_path = source_head_path(work, part_name)
            with Image.open(source_path) as source_file:
                source = source_file.convert("RGBA")
            legacy = legacy_render_part(source, part, joints, k)
            transform = part_transform(source, part, joints, k)
            current = None if transform is None else render_part(source, transform, k)
            if legacy is None or current is None:
                if legacy is not current:
                    raise AssertionError(f"{skin_id}/{part_name}: helper changed empty-part handling")
            elif not np.array_equal(legacy, current):
                changed = int(np.count_nonzero(np.any(legacy != current, axis=2)))
                raise AssertionError(f"{skin_id}/{part_name}: shared cut helper differs from original math at {changed} pixels")
        char = read_json(ROOT / "art" / "characters" / actual_skin_id / "character.json")
        open_path = ROOT / "art" / "characters" / actual_skin_id / char["textures"]["head"]["file"]
        open_hashes[open_path] = sha256(open_path)
        candidate = candidate_manifest["characters"][mapping["candidate_id"]]
        input_hashes[ROOT / candidate["source"]] = candidate["source_sha256"]
        candidate_dir = ROOT / "art_src/characters/eye_layers/corrected_candidates/characters" / mapping["candidate_id"]
        input_hashes[candidate_dir / "half.png"] = candidate["outputs_sha256"]["half"]
        input_hashes[candidate_dir / "closed.png"] = candidate["outputs_sha256"]["closed"]

    PRIVATE_EXPORT_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="eye-export-repro-", dir=PRIVATE_EXPORT_ROOT) as temp:
        base = Path(temp)
        first, second = base / "first", base / "second"
        sentinel_output = base / "preserved-output"
        sentinel_output.mkdir()
        sentinel = sentinel_output / "sentinel.txt"
        sentinel.write_text("keep existing private output", encoding="utf-8")
        malformed_recipe = json.loads(json.dumps(recipe))
        first_mapping = next(iter(malformed_recipe["characters"].values()))
        first_mapping["recipe"] = "tools/comfyui/recipes/__missing_eye_export_fixture__.json"
        bad_recipe = base / "bad-recipe.json"
        bad_recipe.write_text(json.dumps(malformed_recipe), encoding="utf-8")
        try:
            export(ROOT, bad_recipe, sentinel_output)
        except (FileNotFoundError, ValueError):
            pass
        else:
            raise AssertionError("malformed source recipe unexpectedly exported")
        if sentinel.read_text(encoding="utf-8") != "keep existing private output":
            raise AssertionError("failed export partially replaced the existing private output")
        outside = Path(tempfile.mkdtemp(prefix="eye-export-outside-", dir=ROOT / ".godot"))
        outside_sentinel = outside / "sentinel.txt"
        outside_sentinel.write_text("outside private export", encoding="utf-8")
        try:
            try:
                export(ROOT, RECIPE, outside)
            except ValueError as error:
                if "must stay under the private export directory" not in str(error):
                    raise
            else:
                raise AssertionError("export accepted a destination outside the private export root")
            if outside_sentinel.read_text(encoding="utf-8") != "outside private export":
                raise AssertionError("rejected outside destination was modified")
        finally:
            import shutil
            if (ROOT / ".godot").resolve() not in outside.resolve().parents:
                raise AssertionError(f"test cleanup target escaped .godot: {outside.resolve()}")
            shutil.rmtree(outside)

        collision = first.with_name(first.name + ".previous")
        collision.mkdir()
        collision_sentinel = collision / "user-data.txt"
        collision_sentinel.write_text("preserve colliding sibling", encoding="utf-8")
        export(ROOT, RECIPE, first)
        export(ROOT, RECIPE, second)
        if collision_sentinel.read_text(encoding="utf-8") != "preserve colliding sibling":
            raise AssertionError("exporter modified a pre-existing sibling that resembles a backup")
        first_files = {p.relative_to(first).as_posix(): sha256(p) for p in first.rglob("*") if p.is_file()}
        second_files = {p.relative_to(second).as_posix(): sha256(p) for p in second.rglob("*") if p.is_file()}
        if first_files != second_files:
            raise AssertionError("private eye-state export rerun produced different files")
        manifest = json.loads((first / "manifest.json").read_text(encoding="utf-8"))
        for skin_id, item in manifest["characters"].items():
            actual_skin_id = read_json(ROOT / recipe["characters"][skin_id]["recipe"])["id"]
            if item["runtime_metadata"] != {
                "part": "head", "half_texture": "head_half", "closed_texture": "head_closed", "timing": {}
            }:
                raise AssertionError(f"{skin_id}: runtime metadata leaks or differs from the agreed schema")
            if item["texture_size"] != read_json(ROOT / "art/characters" / actual_skin_id / "character.json")["textures"]["head"]["size"]:
                raise AssertionError(f"{skin_id}: exported state texture size differs from formal head")
            if item["pivot"] != read_json(ROOT / "art/characters" / actual_skin_id / "character.json")["textures"]["head"]["pivot"]:
                raise AssertionError(f"{skin_id}: exported state pivot differs from formal head")
            for state in ("half", "closed"):
                part = first / item["states"][state]["diffuse"]
                with Image.open(part) as image:
                    if image.mode != "RGBA":
                        raise AssertionError(f"{skin_id}/{state}: exported diffuse is not RGBA")
        for path, expected in input_hashes.items():
            if sha256(path) != expected:
                raise AssertionError(f"source changed during export test: {path}")
        for path, expected in open_hashes.items():
            if sha256(path) != expected:
                raise AssertionError(f"published open head changed during export test: {path}")
    print("PASS: shared cut helpers match old rendering byte-for-byte across every recipe part set; every open head rebuilds byte-exactly and preserve size/pivot; deterministic rerun, source/open hashes unchanged")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="run offline source and reproducibility checks")
    parser.add_argument("--out", type=Path, default=OUT, help="candidate output directory")
    args = parser.parse_args()
    if args.check:
        self_test()
        test_cut_layer_eye_state_validation()
        test_private_export_reproducibility()
    else:
        generated = make_candidates(ROOT, args.out, load_sources())
        print(f"Wrote {sum(len(states) for states in generated.values())} native-resolution blink candidates to {args.out}")


if __name__ == "__main__":
    main()
