"""Make the half-closed and closed eye pictures of a character's head and register them in its spec (spec.eye_states).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/make_eye_states.py --recipe tools/comfyui/recipes/lu.json

Run it after the refine step and before textures (it needs <work>/07_refined/head.png). Steps:
  1. crop a square around the head from base_rgba.png and let Qwen redraw it twice (eye half closed, eye closed); a finished job is reused,
     so only the first run needs the GPU. Raw outputs: <work>/eyes/raw/
  2. find where the closed-eye picture differs from the open one (the eye), and use that box, slightly grown, as spec.eye_states.eye_mask
     unless the spec already has a mask (a reviewed mask is never replaced)
  3. write <work>/eyes/half.png and closed.png = 07_refined/head.png with only the pixels inside the mask replaced, alpha untouched
     (exactly what cut_layers.validate_eye_state_sources demands), and write their hashes into the spec
Run it again whenever 07_refined/head.png changed: step 1 is skipped, 2 keeps the mask, 3 refreshes the pictures and hashes.
Always look at <work>/eyes/review.png (open | half | closed, mask outlined) before building the textures.
"""
import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
PROMPTS = {
    "half": (421, "Make the eye half closed, calm and half-lidded: the upper eyelid comes down and covers the upper half of the iris, with the "
                  "same dark lash line. Same skin tone and shading. Keep everything else exactly unchanged."),
    "closed": (422, "Close the eye completely: the eyelid is shut, a single dark downward-curved lash line where the eye was, the eyelid in the "
                    "same skin tone and shading. Keep everything else exactly unchanged."),
}
RGBA = ("This is an RGBA image with transparency. ", " The image has alpha channel and the background is transparent.")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def head_box(head_alpha: np.ndarray, size: tuple[int, int]) -> tuple[int, int, int, int]:
    """A square around the head part, inside the picture, at least 256 px wide."""
    ys, xs = np.nonzero(head_alpha > 127)
    side = max(256, int(max(xs.max() - xs.min(), ys.max() - ys.min())) + 24)
    side = min(side, size[0], size[1])
    x0 = int(np.clip((xs.min() + xs.max()) // 2 - side // 2, 0, size[0] - side))
    y0 = int(np.clip((ys.min() + ys.max()) // 2 - side // 2, 0, size[1] - side))
    return x0, y0, x0 + side, y0 + side


def eye_polygon(open_rgb: np.ndarray, closed_rgb: np.ndarray, solid: np.ndarray, box: tuple[int, int, int, int]) -> list[list[int]]:
    """The box of the largest changed blob (the eye), grown by 3 px, as a polygon in picture coordinates."""
    diff = (np.abs(open_rgb.astype(int) - closed_rgb.astype(int)).max(2) > 40) & solid
    diff = cv2.morphologyEx(diff.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, _, stats, _ = cv2.connectedComponentsWithStats(diff, connectivity=8)
    if n < 2:
        raise SystemExit("[make_eye_states] the closed-eye picture does not differ from the open one: nothing to register")
    x, y, w, h, area = (int(v) for v in stats[1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))])
    if area < 20:
        raise SystemExit(f"[make_eye_states] the largest change is only {area} px: the edit did not close the eye")
    x0, y0, x1, y1 = box[0] + x - 3, box[1] + y - 3, box[0] + x + w + 3, box[1] + y + h + 3
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--recipe", required=True)
    args = ap.parse_args()
    recipe = json.loads(Path(args.recipe).read_text(encoding="utf8"))
    spec_path = ROOT / recipe["spec"]
    spec = json.loads(spec_path.read_text(encoding="utf8"))
    work = ROOT / recipe["work"]
    head_path = work / "07_refined" / "head.png"
    if not head_path.exists():
        raise SystemExit(f"[make_eye_states] {head_path} is missing - run the refine step first")
    head = np.asarray(Image.open(head_path).convert("RGBA"))
    base = Image.open(work / "base_rgba.png").convert("RGBA")
    eyes = work / "eyes"
    (eyes / "raw").mkdir(parents=True, exist_ok=True)
    (eyes / "raw" / ".gdignore").touch()
    state = spec.get("eye_states", {})
    box = tuple(state.get("head_box") or head_box(head[:, :, 3], base.size))
    reference = eyes / "raw" / "head_reference.png"
    base.crop(box).save(reference)

    os.environ["OUT_DIR"] = str(eyes / "raw")
    sys.path.insert(0, str(Path(__file__).parent))
    from comfy_api import qwen  # after OUT_DIR: the module reads it on import
    edits = {}
    for name, (seed, prompt) in PROMPTS.items():
        made = qwen(RGBA[0] + prompt + RGBA[1], images=[str(reference)], seed=seed, resolution=1024, prefix=f"{spec['id']}_eye_{name}_s{seed}")[0]
        side = box[2] - box[0]
        edits[name] = np.asarray(Image.open(made).convert("RGB").resize((side, side), Image.LANCZOS))

    x0, y0, x1, y1 = box
    polygon = state.get("eye_mask") or eye_polygon(head[y0:y1, x0:x1, :3], edits["closed"], head[y0:y1, x0:x1, 3] > 127, box)
    canvas = Image.new("L", (head.shape[1], head.shape[0]), 0)  # rasterised exactly like cut_layers.validate_eye_state_sources
    ImageDraw.Draw(canvas).polygon([(round(x), round(y)) for x, y in polygon], fill=255)
    mask = (np.asarray(canvas) > 0) & (head[:, :, 3] > 0)
    sources = {"original_head": {"path": head_path.relative_to(ROOT).as_posix(), "sha256": sha256(head_path)}}
    review = [Image.fromarray(head[y0:y1, x0:x1])]
    for name, edit in edits.items():
        out = head.copy()
        out[y0:y1, x0:x1, :3] = np.where(mask[y0:y1, x0:x1, None], edit, head[y0:y1, x0:x1, :3])
        target = eyes / f"{name}.png"
        Image.fromarray(out).save(target)
        sources[name] = {"path": target.relative_to(ROOT).as_posix(), "sha256": sha256(target)}
        review.append(Image.fromarray(out[y0:y1, x0:x1]))
        print(f"  eyes/{name}.png: {int((out != head).any(2).sum())} px differ from the open head")
    sheet = Image.new("RGBA", (review[0].width * 3, review[0].height), (120, 125, 135, 255))
    for i, tile in enumerate(review):
        sheet.alpha_composite(tile, (i * tile.width, 0))
        ImageDraw.Draw(sheet).polygon([(x - x0 + i * tile.width, y - y0) for x, y in polygon], outline=(255, 255, 0, 255))
    sheet.convert("RGB").save(eyes / "review.png")
    spec["eye_states"] = {"part": "head", "half_texture": "head_half", "closed_texture": "head_closed", "timing": state.get("timing", {}),
                          "head_box": list(box), "sources": sources, "eye_mask": polygon}
    spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"  eye_states registered in {spec_path.relative_to(ROOT)}; check {(eyes / 'review.png').relative_to(ROOT)}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
