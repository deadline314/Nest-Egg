"""Native-sized source/runtime material sheets; alpha bbox crops never resample pixels."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/material-parts-native-v1"


def main():
    OUT.mkdir(exist_ok=False)
    records = []
    for name in ("hand", "torso", "pelvis", "leg_lower"):
        for kind, source in (("source", WORK / "07_refined" / (name + ".png")),
                             ("runtime", ROOT / "art/characters/guest_zheng/parts" / (name + ".png"))):
            image = Image.open(source)
            bbox = image.getchannel("A").getbbox()
            crop = image.crop(bbox)
            width, height = crop.size
            sheet = Image.new("RGB", (width * 3, height + 20))
            for column, background in enumerate(((144, 144, 144), (208, 210, 214), (32, 35, 42))):
                tile = Image.new("RGB", crop.size, background)
                tile.paste(crop, mask=crop.getchannel("A"))
                sheet.paste(tile, (width * column, 0))
            ImageDraw.Draw(sheet).text((0, height + 2), name + " / " + kind + " / native pixel scale 1", fill="white")
            target = OUT / (name + "-" + kind + ".png")
            sheet.save(target)
            records.append(dict(part=name, kind=kind, source=source.relative_to(ROOT).as_posix(),
                                source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                                native_crop=list(bbox), pixel_scale=1, sheet=target.name,
                                sheet_sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    (OUT / "manifest.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf8", newline="\n")
    print(len(records), "native pixel source/runtime sheets")


if __name__ == "__main__":
    main()
