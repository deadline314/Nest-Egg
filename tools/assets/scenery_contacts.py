"""Record the opaque bottom edge of each scenery sprite as normalized contact spans.

Run after changing environment props. Reads one image at a time; changes no art.
The last world pixel excludes wheels' transparent margins and trees' crowns.
"""
import json
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]

def main():
    contacts = {}
    for resource in sorted((ROOT / "data/environment").rglob("*.tres")):
        text = resource.read_text(encoding="utf-8")
        ident = re.search(r'^id = &"([^"]+)"', text, re.M)
        texture = re.search(r'^texture = "res://([^"]+\.png)"', text, re.M)
        size = re.search(r'^size = Vector2\([^,]+, ([^)]+)\)', text, re.M)
        if not (ident and texture and size):
            continue
        with Image.open(ROOT / texture[1]) as image:
            alpha = image.convert("RGBA").getchannel("A")
            bounds = alpha.getbbox()
            if bounds is None:
                raise ValueError(f"Empty scenery image: {texture[1]}")
            band = max(1, round(image.height / float(size[1])))
            strip = alpha.crop((0, bounds[3] - band, image.width, bounds[3]))
            pixels = strip.load()
            spans = []
            start = None
            for x in range(image.width + 1):
                opaque = x < image.width and any(pixels[x, y] >= 128 for y in range(band))
                if opaque and start is None:
                    start = x
                elif not opaque and start is not None:
                    if x - start > 2:
                        spans.append([round(start / image.width, 5), round(x / image.width, 5)])
                    start = None
            contacts[ident[1]] = {"spans": spans or [[0, 1]], "bottom_margin": round((image.height - bounds[3]) / image.height, 8),
                                 "bounds": [round(bounds[0]/image.width, 8), round(bounds[1]/image.height, 8), round(bounds[2]/image.width, 8), round(bounds[3]/image.height, 8)]}
    target = ROOT / "data/environment/scenery_contacts.json"
    target.write_text(json.dumps(contacts, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Recorded {len(contacts)} scenery footprints")
    walls = {}
    for texture in sorted((ROOT / "art/environment/facades").glob("*.png")):
        if "_glow" in texture.stem or texture.stem.endswith("_n"):
            continue
        with Image.open(texture) as image:
            alpha = image.getchannel("A")
            pixels = alpha.load()
            top = image.height
            # Roof ornaments and triangular gables do not constitute a full wall surface.
            for y in range(image.height - 1, -1, -1):
                if not all(pixels[x, y] >= 128 for x in range(image.width)):
                    break
                top = y
            walls["res://" + texture.relative_to(ROOT).as_posix()] = top / image.height
    target = ROOT / "data/environment/facade_wall_support.json"
    target.write_text(json.dumps(walls, indent=2) + "\n", encoding="utf-8")
    print(f"Recorded {len(walls)} facade opaque wall surfaces")

if __name__ == "__main__":
    main()
