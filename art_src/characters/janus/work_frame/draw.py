"""Rebuild the gatekeeper's work frame atlas from original pixel drawings."""

from pathlib import Path

from PIL import Image, ImageDraw


INK = "#191d24"
SHADOW = "#2d3640"
STEEL = "#54616c"
EDGE = "#87928e"
RUST = "#827059"
WARNING = "#b69a53"


def frame(draw):
    draw.polygon([(8, 12), (12, 4), (73, 4), (81, 8), (77, 13), (24, 13),
                  (20, 25), (20, 228), (25, 244), (28, 255), (5, 255), (7, 240)], fill=INK)
    draw.polygon([(11, 17), (15, 8), (73, 7), (76, 9), (19, 10), (15, 22),
                  (16, 231), (20, 246), (20, 251), (10, 251)], fill=STEEL)
    draw.line([(13, 24), (12, 229)], fill=EDGE, width=2)
    draw.line([(17, 24), (17, 226)], fill=SHADOW, width=2)
    for y in (78, 158):
        draw.polygon([(13, y), (91, y), (97, y + 3), (94, y + 8), (13, y + 8)], fill=INK)
        draw.line([(21, y + 2), (92, y + 2)], fill=STEEL, width=2)
        draw.rectangle((28, y + 2, 32, y + 6), fill=RUST)
        draw.rectangle((88, y + 1, 92, y + 6), fill=SHADOW)
    for y in (44, 122, 203, 248):
        draw.rectangle((9, y, 17, y + 3), fill=INK)
        draw.line([(10, y), (15, y)], fill=EDGE)


def shield(draw, damaged=False):
    face = SHADOW if damaged else STEEL
    draw.polygon([(5, 1), (25, 1), (31, 10), (30, 126), (24, 134),
                  (6, 134), (1, 127), (0, 11)], fill=INK)
    draw.polygon([(6, 4), (24, 4), (28, 12), (27, 124), (23, 131),
                  (7, 131), (4, 125), (3, 13)], fill=face)
    draw.line([(7, 8), (6, 122), (9, 128)], fill=WARNING, width=2)
    draw.line([(25, 15), (24, 119)], fill=SHADOW, width=2)
    for y in (16, 48, 80, 112):
        draw.line([(10, y + 4), (20, y)], fill=RUST, width=2)
    for x, y in ((8, 7), (24, 12), (8, 127), (23, 126)):
        draw.rectangle((x, y, x + 2, y + 2), fill=INK)
    if damaged:
        crack = [(8, 14), (20, 41), (13, 65), (20, 92), (14, 111), (18, 132)]
        draw.line(crack, fill=INK, width=4)
        draw.line([(x + 2, y) for x, y in crack], fill=EDGE)
        draw.line([(14, 65), (24, 73), (27, 86)], fill=INK, width=2)


def communicator(draw, damaged=False):
    antenna = [(19, 43), (19, 18), (7, 8)] if damaged else [(19, 43), (19, 4)]
    draw.line(antenna, fill=INK, width=5)
    if not damaged:
        draw.line([(19, 9), (19, 39)], fill=EDGE)
        draw.rectangle((16, 33, 22, 41), fill=RUST, outline=INK)
    draw.polygon([(5, 41), (33, 41), (39, 48), (39, 88), (34, 94),
                  (5, 94), (0, 88), (0, 47)], fill=INK)
    draw.polygon([(7, 45), (31, 45), (35, 50), (35, 86), (32, 90),
                  (7, 90), (4, 86), (4, 50)], fill=SHADOW if damaged else STEEL)
    draw.line([(7, 51), (7, 86)], fill=EDGE, width=2)
    draw.polygon([(11, 54), (29, 54), (32, 59), (32, 70), (12, 70)], fill=INK)
    for y in range(74, 89, 4):
        draw.line([(13, y), (29, y)], fill=SHADOW, width=2)
    if damaged:
        draw.line([(21, 45), (15, 56), (26, 65), (22, 77)], fill=INK, width=3)
        draw.line([(22, 79), (33, 83), (31, 90)], fill=RUST, width=2)
    else:
        draw.line([(14, 69), (29, 69)], fill=EDGE)


def scanner(draw):
    draw.polygon([(4, 17), (23, 13), (82, 8), (90, 1), (104, 1), (111, 7),
                  (110, 20), (105, 24), (89, 24), (81, 20), (25, 25), (6, 28)], fill=INK)
    draw.polygon([(8, 18), (27, 16), (84, 10), (91, 5), (102, 5), (107, 9),
                  (106, 18), (103, 21), (91, 21), (83, 17), (26, 22), (9, 24)], fill=STEEL)
    draw.line([(24, 17), (83, 11)], fill=EDGE, width=2)
    draw.rectangle((30, 16, 36, 22), fill=SHADOW, outline=INK)
    draw.rectangle((66, 12, 72, 18), fill=SHADOW, outline=INK)
    draw.ellipse((94, 8, 104, 17), fill=INK, outline=RUST, width=2)
    draw.point((99, 12), fill=EDGE)


def pin(draw):
    draw.polygon([(3, 2), (13, 2), (15, 6), (15, 18), (12, 21),
                  (4, 21), (0, 18), (0, 5)], fill=INK)
    draw.rectangle((4, 5, 12, 17), fill=STEEL)
    draw.rectangle((6, 7, 10, 14), fill=INK)
    draw.line([(4, 6), (4, 16)], fill=EDGE)


def draw_atlas() -> Image.Image:
    sheet = Image.new("RGBA", (256, 272))
    slots = (
        ((4, 4), (100, 260), frame),
        ((112, 4), (32, 136), shield),
        ((152, 4), (32, 136), lambda draw: shield(draw, True)),
        ((192, 4), (40, 96), communicator),
        ((192, 108), (40, 96), lambda draw: communicator(draw, True)),
        ((112, 150), (112, 32), scanner),
        ((112, 194), (16, 24), pin),
    )
    for point, size, paint in slots:
        piece = Image.new("RGBA", size)
        paint(ImageDraw.Draw(piece))
        sheet.paste(piece, point)
    return sheet


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[4]
    draw_atlas().save(root / "art/weapons/janus_work_frame.png", optimize=True)
