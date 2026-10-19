"""關卡固定物件的賽璐璐貼圖：門、梯子、提示牌、開關箱、可擊碎牆、閘門（BG-21）。

這些東西又小又規則（門 28×48、提示牌 16×24 世界像素），生成模型畫不出乾淨的直線與可平鋪的邊，
所以和管線、地形材質一樣用程式畫：平塗、深色墨線、左上亮邊、右下硬邊陰影。每個世界像素畫 8 個貼圖像素。
會發光的部分（門上的狀態燈、提示牌的驚嘆號、開關的指示燈）不畫進貼圖，由遊戲依狀態用自發光疊上去。

用法（在專案根目錄）：
  python tools/assets/cel_fixtures.py            # 重畫全部，寫到 art/environment/fixtures/
  python tools/assets/cel_fixtures.py --sheet <png>   # 另外輸出一張放大的樣本一覽
重跑結果固定（沒有亂數）。畫完跑 python tools/assets/texture_import.py 再匯入。
"""
import argparse
import os

from PIL import Image, ImageDraw

SCALE = 8
OUT = os.path.join("art", "environment", "fixtures")

INK = (11, 14, 22, 255)
STEEL_DARK = (38, 46, 60, 255)
STEEL = (58, 70, 88, 255)
STEEL_LIGHT = (92, 108, 130, 255)
STEEL_PALE = (150, 166, 186, 255)
GLASS = (14, 22, 34, 255)
GLASS_GLINT = (70, 120, 150, 255)
HAZARD = (226, 179, 60, 255)
HAZARD_DARK = (24, 22, 20, 255)
SCREEN = (12, 24, 34, 255)
BRICK = (62, 72, 86, 255)
BRICK_LIGHT = (84, 96, 112, 255)
BRICK_DARK = (40, 48, 60, 255)
PATCH = (104, 96, 84, 255)
PATCH_LIGHT = (136, 126, 108, 255)
CLEAR = (0, 0, 0, 0)


class Sheet:
    """以世界像素為單位作畫的畫布。"""

    def __init__(self, width, height):
        self.size = (width, height)
        self.image = Image.new("RGBA", (width * SCALE, height * SCALE), CLEAR)
        self.draw = ImageDraw.Draw(self.image)

    def rect(self, x0, y0, x1, y1, fill):
        if round(x1 * SCALE) <= round(x0 * SCALE) or round(y1 * SCALE) <= round(y0 * SCALE):
            return
        self.draw.rectangle([round(x0 * SCALE), round(y0 * SCALE), round(x1 * SCALE) - 1, round(y1 * SCALE) - 1], fill=fill)

    def panel(self, x0, y0, x1, y1, fill, light, dark, ink=0.5, bevel=0.5):
        """有墨線、左上亮邊、右下暗邊的平塗方塊。"""
        self.rect(x0, y0, x1, y1, INK)
        self.rect(x0 + ink, y0 + ink, x1 - ink, y1 - ink, fill)
        self.rect(x0 + ink, y0 + ink, x1 - ink, y0 + ink + bevel, light)
        self.rect(x0 + ink, y0 + ink, x0 + ink + bevel, y1 - ink, light)
        self.rect(x0 + ink, y1 - ink - bevel, x1 - ink, y1 - ink, dark)
        self.rect(x1 - ink - bevel, y0 + ink, x1 - ink, y1 - ink, dark)

    def rivet(self, x, y):
        self.rect(x - 0.4, y - 0.4, x + 0.4, y + 0.4, INK)
        self.rect(x - 0.25, y - 0.25, x + 0.15, y + 0.15, STEEL_PALE)

    def polygon(self, points, fill):
        self.draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=fill)

    def hazard(self, x0, y0, x1, y1, stripe=2.0):
        """黃黑斜紋警示條。斜紋先畫在另一張圖上再裁進範圍，不會蓋到範圍外的東西。"""
        box = (round(x0 * SCALE), round(y0 * SCALE), round(x1 * SCALE), round(y1 * SCALE))
        width, height = box[2] - box[0], box[3] - box[1]
        strip = Image.new("RGBA", (width, height), HAZARD)
        pen = ImageDraw.Draw(strip)
        step = round(stripe * SCALE)
        x = -height
        while x < width:
            pen.polygon([(x, height), (x + step, height), (x + step + height, 0), (x + height, 0)], fill=HAZARD_DARK)
            x += step * 2
        self.image.paste(strip, box[:2])

    def save(self, name):
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name + ".png")
        self.image.save(path)
        return path


