"""Clean up the full-canvas part layers from make_parts.py before they are cut into game textures (NE-68).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/refine_parts.py --spec tools/comfyui/specs/rin_side.json --work art_src/characters/rin2

Inputs : <work>/06_parts/<part>.png, <work>/05_groups/<group>.png, <work>/base_rgba.png, spec["refine"]
Outputs: <work>/07_refined/<part>.png   same size and pixel coordinates as the input (cut_layers.py reads this folder when it exists)

spec["refine"] (every key is optional):
  far_side   {"parts": [...], "min_area": N, "y_min": Y}        remove the far-side leg / boot that Qwen drew as a flat teal silhouette behind the near leg
  erase      [{"part": p, "poly": [[x, y], ...]}]    clear a polygon (pixel coordinates of base_rgba.png)
  repaint    [{"parts": [...], "group": g, "y": [lo, hi]}] throw away what Qwen painted into the hidden gap of group g inside the y range and
                                                      refill it with a colour ramp from the visible pixels above and below (removes the seams drawn on the thigh)
  close_fill {"parts": [...], "radius": N}           close holes cut into a part by something in front of it (the holster behind the hand)
  fill_holes {"parts": [...], "max_area": N}         paint enclosed transparent holes smaller than N px (default 200) from the colours around them:
                                                      a sliver between two outlines would show the background as a bright dot (check_parts.py lists them)
  magenta_specks {"parts": [...], "max_area": N}     delete tiny magenta fringe flecks on the listed parts
  white_specks {"parts": [...], "max_area": N}       same for tiny near-white flecks (only use on dark parts)
  smooth_alpha {"parts": [...], "sigma": S}          round off the stair-stepped outline of the listed parts
  defringe   {"width": N}                            recolour the outer N px of every part from its inside (kills the white Qwen halo)
  speckle    N                                       delete detached islands smaller than N px
"""
import argparse
import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage


def ell(r: int) -> np.ndarray:
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def components(mask: np.ndarray, min_area: int) -> np.ndarray:
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    keep = [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] >= min_area]
    return np.isin(lab, keep)


