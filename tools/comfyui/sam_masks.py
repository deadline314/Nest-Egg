"""Segment an illustration with SAM 3.1 (ComfyUI native nodes) by text prompt; one mask PNG per prompt.

Needs ComfyUI running and models/checkpoints/sam3.1_multiplex_fp16.safetensors
(https://huggingface.co/Comfy-Org/sam3.1).

Usage:
    python sam_masks.py --image rin_tall.png --out masks_dir --prompt "ponytail hair" --prompt "jacket" ...
Writes <out>/<slug>.png (white = the prompted object, all instances merged) and prints each mask's coverage.
"""
import argparse
import re
import uuid
from pathlib import Path

from comfy_api import run, upload
import comfy_guard

SAM_CKPT = "sam3.1_multiplex_fp16.safetensors"


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def segment(image_path: str, prompts: list[str], out_dir: str, threshold: float = 0.4, refine: int = 2) -> dict:
    """Return {prompt: Path}. Prompts that find nothing produce an empty (black) mask."""
    comfy_guard.ensure_server()
    name = upload(image_path)
    g = {"load": {"class_type": "LoadImage", "inputs": {"image": name}},
         "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": SAM_CKPT}}}
    for i, text in enumerate(prompts):
        g[f"t{i}"] = {"class_type": "CLIPTextEncode", "inputs": {"clip": ["ckpt", 1], "text": text}}
        g[f"d{i}"] = {"class_type": "SAM3_Detect", "inputs": {"model": ["ckpt", 0], "image": ["load", 0], "conditioning": [f"t{i}", 0],
                                                              "threshold": threshold, "refine_iterations": refine, "individual_masks": False}}
        g[f"m{i}"] = {"class_type": "MaskToImage", "inputs": {"mask": [f"d{i}", 0]}}
        g[f"s{i}"] = {"class_type": "SaveImage", "inputs": {"images": [f"m{i}", 0], "filename_prefix": f"sam_{uuid.uuid4().hex[:6]}_{i}"}}
    job = "sam_" + uuid.uuid4().hex[:8]
    paths = run(g, job)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").touch()
    result = {}
    for i, text in enumerate(prompts):
        source = next(p for p in paths if p.name == (f"{job}_s{i}_0.png" if len(prompts) > 1 else f"{job}_0.png"))
        data = source.read_bytes()
        path = out / f"{slug(text)}.png"
        path.write_bytes(data)
        result[text] = path
    return result


def main() -> None:
    from PIL import Image
    import numpy as np
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--prompt", action="append", required=True)
    ap.add_argument("--threshold", type=float, default=0.4)
    args = ap.parse_args()
    for text, path in segment(args.image, args.prompt, args.out, args.threshold).items():
        cover = (np.array(Image.open(path).convert("L")) > 127).mean() * 100
        print(f"{text!r}: {cover:.1f}% of image -> {path}")



def segment_points(image_path: str, out_dir: str, jobs: dict, threshold: float = 0.3, refine: int = 2) -> dict:
    """Point-prompted segmentation: jobs = {name: {"pos": [(x, y), ...], "neg": [(x, y), ...]}} (pixels of the picture).
    Lets SAM cut finer than a text prompt can, e.g. only the forearm of a one-piece prosthetic arm."""
    import json
    comfy_guard.ensure_server()
    name = upload(image_path)
    g = {"load": {"class_type": "LoadImage", "inputs": {"image": name}},
         "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": SAM_CKPT}}}
    for i, (key, pts) in enumerate(jobs.items()):
        g[f"d{i}"] = {"class_type": "SAM3_Detect", "inputs": {
            "model": ["ckpt", 0], "image": ["load", 0], "threshold": threshold, "refine_iterations": refine, "individual_masks": False,
            "positive_coords": json.dumps([{"x": int(x), "y": int(y)} for x, y in pts.get("pos", [])]),
            "negative_coords": json.dumps([{"x": int(x), "y": int(y)} for x, y in pts.get("neg", [])])}}
        g[f"m{i}"] = {"class_type": "MaskToImage", "inputs": {"mask": [f"d{i}", 0]}}
        g[f"s{i}"] = {"class_type": "SaveImage", "inputs": {"images": [f"m{i}", 0], "filename_prefix": f"sampt_{uuid.uuid4().hex[:6]}_{i}"}}
    job = "sam_" + uuid.uuid4().hex[:8]
    paths = run(g, job)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    result = {}
    for i, key in enumerate(jobs):
        source = next(p for p in paths if p.name == (f"{job}_s{i}_0.png" if len(jobs) > 1 else f"{job}_0.png"))
        path = out / f"{slug(key)}.png"
        path.write_bytes(source.read_bytes())
        result[key] = path
    return result


if __name__ == "__main__":
    main()
