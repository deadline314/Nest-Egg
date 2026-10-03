"""Generate scene-sized art with Qwen Image: cutscene stage backgrounds and the near-foreground strips (NE-61 / NE-65).

Usage: python tools/assets/qwen_scenes.py [--pipeline NAME] [--only ID ...] [--regen] [--no-gen] [--sheet OUT.png]

--pipeline NAME reads assets_src/pipeline/NAME.json (list under "images"); anything but the default list inherits "styles",
"glow_presets" and "defaults" from qwen_scenes.json.

Reads assets_src/pipeline/qwen_scenes.json. Entry kinds:
  "scene"  an opaque picture (a room, a hangar...) -> resized to "px", graded, saved as WebP at "out"; bright coloured
           spots (lamps, screens, LEDs) matching the "glow" rules also go to <out>_glow.webp (the stage layer shows it
           additively and with the window-life animation).
  "strip"  a transparent strip (foreground pipes, railings) generated with the official RGBA prompt -> graded to near
           black, a faint rim light along the upward-facing edges, LEDs to the glow layer.
"ref" (an id of another entry) makes the picture an edit of that entry's raw image (e.g. the dawn version of the shop).
Prompt and seed are the "source" (no third-party art); raw images are cached in assets_src/work/qwen.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import qwen_matte as qm  # noqa: E402
import qwen_props  # noqa: E402
from comfy_guard import ComfyFailure  # noqa: E402  (qwen_props puts tools/comfyui on the path)
from qwen_props import RAW, ROOT, generate  # noqa: E402

DEFAULT_PIPELINE = ROOT / "assets_src" / "pipeline" / "qwen_scenes.json"
PIPELINE = DEFAULT_PIPELINE


def rim_light(alpha: np.ndarray, color, width_px: float, strength: float) -> np.ndarray:
    """Rim mask along the edges that face up (alpha drops just above them)."""
    k = max(1, int(round(width_px)))
    shifted = np.zeros_like(alpha)
    shifted[k:] = alpha[:-k]  # alpha moved down: pixels whose upper neighbour is empty keep a positive difference
    return np.clip(alpha - shifted, 0.0, 1.0) * strength


def process(e: dict, cfg: dict, regen: bool, no_gen: bool) -> bool:
    e = {**cfg["defaults"], **e}
    if isinstance(e.get("glow"), str):
        e["glow"] = cfg["glow_presets"][e["glow"]]
    sid = e["id"]
    e.setdefault("native_alpha", e["kind"] == "strip")
    if e.get("ref"):
        e["refs"] = [f"assets_src/work/qwen/{e['ref']}.png"]
    size = (e["px"][0], e["px"][1])
    src = RAW / f"{sid}.png"
    if not no_gen:
        src = generate(e, cfg, size, regen)
    if src is None or not src.exists():
        print(f"FAIL  {sid}: no generated image", file=sys.stderr)
        return False
    raw = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255.0
    if e.get("crop_x"):  # fractions of the width to keep (cuts off pipe elbows so the mirrored tile has no visible joint)
        x0, x1 = e["crop_x"]
        raw = raw[:, int(x0 * raw.shape[1]):int(x1 * raw.shape[1])]
    out = ROOT / e["out"]
    out.parent.mkdir(parents=True, exist_ok=True)
    glow_path = out.with_name(out.stem + "_glow.webp")

    px = (int(e["px"][0]), int(e["px"][1]))
    if e["kind"] == "strip":
        if raw[..., 3].min() > 0.98:
            print(f"FAIL  {sid}: the model returned no transparency; try another seed", file=sys.stderr)
            return False
        alpha = np.clip((raw[..., 3] - 0.04) / 0.92, 0.0, 1.0)
        rgba_full = np.dstack([raw[..., :3], alpha])
        if e.get("trim"):  # crop to the drawn part; "px" then gives the width and the height follows
            box = Image.fromarray((alpha * 255).astype(np.uint8)).point(lambda v: 255 if v > 10 else 0).getbbox()
            if box is not None:
                rgba_full = rgba_full[box[1]:box[3], box[0]:box[2]]
                px = (px[0], max(1, round(px[0] * rgba_full.shape[0] / rgba_full.shape[1])))
        big = Image.fromarray((rgba_full * 255 + 0.5).astype(np.uint8), "RGBA")
    else:
        big = Image.fromarray((raw[..., :3] * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    small = np.asarray(qwen_props.resize_rgba(big, px)).astype(np.float32) / 255.0
    rgb, alpha = small[..., :3], small[..., 3]
    graded = qm.grade(rgb, e.get("grade", {}))

    glow_img = None
    if e.get("glow"):
        glow_img = qm.glow_mask(np.dstack([qm.grade(rgb, e.get("glow_source_grade", {})), alpha]), e["glow"])
        if glow_img is not None:
            glow_img[..., :3] = qm.grade(glow_img[..., :3], e.get("glow_grade", {}))
    if e["kind"] == "strip" and e.get("rim"):
        r = e["rim"]
        mask = rim_light(alpha, r["color"], r.get("width", 2), r.get("strength", 0.6))
        graded = np.clip(graded + mask[..., None] * np.array(r["color"], dtype=np.float32), 0.0, 1.0)

    img = qm.to_image(np.dstack([graded, alpha])) if e["kind"] == "strip" else qm.to_image(graded)
    img.save(out, "WEBP", quality=int(e.get("quality", 90)), method=6)
    if glow_img is not None:
        qm.to_image(glow_img).save(glow_path, "WEBP", quality=90, method=6)
    elif glow_path.exists():
        glow_path.unlink()
    print(f"ok    {sid:22} {px[0]}x{px[1]}  {out.stat().st_size // 1024} KB  glow={'yes' if glow_img is not None else 'no'}")
    return True


def sheet(entries: list[dict], out: Path) -> None:
    tiles = []
    for e in entries:
        p = ROOT / e["out"]
        if not p.exists():
            continue
        im = Image.open(p).convert("RGBA")
        im = im.resize((640, max(1, int(640 * im.height / im.width))), Image.LANCZOS)
        bg = Image.new("RGBA", im.size, (40, 44, 70, 255))
        bg.alpha_composite(im)
        gp = p.with_name(p.stem + "_glow.webp")
        if gp.exists():
            g = Image.open(gp).convert("RGBA").resize(im.size, Image.LANCZOS)
            black = Image.new("RGBA", im.size, (0, 0, 0, 255))
            black.alpha_composite(g)
            both = Image.new("RGBA", (im.width * 2 + 6, im.height), (20, 20, 24, 255))
            both.paste(bg, (0, 0))
            both.paste(black, (im.width + 6, 0))
            tiles.append(both)
        else:
            tiles.append(bg)
    if not tiles:
        return
    w = max(t.width for t in tiles)
    sh = Image.new("RGB", (w, sum(t.height + 6 for t in tiles)), (16, 16, 20))
    y = 0
    for t in tiles:
        sh.paste(t.convert("RGB"), (0, y))
        y += t.height + 6
    sh.save(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--regen", action="store_true")
    ap.add_argument("--no-gen", action="store_true")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--pipeline", default="qwen_scenes", help="list name in assets_src/pipeline/ (without .json)")
    args = ap.parse_args()
    path = ROOT / "assets_src" / "pipeline" / f"{args.pipeline}.json"
    cfg = json.loads(path.read_text(encoding="utf-8"))
    if path != DEFAULT_PIPELINE:
        base = json.loads(DEFAULT_PIPELINE.read_text(encoding="utf-8"))
        for key in ("styles", "glow_presets", "defaults"):
            cfg[key] = {**base.get(key, {}), **cfg.get(key, {})}
    entries = [e for e in cfg["images"] if not args.only or e["id"] in args.only]
    failed = 0
    for e in entries:
        try:
            failed += 0 if process(e, cfg, args.regen, args.no_gen) else 1
        except ComfyFailure as ex:  # the server stays broken after every retry: stop instead of failing every remaining entry
            print(f"STOP  {e.get('id')}: {ex}", file=sys.stderr)
            return 2
        except Exception as ex:  # one bad entry must not block the rest
            failed += 1
            print(f"FAIL  {e.get('id')}: {ex}", file=sys.stderr)
    if args.sheet:
        sheet(entries, Path(args.sheet))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
