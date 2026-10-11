"""把 tools/vfx_exposure_probe.tscn 拍的圖算出過曝比例，並把每份光影設定拼成一列的一覽圖。

用法（在專案根目錄）：
  python tools/vfx_exposure_sheet.py <輸出資料夾> --tag before [--rows 6] [--width 1680] [--csv <檔>]
  python tools/vfx_exposure_sheet.py <輸出資料夾> --tag before --compare after --profiles market,blackout --moments 3-blast-015 --out <png>
量測（每張圖）：
  全白＝三個色版都高於 0.92 的像素。frame 是整張畫面的比例；far 是離特效中心 2 倍半徑以外的比例
  （特效自己的白熱中心不算，量的是「整個畫面被洗白」）；player、watcher 是主角與旁觀敵人身上的比例。
門檻：far ≤ 0.5%、player ≤ 5%、watcher ≤ 5%；爆炸後 0.45 秒起 frame ≤ 0.5%（白光要退場）。
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WHITE = 0.92 * 255.0
LIMIT_FAR = 0.005
LIMIT_BODY = 0.05
LIMIT_LINGER = 0.005
LINGER_FROM = "5-"
BACKGROUND = (18, 22, 28)
LABEL = (235, 240, 245)
BAD = (255, 120, 110)


def font(size):
    for path in (r"C:\Windows\Fonts\msjh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def load_index(folder, tag):
    path = os.path.join(folder, f"{tag}-index.json")
    if not os.path.exists(path):
        sys.exit(f"找不到索引：{path}（先跑 tools/vfx_exposure_probe.tscn --tag={tag}）")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def ratio(mask, rect=None):
    if rect is not None:
        x, y, w, h = (int(round(v)) for v in rect)
        mask = mask[max(0, y):max(0, y + h), max(0, x):max(0, x + w)]
    return float(mask.mean()) if mask.size else 0.0


def measure(folder, shot):
    pixels = np.asarray(Image.open(os.path.join(folder, shot["file"])).convert("RGB"), dtype=np.float32)
    white = (pixels > WHITE).all(axis=2)
    luma = (pixels * np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).sum(axis=2) / 255.0
    ex, ey, radius = shot["effect"]
    far = white
    if radius > 0.0:
        ys, xs = np.mgrid[0:white.shape[0], 0:white.shape[1]]
        far = white[(xs - ex) ** 2 + (ys - ey) ** 2 > (radius * 2.0) ** 2]
    result = {"frame": ratio(white), "far": float(far.mean()) if far.size else 0.0,
              "player": ratio(white, shot["player"]), "watcher": ratio(white, shot["watcher"]), "luma": float(luma.mean())}
    problems = []
    if result["far"] > LIMIT_FAR:
        problems.append("far")
    if result["player"] > LIMIT_BODY:
        problems.append("player")
    if result["watcher"] > LIMIT_BODY:
        problems.append("watcher")
    if shot["moment"] >= LINGER_FROM and result["frame"] > LIMIT_LINGER:
        problems.append("linger")
    result["problems"] = problems
    return result


def crop_box(shots, size):
    """同一列共用的裁切框：包住主角、旁觀敵人與爆炸。"""
    xs, ys = [], []
    for shot in shots:
        for key in ("player", "watcher"):
            x, y, w, h = shot[key]
            xs += [x, x + w]
            ys += [y, y + h]
        ex, ey, radius = shot["effect"]
        if radius > 0.0:
            xs += [ex - radius * 2.2, ex + radius * 2.2]
            ys += [ey - radius * 2.6, ey + radius * 0.6]
    pad = 24
    return (int(max(0, min(xs) - pad)), int(max(0, min(ys) - pad)), int(min(size[0], max(xs) + pad)), int(min(size[1], max(ys) + pad)))


def cell(folder, shot, box, width, label, text_font, flagged):
    image = Image.open(os.path.join(folder, shot["file"])).convert("RGB").crop(box)
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.LANCZOS)
    out = Image.new("RGB", (width, height + 22), BACKGROUND)
    out.paste(image, (0, 22))
    ImageDraw.Draw(out).text((4, 2), label, fill=BAD if flagged else LABEL, font=text_font)
    return out


def paste_row(cells, gap=4):
    out = Image.new("RGB", (sum(c.width for c in cells) + gap * (len(cells) - 1), max(c.height for c in cells)), BACKGROUND)
    x = 0
    for item in cells:
        out.paste(item, (x, 0))
        x += item.width + gap
    return out


def stack(rows, gap=4):
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
    parser.add_argument("--compare", help="第二個標籤；逐份光影設定與 --tag 上下並排")
    parser.add_argument("--profiles", help="只取這些光影設定（逗號分隔）")
    parser.add_argument("--moments", help="只取這些時刻（逗號分隔，例如 3-blast-015）")
    parser.add_argument("--rows", type=int, default=6, help="一覽圖每張幾份光影設定")
    parser.add_argument("--width", type=int, default=1680)
    parser.add_argument("--csv")
    parser.add_argument("--out")
    args = parser.parse_args()

    index = load_index(args.folder, args.tag)
    profiles = args.profiles.split(",") if args.profiles else index["profiles"]
    moments = set(args.moments.split(",")) if args.moments else None
    text_font = font(13)

    def rows_for(tag_index, tag):
        rows, records = [], []
        for profile in profiles:
            every = [s for s in tag_index["shots"] if s["profile"] == profile]
            shots = [s for s in every if moments is None or s["moment"] in moments]
            if not shots:
                continue
            size = Image.open(os.path.join(args.folder, shots[0]["file"])).size
            box = crop_box(every, size)
            width = (args.width - 4 * (len(shots) - 1)) // len(shots)
            cells = []
            for shot in shots:
                numbers = measure(args.folder, shot)
                records.append({"tag": tag, "profile": profile, "moment": shot["moment"], **numbers})
                label = "%s %s｜%s｜遠 %.2f%% 主角 %.1f%% 敵 %.1f%%" % (
                    profile, shot["moment"], tag, numbers["far"] * 100, numbers["player"] * 100, numbers["watcher"] * 100)
                cells.append(cell(args.folder, shot, box, width, label, text_font, bool(numbers["problems"])))
            rows.append((profile, paste_row(cells)))
        return rows, records

    rows, records = rows_for(index, args.tag)
    if args.compare:
        other_rows, other_records = rows_for(load_index(args.folder, args.compare), args.compare)
        records += other_records
        other = dict(other_rows)
        merged = []
        for profile, row in rows:
            merged.append(row)
            if profile in other:
                merged.append(other[profile])
        out = args.out or os.path.join(args.folder, "%s-vs-%s.png" % (args.tag, args.compare))
        stack(merged).save(out)
        print(out)
    else:
        for number, start in enumerate(range(0, len(rows), args.rows)):
            out = os.path.join(args.folder, "%s-sheet-%02d.png" % (args.tag, number))
            stack([row for _, row in rows[start:start + args.rows]]).save(out)
            print(out)

    flagged = [r for r in records if r["problems"]]
    print("%d 張，%d 張超過門檻" % (len(records), len(flagged)))
    for record in flagged:
        print("  %s %s %s: %s（frame %.2f%% far %.2f%% player %.1f%% watcher %.1f%%）" % (
            record["tag"], record["profile"], record["moment"], ",".join(record["problems"]),
            record["frame"] * 100, record["far"] * 100, record["player"] * 100, record["watcher"] * 100))
    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=["tag", "profile", "moment", "frame", "far", "player", "watcher", "luma", "problems"])
            writer.writeheader()
            for record in records:
                writer.writerow({**record, "problems": " ".join(record["problems"])})
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
