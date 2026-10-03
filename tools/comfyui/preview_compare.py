import sys
from PIL import Image, ImageEnhance
# preview_compare.py out.png scale "x0,y0,x1,y1" a.png b.png [brighten]
out, scale, box = sys.argv[1], int(sys.argv[2]), tuple(map(int, sys.argv[3].split(",")))
files = sys.argv[4:6]; gain = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0
ims = [Image.open(f).convert("RGB").crop(box) for f in files]
w, h = ims[0].size
c = Image.new("RGB", (w * 2 * scale + 10, h * scale), (40, 40, 60))
for i, im in enumerate(ims):
    im = ImageEnhance.Brightness(im.resize((w * scale, h * scale), Image.LANCZOS)).enhance(gain)
    c.paste(im, (i * (w * scale + 10), 0))
c.save(out)
