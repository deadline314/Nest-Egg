"""Extra sources of rin_field that no stage picture shows (Qwen Image 2.1 reference edits). Finished jobs are reused, not generated again.

    D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_field/extras/generate.py [arm] [half] [closed]

arm     the bare natural far arm (shown only once the jacket is torn off); reference = stage C
half    the head with the eye half closed;   reference = HEAD_BOX of base_rgba.png
closed  the head with the eye closed;        reference = HEAD_BOX of base_rgba.png
Raw outputs: extras/raw/. Nothing here touches the game textures; register.py turns the reviewed outputs into part sources.
"""
import os
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
WORK = HERE.parent
ROOT = WORK.parents[2]
HEAD_BOX = (424, 0, 680, 256)  # base_rgba.png pixels; 256 px square around the head

os.environ["OUT_DIR"] = str(HERE / "raw")
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from comfy_api import qwen  # noqa: E402

RGBA = ("This is an RGBA image with transparency. ", " The image has alpha channel and the background is transparent.")
JOBS = {
    "arm": (22411, "C", "Draw only the bare far-side arm of the woman in image1 as one isolated object on an empty transparent background: her complete "
            "natural-skin arm with a rounded shoulder at the top, the upper arm, the elbow, the forearm and the wrist, ending in a clean cut at "
            "the wrist with no hand. The arm hangs straight down, vertical, slightly relaxed at the elbow, seen from the side, tall in the frame. "
            "Exactly the same anime cel-shaded style, skin tone, line weight and upper-left lighting as image1. No hand, no body, no clothes, "
            "no jacket, no second arm, nothing else."),
    "half": (22421, "head", "Make her eye half closed, calm and half-lidded: the upper eyelid comes down and covers the upper half of the iris, with the "
             "same dark lash line. Same skin tone and shading. Keep everything else exactly unchanged."),
    "closed": (22422, "head", "Close her eye completely: the eyelid is shut, a single dark downward-curved lash line where the eye was, the eyelid in the "
               "same skin tone and shading. Keep everything else exactly unchanged."),
}


def main() -> None:
    head = HERE / "raw" / "head_reference.png"
    head.parent.mkdir(exist_ok=True)
    (head.parent / ".gdignore").touch()
    Image.open(WORK / "base_rgba.png").convert("RGBA").crop(HEAD_BOX).save(head)
    for name in sys.argv[1:] or JOBS:
        seed, ref, prompt = JOBS[name]
        image = head if ref == "head" else WORK / "04_stages" / f"{ref}.png"
        made = qwen(RGBA[0] + prompt + RGBA[1], images=[str(image)], seed=seed, resolution=1024, prefix=f"rin_field_{name}_s{seed}")[0]
        print(name, made, flush=True)


if __name__ == "__main__":
    main()
