"""Apply the retained-source contract to the generated ch2_greycoat spec (same rules as guest_zheng).

No model or source image is edited. Parts, appearance and native acceptance remain separate.
用法：python art_src/characters/ch2_greycoat/configure_spec.py（field_spec --force 之後重跑）
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
path = root / "tools/comfyui/specs/ch2_greycoat_side.json"
spec = json.loads(path.read_text(encoding="utf-8"))
spec["description"] = ("灰衣搬運者的本機 Qwen 中性站姿立繪（seed 24501）；關節由姿勢模型預測後逐點核對，被遮住的遠側解剖點不冒稱量測。"
                       "分件、完整底層、接點與原生動作另驗。")
# Keep the source's own semi-transparent edge; ownership masks still decide the parts.
spec["preserve_source_alpha"] = True
for stage in spec["stages"]:
    stage["resolution"] = 0  # Native 1024x1536 is already 32-aligned; refuse resampling.
spec["refine"]["alpha_floor"] = 40
spec["refine"]["speckle"] = 30
# Retained lines already have clean colour and coverage: a generic blur, edge repaint or
# blind hole fill discards valid one-pixel contour material (guest_zheng review).
for key in ("smooth_alpha", "defringe", "fill_holes"):
    spec["refine"].pop(key, None)
for use in spec["parts"]["arm_upper"]["uses"]:
    use["root_attach"] = True
path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("configured", path)

# Dialogue portrait (NE-267: the speaker no longer borrows the resident face). Frame the actual head layer with a
# margin, so the cap brim and nose stay inside; the neck-based field_spec box clips this cap.
from PIL import Image  # noqa: E402
spec = json.loads(path.read_text(encoding="utf-8"))
base = Image.open(Path(__file__).resolve().parent / "base_rgba.png").getchannel("A")
neck_y = spec["joints"]["neck"][1]
x0, y0, x1, y1 = base.crop((0, 0, base.width, neck_y)).point(lambda a: 255 if a > 40 else 0).getbbox()
side = round(max(x1 - x0, y1 - y0) * 1.3)
cx, top = (x0 + x1) / 2, y0 - round(0.06 * side)
spec["dialog_portrait"] = {"box": [round(cx - side * 0.52), top, round(cx - side * 0.52) + side, top + side],
                           "out": "art/portraits/ch2_greycoat.png", "size": 256}
path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
