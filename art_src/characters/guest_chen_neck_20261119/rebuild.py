"""Restore the approved chin-to-collar seam from the registered Chen portrait."""
from argparse import ArgumentParser
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part
from registered_layers import registered_layer_bytes, write_registered_file


def digest(data):
    return hashlib.sha256(data).hexdigest()


def rebuild(record):
    for name, expected in record["inputs"].items():
        path = ROOT / name
        data = path.read_bytes()
        if path.suffix in {".json", ".py"}:
            data = data.replace(b"\r\n", b"\n")
        if digest(data) != expected:
            raise ValueError(f"Chen neck source has changed: {name}")
    source = ROOT / "art_src/characters/guest_chen"
    with Image.open(source / "base_rgba.png") as image:
        author = np.array(image.convert("RGBA"))
    with Image.open(source / "07_refined/head.png") as image:
        old = image.convert("RGBA")
    previous = np.asarray(old)
    matte = Image.new("L", old.size)
    ImageDraw.Draw(matte).polygon(record["neck_polygon"], fill=255)
    scanlines = np.arange(old.height)[:, None]
    taper = np.clip((record["fade_end_y"] - scanlines) / record["fade_rows"], 0, 1)
    authors_alpha = np.rint(author[:, :, 3] * np.minimum(np.asarray(matte) / 255, taper)).astype(np.uint8)
    result = previous.copy()
    unowned = previous[:, :, 3] < 128
    use_original = unowned & (previous[:, :, 3] < authors_alpha)
    result[use_original] = author[use_original]
    result[:, :, 3][use_original] = authors_alpha[use_original]
    x = np.arange(*record["underlap_columns"])
    # Keep the moved strip connected to the existing throat at its inner edge.
    for y, offset, expected in record["underlap_rows"]:
        source_x = x - offset
        selected = unowned[y, x] & (authors_alpha[y, source_x] > result[y, x, 3])
        if int(selected.sum()) != expected:
            raise ValueError(f"Chen neck overlap has changed at source row {y}")
        result[y, x[selected]] = author[y, source_x[selected]]
        result[y, x[selected], 3] = authors_alpha[y, source_x[selected]]
    edited = Image.fromarray(result)
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_chen_side.json").read_bytes())
    scale = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.asarray(point, float) * scale for name, point in spec["joints"].items()}
    matrix, width, height, pivot = part_transform(old, spec["parts"]["head"], joints, scale)
    cut = part_transform(edited, spec["parts"]["head"], joints, scale)
    if not np.array_equal(matrix, cut[0]) or width != cut[1] or not np.array_equal(pivot, cut[3]):
        raise ValueError("Chen head source grid or pivot has changed")
    original = render_part(old, (matrix, width, height, pivot), scale)
    frame = render_part(edited, cut, scale)
    kept = original[:, :, 3] >= 128
    frame[:height][kept] = original[kept]
    if list(frame.shape[1::-1]) != record["native_size"] or digest(frame.tobytes()) != record["native_rgba_sha256"]:
        raise ValueError("Chen neck output differs from the approved native pixels")
    return edited


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--write-overrides", action="store_true")
    args = parser.parse_args()
    record = json.loads((HERE / "provenance.json").read_bytes())
    source = registered_layer_bytes({"head": rebuild(record)}, HERE, record)["head"]
    runtime = ROOT / "art/characters/guest_chen"
    compiled = (runtime / "parts/head.png").read_bytes()
    metadata = json.loads((runtime / "character.json").read_bytes())["textures"]["head"]
    if digest(compiled) != record["native_png_sha256"] or metadata["size"] != record["native_size"] or metadata["pivot"] != record["pivot"]:
        raise ValueError("Chen head runtime asset, size or pivot differs from the registered output")
    if args.write_overrides:
        overrides = ROOT / "art_src/characters/guest_chen/overrides"
        outputs = {overrides / "refined/head.png": source, overrides / "head.png": compiled}
        for target, data in outputs.items():
            if target.exists() and target.read_bytes() != data:
                raise ValueError(f"Existing unapproved override retained: {target}")
        for target, data in outputs.items():
            write_registered_file(target, data)
    print("Chen neck source, retained face, pivot and runtime output verified.")


if __name__ == "__main__":
    main()
