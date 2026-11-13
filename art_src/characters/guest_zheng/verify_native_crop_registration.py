"""Compare actual Sprite geometry across the old native cut and integer-extended cut."""
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"


def points(sprite, coordinates):
    matrix = np.asarray(sprite["to_cell"], float)
    local = np.asarray(coordinates, float) + sprite["rect_origin"]
    return local @ matrix[:, :2].T + matrix[:, 2]


def main():
    before = json.loads((OUT / "onepixel-negative-native-v1/frames.json").read_text(encoding="utf8"))[0]
    after = json.loads((OUT / "material-true-hole-native-v2/frames.json").read_text(encoding="utf8"))[0]
    records = []
    for facing in (-1, 1):
        sprites = []
        for group in (before, after):
            cell = next(c for c in group["cells"] if c["joint"] == "wrist_back" and c["facing"] == facing)
            sprites.append(next(p for p in cell["geometry_first"] if p["part"] == "hand_back"))
        old, new = sprites
        assert old["size"] == [171, 100] and new["size"] == [180, 100]
        assert np.max(np.abs(np.array(new["rect_origin"]) - old["rect_origin"] + [9, 0])) < 1e-5
        # Full retained finger domain corners and the exact authored contact.
        uv = np.array([[60, 0], [170, 0], [60, 99], [170, 99], [149.156589, 42.000018]])
        old_points = points(old, uv)
        new_points = points(new, uv + [9, 0])
        delta = np.linalg.norm(new_points - old_points, axis=1)
        assert float(delta.max()) < .001, delta
        records.append(dict(facing=facing, native_cell_point_error=delta.tolist(), maximum_native_pixel_error=float(delta.max()),
                            old_rect_origin=old["rect_origin"], new_rect_origin=new["rect_origin"]))
    result = dict(classification="actual native Sprite geometry and retained UV/contact correspondence; not a full rendered RGB equality claim",
                  old_capture="onepixel-negative-native-v1", new_capture="material-true-hole-native-v2",
                  cases=records, passed=True)
    (OUT / "material-native-crop-registration.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8", newline="\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
