"""道具圖示繪製工具：用 Pillow 以 8 倍超採樣繪製向量形狀，縮小後把邊緣二值化並加 1 像素描邊，得到乾淨的像素風圖示。

設計座標一律是 0～64 的格子（與輸出尺寸無關），同一份繪製程式可以輸出 32×32（背包卡片）、384×384（原生詳情大圖）、
24×24（場景裡的拾取小圖）。發光的部位畫在 glow 圖層，另存成 _glow.png 供遊戲以 HDR 疊加。
"""
import math
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 8            # 超採樣倍率
DESIGN = 64.0     # 設計座標範圍
OUTLINE = (9, 11, 20, 255)


def hexc(value, alpha=255):
    value = value.lstrip('#')
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))


def shade(c, t):
    """t>0 變亮、t<0 變暗。"""
    if t >= 0:
        return mix(c, (255, 255, 255, c[3]), t)
    return mix(c, (0, 0, 0, c[3]), -t)


class Canvas:
    def __init__(self, size, outline=True, angle=0.0):
        self.size = size
        self.px = size * SS
        self.k = self.px / DESIGN
        self.img = Image.new('RGBA', (self.px, self.px), (0, 0, 0, 0))
        self.glow = Image.new('RGBA', (self.px, self.px), (0, 0, 0, 0))
        self.outline = outline
        self.angle = angle

    # --- 座標 --------------------------------------------------------------
    def p(self, x, y):
        return (x * self.k, y * self.k)

    def pts(self, points):
        return [self.p(x, y) for x, y in points]

    def _layer(self, emit):
        return self.glow if emit else self.img

    def _paint(self, draw_fn, fill, emit=False, shadow=False):
        """把 draw_fn(ImageDraw) 畫成遮罩，再以 fill 填色（fill 可以是顏色或函式 (x, y)->顏色 的垂直漸層）貼上。"""
        mask = Image.new('L', (self.px, self.px), 0)
        draw_fn(ImageDraw.Draw(mask))
        layer = self._layer(emit)
        if callable(fill):
            colored = Image.new('RGBA', (self.px, self.px))
            col = Image.new('RGBA', (1, self.px))
            for y in range(self.px):
                col.putpixel((0, y), fill(y / self.k))
            colored = col.resize((self.px, self.px))
        else:
            colored = Image.new('RGBA', (self.px, self.px), fill)
        layer.paste(colored, (0, 0), ImageChops.multiply(mask, colored.split()[3]))
        if emit:   # 發光部位同時畫在本體上（本體看得到，glow 層再疊亮）
            self.img.paste(colored, (0, 0), ImageChops.multiply(mask, colored.split()[3]))

    # --- 形狀 --------------------------------------------------------------
    def poly(self, points, fill, emit=False):
        self._paint(lambda d: d.polygon(self.pts(points), fill=255), fill, emit)

    def rrect(self, x0, y0, x1, y1, r, fill, emit=False):
        self._paint(lambda d: d.rounded_rectangle([self.p(x0, y0), self.p(x1, y1)], radius=r * self.k, fill=255), fill, emit)

    def ellipse(self, x0, y0, x1, y1, fill, emit=False):
        self._paint(lambda d: d.ellipse([self.p(x0, y0), self.p(x1, y1)], fill=255), fill, emit)

    def line(self, x0, y0, x1, y1, w, fill, emit=False):
        def fn(d):
            d.line([self.p(x0, y0), self.p(x1, y1)], fill=255, width=max(1, int(w * self.k)))
            r = w * self.k / 2
            for x, y in ((x0, y0), (x1, y1)):
                cx, cy = self.p(x, y)
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        self._paint(fn, fill, emit)

    def polyline(self, points, w, fill, emit=False):
        def fn(d):
            pp = self.pts(points)
            d.line(pp, fill=255, width=max(1, int(w * self.k)), joint='curve')
            r = w * self.k / 2
            for cx, cy in pp:
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        self._paint(fn, fill, emit)

    def arc(self, cx, cy, r, a0, a1, w, fill, emit=False):
        def fn(d):
            c = self.p(cx, cy)
            rr = r * self.k
            d.arc([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], a0, a1, fill=255, width=max(1, int(w * self.k)))
        self._paint(fn, fill, emit)

    def vgrad(self, y0, y1, c0, c1):
        """垂直漸層（設計座標 y0→y1），給 fill 用。"""
        def f(y):
            t = min(1.0, max(0.0, (y - y0) / (y1 - y0)))
            return mix(c0, c1, t)
        return f

    # --- 輸出 --------------------------------------------------------------
    def _finish_layer(self, img, outline):
        if self.angle:
            img = img.rotate(self.angle, resample=Image.BICUBIC, center=(self.px / 2, self.px / 2))
        small = img.resize((self.size, self.size), Image.BOX)
        r, g, b, a = small.split()
        # 邊緣二值化：半透明的邊緣變成實心或透明，保持像素風的乾淨輪廓。
        a = a.point(lambda v: 255 if v >= 110 else 0)
        small = Image.merge('RGBA', (r, g, b, a))
        if outline:
            width = max(1, round(self.size / 32))
            grown = a
            for _ in range(width):
                grown = grown.filter(ImageFilter.MaxFilter(3))
            edge = ImageChops.subtract(grown, a)
            ol = Image.new('RGBA', (self.size, self.size), OUTLINE)
            small = Image.composite(ol, small, edge)
        return small

    def result(self):
        return self._finish_layer(self.img, self.outline)

    def glow_result(self):
        small = self._finish_layer(self.glow, False)
        return small