def door():
    """鋼製防盜門：門框、門板、觀察窗、把手、底部警示踢腳板。狀態燈的燈座在門框頂端正中央。"""
    s = Sheet(28, 48)
    s.panel(0, 0, 28, 48, STEEL_DARK, STEEL, INK, bevel=0.75)
    s.rect(11.5, 0.5, 16.5, 2.5, INK)                      # 狀態燈燈座
    s.panel(2.5, 3.5, 25.5, 47.5, STEEL, STEEL_LIGHT, STEEL_DARK, bevel=0.75)
    for y in (17.0, 31.0):                                  # 門板的壓條
        s.rect(4, y, 24, y + 0.5, STEEL_DARK)
        s.rect(4, y + 0.5, 24, y + 1.0, STEEL_LIGHT)
    s.panel(8, 7, 20, 12, GLASS, GLASS, GLASS)              # 觀察窗
    s.polygon([(9.5, 11), (12, 8), (13, 8), (10.5, 11)], GLASS_GLINT)
    s.panel(20.5, 22, 23, 29, STEEL_PALE, (210, 220, 232, 255), STEEL_LIGHT)  # 把手
    for x, y in ((4.5, 5.5), (23.5, 5.5), (4.5, 39.0), (23.5, 39.0)):
        s.rivet(x, y)
    s.hazard(3, 41.5, 25, 47)                               # 踢腳板
    s.rect(3, 41, 25, 41.5, INK)
    return s


def ladder():
    """梯子的一段（20×20，上下可平鋪）：兩支扶手、兩根橫桿，間距 10 像素。"""
    s = Sheet(20, 20)
    for x in (2.5, 15.0):
        s.rect(x, 0, x + 2.5, 20, INK)
        s.rect(x + 0.5, 0, x + 2.0, 20, STEEL_LIGHT)
        s.rect(x + 0.5, 0, x + 1.0, 20, STEEL_PALE)
    for y in (3.5, 13.5):
        s.rect(4.5, y, 15.5, y + 2.5, INK)
        s.rect(4.5, y + 0.5, 15.5, y + 2.0, STEEL_LIGHT)
        s.rect(4.5, y + 0.5, 15.5, y + 1.0, STEEL_PALE)
    return s


def hint_sign():
    """提示牌：底座、立柱、有邊框的螢幕。螢幕上的驚嘆號由遊戲用自發光畫。"""
    s = Sheet(16, 24)
    s.panel(3, 22, 13, 24, STEEL_DARK, STEEL, INK, ink=0.4, bevel=0.4)       # 底座
    s.rect(7, 12, 9, 22, INK)                                                 # 立柱
    s.rect(7.4, 12, 8.6, 22, STEEL_LIGHT)
    s.rect(7.4, 12, 7.9, 22, STEEL_PALE)
    s.polygon([(5.5, 22), (7, 19.5), (7, 22)], INK)                           # 斜撐
    s.polygon([(10.5, 22), (9, 19.5), (9, 22)], INK)
    s.panel(0.5, 1, 15.5, 12.5, STEEL, STEEL_LIGHT, STEEL_DARK, bevel=0.6)   # 外框
    s.panel(2, 2.5, 14, 11, SCREEN, SCREEN, SCREEN, ink=0.4, bevel=0.0)      # 螢幕
    s.rivet(1.4, 1.9)
    s.rivet(14.6, 1.9)
    return s


def switch_box(on):
    """地面的開關箱：箱體、拉桿（開在左、關在右，和遊戲原本的方向一致）、接進地面的管線。指示燈的位置在箱體正面中央。"""
    s = Sheet(20, 20)
    s.rect(15.5, 9, 17.5, 20, INK)                          # 管線：從箱側往下接進地面
    s.rect(16.0, 9, 17.0, 20, STEEL_LIGHT)
    s.rect(13.5, 8.5, 17.5, 10.5, INK)
    s.rect(13.5, 9.0, 17.0, 10.0, STEEL_LIGHT)
    s.panel(3, 18.5, 14.5, 20, STEEL_DARK, STEEL, INK, ink=0.4, bevel=0.4)  # 底座
    s.panel(2, 6, 14, 19, STEEL, STEEL_LIGHT, STEEL_DARK, bevel=0.6)        # 箱體
    s.rect(4, 8, 12, 9.5, INK)                              # 拉桿的滑槽
    s.panel(5.5, 11.5, 10.5, 16.5, STEEL_DARK, STEEL_DARK, INK, ink=0.4, bevel=0.0)  # 指示燈的燈座
    base = (8.0, 8.75)
    tip = (3.5, 2.0) if on else (12.5, 2.0)
    side = 0.9
    s.polygon([(base[0] - side, base[1]), (base[0] + side, base[1]), (tip[0] + side, tip[1]), (tip[0] - side, tip[1])], INK)
    s.polygon([(base[0] - 0.4, base[1]), (base[0] + 0.4, base[1]), (tip[0] + 0.4, tip[1]), (tip[0] - 0.4, tip[1])], STEEL_PALE)
    s.panel(tip[0] - 1.6, tip[1] - 1.6, tip[0] + 1.6, tip[1] + 1.6, HAZARD, (250, 214, 110, 255), (160, 120, 30, 255), ink=0.4, bevel=0.4)
    s.rivet(3.2, 7.2)
    s.rivet(12.8, 17.8)
    return s


