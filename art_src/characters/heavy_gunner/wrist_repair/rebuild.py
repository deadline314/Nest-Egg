"""Rebuild the reviewed heavy_gunner arm_lower source override."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SIZE = (832, 1216)
SOURCES = {
    "base_rgba.png": "50ad19cfbac08512068e870298354b9881b923482e5866a858bd9f55ad0894a0",
    "04_stages/P.png": "2d433d2f90d21d24276dc7ef12a6a1ac8abb7e635f2fd474ffeaa092b3ebc761",
    "07_refined/arm_lower.png": "bd2837c4817e6d87e4000ffddc4c69bd8f71f518d6784c846c9015fabcb33e41",
    "07_refined/arm_upper.png": "74ef8fe79df12343e361b831ba1f1717fa2990b65e3aeb1c07d96ece526a3943",
}
OWNERS = {
    "base.png": ("base_rgba.png", "702af51d263f2ebd535f1316503d2d48de8f2b183a1efc7710d193edb9d13028", 10),
    "stage_P.png": ("04_stages/P.png", "be7b35ce51087e1dd950a4977918817e0d7feba9ce01cc60356073298c71c810", 18687),
    "lower_07.png": ("07_refined/arm_lower.png", "889df694636f7f0f6b420ddc9c6e3a8e87705379575f2e05bff656449894e214", 11),
    "upper_band18.png": ("07_refined/arm_upper.png", "bb9ee878e8db941c4a06024f721499c90e9d2ca886f72f3372c2f52910820a9c", 3400),
}
TARGET_PIXELS = "55c3d94a8ce1e6a18e4c602b6d41531550788f06b804bdfbad0c46214ad4fac5"
TARGET_OPAQUE = 22108
TARGET_PART_PNG = "88a893bab6ffa739a9d6a6ad67482d1b6248f3551e72a22d71c6ad790f54854a"
TARGET_NORMAL_PNG = "bbdb15ff0c61827683352ce8f75cd0c98933921a6a9fb1ced5a9820b63784218"
TARGET_SIZE = [162, 230]
TARGET_PIVOT = [64.15, 21.87]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return sha(path.read_bytes())


def pin(path: Path, expected: str) -> None:
    actual = file_sha(path)
    if actual != expected:
        raise ValueError(f"SHA-256 mismatch: {path}; expected {expected}, got {actual}")


def rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.mode != "RGBA" or image.size != SIZE:
            raise ValueError(f"expected native RGBA 832x1216: {path}")
        return np.asarray(image).copy()


def binary_mask(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        if image.mode != "L" or image.size != SIZE:
            raise ValueError(f"expected native L mask 832x1216: {path}")
        values = np.asarray(image).copy()
    if not set(np.unique(values)).issubset({0, 255}):
        raise ValueError(f"mask is not binary: {path}")
    return values == 255


def one_component_no_holes(mask: np.ndarray, name: str) -> None:
    count, _, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count != 2:
        raise ValueError(f"{name} must have one connected component, found {count - 1}")
    x, y, width, height, _ = (int(value) for value in stats[1])
    crop = mask[y:y + height, x:x + width]
    count, _, holes, _ = cv2.connectedComponentsWithStats((~crop).astype(np.uint8), 8)
    for index in range(1, count):
        hx, hy, hw, hh, _ = (int(value) for value in holes[index])
        if hx > 0 and hy > 0 and hx + hw < width and hy + hh < height:
            raise ValueError(f"{name} contains an enclosed one-pixel or larger hole")


def load(work: Path, owner_dir: Path) -> tuple[dict[str, np.ndarray], dict[str, np.ndarray]]:
    for relative, digest in SOURCES.items():
        pin(work / relative, digest)
    sources = {relative: rgba(work / relative) for relative in SOURCES}
    masks = {}
    for name, (_, digest, pixel_count) in OWNERS.items():
        path = owner_dir / name
        pin(path, digest)
        masks[name] = binary_mask(path)
        if int(masks[name].sum()) != pixel_count:
            raise ValueError(f"owner mask pixel count changed: {name}")
    return sources, masks


def assemble(sources: dict[str, np.ndarray], masks: dict[str, np.ndarray]) -> np.ndarray:
    names = tuple(OWNERS)
    for index, left in enumerate(names):
        for right in names[index + 1:]:
            if np.any(masks[left] & masks[right]):
                raise ValueError(f"source owner masks overlap: {left}, {right}")
    upper_band = masks["upper_band18.png"]
    one_component_no_holes(upper_band, "reviewed upper-arm band18 owner")
    upper = sources["07_refined/arm_upper.png"]
    if np.any(upper[upper_band, 3] < 40):
        raise ValueError("band18 owner selects upper-arm source below alpha 40")

    union = np.logical_or.reduce([masks[name] for name in names])
    if int(union.sum()) != TARGET_OPAQUE:
        raise ValueError(f"source-owner union changed: {int(union.sum())}")
    one_component_no_holes(union, "arm_lower candidate alpha")

    # Preserve the existing transparent RGB exactly, then assign each visible pixel
    # from its single pinned native source owner.
    output = sources["07_refined/arm_lower.png"].copy()
    output[:, :, 3][~union] = 0
    for name, (source_name, _, _) in OWNERS.items():
        owner = masks[name]
        source = sources[source_name]
        if np.any(source[owner, 3] == 0):
            raise ValueError(f"{name} selects transparent source pixels")
        output[owner] = source[owner]
    if sha(np.ascontiguousarray(output).tobytes()) != TARGET_PIXELS:
        raise ValueError("decoded arm_lower RGBA differs from reviewed band18 candidate")
    if not np.array_equal(output[:, :, 3] > 0, union):
        raise ValueError("source-owner union differs from reconstructed alpha")
    return output


def install(output: np.ndarray, work: Path) -> Path:
    target_dir = work / "overrides/refined"
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / "arm_lower.png"
    with tempfile.NamedTemporaryFile(prefix=".arm-lower-replay-", suffix=".png", dir=target_dir, delete=False) as temp:
        staged = Path(temp.name)
    try:
        Image.fromarray(output).save(staged)
        if sha(np.ascontiguousarray(rgba(staged)).tobytes()) != TARGET_PIXELS:
            raise ValueError("staged arm_lower PNG failed decoded RGBA check")
        os.replace(staged, target)
    finally:
        staged.unlink(missing_ok=True)
    return target


def build(work: Path, owner_dir: Path = HERE / "owners") -> dict:
    sources, masks = load(work, owner_dir)
    output = assemble(sources, masks)
    target = install(output, work)
    return {
        "source_sha256": SOURCES,
        "owner_sha256": {name: digest for name, (_, digest, _) in OWNERS.items()},
        "owner_pixels": {name: int(mask.sum()) for name, mask in masks.items()},
        "arm_lower": {"opaque_pixels": int((output[:, :, 3] > 0).sum()), "decoded_rgba_sha256": sha(output.tobytes())},
        "written_override": str(target),
        "status": "source replay candidate only; native elbow/wrist acceptance remains open",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=HERE.parent, help="isolated heavy_gunner source clone; default follows source_rebuilds hook")
    args = parser.parse_args()
    print(json.dumps(build(args.work), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
