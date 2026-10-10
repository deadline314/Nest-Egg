"""Turn the full-canvas part layers from make_parts.py into game textures, a rig and a character definition.

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/cut_layers.py --spec tools/comfyui/specs/rin_side.json --work art_src/characters/rin2 \
        --char art/characters/rin --rig art/rigs/humanoid_tall.json

Inputs : <work>/07_refined/<part>.png (else 06_parts/)   full-canvas RGBA per part (same pixel coordinates as base_rgba.png)
         spec: joints, bones, parts (from / to / mode / pivot / uses), glow
Outputs: <char>/parts/<part>.png (+ _glow.png)  each part rotated so its bone points down, cropped, pivot at its joint
         <char>/character.json                  textures (size, pivot) + parts (texture, bone, z, tint)
         <rig>                                  bone rest positions measured from the picture
To replace a texture by hand: paint a PNG with the SAME size and pivot and overwrite <char>/parts/<part>.png (or put it in
<work>/overrides/ - build_character.py copies those over after every run).
"""
import argparse
import hashlib
import json
import math
import os
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

from cut_rig_parts import frame, glow_layer

PAD = 3
NOTE = "由 tools/comfyui/cut_layers.py 依分件圖層切出"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_eye_state_sources(config: dict, source_path: Path, expected_canvas: tuple[int, int] | None = None) -> tuple[Image.Image, dict[str, Image.Image]]:
    """Validate full-canvas source variants before cut output can be replaced."""
    if not isinstance(config, dict) or config.get("part") != "head":
        raise ValueError("spec.eye_states.part must be 'head'")
    sources = config.get("sources")
    if not isinstance(sources, dict) or not isinstance(sources.get("original_head"), dict):
        raise ValueError("spec.eye_states.sources.original_head is required")
    original_meta = sources["original_head"]
    for key in ("path", "sha256"):
        if not isinstance(original_meta.get(key), str) or not original_meta[key]:
            raise ValueError(f"spec.eye_states.sources.original_head.{key} is required")
    original_resolved = Path(original_meta["path"]).resolve()
    if original_resolved != source_path.resolve():
        raise ValueError(f"eye-state original_head path differs from the selected head source: {original_resolved} != {source_path.resolve()}")
    if sha256(original_resolved) != original_meta["sha256"]:
        raise ValueError(f"eye-state original_head hash mismatch: {original_resolved}")
    with Image.open(original_resolved) as image:
        if image.mode != "RGBA":
            raise ValueError(f"eye-state original head must be RGBA: {original_resolved} got {image.mode}")
        original = image.copy()
    if expected_canvas and original.size != expected_canvas:
        raise ValueError(f"eye-state original head canvas mismatch: expected {expected_canvas}, got {original.size}")

    polygon = config.get("eye_mask")
    if not isinstance(polygon, list) or len(polygon) < 3:
        raise ValueError("spec.eye_states.eye_mask must contain at least three native-coordinate points")
    points: list[tuple[int, int]] = []
    for point in polygon:
        if not isinstance(point, list) or len(point) != 2:
            raise ValueError("spec.eye_states.eye_mask points must be [x, y]")
        x, y = point
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or not math.isfinite(x) or not math.isfinite(y):
            raise ValueError("spec.eye_states.eye_mask contains a non-finite point")
        if not (0 <= x < original.width and 0 <= y < original.height):
            raise ValueError(f"spec.eye_states.eye_mask point is outside {original.size}: {point}")
        points.append((round(x), round(y)))
    mask = Image.new("L", original.size, 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mp = np.array(mask) > 0
    if not mp.any():
        raise ValueError("spec.eye_states.eye_mask is empty")

    states: dict[str, Image.Image] = {}
    for state in ("half", "closed"):
        meta = sources.get(state)
        if not isinstance(meta, dict) or not isinstance(meta.get("path"), str) or not isinstance(meta.get("sha256"), str):
            raise ValueError(f"spec.eye_states.sources.{state} requires path and sha256")
        path = Path(meta["path"]).resolve()
        if not path.is_file():
            raise ValueError(f"missing eye-state source: {path}")
        actual_hash = sha256(path)
        if actual_hash != meta["sha256"]:
            raise ValueError(f"eye-state source hash mismatch for {state}: expected {meta['sha256']}, got {actual_hash}")
        with Image.open(path) as image:
            if image.mode != "RGBA" or image.size != original.size:
                raise ValueError(f"eye-state {state} must be native RGBA {original.size}: {path} got {image.mode} {image.size}")
            candidate = image.copy()
        source_pixels = np.array(original)
        candidate_pixels = np.array(candidate)
        if not np.array_equal(source_pixels[:, :, 3], candidate_pixels[:, :, 3]):
            raise ValueError(f"eye-state {state} changed source alpha: {path}")
        if not np.array_equal(source_pixels[~mp], candidate_pixels[~mp]):
            raise ValueError(f"eye-state {state} changed pixels outside eye_mask: {path}")
        states[state] = candidate
    return original, states


def _resized_premultiplied(source: Image.Image, k: float) -> tuple[np.ndarray, np.ndarray]:
    arr = np.array(source.convert("RGBA")).astype(np.float32)
    pm = arr.copy()
    pm[:, :, :3] *= pm[:, :, 3:4] / 255.0
    pm = cv2.resize(pm, None, fx=k, fy=k, interpolation=cv2.INTER_AREA)
    arr = pm.copy()
    arr[:, :, :3] = pm[:, :, :3] / np.maximum(pm[:, :, 3:4] / 255.0, 1e-3)
    a = arr[:, :, 3]
    prem = arr[:, :, :3] * (a[:, :, None] / 255.0)
    return prem, a


def part_transform(source: Image.Image, part: dict, joints: dict[str, np.ndarray], k: float) -> tuple[np.ndarray, int, int, np.ndarray] | None:
    """Compute the exact source-to-part transform used by the cut loop."""
    _, a = _resized_premultiplied(source, k)
    ys, xs = np.nonzero(a > 20)
    if len(ys) == 0:
        return None
    a_pt, b_pt = joints[part["from"]], joints[part["to"]]
    pivot_pt = joints[part.get("pivot", part["from"])]
    ex, ey = frame(part["mode"], a_pt, b_pt)
    rel = np.stack([xs, ys], 1) - pivot_pt
    u, v = rel @ ex, rel @ ey
    lo, hi = part.get("y", (0, source.height))
    pad_top, pad_bottom = (0 if lo > 0 else PAD), (1 if hi < source.height else PAD)
    umin, umax, vmin, vmax = u.min() - PAD, u.max() + PAD, v.min() - pad_top, v.max() + pad_bottom
    cw, ch = int(math.ceil(umax - umin)), int(math.ceil(vmax - vmin))
    piv = np.array([-umin, -vmin])
    A = np.float32([[ex[0], ey[0], pivot_pt[0] - piv[0] * ex[0] - piv[1] * ey[0]],
                    [ex[1], ey[1], pivot_pt[1] - piv[0] * ex[1] - piv[1] * ey[1]]])
    return A, cw, ch, piv


def render_part(source: Image.Image, transform: tuple[np.ndarray, int, int, np.ndarray], k: float) -> np.ndarray:
    """Run the same INTER_AREA resize and premultiplied CUBIC affine warp as cut_layers."""
    A, cw, ch, _ = transform
    prem, a = _resized_premultiplied(source, k)
    flags = cv2.INTER_CUBIC | cv2.WARP_INVERSE_MAP
    wa = np.clip(cv2.warpAffine(a, A, (cw, ch), flags=flags), 0, 255)
    wc = cv2.warpAffine(prem, A, (cw, ch), flags=flags)
    col = np.clip(wc / np.maximum(wa[:, :, None] / 255.0, 1e-3), 0, 255)
    col[wa < 4] = 0
    return np.dstack([col, wa]).astype(np.uint8)


def make_normal_map(rgba: np.ndarray) -> np.ndarray:
    """CPU port of NormalMapMaker.make(source, 2, 3.0, 1.4)."""
    rgb = rgba[:, :, :3].astype(np.float32) / 255.0
    alpha = rgba[:, :, 3].astype(np.float32) / 255.0
    luma = (rgb[:, :, 0] * 0.2126 + rgb[:, :, 1] * 0.7152 + rgb[:, :, 2] * 0.0722) * alpha
    blurred = cv2.boxFilter(alpha, cv2.CV_32F, (5, 5), normalize=True, borderType=cv2.BORDER_REPLICATE)
    height = blurred * 3.0 + luma * 1.4
    dx = np.pad(height, ((0, 0), (1, 1)), mode="edge")[:, 2:] - np.pad(height, ((0, 0), (1, 1)), mode="edge")[:, :-2]
    dy = np.pad(height, ((1, 1), (0, 0)), mode="edge")[2:, :] - np.pad(height, ((1, 1), (0, 0)), mode="edge")[:-2, :]
    vector = np.stack((-dx, dy, np.full_like(dx, 2.0)), axis=2)
    vector /= np.linalg.norm(vector, axis=2, keepdims=True)
    normal = np.empty_like(rgba)
    normal[:, :, :3] = np.clip(np.rint((vector * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)
    normal[:, :, 3] = rgba[:, :, 3]
    return normal


def load_native_grips(spec: dict, root: Path) -> dict:
    """Keep registered hand edits at their own density instead of resampling the source."""
    grips = spec.get("native_grips", {})
    if not isinstance(grips, dict):
        raise ValueError("spec.native_grips must be an object")
    referenced = {u.get("grip_texture") for p in spec["parts"].values() for u in p.get("uses", [])}
    result = {}
    for name, config in grips.items():
        if name not in referenced or not isinstance(config, dict):
            raise ValueError(f"spec.native_grips.{name}: requires a referenced gripping attachment")
        if not isinstance(config.get("source"), str):
            raise ValueError(f"spec.native_grips.{name}: source must be a registered path")
        source = (root / config["source"]).resolve()
        scale, pivot = config.get("texture_scale"), config.get("pivot")
        if (not source.is_relative_to(root / "art_src/characters") or not source.is_file()
                or type(scale) not in (int, float) or not math.isfinite(scale) or scale <= 0
                or not isinstance(pivot, list) or len(pivot) != 2
                or any(type(v) not in (int, float) or not math.isfinite(v) for v in pivot)):
            raise ValueError(f"spec.native_grips.{name}: invalid source, density or pivot")
        data = source.read_bytes()
        with Image.open(source) as image:
            if (image.mode != "RGBA" or list(image.size) != config.get("size")
                    or hashlib.sha256(data).hexdigest() != config.get("sha256")):
                raise ValueError(f"spec.native_grips.{name}: source hash, RGBA or size differs")
        result[name] = (data, {"file": f"parts/{name}.png", "size": config["size"],
                              "pivot": pivot, "texture_scale": scale, "note": "原生握持部件；來源與重建見 spec.native_grips"})
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--char", required=True)
    ap.add_argument("--rig", required=True)
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    native_grips = load_native_grips(spec, Path(__file__).resolve().parents[2])
    work = Path(args.work)
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    px_wp = spec["tex_px_per_wp"]
    J = {n: np.array(p, float) * k for n, p in spec["joints"].items()}
    src_dir = work / "07_refined" if (work / "07_refined").exists() else work / "06_parts"  # refine_parts.py output wins
    source_overrides = work / "overrides/refined"
    overrides = {path.stem: path for path in source_overrides.glob("*.png")}
    if overrides:
        canvas = Image.open(work / "base_rgba.png").size
        for name, path in overrides.items():
            with Image.open(path) as image:
                if name not in spec["parts"] or image.mode != "RGBA" or image.size != canvas:
                    raise ValueError(f"{path}: source override requires a known part and full-canvas RGBA of size {canvas}")
    eye_config = spec.get("eye_states")
    eye_sources = None
    eye_source_path = None
    if eye_config is not None:
        if "head" not in spec["parts"]:
            raise ValueError("spec.eye_states requires spec.parts.head")
        eye_source_path = overrides.get("head", src_dir / "head.png")
        eye_sources = validate_eye_state_sources(eye_config, eye_source_path)
    final_parts = Path(args.char) / "parts"
    out_parts = Path(args.char) / "parts.tmp"  # written here first; swapped in only when every part was cut (a failed run keeps the old textures)
    if out_parts.exists():
        shutil.rmtree(out_parts)
    out_parts.mkdir(parents=True, exist_ok=True)
    (out_parts / ".gdignore").touch()  # a leftover temp folder must not be imported by the engine

    textures, transforms = {}, {}
    for name, p in spec["parts"].items():
        source_path = overrides.get(name, src_dir / f"{name}.png")
        with Image.open(source_path) as image:
            src = image.convert("RGBA")
        transform = part_transform(src, p, J, k)
        if transform is None:
            print("WARN empty part", name)
            continue
        A, cw, ch, piv = transform
        rgba = render_part(src, transform, k)
        Image.fromarray(rgba).save(out_parts / f"{name}.png")
        entry = {"file": f"parts/{name}.png", "size": [cw, ch], "pivot": [round(float(piv[0]), 2), round(float(piv[1]), 2)], "note": NOTE}
        kind = spec["glow"].get(name)
        if kind:
            thr = spec.get("glow_threshold", {})
            g = glow_layer(rgba[:, :, :3], rgba[:, :, 3], kind, thr.get("sat", 140), thr.get("val", 190))
            if g is None:  # nothing glows on this part: no glow layer at all (an all-transparent one only costs a texture and a draw)
                print(f"  WARN {name}: no '{kind}' glow pixels found, no glow layer written (lower spec.glow_threshold, or drop it from spec.glow)")
            else:
                Image.fromarray(g).save(out_parts / f"{name}_glow.png")
                entry["glow"] = f"parts/{name}_glow.png"
        textures[name] = entry
        transforms[name] = (A, cw, ch)
        print(f"  {name}: {cw}x{ch} pivot=({piv[0]:.1f},{piv[1]:.1f})")

    eye_runtime = None
    if eye_sources is not None and eye_config is not None:
        part_name = eye_config["part"]
        if part_name not in transforms or part_name not in textures:
            raise ValueError(f"spec.eye_states part has no rendered texture: {part_name}")
        head_texture = textures[part_name]
        state_names = {"half": eye_config.get("half_texture", "head_half"),
                       "closed": eye_config.get("closed_texture", "head_closed")}
        if any(not isinstance(name, str) or not name or "/" in name or "\\" in name for name in state_names.values()):
            raise ValueError("spec.eye_states texture names must be nonempty filenames")
        if len(set(state_names.values())) != 2 or any(name in textures for name in state_names.values()):
            raise ValueError("spec.eye_states texture names must be unique and not collide with existing textures")
        _, state_images = eye_sources
        for state, texture_name in state_names.items():
            rgba = render_part(state_images[state], transforms[part_name] + (np.array(head_texture["pivot"], dtype=float),), k)
            Image.fromarray(rgba).save(out_parts / f"{texture_name}.png")
            entry = {"file": f"parts/{texture_name}.png", "size": list(rgba.shape[1::-1]),
                     "pivot": list(head_texture["pivot"]), "note": NOTE}
            kind = spec.get("glow", {}).get(part_name)
            if kind:
                threshold = spec.get("glow_threshold", {})
                glow = glow_layer(rgba[:, :, :3], rgba[:, :, 3], kind,
                                  threshold.get("sat", 140), threshold.get("val", 190))
                if glow is not None:
                    glow_name = f"{texture_name}_glow"
                    Image.fromarray(glow).save(out_parts / f"{glow_name}.png")
                    entry["glow"] = f"parts/{glow_name}.png"
            textures[texture_name] = entry
        timing = eye_config.get("timing", {})
        if not isinstance(timing, dict):
            raise ValueError("spec.eye_states.timing must be an object")
        eye_runtime = {"part": part_name, "half_texture": state_names["half"],
                       "closed_texture": state_names["closed"], "timing": timing}

    # ---- carried-over textures (e.g. a riot shield drawn earlier): <dir>/<name>.png (+_glow.png) and <name>.json {size, pivot, factor, use} --------
    extra_uses: list[dict] = []
    for item in spec.get("carry_over", []):
        src_dir_c = Path(item["dir"])
        meta = json.loads((src_dir_c / f"{item['name']}.json").read_text(encoding="utf8"))
        f = meta.get("factor", 1)
        for suffix in ("", "_glow"):
            src_png = src_dir_c / f"{item['name']}{suffix}.png"
            if src_png.exists():
                im = Image.open(src_png).convert("RGBA")
                im.resize((im.width * f, im.height * f), Image.LANCZOS).save(out_parts / f"{item['name']}{suffix}.png")
        entry = {"file": f"parts/{item['name']}.png", "size": [meta["size"][0] * f, meta["size"][1] * f], "pivot": [meta["pivot"][0] * f, meta["pivot"][1] * f], "note": NOTE}
        if (src_dir_c / f"{item['name']}_glow.png").exists():
            entry["glow"] = f"parts/{item['name']}_glow.png"
        textures[item["name"]] = entry
        extra_uses.append(dict(meta["use"], texture=item["name"]))

    # ---- rig -----------------------------------------------------------------------------------------------------
    ground = spec["ground_y"] * k
    by_name = {b["name"]: b for b in spec["bones"]}

    def joint_of(bone: str) -> np.ndarray:
        b = by_name[bone]
        if bone == "hip":
            return J["hip"]
        if "at" in b:
            return J[b["at"]]
        return J[by_name[b["parent"]]["tip"]]

    bones = []
    for b in spec["bones"]:
        name, parent = b["name"], b["parent"]
        if name == "hip":
            pos = [0.0, -round((ground - J["hip"][1]) / px_wp, 2)]
        elif "fixed" in b:
            pos = b["fixed"]
        elif "at" in b:
            d = (J[b["at"]] - joint_of(parent)) / px_wp
            pos = [round(float(d[0]) + b.get("dx", 0.0), 2), round(float(d[1]), 2)]
        else:
            pb = by_name[parent]
            pos = [0.0, round(float(np.linalg.norm(J[pb["tip"]] - joint_of(parent))) / px_wp, 2)]
        bones.append({"name": name, "parent": parent, "pos": pos})
    ac = spec["weapon_anchor"]
    anchor = (J[ac["to"]] - J[ac["from"]]) / px_wp
    rig = {"id": Path(args.rig).stem,
           "description": "人形骨架（7.5 頭身版）。座標單位為世界像素，原點在腳底，面向右（+X），Y 軸向下；骨頭靜止時沿 +Y 延伸。長度由立繪量出（" + NOTE + "）。",
           "bones": bones,
           **({"springs": spec["springs"]} if "springs" in spec else {}),
           "weapon_anchor": {"bone": ac["bone"], "pos": [round(float(anchor[0]) + ac["dx"], 2), round(float(anchor[1]) + ac["dy"], 2)], "reach": ac["reach"]}}
    rig_text = json.dumps(rig, ensure_ascii=False, indent=2) + "\n"

    # ---- character -----------------------------------------------------------------------------------------------
    uses = []
    for name, p in spec["parts"].items():
        if name in textures:
            uses += [dict(u, texture=name) for u in p["uses"]]
    uses += extra_uses
    uses.sort(key=lambda e: e["z"])
    char = {"id": spec["id"], "display_name": spec["display_name"], "rig": "res://art/rigs/" + Path(args.rig).name,
            "texture_scale": round(1.0 / px_wp, 5), "scale": spec["scale"]}
    if "armor_debris" in spec:
        char["armor_debris"] = spec["armor_debris"]
    blink = spec.get("blink")
    if blink and blink["part"] in transforms:
        A, cw, ch = transforms[blink["part"]]
        inv = cv2.invertAffineTransform(A)

        def to_canvas(pt: list) -> list:
            q = inv @ np.array([pt[0] * k, pt[1] * k, 1.0])
            return [round(float(q[0]), 1), round(float(q[1]), 1)]
        char["portrait"] = {"description": "背包立繪的眨眼設定（頭部貼圖像素座標）：part＝頭部零件名稱；eye＝要被抹成膚色的眼睛範圍（四邊形）；lid＝閉眼時畫上的眼線。",
                            "blink": {"part": blink["part"], "eye": sum((to_canvas(q) for q in blink["eye"]), []), "lid": sum((to_canvas(q) for q in blink["lid"]), [])}}
    if eye_runtime is not None:
        char["eye_states"] = eye_runtime
    char["description"] = "外觀（skin）定義：textures 是零件圖片的尺寸與支點；parts 是把圖片掛到骨頭上的方式。" + NOTE + "。"
    char["textures"] = textures
    char["parts"] = [{"name": u["name"], "texture": u["texture"], "bone": u["bone"], "z": u["z"], **({"tint": u["tint"]} if "tint" in u else {}), **({"armor_order": u["armor_order"]} if "armor_order" in u else {}), **({"under": True} if u.get("under") else {}), **({"offset": u["offset"]} if "offset" in u else {}), **({"root_attach": True} if u.get("root_attach") else {}), **({"bend_partner": u["bend_partner"]} if "bend_partner" in u else {})} for u in uses]
    for entry, use in zip(char["parts"], uses):
        if "grip_texture" not in use:
            continue
        name = use["grip_texture"]
        inverse = cv2.invertAffineTransform(transforms[name][0])
        grasp = inverse @ np.array([*np.array(spec["parts"][name]["grasp"]) * k, 1.0])
        offset = (grasp - np.array(textures[name]["pivot"])) / px_wp
        entry.update(grip_texture=name, grip_offset=[round(float(v), 5) for v in offset])
    for name, (data, definition) in native_grips.items():
        (out_parts / f"{name}.png").write_bytes(data)
        textures[name] = definition
    # swap in the new files only now that everything above worked
    for path in (work / "overrides").glob("*.png"):
        target = out_parts / path.name
        if not target.exists() or Image.open(path).mode != "RGBA" or Image.open(path).size != Image.open(target).size:
            raise ValueError(f"{path}: final override requires an existing part and RGBA PNG of the same size")
    (out_parts / ".gdignore").unlink()
    if final_parts.exists():
        for imp in final_parts.glob("*.import"):  # keep the engine's import records (and their uids) of textures that still exist
            png = imp.name[: -len(".import")]
            base = png[: -len("_n.png")] + ".png" if png.endswith("_n.png") else png  # the normal maps are made again by the next step
            if (out_parts / base).exists():
                shutil.copy(imp, out_parts / imp.name)
        shutil.rmtree(final_parts)
    os.replace(out_parts, final_parts)
    Path(args.rig).write_text(rig_text, encoding="utf8")
    (Path(args.char) / "character.json").write_text(json.dumps(char, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print("rig bones:", len(bones), " textures:", len(textures), " parts:", len(char["parts"]))


if __name__ == "__main__":
    main()