def breakable_wall():
    """可擊碎的牆（16×32，上下左右可平鋪）：和一般牆面不同的補磚牆，每一格寬都釘著一塊有裂縫的補板，看得出是弱點。
    牆通常只有一格寬，所以貼圖也只有一格寬，補板不會被切掉。"""
    s = Sheet(16, 32)
    s.rect(0, 0, 16, 32, BRICK_DARK)
    for row in range(4):
        y = row * 8
        if row % 2 == 0:
            spans = [(0.5, 15.5)]
        else:
            spans = [(0.0, 7.5), (8.5, 16.0)]                # 錯開半塊，左右接得起來
        for a, b in spans:
            s.rect(a, y + 0.5, b, y + 7.5, BRICK)
            s.rect(a, y + 0.5, b, y + 1.25, BRICK_LIGHT)
            s.rect(a, y + 6.75, b, y + 7.5, BRICK_DARK)
    s.panel(2.5, 9, 13.5, 23, PATCH, PATCH_LIGHT, (70, 64, 56, 255), bevel=0.6)   # 補板
    for x, y in ((4.0, 10.5), (12.0, 10.5), (4.0, 21.5), (12.0, 21.5)):
        s.rivet(x, y)
    # 補板上原本就有的裂縫
    s.draw.line([(6 * SCALE, 11 * SCALE), (9 * SCALE, 14 * SCALE), (7 * SCALE, 18 * SCALE), (10 * SCALE, 22 * SCALE)], fill=INK, width=4)
    return s


def gate_shutter():
    """閘門的捲門板（32×16，上下可平鋪）：橫向的鋼條，每條上亮下暗。"""
    s = Sheet(32, 16)
    s.rect(0, 0, 32, 16, STEEL_DARK)
    for y in (0, 4, 8, 12):
        s.rect(0, y, 32, y + 0.5, INK)
        s.rect(0, y + 0.5, 32, y + 1.5, STEEL_LIGHT)
        s.rect(0, y + 1.5, 32, y + 3.0, STEEL)
    for x in (0.0, 31.0):                                   # 兩側的導軌
        s.rect(x, 0, x + 1.0, 16, INK)
    return s


def crate(state="intact"):
    """Wood slats, steel corners and a shipping seal; rubble has its own silhouette."""
    wood = (118, 85, 57, 255)
    light = (161, 122, 80, 255)
    dark = (65, 47, 36, 255)
    if state == "broken":
        s = Sheet(32, 12)
        for points in [[(1, 9), (3, 7), (16, 9), (18, 11), (16, 12), (2, 12)],
                       [(8, 8), (12, 4), (14, 5), (12, 8), (24, 9), (25, 12), (21, 11)],
                       [(18, 9), (27, 5), (30, 6), (28, 8), (30, 11), (28, 12)]]:
            s.polygon(points, INK)
            s.polygon([(x, y - 0.6) for x, y in points], wood)
        s.polygon([(4, 8), (15, 10), (16, 10.5), (5, 8.5)], light)
        s.polygon([(19, 9), (27, 6), (28, 6.5), (20, 9.5)], light)
        s.panel(1, 8, 6, 12, STEEL, STEEL_PALE, STEEL_DARK)
        return s
    s = Sheet(32, 32)
    s.panel(0, 0, 32, 32, dark, light, INK)
    for y in range(2, 30, 6):
        s.panel(2, y, 30, y + 5.5, wood, light, dark, ink=0.25, bevel=0.35)
        s.rect(8 + y % 7, y + 2, 16 + y % 7, y + 2.3, dark)
    for x in (1.0, 27.0):
        s.panel(x, 1, x + 4, 31, STEEL, STEEL_LIGHT, STEEL_DARK, bevel=0.4)
        for y in (3, 15, 28):
            s.rivet(x + 2, y)
    s.polygon([(6, 25), (25, 5), (27, 7), (8, 27)], dark)
    s.polygon([(6, 24), (24, 5), (25, 6), (7, 25)], light)
    s.panel(12, 11, 21, 18, PATCH_LIGHT, (174, 162, 139, 255), PATCH, ink=0.3, bevel=0.2)
    for x in (14, 16, 17.5, 19):
        s.rect(x, 13, x + 0.4, 16, dark)
    if state == "damaged":
        s.polygon([(8, 4), (12, 11), (9, 18), (15, 25), (12, 30), (18, 25), (12, 17), (15, 10)], INK)
        s.polygon([(8, 4), (12, 11), (9, 18), (10, 16), (13, 10)], light)
        s.rect(22, 23, 28, 25, dark)
    return s


