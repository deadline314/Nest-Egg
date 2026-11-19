"""Rebuild the heavy gunner's concealed contacts on the original source grid."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
from runpy import run_path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image

SOURCE_HASHES = {
    "hand": "51b8909d7e20cbba527666da0d7ac736e98437e34bd483cf01c51ac926ae1e50",
    "leg_upper": "072474aa94d2dab0c6effc809a6f13860d8e6324b9e47734d09cbc9917297b26",
    "arm_upper": "74ef8fe79df12343e361b831ba1f1717fa2990b65e3aeb1c07d96ece526a3943",
}
# Hidden cloth sampled at the measured knee, shoulder and sleeve contacts.
BANDS = {
    "leg_upper": ((316, 342, 779, 818, 16), (311, 335, 792, 812, 22), (312, 338, 812, 839, 10)),
    "hand": ((311, 324, 573, 586, 4),),
    "torso": ((355, 372, 388, 414, 11),),
    "arm_lower": ((370, 380, 410, 421, 2),),
}
COUNTS = {"leg_upper": 771, "hand": 28, "torso": 222, "arm_lower": 4, "arm_upper": 22}


def approved(work: Path, name: str) -> np.ndarray:
    path = work / "07_refined" / f"{name}.png"
    content = path.read_bytes()
    if sha256(content).hexdigest() != SOURCE_HASHES[name]:
        raise ValueError(f"{path}: expected the approved heavy gunner source")
    with Image.open(BytesIO(content)) as image:
        return np.array(image.convert("RGBA"))


def build(work: Path) -> dict[str, Image.Image]:
    collar = run_path(str(work / "neck_overlap/rebuild.py"))
    wrist = run_path(str(work / "wrist_repair/rebuild.py"))
    original = {
        "leg_upper": approved(work, "leg_upper"),
        "hand": approved(work, "hand"),
        "torso": np.asarray(collar["build"](work.parents[2])),
        "arm_lower": wrist["assemble"](*wrist["load"](work, work / "wrist_repair/owners")),
        "arm_upper": approved(work, "arm_upper"),
    }
    repaired = {name: layer.copy() for name, layer in original.items()}
    for name, bands in BANDS.items():
        for left, right, top, bottom, depth in bands:
            for row in range(top, bottom):
                distance = min(row - top, bottom - 1 - row)
                reach = round(depth * min(1.0, distance / 3.0))
                edge = repaired[name][row, left:right]
                extension = original[name][row, left + reach:right + reach]
                replace = extension[:, 3] > edge[:, 3]
                edge[replace] = extension[replace]
    repaired["arm_upper"][270:277, 240:247, 3] = 0
    repaired["arm_upper"][364:367, 255:264, 3] = 0
    for name, layer in repaired.items():
        if np.count_nonzero(np.any(layer != original[name], axis=2)) != COUNTS[name]:
            raise ValueError(f"Heavy gunner {name}: contact edit has drifted from its source grid")
    return {name: Image.fromarray(layer) for name, layer in repaired.items()}


def install(work: Path) -> None:
    parts = build(work)
    destination = work / "overrides/refined"
    destination.mkdir(parents=True, exist_ok=True)
    for name, image in parts.items():
        path = destination / f"{name}.png"
        with BytesIO() as stream:
            image.save(stream, format="PNG")
            content = stream.getvalue()
        if path.is_file() and path.read_bytes() == content:
            continue
        with NamedTemporaryFile(dir=destination, suffix=".png", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        try:
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    install(Path(__file__).resolve().parents[1])
