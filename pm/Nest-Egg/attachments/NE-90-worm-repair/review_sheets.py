"""Unscaled native crops of every +/-90 degree boundary frame; originals retained."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[4]
folder = root / 'pm/Nest-Egg/images/NE-90-worm-repair'
frames = sorted(folder.glob('boundary-frame*.png'), key=lambda p: int(p.stem.split('frame')[1]))
for batch in range(0, len(frames), 12):
    selected = frames[batch:batch + 12]
    sheet = Image.new('RGB', (3120, 630 * ((len(selected) + 2) // 3)), (60, 60, 60))
    for index, path in enumerate(selected):
        with Image.open(path) as native:
            crop = native.convert('RGB').crop((120, 100, 1160, 700))
        x, y = (index % 3) * 1040, (index // 3) * 630
        sheet.paste(crop, (x, y + 30))
        ImageDraw.Draw(sheet).text((x + 12, y + 10), path.stem, fill='white')
        crop.close()
    sheet.save(folder / f'boundary-native-crops-{batch // 12 + 1}.png')
    sheet.close()
print(len(frames), 'native boundary frames, no resampling')
