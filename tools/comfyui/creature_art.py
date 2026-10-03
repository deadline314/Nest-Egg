"""Draw one creature picture with Qwen Image 2.1 (transparent background, side view facing right) for the non-humanoid enemies.

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/creature_art.py --id salvage_arm --part body --seed 3 \
        --prompt "<English description of just this picture>" [--size 832 1216]

Output: art_src/creatures/<id>/<part>_s<seed>.png (RGBA). `part` is a free name: "design" (the whole creature), "body", "tentacle", "wing", "leg", "tail" ...
The prompt gets the style line in front and the RGBA wrapper around it (the same wrapper the humanoid pipeline uses). Existing files are kept unless --force.
Needs ComfyUI running (127.0.0.1:8188).
"""
import argparse
import os
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
STYLE = ("Anime cel-shaded creature art in the style of Studio Trigger's Cyberpunk Edgerunners: flat colors, bold clean black outlines, "
         "hard-edged two-tone shading, saturated neon accents, dark cyberpunk mood. Strict side view facing right. ")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--part", default="design")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--size", type=int, nargs=2, default=[832, 1216])
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    out_dir = ROOT / "art_src/creatures" / args.id
    out_dir.mkdir(parents=True, exist_ok=True)
    (ROOT / "art_src/creatures/.gdignore").touch()
    target = out_dir / f"{args.part}_s{args.seed}.png"
    if target.exists() and not args.force:
        print(f"keep {target.relative_to(ROOT)}")
        return
    os.environ["OUT_DIR"] = str(ROOT / "art_src/creatures/_gen")
    sys.path.insert(0, str(HERE))
    from comfy_api import qwen
    t = time.time()
    prompt = "This is an RGBA image with transparency. " + STYLE + args.prompt.strip() + " The image has alpha channel and the background is transparent."
    made = qwen(prompt, w=args.size[0], h=args.size[1], seed=args.seed, prefix=f"creature_{args.id}_{args.part}_s{args.seed}")[0]
    shutil.copy(made, target)
    print(f"made {target.relative_to(ROOT)} ({time.time() - t:.0f}s)")


if __name__ == "__main__":
    main()
