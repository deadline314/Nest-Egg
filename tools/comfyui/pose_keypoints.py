"""Predict body keypoints (shoulder, elbow, wrist, hip, knee, ankle...) of the character in a picture with SAM 3D Body.

Runs ComfyUI's own SAM 3D Body nodes in-process, so use ComfyUI's python:
    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/pose_keypoints.py --image base.png --out keypoints.json [--overlay overlay.png]

Needs models/detection/sam_3d_body_dinov3_bf16.safetensors (https://huggingface.co/Comfy-Org/sam-3d-body).
Output JSON: {"image_size": [w, h], "points": {"left_elbow": [x, y], ...}} in pixels of the input picture.
MHR70 layout (Meta): 0 nose, 1-2 eyes, 3-4 ears, 5/6 shoulders, 7/8 elbows, 9/10 hips, 11/12 knees, 13/14 ankles, 15-20 feet,
21-41 right hand (41 = wrist), 42-62 left hand (62 = wrist), 63-66 elbow detail, 67/68 acromion, 69 neck.
"""
import argparse
import json
import sys
from pathlib import Path

COMFY = Path("D:/ComfyUI")
NAMES = {0: "nose", 5: "left_shoulder", 6: "right_shoulder", 7: "left_elbow", 8: "right_elbow", 9: "left_hip", 10: "right_hip",
         11: "left_knee", 12: "right_knee", 13: "left_ankle", 14: "right_ankle", 15: "left_big_toe", 17: "left_heel", 18: "right_big_toe",
         20: "right_heel", 41: "right_wrist", 62: "left_wrist", 67: "right_acromion", 68: "left_acromion", 69: "neck"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--overlay")
    ap.add_argument("--model", default="sam_3d_body_dinov3_bf16.safetensors")
    ap.add_argument("--hands", action="store_true", help="also run the (slower) hand refinement")
    args = ap.parse_args()
    sys.path = [p for p in sys.path if Path(p or ".").resolve() != Path(__file__).resolve().parent]  # our comfy_api.py would shadow ComfyUI's comfy_api package
    sys.path.insert(0, str(COMFY))
    import numpy as np
    import torch
    from PIL import Image, ImageDraw
    import comfy_extras.nodes_sam3d_body as nb

    img = Image.open(args.image).convert("RGB")
    arr = torch.from_numpy(np.asarray(img).astype(np.float32) / 255.0)[None]
    torch.set_grad_enabled(False)  # ComfyUI runs nodes without autograd
    model = nb.SAM3DBody_Loader.execute(args.model).args[0]
    data = nb.SAM3DBody_Predict.execute(model, arr, run_hand_refinement=args.hands).args[0]
    people = data["frames"][0]
    if not people:
        sys.exit("SAM 3D Body found nobody in the picture")
    kp = np.asarray(people[0]["pred_keypoints_2d"], dtype=float)
    print("keypoints:", kp.shape)
    points = {NAMES.get(i, f"kp{i}"): [round(float(x), 1), round(float(y), 1)] for i, (x, y) in enumerate(kp[:, :2])}
    Path(args.out).write_text(json.dumps({"image_size": list(img.size), "points": points}, indent=1), encoding="utf8")
    if args.overlay:
        d = ImageDraw.Draw(img)
        for i, (x, y) in enumerate(kp[:, :2]):
            if i in NAMES or i in (63, 64, 65, 66):
                d.ellipse([x - 5, y - 5, x + 5, y + 5], outline=(255, 0, 0), width=2)
                d.text((x + 7, y - 6), str(i), fill=(255, 0, 0))
        img.save(args.overlay)


if __name__ == "__main__":
    main()
