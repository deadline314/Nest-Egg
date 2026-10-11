"""Draw the source picture of a humanoid character in the house style and the neutral standing pose the rig needs (Qwen Image 2.1).

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/field_design.py --id egret --seed 21911 [--size 832 1216]

Reads   art_src/characters/<id>/01_design/character.txt   who this is: age, build, face, each piece of clothing with its wear. Plain prose.
Writes  01_design/design_s<seed>.png, 01_design/prompt.txt (the full prompt that was sent), base_rgba.png (only when it does not exist
        yet, or with --adopt: looking at the picture comes first)
One picture per call; a finished job (same prompt, seed, size) is reused. Next step: field_spec.py.

The style and pose text is shared by every character so that the cast reads as one production. Why it says what it says (NE-218):
  pose    Mid-stride sources carry the walk into every pose: the shoulder is rotated back, the arm hangs from the back edge of the torso,
          and standing still the figure looks chest-out with both arms behind it. The source stands still, spine vertical, the near arm
          straight down beside the thigh. Only the far foot is half a step ahead, so the far shin can be told from the near one.
  style   The same sentence the first cast was drawn with, minus "saturated neon accents": the world is rain, rust and work clothes, and
          neon is one small accent per character at most.
  finish  What makes a picture read as machine-made is polish: airbrushed gradients, glossy cloth, a symmetrical pretty face, ornaments
          that mean nothing, perfectly clean clothes. The closing lines ask for the opposite in plain positive words (this pipeline runs
          without a negative prompt). Do not add quality words ("highly detailed", "masterpiece", "4K"): they pull toward that polish.
character.txt should name mundane, functional clothes that fit the harbour (rain gear, work wear, patched and faded), a face with
something uneven about it, and no more than the details the character needs.
"""
import argparse
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STYLE = ("Anime cel-shaded character art in the style of Studio Trigger's Cyberpunk Edgerunners: flat muted colors, bold clean black "
         "outlines, hard-edged two-tone shading, at most one small lit accent. Full body, strict side view facing right, the whole figure from "
         "the top of the head to the soles inside the frame, tall in the frame: the figure fills nine tenths of the picture height. ")
POSE = ("The character stands upright and still, like a model sheet: weight evenly on both feet, hips and shoulders level, the spine vertical, "
        "the chest not pushed out and the lower back not arched, the head level. The near arm hangs straight down beside the thigh with an "
        "open empty hand; it is not swept back. The far arm is hidden behind the torso. The feet are a small step apart with the far foot "
        "half a step ahead, so the far shin and the far shoe show in front of the near leg. ")
FINISH = (" Empty hands. Uneven rough hand-inked linework with varied line weight, gritty grime and fabric wrinkles where the cloth bends, "
          "slightly asymmetrical, lived-in and worn, matte not glossy, not airbrushed, no idealized perfect face. Few large plain shapes, no "
          "decorative details beyond the ones described. Even overcast light, no glow, no bloom, no text.")
RGBA = ("This is an RGBA image with transparency. ", " The image has alpha channel and the background is transparent.")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--size", type=int, nargs=2, default=[832, 1216], help="the first cast was drawn at 832x1216; the line weight follows the size")
    ap.add_argument("--adopt", action="store_true", help="make this picture base_rgba.png even when one exists")
    args = ap.parse_args()
    work = ROOT / "art_src/characters" / args.id
    design = work / "01_design"
    character = design / "character.txt"
    if not character.exists():
        raise SystemExit(f"[field_design] {character} is missing: write who this character is first")
    prompt = STYLE + POSE + character.read_text(encoding="utf8").strip() + FINISH
    sys.path.insert(0, str(Path(__file__).parent))
    from comfy_api import qwen
    started = time.time()
    made = qwen(RGBA[0] + prompt + RGBA[1], w=args.size[0], h=args.size[1], seed=args.seed, prefix=f"{args.id}_design_s{args.seed}")[0]
    (work / ".gdignore").touch()
    target = design / f"design_s{args.seed}.png"
    shutil.copy(made, target)
    (design / "prompt.txt").write_text(prompt + "\n", encoding="utf8")
    base = work / "base_rgba.png"
    if args.adopt or not base.exists():
        shutil.copy(target, base)
    print(f"  {target.relative_to(ROOT)} ({time.time() - started:.0f}s){' -> base_rgba.png' if args.adopt or not base.exists() else ''}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
