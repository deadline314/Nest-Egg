"""Build dialogue portraits from retained adult guest source illustrations.

This is a portrait-only crop recipe, not character splitting or rig acceptance.
Validate the entire batch before replacing any runtime PNG. --check publishes nothing.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import os
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def build(spec_path: Path, check: bool):
    rows = json.loads(spec_path.read_text())
    pending = []
    for row in rows:
        source = (ROOT / row["source"]).resolve()
        output = (ROOT / row["output"]).resolve()
        if not source.is_relative_to(ROOT / "art_src/characters") or not output.is_relative_to(ROOT / "art/portraits") or output.suffix != ".png":
            raise ValueError(f"{row['id']}: invalid portrait source/output path")
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != row["sha256"]:
            raise ValueError(f"{source}: source SHA differs; existing portraits retained")
        with Image.open(source) as image:
            if image.mode != "RGBA" or list(image.size) != row["dimensions"]:
                raise ValueError(f"{source}: native RGBA dimensions differ")
            box = row["crop"]
            if len(box) != 4 or any(type(x) != int for x in box) or not (0 <= box[0] < box[2] <= image.width and 0 <= box[1] < box[3] <= image.height) or box[2] - box[0] != box[3] - box[1]:
                raise ValueError(f"{source}: crop must be an in-bounds native square")
            portrait = image.crop(box)
        # Same alpha cleanup floor as the existing character pipeline. No colour
        # fill, enlargement, head redraw or adoption of the generated full-body rig.
        portrait.putalpha(portrait.getchannel("A").point(lambda value: 0 if value < row["alpha_floor"] else value))
        if portrait.getchannel("A").getextrema()[1] < 250:
            raise ValueError(f"{source}: portrait has no opaque material")
        buffer = io.BytesIO();portrait.save(buffer, format="PNG")
        pending.append((output, buffer.getvalue()))
    for output, data in pending:
        if check:
            if not output.exists() or output.read_bytes() != data:
                raise ValueError(f"{output}: portrait is not the recorded source crop")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            temporary = output.with_suffix(".pending")
            temporary.write_bytes(data);os.replace(temporary, output)
            imported = output.with_suffix(".png.import")
            if not imported.exists():
                relative = output.relative_to(ROOT).as_posix()
                imported.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="res://' + relative + '"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\nprocess/size_limit=0\n')
        print(f"{output.relative_to(ROOT)}: {hashlib.sha256(data).hexdigest()}, exact native crop, no resize")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=HERE / "portraits.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(args.spec, args.check)
