"""Rebuild Yong's original baton texture from the checked-in drawing."""

from pathlib import Path

from PIL import Image, ImageDraw


def draw_baton() -> Image.Image:
    image = Image.new("RGBA", (96, 20))
    draw = ImageDraw.Draw(image)
    ink = "#211e20"

    # The narrow handle, captive collar and weighted cap share one silhouette.
    draw.polygon([(0, 7), (4, 5), (21, 5), (25, 6), (64, 6), (67, 4),
                  (90, 4), (95, 7), (95, 13), (91, 16), (71, 16), (67, 14),
                  (25, 14), (20, 15), (4, 15), (0, 13)], fill=ink)
    draw.polygon([(2, 8), (5, 7), (22, 7), (25, 8), (25, 12), (21, 13), (4, 13), (2, 12)],
                 fill="#59443a")
    for x in (4, 9, 14, 19):
        draw.line([(x, 12), (x + 3, 7)], fill="#836958", width=1)

    draw.polygon([(22, 7), (66, 7), (70, 6), (89, 6), (93, 8), (93, 12),
                  (90, 14), (72, 14), (68, 12), (22, 12)], fill="#555955")
    draw.polygon([(24, 8), (70, 8), (72, 7), (89, 7), (92, 9), (74, 9), (69, 10), (24, 10)],
                 fill="#91958b")
    draw.line([(27, 12), (66, 12)], fill="#414742")
    draw.line([(76, 13), (87, 13), (91, 11)], fill="#3b403a")
    draw.rectangle((7, 5, 13, 14), fill="#393332", outline=ink)
    draw.line([(8, 6), (12, 6)], fill="#88877c")
    draw.point((10, 9), fill="#afac9b")

    for start, end in (((34, 8), (37, 9)), ((48, 10), (50, 11)), ((61, 8), (64, 8)),
                       ((78, 8), (80, 9)), ((85, 11), (87, 12))):
        draw.line([start, end], fill="#b0aca0", width=1)
    return image


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    draw_baton().save(root / "art/weapons/yong_baton.png", optimize=True)
