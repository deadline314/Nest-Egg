"""Turn the reviewed extra sources of rin_field into part sources (CPU only; listed in the recipe's source_rebuilds, so it runs before
every textures step). Inputs are checked by hash first; nothing is generated here.

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_field/extras/register.py

Writes  <work>/overrides/refined/arm_left_upper.png, arm_left_lower.png   the bare far arm, full canvas, cut at its elbow with an overlap
        <work>/extras/eyes/half.png, closed.png                           07_refined/head.png with only the eye region replaced
The arm is scaled as one piece (no stretching of one segment) so that shoulder to wrist equals the rig's arm, and placed on free canvas at
the joints arm_far_shoulder / arm_far_elbow / arm_far_wrist of the spec.
"""
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
WORK = HERE.parent
ROOT = WORK.parents[2]
SPEC = ROOT / "tools/comfyui/specs/rin_side.json"
HEAD_BOX = (424, 0, 680, 256)  # same box as generate.py
RAW = {
    "rin_field_arm_s22411_0.png": "6a81f0c736cc7ebf5d6af5fbcc620c8d7c61ee1f51afa3c4cc73dbb556afca23",
    "rin_field_half_s22421_0.png": "42388c5305a1454c89333afa4174ca4bb796b879bfcee0eeea8753f30dcc6386",
    "rin_field_closed_s22422_0.png": "61604eb90c01bfd2c6826cd117f76e38932378871c5851296ee5f8c471303350",
}
# Centres in pixels of the raw arm picture: the shoulder, the elbow crease and the wrist. The picture ends 12 px below ARM_WRIST: that
# stub stays hidden under the hand as the wrist's overlap.
ARM_SHOULDER, ARM_ELBOW, ARM_WRIST = (425.0, 342.0), (419.0, 575.0), (444.5, 824.0)
ALPHA_FLOOR = 40  # same floor as refine_parts.py: the generator leaves an alpha 1-3 haze on the whole canvas
SEAM = 12


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def similarity(src_a, src_b, dst_a, dst_b) -> tuple[np.ndarray, float]:
    """The scale + turn + shift that carries src_a -> dst_a and src_b -> dst_b (2x3 matrix), and its scale."""
    src_a, src_b, dst_a, dst_b = (np.array(p, float) for p in (src_a, src_b, dst_a, dst_b))
    scale = np.linalg.norm(dst_b - dst_a) / np.linalg.norm(src_b - src_a)
    turn = np.arctan2(*(dst_b - dst_a)[::-1]) - np.arctan2(*(src_b - src_a)[::-1])
    c, s = np.cos(turn) * scale, np.sin(turn) * scale
    A = np.array([[c, -s, 0.0], [s, c, 0.0]])
    A[:, 2] = dst_a - A[:, :2] @ src_a
    return A, float(scale)


def arm(spec: dict, size: tuple[int, int]) -> None:
    """Upper arm and forearm are placed separately, each as one rigid piece, so that the drawn elbow lands on the rig's elbow."""
    J = spec["joints"]
    raw = np.asarray(Image.open(HERE / "raw" / "rin_field_arm_s22411_0.png").convert("RGBA")).copy()
    raw[:, :, 3][raw[:, :, 3] < ALPHA_FLOOR] = 0
    premult = raw.astype(np.float32)
    premult[:, :, :3] *= premult[:, :, 3:] / 255.0
    yy, xx = np.mgrid[0:raw.shape[0], 0:raw.shape[1]]
    target = WORK / "overrides" / "refined"
    target.mkdir(parents=True, exist_ok=True)
    pieces = (("arm_left_upper", ARM_SHOULDER, ARM_ELBOW, "arm_far_shoulder", "arm_far_elbow", -1.0),
              ("arm_left_lower", ARM_ELBOW, ARM_WRIST, "arm_far_elbow", "arm_far_wrist", 1.0))
    for name, src_a, src_b, joint_a, joint_b, side in pieces:
        axis = (np.array(ARM_WRIST) - np.array(ARM_SHOULDER)) / np.linalg.norm(np.array(ARM_WRIST) - np.array(ARM_SHOULDER))
        along = (xx - ARM_ELBOW[0]) * axis[0] + (yy - ARM_ELBOW[1]) * axis[1]  # 0 at the elbow, + toward the wrist
        piece = premult.copy()
        piece[along * side < -SEAM / 0.8] = 0  # keep this segment and an overlap past the elbow
        A, scale = similarity(src_a, src_b, J[joint_a], J[joint_b])
        out = cv2.warpAffine(piece, A, size, flags=cv2.INTER_AREA)
        alpha = out[:, :, 3:]
        layer = np.dstack([np.where(alpha > 0, out[:, :, :3] / np.maximum(alpha, 1e-3) * 255.0, 0), alpha]).clip(0, 255).round().astype(np.uint8)
        Image.fromarray(layer).save(target / f"{name}.png")
        print(f"  {name}: {int((layer[:, :, 3] > 127).sum())} px, scale {scale:.4f}")


def eyes(spec: dict) -> None:
    head_path = WORK / "07_refined" / "head.png"
    head = np.asarray(Image.open(head_path).convert("RGBA"))
    canvas = Image.new("L", (head.shape[1], head.shape[0]), 0)  # rasterised exactly like cut_layers.validate_eye_state_sources
    ImageDraw.Draw(canvas).polygon([(round(x), round(y)) for x, y in spec["eye_states"]["eye_mask"]], fill=255)
    mask = (np.asarray(canvas) > 0) & (head[:, :, 3] > 0)
    (HERE / "eyes").mkdir(exist_ok=True)
    x0, y0, x1, y1 = HEAD_BOX
    for name, raw in (("half", "rin_field_half_s22421_0.png"), ("closed", "rin_field_closed_s22422_0.png")):
        edit = np.asarray(Image.open(HERE / "raw" / raw).convert("RGB").resize((x1 - x0, y1 - y0), Image.LANCZOS))
        out = head.copy()
        out[y0:y1, x0:x1, :3] = np.where(mask[y0:y1, x0:x1, None], edit, head[y0:y1, x0:x1, :3])
        assert np.array_equal(out[:, :, 3], head[:, :, 3]) and np.array_equal(out[~mask], head[~mask]), "only the eye region may change"
        Image.fromarray(out).save(HERE / "eyes" / f"{name}.png")
        print(f"  eyes/{name}.png: {int((out != head).any(2).sum())} px differ from the open head")


def main() -> None:
    for name, want in RAW.items():
        got = sha256(HERE / "raw" / name)
        if got != want:
            raise SystemExit(f"[rin_field extras] {name}: hash {got[:12]} is not the reviewed picture ({want[:12]}); stop")
    spec = json.loads(SPEC.read_text(encoding="utf8"))
    size = Image.open(WORK / "base_rgba.png").size
    arm(spec, size)
    if "eye_states" in spec:
        eyes(spec)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
