"""Read-only HIGH factory AABA diagnostic. CPU controls never imply native acceptance."""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image

FORMATS = {14: ("<f2", 3), 15: ("<f2", 4), 10: ("<f4", 3), 11: ("<f4", 4)}
KEYS = ["A1", "A2", "B", "A3", "old-A", "old-B", "ui-old", "ui-white-new", "ui-white-old"]

def decode(data, row):
    assert row["hdr2d"] is True and row["mipmaps"] is False, "HDR/ordinary readback required"
    dtype, channels = FORMATS[row["format"]]
    expected = row["width"] * row["height"] * channels * np.dtype(dtype).itemsize
    assert len(data) == row["bytes"] == expected, "exact raw byte count"
    pixels = np.frombuffer(data, dtype=dtype).reshape(row["height"], row["width"], channels).astype(np.float64)
    assert np.isfinite(pixels).all(), "finite original HDR required"
    return pixels

def png_reference(pixels):
    rgb = pixels[..., :3]
    shown = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.maximum(rgb, 0) ** (1 / 2.4) - 0.055)
    alpha = np.clip(pixels[..., 3], 0, 1) if pixels.shape[2] == 4 else np.ones(rgb.shape[:2])
    return np.dstack((np.clip(shown, 0, 1), alpha))

def affine(values):
    assert len(values) == 6 and np.isfinite(values).all(), "actual finite affine matrix"
    a, b, c, d, x, y = values
    return np.array([[a, c, x], [b, d, y], [0, 0, 1]], dtype=float)


def projection_control(item):
    final, canvas, viewport, world, projection = (affine(item[key]) for key in ["final_matrix", "canvas_matrix", "viewport_matrix", "global_matrix", "projection_matrix"])
    assert np.allclose(final @ canvas, viewport, rtol=0, atol=1e-6), "final times actual item canvas must equal viewport transform"
    assert np.allclose(viewport @ world, projection, rtol=0, atol=1e-6), "actual physical projection must include item global transform"
    x, y, w, h = item["local_rect"]
    corners = projection @ np.array([[x, x+w, x+w, x], [y, y, y+h, y+h], [1, 1, 1, 1]])
    low, high = np.floor(corners[:2].min(axis=1)).astype(int), np.ceil(corners[:2].max(axis=1)).astype(int)
    assert list(item["roi"]) == [*low.tolist(), *(high-low).tolist()], "recorded full ROI must follow actual native projection"


