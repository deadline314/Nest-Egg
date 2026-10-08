"""Stack before/after screenshots side by side for review. Usage: python tools/assets/compare.py <before_dir> <after_dir> <out.png> <name> [name ...]
Names are file stems shared by both dirs once their trailing _<tag> is removed (e.g. spot_level_01_s1b)."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

before, after, out, names = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:]
def find(d, n):
    if (d / (n + ".png")).exists():
        return d / (n + ".png")
    hits = sorted(d.glob(f"{n}_*.png"))
    return hits[0] if hits else None
rows = []
for n in names:
    a, b = find(before, n), find(after, n)
    if a is None or b is None:
        print("missing", n); continue
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    row = Image.new("RGB", (ia.width + ib.width + 8, ia.height + 20), (30, 30, 36))
    row.paste(ia, (0, 20)); row.paste(ib, (ia.width + 8, 20))
    d = ImageDraw.Draw(row); d.text((6, 4), f"{n}   before", fill=(230, 230, 230)); d.text((ia.width + 14, 4), "after", fill=(230, 230, 230))
    rows.append(row)
sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)), (30, 30, 36))
y = 0
for r in rows:
    sheet.paste(r, (0, y)); y += r.height
sheet.save(out); print(out, sheet.size)
