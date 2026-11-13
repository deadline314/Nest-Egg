"""Native pixel, three-background comparison; does not publish the candidate."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

WORK = Path(__file__).resolve().parent


def main():
    folder = WORK / "torso_underlayer"
    before = np.array(Image.open(WORK / "07_refined/torso.png"))
    candidate = np.array(Image.open(folder / "candidate_full_canvas.png"))
    mask = np.array(Image.open(folder / "reviewed_region_candidate.png")) > 0
    after = before.copy()
    region = mask & (before[:, :, 3] > 0)
    after[region, :3] = candidate[region, :3]
    assert np.array_equal(before[:, :, 3], after[:, :, 3])
    assert np.array_equal(before[~region], after[~region])
    Image.fromarray(after).save(folder / "candidate_torso.png")
    box = (320, 256, 544, 544)
    width, height = box[2] - box[0], box[3] - box[1]
    review = Image.new("RGB", (width * 3, (height + 20) * 2), (48, 48, 48))
    draw = ImageDraw.Draw(review)
    for row, array in enumerate((before, after)):
        layer = Image.fromarray(array).crop(box)
        for column, background in enumerate(((144, 144, 144), (208, 210, 214), (32, 35, 42))):
            tile = Image.new("RGB", layer.size, background)
            tile.paste(layer, mask=layer.getchannel("A"))
            review.paste(tile, (column * width, row * (height + 20)))
            draw.text((column * width, row * (height + 20) + height),
                      "old flat underlayer" if row == 0 else "unadopted cloth RGB", fill="white")
    review.save(folder / "native-rgb-review.png")
    receipt = dict(classification="CPU material review, unadopted; alpha and geometry unchanged",
                   native_crop=list(box), alpha_exact=True, outside_saved_mask_rgba_exact=True,
                   changed_rgb_pixels=int(np.count_nonzero(np.any(before != after, axis=2))),
                   before_sha256=hashlib.sha256((WORK / "07_refined/torso.png").read_bytes()).hexdigest(),
                   proposed_sha256=hashlib.sha256((folder / "candidate_torso.png").read_bytes()).hexdigest())
    (folder / "material-review.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