def verify(directory):
    metadata = json.loads((directory / "capture.json").read_text(encoding="utf-8"))
    assert metadata["renderer"] == "forward_plus" and metadata["display"] != "headless", "native Forward+ required"
    assert "9070" in metadata["adapter"], "actual expected adapter witness required"
    assert metadata["quality"] == 2, "first gallery is HIGH only"
    assert metadata["world_light_range"] == [0, 0], "no widened world light layer"
    assert metadata["stage_light_range"] == [metadata["canvas_layer"]] * 2 and metadata["canvas_layer"] == 58, "actual independent stage canvas range"
    frames = metadata["frames"]
    assert [f["key"] for f in frames] == KEYS, "complete original nine-frame order"
    arrays, originals, encoded = {}, {}, []
    for row in frames:
        assert [row["width"], row["height"]] == row["window_size"] == [1280, 720] and row["window_mode"] == 0, "actual windowed native size without resize"
        assert row["raw_rid_image_size"] == [row["width"], row["height"]] == [1280, 720], "same original readback Image owns raw dimensions"
        declared = row["texture_declared_size_metadata_only"]
        assert len(declared) == 2 and all(isinstance(v, int) and v > 0 for v in declared), "declared texture size recorded without equality gate"
        raw = (directory / row["raw"]).read_bytes()
        assert row["readback_supported"] is True, "actual format supported before PNG conversion"
        assert row["ui_complete"] is True and row["ui_frame_alpha"] == 1.0, "actual readable UI after natural portrait reveal"
        assert row["ui_text_mode"] == (-1 if row["key"] in ["ui-old", "ui-white-old"] else 1), "actual UI material control"
        pixels = decode(raw, row)
        image = Image.open(directory / row["png"])
        assert image.format == "PNG", "actual PNG format"
        shown = np.asarray(image.convert("RGBA"), dtype=np.float64) / 255
        assert shown.shape[:2] == pixels.shape[:2], "PNG native dimensions"
        error = float(np.max(np.abs(shown - png_reference(pixels))))
        assert error <= 1 / 255 + 0.00001, (row["key"], "canonical gamma before quantization", error)
        originals[row["key"]] = raw
        arrays[row["key"]] = pixels[..., :3]
        encoded.append({"key": row["key"], "max_png_error": error})
        assert len(row["body_materials"]) == 8, "all eight real physical factories"
        if row["key"].startswith("old-"):
            assert all(x["light_mode"] == 1 for x in row["body_materials"]), "legacy unshaded material control actually applied"
        else:
            assert all(x["material_id"] == 0 for x in row["body_materials"]), "ordinary reflective material actually applied"
    assert originals["A1"] == originals["A2"] == originals["A3"], "original and restored raw must match without relaxing ULP"
    assert originals["old-A"] == originals["old-B"], "legacy all-unshaded light-direction negative must remain constant"
    ui_rois = [tuple(row["ui_rect"]) for row in frames]
    assert len(set(ui_rois)) == 1, "same original UI projection in every control"
    x, y, w, h = ui_rois[0]
    assert w > 0 and h > 0 and x >= 0 and y >= 0 and x + w <= 1280 and y + h <= 720, "full UI ROI in native frame"
    shown = arrays["A3"][y:y+h, x:x+w]
    old = arrays["ui-old"][y:y+h, x:x+w]
    assert np.any(shown != old), "old ordinary UI under the SAME dark stage must reproduce response"
    assert originals["ui-white-new"] == originals["ui-white-old"], "white ambient and lights off must retain exact original UI output"
    assert frames[-1]["stage_ambient"] == frames[-2]["stage_ambient"] == [1, 1, 1, 1]
    assert frames[-1]["stage_light_enabled"] is False and frames[-2]["stage_light_enabled"] is False
    assert all(row["draw_frame"] > frames[i-1]["draw_frame"] for i,row in enumerate(frames) if i)
    results = []
    objects = metadata["objects"]
    assert len(objects) == 9 and len({x["id"] for x in objects}) == 9, "all physical and baked controls recorded"
    for item in objects:
        projection_control(item)
        assert item["canvas_layer"] == (58 if item["id"].startswith("ch1_") or item["id"] == "baked-control" else 0), "actual drawable canvas layer"
        x, y, width, height = item["roi"]
        assert all(isinstance(v, int) for v in item["roi"]), "integer physical ROI"
        assert width > 0 and height > 0 and x >= 0 and y >= 0 and x + width <= 1280 and y + height <= 720, "complete physical ROI inside native frame"
        a = arrays["A1"][y:y + height, x:x + width]
        b = arrays["B"][y:y + height, x:x + width]
        changed = int(np.count_nonzero(np.any(a != b, axis=2)))
        if item["id"] == "baked-control":
            assert changed == 0, "complete baked source must not be relit"
        else:
            assert changed > 0, (item["id"], "actual light response absent")
        if item["id"].startswith("ch1_"):
            assert item["texture_class"] == "CanvasTexture" and item["normal_path"].endswith("_n.png"), "HIGH physical stage retains its real normal"
        results.append({"id": item["id"], "roi": item["roi"], "changed_pixels": changed})
    return {"scope": "HIGH factory light-direction response only, not visual approval or complete ticket", "exact_raw_AABA": True, "legacy_negative_constant": True, "same_canvas_UI_negative_reproduced": True, "white_UI_exact": True, "objects": results, "png": encoded}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print(json.dumps(verify(parser.parse_args().directory), indent=2))
