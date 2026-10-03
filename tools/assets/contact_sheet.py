"""Build a contact sheet of rendered props (albedo row + normal row) for quick visual review.
Usage: python tools/assets/contact_sheet.py <dir with <name>.png and <name>_n.png> <out.png> [cell_height]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

src, out = Path(sys.argv[1]), Path(sys.argv[2])
ch = int(sys.argv[3]) if len(sys.argv) > 3 else 300
names = sorted(p.stem for p in src.glob("*.png") if not p.stem.endswith("_n"))
cells, x = [], 8
for n in names:
    im = Image.open(src / f"{n}.png").convert("RGBA")
    s = min(ch / im.height, 360 / im.width)
    cells.append((n, im.resize((max(1, int(im.width * s)), max(1, int(im.height * s)))),
                  Image.open(src / f"{n}_n.png").convert("RGBA").resize((max(1, int(im.width * s)), max(1, int(im.height * s))))))
per_row = 6
rows = [cells[i:i + per_row] for i in range(0, len(cells), per_row)]
row_w = [sum(c[1].width + 12 for c in r) + 8 for r in rows]
sheet = Image.new("RGB", (max(row_w), len(rows) * (ch * 2 + 56)), (26, 28, 40))
d = ImageDraw.Draw(sheet)
for ri, r in enumerate(rows):
    x, y = 8, ri * (ch * 2 + 56)
    for n, a, nm in r:
        d.text((x, y + 2), n, fill=(210, 210, 220))
        sheet.paste(a, (x, y + 18), a)
        sheet.paste(nm, (x, y + 18 + ch + 8), nm)
        x += a.width + 12
sheet.save(out)
print(out, sheet.size)
