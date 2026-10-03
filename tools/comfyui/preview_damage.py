import sys
from PIL import Image, ImageEnhance
# preview_damage.py out.png scale gain damage.png  -> the seven health stages of a rig_preview --damage sheet, side by side, big
out, scale, gain, src = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
im = Image.open(src).convert("RGB")
tiles = [im.crop((i * 180, 100, i * 180 + 180, 680)).resize((180 * scale, 580 * scale), Image.LANCZOS) for i in range(7)]
c = Image.new("RGB", (tiles[0].width * 7 + 60, tiles[0].height), (60, 60, 90))
for i, t in enumerate(tiles):
    c.paste(ImageEnhance.Brightness(t).enhance(gain), (i * (t.width + 10), 0))
c.save(out)