def teal_mask(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Dark blue-green pixels: the far leg, the far boot and the shaded far hip."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    hue, v = hsv[:, :, 0].astype(int) * 2, hsv[:, :, 2]
    r, b = rgb[:, :, 0].astype(int), rgb[:, :, 2].astype(int)
    return (alpha > 127) & (b - r > 18) & (v < 150) & (hue > 165) & (hue < 245)


def defringe(layer: np.ndarray, width: int) -> np.ndarray:
    """Recolour the pale halo Qwen leaves on the outline: semi-transparent edge pixels, and (width > 1) opaque rim pixels that are much
    brighter than the pixels inside, take the colour of the nearest solid inner pixel. Alpha is untouched."""
    a = layer[:, :, 3]
    core = a >= 250
    if not core.any():
        return layer
    edge = (a > 0) & ~core
    if width > 1:
        solid = a > 127
        rim = solid & ~(cv2.erode(solid.astype(np.uint8), ell(width - 1)) > 0)
        lum = layer[:, :, :3].astype(np.float32).mean(2)
        inside = (core & ~rim).astype(np.float32)
        inner_lum = cv2.blur(lum * inside, (7, 7)) / np.maximum(cv2.blur(inside, (7, 7)), 1e-3)
        edge |= rim & (lum > inner_lum + 60)
    keep = core & ~edge
    idx = cv2.distanceTransformWithLabels(np.where(keep, 0, 1).astype(np.uint8), cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)[1]
    ys, xs = np.nonzero(keep)
    lut = np.zeros(idx.max() + 1, np.int64)
    lut[idx[ys, xs]] = ys * layer.shape[1] + xs
    out = layer.copy()
    out[:, :, :3][edge] = layer[:, :, :3].reshape(-1, 3)[lut[idx][edge]]
    return out


def vertical_fill(L: np.ndarray, region: np.ndarray, max_run: int, blur: float) -> int:
    """Replace every vertical run of `region` pixels by a straight colour ramp between the solid pixel above it and the one below it.
    Stockings shade across the leg and hardly at all along it, so this keeps the sheen and the shadow side and drops the seams Qwen painted.
    Runs that lack a solid neighbour on either side (the outline of the hip) keep what Qwen painted."""
    H, W = region.shape
    rgb = L[:, :, :3].astype(np.float32)
    solid = (L[:, :, 3] > 127) & ~region
    out = rgb.copy()
    done = np.zeros_like(region)
    for x in range(W):
        col = region[:, x]
        if not col.any():
            continue
        ys = np.nonzero(col)[0]
        start = 0
        for i in range(1, len(ys) + 1):
            if i == len(ys) or ys[i] != ys[i - 1] + 1:
                y0, y1 = ys[start], ys[i - 1]
                start = i
                if y0 == 0 or y1 >= H - 1 or y1 - y0 + 1 > max_run or not (solid[y0 - 1, x] and solid[y1 + 1, x]):
                    continue
                top, bot = rgb[max(y0 - 3, 0):y0, x].mean(0), rgb[y1 + 1:y1 + 4, x].mean(0)
                t = (np.arange(y0, y1 + 1) - y0 + 1.0) / (y1 - y0 + 2.0)
                out[y0:y1 + 1, x] = top[None] * (1 - t[:, None]) + bot[None] * t[:, None]
                done[y0:y1 + 1, x] = True
    if blur > 0:  # the columns are filled independently: even them out sideways, only inside the filled area
        soft = cv2.GaussianBlur(out, (0, 0), blur)
        out = np.where(done[:, :, None], soft, out)
    L[:, :, :3] = np.clip(out, 0, 255).astype(np.uint8)
    return int(done.sum())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    cfg = spec.get("refine", {})
    work = Path(args.work)
    src_dir, out_dir = work / "06_parts", work / "07_refined"
    out_dir.mkdir(exist_ok=True)
    base = np.array(Image.open(work / "base_rgba.png").convert("RGBA"))
    H, W = base.shape[:2]
    yy = np.mgrid[0:H, 0:W][0]

    layers = {n: np.array(Image.open(src_dir / f"{n}.png").convert("RGBA")) for n, p in spec["parts"].items() if "damage_of" not in p}

    fs = cfg.get("far_side")
    if fs:
        for n in fs["parts"]:
            L = layers[n]
            teal = teal_mask(L[:, :, :3], L[:, :, 3]) & (yy >= fs.get("y_min", 0))
            far = components(cv2.morphologyEx(teal.astype(np.uint8), cv2.MORPH_CLOSE, ell(2)) > 0, fs.get("min_area", 300))
            far = cv2.dilate(far.astype(np.uint8), ell(fs.get("grow", 1))) > 0
            L[:, :, 3][far] = 0
            print(f"  far_side {n}: removed {int(far.sum())} px")

    for e in cfg.get("erase", []):
        m = np.zeros((H, W), np.uint8)
        cv2.fillPoly(m, [np.array(e["poly"], np.int32)], 1)
        layers[e["part"]][:, :, 3][m > 0] = 0
        print(f"  erase {e['part']}: {int(m.sum())} px")

    ec = cfg.get("magenta_specks")
    if ec:  # tiny magenta flecks (hair / jacket fringe that Qwen dragged onto neighbouring parts)
        for n in ec["parts"]:
            L = layers[n]
            hsv = cv2.cvtColor(L[:, :, :3], cv2.COLOR_RGB2HSV)
            hue = hsv[:, :, 0].astype(int) * 2
            mag = (L[:, :, 3] > 0) & (hue >= 270) & (hue <= 345) & (hsv[:, :, 1] > 150) & (hsv[:, :, 2] > 40)
            small = mag & ~components(mag, ec.get("max_area", 80))
            small = cv2.dilate(small.astype(np.uint8), ell(1)) > 0
            L[:, :, 3][small] = 0
            print(f"  magenta_specks {n}: removed {int(small.sum())} px")

    ws = cfg.get("white_specks")
    if ws:  # tiny near-white flecks (the pale Qwen halo that survived on a dark part)
        for n in ws["parts"]:
            L = layers[n]
            hsv = cv2.cvtColor(L[:, :, :3], cv2.COLOR_RGB2HSV)
            white = (L[:, :, 3] > 0) & (hsv[:, :, 2] > 170) & (hsv[:, :, 1] < 70)
            small = cv2.dilate((white & ~components(white, ws.get("max_area", 60))).astype(np.uint8), ell(1)) > 0
            L[:, :, 3][small] = 0
            print(f"  white_specks {n}: removed {int(small.sum())} px")

    for r in cfg.get("repaint", []):
        grp = np.array(Image.open(work / "05_groups" / f"{r['group']}.png").convert("RGBA"))
        gap = (grp[:, :, 3] > 127) & (np.abs(grp[:, :, :3].astype(int) - base[:, :, :3].astype(int)).max(2) > 2)
        gap &= (yy >= r["y"][0]) & (yy < r["y"][1])
        gap = cv2.dilate(gap.astype(np.uint8), ell(r.get("grow", 3))) > 0
        for n in r["parts"]:
            L = layers[n]
            region = gap & (L[:, :, 3] > 127)
            if region.any():
                print(f"  repaint {n}: {int(vertical_fill(L, region, r.get('max_run', 160), r.get('blur', 2.0)))} px")

    cf = cfg.get("close_fill")
    if cf:  # a part cut by something in front of it (the holster behind the hand): close the hole and paint it from the part's own colours
        for n in cf["parts"]:
            L = layers[n]
            solid = (L[:, :, 3] > 127).astype(np.uint8)
            closed = cv2.morphologyEx(solid, cv2.MORPH_CLOSE, ell(cf.get("radius", 10))) > 0
            new = closed & (solid == 0)
            L[:, :, :3] = cv2.inpaint(L[:, :, :3], new.astype(np.uint8) * 255, 5, cv2.INPAINT_TELEA)
            L[:, :, 3][new] = 255
            print(f"  close_fill {n}: +{int(new.sum())} px")

    sm = cfg.get("smooth_alpha")
    for n, L in layers.items():
        if sm and n in sm["parts"]:  # soften stair-stepped outlines: blur the mask, then re-sharpen it around 50 %
            blur = cv2.GaussianBlur(L[:, :, 3].astype(np.float32), (0, 0), sm.get("sigma", 1.0))
            L[:, :, 3] = np.clip((blur - 127.5) * sm.get("gain", 3.0) + 127.5, 0, 255).astype(np.uint8)
        L[:, :, 3][L[:, :, 3] < cfg.get("alpha_floor", 40)] = 0
        if "speckle" in cfg:
            big = components(L[:, :, 3] > 0, cfg["speckle"])
            L[:, :, 3][~big] = 0
        fh = cfg.get("fill_holes")
        if fh and n in fh["parts"]:  # last, after the outline smoothing, which can itself open a hair-thin crack into a hole
            solid = L[:, :, 3] > 127
            holes, count = ndimage.label(ndimage.binary_fill_holes(solid) & ~solid)
            small = np.isin(holes, [i for i in range(1, count + 1) if (holes == i).sum() < fh.get("max_area", 200)])
            if small.any():
                small = cv2.dilate(small.astype(np.uint8), ell(1)) > 0
                L[:, :, :3] = cv2.inpaint(L[:, :, :3], small.astype(np.uint8) * 255, 5, cv2.INPAINT_TELEA)
                L[:, :, 3][small] = 255
                print(f"  fill_holes {n}: +{int(small.sum())} px")
        if "defringe" in cfg:
            layers[n] = defringe(L, cfg["defringe"]["width"])
        Image.fromarray(layers[n]).save(out_dir / f"{n}.png")
    shutil.copy(src_dir / "ownership.png", out_dir / "ownership.png") if (src_dir / "ownership.png").exists() else None
    print(f"refined {len(layers)} parts -> {out_dir}")


if __name__ == "__main__":
    main()
