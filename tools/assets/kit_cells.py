"""Find the separate pieces ("cells") of a rendered kit model and print a numbered preview (NE-57 / NE-59).

Kit models (Poly Haven modular facades, pipes, poles) hold many pieces laid out on a grid in one glTF. After
render_model.py has written assets_src/work/kits/<name>.png this script labels the pieces, writes
assets_src/work/kits/<name>_cells.json (boxes in pixels, sorted row by row) and <name>_cells.png (numbered preview),
so a pipeline entry can refer to a piece by its index instead of by hand-measured coordinates.

Usage: python tools/assets/kit_cells.py <name> [min_size_px]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

KITS = Path(__file__).resolve().parents[2] / "assets_src" / "work" / "kits"


def find_cells(alpha: np.ndarray, min_size: int, gap: int = 6) -> list[list[int]]:
    mask = alpha > 8
    mask = ndimage.binary_dilation(mask, iterations=gap)  # bridge hairline gaps inside one piece
    labels, count = ndimage.label(mask)
    boxes = []
    for sl in ndimage.find_objects(labels):
        y0, y1, x0, x1 = sl[0].start + gap, sl[0].stop - gap, sl[1].start + gap, sl[1].stop - gap
        if x1 - x0 >= min_size and y1 - y0 >= min_size:
            boxes.append([int(x0), int(y0), int(x1), int(y1)])
    row_h = max(1, min_size)
    boxes.sort(key=lambda b: (round(b[1] / row_h), b[0]))
    return boxes


def main() -> int:
    name = sys.argv[1]
    min_size = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    image = Image.open(KITS / f"{name}.png").convert("RGBA")
    boxes = find_cells(np.asarray(image.getchannel("A")), min_size)
    (KITS / f"{name}_cells.json").write_text(json.dumps(boxes), encoding="utf-8")
    preview = Image.new("RGBA", image.size, (50, 50, 70, 255))
    preview.alpha_composite(image)
    draw = ImageDraw.Draw(preview)
    for i, b in enumerate(boxes):
        draw.rectangle(b, outline=(255, 255, 0, 255), width=3)
        draw.text((b[0] + 6, b[1] + 6), str(i), fill=(255, 255, 0, 255))
    preview.convert("RGB").save(KITS / f"{name}_cells.png")
    print(f"{len(boxes)} cells -> {KITS / (name + '_cells.png')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
