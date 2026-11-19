"""Draw the folded clear umbrella for the reception office."""

from pathlib import Path

from PIL import Image, ImageDraw


def draw_umbrella() -> Image.Image:
    image = Image.new("RGBA", (80, 164))
    draw = ImageDraw.Draw(image)
    ink = (27, 39, 50, 255)
    steel = (84, 106, 120, 245)
    edge = (154, 180, 187, 222)
    seam = (79, 119, 132, 173)
    pvc = (201, 222, 225, 54)

    # The hook wraps around the desk's right rim, slightly above the clear fabric.
    hook = [(52, 29), (56, 19), (53, 11), (44, 7), (36, 8), (30, 14), (30, 22)]
    draw.line(hook, fill=ink, width=8, joint="curve")
    draw.line([(52, 24), (53, 18), (50, 13), (44, 10), (36, 12)], fill=steel, width=3, joint="curve")
    draw.line([(52, 25), (46, 52), (28, 143), (24, 158)], fill=ink, width=4)
    draw.line([(53, 26), (45, 57), (29, 141)], fill=steel, width=1)

    outside = [(44, 39), (56, 43), (60, 56), (54, 70), (46, 91), (32, 126),
               (26, 151), (19, 146), (20, 130), (25, 107), (29, 82), (33, 58)]
    draw.polygon(outside, fill=pvc, outline=seam, width=2)
    draw.polygon([(46, 42), (51, 51), (45, 77), (35, 106), (26, 143), (25, 128),
                  (30, 95), (34, 67)], fill=(196, 218, 224, 83))
    draw.line([(36, 59), (32, 87), (26, 119), (23, 140)], fill=edge, width=2)
    draw.line([(55, 55), (47, 78), (34, 118), (27, 145)], fill=steel, width=2)
    draw.line([(44, 50), (41, 69), (32, 105), (26, 134)], fill=(173, 205, 214, 147), width=2)
    draw.polygon([(28, 87), (49, 94), (47, 101), (27, 94)], fill=ink)
    draw.line([(30, 89), (47, 95)], fill=steel, width=2)
    draw.line([(24, 149), (24, 159)], fill=ink, width=3)
    draw.point((24, 159), fill=edge)
    return image


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    draw_umbrella().save(root / "art/environment/stages/ch3_ye_clear_umbrella.png", optimize=True)
