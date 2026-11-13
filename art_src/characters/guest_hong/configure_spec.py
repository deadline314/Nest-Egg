"""Apply the retained-source contract to the generated guest_hong spec (same rules as guest_zheng).

No model or source image is edited. Parts, appearance and native acceptance remain separate.
用法：python art_src/characters/guest_hong/configure_spec.py（field_spec --force 之後重跑）
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
path = root / "tools/comfyui/specs/guest_hong_side.json"
spec = json.loads(path.read_text(encoding="utf-8"))
spec["description"] = ("洪先生的保留中性站姿來源；關節由姿勢模型預測後逐點核對，被遮住的遠側解剖點不冒稱量測。"
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
