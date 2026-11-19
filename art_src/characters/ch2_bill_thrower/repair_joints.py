"""Rebuild the three reviewed source-space overlaps before cutting the textures."""

from hashlib import sha256
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage


ROOT = Path(__file__).resolve().parent


def layer(name: str, digest: str) -> np.ndarray:
    path = ROOT / name
    if sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f"{path}: expected the reviewed source")
    with Image.open(path) as image:
        if image.mode != "RGBA" or image.size != (832, 1216):
            raise ValueError(f"{path}: expected native RGBA canvas")
        return np.array(image)


def polygon(canvas: np.ndarray, points: list[tuple[int, int]]) -> np.ndarray:
    mask = Image.new("1", (canvas.shape[1], canvas.shape[0]))
    ImageDraw.Draw(mask).polygon(points, fill=1)
    return np.array(mask)


def store(name: str, pixels: np.ndarray) -> None:
    target = ROOT / "overrides" / "refined"
    target.mkdir(parents=True, exist_ok=True)
    Image.fromarray(pixels).save(target / f"{name}.png")


def main() -> None:
    original = layer("base_rgba.png", "9e52976c5a622cd29846d3d520c99e135ba45a33ed4ce00f484ed83d6571a33f")
    head = layer("07_refined/head.png", "211a3a2532a88b5e1728b07973edd05794800ca927c65969799c1032c596c792")
    chin = polygon(head, [(425, 157), (435, 158), (440, 166), (439, 175), (429, 177), (423, 170)])
    restore = chin & (head[:, :, 3] < 128) & (original[:, :, 3] >= 128)
    head[restore] = original[restore]
    store("head", head)

    pelvis = layer("07_refined/pelvis.png", "b2b1d0a1ff17223a84dfd89d220e4e857e28b77168682d7cfa85a991eaf242e2")
    belt = polygon(pelvis, [(494, 528), (500, 530), (505, 533), (505, 540), (500, 544), (494, 544)])
    restore = belt & (pelvis[:, :, 3] < 128)
    y, x = np.nonzero(restore)
    pelvis[y, x] = pelvis[y, np.minimum(x, 496)]
    store("pelvis", pelvis)

    ticket_box = layer("07_refined/ticket_box.png", "b1da6fecc4f9bbe89b9c7c16f7b611bdf100469fd6425621149c9a33452b741d")
    strap = ticket_box[527:567, 320:350]
    solid = strap[:, :, 3] >= 128
    continuous = cv2.morphologyEx(solid.astype(np.uint8), cv2.MORPH_CLOSE,
                                  cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))) > 0
    restore = continuous & ~solid
    nearest = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    strap[restore] = strap[nearest[0][restore], nearest[1][restore]]
    store("ticket_box", ticket_box)
    print("Rebuilt the chin, front waistband and ticket strap overlaps.")


if __name__ == "__main__":
    main()