def barrel(state="intact"):
    """Stepped drum, recessed lid, steel bands and an unambiguous fuel pictogram."""
    red = (132, 56, 47, 255)
    red_light = (177, 82, 64, 255)
    red_dark = (70, 32, 33, 255)
    if state == "broken":
        s = Sheet(24, 12)
        s.polygon([(1, 11), (3, 4), (10, 1), (15, 6), (22, 4), (23, 12)], INK)
        s.polygon([(3, 10), (5, 5), (10, 3), (14, 8), (21, 6), (22, 11)], red)
        s.polygon([(3, 9), (10, 5), (13, 8), (20, 7), (21, 9), (12, 11)], STEEL_LIGHT)
        return s
    s = Sheet(24, 36)
    s.polygon([(3, 0), (21, 0), (24, 3), (24, 33), (21, 36), (3, 36), (0, 33), (0, 3)], INK)
    s.rect(1, 3, 23, 33, red_dark)
    s.rect(2, 4, 18, 33, red)
    s.rect(3, 4, 7, 33, red_light)
    s.panel(2, 1, 22, 5, STEEL_DARK, STEEL_LIGHT, INK, bevel=0.4)
    s.panel(3, 1.5, 8, 4, INK, STEEL, INK, ink=0.3, bevel=0.2)
    for y in (8, 27, 32):
        s.panel(1, y, 23, y + 2.5, STEEL, STEEL_LIGHT, STEEL_DARK, ink=0.3, bevel=0.3)
    s.polygon([(12, 12), (19, 22), (5, 22)], INK)
    s.polygon([(12, 13.5), (17, 21), (7, 21)], HAZARD)
    s.polygon([(12, 16), (10, 19), (12, 20.5), (14, 19.5), (13, 17), (12, 18)], INK)
    if state == "damaged":
        s.polygon([(18, 6), (14, 10), (18, 14), (15, 19), (22, 17), (19, 12), (22, 9)], red_dark)
        s.polygon([(18, 6), (14, 10), (18, 14), (16, 10)], red_light)
        s.rect(3, 29, 8, 30, INK)
    return s


def glass(state="intact"):
    """A bolted frame and a translucent pane, never an opaque cyan wall."""
    if state == "broken":
        s = Sheet(16, 12)
        for points in [[(0, 11), (4, 2), (7, 12)], [(6, 12), (12, 3), (14, 11)], [(11, 11), (16, 6), (15, 12)]]:
            s.polygon(points, STEEL_DARK)
            s.polygon([(x + 0.3, y - 0.3) for x, y in points], (108, 176, 188, 170))
        return s
    s = Sheet(16, 48)
    s.panel(0, 0, 16, 48, STEEL_DARK, STEEL_PALE, INK, ink=0.4, bevel=0.35)
    s.rect(2, 2, 14, 46, (22, 64, 78, 65))
    # Replace the opaque panel interior with genuine alpha.
    s.draw.rectangle([2 * SCALE, 2 * SCALE, 14 * SCALE - 1, 46 * SCALE - 1], fill=(22, 64, 78, 65))
    for x, y in ((1, 5), (15, 5), (1, 43), (15, 43)):
        s.rivet(x, y)
    for y in (10, 27):
        s.polygon([(3, y + 5), (11, y), (12, y + 1), (4, y + 6)], (138, 193, 204, 120))
    if state == "damaged":
        for line in [[(8, 20), (4, 10), (5, 3)], [(8, 20), (13, 16), (14, 7)],
                     [(8, 20), (6, 29), (10, 38), (8, 46)], [(8, 20), (13, 26), (14, 33)]]:
            s.draw.line([(x * SCALE, y * SCALE) for x, y in line], fill=(182, 223, 228, 220), width=4)
    return s


def lift_deck():
    s = Sheet(32, 6)
    s.panel(0, 0, 32, 6, STEEL, STEEL_PALE, STEEL_DARK, ink=0.3, bevel=0.5)
    s.hazard(6, 1.5, 26, 3.5, stripe=2)
    for x in (3, 29):
        s.rivet(x, 3)
    s.rect(5, 4.5, 27, 6, INK)
    return s


