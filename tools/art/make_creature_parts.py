"""把非人形敵人的高解析立繪（art_src/creatures/<id>/）整理成遊戲用的零件圖（art/creatures/<id>/）：
依透明度裁掉空白、縮到遊戲尺寸（世界像素 × 4，對應 texture_scale 0.25）、去掉半透明雜點，並印出每個零件的尺寸，
給 art/creatures/<id>.json 設定關節（pivot）時對照。法線貼圖之後用 `godot --headless --path . res://tools/art/paint_normals.tscn -- --only=creatures` 產生。

用法：python tools/art/make_creature_parts.py [id ...]（不給 id 就處理全部）
"""
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art_src", "creatures")
DST = os.path.join(ROOT, "art", "creatures")
SCALE = 4  # 世界像素 → 貼圖像素（texture_scale 0.25）
ALPHA_CUT = 24

# id -> [(來源檔, 輸出名, "w" 或 "h", 目標世界像素)]
PARTS = {
    "drone": [("body_s1.png", "body", "w", 30), ("wing_s1.png", "wing", "h", 16)],
    "searchlight_drone": [("body_s2.png", "body", "w", 30), ("thruster_s1.png", "thruster", "h", 12)],
    "repair_drone": [("body_s2.png", "body", "w", 24), ("arm_s3.png", "arm", "h", 22)],
    "bomber": [("body_s1.png", "body", "w", 18), ("leg_s1.png", "leg", "h", 14)],
    "shock_hound": [("body_s2.png", "body", "w", 34), ("tail_s1.png", "tail", "w", 18)],
    "turret": [("base_s1.png", "base", "w", 24), ("turret_s3.png", "head", "w", 22), ("barrel_s1.png", "barrel", "w", 24)],
    "mimic": [("closed_s4.png", "closed", "w", 36), ("open_s1.png", "open", "w", 36)],
    # 觸手與蠕行類（ChainCreature、WormCreature）
    "salvage_arm": [("body_s1.png", "body", "w", 44), ("tentacle_s1.png", "tentacle", "h", 34)],
    "tangle_wire": [("body_s3.png", "body", "w", 30), ("tentacle_s1.png", "tentacle", "h", 30)],
    "buoy_worm": [("body_s4.png", "body", "w", 24), ("leg_s1.png", "leg", "h", 7)],
    # 飛行、攀附、懸浮、軌道與群體類（NE-99）
    "shaft_bat": [("body_s5.png", "body", "w", 30), ("wing_s1.png", "wing", "h", 22)],
    "wall_gecko": [("design_s1.png", "body", "w", 26)],
    "cloud_jelly": [("body_s2.png", "body", "w", 28), ("tentacle_s2.png", "tentacle", "h", 34)],
    "rail_cannon": [("slider_s2.png", "slider", "w", 18), ("barrel_s3.png", "barrel", "w", 26)],
    "swarm_bee": [("design_s2.png", "body", "w", 9)],
    "cloud_serpent": [("head_s1.png", "head", "w", 28), ("segment_s1.png", "segment", "w", 18)],
}


def clean(img: Image.Image) -> Image.Image:
    """把很淡的雜點（alpha 很低）清成全透明，再依剩下的內容裁切。"""
    img = img.convert("RGBA")
    r, g, b, a = img.split()
    a = a.point(lambda v: 0 if v < ALPHA_CUT else v)
    img = Image.merge("RGBA", (r, g, b, a))
    bbox = a.getbbox()
    return img.crop(bbox) if bbox else img


def process(creature: str) -> None:
    out_dir = os.path.join(DST, creature)
    os.makedirs(out_dir, exist_ok=True)
    for source, name, axis, world in PARTS[creature]:
        path = os.path.join(SRC, creature, source)
        if not os.path.exists(path):
            print(f"[{creature}] 缺少來源：{path}")
            continue
        img = clean(Image.open(path))
        target = world * SCALE
        factor = target / (img.width if axis == "w" else img.height)
        size = (max(1, round(img.width * factor)), max(1, round(img.height * factor)))
        img = img.resize(size, Image.LANCZOS)
        out_path = os.path.join(out_dir, f"{name}.png")
        img.save(out_path)
        print(f"[{creature}] {name}: {size[0]}x{size[1]} px = {size[0] / SCALE:.1f}x{size[1] / SCALE:.1f} 世界像素")


if __name__ == "__main__":
    ids = sys.argv[1:] or list(PARTS.keys())
    for cid in ids:
        if cid not in PARTS:
            print(f"沒有 {cid} 的設定")
            continue
        process(cid)
