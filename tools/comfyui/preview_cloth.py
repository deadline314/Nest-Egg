import sys
from PIL import Image, ImageEnhance
# preview_cloth.py out.png scale gain img.png [x_offset y0 y1 half_width]  -> zoom on the jacket of every pose in a rig_preview --cloth sheet
out, scale, gain, src = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
xo, y0, y1, hw = (int(v) for v in sys.argv[5:9]) if len(sys.argv) > 8 else (-10, 270, 450, 75)
im = Image.open(src).convert("RGB")
tiles = []
for i in range(6):
    cx = 140 + 200 * i + xo
    tiles.append(im.crop((cx - hw, y0, cx + hw, y1)).resize((hw * 2 * scale, (y1 - y0) * scale), Image.LANCZOS))
c = Image.new("RGB", (tiles[0].width * 6 + 50, tiles[0].height), (60, 60, 90))
for i, t in enumerate(tiles):
    c.paste(ImageEnhance.Brightness(t).enhance(gain), (i * (t.width + 10), 0))
c.save(out)
