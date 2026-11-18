"""從既有窗口原圖重建S08受限分件；原始素材與已存在的批准PNG均不改寫。"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    config_path = ROOT / "assets_src/pipeline/rent_window_contacts.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    for name, digest in config["sources"].items():
        if sha(ROOT / name) != digest:
            raise ValueError(f"租攤窗口來源不同，停止發布：{name}")
    source = np.array(Image.open(ROOT / config["window"]).convert("RGBA"))
    normal = np.array(Image.open(ROOT / config["normal"]).convert("RGBA"))
    glow = np.array(Image.open(ROOT / config["glow"]).convert("RGBA"))
    if list(source.shape[1::-1]) != config["window_canvas"]:
        raise ValueError("窗口來源畫布不同")
    clean, clean_normal = source.copy(), normal.copy()
    x0, y0, x1, y1 = config["clean_plate"]["target"]
    sx0, sy0, sx1, sy1 = config["clean_plate"]["source"]
    clean[y0:y1, x0:x1] = source[sy0:sy1, sx0:sx1]
    clean_normal[y0:y1, x0:x1] = normal[sy0:sy1, sx0:sx1]
    changed_region = np.zeros(source.shape[:2], bool)
    changed_region[y0:y1, x0:x1] = True
    if not np.array_equal(clean[~changed_region], source[~changed_region]):
        raise ValueError("窗口底層修改超出指定原位印章範圍")
    front, front_normal, front_glow = clean.copy(), clean_normal.copy(), glow.copy()
    for a, b, c, d in config["front_openings"]:
        for pixels in (front, front_normal, front_glow):
            pixels[b:d, a:c, 3] = 0
    mask = Image.new("L", tuple(config["window_canvas"]), 0)
    ImageDraw.Draw(mask).polygon([tuple(point) for point in config["stamp_polygon"]], fill=255)
    stamp = source.copy()
    stamp[:, :, 3] = np.minimum(stamp[:, :, 3], np.array(mask))
    stamp_normal = normal.copy()
    stamp_normal[:, :, 3] = stamp[:, :, 3]
    a, b, c, d = config["stamp_crop"]
    paper = np.array(Image.open(ROOT / config["paper"]).convert("RGBA"))
    mark = Image.new("RGBA", (paper.shape[1], paper.shape[0]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mark)
    ink = config["mark"]
    draw.rectangle(ink["border"], outline=tuple(ink["color"]), width=1)
    draw.text(tuple(ink["position"]), ink["text"], font=ImageFont.truetype(str(ROOT / config["font"]), ink["font_size"]), fill=tuple(ink["color"]))
    mark_pixels = np.array(mark)
    mark_pixels[:, :, 3] = np.minimum(mark_pixels[:, :, 3], paper[:, :, 3])
    mark_normal = np.zeros_like(mark_pixels)
    mark_normal[:, :, :3] = (128, 128, 255)
    mark_normal[:, :, 3] = mark_pixels[:, :, 3]
    images = {"window_clean": clean, "window_clean_n": clean_normal, "window_front": front,
              "window_front_n": front_normal, "window_front_glow": front_glow,
              "stamp": stamp[b:d, a:c], "stamp_n": stamp_normal[b:d, a:c],
              "contract_mark": mark_pixels, "contract_mark_n": mark_normal}
    out = ROOT / config["output"]
    # 先驗證所有既有輸出，避免一件不符時留下半套替換。
    for name, pixels in images.items():
        target = out / (name + ".png")
        if target.exists():
            with Image.open(target) as current:
                if current.mode != "RGBA" or current.size != (pixels.shape[1], pixels.shape[0]) or current.tobytes() != pixels.tobytes():
                    raise ValueError(f"既有窗口衍生圖不同，保留並停止：{target}")
    out.mkdir(parents=True, exist_ok=True)
    for name, pixels in images.items():
        target = out / (name + ".png")
        if not target.exists():
            Image.fromarray(pixels).save(target)
    report = {"generation": "none；原圖分件、相鄰原像素底層與既有字型印記", "sources": config["sources"],
              "config": config, "outputs": {name + ".png": sha(out / (name + ".png")) for name in images},
              "outside_clean_plate_unchanged": True,
              "stamp_crop": config["stamp_crop"], "stamp_grip": [23, 12], "stamp_base": [23, 50]}
    (ROOT / "assets_src/pipeline/rent_window_contacts-receipt.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    import texture_import
    texture_import.ART = out
    texture_import.apply_policy()
    print("租攤窗口：9個原生RGBA衍生層，原圖保持；既有同像素輸出不重新編碼")


if __name__ == "__main__":
    main()
