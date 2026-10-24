"""Which joint-audit failures are cracks a player can see: the samples that fail BOTH ways of drawing the joint.

    python tools/joint_audit_both.py <pair-only audit dir> <as-worn audit dir> [--top=N] [--sheet=<png>]

rig_joint_audit draws a joint two ways:
  --pair-only  only the two adjoining parts. Finds a gap between them, but also fails wherever the joint is covered by a third part the
               audit does not draw (a sleeve over an elbow, a wrist guard, a collar).
  (default)    the two parts plus everything else that is visible on their bones. What the player sees with all gear on, but an armour
               plate standing off a limb encloses a pocket of background that is the drawing's own shape, not a crack.
A sample that fails only one way is one of those two false alarms. A sample that fails both ways is a gap between the two parts that
nothing covers. The threshold of check_joint_frames.py is not changed; both directories must hold its report.json for the same characters.
What gear hides is still open when the gear is shot off: look at rig_preview --damage --bare for that.
"""
import collections
import json
import sys
from pathlib import Path


def real(report: dict) -> dict:
    out = {}
    for f in report["failures"]:
        if f["center_alpha"] >= 128 and not f["enclosed_pixels"] and not f["loose_pieces"]:
            continue  # outline notch or the band cutting a bent limb
        kind = ("loose" if f["loose_pieces"] else "") + ("encl" if f["enclosed_pixels"] else "") + ("center" if f["center_alpha"] < 128 else "")
        out[(f["char"], f["facing"], f["joint"], f["pose"], f["zoom"], f["frame"])] = kind
    return out


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top = int(next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("--top=")), 12))
    pair = json.loads((Path(args[0]) / "report.json").read_text(encoding="utf8"))
    worn = json.loads((Path(args[1]) / "report.json").read_text(encoding="utf8"))
    a, b = real(pair), real(worn)
    both = {k: b[k] for k in a.keys() & b.keys()}
    per, kinds = collections.Counter(k[0] for k in both), collections.Counter((k[0], k[2], v) for k, v in both.items())
    print(f"samples {worn['samples']}: pair-only {len(a)}, as-worn {len(b)}, both {len(both)}")
    print(" ", dict(per))
    for key, count in kinds.most_common(top):
        print(" ", key, count)
    sheet = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--sheet=")), "")
    if sheet:
        class_sheet(Path(args[0]), pair, Path(args[1]), worn, Path(sheet))


def kind_of(f: dict) -> str:
    if f["loose_pieces"]:
        return "loose"
    if f["center_alpha"] < 128:
        return "center"
    if f["enclosed_pixels"]:
        return "encl"
    return "split" if f["components"] > 1 else "notch"


def class_sheet(pair_dir: Path, pair: dict, worn_dir: Path, worn: dict, out: Path, half: int = 22, scale: int = 11, cols: int = 6) -> None:
    """--sheet=<png>: every kind of failure, outline notches included, with one enlarged crop each and the offending pixels outlined.
    A number says how often; whether it is a crack, a garment's own opening or a speck is decided by looking, so look at every tile."""
    import numpy as np
    from PIL import Image, ImageDraw
    from scipy import ndimage

    def index(report: dict) -> dict:
        return {(f["char"], f["facing"], f["joint"], f["pose"], f["zoom"], f["frame"]): f for f in report["failures"]}

    a, b = index(pair), index(worn)
    tiles = []
    for tag, keys, src, folder in (("both", a.keys() & b.keys(), b, worn_dir), ("pair-only", a.keys() - b.keys(), a, pair_dir), ("worn-only", b.keys() - a.keys(), b, worn_dir)):
        classes = collections.defaultdict(list)
        for k in keys:
            classes[(k[0], k[2], kind_of(src[k]))].append(k)
        for (char, joint, kind), ks in sorted(classes.items(), key=lambda t: (-len(t[1]), t[0])):
            ks.sort(key=lambda k: (-k[4], k[1] != 1, k[5], k[3]))  # the cutscene zoom, facing right, earliest frame
            f = src[ks[0]]
            x, y, w, h = f["rect"]
            crop = Image.open(folder / f["file"]).convert("RGBA").crop((x, y, x + w, y + h))
            solid = np.array(crop)[:, :, 3] >= 128
            radius = f["radius"]
            if radius <= 0 or radius >= min(w, h) // 2:
                raise ValueError(f"joint band clipped or invalid: {f}")
            bx, by = w // 2 - radius, h // 2 - radius
            band = solid[by:by + 2 * radius, bx:bx + 2 * radius]
            # Match the original checker's domain; other pockets and pieces in
            # the 128px cell are context, not evidence for this failed sample.
            if kind in ("loose", "split"):
                labels, count = ndimage.label(band, np.ones((3, 3)))
                sizes = ndimage.sum(band, labels, range(1, count + 1))
                band_bad = band & (labels != 1 + int(np.argmax(sizes)))
            elif kind == "center":
                band_bad = np.zeros_like(band)
                band_bad[radius, radius] = True
            else:
                band_bad = ndimage.binary_fill_holes(band, structure=np.ones((3, 3)) if kind == "encl" else None) & ~band
            bad = np.zeros_like(solid)
            bad[by:by + 2 * radius, bx:bx + 2 * radius] = band_bad
            ys, xs = np.nonzero(bad)
            if not len(ys):
                raise ValueError(f"reported joint failure has no matching pixels in its checked band: {f}")
            focus = int(np.argmin((xs - w // 2) ** 2 + (ys - h // 2) ** 2))
            cx, cy = int(xs[focus]), int(ys[focus])
            x0, y0 = min(max(0, cx - half), w - 2 * half), min(max(0, cy - half), h - 2 * half)
            backdrop = Image.new("RGBA", crop.size, (255, 0, 255, 255))
            backdrop.alpha_composite(crop)
            tile = backdrop.crop((x0, y0, x0 + 2 * half, y0 + 2 * half)).resize((2 * half * scale,) * 2, Image.NEAREST).convert("RGB")
            draw = ImageDraw.Draw(tile)
            visible_bad = [(yy, xx) for yy, xx in zip(ys, xs)
                           if x0 <= xx < x0 + 2 * half and y0 <= yy < y0 + 2 * half]
            visible_bad.sort(key=lambda point: ((point[1] - cx) ** 2 + (point[0] - cy) ** 2, point[0], point[1]))
            for yy, xx in visible_bad[:40]:
                draw.rectangle([(xx - x0) * scale, (yy - y0) * scale, (xx - x0 + 1) * scale - 1, (yy - y0 + 1) * scale - 1], outline=(0, 255, 0))
            label = f"#{len(tiles) + 1} {tag} {char} {joint} {kind} x{len(ks)} {f['pose']} z{f['zoom']} f{f['frame']}"
            draw.rectangle([0, 0, tile.width, 13], fill=(0, 0, 0))
            draw.text((2, 1), label, fill=(255, 255, 0))
            print(" ", label)
            tiles.append(tile)
    if not tiles:
        print("  no failures: no sheet written")
        return
    side = 2 * half * scale
    canvas = Image.new("RGB", (side * cols, side * ((len(tiles) + cols - 1) // cols)), (30, 30, 30))
    for i, tile in enumerate(tiles):
        canvas.paste(tile, ((i % cols) * side, (i // cols) * side))
    canvas.save(out)
    print(f"  {len(tiles)} kinds -> {out}")


if __name__ == "__main__":
    main()
