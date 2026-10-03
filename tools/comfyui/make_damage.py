"""Torn-clothes layers: the picture the character shows underneath her clothes while they are being shot off (NE-70).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/make_damage.py --spec tools/comfyui/specs/rin_side.json --work art_src/characters/rin2

Inputs : <work>/04_stages/<spec.damage.stage>.png   the torn-clothes picture (make_parts.py: stage C removes jacket, arm, hand and holster,
                                                    stage D tears the clothes of C - both are Qwen edits and keep the pose)
         <work>/07_refined/<part>.png               the intact part (its outline is reused, so the torn layer has the same silhouette)
         spec.parts.<name>.damage_of = <part>       one entry per torn layer
Output : <work>/07_refined/<name>.png               same canvas as the intact part: its outline, the torn picture's colours
The torn layer is drawn one step below the intact part (spec z), so at full health it is hidden; the intact parts (spec armor_order) fly off
one step at a time and uncover it.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    ap.add_argument("--work", required=True)
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text(encoding="utf8"))
    work = Path(args.work)
    stage = np.array(Image.open(work / "04_stages" / f"{spec['damage']['stage']}.png").convert("RGBA"))
    for name, p in spec["parts"].items():
        if "damage_of" not in p:
            continue
        intact = np.array(Image.open(work / "07_refined" / f"{p['damage_of']}.png").convert("RGBA"))
        # only the solid pixels of the torn picture, pulled in 2 px from its outline (Qwen paints a pale halo on the rim); elsewhere keep the intact colours
        import cv2
        solid = (stage[:, :, 3] >= 250).astype(np.uint8)
        use_stage = cv2.erode(solid, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0  # where the torn picture has no pixels, keep the intact colours rather than a hole
        rgb = np.where(use_stage[:, :, None], stage[:, :, :3], intact[:, :, :3])
        Image.fromarray(np.dstack([rgb, intact[:, :, 3]])).save(work / "07_refined" / f"{name}.png")
        print(f"  {name}: torn layer of {p['damage_of']}")


if __name__ == "__main__":
    main()
