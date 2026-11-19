"""Rebuild the enforcer's concealed cuff and knee seams from pinned parts."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
from runpy import run_path
from tempfile import NamedTemporaryFile

import numpy as np
from PIL import Image

THIGH_SHA256 = "5722c859cfcba36876767193dcb3fc06ea327d513a5d1c320bc24ae2d32763e2"
# Source-space bands traced from the genuine death, crouch, jump and run frames.
CUFF = ((325, 352, 610, 622, 0, 5),)
KNEE = ((331, 342, 784, 801, -4, 0), (332, 342, 808, 820, -4, 0))


def extend(original: np.ndarray, bands: tuple, expected: int) -> Image.Image:
    result = original.copy()
    for left, right, top, bottom, dx, dy in bands:
        for y in range(top, bottom):
            for x in range(left, right):
                distance = min(x-left, right-1-x) if dy else min(y-top, bottom-1-y)
                taper = min(1.0, distance / 3.0)
                source = original[y-round(dy*taper), x-round(dx*taper)]
                if source[3] > result[y, x, 3]:
                    result[y, x] = source
    if np.count_nonzero(np.any(result != original, axis=2)) != expected:
        raise ValueError("Enforcer layer overlap has drifted from its traced source grid")
    return Image.fromarray(result)


def build(work: Path) -> dict[str, Image.Image]:
    thigh_path = work / "07_refined/leg_upper.png"
    thigh = thigh_path.read_bytes()
    if sha256(thigh).hexdigest() != THIGH_SHA256:
        raise ValueError(f"{thigh_path}: expected the approved enforcer thigh source")
    wrist = run_path(str(work / "wrist_repair/rebuild.py"))
    sleeve = wrist["assemble"](*wrist["load"](work, work / "wrist_repair/owners"))["arm_lower"]
    with Image.open(BytesIO(thigh)) as image:
        knee = extend(np.asarray(image.convert("RGBA")), KNEE, 94)
    return {"arm_lower": extend(sleeve, CUFF, 114), "leg_upper": knee}


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
