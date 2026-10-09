"""Check the part textures of built characters for the usual cutting mistakes, with the exact place of each one (NE-90).

    python tools/comfyui/check_parts.py [id ...] [--normals]      (no id = every folder in art/characters)

What it looks for, per texture in art/characters/<id>/character.json:
  empty        the picture is fully transparent, or has almost no pixels (a failed cut)
  holes        enclosed transparent holes of 40 px or more (and thicker than a hair-thin sliver): something that hid the part (an arm in front of the torso) and was not
               filled in, so the background shows through when the limb moves away. Small holes can be legitimate (a hair loop)
  fragments    detached pieces of 6 px or more that are not the main piece: a sliver of thigh left behind an arm, which then floats
               beside the leg while it runs
  far pivot    the pivot (the joint the part turns around) is farther from the part's pixels than 60% of the part's own size (and 40 texture px):
               wrong joint or cut
  glow         a glow layer that is missing, or has fewer than 25 lit pixels (cut_layers.py no longer writes fully empty ones)
  normals      (--normals, after the `normals` step) a part without its _n.png
Output: "OK <id>" or "WARN <id>" followed by one line per problem. Exit code 1 when anything was reported, so a batch can stop on it.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
MIN_HOLE = 40
MIN_FRAGMENT = 6
MIN_PIXELS = 150
MIN_GLOW_PIXELS = 25
FAR_PIVOT = 40.0
FAR_PIVOT_RATIO = 0.6  # of the longer side of the part


def check_character(char_id: str, normals: bool = False) -> list[str]:
    """Return one message per problem found in art/characters/<char_id>/ (an empty list = fine)."""
    char_dir = ROOT / "art/characters" / char_id
    try:
        definition = json.loads((char_dir / "character.json").read_text(encoding="utf8"))
    except (OSError, ValueError) as ex:
        return [f"character.json: cannot read ({ex})"]
    problems: list[str] = []
    used = {p.get("texture") for p in definition.get("parts", [])}
    used.update(p["grip_texture"] for p in definition.get("parts", []) if isinstance(p.get("grip_texture"), str))
    for name, tex in definition.get("textures", {}).items():
        if name not in used and not name.endswith("_dmg"):
            problems.append(f"{name}: no part uses this texture")
        path = char_dir / str(tex.get("file", ""))
        if not path.exists():
            problems.append(f"{name}: file {tex.get('file')} is missing")
            continue
        rgba = np.asarray(Image.open(path).convert("RGBA"))
        solid = rgba[..., 3] > 20
        pixels = int(solid.sum())
        if pixels < MIN_PIXELS:
            problems.append(f"{name}: empty ({pixels} px)")
            continue
        firm = rgba[..., 3] > 127  # holes are judged on the firm pixels: a few half-transparent edge pixels around a notch are anti-aliasing, not a hole
        holes, hole_count = ndimage.label(ndimage.binary_fill_holes(firm) & ~firm)
        # a hair-thin sliver along two outlines (the warp that turns the limb upright can leave one) is not a hole: it must survive an erosion
        sizes = [int((holes == i).sum()) for i in range(1, hole_count + 1)
                 if ndimage.binary_erosion(holes == i).any()]
        big = [s for s in sizes if s >= MIN_HOLE]
        if big:
            problems.append(f"{name}: {len(big)} enclosed hole(s), largest {max(big)} px")
        pieces, piece_count = ndimage.label(solid, structure=np.ones((3, 3)))
        if piece_count > 1:
            sizes = sorted((int((pieces == i).sum()) for i in range(1, piece_count + 1)), reverse=True)
            loose = [s for s in sizes[1:] if s >= MIN_FRAGMENT]
            if loose:
                problems.append(f"{name}: {len(loose)} detached fragment(s) {loose[:4]} px next to the main piece of {sizes[0]} px")
        pivot = tex.get("pivot")
        if pivot:
            ys, xs = np.nonzero(solid)
            dx = max(xs.min() - pivot[0], 0, pivot[0] - xs.max())
            dy = max(ys.min() - pivot[1], 0, pivot[1] - ys.max())
            far = (dx * dx + dy * dy) ** 0.5
            if far > max(FAR_PIVOT, FAR_PIVOT_RATIO * max(xs.max() - xs.min(), ys.max() - ys.min())):
                problems.append(f"{name}: the pivot {pivot} is {far:.0f} px away from the part's pixels")
        if "glow" in tex:
            glow_path = char_dir / str(tex["glow"])
            if not glow_path.exists():
                problems.append(f"{name}: glow file {tex['glow']} is missing")
            else:
                lit = int((np.asarray(Image.open(glow_path).convert("RGBA"))[..., 3] > 8).sum())
                if lit < MIN_GLOW_PIXELS:
                    problems.append(f"{name}: the glow layer has only {lit} lit px (drop it from spec.glow, or lower spec.glow_threshold)")
        if normals and not path.with_name(path.stem + "_n.png").exists():
            problems.append(f"{name}: no normal map ({path.stem}_n.png)")
    return problems


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ids = args or sorted(p.name for p in (ROOT / "art/characters").iterdir() if (p / "character.json").exists())
    failed = False
    for char_id in ids:
        problems = check_character(char_id, "--normals" in sys.argv)
        print(("WARN " if problems else "OK   ") + char_id)
        for problem in problems:
            print("     ", problem)
        failed |= bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
