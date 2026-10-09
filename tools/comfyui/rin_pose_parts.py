"""Cut annotated Rin pose candidates without publishing them to the game.

python tools/comfyui/rin_pose_parts.py
Source pixels are cropped, never resized or straightened. Source-space pivots
and masks remain available for the subsequent pose binding/transition review.
"""
import json
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art_src/characters/rin_pose_variants"


def build(work=WORK):
    spec = json.loads((work / "poses.json").read_text(encoding="utf-8"))
    output = work / "03_parts"
    report = {}
    images, documents = [], []
    for name, pose in spec.items():
        path = work / pose["source"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == pose["source_sha256"], f"{name}: source hash mismatch"
        with Image.open(path) as image:
            assert image.mode == "RGBA", f"{name}: source must be RGBA"
            source = np.array(image)
        if pose.get("matte") == "border":
            # SAM loses the heel here; use the existing border-connected matte.
            from cut_parts import foreground
            source[:, :, 3] = foreground(source[:, :, :3]).astype(np.uint8) * 255
        else:
            source[source[:, :, 3] <= 8] = 0
        replacement = pose.get("replacement")
        if replacement:
            path = work / replacement["image"]
            assert hashlib.sha256(path.read_bytes()).hexdigest() == replacement["sha256"], f"{name}: replacement hash mismatch"
            edited = np.array(Image.open(path).convert("RGBA"))
            assert edited.shape == source.shape, f"{name}: replacement canvas mismatch"
            region = Image.new("L", (source.shape[1], source.shape[0]))
            ImageDraw.Draw(region).polygon([tuple(p) for p in replacement["polygon"]], fill=255)
            take = (np.array(region) > 0) & (source[:, :, 3] > 8)
            source[take, :3] = edited[take, :3]
        for polygon in pose.get("clear_polygons", []):
            clear = Image.new("L", (source.shape[1], source.shape[0]))
            ImageDraw.Draw(clear).polygon([tuple(p) for p in polygon], fill=255)
            source[np.array(clear) > 0] = 0
        source[source[:, :, 3] == 0] = 0
        assert all(edge.max() == 0 for edge in (source[0, :, 3], source[-1, :, 3], source[:, 0, 3], source[:, -1, 3])), f"{name}: clipped subject or opaque background"
        folder = output / name
        images.append((folder / "source_rgba.png", Image.fromarray(source)))
        union = np.zeros(source.shape[:2], dtype=bool)
        ownership = np.zeros_like(source)
        metadata = dict(source=pose["source"], source_sha256=hashlib.sha256((work / pose["source"]).read_bytes()).hexdigest(),
                        status="candidate: final anatomy, contacts and transitions require native review",
                        px_per_world=pose["px_per_world"], waist=pose["waist"], joints=pose["joints"], parts=[])
        metadata["clear_polygons"] = pose.get("clear_polygons", [])
        metadata["clear_reason"] = pose.get("clear_reason", "")
        metadata["replacement"] = replacement
        metadata["review_adjustment"] = pose.get("review_adjustment", {})
        metadata["waist_alignment"] = pose.get("waist_alignment", "")
        for i, part in enumerate(pose["parts"]):
            mask_image = Image.new("L", (source.shape[1], source.shape[0]))
            ImageDraw.Draw(mask_image).polygon([tuple(p) for p in part["polygon"]], fill=255)
            mask = np.array(mask_image) > 0
            layer = source.copy()
            layer[~mask] = 0
            solid = layer[:, :, 3] > 20
            assert solid.any(), f"{name}/{part['name']}: empty"
            _, count = ndimage.label(layer[:, :, 3] > 0)
            assert count == 1, f"{name}/{part['name']}: detached fragment"
            ys, xs = np.nonzero(layer[:, :, 3] > 0)
            box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
            path = folder / (part["name"] + ".png")
            cropped = Image.fromarray(layer).crop(box)
            images.append((path, cropped))
            images.append((folder / (part["name"] + "_mask.png"), mask_image))
            pivot = pose["joints"][part["joint"]]
            entry = {k: v for k, v in part.items() if k != "polygon"}
            entry.update(file=path.name, box=list(box), pivot=[pivot[0]-box[0], pivot[1]-box[1]],
                         source_pixels=int(solid.sum()), components=int(count))
            metadata["parts"].append(entry)
            union |= layer[:, :, 3] > 0
            color = [(i * 73 + 45) % 230, (i * 127 + 55) % 230, (i * 193 + 65) % 230, 255]
            ownership[solid] = color
        missing = int(((source[:, :, 3] > 0) & ~union).sum())
        assert missing == 0, f"{name}: {missing} unassigned source pixels"
        metadata["unassigned_pixels"] = missing
        images.append((folder / "ownership.png", Image.fromarray(ownership)))
        documents.append((folder / "parts.json", metadata))
        report[name] = {"parts": len(metadata["parts"]), "unassigned_pixels": missing,
                        "components": {p["name"]: p["components"] for p in metadata["parts"]}}
    # Validate every pose before replacing any candidate output.
    output.mkdir(exist_ok=True)
    (output / ".gdignore").touch()
    for path, image in images:
        path.parent.mkdir(exist_ok=True)
        image.save(path)
    for path, metadata in documents:
        for part in metadata["parts"]:
            part["sha256"] = hashlib.sha256((path.parent / part["file"]).read_bytes()).hexdigest()
        path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
    print(json.dumps(report, indent=2))
    return report


if __name__ == "__main__":
    build()
