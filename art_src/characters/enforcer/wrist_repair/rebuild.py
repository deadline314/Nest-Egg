"""Rebuild the reviewed enforcer wrist overrides from pinned source pixels."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SIZE = (832, 1216)
SOURCES = {
    "base_rgba.png": "046fc689ee025174875a098a92c0b2555b683b0021ffb9aad398ef18f82dd18f",
    "04_stages/P.png": "7477e641207ba5f8a44504214501cf80282d727dd936a355553e2c85f9bab559",
    "07_refined/arm_lower.png": "14a8a771f3e6da21de8049c1635026891c7663a52815f96d25e562390dec4e7e",
    "sam/arm_sleeve.png": "e3422d0b72bcd2f29b067e57a4d7c5f46f95c59d05ca4d09698e01dc960727af",
    "sam/gloved_hand.png": "565069db0f8ddcefb0e49b60542ca947c5f05b756405b34ed2159ab3e943f1e2",
    "04_stages/sam_P/arm_sleeve.png": "cd22238a11e0162aed9827d8b952a370b2ea37b91bdaabc4ec81419209e00dc8",
}
OWNERS = {
    "arm_lower_base.png": ("c2cf81d450c6552e6ae8dc9df03e321961277ea334f8c6e29a7510374b5ee0a7", 2743, "base_rgba.png"),
    "arm_lower_stage_P.png": ("403ef8ad280aa37d9dccd0f0db84d8664593e10bc3869723c276a8784c789338", 18919, "04_stages/P.png"),
    "arm_lower_existing_07_refined.png": ("c119a7fb415a04738587323bb0706d07626ee010e7015ff2331557a7eed29856", 73, "07_refined/arm_lower.png"),
    "hand_base.png": ("068c16743d686de24f8e1281fc7719f271fbbc80673dff18fb451a402c92ab1f", 9154, "base_rgba.png"),
}
CLEAR = ("f2de42f7c0125bd50995695f792d0e60ccbe9239b1f33591ec981daf0ab74735", 14)
TARGET_PIXELS = {
    "arm_lower": "5ba8f592c4e135b590afee9c101121fb5db96be3f761334e66c2bba12e45a1dc",
    "hand": "07e277410ef549c4b73c3eadf91f6ce740a1878e35661b6834e2af2eba4c6daa",
}
OWNER_NAMES = tuple(OWNERS)
HAND_UNION_SHA = "cf013374e0184eb70bcef7349656b6310dbc7103ad15982088ca2cfec8e57b53"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return sha(path.read_bytes())


def pixel_sha(array: np.ndarray) -> str:
    return sha(np.ascontiguousarray(array).tobytes())


def pin(path: Path, expected: str) -> None:
    actual = file_sha(path)
    if actual != expected:
        raise ValueError(f"SHA-256 mismatch: {path} expected {expected}, got {actual}")


def rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.mode != "RGBA" or image.size != SIZE:
            raise ValueError(f"expected native 832x1216 RGBA: {path}")
        return np.asarray(image).copy()


def binary_l(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.mode != "L" or image.size != SIZE:
            raise ValueError(f"expected native 832x1216 L mask: {path}")
        mask = np.asarray(image).copy()
    if not set(np.unique(mask)).issubset({0, 255}):
        raise ValueError(f"owner mask is not binary: {path}")
    return mask == 255


def one_component_no_holes(mask: np.ndarray, name: str) -> None:
    count, _, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count != 2:
        raise ValueError(f"{name} must have one component; found {count - 1}")
    x, y, w, h, _ = (int(v) for v in stats[1])
    cropped = mask[y:y + h, x:x + w]
    n, _, holes, _ = cv2.connectedComponentsWithStats((~cropped).astype(np.uint8), 8)
    for i in range(1, n):
        hx, hy, hw, hh, _ = (int(v) for v in holes[i])
        if hx > 0 and hy > 0 and hx + hw < w and hy + hh < h:
            raise ValueError(f"{name} contains an enclosed alpha hole")


def load(work: Path, owner_dir: Path) -> tuple[dict[str, np.ndarray], dict[str, np.ndarray]]:
    for path, digest in SOURCES.items():
        pin(work / path, digest)
    src = {name: rgba(work / name) for name in ("base_rgba.png", "04_stages/P.png", "07_refined/arm_lower.png")}
    masks = {}
    for name, (digest, count, _) in OWNERS.items():
        path = owner_dir / name
        pin(path, digest)
        masks[name] = binary_l(path)
        if int(masks[name].sum()) != count:
            raise ValueError(f"owner mask count changed: {name}")
    path = owner_dir / "seam_clear_overlap.png"
    pin(path, CLEAR[0])
    masks["seam_clear_overlap.png"] = binary_l(path)
    if int(masks["seam_clear_overlap.png"].sum()) != CLEAR[1]:
        raise ValueError("seam-clear owner count changed")
    return src, masks


def assemble(src: dict[str, np.ndarray], masks: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    names = OWNER_NAMES[:3]
    part_masks = [masks[name] for name in names]
    if any(np.any(part_masks[i] & part_masks[j]) for i in range(3) for j in range(i + 1, 3)):
        raise ValueError("arm source owners overlap")
    union = part_masks[0] | part_masks[1] | part_masks[2]
    if int(union.sum()) != 21735:
        raise ValueError("arm source owner union changed")
    one_component_no_holes(union, "arm_lower")

    arm = src["07_refined/arm_lower.png"].copy()
    arm[:, :, 3][~union] = 0
    for name, source_key in zip(names, ("base_rgba.png", "04_stages/P.png", "07_refined/arm_lower.png")):
        selected = part_masks[names.index(name)]
        source = src[source_key]
        if np.any(source[selected, 3] == 0):
            raise ValueError(f"{name} selects transparent source pixels")
        arm[selected] = source[selected]
    clear = masks["seam_clear_overlap.png"]
    if np.any(clear & union):
        raise ValueError("seam-clear pixels overlap an alpha owner")
    arm[clear] = 0

    hand_mask = masks["hand_base.png"]
    one_component_no_holes(hand_mask, "hand")
    base = src["base_rgba.png"]
    if np.any(base[hand_mask, 3] == 0):
        raise ValueError("hand owner selects transparent source pixels")
    hand = np.zeros_like(base)
    hand[hand_mask] = base[hand_mask]
    outputs = {"arm_lower": arm, "hand": hand}
    for name, output in outputs.items():
        if pixel_sha(output) != TARGET_PIXELS[name]:
            raise ValueError(f"{name} RGBA differs from reviewed candidate, including transparent RGB")
    return outputs


def install(outputs: dict[str, np.ndarray], work: Path) -> list[str]:
    target = work / "overrides/refined"
    target.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".wrist-replay-", dir=target.parent))
    files = {name: target / f"{name}.png" for name in outputs}
    backups = {path: path.read_bytes() if path.exists() else None for path in files.values()}
    replaced = []
    try:
        for name, array in outputs.items():
            temp = stage / f"{name}.png"
            Image.fromarray(array, "RGBA").save(temp)
            if pixel_sha(rgba(temp)) != TARGET_PIXELS[name]:
                raise ValueError(f"staged output differs: {name}")
        for name, path in files.items():
            os.replace(stage / f"{name}.png", path)
            replaced.append(path)
    except Exception:
        for path in reversed(replaced):
            old = backups[path]
            if old is None:
                path.unlink(missing_ok=True)
            else:
                rollback = stage / f"rollback-{path.name}"
                rollback.write_bytes(old)
                os.replace(rollback, path)
        raise
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    return [str(path) for path in files.values()]


def build(work: Path, owner_dir: Path = HERE / "owners") -> dict:
    src, masks = load(work, owner_dir)
    hand_union = work / "wrist_repair/provenance/root-hand-selection/hand-union-fullcanvas.png"
    pin(hand_union, HAND_UNION_SHA)
    if not np.array_equal(rgba(hand_union)[:, :, 3] > 0, masks["hand_base.png"]):
        raise ValueError("hand owner differs from pinned root hand selection")
    cuff_path = work / "sam/arm_sleeve.png"
    with Image.open(cuff_path) as image:
        if image.size != SIZE or image.mode not in ("L", "RGB", "RGBA"):
            raise ValueError(f"expected native 832x1216 cuff mask image: {cuff_path}")
        cuff = np.asarray(image.convert("L")).copy() >= 128
    expected_clear = cuff & (np.indices(cuff.shape)[0] >= 588) & masks["hand_base.png"]
    if not np.array_equal(expected_clear, masks["seam_clear_overlap.png"]):
        raise ValueError("seam-clear mask differs from original cuff/hand owners")
    outputs = assemble(src, masks)
    paths = install(outputs, work)
    return {
        "source_sha256": SOURCES,
        "owner_sha256": {name: file_sha(owner_dir / name) for name in OWNER_NAMES},
        "seam_clear_sha256": file_sha(owner_dir / "seam_clear_overlap.png"),
        "full_canvas": {n: {"pixels": int((a[:, :, 3] > 0).sum()), "rgba_sha256": pixel_sha(a)} for n, a in outputs.items()},
        "written_overrides": paths,
        "status": "source replay only; cut-layer and animation acceptance are separate checks",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=ROOT / "art_src/characters/enforcer", help="isolated clone; default is only for registered source_rebuilds hook")
    args = parser.parse_args()
    report = build(args.work)
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
