#!/usr/bin/env python3
"""把一或多個區域的地圖畫成俯覽示意圖（修前修後比對用）。

用法：python tools/level/render_map.py --out <png> ch3_gate_hall [ch3_glass_edge ...] [--rev <git 版本>]
讀 data/levels/<區域>_map.json 與 <區域>.tres 的 legend；給 --rev 時從那個 git 版本讀（例如 HEAD~1）。
顏色：灰＝實心、青＝單向平台、紅＝敵人、藍＝人物或調查點、綠＝出入口、橘＝機關、黃＝信用點與拾取、白＝起點與檢查點。
"""
import argparse
import json
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CELL = 4
COLORS = {
    '#': (78, 82, 96), '=': (90, 190, 220), '^': (230, 60, 60), '|': (230, 60, 160), '~': (170, 220, 255),
    'P': (255, 255, 255), 'C': (255, 255, 255), 'B': (255, 120, 120), '*': (96, 88, 60),
}
KIND_COLORS = {'enemy': (235, 70, 70), 'npc': (90, 140, 255), 'portal': (70, 220, 110), 'mechanism': (255, 150, 40),
               'pickup': (255, 225, 60), 'secret': (255, 90, 220), 'other': (180, 180, 180)}
LEGEND_ORDER = [('實心', COLORS['#']), ('平台', COLORS['=']), ('敵人', KIND_COLORS['enemy']), ('人物／調查', KIND_COLORS['npc']),
                ('出入口', KIND_COLORS['portal']), ('機關', KIND_COLORS['mechanism']), ('信用點／拾取', KIND_COLORS['pickup']),
                ('秘密', KIND_COLORS['secret']), ('起點／檢查點', COLORS['P'])]


def read(path, rev):
    if rev:
        out = subprocess.run(['git', 'show', f'{rev}:{path}'], cwd=ROOT, capture_output=True)
        if out.returncode != 0:
            raise SystemExit(f'{rev}:{path} 讀不到：{out.stderr.decode("utf-8", "replace").strip()}')
        return out.stdout.decode('utf-8')
    with open(os.path.join(ROOT, path), encoding='utf-8') as f:
        return f.read()


def kind_of(path):
    if '/enemies/' in path:
        return 'enemy'
    if '/npcs/' in path or '/shops/' in path:
        return 'npc'
    if 'secret_wall' in path:
        return 'secret'
    if 'credits' in path or '/items/' in path or '/consumables/' in path or '/weapons/' in path:
        return 'pickup'
    if '/props/' in path or '/encounters/' in path or '/challenges/' in path or '/throwables/' in path:
        return 'mechanism'
    return 'other'


def legend(tres):
    ext = {i: p for p, i in re.findall(r'path="([^"]+)" id="([^"]+)"', tres)}
    result = {}
    for char, ref in re.findall(r'"(.)": (?:ExtResource|SubResource)\("([^"]+)"\)', tres):
        result[char] = kind_of(ext.get(ref, '')) if ref in ext else 'portal'
    return result


def rows_of(level, rev):
    data = json.loads(read(f'data/levels/{level}_map.json', rev))
    segments = data['segments']
    return [''.join(seg[y] for seg in segments) for y in range(len(segments[0]))]


def render(level, rev, font):
    rows = rows_of(level, rev)
    glyphs = legend(read(f'data/levels/{level}.tres', rev))
    w, h = len(rows[0]), len(rows)
    title = 22
    im = Image.new('RGB', (w * CELL, h * CELL + title), (22, 22, 28))
    dr = ImageDraw.Draw(im)
    dr.text((4, 2), f'{level}{"（" + rev + "）" if rev else ""}  {w}×{h} 格', font=font, fill=(230, 230, 230))
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in '. ':
                continue
            box = (x * CELL, title + y * CELL, x * CELL + CELL - 1, title + y * CELL + CELL - 1)
            if c in COLORS:
                dr.rectangle(box, fill=COLORS[c])
            elif c.isdigit():
                dr.rectangle(box, fill=(150, 150, 150))
            elif c in glyphs:
                k = glyphs[c]
                big = (box[0] - 2, box[1] - 6, box[2] + 2, box[3])
                dr.rectangle(big if k in ('enemy', 'npc', 'portal') else box, fill=KIND_COLORS[k])
            else:
                dr.rectangle(box, fill=KIND_COLORS['other'])
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('levels', nargs='+')
    ap.add_argument('--out', required=True)
    ap.add_argument('--rev', default='')
    args = ap.parse_args()
    font = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 14) if os.path.exists('C:/Windows/Fonts/msjh.ttc') else ImageFont.load_default()
    images = [render(level, args.rev, font) for level in args.levels]
    width = max([im.width for im in images] + [760])
    sheet = Image.new('RGB', (width, sum(im.height + 6 for im in images) + 24), (22, 22, 28))
    y = 0
    for im in images:
        sheet.paste(im, (0, y))
        y += im.height + 6
    dr = ImageDraw.Draw(sheet)
    x = 4
    for name, color in LEGEND_ORDER:
        dr.rectangle((x, y + 6, x + 10, y + 16), fill=color)
        dr.text((x + 14, y + 2), name, font=font, fill=(220, 220, 220))
        x += 24 + int(dr.textlength(name, font=font))
    sheet.save(args.out)
    print(f'{args.out}: {sheet.width}×{sheet.height}')


if __name__ == '__main__':
    sys.exit(main())
