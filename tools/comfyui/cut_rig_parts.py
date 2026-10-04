"""Cut one full-body illustration into rig parts for ANY body proportion, and write the matching rig + character files.

Unlike cut_parts.py (which follows the chibi stand-in rig), the skeleton is measured from the illustration itself:
  specs/<name>.json lists joint positions in the illustration; this tool
    1. gives every illustration pixel to the nearest bone capsule (distance / radius),
    2. straightens each limb so its bone points down (the rig's rest pose) and crops a tight canvas around it,
    3. fills the areas other limbs hide (arm over torso...) by inpainting,
    4. writes parts/*.png (+ *_glow.png), art/rigs/<rig>.json and art/characters/<id>/character.json.

Usage:
    python cut_rig_parts.py --spec specs/rin_tall.json --image rin_tall.png --char art/characters/rin --rig art/rigs/humanoid_tall.json
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np

from cut_parts import foreground, glow_layer, nearest_fill
from sam_masks import segment, segment_points, slug

SEAM = 10  # px of overlap around each part so rotated joints show no cracks (texture px)
PIECE_GROW = 4  # px the cloth pieces are widened past the clothes edge (texture px)
HIDE_GROW = 13  # px the hidden area is widened before inpainting (drops the occluder's anti-aliased edge)
MIN_BLOB = 0.02  # connected pieces smaller than this share of a part's largest piece are stray strands
PAD = 3
SKIN_NOTE = "由 tools/comfyui/cut_rig_parts.py 依立繪切出"


def seg_dist(points: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Distance from each (x, y) point to the segment a-b."""
    ab = b - a
    t = np.clip(((points - a) @ ab) / max(float(ab @ ab), 1e-6), 0.0, 1.0)
    return np.linalg.norm(points - (a + t[:, None] * ab), axis=1)


def keep_big_blobs(mask: np.ndarray) -> np.ndarray:
    """Drop stray strands: connected pieces much smaller than the part's largest piece."""
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if n <= 2:
        return mask
    areas = stats[1:, cv2.CC_STAT_AREA]
    keep = np.nonzero(areas >= areas.max() * MIN_BLOB)[0] + 1
    return np.isin(labels, keep)


