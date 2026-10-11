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


FIXTURES = {
    "door_steel": door,
    "ladder_segment": ladder,
    "hint_sign": hint_sign,
    "switch_box_off": lambda: switch_box(False),
    "switch_box_on": lambda: switch_box(True),
    "breakable_wall": breakable_wall,
    "gate_shutter": gate_shutter,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheet", help="另外輸出一張樣本一覽（每件放在深色底上）")
    args = parser.parse_args()
    sheets = {}
    for name, build in FIXTURES.items():
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
