"""Build Folio's optional handwritten close-up from the released rig artwork."""

from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont


def draw_closeup(root: Path) -> Image.Image:
    parts = root / "art/characters/ye/parts"
    with Image.open(parts / "arm_lower.png") as raw:
        sleeve = raw.convert("RGBA").transpose(Image.Transpose.ROTATE_90)
    ImageDraw.Draw(sleeve).polygon([(178, 64), (188, 59), (193, 58), (193, 86), (178, 86)], fill=(0, 0, 0, 0))
    with Image.open(parts / "hand.png") as raw:
        hand = raw.convert("RGBA")
    surface = ImageDraw.Draw(hand)
    surface.polygon([(24, 20), (52, 15), (66, 20), (64, 48), (54, 57),
                     (28, 55), (19, 47), (19, 33)], fill="#c9af99")
    surface.polygon([(24, 48), (37, 53), (56, 52), (66, 46), (55, 57),
                     (28, 55), (19, 47)], fill="#b99d89")
    surface.line([(26, 20), (45, 17), (53, 16)], fill="#d3b9a4")

    # Build at three times the source contour resolution so ink strokes stay legible in the insert.
    upscale = 3
    compose = Image.new("RGBA", (300 * upscale, 102 * upscale))
    compose.alpha_composite(sleeve.resize((sleeve.width * upscale, sleeve.height * upscale), Image.Resampling.BICUBIC),
                            (0, 7 * upscale))
    compose.alpha_composite(hand.resize((hand.width * upscale, hand.height * upscale), Image.Resampling.BICUBIC),
                            (174 * upscale, 11 * upscale))
    compose = compose.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    ink = ImageDraw.Draw(compose)
    font = ImageFont.truetype(str(root / "art/fonts/NotoSansTC-Regular-subset.ttf"), 21)
    x = 62 * upscale
    for glyph, wobble in zip("他叫阿翰。你愛他。", (0, -2, 1, -1, 0, 1, -1, 0, 0)):
        y = 44 * upscale + wobble
        if glyph == "。":
            ink.ellipse((x + 1, y - 4, x + 4, y - 1), outline="#24374b", width=1)
            x += 10
        else:
            ink.text((x, y), glyph, fill="#24374b", font=font, anchor="ls")
            x += 22
    return compose


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    if len(sys.argv) > 1:
        root = Path(sys.argv[1]).resolve()
    draw_closeup(root).save(Path(sys.argv[2]) if len(sys.argv) > 2 else
                            root / "art/environment/stages/ch3_ye_handwriting.png", optimize=True)
