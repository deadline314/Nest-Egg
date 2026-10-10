"""把 tools/scene_tour.tscn 拍的格子拼成一覽圖，或把兩個標籤（修前、修後）逐格並排。

用法（在專案根目錄）：
  python tools/scene_tour_sheet.py <巡覽輸出資料夾>/<關卡> --tag before [--per-sheet 3] [--width 1560]
  python tools/scene_tour_sheet.py <巡覽輸出資料夾>/<關卡> --tag before --compare after --cells 2:0,3:1 --out <png>
一覽圖每張最多 per-sheet 欄，存成 <關卡>/<標籤>-sheet-r<列>-<序號>.png；幾乎全黑的格子（整格是實心地形或畫面外）略過。
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageStat

BACKGROUND = (18, 22, 28)
LABEL = (235, 240, 245)
EMPTY_MEAN = 3.0  # 0~255；整格平均亮度低於這個值視為空格


def font(size):
    for path in (r"C:\Windows\Fonts\msjh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def load_index(folder, tag):
    path = os.path.join(folder, f"{tag}-index.json")
    if not os.path.exists(path):
        sys.exit(f"找不到索引：{path}（先跑 tools/scene_tour.tscn --tag={tag}）")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def cell(folder, shot, width, label, text_font):
    image = Image.open(os.path.join(folder, shot["file"])).convert("RGB")
    empty = sum(ImageStat.Stat(image).mean) / 3.0 < EMPTY_MEAN
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.LANCZOS)
    out = Image.new("RGB", (width, height + 24), BACKGROUND)
    out.paste(image, (0, 24))
    ImageDraw.Draw(out).text((6, 2), label, fill=LABEL, font=text_font)
    return out, empty


def paste_row(cells, gap=6):
    width = sum(c.width for c in cells) + gap * (len(cells) - 1)
    out = Image.new("RGB", (width, max(c.height for c in cells)), BACKGROUND)
    x = 0
    for item in cells:
        out.paste(item, (x, 0))
        x += item.width + gap
    return out


def stack(rows, gap=6):
    out = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows) + gap * (len(rows) - 1)), BACKGROUND)
    y = 0
    for item in rows:
        out.paste(item, (0, y))
        y += item.height + gap
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--compare", help="第二個標籤；逐格與 --tag 並排")
    parser.add_argument("--cells", help="只取這些格（欄:列，逗號分隔）")
    parser.add_argument("--per-sheet", type=int, default=3)
    parser.add_argument("--width", type=int, default=1560)
    parser.add_argument("--out", help="--compare 的輸出檔")
    args = parser.parse_args()

    index = load_index(args.folder, args.tag)
    wanted = set(args.cells.split(",")) if args.cells else None
    shots = [s for s in index["shots"] if wanted is None or f"{s['column']}:{s['row']}" in wanted]
    if not shots:
        sys.exit("沒有符合的格子")
    text_font = font(15)

    if args.compare:
        other = {(s["column"], s["row"]): s for s in load_index(args.folder, args.compare)["shots"]}
        width = (args.width - 6) // 2
        rows = []
        for shot in shots:
            key = (shot["column"], shot["row"])
            if key not in other:
                sys.exit(f"{args.compare} 缺少格子 {key}")
            left, _ = cell(args.folder, shot, width, f"{index['level']} 欄{key[0]} 列{key[1]}｜{args.tag}", text_font)
            right, _ = cell(args.folder, other[key], width, f"{index['level']} 欄{key[0]} 列{key[1]}｜{args.compare}", text_font)
            rows.append(paste_row([left, right]))
        out = args.out or os.path.join(args.folder, f"{args.tag}-vs-{args.compare}.png")
        stack(rows).save(out)
        print(out)
        return

    width = (args.width - 6 * (args.per_sheet - 1)) // args.per_sheet
    by_row = {}
    for shot in shots:
        by_row.setdefault(shot["row"], []).append(shot)
    for row, items in sorted(by_row.items()):
        items.sort(key=lambda s: s["column"])
        cells = []
        for shot in items:
            world = shot["world"]
            tile = index["tile"]
            label = f"欄{shot['column']} 列{shot['row']}｜格 x {int(world[0] // tile)}–{int((world[0] + world[2]) // tile)}"
            image, empty = cell(args.folder, shot, width, label, text_font)
            if not empty:
                cells.append(image)
        for number, start in enumerate(range(0, len(cells), args.per_sheet)):
            out = os.path.join(args.folder, f"{args.tag}-sheet-r{row:02d}-{number:02d}.png")
            paste_row(cells[start:start + args.per_sheet]).save(out)
            print(out)


if __name__ == "__main__":
    main()
