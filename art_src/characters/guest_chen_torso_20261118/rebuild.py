"""在既有精修後補回陳女士漏切的3009個原圖軀幹像素。"""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part
from registered_layers import registered_layer_bytes, write_registered_file


def sha(data):
    return hashlib.sha256(data).hexdigest()


def input_sha(path):
    data = path.read_bytes()
    # 只容許文字檔的換行差異；PNG與其他內容一律原始bytes。
    if path.suffix in {".json", ".py"}:
        data = data.replace(b"\r\n", b"\n")
    return sha(data)


def main():
    record = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    # 固定既有精修來源；重跑精修產生的任何漂移先停止，不帶入其他零件。
    for name, expected in record["inputs"].items():
        path = ROOT / name
        if not path.is_file() or input_sha(path) != expected:
            raise ValueError(f"陳女士來源版本不同，切件前停止；請核對已登記來源：{name}")
    mask_path = HERE / "claim-mask.png"
    if sha(mask_path.read_bytes()) != record["mask_sha256"]:
        raise ValueError("陳女士軀幹遮罩版本不同：claim-mask.png")
    work = ROOT / "art_src/characters/guest_chen"
    with Image.open(work / "base_rgba.png") as image:
        base = np.array(image.convert("RGBA"))
    with Image.open(work / "07_refined/torso.png") as image:
        old = image.convert("RGBA")
    original = np.array(old)
    with Image.open(mask_path) as image:
        if image.mode != "L" or image.size != old.size:
            raise ValueError("陳女士軀幹遮罩須為與原圖相同畫布的灰階圖")
        mask = np.array(image) == 255
    if int(mask.sum()) != record["source_changed_pixels"] or np.any(base[:, :, 3][mask] <= 127):
        raise ValueError("陳女士軀幹遮罩未對應3009個原圖不透明材料像素")
    result = original.copy()
    result[mask] = base[mask]
    if not np.array_equal(result[~mask], original[~mask]):
        raise ValueError("陳女士軀幹補丁超出已核對的遮罩")
    opaque = original[:, :, 3] > 127
    if not np.array_equal(result[opaque], original[opaque]):
        raise ValueError("陳女士既有不透明材料被改變")
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_chen_side.json").read_text(encoding="utf-8"))
    scale = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.array(point, float) * scale for name, point in spec["joints"].items()}
    candidate = Image.fromarray(result)
    before = part_transform(old, spec["parts"]["torso"], joints, scale)
    after = part_transform(candidate, spec["parts"]["torso"], joints, scale)
    if not all(np.array_equal(a, b) for a, b in zip(before, after)):
        raise ValueError("陳女士軀幹畫布、支點或取樣格改變")
    if sha(render_part(candidate, after, scale).tobytes()) != record["diffuse_rgba_sha256"]:
        raise ValueError("陳女士軀幹原生切件像素不同於已核對候選")
    # 驗證重建RGBA與固定批准PNG相同，再取批准原始bytes，不重新編碼PNG。
    payload = registered_layer_bytes({"torso": candidate}, HERE, record)["torso"]
    target = work / "overrides/refined/torso.png"
    if target.exists() and target.read_bytes() != payload:
        raise ValueError(f"陳女士已有不同的來源覆寫，保留並停止：{target}")
    write_registered_file(target, payload)
    print("陳女士軀幹來源：3009原圖像素；原畫布、支點及其他零件保持；既有相同輸出不改寫")


if __name__ == "__main__":
    main()
