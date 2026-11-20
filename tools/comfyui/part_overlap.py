"""Extend only the concealed alpha margins of pinned character parts."""

from hashlib import sha256
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt


def extend_overlap(source: Path, expected: str, contacts: tuple, *,
                   last_row: int | None = None, last_column: int | None = None) -> Image.Image:
    content = source.read_bytes()
    if sha256(content).hexdigest() != expected:
        raise ValueError(f"{source}: expected the approved contact source")
    with Image.open(BytesIO(content)) as image:
        original = np.asarray(image.convert("RGBA"))
    result = original.copy()
    alpha = original[:, :, 3]
    source_y, source_x = distance_transform_edt(alpha < 128, return_distances=False, return_indices=True)
    for x, y, reach in contacts:
        from_x = source_x[round(y), round(x)]
        from_y = source_y[round(y), round(x)]
        left = int(min(x, from_x) - reach - 2)
        right = int(max(x, from_x) + reach + 3)
        top = int(min(y, from_y) - reach - 2)
        bottom = int(max(y, from_y) + reach + 3)
        rows, columns = np.ogrid[top:bottom, left:right]
        vx, vy = x - from_x, y - from_y
        progress = np.clip(((columns + 0.5 - from_x) * vx + (rows + 0.5 - from_y) * vy)
                           / max(vx * vx + vy * vy, 0.01), 0.0, 1.0)
        distance = np.hypot(columns + 0.5 - from_x - progress * vx,
                            rows + 0.5 - from_y - progress * vy)
        coverage = np.clip((reach - distance) * 255.0, 0.0, 255.0).astype(np.uint8)
        region = np.s_[top:bottom, left:right]
        local = result[region]
        mask = (coverage > local[:, :, 3]) & (alpha[region] < 128)
        if last_row is not None:
            mask &= rows <= last_row
        if last_column is not None:
            mask &= columns <= last_column
        local[mask, :3] = original[source_y[region][mask], source_x[region][mask], :3]
        local[mask, 3] = coverage[mask]
    return Image.fromarray(result)
