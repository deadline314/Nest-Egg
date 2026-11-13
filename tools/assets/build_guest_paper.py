"""Build the explicitly geometric NE-267 paper tilt from retained unlettered paper art.

No model work and no changes to the source. All states fix the same real material
contact coordinate, so StagePropHold can follow the existing hand while it lays
the paper down. Parameters and native RGBA/hash receipts remain reproducible.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from depth_normals import depth_normal_map

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "assets_src/pipeline/guest_book_contacts.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    config = json.loads(CONFIG.read_text(encoding="utf8"))
    source = ROOT / config["source"]
    original = source.read_bytes()
    if sha(source) != config["source_sha256"]:
        raise ValueError("Retained paper source hash changed; stop before replacing derived states")
    image = Image.open(source)
    if image.mode != "RGBA" or list(image.size) != config["canvas"]:
        raise ValueError("Retained paper requires native 96x96 RGBA; no resize fallback")
    out = ROOT / config["output"]
    out.mkdir(parents=True, exist_ok=True)
    ax, ay = config["anchor"]
    premultiplied = image.convert("RGBa")
    report = dict(source=config["source"], source_sha256=sha(source), native_size=image.size,
                  generation="none: deterministic geometric derivative of existing project art",
                  config=config, config_sha256=sha(CONFIG), states=[])
    for index in range(1, config["states"] + 1):
        u = index / config["states"]
        sy = 1 + u * (config["final_vertical_scale"] - 1)
        shear = u * config["final_x_shear"]
        # Forward: x'=x+shear*(ay-y), y'=ay+sy*(y-ay); fixed material anchor.
        inverse = (1, shear / sy, -shear * ay / sy, 0, 1 / sy, -(1 - sy) * ay / sy)
        state = premultiplied.transform(image.size, Image.Transform.AFFINE, inverse,
                                        resample=Image.Resampling.BICUBIC).convert("RGBA")
        pixels = np.array(state)
        assert pixels[ay, ax, 3] >= 128, "the physical hold point left the paper"
        yy, xx = np.nonzero(pixels[:, :, 3] >= 128)
        file = out / f"zheng_slip_lay_{index}.png"
        state.save(file)
        normal = depth_normal_map(pixels.astype(np.float32) / 255, **config["normal"])
        normal_file = file.with_stem(file.stem + "_n")
        Image.fromarray(np.rint(normal * 255).astype(np.uint8)).save(normal_file)
        report["states"].append(dict(id=f"lay_{index}", path=file.relative_to(ROOT).as_posix(),
            sha256=sha(file), normal_sha256=sha(normal_file), vertical_scale=sy, x_shear=shear,
            inverse_affine=inverse, opaque_bbox_inclusive=[int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max())],
            material_bottom_pixel_centre=float(yy.max()) + .5, hold_point_alpha=int(pixels[ay, ax, 3])))
    assert source.read_bytes() == original
    target = ROOT / "assets_src/pipeline/guest_book_contacts-receipt.json"
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    # Apply the existing import policy only to these new contact textures; never
    # rewrite another worker's image imports while building this small unit.
    import texture_import
    texture_import.ART = out
    texture_import.apply_policy()
    print("built", len(report["states"]), "native RGBA geometric states; source unchanged")


if __name__ == "__main__":
    main()
