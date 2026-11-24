from pathlib import Path
from hashlib import sha256
import json
from PIL import Image, ImageOps, ImageFilter
import sys

source_dir = Path(__file__).resolve().parent
src = source_dir / "atlas.png"
out = Path(sys.argv[1]) if len(sys.argv) > 1 else source_dir.parents[2] / "art/projectiles/projectile_heads.png"
if sha256(src.read_bytes()).hexdigest() != json.loads((source_dir / "source.json").read_bytes())["sha256"]:
    raise ValueError(f"Unexpected source atlas contents: {src}")
image = Image.open(src).convert("RGBA")
atlas=Image.new("RGBA",(128,64))
sizes=[(26,15), (28,10), (26,15), (20,20), (27,13), (28,9), (26,19), (27,17)]
w,h=image.size
for index,max_size in enumerate(sizes):
    column,row = index%2,index//2
    sprite=image.crop((column*w//2,row*h//4,(column+1)*w//2,(row+1)*h//4))
    matte=sprite.getchannel("A").point(lambda a: max(0,min(255,round((a-45)*1.52))))
    sprite.putalpha(matte)
    body=sprite.crop(matte.point(lambda a: 255 if a>128 else 0).getbbox())
    gray=ImageOps.grayscale(body).point(lambda x: min(255, max(22,round((x-80)*1.43))))
    red=Image.merge("RGBA", (gray,gray,gray,body.getchannel("A")))
    red=red.resize(max_size,Image.Resampling.LANCZOS)
    cell=Image.new("RGBA",(32,32))
    cell.alpha_composite(red,((32-red.width)//2,(32-red.height)//2))
    mask = cell.getchannel("A").filter(ImageFilter.MaxFilter(3)).point(lambda a: round(a*0.84))
    edge=Image.new("RGBA",cell.size,(21,22,27,0))
    edge.putalpha(mask)
    edge.alpha_composite(cell)
    assert edge.getchannel("A").getbbox()[0]>0
    atlas.paste(edge,(index%4*32,index//4*32))
out.parent.mkdir(parents=True,exist_ok=True)
atlas.save(out,optimize=True)
