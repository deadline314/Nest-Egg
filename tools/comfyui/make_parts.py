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

groups.<name>.points (NE-218): {"pos": [[x, y], ...], "neg": [[x, y], ...]} picks the group with SAM point prompts instead of (or on top of)
its text prompts; groups.<name>.rest: true gives it every picture pixel no earlier group took. "sam" may then be an empty list.

parts.<name>.caps (NE-222): [{"joint": "hip", "radius": 80, "feather": 10}] adds the group's pixels inside a disc around a joint to the part,
on top of its straight cut, and fades the disc's rim over `feather` px. Give it to BOTH parts of a rigid joint (pelvis and thigh at the hip,
torso and sleeve at the shoulder...): the two discs stay on top of each other at every angle, so the silhouette stays round and closed.
radius = about half the limb's width at the joint, in pixels of base_rgba.png. "sam": ["black stockings leg"] keeps only the cap pixels of
those SAM prompts. The part drawn on top gets the larger, feathered cap; the part under it a smaller hard one that the top cap always covers
(smaller than the shortest distance from the joint to the top part's outline), or its rim shows when the joint turns.

spec["near_leg"] (NE-152): in a side view both legs and both shoes are in the picture, but the rig draws ONE leg texture twice (the far
copy dimmed), so a leg part must hold exactly one leg. near_leg picks the near (front, unobstructed) leg with SAM point prompts and
makes it a group of its own ("group": "near_leg" in the parts):
    {"stage": "U", "stage_until": "knee", "lower_outline": [[x, y], ...]} optionally segment a peeled underlayer above the joint,
                               preserving the original lower limb below it; lower_outline is a reviewed polygon on base_rgba.png,
                               bounded by the completed body/boot alpha; colors stay original below stage_until, otherwise reuse the original point mask.
    {"pos": [[x, y], ...],     points on the near thigh, shin and shoe (pixels of base_rgba.png)
     "neg": [[x, y], ...],     points on the far leg and the other shoe
     "threshold": 0.3, "close": 9, "grow": 0,
     "fill": ["hand", "arm"],  groups that hang in front of the leg: their pixels inside the leg are painted again from the cloth beside them
     "cover": [{"pos": [[x, y]], "neg": []}],  point prompts of things that hang in front of the leg and belong to no group (a hand SAM took
                               for the body): they are painted over with the cloth beside them, like the "fill" groups
     "cover_limbs": true,       false = leave the notch where a hand or forearm hangs in front of the thigh (when the cloth behind it is unknown,
                               a colour ramp across it looks like a slab; a notch looks like a bite and the hand covers it)
     "thigh_x": [300, 478],     take every picture pixel between hip and knee inside this x range as thigh (hands and plates in front get painted over by "fill") (both thighs overlap in one big mass)
     "close_thigh": 30,         wide closing between hip and knee: fills the bite a hand or a pocket took out of the thigh's front
     "exclude": ["armor_chest"],  groups that are removed from the leg again (plates that ride another bone and would leave a slab behind)
     "extra": ["apron"]}       SAM text prompts of garments that hang over the thigh (an apron, a long coat): they are not the leg but
                               they belong to its sprite, otherwise they would vanish from the character
the leg is the SAM mask without those groups, closed and hole-filled; what is not known (hand, knee pad, cracks) gets a colour ramp.
"""
import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sam_masks import SAM_CKPT, segment, segment_points, slug  # noqa: E402

TEXT_MASK_THRESHOLD = 0.4
TEXT_MASK_REFINE = 2
POINT_MASK_REFINE = 2
TEXT_MASK_CACHE_VERSION = 1
TEXT_MASK_CACHE_NAME = ".text_mask_cache.json"


def largest_blobs(mask: np.ndarray, min_share: float = 0.02) -> np.ndarray:
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if n <= 2:
        return mask
    areas = st[1:, cv2.CC_STAT_AREA]
    return np.isin(lab, np.nonzero(areas >= areas.max() * min_share)[0] + 1)


def row_fill(color: np.ndarray, region: np.ndarray, known: np.ndarray, blur: float = 3.0) -> np.ndarray:
    """Colour every `region` pixel by a straight ramp along its row between the nearest `known` pixel on its left and on its right
    (a run with a known pixel on one side only copies that side). The gap behind a limb is mostly flat cloth, so a ramp looks like cloth."""
    H, W = region.shape
    out = color.astype(np.float32).copy()
    for y in np.nonzero(region.any(1))[0]:
        xs = np.nonzero(region[y])[0]
        start = 0
        for i in range(1, len(xs) + 1):
            if i < len(xs) and xs[i] == xs[i - 1] + 1:
                continue
            x0, x1 = xs[start], xs[i - 1]
            start = i
            left = x0 - 1 if x0 > 0 and known[y, x0 - 1] else None
            right = x1 + 1 if x1 < W - 1 and known[y, x1 + 1] else None
            if left is None and right is None:
                continue
            a = out[y, left] if left is not None else out[y, right]
            b = out[y, right] if right is not None else out[y, left]
            t = (np.arange(x0, x1 + 1) - x0 + 1.0) / (x1 - x0 + 2.0)
            out[y, x0:x1 + 1] = a[None] * (1 - t[:, None]) + b[None] * t[:, None]
    soft = cv2.GaussianBlur(out, (0, 0), sigmaX=blur, sigmaY=blur * 4)  # rows were filled one by one: even them out, more so along the limb
    out = np.where(region[:, :, None], soft, out)
    return np.clip(out, 0, 255).astype(np.uint8)


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    if r <= 0:
        return mask
    return cv2.dilate(mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))) > 0


def cap_distance(shape: tuple[int, int], joint) -> np.ndarray:
    """Distance of every pixel to a joint (pixels of base_rgba.png)."""
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return np.hypot(xx - float(joint[0]), yy - float(joint[1]))


def cap_alpha(alpha: np.ndarray, straight: np.ndarray, caps: list[tuple[np.ndarray, float, float]]) -> np.ndarray:
    """Fade the rim of a part's round joint caps (spec parts.caps): alpha stays whole inside the straight cut and inside each cap, and
    falls to 0 over the cap's last `feather` px. A hard rim drawn over the neighbouring part shows as a line once the joint turns.
    caps = [(distance to the joint, radius, feather)]."""
    keep = np.zeros(alpha.shape, np.float32)
    for dist, radius, feather in caps:
        keep = np.maximum(keep, np.clip((radius - dist) / max(feather, 1e-6), 0.0, 1.0))
    keep[straight] = 1.0
    return (alpha.astype(np.float32) * keep).round().astype(np.uint8)


def ensure_point_masks(image: Path, groups: dict, out_dir: Path, threshold: float = 0.3) -> dict:
    """SAM point-prompt masks of spec groups.<name>.points = {"pos": [[x, y], ...], "neg": [[x, y], ...]} (pixels of base_rgba.png).
    A limb a text prompt cannot tell from its twin (near arm / far arm, near leg / far leg) is picked by points on it and on what it is not.
    Cached per group by the picture and the points (out_dir/points_<name>.png + .json); returns {name: Path}."""
    result = {}
    for name, points in groups.items():
        png, key_json = out_dir / f"points_{name}.png", out_dir / f"points_{name}.json"
        key = near_leg_key({"pos": points["pos"], "neg": points.get("neg", []), "threshold": threshold}, image)
        if not (png.exists() and key_json.exists() and json.loads(key_json.read_text(encoding="utf8")).get("key") == key):
            print(f"SAM 3.1 points {name}:", points["pos"], points.get("neg", []))
            key_json.unlink(missing_ok=True)  # a failed run must not leave a valid key beside an old mask
            segment_points(str(image), str(out_dir), {f"points_{name}": {"pos": [tuple(q) for q in points["pos"]], "neg": [tuple(q) for q in points.get("neg", [])]}},
                           threshold=threshold)
            key_json.write_text(json.dumps({"key": key}), encoding="utf8")
        result[name] = png
    return result


def near_leg_key(cfg: dict, image: Path) -> str:
    """A changed source or SAM configuration invalidates its point masks."""
    return json.dumps([cfg["pos"], cfg.get("neg", []), cfg.get("threshold", 0.3),
                       hashlib.sha256(image.read_bytes()).hexdigest(), SAM_CKPT, POINT_MASK_REFINE])


def text_mask_key(image: Path, stage: str, prompt: str, threshold: float = TEXT_MASK_THRESHOLD,
                  refine: int = TEXT_MASK_REFINE, model: str = SAM_CKPT) -> str:
    """Stable key for a SAM text mask, tied to the exact composited input and all segmentation inputs."""
    payload = {
        "version": TEXT_MASK_CACHE_VERSION,
        "image_sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
        "stage": stage,
        "prompt": prompt,
        "model": model,
        "threshold": float(threshold),
        "refine": int(refine),
        "individual_masks": False,
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf8")).hexdigest()


def _read_text_mask_cache(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _write_text_mask_cache(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf8", dir=path.parent, prefix=path.name + ".", suffix=".tmp", delete=False) as handle:
        temp = Path(handle.name)
        json.dump(value, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")
    os.replace(temp, path)


def _text_mask_cache_entry(key: str, mask_path: Path) -> dict:
    return {"key": key, "mask_sha256": hashlib.sha256(mask_path.read_bytes()).hexdigest()}


def ensure_text_masks(image: Path, prompts: list[str], out_dir: Path, stage: str,
                      threshold: float = TEXT_MASK_THRESHOLD, refine: int = TEXT_MASK_REFINE) -> dict[str, Path]:
    """Reuse only masks whose exact image, stage, prompt, model and SAM settings still match."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / ".gdignore").touch(exist_ok=True)
    slugs = [slug(prompt) for prompt in prompts]
    if len(slugs) != len(set(slugs)):
        raise ValueError(f"SAM prompts collide after slugging for {stage}: {prompts}")
    cache_path = out_dir / TEXT_MASK_CACHE_NAME
    cache = _read_text_mask_cache(cache_path)
    keys = {prompt: text_mask_key(image, stage, prompt, threshold, refine) for prompt in prompts}
    with Image.open(image) as source_image:
        source_size = source_image.size
    missing = []
    for prompt, key in keys.items():
        mask_path = out_dir / f"{slug(prompt)}.png"
        entry = cache.get(slug(prompt))
        if not isinstance(entry, dict) or entry.get("key") != key or not mask_path.is_file():
            missing.append(prompt)
            cache.pop(slug(prompt), None)
        else:
            try:
                with Image.open(mask_path) as mask_image:
                    if mask_image.size != source_size or entry.get("mask_sha256") != hashlib.sha256(mask_path.read_bytes()).hexdigest():
                        missing.append(prompt)
                        cache.pop(slug(prompt), None)
            except (OSError, ValueError):
                missing.append(prompt)
                cache.pop(slug(prompt), None)
    if missing:
        # Keep the prior mask as evidence until all regenerated files validate.
        # Removing only its key ensures a failed SAM run cannot reuse stale pixels.
        _write_text_mask_cache(cache_path, cache)
        before_sha = hashlib.sha256(image.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="text-mask-", dir=out_dir) as temp_name:
            temp_dir = Path(temp_name)
            generated = segment(str(image), missing, str(temp_dir), threshold=threshold, refine=refine)
            after_sha = hashlib.sha256(image.read_bytes()).hexdigest()
            if before_sha != after_sha:
                raise RuntimeError(f"SAM input changed while segmenting {stage}; masks were not cached")
            staged = {}
            for prompt in missing:
                path = temp_dir / f"{slug(prompt)}.png"
                if prompt not in generated or not path.is_file():
                    raise RuntimeError(f"SAM did not write the {stage} mask for prompt {prompt!r}")
                try:
                    with Image.open(path) as mask_image:
                        mask_image.verify()
                    with Image.open(path) as mask_image:
                        if mask_image.size != source_size:
                            raise RuntimeError(f"SAM mask has wrong dimensions for {stage}/{prompt}: {mask_image.size}")
                except OSError as error:
                    raise RuntimeError(f"SAM wrote an invalid mask for {stage}/{prompt}: {path}") from error
                staged[prompt] = path
            for prompt, path in staged.items():
                os.replace(path, out_dir / f"{slug(prompt)}.png")
                cache[slug(prompt)] = _text_mask_cache_entry(keys[prompt], out_dir / f"{slug(prompt)}.png")
        _write_text_mask_cache(cache_path, cache)
    return {prompt: out_dir / f"{slug(prompt)}.png" for prompt in prompts}


def write_grey_composite(rgba: np.ndarray, destination: Path) -> None:
    """Deterministically rebuild the gray SAM reference from the current RGBA source."""
    height, width = rgba.shape[:2]
    background = Image.new("RGBA", (width, height), (128, 128, 128, 255))
    background.alpha_composite(Image.fromarray(rgba, "RGBA"))
    background.convert("RGB").save(destination)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--no-complete", action="store_true", help="skip Qwen: parts are just the visible pixels")
    ap.add_argument("--only", help="comma list of groups to (re)complete and export; preserve existing unrelated part PNGs")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--redo-stage", help="comma list of stage pictures to generate again")
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    only = {name.strip() for name in args.only.split(",")} if args.only is not None else None
    if only is not None and (not only or "" in only or not only <= spec["groups"].keys()):
        ap.error("--only requires nonempty group names from spec.groups")
    work = Path(args.work)
    rgba = np.array(Image.open(work / "base_rgba.png").convert("RGBA"))
    H, W = rgba.shape[:2]
    alpha = rgba[:, :, 3] > 127
    rgb = rgba[:, :, :3]

    # ---- SAM masks --------------------------------------------------------------------------------------------
    prompts = sorted({p for g in spec["groups"].values() for p in g["sam"]} | {p for g in spec["groups"].values() for p in g.get("minus", [])}
                     | set(spec.get("near_leg", {}).get("extra", []))
                     | {p for part in spec["parts"].values() for cap in part.get("caps", []) for p in cap.get("sam", [])})
    sam_dir = work / "sam"
    grey = work / "base_grey.png"
    write_grey_composite(rgba, grey)
    base_masks = ensure_text_masks(grey, prompts, sam_dir, "base")
    M = {p: (np.array(Image.open(base_masks[p]).convert("L").resize((W, H))) > 127) & alpha for p in prompts}
    point_masks = ensure_point_masks(grey, {name: g["points"] for name, g in spec["groups"].items() if "points" in g}, sam_dir)
    PM = {name: (np.array(Image.open(path).convert("L").resize((W, H))) > 127) & alpha for name, path in point_masks.items()}

    # ---- visible group masks (first group in spec order wins) -------------------------------------------------
    order = list(spec["groups"].keys())
    V: dict[str, np.ndarray] = {}
    taken = np.zeros((H, W), bool)
    for name in order:
        g = spec["groups"][name]
        m = np.zeros((H, W), bool)
        for p in g["sam"]:
            m |= M[p]
        if name in PM:
            m |= PM[name]
        if g.get("rest"):
            # Everything no earlier group took: the body of a figure whose limbs were picked by points. A mask stops a few pixels short of
            # its limb's ink outline; taken as "rest", those outlines hang off the body as stray thin lines (they go to the nearest group
            # below instead, i.e. back to their limb).
            m = alpha & ~dilate(taken, g.get("rest_gap", 6))
        if "outline" in g:
            reviewed = np.zeros((H, W), np.uint8)
            cv2.fillPoly(reviewed, [np.array(g["outline"], np.int32)], 1)
            m = (reviewed > 0) & alpha
        for p in g.get("minus", []):
            m &= ~M[p]
        if "y" in g:  # a group that SAM over-segments (a knee pad that swallows the whole shin) can be clipped to a pixel-row range
            yy_ = np.mgrid[0:H, 0:W][0]
            m &= (yy_ >= g["y"][0]) & (yy_ < g["y"][1])
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
        with Image.open(sp_) as stage_image:
            if stage_image.size != (W, H):
                raise ValueError(f"stage image size mismatch for {sp_}: expected {(W, H)}, got {stage_image.size}")
            stage_rgba[st["name"]] = np.array(stage_image.convert("RGBA"))
    stage_masks: dict[str, dict[str, np.ndarray]] = {}
    for sname, arr_ in stage_rgba.items():
        gimg = sdir / f"{sname}_grey.png"
        write_grey_composite(arr_, gimg)
        need = sorted({p for gname, g in spec["groups"].items() if g.get("complete", {}).get("stage") == sname for p in g["sam"]})
        have = ensure_text_masks(gimg, need, sdir / f"sam_{sname}", f"stage:{sname}")
        stage_masks[sname] = {p: (np.array(Image.open(have[p]).convert("L").resize((W, H))) > 127) & (arr_[:, :, 3] > 127) for p in need}

    # ---- completion of hidden groups --------------------------------------------------------------------------
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
            if c.get("check_removed"):
                # The stage picture must really have removed what was in front. A hand it left on the thigh ends up in the body part and
                # shows as a second hand as soon as the real hand moves away. Compare the stage with the original inside the box.
                x0, y0, x1, y1 = c["check_removed"]
                box = np.zeros((H, W), bool)
                box[max(y0, 0):y1, max(x0, 0):x1] = True
                watched = occ & box
                same = np.abs(stage_rgba[c["stage"]][:, :, :3].astype(int) - rgb.astype(int)).max(2) < 24
                share = float((watched & same).sum()) / max(int(watched.sum()), 1)
                if watched.sum() > 200 and share > c.get("check_removed_share", 0.4):
                    raise ValueError(f"stage {c['stage']} still shows {share:.0%} of what it should have removed inside {c['check_removed']} "
                                     f"(group {name}): change the stage prompt or seed and run again with --redo-stage {c['stage']}")
            sm = np.zeros((H, W), bool)
            for p_ in g["sam"]:
                sm |= stage_masks[c["stage"]][p_]
            others = np.zeros((H, W), bool)
            for other in order:
                if other != name and other not in c["occluders"]:
                    others |= V[other]
            # only fully opaque stage pixels, pulled in a few px from the stage picture's outer edge: Qwen's edit paints a pale
            # semi-transparent rim there that would show up as a halo around the completed part
            if c.get("mask_close"):  # the dark outline strokes between two masked regions belong to no SAM mask: close those cracks
                sm = cv2.morphologyEx(sm.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * c["mask_close"] + 1,) * 2)) > 0
            # Peeled underlayers may have a belt/waist SAM omits; the original occluders still bound the replacement.
            solid = (np.ones((H, W), bool) if c.get("stage_silhouette") else sm) & (stage_rgba[c["stage"]][:, :, 3] >= 250)
            solid = cv2.erode(solid.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * c.get("edge_trim", 3) + 1,) * 2)) > 0
            if "reject_hue" in c:  # colours the hidden part can not have (e.g. the pale blue wisp Qwen paints at the tip of the hair)
                hsv = cv2.cvtColor(stage_rgba[c["stage"]][:, :, :3], cv2.COLOR_RGB2HSV)
                hue = hsv[:, :, 0].astype(int) * 2
                bad = (hue >= c["reject_hue"][0]) & (hue <= c["reject_hue"][1]) & (hsv[:, :, 1] > 25)
                solid &= ~dilate(bad, 2)
            # trim: a ring of N px around the occluders is taken from the stage picture instead of the original, so the dark outline of the
            # arm (or whatever sits in front) does not stay behind on the part as a dotted line
            core = V[name] & ~dilate(occ, c["trim"]) if c.get("trim") else V[name]
            gap = solid & dilate(occ, c.get("gap_grow", 14)) & ~others & ~core & dilate(core, c.get("near", 120))
            final = largest_blobs(cv2.morphologyEx((core | gap).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)) > 0)
            color = np.where(core[:, :, None], rgb, stage_rgba[c["stage"]][:, :, :3])
            holes = ndimage.binary_fill_holes(final) & ~final  # enclosed gaps (a tool handle the SAM mask skipped): fill them from the stage picture
            if holes.any():
                st_ = stage_rgba[c["stage"]]
                color = np.where(holes[:, :, None], np.where((st_[:, :, 3] > 127)[:, :, None], st_[:, :, :3], rgb), color)
                final = final | holes
            if c.get("fill_behind"):
                # the stage picture still has the limb in front of the body (only armor was removed), so nothing was painted behind it:
                # fill the rows between the body pixels on both sides of the limb, and the holes the limb left, with a colour ramp
                hid = np.zeros((H, W), bool)
                for o in c["fill_behind"]:
                    hid |= V[o]
                hid = dilate(hid, c.get("fill_grow", 3)) & ~final
                if hid.any():
                    # bounded by the picture's own silhouette (the limb in front is inside it), on rows where the part has pixels at all:
                    # the old bound (first..last pixel of the row) left the part an L-shape when the arm covered one whole side of the hip
                    gap_fill = hid & alpha & final.any(1)[:, None]
                    gap_fill |= ndimage.binary_fill_holes(final | gap_fill) & ~final
                    color = row_fill(color, gap_fill, final)
                    final = final | gap_fill
            if c.get("keep_rim"):
                # trim took a ring of the group's own pixels away and the stage picture gives back only its opaque inside: along the stage's
                # soft outer edge nothing came back, and the part's outline had 1 px breaks wherever it used to touch the thing in front
                # Their colour comes from the stage picture where it has any (its soft edge is still the right material), else from the
                # nearest pixel already kept: the original pixel there is a blend with the thing that was in front (white hair on a navy sleeve).
                lost = V[name] & ~final
                if lost.any() and final.any():
                    st_ = stage_rgba[c["stage"]]
                    idx = ndimage.distance_transform_edt(~final, return_distances=False, return_indices=True)
                    near_color = color[idx[0], idx[1]]
                    color = np.where(lost[:, :, None], np.where((st_[:, :, 3] > 127)[:, :, None], st_[:, :, :3], near_color), color)
                    final = final | lost
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

    # ---- the near leg as a group of its own (NE-152) ----------------------------------------------------------
    if "near_leg" in spec:
        nl_cfg = spec["near_leg"]
        leg_stage = nl_cfg.get("stage")
        leg_sam_dir = sdir / f"sam_{leg_stage}" if leg_stage else sam_dir
        leg_image = sdir / f"{leg_stage}_grey.png" if leg_stage else grey
        leg_alpha = stage_rgba[leg_stage][:, :, 3] > 127 if leg_stage else alpha
        mask_png = leg_sam_dir / "near_leg.png"
        key_json = leg_sam_dir / "near_leg.json"
        key = near_leg_key(nl_cfg, leg_image)
        if not mask_png.exists() or not key_json.exists() or key_json.read_text(encoding="utf8") != key:
            print("SAM 3.1 near_leg:", nl_cfg["pos"], nl_cfg.get("neg", []))
            segment_points(str(leg_image), str(leg_sam_dir), {"near_leg": {"pos": [tuple(q) for q in nl_cfg["pos"]], "neg": [tuple(q) for q in nl_cfg.get("neg", [])]}},
                           threshold=nl_cfg.get("threshold", 0.3), refine=POINT_MASK_REFINE)
            key_json.write_text(key, encoding="utf8")
        near = (np.array(Image.open(mask_png).convert("L").resize((W, H))) > 127) & leg_alpha
        far = np.zeros((H, W), bool)
        if nl_cfg.get("neg"):  # the far leg's own mask: the same SAM call with the point lists swapped; nothing of it may end up in the near leg
            far_png, far_json = leg_sam_dir / "near_leg_far.png", leg_sam_dir / "near_leg_far.json"
            if not far_png.exists() or not far_json.exists() or far_json.read_text(encoding="utf8") != key:
                segment_points(str(leg_image), str(leg_sam_dir), {"near_leg_far": {"pos": [tuple(q) for q in nl_cfg["neg"]], "neg": [tuple(q) for q in nl_cfg["pos"]]}},
                               threshold=nl_cfg.get("threshold", 0.3), refine=POINT_MASK_REFINE)
                far_json.write_text(key, encoding="utf8")
            far = (np.array(Image.open(far_png).convert("L").resize((W, H))) > 127) & ~near
        if leg_stage and nl_cfg.get("stage_until"):
            # Preserve the original lower limb: the peeled edit is only needed above this joint.
            cut = int(spec["joints"][nl_cfg["stage_until"]][1])
            if nl_cfg.get("lower_outline"):
                original = np.zeros((H, W), np.uint8)
                cv2.fillPoly(original, [np.array(nl_cfg["lower_outline"], np.int32)], 1)
                lower_alpha = (complete["body"][:, :, 3] > 127) | (complete.get("boot", rgba)[:, :, 3] > 127)
                original = original.astype(bool) & lower_alpha
                original_far = lower_alpha & ~original
            else:
                original = np.array(Image.open(sam_dir / "near_leg.png").convert("L").resize((W, H))) > 127
                original_far = np.array(Image.open(sam_dir / "near_leg_far.png").convert("L").resize((W, H))) > 127
            near[cut:] = original[cut:]
            far[cut:] = original_far[cut:] & ~near[cut:]
            leg_alpha[cut:] = (original | original_far)[cut:]
        yy_leg = np.mgrid[0:H, 0:W][0]
        occ_leg = np.zeros((H, W), bool)
        for g_ in nl_cfg.get("fill", []):
            occ_leg |= V[g_]
        for i_, cv_ in enumerate(nl_cfg.get("cover", [])):  # things in front of the leg that no group claims (a hand SAM took for the body)
            cpng, cjson = leg_sam_dir / f"near_leg_cover{i_}.png", leg_sam_dir / f"near_leg_cover{i_}.json"
            ckey = near_leg_key({**cv_, "threshold": nl_cfg.get("threshold", 0.3)}, leg_image)
            if not cpng.exists() or not cjson.exists() or cjson.read_text(encoding="utf8") != ckey:
                segment_points(str(leg_image), str(leg_sam_dir), {f"near_leg_cover{i_}": {"pos": [tuple(q) for q in cv_["pos"]], "neg": [tuple(q) for q in cv_.get("neg", [])]}},
                               threshold=nl_cfg.get("threshold", 0.3), refine=POINT_MASK_REFINE)
                cjson.write_text(ckey, encoding="utf8")
            occ_leg |= np.array(Image.open(cpng).convert("L").resize((W, H))) > 127
        occ_leg = dilate(occ_leg, nl_cfg.get("fill_grow", 3))
        k_ = nl_cfg.get("close", 9)
        # closing fills what hangs in front of the leg and cuts a notch into its outline (a hand beside the thigh); it stays inside the picture's
        # silhouette and out of the far leg
        region = (cv2.morphologyEx(near.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k_ + 1,) * 2)) > 0) & leg_alpha & ~far
        for prompt in nl_cfg.get("extra", []):
            region |= M[prompt] & ~occ_leg
        # a hand or forearm that hangs in front of the thigh is inside the leg's silhouette: the leg sprite has to cover it, because the
        # arm sprite moves away when the character aims or runs
        hip_y = int(spec["joints"]["hip"][1])
        # ... but only inside the leg's own width: a forearm guard that sticks out in front of the thigh would otherwise grow a slab on it
        rows = region.any(1) & (np.arange(H) >= hip_y)  # (region here already holds the closed leg and its extra garments, so an apron widens it)
        left_edge = np.where(rows, region.argmax(1), 0).astype(float)
        right_edge = np.where(rows, W - 1 - region[:, ::-1].argmax(1), 0).astype(float)
        ys_ok = np.nonzero(rows)[0]
        if len(ys_ok) > 1:
            left_edge = ndimage.median_filter(np.interp(np.arange(H), ys_ok, left_edge[ys_ok]), 41)
            right_edge = ndimage.median_filter(np.interp(np.arange(H), ys_ok, right_edge[ys_ok]), 41)
            inside = (np.arange(W)[None, :] >= left_edge[:, None] - 6) & (np.arange(W)[None, :] <= right_edge[:, None] + 6)
        else:
            inside = np.ones((H, W), bool)
        for g_ in (("hand", "arm", "armor_forearm", "armor_shoulder", "armor_knee", "armor_chest") if nl_cfg.get("cover_limbs", True) else ()):
            if g_ in V:
                region |= V[g_] & (yy_leg >= hip_y) & dilate(region, 40) & ~far & inside
        if nl_cfg.get("thigh_x") and not leg_stage:  # a thigh the SAM points did not reach (one big armoured mass where both thighs overlap): take the body pixels of the
            # rows between hip and knee that lie inside this x range, the far thigh peeks out beyond it
            x0_, x1_ = nl_cfg["thigh_x"]
            knee_y = int(spec["joints"]["knee"][1])
            rows_ = (yy_leg >= int(spec["joints"]["hip"][1])) & (yy_leg <= knee_y)
            region |= leg_alpha & rows_ & (np.arange(W)[None, :] >= x0_) & (np.arange(W)[None, :] <= x1_) & ~far
        if nl_cfg.get("close_thigh"):  # a wide closing between hip and knee fills the bite a hand or a pocket took out of the thigh's front
            k2 = nl_cfg["close_thigh"]
            wide = cv2.morphologyEx(region.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k2 + 1,) * 2)) > 0
            region |= wide & leg_alpha & ~far & (yy_leg >= int(spec["joints"]["hip"][1])) & (yy_leg <= int(spec["joints"]["knee"][1]))
        for g_ in nl_cfg.get("exclude", []):  # plates that the SAM mask took in but that ride another bone (a hip plate on the chest): the leg keeps no copy
            region &= ~V[g_]
        region = ndimage.binary_fill_holes(region)
        region = largest_blobs(region, 0.05)
        if nl_cfg.get("grow"):  # take the outline and the rim light the mask leaves out (a violet glow along the trouser leg), but not the far leg's
            region = dilate(region, nl_cfg["grow"]) & leg_alpha & ~far
        body_c, boot_c = complete["body"], complete.get("boot")
        if nl_cfg.get("root_overlap"):
            region |= (body_c[:, :, 3] > 127) & (abs(yy_leg - hip_y) <= nl_cfg["root_overlap"])
        have_body = body_c[:, :, 3] > 127
        have_boot = (boot_c[:, :, 3] > 127) if boot_c is not None else np.zeros((H, W), bool)
        # colours come from the body and boot groups (they hold the picture plus what the peeled stage painted behind an arm or a knee pad);
        # only what those do not cover, or what spec.near_leg.fill lists, is painted again
        known = (have_body | have_boot) & ~occ_leg & region
        color = np.where(have_body[:, :, None], body_c[:, :, :3], np.where(have_boot[:, :, None], boot_c[:, :, :3] if boot_c is not None else rgb, rgb))
        unknown = region & ~known
        if unknown.any():
            color = row_fill(color, unknown, known)
        complete["near_leg"] = np.dstack([color, (region * 255).astype(np.uint8)])
        V["near_leg"] = region
        Image.fromarray(complete["near_leg"]).save(gdir / "near_leg.png")

    # ---- cut groups into parts --------------------------------------------------------------------------------
    yy, xx = np.mgrid[0:H, 0:W]
    seam = spec.get("seam", 10)
    parts: dict[str, np.ndarray] = {}
    straight: dict[str, np.ndarray] = {}  # the part before its round joint caps were added
    for pname, pdef in spec["parts"].items():
        if "damage_of" in pdef:
            continue  # torn-clothes layers are made by make_damage.py
        grp = complete[pdef["group"]]
        region = grp[:, :, 3] > 127
        if "minus_group" in pdef:
            region &= ~(complete[pdef["minus_group"]][:, :, 3] > 127)
        if "y" in pdef:
            lo, hi = pdef["y"]
            if pdef.get("mode") == "bone":
                # Cut perpendicular to the bone, not along an image row: the limb is turned upright when it is cut into a texture, and a
                # slanted cut edge there would be lit like a silhouette (a bright tick across the hip).
                a_, b_ = np.array(spec["joints"][pdef["from"]], float), np.array(spec["joints"][pdef["to"]], float)
                d_ = (b_ - a_) / np.linalg.norm(b_ - a_)
                s_ = (xx - a_[0]) * d_[0] + (yy - a_[1]) * d_[1]
                region &= (s_ >= (lo - a_[1]) / d_[1] if lo > 0 else True) & (s_ < (hi - a_[1]) / d_[1] if hi < H else True)
            else:
                region &= (yy >= lo) & (yy < hi)
        straight[pname] = region
        # caps: a rigid joint (hip, shoulder, wrist, ankle, neck) turns without showing a corner or a gap only when both parts keep a round
        # disc of the group around the joint they turn on; a straight cut alone leaves an angular silhouette as soon as the limb swings.
        for cap in pdef.get("caps", []):
            disc = (grp[:, :, 3] > 127) & (cap_distance((H, W), spec["joints"][cap["joint"]]) <= cap["radius"])
            if "sam" in cap:  # only this material: a thigh's cap must not carry a sliver of the bodysuit around with it
                wanted = np.zeros((H, W), bool)
                for prompt in cap["sam"]:
                    wanted |= M[prompt]
                disc &= dilate(wanted, 2)
            region = region | disc
        if "within" in pdef:  # keep the pixels of this group that fall inside another group's visible mask (e.g. the hand inside the arm group)
            region &= dilate(V[pdef["within"]], pdef.get("within_grow", 3))
        if "not_within" in pdef:
            region &= ~dilate(V[pdef["not_within"]], pdef.get("within_grow", 3))
        if "blob" in pdef:  # "main" = the largest connected piece of the region, "rest" = every other piece (e.g. a collar floating beside the neck)
            n_, lab_, st_, _ = cv2.connectedComponentsWithStats(region.astype(np.uint8), connectivity=8)
            main_ = lab_ == (1 + int(np.argmax(st_[1:, cv2.CC_STAT_AREA]))) if n_ > 1 else region
            region = main_ if pdef["blob"] == "main" else region & ~main_
        parts[pname] = region
    # each part also gets `seam` px of its neighbours inside the same group, so joints can turn without cracks
    for pname, pdef in spec["parts"].items():
        if "damage_of" in pdef:
            continue
        grp = complete[pdef["group"]]
        region = parts[pname]
        dependencies = {pdef["group"]} | {pdef[key] for key in ("minus_group", "within", "not_within") if key in pdef}
        dependencies.update(rule["group"] for rule in pdef.get("joint_overlap", []))
        if "near_leg" in dependencies:
            dependencies.update(spec["groups"])
        target = pdir / f"{pname}.png"
        if only is not None and dependencies.isdisjoint(only) and target.exists():
            parts[pname] = np.array(Image.open(target).convert("RGBA"))[:, :, 3] > 127
            continue
        grown = dilate(region, 2 if "blob" in pdef else pdef.get("seam", seam)) & (grp[:, :, 3] > 127)
        if "minus_group" in pdef:
            grown &= ~(complete[pdef["minus_group"]][:, :, 3] > 127)
        grown = largest_blobs(grown)
        layer = grp.copy()
        layer[:, :, 3] = (grown * 255).astype(np.uint8)
        if pdef.get("caps"):
            part_seam = pdef.get("seam", seam)
            layer[:, :, 3] = cap_alpha(layer[:, :, 3], dilate(straight[pname], part_seam) & grown,
                                       [(cap_distance((H, W), spec["joints"][cap["joint"]]), cap["radius"] + part_seam, cap.get("feather", 0))
                                        for cap in pdef["caps"]])
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
