"""Put a character's refined part layers back together where they came from and compare with the illustration (no model, no GPU).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/check_reassembly.py --spec tools/comfyui/specs/rin_field_side.json --work art_src/characters/rin_field [--out DIR] [--allow far.json]

The part layers (<work>/07_refined, same canvas as base_rgba.png) are stacked in the draw order of the spec (highest z of each part's
uses on top; torn `damage_of` layers and parts without uses are left out). Reported:
  holes    picture pixels no part covers, as connected pieces (bbox, size). A far-side limb the rig draws from the near one is expected
           here: list such pieces in --allow as {"holes": [[x0, y0, x1, y1], ...]} once they have been looked at.
  changed  covered pixels whose colour differs from the picture by more than --tolerance (defringe, inpainted gaps, erased regions).
Exit code 1 when a hole outside the allowed boxes is larger than --max-hole px. Writes reassembled.png and holes.png into --out.
This is the "in place" gate only: it says nothing about joints that turn, lighting or anatomy.
"""
import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def stack(spec: dict, work: Path) -> np.ndarray:
    """Premultiplied 'over' of the visible parts, back to front; returns float RGBA in 0..1."""
    order = []
    for name, part in spec["parts"].items():
        uses = [u for u in part.get("uses", []) if not u.get("under")]
        if "damage_of" in part or not uses:
            continue
        order.append((max(u["z"] for u in uses), name))
    out = None
    for _, name in sorted(order, key=lambda item: item[0]):
        path = work / "07_refined" / f"{name}.png"
        if not path.exists():
            raise SystemExit(f"[check_reassembly] {path} is missing - run the refine step first")
        layer = np.asarray(Image.open(path).convert("RGBA"), np.float32) / 255.0
        if out is None:
            out = np.zeros_like(layer)
        a = layer[:, :, 3:4]
        out[:, :, :3] = layer[:, :, :3] * a + out[:, :, :3] * (1 - a)
        out[:, :, 3:4] = a + out[:, :, 3:4] * (1 - a)
    if out is None:
        raise SystemExit("[check_reassembly] the spec has no visible parts")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--out")
    ap.add_argument("--allow", help="JSON file: {\"holes\": [[x0, y0, x1, y1], ...]} boxes of reviewed, expected holes")
    ap.add_argument("--max-hole", type=int, default=0, help="largest hole (px) that still passes outside the allowed boxes")
    ap.add_argument("--tolerance", type=int, default=24, help="colour difference (0-255, max over RGB) that counts as changed")
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    work = Path(args.work)
    base = np.asarray(Image.open(work / "base_rgba.png").convert("RGBA"), np.float32) / 255.0
    got = stack(spec, work)
    if got.shape != base.shape:
        raise SystemExit(f"[check_reassembly] part layers are {got.shape[1]}x{got.shape[0]}, the picture is {base.shape[1]}x{base.shape[0]}")
    solid = base[:, :, 3] > 0.5
    hole = solid & (got[:, :, 3] <= 0.5)
    allowed = np.zeros_like(hole)
    for x0, y0, x1, y1 in (json.loads(Path(args.allow).read_text(encoding="utf8"))["holes"] if args.allow else []):
        allowed[y0:y1, x0:x1] = True
    n, labels, stats, _ = cv2.connectedComponentsWithStats(hole.astype(np.uint8), connectivity=8)
    failed = 0
    pieces = sorted(range(1, n), key=lambda i: -stats[i, cv2.CC_STAT_AREA])
    for i in pieces:
        x, y, w, h, area = (int(v) for v in stats[i])
        ok = bool(allowed[labels == i].all())
        if not ok and area > args.max_hole:
            failed += 1
        if area >= 20 or not ok:
            print(f"  hole {area:6d} px at [{x}, {y}, {x + w}, {y + h}]{' (allowed)' if ok else ''}")
    covered = solid & ~hole
    diff = (np.abs(got[:, :, :3] - base[:, :, :3]).max(2) * 255) > args.tolerance
    changed = covered & diff
    print(f"check_reassembly {spec['id']}: {int(solid.sum())} picture px, {int(hole.sum())} uncovered in {n - 1} piece(s) "
          f"({failed} not allowed), {int(changed.sum())} covered px changed by more than {args.tolerance}")
    if args.out:
        out = Path(args.out)
        out.mkdir(parents=True, exist_ok=True)
        (out / ".gdignore").touch()
        Image.fromarray((got * 255).round().astype(np.uint8)).save(out / "reassembled.png")
        view = (base[:, :, :3] * 0.35 * 255).astype(np.uint8)
        view[~solid] = (40, 40, 48)
        view[changed] = (255, 200, 0)
        view[hole] = (255, 0, 255)
        Image.fromarray(view).save(out / "holes.png")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
