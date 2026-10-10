"""Round joint caps (make_parts.cap_distance / cap_alpha): offline, no model, no GPU.

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/test_joint_caps.py
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from make_parts import cap_alpha, cap_distance  # noqa: E402


def main() -> None:
    shape = (80, 80)
    dist = cap_distance(shape, [40, 40])
    assert dist[40, 40] == 0 and abs(dist[40, 50] - 10) < 1e-6 and abs(dist[30, 40] - 10) < 1e-6
    alpha = np.full(shape, 255, np.uint8)
    straight = np.zeros(shape, bool)
    straight[:20] = True  # the rows of the straight cut keep their alpha whatever the cap says
    out = cap_alpha(alpha, straight, [(dist, 20.0, 10.0)])
    assert (out[:20] == 255).all(), "straight cut lost alpha"
    assert out[40, 40] == 255 and out[40, 49] == 255, "cap core must stay opaque"
    assert out[40, 55] == 128, f"half way through the feather should be half alpha, got {out[40, 55]}"
    assert out[40, 60] == 0 and out[70, 70] == 0, "outside the cap must be empty"
    hard = cap_alpha(alpha, straight, [(dist, 20.0, 0.0)])
    assert hard[40, 59] == 255 and hard[40, 61] == 0, "feather 0 = hard rim"
    two = cap_alpha(alpha, straight, [(dist, 20.0, 10.0), (cap_distance(shape, [60, 60]), 8.0, 0.0)])
    assert two[60, 60] == 255, "a second cap adds, it never removes"
    print("test_joint_caps: ok")


if __name__ == "__main__":
    main()
