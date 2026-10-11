"""Cut the seated hip and thigh out of the rin_sit source and register it on rin_field's canvas as a thigh in bind (standing) orientation.

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_sit/register.py

CPU only, nothing is generated. The seated picture is drawn about a third larger than rin_field and with a longer thigh, so the cut-out is
turned and scaled (a little less along the thigh than across it) until hip -> knee equals rin_field's own hip -> knee. The game turns the
thigh bone back to horizontal when she sits, which shows the piece the way it was drawn: one buttock-and-thigh volume instead of the
standing thigh folded by 90 degrees.
Writes art_src/characters/rin_field/poses/sit/leg_upper.png and leg_upper_dmg.png (full canvas, same coordinates as base_rgba.png) and review.png next to this file.
"""
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "01_design" / "design_s22501.png"
SOURCE_SHA256 = "311e938eaaefe959841496eb0f24648dfa52f81ddc6e54f0a921152de5a58999"
SPEC = ROOT / "tools/comfyui/specs/rin_side.json"
TARGET = ROOT / "art_src/characters/rin_field/poses/sit"
HIP, KNEE = (340.0, 792.0), (806.0, 792.0)  # seated picture: centre of the hip, centre of the knee (thigh midline x shin midline)
KNEE_RADIUS = 80.0                         # the kneecap stays on the thigh piece; the shin below it is the existing part
ACROSS = 0.80                              # thickness of the seated thigh over rin_field's thigh


def main() -> None:
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise SystemExit(f"[rin_sit] {SOURCE} is not the reviewed picture; stop")
    spec = json.loads(SPEC.read_text(encoding="utf8"))
    hip, knee = np.array(spec["joints"]["hip"], float), np.array(spec["joints"]["knee"], float)
    seated = np.asarray(Image.open(SOURCE).convert("RGBA")).copy()
    rgb = seated[:, :, :3].astype(int)
    yy, xx = np.mgrid[0:seated.shape[0], 0:seated.shape[1]]
    stocking = (seated[:, :, 3] > 127) & (rgb.max(2) < 110) & (rgb[:, :, 2] - rgb[:, :, 0] < 14)  # the navy jacket is bluer than the stockings
    region = (yy > 668) & ((xx < KNEE[0] - 60) & (yy < 930) | (np.hypot(xx - KNEE[0], yy - KNEE[1]) <= KNEE_RADIUS))
    disc = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))
    solid = cv2.morphologyEx((stocking & region).astype(np.uint8), cv2.MORPH_OPEN, disc)  # outlines of the bodysuit and the far shin are dark too, but thin
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, 8)
    keep = labels == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))  # the hip and thigh
    keep = cv2.morphologyEx(keep.astype(np.uint8), cv2.MORPH_CLOSE, disc) > 0
    seated[:, :, 3] = np.where(keep & (seated[:, :, 3] > 127), 255, 0)
    # The seated stockings came out more opaque than rin_field's sheer ones: scale the piece to the standing
    # thigh's mean colour, or the piece would not match the shin it meets at the knee.
    standing_thigh = np.asarray(Image.open(ROOT / "art_src/characters/rin_field/07_refined/leg_upper.png").convert("RGBA")).astype(np.float32)
    want = standing_thigh[standing_thigh[:, :, 3] > 250][:, :3]
    cloth = seated[:, :, 3] > 0  # every pixel of the piece: a brightness threshold here speckles the shadow, whose values sit around it
    have = seated[cloth][:, :3].astype(np.float32)
    seated[cloth, :3] = (have * (want.mean(0) / have.mean(0))).clip(0, 255).round().astype(np.uint8)  # a gain per channel: the black outline stays black
    print(f"cloth colour {have.mean(0).round(1)} -> {want.mean(0).round(1)}")

    along = np.linalg.norm(knee - hip) / np.hypot(KNEE[0] - HIP[0], KNEE[1] - HIP[1])
    axis = (knee - hip) / np.linalg.norm(knee - hip)
    front = np.array([axis[1], -axis[0]])  # the side of the standing thigh that faces +x (the character faces right)
    linear = np.column_stack([along * axis, -ACROSS * front])  # seated +x = down the thigh, seated +y (underside) = back of the standing thigh
    offset = hip - linear @ np.array(HIP)
    size = Image.open(ROOT / "art_src/characters/rin_field/base_rgba.png").size
    premultiplied = seated.astype(np.float32)
    premultiplied[:, :, :3] *= premultiplied[:, :, 3:] / 255.0
    out = cv2.warpAffine(premultiplied, np.column_stack([linear, offset]), size, flags=cv2.INTER_AREA)
    alpha = out[:, :, 3:]
    layer = np.dstack([np.where(alpha > 0, out[:, :, :3] / np.maximum(alpha, 1e-3) * 255.0, 0), alpha]).clip(0, 255).round().astype(np.uint8)
    TARGET.mkdir(parents=True, exist_ok=True)
    Image.fromarray(layer).save(TARGET / "leg_upper.png")
    print(f"poses/sit/leg_upper.png: {int((layer[:, :, 3] > 127).sum())} px, along {along:.3f}, across {ACROSS}")
    # The torn layer under it (shown once the stockings are shot off): the same seated piece with the standing thigh's tear, which lies
    # on the same canvas coordinates because both pieces are registered on the same hip and knee.
    refined = ROOT / "art_src/characters/rin_field/07_refined"
    intact = np.asarray(Image.open(refined / "leg_upper.png").convert("RGBA")).astype(int)
    torn = np.asarray(Image.open(refined / "leg_upper_dmg.png").convert("RGBA")).astype(int)
    tear = (np.abs(torn[:, :, :3] - intact[:, :, :3]).max(2) > 24) & (torn[:, :, 3] > 127) & (intact[:, :, 3] > 127) & (layer[:, :, 3] > 127)
    tear = cv2.morphologyEx(tear.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0
    damaged = layer.copy()
    damaged[tear, :3] = torn[tear, :3]
    Image.fromarray(damaged).save(TARGET / "leg_upper_dmg.png")
    print(f"poses/sit/leg_upper_dmg.png: tear {int(tear.sum())} px")

    review = Image.new("RGBA", size, (255, 0, 255, 255))
    review.alpha_composite(Image.fromarray(layer))
    standing = Image.new("RGBA", size, (255, 0, 255, 255))
    standing.alpha_composite(Image.open(ROOT / "art_src/characters/rin_field/07_refined/leg_upper.png").convert("RGBA"))
    box = (380, 540, 760, 1040)
    sheet = Image.new("RGB", ((box[2] - box[0]) * 2 + 8, box[3] - box[1]), (30, 30, 30))
    sheet.paste(standing.crop(box).convert("RGB"), (0, 0))
    sheet.paste(review.crop(box).convert("RGB"), (box[2] - box[0] + 8, 0))
    sheet.save(HERE / "review.png")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
