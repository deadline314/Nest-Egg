"""Split a transparent-background side view into complete character parts (full-canvas RGBA PNGs).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/make_parts.py --spec tools/comfyui/specs/rin_side.json --work art_src/characters/rin2 [--no-complete] [--only arm,body]

Inputs  (in --work): base_rgba.png (Qwen 2.1 RGBA side view), sam/<prompt>.png (SAM 3.1 masks, made on demand through ComfyUI)
Outputs (in --work):
    05_groups/<group>_incomplete.png   what is visible of the group, cropped, transparent background  (Qwen input 1)
    05_groups/<group>_qwen.png         Qwen's completion of it                                          (raw)
    05_groups/<group>.png              full-canvas RGBA: visible pixels + completed gap (only where something in front hides it)
    06_parts/<part>.png                full-canvas RGBA of every part (same pixel coordinates as base_rgba.png)
    06_parts/ownership.png             debug picture: which part every pixel belongs to

How a pixel gets its part: SAM masks give the group (hand, arm, holster, jacket, hair, boot, head, body); groups hidden by
something in front of them are completed by Qwen (the gap only); limb groups are then cut at the joints (spec.cuts).
"""
import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sam_masks import segment, slug  # noqa: E402


def largest_blobs(mask: np.ndarray, min_share: float = 0.02) -> np.ndarray:
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if n <= 2:
        return mask
    areas = st[1:, cv2.CC_STAT_AREA]
    return np.isin(lab, np.nonzero(areas >= areas.max() * min_share)[0] + 1)


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    if r <= 0:
        return mask
    return cv2.dilate(mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))) > 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--no-complete", action="store_true", help="skip Qwen: parts are just the visible pixels")
    ap.add_argument("--only", help="comma list of groups to (re)complete; the others reuse 05_groups/<group>.png when present")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--redo-stage", help="comma list of stage pictures to generate again")
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    work = Path(args.work)
    rgba = np.array(Image.open(work / "base_rgba.png").convert("RGBA"))
    H, W = rgba.shape[:2]
    alpha = rgba[:, :, 3] > 127
    rgb = rgba[:, :, :3]

    # ---- SAM masks --------------------------------------------------------------------------------------------
    prompts = sorted({p for g in spec["groups"].values() for p in g["sam"]} | {p for g in spec["groups"].values() for p in g.get("minus", [])})
    sam_dir = work / "sam"
    grey = work / "base_grey.png"
    if not grey.exists():
        bg = Image.new("RGBA", (W, H), (128, 128, 128, 255))
        bg.alpha_composite(Image.fromarray(rgba))
        bg.convert("RGB").save(grey)
    missing = [p for p in prompts if not (sam_dir / f"{slug(p)}.png").exists()]
    if missing:
        print("SAM 3.1:", missing)
        segment(str(grey), missing, str(sam_dir))
    M = {p: (np.array(Image.open(sam_dir / f"{slug(p)}.png").convert("L").resize((W, H))) > 127) & alpha for p in prompts}

    # ---- visible group masks (first group in spec order wins) -------------------------------------------------
    order = list(spec["groups"].keys())
    V: dict[str, np.ndarray] = {}
    taken = np.zeros((H, W), bool)
    for name in order:
        g = spec["groups"][name]
        m = np.zeros((H, W), bool)
        for p in g["sam"]:
            m |= M[p]
        for p in g.get("minus", []):
            m &= ~M[p]
        m &= ~taken
        m = largest_blobs(m)
        V[name] = m
        taken |= m
    # pixels no group claims go to the nearest claimed pixel's group (anti-aliased edges, small gaps)
    left = alpha & ~taken
    if left.any():
        idx = ndimage.distance_transform_edt(~taken, return_distances=False, return_indices=True)
        label = np.full((H, W), -1, np.int16)
        for i, name in enumerate(order):
            label[V[name]] = i
        near = label[idx[0], idx[1]]
        for i, name in enumerate(order):
            V[name] = V[name] | (left & (near == i))
    gdir = work / "05_groups"
    pdir = work / "06_parts"
    gdir.mkdir(exist_ok=True)
    pdir.mkdir(exist_ok=True)

    # ---- stage pictures: peel the character layer by layer (remove what is in front, let Qwen paint what was behind) ----------
    from comfy_api import qwen
    sdir = work / "04_stages"
    sdir.mkdir(exist_ok=True)
    stage_rgba: dict[str, np.ndarray] = {}
    prev_path = work / "base_rgba.png"
    for st in spec.get("stages", []):
        sp_ = sdir / f"{st['name']}.png"
        if not sp_.exists() or (args.redo_stage and st["name"] in args.redo_stage.split(",")):
            src = prev_path if st.get("from") is None else sdir / f"{st['from']}.png"
            t0 = time.time()
            made = qwen("This is an RGBA image with transparency. " + st["prompt"] + " The image has alpha channel and the background is transparent.",
                        images=[str(src)], seed=st.get("seed", 51), prefix=f"{spec['id']}_stage_{st['name']}", w=W, h=H)[0]
            Image.open(made).convert("RGBA").resize((W, H)).save(sp_)
            print(f"stage {st['name']}: {time.time() - t0:.0f}s")
        stage_rgba[st["name"]] = np.array(Image.open(sp_).convert("RGBA"))
    stage_masks: dict[str, dict[str, np.ndarray]] = {}
    for sname, arr_ in stage_rgba.items():
        gimg = sdir / f"{sname}_grey.png"
        bgi = Image.new("RGBA", (W, H), (128, 128, 128, 255))
        bgi.alpha_composite(Image.fromarray(arr_))
        bgi.convert("RGB").save(gimg)
        need = sorted({p for gname, g in spec["groups"].items() if g.get("complete", {}).get("stage") == sname for p in g["sam"]})
        have = {p: sdir / f"sam_{sname}" / f"{slug(p)}.png" for p in need}
        miss = [p for p in need if not have[p].exists()]
        if miss:
            segment(str(gimg), miss, str(sdir / f"sam_{sname}"))
        stage_masks[sname] = {p: (np.array(Image.open(have[p]).convert("L").resize((W, H))) > 127) & (arr_[:, :, 3] > 127) for p in need}

    # ---- completion of hidden groups --------------------------------------------------------------------------
    only = set(args.only.split(",")) if args.only else None
    complete: dict[str, np.ndarray] = {}  # group -> full-canvas RGBA
    for name in order:
        g = spec["groups"][name]
        done = gdir / f"{name}.png"
        vis_rgba = np.dstack([rgb, (V[name] * 255).astype(np.uint8)])
        if "complete" not in g or args.no_complete or (only is not None and name not in only and done.exists()):
            if "complete" in g and not args.no_complete and done.exists() and (only is None or name not in only):
                complete[name] = np.array(Image.open(done).convert("RGBA"))
            else:
                complete[name] = vis_rgba
            continue
        if done.exists() and only is None:
            print(f"keep {done.name} (use --only {name} to redo)")
            complete[name] = np.array(Image.open(done).convert("RGBA"))
            continue
        c = g["complete"]
        occ = np.zeros((H, W), bool)
        for o in c["occluders"]:
            occ |= V[o]
        if "stage" in c:  # the group as it looks in a stage picture where everything in front of it was removed
            sm = np.zeros((H, W), bool)
            for p_ in g["sam"]:
                sm |= stage_masks[c["stage"]][p_]
            others = np.zeros((H, W), bool)
            for other in order:
                if other != name and other not in c["occluders"]:
                    others |= V[other]
            # only fully opaque stage pixels, pulled in a few px from the stage picture's outer edge: Qwen's edit paints a pale
            # semi-transparent rim there that would show up as a halo around the completed part
            solid = sm & (stage_rgba[c["stage"]][:, :, 3] >= 250)
            solid = cv2.erode(solid.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * c.get("edge_trim", 3) + 1,) * 2)) > 0
            if "reject_hue" in c:  # colours the hidden part can not have (e.g. the pale blue wisp Qwen paints at the tip of the hair)
                hsv = cv2.cvtColor(stage_rgba[c["stage"]][:, :, :3], cv2.COLOR_RGB2HSV)
                hue = hsv[:, :, 0].astype(int) * 2
                bad = (hue >= c["reject_hue"][0]) & (hue <= c["reject_hue"][1]) & (hsv[:, :, 1] > 25)
                solid &= ~dilate(bad, 2)
            gap = solid & dilate(occ, c.get("gap_grow", 14)) & ~others & ~V[name] & dilate(V[name], c.get("near", 120))
            final = largest_blobs(cv2.morphologyEx((V[name] | gap).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)) > 0)
            color = np.where(V[name][:, :, None], rgb, stage_rgba[c["stage"]][:, :, :3])
            layer = np.dstack([color, (final * 255).astype(np.uint8)])
            Image.fromarray(layer).save(done)
            complete[name] = layer
            continue
        ys, xs = np.nonzero(dilate(V[name], 50) | (dilate(occ, 10) & dilate(V[name], 80)))
        y0, y1, x0, x1 = max(ys.min(), 0), min(ys.max() + 1, H), max(xs.min(), 0), min(xs.max() + 1, W)
        crop_in = vis_rgba[y0:y1, x0:x1]
        Image.fromarray(crop_in).save(gdir / f"{name}_incomplete.png")
        my, mx = c.get("ref_margin", [40, 100])
        ry0, ry1, rx0, rx1 = max(y0 - my, 0), min(y1 + my, H), max(x0 - mx, 0), min(x1 + mx, W)
        Image.fromarray(rgba[ry0:ry1, rx0:rx1]).save(gdir / f"{name}_reference.png")
        prompt = ("This is an RGBA image with transparency. Image 1 is an incomplete cut-out of one part of the character: " + c["what"] + ", seen from the side facing right. "
                  "Some of it is missing because " + c["hidden_by"] + " covered it. Image 2 is the whole character for reference. "
                  "Complete image 1: draw the missing portions of this part as they would look if nothing covered them, in exactly the same art style, line weight and colors, connecting naturally to what is visible. "
                  "Keep every visible pixel unchanged. " + c.get("avoid", "") + " The image has alpha channel and the background is transparent.")
        t = time.time()
        out = qwen(prompt, images=[str(gdir / f"{name}_incomplete.png"), str(gdir / f"{name}_reference.png")], seed=args.seed or c.get("seed", 91),
                   prefix=f"{spec['id']}_{name}", resolution=1024)[0]
        print(f"qwen {name}: {time.time() - t:.0f}s")
        raw = Image.open(out).convert("RGBA")
        raw.save(gdir / f"{name}_qwen.png")
        ch, cw = y1 - y0, x1 - x0
        comp_a = cv2.resize(np.array(raw)[:, :, 3], (cw, ch), interpolation=cv2.INTER_AREA)
        comp_c = cv2.resize((np.array(raw)[:, :, :3].astype(np.float32) * (np.array(raw)[:, :, 3:] / 255.0)), (cw, ch), interpolation=cv2.INTER_AREA)
        comp_c = (comp_c / np.maximum(comp_a[:, :, None] / 255.0, 1e-3)).clip(0, 255).astype(np.uint8)
        sl = (slice(y0, y1), slice(x0, x1))
        others = np.zeros((H, W), bool)
        for other in order:
            if other != name and other not in c["occluders"]:
                others |= V[other]
        gap = np.zeros((H, W), bool)
        gap[sl] = comp_a > 127
        gap &= dilate(occ, c.get("gap_grow", 14)) & dilate(V[name], c.get("near", 90)) & ~others & ~V[name]
        final = V[name] | gap
        final = cv2.morphologyEx(final.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)) > 0
        final = largest_blobs(final & (V[name] | dilate(V[name], c.get("near", 90))))
        full = np.zeros((H, W, 3), np.uint8)
        full[sl] = comp_c
        color = np.where((V[name])[:, :, None], rgb, full)
        layer = np.dstack([color, (final * 255).astype(np.uint8)])
        Image.fromarray(layer).save(done)
        complete[name] = layer

    # ---- cut groups into parts --------------------------------------------------------------------------------
    yy, xx = np.mgrid[0:H, 0:W]
    seam = spec.get("seam", 10)
    parts: dict[str, np.ndarray] = {}
    for pname, pdef in spec["parts"].items():
        grp = complete[pdef["group"]]
        region = grp[:, :, 3] > 127
        if "minus_group" in pdef:
            region &= ~(complete[pdef["minus_group"]][:, :, 3] > 127)
        if "y" in pdef:
            lo, hi = pdef["y"]
            region &= (yy >= lo) & (yy < hi)
        if "within" in pdef:  # keep the pixels of this group that fall inside another group's visible mask (e.g. the hand inside the arm group)
            region &= dilate(V[pdef["within"]], pdef.get("within_grow", 3))
        if "not_within" in pdef:
            region &= ~dilate(V[pdef["not_within"]], pdef.get("within_grow", 3))
        parts[pname] = region
    # each part also gets `seam` px of its neighbours inside the same group, so joints can turn without cracks
    for pname, pdef in spec["parts"].items():
        grp = complete[pdef["group"]]
        region = parts[pname]
        grown = dilate(region, seam) & (grp[:, :, 3] > 127)
        if "minus_group" in pdef:
            grown &= ~(complete[pdef["minus_group"]][:, :, 3] > 127)
        grown = largest_blobs(grown)
        layer = grp.copy()
        layer[:, :, 3] = (grown * 255).astype(np.uint8)
        Image.fromarray(layer).save(pdir / f"{pname}.png")
        parts[pname] = grown
    rng = np.random.default_rng(5)
    pal = rng.integers(60, 255, (len(parts), 3)).astype(np.uint8)
    vis = (rgb // 3).copy()
    for i, (pname, m) in enumerate(parts.items()):
        vis[m] = vis[m] // 2 + pal[i] // 2
    Image.fromarray(vis).save(pdir / "ownership.png")
    print("parts:", ", ".join(f"{k}={int(v.sum())}" for k, v in parts.items()))


if __name__ == "__main__":
    main()
