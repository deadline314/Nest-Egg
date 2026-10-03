"""Stack the frames of one enemy's death (from the enemy_vfx scenario with --times) into one strip.

    python tools/vfx_strip.py <folder> <tag> <enemy> <out.png> [crop x0 y0 x1 y1] [gain]
"""
import glob
import sys
from PIL import Image, ImageDraw, ImageEnhance

folder, tag, enemy, out = sys.argv[1:5]
box = tuple(int(v) for v in sys.argv[5:9]) if len(sys.argv) >= 9 else (300, 330, 700, 630)
gain = float(sys.argv[9]) if len(sys.argv) >= 10 else 1.6
files = sorted(glob.glob(f"{folder}/{tag}_{enemy}_death_*.png"))
w, h = box[2] - box[0], box[3] - box[1]
c = Image.new("RGB", (w * len(files), h + 18), (30, 30, 50))
d = ImageDraw.Draw(c)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").crop(box)
    c.paste(ImageEnhance.Brightness(im).enhance(gain), (i * w, 18))
    d.text((i * w + 4, 3), f"{int(f.rsplit('_', 1)[1][:-4]) / 100:.2f}s", fill=(255, 255, 0))
c.save(out)
print(c.size)
