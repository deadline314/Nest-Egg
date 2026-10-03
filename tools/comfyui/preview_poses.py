import sys
from PIL import Image, ImageEnhance
# preview_poses.py out.png scale gain img.png [img2.png]  -> eight pose crops from a rig_preview poses sheet (row per image)
out, scale, gain = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
rows = []
for f in sys.argv[4:]:
    im = Image.open(f).convert("RGB")
    tiles = [im.crop((i * 160, 20, i * 160 + 160, 345)).resize((160 * scale, 325 * scale), Image.LANCZOS) for i in range(8)]
    row = Image.new("RGB", (160 * scale * 8, 325 * scale))
    for i, t in enumerate(tiles):
        row.paste(ImageEnhance.Brightness(t).enhance(gain), (i * 160 * scale, 0))
    rows.append(row)
c = Image.new("RGB", (rows[0].width, sum(r.height for r in rows) + 8 * (len(rows) - 1)), (60, 60, 90))
y = 0
for r in rows:
    c.paste(r, (0, y)); y += r.height + 8
c.save(out)
