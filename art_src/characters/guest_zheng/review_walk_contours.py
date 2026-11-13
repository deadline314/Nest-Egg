"""Diagnostic source-region contact sheets; never edits or scales an asset."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

WORK = Path(__file__).resolve().parent
folder = WORK / "repair_candidates/walk-contours-v2"
records = [record for record in json.loads((folder / "candidates.json").read_text(encoding="utf8"))["candidates"]
           if record["radius_source_pixels"] == 2]
for record in records:
    name = record["part"]
    x0, y0, x1, y1 = record["native_source_box"]
    region = (x0 - 4, y0 - 4, x1 + 4, y1 + 4)
    images = [Image.open(folder / (name + "-original-source.png")).convert("RGBA"),
              Image.open(folder / "radius-2" / (name + "-source.png")).convert("RGBA")]
    row_height = (region[3]-region[1])*6+30
    sheet = Image.new("RGB", (780, 38+3*row_height), "#c8c8c8")
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 8), name + " bounded source alpha repair; diagnostic 6x nearest crop; NOT a native screenshot", fill="black")
    for row, background in enumerate(["#ffffff", "#000000", "#d82a8c"]):
        for column, image in enumerate(images):
            crop = image.crop(region)
            backing = Image.new("RGBA", crop.size, background)
            backing.alpha_composite(crop)
            preview = backing.convert("RGB").resize((crop.width * 6, crop.height * 6), Image.Resampling.NEAREST)
            x, y = column * 390 + 10, row * row_height + 38
            # Native source scale is identical on both panels; crop is only a review derivative.
            sheet.paste(preview, (x, y))
            draw.text((column * 390 + 235, y + 6), "original" if column == 0 else "radius2 candidate", fill="black")
    sheet.save(folder / (name + "-three-backgrounds.png"))
print("3 bounded source-region contact sheets; live sources unchanged")
