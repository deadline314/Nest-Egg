"""Native-pixel part reviews on checker, light grey and dark grey; no source edits."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/parts-native-review"


def main():
    OUT.mkdir(exist_ok=True)
    records = []
    for group, directory in [("source", WORK / "07_refined"), ("runtime", ROOT / "art/characters/guest_zheng/parts")]:
        for file in sorted(directory.glob("*.png")):
            if file.stem.endswith("_n") or file.stem == "ownership":
                continue
            image = Image.open(file).convert("RGBA")
            box = image.getchannel("A").getbbox()
            assert box is not None
            box = (max(0, box[0] - 12), max(0, box[1] - 12), min(image.width, box[2] + 12), min(image.height, box[3] + 12))
            crop = image.crop(box)
            w, h = crop.size
            sheet = Image.new("RGB", (w * 3, h))
            for column, colour in enumerate([(140, 140, 140), (208, 210, 214), (32, 35, 42)]):
                background = Image.new("RGB", crop.size, colour)
                if column == 0:
                    draw = ImageDraw.Draw(background)
                    for y in range(0, h, 16):
                        for x in range(0, w, 16):
                            if (x // 16 + y // 16) % 2:
                                draw.rectangle((x, y, x + 15, y + 15), fill=(208, 208, 208))
                background.paste(crop, mask=crop.getchannel("A"))
                sheet.paste(background, (w * column, 0))
            output = OUT / (group + "-" + file.name)
            sheet.save(output)
            records.append({"file": file.relative_to(ROOT).as_posix(), "review": output.name,
                            "native_canvas": image.size, "crop_box": box, "pixel_scale": 1,
                            "background_order": ["checker16", "light208,210,214", "dark32,35,42"]})
    (OUT / "manifest.json").write_text(json.dumps(records, indent=2), encoding="utf8")
    print(len(records), "part reviews, three backgrounds each, native pixels without resizing")


if __name__ == "__main__":
    main()
