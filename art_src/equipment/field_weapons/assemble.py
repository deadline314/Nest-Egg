"""Make the detachable assemblies from the approved field art and housing atlas."""
from argparse import ArgumentParser
from hashlib import sha256
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance
from split import housing_images, maps_for_firearm, read_json

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]
SLOTS = ("cell", "barrel", "rail")
APPEARANCE = (
    ("cell_ceramic", "cell_graphite"),
    ("sleeve_blue", "sleeve_silver"),
    ("rail_cyan", "rail_violet"),
)
SHEET_SIZE = (512, 512)
PAD = 2


def bounds(spec):
    x, y, width, height = spec
    return x, y, x + width, y + height


def tile(sheet, image, position):
    sheet.paste(image, position)
    return [*position, *image.size]


def save(project, output, sockets):
    atlas = Image.new("RGBA", SHEET_SIZE)
    normals = Image.new("RGB", SHEET_SIZE, (128, 128, 255))
    emission = Image.new("RGBA", SHEET_SIZE)
    metadata = read_json(SOURCE / "source.json")
    registration = read_json(SOURCE / "registration.json")
    with Image.open(SOURCE / "lab_housings.png") as source:
        expected = metadata["atlases"]["lab_housings"]
        if sha256((SOURCE / "lab_housings.png").read_bytes()).hexdigest() != expected["sha256"]:
            raise ValueError("Lab housing atlas contents changed")
        images = housing_images({"lab_housings": source.convert("RGBA")}, registration)
    parts = {}
    for i, (name, pair) in enumerate(zip(SLOTS, APPEARANCE)):
        parts[name] = []
        for variant, image_name in enumerate(pair):
            frame = images[image_name].resize((62, 30), Image.Resampling.LANCZOS)
            position = (2 + (i * 2 + variant) * 64, PAD)
            parts[name].append(tile(atlas, frame, position))
            tile(normals, maps_for_firearm(frame), position)
            pixels = np.asarray(frame, dtype=np.float32) / 255
            red, green, blue = (pixels[:, :, index] for index in range(3))
            cool = np.maximum(green, blue) - red
            pixels[:, :, 3] *= np.clip((cool - 0.17) * 3.8, 0, 1)
            pixels[:, :, 3] *= np.clip((np.maximum(green, blue) - 0.50) * 3.0, 0, 1)
            light = Image.fromarray(np.uint8(np.clip(pixels * 255 + 0.5, 0, 255)), "RGBA")
            tile(emission, light, position)

    guns = {}
    x, y, depth = PAD, 34, 0
    for name, config in sockets.items():
        art_dir = project / "art/weapons"
        body = Image.open(art_dir / f"{name}.png").convert("RGBA")
        normal = Image.open(art_dir / f"{name}_n.png").convert("RGB")
        glow = Image.open(art_dir / f"{name}_glow.png").convert("RGBA")
        # Leave the mount seam underneath each assembled part, and retain any non-overlapping body details.
        for slot in SLOTS:
            left, top, right, bottom = bounds(config[slot])
            if left < 0 or top < 0 or right > body.width or bottom > body.height:
                raise ValueError(f"{name}/{slot} goes past the drawing")
            opening = left + 1, top + 1, right - 1, bottom - 1
            if slot == "cell" and config["feed"] == "drop":
                body.paste((0, 0, 0, 0), opening)
            else:
                # The chassis, receiver and barrel keep a connected inner frame when a cover moves.
                internal = ImageEnhance.Brightness(body.crop(opening)).enhance(0.43)
                body.paste(internal, opening[:2])
            glow.paste((0, 0, 0, 0), opening)
            normal.paste((128, 128, 255), opening)
        if x + body.width + PAD > SHEET_SIZE[0]:
            y += depth + PAD
            x, depth = PAD, 0
        if y + body.height + PAD > SHEET_SIZE[1]:
            raise ValueError(f"Mechanical atlas is full at {name}")
        region = tile(atlas, body, (x, y))
        tile(normals, normal, (x, y))
        tile(emission, glow, (x, y))
        guns[name] = {"body": region, **config}
        depth = max(depth,body.height)
        x += body.width + PAD

    image_path = output / "art/weapons/modular/firearm_mechanisms.png"
    json_path = output / "data/weapon_art/firearm_mechanisms.json"
    for path in (image_path, json_path):
        path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(image_path, optimize=True)
    normals.save(image_path.with_stem(image_path.stem + "_n"), optimize=True)
    emission.save(image_path.with_stem(image_path.stem + "_glow"), optimize=True)
    json_path.write_text(json.dumps({"regions":parts,"guns":guns},indent=2)+"\n",encoding="utf-8")


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--out", type=Path, default=ROOT)
    options = parser.parse_args()
    # Support both the registered source and Windows UTF-8 tooling that adds a BOM.
    config = json.loads((SOURCE / "sockets.json").read_text(encoding="utf-8-sig"))
    save(options.project, options.out, config)
