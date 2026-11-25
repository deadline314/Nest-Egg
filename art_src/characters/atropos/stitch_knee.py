"""Continue the original trouser edge across Atropos's knee bend.

The inner edge is just short of both warped pieces at deep flexion. Restore
overlap using the adjacent original cloth, within five source pixels of the
inner edge. The original layer and all other joints remain untouched.
"""

from pathlib import Path

from PIL import Image


def rebuild(work: Path) -> None:
    original = Image.open(work / "base_rgba.png").convert("RGBA")
    part_path = work / "07_refined" / "leg_lower.png"
    part = Image.open(part_path).convert("RGBA")
    if original.size != (1037, 1516) or part.size != original.size:
        raise ValueError(f"Atropos knee continuation expects matching native source layers: {work}")

    changed = 0
    for y in range(1047, 1073):
        edge = next((x for x in range(399, 432) if original.getpixel((x, y))[3] >= 128), None)
        if edge is None:
            raise ValueError(f"Atropos trouser edge missing at source row {y}")
        width = max(0, 5 - abs(y - 1059) // 2)
        color = original.getpixel((edge + 1, y))[:3]
        for x in range(edge - width, edge):
            alpha = 190 if x == edge - width else 255
            if part.getpixel((x, y))[3] < alpha:
                part.putpixel((x, y), (*color, alpha))
                changed += 1

    if changed:
        part.save(part_path)
    print(f"Atropos knee: extended the original cloth into {changed} local source pixels")


if __name__ == "__main__":
    rebuild(Path(__file__).resolve().parent)
