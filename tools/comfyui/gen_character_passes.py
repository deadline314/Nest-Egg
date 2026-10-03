"""Generate the two full-body illustrations (body / armor) that cut_parts.py slices into part textures.

Usage (ComfyUI running, reference folder from rig_reference.tscn --zoom=24):
    python gen_character_passes.py --ref <ref_dir> --seed 5 --prefix rin
Outputs <prefix>_body_s<seed>_0.png and <prefix>_armor_s<seed>_0.png in OUT_DIR (see comfy_api.py).
"""
import argparse
import time

from comfy_api import qwen

STYLE = ("Redraw the reference image as finished anime cel-shaded character art in the style of Studio Trigger's Cyberpunk Edgerunners: "
         "flat colors, bold clean black outlines, hard-edged two-tone shading, saturated neon accents. "
         "IMPORTANT: keep the reference's exact silhouette, super-deformed game-sprite proportions (big head, about one quarter of total height, "
         "short torso and short limbs), pose, and the position of every body part. Do not make the body taller or the head smaller. Side view, facing right. ")
RIN = ("An adult woman mercenary. Long white hair in a high ponytail with hot-pink dyed tips, cyan glowing eyes, serious expression. "
       "Her right arm is a chrome military cybernetic prosthetic. She wears a dark navy techwear coat (only its inner lining is magenta) with thin cyan neon trim, "
       "a black bodysuit, black combat boots with glowing pink soles")
TAIL = ". Plain flat light-grey background, no text."
ARMOR = ", and clean white armor plates on the shoulder, the chest, the forearm and the knee"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--seed", type=int, default=5)
    ap.add_argument("--prefix", default="rin")
    ap.add_argument("--steps", type=int, default=25)
    ap.add_argument("--resolution", type=int, default=1024, help="Qwen edit works at ~resolution^2 pixels; 1536 gives ~1248x1856")
    args = ap.parse_args()
    for name, extra in (("body", ""), ("armor", ARMOR)):
        t = time.time()
        paths = qwen(STYLE + RIN + extra + TAIL, images=[f"{args.ref}/{name}_flat.png"], seed=args.seed, steps=args.steps, resolution=args.resolution,
                     prefix=f"{args.prefix}_{name}_s{args.seed}")
        print(name, paths[0], f"{time.time() - t:.0f}s", flush=True)


if __name__ == "__main__":
    main()