def align_to(base_rgb: np.ndarray, other_rgb: np.ndarray, keep_y: tuple[int, int]) -> np.ndarray:
    """Affine-align `other` (same character and pose, e.g. the torn-clothes edit) onto `base` using the
    parts the edit did not touch (rows above keep_y[0] = head, below keep_y[1] = boots)."""
    h, w = base_rgb.shape[:2]
    other = cv2.resize(other_rgb, (w, h), interpolation=cv2.INTER_AREA)
    g0 = cv2.cvtColor(base_rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255
    g1 = cv2.cvtColor(other, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255
    mask = np.zeros((h, w), np.uint8)
    mask[: keep_y[0]] = 1
    mask[keep_y[1]:] = 1
    warp = np.eye(2, 3, dtype=np.float32)
    try:
        _, warp = cv2.findTransformECC(g0, g1, warp, cv2.MOTION_AFFINE, (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 200, 1e-6), mask, 5)
    except cv2.error as e:
        print("WARN ECC alignment failed, using plain resize:", e)
        return other
    print(f"  aligned damaged image: shift=({warp[0, 2]:.1f},{warp[1, 2]:.1f}) scale=({warp[0, 0]:.3f},{warp[1, 1]:.3f})")
    return cv2.warpAffine(other, warp, (w, h), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP, borderMode=cv2.BORDER_REPLICATE)


def hairlike(rgb: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(rgb.reshape(-1, 1, 3), cv2.COLOR_RGB2HSV).reshape(-1, 3).astype(float)
    h, s, v = hsv[:, 0] * 2, hsv[:, 1] / 255, hsv[:, 2] / 255
    white = (s < 0.3) & (v > 0.78)
    pink = ((h > 290) | (h < 10)) & (s > 0.25) & (s < 0.85) & (v > 0.75)
    return white | pink


def frame(mode: str, a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Local axes (ex, ey) of a part canvas, as illustration-space unit vectors."""
    if mode == "upright":
        return np.array([1.0, 0.0]), np.array([0.0, 1.0])
    d = (b - a) / max(np.linalg.norm(b - a), 1e-6)
    if mode == "hand":  # fingers point along +x (the rig turns the hand toward the aim direction)
        return d, np.array([-d[1], d[0]])
    return np.array([d[1], -d[0]]), d  # "bone": +y runs from the joint along the bone


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--char", required=True, help="character folder to (re)write, e.g. art/characters/rin")
    ap.add_argument("--rig", required=True, help="rig JSON to write, e.g. art/rigs/humanoid_tall.json")
    ap.add_argument("--sam-dir", help="folder of SAM masks (default <image>_sam; created with ComfyUI running if missing)")
    ap.add_argument("--damaged", help="same character and pose with torn clothes (Qwen edit); becomes the base layer, the intact image becomes breakable cloth pieces")
    ap.add_argument("--fill", help="intact image with the arm removed and the body behind it completed (Qwen edit); colours for areas the arm hides")
    ap.add_argument("--damaged-fill", help="same for the torn-clothes image")
    ap.add_argument("--verify", help="folder: re-assemble all parts at rest pose (no game lighting) and diff against the illustration")
    ap.add_argument("--sam-only", action="store_true", help="parts are exactly the SAM masks listed in spec.sam_only (no geometry, no fill, no damage layer, no cloth pieces)")
    ap.add_argument("--pose", help="keypoints.json from pose_keypoints.py (SAM 3D Body): overrides the joints listed in spec.pose.joints")
    ap.add_argument("--debug", help="folder for debug images (ownership map)")
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    img = cv2.cvtColor(cv2.imread(args.image), cv2.COLOR_BGR2RGB)
    img = cv2.resize(img, None, fx=k, fy=k, interpolation=cv2.INTER_AREA)
    h, w = img.shape[:2]
    J = {n: np.array(p, float) * k for n, p in spec["joints"].items()}
    px_wp = spec["tex_px_per_wp"]
    if args.pose:
        pose_pts = json.loads(Path(args.pose).read_text())["points"]
        for joint, kp in spec["pose"]["joints"].items():
            moved = np.array(pose_pts[kp]) * k
            print(f"  joint {joint}: hand-labelled {np.round(J[joint] / k)} -> predicted {np.round(moved / k)}")
            J[joint] = moved
    person_cache = Path(args.sam_dir or (Path(args.image).parent / (Path(args.image).stem + "_sam"))) / "_person"

    def fg_sam(rgb: np.ndarray) -> np.ndarray:
        """Cut-out of the character by SAM 3.1 (prompt spec.person_prompt), cached per picture.
        A colour threshold leaves grey pockets between hair strands and a grey fringe; SAM does not."""
        key = hashlib.md5(rgb.tobytes()).hexdigest()[:10]
        d = person_cache / key
        prompt = spec.get("person_prompt", "woman")
        if not (d / f"{slug(prompt)}.png").exists():
            d.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(d / "picture.png"), cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
            segment(str(d / "picture.png"), [prompt], str(d))
        m = cv2.imread(str(d / f"{slug(prompt)}.png"), cv2.IMREAD_GRAYSCALE)
        m = cv2.resize(m, (rgb.shape[1], rgb.shape[0]), interpolation=cv2.INTER_LINEAR) > 127
        return m

    fg = fg_sam(img)
    dmg = dmg_fg = None
    if args.damaged:
        raw = cv2.cvtColor(cv2.imread(args.image), cv2.COLOR_BGR2RGB)
        d_raw = cv2.cvtColor(cv2.imread(args.damaged), cv2.COLOR_BGR2RGB)
        keep = (int(spec["joints"]["head"][1] + 10), int(spec["joints"]["ankle"][1] - 30))
        d_raw = align_to(raw, d_raw, keep)
        dmg = cv2.resize(d_raw, (w, h), interpolation=cv2.INTER_AREA)
        dmg_fg = fg_sam(dmg)
    fill = fill_fg = dmg_fill = dmg_fill_fg = None

    def load_fill(path: str) -> tuple[np.ndarray, np.ndarray]:
        raw = cv2.cvtColor(cv2.imread(args.image), cv2.COLOR_BGR2RGB)
        other = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB)
        keep = (int(spec["joints"]["head"][1] + 10), int(spec["joints"]["ankle"][1] - 30))
        out = cv2.resize(align_to(raw, other, keep), (w, h), interpolation=cv2.INTER_AREA)
        return out, fg_sam(out)
    if args.fill:
        fill, fill_fg = load_fill(args.fill)
    if args.damaged_fill:
        dmg_fill, dmg_fill_fg = load_fill(args.damaged_fill)
    parts = spec["parts"]
    prompts = [c["prompt"] for c in spec["sam_classes"]]
    all_prompts = prompts + [d["prompt"] for d in spec.get("sam_direct", []) if d["prompt"] not in prompts]
    part_names = [p["texture"] for p in parts]

    def sam_for(image_path: str, folder: str) -> Path:
        """SAM 3.1 masks of one picture (cached); returns the folder."""
        d = Path(folder)
        if not all((d / f"{slug(t)}.png").exists() for t in all_prompts):
            print(f"running SAM 3.1 on {Path(image_path).name} ...")
            segment(image_path, all_prompts, str(d))
        return d

    def build_owner(rgb: np.ndarray, fgm: np.ndarray, mdir: Path, src_path: str, limbs: bool = True) -> tuple[np.ndarray, np.ndarray]:
        """Which part each pixel of this picture belongs to: SAM classes limit the candidates, bone capsules pick one."""
        yy, xx = np.nonzero(fgm)
        pt = np.stack([xx, yy], axis=1).astype(float)
        kl = np.full((h, w), -1, np.int8)
        for ci in reversed(range(len(prompts))):  # earlier classes are more specific and win
            m = cv2.imread(str(mdir / f"{slug(prompts[ci])}.png"), cv2.IMREAD_GRAYSCALE)
            kl[cv2.resize(m, (w, h), interpolation=cv2.INTER_LINEAR) > 127] = ci
        cls = kl[yy, xx]
        ok = np.zeros((len(parts), len(pt)), bool)
        for ci, c in enumerate(spec["sam_classes"]):
            for part in c["parts"]:
                ok[part_names.index(part)][cls == ci] = True
        unclass = cls < 0
        far_leg = unclass & (pt[:, 1] > spec["drop_unclassified_below_y"] * k)
        hair_px = hairlike(rgb[yy, xx])
        cost = np.full((len(parts), len(pt)), 9.0)
        for i, p in enumerate(parts):
            d = seg_dist(pt, J[p["from"]], J[p["to"]]) / (p["radius"] * k)
            if p.get("hair"):
                d = np.where(hair_px | ~unclass, d, d * 3.0 + 1.0)
            cost[i] = np.where(ok[i] | unclass, d, 9.0)
        flat = cost.argmin(axis=0)
        flat[(cost.min(axis=0) > 2.5) | far_leg] = -1
        for ch in spec.get("chains", []):
            # a chain of parts along one limb is split by straight lines across the bone at each joint
            # (nearest-bone distance would leave V-shaped seams that look wrong once the joint turns)
            idx = np.array([part_names.index(n) for n in ch["parts"]])
            a_, b_ = J[ch["axis"][0]], J[ch["axis"][1]]
            ax_ = (b_ - a_) / np.linalg.norm(b_ - a_)
            along = (pt - a_) @ ax_
            cuts = np.array([(J[c] - a_) @ ax_ for c in ch["cuts"]])
            inside = np.isin(flat, idx)
            flat[inside] = idx[np.searchsorted(cuts, along[inside])]
        for lp in (spec.get("sam_limbs", []) if limbs else []):  # (not on the arm-removed picture: there is no arm to prompt)
            # arm segments: SAM point prompts (positive on the segment, negative on its neighbours)
            f = mdir / f"pt_{lp['part']}.png"
            if not f.exists():
                mid = lambda pair: [int(round(v)) for v in ((J[pair[0]] + J[pair[1]]) / 2 / k)]
                segment_points(src_path, str(mdir), {f"pt_{lp['part']}": {"pos": [mid(x) for x in lp["pos"]], "neg": [mid(x) for x in lp["neg"]]}})
            m = cv2.imread(str(f), cv2.IMREAD_GRAYSCALE)
            flat[(cv2.resize(m, (w, h), interpolation=cv2.INTER_LINEAR) > 127)[yy, xx]] = part_names.index(lp["part"])
        for dp in reversed(spec.get("sam_direct", [])):  # parts SAM can name directly (hand): its mask IS the part
            m = cv2.imread(str(mdir / f"{slug(dp['prompt'])}.png"), cv2.IMREAD_GRAYSCALE)
            flat[(cv2.resize(m, (w, h), interpolation=cv2.INTER_LINEAR) > 127)[yy, xx]] = part_names.index(dp["part"])
        own_map = np.full((h, w), -1, np.int16)
        own_map[yy, xx] = flat
        return own_map, kl

    masks_dir = sam_for(args.image, args.sam_dir or (Path(args.image).parent / (Path(args.image).stem + "_sam")))
    owner, klass = build_owner(img, fg, masks_dir, args.image)
    if args.sam_only:
        # nothing but SAM: each part is the mask of its text prompt; earlier entries win where masks overlap
        names_ = [p["texture"] for p in parts]
        owner = np.full((h, w), -1, np.int16)
        d_ = sam_for(args.image, masks_dir)
        for entry in reversed(spec["sam_only"]):
            if not (masks_dir / f"{slug(entry['prompt'])}.png").exists():
                segment(args.image, [entry["prompt"]], str(masks_dir))
            m_ = cv2.imread(str(masks_dir / f"{slug(entry['prompt'])}.png"), cv2.IMREAD_GRAYSCALE)
            owner[(cv2.resize(m_, (w, h), interpolation=cv2.INTER_LINEAR) > 127) & fg] = names_.index(entry["part"])
        for p_ in parts:
            p_.pop("occluded_by", None)
        spec["pieces"] = []
    owner_fill = None
    if fill is not None:  # the picture with the arm removed: where does each pixel under the arm really belong?
        owner_fill, _ = build_owner(fill, fill_fg, sam_for(args.fill, Path(args.fill).parent / (Path(args.fill).stem + "_sam")), args.fill, limbs=False)
    if dmg is not None:
        # Torn-clothes layer: take its pixels only where there are clothes. Skin, hair, prosthetic and boots are the same
        # in both pictures, so use the intact ones there; otherwise the few-pixel drift between the two edits shows
        # through the cloth pieces as skin-coloured streaks.
        never = [prompts.index(c) for c in spec.get("never_cloth", [])]
        cloth_zone = fg & ~np.isin(klass, never)
        cloth_zone = cv2.dilate(cloth_zone.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))) > 0
        dmg = np.where(cloth_zone[:, :, None], dmg, img)
        dmg_fg = np.where(cloth_zone, dmg_fg, fg)
    names = [p["texture"] for p in parts]
    if args.debug:
        Path(args.debug).mkdir(parents=True, exist_ok=True)
        rng = np.random.default_rng(3)
        palette = rng.integers(40, 255, (len(parts), 3)).astype(np.uint8)
        vis = img.copy() // 3
        m = owner >= 0
        vis[m] = (vis[m] // 2 + palette[owner[m]] // 2)
        cv2.imwrite(str(Path(args.debug) / "ownership.png"), cv2.cvtColor(vis, cv2.COLOR_RGB2BGR))

    out_parts = Path(args.char) / "parts"
    out_parts.mkdir(parents=True, exist_ok=True)
    for old in out_parts.glob("*"):
        old.unlink()
    textures, transforms, piece_uses = {}, {}, []
    store = {}
    seam = 4 if args.sam_only else SEAM
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * seam + 1, 2 * seam + 1))
    for i, p in enumerate(parts):
        a, bpt = J[p["from"]], J[p["to"]]
        pivot_pt = J[p.get("pivot", p["from"])]
        own = keep_big_blobs(owner == i)
        hidden = np.zeros((h, w), bool)
        if p.get("occluded_by"):
            occ = np.isin(owner, [names.index(n) for n in p["occluded_by"] if n in names])
            cap = np.zeros((h, w), np.float32)
            yy, xx = np.mgrid[0:h, 0:w]
            near = seg_dist(np.stack([xx.ravel(), yy.ravel()], 1).astype(float), a, bpt).reshape(h, w) <= p["radius"] * k
            # only fill inside the part's own outline (convex hull of its visible pixels), never out into empty space
            hull = np.zeros((h, w), np.uint8)
            if own.any():
                cv2.fillConvexPoly(hull, cv2.convexHull(np.argwhere(own)[:, ::-1].astype(np.int32)), 1)
            if owner_fill is not None:
                hidden = occ & (owner_fill == i) & fill_fg
            else:
                hidden = occ & near & fg & (hull > 0)
        full = cv2.dilate((own | hidden).astype(np.uint8), kernel) > 0
        full &= fg | hidden
        if own.sum() < 20:
            print(f"WARN {p['texture']}: only {int(own.sum())} px")
            continue
        ex, ey = frame(p["mode"], a, bpt)
        ysf, xsf = np.nonzero(full)
        rel = np.stack([xsf, ysf], 1) - pivot_pt
        u, v = rel @ ex, rel @ ey
        umin, umax, vmin, vmax = u.min() - PAD, u.max() + PAD, v.min() - PAD, v.max() + PAD
        cw, ch = int(math.ceil(umax - umin)), int(math.ceil(vmax - vmin))
        piv = np.array([-umin, -vmin])
        # canvas px (i, j) -> illustration px
        A = np.float32([[ex[0], ey[0], pivot_pt[0] - piv[0] * ex[0] - piv[1] * ey[0]],
                        [ex[1], ey[1], pivot_pt[1] - piv[0] * ex[1] - piv[1] * ey[1]]])
        y0, y1, x0, x1 = max(ysf.min() - 8, 0), min(ysf.max() + 9, h), max(xsf.min() - 8, 0), min(xsf.max() + 9, w)
        sl = (slice(y0, y1), slice(x0, x1))

        def render(src, src_fg, own_m, hidden_m, full_m, fill_src=None, fill_src_fg=None):
            """Warp one illustration into this part's straightened canvas: real pixels where it has them, nearest fill / inpaint elsewhere."""
            grow = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * HIDE_GROW + 1, 2 * HIDE_GROW + 1))
            hole = cv2.dilate(hidden_m[sl].astype(np.uint8), grow) > 0
            color = nearest_fill(src[sl], own_m[sl] & ~hole)
            hole0 = hole.copy()
            if hole.any():
                if fill_src is not None:  # the completed body behind the arm
                    color = np.where((hole & fill_src_fg[sl])[:, :, None], fill_src[sl], color)
                    hole = hole & ~fill_src_fg[sl]
                if hole.any():
                    color = cv2.inpaint(color, hole.astype(np.uint8), 8, cv2.INPAINT_TELEA)
            color = np.where((src_fg[sl] & ~hole & ~(hidden_m[sl] if fill_src is not None else False))[:, :, None], src[sl], color)
            canvas_img = np.zeros((h, w, 3), np.uint8)
            canvas_img[sl] = color
            mask_img = np.zeros((h, w), np.uint8)
            mask_img[sl] = full_m[sl].astype(np.uint8) * 255
            flags = cv2.INTER_LANCZOS4 | cv2.WARP_INVERSE_MAP
            return (cv2.warpAffine(canvas_img, A, (cw, ch), flags=flags, borderMode=cv2.BORDER_REPLICATE),
                    cv2.warpAffine(mask_img, A, (cw, ch), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP))

        col_intact, alpha_intact = render(img, fg, own, hidden, full, fill, fill_fg)
        if dmg is not None:  # base layer = the torn-clothes illustration, same ownership and hidden areas
            own_d = own & dmg_fg
            # the base may never reach past the intact silhouette: at full health only the cloth pieces may be seen
            full_d = (cv2.dilate((own_d | hidden).astype(np.uint8), kernel) > 0) & (dmg_fg | hidden) & (fg | hidden)
            col, alpha = render(dmg, dmg_fg, own_d, hidden, full_d, dmg_fill, dmg_fill_fg)
        else:
            col, alpha = col_intact, alpha_intact
        claimed = np.zeros((h, w), bool)
        piece_alphas = []
        keep_ids = [prompts.index(c) for c in spec.get("never_cloth", [])]
        for q in spec.get("pieces", []):
            if q["source"] != p["texture"]:
                continue
            cls_ids = [prompts.index(c) for c in q["classes"]]
            piece = own & np.isin(klass, cls_ids) & fg
            if q.get("rest"):  # everything else on this part that is not skin / hair / prosthetic / boots: unclassified clothes (belt, trim...)
                piece |= own & fg & ~claimed & ~np.isin(klass, keep_ids)
            piece &= ~claimed | np.isin(klass, cls_ids)
            claimed |= piece
            if q.get("rest"):
                piece |= hidden  # the stretch an arm covers in the pose is filled in, so it must be cloth as well
            # grow the piece a little past its edge so the torn layer underneath never shows as a rim around it
            piece = (cv2.dilate(piece.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * PIECE_GROW + 1, 2 * PIECE_GROW + 1))) > 0) & (fg | hidden)
            _, piece_alpha = render(img, fg, own, hidden, piece, fill, fill_fg)
            piece_alphas.append(piece_alpha)
            qtex = q["texture"]
            cv2.imwrite(str(out_parts / f"{qtex}.png"), np.dstack([cv2.cvtColor(col_intact, cv2.COLOR_RGB2BGR), piece_alpha]))
            q_entry = {"file": f"parts/{qtex}.png", "size": [cw, ch], "pivot": [round(float(piv[0]), 2), round(float(piv[1]), 2)], "note": "可打飛的衣物片（完整版）：" + SKIN_NOTE}
            q_kind = spec["glow"].get(qtex)
            if q_kind:
                q_glow = glow_layer(col_intact, piece_alpha, q_kind)
                q_glow = np.zeros((ch, cw, 4), np.uint8) if q_glow is None else q_glow
                cv2.imwrite(str(out_parts / f"{qtex}_glow.png"), cv2.cvtColor(q_glow, cv2.COLOR_RGBA2BGRA))
                q_entry["glow"] = f"parts/{qtex}_glow.png"
            textures[qtex] = q_entry
            piece_uses.append((q, qtex))
            store[qtex] = (A, col_intact, piece_alpha)
        if dmg is not None and piece_alphas:
            # Where this part has clothes, the torn base may only exist underneath a cloth piece (otherwise it shows at full
            # health as a stray patch); the bare parts of the part (skin, prosthetic, hair, boots) are kept as they are.
            union = np.maximum.reduce(piece_alphas)
            bare = cv2.warpAffine(((own & np.isin(klass, keep_ids)) * 255).astype(np.uint8), A, (cw, ch), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP)
            allowed = np.maximum(union, bare)
            alpha = (alpha.astype(np.float32) * (allowed > 60)).astype(np.uint8)
        tex = p["texture"]
        cv2.imwrite(str(out_parts / f"{tex}.png"), np.dstack([cv2.cvtColor(col, cv2.COLOR_RGB2BGR), alpha]))
        entry = {"file": f"parts/{tex}.png", "size": [cw, ch], "pivot": [round(float(piv[0]), 2), round(float(piv[1]), 2)], "note": SKIN_NOTE}
        kind = spec["glow"].get(tex)
        if kind:
            glow = glow_layer(col, alpha, kind)
            glow = np.zeros((ch, cw, 4), np.uint8) if glow is None else glow
            cv2.imwrite(str(out_parts / f"{tex}_glow.png"), cv2.cvtColor(glow, cv2.COLOR_RGBA2BGRA))
            entry["glow"] = f"parts/{tex}_glow.png"
        textures[tex] = entry
        transforms[tex] = (A, cw, ch)
        store[tex] = (A, col, alpha)
        print(f"  {tex}: {cw}x{ch} pivot=({piv[0]:.1f},{piv[1]:.1f}) own={int(own.sum())} hidden={int(hidden.sum())}")

    # --- rig: bone rest positions in world px (origin = feet, +y down), limbs straight down
    ground = spec["ground_y"] * k
    hip_pt = J["hip"]
    bones, abs_pos = [], {}
    by_name = {b["name"]: b for b in spec["bones"]}

    def joint_of(bone: str) -> np.ndarray:
        """Where the bone's origin sits in the illustration (a chain link starts at its parent's tip)."""
        b = by_name[bone]
        if bone == "hip":
            return J["hip"]
        if "at" in b:
            return J[b["at"]]
        return J[by_name[b["parent"]]["tip"]]

    for b in spec["bones"]:
        name, parent = b["name"], b["parent"]
        if name == "hip":
            pos = [0.0, -round((ground - hip_pt[1]) / px_wp, 2)]
        elif "fixed" in b:
            pos = b["fixed"]
        elif "at" in b:
            delta = (J[b["at"]] - joint_of(parent)) / px_wp
            pos = [round(float(delta[0]) + b.get("dx", 0.0), 2), round(float(delta[1]), 2)]
        else:  # next link of a straightened chain: straight down by the parent's bone length
            pb = by_name[parent]
            pos = [0.0, round(float(np.linalg.norm(J[pb["tip"]] - joint_of(parent))) / px_wp, 2)]
        bones.append({"name": name, "parent": parent, "pos": pos})
    anchor_cfg = spec["weapon_anchor"]
    anchor = ((J[anchor_cfg["to"]] - J[anchor_cfg["from"]]) / px_wp)
    rig = {"id": Path(args.rig).stem,
           "description": "人形骨架（7.5 頭身版）。座標單位為世界像素，原點在腳底，面向右（+X），Y 軸向下；骨頭靜止時沿 +Y 延伸。長度由立繪量出（" + SKIN_NOTE + "）。",
           "bones": bones,
           "weapon_anchor": {"bone": anchor_cfg["bone"], "pos": [round(float(anchor[0]) + anchor_cfg["dx"], 2), round(float(anchor[1]) + anchor_cfg["dy"], 2)], "reach": anchor_cfg["reach"]}}
    Path(args.rig).write_text(json.dumps(rig, ensure_ascii=False, indent=2) + "\n", encoding="utf8")

    # --- character.json
    use_list = []
    for p in parts:
        if p["texture"] not in textures:
            continue
        for u in p["uses"]:
            use_list.append(dict(u, texture=p["texture"]))
    for q, qtex in piece_uses:
        for u in q["uses"]:
            use_list.append(dict(u, texture=qtex))
    use_list.sort(key=lambda e: e["z"])
    char = {"id": spec["id"], "display_name": spec["display_name"], "rig": "res://art/rigs/" + Path(args.rig).name,
            "texture_scale": round(1.0 / px_wp, 5), "scale": spec["scale"]}
    blink = spec.get("blink")
    if blink and blink["part"] in transforms:
        A, cw, ch = transforms[blink["part"]]
        inv = cv2.invertAffineTransform(A)

        def to_canvas(pt: list) -> list:
            q = inv @ np.array([pt[0] * k, pt[1] * k, 1.0])
            return [round(float(q[0]), 1), round(float(q[1]), 1)]
        char["portrait"] = {"description": "背包立繪的眨眼設定（頭部貼圖像素座標）：part＝頭部零件名稱；eye＝要被抹成膚色的眼睛範圍（四邊形 x1,y1,…x4,y4）；lid＝閉眼時畫上的眼線（x1,y1,x2,y2）。",
                            "blink": {"part": blink["part"], "eye": sum((to_canvas(p) for p in blink["eye"]), []), "lid": sum((to_canvas(p) for p in blink["lid"]), [])}}
    char["description"] = "外觀（skin）定義：textures 是零件圖片的尺寸與支點；parts 是把圖片掛到骨頭上的方式。" + SKIN_NOTE + "。"
    char["textures"] = textures
    char["parts"] = [{"name": u["name"], "texture": u["texture"], "bone": u["bone"], "z": u["z"], **({"tint": u["tint"]} if "tint" in u else {}), **({"armor_order": u["armor_order"]} if "armor_order" in u else {}), **({"offset": u["offset"]} if "offset" in u else {})} for u in use_list]
    (Path(args.char) / "character.json").write_text(json.dumps(char, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print("rig bones:", len(bones), " parts:", len(char["parts"]))
    if args.verify:
        Path(args.verify).mkdir(parents=True, exist_ok=True)

        def assemble(with_pieces: bool) -> np.ndarray:
            canvas = np.zeros((h, w, 3), np.float32)
            for u in char["parts"]:
                if u.get("tint", 1.0) < 1.0 or (not with_pieces and u["texture"].startswith("cloth_")):
                    continue  # far-side copies are dimmed duplicates
                A, col, alpha = store[u["texture"]]
                placed = cv2.warpAffine(col, A, (w, h), flags=cv2.INTER_LINEAR)
                a = cv2.warpAffine(alpha, A, (w, h), flags=cv2.INTER_LINEAR).astype(np.float32)[:, :, None] / 255
                canvas = canvas * (1 - a) + placed.astype(np.float32) * a
            return canvas.astype(np.uint8)
        full = assemble(True)
        base_only = assemble(False)
        cover = np.zeros((h, w), bool)
        for A, col, alpha in store.values():
            cover |= cv2.warpAffine(alpha, A, (w, h), flags=cv2.INTER_NEAREST) > 40
        diff = np.abs(full.astype(int) - img.astype(int)).max(axis=2)
        bad = (diff > 60) & fg
        # where the torn base layer would be seen at full health: base pixels no cloth piece covers
        piece_cover = np.zeros((h, w), np.float32)
        base_cover = np.zeros((h, w), np.float32)
        for u in char["parts"]:
            if u.get("tint", 1.0) < 1.0:
                continue
            A, col, alpha = store[u["texture"]]
            a = cv2.warpAffine(alpha, A, (w, h), flags=cv2.INTER_LINEAR).astype(np.float32) / 255
            target = piece_cover if u["texture"].startswith("cloth_") else base_cover
            np.maximum(target, a, out=target)
        exposed = (base_cover > 0.3) & (piece_cover < 0.9) & ((fg) | (base_cover > 0.3))
        exposed_vis = np.where(exposed[:, :, None], [255, 80, 0], img // 3).astype(np.uint8)
        # parts of the character the pieces cover but only partly (soft edges) are also exposed
        vis = np.hstack([img, full, exposed_vis, np.where(bad[:, :, None], [255, 0, 0], img // 3).astype(np.uint8)])
        cv2.imwrite(str(Path(args.verify) / "verify.png"), cv2.cvtColor(vis, cv2.COLOR_RGB2BGR))
        print(f"verify: {int(bad.sum())} px ({100 * bad.sum() / max(fg.sum(), 1):.2f}% of the character) differ strongly from the illustration; "
              f"{int((fg & ~cover).sum())} character px are covered by no part")


if __name__ == "__main__":
    main()
