#!/usr/bin/env python3
"""第一章道具圖示（ST-8）：背包卡片 32×32、詳情大圖 96×96、場景拾取小圖 24×24（另有 _glow 自發光層）。

繪製工具見 item_icon_kit.py（8 倍超採樣的向量形狀，縮小後二值化邊緣並描邊）。
之後要換成手繪或 AI 圖，直接用同名檔案覆蓋 art/items/icons、art/items/world 裡的 PNG 即可，程式不需要改。
用法：python3 tools/art/build_item_icons.py [圖示名稱…]（不給名稱就全部重畫）
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from item_icon_kit import Canvas, hexc, mix, shade  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
ICON_DIR = os.path.join(ROOT, 'art', 'items', 'icons')
WORLD_DIR = os.path.join(ROOT, 'art', 'items', 'world')
SIZES = {'': 32, '_hd': 96}
WORLD_SIZE = 24


# ---------------------------------------------------------------------------
# 各道具：函式收到 Canvas，用 0～64 的設計座標畫
# ---------------------------------------------------------------------------

def med_injector(c):
    """醫療針：水平畫好再整張旋轉，針頭朝右上。"""
    glass = c.vgrad(24, 40, hexc('e6f8ff'), hexc('9cc3d6'))
    c.rrect(14, 24, 46, 40, 3, glass)
    fluid = c.vgrad(26, 38, hexc('ff86a6'), hexc('d93660'))
    c.rrect(21, 27, 44, 37, 2, fluid, emit=True)
    c.rrect(16, 26, 21, 38, 1, hexc('3b4256'))             # 活塞膠頭
    c.rrect(5, 25, 10, 39, 2, hexc('b6c4d6'))              # 拇指墊
    c.rrect(9, 30, 17, 34, 1, hexc('8794a8'))              # 活塞桿
    c.rrect(12, 21, 16, 43, 1.5, hexc('d7e2ef'))           # 法蘭
    c.poly([(46, 27), (52, 29.5), (52, 34.5), (46, 37)], hexc('c9d4e2'))
    c.line(52, 32, 62.5, 32, 1.6, hexc('eef4fb'))          # 針
    for x in (26, 31, 36, 41):
        c.line(x, 24.8, x, 27 if x % 10 == 1 else 26.2, 0.9, hexc('ffffff'))
    c.rrect(29.5, 29.5, 35.5, 34.5, 0.6, hexc('fff2f6'))   # 十字
    c.rrect(31.6, 28, 33.4, 36, 0.4, hexc('fff2f6'))
    c.line(22, 28.2, 43, 28.2, 1.1, hexc('ffd2de', 200))   # 液面反光
    c.line(18, 25.2, 44, 25.2, 1.0, hexc('ffffff', 220))   # 玻璃高光


def shield_cell(c):
    """護盾電池：直立的能量電池，中間是發光的青色能量窗。"""
    c.rrect(19, 15, 45, 53, 6, c.vgrad(15, 53, hexc('4a5878'), hexc('252d44')))
    c.rrect(24, 9, 40, 17, 2.5, hexc('b9c6d8'))
    c.rrect(29, 5, 35, 10, 1.5, hexc('e9f0f8'))
    c.rrect(19, 50, 45, 57, 2.5, hexc('8e9bb2'))
    c.rrect(25, 20, 39, 47, 3.5, c.vgrad(20, 47, hexc('8bf7ff'), hexc('13a3c8')), emit=True)
    c.poly([(35, 22), (28, 35), (32.5, 35), (29.5, 46), (38, 31), (33.5, 31)], hexc('f4feff'))
    c.line(22, 21, 22, 47, 1.3, hexc('9fb0cf', 200))
    c.line(42.5, 24, 42.5, 44, 1.0, hexc('141a2c', 180))


def data_disk(c):
    """資料盤：黑色硬殼的磁碟，貼著橘色的收帳人徽章，下緣是金色接點。"""
    c.poly([(10, 9), (42, 9), (54, 21), (54, 55), (10, 55)], c.vgrad(9, 55, hexc('424a5e'), hexc('1f2433')))
    c.rrect(16, 15, 42, 35, 2, hexc('efe6cf'))
    c.ellipse(20, 18, 32, 30, hexc('ff9a2e'), emit=True)
    c.ellipse(23, 21, 29, 27, hexc('2a2f40'))
    c.line(34, 20, 40, 20, 1.3, hexc('9a927d'))
    c.line(34, 24, 40, 24, 1.3, hexc('9a927d'))
    c.line(34, 28, 38, 28, 1.3, hexc('9a927d'))
    c.rrect(16, 43, 48, 54, 1.5, hexc('d9b44a'))
    for x in (20, 26, 32, 38, 44):
        c.line(x, 43.5, x, 53.5, 0.9, hexc('7c6420'))
    c.rrect(44, 14, 50, 22, 1, hexc('151a28'))
    c.line(12, 12, 12, 52, 1.2, hexc('8a95b0', 160))


def grey_cloth(c):
    """灰布角：一塊舊布被折起一個角，有皺褶、縫線，下緣是散開的線頭。"""
    c.poly([(9, 19), (38, 9), (52, 21), (51, 50), (22, 56), (8, 45)], c.vgrad(9, 56, hexc('c7cbd3'), hexc('858c9a')))
    c.poly([(38, 9), (52, 21), (42, 27)], hexc('e6e9ee'))                      # 折起來的角（布的背面）
    c.poly([(38, 9), (42, 27), (33, 20)], hexc('6c7382', 200))                  # 折痕的陰影
    c.polyline([(13, 28), (22, 33), (32, 31), (40, 36)], 1.3, hexc('6f7686', 170))
    c.polyline([(14, 40), (25, 45), (36, 42), (47, 46)], 1.3, hexc('6f7686', 170))
    c.polyline([(12, 22), (14, 30), (13, 38), (11, 44)], 0.9, hexc('e9ecf1', 200))   # 縫線
    for i, (x, y) in enumerate(((24, 56), (29, 55.5), (34, 55), (39, 54), (44, 53))):
        c.line(x, y, x + 0.5 * (i % 2), y + 4.2 - (i % 3) * 0.8, 0.9, hexc('aab0bd'))
    c.ellipse(36, 44, 42, 50, hexc('5b6478', 120))


def doc_flyer(c):
    """回音派傳單：淡青色的紙，上面一圈一圈的回音波紋。"""
    c.poly([(14, 8), (50, 6), (53, 53), (17, 56)], c.vgrad(6, 56, hexc('eefafc'), hexc('b7d9e0')))
    for r, w in ((5, 2.2), (10, 2.2), (15, 2.2)):
        c.arc(32, 26, r, 205, 335, w, hexc('2fc6d6'), emit=True)
    c.ellipse(30, 24, 34, 28, hexc('1f8ea0'))
    for i, ln in enumerate((36, 41, 46)):
        c.line(20, ln + 1, 46 - (i % 2) * 8, ln, 1.5, hexc('6f8f99'))
    c.poly([(46, 56), (53, 53), (51, 47)], hexc('9ec3cb'))


def doc_notice(c):
    """收帳通知單：黃色的紙，紅色的印章與一條膠帶。"""
    c.poly([(12, 9), (52, 9), (52, 55), (12, 55)], c.vgrad(9, 55, hexc('f6dc92'), hexc('dbb04c')))
    c.rrect(13, 12, 51, 22, 1, hexc('c93b32'))
    for i, ln in enumerate((29, 34, 39)):
        c.line(17, ln, 47 - (i % 2) * 9, ln, 1.5, hexc('8b6c2c'))
    c.ellipse(32, 38, 51, 53, hexc('e0453a'), emit=True)
    c.ellipse(35, 41, 48, 50, hexc('f6dc92'))
    c.rrect(41, 42, 43, 47, 0.4, hexc('e0453a'))
    c.rrect(41, 48, 43, 50, 0.4, hexc('e0453a'))
    c.poly([(26, 4), (40, 6), (39, 13), (25, 11)], hexc('efe2c0', 230))


def doc_log(c):
    """水閘維修日誌：深青色的硬皮筆記本，頁尾被撕掉，水漬。"""
    c.rrect(11, 7, 52, 56, 3, c.vgrad(7, 56, hexc('3e7c8a'), hexc('1f4752')))
    c.rrect(11, 7, 18, 56, 3, hexc('265562'))
    c.rrect(22, 14, 47, 30, 1.5, hexc('e8e2cf'))
    for i, ln in enumerate((19, 23, 27)):
        c.line(25, ln, 44 - (i % 2) * 6, ln, 1.3, hexc('5b7c85'))
    c.poly([(52, 44), (47, 47), (50, 50), (45, 52), (52, 56)], hexc('e8e2cf'))
    c.ellipse(24, 36, 40, 50, hexc('1b6b86', 180), emit=False)
    c.ellipse(28, 40, 36, 46, hexc('2f9ab8', 150))
    c.line(15, 12, 15, 52, 1.2, hexc('7fb4c0', 150))


def doc_news(c):
    """港區日報：折起來的報紙，頭版是一張雨天的照片。"""
    c.poly([(10, 12), (46, 10), (49, 52), (13, 55)], hexc('b9bec6'))
    c.poly([(15, 8), (53, 7), (54, 51), (18, 54)], c.vgrad(7, 54, hexc('f0eee6'), hexc('cfcabd')))
    c.rrect(19, 12, 50, 19, 1, hexc('2a2e3a'))
    c.rrect(19, 22, 38, 40, 1, c.vgrad(22, 40, hexc('3a5a7a'), hexc('1c3048')))
    for i in range(5):
        c.line(22 + i * 3.4, 24, 20 + i * 3.4, 38, 0.8, hexc('9ec3e6', 190))
    for i, ln in enumerate((24, 29, 34, 39)):
        c.line(41, ln, 49, ln, 1.2, hexc('7d7a70'))
    c.line(19, 45, 50, 44, 1.3, hexc('7d7a70'))
    c.line(19, 49, 44, 48, 1.3, hexc('7d7a70'))


def doc_stub(c):
    """當票存根：奶油色的長票，左邊一排撕孔，中間是一只懷錶。"""
    c.poly([(17, 6), (47, 6), (47, 58), (17, 58)], c.vgrad(6, 58, hexc('f6ebca'), hexc('d9c48f')))
    for i in range(6):
        c.ellipse(14.5, 9 + i * 8.5, 19.5, 14 + i * 8.5, hexc('0b0e17'))
    c.rrect(23, 10, 42, 15, 1, hexc('a5301f'))
    c.ellipse(24, 20, 41, 37, hexc('d8a93a'), emit=True)
    c.ellipse(26, 22, 39, 35, hexc('f6ebca'))
    c.line(32.5, 28.5, 32.5, 23.8, 1.1, hexc('3a3128'))
    c.line(32.5, 28.5, 36.5, 30.5, 1.1, hexc('3a3128'))
    c.rrect(31, 17.5, 34, 20.5, 0.8, hexc('d8a93a'))
    for ln, w in ((43, 17), (47, 12), (51, 15)):
        c.line(23, ln, 23 + w, ln, 1.3, hexc('8a7650'))


def grey_coin_stack(c, coins, big):
    """金幣堆（信用點）：每枚是一個橢圓頂面加側面。"""
    gold_top = hexc('ffe27a')
    gold_side = hexc('c78d1d')
    gold_dark = hexc('8a5a0e')
    positions = []
    if big:
        positions = [(20, 46), (40, 46), (30, 40), (20, 34), (40, 34), (30, 28)][:coins]
    else:
        positions = [(32, 46), (32, 38), (32, 30)][:coins]
    rx, ry, th = (11, 5.5, 5) if big else (13, 6.5, 6)
    for cx, cy in positions:
        c.rrect(cx - rx, cy, cx + rx, cy + th, 1.5, gold_side)
        c.ellipse(cx - rx, cy + th - ry, cx + rx, cy + th + ry, gold_dark)
        c.ellipse(cx - rx, cy - ry, cx + rx, cy + ry, c.vgrad(cy - ry, cy + ry, shade(gold_top, 0.25), gold_top), emit=True)
        c.ellipse(cx - rx * 0.62, cy - ry * 0.6, cx + rx * 0.62, cy + ry * 0.6, hexc('e3b542'))
        c.line(cx - rx * 0.3, cy, cx + rx * 0.3, cy, 1.0, hexc('9c6b12'))


def credits_small(c):
    grey_coin_stack(c, 3, False)


def credits_large(c):
    grey_coin_stack(c, 6, True)


ICONS = {
    # 名稱: (繪製函式, 旋轉角度, 是否畫場景小圖)
    'med_injector': (med_injector, 38.0, True),
    'shield_cell': (shield_cell, 0.0, True),
    'ch1_data_disk': (data_disk, 0.0, True),
    'ch1_grey_cloth': (grey_cloth, 0.0, True),
    'doc_flyer': (doc_flyer, 0.0, True),
    'doc_notice': (doc_notice, 0.0, True),
    'doc_log': (doc_log, 0.0, True),
    'doc_news': (doc_news, 0.0, True),
    'doc_stub': (doc_stub, 0.0, True),
    'credits_small': (credits_small, 0.0, True),
    'credits_large': (credits_large, 0.0, True),
}
# 只有場景小圖、沒有背包圖示的項目（信用點是金額，不進背包）。
WORLD_ONLY = {'credits_small', 'credits_large'}


def render(name, size):
    fn, angle, _ = ICONS[name]
    cv = Canvas(size, angle=angle)
    fn(cv)
    return cv


def main(names):
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(WORLD_DIR, exist_ok=True)
    for name in names or ICONS:
        fn, angle, world = ICONS[name]
        if name not in WORLD_ONLY:
            for suffix, size in SIZES.items():
                render(name, size).result().save(os.path.join(ICON_DIR, f'{name}{suffix}.png'))
        if world:
            cv = render(name, WORLD_SIZE)
            cv.result().save(os.path.join(WORLD_DIR, f'{name}.png'))
            cv.glow_result().save(os.path.join(WORLD_DIR, f'{name}_glow.png'))
        print('drew', name)


if __name__ == '__main__':
    main(sys.argv[1:])
