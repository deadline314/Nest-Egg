"""Cut an AI full-body illustration into rig part textures (NE-17 "做法 C" step 4-5).

Input : the reference folder written by rig_reference.tscn (body.json / armor.json) and the generated
        illustrations (one per pass: body, armor), both drawn over the reference pose.
Output: <out>/<part>.png and <part>_glow.png. Each canvas is the original part size times --upscale
        (pivot positions scale with it; set texture_scale in character.json to 0.25 / upscale).

How a part is cut:
  * Every illustration pixel belongs to one part: the topmost stand-in part whose (re-aligned) region covers it,
    or the nearest stand-in region for pixels the stand-in did not cover (long ponytail, coat tail...).
  * The part's silhouette is therefore the illustration's own outline, not the stand-in polygon.
  * Areas of a part that other parts hide in the reference pose are filled from the part's own visible colours.

Usage:
    python cut_parts.py --char art/characters/rin --orig <stand-in parts dir> --ref <ref_dir> \
        --body body_gen.png --armor armor_gen.png --out <dir> [--upscale 2]
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from scipy import ndimage

# Which glow colour each part may emit: c = cyan, m = magenta/pink. Parts not listed get no glow layer.
GLOW = {"head": "c", "torso": "c", "arm_upper": "c", "arm_lower": "c", "armor_chest": "c", "coat_2": "c", "foot": "cm"}
SEARCH = 6  # downsample factor for the alignment searches
SEAM = 3  # px of overlap added around each part so rotated joints show no cracks
## Parts that can swing in front of another part and must be cut out of it: {hidden part: [texture that covers it]}.
ARM = ("arm_upper", "arm_lower", "hand", "armor_forearm", "armor_shoulder")
LEG = ("leg_upper", "leg_lower", "foot", "armor_knee")
OCCLUDERS = {"torso": ARM, "pelvis": ARM, "coat_1": ARM + LEG, "coat_2": ARM + LEG, "armor_chest": ARM,
             "leg_upper": ARM, "leg_lower": ARM, "head": (), "hair_back_1": ARM, "hair_back_2": ARM}


def foreground(img: np.ndarray) -> np.ndarray:
    """Pixels not connected to the flat background colour at the image border (1px eroded to drop the grey fringe)."""
    border = np.concatenate([img[0], img[-1], img[:, 0], img[:, -1]])
    bg = np.median(border, axis=0)
    near = (np.abs(img.astype(np.int16) - bg).max(axis=2) < 16).astype(np.uint8)
    _, labels = cv2.connectedComponents(near, connectivity=4)
    edge = (set(labels[0]) | set(labels[-1]) | set(labels[:, 0]) | set(labels[:, -1])) - {0}
    fg = ~(np.isin(labels, list(edge)) & (near > 0))
    return cv2.erode(fg.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0


def small(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    return cv2.resize(mask.astype(np.uint8), (w // SEARCH, h // SEARCH), interpolation=cv2.INTER_AREA) > 0


def align_global(fg: np.ndarray, ref_alpha: np.ndarray) -> np.ndarray:
    """Shift+scale of the illustration that maximises silhouette overlap with the reference silhouette."""
    h, w = fg.shape
    ref, src = small(ref_alpha > 40), small(fg)
    sh, sw = ref.shape
    best, best_m = -1.0, np.float32([[1, 0, 0], [0, 1, 0]])
    src_u8 = src.astype(np.uint8)
    for sx in np.arange(0.94, 1.121, 0.02):
        for sy in np.arange(0.94, 1.121, 0.02):
            for dy in range(-12, 13, 2):
                for dx in range(-12, 13, 2):
                    m = np.float32([[sx, 0, dx + (1 - sx) * sw / 2], [0, sy, dy + (1 - sy) * sh / 2]])
                    moved = cv2.warpAffine(src_u8, m, (sw, sh)) > 0
                    iou = (moved & ref).sum() / max((moved | ref).sum(), 1)
                    if iou > best:
                        best, best_m = iou, m
    best_m[:, 2] *= SEARCH
    print(f"  global align iou={best:.3f} scale=({best_m[0, 0]:.2f},{best_m[1, 1]:.2f}) shift=({best_m[0, 2]:.0f},{best_m[1, 2]:.0f})")
    return best_m


def refine_shift(region: np.ndarray, fg: np.ndarray, radius: int = 5) -> tuple[int, int]:
    """Per-part translation (in illustration px) that best lays the stand-in region over the illustration."""
    r, f = small(region), small(fg)
    if not r.any():
        return 0, 0
    best, best_d = -1e9, (0, 0)
    ys, xs = np.nonzero(r)
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            yy, xx = ys + dy, xs + dx
            ok = (yy >= 0) & (yy < r.shape[0]) & (xx >= 0) & (xx < r.shape[1])
            inside = f[yy[ok], xx[ok]].sum()
            score = inside - 0.7 * (len(ys) - inside) - 0.6 * (abs(dx) + abs(dy))
            if score > best:
                best, best_d = score, (dx, dy)
    return best_d[0] * SEARCH, best_d[1] * SEARCH


def nearest_fill(img: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """Replace invalid pixels by the colour of the nearest valid pixel."""
    if valid.all() or not valid.any():
        return img
    idx = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    return img[idx[0], idx[1]]


def affine(xform: list, scale: float, shift: tuple[int, int]) -> np.ndarray:
    """Matrix from a canvas at `scale` px per texture pixel to illustration px (xform = rig_reference transform)."""
    xx, xy, yx, yy, ox, oy = xform
    k = 1.0 / scale
    return np.float32([[xx * k, yx * k, ox + shift[0]], [xy * k, yy * k, oy + shift[1]]])


def cut_pass(ref: dict, gen: np.ndarray, orig_dir: Path, wanted: set, upscale: int) -> dict:
    """Return {texture: (RGB, alpha)} for the wanted textures of one pass, at original size * upscale."""
    validate_reference(ref)
    require_single_instance(ref, wanted)
    h, w = gen.shape[:2]
    px = ref["zoom"] * ref.get("body_scale", 1.0) * ref.get("texture_scale", 0.25)
    fg = foreground(gen)
    parts = sorted(ref["parts"], key=lambda p: (p["z"], p["tree_index"]), reverse=True)  # topmost first
    for p in parts:
        tw, th = p["tex_size"]
        orig = cv2.imread(str(orig_dir / (p["texture"] + ".png")), cv2.IMREAD_UNCHANGED)[:, :, 3]
        if p.get("kind") == "mesh":
            p["region"] = mesh_warp(orig, p, (w, h)) > 100
        else:
            a = cv2.resize(orig, (round(tw * px), round(th * px)), interpolation=cv2.INTER_CUBIC)
            p["region"] = cv2.warpAffine(a, affine(p["xform"], px, (0, 0)), (w, h), flags=cv2.INTER_LINEAR) > 100  # canvas -> illustration
        p["shift"] = refine_shift(p["region"], fg)
        if p["shift"] != (0, 0):
            p["region"] = cv2.warpAffine(p["region"].astype(np.uint8), np.float32([[1, 0, p["shift"][0]], [0, 1, p["shift"][1]]]), (w, h)) > 0
    # pixels no stand-in region covers (long ponytail, coat tail...) go to the nearest region within reach
    covered = np.zeros((h, w), bool)
    for p in parts:
        covered |= p["region"]
    leftover = fg & ~covered
    extra = {}
    if leftover.any():
        dist = np.stack([cv2.distanceTransform((~p["region"]).astype(np.uint8), cv2.DIST_L2, 3) for p in parts])
        near = dist.argmin(axis=0)
        leftover &= dist.min(axis=0) <= px * 10
        extra = {i: leftover & (near == i) for i in range(len(parts))}
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * SEAM + 1, 2 * SEAM + 1))
    result = {}
    for i, p in enumerate(parts):
        if p["texture"] not in wanted:
            continue
        # Overlapping parts (head/bangs, thigh/shin) each keep their full content: at rest they paint the same pixels.
        # Only a limb that swings in front of a part (arm over torso, leg over coat) is cut out of it and re-painted.
        occluders = np.zeros((h, w), bool)
        for q in parts:
            if q["texture"] in OCCLUDERS.get(p["texture"], ()):
                occluders |= q["region"]
        occluders = cv2.dilate(occluders.astype(np.uint8), kernel) > 0
        own = (p["region"] & fg) | extra.get(i, False)
        hidden = own & occluders
        visible = own & ~occluders
        if visible.sum() < 16:
            print(f"  WARN {p['name']}: almost no illustration pixels ({int(visible.sum())})")
        ys, xs = np.nonzero(own)
        if len(ys) == 0:
            continue
        pad = 24
        y0, y1, x0, x1 = max(ys.min() - pad, 0), min(ys.max() + pad, h), max(xs.min() - pad, 0), min(xs.max() + pad, w)
        sl = (slice(y0, y1), slice(x0, x1))
        vis, hid = visible[sl], hidden[sl]
        full = (cv2.dilate(own[sl].astype(np.uint8), kernel) > 0) & fg[sl] | own[sl]
        color = nearest_fill(gen[sl], vis) if vis.any() else np.full_like(gen[sl], 128)
        if hid.any() and vis.any():
            color = cv2.inpaint(color, cv2.dilate(hid.astype(np.uint8), kernel), 6, cv2.INPAINT_TELEA)
        canvas_full = np.zeros((h, w, 3), np.uint8)
        canvas_full[sl] = color
        mask_full = np.zeros((h, w), np.uint8)
        mask_full[sl] = full.astype(np.uint8) * 255
        tw, th = p["tex_size"]
        size = (tw * upscale, th * upscale)
        if p.get("kind") == "mesh":
            col = mesh_warp(canvas_full, p, size, inverse=True, scale=upscale, shift=p["shift"])
            msk = mesh_warp(mask_full, p, size, inverse=True, scale=upscale, shift=p["shift"])
        else:
            m = affine(p["xform"], upscale, p["shift"])
            col = cv2.warpAffine(canvas_full, m, size, flags=cv2.INTER_LANCZOS4 | cv2.WARP_INVERSE_MAP, borderMode=cv2.BORDER_REPLICATE)
            msk = cv2.warpAffine(mask_full, m, size, flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP)
        result[p["texture"]] = (col, msk)
    return result


def validate_reference(ref: dict) -> None:
    for part in ref["parts"]:
        size = np.asarray(part.get("tex_size", []))
        if size.shape != (2,) or not np.issubdtype(size.dtype, np.integer) or (size <= 0).any():
            raise ValueError(f"{part['name']}: invalid reference texture size")
        if part.get("kind") == "mesh":
            vertices = np.asarray(part["vertices"], dtype=np.float64)
            uv = np.asarray(part["uv"], dtype=np.float64)
            indices = np.asarray(part["triangles"])
            valid = (vertices.ndim == 2 and vertices.shape[1] == 2 and uv.shape == vertices.shape
                     and np.isfinite(vertices).all() and np.isfinite(uv).all()
                     and indices.ndim == 2 and indices.shape[1] == 3 and indices.size > 0
                     and np.issubdtype(indices.dtype, np.integer) and indices.min() >= 0
                     and indices.max() < len(vertices))
            if not valid:
                raise ValueError(f"{part['name']}: invalid posed mesh vertices, UV or triangles")
            for points in (vertices, uv):
                t = points[indices]
                a, b = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
                if (np.abs(a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0]) < 1e-8).any():
                    raise ValueError(f"{part['name']}: singular posed mesh triangle")
        else:
            xf = np.asarray(part.get("xform", []), dtype=np.float64)
            if (part.get("kind", "sprite") != "sprite" or xf.shape != (6,) or not np.isfinite(xf).all()
                    or abs(xf[0] * xf[3] - xf[1] * xf[2]) < 1e-8):
                raise ValueError(f"{part['name']}: invalid rigid reference transform")


def require_single_instance(ref: dict, wanted: set) -> None:
    seen = {}
    for part in ref["parts"]:
        texture = part["texture"]
        if texture not in wanted:
            continue
        if texture in seen:
            raise ValueError(f"{texture}: {seen[texture]} and {part['name']} share one output; "
                             "isolate each posed side and publish distinct attachments")
        seen[texture] = part["name"]


def mesh_warp(image: np.ndarray, part: dict, size: tuple[int, int], inverse=False, scale=1.0, shift=(0, 0)) -> np.ndarray:
    """Sample the exported triangles rather than pretending a bent limb is affine."""
    validate_reference({"parts": [part]})
    uv = np.asarray(part["uv"], dtype=np.float64) * scale
    vertices = np.asarray(part["vertices"], dtype=np.float64) + shift
    src, dst = (vertices, uv) if inverse else (uv, vertices)
    w, h = size
    map_x, map_y = np.full((h, w), -1, np.float32), np.full((h, w), -1, np.float32)
    for indices in part["triangles"]:
        source, triangle = src[indices], dst[indices]
        lo = np.maximum(np.ceil(triangle.min(axis=0)).astype(int), 0)
        hi = np.minimum(np.floor(triangle.max(axis=0)).astype(int) + 1, [w, h])
        if (hi <= lo).any():
            continue
        yy, xx = np.mgrid[lo[1]:hi[1], lo[0]:hi[0]]
        v = np.stack((xx - triangle[0, 0], yy - triangle[0, 1]), axis=-1)
        basis = np.stack((triangle[1] - triangle[0], triangle[2] - triangle[0]), axis=1)
        weights = v @ np.linalg.inv(basis).T
        inside = (weights.min(axis=-1) >= -1e-7) & (weights.sum(axis=-1) <= 1 + 1e-7)
        sampled = source[0] + weights @ np.stack((source[1] - source[0], source[2] - source[0]))
        region = np.s_[lo[1]:hi[1], lo[0]:hi[0]]
        map_x[region][inside], map_y[region][inside] = sampled[inside, 0], sampled[inside, 1]
    return cv2.remap(image, map_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)


def glow_layer(rgb: np.ndarray, alpha: np.ndarray, kinds: str, sat_min: int = 140, val_min: int = 190) -> np.ndarray | None:
    """Pixels of the neon colours in `kinds` (c m p r o y g) that are saturated and bright enough (spec "glow_threshold" lowers the
    limits for a character whose lit details are not neon, e.g. the golden piping of a coat). None when nothing qualifies."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    hue, sat, val = hsv[:, :, 0].astype(int) * 2, hsv[:, :, 1], hsv[:, :, 2]
    bright = (sat > sat_min) & (val > val_min)
    mask = np.zeros(alpha.shape, bool)
    if "c" in kinds:
        mask |= bright & (hue >= 165) & (hue <= 205)
    if "m" in kinds:
        mask |= bright & (hue >= 295) & (hue <= 345)
    if "p" in kinds:  # purple / violet
        mask |= bright & (hue >= 250) & (hue < 295)
    if "r" in kinds:  # red
        mask |= bright & ((hue >= 345) | (hue <= 12))
    if "o" in kinds:  # orange
        mask |= bright & (hue > 12) & (hue <= 40)
    if "y" in kinds:  # yellow
        mask |= bright & (hue > 40) & (hue <= 70)
    if "g" in kinds:  # green
        mask |= bright & (hue >= 90) & (hue <= 160)
    mask &= alpha > 128
    if not mask.any():
        return None
    out = np.zeros((*alpha.shape, 4), np.uint8)
    out[mask, :3] = rgb[mask]
    out[mask, 3] = 255
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--char", required=True, help="character folder, e.g. art/characters/rin")
    ap.add_argument("--orig", required=True, help="folder with the ORIGINAL stand-in part PNGs (canvas size reference)")
    ap.add_argument("--ref", required=True, help="folder written by rig_reference.tscn")
    ap.add_argument("--body", required=True)
    ap.add_argument("--armor", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--upscale", type=int, default=2, help="output texels per original texture pixel")
    args = ap.parse_args()
    out = Path(args.out)
    references = {name: json.loads((Path(args.ref) / f"{name}.json").read_text(encoding="utf-8"))
                  for name in ("body", "armor")}
    for ref in references.values():
        validate_reference(ref)
    cfg = json.loads((Path(args.char) / "character.json").read_text(encoding="utf8"))
    tex_of = {p["name"]: p["texture"] for p in cfg["parts"]}
    for name, ref in references.items():
        for p in ref["parts"]:
            p["texture"] = tex_of[p["name"]]
        wanted = {t for t in tex_of.values() if t.startswith("armor_") == (name == "armor")}
        require_single_instance(ref, wanted)
    out.mkdir(parents=True, exist_ok=True)
    orig_dir = Path(args.orig)
    for name, gen_path in (("body", args.body), ("armor", args.armor)):
        ref = references[name]
        ref_alpha = cv2.imread(str(Path(args.ref) / f"{name}.png"), cv2.IMREAD_UNCHANGED)[:, :, 3]
        w, h = ref["size"]
        gen = cv2.cvtColor(cv2.imread(gen_path), cv2.COLOR_BGR2RGB)
        gen = cv2.resize(gen, (w, h), interpolation=cv2.INTER_AREA)
        print(f"[{name}]")
        m = align_global(foreground(gen), ref_alpha)
        gen = cv2.warpAffine(gen, m, (w, h), flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE)
        # the armor illustration only supplies armor plates; the body illustration supplies everything else
        wanted = {t for t in tex_of.values() if t.startswith("armor_") == (name == "armor")}
        for tex, (rgb, alpha) in cut_pass(ref, gen, orig_dir, wanted, args.upscale).items():
            cv2.imwrite(str(out / f"{tex}.png"), np.dstack([cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), alpha]))
            if tex in GLOW and (orig_dir / f"{tex}_glow.png").exists():
                g = glow_layer(rgb, alpha, GLOW[tex])
                g = np.zeros((*alpha.shape, 4), np.uint8) if g is None else g
                cv2.imwrite(str(out / f"{tex}_glow.png"), cv2.cvtColor(g, cv2.COLOR_RGBA2BGRA))
            print(f"  {tex}")


if __name__ == "__main__":
    main()