def lift_rail():
    s = Sheet(4, 16)
    s.rect(0, 0, 4, 16, INK)
    s.rect(0.5, 0, 3.5, 16, STEEL_DARK)
    s.rect(0.5, 0, 1.4, 16, STEEL_PALE)
    s.rect(2.3, 0, 3, 16, STEEL)
    for y in (2, 10):
        s.rect(1.4, y, 3.5, y + 1.5, STEEL_LIGHT)
    return s


def lift_stop():
    s = Sheet(32, 4)
    s.panel(0, 0, 32, 4, STEEL_DARK, STEEL_LIGHT, INK, ink=0.4, bevel=0.4)
    for x in (3, 29):
        s.rivet(x, 2)
    return s


def power_switch(on):
    s = Sheet(22, 28)
    s.panel(1, 1, 21, 26, STEEL_DARK, STEEL_LIGHT, INK, bevel=0.5)
    s.panel(3, 3, 19, 24, STEEL, STEEL_LIGHT, STEEL_DARK, bevel=0.4)
    s.hazard(4, 21, 18, 23, stripe=1.5)
    for x, y in ((2, 2), (20, 2), (2, 25), (20, 25)):
        s.rivet(x, y)
    s.panel(5, 5, 17, 10, SCREEN, STEEL_DARK, INK, bevel=0.2)
    s.polygon([(11, 5.5), (8, 8), (11, 8), (10, 9.5), (14, 7), (11, 7)], HAZARD)
    s.panel(7, 12, 15, 17, INK, STEEL_DARK, INK, bevel=0.2)  # state-lamp recess
    tip = (6, 10) if on else (16, 10)
    s.polygon([(10, 19), (12, 19), (tip[0] + 1, tip[1]), (tip[0] - 1, tip[1])], INK)
    s.polygon([(10.6, 19), (11.4, 19), (tip[0] + 0.4, tip[1]), (tip[0] - 0.4, tip[1])], STEEL_PALE)
    s.panel(tip[0] - 2, tip[1] - 1.5, tip[0] + 2, tip[1] + 1.5, HAZARD, PATCH_LIGHT, PATCH, ink=0.3, bevel=0.3)
    s.panel(0, 26, 22, 28, STEEL_DARK, STEEL, INK, ink=0.3, bevel=0.3)
    s.rect(18.5, 15, 20, 28, INK)
    s.rect(19, 15, 19.5, 28, STEEL_LIGHT)
    return s


FIXTURES = {
    "door_steel": door,
    "ladder_segment": ladder,
    "hint_sign": hint_sign,
    "switch_box_off": lambda: switch_box(False),
    "switch_box_on": lambda: switch_box(True),
    "breakable_wall": breakable_wall,
    "gate_shutter": gate_shutter,
    "breakable_crate": crate,
    "breakable_crate_damaged": lambda: crate("damaged"),
    "breakable_crate_broken": lambda: crate("broken"),
    "breakable_barrel": barrel,
    "breakable_barrel_damaged": lambda: barrel("damaged"),
    "breakable_barrel_broken": lambda: barrel("broken"),
    "breakable_glass": glass,
    "breakable_glass_damaged": lambda: glass("damaged"),
    "breakable_glass_broken": lambda: glass("broken"),
    "lift_deck": lift_deck,
    "lift_rail": lift_rail,
    "lift_stop": lift_stop,
    "power_switch_off": lambda: power_switch(False),
    "power_switch_on": lambda: power_switch(True),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheet", help="另外輸出一張樣本一覽（每件放在深色底上）")
    parser.add_argument("--only", nargs="+", choices=FIXTURES, help="只重建指定物件")
    args = parser.parse_args()
    sheets = {}
    for name, build in FIXTURES.items():
        if args.only and name not in args.only:
            continue
        sheets[name] = build()
        print(sheets[name].save(name), sheets[name].size)
    if args.sheet:
        gap = 24
        width = sum(s.image.width for s in sheets.values()) + gap * (len(sheets) + 1)
        height = max(s.image.height for s in sheets.values()) + gap * 2
        board = Image.new("RGBA", (width, height), (30, 34, 46, 255))
        x = gap
        for sheet in sheets.values():
            board.alpha_composite(sheet.image, (x, height - gap - sheet.image.height))
            x += sheet.image.width + gap
        board.convert("RGB").save(args.sheet)
        print(args.sheet)


if __name__ == "__main__":
    main()
